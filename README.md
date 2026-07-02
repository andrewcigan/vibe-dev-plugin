# Vibe Dev v6

> 🌐 **English:** this file · **Русский:** [README.ru.md](README.ru.md)

**A harness-first plugin that turns a business idea into a shipped product — for founders who build with Codex and Claude Code.**

Vibe Dev is built for entrepreneurs who don't write code but ship real products with AI
agents. You stay at the level of business and architecture; the agent makes the technical
decisions and does the work. The point of the plugin is to make the agent *reliable* — so
"done" means done, not "the code compiled."

> ## "The harness is enforcement, not documentation."
> Every principle is backed by a **real mechanism** (hook / gate / agent / self-check), not a
> line in an instruction file that the agent can quietly ignore. Discipline is broken by
> exactly the link that's supposed to keep it — the agent itself. So the rules are turned into
> checkpoints that are actually enforced.

The number of mechanisms and their live status live in `docs/traceability.md` — the single
source of truth (42 tracked today; 2 of them — the screen-layer jargon catcher and the
secret-output mask — are honestly marked display-only/partial, i.e. **not** real enforcement).
Each mechanism carries three attributes: *where it's defined / what enforces it / what happens
if you try to bypass it*. The plugin's self-check verifies completeness — a claim without a live
mechanism doesn't pass.
New in v6.2: **hook activation became a provable fact** (a guard that "didn't turn on" can no
longer stay silent), and **clarity of the final message** went from a wish to a blocking gate.
Every new guard was verified with live runs on the Claude Code 2.1.170 engine.

---

## Who it's for

- **Founders and non-engineers** who want to ship a working product, not learn to code.
- People who already work with **Codex** and **Claude Code** and want the agent to behave like
  a disciplined senior engineer instead of an eager intern.
- Anyone tired of agents that declare "done" on code that was never actually run.

You describe the business. The agent picks the stack, writes the code, tests it, and only
reports "done" when a verification command passed and the behavior matched expectations.

---

## How it works (the harness in plain words)

An AI coding agent announces key moments: "about to save a file," "about to run a command,"
"showing a message to the human," "opening/closing a session." The plugin **attaches small
inspectors to those moments** (hooks). Each inspector looks at the *intent* and returns one
verdict:

- **block** — the action is cancelled (e.g. you can't mark a feature "done" without evidence);
- **warn / inject** — the action proceeds, but a note appears for the agent or a flag for the human;
- **pass** — all clear, stay silent.

The map of "on this event, call this inspector" lives in `hooks/hooks.json` and is **loaded
automatically** on install (Claude Code v2.1+) — no manual wiring. Strictness is per-project:
`minimal` / `standard` / `strict` (existing projects aren't broken — they're migrated with
`/upgrade-project`).

---

## What it catches (key mechanisms)

### A. "Done" means verified, not claimed
| Mechanism | What it catches | What it does |
|---|---|---|
| **UI-evidence gate** | a UI feature is marked "done" on typecheck/tests, but a real click shows nothing | **block** (a screenshot / live run is required) |
| **Surface-aware evidence** (v6.2) | a "no-UI" feature (API / scheduled job / CLI) is closed with no trace of a real call; a UI feature hides as a "library" | the surface is inferred from files and can only tighten: ui → **block**, others → **warn** with an acceptance recipe |
| **Test-strategy before build** | a medium/large feature goes into work without a thought-through verification plan | **block** (no `docs/test-strategy.md` → it can't enter `active`) |
| **Data-model review gate** | a DB schema is written without a separate critical review (the model "freezes," reworks are expensive) | **block** (no `docs/data-model-review.md` → it can't enter `active`) |
| **State-machine transitions** | a feature jumps to an invalid state / a corrupted state file | **block** (current project) / warn (legacy) |

### A2. Hook activation as a provable fact (new in v6.2)
| Mechanism | What it catches | What it does |
|---|---|---|
| **Heartbeat** | hooks "look installed" but don't physically run (silent strictness theater) | every live event writes a stamp with the version; readers check freshness |
| **Two-phase profile** | profile says "strict" but enforcement never turned on | bootstrap writes `pending-strict`; only a live hook promotes it to real `strict` — the promotion *is* the proof |
| **Git pre-commit backstop** | the plugin was removed/broken and nobody noticed | an INDEPENDENT post in `.git/hooks`: a pending profile or stale heartbeat → **block** the commit |
| **Fail-loud + crash artifacts** | a guard crashed and silently "allowed everything" (a real bug, 2026-06-06) | crash → loud warning + crash log + a probe at session start |
| **Real-shape fixture corpus** | a gate green on synthetic data, broken on real files | self-check runs gates against 6 anonymized real `feature_list` files |
| **`/doctor`** | "why are the guards silent?" | self-diagnosis: profile / heartbeat / crashes / install + a fix table |

### B. Safety and money
| Mechanism | What it catches | What it does |
|---|---|---|
| **Bulk-API gate** | a mass external-API job with no limit check (real case: a project banned for 2 days + wasted money) | **block** without a pre-launch checklist (the checklist now requires explicit volume × price) |
| **Model-swap guard** | an edit introduces a model / setting that affects every answer (real case: 3 days of dropped client replies after "newer = drop-in") | **warn** "this is a contract change, run a smoke test" |
| **Vendor-lock research gate** | a specific provider is hard-wired into the architecture blindly, with no comparison | **block** an integration feature without `docs/research/*.md` |
| **Secret-in-prompt** (v6.2) | the user pasted a live key into a message | **warn**: the key is compromised → rotate + move to `.env` |
| **Secret-in-output** (v6.2) | a CLI printed a token — it lingers in the session context | **warn** to the model: don't reuse the literal, suggest rotation (+ output masking on engines that support it) |
| **Concurrent-write advisory** | two sessions write to one file (real case: data loss) | **warn** (advisory) |

### C. Anti-stall
| Mechanism | What it catches | What it does |
|---|---|---|
| **User stop-signal** | the human writes "wrong way / stop / that's not it" and the agent keeps grinding tactically | **inject** "change the *level*, not the method; launch a diagnostic subagent" |
| **Interrupt-recovery** (v6.2.1) | a dropped connection (closed laptop lid) or an inbound message kills the running tool — the system falsely logs "user rejected," and the agent stalls for hours | the next message without a stop-word → **inject** "that was a disconnect, not a veto — continue the plan"; a real "stop" keeps its force |
| **Repeated-failure detector** | the same command is launched a 3rd time in a row with no success and no structural change | **warn** before running: prompt for a diagnostic subagent (carrier verified against the live 2.1.170 event model) |

### D. Plain language (the non-engineer's biggest pain)
| Mechanism | What it catches | What it does |
|---|---|---|
| **Clarity gate on the final turn** (v6.2) | the turn ends with a person-days estimate or heavy jargon outside code blocks | **block**: the agent must add a plain-words version (≤10 lines); precision is held by a labeled corpus from real sessions + append limits |
| **Jargon catcher (screen layer)** | jargon / a fork with no "what you lose" / person-days in any message | **on-screen flag + a log metric** (honestly display-only; on Desktop the event doesn't fire — the load-bearing layer is the gate above) |
| **Onboarding (`/setup`)** | the system doesn't know how to talk to a new user | a portrait at `~/.vibe-dev/portrait.md` → gate strictness and fork format adapt (no portrait → a neutral default) |

### E. Process discipline
| Mechanism | What it catches | What it does |
|---|---|---|
| **WIP=1 / scope** | edits spill outside the declared feature | **block** the commit (diff ⊆ affected_files) |
| **Intent-without-action** | the agent ends a turn saying "I'll now do X" with no action taken | **block** (continue the turn) |
| **Unified Stop dispatcher** (v6.2) | several end-of-turn guards cascade blocks and loop the turn | priorities + a shared cap of ≤3 blocks per turn; overflow → pass with a log entry |
| **Architecture research gate** (v6.2) | architecture is written without studying best practices and existing solutions | **block** writing `ARCHITECTURE*.md` without `docs/research/*`; the skip is allowed ONLY by an explicit user phrase |
| **Closing mode** (v6.2) | "let's close the session" → the agent suddenly starts coding | rights degrade: writes only to state files; new work → backlog; lifted by a normal next message |
| **Lock pattern** (v6.2) | the agent fakes "user consent" markers (skip / closing) | `.harness/locks/*` markers are written ONLY by hooks on an explicit phrase — an agent write is **block** |
| **Config-protect** (v6.2) | the agent weakens its own gates (profile, heartbeat, disabling) | **block** in all profiles; disabling enforcement is the user's manual action only |
| **Handoff loop** | at session close the plan stays in the chat (the next session won't see it) | **inject** a cold-start checklist + detect a missed handoff at startup |
| **User rules (`/hookify`)** | "never do X again" is forgotten and repeated | the human freezes a correction into a permanent **block/warn** rule, no code needed |

### F. Harness infrastructure
| Mechanism | What it does |
|---|---|
| **Hooks out of the box** | `hooks.json` auto-loads on install; with no file you can't "forget to turn it on" |
| **Warnings reach the model** | warnings travel on the correct channel (otherwise they'd be silently lost) |
| **Profiles + version lifecycle** | minimal/standard/strict; legacy projects aren't forced, they migrate on command |
| **Traceability table + self-check** | every mechanism is described by 3 attributes; a row without a live mechanism fails the self-check |
| **Personal-data gate** | if anything personal slips into the public build (email / client project / private path) — **block** the self-check |

> **Honest — what's still discipline, not a mechanism:** checking cross-module wiring on the
> real path, "the agent does it itself instead of sending you to the terminal," realistic test
> data. A hook can't reliably force these. We keep them as discipline + catch them on real
> projects. We don't pass them off as "bulletproof."

Built **after auditing all ~20 real projects** from earlier versions (12 retrospectives + ~150
memory notes + 6 bug journals); v6.2 followed an **audit of 54 live sessions** on v6.1 + harness
practice research + an independent critique of the plan.

---

## 7 subsystems

**Instructions** (CLAUDE.md routing + domain-rules.yaml) · **State** (feature_list.json +
SESSION.md + error-journal) · **Verification** (4 layers + dual critique + negative gate) ·
**Scope** (affected_files, WIP=1) · **Lifecycle** (init, cold-start, clean-exit, /upgrade) ·
**Learning** (feedback memory, retrospectives, anti-patterns) · **Cost & Safety** (bulk-gate,
concurrent-lock, secrets-scope).

---

## Commands

| Command | What it does |
|---|---|
| `/setup` | Onboarding: 6 simple questions → a portrait (how to talk to you) |
| `/new-project` | Business interview + bootstrap the harness (4 files at start) |
| `/resume <project>` | Cold-start test + diff against the previous session |
| `/feature <id>` | WIP=1 + dual critique (test-researcher + user-perspective-critic) |
| `/verify` | 4-layer verification (syntax + runtime + e2e + user) |
| `/hookify` | "never do X again" → a permanent block/warn rule |
| `/handoff` · `/end-session` | Clean exit + persist state into files |
| `/audit` | External harness assessment + error rate |
| `/stuck` | Stuck protocol + an LLM quorum |
| `/ship` | Final validation ≥90% + retrospective |
| `/research` · `/architecture` · `/dev-plan` · `/upgrade-project` | … (full list in `skills/`) |

## Pipeline

- **FAST (5 stages)** — internal tools, simple MVPs, bots:
  interview → architecture + stack → design handoff (if UI) → `/feature` loop → `/ship`.
- **FULL (10 stages)** — products going to market: ideas R1/R2 → validation → research →
  architecture + prototype → design → wave plan → `/feature` loop → `/ship` + marketing launch.

---

## Install

### Claude Code
```bash
# 1. Add the marketplace from GitHub
claude plugin marketplace add andrewcigan/vibe-dev-plugin
# 2. Install and enable the plugin
claude plugin install vibe-dev@vibe-dev
```
Or locally (for developing the plugin itself):
```bash
claude --plugin-dir "/path/to/vibe-dev-plugin"
```
In Claude Code you get the full harness: auto-loaded hooks, the slash commands above, and
profile-based strictness.

### Codex
Codex reads `AGENTS.md` automatically. Point it at the harness:
```bash
git clone https://github.com/andrewcigan/vibe-dev-plugin
# then run Codex with the repo's AGENTS.md as your project rules
```
In Codex the harness drives the agent through `AGENTS.md`, the domain rules, the state files,
and the methodology — the same principles and workflow, applied as the agent's operating
instructions.

> The plugin's technical id is `vibe-dev` (command names and install depend on it). Version: **6.2.1**.

---

## Version

**v6.2.1** — Interrupt-recovery: a technical interruption (client disconnect / message delivery)
no longer paralyzes the agent into "waiting for instructions" — the next prompt without a
stop-word continues the plan automatically.

**v6.2.0** — Enforcement as a provable fact (37 mechanisms): provable hook activation (heartbeat
+ two-phase profile + independent git pre-commit backstop + `/doctor`), fail-loud (a crashed
guard can't stay silent), clarity gate on the final message, surface-aware evidence, mandatory
research before architecture, closing mode, secret hygiene, config-protect. Every new guard was
verified with live runs on the 2.1.170 engine. Built from an audit of 54 live v6.1 sessions.
Full change list — [`CHANGELOG.md`](CHANGELOG.md).

_v6.1.0 — public release: enforcement from text into mechanism (20 mechanisms) + onboarding
(`/setup`) + personal-data gate, after an audit of ~20 real v5 projects._

---

## Notes

- The harness was built for, and currently converses in, **Russian** (its clarity gates and
  prompts are Russian-language). The methodology, mechanisms, and pipeline are
  language-agnostic; UI/interface localization is not done yet.
- Author: Andrei Tsyhan.
