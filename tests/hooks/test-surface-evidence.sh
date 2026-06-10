#!/bin/bash
# Vibe Dev v6.2 — тест surface-поля и evidence по категории поверхности (F5; П2 аудита).
#
# Контракты:
#   - МОНОТОННОСТЬ: файловая эвристика — пол; declared (surface/category) может только
#     УЖЕСТОЧИТЬ. declared=lib при .tsx в affected НЕ отключает UI-hard-gate (анти-регрессия).
#   - ui: layer_4/5 user-evidence обязателен (hard, существующий механизм 2).
#   - api/service/job/cli: passing без evidence -> WARN с lane-инструкцией (мягкий ввод v6.2).
#   - mismatch declared<эвристика -> warning «поле может только ужесточать».
#
# Запуск: bash tests/hooks/test-surface-evidence.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISPATCH="$PLUGIN_ROOT/hooks/dispatch-pre-tool-use.sh"
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
assert_empty() {
  if [ -z "$(printf '%s' "$2" | tr -d '[:space:]')" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s (ожидал пусто)\n     получил: %s\n' "$1" "$2"; fi
}

PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness"
echo "6.0" > "$PROJ/.harness/engine-version"; echo strict > "$PROJ/.harness/profile"

# write_fl <json-фичи> — Write-намерение feature_list с одной passing-фичей.
write_fl() {
  local content
  content="$(jq -cn --argjson feat "$1" '{features:{passing:[$feat]}}')"
  jq -cn --arg cwd "$PROJ" --arg fp "$PROJ/feature_list.json" --arg c "$content" \
    '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Write",tool_input:{file_path:$fp,content:$c}}' \
    | bash "$DISPATCH"
}

echo "Surface + evidence по категории (F5) — сценарии:"

# 1. api (declared surface) passing без evidence -> WARN с lane-инструкцией
OUT="$(write_fl '{"id":"f1","state":"passing","surface":"api","affected_files":["src/logic.py"]}')"
assert_not_contains "1a. api без evidence: НЕ block (мягкий ввод)" "$OUT" '"permissionDecision":"deny"'
assert_contains     "1b. api без evidence: WARN" "$OUT" "additionalContext"
assert_contains     "1c. lane-инструкция в тексте (curl+статус)" "$OUT" "curl"

# 2. api с evidence (строкой — реальная форма) -> тихо
OUT="$(write_fl '{"id":"f2","state":"passing","surface":"api","affected_files":["src/logic.py"],"evidence":"curl /health -> 200, ответ корректный"}')"
assert_empty "2. api с evidence-строкой -> тихо" "$OUT"

# 3. МОНОТОННОСТЬ: declared=lib + .tsx в affected -> UI-hard всё равно работает
OUT="$(write_fl '{"id":"f3","state":"passing","surface":"lib","affected_files":["src/components/Card.tsx"],"evidence":{"layer_1_syntax":"ok"}}')"
assert_contains "3a. declared=lib не отключает UI-gate (deny)" "$OUT" '"permissionDecision":"deny"'
assert_contains "3b. причина — UI без user-evidence" "$OUT" "layer_4/5"

# 4. mismatch-warn: declared=lib + api-файлы -> предупреждение о монотонности
OUT="$(write_fl '{"id":"f4","state":"passing","surface":"lib","affected_files":["src/api/users.py"],"evidence":{"layer_1_syntax":"ok"}}')"
assert_contains "4. mismatch: «может только УЖЕСТОЧАТЬ»" "$OUT" "УЖЕСТОЧАТЬ"

# 5. declared=ui УЖЕСТОЧАЕТ (файлы не интерфейсные, но surface=ui) -> UI-требование
OUT="$(write_fl '{"id":"f5","state":"passing","surface":"ui","affected_files":["src/logic.py"],"evidence":{"layer_1_syntax":"ok"}}')"
assert_contains "5. declared=ui без ui-файлов -> UI-gate (deny)" "$OUT" '"permissionDecision":"deny"'

# 6. job по ФАЙЛОВОЙ эвристике (jobs/) без evidence -> WARN
OUT="$(write_fl '{"id":"f6","state":"passing","affected_files":["src/jobs/sync.py"]}')"
assert_contains "6a. job-эвристика без evidence: WARN" "$OUT" "additionalContext"
assert_contains "6b. lane: лог реального прогона" "$OUT" "лог реального прогона"

# 7. category=api (legacy-поле, surface нет) -> работает как declared
OUT="$(write_fl '{"id":"f7","state":"passing","category":"api","affected_files":["src/logic.py"]}')"
assert_contains "7. category=api без evidence -> WARN (legacy-поле учитывается)" "$OUT" "additionalContext"

# 8. ui с полноценным evidence -> тихо (счастливый путь не зашумлён)
OUT="$(write_fl '{"id":"f8","state":"passing","surface":"ui","affected_files":["src/components/Card.tsx"],"evidence":{"layer_4_user_at":"2026-06-10 12:00"}}')"
assert_empty "8. ui с layer_4 -> тихо" "$OUT"

rm -rf "$PROJ"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
