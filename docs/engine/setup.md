# Setup, paths, and project config

The *"where is everything, and what INI settings make cooking work"*
doc — second read after [`overview.md`](./overview.md). Distilled
from [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) §"Game Paths" +
§"UE Project Settings" + §"Pak Packaging" + §"Maps" (under "Omega
Strikers — Game Internals").

> **Status:** seeded 2026-05-01 from
> [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md), with KB's stale
> prototype paths (`CustomPings_P.pak`, `OmegaStrikersMod`,
> `OmegaStonkers` minus the ` 5.1` suffix) updated to match the
> current OSPlus mod layout per [`docs/UE_PROJECT_MIGRATION.md`](../UE_PROJECT_MIGRATION.md).
>
> **Stability:** install paths are user-machine-specific; the
> *layout patterns* (LogicMods folder, mount-root convention, INI
> requirements) are stable. Cooked-pak filename + asset folder
> tree are stable per [`docs/decisions/`](../decisions/) one-mod-
> one-pak architectural decision.

This doc is the *paths and config*. The *patterns for what goes
inside a pak* (asset loading, actor spawning, widget tree) live in
[`widgets.md`](./widgets.md). The *toolchain scripts* that operate
on these paths live in
[AGENTS.md → "Toolchain"](../../AGENTS.md#toolchain--use-these-dont-reinvent)
and [`.cursor/rules/harnesses.mdc`](../../.cursor/rules/harnesses.mdc).

## TL;DR

- **Game install: `F:\SteamLibrary\steamapps\common\OmegaStrikers\`.**
  Per-machine; the canonical reference is in
  [AGENTS.md → "External paths"](../../AGENTS.md#external-paths-non-discoverable)
  not here.
- **OSPlus mods land in two places inside the game install:** Lua
  at `Binaries\Win64\ue4ss\Mods\OSPlus\scripts\`; cooked pak at
  `OmegaStrikers\Content\Paks\LogicMods\OSPlus.pak`.
- **The `LogicMods\` folder is BPModLoaderMod's scan target.** Any
  pak in there with the right naming gets auto-loaded. Detail in
  [`widgets.md` → "BPModLoaderMod lifecycle"](./widgets.md#bpmodloadermod-lifecycle).
- **Two `DefaultEngine.ini` settings are LOAD-BEARING for cooking:**
  `CanUseUnversionedPropertySerialization=False` (or complex
  widgets crash on load) and the SM5/DX11 RHI configuration (or
  shaders silently render as black squares).
- **All cooking is manual** in the UE editor — `File → Cook
  Content for Windows`. `/Game/Mods/OSPlus` MUST be in *Project
  Settings → Packaging → Additional Asset Directories to Cook* or
  the cook is empty. See
  [`docs/learnings/ue-cook-additional-asset-dirs.md`](../learnings/ue-cook-additional-asset-dirs.md).
- **Three online maps confirmed**, more exist but uncatalogued.
  See [§"Maps"](#maps).

## Game install layout (player's machine)

| Path (relative to game install root) | What |
|---|---|
| `OmegaStrikers\Binaries\Win64\OmegaStrikers-Win64-Shipping.exe` | Game executable |
| `OmegaStrikers\Binaries\Win64\ue4ss\` | UE4SS root (DLL + Mods folder) |
| `OmegaStrikers\Binaries\Win64\ue4ss\Mods\OSPlus\scripts\` | OSPlus Lua scripts (deployed by [`deploy.ps1`](../../deploy.ps1)) |
| `OmegaStrikers\Content\Paks\` | Base game paks (read-only; do not modify) |
| `OmegaStrikers\Content\Paks\LogicMods\` | **BPModLoaderMod's scan folder** — OSPlus.pak lives here |
| `OmegaStrikers\Content\Paks\LogicMods\OSPlus.pak` | The OSPlus mod pak (cooked Blueprint widgets, materials, actors) |
| `OmegaStrikers\Binaries\Win64\Mods\shared\types\` | UE4SS auto-dumped type stubs (`Prometheus.lua`, `OdyUI.lua`, etc.) — see [`docs/learnings/ue4ss-type-stubs-as-canonical-source.md`](../learnings/ue4ss-type-stubs-as-canonical-source.md) |
| `OmegaStrikers\Binaries\Win64\crash_<timestamp>.dmp` | UE4SS-caught minidumps (when crashes happen — see [`docs/learnings/profile-tick-userdata-allocation-leak.md`](../learnings/profile-tick-userdata-allocation-leak.md)) |
| `%LOCALAPPDATA%\OSPlus\` | OSPlus runtime data (IPC outbox/inbox files; see [`docs/architecture/`](../architecture/)) |

**Conventions:**

- **Game install path is per-machine.** The user's is documented
  in [AGENTS.md → "External paths"](../../AGENTS.md#external-paths-non-discoverable).
  An automation that needs the game install should use the
  detection logic in `dist/install.bat`, not hardcode.
- **Lua deploy is fast.** `deploy.ps1` syncs Lua-only changes;
  no cook needed for Lua iteration. See
  [AGENTS.md → "Local dev loop"](../../AGENTS.md#local-dev-loop).
- **Pak deploy requires cook + repackage.** Cook in editor →
  `package_logicmod.ps1` → drop in `LogicMods\`.

## UE editor project layout (your machine, for cooking)

The OSPlus team uses a UE 5.1.0 source-built editor with a
project that mirrors the game's content layout for the
`/Game/Mods/OSPlus/` mount.

| Path | What |
|---|---|
| (UE editor project root, per-machine) | UE editor project that hosts OSPlus's cooked content. Per-machine path in [AGENTS.md → "External paths"](../../AGENTS.md#external-paths-non-discoverable). |
| `Content\Mods\OSPlus\` | **The mount root.** Anything cooked here lands at `/Game/Mods/OSPlus/...` in the game. Filename MUST match the pak filename (`OSPlus.pak` ↔ `/Game/Mods/OSPlus/`). |
| `Content\Mods\OSPlus\ModActor.uasset` | **Magic name** — required by BPModLoaderMod. Must stay named `ModActor`, must stay at the mount root (not in a subfolder). See [`docs/UE_PROJECT_MIGRATION.md`](../UE_PROJECT_MIGRATION.md) and [`widgets.md` → "BPModLoaderMod lifecycle"](./widgets.md#bpmodloadermod-lifecycle). |
| `Content\Mods\OSPlus\Chat\WBP_ModChat.uasset` | Per-feature widget; lives in a feature subfolder. |
| `Content\Mods\OSPlus\_Shared\` | Reserved for cross-feature assets (currently empty). |
| `Saved\Cooked\Windows\OmegaStrikers\Content\Mods\OSPlus\` | Cook output. `package_logicmod.ps1` reads from here and packs `OSPlus.pak`. |

**Cooking is manual:**

> `File → Cook Content for Windows` in the editor.

`Project Settings → Packaging → Additional Asset Directories to
Cook` MUST include `/Game/Mods/OSPlus` or the cook produces
nothing for OSPlus. See
[`docs/learnings/ue-cook-additional-asset-dirs.md`](../learnings/ue-cook-additional-asset-dirs.md).

For the source-built UE 5.1.0 location (per-machine), see
[AGENTS.md → "External paths"](../../AGENTS.md#external-paths-non-discoverable).

## DefaultEngine.ini

Two clusters of required settings.

### Schema-stability cluster (load-bearing for ScrollBox + complex widgets)

```ini
[Core.System]
CanUseUnversionedPropertySerialization=False
```

**Why this matters.** UE5 cooked assets serialize properties by
schema-index order by default — no property names are stored. If
the game's `UScrollBox` class has even one extra/reordered
property compared to the editor build, the deserializer reads at
wrong offsets and interprets garbage bytes as `FName` indices,
crashing the game during pak load.

`CanUseUnversionedPropertySerialization=False` forces the cooker
to embed property names. The deserializer matches by name instead
of by index, making assets tolerant to property layout
differences. File size grows slightly (e.g., `WBP_ModChat`:
7135 → 8567 bytes) but complex widgets stop crashing.

The full investigation lives in [`widgets.md` → "ScrollBox crash"](./widgets.md#scrollbox-crash--root-cause)
and the original KB section.

> **Important false-friend:** the wrong key name is
> `bUnversionedPropertySerialization` under
> `[/Script/UnrealEd.CookerSettings]`. That setting is not the
> one the cooker actually reads. The correct setting is
> `CanUseUnversionedPropertySerialization` under `[Core.System]`,
> read by `UnversionedPropertySerialization.cpp`. KB documents
> this trap; calling it out here so it doesn't get re-discovered.

### Renderer cluster (load-bearing for materials + shaders)

```ini
[/Script/Engine.RendererSettings]
r.DefaultFeature.AutoExposure=False
r.Lumen.Supported=False
r.Shadow.Virtual.Enable=False
r.GenerateMeshDistanceFields=False

[/Script/WindowsTargetPlatform.WindowsTargetSettings]
DefaultGraphicsRHI=DefaultGraphicsRHI_DX11
TargetedRHIs=PCD3D_SM5

[/Script/HardwareTargeting.HardwareTargetingSettings]
TargetedHardwareClass=Desktop
AppliedTargetedHardwareClass=Desktop
DefaultGraphicsPerformance=Maximum
AppliedDefaultGraphicsPerformance=Maximum
```

**Why this matters.** OS ships DX11 / SM5 only (no Lumen,
no virtual shadow maps, no mesh distance fields). Cook against
SM5 / DX11 or shaders compile for an RHI the game can't use
and render as black squares (or vanish entirely).

## DefaultGame.ini

```ini
[/Script/UnrealEd.ProjectPackagingSettings]
bShareMaterialShaderCode=False
bSharedMaterialNativeLibraries=False
```

**Why this matters.** With shared shader code enabled, shader
bytecode goes into a separate ShaderArchive that may not load
correctly in the game (no mod-side ShaderArchive plumbing).
Disabling forces shader bytecode to be embedded directly in each
material's `.uasset` file. Larger uassets, but reliable.

If you see "black squares" rendering in-game on a material that
worked in the editor preview, this is the first setting to
verify.

## Maps

OS arena maps catalogued so far:

| Map | Player-side context | Asset path |
|---|---|---|
| `MainMenuMap` | Lobby, menus, social, queue (the [Home Hub](../game/lobby.md)) | `/Game/Prometheus/Maps/MainMenuMap/MainMenuMap` |
| `GameMapPractice` | Tutorial / practice mode | `/Game/Prometheus/Maps/GameMap/GameMapPractice` |
| `GameMapAhtenCity` | Online match — the Ahten City arena | `/Game/Prometheus/Maps/GameMap/GameMapAhtenCity` |

Other arena maps almost certainly exist under
`/Game/Prometheus/Maps/GameMap/` but have not been enumerated
in this docset. See [`open-questions.md` → planned](./README.md)
and player-side [`maps.md` → "Open questions"](../game/maps.md#open-questions).

The bridge to the player-side concept ("which arena am I on?")
goes through [glossary → "Map / Arena"](../glossary.md#map--arena).

## Pak packaging

Modern OSPlus packaging uses **`ue-assets/package_logicmod.ps1`** —
the canonical harness. The KB's old reference to a
`package_pak.ps1` is from the prototype era (`CustomPings_P.pak`)
and is not used today.

| Step | Tool | Detail |
|---|---|---|
| 1. Cook | UE editor: `File → Cook Content for Windows` | Manual; `/Game/Mods/OSPlus` must be in *Additional Asset Directories to Cook*. |
| 2. Pack | [`ue-assets/package_logicmod.ps1`](../../ue-assets/package_logicmod.ps1) | Consumes the cook output, runs `repak`, drops `OSPlus.pak` in the game's `LogicMods\`. |
| 3. Restart game | (manual) | "Reload All Mods" only re-runs Lua scripts; pak files require a full game restart to remount. |

What's inside the pak:

- All cooked content from `/Game/Mods/OSPlus/...`
- Skipped: `ShaderArchive-Global`, `ShaderAssetInfo-Global`, HLOD
  files (per the original KB pak guidance — these are the
  game-wide shader archives we don't ship)

For end-user distribution, [`build_dist.ps1`](../../build_dist.ps1)
assembles `OSPlus.pak` + Lua + sidecar SEA + UE4SS bundle +
installer into `dist/OSPlus.zip`. See
[AGENTS.md → "Build & ship the mod"](../../AGENTS.md#build--ship-the-mod).

## Cross-references

- **Engine + UE4SS version pin (load-bearing for everything):** [`overview.md`](./overview.md)
- **UE4SS Lua API used after the pak is loaded:** [`ue4ss-version-and-gotchas.md`](./ue4ss-version-and-gotchas.md)
- **What the cooked content does at runtime:** [`widgets.md`](./widgets.md)
- **Mod-asset-folder rename history (CustomPings → OSPlus, mount-root locking):** [`docs/UE_PROJECT_MIGRATION.md`](../UE_PROJECT_MIGRATION.md)
- **Toolchain scripts:** [AGENTS.md → "Toolchain"](../../AGENTS.md#toolchain--use-these-dont-reinvent), [`.cursor/rules/harnesses.mdc`](../../.cursor/rules/harnesses.mdc)
- **First-time machine setup:** [`tools/setup/bootstrap.ps1`](../../tools/setup/bootstrap.ps1)
- **End-user installer:** [`dist/install.bat`](../../dist/install.bat)
- **Sibling docs index:** [`docs/engine/README.md`](./README.md)

## Open questions

- **Full arena map list.** Three maps catalogued; folder
  `/Game/Prometheus/Maps/GameMap/` likely contains all online
  arenas. A quick `ls` of cooked content would close this.
- **Per-mode map availability matrix.** Which arenas are in
  Ranked vs Brawl vs Custom is not documented here (lives on the
  player-side under [`maps.md`](../game/maps.md) where the same
  question is open).
- **Source-built UE 5.1.0 modifications (if any) by Odyssey.**
  Whether Odyssey's 5.1.0 fork has *additional* schema deltas
  beyond stock 5.1.0 (which is what the source-built editor
  gives us) is not catalogued. The empirical answer is "schema
  drift exists, hence the `CanUseUnversionedPropertySerialization`
  rule" — but the *specific deltas* per affected widget are not
  enumerated. Probably not worth chasing unless we hit another
  ScrollBox-class crash.
