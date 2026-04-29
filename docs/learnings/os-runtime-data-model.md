# os-runtime-data-model

| Field | Value |
|---|---|
| Date | 2026-04-24 |
| Area | re |
| Tags | prometheus, identity, match-stats, ue4ss, ufunction, scriptstruct, redirect, ge-runtime |
| Status | partially-superseded |

> **2026-04-28 update — construction-order claim falsified.** The "first `PMPlayerPublicProfile` constructed = local player" rule (line 78, 87) was empirically wrong on accounts with a populated friends list. v38 of `identity.lua` deployed `NotifyOnNewObject` per the prescription here and captured `Greedom` (an inactive friend) instead of the local player. Friend list profiles can be constructed before the local player's, and the cache subsequently stays empty at the menu for 2+ minutes — `PMPlayerPublicProfile` is not the substrate for the local-player display name at all. The local Prometheus ID resolution via `RegisterHook` on `GetIdentityState` (line 84-86) still works and is in production. The display-name half is replaced by the `UPMPlayerUIData.Username` path — see `docs/learnings/ue4ss-type-stubs-as-canonical-source.md` and `mod/OSPlus/scripts/identity.lua` v41. The `MeResponseV1` super-struct claim (line 39) is still correct as a static dump fact; it just isn't reachable from the menu in this game's actual cache-warming behavior.


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

Also relevant: **`PMPlayerPublicProfile`** (a UObject *wrapper class*, not the struct) has a `PlayerPublicProfile : Struct` field + `IsOnline : Bool` + `IsNativePlatformFriend()` UFn. **Cache composition is context-dependent and races during cold-start identity bootstrap** (R-B v27 update — supersedes Pass-6 v2's "first non-empty walk works at login" claim, which was a Pass-6 v2-time-of-observation artifact):

- *Cold-start, very early in identity bootstrap* (the first ~250ms after `PMIdentitySubsystem:GetIdentityState` first fires), `FindAllOf("PMPlayerPublicProfile")` returns **0 instances** — the cache hasn't populated yet. R-B v27 cold-start logs captured 2 `GetIdentityState` fires in this window before any profile existed.
- *Cold-start, ~3s after the first `GetIdentityState` fire*, the cache has populated to **100+ instances** (observed: 112). This is a synchronous load of the friend list / matchmaking pool / recent-opponents — the local profile is one of them, but not findable via "first non-empty `PlayerId`" walk because (a) iteration order isn't guaranteed and (b) `PlayerState.PlayerNamePrivate` disambiguation doesn't work either: during cold-start, `PlayerNamePrivate` is the **Windows hostname** (e.g., `DESKTOP-XXX-NNNN`), not an account ID — identity hasn't been bound to the PlayerState yet.
- *At main menu, after identity bootstrap settles*, the cache may shrink back to 1 instance (just local) before friend-list reload, or may stay at 100+ depending on platform / friend-list-loaded state. Pass-6 v2's NUM_SIX summary press happened to land in a quiet window where "first non-empty" returned the local — that working observation does **not** generalize to cold-start.

**The reliable disambiguation key is construction order, not iteration order or PlayerState lookup.** The local profile is the **first** `PMPlayerPublicProfile` constructed during identity bootstrap; the friend/lobby profiles are constructed afterwards in a synchronous batch. R-B captures this via `NotifyOnNewObject("/Script/Prometheus.PMPlayerPublicProfile")`, gates the callback to capture only the first instance, then reads `PlayerId` from that captured reference (eagerly on capture if populated, or on the next `GetIdentityState` fire if construction-time `PlayerId` is empty). Construction order is more reliable than `FindAllOf` iteration order (implementation-defined) and doesn't depend on `PlayerState.PlayerNamePrivate` (unbound during cold-start).

The "resolve once and cache" R-B premise still holds — `PlayerId` is session-stable. What changed is the *read mechanism*: not "walk `FindAllOf` for the first non-empty" but "capture construction order, then read on engine-driven fire."

### Local-identity resolution path (callable from Lua)

The **`RegisterHook` + `NotifyOnNewObject` combined path** is the working substrate in this UE4SS build (post-Pass-5 pivot, post-Pass-6 v2 concrete pin, post-R-B-v27 disambiguation fix). Two cooperating module-load installs:

1. **`RegisterHook("/Script/Prometheus.PMIdentitySubsystem:GetIdentityState")`** — direct module-load install (no instance required for known UFunction paths; see `ue4ss-cold-start-hook-install-pattern.md`). Acts as the read trigger.
2. **`NotifyOnNewObject("/Script/Prometheus.PMPlayerPublicProfile")`** — captures the **first** profile instance constructed during identity bootstrap. This is the local player's profile (friend / lobby profiles are constructed afterwards in a synchronous batch — observed: 112 instances ~3s after the first `GetIdentityState` fire).

In the `GetIdentityState` callback, read `PlayerId` from the captured local profile instance (not from a `FindAllOf` walk). Cache + self-`UnregisterHook` on first non-empty read.

```lua
-- ADR 0001 R-B production pattern (mod/OSPlus/scripts/identity.lua).
-- Install at module load, not on a user keypress — login fires before any
-- user interaction is possible. See docs/learnings/ue4ss-cold-start-hook-install-pattern.md.
local PRE_ID, POST_ID
local resolvedPid
local localProfileInstance

NotifyOnNewObject("/Script/Prometheus.PMPlayerPublicProfile", function(instance)
    if localProfileInstance ~= nil then return end  -- only the first
    if resolvedPid then return end
    if not instance or not instance:IsValid() then return end
    localProfileInstance = instance
    -- Eager read: if PlayerId is populated at construction time, resolve now.
    -- Otherwise the GetIdentityState callback below will retry on the next fire.
    onIdentityHookFire()
end)

PRE_ID, POST_ID = RegisterHook(
    "/Script/Prometheus.PMIdentitySubsystem:GetIdentityState",
    function(_context)
        if resolvedPid then return end  -- once-flag (handles pre+post double-fire)
        if not (localProfileInstance and localProfileInstance:IsValid()) then return end

        local pid
        pcall(function()
            local struct = localProfileInstance.PlayerPublicProfile
            if struct then pid = struct.PlayerId and struct.PlayerId:ToString() end
        end)
        if not pid or pid == "" then return end  -- not yet — keep hook live

        resolvedPid = pid
        ExecuteInGameThread(function()
            -- Defer one tick: matching post-fire may still be in flight.
            -- The once-flag above keeps the body idempotent across the gap.
            pcall(UnregisterHook,
                "/Script/Prometheus.PMIdentitySubsystem:GetIdentityState",
                PRE_ID, POST_ID)
        end)
        -- ... fan out to subscribers ...
    end)
```

**Pass-6 v2 empirical results** (the evidence the ADR pin rests on): instrumented all 79 UFunctions across `PMPlayerModel` (44) + `PMIdentitySubsystem` (35) with `RegisterHook(Pre|Post)`. During cold-start login, exactly **4 UFunctions fire**:

| UFunction | Class | Why |
|---|---|---|
| **`GetIdentityState`** ★ | `PMIdentitySubsystem` | Fires earliest (~T+0 in identity-bootstrap window). One-instance-per-process subsystem — simplest hook lifecycle. Semantic match for "identity changed, re-read it." **R-B's chosen target.** |
| `GetCachedPlayerPublicProfile` | `PMPlayerModel` | Fires during the same window. `PMPlayerModel` is a runner-up host. |
| `GetCachedPlayerMatchmakingConstraintsV1` | `PMPlayerModel` | Fires during the same window. Notable because `WasCached=false` while `PMPlayerPublicProfile.PlayerId` was already populated — confirms the walk is independent of `PMPlayerModel`'s cache flag. |
| `HasFeatureFlag` | `PMIdentitySubsystem` | Fires during the same window. Polled by feature-gate UI code. |

Two findings that load-bear into R-B's design:

1. **`PMPlayerPublicProfile.PlayerId` populates independently of `PMPlayerModel.WasCached`.** In Pass-6 v2's per-fire log, fire #9 captured ambient `PlayerId` populated while `WasCached=false`. This decouples R-B's read path from the broken `(Bool out, X out)` UFunction class (Pass-4 finding) — we don't need to wait for or read `PMPlayerModel`'s internal cache flag at all. Walk `PMPlayerPublicProfile` instead; the cache populates ~1.78s after the first hook fires, and any of the 4 firing UFunctions is downstream enough to read it from.

2. **`MeRequestV1Completed` itself was not caught by any of the 79 hooks.** Confirms the Pass-5 hypothesis that `Broadcast` on `MulticastInlineDelegateProperty` doesn't go through a regular UFunction call path on this build — there's nothing to `RegisterHook` for the multicast itself. Downstream pollers (the 4 UFunctions above) are the available reactive surface. R-B uses one of them.

Why `RegisterHook` instead of `prop:Add` on `GetMeRequestV1Completed`: Pass-5 found `MulticastInlineDelegateProperty:Add` silently no-ops on this UE4SS build for any target shape (likely a vtable-offset mismatch in UE4SS's parser for Omega Strikers' shipped binary layout — `Add` returns ok, `GetBindings` reports 0, `Broadcast` succeeds at marshaling but invokes nothing). `RegisterHook` is implemented by patching the UFunction's `Func` pointer to UE4SS's interceptor — different mechanism, no exposure to the vtable bug, proven working on this build. See `docs/learnings/ue4ss-multicast-delegate-add-silent-noop.md` for the full evidence chain. The canonical implementation is ADR 0001's R-B (`docs/decisions/0001-identity-model.md`); the maintainer-recommended pattern this follows is from [UE4SS Issue #455](https://github.com/UE4SS-RE/RE-UE4SS/issues/455). The cold-start install timing pattern is captured in `docs/learnings/ue4ss-cold-start-hook-install-pattern.md`.

**Substrate revision history.** Pre-Pass-4: "subscribe to delegate from Lua (likely with a Lua callback)" — falsified in Pass-4 (Lua callbacks are a native crash; correct API is `prop:Add(uobject, fname)`). Pass-4 era: "subscribe via `prop:Add(modActor, fname)` with a ModActor BP wrapper, since `prop:Add` requires a UObject target" — falsified in Pass-5 (`prop:Add` is a silent no-op on this UE4SS build for `MulticastInlineDelegateProperty`). Post-Pass-5: "`RegisterHook` on the originating engine UFunction" — substrate validated at the registration layer (Pass-5 F6); concrete target deferred to Pass-6. Post-Pass-6 v2 (current): "`RegisterHook` on `PMIdentitySubsystem:GetIdentityState` + walk `PMPlayerPublicProfile` for the actual `PlayerId` read + self-unhook on first resolution" — concrete target picked from operational evidence; substrate validated end-to-end. For raw delegate-shape reference (still useful for any future work that targets the delegate signature directly — UE4SS C++ mod, future-build where `prop:Add` works): the property is `MulticastInlineDelegateProperty` at offset 0x248 on `PMPlayerModel`, signature `/Script/Prometheus.MeRequestV1Completed__DelegateSignature`, callback shape `(Succeeded: Bool, RequestId: Str, MeResponse: MeResponseV1, ErrorResponse: ErrorResponse)`, flags `0x130000` (`FUNC_Delegate | FUNC_Public | FUNC_MulticastDelegate`).

The **synchronous cache-read path** (`GetCachedMeResponseV1`, `GetCachedPlayerPublicProfile`, `GetCachedLinkCodeV1`, etc.) was hypothesised in Pass-3 as a warm-cache fast-path but **falsified in Pass-4** for the entire `(Bool out, X out)` UFunction class on `PMPlayerModel` in this UE4SS build. Every placeholder shape errors at the marshaling layer; see `docs/learnings/ue4ss-outparam-marshaling-failure.md`. If a future feature needs synchronous cache reads, the workarounds are direct UProperty access (untested — needs a property-dump probe), a BP wrapper that invokes the UFunction natively (BPs bypass UE4SS's Lua marshaler), or a UE4SS upgrade. **None of the workarounds are wired up today;** the current Stage-5 path uses `RegisterHook` on the natural identity-flow UFunction(s) instead.

The `GetDisplayNameV1` UFunction is a *separate concern* — it returns a request ID + fires `GetDisplayNameV1Completed` async. Same `RegisterHook`-on-originating-UFunction pattern applies for any future feature that needs to react to display-name changes; the multicast delegate equivalent (`GetDisplayNameV1Completed`) is presumed to share the same `prop:Add` silent-no-op fate as `GetMeRequestV1Completed` since they're the same property type on the same class. Use the `GetDisplayNameV1`-style hook only for cases where the cached profile is missing or stale; not the right tool for "what's my Prometheus ID right now?"

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
- **Pass-4 / Pass-5 / Pass-6 follow-up learnings** (extend / correct this doc):
  - `docs/learnings/ue4ss-lua-multicast-delegate-binding.md` — the Pass-4 `prop:Add(uobject, fname)` API surface (D1, no longer load-bearing for ADR 0001 R-B since Pass-5 found it non-functional).
  - `docs/learnings/ue4ss-outparam-marshaling-failure.md` — the broken `(Bool out, X out)` UFunction marshaling that falsified Pass-3's calling-convention claim (D2).
  - `docs/learnings/ue4ss-multicast-delegate-add-silent-noop.md` — Pass-5: why `prop:Add` is non-functional on this build, and the pivot to `RegisterHook` on engine UFunctions.
  - `docs/learnings/ue4ss-cold-start-hook-install-pattern.md` — Pass-6: why `RegisterHook` for cold-start events must install at module load via `NotifyOnNewObject` + `FindFirstOf`, not on a user keypress.
- **Prior learning** on the broader API ecosystem: `docs/learnings/os-prometheus-api-ecosystem.md`. This learning extends it with the *runtime client-side* data model, where that doc covered the *backend API* surface.
- **ADR consuming this finding:** `docs/decisions/0001-identity-model.md` — uses the delegate path (R-B) as Option B; cold-start posture revised post-Pass-4.
- **External evidence:** `F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\UE4SS_ObjectDump.txt` (40 MB; not committed). Reproducible via UE4SS GUI → Dumpers → "Dump all objects and properties" during active gameplay.
- **Probe sources:**
  - `docs/features/pass2-probes/pass2_probes.lua` F9 keybind, probe `C2` — Pass-3 in-game cross-check that confirmed the dump-derived signatures.
  - Same file F8 keybind, Pass-4 (Rev 4) — D1 introspection + D2 sweep that produced the two follow-up learnings.
