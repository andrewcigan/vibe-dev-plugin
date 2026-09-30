#!/bin/bash
# Vibe Dev v9.0.2 — чекпоинт после ротации не переписывает стабы, и его результат проходит
# сторож коммитов (блок 5, правка требования без события истории).
#
# Живой случай (30.09.2026, реестр проекта): второй /checkpoint после ротации напечатал
# «recover: восстановлено голов 24», и сторож коммитов отказал: у feat-514…518 «изменены
# description без нового события лога». Причина — record-change.sh --recover: у стаба ротации
# головы истории нет (она уехала в архив вместе с телом), recover считал её seq=-1 и переигрывал
# в стаб ВЕСЬ журнал фичи — описание, инвариант, проверки, файлы. Тело в архиве при этом было
# актуально. Выйти удалось только откатом реестра — вместе с ротацией.
#
# Здесь: (А) recover сверяет стаб с телом в архиве и не трогает актуальный; запись без головы
# вообще не трогает — сверять не с чем; стаб, реально отставший после ротации, догоняет ровно
# на недостающие события. (Б) Настоящие checkpoint.sh + сторож коммитов на git-репозитории:
# второй чекпоинт после ротации проходит коммит. (В) Писатель заводит голову ДО записи события,
# поэтому обрыв на записи никогда не оставляет журнал впереди безголовой записи. (Г) Повтор
# события после обрыва догоняет реестр. (Д) Голова seq 0 от миграции не заставляет переигрывать
# стаб; изменение без значения не откатывает поле; стаб без тела и битый архив — не трогаем.
# (Е) Миграция ставит голову по журналу. Г–Е найдены критиком со свежим контекстом.
# Запуск: bash tests/hooks/test-checkpoint-stub-recover.sh
set -u
unset VIBE_PROJECT_ROOT   # иначе резолвер уведёт скрипты в проект из окружения

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RC="$PLUGIN_ROOT/scripts/record-change.sh"
ARCHSH="$PLUGIN_ROOT/scripts/archive-features.sh"
CP="$PLUGIN_ROOT/scripts/checkpoint.sh"
HOOK_SRC="$PLUGIN_ROOT/templates/git-pre-commit.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "ожидал [$2] получил [$3]"; fi; }

# Реестр по образцу живого: feat-001 завершена, её история — два события писателя плагина
# (описание, затем проверки); feat-002 живая и БЕЗ головы истории, её события пишет другой
# писатель (у него поля требования — from/to), голову он сознательно не заводит.
seed() {  # $1 = каталог проекта
  mkdir -p "$1/.harness"
  cat > "$1/feature_list.json" <<'JSON'
{"version":"8.0","features":{"done":[
{"id":"feat-001","name":"Экран сообщений","description":"описание v2","business_invariant":"инвариант","size_estimate":"M","state":"passing",
 "evidence":{"layer_2_runtime_at":"2026-09-22T00:00:00Z"},"verification":{"layer_2_runtime":["pnpm tsx e2e/a.ts"]},
 "provenance":{"origin":"dialog","source_ref":{"kind":"session","ref":"s"},"captured_at":"2026-09-21","by":"agent","seq":2,"rev_cache":{"seq":2,"at":"2026-09-22T08:06:03Z"}}}],
"captured":[
{"id":"feat-002","name":"Живая без головы","description":"как есть","state":"captured"}]}}
JSON
  cat > "$1/.harness/provenance-log.jsonl" <<'LOG'
{"v":1,"at":"2026-09-22T06:06:31Z","feat":"feat-001","seq":1,"op":"MODIFIED","by":"agent","changes":{"description":{"to":"описание v2","from_hash":"sha256:x"}}}
{"v":1,"at":"2026-09-22T08:06:03Z","feat":"feat-001","seq":2,"op":"MODIFIED","by":"agent","changes":{"verification":{"to":{"layer_2_runtime":["pnpm tsx e2e/a.ts"]},"from_hash":"sha256:y"}}}
{"v":1,"at":"2026-09-23T13:45:24Z","feat":"feat-002","seq":1,"op":"ADDED","by":"agent","why":"заведена"}
{"v":1,"at":"2026-09-30T14:13:00Z","feat":"feat-002","seq":2,"op":"MODIFIED","by":"agent","changes":{"description":{"from":"было","to":"как есть"}}}
LOG
}
stub() {  # $1 = каталог, $2 = python-выражение над стабом feat-001 (s)
  python3 -c "import json;d=json.load(open('$1/feature_list.json'));s=[f for b in d['features'].values() for f in b if f.get('id')=='feat-001'][0];print($2)"
}
rec() {  # $1 = каталог, $2 = python-выражение над записью feat-002 (f)
  python3 -c "import json;d=json.load(open('$1/feature_list.json'));f=[x for b in d['features'].values() for x in b if x.get('id')=='feat-002'][0];print($2)"
}

echo "А. record-change --recover против стабов ротации и записей без головы"

P="$(mktemp -d)"; seed "$P"
bash "$ARCHSH" "$P" >/dev/null 2>&1
eq "А0. ротация сделала feat-001 стабом без полей требования" "True" "$(stub "$P" "'evidence_hash' in s and 'description' not in s")"
cp "$P/feature_list.json" "$P/before.json"
OUT="$(bash "$RC" --recover --project "$P" 2>&1)"
if cmp -s "$P/before.json" "$P/feature_list.json"; then
  ok "А1. стаб с актуальным телом в архиве и безголовая запись: реестр не изменён ни на байт"
else
  bad "А1. реестр не изменён" "recover переписал: стаб description=$(stub "$P" "s.get('description')"), у feat-002 provenance=$(rec "$P" "'provenance' in f")"
fi
eq "А2. стаб не получил описание из журнала" "False" "$(stub "$P" "'description' in s")"
eq "А3. безголовой записи голова не навешена" "False" "$(rec "$P" "'provenance' in f")"
if printf '%s' "$OUT" | grep -q "восстановлено голов 0" && printf '%s' "$OUT" | grep -q "без головы истории 1"; then
  ok "А4. отчёт честный: восстановлено 0, запись без головы названа отдельным числом"
else
  bad "А4. честный отчёт recover" "$OUT"
fi

# Стаб реально отстал: после ротации писатель дописал событие seq=3, а запись реестра не успел
# (обрыв). Догнать нужно ровно на seq=3 — туда же, куда пишет писатель (в стаб), без старых событий.
printf '%s\n' '{"v":1,"at":"2026-09-30T20:00:00Z","feat":"feat-001","seq":3,"op":"MODIFIED","by":"owner","changes":{"description":{"to":"описание v3","from_hash":"sha256:z"}}}' >> "$P/.harness/provenance-log.jsonl"
bash "$RC" --recover --project "$P" >/dev/null 2>&1
eq "А5. отставший стаб догнал недостающее событие (description=v3)" "описание v3" "$(stub "$P" "s.get('description')")"
eq "А6. голова стаба = seq 3" "3" "$(stub "$P" "(s.get('provenance') or {}).get('seq')")"
eq "А7. старые события (проверки, seq 2) в стаб не переиграны — они уже в теле архива" "False" "$(stub "$P" "'verification' in s")"
rm -rf "$P"

# Голова тела в архиве отстаёт только по счёту: писатель записал событие и поле, но голову не
# сдвинул (так вела себя первая версия проектного писателя 23.09 — feat-530/531 живого реестра).
# Данные события уже в теле, переносить в стаб нечего: стаб обязан остаться нетронутым.
P="$(mktemp -d)"; seed "$P"
python3 -c "
import json;p='$P/feature_list.json';d=json.load(open(p));f=d['features']['done'][0]
f['provenance']['seq']=1;f['provenance']['rev_cache']['seq']=1;json.dump(d,open(p,'w'),ensure_ascii=False)"
python3 -c "
import json;p='$P/.harness/provenance-log.jsonl';ls=[json.loads(l) for l in open(p) if l.strip()]
for e in ls:
    if e['feat']=='feat-001' and e['seq']==2: e['changes']={'description':{'to':'описание v2','from_hash':'sha256:v'}}
open(p,'w').write(''.join(json.dumps(e,ensure_ascii=False)+'\n' for e in ls))"
bash "$ARCHSH" "$P" >/dev/null 2>&1
cp "$P/feature_list.json" "$P/before.json"
bash "$RC" --recover --project "$P" >/dev/null 2>&1
if cmp -s "$P/before.json" "$P/feature_list.json"; then
  ok "А8. голова тела отстала только по счёту, данные уже в теле — стаб не тронут"
else
  bad "А8. стаб с отставшей по счёту головой" "стаб стал: $(stub "$P" "sorted(s.keys())")"
fi
rm -rf "$P"

echo ""
echo "Б. настоящие checkpoint.sh + сторож коммитов: второй чекпоинт после ротации"

REPO="$(mktemp -d)"; seed "$REPO"; cd "$REPO" || exit 1
git init -q; git config user.email t@t.t; git config user.name t
cat > SESSION.md <<'MD'
# Session Log
## Current State
**Last Updated**: 2026-09-30 20:00
**Active Feature**: нет активной (граница волны)
MD
git add -A; git commit -q -m seed 2>/dev/null
mkdir -p .git/hooks; cp "$HOOK_SRC" .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit

bash "$CP" "$REPO" >/dev/null 2>&1
eq "Б0. первый чекпоинт вынес feat-001 в архив" "True" "$(stub "$REPO" "'evidence_hash' in s")"
git add -A
if OUT="$(git commit -q -m "checkpoint 1: ротация" 2>&1)"; then ok "Б1. коммит первого чекпоинта (ротация) проходит"; else bad "Б1. коммит ротации" "$OUT"; fi

OUT2="$(bash "$CP" "$REPO" 2>&1)"
if git diff --quiet -- feature_list.json feature_list.archive.json; then
  ok "Б2. второй чекпоинт не тронул реестр и архив"
else
  bad "Б2. реестр после второго чекпоинта" "$(git diff --stat -- feature_list.json feature_list.archive.json | tail -1); вывод: $(printf '%s' "$OUT2" | grep 'провенанс')"
fi
# Агент на чекпоинте переписывает Current State — коммит не пустой при любой скорости прогона
# (иначе два чекпоинта в одну секунду дают одинаковую резервную копию и коммитить нечего).
printf '**Checkpoint**: второй за сессию\n' >> SESSION.md
git add -A
if OUT="$(git commit -q -m "checkpoint 2" 2>&1)"; then
  ok "Б3. коммит второго чекпоинта проходит сторож (блок 5 — правка требования без события)"
else
  bad "Б3. коммит второго чекпоинта" "$(printf '%s' "$OUT" | grep -E 'feat-|ОСТАНОВЛЕН' | head -3)"
fi
cd /; rm -rf "$REPO"

echo ""
echo "В. писатель заводит голову безголовой записи ДО записи события"

P="$(mktemp -d)"; seed "$P"
LOG="$P/.harness/provenance-log.jsonl"
# Обрыв на дописывании журнала (журнал только для чтения): событие не записалось. Голова уже
# должна стоять и быть равна журналу — тогда обрыв МЕЖДУ журналом и реестром оставляет
# «голова позади на одно событие», а это recover чинит.
chmod 444 "$LOG"
printf '{"feat":"feat-002","op":"MODIFIED","by":"owner","changes":{"description":{"to":"новое"}},"change_id":"w1"}' | bash "$RC" --project "$P" >/dev/null 2>&1
chmod 644 "$LOG"
eq "В1. журнал не принял событие (обрыв смоделирован)" "4" "$(grep -c . "$LOG")"
eq "В2. голова заведена до записи события и равна журналу (seq 2)" "2" "$(rec "$P" "(f.get('provenance') or {}).get('seq')")"
eq "В3. поле требования не тронуто — события нет" "как есть" "$(rec "$P" "f.get('description')")"
OUT="$(bash "$RC" --recover --project "$P" 2>&1)"
if printf '%s' "$OUT" | grep -q "восстановлено голов 0"; then ok "В4. после обрыва журнал и голова сходятся — чинить нечего"; else bad "В4. recover после обрыва" "$OUT"; fi
printf '{"feat":"feat-002","op":"MODIFIED","by":"owner","changes":{"description":{"to":"новое"}},"change_id":"w1"}' | bash "$RC" --project "$P" >/dev/null 2>&1
eq "В5. повтор после обрыва записал событие seq 3" "3" "$(python3 -c "import json;print(json.loads(open('$LOG').readlines()[-1])['seq'])")"
eq "В6. голова = seq 3, поле применено" "3 новое" "$(rec "$P" "str((f.get('provenance') or {}).get('seq'))+' '+f.get('description')")"
rm -rf "$P"

echo ""
echo "Г. повтор события после обрыва догоняет реестр, а не сообщает ложный успех"

# Обрыв между журналом и реестром: событие seq=3 в журнале, реестр его не получил. Агент повторяет
# то же событие (тот же change_id). Раньше ответ был «уже в логе, пропуск» с кодом 0 — реестр так
# и оставался позади, коммит проходил, а следующий чекпоинт применял уже закоммиченное событие,
# и сторож отвергал коммит: событие не новое.
P="$(mktemp -d)"; seed "$P"
python3 -c "
import json;p='$P/feature_list.json';d=json.load(open(p))
d['features']['captured'][0]['provenance']={'origin':'dialog','source_ref':{'kind':'session','ref':'s'},'captured_at':'2026-09-23','by':'agent','seq':2}
json.dump(d,open(p,'w'),ensure_ascii=False)"
printf '%s\n' '{"v":1,"at":"2026-09-30T21:00:00Z","feat":"feat-002","seq":3,"op":"MODIFIED","change_id":"c9","by":"owner","changes":{"description":{"to":"после обрыва","from_hash":"sha256:x"}}}' >> "$P/.harness/provenance-log.jsonl"
printf '{"feat":"feat-002","op":"MODIFIED","by":"owner","changes":{"description":{"to":"после обрыва"}},"change_id":"c9"}' | bash "$RC" --project "$P" >/dev/null 2>&1
eq "Г1. повтор догнал реестр: поле применено, голова seq 3" "после обрыва 3" "$(rec "$P" "f.get('description')+' '+str(f['provenance'].get('seq'))")"
eq "Г2. журнал не получил дубль события" "5" "$(grep -c . "$P/.harness/provenance-log.jsonl")"
rm -rf "$P"

echo ""
echo "Д. голова от миграции, изменения без значения, стаб без тела"

# Проектный писатель отмечает технические поля как {"changed": true} — без значения. Если раньше
# писатель плагина записал то же поле со значением, последнее «to» в журнале устарело. Голова
# seq 0 (так её ставила миграция) заставляла переигрывать с начала — и откатывала поле к старому.
P="$(mktemp -d)"; seed "$P"
python3 - "$P" <<'PY'
import json,sys
P=sys.argv[1]; p=P+"/feature_list.json"; d=json.load(open(p))
f=d["features"]["done"][0]; f["affected_files"]=["new.ts"]; f["provenance"]["seq"]=3; f["provenance"]["rev_cache"]["seq"]=3
live={"id":"feat-003","name":"Живая с головой от миграции","description":"д","state":"captured","verification":{"v":"новая"},
      "provenance":{"origin":"inference","source_ref":{"kind":"unknown","ref":"retro-migration"},"captured_at":"2026-09-01","by":"agent","seq":0}}
d["features"]["captured"].append(live); json.dump(d,open(p,"w"),ensure_ascii=False)
lp=P+"/.harness/provenance-log.jsonl"
with open(lp,"a") as w:
    for e in ({"v":1,"at":"2026-09-22T09:00:00Z","feat":"feat-001","seq":3,"op":"MODIFIED","by":"owner","why":"пересобрано","changes":{"affected_files":{"changed":True}}},
              {"v":1,"at":"2026-09-20T09:00:00Z","feat":"feat-003","seq":1,"op":"MODIFIED","by":"agent","changes":{"verification":{"to":{"v":"старая"},"from_hash":"sha256:a"}}},
              {"v":1,"at":"2026-09-24T09:00:00Z","feat":"feat-003","seq":2,"op":"MODIFIED","by":"owner","why":"переписано","changes":{"verification":{"changed":True}}}):
        w.write(json.dumps(e,ensure_ascii=False)+"\n")
PY
# у feat-001 до ротации поле affected_files записано событием со значением (seq 1 → старое)
python3 -c "
import json;p='$P/.harness/provenance-log.jsonl';ls=[json.loads(l) for l in open(p) if l.strip()]
ls[0]['changes']['affected_files']={'to':['old.ts'],'from_hash':'sha256:o'}
open(p,'w').write(''.join(json.dumps(e,ensure_ascii=False)+'\n' for e in ls))"
bash "$ARCHSH" "$P" >/dev/null 2>&1
# стаб получил голову seq 0, как от старой миграции
python3 -c "
import json;p='$P/feature_list.json';d=json.load(open(p));s=[f for b in d['features'].values() for f in b if f.get('id')=='feat-001'][0]
s['provenance']={'origin':'inference','source_ref':{'kind':'unknown','ref':'retro-migration'},'captured_at':'2026-09-01','by':'agent','seq':0}
json.dump(d,open(p,'w'),ensure_ascii=False)"
cp "$P/feature_list.json" "$P/before.json"
bash "$RC" --recover --project "$P" >/dev/null 2>&1
eq "Д1. стаб с головой seq 0 от миграции: тело в архиве актуально — стаб не тронут" "True" \
   "$(python3 -c "import json;a=json.load(open('$P/before.json'));b=json.load(open('$P/feature_list.json'));g=lambda d:[f for x in d['features'].values() for f in x if f.get('id')=='feat-001'][0];print(g(a)==g(b))")"
eq "Д2. живая запись с головой seq 0: поле, изменённое без значения, не откачено к старому" "новая" \
   "$(python3 -c "import json;d=json.load(open('$P/feature_list.json'));f=[x for b in d['features'].values() for x in b if x.get('id')=='feat-003'][0];print(f['verification']['v'])")"
rm -rf "$P"

# Архив потерял тело стаба (или файл архива битый): сверять не с чем — стаб не трогаем и говорим
# об этом отдельно; целостность архива проверит сторож коммитов (блок 6).
P="$(mktemp -d)"; seed "$P"
bash "$ARCHSH" "$P" >/dev/null 2>&1
python3 -c "
import json;p='$P/feature_list.json';d=json.load(open(p));s=[f for b in d['features'].values() for f in b if f.get('id')=='feat-001'][0]
s['provenance']={'origin':'inference','source_ref':{'kind':'unknown','ref':'retro-migration'},'captured_at':'2026-09-01','by':'agent','seq':0}
json.dump(d,open(p,'w'),ensure_ascii=False)"
printf '{"version":"8.0","archived":[]}\n' > "$P/feature_list.archive.json"
cp "$P/feature_list.json" "$P/before.json"
OUT="$(bash "$RC" --recover --project "$P" 2>&1)"
if cmp -s "$P/before.json" "$P/feature_list.json"; then ok "Д3. стаб без тела в архиве не тронут"; else bad "Д3. стаб без тела" "стаб стал: $(stub "$P" "sorted(s.keys())")"; fi
if printf '%s' "$OUT" | grep -q "без тела в архиве 1"; then ok "Д4. отчёт называет стаб без тела отдельно"; else bad "Д4. отчёт про стаб без тела" "$OUT"; fi
printf '{битый' > "$P/feature_list.archive.json"
if OUT="$(bash "$RC" --recover --project "$P" 2>&1)" && cmp -s "$P/before.json" "$P/feature_list.json"; then
  ok "Д5. битый архив: recover не падает и стаб не трогает"
else
  bad "Д5. битый архив" "$OUT"
fi
rm -rf "$P"

echo ""
echo "Е. миграция провенанса ставит голову по журналу, а не seq 0"

# Голова seq 0 у записи, чьи события уже есть в журнале, утверждает «ничего не учтено» — и
# отправляет recover переигрывать всё с начала. Честная реконструкция: запись учла свой журнал.
P="$(mktemp -d)"; seed "$P"
python3 -c "
import json;p='$P/feature_list.json';d=json.load(open(p))
d['features']['captured'].append({'id':'feat-004','name':'Без событий','description':'x','state':'captured'})
json.dump(d,open(p,'w'),ensure_ascii=False)"
bash "$PLUGIN_ROOT/scripts/migrate-provenance.sh" "$P" >/dev/null 2>&1
eq "Е1. запись с двумя событиями в журнале: голова = seq 2" "2" "$(rec "$P" "f['provenance'].get('seq')")"
eq "Е2. запись без событий: голова = seq 0, как раньше" "0" \
   "$(python3 -c "import json;d=json.load(open('$P/feature_list.json'));f=[x for b in d['features'].values() for x in b if x.get('id')=='feat-004'][0];print(f['provenance'].get('seq'))")"
cp "$P/feature_list.json" "$P/before.json"
bash "$RC" --recover --project "$P" >/dev/null 2>&1
if cmp -s "$P/before.json" "$P/feature_list.json"; then ok "Е3. после миграции recover чинить нечего"; else bad "Е3. recover после миграции" "реестр изменён"; fi
rm -rf "$P"

echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
