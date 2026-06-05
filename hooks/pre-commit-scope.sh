#!/bin/bash
# Vibe Dev — Pre-Commit Scope Hook
#
# Устанавливается как .git/hooks/pre-commit в проекте.
# Проверяет: diff ⊆ active feature.affected_files
#
# Closes WIP=1 / surgical changes scope leak.

set -e

PROJECT_ROOT="$(git rev-parse --show-toplevel)"

# Skip if not Vibe Dev project
if [ ! -f "$PROJECT_ROOT/feature_list.json" ]; then
    exit 0
fi

# Read active feature
ACTIVE=$(python3 -c "
import json, sys
try:
    d = json.load(open('$PROJECT_ROOT/feature_list.json'))
    a = d.get('active')
    print(a if a else '')
except:
    print('')
" 2>/dev/null)

if [ -z "$ACTIVE" ]; then
    # No active feature — allow commit (probably bootstrap or handoff)
    exit 0
fi

# Read affected_files for active feature
AFFECTED=$(python3 -c "
import json, sys, glob
try:
    d = json.load(open('$PROJECT_ROOT/feature_list.json'))
    active_id = d.get('active')
    if not active_id:
        sys.exit(0)

    # Find feature in any state list
    feat = None
    for state_list in d.get('features', {}).values():
        if isinstance(state_list, list):
            for f in state_list:
                if isinstance(f, dict) and f.get('id') == active_id:
                    feat = f
                    break
        if feat: break

    if not feat: sys.exit(0)

    files = feat.get('affected_files', [])
    if not files:
        # No affected_files declared — warn, but allow
        print('__NO_AFFECTED_FILES__')
    else:
        for f in files:
            # Expand glob if any
            for matched in glob.glob(f, recursive=True):
                print(matched)
            if '*' not in f and '?' not in f:
                print(f)
except Exception as e:
    print(f'__ERROR__: {e}', file=sys.stderr)
" 2>/dev/null)

if echo "$AFFECTED" | grep -q "__NO_AFFECTED_FILES__"; then
    cat >&2 <<EOF
⚠️  Active feature "$ACTIVE" не имеет affected_files в feature_list.json.

WIP=1 invariant требует явных affected_files для surgical changes.

Добавь поле:
"affected_files": ["src/api/...", "tests/..."]

Commit allowed (warning only), но добавь — иначе следующий /audit понизит Scope score.
EOF
    exit 0
fi

# Get staged files
STAGED=$(git diff --cached --name-only)

# Check each staged file
VIOLATIONS=()
for file in $STAGED; do
    MATCHED=0
    for affected in $AFFECTED; do
        # Match exact or by pattern (если affected с *)
        if [ "$file" = "$affected" ]; then
            MATCHED=1
            break
        fi
        # Match если в той же папке (parent dir of affected)
        affected_dir=$(dirname "$affected")
        if [[ "$file" == "$affected_dir"/* ]]; then
            MATCHED=1
            break
        fi
    done
    if [ "$MATCHED" -eq 0 ]; then
        # Allow common project files без affected_files
        case "$file" in
            SESSION.md|feature_list.json|error-journal.md|implementation-notes.md|README.md|.gitignore)
                continue
                ;;
            docs/decisions/*.md|.harness/cost-log.json|.harness/error-metrics.json)
                continue
                ;;
        esac
        VIOLATIONS+=("$file")
    fi
done

if [ ${#VIOLATIONS[@]} -gt 0 ]; then
    cat >&2 <<EOF
🚨 SCOPE LEAK BLOCKED.

Active feature: $ACTIVE
Affected files declared:
$(echo "$AFFECTED" | sed 's/^/  - /')

Файлы вне scope активной фичи:
$(printf '  ❌ %s\n' "${VIOLATIONS[@]}")

WIP=1 / surgical changes invariant: diff ⊆ feature.affected_files.

Что делать:
1. Если эти файлы должны быть частью текущей фичи — добавь их в feature.affected_files
2. ЕСЛИ нет — выноси в отдельную фичу (/feature add ...) и работай WIP=1
3. Не делай drive-by changes (anti-pattern AP-1)

Чтобы СРОЧНО override (на свой страх): git commit --no-verify
(но это инцидент → запишется в error-journal.md как scope_leak класс)
EOF
    exit 1
fi

exit 0
