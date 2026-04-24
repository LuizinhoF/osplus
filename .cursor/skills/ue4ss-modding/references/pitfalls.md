# UE4SS common pitfalls + debugging

Load when: debugging a crash, an asset-load failure, or unexpected mod behavior.

Before grinding on a specific symptom, check `docs/learnings/` for the exact failure mode — OSPlus has a backlog of solved gotchas documented there.

## Crash/failure matrix

| Problem | Cause | Solution |
|---------|-------|----------|
| Game crash on `GetAsset` for Widget Blueprint | StaticConstructObject hook thread-safety issue with complex widgets (ScrollBox, ListView) | Use ModActor/BPModLoaderMod pattern — let Blueprint handle widget creation |
| `LoadAsset` succeeds but returned object is unusable | UE4SS can't properly wrap all UObject types in Lua | Use `GetAsset` for simple assets, ModActor pattern for complex ones |
| `StaticFindObject` returns nil after `LoadAsset` | Asset loaded into memory but not registered in UE4SS's Lua object table | Known limitation — use `GetAsset` or ModActor pattern |
| Widget Blueprint loads fine without ScrollBox, crashes with it | ScrollBox serialization involves Slate style assets that conflict with UE4SS hooks AND unversioned-property-serialization | Set `CanUseUnversionedPropertySerialization=False`; or use ModActor to create widgets natively |
| `WidgetBlueprintLibrary:Create` returns nil / throws | UE4SS requires explicit parameters: `(WorldContext, WidgetClass, OwningPlayer, WidgetName)` | Always pass all 4 parameters |
| `SetText` native-crashes on TextBlock | `SetText` expects `FText`, Lua passes a string | Wrap in a BP function that converts String → FText, call that from Lua |
| Key bind callback crashes when calling game functions | Key bind callbacks run outside game thread | Wrap in `ExecuteInGameThread(function() ... end)` |
| Mod works in lobby but crashes in-game (or vice versa) | Cached UObject references became stale after map transition | Drop refs in `RegisterLoadMapPostHook`; re-acquire lazily. See `chat.lua:reset()`. |
| Native crash inside `pcall`, process dies anyway | `pcall` doesn't catch C++ access violations on freed UObjects | Ref-drop at known invalidation points — `pcall` is necessary but not sufficient |
| Empty pak after cook | `/Game/Mods/OSPlus` missing from *Additional Asset Directories to Cook* in Project Settings → Packaging | Add it, re-cook |
| `Out-File` response file rejected by UnrealPak | PowerShell default encoding is UTF-16-LE-with-BOM | Use `Out-File -Encoding ascii` (see `powershell-conventions.mdc`) |

## Debugging

### UE4SS log

Located at: `<Game>/Binaries/Win64/ue4ss/UE4SS.log`. Lua `print(...)` lines appear with a `[Lua]` tag.

For file-logged output with timestamps, OSPlus uses `cfg.LOG_FILE` (`log.log("[CATEGORY] msg")`). See `lua-conventions.mdc`.

### Finding game widget classes

```lua
-- Scan for all instances of a widget type
local ok, all = pcall(FindAllOf, "ScrollBox")
if ok and all then
    for _, obj in pairs(all) do
        print(obj:GetFullName())
    end
end

-- Scan all UserWidgets for name-containing substring
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

### Protected calls

Always wrap operations that *might* crash at the Lua level:

```lua
local ok, result = pcall(function()
    return someRiskyOperation()
end)
if not ok then
    print("Error: " .. tostring(result))
end
```

**Caveat, repeated because it keeps costing hours:** `pcall` does NOT catch native access violations. If a C++ function dereferences a freed UObject, the game process terminates regardless of `pcall`. The defense is ref-drop discipline on known invalidation points (map transition, BPModLoader respawn), not adding more `pcall`.
