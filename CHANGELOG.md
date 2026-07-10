# Changelog

## v8.0.0 (2026-07-10) — Провенанс фич, управляемый контекст, пины моделей, усиленная проверка

Девять волн (0–8), **26 фич**, реализовано по решениям владельца (карточки c1-c12 из отчёта
vibe-dev-report.vercel.app) + паттернам доноров pilotfish / OpenSpec / spec-kit /
agents-best-practices. Корневой курс: авто-сжатие контекста — крайняя мера, не инструмент;
состояние фич живёт в файлах под провенансом, а не в раздувающемся контексте; «готово» = проверенное
поведение, а зелёные тесты умеют лгать. Пять линий:

- **Линия 1 — Модели.** Контракт фронтматтера агентов (`model` / `effort: max` / `disallowedTools`) —
  enforced-поля движка, не декларация. Пины: 12 opus (план / критика / проверка) + 12 sonnet
  (код / чтение / рутина); реестр `docs/agent-registry.md` = источник истины, self-check сверяет
  фронтматтер с реестром. Эскалация по тиру при залипании (circuit breaker: 2 провала на тире →
  поднять тир, не ретрай; LLM-кворум только если высший тир провалил). Защитную работу — на Opus,
  не на свежайшую frontier (её safety-классификатор рвёт benign defensive mid-task).
- **Линия 2 — Детализация.** Единый резолвер путей харнеса (`hooks/lib/resolve-paths.sh`): один
  источник имён артефактов + поиск корня вверх по дереву, STRICT-режим при неоднозначном корне →
  hard-error вместо тихого фолбэка на cwd (лечит «запись не в тот проект»). Стадия детализации:
  M/L-фича (или `detail_required`) не входит в active без `docs/changes/<id>/proposal.md` с ≥1
  приоритизированной P1 user story в Given/When/Then (OpenSpec + spec-kit) — основа
  verification_command. Backlog ленивый: детали рождаются при взятии в работу, не грузятся заранее.
- **Линия 3 — Провенанс (event-sourcing).** Схема головы (origin/medium разделены, source_ref,
  occurred_at, seq, superseded_by, неизменяемый feat-id) + честная миграция. Append-only лог (git
  pre-commit reject на правку прошлой строки). `record-change.sh` — единственный crash-safe путь
  записи (append лога → temp+mv головы; обрыв → голова позади = восстановимо; идемпотентность по
  change_id). Инвариант правки бизнес-поля (изменено без события лога → reject). Архив по ссылке:
  done/superseded/rejected с evidence → `feature_list.archive.json` (тело + hash), в горячем стаб;
  git pre-commit сверяет evidence_hash БЕЗ загрузки тела в контекст. Delta-мёрж спеки в
  `docs/ARCHITECTURE.md` + гейт незакрытых tasks.
- **Линия 4 — Анти-сжатие контекста.** Трёхуровневая модель (горячий CLAUDE.md ≤200 строк = голова +
  индекс / по требованию grep / холод = архив + лог) + warn на раздутый горячий. Управляемый
  `/checkpoint` (`scripts/checkpoint.sh`): recovery провенанса → ротация завершённого в архив →
  **cold-start gate (block)**: шаблонный/отсутствующий SESSION.md ИЛИ некогерентный провенанс →
  exit 1. PreCompact-слепок демотирован до страховки (основной носитель — /checkpoint). Нудж на
  /checkpoint по длине сессии (честно discipline). Сужение возврата 4 читающих агентов: полный
  результат в файл, в главный поток — дайджест ≤2 КБ + путь (критиков не режем — whitelist).
- **Линия 5 — Проверка.** Закрыт fail-open защиты границ правок (`.harness/hook-mode` под защитой;
  Bash-детект расширен на cp/mv/install/ln/sed -i). Evidence на logic-фиче: passing для surface=lib/
  logic требует runtime/e2e (не только typecheck+lint); M/L passing без negative-gate
  (mutation/leak) → block. Adversarial fresh-context verifier (`stage-verifier` в режиме assume
  broken; disallowedTools физически запрещает ему Write/Edit — верификатор не подгонит код под свой
  тест). Бюджет tool-call на фичу (нудж). Единая цифра готовности `/audit` = min по узкому месту
  (bottleneck 7-tuple × детерминированные метрики provenance/archive). Folder-scope log-only → warn.

Все механизмы — строкой в `docs/traceability.md` с датой живой проверки (**67 отслеживаемых** —
единственный источник числа; экранные детекторы clarity/secret-mask честно НЕ в счёт). self-check
вырос до **43 разделов**, все PASS; `plugin validate --strict` зелёный. **Осознанно НЕ в ядро**
(честность деклараций): headroom-датчик размера окна (нет надёжного сигнала контекста в Claude Code →
только неразрушающий эксперимент с авто-эвикцией, строки-механизма нет намеренно); нудж /checkpoint и
бюджеты tool-call помечены discipline, не enforcement.

## v7.0.0 (2026-07-02) — Пять волн: доставка, честность, автопамять, замки, поведение

Собрано по аудиту 9 боевых журналов недели (24.06–02.07) + план `_internal/plans/START-HERE-v7.md`
(3 критика, автопамять сведена к минимальному ядру). Корневой диагноз: плагин выдавал ДИСЦИПЛИНУ
за МЕХАНИЗМ, клеил пост-фактум костыли, нёс мёртвые механизмы в счётчике «38» и рассинхроны.

**Гейт-1 (развилка автопамяти) — закрыт живым прогоном.** Изолированная песочница на 2.1.170:
`/compact` → хук сработал (`FIRED=PreCompact`), payload несёт `transcript_path`, файл существует;
`SessionEnd` тоже приходит. Фантомность `MessageDisplay` (display-only, client-gated) на них не
переносится — это события контрольного потока. Значит M2 держится на PreCompact, а не на Stop.

- **Волна 0 — доставка + честность.** Канал доставки (`hook_upgrade_nudge` + SessionStart + /doctor):
  установлен новый мажор плагина > пин проекта → подсказка `/upgrade-project` (только кросс-мажор).
  Переписан `workflow/enforcement-philosophy.md` (убрано ложное «Quality>Speed блокирует сообщение
  до показа» — в SDK нет pre-send хука; мёртвые ссылки → реальные `checks/*`; введены 3 честных
  класса механизм/подсказка/дисциплина). Счётчик «38/37» в прозе (CLAUDE.md, README, plugin.json)
  → ссылка на traceability как единственный источник (42 отслеживаемых, 2 честно display-only).
  Починка генератора P8/P9: `AGENTS.md → CLAUDE.md` в 27 файлах (интервью писало в несозданный файл).
- **Волна 1 — дешёвые надёжные.** `browser-tester` переписан: Playwright из Bash — основной путь +
  обязательный протокол снять PNG (desktop+mobile) → Read → описать глазами (без этого нет «PASS»).
  Сужен data-gate P7 (`state-transition.sh`): триггер только по путям ОПРЕДЕЛЕНИЯ схемы + escape
  `data_model_predefined`; уровень НЕ понижен по размеру (правила #1/#11 сохранены; тесты 24/26 целы).
- **Волна 2 — автопамять (минимальное ядро, 0 токенов, без демона/субагента).**
  M2 `hooks/pre-compact.sh` (PreCompact): extractive-слепок транскрипта → `.harness/last-checkpoint.md`,
  пишет ФАКТЫ, не статус «готово». C1 `hook_cold_start_brief` (SessionStart): активные фичи + тупики
  + слепок → inject с ОБЯЗАТЕЛЬНОЙ recall-фразой. G1/C2/C3 (шаблон журнала): штамп устаревания +
  форма против повторов + маршрутизация. G5 `scripts/journal-audit.sh`: read-only аудит + дедуп.
- **Волна 3 — новые замки.** `secret-scan-write.sh` (block хардкода живого ключа, единый словарь
  `secret-lexicon.sh`, escape-фраза через `secret-skip-listener`). `folder-scope.sh` (запись вне
  корня → старт в режиме ТОЛЬКО-ЛОГ, whitelist + git-worktree, file_path-only).
- **Волна 4 — гигиена.** Дешёвый дедуп журнала (нормализация + uniq, кириллица через python) +
  circuit breaker на счётчике повторов (удвоенный порог → твёрдая эскалация в /stuck).
- **Волна 5 — глобальный слой + поведение.** wave-continue (`go-mode-listener` + `wave-continue.sh`):
  явная фраза «не тормози» → маркер, и если ход кончился вопросом — inject «тех-переспрос не задавай»
  (warn, вопрос не давим). Плюс правило формата/доставки/следующего шага/окружения в глобальном
  пользовательском слое `~/CLAUDE.md` + обёртка рендера office→PDF в `~/bin` (через soffice).

Все новые механизмы — строкой в `docs/traceability.md` с датой живой проверки. self-check вырос до
32 разделов, все PASS; no-personal-data 7/7. **Осознанно НЕ сделано** (критики: плодят беды):
idle-демон (зомби), модуло-счётчик (дубль M2), rethink-перезапись журнала (потеря данных),
PostToolUse-grep стек-трейсов (событие не приходит на упавших Bash), субагентская дистилляция из хука.

## v6.2.1 (2026-06-12) — Interrupt-recovery: техническое прерывание ≠ запрет

Диагностика 51 interrupt-события в боевых журналах (зафиксирован простой 7ч17м): обрыв
клиентского канала (закрытая крышка ноутбука при Desktop/удалённой сессии — открытый
issue anthropics/claude-code#49790) и доставка входящего сообщения (вопрос «готово?»,
Telegram-канал, task-notification) помечают выполнявшийся инструмент «The user doesn't
want to proceed…» — агент читает «STOP and wait» и стоит часами, хотя пользователь ничего
не запрещал.

- **Новый механизм №38 — interrupt-recovery** (`hooks/checks/interrupt-recovery.sh`,
  UserPromptSubmit): хвост последнего хода оборван interrupt/reject-маркером, работа после
  него не возобновлялась, в новом промпте нет стоп-слов → inject «прерывание было
  техническим, не запретом — продолжай план, перезапусти убитый вызов». Настоящий «стоп»
  пользователя главнее: стоп-словарь выключает напоминание. warn/inject, не block.
- Тест `tests/hooks/test-interrupt-recovery.sh` (12 сценариев на реальных формах записей
  transcript 2.1.170) + контрольный прогон на настоящем боевом журнале с deny-таймаутом.
  Self-check раздел 28. Попутно убран задвоенный раздел в README.

## v6.2.0 (2026-06-10) — Enforcement как проверяемый факт

Построено по аудиту 54 боевых сессий (5 проектов, 11 мая — 10 июня) + рисёрчу ×3 (статьи
Anthropic/OpenAI по харнесам, 9 GitHub-репо включая pilot-shell/BMAD/ECC/ralph-wiggum,
актуальные возможности Claude Code 2.1.170) + независимой критике гипотез. **37 механизмов**
в таблице трассировки. Опубликовано 2026-06-10 после живой проверки всех новых сторожей на
движке 2.1.170 (по ходу проверки: счётчик повторов перенесён на PreToolUse — PostToolUse не
приходит на упавших командах; secret-mask получил живой канал additionalContext).

### F1 — Надёжность самих сторожей (урок бага 2026-06-06: краш = молчаливый fail-open)
- `hook_run_check` во всех 6 диспетчерах: краш проверки → громкое предупреждение в канал + crash-артефакт `.harness/hook-crashes/<label>.log`; SessionStart-probe сообщает о крашах прошлых сессий.
- Корпус реальных форм: `tests/hooks/fixtures/real/` — 6 обезличенных боевых feature_list (188 фич, анонимизатор сохраняет типы/формы полей); self-check гоняет гейты на корпусе: реальные формы не роняют сторож + контрольная битая UI-фича ловится.
- Stop additionalContext канал (движок ≥2.1.163).

### F2 — Активация: профиль строгости без живых хуков невозможен («харнес не поднялся» — главный провал аудита)
- Heartbeat: SessionStart/UserPromptSubmit пишут `.harness/hooks-heartbeat` — живое доказательство работы хуков.
- Двухфазный профиль: bootstrap пишет `pending-strict`; в боевой strict переводит ТОЛЬКО живой хук (факт перевода = доказательство активации).
- НЕЗАВИСИМЫЙ backstop: git pre-commit (работает даже без плагина) блокирует коммит при pending-профиле или устаревшем heartbeat; escape `.harness/hooks-disabled` — только руками пользователя. Заодно закрыта дыра «pre-commit-scope.sh никогда не устанавливался в проекты» (`scripts/install-precommit.sh` зовут bootstrap и /upgrade-project).
- `/doctor` — самодиагностика (профиль/heartbeat/краши/plugin) + Check 0 в /feature, /verify, /resume.

### F3 — Единый Stop-dispatcher
- Приоритеты (intent → clarity → wave-слот v6.3), общий cap ≤3 block на цепочку хода, сброс новым промптом; переполнение → pass + `.harness/stop-cap-log`.

### F4 — Clarity-gate: боль №1 аудита (жаргон/развилки/человеко-дни) переведена из дисциплины в механизм
- Stop-хук читает `last_assistant_message` (движок ≥2.1.47 — открытие рисёрча: «нельзя проверить контент ответа» было неверным выводом): BLOCK → агент дописывает аддендум ≤10 строк (не переписывает — честная ценность: ход не закончится ТОЛЬКО непонятным сообщением).
- Tiered по точности: BLOCK = человеко-дни-оценка (факты «бот молчал 5 дней» не матчатся) + тяжёлый жаргон вне код-блоков; развилка без «что теряешь»/рекомендации = warn. Включение block-tier — портретом непрограммиста или strict.
- Labeled-корпус из реальных формулировок аудита; precision-гейт: false positive на good-корпусе = self-check красный (демоция словаря). Общий лексикон `hooks/lib/clarity-lexicon.sh` (экранный ловец + гейт из одного источника).

### F5 — Evidence по поверхности фичи (П2: «зелёные тесты лгут»)
- Поле `surface: ui|api|cli|job|service|lib|content`; МОНОТОННАЯ строгость: файловая эвристика — пол, заявленное поле только ужесточает (surface=lib при .tsx не отключит UI-gate).
- ui → layer_4/5 hard block; api/job/service/cli → passing без evidence реального вызова = warn с lane-инструкцией (мягкий ввод). `rules/verification-lanes.md` + Live-Target Probe (4 яруса) в /verify; /feature: поверхность перебивает размер (user-critic обязателен для ui).

### F6 — Research-гейт архитектуры (распоряжение владельца: «всегда детальный рисёрч»)
- Запись `docs/ARCHITECTURE*.md` без `docs/research/*.md` → block; пропуск — ТОЛЬКО явной фразой пользователя («пропусти рисёрч»): маркер пишет хук с цитатой (lock-паттерн), скилл потребляет одноразово.
- Lock-паттерн (общий): `.harness/locks/*` пишут только хуки; запись агентом блокируется; rm разрешён (движение к строгости).

### F7 — Closing-mode (П6: «закрой сессию» запускал разработку)
- Сигнал завершения → деградация прав: запись только в state-файлы, Bash только git/read-only/скрипты плагина; авто-снятие следующим промптом без сигнала.

### F8 — Секрет-гигиена (П8)
- Живой ключ в сообщении пользователя → предупреждение о компрометации + ротация + .env + $VAR (жёсткие паттерны, голый sk- не ловится).
- Токен в выводе команды → `updatedToolOutput` с маской (контракт ≥2.1.121, честно помечен «под живой тест»; деградация safe).
- pre-launch-checklist: объём × цена за единицу — до вопроса пользователя.

### F9 — Мелочи
- enforcement-config-protect: агент не ослабит свои гейты (правка profile/heartbeat/hooks-disabled → block; pending-* разрешён).
- Портрет: «стиль ≠ содержание» + 3 канонических примера сообщений; data-model-reviewer: fact-forcing вместо «уверен?».

### Проверки
- 19 наборов тестов, 254 проверки, всё зелёное; self-check 27 разделов; трассировка 37 механизмов (3 атрибута + живые ссылки); полная регрессия на каждом шаге.

### Отложено в v6.3 (по вердикту критика — не повторять «слишком большой дифф»)
- Волна 1: anti-recurrence ядро (баг чинится 3-5 раз) + contract-swap smoke (смена модели/промпта без регрессии).
- Волна 2: /run-wave (батч поверх WIP=1, ralph-паттерн с passthrough вопросов), stuck по метрике, health по поведению, doc-gardening (П5).

## v6.1.0 (2026-06-05) — Публичный релиз: обезличивание + онбординг

Подготовка к публичному распространению. Плагин обезличен (убрано всё личное — username/почта автора, имена реальных проектов клиентов, личные пути, ссылки на личный портрет), добавлен онбординг под нового пользователя. Каркас и 19 механизмов v6.0 по сути не менялись.

### Обезличивание + gate (механизм)
- Все shipped-файлы очищены от приватных данных: имена реальных проектов → обобщённые примеры (уроки сохранены), личные пути → нейтральные, коды внутреннего баг-трекинга убраны. Автор в манифесте — публичное имя по выбору пользователя.
- НОВЫЙ механизм: `scripts/check-no-personal-data.sh` + `tests/hooks/test-no-personal-data.sh` (TDD) — grep-gate в self-check (раздел 17): приватные данные в shipped → self-check падает (**block**). Трассировка: **20 механизмов**.
- Удалён мёртвый `scripts/install-hooks.sh`.

### Онбординг (новая фича)
- `/setup` — интервью из 6 простых вопросов (роль, пишешь ли код, уровень ответов, терпимость к терминам, что строишь, язык) → портрет `~/.vibe-dev/portrait.md`.
- Механизмы стиля читают портрет: язык-ловец (`clarity-detector.sh`) берёт уровень `jargon_tolerance` (high — термины и краткие развилки не подсвечивает, medium — ядро жаргона, low — строго; человеко-дни ловит всегда); формат развилок (`decision-format.md`) — простой язык непрограммисту, краткий технический список технарю. «Что теряешь» + рекомендация — на любом уровне.
- Без портрета — безопасный нейтральный дефолт (medium). `/new-project` (Шаг 0) предлагает `/setup` при первом запуске.

### Проверки
- self-check 17/17 (включая новый gate 7/7), `plugin validate --strict` passed, 8 наборов хук-тестов целы.

## v6.0.0 (2026-06-05) — Enforcement из текста в механизм

После аудита всех ~20 реальных проектов v5 (12 ретроспектив + ~150 memory + 6 error-journal, 6-агентный разбор → `docs/v5-coverage-audit-2026-06-05.md`) перенесён enforcement из текста в проверяемые механизмы. **19 механизмов** в таблице трассировки (`docs/traceability.md`), у каждого 3 атрибута (где / чем enforce / что при обходе), self-check на полноту.

### Hooks из коробки (авто-загрузка hooks.json, Claude Code v2.1+)
- Единые диспетчеры на 6 событий: PreToolUse, PostToolUse, Stop, UserPromptSubmit, SessionStart, MessageDisplay. Контракт верифицирован (`docs/hooks-contract-verified-2026-06-03.md` + живая проверка на движке 2.1.161, баг Stop найден и починен).
- Общая библиотека `hooks/lib/hook-io.sh` (правильные коды: stdout-JSON additionalContext/displayContent, не stderr; permissionDecision:deny для block).
- Профили строгости minimal/standard/strict; version-awareness (живые проекты не форсятся) + `/upgrade-project`.

### Механизмы (что реально enforce'ится)
- **UI-evidence gate** — UI→passing без user-evidence = block (закрывает B2/feat-204).
- **Критика-до-реализации (H7)** + **ревью модели данных** — M/L-фича требует `docs/test-strategy.md`, data-фича — `docs/data-model-review.md` (агент `data-model-reviewer`).
- **bulk-API gate**, **WIP=1** (git pre-commit), **concurrent-write** (advisory).
- **Stop-intent (H19)** — обещание действия без tool_use = block. **Handoff loop (H6)** — cold-start чеклист + детекция пропуска.
- **Анти-залипание ×2** — стоп-сигнал пользователя (UserPromptSubmit) + повтор падающих Bash (PostToolUse).
- **hookify** — «не делай X» от пользователя → block/warn-правило без кода.
- **Смена-модели без smoke** → warn про изменение контракта (реальный кейс: 3 дня обрывов после замены модели).
- **Vendor-research gate** — integration-фича без `docs/research/*.md` = block.
- **Язык-ловец (MessageDisplay)** — жаргон/развилка-без-«что теряешь»/человеко-дни → лог `.harness/clarity-violations.log` + флаг на экране (честно display-only: детектор+метрика, НЕ enforcement модели) + `rules/decision-format.md`.

### Честно осталось дисциплиной (не механизм)
integration-smoke / verify-на-реальном-пути, агент-сам-не-в-терминал, тест-реалистичность — труднее мехнизировать. `feature`→Workflow — first-use на первом боевом. Harness-observability (сигнал наружу) — кандидат v6.1.

### Тесты
8 наборов хук-тестов (PreToolUse 33 · Stop 12 · UserPrompt 19 · SessionStart 9 · PostToolUse 14 · user-rules 11 · model-swap 9 · clarity 11) + self-check плагина + `plugin validate`. Все зелёные. ⏳ Живая сверка проводки PostToolUse + MessageDisplay — при первом старте сессии (новые события).

> id плагина остаётся `vibe-dev-v5` (внутренний идентификатор — от него зависят имена команд и установка; меняется ВЕРСИЯ → 6.0.0).

---

## v5.2.0-alpha (2026-05-20) — Bottleneck-first iteration

После валидации v5.1 на 2 реальных проектах (проект голосового ассистента + CRM-проект, 20.05.2026) собрано 14 feedback файлов CRM-проекта + 12 уроков проекта голосового ассистента + 4 ретроспективы + error-journal с 4 детальными разборами. Прошли через 3 независимых ревьюера (Opus max).

**Финальный вердикт ревьюера**: вернуться на доработку. Внедряем только TOP-3 гипотезы из 30 в первой итерации, остальное — после теста на новом проекте.

### Top-3 внедрено (Wave 1)

#### H13 — Переписать SKILL.md (удалить «эпидемию человеко-дней»)

Источник: `skills/dev-plan/SKILL.md` строка 53 содержала «Total: ~12 дней» — плагин сам учил агента нарушению A3 из памяти CRM-проекта.

Изменения:
- `agents/dev-planner.md` — переписан финальный отчёт (количество фичей + size_estimate вместо дней)
- `agents/reordering-agent.md` — все «X days» → S/M/L size_estimate
- `agents/evaluator-agent.md`, `agents/idea-generator.md`, `agents/idea-critic.md`, `agents/idea-validator.md`, `agents/marketing-launch-preparer.md`, `agents/stage-verifier.md` — массовая чистка
- `skills/choose-stack/SKILL.md`, `skills/ship/SKILL.md`, `skills/dev-plan/SKILL.md` — финальные сообщения переписаны по шаблону B (см. `rules/message-finalization.md`)
- `workflow/pipeline.md` — длительность фичи в S/M/L, не часах

Новые rules:
- `rules/no-human-days.md` — запрет с примерами замены
- `rules/message-finalization.md` — обязательные шаблоны A/B/C для финализации
- `rules/check-yourself-first.md` — таблица замены инфра-вопросов на bash-проверки

#### H1 — Pre-write state-transition hook

Источник: главный совет harness-ревьюера. Закрывает B2 (feat-204 объявлен passing без user-acceptance), B4 (data-model-reviewer), C1 (UI без visible outcome).

Новое:
- `schemas/feature-state-transitions.yaml` — единый источник истины state machine
  - 13 states (добавлены `awaiting_research`, `awaiting_reviewer`, `awaiting_demo_milestone`, `awaiting_user_acceptance`)
  - Allowed transitions явно описаны
  - Evidence requirements per transition (UI → обязателен layer_5_user_at)
  - Категории фичи + auto-detect patterns по affected_files
- `hooks/pre-write-state-transition.sh` — Python-валидатор state transitions при Write feature_list.json
  - Strict mode (block) / Learn mode (warn) через `.harness/hook-mode`
  - Особый случай: UI-фича в passing БЕЗ layer_4/5_user evidence = ❌ block (B2 enforcement)
- `templates/feature_list.json` — обновлён schema, добавлены поля `category`, `integration_boundaries`, `evidence` объект

#### H6 — test-strategy.md template с обязательным frontmatter

Источник: feedback feat-001 (правильный шаблон) vs feat-204 (engineering-first без user-risk). Закрывает B3, C1.

Новое:
- `templates/test-strategy.md` — обязательный yaml-frontmatter:
  - `primary_user_risk` (главный риск с точки зрения пользователя)
  - `user_visible_outcome` (что пользователь должен увидеть после успешной фичи)
  - `integration_boundaries` (границы A↔B для smoke-тестов)
  - `domain_invariants_covered` (ссылки на invariants)
- 5-секционный template с обязательной первой секцией «Главный риск с точки зрения пользователя»
- Включает 5-категорийный чек-лист перед passing (E7) + 3 preflight вопроса (E1)

#### H28 — CI на плагин (Quality Gate сам на себя)

- `scripts/check-plugin-self.sh` — self-check скрипт:
  - Запрещённые «человеко-дни» в шаблонах
  - templates/CLAUDE.md (не AGENTS.md) — Claude Code convention
  - Все skills имеют SKILL.md
  - Все agents имеют frontmatter
  - Hooks executable
  - Critical rules файлы существуют
  - JSON/YAML validity

### Дополнительные изменения

- **`AGENTS.md` → `CLAUDE.md`** в templates (Claude Code convention) — пользователь работает 95% в Claude Code, agent-portability убран как design constraint
- **5-layer verification** введён в template `templates/test-strategy.md` (Layer 3 = Integration Smoke) — закрывает H1 voice-worker integration gap
- Обновлены ссылки в `skills/new-project/SKILL.md`

### НЕ внедрено в alpha (отложено)

- **H2 (quality-gate-validator)** — REJECT в исходном виде. В Claude Code SDK нет pre-message hook. Требует радикальной переработки в «metrics + selective validator».
- **H3 (3 preflight вопроса)** — без H2 = декларация. Встроено как **секция** в test-strategy.md template, но без validator enforcement.
- **H4-H30** — после теста v5.2-alpha на новом проекте (~2 недели).

### Migration path для live проектов

- **Проект голосового ассистента** (FAST, feat-04 active) — остаётся на v5.1 до завершения feat-04. После — opt-in миграция.
- **CRM-проект** (FAST, feat-103 next) — пользователь решает. Если контракт горит — оставаться. Иначе — partial adoption (только H13 + H24 без новых hooks).
- **Новый тестовый проект** — стартовать сразу на v5.2-alpha с `.harness/hook-mode = strict`.

### Ожидаемый балл

Реалистичный forecast (по оценке ревьюера): **6.5–7.5** среднее (был 5.4). Авторская оценка 8.6 — переоценка. Главные приросты: State (5→8 через H1), Communication (4→7 через H13), Verification (5→7 через H6).

### Что дальше

После 2 недель использования v5.2-alpha на новом проекте — retrospective + решение по Wave 2 (H4 5-layer, H5 category-aware path, H7 resume-checklist, H8 data-model-reviewer, H10 model-fit-critic, ...).

---

## v5.1.0 (2026-05-19) — Harness-enforcement architecture

### Главный сдвиг
- «Harness — это enforcement, не documentation» — каждый принцип имеет механизм
- 7 подсистем (добавлена Cost & Safety)
- Agent-portability (Claude Code / Codex / Cursor)

### Добавлено (8 must-fix после критики 3 проектов)
- **Pre-flight bulk-API gate** (templates/pre-launch-checklist.yaml + hooks/pre-bash-bulk-api.sh)
  - Закрывает: реальный кейс: $25 + 48h бан Gemini при массовом вызове без проверки квот
- **Concurrent-write lock-table** (templates/tools-allowlist.yaml + hooks/pre-write-concurrent.sh)
  - Закрывает: реальный кейс: $4 + 9 моделей потеряно в проекте с документным ассистентом
- **Stuck auto-trigger** (scripts/stuck-watcher.sh — 30 мин без progress)
  - Закрывает: реальный кейс: 3 часа + 12h compute на skip-pagination в проекте-поисковике по документам
- **Dual critique** (agents/test-researcher.md + agents/user-perspective-critic.md)
  - Закрывает: top-down user perspective из проекта с документным ассистентом
- **domain-rules.yaml** schema (templates/domain-rules.yaml)
  - Закрывает: domain-knowledge gaps в 3 проектах (терминология ниши, отраслевые правила, вендор-специфика)
- **Quality Gate на исходящие** (rules/quality-gate.md + hooks/pre-send-quality.sh)
  - Закрывает: фидбек основателя-непрограммиста «половина слов непонятна» (реальный кейс)
- **Cost-preview** перед bulk LLM call
  - Закрывает: реальный кейс: $13.49 Opus thinking в проекте с документным ассистентом
- **Light/heavy path** в /feature loop
  - Закрывает: bottleneck в самой v5 (Lean-агент валидация)

### Удалено (муда)
- Telegram-дайджест (пользователь работает в Claude Code)
- INBOX.md (избыточен без Telegram)
- BUSINESS-RATIONALE.md (дублировал DECISIONS.md)
- Auto-обновление портрета (заменено на /portrait-review)
- `.planning/` папка (схлопнута в docs/)
- implementation-notes.md отдельным файлом (схлопнут в SESSION.md секцию)
- Sprint contracts (дублировал feature_list.json)
- `.harness/benchmark.json` (автоматизировано через /verify timing)

### Упрощено
- 17 этапов MAX → 10 этапов FULL
- 10 этапов LIGHT → 5 этапов FAST
- 20 команд → 10 команд
- 7 файлов `.planning/` → 0 (в docs/)
- 12-14 файлов в корне проекта → 4 на старте, остальные по факту

### Унаследовано из v4
- Бизнес-интервью + Lean/TOC/6 Sigma язык
- Long-list → critique → parallel research (авторская методология)
- Stuck-протокол с LLM-кворумом (с budget cap)
- Валидационная выборка ≥90%
- Design-handoff через Claude Design
- Marketing-launch (FULL режим)
- Карпати-принципы
- 12 ключевых агентов из 20

### Унаследовано из harness-engineering
- 5 подсистем + AGENTS.md routing ≤200 строк
- WIP=1 + feature_list.json как state-machine
- Cold-start test (5 точных вопросов)
- 5-dim clean-exit
- Memory two-step save invariant
- 15 gotchas каталог
