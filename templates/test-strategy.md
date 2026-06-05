---
feature_id: feat-NNN
category: infra|data|api|ui|workflow|integration
size_estimate: S|M|L
primary_user_risk: "ОБЯЗАТЕЛЬНО ЗАПОЛНИТЬ. Главный риск с точки зрения пользователя (не engineering). Что будет хуже всего если фича сломается? Например: «пользователь нажмёт кнопку и ничего не увидит» (feat-204). Один абзац."
user_visible_outcome: "ОБЯЗАТЕЛЬНО ЗАПОЛНИТЬ. Что пользователь должен увидеть / получить / испытать после успешной фичи. Конкретно: «открыл /dashboard → в списке появилась новая запись с текстом X», не «компоненты работают». Один абзац."
integration_boundaries:
  - "AdapterA → ServiceB"
  - "ServiceB → WorkerC"
domain_invariants_covered:
  - "invariant-1 из domain-rules.yaml"
ux_data_model_fit_checked: false  # true только после model_fit_critic для ui/workflow/api
---

# Test Strategy — feat-NNN: <название>

## 1. Главный риск с точки зрения пользователя

> **Обязательная первая секция.** Если ты engineer, фокусирующийся на коде — стоп. Поставь себя на место пользователя. Что для **него** означает «фича сломалась»?

[Опиши главный риск одним абзацем. Не «testid невидим / HTTP 500», а «пользователь сделал X и не получил Y».]

## 2. Видимый outcome для пользователя

[Что пользователь должен увидеть **в DOM** / **на экране** / **в боте** / **в файле** после успешной фичи. Конкретно. Например:
- «На странице /bloggers появилась карточка с именем блогера и его аватаром»
- «В Telegram пришло сообщение `сохранено: голос #14:02`»
- «Файл `<project>/users/<u>/raw/2026-05-20/14-02-00.md` создан с frontmatter `type: voice`»

НЕ:
- «Компонент UploadButton корректно рендерится»
- «HTTP 200 на /api/upload»
- «Console без errors»
]

## 3. Tests Proposed

### 3.1 Layer 1 — Syntax & Static Analysis

```bash
npm run check    # tsc --noEmit
npm run lint
```

### 3.2 Layer 2 — Unit (isolated modules)

| Test | What checks | Verification command |
|---|---|---|
| t-unit-01 | <happy case> | `npm test -- --filter=feat-NNN-t01` |
| t-unit-02 | <edge case> | ... |
| t-unit-03 | <error case> | ... |

### 3.3 Layer 3 — Integration Smoke (границы A↔B без моков)

> Для каждой границы из `integration_boundaries` frontmatter — обязательно ≥1 smoke-тест.
> Mock одного из модулей, real другой (или spy с assert аргументов).
> Проверяет **трансформированный payload**, не только факт вызова.

| Boundary | Test | Verification |
|---|---|---|
| `AdapterA → ServiceB` | t-smoke-01: A передаёт event X → B получает payload с правильными полями | `npm test -- --filter=smoke-AdapterA-ServiceB` |
| `ServiceB → WorkerC` | t-smoke-02: B enqueue → C запускается с правильными аргументами | ... |

### 3.4 Layer 4 — E2E (Hot path + Recovery + Error branches)

Hot path:
- Команда: `bash e2e/test-feat-NNN-hot.sh`
- Что проверить: <пользовательский сценарий end-to-end>

Recovery path (если применимо):
- Команда: `bash e2e/test-feat-NNN-recovery.sh`
- Что проверить: <отдельно от hot path>

Error branches:
- Что проверить: <как форсировать ошибку + что увидеть>

> ⚠ Recovery работает не значит hot path работает. См. error-journal: integration-gap voice-worker (feat-02 проекта голосового ассистента).

### 3.5 Layer 5 — User-reported (ОБЯЗАТЕЛЬНО для UI)

> Без этого слоя UI-фича НЕ может стать `passing`. State машина переводит в `awaiting_user_acceptance` после Layer 1-4.

Сценарий который пользователь должен пройти:
- [Описание один-два шага]
- [Конкретный ожидаемый результат который пользователь увидит]

Пример: «Открой /dashboard, нажми «Добавить блогера», введи `@test_blogger`. Должна появиться карточка с именем `test_blogger` и кнопкой «Удалить»».

## 4. 5-категорийный чек-лист перед passing

> Из `feedback_isolated_tests_dont_cover_real_paths.md`. Прохожу перед объявлением passing.

- [ ] **Universal limits / lookups** — если лимит универсален для N типов, тест есть на каждом?
- [ ] **Integration smoke (связки)** — все границы из `integration_boundaries` покрыты?
- [ ] **Recovery vs hot path** — оба пути проверены e2e ОТДЕЛЬНО?
- [ ] **Success vs error** — happy + error branches оба покрыты?
- [ ] **Race conditions** — если асинхронный код — два параллельных теста не врут?

## 5. 3 preflight вопроса (E1 — доминирующий принцип)

> Перед каждым «готово» — отвечаю на эти 3 вопроса. Запрещено объявлять passing без ответов.

1. **Что конкретно увидит / получит / испытает пользователь?** [ответ]
2. **Чем я это проверил end-to-end?** [инструмент: chrome-devtools-mcp / curl / прогон сценария / ...] [НЕ «прошёл structural verifier»]
3. **Что между моим артефактом и конечным результатом может сломаться?** [рендеринг / deploy / env / сеть / версии / интерпретация / ...] [и как я это проверил]

## 6. Negative-verification self-check

Перед промоушеном verification_command в feature_list.json — введён искусственный bug, тест упал, bug убран, тест прошёл.

- Что сломал в коде: [описание]
- Какой тест упал: [t-unit-XX / t-smoke-XX]
- Что вижу при success: [ожидаемое поведение]

## 7. Что НЕ покрывает feat-NNN

[Явный scope-out. Что НЕ будет работать после этой фичи и нужно в feat-XXX.]

## 8. Зависимости

- Зависит от: [feat-XXX в passing]
- Блокирует: [feat-YYY ждёт этой фичи]
- Внешние ресурсы: [API ключи / база / supabase / vercel доступ]
