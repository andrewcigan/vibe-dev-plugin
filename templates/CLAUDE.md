# CLAUDE.md

[Одно предложение про проект: что и для кого.]

## Startup Workflow

Перед написанием кода:
1. **Подтверди working directory** через `pwd`
2. **Прочитай этот файл** полностью
3. **Прочитай docs/ARCHITECTURE.md** и **docs/PRODUCT.md** для понимания
4. **Прочитай domain-rules.yaml** для специфики ниши
5. **Запусти `./init.sh`** для верификации окружения
6. **Прочитай feature_list.json** для текущего скоупа
7. **Прочитай SESSION.md** для контекста последней сессии
8. **Прочитай error-journal.md** (если есть) для известных граблей
9. Просмотри последние коммиты: `git log --oneline -5`

Если baseline-верификация падает — чинить её ДО добавления нового скоупа.

## Working Rules

- **WIP=1**: одна фича в `active` за раз. Pre-commit hook блокирует diff вне `feature.affected_files`.
- **Verification обязательна**: фича не `passing` пока verification_command не вернул зелёное.
- **Update artifacts**: до конца сессии обновить SESSION.md и feature_list.json.
- **Surgical changes**: не трогать файлы вне `affected_files` текущей фичи.
- **Clean state на выход**: следующая сессия должна сразу запустить `./init.sh`.

## Quality Gate (на каждое сообщение пользователю)

Перед отправкой сообщения проверь:
- Не предлагаю ли я technical A/B (Postgres vs Mongo и т.п.)? → ❌ переписать в формат «беру X, потому что Y для твоего кейса»
- Есть ли термин без объяснения бизнес-влияния? → ❌ переписать
- Молчу ли я о компромиссе (быстро vs качество)? → ❌ озвучить
- Quality > Speed по умолчанию.

## Required Artifacts

- `feature_list.json` — Source of truth для скоупа (включая backlog)
- `SESSION.md` — Текущее состояние с TTL-секциями
- `domain-rules.yaml` — Специфика ниши (структурированно)
- `init.sh` — Standard startup + verification path
- `error-journal.md` — Live-журнал ошибок и фиксов (создаётся при первом «не работает»)
- `.harness/tools-allowlist.yaml` — При первом external API

## Контекст: три уровня (v8 L4-F1)

Держим горячий контекст малым — тогда авто-сжатие («рулетка») почти не запускается, а состояние остаётся под управлением в файлах.

- **Горячий** (всегда в контексте): `CLAUDE.md` ≤200 строк + `SESSION.md` → Current State — только активные+up_next фичи и **индекс архива** (одна строка на завершённую).
- **По требованию** (grep/offset): детали фич, backlog, журнал, `docs/`.
- **Холод** (не грузится): завершённое (тело+доказательство) → `feature_list.archive.json`, история требований → `.harness/provenance-log.jsonl`.

Завершённая фича в горячем = **одна строка-ссылка**, не развёрнутый блок. Разгрузка — `/checkpoint` (управляемо) или `scripts/archive-features.sh`. Pre-commit предупредит (warn), если тело архивной фичи осталось в горячем. Детали — `rules/context-tiers.md`.

## Definition of Done

Фича `passing` только когда ВСЕ:
- [ ] Поведение реализовано
- [ ] Verification 4-layer прошёл: syntax → runtime → e2e → user-reported (если применимо)
- [ ] Evidence записано в feature_list.json
- [ ] Repository restartable через `./init.sh`
- [ ] WIP=1 не нарушено (diff ⊆ affected_files)

## End of Session (5-dim clean-exit)

Перед выходом проверь:
1. **Build** — компилируется без ошибок
2. **Tests** — все тесты зелёные
3. **Progress** — SESSION.md и feature_list.json обновлены
4. **Artifacts** — нет stale temp файлов, .env не в git
5. **Startup** — `./init.sh` запустится с нуля в следующей сессии

Если что-то не закрыто — записать в SESSION.md секцию `# Open Issues`.

## Verification Commands

```bash
./init.sh                          # Full verification (recommended)
# Individual checks
npm install && npm run check && npm test
```

## Escalation

- **Архитектурные решения** → консультируйся с docs/ARCHITECTURE.md, при сомнении — спроси пользователя
- **Неясные требования** → docs/PRODUCT.md
- **3 неуспешных попытки** → `/stuck` (auto-trigger через 30 мин без progress)
- **Scope ambiguity** → перечитай feature_list.json

## Anti-patterns (gotchas из ~/.claude/CLAUDE.md + harness-engineering)

- ❌ Не запускать bulk-API job без research (`/before-bulk` checklist)
- ❌ Не писать параллельно в один файл (tools-allowlist enforces)
- ❌ Не молчать в длинных задачах (>10 мин — отчёт в SESSION.md)
- ❌ Не объявлять «готово» без verification_command
- ❌ Не задавать technical A/B пользователю (Quality Gate enforces)
- ❌ Не truncate stored text (реальный кейс: 5000-char лимит срезал 60% точности в проекте с документным ассистентом)
- ❌ Не дублировать state между файлами

## State-machine over tool_use

На средних моделях (Sonnet/Haiku) tool_use ненадёжен. По умолчанию использовать pattern:
агент ставит статус в БД → watcher-скрипт обрабатывает → результат в БД → агент читает.

См. `.claude/projects/<this>/memory/feedback_*.md` для проектных паттернов.
