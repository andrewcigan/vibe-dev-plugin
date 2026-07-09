#!/bin/bash
# Vibe Dev v8 — тест record-change.sh (L3-F3): crash-safe writer + идемпотентность + recovery.
# Запуск: bash tests/hooks/test-record-change.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RC="$PLUGIN_ROOT/scripts/record-change.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "ожидал [$2] получил [$3]"; fi; }

PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness"
cat > "$PROJ/feature_list.json" <<'JSON'
{"version":"8.0","features":{"active_list":[
{"id":"feat-001","name":"X","description":"старое","state":"active",
 "provenance":{"origin":"owner-msg","source_ref":{"kind":"session","ref":"s"},"captured_at":"2026-07-10T00:00:00Z","by":"owner","seq":0}}
]}}
JSON
LOG="$PROJ/.harness/provenance-log.jsonl"
q() { python3 -c "import json,sys; d=json.load(open('$PROJ/feature_list.json')); f=[x for b in d['features'].values() for x in b if x['id']=='feat-001'][0]; print($1)"; }
logcount() { [ -f "$LOG" ] && grep -c . "$LOG" || echo 0; }

echo "record-change (L3-F3) — сценарии:"

# 1. MODIFIED → seq=1, лог+голова+бизнес-поле синхронны
printf '{"feat":"feat-001","op":"MODIFIED","by":"owner","origin":"dialog","source_ref":{"kind":"session","ref":"s2"},"changes":{"description":{"to":"новое"}},"change_id":"c1"}' | bash "$RC" --project "$PROJ" >/dev/null 2>&1
eq "1a. лог: 1 событие" "1" "$(logcount)"
eq "1b. голова provenance.seq=1" "1" "$(q "f['provenance']['seq']")"
eq "1c. бизнес-поле применено" "новое" "$(q "f['description']")"
eq "1d. from_hash в событии" "True" "$(python3 -c "import json; e=json.loads(open('$LOG').readlines()[-1]); print('from_hash' in e['changes']['description'])")"

# 2. Идемпотентность: повтор того же change_id → лог НЕ растёт
printf '{"feat":"feat-001","op":"MODIFIED","by":"owner","changes":{"description":{"to":"новое"}},"change_id":"c1"}' | bash "$RC" --project "$PROJ" >/dev/null 2>&1
eq "2. повтор change_id → лог всё ещё 1 (идемпотентно)" "1" "$(logcount)"

# 3. Ещё одно изменение → seq=2
printf '{"feat":"feat-001","op":"MODIFIED","by":"owner","changes":{"description":{"to":"третье"}},"change_id":"c2"}' | bash "$RC" --project "$PROJ" >/dev/null 2>&1
eq "3a. лог: 2 события" "2" "$(logcount)"
eq "3b. голова seq=2" "2" "$(q "f['provenance']['seq']")"

# 4. Симуляция ОБРЫВА: событие seq=3 добавлено в лог, а голова не успела (обрыв между append и mv)
printf '{"v":1,"at":"2026-07-10T01:00:00Z","feat":"feat-001","seq":3,"op":"MODIFIED","change_id":"c3","by":"owner","changes":{"description":{"to":"после обрыва","from_hash":"sha256:x"}}}\n' >> "$LOG"
eq "4a. до recovery: голова отстала (seq=2)" "2" "$(q "f['provenance']['seq']")"
bash "$RC" --recover --project "$PROJ" >/dev/null 2>&1
eq "4b. после recovery: голова догнала seq=3" "3" "$(q "f['provenance']['seq']")"
eq "4c. после recovery: бизнес-поле восстановлено" "после обрыва" "$(q "f['description']")"

# 5. Рваный хвост лога (обрыв на середине append) — не роняет recovery
printf '{"feat":"feat-001","op":"MODI' >> "$LOG"  # незавершённая строка
if bash "$RC" --recover --project "$PROJ" >/dev/null 2>&1; then ok "5. рваный хвост лога → recovery терпит (exit 0)"; else bad "5. рваный хвост" "recovery упал на битой строке"; fi

rm -rf "$PROJ"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
