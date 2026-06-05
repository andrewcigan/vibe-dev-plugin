# Memory stays in sync with reality

> Источник: память проекта голосового ассистента `feedback_memory_stays_in_sync_with_reality.md` (E6). 
> ⚠ КРИТИЧНО — нарушение приводит к расхождению между cold-start view и реальностью.

При любом закрытии фичи (`passing`) или handoff сессии — **явно** обновить `project_*.md` файлы в `~/.claude/projects/<slug>/memory/`.

Auto-memory триггер срабатывает **нерегулярно** — не полагаться на него.

## Триггеры обязательного обновления project_*.md

- Закрытие фичи в `passing` (Definition of Done)
- Любой `/handoff` / `/end-session`
- Изменение архитектурного решения, стека, MVP path
- Открытие новой основной фазы

## Что обновлять (5 минут)

```
Pipeline stage: "X / 10 — <словесное описание>"
Активные фичи: список с (PASSING / active / blocked / paused)
Next command: <команда для следующей сессии>
MVP path: <последовательность оставшихся фич>
Архитектурные решения за сессию: список с одной строкой каждое
```

## Не путать

- **feedback_*.md** — это **уроки** (immutable, append-only)
- **project_*.md** — это **состояние** (mutable, всегда отражает «сейчас»)

## Проверочный вопрос перед закрытием сессии

> «Если я сейчас сделаю /resume — увидит ли cold-start agent ту же картину что я вижу в SESSION.md?»

Если в memory несовпадение — обновить.

## Сигналы что снова в ловушке

- Сессия завершилась без явного Edit на `project_*.md`
- `Last Updated` в project memory старше последнего коммита более чем на 2 часа
- В feedback'ах за сегодня упоминаются feat-X+N, а project memory ещё на feat-Y < N
- Cold-start вопросы в SESSION.md и project memory дают разные ответы

## Enforcement в v5.2

- Skill `/end-session` имеет step «Memory sync» в начале — обязательное условие
- Bash скрипт `scripts/end-session.sh` проверяет mtime project_*.md, ругается если старше 1 часа
- Будущий механизм (v5.3+): `Stop` hook проверяет sync автоматически

## Связано

- `skills/end-session/SKILL.md` — оркестрирует
- `skills/handoff/SKILL.md` — низкоуровневый handoff
- Память проекта голосового ассистента: `feedback_memory_stays_in_sync_with_reality.md`
