#!/bin/bash
# Vibe Dev v6 — clarity-detector (язык-ловец на MessageDisplay; экранная подсветка + метрика).
#
# v6.2 (F4): словари вынесены в hooks/lib/clarity-lexicon.sh — ОБЩИЙ источник с
# clarity-stop-gate.sh (Stop: block/warn). Этот детектор остаётся display-слоем:
# MessageDisplay меняет только экран (оригинал читает Claude) — подсветка, чтобы нарушение
# не прошло тихо, + лог .harness/clarity-violations.log (recurrence-метрика). Enforcement
# контента теперь делает stop-gate (см. traceability).
#
# Уровень строгости — из портрета (~/.vibe-dev/portrait.md, jargon_tolerance: low|medium|high);
# нет портрета -> medium. high: жаргон и краткие развилки не ловятся, человеко-дни — всегда.
#
# Вход — HOOK_PAYLOAD (env), поле .message_text. Печатает строку нарушений или пусто. exit 0.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/clarity-lexicon.sh"

MSG="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.message_text // empty' 2>/dev/null)"
[ -z "$MSG" ] && exit 0

TOL="$(clarity_tolerance)"

issues=""

# 1. Жаргон — английские технические термины (целые слова). Список зависит от уровня портрета.
JARGON=""
case "$TOL" in
  low)  JARGON="$CLARITY_JARGON_FULL" ;;
  high) JARGON="" ;;
  *)    JARGON="$CLARITY_JARGON_CORE" ;;   # medium (дефолт)
esac
if [ -n "$JARGON" ]; then
  found="$(printf '%s' "$MSG" | grep -woiE "($JARGON)" 2>/dev/null | tr 'A-Z' 'a-z' | sort -u | head -6 | tr '\n' ',' | sed 's/,$//')"
  [ -n "$found" ] && issues="технические слова ($found)"
fi

# 2. Человеко-дни в оценке (правило no-human-days) — ВСЕГДА, независимо от уровня.
if printf '%s' "$MSG" | grep -qiE "($CLARITY_HUMANDAYS_BLOCK|$CLARITY_HUMANDAYS_WARN)" 2>/dev/null; then
  issues="${issues:+$issues; }человеко-дни в оценке"
fi

# 3. Развилка (Вариант А/Б, Option A/B) БЕЗ «что теряешь» — кроме high (технарю краткий список норма).
if [ "$TOL" != "high" ] \
   && printf '%s' "$MSG" | grep -qE "$CLARITY_FORK_PATTERN" 2>/dev/null \
   && ! printf '%s' "$MSG" | grep -qiE "$CLARITY_FORK_LOSS" 2>/dev/null; then
  issues="${issues:+$issues; }развилка без «что теряешь»"
fi

[ -n "$issues" ] && printf '%s' "$issues"
exit 0
