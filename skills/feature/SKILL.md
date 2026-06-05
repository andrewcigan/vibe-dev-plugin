---
name: feature
description: Запуск работы над одной фичей (WIP=1). Авто-запускает test-researcher + user-perspective-critic (dual critique), читает domain-rules.yaml, error-journal, выбирает light/heavy path по размеру. Триггеры — "/feature <id>", "берём feat-X", "поехали по feat-Y".
when_to_use: Когда пользователь начинает работу над конкретной фичей из feature_list.json. Это основной рабочий цикл FAST и FULL pipeline.
---

# /feature <feature-id>

Запуск одной фичи. WIP=1 enforced — другую фичу взять нельзя пока эта не passing.

## Pre-flight checks

### Check 1: WIP=1

```bash
# В feature_list.json должна быть ровно одна active или ноль
python3 -c "
import json
d = json.load(open('feature_list.json'))
active = d.get('active')
if active is not None and active != '<this-feature-id>':
    print(f'❌ WIP=1 violated: feat \"{active}\" already active. Закрой её через /verify до passing или /handoff с paused.')
    exit(1)
"
```

Если нарушено — STOP, скажи пользователю.

### Check 2: Feature существует в captured/up_next

Если фича в `done` — спроси пользователя зачем заново.
Если фича в `superseded`/`rejected` — STOP.

### Check 3: Зависимости

```python
# Если feat.dependencies = ["feat-001", "feat-002"] — все должны быть в done
```

Если нет — предложить взять зависимости сначала.

## Размер фичи → light/heavy path

Из feature_list.json смотрим `size_estimate`:

- **S (<1 час, ~30 строк, 1 файл)** → **light path** (syntax + scope check, без dual critique)
- **M (1-4 часа, 30-200 строк)** → **medium path** (single critic + verify)
- **L (1+ день, >200 строк)** → **heavy path** (dual critique + 4-layer verify)

## Main flow (heavy path — для L)

> ⚠️ **Порядок enforced хуком, а не дисциплиной.** `hooks/checks/state-transition.sh` БЛОКИРУЕТ
> перевод M/L-фичи в `active`, пока нет `docs/test-strategy.md` с её id. Поэтому критика идёт
> ПЕРВОЙ (фича остаётся в `up_next`), перевод в `active` — последним. Это test-first: стратегия
> проверки рождается до реализации. Закрывает H7 (раньше критику просили «по-доброму» — и пропускали).

### Шаг 1: Параллельный dual critique (фича ещё в up_next)

Запусти 2 subagent **параллельно** через Task tool (детерминированный вариант через Workflow — Шаг 3-bis):

**Agent 1: test-researcher (engineering critique)**
- Читает: feature description, AGENTS.md, ARCHITECTURE.md, существующий код в affected_files
- Делает: параллельный GitHub-ресёрч «как тестируют похожие фичи»
- Возвращает: 3-7 тестов с verification_commands (1 happy + 2-3 edge + 1-2 error + 1 e2e)

**Agent 2: user-perspective-critic (top-down user perspective)**
- Читает: PRODUCT.md, domain-rules.yaml (особенно invariants, disambiguation_triggers, anti_patterns, target_markets)
- Делает: смотрит на фичу глазами реального пользователя
- Возвращает:
  - Какие сценарии test-researcher НЕ покрыл (но пользователь bы делал)
  - Какие domain-rules invariants не отражены в тестах
  - Top-down вопросы: «оптимизируем по правильной метрике?», «фиксим продукт или тест?», «работает ли при голосовом вводе по-русски?»

### Шаг 2: Synthesizer merge → docs/test-strategy.md (артефакт-gate)

Третий subagent (synthesizer) читает оба выхода и пишет `docs/test-strategy.md`:
- объединённый список тестов; конфликты (engineering X vs user Y) — в пользу user perspective
- **ОБЯЗАТЕЛЬНО упомянуть id фичи** в файле (хук проверяет наличие id — без него active заблокируется)
- final verification_commands → записать в feature_list.json

### Шаг 2-bis: data-model-reviewer (если фича трогает БД-схему)

Если `affected_files` содержит `*/schema/*`, `*/migrations/*`, `prisma/`, `drizzle/`, `supabase/migrations/` ИЛИ `category=data` — **ОБЯЗАТЕЛЬНО** запусти агента `data-model-reviewer` (Opus, fresh context) ПЕРЕД реализацией. Он пишет `docs/data-model-review.md` (недостающие/лишние сущности, упущенные поля, спорные решения, UX-фичи которые врут о связях). Утверждение пользователя по вердикту — gate для старта. Это глобальное правило `~/CLAUDE.md` (модель данных застывает — переделка дороже ревью).

### Шаг 3: Перевести feature в active (хук теперь пропустит)

```python
# feature_list.json
d['active'] = '<feature-id>'
d['features'][f]['state'] = 'active'
d['features'][f]['started_at'] = today
```

Хук пропустит запись, т.к. `docs/test-strategy.md` с id фичи уже существует (Шаг 2). Если хук заблокировал — критика не пройдена, вернись к Шагу 1.

### Шаг 3-bis (опционально): Workflow-оркестрация критиков

Если в среде доступен **Workflow-инструмент** — критику лучше запускать детерминированным скриптом, а не вручную: `parallel([test-researcher, user-perspective-critic]) → synthesizer пишет docs/test-strategy.md`. Преимущество: скрипт спавнит критиков САМ (не «агент решит и пропустит»), barrier на артефакт. ⚠️ Контракт Workflow-инструмента внутри скилла проверить на первом реальном `/feature` (first-use, как Bash-хук). Гарантия H7 в любом случае — хук active-gate (Шаг 3), Workflow лишь усиливает оркестрацию.

### Шаг 4: Pre-launch checklist (если намечается bulk API)

Если в тестах будут массовые API-вызовы:
- Заполнить `.harness/pre-launch-checklist.yaml` (см. templates)
- Без passing checklist — implementation не стартует

### Шаг 5: Negative-verification gate

Для каждой verification_command — test-researcher специально вводит ошибку в код и проверяет что команда падает. Только потом — её записываем как валидную в feature_list.json. Иначе verification — театр.

### Шаг 6: Test-First (Карпати)

Сначала пишем тесты (red), потом implementation (green), потом refactor. Не наоборот.

### Шаг 7: Implementation в worktree (для L размера)

```bash
git worktree add ../worktrees/<feature-id> -b <feature-id>
cd ../worktrees/<feature-id>
# implementer работает здесь
```

Pre-commit hook проверяет: `diff ⊆ feature.affected_files`. Нарушение = block.

### Шаг 8: Periodic updates

Каждые 10 минут или ключевое событие → запись в SESSION.md секцию «Today». Не молчать.

### Шаг 9: /verify (4-layer)

Когда implementation готова — `/verify`. Прохождение всех 4 уровней = можно ставить state=passing.

## Medium / Light path

**Light (S)**:
- Без dual critique
- Тесты: 1 happy + 1 error (минимум)
- Skip negative-verification gate
- Verify: только layer 1 (syntax) + layer 2 (runtime)
- Без worktree, прямо в main

**Medium (M)**:
- Только test-researcher (без user-perspective-critic в параллель — но quick sanity read domain-rules.yaml)
- 3-5 тестов
- Negative-verification gate включен
- Verify: layers 1+2+3

## Stuck protection (защита от залипания)

Background watcher в init.sh запускается. Считает:
- Время без commit
- Время без test pass

Триггеры:
- 30 мин без progress → prompt в SESSION.md
- 45 мин без progress → auto /stuck
- 2 одинаковых fail подряд → auto параллельный subagent на диагностику (без ожидания /stuck)

## Anti-patterns

- ❌ Брать вторую фичу пока эта не passing (WIP=1 enforced)
- ❌ Скипнуть test-researcher для «маленькой» фичи если она L
- ❌ Помечать passing вручную без verification_command
- ❌ Молчать >10 мин в длинной задаче
- ❌ Расширять scope мимоходом («заодно поправлю смежный файл») — pre-commit hook блокирует
