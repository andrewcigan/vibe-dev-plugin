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

- **Три уровня, а не два (решение владельца 2026-09-03).** Верхний уровень работы —
  архитектура, план, детализация, критика, аудит — идёт на **Fable 5.1**; она рассуждает,
  но кода не пишет. Написание кода — **Opus 5**, и только когда всё расписано детально.
  Сбор сырья, сортировка, слияние — **Sonnet 5**.
- **Почему так.** Это не догадка: Anthropic измерила связку «исполнитель Opus 5 с советником
  Fable 5.1» как самую точную из проверенных конфигураций, и отдельно описала образец
  «крупные модели планируют, мелкие исполняют». Источники и цитаты —
  `_internal/plans/v9-research-digest.md`.
- **Усилие: max у ключевых ролей** (архитектор, кодер, аудитор, критики), **ступень ниже —
  у рутинных** (сбор источников, сортировка, слияние). Решение владельца: экономить надо,
  но не в ущерб тому, где цена ошибки высока.
- **Модель — алиасы** `fable`/`opus`/`sonnet`, не полные идентификаторы: обновление модели
  не требует правок реестра. Алиас `opus` с версии движка 2.1.219 указывает на Opus 5.
- **Веер задаёт `model` явно** — субагент никогда не наследует модель главной сессии молча.

## Таблица (источник истины — сверяется self-check)

| Агент | Что делает | Модель | Усилие | read-only |
|---|---|---|---|---|
| architect | V0/детальная архитектура, TOC-bottleneck | fable | max | — |
| business-interviewer | бизнес-интервью → CLAUDE.md/domain-rules | fable | max | — |
| dev-planner | wave-план, feature_list | fable | max | — |
| stack-advisor | выбор стека под bottleneck | fable | max | — |
| idea-generator | генерация идей (2 раунда) | fable | max | — |
| design-handoff-builder | бриф для Claude Design (C.R.O.P.) | fable | max | — |
| data-model-reviewer | критик модели данных (fresh, не соглашается) | fable | max | да |
| idea-critic | long-list идей → critique → отсев | fable | max | — |
| user-perspective-critic | top-down критика глазами пользователя | fable | max | да |
| stage-verifier | верификация перехода этапов | fable | max | да |
| evaluator-agent | внешний оценщик харнеса (7-tuple) | fable | max | да |
| browser-tester | e2e через Playwright, читает PNG глазами | fable | max | да |
| implementer | реализация фичи (TDD) — кодовая роль | opus | max | — |
| synthesizer | merge параллельных субагентов | sonnet | high | — |
| reordering-agent | DAG-пересортировка секций | sonnet | high | — |
| test-researcher | инженерная перспектива тестов | sonnet | high | да |
| github-researcher | поиск/разбор GitHub-репозиториев | sonnet | high | — |
| market-researcher | анализ рынка и конкурентов | sonnet | high | — |
| best-practices-researcher | лучшие практики проблемных классов | sonnet | high | — |
| prototype-builder | HTML/CSS-прототип под user stories | sonnet | high | — |
| validation-sample-builder | валидационная выборка 50-100 + ground truth | sonnet | high | — |
| idea-validator | валидация бизнес-модели Top-3 | sonnet | high | — |
| stuck-protocol-handler | stuck-протокол (LLM-кворум) | sonnet | high | — |
| marketing-launch-preparer | пакет запуска (FULL) | sonnet | high | — |

Итог: **12 fable** (архитектура / план / критика / аудит) + **1 opus** (написание кода) + **11 sonnet** (сбор сырья и рутина).

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
