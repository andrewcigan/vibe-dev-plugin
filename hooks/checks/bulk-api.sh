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
detected=0
PATTERNS='for .* in .*(curl|wget)
while read.*(curl|wget)
xargs.*(curl|wget)
parallel.*(curl|wget)
for i in \{1\.\.[0-9]+\}.*(curl|wget)
(openai|anthropic|gemini|voyage).*(embed|generate|messages\.create|chat\.completions)'
while IFS= read -r p; do
  [ -z "$p" ] && continue
  if printf '%s' "$CMD" | grep -qE "$p"; then detected=1; break; fi
done <<EOF
$PATTERNS
EOF

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
