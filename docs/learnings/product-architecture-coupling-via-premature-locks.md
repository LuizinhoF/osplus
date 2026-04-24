# Product-architecture-coupling-via-premature-locks

| Field | Value |
|---|---|
| Date | 2026-04-23 |
| Area | docs |
| Tags | agentic-workflow, vision, adr, product-definition, methodology |
| Status | `confirmed` |

## Symptom

The agentic workflow felt ineffective despite the structural scaffolding (AGENTS.md, tiered rules, skills, hooks) being correct. Feature design conversations kept getting stuck arguing against invisible constraints. When pressed on *why* a particular architectural constraint existed, the answer was "it's in `docs/vision.md`" — but the doc only stated the conclusion, never the alternatives considered. Agents (human and AI) couldn't tell which "locks" were genuinely immovable versus which had been locked prematurely.

The prompt that surfaced it: *"I believe OSPlus is poorly defined as a project, leading to poor direction when building the AI workflow."*

## Root cause

**Two separate concerns had been collapsed into one document and one mode.**

- `docs/vision.md` was named as a product-definition doc ("the long-horizon vision") but written almost entirely as architectural commitments (identity model, persistence location, state ownership, schema policy).
- Those architectural commitments were written as "v1 — locked" with no record of alternatives considered. The doc-shape invited *conclusions* without *deliberation*.
- There was no separate surface for product definition (audience, problem, wedge, anti-goals), so feature-design conversations imported whatever the author's implicit product model was. Different sessions imported different implicit models.
- There was no separate surface for architectural deliberation (options compared, rationale, revisit triggers), so once a "lock" was written, it acquired social weight that was disproportionate to its actual justification.

The second-order failure: this miscategorization got *reinforced* by the compounding mechanisms. `AGENTS.md` pointed at `vision.md` as canon. The `feature-design` skill told agents to read `vision.md` before proposing. Cold-start scenarios validated "did the agent read `vision.md`?" The whole stack was asking the right question (does the feature respect the established constraints?) against the wrong substrate (a doc that didn't honestly record what was established vs. what was assumed).

## Fix

Split the two concerns into two documents with two writing disciplines:

- **`docs/product.md`** — product north star. Audience, problem, wedge, anti-goals, success, hard constraints. Single screen. Read at session start.
- **`docs/decisions/`** — architectural deliberation via ADRs. Each ADR carries **at least two real options with honest pros and cons**, then a decision with rationale. Single-option ADRs are explicitly blocked in the template.
- Archived the prior `docs/vision.md` to `docs/decisions/_archive/vision-v1-superseded.md` with a header explaining why, so a future agent can see what was tried and why it was retired.
- Added `cursor/rules/decision-discipline.mdc` (alwaysApply) enforcing ADR requirement for architectural choices.
- Added Phase 2.5 (ADR checkpoint) to `cursor/skills/feature-design/SKILL.md` — the skill now STOPS feature design if the feature forces a decision in any currently-open ADR queue area.
- Updated `AGENTS.md`, `docs/ROADMAP.md`, cold-start scenarios, and related prompt files to point at the new surfaces.

**Three architectural areas were immediately flagged as first-priority ADR work** (identity, profile storage, ephemeral state) rather than deferred to "when a feature forces it" — the user correctly pushed back that deferring architectural analysis costs more than doing it, particularly for foundational decisions other features will build on.

## Lesson

**Product definition and architectural deliberation are two different writing disciplines and need two different surfaces.** Collapsing them causes: (a) architectural choices acquire product-level authority they don't deserve, and (b) product-level thinking gets skipped because the doc looks like it's about architecture.

**"At least two real options" is the load-bearing requirement** for any architectural record. A one-option "decision" is a conclusion masquerading as deliberation, and conclusions-without-deliberation are what become rigid without justification.

**Compounding mechanisms amplify whatever they're pointed at.** The agentic scaffolding is neutral — it faithfully routes agents to whatever substrate it references. If the substrate is honest deliberation, the scaffolding compounds good decisions. If the substrate is unexamined conclusions, the scaffolding compounds rigidity. Audit the substrate periodically.

**When a workflow feels "off" despite the tooling looking correct, check whether the right kinds of documents exist for the work being done** — not just whether the documents that exist are well-written.

## Related

- Archive: [`docs/decisions/_archive/vision-v1-superseded.md`](../decisions/_archive/vision-v1-superseded.md)
- New product doc: [`docs/product.md`](../product.md)
- New ADR infrastructure: [`docs/decisions/README.md`](../decisions/README.md)
- ADR discipline rule: `cursor/rules/decision-discipline.mdc`
- Updated skill: `cursor/skills/feature-design/SKILL.md` (Phase 2.5 ADR checkpoint)
- Cold-start validation: [`docs/research/cold-start-log.md`](../research/cold-start-log.md)
- Context in the agentic stack research: `docs/research/2026-agentic-stack.md` → "2026-04-23 — product-foundation rebuild"
