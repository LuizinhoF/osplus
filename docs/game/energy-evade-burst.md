# Energy, Evade, and Energy Burst

The single resource (Energy) that backs both the player's main
defensive escape (Evade) and their main offensive/clutch nuke
(Energy Burst). Sharing one meter between two opposing-purpose
abilities is the core tension of the system.

> **Status:** seeded 2026-04-30 from
> [`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 13.
>
> **Last validated against game patch:** 2026-04. Energy
> mechanics have been mechanically stable; specific gain rates,
> max-energy values, and Energy-related Awakening tuning are
> patch-volatile. Re-validate when patch notes mention Energy,
> Evade, Burst, or Energy-modifying Awakenings.

This doc is the player-side mechanic. Engine class names for the
Energy resource and the Evade / Burst UFunctions are not
catalogued in this docset and are surfaced as TBDs in
[Open questions](#open-questions).

## TL;DR

- **One resource, two opposite uses.** Energy fuels both Evade
  (defensive avoidance) and Energy Burst (high-impact Core
  control / emergency reversal). Spending it on one means not
  having it for the other.
- **It's the most decision-rich resource in the game moment-to-
  moment.** Every second of play, the player is implicitly
  asking "do I save this for survival or commit it for impact?"
- **Energy decisions affect both combat survivability AND Core
  control.** Don't change Energy lightly — a tuning change ripples
  into goalie clutch saves, forward stuffing, KO escape, and
  comeback potential simultaneously.
- **Both teams see each other's Energy state.** Like stagger,
  Energy is public information that shapes mind games.

## The Energy resource

Energy is a per-player meter. It fills passively during play (and
likely from certain triggers — see
[`power-orbs.md`](./power-orbs.md) and
[Open questions](#open-questions)). When the meter is full, the
player can spend it on either Evade or Energy Burst.

What the player observes:

- **There is one Energy meter, not two.** Spending fills the same
  bucket whether you Evaded or Bursted.
- **Energy state is visible** to the player and (likely) to enemies
  — its visibility is what makes it a strategic resource rather
  than a hidden cooldown.
- **Spending Energy is a discrete commit, not a meter drain.** When
  you Evade, the Energy is gone in one input; when you Burst, same
  thing. There is no "half an Evade" or "burst at 50%."

## Evade — defensive avoidance

Evade is the survival tool. Pressed under pressure, it lets the
player escape an incoming hit, an unfavorable position, or a
KO-pending stagger state.

### What Evade does (player perspective)

- **Brief invulnerability + repositioning.** The player covers some
  distance in a chosen direction with damage immunity for the
  duration. Exact frame data and distance are TBD on the engine
  side.
- **Cancels into other actions.** Evade enables follow-up Strikes /
  abilities once the immunity window ends.
- **Costs the full Energy meter.** Evade is not "cheaper" than
  Burst — the same resource expenditure.

### Why Evade is load-bearing

The Evade input is what separates "I'll definitely die at high
stagger near the edge" from "I survived that exchange". Without
Evade, the combat in [`combat.md`](./combat.md) becomes
deterministic — high stagger near the edge = guaranteed KO.

This is why an Evade decision is also a *meta-game* decision.
Evading **now** means not Bursting **next moment**, even though
that next moment might be the better Burst window.

## Energy Burst — high-impact Core control / emergency reversal

Burst is the offensive/clutch tool. Pressed at the right moment, it
massively redirects the Core, denies an enemy clear, secures a
clutch save, or breaks a chokepoint.

### What Burst does (player perspective)

- **A hard-hitting Core interaction.** Bursting near the Core
  produces an outsized Core-redirect (sends it harder, faster, in
  the player's chosen direction). The exact mechanic — pure
  knockback magnitude, special hit type, area-of-effect, timing
  window — is documented at the engine level via
  [glossary → "Core (a.k.a. Rock)"](../glossary.md#core-aka-rock)
  (`EnergyBurst` is referenced as a Core-interaction system in the
  KB).
- **A potential clutch save.** A goalie under heavy pressure can
  Burst the Core away from imminent goal danger.
- **A potential clutch score.** A forward facing a half-broken
  defense can Burst the Core through it.
- **Costs the full Energy meter.** Same resource as Evade.

### Why Burst is load-bearing

Without Burst, late-set comebacks are largely impossible — the
team that's snowballing has no countervailing tool. Burst is the
"reset the moment" lever that keeps OS matches from being
deterministic from the first goal onward.

## Why they share a meter

Sharing one meter between defense and offense is the design
choice that makes the system interesting. If Evade and Burst had
separate meters:

- Defense and offense would be balanced separately.
- Players would Evade *and* Burst in the same exchange whenever
  they could.
- The strategic question "spend on survival now or commit to
  impact later?" would not exist.

Because they share a meter, every Energy decision is **a tradeoff
between two desirable things**. The skill is not in mashing the
buttons — it's in knowing which one to mash.

### Strategic implications

| Situation | Default Energy framing |
|---|---|
| **Goalie under early pressure, score 0-0.** | Save for Burst clutch save; Evade is a fallback. |
| **Forward late-set, behind on score.** | Save for Burst comeback; Evade only if KO is imminent. |
| **High-stagger anyone near the edge.** | Spend on Evade; survival > all. |
| **Defending against a known Burst threat.** | Match expectations — if the enemy team Bursts, your team probably should too. |
| **Right after KO-respawn (no Energy yet).** | Play conservatively until the meter rebuilds. |

These are framings, not rules. The actual moment-to-moment Energy
decision is one of the most skill-expressive parts of OS.

## Why this matters for OSPlus

Energy is in the same category as the Core itself: any feature
touching it has cascading effects across both combat and Core play.

**Likely good feature shapes:**

- Energy-state HUD overlays (only if they communicate something
  not already conveyed by the native Energy meter — easy to
  duplicate; hard to genuinely add value).
- Energy-decision training tools (drills that surface the
  "Evade vs Burst" tension explicitly).
- Post-match Energy analysis (per-match Energy spent / Energy
  expired unspent / Burst impact ratings).
- Practice-mode Energy scenarios (e.g., "you have 1 Energy and a
  high-stagger forward is closing — what do you do?").

**Likely bad feature shapes:**

- Anything that automates Evade or Burst decisions for the player
  — these are the player's most expressive in-match decisions.
- Anything that visually obscures the native Energy meter.
- Energy-related telemetry shown mid-match in a way that distracts
  from the existing high-cognitive-load HUD (see
  [`in-match-hud.md` → "HUD discipline rules"](./in-match-hud.md#hud-discipline-rules)).

A general check: **does this feature change the player's Energy
decision, or does it inform it?** Inform = good. Change = usually
bad.

### Sec 13's checklist (preserved)

The source doc Sec 13 framed Energy-feature evaluation around five
direct checks. They're worth preserving verbatim because they're
the cleanest sanity-check for any Energy-touching mod feature:

- Does this make goalies too safe?
- Does this make forwards too oppressive?
- Does this remove clutch saves?
- Does this make KO pressure meaningless?
- Does this create too much Core priority?

If a feature design answers "yes" to any of these, reconsider.

## Engine bridge (one-link summary)

Energy-system engine names are NOT catalogued in this docset. What
is known indirectly:

- **Energy Burst is a Core-interaction system.**
  [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) lists `EnergyBurst`
  in the Core-related grep cluster (per Sec 26 of the legacy
  monolith — engine-side material destined for `docs/engine/`).
- **The Energy resource itself probably lives on PlayerState.**
  Per-match Energy stats (Burst count, Evade count, etc.) likely
  live on `PMPlayerMatchSummary` alongside the other per-player
  combat counters; field names not catalogued here. **TBD; surfaces
  during the engine doc migration.**

Per ADR 0003, the engine search-target list does not live in this
player-side doc.

## Open questions

- **Energy gain mechanics.** Does the meter fill at a flat rate
  per-second, on damage taken / dealt, on Power Orb pickup, or
  some combination? Player intuition: passive fill rate +
  acceleration from Power Orbs +/- some triggers, but
  unconfirmed. **TBD.**
- **Energy max value.** Is max-energy a fixed value (one Burst /
  Evade worth), or do some Strikers / Awakenings / modes scale it?
  Player observation: appears to be fixed, but TBD.
- **Energy-modifying Awakenings.** Confirmed conceptually (Sec 15
  lists "Energy behavior" as one Awakening modification dimension)
  but the per-Awakening matrix is not in this doc. **Patch-volatile;
  belongs in `awakenings.md` ad-hoc when relevant, not catalogued
  here.**
- **Burst's exact Core-interaction details.** Is it pure
  knockback-magnitude scaling, a special hit type, or an
  area-of-effect? Engine-level question. **TBD; route via
  `KNOWLEDGEBASE.md` → Core-related grep cluster.**
- **Whether Burst affects players (not just the Core) directly.**
  Player observation suggests Burst can also affect nearby enemies
  (knockback), but exact rules are TBD.
- **Visibility of enemy Energy.** Does the enemy see your full
  Energy meter, only "Energy ready / not ready", or nothing?
  Strategically important — affects the mind game. **TBD;
  observation suggests it's visible-as-state, but worth confirming.**

## Cross-references

- Combat / KO context that drives Energy decisions: [`combat.md`](./combat.md)
- The Core mechanics Burst routes through: [`core-and-strike.md`](./core-and-strike.md)
- Power Orbs that may accelerate Energy gain: [`power-orbs.md`](./power-orbs.md)
- Roles whose Energy management styles differ: [`roles.md`](./roles.md)
- Engine bridge for the Core-interaction `EnergyBurst` reference: [glossary → "Core (a.k.a. Rock)"](../glossary.md#core-aka-rock)
- HUD discipline (do not duplicate the native Energy meter): [`in-match-hud.md` → "HUD discipline rules"](./in-match-hud.md#hud-discipline-rules)
- Sibling docs index: [`docs/game/README.md`](./README.md)
