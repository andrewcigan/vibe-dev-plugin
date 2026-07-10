#!/bin/bash
# Vibe Dev v8 — тест управляемого чекпоинта (L4-F2, c6/c8):
# cold-start gate блокирует завершение, если состояние не в файлах; ротация завершённых в архив.
# Запуск: bash tests/hooks/test-checkpoint.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CP="$PLUGIN_ROOT/scripts/checkpoint.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "ожидал [$2] получил [$3]"; fi; }

mkproj() { local d; d="$(mktemp -d)"; mkdir -p "$d/.harness"; printf '%s' "$d"; }

echo "Checkpoint L4-F2 — cold-start gate + ротация"

# --- Сценарий 1: SESSION.md шаблонный (не обновляли) → BLOCK ---
P1="$(mkproj)"
cat > "$P1/feature_list.json" <<'JSON'
{"version":"8.0","features":{"active_list":[{"id":"feat-042","name":"Экспорт","state":"active","description":"D"}]}}
JSON
cp "$PLUGIN_ROOT/templates/SESSION.md" "$P1/SESSION.md"   # шаблон as-is (плейсхолдеры)
OUT1="$(bash "$CP" "$P1" 2>&1)"; RC1=$?
eq "1. шаблонный SESSION.md → block (exit 1)" "1" "$RC1"
if printf '%s' "$OUT1" | grep -q "CHECKPOINT НЕ ЗАВЕРШЁН"; then ok "2. block называет причину"; else bad "2. block причина" "$OUT1"; fi
if printf '%s' "$OUT1" | grep -q "YYYY-MM-DD"; then ok "3. указывает шаблонный Last Updated"; else bad "3. Last Updated" "$OUT1"; fi
rm -rf "$P1"

# --- Сценарий 2: SESSION.md заполнен реально → PASS + cold-start self-test ---
P2="$(mkproj)"
cat > "$P2/feature_list.json" <<'JSON'
{"version":"8.0","features":{"active_list":[{"id":"feat-042","name":"Экспорт","state":"active","description":"D",
  "provenance":{"origin":"owner-msg","source_ref":{"kind":"session","ref":"s"},"captured_at":"2026-07-10T00:00:00Z","by":"owner"}}]}}
JSON
cat > "$P2/SESSION.md" <<'MD'
# Session Log

## Current State

**Last Updated**: 2026-07-10 14:00
**Active Feature**: feat-042 — Экспорт (state: active)
**Mode**: FAST

## Today
### What's Next
1. Доделать e2e экспорта
MD
OUT2="$(bash "$CP" "$P2" 2>&1)"; RC2=$?
eq "4. заполненный SESSION.md → pass (exit 0)" "0" "$RC2"
if printf '%s' "$OUT2" | grep -q "checkpoint готов"; then ok "5. checkpoint завершён"; else bad "5. завершён" "$OUT2"; fi
if printf '%s' "$OUT2" | grep -q "Cold-start self-test"; then ok "6. печатает cold-start self-test"; else bad "6. cold-start" "$OUT2"; fi
rm -rf "$P2"

# --- Сценарий 3: нет SESSION.md → BLOCK ---
P3="$(mkproj)"
cat > "$P3/feature_list.json" <<'JSON'
{"version":"8.0","features":{"active_list":[]}}
JSON
OUT3="$(bash "$CP" "$P3" 2>&1)"; RC3=$?
eq "7. нет SESSION.md → block" "1" "$RC3"
if printf '%s' "$OUT3" | grep -q "нет SESSION.md"; then ok "8. block про отсутствие SESSION.md"; else bad "8. отсутствие SESSION" "$OUT3"; fi
rm -rf "$P3"

# --- Сценарий 4: провенанс голова впереди лога → BLOCK ---
P4="$(mkproj)"
cat > "$P4/feature_list.json" <<'JSON'
{"version":"8.0","features":{"active_list":[{"id":"feat-042","name":"Экспорт","state":"active","description":"D",
  "provenance":{"origin":"owner-msg","source_ref":{"kind":"session","ref":"s"},"captured_at":"2026-07-10T00:00:00Z","by":"owner","seq":5}}]}}
JSON
cat > "$P4/SESSION.md" <<'MD'
## Current State
**Last Updated**: 2026-07-10 14:00
**Active Feature**: feat-042 — Экспорт (state: active)
MD
OUT4="$(bash "$CP" "$P4" 2>&1)"; RC4=$?
eq "9. голова провенанса впереди лога → block" "1" "$RC4"
if printf '%s' "$OUT4" | grep -q "впереди лога"; then ok "10. block про когерентность"; else bad "10. когерентность" "$OUT4"; fi
rm -rf "$P4"

# --- Сценарий 5: ротация завершённой фичи в архив при checkpoint ---
P5="$(mkproj)"
cat > "$P5/feature_list.json" <<'JSON'
{"version":"8.0","features":{"done":[{"id":"feat-001","name":"Готово","state":"done","description":"D",
  "evidence":{"layer_1_syntax_at":"2026-07-10T00:00:00Z"},
  "provenance":{"origin":"owner-msg","source_ref":{"kind":"session","ref":"s"},"captured_at":"2026-07-10T00:00:00Z","by":"owner"}}],
 "active_list":[]}}
JSON
cat > "$P5/SESSION.md" <<'MD'
## Current State
**Last Updated**: 2026-07-10 14:00
**Active Feature**: нет активной (граница волны)
MD
bash "$CP" "$P5" >/dev/null 2>&1
eq "11. done+evidence → архивирован при checkpoint (стаб)" "True" \
   "$(python3 -c "import json;d=json.load(open('$P5/feature_list.json'));f=[x for x in d['features']['done'] if x['id']=='feat-001'][0];print('evidence_hash' in f)")"
eq "12. тело перенесено в archive.json" "True" \
   "$(python3 -c "import json,os;p='$P5/feature_list.archive.json';print(os.path.exists(p) and any(x['id']=='feat-001' for x in json.load(open(p))['archived']))")"
rm -rf "$P5"

echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
