# Cold-start scenarios for OSPlus agents

| Field | Value |
|---|---|
| Date | 2026-04-23 |
| Scope | Canonical prompts a fresh AI session (no prior context) must handle correctly. Validates that `AGENTS.md`, `.cursor/rules/`, and skills reach the right tools on turn 1. |
| Cadence | Run after every meaningful change to `AGENTS.md`, `harnesses.mdc`, or the toolchain. |
| Committed by | `docs/research/2026-agentic-stack.md` → "Layers of redundancy" → item 5 ("Cold-start validation"). |

Purpose: the compound failure mode we're defending against is — fresh chat, agent doesn't know `build_dist.ps1` exists, invents a worse version. Silent docs-decay. These scenarios are the canary.

## How to run

1. Start a fresh chat with zero context pre-loaded (new conversation, no recent file edits in scope).
2. Paste one of the prompts below verbatim.
3. Compare the agent's first 1–3 tool calls (or first response if no tool use) against the pass/fail criteria.
4. If any scenario fails: **that's the docs failing, not the agent**. Fix `AGENTS.md` / rules / skills so the signal is there. Re-run.

## Scenario 1 — "Ship a build"

**Prompt:**
> "I want to cut a new OSPlus release for users to download. Walk me through what we need to do."

**Expected early actions (any one is a pass):**
- References / reads `cursor/skills/release-checklist/SKILL.md` (the workflow skill is the entry point).
- References `build_dist.ps1` as the distribution builder and notes it refuses to build without `OSPlus.pak`.
- Notes that cooking is manual in the UE editor and that `/Game/Mods/OSPlus` must be in *Additional Asset Directories to Cook*.

**Red flags (fail):**
- Proposes writing a new build script from scratch.
- Skips the cook step and tries to build `OSPlus.zip` directly from Lua sources.
- Invents a `dist` folder structure instead of pointing at the real one.

**Why this scenario:** "Ship a build" exercises the toolchain knowledge AGENTS.md is structured around. If the agent can't reach `release-checklist` + `build_dist.ps1`, the Toolchain section isn't doing its job.

## Scenario 2 — "Fix a chat bug"

**Prompt:**
> "Players report that after they leave a match and rejoin, the chat stops sending. No crash, just silent. How do we debug this?"

**Expected early actions:**
- Invokes or reads `cursor/skills/bug-investigate/SKILL.md`.
- Greps or reads `docs/learnings/` for prior art (chat-match-detection-via-seed, sidecar-reconnect, room-change lifecycle, etc.).
- Identifies that map transition invalidates cached UObject refs → points at `chat.lua:reset()` and the ref-drop pattern in `lua-conventions.mdc`.
- Distinguishes between "Lua-side logic bug" and "sidecar ↔ relay disconnect" as two separate hypotheses before picking one.

**Red flags (fail):**
- Starts proposing code changes before searching `docs/learnings/`.
- Wraps more `pcall` around existing code without understanding that `pcall` doesn't catch native access violations.
- Suggests adding a new `LoopAsync` for a "retry" without checking `main.lua`'s existing tick loop.

**Why this scenario:** bugs are the most common work. `bug-investigate` is the highest-leverage skill because it front-loads prior-art search. If it doesn't fire, we pay the debug tax twice.

## Scenario 3 — "Add a new feature"

**Prompt:**
> "I want to add persistent user profiles — things like a display name override and a badge. Where does this live and what do I build first?"

**Expected early actions:**
- Invokes or reads `cursor/skills/feature-design/SKILL.md`.
- **Reads `docs/product.md` first** — profiles are the wedge; the feature request aligns but the agent should confirm it against audience, wedge shape, and anti-goals rather than assume.
- **Scans `docs/decisions/` for accepted ADRs** — profiles touch identity (first-priority ADR queue), profile storage (first-priority), and potentially schema-grows-on-demand policy.
- Hits the ADR checkpoint (Phase 2.5 of feature-design): **recognizes that this feature forces decisions in two open ADR areas — identity model and profile storage architecture — and STOPS feature design to propose drafting those ADRs first.**
- Surfaces the correct question to the user: "Do you want me to draft the ADRs for identity and profile storage, or treat the archived `vision.md` direction as decided for this work?"
- Surfaces the Lua/BP boundary question: profile *fetch* is operational (Lua owns) but the *display* of the profile is UI-reactive (BP owns). Function-call boundary, not a duplicated state store.

**Red flags (fail):**
- Proceeds to propose architecture (storage, identity, schema) without hitting the ADR checkpoint — the prior "locks"-as-canon failure mode, now at a new address.
- Reads `docs/decisions/_archive/vision-v1-superseded.md` and treats its "locks" as current commitments. The archive header is explicit that they are not.
- Invents a schema with fields the prompt didn't justify (violates the preserved "schema grows on demand" policy).
- Proposes a new standalone Node service for profiles *without* recognizing that process-model is exactly what the profile-storage ADR is meant to decide.
- Stores display name on disk in the client sidecar (violates the shape of the archived Lock 4 *and* sidesteps the ephemeral-state ADR).
- Skips `docs/product.md` entirely. Skips `docs/decisions/` entirely.

**Why this scenario:** new features are where architectural drift happens fastest. Under the old regime the vulnerability was "four locks get skipped." Under the new regime the vulnerability is "the ADR checkpoint gets skipped and the agent silently defaults to whatever the archive said." This scenario tests whether `feature-design` Phase 2.5 actually fires when it should and whether the agent correctly distinguishes accepted ADRs (canon) from archived pre-ADR material (not canon).

## Running the validation — heuristics

- **One failure is data. Three failures is signal.** Re-run twice after a docs change; if cold-start still fails, the docs haven't closed the gap.
- **Check the first tool call, not the full conversation.** Most docs-decay shows up as "didn't look where I should have looked." That's a turn-1 signal.
- **Log the run.** Append to `docs/research/cold-start-log.md` (create it when we do the first run): date, scenario, pass/fail, one-sentence note on what was missed.
- **Don't optimize the agent prompt.** The scenarios exist to test the *docs*, not the model. If the agent has to be coaxed into doing the right thing, the docs are wrong.

## When to update this doc

- A new skill or rule is added that changes which entry point *should* fire for an existing scenario → update the expected actions.
- A new scenario appears that would catch a real failure mode (e.g. "migrate the relay to a new VM," "add a Linux client build") → add it.
- A scenario stops mattering (e.g. we stop shipping Drive-direct-link builds and distribution becomes automated) → archive it, don't delete it; note the date.
