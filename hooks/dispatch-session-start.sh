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

PROFILE="$(hook_profile "$CWD")"
ROOT="$(hook_plugin_root)"

# Активен только в standard,strict.
profile_in "standard,strict" "$PROFILE" || hook_emit_pass

VERDICT="$(HOOK_PAYLOAD="$HOOK_INPUT" bash "$ROOT/hooks/checks/handoff-pending-probe.sh" "$CWD" 2>/dev/null)"
MSG="$(printf '%s' "$VERDICT" | awk -F'\t' '$1=="WARN"{print $2; exit}')"
if [ -n "$MSG" ]; then
  hook_emit_context "SessionStart" "$MSG"
fi
hook_emit_pass
