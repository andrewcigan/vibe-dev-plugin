# Реестр агентов — контракт роль→модель→усилие (v8 L1-F1)

> **Единый источник контракта агентов.** Каждый субагент плагина (`agents/*.md`) обязан нести
> во фронтматтере поля `model`, `effort` и (для read-only ролей) `disallowedTools`. Наличие
> `model`+`effort` у каждого агента проверяет `scripts/check-plugin-self.sh` (раздел 4) — файл
> без них роняет self-check. Это не документация «на доверии» — движок Claude Code читает и
> применяет `model`/`effort`/`disallowedTools` из фронтматтера субагента (subagents-and-plugins.md).
>
> **Почему единый файл:** менять привязку «роль→модель» при обновлении моделей — одним движением
> здесь и во фронтматтере, а не искать по коду (решение владельца 2026-07-09, карточка c1).

## Дефолты плагина

- **Усилие: `max` у всех ролей.** Качество приоритетно, лимитов хватает (решение владельца).
  Экономия достигается разделением МОДЕЛЕЙ по роли, не понижением усилия.
- **Модель — алиасы** `opus`/`sonnet` (не полные id): резолвятся в актуальные версии
  (`opus`→Opus 4.8, `sonnet`→Sonnet 5), поэтому обновление модели не требует правок реестра.
- **Fan-out задаёт `model` явно** — субагент в Workflow/Task никогда не наследует модель
  главной сессии молча (pilotfish-правило).

## Таблица (фактическое состояние)

| Агент | Что делает | Модель | Усилие | read-only (disallowedTools) |
|---|---|---|---|---|
| architect | V0/детальная архитектура, TOC-bottleneck | opus | max | — |
| business-interviewer | бизнес-интервью → CLAUDE.md/domain-rules | opus | max | — |
| dev-planner | wave-план, feature_list | opus | max | — |
| stack-advisor | выбор стека под bottleneck | opus | max | — |
| idea-generator | генерация идей (2 раунда) | opus | max | — |
| design-handoff-builder | бриф для Claude Design (C.R.O.P.) | opus | max | — |
| implementer | реализация фичи (TDD) | opus | max | — |
| data-model-reviewer | критик модели данных (fresh, не соглашается) | opus | max | **да** |
| browser-tester | e2e через Playwright, читает PNG глазами | opus | max | **да** |
| stage-verifier | верификация перехода этапов | sonnet | max | **да** |
| evaluator-agent | внешний оценщик харнеса (7-tuple) | sonnet | max | **да** |
| test-researcher | инженерная перспектива тестов | sonnet | max | **да** |
| user-perspective-critic | top-down критика глазами пользователя | sonnet | max | **да** |
| idea-critic | long-list идей → critique → отсев | sonnet | max | — |
| idea-validator | валидация бизнес-модели Top-3 | sonnet | max | — |
| synthesizer | merge параллельных субагентов | sonnet | max | — |
| reordering-agent | DAG-пересортировка секций | sonnet | max | — |
| github-researcher | поиск/разбор GitHub-репозиториев | sonnet | max | — |
| market-researcher | анализ рынка и конкурентов | sonnet | max | — |
| best-practices-researcher | лучшие практики проблемных классов | sonnet | max | — |
| prototype-builder | HTML/CSS-прототип под user stories | sonnet | max | — |
| validation-sample-builder | валидационная выборка 50-100 + ground truth | sonnet | max | — |
| stuck-protocol-handler | stuck-протокол (LLM-кворум) | sonnet | max | — |
| marketing-launch-preparer | пакет запуска (FULL) | sonnet | max | — |

**read-only (`disallowedTools: Write, Edit, MultiEdit, NotebookEdit`):** роли, чей продукт —
суждение, а не правка кода (критики / верификатор / оценщик / браузер-тестировщик). Явный запрет
записи — гарантия «проверяющий не подгонит код под свой вывод» (несёт L5-F4).

## Целевые изменения в L1-F2 (Волна 2) — ЕЩЁ НЕ применены

Разделение моделей по роли (карточка c1) переставит тиры и обновит эту таблицу:
- `implementer` (кодовая роль) → **sonnet** (сейчас opus): дешёвый исполнитель по детальному
  плану; главную ошибку ловят механизмы harness, не ум модели (CLEAR-замер: цена фичи ↓ ~3–4×).
- `evaluator-agent`, `stage-verifier` (проверка/оценка reasoning) → **opus**.
- `user-perspective-critic` (критик, важное стороннее мнение) → **opus**.
- Security/defensive-роль → **opus**, не свежайшая frontier (L1-F4, урок pilotfish).

После L1-F2 self-check будет сверять роль↔тир по этой таблице (сейчас проверяется только
наличие полей). До применения L1-F2 таблица отражает фактическое состояние файлов.
