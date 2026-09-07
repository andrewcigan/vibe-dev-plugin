# Источники решения «какая модель на какой стадии»

> Дословные цитаты официальных гайдов, на которых стоит контракт ролей из
> [`agent-registry.md`](agent-registry.md). Держим отдельно и целиком, чтобы решение
> можно было перепроверить по первоисточнику, а не по пересказу.

> Собрано 2026-09-03 пятью агентами разведки. Цитаты дословные, английские — как в источнике.
> Файл существует, чтобы план не стоял на пересказе: любую строку плана можно проверить здесь.

## 1. Какая модель на какую роль (запрос владельца)

- «a Claude Opus 5 executor with a Claude Fable 5.1 advisor was the most accurate configuration
  measured, at $7.69 per attempt» — источник: `platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence`.
- «Coordinator pattern: big models for planning, small models for execution» — там же.
- «For most workloads, start with Claude Opus 5… Use Claude Fable 5.1 for demanding reasoning and
  long-horizon agentic work» — `docs/en/about-claude/models/choosing-a-model`.
- Opus 5 о коде: «strongest on difficult coding tasks: multi-file features, larger refactors…
  performs best when given the complete task specification up front and left to run»
  — `docs/en/models/opus-5/migration-guide`.
- Фронтматтер агента принимает `model` (`sonnet|opus|haiku|fable|inherit`|полный id), `effort`,
  `tools`, `disallowedTools` — `code.claude.com/docs/en/sub-agents`.

## 2. Что ЛОМАЕТ наши промпты (написаны под прежние модели)

- «If your prompt contains explicit verification instructions… remove them: instructions like these
  cause over-verification on Claude Opus 5, and removing them reduces wasted tokens with no loss in
  quality. The same applies to legacy harness scaffolding that adds separate verification steps.»
- «do not use subagents to verify or double-check your own work» — оба: migration-guide Opus 5.
  ⚠️ **Граница, которую обязан держать план:** речь про модель, перечитывающую собственный вывод.
  Независимое машинное свидетельство (скрипт, прогон, хук) под это НЕ подпадает.
- Ревью: «If your review prompt says "only report high-severity issues" or "be conservative," the
  model may follow that instruction literally and report less; ask it to report everything and
  filter in a separate pass instead.»
- Fable 5.1: «audit your prompt for instructions that suppress narration… system prompt lines such
  as "hold all findings for the final response." Remove lines like that.»
- Fable 5.1, один вызов инструмента за ход: «First privately list what you need next; then request
  every item that doesn't depend on another's result in this one response.»
- Fable 5.1, плотность прозы: «Mannered prose substitutes metaphor and flourish for direct
  statement… The fix is to say what you mean. When a literal phrase is available, use it.»
  Короткая форма: «Please remove all mannered prose.»
- «Instructions like "If in doubt, use [tool]" will cause overtriggering» — `prompting-claude-fable-5-1`.

## 3. Контекст и токены

- «target under 200 lines per CLAUDE.md file. Longer files consume more context and reduce adherence» — `code.claude.com/docs/en/memory`.
- «Bloated CLAUDE.md files cause Claude to ignore your actual instructions!» — `code.claude.com/docs/en/best-practices`.
- «Would removing this cause Claude to make mistakes? If not, cut it.» — там же.
- «Unscoped rules waste tokens by loading context during unrelated work.»
- «imported files still load and enter the context window at launch» — импорты контекст не экономят.
- Субагент возвращает «a condensed, distilled summary of its work (often 1,000-2,000 tokens)», но
  **грузит свою копию CLAUDE.md** — `anthropic.com/engineering/effective-context-engineering-for-ai-agents`.
- Скиллы: «Keep SKILL.md body under 500 lines»; при сжатии «Truncation keeps the start of the file,
  so put the most important instructions near the top of SKILL.md»; `disable-model-invocation: true`
  → «User-only skills have zero cost until invoked» — `docs/agent-skills/best-practices`.
- «Context must be treated as a finite resource with diminishing marginal returns.»

## 4. Инструменты и принуждение

- «An instruction like "never edit .env" in CLAUDE.md or a skill is a request, not a guarantee.
  A PreToolUse hook that blocks the edit is enforcement.» — `claude.com/blog/steering-claude-code…`
  (совпадает с главным принципом плагина).
- «More tools don't always lead to better outcomes… Too many tools or overlapping tools can also
  distract agents from pursuing efficient strategies.» — `anthropic.com/engineering/writing-tools-for-agents`.
- «If a human engineer can't definitively say which tool should be used in a given situation, an AI
  agent can't be expected to do better.» — там же.

## 5. Движок Claude Code (что появилось)

| Версия | Что |
|---|---|
| 2.1.219 | Opus 5 — дефолт алиаса `opus` (наши 12 «opus»-ролей уже на нём) |
| 2.1.248 | `experimental.cacheTtl: "1h"` во фронтматтере агента |
| 2.1.251 | Хуки `PreModelSwitch` / `PostModelSwitch` |
| 2.1.259 | `claude plugin validate --json` |
| 2.1.212 | параметр `mode` у Task депрекейтед |

## 6. Донор mattpocock/skills — формулировки, которые лучше наших

- «Steering by prohibition drags the forbidden behaviour into context and makes it **more**
  available, not less… Prompt the **positive**.»
- «Hunt no-ops sentence by sentence: an instruction the model already obeys by default pays load to
  say nothing.»
- «If you catch yourself reading code to build a theory before this command exists, stop… No
  red-capable command, no Phase 2.»
- «Finding facts is your job, never the user's… The decisions are the user's.»

## 7. Замерено лично в этой сессии (не из источников)

- 26 из 26 сторожей при подменённых `jq`/`python3` (заглушка exit 127) возвращают код 0.
  Прицельно: `secret-scan-write` в здоровой среде выдаёт BLOCK на боевой ключ в исходнике,
  при сломанном `jq` — **пустой вывод**, ключ проходит молча.
- Протоколов вызова сторожей три разных (`$1=cwd` / `$1=file` / `$1=file,$2=cwd`), стандарта нет.
- `--no-verify`: 176 упоминаний в 34 файлах живых проектов (вне репозитория плагина).
- Версии движка в проектах: 8 из 9 на `7.0`, плагин — `8.0.2`.
- Постоянный налог контекста: `~/CLAUDE.md` 368 строк, `CLAUDE.md` плагина 166, описания команд 10,8 КБ.
- `effort: max` у 24 ролей из 24; `disable-model-invocation` — у 0 команд из 29.
