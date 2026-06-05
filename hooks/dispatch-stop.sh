#!/bin/bash
# Vibe Dev v6 — Stop dispatcher (единая точка входа на событие Stop). H19.
#
# Поток: stdin JSON -> guard (vibe-проект?) -> профиль -> stop-intent-without-action
#        -> decision:block (продолжить ход) или тихий pass.
#
# Stop-intent — discipline-усиление поведения агента: активен в standard,strict; minimal — off.
# Не зависит от engine-version (это про ход агента, не про формат feature_list).
# Контракт Stop: docs/hooks-contract-verified-2026-06-03.md §5 (decision:block, cap 8).

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

VERDICT="$(HOOK_PAYLOAD="$HOOK_INPUT" bash "$ROOT/hooks/checks/stop-intent-without-action.sh" "$CWD" 2>/dev/null)"

# Первая BLOCK-строка -> stop-block (заставить продолжить).
BLOCK_MSG="$(printf '%s' "$VERDICT" | awk -F'\t' '$1=="BLOCK"{print $2; exit}')"
if [ -n "$BLOCK_MSG" ]; then
  hook_emit_stop_block "Vibe Dev (профиль ${PROFILE}): ${BLOCK_MSG}"
fi
hook_emit_pass
