#!/bin/bash
# Vibe Dev v6 — user-rules (hookify, R6/H9/H18): правила пользователя «больше не делай X».
#
# Читает .harness/user-rules.json (массив правил) и применяет на PreToolUse. Правило:
#   { "id":"...", "tool":"Bash|Write|Edit|MultiEdit|*", "match":"<regex>",
#     "action":"block|warn", "message":"..." }
# Subject для regex: Bash -> .tool_input.command; Write/Edit/MultiEdit -> .tool_input.file_path.
# tool совпал (или "*") И regex match -> печатает "<BLOCK|WARN><TAB><message>" (формат проверок
# PreToolUse-диспетчера). Диспетчер агрегирует и эмитит.
#
# Цель: непрограммист замораживает свою коррекцию в исполняемое block/warn-правило без кода
# (скилл hookify пишет правило из «не делай X»). Честная граница: ловит ДЕЙСТВИЯ (команды/файлы),
# НЕ контент сообщений агента — контент display-only, хуком не enforce'ится (см. H5 отложен).
#
# Вход — HOOK_PAYLOAD (env, ставит диспетчер). exit 0 всегда (печатает вердикты или ничего).

set -u
CWD="${1:-$PWD}"
RULES="$CWD/.harness/user-rules.json"
[ -f "$RULES" ] || exit 0
TAB="$(printf '\t')"

tool="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_name // empty' 2>/dev/null)"
[ -z "$tool" ] && exit 0
cmd="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_input.command // empty' 2>/dev/null)"
file="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"

case "$tool" in
  Bash)                 subject="$cmd" ;;
  Write|Edit|MultiEdit) subject="$file" ;;
  *)                    subject="$cmd$file" ;;
esac
[ -z "$subject" ] && exit 0

# Перебор правил. Только печать (pipe-subshell безопасен — переменные не аккумулируем).
jq -c '.[]?' "$RULES" 2>/dev/null | while IFS= read -r rule; do
  [ -z "$rule" ] && continue
  rtool="$(printf '%s' "$rule" | jq -r '.tool // "*"' 2>/dev/null)"
  case "$rtool" in
    "$tool"|'*') ;;
    *) continue ;;
  esac
  rmatch="$(printf '%s' "$rule" | jq -r '.match // empty' 2>/dev/null)"
  [ -z "$rmatch" ] && continue
  printf '%s' "$subject" | grep -qE "$rmatch" 2>/dev/null || continue
  raction="$(printf '%s' "$rule" | jq -r '.action // "warn"' 2>/dev/null)"
  rmsg="$(printf '%s' "$rule" | jq -r '.message // "Нарушено правило пользователя (hookify)"' 2>/dev/null)"
  case "$raction" in
    block) printf 'BLOCK%s%s (правило пользователя hookify)\n' "$TAB" "$rmsg" ;;
    *)     printf 'WARN%s%s (правило пользователя hookify)\n'  "$TAB" "$rmsg" ;;
  esac
done
exit 0
