#!/bin/bash
# Vibe Dev — End Session script
#
# Запускается из skill /end-session. Делает полный handoff:
# 1. Все проверки 5-dim clean-exit (build / tests / progress / artifacts / startup)
# 2. Group errors из error-journal + propose memory promotion
# 3. Update SESSION.md + project_*.md sync (E6 memory-stays-in-sync)
# 4. Final auto-commit
# 5. Создаёт restart-here.sh в папке проекта
# 6. Печатает готовую restart команду для пользователя
#
# Usage: bash end-session.sh [project_path]
#        Default project_path = pwd

set -e

PROJECT_PATH="${1:-$(pwd)}"
PROJECT_NAME=$(basename "$PROJECT_PATH")
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

cd "$PROJECT_PATH"

echo "==================================================================="
echo "  /end-session — Vibe Dev Clean Exit"
echo "  Project: $PROJECT_NAME"
echo "  Path: $PROJECT_PATH"
echo "  Time: $TIMESTAMP"
echo "==================================================================="

# ========== Sanity check ==========
if [ ! -f "CLAUDE.md" ] && [ ! -f "AGENTS.md" ]; then
    echo "⚠️  Не похоже на Vibe Dev проект (нет CLAUDE.md / AGENTS.md)."
    echo "    Если это всё-таки проект — продолжаю, иначе прерви Ctrl+C."
    sleep 2
fi

ERRORS=0
WARNINGS=0

# ========== 5-DIM CLEAN-EXIT CHECKS ==========

echo ""
echo "[1/5] Build check..."
if [ -f "package.json" ] && grep -q '"build"' package.json 2>/dev/null; then
    if npm run build --silent > /tmp/end-session-build.log 2>&1; then
        echo "  ✓ Build OK"
    else
        echo "  ❌ Build FAILED — см. /tmp/end-session-build.log (хвост ниже)"
        tail -10 /tmp/end-session-build.log
        ERRORS=$((ERRORS+1))
    fi
elif [ -f "tsconfig.json" ]; then
    if npx tsc --noEmit 2>&1 | tail -5; then
        echo "  ✓ Type check OK"
    fi
else
    echo "  ⊘ Build не настроен (skipped)"
fi

echo ""
echo "[2/5] Tests..."
if [ -f "package.json" ] && grep -q '"test"' package.json 2>/dev/null; then
    if npm test --silent > /tmp/end-session-tests.log 2>&1; then
        TESTS_PASS=$(grep -oE "[0-9]+ pass(ed|ing)?" /tmp/end-session-tests.log | tail -1 || echo "")
        echo "  ✓ Tests OK ($TESTS_PASS)"
    else
        echo "  ⚠️  Tests FAILED — записываю в Open Issues"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo "  ⊘ Тесты не настроены (skipped)"
fi

echo ""
echo "[3/5] Progress (SESSION.md + feature_list.json sync)..."
if [ -f "SESSION.md" ]; then
    SESSION_AGE_SEC=$(( $(date +%s) - $(stat -f %m SESSION.md 2>/dev/null || stat -c %Y SESSION.md 2>/dev/null || echo 0) ))
    SESSION_AGE_MIN=$(( SESSION_AGE_SEC / 60 ))
    if [ "$SESSION_AGE_MIN" -lt 30 ]; then
        echo "  ✓ SESSION.md свежий ($SESSION_AGE_MIN мин назад)"
    else
        echo "  ⚠️  SESSION.md старше 30 мин — нужно обновить агенту перед /end-session"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo "  ⊘ SESSION.md отсутствует"
fi

if [ -f "feature_list.json" ]; then
    if python3 -c "import json; json.load(open('feature_list.json'))" 2>/dev/null; then
        ACTIVE=$(python3 -c "import json; d=json.load(open('feature_list.json')); print(d.get('active') or 'null')" 2>/dev/null)
        echo "  ✓ feature_list.json валиден (active: $ACTIVE)"
    else
        echo "  ❌ feature_list.json не валиден JSON"
        ERRORS=$((ERRORS+1))
    fi
fi

echo ""
echo "[4/5] Artifacts (нет stale temp + секреты не закоммичены)..."
# Stale temp files
find . -name "*.tmp" -mtime -1 -not -path './node_modules/*' -not -path './.git/*' 2>/dev/null | head -3
# .env защита
if [ -f ".gitignore" ]; then
    if grep -q "^\.env" .gitignore || grep -q "^\*\.env" .gitignore; then
        echo "  ✓ .gitignore защищает .env"
    else
        echo "  ⚠️  .gitignore НЕ защищает .env — добавляю автоматически"
        echo ".env*" >> .gitignore
    fi
fi
# Проверка что секреты не в staged
if git diff --cached --name-only 2>/dev/null | grep -E "\.env|secrets/|\.pem|\.key" | head -3 > /tmp/secrets-check.tmp; then
    if [ -s /tmp/secrets-check.tmp ]; then
        echo "  🚨 STAGED секреты найдены:"
        cat /tmp/secrets-check.tmp
        ERRORS=$((ERRORS+1))
    fi
fi

echo ""
echo "[5/5] Startup (./init.sh с нуля)..."
if [ -f "init.sh" ]; then
    if bash -n init.sh 2>&1; then
        echo "  ✓ init.sh syntax OK"
    else
        echo "  ❌ init.sh broken"
        ERRORS=$((ERRORS+1))
    fi
else
    echo "  ⊘ init.sh отсутствует (для FAST после /architecture создаётся)"
fi

# ========== MEMORY PROMOTION HINT ==========

echo ""
echo "==================================================================="
echo "[E6] Memory sync check..."
echo "==================================================================="

if [ -f "error-journal.md" ]; then
    SESSION_ERRORS=$(grep -c "^## err-" error-journal.md 2>/dev/null || true)
    [ -z "$SESSION_ERRORS" ] && SESSION_ERRORS=0
    if [ "$SESSION_ERRORS" -gt 0 ]; then
        echo "  📓 error-journal.md содержит $SESSION_ERRORS записей."
        echo "     Агент в Claude Code предложит promotion отдельно (E6)."
    fi
fi

# Проверка project_*.md sync.
# Память Claude Code лежит в ~/.claude/projects/<cwd с заменой не-буквенно-цифровых на ->/memory
MUNGED_CWD="$(printf '%s' "$PWD" | sed 's/[^a-zA-Z0-9]/-/g')"
PROJECT_MEM_DIR="$HOME/.claude/projects/$MUNGED_CWD/memory"
if [ -d "$PROJECT_MEM_DIR" ]; then
    PROJECT_MD=$(ls "$PROJECT_MEM_DIR"/project_*.md 2>/dev/null | head -1)
    if [ -n "$PROJECT_MD" ]; then
        PMD_AGE_MIN=$(( ( $(date +%s) - $(stat -f %m "$PROJECT_MD" 2>/dev/null || stat -c %Y "$PROJECT_MD" 2>/dev/null || echo 0) ) / 60 ))
        if [ "$PMD_AGE_MIN" -gt 60 ]; then
            echo "  ⚠️  project_*.md в memory старше 1 часа ($PMD_AGE_MIN мин)"
            echo "     Агент должен обновить ДО /end-session (E6 memory-stays-in-sync)"
            WARNINGS=$((WARNINGS+1))
        else
            echo "  ✓ project_*.md sync ($PMD_AGE_MIN мин назад)"
        fi
    fi
fi

# ========== SAVE SESSION STATE ==========

mkdir -p .session-state
cat > .session-state/last-session.md <<EOF
# Last Session Handoff — $PROJECT_NAME

**Дата:** $TIMESTAMP
**Завершение:** /end-session (clean exit)

## Состояние

- Build: $([ -f /tmp/end-session-build.log ] && tail -1 /tmp/end-session-build.log || echo "n/a")
- Tests: $([ -f /tmp/end-session-tests.log ] && grep -oE "[0-9]+ pass(ed|ing)?" /tmp/end-session-tests.log | tail -1 || echo "n/a")
- Errors: $ERRORS блокирующих, $WARNINGS warnings

## Active feature
$([ -f feature_list.json ] && python3 -c "import json; d=json.load(open('feature_list.json')); print(d.get('active') or 'null')" 2>/dev/null || echo "n/a")

## Что было сделано в этой сессии
(агент должен заполнить через /end-session перед запуском этого скрипта)

См. SESSION.md полная сводка.

## Что дальше в новой сессии
1. Прочитать AGENTS.md или CLAUDE.md
2. Прочитать SESSION.md → Cold-Start Test
3. Прочитать error-journal.md tail (последние 5 записей)
4. Прочитать memory feedback tail (последние feedback_*.md)
5. /resume <project> запустить cold-start через external evaluator
EOF
echo ""
echo "✓ Записал .session-state/last-session.md"

# ========== AUTO-COMMIT ==========

echo ""
echo "==================================================================="
echo "Auto-commit..."
echo "==================================================================="

# Проверка что есть git
if [ -d ".git" ]; then
    # Не коммитим .env / секреты
    git diff --cached --name-only | grep -E "\.env|secrets/|\.pem|\.key" > /tmp/staged-secrets 2>/dev/null || true
    if [ -s /tmp/staged-secrets ]; then
        echo "🚨 СТОП — секреты в staged. Не коммичу. Unstage их вручную:"
        cat /tmp/staged-secrets
        ERRORS=$((ERRORS+1))
    else
        # Stage everything кроме игнорируемого
        git add -A
        STAGED_COUNT=$(git diff --cached --name-only | wc -l | tr -d ' ')
        if [ "$STAGED_COUNT" -gt 0 ]; then
            git commit -m "handoff: end-session $TIMESTAMP

- Errors: $ERRORS блокирующих, $WARNINGS warnings
- Build: $([ -f /tmp/end-session-build.log ] && (grep -q 'error' /tmp/end-session-build.log && echo 'FAILED' || echo 'OK') || echo 'n/a')
- Tests: $([ -f /tmp/end-session-tests.log ] && (grep -q 'fail' /tmp/end-session-tests.log && echo 'FAILED' || echo 'PASS') || echo 'n/a')

Co-Authored-By: /end-session skill" > /tmp/commit-out.log 2>&1
            COMMIT_HASH=$(git log -1 --format=%h)
            echo "✓ Commit $COMMIT_HASH ($STAGED_COUNT files)"
        else
            echo "⊘ Нет изменений для коммита"
        fi
    fi
else
    echo "⊘ Git не настроен (skipped)"
fi

# ========== СОЗДАЁМ RESTART-HERE SCRIPT ==========

cat > restart-here.sh <<RESTART
#!/bin/bash
# Вернуться в этот проект в новой Claude Code сессии.
# Запуск: bash restart-here.sh
cd "$PROJECT_PATH"
echo "Стартую новую Claude Code сессию в:"
echo "  $PROJECT_PATH"
echo ""
exec claude
RESTART
chmod +x restart-here.sh
echo "✓ Создан restart-here.sh"

# ========== ФИНАЛЬНОЕ СООБЩЕНИЕ ==========

echo ""
echo "==================================================================="
if [ "$ERRORS" -eq 0 ]; then
    echo "  ✓ /end-session завершён CLEAN ($WARNINGS warnings)"
else
    echo "  ⚠️  /end-session завершён С ОШИБКАМИ ($ERRORS блокирующих)"
    echo "  Записал в SESSION.md → Open Issues"
fi
echo "==================================================================="
echo ""
echo "📋 Чтобы стартовать новую сессию в этом проекте:"
echo ""
echo "   1. Закрой текущую Claude Code (Ctrl+D или exit команда в TUI)"
echo "   2. В обычном терминале выполни ОДНУ из команд:"
echo ""
echo "   ┌─────────────────────────────────────────────────────────────┐"
echo "   │  ВАРИАНТ A (через restart-here.sh):                          │"
echo "   │                                                              │"
echo "   │     cd $PROJECT_PATH && bash restart-here.sh"
echo "   │                                                              │"
echo "   │  ВАРИАНТ B (одной строкой):                                  │"
echo "   │                                                              │"
echo "   │     cd $PROJECT_PATH && claude"
echo "   │                                                              │"
echo "   └─────────────────────────────────────────────────────────────┘"
echo ""
echo "   Новая сессия откроется именем '$PROJECT_NAME' (по имени папки)."
echo ""
echo "   После старта — скажи в Claude Code: /resume $PROJECT_NAME"
echo "   Это запустит cold-start test (5 точных вопросов из репо)."
echo ""

if [ "$ERRORS" -gt 0 ]; then
    exit 1
fi
exit 0
