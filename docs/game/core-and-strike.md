# The Core and the Strike

The player-side mechanics of the central gameplay object (the Core)
and the central player input (the basic Strike). Everything in
Omega Strikers ultimately routes through these two.

> **Status:** seeded 2026-04-30 from
> [`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 11 + Sec 5
> depth that didn't fit in [`overview.md`](./overview.md).
>
> **Last validated against game patch:** 2026-04. Core / Strike have
> been mechanically stable across seasons, but cooldowns and Strike
> hitbox tuning move. Re-validate this doc when patch notes mention
> anything in the cooldowns/hitbox/redirect-knockback area.

This doc is the *player-side* depth. The bridge to engine reality
(class names, UFunctions, knockback enums, per-match counters)
lives in [glossary → "Core (a.k.a. Rock)"](../glossary.md#core-aka-rock)
and from there into [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) →
*Per-match runtime data*.

## TL;DR

- **The Core is internally called "Rock".** All engine work uses
  `Rock`. The player calls it "the Core" (or "the puck"); both are
  this thing.
- **A Strike is a short-cooldown active that hits the Core (or
  another player) in a direction the player aims.** It is not a
  passive collision and it is not a free action.
- **Most plays in the game are a sequence of Strikes alternating
  between teams.** Strike timing is the load-bearing skill.

## What the player observes about the Core

Player-perceptible Core behavior, in roughly the order the player
learns it:

| Behavior | What the player notices |
|---|---|
| **Carries momentum.** | The Core has visible velocity. Faster Core = more dangerous (harder to react to, more knockback when it lands). |
| **Bounces off walls and barriers.** | Predictable rebounds; experienced players play angles. |
| **Redirects on hit.** | Any Strike (or ability that hits the Core) sends it in a new direction with new speed. Direction is a function of *the hit's vector and the Core's prior velocity* — it is not a pure "shoot toward where you aim". |
| **Single instance per arena.** | There is exactly one Core. You cannot lose track of "which one is real" — only "where is it." |
| **Not owned, in the persistent sense.** | The Core does not belong to a team. *Last-touch credit* exists for attribution (assist / score), but neither team "has the Core" the way a soccer team has possession in a held sense. |
| **Goal entry triggers a round end.** | Crossing the goal line ends the round and begins a reset; the Core respawns at center on the next round. |

Implication for any UI / VFX feature: the *visual* Core is the
load-bearing referent for almost every player decision. Anything
that obscures, recolors, doubles, blurs, or duplicates the Core
visually is deeply hostile to play. See
[`overview.md` → "The Core is the main gameplay object"](./overview.md#the-core-is-the-main-gameplay-object)
for the design-rule statement.

## What "controlling the Core" looks like

Players never describe themselves as "having" the Core for more than
a fraction of a second. Instead, the verbs are:

- **Redirect** — change the Core's direction by Striking it.
- **Clear** — Strike the Core *away from danger* (usually away from
  one's own goal).
- **Pass** — Strike the Core *toward a teammate's path*.
- **Stuff** — score from point-blank past a goalie, usually after
  forcing them to commit a Strike or ability.
- **Deny** — Strike the Core *out of an enemy's reach* before they
  can act on it.
- **Rebound** — set up a Strike that uses a wall/barrier to redirect.
- **Force a bad Strike** — play in a way that makes the enemy spend
  their Strike on a low-value redirect, opening their cooldown.

**None of these are "hold the ball" actions.** The Core is in motion
or contested almost all the time. A "good touch" is one that survives
into the next contested moment.

## The basic Strike

The Strike is the most-used input in the game. It is to Omega
Strikers what the basic attack is to a fighting game and what the
shoot is to a sports game — both at once.

### What a Strike does

| Effect | Detail |
|---|---|
| **Hits the Core (if in range).** | Redirects the Core based on the Strike vector + the Core's current motion. Adds knockback magnitude. |
| **Hits enemy players (if in range).** | Deals stagger damage and contributes to the KO threshold (see `combat.md` *(planned)*). |
| **Hits both (if both are in range).** | Both happen on the same Strike. Forwards exploit this to apply Core pressure *and* stagger pressure simultaneously. |
| **Has a cooldown.** | Strike is gated by a short cooldown; spamming is impossible. The cooldown is what makes Strike a *resource* and creates the mind game. |

### Why Strike timing is load-bearing

Strike is the thing experienced players bait, force, and punish.
Concretely:

- **Bait.** Players posture as if to Strike, hoping the opposing
  goalie commits their own Strike on empty air and is then locked
  out of the next exchange.
- **Force.** Sustained pressure from a forward leaves the goalie
  with no choice but to Strike defensively, opening a cooldown
  window for the next Strike to score through.
- **Punish.** A wasted Strike from an enemy is a free open window
  to Strike the Core through them, against an empty goal area, or
  through a now-broken barrier.
- **Stuff.** A goalie whose Strike just went on cooldown can be
  scored on at point-blank range — colloquially "stuffed."

The cooldown loop is the heartbeat of every match. A player can be
mechanically average and still win exchanges through Strike timing
discipline; a player can have perfect aim and still lose exchanges
through Strike timing carelessness.

### What Strike is not

- **Not free.** Cooldowns punish thoughtless inputs.
- **Not passive.** Walking into the Core does not Strike it; the
  player must press the input.
- **Not just a Core action.** It hits players too, and that
  interaction is what makes "Strike *and* stagger pressure" a real
  combo, not two separate things.
- **Not a melee-only action for every Striker.** Some Strikers have
  Strike behavior modified by their kit (e.g., projectile-style
  Strikes). Striker identity colors the Strike — see
  `strikers-and-abilities.md` *(planned)*.

## Core ownership and attribution

From the player's perspective, the Core does not belong to anyone in
the persistent sense — but the game *does* attribute scoring,
assists, and saves after the fact. This affects post-match stats and
end-of-match feel.

Player-observable attribution rules (rough; engine-side rules are
TBD):

- **Score credit** goes to the player whose Strike most recently put
  the Core into the goal. "Most recently" is the load-bearing word —
  this is *not* who hit the Core hardest or whose touch had the
  longest carry.
- **Assist credit** appears to go to a recent prior toucher within
  some short attribution window. Window length is TBD.
- **Save credit** appears to go to whoever Strikes the Core out of
  imminent goal danger.
- **Redirects** are tracked per-player as `RedirectRock` on the
  per-match summary (see [glossary entry](../glossary.md#core-aka-rock));
  the player feels this as "how often I touched the Core in a way
  that mattered."

These attribution windows matter for OSPlus features that try to
*reconstruct* who did what (e.g., a "highlight reel" or a "you got
the assist" overlay). The reconstruction must use the engine's
attribution, not invent its own — the player will trust the game's
end-of-match stats over an OSPlus overlay that disagrees.

## Engine bridge (one-link summary)

Everything in this doc is *player-perceived*. The engine-side
reality (class names, UFunctions, per-match counters, knockback
enums) lives in:

- [glossary → "Core (a.k.a. Rock)"](../glossary.md#core-aka-rock) —
  the canonical bridge: `PMRockCharacter`, `PMPlayerMatchSummary.RedirectRock`,
  `EKnockBackType::Redirect = 2`.
- [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) → *Per-match runtime
  data* — full per-match counter table.
- `docs/engine/rock-and-strike.md` *(planned)* — engine-side topic
  doc, when migrated out of `KNOWLEDGEBASE.md`.

If a search target is wanted (e.g., "where does Strike cooldown
live?"), use the [glossary entry](../glossary.md#core-aka-rock) as
the entry point and follow into the engine docs from there. **Do
not** add engine grep targets directly to this player-side doc — per
ADR 0003, engine search-target lists belong in `docs/engine/`, not
here.

## Open questions

- **Assist window length.** How long after a touch does a player
  still earn assist credit on a subsequent goal? Probably some
  small number of seconds. TBD.
- **Save window / goal-line proximity rule.** When does a Strike
  count as a "save" vs just a clear? TBD; likely a function of how
  close the Core was to the goal line at clear time.
- **Strike hitbox vs Strike visual.** Is the hit volume exactly the
  visual swing arc, or is it a bit larger/smaller? Affects
  expectations on what "should have hit." TBD; probably documented
  in the (planned) engine doc once a Strike-cooldown probe lands.
- **Per-Striker Strike modifiers.** Confirmed conceptually (some
  kits modify Strike behavior — projectile-style, extended range,
  etc.) but the per-Striker matrix is not in this doc. Belongs in
  `strikers-and-abilities.md` *(planned)*.
- **Last-touch attribution rules under simultaneous-Strike edge
  cases.** Two players Strike the Core in the same frame — who gets
  credit? TBD.

## Cross-references

- High-level Core importance: [`overview.md` → "The Core is the main gameplay object"](./overview.md#the-core-is-the-main-gameplay-object)
- Engine bridge: [glossary → "Core (a.k.a. Rock)"](../glossary.md#core-aka-rock)
- Match flow context: [`match-lifecycle.md`](./match-lifecycle.md) (round structure; goals end rounds)
- Goal-area mechanics: [`goals-and-barriers.md`](./goals-and-barriers.md)
- Per-match counters / attribution: [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) → *Per-match runtime data*
- Sibling docs index: [`docs/game/README.md`](./README.md)
