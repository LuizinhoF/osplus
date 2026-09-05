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

> **Status:** corrected 2026-09-05 against current chat code and the
> stored 2026-04-24 UE4SS object/type dumps. The seed-based match
> detector has prior runtime validation; the phase field, enum, and
> function signatures below are confirmed from stored schema only.
> Current runtime phase values, timing, and hook behavior have not
> been tested in this pass, at the user's request.
>
> **Stability:** class tuples below are historical observations,
> not reliable phase gates. Local Pawn presence can change during
> a match. Stored schema may also drift across patches; distinguish
> a known field/signature from a currently verified runtime value.

This doc is the *phase model + lifecycle hooks*. The *per-player
state* layer lives in [`player-state.md`](./player-state.md);
the *per-match counter shapes* in [`data-model.md`](./data-model.md);
the *backend identity* in [`identity-and-api.md`](./identity-and-api.md).

## TL;DR

- **Match identity and gameplay phase are different signals.**
  A nonzero `CurrentMatchSeed` identifies the match room, including
  pregame steps; it does not prove that active play has started.
  See [§"Match detection"](#match-detection).
- **A phase enum is present in the stored schema.**
  `PMGameState.CurrentMatchPhase` uses `EMatchPhase`; the complete
  value table is in [§"Reflected match phase"](#reflected-match-phase).
  Current runtime timing remains unverified.
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
- **Do not restore Pawn-based match gating.** Pawn loss during
  KOs, respawns, and round transitions does not end the match.
  Enemy-presence visibility uses a separate same-seed gameplay
  observation, not Pawn existence or enum ordering.

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

The following class tuples are historical snapshots that help identify
objects during investigation. They are not mutually exclusive phase
detectors: a missing Pawn also occurs during ordinary gameplay, and
spectators need not have a combat Pawn at all. Use match identity and
the reflected phase separately, as described below.

### Main Menu / Lobby

```text
GameStateBase         → GameStateBase (engine base class)
GameModeBase          → GameMode_Menu_C
PlayerController      → PlayerController_Menu_C
PlayerState           → PlayerState (engine base class)
Pawn                  → NONE
GameInstance          → GameInstance_Base_C  (persists across ALL maps)
```

- **Historical observation:** `FindFirstOf("PlayerState_Game_C")` returned nil.
- **Key fact:** No game-specific PlayerState or Pawn exists.
- Player-side equivalent: see [`docs/game/lobby.md`](../game/lobby.md).

### Character Select (online match loaded, picking strikers)

```text
GameStateBase         → GameState_Game_C
PlayerController      → PlayerController_Game_C
PlayerState           → PlayerState_Game_C
Pawn                  → NONE  (not spawned yet)
```

- **Historical observation:** `PlayerState_Game_C` exists but
  `PlayerController.Pawn` is nil. This also happens during KOs, so
  it cannot identify character selection by itself.
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

- **Historical observation:** `PlayerState_Game_C` exists and
  `PlayerController.Pawn` is valid. Pawn absence must not tear down
  chat or revoke a same-match gameplay observation.
- Player-side equivalent: see [`docs/game/in-match-hud.md`](../game/in-match-hud.md).

### Awakening Select (between sets)

```text
GameStateBase         → GameState_Game_C  (same as gameplay)
PlayerState           → PlayerState_Game_C
Pawn                  → Still valid (character persists)
```

- **Match continuity:** retain the nonzero match seed and any
  same-seed gameplay observation. Do not reclassify this as pregame
  because local player objects change or a draft UI is visible.
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

- **Match detection:** the current seed reader falls back to
  `GameState_Tutorial_C`; it does not require a Pawn.
- **Key fact:** GameState class differs (`GameState_Tutorial_C`)
  but PlayerState/Pawn use the standard `_Game_C` classes. Their
  presence is descriptive, not the chat room-membership gate.
- Player-side equivalent: see [`docs/game/match-lifecycle.md` → practice](../game/match-lifecycle.md).

### Post-match (between match end and lobby return)

Class-tuple shape during the post-match results screen has not
been catalogued in detail. Player-side perception is documented
in [`docs/game/post-match.md`](../game/post-match.md); the
engine-side detection question is open (TBD probe target).

## Match detection

The current chat detector reads the server-provided match seed,
with a practice-class fallback:

```lua
local function isInMatch()
    local ok, seed = pcall(function()
        local gs = FindFirstOf("GameState_Game_C")
        if not gs or not gs:IsValid() then
            gs = FindFirstOf("GameState_Tutorial_C")
        end
        if not gs or not gs:IsValid() then return nil end
        return gs.CurrentMatchSeed
    end)
    return ok and type(seed) == "number" and seed ~= 0
end
```

This is the room-membership signal, not an active-gameplay predicate.
The 2026-09-05 user report of chat presence during bans/selection
exposed why those concepts must remain separate. A seed remains
stable through KOs, respawns, and set transitions; no Pawn check is
needed. See [the seed-gate learning](../learnings/chat-match-detection-via-seed.md).

### Reflected match phase

The following stored artifacts agree on the schema. Paths are relative
to `<game>/OmegaStrikers/Binaries/Win64/`; all were generated on
2026-04-24 and inspected on 2026-09-05:

- `Mods/shared/types/Prometheus.lua:820`: `APMGameState.CurrentMatchPhase`.
- `Mods/shared/types/Prometheus.lua:970`: `MatchPhaseChanged(OldPhase, NewPhase)`.
- `Mods/shared/types/Prometheus_enums.lua:683`: `EMatchPhase` values.
- `UE4SS_ObjectDump.txt:25942` and `:64765`: the reflected property and enum.
- `UE4SS_ObjectDump.txt:142390`: the `GameState_Game_C` Blueprint override
  of `MatchPhaseChanged`, also with `OldPhase` and `NewPhase`.

| Value | `EMatchPhase` member | Value | `EMatchPhase` member |
|---|---|---|---|
| 0 | `None` | 12 | `ArenaOverview` |
| 1 | `PreGame` | 13 | `PostGameSummary` |
| 2 | `CharacterSelect` | 14 | `EndGame` |
| 3 | `FaceOffIntro` | 15 | `LoadoutSelect` |
| 4 | `FaceOffCountdown` | 16 | `BoostSelect` |
| 5 | `InGame` | 17 | `TimeoutCelebration` |
| 6 | `GoalCelebration` | 18 | `VersusScreen` |
| 7 | `GoalScore` | 19 | `BanSelect` |
| 8 | `IntermissionIntro` | 20 | `CharacterPreSelect` |
| 9 | `Intermission` | 21 | `BanCelebration` |
| 10 | `IntermissionOutro` | 22 | `IntermissionMvp` |
| 11 | `PostGameCelebration` | 23 | `EMatchPhase_MAX` (sentinel) |

**Values are not chronological.** In particular, `phase >= 5` includes
bans and preselection. The table proves schema, not current client
timing, enum marshaling, or which hook catches the Blueprint override.

`PMGameState.MatchCharacterSelectInfo.EnemyTeamVisibility` also exists
in the stored schema (`NotVisible=0`, `AfterEachPickPhase=1`, `Visible=2`).
Its name suggests pick visibility; it is not established as permission
to reveal opponent usernames.

### Pregame presence boundary

OSPlus keeps room membership based on the seed while independently
restricting presence until it explicitly observes `CurrentMatchPhase == 5`
for that seed. Unknown/unreadable phase cannot grant enemy visibility.
Once observed, that permission persists through KOs, goals, and
between-set drafts; it clears on seed change, map load, or match end.
The existing throttled match checks read the field; no new unverified
phase hook is required.

Before that observation, the relay shows a player only self and confirmed
teammates. Spectators and players with an unknown team see only self.
Keep spectator status separate from `AssignedTeam`: a spectator can
report a viewing-side team. See [the presence investigation](../learnings/chat-pregame-presence-privacy.md)
and [relay architecture](../architecture/relay.md) for the filtering contract.

This intentionally keeps enemies hidden through initial loading/drafts.
A newly joined client first observed during intermission waits for the
next `InGame` observation. Current runtime phase timing is still untested;
the user deferred in-game tests for this change.

## Hookable UFunctions

Captured at one moment in time via `GetClass:ForEachFunction`
dumps. These are the UFunctions present on the listed classes
that are *plausibly hookable* — name + apparent purpose. Treat
as a grep target and probe before relying on a specific
signature.

### `GameState_Game_C` (online match)

| UFunction | What it appears to do |
|---|---|
| `MatchPhaseChanged` | Stored schema confirms `(OldPhase: EMatchPhase, NewPhase: EMatchPhase)` on both `PMGameState` and the Blueprint override. Runtime hook coverage/timing remain unverified; presence currently reads the field at the existing throttled cadence. |
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

- **Current runtime phase transitions.** The stored field, enum,
  and parameter schema are catalogued above. Still verify their
  current values and UE4SS marshaling, transition timing, and
  whether a hook sees the Blueprint override. No such live test
  was performed during the 2026-09-05 correction.
- **What triggers map loads.** Is there a `MatchManager` or
  similar coordinator that drives the lobby → arena transition?
  KB flagged this; still unanswered.
- **Other `GameState_Game_C` property values.** The stored schema
  includes `CurrentMatchPhase`; live score, round, team-data, and
  timer interpretation still require targeted verification.
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
