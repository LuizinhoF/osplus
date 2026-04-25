# Pass 2 + Pass 3 + Pass 4 + Pass 5 + Pass 6 probes — `OSPlusProbes` mod

Runtime scripts for Feasibility Passes 2 through 6 of [`in-game-profile-mvp`](../in-game-profile-mvp.md). **NOT shipped with OSPlus.** Install as a separate UE4SS mod, run the probes, then uninstall. The `OSPlus` mod is never modified by this work.

> **STATUS (2026-04-25, post-Pass-5 pivot):** Pass 2, Pass 3, Pass 4, and **Pass 5 are now all COMPLETE**. The Pass-5 verdict (universal silent no-op of `prop:Add()` for `MulticastInlineDelegateProperty` on this UE4SS build) pivoted ADR 0001 R-B from "ModActor BP wrapper for delegate binding" to "RegisterHook on engine-side originating UFunction" — see [`docs/learnings/ue4ss-multicast-delegate-add-silent-noop.md`](../../learnings/ue4ss-multicast-delegate-add-silent-noop.md) for evidence chain + root-cause analysis (vtable-offset mismatch in UE4SS's binary parser, UE4SS Issue #455 maintainer recommendation). **Pass 6 (in progress) — RegisterHook discovery probe** (`NUM_SIX` keybind) on every UFunction of `PMPlayerModel` + `PMIdentitySubsystem`. Identifies which engine UFunction(s) fire reliably during natural identity flow and what state is available at each fire — the operational target ADR 0001 R-B will hook. Earlier Pass-5 history below is kept as-is so the F1/F10 evidence chain stays grep-friendly. **Pass 5 history (kept for context):** BP-path viability micro-probe. ADR 0001 was accepted on API introspection, not behavioral validation; Pass 5 fills that gap before any BP work in the UE editor. **Findings so far:** F7 (E1/E2) → outcome (a): `Add` is fully permissive at bind time. F5 (E4) → all 40 `PMPlayerModel` properties are `MulticastInlineDelegateProperty`; no scalar identity UProperty fast-path. F6 (E3) → bind+hook install cleanly, but `:GetMeV1` force-trigger hits the same out-param marshaling bug as `GetCached*`, and natural `MeRequestV1` doesn't re-fire on UI nav (only at login, before our bind). F4 (E5) → broadcast-bound `OnMeResponseFired` to all 40 `PMPlayerModel` delegates; ~50s of UI nav including a loadout-character mutation produced **0 hook fires**. F3 (E6) iter 1 → 0 `__DelegateSignature` matches, but the probe was too narrow (no unfiltered total, no sample names). **F3 (E6) iter 2 (2026-04-25):** ground truth — `PMPlayerModel` has **44 UFunctions** (all "regular" request handlers like `UpdateDisplayNameV1`, `GetPlayerLoadoutsV1`, etc.), and **NONE have `FUNC_Delegate` flag set, NONE have `__DelegateSignature` suffix**. Same for `PMBaseServiceModel` (0 UFunctions) and `Object` (1 UFunction: `ExecuteUbergraph`). 45 total UFunctions across the chain, **0 delegate-signature candidates anywhere**. **F2 (E7) (2026-04-25):** controlled-broadcast probe — Phase A surfaced 0 metatable methods (`getmetatable(prop) = nil`); Phase B's 8 `StaticFindObject` candidates all returned not-found; Phase C's `Broadcast()` with 0 args **errored — and the error leaked the signature path for free**: `/Script/Prometheus.MeRequestV1Completed__DelegateSignature:RequestId` (StrProperty at StoredAtIndex 1). **Two breakthroughs:** (1) signatures are *package-scoped*, not class-scoped — F3 walked the wrong outer (no bug in F3, just wrong scope assumption); (2) the delegate type name *drops the `Get` prefix* from the property (property `GetMeRequestV1Completed` → signature `MeRequestV1Completed__DelegateSignature`), which is why my StaticFindObject sweep in F2.B missed it. Plus the discrepancy: `prop:Add` returned OK while `GetBindings()` returned 0 — either Add is a silent no-op OR GetBindings doesn't surface our binding type. **F1 (E8) v1 result (2026-04-25):** Phase A WORKED — signature found at the package outer (`DelegateFunction /Script/Prometheus.MeRequestV1Completed__DelegateSignature`, flags `0x130000` = `Delegate|Public|MulticastDelegate`, **4 params: `Succeeded`, `RequestId`, `MeResponse`, `ErrorResponse`** — exactly what Pass 4 inferred from the cache UFunction). **Signature mystery for ADR 0001 is FULLY RESOLVED.** But Phase A's type introspection (`p:GetClass():GetName()`) returned `nil` for all 4 params, which cascaded into Phase C: my probe built `fullArgs = {nil, nil, nil, nil}`, `ipairs` skipped iteration entirely, and every Broadcast attempt was effectively `Broadcast(nil, nil, ...)` → `[push_strproperty]` error at the `RequestId` slot for every arity. **Phase C didn't actually test the substrate; it tested whether `nil` marshals as `Str` (it doesn't).** Phase B's GetBindings stayed at 0 across all 5 Add/Remove calls. The "BIND PATH BROKEN" verdict is a probe artifact — v2 needs to re-run with proper args. **F1 v2 (this rev):** multi-path type introspection (5 paths), name-driven arg defaults (hardcoded for the 4 known param names + generic name heuristics), `paramCount` tracked separately from `#params`, numeric loops instead of `ipairs`, `e8CallBroadcast(prop, arity, args)` takes intended arity to preserve trailing nils, multi-line error logging to capture continuation paths. **F1 v2 result (2026-04-25):** Phase A SUCCESS — multi-path introspection worked, full param types confirmed (`Succeeded:BoolProperty`, `RequestId:StrProperty`, `MeResponse:StructProperty`, `ErrorResponse:StructProperty`). Phase B GetBindings stayed at 0 across all 5 cycles. Phase C: arity-1 errored at `RequestId`, arity-2 errored at `MeResponse`, arity-3 errored at `ErrorResponse` (each error walked one slot deeper, confirming the marshaler iterates slot-by-slot and accepts `nil` as default for `StructProperty` once the prior slot is filled), **arity-4 `Broadcast(false, "e8-pass5-test", nil, nil)` returned OK — passed marshaling cleanly, dispatch happened — but produced 0 hook fires.** Three independent signals (GetBindings=0, all 5 Add cycles, arity-4 successful Broadcast with 0 fires) all converge on the same diagnosis: **`MulticastInlineDelegateProperty:Add()` from UE4SS Lua does NOT register an engine-side binding for the cross-actor BP-target shape.** Verdict: STRONG SIGNAL bind path looks broken, but before pivoting ADR 0001 we triangulate with **F10 (E8 Phase D)** to disambiguate: is `Add` a UNIVERSAL no-op on this build, or only broken for our specific shape? Plus a parallel web-research sweep on UE4SS GitHub issues. **F10 (E8 Phase D) (in progress):** six sub-probes — D0 prop UClass introspection (Inline vs Sparse vs regular), D1 `pairs(prop)` for internal Lua-side fields, D2 API-surface enumeration across ~25 plausible method names (`AddDynamic`, `AddUFunction`, `Bind`, etc.), D3 same-actor bind to disambiguate cross-actor vs universal no-op, D4 explicit `FName(...)` bind to test the string→FName conversion path, D5 `:Bind()` if present as alt API, D6 cross-actor re-confirmation Broadcast. Decisive triangulation before pivoting to UE4SS C++ mod path.

Scope:

- **Pass 2** — resolved by `F11` (battery: A1+A3+B1+B2) and `F12` (A2 poll). Done 2026-04-24; see the feature doc's `### Pass 2 findings` section.
- **Pass 3** — `F9` (battery: C1+C2+C3) resolves the UFunction signatures (critical path for `0001-identity-model`) and pushes into the capture-surface hypothesis space (components / replicated PlayerState). Best paired with a **UE4SS GUI object dumper** run (primary Pass 3 task — see below).
- **Pass 4** — `F8` (battery: D1+D2). **Done 2026-04-25.** D1 (delegate substrate) viable with ModActor BP wrapper; D2 (sync cache pre-check) unreachable in this UE4SS build. ADR 0001 accepted on Path A. See the `### F8 — Pass 4 spike` section below for the four-revision crash-forensics history that produced the two learnings.
- **Pass 6 v2** — `NUM_SIX` (E9) RegisterHook discovery probe. **Goal:** identify the engine-side UFunction(s) on `PMPlayerModel` (and fallback target `PMIdentitySubsystem`) that fire reliably during natural identity flow, and what identity state is available at the time of the fire — output feeds directly into ADR 0001 R-B's "hook this UFunction, read identity from `<source>`" sentence. **Methodology:** mass-hook β. v2 installs at module load via `NotifyOnNewObject` + a `FindFirstOf` one-shot (UE4SS Issue #455 maintainer-recommended pattern), so hooks are in place *before* the natural login flow runs. **NUM_SIX is now a pure summary endpoint** — dumps install state, per-UFunction fire counts, ambient PlayerId. Each fire-time callback unwraps every parameter via `context[i+1]:get()` and reads an ambient PlayerId from `PMPlayerPublicProfile`. **No BP work, no editor work, no pak rebuild — entirely Lua.** Decision matrix in the `### NUM_SIX` section below. **v1 (keypress-install) findings still valid:** RegisterHook works on 79/79 PMPlayerModel + PMIdentitySubsystem UFunctions with zero failures, eliminating the "/Script/Prometheus restriction" risk.
- **Pass 5** — `F7` (E1/E2) **resolved 2026-04-25 → outcome (a): Add is fully permissive at bind time.** `F6` (E3) installs the UE4SS `RegisterHook` on the 0-param `OnMeResponseFired` BP UFunction (added to OSPlus's existing ModActor) and binds it to `GetMeRequestV1Completed`. **No force-trigger** — `:GetMeV1` is unreachable from Lua (same out-param marshaling bug as `GetCached*`). `F4` (E5) broadcast-binds the SAME UFunction to all 40 `PMPlayerModel` multicast delegates. **`F4` outcome 2026-04-25:** 0 hook fires after ~50s of UI nav + loadout mutation. `F3` (E6) is the ground-truth probe. **Iteration 1** returned 0 `__DelegateSignature` matches but was too narrow (filter-only, no unfiltered totals). **Iteration 2 (resolved 2026-04-25):** PMPlayerModel has 44 "regular" UFunctions (all request handlers — `UpdateDisplayNameV1`, `GetPlayerLoadoutsV1`, etc.), 0 with `FUNC_Delegate` flag, 0 with `__DelegateSignature` suffix; PMBaseServiceModel has 0 UFunctions; CoreUObject.Object has 1 (`ExecuteUbergraph`). 45 total UFunctions across the chain, 0 delegate-signature candidates. Since F5 confirmed 40 delegate properties exist, the signatures must live at the `/Script/Prometheus` package outer (shared-signature pattern) where `ForEachFunction` on the class can't reach them. `F2` (E7) **resolved 2026-04-25:** controlled `prop:Broadcast()` with 0 args errored with a signature path leak — `/Script/Prometheus.MeRequestV1Completed__DelegateSignature:RequestId` (StrProperty at StoredAtIndex 1). **Two breakthroughs:** signatures are package-scoped (not class-scoped, F3 walked the wrong outer); delegate type name drops the `Get` prefix from the property name. Plus a new finding: `prop:Add` returned OK but `GetBindings()` returned 0 — either silent no-op or GetBindings is broken. `F1` (E8) v2 **resolved 2026-04-25:** Phase A confirmed full 4-param signature with types (Bool/Str/Struct/Struct); Phase B GetBindings stayed 0 across 5 cycles; Phase C arity-4 `Broadcast(false, "e8-pass5-test", nil, nil)` succeeded at marshaling but produced 0 hook fires. **Strong signal: `prop:Add()` is not registering bindings.** Triangulated by `F10` (E8 Phase D) **before** pivoting ADR 0001. `F10` (E8 Phase D) is the bind-shape disambiguation probe: D0 prop UClass introspection, D1 `pairs(prop)`, D2 API-surface enumeration (~25 method names), D3 same-actor bind (target = PMPlayerModel itself; if this works, cross-actor is the broken case), D4 explicit `FName(...)` bind, D5 `:Bind()` alt API if present, D6 cross-actor re-confirmation. After F10 + parallel web research, ADR 0001 R-B is either rescued by an alt API or pivots to UE4SS C++ mod. `F5` (E4) is the parallel exploration: enumerates ALL UProperties on `PMPlayerModel`, looking for directly-readable identity data; outcome was that ALL 40 props are `MulticastInlineDelegateProperty` — no scalar fast-path.
- **Manual** — B3 (redirect volume count during 2-3 practice matches) — still pending.

---

## Install

*UE4SS layout note:* on this install, UE4SS lives directly under `Binaries\Win64\` (so the log is at `Binaries\Win64\UE4SS.log` and mods are under `Binaries\Win64\Mods\`). Some UE4SS installations use a nested `Binaries\Win64\ue4ss\` folder instead. Check where your `UE4SS.log` actually lives before copying paths below.

1. Create the mod directory in the game install:

    ```
    <GameDir>\OmegaStrikers\Binaries\Win64\Mods\OSPlusProbes\Scripts\
    ```

    For this machine: `F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\Mods\OSPlusProbes\Scripts\`.

2. Copy `pass2_probes.lua` (this folder) to that directory, renaming it to `main.lua`:

    PowerShell one-liner (adjust source path if you cloned the repo elsewhere):

    ```powershell
    $src = "C:\Users\T-Gamer\Documents\omega-strikers-overlay\docs\features\pass2-probes\pass2_probes.lua"
    $dst = "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\Mods\OSPlusProbes\Scripts\main.lua"
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    Copy-Item $src $dst -Force
    ```

3. Create `enabled.txt` with contents `1` in the mod root:

    ```powershell
    Set-Content "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\Mods\OSPlusProbes\enabled.txt" "1"
    ```

4. Add `OSPlusProbes : 1` to `Mods\mods.txt` (next to `OSPlus : 1`). Any text editor; no reorder needed.

5. Restart the game fully (UE4SS only loads Lua mods once, at process start).

On successful load you'll see a session-marker line in `Binaries\Win64\OSPlusProbes.log` (the persistent forensic log; UE4SS.log gets overwritten on relaunch and clobbered post-crash, so the session marker lives in the survivor file):

```
==== [OSPlusProbes] session start YYYY-MM-DD HH:MM:SS — F11 Pass2, F12 A2 poll, F9 Pass3, F8 Pass4 Rev 4, F7 Pass5 E1/E2 (Add validation), F6 Pass5 E3 (BP-fire test, hook+bind), F4 Pass5 E5 (broadcast bind to 40 delegates), F5 Pass5 E4 (property dump), F3 Pass5 E6 (delegate signature ground-truth), F2 Pass5 E7 (controlled-broadcast probe), F1 Pass5 E8 v2 (signature-fetch + Broadcast-with-args), F10 Pass5 E8 Phase D (bind shape variations), NUM_SIX Pass6 E9 (RegisterHook discovery on PMPlayerModel + PMIdentitySubsystem UFunctions), persistent log to OSPlusProbes.log ====
```

The Pass-4 spike is **keybind-only** — nothing happens until you press F8. (An earlier revision auto-attempted binding from a `LoopAsync` at script load and crashed the game during startup before any diagnostic could be captured. `pcall` does not catch native C++ access violations on UE delegate properties; the only safe move is to put every binding attempt under explicit user control and print *before* the call so the log captures the killer.)

---

## Run

Two keys, used from different game contexts.

### F11 — one-shot snapshot battery

Runs probes A1, A3, B1, B2 once. Press in each of these four contexts and save the log output with a note about which context:

- **Main menu** (no match loaded)
- **Character select** (match loaded, no Pawn)
- **Active match** (controlling a Pawn)
- **Post-match** (results screen)

Each press produces a block in `UE4SS.log` between `=== [Pass2] F11 battery @ HH:MM:SS ===` markers. All four contexts provide evidence for a different assumption:

| Probe | What it tests | What matters per context |
|---|---|---|
| A1 | `SteamId` stability | Same value in all four? Or does one context return nil / different? |
| A3 | `PMPlayerModel` UFunctions | Does any of the three calls succeed anywhere? Does success correlate with context? |
| B1 | `PM*` object population | Which classes appear only in-match? Which persist across match-end? |
| B2 | Redirect-signal candidates | Only meaningful in-match; elsewhere reports "No Pawn" — that's expected. |

### F12 — A2 poll (PlayerNamePrivate replication window)

Starts a 15-second polling loop that reads `PlayerNamePrivate` every 500ms (30 samples total). Press it **during character-select** so we catch the hex → friendly-name transition.

Look for:

- The **length** of the hex-shape readings: `len=20` or `len=24`? (Key finding for the identity ADR — 24 matches Clarion's documented Prometheus ID format directly.)
- Whether any sample shows a friendly name within the 15s window.
- Whether different matches produce the same or different hex values for the same player.

### F9 — Pass 3 battery (C1 + C2 + C3)

One-shot battery of three capture-surface + identity-signature probes. Run in a single context: **active match with controlled Pawn** (not menu, not char-select). Each press produces a block in `UE4SS.log` between `=== [Pass3] F9 battery @ HH:MM:SS ===` markers.

| Probe | What it tests | What matters |
|---|---|---|
| C1 | Pawn component enumeration | Walks `BlueprintCreatedComponents` + `InstanceComponents` arrays on the Pawn; per-component, class name + ForEachFunction scan for redirect patterns. Answers "does the redirect signal live on a component?" |
| C2 | `PMPlayerModel` UFunction signature introspection | For each of `GetCachedMeResponseV1`, `GetDisplayNameV1`, `GetCachedPlayerPublicProfile`: enumerates their parameter-properties via `ForEachProperty`. Reveals NumParms + each parameter's name + type. **If this works, the Pass-2 "expected 2 parameters, received 0" mystery is resolved in-session, unblocking the identity ADR.** |
| C3 | `PlayerState_Game_C` full property + UFunction dump | Scans all properties + UFunctions on the BP-subclass; reports redirect-pattern matches. Answers "does redirect surface as a replicated property or UFunction on PlayerState?" |

**Expected outcomes:**

- C1 prints each component's class path (e.g. `.../C_NimbleBlaster.C_NimbleBlaster_C.SomeComponent_GEN_VARIABLE`) and, if any component has a redirect-shaped UFunction, that match. A clean run with no matches narrows the hypothesis space further (but doesn't falsify — ball-side is still unexamined).
- C2 either prints each target UFunction's parameter list (WIN — we have the signatures) or prints `(ForEachProperty not available on UFunction in this build)`. The latter means we fall back on the GUI dumper.
- C3 prints two `total` counts + any redirect-pattern matches for properties and UFunctions on `PlayerState_Game_C`. A `Redirects` Int property would be a major find.

### F8 — Pass 4 spike (D2 then D1)

**Acceptance prerequisite for [`0001-identity-model`](../../decisions/0001-identity-model.md).** Validates the two-pronged R-B implementation: subscription-based delegate (preferred) + cache-fetch fast-path (fallback). Both must work for R-B to be implementable.

#### How to run

**Keybind-only — no automatic binding at script load.** Direct binding to a `MulticastInlineDelegateProperty` from UE4SS Lua isn't documented in our knowledge base, and `pcall` does not catch native C++ access violations on UE delegate properties; safety requires every binding attempt to be explicit and under user control.

1. Launch the game.
2. Wait until you're past the login splash (i.e. somewhere `PMPlayerModel` exists — main menu is fine).
3. **Press F8 once.** The probe runs D2 first (safer), then D1 binding, then forces a delegate fire if binding succeeded.
4. Grep the log:
    ```powershell
    Select-String -Path "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\UE4SS.log" -Pattern "\[(D1|D2|Pass4|OSPlusProbes)\]" | ForEach-Object { $_.Line }
    ```

Each press produces a block in `UE4SS.log` between `=== [Pass4] D battery @ HH:MM:SS ===` markers.

#### What's tested

| Probe | What it tests | Decision impact |
|---|---|---|
| D2 | `PMPlayerModel:GetCachedMeResponseV1` synchronous cache read | Tries 3 placeholder shapes (`(false, nil)` / `(false, {})` / `()`) until one works. Succeeding **also resolves the Stage-5 calling-convention prereq** as a side effect. |
| D1 (bind) | Subscription to `PMPlayerModel.GetMeRequestV1Completed` (`MulticastInlineDelegateProperty`) | Tries 2 plausible UE4SS API shapes (`prop:Add(cb)`, `prop:Bind(cb)`). Trimmed from 4 because `prop:AddDynamic` is BP-only and `RegisterCustomEvent` is the wrong API for this purpose (it's for Lua-to-Lua events). |
| D1 (fire) | `PMPlayerModel:GetMeV1(false, nil)` force-trigger | Only runs if D1 binding succeeded. Logs `(WasSent, OutRequestId)` for correlation against subsequent `[D1] FIRE` lines. |

#### Outcome decision matrix

| D1 binds? | D1 fires? | D2 works? | Outcome |
|---|---|---|---|
| Yes | Yes | Yes | **R-B accepted.** ADR can flip to `accepted`. |
| Yes | Yes | No | R-B works but no warm-cache fast-path; subscribe-time pre-check unreliable. ADR re-opens; design changes. |
| Yes | No | Yes | Binding API call returned without error but delegate doesn't fire. Try a follow-up probe variant (RegisterHook on a callback UFunction) before accepting. |
| No | — | Yes | Direct prop binding falsified. Spike pivots to a follow-up RegisterHook-based R-B variant — same "event-driven" semantics, different mechanism. |
| No | — | No | Deeper RE needed. ADR cannot proceed. |

#### What to look for in the log after F8

- `[D2] OK shape=... wasCached=true PlayerId="<24-char hex>"` — D2 working. Note which shape succeeded.
- `[D1] BIND OK via ...` — substrate primitive works. Note which API shape.
- `[D1] FIRE #N ... succeeded=true PlayerId="<24-char hex>" [matches last-trigger]` — full validation.
- `[D1] GetMeV1 triggered: WasSent=false` — request was short-circuited (cache warm); delegate may not fire this run; press F8 again ~30s later to retry.

If D1's `[FIRE]` line **never appears** after multiple F8 presses spaced apart, that's evidence the binding call returned cleanly but the callback isn't actually wired up — same outcome as the "Yes / No / Yes" row above.

#### If F8 crashes the game

Native crashes from operating on UE delegate properties are not catchable by `pcall`. The probe writes every step to a **persistent log file** (`OSPlusProbes.log`, next to `UE4SS.log`) with `flog()` — `print()` + `io.open` + `flush` per call. UE4SS doesn't know about this file, so it survives crashes and re-launches.

Why the dedicated log: UE4SS overwrites `UE4SS.log` on each launch. After a crash, UE4SS attaches to `CrashReportClient.exe` and rewrites the log with PS-Scan spam that drowns out our pre-crash entries. `OSPlusProbes.log` is our file and isn't touched by UE4SS at all.

Steps after a crash:

1. **Don't dismiss the crash report immediately if you want to be safe** (read the log first; the log file is written and flushed before the crash, so reading after dismissal is also fine).
2. Read the persistent log:
    ```powershell
    Get-Content "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\OSPlusProbes.log" -Tail 50
    ```
3. The **last line** is the killer call (one of the `>>> ATTEMPT` markers, or a step-N line right before the crash).
4. Report it back. The probe is revised to drop or substitute that specific call.

If you want to grep just the Pass-4 spike lines from the persistent log:

```powershell
Select-String -Path "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\OSPlusProbes.log" -Pattern "\[(D1|D2|Pass4|OSPlusProbes)\]" | ForEach-Object { $_.Line }
```

Do **not** restore the script-load auto-binding loop; it was the cause of an earlier hard-to-diagnose crash.

### F6 — Pass 5 step 2 (BP-fire setup: hook + bind)

**Step-2 setup probe — run FIRST in any session.** F7 (E1) confirmed `Add` is permissive at bind, so any BP UFunction signature will bind. The remaining open question is fire-time: when the engine packs `(Bool, Str, MeResponseV1, ErrorResponse)` into a buffer at delegate offsets and tries to invoke our 0-param BP UFunction reading from that buffer at *its* offsets, **does the BP UFunction actually fire?**

F6 doesn't answer that question by itself anymore — it just installs the observability:

1. Locates the OSPlus `ModActor` and verifies `OnMeResponseFired` exists on its class.
2. Registers a UE4SS `RegisterHook` (post-hook) on the BP UFunction. One-time per session.
3. Binds `OnMeResponseFired` to `PMPlayerModel.GetMeRequestV1Completed`.

There's **no force-trigger.** Earlier revisions called `model:GetMeV1(false, nil)` here, but `:GetMeV1` hits the exact same out-param marshaling bug as the `GetCached*` family (see `docs/learnings/ue4ss-outparam-marshaling-failure.md`) — it's unreachable from Lua. Natural `MeRequestV1` fires also don't recur during main-menu activity (only at login, before our bind is placed). So F6 alone validates *nothing* — it just makes the substrate observable. **F4 (E5) below is what actually exercises the hook**, by broadcast-binding the same UFunction to all 40 `PMPlayerModel` delegates so UI navigation (which fetches loadouts, profiles, characters) provokes natural fires on a delegate of the same UE type.

#### Prerequisites

The OSPlus mod's existing `ModActor` BP must be updated with a new UFunction:

- **Name:** `OnMeResponseFired` (must match exactly — the probe binds by FName)
- **Inputs:** none — cheapest possible signature (0 params vs delegate's 4)
- **Body:** one `Print String` node with literal `"[OSPlus] OnMeResponseFired native-fired"`. Leave **`Print to Log`** checkbox **on**.

Compile + Save the BP, then **File → Cook Content for Windows**, then `ue-assets/package_logicmod.ps1`, then drop the new `OSPlus.pak` into `<GameDir>/OmegaStrikers/Content/Paks/LogicMods/`.

#### How to run

1. Restart the game (UE4SS only loads Lua at process start; new pak content also takes effect on restart).
2. Wait until you're past the login splash (main menu fine — same precondition as F8).
3. **Press F6 once.** Locates ModActor → verifies `OnMeResponseFired` exists → registers hook (one-time) → binds delegate → logs the signals to watch for.
4. **Then press F4 once** (see next section) to broadcast-bind to the other 39 delegates.
5. **Then nav game UI** (loadouts, character select, profile) for ~60s.
6. Grep:
    ```powershell
    Select-String -Path "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\OSPlusProbes.log" -Pattern "\[(E3|E5|Pass5)\]" | ForEach-Object { $_.Line }
    Select-String -Path "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\UE4SS.log" -Pattern "(OnMeResponseFired|\[OSPlus\]|\[E3)" | ForEach-Object { $_.Line }
    ```

#### Outcome decision matrix (F6 + F4 combined)

The decision matrix below applies to the **combined F6+F4+nav** flow, not F6 alone. F6 alone produces no fires for the reasons above.

| `[E3.HOOK] FIRE` in OSPlusProbes.log | `[OSPlus] OnMeResponseFired native-fired` in UE4SS.log | Outcome | Step-3 implication |
|---|---|---|---|
| **Yes** | **Yes** | (i) **Both fire** | **Event-driven path FULLY VALIDATED.** ADR 0001 R-B is implementable as documented. Move to Stage 4 design — extending the BP UFunction signature to read at least the `Succeeded` Bool, then bridging back to Lua via a custom event. |
| **Yes** | **No** | (ii) Hook only | Engine reaches the UFunction but BP body doesn't run. Surprising — the BP VM is rejecting truncated args mid-dispatch, post-ProcessEvent. Needs follow-up probe; might still be salvageable via UFunction-only handling (skip the BP body, do everything in the hook). |
| **No** | **No** | (iii) Neither | Engine silently no-ops on signature mismatch. Truncated BP UFunction is a dead end for fire-time. Pivot path — likely UE4SS C++ mod, since BP can't author signature-matched UFunctions for `/Script/Prometheus` types. |
| (any) | (any) — game crashed | (iv) **Crash on fire** | Fire-time signature validation is fatal. Last on-disk line in `OSPlusProbes.log` is the killer. Same pivot as (iii); also document the crash mode. |

#### What to look for in the F6 log block

- `[E3] step 1   FOUND OnMeResponseFired (NumParms=...)` — your BP edit + cook + repack + redeploy succeeded. (NumParms may print as a `userdata` rather than `0` — that's a separate UE4SS reflection quirk; the FName match is what matters.)
- `[E3]   hook registered OK` — UE4SS attached to the BP UFunction. Required for F4 to be useful.
- `[E3]   BIND ACCEPTED` — `GetMeRequestV1Completed` has our binding (consistent with E1's permissive finding).

The fire signals (`[E3.HOOK] FIRE` and `[OSPlus] OnMeResponseFired native-fired`) won't appear from F6 alone — they appear after F4 + UI nav.

#### What this probe leaves out (deferred)

- **Reading the actual MeResponse payload from BP.** That requires extending the BP UFunction signature, which has its own questions (does the engine pack the `Bool` correctly into a 1-param UFunction? Can we go further?). Tackled in Stage 4 if outcome (i) holds.
- **Removing our binding cleanly.** The binding stays in place for natural fires across the rest of the session. If you want to tear it down, restart the game (the easiest path now that F4 broadcast-binds to 40 delegates).
- **Distinguishing which delegate fired.** The hook is on the UFunction, not the delegate property — so a fire tells us "engine invoked OnMeResponseFired" but not "from which of the 40 delegates". For the validation question that's enough. For future feature use we'd assign a distinct BP UFunction per delegate.

### F4 — Pass 5 step 2.5 (broadcast bind to 40 delegates)

**The probe that actually answers the fire-time question.** Run **after F6** (which caches the ModActor and installs the hook). F4 binds the *same* `OnMeResponseFired` BP UFunction to all 40 multicast delegates on `PMPlayerModel` at once.

The substrate insight that justifies this: F5 (E4) showed all 40 properties are `MulticastInlineDelegateProperty` of the same UE type. Whatever the engine does at fire time for `GetMeRequestV1Completed`, it does for `PlayerLoadoutsV2RequestCompleted`, `PlayerPublicProfileChanged`, `GetPlayerCharactersV1RequestCompleted`, etc. So any of them firing with our truncated 0-param UFunction bound is sufficient evidence the dispatch works for the whole family.

The reason this is necessary: the original target (`GetMeRequestV1Completed`) only fires at login. Our hook isn't installed until after login. Force-triggering via `:GetMeV1` is blocked by the marshaling bug. Without F4, the hook is silent for the rest of the session.

#### Prerequisites

- F6 has been pressed at least once this session (caches `E3_MODACTOR`, registers the hook). F4 will abort with a clear message if either is missing.
- No new BP work — F4 reuses `OnMeResponseFired` from F6.

#### How to run

1. Press F6 first (sets up ModActor cache + hook).
2. **Press F4 once.** Iterates the 40 delegate names verbatim from F5's enumeration, attempts `prop:Remove` then `prop:Add` on each, summarizes bind counts.
3. **Nav game UI** for ~60s. Suggested itinerary: open Loadouts → switch character → close → open Profile (if available) → close → reopen Loadouts. Each screen typically triggers a `*RequestCompleted` / `*Changed` delegate as the game lazily fetches the data.
4. Watch `OSPlusProbes.log` for `[E3.HOOK] FIRE #N` lines. Logging is capped: first 5 fires verbose, then every 20th (so a chatty delegate doesn't drown the log).
5. **Press F4 again** any time to log the running fire count.

#### What to look for in the log

- `[E5] === bound 40, missing 0, failed 0 (of 40) ===` — all delegates accepted the bind. Expected outcome given E1's permissive finding.
- `[E5]   <DelegateName>: BIND FAILED: <err>` — single-delegate failure. Note which one; not necessarily fatal.
- `[E5]   <DelegateName>: property not found, skipping` — game build added/removed a delegate since 2026-04-25. Update `E5_TARGET_DELEGATES` in the script.
- `[E3.HOOK] FIRE #N — engine invoked OnMeResponseFired (self=...)` — **the primary success signal.** Each one is engine-driven, not Lua-driven, evidence that the truncated-signature dispatch works.
- `[OSPlus] OnMeResponseFired native-fired` in `UE4SS.log` (BP-side `Print String`) — the secondary signal that distinguishes outcome (i) from (ii).

#### What F4 doesn't tell you

- **Which delegate fired** (same UFunction = same hook). For the validation question, doesn't matter. For future feature work, distinct BP UFunctions per delegate would be needed.
- **What payload the engine packed.** The 0-param UFunction reads nothing. Reading the `Succeeded` Bool needs a 1-param UFunction in step 3.
- **Cleanup.** F4 leaves all 40 bindings in place. Easiest tear-down is a game restart; we're at the end of the spike anyway.

### F3 — Pass 5 step 4 (delegate signature ground-truth, iteration 2)

**Run after F4 produces 0 hook fires.** Iteration 1 returned `total __DelegateSignature UFunctions: 0` — the probe was too narrow (filtered first, never logged unfiltered total or sample names). Iteration 2 is empirical: walks the SuperStruct chain from `PMPlayerModel` up to 5 parent classes, logs the total UFunction count + first 20 names per class, and detects delegate signatures via *both* the `FUNC_Delegate` flag (`0x00100000`) AND the `__DelegateSignature` name suffix as independent signals. This way we see the actual ground truth, not a filter result.

#### Why two signals (flag AND suffix)?

Per UE4SS source ([`SDKGenerator/Common.cpp`](https://github.com/UE4SS-RE/RE-UE4SS/blob/3dd2bc5a/UE4SS/src/SDKGenerator/Common.cpp), `is_delegate_signature_function`), both are typically true together. Checking each independently means we learn *which* signal is missing if the convention differs in this game build:

- **Flag set, no suffix** → engine uses `FUNC_Delegate` correctly but a different naming scheme.
- **Suffix, no flag** → unlikely but would indicate something custom.
- **Neither anywhere in the chain** → either `ForEachFunction` filters delegate signatures out in this UE4SS build, or Prometheus uses a non-standard delegate macro family (e.g., sparse delegates with hand-registered signatures).

#### Why walk the parent chain?

UE4SS docs explicitly state `ForEachFunction(callback)` iterates "every UFunction that belongs to this struct" — class-immediate, no inheritance walk. F5's `ForEachProperty` shares the same scope rules, and it found 40 delegate properties on `PMPlayerModel` directly, so the signatures *should* also be on `PMPlayerModel` directly. But the iteration-1 result was 0, so we walk up the chain (capped at depth 5) just to be sure we haven't misjudged where they live.

#### Why this is decisive (when it works)

UE's `TMulticastScriptDelegate::ProcessMulticastDelegate` calls `target->ProcessEvent(SignatureFunction, ParamsBlob)` for every binding. A bound UFunction with `ParmsSize` smaller than the delegate's `ParmsSize` is dispatched against a buffer the engine sized to the delegate; in practice [the documented behavior is that signature mismatches are silently ignored](https://stackoverflow.com/questions/77277640/delegate-not-triggering-function-in-another-class-after-broadcasting). Our 0-param `OnMeResponseFired` is a worst-case mismatch. If F3 finds the delegate signatures and *all* 40 require N≥1 params, every binding F4 created is mismatched → outcome (iii) is the certain explanation. If even one delegate is 0-param and our hook still doesn't fire when it broadcasts, the bug is somewhere else (bind mechanism, hook plumbing, or no natural fire).

Bonus: F3 also disambiguates the F6 log line `FindFirstOf("ModActor_C"): BlueprintGeneratedClass /Game/Mods/OSPlus/ModActor.ModActor_C` by logging `:GetFullName()` (whose first token is the *type* — `ModActor_C` for an instance, `BlueprintGeneratedClass` for the class itself) and a `FindAllOf` count. Per [UE4SS docs](https://docs.ue4ss.com/dev/lua-api/global-functions/findfirstof.html) `FindFirstOf` only returns spawned non-default instances, and iteration 1 confirmed this: `ModActor_C /Game/.../ModActor_C_2147482178` is an instance path. Iteration 2 keeps the verification but drops the broken `:GetClass():GetName()` call (returned `nil` in iteration 1 — false-friend trap).

#### How to run

1. Press F6 first (this probe doesn't need it, but typically you'd already be set up from the F6→F4 flow).
2. **Press F3 once.** Probe runs Phase A (instance verification) → Phase B (UFunction enumeration up the SuperStruct chain) → Phase C (verdict).
3. Grep:
    ```powershell
    Select-String -Path "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\OSPlusProbes.log" -Pattern "\[E6\]" | ForEach-Object { $_.Line }
    ```

#### What to look for

- `[E6]   modActor:GetFullName() = ModActor_C /Game/...` → first token is `ModActor_C` → instance (expected).
- `[E6]   FindAllOf('ModActor_C') returned N instance(s)` → confirms instance count; iteration 1 saw 2 (worth understanding why eventually, but not blocking).
- `[E6] inheritance chain depth: D (capped at 5)` → how deep PMPlayerModel's parent chain is.
- `[E6] === class: <FullName> ===` → one block per class in the chain.
- `[E6]   total UFunctions on this class: N` — *the* key number iteration 1 didn't report. If N=0 on PMPlayerModel itself, `ForEachFunction` is broken on this class entirely.
- `[E6]   first K names (samples): [1] ... [K] ...` — sample function names. Useful to spot delegate-shaped names by inspection (anything with `Completed`, `Changed`, `Fired` is a candidate).
- `[E6]   --- M delegate-signature candidates on this class ---` followed by per-function lines `<name> (flags=0xN delegate-flag=true|false suffix=true|false NumProps=K [...types])`.
- `[E6]   grand totals across chain: F UFunctions, D delegate-signature candidates`.
- `[E6] → 0 delegate-signature candidates anywhere in the chain` — verdict (a)/(b)/(c) below.
- `[E6] → found D delegate-signature candidates total` — verdict (d) below; details in per-class entries.

#### Decision impact

| F3 iteration-2 result | Interpretation | Next step |
|---|---|---|
| Many UFunctions per class, 0 delegate-flag, 0 suffix matches anywhere | This UE4SS build's `ForEachFunction` doesn't expose delegate signatures, OR Prometheus uses a custom delegate path. | Try the GUI object dumper (Pass 3 section above) and grep its output for `__DelegateSignature` on `PMPlayerModel`. If the dumper finds them, the bug is `ForEachFunction`; if not, Prometheus is using something custom. |
| `total UFunctions: 0` on PMPlayerModel itself | `ForEachFunction` is broken on this specific class (would also have broken Pass-3 C2, but C2 hardcoded names so couldn't tell). | Try `model:GetClass():Reflection():GetProperty(...)` indirection, or fall back entirely to the GUI dumper. |
| Delegate signatures found, all 40 with N≥1 params | Outcome (iii) **mechanism-confirmed.** Truncated 0-param BP UFunction is a dead end at fire time. | Pivot: author a signature-matching BP UFunction (blocked because `MeResponseV1`/`ErrorResponse` are `/Script/Prometheus` types not visible to our editor) → likely UE4SS C++ mod, or accept that R-B requires a different bridge mechanism. ADR 0001 needs revision. |
| Delegate signatures found, K≥1 with N=0 params | Substrate should work for those K delegates. Hook silence during nav means either bind mechanism is broken OR none of those K fire during normal UI nav. | Add a follow-up probe: `prop:Broadcast()` on one of the K 0-param delegates as a controlled test. |
| Delegate-flag set on signatures but no `__DelegateSignature` suffix | Custom naming convention in this build. The flag tells us where they are; the per-function dump gives names directly. | Update `E5_TARGET_DELEGATES` filtering and re-run F4 with a known-matching signature. |

#### Iteration 2 result (2026-04-25)

Verdict was the first row of the matrix above: **44+0+1 = 45 UFunctions across PMPlayerModel + PMBaseServiceModel + Object, 0 delegate-signature candidates anywhere.** All 44 functions on PMPlayerModel are "regular" request handlers (`UpdateDisplayNameV1`, `GetPlayerLoadoutsV1`, `SubmitLinkCodeV1`, etc.) with neither the `FUNC_Delegate` flag nor the `__DelegateSignature` suffix. F5 already proved 40 delegate properties exist on the same class, so the signatures must live somewhere `ForEachFunction` can't reach — most likely the `/Script/Prometheus` package outer when delegates are declared at file scope and shared as property types. Per-property class-scoped introspection is therefore a dead end on this build; F2 (E7) sidesteps it.

### F2 — Pass 5 step 5 (controlled broadcast + GetBindings + StaticFindObject sweep)

**Run after F6, after F3 returned 0 delegate-signature candidates.** Sidesteps the introspection wall by directly testing the bind/dispatch substrate — does `prop:Broadcast()` from Lua actually reach our hook?

#### Why this is decisive

Three angles, three sources of evidence, in one probe:

- **Phase A — `pairs(getmetatable(prop))`:** If the multicast delegate property userdata exposes any undocumented signature accessors (e.g. a hidden `:GetSignatureFunction()`), the metatable iteration surfaces them. Bypasses the false-friend trap (UE4SS `__index` returns `userdata` for unknown keys, so `prop.GetFoo == nil` is never true) by listing only what's actually in the metatable.
- **Phase B — `StaticFindObject` sweep:** Tries 8 candidate paths for the `GetMeRequestV1Completed` signature (class-scoped, package-scoped per-property, package-scoped delegate-type-named, shared-signature naming patterns). If any resolve, `obj:ForEachProperty(...)` gives us NumProps directly — full signature ground truth.
- **Phase C — `prop:Broadcast()` with 0 args + `GetBindings()`:** The substrate test. Re-binds `OnMeResponseFired`, calls `Broadcast()` with no args, measures hook fire delta. Plus `GetBindings()` to confirm our bind actually persisted (vs `Add` being a silent no-op).

If Phase C's `Broadcast()` makes our hook fire, **the substrate works completely** — bind, dispatch, RegisterHook are all wired correctly. The "0 hooks during nav" then has only two possible causes:

1. **Engine's natural broadcasts use the *real* signature** and silent-skip our 0-arg UFunction (outcome iii). Lua-issued broadcasts go through a different code path that doesn't validate.
2. **No natural broadcast actually happens during the navs we tried.** `MeRequestV1Completed` fires only at login, before our bind is installed. The other 39 might be similarly login-only or only fire on rare events.

Either path is diagnosable from there and unblocks ADR 0001 at the substrate level. If `Broadcast()` does NOT fire our hook, the bind/dispatch path is broken in a more fundamental way (UE4SS Lua bind goes into a separate list, hook isn't actually attached, etc.).

#### Prerequisites

- **F6 pressed first** in this session (caches `E3_MODACTOR`, registers the hook). F2 will abort Phase C with a clear message if either is missing.
- No new BP work — F2 reuses `OnMeResponseFired` from F6.

#### How to run

1. Press F6 first (sets up ModActor cache + hook).
2. **Press F2 once.** Runs Phase A → Phase B → Phase C in sequence.
3. Grep:
    ```powershell
    Select-String -Path "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\OSPlusProbes.log" -Pattern "\[E7" | ForEach-Object { $_.Line }
    ```

#### What to look for

- `[E7.A]   metatable has N entries:` — full method list on the property userdata. If `GetSignatureFunction` or similar appears as `function` (REAL!), that's a free signature accessor we missed.
- `[E7.B]   FOUND: <path> -> <fullname>` followed by `NumProps via ForEachProperty: K` — at least one candidate path resolved. K is the parameter count for the delegate signature.
- `[E7.B]   not found: <path>` — negative result for that path; doesn't rule out others.
- `[E7.C]     GetBindings() returned N binding(s):` followed by per-binding lines — confirms our `Add` persisted. If `N=0` after we just re-bound, our `Add` was a silent no-op (rare but possible).
- `[E7.C]   hook fires AFTER Broadcast(): X (delta=D)` — **the primary signal.** D≥1 means substrate works; D=0 means substrate is broken.
- `[E7.C]   Broadcast() errored: <err>` — UE4SS validates broadcast args at Lua level. Read the error; it likely describes the expected signature (free signature reveal).

#### Decision impact

| F2 result | Interpretation | Next step |
|---|---|---|
| Phase A reveals an undocumented signature accessor | We can read the signature directly from Lua. | Use it to verify outcome (iii) mechanistically; revise F3 to use the new method. |
| Phase B finds the signature via `StaticFindObject` | We have the path. NumProps tells us the param count. | Same verdict logic as F3's "delegate signatures found" rows. |
| Phase C: D≥1 hook fire from `Broadcast()` | Substrate WORKS. ADR 0001 R-B path is unblocked. | Either (i) accept outcome (iii) for natural fires and move to a broadcast-driven design (manually trigger the right delegates from Lua), or (ii) install the bind earlier (before login, via `Lua_ModInitialized`) to catch the natural `MeRequestV1` fire. |
| Phase C: D=0 hook fires from `Broadcast()` | Substrate BROKEN. Check `GetBindings()` output above. | If `GetBindings()` shows our bind is missing, `prop:Add()` is a silent no-op in this UE4SS build → pivot to UE4SS C++ mod or a different bridge. If `GetBindings()` shows it's there but `Broadcast()` doesn't fire it, `RegisterHook` on the BP UFunction isn't actually attached at runtime (despite `Registered script hook` log line). |
| Phase C: `Broadcast()` errors with a signature-related message | UE4SS validates args at Lua level — the error message tells us the expected signature for free. | Use the revealed signature to author a matching BP UFunction (still blocked if signature includes `/Script/Prometheus` types) or pivot. |

#### F2 outcome (2026-04-25)

The probe surfaced **two breakthroughs** plus one open question:

**Breakthrough 1 — signature path leaked via `Broadcast()` error.** Phase C's `prop:Broadcast()` with 0 args errored at the UE4SS marshaling layer with:

```
[push_strproperty] Error: StrProperty can only be set to a string or FString
    Property: StrProperty /Script/Prometheus.MeRequestV1Completed__DelegateSignature:RequestId
    StoredAtIndex: 1
```

Two pieces of ground truth in one line:

1. **Signatures are PACKAGE-scoped, not class-scoped.** The full path is `/Script/Prometheus.MeRequestV1Completed__DelegateSignature` — outer is the package `/Script/Prometheus`, not the class `PMPlayerModel`. F3's `cls:ForEachFunction` walks class scope; that's why it returned 0 (no F3 bug — wrong scope assumption baked into the probe design).
2. **Delegate type name DROPS the `Get` prefix from the property.** Property is `GetMeRequestV1Completed`; signature is `MeRequestV1Completed__DelegateSignature`. The naming pattern is the C++ delegate type (`FMeRequestV1Completed`) without the `F` UE-style prefix, plus `__DelegateSignature`. The property's `Get` prefix is property-only metadata, not part of the delegate type. This is also why my F2.B `StaticFindObject` sweep missed it — I tried `GetMeRequestV1Completed__DelegateSignature` (with Get) but not without Get.

The signature also has at least 2 params: index 1 is `StrProperty RequestId` (revealed); index 0 is something it auto-defaulted (likely a `BoolProperty` — Pass 4 already inferred the full signature is `(Bool Succeeded, Str RequestId, MeResponseV1 Response, ErrorResponse Error)` from the matching cache UFunction).

**Breakthrough 2 — Phase A confirmed the metatable is hidden.** `getmetatable(prop)` returned `nil` for the `MulticastInlineDelegateProperty` userdata — UE4SS doesn't expose the metatable to Lua. Only the C++-bound methods listed in the Pass-4 introspection (Add/Remove/Clear/Broadcast/GetFName/GetClass) plus the Phase-A candidate-name probe's positive `GetClass = function (REAL!)` are reachable. No undocumented signature accessors exist on this surface.

**Open question — `prop:Add` returned OK but `GetBindings()` returned 0.** Phase C did `Remove`, `Add`, `GetBindings()` — and `GetBindings()` reported 0 binding(s) immediately after a successful `Add`. Either (a) `prop:Add()` is a silent no-op in this UE4SS build for our cross-actor BP-target binding shape — which would explain F4's "0 fires after 50s nav" — OR (b) `GetBindings()` doesn't surface our binding type (false zero). F1 (E8) Phase B resolves this with a Add/Remove/Add cycle plus per-call GetBindings.

**Net effect on next steps:** signatures are reachable now (we have the path pattern), F3's "0 candidates" is explained (wrong outer), and the substrate question reduces to a single decisive test — `Broadcast()` with proper args. F1 (E8) executes that test.

### F1 — Pass 5 step 6 (signature-fetch + Broadcast-with-args)

**Run after F6, after F2 leaked the signature path.** Decisive substrate test for ADR 0001 R-B.

#### Why this is decisive

F2's accidental signature reveal turns the formerly-introspection-blocked question into a direct test:

- **Phase A** fetches `/Script/Prometheus.MeRequestV1Completed__DelegateSignature` via `StaticFindObject`, reads `GetFunctionFlags()` (should have `FUNC_Delegate = 0x100000` set), and enumerates parameters via `ForEachProperty`. Output is the full param list with names and property-class types. **Resolves the signature mystery for ADR 0001 with no further indirection.**
- **Phase B** does an Add/Remove/Add cycle with `GetBindings()` between each call. If GetBindings tracks Add (count grows from 0 → 1 → 2 → 0 → 1), our binding IS in the list; F2's `GetBindings() == 0` was a false zero. If GetBindings stays at 0 throughout, `Add` is genuinely a silent no-op for our binding shape, and Phase C will confirm it independently.
- **Phase C** is the substrate test. Builds a default-arg list from Phase A's signature (`false` for Bool, `""` for Str, `nil` for Object/Struct, `0` for numerics, `{}` for Array/Map/Set). Calls `Broadcast()` with progressive arg counts 1..NumParams. For each successful Broadcast, measures hook-fire delta. **If any arity makes our 0-arg `OnMeResponseFired` hook fire, the bind+dispatch substrate works completely** — RegisterHook is attached, `prop:Add` did create a real binding (regardless of GetBindings result), and the engine's dispatch path doesn't silent-skip on signature mismatch. The "0 fires during nav" then has a narrowed explanation: engine-side natural broadcasts use a different code path that *does* validate signature (outcome iii at fire time, mechanism-confirmed for natural fires only).

If no arity fires our hook AND GetBindings stayed at 0, the bind path is broken at a fundamental level — `prop:Add()` is a silent no-op for cross-actor BP-target bindings. ADR 0001 R-B would need a different bridge mechanism (likely a UE4SS C++ mod that calls `MulticastDelegate.Add()` via the engine API directly, since the Lua API exposed by UE4SS is the only path BPModLoaderMod gives us).

#### Prerequisites

- **F6 pressed first** in this session (caches `E3_MODACTOR`, registers the hook). F1 will abort Phase B/C with a clear message if either is missing. Phase A runs regardless (it doesn't need ModActor — only the signature path).
- No new BP work — F1 reuses `OnMeResponseFired` from F6.

#### How to run

1. Press F6 first (sets up ModActor cache + hook).
2. **Press F1 once.** Runs Phase A → Phase B → Phase C in sequence.
3. Grep:
    ```powershell
    Select-String -Path "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\OSPlusProbes.log" -Pattern "\[E8" | ForEach-Object { $_.Line }
    ```

#### What to look for

- `[E8.A]   FOUND: <UFunction full name>` — the signature UFunction was reachable. If "not found", the path pattern is wrong — fall back to alternative naming variants in Phase A code.
- `[E8.A]   GetFunctionFlags() = 0xN` followed by `FUNC_Delegate (0x100000) set: true` — confirms this is a delegate signature UFunction, not a regular one.
- `[E8.A]   signature has K params:` followed by per-param lines `[i] <name> : <PropertyClass>` — **the prize.** Resolves the signature mystery. K is the param count; types tell us the marshaling shape.
- `[E8.B]   after Add #1: GetBindings() = N binding(s):` — if `N≥1`, GetBindings tracks Add and F2's zero was real-but-false-zero. If `N=0`, Add is a silent no-op (or GetBindings is broken — Phase C disambiguates).
- `[E8.B]     [i] obj=<full name> fn=<FName>` — per-binding details. If our binding shows up here, the bind list works.
- `[E8.C] >>> ATTEMPT prop:Broadcast(<N args>)` — each arity attempt logged before the call (so a native crash leaves the ATTEMPT line on disk as the last entry).
- `[E8.C]   N-arg Broadcast: OK; hook fires +D` — **the primary signal.** Any `D≥1` means the substrate works.
- `[E8.C]   N-arg Broadcast: ERR; hook fires +D` followed by `err: <message>` — UE4SS marshaling rejected the arg shape. Read the error; subsequent arities may succeed.

#### Decision impact

| F1 result | Interpretation | Next step |
|---|---|---|
| Phase A finds signature, K params dumped | Signature mystery RESOLVED. We have ground truth for ADR 0001's R-B signature design. | Carry the param list into ADR 0001's "Acceptance prerequisite". |
| Phase B GetBindings count grows with Add | Add IS creating bindings. F2's `GetBindings() == 0` was a probe artifact. | Rely on GetBindings for future bind-state checks. |
| Phase C: any arity fires our hook (`+D≥1`) | **SUBSTRATE WORKS.** Bind, dispatch, RegisterHook all wired correctly. ADR 0001 R-B unblocked. | Move to step 3 (extend BP UFunction signature to read `Succeeded` Bool, bridge to Lua). The "0 fires during nav" is then either signature-mismatch silent-skip on engine-side natural broadcasts (outcome iii at fire time, but only for engine-driven dispatches) OR no natural broadcast occurred during the navs we tried. We'd resolve which by manually triggering the delegate from Lua at the appropriate game lifecycle moments. |
| Phase B GetBindings stays 0 + Phase C no fires at any arity | **BIND PATH BROKEN.** `prop:Add()` is a silent no-op for cross-actor BP-target bindings in this UE4SS build. | Pivot ADR 0001 R-B to a UE4SS C++ mod (real cost; likely a separate ADR for the bridge layer), OR accept that the R-B path requires authoring native code. Falls back to the M (manual relink) path with the cost the original ADR documented. |
| Phase B GetBindings tracks Add but Phase C no fires | **AMBIGUOUS — fire-time silent-skip.** Binding IS there, but engine doesn't invoke our truncated UFunction even on Lua-issued Broadcast. Outcome (iii) mechanism-confirmed at fire time for ALL broadcasts, not just natural ones. | Same pivot as bind-broken case above. ADR 0001 R-B needs a different mechanism since signature-matched BP UFunctions aren't authorable in our editor. |
| Phase C errors at every arity with marshaling messages | UE4SS Lua can't construct the struct-typed args. | Try Phase C with hand-crafted struct tables, OR conclude that Lua-issued Broadcast isn't a viable substrate test for this signature shape — fall back to natural-fire observation across more game lifecycle states. |

#### F1 v1 outcome (2026-04-25) and v2 rewrite

**Phase A — SIGNATURE FOUND.** `StaticFindObject("/Script/Prometheus.MeRequestV1Completed__DelegateSignature")` returned `DelegateFunction /Script/Prometheus.MeRequestV1Completed__DelegateSignature` with flags `0x130000` = `FUNC_Delegate (0x100000) | FUNC_Public (0x20000) | FUNC_MulticastDelegate (0x10000)` — textbook multicast-delegate signature. **4 params with the names Pass 4 inferred from the cache UFunction:** `(Succeeded, RequestId, MeResponse, ErrorResponse)`. The signature mystery is fully resolved.

**Phase A bug — type introspection silently failed.** All 4 param types logged as `: nil` because `p:GetClass():GetName()` either errored under `pcall` or returned a userdata that tostrings to `"nil"`. F3 iter 2 had the exact same issue with the same call shape on its UFunction-property scans. v2 adds **5 introspection paths per property** (`Class:GetName`, `Class:GetFullName`, `Class:GetFName:ToString`, `GetCPPType`, `GetClassPrivate:GetName`) and logs each — at least one usually returns a usable string in UE4SS.

**Phase B — `GetBindings()` returned 0 across 3 Add calls.** Same as F2/E7. Either silent no-op or broken tracker.

**Phase C — false-negative cascade.** The Phase A `: nil` types bubbled into `e8DefaultArgForType(nil) → nil` for every slot, so `fullArgs = {nil, nil, nil, nil}`. Worse, `for i, a in ipairs(fullArgs)` iterates **zero times** when the table starts with nil, so the "default args constructed" log block printed empty (no `args[N] = ...` lines visible) and every `Broadcast(arity)` was effectively `Broadcast(nil, nil, ..., nil)`. UE4SS marshaling can't default a `StrProperty` from `nil` → `[push_strproperty] Error` at slot 2 (`RequestId`) for every arity. **Phase C didn't actually test the substrate; it tested whether `nil` marshals as `Str` (it doesn't).**

**v2 fixes (in `pass2_probes.lua`):**

1. **Multi-path type introspection** in `e8IntrospectPropertyType(p)` — tries 5 paths, logs each result. Even if all 5 return nil for a given property, the param NAME is still captured.
2. **Name-driven arg defaults** in `e8DefaultArgForName(pname)` — hardcoded for the 4 known `MeRequestV1Completed` param names (`Succeeded → false`, `RequestId → "e8-pass5-test"`, `MeResponse → nil`, `ErrorResponse → nil`) plus generic name-pattern heuristics (`*Id` / `*Name` → `""`, `Is*` / `Has*` → `false`, etc.). Type-driven defaults are kept as a secondary fallback.
3. **`paramCount` tracked separately from `#params`** so we can iterate even when `params[i].name` or `params[i].type` is nil.
4. **Numeric `for i = 1, paramCount do` everywhere** that was previously `ipairs` — Lua's `ipairs` and `#` both stop at the first nil.
5. **`e8CallBroadcast(prop, arity, args)` takes intended arity as a parameter** instead of computing it from `#args` — preserves trailing nils through to the C++ marshaler.
6. **Multi-line error logging in Phase C** — captures the `Property: ... /Script/Prometheus.X__DelegateSignature:Name` continuation line that lives 2-3 lines into UE4SS marshaling errors. Each error becomes a small free signature reveal.

After deploying v2 and re-running F6 → F1, the decision matrix above applies as written. v1's "BIND PATH BROKEN" verdict was a probe artifact — v2's decisive Phase C run is what tells us whether the substrate works.

#### F1 v2 outcome (2026-04-25)

**Phase A — SIGNATURE + TYPES FULLY RESOLVED.** The new multi-path `e8IntrospectPropertyType` returned a usable type via `Class:GetFName():ToString()` for all 4 params (the other 4 paths returned nil). Confirmed:

| Slot | Name | UClass |
|---|---|---|
| 0 | Succeeded | `BoolProperty` |
| 1 | RequestId | `StrProperty` |
| 2 | MeResponse | `StructProperty` |
| 3 | ErrorResponse | `StructProperty` |

Flags `0x130000` = `FUNC_Delegate | FUNC_Public | FUNC_MulticastDelegate`. ADR 0001's signature design has ground truth.

**Phase B — GetBindings stayed at 0.** All 5 Add/Remove cycles reported 0 bindings — same as F2/E7. Either silent no-op or false-zero; Phase C resolves.

**Phase C — marshaler walks slot-by-slot, arity-4 dispatches but our hook doesn't fire.** Each error continuation line revealed exactly which slot failed:

| Arity | Args sent | Result |
|---|---|---|
| 1 | `(false)` | ERR at `RequestId` (`[push_strproperty]` — `nil` not allowed for Str) |
| 2 | `(false, "e8-pass5-test")` | ERR at `MeResponse` (`[push_structproperty]` — but slots 0–1 marshaled cleanly) |
| 3 | `(false, "e8-pass5-test", nil)` | ERR at `ErrorResponse` (slot 2 `nil` ACCEPTED as default Struct, slot 3 `nil` rejected — UE4SS distinguishes "explicit nil for an arg" from "no arg at this position") |
| 4 | `(false, "e8-pass5-test", nil, nil)` | **OK; hook fires +0** |

The arity-4 result is the substrate test. UE4SS accepted all 4 args, marshaling completed, dispatch happened. **If any binding existed on `GetMeRequestV1Completed`, our `OnMeResponseFired` UFunction would have been invoked via `ProcessEvent` and our `RegisterHook` would have caught it.** It didn't fire (delta = 0).

**Verdict — STRONG SIGNAL bind path looks broken.** Three independent pieces of evidence converge:

1. `GetBindings()` returned 0 across 5 Add/Remove/Add cycles.
2. Arity-4 Broadcast succeeded at marshaling but invoked nothing (no hook fire).
3. F4 (E5) broadcast-bind to all 40 delegates produced 0 fires across ~50s of UI nav.

All consistent with `MulticastInlineDelegateProperty:Add()` being a **silent no-op for cross-actor BP-target bindings on this UE4SS build** — `Add` returns ok (E1 confirmed it's fully permissive at bind time, accepting nonexistent FNames without error) but doesn't actually create an engine-side binding entry.

**Before pivoting ADR 0001 R-B,** F10 (E8 Phase D) triangulates one more time — is `Add` UNIVERSALLY no-op, or only for our specific shape? Plus a parallel web-research sweep on UE4SS's GitHub issue tracker for known reports of this behavior.

### F10 — Pass 5 step 7 (E8 Phase D — bind shape variations)

**Run after F6.** Triangulating probe before pivoting ADR 0001 R-B. F1 v2 proved the bind+dispatch substrate is broken for our specific shape (cross-actor, BP-target, string FName); F10 disambiguates whether it's universal or shape-specific, and whether there's an alt UE4SS API name we missed.

#### Six sub-probes (each isolated; one failure doesn't abort the rest)

- **D0 — prop UClass introspection.** We have NEVER confirmed the property's actual UClass. F5 (E4) said "all 40 are MulticastInlineDelegateProperty" but that was via shorthand. D0 dumps `prop:GetClass():GetFullName()` and `:GetFName():ToString()`. Possible answers: `MulticastInlineDelegateProperty` (most common), `MulticastSparseDelegateProperty` (sparse storage; different binding API), or `MulticastDelegateProperty` (regular). API behavior may differ across these.
- **D1 — `pairs(prop)` iteration.** F2/E7 already confirmed `getmetatable(prop)` returns `nil`, but `pairs(prop)` may surface direct userdata fields (e.g., an `InvocationList` table). If anything appears, we have a C++-side state surface to read directly.
- **D2 — API surface enumeration.** Avoiding the false-friend trap (UE4SS `__index` returns userdata for unknown keys), we check `type(prop[name]) == "function"` for ~25 plausible method names (`Add`, `AddDynamic`, `AddUFunction`, `AddStatic`, `Bind`, `BindUObject`, `BindDynamic`, `Remove`, `Clear`, `Unbind`, `Broadcast`, `Execute`, `GetBindings`, `IsBound`, `Contains`, etc.). If `AddDynamic` or `Bind` surface as callables we never tried, we have a workaround candidate.
- **D3 — same-actor bind.** Bind a UFunction that lives ON the property's owner (PMPlayerModel itself) instead of on a separate ModActor. Tries 3 known UFunction names: `GetMeV1`, `GetDisplayNameV1`, `GetCachedMeResponseV1`. Logs GetBindings before/after and Δ. **If any same-actor bind tracks (Δ>0), cross-actor is the broken case** and we'd pivot to a different bridge approach for the BP target. **If still Δ=0 across all 3, `Add` is a UNIVERSAL no-op** and the Lua API is fundamentally broken for this property type.
- **D4 — explicit FName bind.** Many UE4SS APIs accept both string and FName, but the conversion path inside UE4SS may be the broken one. Tries `prop:Add(modActor, FName("OnMeResponseFired"))` instead of the string variant.
- **D5 — `:Bind()` if present.** Multicast delegates in UE C++ use `.Add()`, single-cast use `.Bind()`. UE4SS's API surface might expose `Bind` as a hidden working alternative.
- **D6 — cross-actor re-confirmation.** Repeats the original failing case with `Broadcast(arity 4)` to confirm v2's verdict reproduces deterministically.

#### Prerequisites

- **F6 pressed first** in this session. F10 will abort with a clear message if `E3_MODACTOR` isn't cached or the hook isn't registered.
- No new BP work — F10 reuses `OnMeResponseFired` and exists entirely in Lua.

#### How to run

1. Press F6 first (sets up ModActor cache + hook on `OnMeResponseFired`).
2. **Press F10 once.** All six sub-probes run in sequence; each is wrapped in `pcall` so a failure logs and continues.
3. Grep:
    ```powershell
    Select-String -Path "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\OSPlusProbes.log" -Pattern "\[E8\.D" | ForEach-Object { $_.Line }
    ```

#### What to look for

- `[E8.D]   prop:GetClass():GetFullName() = ...` — the property's actual UClass. Tells us which UE delegate property type we're dealing with.
- `[E8.D]   pairs(prop) yielded N entries` — if N>0, lists up to 30 keys with their Lua types. An `InvocationList` or similar would be a workaround target.
- `[E8.D]   prop.<NAME> = function  ★` — alt API names that exist as callables. `AddDynamic`, `AddUFunction`, `Bind` are highest-value finds.
- `[E8.D]   prop:Add(model, '<NAME>')  ok=true  bindings 0→1  Δ=1 ★ TRACKED` — same-actor bind worked. **Cross-actor is the bug.**
- `[E8.D]   prop:Add(model, '<NAME>')  ok=true  bindings 0→0  Δ=0` (3 times in D3) — universal no-op.
- `[E8.D]   prop:Add(modActor, FName(...))  bindings 0→1 Δ=1 ★ TRACKED` — string→FName conversion is the bug.
- `[E8.D]     (post-D* Add) Broadcast(4): OK; hook fires +1` — **THE PRIZE.** Substrate works for this variant; ADR 0001 R-B is rescued.

#### Decision impact

| F10 result | Interpretation | Next step |
|---|---|---|
| D2 surfaces `AddDynamic`/`AddUFunction`/`Bind` as callables | Alt API exists. Try the same flow with the alt name. | Run a follow-up probe with the alt method, then update ADR 0001 R-B with the working API name. |
| D3 shows ANY same-actor bind tracking (Δ>0) and Broadcast fires | Cross-actor binding is the broken case. Same-actor or self-actor binding works. | Pivot ADR 0001 R-B to register handlers on PMPlayerModel itself (synthesize a new UFunction or hook an existing one), not via ModActor. |
| D4 explicit FName tracks (Δ>0) | string→FName conversion in UE4SS is the bug. | Use FName explicitly throughout the R-B substrate; carry that pattern in a new learning doc. |
| D5 `:Bind()` works | Wrong API was being called all along. | Switch to `:Bind()`; investigate whether it's single-cast or multicast semantics. |
| D1 surfaces `InvocationList` (or similar) | Direct C++ state surface accessible. | May allow a manual workaround — append our entry to InvocationList directly. Last-resort hack. |
| ALL of D2/D3/D4/D5 produce Δ=0 and nothing surfaces | Bind path is unreachable from UE4SS Lua API entirely. | **Pivot ADR 0001 R-B to UE4SS C++ mod path** (separate ADR for the bridge layer; real engineering cost). Or fall back to the M (manual relink) path. Or explore Pass 6: hook a different UFunction the engine calls during identity flow (RegisterHook on PMPlayerModel:GetMeV1 itself, intercepting engine-side ProcessEvent calls — bypasses delegate binding entirely). |

### NUM_SIX — Pass 6 v2 RegisterHook discovery (E9)

**The first probe that runs after the Pass-5 pivot.** Pass 5's verdict (`prop:Add()` is a universal silent no-op for `MulticastInlineDelegateProperty` on this UE4SS build — see [`docs/learnings/ue4ss-multicast-delegate-add-silent-noop.md`](../../learnings/ue4ss-multicast-delegate-add-silent-noop.md)) ruled out delegate-binding as the substrate for ADR 0001 R-B. Pass 6 finds the engine-side UFunction that ADR 0001 R-B will hook instead.

#### Pass 6 v1 → v2 (2026-04-25)

v1 installed hooks on a NUM_SIX keypress, then asked the user to relog. **Bug:** the natural identity flow (`MeRequestV1Completed`) fires at *login* — before any user can press a key. v1's runs captured 0 fires for that reason. **Findings v1 still produced (substrate-positive):** `RegisterHook` registered cleanly on **all 79/79 UFunctions** of `PMPlayerModel` (44, sanity-confirms F3 iter 2's count) + `PMIdentitySubsystem` (35), with **zero failures**. That eliminates the "RegisterHook is restricted on `/Script/Prometheus`" failure mode entirely — the substrate question for the Pass-5 pivot is settled.

**v2 fix:** install at module load via `NotifyOnNewObject("/Script/Prometheus.PMPlayerModel", cb)` + `NotifyOnNewObject("/Script/Prometheus.PMIdentitySubsystem", cb)` — the maintainer-recommended pattern from UE4SS Issue #455 (also called out in ADR 0001 + the silent-noop learning). A `FindFirstOf` one-shot at load covers the case where instances already exist when Lua loads. NUM_SIX becomes a pure summary endpoint: dumps install state + per-UFunction fire counts + ambient PlayerId.

#### Why this is decisive

`RegisterHook` registration was already confirmed working on this UE4SS build (Pass-5 F6 successfully hooked our BP `OnMeResponseFired`; v1 confirmed it on 79/79 engine UFunctions). The remaining question is purely operational: **which engine UFunctions does the game actually call during natural identity flow?** And of those that fire, which have identity state populated at the time of the call (either as a parameter readable via `context[i+1]:get()` or via the existing `PMPlayerPublicProfile` walk)?

Mass-hooking everything (β methodology) and observing one cold-start login answers both questions in one pass. Single-target trial-and-error (α) would take up to N relogs; the cost difference is huge and the log volume is manageable (verbose for the first 3 fires per UFunction, then every 25th — same cap F4 uses).

#### Prerequisites

- The Pass 6 v2 install runs at script load — **no manual prerequisite**. Just deploy + restart the game.
- No `OSPlus.pak` rebuild, no editor work, no BP work — pure Lua. v2 also drops F6's `E3_MODACTOR` cached-actor prerequisite.

#### How to run

1. **Deploy** the updated `pass2_probes.lua`:
    ```powershell
    Copy-Item "C:\Users\T-Gamer\Documents\omega-strikers-overlay\docs\features\pass2-probes\pass2_probes.lua" "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\Mods\OSPlusProbes\Scripts\main.lua" -Force
    ```
2. **Quit + restart the game** (the install runs at Lua-mod load, so the script must be in place before launch).
3. **Log in normally.** Watch the log — at module load you should see a `[E9.boot]` block confirming `NotifyOnNewObject(PMPlayerModel) registered: true` and `NotifyOnNewObject(PMIdentitySubsystem) registered: true`. As the engine constructs the first instance of each class (typically very early in startup, before login completes), `[E9.boot] NotifyOnNewObject(...) fired` lines appear, immediately followed by the `[E9.A]` signature dump and `[E9.B]` `RegisterHook` ATTEMPT lines.
4. After main menu loads, **press NUM_SIX** to log the fire-count summary.
5. Grep:
    ```powershell
    Select-String -Path "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\OSPlusProbes.log" -Pattern "\[E9" | ForEach-Object { $_.Line }
    ```
6. (Per-fire detail beyond the summary) Each fire-time callback writes one `[E9.HOOK] #N <UFunctionName>` line plus per-parameter and ambient-PlayerId lines. The ordering matters — the *first* UFunction to fire post-login that carries identity state is the best ADR 0001 R-B target.

#### What to look for

- `[E9.boot] NotifyOnNewObject(PMPlayerModel) registered: true` — v2 install path is wired. If `false` (with err: ...), NotifyOnNewObject failed at module-load (probably package not yet loaded); the FindFirstOf one-shot at NUM_SIX press will catch it.
- `[E9.boot] NotifyOnNewObject(PMPlayerModel) fired: <FullName>` — engine constructed the instance. v2 install is now in flight on the game thread.
- `[E9.A] PMPlayerModel: 44 UFunction(s) enumerated` — sanity check against F3 iter 2's count + Pass 6 v1 confirm. If it differs, the game build's class shape changed.
- `[E9.A]   PMPlayerModel.<Name> flags=0x... NumParms=...` followed by `[E9.A]     [i] <ParamName> : <Type>` — full signature for each UFunction. **A UFunction whose param list contains `MeResponse` / `MeResponseV1` / `PlayerPublicProfile` is the highest-value target** — its parameter is the full identity payload.
- `[E9.B] >>> ATTEMPT RegisterHook /Script/Prometheus.PMPlayerModel:<Name>` — pre-call forensic marker. If a `RegisterHook` call native-crashes, the last on-disk line is this ATTEMPT (same pattern as F8/F1).
- `[E9.B]   FAILED: <Name> — <error>` — UE4SS rejected the hook for that UFunction. v1 produced 0 of these across 79 UFunctions; expect the same in v2.
- `[E9.B] total: N hooks installed across M UFunctions` — Phase B summary. **N==M is the happy path.** v1 confirmed 79/79.
- `[E9.HOOK] #G <Name> — fire #L for this UFunction (self=<FullName>)` — a hook fired. G is the global fire counter, L is the per-UFunction count, `self` confirms which instance the engine invoked the UFunction on.
- `[E9.HOOK]   <ParamName> = <value>` — parameter readback. Bool/Str/Int show their value; struct/userdata shows `<ud:'...'>` or full path. **A line like `MeResponse = <ud:...>` means we have the payload directly.**
- `[E9.HOOK]   ambient PlayerId=<24-char hex>` — `PMPlayerPublicProfile` walk found a populated PlayerId at fire time. **Non-nil here means identity is reachable via the existing flow even if the UFunction has no useful param.**
- `[E9]   N unique UFunctions have fired:` (after NUM_SIX press) — sorted summary. Top of the list = chattiest UFunction (probably gameplay-related, not identity); look for the *first* identity-shaped name in the list.

#### Decision impact

| Pass-6 result | Interpretation | ADR 0001 R-B implementation |
|---|---|---|
| ≥1 UFunction fires post-login + has a `MeResponse` / `PlayerPublicProfile`-shaped param the hook can read | **Best case.** Pick the earliest-fire UFunction with the richest payload. | Hook one UFunction; read identity from `context[i+1]:get()`. ~10 lines added to `mod/OSPlus/scripts/identity.lua`. Pure Lua. |
| ≥1 UFunction fires post-login but no useful param (just `self`) — ambient PlayerId is non-nil at fire time | **Signal-only path.** The hook is the *trigger*; identity readback uses the existing `findFriendlyNameByAccountId` walk in `identity.lua`. | Hook one UFunction; on fire, run existing identity resolution and emit the resolved-identity event. Still pure Lua. |
| ≥1 UFunction fires post-login, ambient PlayerId stays nil through all fires | Engine returns *before* it populates `PMPlayerPublicProfile`. Identity must be read elsewhere (param payload, `PlayerState.PlayerNamePrivate`, or `PMIdentitySubsystem.GetSteamId`). | Pick a UFunction that fires when identity *is* reachable (likely a later one in the call chain — e.g. `OnLoginComplete`-style hooks if they exist on PMIdentitySubsystem). Add a small poll-then-emit loop driven by the hook fire. |
| 0 UFunctions on `PMPlayerModel` fire post-login but ≥1 on `PMIdentitySubsystem` fires | Engine handles the response in C++ private methods on PMPlayerModel; PMIdentitySubsystem is the visible entry point. | Same shape as the previous rows but pick a PMIdentitySubsystem UFunction. |
| 0 UFunctions fire on either class | Engine bypasses public UFunctions entirely; everything is C++ private state mutation. | Pivot — likely UE4SS C++ mod (real engineering cost; separate ADR for the bridge), or accept M (manual relink) path with original Pass-2 cost. ADR 0001 needs revision. |
| `RegisterHook` errors / native-crashes on `/Script/Prometheus.PMPlayerModel:*` for some/all | UE4SS's `RegisterHook` is restricted on this engine's UFunctions. Per-UFunction `pcall` lets us continue and identify the unhookable subset. | Evaluate viability against the hookable subset; pivot if the hookable set doesn't include any identity-flow UFunction. |

#### What this probe does NOT do

- **No teardown.** UE4SS doesn't expose hook unregistration from Lua. Hooks survive process lifetime; restart the game between probe runs.
- **Doesn't distinguish pre vs post.** `RegisterHook(funcName, callback)` registers BOTH positions with the same callback (returns Pre, Post IDs that you could use to unregister selectively). So each natural call fires our callback twice. **2x counts are expected.** State readback on each fire reveals when identity becomes available — a pre-fire might show nil ambient PlayerId, a post-fire of the same UFunction might show the populated value.
- **Doesn't go cross-class.** Only `PMPlayerModel` + `PMIdentitySubsystem`. Other classes (`PMPlayerPublicProfile`, request handlers, etc.) aren't enumerated. Add them later if Pass 6 turns up nothing useful here.

### F5 — Pass 5 parallel exploration (PMPlayerModel property dump)

**Independent investigation — not on the critical path for ADR 0001's R-B validation.** Pass 4's deferred property-dump probe. If `PMPlayerModel` exposes identity-relevant data (PlayerId, DisplayName, MeResponse cache, etc.) as direct UProperties readable from Lua, we have a *second* path to identity that bypasses both the broken `GetCached*` UFunctions AND the (now-being-validated) delegate-binding path. Worth knowing about for both ADR 0001 (might simplify) and ADR 0002 (warm-cache fast-path).

#### How to run

1. Game running, post-login (same precondition as the others).
2. **Press F5 once.** Probe enumerates ALL properties on `PMPlayerModel` via `ForEachProperty`, reads each defensively via pcall, flags identity-relevant names (anything matching `playerid`, `displayname`, `response`, `profile`, `identity`, `linkcode`, `cached`, etc.) with `★`.
3. Grep:
    ```powershell
    Select-String -Path "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\OSPlusProbes.log" -Pattern "\[E4\]" | ForEach-Object { $_.Line }
    ```

#### What to look for

- `[E4]   <Name> ★ : <Type> = <Value>` — flagged property with a readable value. **A ★ row showing a 24-char hex `PlayerId` would be the prize.**
- `[E4] === total properties: N ===` — sanity check.
- `[E4] === N identity-relevant properties (★) ===` — focused summary.
- Anything reading as `<userdata>` is a struct/object — might still be useful but needs a follow-up read.

#### What it doesn't do

- Doesn't recurse into struct fields (e.g., a `MeResponse` UProperty would show as `<userdata>` — reading `.PlayerId` from it requires a follow-up).
- Doesn't try property-set / mutation. Read-only.
- Doesn't touch UFunctions — those are Pass 3's territory.

### F7 — Pass 5 micro-probe (Add validation level)

**Validates ADR 0001's step-2 BP-path viability.** Pass 4 confirmed via *introspection* that `prop:Add(UObject, FName-or-string)` is the right API shape (UE4SS docs + PR #1073), but never actually called it. Pass 5 calls it — and observes whether the engine validates the bound UFunction's name and/or signature at bind time.

The reason this matters for ADR 0001: the delegate's signature is `(Bool, Str, MeResponseV1, ErrorResponse)`, and `MeResponseV1`/`ErrorResponse` are `/Script/Prometheus` USTRUCTs that aren't visible to our UE editor. So we *can't* author a BP UFunction in our project with parameters of those exact types. Whether `Add` accepts a wrong-signature BP UFunction determines whether step 2 (BP work) is straightforward or structurally blocked.

#### How to run

1. Launch the game.
2. Wait until you're past the login splash (i.e. somewhere `PMPlayerModel` exists — main menu is fine).
3. **Press F7 once.** The probe runs E1 (bind nonexistent name); if E1 binds successfully, that's the answer and E2 is skipped. If E1 errors, E2 (bind real UFunction with truncated signature) runs automatically.
4. Each bind is immediately `Remove()`'d — nothing lingers for the rest of the session.
5. Grep the log:
    ```powershell
    Select-String -Path "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\OSPlusProbes.log" -Pattern "\[(E1|E2|Pass5)\]" | ForEach-Object { $_.Line }
    ```

#### Outcome decision matrix

| E1 (nonexistent) | E2 (wrong signature) | Outcome | Step-2 implication |
|---|---|---|---|
| **Accepts** | (skipped) | (a) `Add` is fully permissive | Build **any** BP UFunction on the OSPlus ModActor (e.g. `OnMeResponse(Succeeded: Bool)` — single param, easy). Bind. The remaining open question (does the engine actually invoke a wrong-shape UFunction at fire time?) is answered by step 2 itself. |
| **Rejects** | **Accepts** | (b) `Add` validates name only | Same as (a) — build a truncated-signature BP UFunction and bind. Same fire-time open question. |
| **Rejects** | **Rejects** | (c) `Add` validates name **and** signature | **BP-from-our-project structurally blocked.** ADR 0001 R-B path needs to pivot. Likely options: a UE4SS C++ mod that does the binding directly via the engine API (real cost — may be a separate ADR); or a way to expose `/Script/Prometheus` types to our editor (probably impossible without source access). |

#### What to look for in the log after F7

- `[E1]   BIND ACCEPTED ...` — outcome (a). E2 is skipped automatically. Move on to step 2 (BP work).
- `[E1]   BIND REJECTED ...` followed by `[E2]   BIND ACCEPTED ...` — outcome (b). Move on to step 2 with a truncated signature.
- `[E1]   BIND REJECTED ...` followed by `[E2]   BIND REJECTED ...` — outcome (c). Pause and we'll re-design the path.

The probe writes the same `>>> ATTEMPT` / `BIND ACCEPTED|REJECTED` pair structure as Pass 4, so a native crash on either `Add` would leave the ATTEMPT line on disk with no terminating line — same forensics flow as Pass 4. If that happens (we don't expect it; the API shape is web-confirmed), report the last on-disk line per the `If F8 crashes the game` flow above (substituting F7 for F8).

#### What this probe does NOT test

- **Fire-time behavior.** No `model:GetMeV1` trigger. Calling `GetMeV1` would invoke our wrong-shape binding via UE's `ProcessEvent`, which packs delegate args into a buffer at delegate-shaped offsets and reads them at the bound UFunction's offsets — a wrong-shape binding can read arbitrary memory. The fire-time test belongs in step 2, with a controlled BP UFunction whose memory layout we author and trust.
- **Whether the engine truncates / coerces / silently skips at fire time.** Even outcome (a) doesn't tell us whether the engine actually fires a wrong-shape UFunction. That's a separate question — and it's *much* more cheaply answered by adding a real BP UFunction in step 2 that flogs `print("FIRED")` than by speculating from this probe.

### B3 — redirect volume (manual)

No script. Play 2–3 practice matches, loosely count how often you redirect the puck, report a rough per-match range back. Feeds the `0002-profile-storage` ADR write-frequency axis.

---

## GUI object dumper (Pass 3 primary task)

UE4SS ships a built-in object dumper that writes every live UObject's class + property + UFunction list (with parameter metadata) to a large text file. **This is the primary Pass 3 deliverable** — the F9 probe above is a lighter same-session cross-check, but the dumper gives exhaustive ground truth.

### Run

1. Start the game, load into an **active match** (not menu; we want match-only objects in the dump).

2. Open the UE4SS GUI. The default toggle is often `Home` or the `ConsoleKey` configured in `UE4SS-settings.ini` — look for `[Debug]` or `[Keybinds]` section in that ini to confirm. On this install it's in the same directory as `UE4SS.log`: `Binaries\Win64\UE4SS-settings.ini`.

3. In the GUI, find the *Dumpers* tab (exact name varies by UE4SS version — may also be *Live View* or *Debug Tools*). Click **Dump all objects and properties** (or the closest-named button).

4. The dump is written next to `UE4SS.log`, typically named `ObjectDump.txt` or `UE4SS_ObjectDump.txt`. Expect a file in the **hundreds of MB** range for a fully-loaded match.

5. Close the GUI; the game continues running.

### Grep

Don't try to read the dump linearly. Grep for targeted patterns. PowerShell one-liners:

```powershell
$dump = "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\UE4SS_ObjectDump.txt"

# A3 UFunction signatures — the identity ADR's critical path:
Select-String -Path $dump -Pattern "GetCachedMeResponseV1|GetDisplayNameV1|GetCachedPlayerPublicProfile" -Context 0,12

# Ball/puck actor class — whatever the real name is:
Select-String -Path $dump -Pattern "Puck|Ball|Orb" -SimpleMatch:$false | Where-Object { $_.Line -match "Class /Script/Prometheus|BlueprintGeneratedClass.*Puck|BlueprintGeneratedClass.*Ball" }

# Every PM* class name (exhaustive inventory):
Select-String -Path $dump -Pattern "^\s*Class\s+/Script/Prometheus\." | ForEach-Object { $_.Line } | Sort-Object -Unique

# PlayerState_Game_C's block:
Select-String -Path $dump -Pattern "PlayerState_Game_C" -Context 0,200 | Select-Object -First 1
```

### Report back

Paste:

- The C1/C2/C3 log lines (grep below).
- The three UFunction signature blocks from the dumper grep.
- The ball actor class name (if the `Puck|Ball|Orb` grep found something plausible).
- The exhaustive `PM*` class list (truncated if huge).
- `PlayerState_Game_C` block (or a summary of redirect-shaped properties/UFunctions if you pre-filter it).

If the `Puck|Ball|Orb` grep returns nothing recognizable, report that too — it's evidence the naming convention is different (e.g., the ball might be an `Actor_Puck_01` or similar).

---

## Report output

For each probe, paste back:

1. **Which context** you ran it from (menu / char-select / in-match / post-match / awakening).
2. The `[A*]`, `[B*]`, `[C*]`, `[D*]`, `[E*]`, `[Pass2]`, `[Pass3]`, `[Pass4]`, `[Pass5]` lines from `UE4SS.log` (or `OSPlusProbes.log` for Pass-4/Pass-5 forensics — that file is the survivor across crashes). Easiest: grep the log in PowerShell:

    ```powershell
    Select-String -Path "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\OSPlusProbes.log" -Pattern "\[(A1|A2|A3|B1|B2|C1|C2|C3|D1|D2|E1|E2|E3|E3\.HOOK|E4|E5|E6|E7|E7\.A|E7\.B|E7\.C|E8|E8\.A|E8\.B|E8\.C|E8\.D|E9|E9\.A|E9\.B|E9\.HOOK|Pass2|Pass3|Pass4|Pass5|Pass6|OSPlusProbes)\]" | ForEach-Object { $_.Line }
    ```

If one probe errors in a way the defensive `pcall`s don't catch, paste the stack trace — that's also useful data.

---

## Uninstall

When all four passes are complete and the spike findings have landed in `docs/learnings/`:

1. Delete `<GameDir>\Binaries\Win64\Mods\OSPlusProbes\` (entire folder).
2. Remove the `OSPlusProbes : 1` line from `Mods\mods.txt`.
3. Restart the game.

---

## Design notes for the future reader

- **Separate mod, not OSPlus:** keeps investigation tooling out of the shipping mod entirely. No `require()` from `OSPlus/main.lua`, no config flag, no commit against `mod/OSPlus/scripts/`. The probe mod dies when feasibility ends and leaves no trace in the OSPlus code.
- **Four keybinds, one mod:** F11 = Pass 2 battery (per-context one-shots), F12 = Pass 2 A2 poll (temporal sampling, one context), F9 = Pass 3 battery (in-match deep introspection), F8 = Pass 4 spike (delegate-binding + cache-fetch validation). One key per interaction shape beats a single do-everything dispatch.
- **`LoopAsync` over `LoopInGameThreadWithDelay`:** `LoopAsync` is marked deprecated in the UE4SS Lua reference, but it's what the shipped `OSPlus/main.lua` uses successfully for its 30ms tick loop. Using a known-working API for one-off investigation tooling beats switching to the recommended API mid-session.
- **All probes `pcall`-wrapped:** UE4SS access to missing / freed UObjects is a native crash path (not a Lua error). `pcall` catches Lua-level errors but not C++ access violations, so probes additionally gate every UObject access behind `:IsValid()` checks. If a probe still native-crashes the game, that IS the finding — note which one and in which context.
- **Pass 3 complements the GUI dumper, not replaces it:** `F9` introspects Lua-reachable state during a live match; the dumper captures everything. If C2 fails (`ForEachProperty` not available on UFunction), the dumper is a guaranteed fallback. If both succeed they cross-validate.
- **`iterUObjectArrayProp` tries multiple TArray access patterns:** UE4SS's TArray Lua binding shape varies by build. The helper tries `:GetArrayNum()` + `[i]` first, then `:ForEach(cb)`, then reports failure. This is investigation code's equivalent of graceful degradation — we'd rather learn which access pattern worked than have a single-API probe fail opaquely.
- **Pass 4 tries multiple binding APIs in sequence:** the UE4SS Lua API for binding to `MulticastInlineDelegateProperty` isn't documented in the OSPlus knowledge base — this spike's *primary deliverable* is discovering which shape works. Each attempt is `pcall`-wrapped so Lua-level errors don't crash the next attempt. The same graceful-degradation principle as `iterUObjectArrayProp` — but with one critical difference: see next note.
- **Pass 4 logs every step BEFORE the call AND to a persistent file:** because `pcall` does not catch native C++ access violations on UE objects, a binding attempt that natively crashes leaves no Lua-side trace. The `flog()` helper writes to both `print()` (UE4SS.log live view) AND `OSPlusProbes.log` (`io.open + flush` per call) — UE4SS owns the former and overwrites it on every launch (including the post-crash `CrashReportClient.exe` attach session, which destroys the pre-crash entries); the latter is our file and survives. Two layers of defense are needed because `pcall`-wrapping alone is insufficient for spike code that pokes at undocumented UE4SS APIs.
- **Pass 4 is keybind-only — no script-load auto-binding:** an earlier revision tried to auto-bind from a `LoopAsync` at script load to catch the natural login fire. It crashed the game during startup before any diagnostic could be captured. For investigation code touching unfamiliar UE APIs, the user must control *when* the risky call happens; otherwise a single bad binding attempt becomes a launch-time crash with zero forensic value.
- **D1 is broken into numbered steps, not a loop over attempts:** earlier revisions iterated `{prop:Add, prop:Bind}` in a `for` loop. Cleaner code, but if the property *access* is the killer rather than a binding method, the loop body never runs and the log doesn't distinguish "property access died" from "first attempt died". Numbered steps (`step 1` = property access, `step 2` = `:Add`, `step 3` = `:Bind`) each get their own `flog` line so the killer is unambiguous.
