# In-game profile MVP

| Field | Value |
|---|---|
| Slug | `in-game-profile-mvp` |
| Status | `framed` |
| Created | 2026-04-24 |
| Last updated | 2026-04-24 |
| Owner | agent + maintainer |
| Branch | `feat/in-game-profile-mvp` |

---

## Brief
*(Stage 2 — Frame.)*

**Problem:** OSPlus today has no persistent binding between the local player's Odyssey account and an OSPlus profile row, and the per-match state the game discards at match-end (redirects, per-character outcomes, any other transient observable) is not captured anywhere. Without the binding, future wedge features (unlockables, events, consolidated stats) have no stable subject to attach to. Without raw capture, no later feature can render derived stats that the game itself doesn't store.

**Audience:** Primary OSPlus audience per [`docs/product.md`](../product.md) — non-veteran players, with mid-skill players as the sharpest slice. For this MVP specifically, **no user-facing surface is required to satisfy the audience.** The audience is served indirectly by the features this MVP unblocks; directly, this is substrate plumbing.

**Wedge fit:** Substrate role, directly named in `docs/product.md` → Wedge + `docs/ROADMAP.md` → Next. Every later engagement-loop feature — unlockable-earning paths, consolidated stats displays, event credit, flair — depends on an Odyssey-account-bound profile and on having captured the raw data they compute from. Shipping those features without this MVP would force each to reinvent identity + capture. Shipping this MVP without them is inert but unblocking.

**Anti-goal check:** Passes every anti-goal in `docs/product.md`:

- **Cheat-adjacent:** no. Capture is strictly the local player's own observable state; no opponent data, no in-match HUD exposing hidden info, no predictive overlay.
- **Monetization:** no.
- **NSFW/NSFL:** n/a — no user-generated content at MVP.
- **Pure silliness / caricature:** n/a.
- **Cross-game:** OS-only.
- **Wholesale native UI replacement:** no. The MVP may have no in-game display surface at all; any debug surface added is strictly additive.
- **Assumes Odyssey cooperation:** no — but see filter 3 below.

**Three-filter test (`docs/product.md` → Anti-goals):**

1. Reinforces retention of non-veteran players — yes, indirectly (unlocks every feature that will).
2. Avoids cheat territory / ToS amplification — yes.
3. Survives the next Odyssey patch with zero work — **partial / known risk.** Identity resolution uses `PMIdentitySubsystem` / `PMPlayerPublicProfile`; raw capture will similarly rely on engine-internal objects or hooks. A patch could shift these. Carried as a named Feasibility assumption, not a Brief-level blocker.

**Loose success criteria (signal-based, not metric-based):**

- OSPlus launches and resolves the local Odyssey account; a profile row exists bound to that account and survives restart.
- After N played matches, N raw capture records exist for those matches. At minimum, each record contains player redirects (the exemplar case); Stage 3 decides what else is cheap to add without duplicating game-stored data.
- Identity model and storage shape shipped under accepted ADRs (`0001-identity-model`, `0002-profile-storage`) — not silently-adopted defaults.
- At least one follow-on feature (first unlockable-earning path, or a consolidation pass) can be implemented against this substrate without having to touch identity or capture plumbing.

**Out of scope (explicit, so it's not assumed):**

- **No consolidation / ETL.** Raw capture only. Turning per-match records into useful derived stats (win-rate-as-character, redirect averages, streaks, grading) is a separate follow-on feature.
- **No stats display.** Anything beyond possible debug visibility of "capture is working" is deferred. The roadmap's "two visible stats" acceptance hint belongs to the consolidation feature, not this MVP.
- **No unlockables.** Grants, earning paths, ownership flags, cosmetic gating — all explicitly the "First unlockable-earning path" roadmap item, not this MVP. The prior `mod/OSPlus/scripts/emotes.lua` / `native_emotes.lua` on disk are out of scope here.
- **No OSPlus-exclusive content.** Voice-lines and any other new-asset customization are deferred until they have their own feature design with an asset-pipeline discussion.
- **No viewer mode.** Self-only at MVP.
- **No analytics / grading / leaderboards / performance scoring.**
- **No change to public distribution.** Stays in the SA-community distribution scope.
- **No identity posture beyond the ADR.** Whatever `0001-identity-model` lands on, MVP conforms.
- **No storage topology beyond the ADR.** Including where raw capture records live (local-per-install, sidecar-local, relay-remote, or split) — `0002-profile-storage` decides, MVP conforms.

---

## Feasibility
*(Stage 3 — Discover. To be filled by the `discover` skill before Design.)*

**Verdict:** *(pending)*

**Confidence rationale:** *(pending. Much of Stage 3 is retrospective write-up of prior exploration already on disk — `mod/OSPlus/scripts/identity.lua`, `mod/OSPlus/scripts/profile.lua`, `server/profile/index.js`, and the learnings `playernameprivate-transient-account-id.md` + `playernameprivate-machine-name-out-of-match.md`. The capture side is new investigation.)*

**Assumptions (named, not buried):** *(pending)*

**Evidence trail:** *(pending — tasks queued for Stage 3):*

- *Identity surface: audit `identity.lua` + the two learnings; confirm `PMIdentitySubsystem:GetSteamId()` stability across menu/lobby/match, `PMPlayerPublicProfile` population timing.*
- *Capture surface: enumerate `PM*` subsystems and other game objects that already hold per-match state; what the game stores, where, and for how long (does it survive match-end? map-load? game restart?).*
- *Tracker ecosystem inventory: what external tools exist, what their data source is, what they expose, what they can't — so MVP captures the non-duplicative gap. Starting points named by maintainer: [`stats.omegastrikers.gg`](https://stats.omegastrikers.gg/) (carries an "Odyssey Interactive" copyright line; possibly endorsed or first-party-adjacent) and [`clarioncorp.net`](https://clarioncorp.net/) (third-party, explicitly NOT Odyssey-endorsed). Clarion publishes a GitHub org [`ClarionCorp`](https://github.com/ClarionCorp) with a `PublicAPI` repo described as "A Public API Proxy for Omega Strikers" and docs at `docs.clarioncorp.net` — this proxies what the maintainer believes is an internal Omega Strikers backend ("Prometheus Proxy") which is otherwise undocumented. Stage 3 treats Clarion's repo + docs as a concrete entry point for understanding the upstream OS API surface rather than cold-researching it.*
- *Observability of redirects specifically: name the concrete hook / object we'd watch during a match to count them.*
- *Capture frequency/volume: rough sizing of per-match record shape (bytes, rows per match) — feeds the storage ADR.*

**Promoted findings:** *(pending)*

**Recommended Stage 5 path:** *(pending)*

---

## Design
*(Stage 4 — Feature design. Filled after Stage 3 verdict + sign-off and after the two forced ADRs are accepted.)*

**Approach:** *(pending)*

**Axes considered:** *(pending)*

**Decisions deferred to ADR:**

- **Identity model** — forced ADR, `docs/decisions/0001-identity-model.md`. Archived position: trust-on-claim SteamID. Alternatives to name honestly: Steam Web API ticket validation, OAuth-via-Steam, game-observed handshake tokens.
- **Profile storage architecture** — forced ADR, `docs/decisions/0002-profile-storage.md`. Archived position: in-process SQLite in the relay. The raw-capture framing expands this ADR's scope — it now has to answer *where raw per-match records live*, not just where profile rows live. Alternatives to name: all-local (per-install SQLite / flat file), all-remote (every capture hits the relay), split (local capture + remote profile binding, reconciled later).

**Files that will change:** *(pending)*

**Files that will NOT change but matter:** *(pending)*

---

## Outcome
*(Stage 6 — Land.)*

**Result:** *(pending)*

---

## Notes

**Prior exploration on disk (Stage 3 input, not yet wired):**

- `mod/OSPlus/scripts/identity.lua` — resolves `SteamId` via `PMIdentitySubsystem:GetSteamId()`; resolves friendly display name via `PMPlayerPublicProfile` with fallback handling for account-ID-shaped and machine-name-shaped values. Referenced learnings: `docs/learnings/playernameprivate-transient-account-id.md`, `docs/learnings/playernameprivate-machine-name-out-of-match.md`.
- `mod/OSPlus/scripts/profile.lua` — minimal poll + push; emits a `profile_identity` IPC event when both identity fields are ready.
- `server/profile/index.js` — `better-sqlite3`-backed profile module with `upsertIdentity`, `getProfile`, and `GET /profiles/:steamId`. **Pre-commits one corner of the profile-storage ADR** (relay-side SQLite). Its existence is evidence for feasibility, not a design decision.
- `server/data/` — empty directory, SQLite target.
- `mod/OSPlus/scripts/emotes.lua` / `native_emotes.lua` — **out of scope** for this MVP (no unlockables). Remain on disk for the later "First unlockable-earning path" feature.

**Open questions deferred to Stage 3 or Stage 4, not Stage 2:**

- Which concrete per-match state lands in the MVP capture set? Redirects are named as the exemplar; what else is cheap to add without duplicating game-stored data? (Stage 3 enumerates options; Stage 4 chooses.)
- Where does raw capture data physically live? (Profile-storage ADR.)
- What debug visibility, if any, ships with the MVP so "capture is working" is provable without grepping the relay DB? (Stage 4.)

**Explicit Brief ↔ Roadmap tension recorded here so it isn't lost:**

The roadmap's acceptance hint for "In-game profile scaffolding" ("player opens profile panel and sees two game-derived stats") expected a *visible* MVP. This feature's MVP is **plumbing-only**: no consolidation, no stats display, no panel. The visible MVP described by the roadmap is now a follow-on feature (probably bundled with "First unlockable-earning path" or a dedicated "profile display MVP"). This split came out of the Stage-2 Frame conversation and is an improvement — it separates the substrate decision from the display decision, so both can be small enough to ship.
