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
  printf 'WARN%sЖурнал фич изменился командой оболочки, минуя record-change.sh: история изменения не записана и переход состояния не проверен. Если статус фичи менялся — верни как было и проведи через record-change.sh; если правка техническая (форматирование, слияние), скажи об этом пользователю прямо, чтобы это не выглядело закрытой фичей.\n' "$TAB"
fi
guard_done
