#!/bin/bash
# Vibe Dev v6 — bulk-API gate (вызывается hooks/dispatch-pre-tool-use.sh на Bash).
#
# Детектит массовые вызовы внешних API в НАМЕРЕНИИ (tool_input.command из HOOK_PAYLOAD),
# а не постфактум. Если паттерн найден — требует пройденный .harness/pre-launch-checklist.yaml.
# Закрывает реальный инцидент: $25 + 48h бан внешнего API при массовом вызове без проверки квот.
#
# Печатает на stdout строки "BLOCK<TAB>msg". Пусто = OK. Всегда exit 0.
# Активен во ВСЕХ профилях (это про деньги/safety, не понижается learn-режимом).

set -u
CWD="${1:-$PWD}"
ROOT="${2:-}"
TAB="$(printf '\t')"

CMD="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$CMD" ] && exit 0

# tools-allowlist.yaml может явно выключить gate (нет секции bulk_api:)
ALLOW="$CWD/.harness/tools-allowlist.yaml"
if [ -f "$ALLOW" ] && ! grep -q "bulk_api:" "$ALLOW" 2>/dev/null; then
  exit 0
fi

# --- Детект bulk-паттернов в команде ---
# Цель — отличить РЕАЛЬНУЮ массовую работу (цикл по файлу/коллекции/много элементов,
# поток через xargs/parallel, LLM/embedding-батч) от ГОРСТКИ диагностических проб
# (3 retry, чтобы подтвердить, что 403 не транзиентный). Диагностику не блокируем:
# фиксированный перечень <=5 или {1..N<=6} по curl/wget — это проверка, не нагрузка.
detected=0
HAS_HTTP=0
printf '%s' "$CMD" | grep -qE '(curl|wget)' && HAS_HTTP=1

# (A) Поток данных через while-read / xargs / parallel рядом с curl/wget = всегда bulk
#     (число итераций = размер потока, неизвестно/велико).
if [ "$HAS_HTTP" -eq 1 ]; then
  if printf '%s' "$CMD" | grep -qE 'while[[:space:]]+(IFS=[^;]*[[:space:]]+)?read'; then detected=1; fi
  if [ "$detected" -eq 0 ] && printf '%s' "$CMD" | grep -qE '(xargs|parallel)([[:space:]]|$)'; then detected=1; fi
fi

# (B) for-петля с curl/wget: анализируем ТОЛЬКО перечень (между "in" и ";"/"do"),
#     а не тело (в curl-теле может быть $i — это не делает цикл массовым).
if [ "$detected" -eq 0 ] && [ "$HAS_HTTP" -eq 1 ] && \
   printf '%s' "$CMD" | grep -qE 'for[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+in[[:space:]]'; then
  items="$(printf '%s' "$CMD" | sed -nE 's/.*for[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+in[[:space:]]+(.*)/\1/p' | head -1)"
  items="$(printf '%s' "$items" | sed -E 's/;.*//; s/[[:space:]]+do([[:space:]].*)?$//')"
  if printf '%s' "$items" | grep -qE '\$\(|`|\$\{?[A-Za-z_]|\*|\.txt|\.csv|\.tsv|\.json|\.jsonl|\.ndjson|seq[[:space:]]|cat[[:space:]]'; then
    detected=1   # динамический/файловый перечень = массовая работа
  else
    range="$(printf '%s' "$items" | grep -oE '\{[0-9]+\.\.[0-9]+\}' | head -1)"
    if [ -n "$range" ]; then
      a="${range#\{}"; a="${a%%..*}"; b="${range##*..}"; b="${b%\}}"
      if [ "$b" -ge "$a" ]; then cnt=$(( b - a + 1 )); else cnt=$(( a - b + 1 )); fi
      [ "$cnt" -gt 6 ] && detected=1   # {1..6} и меньше — диагностика; больше — bulk
    else
      n="$(printf '%s' "$items" | wc -w | tr -d ' ')"
      [ "${n:-0}" -gt 5 ] && detected=1   # >5 фиксированных элементов — bulk
    fi
  fi
fi

# (C) Прямая LLM/embedding-батч сигнатура (стоимость/квота вне зависимости от формы цикла)
if [ "$detected" -eq 0 ] && \
   printf '%s' "$CMD" | grep -qE '(openai|anthropic|gemini|voyage).*(embed|generate|messages\.create|chat\.completions)'; then
  detected=1
fi

# Детект по числу API-вызовов в запускаемом скрипте (python/node/ts с >5 вызовами)
if [ "$detected" -eq 0 ] && printf '%s' "$CMD" | grep -qE '(python3?|node|ts-node|bun) '; then
  sf="$(printf '%s' "$CMD" | grep -oE '[a-zA-Z0-9_./-]+\.(py|js|ts)' | head -1)"
  for cand in "$CWD/$sf" "$sf"; do
    if [ -n "$sf" ] && [ -f "$cand" ]; then
      n="$(grep -cE '(openai|anthropic|gemini|google.*generative|requests\.(post|get)|fetch\()' "$cand" 2>/dev/null)"
      n=${n:-0}
      [ "$n" -gt 5 ] && detected=1
      break
    fi
  done
fi

[ "$detected" -eq 0 ] && exit 0

# --- Detected: проверяем pre-launch-checklist ---
CHECKLIST="$CWD/.harness/pre-launch-checklist.yaml"
if [ ! -f "$CHECKLIST" ]; then
  printf 'BLOCK%sМассовый внешний API-вызов без pre-launch-checklist. Скопируй templates/pre-launch-checklist.yaml в .harness/, заполни (стоимость, Batch API, дневная квота, dedup, checkpoint) и выстави decision.status: approved.\n' "$TAB"
  exit 0
fi

status="$(grep -E '^[[:space:]]*status:' "$CHECKLIST" | head -1 | sed -E 's/.*status:[[:space:]]*"?([a-z_]+)"?.*/\1/')"
if [ "$status" != "approved" ] && [ "$status" != "approved_with_user_confirm" ]; then
  printf 'BLOCK%spre-launch-checklist.decision.status="%s" (нужно approved). Заполни обязательные галки checklist и выстави approved.\n' "$TAB" "$status"
  exit 0
fi

# Cost gate: оценка > $2 требует явного подтверждения пользователя
est="$(grep -E '^[[:space:]]*estimate_usd:' "$CHECKLIST" | head -1 | sed -E 's/.*estimate_usd:[[:space:]]*"?([0-9.]+)"?.*/\1/')"
if [ -n "$est" ]; then
  over="$(awk -v e="$est" 'BEGIN{print (e+0>2.0)?1:0}' 2>/dev/null || echo 0)"
  if [ "$over" = "1" ]; then
    conf="$(grep -A2 'user_confirmed_if_over_2usd:' "$CHECKLIST" | grep -E 'answer:' | head -1 | sed -E 's/.*answer:[[:space:]]*"?(true|false)"?.*/\1/')"
    if [ "$conf" != "true" ]; then
      printf 'BLOCK%sОценка $%s > $2 — нужно явное подтверждение пользователя. Выстави user_confirmed_if_over_2usd.answer: true и впиши цитату подтверждения.\n' "$TAB" "$est"
      exit 0
    fi
  fi
fi
exit 0
