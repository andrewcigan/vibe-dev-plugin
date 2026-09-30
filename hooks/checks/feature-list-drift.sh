#!/bin/bash
# Второй рубеж: журнал фич изменился мимо record-change (v9 F1.3).
#
# ЗАЧЕМ ОТДЕЛЬНО ОТ ДЕТЕКТОРА. Первый рубеж распознаёт намерение по тексту команды и потому
# принципиально неполон: любую форму записи предугадать нельзя, и прошлые провалы были ровно
# такими — перехват по списку команд обходился переименованием файла или интерпретатором.
# Этот рубеж не смотрит на команду вовсе: он сравнивает СОСТОЯНИЕ файла до и после.
#
# Не может блокировать (действие уже выполнено) — поэтому громко помечает и пишет в журнал
# срабатываний. Молчаливое расхождение состояния — то, чего быть не должно.
#
# Аргументы: $1=cwd, $2=фаза (before|after). Payload в HOOK_PAYLOAD.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/../lib/guard-prelude.sh"
guard_require_tools jq
CWD="${1:-$PWD}"; PHASE="${2:-after}"; TAB="$(printf '\t')"
# Корень плагина — от расположения сторожа: писатель истории живёт в плагине, не в проекте (v9.0.3).
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FL="$CWD/feature_list.json"
SNAP="$CWD/.harness/fl-hash"
[ -f "$FL" ] || guard_done

hash_of() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }

if [ "$PHASE" = "before" ]; then
  mkdir -p "$CWD/.harness" 2>/dev/null
  hash_of "$FL" > "$SNAP" 2>/dev/null
  guard_done
fi

# Фаза after: сверяем.
[ -f "$SNAP" ] || guard_done
BEFORE="$(cat "$SNAP" 2>/dev/null)"
NOW="$(hash_of "$FL")"
[ -n "$BEFORE" ] && [ -n "$NOW" ] || guard_done
if [ "$BEFORE" != "$NOW" ]; then
  CMD="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  case "$CMD" in
    *record-change.sh*|*archive-features.sh*|*migrate-provenance.sh*|*upgrade-project.sh*|*patch-projects.sh*)
      hash_of "$FL" > "$SNAP" 2>/dev/null; guard_done ;;
  esac
  hash_of "$FL" > "$SNAP" 2>/dev/null
  printf 'WARN%s%s\n' "$TAB" "Журнал фич изменился командой оболочки, мимо писателя истории: событие не записано, новое состояние и доказательство никто не проверил. Если менялся статус — верни как было и поставь его правкой файла (в профилях standard и strict там проверяются состояние и доказательство). Если менялось требование — верни и проведи писателем истории плагина (формат события — в начале его скрипта). Если правка техническая (форматирование, слияние), скажи об этом пользователю прямо, чтобы это не выглядело закрытой фичей. Команда: printf '%s' '<событие JSON>' | bash \"$PLUGIN_ROOT/scripts/record-change.sh\" --project \"$CWD\""
fi
guard_done
