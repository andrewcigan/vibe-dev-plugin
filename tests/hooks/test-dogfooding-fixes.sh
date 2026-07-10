#!/bin/bash
# Vibe Dev v8.0.2 — фиксы по dogfooding-отчёту (внедрение харнеса в живой проект LinX):
#   #3 model-swap-guard по типу файла (документация не шумит);
#   #2 upgrade --soft дописывает .gitignore рантайма (идемпотентно, не ломает чистое-дерево-чек);
#   #4 граф переходов справочный — нестандартный lifecycle-переход не блокируется.
# Запуск: bash tests/hooks/test-dogfooding-fixes.sh
set -u
PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MSG="$PLUGIN/hooks/checks/model-swap-guard.sh"
DISPATCH="$PLUGIN/hooks/dispatch-pre-tool-use.sh"
UPG="$PLUGIN/scripts/upgrade-project.sh"
P=0; F=0
ok(){ P=$((P+1)); printf '  ok   %s\n' "$1"; }
bad(){ F=$((F+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

echo "Dogfooding-фиксы v8.0.2:"

# #3 — model-swap-guard по типу файла
OUT="$(HOOK_PAYLOAD='{"tool_name":"Write","tool_input":{"file_path":"docs/report.md","content":"перешли на claude-opus-4, temperature=0.7"}}' bash "$MSG" /tmp 2>/dev/null)"
[ -z "$OUT" ] && ok "3a. .md с моделью/настройкой → тихо (документация)" || bad "3a. .md тихо" "$OUT"
OUT="$(HOOK_PAYLOAD='{"tool_name":"Write","tool_input":{"file_path":"CHANGELOG.md","content":"gpt-4 → claude-sonnet, max_tokens=4096"}}' bash "$MSG" /tmp 2>/dev/null)"
[ -z "$OUT" ] && ok "3b. CHANGELOG → тихо" || bad "3b. CHANGELOG тихо" "$OUT"
OUT="$(HOOK_PAYLOAD='{"tool_name":"Write","tool_input":{"file_path":"src/llm.js","content":"const model=\"claude-opus-4\"; temperature: 0.7"}}' bash "$MSG" /tmp 2>/dev/null)"
printf '%s' "$OUT" | grep -q WARN && ok "3c. .js со сменой модели → WARN (не потеряли сигнал)" || bad "3c. .js warn" "$OUT"
OUT="$(HOOK_PAYLOAD='{"tool_name":"Write","tool_input":{"file_path":".env","content":"MODEL_NAME=gpt-4"}}' bash "$MSG" /tmp 2>/dev/null)"
printf '%s' "$OUT" | grep -q WARN && ok "3d. .env со сменой модели → WARN" || bad "3d. .env warn" "$OUT"

# #2 — upgrade --soft дописывает .gitignore рантайма
PROJ="$(mktemp -d)"; ( cd "$PROJ"; git init -q; git config user.email t@t; git config user.name t )
mkdir -p "$PROJ/.harness"; echo 7.0 > "$PROJ/.harness/engine-version"; echo strict > "$PROJ/.harness/profile"
echo '{"version":"7.0","features":{"passing":[{"id":"f1","state":"passing","surface":"logic","affected_files":["src/c.py"],"evidence":{"layer_2_runtime_at":"2026-07-10"}}]}}' > "$PROJ/feature_list.json"
printf 'node_modules/\n' > "$PROJ/.gitignore"; ( cd "$PROJ"; git add -A; git commit -q -m base )
bash "$UPG" --soft "$PROJ" >/dev/null 2>&1
[ $? = 0 ] && ok "2a. --soft прошёл несмотря на правку .gitignore" || bad "2a. soft прошёл" "exit≠0"
grep -qF "Vibe Dev — рантайм-состояние хуков" "$PROJ/.gitignore" && ok "2b. .gitignore получил секцию рантайма" || bad "2b. секция" "нет"
grep -qF ".harness/hooks-heartbeat" "$PROJ/.gitignore" && ok "2c. рантайм-файлы перечислены" || bad "2c. файлы" "нет"
echo strict > "$PROJ/.harness/profile"; rm -f "$PROJ/.harness/hook-mode"; echo 7.0 > "$PROJ/.harness/engine-version"
( cd "$PROJ"; git add -A; git commit -q -m reset 2>/dev/null )
bash "$UPG" --soft "$PROJ" >/dev/null 2>&1
[ "$(grep -c "Vibe Dev — рантайм" "$PROJ/.gitignore")" = "1" ] && ok "2d. секция идемпотентна (не дублируется)" || bad "2d. идемпотентность" "дубль"
grep -qF ".harness/clarity-cap-log" "$PROJ/.gitignore" && grep -qF ".harness/stuck-watcher.pid" "$PROJ/.gitignore" && ok "2e. новые рантайм-файлы (clarity-cap-log/handoff-pending/stuck-watcher.pid) в игноре" || bad "2e. новые файлы" "нет"
# 2f (критик v8.0.2): H5-дыра закрыта — грязный файл с суффиксом .gitignore всё равно ловится
echo strict > "$PROJ/.harness/profile"; rm -f "$PROJ/.harness/hook-mode"; echo 7.0 > "$PROJ/.harness/engine-version"
( cd "$PROJ"; git add -A; git commit -q -m clean 2>/dev/null; echo dirt > app.gitignore )
bash "$UPG" --soft "$PROJ" >/dev/null 2>&1
[ $? = 2 ] && ok "2f. грязный app.gitignore → H5 exit 2 (суффиксная дыра закрыта pathspec'ом)" || bad "2f. H5 дыра" "прошёл на грязном"
rm -rf "$PROJ"

# #4 — граф переходов справочный: нестандартный lifecycle-переход не блокируется
SB="$(mktemp -d)"; mkdir -p "$SB/.harness"; echo 8.0 > "$SB/.harness/engine-version"; echo strict > "$SB/.harness/profile"
H='"provenance":{"origin":"owner-msg","source_ref":{"kind":"session","ref":"s"},"captured_at":"2026-07-10T00:00:00Z","by":"owner"}'
C="{\"features\":{\"awaiting\":[{\"id\":\"f1\",\"state\":\"awaiting_user_acceptance\",\"surface\":\"ui\",\"affected_files\":[\"pages/x.tsx\"],$H}]}}"
OUT="$(jq -cn --arg cwd "$SB" --arg fp "$SB/feature_list.json" --arg c "$C" '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Write",tool_input:{file_path:$fp,content:$c}}' | bash "$DISPATCH" 2>/dev/null)"
printf '%s' "$OUT" | grep -q '"permissionDecision":"deny"' && bad "4a. awaiting_user_acceptance → deny" "$OUT" || ok "4a. нестандартный граф-переход НЕ блокируется"
printf '%s' "$OUT" | grep -q 'не в schema' && bad "4b. ложно 'не в schema'" "$OUT" || ok "4b. валидное имя state принято"
rm -rf "$SB"

echo ""
echo "Итог: PASS=$P FAIL=$F"
[ "$F" -eq 0 ]
