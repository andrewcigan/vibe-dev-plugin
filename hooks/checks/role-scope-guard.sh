#!/bin/bash
# Архитектурная роль не пишет код (v9 F3.2).
#
# ЗАЧЕМ. Решение владельца: верхний уровень (архитектура, план, критика, аудит) идёт на
# Fable 5.1 и КОДА НЕ ПИШЕТ; код начинается только когда всё расписано детально, и пишет его
# Opus 5. Без замка это пожелание: роль с доступом к оболочке пишет файл перенаправлением,
# и запрет инструментов правки её не останавливает — так в предыдущей версии шесть «только
# читающих» ролей фактически могли писать.
#
# ЧТО ДЕЛАЕТ. Смотрит, кто вызвал инструмент (движок сообщает тип роли в payload). Если это
# архитектурная роль и запись идёт в файл кода — block. Документы, планы, разметка разрешены:
# продукт архитектора — документ.
#
# ЧЕСТНАЯ ГРАНИЦА. Если движок не сообщил тип роли (вызов из главной сессии), сторож молчит:
# правило про роли, а не про человека за клавиатурой.
#
# Аргументы: $1=cwd. Payload в HOOK_PAYLOAD. Печатает "BLOCK\tmsg", пусто = ОК.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/../lib/guard-prelude.sh"
guard_require_tools jq
. "$(dirname "${BASH_SOURCE[0]}")/../lib/write-detect.sh"
CWD="${1:-$PWD}"; TAB="$(printf '\t')"

AGENT="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.agent_type // empty' 2>/dev/null)"
[ -n "$AGENT" ] || guard_done
AGENT="${AGENT#vibe-dev:}"

# Роли верхнего уровня: их продукт — суждение и документ, не код.
case "$AGENT" in
  architect|dev-planner|stack-advisor|business-interviewer|idea-generator|idea-critic|\
  data-model-reviewer|user-perspective-critic|stage-verifier|evaluator-agent|design-handoff-builder) : ;;
  *) guard_done ;;
esac

TOOL="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_name // empty' 2>/dev/null)"
CODE_EXT='\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|java|kt|rb|php|swift|c|h|cpp|cs|sql|sh|bash|vue|svelte)$'

TARGET=""
case "$TOOL" in
  Write|Edit|MultiEdit|NotebookEdit)
    TARGET="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
    printf '%s' "$TARGET" | grep -qE "$CODE_EXT" 2>/dev/null || guard_done ;;
  Bash)
    CMD="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    [ -n "$CMD" ] || guard_done
    # Запись в файл кода командой оболочки — тот же запрет, иначе замок обходится одной строкой.
    cmd_writes_to "$CMD" "[^[:space:]]*\.(ts|tsx|js|jsx|py|go|rs|java|rb|php|c|cpp|cs|sql|sh)" || guard_done
    TARGET="$CMD" ;;
  *) guard_done ;;
esac

printf 'BLOCK%sРоль «%s» работает на стадии замысла: её продукт — решение и документ, а не код. Написание кода начинается отдельным шагом, когда решение расписано детально, и делает это роль-исполнитель. Зафиксируй решение в документе (docs/, план, спецификация) и передай работу дальше.\n' "$TAB" "$AGENT"
guard_done
