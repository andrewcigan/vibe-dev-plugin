#!/bin/bash
# Vibe Dev v6.2 — clarity-stop-gate (F4; закрывает боль №1 аудита: жаргон / развилки без
# рекомендации / человеко-дни доходили до пользователя при пустом логе ловца).
#
# Носитель: Stop-хук. Вход stdin-payload содержит .last_assistant_message (движок >=2.1.47) —
# текст финального ответа БЕЗ парсинга транскрипта. При нарушении печатает BLOCK -> диспетчер
# заставляет агента ДОПИСАТЬ короткий аддендум (НЕ переписывать всё: первое сообщение
# пользователь уже видел — честная ценность: «ход не закончится ТОЛЬКО непонятным сообщением»).
#
# Tiered по precision (правило демоции: block-tier держит 0 false-positive на labeled-корпусе
# tests/hooks/fixtures/clarity-corpus/, иначе self-check красный и детектор уезжает в warn):
#   BLOCK: (а) человеко-дни как ОЦЕНКА работы (узкий regex; факты «бот молчал 5 дней» не матчатся);
#          (б) HARD-жаргон вне код-блоков (узкий словарь без легитимных употреблений).
#   WARN:  развилка «Вариант А/Б» без «что теряешь» или без рекомендации (эвристика).
#
# Включение BLOCK-tier (без него всё демотируется в WARN): профиль strict ИЛИ портрет
# существует с jargon_tolerance != high (пользователь-непрограммист попросил строгость).
# Без портрета и не-strict — нейтральный дефолт v6.1: warn.
#
# Свой лимит: <=2 BLOCK на цепочку хода (.harness/clarity-stop-count, сброс на UserPromptSubmit);
# дальше — демоция в WARN + .harness/clarity-cap-log. Поверх работает общий cap диспетчера (3).
#
# Аргументы: $1 = cwd, $2 = профиль. Печатает "BLOCK\tmsg" / "WARN\tmsg", пусто = ОК. exit 0.

set -u
CWD="${1:-$PWD}"
PROFILE="${2:-standard}"
TAB="$(printf '\t')"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/clarity-lexicon.sh"

MSG="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.last_assistant_message // empty' 2>/dev/null)"
[ -z "$MSG" ] && exit 0

TOL="$(clarity_tolerance)"
PORTRAIT_FILE="${VIBE_DEV_PORTRAIT:-$HOME/.vibe-dev/portrait.md}"

# BLOCK-tier включён? strict — всегда; иначе только по явному портрету непрограммиста.
BLOCK_ENABLED=0
if [ "$PROFILE" = "strict" ]; then
  BLOCK_ENABLED=1
elif [ -f "$PORTRAIT_FILE" ] && [ "$TOL" != "high" ]; then
  BLOCK_ENABLED=1
fi

# Термины в коде легитимны: вырезаем ```блоки``` и `inline` ДО детекции (precision).
CLEAN="$(printf '%s' "$MSG" | clarity_strip_code)"

block_issues=""
warn_issues=""

# BLOCK (а): человеко-дни как оценка работы (регистр кириллицы — в классах паттерна, без -i).
if printf '%s' "$CLEAN" | grep -qE "$CLARITY_HUMANDAYS_BLOCK" 2>/dev/null; then
  block_issues="оценка работы в человеко-днях (агент не оценивается в днях — только размер S/M/L)"
fi

# BLOCK (б): HARD-жаргон вне кода (high-терпимость выключает жаргонную часть).
if [ "$TOL" != "high" ]; then
  hard_found="$(printf '%s' "$CLEAN" | grep -woiE "($CLARITY_JARGON_HARD)" 2>/dev/null | tr 'A-Z' 'a-z' | sort -u | head -5 | tr '\n' ',' | sed 's/,$//')"
  if [ -n "$hard_found" ]; then
    block_issues="${block_issues:+$block_issues; }тяжёлый жаргон вне кода: $hard_found"
  fi
fi

# WARN: развилка без «что теряешь» или без рекомендации.
if [ "$TOL" != "high" ] && printf '%s' "$CLEAN" | grep -qE "$CLARITY_FORK_PATTERN" 2>/dev/null; then
  miss=""
  printf '%s' "$CLEAN" | grep -qiE "$CLARITY_FORK_LOSS" 2>/dev/null || miss="«что теряешь» по каждому пути"
  if ! printf '%s' "$CLEAN" | grep -qiE "$CLARITY_FORK_RECO" 2>/dev/null; then
    miss="${miss:+$miss и }твоя рекомендация"
  fi
  [ -n "$miss" ] && warn_issues="в развилке не хватает: $miss"
fi

REMEDIATION="НЕ переписывай сообщение целиком — добавь короткое дополнение (до 10 строк): то же самое простыми словами без терминов; если предлагался выбор — по каждому пути «что получишь / что теряешь» + одна твоя рекомендация. Затем заверши ход. [clarity-gate]"

if [ -n "$block_issues" ]; then
  if [ "$BLOCK_ENABLED" -eq 1 ]; then
    # Свой лимит <=2 BLOCK на цепочку: дальше демоция (не бесконечная дописка).
    CNT_FILE="$CWD/.harness/clarity-stop-count"
    CNT=0
    [ -f "$CNT_FILE" ] && { CNT="$(tr -dc '0-9' < "$CNT_FILE" 2>/dev/null)"; CNT="${CNT:-0}"; }
    if [ "$CNT" -ge 2 ]; then
      mkdir -p "$CWD/.harness" 2>/dev/null
      printf '%s\tclarity-cap\t%s\n' "$(date '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?')" "$block_issues" \
        >> "$CWD/.harness/clarity-cap-log" 2>/dev/null
      printf 'WARN%s[лимит дописок] Сообщение всё ещё непонятно (%s) — учти в следующем ответе.\n' "$TAB" "$block_issues"
    else
      mkdir -p "$CWD/.harness" 2>/dev/null
      printf '%s\n' "$((CNT + 1))" > "$CNT_FILE" 2>/dev/null
      printf 'BLOCK%sСообщение, завершающее ход, непонятно пользователю-непрограммисту: %s. %s\n' "$TAB" "$block_issues" "$REMEDIATION"
    fi
  else
    printf 'WARN%sСообщение содержит: %s. %s\n' "$TAB" "$block_issues" "$REMEDIATION"
  fi
fi

if [ -n "$warn_issues" ]; then
  printf 'WARN%s%s. %s\n' "$TAB" "$warn_issues" "$REMEDIATION"
fi
exit 0
