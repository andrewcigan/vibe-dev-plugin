#!/bin/bash
# Vibe Dev v6 — concurrent-write advisory (вызывается dispatch на Write/Edit/MultiEdit).
#
# ПЕРЕОСМЫСЛЕНО (v6): старый pre-write-concurrent.sh держал lock по PID хука — бессмысленно
# в stateless PreToolUse (процесс хука живёт миллисекунды, release не гарантирован, взаимное
# исключение в синхронном хуке гарантировать нельзя). Поэтому — session-based ADVISORY WARN,
# не block: раннее предупреждение о риске гонки. Настоящая защита — дизайн (раздельные файлы
# на воркер + merge). Закрывает инвариант «параллельная запись в shared-файл» предупреждением, честно (warn, не фиктивный block).
#
# Печатает "WARN<TAB>msg" / пусто. Всегда exit 0. Активен в standard,strict.

set -u
FILE="${1:-}"
CWD="${2:-$PWD}"
TAB="$(printf '\t')"
[ -z "$FILE" ] && exit 0

# Только shared-форматы, где параллельная запись реально затирает данные
case "$FILE" in
  *.json|*.csv|*.jsonl|*.yaml|*.yml) : ;;
  *) exit 0 ;;
esac

SID="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.session_id // empty' 2>/dev/null)"
[ -z "$SID" ] && SID="unknown"

LOCK_DIR="$CWD/.harness/locks"
mkdir -p "$LOCK_DIR" 2>/dev/null || exit 0
SAN="$(printf '%s' "$FILE" | tr '/ ' '__' | tr -cd 'A-Za-z0-9_.-')"
MARK="$LOCK_DIR/${SAN}.writer"
TTL=120
NOW="$(date +%s)"

if [ -f "$MARK" ]; then
  OTHER_SID="$(awk -F"$TAB" 'NR==1{print $1}' "$MARK" 2>/dev/null)"
  TS="$(awk -F"$TAB" 'NR==1{print $2}' "$MARK" 2>/dev/null)"
  TS=${TS:-0}
  AGE=$((NOW - TS))
  if [ "$AGE" -lt "$TTL" ] && [ -n "$OTHER_SID" ] && [ "$OTHER_SID" != "$SID" ]; then
    printf 'WARN%sФайл "%s" трогала другая сессия %sс назад — возможна параллельная запись (риск затереть). Если работает несколько агентов одновременно: пишите в раздельные файлы (suffix=сессия) и сливайте при /handoff.\n' "$TAB" "$FILE" "$AGE"
  fi
fi

# Обновить маркер своей сессией (advisory, без гарантии взаимного исключения)
printf '%s%s%s\n' "$SID" "$TAB" "$NOW" > "$MARK" 2>/dev/null
exit 0
