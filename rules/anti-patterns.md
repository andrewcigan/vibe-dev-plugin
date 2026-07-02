# Anti-Patterns — Что НЕ делать

Каталог анти-паттернов от Карпати + harness-engineering + lessons из реальных проектов.

---

## Из Карпати (на каждый Edit/Write/Bash)

### AP-1: Drive-by Refactoring
«Заодно причесал» → нечитаемый diff, scope leak.
**Защита**: pre-commit hook diff ⊆ feature.affected_files.

### AP-2: Over-abstraction
Strategy pattern на 30 строк там где хватает 2 if'а.
**Защита**: каждая абстракция обоснована ≥3 случаями применения.

### AP-3: Hidden Assumptions
Додумывание параметров без подтверждения.
**Защита**: вытащить assumption в domain-rules.yaml или ask.

### AP-4: Features Beyond the Ask
«Ещё полезное» без запроса.
**Защита**: WIP=1, definition of done строго по фиче.

---

## Из harness-engineering (15 gotchas)

### AP-5: CLAUDE.md разрастается
Дописываем в один файл, пока не станет 1000 строк (lost in the middle).
**Защита**: init.sh stage 5 проверяет ≤200 строк.

### AP-6: Memory index caps fire silently
Длинные записи скрываются. **Защита**: одна строка в индексе, детали в topic-файле.

### AP-7: Priority counterintuitive (local > project > user > org)
Глобальное правило молча перебивается локальным.
**Защита**: тестировать с полным стеком инструкций.

### AP-8: Derivable content в memory
Архитектура, код-паттерны выводятся из репо — не дублировать в memory.
**Защита**: memory только для feedback / project / user / reference типов, не для кода.

### AP-9: Skill description >150 chars
Хвост обрезается, trigger language пропадает.
**Защита**: front-load distinctive trigger phrases.

### AP-10: Fork children must not fork
Рекурсивный fork = экспоненциальный context cost.
**Защита**: enforce «no second-level fork» в agent-runner.

### AP-11: Context builders memoized but not invalidated
Кешируешь — забываешь invalidate → stale data всю сессию.
**Защита**: каждая mutation point явно invalidates cache.

### AP-12: Hook trust all-or-nothing
Один untrusted hook отключает всю extension system.
**Защита**: trust gate at dispatch point.

---

## Из реальных проектов (с конкретной ценой)

### AP-13: Bulk API без research
**Цена**: $25 + 48h блокировки внешнего API + 3 фазы eval переделать
**Защита**: templates/pre-launch-checklist.yaml + hooks/checks/bulk-api.sh (block через dispatch на Bash, читает tool_input.command)

### AP-14: Concurrent writes в один файл
**Цена**: $4 + 9 моделей потеряно
**Защита**: hooks/checks/concurrent-write.sh — session-based advisory warn (взаимное исключение в stateless PreToolUse негарантируемо; настоящая защита — раздельные файлы на воркер + merge)

### AP-15: Opus thinking unconditional
**Цена**: $13.49 vs $0.64 = 21× переплата
**Защита**: cost preview before bulk LLM call

### AP-16: Truncate stored text
**Цена**: accuracy ceiling 60% (root cause)
**Защита**: never truncate at storage, document constraint in domain-rules.yaml

### AP-17: Expected leaked в context
**Цена**: inflated metrics 96% vs реальные 65-74%
**Защита**: leak-check как часть negative-verification

### AP-18: Subprocess+curl для маленьких responses
**Цена**: 10× медленнее
**Защита**: pattern-reuse guard — оцени характеристики копируемого паттерна

### AP-19: skip-pagination для больших offsets
**Цена**: 3 часа сессии + 12h compute
**Защита**: anti-pattern в `CLAUDE.md` проекта (skip > 10000 → cursor через `{_id: $gt}`)

### AP-20: tool_use на средних моделях
**Цена**: ненадёжность в продакшене
**Защита**: state-machine pattern по умолчанию для Sonnet/Haiku

### AP-21: smoke через прод API
**Цена**: contamination данных / billing surprises
**Защита**: tools-allowlist запрещает prod API в тестах, smoke через role-play subagents

### AP-22: Opus через Anthropic Direct
**Цена**: лишние расходы (есть подписка Claude Code)
**Защита**: tools-allowlist forbidden_keys.default: [ANTHROPIC_DIRECT_KEY]

### AP-23: .env в shared scope для всех проектов
**Цена**: secrets ливают между проектами, accidental prod hit
**Защита**: secrets-scope.yaml per-project

### AP-24: Technical A/B пользователю
**Цена**: пользователь не может решить, шум коммуникации
**Защита**: Quality Gate filter на исходящие

### AP-25: Optimization без validation diagnosis
«Метрика 26.7% — давай оптимизировать» (реально была 74%, метрика была сломана).
**Защита**: dual critique включает «валидирован ли diagnosis?»

---

## Class-level Anti-Patterns (структурные)

### CAP-1: Принцип без enforcement
«Quality > Speed» как фраза — пожелание. С Quality Gate filter — инвариант.
**Защита**: `workflow/enforcement-philosophy.md` тест 3 вопросов.

### CAP-2: Множественные источники одного state
v4 имел state.json + STATE.md + CHECKPOINT.md.
**Защита**: один source of truth per данные.

### CAP-3: Скрытое предположение про коммуникацию
«Пользователь увидит уведомление в Telegram». Без замера response rate — это допущение.
**Защита**: метрики communication в /audit.

### CAP-4: Аспирационная архитектура
Документ описывает «как должно быть», без enforcement → деградирует.
**Защита**: workflow/enforcement-philosophy.md.

### CAP-5: Self-bias в аудите
Тот же агент что делал работу её и оценивает → 5/5/5 всегда.
**Защита**: external evaluator-agent с fresh context.

---

## Когда нарушение допустимо

С явным confirm пользователя и записью в SESSION.md:
- AP-4 (Features beyond): если пользователь говорит «заодно добавь Y» — записать как новую фичу feat-X в feature_list.json, не делать мимоходом
- AP-13 (Bulk без research): если research уже сделан в предыдущей сессии — упомянуть ссылку

Без права обхода никогда:
- AP-14 (Concurrent writes) — это data loss риск
- AP-22 (Anthropic Direct без причины) — economic
- AP-23 (Shared secrets scope) — security
- AP-24 (Technical A/B) — это нарушение принципа «решай сам, не перекладывай технические решения на пользователя»

---

## Запись в error-journal

Каждое срабатывание anti-pattern — запись в `error-journal.md`:
```markdown
## err-NNN | <date> | <feature>
**Класс ошибки**: anti_pattern_AP-XX
**Что**: <конкретный сценарий>
**Защита сработала?**: yes/no
**Если нет — почему**: <причина обхода>
```

Это для отслеживания **где enforcement реально работает**, а где остаётся пожеланием.
