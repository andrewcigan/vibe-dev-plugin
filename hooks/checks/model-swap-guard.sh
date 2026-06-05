#!/bin/bash
# Vibe Dev v6 — model-swap-guard (дыра аудита 2026-06-05: смена модели/зависимости без smoke).
#
# Реальный инцидент в проекте RAG-ассистента: writer-модель сменили gemini-2.5→3.5 одной env-строкой («новее = drop-in»)
# без прогона → 3 дня обрывы и утечка reasoning живым клиентам. Урок:
# смена модели / её версии / настроек вызова / промпта целиком = ИЗМЕНЕНИЕ КОНТРАКТА (влияет
# на каждый вывод), а не «правка конфига». Требует проверки контракта + регрессионного smoke
# + gate на исходящие ДО прода. Blast radius = охват влияния, не размер диффа.
#
# Механизм: PreToolUse на Write/Edit/MultiEdit. Если ВНОСИМОЕ содержимое содержит идентификатор
# модели (gpt-/claude-/gemini-/…) или ключ настройки, влияющей на каждый вывод
# (max_tokens/temperature/reasoning/thinking_budget/response_format/system_prompt) → WARN.
# НЕ block — правка легитимна; цель — заставить прогнать smoke. standard/strict.
#
# Вход — HOOK_PAYLOAD (env, ставит диспетчер). Печатает "WARN<TAB>msg" или ничего. exit 0.

set -u
CWD="${1:-$PWD}"
TAB="$(printf '\t')"

tool="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_name // empty' 2>/dev/null)"
file="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"

# Вносимое содержимое (намерение, не диск): Write→content, Edit→new_string, MultiEdit→все new_string.
case "$tool" in
  Write)     subj="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_input.content // empty' 2>/dev/null)" ;;
  Edit)      subj="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_input.new_string // empty' 2>/dev/null)" ;;
  MultiEdit) subj="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '[.tool_input.edits[]?.new_string] | join("\n") // empty' 2>/dev/null)" ;;
  *)         exit 0 ;;
esac
[ -z "$subj" ] && exit 0

# Идентификаторы моделей (провайдеры LLM/embeddings/speech).
MODEL_PAT='gpt-[0-9]|gpt-image|claude-[a-z0-9]|gemini-[0-9]|gemini-(pro|flash)|o[0-9]-(mini|preview|pro)|deepseek|llama-?[0-9]|mistral|mixtral|gemma|grok-|qwen|text-embedding-|whisper-|tts-1'
# Ключи настроек, влияющих на КАЖДЫЙ вывод.
SETTING_PAT='(max_tokens|temperature|reasoning_effort|thinking_budget|response_format|top_p|system_prompt|systemPrompt|MODEL_NAME|_MODEL|model_id|model_name)[[:space:]]*[=:]'

if printf '%s' "$subj" | grep -qiE "$MODEL_PAT" || printf '%s' "$subj" | grep -qE "$SETTING_PAT"; then
  printf 'WARN%sПохоже на смену модели или настроек, влияющих на КАЖДЫЙ вывод (файл: %s). Это изменение контракта, не правка конфига — прогони регрессионный smoke на реальных сценариях и проверь обрыв / finish_reason=length / утечку служебного текста ДО выкатки в прод. «Новее» ≠ «совместимее».\n' "$TAB" "${file:-?}"
fi
exit 0
