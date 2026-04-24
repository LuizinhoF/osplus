# UE4SS Lua API reference

Load when: you need the exact call signature for finding, loading, creating, or hooking UObjects.

For OSPlus-specific patterns (ref-drop, `pcall` discipline, module shape), see `mod-architecture.mdc` and `lua-conventions.mdc`. Read the live `chat.lua` / `ipc.lua` / `main.lua` before writing new UE-touching code.

## Finding objects

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

`FindFirstOf` / `FindAllOf` take the **short class name** (`"ScrollBox"`). `StaticFindObject` takes the **full path**. They aren't interchangeable.

## Loading assets — `GetAsset` vs `LoadAsset`

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

| Method | Behavior | Risk |
|--------|----------|------|
| `arh:GetAsset()` | Loads and returns a reference. Works for Actors and simple Widgets. | Can crash on complex Widget Blueprints due to StaticConstructObject hook thread-safety (UE4SS issue #317). |
| `LoadAsset(path)` | Synchronous load via `StaticLoadObject`. Doesn't crash on complex assets. | Returns a UObject that may not be inspectable via Lua (`GetFullName`/`GetClass` can native-crash). `StaticFindObject` may not find it afterward. |

**Recommendation:** For complex Widget Blueprints (containing ScrollBox, ListView, etc.), don't load them directly via Lua. Use the ModActor/BPModLoaderMod pattern in `mod-actor-pattern.md`.

## Creating objects

```lua
-- StaticConstructObject — creates a UE object from an existing class
local scrollBoxClass = StaticFindObject("/Script/UMG.ScrollBox")
local newScrollBox = StaticConstructObject(scrollBoxClass, parentWidget, 0, 0, 0, nil, false, false, nil)
```

## Calling UFunctions

```lua
-- Call a function on a UObject
local pc = FindFirstOf("PlayerController")
pc:SomeFunction(arg1, arg2)

-- Structs are passed as Lua tables
actor:K2_SetActorLocation({X=100, Y=200, Z=50}, false, {}, false)
```

`SetText` on a TextBlock is a classic trap — it expects `FText`, not a Lua string; passing a string native-crashes. Handle text-setting inside a BP function that converts String → FText, then call that function from Lua.

## Hooks

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

OSPlus calls each module's `M.reset()` from a single `RegisterLoadMapPostHook` in `main.lua`. Don't register your own map hook for a new module — extend `reset()`.

## Mod structure on disk

```
Mods/
  OSPlus/
    scripts/
      main.lua      -- Entry point, runs on mod load
    enabled.txt     -- Contains "1" to enable
```

Register in `Mods/mods.txt`: `OSPlus : 1`. `BPModLoaderMod : 1` must also be present (it owns the ModActor spawn).
