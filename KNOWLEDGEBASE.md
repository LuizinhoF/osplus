# Omega Strikers Modding — Knowledgebase

Everything learned through trial and error while building the custom ping system mod.
This document is the single source of truth for "how things work" in this game's modding context.

---

## Game Engine Facts

- **Engine**: Unreal Engine 5.1 (built with UE 5.1.0 or 5.1.1)
- **Game modules**: `Prometheus` (gameplay), `OdyUI` (UI framework)
- **Rendering**: DX11 at runtime (DX12 may be available but shaders must target SM5)
- **UI system**: UMG widgets via `OdyUI.OdyHUD` with a `UIRouter` — the game does NOT use Canvas-based HUD drawing

## Game Paths

| What | Path |
|------|------|
| Game install | `F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\` |
| Game executable | `Binaries\Win64\OmegaStrikers-Win64-Shipping.exe` |
| UE4SS root | `Binaries\Win64\ue4ss\` |
| Mod scripts | `ue4ss\Mods\OSPlus\scripts\` |
| Pak directory | `Content\Paks\` |
| Mod pak | `Content\Paks\CustomPings_P.pak` |
| UE project | `F:\Omegamod\OmegaStonkers\` |
| Cooked content | `F:\Omegamod\OmegaStonkers\Saved\Cooked\Windows\OmegaStonkers\Content\` |

## UE Project Settings (Critical)

These settings in the UE project are required for materials to render correctly in-game.

### DefaultEngine.ini
```ini
[Core.System]
CanUseUnversionedPropertySerialization=False  # CRITICAL — without this, complex widgets (ScrollBox, etc.) crash on load

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

### DefaultGame.ini
```ini
[/Script/UnrealEd.ProjectPackagingSettings]
bShareMaterialShaderCode=False
bSharedMaterialNativeLibraries=False
```

**Why**: `bShareMaterialShaderCode=False` forces shader bytecode to be embedded directly in each material's `.uasset` file. Without this, shaders go into a separate ShaderArchive that may not load correctly in the game.

---

## HUD System — What Works and What Doesn't

### The HUD class hierarchy (Practice mode)
```
HUD_Practice_C (Blueprint, 2 UFunctions)
  └─ PMHUDBase (/Script/Prometheus, 2 UFunctions: AddOffscreenIndicator, RemoveOffscreenIndicator)
      └─ OdyHUD (/Script/OdyUI, 2 UFunctions: OnUIRouterCreated, GetUIRouter)
          └─ AHUD (/Script/Engine, 29 UFunctions including DrawRect, DrawText, ReceiveDrawHUD, etc.)
              └─ AActor (/Script/Engine, 134 UFunctions including ReceiveTick)
                  └─ UObject
```

### ReceiveDrawHUD does NOT fire
- `ReceiveDrawHUD` is a `BlueprintImplementableEvent` — it only fires if a Blueprint subclass implements it
- The game's HUD Blueprint (`HUD_Practice_C`) does NOT implement it
- The C++ class (`OdyHUD` or `PMHUDBase`) overrides `DrawHUD()` in C++ without calling `Super::DrawHUD()`, so the event is never dispatched
- Hooking `/Script/Engine.HUD:ReceiveDrawHUD` registers successfully but the callback never fires

### Canvas drawing functions are never called
- `DrawRect`, `DrawText`, `DrawLine`, `DrawTexture`, `DrawMaterial`, etc. on AHUD are never called by the game
- The game uses UMG widgets exclusively — Canvas is never set up during gameplay

### What DOES work for UI
- **Widget Blueprints (UMG)**: Create a `UserWidget` Blueprint in the UE project, cook it, pak it, load from Lua
- **World-space actors**: Spawn `BP_PingMarker` actors for in-world visuals (proven working)

---

## Asset Loading — Proven Pattern

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

### Loading a Blueprint class
```lua
-- For Blueprint classes, try loading BP_Name_C (the generated class)
local arh = StaticFindObject("/Script/AssetRegistry.Default__AssetRegistryHelpers")
local assetData = {
    ["PackageName"] = UEHelpers.FindOrAddFName("/Game/CustomPings/VFX/BP_PingMarker"),
    ["AssetName"] = UEHelpers.FindOrAddFName("BP_PingMarker_C"),
}
local cls = arh:GetAsset(assetData)

-- Fallback: load the Blueprint, then get .GeneratedClass
local assetData2 = {
    ["PackageName"] = ...,
    ["AssetName"] = UEHelpers.FindOrAddFName("BP_PingMarker"),  -- without _C
}
local bp = arh:GetAsset(assetData2)
local cls = bp.GeneratedClass

-- Last resort: StaticFindObject with full path
local cls = StaticFindObject("BlueprintGeneratedClass /Game/CustomPings/VFX/BP_PingMarker.BP_PingMarker_C")
```

---

## Actor Spawning — Proven Pattern

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

-- Destroy
actor:K2_DestroyActor()
```

---

## Material Setup — Lessons Learned

### M_PingSprite (Master Material)
- **Material Domain**: Surface
- **Blend Mode**: Translucent
- **Shading Model**: Unlit
- **Two Sided**: checked
- **Graph**: `TextureSample(PingIcon).RGB * PingColor.RGB` → Emissive Color, `TextureSample(PingIcon).A * PingColor.A` → Opacity

### Material Instance overrides (each MI_PingSprite_*)
Must enable **Material Property Overrides** for:
- Blend Mode → Translucent
- Shading Model → Unlit
- Two Sided → override checkbox ON, actual value OFF (unchecked)

### Common material bugs
| Symptom | Cause | Fix |
|---------|-------|-----|
| Black squares | Shader incompatibility (SM6 vs SM5) or missing shader archives | Set `bShareMaterialShaderCode=False`, target SM5/DX11 |
| Invisible/transparent | Alpha channel multiplied by 0 in material graph | Verify `PingIcon.A * PingColor.A` wiring to Opacity is correct |
| White squares | Material not assigned | Check `meshComp:SetMaterial(0, mat)` is called with valid material |

---

## Pak Packaging

### Script: `package_pak.ps1`
- Uses `UnrealPak.exe` from `F:\UE_5.1\Engine\Binaries\Win64\`
- Input: cooked content from `F:\Omegamod\OmegaStonkers\Saved\Cooked\Windows\OmegaStonkers\Content\CustomPings\`
- Output: `CustomPings_P.pak` in the game's `Content\Paks\` directory
- The `_P` suffix is important — it tells UE to mount this pak after the base game paks

### What to include
- All files under `CustomPings/` from cooked content
- Skip: `ShaderArchive-Global`, `ShaderAssetInfo-Global`, `HLOD` files

### After cooking & paking
Always restart the game fully — "Reload All Mods" does NOT reload pak files.

---

## UE4SS Lua API — Key Functions

### Lifecycle hooks
| Function | When it fires |
|----------|---------------|
| `RegisterLoadMapPostHook(cb)` | After any map loads |
| `RegisterBeginPlayPostHook(cb)` | After any actor's BeginPlay |
| `NotifyOnNewObject(className, cb)` | When any instance of the class is constructed |
| `RegisterHook(funcPath, cb)` | Before/after a UFunction executes |
| `RegisterKeyBind(keyCode, cb)` | On key press (game must be focused) |

### Execution
| Function | Behavior |
|----------|----------|
| `ExecuteInGameThread(cb)` | Run code on game thread (required for UObject operations from keybinds) |
| `ExecuteWithDelay(ms, cb)` | Run code after delay (on game thread) |
| `LoopInGameThreadWithDelay(ms, cb)` | Repeating loop on game thread (preferred) |
| `LoopAsync(ms, cb)` | Repeating loop (DEPRECATED, use above) |

### Object lookup
| Function | Returns |
|----------|---------|
| `StaticFindObject(path)` | Single UObject by full path |
| `FindFirstOf(className)` | First instance of class (short name only) |
| `FindAllOf(className)` | Table of all instances (short name only) |
| `LoadAsset(path)` | Load an asset (must be on game thread) |

### Class introspection
```lua
local cls = obj:GetClass()
cls:ForEachFunction(function(func)
    local name = func:GetFullName()
    local flags = func:GetFunctionFlags()
end)
local super = cls:GetSuperStruct()  -- parent class
```

### Hook registration
```lua
-- /Script/ prefix = pre-hook (fires BEFORE the function)
RegisterHook("/Script/Engine.HUD:ReceiveDrawHUD", function(Context, SizeX, SizeY)
    local hud = Context:get()
end)

-- Non-/Script/ prefix = post-hook (fires AFTER)
RegisterHook("/Game/MyBP.MyBP_C:MyFunc", function(Context)
    local self = Context:get()
end)
```

### FVector creation
```lua
local UEHelpers = require("UEHelpers")
local kml = UEHelpers.GetKismetMathLibrary()
local vec = kml:MakeVector(x, y, z)
local rot = kml:MakeRotator(roll, pitch, yaw)
```

---

## Common Pitfalls

1. **Mod not updating**: Always copy ALL `.lua` files to the game's `Mods/OSPlus/scripts/` folder after editing. The source copy in the project repo is NOT what the game reads.

2. **"Reload All Mods" limitations**: Reloading mods re-runs Lua scripts but does NOT reload `.pak` files. After cooking/paking, a full game restart is required.

3. **Keybind conflicts**: Check that your keybind doesn't conflict with the game's controls. The game uses G for its own emote wheel.

4. **pcall everything**: UE4SS Lua calls to engine functions can crash if objects are invalid. Always wrap in `pcall()` and check `IsValid()`.

5. **Game thread requirement**: Most UObject operations must run on the game thread. Keybind callbacks run on the input thread — wrap engine calls in `ExecuteInGameThread()`.

6. **Hook parameters are wrapped**: Parameters in `RegisterHook` callbacks are `RemoteUnrealParam` — call `:get()` to unwrap them.

7. **Blueprint events vs native functions**: `RegisterHook` on a BlueprintImplementableEvent (like `ReceiveDrawHUD`, `ReceiveTick`) only fires if the Blueprint actually implements the event. Just because the UFunction exists doesn't mean it's called.

8. **Lua version is 5.4+**: UE4SS uses modern Lua. `math.atan2` does NOT exist -- use `math.atan(y, x)` instead (two-argument form). Similarly, integer division uses `//` not `math.floor(a/b)`.

9. **Widget creation**: `WidgetBlueprintLibrary::Create` expects 4 params (WorldContext, WidgetClass, OwningPlayer, WidgetName). Use `StaticConstructObject(widgetClass, playerController, FName("name"))` instead -- it's simpler and proven working.

10. **Lua local function ordering**: If function A calls function B, and both are `local function`, B must be defined before A — or forward-declare B with `local B` at the top and assign later with `B = function(...)`. Otherwise A captures a nil upvalue.

11. **UE4SS has no networking**: No HTTP, WebSocket, or socket support in Lua. Use file-based IPC (`io.open`) with an external sidecar process for networking.

12. **PlaySound2D requires all 8 params**: `UGameplayStatics:PlaySound2D(world, sound, vol, pitch, startTime, nil, nil, true)` — UE4SS does not support default parameter values, all must be passed explicitly.

---

## Lua Module Architecture (v11+)

The mod is split into focused modules under `scripts/`:

| Module | Responsibility |
|--------|---------------|
| `main.lua` | Entry point: wires modules together, registers keybinds, starts animation loop |
| `config.lua` | All constants: colors, timing, paths, keybinds, ping type definitions |
| `log.lua` | Logging to console and file, `try()` wrapper, `safeFullName()` |
| `utils.lua` | UE math helpers: `makeVec`, `makeRot`, `getPlayerController`, `getWorld` |
| `assets.lua` | Asset discovery and loading: materials, BP classes, SFX, widget class |
| `pings.lua` | Ping spawning, animation math, position helpers, SFX playback |
| `wheel.lua` | Radial wheel widget: creation, show/hide, cursor positioning, selection |
| `ipc.lua` | File-based IPC: outbox writing, inbox reading, tick polling |
| `json.lua` | Minimal JSON encode/decode for flat objects |

Cross-module dependencies are wired via callbacks in `main.lua`:
- `pings.onPingFired` -> `ipc.writePingToOutbox` (local ping fires broadcast it)
- `ipc.spawnRemotePing` -> `pings.spawn` (remote pings get rendered locally)

---

## Network Relay Architecture

### Overview
Pings sync between players via a three-part system:
- **Lua mod** writes/reads JSONL files in `%LOCALAPPDATA%\OSPlus\`
- **Node.js sidecar** (local) bridges file IPC to WebSocket
- **Node.js relay server** (remote) broadcasts messages within rooms

### IPC Files
| File | Writer | Reader | Purpose |
|------|--------|--------|---------|
| `outbox.jsonl` | Lua mod | Sidecar | Outgoing pings to broadcast |
| `inbox.jsonl` | Sidecar | Lua mod | Incoming pings from other players |

### Message format
```json
{"type":"ping","key":"DANGER","x":1234.5,"y":678.9,"z":0.0,"ts":1712345678}
```

### Running the system
```bash
# Terminal 1: Relay server
cd server && node index.js

# Terminal 2: Sidecar client
cd sidecar && node index.js ws://localhost:3000 ROOMCODE
```

### Key design decisions
- File-based IPC adds ~30-50ms overhead (acceptable for pings)
- Sidecar uses `fs.watchFile` with 50ms polling (chokidar v4 is ESM-only, incompatible with CommonJS)
- Lua polls inbox every ~90ms (3 animation ticks at 30ms/tick)
- `isRemote` flag on `spawnPingVisual()` prevents re-broadcasting received pings

## Flipbook Animation (Sprite Sheets)

### Material setup
- Replace `TextureSampleParameter2D` with `TextureObjectParameter` for the Flipbook's Texture input
- Flipbook node takes Number of Rows and Number of Columns as **input pins** (wire Constant or Scalar Parameter nodes)
- `Time` node multiplied by a constant controls playback speed (1.0 = one cycle/sec)
- Use Scalar Parameters for Rows/Columns so material instances can set 1x1 (static) or 4x4 (animated)

### Sprite sheet requirements
- Power-of-2 textures preferred (2048x2048, 4096x4096) but non-power-of-2 works fine
- 16 frames (4x4 grid) is a good sweet spot for VFX animations
- UE Editor material preview only animates with Realtime Preview enabled

---

## Omega Strikers — Game Internals

### Engine & Modules

| Property | Value |
|----------|-------|
| Engine version (runtime) | UE 5.1.0 (confirmed via sentry crash metadata) |
| UE editor (modding) | 5.1.1 |
| Gameplay module | `Prometheus` — all core game logic, characters, game modes |
| UI module | `OdyUI` — widget framework, `OdyHUD`, `UIRouter` |
| Internal project name | `OmegaStrikers` |
| Shipping config | `Shipping`, DX11 / SM5 |

### Maps

| Map | Context | Path |
|-----|---------|------|
| MainMenuMap | Lobby, menus, social, queue | `/Game/Prometheus/Maps/MainMenuMap/MainMenuMap` |
| GameMapPractice | Tutorial / practice mode | `/Game/Prometheus/Maps/GameMap/GameMapPractice` |
| GameMapAhtenCity | Online match (one of several arenas) | `/Game/Prometheus/Maps/GameMap/GameMapAhtenCity` |

Other arena maps likely exist under `/Game/Prometheus/Maps/GameMap/` but have not been catalogued yet.

### Backend Ecosystem — Odyssey's "Prometheus" API

**Naming note.** "Prometheus" refers to *two* things in the Omega Strikers universe, and both are Odyssey-chosen:

1. **The UE client module** (`Prometheus` — see Engine & Modules above). Game-side UObjects are prefixed `PM*` (`PMIdentitySubsystem`, `PMPlayerPublicProfile`, `PMPlayerModel`, etc.) and gameplay content lives under `/Game/Prometheus/...`.
2. **Odyssey's game backend API** — a separate JWT-authenticated HTTP API the client talks to. The community named it "Prometheus" because schema/ID naming from the client module leaks into the API's responses (e.g. every player's canonical ID hex string is the same value exposed as `PMPlayerPublicProfile.PlayerId` — same namespace).

Both meanings are active. In community tooling, "Prometheus" almost always means the backend API.

**The backend API is not publicly documented by Odyssey.** Every Omega Strikers tracker in existence — [stats.omegastrikers.gg](https://stats.omegastrikers.gg/), [clarioncorp.net](https://clarioncorp.net/), [strikr.gg](https://strikr.gg/), [omegastrikers.stlr.cx](https://omegastrikers.stlr.cx/) — taps this same API via reverse-engineered endpoints. One community author (Strikr-GG) signed an NDA with Odyssey after reverse-engineering it. The broader community posture is "grey zone, not endorsed, not prosecuted."

**Auth:** JWT pair (`ODYSSEY_TOKEN` + `ODYSSEY_REFRESH_TOKEN`, per the Strikr-GG README). Tokens obtainable via:
- Live capture with Fiddler Classic while the game runs.
- Steam Ticket → Odyssey auth handshake (per Clarion docs; full guide not yet published as of 2026-04).

**What the API exposes** (per [Clarion's v2 `/players/<id>`](https://docs.clarioncorp.net/clarion-api/v2/players), which proxies Prometheus):
- Player metadata: 24-char hex Prometheus ID, username, region, cosmetic loadout IDs (logo, nameplate, emoticon, title), currentXp, online/offline status.
- Per-character aggregates (by `character` × `role` × `gamemode`): `games`, `wins`, `losses`, `mvp`, `knockouts`, `assists`, `saves`, `scores`.
- Rating per season: `rating`, `rank`, `wins`, `losses`, `games`, `masteryLevel`.
- Mastery totals: `currentLevel`, `currentLevelXp`, `totalXp`, `xpToNextLevel`.
- Per-match metadata (map, score, duration, timestamp, per-team rank delta) — drillable via a per-match endpoint.

**What the API does NOT expose — the OSPlus capture gap:**
- **Redirects** — no `redirects` field in any tracker's per-character or per-match response shape.
- Per-match event sequences (when goals scored, saves per match, action-by-action breakdown).
- In-match transient state (positions, action timing, duration-of-possession).
- Anything that happens during a match but isn't persisted to the backend.

**See also:** `docs/learnings/os-prometheus-api-ecosystem.md` (discovery diary).

### Per-match runtime data — what's reachable from Lua

The backend API (above) exposes career aggregates. The *client* exposes per-match transient state through a parallel set of objects. This section is the canonical "what to grep for" when a feature needs in-match observable data.

**`PMPlayerMatchSummary`** (`/Script/Prometheus.PMPlayerMatchSummary` ScriptStruct) — per-player per-match counter struct. Fields (offset / type):

| Offset | Field | Type | EOG stat # |
|---|---|---|---|
| 0x00 | `RedirectRock` | Int | 5 (Redirects) — **the canonical OSPlus capture target** |
| 0x04 | `PowerUpsPickedUpCount` | Int | 8 (PowerUps) |
| 0x08 | `HitRockIntoGoalArea` | Int | 6 (ShotsOnGoal) |
| 0x0C | `DamageDoneToPlayers` | Int | 7 (Damage) |

**`EPMEndOfGameStat`** enum — the full per-match stat universe surfaced at end-of-match:

```
None=0, Goals=1, Assists=2, Saves=3, KOs=4,
Redirects=5, ShotsOnGoal=6, Damage=7, PowerUps=8
```

`PMPlayerMatchSummary` covers 4 of those 9. The other 5 (Goals / Assists / Saves / KOs) live on a sibling structure — investigation pending. Most likely `PMPlayerState` (the C++ parent of `PlayerState_Game_C`) or another summary keyed off it. See `docs/learnings/os-runtime-data-model.md` → "Per-match runtime data".

**Other relevant runtime objects:**
- `PMEndOfGamePlayerUIData:Redirects : Struct` — EOG UI surface (probably wraps the same counter).
- `PMRockCharacter:LastRedirectKnockBack : Struct` — last redirect on the puck character itself. For per-event detail (vs. per-match aggregate), this is the per-redirect surface.
- `EKnockBackType::Redirect = 2` — redirects are classified knock-backs of type 2.

**Naming gotcha — the puck is internally called "Rock".** Future searches for the puck/ball actor should grep `Rock`, not `Ball` / `Puck` / `Core`. The `PMRockCharacter` class is the puck.

**Open questions** (Pass-4 candidates for `in-game-profile-mvp`):
- How does a `PMPlayerMatchSummary` instance map back to its player? (Held by `PMPlayerState`? An array on `PMGameState`? Keyed by `PlayerId`?)
- Where do Goals / Assists / Saves / KOs live? (Likely `PMPlayerState` or sibling.)
- Lifetime: persists across match-end, replaced per-match, or held for the session?

**See also:** `docs/learnings/os-runtime-data-model.md` (the runtime data model in full).

### Game Lifecycle & Phase Detection

The game progresses through distinct phases. Each phase has a unique combination of classes that can be queried from Lua:

#### Main Menu / Lobby
```
GameStateBase         → GameStateBase (engine base class)
GameModeBase          → GameMode_Menu_C
PlayerController      → PlayerController_Menu_C
PlayerState           → PlayerState (engine base class)
Pawn                  → NONE
GameInstance          → GameInstance_Base_C (persists across ALL maps)
```
- **Detection**: `FindFirstOf("PlayerState_Game_C")` returns nil
- **Key fact**: No game-specific PlayerState or Pawn exists

#### Character Select (online match loaded, picking strikers)
```
GameStateBase         → GameState_Game_C
PlayerController      → PlayerController_Game_C
PlayerState           → PlayerState_Game_C
Pawn                  → NONE (not spawned yet)
```
- **Detection**: `PlayerState_Game_C` exists BUT `PlayerController.Pawn` is nil
- **Key fact**: Map has loaded (e.g. GameMapAhtenCity) but player has no Pawn

#### Active Gameplay (in-match, controlling striker)
```
GameStateBase         → GameState_Game_C
PlayerController      → PlayerController_Game_C
PlayerState           → PlayerState_Game_C
Pawn                  → Character class (e.g. C_FlexibleBrawler_C, C_NimbleBlaster_C)
```
- **Detection**: `PlayerState_Game_C` exists AND `PlayerController.Pawn` is valid
- **This is the only phase where the mod chat should be visible/interactive**

#### Awakening Select (between rounds)
```
GameStateBase         → GameState_Game_C (same as gameplay)
PlayerState           → PlayerState_Game_C
Pawn                  → Still valid (character persists)
```
- **Detection**: Same as active gameplay — chat remains visible

#### Practice Mode
```
GameStateBase         → GameState_Tutorial_C
PlayerController      → PlayerController_Practice_C
PlayerState           → PlayerState_Game_C
Pawn                  → Character class
```
- **Detection**: `PlayerState_Game_C` + valid Pawn (same logic works)

#### Match Detection Function (proven working)
```lua
local function isInMatch()
    local ok, obj = pcall(FindFirstOf, "PlayerState_Game_C")
    if not ok or not obj or not obj:IsValid() then return false end
    local pc = utils.getPlayerController()
    if not pc or not pc:IsValid() then return false end
    local pawn = pc.Pawn
    return pawn ~= nil and pawn:IsValid()
end
```

### Class Hierarchy Reference

#### Core Framework
```
/Game/Prometheus/Blueprints/Core/
├── GameInstance_Base          → persists across all maps, owns persistent widgets
├── GameModes/
│   └── GameMode_Menu         → menu-only game mode
├── GameState_Game             → online match state
├── GameState_Tutorial         → practice mode state
├── PlayerController_Menu      → menu navigation
├── PlayerController_Game      → online match input
├── PlayerController_Practice  → practice mode input
└── PlayerState_Game           → per-player match state
```

#### Characters (confirmed via F10 dump + runtime Pawn inspection)

| Internal Name | Striker Name | Confirmed |
|--------------|-------------|-----------|
| FlexibleBrawler | Juliette | Yes (Pawn observed in practice) |
| NimbleBlaster | Drek'ar | Yes (used in online match) |
| AngelicSupport | | |
| Asher | Asher | Likely (folder = name) |
| ChaoticRocketeer | | |
| Chibi | | |
| CleverSummoner | | |
| DrumOni | | |
| Dubu | Dubu | Likely (folder = name) |
| EDMOni | | |
| EmpoweringEnchanter | | |
| Estelle | Estelle | Likely (folder = name) |
| FlashySwordsman | | |
| GravityMage | | |
| Healer | | |
| HulkingBeast | | |
| MagicalPlaymaker | | |
| ManipulatingMastermind | | |
| RockOni | | |
| Shieldz | | |
| SpeedySkirmisher | | |
| StalwartProtector | | |
| TempoSniper | | |
| TheAstronaut | | |
| UmbrellaUser | | |
| WhipFighter | | |

Characters follow the pattern `C_<InternalName>` → `C_<InternalName>_C` at runtime.
Utility folders: `Shared/` (common abilities like GA_Rescue), `Concept/`, `Full/`, `Timeline/`, `X/`, `CloseUp/`, `GoalScore/`, `GradientGoal/` (art/VFX, not playable characters).

#### HUD Hierarchy
```
HUD_Menu_C (menu) / HUD_Practice_C (practice)
  └─ PMHUDBase (/Script/Prometheus)
      └─ OdyHUD (/Script/OdyUI) — GetUIRouter(), OnUIRouterCreated()
          └─ AHUD (/Script/Engine)
```
- Game uses UMG exclusively — no Canvas drawing
- `ReceiveDrawHUD` never fires (not implemented in Blueprint, C++ doesn't call Super)
- All game UI goes through `OdyHUD` → `UIRouter` pattern

#### Key UFunctions (hookable)

**GameState_Game_C** (online match):
- `MatchPhaseChanged` — fires on phase transitions (char select → gameplay → intermission)
- `IntermissionPlayerDataChanged` — between rounds data update
- `MatchSummary` — end of match
- `SpawnGoalEffects` — goal scored
- `GetPlayerMvpScore`, `GetMvpScoreRoundMultiplier`
- `TryPlayMVPTheme`, `PlayPowerUpPickedUpAudio`
- `Try Set Power Orb Based On Map`, `GetGoalExplosion`

**GameState_Tutorial_C** (practice):
- `SwitchToNextPowerUp`, `Set Random Power Orb`
- `MatchPhaseChanged`, `SpawnGoalEffects`

**PlayerState_Game_C**:
- `DamageChanged` — damage dealt/received tracking
- `SpawnEffectsOnCharacterKnockedOut` — KO event
- `OnPlayerLevelMilestoneChanged` — level up during match
- `IncrementOrbTracking`, `ResetOrbTracking`
- `TryResetEnergy`, `TryUnlockSpecial`, `TryPlayLevelUpFX`
- `TryTriggerFXPackage`, `TryApplyFXPackageGameplayEffect`
- `FaceOffAddGoalieStrike`

**PlayerController_Game_C** (online):
- `StrikeReleased`, `StrikeDragged` — strike input events
- `MatchIntensityChanged` — match intensity system
- `ShowMoveToIndicator`, `OnMoveToPressed`
- `AddStealthBorder` — stealth visual effect
- `HoldToStrikeModeEnabledChanged`

**PlayerController_Practice_C**:
- `On Match Phase Changed`

**GameInstance_Base_C**:
- `ReceiveInit`, `ReceiveShutdown`

#### UI Widget Tree (menu — from F3 dump)

All persistent widgets live under `GameInstance_Base_C`:
```
GameInstance_Base_C
├── WBP_SoftwareCursor_C          — custom cursor overlay
├── WBP_SoftwareCursorTextBeam_C  — cursor text beam effect
├── WBP_ModChat_C                 — OUR mod chat widget
├── Router_OutOfGame_C            — main UI router (out-of-game screens)
└── WBP_HomeHub_PC_C              — the main lobby hub
    ├── GroupMemberNameplateRight  (WBP_HomeHubGroupNameplate_C)
    ├── GroupMemberNameplateLeft   (WBP_HomeHubGroupNameplate_C)
    ├── PlayerNameplateCenter     (WBP_HomeHubGroupNameplate_C)
    ├── WBP_ReactionButtonPanel_C — emote/reaction buttons
    ├── PlayPanel                 (WBP_PlayPanel_C) — queue button
    ├── WBP_FitActorToRect_C      — 3D character model in hub
    ├── WBP_GroupInvitePanel_C    — party invite list
    ├── WBP_GameVersion_C         — version display
    └── TournamentAnnouncement    (WBP_TournamentAnnouncement_C)
```

#### ScrollBox Usage in Game (confirmed via F9 dump)

The game uses ScrollBox extensively across all phases:

**Always loaded:**
- `WBP_SettingsHub_C:MainScrollBox` — settings screen
- `WBP_ReportPlayerModal_C:ScrollBox_0` — report player

**Menu-only (16 instances on menu):**
- `WBP_FriendChatModal_C:MessagesScrollBox` — **DM chat message list**
- `WBP_FriendChat_StartChatModal_C:ScrollBox_0` — chat start modal
- `WBP_SocialModal_C:ScrollBox_0`, `ContentScrollBox` — social/friends
- `WBP_GroupInvitePanel_C:InviteListContainer` — party invites
- `WBP_Store_C:Tabs_ScrollBox`, `ScrollBox_Description`, `ScrollBox_0` — store
- `WBP_CharacterLoreModal_C:MainScroll_1` — character lore
- `WBP_Menu_DailyLogin_C:ScrollBox_58` — daily login
- `WBP_VisualNovelTextMessageScene_C:MessageScrollBox` — visual novel

**Practice match (6 instances):**
- `WBP_TrainingSelectModal_C:ScrollBox_0` — training mode selection
- `WBP_InGameMobile_AbilityTooltipsModal_C:ScrollBox_3` — ability tooltips
- `WBP_StrikerSelect_ChoosePhases_C:ScrollBox_0` — striker select

**Online match (5 instances):**
- `WBP_CharacterSelectModal_C:ChoosePhase:ScrollBox_0` — live character select
- Plus persistent ones from above

### BPModLoaderMod Lifecycle

This is how our Blueprint mod assets get loaded into the game:

1. **Startup**: BPModLoaderMod scans `Content/Paks/LogicMods/` for `.pak` files
2. **Registration**: Creates a config for each pak: `AssetPath = /Game/Mods/<ModName>/ModActor`, `AssetName = ModActor_C`
3. **Map load**: On every `RegisterLoadMapPostHook`, calls `LoadMods(World)`
4. **Loading**: Uses `AssetRegistryHelpers:GetAsset(assetData)` to resolve the Blueprint class from the pak
5. **Spawning**: Calls `World:SpawnActor(ModClass, {}, {})` to instantiate the ModActor
6. **Widget creation**: ModActor's BeginPlay event graph creates `WBP_ModChat` and adds it to viewport

**Timing**: The `Loading mod:` log line appears ~27s after game start (first map load). The `Actor:` confirmation follows immediately if successful. If no `Actor:` line appears, the crash occurred during `SpawnActor` → asset deserialization.

**Duplicate prevention**: ModActor Blueprint includes `Get All Widgets Of Class(WBP_ModChat)` + `Array.IsEmpty` check before creating the widget.

### Widget System — What Works in Cooked Paks

| Widget Type | Status | Notes |
|-------------|--------|-------|
| CanvasPanel | Working | Root container, use as widget root |
| SizeBox | Working | Size constraints, MaxDesiredHeight for clipping |
| Border | Working | Background color/padding |
| VerticalBox | Working | Vertical layout |
| HorizontalBox | Working | Horizontal layout |
| TextBlock | Working | Static text display |
| EditableText | Working | Text input (NOT EditableTextBox) |
| ScrollBox | Working | Requires `CanUseUnversionedPropertySerialization=False` in `[Core.System]` — without it, crashes on pak deserialization due to schema drift between editor and game builds. With versioned serialization, works natively in Blueprint |

### EditableText (ChatInput) — Known Bugs & Workarounds

| Issue | Cause | Workaround |
|-------|-------|------------|
| `SetText("")` doesn't clear | UE 5.1.1 Slate bug — empty string reverts | Use `SetText(FText(" "))` (space), trim on Lua side |
| `OnTextCommitted` fires twice on Enter | Engine behavior | Blueprint clears `PendingMessage` after first read |
| `Get Owning Player` returns null | Widget added to GameInstance, not level player | Use `Get Player Controller 0` instead |
| Controls locked after chat | `Set Input Mode Game Only` doesn't recapture mouse | Use `Set Input Mode Game And UI` + `Set Focus to Game Viewport` |
| Empty Enter doesn't close chat | Space workaround trims to "", early return skipped `close()` | Call `close()` before the empty-string check |

### Input Mode Management

The chat system requires switching between game and UI input modes:

**Opening chat (OpenInput Blueprint function):**
1. Set ChatInput visibility → Visible
2. `Set Input Mode UI Only` (target: `Get Player Controller 0`)
3. `Set User Focus` on ChatInput

**Closing chat (CloseInput Blueprint function):**
1. Set ChatInput visibility → Collapsed
2. `Set Input Mode Game And UI` (target: `Get Player Controller 0`)
3. `Set Focus to Game Viewport`

### Visibility Constants (ESlateVisibility)

| Value | Name | Behavior |
|-------|------|----------|
| 0 | Visible | Renders and receives clicks |
| 1 | Collapsed | Hidden, takes no layout space |
| 2 | Hidden | Hidden but takes layout space |
| 3 | HitTestInvisible | Renders but passes clicks through (and children) |
| 4 | SelfHitTestInvisible | Renders, self doesn't receive clicks but children can |

**Widget default visibility**: Root CanvasPanel in WBP_ModChat must default to `Hit Test Invisible` (not Visible, not Collapsed). Collapsed prevents Lua from showing it. Visible blocks mouse clicks on menu.

**HitTestInvisible vs SelfHitTestInvisible — critical for mouse interaction**:
`HitTestInvisible (3)` on a UserWidget blocks ALL descendant widgets from receiving mouse events (scroll, click, drag). `SelfHitTestInvisible (4)` only blocks the widget itself — children can still receive mouse input. When the chat needs mouse interaction (e.g. scrolling the history), Self must be upgraded from `HitTestInvisible` to `SelfHitTestInvisible`. In compact/passive mode, `HitTestInvisible` is correct to prevent accidental mouse capture.

**BP function naming**: UE4SS Lua resolves Blueprint functions by their internal name, which matches the display name **without spaces**. A BP function displayed as "Open Input" must be called as `widget:OpenInput()` in Lua. A mismatch causes `nullptr` errors because UE4SS wraps a null UFunction.

### GameInstance Persistence

`GameInstance_Base_C` persists across ALL map loads. Widgets added to the GameInstance's viewport persist too. This means:
- WBP_ModChat survives map transitions without re-creation
- On map change, `chat.reset()` clears Lua state but the widget object stays alive
- `ensureWidget()` re-finds it via `FindFirstOf("WBP_ModChat_C")`
- Must explicitly collapse widget on map transitions to prevent menu visibility

---

## Known Unknowns / Investigation Needed

### Game Architecture
- [ ] Full list of arena maps (only AhtenCity confirmed for online play)
- [x] ~~All character internal names~~ — 26 characters catalogued, 3 striker names confirmed
- [ ] Remaining striker name ↔ internal name mappings (need to play each character and check Pawn class)
- [ ] Game phase transitions — `MatchPhaseChanged` fires, but what are the phase enum values?
- [ ] What triggers map loads? Is there a `MatchManager` or similar coordinator?
- [ ] `GameState_Game_C` readable properties — round number, score, team data, match timer (UFunctions known, but property fields need probing)

### UI System
- [x] ~~What widgets does the game's own HUD use?~~ — full widget tree captured for menu
- [x] ~~How does the game's DM/chat popup work?~~ — `WBP_FriendChatModal_C:MessagesScrollBox` confirmed
- [ ] `Router_OutOfGame_C` — how does it manage screen transitions? Could we hook into it?
- [ ] Game's existing notification/toast system — can we piggyback on it?
- [ ] In-match widget tree (F3 dump during active gameplay needed)

### Networking / Player Data
- [ ] Does the game expose any match ID, room ID, or lobby ID we can read?
- [x] ~~Can we read the player's display name?~~ — **SOLVED**: `PlayerState_Game_C.PlayerNamePrivate:ToString()` returns the display name (e.g. "Ispicas") in custom/real games. Returns hex ID in practice mode. Also visible in `WBP_CharacterNameplate_Base_C.PlayerNameRichText` and `WBP_CharacterSelectPlayerCard_C.PlayerName_Text` RichTextBlock widgets.
- [x] ~~Team assignment~~ — `TeamId` exists on PlayerState but returns UObject, needs further probing
- [ ] Can we read other players' PlayerStates? (F4 dump only found 1 PlayerState_Game_C per phase — might need FindAllOf)

### Player Identity Reference

**Three identifier namespaces — distinguish them:**

| Identifier | Shape | Stable? | Source | Who uses it |
|---|---|---|---|---|
| **SteamID** | 17-digit decimal (e.g. `76561198022185004`) | Yes, cross-session, cross-platform | `PMIdentitySubsystem:GetSteamId()` | Steam; OSPlus profile binding today |
| **Prometheus ID** | 24-char hex / MongoDB ObjectID (e.g. `6333a58673a37dc7cb11a7a7`) | Yes (assumed) | Game backend; appears as `PMPlayerPublicProfile.PlayerId` | Odyssey's backend API and every OS tracker as the canonical player key |
| **Display name** | Friendly, mutable string (e.g. `Ispicas`) | No — user-mutable | `PlayerState.PlayerNamePrivate` (after replication) | Human UI |

Three separate namespaces. A Prometheus ID cannot be derived from a SteamID (or vice versa) without the game backend. **If OSPlus ever wants to join its own captures against tracker-ecosystem aggregate stats, it needs the Prometheus ID** — every tracker keys off Prometheus, not Steam.

**Caveat: `PlayerState.PlayerNamePrivate` has three observed modes** — see `docs/learnings/playernameprivate-transient-account-id.md` and `docs/learnings/playernameprivate-machine-name-out-of-match.md`. During the replication window it carries the Prometheus ID as a hex string (the "account-ID" mode in those learnings); after replication it holds the display name; some out-of-match contexts briefly return the local Windows machine name.

**Individual reads:**
- **Display name in match**: `FindFirstOf("PlayerState_Game_C").PlayerNamePrivate:ToString()` → display name string (after replication; see caveats above)
- **SteamID**: `FindFirstOf("PMIdentitySubsystem"):GetSteamId()` → `76561198022185004`
- **Identity state**: `FindFirstOf("PMIdentitySubsystem"):GetIdentityState()` → `2` (Authenticated — enum semantics inferred from name, not confirmed by enum-dump)
- **PMPlayerPublicProfile**: `FindAllOf("PMPlayerPublicProfile")` returns ~100+ cached profiles of OTHER players (observed: 104 and 109 in two separate dumps). Each has `Username` (display name) and `PlayerId` (Prometheus ID). **The local player is NOT in this cache.**
- **PMPlayerModel**: Hosts the local-identity getters. Signatures (from the GUI Object Dumper, in-match):
  - `GetCachedMeResponseV1(out WasCached: Bool, out OutMeResponse: MeResponseV1)` — sync read of the local cache.
  - `GetCachedPlayerPublicProfile(out WasCached: Bool, out Profile: PlayerPublicProfile)` — sync read of an already-cached profile.
  - `GetDisplayNameV1(out WasSent: Bool, out OutRequestId: Str)` — **async**: returns a request ID; the actual response fires the `GetDisplayNameV1Completed` multicast delegate.
  - **`MeResponseV1` extends `PlayerPublicProfile`** (UE `ScriptStruct` inheritance via the dumper's `sps` field), so `OutMeResponse` carries every PlayerPublicProfile field — **`PlayerId` (Prometheus ID), `Username`, `LogoId`/`NameplateId`/`EmoticonId`/`TitleId`, `PlatformIds` struct, `MasteryLevel`, `CurrentPlatform` enum** — plus Me-only fields (`MatchmakingRegion`, `EulaNeeded`, `DiscordConnection`, etc.). One sync call → full local identity.
  - UE4SS calling convention: pass *placeholder* values for the output params (e.g. `model:GetCachedMeResponseV1(false, nil)`) and capture the return values. The Pass-2 error `UFunction expected 2 parameters, received 0` was UE4SS asking for the output slots, not "uncallable." Exact placeholder shape is build-dependent — see `docs/learnings/os-runtime-data-model.md` for the validation gap.
- **Practice mode caveat**: `PlayerNamePrivate` returns a hex Prometheus ID rather than the display name in practice mode. Only returns the display name in custom / real games.

### ScrollBox Crash — Root Cause & Resolution (SOLVED)

**Root cause**: Unversioned property serialization (`PKG_UnversionedProperties` flag `0x2000`). UE5 cooked assets serialize properties by schema index order by default — no property names are stored. If the game's `UScrollBox` class has even a single extra/reordered property compared to our editor build, the deserializer reads at wrong offsets and interprets garbage bytes as FName indices, causing the crash.

**Investigation timeline**:
1. **UE 5.1.1 (Epic launcher)**: ScrollBox crashes on `SpawnActor` — binary schema mismatch with the 5.1.0 game runtime
2. **UE 5.1.0 (built from source)**: Still crashes with `FName serialization error — index 33817088, valid range [0, 96)` — same root cause, the source build's ScrollBox schema still differs from Odyssey Interactive's custom 5.1.0 fork
3. **Binary analysis**: `ModActor` files were byte-identical between 5.1.0 and 5.1.1 (simple widgets serialize identically). The garbage FName index was NOT present in the files — the deserializer was reading at a wrong offset due to schema mismatch
4. **INI config attempt**: `bUnversionedPropertySerialization=False` under `[/Script/UnrealEd.CookerSettings]` — **had no effect** (wrong section, wrong key name)
5. **Source code analysis**: Found the actual setting in `UnversionedPropertySerialization.cpp:771` — it reads `[Core.System] CanUseUnversionedPropertySerialization` from `GEngineIni`

**Solution**: Add to `DefaultEngine.ini`:
```ini
[Core.System]
CanUseUnversionedPropertySerialization=False
```
This forces the cooker to embed property names in serialized data. The deserializer matches by name instead of by index, making assets tolerant to property layout differences. File size increases slightly (e.g. 7135 → 8567 bytes for WBP_ModChat) but all widgets including ScrollBox now load correctly.

**Key lesson**: Simple containers (CanvasPanel, VerticalBox, SizeBox, Border) happen to have identical schemas across UE 5.1.x variants, so they worked even with unversioned serialization. Complex widgets like ScrollBox have schema drift. Always cook with `CanUseUnversionedPropertySerialization=False` for mod assets.

### Audio
- [ ] Game's sound classes / sound mixes — can we play custom sounds without conflicting?
- [ ] Volume control — does the game's audio settings affect our custom `PlaySound2D`?

### Input
- [ ] Full list of game keybinds to avoid conflicts
- [ ] Does the game use Enhanced Input or legacy input?
- [ ] Can we read mouse position in world space without line traces?
