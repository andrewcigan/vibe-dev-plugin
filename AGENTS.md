# AGENTS.md — Vibe Dev v6 Plugin

> Это файл для AI-агентов работающих с самим плагином (не с проектами под управлением плагина).

## Идентичность плагина

Vibe Dev v6 — harness-first pipeline для разработки продуктов от бизнес-идеи. Главный принцип: **«Harness is enforcement, not documentation.»** (id плагина — `vibe-dev`, версия — 6.1.0.)

## Структура

```
vibe-dev/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── CLAUDE.md           ← Мозг плагина (как себя ведут агенты под управлением)
├── README.md
├── CHANGELOG.md
├── AGENTS.md           ← Этот файл (для агентов разрабатывающих сам плагин)
├── agents/             ← 12 агентов
│   ├── test-researcher.md         ⭐ NEW в v5.1
│   ├── user-perspective-critic.md ⭐ NEW в v5.1
│   ├── evaluator-agent.md         ⭐ NEW в v5.1
│   └── ... (унаследовано из v4)
├── skills/             ← 10 команд (skills)
│   ├── new-project/
│   ├── resume/
│   ├── feature/
│   ├── verify/
│   ├── handoff/
│   ├── audit/
│   ├── stuck/
│   ├── ship/
│   ├── lessons/
│   └── trim/
├── rules/              ← Правила и анти-паттерны
│   ├── karpathy-principles.md
│   ├── anti-patterns.md       ← 25 anti-patterns с ценой из реальных проектов
│   ├── lean-toc-language.md   ← Словарь
│   ├── quality-gate.md        ⭐ Фильтр сообщений
│   └── subsystems.md          ← Обзор 7 подсистем
├── templates/          ← Шаблоны проектных файлов
│   ├── AGENTS.md (проектный)
│   ├── feature_list.json
│   ├── SESSION.md
│   ├── domain-rules.yaml      ⭐ Structured YAML
│   ├── init.sh
│   ├── cold-start.yaml
│   ├── tools-allowlist.yaml   ⭐ NEW
│   ├── pre-launch-checklist.yaml ⭐ NEW
│   └── error-journal.md
├── workflow/           ← Методология
│   ├── methodology.md
│   ├── pipeline.md
│   ├── stuck-protocol.md
│   └── enforcement-philosophy.md ⭐ NEW — главный документ
├── hooks/              ← Pre-action механизмы (авто-загрузка через hooks.json)
│   ├── hooks.json                  ⭐ v6 — авто-регистрация PreToolUse при установке
│   ├── dispatch-pre-tool-use.sh    ⭐ v6 — единый диспетчер (stdin JSON, профили, роутинг)
│   ├── lib/hook-io.sh              ⭐ v6 — контракт (stdin / permissionDecision / additionalContext)
│   ├── checks/state-transition.sh  ⭐ UI→passing без user-evidence = block
│   ├── checks/bulk-api.sh          ⭐ массовый внешний API без checklist = block
│   ├── checks/concurrent-write.sh  ⭐ advisory warn: гонка записи в shared-файл
│   └── pre-commit-scope.sh         ⭐ git-hook, closes WIP=1 enforcement
└── scripts/
    ├── stuck-watcher.sh            ⭐ детектор залипания
    └── auto-handoff-watcher.sh
```

## Текущая версия

**v6.1.0** — публичный релиз: enforcement из текста в механизм (20 механизмов) + онбординг (`/setup`) + gate обезличенности, после аудита ~20 реальных проектов v5. (v5.x — первая harness-enforcement версия после критики v5.0; 8 must-fix механизмов.)

## Как разрабатывать плагин

### Принципы развития

1. **Каждый принцип = механизм** (см. `workflow/enforcement-philosophy.md`)
2. **Templates минимальны на старте** — 4 файла, остальные при необходимости
3. **Hooks → fail-open** при собственных багах (audit log, не block операцию)
4. **Skill descriptions <150 chars** для front-load distinctive trigger language
5. **Agent-portability**: не закладывать Claude-specific вещи в core

### Тестирование плагина

Тестовая методика:
1. Применить v6 на новом проекте пользователя
2. Замерять метрики по `baseline-template.md`
3. Сравнить с baseline (без v6)
4. Итерация: v6.1 закрывает дыры найденные на тестовом проекте

### Точки расширения

- Добавить новый skill → `skills/<name>/SKILL.md` с frontmatter
- Добавить агента → `agents/<name>.md` с frontmatter (model, tools)
- Добавить hook → `hooks/<name>.sh` + регистрация в `~/.claude/settings.json`
- Добавить anti-pattern → `rules/anti-patterns.md`
- Добавить gotcha → `rules/subsystems.md` соответствующая секция

## Установка плагина

```bash
# Через локальный marketplace
claude --plugin-dir "/path/to/vibe-dev-plugin"

# Или зарегистрировать
echo '{"name":"vibe-dev","source":"directory","path":"/path/to/vibe-dev-plugin"}' \
  >> ~/.claude/plugins/known_marketplaces.json

# Включить
claude plugin enable vibe-dev@vibe-dev
```

## Verification команды

```bash
# Проверить структуру
find . -name "*.md" | wc -l    # должно быть >25
find . -name "*.sh" -executable | wc -l  # все hooks executable

# Linting
shellcheck hooks/*.sh
yamllint templates/*.yaml

# Прогон тестовой /new-project (manual)
cd /tmp/test-project
ln -s /path/to/vibe-dev-plugin plugin
# Симулировать создание проекта
```

## Контрибьюция

Плагин открыт для фидбэка. Issues с реальными кейсами (что сработало, что нет на ваших проектах) — приветствуются, на них и строится развитие. Также развитие идёт через retrospectives после реальных проектов.
