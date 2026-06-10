#!/bin/bash
# Vibe Dev v6 — bash-repeat counter (вызывается hooks/dispatch-pre-tool-use.sh на PreToolUse/Bash).
# Анти-залипание, прокси №2 разбора [[tunnel-vision-goal-substitution]].
# 3-criterion gate: docs/anti-stuck-gate-2026-06-05.md (Гипотеза 2 — APPROVE-WITH-CHANGES).
#
# ⚠️ Носитель — PreToolUse (живая проверка 2026-06-10, движок 2.1.170): PostToolUse НЕ приходит
# на упавших с выводом Bash-командах (события нет; полей exit_code/success в payload нет;
# тихое падение даёт событие с returnCodeInterpretation) — счётчик «падений» на PostToolUse
# был мёртв вживую. Живая модель событий:
#   - PreToolUse приходит на КАЖДЫЙ запуск Bash -> здесь ИНКРЕМЕНТ счётчика класса команды;
#   - PostToolUse «чистый успех» (нет interrupted/returnCodeInterpretation) -> там СБРОС;
#   - Edit/Write/MultiEdit -> сброс делает PostToolUse-диспетчер (структурное изменение = прогресс).
# Значит count = «номер подряд идущего запуска одного класса БЕЗ успеха и без правок между ними».
# На пороге (THRESH=3: позади 2 запуска без успеха, это 3-я попытка) — WARN до выполнения.
#
# Класс команды: нижний регистр, без цифр, схлоп пробелов — param-tweak считается повтором.
# Инжект РОВНО на пороге (не спамит на 4,5,...). warn/inject, НЕ block.
# Честная граница (см. gate): ловит retry-loop одной падающей команды, НЕ conceptual
# goal-substitution (для него — прокси №1, стоп-сигнал пользователя).
#
# Вход — HOOK_PAYLOAD (env, ставит диспетчер; PreToolUse: .tool_input.command, tool_response
# ещё НЕТ). Печатает "WARN\t<подсказка>" на пороге или пусто. exit 0.

set -u
CWD="${1:-$PWD}"
STATE="$CWD/.harness/bash-repeat-state"
THRESH="${VIBE_BASH_REPEAT_THRESHOLD:-3}"
TAB="$(printf '\t')"

cmd="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

# Класс команды: нижний регистр, без цифр, схлоп пробелов -> хеш (cksum, портативно).
norm="$(printf '%s' "$cmd" | tr 'A-Z' 'a-z' | tr -d '0-9' | tr -s '[:space:]' ' ' | sed 's/^ *//;s/ *$//')"
hash="$(printf '%s' "$norm" | cksum | cut -d' ' -f1)"

last_hash=""; count=0
if [ -f "$STATE" ]; then
  last_hash="$(sed -n '1p' "$STATE" 2>/dev/null)"
  count="$(sed -n '2p' "$STATE" 2>/dev/null)"
fi
case "$count" in ''|*[!0-9]*) count=0 ;; esac

if [ "$hash" = "$last_hash" ]; then count=$((count + 1)); else count=1; fi
mkdir -p "$CWD/.harness" 2>/dev/null
printf '%s\n%s\n' "$hash" "$count" > "$STATE" 2>/dev/null

# WARN РОВНО на пороге (не спамить на следующих повторах).
if [ "$count" -eq "$THRESH" ]; then
  printf 'WARN%s⚠️ Эта команда запускается %s-й раз подряд без успеха и без структурных правок между запусками — признак залипания (подкрутка параметров вместо диагноза). Останови повтор: (1) запусти субагент-диагностику (Task tool, Sonnet/Opus) на структурное решение — параллельно, не ещё один retry; (2) прогони минимальную диагностику (curl / маленький тест-скрипт / 5-7 сценариев), чтобы выяснить причину, а не гадать; (3) смени уровень, не способ: нужна ли вообще эта команда / этот путь.\n' "$TAB" "$count"
fi
exit 0
