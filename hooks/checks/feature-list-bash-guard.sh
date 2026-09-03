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
  printf 'BLOCK%sЖурнал фич (feature_list.json) меняется только через record-change.sh — он ведёт историю изменений и проверяет переход состояния. Прямая запись командой оболочки обходит обе проверки: статус фичи можно поставить в «работает», не предъявив доказательства. Нужно изменить фичу — вызови scripts/record-change.sh; нужно посмотреть — cat/jq на чтение не блокируются.\n' "$TAB"
fi
guard_done
