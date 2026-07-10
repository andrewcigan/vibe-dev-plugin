#!/bin/bash
# Vibe Dev v8 — тест единой цифры /audit: объективные метрики (L5-F5, c11).
# Запуск: bash tests/hooks/test-audit-health.sh
set -u
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AH="$PLUGIN_ROOT/scripts/audit-health.sh"
ARCHSH="$PLUGIN_ROOT/scripts/archive-features.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }
has() { printf '%s' "$1" | grep -q -- "$2"; }

PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness"

# 2 горячих фичи: одна с валидной головой, одна с битой (нет origin) → integrity 50%.
# + 1 done+evidence с валидной головой → уйдёт в архив стабом (archive_evidence).
cat > "$PROJ/feature_list.json" <<'JSON'
{"version":"8.0","features":{
 "up_next":[
   {"id":"feat-01","name":"Валидная","state":"up_next","description":"D","tool_call_budget":80,
    "provenance":{"origin":"owner-msg","source_ref":{"kind":"session","ref":"s"},"captured_at":"2026-07-10T00:00:00Z","by":"owner"}},
   {"id":"feat-02","name":"Битая голова","state":"up_next","description":"D",
    "provenance":{"source_ref":{"kind":"session","ref":"s"},"captured_at":"2026-07-10T00:00:00Z","by":"owner"}}
 ],
 "done":[
   {"id":"feat-03","name":"Готовая","state":"done","description":"D","evidence":{"layer_1_syntax_at":"2026-07-10T00:00:00Z"},
    "provenance":{"origin":"owner-msg","source_ref":{"kind":"session","ref":"s"},"captured_at":"2026-07-10T00:00:00Z","by":"owner"}}
 ]}}
JSON

echo "Audit-health L5-F5 — объективные метрики"
bash "$ARCHSH" "$PROJ" >/dev/null 2>&1   # feat-03 → стаб + archive.json
OUT="$(bash "$AH" "$PROJ" 2>&1)"

has "$OUT" "provenance_integrity: 50%" && ok "1. provenance_integrity 50% (1 из 2 голов валидна)" || bad "1. provenance_integrity 50%" "$OUT"
has "$OUT" "archive_evidence:     100%" && ok "2. archive_evidence 100% (стаб сошёлся с телом)" || bad "2. archive_evidence 100%" "$OUT"
has "$OUT" "health_objective:     50" && ok "3. health_objective = min (узкое место 50)" || bad "3. health_objective min" "$OUT"
has "$OUT" "budget_coverage:" && ok "4. budget_coverage печатается (информативно)" || bad "4. budget_coverage" "$OUT"

# Полностью валидный проект → integrity 100%
cat > "$PROJ/feature_list.json" <<'JSON'
{"version":"8.0","features":{"up_next":[
 {"id":"feat-10","name":"OK","state":"up_next","description":"D","tool_call_budget":50,
  "provenance":{"origin":"dialog","source_ref":{"kind":"session","ref":"s"},"captured_at":"2026-07-10T00:00:00Z","by":"owner"}}
]}}
JSON
rm -f "$PROJ/feature_list.archive.json"
OUT2="$(bash "$AH" "$PROJ" 2>&1)"
has "$OUT2" "provenance_integrity: 100%" && ok "5. валидный проект → integrity 100%" || bad "5. integrity 100%" "$OUT2"
has "$OUT2" "health_objective:     100" && ok "6. health_objective 100 (нет узких мест)" || bad "6. health 100" "$OUT2"

rm -rf "$PROJ"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
