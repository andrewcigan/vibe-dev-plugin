#!/bin/bash
# Vibe Dev v6.2 — closing-mode gate (F7; П6 аудита: «закрой сессию» -> агент начал кодить,
# пользователь: «Стоп! Что ты делаешь?… никакой код не пиши»).
#
# Маркер .harness/locks/closing-mode ставит UserPromptSubmit-диспетчер при детекте сигнала
# завершения (handoff-reminder), снимает — следующий промпт БЕЗ сигнала (инструкция
# пользователя главнее; закрывает FP «на сегодня всё, только поправь кнопку»).
# Пока маркер стоит — деградация прав (паттерн auto mode «вход в режим выкидывает опасные
# права»): запись только в state-файлы, Bash — только git/read-only/скрипты плагина.
#
# Аргументы: $1=cwd. Payload в HOOK_PAYLOAD. Печатает "BLOCK\tmsg", пусто = ОК. exit 0.

set -u
CWD="${1:-$PWD}"
TAB="$(printf '\t')"

[ -f "$CWD/.harness/locks/closing-mode" ] || exit 0

TOOL="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_name // empty' 2>/dev/null)"

REMEDIATION="Идёт закрытие сессии (режим closing): фиксируй состояние в файлы, НЕ разрабатывай. Новую работу — строкой в backlog (feature_list.json) и/или SESSION.md «NEXT». Если пользователь действительно просит продолжить работу — режим снимется его следующим сообщением без слов закрытия."

# Файл относится к state-набору закрытия?
is_state_file() {
  case "$1" in
    *SESSION.md|*MEMORY.md|*feature_list.json|*error-journal*|*/memory/*|*.session-state/*|\
    */docs/retrospectives/*|*/docs/decisions/*|*.harness/*|*domain-rules.yaml|*CLAUDE.md|*AGENTS.md)
      return 0 ;;
    *) return 1 ;;
  esac
}

case "$TOOL" in
  Write|Edit|MultiEdit|NotebookEdit)
    FILE="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)"
    if [ -n "$FILE" ] && ! is_state_file "$FILE"; then
      printf 'BLOCK%sЗапись в «%s» во время закрытия сессии. %s\n' "$TAB" "$FILE" "$REMEDIATION"
    fi
    ;;
  Bash)
    CMD="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    [ -z "$CMD" ] && exit 0
    # Разрешено: git, read-only, скрипты плагина (end-session.sh и пр.).
    if printf '%s' "$CMD" | grep -qE '(^|[;&|][[:space:]]*)(git|ls|cat|head|tail|grep|find|wc|pwd|date|echo[[:space:]][^>]*$|bash[[:space:]][^;&|]*scripts/(end-session|install-precommit|upgrade-project)\.sh)' 2>/dev/null \
       && ! printf '%s' "$CMD" | grep -qE '(npm|pnpm|yarn|pip3?|cargo|make|pytest|tsc|node[[:space:]]|python3?[[:space:]])' 2>/dev/null \
       && ! printf '%s' "$CMD" | grep -qE '>>?[[:space:]]*[^[:space:]]*(src/|app/|lib/|components/)' 2>/dev/null; then
      exit 0
    fi
    # Явная разработка/сборка/тесты или запись в код -> block.
    if printf '%s' "$CMD" | grep -qE '(npm|pnpm|yarn|pip3?|cargo|make|pytest|tsc)([[:space:]]|$)|>>?[[:space:]]*[^[:space:]]*(src/|app/|lib/|components/)|node[[:space:]]+[^-]|python3?[[:space:]]+[^-]' 2>/dev/null; then
      printf 'BLOCK%sКоманда разработки/сборки во время закрытия сессии: %.80s… %s\n' "$TAB" "$CMD" "$REMEDIATION"
    fi
    ;;
esac
exit 0
