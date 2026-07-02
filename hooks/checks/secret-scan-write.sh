#!/bin/bash
# Vibe Dev v7 (Волна 3, P14) — блок хардкода ЖИВОГО ключа в исходники при Write/Edit/MultiEdit.
#
# Честно: наблюдаемая утечка недели была в ЧАТ/транскрипт (вне SDK) — это НЕ она. Здесь —
# ПРЕВЕНТИВНЫЙ рычаг «на будущее»: агент не должен зашивать боевой ключ в код. Не выдаём за
# закрытие наблюдаемой боли. Паттерн живого ключа — единый словарь (secret-lexicon.sh), не второй.
#
# Escape (lock-паттерн, как research-skip):
#   1) цель — .env-семейство → разрешено (легитимное место ключа);
#   2) маркер .harness/locks/secret-scan-off → разрешено (ставит listener по явной фразе
#      «ключ тестовый / забей», или пользователь руками).
#
# Аргументы: $1=cwd, $2=file_path, $3=tool. Payload в HOOK_PAYLOAD. Печатает BLOCK-строку или пусто.
set -u
CWD="${1:-$PWD}"; FILE="${2:-}"; TOOL="${3:-Write}"; TAB="$(printf '\t')"
. "$(dirname "${BASH_SOURCE[0]}")/../lib/secret-lexicon.sh" 2>/dev/null || true
SECRET_RE="${VIBE_SECRET_RE:-sk-ant-[A-Za-z0-9_-]{10,}}"

[ -n "$FILE" ] || exit 0

# Escape 1: запись в .env-семейство — правильное место ключа.
case "$FILE" in
  *.env|*.env.*|*/.env|*.envrc|*.env.local|*.env.example) exit 0 ;;
esac
# Escape 2: явный маркер-обход (ставит listener по фразе или пользователь руками). Одноразовый:
# снимаем при использовании, чтобы фраза «забей» не открывала хардкод навсегда.
if [ -f "$CWD/.harness/locks/secret-scan-off" ]; then
  rm -f "$CWD/.harness/locks/secret-scan-off" 2>/dev/null
  exit 0
fi

# Содержимое-НАМЕРЕНИЕ: Write→content, Edit→new_string, MultiEdit→edits[].new_string.
CONTENT="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '
  (.tool_input.content // empty),
  (.tool_input.new_string // empty),
  ((.tool_input.edits // []) | map(.new_string // empty) | join("\n"))
' 2>/dev/null)"
[ -n "$CONTENT" ] || exit 0

FOUND="$(printf '%s' "$CONTENT" | grep -oE "$SECRET_RE" 2>/dev/null | head -1)"
[ -z "$FOUND" ] && exit 0

printf 'BLOCK%sЖивой ключ/секрет (%.12s…) зашивается в исходник %s — он попадёт в git и утечёт. Вынеси в .env (переменная окружения; .env в .gitignore) и читай через $ИМЯ_ПЕРЕМЕННОЙ. Если это НЕ боевой ключ (тестовый/плейсхолдер) — скажи явно «ключ тестовый, забей», и хук снимет блок.\n' "$TAB" "$FOUND" "$FILE"
exit 0
