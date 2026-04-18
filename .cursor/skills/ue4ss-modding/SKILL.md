---
name: ue4ss-modding
description: "Use this skill when working with UE4SS (Unreal Engine Scripting System) mods, Lua scripts for UE4/5 game modding, Blueprint mods via BPModLoaderMod, custom pak files, widget creation in mods, or any modding workflow involving UE4SS. Covers Lua API, asset loading, ModActor patterns, Blueprint+Lua integration, and common pitfalls."
metadata:
  version: 1.0.0
---

# UE4SS Modding — Lua, Blueprint Mods, and Custom UI

You are an expert in UE4SS (RE-UE4SS) modding for Unreal Engine 4/5 games.

## Key Resources

- UE4SS Docs: https://docs.ue4ss.com/
- UE4SS GitHub: https://github.com/UE4SS-RE/RE-UE4SS
- Dmgvol UE Modding Guide: https://github.com/Dmgvol/UE_Modding
- Palworld Modding Wiki (BP+Lua integration): https://pwmodding.wiki/docs/developers/ue4ss-modding/

---

## 1. Lua Mod Structure

```
Mods/
  MyMod/
    scripts/
      main.lua      -- Entry point, runs on mod load
    enabled.txt     -- Contains "1" to enable
```

Register in `Mods/mods.txt`: `MyMod : 1`

### Thread Context

- `RegisterKeyBind` callbacks run outside the game thread — always wrap game operations in `ExecuteInGameThread(function() ... end)`
- `RegisterHook` callbacks run on the game thread
- `LoadAsset` must only be called from the game thread
- `LoopInGameThreadWithDelay(ms, fn)` runs `fn` repeatedly on the game thread

---

## 2. Core Lua API

### Finding Objects

```lua
-- Find first live instance of a class (by short name)
local pc = FindFirstOf("PlayerController")

-- Find ALL instances of a class
local allScrollBoxes = FindAllOf("ScrollBox")

-- Find a specific object by full path
local obj = StaticFindObject("/Script/Engine.Default__GameplayStatics")

-- Notification when new instances are created
NotifyOnNewObject("/Script/UMG.UserWidget", function(constructedObj)
    print("New widget: " .. constructedObj:GetFullName())
end)
```

### Loading Assets

```lua
-- Synchronous load — must run on game thread
-- Returns the loaded UObject (may be nil/unusable for some asset types)
LoadAsset("/Game/MyMod/MyAsset")

-- AssetRegistryHelpers — preferred for Blueprint classes
local arh = StaticFindObject("/Script/AssetRegistry.Default__AssetRegistryHelpers")
local assetData = {
    ["PackageName"] = UEHelpers.FindOrAddFName("/Game/Mods/MyMod/MyActor"),
    ["AssetName"]   = UEHelpers.FindOrAddFName("MyActor_C"),
}
local actorClass = arh:GetAsset(assetData)
```

**CRITICAL: `GetAsset` vs `LoadAsset`**

| Method | Behavior | Risk |
|--------|----------|------|
| `arh:GetAsset()` | Loads and returns a reference. Works for Actors, simple Widgets. | Can crash on complex Widget Blueprints due to StaticConstructObject hook thread-safety (UE4SS issue #317). |
| `LoadAsset(path)` | Synchronous load via `StaticLoadObject`. Doesn't crash on complex assets. | Returns a UObject that may not be inspectable via Lua (GetFullName/GetClass can native-crash). `StaticFindObject` may not find it afterward. |

**Recommendation:** For complex Widget Blueprints (containing ScrollBox, ListView, etc.), do NOT load them directly via Lua. Use the ModActor/BPModLoaderMod pattern instead (Section 4).

### Creating Objects

```lua
-- StaticConstructObject — creates a UE object from an existing class
local scrollBoxClass = StaticFindObject("/Script/UMG.ScrollBox")
local newScrollBox = StaticConstructObject(scrollBoxClass, parentWidget, 0, 0, 0, nil, false, false, nil)
```

### Calling UFunctions

```lua
-- Call a function on a UObject
local pc = FindFirstOf("PlayerController")
pc:SomeFunction(arg1, arg2)

-- Structs are passed as Lua tables
actor:K2_SetActorLocation({X=100, Y=200, Z=50}, false, {}, false)
```

### Hooks

```lua
-- Hook a UFunction (runs on game thread)
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(Context)
    local pc = Context:get()
    print("Player restarted: " .. pc:GetFullName())
end)

-- Key binds (NOT game thread — wrap in ExecuteInGameThread)
RegisterKeyBind(Key.F6, function()
    ExecuteInGameThread(function()
        -- safe to call game functions here
    end)
end)

-- Map load hook
RegisterLoadMapPostHook(function(Engine, World)
    -- New map loaded, reset state
end)

-- Console commands
RegisterConsoleCommandHandler("mycommand", function(FullCommand, Parameters)
    -- Handle command
    return false
end)
```

---

## 3. Widget Creation via Lua (Simple Widgets Only)

This approach works for Widget Blueprints that contain ONLY simple widgets (CanvasPanel, VerticalBox, HorizontalBox, TextBlock, Image). It WILL CRASH for Widget Blueprints containing ScrollBox, ListView, EditableTextBox, or other complex widgets.

```lua
local UEHelpers = require("UEHelpers")
local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
local pc = FindFirstOf("PlayerController")

-- Load the widget class via AssetRegistryHelpers
local arh = StaticFindObject("/Script/AssetRegistry.Default__AssetRegistryHelpers")
local assetData = {
    ["PackageName"] = UEHelpers.FindOrAddFName("/Game/CustomUI/WBP_MyWidget"),
    ["AssetName"]   = UEHelpers.FindOrAddFName("WBP_MyWidget_C"),
}
local widgetClass = arh:GetAsset(assetData)

-- Create the widget (4 parameters required)
local widget = wbl:Create(pc, widgetClass, pc, FName("MyWidget"))
if not widget then
    -- Fallback: StaticConstructObject
    widget = StaticConstructObject(widgetClass, pc, 0, 0, 0, nil, false, false, nil)
end

-- Add to viewport
widget:AddToViewport(0)
widget:SetVisibility(2) -- ESlateVisibility::Visible
```

---

## 4. ModActor + BPModLoaderMod (Recommended for Complex UI)

This is the **community-standard approach** for custom UI in UE4SS mods. The Blueprint handles widget creation internally, avoiding Lua asset loading crashes.

### UE Editor Setup

1. Create folder: `Content/Mods/MyMod/`
2. Create **Actor Blueprint** named `ModActor` in that folder
3. Create **Widget Blueprint** (e.g., `WBP_MyUI`) in the same folder — can contain any widgets including ScrollBox
4. In ModActor Event Graph:
   - `Event BeginPlay` → `Create Widget` (select WBP_MyUI class) → `Add to Viewport`
   - Store the widget reference in a variable for later access

### Pak Packaging

- Cook the project (File → Cook Content for Windows, or Package Project for UE5)
- Package into a `.pak` file
- Place in `Content/Paks/LogicMods/` (NOT regular Paks folder)
- Do NOT use `_P` suffix for LogicMods paks

### UE4SS Configuration

Enable BPModLoaderMod in `Mods/mods.txt`:
```
BPModLoaderMod : 1
```

### Lua ↔ Blueprint Communication

**Blueprint calls Lua:**
In the Blueprint, create a function named `Lua_ModInitialized` that fires a custom event with the ModActor as parameter.

```lua
-- Lua side: catch the Blueprint initialization
local _ModActor = nil

RegisterCustomEvent("Lua_ModInitialized", function(ModActor)
    if ModActor:get() ~= nil and ModActor:get():IsValid() then
        _ModActor = ModActor:get()
        print("Blueprint mod loaded!")
    end
end)
```

**Lua calls Blueprint functions:**
```lua
-- Call any function defined in the ModActor Blueprint
_ModActor:MyBlueprintFunction(arg1, arg2)
```

---

## 5. Cooking & Packaging Assets

### UE5 Packaging (Chunk Method)

1. Edit → Editor Preferences → search "chunk" → enable "Allow ChunkID Assignments"
2. Right-click assets → Asset Actions → Assign to Chunk (use ID 1-300, avoid 0)
3. Platforms → Windows → Package Project
4. Find `.pak` in `Build/Windows/ProjectName/Content/Paks/`

### UE4/UE5 Manual Method (UnrealPak)

1. File → Cook Content for Windows
2. Find cooked content in `Saved/Cooked/Windows/ProjectName/Content/`
3. Create a response file mapping source → mount paths
4. Run: `UnrealPak.exe Output.pak -Create=response.txt`

### Mount Path Format

```
"C:\Project\Saved\Cooked\...\MyAsset.uasset" "../../../GameName/Content/MyMod/MyAsset.uasset"
```

---

## 6. Common Pitfalls

| Problem | Cause | Solution |
|---------|-------|----------|
| Game crash on `GetAsset` for Widget Blueprint | StaticConstructObject hook thread-safety issue with complex widgets (ScrollBox, ListView) | Use ModActor/BPModLoaderMod pattern — let Blueprint handle widget creation |
| `LoadAsset` succeeds but returned object is unusable | UE4SS can't properly wrap all UObject types in Lua | Use `GetAsset` for simple assets, ModActor pattern for complex ones |
| `StaticFindObject` returns nil after `LoadAsset` | Asset loaded into memory but not registered in UE4SS's Lua object table | Known limitation — use `GetAsset` or ModActor pattern |
| Widget Blueprint loads fine without ScrollBox, crashes with it | ScrollBox serialization involves Slate style assets that may conflict with UE4SS hooks | Remove ScrollBox from pak-loaded widgets, or use ModActor to create widgets natively |
| `WidgetBlueprintLibrary:Create` expects N parameters | UE4SS requires explicit parameters: (WorldContext, WidgetClass, OwningPlayer, WidgetName) | Always pass all 4 parameters |
| `SetText` crashes on TextBlock | `SetText` expects FText, Lua passes a string — native crash | Handle text setting inside Blueprint functions that convert String → FText |
| Key bind callback crashes when calling game functions | Key bind callbacks run outside game thread | Wrap in `ExecuteInGameThread(function() ... end)` |
| Mod works in lobby but crashes in-game | Asset references become stale after map transitions | Reset cached references in `RegisterLoadMapPostHook` and reload |

---

## 7. Debugging

### UE4SS Log

Located at: `<Game>/Binaries/Win64/ue4ss/UE4SS.log`

```lua
-- Print to UE4SS console (appears in log with [Lua] tag)
print("[MyMod] Hello world\n")
```

### Finding Game Widget Classes

```lua
-- Scan for all instances of a widget type
local ok, all = pcall(FindAllOf, "ScrollBox")
if ok and all then
    for _, obj in pairs(all) do
        print(obj:GetFullName())
    end
end

-- Scan all UserWidgets for specific names
local ok, all = pcall(FindAllOf, "UserWidget")
if ok and all then
    for _, w in pairs(all) do
        local name = w:GetFullName()
        if name:lower():find("chat") then
            print("Found: " .. name)
        end
    end
end
```

### Protected Calls

Always use `pcall` for operations that might crash:
```lua
local ok, result = pcall(function()
    return someRiskyOperation()
end)
if not ok then
    print("Error: " .. tostring(result))
end
```

Note: `pcall` catches Lua errors but NOT native crashes. If a C++ function triggers an access violation, the game process terminates regardless of pcall.
