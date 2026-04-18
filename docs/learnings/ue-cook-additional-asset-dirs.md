# ue-cook-additional-asset-dirs

| Field | Value |
|---|---|
| Date | 2026-04-04 |
| Area | ue-editor |
| Tags | ue5, cooking, packaging, mods, project-settings, empty-cook |
| Status | confirmed |

## Symptom

After running `File → Cook Content for Windows` in the UE editor, `ue-assets/package_logicmod.ps1` failed with:

```
Cooked content not found:
  F:\Omegamod\OmegaStonkers 5.1\Saved\Cooked\Windows\OmegaStonkers\Content\Mods\OSPlus
(cook the project first)
```

The cook itself reported success. The cooked output directory existed but contained nothing under `Content/Mods/OSPlus/`.

## Root cause

UE5's "Cook Content for Windows" only cooks assets that are **reachable from a cooked map** by default. The cooker walks the asset graph starting from each map listed under *Project Settings → Packaging → Maps & Modes → List of maps to include in a packaged build*, and any asset not reachable from those maps gets skipped.

Mod assets (`/Game/Mods/OSPlus/`) are not referenced by any of the project's maps — by design, since they're loaded at runtime via BPModLoaderMod, not via a level reference. So the cooker silently skipped them. There's no "I cooked nothing for this directory" warning unless you specifically check the cooked output structure.

## Fix

Add `/Game/Mods/OSPlus` to *Project Settings → Packaging → **Additional Asset Directories to Cook***. The cooker will then treat that path as a root and cook every asset under it regardless of map reachability.

After the setting change, re-cook (`File → Cook Content for Windows`). Cooked output now correctly populates `…\Saved\Cooked\Windows\OmegaStonkers\Content\Mods\OSPlus\`. `package_logicmod.ps1` then succeeds.

## Lesson

- **A "successful" cook with no errors does not mean every asset you wanted cooked was cooked.** UE5 cooks by reachability from registered maps; non-map-referenced asset trees need explicit registration.
- **For mod projects specifically, *Additional Asset Directories to Cook* is mandatory** — your mod root is the entry point, not a map.
- This is an `.ini` setting (`+DirectoriesToAlwaysCook=(Path="/Game/Mods/OSPlus")` under `[/Script/UnrealEd.ProjectPackagingSettings]` in `DefaultGame.ini`) — so it's source-controlled with the project, not per-machine. New contributors who clone the project shouldn't hit this twice.
- **`package_logicmod.ps1` should still detect the empty-cook case explicitly** rather than just failing on missing directory. Defer to a future hardening pass; today's error is clear enough.

## Related

- Files: `ue-assets/package_logicmod.ps1`, `F:\Omegamod\OmegaStonkers 5.1\Config\DefaultGame.ini` (project file, not in this repo)
- Reference: `docs/UE_PROJECT_MIGRATION.md` (the OSPlus folder rename), `KNOWLEDGEBASE.md` → "Pak Packaging"
