# Таблица трассировки механизмов — Vibe Dev v6

> **Живой документ + механизм.** Каждый заявленный инвариант обязан иметь все 3 атрибута
> (тест 3 атрибутов из `~/CLAUDE.md`). Полноту проверяет `scripts/check-traceability.sh`:
> строка без 3 заполненных колонок ИЛИ со ссылкой на несуществующий файл → self-check **падает**.
> Это не документация «на доверии» — это проверяемый контракт. Запускается в self-check плагина.
>
> **Правила формата (иначе self-check падает):**
> - 4 непустых колонки на строку: Механизм | Где зафиксирован | Чем enforce | Что при обходе.
> - «Где зафиксирован» содержит ≥1 реально существующий путь-файл (относительно корня плагина).
> - «Что при обходе» содержит одно из слов: block / warn / log / ask / safe.
>
> Добавляешь новый механизм enforcement в плагин → добавляешь строку сюда. Нет строки = механизм
> не отслеживается. Строка с пустым атрибутом или мёртвой ссылкой = это пожелание, не механизм.

| Механизм | Где зафиксирован | Чем enforce | Что при обходе |
|---|---|---|---|
| Хуки активны из коробки | hooks/hooks.json | Claude Code авто-загрузка при установке (v2.1+) | без файла невозможно; cold-start кричит «ENFORCEMENT OFF» — log |
| UI-evidence gate | hooks/checks/state-transition.sh | dispatch валидирует вносимое содержимое feature_list.json (намерение, не диск) | UI→passing без layer_4/5 user-evidence = **block** (hard, всегда, даже legacy/learn) |
| State-machine структура | hooks/checks/state-transition.sh | валидатор переходов против schemas/feature-state-transitions.yaml | невалидный state / битый JSON = block (актуальный) или warn (legacy/learn) |
| bulk-API gate | hooks/checks/bulk-api.sh | dispatch на Bash, детект массового API в команде → требует pre-launch-checklist | массовый внешний API без approved checklist = **block** (во всех профилях) |
| concurrent-write | hooks/checks/concurrent-write.sh | session-marker в .harness/locks, TTL 120с | другая сессия писала shared-файл < TTL = **warn** (advisory; mutual exclusion негарантируем) |
| warn доходит до модели (R2) | hooks/lib/hook-io.sh | stdout JSON additionalContext + exit 0 (не stderr) | иначе предупреждение молча терялось бы → теперь warn виден модели |
| version lifecycle (H2) | scripts/upgrade-project.sh | .harness/engine-version + /upgrade-project; новые проекты strict, старые legacy | старый проект не форсится на strict автоматически = safe (перевод по команде) |
| WIP=1 scope | hooks/pre-commit-scope.sh | git pre-commit hook (exit 1 блокирует commit) | diff вне feature.affected_files = block коммита |
| Критика до реализации (H7) | hooks/checks/state-transition.sh | active-gate: M/L-фича в active требует docs/test-strategy.md с её id | критику пропустили = фича не входит в active = **block** |
| Ревью модели данных | hooks/checks/state-transition.sh | active-gate: data-фича требует docs/data-model-review.md с её id; критик — agents/data-model-reviewer.md | схема без ревью = фича не входит в active = **block** |
| Намерение без действия (H19) | hooks/checks/stop-intent-without-action.sh | dispatch-stop.sh на Stop: маркер-намерение в тексте хода + ноль tool_use в ходе (из transcript) | завершение хода обещанием действия без выполнения = **block** (продолжить; cap 8, standard/strict) |
| Handoff loop (H6) | hooks/checks/handoff-reminder.sh + hooks/checks/handoff-pending-probe.sh | UserPromptSubmit: сигнал завершения → inject cold-start чеклиста + маркер handoff-pending; SessionStart: маркер есть и SESSION.md не обновлён после → warn о пропуске | план рискует остаться в чате → напоминание при закрытии + детекция пропуска при старте (**warn**/inject, не block; standard/strict) |
| Стоп-сигнал пользователя (анти-залипание №1) | hooks/checks/stuck-signal-reminder.sh + hooks/dispatch-user-prompt.sh | UserPromptSubmit: стоп-слова курс-коррекции в промпте → inject «смена УРОВНЯ, не способа; субагент-диагностика, не ещё одна тактическая попытка» | проигнорированный стоп-сигнал → напоминание видно модели (**warn**/inject, не block; standard/strict) |
| Повтор Bash / retry-loop (анти-залипание №2) | hooks/checks/bash-repeat-counter.sh + hooks/dispatch-post-tool-use.sh | PostToolUse: ≥3 подряд падающих однотипных команд без структурных правок → inject подсказки про субагент-диагностику; сброс при успехе и при Edit/Write | слепой retry-loop одной падающей команды → подсказка видна модели (**warn**/inject, не block; standard/strict) |
| Правило пользователя (hookify R6/H9) | hooks/checks/user-rules.sh + skills/hookify/SKILL.md | PreToolUse: `.harness/user-rules.json` (tool+regex+action) применяется к командам/путям; скилл пишет правило из «не делай X» | действие, нарушающее правило пользователя → **block** или **warn** по выбору пользователя (standard/strict); только действия, не контент сообщений |
| Смена модели без smoke (дыра аудита) | hooks/checks/model-swap-guard.sh + hooks/dispatch-pre-tool-use.sh | PreToolUse: правка вносит идентификатор модели (gpt-/claude-/gemini-/…) или ключ настройки (max_tokens/temperature/reasoning/…) → warn про изменение контракта | смена зависимости, влияющей на каждый вывод, без smoke → напоминание прогнать smoke (**warn**, не block; standard/strict) |
| Vendor-lock без research (дыра аудита) | hooks/checks/state-transition.sh + skills/research/SKILL.md | active-gate: integration-фича (category=integration или providers/scraper/fetcher в affected) не входит в active без docs/research/*.md с её id | поставщик пригвождается без research → фича не входит в active (**block**; standard/strict, warn в legacy) |
| Язык-ловец (дыра аудита: коммуникация) | hooks/checks/clarity-detector.sh + hooks/dispatch-message-display.sh + rules/decision-format.md | MessageDisplay: жаргон / развилка-без-«что теряешь» / человеко-дни в сообщении агента → лог `.harness/clarity-violations.log` + флаг на экране; строгость по `jargon_tolerance` из портрета `~/.vibe-dev/portrait.md` (онбординг /setup) | непонятное сообщение пользователю → подсвечено + посчитано (**warn/log**; честно display-only, НЕ enforcement поведения модели; standard/strict) |
| Полнота трассировки (тест 3 атрибутов) | scripts/check-traceability.sh | парсит эту таблицу: 3 атрибута + живые ссылки | строка без 3 колонок / мёртвая ссылка = self-check **block** (exit 1) |
| Обезличенность shipped (v6.1, публичный релиз) | scripts/check-no-personal-data.sh + tests/hooks/test-no-personal-data.sh | grep по shipped-набору, вызывается из scripts/check-plugin-self.sh (раздел 17) | приватные данные (username/личная почта автора / имя реального проекта / личный путь / портрет; публичное имя автора разрешено) в shipped → self-check **block** (exit 1) |

---

## Профили строгости

| Профиль | state-machine | UI-evidence | bulk-API | concurrent | Stop-intent (H19) | handoff (H6) |
|---|---|---|---|---|---|---|
| minimal | выключено | выключено | **block** | выключено | выключено | выключено |
| standard (default) | block (актуальный) / warn (legacy) | **block** | **block** | warn | **block** | inject |
| strict | block | **block** | **block** | warn | **block** | inject |

`.harness/profile` переключает; `.harness/hook-mode=learn` понижает структурные до warn (UI-evidence остаётся hard).

Анти-залипание №1 (стоп-сигнал, UserPromptSubmit) и №2 (повтор Bash, PostToolUse) — как handoff: **inject в standard/strict, off в minimal**. Оба warn/inject, никогда не block.

## Что НЕ в таблице (ещё не реализовано — не заявлять как механизм)

Эти из мастер-плана появятся в волнах 1-2 и попадут в таблицу ТОЛЬКО когда будут реальными файлами:
MessageDisplay-детектор языка (H5 — ✅ событие ПОДТВЕРЖДЕНО в 2.1.161; ⚠️ контракт display-only: `displayContent` меняет только экран пользователя, оригинал читает Claude → хуком НЕ enforce'ится поведение модели, только recurrence-метрика + косметика; живой тест payload ПЕРЕД реализацией),
config-protection,
`feature`→Workflow-оркестрация (контракт Workflow-инструмента в скилле — first-use).
До реализации строки тут быть НЕ должно — иначе self-check упадёт на мёртвой ссылке (и это правильно).

> Волна 1 (частично): active-gate H7 + data-model review (строки выше) + агент `data-model-reviewer` —
> сделаны как хук-механизм (не Workflow). `feature` SKILL переписан на правильный порядок (критика → active).
