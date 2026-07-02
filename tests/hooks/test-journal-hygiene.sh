#!/bin/bash
# Vibe Dev v7 (Волна 4) — тесты гигиены журнала: read-only аудит + дешёвый дедуп + circuit breaker.
# Запуск: bash tests/hooks/test-journal-hygiene.sh
set -u
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PLUGIN_ROOT" || exit 1
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness"
cat > "$PROJ/error-journal.md" <<'J'
## err-001 | 2026-07-01 | feat-1
**status**: active
- problem: парсер падает на кириллице в URL
**Класс ошибки**: domain_knowledge
## err-002 | 2026-07-01 | feat-2
**status**: active
- problem: Парсер падает на кириллице в URL
**Класс ошибки**: domain_knowledge
## err-003 | 2026-07-02 | feat-3
- problem: таймаут внешнего API
**Класс ошибки**: api_research
J

AUD="$(bash scripts/journal-audit.sh "$PROJ")"
printf '%s' "$AUD" | grep -q "записей 3, active 2, без штампа устаревания 1" && ok "1. счётчики записей/active/без штампа" || bad "1. счётчики"
printf '%s' "$AUD" | grep -q "Повтор классов" && ok "2. повтор класса пойман" || bad "2. повтор класса"
printf '%s' "$AUD" | grep -q "повторные problem" && ok "3. дубль problem пойман (кириллица нормализована)" || bad "3. дубль problem"

# Пустой журнал → не падает, докладывает норму
EMPTY="$(mktemp -d)"
bash scripts/journal-audit.sh "$EMPTY" | grep -q "нет файла" && ok "4. нет журнала → норма" || bad "4. нет журнала"

# Circuit breaker: одинаковая команда, порог 3 → warn, 6 → circuit
rm -f "$PROJ/.harness/bash-repeat-state"
CMD='{"tool_input":{"command":"npx tsc --noEmit"}}'
declare -a TAGS
i=1
while [ "$i" -le 6 ]; do
  R=$(HOOK_PAYLOAD="$CMD" bash hooks/checks/bash-repeat-counter.sh "$PROJ")
  if printf '%s' "$R" | grep -q "Circuit breaker"; then TAGS[$i]="C"
  elif printf '%s' "$R" | grep -q "признак залипания"; then TAGS[$i]="W"
  else TAGS[$i]="-"; fi
  i=$((i+1))
done
[ "${TAGS[3]}" = "W" ] && ok "5. порог 3 → мягкий warn" || bad "5. порог 3 → warn (got ${TAGS[3]})"
[ "${TAGS[6]}" = "C" ] && ok "6. порог 6 → circuit breaker" || bad "6. порог 6 → circuit (got ${TAGS[6]})"
[ "${TAGS[4]}" = "-" ] && [ "${TAGS[5]}" = "-" ] && ok "7. между порогами тихо (нет спама)" || bad "7. между порогами тихо"

rm -rf "$PROJ" "$EMPTY" 2>/dev/null
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ]
