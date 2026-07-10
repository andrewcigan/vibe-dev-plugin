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
echo "=== 4. Все agents: frontmatter + контракт model/effort + сверка тиров (v8 L1-F1/F2) ==="
for a in agents/*.md; do
    if ! head -1 "$a" | grep -q "^---$"; then
        echo "❌ No frontmatter: $a"
        ERRORS=$((ERRORS + 1)); continue
    fi
    # Контракт L1-F1: model + effort обязательны у КАЖДОГО агента (движок читает их из
    # фронтматтера; наличие — enforced здесь). Фронтматтер короткий → ищем в первых 20 строках.
    if ! head -20 "$a" | grep -q "^model:"; then
        echo "❌ Нет 'model:' во фронтматтере (L1-F1): $a"; ERRORS=$((ERRORS + 1))
    fi
    if ! head -20 "$a" | grep -q "^effort:"; then
        echo "❌ Нет 'effort:' во фронтматтере (L1-F1): $a"; ERRORS=$((ERRORS + 1))
    fi
done
# L5-F4: read-only роли (верификаторы/критики) ОБЯЗАНЫ нести disallowedTools с Write+Edit —
# движок физически запрещает им писать код (гарантия «adversarial-верификатор не подгонит код
# под свой тест, критик не чинит»). Обход = self-check red.
READONLY_ROLES="data-model-reviewer user-perspective-critic test-researcher stage-verifier evaluator-agent browser-tester"
RO_OK=0
for role in $READONLY_ROLES; do
    f="agents/$role.md"
    if [ ! -f "$f" ]; then echo "❌ read-only роль отсутствует: $f (L5-F4)"; ERRORS=$((ERRORS + 1)); continue; fi
    dt="$(head -20 "$f" | grep -m1 '^disallowedTools:')"
    if printf '%s' "$dt" | grep -q 'Write' && printf '%s' "$dt" | grep -q 'Edit'; then
        RO_OK=$((RO_OK + 1))
    else
        echo "❌ read-only роль $role без disallowedTools Write+Edit (L5-F4: верификатор/критик не пишет код)"; ERRORS=$((ERRORS + 1))
    fi
done
[ "$RO_OK" -gt 0 ] && echo "✓ read-only роли с disallowedTools Write/Edit: $RO_OK/6 (L5-F4)"
# L4-F4: читающие агенты (researcher) обязаны нести контракт возврата «дайджест ≤X КБ + путь»
# (c7 — сужаем ТОЛЬКО объём сырья в главном потоке). Критики/reviewer НЕ трогаем (whitelist —
# их стороннее мнение сохраняем полностью).
READER_ROLES="github-researcher best-practices-researcher test-researcher market-researcher"
RD_OK=0
for role in $READER_ROLES; do
    f="agents/$role.md"
    if [ -f "$f" ] && grep -q "L4-F4" "$f"; then RD_OK=$((RD_OK + 1))
    else echo "❌ читающий агент $role без контракта возврата L4-F4 (дайджест+путь, c7)"; ERRORS=$((ERRORS + 1)); fi
done
[ "$RD_OK" -gt 0 ] && echo "✓ читатели с контрактом возврата дайджест+путь: $RD_OK/4 (L4-F4)"
# L1-F2: реестр docs/agent-registry.md — источник истины роль↔тир. Модель во фронтматтере
# обязана совпадать с колонкой «Модель» таблицы. Расхождение = self-check red (реестр правит
# тир «одним движением», фронтматтер обязан следовать).
REG="docs/agent-registry.md"
TIER_MISMATCH=0
if [ -f "$REG" ]; then
    while IFS='|' read -r _ c_name c_desc c_model c_rest; do
        name="$(printf '%s' "$c_name" | tr -d '[:space:]')"
        model="$(printf '%s' "$c_model" | tr -d '[:space:]')"
        case "$name" in ''|"Агент"|-*) continue ;; esac
        [ -f "agents/$name.md" ] || continue
        if ! head -20 "agents/$name.md" | grep -q "^model: ${model}$"; then
            actual="$(head -20 "agents/$name.md" | grep -m1 '^model:' | sed 's/model: *//')"
            echo "❌ Тир не совпал с реестром: agents/$name.md='$actual', реестр='$model'"
            TIER_MISMATCH=$((TIER_MISMATCH + 1))
        fi
    done < <(grep '^| ' "$REG")
    if [ "$TIER_MISMATCH" -gt 0 ]; then
        ERRORS=$((ERRORS + TIER_MISMATCH))
    else
        echo "✓ роль↔тир: 24 агента совпали с реестром (L1-F2)"
    fi
else
    echo "❌ Нет реестра $REG (L1-F2)"; ERRORS=$((ERRORS + 1))
fi

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
echo "=== 29. M2 слепок перед сжатием: extractive-парсинг транскрипта (v7 автопамять) ==="
if bash tests/hooks/test-pre-compact.sh > /tmp/vibe-pctest.out 2>&1; then
    tail -1 /tmp/vibe-pctest.out
else
    echo "❌ тест pre-compact упал:"; cat /tmp/vibe-pctest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 30. Новые замки: secret-scan (P14) + folder-scope (P9) (v7 Волна 3) ==="
if bash tests/hooks/test-new-locks.sh > /tmp/vibe-nltest.out 2>&1; then
    tail -1 /tmp/vibe-nltest.out
else
    echo "❌ тест new-locks упал:"; cat /tmp/vibe-nltest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 31. Гигиена журнала: read-only аудит + дедуп + circuit breaker (v7 Волна 4) ==="
if bash tests/hooks/test-journal-hygiene.sh > /tmp/vibe-jhtest.out 2>&1; then
    tail -1 /tmp/vibe-jhtest.out
else
    echo "❌ тест journal-hygiene упал:"; cat /tmp/vibe-jhtest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 32. wave-continue: go-режим + ход кончился вопросом (P6, v7 Волна 5) ==="
if bash tests/hooks/test-wave-continue.sh > /tmp/vibe-wctest.out 2>&1; then
    tail -1 /tmp/vibe-wctest.out
else
    echo "❌ тест wave-continue упал:"; cat /tmp/vibe-wctest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 33. Единый резолвер путей: fail-loud при неоднозначном корне (v8 L2-F1) ==="
if bash tests/hooks/test-resolve-paths.sh > /tmp/vibe-rptest.out 2>&1; then
    tail -1 /tmp/vibe-rptest.out
else
    echo "❌ тест resolve-paths упал:"; cat /tmp/vibe-rptest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 34. Provenance-лог append-only через git pre-commit (v8 L3-F2) ==="
if bash tests/hooks/test-provenance-append-only.sh > /tmp/vibe-paotest.out 2>&1; then
    tail -1 /tmp/vibe-paotest.out
else
    echo "❌ тест provenance append-only упал:"; cat /tmp/vibe-paotest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 35. Провенанс-захват + клапан честности (engine≥8, v8 L3-F1) ==="
if bash tests/hooks/test-provenance-capture.sh > /tmp/vibe-pctest2.out 2>&1; then
    tail -1 /tmp/vibe-pctest2.out
else
    echo "❌ тест provenance-capture упал:"; cat /tmp/vibe-pctest2.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 36. record-change.sh crash-safe: append+seq+идемпотентность+recovery (v8 L3-F3) ==="
if bash tests/hooks/test-record-change.sh > /tmp/vibe-rctest.out 2>&1; then
    tail -1 /tmp/vibe-rctest.out
else
    echo "❌ тест record-change упал:"; cat /tmp/vibe-rctest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 37. Провенанс head↔log когерентность через git pre-commit (v8 L3-F3 M1) ==="
if bash tests/hooks/test-provenance-coherence.sh > /tmp/vibe-cohtest.out 2>&1; then
    tail -1 /tmp/vibe-cohtest.out
else
    echo "❌ тест provenance-coherence упал:"; cat /tmp/vibe-cohtest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 38. Провенанс инвариант правки бизнес-поля (v8 L3-F4) ==="
if bash tests/hooks/test-provenance-edit-gate.sh > /tmp/vibe-egtest.out 2>&1; then
    tail -1 /tmp/vibe-egtest.out
else
    echo "❌ тест provenance-edit-gate упал:"; cat /tmp/vibe-egtest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 39. Архив по ссылке + evidence-hash + гейт tasks (v8 L3-F5/F6) ==="
if bash tests/hooks/test-provenance-archive.sh > /tmp/vibe-artest.out 2>&1; then
    tail -1 /tmp/vibe-artest.out
else
    echo "❌ тест provenance-archive упал:"; cat /tmp/vibe-artest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 40. Трёхуровневый контекст: warn на тело архивной фичи в горячем (v8 L4-F1) ==="
if bash tests/hooks/test-context-tiers.sh > /tmp/vibe-cttest.out 2>&1; then
    tail -1 /tmp/vibe-cttest.out
else
    echo "❌ тест context-tiers упал:"; cat /tmp/vibe-cttest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 41. Управляемый /checkpoint: cold-start gate + ротация (v8 L4-F2) ==="
if bash tests/hooks/test-checkpoint.sh > /tmp/vibe-cptest.out 2>&1; then
    tail -1 /tmp/vibe-cptest.out
else
    echo "❌ тест checkpoint упал:"; cat /tmp/vibe-cptest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 42. Бюджет tool-call на фичу: счётчик + нудж (v8 L5-F6) ==="
if bash tests/hooks/test-feature-budget.sh > /tmp/vibe-fbtest.out 2>&1; then
    tail -1 /tmp/vibe-fbtest.out
else
    echo "❌ тест feature-budget упал:"; cat /tmp/vibe-fbtest.out; ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== 43. Единая цифра /audit: объективные метрики провенанс/архив (v8 L5-F5) ==="
if bash tests/hooks/test-audit-health.sh > /tmp/vibe-ahtest.out 2>&1; then
    tail -1 /tmp/vibe-ahtest.out
else
    echo "❌ тест audit-health упал:"; cat /tmp/vibe-ahtest.out; ERRORS=$((ERRORS + 1))
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
