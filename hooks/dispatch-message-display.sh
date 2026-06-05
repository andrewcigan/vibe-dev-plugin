#!/bin/bash
# Vibe Dev v6 — MessageDisplay dispatcher (точка входа на событие MessageDisplay). Язык-ловец.
#
# Поток: stdin JSON -> guard (vibe-проект?) -> профиль -> clarity-detector по .message_text.
# Нарушение (жаргон / развилка без «что теряешь» / человеко-дни) -> (1) запись в
# .harness/clarity-violations.log (метрика повторов), (2) displayContent = оригинал + флаг
# ловца на экране пользователя.
#
# ЧЕСТНО: MessageDisplay display-only (контракт code.claude.com/docs/en/hooks) — меняет только
# экран, оригинал сохраняется в transcript и его читает Claude. То есть это НЕ enforcement
# поведения модели (заставить меня говорить иначе хук не может), а ДЕТЕКТОР: меряет + подсвечивает,
# чтобы нарушение не прошло тихо. Дисциплину держит rules/decision-format.md. standard/strict.

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/hook-io.sh"

hook_read_stdin
CWD="$(hook_field '.cwd')"
[ -z "$CWD" ] && CWD="$PWD"

hook_is_vibe_project "$CWD" || hook_emit_pass

PROFILE="$(hook_profile "$CWD")"
ROOT="$(hook_plugin_root)"
profile_in "standard,strict" "$PROFILE" || hook_emit_pass

ISSUES="$(HOOK_PAYLOAD="$HOOK_INPUT" bash "$ROOT/hooks/checks/clarity-detector.sh" "$CWD" 2>/dev/null)"
if [ -n "$(printf '%s' "$ISSUES" | tr -d '[:space:]')" ]; then
  # (1) метрика повторов — лог нарушений (для /audit и саморефлексии).
  mkdir -p "$CWD/.harness" 2>/dev/null
  printf '%s\t%s\n' "$(date '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?')" "$ISSUES" >> "$CWD/.harness/clarity-violations.log" 2>/dev/null
  # (2) флаг на экране пользователя (оригинал + пометка). Только экран — Claude читает оригинал.
  MSG="$(hook_field '.message_text')"
  hook_emit_display "$MSG

⚠️ ловец непонятного: $ISSUES. Это для тебя сигнал — можешь попросить сказать проще/по-деловому."
fi
hook_emit_pass
