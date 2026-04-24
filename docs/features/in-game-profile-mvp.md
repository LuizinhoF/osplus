# In-game profile MVP

| Field | Value |
|---|---|
| Slug | `in-game-profile-mvp` |
| Status | `feasibility` (Pass 1 complete; Pass 2 pending in-game probes) |
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
*(Stage 3 — Discover. Split into two passes per maintainer direction: Pass 1 = code + web only; Pass 2 = in-game probes. Pass 1 complete.)*

**Verdict (Pass 1 scope — identity surface + external-API inventory):** `High`.
**Overall verdict pending** Pass 2 completion of the capture-surface investigation. No Pass-1-scope showstoppers found; the capture-surface is the remaining uncertainty.

**Confidence rationale:**

- *Identity surface:* substantial retrospective evidence. `identity.lua` already implements three-mode rejection (hex-ID / machine-name / empty) and a friendly-name resolver with documented fallbacks. Both edge cases have confirmed learnings. `PMIdentitySubsystem:GetSteamId()` has a real observed value recorded in `KNOWLEDGEBASE.md` (`76561198022185004`). The binding key for a profile row (SteamID) is available and reliable.
- *External-API inventory:* three independent community projects (ClarionCorp, Strikr-GG, omega-strikers-tracker/stlr.cx) confirm the same upstream data source with the same auth pattern. Clarion's v2 `/players/<id>` documented response shape lets me characterize precisely what the tracker ecosystem covers — and, by absence, what it doesn't.

**Assumptions (named explicitly — Stage 5 walls need something to land on):**

1. `PMIdentitySubsystem:GetSteamId()` is callable and returns the same 17-digit SteamID across all four runtime contexts: main menu, lobby, in-match, post-match. *Verified in at least one context (`KNOWLEDGEBASE.md`); not exhaustively verified across all four.*
2. `PlayerState.PlayerNamePrivate`'s "account-ID mode" value is a **Prometheus ID**, not a SteamID. Clarion's v2 API shows Prometheus IDs as 24-char hex MongoDB-style ObjectIDs (e.g. `6333a58673a37dc7cb11a7a7`); learning `playernameprivate-transient-account-id.md` observed 20-char lowercase hex in the client. The discrepancy is unresolved — possible explanations: account vintage, client-side truncation, or different ID namespace. **Needs a Pass-2 probe** comparing the `PlayerNamePrivate` raw value against Clarion's returned ID for the same player.
3. The local player's Prometheus ID is **NOT** reliably obtainable via `FindAllOf("PMPlayerPublicProfile")` — confirmed per learning #1 (109 instances found; none matched the local account). Candidate alternative paths: `PMPlayerModel.GetCachedMeResponseV1` / `GetDisplayNameV1` (UFunctions with out-param + UScriptStruct; `KNOWLEDGEBASE.md` flags these as "not trivially callable from Lua"), or `PlayerState.PlayerNamePrivate` during the replication window (currently rejected by `identity.lua` as "looks like an ID"). **Needs a Pass-2 probe** to determine the cleanest resolution path.
4. Redirects are **NOT** exposed via the Prometheus API surface that trackers expose. Inferred from: Clarion's `/players/<id>` per-character rating schema includes `games`, `wins`, `losses`, `mvp`, `knockouts`, `assists`, `saves`, `scores` but **no `redirects` field**. Cross-referenced: the entire community tracker ecosystem treats redirects as a non-exposed metric. *Not exhaustively verified* against Prometheus's full (partially-undocumented) endpoint surface.
5. Runtime observation of redirects from the running client (via UE4SS hook or polling game state) is feasible. **Completely unverified** — this is the core Pass-2 question.
6. `PMIdentitySubsystem:GetIdentityState() == 2` means "authenticated." Value observed per `KNOWLEDGEBASE.md`; enum semantics inferred from name only, not confirmed by reflection of the enum definition.

**Evidence trail:**

### Identity surface (retrospective)

- `mod/OSPlus/scripts/identity.lua` — 209 lines. Resolves `SteamId` via `FindFirstOf("PMIdentitySubsystem"):GetSteamId()`. Resolves display name via a sequence: fast path (if `PlayerState.PlayerNamePrivate` is usable, cache it), slow path (walk `FindAllOf("PMPlayerPublicProfile")` looking for `PlayerId == localId`), reject path (account-ID-shaped hex, machine-name-shaped from `COMPUTERNAME`/`HOSTNAME`). Returns `nil` rather than a bad value; callers fall back to `Player-<last4OfSteamId>` synthetic label.
- Learning `docs/learnings/playernameprivate-transient-account-id.md` (confirmed, 2026-04-19): `PlayerNamePrivate` holds the account ID during the pre-replication window and the friendly name after. Fix: hex-shape heuristic + deferred relay JOIN until friendly name is cached.
- Learning `docs/learnings/playernameprivate-machine-name-out-of-match.md` (confirmed, 2026-04-20): adds the third observed mode (local Windows machine name out-of-match). Fix: three-layer rejection across mod / sidecar / relay so a bad client value can't become authoritative anywhere.
- `KNOWLEDGEBASE.md` lines 708–720 — Player Identity Reference: documents the three verified reads (`PlayerNamePrivate`, `PMIdentitySubsystem:GetSteamId()`, `GetIdentityState()`), with real-world observed values.

### External-API inventory (Prometheus ecosystem)

- **"Prometheus"** is Odyssey Interactive's internal backend API for Omega Strikers. Confirmed by Clarion docs: *"This is the API that Odyssey created for Omega Strikers. We will be calling it Prometheus in the event that more games pop up in the future."* No public Odyssey-run documentation exists; every community tool has reverse-engineered it independently.
- **Auth:** JWT pair (`ODYSSEY_TOKEN` + `ODYSSEY_REFRESH_TOKEN` per `Strikr-GG/strikr-api` README). Tokens obtainable via (a) live capture with Fiddler Classic, or (b) Steam-Ticket → Odyssey auth flow (per Clarion docs; guide pending from them). The Strikr-GG author signed an NDA with Odyssey after reverse-engineering the API — community posture is "grey zone, not endorsed, not prosecuted."
- **Community proxies** (all taps of the same upstream):
  - [`stats.omegastrikers.gg`](https://stats.omegastrikers.gg/) — NOT Odyssey-run despite the domain. Surfaces: Ranked Leaderboard, Mastery Leaderboard, Map Rotation, Wiki, Omega Casino.
  - [`clarioncorp.net`](https://clarioncorp.net/) + [`api.clarioncorp.net`](https://api.clarioncorp.net/) — Discord-OAuth account system, links Discord ↔ OS account. Explicit "not endorsed by Odyssey Interactive" disclaimer. v2 API publicly documented at [`docs.clarioncorp.net`](https://docs.clarioncorp.net/).
  - [`strikr.gg`](https://strikr.gg/) — same upstream, similar architecture.
  - [`omegastrikers.stlr.cx`](https://omegastrikers.stlr.cx/) (ckhawks/omega-strikers-tracker) — personal project, same upstream, per-match drill-down UI.
- **Clarion v2 `/players/<id>` response shape** (concrete observed example — player `blals`, ID `6333a58673a37dc7cb11a7a7`):
  - **Player metadata:** `id` (24-char Prometheus ID), `username`, `region`, cosmetic IDs (`logoId`, `nameplateId`, `emoticonId`, `titleId` + resolved english `title`), `currentXp`, `playerStatus` (`Online`/`Offline`), `discordId` (Clarion-linked, not Prometheus).
  - **Per-character ratings:** `character` (e.g. `CD_WhipFighter`), `role` (Forward/Goalie), `gamemode` (e.g. `RankedInitial`), with aggregates: `games`, `wins`, `losses`, `mvp`, `knockouts`, `assists`, `saves`, `scores`. **No `redirects`.**
  - **Ratings (by season):** `rating`, `rank`, `wins`, `losses`, `games`, `masteryLevel`.
  - **Mastery:** `currentLevel`, `currentLevelXp`, `totalXp`, `xpToNextLevel`.
- **Per-match data observed via omega-strikers-tracker UI:** match UUID (e.g. `e97562ec-a96b-4d0d-9263-16528dd126f3` — not the ObjectID format), map name, final score, duration, timestamp, per-team rank tier + favorability delta. Likely implies a Prometheus `/matches/<id>` endpoint exists. **Per-match event-level data (who scored when, redirects per match) is NOT visible anywhere in the tracker ecosystem** — strongest available signal that it's the genuine capture gap.

### The three-identifier distinction (new finding, material to the identity ADR)

Three identifiers are in play, previously conflated in the Brief:

| Identifier | Shape | Source | Stable? | Used by |
|---|---|---|---|---|
| **SteamID** | 17-digit decimal (e.g. `76561198022185004`) | `PMIdentitySubsystem:GetSteamId()` | Yes, cross-platform, cross-session | Steam, OSPlus today |
| **Prometheus ID** | 24-char hex / MongoDB ObjectID (e.g. `6333a58673a37dc7cb11a7a7`) | Game backend | Yes, assumed | All OS tracker tooling as their canonical player key |
| **Display name** | Friendly string | Replicated to `PlayerNamePrivate` | No — user-mutable | Human UI |

Implication: if an OSPlus profile ever wants to interoperate with tracker-ecosystem aggregate data (surfacing "you have X redirects per match; your community's 25th/50th/75th percentile is Y"), the profile needs the **Prometheus ID as well as the SteamID**. Current `identity.lua` resolves SteamID and friendly name; it does not separately surface the Prometheus ID.

This is an identity-ADR-shaping finding, not a Brief-level reshape — the ADR's options list now has to answer "which of the two IDs is the primary binding key?" rather than assume SteamID.

**Promoted findings (pending maintainer sign-off before I write them):**

1. **Propose adding a "Prometheus API ecosystem" section to `KNOWLEDGEBASE.md`** — documenting: what Prometheus is, auth shape, community proxies, what the API exposes vs. doesn't. Future features that ask "is X available server-side?" will reference this. **Obviously general** per `learnings-discipline.mdc`, but large enough that I want explicit sign-off before writing.
2. **Propose adding the three-identifier distinction to `KNOWLEDGEBASE.md`'s existing "Player Identity Reference" section** — clarifying that `PMPlayerPublicProfile.PlayerId` is a Prometheus ID, not a SteamID, and that the two are independent namespaces.
3. **Propose a new learning `docs/learnings/os-prometheus-api-ecosystem.md`** — shorter diary-style entry capturing that these external trackers exist, what they share, and what their limitations are. Saves the next session from rediscovering cold.

**Pass 2 remaining tasks (need in-game access; maintainer flagged as available).** Six tasks, grouped by surface. The probe pack below ships the Lua snippets for the scripted ones.

**Identity surface:**

1. Verify assumption #1: `PMIdentitySubsystem:GetSteamId()` returns the same value across menu / lobby / in-match / post-match.
2. Resolve assumption #2: raw `PlayerNamePrivate` shape during the replication window — is the hex form 20 or 24 chars, and does it equal the Clarion-documented Prometheus ID for the same account?
3. Resolve assumption #3: Probe `PMPlayerModel.GetCachedMeResponseV1` / `GetDisplayNameV1` from Lua. Can we get the local Prometheus ID cleanly, or is the UFunction signature genuinely blocking?

**Capture surface:**

4. Enumerate loaded `PM*` objects in a live match. What does the game already hold per-match? Lifetime across match-end / map-load / restart?
5. Identify the concrete signal for "the local player redirected the puck" (UE hook, property, or event).
6. Volume sizing: roughly how many redirects per player per match? Feeds the storage ADR's high-frequency vs. low-frequency axis.

### Pass 2 probe pack

**How to run these.** F10 is the Unreal `Exec` console (engine commands), not a Lua REPL; pasting Lua there does nothing. The probes run as a **separate throwaway mod** (`OSPlusProbes`), not inside `OSPlus`. Install per [`docs/features/pass2-probes/README.md`](./pass2-probes/README.md), restart the game once, then:

- **F11** = one-shot snapshot battery (A1 + A3 + B1 + B2). Press once per game context.
- **F12** = A2 polling (reads `PlayerNamePrivate` every 500ms for 15s). Press during character-select.
- **B3** = manual observation during 2–3 practice matches.

Runnable source: [`docs/features/pass2-probes/pass2_probes.lua`](./pass2-probes/pass2_probes.lua). Output lands in `Binaries\Win64\ue4ss\UE4SS.log`, tagged `[A1]` / `[A2]` / `[A3]` / `[B1]` / `[B2]` / `[Pass2]`. All probes are `pcall`-wrapped with `:IsValid()` checks; a "not found" line in some contexts is expected data, not a failure.

Below: per-probe summary of *what each tests* and *what the output means*. The Lua lives only in `pass2_probes.lua` (single source of truth).

---

**Probe A1 — SteamID stability across contexts.** Tests assumption #1. Reads `PMIdentitySubsystem:GetSteamId()` and `:GetIdentityState()`. Run in each of: main menu, character-select, active match, post-match. Prints one `[A1]` line per press.

**Expected:** same `SteamId` value in all four contexts, `IdentityState=2`. A divergence from either would mean the identity binding has a context-dependent read — material finding for `0001-identity-model`.

---

**Probe A2 — `PlayerNamePrivate` shape over time.** Tests assumption #2. Polls `PlayerState.PlayerNamePrivate` every 500ms for 15s (30 samples) during character-select, to catch the hex → friendly transition window. Prints one `[A2]` line per sample with the raw value, its length, and whether it looks hex-shaped.

**Expected:** early samples return a lowercase hex string; later samples return the friendly display name. The critical datum is the **length** of the hex form. **If `len=24`**, the hex string matches Clarion's documented Prometheus ID format — which would mean `PlayerNamePrivate`'s early-window value **IS** the local Prometheus ID and resolves assumption #3 without needing `PMPlayerModel`. **If `len=20`**, there's a different ID format in play; further probing needed.

---

**Probe A3 — `PMPlayerModel` UFunction callability.** Tests assumption #3. Calls `GetCachedMeResponseV1`, `GetDisplayNameV1`, `GetCachedPlayerPublicProfile` on the `PMPlayerModel` singleton with no args. Prints `[A3]` lines with `ok=` and `ret=` per call.

**Expected:** errors or nil returns are the likely outcomes — confirming KB's "not trivially callable". A string return from `GetDisplayNameV1` would be a significant find — a clean local-player name path that bypasses the `PlayerNamePrivate` three-mode drama entirely.

---

**Probe B1 — `PM*` object enumeration.** Tests capture-surface task #4. Walks a fixed list of 12 guessed `PM*` class names; for each, prints `[B1] <kind> : N instance(s), class=<fullClass>` or `[B1] <kind> : not found`. Not exhaustive — depends on us having guessed the class names.

**For the exhaustive enumeration** (recommended once, in-match): use UE4SS's built-in object dumper via the UE4SS GUI (`Dumpers` tab → `Dump all objects and properties`). Writes a large `.txt` next to `UE4SS.log`; grep for `/PM` or `PM*` class names. Run during active gameplay to catch match-only objects.

---

**Probe B2 — Redirect-signal hypothesis scan.** Tests capture-surface task #5. Walks the local Pawn's UFunction list looking for names matching redirect-related patterns (`Redirect`, `HitPuck`, `Bounce`, `Kick`, `Smash`, `Impact`, `Contact`, `Deflect`, etc.); also probes a guess list of ball/puck actor classes. Exploratory — negative results narrow the hypothesis space.

**Expected:** at least one pattern group probably hits something on the Pawn class or a component; the names feed a follow-up session that hooks the function and counts calls. **If no hits**, redirects likely aren't exposed as a named UFunction — next hypothesis is a replicated property on `PlayerState` that increments (observable via polling) or a tagged gameplay event.

---

**Observation B3 — Redirect volume sizing.** Tests capture-surface task #6. No script — play 2–3 full practice matches, loosely count how often you deliberately redirect the puck per match. Rough range is enough. Pins the storage ADR's write-frequency axis (5–10 writes per match vs. 50–100 is a different ADR conversation).

---

**What Pass 2 needs back from maintainer.** Per the README's "Report output" section: which context each press was made from, plus the `[A*]` / `[B*]` log lines. Stack traces too if anything native-crashes the game (that's also useful data).

**Recommended Stage 5 path (conditional on Pass 2 results):**

- **Identity binding:** `full feature` path. Surface is High-confidence with two documented edge-case fixes already on disk. Retrospective integration of `identity.lua` into `main.lua`.
- **Raw capture pipeline:** `thin slice first`. MVP captures redirects only, validates the runtime-observation assumption (which is currently Low-confidence), then expands. If Pass 2 reveals redirects are not cheaply observable, the capture-side verdict may drop to Low and re-enter Stage 3 for a spike.
- **Storage:** waits for `0002-profile-storage` ADR. The Pass-2 volume sizing feeds the ADR's options.

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

**Open questions deferred to Stage 4 or later passes of Stage 3:**

- *[Pass 2]* Which concrete per-match state lands in the MVP capture set beyond redirects? Needs the `PM*` subsystem enumeration from a live match to know what's cheap.
- *[Stage 4]* Where does raw capture data physically live? Answered by `0002-profile-storage`.
- *[Stage 4]* What debug visibility, if any, ships with the MVP so "capture is working" is provable without grepping the relay DB?
- *[Stage 4]* Which identifier is the profile row's primary binding key — SteamID or Prometheus ID? The three-identifier finding in Pass 1 Feasibility makes this an explicit ADR decision, not a default.
- *[Stage 4]* Does `identity.lua` get extended to surface the Prometheus ID, or is that a separate feature?

**Explicit Brief ↔ Roadmap tension recorded here so it isn't lost:**

The roadmap's acceptance hint for "In-game profile scaffolding" ("player opens profile panel and sees two game-derived stats") expected a *visible* MVP. This feature's MVP is **plumbing-only**: no consolidation, no stats display, no panel. The visible MVP described by the roadmap is now a follow-on feature (probably bundled with "First unlockable-earning path" or a dedicated "profile display MVP"). This split came out of the Stage-2 Frame conversation and is an improvement — it separates the substrate decision from the display decision, so both can be small enough to ship.
