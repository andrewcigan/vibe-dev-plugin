#!/bin/bash
# Vibe Dev v6.2 — тест защиты конфигурации enforcement (F9; R3: агент не ослабляет свои гейты).
#
# Контракты:
#   - прямая запись .harness/profile НЕ-pending значением -> BLOCK (ослабление гейтов);
#     pending-* -> pass (bootstrap, слабейшее состояние);
#   - запись heartbeat агентом -> BLOCK (фальсификация активации);
#   - создание hooks-disabled агентом -> BLOCK (escape ставит пользователь руками);
#   - Write-инструментом на эти файлы -> BLOCK.
#
# Запуск: bash tests/hooks/test-config-protect.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PRE="$PLUGIN_ROOT/hooks/dispatch-pre-tool-use.sh"
PASS=0; FAIL=0

unset VIBE_DEV_PROFILE CLAUDE_PLUGIN_ROOT HOOK_PAYLOAD 2>/dev/null || true

assert_contains() {
  if printf '%s' "$2" | grep -q -- "$3"; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s\n     ожидал: %s\n     получил: %s\n' "$1" "$3" "$2"; fi
}
assert_not_contains() {
  if printf '%s' "$2" | grep -q -- "$3"; then FAIL=$((FAIL+1)); printf '  FAIL %s (НЕ ожидал: %s)\n     получил: %s\n' "$1" "$3" "$2"
  else PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; fi
}

PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness"
echo "7.0" > "$PROJ/.harness/engine-version"; echo strict > "$PROJ/.harness/profile"

bashcmd() { jq -cn --arg cwd "$PROJ" --arg c "$1" '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Bash",tool_input:{command:$c}}' | bash "$PRE"; }
write()   { jq -cn --arg cwd "$PROJ" --arg fp "$1" '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Write",tool_input:{file_path:$fp,content:"x"}}' | bash "$PRE"; }

echo "Enforcement-config-protect (F9) — сценарии:"

OUT="$(bashcmd 'echo minimal > .harness/profile')"
assert_contains "1. echo minimal > profile -> deny (ослабление)" "$OUT" '"permissionDecision":"deny"'

OUT="$(bashcmd 'echo strict > .harness/profile')"
assert_contains "2. echo strict > profile -> deny (профиль меняют скрипты/хуки)" "$OUT" '"permissionDecision":"deny"'

OUT="$(bashcmd 'echo "pending-strict" > .harness/profile')"
assert_not_contains "3. pending-strict -> pass (bootstrap легитимен)" "$OUT" '"permissionDecision":"deny"'

OUT="$(bashcmd 'echo "$(date +%s) plugin=6.2" > .harness/hooks-heartbeat')"
assert_contains "4. запись heartbeat агентом -> deny (фальсификация)" "$OUT" '"permissionDecision":"deny"'

OUT="$(bashcmd 'touch .harness/hooks-disabled')"
assert_contains "5a. touch hooks-disabled -> deny" "$OUT" '"permissionDecision":"deny"'
assert_contains "5b. remediation: решение пользователя руками" "$OUT" "руками"

OUT="$(write "$PROJ/.harness/profile")"
assert_contains "6. Write profile -> deny" "$OUT" '"permissionDecision":"deny"'

OUT="$(bashcmd 'cat .harness/profile && ls .harness/')"
assert_not_contains "7. чтение конфигурации -> pass" "$OUT" '"permissionDecision":"deny"'

OUT="$(bashcmd 'echo strict > /tmp/other-file')"
assert_not_contains "8. запись в посторонний файл -> pass" "$OUT" '"permissionDecision":"deny"'

echo ""
echo "L5-F1 must-fix — hook-mode под защитой + расширенные глаголы записи:"

# hook-mode=learn понижает структурные гейты → агент не включает (раньше НЕ было защиты)
OUT="$(bashcmd 'echo learn > .harness/hook-mode')"
assert_contains "9. echo learn > hook-mode -> deny (L5-F1: hook-mode под защитой)" "$OUT" '"permissionDecision":"deny"'

OUT="$(bashcmd 'printf learn | tee .harness/hook-mode')"
assert_contains "10. tee learn -> hook-mode -> deny" "$OUT" '"permissionDecision":"deny"'

OUT="$(bashcmd "sed -i 's/strict/learn/' .harness/hook-mode")"
assert_contains "11. sed -i ...learn hook-mode -> deny" "$OUT" '"permissionDecision":"deny"'

OUT="$(write "$PROJ/.harness/hook-mode")"
assert_contains "12. Write hook-mode -> deny" "$OUT" '"permissionDecision":"deny"'

# ключевая дыра: cp файла-с-learn — значение вне текста команды → всё равно deny (любая запись)
OUT="$(bashcmd 'cp /tmp/anyfile .harness/hook-mode')"
assert_contains "12b. cp -> hook-mode (значение вне команды) -> deny (дыра закрыта)" "$OUT" '"permissionDecision":"deny"'

# снятие learn (rm) и чтение — движение к строгости, легитимно
OUT="$(bashcmd 'rm -f .harness/hook-mode')"
assert_not_contains "13. rm hook-mode (снятие learn) -> pass" "$OUT" '"permissionDecision":"deny"'

OUT="$(bashcmd 'cat .harness/hook-mode')"
assert_not_contains "14. чтение hook-mode -> pass" "$OUT" '"permissionDecision":"deny"'

# расширенные глаголы (раньше Bash-ветка ловила только >/>>/tee → cp/mv/sed/install проходили)
OUT="$(bashcmd 'cp /tmp/x .harness/profile')"
assert_contains "15. cp -> profile -> deny (расширенный глагол)" "$OUT" '"permissionDecision":"deny"'

OUT="$(bashcmd 'mv /tmp/x .harness/profile')"
assert_contains "16. mv -> profile -> deny" "$OUT" '"permissionDecision":"deny"'

OUT="$(bashcmd "sed -i 's/strict/minimal/' .harness/profile")"
assert_contains "17. sed -i minimal profile -> deny" "$OUT" '"permissionDecision":"deny"'

OUT="$(bashcmd 'install -m 644 /tmp/x .harness/hooks-disabled')"
assert_contains "18. install -> hooks-disabled -> deny (расширенный глагол)" "$OUT" '"permissionDecision":"deny"'

# pending-* через расширенный глагол всё ещё легитимен (bootstrap, слабейшее состояние)
OUT="$(bashcmd 'cp /tmp/pending-strict-src .harness/profile')"
assert_not_contains "19. cp c pending- в имени -> pass (bootstrap не ломаем)" "$OUT" '"permissionDecision":"deny"'

rm -rf "$PROJ"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
