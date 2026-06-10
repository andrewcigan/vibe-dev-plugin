#!/bin/bash
# Vibe Dev v6.2 — защита lock-маркеров (F6; общий lock-паттерн, переиспользуют F7/wave).
#
# `.harness/locks/*` — маркеры согласия/пропуска (research-skipped, closing-mode, wave-arming).
# Их пишут ТОЛЬКО хуки по явной фразе пользователя — иначе «ставится по явной фразе» было бы
# просьбой к агенту, а агент и есть нарушитель. Здесь блокируем ЗАПИСЬ агентом:
#   - Write/Edit/MultiEdit с file_path внутри .harness/locks/
#   - Bash с очевидной записью (>, >>, tee, touch, cp/mv в .harness/locks/)
# Удаление (rm) НЕ блокируем: снятие маркера двигает систему в СТРОГУЮ сторону (безопасно).
# Честная граница: экзотический Bash-обход (printf | dd ...) не ловим — threat model
# «агент ошибается пассивно», не «активная ложь».
#
# Аргументы: $1=cwd. Payload в HOOK_PAYLOAD. Печатает "BLOCK\tmsg", пусто = ОК. exit 0.

set -u
CWD="${1:-$PWD}"
TAB="$(printf '\t')"

TOOL="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_name // empty' 2>/dev/null)"

MSG="Маркеры .harness/locks/* пишут ТОЛЬКО хуки по явной фразе пользователя (lock-паттерн): скажи пользователю, какая фраза нужна (например, «пропусти рисёрч»), и хук поставит маркер сам. Снять маркер (rm) можно — это безопасное направление."

case "$TOOL" in
  Write|Edit|MultiEdit)
    FILE="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
    case "$FILE" in
      */.harness/locks/*|.harness/locks/*)
        printf 'BLOCK%s%s\n' "$TAB" "$MSG"
        ;;
    esac
    ;;
  Bash)
    CMD="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    if printf '%s' "$CMD" | grep -qE '(>>?|tee|touch|cp |mv )[^|;&]*\.harness/locks/' 2>/dev/null; then
      printf 'BLOCK%s%s\n' "$TAB" "$MSG"
    fi
    ;;
esac
exit 0
