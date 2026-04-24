# os-runtime-data-model

| Field | Value |
|---|---|
| Date | 2026-04-24 |
| Area | re |
| Tags | prometheus, identity, match-stats, ue4ss, ufunction, scriptstruct, redirect, ge-runtime |
| Status | confirmed |

## Symptom

Two recurring blockers across feature work — both rediscovered cold every session:

1. **"`PMPlayerModel` getter UFunctions aren't trivially callable from Lua."** Existing `KNOWLEDGEBASE.md` carried this as a known gap, blocking any feature that needs the local Prometheus ID. Pass-2 of the in-game-profile-mvp confirmed the symptom: calling `model:GetCachedMeResponseV1()` errored with `UFunction expected 2 parameters, received 0`.
2. **"Where does the per-match redirect counter live?"** `ForEachFunction` on the local Pawn (`C_NimbleBlaster_C`) returned zero matches for any redirect-related pattern. The hypothesis space (Pawn components, ball/puck actor, replicated `PlayerState` properties) was unexplored without a clear next probe.

Without a documented mental model for *how the runtime data is laid out*, every future feature ("show local Prometheus ID", "count saves per match", "expose per-character match aggregates", etc.) has to redo the same RE.

## Root cause

The runtime data is reachable, but not via the obvious paths. Three things weren't clear before the GUI Object Dumper run:

**1. UE4SS calls UFunctions including their *output* parameters as placeholder slots.**
The signatures (visible in the dump):
```
PMPlayerModel:GetCachedMeResponseV1
  ├─ WasCached     : BoolProperty   ← OUTPUT
  └─ OutMeResponse : StructProperty ← OUTPUT (MeResponseV1 — see below)

PMPlayerModel:GetCachedPlayerPublicProfile
  ├─ WasCached : BoolProperty   ← OUTPUT
  └─ Profile   : StructProperty ← OUTPUT (PlayerPublicProfile)

PMPlayerModel:GetDisplayNameV1
  ├─ WasSent      : BoolProperty ← OUTPUT
  └─ OutRequestId : StrProperty  ← OUTPUT (request ID for the async fetch)
```
Both `Get*Cached*` are synchronous reads of the local cache; `GetDisplayNameV1` is async (returns a request ID, fires the multicast `GetDisplayNameV1Completed` delegate when the response arrives). The error "expected 2 parameters" was UE4SS's UFunction caller wanting placeholder slots for both outputs.

**2. `MeResponseV1` is a subclass of `PlayerPublicProfile`** (UE `ScriptStruct` inheritance). The dump line `ScriptStruct /Script/Prometheus.MeResponseV1 [sps: 0000021F9ECFBE00]` points at PlayerPublicProfile's address as `sps` (super-script-struct). So `OutMeResponse` carries every PlayerPublicProfile field — `PlayerId`, `Username`, cosmetic IDs, `PlatformIds`, etc. — *plus* the Me-specific extras (`MatchmakingRegion`, `EulaNeeded`, etc.). One sync call → full local identity.

**3. Per-match counters don't live on the Pawn class.** They live on `/Script/Prometheus.PMPlayerMatchSummary` — a parallel C++ ScriptStruct keyed per player per match. `ForEachFunction(Pawn)` would never find them. The dump confirmed it directly.

There's also an internal naming oddity: **the puck/ball is called "Rock"** in OS code. `/Script/Prometheus.PMRockCharacter` is the puck class; `EKnockBackType::Redirect = 2` is the redirect-as-knockback enum value. Future "find the ball" searches should grep `Rock`, not `Ball` / `Puck` / `Core`.

## Fix

The runtime data model below is now the canonical reference. KB updated in the same branch (Player Identity Reference fixed; new "Per-match runtime data" subsection added under *Omega Strikers — Game Internals*).

### Identity surface — `PlayerPublicProfile` (the canonical profile shape)

The shape returned by every cached-profile path. Field offsets observed from the dump:

| Offset | Field | Type | Notes |
|---|---|---|---|
| 0x00 | **`PlayerId`** | Str | **Prometheus ID — the canonical backend key, also the value tracker sites use.** |
| 0x10 | `Username` | Str | Display name (cached, post-replication). |
| 0x20 | `Title` | Str | Resolved title text. |
| 0x30 | `LogoId` | Str | Cosmetic IDs — already an unlockable surface. |
| 0x40 | `NameplateId` | Str | |
| 0x50 | `EmoticonId` | Str | |
| 0x60 | `TitleId` | Str | |
| 0x70 | `SocialUrl` | Str | |
| 0x80 | `Tags` | Array&lt;Name&gt; | |
| 0x90 | `Organization` | Struct | |
| 0xB8 | `CurrentPlatform` | Enum | Steam / Xbox / PSN / etc. |
| 0xBC | **`PlatformIds`** | Struct | **Likely contains the SteamID + other platform IDs — the SteamID↔PrometheusId crosswalk.** |
| 0xD8 | `MasteryLevel` | Int | |
| 0xE0 | `PlayerStatus` | Str | |

`MeResponseV1` extends this (sps inheritance) with: `Timestamp`, `LastDisplayNameChangeTimestamp`, `DisplayNameStatus` (Enum), `TutorialProgress` (Struct), `EulaNeeded` (Bool), `MatchmakingRegion` (Name), `GameLiftRegionUrls` (Array&lt;Struct&gt;), `DiscordConnection` (Struct).

Also relevant: **`PMPlayerPublicProfile`** (a UObject *wrapper class*, not the struct) has a `PlayerPublicProfile : Struct` field + `IsOnline : Bool` + `IsNativePlatformFriend()` UFn. The 100+ instances `FindAllOf("PMPlayerPublicProfile")` returns are the *remote*-player profile cache; the local player isn't in it. For the local player, prefer `PMPlayerModel:GetCachedMeResponseV1`.

### Local-identity resolution path (callable from Lua)

```lua
local model = FindFirstOf("PMPlayerModel")
-- UE4SS expects placeholders for output params; pass them, capture returns:
local wasCached, meResponse = model:GetCachedMeResponseV1(false, nil)
if wasCached and meResponse then
    local prometheusId = meResponse.PlayerId  -- Str
    local username     = meResponse.Username  -- Str
    -- ...platform IDs, cosmetic IDs, etc.
end
```

If `wasCached == false`, the cache hasn't filled yet. Fallback: subscribe to the multicast delegate `/Script/Prometheus.MeRequestV1Completed__DelegateSignature` (carries `MeResponse : MeResponseV1`) — but delegate-binding from UE4SS Lua hasn't been validated yet in this codebase, so the sync path is the proven one.

> **Pass-4 validation still pending.** The UE4SS calling convention for output params (specifically: `(false, nil)` vs `(false, {})` vs no args) varies by build. The signatures are known; the exact invocation shape needs an in-game probe before any feature relies on it.

The `GetDisplayNameV1` UFunction is a *separate concern* — it returns a request ID + fires `GetDisplayNameV1Completed` async. Use it only for cases where the cached profile is missing or stale; not the right tool for "what's my Prometheus ID right now?"

### Per-match runtime data — `PMPlayerMatchSummary`

```
/Script/Prometheus.PMPlayerMatchSummary  (ScriptStruct)
├─ 0x00 RedirectRock          : Int    ← per-player redirect counter
├─ 0x04 PowerUpsPickedUpCount : Int
├─ 0x08 HitRockIntoGoalArea   : Int    ← shots on goal
└─ 0x0C DamageDoneToPlayers   : Int
```

Cross-checked against the EOG stat enum (the *full* per-match stat universe surfaced at end-of-match):

```
/Script/Prometheus.EPMEndOfGameStat
├─ None=0, Goals=1, Assists=2, Saves=3, KOs=4
├─ Redirects=5, ShotsOnGoal=6, Damage=7, PowerUps=8
└─ EPMEndOfGameStat_MAX=9
```

`PMPlayerMatchSummary` covers **4 of 9** (Redirects + ShotsOnGoal + Damage + PowerUps). The other 5 (Goals / Assists / Saves / KOs) live on a sibling structure — most likely `PMPlayerState` (the C++ parent of `PlayerState_Game_C`) or another summary keyed off it. Open Pass-4 question: enumerate `PMPlayerState` properties to find the missing 5, and figure out how a `PMPlayerMatchSummary` instance maps back to its player (is it held by `PMPlayerState`? An array on `PMGameState`? Keyed by `PlayerId`?).

Also discovered alongside:
- `/Script/Prometheus.PMEndOfGamePlayerUIData:Redirects : Struct` — the EOG UI's redirect surface (probably wraps the same counter for display).
- `/Script/Prometheus.PMRockCharacter:LastRedirectKnockBack : Struct` — last redirect on the puck character itself. Useful for per-event detail (vs. per-match aggregate) if a future feature ever wants per-redirect timing/location.
- `/Script/Prometheus.EKnockBackType::Redirect = 2` — redirects are classified knock-backs of type 2.

## Lesson

**Three transferable insights:**

1. **For "where is X reachable?" questions in OS, run the GUI Object Dumper (UE4SS GUI → Dumpers) during active gameplay first.** Greppable single-file output beats a battery of `ForEachFunction` probes for hypothesis-space exploration. The 40 MB dump took ~0.6s to produce and answered both blockers in one targeted set of greps.

2. **UE4SS UFunctions with output parameters need placeholder slots in the call.** When the dump shows a UFunction with N child properties (typically `BoolProperty Was*` + `StructProperty Out*`), those are outputs — pass placeholders, capture multiple return values. "Expected N parameters, received 0" is *not* "uncallable"; it's UE4SS's caller asking for the slots.

3. **OS internal naming has gotchas — "Rock" is the puck.** Future searches for game objects should match against `KNOWLEDGEBASE.md`'s naming conventions before grepping. Add a one-line note when a non-obvious name is discovered.

## Related

- **Feature** that produced this finding: `docs/features/in-game-profile-mvp.md` (Feasibility Pass 3).
- **KB updates** in the same branch:
  - `KNOWLEDGEBASE.md` → *Known Unknowns → Player Identity Reference* — `PMPlayerModel` UFunction note replaced with the resolved signatures and call shape.
  - `KNOWLEDGEBASE.md` → *Omega Strikers — Game Internals → Per-match runtime data* — new subsection covering `PMPlayerMatchSummary`, `EPMEndOfGameStat`, and the puck-is-called-Rock naming note.
- **Prior learning** on the broader API ecosystem: `docs/learnings/os-prometheus-api-ecosystem.md`. This learning extends it with the *runtime client-side* data model, where that doc covered the *backend API* surface.
- **ADR consuming this finding:** `docs/decisions/0001-identity-model.md` — uses the resolved local-identity path as Option B.
- **External evidence:** `F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\UE4SS_ObjectDump.txt` (40 MB; not committed). Reproducible via UE4SS GUI → Dumpers → "Dump all objects and properties" during active gameplay.
- **Probe source:** `docs/features/pass2-probes/pass2_probes.lua` (F9 keybind, probe `C2`) — the in-game cross-check that confirmed the dump-derived signatures.
