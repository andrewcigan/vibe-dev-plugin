#!/bin/bash
# Vibe Dev v6.2 — маскирование секретов в выводе инструментов (F8; П8 аудита: Vercel CLI
# напечатал VERCEL_TOKEN в вывод — токен утёк в контекст сессии).
#
# PostToolUse умеет updatedToolOutput (движок >=2.1.121): заменяем вывод с замаскированными
# секретами (первые 8 символов + …MASKED) + дописываем агенту строку про $VAR-workflow.
# Маскирование НАМЕРЕННО ломает «напечатаю литерал токена, чтобы переиспользовать» —
# правильный паттерн только $ИМЯ_ПЕРЕМЕННОЙ.
# Cap: сканируем первые 64КБ вывода (анти-латентность на гигантских выводах).
#
# ⚠️ Контракт updatedToolOutput НЕ верифицирован вживую (как MessageDisplay в своё время):
# при неподдержке поле молча игнорируется движком — безопасная деградация (вывод без маски,
# как было до F8). Живой тест — при рестарте (см. SESSION).
#
# Аргументы: $1=cwd. Payload в HOOK_PAYLOAD. Печатает ЗАМЕНЁННЫЙ вывод (raw) или пусто
# (= менять нечего). Диспетчер сам оборачивает в JSON updatedToolOutput. exit 0.

set -u
CWD="${1:-$PWD}"

OUT="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '(.tool_response.stdout // .tool_response.output // empty)' 2>/dev/null | head -c 65536)"
[ -z "$OUT" ] && exit 0

SECRET_RE='sk-ant-[A-Za-z0-9_-]{10,}|sk-proj-[A-Za-z0-9_-]{10,}|sk-or-v1-[A-Za-z0-9_-]{10,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{16}|xox[bp]-[A-Za-z0-9-]{10,}'

printf '%s' "$OUT" | grep -qE "$SECRET_RE" 2>/dev/null || exit 0

# Маска: первые 8 символов + «…MASKED» (python — надёжная группа-замена на multibyte-тексте).
MASKED="$(printf '%s' "$OUT" | python3 -c '
import re, sys
pat = re.compile(r"(sk-ant-|sk-proj-|sk-or-v1-|ghp_|github_pat_|AKIA|xoxb-|xoxp-)[A-Za-z0-9_-]{6,}")
text = sys.stdin.read()
sys.stdout.write(pat.sub(lambda m: m.group(0)[:8] + "…MASKED-by-vibe-dev", text))
' 2>/dev/null)"
[ -z "$MASKED" ] && exit 0

printf '%s\n\n[Vibe Dev: в выводе был живой токен — замаскирован. Не печатай секреты литералом: используй $ИМЯ_ПЕРЕМЕННОЙ из .env; если токен засветился раньше — предложи пользователю ротацию.]' "$MASKED"
exit 0
