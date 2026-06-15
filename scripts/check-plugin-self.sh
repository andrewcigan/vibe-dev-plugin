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
# rules/quality-gate.md (примеры anti-pattern),
# docs/*audit*.md (отчёты аудитов цитируют реальность дословно — это данные, не оценки;
# в shipped-набор публичного релиза docs-отчёты не входят),
# _internal/ _archive/ research/ — приватная кухня (git-ignored, наружу не уходит;
# аудиты/разведки цитируют реальность дословно — данные, не оценки).
HUMAN_DAYS_HITS=$(grep -rnE "(~[0-9]+ дней|~[0-9]+ days|estimate: [0-9]+ day|[0-9]+ days minimum|на N дней|N дней)" \
    --include="*.md" --include="*.yaml" --include="*.json" \
    --exclude-dir=_internal --exclude-dir=_archive --exclude-dir=research . 2>/dev/null \
    | grep -v "rules/no-human-days.md" \
    | grep -v "CHANGELOG.md" \
    | grep -v "rules/quality-gate.md" \
    | grep -v "docs/.*audit" \
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
echo "=== 18. Fail-loud обвязка хуков (краш сторожа != молчаливый fail-open; v6.2 F1) ==="
if bash tests/hooks/test-failsafe.sh > /tmp/vibe-fltest.out 2>&1; then
    tail -1 /tmp/vibe-fltest.out
else
    echo "❌ тест fail-loud упал:"; cat /tmp/vibe-fltest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 19. Корпус реальных feature_list (формы боевых данных; v6.2 F1) ==="
if bash tests/hooks/test-real-fixtures.sh > /tmp/vibe-rftest.out 2>&1; then
    tail -1 /tmp/vibe-rftest.out
else
    echo "❌ тест real-fixtures упал:"; cat /tmp/vibe-rftest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 20. Активация enforcement (heartbeat + pending-профиль + pre-commit backstop; v6.2 F2) ==="
if bash tests/hooks/test-activation.sh > /tmp/vibe-acttest.out 2>&1; then
    tail -1 /tmp/vibe-acttest.out
else
    echo "❌ тест активации упал:"; cat /tmp/vibe-acttest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 21. Единый Stop-dispatcher (приоритеты + общий cap цепочки; v6.2 F3) ==="
if bash tests/hooks/test-stop-dispatcher.sh > /tmp/vibe-sdtest.out 2>&1; then
    tail -1 /tmp/vibe-sdtest.out
else
    echo "❌ тест Stop-диспетчера упал:"; cat /tmp/vibe-sdtest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 22. Clarity-gate: precision на labeled-корпусе (false positive = демоция; v6.2 F4) ==="
if bash tests/hooks/test-clarity-gate.sh > /tmp/vibe-cgtest.out 2>&1; then
    tail -1 /tmp/vibe-cgtest.out
else
    echo "❌ clarity-gate: провал (false positive на good-корпусе или потерян bad-кейс):"; cat /tmp/vibe-cgtest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 23. Surface + evidence по поверхности (монотонная строгость; v6.2 F5) ==="
if bash tests/hooks/test-surface-evidence.sh > /tmp/vibe-setest.out 2>&1; then
    tail -1 /tmp/vibe-setest.out
else
    echo "❌ тест surface-evidence упал:"; cat /tmp/vibe-setest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 24. Research-гейт архитектуры + lock-паттерн (v6.2 F6) ==="
if bash tests/hooks/test-research-gate.sh > /tmp/vibe-rgtest.out 2>&1; then
    tail -1 /tmp/vibe-rgtest.out
else
    echo "❌ тест research-гейта упал:"; cat /tmp/vibe-rgtest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 25. Closing-mode: деградация прав при закрытии сессии (v6.2 F7) ==="
if bash tests/hooks/test-closing-mode.sh > /tmp/vibe-cmtest.out 2>&1; then
    tail -1 /tmp/vibe-cmtest.out
else
    echo "❌ тест closing-mode упал:"; cat /tmp/vibe-cmtest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 26. Секрет-гигиена: ротация + маскирование вывода (v6.2 F8) ==="
if bash tests/hooks/test-secret-hygiene.sh > /tmp/vibe-shtest.out 2>&1; then
    tail -1 /tmp/vibe-shtest.out
else
    echo "❌ тест секрет-гигиены упал:"; cat /tmp/vibe-shtest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 27. Enforcement-config-protect: агент не ослабляет свои гейты (v6.2 F9) ==="
if bash tests/hooks/test-config-protect.sh > /tmp/vibe-cptest.out 2>&1; then
    tail -1 /tmp/vibe-cptest.out
else
    echo "❌ тест config-protect упал:"; cat /tmp/vibe-cptest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 28. Interrupt-recovery: техническое прерывание ≠ запрет (v6.2.1) ==="
if bash tests/hooks/test-interrupt-recovery.sh > /tmp/vibe-irtest.out 2>&1; then
    tail -1 /tmp/vibe-irtest.out
else
    echo "❌ тест interrupt-recovery упал:"; cat /tmp/vibe-irtest.out; ERRORS=$((ERRORS + 1))
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
