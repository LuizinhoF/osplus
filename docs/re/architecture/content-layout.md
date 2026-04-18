---
id: 0001-content-layout
title: Game content layout and pak strategy
status: confirmed
last-verified: 2026-04-04
sources:
  - data/re/raw/pak-inventory/CustomPings_P.list.txt
  - data/re/raw/pak-inventory/CustomPings_P.info.txt
  - data/re/raw/pak-inventory/OmegaStrikers-Windows.list.txt
  - mod/OSPlus/scripts/chat.lua#L26
  - mod/OSPlus/scripts/config.lua#L37
  - mod/OSPlus/scripts/assets.lua#L123
tags: [pak, asset-loading, mod-architecture, prometheus]
related: []
---

# Game content layout and pak strategy

> **Scope:** how Omega Strikers organises its shipped content, how mod paks layer on top, and what's safe vs not safe to remove from a player's install.
> **Purpose:** informs OSPlus pak naming, asset path conventions, and install/uninstall hygiene in the distribution installer.

---

## Executive Summary

Omega Strikers ships **two paks** in `Content/Paks/`: a 21 GB main pak (`OmegaStrikers-Windows.pak`, 64,213 files) and a small 4 MB patch pak (`CustomPings_P.pak`, 49 files). The internal project codename is **Prometheus** — every cooked path begins `OmegaStrikers/Content/...` but the editor project itself is named "Prometheus" (visible in path traces). The game uses **Wwise** for audio, **UE 5.1**, and pak format **V11 / Fnv64BugFix** with no encryption — meaning we can fully inventory and statically analyse everything Riot ships without bypassing protection.

`CustomPings_P.pak` is **not a game file**. It's a leftover from this project's pre-OSPlus prototype phase — three iteration drafts of a chat widget plus a custom ping system. Nothing in the current OSPlus codebase loads any asset from it. It's 4 MB of orphaned mod content sitting in players' installs, and the OSPlus installer should clean it up.

Mod content reaches the running game via two paths today, and we should converge on one.

---

## Findings

### 1. The shipped game uses two paks

From `data/re/raw/pak-inventory/OmegaStrikers-Windows.info.txt` and `CustomPings_P.info.txt`:

| Pak | Size | Files | Mount | Notes |
|---|---|---|---|---|
| `OmegaStrikers-Windows.pak` | ~21 GB | 64,213 | `../../../OmegaStrikers/Content/` | Main shipping pak. Compressed. Encryption GUID is zero (= unencrypted). |
| `CustomPings_P.pak` | ~4 MB | 49 | `../../../OmegaStrikers/Content/CustomPings/` | `_P` patch pak. Overlays into the `CustomPings/` content root. **Not a game file.** See finding 2. |

Both paks are V11 / Fnv64BugFix, the standard UE 5.1 format. The unencrypted index means `repak list/unpack` works on every file without keys.

### 2. `CustomPings_P.pak` is leftover OSPlus prototype work

The 49 entries in `data/re/raw/pak-inventory/CustomPings_P.list.txt` decompose into three groups, all clearly authored:

**Three chat widget iterations** (visible draft history):
```
OmegaStrikers/Content/CustomPings/UI/WBP_Chat.uasset
OmegaStrikers/Content/CustomPings/UI/WBP_Chat2.uasset
OmegaStrikers/Content/CustomPings/UI/WBP_Chat_Nofunc.uasset
```

**A disabled ping system** (widgets, marker BP, sprite materials, sound):
```
OmegaStrikers/Content/CustomPings/UI/WBP_PingWheel.uasset
OmegaStrikers/Content/CustomPings/VFX/BP_PingMarker.uasset
OmegaStrikers/Content/CustomPings/VFX/MI_PingSprite_{Generic,Danger,Assist,OMW,Retreat,Awaken}.uasset
OmegaStrikers/Content/CustomPings/SFX/SFX_Danger.uasset
```

**One scratch asset:** `Test.uasset`.

Confirmation that this is ours, not the game's:
- `rg CustomPings data/re/raw/pak-inventory/OmegaStrikers-Windows.list.txt` returns zero matches. The shipping game has no `CustomPings/` content root.
- The asset names (`WBP_Chat`, `MI_PingSprite_Danger`, `SFX_Danger`) match the literal strings used in OSPlus Lua: `mod/OSPlus/scripts/config.lua#L37` lists every `MI_PingSprite_*` material as a constant.

### 3. Nothing in the live OSPlus code path actually loads from CustomPings

The active chat widget is found at runtime by class name, **not** by `CustomPings/` asset path:

```lua
-- mod/OSPlus/scripts/chat.lua#L26
local ok, w = pcall(FindFirstOf, "WBP_ModChat_C")
```

`WBP_ModChat` is a different asset entirely, cooked into `OmegaStrikersMod.pak` under `LogicMods/` and instantiated by the mod's BP-side `ModActor`. It is **not** any of the three `WBP_Chat*` variants in `CustomPings_P.pak`.

The remaining `/Game/CustomPings/...` references in OSPlus Lua are all inside the disabled ping subsystem:

| Reference | File | Live? |
|---|---|---|
| `MI_PingSprite_*` paths | `mod/OSPlus/scripts/config.lua#L37-42` | No — only read by `pings.lua`, which is not registered. |
| `SFX_Danger` path | `mod/OSPlus/scripts/config.lua#L46` | No — same as above. |
| `BP_PingMarker` load | `mod/OSPlus/scripts/assets.lua#L123` | No — `assets.lua` is `require`d only by the disabled ping module. |
| `WBP_PingWheel` load | `mod/OSPlus/scripts/assets.lua#L150` | No — same as above. |

**Conclusion:** removing `CustomPings_P.pak` from a player's install will not break OSPlus. It is dead weight.

### 4. Mod content reaches the game via two pak paths today

We are currently using both UE pak loading mechanisms simultaneously:

| Path | Loader | Where pak goes | Asset path convention | Used by |
|---|---|---|---|---|
| **Native UE patch pak** | UE pak system (built-in) | `Content/Paks/<Name>_P.pak` | Mounts at the path declared in `info.txt` (e.g. `Content/CustomPings/`) | Old `CustomPings_P.pak` (now dead) |
| **BPModLoaderMod** | UE4SS BPModLoaderMod (Lua-side mod) | `Content/Paks/LogicMods/<Name>.pak` | Mounts under `Content/Mods/<ModName>/` | Current `OmegaStrikersMod.pak` (the live one) |

These coexist without conflict only because their mount points don't overlap. They are otherwise different mechanisms with different lifecycles, different debugging stories, and different load order guarantees.

### 5. Codename "Prometheus" is the editor-side project name

UE asset full-paths surfaced via UE4SS reflection (and visible in `data/re/raw/pak-inventory/OmegaStrikers-Windows.info.txt` mount-point traces) reference the path component `Prometheus`. This is the **editor-side `.uproject` name** Riot used internally; cooking renamed the runtime root to `OmegaStrikers/`. It only matters when reading external community RE that references "Prometheus" — it's the same game.

---

## Implications for OSPlus

1. **Converge on the LogicMods path.** All future mod paks ship to `Content/Paks/LogicMods/` with mount root `/Game/Mods/OSPlus/...`. Native patch paks (`_P.pak`) are off the table — they bypass BPModLoaderMod, fight load order, and produced this exact orphan-pak problem. The "One mod, one pak" decision (Option A from earlier discussion) holds.

2. **The installer must remove `CustomPings_P.pak`.** Add to the migration block in `dist/install.bat`:
   ```batch
   if exist "%PAKS_DIR%\CustomPings_P.pak" (
       echo Removing legacy CustomPings_P.pak (orphaned prototype mod)...
       del /f /q "%PAKS_DIR%\CustomPings_P.pak"
   )
   ```
   This is alongside the existing `OmegaStrikersMod.pak` cleanup. Document in the installer README that this file is safe to delete and not a game file.

3. **Standard asset paths under `/Game/Mods/OSPlus/`.** The UE project restructure (forthcoming) cooks every mod asset under `Content/Mods/OSPlus/<Feature>/...` so the runtime path is `/Game/Mods/OSPlus/<Feature>/...`. Inside the mod folder, **co-locate by feature, not by asset type** — see the upcoming UE-restructure decision doc.

4. **Static analysis is unblocked.** No encryption, format V11, `repak` and `UAssetGUI` both installed under `tools/_bin/`. We can inventory and unpack any shipping asset for RE without runtime instrumentation.

5. **Watch for "Prometheus" in external RE.** Community RE (UE4SS Discord, modding forums) may use the editor-side codename. Treat `Prometheus` and `OmegaStrikers` as aliases when searching.

---

## Verification

**Reproduce the pak inventory:**
```powershell
.\tools\setup\extract_game_paks.ps1
# Writes data/re/raw/pak-inventory/<pak>.list.txt and <pak>.info.txt
```

**Re-verify CustomPings_P.pak is unreferenced by live code:**
```powershell
rg "CustomPings" mod\OSPlus\scripts\
# Should return only matches inside config.lua (constants) and assets.lua
# (ping-system loaders), both consumed only by the disabled pings.lua.
```

**Empirical no-break test (recommended once before shipping the installer change):**
1. Move `F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Content\Paks\CustomPings_P.pak` outside the Paks folder.
2. Launch the game with OSPlus installed.
3. Confirm chat opens, sends, receives, and clears between matches.
4. If green, the installer change in implication 2 is safe to ship.

**Re-verify after:** any game patch, or any time we re-enable the ping system.

---

## Remaining Unknowns

| Question | Impact | How to Resolve |
|---|---|---|
| Does `OmegaStrikersMod.pak` (LogicMods/) hold any internal hard reference to `/Game/CustomPings/...`? | If yes, deleting `CustomPings_P.pak` would break the live mod despite the Lua analysis. | Extract `OmegaStrikersMod.pak` with `repak unpack`, run `UAssetGUI tojson` on `WBP_ModChat.uasset` and `BP_ModActor.uasset`, grep the resulting JSON for `CustomPings`. |
| What's the cooked load order between `LogicMods/*.pak` and `Paks/*_P.pak`? | Determines whether two paks can ever shadow each other's assets. | Hook `IPakFile::Mount` via UE4SS `RegisterHook` and log mount order during startup. Findings folder: `lifecycle/`. |
| Are there other orphan paks from older prototypes anywhere in `Content/Paks/`? | Same hygiene story as `CustomPings_P.pak`. | `dir /s /b Content\Paks\*.pak` and cross-check filenames against `mod/` git history. |
| Does the shipping game itself ever load any `_P` patch pak? | Determines whether our installer can safely refuse to load any non-LogicMods pak it didn't ship. | Inventory the game install on a fresh machine before any modding. |
