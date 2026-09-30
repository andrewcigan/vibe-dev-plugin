#!/bin/bash
# Подсказки сторожей исполнимы из проекта (v9.0.3).
#
# ЗАЧЕМ. Сторожа отсылали агента к «scripts/record-change.sh» относительным путём, а этот скрипт
# живёт в плагине: в проекте такой команды нет. Замер 30.09.2026: проект 23.09 написал СОБСТВЕННЫЙ
# scripts/record-change.sh, потому что подсказка не исполнялась, — и этот самодельный писатель
# голову истории у записей не заводит (в реестре 14 живых записей без головы при 2–6 событиях в
# журнале); подсказка «--recover» в проекте вызывала уже его, а он такого режима не знает. Тот же
# класс чинили в v9.0.1 для пробника журналов — теперь он повторился в других сторожах.
#
# КАК ПРОВЕРЯЕМ. Команду берём ИЗ ТЕКСТА подсказки, выполняем из корня файловой системы (не из
# папки проекта и не из плагина) и смотрим на последствие: событие в журнале истории, восстановленная
# голова, квитанция прогона, прошедший коммит, завершившийся чекпоинт, замолчавший сторож. Где
# подсказка лечения не даёт (решение за человеком), проверяем только, что её команда исполняется.
# Единственное, что тест подставляет сам, — содержимое события: оно зависит от того, что агент
# меняет, и в подсказке помечено слотом. Пути проектов — с пробелом и кириллицей.
#
# Формы записей без головы истории — как в живом реестре: новая, с журналом событий, стаб ротации.
# Им подсказка обязана дать миграцию (пишет только голову), а не событие ADDED: журнал истории только
# дописывается, и ложное «происхождение неизвестно, занесено сегодня» из него уже не убрать. Команда
# в отказе — одна на весь отказ: повтор в каждой строке раздувал текст в 3,6 раза.
#
# Второй рубеж (сверка журнала фич до и после команды) к диспетчеру сейчас не подключён: фаза
# «после» не вызывается нигде. Его текст проверяем прямым вызовом — чтобы при подключении он был верен.
#
# Последний раздел — сторож класса: ни одна подсказка в выводе сторожей и скриптов, ни одна
# инструкция в навыках, описаниях ролей и правилах не называет файл плагина относительным путём
# или голым именем скрипта.
#
# Глобальные настройки git машины (перенаправленные хуки, обязательная подпись) тест не видит.
#
# Запуск: bash tests/hooks/test-hint-commands.sh
set -u
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }
unset VIBE_PROJECT_ROOT VIBE_DEV_PROFILE CLAUDE_PLUGIN_ROOT HOOK_PAYLOAD 2>/dev/null || true
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

BASE="$(mktemp -d)"; trap 'cd /; rm -rf "$BASE"' EXIT
SLOT='<событие JSON>'

# Команды из текста подсказки: после «Команда: » до конца строки; строка, целиком занятая
# командой; иначе — от «bash "/…» до конца строки. Порядок — как в тексте.
hint_cmds() { python3 - "$1" <<'PY'
import sys
for ln in sys.argv[1].splitlines():
    if "Команда: " in ln:
        print(ln.split("Команда: ", 1)[1].strip())
    elif ln.strip().startswith(('bash "', "printf '%s' '", 'git -C "')):
        print(ln.strip())
    elif 'bash "/' in ln:
        print(ln[ln.index('bash "/'):].strip())
PY
}
# Первая команда подсказки, в которой встречается $2.
hint_cmd() { hint_cmds "$1" | grep -F -- "$2" | head -1; }
# Выполнить команду из подсказки из корня файловой системы; слот события заменить на $2.
run_hint() {
  local c="$1"
  [ -n "$c" ] || { echo "<в подсказке нет команды>"; return 97; }
  [ -n "${2:-}" ] && c="$(python3 -c 'import sys; print(sys.argv[1].replace(sys.argv[2], sys.argv[3]))' "$c" "$SLOT" "$2")"
  (cd / && eval "$c") 2>&1
}
# Пути после «bash "…"» в подсказке, которых нет на диске (пусто — все живые).
dead_paths() { python3 - "$1" <<'PY'
import os, re, sys
for p in re.findall(r'bash "(/[^"]+)"', sys.argv[1]):
    if not os.path.isfile(p):
        print(p)
PY
}
# Проект: реестр с feat-001 (голова истории seq 0), пустой журнал истории, заполненный SESSION.md.
mkproj() {
  mkdir -p "$1/.harness"; echo "9.0" > "$1/.harness/engine-version"
  cat > "$1/feature_list.json" <<'JSON'
{"version":"9.0","features":{"active_list":[{"id":"feat-001","name":"Экспорт","state":"active","description":"старое","verification_command":"true","provenance":{"origin":"owner-msg","source_ref":{"kind":"session","ref":"s"},"captured_at":"2026-09-30T00:00:00Z","by":"owner","seq":0}}]}}
JSON
  : > "$1/.harness/provenance-log.jsonl"
  printf '# Session Log\n\n## Current State\n\n**Last Updated**: 2026-09-30 12:00\n**Active Feature**: feat-001 — Экспорт\n' > "$1/SESSION.md"
}
# Правка реестра на месте: $1 — проект, $2 — python-выражение над записью f (feat-001) и реестром d.
edit_feat() { python3 - "$1/feature_list.json" "$2" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p, encoding="utf-8"))
f = d["features"]["active_list"][0]
exec(sys.argv[2])
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY
}
# Сколько событий записи $2 в журнале истории проекта $1.
logged() { python3 - "$1/.harness/provenance-log.jsonl" "$2" <<'PY'
import json, sys
print(sum(1 for ln in open(sys.argv[1], encoding="utf-8") if ln.strip() and json.loads(ln).get("feat") == sys.argv[2]))
PY
}
# Номера голов истории записей feat-002..004 (для проверки миграции).
heads_of() { python3 - "$1/feature_list.json" <<'PY'
import json, sys
seq = {}
for fs in json.load(open(sys.argv[1], encoding="utf-8"))["features"].values():
    for f in fs:
        seq[f["id"]] = (f.get("provenance") or {}).get("seq")
print(" ".join("%s=%s" % (k, seq.get(k)) for k in ("feat-002", "feat-003", "feat-004")))
PY
}
payload_bash() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1"; }
# Сторож переходов на запись в реестр: $1 — проект, $2 — файл с намерением (по умолчанию — как на
# диске). Вывод — в ST_OUT, код — в ST_RC: упавший сторож (код 92, пустой вывод) — не «замолчал».
state_guard() {
  local pay
  pay="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":open(sys.argv[2],encoding="utf-8").read()}}))' "$1/feature_list.json" "${2:-$1/feature_list.json}")"
  ST_OUT="$(HOOK_PAYLOAD="$pay" bash "$PLUGIN_ROOT/hooks/checks/state-transition.sh" "$1/feature_list.json" "$1" "$PLUGIN_ROOT" Write 2>/dev/null)"
  ST_RC=$?
}
EV1='{"feat":"feat-001","op":"MODIFIED","by":"agent","origin":"dialog","source_ref":{"kind":"session","ref":"test"},"changes":{"description":{"to":"новое"}}}'

echo "Подсказки сторожей исполнимы из проекта (v9.0.3) — сценарии:"

# --- А. Запрет записи журнала фич командой оболочки ---
PA="$BASE/а проект с пробелом"; mkproj "$PA"
OUT="$(HOOK_PAYLOAD="$(payload_bash "echo '{}' > feature_list.json")" bash "$PLUGIN_ROOT/hooks/checks/feature-list-bash-guard.sh" "$PA" 2>/dev/null)"
case "$OUT" in BLOCK*) ok "а1. запись журнала фич командой оболочки остановлена";; *) bad "а1. блок" "$OUT";; esac
CMD="$(hint_cmd "$OUT" record-change.sh)"
if [ -n "$CMD" ] && [ -z "$(dead_paths "$OUT")" ]; then ok "а2. подсказка называет писателя истории путём, который существует"
else bad "а2. путь к писателю истории" "$OUT"; fi
R="$(run_hint "$CMD" "$EV1")"; RC=$?
if [ "$RC" = 0 ] && [ "$(logged "$PA" feat-001)" = 1 ]; then ok "а3. команда из подсказки выполнилась из корня — событие легло в журнал истории"
else bad "а3. команда из подсказки" "код $RC: $R | команда: $CMD"; fi
# Способ посмотреть, названный в подсказке, сам не блокируется.
READ="cat feature_list.json | jq '.features'"
if printf '%s' "$OUT" | grep -qF "cat feature_list.json | jq" \
   && [ -z "$(HOOK_PAYLOAD="$(payload_bash "$READ")" bash "$PLUGIN_ROOT/hooks/checks/feature-list-bash-guard.sh" "$PA" 2>/dev/null)" ]; then
  ok "а4. названный в подсказке способ посмотреть журнал сторож пропускает"
else bad "а4. способ посмотреть" "$OUT"; fi
# Агент видит не голый вывод сторожа, а ответ диспетчера хуков (JSON): кавычки команды обязаны
# пережить упаковку.
PA2="$BASE/а2 проект с пробелом"; mkproj "$PA2"
PAY="$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"echo x > feature_list.json"},"cwd":sys.argv[1]}))' "$PA2")"
OUT="$(cd "$PA2" && printf '%s' "$PAY" | bash "$PLUGIN_ROOT/hooks/dispatch-pre-tool-use.sh" 2>/dev/null)"
REASON="$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty')"
CMD="$(hint_cmd "$REASON" record-change.sh)"
R="$(run_hint "$CMD" "$EV1")"; RC=$?
if [ "$RC" = 0 ] && [ "$(logged "$PA2" feat-001)" = 1 ]; then ok "а5. через диспетчер хуков: команда из причины отказа выполнилась из корня"
else bad "а5. через диспетчер хуков" "код $RC: $R | причина: ${REASON:-<нет>}"; fi

# --- Б. Сверка журнала фич до и после команды (прямой вызов: к диспетчеру не подключена) ---
PB="$BASE/б проект"; mkproj "$PB"
PAY="$(payload_bash "python3 fix.py")"
HOOK_PAYLOAD="$PAY" bash "$PLUGIN_ROOT/hooks/checks/feature-list-drift.sh" "$PB" before >/dev/null 2>&1
edit_feat "$PB" 'f["description"] = "мимо писателя"'
OUT="$(HOOK_PAYLOAD="$PAY" bash "$PLUGIN_ROOT/hooks/checks/feature-list-drift.sh" "$PB" after 2>/dev/null)"
CMD="$(hint_cmd "$OUT" record-change.sh)"
case "$OUT" in WARN*) [ -n "$CMD" ] && [ -z "$(dead_paths "$OUT")" ] && ok "б1. изменение мимо писателя замечено, писатель назван живым путём" || bad "б1. путь к писателю" "$OUT";;
  *) bad "б1. предупреждение" "$OUT";; esac
R="$(run_hint "$CMD" "$EV1")"; RC=$?
if [ "$RC" = 0 ] && [ "$(logged "$PB" feat-001)" = 1 ]; then ok "б2. команда из подсказки выполнилась из корня — событие в журнале истории"
else bad "б2. команда из подсказки" "код $RC: $R | команда: $CMD"; fi

# --- В. Сторож переходов состояния ---
# Три формы записи без головы истории: новая (feat-002), с тремя событиями в журнале (feat-003),
# стаб настоящей ротации (feat-004: голова seq 2 и тело уехали в архив).
PV="$BASE/в проект с пробелом"; mkproj "$PV"
python3 - "$PV/feature_list.json" "$PV/.harness/provenance-log.jsonl" <<'PY'
import json, sys
p, log = sys.argv[1], sys.argv[2]
d = json.load(open(p, encoding="utf-8"))
d["features"]["active_list"] += [
    {"id": "feat-002", "name": "Импорт", "state": "active", "description": "x"},
    {"id": "feat-003", "name": "Отчёт", "state": "active", "description": "y"}]
d["features"]["passing"] = [{"id": "feat-004", "name": "Готовая", "state": "passing", "description": "z",
    "evidence": {"layer_2_runtime_at": "2026-09-30T00:00:00Z"},
    "provenance": {"origin": "owner-msg", "source_ref": {"kind": "session", "ref": "s"},
                   "captured_at": "2026-09-01T00:00:00Z", "by": "owner", "seq": 2}}]
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False)
with open(log, "a", encoding="utf-8") as w:
    for fid, seq in (("feat-003", 1), ("feat-003", 2), ("feat-003", 3), ("feat-004", 1), ("feat-004", 2)):
        w.write(json.dumps({"v": 1, "at": "2026-09-2%dT00:00:00Z" % seq, "feat": fid, "seq": seq,
                            "op": "MODIFIED", "by": "agent"}) + "\n")
PY
bash "$PLUGIN_ROOT/scripts/archive-features.sh" "$PV" >/dev/null
state_guard "$PV"
N_HEADLESS="$(printf '%s\n' "$ST_OUT" | grep -c 'нет provenance-головы')"
N_CMD="$(printf '%s' "$ST_OUT" | grep -o 'migrate-provenance.sh' | wc -l | tr -d ' ')"
CMD="$(hint_cmd "$ST_OUT" migrate-provenance.sh)"
if [ "$ST_RC" = 0 ] && [ "$N_HEADLESS" = 3 ] && [ "$N_CMD" = 1 ] && [ -n "$CMD" ] && [ -z "$(dead_paths "$ST_OUT")" ]; then
  ok "в1. три записи без головы (новая, с журналом, стаб ротации): одна команда на весь отказ, путь живой"
else bad "в1. записи без головы" "код $ST_RC, строк без головы $N_HEADLESS, команд $N_CMD: $ST_OUT"; fi
LOG_BEFORE="$(wc -l < "$PV/.harness/provenance-log.jsonl" | tr -d ' ')"
R="$(run_hint "$CMD")"; RC=$?
HEADS="$(heads_of "$PV")"
state_guard "$PV"
if [ "$RC" = 0 ] && [ "$(wc -l < "$PV/.harness/provenance-log.jsonl" | tr -d ' ')" = "$LOG_BEFORE" ] \
   && [ "$HEADS" = "feat-002=0 feat-003=3 feat-004=2" ] && [ "$ST_RC" = 0 ] \
   && ! printf '%s' "$ST_OUT" | grep -q 'нет provenance-головы'; then
  ok "в2. команда из подсказки восстановила головы по журналу и архиву, журнал истории не тронут — сторож замолчал"
else bad "в2. миграция из подсказки" "код $RC: $R | головы: $HEADS | журнал: было $LOG_BEFORE | сторож: код $ST_RC $ST_OUT"; fi

# Переход в готовое без квитанции прогона: подсказка — команда квитанции.
cp "$PV/feature_list.json" "$BASE/намерение.json"
python3 - "$BASE/намерение.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p, encoding="utf-8"))
f = d["features"]["active_list"][0]; f["state"] = "passing"; f["surface"] = "integration"
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY
state_guard "$PV" "$BASE/намерение.json"; OUT="$ST_OUT"
CMD="$(hint_cmd "$(printf '%s\n' "$OUT" | grep 'F4.1')" verify-receipt.sh)"
if [ "$ST_RC" = 0 ] && [ -n "$CMD" ] && [ -z "$(dead_paths "$OUT")" ]; then ok "в3. переход без квитанции: команда квитанции названа живым путём"
else bad "в3. путь к квитанции" "код $ST_RC: ${OUT:-<сообщения нет>}"; fi
R="$(run_hint "$CMD")"; RC=$?
state_guard "$PV" "$BASE/намерение.json"
if [ "$RC" = 0 ] && ls "$PV/.harness/receipts/" 2>/dev/null | grep -q '^feat-001-' \
   && [ "$ST_RC" = 0 ] && ! printf '%s' "$ST_OUT" | grep -q 'F4.1'; then ok "в4. команда из подсказки выписала квитанцию — сторож замолчал"
else bad "в4. команда квитанции" "код $RC: $R | сторож: код $ST_RC | команда: $CMD"; fi
CMD="$(hint_cmd "$(printf '%s\n' "$OUT" | grep 'F4.3')" verify-receipt.sh)"
R="$(run_hint "$CMD")"; RC=$?
state_guard "$PV" "$BASE/намерение.json"
if [ -n "$CMD" ] && [ "$RC" = 0 ] && [ "$ST_RC" = 0 ] && ! printf '%s' "$ST_OUT" | grep -q 'F4.3'; then ok "в5. внешняя связь: команда живого прогона из подсказки выполнилась — сторож замолчал"
else bad "в5. команда живого прогона" "код $RC: $R | сторож: код $ST_RC | команда: ${CMD:-<нет>}"; fi

# --- Г. Сторож коммитов, поставленный установщиком ---
repo_init() { ( cd "$1" && git init -q && git config user.email t@t.t && git config user.name t && git add -A && git commit -q -m init ); }
commit_out() { (cd "$1" && git add -A && git commit -q -m "$2" 2>&1); }
clean_repo() { (cd "$1" && git reset -q --hard HEAD && git clean -qfd); }
PG="$BASE/г проект с пробелом"; mkproj "$PG"; ( cd "$PG" && git init -q )
bash "$PLUGIN_ROOT/scripts/install-precommit.sh" "$PG" >/dev/null
repo_init "$PG" 2>/dev/null
# Блок 4: голова впереди журнала — правка мимо писателя.
edit_feat "$PG" 'f["provenance"]["seq"] = 2'
OUT="$(commit_out "$PG" "мимо писателя")"; RC=$?
WCMD="$(hint_cmd "$OUT" "$SLOT")"; RCMD="$(hint_cmd "$OUT" "--recover")"
if [ "$RC" != 0 ] && [ -n "$WCMD" ] && [ -n "$RCMD" ] && [ -z "$(dead_paths "$OUT")" ]; then ok "г1. голова впереди журнала: коммит остановлен, писатель и его восстановление названы живым путём"
else bad "г1. блок 4 и пути" "код $RC: $OUT"; fi
R="$(run_hint "$RCMD")"; RC=$?
case "$RC:$R" in 0:*recover:*) ok "г2. команда восстановления из подсказки выполнилась из корня";; *) bad "г2. восстановление" "код $RC: $R | команда: $RCMD";; esac
R="$(run_hint "$WCMD" "$EV1")"; RC=$?
OUT2="$(commit_out "$PG" "через писателя")"; RC2=$?
if [ "$RC" = 0 ] && [ "$RC2" = 0 ]; then ok "г3. правка писателем из подсказки — коммит прошёл"
else bad "г3. после подсказки коммит" "писатель: код $RC $R | коммит: код $RC2 $OUT2"; fi
# Блок 5: правка требования без события.
clean_repo "$PG"; edit_feat "$PG" 'f["description"] = "тихая правка"'
OUT="$(commit_out "$PG" "тихо")"; RC=$?
WCMD="$(hint_cmd "$OUT" "$SLOT")"
if [ "$RC" != 0 ] && [ -n "$WCMD" ] && [ -z "$(dead_paths "$OUT")" ]; then ok "г4. правка требования без события: коммит остановлен, писатель назван живым путём"
else bad "г4. блок 5 и путь" "код $RC: $OUT"; fi
R="$(run_hint "$WCMD" '{"feat":"feat-001","op":"MODIFIED","by":"agent","origin":"dialog","source_ref":{"kind":"session","ref":"test"},"changes":{"description":{"to":"тихая правка"}}}')"; RC=$?
OUT2="$(commit_out "$PG" "правка через писателя")"; RC2=$?
if [ "$RC" = 0 ] && [ "$RC2" = 0 ]; then ok "г5. событие писателем из подсказки — коммит прошёл"
else bad "г5. после подсказки коммит" "писатель: код $RC $R | коммит: код $RC2 $OUT2"; fi
# Блок 3: из журнала истории удалена строка (в журнале есть хотя бы одно событие — от г5).
clean_repo "$PG"; [ "$(logged "$PG" feat-001)" -ge 1 ] || printf '%s\n' '{"v":1,"at":"2026-09-30T00:00:00Z","feat":"feat-001","seq":1,"op":"MODIFIED","by":"agent"}' > "$PG/.harness/provenance-log.jsonl"
(cd "$PG" && git add -A && git commit -q -m "событие") >/dev/null 2>&1
(cd "$PG" && sed -i.bak '1d' .harness/provenance-log.jsonl && rm -f .harness/provenance-log.jsonl.bak)
OUT="$(commit_out "$PG" "переписать историю")"; RC=$?
if [ "$RC" != 0 ] && [ -n "$(hint_cmd "$OUT" "$SLOT")" ] && [ -z "$(dead_paths "$OUT")" ]; then ok "г6. переписанный журнал истории: коммит остановлен, писатель назван живым путём"
else bad "г6. блок 3 и путь" "код $RC: $OUT"; fi
# Блок 6: стаб без тела в архиве. Лечения одной командой нет (что возвращать — решает человек),
# подсказка даёт историю обоих файлов; проверяем, что эта команда исполняется из корня.
clean_repo "$PG"; edit_feat "$PG" 'f["evidence_hash"] = "sha256:0"'
OUT="$(commit_out "$PG" "стаб без тела")"; RC=$?
CMD="$(hint_cmd "$OUT" "feature_list.archive.json")"
R="$(run_hint "$CMD")"; RC2=$?
if [ "$RC" != 0 ] && [ -n "$CMD" ] && [ "$RC2" = 0 ]; then ok "г7. стаб без тела: команда из подсказки (история обоих файлов) выполнилась из корня"
else bad "г7. блок 6 и команда" "коммит: код $RC $OUT | команда: код $RC2 $R"; fi
clean_repo "$PG"

# Рабочая копия (git worktree): сессии идут в них, .git там — файл, а хуки — общие с основной папкой.
WT="$BASE/г рабочая копия"
(cd "$PG" && git worktree add -q --detach "$WT") >/dev/null 2>&1
OUT="$(bash "$PLUGIN_ROOT/scripts/install-precommit.sh" "$WT" 2>&1)"; RC=$?
case "$RC:$OUT" in 0:*✅*) ok "г8. установщик из рабочей копии ставит сторожа в общий каталог хуков";; *) bad "г8. установка из рабочей копии" "код $RC: $OUT";; esac
edit_feat "$WT" 'f["provenance"]["seq"] = f["provenance"]["seq"] + 5'
OUT="$(commit_out "$WT" "мимо писателя")"; RC=$?
WCMD="$(hint_cmd "$OUT" "$SLOT")"
R="$(run_hint "$WCMD" '{"feat":"feat-001","op":"MODIFIED","by":"agent","origin":"dialog","source_ref":{"kind":"session","ref":"test"},"changes":{"description":{"to":"правка в рабочей копии"}}}')"; RC2=$?
OUT2="$(commit_out "$WT" "через писателя")"; RC3=$?
if [ "$RC" != 0 ] && [ -z "$(dead_paths "$OUT")" ] && [ "$RC2" = 0 ] && [ "$RC3" = 0 ]; then ok "г9. в рабочей копии: команда писателя из подсказки выполнилась — коммит прошёл"
else bad "г9. рабочая копия" "коммит: код $RC $OUT | писатель: код $RC2 $R | повтор: код $RC3 $OUT2"; fi

# Хуки перенаправлены (husky и т.п.): git не вызывает .git/hooks — «установлен» было бы неправдой.
PH="$BASE/г3 проект"; mkproj "$PH"; ( cd "$PH" && git init -q && git config core.hooksPath .husky )
OUT="$(bash "$PLUGIN_ROOT/scripts/install-precommit.sh" "$PH" 2>&1)"
if printf '%s' "$OUT" | grep -q 'перенаправлены' && ! printf '%s' "$OUT" | grep -q '✅' && [ ! -f "$PH/.git/hooks/pre-commit" ]; then
  ok "г10. хуки перенаправлены: установщик не рапортует «установлен» о стороже, которого git не вызовет"
else bad "г10. перенаправленные хуки" "$OUT"; fi

# Переустановка поверх сторожа, слитого вручную: прежний файл сохраняется рядом — и не теряется на
# второй переустановке (одно поколение копии затиралось чистой копией).
PK="$BASE/г4 проект"; mkproj "$PK"; ( cd "$PK" && git init -q )
bash "$PLUGIN_ROOT/scripts/install-precommit.sh" "$PK" >/dev/null
printf '\necho свой-шаг-проекта\n' >> "$PK/.git/hooks/pre-commit"
bash "$PLUGIN_ROOT/scripts/install-precommit.sh" "$PK" >/dev/null
printf '\n# отметка второй установки\n' >> "$PK/.git/hooks/pre-commit"
bash "$PLUGIN_ROOT/scripts/install-precommit.sh" "$PK" >/dev/null
if cat "$PK/.git/hooks/"pre-commit.vibe-prev-* 2>/dev/null | grep -q 'свой-шаг-проекта' && ! grep -q 'свой-шаг-проекта' "$PK/.git/hooks/pre-commit"; then
  ok "г11. две переустановки поверх слитого вручную сторожа: свои строки лежат в копии рядом"
else bad "г11. прежний файл" "$(ls "$PK/.git/hooks/" | tr '\n' ' ')"; fi

# Без python3: блок активации — чистый bash, сторож обязан ставиться и там.
NB="$BASE/утилиты без python"; mkdir -p "$NB"
for t in git dirname grep sed awk mkdir cp chmod mv cmp rm cat; do ln -s "$(type -P "$t")" "$NB/$t"; done
PN="$BASE/г5 проект"; mkproj "$PN"; ( cd "$PN" && git init -q )
OUT="$(PATH="$NB" /bin/bash "$PLUGIN_ROOT/scripts/install-precommit.sh" "$PN" 2>&1)"; RC=$?
if [ -z "$(PATH="$NB" /bin/bash -c 'command -v python3' 2>/dev/null)" ] && [ "$RC" = 0 ] && grep -qxF "VIBE_PLUGIN_ROOT='$PLUGIN_ROOT'" "$PN/.git/hooks/pre-commit"; then
  ok "г12. без python3 сторож ставится, путь к плагину вписан"
else bad "г12. установка без python3" "код $RC: $OUT"; fi

# Вызов из подпапки проекта ставит сторожа для корня репозитория и не плодит .harness в подпапке:
# иначе поиск корня проекта находил бы подпапку, и писатель истории искал бы журнал там.
PS="$BASE/г6 проект"; mkproj "$PS"; ( cd "$PS" && git init -q ); mkdir -p "$PS/src/комп"
OUT="$(bash "$PLUGIN_ROOT/scripts/install-precommit.sh" "$PS/src/комп" 2>&1)"; RC=$?
if [ "$RC" = 0 ] && [ -f "$PS/.git/hooks/pre-commit" ] && [ ! -e "$PS/src/комп/.harness" ]; then ok "г14. вызов из подпапки: сторож поставлен для корня, лишнего .harness в подпапке нет"
else bad "г14. вызов из подпапки" "код $RC: $OUT"; fi
# Проект в подпапке git-репозитория: сторож коммитов смотрит журнал в корне репозитория и такой
# проект не охранял бы — «установлен» было бы неправдой.
PMO="$BASE/г7 монорепо"; mkdir -p "$PMO"; ( cd "$PMO" && git init -q ); mkproj "$PMO/app"
OUT="$(bash "$PLUGIN_ROOT/scripts/install-precommit.sh" "$PMO/app" 2>&1)"
if ! printf '%s' "$OUT" | grep -q '✅' && [ ! -f "$PMO/.git/hooks/pre-commit" ] && printf '%s' "$OUT" | grep -q 'нет проекта Vibe Dev'; then
  ok "г15. проект в подпапке репозитория: установщик честно отказывает"
else bad "г15. проект в подпапке репозитория" "$OUT"; fi
# Явно заданный стандартный каталог хуков — не перенаправление.
PSTD="$BASE/г8 проект"; mkproj "$PSTD"; ( cd "$PSTD" && git init -q && git config core.hooksPath .git/hooks )
OUT="$(bash "$PLUGIN_ROOT/scripts/install-precommit.sh" "$PSTD" 2>&1)"
if printf '%s' "$OUT" | grep -q '✅' && [ -f "$PSTD/.git/hooks/pre-commit" ]; then ok "г16. core.hooksPath=.git/hooks: стандартный каталог, сторож поставлен"
else bad "г16. стандартный каталог хуков" "$OUT"; fi

# Плагин переехал после установки сторожа: подсказка не выдаёт мёртвый путь за команду.
MOVED="$BASE/копия плагина"; mkdir -p "$MOVED"
cp -R "$PLUGIN_ROOT/scripts" "$PLUGIN_ROOT/hooks" "$PLUGIN_ROOT/templates" "$MOVED/"
PM="$BASE/г2 проект"; mkproj "$PM"; ( cd "$PM" && git init -q )
bash "$MOVED/scripts/install-precommit.sh" "$PM" >/dev/null
repo_init "$PM" 2>/dev/null
rm -rf "$MOVED"
edit_feat "$PM" 'f["provenance"]["seq"] = 2'
OUT="$(commit_out "$PM" "мимо писателя")"; RC=$?
if [ "$RC" != 0 ] && [ -z "$(dead_paths "$OUT")" ] && printf '%s' "$OUT" | grep -q 'не найден'; then ok "г13. плагин переехал: подсказка честно говорит «не найден», мёртвый путь командой не выдаётся"
else bad "г13. честный отказ" "код $RC: $OUT"; fi

# --- Д. Чекпоинт: голова впереди журнала ---
PD="$BASE/д проект с пробелом"; mkproj "$PD"
edit_feat "$PD" 'f["provenance"]["seq"] = 2'
OUT="$(bash "$PLUGIN_ROOT/scripts/checkpoint.sh" "$PD" 2>&1)"; RC=$?
CMD="$(hint_cmd "$(printf '%s\n' "$OUT" | grep 'feat-001')" record-change.sh)"
if [ "$RC" != 0 ] && [ -n "$CMD" ] && [ -z "$(dead_paths "$OUT")" ]; then ok "д1. чекпоинт остановлен, писатель назван живым путём"
else bad "д1. чекпоинт и путь" "код $RC: $OUT"; fi
R="$(run_hint "$CMD" "$EV1")"; RC=$?
OUT2="$(bash "$PLUGIN_ROOT/scripts/checkpoint.sh" "$PD" 2>&1)"; RC2=$?
if [ "$RC" = 0 ] && [ "$RC2" = 0 ]; then ok "д2. команда из подсказки сняла расхождение — чекпоинт завершился"
else bad "д2. после подсказки чекпоинт" "команда: код $RC $R | чекпоинт: код $RC2 $(printf '%s' "$OUT2" | grep '✗')"; fi

# --- Е. Другие скрипты и шаблоны плагина в подсказках ---
PJ="$BASE/е проект с пробелом"; mkproj "$PJ"
OUT="$(HOOK_PAYLOAD="$(payload_bash 'cat ids.txt | while read id; do curl -s "https://api.example.com/x/$id"; done')" bash "$PLUGIN_ROOT/hooks/checks/bulk-api.sh" "$PJ" "$PLUGIN_ROOT" 2>/dev/null)"
CMD="$(hint_cmd "$OUT" pre-launch-checklist.yaml)"
R="$(run_hint "$CMD")"; RC=$?
if [ "$RC" = 0 ] && [ -f "$PJ/.harness/pre-launch-checklist.yaml" ]; then ok "е1. массовый вызов: команда из подсказки положила шаблон чек-листа в проект"
else bad "е1. шаблон чек-листа" "код $RC: $R | подсказка: $OUT"; fi
OUT="$(bash "$PLUGIN_ROOT/scripts/wave-relay.sh" plan "$PJ" 2>&1)"
CMD="$(hint_cmd "$OUT" wave-relay.sh)"
R="$(run_hint "$CMD")"; RC=$?
if [ "$RC" = 0 ] && [ -n "$CMD" ] && [ -z "$(dead_paths "$OUT")" ] && printf '%s' "$R" | grep -q 'feat-001\|Экспорт'; then ok "е2. эстафета: команда «что дальше» из подсказки выполнилась из корня"
else bad "е2. эстафета" "код $RC: $R | команда: ${CMD:-<нет>}"; fi

# --- Ж. Сторож класса: файл плагина не называется относительным путём или голым именем ---
# Разбор — функцией верхнего уровня: bash 3.2 (системный на macOS) не разбирает кавычки в heredoc
# внутри $(…).
class_leaks() { (cd "$PLUGIN_ROOT" && python3 - <<'PY'
import glob, os, re
names = "|".join(re.escape(os.path.basename(p)) for p in sorted(glob.glob("scripts/*.sh")))
DIRS = "scripts|templates|rules|schemas|skills|workflow|hooks"
rel = re.compile(r"(?<![/\w.$}-])(%s)/(?:[\w.-]+/)*[\w.-]+\.\w+" % DIRS)  # scripts/x.sh, hooks/lib/x.py
dot = re.compile(r"(?<![\w/.-])\./(%s)/[\w.-]+" % DIRS)            # ./scripts/x.sh
bare = re.compile(r"(?<![/\w.*-])(%s)\b(?!\*)" % names)            # голое имя; *имя* — шаблон case
helper = re.compile(r"\bplugin_(?:cmd|path)\s+(?:\w+\s+)?[\"']?(%s)" % names)  # аргумент помощника
# Вывод сторожей и скриптов, работающих в папке ПРОЕКТА. Скрипты самопроверки плагина (check-*)
# работают в его собственном репозитории — там относительный путь верен.
runtime = sorted(p for p in glob.glob("hooks/**/*", recursive=True) if p.endswith((".sh", ".py")))
runtime += ["templates/git-pre-commit.sh"]
runtime += sorted(p for p in glob.glob("scripts/*.sh") if not os.path.basename(p).startswith("check-"))
for f in runtime:
    for i, ln in enumerate(open(f, encoding="utf-8"), 1):
        if ln.lstrip().startswith("#"):
            continue
        spans = [m.span(1) for m in helper.finditer(ln)]
        for m in list(rel.finditer(ln)) + list(dot.finditer(ln)):
            print("%s:%d: %s" % (f, i, m.group(0)))
        for m in bare.finditer(ln):
            if not any(a <= m.start() < b for a, b in spans):
                print("%s:%d: %s" % (f, i, m.group(0)))
# Инструкции агенту в навыках, описаниях ролей и правилах: «bash/sh» + относительный путь или имя.
md = []
for pat in ("skills/**/*.md", "agents/**/*.md", "rules/**/*.md", "workflow/**/*.md", "commands/**/*.md", "templates/*.md"):
    md += glob.glob(pat, recursive=True)
cmd = re.compile(r"""\b(?:bash|sh)\s+["']?(?:\./)?(?:(?:%s)/[\w./-]+|(?:%s)\b)""" % (DIRS, names))
for f in sorted(md):
    for i, ln in enumerate(open(f, encoding="utf-8"), 1):
        for m in cmd.finditer(ln):
            print("%s:%d: %s" % (f, i, m.group(0)))
PY
); }
LEAKS="$(class_leaks)"
if [ -z "$LEAKS" ]; then ok "ж1. ни подсказка, ни инструкция не называют файл плагина относительным путём или голым именем"
else bad "ж1. относительные пути и голые имена файлов плагина" "$(printf '%s' "$LEAKS" | tr '\n' ';')"; fi

echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
