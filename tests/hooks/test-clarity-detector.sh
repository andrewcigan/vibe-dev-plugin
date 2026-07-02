#!/bin/bash
# Vibe Dev v6 — регрессионный тест clarity-detector (язык-ловец; дыра аудита: коммуникация).
#
# Самая частая дыра v5 (8+ проектов, рецидив): жаргон / технические A/B / развилка без «что
# теряешь» в сообщениях непрограммисту. Механизм честно НЕ 100% (MessageDisplay display-only:
# меняет только экран пользователя, оригинал читаю я). Что реально: ДЕТЕКТОР меряет (лог) +
# подсвечивает (флаг на экране), чтобы нарушение не проходило тихо.
#
# v6.1: уровень строгости берётся из портрета (jargon_tolerance). Тесты 9-13 проверяют уровни.
# Существующие сценарии 1-8 идут под medium (дефолт) — VIBE_DEV_PORTRAIT указан на несуществующий
# путь, чтобы тест НЕ читал реальный ~/.vibe-dev/portrait.md машины.
#
# Тест гонит реальный триггер через dispatch-message-display.sh (payload .message_text).
# Запуск: bash tests/hooks/test-clarity-detector.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISPATCH="$PLUGIN_ROOT/hooks/dispatch-message-display.sh"
PASS=0; FAIL=0
unset VIBE_DEV_PROFILE CLAUDE_PLUGIN_ROOT HOOK_PAYLOAD 2>/dev/null || true
# Дефолт для сценариев 1-8: medium (портрета нет).
export VIBE_DEV_PORTRAIT="/nonexistent/vibe-portrait-$$.md"

run() { printf '%s' "$1" | bash "$DISPATCH"; }
assert_contains() {
  if printf '%s' "$2" | grep -q -- "$3"; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s\n     ожидал: %s\n     получил: %s\n' "$1" "$3" "$2"; fi
}
assert_empty() {
  if [ -z "$(printf '%s' "$2" | tr -d '[:space:]')" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s (ожидал пусто)\n     получил: %s\n' "$1" "$2"; fi
}

PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness"; echo "7.0" > "$PROJ/.harness/engine-version"
md_pl() { jq -cn --arg m "$1" --arg cwd "${2:-$PROJ}" '{hook_event_name:"MessageDisplay",cwd:$cwd,message_text:$m}'; }

echo "clarity-detector (язык-ловец) — сценарии:"

# 1. Жаргон -> displayContent с флагом + запись в лог
rm -f "$PROJ/.harness/clarity-violations.log"
OUT="$(run "$(md_pl "Я настроил hook и сделал deploy на прод, проверь dashboard")")"
assert_contains "1a. жаргон -> displayContent" "$OUT" 'displayContent'
assert_contains "1b. ... флаг ловца" "$OUT" 'ловец'
assert_contains "1c. ... оригинал сообщения сохранён" "$OUT" 'настроил'
if [ -f "$PROJ/.harness/clarity-violations.log" ]; then PASS=$((PASS+1)); printf '  ok   1d. нарушение записано в лог (метрика)\n'
else FAIL=$((FAIL+1)); printf '  FAIL 1d. лог нарушений не создан\n'; fi

# 2. Чистое человеческое сообщение -> pass (оригинал показывается как есть)
assert_empty "2. чистое сообщение -> pass" "$(run "$(md_pl "Готово — кнопка теперь работает, проверил сам")")"

# 3. Развилка БЕЗ «что теряешь» -> флаг
OUT="$(run "$(md_pl "Вариант А — Postgres. Вариант Б — Mongo. Рекомендую А.")")"
assert_contains "3. развилка без «теряешь» -> displayContent" "$OUT" 'displayContent'

# 4. Развилка С «что теряешь» и без жаргона -> pass
assert_empty "4. развилка с «теряешь» -> pass" "$(run "$(md_pl "Вариант А — что получишь скорость, что теряешь гибкость. Вариант Б — наоборот. Советую А.")")"

# 5. Человеко-дни -> флаг
OUT="$(run "$(md_pl "Эта задача займёт примерно 5 рабочих дней")")"
assert_contains "5. человеко-дни -> флаг" "$OUT" 'displayContent'

# 6. minimal-профиль -> pass (ловец выключен)
echo minimal > "$PROJ/.harness/profile"
assert_empty "6. профиль minimal -> pass" "$(run "$(md_pl "сделал deploy через hook")")"
rm -f "$PROJ/.harness/profile"

# 7. Не-vibe-проект -> pass (guard)
NOPROJ="$(mktemp -d)"
assert_empty "7. не-vibe-проект -> pass" "$(run "$(md_pl "deploy hook payload" "$NOPROJ")")"
rm -rf "$NOPROJ"

# 8. Вывод -> валидный JSON
OUT="$(run "$(md_pl "deploy на прод через hook")")"
if printf '%s' "$OUT" | jq empty 2>/dev/null; then PASS=$((PASS+1)); printf '  ok   8. вывод — валидный JSON\n'
else FAIL=$((FAIL+1)); printf '  FAIL 8. вывод — НЕ валидный JSON\n     получил: %s\n' "$OUT"; fi

# --- v6.1: уровни строгости из портрета (jargon_tolerance) ---
HIGH_P="$(mktemp)"; printf -- '---\njargon_tolerance: high\nanswer_level: technical\n---\n# portrait\n' > "$HIGH_P"
LOW_P="$(mktemp)";  printf -- '---\njargon_tolerance: low\n---\n# portrait\n' > "$LOW_P"

# 9. high -> жаргон НЕ ловится (технарю термины не мешают)
export VIBE_DEV_PORTRAIT="$HIGH_P"
assert_empty "9. портрет high -> жаргон не ловится" "$(run "$(md_pl "сделал deploy через hook, проверь pipeline")")"

# 10. high -> краткая развилка без «теряешь» НЕ ловится
assert_empty "10. портрет high -> краткая развилка ок" "$(run "$(md_pl "Вариант А — Postgres. Вариант Б — Mongo. Рекомендую А.")")"

# 11. high -> человеко-дни ЛОВЯТСЯ всегда (это про оценку работы агента)
OUT="$(run "$(md_pl "Задача займёт 5 рабочих дней")")"
assert_contains "11. портрет high -> человеко-дни всё равно ловятся" "$OUT" 'displayContent'

# 12. low -> пограничный термин (commit/repository) ловится (полный список)
export VIBE_DEV_PORTRAIT="$LOW_P"
OUT="$(run "$(md_pl "сделай commit в repository")")"
assert_contains "12. портрет low -> пограничный термин ловится" "$OUT" 'displayContent'

# 13. medium (дефолт) -> тот же пограничный термин НЕ придирается (ядро жаргона)
export VIBE_DEV_PORTRAIT="/nonexistent/vibe-portrait-$$.md"
assert_empty "13. дефолт medium -> пограничный термин не ловится" "$(run "$(md_pl "сделай commit в repository")")"

rm -f "$HIGH_P" "$LOW_P"
rm -rf "$PROJ"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
