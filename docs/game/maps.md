# Maps / arenas

The arenas where matches are played. Maps are *gameplay systems*,
not just backgrounds — wall geometry, goal placement, hazards, orb
spawn points, and visual readability all change how the same
Strikers and Awakenings perform.

> **Status:** seeded 2026-05-01 from
> [`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 17.
>
> **Last validated against game patch:** 2026-04. The *abstract*
> map model (what dimensions a map varies on) is mechanically
> stable. The *catalog* (which arenas exist, their per-arena
> details, per-mode availability) is patch-volatile and
> partially uncatalogued in this docset. Re-validate when patch
> notes mention new arenas, arena reworks, or per-arena hazard /
> orb tuning.

This doc is the player-side conceptual layer. The engine-side
catalog of confirmed map asset paths lives in
[glossary → "Map / Arena"](../glossary.md#map--arena) and from
there into [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) → *Maps*.

## TL;DR

- **A map is gameplay context, not just art.** Goal shape, wall
  geometry, hazards, and orb spawns all materially affect how
  Strikers, Awakenings, and roles play out.
- **Each map nudges Striker / Awakening / role viability.** A
  bouncy-walled arena rewards Strikers / Awakenings that exploit
  rebounds; an open arena rewards range and mobility; an
  hazard-heavy arena rewards CC / displacement.
- **Bad map design is recognizable.** The source doc Sec 17
  enumerated symptoms (Core hard to see, unpredictable bounces,
  hazards too dominant, etc.) — preserved below.
- **The full per-arena catalog is patch-volatile + partially
  uncatalogued.** This doc stays abstract; per-arena facts route
  through [glossary → "Map / Arena"](../glossary.md#map--arena)
  and [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md).

## What a map varies on

Per Sec 17, an arena may define any combination of:

| Dimension | What it varies |
|---|---|
| **Goal shape** | The geometry of each team's net. Affects scoring angles. |
| **Barrier layout** | How many barriers per goal, where they sit, what shape. See [`goals-and-barriers.md`](./goals-and-barriers.md). |
| **Wall geometry** | Where the walls are, their angles, their bounce behavior. Determines rebound play. |
| **Core bounce behavior** | Per-arena modifiers on Core rebound (e.g., dampened vs lively walls). **TBD whether this is per-arena or per-Striker / per-Awakening.** |
| **Hazards** | Persistent or periodic environmental damage / KO sources. |
| **Special objectives** | Per-arena unique mechanics (e.g., capturable points, periodic events). |
| **Orb spawn points** | Where Power Orbs appear. See [`power-orbs.md`](./power-orbs.md). |
| **Spawn locations** | Where players (re)spawn — including post-KO respawn locations. |
| **Camera framing** | Where the camera sits and how it pans. Affects player situational awareness. |
| **Visual readability** | Color palette, lighting, contrast — does the Core read well against the floor? |
| **Choke points** | Narrow passages that funnel Core / player movement. |
| **Safe zones / danger zones** | Areas where stagger / KO risk are higher / lower. |

Not every map varies all of these. The *recognizable identity* of
each arena comes from which dimensions it leans on — a
"hazard-heavy arena" pushes hazards; a "bouncy arena" pushes wall
geometry.

## How map shapes the rest of the game

A map's choices ripple into every other player-side system:

- **Which Strikers are strong** — projectile-poke kits prefer open
  maps; close-range brawlers prefer cramped maps; deployable
  control kits prefer maps with chokepoints. (See
  [`strikers-and-abilities.md`](./strikers-and-abilities.md).)
- **Which Awakenings are valuable** — ability-size Awakenings shine
  in cramped maps; range Awakenings shine in open maps. (See
  [`awakenings.md`](./awakenings.md).)
- **How goalies defend** — barrier layout + wall geometry change
  the defensive read. (See [`roles.md`](./roles.md).)
- **How forwards pressure** — open lanes vs. constricted approaches.
- **Where KOs happen** — edge proximity is map-dependent. (See
  [`combat.md`](./combat.md).)
- **Where Orbs are contested** — per-arena spawn points define the
  micro-objectives. (See [`power-orbs.md`](./power-orbs.md).)
- **How Core rebounds behave** — wall geometry + bounce behavior
  shape ricochet plays.

A common error: assuming a Striker / Awakening / strategy that
worked on Map A will work the same on Map B. Map context is one of
the load-bearing reads of the [Awakening draft moment](./awakenings.md#what-drafting-well-looks-like).

## Bad map design symptoms (preserved from source)

Sec 17 enumerated symptoms of bad map design. Preserved as a
diagnostic checklist for any custom-map experiments:

- Core becomes hard to see (visual readability failure)
- Wall bounces feel unpredictable (player can't model rebounds)
- Hazards dominate too much (combat / Core become irrelevant)
- Goalie has no reasonable defense (forwards score uncontested)
- Forwards cannot reasonably break barriers (defense is too
  strong)
- Orb spawns create runaway advantage (snowballing without
  comeback chances)
- Visual clutter hides important state

If a feature changes a map (or proposes a custom map), it should
be checked against each of these.

## Where OSPlus could attach

Maps are a moderate-leverage feature surface. Most useful map
features are *informational* (surfacing arena context for
decisions) rather than *modificational* (changing the arena
itself).

**Likely good feature shapes:**

- **Map-specific tips.** "On this arena, X Striker is unusually
  strong; Y Awakening is unusually valuable." Surfaced at
  [striker-select](./striker-select.md) or in-match.
- **Per-arena Orb spawn timing / locations.** Once known, the
  spawn-point map is a useful overlay (small, peripheral,
  respecting [`in-match-hud.md` → "HUD discipline rules"](./in-match-hud.md#hud-discipline-rules)).
- **Per-arena performance retrospectives.** "You play X arena
  better than Y arena; here's why." Lives in
  [`post-match.md`](./post-match.md) territory.
- **Custom-arena experiments.** OS supports custom lobbies; an
  OSPlus custom-map editor / loader is a plausible long-tail
  feature.

**Likely bad feature shapes:**

- Live arena modification mid-match (would break the public-state
  contract every other player relies on).
- Arena-readability "fixes" that override player-vs-player parity
  (one player seeing a different arena than another).
- Hard-coded per-arena matrices in code. **Patch-volatile arena
  data should live in JSON / config, not in code.**
- A "pick-this-arena" recommendation engine when the player has no
  agency over arena choice in matchmaking.

## Engine bridge (one-link summary)

[glossary → "Map / Arena"](../glossary.md#map--arena) is the
canonical bridge. What's known:

| Map | Asset path | Status |
|---|---|---|
| Lobby (Main Menu) | `/Game/Prometheus/Maps/MainMenuMap/MainMenuMap` | confirmed |
| Practice arena | `/Game/Prometheus/Maps/GameMap/GameMapPractice` | confirmed |
| Ahten City (an online arena) | `/Game/Prometheus/Maps/GameMap/GameMapAhtenCity` | confirmed |
| Other arenas | Folder `/Game/Prometheus/Maps/GameMap/` | exist but **not catalogued in this docset** |

Mode-locking (which arenas are available in which modes) is
**TBD**. Practice has its own dedicated map; Ranked / Brawl /
Custom arena availability is not catalogued.

Per ADR 0003, the engine search-target list does not live in this
player-side doc. Full map table will land in
`docs/engine/setup.md` *(planned)*.

## Open questions

- **Complete map list.** Folder `/Game/Prometheus/Maps/GameMap/`
  contains the right places to look, but the full inventory is
  **not catalogued in this docset.** Quick `ls` of cooked content
  in a probe would close this.
- **Per-mode map availability matrix.** Which arenas are in
  Ranked? Brawl? Custom? Per-mode rotations? **TBD.**
- **Per-arena Orb spawn locations.** Player observation: spawn
  points are arena-specific. The map of all spawn points per
  arena is **TBD; would close one of the open questions in
  [`power-orbs.md`](./power-orbs.md#open-questions).**
- **Per-arena hazard catalogs.** Which arenas have hazards, of
  what type, with what timing. **TBD; patch-volatile.**
- **Per-arena bounce / wall behavior.** Whether some arenas
  modify Core rebound behavior (e.g., "lively" vs "dampened"
  walls). **TBD.**
- **Custom map authoring.** Whether the engine supports custom
  arena content (likely yes, given the cooked content pipeline
  used by `OSPlus.pak`). Specifics for an OSPlus custom-arena
  feature would route through `docs/engine/` and Stage-3 RE.
  **TBD.**

## Cross-references

- Goal-area mechanics that vary per arena: [`goals-and-barriers.md`](./goals-and-barriers.md)
- Striker / Awakening / role viability map-dependence: [`strikers-and-abilities.md`](./strikers-and-abilities.md), [`awakenings.md`](./awakenings.md), [`roles.md`](./roles.md)
- Combat / KO context shaped by arena edges: [`combat.md`](./combat.md)
- Power Orb spawn points (arena-specific): [`power-orbs.md`](./power-orbs.md)
- HUD discipline (any per-arena overlay must respect this bar): [`in-match-hud.md` → "HUD discipline rules"](./in-match-hud.md#hud-discipline-rules)
- Engine bridge: [glossary → "Map / Arena"](../glossary.md#map--arena)
- Sibling docs index: [`docs/game/README.md`](./README.md)
