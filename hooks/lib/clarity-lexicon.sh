#!/bin/bash
# Vibe Dev v6.2 — общий лексикон ясности (sourced; F4).
# Один источник словарей для ДВУХ носителей:
#   - hooks/checks/clarity-detector.sh  (MessageDisplay: подсветка на экране + метрика)
#   - hooks/checks/clarity-stop-gate.sh (Stop: block/warn -> агент дописывает аддендум)
# Менять словари здесь — оба носителя подхватят. Block-tier обязан держать precision на
# labeled-корпусе tests/hooks/fixtures/clarity-corpus/ (self-check падает при false positive).

# --- Жаргон (целые слова, без учёта регистра) ---
# FULL: строгий режим (портрет jargon_tolerance: low).
CLARITY_JARGON_FULL='hook|hooks|payload|deploy|deployment|pipeline|dashboard|endpoint|middleware|backend|frontend|schema|migration|regex|webhook|enforcement|refactor|runtime|latency|throughput|embedding|inference|rollout|changelog|RLS|CTA|ROI|KPI|MVP|BANT|MQL|async|cache|commit|repository|workflow'
# CORE: ядро тяжёлых терминов (дефолт medium).
CLARITY_JARGON_CORE='hook|hooks|payload|deploy|deployment|pipeline|middleware|schema|migration|regex|webhook|enforcement|refactor|runtime|latency|throughput|embedding|inference|rollout|RLS|BANT|MQL'
# HARD (block-tier): термины, у которых НЕТ легитимного употребления в сообщении
# непрограммисту вне код-блоков. Узкий список ради precision ~1.0 (порог демоции).
CLARITY_JARGON_HARD='payload|middleware|enforcement|embedding|inference|refactor|throughput|webhook|rollout|RLS|BANT|MQL|idempoten\w*|polymorph\w*'

# --- Человеко-дни ---
# BLOCK-tier: явная ОЦЕНКА работы в днях («займёт 3 дня», «человеко-дни», «осталось 2 дня работы»).
# Факты («бот молчал 5 дней») сюда попадать НЕ должны — это warn-паттерн ниже ловит обобщённо.
# Регистр кириллицы — явными классами (grep -i ненадёжен для кириллицы на macOS, см. stop-intent).
CLARITY_HUMANDAYS_BLOCK='[Чч]еловеко-?дн|([Зз]айм[её]т|[Пп]отребует|[Оо]ценива[юе]|[Оо]сталось|[Пп]римерно|[Пп]лан на|[Уу]ложусь в)[^.!?]{0,40}[0-9]+[^.!?]{0,12}дн(я|ей|и)|[0-9]+ (рабочих|календарных) дн(я|ей)'
# WARN-tier: любые «N дней» (могут быть фактом — подсветить, не блокировать).
CLARITY_HUMANDAYS_WARN='[0-9]+ дн(я|ей)'

# --- Развилка без «что теряешь» / без рекомендации (эвристика -> warn-tier) ---
CLARITY_FORK_PATTERN='Вариант [АAБB1-3]|[Oo]ption [AB1-3]'
CLARITY_FORK_LOSS='теря(ешь|ем|ете)|что теряешь|чего лишишься|минус(ы)?:|недостат(ок|ки)'
CLARITY_FORK_RECO='[Рр]екоменду|[Сс]оветую|[Бб]еру вариант|[Мм]ой выбор|[Пп]редлагаю взять'

# clarity_strip_code: убрать ``` ... ``` блоки и `inline` код — термины в коде легитимны
# (главный источник false positives). stdin -> stdout.
clarity_strip_code() {
  awk 'BEGIN{inblock=0} /^[[:space:]]*```/{inblock=!inblock; next} !inblock{print}' \
    | sed -E 's/`[^`]*`//g'
}

# clarity_tolerance [портрет-файл] -> low|medium|high (нет файла/ключа -> medium).
clarity_tolerance() {
  local portrait="${1:-${VIBE_DEV_PORTRAIT:-$HOME/.vibe-dev/portrait.md}}" v=""
  if [ -f "$portrait" ]; then
    v="$(grep -m1 -E '^jargon_tolerance:' "$portrait" 2>/dev/null | sed -E 's/^jargon_tolerance:[[:space:]]*//; s/[[:space:]]*$//')"
  fi
  case "$v" in low|medium|high) printf '%s' "$v" ;; *) printf 'medium' ;; esac
}
