#!/bin/bash
# Сторож рамок фичи (WIP=1 scope) находит активную фичу по её состоянию (v9.0.4).
#
# ЗАЧЕМ. Сторож читал только верхнее поле «active» журнала фич, а его не ставил и не снимал ни один
# писатель состояния. Замер 02.10.2026 на живом проекте: фича стояла в state active, поле было
# пустым — сторож выходил на первой строке и не проверил ни одного коммита. Обратный случай
# (08.07.2026): поле осталось от закрытой фичи, и сторож блокировал коммит по фиче, которой нет.
# Теперь источник один — state самих записей.
#
# Ожив, сторож не должен останавливать нормальную работу. Замер истории того же проекта
# (июль–октябрь 2026, 199 коммитов при активной работе): старый список разрешённого остановил бы 68 —
# 26 в волнах с несколькими фичами в active и десятки на служебных файлах процесса (журнал истории
# реестра, передача сессии, план самой фичи). Эти случаи здесь закреплены как проходящие.
#
# Формы журнала — как на живом проекте: записи всех состояний лежат в разделе captured, верхнее
# поле null. Путь проекта — с пробелом, кириллицей и апострофом.
#
# Прежний код проверить: SCOPE_UNDER_TEST=<путь к старой копии> bash tests/hooks/test-scope-active-from-state.sh
# Запуск: bash tests/hooks/test-scope-active-from-state.sh
set -u
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCOPE="${SCOPE_UNDER_TEST:-$PLUGIN_ROOT/hooks/pre-commit-scope.sh}"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }
unset VIBE_PROJECT_ROOT VIBE_DEV_PROFILE CLAUDE_PLUGIN_ROOT HOOK_PAYLOAD 2>/dev/null || true
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

BASE="$(mktemp -d)"; trap 'cd /; rm -rf "$BASE"' EXIT
REPO="$BASE/проект с пробелом и 'кавычкой'"
mkdir -p "$REPO/src/feat" "$REPO/src/other" "$REPO/docs/шаблоны" "$REPO/.harness" "$REPO/.session-state" \
         "$REPO/docs/changes/feat-002" "$REPO/docs/changes/feat-001" "$REPO/docs/reports"
( cd "$REPO" && git init -q && git config user.email t@t && git config user.name t \
  && echo base > README.md && git add README.md && git commit -qm base )
echo a > "$REPO/src/feat/a.ts"; echo b > "$REPO/src/other/b.ts"; echo c > "$REPO/outside.txt"
echo e > "$REPO/.harness/provenance-log.jsonl"; echo n > "$REPO/.session-state/next-prompt.txt"
echo p > "$REPO/docs/changes/feat-002/proposal.md"; echo q > "$REPO/docs/changes/feat-001/proposal.md"
echo r > "$REPO/docs/reports/otchet.html"; echo x > "$REPO/docs/шаблоны/Шаблон загрузки.xlsx"
echo y > "$REPO/docs/шаблоны/Чужой файл.txt"

journal() { printf '%s\n' "$1" > "$REPO/feature_list.json"; }
# stage <файлы…>: в индексе ровно эти файлы
stage() { ( cd "$REPO" && git reset -q && git add -- "$@" ); }
run_scope() { OUT="$( cd "$REPO" && bash "$SCOPE" 2>&1 )"; RC=$?; }
expect() { # expect <имя> <код> [<обязательный фрагмент вывода>]
  if [ "$RC" != "$2" ]; then bad "$1" "код $RC, ожидал $2; вывод: $(printf '%s' "$OUT" | head -4 | tr '\n' ' ')"; return; fi
  if [ -n "${3:-}" ] && ! printf '%s' "$OUT" | grep -qF -- "$3"; then bad "$1" "нет «$3» в выводе: $(printf '%s' "$OUT" | head -4 | tr '\n' ' ')"; return; fi
  ok "$1"
}

ONE_ACTIVE='{"active":null,"wip_limit":1,"features":{"captured":[
 {"id":"feat-001","state":"passing","affected_files":["src/other/b.ts"]},
 {"id":"feat-002","state":"active","affected_files":["src/feat/a.ts"]}],"active_list":[],"done":[]}}'

echo "Сторож рамок фичи: активная фича — по state записи:"

journal "$ONE_ACTIVE"; stage outside.txt; run_scope
expect "1. поле active пустое, фича в state active: файл вне рамок → блок" 1 "SCOPE LEAK"
printf '%s' "$OUT" | grep -qF "feat-002" && ok "1b. в отказе названа активная фича" || bad "1b. в отказе названа активная фича" "$OUT"

stage src/feat/a.ts; run_scope
expect "2. файл в рамках активной фичи → проходит" 0

stage src/feat/a.ts outside.txt; run_scope
expect "3. в рамках + вне рамок в одном коммите → блок" 1 "outside.txt"

# 3c. Отказ читается: рамки — как записаны в журнале (маска не раскрыта в сотни файлов), без
# повторов; файлы вне рамок — выше списка рамок. Замер на живом проекте до правки: 153 строки
# отказа, каждый файл рамок дважды, файл вне рамок — в самом низу.
journal '{"active":null,"features":{"captured":[
 {"id":"feat-002","state":"active","affected_files":["src/feat/a.ts","src/feat/**"]}]}}'
stage outside.txt; run_scope
expect "3c. маска в рамках: файл вне рамок → блок" 1 "SCOPE LEAK"
DUPS="$(printf '%s\n' "$OUT" | grep '^  - ' | sort | uniq -d)"
[ -z "$DUPS" ] && ok "3d. рамки в отказе без повторов" || bad "3d. рамки в отказе без повторов" "$DUPS"
printf '%s' "$OUT" | grep -qxF '  - src/feat/**' && ok "3e. маска показана как записана" || bad "3e. маска показана как записана" "$OUT"
L_OUT="$(printf '%s\n' "$OUT" | grep -n 'outside.txt' | head -1 | cut -d: -f1)"
L_DECL="$(printf '%s\n' "$OUT" | grep -n '^Affected files declared' | cut -d: -f1)"
[ -n "$L_OUT" ] && [ -n "$L_DECL" ] && [ "$L_OUT" -lt "$L_DECL" ] && ok "3f. файл вне рамок — выше списка рамок" \
  || bad "3f. файл вне рамок — выше списка рамок" "строка файла $L_OUT, строка рамок $L_DECL"

journal '{"active":"feat-001","features":{"captured":[
 {"id":"feat-001","state":"passing","affected_files":["src/other/b.ts"]}]}}'
stage outside.txt; run_scope
expect "4. поле active осталось от закрытой фичи, в active никого → не блокирует" 0

TWO_ACTIVE='{"active":null,"features":{"captured":[
 {"id":"feat-001","state":"active","affected_files":["src/other/b.ts"]},
 {"id":"feat-002","state":"active","affected_files":["src/feat/a.ts"]}]}}'
journal "$TWO_ACTIVE"; stage src/feat/a.ts src/other/b.ts; run_scope
expect "5. две фичи в active при пределе 1: файлы обеих → проходит, но говорит вслух" 0 "WIP"
printf '%s' "$OUT" | grep -qF "feat-001 feat-002" && ok "5b. в предупреждении названы обе фичи" || bad "5b. в предупреждении названы обе фичи" "$OUT"
stage outside.txt; run_scope
expect "5c. две фичи в active: файл вне рамок обеих → блок" 1 "SCOPE LEAK"

journal '{"active":null,"wip_limit":2,"features":{"captured":[
 {"id":"feat-001","state":"active","affected_files":["src/other/b.ts"]},
 {"id":"feat-002","state":"active","affected_files":["src/feat/a.ts"]}]}}'
stage src/feat/a.ts src/other/b.ts; run_scope
expect "6. предел 2, две в active: файлы обеих → проходит" 0
[ -z "$OUT" ] && ok "6a. в пределе — без предупреждения" || bad "6a. в пределе — без предупреждения" "$OUT"
stage outside.txt; run_scope
expect "6b. предел 2: файл вне рамок обеих → блок" 1 "SCOPE LEAK"

journal '{"active":null,"features":{"active_list":[{"id":"feat-003","affected_files":["src/feat/a.ts"]}]}}'
stage outside.txt; run_scope
expect "7. старая форма: раздел active_list без поля state → рамки сверяются" 1 "SCOPE LEAK"

journal '{"active":null,"features":{"captured":[{"id":"feat-004","state":"active"}]}}'
stage outside.txt; run_scope
expect "8. активная фича без affected_files → предупреждение, коммит проходит" 0 "не имеет affected_files"

printf '{"active": "feat-002", "features": {' > "$REPO/feature_list.json"
stage outside.txt; run_scope
expect "9. журнал фич не читается → проходит, но говорит вслух" 0 "НЕ проверен"

journal '{"active":null,"features":{"captured":[{"id":"feat-001","state":"passing"}]}}'
stage outside.txt; run_scope
expect "10. ни одной фичи в active → проходит молча" 0
[ -z "$OUT" ] && ok "10b. без лишнего вывода" || bad "10b. без лишнего вывода" "$OUT"

# 12. Служебные файлы процесса — при любой активной фиче (замер истории живого проекта).
journal "$ONE_ACTIVE"
stage .harness/provenance-log.jsonl src/feat/a.ts; run_scope
expect "12a. журнал истории реестра вместе с правкой фичи → проходит" 0
stage .session-state/next-prompt.txt; run_scope
expect "12b. передача сессии (.session-state) → проходит" 0
stage docs/changes/feat-002/proposal.md; run_scope
expect "12c. план самой активной фичи (docs/changes/<её id>) → проходит" 0
stage docs/changes/feat-001/proposal.md; run_scope
expect "12d. план ДРУГОЙ фичи → блок" 1 "docs/changes/feat-001/proposal.md"
stage docs/reports/otchet.html; run_scope
expect "12e. отчёт без записи в .harness/scope-allow → блок" 1 "SCOPE LEAK"
printf '# отчёты владельцу пишутся при любой работе\n\ndocs/reports/*\n' > "$REPO/.harness/scope-allow"
run_scope
expect "12f. маска в .harness/scope-allow → проходит" 0
rm -f "$REPO/.harness/scope-allow"

# 14. Рамка-папка разрешает своё содержимое, а не всё у родителя (прежде docs/changes/feat-528/**
# пускало планы всех фич, supabase/migrations/ — всю supabase/).
J14='{"active":null,"features":{"captured":[
 {"id":"feat-002","state":"active","affected_files":["docs/changes/feat-002/**","src/feat/"]}]}}'
journal "$J14"
stage docs/changes/feat-002/proposal.md src/feat/a.ts; run_scope
expect "14. содержимое объявленных папок (маска и «папка/») → проходит" 0
stage src/other/b.ts; run_scope
expect "14b. соседняя папка у родителя объявленной «src/feat/» → блок" 1 "src/other/b.ts"
journal '{"active":null,"features":{"captured":[
 {"id":"feat-004","state":"active","affected_files":["docs/changes/feat-002/**"]}]}}'
stage docs/changes/feat-001/proposal.md; run_scope
expect "14c. план чужой фичи при рамке «docs/changes/<своя>/**» → блок" 1 "docs/changes/feat-001/proposal.md"

# 13. Имена с пробелом и кириллицей (git по умолчанию выдаёт их экранированными и в кавычках).
journal '{"active":null,"features":{"captured":[
 {"id":"feat-002","state":"active","affected_files":["docs/шаблоны/Шаблон загрузки.xlsx"]}]}}'
stage "docs/шаблоны/Шаблон загрузки.xlsx"; run_scope
expect "13. файл рамок с пробелом и кириллицей → проходит" 0
journal '{"active":null,"features":{"captured":[
 {"id":"feat-002","state":"active","affected_files":["src/feat/a.ts"]}]}}'
stage "docs/шаблоны/Чужой файл.txt"; run_scope
expect "13b. чужой файл с пробелом и кириллицей → блок, имя читаемо" 1 "❌ docs/шаблоны/Чужой файл.txt"

# 11. Настоящий коммит через установленный сторож коммитов (а не прямой вызов проверки).
# Профиль строгости не задан: блок активации не применяется, проверка рамок идёт всегда.
if [ -z "${SCOPE_UNDER_TEST:-}" ]; then
  bash "$PLUGIN_ROOT/scripts/install-precommit.sh" "$REPO" >/dev/null
  journal "$ONE_ACTIVE"; stage outside.txt
  HEAD_BEFORE="$(git -C "$REPO" rev-parse HEAD)"
  OUT="$( cd "$REPO" && git commit -qm probe 2>&1 )"; RC=$?
  if [ "$RC" != 0 ] && [ "$(git -C "$REPO" rev-parse HEAD)" = "$HEAD_BEFORE" ] && printf '%s' "$OUT" | grep -qF "SCOPE LEAK"; then
    ok "11. git commit файла вне рамок через установленный сторож → отказ, HEAD не сдвинулся"
  else
    bad "11. git commit файла вне рамок через установленный сторож → отказ" "код $RC; $(printf '%s' "$OUT" | head -3 | tr '\n' ' ')"
  fi
  stage src/feat/a.ts
  OUT="$( cd "$REPO" && git commit -qm in-scope 2>&1 )"; RC=$?
  [ "$RC" = 0 ] && ok "11b. git commit файла в рамках → проходит" || bad "11b. git commit файла в рамках → проходит" "код $RC; $(printf '%s' "$OUT" | head -3 | tr '\n' ' ')"
fi

echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
