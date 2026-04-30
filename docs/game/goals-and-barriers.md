# Goals and barriers

How the *defending side* of every match works from the player's
seat. The goal is not a static open net — it's a small destructible
defensive structure that the attacking team has to chip down before
they can score freely.

> **Status:** seeded 2026-04-30 from
> [`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 7.
>
> **Last validated against game patch:** 2026-04. Goal/barrier
> geometry has been stable across recent seasons; barrier
> regeneration rules and per-arena variations are TBD (see [Open
> questions](#open-questions)). Re-validate when patch notes mention
> goal/barrier behavior or arena layout.

This doc covers the player-perceived mechanic. The engine-side
class names and confirmed per-match counters live in
[glossary → "Goal & Barrier"](../glossary.md#goal--barrier).

## TL;DR

- A **goal** is the net at each team's end of the arena. The Core
  must cross its line for the attacking team to score.
- A goal is **not always open**. It is fronted by one or more
  destructible **barriers** that have to be broken (or shot around)
  first.
- Barrier state is **public information** — both teams see which
  barriers are up, broken, or vulnerable, and play accordingly.
- Barrier state is **not cosmetic**. It changes every player's
  decision tree on the field — what to shoot, where to stand, when
  to commit.

## What the player observes

| Observation | Detail |
|---|---|
| **Each team has one goal.** | Two goals per arena, one per team, mirrored across the arena's midline. |
| **Each goal has barriers in front of it.** | Barriers are visible structures between the field and the goal line. The attacking team has to break or get the Core around them to score cleanly. |
| **Barriers take Core hits to break.** | Strikes that drive the Core into a barrier chip away at it. Direct ability hits may also damage barriers, depending on the kit. |
| **Once a barrier is broken, the goal behind it is "open".** | "Open goal" is the phrase players use. It means the Core has a clean line into the net through that barrier's lane. |
| **Both teams see barrier state.** | Barrier state is part of the public game state. Forwards know which barriers are vulnerable; goalies know which barriers are gone and where the open lanes are. |
| **Barrier state evolves across a round.** | Barriers chip down over a round of contested play, not in a single hit. The pacing of "barriers up → barriers chipped → barriers broken → goal open → goal scored" is the round arc. |

## Why barrier state changes every player's plan

The presence (or absence) of a barrier reframes every Strike
decision on the field, for both sides:

**For the attacking team:**

- **Barriers up** → Strikes are aimed *at the barrier* (to break it)
  or *around the barrier* (to score behind/past it). Both have lower
  scoring probability than a clean shot at an open goal.
- **Barriers chipped** → A barrier near breaking shifts pressure. A
  hard Strike *now* might break it; a Strike that misses might hand
  control to the defender.
- **Barriers broken** → The relevant lane is now an open-goal
  scoring window. Strikes target *the goal*, not the barrier. The
  pressure on the goalie spikes.

**For the defending team:**

- **Barriers up** → Goalie has the most defensive help. Strike
  reads can be more conservative; the barrier absorbs near misses.
- **Barriers chipped** → Goalie shifts to "do not let this barrier
  fall to a sloppy hit." Cooldown discipline increases.
- **Barriers broken** → Goalie is effectively defending an open
  goal. Energy Burst and clutch saves become much more likely
  expenditures (see `energy-evade-burst.md` *(planned)*).

The transition between these states is the round's tension curve.
A team can be **under heavy scoring pressure even before conceding**
just by having its barriers broken — the score might still be 0-0
but the next clean Strike likely ends the round.

## Implications across roles

- **Goalies** defend *both* the barriers and the goal itself. A
  goalie cannot only camp the line; they have to position to deny
  Strikes against the barrier, while staying close enough to make
  the on-line save when a barrier falls. See
  `roles.md` *(planned)*, "Goalie".
- **Forwards** typically coordinate to break barriers *before*
  going for the score. Two forwards can rotate Strikes onto a
  barrier far faster than a single forward — barrier breakage is
  often the team-coordination moment of a round.
- **Flexible / rotational play** still applies (`roles.md`
  *(planned)*, "Flexible / Rotational"). A forward might rotate
  back to defend a broken barrier; a goalie might step up to clear
  the Core before it has time to land another barrier hit.

## Why this matters for OSPlus

A handful of feature classes touch goal/barrier state directly:

- **Goalie training tools** — drill barrier-defending fundamentals.
  Need accurate barrier-state telemetry.
- **Goal/scoring HUD overlays** — anything that augments the player's
  read of "is this goal open or not" runs into the player-attention
  rules in [`in-match-hud.md` → "HUD discipline rules"](./in-match-hud.md#hud-discipline-rules).
  Adding a barrier-state HUD element is unlikely to be useful —
  barrier state is *already* one of the most visually obvious things
  on the field.
- **Replay / highlight tools** — barrier-break events are natural
  highlight moments. The (planned) `MatchPhaseChanged` and
  `SpawnGoalEffects` engine signals are the start of any
  reconstruction; see [glossary entry](../glossary.md#goal--barrier).

## Engine bridge (one-link summary)

- [glossary → "Goal & Barrier"](../glossary.md#goal--barrier) is the
  canonical bridge: confirmed `SpawnGoalEffects` UFunction,
  `PMPlayerMatchSummary.HitRockIntoGoalArea` per-player counter,
  `MatchPhaseChanged` event. Barrier object class and regeneration
  rules are TBD on the engine side.
- [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) → *Per-match runtime
  data* — full per-match counter table, including goal-related
  counters.
- `docs/engine/game-state-class.md` *(planned)* — eventual home for
  the GameState-side details.

Per ADR 0003, engine search-target lists do not live in this
player-side doc — start from the glossary entry and follow into the
engine docs.

## Open questions

- **Barrier object engine class.** Search candidates from the
  glossary: `Gate`, `Barrier`, `GoalBarrier`, `GoalArc`. Not yet
  confirmed. Any feature that touches barrier state directly will
  force this probe.
- **Barrier regeneration rules.** Do barriers reset between rounds?
  Between sets? Never (within a match)? Player observation suggests
  per-round reset, but this needs explicit confirmation against the
  engine. **TBD.**
- **Per-arena barrier variation.** Whether all arenas have the same
  goal/barrier geometry or whether some arenas have different
  numbers/shapes/positions of barriers. Player-doc Sec 7 is
  arena-agnostic; arena-specifics belong in `maps.md` *(planned)*.
  **TBD.**
- **Hit thresholds for barrier breakage.** How many "average"
  Strikes break a barrier? Does Strike speed/Awakening modifier
  matter? Player intuition says yes, but the rule is undocumented.
  **TBD.**
- **Barrier vs ability damage.** Confirmed conceptually that
  abilities can hit barriers (per Sec 10 ability-target hooks like
  `onBarrierHit`), but the per-ability behavior matrix is not
  catalogued here. Belongs in `strikers-and-abilities.md`
  *(planned)*.

## Cross-references

- High-level scoring objective: [`overview.md` → "Main gameplay objective"](./overview.md#main-gameplay-objective)
- The Core itself: [`core-and-strike.md`](./core-and-strike.md)
- Match flow / round/set structure: [`match-lifecycle.md`](./match-lifecycle.md)
- Player roles' relation to barriers: [`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 8 (until migrated to `roles.md`)
- HUD discipline (why barrier-state HUD additions are usually wrong): [`in-match-hud.md` → "HUD discipline rules"](./in-match-hud.md#hud-discipline-rules)
- Engine bridge: [glossary → "Goal & Barrier"](../glossary.md#goal--barrier)
- Sibling docs index: [`docs/game/README.md`](./README.md)
