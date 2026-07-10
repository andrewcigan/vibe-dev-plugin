#!/bin/bash
# Vibe Dev v8 (L5-F6, agents-best-practices #6) — бюджет tool-call на активную фичу.
#
# Пробел #6 из сверки 8 правил: был только cost-preview ($), не было step/tool-call бюджета.
# Здесь: считаем tool-call с начала работы над active-фичей; при превышении бюджета — мягкий
# нудж «оцени, не залип ли; сделай /checkpoint или /stuck». Бюджет берётся из
# feature.tool_call_budget (feature_list.json), иначе дефолт.
#
# ЧЕСТНО discipline+nudge, НЕ в enforcement-счёт: число tool-call — ПРОКСИ усилия, порог
# эвристичен (как L4-F5). warn один раз на пересечение порога (не спамим каждый вызов),
# НИКОГДА не block. Смена active-фичи сбрасывает счётчик.
#
# Аргумент: $1=cwd. Печатает "WARN\t<msg>" или пусто. exit 0.
set -u
CWD="${1:-$PWD}"; TAB="$(printf '\t')"
FL="$CWD/feature_list.json"
[ -f "$FL" ] || exit 0

ACTIVE="$(jq -r '.active // empty' "$FL" 2>/dev/null)"
[ -n "$ACTIVE" ] || exit 0   # нет активной фичи — нечего бюджетировать

BUDGET="$(jq -r --arg id "$ACTIVE" '[.features[]?[]? | select(.id==$id) | .tool_call_budget] | map(select(type=="number")) | .[0] // empty' "$FL" 2>/dev/null)"
case "$BUDGET" in ''|*[!0-9]*) BUDGET=150 ;; esac   # дефолт — крупная фича; фича может задать свой

STATE="$CWD/.harness/feature-budget-state"
PREV_ID=""; COUNT=0; WARNED=0
if [ -f "$STATE" ]; then
  read -r PREV_ID COUNT WARNED < "$STATE" 2>/dev/null
  case "$COUNT" in ''|*[!0-9]*) COUNT=0 ;; esac
  case "$WARNED" in ''|*[!0-9]*) WARNED=0 ;; esac
fi
# смена активной фичи → новый бюджет
if [ "$PREV_ID" != "$ACTIVE" ]; then COUNT=0; WARNED=0; fi
COUNT=$((COUNT + 1))

OUT=""
if [ "$COUNT" -gt "$BUDGET" ] && [ "$WARNED" = "0" ]; then
  WARNED=1
  OUT="$(printf 'WARN%sБюджет tool-call на фичу %s исчерпан (%d > %d). Оцени честно: движешься к цели или залип? Варианты — сделай /checkpoint (зафиксируй прогресс в файлы), либо /stuck (если 3+ попытки не дали результата — сменить УРОВЕНЬ, не способ: субагент-диагностика). Бюджет — сигнал остановиться и подумать, не запрет.' "$TAB")"
fi

mkdir -p "$CWD/.harness" 2>/dev/null && printf '%s %d %d\n' "$ACTIVE" "$COUNT" "$WARNED" > "$STATE" 2>/dev/null
[ -n "$OUT" ] && printf '%s\n' "$OUT"
exit 0
