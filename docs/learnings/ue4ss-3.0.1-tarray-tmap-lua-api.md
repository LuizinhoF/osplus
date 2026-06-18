# UE4SS 3.0.1 Lua: TArray, TMap, and TSoftObjectPtr container API

| Field | Value |
|---|---|
| Date | 2026-05-17 |
| Area | ue4ss |
| Tags | ue4ss-3.0.1, lua, tarray, tmap, tsoftobjectptr, container-api, iteration, uidatamodel, pmuisubsystembase, kismetsystemlibrary |
| Status | confirmed (empirically validated against UE4SS 3.0.1, Omega Strikers shipping branch) |

## Symptom

Iterating the catalog's emote TMap and TArray containers from Lua looked simple on paper (the Prometheus.lua type stubs declare `TMap<FName, UPMEmoticonUIData>` and `TArray<UPMEmoticonUIData>`) but every Lua-style access pattern errored:

- `#owned` silently failed (returned 0 / `nil` depending on usage)
- `pairs(tmap)` errored: `bad argument #1 to 'for iterator' (table expected, got UObject)`
- `tmap[stringKey]` returned a default-constructed value of the TMap's value type rather than dispatching as a method, so any `:Length()` / `:Num()` / `:Size()` named-method call hit "attempt to call a TMap value (field '?')"
- `:GetClass()` on the wrong wrapper (a CDO returned by `FindFirstOf("PMUIDataModel")`) crashed the game outright (no Lua error; process termination — same family as the GetSuperStruct crash documented in `ue4ss-3.0.1-bp-reflection-cliffs.md`)

The Lua-style intuition that TArrays are sequence-tables and TMaps are key-value tables is wrong for UE4SS 3.0.1. They're specific userdata types with their own method names and a distinctive `tostring()` label (`TArray: <addr>` and `TMap: <addr>`, not `UObject: <addr>`).

## The validated API

### TArray

```lua
local arr = catalog.OwnedEmoticons   -- TArray<UPMEmoticonUIData>

local n = arr:GetArrayNum()           -- length, e.g. 282

for i = 1, n do                       -- 1-INDEXED
    local elem = arr[i]               -- UObject userdata
    -- ...
end
```

- **Length**: `:GetArrayNum()`. *Not* `:Num()`, `:Length()`, `:GetNum()`, `:Size()` — those all hit the index-out-of-range metamethod because UE4SS treats `arr["MethodName"]` as `arr[tonumber("MethodName")]` → invalid index.
- **Indexing**: `arr[i]` for `i = 1 .. n`. `arr[0]` errors as "TArray index out of range".
- **No `:GetArrayElement(i)` method.** That name errors the same way.
- **No `#arr` operator support.** Use `:GetArrayNum()`.

### TMap

```lua
local tmap = catalog.ReactionsByCharacterId   -- TMap<FName, UPMReactionsUIData>

local n = #tmap                                 -- count, e.g. 21

tmap:ForEach(function(k, v)                     -- iteration
    local realK = k:get()                       -- k is a RemoteUnrealParam wrapper
    local realV = v:get()                       -- v is a RemoteUnrealParam wrapper
    -- realK is FName userdata (realK:ToString() → e.g. "CD_AngelicSupport")
    -- realV is the UObject userdata (realV.SomeField works after :get())
end)
```

- **Count**: `#tmap` works (returned 21 on a ReactionsByCharacterId map matching the OS roster size). Unlike TArray, the `#` operator IS supported on TMap.
- **Iteration**: `:ForEach(callback(k, v))`. The callback fires once per pair. Confirmed by counting iterations — our 21-entry map fired the callback 21 times. No other iteration shape worked.
- **The (k, v) ForEach yields are `RemoteUnrealParam` wrappers**, same pattern as `RegisterHook` / `RegisterCustomEvent` callback args. Must call `:get()` to access the real FName / UObject. Accessing fields directly on the wrapper silently returns more `RemoteUnrealParam` wrappers (e.g., `v.Emoticons` is still wrapped) and any method call errors with `attempt to call a RemoteUnrealParam value`. *This was a one-iteration trap during write-side validation* — `v.Emoticons:GetArrayNum()` on 21 strikers all errored before unwrapping; after `realV = v:get()`, `realV.Emoticons:GetArrayNum()` returned 7 on every striker.
- **No named arity-0 methods**: `:GetMapNum`, `:GetMapPairNum`, `:Pairs`, `:Iterate`, `:Length`, `:Num`, `:Size`, `:Keys`, `:Values` all error with "attempt to call a TMap value (field '?')". UE4SS interprets `tmap[stringKey]` as a key lookup that returns the value type's default — *not* a method dispatch.
- **No `pairs(tmap)` support.** Errors with "bad argument #1 to 'for iterator' (table expected, got UObject)".
- **Key lookup**: `tmap[fnameKey]` where `fnameKey` is an FName userdata obtained via `k:get()` from ForEach. Confirmed working: passing the resulting value to a UFunction (`EquipEmoticonToSlot`) succeeded, but the value's `tostring()` reads `TMap: <addr>` — likely a UE4SS labeling quirk for TMap-derived field access. Treat the label as cosmetic; trust the UFunction return.

### Object userdata labels are the first clue

`tostring(userdata)` distinguishes the cases:

| Label | Meaning |
|---|---|
| `UObject: <addr>` | Generic UObject — has `:IsValid()`, field access, BP function calls |
| `TArray: <addr>` | TArray container — use `:GetArrayNum()` and `arr[1..N]` |
| `TMap: <addr>` | TMap container — use `#tmap` and `:ForEach(cb)` |
| `UScriptStruct: <addr>` | Struct value — field access, no methods |

Always log `tostring(x)` before assuming the wrapper kind. If you see `UObject: ...` on a field whose type stub says `TArray<T>`, you have the CDO of the parent class (default-constructed empty containers) — see PMUISubsystemBase entry below.

### TSoftObjectPtr

```lua
local softPtr = emote.DataAsset.Image   -- TSoftObjectPtr<UTexture2D>

local kismet = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")

local resolved = kismet:Conv_SoftObjectReferenceToObject(softPtr)  -- nil if unloaded
if not resolved then
    resolved = kismet:LoadAsset_Blocking(softPtr)                  -- forces sync load
end
-- resolved is now a UTexture2D usable as a UMG Image brush.
```

- The wrapper labels as `TSoftObjectPtrUserdata: <addr>` via `tostring`.
- **No `:Get()` / `:LoadSynchronous()` method dispatch.** Same wrapper-returns-default cliff as TMap — `softPtr:Get()` errors with `attempt to call a TSoftObjectPtrUserdata value (field '?')`. The UE method names you'd reach for from C++ don't exist on the Lua wrapper.
- **Resolution goes through `UKismetSystemLibrary`.** The CDO at `/Script/Engine.Default__KismetSystemLibrary` is always loaded; cache it once and reuse. Two functions matter (`Engine.lua` line numbers from the cooked stubs):
  - `Conv_SoftObjectReferenceToObject(softPtr) → UObject` (line 21889) — returns the resolved object if already loaded, `nil` otherwise. Non-blocking, zero side effects. Try this first.
  - `LoadAsset_Blocking(softPtr) → UObject` (line 21294) — forces a synchronous load. Blocks the main thread; use as a fallback for the `Conv → nil` case.
- **Asset path as a string**: `Conv_SoftObjectReferenceToString(softPtr) → FString` (line 21886). Useful for logging or for `StaticFindObject`/`StaticLoadObject` paths. The returned string is the full `/Game/...` asset path.
- **Validated production reference**: `mod/OSPlus/scripts/catalog.lua` → `resolveSoftPtr`. Used to resolve emote `Image` and character `CharacterPortrait` / `CharacterIcon` for the v1 emote loadout display layer.

## Canonical entry to the live UIDataModel

`FindFirstOf("PMUIDataModel")` returns the CDO (`IsValid=false`, all containers default-constructed as zero-size). The live UIDataModel is reached through the UI subsystem:

```lua
local subsystem = FindFirstOf("PMUISubsystemBase")  -- live singleton, IsValid=true
local model = subsystem.UIDataModel                  -- UPMUIDataModelBase, live
local catalog = model.Catalog                        -- UPMCatalogUIData, live

-- catalog.Emoticons is a real TMap (tostring shows "TMap: <addr>")
-- catalog.OwnedEmoticons is a real TArray (tostring shows "TArray: <addr>")
-- catalog.ReactionsByCharacterId is a real TMap (per-striker equipped loadouts)
```

Per type stub `Prometheus.lua:15211`, `UPMUISubsystemBase` has a direct `UIDataModel : UPMUIDataModelBase` field — no UFunction call needed. The subsystem is a session-stable singleton (same pattern `identity.lua` uses with `PMIdentitySubsystem`). All three of subsystem, model, catalog reported `IsValid=true` once accessed this way.

**Why `FindFirstOf("PMUIDataModel")` returned the CDO**: UE4SS's class-name resolution found the CDO first because the live instance's actual runtime class is a BP-generated subclass (`PMUIDataModel_C` or similar) whose short name doesn't exactly match `PMUIDataModel`. The CDO is always present at the C++ base class name. Always go through a subsystem when one exists.

## Lesson

Three transferable rules for any UE4SS 3.0.1 work touching UObject containers:

1. **`tostring(userdata)` is the first diagnostic.** `UObject:`, `TArray:`, `TMap:`, `UScriptStruct:` are distinct wrapper kinds with non-overlapping APIs. Log it before assuming what works.

2. **TArray uses `:GetArrayNum()` + 1-indexed `arr[i]`. TMap uses `#tmap` + `:ForEach(cb)`.** Forget Lua-style `#arr`, `pairs(tmap)`, and C++-style `:Num()` / `:Size()` — none of them work. The asymmetry is real and not intuitive (TMap supports `#`, TArray doesn't).

3. **For UI/data singletons, always go through the subsystem.** `FindFirstOf` on a UObject-base-class name (e.g., `PMUIDataModel`) can return the CDO when the live instance's runtime class is a BP subclass. `FindFirstOf` on the *subsystem* class (`PMUISubsystemBase`, `PMIdentitySubsystem`, …) reliably returns the live instance because subsystems are C++-base singletons.

## Related

- Discovery context: emote loadout v1 PoC (this commit's `emote_loadout.lua`)
- Type stubs: `<game>/Binaries/Win64/Mods/shared/types/Prometheus.lua` line 8864 `UPMCatalogUIData`, line 15101 `Catalog UPMCatalogUIData`, line 15211 `UIDataModel UPMUIDataModelBase`, line 15219 `GetUIDataModel(WorldContextObject)`
- Sibling cliff doc (covers `:GetClass()` chain crash, struct-property cliffs): `docs/learnings/ue4ss-3.0.1-bp-reflection-cliffs.md`
- UFunction call shapes (different problem, same UE4SS version pin): `docs/learnings/ue4ss-ufunction-out-param-marshaling-3-0-1.md`
- Type-stubs methodology: `docs/learnings/ue4ss-type-stubs-as-canonical-source.md`
