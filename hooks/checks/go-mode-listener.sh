#!/bin/bash
# Vibe Dev v7 (Волна 5, P6) — go-mode listener (UserPromptSubmit).
#
# Явная фраза пользователя «не тормози / делай до конца / продолжай сам» → маркер
# .harness/locks/go-mode (его читает wave-continue.sh на Stop). Стоп-слово → маркер снять.
# Ставит ХУК (не агент): агенту запись в locks/ запрещена (locks-protect) — «изобразить
# go-режим» он не может. Cyrillic лоуэркейс через python (grep-классы ломки на multibyte).
#
# Аргументы: $1=cwd. Payload в HOOK_PAYLOAD (.prompt). exit 0 (текст не печатает — тихий маркер).
set -u
CWD="${1:-$PWD}"

PROMPT="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.prompt // .user_prompt // .message // empty' 2>/dev/null)"
[ -z "$PROMPT" ] && exit 0
PROMPT_LC="$(printf '%s' "$PROMPT" | python3 -c 'import sys; sys.stdout.write(sys.stdin.read().lower())' 2>/dev/null)"
[ -z "$PROMPT_LC" ] && PROMPT_LC="$PROMPT"

STOP_RE='стоп|останов|подожд|погоди|не продолжа|отмен[аиь]|хватит|другая задач|не туда'
GO_RE='не тормоз|не останавлив|продолжай|делай все|делай всё|делай дальше|делай до конца|поехали|го дальше|не жди|не спрашивай|сам реши|доведи до конца|все волны|всё сам|до конца сам'

mkdir -p "$CWD/.harness/locks" 2>/dev/null
if printf '%s' "$PROMPT_LC" | grep -qE "$STOP_RE" 2>/dev/null; then
  rm -f "$CWD/.harness/locks/go-mode" 2>/dev/null
elif printf '%s' "$PROMPT_LC" | grep -qE "$GO_RE" 2>/dev/null; then
  printf 'when: %s\nquote: %s\n' "$(date '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?')" \
    "$(printf '%s' "$PROMPT" | head -c 160 | tr '\n' ' ')" > "$CWD/.harness/locks/go-mode" 2>/dev/null
fi
exit 0
