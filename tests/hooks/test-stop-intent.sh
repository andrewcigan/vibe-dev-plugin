#!/bin/bash
# Vibe Dev v6 — регрессионный тест Stop-диспетчера (волна 1, H19).
#
# H19: ход завершён маркером-намерением («сейчас запущу/стартую») И в ходе НЕ было
# ни одного tool_use → block (заставить продолжить). Защита от false-positive: блок
# только при (намерение И ноль действий); чистый ответ/вопрос/результат — проход.
#
# Воспроизводит РЕАЛЬНЫЙ триггер: Stop-payload (stdin JSON с transcript_path) + транскрипт
# в формате, ВЕРИФИЦИРОВАННОМ на живом transcript 2026-06-03: промпт пользователя =
# message.content СТРОКА (не массив text-блоков!); assistant = массив блоков; tool_result
# через toolUseResult. Правило hook-test-must-replay-real-trigger.
#
# Запуск: bash tests/hooks/test-stop-intent.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISPATCH="$PLUGIN_ROOT/hooks/dispatch-stop.sh"
PASS=0; FAIL=0

unset VIBE_DEV_PROFILE CLAUDE_PLUGIN_ROOT HOOK_PAYLOAD 2>/dev/null || true

# Сброс цепочки Stop-блоков перед каждым прогоном: этот тест проверяет ЛОГИКУ intent-детектора,
# общий cap цепочки (F3) тестируется отдельно в test-stop-dispatcher.sh.
run() { rm -f "$PROJ/.harness/stop-chain-count" 2>/dev/null; printf '%s' "$1" | bash "$DISPATCH"; }
assert_contains() {
  if printf '%s' "$2" | grep -q -- "$3"; then
    PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else
    FAIL=$((FAIL+1)); printf '  FAIL %s\n     ожидал найти: %s\n     получил: %s\n' "$1" "$3" "$2"
  fi
}
assert_empty() {
  if [ -z "$(printf '%s' "$2" | tr -d '[:space:]')" ]; then
    PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else
    FAIL=$((FAIL+1)); printf '  FAIL %s (ожидал пусто)\n     получил: %s\n' "$1" "$2"
  fi
}
block_in() { printf '%s' "$1" | grep -o '"decision":"block"'; }

# --- конструкторы записей транскрипта (verified-формат) ---
rec_user_prompt() { jq -cn --arg t "$1" '{type:"user",message:{role:"user",content:$t}}'; }  # реальный формат: content = СТРОКА
rec_asst_text()   { jq -cn --arg t "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'; }
rec_asst_think()  { jq -cn --arg t "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"thinking",thinking:$t}]}}'; }
rec_asst_tool()   { jq -cn --arg n "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:$n}]}}'; }
rec_user_result() { jq -cn '{type:"user",message:{role:"user",content:[{type:"tool_result"}]},toolUseResult:{stdout:"ok"}}'; }
# legacy-формат промпта (content = массив text-блоков) — должен распознаваться так же, как строковый
rec_user_prompt_arr() { jq -cn --arg t "$1" '{type:"user",message:{role:"user",content:[{type:"text",text:$t}]}}'; }

# --- mock vibe-проект ---
PROJ="$(mktemp -d)"
mkdir -p "$PROJ/.harness"
echo "7.0" > "$PROJ/.harness/engine-version"

stop_payload() {  # stop_payload <transcript_path> [cwd]
  jq -cn --arg tp "$1" --arg cwd "${2:-$PROJ}" \
    '{hook_event_name:"Stop",cwd:$cwd,transcript_path:$tp}'
}

echo "Stop dispatcher (H19 — намерение без действия) — сценарии:"

# 1. Намерение БЕЗ действия -> BLOCK (центральный сценарий)
T="$(mktemp)"
{ rec_user_prompt "сделай проверку"; rec_asst_think "надо запустить"; rec_asst_text "Сейчас запущу проверку wiring и доложу результат."; } > "$T"
OUT="$(run "$(stop_payload "$T")")"
assert_contains "1. намерение без действия -> block" "$OUT" '"decision":"block"'

# 2. Намерение + действие в том же ходе -> PASS (collapse — это ноль действий)
{ rec_user_prompt "сделай проверку"; rec_asst_text "Запускаю проверку."; rec_asst_tool "Bash"; rec_user_result; } > "$T"
OUT="$(run "$(stop_payload "$T")")"
assert_empty "2. намерение + tool_use -> pass" "$OUT"

# 3. Без маркера-намерения (вопрос/варианты), без действия -> PASS (легит конец хода)
{ rec_user_prompt "что лучше?"; rec_asst_text "Вот два варианта — A и B с плюсами и минусами. Что выбираешь?"; } > "$T"
OUT="$(run "$(stop_payload "$T")")"
assert_empty "3. вопрос/варианты без действия -> pass" "$OUT"

# 4. Результат (прошедшее время), без действия -> PASS
{ rec_user_prompt "как дела"; rec_asst_text "Готово. Все проверки прошли, git чистый."; } > "$T"
OUT="$(run "$(stop_payload "$T")")"
assert_empty "4. результат без маркера -> pass" "$OUT"

# 5. Граница хода: маркер в ПРОШЛОМ ходе, текущий ход чистый -> PASS
{ rec_user_prompt "сделай X"; rec_asst_text "Стартую."; rec_asst_tool "Write"; rec_user_result; \
  rec_user_prompt "спасибо, а статус?"; rec_asst_text "Статус: всё зелёное."; } > "$T"
OUT="$(run "$(stop_payload "$T")")"
assert_empty "5. маркер в прошлом ходе, текущий чистый -> pass" "$OUT"

# 6. minimal-профиль -> PASS (Stop-хук выключен)
echo minimal > "$PROJ/.harness/profile"
{ rec_user_prompt "сделай"; rec_asst_text "Сейчас запущу всё."; } > "$T"
OUT="$(run "$(stop_payload "$T")")"
assert_empty "6. профиль minimal -> pass (выключен)" "$OUT"
rm -f "$PROJ/.harness/profile"

# 7. strict-профиль -> BLOCK (активен)
echo strict > "$PROJ/.harness/profile"
{ rec_user_prompt "сделай"; rec_asst_text "Приступаю к реализации хука."; } > "$T"
OUT="$(run "$(stop_payload "$T")")"
assert_contains "7. профиль strict -> block" "$OUT" '"decision":"block"'
rm -f "$PROJ/.harness/profile"

# 8. Не vibe-проект (guard) -> PASS
NOPROJ="$(mktemp -d)"
{ rec_user_prompt "сделай"; rec_asst_text "Сейчас запущу."; } > "$T"
OUT="$(run "$(stop_payload "$T" "$NOPROJ")")"
assert_empty "8. не-vibe-проект -> pass" "$OUT"
rm -rf "$NOPROJ"

# 9. Нет transcript_path -> PASS (fail-safe)
OUT="$(run "$(jq -cn --arg cwd "$PROJ" '{hook_event_name:"Stop",cwd:$cwd}')")"
assert_empty "9. нет transcript_path -> pass (fail-safe)" "$OUT"

# 10. transcript_path указывает на несуществующий файл -> PASS (fail-safe)
OUT="$(run "$(stop_payload "/tmp/nope-$$-does-not-exist.jsonl")")"
assert_empty "10. transcript отсутствует -> pass (fail-safe)" "$OUT"

# 11. Вывод block — валидный JSON
{ rec_user_prompt "сделай"; rec_asst_text "Сейчас запущу проверку."; } > "$T"
OUT="$(run "$(stop_payload "$T")")"
if printf '%s' "$OUT" | jq empty 2>/dev/null; then
  PASS=$((PASS+1)); printf '  ok   11. вывод block — валидный JSON\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL 11. вывод block — НЕ валидный JSON\n     получил: %s\n' "$OUT"
fi

# 12. Регресс формата: промпт в legacy-формате (content = массив text-блоков) -> граница хода
#     находится так же, намерение без действия -> BLOCK. Старый jq с any(.type=="text") падал
#     на реальном СТРОКОВОМ content; этот сценарий + строковые выше держат оба формата.
{ rec_user_prompt_arr "сделай"; rec_asst_text "Сейчас запущу проверку."; } > "$T"
OUT="$(run "$(stop_payload "$T")")"
assert_contains "12. legacy массив-промпт -> block (оба формата границы)" "$OUT" '"decision":"block"'

rm -f "$T"; rm -rf "$PROJ"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
