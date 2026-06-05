# Enforcement Philosophy — Сердце v5.1

> «Harness is enforcement, not documentation.»

После критики v5.0 на 3 реальных проектах главное открытие: **архитектура из документов и принципов деградирует за 2-3 недели**. Работает только то, что физически невозможно нарушить.

---

## Тест для каждого инварианта

Перед тем как добавить любое правило в v5.1, оно должно ответить **на 3 вопроса**:

1. **Где зафиксирован?** (конкретный файл, не «в принципах»)
2. **Какой механизм enforces?** (hook / script / agent / schema validator)
3. **Что произойдёт при попытке обхода?** (block / warn / log)

Если хотя бы одного атрибута нет — это **пожелание, не инвариант**. Удалять или превращать в механизм.

---

## Принципы и их механизмы (полный список)

| # | Принцип | Файл | Механизм | При обходе |
|---|---|---|---|---|
| 1 | Quality > Speed | `rules/quality-gate.md` | Pre-send filter на исходящие сообщения | Сообщение блокируется до переписания |
| 2 | Execute, don't ask на техническом | `cold-start.yaml` + `quality-gate.md` | Filter ловит technical A/B вопросы | Reformulate в business-impact |
| 3 | Top-down user perspective | `agents/user-perspective-critic.md` | Параллельный subagent при /feature heavy path | Mandatory artefact `critique-merge.md` |
| 4 | Бизнес-язык, no jargon | `quality-gate.md` глоссарий | Pre-send check: термин не из словаря | Переписать |
| 5 | WIP=1 | `hooks/pre-commit-scope.sh` | Pre-commit hook: diff ⊆ affected_files | Commit blocked |
| 6 | Surgical changes | Same as WIP=1 + `feature_list.json schema` | affected_files обязательно | Validation error |
| 7 | Agent-portability | `AGENTS.md` (primary, не CLAUDE.md) | `init.sh` проверяет наличие | Bootstrap fail |
| 8 | State-machine over tool_use на средних моделях | `domain-rules.yaml anti_patterns` + `/audit` rule | Audit-check ищет tool_use patterns | Warning + рекомендация |
| 9 | Verification 4-layer | `skills/verify/SKILL.md` | Skill enforces order | Нельзя ставить passing без всех 4 |
| 10 | Negative-verification self-check | Same | Тест должен упасть на специально внесённой ошибке | Verification rejected |
| 11 | API research first | `templates/pre-launch-checklist.yaml` + `hooks/pre-bash-bulk-api.sh` | Hook detect `for X in <large_list>: api_call` → block | Block до passed checklist |
| 12 | Concurrent writes guard | `templates/tools-allowlist.yaml` + `hooks/pre-write-concurrent.sh` | File lock table | Block с suggestion |
| 13 | Cost preview перед bulk | `tools-allowlist.yaml cost section` + `hooks/pre-bash-bulk-api.sh` | Estimate > $2 → confirm | Block без confirm |
| 14 | Stuck auto-trigger | `scripts/stuck-watcher.sh` (background) | Watcher 30/45 мин timers | Auto /stuck |
| 15 | Cold-start test | `templates/cold-start.yaml` + skill resume | External evaluator с fresh context | Continue не разрешён если <4/5 |
| 16 | 5-dim clean-exit | `skills/handoff/SKILL.md` | Auto-trigger на tmux detach | SESSION.md Open Issues |
| 17 | AGENTS.md ≤200 строк | `init.sh` Stage 5 | wc -l + сравнение | init.sh exit 1 |
| 18 | Memory two-step save | `agents/synthesizer.md` discipline | Topic file FIRST, index SECOND | Orphaned file (recoverable) |
| 19 | Priority ordering (local > project > user > org) | OS-level через ~/.claude иерархию | Уже work in Claude Code | N/A |
| 20 | Secrets per-project scope | `templates/secrets-scope.yaml` | Key-vault read проверяет scope | Permission denied |

---

## Anti-pattern: «principle without mechanism»

Если ты собираешься написать в архитектуре фразу типа:

- «Все агенты должны соблюдать X»
- «Это рекомендуется»
- «Обычно мы делаем Y»
- «Принцип Z важен»

— **STOP**. Это не закрытое правило. Либо найди механизм enforcement, либо удали.

---

## Anti-pattern: «декларация == закрытое»

В критике v5.0 это была самая частая ошибка: «execute don't ask — принцип в core». Но что произойдёт если модель напишет «вариант A или вариант B»? **Ничего.** Принцип сам себя не enforces.

В v5.1 каждый такой принцип ОБЯЗАН иметь:
- Конкретный файл с описанием
- Конкретный механизм проверки
- Конкретное последствие нарушения

---

## Failure modes этой философии

### Risk 1: Over-enforcement → пользователь начнёт обходить

Если каждое действие блокируется hook'ом, пользователь начнёт `--force` или просто закроет сессию. **Защита**: каждый hook имеет «escape hatch» с явным confirm. Не deny, а «вы уверены? введите 'я понимаю риск' для продолжения».

### Risk 2: Hooks устаревают → false positives растут

Hook на конкретный pattern (например `for X in list: api_call`) ловит и легитимные случаи. **Защита**: per-hook метрика false positive rate. Если >20% за 2 недели — пересмотреть.

### Risk 3: Сложность системы → когнитивный налог

20 правил с 20 hook'ами = тяжёлый старт. **Защита**: hooks стартуют **только при первом triggered нарушении**, не на пустом проекте. AGENTS.md ≤200 строк — единственная всегда-on проверка.

### Risk 4: Каждый hook сам становится source of bugs

Bash hook упал → блокирует всю работу. **Защита**: hooks should fail-open (если hook сам падает, не блокировать действие, но залогировать в audit log).

---

## Когда правило важнее enforcement

Есть категории где enforcement невозможен:
- **Тон коммуникации** — общая культура, нет grep
- **Top-down user perspective** в дизайне — частично enforced через user-perspective-critic agent, но не на 100%
- **Качество решений** — субъективно

Для них: **внешний evaluator-agent** через `/audit` периодически проверяет. Не реал-тайм, но регулярно.

---

## Главная цитата

Из лекции 1 harness-engineering, перефраз для v5.1:

> «Хороший AGENTS.md важнее апгрейда модели. Hook важнее AGENTS.md. Тест важнее hook.»

Лестница доверия: principle → file → hook → automated test. Чем выше — тем меньше доверия к дисциплине, больше — к механике.
