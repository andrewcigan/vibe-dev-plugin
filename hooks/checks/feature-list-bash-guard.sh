#!/bin/bash
# Журнал фич правится только через record-change (v9 F1.3).
#
# ЗАЧЕМ. Сторож переходов состояний (state-transition) видит вносимое содержимое при Write и
# Edit — и не видит записи через bash. Дыра подтверждалась дважды независимыми проверками:
# агент, которому запретили менять статус фичи, менял его командой оболочки, и запись
# проходила как обычная работа с файлами.
#
# ЧТО ДЕЛАЕТ. На Bash: команда пишет в feature_list.json → block с объяснением, чем писать
# вместо этого. Первый рубеж; второй — сверка состояния файла после выполнения.
#
# Аргументы: $1=cwd. Payload в HOOK_PAYLOAD. Печатает "BLOCK\tmsg", пусто = ОК.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/../lib/guard-prelude.sh"
guard_require_tools jq
. "$(dirname "${BASH_SOURCE[0]}")/../lib/write-detect.sh"
CWD="${1:-$PWD}"; TAB="$(printf '\t')"
# Писатель истории живёт в плагине, а не в проекте: подсказка «scripts/record-change.sh» в проекте
# не исполнялась, и проект написал собственного писателя, который голову истории не ведёт
# (v9.0.3). Корень плагина — от расположения самого сторожа (hooks/checks → два уровня вверх),
# как в journal-size-probe.sh.
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

TOOL="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_name // empty' 2>/dev/null)"
[ "$TOOL" = "Bash" ] || guard_done
CMD="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$CMD" ] || guard_done

# Скрипты самого харнеса — законный путь записи, их не трогаем.
case "$CMD" in
  *record-change.sh*|*archive-features.sh*|*migrate-provenance.sh*|*upgrade-project.sh*|*patch-projects.sh*) guard_done ;;
esac
# Чтение — не запись.
case "$CMD" in
  cat\ *|less\ *|head\ *|tail\ *|grep\ *|wc\ *) guard_done ;;
esac

# Охраняем журнал СВОЕГО проекта. Запись по абсолютному пути вне корня (чужой репозиторий,
# тестовая песочница) — не наша забота: за выход за границы отвечает folder-scope.
FOREIGN=no
if printf '%s' "$CMD" | grep -qE "/[^[:space:]\"']*feature_list\.json" 2>/dev/null; then
  printf '%s' "$CMD" | grep -qF "$CWD/feature_list.json" 2>/dev/null || FOREIGN=yes
fi
if [ "$FOREIGN" = "no" ] && cmd_writes_to "$CMD" "feature_list\.json"; then
  # Писатель истории переход состояния НЕ проверяет (он пишет событие и голову) — проверяет
  # сторож переходов при правке файла. Поэтому статус ведём туда, требование — к писателю.
  printf 'BLOCK%s%s\n' "$TAB" "Журнал фич (feature_list.json) командой оболочки не пишется: такая запись минует сторожа состояния (он видит правку файла, а не команду) и не оставляет истории — статус фичи можно поставить в «работает», не предъявив доказательства. Статус и технические поля меняй правкой файла: в профилях standard и strict там проверяются новое состояние и доказательство. Требование (название, описание, размер, инвариант, отмена или замена) — писателем истории плагина: он пишет событие в журнал истории и голову синхронно, переход состояния не проверяет; формат события — в начале его скрипта. Посмотреть — cat, head, grep (jq с именем журнала считается записью: читай cat feature_list.json | jq …). Команда: printf '%s' '<событие JSON>' | bash \"$PLUGIN_ROOT/scripts/record-change.sh\" --project \"$CWD\""
fi
guard_done
