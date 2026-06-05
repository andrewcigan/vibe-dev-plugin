# Changelog

## v6.1.0 (2026-06-05) — Публичный релиз: обезличивание + онбординг

Подготовка к публичному распространению. Плагин обезличен (убрано всё личное — username/почта автора, имена реальных проектов клиентов, личные пути, ссылки на личный портрет), добавлен онбординг под нового пользователя. Каркас и 19 механизмов v6.0 по сути не менялись.

### Обезличивание + gate (механизм)
- Все shipped-файлы очищены от приватных данных: имена реальных проектов → обобщённые примеры (уроки сохранены), личные пути → нейтральные, коды внутреннего баг-трекинга убраны. Автор в манифесте — публичное имя по выбору пользователя.
- НОВЫЙ механизм: `scripts/check-no-personal-data.sh` + `tests/hooks/test-no-personal-data.sh` (TDD) — grep-gate в self-check (раздел 17): приватные данные в shipped → self-check падает (**block**). Трассировка: **20 механизмов**.
- Удалён мёртвый `scripts/install-hooks.sh`.

### Онбординг (новая фича)
- `/setup` — интервью из 6 простых вопросов (роль, пишешь ли код, уровень ответов, терпимость к терминам, что строишь, язык) → портрет `~/.vibe-dev/portrait.md`.
- Механизмы стиля читают портрет: язык-ловец (`clarity-detector.sh`) берёт уровень `jargon_tolerance` (high — термины и краткие развилки не подсвечивает, medium — ядро жаргона, low — строго; человеко-дни ловит всегда); формат развилок (`decision-format.md`) — простой язык непрограммисту, краткий технический список технарю. «Что теряешь» + рекомендация — на любом уровне.
- Без портрета — безопасный нейтральный дефолт (medium). `/new-project` (Шаг 0) предлагает `/setup` при первом запуске.

### Проверки
- self-check 17/17 (включая новый gate 7/7), `plugin validate --strict` passed, 8 наборов хук-тестов целы.

## v6.0.0 (2026-06-05) — Enforcement из текста в механизм

После аудита всех ~20 реальных проектов v5 (12 ретроспектив + ~150 memory + 6 error-journal, 6-агентный разбор → `docs/v5-coverage-audit-2026-06-05.md`) перенесён enforcement из текста в проверяемые механизмы. **19 механизмов** в таблице трассировки (`docs/traceability.md`), у каждого 3 атрибута (где / чем enforce / что при обходе), self-check на полноту.

### Hooks из коробки (авто-загрузка hooks.json, Claude Code v2.1+)
- Единые диспетчеры на 6 событий: PreToolUse, PostToolUse, Stop, UserPromptSubmit, SessionStart, MessageDisplay. Контракт верифицирован (`docs/hooks-contract-verified-2026-06-03.md` + живая проверка на движке 2.1.161, баг Stop найден и починен).
- Общая библиотека `hooks/lib/hook-io.sh` (правильные коды: stdout-JSON additionalContext/displayContent, не stderr; permissionDecision:deny для block).
- Профили строгости minimal/standard/strict; version-awareness (живые проекты не форсятся) + `/upgrade-project`.

### Механизмы (что реально enforce'ится)
- **UI-evidence gate** — UI→passing без user-evidence = block (закрывает B2/feat-204).
- **Критика-до-реализации (H7)** + **ревью модели данных** — M/L-фича требует `docs/test-strategy.md`, data-фича — `docs/data-model-review.md` (агент `data-model-reviewer`).
- **bulk-API gate**, **WIP=1** (git pre-commit), **concurrent-write** (advisory).
- **Stop-intent (H19)** — обещание действия без tool_use = block. **Handoff loop (H6)** — cold-start чеклист + детекция пропуска.
- **Анти-залипание ×2** — стоп-сигнал пользователя (UserPromptSubmit) + повтор падающих Bash (PostToolUse).
- **hookify** — «не делай X» от пользователя → block/warn-правило без кода.
- **Смена-модели без smoke** → warn про изменение контракта (реальный кейс: 3 дня обрывов после замены модели).
- **Vendor-research gate** — integration-фича без `docs/research/*.md` = block.
- **Язык-ловец (MessageDisplay)** — жаргон/развилка-без-«что теряешь»/человеко-дни → лог `.harness/clarity-violations.log` + флаг на экране (честно display-only: детектор+метрика, НЕ enforcement модели) + `rules/decision-format.md`.

### Честно осталось дисциплиной (не механизм)
integration-smoke / verify-на-реальном-пути, агент-сам-не-в-терминал, тест-реалистичность — труднее мехнизировать. `feature`→Workflow — first-use на первом боевом. Harness-observability (сигнал наружу) — кандидат v6.1.

### Тесты
8 наборов хук-тестов (PreToolUse 33 · Stop 12 · UserPrompt 19 · SessionStart 9 · PostToolUse 14 · user-rules 11 · model-swap 9 · clarity 11) + self-check плагина + `plugin validate`. Все зелёные. ⏳ Живая сверка проводки PostToolUse + MessageDisplay — при первом старте сессии (новые события).

> id плагина остаётся `vibe-dev-v5` (внутренний идентификатор — от него зависят имена команд и установка; меняется ВЕРСИЯ → 6.0.0).

---

## v5.2.0-alpha (2026-05-20) — Bottleneck-first iteration

После валидации v5.1 на 2 реальных проектах (проект голосового ассистента + CRM-проект, 20.05.2026) собрано 14 feedback файлов CRM-проекта + 12 уроков проекта голосового ассистента + 4 ретроспективы + error-journal с 4 детальными разборами. Прошли через 3 независимых ревьюера (Opus max).

**Финальный вердикт ревьюера**: вернуться на доработку. Внедряем только TOP-3 гипотезы из 30 в первой итерации, остальное — после теста на новом проекте.

### Top-3 внедрено (Wave 1)

#### H13 — Переписать SKILL.md (удалить «эпидемию человеко-дней»)

Источник: `skills/dev-plan/SKILL.md` строка 53 содержала «Total: ~12 дней» — плагин сам учил агента нарушению A3 из памяти CRM-проекта.

Изменения:
- `agents/dev-planner.md` — переписан финальный отчёт (количество фичей + size_estimate вместо дней)
- `agents/reordering-agent.md` — все «X days» → S/M/L size_estimate
- `agents/evaluator-agent.md`, `agents/idea-generator.md`, `agents/idea-critic.md`, `agents/idea-validator.md`, `agents/marketing-launch-preparer.md`, `agents/stage-verifier.md` — массовая чистка
- `skills/choose-stack/SKILL.md`, `skills/ship/SKILL.md`, `skills/dev-plan/SKILL.md` — финальные сообщения переписаны по шаблону B (см. `rules/message-finalization.md`)
- `workflow/pipeline.md` — длительность фичи в S/M/L, не часах

Новые rules:
- `rules/no-human-days.md` — запрет с примерами замены
- `rules/message-finalization.md` — обязательные шаблоны A/B/C для финализации
- `rules/check-yourself-first.md` — таблица замены инфра-вопросов на bash-проверки

#### H1 — Pre-write state-transition hook

Источник: главный совет harness-ревьюера. Закрывает B2 (feat-204 объявлен passing без user-acceptance), B4 (data-model-reviewer), C1 (UI без visible outcome).

Новое:
- `schemas/feature-state-transitions.yaml` — единый источник истины state machine
  - 13 states (добавлены `awaiting_research`, `awaiting_reviewer`, `awaiting_demo_milestone`, `awaiting_user_acceptance`)
  - Allowed transitions явно описаны
  - Evidence requirements per transition (UI → обязателен layer_5_user_at)
  - Категории фичи + auto-detect patterns по affected_files
- `hooks/pre-write-state-transition.sh` — Python-валидатор state transitions при Write feature_list.json
  - Strict mode (block) / Learn mode (warn) через `.harness/hook-mode`
  - Особый случай: UI-фича в passing БЕЗ layer_4/5_user evidence = ❌ block (B2 enforcement)
- `templates/feature_list.json` — обновлён schema, добавлены поля `category`, `integration_boundaries`, `evidence` объект

#### H6 — test-strategy.md template с обязательным frontmatter

Источник: feedback feat-001 (правильный шаблон) vs feat-204 (engineering-first без user-risk). Закрывает B3, C1.

Новое:
- `templates/test-strategy.md` — обязательный yaml-frontmatter:
  - `primary_user_risk` (главный риск с точки зрения пользователя)
  - `user_visible_outcome` (что пользователь должен увидеть после успешной фичи)
  - `integration_boundaries` (границы A↔B для smoke-тестов)
  - `domain_invariants_covered` (ссылки на invariants)
- 5-секционный template с обязательной первой секцией «Главный риск с точки зрения пользователя»
- Включает 5-категорийный чек-лист перед passing (E7) + 3 preflight вопроса (E1)

#### H28 — CI на плагин (Quality Gate сам на себя)

- `scripts/check-plugin-self.sh` — self-check скрипт:
  - Запрещённые «человеко-дни» в шаблонах
  - templates/CLAUDE.md (не AGENTS.md) — Claude Code convention
  - Все skills имеют SKILL.md
  - Все agents имеют frontmatter
  - Hooks executable
  - Critical rules файлы существуют
  - JSON/YAML validity

### Дополнительные изменения

- **`AGENTS.md` → `CLAUDE.md`** в templates (Claude Code convention) — пользователь работает 95% в Claude Code, agent-portability убран как design constraint
- **5-layer verification** введён в template `templates/test-strategy.md` (Layer 3 = Integration Smoke) — закрывает H1 voice-worker integration gap
- Обновлены ссылки в `skills/new-project/SKILL.md`

### НЕ внедрено в alpha (отложено)

- **H2 (quality-gate-validator)** — REJECT в исходном виде. В Claude Code SDK нет pre-message hook. Требует радикальной переработки в «metrics + selective validator».
- **H3 (3 preflight вопроса)** — без H2 = декларация. Встроено как **секция** в test-strategy.md template, но без validator enforcement.
- **H4-H30** — после теста v5.2-alpha на новом проекте (~2 недели).

### Migration path для live проектов

- **Проект голосового ассистента** (FAST, feat-04 active) — остаётся на v5.1 до завершения feat-04. После — opt-in миграция.
- **CRM-проект** (FAST, feat-103 next) — пользователь решает. Если контракт горит — оставаться. Иначе — partial adoption (только H13 + H24 без новых hooks).
- **Новый тестовый проект** — стартовать сразу на v5.2-alpha с `.harness/hook-mode = strict`.

### Ожидаемый балл

Реалистичный forecast (по оценке ревьюера): **6.5–7.5** среднее (был 5.4). Авторская оценка 8.6 — переоценка. Главные приросты: State (5→8 через H1), Communication (4→7 через H13), Verification (5→7 через H6).

### Что дальше

После 2 недель использования v5.2-alpha на новом проекте — retrospective + решение по Wave 2 (H4 5-layer, H5 category-aware path, H7 resume-checklist, H8 data-model-reviewer, H10 model-fit-critic, ...).

---

## v5.1.0 (2026-05-19) — Harness-enforcement architecture

### Главный сдвиг
- «Harness — это enforcement, не documentation» — каждый принцип имеет механизм
- 7 подсистем (добавлена Cost & Safety)
- Agent-portability (Claude Code / Codex / Cursor)

### Добавлено (8 must-fix после критики 3 проектов)
- **Pre-flight bulk-API gate** (templates/pre-launch-checklist.yaml + hooks/pre-bash-bulk-api.sh)
  - Закрывает: реальный кейс: $25 + 48h бан Gemini при массовом вызове без проверки квот
- **Concurrent-write lock-table** (templates/tools-allowlist.yaml + hooks/pre-write-concurrent.sh)
  - Закрывает: реальный кейс: $4 + 9 моделей потеряно в проекте с документным ассистентом
- **Stuck auto-trigger** (scripts/stuck-watcher.sh — 30 мин без progress)
  - Закрывает: реальный кейс: 3 часа + 12h compute на skip-pagination в проекте-поисковике по документам
- **Dual critique** (agents/test-researcher.md + agents/user-perspective-critic.md)
  - Закрывает: top-down user perspective из проекта с документным ассистентом
- **domain-rules.yaml** schema (templates/domain-rules.yaml)
  - Закрывает: domain-knowledge gaps в 3 проектах (терминология ниши, отраслевые правила, вендор-специфика)
- **Quality Gate на исходящие** (rules/quality-gate.md + hooks/pre-send-quality.sh)
  - Закрывает: фидбек основателя-непрограммиста «половина слов непонятна» (реальный кейс)
- **Cost-preview** перед bulk LLM call
  - Закрывает: реальный кейс: $13.49 Opus thinking в проекте с документным ассистентом
- **Light/heavy path** в /feature loop
  - Закрывает: bottleneck в самой v5 (Lean-агент валидация)

### Удалено (муда)
- Telegram-дайджест (пользователь работает в Claude Code)
- INBOX.md (избыточен без Telegram)
- BUSINESS-RATIONALE.md (дублировал DECISIONS.md)
- Auto-обновление портрета (заменено на /portrait-review)
- `.planning/` папка (схлопнута в docs/)
- implementation-notes.md отдельным файлом (схлопнут в SESSION.md секцию)
- Sprint contracts (дублировал feature_list.json)
- `.harness/benchmark.json` (автоматизировано через /verify timing)

### Упрощено
- 17 этапов MAX → 10 этапов FULL
- 10 этапов LIGHT → 5 этапов FAST
- 20 команд → 10 команд
- 7 файлов `.planning/` → 0 (в docs/)
- 12-14 файлов в корне проекта → 4 на старте, остальные по факту

### Унаследовано из v4
- Бизнес-интервью + Lean/TOC/6 Sigma язык
- Long-list → critique → parallel research (авторская методология)
- Stuck-протокол с LLM-кворумом (с budget cap)
- Валидационная выборка ≥90%
- Design-handoff через Claude Design
- Marketing-launch (FULL режим)
- Карпати-принципы
- 12 ключевых агентов из 20

### Унаследовано из harness-engineering
- 5 подсистем + AGENTS.md routing ≤200 строк
- WIP=1 + feature_list.json как state-machine
- Cold-start test (5 точных вопросов)
- 5-dim clean-exit
- Memory two-step save invariant
- 15 gotchas каталог
