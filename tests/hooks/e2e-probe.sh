#!/bin/bash
# Сквозной зонд активации (v9 F0.3): движок РЕАЛЬНО вызывает сторожей?
#
# ЗАЧЕМ ОТДЕЛЬНО ОТ КОРПУСА. baseline-probe.sh запускает скрипты сторожей напрямую и потому
# не может отличить «сторожа исправны» от «сторожа исправны, но движок их больше не грузит».
# Обновление движка или поломка регистрации хуков дадут зелёный корпус при снятой охране.
# Этот зонд поднимает НАСТОЯЩУЮ сессию в песочнице и ищет след в журнале срабатываний.
#
# Критерий: после сессии в .harness/guard-stats.jsonl есть хотя бы одна запись.
# Записи достаточно — она физически появляется только изнутри hook_run_check.
set -u
PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SANDBOX="$(mktemp -d)"; trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/.harness"
( cd "$SANDBOX" && git init -q 2>/dev/null )
( cd "$SANDBOX" && claude -p "Создай файл zond.txt со строкой: проверка сторожей" \
    --plugin-dir "$PLUGIN" --permission-mode bypassPermissions ) >/dev/null 2>&1 </dev/null
LOG="$SANDBOX/.harness/guard-stats.jsonl"
if [ -s "$LOG" ]; then
  N=$(wc -l < "$LOG" | tr -d ' ')
  EVENTS=$(python3 -c "
import json,sys,collections
c=collections.Counter()
for l in open('$LOG',encoding='utf-8'):
    l=l.strip()
    if l:
        try: c[json.loads(l).get('event','?')]+=1
        except Exception: pass
print(', '.join(f'{k}×{v}' for k,v in c.items()))" 2>/dev/null)
  echo "АКТИВНЫ: движок вызвал сторожей $N раз ($EVENTS), движок $(claude --version 2>/dev/null)"
  exit 0
else
  echo "ТРЕВОГА: движок $(claude --version 2>/dev/null) НЕ вызвал ни одного сторожа."
  echo "Охрана снята: проверь регистрацию хуков (hooks/hooks.json) и установку плагина."
  exit 1
fi
