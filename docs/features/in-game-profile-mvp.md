# In-game profile MVP

| Field | Value |
|---|---|
| Slug | `in-game-profile-mvp` |
| Status | `feasibility` (Passes 1, 2, 3 complete; Stage 4 unblocked pending ADR sign-off) |
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
| 3 | `PMPlayerModel` getter UFunctions resolvable to a clean local-Prometheus-ID path | Med-High (callable, signatures unread) | Signatures fully read from dumper; cross-checked in-game via C2 (`ForEachProperty`). `MeResponseV1` ScriptStruct inherits from `PlayerPublicProfile` (`sps` chain). One sync call yields the local profile struct including `PlayerId`. | **High.** Calling-convention placeholder shape is the only Pass-4 residual. |
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

### Recommended Stage 5 path (revised post-Pass-3)

- **Identity binding:** `full feature` path. Resolution path is now characterized end-to-end (`PMPlayerModel:GetCachedMeResponseV1` → `MeResponseV1` (extends `PlayerPublicProfile`) → `PlayerId`). One Pass-4 in-game probe validates the UE4SS calling-convention placeholder shape, then `identity.lua` extends to surface the Prometheus ID alongside the existing SteamID + display-name reads. Trust posture and primary-key choice land in `0001-identity-model`.
- **Raw capture pipeline:** `thin slice` (upgraded from "spike first"). The capture surface is now known: `FindAllOf("PMPlayerMatchSummary")` during a match yields the per-player counters. Thin slice = (1) read all summaries at end-of-match, (2) write each as one row to wherever `0002-profile-storage` lands them, (3) prove round-trip end-to-end with one match's worth of redirect counts. The per-summary → per-player mapping question (Pass-4) is the only thing that could turn this back into a spike.
- **Storage:** still waits for `0002-profile-storage` ADR. Pass-3 findings now feed concrete inputs: schema rows can be designed against `PlayerPublicProfile` for profile data and against the `EPMEndOfGameStat` enum (capped at 9 ints per player per match) for capture data. Cardinality bounded; cheapest write strategy is now answerable.

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

- ~~*[Pass 3]* UFunction signatures for `PMPlayerModel.GetCachedMeResponseV1` / `GetDisplayNameV1` / `GetCachedPlayerPublicProfile`~~ — **Resolved in Pass 3 findings.** Documented in `docs/learnings/os-runtime-data-model.md` and `KNOWLEDGEBASE.md`.
- ~~*[Pass 3]* Where does the redirect signal actually live?~~ — **Resolved in Pass 3 findings.** `PMPlayerMatchSummary:RedirectRock`, plus per-event `PMRockCharacter:LastRedirectKnockBack`.
- ~~*[Pass 3]* What is the 111 `PMPlayerPublicProfile` instances pool?~~ — **Resolved.** It's the *remote*-player profile cache (UObject wrapper around `PlayerPublicProfile` struct + `IsOnline` flag); the local player isn't in it. Local player goes through `PMPlayerModel:GetCachedMeResponseV1` instead.
- *[Pass 4]* Validate UE4SS calling-convention for output-param placeholders on `GetCachedMeResponseV1` — `(false, nil)` vs `(false, {})` vs no args; build-dependent. Single in-game probe call.
- *[Pass 4]* How does a `PMPlayerMatchSummary` instance map back to its player? (Held by `PMPlayerState`? An array on `PMGameState`? Keyed by `PlayerId`?) Required before designing the storage schema's player-FK shape.
- *[Pass 4]* Where do the missing 5 EOG stats (Goals / Assists / Saves / KOs) live? Most likely on `PMPlayerState` C++ parent; needs a property dump of that class.
- *[Pass 3 / deferred]* Does A2's local-stable finding hold in a matchmade public game, or is it solo-custom-only?
- *[B3 — pending]* Rough per-match redirect count — feeds `0002-profile-storage` write-frequency axis.
- *[Stage 4]* Where does raw capture data physically live? Answered by `0002-profile-storage`.
- *[Stage 4]* What debug visibility, if any, ships with the MVP so "capture is working" is provable without grepping the relay DB?
- *[Stage 4]* Does `identity.lua` get extended to surface the Prometheus ID, or is that a separate feature? (Now *when* not *whether* — the binding-key decision forces the extension.)
- ~~*[Stage 4]* Which identifier is the profile row's primary binding key — SteamID or Prometheus ID?~~ **Decided in Pass 2 findings:** Prometheus ID is primary, SteamID is secondary cross-reference.

**Explicit Brief ↔ Roadmap tension recorded here so it isn't lost:**

The roadmap's acceptance hint for "In-game profile scaffolding" ("player opens profile panel and sees two game-derived stats") expected a *visible* MVP. This feature's MVP is **plumbing-only**: no consolidation, no stats display, no panel. The visible MVP described by the roadmap is now a follow-on feature (probably bundled with "First unlockable-earning path" or a dedicated "profile display MVP"). This split came out of the Stage-2 Frame conversation and is an improvement — it separates the substrate decision from the display decision, so both can be small enough to ship.
