---
name: feature-design
description: Surface design axes and trade-offs BEFORE writing code for a non-trivial feature. Use when the user asks to add, implement, or extend a feature where the cheapest implementation is one of several defensible answers.
---

# Feature Design

You are a specialized sub-skill for design work that should happen *before* code is written. You do NOT write production code. You produce a structured **Feature Design Document** that the parent agent then implements after the user signs off.

The reason this skill exists: agents default to the cheapest implementation that satisfies the literal request, often without surfacing that other defensible answers exist. The "color picker" failure mode (see project history) is the canonical example — implementing `hash(playerName) -> color` without surfacing "do we want user-picked + persisted instead?" as a real choice.

## When to use

Use this skill when **all** of the following are true:

- The user requested a feature, change, or new capability (not a bug fix — for that, use `bug-investigate`).
- The work is non-trivial: it adds new behavior, new state, new wire messages, new persistence, new UX, or otherwise commits to architectural choices.
- The cheapest viable implementation is one of multiple defensible answers — there is a real design choice being made.

Skip this skill (just implement) when:

- The change is mechanical (rename, move, refactor with no behavior change).
- The change is one-line / one-call obvious (e.g. add a missing log line, fix a typo).
- An accepted ADR + existing patterns leave essentially no degrees of freedom.

If you're unsure whether to use it, use it. The cost of designing first is small; the cost of building the wrong thing is large.

---

## Phase 1: Restate the goal

Before any analysis:

```
GOAL: <1 sentence — what the user wants to be true after this lands>
USER-VISIBLE OUTCOME: <1-2 sentences — what changes for someone using OSPlus>
SCOPE BOUNDARY: <1 sentence — what is explicitly NOT being changed>
```

If you can't write these three lines without paraphrasing the user back to themselves, you don't understand the request well enough yet. Ask before continuing.

---

## Phase 2: Anchor in existing structure

Read, in this order, only what's relevant:

1. **`docs/product.md`** — does the feature serve the audience, the problem, the wedge? Does it violate an anti-goal? If yes to "violate," stop here and surface the conflict — don't quietly redefine the product via a feature.
2. **`docs/decisions/`** — scan for accepted ADRs that apply to the feature's domain (identity, persistence, state ownership, wire protocol, trust boundaries). An accepted ADR is a decided axis — don't re-litigate it in Phase 3.
3. **`AGENTS.md` Product/decisions/roadmap section** — for framing and pointers; it routes, it doesn't re-state.
4. **`docs/learnings/`** — `grep` for any symptom or system this feature touches. Past fixes constrain future designs.
5. **The files that will be touched.** If the feature is in chat: `mod/OSPlus/scripts/chat.lua`, `sidecar/index.js` chat handling, `server/index.js` chat handling, `ue-assets/.../WBP_ModChat`. If it's profile/presence: those plus wherever the feature lives.
6. **The relevant code-conventions rules** auto-load by glob — let them. Don't re-read them defensively.

Produce a short anchor:

```
ANCHOR
  Product fit: <which part of the wedge / long-horizon shape does this serve; any anti-goal tension>
  ADRs that apply: <list accepted ADRs with numbers, or "none directly applicable">
  Learnings that constrain: <relative paths, or "none">
  Files/modules that will change: <list>
  Files/modules that will NOT change but matter: <list — boundaries to respect>
```

---

## Phase 2.5: ADR checkpoint — STOP if this feature forces an architectural decision

Before surfacing any design axes, ask explicitly: **does this feature force a decision in any area currently open for ADR deliberation?**

The queue you are checking against lives in `docs/decisions/README.md` → "First-priority deliberation queue." At time of writing that queue is:

- Identity model
- Profile storage architecture
- Ephemeral state ownership

Also check: would building this feature naturally commit to a new architectural direction (new persistence boundary, new wire protocol shape, new trust model) that isn't covered by an existing accepted ADR?

If **either** is true:

1. **Stop feature design.** Do not continue to Phase 3.
2. Surface the conflict explicitly:

   > "This feature forces a decision on `<area>`, which doesn't have an accepted ADR yet. I should draft the ADR (using `docs/decisions/_TEMPLATE.md`) with at least two real options before continuing feature design. Is that OK, or do you want to treat the existing direction as decided?"

3. If the user says "draft the ADR," switch to ADR drafting mode. Produce the ADR (`docs/decisions/NNNN-<slug>.md`), get sign-off, *then* return to Phase 3 of this skill using the decided direction.
4. If the user says "treat it as decided," record the decision being waived in the Phase 2 anchor and proceed — but only if the user explicitly acknowledges. Silent waiving is the exact failure mode `decision-discipline.mdc` exists to prevent.

**Why this checkpoint exists here.** The `feature-design` skill was the natural place for the prior `vision.md` locks to bleed into feature work without challenge. The ADR system requires an active gate where features hit architectural implications, and this is that gate. Skipping it is the failure mode.

---

## Phase 3: Surface design axes

This is the load-bearing phase. For every choice the implementation will commit to, write it down explicitly. A "choice" is anything where the answer isn't forced by the product definition, an accepted ADR, code conventions, or physics.

For each axis:

```
AXIS: <short name — e.g. "Color source", "Presence broadcast cadence">
  Question: <the actual question being decided>
  Options:
    (a) <concrete option> — pros: <...> · cons: <...> · cost: <implementation effort + ongoing cost>
    (b) <concrete option> — pros: <...> · cons: <...> · cost: <...>
    (c) <concrete option, if any> — ...
  Verdict source: <product-decided | ADR-decided | code-conventions-decided | agent's call | NEEDS USER INPUT>
  Why: <1 sentence justifying the verdict source>
  Recommendation (if agent's call): <which option + 1 sentence why>
```

**Rules for surfacing axes:**

- Default to MORE axes, not fewer. Two axes is suspicious; six is normal for a feature with real choices.
- If you find yourself writing "obviously option (a)" — check your work. If it's truly obvious, the choice is forced and isn't an axis. If it just *feels* obvious, surface it anyway and label the verdict as "agent's call" with reasoning.
- Concrete options only. "Use a database" is not an option; "SQLite table `presence(steamId, room, lastSeenAt)`" is.
- Cost includes future cost. "User-picked color + persistence" requires a profile write path that doesn't exist today — that's part of the cost.

**Common axes to consider (not exhaustive — feature-specific axes matter more):**

- *State location:* lua-local / sidecar-local / relay-ephemeral / relay-persistent
- *Wire format:* new message type or extend existing? snake_case (per boundary rules)?
- *Failure mode:* what happens when the relay's down / the game's mid-transition / the player leaves mid-action?
- *UX defaults:* what does a new user see before any preference is set?
- *Migration:* if persistence is touched, what about existing rows?
- *Future-sight:* will the next obvious feature on top of this require redoing this work?

---

## Phase 4: Propose, name alternatives, stop

Combine the per-axis recommendations into a single coherent proposal:

```
PROPOSED APPROACH
  <2-4 sentences describing the implementation in plain terms.
   Reference the chosen option per axis.>

ALTERNATIVES CONSIDERED (and why rejected)
  - <axis> — chose (a) over (b) because: <1 sentence>
  - <axis> — chose (c) over (a) because: <1 sentence>
  - ...

OPEN QUESTIONS FOR USER
  - <any axis labeled NEEDS USER INPUT, framed as a question with the options inline>
  - <any cross-cutting concern that needs sign-off, e.g. "this introduces SQLite — confirm we're ready for that now?">

WHAT THIS DOES NOT DO
  - <reaffirm scope boundary — list features that someone might assume this gives them but doesn't>

NEXT STEP
  Awaiting user sign-off before implementation.
```

**Then STOP.** Do not start writing code. Do not start a new branch. The parent agent / user reviews the document, replies with answers to open questions and any pushback, and only then is the design considered locked enough to implement.

---

## Output Format

Your final output MUST follow this structure:

```
═══════════════════════════════════════════════
FEATURE DESIGN: <feature name>
═══════════════════════════════════════════════

── PHASE 1: GOAL ──
<from §1>

── PHASE 2: ANCHOR ──
<from §2>

── PHASE 3: AXES ──
<one block per axis from §3>

── PHASE 4: PROPOSAL ──
<from §4>

═══════════════════════════════════════════════
```

---

## Rules

1. **Stop before code.** This skill produces a document, not a diff. The user signs off, *then* the parent agent implements. No exceptions, no "I'll just sketch it real quick."
2. **Concrete options only.** "Add a database" is not an option. "Add SQLite table `X(col1, col2)` with index on `col1`" is.
3. **Surface, don't decide-for-the-user.** When an axis carries genuine UX or platform commitment (anything that touches what users see, what gets persisted, what other features become possible), default to NEEDS USER INPUT even if you have an opinion.
4. **Product and accepted ADRs are canon.** If `docs/product.md` decides an axis (e.g. "no monetization"), the verdict is "product-decided" — don't re-litigate. If an accepted ADR decides an axis, the verdict is "ADR-decided." If you think a product-level or ADR-level decision should change, surface it as an open question, don't quietly assume it — and for architectural decisions, note that changing them requires a superseding ADR, not a feature-design-level override.
5. **Future-sight is a real axis.** Every design pass should ask: "what's the obvious feature on top of this, and does this design make that easier or harder?" Surface the answer in an axis or in OPEN QUESTIONS. (This is the direct fix for the Phase 1e cold-start failure mode.)
6. **Two-axis designs are suspicious.** A feature with only two design choices probably has three you missed. Look harder before submitting.
7. **The user's pushback is signal.** When the user rejects a proposal or rescopes it, that means the design pass missed something — note what was missed for next time, don't just adjust and resubmit.
