# UI, widgets, and cooked-pak rendering

The catch-all *"how do I put pixels on screen via cooked paks +
UE4SS"* doc — read this when designing any UI feature, working on
the chat widget, or planning a new in-match overlay. Distilled
from [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) §"HUD System" +
§"Asset Loading" + §"Actor Spawning" + §"Material Setup" +
§"BPModLoaderMod Lifecycle" + §"Widget System (Cooked Paks)" +
§"EditableText" + §"Input Mode Management" + §"Visibility
Constants" + §"GameInstance Persistence" + §"Flipbook Animation"
+ §"ScrollBox Crash" + the HUD/UI sub-sections of "Class Hierarchy
Reference".

> **Status:** seeded 2026-05-01 from
> [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md). The original KB
> sections referenced the prototype-era ping system
> (`CustomPings_P.pak`, `BP_PingMarker`, `M_PingSprite`) which
> shipped before the OSPlus rename. The *patterns* documented
> there are still load-bearing for any cooked-pak content; the
> *specific asset names* are historical. Examples below use both:
> the historical asset names where the original learning was
> recorded, and the current OSPlus paths where the production
> system lives.
>
> **Stability:** UMG-only HUD pattern, BPModLoaderMod magic name,
> and ScrollBox crash root-cause are all stable — they survive
> any patch short of an engine bump. EditableText / ScrollBox /
> Input Mode quirks are pinned to UE 5.1.0 and unlikely to move.

This doc is the *consolidated* UI / cooked-pak-rendering
reference. It's deliberately big to keep cross-cutting topics
(asset loading + widget instantiation + ScrollBox crash root cause
+ widget tree of the game) one read away from each other. Per-doc
fragmentation would mean three more cross-references for any
question.

## TL;DR

- **The game's HUD is UMG-only.** Canvas drawing
  (`DrawRect`/`DrawText`/`DrawLine`) is unreachable;
  `ReceiveDrawHUD` doesn't fire. To put pixels on screen,
  cook a UserWidget Blueprint and instantiate it from Lua.
  See [§"The cooked-pak rendering model"](#the-cooked-pak-rendering-model).
- **BPModLoaderMod is the auto-loader.** It scans
  `Content/Paks/LogicMods/` for paks, looks for the magic
  `/Game/Mods/<ModName>/ModActor` asset path, and spawns the
  ModActor whose BeginPlay graph creates feature widgets. See
  [§"BPModLoaderMod lifecycle"](#bpmodloadermod-lifecycle).
- **Widget instantiation from Lua:** prefer
  `StaticConstructObject` over `WidgetBlueprintLibrary::Create`.
  See [§"Widget instantiation from Lua"](#widget-instantiation-from-lua).
- **The ScrollBox crash root-cause** is unversioned property
  serialization + schema drift between editor and game builds.
  Fixed by `CanUseUnversionedPropertySerialization=False`. See
  [§"ScrollBox crash — root cause"](#scrollbox-crash--root-cause).
- **Five widget-specific quirks bite hard** on UE 5.1.0:
  EditableText `SetText("")` doesn't clear; `OnTextCommitted`
  fires twice; `Get Owning Player` returns null on
  GameInstance-parented widgets; HitTestInvisible vs
  SelfHitTestInvisible affects descendant click handling; BP
  function naming strips spaces. See
  [§"Widget-specific quirks"](#widget-specific-quirks).
- **`GameInstance_Base_C` is the persistent root.** Widgets added
  to its viewport survive map transitions. See
  [§"GameInstance persistence"](#gameinstance-persistence-the-persistent-root).

## The cooked-pak rendering model

### HUD class hierarchy

The game's HUD class hierarchy in practice mode (which is
representative; menu and online use sibling classes following
the same shape):

```text
HUD_Practice_C (Blueprint, 2 UFunctions)
  └─ PMHUDBase (/Script/Prometheus, 2 UFunctions: AddOffscreenIndicator, RemoveOffscreenIndicator)
      └─ OdyHUD (/Script/OdyUI, 2 UFunctions: OnUIRouterCreated, GetUIRouter)
          └─ AHUD (/Script/Engine, 29 UFunctions including DrawRect, DrawText, ReceiveDrawHUD, etc.)
              └─ AActor (/Script/Engine, 134 UFunctions including ReceiveTick)
                  └─ UObject
```

Sibling HUD classes per phase:

- `HUD_Menu_C` — menu / out-of-match
- `HUD_Practice_C` — practice mode
- (online match HUD class is presumably similar; not catalogued)

### `ReceiveDrawHUD` does NOT fire

`ReceiveDrawHUD` is a `BlueprintImplementableEvent` — it only
fires if a Blueprint subclass implements it. None of the OS HUD
Blueprints (`HUD_Practice_C`, `HUD_Menu_C`, etc.) implement it.

The C++ classes (`OdyHUD`, `PMHUDBase`) override `DrawHUD()` in
C++ **without calling `Super::DrawHUD()`**, so the event never
gets dispatched.

Practical consequence: hooking `/Script/Engine.HUD:ReceiveDrawHUD`
via `RegisterHook` registers successfully but the callback never
fires. Don't waste time on this path.

### Canvas drawing functions are never called

`DrawRect`, `DrawText`, `DrawLine`, `DrawTexture`, `DrawMaterial`,
etc. on `AHUD` are never called by the game. The game uses UMG
widgets exclusively — Canvas is never set up during gameplay.

### What DOES work for UI

| Approach | When to use |
|---|---|
| **UMG widget Blueprints (UserWidget)** | Almost always. Cook a `WBP_*` widget in the UE editor, ship it in the OSPlus pak, instantiate from Lua. The chat widget (`WBP_ModChat`) follows this pattern; every future OSPlus UI feature should too. |
| **World-space actors** | When the visual needs to live in 3D space (e.g., the prototype ping markers). Cook a `BP_*` actor, ship in the pak, `world:SpawnActor()` from Lua. |
| (Anything Canvas-based) | (Not viable — see above.) |

The full instantiation patterns are below.

## BPModLoaderMod lifecycle

This is how OSPlus's cooked Blueprint assets get loaded into
the game. **Critical magic-name constraint.**

### The auto-load sequence

1. **Startup.** BPModLoaderMod (a UE4SS bundled-mod) scans
   `OmegaStrikers\Content\Paks\LogicMods\` for `.pak` files.
2. **Registration.** For each pak, it creates a config:
   - `AssetPath = /Game/Mods/<ModName>/ModActor`
   - `AssetName = ModActor_C`
   - `<ModName>` is derived from the **pak filename** (so
     `OSPlus.pak` → mount root `/Game/Mods/OSPlus/`).
3. **Map load.** On every `RegisterLoadMapPostHook`, it calls
   `LoadMods(World)`.
4. **Loading.** Uses `AssetRegistryHelpers:GetAsset(assetData)`
   to resolve the Blueprint class from the pak.
5. **Spawning.** Calls `World:SpawnActor(ModClass, {}, {})` to
   instantiate the ModActor.
6. **Widget creation.** ModActor's BeginPlay event graph is
   responsible for creating the feature widgets (e.g.,
   `WBP_ModChat`) and adding them to viewport.

### The magic-name constraint

Everything follows from the path-derivation rule above:

- The asset **MUST** be named `ModActor` (not
  `BP_OSPlusActor` or anything else).
- The asset **MUST** live directly under `/Game/Mods/OSPlus/`
  (not in any subfolder).
- The pak filename **MUST** match the mount root —
  `OSPlus.pak` mounts to `/Game/Mods/OSPlus/`. A pak named
  differently won't be loaded.

Feature widgets (`WBP_ModChat`, future widgets) are loaded by
**`ModActor`'s BeginPlay graph** using BP class references —
NOT by BPModLoaderMod itself. They can live in subfolders. UE
Editor's "Move Asset" dialog updates BP references automatically
when you do moves through the editor. Full layout decisions in
[`docs/UE_PROJECT_MIGRATION.md`](../UE_PROJECT_MIGRATION.md).

### Timing characteristics

- `[BPModLoaderMod] Loading mod:` log line appears **~27s
  after game start** (the first `LoadMapPostHook`).
- The `Actor:` confirmation log follows immediately if
  `SpawnActor` succeeded.
- **If no `Actor:` line appears**, the crash occurred during
  `SpawnActor` → asset deserialization. The most common cause
  is the ScrollBox / unversioned-property crash; see
  [§"ScrollBox crash"](#scrollbox-crash--root-cause).

### Duplicate prevention

ModActor's BeginPlay graph runs `Get All Widgets Of Class(WBP_ModChat)`
+ `Array.IsEmpty` check before creating the chat widget. Without
this, every map transition would re-create a duplicate chat
widget on top of the existing one (since `GameInstance_Base_C`
persistence keeps the old one alive — see
[§"GameInstance persistence"](#gameinstance-persistence-the-persistent-root)).

## Asset loading from cooked paks

The proven pattern for finding any cooked asset (material,
texture, BP class) by path. Carried forward from the original
ping system; still load-bearing for any cooked content lookup.

```lua
local function findAsset(assetPath)
    local assetName = assetPath:match("[^/]+$")

    -- Try StaticFindObject with multiple path formats
    local tryPaths = {
        assetPath .. "." .. assetName,
        "MaterialInstanceConstant " .. assetPath .. "." .. assetName,
        "Texture2D " .. assetPath .. "." .. assetName,
    }
    for _, path in ipairs(tryPaths) do
        local ok, obj = pcall(StaticFindObject, path)
        if ok and obj and type(obj) == "userdata" then
            local validOk, isValid = pcall(function() return obj:IsValid() end)
            if validOk and isValid then return obj end
        end
    end

    -- Fallback: AssetRegistryHelpers
    local arh = StaticFindObject("/Script/AssetRegistry.Default__AssetRegistryHelpers")
    if not arh or not arh:IsValid() then return nil end

    local ok, result = pcall(function()
        local assetData = {
            ["PackageName"] = UEHelpers.FindOrAddFName(assetPath),
            ["AssetName"] = UEHelpers.FindOrAddFName(assetName),
        }
        return arh:GetAsset(assetData)
    end)
    if ok and result then
        local validOk, isValid = pcall(function() return result:IsValid() end)
        if validOk and isValid then return result end
    end
    return nil
end
```

**Why this many paths.** Different asset types (textures,
materials, MIs, BP classes) can require their typename prefix in
the path string for `StaticFindObject` to succeed. Falling back
to `AssetRegistryHelpers` handles cases where the asset's package
hasn't been loaded yet.

### Loading a Blueprint class

Three patterns in order of preference:

```lua
-- Pattern 1: AssetRegistryHelpers with the generated class name (BP_Name_C)
local arh = StaticFindObject("/Script/AssetRegistry.Default__AssetRegistryHelpers")
local assetData = {
    ["PackageName"] = UEHelpers.FindOrAddFName("/Game/Mods/OSPlus/Chat/WBP_ModChat"),
    ["AssetName"] = UEHelpers.FindOrAddFName("WBP_ModChat_C"),
}
local cls = arh:GetAsset(assetData)

-- Pattern 2: AssetRegistryHelpers with the asset itself, then .GeneratedClass
local assetData2 = {
    ["PackageName"] = UEHelpers.FindOrAddFName("/Game/Mods/OSPlus/Chat/WBP_ModChat"),
    ["AssetName"] = UEHelpers.FindOrAddFName("WBP_ModChat"),  -- without _C
}
local bp = arh:GetAsset(assetData2)
local cls = bp.GeneratedClass

-- Pattern 3: StaticFindObject with the typename prefix and full path
local cls = StaticFindObject("BlueprintGeneratedClass /Game/Mods/OSPlus/Chat/WBP_ModChat.WBP_ModChat_C")
```

(KB's original example used `/Game/CustomPings/VFX/BP_PingMarker`
from the prototype-era ping system; replaced here with the
current OSPlus chat widget path.)

## Actor spawning from cooked paks

The proven pattern for spawning a cooked BP actor (e.g., 3D
world-space visuals).

```lua
local world = UEHelpers.GetWorld()
local actor = world:SpawnActor(cachedBPClass, {}, {})
actor:K2_SetActorLocation(makeVec(x, y, z), false, {}, false)
actor:SetLifeSpan(10.0)  -- auto-destroy after 10 seconds

-- Access Blueprint components by name
local meshComp = actor.PingMesh
meshComp:SetMaterial(0, materialInstance)
meshComp.bVisible  -- read visibility

-- Scale
actor:SetActorScale3D(makeVec(scaleX, scaleY, scaleZ))

-- Destroy explicitly (vs SetLifeSpan)
actor:K2_DestroyActor()
```

**Notes:**

- `SpawnActor`'s 2nd/3rd args are `FTransform`/`FActorSpawnParameters`;
  empty tables work as defaults.
- Component access by name (`actor.PingMesh`) requires the
  component to have been added in the BP editor with that name.
- `makeVec` is a UEHelpers convenience; use
  `KismetMathLibrary:MakeVector(x, y, z)` if not using helpers.
  See [`ue4ss-version-and-gotchas.md` → "FVector / FRotator creation"](./ue4ss-version-and-gotchas.md#fvector--frotator-creation).

## Widget instantiation from Lua

The pattern for instantiating a UMG widget from Lua and adding
it to the viewport.

**Preferred:**

```lua
local widget = StaticConstructObject(widgetClass, playerController, FName("WidgetName"))
widget:AddToViewport(0)  -- z-order
```

**Why this over `WidgetBlueprintLibrary::Create`:**

- `WidgetBlueprintLibrary::Create` expects 4 params
  (`WorldContext`, `WidgetClass`, `OwningPlayer`, `WidgetName`).
- `StaticConstructObject` is simpler and proven working.
- The UE4SS Lua wrapper for `WidgetBlueprintLibrary::Create` has
  surprising arg-passing requirements that have bitten teams in
  the past.

**For OSPlus's chat widget specifically**, the widget is
created **by the ModActor's BeginPlay graph** (Blueprint side),
not by Lua. Lua then finds the widget via
`FindFirstOf("WBP_ModChat_C")` and operates on it. This split
exists because:

- BeginPlay graph runs at the right moment
  (post-`LoadMapPostHook`, before player-interactive).
- `FindFirstOf` is reliable once the widget exists.
- Doing the construction from Lua duplicates BP work and adds
  cold-start race surface.

If you're adding a new widget feature, you have two choices:

1. **Construct in BP** (extend ModActor's BeginPlay graph) +
   **operate from Lua** (find via `FindFirstOf`). Same pattern
   as chat. Recommended for persistent widgets.
2. **Construct from Lua** with `StaticConstructObject`. Fine for
   ephemeral / on-demand widgets.

## Material setup

Patterns from the original ping-system master material work.
Still load-bearing for any custom material in OSPlus's pak.

### Master material requirements

For a typical screen-space sprite material (the canonical example
was `M_PingSprite`):

| Setting | Value | Why |
|---|---|---|
| Material Domain | Surface | Standard surface material. |
| Blend Mode | **Translucent** | Allows alpha blending with the scene. |
| Shading Model | **Unlit** | UI-style — don't compute lighting. |
| Two Sided | **checked** | Renders both faces (handy for sprites that may face away). |
| Graph (typical) | `TextureSample(Icon).RGB * Color.RGB` → Emissive Color, `TextureSample(Icon).A * Color.A` → Opacity | The standard "tinted icon with alpha" wiring. |

### Material instance overrides

When creating a Material Instance from the master, **enable
Material Property Overrides** for the attributes you want the MI
to lock in:

- Blend Mode → Translucent
- Shading Model → Unlit
- Two Sided → override checkbox ON, actual value OFF (yes, this
  is correct — checking the override box with an unchecked value
  forces the instance to single-sided regardless of the master's
  setting)

Without the override, the MI inherits from the master *at
package-load time*; subsequent master changes don't propagate
through to old instances cleanly.

### Common material bugs

| Symptom | Cause | Fix |
|---|---|---|
| Black squares | Shader incompatibility (SM6 vs SM5) or missing shader archives | Set `bShareMaterialShaderCode=False`, target SM5 / DX11 — see [`setup.md` → "DefaultGame.ini"](./setup.md#defaultgameini). |
| Invisible / transparent | Alpha channel multiplied by 0 in material graph | Verify `Icon.A * Color.A` wiring to Opacity is correct. |
| White squares | Material not assigned | Check `meshComp:SetMaterial(0, mat)` is called with a valid material reference. |

## Flipbook animation (sprite sheets)

Pattern for animated sprite-sheet materials.

### Material setup

- Replace `TextureSampleParameter2D` with **`TextureObjectParameter`**
  for the Flipbook node's Texture input.
- The `Flipbook` node takes Number of Rows and Number of Columns
  as **input pins** — wire `Constant` or `Scalar Parameter` nodes
  to them.
- A `Time` node multiplied by a constant controls playback speed
  (`* 1.0` = one cycle/sec).
- Use `Scalar Parameters` for Rows / Columns so material
  instances can set 1×1 (static) or 4×4 (animated) without
  needing a separate master.

### Sprite sheet requirements

- Power-of-2 textures preferred (2048×2048, 4096×4096) but
  non-power-of-2 works fine.
- 16 frames (4×4 grid) is a reasonable sweet spot for VFX
  animations — enough cells for smooth motion, small enough that
  the sprite-sheet texture stays compact.
- UE Editor's material preview only animates with **Realtime
  Preview** enabled (the little clock icon in the preview
  toolbar).

## Widget catalog (what works in cooked paks)

The widget types proven to work in cooked OSPlus paks on this
engine + UE4SS combination:

| Widget Type | Status | Notes |
|---|---|---|
| `CanvasPanel` | Working | Root container for any UserWidget. |
| `SizeBox` | Working | Size constraints, `MaxDesiredHeight` for clipping. |
| `Border` | Working | Background color / padding. |
| `VerticalBox` | Working | Vertical layout. |
| `HorizontalBox` | Working | Horizontal layout. |
| `TextBlock` | Working | Static text display. |
| `EditableText` | Working | Text input. **NOT** `EditableTextBox` — see [§"EditableText quirks"](#editabletext-quirks-chat-input). |
| `ScrollBox` | **Working with prerequisite** | Requires `CanUseUnversionedPropertySerialization=False` in `[Core.System]`. Without that, crashes on pak deserialization due to schema drift between editor and game builds. With versioned serialization, works natively. See [§"ScrollBox crash — root cause"](#scrollbox-crash--root-cause). |

### ScrollBox crash — root cause

**Status: SOLVED 2026-04-18.** Background here for context; the
fix is the INI line above + in [`setup.md` → "DefaultEngine.ini"](./setup.md#defaultengineini).

**Symptom:** Spawning the ModActor — which contained a child
ScrollBox somewhere in its widget tree — crashed the game during
asset deserialization with `FName serialization error — index
33817088, valid range [0, 96)`.

**Root cause:** Unversioned property serialization
(`PKG_UnversionedProperties` flag `0x2000`). UE5 cooked assets
serialize properties by schema-index order by default — no
property names are stored. If the game's `UScrollBox` class has
even a single extra/reordered property compared to the editor
build, the deserializer reads at wrong offsets and interprets
garbage bytes as `FName` indices, causing the crash.

**Investigation timeline (compressed from KB):**

1. **UE 5.1.1 (Epic launcher) attempt.** Crashes on
   `SpawnActor` — binary schema mismatch with the 5.1.0 game
   runtime.
2. **UE 5.1.0 (built from source) attempt.** Still crashes
   with the same `FName serialization error` — the source
   build's ScrollBox schema *still* differs from Odyssey's
   custom 5.1.0 fork.
3. **Binary analysis.** ModActor files were byte-identical
   between 5.1.0 and 5.1.1 outputs (simple widgets serialize
   identically). The garbage FName index wasn't present in the
   files — the deserializer was reading at a wrong offset due to
   schema mismatch.
4. **INI config attempt 1 (false start).**
   `bUnversionedPropertySerialization=False` under
   `[/Script/UnrealEd.CookerSettings]` had no effect. **Wrong
   section, wrong key name.**
5. **Source-code analysis.** Found the actual setting in
   `UnversionedPropertySerialization.cpp:771` — it reads
   `[Core.System] CanUseUnversionedPropertySerialization` from
   `GEngineIni`.

**Solution:** see [`setup.md` → "DefaultEngine.ini → Schema-stability cluster"](./setup.md#schema-stability-cluster-load-bearing-for-scrollbox--complex-widgets).

**Lesson (carried forward):** simple containers (`CanvasPanel`,
`VerticalBox`, `SizeBox`, `Border`) happen to have identical
schemas across UE 5.1.x variants, so they worked even with
unversioned serialization. Complex widgets like `ScrollBox` have
schema drift. **Always cook with
`CanUseUnversionedPropertySerialization=False` for mod assets.**

## Widget-specific quirks

### EditableText quirks (chat input)

| Issue | Cause | Workaround |
|---|---|---|
| `SetText("")` doesn't clear | UE 5.1.1 Slate bug — empty string reverts | Use `SetText(FText(" "))` (single space), trim on Lua side |
| `OnTextCommitted` fires twice on Enter | Engine behavior (event also fires on focus loss) | Blueprint clears `PendingMessage` after first read so the second fire is a no-op |
| `Get Owning Player` returns null | Widget added to GameInstance, not level player | Use `Get Player Controller 0` instead |
| Controls locked after chat closes | `Set Input Mode Game Only` doesn't recapture mouse properly | Use `Set Input Mode Game And UI` + `Set Focus to Game Viewport` — see [§"Input mode management"](#input-mode-management) |
| Empty Enter doesn't close chat | Space-workaround trims to `""` and the early-return skips the `close()` call | Call `close()` *before* the empty-string check |

### Input mode management

OSPlus's chat system needs to switch between game and UI input
modes around the chat focus. The two procedures:

**Opening chat (`OpenInput` BP function):**

1. Set ChatInput visibility → `Visible`
2. `Set Input Mode UI Only` (target: `Get Player Controller 0`)
3. `Set User Focus` on ChatInput

**Closing chat (`CloseInput` BP function):**

1. Set ChatInput visibility → `Collapsed`
2. `Set Input Mode Game And UI` (target: `Get Player Controller 0`)
3. `Set Focus to Game Viewport`

The asymmetry — opening goes to UI Only, closing returns to
Game And UI — is deliberate. Game Only loses mouse capture
(see EditableText quirks above).

### Visibility constants (`ESlateVisibility`)

| Value | Name | Behavior |
|---|---|---|
| 0 | `Visible` | Renders and receives clicks. |
| 1 | `Collapsed` | Hidden, takes no layout space. |
| 2 | `Hidden` | Hidden but takes layout space. |
| 3 | `HitTestInvisible` | Renders but passes clicks through (and **all descendants** also can't receive clicks). |
| 4 | `SelfHitTestInvisible` | Renders, self doesn't receive clicks but **children can**. |

**Critical for the chat widget specifically:**

The root `CanvasPanel` of `WBP_ModChat` must default to
`HitTestInvisible` (not Visible, not Collapsed):

- `Collapsed` → prevents Lua from showing it.
- `Visible` → blocks mouse clicks on the menu underneath the
  chat region.
- `HitTestInvisible` → renders, doesn't intercept menu clicks.

When the chat needs mouse interaction (e.g., **scrolling the
history**), it must upgrade from `HitTestInvisible (3)` to
`SelfHitTestInvisible (4)`. The difference is critical:
`HitTestInvisible` blocks ALL descendant widgets from receiving
mouse events; `SelfHitTestInvisible` only blocks the widget
itself, allowing children (the ScrollBox) to receive scroll
input.

In compact / passive mode, downgrade back to `HitTestInvisible`
to prevent accidental mouse capture.

### BP function name resolution

UE4SS Lua resolves Blueprint functions by their **internal
name**, which matches the editor display name **with spaces
removed**. A BP function displayed as `"Open Input"` must be
called as `widget:OpenInput()` from Lua. A mismatch causes
`nullptr` errors because UE4SS wraps a null UFunction.

Also documented in
[`ue4ss-version-and-gotchas.md` → "BP function name resolution"](./ue4ss-version-and-gotchas.md#4-bp-function-name-resolution-display-name-without-spaces).

## GameInstance persistence (the persistent root)

`GameInstance_Base_C` persists across **ALL** map loads. Widgets
added to its viewport persist too. This is *the* mechanism that
makes the OSPlus chat widget survive lobby ↔ match ↔ post-match
cycles without re-creation.

**Implications:**

- `WBP_ModChat` survives map transitions without re-creation.
- On map change, `chat.reset()` clears Lua state but the widget
  object stays alive.
- `ensureWidget()` re-finds the widget via
  `FindFirstOf("WBP_ModChat_C")` — fast and reliable because the
  instance has been alive since cold-start.
- **Must explicitly collapse the widget on map transitions** to
  prevent leftover-from-match visibility on the menu (and vice
  versa). The visibility toggle is a per-feature responsibility,
  not something the GameInstance handles for you.
- The duplicate-prevention check in ModActor's BeginPlay graph
  (see [§"BPModLoaderMod lifecycle → Duplicate prevention"](#duplicate-prevention))
  is what stops every map transition from layering a new widget
  on top.

## The game's own widget tree (for reference + hooking)

This section is *catalog-style reference* — what widgets exist
in OS's own UI. Useful when planning a feature that wants to
hook the game's behavior (e.g., "fire when this game widget
becomes visible") rather than ship its own.

### Persistent widgets (parented to `GameInstance_Base_C`)

```text
GameInstance_Base_C
├── WBP_SoftwareCursor_C          — custom cursor overlay
├── WBP_SoftwareCursorTextBeam_C  — cursor text beam effect
├── WBP_ModChat_C                 — OSPlus mod chat widget (THIS IS US)
├── Router_OutOfGame_C            — main UI router (out-of-game screens)
└── WBP_HomeHub_PC_C              — the main lobby hub
    ├── GroupMemberNameplateRight  (WBP_HomeHubGroupNameplate_C)
    ├── GroupMemberNameplateLeft   (WBP_HomeHubGroupNameplate_C)
    ├── PlayerNameplateCenter     (WBP_HomeHubGroupNameplate_C)
    ├── WBP_ReactionButtonPanel_C — emote / reaction buttons
    ├── PlayPanel                 (WBP_PlayPanel_C) — queue button
    ├── WBP_FitActorToRect_C      — 3D character model in hub
    ├── WBP_GroupInvitePanel_C    — party invite list
    ├── WBP_GameVersion_C         — version display
    └── TournamentAnnouncement    (WBP_TournamentAnnouncement_C)
```

### ScrollBox usage in OS's own UI

The game uses ScrollBox extensively across all phases. Useful
inventory if you ever want to hook the game's scrolling lists
(rather than ship your own ScrollBox-containing widget).

**Always loaded:**

- `WBP_SettingsHub_C:MainScrollBox` — settings screen
- `WBP_ReportPlayerModal_C:ScrollBox_0` — report player

**Menu-only (16 instances on menu):**

- `WBP_FriendChatModal_C:MessagesScrollBox` — DM chat message
  list
- `WBP_FriendChat_StartChatModal_C:ScrollBox_0` — chat start
  modal
- `WBP_SocialModal_C:ScrollBox_0`, `ContentScrollBox` —
  social / friends
- `WBP_GroupInvitePanel_C:InviteListContainer` — party invites
- `WBP_Store_C:Tabs_ScrollBox`, `ScrollBox_Description`,
  `ScrollBox_0` — store
- `WBP_CharacterLoreModal_C:MainScroll_1` — character lore
- `WBP_Menu_DailyLogin_C:ScrollBox_58` — daily login
- `WBP_VisualNovelTextMessageScene_C:MessageScrollBox` — visual
  novel

**Practice match (6 instances):**

- `WBP_TrainingSelectModal_C:ScrollBox_0` — training mode
  selection
- `WBP_InGameMobile_AbilityTooltipsModal_C:ScrollBox_3` —
  ability tooltips
- `WBP_StrikerSelect_ChoosePhases_C:ScrollBox_0` — striker
  select

**Online match (5 instances):**

- `WBP_CharacterSelectModal_C:ChoosePhase:ScrollBox_0` — live
  character select
- Plus persistent ones from above

(Source: F9 widget-tree dump, original KB.)

## Cross-references

- **Why UMG-only — engine reasoning:** [`overview.md` → "UMG-only HUD"](./overview.md#umg-only-hud)
- **Where to put cooked widgets so the game loads them:** [`setup.md` → "UE editor project layout"](./setup.md#ue-editor-project-layout-your-machine-for-cooking)
- **The INI lines that prevent the ScrollBox crash:** [`setup.md` → "DefaultEngine.ini"](./setup.md#defaultengineini)
- **`RegisterHook`, `FindFirstOf`, etc. (Lua API used here):** [`ue4ss-version-and-gotchas.md`](./ue4ss-version-and-gotchas.md)
- **Mod-asset folder layout (one-mod-one-pak):** [`docs/UE_PROJECT_MIGRATION.md`](../UE_PROJECT_MIGRATION.md)
- **Lua-side OSPlus module split:** [`docs/architecture/mod-scripts.md`](../architecture/mod-scripts.md)
- **Player-side equivalent for "what UI elements exist":** [`docs/game/screens.md`](../game/screens.md), [`docs/game/in-match-hud.md`](../game/in-match-hud.md), [`docs/game/lobby.md`](../game/lobby.md)
- **Engine-side bridges to player UI concepts:** [`docs/glossary.md`](../glossary.md)
- **Sibling docs index:** [`docs/engine/README.md`](./README.md)

## Open questions

- **In-match widget tree.** The persistent + menu widget tree
  was captured via F3 dump; the in-match one wasn't. A dump
  during active gameplay would close this — useful for any
  feature that wants to hook in-match game UI.
- **`Router_OutOfGame_C`.** The router that drives screen
  transitions out-of-match. Hooking it is a high-leverage
  feature surface that hasn't been explored. Could it be used
  to drive an OSPlus screen overlay? **TBD.**
- **The game's existing notification / toast system.** OS
  surfaces notifications via some persistent widget cluster
  (level-up, friend-online, mission-complete). Whether OSPlus
  could piggyback on it is open. **TBD.**
- **Online-match HUD class name.** Documented for
  `HUD_Practice_C` and `HUD_Menu_C`; the online equivalent is
  not catalogued here.
- **Material setup for non-screen-space materials.** The
  documented material patterns are for screen-space sprite
  use cases (the prototype ping system). World-space lit
  materials would need a different pattern; not investigated
  for OSPlus.
