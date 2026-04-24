# Cold-start validation log

Runs of the three canonical scenarios in `docs/research/cold-start-scenarios.md`. Each entry: date, what changed in the docs, what was tested, pass/fail per scenario, one-line notes on anything surfaced.

Append newest entries at the top.

---

## 2026-04-23 — post product-foundation rebuild

**Docs changed since last validation (this is the first recorded run):**

- `docs/vision.md` → archived to `docs/decisions/_archive/vision-v1-superseded.md` with a "why archived" header.
- `docs/product.md` (new) — product north star.
- `docs/decisions/README.md`, `_TEMPLATE.md` (new) — ADR infrastructure.
- `cursor/rules/decision-discipline.mdc` (new) — always-apply rule for ADR discipline.
- `cursor/skills/feature-design/SKILL.md` — Phase 2 rewritten to read product.md + decisions/; **Phase 2.5 ADR checkpoint added**.
- `AGENTS.md` — pre-work reading updated; Vision & roadmap section rewritten.
- `docs/ROADMAP.md` — re-filtered through the product lens; Now / Next / Needs-ADR / Won't-do restructured.
- Cold-start scenarios (this doc's companion) — Scenario 3 updated to test ADR-checkpoint behavior; Scenarios 1+2 path references fixed (`.cursor/` → `cursor/`).

**Method:** Mental walkthrough by the parent agent against each scenario, tracing what a fresh session with only the always-applied rules + AGENTS.md loaded would do on turn 1.

### Scenario 1 — "Ship a build"

**Result: PASS.** No regression. AGENTS.md "Workflow skills" routes to `release-checklist`; Toolchain section exposes `build_dist.ps1` and the manual cook step. Red flags (new script, skipped cook) would not trigger.

### Scenario 2 — "Fix a chat bug"

**Result: PASS.** No regression. Description match triggers `bug-investigate`; the skill instructs prior-art grep against `docs/learnings/`. Chat-specific learnings exist in-repo (`docs/learnings/` includes related entries per git status).

### Scenario 3 — "Add a new feature"

**Result: PASS** — the primary objective of this rebuild.

Traced flow:
1. `feature-design` description matches the "add X" prompt → skill invoked.
2. Phase 2 anchor: agent reads `docs/product.md` (wedge confirms fit), scans `docs/decisions/` (finds first-priority queue: identity, profile storage, ephemeral state).
3. Phase 2.5 ADR checkpoint fires: profiles force decisions on identity + profile storage → skill instructs STOP and proposes ADR drafting.
4. Agent surfaces the conflict to the user rather than proposing architecture silently.

All four red flags are now guarded by independent mechanisms:
- "Proceeds without ADR" — blocked by Phase 2.5 STOP.
- "Treats archive as canon" — guarded by archive header + product.md callouts + `decision-discipline.mdc`.
- "Invents schema fields" — schema-grows-on-demand policy preserved in product.md.
- "Silent service/persistence choice" — now an ADR option, not a default.

### Observations / risks surfaced

- **AGENTS.md pre-work reading list is now 9 items.** Long. A fresh agent will cherry-pick on turn 1; this is fine for routing but means the "always-read" bar is really only AGENTS.md itself. Acceptable — the other entries are "read when relevant," not "read before every response."
- **Phase 2.5 is load-bearing.** The whole regime depends on `feature-design` getting activated by description match. If the prompt shape stops triggering the skill, Phase 2.5 won't fire. Monitor in future runs. Potential mitigation (not doing now): duplicate the checkpoint into `decision-discipline.mdc` as a run-every-turn check rather than a skill-activation-time check.
- **`decision-discipline.mdc` is `alwaysApply: true`** — acts as the backstop for the above. If `feature-design` doesn't activate, the discipline rule still tells the agent "you're committing to an architectural direction without an ADR; stop."

**No doc fixes required from this run.** Scenario 3 behaves as intended.

---
