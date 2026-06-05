#!/bin/bash
# Vibe Dev v6 — UserPromptSubmit dispatcher (точка входа на событие UserPromptSubmit). H6.
#
# Поток: stdin JSON -> guard (vibe-проект?) -> профиль -> handoff-reminder
#        -> inject additionalContext (cold-start чеклист) или тихий pass.
#
# handoff-reminder — warn-уровень (inject, НЕ block): промпт пользователя легитимен,
# блокировать его нельзя; напоминание видно модели. Активен standard,strict; minimal — off.
# Контракт UserPromptSubmit: docs/hooks-contract-verified-2026-06-03.md §4 (stdout как контекст).

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/hook-io.sh"

hook_read_stdin
CWD="$(hook_field '.cwd')"
[ -z "$CWD" ] && CWD="$PWD"

# Guard: только vibe-target-проекты.
hook_is_vibe_project "$CWD" || hook_emit_pass

PROFILE="$(hook_profile "$CWD")"
ROOT="$(hook_plugin_root)"

# Активен только в standard,strict.
profile_in "standard,strict" "$PROFILE" || hook_emit_pass

PIECES=""

# H6: сигнал завершения сессии -> cold-start чеклист + маркер handoff-pending.
HANDOFF="$(HOOK_PAYLOAD="$HOOK_INPUT" bash "$ROOT/hooks/checks/handoff-reminder.sh" "$CWD" 2>/dev/null)"
if [ -n "$(printf '%s' "$HANDOFF" | tr -d '[:space:]')" ]; then
  # Маркер для SessionStart-probe (loop H6): следующий старт проверит, обновился ли
  # SESSION.md после этого сигнала. Если нет — handoff мог не записаться -> warn.
  mkdir -p "$CWD/.harness" 2>/dev/null
  : > "$CWD/.harness/handoff-pending" 2>/dev/null
  PIECES="$HANDOFF"
fi

# Анти-залипание (прокси №1 tunnel-vision): стоп-сигнал / коррекция курса -> напоминание
# (смена УРОВНЯ, не способа). Маркер handoff НЕ ставит — это не завершение сессии.
STUCK="$(HOOK_PAYLOAD="$HOOK_INPUT" bash "$ROOT/hooks/checks/stuck-signal-reminder.sh" "$CWD" 2>/dev/null)"
if [ -n "$(printf '%s' "$STUCK" | tr -d '[:space:]')" ]; then
  if [ -n "$PIECES" ]; then
    PIECES="$PIECES
—
$STUCK"
  else
    PIECES="$STUCK"
  fi
fi

if [ -n "$(printf '%s' "$PIECES" | tr -d '[:space:]')" ]; then
  hook_emit_context "UserPromptSubmit" "$PIECES"
fi
hook_emit_pass
