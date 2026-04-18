# UE Project Migration: OmegaStrikersMod → OSPlus

When the project was renamed from `OmegaStrikersTest` to `OSPlus`, all code, scripts, install paths, and runtime data dirs were updated automatically. The asset folder *inside the UE editor project* was not — it can only be moved in the Unreal Editor, then re-cooked.

This doc is the concrete plan for that one-time migration **plus** the cleanup of dead prototype content discovered during reverse-engineering. After this migration, the cooked pak structure becomes the long-term layout the mod platform builds on.

---

## Why now

The current pak (`OSPlus.pak`) cooks fine and the mod runs. We could defer this forever and nothing would break. But:

1. **One-mod-one-pak architecture (decided).** OSPlus is the mod platform; everything we ship goes inside `/Game/Mods/OSPlus/`. Locking in that mount path now means every future feature lands in the right place from day one.
2. **Dead prototype content is being cooked.** `Content/CustomPings/` (35 assets — old chat drafts, the disabled ping system, scratch files) is still in the editor project and still gets cooked into a separate `CustomPings_P.pak`. See [`docs/re/architecture/content-layout.md`](re/architecture/content-layout.md). Removing it shrinks the cook, deletes 4 MB of useless content from every player's install, and stops accidental re-references.
3. **Feature folders need to be set up.** When we add the second feature (Profile, Friends, whatever), it needs a folder convention to land in. Easiest to define that pattern now with one feature than during the rush of building the second.

---

## Constraint we have to respect

**`ModActor` is a magic name.** From `KNOWLEDGEBASE.md` line 617:

> BPModLoaderMod creates a config for each pak: `AssetPath = /Game/Mods/<ModName>/ModActor`, `AssetName = ModActor_C`

This means:

- The asset **must** be named `ModActor` (not `BP_OSPlusActor` or anything else).
- The asset **must** live directly under `/Game/Mods/OSPlus/` (not in any subfolder).
- `<ModName>` is derived from the pak filename, so `OSPlus.pak` → mount root `/Game/Mods/OSPlus/`.

Feature widgets (`WBP_ModChat`, future widgets, etc.) are loaded by `ModActor`'s BeginPlay graph using BP class references, not by BPModLoaderMod. **They can live in subfolders.** UE Editor's "Move Asset" dialog updates the BP references automatically when you do the move through the editor.

---

## Target layout

```
Content/
└── Mods/
    └── OSPlus/                         ← mount root, must match pak filename
        ├── ModActor.uasset             ← MUST stay here, MUST stay named ModActor
        ├── _Shared/                    ← reserved for cross-feature assets
        │       (empty for now)         ← future: shared widgets, data tables, base classes
        └── Chat/
            └── WBP_ModChat.uasset      ← keep current name (avoids Lua change at chat.lua#L26)
```

After we add features, the same pattern:

```
        ├── Chat/
        │   └── WBP_ModChat.uasset
        ├── Profile/
        │   ├── WBP_ProfileMenu.uasset
        │   └── DT_UnlockCatalog.uasset
        ├── Friends/
        │   └── WBP_FriendsList.uasset
        └── _Shared/
            └── WBP_BaseModal.uasset
```

One folder per feature. Cross-feature assets (base widget classes, shared data tables, the `_Shared/` orchestration utilities `ModActor` reaches for) go in `_Shared/`.

---

## Current state (what we're migrating from)

Inventoried 2026-04-04:

| Path in editor project | What it is | Action |
|---|---|---|
| `Content/Mods/OmegaStrikersMod/ModActor.uasset` | Live orchestrator BP | **Move** with the folder rename → `Content/Mods/OSPlus/ModActor.uasset` |
| `Content/Mods/OmegaStrikersMod/WBP_ModChat.uasset` | Live chat widget | **Move into subfolder** → `Content/Mods/OSPlus/Chat/WBP_ModChat.uasset` |
| `Content/CustomPings/` (35 assets) | Old chat drafts + disabled ping system + scratch | **Delete entirely** (zero live references — see [content-layout.md](re/architecture/content-layout.md)) |
| `Content/Dump/WBP_Chat.uasset` | Yet another orphan chat draft | **Delete** |
| `Content/Developers/TGamer/` | Per-developer scratch (UE editor convention) | Leave alone |
| `Content/Collections/`, `Content/__External*__/` | UE editor metadata | Leave alone |
| `Content/StarterContent/` | UE template starter content (large, unused) | Optional cleanup — separate concern, not required for this migration |

---

## Migration steps

### 1. Rename the mod folder

In the UE Editor (open `F:\Omegamod\OmegaStonkers 5.1\OmegaStonkers.uproject`):

1. Content Browser → navigate to `Content/Mods/`
2. Right-click `OmegaStrikersMod` → **Rename** → `OSPlus`
3. UE asks "Found references in N assets. Fix up references?" → **Yes to all**

This single rename moves both `ModActor.uasset` and `WBP_ModChat.uasset` together and updates `ModActor`'s internal reference to `WBP_ModChat`.

### 2. Create the feature subfolders and move the chat widget

1. Content Browser → navigate to `Content/Mods/OSPlus/`
2. Right-click empty area → **New Folder** → `Chat`
3. Right-click empty area again → **New Folder** → `_Shared` (placeholder for future)
4. Drag `WBP_ModChat.uasset` from `OSPlus/` into `OSPlus/Chat/`
5. UE asks about reference fixup → **Yes to all**
6. After `WBP_ModChat` is moved, the only thing left at `OSPlus/` root should be `ModActor.uasset`

### 3. Delete the dead content folders

1. Content Browser → right-click `Content/CustomPings/` → **Delete**
2. UE will scan for references — should report **0 references**. Confirm delete.
3. Same for `Content/Dump/`.
4. If UE reports any unexpected references, **stop** and investigate before deleting (see "Verification" below).

### 4. Save and fix up redirectors

1. `File → Save All` (or `Ctrl+S` in the Content Browser with everything dirty)
2. Right-click `Content/Mods/OSPlus/` → **Fix Up Redirectors in Folder**
3. This eliminates the redirector ghost-files UE created during the moves so the cooked pak is clean.

### 5. Update the pak builder script

In `ue-assets/package_logicmod.ps1`, change three literal strings — all currently say `OmegaStrikersMod`:

```powershell
$COOKED_DIR = "F:\Omegamod\OmegaStonkers 5.1\Saved\Cooked\Windows\OmegaStonkers\Content\Mods\OSPlus"
```

```powershell
$mountPath = "../../../OmegaStrikers/Content/Mods/OSPlus/$relativePath"
```

```powershell
Write-Host "Assets mount at /Game/Mods/OSPlus/" -ForegroundColor Cyan
```

The script already uses `Get-ChildItem -Recurse` and computes `$relativePath` from the cooked dir, so the new `Chat/` subfolder is picked up automatically. **No structural changes needed** beyond the three literal renames.

### 6. Cook + repack + verify

```powershell
# In the UE Editor:
File → Cook Content for Windows

# Verify the cook output:
dir "F:\Omegamod\OmegaStonkers 5.1\Saved\Cooked\Windows\OmegaStonkers\Content\Mods\OSPlus"
# Expected:
#   ModActor.uasset (and .uexp)
#   Chat\WBP_ModChat.uasset (and .uexp)
#   _Shared\  (empty or absent — empty folders may not cook)

# Repackage:
cd c:\Users\T-Gamer\Documents\omega-strikers-overlay
.\ue-assets\package_logicmod.ps1
```

The pak builder writes directly to your game's `LogicMods/OSPlus.pak`. Launch the game. UE4SS console should show:

```
[BPModLoaderMod] Loading mod: /Game/Mods/OSPlus/ModActor.ModActor_C
[BPModLoaderMod] Actor: ModActor_C ...
```

(Both lines `OSPlus`, no more `OmegaStrikersMod`.)

### 7. Optional: cleanup the legacy fallback

After step 6 succeeds, the fallback in `build_dist.ps1` for `OmegaStrikersMod.pak` is dead code. You can remove the `$PAK_LEGACY` block if you want, or leave it as a safety net for one more release cycle.

---

## Verification

**Before starting** — confirm no surprise references to the dead folders:

```powershell
# Should return matches only inside config.lua (constants) and assets.lua (disabled ping system loaders).
# Both consumed only by mod/OSPlus/scripts/pings.lua, which is not registered.
rg "CustomPings" c:\Users\T-Gamer\Documents\omega-strikers-overlay\mod
```

**During the deletes** — UE Editor will refuse to delete an asset with live references. If it warns, the dead-content claim is wrong for that asset; investigate before continuing.

**After re-cook** — the new pak should contain exactly:
```
OSPlus/ModActor.uasset (+ .uexp)
OSPlus/Chat/WBP_ModChat.uasset (+ .uexp)
```

You can verify with:
```powershell
.\tools\_bin\repak\repak.exe list "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Content\Paks\LogicMods\OSPlus.pak"
```

Optionally re-run the inventory to confirm `CustomPings_P.pak` is gone from the player install:
```powershell
.\tools\setup\extract_game_paks.ps1
# Expected: only OmegaStrikers-Windows.pak (the game) and OSPlus.pak (our mod) listed.
```

---

## What we are NOT doing

- **Not renaming `ModActor`** — BPModLoaderMod hardcodes the name. See "Constraint" above.
- **Not renaming `WBP_ModChat`** — `mod/OSPlus/scripts/chat.lua#L26` calls `FindFirstOf("WBP_ModChat_C")`. Renaming the widget would mean changing the Lua side too, with no benefit beyond cosmetics. The current name is fine.
- **Not writing a UE Python script for this migration** — only 2 assets to move + 36 to delete. UE Editor's right-click handles it in 60 seconds with proper redirector fixup. The Python plugins are now enabled (see `tools/setup/enable_ue_plugins.ps1`) and we'll write `tools/ue/restructure_mod.py` when we have a real bulk-rename problem to solve (the second feature add, probably).

---

## If you skip this migration

The current mod keeps working. The trade-offs:

- Cooked pak structure says `OmegaStrikersMod` while everything else says `OSPlus` — naming inconsistency in logs.
- `CustomPings_P.pak` keeps shipping to your players. They'll never notice but it's 4 MB of dead code in their install.
- Future features have to either re-do this migration or pile into the legacy `OmegaStrikersMod` folder, which would be a worse decision than fixing it now.

Recommendation: do steps 1–6 in one focused 15-minute editor session.
