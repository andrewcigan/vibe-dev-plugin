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

# --- Ротация настоящим scripts/archive-features.sh (v9.0.1) ---
# Ротация заменяет тело завершённой фичи стабом {id,name,state,evidence_ref,history_ref,
# evidence_hash} и уносит тело в feature_list.archive.json. Требование при этом не изменилось,
# оно ПЕРЕЕХАЛО. Живой случай: реестр проекта не разгружался две недели, потому что гейт сравнивал
# прошлую запись со стабом, где полей требования нет, и видел «правку без события».
echo ""
echo "Ротация в архив против гейта правки требования:"
ARCHSH="$PLUGIN_ROOT/scripts/archive-features.sh"
rot_repo() {  # свежий репозиторий: feat-001 завершена (как в живом реестре), feat-002 в работе
  RREPO="$(mktemp -d)"; cd "$RREPO" || exit 1
  git init -q; git config user.email t@t.t; git config user.name t
  mkdir -p .harness .git/hooks
  cp "$HOOK_SRC" .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
  cat > feature_list.json <<'JSON'
{"version":"8.0","features":{"done":[{"id":"feat-001","name":"X","description":"старое","size_estimate":"M","business_invariant":"инвариант","state":"passing","evidence":{"layer_2_runtime_at":"2026-07-10T00:00:00Z"},
"provenance":{"origin":"owner-msg","source_ref":{"kind":"session","ref":"s"},"captured_at":"2026-07-10T00:00:00Z","by":"owner","seq":1}}],
"active_list":[{"id":"feat-002","name":"Y","description":"в работе","state":"active","affected_files":["b.ts"],
"provenance":{"origin":"owner-msg","source_ref":{"kind":"session","ref":"s"},"captured_at":"2026-07-10T00:00:00Z","by":"owner","seq":1}}]}}
JSON
  printf '%s\n' '{"v":1,"at":"2026-07-10T01:00:00Z","feat":"feat-001","seq":1,"op":"ADDED","by":"owner"}' \
                '{"v":1,"at":"2026-07-10T01:00:00Z","feat":"feat-002","seq":1,"op":"ADDED","by":"owner"}' > "$LOG"
  git add -A; git commit -q -m seed 2>/dev/null
}
rot_done() { cd /; rm -rf "$RREPO"; }
setf() {  # $1=python-выражение над f (feat-001 в горячем файле)
  python3 -c "import json;d=json.load(open('feature_list.json'));f=[x for x in d['features']['done'] if x['id']=='feat-001'][0];$1;json.dump(d,open('feature_list.json','w'),ensure_ascii=False)"
}

# а. Ротация без правок → коммит проходит (перенос, не правка требования)
rot_repo
bash "$ARCHSH" "$RREPO" >/dev/null 2>&1
ROTATED="$(python3 -c "import json;d=json.load(open('feature_list.json'));a=json.load(open('feature_list.archive.json'));f=[x for x in d['features']['done'] if x['id']=='feat-001'][0];print('evidence_hash' in f and 'description' not in f and any(x.get('id')=='feat-001' for x in a['archived']))" 2>/dev/null)"
if [ "$ROTATED" = "True" ]; then ok "а0. archive-features.sh вынес тело: стаб в горячем, тело в архиве"; else bad "а0. ротация произошла" "стаба/тела нет — сценарий не проверяет ничего"; fi
git add -A
if OUT="$(git commit -q -m "rotate" 2>&1)"; then ok "а. ротация настоящим archive-features.sh → коммит проходит"; else bad "а. ротация → pass" "$(printf '%s' "$OUT" | grep 'feat-001' | head -1)"; fi
rot_done

# б. Описание поправлено и тут же унесено в архив, события нет → reject (правка под видом ротации)
rot_repo
setf "f['description']='новое'"
bash "$ARCHSH" "$RREPO" >/dev/null 2>&1; git add -A
if OUT="$(git commit -q -m "edit+rotate" 2>&1)"; then bad "б. правка в архивном теле без события → reject" "коммит прошёл"; else ok "б. архивное тело с изменённым description без события → reject"; fi
LINE="$(printf '%s\n' "$OUT" | grep 'feat-001' | head -1)"
if printf '%s' "$LINE" | grep -q 'description' && ! printf '%s' "$LINE" | grep -q 'size_estimate'; then
  ok "б'. в отказе названо ровно изменённое поле (description), а не поля, которых у стаба нет"
else
  bad "б'. отказ называет изменённое поле" "строка отказа: [$LINE]"
fi
rot_done

# б2. Та же правка, но с событием лога (как делает record-change.sh) → pass
rot_repo
setf "f['description']='новое';f['provenance']['seq']=2"
printf '%s\n' '{"v":1,"at":"2026-07-10T02:00:00Z","feat":"feat-001","seq":2,"op":"MODIFIED","by":"owner","changes":{"description":{"to":"новое","from_hash":"sha256:x"}}}' >> "$LOG"
bash "$ARCHSH" "$RREPO" >/dev/null 2>&1; git add -A
if OUT="$(git commit -q -m "logged edit+rotate" 2>&1)"; then ok "б2. правка с событием лога + ротация → pass"; else bad "б2. покрытая правка + ротация → pass" "$(printf '%s' "$OUT" | grep 'feat-001' | head -1)"; fi
rot_done

# б3. Тихая отмена (rejected) и сразу в архив → reject: терминальная судьба под видом ротации
rot_repo
setf "f['state']='rejected'"
bash "$ARCHSH" "$RREPO" >/dev/null 2>&1; git add -A
if git commit -q -m "reject+rotate" 2>/dev/null; then bad "б3. отмена под видом ротации → reject" "коммит прошёл"; else ok "б3. тихая отмена (rejected) и сразу в архив → reject"; fi
rot_done

# е. Стаб без тела в архиве → reject, и отказ даёт блок архива (6), а не ложное «изменены поля»
rot_repo
bash "$ARCHSH" "$RREPO" >/dev/null 2>&1
python3 -c "import json;a=json.load(open('feature_list.archive.json'));a['archived']=[];json.dump(a,open('feature_list.archive.json','w'))"
git add -A
if OUT="$(git commit -q -m "rotate, body lost" 2>&1)"; then bad "е. стаб без тела → reject" "коммит прошёл"; else ok "е. стаб без тела в архиве → reject"; fi
if printf '%s' "$OUT" | grep 'feat-001' | grep -q 'тела в archive.json нет'; then ok "е'. причину называет проверка архива, гейт правки её не подменяет"; else bad "е'. причина — нет тела" "$(printf '%s' "$OUT" | grep 'feat-001' | head -1)"; fi
rot_done

# ж. Прошлая и новая записи — обе стабы: поведение прежнее
rot_repo
bash "$ARCHSH" "$RREPO" >/dev/null 2>&1; git add -A; git commit -q --no-verify -m "rotated (подготовка)" 2>/dev/null
python3 -c "import json;d=json.load(open('feature_list.json'));d['features']['active_list'][0]['affected_files']=['b.ts','c.ts'];json.dump(d,open('feature_list.json','w'),ensure_ascii=False)"
git add feature_list.json
if git commit -q -m "technical edit next to stub" 2>/dev/null; then ok "ж1. стаб не менялся, правка соседней фичи → pass"; else bad "ж1. стаб→стаб без изменений → pass" "reject"; fi
python3 -c "import json;d=json.load(open('feature_list.json'));[f for f in d['features']['done'] if f['id']=='feat-001'][0]['name']='X2';json.dump(d,open('feature_list.json','w'),ensure_ascii=False)"
git add feature_list.json
if git commit -q -m "rename stub silently" 2>/dev/null; then bad "ж2. тихое переименование стаба → reject" "коммит прошёл"; else ok "ж2. тихое переименование стаба → reject (как было)"; fi
rot_done

echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
