# OSPlus — Feature Docs

Per-feature paper trail. Each file is the single source of truth for what a feature is, whether it's possible, what we decided to do, and how it ended.

This folder exists because the prior workflow lost feature context between sessions: briefs lived in chat, feasibility findings lived in agent memory, design decisions lived in commit messages. The next agent re-derived everything. Feature docs fix that — Stage 3 of the next feature investigating the same area can read the previous feature's `## Feasibility` section in 30 seconds instead of re-running an hour of RE.

See [`docs/dev-cycle.md`](../dev-cycle.md) for the lifecycle that writes into these docs.

## How to use this folder

| Path | Purpose |
|---|---|
| `<slug>.md` | One file per feature. Slug is short kebab-case. Filled progressively across stages. |
| `_TEMPLATE.md` | Template to copy. Has the four required sections. |

## When to create a feature doc

Create one when the feature passes triage at Stage 1 (Capture) and is moving into Stage 2 (Frame). Don't create empty stubs for ideas that are still in the inbox — the doc starts existing when the brief gets drafted.

The slug should be specific enough that someone scanning the folder can guess the feature: `in-game-profile-mvp` is good; `profile` is too broad; `add-profile-page-with-stats-and-cosmetic-unlocks` is too long.

## When to mark Outcome=shelved

A feature gets `## Outcome: shelved` when:

- Feasibility came back Low and a spike confirmed the assumption fails (no path forward at our scale of tooling/effort).
- Design surfaced an architectural conflict that the relevant ADR rules out, and re-opening the ADR isn't worth it.
- Build hit a wall that loop-back to Feasibility couldn't unstick, and the feature isn't worth the effort to find an alternate path.
- The brief, on second look, doesn't actually serve the wedge or violates an anti-goal.

Shelved docs **stay in the folder**. Their value is the documentation of *why* the path didn't work — so the next person (or session) doesn't re-try it from scratch. Add a learning entry alongside if the failure surfaced new general knowledge.

## When to delete a feature doc

Almost never. Two cases:

- The feature was captured by mistake (duplicate of an existing one) and never moved past an empty `## Brief`.
- The feature is being merged into another feature doc — in which case, the surviving doc absorbs the relevant content and the dead one is deleted with a commit message linking forward.

If you find yourself deleting a doc with substantive content, that's a smell. Prefer marking it `## Outcome: shelved` with a reason instead.

## Index

Newest first. Empty until the first feature gets a doc.

| Status | Slug | One-line summary |
|---|---|---|
| `feasibility` | [`in-game-profile-mvp`](./in-game-profile-mvp.md) | v1 wedge substrate — plumbing only: identity binding + raw per-match state capture. Feasibility Pass 1 done (identity High; tracker ecosystem mapped; Prometheus-ID-vs-SteamID distinction surfaced). Pass 2 (capture-surface live probes) pending. ADR-gated on identity model + profile storage. |

`Status` values: `framed` (Stage 2 done), `feasibility` (Stage 3 done), `designed` (Stage 4 done), `building` (Stage 5 in progress), `shipped`, `shelved`.

## Related

- [`docs/dev-cycle.md`](../dev-cycle.md) — the lifecycle these docs live inside.
- [`docs/product.md`](../product.md) — the lens every brief must pass.
- [`docs/decisions/`](../decisions/) — accepted ADRs that constrain feature designs.
- [`docs/learnings/`](../learnings/) — diary of findings; feature docs link out when a finding gets promoted.
- [`.cursor/skills/discover/`](../../.cursor/skills/discover/) — Stage 3 skill; writes into `## Feasibility`.
- [`.cursor/skills/feature-design/`](../../.cursor/skills/feature-design/) — Stage 4 skill; writes into `## Design`.
