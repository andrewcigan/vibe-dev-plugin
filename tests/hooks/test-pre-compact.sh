#!/bin/bash
# Vibe Dev v7 (Волна 2) — тест M2 (слепок перед сжатием, hooks/pre-compact.sh).
#
# Проверяет: extractive-парсинг транскрипта берёт РЕАЛЬНЫЕ просьбы пользователя (первую +
# последнюю), отсекает шум (isMeta, <command-name>, toolUseResult), пишет честную пометку
# «ФАКТЫ, не статус», в не-vibe-проект не пишет. Событие PreCompact подтверждено живым
# прогоном 2026-07-02 (2.1.170) — здесь тест парсера на РЕАЛЬНЫХ формах записей транскрипта.
#
# Запуск: bash tests/hooks/test-pre-compact.sh
set -u
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/pre-compact.sh"
PASS=0; FAIL=0
unset CLAUDE_PLUGIN_ROOT HOOK_PAYLOAD 2>/dev/null || true

assert_contains() {
  if printf '%s' "$2" | grep -qF -- "$3"; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s\n     ожидал найти: %s\n' "$1" "$3"; fi
}
assert_not_contains() {
  if printf '%s' "$2" | grep -qF -- "$3"; then FAIL=$((FAIL+1)); printf '  FAIL %s (НЕ ожидал «%s»)\n' "$1" "$3"
  else PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; fi
}

PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness"; echo '{"features":{}}' > "$PROJ/feature_list.json"
TR="$PROJ/transcript.jsonl"
# Реальные формы записей транскрипта 2.1.170: промпт = content-строка; meta = isMeta:true;
# слэш-команда = <command-name>; ответ агента = assistant с text-блоком.
{
  printf '%s\n' '{"type":"queue-operation"}'
  printf '%s\n' '{"type":"user","message":{"content":"Построй парсер накладных PDF"}}'
  printf '%s\n' '{"type":"user","isMeta":true,"message":{"content":[{"type":"text","text":"META-ШУМ-не-должен-попасть"}]}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"СТАТУС-ГОТОВО-passing"}]}}'
  printf '%s\n' '{"type":"user","message":{"content":"<command-name>/compact</command-name>"}}'
  printf '%s\n' '{"type":"user","message":{"content":"Добавь валидацию ИНН контрагента"}}'
} > "$TR"

payload() { jq -cn --arg cwd "$1" --arg tr "$2" \
  '{hook_event_name:"PreCompact",cwd:$cwd,transcript_path:$tr,trigger:"manual"}'; }

# 1. vibe-проект → слепок создаётся
printf '%s' "$(payload "$PROJ" "$TR")" | bash "$HOOK"
CK="$(cat "$PROJ/.harness/last-checkpoint.md" 2>/dev/null || echo '')"
[ -n "$CK" ] && { PASS=$((PASS+1)); echo "  ok   1. слепок создан"; } || { FAIL=$((FAIL+1)); echo "  FAIL 1. слепок НЕ создан"; }

# 2. первая реальная просьба захвачена
assert_contains "2. первая просьба в слепке" "$CK" "Построй парсер накладных PDF"
# 3. последняя реальная просьба захвачена
assert_contains "3. последняя просьба в слепке" "$CK" "Добавь валидацию ИНН контрагента"
# 4. шум отсеян (isMeta)
assert_not_contains "4. isMeta-шум отсеян" "$CK" "META-ШУМ-не-должен-попасть"
# 5. слэш-команда отсеяна
assert_not_contains "5. <command-name> отсеян" "$CK" "command-name"
# 6. честная пометка ФАКТЫ (а не статус)
assert_contains "6. честная пометка «ФАКТЫ, не статус»" "$CK" "ФАКТЫ о ходе сессии"
# 7. статус агента, если попал — только под пометкой «НЕ сверенный статус»
assert_contains "7. хвост агента под честной пометкой" "$CK" "НЕ сверенный статус"

# 8. не-vibe cwd → слепок НЕ пишется
NV="$(mktemp -d)"
printf '%s' "$(payload "$NV" "$TR")" | bash "$HOOK"
[ -f "$NV/.harness/last-checkpoint.md" ] && { FAIL=$((FAIL+1)); echo "  FAIL 8. записал в не-vibe"; } || { PASS=$((PASS+1)); echo "  ok   8. в не-vibe не пишет"; }

# 9. битый transcript_path → тихий пропуск (exit 0), не падает
printf '%s' "$(payload "$PROJ" "$PROJ/нет-такого.jsonl")" | bash "$HOOK"; rc=$?
[ "$rc" = "0" ] && { PASS=$((PASS+1)); echo "  ok   9. битый путь → exit 0 (fail-open)"; } || { FAIL=$((FAIL+1)); echo "  FAIL 9. упал на битом пути (rc=$rc)"; }

rm -rf "$PROJ" "$NV" 2>/dev/null
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ]
