# Research: Agentic Documentation Stack for OSPlus (2026)

| Field | Value |
|---|---|
| Date | 2026-04-04 (original), 2026-04-23 (refresh) |
| Scope | How OSPlus structures always-loaded context, on-demand expertise, and behavioral rules so AI coding agents (Cursor, Codex, Copilot, etc.) work productively across sessions. |
| Status | Decisions locked. Implementation in `AGENTS.md`, `.cursor/rules/`, `.cursor/skills/`, `.cursor/hooks.json`. |
| Re-evaluate when | Cursor's rule / hook / skill format changes meaningfully, AGENTS.md spec gets a v2, or a tool we use drops/adds support. |

This doc exists so the structure of OSPlus's agent-facing files is **defensible**, not just "the way it is." If a future agent (or future me) wants to change it, they should be arguing against this doc, not against vibes.

---

## Question 1 — Where should always-loaded project context live?

### Options considered

1. `README.md` — human-facing, but tools may or may not load it.
2. `.cursorrules` — Cursor-specific, legacy approach.
3. `CLAUDE.md` — Claude Code's native format.
4. `AGENTS.md` — open standard.
5. Some combination.

### What sources say

- **`agentsmd.io`** (canonical spec page, fetched 2026-04-04): AGENTS.md is "a dedicated file in your project root that guides AI coding agents." Plain Markdown, no required schema. Compatible with **GitHub Copilot, Cursor, OpenAI Codex, Google Jules, Aider**. ([agentsmd.io](https://agentsmd.io/))
- **`agentsmd.online` / vibecoding.app guide (2026)**: AGENTS.md emerged from collaboration between OpenAI, Google, Sourcegraph, Cursor, and Factory. Now stewarded by the Agentic AI Foundation under the Linux Foundation. Adopted by **60,000+ open-source repositories on GitHub**. **Featured in ThoughtWorks Technology Radar at "Trial" level (November 2025).**
- **Notable limitation**: Claude Code does **not** natively read AGENTS.md — it uses `CLAUDE.md`. (Several 2026 sources confirm this; OSPlus does not currently use Claude Code, so not blocking.)
- **Cursor docs** (cursor.sh/docs/rules): `.cursorrules` is the legacy approach; the recommended 2026 layout is `.cursor/rules/*.mdc` files with frontmatter for fine-grained attachment.

### Decision

**Single root-level `AGENTS.md` as the always-loaded project briefing.** Cross-tool (Cursor + Codex + Copilot + others) coverage with one file, native loading, no per-tool maintenance.

### What this rules out

- Maintaining `.cursorrules` AND `CLAUDE.md` AND `README.md`-as-instructions in parallel (drift inevitable).
- Putting agent instructions in `README.md` (fights its human audience purpose).
- Skipping AGENTS.md because "Cursor has rules" — rules don't auto-load on session start across tools the way AGENTS.md does, and they're Cursor-only.

### Open caveat

If we ever adopt Claude Code as a dev tool, we'll need a `CLAUDE.md` symlink or a duplicate. Not solving today.

---

## Question 2 — How should `.cursor/rules/` files be attached?

### Three attachment mechanisms

Per Cursor docs and 2026 community guides:

| Mechanism | Trigger | Reliability | Context cost |
|---|---|---|---|
| `alwaysApply: true` | Every Cursor session | Deterministic | Always-on (use sparingly) |
| `globs: [...]` | Auto-attaches when files matching pattern are touched | Deterministic *if globs are correct* | On-demand |
| `description: "..."` | Model decides based on description match | Probabilistic | On-demand |

### What sources say

- **skillsplayground.com guide (2026)**: keep rules under 500 lines; split larger rules; use `@-mentions` for cross-references; check rules into git.
- **localskills.sh blog (2026)**: most rules should be `alwaysApply: false` to avoid context bloat. Use `alwaysApply: true` only for "universal conventions that apply project-wide."
- **Glob anti-patterns** (multiple sources):
  - Too broad (`**/*`) → context pollution across all file types.
  - Too narrow (`components/*.tsx`) → misses nested directories.
  - Right shape: `mod/**/*.lua`, `**/*.{ts,tsx}` — recursive, file-type-scoped.

### Decision (tiered policy for OSPlus)

| Tier | Use `alwaysApply: true` for | Use `globs:` for | Use `description:` for |
|---|---|---|---|
| Examples | "OSPlus has these harnesses, don't reinvent." Learnings discipline. | Lua/BP boundary contract (auto-attach when touching `mod/**/*.lua`). Build pipeline notes (auto-attach to `build_dist.ps1` etc). | Rare workflows the model needs to opt into ("when authoring a new RE finding"). |
| Why | Must-know on turn 1. Cheap. | Loads exactly when relevant, costs nothing otherwise. | Lower reliability — keep for genuinely optional context. |

### What this rules out

- A single mega-rule with `alwaysApply: true` containing all conventions (context bloat, hard to maintain, agent has to re-read everything).
- Pure description-based rules for safety-critical guidance (description matching is probabilistic).
- Wide globs like `**/*` (every file in the repo would attach the rule — wastes tokens and dilutes signal).

---

## Question 3 — When to use Cursor *skills* vs. *rules*?

### Distinction

- **Rule** (`.mdc` in `.cursor/rules/`): policy or behavior. *"When you do X, do it this way."* Auto-attached based on context.
- **Skill** (`SKILL.md` in `.cursor/skills/<name>/`): expertise or knowledge. *"Here's how to be good at X."* Model-invoked based on description match.

### Decision

| Topic | Lives as | Why |
|---|---|---|
| "Don't reinvent OSPlus harnesses" | Rule (`alwaysApply: true`) | Behavior policy. Must apply on turn 1. |
| "Lua/BP boundary state ownership" | Rule (glob-attached) | Behavior contract. Auto-fires when touching mod files. |
| "How UE4SS Lua API works" | Skill | Reference expertise. Pulled in when actually needed. |
| "How to design a tool-calling agent" | Skill | Reference expertise. |
| "Findings-discipline (always log to docs/learnings/)" | Rule (`alwaysApply: true`) | Behavior policy. |

If a piece of content is **what the agent should do**, it's a rule. If it's **what the agent needs to know to do something well**, it's a skill.

### What this rules out

- Putting reference material in `alwaysApply: true` rules (token waste; agent doesn't need UE4SS API reference unless writing UE4SS code).
- Putting safety/policy guidance only in skills (skill invocation is probabilistic).

---

## Question 4 — How do we keep context alive across sessions?

This is the failure mode: agent starts a fresh chat, doesn't know about `build_dist.ps1`, reinvents a worse version. Validated as a real concern (see workflow discussion 2026-04-04).

### Layers of redundancy adopted

1. **`AGENTS.md` "Toolchain" section** — every script and what it does, one line each, pointer to deep-dive doc/skill. Always loaded by any AGENTS.md-aware tool.
2. **`harnesses.mdc` rule with `alwaysApply: true`** — short, deterministic backstop. Loaded by Cursor on every session. Single source of truth co-maintained with the AGENTS.md Toolchain section.
3. **Glob-attached deep-dive rules** — when the agent actually touches `build_dist.ps1`, a richer rule loads with history/gotchas.
4. **Skills for workflows the agent might need to *learn*, not just know exist** — `installer-packaging`, `sidecar-dev`, etc.
5. **Cold-start validation** — periodically test that a fresh session reaches for the right tools when given common requests. If it doesn't, the docs failed and get fixed before the gap propagates.

### What this rules out

- Relying on a single mechanism (any one layer can fail; the redundancy is the point).
- "We'll just remember to mention the tools" — discipline alone has a 100% failure rate over time.

---

## Adopted layout (concrete, post-refresh 2026-04-23)

```
AGENTS.md                          ← always-loaded project briefing (~80 lines)
.cursor/
  hooks.json                       ← v1 hooks: beforeShellExecution, afterFileEdit, stop
  hooks/
    block-mcp-commit.ps1           ← deny git commands that would commit mcp.json
    warn-hardcoded-path.ps1        ← flag F:\ paths added outside the scripts allowlist
    learnings-reminder.ps1         ← reminder on stop when branch != main & no learning staged
  rules/
    harnesses.mdc                  ← alwaysApply: true, "use existing scripts"
    learnings-discipline.mdc       ← alwaysApply: true, "log findings before done"
    code-conventions.mdc           ← alwaysApply: true, project-wide style
    git-workflow.mdc               ← alwaysApply: true, branches + commit style
    mod-architecture.mdc           ← globs: mod/**/*.lua (Lua/BP contract + three-bucket model)
    lua-conventions.mdc            ← globs: mod/**/*.lua (pcall + ref-drop discipline)
    node-conventions.mdc           ← globs: sidecar/**, server/**
    powershell-conventions.mdc     ← globs: **/*.ps1
  skills/
    feature-design/SKILL.md        ← design axes + trade-offs before code
    bug-investigate/SKILL.md       ← prior-art → reproduce → falsify → fix → learning
    release-checklist/SKILL.md     ← end-to-end build, validate, ship
    ue4ss-modding/
      SKILL.md                     ← compact overview + decisions
      references/
        lua-api.md                 ← full Lua API reference
        mod-actor-pattern.md       ← BPModLoaderMod + cooking/packaging
        pitfalls.md                ← crash matrix + debugging
docs/
  product.md                       ← product north star (audience/problem/wedge/anti-goals)
  ROADMAP.md                       ← what's next, filtered through the product lens
  decisions/                       ← ADR-based architectural deliberation
    README.md                      ← index + "when an ADR is required"
    _TEMPLATE.md                   ← ADR template (≥2 options required)
    _archive/
      vision-v1-superseded.md     ← prior "v1 locks" doc, archived 2026-04-23
  research/
    2026-agentic-stack.md          ← this file
    cold-start-scenarios.md        ← canonical validation prompts
  learnings/                       ← findings discipline lands here
  architecture/
    state-contract.md              ← Lua/BP boundary deep dive
  ops/
    deploy-relay.md                ← runbook
  UE_PROJECT_MIGRATION.md
```

## 2026-04-23 refresh — trims + gap coverage

A content-level audit found the structure sound but individual files bloated past their useful bounds. Changes:

### Skills — content alignment

- **Deleted `.cursor/skills/ue-ui-umg-slate/`** (C++ UMG/Slate for engine-integrated tools) and **`ue-serialization-savegames/`** (C++ USaveGame patterns). OSPlus does UE modding via UE4SS Lua and persists state on the relay — neither skill applied. They were generic UE material, not OSPlus-shaped.
- **Restructured `ue4ss-modding/`** from a single 304-line SKILL.md into a ~60-line `SKILL.md` (decisions + entry points) plus three on-demand references (`lua-api.md`, `mod-actor-pattern.md`, `pitfalls.md`). Progressive disclosure — the agent pays tokens for reference material only when it's writing UE4SS code.

### Rules — signal density

- `AGENTS.md` trimmed from ~114 lines to ~80: removed the in-repo directory listing (discoverable via `ls`) and principles that duplicated always-applied rules.
- `code-conventions.mdc`: collapsed "Comments WHY not WHAT" from a 25-line lecture to a 2-line assertion; removed the "No fabrication in comments" section (merged into `AGENTS.md` principle 2); dropped the "What is NOT in scope" meta-section.
- `lua-conventions.mdc`: removed the duplicated logging block (lives in `code-conventions.mdc`), removed the naming table (generic camelCase), dropped "What is NOT in scope". Preserved all load-bearing sections (`pcall` + ref-drop, cross-module callbacks, tick-loop discipline).
- `node-conventions.mdc`: same pattern — dropped logging dup, naming table, NOT-in-scope. Preserved wire-boundary validation and the SIGTERM lifecycle pattern (both load-bearing).
- `powershell-conventions.mdc`: dropped naming table, collapsed the `CmdletBinding` section to one sentence, dropped NOT-in-scope. Preserved `$ErrorActionPreference`, `$LASTEXITCODE`, `_lib.ps1` helpers, encoding, line endings, and the F:\ path policy.

### Hooks — deterministic backstops

New layer: `.cursor/hooks.json` with three project-level hooks. These are the *enforcement* layer that survives even when the agent's context is stripped:

- `beforeShellExecution` → `block-mcp-commit.ps1` — returns `permission: deny` for any `git add/commit/stash/checkout` that references `mcp.json`. The gitignore is the default defense; this is the belt.
- `afterFileEdit` → `warn-hardcoded-path.ps1` — logs a warning to Cursor's Hooks output channel when an edit adds an `F:\Omegamod|UE510|SteamLibrary` reference to a file outside the known scope-debt allowlist. Informational by design — surfacing the signal is the whole point; it doesn't block.
- `stop` → `learnings-reminder.ps1` — on task completion, if the current branch != `main` and `git status` shows no new/changed file under `docs/learnings/`, emits a reminder. Heuristic, not authoritative — exists because `learnings-discipline.mdc` is only as strong as the agent's compliance.

Hooks complement rules rather than replacing them: rules advise, hooks verify.

### Gap coverage — cold-start scenarios

Wrote `docs/research/cold-start-scenarios.md` — the validation canary that the original research committed to but never landed. Three canonical scenarios ("ship a build," "fix a chat bug," "add a new feature") with prompts, expected turn-1 actions, and red flags. Run after meaningful `AGENTS.md` / `harnesses.mdc` / toolchain changes.

### Rationale — why trim rather than restructure

The original 2026-04-04 research validated that the *layout* was correct (AGENTS.md + tiered rules + skills). What this refresh found was *density decay* inside individual files — meta-sections, duplicated prose, examples longer than the principle they illustrated. Those don't invalidate the structure; they bleed signal from it. Trim > rebuild.

## 2026-04-23 — product-foundation rebuild

A follow-up pass diagnosed that the agentic stack was healthy *structurally* but the project it served was **poorly defined at the product layer**, and architectural choices had been written as "locks" without recorded alternatives. Structure fix: separate the two concerns.

- **`docs/product.md` (new)** — product north star. Audience / problem / wedge / anti-goals / success / hard constraints. One screen. Read at session start.
- **`docs/decisions/` (new)** — architectural deliberation via ADRs. Each ADR requires ≥2 honest options — single-option ADRs are blocked. Enforced by `.cursor/rules/decision-discipline.mdc`.
- **`docs/vision.md` → `docs/decisions/_archive/vision-v1-superseded.md`** — the prior "v1 locks" doc is archived, preserved so future agents can see what was tried (and why it was retired).
- **`feature-design/SKILL.md` gains Phase 2.5** — ADR checkpoint. If a feature forces an architectural decision in any open-queue area, feature design stops and an ADR is drafted first.
- **`AGENTS.md` and `ROADMAP.md` rewritten** through the product lens. Both now point to `docs/product.md` as canon.

The meta-lesson: *the agentic stack compounds findings about the code (`docs/learnings/`) and choices about the architecture (`docs/decisions/`) as two different disciplines with two different writing modes.* Findings are post-hoc ("we learned X"); decisions are pre-lock ("we compared X and Y, chose Y because Z"). Prior state conflated them.

## What we're committing to maintain

Each of these is a recurring cost. Accepted deliberately:

1. **`AGENTS.md` Toolchain section ↔ `harnesses.mdc` parity.** When a script is added/changed/removed, both files update. Two places, both short, both next to the change.
2. **`docs/learnings/` entries before "done."** Every non-trivial finding lands here. Enforced by `learnings-discipline.mdc` + the `stop`-hook reminder.
3. **`docs/decisions/` ADRs before architectural commitment.** Every "this is now how we do X" earns an ADR with ≥2 real options. Enforced by `decision-discipline.mdc` + the `feature-design` Phase 2.5 checkpoint.
4. **Cold-start validation after meaningful `AGENTS.md`, `harnesses.mdc`, product/decision, or toolchain changes.** See `docs/research/cold-start-scenarios.md`. If a scenario fails, the docs failed.
5. **Hook scripts stay short (< 40 lines each).** Hooks run on every tool use / edit / stop — PowerShell startup is non-zero. If a hook grows complex, rethink whether the guidance belongs as a rule instead.
6. **Re-evaluate this research yearly** or when a triggering signal appears (see header).

## Sources cited

| # | Source | Type | Date checked |
|---|---|---|---|
| 1 | [agentsmd.io](https://agentsmd.io/) | Canonical spec page | 2026-04-04 |
| 2 | agentsmd.online | Reference site | 2026-04-04 (via search summary) |
| 3 | [vibecoding.app — AGENTS.md Guide 2026](https://vibecoding.app/blog/agents-md-guide) | Synthesis blog | 2026-04-04 (via search summary) |
| 4 | [Cursor Rules docs](https://cursor.sh/docs/rules) | Tool documentation | 2026-04-04 (via search summary) |
| 5 | [skillsplayground.com — Cursor Rules Guide 2026](https://skillsplayground.com/guides/cursor-rules/) | Synthesis blog | 2026-04-04 (via search summary) |
| 6 | localskills.sh — Cursor Rules Guide 2026 | Synthesis blog | 2026-04-04 (via search summary) |
| 7 | [SOTAAZ blog — CLAUDE.md vs .cursorrules vs AGENTS.md](https://blog.sotaaz.com/post/ai-coding-rules-guide-en) | Comparison article | 2026-04-04 (via search summary) |
| 8 | [The Prompt Shelf — AGENTS.md vs CLAUDE.md (2026)](https://thepromptshelf.dev/blog/agents-md-vs-claude-md) | Comparison article | 2026-04-04 (via search summary) |

Primary source for the AGENTS.md decision is #1 (canonical spec). Primary source for Cursor rules mechanics is #4 (tool docs). The blog sources are synthesis — used to confirm the canonical sources said what we think they said and that 2026 community practice matches.
