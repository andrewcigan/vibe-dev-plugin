#!/bin/bash
# Vibe Dev v6.2 — тест research-гейта архитектуры + lock-паттерна (F6).
#
# Распоряжение пользователя 2026-06-10: рисёрч перед архитектурой обязателен; пропуск —
# только явной фразой. Контракты:
#   - Write docs/ARCHITECTURE*.md без docs/research/*.md и без маркера -> BLOCK (глоб имени);
#   - lock-паттерн: маркер пишет ТОЛЬКО хук (research-skip-listener по фразе);
#     запись агентом в .harness/locks/* (Write/Bash-redirect) -> BLOCK; rm — разрешён.
#
# Запуск: bash tests/hooks/test-research-gate.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PRE="$PLUGIN_ROOT/hooks/dispatch-pre-tool-use.sh"
UP="$PLUGIN_ROOT/hooks/dispatch-user-prompt.sh"
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
assert_file() { if [ -f "$2" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL %s (файл должен существовать: %s)\n' "$1" "$2"; fi; }
assert_absent() { if [ ! -f "$2" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL %s (файла быть не должно: %s)\n' "$1" "$2"; fi; }

PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness"
echo "7.0" > "$PROJ/.harness/engine-version"; echo strict > "$PROJ/.harness/profile"

write_payload() { # $1=file_path
  jq -cn --arg cwd "$PROJ" --arg fp "$1" \
    '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Write",tool_input:{file_path:$fp,content:"# arch"}}'
}
bash_payload() { # $1=command
  jq -cn --arg cwd "$PROJ" --arg c "$1" \
    '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Bash",tool_input:{command:$c}}'
}
prompt_payload() { # $1=prompt
  jq -cn --arg cwd "$PROJ" --arg p "$1" '{hook_event_name:"UserPromptSubmit",cwd:$cwd,prompt:$p}'
}

echo "Research-гейт архитектуры + lock-паттерн (F6) — сценарии:"

# 1. ARCHITECTURE.md без рисёрча -> BLOCK
OUT="$(printf '%s' "$(write_payload "$PROJ/docs/ARCHITECTURE.md")" | bash "$PRE")"
assert_contains "1a. без research -> deny" "$OUT" '"permissionDecision":"deny"'
assert_contains "1b. remediation: запустить researcher-агентов" "$OUT" "github-researcher"

# 2. Вариант имени не обходит глоб
OUT="$(printf '%s' "$(write_payload "$PROJ/docs/ARCHITECTURE-v2.md")" | bash "$PRE")"
assert_contains "2. ARCHITECTURE-v2.md -> тоже deny (глоб)" "$OUT" '"permissionDecision":"deny"'

# 3. С артефактом рисёрча -> pass
mkdir -p "$PROJ/docs/research"; echo "# research" > "$PROJ/docs/research/architecture-research.md"
OUT="$(printf '%s' "$(write_payload "$PROJ/docs/ARCHITECTURE.md")" | bash "$PRE")"
assert_not_contains "3. docs/research/*.md есть -> pass" "$OUT" '"permissionDecision":"deny"'
rm -rf "$PROJ/docs/research"

# 4. Lock-паттерн: явная фраза пользователя -> хук ставит маркер + inject
OUT="$(printf '%s' "$(prompt_payload "пропусти рисёрч, я уверен в архитектуре")" | bash "$UP")"
assert_file     "4a. маркер research-skipped поставлен хуком" "$PROJ/.harness/locks/research-skipped"
assert_contains "4b. в маркере цитата" "$(cat "$PROJ/.harness/locks/research-skipped")" "quote:"
assert_contains "4c. inject подтверждает фиксацию" "$OUT" "ПРОПУЩЕН"

# 5. С маркером гейт пропускает
OUT="$(printf '%s' "$(write_payload "$PROJ/docs/ARCHITECTURE.md")" | bash "$PRE")"
assert_not_contains "5. маркер research-skipped -> pass" "$OUT" '"permissionDecision":"deny"'
rm -f "$PROJ/.harness/locks/research-skipped"

# 6. Обычный промпт маркер НЕ ставит
OUT="$(printf '%s' "$(prompt_payload "продолжаем работу над фичей")" | bash "$UP")"
assert_absent "6. обычный промпт -> маркера нет" "$PROJ/.harness/locks/research-skipped"

# 7. Запись агентом в locks/ -> BLOCK (Write)
OUT="$(printf '%s' "$(write_payload "$PROJ/.harness/locks/research-skipped")" | bash "$PRE")"
assert_contains "7. Write в .harness/locks/ -> deny (lock-protect)" "$OUT" '"permissionDecision":"deny"'

# 8. Bash-redirect в locks/ -> BLOCK
OUT="$(printf '%s' "$(bash_payload "echo x > .harness/locks/research-skipped")" | bash "$PRE")"
assert_contains "8. echo > locks/ -> deny" "$OUT" '"permissionDecision":"deny"'

# 9. rm маркера разрешён (строгая сторона)
OUT="$(printf '%s' "$(bash_payload "rm .harness/locks/research-skipped")" | bash "$PRE")"
assert_not_contains "9. rm маркера -> pass (движение к строгости)" "$OUT" '"permissionDecision":"deny"'

# 10. Не-ARCHITECTURE docs не трогаем
OUT="$(printf '%s' "$(write_payload "$PROJ/docs/PRODUCT.md")" | bash "$PRE")"
assert_not_contains "10. docs/PRODUCT.md -> гейт молчит" "$OUT" '"permissionDecision":"deny"'

rm -rf "$PROJ"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
