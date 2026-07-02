#!/bin/bash
# Vibe Dev v6.2 — тест секрет-гигиены (F8; П8 аудита: ключ в чате без предупреждения о
# ротации; VERCEL_TOKEN напечатан в вывод).
#
# Контракты:
#   - живой ключ в промпте -> inject: компрометация + ротация + .env + $VAR (НЕ block);
#   - живой токен в выводе Bash -> updatedToolOutput: маска (8 символов + MASKED) + памятка;
#   - чистые промпт/вывод -> тихо (precision: голый "sk-" не ловится).
#
# Запуск: bash tests/hooks/test-secret-hygiene.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UP="$PLUGIN_ROOT/hooks/dispatch-user-prompt.sh"
PT="$PLUGIN_ROOT/hooks/dispatch-post-tool-use.sh"
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
assert_empty() {
  if [ -z "$(printf '%s' "$2" | tr -d '[:space:]')" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s (ожидал пусто)\n     получил: %s\n' "$1" "$2"; fi
}

PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness"
echo "7.0" > "$PROJ/.harness/engine-version"; echo strict > "$PROJ/.harness/profile"

up() { jq -cn --arg cwd "$PROJ" --arg p "$1" '{hook_event_name:"UserPromptSubmit",cwd:$cwd,prompt:$p}' | bash "$UP"; }
pt() { # $1=stdout инструмента
  jq -cn --arg cwd "$PROJ" --arg o "$1" \
    '{hook_event_name:"PostToolUse",cwd:$cwd,tool_name:"Bash",tool_input:{command:"vercel env ls"},tool_response:{stdout:$o,exit_code:0,success:true}}' \
    | bash "$PT"
}

echo "Секрет-гигиена (F8) — сценарии:"

# 1. Ключ OpenRouter в промпте (реальный кейс аудита)
OUT="$(up "вот ключ sk-or-v1-aaaabbbbccccddddeeeeffff111122223333 сохрани куда надо")"
assert_contains "1a. ключ в промпте -> inject" "$OUT" "additionalContext"
assert_contains "1b. слово про компрометацию" "$OUT" "СКОМПРОМЕТИРОВАН"
assert_contains "1c. направление в .env" "$OUT" ".env"
assert_contains "1d. тип ключа распознан (OpenRouter)" "$OUT" "OpenRouter"

# 2. Токен GitHub
OUT="$(up "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ123456 — токен для репо")"
assert_contains "2. GitHub-токен распознан" "$OUT" "GitHub"

# 3. Чистый промпт — тихо; голый sk- не ловится (precision)
OUT="$(up "сделай задачу со skill-файлом и sk-метрикой")"
assert_not_contains "3. чистый промпт без секретов -> нет 🔐" "$OUT" "СКОМПРОМЕТИРОВАН"

# 4. Токен в выводе Bash -> updatedToolOutput с маской
RAW_OUT="VERCEL_TOKEN=ghp_SECRETSECRETSECRETSECRET123456 production"
OUT="$(pt "$RAW_OUT")"
assert_contains     "4a. вывод заменён (updatedToolOutput)" "$OUT" "updatedToolOutput"
assert_contains     "4b. маска на месте" "$OUT" "MASKED-by-vibe-dev"
assert_not_contains "4c. полного токена в выводе больше нет" "$OUT" "SECRETSECRETSECRETSECRET123456"
assert_contains     "4d. первые 8 символов сохранены (узнаваемость)" "$OUT" "ghp_SECR"
assert_contains     "4e. памятка про \$VAR" "$OUT" "ИМЯ_ПЕРЕМЕННОЙ"

# 5. Чистый вывод -> updatedToolOutput НЕ эмитится
OUT="$(pt "Deployment ready: https://app.example.com")"
assert_not_contains "5. чистый вывод -> без подмены" "$OUT" "updatedToolOutput"

# 6. Вывод диспетчера при маскировании — валидный JSON
OUT="$(pt "$RAW_OUT")"
if printf '%s' "$OUT" | jq empty 2>/dev/null; then PASS=$((PASS+1)); printf '  ok   6. JSON валиден\n'
else FAIL=$((FAIL+1)); printf '  FAIL 6. вывод не JSON\n     %s\n' "$OUT"; fi

rm -rf "$PROJ"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
