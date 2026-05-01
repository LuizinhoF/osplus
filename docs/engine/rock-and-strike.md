# Rock and Strike — the puck actor and the basic-Strike input

The *"how does the engine see the Core / puck and the Strike
input"* doc — read this when designing any feature that observes
or reacts to the puck (`PMRockCharacter`), the canonical Strike
event (`StrikeReleased` / `StrikeDragged`), or the redirect
mechanic (`EKnockBackType::Redirect = 2`,
`PMRockCharacter:LastRedirectKnockBack`). Distilled from
[`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) "Per-match runtime
data" + the strike-specific UFunction sub-rows of the "Key
UFunctions" sub-section. Centralizes Strike + Rock so existing
cross-references from [`game-state.md`](./game-state.md) and
[`data-model.md`](./data-model.md) resolve.

> **Status:** seeded 2026-05-01 from
> [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md). The "Rock"
> naming convention, `EKnockBackType::Redirect = 2`, and the
> Strike UFunction names are dump-confirmed. The *parameter
> shapes* for both Strike events and `LastRedirectKnockBack`
> are unprobed — every "what does this carry" question in this
> doc is currently open.
>
> **Stability:** Names should be stable across patches within a
> UE major version. The *behavior* of Strike (cooldown, hitbox)
> moves with patch tuning; this doc deliberately stays at the
> engine-surface layer and defers behavior questions to the
> player-side [`core-and-strike.md`](../game/core-and-strike.md).

This doc is the *engine + UE4SS surface* for the puck and the
basic Strike. The *player-side feel + cooldown discipline* lives
in [`docs/game/core-and-strike.md`](../game/core-and-strike.md).
The *per-match aggregate counters* (`RedirectRock`,
`HitRockIntoGoalArea`) live in
[`data-model.md`](./data-model.md). The *match-phase context*
(when does Strike input fire) lives in
[`game-state.md`](./game-state.md).

## TL;DR

- **The puck is `PMRockCharacter`.** Engine grep for the puck
  is **`Rock`** — never `Ball` / `Puck` / `Core`. See
  [`data-model.md` → "The Rock naming gotcha"](./data-model.md#the-rock-naming-gotcha).
- **One puck per match.** `FindFirstOf("PMRockCharacter")` is a
  stable handle during active gameplay.
- **Strike is a drag-release input** (per UFunction names —
  `StrikeDragged` for the in-progress windup, `StrikeReleased`
  for the actual hit). Both live on `PlayerController_Game_C`.
- **`HoldToStrikeModeEnabledChanged`** is the user-settings
  toggle for hold-to-strike mode (a UI-pref variant); not the
  Strike event itself.
- **Per-event redirect detail:** `PMRockCharacter:LastRedirectKnockBack`
  carries the per-event payload (presumably: redirector reference,
  direction, magnitude, timestamp — **shape unprobed**).
- **Per-match redirect aggregate:** `PMPlayerMatchSummary.RedirectRock`
  is the per-player counter (see [`data-model.md`](./data-model.md)).
- **`EKnockBackType::Redirect = 2`** classifies a redirect-on-Core
  knockback specifically. Other `EKnockBackType` values exist
  but aren't catalogued.

## The puck actor — `PMRockCharacter`

`PMRockCharacter` is the in-match puck actor. C++ class lives in
the `Prometheus` module (`PM*` prefix); the Blueprint runtime
form is `PMRockCharacter_C` for the spawned instance.

**Lua-side handle:**

```lua
local rock = FindFirstOf("PMRockCharacter")
if rock and rock:IsValid() then
    -- rock.LastRedirectKnockBack — per-event redirect detail (shape TBD)
end
```

**Lifetime.** One instance per match, spawned with the arena and
present from Active Gameplay onward. Not present in Main Menu /
Lobby / Character Select (per [`game-state.md` → "Phase model"](./game-state.md#phase-model)).

**Why "Rock" and not "Core" / "Ball" / "Puck".** Pre-launch
Odyssey naming convention; carried over into the live game's
internal class names. The player-facing rename to "Core" never
propagated into engine code. Every grep on the puck — actor
class, redirect counter, knockback enum, shots-on-goal counter —
uses `Rock`. See player-side [`core-and-strike.md`](../game/core-and-strike.md)
for the player vocabulary.

### Per-event redirect detail — `LastRedirectKnockBack`

Field on `PMRockCharacter` itself. Sibling structure to the
per-match aggregate counters in
[`PMPlayerMatchSummary`](./data-model.md#pmplayermatchsummary):
the aggregate tells you "this player has 14 redirects this
match," `LastRedirectKnockBack` tells you "the most recent
redirect happened with these properties."

**Inferred shape (unprobed — confirm before use):**

- The redirecting player (likely a `PlayerState` / `Pawn`
  reference).
- The direction the Core was sent.
- The knockback magnitude.
- A timestamp / frame marker.

**Use case.** A "highlight reel" / per-event capture feature
needs `LastRedirectKnockBack`. A "career redirect total" feature
only needs `PMPlayerMatchSummary.RedirectRock`. **Don't read
`LastRedirectKnockBack` per-tick** — it's a single field that
overwrites; sample it on the rising edge of an actual redirect
event (probably hookable via a `PMRockCharacter` UFunction
that hasn't been catalogued yet — see
[§"Open questions"](#open-questions)).

### Other `PMRockCharacter` surface — TBD

The PMRockCharacter's full UFunction surface, exposed properties
(velocity, position, last-toucher reference, set-of-recent-touchers
for assist attribution), and per-event hook points have **not
been catalogued.** A `GetClass:ForEachFunction` dump on
`PMRockCharacter` is the natural Stage-3 RE pass; until then,
treat the actor as "handle exists, payload mostly opaque."

## The Strike input — `PlayerController_Game_C`

Strike is the drag-release input that fires the Striker's basic
attack. Carried as two UFunctions on `PlayerController_Game_C`:

| UFunction | Inferred role |
|---|---|
| `StrikeDragged` | **In-progress windup.** Per-frame during the windup, reporting the current aim vector. Probably high-frequency — don't post-hook with heavy work. |
| `StrikeReleased` | **The actual Strike event.** Fires once when the player releases the input. The "a Strike just happened" hookable signal. |
| `HoldToStrikeModeEnabledChanged` | **Settings event** for the hold-to-strike mode toggle (a UI-pref for whether Strike requires holding the input vs. tap-to-fire). NOT the Strike event itself; don't confuse it with `StrikeReleased`. |

**Reachability.** `PlayerController_Game_C` exists from Character
Select onward, but Strike is only meaningful during Active
Gameplay (Pawn must exist for the input to do anything). Use
the [`isInMatch()` predicate](./game-state.md#match-detection)
to gate Strike-related feature code.

**Why this is the canonical "did a player Strike" signal —
and the caveats.**

1. `StrikeReleased` is the cleanest dump-confirmed signal that
   a Strike happened *for the local player*. Whether it also
   fires for remote-player Strikes (visible to the local client
   via replication) is **unconfirmed** — likely no, because
   PlayerController is local-only on UE-replication semantics.
2. The hit consequence (did the Strike actually connect? what
   did it hit? did it count as a redirect?) is **not** carried
   on the PlayerController hook. That information lives on:
   - `PlayerState_Game_C.DamageChanged` for stagger pressure on
     opponents (see [`player-state.md`](./player-state.md)).
   - `PMPlayerMatchSummary.RedirectRock` increments for redirect
     counts.
   - `PMRockCharacter.LastRedirectKnockBack` for per-event
     redirect detail.
3. The **cooldown** state is not exposed on the PlayerController.
   It's almost certainly held on the Pawn / Striker character or
   on a sibling component; finding it is a TBD probe target.

### Practice mode — `PlayerController_Practice_C`

Practice has its own PlayerController. The UFunction surface
catalogued for it includes `On Match Phase Changed` (BP display
name has spaces; runtime UFunction name is `OnMatchPhaseChanged`
— see [`ue4ss-version-and-gotchas.md` → "BP function name
resolution"](./ue4ss-version-and-gotchas.md#4-bp-function-name-resolution-display-name-without-spaces)).
Whether `StrikeReleased` / `StrikeDragged` exist on
`PlayerController_Practice_C` (or whether practice mode
intercepts strikes through a different path) has not been
confirmed — practice mode isn't a high-priority surface for
Strike-gating features, but worth a probe if a feature needs
to behave consistently in both modes.

## Knockback classification — `EKnockBackType`

Knockbacks on the Core are classified into an enum.
**`EKnockBackType::Redirect = 2`** is the only enum value
catalogued; the others have not been enumerated.

**Why this matters.** A feature that wants to count "redirects
specifically" (vs other knockback events such as ability-induced
Core knock-backs that aren't direct Strikes) should filter on
`EKnockBackType::Redirect` rather than counting all knockbacks.
The per-match aggregate `PMPlayerMatchSummary.RedirectRock`
already filters this way (otherwise the field would be named
`KnockBackRock` or similar) — but a feature reading
`LastRedirectKnockBack` directly should re-check the type field
to defend against future enum additions.

**Other inferred values (unconfirmed).** Some values are
presumably for non-Core knock-back events (e.g.,
ability-induced player knock-backs, environmental knockbacks).
A `enums.txt`-style dump of `EKnockBackType` would close this;
not yet performed.

## Cross-references

- **Player-side feel + cooldown discipline:** [`docs/game/core-and-strike.md`](../game/core-and-strike.md)
- **Per-match aggregate counters (RedirectRock, HitRockIntoGoalArea):** [`data-model.md` → "PMPlayerMatchSummary"](./data-model.md#pmplayermatchsummary)
- **The Rock naming gotcha:** [`data-model.md` → "The Rock naming gotcha"](./data-model.md#the-rock-naming-gotcha)
- **Match-phase gating (when does Strike fire):** [`game-state.md` → "Phase model"](./game-state.md#phase-model), [`game-state.md` → "Match detection"](./game-state.md#match-detection)
- **Per-player engine surface (DamageChanged etc.):** [`player-state.md`](./player-state.md)
- **Hooking patterns (RegisterHook, pre vs post):** [`ue4ss-version-and-gotchas.md` → "RegisterHook"](./ue4ss-version-and-gotchas.md#registerhook)
- **Glossary bridge:** [`docs/glossary.md` → "Core (a.k.a. Rock)"](../glossary.md#core-aka-rock), [`docs/glossary.md` → "Strike" (stub)](../glossary.md#stub-entries)
- **Sibling docs index:** [`docs/engine/README.md`](./README.md)

## Open questions

- **`PMRockCharacter` full UFunction surface.** A
  `GetClass:ForEachFunction` dump on `PMRockCharacter` would
  catalogue the per-event hooks (when does
  `LastRedirectKnockBack` get written? is there a
  `OnRedirected` UFunction we can hook?). High-value because
  it gates per-event capture features.
- **`PMRockCharacter` exposed properties.** Velocity, position,
  current-set-of-recent-touchers (for assist attribution),
  goal-area-overlap state. None catalogued.
- **`LastRedirectKnockBack` field shape.** Direction? Magnitude?
  Redirector reference (PlayerState? Pawn? Prometheus ID
  string?)? Timestamp? Pre-condition for any per-event redirect
  feature.
- **`StrikeReleased` / `StrikeDragged` parameter shapes.** What
  do the callbacks receive? Strike vector? Aim point? Hit-target
  reference? Hook the engine-side function and dump the params
  to find out.
- **Whether `StrikeReleased` fires for remote players.** Likely
  no (PlayerController is local), but worth confirming if a
  feature needs to observe opponents' Strikes.
- **Cooldown state location.** Probably on the Pawn / Striker
  character class. Finding it would enable cooldown-tracking
  features (e.g., a teammate-cooldown HUD).
- **Full `EKnockBackType` enum.** Type 2 = Redirect is
  catalogued; the other values aren't. Some are presumably for
  ability knock-backs (non-Core knock-back events).
- **Practice-mode Strike surface.** Does `PlayerController_Practice_C`
  expose `StrikeReleased` / `StrikeDragged`? Affects feature
  parity across modes.
