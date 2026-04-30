# Awakenings

The current-version main in-match build system. Players draft
Awakenings during the match — once at start, then again between
sets — and these drafted picks define how the player's Striker
behaves for the rest of the match.

> **Status:** seeded 2026-04-30 from
> [`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 15 +
> Sec 21-22.
>
> **Last validated against game patch:** 2026-04. **Awakening lists
> are highly patch-volatile** — Omega Strikers regularly adds,
> removes, retunes, and rebalances Awakenings between seasons. This
> doc deliberately stays *abstract* about specific Awakening names,
> stat values, and synergies, because those facts age out fast. Re-
> validate whenever a new season ships.

This doc is the player-side mechanic + UX. The bridge to engine
reality (Awakening data class, draft UI widget, per-player drafted
list location) lives in
[glossary → "Awakening"](../glossary.md#awakening) — and most of it
is currently TBD; any feature touching Awakenings will force a
Stage-3 RE probe per [`docs/dev-cycle.md`](../dev-cycle.md).

## TL;DR

- **The build is built *during* the match, not before it.** This is
  the single most important fact about Omega Strikers' build
  system.
- **Two draft moments:** one starting Awakening pick at match start,
  then a between-set draft after each completed set.
- **Awakenings are not just stat passives.** They are draft choices
  with strategic context — what your kit needs, what the map
  rewards, what the enemy team is building, what the score is.
- **OSPlus features in this area should help the *draft decision*,
  not replace it with a "build editor".** Beta-era OS had a more
  traditional pre-match build system; that no longer exists in the
  current official game and OSPlus should not accidentally re-create
  it (see [OSPlus framing rules](#osplus-framing-rules) below).

## What an Awakening *is*

An **Awakening** is a draftable upgrade that modifies how the
player's Striker behaves for the rest of the match.

A single Awakening can affect dimensions like (illustrative — the
exact catalog moves between seasons):

- Ability size (e.g., bigger AoE / projectile)
- Cooldown rate
- Movement speed
- Damage / knockback / power
- Range
- Creation/deployable size
- Energy behavior (gain rate, max, refresh-on-event)
- Power Orb effects
- Special-ability availability changes
- Survivability (stagger reduction, max stagger threshold, etc.)
- Scaling-over-the-match effects (gets stronger as the match
  progresses)

An Awakening is **a draft choice**, not a passive stat. The
question for the player is never "is +10% bigger AoE good?" — it's
*"is +10% bigger AoE good for this Striker, on this map, with this
team comp, against this enemy comp, at this score?"* That framing
is the whole skill of drafting.

## When the draft happens

There are **two distinct draft moments**:

### 1. Starting Awakening (match start)

After the arena loads but before active play begins, each player
picks one **starting Awakening** from a small offered slate. This
is the player's first build commitment of the match.

What the player wants to know at this moment:

- What options am I being offered?
- What does each one do?
- Which one fits my Striker?
- Which one fits my role (goalie / forward)?
- Which one suits this map?
- Which one counters or complements the team compositions I can
  see?
- How much time do I have to choose?

For OSPlus context: this is where the player's actual *build path*
begins. There is no pre-match equivalent — no full loadout editor,
no item shop, no rune page. The starting Awakening selection is the
build's first node.

### 2. Between-set Awakening drafts

After a set ends (and before the next set begins), each player
drafts one or more additional Awakening(s) onto their build. The
draft is *strategic adaptation* — the player has now seen a full
set of their own kit, their teammates' kits, the enemy kits, and
the map dynamics, and is responding to that.

What the player wants to know at this moment:

- Who won the previous set, and why?
- What worked / what didn't for me last set?
- What Awakenings are available now? (Note: the offered slate may
  differ from previous drafts — TBD whether this is curated or
  random.)
- What has my team already drafted? (Coordination matters — three
  forwards who all draft "more poke" is rarely as good as a poke +
  utility + survivability split.)
- What have the enemies drafted? (Counter-builds matter — if the
  enemy goalie just drafted +cooldown, the response on the
  attacking side is different than if they drafted +knockback.)
- What does my Striker *need* next? (A kit that scales hard wants
  one thing; a kit that's already strong early wants something
  else.)
- Should I draft for offense, defense, cooldowns, size, speed,
  survival, or utility? (One major axis at a time.)
- How much time do I have to choose?

This is the strategic adaptation moment of the match — the moment
where a losing team can pivot and where a winning team can
consolidate. It is also the most information-rich UI moment in a
match (lots of small text, lots of icons, time pressure, full team
context). Any OSPlus feature that operates here has to respect that
density.

## What "drafting well" looks like

Drafting decisions are multi-dimensional. A player roughly weighs:

| Dimension | Question |
|---|---|
| **Striker fit** | Does this Awakening reinforce what my kit already does, or compensate for what it lacks? |
| **Role fit** | Goalies often draft different priorities than forwards. |
| **Map fit** | A wall-bouncy arena rewards different Awakenings than an open arena. |
| **Team comp synergy** | Do my team's drafts combine well? Are we covering different needs or stacking the same one? |
| **Enemy comp counter** | What is the enemy team's most-pressing threat, and which Awakening would blunt it? |
| **Match state** | Comeback Awakenings ("scaling over the match") are differently valuable when behind vs ahead, near match point vs early. |

A good drafter cycles through several of these dimensions per
choice; a beginner draws "the most flashy effect." OSPlus feature
ideas that help drafters surface these dimensions (rather than
prescribe a single answer) are likely to age well across seasons.

## A note on the source contradiction (KB vs player-doc)

[`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) describes an "Awakening
Select" phase as occurring *between rounds* (where rounds are
goal-to-goal). Player-side reality
([`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 15) says
between *sets* (where sets contain multiple rounds).

**The player-side reading is canonical.** Awakening drafts happen at
match start and between sets. They do *not* happen between every
goal/round reset.

This is a known stale claim in `KNOWLEDGEBASE.md`; flagged in the
[glossary entry](../glossary.md#awakening) as the open
reconciliation. When the engine doc gets migrated out of `KNOWLEDGEBASE.md`,
the "between rounds" wording must be corrected to "between sets" in
the same change. See also
[`match-lifecycle.md` → "Match structure"](./match-lifecycle.md#match-structure-sets-rounds-goals)
for the sets-vs-rounds distinction.

## OSPlus framing rules

When designing an OSPlus feature in the Awakening area, **frame it as
draft assistance**, not as build authoring. Concretely:

**Likely good feature shapes:**

- Awakening draft helper — surfaces what the player's Striker /
  role / map context calls for, without picking for them.
- Post-match Awakening analysis — "here's how your drafts
  performed; here's what you might've drafted differently."
- Practice-mode Awakening simulation — let the player feel a
  specific draft in a controlled setting.
- Awakening UI improvements — better information density at the
  draft moment, not a different draft moment.
- Awakening-related telemetry — capture per-match draft patterns
  for later analysis (player-controlled, of course).

**Likely bad feature shapes:**

- A traditional pre-match item/build editor (this is the beta-era
  failure mode that the current official game deliberately moved
  away from).
- A full pre-match loadout planner that feeds into the live match.
- Static build selection before queue.
- "Auto-draft" features that pick Awakenings without player input.

The rule is: **the player still drafts, OSPlus helps them draft
better**. Anything that takes the draft decision *away from* the
player drifts toward the beta-era model the game deliberately left
behind.

(Exception: if OSPlus is intentionally adding a new
*non-mainline-game* mode where pre-match build editing is part of
the design — e.g., a sandbox/practice tool — that's a different
conversation. The rule above applies to features that touch live
matchmade play.)

## Engine bridge (one-link summary)

[glossary → "Awakening"](../glossary.md#awakening) is the canonical
bridge — and it is mostly TBD on the engine side. What's known:

- **Phase exists in the lifecycle.** Detection: `PlayerState_Game_C`
  + valid Pawn — see
  [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) → *Awakening Select*.
  (The KB labels this "between rounds" — see
  [contradiction note](#a-note-on-the-source-contradiction-kb-vs-player-doc)
  above.)
- **Awakening data class — TBD.** Not yet identified. Search
  candidate: `/Script/Prometheus.*` with `Awakening` in the name.
- **Draft UI widget — TBD.** Probably under the `WBP_*Awakening*`
  family.
- **Per-player drafted-Awakening list runtime location — TBD.**
  Likely on `PMPlayerState` or a sibling structure.

Per ADR 0003, the engine search-target list does not live here.
Start from the glossary entry and follow into the engine docs (or
into a Stage-3 RE probe).

## Open questions

- **Does the starting Awakening pick happen at *each* set start, or
  only at the very first set of a match?** Source doc says "at the
  start of the match" + "between sets" — the cleanest reading is
  *one* starting pick (match start) + *one or more* between-set
  drafts thereafter. Confirm with a test match.
- **Is the offered Awakening slate curated or random?** The player
  experiences a small offered slate per draft moment. Whether the
  options are randomized, weighted by Striker, weighted by recent
  picks, or chosen by some other logic — TBD.
- **How many Awakenings can be drafted per between-set moment?**
  Source doc is vague ("draft additional Awakenings between sets").
  Probably one per moment, possibly more in some modes. TBD.
- **Cap on total Awakenings per match.** Implied by "drafted" but
  not stated. TBD.
- **Replacement vs accumulation.** Are between-set drafts purely
  additive, or do some replace earlier picks? TBD.
- **Per-mode availability.** Whether Brawl / Ranked / Custom all use
  the same Awakening pool and draft schedule. TBD.
- **The full engine cluster from
  [glossary entry](../glossary.md#awakening)** — Awakening data
  class, draft widget, per-player runtime list location. **Any
  Awakening feature will force this probe.** Plan a Stage-3 RE pass
  per [`docs/dev-cycle.md`](../dev-cycle.md).

## Cross-references

- High-level "the build is built in-match": [`overview.md` → "Current-version baseline"](./overview.md#current-version-baseline-required-reading)
- Match flow / where draft moments slot into the lifecycle: [`match-lifecycle.md` → "State machine"](./match-lifecycle.md#state-machine)
- Sets vs rounds distinction: [`match-lifecycle.md` → "Match structure"](./match-lifecycle.md#match-structure-sets-rounds-goals)
- Engine bridge: [glossary → "Awakening"](../glossary.md#awakening)
- Striker / role context that informs drafts: [`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 8-10 (until migrated to `roles.md` / `strikers-and-abilities.md`)
- Sibling docs index: [`docs/game/README.md`](./README.md)
