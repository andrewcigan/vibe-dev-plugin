#!/bin/bash
# Vibe Dev v6 — SessionStart dispatcher (точка входа на событие SessionStart). H6 loop-замыкание.
#
# Поток: stdin JSON -> guard (vibe-проект?) -> профиль -> handoff-pending-probe
#        -> inject additionalContext (warn о возможном пропуске handoff) или тихий pass.
#
# Активен standard,strict; minimal — off. Контракт SessionStart:
# docs/hooks-contract-verified-2026-06-03.md §4 (stdout идёт как контекст).

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/hook-io.sh"

hook_read_stdin
CWD="$(hook_field '.cwd')"
[ -z "$CWD" ] && CWD="$PWD"

# Guard: только vibe-target-проекты.
hook_is_vibe_project "$CWD" || hook_emit_pass

# Активация (v6.2 F2): heartbeat «хуки живы» + перевод pending-профиля в боевой.
# ДО фильтра профиля: heartbeat — свидетельство активации для ЛЮБОГО профиля.
hook_write_heartbeat "$CWD"
ACTIVATED="$(hook_activate_pending_profile "$CWD")"

PROFILE="$(hook_profile "$CWD")"
ROOT="$(hook_plugin_root)"

# Активен только в standard,strict.
if ! profile_in "standard,strict" "$PROFILE"; then
  [ -n "$ACTIVATED" ] && hook_emit_context "SessionStart" "✅ Vibe Dev: enforcement активирован живым хуком — профиль «${ACTIVATED}» подтверждён."
  hook_emit_pass
fi

# hook_run_check (fail-loud): краш проверки -> WARN-строка + crash-артефакт.
VERDICT="$(HOOK_PAYLOAD="$HOOK_INPUT" hook_run_check "$CWD" "handoff-probe" verdict "$ROOT/hooks/checks/handoff-pending-probe.sh" "$CWD")"
MSG="$(printf '%s' "$VERDICT" | awk -F'\t' '$1=="WARN"{print $2; exit}')"

# Crash-probe (F1): на старте сессии сообщить о крашах сторожей из прошлых сессий —
# fail-loud не должен оставаться незамеченным (иначе деградирует обратно в тихий fail-open).
CRASHES=""
if [ -d "$CWD/.harness/hook-crashes" ]; then
  CRASH_LIST="$(ls -1 "$CWD/.harness/hook-crashes" 2>/dev/null | sed 's/\.log$//' | tr '\n' ' ')"
  if [ -n "$(printf '%s' "$CRASH_LIST" | tr -d '[:space:]')" ]; then
    CRASHES="⚠️ Vibe Dev: в прошлых сессиях ПАДАЛИ сторожа: ${CRASH_LIST}— их проверки тогда НЕ выполнялись. Открой .harness/hook-crashes/*.log, почини причину (или сообщи о баге плагина), затем удали логи. Пока логи на месте — действия, которые сторожа охраняют, требуют ручной проверки."
  fi
fi

# Сборка inject: активация + handoff-warn + crash-probe (что есть).
OUT=""
[ -n "$ACTIVATED" ] && OUT="✅ Vibe Dev: enforcement активирован живым хуком — профиль «${ACTIVATED}» подтверждён."
if [ -n "$MSG" ]; then
  [ -n "$OUT" ] && OUT="$OUT

"
  OUT="${OUT}${MSG}"
fi
if [ -n "$CRASHES" ]; then
  [ -n "$OUT" ] && OUT="$OUT

"
  OUT="${OUT}${CRASHES}"
fi
[ -n "$OUT" ] && hook_emit_context "SessionStart" "$OUT"
hook_emit_pass
