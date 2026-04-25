# Pass 2 + Pass 3 + Pass 4 probes — `OSPlusProbes` mod

Runtime scripts for Feasibility Passes 2, 3, and 4 of [`in-game-profile-mvp`](../in-game-profile-mvp.md). **NOT shipped with OSPlus.** Install as a separate UE4SS mod, run the probes, then uninstall. The `OSPlus` mod is never modified by this work.

> **STATUS (2026-04-25): Pass 2, Pass 3, and Pass 4 are all COMPLETE.** ADR 0001 is `accepted` on the R-B path with revised cold-start posture (Path A: ModActor BP wrapper for delegate binding; warm-cache UFunction pre-check dropped). Pass 4's findings live in `docs/learnings/ue4ss-lua-multicast-delegate-binding.md` and `docs/learnings/ue4ss-outparam-marshaling-failure.md`; the F8 sections below preserve the operational record but are retrospective. **The probe mod is intentionally left installed** for the next deferred spike — a property-dump probe on `PMPlayerModel` looking for direct UProperty cache fields as a future cheap warm-start path (see `docs/features/in-game-profile-mvp.md` Open Questions). Uninstall once that follow-up either lands or is explicitly dropped from the roadmap.

Scope:

- **Pass 2** — resolved by `F11` (battery: A1+A3+B1+B2) and `F12` (A2 poll). Done 2026-04-24; see the feature doc's `### Pass 2 findings` section.
- **Pass 3** — `F9` (battery: C1+C2+C3) resolves the UFunction signatures (critical path for `0001-identity-model`) and pushes into the capture-surface hypothesis space (components / replicated PlayerState). Best paired with a **UE4SS GUI object dumper** run (primary Pass 3 task — see below).
- **Pass 4** — `F8` (battery: D1+D2). **Done 2026-04-25.** D1 (delegate substrate) viable with ModActor BP wrapper; D2 (sync cache pre-check) unreachable in this UE4SS build. ADR 0001 accepted on Path A. See the `### F8 — Pass 4 spike` section below for the four-revision crash-forensics history that produced the two learnings.
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

On successful load you'll see this in `Binaries\Win64\UE4SS.log`:

```
[Lua] [OSPlusProbes] loaded. F11 = Pass2 battery, F12 = A2 poll (15s), F9 = Pass3 battery (C1+C2+C3), F8 = Pass4 spike (D2 then D1; KEYBIND-ONLY, no auto-bind)
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
2. The `[A*]`, `[B*]`, `[C*]`, `[D*]`, `[Pass2]`, `[Pass3]`, `[Pass4]` lines from `UE4SS.log`. Easiest: grep the log in PowerShell:

    ```powershell
    Select-String -Path "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\UE4SS.log" -Pattern "\[(A1|A2|A3|B1|B2|C1|C2|C3|D1|D2|Pass2|Pass3|Pass4|OSPlusProbes)\]" | ForEach-Object { $_.Line }
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
