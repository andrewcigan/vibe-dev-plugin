#!/bin/bash
# Vibe Dev v8 — тест провенанс-захвата (L3-F1) в state-transition.sh (через dispatcher).
#
# Контракты (активны при engine major≥8, strict):
#   - фича без provenance-головы → block (backstop против ручных Write);
#   - фича с полной головой (origin+source_ref{kind}+captured_at+by) → pass;
#   - клапан честности: origin=inference + source_ref.kind=unknown → pass (не выдумываем источник);
#   - невалидный origin / source_ref без kind → block;
#   - engine<8 → провенанс спит (старый контракт не задет).
#
# Запуск: bash tests/hooks/test-provenance-capture.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PRE="$PLUGIN_ROOT/hooks/dispatch-pre-tool-use.sh"
PASS=0; FAIL=0
unset VIBE_DEV_PROFILE CLAUDE_PLUGIN_ROOT HOOK_PAYLOAD 2>/dev/null || true

ac() { if printf '%s' "$2" | grep -q -- "$3"; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL %s\n     получил: %s\n' "$1" "$2"; fi; }
nc() { if printf '%s' "$2" | grep -q -- "$3"; then FAIL=$((FAIL+1)); printf '  FAIL %s (не ожидал deny)\n     %s\n' "$1" "$2"; else PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; fi; }

PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness"
echo strict > "$PROJ/.harness/profile"

writefl() { # $1 = engine-version, $2 = content
  echo "$1" > "$PROJ/.harness/engine-version"
  jq -cn --arg cwd "$PROJ" --arg fp "$PROJ/feature_list.json" --arg c "$2" \
    '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Write",tool_input:{file_path:$fp,content:$c}}' | bash "$PRE"
}

FULL='{"version":"8.0","features":{"captured":[{"id":"feat-001","name":"X","state":"captured","provenance":{"origin":"owner-msg","source_ref":{"kind":"session","ref":"s:1"},"captured_at":"2026-07-10T10:00:00Z","by":"owner","seq":0}}]}}'
NOPROV='{"version":"8.0","features":{"captured":[{"id":"feat-001","name":"X","state":"captured"}]}}'
HONEST='{"version":"8.0","features":{"captured":[{"id":"feat-001","name":"X","state":"captured","provenance":{"origin":"inference","source_ref":{"kind":"unknown"},"captured_at":"2026-07-10T10:00:00Z","by":"agent","seq":0}}]}}'
BADORIGIN='{"version":"8.0","features":{"captured":[{"id":"feat-001","name":"X","state":"captured","provenance":{"origin":"telepathy","source_ref":{"kind":"session","ref":"s"},"captured_at":"2026-07-10T10:00:00Z","by":"owner"}}]}}'
NOKIND='{"version":"8.0","features":{"captured":[{"id":"feat-001","name":"X","state":"captured","provenance":{"origin":"owner-msg","source_ref":{"ref":"s"},"captured_at":"2026-07-10T10:00:00Z","by":"owner"}}]}}'

echo "Провенанс-захват (L3-F1) — сценарии:"

OUT="$(writefl "8.0" "$NOPROV")"
ac "1. engine8: фича без provenance → deny" "$OUT" '"permissionDecision":"deny"'

OUT="$(writefl "8.0" "$FULL")"
nc "2. engine8: полная provenance-голова → pass" "$OUT" '"permissionDecision":"deny"'

OUT="$(writefl "8.0" "$HONEST")"
nc "3. клапан честности inference/unknown → pass" "$OUT" '"permissionDecision":"deny"'

OUT="$(writefl "8.0" "$BADORIGIN")"
ac "4. невалидный origin → deny" "$OUT" '"permissionDecision":"deny"'

OUT="$(writefl "8.0" "$NOKIND")"
ac "5. source_ref без kind → deny" "$OUT" '"permissionDecision":"deny"'

OUT="$(writefl "7.0" "$NOPROV")"
nc "6. engine7: провенанс спит (старый контракт) → pass" "$OUT" '"permissionDecision":"deny"'

rm -rf "$PROJ"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
