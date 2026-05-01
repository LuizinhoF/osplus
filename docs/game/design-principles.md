# OSPlus design principles

The seven cross-cutting design constraints that govern any
gameplay-touching OSPlus feature. Originally enumerated in
[`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 27, now
canonical here.

> **Status:** seeded 2026-05-01 from
> [`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 27.
>
> **Last validated against game patch:** 2026-04. These principles
> are *meta-stable* — they reflect what makes Omega Strikers
> *play well*, not what's in the current patch. Re-validate only
> if the game itself fundamentally changes shape (e.g., a sequel,
> a new mode that breaks the assumed rules).

These principles are the *governing layer* for every other doc in
[`docs/game/`](./README.md). Each individual gameplay doc (combat,
energy, awakenings, etc.) restates whichever principle is most
load-bearing for that doc's content; this doc is the canonical
home for all seven together.

## TL;DR

Seven principles. Each one is a **design constraint**, not a
recommendation. A feature should satisfy all seven (or have a
deliberate, documented reason for violating one).

1. [Preserve Core readability](#preserve-core-readability) — the Core
   is the load-bearing visual referent in every match.
2. [Preserve goalie agency](#preserve-goalie-agency) — defenders
   need reasonable tools to defend.
3. [Preserve forward pressure](#preserve-forward-pressure) — attackers
   need ways to create threats.
4. [Respect cooldown mind games](#respect-cooldown-mind-games) —
   timing is the load-bearing skill on top of aim.
5. [Respect Striker identity](#respect-striker-identity) — kits
   should stay distinct.
6. [Avoid visual pollution](#avoid-visual-pollution) — OS is
   already visually busy.
7. [Design around sets, not just goals](#design-around-sets-not-just-goals)
   — the match evolves across sets, not just round-to-round.

The compact summary lives at
[`overview.md` → "OSPlus design principles (compact)"](./overview.md#osplus-design-principles-compact);
this doc is the long-form treatment.

## Preserve Core readability

The Core must always be easy to see and understand. Anything that
makes the Core harder to track is hostile to play.

**Avoid:**

- Large opaque VFX over the Core (especially during contested
  moments).
- UI overlays that sit near or in front of the Core.
- Skins or art that obscure Core direction (the Core's *velocity
  vector* needs to be readable; a Core that always looks
  stationary is a Core that's hostile to track).
- Map art that visually blends with the Core.
- Too many simultaneous indicators stacked over the Core.

**Why this principle is load-bearing:** the Core *is* the game
(see [`overview.md` → "The Core is the main gameplay object"](./overview.md#the-core-is-the-main-gameplay-object)
and [`core-and-strike.md`](./core-and-strike.md)). Every player
decision routes through reading the Core. If a feature degrades
that read, it degrades every other decision the player makes.

## Preserve goalie agency

Goalies need reasonable tools to defend. A change that makes
defense unreactive turns the game into a one-sided dunk.

**Avoid:**

- Unreactable scoring patterns (no read, no recourse).
- Unavoidable stuffing (point-blank scoring without a counter).
- Visual clutter inside the goal area (the area where Core reads
  matter most).
- Too many forced open-goal states (open-goal pressure should be
  *earned*, not constant).
- Abilities that remove defensive counterplay entirely.

**Why this principle is load-bearing:** goalies are
load-bearing for match pacing. A goalie role that can't actually
goalie collapses the match into a high-score-fest with no tension.
See [`roles.md` → "Goalie"](./roles.md#goalie) for the player-side
detail.

## Preserve forward pressure

Forwards need ways to create threats. A change that makes offense
impossible collapses the match into a 0-0 stalemate.

**Avoid:**

- Goalies becoming too safe (no scoring chances generate).
- Defensive tools that erase all pressure (forwards have no work
  to do).
- Barrier systems that are too hard to break (offensive
  coordination yields nothing).
- Maps where offense cannot create angles (no scoring routes).

**Why this principle is load-bearing:** OS depends on the
goalie/forward *tension*. If forwards can't generate threats, the
goalie/forward dynamic collapses. See
[`roles.md` → "Forward"](./roles.md#forward) for the player-side
detail and [`goals-and-barriers.md`](./goals-and-barriers.md) for
the barrier mechanics that gate offensive routing.

## Respect cooldown mind games

Players bait, force, and punish each other's cooldowns — Strike,
ability, Energy. This timing layer is what separates mechanical
proficiency from match-winning.

**Important interactions to preserve:**

- **Bait Strike** — pressure the enemy until they Strike on empty
  air, opening their cooldown.
- **Force goalie ability** — coordinate offense to make the goalie
  burn defensive cooldowns.
- **Punish wasted Evade** — an Evade-on-cooldown enemy is a
  KO target.
- **Wait for enemy projectile** — bait, dodge, counter-pressure
  during recovery.
- **Use Core timing to force bad reactions** — Core position +
  velocity make the enemy commit before they want to.

**Avoid:**

- Cooldown-erasing mechanics that flatten the timing layer.
- "Always-on" abilities that remove the read.
- Visual changes that hide cooldown state (own or enemy's).
- Auto-timing features (mod-side) that take the read away from
  the player.

**Why this principle is load-bearing:** cooldown timing is the
*reason high-skill OS looks different from low-skill OS*. Aim and
positioning are necessary; cooldown reads are sufficient. Any
feature that flattens this layer flattens the skill ceiling. See
[`core-and-strike.md` → "Why Strike timing is load-bearing"](./core-and-strike.md#why-strike-timing-is-load-bearing)
and [`energy-evade-burst.md`](./energy-evade-burst.md).

## Respect Striker identity

Each Striker should keep a recognizable rhythm. Kits should not
all feel the same.

**Avoid:**

- Universal mechanics that override per-Striker flavor.
- Awakenings that erase a Striker's intended weakness too easily
  (a melee brawler with ranged poke is no longer a brawler).
- Balance changes that remove signature play patterns (a hook
  character whose hook is unconditional has no hook mind game).
- Mod features that smooth out kit differences in pursuit of
  "consistency."

**Why this principle is load-bearing:** part of why each Striker
is fun is that they play *differently*. Sameness is the failure
state, not the success state. See
[`strikers-and-abilities.md` → "Striker identity as a design constraint"](./strikers-and-abilities.md#striker-identity-as-a-design-constraint)
for the full player-side treatment.

## Avoid visual pollution

Omega Strikers is already visually busy. A new mod feature should
be visually quiet unless it communicates something genuinely
important.

**Before adding any visual element, ask:**

- Does this help the player make a decision? (If no, cut it.)
- Can it be smaller?
- Can it be shown only when relevant (event-triggered, not
  always-on)?
- Can it be moved away from the Core (peripheral, not central)?
- Can it be represented with existing UI language (not a novel
  visual that the player has to learn)?

**Why this principle is load-bearing:** the player's attention is
finite (see [`in-match-hud.md` → "What the player tracks (perception load)"](./in-match-hud.md#what-the-player-tracks-perception-load)).
Every new visual element is paid for in attention budget; that
budget is already tight. The
[`in-match-hud.md` → "HUD discipline rules"](./in-match-hud.md#hud-discipline-rules)
operationalize this principle for in-match HUD specifically.

## Design around sets, not just goals

The match evolves across sets through Awakening drafts. A feature
that only considers a single goal-round will miss most of the
match's actual dynamics.

**A feature should consider:**

- **Early set state** — both teams at base power, no Awakenings
  yet drafted (or only the starting one).
- **Late set state** — one or both teams have an Awakening edge;
  resource Energy meters more important; stagger states
  accumulating.
- **Match point** — one team is one set from winning; pressure
  asymmetry.
- **Comebacks** — Power Orbs + Awakening drafts as
  comeback-enabling systems. (See
  [`power-orbs.md` → "Orbs as the comeback engine"](./power-orbs.md#orbs-as-the-comeback-engine)
  and [`awakenings.md`](./awakenings.md).)
- **Awakening scaling** — some Awakenings shine more in late
  sets; the match's "equilibrium" shifts as drafts accumulate.
- **Enemy adaptation** — the enemy team's drafts change the
  matchup mid-match.
- **Team adaptation** — your own team's drafts compound or
  fragment depending on coordination.

**Why this principle is load-bearing:** OS matches are not
single-goal contests. Designing as if they were collapses the
strategic depth that comes from multi-set adaptation. See
[`match-lifecycle.md` → "Match structure (sets, rounds, goals)"](./match-lifecycle.md#match-structure-sets-rounds-goals)
for the structure these principles operate within.

## Putting them together

Any feature touching live gameplay should pass a quick mental
checklist against all seven:

```text
1. Does it preserve Core readability?              (the visual contract)
2. Does it preserve fair goalie/forward dynamics?  (the role contract)
3. Does it respect cooldown mind games?            (the timing contract)
4. Does it preserve Striker identity?              (the kit contract)
5. Does it avoid visual pollution?                 (the attention contract)
6. Does it design around sets, not just goals?     (the match-shape contract)
7. Does it help the player make a decision?        (the *purpose* contract)
```

The seventh entry is meta — it's the *why* behind the other six.
Any feature that doesn't help the player make a better decision
is a feature whose value is unclear before considering whether it
violates any of the other principles.

If the answer to any is unclear, prefer **a smaller, more
readable, less invasive feature**. The default in OS modding is
*restraint*, not *expressiveness*.

## How this doc relates to others

| Other doc | Relationship |
|---|---|
| [`overview.md`](./overview.md) | Compact restatement (the eight-bullet OSPlus checklist). |
| [`core-and-strike.md`](./core-and-strike.md) | Operationalizes "preserve Core readability" + "respect cooldown mind games." |
| [`goals-and-barriers.md`](./goals-and-barriers.md) | Operationalizes "preserve goalie agency" + "preserve forward pressure" via barrier mechanics. |
| [`roles.md`](./roles.md) | Restates the goalie/forward principles with player-side context. |
| [`combat.md`](./combat.md) | The combat side of "preserve goalie agency" + "preserve forward pressure" + the load-bearing role of arena edges. |
| [`energy-evade-burst.md`](./energy-evade-burst.md) | The Energy / cooldown side of "respect cooldown mind games." |
| [`power-orbs.md`](./power-orbs.md) | "Design around sets" — Orbs as the comeback enabler. |
| [`awakenings.md`](./awakenings.md) | "Design around sets" + "respect Striker identity" — Awakenings can either reinforce identity or flatten it. |
| [`strikers-and-abilities.md`](./strikers-and-abilities.md) | The canonical home for "respect Striker identity." |
| [`in-match-hud.md`](./in-match-hud.md) | The HUD-discipline operationalization of "avoid visual pollution." |

## Engine bridge (none)

These are *design principles*, not engine facts. There is no
engine-side bridge. The principles are observable from playing
the game; they're not encoded anywhere in the runtime.

What *does* exist in the engine and is relevant to several
principles:

- **The visual layer** the principles operate against — Core
  rendering, HUD widgets, particle systems. Engine bridges live
  in `docs/engine/widgets.md` *(planned)* and per-system docs.
- **The match phase machinery** "Design around sets" depends on —
  documented at the Lua/BP boundary in `docs/architecture/state-contract.md`
  and at the engine level in [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md)
  → *Game Lifecycle & Phase Detection*.

## Open questions

(Intentionally none. These principles are deliberately stable; if
they change, that's a major architectural shift and warrants an
ADR rather than an open-question entry here.)

## Cross-references

- Compact restatement: [`overview.md` → "OSPlus design principles (compact)"](./overview.md#osplus-design-principles-compact)
- Per-principle in-doc operationalizations: see [How this doc relates to others](#how-this-doc-relates-to-others) table above.
- Sibling docs index: [`docs/game/README.md`](./README.md)
- Related decisions: [`docs/decisions/`](../decisions/) — when a feature genuinely needs to violate one of these principles, that's an ADR conversation, not a "the principle was wrong" conversation.
