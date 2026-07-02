# Vibe Dev Pipeline

Два режима: FAST (5 этапов) и FULL (10 этапов).

---

## FAST (5 этапов)

Для внутренних инструментов, простых MVP, Telegram-ботов, понятного стека.

### Этап 1: /new-project
- **Что**: бизнес-интервью + bootstrap 4 файлов (CLAUDE.md, feature_list.json, SESSION.md, domain-rules.yaml)
- **Critic**: business-interviewer (Opus)
- **Артефакты**: 4 файла + git init + .gitignore
- **Gate**: домен-rules.yaml заполнен (main_function, target_markets, invariants ≥2)
- **Длительность**: 30-60 минут

### Этап 2: /architecture + /choose-stack
- **Что**: V0 архитектура с TOC bottleneck-анализом + выбор стека по quality > speed
- **Агенты**: architect (Opus), stack-advisor (Opus)
- **Артефакты**: `docs/ARCHITECTURE.md`, `docs/PRODUCT.md`, `init.sh`, `.harness/tools-allowlist.yaml`
- **Gate**: компонентов ≤10 (Simplicity First), bottleneck явно указан, tech-defaults применены
- **Длительность**: 1-2 часа

### Этап 3: /design-handoff (опционально)
- **Когда**: если есть UI
- **Агент**: design-handoff-builder (Opus)
- **Артефакты**: `docs/design-brief.md` для Claude Design
- **Gate**: пользователь подтвердил результат от Claude Design

### Этап 4: /feature loop (повторяется per фича)
- **Что**: WIP=1, dual critique (engineering + user-perspective), Test-First, implement
- **Агенты**: test-researcher (Sonnet), user-perspective-critic (Sonnet), synthesizer (Sonnet), implementer (Opus)
- **Артефакты**: `docs/test-strategy.md`, `eval-samples/`, code + tests
- **Gate**: /verify 4-layer + negative-verification self-check
- **Длительность**: per feature (S / M / L по size_estimate (см. rules/no-human-days.md))

### Этап 5: /ship
- **Что**: validation sample ≥90% + retrospective + final commit
- **Агент**: validation-sample-builder (Sonnet)
- **Артефакты**: `docs/validation-sample.md`, `~/.vibe-dev/retrospectives/...`
- **Gate**: validation rate ≥90%

---

## FULL (10 этапов)

Для продуктов на рынок.

### Этапы 1-3: Идеи и валидация
1. /new-project
2. /expand-ideas (R1 + R2) — `idea-generator` (Opus)
3. /critique (long-list → отсев) — `idea-critic` (Sonnet)

### Этап 4: /validate
- **Агент**: idea-validator (Sonnet)
- **Артефакт**: `docs/validation.md`
- **Gate**: validation score ≥60

### Этап 5: /research (параллельный)
- **Агенты**: github-researcher + market-researcher + best-practices-researcher (параллельно через worktrees)
- **Артефакты**: `docs/research/*`

### Этапы 6-7: Архитектура и прототип
6. /architecture + /prototype — V0 + HTML clickable
7. /choose-stack + /detail-architecture + reordering

### Этап 8: /design-handoff (обязательно если UI)
- Бриф для Claude Design

### Этап 9: /dev-plan + /feature loop
- **Агент**: dev-planner (Opus) — волны + DAG
- Затем итеративно /feature
- **/validation-sample** строится здесь — `validation-sample-builder` (50-100 сценариев)

### Этап 10: /ship + /marketing-launch
- Final validation ≥90%
- **/marketing-launch** — `marketing-launch-preparer` (Sonnet)
- Артефакты: `docs/marketing-launch/` (14 файлов)

---

## Stuck-protocol (auto-trigger на любом этапе)

См. `workflow/stuck-protocol.md` и `skills/stuck/SKILL.md`.

Триггеры:
- 45 мин без commit/test-pass → auto `/stuck`
- 3 неуспешных /verify
- 2 одинаковых ошибки подряд (recurrence)
- Manual: пользователь сказал «в тупике»

---

## Pipeline-этапы как граф (FULL)

```
1. /new-project
   ↓
2. /expand-ideas (R1) → 3. R2 → 4. /critique → 5. /validate
   ↓
6. /research (parallel: github + market + best-practices)
   ↓
7. /architecture → 8. /prototype → 9. /choose-stack → 10. /detail-architecture
   ↓
11. /design-handoff (если UI)
   ↓
12. /dev-plan (waves + DAG)
   ↓
13. /validation-sample (50-100 scenarios)
   ↓
14. /feature loop (WIP=1, dual critique, /verify 4-layer)
   ↓
15. /ship (validation ≥90%)
   ↓
16. /marketing-launch (FULL only)
   ↓
17. /handoff final
```

---

## Общие правила пайплайна

1. **State обновляется** после каждого этапа (SESSION.md + feature_list.json)
2. **Stuck-протокол** может сработать на любом этапе автоматически
3. **/audit** запускать после каждого крупного этапа (или раз в неделю)
4. **/handoff** на каждое закрытие сессии — обязательно (auto-trigger на tmux detach)
5. **Quality Gate** на каждое сообщение пользователю — всегда
6. **Cost preview** перед каждым bulk job — всегда

---

## Mode selection

При /new-project — система определяет автоматически по 5 вопросам:
- Для рынка? +3 → FULL
- Пользователей >100? +2
- Нужен маркетинг-запуск? +3
- Бюджет < $50/мес? +2 → FAST
- Нужно за 1-2 дня? +3 → FAST
- Один разработчик? +1 → FAST

**Порог**: ≥4 баллов → FULL. Иначе FAST.

**Финальное решение за пользователем** (один вопрос: «по моей оценке X, согласен?»).

---

## Переключение режимов

- **FAST → FULL**: до /feature loop. Добавляются этапы ideas/critique/research/prototype/validation-sample/marketing-launch.
- **FULL → FAST**: до /architecture. Пропускаются ideas/research/prototype/marketing.
- После начала /feature — переключение запрещено (consistency).
