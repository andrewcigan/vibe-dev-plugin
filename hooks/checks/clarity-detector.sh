#!/bin/bash
# Vibe Dev v6 — clarity-detector (язык-ловец; дыра аудита 2026-06-05: коммуникация).
#
# Самая частая дыра v5 (8+ проектов, рецидив): жаргон / технические A/B / развилка без «что
# теряешь» / человеко-дни в сообщениях непрограммисту. Чинит её НЕ полностью — MessageDisplay
# display-only (меняет только экран, оригинал читает Claude). Реальный максимум: ДЕТЕКТОР меряет
# нарушение (диспетчер пишет лог) + подсвечивает (флаг на экране), чтобы оно не прошло тихо.
# Это честно «дисциплина + ловец-метрика», не «железобетон» (см. [[plain-language-decision-forks-iron-rule]]).
#
# v6.1 (онбординг): уровень строгости берётся из ПОРТРЕТА пользователя (~/.vibe-dev/portrait.md,
# ключ `jargon_tolerance: low|medium|high`). Нет портрета -> medium (нейтральный дефолт).
#   low    — ловит жаргон по ПОЛНОМУ списку (строгий режим для непрограммиста);
#   medium — ловит ЯДРО самых тяжёлых терминов, не придирается к пограничным (commit/cache/backend);
#   high   — жаргон и краткие развилки НЕ ловятся (технарю термины и сжатый выбор не мешают),
#            но человеко-дни ловятся ВСЕГДА (это про оценку работы агента, не про комфорт читателя).
#
# Вход — HOOK_PAYLOAD (env, ставит диспетчер), поле .message_text. Печатает СТРОКУ нарушений
# (диспетчер делает из неё лог + флаг) или пусто. exit 0.

set -u
MSG="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.message_text // empty' 2>/dev/null)"
[ -z "$MSG" ] && exit 0

# Уровень терпимости к жаргону из портрета. Frontmatter — markdown (НЕ JSON), достаём grep+sed.
# VIBE_DEV_PORTRAIT переопределяет путь (для тестов). Нет файла/ключа -> medium.
PORTRAIT="${VIBE_DEV_PORTRAIT:-$HOME/.vibe-dev/portrait.md}"
TOL="medium"
if [ -f "$PORTRAIT" ]; then
  v="$(grep -m1 -E '^jargon_tolerance:' "$PORTRAIT" 2>/dev/null | sed -E 's/^jargon_tolerance:[[:space:]]*//; s/[[:space:]]*$//')"
  case "$v" in low|medium|high) TOL="$v" ;; esac
fi

issues=""

# 1. Жаргон — английские технические термины (целые слова). Список зависит от уровня портрета.
JARGON_FULL='hook|hooks|payload|deploy|deployment|pipeline|dashboard|endpoint|middleware|backend|frontend|schema|migration|regex|webhook|enforcement|refactor|runtime|latency|throughput|embedding|inference|rollout|changelog|RLS|CTA|ROI|KPI|MVP|BANT|MQL|async|cache|commit|repository|workflow'
JARGON_CORE='hook|hooks|payload|deploy|deployment|pipeline|middleware|schema|migration|regex|webhook|enforcement|refactor|runtime|latency|throughput|embedding|inference|rollout|RLS|BANT|MQL'
JARGON=""
case "$TOL" in
  low)  JARGON="$JARGON_FULL" ;;
  high) JARGON="" ;;
  *)    JARGON="$JARGON_CORE" ;;   # medium (дефолт)
esac
if [ -n "$JARGON" ]; then
  found="$(printf '%s' "$MSG" | grep -woiE "($JARGON)" 2>/dev/null | tr 'A-Z' 'a-z' | sort -u | head -6 | tr '\n' ',' | sed 's/,$//')"
  [ -n "$found" ] && issues="технические слова ($found)"
fi

# 2. Человеко-дни в оценке (правило no-human-days для LLM-агента) — ВСЕГДА, независимо от уровня.
if printf '%s' "$MSG" | grep -qiE 'человеко-?дн|[0-9]+ (рабочих )?дн(я|ей)' 2>/dev/null; then
  issues="${issues:+$issues; }человеко-дни в оценке"
fi

# 3. Развилка (Вариант А/Б, Option A/B) БЕЗ «что теряешь» — кроме high (технарю краткий список норма).
if [ "$TOL" != "high" ] \
   && printf '%s' "$MSG" | grep -qE 'Вариант [АAБB1-3]|[Oo]ption [AB1-3]' 2>/dev/null \
   && ! printf '%s' "$MSG" | grep -qiE 'теря(ешь|ем|ете)|что теряешь|чего лишишься' 2>/dev/null; then
  issues="${issues:+$issues; }развилка без «что теряешь»"
fi

[ -n "$issues" ] && printf '%s' "$issues"
exit 0
