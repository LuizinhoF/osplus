# Data model — per-match runtime data shapes

The *"what counters / structs / objects expose per-match
quantitative state, and where do they live"* doc — read this
before designing any feature that captures, displays, or
aggregates per-match numbers (redirects, KOs, damage, orb
pickups, save count). Distilled from
[`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) §"Per-match runtime
data — what's reachable from Lua".

> **Status:** seeded 2026-05-01 from
> [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md). The
> `PMPlayerMatchSummary` field shape was probed end-to-end as
> part of the `in-game-profile-mvp` Pass-3 work (offsets +
> types confirmed via `sps`-style dump). The mapping from
> `PMPlayerMatchSummary` *instance* back to *which player
> owns it* is open.
>
> **Stability:** struct field offsets are stable across patches
> within a UE major version. The `EPMEndOfGameStat` enum is
> stable. Connection-mapping questions are open.

This doc is the *runtime data shapes* for per-match observable
quantities. The *backend aggregate* equivalent (career stats
exposed by the Prometheus API) is in
[`identity-and-api.md` → "What the backend exposes"](./identity-and-api.md#what-the-backend-exposes)
— **with the critical capture gap** (Redirects don't appear in
the backend aggregates, only in client-side runtime data).

## TL;DR

- **`PMPlayerMatchSummary` is a per-player-per-match counter
  ScriptStruct** with 4 fields: `RedirectRock`,
  `PowerUpsPickedUpCount`, `HitRockIntoGoalArea`,
  `DamageDoneToPlayers`. See [§"PMPlayerMatchSummary"](#pmplayermatchsummary).
- **`EPMEndOfGameStat` is the full 9-value stat enum** of what
  the EOG screen surfaces: `Goals`, `Assists`, `Saves`, `KOs`,
  `Redirects`, `ShotsOnGoal`, `Damage`, `PowerUps`, plus
  `None`. See [§"EPMEndOfGameStat enum"](#epmendofgamestat-enum).
- **`PMPlayerMatchSummary` only covers 4 of the 9.** The other
  5 (Goals / Assists / Saves / KOs) live on a sibling structure
  — likely `PMPlayerState` or a sibling. **Open question.**
- **The puck is internally called "Rock", not "Ball" or
  "Core".** `PMRockCharacter` is the puck actor; grep `Rock`
  for puck stuff. See [§"The 'Rock' naming gotcha"](#the-rock-naming-gotcha).
- **Per-event redirect detail lives at
  `PMRockCharacter:LastRedirectKnockBack`.** For per-event
  granularity (vs per-match aggregate), this is the surface.
- **`EKnockBackType::Redirect = 2`.** Redirects are classified
  knock-backs of type 2.
- **Redirects are the canonical OSPlus capture target** because
  they are the most-prominent per-match signal that **the
  backend API does NOT expose** (see [`identity-and-api.md` →
  "What the backend does NOT expose"](./identity-and-api.md#what-the-backend-does-not-expose--the-osplus-capture-gap)).

## `PMPlayerMatchSummary`

`/Script/Prometheus.PMPlayerMatchSummary` ScriptStruct — per-
player-per-match counter struct.

| Offset | Field | Type | EOG stat # |
|---|---|---|---|
| `0x00` | `RedirectRock` | Int | 5 (Redirects) — **the canonical OSPlus capture target** |
| `0x04` | `PowerUpsPickedUpCount` | Int | 8 (PowerUps) |
| `0x08` | `HitRockIntoGoalArea` | Int | 6 (ShotsOnGoal) |
| `0x0C` | `DamageDoneToPlayers` | Int | 7 (Damage) |

**Naming.** `RedirectRock` means "this player redirected the
Rock (Core) N times this match" — the redirect count, the
canonical OSPlus capture target. `HitRockIntoGoalArea` is
"shots on goal" in player-side terms (whether the shot scored
or was saved is encoded elsewhere; this counter just measures
attempts that crossed into the goal zone).

**Reachability.** `PMPlayerMatchSummary` is a `ScriptStruct`,
not a `UObject` — `FindFirstOf` doesn't return ScriptStructs
directly. You need to find a UObject that *contains* one (e.g.,
on `PMPlayerState`, on `PMGameState`, etc.). **Where these
struct instances are held — open question.** See
[§"Open questions"](#open-questions).

## `EPMEndOfGameStat` enum

The full per-match stat universe surfaced at end-of-match:

```text
None        = 0
Goals       = 1
Assists     = 2
Saves       = 3
KOs         = 4
Redirects   = 5
ShotsOnGoal = 6
Damage      = 7
PowerUps    = 8
```

**`PMPlayerMatchSummary` covers 4 of those 9** (Redirects,
PowerUps, ShotsOnGoal, Damage). The other 5 (Goals, Assists,
Saves, KOs) live on a sibling structure — most likely
`PMPlayerState` (the C++ parent of `PlayerState_Game_C`) or
another summary keyed off it. See
[`docs/learnings/os-runtime-data-model.md`](../learnings/os-runtime-data-model.md)
for the detailed RE diary, and
[§"Open questions"](#open-questions) for what's still unknown.

## Other relevant runtime objects

### `PMEndOfGamePlayerUIData`

UObject that drives the EOG UI surface. Carries a `Redirects`
field (typed Struct) — probably wraps the same counter as
`PMPlayerMatchSummary.RedirectRock` for display purposes. If
you're hooking the EOG screen specifically, this is closer to
the UI than the raw counter.

### `PMRockCharacter:LastRedirectKnockBack`

Field on the puck character itself. **Per-event detail** vs the
per-match aggregate counter on `PMPlayerMatchSummary`. The
struct presumably carries the redirecting-player reference,
direction, magnitude, timestamp.

For a feature that needs *per-redirect* data (replay-style
"who redirected when"), this is the surface to hook around.
For just the per-match count, `PMPlayerMatchSummary.RedirectRock`
is simpler.

Per-Striker / per-event detail is in
[`rock-and-strike.md`](./rock-and-strike.md) (TBD batch 3).

### `EKnockBackType::Redirect = 2`

Knock-backs are classified in an enum; redirect is type 2. Other
types are presumably for non-redirect knock-back events (e.g.,
ability-induced knock-backs that aren't strikes-on-the-Core).
The full enum has not been catalogued; probe target.

## The "Rock" naming gotcha

**The puck is internally called "Rock", not "Ball" or "Core".**

Player-facing language is "Core" (per
[glossary → Core (a.k.a. Rock)](../glossary.md#core-aka-rock)).
The engine-side name is "Rock" everywhere:

- `PMRockCharacter` — the puck actor.
- `RedirectRock` — the redirect counter on
  `PMPlayerMatchSummary`.
- `HitRockIntoGoalArea` — the shots-on-goal counter.
- `Set Random Power Orb` — the power-orb function
  (note: orb, not Rock — distinct from the Core).

**Future grep / reverse-engineering rule:** when looking for
the puck in dumps, search `Rock`, not `Ball`, `Puck`, or `Core`.
A search for `Core` will yield power-orb / system-class hits
that are not the puck.

## Cross-references

- **The match-phase model (when these counters exist):** [`game-state.md`](./game-state.md)
- **The per-player engine surface (where these structs likely live):** [`player-state.md`](./player-state.md)
- **The puck actor and Strike events:** `rock-and-strike.md` (TBD batch 3)
- **The backend aggregate equivalents + the OSPlus capture gap:** [`identity-and-api.md` → "What the backend exposes"](./identity-and-api.md#what-the-backend-exposes), [`identity-and-api.md` → "What the backend does NOT expose"](./identity-and-api.md#what-the-backend-does-not-expose--the-osplus-capture-gap)
- **The runtime data model in full (RE diary):** [`docs/learnings/os-runtime-data-model.md`](../learnings/os-runtime-data-model.md)
- **The Rock vs Core glossary entry:** [`docs/glossary.md` → "Core (a.k.a. Rock)"](../glossary.md#core-aka-rock)
- **Player-side equivalent — how players perceive these stats:** [`docs/game/post-match.md`](../game/post-match.md), [`docs/game/in-match-hud.md`](../game/in-match-hud.md)
- **Sibling docs index:** [`docs/engine/README.md`](./README.md)

## Open questions

- **How does a `PMPlayerMatchSummary` instance map back to its
  player?** Held by `PMPlayerState` (one per player)? On an
  array on `PMGameState`? Keyed by `PlayerId`? **The single
  most important open question on this surface** because it
  gates any feature that wants to read per-player redirect
  counts from Lua. Probe target.
- **Where do Goals / Assists / Saves / KOs live?** Likely
  `PMPlayerState` or a sibling summary. The `EPMEndOfGameStat`
  enum lists all 9 stats; `PMPlayerMatchSummary` only carries
  4. The other 5 must come from somewhere — finding them is
  pre-condition for full per-match capture.
- **Lifetime of `PMPlayerMatchSummary` instances.** Persists
  across match-end? Replaced per-match? Held for the session?
  Affects when post-match capture can read these.
- **`PMEndOfGamePlayerUIData.Redirects` struct shape.** Inferred
  to wrap the same counter as `PMPlayerMatchSummary.RedirectRock`
  but not confirmed. If the struct carries additional fields
  (pretty-print formatting, per-set breakdown, etc.), worth
  knowing.
- **`PMRockCharacter:LastRedirectKnockBack` struct fields.**
  Direction? Magnitude? Redirector reference? Timestamp?
  Probe before any feature design that wants per-event redirect
  detail.
- **Full `EKnockBackType` enum values.** Type 2 = Redirect is
  catalogued; the other values aren't. Some are presumably for
  ability knock-backs (non-Core knock-back events).
