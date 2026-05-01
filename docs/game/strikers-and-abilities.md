# Strikers and abilities

The two layers that *define* how the player actually plays Omega
Strikers: the **Striker** (their character + kit identity) and the
**abilities** they cast during the match. Together these are the
"who am I and what do I do" of OS.

> **Status:** seeded 2026-05-01 from
> [`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 9 + 10.
>
> **Last validated against game patch:** 2026-04. **The Striker
> roster, per-Striker stats, and per-ability tuning are highly
> patch-volatile.** This doc deliberately stays *abstract* about
> specific Striker names, ability identities, and balance numbers,
> because those facts age out fast. The full per-Striker /
> per-ability matrix belongs in a season-specific catalog (not yet
> drafted), not in this player-side mechanic doc. Re-validate
> whenever a new Striker ships, balance patches drop, or kits get
> reworked.

This doc is the player-side conceptual layer: what a Striker *is*,
what abilities *can do*, and the design rules that bind kits
together. The bridge to engine reality (per-Striker actor classes,
ability data assets, hit-event hooks) lives in
[glossary → "Striker"](../glossary.md#striker) and from there into
[`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md).

## TL;DR

- **A Striker is a character with a unique kit.** Strikers are
  *not* skins — they meaningfully change how the player interacts
  with the match. Picking a Striker is the player's first identity
  commitment of the match.
- **Each Striker has a roughly four-action kit:** basic Strike +
  primary ability + secondary ability + special ability. Some
  Strikers also modify the basic Strike itself.
- **Abilities are dual-purpose.** Most abilities both interact with
  the Core *and* affect players (KO threat, stagger, displacement).
  Treating any ability as "only combat" or "only Core control" is
  usually a misframing.
- **Striker identity is sacred.** A core OSPlus design rule: a
  feature should *preserve* a Striker's recognizable rhythm, not
  flatten kits into sameness. (See
  [`design-principles.md`](./design-principles.md) → "Respect
  Striker identity".)

## What a Striker is

A Striker bundles together:

| Component | What it is |
|---|---|
| **Basic Strike** | The cooldown-gated input shared by all Strikers — but per-Striker modifications exist (e.g., projectile-style basic). See [`core-and-strike.md` → "The basic Strike"](./core-and-strike.md#the-basic-strike). |
| **Primary ability** | The most-used non-Strike action. Often the Striker's signature mechanic. |
| **Secondary ability** | A complementary tool (mobility, control, follow-up). |
| **Special ability** | The biggest-impact action; often longer cooldown, often what the Striker is "known for." |
| **Unique stats** | Movement speed, max stagger threshold, hitbox size, etc. Per-Striker variations. |
| **Role tendencies** | Bias toward goalie, forward, or flexible play (not enforced; see [`roles.md`](./roles.md)). |
| **Cosmetic identity** | Visual / audio / animation distinctiveness — *separate* from gameplay identity, but contributes to recognizability. |

A Striker is *not* a class in the MOBA sense (where role is
mechanically enforced). Players can flex any Striker into any
role; the kit just *biases* what plays well there. See
[`roles.md`](./roles.md).

## Striker identity patterns (broad clusters, not a roster)

Players intuitively cluster Strikers by playstyle. Names move with
patches; the *patterns* are stable:

- **Close-range brawler** — short-range Strikes / abilities, wins
  Core control through proximity pressure.
- **Projectile poke** — ranged ability output, plays at distance.
- **Defensive goalie-favored** — ability kit oriented toward
  blocks, clears, and area control near the goal line.
- **Area control** — places persistent zones / hazards that deny
  enemy positioning.
- **Summoner / deployable control** — spawns persistent objects
  (turrets, traps, totems) that change the field.
- **Mobility assassin** — short cooldowns + dashes; hits-and-runs.
- **Hook / displacement specialist** — pulls / pushes enemies into
  KO positions.
- **Support / buff / utility** — abilities that empower teammates
  or weaken enemies, less direct Core/KO output.

These clusters are not crisp categories — many Strikers occupy
multiple. They're useful as a *design vocabulary* when discussing
how a feature might affect "all the brawlers" vs "all the
deployable kits."

## Abilities — what they actually do

An ability is rarely a single-purpose effect. It typically does
*some combination* of:

| Effect cluster | Examples |
|---|---|
| **Core interaction** | Hit Core, redirect Core, accelerate Core, slow / stop Core. |
| **Player damage** | Stagger enemies, KO enemies, knock enemies away. |
| **Spatial control** | Create terrain / obstacles, deny an area, generate a deployable. |
| **Buff / debuff** | Empower allies, slow / blind / banish enemies. |
| **Self-mobility** | Move the player (dash, jump, blink). |
| **Resource pressure** | Force enemy cooldowns or Energy expenditure (see [`energy-evade-burst.md`](./energy-evade-burst.md)). |

The crucial player-side fact:

> **Most ability design exists in the overlap between fighting and
> Core control.** Neither pure-combat nor pure-Core framings will
> hold for most abilities.

A goalie clear ability also stuns enemies. A forward poke also
redirects the Core. A mobility dash also creates space for a
follow-up Strike. Treating these as single-purpose underestimates
how dense OS abilities are.

## Cooldowns and the timing layer

Every active ability has a cooldown. This is the *load-bearing
timing layer* that intersects with everything else in the game:

- **Strike timing** ([`core-and-strike.md` → "Why Strike timing is load-bearing"](./core-and-strike.md#why-strike-timing-is-load-bearing))
- **Energy timing** ([`energy-evade-burst.md`](./energy-evade-burst.md))
- **Ability timing** (this layer)

Players bait, force, and punish ability cooldowns the same way
they do Strike cooldowns. A goalie whose primary ability just went
on cooldown is briefly defenseless against the next forward
combo; a forward whose mobility just expired is a sitting duck.

The cooldown read is *the* mid-match skill on top of pure aim. See
[`design-principles.md`](./design-principles.md) → "Respect Cooldown
Mind Games".

## Striker identity as a design constraint

The most important *design rule* about Strikers (from Sec 9):

> A good feature preserves Striker identity. A bad feature makes
> every Striker feel the same or breaks the intended rhythm of a
> kit.

What "breaks Striker identity" looks like in practice:

- A universal mechanic that overrides per-Striker flavor (e.g., a
  global "extra Strike" buff turns every Striker into the same
  basic-Strike spammer).
- An Awakening that erases a Striker's intended weakness (e.g.,
  giving a melee brawler ranged poke; the brawler becomes
  universal).
- A balance change that removes a Striker's signature play pattern
  (e.g., making a hook character's hook unconditional removes the
  hook-prediction mind game).

For OSPlus features, this rule generalizes: any cross-cutting
mechanic (HUD overlay, damage modifier, ability augment) must
respect that *part of why each Striker is fun is that they play
differently from the others*. A feature that smooths out
differences is usually a worse feature.

The full list of design rules — including the Striker-identity
rule — lives in
[`design-principles.md` → "Respect Striker identity"](./design-principles.md#respect-striker-identity).

## Where OSPlus could attach

Strikers + abilities are a high-leverage feature surface, but
also high-risk because patch volatility makes any specific feature
likely to drift.

**Likely good feature shapes:**

- **Improved ability descriptions.** The native game's ability
  text is sometimes terse; in-mod expanded descriptions (with
  Awakening interactions, role context) are useful.
- **Striker matchup notes.** Cross-Striker matchup information
  surfaced in the lobby / [striker-select](./striker-select.md).
- **Per-Striker training drills.** Practice scenarios that
  specifically exercise a Striker's signature mechanics.
- **Per-Striker performance tracking.** Stats by Striker over a
  rolling window; "you play X better than Y; here's why."
- **Striker-roster onboarding.** "You haven't played this Striker
  before; here's the 30-second pitch."

**Likely bad feature shapes:**

- A "best Striker" recommendation engine that flattens player
  agency.
- Mod-side balance changes (not what OSPlus is for; would
  invalidate every conventional matchup read).
- A universal mechanic that affects all Strikers identically (the
  Striker-identity rule).
- Hard-coded per-Striker matrices in the OSPlus codebase that
  age out the moment a Striker gets reworked. **Patch-volatile
  data should live in JSON / config / a season-specific catalog,
  not in code.**

## Engine bridge (one-link summary)

[glossary → "Striker"](../glossary.md#striker) is the canonical
bridge:

- **In-match combat Pawn.** `C_<InternalName>_C`
  (e.g., `C_FlexibleBrawler_C` = Juliette,
  `C_NimbleBlaster_C` = Drek'ar). Confirmed.
- **Striker select / draft UI representation.** Likely uses
  preview / visualization actor classes; **TBD per-context**.
- **Identity key.** A backend ID is used across all engine contexts
  to identify the equipped Striker.
- **Ability data assets.** **TBD; not catalogued in this docset.**
  Search candidates from the legacy monolith Sec 9-10:
  `StrikerDefinition`, `CharacterDefinition`, `HeroDefinition`,
  `AbilityPrimary`, `AbilitySecondary`, `AbilitySpecial`,
  `AbilityCooldown`, `AbilityHitbox`, `AbilityProjectile`,
  `AbilityCastTime`, `AbilityRange`, `AbilityDamage`,
  `AbilityKnockback`, `CoreHitModifier`, `PlayerHitModifier`,
  `StatusEffect`, `Buff`, `Debuff`. These belong in
  `docs/engine/` per ADR 0003, not here.
- **Per-target ability handlers.** Ability logic likely branches
  on target type (`onCoreHit`, `onPlayerHit`, `onAllyHit`,
  `onEnemyHit`, `onBarrierHit`, `onTerrainHit`, `onProjectileExpire`,
  `onRecast`, `onChargeStart`, `onChargeRelease`,
  `onDeployableSpawn`, `onDeployableExpire`). Names are illustrative
  — confirmed names **TBD; route via engine doc when migrated.**

Per ADR 0003, the engine search-target list does not live in this
player-side doc.

## Open questions

- **Full Striker roster catalog.** Patch-volatile; belongs in a
  season-specific data file, not this doc. **TBD.**
- **Per-Striker basic-Strike modifications.** Some kits modify
  Strike behavior (e.g., projectile basic). Full matrix not
  catalogued. **TBD.**
- **Per-ability cooldown / hitbox / damage matrix.** Patch-volatile
  data. **TBD; should live in a separate data catalog if needed,
  not here.**
- **The full per-target ability hook cluster.** Engine-side names
  for `onXxxHit` family. **TBD; route via engine doc.**
- **Deployable / persistent-object lifecycle.** Some kits spawn
  persistent objects; how their state is replicated, cleaned up,
  and interacts with round/set boundaries — **TBD.**
- **Awakening × Striker interaction matrix.** Awakenings can modify
  per-Striker behavior asymmetrically (some Awakenings shine on
  some Strikers). Patch-volatile per-pair data. **TBD; out of
  scope for this doc.**

## Cross-references

- The Strike (basic input shared across kits): [`core-and-strike.md`](./core-and-strike.md)
- Combat / KO context the abilities feed into: [`combat.md`](./combat.md)
- Energy resources Strikers use to unlock potential: [`energy-evade-burst.md`](./energy-evade-burst.md)
- Roles that Striker kits bias toward: [`roles.md`](./roles.md)
- Awakenings that modify Striker behavior in-match: [`awakenings.md`](./awakenings.md)
- Pre-match passive role/style tuning: [`gear.md`](./gear.md)
- Map context that shapes Striker viability: [`maps.md`](./maps.md)
- The over-arching design rule: [`design-principles.md` → "Respect Striker identity"](./design-principles.md#respect-striker-identity)
- Engine bridge: [glossary → "Striker"](../glossary.md#striker)
- Sibling docs index: [`docs/game/README.md`](./README.md)
