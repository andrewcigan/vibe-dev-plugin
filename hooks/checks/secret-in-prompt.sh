#!/bin/bash
# Vibe Dev v6.2 — секрет во входящем промпте (F8; П8 аудита: владелец вставил живой
# OpenRouter-ключ в чат — агент молча сохранил и НЕ предупредил о компрометации).
#
# Жёсткие паттерны (precision: голый "sk-" не ловим — шумит). Inject, НЕ block: ключ уже
# в контексте, блокировать поздно — задача предупредить о ротации и правильном хранении.
#
# Аргументы: $1=cwd. Payload в HOOK_PAYLOAD (.prompt). Печатает текст-inject или пусто. exit 0.

set -u
CWD="${1:-$PWD}"
# Единый словарь живого ключа (один источник для обоих secret-хуков).
. "$(dirname "${BASH_SOURCE[0]}")/../lib/secret-lexicon.sh" 2>/dev/null || true
SECRET_RE="${VIBE_SECRET_RE:-sk-ant-[A-Za-z0-9_-]{10,}}"

PROMPT="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.prompt // .user_prompt // .message // empty' 2>/dev/null)"
[ -z "$PROMPT" ] && exit 0

FOUND="$(printf '%s' "$PROMPT" | grep -oE "$SECRET_RE" 2>/dev/null | head -1)"
[ -z "$FOUND" ] && exit 0

KIND="API-ключ"
case "$FOUND" in
  sk-ant-*) KIND="ключ Anthropic" ;;
  sk-or-*) KIND="ключ OpenRouter" ;;
  sk-proj-*|sk-*) KIND="ключ OpenAI" ;;
  ghp_*|github_pat_*) KIND="токен GitHub" ;;
  AKIA*) KIND="ключ AWS" ;;
  xox*) KIND="токен Slack" ;;
  *PRIVATE*) KIND="приватный ключ" ;;
esac

printf '🔐 В сообщении пользователя — живой %s (%.12s…). Ключ СКОМПРОМЕТИРОВАН самим фактом вставки в чат (контекст может логироваться). Сделай три вещи: (1) сохрани его в .env (не в код, .env в .gitignore), (2) скажи пользователю одной строкой: «ключ засветился в переписке — лучше выпустить новый у провайдера, старый отозвать; работаю пока с этим», (3) никогда не печатай его литералом — используй $ИМЯ_ПЕРЕМЕННОЙ.\n' "$KIND" "$FOUND"
exit 0
