#!/bin/bash
# Vibe Dev v6.2 — защита конфигурации enforcement (F9; R3 из ECC: «агент ослабляет
# собственные гейты»). При ужесточении гейтов (v6.2) это очевидный следующий «побег».
#
# Носитель — верифицированный PreToolUse (а не сырое событие ConfigChange — его контракт
# не проверен вживую; отмечено в плане как отложенное).
#
# Блокируем попытки агента:
#   - переписать .harness/profile НЕ-pending значением (ослабить strict->minimal; pending-*
#     разрешён — это bootstrap, слабейшее состояние, его легитимно пишут скиллы);
#   - писать .harness/hooks-heartbeat (фальсификация «хуки живы»);
#   - создавать .harness/hooks-disabled (отключение backstop — решение ПОЛЬЗОВАТЕЛЯ руками);
#   - Write/Edit на эти файлы любым содержимым.
#
# Аргументы: $1=cwd. Payload в HOOK_PAYLOAD. Печатает "BLOCK\tmsg", пусто = ОК. exit 0.

set -u
CWD="${1:-$PWD}"
TAB="$(printf '\t')"

TOOL="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_name // empty' 2>/dev/null)"

MSG_PROFILE="Профиль строгости меняют только bootstrap/upgrade-скрипты (pending-*) и живые хуки (pending→боевой). Ослабить профиль напрямую нельзя — это ослабление собственных гейтов. Нужен другой режим? Скажи пользователю, пусть решит: /upgrade-project или осознанный minimal через правку руками."
MSG_HEARTBEAT="Heartbeat пишут ТОЛЬКО хуки — это доказательство их работы; запись агентом = фальсификация активации."
MSG_DISABLED="Отключение enforcement (.harness/hooks-disabled) — решение пользователя, выполняемое его руками вне сессии. Объясни ему команду, но не выполняй сам: иначе сторож отключал бы сам себя."

case "$TOOL" in
  Write|Edit|MultiEdit)
    FILE="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
    case "$FILE" in
      *.harness/profile)         printf 'BLOCK%s%s\n' "$TAB" "$MSG_PROFILE" ;;
      *.harness/hooks-heartbeat) printf 'BLOCK%s%s\n' "$TAB" "$MSG_HEARTBEAT" ;;
      *.harness/hooks-disabled)  printf 'BLOCK%s%s\n' "$TAB" "$MSG_DISABLED" ;;
    esac
    ;;
  Bash)
    CMD="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    [ -z "$CMD" ] && exit 0
    if printf '%s' "$CMD" | grep -qE '(>>?|tee)[^|;&]*\.harness/profile' 2>/dev/null; then
      # pending-* — легитимный bootstrap (слабейшее состояние); остальное — ослабление.
      if ! printf '%s' "$CMD" | grep -q 'pending-' 2>/dev/null; then
        printf 'BLOCK%s%s\n' "$TAB" "$MSG_PROFILE"
      fi
    fi
    if printf '%s' "$CMD" | grep -qE '(>>?|tee|touch[[:space:]])[^|;&]*\.harness/hooks-heartbeat' 2>/dev/null; then
      printf 'BLOCK%s%s\n' "$TAB" "$MSG_HEARTBEAT"
    fi
    if printf '%s' "$CMD" | grep -qE '(>>?|tee|touch[[:space:]])[^|;&]*\.harness/hooks-disabled' 2>/dev/null; then
      printf 'BLOCK%s%s\n' "$TAB" "$MSG_DISABLED"
    fi
    ;;
esac
exit 0
