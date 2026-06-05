# Baseline Measurement Template — Vibe Dev Validation

> Этот файл используется для замеров на ТЕСТОВОМ проекте перед / в процессе работы.
> Цель: получить цифры, по которым решать — пошло ли лучше с v5.1 vs без неё.

---

## Setup

**Тестовый проект**: <название>
**Дата старта**: YYYY-MM-DD
**Тип**: <RAG / агентная система / парсер / диалог / админка / ...>
**Режим**: FAST / FULL
**Стек**: <выбранный>

---

## Метрики для замера

### M1: Cold-start success

| Метрика | Цель | Замер |
|---|---|---|
| /resume через 7+ дней — успешно за <3 мин? | да | _____ |
| Cold-start test пройден ≥4/5 | да | _____ |
| Сколько раз пришлось спрашивать пользователя «а что мы делали»? | 0 | _____ |

### M2: /handoff compliance (CR-7)

| Метрика | Цель | Замер |
|---|---|---|
| % сессий с /handoff (manual или auto) | ≥90% | _____ |
| % сессий с clean-exit 5-dim pass | ≥80% | _____ |
| Сколько раз забыл /handoff (auto-watcher trigger) | <2 за неделю | _____ |

### M3: API research checklist ($25+48h)

| Метрика | Цель | Замер |
|---|---|---|
| Bulk-jobs прошедшие через pre-launch-checklist | 100% | _____ |
| Bulk-jobs запущенные в обход (--force) | 0 | _____ |
| Cost surprises (фактическая стоимость > estimate × 1.5) | 0 | _____ |
| Quota-related incidents (rate limit / ban) | 0 | _____ |

### M4: Concurrent-write блокировки ($4)

| Метрика | Цель | Замер |
|---|---|---|
| Попытки параллельной записи (детектированы hook) | _____ |
| Из них blocked / разрешены через suffix | _____ / _____ |
| Data loss incidents (concurrent writes succeed) | 0 |

### M5: Stuck auto-trigger time (3h+12h compute)

| Метрика | Цель | Замер |
|---|---|---|
| От первой ошибки до /stuck (auto или manual) | ≤30 мин | _____ |
| Manual /stuck triggers | _____ |
| Auto /stuck triggers (45 мин timer) | _____ |
| Auto parallel-research (2 одинаковых fail) | _____ |
| 4-я попытка того же подхода | 0 | _____ |

### M6: Technical A/B в сообщениях пользователю

| Метрика | Цель | Замер |
|---|---|---|
| Сообщений с «вариант A: tech1 / вариант B: tech2» | 0 | _____ |
| Сообщений с jargon без объяснения | 0 | _____ |
| Сообщений с >2 вопросами одновременно | 0 | _____ |
| Сколько раз пользователь сказал «не понимаю» | 0 | _____ |

Метод: grep по transcript сессий + ручной review.

### M7: Cost preview before bulk ($13)

| Метрика | Цель | Замер |
|---|---|---|
| Bulk LLM calls с estimated cost shown | 100% | _____ |
| Cost cap auto-pauses | _____ |
| Per-feature cost (среднее) | <$5 | _____ |
| Monthly project cost | <$100 | _____ |

### M8: Error-journal velocity (новая метрика)

| Метрика | Цель | Замер |
|---|---|---|
| Записей в неделю | <20 | _____ |
| Recurrence rate (% повторов) | 0% | _____ |
| Lessons promoted в memory | _____ |
| Класс ошибок Top-3 | _____ |

### M9: WIP=1 enforcement

| Метрика | Цель | Замер |
|---|---|---|
| Pre-commit scope blocks | _____ |
| Из них justified (расширение feature scope) vs обходы | _____ / _____ |
| Параллельные active features | 0 | _____ |

### M10: 7-tuple assessment evolution

Дата: YYYY-MM-DD (запускать /audit раз в неделю)

| Subsystem | Week 1 | Week 2 | Week 3 |
|---|---|---|---|
| Instructions | _____ | _____ | _____ |
| State | _____ | _____ | _____ |
| Verification | _____ | _____ | _____ |
| Scope | _____ | _____ | _____ |
| Lifecycle | _____ | _____ | _____ |
| Learning | _____ | _____ | _____ |
| Cost & Safety | _____ | _____ | _____ |
| **Bottleneck** | _____ | _____ | _____ |

### M11: Dual critique качество

| Метрика | Цель | Замер |
|---|---|---|
| Фичей с dual critique (heavy path) | 100% L-фичей | _____ |
| Конфликтов engineering vs user resolved для user | ≥80% | _____ |
| User-perspective сценарии добавлены к engineering | _____ |

### M12: Subjective UX feedback

Пользователь сам отмечает в SESSION.md в конце недели:

- [ ] Стало проще возвращаться к работе через паузу? (1-5)
- [ ] Меньше «забыл что делал»? (1-5)
- [ ] Меньше техно-вопросов от системы? (1-5)
- [ ] Уроки реально не повторяются? (1-5)
- [ ] Доверие к системе выросло / снизилось? (-2 .. +2)

---

## Сравнение с baseline (без v5.1)

Если есть данные с предыдущих проектов — заполнять:

| Метрика | Старые проекты | v5.1 на тестовом | Δ |
|---|---|---|---|
| Time on stuck (avg) | 3h (типовое залипание) | _____ | _____ |
| Cost surprise events | $25+$13+$4 на 3 проекта | _____ | _____ |
| Memory loss between sessions | 15 мин/сессия | _____ | _____ |
| Recurrence rate | ? (не мерили) | _____ | _____ |

---

## Решение через неделю

После 5-7 сессий работы — review таблиц + ответы:

1. **Идём в v5.2?** Какие конкретно must-fix добавить (на основе закрытых дыр)?
2. **Что выкинуть?** Какие механизмы оказались муда (false positives, шум)?
3. **Что усилить?** Где enforcement слабоват (часто обходится)?

Запись в `~/.vibe-dev/retrospectives/YYYY-MM-DD-v5.1-validation/retrospective.md`.

---

## Notes

(свободно в течение работы — что заметил, что удивило, что бесит)
