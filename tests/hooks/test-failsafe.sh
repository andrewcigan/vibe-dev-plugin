#!/bin/bash
# Vibe Dev v6.2 — тест fail-loud обвязки хуков (F1; урок бага 2026-06-06).
#
# Краш дочерней проверки раньше глотался (`2>/dev/null` + пустой stdout = «возражений нет»)
# и превращал гейт в молчаливый fail-open. Теперь hook_run_check обязан:
#   (1) добавить громкое предупреждение в канал (WARN-строка или ⚠️-абзац),
#   (2) записать crash-артефакт .harness/hook-crashes/<label>.log,
#   (3) НЕ исказить вывод здоровой проверки (прозрачность),
# а SessionStart-probe — сообщить о крашах прошлых сессий.
#
# Запуск: bash tests/hooks/test-failsafe.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; FAIL=0

unset VIBE_DEV_PROFILE CLAUDE_PLUGIN_ROOT HOOK_PAYLOAD 2>/dev/null || true

assert_contains() {
  if printf '%s' "$2" | grep -q -- "$3"; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s\n     ожидал: %s\n     получил: %s\n' "$1" "$3" "$2"; fi
}
assert_not_contains() {
  if printf '%s' "$2" | grep -q -- "$3"; then FAIL=$((FAIL+1)); printf '  FAIL %s (НЕ ожидал: %s)\n     получил: %s\n' "$1" "$3" "$2"
  else PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; fi
}
assert_file() { if [ -f "$2" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL %s (файл должен существовать: %s)\n' "$1" "$2"; fi; }
assert_absent() { if [ ! -f "$2" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL %s (файл должен отсутствовать: %s)\n' "$1" "$2"; fi; }

# --- Песочница ---
PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness"; echo "7.0" > "$PROJ/.harness/engine-version"
STUBS="$(mktemp -d)"   # фейковые проверки для юнита hook_run_check

cat > "$STUBS/ok.sh" <<'EOF'
#!/bin/bash
printf 'WARN\tобычное предупреждение проверки\n'
exit 0
EOF
cat > "$STUBS/crash.sh" <<'EOF'
#!/bin/bash
echo "Traceback (most recent call last): AttributeError: 'str' object has no attribute 'get'" >&2
exit 3
EOF
cat > "$STUBS/partial-then-crash.sh" <<'EOF'
#!/bin/bash
printf 'BLOCK\tчастичный вердикт до краша\n'
echo "boom" >&2
exit 1
EOF
cat > "$STUBS/silent-ok.sh" <<'EOF'
#!/bin/bash
exit 0
EOF

# Юниты hook_run_check — сорсим библиотеку в субшелле, чтобы exit emit-функций не убил тест.
runwrap() { # $1=label $2=format $3=script
  ( . "$PLUGIN_ROOT/hooks/lib/hook-io.sh"; hook_run_check "$PROJ" "$1" "$2" "$3" )
}

echo "Fail-loud обвязка хуков (F1) — сценарии:"

# 1. Здоровая проверка: вывод прозрачен, crash-артефакта нет
OUT="$(runwrap "ok-check" verdict "$STUBS/ok.sh")"
assert_contains     "1a. здоровая: вывод прозрачен" "$OUT" "обычное предупреждение проверки"
assert_not_contains "1b. здоровая: нет пометки УПАЛ" "$OUT" "УПАЛ"
assert_absent       "1c. здоровая: нет crash-артефакта" "$PROJ/.harness/hook-crashes/ok-check.log"

# 2. Тихая здоровая (пустой вывод, exit 0): по-прежнему пусто
OUT="$(runwrap "silent" verdict "$STUBS/silent-ok.sh")"
if [ -z "$(printf '%s' "$OUT" | tr -d '[:space:]')" ]; then PASS=$((PASS+1)); printf '  ok   2. тихая здоровая -> пусто\n'
else FAIL=$((FAIL+1)); printf '  FAIL 2. тихая здоровая должна давать пустой вывод\n     получил: %s\n' "$OUT"; fi

# 3. Краш, verdict-формат: WARN-строка + артефакт со stderr
OUT="$(runwrap "py-gate" verdict "$STUBS/crash.sh")"
assert_contains "3a. краш(verdict): WARN-строка с УПАЛ" "$OUT" "УПАЛ"
assert_contains "3b. краш(verdict): WARN-вердикт по формату" "$OUT" "WARN"
assert_contains "3c. краш(verdict): remediation (куда смотреть)" "$OUT" "hook-crashes/py-gate.log"
assert_file     "3d. краш(verdict): crash-артефакт записан" "$PROJ/.harness/hook-crashes/py-gate.log"
assert_contains "3e. краш(verdict): артефакт содержит stderr" "$(cat "$PROJ/.harness/hook-crashes/py-gate.log")" "AttributeError"

# 4. Краш, text-формат: ⚠️-абзац
OUT="$(runwrap "reminder" text "$STUBS/crash.sh")"
assert_contains "4a. краш(text): абзац ⚠️ сторож" "$OUT" "⚠️ сторож"
assert_contains "4b. краш(text): label в сообщении" "$OUT" "reminder"

# 5. Частичный вывод + краш: вердикты НЕ теряются, краш добавлен
OUT="$(runwrap "flaky" verdict "$STUBS/partial-then-crash.sh")"
assert_contains "5a. частичный вердикт сохранён" "$OUT" "частичный вердикт до краша"
assert_contains "5b. краш добавлен поверх" "$OUT" "УПАЛ"

rm -rf "$PROJ/.harness/hook-crashes"

# --- Интеграция: краш РЕАЛЬНОГО пути через диспетчер (CLAUDE_PLUGIN_ROOT -> стаб-дерево) ---
FAKEROOT="$(mktemp -d)"; mkdir -p "$FAKEROOT/hooks/checks"
cp "$STUBS/crash.sh" "$FAKEROOT/hooks/checks/state-transition.sh"
# Остальные проверки маршрута Write -> тихие заглушки (изолируем краш одного гейта).
for c in concurrent-write model-swap-guard user-rules; do
  cp "$STUBS/silent-ok.sh" "$FAKEROOT/hooks/checks/$c.sh"
done

echo strict > "$PROJ/.harness/profile"
PAYLOAD="$(jq -cn --arg cwd "$PROJ" --arg fp "$PROJ/feature_list.json" \
  '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Write",tool_input:{file_path:$fp,content:"{}"}}')"
OUT="$(printf '%s' "$PAYLOAD" | CLAUDE_PLUGIN_ROOT="$FAKEROOT" bash "$PLUGIN_ROOT/hooks/dispatch-pre-tool-use.sh")"
assert_contains "6a. PreToolUse: краш гейта -> НЕ молчание (additionalContext)" "$OUT" '"additionalContext"'
assert_contains "6b. PreToolUse: причина видна (УПАЛ)" "$OUT" "УПАЛ"
assert_file     "6c. PreToolUse: crash-артефакт state-transition" "$PROJ/.harness/hook-crashes/state-transition.log"
if printf '%s' "$OUT" | jq empty 2>/dev/null; then PASS=$((PASS+1)); printf '  ok   6d. вывод диспетчера — валидный JSON\n'
else FAIL=$((FAIL+1)); printf '  FAIL 6d. вывод диспетчера — НЕ валидный JSON\n     получил: %s\n' "$OUT"; fi

# 7. Краш handoff-reminder НЕ ставит маркер handoff-pending (краш != сигнал завершения)
FAKEROOT2="$(mktemp -d)"; mkdir -p "$FAKEROOT2/hooks/checks"
cp "$STUBS/crash.sh" "$FAKEROOT2/hooks/checks/handoff-reminder.sh"
cp "$STUBS/silent-ok.sh" "$FAKEROOT2/hooks/checks/stuck-signal-reminder.sh"
rm -f "$PROJ/.harness/handoff-pending"
UP_PAYLOAD="$(jq -cn --arg cwd "$PROJ" '{hook_event_name:"UserPromptSubmit",cwd:$cwd,prompt:"продолжаем работу"}')"
OUT="$(printf '%s' "$UP_PAYLOAD" | CLAUDE_PLUGIN_ROOT="$FAKEROOT2" bash "$PLUGIN_ROOT/hooks/dispatch-user-prompt.sh")"
assert_contains "7a. UserPrompt: краш доносится" "$OUT" "УПАЛ"
assert_absent   "7b. UserPrompt: маркер handoff-pending НЕ поставлен при краше" "$PROJ/.harness/handoff-pending"

# 8. SessionStart crash-probe: краши прошлых сессий видны на старте
SS_PAYLOAD="$(jq -cn --arg cwd "$PROJ" '{hook_event_name:"SessionStart",cwd:$cwd}')"
OUT="$(printf '%s' "$SS_PAYLOAD" | bash "$PLUGIN_ROOT/hooks/dispatch-session-start.sh")"
assert_contains "8a. SessionStart: probe видит краши (state-transition)" "$OUT" "state-transition"
assert_contains "8b. SessionStart: понятно что делать" "$OUT" "hook-crashes"

# 9. Нет крашей -> SessionStart тихий
rm -rf "$PROJ/.harness/hook-crashes"
OUT="$(printf '%s' "$SS_PAYLOAD" | bash "$PLUGIN_ROOT/hooks/dispatch-session-start.sh")"
if [ -z "$(printf '%s' "$OUT" | tr -d '[:space:]')" ]; then PASS=$((PASS+1)); printf '  ok   9. без крашей -> SessionStart тихий\n'
else FAIL=$((FAIL+1)); printf '  FAIL 9. без крашей SessionStart должен молчать\n     получил: %s\n' "$OUT"; fi

rm -rf "$PROJ" "$STUBS" "$FAKEROOT" "$FAKEROOT2"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
