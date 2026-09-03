#!/bin/bash
# Пин модели субагента — проверяемый факт, а не запись в документе (v9 F3.3).
#
# ЗАЧЕМ. docs/agent-registry.md объявляет, на какой модели работает каждая роль: верхний
# уровень (архитектура, план, критика, аудит) — Fable 5.1, написание кода — Opus 5, сбор
# сырья — Sonnet 5. До этого сверка держалась на самопроверке ФАЙЛОВ: она видит, что во
# фронтматтере написано «fable», и не видит, на чём субагент реально стартовал.
#
# ЧТО ДЕЛАЕТ. На PostToolUse инструмента Agent берёт из ответа модель, на которой субагент
# фактически стартовал, и сверяет с реестром. Расхождение → предупреждение и запись в журнал.
#
# САМОДИАГНОСТИКА. Если поля с фактической моделью в ответе нет, сторож пишет об этом в журнал
# срабатываний отдельной пометкой. Так мы узнаем правду о возможностях движка из живой работы,
# а не из предположения — и не будем считать замком то, что им не является.
#
# Аргументы: $1=cwd. Payload в HOOK_PAYLOAD. Печатает "WARN\tmsg", пусто = ОК.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/../lib/guard-prelude.sh"
guard_require_tools jq
CWD="${1:-$PWD}"; ROOT="${2:-}"; TAB="$(printf '\t')"

TOOL="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_name // empty' 2>/dev/null)"
[ "$TOOL" = "Agent" ] || guard_done

TYPE="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)"
ACTUAL="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_response.resolvedModel // empty' 2>/dev/null)"
[ -n "$TYPE" ] || guard_done

# Роль вне плагина (общие агенты движка) — не наша забота.
case "$TYPE" in vibe-dev:*) TYPE="${TYPE#vibe-dev:}" ;; *) guard_done ;; esac

REG="${ROOT:-$CWD}/docs/agent-registry.md"
[ -f "$REG" ] || guard_done
EXPECT="$(awk -F'|' -v n=" $TYPE " '$2==n {gsub(/ /,"",$4); print $4; exit}' "$REG" 2>/dev/null)"
[ -n "$EXPECT" ] || guard_done

if [ -z "$ACTUAL" ]; then
  # Движок не сообщает фактическую модель — фиксируем это как факт, а не молчим.
  printf 'WARN%sПин модели проверить нечем: движок не сообщил, на какой модели стартовал субагент «%s». Пин остаётся дисциплиной, а не замком — это надо отразить в таблице механизмов, а не выдавать за проверку.\n' "$TAB" "$TYPE"
  guard_done
fi

case "$ACTUAL" in
  *"$EXPECT"*) : ;;
  *) printf 'WARN%sРоль «%s» по реестру работает на модели %s, а субагент стартовал на %s. Либо роль запущена мимо контракта, либо реестр устарел — сверь docs/agent-registry.md и фронтматтер роли.\n' "$TAB" "$TYPE" "$EXPECT" "$ACTUAL" ;;
esac
guard_done
