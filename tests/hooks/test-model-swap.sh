#!/bin/bash
# Vibe Dev v6 — регрессионный тест model-swap-guard (дыра аудита: смена модели без smoke).
#
# Реальный кейс (3 дня брака): смена writer-модели одной env-строкой («новее = drop-in»)
# без прогона → thinking-модель съедала max_tokens → обрывы клиентам. Урок: смена модели/
# настроек, влияющих на КАЖДЫЙ вывод = изменение контракта, требует smoke ДО прода.
#
# Механизм: PreToolUse на Write/Edit/MultiEdit — если правка содержит идентификатор модели
# (gpt-/claude-/gemini-/…) или ключ настройки (max_tokens/temperature/reasoning…) → WARN
# (не block — правка легитимна, но требует smoke). Воспроизводит реальный триггер (намерение
# из tool_input). Запуск: bash tests/hooks/test-model-swap.sh
set -u

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISPATCH="$PLUGIN_ROOT/hooks/dispatch-pre-tool-use.sh"
PASS=0; FAIL=0
unset VIBE_DEV_PROFILE CLAUDE_PLUGIN_ROOT HOOK_PAYLOAD 2>/dev/null || true

run() { printf '%s' "$1" | bash "$DISPATCH"; }
assert_contains() {
  if printf '%s' "$2" | grep -q -- "$3"; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s\n     ожидал: %s\n     получил: %s\n' "$1" "$3" "$2"; fi
}
assert_empty() {
  if [ -z "$(printf '%s' "$2" | tr -d '[:space:]')" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s (ожидал пусто)\n     получил: %s\n' "$1" "$2"; fi
}

PROJ="$(mktemp -d)"; mkdir -p "$PROJ/.harness"; echo "6.0" > "$PROJ/.harness/engine-version"

edit_pl() { jq -cn --arg f "$1" --arg ns "$2" --arg cwd "${3:-$PROJ}" '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Edit",tool_input:{file_path:$f,old_string:"old",new_string:$ns}}'; }
write_pl() { jq -cn --arg f "$1" --arg c "$2" --arg cwd "${3:-$PROJ}" '{hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Write",tool_input:{file_path:$f,content:$c}}'; }

echo "model-swap-guard — сценарии:"

# 1. Edit вводит claude-модель -> warn
OUT="$(run "$(edit_pl "src/llm.ts" "const MODEL = 'claude-sonnet-4-5'")")"
assert_contains "1a. смена на claude-* -> warn" "$OUT" 'additionalContext'
assert_contains "1b. ... про контракт/smoke" "$OUT" 'контракт'

# 2. Edit меняет max_tokens -> warn (настройка, влияющая на вывод)
OUT="$(run "$(edit_pl "config/bot.ts" "max_tokens: 400")")"
assert_contains "2. смена max_tokens -> warn" "$OUT" 'additionalContext'

# 3. Edit .env с моделью gemini -> warn
OUT="$(run "$(edit_pl ".env" "WRITER_MODEL=gemini-3.5-flash")")"
assert_contains "3. .env смена gemini-модели -> warn" "$OUT" 'additionalContext'

# 4. Обычная правка без модели/настроек -> pass
assert_empty "4. обычная правка -> pass" "$(run "$(edit_pl "src/util.ts" "const sum = a + b")")"

# 5. Write обычного файла -> pass
assert_empty "5. write обычного кода -> pass" "$(run "$(write_pl "src/app.ts" "export const greet = () => 'hi'")")"

# 6. minimal-профиль -> pass
echo minimal > "$PROJ/.harness/profile"
assert_empty "6. профиль minimal -> pass" "$(run "$(edit_pl "src/llm.ts" "MODEL='gpt-4o'")")"
rm -f "$PROJ/.harness/profile"

# 7. Не-vibe-проект -> pass (guard)
NOPROJ="$(mktemp -d)"
assert_empty "7. не-vibe-проект -> pass" "$(run "$(edit_pl "src/llm.ts" "MODEL='claude-opus-4-8'" "$NOPROJ")")"
rm -rf "$NOPROJ"

# 8. Вывод warn -> валидный JSON
OUT="$(run "$(edit_pl "src/llm.ts" "model: 'gpt-4o-mini'")")"
if printf '%s' "$OUT" | jq empty 2>/dev/null; then PASS=$((PASS+1)); printf '  ok   8. warn -> валидный JSON\n'
else FAIL=$((FAIL+1)); printf '  FAIL 8. warn -> НЕ валидный JSON\n     получил: %s\n' "$OUT"; fi

rm -rf "$PROJ"
echo ""
echo "Итог: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
