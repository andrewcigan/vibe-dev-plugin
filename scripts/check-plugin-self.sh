#!/bin/bash
# Vibe Dev — Self-check для плагина (H28 — CI на плагин)
# Запускается перед commit в репо плагина.
# Проверяет: плагин сам не нарушает свои правила.

set -e
cd "$(dirname "$0")/.."

ERRORS=0

echo "=== 1. Запрещённые «человеко-дни» в шаблонах ==="
# Игнорируем: rules/no-human-days.md (описывает правило с примерами),
# CHANGELOG.md (история починок упоминает исторические нарушения),
# rules/quality-gate.md (примеры anti-pattern)
HUMAN_DAYS_HITS=$(grep -rnE "(~[0-9]+ дней|~[0-9]+ days|estimate: [0-9]+ day|[0-9]+ days minimum|на N дней|N дней)" \
    --include="*.md" --include="*.yaml" --include="*.json" . 2>/dev/null \
    | grep -v "rules/no-human-days.md" \
    | grep -v "CHANGELOG.md" \
    | grep -v "rules/quality-gate.md" \
    | grep -v ".git/" \
    | head -5)

if [ -n "$HUMAN_DAYS_HITS" ]; then
    echo "❌ Найдены оценки в человеко-днях:"
    echo "$HUMAN_DAYS_HITS"
    ERRORS=$((ERRORS + 1))
else
    echo "✓ Нет нарушений no-human-days"
fi

echo ""
echo "=== 2. AGENTS.md в templates не должно быть (Claude Code convention) ==="
if [ -f "templates/AGENTS.md" ]; then
    echo "❌ templates/AGENTS.md существует. Должен быть templates/CLAUDE.md"
    ERRORS=$((ERRORS + 1))
else
    echo "✓ templates/CLAUDE.md (правильно)"
fi

echo ""
echo "=== 3. Все skills имеют SKILL.md ==="
for s in skills/*/; do
    if [ ! -f "$s/SKILL.md" ]; then
        echo "❌ Missing $s/SKILL.md"
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""
echo "=== 4. Все agents имеют frontmatter ==="
for a in agents/*.md; do
    if ! head -1 "$a" | grep -q "^---$"; then
        echo "❌ No frontmatter: $a"
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""
echo "=== 5. Hooks executable ==="
for h in hooks/*.sh scripts/*.sh templates/init.sh; do
    if [ ! -x "$h" ]; then
        echo "❌ Not executable: $h"
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""
echo "=== 6. Critical rules файлы существуют ==="
for r in rules/no-human-days.md rules/message-finalization.md rules/check-yourself-first.md rules/quality-gate.md; do
    if [ ! -f "$r" ]; then
        echo "❌ Missing: $r"
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""
echo "=== 7. JSON/YAML valid ==="
python3 -c "import json; json.load(open('.claude-plugin/plugin.json'))" 2>&1 && echo "✓ plugin.json" || ERRORS=$((ERRORS + 1))
python3 -c "import json; json.load(open('templates/feature_list.json'))" 2>&1 && echo "✓ feature_list.json template" || ERRORS=$((ERRORS + 1))

echo ""
echo "=== 8. Таблица трассировки полна (3 атрибута + живые ссылки) ==="
bash scripts/check-traceability.sh || ERRORS=$((ERRORS + 1))

echo ""
echo "=== 9. Регрессионный тест PreToolUse-хуков ==="
if bash tests/hooks/test-pre-tool-use.sh > /tmp/vibe-hooktest.out 2>&1; then
    tail -1 /tmp/vibe-hooktest.out
else
    echo "❌ тест хуков упал:"; cat /tmp/vibe-hooktest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 10. Регрессионный тест Stop-хука (H19) ==="
if bash tests/hooks/test-stop-intent.sh > /tmp/vibe-stoptest.out 2>&1; then
    tail -1 /tmp/vibe-stoptest.out
else
    echo "❌ тест Stop-хука упал:"; cat /tmp/vibe-stoptest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 11. Регрессионный тест UserPromptSubmit-хука (H6) ==="
if bash tests/hooks/test-user-prompt.sh > /tmp/vibe-uptest.out 2>&1; then
    tail -1 /tmp/vibe-uptest.out
else
    echo "❌ тест UserPromptSubmit-хука упал:"; cat /tmp/vibe-uptest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 12. Регрессионный тест SessionStart-хука (H6 loop) ==="
if bash tests/hooks/test-session-start.sh > /tmp/vibe-sstest.out 2>&1; then
    tail -1 /tmp/vibe-sstest.out
else
    echo "❌ тест SessionStart-хука упал:"; cat /tmp/vibe-sstest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 13. Регрессионный тест PostToolUse-хука (анти-залипание №2) ==="
if bash tests/hooks/test-post-tool-use.sh > /tmp/vibe-pttest.out 2>&1; then
    tail -1 /tmp/vibe-pttest.out
else
    echo "❌ тест PostToolUse-хука упал:"; cat /tmp/vibe-pttest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 14. Регрессионный тест user-rules (hookify) ==="
if bash tests/hooks/test-user-rules.sh > /tmp/vibe-urtest.out 2>&1; then
    tail -1 /tmp/vibe-urtest.out
else
    echo "❌ тест user-rules упал:"; cat /tmp/vibe-urtest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 15. Регрессионный тест model-swap-guard (дыра аудита) ==="
if bash tests/hooks/test-model-swap.sh > /tmp/vibe-mstest.out 2>&1; then
    tail -1 /tmp/vibe-mstest.out
else
    echo "❌ тест model-swap упал:"; cat /tmp/vibe-mstest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 16. Регрессионный тест clarity-detector (язык-ловец) ==="
if bash tests/hooks/test-clarity-detector.sh > /tmp/vibe-cltest.out 2>&1; then
    tail -1 /tmp/vibe-cltest.out
else
    echo "❌ тест clarity-detector упал:"; cat /tmp/vibe-cltest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 17. Gate обезличенности (нет личных данных в shipped) ==="
if bash tests/hooks/test-no-personal-data.sh > /tmp/vibe-nptest.out 2>&1; then
    tail -1 /tmp/vibe-nptest.out
else
    echo "❌ gate обезличенности упал (личное в shipped или сломана логика gate):"; cat /tmp/vibe-nptest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
if [ "$ERRORS" -gt 0 ]; then
    echo "==================================================="
    echo "❌ $ERRORS errors. Плагин нарушает свои же правила."
    echo "==================================================="
    exit 1
else
    echo "==================================================="
    echo "✓ Plugin self-check passed"
    echo "==================================================="
fi
