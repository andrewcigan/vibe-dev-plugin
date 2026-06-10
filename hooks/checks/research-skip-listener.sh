#!/bin/bash
# Vibe Dev v6.2 — слушатель явной фразы «пропусти рисёрч» (F6; lock-паттерн).
#
# Распоряжение пользователя (2026-06-10): research перед архитектурой ОБЯЗАТЕЛЕН,
# «только если пользователь явно не скажет пропустить». Явность фразы фиксирует ХУК
# (не агент): детект фразы пропуска в промпте -> .harness/locks/research-skipped
# (дата + цитата). Агенту писать в locks/ нельзя (locks-protect.sh).
#
# Аргументы: $1=cwd. Payload в HOOK_PAYLOAD (.prompt). Печатает текст-inject или пусто. exit 0.

set -u
CWD="${1:-$PWD}"

PROMPT="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.prompt // .user_prompt // .message // empty' 2>/dev/null)"
[ -z "$PROMPT" ] && exit 0

# Кириллические [классы] в grep ломки на multibyte (байтовый режим) — нормализуем регистр
# python-ом (UTF-8-корректно) и матчим явными альтернативами в нижнем регистре.
PROMPT_LC="$(printf '%s' "$PROMPT" | python3 -c 'import sys; sys.stdout.write(sys.stdin.read().lower())' 2>/dev/null)"
[ -z "$PROMPT_LC" ] && PROMPT_LC="$PROMPT"

SKIP_RE='(пропусти(м|ть)?|без|скип|skip|не (надо|нужен|нужно|делай))[^.!?]{0,30}(research|рисёрч|рисерч|ресёрч|ресерч)|(research|рисёрч|рисерч|ресёрч|ресерч)[^.!?]{0,20}(не нужен|не надо|пропус)'

if printf '%s' "$PROMPT_LC" | grep -qE "$SKIP_RE" 2>/dev/null; then
  mkdir -p "$CWD/.harness/locks" 2>/dev/null
  {
    printf 'when: %s\n' "$(date '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?')"
    printf 'quote: %s\n' "$(printf '%s' "$PROMPT" | head -c 300 | tr '\n' ' ')"
  } > "$CWD/.harness/locks/research-skipped" 2>/dev/null
  printf 'Зафиксировано хуком: рисёрч перед архитектурой ПРОПУЩЕН по явной фразе пользователя (маркер .harness/locks/research-skipped с цитатой). Маркер одноразовый: /architecture потребит его (rm) при использовании.'
fi
exit 0
