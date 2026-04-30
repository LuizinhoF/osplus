# Power Orbs

Neutral pickups that spawn during play and create the only
*shared third-party objective* in a match. Both teams want them;
neither team starts with them. Orbs are the contestable resource
that pulls teams off their default positions.

> **Status:** seeded 2026-04-30 from
> [`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 14.
>
> **Last validated against game patch:** 2026-04. Orb spawn cadence
> and reward values are patch-volatile (and likely tuned per arena).
> Re-validate when patch notes mention orbs, comeback mechanics, or
> arena-specific neutral objectives.

This doc is the player-side mechanic. Engine class names for the
Orb actor and the spawn rule are not catalogued in this docset and
are surfaced as TBDs in [Open questions](#open-questions).

## TL;DR

- **An Orb is a neutral pickup** that appears at known locations
  in the arena during play. Either team can grab it.
- **Picking up an Orb gives the player some combination of:**
  stagger recovery, experience / leveling progress, Energy gain,
  and other smaller benefits. The exact reward set is patch- and
  context-dependent.
- **Orbs create micro-objectives** that distort positioning. Two
  teams that would otherwise stay in their lanes are pulled
  together over an Orb spawn point.
- **Orbs are the comeback engine.** A staggered, low-Energy
  losing team grabbing the right Orb at the right moment can
  reverse the match flow.

## What an Orb is (player perspective)

| Observation | Detail |
|---|---|
| **Visible third-party object.** | An Orb is clearly distinct from the Core, players, and arena geometry — recognizably *a pickup*. |
| **Spawns during play, not at round start.** | Orbs appear mid-round at scripted or rules-driven moments. Spawn cadence is TBD in this docset. |
| **Has a fixed pickup interaction.** | Walking onto the Orb collects it; this isn't an action with a cooldown. |
| **First-come-first-served.** | The Orb belongs to whoever touches it first. There's no "carry" or "deposit" — the benefit is granted on pickup. |
| **Both teams see the spawn.** | Spawn locations and timings are public information; the contest is real, not hidden. |

## What an Orb gives the player

The reward set, as observed by players (exact rules and per-arena /
per-mode variation **TBD**):

- **Stagger recovery.** Reduces the player's stagger meter,
  making them less knockback-vulnerable. Often the most
  immediately useful effect for a player at high stagger.
- **Experience / level progress.** Contributes to in-match
  leveling — note that *match-level* leveling is a separate axis
  from Awakening drafts (see
  [`awakenings.md`](./awakenings.md)). Specific level mechanics
  are not yet documented in this docset.
- **Energy gain.** Fills (or partially fills) the Energy meter,
  enabling earlier Evade or Burst (see
  [`energy-evade-burst.md`](./energy-evade-burst.md)).
- **Possibly more.** Additional/situational rewards may apply per
  patch, per arena, per mode. **TBD.**

The Orb effectively acts as a **multi-resource boost** — and
because each of those resources matters, the Orb is contested by
both teams almost regardless of match state.

## Why Orbs distort positioning

Without Orbs, teams default to:

- Goalie near own goal.
- Forwards in the enemy half.
- The Core wherever it is.

With Orbs:

- Both teams allocate someone to contest the Orb.
- That contest **pulls a defender out of position** or **pulls a
  forward away from the Core**.
- The team that *wins* the Orb gains resources; the team that
  *loses* it gains an opening (the contesting opponent is now
  out of position).

This is why an Orb spawn is rarely a free pickup — even an "easy"
Orb costs *something* for someone on the team. Read against
position and timing, the strategic question becomes:

> "Is this Orb worth the positional cost of contesting it?"

A goalie on the verge of a clutch save shouldn't leave the goal
for an Orb. A forward who already has full Energy probably
shouldn't sprint across the map for one either. Orb decisions are
context-dependent.

## Orbs as the comeback engine

OS matches can snowball. The team that scores first tends to have:

- Higher Energy availability (recently spent for the goal but
  refilling).
- Better momentum and confidence.
- Possibly an Awakening edge from the next draft.

Orbs are one of the main systems that **prevent guaranteed
snowballs**. Specifically:

- **Stagger recovery** lets a beaten-down losing team get back to
  full combat readiness.
- **Energy gain** gives a low-resource losing team a Burst they
  wouldn't otherwise have.
- **Experience** keeps the leveling curve close enough that the
  losing team isn't permanently outscaled.

A losing team that contests Orbs aggressively *makes its own
comeback chances*. A losing team that ignores Orbs almost
certainly loses worse.

For OSPlus design context: this is why a feature that says "let me
auto-take the Orb" or "let me skip the Orb micro-objective" would
break the game's comeback design. Orbs aren't bonus loot; they're
a **balancing mechanism** built into match pacing.

## Why this matters for OSPlus

Orbs are a moderate-leverage feature surface. Several feature
classes touch Orb mechanics directly or indirectly:

- **Orb timer / spawn HUD overlays.** Calling out the next spawn
  ahead of time is a real value-add — it lets the team coordinate
  the contest. *But* it has to clear the
  [`in-match-hud.md` → "HUD discipline rules"](./in-match-hud.md#hud-discipline-rules)
  bar (small, peripheral, only when relevant).
- **Orb training tools.** Drills around contesting / denying Orbs
  are reasonable.
- **Replay / highlight tools.** Orb pickups at pivotal moments are
  natural highlight markers.
- **Post-match Orb analysis.** Orbs taken / Orbs lost / Orb-related
  comeback ratings are useful retrospective signals.

Avoid:

- Anything that pre-resolves Orb contests for the player.
- Anything that hides Orb spawns from one team.
- Anything that visually clutters the area around an Orb spawn
  (the contest needs to be readable).

## Engine bridge (one-link summary)

Orb-related engine names are NOT catalogued in this docset.
Search candidates from the legacy monolith's Sec 14:

- Orb actor class — likely `PMPowerOrb*`, `PowerOrb*`, or
  `Orb*`. **TBD.**
- Orb spawn rule / spawner — likely lives on the GameMode or per-
  arena `Spawner` actor. **TBD.**
- Per-match Orb counter — likely `PMPlayerMatchSummary` field with
  `Orb` in the name (e.g., `OrbsPickedUp`, `OrbsContested`).
  **TBD.**

Per ADR 0003, engine search-target lists do not live here. Start
from [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) and follow into
the (planned) `docs/engine/power-orbs.md`.

## Open questions

- **Orb spawn cadence.** Are spawns on a fixed timer, on score
  events, on round-elapsed thresholds, or some hybrid? Player
  observation suggests roughly periodic but with possible round-
  state triggers. **TBD.**
- **Orb spawn locations per arena.** Player observation: spawn
  points are arena-specific and stable per arena. The full per-
  arena map of spawn points is **TBD; belongs in `maps.md`
  *(planned)* once known.**
- **Exact reward values.** Each Orb's stagger / Energy / XP grant
  amounts are not catalogued. Are they uniform across Orbs, or
  does each Orb have a tier / type? **TBD.**
- **Multiple Orb types?** Player observation suggests Orbs are
  uniform within a match, but possibly different types in
  different modes / arenas. **TBD.**
- **Orb interaction with Awakenings.** Sec 15 lists "Orb effects"
  as one Awakening modification dimension, suggesting Awakenings
  exist that change Orb behavior. **TBD; per-Awakening matrix
  belongs ad-hoc in `awakenings.md`, not catalogued here.**
- **Per-Striker pickup ability differences.** Whether some kits
  pick up Orbs faster, contest more efficiently, or otherwise
  interact with Orbs differently — TBD.

## Cross-references

- Combat context (stagger recovery is the most immediate Orb
  payoff): [`combat.md`](./combat.md)
- Energy context (Energy gain is the second most immediate Orb
  payoff): [`energy-evade-burst.md`](./energy-evade-burst.md)
- Match flow (Orbs shape mid-round pacing, not goal/round events):
  [`match-lifecycle.md`](./match-lifecycle.md)
- Roles (forwards typically contest more than goalies): [`roles.md`](./roles.md)
- Awakenings that may modify Orb behavior: [`awakenings.md`](./awakenings.md)
- HUD discipline (any Orb HUD overlay must respect this bar):
  [`in-match-hud.md` → "HUD discipline rules"](./in-match-hud.md#hud-discipline-rules)
- Per-arena Orb spawn locations (when documented): `maps.md` *(planned)*
- Sibling docs index: [`docs/game/README.md`](./README.md)
