#!/bin/bash
# Vibe Dev v8 — тест инварианта правки бизнес-поля (L3-F4, критик b/Q9) через git pre-commit.
# Правка бизнес-поля без события лога → reject; с покрывающим событием → pass; техническое поле → pass.
# Запуск: bash tests/hooks/test-provenance-edit-gate.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK_SRC="$PLUGIN_ROOT/templates/git-pre-commit.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

REPO="$(mktemp -d)"; cd "$REPO" || exit 1
git init -q; git config user.email t@t.t; git config user.name t
mkdir -p .harness .git/hooks
cp "$HOOK_SRC" .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
LOG=".harness/provenance-log.jsonl"

# seed: фича description=старое, seq=1; лог событие seq=1
cat > feature_list.json <<'JSON'
{"version":"8.0","features":{"active_list":[{"id":"feat-001","name":"X","description":"старое","state":"active","affected_files":["a.ts"],
"provenance":{"origin":"owner-msg","source_ref":{"kind":"session","ref":"s"},"captured_at":"2026-07-10T00:00:00Z","by":"owner","seq":1}}]}}
JSON
printf '%s\n' '{"v":1,"at":"2026-07-10T01:00:00Z","feat":"feat-001","seq":1,"op":"ADDED","by":"owner"}' > "$LOG"
git add -A; git commit -q -m seed 2>/dev/null
SEED="$(git rev-parse HEAD)"

wfeat() {  # $1=description $2=seq $3=affected(json) -> перезаписать feature_list
  cat > feature_list.json <<JSON
{"version":"8.0","features":{"active_list":[{"id":"feat-001","name":"X","description":"$1","state":"active","affected_files":$3,
"provenance":{"origin":"owner-msg","source_ref":{"kind":"session","ref":"s"},"captured_at":"2026-07-10T00:00:00Z","by":"owner","seq":$2}}]}}
JSON
}

echo "Провенанс правка бизнес-поля (L3-F4) — сценарии:"

# 1. Бизнес-поле (description) изменено БЕЗ события лога → reject
wfeat "новое" 1 '["a.ts"]'; git add feature_list.json
if git commit -q -m "silent edit" 2>/dev/null; then bad "1. description без события → reject" "коммит прошёл"; else ok "1. description изменён без события лога → reject"; fi
git reset -q --hard "$SEED" 2>/dev/null

# 2. Бизнес-поле изменено + покрывающее событие лога → pass
wfeat "новое" 2 '["a.ts"]'
printf '%s\n' '{"v":1,"at":"2026-07-10T02:00:00Z","feat":"feat-001","seq":2,"op":"MODIFIED","by":"owner","changes":{"description":{"to":"новое","from_hash":"sha256:x"}}}' >> "$LOG"
git add -A
if git commit -q -m "logged edit" 2>/dev/null; then ok "2. description + событие changes.description → pass"; else bad "2. covered → pass" "reject покрытой правки"; fi
git reset -q --hard "$SEED" 2>/dev/null

# 3. Техническое поле (affected_files) изменено БЕЗ события → pass (вне провенанса)
wfeat "старое" 1 '["a.ts","b.ts"]'; git add feature_list.json
if git commit -q -m "technical edit" 2>/dev/null; then ok "3. affected_files без события → pass (техническое, вне провенанса)"; else bad "3. техническое → pass" "reject технической правки"; fi
git reset -q --hard "$SEED" 2>/dev/null

# 4. state→rejected + событие op=REJECTED → pass (op покрывает state)
wfeat "старое" 2 '["a.ts"]'
python3 -c "import json;d=json.load(open('feature_list.json'));d['features']['active_list'][0]['state']='rejected';json.dump(d,open('feature_list.json','w'))"
printf '%s\n' '{"v":1,"at":"2026-07-10T03:00:00Z","feat":"feat-001","seq":2,"op":"REJECTED","by":"owner"}' >> "$LOG"
git add -A
if git commit -q -m "reject via op" 2>/dev/null; then ok "4. state→rejected + op=REJECTED → pass (op покрывает state)"; else bad "4. op покрывает state → pass" "reject"; fi
git reset -q --hard "$SEED" 2>/dev/null

# 5. lifecycle active→passing БЕЗ события → pass (C3-фикс: статус реализации ≠ правка требования)
wfeat "старое" 1 '["a.ts"]'
python3 -c "import json;d=json.load(open('feature_list.json'));d['features']['active_list'][0]['state']='passing';json.dump(d,open('feature_list.json','w'))"
git add feature_list.json
if git commit -q -m "verify → passing" 2>/dev/null; then ok "5. lifecycle active→passing без события → pass (C3: /verify не встаёт)"; else bad "5. lifecycle → pass" "reject прогресса реализации"; fi
git reset -q --hard "$SEED" 2>/dev/null

# 6. lifecycle active→done БЕЗ события → pass (как /ship)
wfeat "старое" 1 '["a.ts"]'
python3 -c "import json;d=json.load(open('feature_list.json'));d['features']['active_list'][0]['state']='done';json.dump(d,open('feature_list.json','w'))"
git add feature_list.json
if git commit -q -m "ship → done" 2>/dev/null; then ok "6. lifecycle active→done без события → pass (C3: /ship не встаёт)"; else bad "6. lifecycle → pass" "reject"; fi
git reset -q --hard "$SEED" 2>/dev/null

# 7. терминальная судьба active→rejected БЕЗ события → reject (судьба требования требует историю)
wfeat "старое" 1 '["a.ts"]'
python3 -c "import json;d=json.load(open('feature_list.json'));d['features']['active_list'][0]['state']='rejected';json.dump(d,open('feature_list.json','w'))"
git add feature_list.json
if git commit -q -m "silent reject" 2>/dev/null; then bad "7. rejected без события → reject" "коммит прошёл"; else ok "7. state→rejected без события → reject (терминальная судьба защищена)"; fi
git reset -q --hard "$SEED" 2>/dev/null

cd /; rm -rf "$REPO"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
