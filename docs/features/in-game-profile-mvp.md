# In-game profile MVP

| Field | Value |
|---|---|
| Slug | `in-game-profile-mvp` |
| Status | `stage-5-build-in-progress` (Passes 1–6 complete; ADR 0001 substrate end-to-end-validated; identity-resolver implementation in flight) |
| Created | 2026-04-24 |
| Last updated | 2026-04-25 |
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

**Loose success criteria (signal-based, not metric-based) — narrowed at Stage 4 to profile + auth only; raw capture is now a follow-on feature, see *Follow-on features* in Notes:**

- OSPlus launches and resolves the local Odyssey account; a profile row exists bound to that account (PrometheusID PK + cosmetic loadout) and survives restart.
- Identity model and storage shape shipped under accepted ADRs (`0001-identity-model`, `0002-profile-storage`) — not silently-adopted defaults.
- The substrate built here (auth middleware, sidecar HTTP client + token storage, mod → sidecar IPC shape) is reusable by the first follow-on feature without touching identity or persistence plumbing — captures rides this exact substrate plus its own DB and routes; unlockable-earning hangs ownership flags on the profile row built here.

**Out of scope (explicit, so it's not assumed) — see *Follow-on features* in Notes for the named next steps:**

- **Raw match capture pipeline.** Originally bundled into this MVP's Brief; deferred to a dedicated follow-on feature at Stage 4 because the substrate work for profile+auth alone is a clean reviewable unit and captures has its own discovery sub-questions (capture scope, match-ID strategy, which `PMPlayerMatchSummary` siblings to persist) that don't share a clock with profile+auth. ADR 0002 already pins where captures will live (`osplus_captures.sqlite3` per R-Y) — only the build is deferred, not the architectural commitment.
- **No consolidation / ETL.** Even when the capture follow-on lands, it's raw capture only. Turning per-match records into derived stats (win-rate-as-character, redirect averages, streaks, grading) is a separate later feature.
- **No stats display.** Anything beyond possible debug visibility of "capture is working" is deferred. The roadmap's "two visible stats" acceptance hint belongs to the consolidation feature, not this MVP.
- **No unlockables.** Grants, earning paths, ownership flags, cosmetic gating — all explicitly the "First unlockable-earning path" roadmap item, not this MVP. The prior `mod/OSPlus/scripts/emotes.lua` / `native_emotes.lua` on disk are out of scope here.
- **No OSPlus-exclusive content.** Voice-lines and any other new-asset customization are deferred until they have their own feature design with an asset-pipeline discussion.
- **No viewer mode.** Self-only at MVP.
- **No analytics / grading / leaderboards / performance scoring.**
- **No change to public distribution.** Stays in the SA-community distribution scope.
- **No identity posture beyond the ADR.** Whatever `0001-identity-model` lands on, MVP conforms.
- **No storage topology beyond the ADR.** Including where raw capture records live — decided by [ADR 0002](../decisions/0002-profile-storage.md) (accepted 2026-04-25): server-side, two SQLite files (profile + auth in `osplus.sqlite3`, captures in `osplus_captures.sqlite3`), in the existing chat-relay process, served over HTTP REST, gated by per-install bearer tokens TOFU-bound to the player's Prometheus ID. MVP conforms.

---

## Feasibility
*(Stage 3 — Discover. Split into Pass 1 (code + web), Pass 2 (in-game probes), Pass 3 (in-game cross-check + GUI Object Dumper). All three passes complete.)*

**Post-Pass-3 verdicts:**

- *Identity resolution:* `High`. The local-Prometheus-ID path is fully characterized: `PMPlayerModel:GetCachedMeResponseV1(out WasCached, out OutMeResponse)` returns a `MeResponseV1` struct that **inherits from `PlayerPublicProfile`** (UE `ScriptStruct` `sps` chain confirmed in the dumper output). One sync call yields `PlayerId` (Prometheus ID), `Username`, `PlatformIds` struct (the SteamID crosswalk), and the full cosmetic loadout. Signatures, parameter shapes, and inheritance chain are all in `docs/learnings/os-runtime-data-model.md`. *Single residual gap:* the exact UE4SS calling convention for output-param placeholders (e.g. `(false, nil)` vs `(false, {})`) is build-dependent; one Pass-4 in-game probe call validates it before any feature relies on it.
- *Capture surface:* `High`. The redirect counter is reachable: `/Script/Prometheus.PMPlayerMatchSummary:RedirectRock : Int`. Sibling counters on the same struct cover ShotsOnGoal, Damage, PowerUps. The full per-match stat universe is enumerated by `EPMEndOfGameStat` (9 entries); 4 of 9 are already mapped to `PMPlayerMatchSummary`. The puck/ball is internally called *Rock* — `PMRockCharacter:LastRedirectKnockBack` carries per-event detail, and `EKnockBackType::Redirect = 2` confirms redirects are a classified knock-back type. Per-match raw capture is feasible without instrumentation — just read existing structs.

**No remaining feasibility blockers.** Both forced ADRs (`0001-identity-model`, `0002-profile-storage`) are now writable.

**Binding key decision (maintainer-stated, not ADR-gated):** The profile's primary binding key is the **Odyssey (Prometheus) account ID**, not SteamID. Rationale: Omega Strikers may be playable outside Steam (other launchers / platforms); SteamID is platform-specific, Odyssey identity is platform-agnostic and travels with the account. SteamID remains useful as a **secondary** identifier (cross-reference for Steam-sourced enrichments, fallback if Prometheus resolution fails at startup), not the primary key. This reshapes `0001-identity-model`: the ADR question becomes *"how do we resolve the Odyssey ID reliably?"* rather than *"which ID is primary?"* — making the Pass-3 UFunction signature discovery critical-path for the ADR, not optional.

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

### Pass 2 findings

*(Session: 2026-04-24, solo custom game, account `Ispicas` / SteamID `76561198022185004`, character NimbleBlaster. Six F11 presses across menu / char-select pre-pick / char-select post-pick / in-match / awakening-select / post-match; one F12 poll during char-select; B3 pending.)*

**Assumption updates:**

| # | Assumption | Pass 1 | Pass 2 result | New status |
|---|---|---|---|---|
| 1 | SteamID stable across contexts | Med-High | 6/6 presses identical: `SteamId=76561198022185004 IdentityState=2` | **High (definitive)** |
| 2 | `PlayerNamePrivate` passes through a hex window for the local player | Medium | 30/30 polled samples returned friendly name `"Ispicas"` at `len=7`. Zero hex window observed for local player in a solo custom game. | **Falsified for local / custom.** New hypothesis: hex window is a **remote-player replication phenomenon**, not local; matchmade public games unverified. |
| 3 | `PMPlayerModel` getter UFunctions not trivially callable | Medium | All three errored with `UFunction expected 2 parameters, received 0` — **callable, just wrong arity.** Signatures unread. | **Med-High (signatures are the gate, not callability).** Critical path for the Odyssey-ID binding-key decision. |
| 4 | `PM*` inventory must be probed live | Low | 3-of-12 guesses confirmed in-match: `PMIdentitySubsystem` (1), `PMPlayerModel` (2), `PMPlayerPublicProfile` (111). `PMPlayerState` resolves to a BP subclass `PlayerState_Game_C` under `/Game/Prometheus/Blueprints/Core/`. Other 8 guesses absent — names are wrong, not the objects. | **Low+** — partial inventory, exhaustive dump still needed. |
| 5 | Redirect signal hypothesis (UFunction on Pawn) | Low | Pawn class `C_NimbleBlaster_C` — `ForEachFunction` ran cleanly; **zero** pattern matches for Redirect/HitPuck/Bounce/Kick/Smash/Impact/Contact/Deflect across in-match + awakening contexts. | **Falsified for Pawn class.** Next hypothesis space: components of Pawn, ball/puck actor, replicated properties on `PlayerState_Game_C`, gameplay tags. |
| 6 | Redirect-volume sizing | Low | Pending (B3 — manual observation during practice). |  |

**Incidental findings worth keeping:**

- **`PMPlayerPublicProfile: 111 instances` across all 6 contexts** (menu through post-match). Suspiciously stable count — strongly suggests Odyssey pre-populates a profile-cache pool at load. If the cache shadows the Prometheus `/players/<id>` response shape, it's a **passive capture surface** readable *without* calling the API. Worth a Pass-3 drill into one of the instances to characterize its property set.
- **`PMPlayerModel: 2 instances` across all 6 contexts.** Two models everywhere, not one. Common UE pattern would be one "me" model + one scratch/cache/query slot. If `GetCachedMeResponseV1` expects 2 parameters, the first might be a target model pointer — worth testing once signatures are known.
- **`PlayerState_Game_C` is the real class in play for match state.** The C++ `PMPlayerState` parent is a template; the live BP subclass is what `FindAllOf("PMPlayerState")` actually returns. Any future probe targeting "player state properties" should query `PlayerState_Game_C` directly, not the parent.
- **The known `identity.lua` 3-mode rejection is still correct**, but its rationale updates: the hex-shape rejection is defending against **remote-player bleed contaminating a local read**, not against local-player replication transience. This wasn't clear pre-Pass-2.

**Matchmade verification gap (explicit open question):** A2's local-stable finding came from a solo custom game. Public matchmade games have remote PlayerStates replicating in. They are expected to behave identically for the *local* PlayerState, but unverified — noted in `identity.lua`'s assumption pool.

### Pass 3 scope

Two parallel tasks (one Lua probe, one GUI action), both run in a single **active-match** session. Scoped to resolve the identity ADR's critical path and push the capture-surface hypothesis space from "falsified Pawn" to "specific component / actor / property confirmed or falsified."

**Primary task — GUI object dumper during active match.** UE4SS's built-in dumper writes every live UObject (class + properties + UFunctions with full parameter signatures) to a large `.txt` alongside `UE4SS.log`. Run during active gameplay to capture match-only objects. Targets:

- **UFunction signatures for `PMPlayerModel.GetCachedMeResponseV1` / `GetDisplayNameV1` / `GetCachedPlayerPublicProfile`** — parameter types + names. **Critical path for `0001-identity-model`** given the maintainer-stated requirement that Prometheus ID is the binding key.
- **Exhaustive class inventory under `/Script/Prometheus.*` and `/Game/Prometheus/*`** — fixes B1's 9-of-12 miss rate. Feeds future probe rounds with real class names instead of guesses.
- **Ball/puck actor class name** — name it once, stop guessing.
- **`PlayerState_Game_C` full property + UFunction list** — evidence for whether redirects surface as a replicated property (e.g., a `Redirects` Int with net-replication flag).

**Secondary task — `F9` battery on `OSPlusProbes`.** Same-session cross-check, Lua-side. Three sub-probes under one keybind, grep tags `[C1]` / `[C2]` / `[C3]`:

1. **C1 — Pawn component enumeration.** Walks `BlueprintCreatedComponents` + `InstanceComponents` TArrays on the Pawn; per-component, class name + redirect-pattern UFunction scan. Directly tests the post-B2 hypothesis ("redirect logic lives on a component of the Pawn, not the Pawn class itself").
2. **C2 — `PMPlayerModel` UFunction introspection.** For each of the three target getters, enumerates their parameter-properties via `UFunction:ForEachProperty`. **If this API exists in this UE4SS build, the Pass-2 "expected 2 parameters, received 0" mystery resolves in-session and the identity ADR unblocks without waiting for the dumper file.** If not, the GUI dumper is the guaranteed fallback.
3. **C3 — `PlayerState_Game_C` full dump.** Property count + UFunction count + pattern-matched highlights. Tests "redirect is a replicated counter on PlayerState" as an alternative signal source.

Probe source: [`docs/features/pass2-probes/pass2_probes.lua`](./pass2-probes/pass2_probes.lua) — F9 keybind added. Install/usage: [`docs/features/pass2-probes/README.md`](./pass2-probes/README.md) — updated with the F9 section + GUI-dumper step-by-step.

**Deferred to a later pass or a dedicated session:**

- A2 matchmade verification — same F12 poll, but in a public matchmade lobby. Low-priority given the remote-bleed-only hypothesis is sufficient for MVP scope; can re-check if/when a bug surfaces.
- B3 redirect-volume sizing — still needs manual count during 2-3 practice matches.

### Pass 3 findings

*(Session: 2026-04-24, in-match. F9 battery on `OSPlusProbes` + UE4SS GUI Object Dumper run during active gameplay. Dumper output: 40 MB at `Binaries\Win64\UE4SS_ObjectDump.txt`, generated in 0.58s.)*

**Assumption updates:**

| # | Assumption | Pass 2 status | Pass 3 result | New status |
|---|---|---|---|---|
| 3 | `PMPlayerModel` getter UFunctions resolvable to a clean local-Prometheus-ID path | Med-High (callable, signatures unread) | Signatures fully read from dumper; cross-checked in-game via C2 (`ForEachProperty`). `MeResponseV1` ScriptStruct inherits from `PlayerPublicProfile` (`sps` chain). | **High via the `RegisterHook`-on-engine-UFunction path** (post-Pass-5 pivot). Pass 4 found `(Bool out, X out)` UFunctions unreachable in this UE4SS build; Pass 5 found that `MulticastInlineDelegateProperty:Add` *also* silently no-ops on this build (likely vtable mismatch — the originally-planned delegate-via-BP-wrapper path is non-functional). The pivoted substrate (RegisterHook on `PMPlayerModel:GetMeV1` or equivalent originating UFunction, identified via Pass 6 discovery probe) is proven at the registration layer (Pass 5 F6) and is the maintainer-recommended pattern (UE4SS Issue #455). See Pass 4 + Pass 5 findings sections + `docs/learnings/ue4ss-outparam-marshaling-failure.md` + `docs/learnings/ue4ss-multicast-delegate-add-silent-noop.md`. |
| 5 | Redirect signal lives somewhere in the runtime | Falsified for Pawn class (B2); component / ball-actor / PlayerState hypotheses untested | C1 confirmed: Pawn's `BlueprintCreatedComponents` are all generic engine types (no `PM*` components). C3 confirmed: `PlayerState_Game_C`'s 14 BP-defined properties + 15 BP UFunctions contain zero redirect-pattern matches. Dumper found the actual host: **`PMPlayerMatchSummary:RedirectRock : Int`** (a parallel C++ ScriptStruct, not on the Pawn or its components). | **High.** Per-match counter reachable; per-event detail also available via `PMRockCharacter:LastRedirectKnockBack`. |
| 6 | Redirect-volume sizing | Pending | Still pending (B3 — manual practice-match observation). | Unchanged — feeds storage ADR's write-frequency axis but doesn't block ADR drafting. |

**New findings (Pass-3-specific, material to ADRs):**

- **`PlayerPublicProfile` is the canonical profile shape.** 14 fields including `PlayerId : Str` (Prometheus ID, offset 0), `Username : Str`, the cosmetic-ID quad (`LogoId` / `NameplateId` / `EmoticonId` / `TitleId`), `PlatformIds : Struct` (the SteamID crosswalk path), `MasteryLevel : Int`, `CurrentPlatform : Enum`. Three structs in the dump inherit from it: `PlayerPublicProfileWithTimestamp` (adds `Timestamp`), `MeResponseV1` (adds Me-only fields), and `PMPlayerPublicProfile` UObject wraps it as a field. **All cached profile reads return some flavor of this shape.** Reshapes the storage ADR's schema axis — the profile row should be designed against this canonical shape, not invented from scratch.
- **`EPMEndOfGameStat` enumerates the per-match stat universe at 9 entries.** `PMPlayerMatchSummary` covers 4 (Redirects + ShotsOnGoal + Damage + PowerUps). The other 5 (Goals / Assists / Saves / KOs) live elsewhere — most likely on `PMPlayerState` (the C++ parent of `PlayerState_Game_C`) or a sibling summary keyed off it. **Open: not blocking ADRs**, but worth a Pass-4 grep before designing the full capture schema.
- **The puck is internally called "Rock".** `PMRockCharacter` is the puck class. `PMRockCharacter:LastRedirectKnockBack : Struct` is a per-redirect runtime field; `EKnockBackType::Redirect = 2` is the redirect-type enum value. Future per-event capture (vs. per-match aggregate) hangs off this surface.
- **`PMPlayerState` exists as a C++ parent class** (`/Script/Prometheus.PMPlayerState`) — `PlayerState_Game_C` is the BP layer extending it with orb-tracking. The 14 BP-layer properties on `PlayerState_Game_C` are all orb-mechanic state (`NumOrbsAcquired`, `OrbAwakeningsMaxStacks`, `LevelUnlockForSpecial`, etc.); the per-match counter universe lives on the C++ parent or a sibling — **not** on the BP subclass. Saved a chase down the wrong path.
- **`GetDisplayNameV1` is async.** Signature: `(WasSent: Bool, OutRequestId: Str)`. It enqueues a request and fires the multicast `GetDisplayNameV1Completed` delegate when the response arrives. Not the right tool for "what's the local Prometheus ID right now?" — that's `GetCachedMeResponseV1`. Use `GetDisplayNameV1` only when the cached profile is missing or stale (e.g., a remote player whose hex window hasn't resolved).

**Probe `OSPlusProbes/pass2_probes.lua` C3 tech debt:** The probe printed only the names that *matched* the redirect pattern, not all 14 properties / 15 UFunctions. We had to grep the dumper output to recover the full list. Worth fixing if we run C3 again — but the dumper now serves that purpose, so don't fix preemptively.

**No new identity-side gaps surfaced.** The matchmade-public verification gap from Pass 2 (does the local-stable hex-window finding hold outside solo-custom?) remains the only A2 carryover; sufficient for MVP scope per Pass 2 reasoning.

### Factual correction (from Pass 2 session)

The `OSPlusProbes` README said the log lives at `Binaries\Win64\ue4ss\UE4SS.log`. It actually lives at **`Binaries\Win64\UE4SS.log`** (no `ue4ss\` subfolder) on at least this install. Fixed in a separate commit after this Pass 2 write-up.

### Pass 4 findings — ADR 0001 acceptance spike

*(Session: 2026-04-24 → 2026-04-25, in-match. F8 keybind on `OSPlusProbes`, four iterative revisions through native-crash forensics. Persistent log at `Binaries\Win64\OSPlusProbes.log`.)*

The Pass-4 spike answered both halves of ADR 0001's acceptance prerequisite. Output landed in two new learnings (`docs/learnings/ue4ss-lua-multicast-delegate-binding.md`, `docs/learnings/ue4ss-outparam-marshaling-failure.md`) and ADR 0001 is now `accepted` (Path A — see below).

**D1 — delegate subscription substrate: VIABLE, requires ModActor BP wrapper.** UE4SS's `MulticastDelegateProperty:Add` takes `(UObject targetObject, FName | string functionName)` per the [official docs](https://docs.ue4ss.com/dev/lua-api/classes/multicastdelegateproperty.html) and [PR #1073 (Nov 2025)](https://github.com/UE4SS-RE/RE-UE4SS/pull/1073) — *not* a Lua function. Passing a Lua function is a native C++ access violation that `pcall` cannot catch (Rev-3 crash; pinpointed only because Rev-3 had crash-survivable `flog()` writing to `OSPlusProbes.log` with `flush()` per call). The binding target must be a UObject, in OSPlus that means a Blueprint actor delivered via the existing `mod-actor-pattern.md` substrate. Rev-4 introspection of the prop userdata confirmed only six method names resolve to real `function` types (`Add`, `Remove`, `Clear`, `Broadcast`, `GetFName`, `GetClass`); every other guessed name returns a `userdata` placeholder rather than `nil` — the *specific* false-friend trap that bit Rev 3.

**D2 — synchronous cache pre-check substrate: NOT AVAILABLE in this UE4SS build.** Rev-4 swept three `PMPlayerModel` `(Bool out, X out)` UFunctions (`GetCachedMeResponseV1`, `GetCachedLinkCodeV1`, `GetCachedPlayerPublicProfile`) across four placeholder shapes each. Every shape failed at the marshaling layer (`(arg, nil)` → "expected 2, received 1" because trailing `nil` is dropped; `(arg, {})` → "no table was on the stack"; `()` → "received 0"). The failure is uniform across the X-type and across the placeholder shape — broken at the signature-shape level, not per-call. Workarounds (BP wrapper, direct UProperty read, UE4SS upgrade) are documented but not built.

**Implications for ADRs and Stage 5 (Pass-4-era — see Pass 5 below for revisions):**

- **ADR 0001 was `accepted` on the R-B path with revised cold-start posture** — the warm-cache pre-check is removed from R-B's design; cold start = wait for the natural login fire (~RTT seconds at session start, not user-perceptible at the Stage-5 use-site of "have identity ready by the first IPC handshake"). Path A was chosen explicitly: pay the BP-wrapper cost once, reuse the substrate forever. R-A and R-C inherit the same UFunction-marshaling block on their warm-cache halves and are now strictly worse choices, not just less reactive ones. **(See Pass 5 findings — the BP-wrapper substrate was end-to-end-validated and found non-functional; ADR R-B substrate revised. ADR remains `accepted` under the revised substrate.)**
- **Spike artifact disposition** — the Pass-4 probe (`pass2_probes.lua` Rev 4, F8 keybind) is left in place for the next spike (likely a property-dump probe on `PMPlayerModel` to look for direct UProperty cache fields, as a future cheap warm-start path). The probe's installation README and findings are not auto-shipped — `OSPlusProbes` remains a separate UE4SS mod from `OSPlus`.

### Pass 5 findings — ADR 0001 R-B substrate end-to-end validation + pivot

*(Session: 2026-04-25, in-match. Pass 5 = end-to-end validation of the Pass-4-documented BP-wrapper substrate before committing the ADR's "Path A" to it. Probe source: `docs/features/pass2-probes/pass2_probes.lua` E1–E8 + E8.D suite, F1/F2/F3/F4/F6/F10 keybinds; ~10 iterative revisions across the suite. Persistent log at `Binaries\Win64\OSPlusProbes.log`.)*

The Pass-4 spike characterized the API surface (`prop:Add(uobject, fname)`) but not whether the API actually *works* on this UE4SS build for the `PMPlayerModel.GetMeRequestV1Completed` property type (`MulticastInlineDelegateProperty`). Pass 5 ran end-to-end: bind a real ModActor BP to the property, hook the BP UFunction with `RegisterHook`, observe whether either the engine's natural broadcast or our manual `prop:Broadcast()` call results in the bound UFunction firing.

**Result: the Pass-4-documented BP-wrapper substrate is non-functional on this UE4SS build.** Across all 6 callable methods on `MulticastInlineDelegateProperty` × all bind-shape variations × cross-actor and same-actor targets, `prop:Add` returns ok with no error, but `prop:GetBindings()` reports 0 bindings, and `prop:Broadcast()` succeeds at marshaling but invokes nothing (the `InvocationList` is empty, so the bound `RegisterHook` target never fires). The Phase D triangulation probe (F10 / E8.D) ruled out shape-specific causes:

- D2 enumerated only **6 callable methods** on this property type (`Add`, `Remove`, `Clear`, `Broadcast`, `GetBindings`, `IsValid`) — there is no alternate `AddDynamic` / `AddUFunction` / `Bind` API to fall back to.
- D3 (same-actor bind) and D4 (explicit `FName(...)` bind) both produced `Δ=0` — not a cross-actor or string-conversion bug.
- D6 reproduced the cross-actor failure deterministically (`bindings 0→0`, `Broadcast(arity 4): OK; hook fires +0`).

Web research grounded the failure in source code analysis: most-likely root cause is a **vtable-offset mismatch in UE4SS's parser for Omega Strikers' shipped `FMulticastInlineDelegateProperty` binary layout**. PR #1073 (the only commit that introduced these Lua bindings, merged 2025-11-06) has no regression coverage for inline-multicast on a custom `UDataModel` subclass with a non-engine-namespace `__DelegateSignature`. The implementation is correct on its face; the virtual `AddDelegate` call resolves through the vtable to a no-op (or a `ClearDelegate`-class slot) for this game's binary layout. We may be the first hitting this specific failure mode in the wild.

**Pivot — substrate revised to `RegisterHook` on engine-side originating UFunction.** The maintainer-recommended workaround for cross-actor BP↔Lua signaling on UE4SS today (per [UE4SS Issue #455](https://github.com/UE4SS-RE/RE-UE4SS/issues/455)) is to hook the engine UFunction that *calls* `Broadcast` on the multicast delegate, not to subscribe to the delegate. For OSPlus's identity path this means `RegisterHook(Pre|Post)` on `PMPlayerModel:GetMeV1` (or whichever Prometheus-side UFunction Pass-6 identifies as the most reliable identity-flow fire), reading identity state from `self` inside the hook callback. **Substrate is proven at the registration layer on this UE4SS build** — Pass-5 F6 confirmed `Registered script hook (NN, NN) for Function …` via the same `RegisterHook` call we'd use in production.

**Pass 5 byproducts (kept for future work):**

- **Delegate signature mystery resolved.** Pass-3's runtime-data-model survey couldn't find the `MeRequestV1Completed__DelegateSignature` UFunction via `ForEachFunction` on `PMPlayerModel`'s class hierarchy because it lives at *package scope*: `/Script/Prometheus.MeRequestV1Completed__DelegateSignature` (not class-scoped). Confirmed signature: 4 parameters (`Succeeded: BoolProperty, RequestId: StrProperty, MeResponse: StructProperty, ErrorResponse: StructProperty`), flags `0x130000` (`FUNC_Delegate | FUNC_Public | FUNC_MulticastDelegate`). Captured for any future UE4SS C++ mod or future-build work that targets the delegate signature directly.
- **44-UFunction enumeration on `PMPlayerModel` class hierarchy** (Pass 5 F3) — feeds Pass 6's RegisterHook discovery probe directly.
- **Two-pass spike pattern as a methodology lesson** — Pass-4 stopped at "the documented API exists and accepts our call shape" (sufficient for ADR API-surface acceptance, insufficient for "does it actually work on this binary"). Pass-5 caught a substrate that would have failed at Stage-5 build, rescued the ADR with a strictly-cheaper pivot (no BP wrapper at all), and produced a transferable learning. The cost was ~10 probe iterations; the benefit was avoiding both a Stage-5 wall AND the BP-wrapper substrate work. Captured under "Two-pass spike pattern" in ADR 0001's Notes.

**Implications for ADRs and Stage 5 (Pass-5 revision):**

- **ADR 0001 R-B substrate revised** — pivot from "ModActor BP wrapper + delegate subscription" to "RegisterHook on engine-side originating UFunction." ADR remains `accepted` under the revised substrate (per the revision history field at top of ADR). The pivoted substrate is **strictly cheaper** than the Pass-4-era plan: no BP class, no cook step, no Lua-BP bridge. R-A and R-C remain even worse choices than they were post-Pass-4 (they no longer share a substrate with R-B, so they pay their original costs alone).
- **Stage-5 prereq updated to Pass 6** — the open question is no longer "does the BP wrapper substrate work?" (answered no) but "which `PMPlayerModel`-or-adjacent UFunction(s) fire reliably during natural identity flow?" Pass 6 = ~30min Lua probe instrumenting the 44 enumerated UFunctions with `Pre`+`Post` `RegisterHook`s, logging per-fire timing during natural login, picking the earliest reliable identity-event source.

### Pass 6 findings — RegisterHook discovery probe (v1 install-timing bug → v2 module-load install)

*(Session: 2026-04-25, two cold-start runs of `OSPlusProbes`. Probe source: `docs/features/pass2-probes/pass2_probes.lua` `probeE9` (E9.A install / E9.B summary / E9.HOOK per-fire), `NUM_SIX` keybind. Persistent log at `Binaries\Win64\OSPlusProbes.log`.)*

Pass 6 = the RegisterHook discovery probe scoped in the Pass-5 "Recommended Stage 5 path." Goal: instrument every UFunction on `PMPlayerModel` (44) + `PMIdentitySubsystem` (35) with Pre+Post `RegisterHook`s, observe per-fire timing during natural login, pick the earliest UFunction that fires reliably with identity state populated. Two iterations were needed:

**Pass 6 v1 (install-on-keypress) — false-negative substrate verdict.** v1 installed all 79 hooks when the user pressed `NUM_SIX` after reaching the main menu. Result: 79/79 hooks registered cleanly with zero `RegisterHook` failures (positive substrate signal — eliminated the "/Script/Prometheus restriction" risk that was open after Pass-5), but **0 fires across all 79 hooks**, even after a full game restart + relogin. The "0 fires" shape was *exactly* what we'd expect to see if `RegisterHook` were broken at the dispatch layer (matching the Pass-5 silent-no-op finding for `prop:Add`). One careful look at the install-time markers revealed the actual cause: identity-flow UFunctions fire during the *cold-start login window* (engine init → main-menu interactive), which is **before any user keypress is possible**. The keypress-driven install couldn't reach that window by construction. Documented as a probe-design bug in `docs/learnings/ue4ss-cold-start-hook-install-pattern.md` with the lesson "0 fires + clean register = check install timing before pivoting substrate."

**Pass 6 v2 (install-at-module-load via `NotifyOnNewObject` + `FindFirstOf` one-shot) — the substrate works.** v2 refactored install to module-load time using the maintainer-recommended UE4SS Issue #455 pattern: `FindFirstOf` covers the case where Lua loads after the engine instantiates the target class, `NotifyOnNewObject` covers the opposite race; an `INSTALLED_FOR[className]` guard makes the install one-shot per class. `NUM_SIX` becomes a pure summary endpoint (per-UFunction fire counts + ambient state snapshot). Cold-start run captured **4 UFunctions firing during identity flow**:

| UFunction | Class | Fire count | Notes |
|---|---|---|---|
| `GetIdentityState` | `PMIdentitySubsystem` | 1 | Earliest fire; `PMPlayerPublicProfile` cache already populated by fire time. **Chosen as the production hook target.** |
| `GetCachedPlayerPublicProfile` | `PMPlayerModel` | several | Fires after `GetIdentityState`; not chosen because `PMPlayerModel.WasCached` is `false` during identity bootstrap, so its cache-read path is unreliable. |
| `GetCachedPlayerMatchmakingConstraintsV1` | `PMPlayerModel` | several | Same `WasCached=false` issue. |
| `HasFeatureFlag` | `PMPlayerModel` | many | Fires too often to use as a one-shot identity trigger. |

**Critical finding from v2 — `PMPlayerPublicProfile.PlayerId` populates *independently of* `PMPlayerModel.WasCached`.** v1's pre-relog ambient `PlayerId` snapshot already showed this (the `PMPlayerPublicProfile` walk returned a clean Prometheus ID even when `PMPlayerModel.GetCachedMeResponseV1` would have returned `WasCached=false`); v2 confirmed it across the entire identity-flow window. **This breaks the dependency between Pass-3's "GetCachedMeResponseV1 is the primary local-Prometheus-ID path" framing and reality** — the actual production read path is "wait for `GetIdentityState` to fire, walk `FindAllOf("PMPlayerPublicProfile")` for the local profile (disambiguate via `PlayerState.PlayerNamePrivate` if needed), read `PlayerId` from the wrapped struct." `PMPlayerModel` doesn't appear on the read path at all.

**Secondary v2 finding — `MeRequestV1Completed` does not fire on either probed class.** None of the 79 hooked UFunctions correspond to the multicast delegate's originating `Broadcast` call. The originating UFunction lives elsewhere in the engine binary (likely deeper in the Prometheus subsystem code, not exposed as a `BlueprintCallable` on these two classes). For Pass 6's purpose this is fine — `GetIdentityState` is a downstream poller that fires reliably *after* the cache is populated, which is all we need. Flagged for any future feature that needs to catch the originating broadcast itself rather than a downstream cache-read.

**Implications for ADR 0001 + Stage 5 build (post-Pass-6 v2):**

- **ADR 0001 R-B substrate concretized.** The "Pass-6-discovered UFunction" placeholder in the post-Pass-5 ADR is now pinned to `PMIdentitySubsystem:GetIdentityState`. Stage-5 prerequisite is `MET`. Hook installs at `identity.lua` module load via the same `NotifyOnNewObject` + `FindFirstOf` two-phase pattern Pass-6 v2 used.
- **Hook lifecycle: self-unhooking on first resolution.** Per maintainer-confirmed `UnregisterHook` API + the `ConsoleEnablerMod` precedent for unregistering from inside a hook callback, the production hook unregisters itself the first time it produces a non-empty `PlayerId` (deferred via `ExecuteInGameThread` to the next tick to avoid mutating the dispatcher mid-fire). One hook, one fire, then gone. No persistent overhead, no rebind cost.
- **Pass-6 v2 is the canonical reference for cold-start `RegisterHook` install.** The probe code in `pass2_probes.lua` is the copy-pasteable template; the new learning is the prose explanation. Both go into `identity.lua`'s install-site comments.
- **The 109-instance `PMPlayerPublicProfile` cache claim from Pass 3 needs nuance.** Pass-3 reported "111 instances; local player isn't in it" from an in-match observation. Pass 6 v2 confirmed that *at login / main-menu* the cache typically contains **only** the local player's profile (it's populated by the same `MeResponseV1` flow that resolves identity). Mid-session it grows to include remote-player profiles. The disambiguation "is this the local profile?" therefore depends on context: at login the cache is small enough to read the first instance directly; mid-session the disambiguation needs `PlayerState.PlayerNamePrivate` cross-reference. `os-runtime-data-model.md` was updated to record this nuance.

### Recommended Stage 5 path (revised post-Pass-5)

- **Identity binding:** `full feature` path. Substrate is end-to-end-validated end-to-end (Pass-5 F6 for `RegisterHook` registration; Pass-6 v2 for natural-fire timing on the chosen target). Build sequence:
  1. ~~**Pass 6 RegisterHook discovery probe**~~ — **Done (2026-04-25).** v1 install-on-keypress hit the cold-start install-timing bug; v2 install-at-module-load via `NotifyOnNewObject` + `FindFirstOf` caught 4 firing UFunctions. **Chosen target: `PMIdentitySubsystem:GetIdentityState`** (earliest reliable fire, host UObject is singleton-stable, doesn't depend on `PMPlayerModel.WasCached`). Full evidence in the Pass-6 findings section above. Probe code (`probeE9` in `pass2_probes.lua`, `NUM_SIX` keybind) doubles as the install-pattern template for production.
  2. **`mod/OSPlus/scripts/identity.lua` extension** — `RegisterHook(Pre|Post)` on `PMIdentitySubsystem:GetIdentityState` installed at module load via the same two-phase `NotifyOnNewObject` + `FindFirstOf` pattern. On first hook fire, walk `FindAllOf("PMPlayerPublicProfile")` (disambiguating via `PlayerState.PlayerNamePrivate` if multiple instances exist), read `PlayerId` from the wrapped struct. Cache locally; expose via `M.getLocalPrometheusId()` (sync getter) + `M.onPrometheusIdResolved(cb)` (subscribe-on-resolve, fires immediately if already resolved). On first non-empty resolve, defer `UnregisterHook` to the next tick via `ExecuteInGameThread`. One hook, one fire, then gone. **No BP class, no cook step, no ModActor wrapper, no polling.**
  3. **No BP work whatsoever** — the Pass-4 era required `BP_OSPlusDelegateBridge` cooked into the OSPlus pak via the existing pipeline; that step is *removed entirely* from the Pass-5/Pass-6 build sequence.
- **Raw capture pipeline:** `thin slice` (unchanged from Pass-3 recommendation). The capture surface is `FindAllOf("PMPlayerMatchSummary")` during a match. Thin slice = (1) read all summaries at end-of-match, (2) write each as one row to wherever `0002-profile-storage` lands them, (3) prove round-trip end-to-end with one match's worth of redirect counts. The per-summary → per-player mapping question is the only thing that could turn this back into a spike. **Note (Pass-5 revision):** for per-event redirect capture, the `PMRockCharacter:LastRedirectKnockBack` path can reuse the same `RegisterHook`-on-engine-UFunction substrate built for identity — reducing the marginal cost of per-event capture to "one new `RegisterHook` call from Lua, no BP work." Even cheaper than the Pass-4 era's "one new BP UFunction + one new `prop:Add` call."
- **Storage:** still waits for `0002-profile-storage` ADR. Pass-3 findings (canonical `PlayerPublicProfile` shape, bounded `EPMEndOfGameStat` enum) feed concrete schema inputs; Pass-4 + Pass-5 findings don't change the storage axis but do reinforce that profile-row reads are event-driven — the storage layer should not assume "I can always re-read the local profile from the game on demand."

---

## Design
*(Stage 4 — Feature design. Filled 2026-04-25 after ADR 0001 + ADR 0002 acceptance.)*

**MVP scope split (post-ADR-0002).** This MVP ships **profile creation + authentication** only. The raw capture pipeline named in the Brief is moved to a follow-on feature (`docs/features/in-game-match-capture.md`, to be authored when picked up). Rationale: profile+auth is the smallest end-to-end thing that produces a row in the database against the local player's Prometheus ID — landing it cleanly is a natural reviewable unit. Captures has its own discovery sub-questions (capture scope, match-ID strategy, which `PMPlayerMatchSummary` siblings to persist) that don't share a clock with profile+auth and would stretch a single MVP. The capture feature reuses the entire substrate built here (auth middleware, sidecar HTTP client + token storage, mod → sidecar IPC shape) and adds its own database, schema, route(s), and capture trigger. ADR 0002 is unchanged — it remains the architectural commitment for both DBs; the captures DB is just created when the capture feature lands.

**Approach.** Layered build along the dependency chain: server-side persistence module first (foundation), then sidecar HTTP client + token storage (auth pair flow), then mod-side rewrite of `profile.lua` to emit the upsert payload via the existing IPC channel. M-i (drop & recreate) collapses the schema and the read/write paths into a single slice — no migration work between schema and code.

**Axes considered.** Most architectural axes are already pinned by ADR 0002 (S/T/M/R/A). The only build-time axis with multiple defensible answers was **module organization on the server**: flat `server/persistence/` vs grouped `server/api/<feature>/`. Picked **grouped** — `server/api/profile/` for this slice, `server/api/captures/` for the follow-on, `server/api/middleware/auth.js` shared. Reasoning: the relay process will accumulate REST endpoints (more profile sub-routes, captures, future leaderboards/achievements/events). A flat module gets crowded fast; "one folder per feature" is the obvious mental model when six months from now you're reading `server/index.js` and asking "where does X live?"

**Decisions deferred to ADR (both now accepted):**

- **Identity model** — [`docs/decisions/0001-identity-model.md`](../decisions/0001-identity-model.md), **accepted 2026-04-25** under the post-Pass-5/6 RegisterHook substrate (`RegisterHook` on `PMIdentitySubsystem:GetIdentityState`, no BP wrapper, no polling). MVP build conforms via the production `identity.lua` module (`getLocalPrometheusId()` + `onPrometheusIdResolved(cb)`).
- **Profile + capture storage architecture** — [`docs/decisions/0002-profile-storage.md`](../decisions/0002-profile-storage.md), **accepted 2026-04-25**. Picks: server-side persistence in the existing chat-relay process (S-A), HTTP REST on the relay's existing `http.Server` (T-β), two SQLite files (profile + auth in `osplus.sqlite3`, captures in `osplus_captures.sqlite3` — R-Y), drop-and-recreate schema for MVP (M-i), per-install bearer token TOFU-bound to Prometheus ID at first contact (A-2). MVP build conforms; the captures DB and `server/api/captures/` module are deferred to the follow-on capture feature.

---

### Build slices

Three slices on `feat/in-game-profile-mvp`. Each slice is independently committable and has a green smoke test. Final merge to `main` after Slice 2.

#### Slice 0 — Checkpoint commits

Land the in-flight ADR + identity work cleanly before starting build. Logical commits:

1. **Pass 5/6 substrate + ADR 0001 acceptance under revised substrate.** Production `identity.lua`, `main.lua` wire-up, `config.lua` bump if any, Pass 5/6 probe revisions in `pass2-probes/`, three new `ue4ss-*` learnings (cold-start hook install pattern, multicast-delegate `Add` silent no-op, UFunction out-param marshaling on 3.0.1) plus updates to the older two related learnings, `os-runtime-data-model.md` nuance, `learnings/README.md` index, `KNOWLEDGEBASE.md` Pass 6 update, ADR `0001-identity-model.md` acceptance under the RegisterHook pivot, and `.cursor/rules/lua-conventions.mdc` adding the UE4SS-3.0.1 marshaling rules.
2. **ADR 0002 + cascade + ADR template tightening + decision-discipline policy.** ADR `0002-profile-storage.md` (new, accepted), ADR template rewrite, decision-discipline rule "be terse" section, plus cross-doc updates (`product.md`, `AGENTS.md`, `decisions/README.md`).
3. **This feature doc** — narrow MVP scope to profile+auth, add Stage 4 build plan, defer captures to a follow-on feature.

Untracked-but-not-committed-here: `mod/OSPlus/scripts/emotes.lua` and `native_emotes.lua` (out of scope — wait for the unlockable feature). `server/profile/` is deleted (untracked prototype, ADR 0002 replaces it; no commit needed).

#### Slice 1 — Profile creation + authentication, end-to-end

Goal: a fresh OSPlus launch results in a row in `osplus.sqlite3.profiles` correlated to the local player's Prometheus ID, gated by a per-install bearer token TOFU-bound on first contact (per ADR 0002 A-2). Re-launch reuses the stored token; no re-pair, no DB churn beyond `last_seen_at`.

**Server (`server/`):**

- `server/api/middleware/auth.js` (new) — bearer middleware. Extracts `Authorization: Bearer <token>`, scrypt-verifies against `auth_tokens.token_hash` (using stored `scrypt_salt`), attaches `req.prometheusId` on success, responds `401` on missing/invalid token. Touches `auth_tokens.last_seen_at` on successful verify.
- `server/api/profile/schema.js` (new) — table definitions:
  - `profiles(prometheus_id PK, steam_id, display_name, current_platform, logo_id, nameplate_id, emoticon_id, title_id, mastery_level, created_at, updated_at)` — all cosmetic columns nullable (future non-Steam launches may not surface every field, per ADR 0002 Notes).
  - `auth_tokens(prometheus_id PK, token_hash, scrypt_salt, created_at, last_seen_at)`
- `server/api/profile/index.js` (new) — handlers:
  - `POST /api/auth/pair` — body `{prometheusId, token}`. No auth (the request *is* the pairing). On conflict (PID already paired with a different token hash) → `409` + maintainer-recovery hint. On success → `201`. Rate-limited per source IP at relay layer.
  - `PUT /api/profiles/{prometheusId}` — auth-required. Cross-PID = `403`. Body upserts the profile row (full replace of mutable columns; `created_at` preserved).
  - `GET /api/profiles/{prometheusId}` — auth-required. Cross-PID = `403`. `404` if absent.
- `server/api/index.js` (new) — `createApi({ logger })`: builds the per-module pieces, exposes `handleHttp(req, res)` returning `boolean` (matched / didn't match) so `server/index.js` can fall through to `/health` and 404.
- `server/index.js` — mount `api.handleHttp` ahead of `/health`. Drop "no persistence by design" from the header; replace with brief description of the new persistence module.
- `server/package.json` — add `better-sqlite3`.
- *Deletes:* `server/profile/` (untracked prototype; ADR 0002 replaces the schema entirely).

**Sidecar (`sidecar/`):**

- `sidecar/profile.js` (new) — token storage at `%LOCALAPPDATA%\OSPlus\token` (32 random bytes, base64url, restrictive Windows ACL). HTTP client (Node built-in `http`/`https`). On startup: ensure token exists. On receiving `profile_upsert` IPC: if the server doesn't recognize the token (first ever request OR after maintainer-recovery), `POST /api/auth/pair`; then `PUT /api/profiles/{pid}` with the full payload. Errors logged to the sidecar log; transient failures retried on the next IPC tick.
- `sidecar/index.js` — wire `profile.js` into the IPC dispatch loop and the startup flow. New IPC type: `profile_upsert`.
- `sidecar/package.json` — no new runtime deps (uses Node built-ins only; preserves the SEA bundle story).

**Mod (`mod/OSPlus/scripts/`):**

- `identity.lua` — confirm the resolver surfaces the cosmetic loadout fields from `PMPlayerPublicProfile` (`logo_id`, `nameplate_id`, `emoticon_id`, `title_id`, `mastery_level`, `current_platform`); widen if needed. `getLocalPrometheusId()` and `onPrometheusIdResolved(cb)` remain the single source of truth.
- `profile.lua` — rewrite. Subscribe via `identity.onPrometheusIdResolved(cb)`. Once Prometheus ID + display name + cosmetic loadout are all known, emit one `profile_upsert` IPC message per session (idempotent server-side via PUT semantics).
- `ipc.lua` — add `writeProfileUpsertToOutbox(payload)` following the `writeChatToOutbox` shape.
- `main.lua` — drop the `profile.poll()` call; identity.lua's hook handles event delivery now.

**Wire shapes (Lua → sidecar IPC → server REST):**

- IPC: `{type: "profile_upsert", prometheusId, steamId, displayName, currentPlatform, logoId, nameplateId, emoticonId, titleId, masteryLevel, ts}`
- REST PUT body: `{prometheusId, steamId, displayName, currentPlatform, logoId, nameplateId, emoticonId, titleId, masteryLevel}` — same shape minus the IPC envelope fields.
- REST PUT response: `{prometheusId, ..., createdAt, updatedAt}` — server-canonical row.

**Exit criteria (smoke battery, run in this order against local relay first, VM relay second):**

1. **Fresh local launch.** Sidecar log shows `POST /api/auth/pair → 201`, then `PUT /api/profiles/{pid} → 200`. No errors. Token file exists at `%LOCALAPPDATA%\OSPlus\token` with restrictive ACL.
2. **Re-launch on the same machine.** Sidecar log shows `PUT /api/profiles/{pid} → 200` only. No pair attempt. `last_seen_at` advances on the relay.
3. **DB inspection.** `sqlite3 data/osplus.sqlite3 "select prometheus_id, display_name, current_platform, logo_id from profiles"` — row present, cosmetic columns populated.
4. **Auth-row inspection.** `sqlite3 data/osplus.sqlite3 "select prometheus_id, last_seen_at from auth_tokens"` — row present, `last_seen_at` matches the most recent request.
5. **Auth negative tests** (hand-rolled `curl`):
   - Valid token, mismatched PID in URL → `403`.
   - Garbage `Authorization: Bearer ...` → `401`.
   - No `Authorization` header → `401`.
6. **Token rotation drill (manual recovery — proves the ADR 0002 maintainer-only recovery flow).** `sqlite3 osplus.sqlite3 "DELETE FROM auth_tokens WHERE prometheus_id='<pid>'"` → next launch from a fresh client (or one whose token file we deleted) succeeds at pair, and the next request from the original (no-longer-paired) token returns `401`.

#### Slice 2 — Operational hardening + ship

Goal: deploy Slice 1 to the OCI VM cleanly and lock down the runbook for the maintainer-only recovery flows ADR 0002 explicitly defers.

- `server/deploy/install-relay.sh` — verify `npm install` builds `better-sqlite3` cleanly on the VM. May need a one-time `apt-get install -y build-essential python3` if not present; if so, document at the top of the script and in the persistence ops doc below.
- `docs/ops/persistence.md` (new) — short runbook:
  - DB file paths and ownership (`/opt/osplus/relay/data/osplus.sqlite3`, owner `osplus`).
  - Backup command (`sqlite3 .backup` form).
  - Manual `auth_tokens` recovery one-liner (the ADR 0002 token-loss recovery procedure).
  - Where to look in the relay journal log for pair / put / 401 / 403.
- Bump mod `config.lua` `VERSION` to mark the profile-substrate landing.
- `ship.ps1` deploys the new bundle + server.
- End-to-end smoke from a clean VM state (delete `osplus.sqlite3`, redeploy, launch fresh client, run the Slice-1 smoke battery against the public TLS endpoint).

**Exit criteria:** Slice 1 smoke battery green against the VM (not just localhost). `docs/ops/persistence.md` exists and contains commands the maintainer can copy-paste.

---

**Files that will change (Slice 1 + Slice 2):**

- *New:* `server/api/index.js`, `server/api/middleware/auth.js`, `server/api/profile/index.js`, `server/api/profile/schema.js`, `sidecar/profile.js`, `docs/ops/persistence.md`.
- *Modified:* `server/index.js`, `server/package.json`, `server/deploy/install-relay.sh` (only if VM toolchain needs build-essential), `sidecar/index.js`, `mod/OSPlus/scripts/profile.lua` (full rewrite), `mod/OSPlus/scripts/ipc.lua`, `mod/OSPlus/scripts/main.lua`, `mod/OSPlus/scripts/config.lua` (VERSION bump), and `mod/OSPlus/scripts/identity.lua` only if the cosmetic-loadout fields aren't already surfaced.
- *Deleted:* `server/profile/` (untracked prototype).

**Files that will NOT change but matter:**

- `server/deploy/Caddyfile` — proxies everything to `127.0.0.1:3000`; new `/api/*` routes work for free under the existing TLS endpoint.
- `mod/OSPlus/scripts/chat.lua` and the WS upgrade path on the relay — chat/ping flow is independent; the persistence module mounts ahead of `/health` and falls through to the unchanged WS upgrade.
- `sidecar/launch_hidden.vbs` and the SEA build pipeline — sidecar gains an HTTP client using only Node built-ins; no new native deps, the bundle build is unchanged.

---

## Outcome
*(Stage 6 — Land.)*

**Result:** *(pending)*

---

## Notes

**Prior exploration on disk (Stage 3 input, not yet wired):**

- `mod/OSPlus/scripts/identity.lua` — resolves `SteamId` via `PMIdentitySubsystem:GetSteamId()`; resolves friendly display name via `PMPlayerPublicProfile` with fallback handling for account-ID-shaped and machine-name-shaped values. Referenced learnings: `docs/learnings/playernameprivate-transient-account-id.md`, `docs/learnings/playernameprivate-machine-name-out-of-match.md`.
- `mod/OSPlus/scripts/profile.lua` — minimal poll + push; emits a `profile_identity` IPC event when both identity fields are ready.
- `server/profile/index.js` — `better-sqlite3`-backed profile module with `upsertIdentity`, `getProfile`, and `GET /profiles/:steamId`. **Reference prototype only — entirely subject to change.** ADR 0002 (accepted) replaces the schema (`prometheus_id` PK, not `steam_id`) and adds auth + captures; the new `server/persistence/` module per ADR 0002 is the implementation that ships.
- `server/data/` — empty directory, SQLite target.
- `mod/OSPlus/scripts/emotes.lua` / `native_emotes.lua` — **out of scope** for this MVP (no unlockables). Remain on disk for the later "First unlockable-earning path" feature.

**Open questions deferred to Stage 4 or later passes of Stage 3:**

- ~~*[Pass 3]* UFunction signatures for `PMPlayerModel.GetCachedMeResponseV1` / `GetDisplayNameV1` / `GetCachedPlayerPublicProfile`~~ — **Resolved in Pass 3 findings.** Documented in `docs/learnings/os-runtime-data-model.md` and `KNOWLEDGEBASE.md`.
- ~~*[Pass 3]* Where does the redirect signal actually live?~~ — **Resolved in Pass 3 findings.** `PMPlayerMatchSummary:RedirectRock`, plus per-event `PMRockCharacter:LastRedirectKnockBack`.
- ~~*[Pass 3]* What is the 111 `PMPlayerPublicProfile` instances pool?~~ — **Resolved.** It's the *remote*-player profile cache (UObject wrapper around `PlayerPublicProfile` struct + `IsOnline` flag); the local player isn't in it. Local player goes through `PMPlayerModel:GetCachedMeResponseV1` instead.
- ~~*[Pass 4]* Validate UE4SS calling-convention for output-param placeholders on `GetCachedMeResponseV1`~~ — **Resolved (negatively) in Pass 4 spike.** No documented placeholder shape works for `(Bool out, X out)` UFunctions on `PMPlayerModel` in this UE4SS build (v3.0.1). Workarounds documented in `docs/learnings/ue4ss-outparam-marshaling-failure.md`; current Stage 5 path drops the warm-cache pre-check rather than building a workaround.
- ~~*[Pass 4]* **Delegate-binding spike (1–2 hours).**~~ — **Resolved (API surface) in Pass 4 spike.** UE4SS's `MulticastDelegateProperty:Add` takes `(UObject, FName)`, requires a ModActor BP wrapper as the binding target. Full pattern + false-friend trap in `docs/learnings/ue4ss-lua-multicast-delegate-binding.md`. R-B's API surface exists; ADR 0001 was `accepted` post-Pass-4 with the BP-wrapper substrate.
- ~~*[Pass 5]* **End-to-end validation of the BP-wrapper substrate before committing Stage-5 build to it.**~~ — **Resolved (negatively) in Pass 5 spike.** `prop:Add` is a silent no-op on this UE4SS build for `MulticastInlineDelegateProperty` (likely vtable-offset mismatch). Pivoted ADR 0001 R-B substrate to `RegisterHook` on engine-side originating UFunction (maintainer-recommended workaround per UE4SS Issue #455). Substrate proven at registration layer (Pass-5 F6); operational target identified via Pass-6 discovery probe in Stage 5 build. Full evidence chain in `docs/learnings/ue4ss-multicast-delegate-add-silent-noop.md`.
- ~~*[Pass 6 / Stage 5 build — opens this Stage 5]* RegisterHook discovery probe on the 44 `PMPlayerModel`-class-hierarchy UFunctions enumerated by Pass-5 F3.~~ **Resolved in Pass 6 v2 (2026-04-25).** Scope expanded to include `PMIdentitySubsystem` (35 more UFunctions, 79 total). v1 install-on-keypress missed cold-start window (false-negative "0 fires"); v2 install-at-module-load via `NotifyOnNewObject` + `FindFirstOf` caught 4 firing UFunctions. Chosen target: `PMIdentitySubsystem:GetIdentityState`. Full findings in the Pass-6 section above; install-timing lesson in `docs/learnings/ue4ss-cold-start-hook-install-pattern.md`.
- *[Stage 4 design / future feature — deferred from Pass 4, deprioritized post-Pass-5]* Property-dump probe on `PMPlayerModel` to look for direct UProperty cache fields (e.g., `CachedMeResponse : MeResponseV1`). If such fields exist, they're a zero-build-cost workaround for the synchronous warm-cache read. Pass-5's `RegisterHook` pivot makes this less urgent (the hook fires when the engine populates the cache, so `self`-side property read inside the hook is the same outcome as a direct property read at an arbitrary tick); still worth one probe pass when the next feature wants synchronous local-cache reads from outside a hook context.
- *[Pass 4]* How does a `PMPlayerMatchSummary` instance map back to its player? (Held by `PMPlayerState`? An array on `PMGameState`? Keyed by `PlayerId`?) Required before designing the storage schema's player-FK shape.
- *[Pass 4]* Where do the missing 5 EOG stats (Goals / Assists / Saves / KOs) live? Most likely on `PMPlayerState` C++ parent; needs a property dump of that class.
- *[Pass 3 / deferred]* Does A2's local-stable finding hold in a matchmade public game, or is it solo-custom-only?
- *[B3 — pending]* Rough per-match redirect count — feeds `0002-profile-storage` write-frequency axis.
- ~~*[Stage 4]* Where does raw capture data physically live?~~ **Answered by [ADR 0002](../decisions/0002-profile-storage.md) (accepted 2026-04-25):** server-side, in `osplus_captures.sqlite3` on the OCI VM, owned by the chat-relay process, written via `POST /captures` with bearer-token auth.
- *[Stage 4]* What debug visibility, if any, ships with the MVP so "capture is working" is provable without grepping the relay DB?
- *[Stage 4]* Does `identity.lua` get extended to surface the Prometheus ID, or is that a separate feature? (Now *when* not *whether* — the binding-key decision forces the extension.)
- ~~*[Stage 4]* Which identifier is the profile row's primary binding key — SteamID or Prometheus ID?~~ **Decided in Pass 2 findings:** Prometheus ID is primary, SteamID is secondary cross-reference. Formalized in `docs/decisions/0001-identity-model.md`.

**Explicit Brief ↔ Roadmap tension recorded here so it isn't lost:**

The roadmap's acceptance hint for "In-game profile scaffolding" ("player opens profile panel and sees two game-derived stats") expected a *visible* MVP. This feature's MVP is **plumbing-only**: no consolidation, no stats display, no panel. The visible MVP described by the roadmap is now a follow-on feature (probably bundled with "First unlockable-earning path" or a dedicated "profile display MVP"). This split came out of the Stage-2 Frame conversation and is an improvement — it separates the substrate decision from the display decision, so both can be small enough to ship.

**Follow-on features (named explicitly so the substrate built here has clear next users):**

- **In-match raw capture pipeline** — own feature doc to be authored when picked up. Reuses Slice 1's auth middleware, sidecar HTTP client + token storage pattern, and mod IPC shape. Adds: `osplus_captures.sqlite3` (per ADR 0002 R-Y), `server/api/captures/` module (`POST /api/captures` + `GET /api/captures?since=`), `mod/OSPlus/scripts/captures.lua`, and `sidecar/captures.js` with a `pending_captures.jsonl` retry buffer. Open design questions for that feature: (a) capture scope — self-only vs all-players-in-lobby vs anonymized non-self; (b) whether a stable game-side `match_uuid` is reachable (Stage-3 sub-discovery against `PMPlayerMatchSummary` siblings + `PMGameState` properties) or whether one must be synthesized client-side from PID + start-ts + map; (c) which match-end fields beyond redirects are worth persisting (Pass-3 found 4 of 9 `EPMEndOfGameStat` entries on `PMPlayerMatchSummary`; the other 5 — Goals/Assists/Saves/KOs — most likely live on `PMPlayerState` C++ parent and need a property dump).
- **First unlockable-earning path** — `mod/OSPlus/scripts/emotes.lua` / `native_emotes.lua` (currently on disk, untracked) live for this feature. The profile substrate built here is what they hang ownership flags on — the schema gains an `unlockables_owned` join table at that point, not now.
- **Profile display MVP** — the visible-MVP component the roadmap originally bundled with profile scaffolding, now its own follow-on. Reads `GET /api/profiles/{pid}` (Slice 1) plus whatever consolidation queries the capture follow-on exposes. Likely the first feature that gives this substrate user-visible value.
