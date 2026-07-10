#!/bin/bash
# Vibe Dev v8 — тест архива фич по ссылке (L3-F5, c3/c10): ротация + hash-целостность.
# Запуск: bash tests/hooks/test-provenance-archive.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARCHSH="$PLUGIN_ROOT/scripts/archive-features.sh"
HOOK_SRC="$PLUGIN_ROOT/templates/git-pre-commit.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "ожидал [$2] получил [$3]"; fi; }

echo "Архив фич (L3-F5) — часть A: ротация"
SB="$(mktemp -d)"; mkdir -p "$SB/.harness"
cat > "$SB/feature_list.json" <<'JSON'
{"version":"8.0","features":{"done":[
{"id":"feat-001","name":"Готовая с evidence","state":"done","description":"D","evidence":{"layer_1_syntax_at":"2026-07-10T00:00:00Z"},
 "provenance":{"origin":"owner-msg","source_ref":{"kind":"session","ref":"s"},"captured_at":"2026-07-10T00:00:00Z","by":"owner","seq":1}},
{"id":"feat-002","name":"Готовая без evidence","state":"done","description":"D2",
 "provenance":{"origin":"owner-msg","source_ref":{"kind":"session","ref":"s"},"captured_at":"2026-07-10T00:00:00Z","by":"owner","seq":1}}
],"superseded":[
{"id":"feat-003","name":"Заменённая","state":"superseded",
 "provenance":{"origin":"owner-msg","source_ref":{"kind":"session","ref":"s"},"captured_at":"2026-07-10T00:00:00Z","by":"owner","seq":1,"superseded_by":["feat-004"]}}
],"active_list":[]}}
JSON
bash "$ARCHSH" "$SB" >/dev/null 2>&1
pj() { python3 -c "import json;print($1)"; }
HOT="$(cat "$SB/feature_list.json")"
ARC="$(cat "$SB/feature_list.archive.json" 2>/dev/null || echo '{}')"

eq "1. done c evidence → стаб в горячем (есть evidence_hash)" "True" "$(python3 -c "import json;d=json.load(open('$SB/feature_list.json'));f=[x for x in d['features']['done'] if x['id']=='feat-001'][0];print('evidence_hash' in f and 'description' not in f)")"
eq "2. done c evidence → тело в архиве" "True" "$(python3 -c "import json;a=json.load(open('$SB/feature_list.archive.json'));print(any(x['id']=='feat-001' for x in a['archived']))")"
eq "3. done БЕЗ evidence → НЕ архивирован (остался с телом)" "True" "$(python3 -c "import json;d=json.load(open('$SB/feature_list.json'));f=[x for x in d['features']['done'] if x['id']=='feat-002'][0];print('evidence_hash' not in f and 'description' in f)")"
eq "4. superseded → архивирован (стаб)" "True" "$(python3 -c "import json;d=json.load(open('$SB/feature_list.json'));f=[x for x in d['features']['superseded'] if x['id']=='feat-003'][0];print('evidence_hash' in f)")"

# идемпотентность
CNT1="$(python3 -c "import json;print(len(json.load(open('$SB/feature_list.archive.json'))['archived']))")"
bash "$ARCHSH" "$SB" >/dev/null 2>&1
CNT2="$(python3 -c "import json;print(len(json.load(open('$SB/feature_list.archive.json'))['archived']))")"
eq "5. идемпотентность (повтор не дублирует архив)" "$CNT1" "$CNT2"
rm -rf "$SB"

echo "Архив фич (L3-F5) — часть B: hash-целостность (git pre-commit)"
REPO="$(mktemp -d)"; cd "$REPO" || exit 1
git init -q; git config user.email t@t.t; git config user.name t
mkdir -p .harness .git/hooks
cp "$HOOK_SRC" .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
# сгенерировать корректный стаб+архив через archive-features.sh
cat > feature_list.json <<'JSON'
{"version":"8.0","features":{"done":[{"id":"feat-001","name":"X","state":"done","description":"D","evidence":{"layer_1_syntax_at":"2026-07-10T00:00:00Z"},"provenance":{"origin":"owner-msg","source_ref":{"kind":"session","ref":"s"},"captured_at":"2026-07-10T00:00:00Z","by":"owner","seq":1}}]}}
JSON
bash "$ARCHSH" "$REPO" >/dev/null 2>&1
git add -A
if git commit -q -m "archive rotate" 2>/dev/null; then ok "6. корректный стаб + тело + hash → pass"; else bad "6. корректный → pass" "reject валидного архива"; fi

# битый hash в стабе → reject
python3 -c "import json;d=json.load(open('feature_list.json'));[f for f in d['features']['done'] if f['id']=='feat-001'][0]['evidence_hash']='sha256:TAMPERED';json.dump(d,open('feature_list.json','w'))"
git add feature_list.json
if git commit -q -m "tamper hash" 2>/dev/null; then bad "7. битый evidence_hash → reject" "коммит прошёл"; else ok "7. битый evidence_hash стаба → reject"; fi
git reset -q --hard HEAD 2>/dev/null

# стаб без тела в архиве → reject
python3 -c "import json;a=json.load(open('feature_list.archive.json'));a['archived']=[];json.dump(a,open('feature_list.archive.json','w'))"
git add feature_list.archive.json
if git commit -q -m "empty archive" 2>/dev/null; then bad "8. стаб без тела в архиве → reject" "коммит прошёл"; else ok "8. стаб без тела в архиве → reject"; fi

cd /; rm -rf "$REPO"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
