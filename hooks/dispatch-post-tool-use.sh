#!/bin/bash
# Vibe Dev v6 — PostToolUse dispatcher (точка входа на событие PostToolUse). Анти-залипание №2.
#
# Поток: stdin JSON -> guard (vibe-проект?) -> профиль -> роутинг по tool_name:
#   Bash               -> bash-repeat-counter (счётчик падающих повторов) -> inject или pass.
#   Edit/Write/MultiEdit -> сброс счётчика повторов (структурное изменение = прогресс, не retry).
#
# warn/inject (не block — PostToolUse не может отменить уже выполненный инструмент). Активен
# standard,strict; minimal — off. Контракт PostToolUse: code.claude.com/docs/en/hooks
# (tool_response.exit_code/success в payload; additionalContext на exit 0 идёт в контекст модели).

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/hook-io.sh"

hook_read_stdin
CWD="$(hook_field '.cwd')"
[ -z "$CWD" ] && CWD="$PWD"

# Guard: только vibe-target-проекты.
hook_is_vibe_project "$CWD" || hook_emit_pass

PROFILE="$(hook_profile "$CWD")"
ROOT="$(hook_plugin_root)"

# Активен только в standard,strict.
profile_in "standard,strict" "$PROFILE" || hook_emit_pass

TOOL="$(hook_field '.tool_name')"
case "$TOOL" in
  Bash)
    NUDGE="$(HOOK_PAYLOAD="$HOOK_INPUT" bash "$ROOT/hooks/checks/bash-repeat-counter.sh" "$CWD" 2>/dev/null)"
    if [ -n "$(printf '%s' "$NUDGE" | tr -d '[:space:]')" ]; then
      hook_emit_context "PostToolUse" "$NUDGE"
    fi
    ;;
  Edit|Write|MultiEdit)
    # Структурное изменение -> сброс счётчика повторов (это прогресс, не слепой retry).
    rm -f "$CWD/.harness/bash-repeat-state" 2>/dev/null
    ;;
esac
hook_emit_pass
