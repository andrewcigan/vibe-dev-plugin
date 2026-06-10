#!/bin/bash
# Vibe Dev v6 — PostToolUse dispatcher (точка входа на событие PostToolUse).
#
# ⚠️ Живая модель событий (проверка 2026-06-10, движок 2.1.170): PostToolUse для Bash
# приходит НЕ на всех командах, и полей tool_response.exit_code/success НЕТ:
#   - падение С ВЫВОДОМ (stdout или stderr) -> события НЕТ вообще;
#   - тихое падение (exit!=0 без вывода)    -> событие ЕСТЬ, в tool_response появляется
#     returnCodeInterpretation ("Condition is false" и т.п.) — признак не-успеха;
#   - чистый успех                          -> событие есть, returnCodeInterpretation нет.
# Поэтому:
#   Bash: чистый успех (нет interrupted и нет returnCodeInterpretation) -> СБРОС счётчика
#         повторов; secret-mask по .tool_response.stdout — на любом пришедшем событии.
#   Edit/Write/MultiEdit -> сброс счётчика повторов (структурное изменение = прогресс).
# Инкремент счётчика повторов живёт в PreToolUse-диспетчере (приходит на каждый запуск).
#
# warn/inject (не block — PostToolUse не может отменить уже выполненный инструмент). Активен
# standard,strict; minimal — off.

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
    # Чистый успех = нет interrupted (^C) и нет returnCodeInterpretation (тихое падение
    # exit!=0 без вывода) -> сброс счётчика повторов.
    INTERRUPTED="$(hook_field '.tool_response.interrupted')"
    RCI="$(hook_field '.tool_response.returnCodeInterpretation')"
    if [ "$INTERRUPTED" != "true" ] && [ -z "$RCI" ]; then
      rm -f "$CWD/.harness/bash-repeat-state" 2>/dev/null
    fi
    # secret-mask (F8): живой токен в выводе -> updatedToolOutput (маска) + additionalContext
    # (предупреждение). Живая проверка 2026-06-10 (2.1.170): updatedToolOutput движком
    # ИГНОРИРУЕТСЯ (вывод у модели остаётся как был — safe-деградация), поэтому рабочий канал —
    # additionalContext: громкое предупреждение «не переиспользуй литерал, предложи ротацию».
    # Оба поля шлём в одном объекте: поддержит будущий движок маску — включится сама.
    MASKED="$(HOOK_PAYLOAD="$HOOK_INPUT" hook_run_check "$CWD" "secret-mask" text "$ROOT/hooks/checks/secret-mask-output.sh" "$CWD")"
    if [ -n "$(printf '%s' "$MASKED" | tr -d '[:space:]')" ]; then
      case "$MASKED" in
        "⚠️ сторож"*) hook_emit_context "PostToolUse" "$MASKED" ;;  # краш чекера -> предупреждение
        *)
          WARN_TEXT="⚠️ Vibe Dev (secret-mask): в выводе команды был ЖИВОЙ токен/ключ. Не печатай и не переиспользуй его литералом — обращайся только как \$ИМЯ_ПЕРЕМЕННОЙ из .env. Токен уже засветился в контексте — предложи пользователю ротацию."
          jq -cn --arg o "$MASKED" --arg c "$WARN_TEXT" \
            '{hookSpecificOutput:{hookEventName:"PostToolUse", updatedToolOutput:$o, additionalContext:$c}}'
          exit 0
          ;;
      esac
    fi
    ;;
  Edit|Write|MultiEdit)
    # Структурное изменение -> сброс счётчика повторов (это прогресс, не слепой retry).
    rm -f "$CWD/.harness/bash-repeat-state" 2>/dev/null
    ;;
esac
hook_emit_pass
