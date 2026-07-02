#!/bin/bash
# Vibe Dev v6 — регрессионный тест анти-залипания №2 (повтор Bash) + secret-mask на PostToolUse.
#
# ⚠️ Воспроизводит ЖИВУЮ модель событий (проверка 2026-06-10, движок 2.1.170):
#   - падение С ВЫВОДОМ (stdout/stderr) -> PostToolUse НЕ приходит вообще;
#   - ТИХОЕ падение (exit!=0 без вывода) -> событие есть + tool_response.returnCodeInterpretation;
#   - чистый успех -> событие есть, returnCodeInterpretation отсутствует;
#   - полей exit_code/success в tool_response НЕТ (есть stdout/stderr/interrupted/isImage/
#     noOutputExpected[/returnCodeInterpretation]).
# Поэтому: инкремент счётчика — PreToolUse-диспетчер (каждый запуск), сброс — PostToolUse
# (чистый успех: нет interrupted и нет returnCodeInterpretation) и Edit/Write/MultiEdit.
# Тест гоняет СВЯЗКУ обоих диспетчеров. Прокси №2 разбора tunnel-vision
# (gate: docs/anti-stuck-gate-2026-06-05.md). Инжект РОВНО на пороге (3-й запуск без успеха).
#
# Запуск: bash tests/hooks/test-post-tool-use.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISPATCH_POST="$PLUGIN_ROOT/hooks/dispatch-post-tool-use.sh"
DISPATCH_PRE="$PLUGIN_ROOT/hooks/dispatch-pre-tool-use.sh"
PASS=0; FAIL=0

unset VIBE_DEV_PROFILE CLAUDE_PLUGIN_ROOT HOOK_PAYLOAD VIBE_BASH_REPEAT_THRESHOLD 2>/dev/null || true

run_pre()  { printf '%s' "$1" | bash "$DISPATCH_PRE"; }
run_post() { printf '%s' "$1" | bash "$DISPATCH_POST"; }
assert_contains() {
  if printf '%s' "$2" | grep -q -- "$3"; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s\n     ожидал найти: %s\n     получил: %s\n' "$1" "$3" "$2"; fi
}
assert_empty() {
  if [ -z "$(printf '%s' "$2" | tr -d '[:space:]')" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s (ожидал пусто)\n     получил: %s\n' "$1" "$2"; fi
}

PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness"; echo "7.0" > "$PROJ/.harness/engine-version"
reset_state() { rm -f "$PROJ/.harness/bash-repeat-state" 2>/dev/null; }

pre_b() {  # pre_b <command> [cwd] — PreToolUse Bash payload (РЕАЛЬНАЯ форма: без tool_response)
  jq -cn --arg c "$1" --arg cwd "${2:-$PROJ}" \
    '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Bash",tool_input:{command:$c}}'
}
post_b() {  # post_b <command> <stdout> [interrupted] [cwd] — PostToolUse Bash payload (чистый успех; реальная форма 2.1.170)
  jq -cn --arg c "$1" --arg out "${2:-}" --argjson intr "${3:-false}" --arg cwd "${4:-$PROJ}" \
    '{hook_event_name:"PostToolUse",cwd:$cwd,tool_name:"Bash",tool_input:{command:$c},tool_response:{stdout:$out,stderr:"",interrupted:$intr,isImage:false,noOutputExpected:false}}'
}
post_b_silentfail() {  # post_b_silentfail <command> [cwd] — тихое падение: есть returnCodeInterpretation (реальная форма 2.1.170)
  jq -cn --arg c "$1" --arg cwd "${2:-$PROJ}" \
    '{hook_event_name:"PostToolUse",cwd:$cwd,tool_name:"Bash",tool_input:{command:$c},tool_response:{stdout:"",stderr:"",interrupted:false,isImage:false,returnCodeInterpretation:"Condition is false",noOutputExpected:false}}'
}
post_e() {  # post_e [cwd] — PostToolUse Edit payload (структурное изменение)
  jq -cn --arg cwd "${1:-$PROJ}" \
    '{hook_event_name:"PostToolUse",cwd:$cwd,tool_name:"Edit",tool_input:{file_path:"x.ts"},tool_response:{}}'
}

echo "Анти-залипание №2 (повтор Bash: PreToolUse-инкремент + PostToolUse-сброс) — сценарии:"

# 1. 3 подряд запуска одного класса БЕЗ успеха (post-события нет) -> warn ровно на 3-м pre
reset_state
assert_empty    "1a. 1-й запуск -> pass"  "$(run_pre "$(pre_b "curl http://x/api fail")")"
assert_empty    "1b. 2-й запуск -> pass"  "$(run_pre "$(pre_b "curl http://x/api fail")")"
OUT="$(run_pre "$(pre_b "curl http://x/api fail")")"
assert_contains "1c. 3-й запуск без успеха -> warn про субагент" "$OUT" 'субагент'
assert_contains "1d. ... в additionalContext (PreToolUse warn)" "$OUT" '"additionalContext"'
assert_empty    "1e. 4-й запуск -> pass (one-shot, не спамит)" "$(run_pre "$(pre_b "curl http://x/api fail")")"

# 2. Успех в середине (post-событие) -> сброс счётчика
reset_state
run_pre "$(pre_b "pnpm test x")" >/dev/null
run_pre "$(pre_b "pnpm test x")" >/dev/null
assert_empty "2a. post (успех) -> pass + reset" "$(run_post "$(post_b "pnpm test x" "ok")")"
assert_empty "2b. 3-й запуск ПОСЛЕ успеха -> count=1, pass" "$(run_pre "$(pre_b "pnpm test x")")"

# 3. Разные классы команд -> не warn'ит
reset_state
run_pre "$(pre_b "ls /a")" >/dev/null
run_pre "$(pre_b "cat /b")" >/dev/null
assert_empty "3. разные команды -> pass" "$(run_pre "$(pre_b "grep x /c")")"

# 4. Один класс, разные числа (нормализация цифр) -> warn на 3-м
reset_state
run_pre "$(pre_b "curl http://api?offset=500")" >/dev/null
run_pre "$(pre_b "curl http://api?offset=1000")" >/dev/null
OUT="$(run_pre "$(pre_b "curl http://api?offset=1500")")"
assert_contains "4. param-tweak одной команды -> warn (нормализация)" "$OUT" 'субагент'

# 5. Edit между запусками -> сброс (прогресс, не слепой повтор)
reset_state
run_pre "$(pre_b "pnpm build")" >/dev/null
run_pre "$(pre_b "pnpm build")" >/dev/null
run_post "$(post_e)" >/dev/null   # структурное изменение -> reset
assert_empty "5. Edit сбросил счётчик -> 3-й запуск count=1, pass" "$(run_pre "$(pre_b "pnpm build")")"

# 6. interrupted=true на post -> успехом НЕ считается, счётчик не сброшен
reset_state
run_pre "$(pre_b "pnpm dev serve")" >/dev/null
run_pre "$(pre_b "pnpm dev serve")" >/dev/null
run_post "$(post_b "pnpm dev serve" "" true)" >/dev/null   # прерванная (^C)
OUT="$(run_pre "$(pre_b "pnpm dev serve")")"
assert_contains "6. interrupted не сбросил -> 3-й запуск warn" "$OUT" 'субагент'

# 6b. Тихое падение (returnCodeInterpretation) -> успехом НЕ считается, счётчик не сброшен
reset_state
run_pre "$(pre_b "test -f /tmp/flag")" >/dev/null
run_post "$(post_b_silentfail "test -f /tmp/flag")" >/dev/null
run_pre "$(pre_b "test -f /tmp/flag")" >/dev/null
run_post "$(post_b_silentfail "test -f /tmp/flag")" >/dev/null
OUT="$(run_pre "$(pre_b "test -f /tmp/flag")")"
assert_contains "6b. тихое падение не сбросило -> 3-й запуск warn" "$OUT" 'субагент'

# 7. minimal-профиль -> выключен (и pre-ветка, и post)
reset_state
echo minimal > "$PROJ/.harness/profile"
run_pre "$(pre_b "x fail")" >/dev/null; run_pre "$(pre_b "x fail")" >/dev/null
assert_empty "7. профиль minimal -> pass (выключен)" "$(run_pre "$(pre_b "x fail")")"
rm -f "$PROJ/.harness/profile"

# 8. Не vibe-проект -> pass (guard)
NOPROJ="$(mktemp -d)"
assert_empty "8. не-vibe-проект -> pass" "$(run_pre "$(pre_b "x fail" "$NOPROJ")")"
rm -rf "$NOPROJ"

# 9. Warn — валидный JSON
reset_state
run_pre "$(pre_b "z fail")" >/dev/null; run_pre "$(pre_b "z fail")" >/dev/null
OUT="$(run_pre "$(pre_b "z fail")")"
if printf '%s' "$OUT" | jq empty 2>/dev/null; then PASS=$((PASS+1)); printf '  ok   9. warn — валидный JSON\n'
else FAIL=$((FAIL+1)); printf '  FAIL 9. warn — НЕ валидный JSON\n     получил: %s\n' "$OUT"; fi

# 10. Состояние сброшено успехом — state-файл удалён
reset_state
run_pre "$(pre_b "echo ok")" >/dev/null
run_post "$(post_b "echo ok" "ok")" >/dev/null
if [ ! -f "$PROJ/.harness/bash-repeat-state" ]; then PASS=$((PASS+1)); printf '  ok   10. успех -> state-файл сброшен\n'
else FAIL=$((FAIL+1)); printf '  FAIL 10. state-файл не сброшен после успеха\n'; fi

echo ""
echo "secret-mask на PostToolUse (живой канал additionalContext + updatedToolOutput) — сценарии:"

# 11. Токен в stdout успешной команды -> оба поля в одном объекте
OUT="$(run_post "$(post_b "gh auth status" "token: ghp_FAKETESTFAKETESTFAKETESTFAKETEST00")")"
assert_contains "11a. маска в updatedToolOutput" "$OUT" 'MASKED-by-vibe-dev'
assert_contains "11b. предупреждение в additionalContext" "$OUT" 'ротаци'
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput | has("updatedToolOutput") and has("additionalContext")' >/dev/null 2>&1; then
  PASS=$((PASS+1)); printf '  ok   11c. оба канала в одном hookSpecificOutput\n'
else FAIL=$((FAIL+1)); printf '  FAIL 11c. нет обоих каналов\n     получил: %s\n' "$OUT"; fi

# 12. Чистый stdout -> пусто
assert_empty "12. вывод без секретов -> pass" "$(run_post "$(post_b "ls" "file1 file2")")"

rm -rf "$PROJ"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
