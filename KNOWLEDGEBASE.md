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
> - **Batch 2 (2026-05-01):** §"Backend Ecosystem — Odyssey's
>   'Prometheus' API", §"Per-match runtime data — what's reachable
>   from Lua", §"Game Lifecycle & Phase Detection", §"Player
>   Identity Reference", and the "Core Framework" + "Key UFunctions"
>   sub-sub-sections of "Class Hierarchy Reference".

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

> **Migrated → [`docs/engine/identity-and-api.md` → "The backend API"](docs/engine/identity-and-api.md#the-backend-api).**
> The two-Prometheus disambiguation, auth (JWT pair from Fiddler
> capture or Steam-ticket handshake), exposed endpoints (per-
> character aggregates, ratings, mastery), and the OSPlus
> capture gap (no `redirects` field, no per-match event
> sequences, no in-match transient state) are all preserved.
> Section retained as a stub so existing references still resolve.

### Per-match runtime data — what's reachable from Lua

> **Migrated → [`docs/engine/data-model.md`](docs/engine/data-model.md).**
> Specifically: [`PMPlayerMatchSummary` field layout](docs/engine/data-model.md#pmplayermatchsummary)
> and [`EPMEndOfGameStat` enum](docs/engine/data-model.md#epmendofgamestat-enum),
> plus `PMRockCharacter:LastRedirectKnockBack`,
> `EKnockBackType::Redirect = 2`, the
> ["Rock" naming gotcha](docs/engine/data-model.md#the-rock-naming-gotcha),
> and the open questions about per-summary↔player mapping.
> Section retained as a stub so existing references still resolve.

### Game Lifecycle & Phase Detection

> **Migrated → [`docs/engine/game-state.md` → "Phase model"](docs/engine/game-state.md#phase-model)
> and [→ "Match detection"](docs/engine/game-state.md#match-detection).**
> All five phase class-tuples (Main Menu, Character Select,
> Active Gameplay, Awakening Select, Practice Mode) and the
> proven `isInMatch()` predicate are preserved. The "between
> rounds" terminology in the original was reconciled with the
> player-side canonical "between sets" — see migrated doc's
> note on the Awakening Select phase.
> Section retained as a stub so existing references still resolve.

### Class Hierarchy Reference

#### Core Framework

> **Migrated → [`docs/engine/game-state.md` → "The Core Framework class tree"](docs/engine/game-state.md#the-core-framework-class-tree).**

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

> **Migrated:**
>
> - `GameState_Game_C`, `GameState_Tutorial_C`,
>   `PlayerController_Game_C`, `PlayerController_Practice_C`,
>   `GameInstance_Base_C` UFunction tables →
>   [`docs/engine/game-state.md` → "Hookable UFunctions"](docs/engine/game-state.md#hookable-ufunctions)
> - `PlayerState_Game_C` UFunction table →
>   [`docs/engine/player-state.md` → "Hookable UFunctions"](docs/engine/player-state.md#hookable-ufunctions)
>
> Strike-specific UFunctions on `PlayerController_Game_C`
> (`StrikeReleased`, `StrikeDragged`) will additionally appear
> in batch 3's `rock-and-strike.md` for centralized Strike
> reference.

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

> **Migrated → [`docs/engine/identity-and-api.md`](docs/engine/identity-and-api.md).**
> Specifically: [the three identifier namespaces](docs/engine/identity-and-api.md#the-three-identifier-namespaces),
> [the local-identity surface (PMIdentitySubsystem, PMPlayerModel, MeResponseV1)](docs/engine/identity-and-api.md#the-local-identity-surface),
> [the cached-others path (PMPlayerPublicProfile)](docs/engine/identity-and-api.md#the-cached-others-path),
> and [the v36-current Lua-side reachability rules](docs/engine/identity-and-api.md#lua-side-reachability)
> with the three-mode `PlayerNamePrivate` caveat
> (display name / hex ID during replication / Windows machine
> name out-of-match) cross-linked to the relevant learnings.
> Section retained as a stub so existing references still resolve.

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
