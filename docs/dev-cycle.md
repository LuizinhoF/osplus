# OSPlus development cycle

How features get from idea to shipped in OSPlus. The canonical answer to "how do we work on things."

This document is **descriptive of the discipline**, not just a process diagram. The lifecycle exists because OSPlus is built AI-first by a single maintainer + agent, and the failure mode without explicit structure is: agents pick the cheapest path, ship something off-target, and the maintainer either rejects it or — worse — ships it. The structure below is the antidote.

For why this shape and not another, see [`docs/learnings/lifecycle-design-back-edges-and-confidence-tiers.md`](learnings/lifecycle-design-back-edges-and-confidence-tiers.md).

---

## The six stages

```
Capture ──→ Frame ──→ Feasibility ──→ Design ──→ Build ──→ Land
              ↑          ↑↓              ↑↓        ↑↓
              │          │               │         │
              │          │ (verdict      │         │ (build evidence
              │          │  changes)     │         │  invalidates plan)
              │          │               │         │
              └──────────┴───────────────┴─────────┘
                  any stage can shelve back to Capture
                  (with a learning entry explaining why)
```

| # | Stage | Output | Driver | Gate to next |
|---|---|---|---|---|
| 1 | **Capture** | A tracked one-liner: idea + who-it's-for hint | You | Triage decision: kill / park / advance |
| 2 | **Frame** | Brief in `docs/features/<slug>.md` `## Brief`: problem, audience, loose success, product-fit check | Agent drafts → you sign off | Passes product fit (no anti-goal violation; serves the wedge or supports it) |
| 3 | **Feasibility** | `## Feasibility` section: verdict + **confidence rating** + **explicit assumption list** + evidence trail | Agent runs the `discover` skill; you run the game when needed | Enough confidence to commit to a design direction (or shelve) |
| 4 | **Design** | `## Design` section: chosen direction with alternatives logged. ADR drafted if architectural | `feature-design` skill | Explicit "go" from you |
| 5 | **Build** | Branch with code; in-game validation iterations | Agent implements → you test in-game → loop | Smoke checks pass; you say "feels right" |
| 6 | **Land** | Merged branch; optionally a release zip; `## Outcome` filled; **learning entry** | `release-checklist` + `learnings-discipline` | Green main + learning written |

**Bug-fix lane** is separate: report → `bug-investigate` (search prior art → reproduce → falsify → fix) → ship → learning. Bugs don't go through Frame/Feasibility/Design; their lifecycle is shorter.

---

## Back-edges are first-class

A linear lifecycle would be a lie. RE-heavy work has unknowns that only surface during build. The named back-edges:

| From → To | When it fires | What happens |
|---|---|---|
| Build → Feasibility | Build hits a wall: an assumption from Stage 3 turned out to be wrong | Loop back with new evidence; Stage 3 re-rates feasibility. If verdict drops from High→Low, write a learning *first* — what evidence would have caught the mis-rating? |
| Build → Design | Scope creep / design needs revision discovered during build | Loop back to Stage 4; revise design, then re-enter Build |
| Design → Feasibility | Designing reveals a hole the feasibility check missed | Loop back to Stage 3 with the specific unknown |
| Feasibility → Frame | Feasibility reveals the problem statement was actually a different problem | Reframe before continuing |
| **Anything → Capture (shelve)** | No loop-back unlocks it | Feature parked back in inbox with a learning explaining *why* — so it isn't re-tried in six months without that context |

These are not failure modes. They are the workflow doing its job when reality disagrees with prediction. The default-paired stance (next section) is what makes them work without thrashing.

---

## Default-paired stance

OSPlus runs in **default-paired** mode. The agent does not silently autonomously execute multi-step work inside a stage. At every non-trivial decision point, it pauses and surfaces the choice.

What this means in practice:

| Surface | Agent default behavior |
|---|---|
| Stage transitions | Always explicit. Agent says "moving from Stage 3 to Stage 4" and waits for sign-off. |
| Inside a stage, before non-trivial actions | Agent surfaces the plan and waits ("I plan to dump UFunctions for the lobby widget — sound right?"). |
| Surprising findings | Agent stops and reports. Does not continue past contradiction. |
| Direction changes / loop-backs | Agent proposes the back-edge; you decide whether to take it. |
| Architectural commitments | Agent stops and routes to the ADR discipline (see `cursor/rules/decision-discipline.mdc`). |

The agent is autonomous on **mechanical** work inside a stage (running a search, dumping an object, drafting a section, applying a known fix). It is paired on **judgment** work (which option to pursue, when to loop back, whether to accept evidence as conclusive).

If the agent feels itself spiraling — repeatedly trying things without progress — that is the trigger to stop and pair with you, not to try harder alone.

---

## Confidence tiers (Stage 3 output)

Stage 3 does not produce binary "yes / no." It produces:

| Tier | Meaning | Stage 5 implication |
|---|---|---|
| **High** | Hook tested live; data shape verified by dump; similar pattern already shipped | Build the full feature directly |
| **Medium** | Hook plausibly exists from code-reading; data shape inferred; analogous pattern works elsewhere | Build a *thin slice* first — minimal version that validates the uncertain assumption. If the slice works, expand to full feature |
| **Low** | Theoretical only; no direct evidence; "should work" reasoning | **Spike only** — a throwaway hack that proves *just* the unknown thing works. No feature work until the spike returns evidence |

Plus an **explicit assumption list** in the feature doc: "this assumes `UEmoteWidget::ShowEmote` is callable from any `UWorld`; we have not verified that during a match." When build hits a wall, the failed assumption is named — no re-deriving.

The spike pattern is documented in [`cursor/skills/discover/references/spike-pattern.md`](../cursor/skills/discover/references/spike-pattern.md).

---

## Per-feature paper trail

Every feature gets a single file: `docs/features/<slug>.md`. Sections are filled progressively as the feature moves through stages.

```
docs/features/<slug>.md
  ## Brief         (Stage 2)
  ## Feasibility   (Stage 3 — verdict, confidence, assumptions, evidence)
  ## Design        (Stage 4 — chosen direction, alternatives, ADR links)
  ## Outcome       (Stage 6 — shipped / shelved / forked, link to learning)
```

Shelved features stay in the folder. Their value *is* that they were tried and *why* they didn't pan out.

See [`docs/features/README.md`](features/README.md) for the policy and [`docs/features/_TEMPLATE.md`](features/_TEMPLATE.md) for the template.

---

## How findings accumulate (the compounding part)

Findings split into two tiers:

| Tier | Where it lives | Promotion default |
|---|---|---|
| **Feature-specific** | `## Feasibility` section of the feature doc | Stays local |
| **Generally reusable** (engine fact, UE4SS pattern, OS internal that future features will care about) | `KNOWLEDGEBASE.md` or `docs/learnings/<slug>.md` (existing rule decides which) | Auto-promote when obviously general; ask when it's a judgment call |

This is what makes Stage 3 cheap over time: the second feature investigating the same engine area starts with a populated knowledge base, not a blank page.

(`KNOWLEDGEBASE.md` is currently a 750-line monster that should be split into `docs/engine/` per topic. The promotion path will accelerate that pressure — not blocking on it now, but it's a known-pending refactor.)

---

## What runs each stage

| Stage | Skill / Tool / Doc |
|---|---|
| 1. Capture | `docs/ROADMAP.md` "Open questions" (current inbox); no skill |
| 2. Frame | No dedicated skill; agent drafts directly into `docs/features/<slug>.md` `## Brief` |
| 3. Feasibility | [`cursor/skills/discover`](../cursor/skills/discover/) skill |
| 4. Design | [`cursor/skills/feature-design`](../cursor/skills/feature-design/) skill (with the Phase 2.5 ADR checkpoint) |
| 5. Build | Direct implementation; harnesses per [`cursor/rules/harnesses.mdc`](../cursor/rules/harnesses.mdc); deploy via `deploy.ps1` |
| 6. Land | [`cursor/skills/release-checklist`](../cursor/skills/release-checklist/) + [`cursor/rules/learnings-discipline.mdc`](../cursor/rules/learnings-discipline.mdc) |
| Bug-fix lane | [`cursor/skills/bug-investigate`](../cursor/skills/bug-investigate/) |

---

## Anti-patterns to recognize

The lifecycle exists to prevent specific failure modes. Recognize them:

- **Skipping Stage 3 for "obvious" features.** If you don't write the assumption list, you don't know what you're assuming. The Build wall later costs more than the Stage 3 hour.
- **Designing with Low-confidence feasibility.** If the verdict is Low, no design phase will rescue the feature — it needs a spike first. Designing on top of "should work" is the canonical path to wasted Stage 4 effort.
- **Letting Build invent design.** When Build discovers something, the answer is to loop back to Stage 4 and revise the design — not to absorb the discovery into ad-hoc implementation choices.
- **Spike turning into "let me just build the feature here."** Hard-stop. Spike branches are throwaway by definition. If a spike is becoming the implementation, return to Stage 3 to re-rate confidence and start a real Build branch.
- **Skipping the Learning step at Land.** Per `learnings-discipline.mdc` the cycle is not done without it. Hooks remind you on session stop.

---

## Related

- [`AGENTS.md`](../AGENTS.md) — entry point for any agent; routes here.
- [`docs/product.md`](product.md) — product definition; what features must serve.
- [`docs/decisions/`](decisions/) — accepted ADRs; what designs cannot quietly violate.
- [`docs/features/`](features/) — per-feature paper trail.
- [`cursor/rules/decision-discipline.mdc`](../cursor/rules/decision-discipline.mdc) — when to stop and write an ADR.
- [`cursor/rules/learnings-discipline.mdc`](../cursor/rules/learnings-discipline.mdc) — when (always) to write a learning.
- [`cursor/rules/git-workflow.mdc`](../cursor/rules/git-workflow.mdc) — branching and commit conventions.
