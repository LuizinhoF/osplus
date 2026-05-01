# Identity and the Prometheus backend API

The *"who is the player, what IDs do we have, and what does
Odyssey's backend expose"* doc — read this before any feature
involving player identity, profile binding, cross-tracker
linking, or backend API access. Distilled from
[`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) §"Backend
Ecosystem — Odyssey's 'Prometheus' API" + §"Player Identity
Reference".

> **Status:** seeded 2026-05-01 from
> [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md). The *three-
> namespace identity model* (SteamID / Prometheus ID / display
> name) and the *Prometheus-API-vs-module disambiguation* are
> both well-validated and load-bearing for ADR 0001 (the
> identity decision). The *Lua-side reachability* sub-section
> tracks the v33→v36 production-shipping work — the most
> patch-volatile part of this doc.
>
> **Stability:** the three-namespace model is stable across
> patches. The reverse-engineered backend API endpoints are
> community-maintained and have been stable for the past year+.
> The Lua-side reachability rules pin to UE4SS 3.0.1 and may
> shift on UE4SS upgrade.

This doc is the *engine + backend identity layer*. The decision
of which identifier to use as OSPlus's primary key lives in
[ADR 0001](../decisions/0001-identity-model.md). The
*per-player engine surface* (PlayerState_Game_C) is in
[`player-state.md`](./player-state.md).

## TL;DR

- **Three identifier namespaces, distinct:** SteamID (17-digit
  decimal, cross-platform stable), Prometheus ID (24-char hex,
  the canonical backend key), display name (mutable, human-
  facing). **None can be derived from another without the
  backend.** See [§"The three identifier namespaces"](#the-three-identifier-namespaces).
- **Two "Prometheus"es — distinguish them.** The UE module name
  vs Odyssey's backend HTTP API. See
  [`overview.md` → "The two 'Prometheus'es"](./overview.md#the-two-prometheuses)
  for the canonical disambiguation; this doc covers the
  *backend* meaning.
- **The backend API is reverse-engineered, not officially
  documented.** Every Omega Strikers tracker
  (stats.omegastrikers.gg, clarioncorp.net, strikr.gg) taps the
  same API; community posture is "grey zone, not endorsed, not
  prosecuted." See [§"The backend API"](#the-backend-api).
- **OSPlus uses the Prometheus ID as primary key** per
  [ADR 0001](../decisions/0001-identity-model.md).
  Production-shipping resolver lives in
  [`mod/OSPlus/scripts/identity.lua`](../../mod/OSPlus/scripts/identity.lua).
- **Local-player identity reads — proven path:** `RegisterHook`
  on `/Script/Prometheus.PMIdentitySubsystem:GetIdentityState`,
  call `GetAuthenticatedPlayerId({}, {})` from the callback.
  See [§"Lua-side reachability"](#lua-side-reachability).
- **`PlayerState.PlayerNamePrivate` has 3 observed modes** —
  display name (after replication), hex Prometheus ID
  (during replication window), local Windows machine name
  (some out-of-match contexts). Cross-link to learnings.

## The three identifier namespaces

| Identifier | Shape | Stable? | Source | Who uses it |
|---|---|---|---|---|
| **SteamID** | 17-digit decimal (e.g., `76561198022185004`) | Yes — cross-session, cross-platform | `PMIdentitySubsystem:GetSteamId()` | Steam itself; OSPlus profile binding (early version, pre-ADR-0001) |
| **Prometheus ID** | 24-char hex / MongoDB ObjectID (e.g., `6333a58673a37dc7cb11a7a7`) | Yes (assumed) | Game backend; appears as `PMPlayerPublicProfile.PlayerId` | Odyssey's backend API; every OS tracker as the canonical player key; OSPlus's primary key per [ADR 0001](../decisions/0001-identity-model.md) |
| **Display name** | Friendly, mutable string (e.g., `"Ispicas"`) | No — user-mutable | `PlayerState.PlayerNamePrivate` (after replication) | Human UI |

**Three separate namespaces.** A Prometheus ID cannot be
derived from a SteamID (or vice versa) without going through
the backend. **If OSPlus ever wants to join its own captures
against tracker-ecosystem aggregate stats, it needs the
Prometheus ID** — every tracker keys off Prometheus, not Steam.
This is the load-bearing fact behind [ADR 0001](../decisions/0001-identity-model.md).

### `PlayerNamePrivate` has three modes

The single most painful identity gotcha in this codebase.
`PlayerState.PlayerNamePrivate` (an `FText`) returns different
things at different times:

1. **Display name** — the normal case in custom / real games,
   after replication has settled.
2. **Hex Prometheus ID** — during the replication window
   (briefly, at match start). The "account-ID" mode documented
   in [`docs/learnings/playernameprivate-transient-account-id.md`](../learnings/playernameprivate-transient-account-id.md).
3. **Local Windows machine name** — observed in some out-of-
   match contexts. Documented in
   [`docs/learnings/playernameprivate-machine-name-out-of-match.md`](../learnings/playernameprivate-machine-name-out-of-match.md).

**Practice mode caveat:** in practice mode, `PlayerNamePrivate`
returns a hex Prometheus ID rather than the display name.
Display name only resolves in custom / real games.

**The fix:** don't use `PlayerNamePrivate` as the canonical
display-name source. Use the local-identity path
([§"Lua-side reachability"](#lua-side-reachability)) which
returns the `Username` field of the PlayerPublicProfile struct
directly. See production code at
[`mod/OSPlus/scripts/identity.lua`](../../mod/OSPlus/scripts/identity.lua).

## The backend API

### Disambiguation note

"Prometheus" refers to **two things** in Omega Strikers, both
Odyssey-chosen:

1. **The UE client module** (covered in
   [`overview.md` → "The two gameplay modules"](./overview.md#the-two-gameplay-modules)).
   `PM*` UClasses, `/Game/Prometheus/...` content, etc.
2. **The backend HTTP API** — *this section*.

The community kept the name because the schema/ID conventions
from the UE module leak into the backend's response shapes
(e.g., `PMPlayerPublicProfile.PlayerId` on the client is the
same hex string the backend uses as its canonical player key).

### What the backend is

A **JWT-authenticated HTTP API** that the OS client talks to
for player metadata, matchmaking, persistence, ranked stats,
mastery progression, etc.

**Not publicly documented by Odyssey.** Every OS tracker in
existence reverse-engineered access to this API:

- [stats.omegastrikers.gg](https://stats.omegastrikers.gg/)
- [clarioncorp.net](https://clarioncorp.net/) — runs `/clarion-api/v2/players` which proxies Prometheus
- [strikr.gg](https://strikr.gg/) — author signed an NDA with Odyssey after RE work
- [omegastrikers.stlr.cx](https://omegastrikers.stlr.cx/)

**Community posture:** grey zone. Not endorsed by Odyssey, not
prosecuted. OSPlus operates in the same posture.

### Auth

JWT pair: `ODYSSEY_TOKEN` + `ODYSSEY_REFRESH_TOKEN` (per the
Strikr-GG README). Tokens obtainable via:

- **Live capture with Fiddler Classic** while the game runs.
  Quickest for development.
- **Steam Ticket → Odyssey auth handshake** (per Clarion docs;
  full guide not yet published as of 2026-04). The proper
  programmatic path; not yet implemented for OSPlus.

### What the backend exposes

Per [Clarion's v2 `/players/<id>`](https://docs.clarioncorp.net/clarion-api/v2/players)
(which proxies Prometheus and is the most-readable reference):

- **Player metadata:** 24-char hex Prometheus ID, username,
  region, cosmetic loadout IDs (logo, nameplate, emoticon,
  title), `currentXp`, online/offline status.
- **Per-character aggregates** (by `character` × `role` ×
  `gamemode`): `games`, `wins`, `losses`, `mvp`, `knockouts`,
  `assists`, `saves`, `scores`.
- **Rating per season:** `rating`, `rank`, `wins`, `losses`,
  `games`, `masteryLevel`.
- **Mastery totals:** `currentLevel`, `currentLevelXp`,
  `totalXp`, `xpToNextLevel`.
- **Per-match metadata** (map, score, duration, timestamp,
  per-team rank delta) — drillable via a per-match endpoint.

### What the backend does NOT expose — the OSPlus capture gap

This is the **product wedge** for OSPlus's eventual capture
features:

- **Redirects** — no `redirects` field in any tracker's per-
  character or per-match response shape. The Core-redirect
  count, the canonical OSPlus capture target, simply isn't
  surfaced by Odyssey's backend at all.
- **Per-match event sequences** — when goals were scored,
  saves per match, action-by-action breakdowns. Backend
  surfaces only aggregates.
- **In-match transient state** — positions, action timing,
  duration-of-possession. Pure aggregate; no event log.
- **Anything that happens during a match but isn't persisted
  to the backend.** The capture gap is large and structural.

**See also:** [`docs/learnings/os-prometheus-api-ecosystem.md`](../learnings/os-prometheus-api-ecosystem.md)
(discovery diary).

## The local-identity surface

The client exposes the local player's identity through a
parallel set of UObjects to the cached-others path. Two key
subsystems.

### `PMIdentitySubsystem`

Singleton-ish; one instance per game session.

| Method | Purpose |
|---|---|
| `GetSteamId()` | Returns the local SteamID. Reliable since module load. |
| `GetIdentityState()` | Returns the auth state enum. Observed value `2` interpreted as `Authenticated` (semantics inferred from name, not enum-dump-confirmed). |
| `GetAuthenticatedPlayerId(Valid: Bool out, OutPlayerId: Str out)` | **The canonical local Prometheus ID read.** Production-shipping. See [§"Lua-side reachability"](#lua-side-reachability). |

### `PMPlayerModel`

Hosts the local-identity getters. Signatures (from the GUI
Object Dumper, in-match):

| Method | Notes |
|---|---|
| `GetCachedMeResponseV1(out WasCached: Bool, out OutMeResponse: MeResponseV1)` | Sync read of the local cache. |
| `GetCachedPlayerPublicProfile(out WasCached: Bool, out Profile: PlayerPublicProfile)` | Sync read of an already-cached profile. |
| `GetDisplayNameV1(out WasSent: Bool, out OutRequestId: Str)` | **Async**: returns a request ID; the actual response fires the `GetDisplayNameV1Completed` multicast delegate. |
| `GetMeRequestV1Completed` | A `MulticastInlineDelegateProperty` (offset `0x248`), typed `MeRequestV1Completed__DelegateSignature`. Callback shape: `(Succeeded: Bool, RequestId: Str, MeResponse: MeResponseV1, ErrorResponse: ErrorResponse)`. |

### The `MeResponseV1` struct

`MeResponseV1` extends `PlayerPublicProfile` (UE `ScriptStruct`
inheritance via the dumper's `sps` field), so `OutMeResponse`
carries every PlayerPublicProfile field plus Me-only additions:

**PlayerPublicProfile fields** (all carried by `MeResponseV1`):
- `PlayerId` — the Prometheus ID.
- `Username` — display name.
- `LogoId`, `NameplateId`, `EmoticonId`, `TitleId` — cosmetic loadout.
- `PlatformIds` — struct.
- `MasteryLevel`.
- `CurrentPlatform` — enum.

**Me-only additions:**
- `MatchmakingRegion`.
- `EulaNeeded`.
- `DiscordConnection`.
- (more — full enumeration via dumper)

**One delegate fire → full local identity.** This is *why* the
multicast-delegate path was the original target before the
silent-no-op bug forced the `RegisterHook` workaround.

### The cached-others path

`FindAllOf("PMPlayerPublicProfile")` returns ~100+ cached
profiles of OTHER players (observed: 104 and 109 in two
separate dumps). Each has `Username` (display name) and
`PlayerId` (Prometheus ID).

**The local player is NOT in this cache.** Don't try to use
`FindAllOf("PMPlayerPublicProfile")` to read your own identity
— it won't be there.

## Lua-side reachability

**Updated 2026-04-25, post-v36-identity-stable.**

Two distinct UE4SS-3.0.1-specific behaviors govern what's
reachable. Both are catalogued in
[`ue4ss-version-and-gotchas.md` → "UE4SS 3.0.1 known bugs"](./ue4ss-version-and-gotchas.md#ue4ss-301-known-bugs);
this section summarizes the identity-relevant subset.

### Sync UFunction calls — call shape `({}, {})`

The pre-v33 conclusion that `(Bool out, X out)` UFunctions are
*"not callable from Lua at all"* is **refuted at the call-shape
layer.** The canonical UE4SS 3.0.1 multi-out-param call shape
is `inst:Fn({}, {})` — pass one empty Lua table per declared
out-param. UE4SS writes results into `bucket.<ParamName>` for
base-type params and (per [Issue #971](https://github.com/UE4SS-RE/RE-UE4SS/issues/971))
collapses multiple base-type out-params into the **first**
bucket on 3.0.1. You still must pass a bucket per declared
param to satisfy the marshaler's argument count.

**End-to-end-validated:** `PMIdentitySubsystem:GetAuthenticatedPlayerId(Valid: Bool out, OutPlayerId: Str out)`
in [`mod/OSPlus/scripts/identity.lua`](../../mod/OSPlus/scripts/identity.lua)
→ `readAuthenticatedPlayerId` (v36; production-shipping). See
[`docs/learnings/ue4ss-ufunction-out-param-marshaling-3-0-1.md`](../learnings/ue4ss-ufunction-out-param-marshaling-3-0-1.md)
for the canonical convention + copy-pasteable example.

**Caveat — three `PMPlayerModel:GetCached*V1` UFunctions are
still untested with the new shape.** Specifically:
`GetCachedMeResponseV1`, `GetCachedLinkCodeV1`,
`GetCachedPlayerPublicProfile`. These were NOT re-tested with
`({}, {})` during the v33→v36 work. They may now be reachable,
or they may still fail for an orthogonal `PMPlayerModel`-
specific reason. **Treat as "untested with new shape; probe
before relying."** Same caveat for `GetCachedLoginResponse`,
`GetMeV1`, and any other sibling that appeared in the older
[`ue4ss-outparam-marshaling-failure.md`](../learnings/ue4ss-outparam-marshaling-failure.md)
catalog.

### Async delegate binding — silent no-op

`MulticastDelegateProperty:Add(uobject, fname)` is a **silent
no-op** on this UE4SS build for inline-multicast props on non-
engine-namespace UObjects. `Add` returns `true`,
`GetBindings()` stays empty across all 6 callable methods +
every bind-shape variation tried, `Broadcast()` fires nothing.
Likely vtable-offset mismatch in UE4SS's binary parser.

This was unaffected by the v33→v36 work (which was about
*calling* UFunctions, not *subscribing* to delegates). Pass-5
documented in
[`docs/learnings/ue4ss-multicast-delegate-add-silent-noop.md`](../learnings/ue4ss-multicast-delegate-add-silent-noop.md).

**The intended path** (waiting on `GetMeRequestV1Completed`
multicast) is therefore unreachable from Lua on this UE4SS
build.

### The working substrate

Pass-5 pivot, Pass-6 v2 validated, v36 production-shipping:

> **`RegisterHook` on the engine-side originating UFunction.**

For identity, that UFunction is
`/Script/Prometheus.PMIdentitySubsystem:GetIdentityState` —
direct module-load `RegisterHook` (no `NotifyOnNewObject`
defer needed, since UFunctions live in the class table from
package load — see
[`ue4ss-version-and-gotchas.md` → "Cold-start hook install patterns"](./ue4ss-version-and-gotchas.md#3-cold-start-hook-install-patterns)).

Inside the callback, call `instance:GetAuthenticatedPlayerId({}, {})`
to read the local Prometheus ID. **No BP wrapper, no delegate
binding, no `WasCached`-flag dependency, pure Lua.**
Maintainer-recommended pattern per
[UE4SS Issue #455](https://github.com/UE4SS-RE/RE-UE4SS/issues/455).

**Production reference:** [`mod/OSPlus/scripts/identity.lua`](../../mod/OSPlus/scripts/identity.lua).

### Quick read recipes

```lua
-- Local SteamID (always available once PMIdentitySubsystem exists)
local idSub = FindFirstOf("PMIdentitySubsystem")
local steamId = idSub:GetSteamId()
-- → "76561198022185004"

-- Local Prometheus ID (production pattern: hook GetIdentityState)
RegisterHook(
    "/Script/Prometheus.PMIdentitySubsystem:GetIdentityState",
    function(Context)
        local instance = Context:get()
        local valid = {}
        local outId = {}
        instance:GetAuthenticatedPlayerId(valid, outId)
        if valid.Valid and outId.OutPlayerId then
            local prometheusId = outId.OutPlayerId:ToString()
            -- → "6333a58673a37dc7cb11a7a7"
        end
    end
)

-- Other players' (cached) profiles
local profiles = FindAllOf("PMPlayerPublicProfile")
for _, p in ipairs(profiles or {}) do
    local username = p.Username:ToString()
    local playerId = p.PlayerId:ToString()
end
-- The local player is NOT in this cache.

-- Display name in match (after replication; see PlayerNamePrivate caveats)
local ps = FindFirstOf("PlayerState_Game_C")
if ps and ps:IsValid() then
    local displayName = ps.PlayerNamePrivate:ToString()
    -- → "Ispicas" (custom/real games), or hex Prometheus ID
    --   (practice mode and replication-window contexts).
end
```

## Cross-references

- **Disambiguation of "Prometheus" (module vs API):** [`overview.md` → "The two 'Prometheus'es"](./overview.md#the-two-prometheuses)
- **The identity decision (which ID is OSPlus's primary key):** [ADR 0001](../decisions/0001-identity-model.md)
- **Production resolver code:** [`mod/OSPlus/scripts/identity.lua`](../../mod/OSPlus/scripts/identity.lua)
- **UE4SS 3.0.1 known bugs (full list):** [`ue4ss-version-and-gotchas.md` → "UE4SS 3.0.1 known bugs"](./ue4ss-version-and-gotchas.md#ue4ss-301-known-bugs)
- **`PlayerNamePrivate` 3-modes learnings:**
  - [`docs/learnings/playernameprivate-transient-account-id.md`](../learnings/playernameprivate-transient-account-id.md)
  - [`docs/learnings/playernameprivate-machine-name-out-of-match.md`](../learnings/playernameprivate-machine-name-out-of-match.md)
- **Backend ecosystem discovery:** [`docs/learnings/os-prometheus-api-ecosystem.md`](../learnings/os-prometheus-api-ecosystem.md)
- **Per-player engine surface (PlayerState):** [`player-state.md`](./player-state.md)
- **Match phase model (when does PMIdentitySubsystem exist):** [`game-state.md`](./game-state.md) — exists from cold-start.
- **Per-match counter shapes:** [`data-model.md`](./data-model.md)
- **Player-side identity perception:** [`docs/glossary.md` → "Player identity"](../glossary.md#player-identity)
- **Sibling docs index:** [`docs/engine/README.md`](./README.md)

## Open questions

- **Do `PMPlayerModel:GetCached*V1` UFunctions work with the
  `({}, {})` shape on UE4SS 3.0.1?** Untested post-v33→v36.
  Re-testing would close the simpler-call-path question for
  identity reads.
- **Steam Ticket → Odyssey auth handshake.** Programmatic auth
  path documented by Clarion but full guide not published. For
  OSPlus to ever ship a sidecar that talks to the backend
  *without* manual Fiddler capture, this needs to be
  reconstructed.
- **Is there a `ReceiveOnLogin` / `ReceiveOnAuthCompleted` hook
  on `PMIdentitySubsystem`?** The current pattern hooks
  `GetIdentityState` (called many times per session, then we
  early-return when we have what we need). A login-completion
  hook would be cleaner. Probe target.
- **`PMPlayerPublicProfile` cache update semantics.** When new
  players are observed (joining a lobby, queuing into a match),
  do they get appended to the cache? Is there a flush event?
  Catalogued at one moment in time; the dynamics are open.
- **Whether `FindAllOf("PMPlayerPublicProfile")` returns the
  local player at any point.** KB observation was "local is
  NOT in the cache"; whether that's invariant or just true at
  the dump-time moment is open.
