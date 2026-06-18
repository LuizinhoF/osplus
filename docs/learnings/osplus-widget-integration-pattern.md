# OSPlus widget integration pattern (v1 PoC validated)

| Field | Value |
|---|---|
| Date | 2026-05-17 |
| Area | osplus |
| Tags | osplus-widget, pattern, register-custom-event, bp-modloader, integration, template |
| Status | confirmed |

## Symptom / context

Building the first OSPlus widget (the emote loadout rework) surfaced a complete, working integration pattern. Captured here as the **canonical template** for every future OSPlus widget that overrides or augments a native customize-page sub-panel. Following this pattern means not reinventing the load mechanism, the hook chain, or the data-push convention each time.

## The validated pattern

End-to-end stages for any OSPlus widget that replaces a native sub-panel routed via `SetActivePanel`.

### 1. Cook a Widget Blueprint in the UE5.1 dev project

- **Parent class:** `UserWidget`. The dev project doesn't have access to `OdyWidget` — that's an internal Odyssey class only present at runtime. UserWidget is what the editor knows; runtime substitution via Lua-mediated integration sidesteps the OdyWidget gap. No post-cook parent-class patch needed for v1 unless we hit a case where the native panel calls SetUIData-style functions on us that require OdyWidget inheritance.
- Define the visible layout (TextBlock, Image, whatever the design calls for).
- Mark any widgets you'll reference from BP as **Is Variable** (checkbox in the Details panel) — otherwise the graph can't see them.
- Define custom BP functions with the `OSPlus_` prefix (e.g., `OSPlus_SetContext(StrikerName: String)`) for Lua → widget data flow. **The prefix is load-bearing** — it makes our functions instantly distinguishable from native ones in any BP graph, debugger output, or NameMap dump.
- Save at `/Game/Mods/OSPlus/UI/<WidgetName>`. The `/Game/Mods/OSPlus/` namespace is the project convention per ADR 0004.

### 2. Reference the widget class on ModActor for transitive load

- Open `ModActor.uasset` in the dev project.
- Add a new variable of type **User Widget → Class Reference** (stacked-rectangle icon, NOT single-rectangle Object Reference; the single-rectangle stores an instance, the stacked stores a `TSubclassOf<UUserWidget>`).
- Set its default value to your widget class.
- Mark **Instance Editable** or check the open-eye icon — UE sometimes optimizes-out unused private variables and we want to guarantee the reference is preserved through cook.
- Compile + save.

**Why:** BPModLoaderMod loads `OSPlus.pak` and spawns `ModActor` on level load. ModActor's CDO loads with all its hard-class-references resolved transitively, making our widget class memory-resident. Lua's `StaticFindObject` then resolves on first call — no `LoadAsset` dynamic-load API gymnastics, which we tried first and hit several UE4SS 3.0.1 quirks on.

**For multiple widgets:** use an **Array of User Widget Class References** on ModActor as a single registry. Every future OSPlus widget adds itself to the array. Cleaner than one variable per widget.

### 3. Cook + pak + deploy

- UE5.1 cook: File → Cook Content for Windows.
- Run `ue-assets/package_logicmod.ps1`. This handles UnrealPak invocation, mount-path rewriting (the dev project name `OmegaStonkers` → runtime `OmegaStrikers`), removal of stale paks, and deployment to the game's `Content/Paks/LogicMods/` directory.
- BPModLoaderMod auto-picks up paks in LogicMods/ without `load_order.txt` edits.

### 4. Lua module shape

One module per OSPlus widget at `mod/OSPlus/scripts/<feature>_loadout.lua` (or similar). Canonical sections, in order:

```
-- Asset constants  (class paths, native parent class name, target class name)
-- State            (cached widget class, per-parent instance cache, recursion guard)
-- Widget discovery / construction
-- Data push
-- Hook callback
-- M.init()
```

Required from `main.lua`:

```lua
local <feature> = require("<feature>_loadout")
<feature>.init()
```

See `mod/OSPlus/scripts/emote_loadout.lua` for the validated example.

### 5. Hook the panel routing chokepoint

`RegisterCustomEvent` (NOT `RegisterHook` — see [API selection learning](./ue4ss-registerhook-vs-registercustomevent.md)) on the routing function:

```lua
RegisterCustomEvent("SetActivePanel", onSetActivePanelFire)
```

Inside the callback, filter by class name because RegisterCustomEvent matches by short name globally:

```lua
local cls = self_:GetClass():GetFName():ToString()
if cls ~= "WBP_Panel_StrikerCosmetics_C" then return end
```

The host page (`WBP_Menu_Striker_C`) also has a `SetActivePanel` for top-level Affinity/Overview/Cosmetics routing — filter explicitly to avoid catching that.

### 6. Construct + slot + redirect

Once the hook fires with the target panel being the native one we're replacing:

```lua
-- Discover the widget class (memory-resident via ModActor transitive load)
local cls = StaticFindObject("/Game/Mods/OSPlus/UI/WBP_<Name>.WBP_<Name>_C")

-- Construct via canonical UMG factory
local wbLib = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
local instance = wbLib:Create(owningPlayer, cls, nil)

-- Find the host switcher (FindAllOf + leaf-name filter is the reliable approach;
-- WidgetTree traversal from inside the hook callback returned nil — flaky on UE4SS 3.0.1)
local switcher = findSwitcher()

-- Add ourselves as a child so SetActivePanel can target us
switcher:AddChild(instance)

-- Push data via our OSPlus_ BP function
instance:OSPlus_SetContext(strikerName)

-- Recursive redirect with guard
inRedirect = true
self_:SetActivePanel(instance)
inRedirect = false
```

The recursion guard prevents the hook from re-firing on the inner call.

## Reading data off the native panel: the binding-wrapper pattern

When the OSPlus widget needs to read striker context (or any other BP-typed UI data) off the parent panel, use **the type stubs at `<game>/Binaries/Win64/Mods/shared/types/`** to find the actual property names + types, then access via the binding-wrapper pattern.

For striker name from `panel.UIData` on `WBP_Panel_StrikerCosmetics_C`:

```lua
-- UPMUIData_Character_C : UPMCharacterUIData : UPMEntitlementUIData
-- UPMEntitlementUIData has: Name FOdyUITextBinding, Description FOdyUITextBinding, ...
-- FOdyUITextBinding has: InitialValue FText
-- FText has: ToString() returning Lua string

local nameBinding = panel.UIData.Name        -- FOdyUITextBinding
local nameFText  = nameBinding.InitialValue  -- FText
local nameStr    = nameFText:ToString()      -- "Drek'ar"
```

The canonical accessor (for *live* values rather than the initial one) is `UOdyUITextBindingFunctionLibrary:TextBinding_GetValue(binding) → FText`. `.InitialValue` works when the binding was populated once and isn't being live-updated; for changing values use the function library accessor.

**Same pattern applies to other binding types:** `FOdyUIBoolBinding.InitialValue` is `bool`, `FOdyUIIntBinding.InitialValue` is `int32`, `FOdyUITextureBinding.InitialValue` is `UTexture` (or similar). The type stubs (`OdyUI.lua` specifically) document every binding wrapper's shape.

## Conventions worth baking in

1. **One feature = one Lua module + one cooked widget.** Single responsibility. Module is the unit of read/modify/delete.
2. **`OSPlus_` BP-function prefix is mandatory.** Future debugging benefits compound — any BP graph reader (human or agent) instantly sees what's OSPlus vs what's the game's.
3. **`pcall` wrap every native call.** UE4SS Lua marshaling has known cliffs; we don't want one bad value to crash the mod.
4. **Self-contained modules.** Only require shared utilities (`log`, `utils`, `ipc`). Cross-module state is a smell at this stage.

## Future framework extraction

Once 2-3 OSPlus widgets exist, the common parts will become visible as candidates for a shared `osplus_ui_framework.lua` module:

- `register_panel_override(target_class, our_widget_class)` — handles RegisterCustomEvent + filter + cache + redirect plumbing
- `get_or_construct(widget_class)` — handles StaticFindObject + WidgetBlueprintLibrary.Create + AddChild + caching
- Common data-push helpers if a uniform pattern emerges

YAGNI applies: don't extract until the SECOND widget reveals the actual seams.

## Lesson

Three transferable rules:

1. **ModActor class reference is the load mechanism.** Not `LoadAsset`, not `StaticLoadObject`, not any UE4SS dynamic-load API. Define widget classes as hard references on ModActor → BPModLoaderMod transitively loads them → `StaticFindObject` resolves. Saves you from a chain of UE4SS 3.0.1 reflection cliffs.

2. **The full substitution chain is: StaticFindObject → WidgetBlueprintLibrary.Create → AddChild to switcher → recursive SetActivePanel.** Each step has a working test in `mod/OSPlus/scripts/emote_loadout.lua`. Don't reinvent — copy.

3. **`OSPlus_` prefix on every custom BP function.** Convention pays off the first time you read a stack trace or debug a future OSPlus feature.

## Related

- ADR 0004 (revised 2026-05-16): [`docs/decisions/0004-emote-loadout-as-osplus-layer.md`](../decisions/0004-emote-loadout-as-osplus-layer.md)
- API selection rule: [`docs/learnings/ue4ss-registerhook-vs-registercustomevent.md`](./ue4ss-registerhook-vs-registercustomevent.md)
- Routing architecture: [`docs/learnings/customize-page-tab-routing-architecture.md`](./customize-page-tab-routing-architecture.md)
- UE4SS reflection cliffs: [`docs/learnings/ue4ss-3.0.1-bp-reflection-cliffs.md`](./ue4ss-3.0.1-bp-reflection-cliffs.md)
- Native data model: [`docs/learnings/emoticon-panel-data-model.md`](./emoticon-panel-data-model.md)
- Production module: `mod/OSPlus/scripts/emote_loadout.lua`
- Pak deploy script: `ue-assets/package_logicmod.ps1`
- Build/cook step is per-developer (UE editor work); see ADR 0004 for the project convention.
