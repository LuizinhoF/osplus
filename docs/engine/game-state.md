# Game state — phase model, GameState classes, lifecycle

The *"what is the match in right now, and how do I tell from
Lua"* doc — read this when designing any feature whose behavior
depends on the current phase (chat-vs-passive, in-match-only
overlays, post-match capture). Distilled from
[`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) §"Game Lifecycle &
Phase Detection" + the "Core Framework" sub-section of "Class
Hierarchy Reference" + the "Key UFunctions" sub-section
(GameState_Game_C, GameState_Tutorial_C, PlayerController_Game_C,
PlayerController_Practice_C, GameInstance_Base_C).

> **Status:** seeded 2026-05-01 from
> [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md). The class-tuple
> phase-detection model and the `isInMatch` Lua function were
> the foundation of the chat feature's seed-gate work — they
> are well-validated. Open questions (the actual `MatchPhaseChanged`
> enum values, the exact between-rounds vs between-sets boundary)
> remain unprobed.
>
> **Stability:** class-tuple detection is robust against
> single-game-version drift. UFunction names listed below were
> dumped at a specific moment in time and may grow / shrink
> across patches; treat the list as a starting grep, not a
> finalized API.

This doc is the *phase model + lifecycle hooks*. The *per-player
state* layer lives in [`player-state.md`](./player-state.md);
the *per-match counter shapes* in [`data-model.md`](./data-model.md);
the *backend identity* in [`identity-and-api.md`](./identity-and-api.md).

## TL;DR

- **No phase enum is exposed (yet).** Phase is detected by
  inspecting the *class tuple* `(GameState, PlayerController,
  PlayerState, Pawn, GameInstance)` — different phases have
  different combinations. See [§"Phase model"](#phase-model).
- **The `isInMatch()` predicate is the canonical detector.**
  `PlayerState_Game_C` exists AND `PlayerController.Pawn` is
  valid. Works across active gameplay, between-rounds, and
  practice. See [§"Match detection"](#match-detection).
- **`GameState_Game_C` and `GameState_Tutorial_C` carry the
  hookable UFunctions for match events.** `MatchPhaseChanged`,
  `MatchSummary`, `SpawnGoalEffects`, `IntermissionPlayerDataChanged`
  for online; `SwitchToNextPowerUp`, `Set Random Power Orb`,
  `MatchPhaseChanged`, `SpawnGoalEffects` for practice. See
  [§"Hookable UFunctions"](#hookable-ufunctions).
- **`GameInstance_Base_C` persists across all maps.** It owns
  the persistent widgets (chat included). Its lifecycle hooks
  (`ReceiveInit`, `ReceiveShutdown`) bracket the entire game
  session, not the match.
- **`MatchPhaseChanged` enum values are not catalogued.** The
  UFunction fires reliably at every phase transition; what the
  argument actually is — TBD probe target. See
  [§"Open questions"](#open-questions).

## The Core Framework class tree

The native + Blueprint class hierarchy that the rest of this doc
references. All paths are under `/Game/Prometheus/Blueprints/Core/`:

```text
GameInstance_Base          → persists across all maps, owns persistent widgets
GameModes/
  └── GameMode_Menu        → menu-only game mode
GameState_Game             → online match state (PMGameState ancestor)
GameState_Tutorial         → practice mode state
PlayerController_Menu      → menu navigation
PlayerController_Game      → online match input
PlayerController_Practice  → practice mode input
PlayerState_Game           → per-player match state (PMPlayerState ancestor)
```

Runtime form adds the `_C` suffix on every class — `GameState_Game_C`,
`PlayerState_Game_C`, etc. **The `_C` matters when you grep / probe.**

The C++ ancestors (`PMGameState`, `PMPlayerState`, `PMHUDBase`,
`OdyHUD`) live in the `Prometheus` and `OdyUI` modules and
provide the underlying functionality the Blueprints extend. See
[`overview.md` → "The two gameplay modules"](./overview.md#the-two-gameplay-modules).

## Phase model

The game progresses through distinct phases. Each phase has a
unique combination of GameState / PlayerController / PlayerState
/ Pawn classes that can be queried from Lua. **No engine-side
phase enum is exposed at this layer** — class-tuple detection is
the substitute.

### Main Menu / Lobby

```text
GameStateBase         → GameStateBase (engine base class)
GameModeBase          → GameMode_Menu_C
PlayerController      → PlayerController_Menu_C
PlayerState           → PlayerState (engine base class)
Pawn                  → NONE
GameInstance          → GameInstance_Base_C  (persists across ALL maps)
```

- **Detection from Lua:** `FindFirstOf("PlayerState_Game_C")` returns nil.
- **Key fact:** No game-specific PlayerState or Pawn exists.
- Player-side equivalent: see [`docs/game/lobby.md`](../game/lobby.md).

### Character Select (online match loaded, picking strikers)

```text
GameStateBase         → GameState_Game_C
PlayerController      → PlayerController_Game_C
PlayerState           → PlayerState_Game_C
Pawn                  → NONE  (not spawned yet)
```

- **Detection from Lua:** `PlayerState_Game_C` exists BUT
  `PlayerController.Pawn` is nil.
- **Key fact:** Map has loaded (e.g., `GameMapAhtenCity`) but
  the player has no Pawn. Striker model previews are widget-based
  3D actors, not the player Pawn.
- Player-side equivalent: see [`docs/game/striker-select.md`](../game/striker-select.md).

### Active Gameplay (in-match, controlling striker)

```text
GameStateBase         → GameState_Game_C
PlayerController      → PlayerController_Game_C
PlayerState           → PlayerState_Game_C
Pawn                  → Character class  (e.g., C_FlexibleBrawler_C, C_NimbleBlaster_C)
```

- **Detection from Lua:** `PlayerState_Game_C` exists AND
  `PlayerController.Pawn` is valid.
- **Key fact:** This is the only phase where the mod chat
  should be visible/interactive.
- Player-side equivalent: see [`docs/game/in-match-hud.md`](../game/in-match-hud.md).

### Awakening Select (between sets)

```text
GameStateBase         → GameState_Game_C  (same as gameplay)
PlayerState           → PlayerState_Game_C
Pawn                  → Still valid (character persists)
```

- **Detection from Lua:** Same as active gameplay — chat
  remains visible.
- **Note on terminology:** the original KB section called this
  "between rounds." The player-side canonical doc
  ([`docs/game/awakenings.md`](../game/awakenings.md)) and
  player-side terminology call this "between sets" (per
  [glossary → Match](../glossary.md#match)). Drafts happen at
  match start AND between sets, not just between sets — refine
  as the engine boundary becomes clearer (planned probe target
  in [`open-questions.md`](./README.md)).
- Player-side equivalent: see [`docs/game/awakenings.md`](../game/awakenings.md).

### Practice Mode

```text
GameStateBase         → GameState_Tutorial_C
PlayerController      → PlayerController_Practice_C
PlayerState           → PlayerState_Game_C
Pawn                  → Character class
```

- **Detection from Lua:** Same `PlayerState_Game_C` + valid Pawn
  predicate as online active gameplay; the same predicate works
  here.
- **Key fact:** GameState class differs (`GameState_Tutorial_C`)
  but PlayerState/Pawn are the standard `_Game_C` classes —
  enabling the chat-visibility logic to work in both contexts.
- Player-side equivalent: see [`docs/game/match-lifecycle.md` → practice](../game/match-lifecycle.md).

### Post-match (between match end and lobby return)

Class-tuple shape during the post-match results screen has not
been catalogued in detail. Player-side perception is documented
in [`docs/game/post-match.md`](../game/post-match.md); the
engine-side detection question is open (TBD probe target).

## Match detection

The proven `isInMatch` predicate, copied from the working
chat-feature implementation:

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

**What it returns true for:**

- Active Gameplay (online + practice, since both share the
  PlayerState_Game_C + valid Pawn shape).
- Awakening Select (Pawn persists during the draft).

**What it returns false for:**

- Main Menu / Lobby (no PlayerState_Game_C).
- Character Select (PlayerState exists, Pawn is nil).
- Post-match results (likely false; not confirmed).

**The chat feature uses this for visibility/interactivity
gating.** Other features should adopt the same predicate as the
"am I in a match?" boundary unless they specifically need
Character Select inclusion (in which case drop the Pawn check).

## Hookable UFunctions

Captured at one moment in time via `GetClass:ForEachFunction`
dumps. These are the UFunctions present on the listed classes
that are *plausibly hookable* — name + apparent purpose. Treat
as a grep target and probe before relying on a specific
signature.

### `GameState_Game_C` (online match)

| UFunction | What it appears to do |
|---|---|
| `MatchPhaseChanged` | **Primary phase-transition hook.** Fires on phase transitions (char select → gameplay → intermission → ...). Argument-shape unprobed; the actual phase enum value is not catalogued. |
| `IntermissionPlayerDataChanged` | Between-sets player-data update. Fires during the awakening-select / set-boundary moment. |
| `MatchSummary` | End of match. Likely the cleanest signal for "match is over, do post-match capture now." |
| `SpawnGoalEffects` | Goal scored. Fires for the goal-effect spawn — useful as a "goal happened" signal. |
| `GetPlayerMvpScore` | MVP scoring read. Pre-hook to peek at internals; not for mutation. |
| `GetMvpScoreRoundMultiplier` | MVP multiplier read. Same caveat. |
| `TryPlayMVPTheme` | MVP audio cue. Useful as a "MVP screen is firing" trigger. |
| `PlayPowerUpPickedUpAudio` | Power-orb pickup audio cue. Fires on every orb pickup; could be used as an orb-pickup detector. |
| `Try Set Power Orb Based On Map` | Power-orb spawn-decision logic per-map. (Note: BP function display name has spaces; runtime UFunction name strips them — `TrySetPowerOrbBasedOnMap`. See [`ue4ss-version-and-gotchas.md` → "BP function name resolution"](./ue4ss-version-and-gotchas.md#4-bp-function-name-resolution-display-name-without-spaces).) |
| `GetGoalExplosion` | Goal-effect lookup, presumably called by `SpawnGoalEffects`. |

### `GameState_Tutorial_C` (practice mode)

| UFunction | What it appears to do |
|---|---|
| `SwitchToNextPowerUp` | Practice-only: cycles through the available power-ups. Useful for testing OS power-orb feature interactions without waiting for natural spawns. |
| `Set Random Power Orb` | Practice-only: randomizes orb selection. Same testing use case. |
| `MatchPhaseChanged` | Same name as online; presumably similar phase semantics. |
| `SpawnGoalEffects` | Same name as online. |

### `PlayerController_Game_C` (online)

| UFunction | What it appears to do |
|---|---|
| `StrikeReleased` | Strike input released. The "player just hit the Core" event. |
| `StrikeDragged` | Strike input being dragged (charging, aiming). Per-frame during the windup. |
| `MatchIntensityChanged` | Match-intensity system event. Probably tied to score-differential / clutch-detection. Unprobed. |
| `ShowMoveToIndicator` | Move-to indicator show. Tied to ping/move commands. |
| `OnMoveToPressed` | Move-to input pressed. |
| `AddStealthBorder` | Stealth visual effect. Tied to specific Striker abilities (likely Awakenings or character-specific FX). |
| `HoldToStrikeModeEnabledChanged` | Settings event for the hold-to-strike mode toggle. |

### `PlayerController_Practice_C`

| UFunction | What it appears to do |
|---|---|
| `On Match Phase Changed` | Practice-mode phase change handler. (Display name has spaces; runtime is `OnMatchPhaseChanged`.) |

### `GameInstance_Base_C`

| UFunction | What it appears to do |
|---|---|
| `ReceiveInit` | Game-instance init. Fires once at game start, before any map load. The earliest reliable Lua-from-engine moment. |
| `ReceiveShutdown` | Game-instance shutdown. Fires at game exit. |

## Cross-references

- **Engine + UE4SS pin:** [`overview.md`](./overview.md)
- **The hooks themselves (RegisterHook):** [`ue4ss-version-and-gotchas.md` → "RegisterHook"](./ue4ss-version-and-gotchas.md#registerhook)
- **Per-player state surfaces:** [`player-state.md`](./player-state.md)
- **Per-match counter shapes:** [`data-model.md`](./data-model.md)
- **Backend identity (Prometheus API + PMIdentitySubsystem):** [`identity-and-api.md`](./identity-and-api.md)
- **The puck (Core / Rock):** `rock-and-strike.md` (TBD batch 3)
- **Player-side phase model + lifecycle:** [`docs/game/match-lifecycle.md`](../game/match-lifecycle.md)
- **Player-side equivalent screens:** [`docs/game/screens.md`](../game/screens.md)
- **Glossary bridge:** [`docs/glossary.md`](../glossary.md)
- **Sibling docs index:** [`docs/engine/README.md`](./README.md)

## Open questions

- **`MatchPhaseChanged` enum values.** The UFunction fires
  reliably at every transition, but the actual phase identifier
  argument has not been catalogued. Probing the param shape
  inside a `RegisterHook` callback would close this — high-value
  because every feature touching match-phase logic currently
  has to use class-tuple detection.
- **What triggers map loads.** Is there a `MatchManager` or
  similar coordinator that drives the lobby → arena transition?
  KB flagged this; still unanswered.
- **`GameState_Game_C` readable properties.** UFunctions are
  enumerated above; the *property fields* (round number, score,
  team data, match timer) have not been probed. Capturing live
  match score would need this.
- **Post-match phase class-tuple shape.** What classes are live
  during the post-match results screen? Affects any feature that
  wants to surface during/after the match-end moment but not
  during the next match.
- **Awakening Select phase boundary specifically.** Player-side
  doc states drafts happen at match start AND between sets;
  KB's section title was "between rounds." Engine-side detection
  needs a probe across the start-of-match draft (does it fire
  via `MatchPhaseChanged`? Is there a separate UFunction?) to
  reconcile.
- **Match-end capture path.** Does `MatchSummary` fire pre-EOG
  or post-EOG? Does it carry the per-match data, or just signal
  that the data is ready elsewhere? Critical for any post-match
  capture feature.
