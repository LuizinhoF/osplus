# Player state — `PlayerState_Game_C` and per-player engine surfaces

The *"what does the engine track per-player during a match, and
how do I read or hook it"* doc — read this when designing any
feature that observes a single player's actions (KOs, damage,
power-orb pickups, level-up moments, energy state). Distilled
from [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) "Key UFunctions
→ PlayerState_Game_C" sub-sub-section.

> **Status:** seeded 2026-05-01 from
> [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md). Most facts here
> are dump-derived UFunction names; the *parameter shapes* of
> those UFunctions are largely unprobed. The
> `SpawnEffectsOnCharacterKnockedOut` hook is the most-validated
> entry on this list (used in active feature design as a KO
> detection signal).
>
> **Stability:** UFunction names listed below were dumped at a
> specific moment; treat as a starting grep, not a finalized API.
> Re-validate via probe before relying on a specific signature.

This doc is the *per-player engine surface*. The *backend
identity layer* (Prometheus ID, MeResponseV1, the 3 identifier
namespaces) is in [`identity-and-api.md`](./identity-and-api.md).
The *match-level state* (GameState, phase model) is in
[`game-state.md`](./game-state.md). The *per-match counter
shapes* (`PMPlayerMatchSummary`) are in
[`data-model.md`](./data-model.md).

## TL;DR

- **`PlayerState_Game_C` is the per-player Blueprint class.** Its
  C++ ancestor is `PMPlayerState` (Prometheus module). One
  instance per player per match.
- **The class hosts a cluster of `Try*` and `On*` UFunctions**
  for damage events, KO events, level-up milestones, orb
  tracking, energy resets, and FX-package application. See
  [§"Hookable UFunctions"](#hookable-ufunctions).
- **Local-vs-remote PlayerState distinction is non-trivial.**
  KB observed that `FindFirstOf("PlayerState_Game_C")` in
  practice mode returned only one PlayerState (the local
  player); whether `FindAllOf` enumerates all players in online
  matches is an open question. See
  [§"Local vs remote players"](#local-vs-remote-players).
- **Display name lives at `PlayerNamePrivate` after replication.**
  Has three observed modes (display name, hex Prometheus ID
  during replication window, machine name in some out-of-match
  contexts). Full identity machinery is in
  [`identity-and-api.md`](./identity-and-api.md).

## The class

`PlayerState_Game_C` is a Blueprint subclass of `PMPlayerState`
(Prometheus module C++). It's spawned by the engine for each
player when entering a match (Character Select onwards — see
[`game-state.md` → "Phase model"](./game-state.md#phase-model)),
and persists for the duration of the match.

**Lua-side handle:**

```lua
local ps = FindFirstOf("PlayerState_Game_C")
if ps and ps:IsValid() then
    local nameField = ps.PlayerNamePrivate  -- FText
    local nameStr = nameField:ToString()    -- "Ispicas" (after replication)
end
```

**Detected presence is a phase signal:** `FindFirstOf("PlayerState_Game_C") ~= nil`
is half of the [`isInMatch()` predicate](./game-state.md#match-detection).

## Hookable UFunctions

| UFunction | What it appears to do |
|---|---|
| `DamageChanged` | Damage dealt / received tracking. Fires when this player's stagger / damage-state changes. **The engine concept "damage" is stagger pressure, not lethal HP** — see [glossary → Stagger / KO](../glossary.md#core-aka-rock) and player-side [`docs/game/in-match-hud.md`](../game/in-match-hud.md). |
| `SpawnEffectsOnCharacterKnockedOut` | KO event. Fires when this player is knocked off the arena. **The most-validated hook on this list** — used as a KO detection signal in active feature design work. |
| `OnPlayerLevelMilestoneChanged` | In-match level-up moment. Triggers the per-Striker level-up FX and (in online play) the awakening-select prompt at certain milestones. |
| `IncrementOrbTracking` | Power-orb pickup increment. Probably called from `PlayPowerUpPickedUpAudio` (on `GameState_Game_C` — see [`game-state.md` → "Hookable UFunctions"](./game-state.md#hookable-ufunctions)) but worth probing the call relationship. |
| `ResetOrbTracking` | Power-orb tracking reset (presumably between sets / at match start). |
| `TryResetEnergy` | Energy resource reset. **The shared Energy resource powers both Evade and Energy Burst** (see player-side [`docs/game/awakenings.md`](../game/awakenings.md) and the design-principles doc). Hooking this catches the moments where Energy regenerates / is forced to a known state. |
| `TryUnlockSpecial` | Special-ability unlock attempt. Tied to the Striker-special / ultimate system. |
| `TryPlayLevelUpFX` | Level-up FX trigger (paired with `OnPlayerLevelMilestoneChanged`). |
| `TryTriggerFXPackage` | Generic FX-package trigger. Ties into the gameplay-effect / FX-package system (per-Striker / Awakening visual effects). |
| `TryApplyFXPackageGameplayEffect` | Generic gameplay-effect application. The "apply this gameplay tag and run the FX" path. |
| `FaceOffAddGoalieStrike` | Face-off-related goalie strike counter. **"Face off"** likely refers to the post-goal kickoff phase. Goalie-specific accounting (per [glossary → Goalie / Forward](../glossary.md#goalie--forward-role)). |

**Convention:** the `Try*` prefix on most of these suggests they
return a success bool and gate their effect on internal
preconditions — hooking them gives you both the attempt and the
outcome. Probe the parameter shape before relying on a specific
return.

**Hook timing:** `RegisterHook` on a `/Game/...` path is a
post-hook (fires after the function returns). `/Script/...` is
pre-hook. See
[`ue4ss-version-and-gotchas.md` → "RegisterHook"](./ue4ss-version-and-gotchas.md#registerhook).

## Local vs remote players

KB observed:

> Can we read other players' PlayerStates? F4 dump only found 1
> PlayerState_Game_C per phase — might need FindAllOf

This is a significant unknown. Two scenarios are possible:

1. **The local PlayerState is the only one Lua can see.** In
   that case, multi-player observation requires a different
   surface — e.g., `FindAllOf("PMPlayerPublicProfile")` (which
   returns ~100+ cached profiles per dump, including remote
   players — but **the local player is NOT in this cache**, see
   [`identity-and-api.md`](./identity-and-api.md)).
2. **All PlayerStates are reachable but the F4-dump path only
   surfaces one of them.** `FindAllOf("PlayerState_Game_C")`
   might enumerate all 6 players in an online match.

Probing this is the gating step for any feature that wants to
observe opponents' damage / KO / orb-pickup events. **Until
proven otherwise, assume only the local PlayerState is
reachable** and design hook-based features around that.

The data-shape side of this question (where do other players'
per-match counters live?) is documented in
[`data-model.md` → "Open questions"](./data-model.md#open-questions).

## Cross-references

- **The match phase model — when does PlayerState_Game_C exist:** [`game-state.md` → "Phase model"](./game-state.md#phase-model)
- **The full identity layer (display name, Prometheus ID, SteamID):** [`identity-and-api.md`](./identity-and-api.md)
- **Per-match counter shapes (PMPlayerMatchSummary etc.):** [`data-model.md`](./data-model.md)
- **The KO detection in player-side terms:** [`docs/game/in-match-hud.md`](../game/in-match-hud.md)
- **The Energy / Evade / Burst system in player-side terms:** [`docs/game/awakenings.md`](../game/awakenings.md)
- **Glossary bridge:** [`docs/glossary.md`](../glossary.md)
- **Sibling docs index:** [`docs/engine/README.md`](./README.md)

## Open questions

- **Can `FindAllOf("PlayerState_Game_C")` enumerate all players
  in an online match?** Single most important probe target on
  this surface — gates feature designs that need opponent
  observation.
- **Parameter shapes of all UFunctions above.** The names are
  catalogued; the actual call signatures (what does
  `DamageChanged` receive? a delta? an absolute? a struct?) are
  not. Each hook needs a shape probe before production use.
- **Which UFunctions fire for the local player only vs all
  players the local client can observe.** Some events are likely
  local-only (e.g., `TryPlayLevelUpFX` probably only fires on the
  player whose level changed, but is the *PlayerState* the local
  PlayerState or the other player's?). This is connected to the
  local-vs-remote question above.
- **`PMPlayerState` (C++ parent) extra surface.** The Blueprint-
  side UFunctions are listed; the C++ parent likely exposes more
  properties / methods directly on the runtime object that
  weren't surfaced in the BP dump. Worth a `GetClass:ForEachFunction`
  probe of `PMPlayerState` specifically.
- **`MatchIntensityChanged` signal source.** Catalogued on
  `PlayerController_Game_C` (see [`game-state.md`](./game-state.md));
  whether the corresponding intensity *value* is stored on
  `PlayerState_Game_C` or elsewhere is open.
