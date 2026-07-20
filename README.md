# Vibe Dev v8

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

The number of mechanisms and their live status live in [`docs/traceability.md`](docs/traceability.md)
— the single source of truth (**67 tracked** today; some rows are honestly marked as discipline
or a display-only layer — the on-screen jargon catcher, the secret-output mask, the `/checkpoint`
nudge — and are **not** counted as enforcement). Each mechanism carries three attributes:
*where it's defined / what enforces it / what happens if you try to bypass it*. The plugin's
self-check verifies completeness — a claim without a live mechanism doesn't pass.

**New in v8:** feature history became append-only (provenance as an event log), context unloading
became a deliberate `/checkpoint` instead of the roulette of auto-compaction, and the verifying
agent is *physically* denied the right to write code. **v7** added auto-memory (a snapshot before
compaction + a return brief), a browser tester that looks at the page with its own eyes, and
secret locks. Every new guard was verified with live runs on the Claude Code 2.1.x engine — the
verification date is recorded in each mechanism's row.

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
automatically** on install (Claude Code v2.1+) — no manual wiring. Some posts sit *outside* the
plugin, in the project's `git pre-commit` — they keep working even if the plugin is removed.
Strictness is per-project: `minimal` / `standard` / `strict` (existing projects aren't broken —
they're migrated with `/upgrade-project`, softly if needed: `--soft`).

---

## What it catches (key mechanisms)

### A. "Done" means verified, not claimed
| Mechanism | What it catches | What it does |
|---|---|---|
| **UI-evidence gate** | a UI feature is marked "done" on typecheck/tests, but a real click shows nothing | **block** (a screenshot / live run is required) |
| **Surface-aware evidence** (v6.2) | a "no-UI" feature (API / scheduled job / CLI) is closed with no trace of a real call; a UI feature hides as a "library" | the surface is inferred from files and can only tighten: ui → **block**, others → **warn** with an acceptance recipe |
| **Runtime evidence on logic + negative gate** (v8) | green tests lie: a logic feature is closed on typecheck alone; a medium/large one ships with no "what if we break it" check | passing with no trace of a real run → **block**; M/L without a mutation or leak check → **block** |
| **Adversarial fresh-context verifier** (v8) | the same agent both writes the code and "confirms" it works | the verifier runs in *assume broken until proven* mode and is **physically denied write access** (the engine forbids it Write/Edit) |
| **Test-strategy before build** | a medium/large feature goes into work without a thought-through verification plan | **block** (no `docs/test-strategy.md` → it can't enter `active`) |
| **Detailing stage** (v8) | a large feature is dragged into work "verbally," with no broken-down plan | an M/L feature can't enter work without `docs/changes/<id>/proposal.md` carrying a prioritized user story in Given/When/Then → **block** |
| **Data-model review gate** | a DB schema is written without a separate critical review (the model "freezes," reworks are expensive) | **block** (no `docs/data-model-review.md` → it can't enter `active`) |
| **State-machine transitions** | a feature jumps to an invalid state / a corrupted state file | **block** (current project) / warn (legacy) |

### A2. Hook activation as a provable fact (v6.2)
| Mechanism | What it catches | What it does |
|---|---|---|
| **Heartbeat** | hooks "look installed" but don't physically run (silent strictness theater) | every live event writes a stamp with the version; readers check freshness |
| **Two-phase profile** | profile says "strict" but enforcement never turned on | bootstrap writes `pending-strict`; only a live hook promotes it to real `strict` — the promotion *is* the proof |
| **Git pre-commit backstop** | the plugin was removed/broken and nobody noticed | an INDEPENDENT post in `.git/hooks`: a pending profile or stale heartbeat → **block** the commit |
| **Fail-loud + crash artifacts** | a guard crashed and silently "allowed everything" (a real bug, 2026-06-06) | crash → loud warning + crash log + a probe at session start |
| **Real-shape fixture corpus** | a gate green on synthetic data, broken on real files | self-check runs gates against 6 anonymized real `feature_list` files |
| **`/doctor`** | "why are the guards silent?" | self-diagnosis: profile / heartbeat / crashes / install + a fix table |

### A3. Feature history can't be rewritten (provenance, v8)
| Mechanism | What it catches | What it does |
|---|---|---|
| **Append-only event log** | history is edited or erased after the fact | an edited/removed log line → **reject** the commit |
| **Requirement-edit invariant** | a feature's requirement (name, description, size, business invariant) is silently rewritten, or the feature is "cancelled" with no trace | an edit with no covering history event → **reject** the commit; ordinary work progress (active → verified → done) stays free |
| **Crash-safe writer** | an interruption mid-write tears the state apart | the single write path commits log then head in a safe order: an interruption is replayable, not lost |
| **Archive by reference + evidence hash** | finished features bloat the hot file, and the "done" evidence can be swapped | the body moves to an archive, a one-line reference stays in the working file; the hash is verified at commit time **without loading the body into context** |
| **Open-tasks gate at ship** | a feature is archived with unfinished items inside | archiving → **block** until the tasks are closed |

### A4. Context under control, not up to luck (v8)
| Mechanism | What it catches | What it does |
|---|---|---|
| **Deliberate `/checkpoint`** | state lives only in the conversation — auto-compaction eats it at a random moment | checkpoint on command: provenance recovery → archive what's finished → **cold-start gate**: a templated or stale `SESSION.md` / incoherent history → **block** completion |
| **Three-tier context** | the body of a finished feature sits in the hot file forever | hot ≤200 lines (head + index) / on demand via search / cold = archive; a bloated hot file → **warn** at commit |
| **Narrowed returns from reading agents** | a research subagent dumps raw material into the main thread and eats the context | full result to a file, a ≤2 KB digest + path into the thread (critics' opinions are never trimmed) |
| **Pre-compaction snapshot** (v7) | auto-compaction happened anyway — facts were lost | before compaction a digest of FACTS is saved (not a "done" status); on return, a brief with "check the files, don't trust your memory of what's finished" |

### B. Safety and money
| Mechanism | What it catches | What it does |
|---|---|---|
| **Bulk-API gate** | a mass external-API job with no limit check (real case: a project banned for 2 days + wasted money) | **block** without a pre-launch checklist (the checklist now requires explicit volume × price) |
| **Model-swap guard** | an edit introduces a model / setting that affects every answer (real case: 3 days of dropped client replies after "newer = drop-in") | **warn** "this is a contract change, run a smoke test" |
| **Vendor-lock research gate** | a specific provider is hard-wired into the architecture blindly, with no comparison | **block** an integration feature without `docs/research/*.md` |
| **Hardcoded live key** (v7) | a production key is written straight into source and rides into git | writing a file with a live key → **block**; lifted only by an explicit user phrase |
| **Secret-in-prompt** (v6.2) | the user pasted a live key into a message | **warn**: the key is compromised → rotate + move to `.env` |
| **Secret-in-output** (v6.2) | a CLI printed a token — it lingers in the session context | **warn** to the model: don't reuse the literal, suggest rotation (+ output masking on engines that support it) |
| **Writes outside the project root** (v7→v8) | the agent writes a file past the project, into someone else's folder | **warn** + a log entry; the corpus accumulates toward a future block |
| **Concurrent-write advisory** | two sessions write to one file (real case: data loss) | **warn** (advisory) |

### C. Anti-stall
| Mechanism | What it catches | What it does |
|---|---|---|
| **User stop-signal** | the human writes "wrong way / stop / that's not it" and the agent keeps grinding tactically | **inject** "change the *level*, not the method; launch a diagnostic subagent" |
| **Interrupt-recovery** (v6.2.1) | a dropped connection (closed laptop lid) or an inbound message kills the running tool — the system falsely logs "user rejected," and the agent stalls for hours | the next message without a stop-word → **inject** "that was a disconnect, not a veto — continue the plan"; a real "stop" keeps its force |
| **Repeated-failure detector** | the same command is launched a 3rd time in a row with no success and no structural change | **warn** before running: prompt for a diagnostic subagent |
| **Circuit breaker** (v7) | even at double the repeat threshold the agent keeps grinding the same thing | a hard escalation into `/stuck` — stalling stopped being a matter of discipline |
| **Tier escalation** (v8) | the cheaper model failed twice and is asked a third time | the order: 2 failures → raise the tier, don't retry; an LLM quorum only if the top tier failed too |

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
| **Config-protect** (v6.2, hardened in v8) | the agent weakens its own gates (profile, heartbeat, "learn" mode, disabling) | **block** in all profiles, including bypasses via copy/move/rename; loosening strictness is the user's manual action only |
| **Wave-continue** (v7) | you said "don't stall, go to the end" and the turn ends with yet another technical question | **inject** "don't ask the technical question, continue; leave the business fork" |
| **Handoff loop** | at session close the plan stays in the chat (the next session won't see it) | **inject** a cold-start checklist + detect a missed handoff at startup |
| **User rules (`/hookify`)** | "never do X again" is forgotten and repeated | the human freezes a correction into a permanent **block/warn** rule, no code needed |

### F. Harness infrastructure
| Mechanism | What it does |
|---|---|
| **Hooks out of the box** | `hooks.json` auto-loads on install; with no file you can't "forget to turn it on" |
| **Warnings reach the model** | warnings travel on the correct channel (otherwise they'd be silently lost) |
| **Profiles + version lifecycle** | minimal/standard/strict; legacy projects aren't forced, they migrate on command (`/upgrade-project`, soft mode `--soft`, preview `--dry-run`) |
| **Single path resolver** (v8) | one source for state-file names + root lookup up the tree; an ambiguous root → refuse instead of quietly writing to the wrong place |
| **Model pins per stage** (v8) | the role registry is the source of truth: the top tier for planning/critique/verification, the working tier for code/reading; drift from the registry fails the self-check |
| **One readiness number in `/audit`** (v8) | project health = the MINIMUM across the bottleneck (not an average), with deterministic history-integrity metrics |
| **Traceability table + self-check** | every mechanism is described by 3 attributes; a row without a live mechanism fails the self-check |
| **Personal-data gate** | if anything personal slips into the public build (email / client project / private path) — **block** the self-check |

> **Honest — what's still discipline, not a mechanism:** checking cross-module wiring on the
> real path, "the agent does it itself instead of sending you to the terminal," realistic test
> data, the `/checkpoint` nudge by session length and the per-feature effort budget (Claude Code
> has no reliable context-window sensor yet — we don't claim a signal that doesn't exist). A hook
> can't reliably force these. We keep them as discipline + catch them on real projects. We don't
> pass them off as "bulletproof."

Built **after auditing all ~20 real projects** from earlier versions (12 retrospectives + ~150
memory notes + 6 bug journals); v6.2 followed an **audit of 54 live sessions**; v7 an **audit of
9 live session journals**; v8 was built from the owner's decisions (12 cards) + donor patterns
(pilotfish / OpenSpec / spec-kit) + the **first rollout of the harness onto a live production
project**, which produced 4 targeted fixes (v8.0.2).

---

## 7 subsystems

**Instructions** (CLAUDE.md routing + domain-rules.yaml) · **State** (feature_list.json +
SESSION.md + provenance log + error-journal) · **Verification** (4 layers + dual critique +
negative gate + an independent verifier) · **Scope** (affected_files, WIP=1) ·
**Lifecycle** (init, cold-start, `/checkpoint`, clean-exit, `/upgrade-project`) ·
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
| `/checkpoint` | Deliberate state persistence + context unloading (instead of the auto-compaction roulette) |
| `/hookify` | "never do X again" → a permanent block/warn rule |
| `/doctor` | Self-diagnosis: are the guards alive in this project |
| `/handoff` · `/end-session` | Clean exit + persist state into files |
| `/audit` | External harness assessment + one readiness number |
| `/stuck` | Stuck protocol + an LLM quorum |
| `/ship` | Final validation ≥90% + retrospective |
| `/upgrade-project` · `/patch-projects` | Migrate live projects onto the current engine (soft or strict) |
| `/research` · `/architecture` · `/dev-plan` · … | full list — 29 commands in `skills/` |

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

> The plugin's technical id is `vibe-dev` (command names and install depend on it). Version: **8.0.2**.

---

## Version

**v8.0.2** — four fixes from the first rollout of the harness onto a live production project:
the migration skill caught up with its code, harness runtime files no longer dirty git, the
model-swap guard stopped firing on prose, and the reference-only transition graph is now
honestly labeled as reference-only.

**v8.0.1** — a core defect fix (ordinary work progress was mistaken for a requirement edit and
rejected the very first commit after verification) + a safe migration path for live projects:
soft mode `--soft`, an honest `--dry-run` preview, and the `/patch-projects` orchestrator.

**v8.0.0** — nine waves, 26 features, **67 mechanisms**. Five lines: feature provenance as an
event log (append-only history + archive by reference with an evidence hash); a detailing stage
for large features; a deliberate `/checkpoint` instead of the auto-compaction roulette + a
three-tier context model; model pins per stage and an independent verifier with no write access;
"done" proven by a real run + a negative gate. Deliberately **not** in the core (honest claims):
a context-size sensor — the engine has no reliable signal for it.

**v7.0.0** — five waves from an audit of live session journals: delivering fixes into live
projects, honesty of claims (dead mechanisms removed from the count), auto-memory (pre-compaction
snapshot + return brief), new locks (secrets, writes outside the root), and a behavioral layer
("don't stall"). The browser tester was given the duty to take a screenshot and describe what it
actually sees.

_v6.2 — enforcement as a provable fact (provable hook activation, fail-loud, clarity gate on the
final message). v6.1 — public release: enforcement from text into mechanism + onboarding.
Full change list — [`CHANGELOG.md`](CHANGELOG.md)._

---

## Notes

- The harness was built for, and currently converses in, **Russian** (its clarity gates and
  prompts are Russian-language). The methodology, mechanisms, and pipeline are
  language-agnostic; UI/interface localization is not done yet.
- Author: Andrei Tsyhan.
