# `docs/game/` — player-side reality of Omega Strikers

The canonical answer to *"what does Omega Strikers look like and feel
like to the player?"* — the layer every OSPlus feature design depends
on but that nothing else in the project has previously documented.

Currently the canonical source for everything in this subtree is
[`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) — a single ~1400-line
narrative covering the whole player experience, written by the
maintainer 2026-04-29. That monolith is being migrated topic-by-topic
into the per-topic files listed below; until each topic is migrated,
**`OMEGA_STRIKERS_GAME.md` remains the canonical source for that
topic**. See [migration sequence](#migration-sequence) below.

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

## What's in this folder (planned)

Per-topic files migrated out of
[`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md). Items marked
**migrated** are live; items marked **TBD** are planned slots that
still resolve to the source monolith until promoted.

| Doc | Status | Source section in `OMEGA_STRIKERS_GAME.md` |
|---|---|---|
| [`overview.md`](./overview.md) | **migrated** (batch 1, 2026-04-29) | Sec 1-2, 4-5, 29-30 (distilled identity + agent memory summary) |
| [`match-lifecycle.md`](./match-lifecycle.md) | **migrated** (batch 1, 2026-04-29) | Sec 3, 6 (session flow + state machine) |
| [`core-and-strike.md`](./core-and-strike.md) | **migrated** (batch 2, 2026-04-30) | Sec 4-5, 11 (Core mechanics + basic Strike) |
| [`goals-and-barriers.md`](./goals-and-barriers.md) | **migrated** (batch 2, 2026-04-30) | Sec 7 |
| [`roles.md`](./roles.md) | **migrated** (batch 3, 2026-04-30) | Sec 8 (goalie / forward / flexible) |
| `strikers-and-abilities.md` | **TBD** | Sec 9-10 |
| [`combat.md`](./combat.md) | **migrated** (batch 3, 2026-04-30) | Sec 12 (stagger / KO / damage) |
| [`energy-evade-burst.md`](./energy-evade-burst.md) | **migrated** (batch 3, 2026-04-30) | Sec 13 |
| [`power-orbs.md`](./power-orbs.md) | **migrated** (batch 3, 2026-04-30) | Sec 14 |
| [`awakenings.md`](./awakenings.md) | **migrated** (batch 2, 2026-04-30) | Sec 15 (gameplay system) + Sec 21-22 (draft UX) |
| `gear.md` | **TBD** | Sec 16 |
| `maps.md` | **TBD** | Sec 17 |
| [`lobby.md`](./lobby.md) | **migrated** (batch 1, 2026-04-29) | Sec 19 |
| `striker-select.md` | **TBD** | Sec 20 |
| [`in-match-hud.md`](./in-match-hud.md) | **migrated** (batch 1, 2026-04-29) | Sec 18, 23 (player attention + HUD UX) |
| `post-match.md` | **TBD** | Sec 24 |
| [`screens.md`](./screens.md) | **migrated** (batch 1, 2026-04-29) | Sec 25 (screen inventory + per-screen detail) |
| `design-principles.md` | **TBD** | Sec 27 |

Items marked **TBD** are slots reserved by intent, not yet drafted.
Don't add a feature that depends on a TBD doc without first promoting
that doc out of TBD via its own `docs/game-<topic>` branch (or by
migrating the relevant section as part of the feature work).

Sec 26 of the source monolith ("Reverse Engineering Search Targets")
is *not* migrated here — it's engine-side material destined for
[`docs/engine/`](../engine/) per-topic files. Sec 28 ("Good OSPlus
Feature Categories") similarly belongs in
[`docs/ROADMAP.md`](../ROADMAP.md), not here.

## Reading orders for common tasks

Most of these still bottom out at
[`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) until migration
completes; the file names below are the *destinations* — read the
linked source section in the monolith until each file lands.

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

## Migration sequence

Migration from
[`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) happens
topic-by-topic, one branch per batch of 3-5 related topics. Each
migration:

1. Lifts the relevant section into a new per-topic file under this folder.
2. Improves structure on the way (per-screen template for `screens.md`, per-mechanic template for `combat.md`, etc.).
3. Closes any open glossary cross-references that are unblocked by the migration.
4. Replaces the corresponding section in the source monolith with a short stub: *"Migrated to [`docs/game/<topic>.md`](./<topic>.md)"*.
5. Updates this README's status table from **TBD** to **migrated**.
6. Surfaces and resolves any contradictions or ambiguities found during the migration (per the OMEGA_STRIKERS_GAME.md review findings already on file).

Once every section has been migrated, the source monolith gets
archived (or deleted, with a learning entry) and this folder becomes
the canonical surface. Until then, **the monolith is canonical for
any topic still marked TBD here**.

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
