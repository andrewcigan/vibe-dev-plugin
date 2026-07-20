# AGENTS.md — Vibe Dev v8 Plugin

> Это файл для AI-агентов работающих с самим плагином (не с проектами под управлением плагина).

## Идентичность плагина

Vibe Dev v8 — harness-first pipeline для разработки продуктов от бизнес-идеи. Главный принцип: **«Harness is enforcement, not documentation.»** (id плагина — `vibe-dev`, версия — 8.0.2.)

## Структура

```
vibe-dev/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── CLAUDE.md           ← Мозг плагина (как себя ведут агенты под управлением)
├── README.md / README.ru.md
├── CHANGELOG.md
├── AGENTS.md           ← Этот файл (для агентов разрабатывающих сам плагин)
├── agents/             ← 24 агента (реестр роль→модель→тир — docs/agent-registry.md)
│   ├── stage-verifier.md          ⭐ v8 — adversarial verifier, disallowedTools=Write/Edit
│   ├── data-model-reviewer.md     ⭐ критик модели данных до реализации схемы
│   ├── browser-tester.md          ⭐ v7 — Playwright + чтение PNG «глазами»
│   ├── test-researcher.md / user-perspective-critic.md   ⭐ dual critique
│   └── ... (полный список — docs/agent-registry.md)
├── skills/             ← 29 команд (skills)
│   ├── new-project/ resume/ feature/ verify/ ship/
│   ├── checkpoint/                ⭐ v8 — управляемая фиксация состояния
│   ├── upgrade-project/ patch-projects/   ⭐ v8 — перевод живых проектов (--soft/--dry-run)
│   ├── doctor/ setup/ hookify/ audit/ stuck/ handoff/ end-session/
│   └── architecture/ research/ dev-plan/ … (полный список — ls skills/)
├── rules/              ← 15 правил и анти-паттернов
│   ├── verification-lanes.md      ⭐ evidence по поверхности + logic-lane
│   ├── context-tiers.md           ⭐ v8 — трёхуровневая модель контекста
│   ├── model-tier-routing.md      ⭐ v8 — тир по стадии + эскалация
│   ├── budgets-and-observations.md / headroom-experiment.md  ⭐ v8 (честно discipline)
│   ├── anti-patterns.md           ← anti-patterns с ценой из реальных проектов
│   └── quality-gate.md / decision-format.md / lean-toc-language.md
├── templates/          ← 15 шаблонов проектных файлов
│   ├── CLAUDE.md (проектный роутинг ≤200 строк)
│   ├── feature_list.json + feature_list.archive.json   ⭐ v8 — архив по ссылке
│   ├── change-proposal.md         ⭐ v8 — стадия детализации M/L (P1 US в G/W/T)
│   ├── git-pre-commit.sh          ⭐ независимый backstop + 7 блоков гейтов
│   ├── SESSION.md / domain-rules.yaml / error-journal.md / portrait.md
│   └── cold-start.yaml / init.sh / tools-allowlist.yaml / pre-launch-checklist.yaml
├── schemas/            ← feature_list.schema.json (провенанс-голова) + переходы состояний
├── workflow/           ← Методология
│   ├── methodology.md / pipeline.md / stuck-protocol.md
│   └── enforcement-philosophy.md  ⭐ 3 честных класса: механизм / подсказка / дисциплина
├── docs/
│   ├── traceability.md            ⭐ ЕДИНСТВЕННЫЙ источник числа механизмов (67) и статуса
│   └── agent-registry.md          ⭐ v8 — источник истины роль → модель/тир
├── hooks/              ← Pre-action механизмы (авто-загрузка через hooks.json)
│   ├── hooks.json                 ← авто-регистрация событий при установке
│   ├── dispatch-*.sh              ← 6 диспетчеров (pre-tool-use / post / stop / user-prompt / session-start / message-display)
│   ├── pre-compact.sh             ⭐ v7 — слепок перед сжатием (страховка)
│   ├── lib/hook-io.sh             ← контракт (stdin / permissionDecision / additionalContext) + fail-loud
│   ├── lib/resolve-paths.sh       ⭐ v8 — единый резолвер путей харнеса (STRICT/LENIENT)
│   ├── checks/                    ← 26 проверок (state-transition, bulk-api, config-protect, secret-scan, …)
│   └── pre-commit-scope.sh        ← git-hook, closes WIP=1 enforcement
├── scripts/            ← 16 скриптов
│   ├── check-plugin-self.sh       ⭐ self-check (45 разделов) — главный гейт разработки
│   ├── check-traceability.sh / check-no-personal-data.sh
│   ├── record-change.sh           ⭐ v8 — единственный crash-safe путь записи провенанса
│   ├── checkpoint.sh / archive-features.sh / migrate-provenance.sh   ⭐ v8
│   ├── upgrade-project.sh / patch-projects.sh / install-precommit.sh
│   └── audit-health.sh / journal-audit.sh / stuck-watcher.sh
└── tests/hooks/        ← 37 тестовых наборов + фикстуры (в т.ч. 6 обезличенных боевых)
```

## Текущая версия

**v8.0.2** — провенанс + управляемый контекст поверх enforcement-фундамента (**67 отслеживаемых механизмов**, актуальное число и живой статус — ТОЛЬКО `docs/traceability.md`). Пять линий v8: контракт фронтматтера агентов (model/effort/disallowedTools — enforced-поля движка) и пины по стадиям; стадия детализации M/L-фичи + ленивый backlog; провенанс как event-sourcing (append-only лог + голова-проекция + архив по ссылке с evidence-hash, 7 блоков git pre-commit); управляемый `/checkpoint` с cold-start gate вместо рулетки авто-сжатия + трёхуровневый контекст; evidence на logic-фиче + negative-gate M/L + adversarial fresh-context verifier без права записи. Фундамент v6.2/v7 держится: доказуемая активация хуков, fail-loud, clarity-gate финала, research-гейт архитектуры, closing-mode, секрет-гигиена, config-protect, interrupt-recovery, автопамять. (v8.0.1 — фикс ядра C3 + мягкий перевод живых проектов; v8.0.2 — 4 фикса по первому dogfooding на живом проекте.)

## Как разрабатывать плагин

### Принципы развития

1. **Каждый принцип = механизм** (см. `workflow/enforcement-philosophy.md`): нет 3 атрибутов — не заявлять как enforcement, честно помечать дисциплиной
2. **Число механизмов живёт в одном месте** — `docs/traceability.md`. В прозе (README/CLAUDE.md/plugin.json) — ссылка, не копия числа
3. **Templates минимальны на старте** — 4 файла, остальные при необходимости
4. **Hooks → fail-loud** при собственных багах: краш проверки не блокирует операцию, но громко предупреждает + пишет crash-артефакт `.harness/hook-crashes/` (молчаливый fail-open запрещён — урок бага 2026-06-06)
5. **Новый механизм = строка в traceability + живой прогон с датой** (не «написал скрипт» — «проверил на реальном событии движка»)
6. **Skill descriptions <150 chars** для front-load distinctive trigger language
7. **Agent-portability**: не закладывать Claude-specific вещи в core

### Тестирование плагина

1. `bash scripts/check-plugin-self.sh` — 45 разделов, все PASS обязательны перед коммитом
2. `claude plugin validate . --strict` — зелёный
3. Живой прогон нового сторожа на реальном событии движка (изолированная песочница/проект), дата → в строку traceability
4. Dogfooding-цикл: харнес ставится на живой проект → технический отчёт с находками → точечные фиксы плагина (так родились v8.0.1 и v8.0.2)

### Точки расширения

- Добавить новый skill → `skills/<name>/SKILL.md` с frontmatter
- Добавить агента → `agents/<name>.md` с frontmatter (**обязательно** model + effort; read-only роли — disallowedTools) + строка в `docs/agent-registry.md`
- Добавить hook → `hooks/checks/<name>.sh` + вызов из нужного диспетчера + регистрация события в `hooks/hooks.json`
- Добавить механизм → строка в `docs/traceability.md` (4 колонки, живые ссылки) + тест в `tests/hooks/`
- Добавить anti-pattern → `rules/anti-patterns.md`

## Установка плагина

```bash
# Через marketplace из GitHub
claude plugin marketplace add andrewcigan/vibe-dev-plugin
claude plugin install vibe-dev@vibe-dev

# Или локально (разработка самого плагина)
claude --plugin-dir "/path/to/vibe-dev-plugin"
```

## Verification команды

```bash
# Главный гейт: self-check плагина (45 разделов)
bash scripts/check-plugin-self.sh

# Отдельные проверки
bash scripts/check-traceability.sh        # 3 атрибута + живые ссылки
bash scripts/check-no-personal-data.sh    # обезличенность публичной сборки
claude plugin validate . --strict         # схема плагина

# Тесты сторожей
for t in tests/hooks/test-*.sh; do bash "$t" || echo "FAIL: $t"; done
```

## Контрибьюция

Плагин открыт для фидбэка. Issues с реальными кейсами (что сработало, что нет на ваших проектах) — приветствуются, на них и строится развитие. Также развитие идёт через ретроспективы и dogfooding после реальных проектов.
