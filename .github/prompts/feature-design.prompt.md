---
description: "Surface design axes and trade-offs BEFORE writing code for a non-trivial feature. Produces a Feature Design Document; STOPS for user sign-off before any implementation."
---

# /feature-design

You are entering the **feature-design** skill. Read the full specification now and follow it exactly:

[.cursor/skills/feature-design/SKILL.md](../../.cursor/skills/feature-design/SKILL.md)

Summary of what you must do (the file above is authoritative):

1. **Phase 1 — Restate the goal:** GOAL / USER-VISIBLE OUTCOME / SCOPE BOUNDARY in three lines. If you can't, ask before continuing.
2. **Phase 2 — Anchor:** Read [docs/product.md](../../docs/product.md), scan [docs/decisions/](../../docs/decisions/) for applicable accepted ADRs, grep [docs/learnings/](../../docs/learnings/) for prior art, list the files that will and won't change.
3. **Phase 2.5 — ADR checkpoint:** Before proceeding, ask whether this feature forces a decision in any area currently open for ADR deliberation (see `docs/decisions/README.md` → First-priority deliberation queue). If yes, STOP feature design and draft the ADR first.
4. **Phase 3 — Surface design axes:** Default to MORE axes, not fewer. Concrete options only. Each axis gets a verdict source (`product-decided` / `ADR-decided` / `code-conventions-decided` / `agent's call` / `NEEDS USER INPUT`).
5. **Phase 4 — Propose, name alternatives, STOP.** Output the document in the exact format the SKILL.md specifies. **Do not write code.** Wait for user sign-off.

Non-negotiable rules (from the skill):

- Stop before code. This skill produces a document, not a diff.
- Two-axis designs are suspicious — look harder before submitting.
- Product definition is canon; if a feature seems to violate an anti-goal or expand the wedge beyond its defined shape, surface the conflict rather than quietly redefine the product.
- Accepted ADRs are canon; if a feature seems to require changing one, draft a superseding ADR, don't quietly drift.
- When an axis carries genuine UX or platform commitment, default to `NEEDS USER INPUT` even if you have an opinion.
