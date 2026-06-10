#!/bin/bash
# Vibe Dev v6.2 — тест closing-mode (F7; П6 аудита: «закрой сессию» -> агент начал кодить).
#
# Контракты:
#   - сигнал завершения в промпте -> UserPromptSubmit ставит .harness/locks/closing-mode;
#   - в режиме: запись вне state-файлов -> BLOCK; state-файлы (SESSION/feature_list/memory) -> pass;
#     Bash разработки (npm/pytest/redirect в src) -> BLOCK; git/read-only -> pass;
#   - следующий промпт БЕЗ сигнала -> режим снят (инструкция пользователя главнее).
#
# Запуск: bash tests/hooks/test-closing-mode.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PRE="$PLUGIN_ROOT/hooks/dispatch-pre-tool-use.sh"
UP="$PLUGIN_ROOT/hooks/dispatch-user-prompt.sh"
PASS=0; FAIL=0

unset VIBE_DEV_PROFILE CLAUDE_PLUGIN_ROOT HOOK_PAYLOAD 2>/dev/null || true

assert_contains() {
  if printf '%s' "$2" | grep -q -- "$3"; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s\n     ожидал: %s\n     получил: %s\n' "$1" "$3" "$2"; fi
}
assert_not_contains() {
  if printf '%s' "$2" | grep -q -- "$3"; then FAIL=$((FAIL+1)); printf '  FAIL %s (НЕ ожидал: %s)\n     получил: %s\n' "$1" "$3" "$2"
  else PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; fi
}
assert_file() { if [ -f "$2" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL %s (файл должен существовать: %s)\n' "$1" "$2"; fi; }
assert_absent() { if [ ! -f "$2" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL %s (файла быть не должно: %s)\n' "$1" "$2"; fi; }

PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness"
echo "6.0" > "$PROJ/.harness/engine-version"; echo strict > "$PROJ/.harness/profile"

up()    { jq -cn --arg cwd "$PROJ" --arg p "$1" '{hook_event_name:"UserPromptSubmit",cwd:$cwd,prompt:$p}' | bash "$UP"; }
write() { jq -cn --arg cwd "$PROJ" --arg fp "$1" '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Write",tool_input:{file_path:$fp,content:"x"}}' | bash "$PRE"; }
bashcmd() { jq -cn --arg cwd "$PROJ" --arg c "$1" '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Bash",tool_input:{command:$c}}' | bash "$PRE"; }

echo "Closing-mode (F7) — сценарии:"

# 1. Сигнал завершения ставит режим
OUT="$(up "закрываем, на сегодня всё")"
assert_file "1. «закрываем» -> маркер closing-mode" "$PROJ/.harness/locks/closing-mode"

# 2. В режиме: запись кода -> BLOCK
OUT="$(write "$PROJ/src/app.py")"
assert_contains "2a. Write src/app.py -> deny" "$OUT" '"permissionDecision":"deny"'
assert_contains "2b. remediation: в backlog" "$OUT" "backlog"

# 3. State-файлы разрешены
OUT="$(write "$PROJ/SESSION.md")"
assert_not_contains "3a. SESSION.md -> pass" "$OUT" '"permissionDecision":"deny"'
OUT="$(write "$PROJ/memory/feedback_x.md")"
assert_not_contains "3b. memory/ -> pass" "$OUT" '"permissionDecision":"deny"'
# feature_list — валидным JSON (иначе state-transition правомерно заблокирует битый контент)
OUT="$(jq -cn --arg cwd "$PROJ" --arg fp "$PROJ/feature_list.json" \
  '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Write",tool_input:{file_path:$fp,content:"{\"features\":{}}"}}' | bash "$PRE")"
assert_not_contains "3c. feature_list.json -> pass (фиксация backlog)" "$OUT" '"permissionDecision":"deny"'

# 4. Bash: разработка -> BLOCK; git/read-only -> pass
OUT="$(bashcmd "npm run build")"
assert_contains "4a. npm run build -> deny" "$OUT" '"permissionDecision":"deny"'
OUT="$(bashcmd "echo done > src/flag.txt")"
assert_contains "4b. redirect в src/ -> deny" "$OUT" '"permissionDecision":"deny"'
OUT="$(bashcmd "git add -A && git commit -m 'session: handoff'")"
assert_not_contains "4c. git commit -> pass" "$OUT" '"permissionDecision":"deny"'
OUT="$(bashcmd "ls -la docs/")"
assert_not_contains "4d. ls -> pass" "$OUT" '"permissionDecision":"deny"'

# 5. Следующий промпт БЕЗ сигнала -> режим снят, работа разрешена
OUT="$(up "продолжаем, поправь ещё кнопку")"
assert_absent "5a. маркер снят промптом без сигнала" "$PROJ/.harness/locks/closing-mode"
OUT="$(write "$PROJ/src/app.py")"
assert_not_contains "5b. после снятия Write src/ -> pass" "$OUT" '"permissionDecision":"deny"'

# 6. Вне режима Bash-разработка не трогается
OUT="$(bashcmd "npm run build")"
assert_not_contains "6. вне режима npm -> pass" "$OUT" '"permissionDecision":"deny"'

rm -rf "$PROJ"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
