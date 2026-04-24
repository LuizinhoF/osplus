# Pass 2 probes — `OSPlusProbes` mod

Runtime scripts for Feasibility Pass 2 of [`in-game-profile-mvp`](../in-game-profile-mvp.md). **NOT shipped with OSPlus.** Install as a separate UE4SS mod, run the probes, then uninstall. The `OSPlus` mod is never modified by this work.

Scope of what the probes resolve: assumptions 1, 2, 3 (identity) and capture-surface tasks 4, 5 — see the feature doc for the full verdict criteria. Probe B3 (redirect volume sizing) is a manual observation, no script.

---

## Install

1. Create the mod directory in the game install:

    ```
    <GameDir>\OmegaStrikers\Binaries\Win64\ue4ss\Mods\OSPlusProbes\scripts\
    ```

    For this machine: `F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\ue4ss\Mods\OSPlusProbes\scripts\`.

2. Copy `pass2_probes.lua` (this folder) to that directory, renaming it to `main.lua`:

    PowerShell one-liner (adjust source path if you cloned the repo elsewhere):

    ```powershell
    $src = "C:\Users\T-Gamer\Documents\omega-strikers-overlay\docs\features\pass2-probes\pass2_probes.lua"
    $dst = "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\ue4ss\Mods\OSPlusProbes\scripts\main.lua"
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    Copy-Item $src $dst -Force
    ```

3. Create `enabled.txt` with contents `1` in the mod root:

    ```powershell
    Set-Content "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\ue4ss\Mods\OSPlusProbes\enabled.txt" "1"
    ```

4. Add `OSPlusProbes : 1` to `Mods\mods.txt` (next to `OSPlus : 1`). Any text editor; no reorder needed.

5. Restart the game fully (UE4SS only loads Lua mods once, at process start).

On successful load you'll see this in `Binaries\Win64\ue4ss\UE4SS.log`:

```
[Lua] [OSPlusProbes] loaded. F11 = A1+A3+B1+B2 battery, F12 = A2 poll (15s)
```

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

### B3 — redirect volume (manual)

No script. Play 2–3 practice matches, loosely count how often you redirect the puck, report a rough per-match range back. Feeds the `0002-profile-storage` ADR write-frequency axis.

---

## Report output

For each probe, paste back:

1. **Which context** you ran it from (menu / char-select / in-match / post-match).
2. The `[A1]`, `[A2]`, `[A3]`, `[B1]`, `[B2]` lines from `UE4SS.log`. Easiest: grep the log in PowerShell:

    ```powershell
    Select-String -Path "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\ue4ss\UE4SS.log" -Pattern "\[(A1|A2|A3|B1|B2|Pass2)\]" | ForEach-Object { $_.Line }
    ```

If one probe errors in a way the defensive `pcall`s don't catch, paste the stack trace — that's also useful data.

---

## Uninstall

When Pass 2 is complete:

1. Delete `<GameDir>\Binaries\Win64\ue4ss\Mods\OSPlusProbes\` (entire folder).
2. Remove the `OSPlusProbes : 1` line from `Mods\mods.txt`.
3. Restart the game.

---

## Design notes for the future reader

- **Separate mod, not OSPlus:** keeps investigation tooling out of the shipping mod entirely. No `require()` from `OSPlus/main.lua`, no config flag, no commit against `mod/OSPlus/scripts/`. The probe mod dies when Pass 2 ends and leaves no trace in the OSPlus code.
- **Two keybinds, not one:** the probes split naturally into one-shots (A1, A3, B1, B2) that want *per-context* runs, and A2 which wants *temporal sampling*. One key per mode; more expressive than a single dispatch and less typing than five keys.
- **`LoopAsync` over `LoopInGameThreadWithDelay`:** `LoopAsync` is marked deprecated in the UE4SS Lua reference, but it's what the shipped `OSPlus/main.lua` uses successfully for its 30ms tick loop. Using a known-working API for one-off investigation tooling beats switching to the recommended API mid-session.
- **All probes `pcall`-wrapped:** UE4SS access to missing / freed UObjects is a native crash path (not a Lua error). `pcall` catches Lua-level errors but not C++ access violations, so probes additionally gate every UObject access behind `:IsValid()` checks. If a probe still native-crashes the game, that IS the finding — note which one and in which context.
