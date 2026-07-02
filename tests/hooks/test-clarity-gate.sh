#!/bin/bash
# Vibe Dev v6.2 — тест clarity-stop-gate (F4; боль №1 аудита: жаргон/развилки/человеко-дни).
#
# Контракты:
#   - BLOCK-tier (человеко-дни-оценка, HARD-жаргон вне кода) включается ТОЛЬКО при strict
#     или явном портрете непрограммиста; иначе демоция в WARN (нейтральный дефолт v6.1).
#   - Аддендум, не rewrite (remediation в reason); <=2 BLOCK на цепочку, дальше демоция + лог.
#   - PRECISION-ГЕЙТ: block-tier обязан дать 0 false-positive на labeled-корпусе good/
#     и поймать 100% bad/ (правило демоции: провал корпуса = self-check красный = словарь чинится).
#
# Запуск: bash tests/hooks/test-clarity-gate.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECK="$PLUGIN_ROOT/hooks/checks/clarity-stop-gate.sh"
DISPATCH="$PLUGIN_ROOT/hooks/dispatch-stop.sh"
CORPUS="$PLUGIN_ROOT/tests/hooks/fixtures/clarity-corpus"
PASS=0; FAIL=0

unset VIBE_DEV_PROFILE CLAUDE_PLUGIN_ROOT HOOK_PAYLOAD VIBE_DEV_PORTRAIT 2>/dev/null || true

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

PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness"; echo "7.0" > "$PROJ/.harness/engine-version"
PORTRAIT_MED="$(mktemp)"; printf 'jargon_tolerance: medium\n' > "$PORTRAIT_MED"
PORTRAIT_HIGH="$(mktemp)"; printf 'jargon_tolerance: high\n' > "$PORTRAIT_HIGH"
NO_PORTRAIT="/nonexistent/portrait.md"

# run_check <сообщение> <профиль> <портрет-файл>
run_check() {
  rm -f "$PROJ/.harness/clarity-stop-count"
  HOOK_PAYLOAD="$(jq -cn --arg m "$1" '{last_assistant_message:$m}')" \
    VIBE_DEV_PORTRAIT="$3" bash "$CHECK" "$PROJ" "$2"
}

echo "Clarity-stop-gate (F4) — сценарии:"

# --- Тиры включения block ---
OUT="$(run_check "Это займёт примерно 3 дня работы." strict "$NO_PORTRAIT")"
assert_contains "1. strict без портрета: человеко-дни -> BLOCK" "$OUT" "BLOCK"
OUT="$(run_check "Это займёт примерно 3 дня работы." standard "$NO_PORTRAIT")"
assert_not_contains "2a. standard без портрета: демоция (нет BLOCK)" "$OUT" "BLOCK"
assert_contains     "2b. standard без портрета: WARN" "$OUT" "WARN"
OUT="$(run_check "Это займёт примерно 3 дня работы." standard "$PORTRAIT_MED")"
assert_contains "3. портрет (непрограммист) + standard -> BLOCK включён" "$OUT" "BLOCK"
OUT="$(run_check "Пересчитал embedding, enforcement работает." standard "$PORTRAIT_HIGH")"
assert_empty "4a. портрет high: жаргон не ловится вовсе" "$OUT"
OUT="$(run_check "Уложусь в 4 дня вместе с проверкой." strict "$PORTRAIT_HIGH")"
assert_contains "4b. портрет high + strict: человеко-дни всё равно BLOCK" "$OUT" "BLOCK"

# --- Remediation: аддендум, не rewrite ---
OUT="$(run_check "Сделал rollout, enforcement работает." strict "$PORTRAIT_MED")"
assert_contains "5a. remediation: НЕ переписывать целиком" "$OUT" "НЕ переписывай"
assert_contains "5b. remediation: дополнение до 10 строк" "$OUT" "до 10 строк"

# --- Развилка: warn-tier (эвристика) ---
OUT="$(run_check "Вариант А — быстро. Вариант Б — надёжно. Что выбираешь?" strict "$PORTRAIT_MED")"
assert_not_contains "6a. развилка без потерь/рекомендации: НЕ block (эвристика)" "$OUT" "BLOCK"
assert_contains     "6b. развилка: WARN с перечнем недостающего" "$OUT" "что теряешь"
OUT="$(run_check "Вариант А — быстро, но теряешь историю. Вариант Б — дольше. Рекомендую Б." strict "$PORTRAIT_MED")"
assert_empty "6c. правильная развилка -> тихо" "$OUT"

# --- Лимит дописок: 2 BLOCK, дальше демоция ---
rm -f "$PROJ/.harness/clarity-stop-count" "$PROJ/.harness/clarity-cap-log"
P="$(jq -cn '{last_assistant_message:"Это займёт примерно 3 дня."}')"
O1="$(HOOK_PAYLOAD="$P" VIBE_DEV_PORTRAIT="$PORTRAIT_MED" bash "$CHECK" "$PROJ" strict)"
O2="$(HOOK_PAYLOAD="$P" VIBE_DEV_PORTRAIT="$PORTRAIT_MED" bash "$CHECK" "$PROJ" strict)"
O3="$(HOOK_PAYLOAD="$P" VIBE_DEV_PORTRAIT="$PORTRAIT_MED" bash "$CHECK" "$PROJ" strict)"
assert_contains     "7a. дописка №1 -> BLOCK" "$O1" "BLOCK"
assert_contains     "7b. дописка №2 -> BLOCK" "$O2" "BLOCK"
assert_not_contains "7c. №3 -> демоция (нет BLOCK)" "$O3" "BLOCK"
assert_contains     "7d. №3 -> WARN [лимит дописок]" "$O3" "лимит дописок"
assert_contains     "7e. демоция записана в clarity-cap-log" "$(cat "$PROJ/.harness/clarity-cap-log" 2>/dev/null)" "clarity-cap"

# --- PRECISION-ГЕЙТ на labeled-корпусе (block-tier, строгие условия: strict + портрет medium) ---
echo "  — корпус bad/ (recall: каждый обязан дать BLOCK):"
for f in "$CORPUS"/bad/*.txt; do
  OUT="$(run_check "$(cat "$f")" strict "$PORTRAIT_MED")"
  if printf '%s' "$OUT" | grep -q "BLOCK"; then PASS=$((PASS+1)); printf '  ok   bad:%s -> BLOCK\n' "$(basename "$f")"
  else FAIL=$((FAIL+1)); printf '  FAIL bad:%s НЕ пойман block-tier\n     %s\n' "$(basename "$f")" "$OUT"; fi
done
echo "  — корпус good/ (precision: BLOCK запрещён, false positive = демоция словаря):"
for f in "$CORPUS"/good/*.txt; do
  OUT="$(run_check "$(cat "$f")" strict "$PORTRAIT_MED")"
  if printf '%s' "$OUT" | grep -q "BLOCK"; then FAIL=$((FAIL+1)); printf '  FAIL good:%s — FALSE POSITIVE block-tier\n     %s\n' "$(basename "$f")" "$OUT"
  else PASS=$((PASS+1)); printf '  ok   good:%s -> без block\n' "$(basename "$f")"; fi
done

# --- Интеграция: через dispatch-stop (payload как от Claude Code) ---
echo strict > "$PROJ/.harness/profile"
rm -f "$PROJ/.harness/stop-chain-count" "$PROJ/.harness/clarity-stop-count"
TR="$PROJ/tr.jsonl"
jq -cn '{type:"user",message:{role:"user",content:"статус?"}}' > "$TR"
jq -cn '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Готово: отчёт ниже."}]}}' >> "$TR"
SP="$(jq -cn --arg tp "$TR" --arg cwd "$PROJ" --arg m "Сделал rollout, enforcement через payload работает." \
  '{hook_event_name:"Stop",cwd:$cwd,transcript_path:$tp,last_assistant_message:$m}')"
OUT="$(printf '%s' "$SP" | VIBE_DEV_PORTRAIT="$PORTRAIT_MED" bash "$DISPATCH")"
assert_contains "8a. dispatch: clarity-block доходит как decision:block" "$OUT" '"decision":"block"'
assert_contains "8b. dispatch: reason содержит clarity-gate" "$OUT" "clarity-gate"

# Приоритет: intent (не сделал обещанное) ПЕРВЫЙ — clarity подождёт следующего Stop.
rm -f "$PROJ/.harness/stop-chain-count" "$PROJ/.harness/clarity-stop-count"
jq -cn '{type:"user",message:{role:"user",content:"чини"}}' > "$TR"
jq -cn '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Сейчас запущу проверку enforcement."}]}}' >> "$TR"
SP="$(jq -cn --arg tp "$TR" --arg cwd "$PROJ" --arg m "Сейчас запущу проверку enforcement." \
  '{hook_event_name:"Stop",cwd:$cwd,transcript_path:$tp,last_assistant_message:$m}')"
OUT="$(printf '%s' "$SP" | VIBE_DEV_PORTRAIT="$PORTRAIT_MED" bash "$DISPATCH")"
assert_contains     "9a. приоритет: intent-block первый" "$OUT" "H19"
assert_not_contains "9b. clarity в этом же блоке не эмитится" "$OUT" "clarity-gate"

rm -rf "$PROJ" "$PORTRAIT_MED" "$PORTRAIT_HIGH"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
