#!/bin/bash
# Vibe Dev v6 — bash-repeat counter (вызывается hooks/dispatch-post-tool-use.sh на PostToolUse/Bash).
# Анти-залипание, прокси №2 разбора [[tunnel-vision-goal-substitution]].
# 3-criterion gate: docs/anti-stuck-gate-2026-06-05.md (Гипотеза 2 — APPROVE-WITH-CHANGES).
#
# Считает ПОДРЯД падающие (exit≠0) Bash-команды ОДНОГО класса (после нормализации: нижний
# регистр, без цифр, схлоп пробелов — чтобы param-tweak одной команды считался как повтор).
# При пороге (≥3) печатает подсказку про субагент-диагностику, которую диспетчер инжектит
# модели (additionalContext). warn/inject, НЕ block.
#
# Mitigation против шума на TDD/build-циклах:
#   - успех (exit 0) -> сброс счётчика (тест позеленел = не залипание);
#   - сброс при Edit/Write/MultiEdit делает ДИСПЕТЧЕР (структурное изменение = прогресс);
#   - инжект РОВНО на пороге (не спамит на 4,5,...).
# Честная граница (см. gate): ловит retry-loop одной падающей команды, НЕ conceptual
# goal-substitution (для него — прокси №1, стоп-сигнал пользователя).
#
# Вход — HOOK_PAYLOAD (env, ставит диспетчер). Печатает текст подсказки или пусто. exit 0.

set -u
CWD="${1:-$PWD}"
STATE="$CWD/.harness/bash-repeat-state"
THRESH="${VIBE_BASH_REPEAT_THRESHOLD:-3}"

cmd="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_input.command // empty' 2>/dev/null)"
ec="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_response.exit_code' 2>/dev/null)"
succ="$(printf '%s' "${HOOK_PAYLOAD:-}" | jq -r '.tool_response.success' 2>/dev/null)"

# Успех -> сброс, тихо.
if [ "$succ" = "true" ] || [ "$ec" = "0" ]; then rm -f "$STATE" 2>/dev/null; exit 0; fi
# Нет команды -> ничего.
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

# Инжект РОВНО на пороге (не спамить на следующих повторах).
if [ "$count" -eq "$THRESH" ]; then
  cat <<TXT
⚠️ Одна и та же падающая команда повторяется $count раз подряд без структурных изменений — признак залипания (подкрутка параметров вместо диагноза). Останови повтор:
1. Запусти субагент-диагностику (Task tool, Sonnet/Opus) на структурное решение — параллельно, а не ещё один retry.
2. Прогони минимальную диагностику (curl / маленький тест-скрипт / сравнение 5-7 сценариев), чтобы выяснить причину, а не гадать.
3. Не меняй ещё один параметр того же подхода. Смени уровень: нужна ли вообще эта команда / этот путь.
TXT
fi
exit 0
