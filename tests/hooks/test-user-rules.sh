#!/bin/bash
# Vibe Dev v6 — регрессионный тест user-rules (hookify, R6/H9): правила пользователя «больше не делай X».
#
# Generic-проверка hooks/checks/user-rules.sh читает .harness/user-rules.json и применяет
# на PreToolUse: tool совпал (или "*") И regex по subject (Bash→command, Write/Edit→file_path)
# -> block|warn по rule.action. Скилл hookify пишет эти правила из коррекции пользователя.
# Честная граница: ловит ДЕЙСТВИЯ (команды/файлы), НЕ контент сообщений (display-only).
#
# Тест гонит реальный триггер через dispatch-pre-tool-use.sh (PreToolUse-payload stdin JSON).
# Запуск: bash tests/hooks/test-user-rules.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISPATCH="$PLUGIN_ROOT/hooks/dispatch-pre-tool-use.sh"
PASS=0; FAIL=0
unset VIBE_DEV_PROFILE CLAUDE_PLUGIN_ROOT HOOK_PAYLOAD 2>/dev/null || true

run() { printf '%s' "$1" | bash "$DISPATCH"; }
assert_contains() {
  if printf '%s' "$2" | grep -q -- "$3"; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s\n     ожидал: %s\n     получил: %s\n' "$1" "$3" "$2"; fi
}
assert_empty() {
  if [ -z "$(printf '%s' "$2" | tr -d '[:space:]')" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s (ожидал пусто)\n     получил: %s\n' "$1" "$2"; fi
}

PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness"; echo "6.0" > "$PROJ/.harness/engine-version"
cat > "$PROJ/.harness/user-rules.json" <<'JSON'
[
  {"id":"no-force-push","tool":"Bash","match":"push.*--force","action":"block","message":"Force-push запрещён (правило пользователя)"},
  {"id":"warn-rm-rf","tool":"Bash","match":"rm -rf","action":"warn","message":"rm -rf — перепроверь путь"},
  {"id":"no-edit-migrations","tool":"*","match":"migrations/","action":"block","message":"Правка миграций без ревью запрещена"}
]
JSON

bash_pl() { jq -cn --arg c "$1" --arg cwd "${2:-$PROJ}" '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Bash",tool_input:{command:$c}}'; }
write_pl() { jq -cn --arg f "$1" --arg cwd "${2:-$PROJ}" '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Write",tool_input:{file_path:$f,content:"x"}}'; }

echo "user-rules (hookify) — сценарии:"

# 1. Bash matches block-rule -> block
OUT="$(run "$(bash_pl "git push --force origin main")")"
assert_contains "1a. force-push -> block (deny)" "$OUT" 'deny'
assert_contains "1b. ... с сообщением правила" "$OUT" 'Force-push запрещён'

# 2. Bash matches warn-rule -> warn
OUT="$(run "$(bash_pl "rm -rf /tmp/junk")")"
assert_contains "2a. rm -rf -> warn (additionalContext)" "$OUT" 'additionalContext'
assert_contains "2b. ... с сообщением правила" "$OUT" 'перепроверь путь'

# 3. Bash без совпадений -> pass
assert_empty "3. безопасная команда -> pass" "$(run "$(bash_pl "ls -la")")"

# 4. Write в migrations/ (правило tool:* ) -> block
OUT="$(run "$(write_pl "prisma/migrations/001_init.sql")")"
assert_contains "4. write migrations/ -> block (tool:*)" "$OUT" 'Правка миграций'

# 5. Write в обычный файл -> pass
assert_empty "5. write обычного файла -> pass" "$(run "$(write_pl "src/app.ts")")"

# 6. Нет user-rules.json -> pass (регрессия: поведение не меняется)
rm -f "$PROJ/.harness/user-rules.json"
assert_empty "6. нет user-rules.json -> pass" "$(run "$(bash_pl "git push --force")")"
# восстановить для остальных
cat > "$PROJ/.harness/user-rules.json" <<'JSON'
[{"id":"no-force-push","tool":"Bash","match":"push.*--force","action":"block","message":"Force-push запрещён (правило пользователя)"}]
JSON

# 7. minimal-профиль -> user-rules выключены
echo minimal > "$PROJ/.harness/profile"
assert_empty "7. профиль minimal -> pass (off)" "$(run "$(bash_pl "git push --force")")"
rm -f "$PROJ/.harness/profile"

# 8. Вывод block -> валидный JSON
OUT="$(run "$(bash_pl "git push --force")")"
if printf '%s' "$OUT" | jq empty 2>/dev/null; then PASS=$((PASS+1)); printf '  ok   8. block -> валидный JSON\n'
else FAIL=$((FAIL+1)); printf '  FAIL 8. block -> НЕ валидный JSON\n     получил: %s\n' "$OUT"; fi

# 9. Не-vibe-проект -> pass (guard)
NOPROJ="$(mktemp -d)"
assert_empty "9. не-vibe-проект -> pass" "$(run "$(bash_pl "git push --force" "$NOPROJ")")"
rm -rf "$NOPROJ"

rm -rf "$PROJ"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
