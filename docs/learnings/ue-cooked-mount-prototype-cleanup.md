# UE Cooked Mount Prototype Cleanup

| Field | Value |
|---|---|
| Date | 2026-05-24 |
| Area | ue-editor |
| Tags | `ue-editor, cooked-assets, packaging, content-layout` |

## Context

OSPlus cooks and packages everything under `/Game/Mods/OSPlus` into
`OSPlus.pak`. During emote-loadout work, the UE project still contained old
prototype assets under that cooked mount: custom-ping chat drafts,
`Test.uasset`, and a stale native-path Prometheus emote-panel override stub.

## Finding

Prototype assets under a cooked mount are production assets unless the package
step explicitly excludes them or they are moved out of `Content`. UE's content
tree is the source of truth for future contributors, but the cooked output can
also contain stale files from prior cooks. Cleaning only the source project does
not guarantee the next `package_logicmod.ps1` run avoids stale cooked scratch
files.

## Action Taken

- Archived unreferenced prototype source assets outside the UE `Content`
  directory under:
  `F:\Omegamod\OmegaStonkers 5.1\_Archive\2026-05-24-osplus-cleanup\`.
- Removed stale standard cook paths for `/Game/CustomPings/*`,
  `/Game/Mods/OmegaStrikersMod`, and the old
  `/Game/Prometheus/UI/OutOfGame/Strikers` override path from
  `DefaultGame.ini`.
- Added scratch/prototype exclusions to `ue-assets/package_logicmod.ps1` so
  stale cooked files are not shipped even if they remain in
  `Saved/Cooked/.../Content/Mods/OSPlus`.

## Rule

Before declaring UE content clean:

1. Check source assets under `Content/Mods/OSPlus`.
2. Check `Saved/Cooked/.../Content/Mods/OSPlus` for stale cooked output.
3. Check package script exclusions for known scratch folders/patterns.
4. Prefer UE Editor or UE Python asset deletion for referenced assets.
5. For unreferenced binary assets, archive outside `Content` rather than
   deleting immediately.

Do not rely on visual Content Browser cleanliness alone; the pak builder reads
cooked files, not the editor tree.

## Follow-Up

`PingTest.umap` and `PingTest_HLOD0_Instancing.uasset` are still present under
`Content/Mods/OSPlus/CustomPings/Textures`. The asset registry reports external
actor/object references owned by that test map, so it should be deleted in a
dedicated UE-side cleanup pass rather than moved by hand.
