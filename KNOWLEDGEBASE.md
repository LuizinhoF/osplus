# Omega Strikers Modding — Knowledgebase

> **Migration in progress.** Per [ADR 0003](docs/decisions/0003-knowledge-substrate-structure.md),
> this monolithic doc is being decomposed into per-topic files
> under [`docs/engine/`](docs/engine/). Sections that have moved
> are stubbed (heading retained, body replaced with a redirect).
> Untouched sections remain canonical here until they too are
> migrated.
>
> **Where to start instead:**
>
> - New agent / first-time engine read → [`docs/engine/overview.md`](docs/engine/overview.md)
> - Engine ↔ player concept bridge → [`docs/glossary.md`](docs/glossary.md)
> - Full topic index + status table → [`docs/engine/README.md`](docs/engine/README.md)
>
> **Migrated so far:**
>
> - **Batch 1 (2026-05-01):** §"Game Engine Facts", §"Game Paths",
>   §"UE Project Settings (Critical)", §"HUD System", §"Asset
>   Loading", §"Actor Spawning", §"Material Setup", §"Pak
>   Packaging", §"UE4SS Lua API", §"Common Pitfalls", §"Flipbook
>   Animation", and the "Engine & Modules" + "Maps" sub-sections of
>   §"Omega Strikers — Game Internals".

This was originally the single source of truth for "how things
work" in this game's modding context. Most of that knowledge has
moved or is moving to [`docs/engine/`](docs/engine/) per the
banner above. The historical context — *"everything learned
through trial and error while building the custom ping system
mod"* — explains why some of the early prototype-era patterns
(ping markers, sprite materials, `CustomPings_P.pak`) appear
throughout: that work *paid forward* the cooked-pak + UE4SS +
sidecar pipeline OSPlus runs on today.

---

## Game Engine Facts

> **Migrated → [`docs/engine/overview.md`](docs/engine/overview.md).**
> Specifically: ["The engine pin"](docs/engine/overview.md#the-engine-pin)
> and ["The two gameplay modules"](docs/engine/overview.md#the-two-gameplay-modules).
> Section retained as a stub so existing references still resolve.

---

## Game Paths

> **Migrated → [`docs/engine/setup.md` → "Game install layout"](docs/engine/setup.md#game-install-layout-players-machine).**
> The KB's prototype-era paths (`CustomPings_P.pak`, `OmegaStonkers`
> minus the ` 5.1` suffix) were updated to current OSPlus paths
> during migration. Section retained as a stub so existing
> references still resolve.

---

## UE Project Settings (Critical)

> **Migrated → [`docs/engine/setup.md` → "DefaultEngine.ini"](docs/engine/setup.md#defaultengineini)
> and [→ "DefaultGame.ini"](docs/engine/setup.md#defaultgameini).**
> Both INI files are documented in full, including the
> "schema-stability cluster" (the `CanUseUnversionedPropertySerialization`
> trap, with the wrong-key-name false-friend called out) and the
> "renderer cluster" (DX11 / SM5 requirements).
> Section retained as a stub so existing references still resolve.

---

## HUD System — What Works and What Doesn't

> **Migrated → [`docs/engine/widgets.md` → "The cooked-pak rendering model"](docs/engine/widgets.md#the-cooked-pak-rendering-model).**
> Specifically: ["HUD class hierarchy"](docs/engine/widgets.md#hud-class-hierarchy),
> ["ReceiveDrawHUD does NOT fire"](docs/engine/widgets.md#receivedrawhud-does-not-fire),
> ["Canvas drawing functions are never called"](docs/engine/widgets.md#canvas-drawing-functions-are-never-called),
> ["What DOES work for UI"](docs/engine/widgets.md#what-does-work-for-ui).
> The engine reasoning ("UMG-only HUD") also lives in
> [`docs/engine/overview.md` → "UMG-only HUD"](docs/engine/overview.md#umg-only-hud).
> Section retained as a stub so existing references still resolve.

---

## Asset Loading — Proven Pattern

> **Migrated → [`docs/engine/widgets.md` → "Asset loading from cooked paks"](docs/engine/widgets.md#asset-loading-from-cooked-paks).**
> Includes the `findAsset` helper, the three-pattern Blueprint
> class loading recipe, and the rationale for falling back through
> multiple path formats. KB's prototype-era examples
> (`/Game/CustomPings/VFX/BP_PingMarker`) were replaced with the
> current OSPlus equivalents (`/Game/Mods/OSPlus/Chat/WBP_ModChat`)
> during migration, with a note about the rename.
> Section retained as a stub so existing references still resolve.

---

## Actor Spawning — Proven Pattern

> **Migrated → [`docs/engine/widgets.md` → "Actor spawning from cooked paks"](docs/engine/widgets.md#actor-spawning-from-cooked-paks).**
> Section retained as a stub so existing references still resolve.

---

## Material Setup — Lessons Learned

> **Migrated → [`docs/engine/widgets.md` → "Material setup"](docs/engine/widgets.md#material-setup).**
> Includes the master material requirements, the material instance
> override pattern (with the "override checkbox ON, value OFF"
> trap explained), and the common material bugs table.
> Section retained as a stub so existing references still resolve.

---

## Pak Packaging

> **Migrated → [`docs/engine/setup.md` → "Pak packaging"](docs/engine/setup.md#pak-packaging).**
> The KB's reference to a `package_pak.ps1` script is from the
> prototype era (`CustomPings_P.pak`); the current canonical
> harness is [`ue-assets/package_logicmod.ps1`](../../ue-assets/package_logicmod.ps1)
> per [`.cursor/rules/harnesses.mdc`](../../.cursor/rules/harnesses.mdc).
> Section retained as a stub so existing references still resolve.

---

## UE4SS Lua API — Key Functions

> **Migrated → [`docs/engine/ue4ss-version-and-gotchas.md` → "The Lua API surface"](docs/engine/ue4ss-version-and-gotchas.md#the-lua-api-surface).**
> Includes the UE4SS 3.0.1 build pin (and trust-ranking for sources
> of truth), lifecycle hooks, execution helpers, object lookup,
> class introspection, `RegisterHook` patterns, and `FVector` /
> `FRotator` creation via UEHelpers.
> Section retained as a stub so existing references still resolve.

---

## Common Pitfalls

> **Migrated → [`docs/engine/ue4ss-version-and-gotchas.md` → "Common pitfalls"](docs/engine/ue4ss-version-and-gotchas.md#common-pitfalls).**
> All twelve pitfalls preserved with cross-references to the
> deeper UE4SS-3.0.1-specific known bugs (`ExecuteInGameThread` +
> callback-registry corruption is now its own dedicated entry).
> Section retained as a stub so existing references still resolve.

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

> **Migrated → [`docs/engine/widgets.md` → "Flipbook animation (sprite sheets)"](docs/engine/widgets.md#flipbook-animation-sprite-sheets).**
> Section retained as a stub so existing references still resolve.

---

## Omega Strikers — Game Internals

This H2 section is a container for several engine-side topics. As
each sub-section migrates to `docs/engine/`, it gets a redirect
stub here. The unmigrated sub-sections remain canonical until
they too move (per the migration banner at the top of this file).

### Engine & Modules

> **Migrated → [`docs/engine/overview.md`](docs/engine/overview.md).**
> Specifically: ["The engine pin"](docs/engine/overview.md#the-engine-pin)
> and ["The two gameplay modules"](docs/engine/overview.md#the-two-gameplay-modules).
> KB stated "UE editor (modding) 5.1.1" — this was *empirically
> wrong* (5.1.1 from launcher silently corrupts complex widgets;
> source-built 5.1.0 is the actual requirement). The migrated
> doc reflects the correction; see
> [`docs/engine/overview.md` → "Why source-built 5.1.0"](docs/engine/overview.md#why-source-built-510).
> Section retained as a stub so existing references still resolve.

### Maps

> **Migrated → [`docs/engine/setup.md` → "Maps"](docs/engine/setup.md#maps).**
> Section retained as a stub so existing references still resolve.

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

> **Migrated → [`docs/engine/widgets.md` → "HUD class hierarchy"](docs/engine/widgets.md#hud-class-hierarchy).**

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

> **Migrated → [`docs/engine/widgets.md` → "Persistent widgets"](docs/engine/widgets.md#persistent-widgets-parented-to-gameinstance_base_c).**

#### ScrollBox Usage in Game (confirmed via F9 dump)

> **Migrated → [`docs/engine/widgets.md` → "ScrollBox usage in OS's own UI"](docs/engine/widgets.md#scrollbox-usage-in-oss-own-ui).**

### BPModLoaderMod Lifecycle

> **Migrated → [`docs/engine/widgets.md` → "BPModLoaderMod lifecycle"](docs/engine/widgets.md#bpmodloadermod-lifecycle).**
> The auto-load sequence, magic-name constraint
> (`/Game/Mods/<ModName>/ModActor`), timing characteristics
> (`~27s` post-start), and the duplicate-prevention check
> are all preserved. Section retained as a stub so existing
> references still resolve.

### Widget System — What Works in Cooked Paks

> **Migrated → [`docs/engine/widgets.md` → "Widget catalog (what works in cooked paks)"](docs/engine/widgets.md#widget-catalog-what-works-in-cooked-paks).**

### EditableText (ChatInput) — Known Bugs & Workarounds

> **Migrated → [`docs/engine/widgets.md` → "EditableText quirks (chat input)"](docs/engine/widgets.md#editabletext-quirks-chat-input).**

### Input Mode Management

> **Migrated → [`docs/engine/widgets.md` → "Input mode management"](docs/engine/widgets.md#input-mode-management).**

### Visibility Constants (ESlateVisibility)

> **Migrated → [`docs/engine/widgets.md` → "Visibility constants (ESlateVisibility)"](docs/engine/widgets.md#visibility-constants-eslatevisibility).**
> The HitTestInvisible vs SelfHitTestInvisible distinction and
> the BP-function-name resolution rule (display name without
> spaces) are preserved in the migrated doc; the latter also
> appears in
> [`docs/engine/ue4ss-version-and-gotchas.md` → "BP function name resolution"](docs/engine/ue4ss-version-and-gotchas.md#4-bp-function-name-resolution-display-name-without-spaces).

### GameInstance Persistence

> **Migrated → [`docs/engine/widgets.md` → "GameInstance persistence"](docs/engine/widgets.md#gameinstance-persistence-the-persistent-root).**

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
  - `GetMeRequestV1Completed` — **`MulticastInlineDelegateProperty`** (offset 0x248), typed `MeRequestV1Completed__DelegateSignature` with callback shape `(Succeeded: Bool, RequestId: Str, MeResponse: MeResponseV1, ErrorResponse: ErrorResponse)`. The working substrate for getting the local profile in this UE4SS build (see "Lua-side reachability" below).
  - **`MeResponseV1` extends `PlayerPublicProfile`** (UE `ScriptStruct` inheritance via the dumper's `sps` field), so `OutMeResponse` carries every PlayerPublicProfile field — **`PlayerId` (Prometheus ID), `Username`, `LogoId`/`NameplateId`/`EmoticonId`/`TitleId`, `PlatformIds` struct, `MasteryLevel`, `CurrentPlatform` enum** — plus Me-only fields (`MatchmakingRegion`, `EulaNeeded`, `DiscordConnection`, etc.). One delegate fire → full local identity.
  - **Lua-side reachability (this UE4SS build):** Updated 2026-04-25 post-v36-identity-stable.
    1. **Sync UFunction calls — call shape REVISED.** The Pass-4 / pre-v33 conclusion that `(Bool out, X out)` UFunctions are *"not callable from Lua at all"* is **refuted at the call-shape layer**. The canonical UE4SS 3.0.1 multi-out-param call shape is `inst:Fn({}, {})` — pass one empty Lua table per declared out-param; UE4SS writes results into `bucket.<ParamName>` for base-type params and collapses multiple base-type out-params into the *first* bucket on 3.0.1 (per [Issue #971](https://github.com/UE4SS-RE/RE-UE4SS/issues/971)). End-to-end-validated against `PMIdentitySubsystem:GetAuthenticatedPlayerId(Valid: Bool out, OutPlayerId: Str out)` in `mod/OSPlus/scripts/identity.lua` → `readAuthenticatedPlayerId` (v36; production-shipping). See `docs/learnings/ue4ss-ufunction-out-param-marshaling-3-0-1.md` for the canonical convention + copy-pasteable example. **The three `PMPlayerModel:GetCached*V1` UFunctions specifically (`GetCachedMeResponseV1`, `GetCachedLinkCodeV1`, `GetCachedPlayerPublicProfile`) were NOT re-tested with `({}, {})` during the v33→v36 work** — they may now be reachable, or they may still fail for an orthogonal `PMPlayerModel`-specific reason. Treat them as "untested with new shape; probe before relying." Same caveat for `GetCachedLoginResponse`, `GetMeV1`, and any other sibling that appeared in `ue4ss-outparam-marshaling-failure.md`.
    2. **Async delegate binding — unchanged.** `MulticastDelegateProperty:Add(uobject, fname)` is still a **silent no-op** on this UE4SS build for inline-multicast props on non-engine-namespace UObjects (Pass-5 finding, not affected by the v33→v36 work — that work was about *calling* UFunctions, not *subscribing* to delegates). `Add` returns `true`, `GetBindings()` stays empty, `Broadcast()` fires nothing. Likely vtable-offset mismatch in UE4SS's binary parser. Pass-5 documented in `docs/learnings/ue4ss-multicast-delegate-add-silent-noop.md`.
    - **Working substrate (Pass-5 pivot, Pass-6 v2 validated, v36 production-shipping):** `RegisterHook` on the engine-side originating UFunction. For identity, that UFunction is `/Script/Prometheus.PMIdentitySubsystem:GetIdentityState` — direct module-load `RegisterHook` (no `NotifyOnNewObject` defer needed, since UFunctions live in the class table from package load). Inside the callback, call `instance:GetAuthenticatedPlayerId({}, {})` to read the local Prometheus ID. No BP wrapper, no delegate binding, no `WasCached`-flag dependency, pure Lua. Maintainer-recommended pattern per UE4SS Issue #455. Production reference: `mod/OSPlus/scripts/identity.lua`.
- **Practice mode caveat**: `PlayerNamePrivate` returns a hex Prometheus ID rather than the display name in practice mode. Only returns the display name in custom / real games.

### ScrollBox Crash — Root Cause & Resolution (SOLVED)

> **Migrated → [`docs/engine/widgets.md` → "ScrollBox crash — root cause"](docs/engine/widgets.md#scrollbox-crash--root-cause).**
> Full investigation timeline preserved (UE 5.1.1 attempt → UE
> 5.1.0 source-built → binary analysis → wrong-key-name
> false-friend → source-code analysis → fix). The fix INI line
> also lives in [`docs/engine/setup.md` → "DefaultEngine.ini"](docs/engine/setup.md#defaultengineini).
> Section retained as a stub (and as a SOLVED marker for the
> "Known Unknowns" section) so existing references still resolve.

### Audio
- [ ] Game's sound classes / sound mixes — can we play custom sounds without conflicting?
- [ ] Volume control — does the game's audio settings affect our custom `PlaySound2D`?

### Input
- [ ] Full list of game keybinds to avoid conflicts
- [ ] Does the game use Enhanced Input or legacy input?
- [ ] Can we read mouse position in world space without line traces?
