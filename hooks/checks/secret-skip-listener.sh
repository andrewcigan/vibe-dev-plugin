#!/bin/bash
# Vibe Dev v7 (Волна 3, P14 escape) — слушатель явной фразы «ключ тестовый / забей на секрет».
#
# Фиксирует ХУК (не агент): фраза → .harness/locks/secret-scan-off (одноразовый маркер,
# secret-scan-write.sh снимает его при использовании). Агенту писать в locks/ нельзя (locks-protect),
# поэтому «изобразить согласие» он не может — только пользователь явной фразой.
#
# Аргументы: $1=cwd. Payload в HOOK_PAYLOAD (.prompt). Печатает текст-inject или пусто. exit 0.
set -u
CWD="${1:-$PWD}"

PROMPT="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.prompt // .user_prompt // .message // empty' 2>/dev/null)"
[ -z "$PROMPT" ] && exit 0

# Кириллица в grep-классах ломка на multibyte — нормализуем регистр python-ом.
PROMPT_LC="$(printf '%s' "$PROMPT" | python3 -c 'import sys; sys.stdout.write(sys.stdin.read().lower())' 2>/dev/null)"
[ -z "$PROMPT_LC" ] && PROMPT_LC="$PROMPT"

SKIP_RE='(ключ|секрет|токен|key|token)[^.!?]{0,30}(тестов|не боев|не живой|плейсхолдер|placeholder|фейк|fake|забей|игнор)|(забей|игнор)[^.!?]{0,25}(ключ|секрет|секрет-скан|secret)'

if printf '%s' "$PROMPT_LC" | grep -qE "$SKIP_RE" 2>/dev/null; then
  mkdir -p "$CWD/.harness/locks" 2>/dev/null
  {
    printf 'when: %s\n' "$(date '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?')"
    printf 'quote: %s\n' "$(printf '%s' "$PROMPT" | head -c 200 | tr '\n' ' ')"
  } > "$CWD/.harness/locks/secret-scan-off" 2>/dev/null
  printf 'Зафиксировано хуком: блок хардкода ключа СНЯТ на одну запись по явной фразе (маркер .harness/locks/secret-scan-off, одноразовый). Если ключ всё же боевой — вынеси в .env.'
fi
exit 0
