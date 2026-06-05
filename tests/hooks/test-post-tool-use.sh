#!/bin/bash
# Vibe Dev v6 — регрессионный тест PostToolUse-диспетчера (волна 1, анти-залипание №2).
#
# Прокси №2 разбора tunnel-vision (gate: docs/anti-stuck-gate-2026-06-05.md, APPROVE-WITH-CHANGES).
# Счётчик ПОДРЯД падающих однотипных Bash-команд (exit≠0, одинаковый «класс» после нормализации)
# -> при пороге (≥3) inject подсказки про субагент-диагностику. warn/inject, НЕ block.
# Mitigation против шума TDD/build: сброс при успехе (exit 0) И при Edit/Write/MultiEdit
# (структурное изменение = прогресс). Инжект РОВНО на пороге (не спамит на 4,5,...).
#
# Воспроизводит реальный триггер: PostToolUse-payload (stdin JSON с tool_response.exit_code).
# Контракт PostToolUse: code.claude.com/docs/en/hooks (tool_response + additionalContext на exit 0).
#
# Запуск: bash tests/hooks/test-post-tool-use.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISPATCH="$PLUGIN_ROOT/hooks/dispatch-post-tool-use.sh"
PASS=0; FAIL=0

unset VIBE_DEV_PROFILE CLAUDE_PLUGIN_ROOT HOOK_PAYLOAD VIBE_BASH_REPEAT_THRESHOLD 2>/dev/null || true

run() { printf '%s' "$1" | bash "$DISPATCH"; }
assert_contains() {
  if printf '%s' "$2" | grep -q -- "$3"; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s\n     ожидал найти: %s\n     получил: %s\n' "$1" "$3" "$2"; fi
}
assert_empty() {
  if [ -z "$(printf '%s' "$2" | tr -d '[:space:]')" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s (ожидал пусто)\n     получил: %s\n' "$1" "$2"; fi
}

PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness"; echo "6.0" > "$PROJ/.harness/engine-version"
reset_state() { rm -f "$PROJ/.harness/bash-repeat-state" 2>/dev/null; }

bp() {  # bp <command> <exit_code> [cwd]   — PostToolUse Bash payload
  local cmd="$1" ec="${2:-1}" cwd="${3:-$PROJ}" succ=false
  [ "$ec" = "0" ] && succ=true
  jq -cn --arg c "$cmd" --argjson ec "$ec" --argjson s "$succ" --arg cwd "$cwd" \
    '{hook_event_name:"PostToolUse",cwd:$cwd,tool_name:"Bash",tool_input:{command:$c},tool_response:{success:$s,exit_code:$ec,stdout:"",stderr:""}}'
}
ep() {  # ep [cwd] — PostToolUse Edit payload (структурное изменение)
  jq -cn --arg cwd "${1:-$PROJ}" \
    '{hook_event_name:"PostToolUse",cwd:$cwd,tool_name:"Edit",tool_input:{file_path:"x.ts"},tool_response:{success:true}}'
}

echo "PostToolUse dispatcher (анти-залипание №2 — повтор Bash) — сценарии:"

# 1. 3 подряд одинаковых падающих -> инжект ровно на 3-м
reset_state
assert_empty   "1a. 1-й падающий -> pass"  "$(run "$(bp "curl http://x/api fail" 1)")"
assert_empty   "1b. 2-й падающий -> pass"  "$(run "$(bp "curl http://x/api fail" 1)")"
OUT="$(run "$(bp "curl http://x/api fail" 1)")"
assert_contains "1c. 3-й падающий -> inject субагент" "$OUT" 'субагент'
assert_contains "1d. ... additionalContext" "$OUT" '"additionalContext"'
# 1e. 4-й одинаковый падающий -> НЕ спамит (инжект только на пороге)
assert_empty   "1e. 4-й падающий -> pass (one-shot)" "$(run "$(bp "curl http://x/api fail" 1)")"

# 2. Успех в середине -> сброс счётчика
reset_state
run "$(bp "pnpm test" 1)" >/dev/null
run "$(bp "pnpm test" 1)" >/dev/null
assert_empty "2a. успех -> pass + reset" "$(run "$(bp "pnpm test" 0)")"
assert_empty "2b. падающий после успеха -> count=1, pass" "$(run "$(bp "pnpm test" 1)")"

# 3. Разные классы падающих -> не инжектит
reset_state
run "$(bp "ls /a" 1)" >/dev/null
run "$(bp "cat /b" 1)" >/dev/null
assert_empty "3. разные команды падают -> pass" "$(run "$(bp "grep x /c" 1)")"

# 4. Один класс, разные числа (нормализация цифр) -> инжект на 3-м
reset_state
run "$(bp "curl http://api?offset=500" 1)" >/dev/null
run "$(bp "curl http://api?offset=1000" 1)" >/dev/null
OUT="$(run "$(bp "curl http://api?offset=1500" 1)")"
assert_contains "4. param-tweak одной команды -> inject (нормализация)" "$OUT" 'субагент'

# 5. Edit между падающими -> сброс (прогресс, не слепой повтор)
reset_state
run "$(bp "pnpm build" 1)" >/dev/null
run "$(bp "pnpm build" 1)" >/dev/null
run "$(ep)" >/dev/null   # структурное изменение -> reset
assert_empty "5. Edit сбросил счётчик -> следующий падающий count=1, pass" "$(run "$(bp "pnpm build" 1)")"

# 6. minimal-профиль -> pass
reset_state
echo minimal > "$PROJ/.harness/profile"
run "$(bp "x fail" 1)" >/dev/null; run "$(bp "x fail" 1)" >/dev/null
assert_empty "6. профиль minimal -> pass (выключен)" "$(run "$(bp "x fail" 1)")"
rm -f "$PROJ/.harness/profile"

# 7. Не vibe-проект -> pass (guard)
NOPROJ="$(mktemp -d)"
assert_empty "7. не-vibe-проект -> pass" "$(run "$(bp "x fail" 1 "$NOPROJ")")"
rm -rf "$NOPROJ"

# 8. Инжект — валидный JSON
reset_state
run "$(bp "z fail" 1)" >/dev/null; run "$(bp "z fail" 1)" >/dev/null
OUT="$(run "$(bp "z fail" 1)")"
if printf '%s' "$OUT" | jq empty 2>/dev/null; then PASS=$((PASS+1)); printf '  ok   8. инжект — валидный JSON\n'
else FAIL=$((FAIL+1)); printf '  FAIL 8. инжект — НЕ валидный JSON\n     получил: %s\n' "$OUT"; fi

# 9. Успешная команда -> pass + state удалён
reset_state
run "$(bp "echo ok" 1)" >/dev/null
run "$(bp "echo ok" 0)" >/dev/null
if [ ! -f "$PROJ/.harness/bash-repeat-state" ]; then PASS=$((PASS+1)); printf '  ok   9. успех -> state-файл сброшен\n'
else FAIL=$((FAIL+1)); printf '  FAIL 9. state-файл не сброшен после успеха\n'; fi

rm -rf "$PROJ"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
