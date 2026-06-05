# 7 Подсистем Vibe Dev

Обзор каждой подсистемы с артефактами и enforce-механизмами.

---

## 1. Instructions

**Что**: как агент знает правила проекта.

**Артефакты**:
- `AGENTS.md` (routing, ≤200 строк)
- `domain-rules.yaml` (structured, специфика ниши)
- `docs/ARCHITECTURE.md` (топологический map)
- `docs/PRODUCT.md` (бизнес-смысл)

**Enforcement**:
- `init.sh` Stage 5: ≤200 строк AGENTS.md, иначе exit 1
- `domain-rules.yaml` schema validation
- `/audit` проверяет freshness (last_reviewed)

**Common failures**:
- AGENTS.md разрастается (защита: проверка длины)
- domain-rules.yaml не machine-readable (защита: YAML schema)

---

## 2. State

**Что**: где сохраняется текущее состояние.

**Артефакты**:
- `feature_list.json` — scope + backlog (single source of truth для задач)
- `SESSION.md` — current session + TTL-секции для notes/decisions/questions
- `error-journal.md` — live журнал ошибок (создаётся при первом «не работает»)

**Enforcement**:
- JSON schema валидация feature_list.json
- TTL cleanup в /handoff (notes/questions старше 5 рабочих дней)
- State-machine transitions enforced (passing только через successful verification_command)

**Common failures**:
- Дублирование state между файлами (защита: только эти 3, явные роли)
- SESSION.md забыли обновить (защита: auto-write при ключевых событиях)

---

## 3. Verification

**Что**: как доказываем что фича работает.

**Артефакты**:
- `docs/test-strategy.md` — стратегия per фича
- `eval-samples/` — eval-выборки на развилках + финальная валидационная
- `feature.verification.layer_1..4` — команды для каждого слоя

**Enforcement**:
- /verify enforces 4-layer (syntax + runtime + e2e + user-reported)
- Negative-verification self-check: тест должен упасть на специально сломанном коде
- Passing требует ВСЕ 4 + negative

**Common failures**:
- Тесты «не ленится» проверка отсутствует (защита: negative-gate)
- Expected leaked в test fixtures (защита: leak-check в negative-gate)
- Unit pass = объявляем готово (защита: layer 3 e2e обязателен)
- User reported fail при passing verification = тесты плохие (защита: layer 4 + улучшение тестов)

---

## 4. Scope

**Что**: что мы делаем СЕЙЧАС, что не трогаем.

**Артефакты**:
- `feature.affected_files` (явно перечислены)
- `feature_list.json` WIP=1 invariant
- `feature.size_estimate` (S/M/L) → light/heavy path

**Enforcement**:
- Pre-commit hook: diff ⊆ affected_files (block иначе)
- Active limit: только 1 active в feature_list.json
- /feature command проверяет дубль active

**Common failures**:
- Drive-by refactoring (защита: scope leak block)
- 2+ active фичи (защита: /feature pre-flight check)

---

## 5. Lifecycle

**Что**: вход/выход из сессии, между сессиями.

**Артефакты**:
- `init.sh` (bootstrap-контракт, 5 stages)
- `.harness/cold-start.yaml` (5 вопросов для resume)
- SESSION.md секция `Cold-Start Test (next session)`

**Enforcement**:
- /handoff enforces 5-dim clean-exit (build/tests/progress/artifacts/startup)
- Auto-handoff на tmux detach (scripts/auto-handoff-watcher.sh)
- /resume requires cold-start ≥4/5 score через external evaluator
- Stuck-watcher (scripts/stuck-watcher.sh) auto-trigger /stuck

**Common failures**:
- Забыл /handoff (защита: auto-trigger)
- Следующая сессия не может запустить ./init.sh (защита: 5-dim startup check)
- State разъехался (защита: cold-start test pre-resume)

---

## 6. Learning

**Что**: как ошибки превращаются в уроки.

**Артефакты**:
- `error-journal.md` (live)
- `~/.claude/projects/<this>/memory/feedback_*.md` (promoted lessons)
- `~/.vibe-dev/retrospectives/<date>-<project>/` (милестоун retros)
- `~/CLAUDE.md` (system-wide rules после confirm)

**Enforcement**:
- Auto-trigger записи на ключевые фразы пользователя («не работает», «опять то же», ...)
- Recurrence detection: новая ошибка совпадает с прошлой → alert + блок «было раньше»
- /handoff: предложение promotion с confirm пользователя
- /audit метрика recurrence_rate (цель: 0%)
- domain-rules.yaml freshness check

**Common failures**:
- error-journal становится дампом (защита: hard cap 10 active questions + TTL 5 дней)
- Урок не повлиял на будущее (защита: рекуррентная проверка перед действием)
- domain-rules устарел (защита: freshness alert в /audit)

---

## 7. Cost & Safety (НОВАЯ в v5.1)

**Что**: защита от дорогих/опасных операций.

**Артефакты**:
- `.harness/tools-allowlist.yaml` — git/file/concurrent/cost/secrets policy
- `.harness/pre-launch-checklist.yaml` — gate перед bulk API job
- `.harness/secrets-scope.yaml` — per-project key scope
- `.harness/cost-log.json` — лог расходов
- `.gitignore` — защита от commit секретов

**Enforcement**:
- `hooks/pre-bash-bulk-api.sh` — block bulk без checklist
- `hooks/pre-write-concurrent.sh` — block parallel write в один файл
- Cost preview перед bulk LLM call (>$2 → confirm)
- Per-feature cost cap → auto-pause при превышении
- Forbidden keys (e.g. ANTHROPIC_DIRECT_KEY) — block read

**Common failures**:
- Bulk API без research = $25 ban (защита: pre-launch-checklist)
- Concurrent writes = data loss (защита: lock-table)
- Opus thinking surprise = $13 (защита: cost preview)
- .env закоммичен (защита: .gitignore + git pre-commit grep)
- Smoke через прод API (защита: tools-allowlist policy)

---

## Связи между подсистемами

```
Instructions ←  Lifecycle  → State
       ↓             ↓         ↓
      Scope ←  Verification → Learning
                    ↓
              Cost & Safety
              (всепроникающая)
```

- **Lifecycle** запускает Instructions check на init
- **Instructions** диктует Scope границы
- **Scope** запрещает Verification обходы
- **Verification** питает Learning через error-journal
- **Learning** обновляет Instructions (domain-rules) через promote
- **Cost & Safety** ограничивает все остальные

---

## 5-tuple → 7-tuple оценка

При /audit external evaluator оценивает все 7 (не 5). Bottleneck = подсистема с минимальным баллом. См. `skills/audit/SKILL.md`.
