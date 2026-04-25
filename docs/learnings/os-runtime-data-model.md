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

**1. UFunction signatures (visible in the dump) — *signatures* are settled; the *Lua calling convention* for them was not.**
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
Both `Get*Cached*` are synchronous reads of the local cache; `GetDisplayNameV1` is async (returns a request ID, fires the multicast `GetDisplayNameV1Completed` delegate when the response arrives). Pass-3 hypothesised that the "expected 2 parameters" Lua error was UE4SS's UFunction caller wanting placeholder slots for both outputs — Pass-4 falsified this for the `(Bool out, X out)` signature class on `PMPlayerModel`. **None of the documented placeholder shapes work** in this UE4SS build (v3.0.1) — see `docs/learnings/ue4ss-outparam-marshaling-failure.md` for the per-shape error matrix and the BP-wrapper / direct-property-read workarounds. The signatures themselves are correct; only the *Lua-side* calling glue is broken.

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

The **delegate path** is the working substrate in this UE4SS build. Subscribe to `PMPlayerModel.GetMeRequestV1Completed` — a `MulticastInlineDelegateProperty` (offset 0x248) on `PMPlayerModel` typed by signature `MeRequestV1Completed__DelegateSignature`. Callback shape: `(Succeeded: Bool, RequestId: Str, MeResponse: MeResponseV1, ErrorResponse: ErrorResponse)`. Force-trigger (only needed if you can't wait for the natural login fire) via `PMPlayerModel:GetMeV1(false, nil)` which returns `(WasSent, OutRequestId)` — `OutRequestId` correlates with the delegate's `RequestId`.

`MulticastDelegateProperty:Add` takes `(UObject targetObject, FName | string functionName)` — **not a Lua function** (passing one is a native C++ access violation; `pcall` does not save you). The binding target must be a UObject; in OSPlus that means a Blueprint actor delivered via `BPModLoaderMod`, per `docs/learnings/ue4ss-lua-multicast-delegate-binding.md` and `.cursor/skills/ue4ss-modding/references/mod-actor-pattern.md`. ADR 0001's R-B implementation is the canonical example.

```lua
-- 1. Acquire a ModActor BP instance (delivered via BPModLoaderMod) whose
--    UFunction "OnMeResponse" matches MeRequestV1Completed__DelegateSignature.
local modActor = -- ... acquire BP_OSPlusDelegateBridge instance

-- 2. Bind from Lua. (UObject, FName) — never a Lua function.
local model = FindFirstOf("PMPlayerModel")
model.GetMeRequestV1Completed:Add(modActor, "OnMeResponse")

-- 3. The BP forwards the payload back into Lua via whatever bridge mechanism
--    the project chose (RegisterHook on a notification UFunction the BP calls,
--    watched property the Lua side reads, etc.).
```

The **synchronous cache-read path** (`GetCachedMeResponseV1`, `GetCachedPlayerPublicProfile`, `GetCachedLinkCodeV1`, etc.) was hypothesised in Pass-3 as a warm-cache fast-path but **falsified in Pass-4** for the entire `(Bool out, X out)` UFunction class on `PMPlayerModel` in this UE4SS build. Every placeholder shape errors at the marshaling layer; see `docs/learnings/ue4ss-outparam-marshaling-failure.md`. If a future feature needs synchronous cache reads, the workarounds are direct UProperty access (untested — needs a property-dump probe), a BP wrapper that invokes the UFunction natively (BPs bypass UE4SS's Lua marshaler), or a UE4SS upgrade. **None of the workarounds are wired up today;** the current Stage-5 path waits for the natural login-time delegate fire instead.

The `GetDisplayNameV1` UFunction is a *separate concern* — it returns a request ID + fires `GetDisplayNameV1Completed` async (same delegate-binding pattern as above, equivalent ModActor BP wrapper). Use it only for cases where the cached profile is missing or stale; not the right tool for "what's my Prometheus ID right now?"

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

2. **UE4SS UFunctions with output parameters are *sometimes* callable from Lua via placeholder slots — but the `(Bool out, X out)` shape on `PMPlayerModel` is broken in this build (UE4SS v3.0.1).** Single-output UFunctions like `PMIdentitySubsystem:GetSteamId()` work. Multi-output UFunctions where the first output is `BoolProperty Was*` and the second is a `StructProperty` or `StrProperty` fail across all documented shapes. Don't treat "the dump shows the signature" as evidence the call is reachable from Lua — only a *working in-game probe call* counts. Workarounds (BP wrapper, direct UProperty read, UE4SS upgrade) are documented in `ue4ss-outparam-marshaling-failure.md`. *(This insight was the inverted form of the original Pass-3 lesson, which was falsified in Pass-4 — kept here in corrected form so future agents don't re-derive the same wrong rule from the dump.)*

3. **OS internal naming has gotchas — "Rock" is the puck.** Future searches for game objects should match against `KNOWLEDGEBASE.md`'s naming conventions before grepping. Add a one-line note when a non-obvious name is discovered.

## Related

- **Feature** that produced this finding: `docs/features/in-game-profile-mvp.md` (Feasibility Pass 3 + Pass 4 spike).
- **KB updates** in the same branch:
  - `KNOWLEDGEBASE.md` → *Known Unknowns → Player Identity Reference* — `PMPlayerModel` UFunction note replaced with the resolved signatures + Pass-4 calling-convention findings (sync path unreachable in this build, delegate path requires ModActor BP).
  - `KNOWLEDGEBASE.md` → *Omega Strikers — Game Internals → Per-match runtime data* — subsection covering `PMPlayerMatchSummary`, `EPMEndOfGameStat`, and the puck-is-called-Rock naming note.
- **Pass-4 follow-up learnings** (extend / correct this doc):
  - `docs/learnings/ue4ss-lua-multicast-delegate-binding.md` — the working delegate-subscription substrate (D1).
  - `docs/learnings/ue4ss-outparam-marshaling-failure.md` — the broken `(Bool out, X out)` UFunction marshaling that falsified Pass-3's calling-convention claim (D2).
- **Prior learning** on the broader API ecosystem: `docs/learnings/os-prometheus-api-ecosystem.md`. This learning extends it with the *runtime client-side* data model, where that doc covered the *backend API* surface.
- **ADR consuming this finding:** `docs/decisions/0001-identity-model.md` — uses the delegate path (R-B) as Option B; cold-start posture revised post-Pass-4.
- **External evidence:** `F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\UE4SS_ObjectDump.txt` (40 MB; not committed). Reproducible via UE4SS GUI → Dumpers → "Dump all objects and properties" during active gameplay.
- **Probe sources:**
  - `docs/features/pass2-probes/pass2_probes.lua` F9 keybind, probe `C2` — Pass-3 in-game cross-check that confirmed the dump-derived signatures.
  - Same file F8 keybind, Pass-4 (Rev 4) — D1 introspection + D2 sweep that produced the two follow-up learnings.
