#!/bin/bash
# Vibe Dev v6.2/v8 — защита конфигурации enforcement (F9; R3 из ECC: «агент ослабляет
# собственные гейты») + must-fix L5-F1 (закрытие подтверждённого fail-open границ правок).
#
# Носитель — верифицированный PreToolUse (а не сырое событие ConfigChange — его контракт
# не проверен вживую; отмечено в плане как отложенное).
#
# Блокируем попытки агента:
#   - переписать .harness/profile НЕ-pending значением (ослабить strict->minimal; pending-*
#     разрешён — это bootstrap, слабейшее состояние, его легитимно пишут скиллы);
#   - писать .harness/hooks-heartbeat (фальсификация «хуки живы»);
#   - создавать .harness/hooks-disabled (отключение backstop — решение ПОЛЬЗОВАТЕЛЯ руками);
#   - ставить .harness/hook-mode в learn (L5-F1: learn понижает структурные гейты до warn —
#     state-transition.sh; это ослабление, легитимно лишь руками пользователя или /upgrade-project,
#     который его СНИМАЕТ. Раньше hook-mode НЕ был под защитой → агент под давлением одной командой
#     разоружал гейт, а dispatcher сам рекламировал побег);
#   - Write/Edit на эти файлы любым содержимым.
#
# L5-F1 второй fail-open: раньше Bash-ветка ловила только redirect (>/>>/tee) — cp/mv/install/
# ln/dd/touch/sed -i обходили защиту ВСЕХ файлов. Теперь запись детектится функцией writes_to
# по расширенному набору глаголов. Threat model — пассивные ошибки / побег под давлением, не
# изощрённый обход (python-open/eval/here-doc не ловим — как locks-protect; честная граница).
#
# Аргументы: $1=cwd. Payload в HOOK_PAYLOAD. Печатает "BLOCK\tmsg", пусто = ОК. exit 0.

set -u
CWD="${1:-$PWD}"
TAB="$(printf '\t')"

TOOL="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_name // empty' 2>/dev/null)"

MSG_PROFILE="Профиль строгости меняют только bootstrap/upgrade-скрипты (pending-*) и живые хуки (pending→боевой). Ослабить профиль напрямую нельзя — это ослабление собственных гейтов. Нужен другой режим? Скажи пользователю, пусть решит: /upgrade-project или осознанный minimal через правку руками."
MSG_HEARTBEAT="Heartbeat пишут ТОЛЬКО хуки — это доказательство их работы; запись агентом = фальсификация активации."
MSG_DISABLED="Отключение enforcement (.harness/hooks-disabled) — решение пользователя, выполняемое его руками вне сессии. Объясни ему команду, но не выполняй сам: иначе сторож отключал бы сам себя."
MSG_HOOKMODE="learn-mode (.harness/hook-mode=learn) понижает структурные гейты до warn — это ослабление enforcement. Ставит его ТОЛЬКО пользователь руками или /upgrade-project (который его, наоборот, СНИМАЕТ). Агент не включает learn: иначе сторож разоружал бы сам себя одной командой. Блок ошибочен и проект действительно legacy? Переведи его на актуальный движок через /upgrade-project."

# writes_to <command> <relpath-regex> — команда пытается ЗАПИСАТЬ/создать <relpath>?
# Ловит redirect (>/>>/tee) и пишущие глаголы (cp/mv/install/ln/dd/touch) с файлом в том же
# сегменте команды (до |;&), плюс sed -i (in-place правка). Путь передаётся как regex с
# экранированной точкой (\.harness/...). НЕ ловит чтение (cat/less/grep/sed без -i) и экзотику.
writes_to() {
  local cmd="$1" f="$2"
  printf '%s' "$cmd" | grep -qE "(>>?|tee|cp|mv|install|ln|dd|touch)[[:space:]]?[^|;&]*${f}" 2>/dev/null && return 0
  printf '%s' "$cmd" | grep -qE "sed[^|;&]*-i[^|;&]*${f}" 2>/dev/null && return 0
  return 1
}

case "$TOOL" in
  Write|Edit|MultiEdit)
    FILE="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
    case "$FILE" in
      *.harness/profile)         printf 'BLOCK%s%s\n' "$TAB" "$MSG_PROFILE" ;;
      *.harness/hooks-heartbeat) printf 'BLOCK%s%s\n' "$TAB" "$MSG_HEARTBEAT" ;;
      *.harness/hooks-disabled)  printf 'BLOCK%s%s\n' "$TAB" "$MSG_DISABLED" ;;
      *.harness/hook-mode)       printf 'BLOCK%s%s\n' "$TAB" "$MSG_HOOKMODE" ;;
    esac
    ;;
  Bash)
    CMD="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    [ -z "$CMD" ] && exit 0
    # profile: запись НЕ-pending значением = ослабление (pending-* легитимен — bootstrap).
    if writes_to "$CMD" '\.harness/profile'; then
      if ! printf '%s' "$CMD" | grep -q 'pending-' 2>/dev/null; then
        printf 'BLOCK%s%s\n' "$TAB" "$MSG_PROFILE"
      fi
    fi
    # heartbeat: любая запись агентом = фальсификация активации.
    if writes_to "$CMD" '\.harness/hooks-heartbeat'; then
      printf 'BLOCK%s%s\n' "$TAB" "$MSG_HEARTBEAT"
    fi
    # hooks-disabled: любое создание агентом (само существование файла отключает backstop).
    if writes_to "$CMD" '\.harness/hooks-disabled'; then
      printf 'BLOCK%s%s\n' "$TAB" "$MSG_DISABLED"
    fi
    # hook-mode: агент не пишет hook-mode вовсе (файл управляет понижением строгости в learn).
    # ЛЮБАЯ запись/создание агентом → block независимо от значения — иначе `cp файл-с-learn
    # .harness/hook-mode` обходил бы проверку (значение в исходнике, не в тексте команды).
    # Снятие (rm) — не writes_to, проходит: движение к строгости безопасно (как locks-protect).
    if writes_to "$CMD" '\.harness/hook-mode'; then
      printf 'BLOCK%s%s\n' "$TAB" "$MSG_HOOKMODE"
    fi
    ;;
esac
exit 0
