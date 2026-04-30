# Omega Strikers — overview

Player-side narrative entry point. The "what is this game and what
should an agent know on first encounter" doc. Distilled from the
fuller [`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md);
per-topic depth lives in the sibling docs listed below.

> **Status:** seeded 2026-04-29 from
> [`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 1-2, 4-5,
> 29-30.
>
> **Last validated against game patch:** 2026-04 (no specific patch
> identifier captured at authoring time). Re-validate this doc when
> Awakening lists, mode availability, or core mechanics change in a
> seasonal patch. Bump this line when you do.

## One-sentence identity

Omega Strikers is a fast, top-down, **3v3 competitive sports-brawler**
where two teams fight over a puck-like object called the **Core**
(engine name "Rock" — see [glossary](../glossary.md#core-aka-rock)),
using character abilities to score goals, defend, control space,
collect resources, draft in-match upgrades, and knock opponents out
of the arena.

A useful analogy bundle:

```text
air hockey + MOBA abilities + arena fighter ring-outs + sports positioning
```

It is **not** normal soccer. It is **not** only a fighting game. It
is **not** only a MOBA. It is a hybrid where the Core is the central
objective.

## Current-version baseline (REQUIRED reading)

Always use the **current official Omega Strikers format** as the
baseline. The single most important correction:

> **Do not assume players create a full pre-match build before
> entering a game.** That was more relevant to earlier/beta versions.
> In the current official version, build-making happens primarily
> *inside* the match through Awakening selection.

**Pre-match choices** are limited to:
- Mode (Ranked, Brawl, Practice, Custom — see [screens.md → Modes](./screens.md#modes))
- Striker (the playable character — see [glossary → Striker](../glossary.md#striker))
- Gear (passive role/style tuning)
- Cosmetics (Logo / Nameplate / Emoticon / Title — see [glossary → Cosmetic loadout](../glossary.md#cosmetic-loadout))
- Party state (solo / duo / trio)

**In-match build evolution** happens through:
- Starting Awakening selection (at match start)
- Between-set Awakening drafts (after each set)
- Adaptation to map, team comp, enemy comp, match state

For OSPlus features: **do not design as if the player has a
traditional pre-match item/build editor** unless the mod is
intentionally adding that as a new system. See
[`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 15 (until
migrated to `awakenings.md`).

## The Core is the main gameplay object

Every system in the game ultimately routes through Core control. The
Core is the puck/ball-like object both teams fight over. Players use
basic Strikes and abilities to:

- Redirect the Core
- Clear the Core from danger
- Pass the Core to teammates
- "Stuff" the Core through a goalie (point-blank score past defense)
- Break goal barriers
- Score goals
- Deny enemy clears
- Create rebounds
- Force bad enemy strikes

**Design rule:** *if a feature makes the Core harder to read, harder
to track, or less predictable, it is probably bad for gameplay.*

The Core is internally called "Rock" in the engine
(`PMRockCharacter`); all engine grep work uses `Rock`. See
[glossary → Core (a.k.a. Rock)](../glossary.md#core-aka-rock) for
the engine-side bridge.

## Main gameplay objective

Score by sending the Core into the enemy goal while preventing the
enemy team from scoring on yours.

Every system should be interpreted through how it affects:

- Core control
- Goal pressure
- Defense
- Positioning
- Cooldown timing
- Stagger / KO pressure
- Awakening scaling
- Map control
- Team coordination

## Match shape (one paragraph)

A match is **not** a single continuous soccer-like game. It has nested
units: a *match* contains multiple *sets*; a set contains multiple
*rounds*; each round ends with a goal scored. **Awakening drafts
happen between sets, not between rounds.** Numeric thresholds (goals
per set, sets per match, time limits) are mode-dependent and currently
TBD in this docset. Full state machine + open questions in
[`match-lifecycle.md`](./match-lifecycle.md).

## What the player tracks while playing

The in-match player constantly tracks: Core position + velocity, own
position, own cooldowns, own stagger, own Energy, role responsibility,
teammate positions, enemy positions, enemy cooldown threats, goal
barrier state, open-goal state, Power Orb spawns, KO threats, map
hazards, set/match score, timer/pacing.

Player attention is finite. Any UI / VFX change should reduce
cognitive load, not increase it. See [in-match-hud.md](./in-match-hud.md)
for the full perception-load breakdown and HUD discipline rules.

## Reading order from here

| Goal | Read |
|---|---|
| Understand the session-level flow | [`match-lifecycle.md`](./match-lifecycle.md) |
| Catalogue the screens | [`screens.md`](./screens.md) |
| Design a feature in the lobby | [`lobby.md`](./lobby.md) |
| Design something in-match | [`in-match-hud.md`](./in-match-hud.md) → [`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 7-17 (gameplay mechanics depth, until migrated) |
| Bridge a player concept to engine | [`docs/glossary.md`](../glossary.md) |
| Find the engine class behind a player concept | [`docs/glossary.md`](../glossary.md) → [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) (until migrated to `docs/engine/`) |

For the gameplay mechanics not yet migrated to per-topic files
(goals & barriers, roles, strikers, abilities, combat, energy,
power orbs, awakenings, gear, maps, design principles), the
canonical source remains [`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md)
sections 7-17 + 27 — see [`docs/game/README.md`](./README.md) for
the full migration status table.

## OSPlus design principles (compact)

When working on OSPlus, always ask:

- Which part of the player experience does this code affect? (Lobby /
  queue / Striker select / starting Awakening / core gameplay /
  goal-barrier state / energy-evade-burst / stagger-KO / map hazards /
  between-set Awakening / post-match / progression / cosmetics /
  custom lobby / networking)
- Does this preserve Core readability?
- Does this preserve fair goalie/forward interaction?
- Does this respect the Awakening-based in-match build system?
- Does this help the player make better decisions?
- Does this add unnecessary visual or cognitive load?
- Does this preserve Striker identity (each Striker keeps a recognizable rhythm)?
- Does this behave correctly across sets, not just one goal?

If the answer is unclear, prefer a smaller, more readable, less
invasive feature. Full design rules in
[`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 27 (until
migrated to `design-principles.md`).

## Cross-references

- Glossary: [`docs/glossary.md`](../glossary.md) — canonical concept
  catalog (player ↔ engine).
- Sibling docs in this folder: full list in
  [`docs/game/README.md`](./README.md).
- Engine reality: [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) →
  planned [`docs/engine/`](../engine/).
- Product: [`docs/product.md`](../product.md) — what OSPlus *is* and
  who it's for. Read first if you haven't.
- Roadmap: [`docs/ROADMAP.md`](../ROADMAP.md) — Now / Next / Later /
  Won't-do.
