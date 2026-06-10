#!/bin/bash
# Vibe Dev v6.2 — тест единого Stop-диспетчера (F3): общий cap цепочки + сброс на новом промпте.
#
# На Stop живут несколько сторожей (intent H19, clarity F4, wave v6.3). Без общего cap
# каскад блоков зацикливает ход. Контракт: ≤3 block на цепочку (от промпта до промпта);
# при переполнении — pass + запись .harness/stop-cap-log; UserPromptSubmit сбрасывает счётчик.
#
# Запуск: bash tests/hooks/test-stop-dispatcher.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISPATCH="$PLUGIN_ROOT/hooks/dispatch-stop.sh"
PASS=0; FAIL=0

unset VIBE_DEV_PROFILE CLAUDE_PLUGIN_ROOT HOOK_PAYLOAD 2>/dev/null || true

assert_contains() {
  if printf '%s' "$2" | grep -q -- "$3"; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s\n     ожидал: %s\n     получил: %s\n' "$1" "$3" "$2"; fi
}
assert_empty() {
  if [ -z "$(printf '%s' "$2" | tr -d '[:space:]')" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s (ожидал пусто)\n     получил: %s\n' "$1" "$2"; fi
}
assert_eq() {
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s\n     ожидал: %s\n     получил: %s\n' "$1" "$3" "$2"; fi
}

rec_user_prompt() { jq -cn --arg t "$1" '{type:"user",message:{role:"user",content:$t}}'; }
rec_asst_text()   { jq -cn --arg t "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'; }

PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness"; echo "6.0" > "$PROJ/.harness/engine-version"

# Транскрипт с намерением-без-действия (триггер intent-блока).
TR="$PROJ/transcript.jsonl"
{ rec_user_prompt "почини баг"; rec_asst_text "Сейчас запущу проверку."; } > "$TR"
STOP_PAYLOAD="$(jq -cn --arg tp "$TR" --arg cwd "$PROJ" '{hook_event_name:"Stop",cwd:$cwd,transcript_path:$tp}')"
run_stop() { printf '%s' "$STOP_PAYLOAD" | bash "$DISPATCH"; }

echo "Единый Stop-dispatcher (F3) — сценарии:"

# 1-3. Три блока подряд: каждый блокирует и инкрементирует счётчик.
OUT="$(run_stop)"
assert_contains "1a. блок №1" "$OUT" '"decision":"block"'
assert_eq       "1b. счётчик цепочки = 1" "$(cat "$PROJ/.harness/stop-chain-count")" "1"
OUT="$(run_stop)"
assert_contains "2. блок №2" "$OUT" '"decision":"block"'
OUT="$(run_stop)"
assert_contains "3a. блок №3" "$OUT" '"decision":"block"'
assert_eq       "3b. счётчик цепочки = 3" "$(cat "$PROJ/.harness/stop-chain-count")" "3"

# 4. Четвёртый: cap -> pass + лог (не бесконечная переписка).
OUT="$(run_stop)"
assert_empty    "4a. блок №4 НЕ эмитится (cap 3)" "$OUT"
assert_contains "4b. cap-pass записан в stop-cap-log" "$(cat "$PROJ/.harness/stop-cap-log" 2>/dev/null)" "cap-pass"

# 5. Новый промпт пользователя сбрасывает цепочку (UserPromptSubmit-диспетчер).
UP="$(jq -cn --arg cwd "$PROJ" '{hook_event_name:"UserPromptSubmit",cwd:$cwd,prompt:"дальше"}')"
printf '%s' "$UP" | bash "$PLUGIN_ROOT/hooks/dispatch-user-prompt.sh" >/dev/null
if [ ! -f "$PROJ/.harness/stop-chain-count" ]; then PASS=$((PASS+1)); printf '  ok   5a. счётчик сброшен новым промптом\n'
else FAIL=$((FAIL+1)); printf '  FAIL 5a. счётчик должен быть сброшен\n'; fi
OUT="$(run_stop)"
assert_contains "5b. после сброса блок снова работает" "$OUT" '"decision":"block"'

# 6. Чистый ход (результат, не намерение) — диспетчер тихий, счётчик не растёт.
rm -f "$PROJ/.harness/stop-chain-count"
{ rec_user_prompt "почини баг"; rec_asst_text "Готово: тест зелёный, причина была в типе поля."; } > "$TR"
OUT="$(run_stop)"
assert_empty "6a. чистый ход -> pass" "$OUT"
if [ ! -f "$PROJ/.harness/stop-chain-count" ]; then PASS=$((PASS+1)); printf '  ok   6b. счётчик не создан на pass\n'
else FAIL=$((FAIL+1)); printf '  FAIL 6b. счётчик не должен расти на pass\n'; fi

rm -rf "$PROJ"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
