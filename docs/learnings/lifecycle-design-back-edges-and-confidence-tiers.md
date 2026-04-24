# lifecycle-design-back-edges-and-confidence-tiers

| Field | Value |
|---|---|
| Date | 2026-04-23 |
| Area | docs |
| Tags | agentic-workflow, lifecycle, feature-design, feasibility, reverse-engineering, default-paired |
| Status | confirmed |

## Symptom

The agentic stack had a clean *what* (`docs/product.md`) and *how-architecturally* (`docs/decisions/`), but no canonical *how-procedurally*. Skills existed (`feature-design`, `bug-investigate`, `release-checklist`) but they didn't compose into a lifecycle, and reverse-engineering / feasibility work was either implicit inside `feature-design` or done ad-hoc with no durable artifact.

The concrete failure mode this would have produced (and which the prior session's emote/profile groundwork was already on track for): designing a feature against an assumed-but-unverified hook, then hitting a Build-stage wall when the hook turns out to behave differently. With no Stage 3 discipline, there's nowhere for the falsified assumption to land — it gets re-derived next session, possibly by a different agent, possibly with the same wrong conclusion.

## Root cause

The mental model of "linear stages with binary gates" doesn't fit RE-heavy modding. Three things go wrong:

1. **Unknowns surface during Build, not before.** Stage 3 evidence is necessarily incomplete because some assumptions only become visible when their failure breaks something downstream. A binary "feasible / not feasible" gate forces a verdict the evidence can't actually support.
2. **Linear gates encourage skipping Stage 3 for "obvious" features.** When the gate is binary, "obviously yes" feels safe — you skip the assumption-listing exercise that would have caught the wrong assumption *because* you weren't forced to write it down. This is a structural failure, not an agent failure.
3. **Without explicit back-edges, loops happen anyway — but informally.** Build hits a wall, the agent quietly "iterates," design slowly drifts, and what was a Stage 3 mis-rating becomes invisible technical debt. The loop is real; refusing to name it just hides where the cost lives.

This connects to a broader pattern documented in [`docs/learnings/product-architecture-coupling-via-premature-locks.md`](product-architecture-coupling-via-premature-locks.md): when a process collapses two distinct disciplines into one (there: product + architecture; here: design + feasibility), the cheaper one quietly absorbs the harder one and the harder one stops happening.

## Fix

Restructured the feature workflow around three load-bearing changes:

1. **Six-stage lifecycle with first-class back-edges.** `docs/dev-cycle.md` defines Capture → Frame → Feasibility → Design → Build → Land plus named loop-backs (Build → Feasibility, Design → Feasibility, etc.). Loop-backs are the workflow doing its job, not a sign of failure. The default-paired stance means agents stop and surface back-edges rather than absorbing them silently.
2. **Stage 3 emits confidence tiers + assumption lists, not binary verdicts.** High / Medium / Low / Not feasible plus an explicit list of testable assumptions. Tier maps to recommended Stage 5 path: full feature / thin slice / spike-first / shelve. The named-assumption discipline gives Stage 5 walls a place to land — when build hits a wall, the failed assumption is the one to point at.
3. **`discover` skill (new) as Stage 3, separate from `feature-design`.** Six-step playbook: search prior knowledge → name unknowns → pick technique → execute → verdict → promote findings. Two modes (feature-driven and standalone). Spike pattern as a controlled escape hatch for Low-confidence verdicts. `feature-design` gains a Phase 0 precondition that hard-routes to `discover` if the feature doc lacks a `## Feasibility` section — closing the loop where Stage 4 used to barrel into design.

Per-feature paper trail: `docs/features/<slug>.md` with `## Brief / ## Feasibility / ## Design / ## Outcome` sections, filled progressively across stages. Shelved features stay (their value is *why* they didn't pan out).

Knowledge accumulation: `discover` Step 6 promotes generally-reusable findings to `docs/learnings/` or `KNOWLEDGEBASE.md` automatically when obvious, asks when judgment-call. Compounding model: the second feature investigating the same engine area starts with a populated knowledge base, not a blank page.

See: [`docs/dev-cycle.md`](../dev-cycle.md), [`cursor/skills/discover/`](../../cursor/skills/discover/), [`docs/features/_TEMPLATE.md`](../features/_TEMPLATE.md), and the Phase 0 addition to [`cursor/skills/feature-design/SKILL.md`](../../cursor/skills/feature-design/SKILL.md).

## Lesson

Three transferable insights:

1. **When designing a workflow for unfamiliar territory, put loop-backs in the diagram from day one.** A "linear with rollback" workflow is actually a "DAG with named edges" workflow that just hasn't been honest about it. Naming the back-edges (and what triggers each) is what lets agents take them deliberately instead of drifting into them.
2. **Confidence tiers + named assumptions beat binary verdicts when the evidence is necessarily incomplete.** The assumption list is the contract Stage 5 holds Stage 3 to. Binary verdicts have no contract — when Build hits a wall, there's nothing to point at.
3. **If an existing skill is quietly absorbing a different discipline, that's the structural smell.** Pulling Stage 3 out of `feature-design` into a dedicated `discover` skill costs a little orchestration overhead (the precondition check, the routing) and buys a lot of clarity (each skill does one thing, the lifecycle is legible end-to-end).

The meta-meta-lesson: workflow discipline is itself a compounding artifact. Each well-defined stage means future features cost less to plan, because the structure does the bookkeeping that ad-hoc agents would otherwise re-derive.

## Related

- Files: [`docs/dev-cycle.md`](../dev-cycle.md), [`docs/features/README.md`](../features/README.md), [`docs/features/_TEMPLATE.md`](../features/_TEMPLATE.md), [`cursor/skills/discover/SKILL.md`](../../cursor/skills/discover/SKILL.md), [`cursor/skills/discover/references/playbook.md`](../../cursor/skills/discover/references/playbook.md), [`cursor/skills/discover/references/standalone-mode.md`](../../cursor/skills/discover/references/standalone-mode.md), [`cursor/skills/discover/references/spike-pattern.md`](../../cursor/skills/discover/references/spike-pattern.md), [`cursor/skills/feature-design/SKILL.md`](../../cursor/skills/feature-design/SKILL.md), [`docs/research/2026-agentic-stack.md`](../research/2026-agentic-stack.md) (2026-04-23 workflow design section), `AGENTS.md`, `docs/ROADMAP.md`.
- Prior learnings (this extends): [`docs/learnings/product-architecture-coupling-via-premature-locks.md`](product-architecture-coupling-via-premature-locks.md) — same shape of failure (collapsing two disciplines into one), different layer of the stack.
- Upstream sources: no external sources directly. This is OSPlus-specific structural design.
