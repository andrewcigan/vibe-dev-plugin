#!/bin/bash
# Vibe Dev v7 (Волна 3) — тесты новых замков: secret-scan-write (P14) + folder-scope (P9).
# Живой-формат ключ строится на РАНТАЙМЕ (не литерал в файле), чтобы сам secret-scan не заблокировал
# запись этого теста. Запуск: bash tests/hooks/test-new-locks.sh
set -u
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PLUGIN_ROOT" || exit 1
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
PASS=0; FAIL=0
FAKE="ghp_$(printf 'A%.0s' $(seq 1 25))"

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness"

scan() { local p="$1" c="$2" pl
  pl=$(jq -cn --arg f "$p" --arg c "$c" '{tool_input:{file_path:$f,content:$c}}')
  HOOK_PAYLOAD="$pl" bash hooks/checks/secret-scan-write.sh "$PROJ" "$p" "Write"
}
fscope() { HOOK_PAYLOAD='{}' bash hooks/checks/folder-scope.sh "$PROJ" "$1"; }

# 1. живой ключ в src → BLOCK
printf '%s' "$(scan 'src/config.ts' "const k=\"$FAKE\"")" | grep -q '^BLOCK' && ok "1. живой ключ в src → BLOCK" || bad "1. живой ключ в src → BLOCK"
# 2. .env → тишина
[ -z "$(scan '.env' "KEY=$FAKE")" ] && ok "2. ключ в .env → тишина" || bad "2. ключ в .env → тишина"
# 3. короткий плейсхолдер → тишина (не живой формат)
[ -z "$(scan 'src/x.ts' 'k="sk-ant-xxx"')" ] && ok "3. плейсхолдер → тишина (нет FP)" || bad "3. плейсхолдер → тишина"
# 4. escape через listener → маркер ставится, блок снят, маркер одноразовый
LP=$(jq -cn '{prompt:"этот ключ тестовый, забей на секрет"}')
HOOK_PAYLOAD="$LP" bash hooks/checks/secret-skip-listener.sh "$PROJ" >/dev/null
[ -f "$PROJ/.harness/locks/secret-scan-off" ] && ok "4a. listener поставил маркер" || bad "4a. listener поставил маркер"
[ -z "$(scan 'src/y.ts' "k=$FAKE")" ] && ok "4b. после фразы блок снят" || bad "4b. после фразы блок снят"
[ ! -f "$PROJ/.harness/locks/secret-scan-off" ] && ok "4c. маркер одноразовый (снят)" || bad "4c. маркер одноразовый"

# 5. folder-scope: вне корня → лог (несистемный путь вне whitelist)
fscope "/opt/foreign-project/proto.html" >/dev/null
grep -q 'foreign-project/proto.html' "$PROJ/.harness/folder-scope.log" 2>/dev/null && ok "5. вне корня → логируется" || bad "5. вне корня → логируется"
# 6. folder-scope: log-only по умолчанию (нет WARN на stdout)
rm -f "$PROJ/.harness/folder-scope.log"
[ -z "$(fscope "/opt/foreign-project/x.txt")" ] && ok "6. log-only (нет warn по умолчанию)" || bad "6. log-only по умолчанию"
# 7. folder-scope: внутри корня → без лога
rm -f "$PROJ/.harness/folder-scope.log"; fscope "src/app.ts" >/dev/null
[ ! -f "$PROJ/.harness/folder-scope.log" ] && ok "7. внутри корня → без лога" || bad "7. внутри корня → без лога"
# 8. folder-scope: /tmp whitelist
rm -f "$PROJ/.harness/folder-scope.log"; fscope "/private/tmp/scratch/x.png" >/dev/null
[ ! -f "$PROJ/.harness/folder-scope.log" ] && ok "8. /tmp whitelisted" || bad "8. /tmp whitelisted"

rm -rf "$PROJ" 2>/dev/null
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ]
