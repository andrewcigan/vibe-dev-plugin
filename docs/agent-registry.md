# Реестр агентов — контракт роль→модель→усилие (v8 L1-F1/F2)

> **Единый источник контракта агентов.** Каждый субагент плагина (`agents/*.md`) обязан нести
> во фронтматтере поля `model`, `effort` и (для read-only ролей) `disallowedTools`. Движок
> Claude Code читает и применяет их (subagents-and-plugins.md). `scripts/check-plugin-self.sh`
> (раздел 4): (1) наличие `model`+`effort` у каждого агента; (2) **сверка роль↔тир — модель
> во фронтматтере обязана совпадать с колонкой «Модель» этой таблицы** (L1-F2). Расхождение
> роняет self-check. Это делает таблицу РЕАЛЬНЫМ источником истины, а не витриной «на доверии».
>
> **Почему единый файл:** менять привязку «роль→модель» при обновлении моделей — одним движением
> здесь (+ фронтматтер), а не искать по коду (решение владельца 2026-07-09, карточка c1).

## Дефолты плагина

- **Усилие: `max` у всех ролей.** Качество приоритетно, лимитов хватает (решение владельца).
  Экономия достигается разделением МОДЕЛЕЙ по роли, не понижением усилия.
- **Модель — алиасы** `opus`/`sonnet` (не полные id): резолвятся в актуальные версии
  (`opus`→Opus 4.8, `sonnet`→Sonnet 5), поэтому обновление модели не требует правок реестра.
- **Fan-out задаёт `model` явно** — субагент в Workflow/Task никогда не наследует модель
  главной сессии молча (pilotfish-правило).

## Контракт тиров (L1-F2)

- **Opus** — планирование / детализация / архитектура / критика / проверка / оценка. Дорогой
  reasoning там, где цена ошибки высока (плохой план, пропущенный дефект, ложная приёмка).
- **Sonnet** — написание кода / исполнение / чтение сырья / механические merge/сортировки.
  Дешёвый исполнитель по детальному плану: главную ошибку («додумал размытый план») ловят
  механизмы harness (4-слойная проверка, границы правок, evidence-гейт, circuit breaker),
  а не ум модели. CLEAR-замер: цена фичи ↓ ~3–4× при той же точности.

## Таблица (источник истины — сверяется self-check)

| Агент | Что делает | Модель | Усилие | read-only |
|---|---|---|---|---|
| architect | V0/детальная архитектура, TOC-bottleneck | opus | max | — |
| business-interviewer | бизнес-интервью → CLAUDE.md/domain-rules | opus | max | — |
| dev-planner | wave-план, feature_list | opus | max | — |
| stack-advisor | выбор стека под bottleneck | opus | max | — |
| idea-generator | генерация идей (2 раунда) | opus | max | — |
| design-handoff-builder | бриф для Claude Design (C.R.O.P.) | opus | max | — |
| data-model-reviewer | критик модели данных (fresh, не соглашается) | opus | max | да |
| idea-critic | long-list идей → critique → отсев | opus | max | — |
| user-perspective-critic | top-down критика глазами пользователя | opus | max | да |
| stage-verifier | верификация перехода этапов | opus | max | да |
| evaluator-agent | внешний оценщик харнеса (7-tuple) | opus | max | да |
| browser-tester | e2e через Playwright, читает PNG глазами | opus | max | да |
| implementer | реализация фичи (TDD) — кодовая роль | sonnet | max | — |
| synthesizer | merge параллельных субагентов | sonnet | max | — |
| reordering-agent | DAG-пересортировка секций | sonnet | max | — |
| test-researcher | инженерная перспектива тестов | sonnet | max | да |
| github-researcher | поиск/разбор GitHub-репозиториев | sonnet | max | — |
| market-researcher | анализ рынка и конкурентов | sonnet | max | — |
| best-practices-researcher | лучшие практики проблемных классов | sonnet | max | — |
| prototype-builder | HTML/CSS-прототип под user stories | sonnet | max | — |
| validation-sample-builder | валидационная выборка 50-100 + ground truth | sonnet | max | — |
| idea-validator | валидация бизнес-модели Top-3 | sonnet | max | — |
| stuck-protocol-handler | stuck-протокол (LLM-кворум) | sonnet | max | — |
| marketing-launch-preparer | пакет запуска (FULL) | sonnet | max | — |

Итог: **12 opus** (план/критика/проверка) + **12 sonnet** (код/чтение/рутина).

**read-only (`disallowedTools: Write, Edit, MultiEdit, NotebookEdit`):** роли, чей продукт —
суждение, а не правка кода (критики / верификатор / оценщик / браузер-тестировщик / test-researcher).
Явный запрет записи — гарантия «проверяющий не подгонит код под свой вывод» (несёт L5-F4).

## История изменений тиров

- **L1-F2 (Волна 2, 2026-07-10) — применено:** `implementer` opus→**sonnet** (главное c1: дешёвый
  исполнитель по детальному плану); `evaluator-agent`, `stage-verifier`, `user-perspective-critic`,
  `idea-critic` sonnet→**opus** (проверка/критика — важное стороннее суждение).
- **L1-F4 (discipline-дополнение):** security/defensive-роль роутить на Opus, не на свежайшую
  frontier (её safety-классификаторы отказывают в benign defensive-работе mid-task — урок pilotfish).
  Честно discipline: у плагина нет выделенного security-агента; правило в `rules/` + предупреждение
  model-swap-guard. См. traceability.
