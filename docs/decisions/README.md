# OSPlus — Architectural Decision Records

This folder holds the **architectural decisions** that OSPlus has deliberately made — each with the options that were considered and the reasoning that picked one. If it's important enough that changing it later would cost real work, it lives here.

This exists because the prior `docs/vision.md` recorded "locks" without options, which made premature decisions rigid. ADRs fix that by making **"what else did we consider"** a mandatory field.

## How to use this folder

| Path | Purpose |
|---|---|
| `NNNN-slug.md` | Individual ADR. Newest gets the next number. |
| `_TEMPLATE.md` | Template to copy. Has required sections and enforces the ≥2-options rule. |
| `_archive/` | Superseded documents preserved for historical reference. |

## When is an ADR required?

Write one before treating any of these as decided:

- A choice that, if changed later, would force a rewrite across multiple subsystems.
- A choice another agent would reasonably call "a lock" — identity model, persistence location, state ownership, wire protocol, trust boundary, API contract shape.
- A choice that commits operational cost (new infra component, new service to run, new dependency to monitor).
- A choice that forecloses future options (e.g. "no moderation layer" means moderation-dependent features are blocked until this ADR is re-opened).
- A **revision** of a prior decision. Superseding an existing ADR is itself an ADR — it doesn't get to happen silently.

When in doubt, write one. A template copy + honest options list costs ~30 minutes and saves multi-day untangling later.

## When is an ADR NOT required?

- **Policy, not architecture.** "Schema grows on demand" is a working practice, not an architectural decision. No ADR.
- **Implementation details that don't lock anything.** Picking `express` vs `fastify` doesn't matter if both satisfy the contract. Picking whether the profile API is HTTP vs WebSocket does. The former is a coin flip; the latter is an ADR.
- **Trivial choices or refactors that preserve contracts.** Moving a file, renaming a function — no ADR.

If you find yourself writing a one-option ADR, the honest fix is usually: this isn't a decision, don't use this template. Write a note in the relevant code or doc instead.

## How to write one

1. Copy `_TEMPLATE.md` to `NNNN-slug.md` where `NNNN` is the next four-digit number (0001, 0002, …) and `slug` is short kebab-case.
2. Fill in every field. **Minimum two real options** with honest pros/cons. "Option A: do it. Option B: don't do it." is not two options — it's one option written twice.
3. Mark `Status: proposed` while it's still open for discussion.
4. Once accepted by the user, change to `Status: accepted` and commit.
5. Add the entry to the index table below (newest first).
6. If the ADR supersedes a prior one, update the prior ADR's `Status` to `superseded` and set its `Superseded by`.
7. If the ADR invalidates claims in `AGENTS.md`, `docs/product.md`, `KNOWLEDGEBASE.md`, or any other doc, update those docs in the same branch. The ADR is additive; fixing the stale source is separate and required.

## First-priority deliberation queue

Three ADRs are named as the first expected entries. They cover decisions previously locked in `vision.md` without options — carried into the archive, now due for honest deliberation. See [`_archive/vision-v1-superseded.md`](./_archive/vision-v1-superseded.md) for the prior state.

| Area | Prior position (now archived) | Why it needs an ADR |
|---|---|---|
| Identity model | Trust-on-claim SteamID | Community events with earned credit make spoofing real. Viable at ~25 known users; probably broken at public-mod scale. Alternatives worth examining include Steam Web API ticket validation, OAuth-via-Steam, game-observed-handshake tokens. |
| Profile storage architecture | In-process SQLite in the relay, single OCI VM | Fine at current scale. "Designed to extract later" without an actual plan is the kind of work that never happens. Alternatives worth examining: keep as-is; extract to separate service now; different storage engine. |
| Ephemeral state ownership | In-memory on the relay, no persistence | Same scaling shape as above. Alternatives: keep as-is; introduce a small in-memory store abstraction; persist selectively. |

None of these are being written *in this folder-creation commit* — they're substantive architectural work that deserves dedicated focus. They are the first items that get ADRs once a feature forces the conversation or once deliberate deliberation time is set aside. Feature work that touches any of these three areas **must** force the ADR first; feature-design skill Phase 2 has a checkpoint for this.

## Index

Newest first.

| # | Status | Title | Date |
|---|---|---|---|
| [0001](0001-identity-model.md) | `proposed` | Bind OSPlus profiles to the Odyssey (Prometheus) account ID | 2026-04-24 |

## Related

- [`docs/product.md`](../product.md) — product definition. Where features start.
- [`.cursor/rules/decision-discipline.mdc`](../../.cursor/rules/decision-discipline.mdc) — enforcement policy.
- [`docs/learnings/`](../learnings/) — captured post-hoc findings (different purpose: diary, not architecture).
- [`.cursor/skills/feature-design/`](../../.cursor/skills/feature-design/) — feature-design skill; reaches for this folder when a feature forces an architectural decision.
