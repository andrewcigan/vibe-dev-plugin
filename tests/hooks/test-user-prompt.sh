#!/bin/bash
# Vibe Dev v6 — регрессионный тест UserPromptSubmit-диспетчера (волна 1):
#   H6 (handoff-reminder) + анти-залипание (стоп-сигнал, прокси №1 tunnel-vision).
#
# H6 часть 1: промпт содержит сигнал завершения сессии («закрываем / на сегодня всё /
# стартуй новую сессию») -> inject mental cold-start чеклиста (additionalContext), чтобы
# план ушёл в файлы, а не остался в чате. Уровень warn (inject), НЕ block — промпт легитимен.
# Закрывает паттерн handoff через слова (30 мин проработки повисли в чате).
#
# Воспроизводит реальный триггер: UserPromptSubmit-payload (stdin JSON с полем промпта).
# ⚠️ Имя поля промпта в payload НЕ верифицировано на живом — хук читает с fallback
# (.prompt/.user_prompt/.message); тест подаёт .prompt (наиболее вероятное).
#
# Запуск: bash tests/hooks/test-user-prompt.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISPATCH="$PLUGIN_ROOT/hooks/dispatch-user-prompt.sh"
PASS=0; FAIL=0

unset VIBE_DEV_PROFILE CLAUDE_PLUGIN_ROOT HOOK_PAYLOAD 2>/dev/null || true

run() { printf '%s' "$1" | bash "$DISPATCH"; }
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

PROJ="$(mktemp -d)"
mkdir -p "$PROJ/.harness"
echo "6.0" > "$PROJ/.harness/engine-version"

up_payload() {  # up_payload <prompt> [cwd]
  jq -cn --arg p "$1" --arg cwd "${2:-$PROJ}" \
    '{hook_event_name:"UserPromptSubmit",cwd:$cwd,prompt:$p}'
}

echo "UserPromptSubmit dispatcher (H6 — handoff reminder) — сценарии:"

# 1. Сигнал завершения -> inject additionalContext с чеклистом
OUT="$(run "$(up_payload "ну всё, закрываем сессию на сегодня")")"
assert_contains "1a. сигнал завершения -> additionalContext" "$OUT" '"additionalContext"'
assert_contains "1b. ... содержит cold-start чеклист" "$OUT" 'SESSION.md'

# 2. Обычный рабочий промпт -> pass (пусто)
OUT="$(run "$(up_payload "давай сделаем следующую фичу, добавь Stop-хук")")"
assert_empty "2. обычный промпт -> pass" "$OUT"

# 3. Другой сигнал («стартуй новую сессию») -> inject
OUT="$(run "$(up_payload "стартуй новую сессию, в первом сообщении расскажи план")")"
assert_contains "3. 'стартуй новую сессию' -> additionalContext" "$OUT" '"additionalContext"'

# 4. Сигнал в середине промпта -> inject (grep подстроки)
OUT="$(run "$(up_payload "ок спасибо, на сегодня всё, до завтра")")"
assert_contains "4. сигнал в середине -> additionalContext" "$OUT" '"additionalContext"'

# 5. minimal-профиль -> pass (выключен)
echo minimal > "$PROJ/.harness/profile"
OUT="$(run "$(up_payload "закрываем сессию")")"
assert_empty "5. профиль minimal -> pass" "$OUT"
rm -f "$PROJ/.harness/profile"

# 6. Не vibe-проект -> pass (guard)
NOPROJ="$(mktemp -d)"
OUT="$(run "$(up_payload "закрываем сессию" "$NOPROJ")")"
assert_empty "6. не-vibe-проект -> pass" "$OUT"
rm -rf "$NOPROJ"

# 7. Вывод — валидный JSON
OUT="$(run "$(up_payload "закрываем")")"
if printf '%s' "$OUT" | jq empty 2>/dev/null; then
  PASS=$((PASS+1)); printf '  ok   7. вывод — валидный JSON\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL 7. вывод — НЕ валидный JSON\n     получил: %s\n' "$OUT"
fi

# 8. Fallback по имени поля: payload с .user_prompt вместо .prompt -> inject
OUT="$(run "$(jq -cn --arg p "закрываем сессию" --arg cwd "$PROJ" '{hook_event_name:"UserPromptSubmit",cwd:$cwd,user_prompt:$p}')")"
assert_contains "8. fallback поля .user_prompt -> additionalContext" "$OUT" '"additionalContext"'

# 9. При сигнале завершения ставится маркер handoff-pending (для SessionStart-probe, loop H6)
rm -f "$PROJ/.harness/handoff-pending"
run "$(up_payload "закрываем сессию")" >/dev/null
if [ -f "$PROJ/.harness/handoff-pending" ]; then PASS=$((PASS+1)); printf '  ok   9. сигнал -> маркер handoff-pending поставлен\n'
else FAIL=$((FAIL+1)); printf '  FAIL 9. маркер handoff-pending НЕ поставлен\n'; fi

# 10. Обычный промпт -> маркер НЕ ставится
rm -f "$PROJ/.harness/handoff-pending"
run "$(up_payload "добавь ещё одну фичу")" >/dev/null
if [ ! -f "$PROJ/.harness/handoff-pending" ]; then PASS=$((PASS+1)); printf '  ok   10. обычный промпт -> маркер не ставится\n'
else FAIL=$((FAIL+1)); printf '  FAIL 10. маркер поставлен ошибочно\n'; fi

# --- Анти-залипание: детектор стоп-сигнала пользователя (прокси №1 tunnel-vision) ---
echo ""
echo "UserPromptSubmit dispatcher (анти-залипание — стоп-сигнал) — сценарии:"

# 11. Стоп-сигнал «мы не то делаем» -> inject напоминания (смена УРОВНЯ, не способа)
OUT="$(run "$(up_payload "стоп, мы не то делаем, вернись назад")")"
assert_contains "11a. стоп-сигнал -> additionalContext" "$OUT" '"additionalContext"'
assert_contains "11b. ... напоминание про УРОВЕНЬ" "$OUT" 'УРОВН'

# 12. Стоп-сигнал НЕ ставит маркер handoff-pending (это не сигнал завершения сессии)
rm -f "$PROJ/.harness/handoff-pending"
run "$(up_payload "ты залип, остановись")" >/dev/null
if [ ! -f "$PROJ/.harness/handoff-pending" ]; then PASS=$((PASS+1)); printf '  ok   12. стоп-сигнал -> маркер handoff НЕ ставится\n'
else FAIL=$((FAIL+1)); printf '  FAIL 12. стоп-сигнал ошибочно поставил маркер handoff\n'; fi

# 13. Латинское "Stop-хук" в рабочем промпте -> pass (нет ложного срабатывания)
OUT="$(run "$(up_payload "добавь Stop-хук и не забудь тест")")"
assert_empty "13. латинский Stop-хук -> pass (нет FP)" "$OUT"

# 14. «Не туда» с заглавной в начале -> inject
OUT="$(run "$(up_payload "Не туда копаешь, давай иначе")")"
assert_contains "14. 'Не туда' (заглавная) -> additionalContext" "$OUT" 'УРОВН'

# 15. Комбинация: завершение + стоп-сигнал -> оба текста, маркер handoff стоит
rm -f "$PROJ/.harness/handoff-pending"
OUT="$(run "$(up_payload "на сегодня всё, и кстати мы не то делаем")")"
assert_contains "15a. комбо -> cold-start чеклист" "$OUT" 'SESSION.md'
assert_contains "15b. комбо -> анти-залипание" "$OUT" 'УРОВН'
if [ -f "$PROJ/.harness/handoff-pending" ]; then PASS=$((PASS+1)); printf '  ok   15c. комбо -> маркер handoff стоит\n'
else FAIL=$((FAIL+1)); printf '  FAIL 15c. комбо -> маркер handoff не поставлен\n'; fi

rm -rf "$PROJ"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
