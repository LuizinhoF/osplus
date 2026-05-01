# `docs/game/` — player-side reality of Omega Strikers

The canonical answer to *"what does Omega Strikers look like and feel
like to the player?"* — the layer every OSPlus feature design depends
on but that nothing else in the project has previously documented.

**Migration complete (2026-05-01).** The original monolith
[`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) — a single
~1400-line narrative written by the maintainer 2026-04-29 — has
been fully decomposed into the per-topic files listed below across
four batches. The monolith remains in this folder as a redirect
index; every section is now a short stub pointing to its canonical
per-topic home.

The two sections deliberately retained in the monolith (and not
in this folder) are: Sec 26 (engine-side RE search targets, will
move with the `docs/engine/` migration) and Sec 28 (good OSPlus
feature categories, belongs in [`docs/ROADMAP.md`](../ROADMAP.md)).

This subtree exists because OSPlus is a mod **layered onto a game**,
and features that don't understand the player-facing reality of that
game ship in the wrong place, at the wrong moment, or with the wrong
shape. The other knowledge substrates cover everything *but* the
player's seat:

| Substrate | Covers | Doesn't cover |
|---|---|---|
| [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) → migrating to [`docs/engine/`](../engine/) | Engine internals: UClasses, UFunctions, hook patterns, runtime data shapes | What any of it *renders* for the player |
| [`docs/glossary.md`](../glossary.md) | Bidirectional concept catalog: player concept ↔ engine representation(s) | Detailed player perception (catalog, not narrative) |
| [`docs/architecture/`](../architecture/) | OSPlus-internal architecture: Lua/BP boundary, script ownership, per-tick discipline | The native game OSPlus is a layer on top of |
| [`docs/product.md`](../product.md) | Audience, wedge, anti-goals, success criteria | Player-facing reality of OS itself |
| **`docs/game/` (this subtree)** | **Screens, navigation, match lifecycle, in-match UX, player systems, design principles** | **Engine internals (above), OSPlus internals (above), product strategy (above)** |

## What's in this folder

Per-topic files migrated out of
[`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md). All entries
are now live.

| Doc | Migrated in | Source section in `OMEGA_STRIKERS_GAME.md` |
|---|---|---|
| [`overview.md`](./overview.md) | batch 1, 2026-04-29 | Sec 1-2, 4-5, 29-30 (distilled identity + agent memory summary) |
| [`match-lifecycle.md`](./match-lifecycle.md) | batch 1, 2026-04-29 | Sec 3, 6 (session flow + state machine) |
| [`core-and-strike.md`](./core-and-strike.md) | batch 2, 2026-04-30 | Sec 4-5, 11 (Core mechanics + basic Strike) |
| [`goals-and-barriers.md`](./goals-and-barriers.md) | batch 2, 2026-04-30 | Sec 7 |
| [`roles.md`](./roles.md) | batch 3, 2026-04-30 | Sec 8 (goalie / forward / flexible) |
| [`strikers-and-abilities.md`](./strikers-and-abilities.md) | batch 4, 2026-05-01 | Sec 9-10 |
| [`combat.md`](./combat.md) | batch 3, 2026-04-30 | Sec 12 (stagger / KO / damage) |
| [`energy-evade-burst.md`](./energy-evade-burst.md) | batch 3, 2026-04-30 | Sec 13 |
| [`power-orbs.md`](./power-orbs.md) | batch 3, 2026-04-30 | Sec 14 |
| [`awakenings.md`](./awakenings.md) | batch 2, 2026-04-30 | Sec 15 (gameplay system) + Sec 21-22 (draft UX) |
| [`gear.md`](./gear.md) | batch 4, 2026-05-01 | Sec 16 |
| [`maps.md`](./maps.md) | batch 4, 2026-05-01 | Sec 17 |
| [`lobby.md`](./lobby.md) | batch 1, 2026-04-29 | Sec 19 |
| [`striker-select.md`](./striker-select.md) | batch 4, 2026-05-01 | Sec 20 |
| [`in-match-hud.md`](./in-match-hud.md) | batch 1, 2026-04-29 | Sec 18, 23 (player attention + HUD UX) |
| [`post-match.md`](./post-match.md) | batch 4, 2026-05-01 | Sec 24 |
| [`screens.md`](./screens.md) | batch 1, 2026-04-29 | Sec 25 (screen inventory + per-screen detail) |
| [`design-principles.md`](./design-principles.md) | batch 4, 2026-05-01 | Sec 27 (incl. 27.1-27.7) |

Sec 26 of the source monolith ("Reverse Engineering Search Targets")
is *not* migrated here — it's engine-side material destined for
[`docs/engine/`](../engine/) per-topic files. Sec 28 ("Good OSPlus
Feature Categories") similarly belongs in
[`docs/ROADMAP.md`](../ROADMAP.md), not here.

## Reading orders for common tasks

| Task | Suggested reads |
|---|---|
| New-to-OS onboarding | `overview.md` → `match-lifecycle.md` → `screens.md` |
| Designing an in-match UI feature | `in-match-hud.md` → `design-principles.md` → `core-and-strike.md` |
| Designing a lobby / pre-match feature | `lobby.md` → `striker-select.md` → `screens.md` |
| Designing an awakening-related feature | `awakenings.md` → `match-lifecycle.md` |
| Working on the cosmetic loadout / emote feature | `lobby.md` → `in-match-hud.md` → [glossary entry on Emote / Emoticon](../glossary.md#emote--emoticon) |
| Cross-referencing engine names | [`docs/glossary.md`](../glossary.md) → relevant `docs/engine/<topic>.md` (or `KNOWLEDGEBASE.md`) |

## Conventions across this subtree

- **Player vocabulary, not engine vocabulary.** *"The Core sails into
  the goal"* is a player observation. *"`PMRockCharacter` enters
  `GoalArea`"* is an engine observation. The first goes here; the
  second goes in `docs/engine/` (or `KNOWLEDGEBASE.md`); the bridge
  between them is a one-line cross-reference, not a re-derivation.
- **Cross-reference engine names** when they're known via the
  glossary. *"The chat box (see [glossary](../glossary.md) → ChatBox
  *(planned)* for engine class)"* is one click of value; *"the chat
  box"* is half of one.
- **Don't duplicate engine-internal facts** that already live in
  [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) or
  [`docs/engine/`](../engine/). Link to them. This subtree describes
  the player's perception; the engine subtree describes engine
  reality. They cross-reference; they don't restate each other.
- **Don't duplicate product-level claims** from
  [`docs/product.md`](../product.md). If a doc here finds itself
  making a claim about *who* OSPlus is for or *why* a feature would
  matter, that belongs in product, not here.
- **Patch volatility is first-class.** When a fact here is
  patch-sensitive (Awakening list changes between seasons; Striker
  balance is a moving target; cosmetic loadout slots may grow), say
  so explicitly. The reader needs to know which facts are stable
  bedrock vs. which need re-validation each season.

## Migration history

Migration from
[`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) ran
topic-by-topic across four batches between 2026-04-29 and
2026-05-01:

- **Batch 1 (2026-04-29)** — `overview.md`, `match-lifecycle.md`,
  `screens.md`, `in-match-hud.md`, `lobby.md`
- **Batch 2 (2026-04-30)** — `core-and-strike.md`,
  `goals-and-barriers.md`, `awakenings.md`
- **Batch 3 (2026-04-30)** — `roles.md`, `combat.md`,
  `energy-evade-burst.md`, `power-orbs.md`
- **Batch 4 (2026-05-01)** — `striker-select.md`, `post-match.md`,
  `strikers-and-abilities.md`, `gear.md`, `maps.md`,
  `design-principles.md`

Each migration: lifted the relevant section into a per-topic file;
improved structure (per-screen / per-mechanic templates); closed
glossary cross-references; replaced the source section with a
short redirect stub; surfaced and resolved any contradictions
found during the pass.

The source monolith is retained as a redirect index (every
section is now a stub pointing to its canonical home). It can be
archived once enough time has passed without anyone deep-linking
into a specific section number — but no rush. The Sec 26 + Sec 28
content stays canonical there until they too move (engine subtree
and ROADMAP respectively).

## When this subtree lies

These docs are only as accurate as the most recent migration pass /
play-through. If you find something here that contradicts what the
game actually does:

1. The game is the truth. Open the doc, fix the inaccuracy in the same branch as the work that exposed it.
2. If a TBD doc is blocking your feature work, promote it: cut a `docs/game-<topic>` branch, do an interview / migration pass with the maintainer, ship.
3. Update [`docs/glossary.md`](../glossary.md) in the same branch if your change invalidates a glossary entry's claim.

This subtree is referenced from [`AGENTS.md`](../../AGENTS.md)
pre-work reading, slotted between *how we work*
([`docs/dev-cycle.md`](../dev-cycle.md)) and *engine reality*
([`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) / planned
[`docs/engine/`](../engine/)) — because every feature design depends
on it.
