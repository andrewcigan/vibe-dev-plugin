#!/bin/bash
# Vibe Dev v6 — регрессионный тест PreToolUse-диспетчера (волна 0).
#
# Проверяет НАМЕРЕНИЕ: подаёт tool_input.content (Write) / old_string+new_string (Edit) /
# edits (MultiEdit) / command (Bash) в payload, как настоящий Claude Code, и убеждается,
# что хук валидирует ИТОГОВОЕ содержимое после правки, а не старое состояние диска.
#
# Покрывает: state-machine gate (content-aware), bulk-API gate, concurrent-write advisory,
# version-awareness (legacy/learn → структурные warn, но UI-evidence hard всегда).
#
# verification command волны 0. Запуск: bash tests/hooks/test-pre-tool-use.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISPATCH="$PLUGIN_ROOT/hooks/dispatch-pre-tool-use.sh"
PASS=0; FAIL=0

unset VIBE_DEV_PROFILE CLAUDE_PLUGIN_ROOT HOOK_PAYLOAD 2>/dev/null || true

run() { printf '%s' "$1" | bash "$DISPATCH"; }
assert_contains() {
  if printf '%s' "$2" | grep -q -- "$3"; then
    PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else
    FAIL=$((FAIL+1)); printf '  FAIL %s\n     ожидал найти: %s\n     получил: %s\n' "$1" "$3" "$2"
  fi
}
assert_empty() {
  if [ -z "$(printf '%s' "$2" | tr -d '[:space:]')" ]; then
    PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else
    FAIL=$((FAIL+1)); printf '  FAIL %s (ожидал пусто)\n     получил: %s\n' "$1" "$2"
  fi
}
deny_in() { printf '%s' "$1" | grep -o '"permissionDecision":"deny"'; }

# --- Mock-проект (актуальный движок: есть engine-version) ---
PROJ="$(mktemp -d)"
mkdir -p "$PROJ/.harness"
echo "6.0" > "$PROJ/.harness/engine-version"
FL="$PROJ/feature_list.json"

write_payload() {  # write_payload <file_path> <content>
  jq -cn --arg fp "$1" --arg c "$2" --arg cwd "$PROJ" \
    '{hook_event_name:"PreToolUse",tool_name:"Write",cwd:$cwd,tool_input:{file_path:$fp,content:$c}}'
}
edit_payload() {   # edit_payload <file_path> <old> <new>
  jq -cn --arg fp "$1" --arg o "$2" --arg n "$3" --arg cwd "$PROJ" \
    '{hook_event_name:"PreToolUse",tool_name:"Edit",cwd:$cwd,tool_input:{file_path:$fp,old_string:$o,new_string:$n}}'
}
multiedit_payload() {  # multiedit_payload <file_path> <old> <new>
  jq -cn --arg fp "$1" --arg o "$2" --arg n "$3" --arg cwd "$PROJ" \
    '{hook_event_name:"PreToolUse",tool_name:"MultiEdit",cwd:$cwd,tool_input:{file_path:$fp,edits:[{old_string:$o,new_string:$n}]}}'
}
bash_payload() {  # bash_payload <command>
  jq -cn --arg cmd "$1" --arg cwd "$PROJ" \
    '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$cwd,tool_input:{command:$cmd}}'
}
write_payload_sid() {  # write_payload_sid <file_path> <content> <session_id>
  jq -cn --arg fp "$1" --arg c "$2" --arg cwd "$PROJ" --arg sid "$3" \
    '{hook_event_name:"PreToolUse",tool_name:"Write",cwd:$cwd,session_id:$sid,tool_input:{file_path:$fp,content:$c}}'
}

BAD_UI='{"features":{"passing_list":[{"id":"feat-204","state":"passing","category":"ui","affected_files":["src/components/Demo.tsx"],"evidence":{}}]}}'
GOOD_UI='{"features":{"passing_list":[{"id":"feat-204","state":"passing","category":"ui","affected_files":["src/components/Demo.tsx"],"evidence":{"layer_4_user_at":"2026-06-03"}}]}}'
GOOD_API='{"features":{"passing_list":[{"id":"feat-101","state":"passing","category":"api","affected_files":["src/api/x.ts"],"evidence":{"layer_1_syntax_at":"2026-06-03"},"verification":{"layer_1_syntax":true}}]}}'
ACTIVE_UI='{"features":{"active_list":[{"id":"feat-204","state":"active","category":"ui","affected_files":["src/components/Demo.tsx"]}]}}'
BAD_STATE='{"features":{"up_next_list":[{"id":"feat-9","state":"banana","category":"infra","affected_files":["x"]}]}}'

echo "PreToolUse dispatcher — сценарии:"

# 1. НЕ vibe-проект -> pass
NOPROJ="$(mktemp -d)"
OUT="$(jq -cn --arg c "$BAD_UI" --arg cwd "$NOPROJ" '{hook_event_name:"PreToolUse",tool_name:"Write",cwd:$cwd,tool_input:{file_path:($cwd+"/feature_list.json"),content:$c}}' | bash "$DISPATCH")"
assert_empty "1. не-vibe-проект -> pass" "$OUT"

# 2. Чужой файл в vibe-проекте -> pass
OUT="$(run "$(write_payload "$PROJ/src/app.ts" "$BAD_UI")")"
assert_empty "2. другой файл -> pass" "$OUT"

# 3. Write НОВОГО файла, битая UI -> BLOCK (раньше fail-open)
rm -f "$FL"
OUT="$(run "$(write_payload "$FL" "$BAD_UI")")"
assert_contains "3a. Write нового файла, битая UI -> deny" "$OUT" '"permissionDecision":"deny"'
assert_contains "3b. ... содержит feat-204" "$OUT" 'feat-204'

# 4. Edit active(валидно на диске) -> passing без evidence -> BLOCK (UI hard)
printf '%s' "$ACTIVE_UI" > "$FL"
OUT="$(run "$(edit_payload "$FL" "$ACTIVE_UI" "$BAD_UI")")"
assert_contains "4. Edit active->passing без evidence -> deny" "$OUT" '"permissionDecision":"deny"'

# 5. Исправление: на диске битое, Write добавляет evidence -> pass
printf '%s' "$BAD_UI" > "$FL"
OUT="$(run "$(write_payload "$FL" "$GOOD_UI")")"
assert_empty "5. исправление битого диска (Write с evidence) -> pass" "$OUT"

# 6. learn-mode: СТРУКТУРНАЯ ошибка понижается до WARN; UI-evidence — всё равно hard BLOCK
rm -f "$FL"
echo learn > "$PROJ/.harness/hook-mode"
OUT="$(run "$(write_payload "$FL" "$BAD_STATE")")"
assert_contains "6a. learn: структурная ошибка -> additionalContext" "$OUT" '"additionalContext"'
assert_empty "6b. learn: структурная -> НЕ блокирует" "$(deny_in "$OUT")"
OUT="$(run "$(write_payload "$FL" "$BAD_UI")")"
assert_contains "6c. learn: UI-evidence всё равно -> deny (hard)" "$OUT" '"permissionDecision":"deny"'
rm -f "$PROJ/.harness/hook-mode"

# 7. minimal-профиль -> state-transition выключен целиком
echo minimal > "$PROJ/.harness/profile"
OUT="$(run "$(write_payload "$FL" "$BAD_UI")")"
assert_empty "7. профиль minimal -> pass (проверка выключена)" "$OUT"
rm -f "$PROJ/.harness/profile"

# 8. Корректная non-UI passing с evidence -> pass
OUT="$(run "$(write_payload "$FL" "$GOOD_API")")"
assert_empty "8. корректная non-UI passing -> pass" "$OUT"

# 9. Невалидный state в актуальном проекте -> BLOCK (soft=block)
OUT="$(run "$(write_payload "$FL" "$BAD_STATE")")"
assert_contains "9. невалидный state (актуальный) -> deny" "$OUT" '"permissionDecision":"deny"'

# 10. MultiEdit active->passing без evidence -> BLOCK (UI hard)
printf '%s' "$ACTIVE_UI" > "$FL"
OUT="$(run "$(multiedit_payload "$FL" "$ACTIVE_UI" "$BAD_UI")")"
assert_contains "10. MultiEdit active->passing без evidence -> deny" "$OUT" '"permissionDecision":"deny"'

# 11. Вывод block — валидный JSON
rm -f "$FL"
OUT="$(run "$(write_payload "$FL" "$BAD_UI")")"
if printf '%s' "$OUT" | jq empty 2>/dev/null; then
  PASS=$((PASS+1)); printf '  ok   11. вывод block — валидный JSON\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL 11. вывод block — НЕ валидный JSON\n     получил: %s\n' "$OUT"
fi

# --- bulk-API gate (Bash) ---
# 12. Безопасная команда -> pass
OUT="$(run "$(bash_payload "git status && ls -la")")"
assert_empty "12. безопасная Bash-команда -> pass" "$OUT"
# 13. Bulk-паттерн без checklist -> BLOCK
rm -f "$PROJ/.harness/pre-launch-checklist.yaml"
OUT="$(run "$(bash_payload 'for u in $(cat urls.txt); do curl -s "$u"; done')")"
assert_contains "13. bulk-API без checklist -> deny" "$OUT" '"permissionDecision":"deny"'
# 14. Bulk + checklist approved -> pass
printf 'decision:\n  status: approved\n' > "$PROJ/.harness/pre-launch-checklist.yaml"
OUT="$(run "$(bash_payload 'for u in $(cat urls.txt); do curl -s "$u"; done')")"
assert_empty "14. bulk-API + checklist approved -> pass" "$OUT"
rm -f "$PROJ/.harness/pre-launch-checklist.yaml"
# 15. Не-vibe + bulk -> pass
OUT="$(jq -cn --arg cwd "$NOPROJ" --arg cmd 'for u in $(cat x); do curl "$u"; done' '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$cwd,tool_input:{command:$cmd}}' | bash "$DISPATCH")"
assert_empty "15. не-vibe + bulk -> pass" "$OUT"

# --- bulk-API: диагностика vs реальный bulk (false-positive fix) ---
rm -f "$PROJ/.harness/pre-launch-checklist.yaml"
# 15a. Диагностика: 3 retry по одному хосту (литералы) -> pass (НЕ bulk)
OUT="$(run "$(bash_payload 'for i in 1 2 3; do curl -s "https://api.gladia.io/v2/$i"; done')")"
assert_empty "15a. диагностика for i in 1 2 3 + curl -> pass" "$OUT"
# 15b. Диагностика: малый брейс-range {1..3} -> pass
OUT="$(run "$(bash_payload 'for i in {1..3}; do curl -s https://api.gladia.io; done')")"
assert_empty "15b. диагностика for i in {1..3} + curl -> pass" "$OUT"
# 15c. Реальный bulk: большой брейс {1..1000} -> deny
OUT="$(run "$(bash_payload 'for i in {1..1000}; do curl -s "https://api.x/$i"; done')")"
assert_contains "15c. bulk {1..1000} + curl -> deny" "$OUT" '"permissionDecision":"deny"'
# 15d. Реальный bulk: фиксированный перечень >5 элементов -> deny
OUT="$(run "$(bash_payload 'for u in a b c d e f g; do curl -s "https://api.x/$u"; done')")"
assert_contains "15d. bulk 7 литералов + curl -> deny" "$OUT" '"permissionDecision":"deny"'
# 15e. Реальный bulk: while-read поток -> deny
OUT="$(run "$(bash_payload 'while read u; do curl -s "$u"; done < urls.txt')")"
assert_contains "15e. bulk while-read + curl -> deny" "$OUT" '"permissionDecision":"deny"'
# 15f. Одиночный curl (не цикл) -> pass
OUT="$(run "$(bash_payload 'curl -s -o /dev/null -w "%{http_code}" https://api.gladia.io')")"
assert_empty "15f. одиночный curl -> pass" "$OUT"
rm -f "$PROJ/.harness/pre-launch-checklist.yaml"

# --- concurrent-write advisory (session-based WARN, не block) ---
# 16. Первая запись в shared-файл -> pass
rm -rf "$PROJ/.harness/locks"
OUT="$(run "$(write_payload_sid "$PROJ/data.json" '{"x":1}' "sessionA")")"
assert_empty "16. concurrent: первая запись -> pass" "$OUT"
# 17. Другая сессия сразу после -> WARN (не блок)
OUT="$(run "$(write_payload_sid "$PROJ/data.json" '{"x":2}' "sessionB")")"
assert_contains "17. concurrent: другая сессия свежая -> warn" "$OUT" '"additionalContext"'
assert_empty "17b. ... но НЕ блокирует" "$(deny_in "$OUT")"
# 18. Та же сессия повторно -> pass
OUT="$(run "$(write_payload_sid "$PROJ/data.json" '{"x":3}' "sessionB")")"
assert_empty "18. concurrent: та же сессия -> pass" "$OUT"
# 19. Не-shared формат -> pass
OUT="$(run "$(write_payload_sid "$PROJ/src/Comp.tsx" 'x' "sessionC")")"
assert_empty "19. concurrent: не-shared формат -> pass" "$OUT"

# --- version-awareness: legacy-проект (нет engine-version) ---
# 20. legacy: структурная ошибка -> WARN; UI-evidence -> всё равно hard BLOCK
rm -f "$PROJ/.harness/engine-version"
OUT="$(run "$(write_payload "$FL" "$BAD_STATE")")"
assert_contains "20a. legacy: структурная ошибка -> warn" "$OUT" '"additionalContext"'
assert_empty "20b. legacy: структурная -> НЕ блокирует" "$(deny_in "$OUT")"
OUT="$(run "$(write_payload "$FL" "$BAD_UI")")"
assert_contains "20c. legacy: UI-evidence всё равно -> deny (hard, инвариант B2)" "$OUT" '"permissionDecision":"deny"'
echo "6.0" > "$PROJ/.harness/engine-version"

# --- active-gate (H7): M/L-фича в active требует артефакт критики ---
ACTIVE_L='{"features":{"active_list":[{"id":"feat-50","state":"active","category":"api","size_estimate":"L","affected_files":["src/api/y.ts"]}]}}'
ACTIVE_S='{"features":{"active_list":[{"id":"feat-51","state":"active","category":"api","size_estimate":"S","affected_files":["src/api/z.ts"]}]}}'
# 21. L-фича в active без docs/test-strategy.md -> BLOCK
rm -rf "$PROJ/docs"
OUT="$(run "$(write_payload "$FL" "$ACTIVE_L")")"
assert_contains "21. L active без критики -> deny (H7)" "$OUT" '"permissionDecision":"deny"'
# 22. Та же L-фича + docs/test-strategy.md с её id -> pass
mkdir -p "$PROJ/docs"; echo "# Test Strategy для feat-50" > "$PROJ/docs/test-strategy.md"
OUT="$(run "$(write_payload "$FL" "$ACTIVE_L")")"
assert_empty "22. L active + test-strategy с id -> pass" "$OUT"
rm -rf "$PROJ/docs"
# 23. S-фича в active без критики -> pass (light path)
OUT="$(run "$(write_payload "$FL" "$ACTIVE_S")")"
assert_empty "23. S active без критики -> pass (light path)" "$OUT"

# --- data-model gate: data-фича в active требует docs/data-model-review.md ---
ACTIVE_DATA='{"features":{"active_list":[{"id":"feat-60","state":"active","category":"data","size_estimate":"S","affected_files":["src/db/schema/x.ts"]}]}}'
# 24. data-фича в active без ревью модели -> BLOCK
rm -rf "$PROJ/docs"
OUT="$(run "$(write_payload "$FL" "$ACTIVE_DATA")")"
assert_contains "24. data-фича active без ревью модели -> deny" "$OUT" '"permissionDecision":"deny"'
# 25. + docs/data-model-review.md с её id -> pass
mkdir -p "$PROJ/docs"; echo "# Data-model review для feat-60" > "$PROJ/docs/data-model-review.md"
OUT="$(run "$(write_payload "$FL" "$ACTIVE_DATA")")"
assert_empty "25. data-фича + review с id -> pass" "$OUT"
rm -rf "$PROJ/docs"

# --- vendor-research gate: integration-фича в active требует docs/research/*.md (дыра аудита) ---
ACTIVE_INTEG='{"features":{"active_list":[{"id":"feat-70","state":"active","category":"integration","size_estimate":"S","affected_files":["src/providers/insta.ts"]}]}}'
# 26. integration-фича в active без research поставщика -> BLOCK (vendor-lock)
rm -rf "$PROJ/docs"
OUT="$(run "$(write_payload "$FL" "$ACTIVE_INTEG")")"
assert_contains "26. integration-фича active без research -> deny (vendor-lock)" "$OUT" '"permissionDecision":"deny"'
# 27. + docs/research/insta.md с её id -> pass
mkdir -p "$PROJ/docs/research"; echo "# Research insta-провайдеров для feat-70" > "$PROJ/docs/research/insta.md"
OUT="$(run "$(write_payload "$FL" "$ACTIVE_INTEG")")"
assert_empty "27. integration-фича + research с id -> pass" "$OUT"
rm -rf "$PROJ/docs"

# --- регрессия: поле verification/evidence как СТРОКА или СПИСОК не должно ронять хук ---
# Реальные проекты пишут проверку человеческим текстом ("e2e: проверил руками") или
# списком шагов — не только словарём layer_1..N. Раньше хук делал .get() вслепую и падал
# (AttributeError), Python-краш → пустой stdout → gate молча пропускал ВСЁ (fail-open).
# Поймано при обкатке на боевом проекте Sensei (feat-15: verification-строкой).
VER_STR_UI='{"features":{"passing_list":[{"id":"feat-301","state":"passing","category":"ui","affected_files":["src/components/A.tsx"],"verification":"e2e: проверил руками","evidence":{}}]}}'
VER_LIST_UI='{"features":{"passing_list":[{"id":"feat-302","state":"passing","category":"ui","affected_files":["src/components/A.tsx"],"verification":["шаг 1","шаг 2"],"evidence":{}}]}}'
EVID_STR_UI='{"features":{"passing_list":[{"id":"feat-303","state":"passing","category":"ui","affected_files":["src/components/A.tsx"],"evidence":"ссылка на коммит abc123"}]}}'
rm -f "$FL"
# 28. verification-СТРОКА: хук не падает, UI-gate доходит -> deny (до фикса: краш -> пусто -> НЕ deny)
OUT="$(run "$(write_payload "$FL" "$VER_STR_UI")")"
assert_contains "28. verification-строка не роняет хук, UI-gate -> deny" "$OUT" '"permissionDecision":"deny"'
# 29. verification-СПИСОК: не падает, UI-gate -> deny
OUT="$(run "$(write_payload "$FL" "$VER_LIST_UI")")"
assert_contains "29. verification-список не роняет хук, UI-gate -> deny" "$OUT" '"permissionDecision":"deny"'
# 30. evidence-СТРОКА (ссылка на коммит, не словарь): не падает, UI без layer_4/5 -> deny
OUT="$(run "$(write_payload "$FL" "$EVID_STR_UI")")"
assert_contains "30. evidence-строка не роняет хук, UI-gate -> deny" "$OUT" '"permissionDecision":"deny"'

rm -rf "$PROJ" "$NOPROJ"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
