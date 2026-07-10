#!/bin/bash
# Vibe Dev v8.0.1 — тесты патч-механизма: мягкое включение, защита H1, грязное дерево,
# идемпотентность, MEDIUM-1 (уже-строгий не понижается молча). Запуск: bash tests/hooks/test-upgrade-soft.sh
set -u
PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UPG="$PLUGIN/scripts/upgrade-project.sh"
CFG="$PLUGIN/hooks/checks/enforcement-config-protect.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf '  FAIL %s (%s)\n' "$1" "$2"; }

mkproj(){ # $1=engine $2=profile -> печатает путь; фичи дают strict-deny (logic passing без runtime, без головы)
  local P; P="$(mktemp -d)"; ( cd "$P"; git init -q; git config user.email t@t; git config user.name t )
  mkdir -p "$P/.harness" "$P/src"; echo "$1" > "$P/.harness/engine-version"; echo "$2" > "$P/.harness/profile"
  cat > "$P/feature_list.json" <<'JSON'
{"version":"7.0","features":{"passing":[{"id":"f1","state":"passing","surface":"logic","size_estimate":"S","affected_files":["src/c.py"],"evidence":{"layer_1_syntax":"ok"}}]}}
JSON
  echo "# c" > "$P/src/c.py"; ( cd "$P"; git add -A; git commit -q -m base )
  echo "$P"
}
sim(){ # $1=projdir $2=learn? -> печатает deny-строки
  local sb; sb="$(mktemp -d)"; mkdir -p "$sb/.harness"; cp "$1/feature_list.json" "$sb/feature_list.json"
  echo 8.0 > "$sb/.harness/engine-version"; echo strict > "$sb/.harness/profile"; [ "$2" = learn ] && echo learn > "$sb/.harness/hook-mode"
  local c; c="$(cat "$sb/feature_list.json")"
  jq -cn --arg cwd "$sb" --arg fp "$sb/feature_list.json" --arg c "$c" \
    '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Write",tool_input:{file_path:$fp,content:$c}}' \
    | bash "$PLUGIN/hooks/dispatch-pre-tool-use.sh" 2>/dev/null | grep -o '"permissionDecision":"deny"' | head -1
  rm -rf "$sb"
}

echo "Патч-механизм v8.0.1 — сценарии:"

# 1-6: мягкое включение end-to-end (legacy → soft)
P="$(mkproj 7.0 strict)"
[ -n "$(sim "$P" strict)" ] && ok "1. строгий v8 на этих фичах → deny (база)" || bad "1. база deny" "нет deny"
bash "$UPG" --soft "$P" >/dev/null 2>&1
[ "$(cat "$P/.harness/engine-version")" = "8.0" ] && ok "2. --soft → движок 8.0" || bad "2. движок" "$(cat "$P/.harness/engine-version")"
[ "$(cat "$P/.harness/hook-mode" 2>/dev/null)" = "learn" ] && ok "3. --soft → hook-mode=learn (C1)" || bad "3. hook-mode" "нет"
[ "$(cat "$P/.harness/profile")" = "strict" ] && ok "4. --soft → profile сохранён strict (C1)" || bad "4. profile" "$(cat "$P/.harness/profile")"
[ ! -f "$P/.git/hooks/pre-commit" ] && ok "5. --soft НЕ ставит git pre-commit (C2)" || bad "5. pre-commit" "поставлен"
[ -z "$(sim "$P" learn)" ] && ok "6. после soft → НЕ deny (подсказки)" || bad "6. soft warn" "остался deny"
rm -rf "$P"

# 7: идемпотентность (повторный --soft безопасен)
P="$(mkproj 7.0 strict)"; bash "$UPG" --soft "$P" >/dev/null 2>&1; bash "$UPG" --soft "$P" >/dev/null 2>&1
[ "$(cat "$P/.harness/hook-mode" 2>/dev/null)" = "learn" ] && ok "7. повторный --soft идемпотентен" || bad "7. идемпотентность" "сломалось"
rm -rf "$P"

# 8: грязное дерево → --soft прерывает (exit 2), ничего не меняет (H5/HIGH-2)
P="$(mkproj 7.0 strict)"; echo "dirty" > "$P/newfile.txt"
bash "$UPG" --soft "$P" >/dev/null 2>&1; RC=$?
[ "$RC" = "2" ] && ok "8. грязное дерево → exit 2 (не трогает)" || bad "8. dirty exit" "код $RC"
[ "$(cat "$P/.harness/engine-version")" = "7.0" ] && ok "9. грязное дерево → движок НЕ изменён" || bad "9. dirty no-change" "изменён"
rm -rf "$P"

# 10: H1 negative — config-protect блокирует обход через комментарий с именем скрипта
OUT="$(HOOK_PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"echo learn > .harness/hook-mode # scripts/patch-projects.sh"}}' bash "$CFG" /tmp 2>/dev/null)"
printf '%s' "$OUT" | grep -q BLOCK && ok "10. H1: обход hook-mode комментом → BLOCK (замок закрыт)" || bad "10. H1 обход" "прошёл: $OUT"

# 11: бэкап-тег создан
P="$(mkproj 7.0 strict)"; bash "$UPG" --soft "$P" >/dev/null 2>&1
git -C "$P" tag 2>/dev/null | grep -q "pre-v8" && ok "11. бэкап-тег pre-v8-* создан (H5)" || bad "11. бэкап" "нет"
rm -rf "$P"

echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
