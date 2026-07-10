#!/bin/bash
# Vibe Dev v8 — тест бюджета tool-call на фичу (L5-F6): счётчик + нудж при превышении.
# Запуск: bash tests/hooks/test-feature-budget.sh
set -u
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHK="$PLUGIN_ROOT/hooks/checks/feature-budget.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }
is_warn()  { printf '%s' "$1" | grep -q '^WARN'; }
is_empty() { [ -z "$(printf '%s' "$1" | tr -d '[:space:]')" ]; }

PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness"
run() { bash "$CHK" "$PROJ"; }

echo "Feature-budget L5-F6 — счётчик tool-call на фичу"

# 1. нет active → тихо
echo '{"active":null,"features":{"active_list":[]}}' > "$PROJ/feature_list.json"
is_empty "$(run)" && ok "1. нет active → тихо" || bad "1. нет active" "ожидал пусто"

# 2-4. active feat-1 с бюджетом 3: первые 3 вызова тихо, 4-й → warn
echo '{"active":"feat-1","features":{"active_list":[{"id":"feat-1","tool_call_budget":3}]}}' > "$PROJ/feature_list.json"
R1="$(run)"; R2="$(run)"; R3="$(run)"
{ is_empty "$R1" && is_empty "$R2" && is_empty "$R3"; } && ok "2. count 1..3 (=бюджет) → тихо" || bad "2. в пределах бюджета" "R1=[$R1] R2=[$R2] R3=[$R3]"
R4="$(run)"
is_warn "$R4" && ok "3. count 4 > бюджет 3 → нудж" || bad "3. превышение → нудж" "получил [$R4]"
printf '%s' "$R4" | grep -q 'checkpoint' && ok "4. нудж зовёт /checkpoint или /stuck" || bad "4. нудж содержит checkpoint" "$R4"

# 5. повторный вызов после нуджа → тихо (не спамит каждый tool-call)
R5="$(run)"
is_empty "$R5" && ok "5. после нуджа → тихо (WARNED, не спам)" || bad "5. не спамит" "получил [$R5]"

# 6. смена active-фичи → счётчик сброшен (feat-2 бюджет 2: 2 тихо, 3-й warn)
echo '{"active":"feat-2","features":{"active_list":[{"id":"feat-2","tool_call_budget":2}]}}' > "$PROJ/feature_list.json"
S1="$(run)"; S2="$(run)"
{ is_empty "$S1" && is_empty "$S2"; } && ok "6. смена фичи → счётчик сброшен (1..2 тихо)" || bad "6. сброс при смене" "S1=[$S1] S2=[$S2]"
S3="$(run)"
is_warn "$S3" && ok "7. новая фича: превышение своего бюджета → нудж" || bad "7. новый бюджет" "получил [$S3]"

# 8. дефолтный бюджет (нет tool_call_budget) → 1 вызов тихо (1 << 150)
echo '{"active":"feat-3","features":{"active_list":[{"id":"feat-3"}]}}' > "$PROJ/feature_list.json"
is_empty "$(run)" && ok "8. без поля бюджета → дефолт 150, тихо на первом" || bad "8. дефолт" "ожидал пусто"

rm -rf "$PROJ"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
