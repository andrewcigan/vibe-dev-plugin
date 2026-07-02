#!/bin/bash
# Vibe Dev v7 (Волна 5, P6) — тесты go-mode listener + wave-continue.
# Маркер go-mode ставит САМ listener (хук-путь), не redirect в locks (иначе locks-protect).
# Запуск: bash tests/hooks/test-wave-continue.sh
set -u
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PLUGIN_ROOT" || exit 1
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness/locks"
listen() { local p="$1"; HOOK_PAYLOAD="$(jq -cn --arg p "$p" '{prompt:$p}')" bash hooks/checks/go-mode-listener.sh "$PROJ"; }
TRQ="$PROJ/q.jsonl"; TRN="$PROJ/n.jsonl"
printf '%s\n' '{"type":"user","message":{"content":"делай"}}' '{"type":"assistant","message":{"content":[{"type":"text","text":"Сделал шаг. Продолжать дальше?"}]}}' > "$TRQ"
printf '%s\n' '{"type":"user","message":{"content":"делай"}}' '{"type":"assistant","message":{"content":[{"type":"text","text":"Сделал шаг, иду дальше."}]}}' > "$TRN"
wc_run() { HOOK_PAYLOAD="$(jq -cn --arg t "$1" '{transcript_path:$t}')" bash hooks/checks/wave-continue.sh "$PROJ"; }

# 1. go-фраза → маркер ставится
listen "не тормози, делай до конца сам"
[ -f "$PROJ/.harness/locks/go-mode" ] && ok "1. go-фраза ставит go-mode" || bad "1. go-фраза ставит go-mode"

# 2. go-mode + последний ход кончился «?» → WARN
printf '%s' "$(wc_run "$TRQ")" | grep -q '^WARN' && ok "2. go-mode + вопрос в конце → warn" || bad "2. go-mode + вопрос → warn"

# 3. go-mode, но ход НЕ кончился «?» → тишина
[ -z "$(wc_run "$TRN")" ] && ok "3. go-mode, нет вопроса → тишина" || bad "3. go-mode без вопроса → тишина"

# 4. стоп-слово снимает go-mode
listen "стоп, погоди"
[ ! -f "$PROJ/.harness/locks/go-mode" ] && ok "4. стоп-слово снимает go-mode" || bad "4. стоп-слово снимает go-mode"

# 5. нет go-mode + вопрос в конце → тишина (не пушим без явной просьбы)
[ -z "$(wc_run "$TRQ")" ] && ok "5. без go-mode не пушит (даже если вопрос)" || bad "5. без go-mode молчит"

rm -rf "$PROJ" 2>/dev/null
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ]
