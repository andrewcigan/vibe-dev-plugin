#!/bin/bash
# Vibe Dev v6.2.1 — тест interrupt-recovery (авто-продолжение после ТЕХНИЧЕСКОГО прерывания).
#
# Боль (диагностика 2026-06-12 по 51 interrupt-событию боевых сессий): обрыв клиентского
# канала (закрытая крышка ноутбука) и доставка входящего сообщения помечают выполняющийся
# инструмент «The user doesn't want to proceed…» + «[Request interrupted by user]» — агент
# читает «STOP and wait» и стоит часами, хотя пользователь ничего не запрещал.
# Механизм: на UserPromptSubmit — если хвост ПОСЛЕДНЕГО хода в transcript содержит
# interrupt/reject-маркеры, после последнего маркера работа не возобновлялась, и в новом
# промпте НЕТ стоп-слов → inject «прерывание было техническим, продолжай план».
#
# Фикстуры воспроизводят РЕАЛЬНЫЕ формы записей transcript 2.1.170 (память
# hook-test-must-replay-real-trigger): промпт = content-СТРОКА; reject = tool_result-блок
# + toolUseResult="User rejected tool use"; interrupt-text = text-блок "[Request interrupted…]".
#
# Запуск: bash tests/hooks/test-interrupt-recovery.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISPATCH="$PLUGIN_ROOT/hooks/dispatch-user-prompt.sh"
PASS=0; FAIL=0

unset VIBE_DEV_PROFILE CLAUDE_PLUGIN_ROOT HOOK_PAYLOAD 2>/dev/null || true

run() { printf '%s' "$1" | bash "$DISPATCH"; }
assert_contains() {
  if printf '%s' "$2" | grep -q -- "$3"; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s\n     ожидал найти: %s\n     получил: %s\n' "$1" "$3" "$2"; fi
}
assert_not_contains() {
  if printf '%s' "$2" | grep -q -- "$3"; then FAIL=$((FAIL+1)); printf '  FAIL %s (НЕ ожидал «%s»)\n     получил: %s\n' "$1" "$3" "$2"
  else PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; fi
}

PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness"; echo "7.0" > "$PROJ/.harness/engine-version"
TR="$PROJ/transcript.jsonl"

payload() {  # payload <prompt> — UserPromptSubmit payload c transcript_path
  jq -cn --arg p "$1" --arg cwd "$PROJ" --arg tr "$TR" \
    '{hook_event_name:"UserPromptSubmit",cwd:$cwd,prompt:$p,transcript_path:$tr}'
}

# --- Строки transcript в реальной форме 2.1.170 ---
REAL_PROMPT='{"type":"user","message":{"role":"user","content":"запусти e2e и доведи фичу"},"timestamp":"2026-06-11T20:50:00.000Z","cwd":"/x"}'
ASSIST_TOOL='{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_01X","name":"Bash","input":{"command":"pnpm test"}}]},"timestamp":"2026-06-11T20:54:50.000Z"}'
REJECT_PROCEED='{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"The user doesn'"'"'t want to proceed with this tool use. The tool use was rejected (eg. if it was a file edit, the new_string was NOT written to the file). STOP what you are doing and wait for the user to tell you how to proceed.","is_error":true,"tool_use_id":"toolu_01X"}]},"toolUseResult":"User rejected tool use","timestamp":"2026-06-11T21:04:50.000Z"}'
REJECT_ACTION='{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"The user doesn'"'"'t want to take this action right now. STOP what you are doing and wait for the user to tell you how to proceed.","is_error":true,"tool_use_id":"toolu_01X"}]},"timestamp":"2026-06-11T21:04:50.000Z"}'
IRQ_TEXT='{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]},"timestamp":"2026-06-11T21:04:50.100Z"}'
ASSIST_WAIT='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Останавливаюсь — жду вашего сигнала."}]},"timestamp":"2026-06-11T21:05:16.000Z"}'
TOOL_OK='{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok","tool_use_id":"toolu_01X"}]},"toolUseResult":{"stdout":"ok"},"timestamp":"2026-06-11T20:55:00.000Z"}'

echo "interrupt-recovery (авто-продолжение после технического прерывания) — сценарии:"

# 1. Оборванный ход (reject+interrupt в хвосте) + обычный промпт -> inject
printf '%s\n' "$REAL_PROMPT" "$ASSIST_TOOL" "$REJECT_PROCEED" "$IRQ_TEXT" "$ASSIST_WAIT" > "$TR"
OUT="$(run "$(payload "продолжаем работу по плану")")"
assert_contains "1a. оборванный ход + обычный промпт -> inject" "$OUT" 'interrupt-recovery'
assert_contains "1b. ... объясняет что это не запрет" "$OUT" 'ТЕХНИЧЕСК'

# 2. Тот же хвост, но в промпте стоп-слово -> МОЛЧИМ (сознательная остановка)
OUT="$(run "$(payload "стоп, не продолжай это")")"
assert_not_contains "2a. промпт со «стоп» -> тихо" "$OUT" 'interrupt-recovery'
OUT="$(run "$(payload "подожди, отмени правку")")"
assert_not_contains "2b. «подожди/отмени» -> тихо" "$OUT" 'interrupt-recovery'

# 3. Чистый хвост (работа завершилась нормально) -> тихо
printf '%s\n' "$REAL_PROMPT" "$ASSIST_TOOL" "$TOOL_OK" "$ASSIST_WAIT" > "$TR"
OUT="$(run "$(payload "продолжаем")")"
assert_not_contains "3. чистый хвост -> тихо" "$OUT" 'interrupt-recovery'

# 4. Interrupt был, но работа возобновилась в том же хвосте (tool_use после) -> тихо
printf '%s\n' "$REAL_PROMPT" "$ASSIST_TOOL" "$REJECT_PROCEED" "$IRQ_TEXT" "$ASSIST_TOOL" "$TOOL_OK" > "$TR"
OUT="$(run "$(payload "как дела?")")"
assert_not_contains "4. возобновилась после interrupt -> тихо" "$OUT" 'interrupt-recovery'

# 5. Permission-deny формулировка («take this action», таймаут 600с) -> inject
printf '%s\n' "$REAL_PROMPT" "$ASSIST_TOOL" "$REJECT_ACTION" "$ASSIST_WAIT" > "$TR"
OUT="$(run "$(payload "ну что там")")"
assert_contains "5. deny-таймаут разрешения -> inject" "$OUT" 'interrupt-recovery'

# 6. Interrupt в ПРОШЛОМ ходе (после него настоящий промпт и нормальная работа) -> тихо
printf '%s\n' "$REAL_PROMPT" "$ASSIST_TOOL" "$REJECT_PROCEED" "$IRQ_TEXT" \
  '{"type":"user","message":{"role":"user","content":"продолжай"},"timestamp":"2026-06-12T04:22:01.000Z"}' \
  "$ASSIST_TOOL" "$TOOL_OK" > "$TR"
OUT="$(run "$(payload "и что в итоге?")")"
assert_not_contains "6. interrupt в прошлом ходе -> тихо" "$OUT" 'interrupt-recovery'

# 7. Нет transcript_path / нет файла -> тихо, не падает
OUT="$(printf '%s' "$(jq -cn --arg cwd "$PROJ" '{cwd:$cwd,prompt:"привет"}')" | bash "$DISPATCH")"
assert_not_contains "7a. нет transcript_path -> тихо" "$OUT" 'interrupt-recovery'
rm -f "$TR"
OUT="$(run "$(payload "привет")")"
assert_not_contains "7b. transcript отсутствует на диске -> тихо" "$OUT" 'interrupt-recovery'

# 8. Вывод — валидный JSON (когда inject есть)
printf '%s\n' "$REAL_PROMPT" "$ASSIST_TOOL" "$REJECT_PROCEED" "$IRQ_TEXT" > "$TR"
OUT="$(run "$(payload "поехали дальше")")"
if printf '%s' "$OUT" | jq empty 2>/dev/null; then PASS=$((PASS+1)); printf '  ok   8. inject — валидный JSON\n'
else FAIL=$((FAIL+1)); printf '  FAIL 8. inject — НЕ валидный JSON\n     получил: %s\n' "$OUT"; fi

# 9. minimal-профиль -> выключен
echo minimal > "$PROJ/.harness/profile"
OUT="$(run "$(payload "продолжаем работу")")"
assert_not_contains "9. профиль minimal -> тихо" "$OUT" 'interrupt-recovery'
rm -f "$PROJ/.harness/profile"

rm -rf "$PROJ"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
