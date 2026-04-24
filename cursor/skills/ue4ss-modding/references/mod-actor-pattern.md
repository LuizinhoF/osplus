# ModActor + BPModLoaderMod pattern — and packaging

Load when: designing a new UI widget for OSPlus, or cooking/packaging assets into the pak.

This is the **community-standard approach** for custom UI in UE4SS mods. Blueprint handles widget creation internally, avoiding the Lua asset-loading crash paths (see `lua-api.md` → "Loading assets").

OSPlus's `WBP_ModChat` already follows this pattern. Read `mod/OSPlus/scripts/ipc.lua` for the Lua↔BP call pattern in production use. For OSPlus-specific cooked-content paths after the rename, see `docs/UE_PROJECT_MIGRATION.md`.

## UE editor setup

1. Create folder: `Content/Mods/OSPlus/`
2. Create an **Actor Blueprint** named `ModActor` in that folder. **Do not rename or move it** — `BPModLoaderMod` hardcodes `/Game/Mods/<ModName>/ModActor`.
3. Create **Widget Blueprint(s)** (e.g. `WBP_ModChat`) in the same folder — can contain any widgets including ScrollBox/ListView.
4. In `ModActor` Event Graph:
   - `Event BeginPlay` → `Create Widget` (select WBP class) → `Add to Viewport`.
   - Store the widget reference in a variable for later access.
   - Fire a `Lua_ModInitialized` custom event, passing the ModActor, so Lua can grab a stable reference.

## Pak packaging (OSPlus-specific)

- Cook the project: **File → Cook Content for Windows**.
- `/Game/Mods/OSPlus` MUST be in *Project Settings → Packaging → Additional Asset Directories to Cook*, or the cook is empty for the mod.
- Package via `ue-assets/package_logicmod.ps1` — packs cooked content into `OSPlus.pak` and drops it in `<GameDir>/OmegaStrikers/Content/Paks/LogicMods/`.
- **LogicMods convention:** do NOT use a `_P` suffix (that's for regular paks and changes load ordering).

Cooker settings required: `CanUseUnversionedPropertySerialization=False` in `DefaultEngine.ini` under `[Core.System]`. Without it, ScrollBox and other complex widgets crash on deserialization. See `KNOWLEDGEBASE.md` RCA.

## UE4SS configuration

`Mods/mods.txt` needs both:

```
BPModLoaderMod : 1
OSPlus : 1
```

`BPModLoaderMod` discovers paks in `LogicMods/` and spawns their ModActor at level-start.

## Lua ↔ Blueprint communication

### Blueprint → Lua — custom events

In the BP, fire a custom event named `Lua_ModInitialized` in `BeginPlay`, passing the ModActor (`self`). The Lua side catches it and caches the reference:

```lua
local _ModActor = nil

RegisterCustomEvent("Lua_ModInitialized", function(ModActor)
    if ModActor:get() ~= nil and ModActor:get():IsValid() then
        _ModActor = ModActor:get()
        print("[OSPlus] ModActor loaded")
    end
end)
```

Drop the `_ModActor` reference in the module's `reset()` — it won't survive a map transition.

### Lua → Blueprint — UFunction calls

Any function defined on the `ModActor` BP (or on a widget inside it) can be called directly from Lua:

```lua
_ModActor:MyBlueprintFunction(arg1, arg2)
```

Good for string-conversion wrappers (e.g. a `SetChatText(String)` BP function that converts to FText internally and calls `TextBlock.SetText`).

## Widget creation via Lua (simple widgets only)

Only use this when the ModActor pattern is overkill — e.g. a CanvasPanel/VerticalBox/TextBlock debug overlay with no complex widgets. **Will crash for Widget Blueprints containing ScrollBox, ListView, or EditableTextBox.**

```lua
local UEHelpers = require("UEHelpers")
local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
local pc = FindFirstOf("PlayerController")

local arh = StaticFindObject("/Script/AssetRegistry.Default__AssetRegistryHelpers")
local assetData = {
    ["PackageName"] = UEHelpers.FindOrAddFName("/Game/CustomUI/WBP_MyWidget"),
    ["AssetName"]   = UEHelpers.FindOrAddFName("WBP_MyWidget_C"),
}
local widgetClass = arh:GetAsset(assetData)

-- WidgetBlueprintLibrary:Create expects 4 parameters: (WorldContext, WidgetClass, OwningPlayer, WidgetName)
local widget = wbl:Create(pc, widgetClass, pc, FName("MyWidget"))
if not widget then
    -- Fallback: StaticConstructObject
    widget = StaticConstructObject(widgetClass, pc, 0, 0, 0, nil, false, false, nil)
end

widget:AddToViewport(0)
widget:SetVisibility(2) -- ESlateVisibility::Visible
```

## Manual UnrealPak method (when needed)

`package_logicmod.ps1` handles 99% of cases. For ad-hoc cooks or investigating pak contents, the manual flow is:

1. File → Cook Content for Windows.
2. Find cooked content in `Saved/Cooked/Windows/ProjectName/Content/`.
3. Create a response file mapping source → mount paths:
   ```
   "C:\Project\Saved\Cooked\...\MyAsset.uasset" "../../../OmegaStrikers/Content/Mods/OSPlus/MyAsset.uasset"
   ```
4. Run: `UnrealPak.exe Output.pak -Create=response.txt`.

Response files MUST be ASCII (see `powershell-conventions.mdc` → Encoding). UnrealPak silently rejects UTF-16 with a cryptic error.

## UE5 packaging (chunk method) — not used by OSPlus

Listed for reference only. OSPlus uses the manual UnrealPak method via `package_logicmod.ps1`.

1. Edit → Editor Preferences → search "chunk" → enable "Allow ChunkID Assignments".
2. Right-click assets → Asset Actions → Assign to Chunk (use ID 1–300, avoid 0).
3. Platforms → Windows → Package Project.
4. Find `.pak` in `Build/Windows/ProjectName/Content/Paks/`.
