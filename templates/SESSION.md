# Session Log

> Этот файл — single source of truth для текущей сессии и handoff в следующую. 
> Перезаписывается при `/handoff`. Секции с TTL автоматически чистятся.

## Current State

**Last Updated**: YYYY-MM-DD HH:MM
**Session ID**: [optional]
**Active Feature**: [feat-XXX — название] (state: `active`)
**Mode**: FAST / FULL
**Sprint Day**: [N из планируемых]

---

## Today (this session)

### What's Done
- [x] [Завершённая задача]

### What's In Progress
- [ ] [Текущая задача]
  - Что конкретно делаю: [...]
  - Блокеры: [если есть]

### What's Next
1. [Следующее действие]
2. [Дальнейшее]

---

## Implementation Notes (TTL 5 рабочих дней)

> Тактические решения по ходу активной фичи. Автоматически удаляются через 5 рабочих дней.
> При `/handoff` важные → продвигаются в `docs/decisions/` или `feedback_*.md` в memory.

### Design Decisions (неоднозначности в спеке)
- [Решение]: [контекст, что выбрали, почему]

### Intentional Deviations (отклонения с обоснованием)
- [Отклонение]: [от чего, почему]

### Alternatives Considered (что отвергли)
- [Альтернатива]: [почему не взяли]

### Open Questions (max 10 active, TTL 5 рабочих дней)
- [ ] [Вопрос]: [контекст; для кого — пользователь / архитектор / инженер]
  - Записан: YYYY-MM-DD
  - Эскалация если не отвечен к: YYYY-MM-DD+5days

---

## Blockers / Risks

- [ ] [Блокер]: [описание, impact]
- [ ] [Риск]: [описание, mitigation]

---

## Decisions Made (этой сессии)

- **[Решение 1]**: [описание]
  - Контекст: [почему]
  - Альтернативы: [что ещё рассматривали]
  - Промоушн в docs/decisions/: ☐ да / ☐ нет

---

## Files Modified (this session)

- `path/to/file1.ts` — [короткое описание изменения]
- `path/to/file2.ts` — [...]

---

## Verification Evidence

- [ ] Tests pass: `[команда + результат]`
- [ ] Type check clean: `[команда + результат]`
- [ ] Manual / user check: `[что проверено]`

---

## Last Audit

(заполняется командой `/audit`)

**Date**: YYYY-MM-DD
**7-tuple scores** (1-5):
- Instructions: ?
- State: ?
- Verification: ?
- Scope: ?
- Lifecycle: ?
- Learning: ?
- Cost & Safety: ?

**Bottleneck**: [подсистема с наименьшим баллом]
**Recommended action**: [что улучшить первым]

---

## Cost Snapshot

(автоматически из .harness/cost-log.json при /handoff)

- Spent this session: $X.XX
- Spent total in project: $X.XX
- Estimated remaining for current feature: $X.XX

---

## Open Issues (если /handoff произошёл с не-чистым выходом)

- [ ] [Что не закрыто]

---

## Cold-Start Test (next session)

(заполняется автоматически — 5 точных вопросов из .harness/cold-start.yaml)

При `/resume`:
1. Что это за продукт?
2. Текущий bottleneck (5-tuple)?
3. Активная фича + verification_command?
4. Последние 3 решения и почему?
5. Что НЕ нужно делать (anti-patterns)?

---

## Notes for Next Session

[Свободная форма — что важно поднять в начале следующей]
