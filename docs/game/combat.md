# Combat — stagger, KO, and damage

How the player-vs-player layer of Omega Strikers actually works,
and why "damage" doesn't mean what it usually means in other games.

> **Status:** seeded 2026-04-30 from
> [`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 12.
>
> **Last validated against game patch:** 2026-04. The stagger / KO
> model has been mechanically stable across recent seasons; specific
> stagger thresholds and per-Striker survivability tuning move with
> patches. Re-validate when patch notes mention stagger, knockback,
> respawn timers, or KO-related Awakenings.

This doc is the player-side mechanic. The engine-side bridge for
knockback (which is the projection vector that determines whether a
hit puts you over the edge) lives in
[glossary → "Core (a.k.a. Rock)"](../glossary.md#core-aka-rock) —
the `EKnockBackType` enum applies to player knockback as well.

## TL;DR

- **"Damage" in OS doesn't kill — it makes you knockback-vulnerable.**
  Lethality comes from being knocked off the arena edge, not from
  damage per se.
- **The state of being knockback-vulnerable is called *staggered*.**
  Build up enough stagger and the next solid hit can punt you off
  the arena into a temporary KO.
- **A KO removes a player from active play for several seconds.**
  During that window the team is short-handed, the Core has fewer
  defenders, and scoring chances open up.
- **KO pressure is a strategic resource, not just an end state.**
  The threat of imminent KO changes positioning, cooldown
  expenditure, and Energy decisions for everyone on the field —
  even before any KO happens.

## What "damage" actually means

In most games, damage subtracts from a health bar; at zero, you die.
Omega Strikers does not work that way.

In OS:

| Concept | What it actually does |
|---|---|
| **Damage** | Increases the player's *stagger* meter. Stagger does not, by itself, kill. |
| **Stagger** | A meter that fills as a player takes damage. The fuller the stagger, the more knockback the player suffers from each subsequent hit. |
| **KO** | Triggered when a player gets knocked off the arena (over the edge). Removes them from active play for a respawn window. |
| **Death** | There is no "die at zero HP." There is only KO via ringout. |

The implication is that a player at high stagger near a wall is
*not* in immediate danger; a player at low stagger near a *cliff
edge* very much is. **Position matters more than current stagger
state.**

## Stagger as accumulated pressure

The stagger meter is the load-bearing combat number. It grows from
basic Strikes that hit you, ability hits, and other knockback-
dealing interactions.

### What the player observes

- **The stagger bar/indicator fills visibly** on the player and on
  enemies — both teams need to read each other's stagger to make
  decisions.
- **High stagger = bigger knockback on the next hit.** A staggered
  player who gets clipped by an ability that *normally* nudges them
  may, when staggered, fly across the arena.
- **Stagger does NOT decay instantly.** It carries between exchanges
  within an active round. Whether stagger fully resets on round-end
  / set-end / KO-respawn is mechanically important and **TBD** in
  this docset; player observation suggests reset on KO and on
  round-end.

### Why stagger is a positional signal

Stagger interacts with the arena's edges. The further from the
center a player is, the less knockback is required to punt them
off. So stagger is really a **dual-axis** signal:

```text
KO risk ≈ stagger * proximity-to-edge
```

A high-stagger player at the center of the arena is in modest
danger. A low-stagger player against the edge is also in modest
danger. A high-stagger player at the edge is in *immediate* danger.
This is why competent forwards push enemies *toward edges* before
committing the KO Strike — they're stacking both axes of the risk
multiplier.

## KO as a match-state shift

A KO is **not just a kill**. The strategic consequences ripple
through the whole team's play.

### What changes when someone gets KO'd

- **Team count drops to 2-on-3 (or worse).** The KO'd team is
  outnumbered for the duration of the respawn window.
- **Map control shifts.** With fewer defenders, the side that lost
  the player is more vulnerable to Core pressure.
- **Cooldowns and Energy on the surviving teammates matter more.**
  A 2v3 team with no Energy is in much worse shape than a 2v3 team
  with one Energy Burst available.
- **Scoring windows open.** Most opportunistic scoring in OS comes
  from a recently-KO'd opponent. Forwards specifically build toward
  KO + score combos.
- **The KO'd player respawns elsewhere on the arena.** Specific
  respawn timing and location rules are **TBD** in this docset;
  player observation suggests a few seconds of respawn delay and
  spawn at a designated team spawn location, not where the player
  was KO'd.

### KO pressure as a forcing function

The *threat* of KO does work even when nobody actually gets KO'd:

- **Forces enemy retreat.** A high-stagger enemy near the edge
  retreats to safer ground, ceding map control.
- **Forces enemy resource expenditure.** A high-stagger enemy may
  Evade or pop Energy Burst defensively (see
  [`energy-evade-burst.md`](./energy-evade-burst.md)) just to
  survive — burning resources that would otherwise have gone toward
  Core control.
- **Distorts goalie / forward calculus.** A goalie who's one-shot
  from KO can't safely commit forward to clear; a forward who's
  one-shot from KO can't safely keep pressuring at the edge.

This is why "I never KO anyone" can still be a contributing combat
playstyle: forcing the enemy team to play scared is itself a
contribution.

## Why this matters for OSPlus

Several feature classes touch combat directly:

- **Stagger / KO clarity overlays.** The native game already shows
  stagger; any overlay that *adds more* needs to clear the bar set
  by [`in-match-hud.md` → "HUD discipline rules"](./in-match-hud.md#hud-discipline-rules)
  — particularly: do not visually obscure the Core or the arena
  edge.
- **Goalie training tools.** Stagger management at the goal line is
  a real skill; drills that teach it are valuable.
- **KO highlight reel / replay tools.** KOs are natural highlight
  moments. Reconstruction needs accurate stagger + position state
  at KO time, not just the KO event itself.
- **Combat-related telemetry.** Per-match KO inflicted/received,
  stagger pressure, edge-positioning frequency — all useful inputs
  to post-match analysis. The per-match counter `KOAttempts` (or
  similar) likely exists; the exact field name belongs in the
  engine doc, not here. See
  [glossary → "Core (a.k.a. Rock)"](../glossary.md#core-aka-rock)
  for the related per-match counter table location.

## What's dangerous to combat balance

A change is hostile to OS combat if it:

- Makes KO pressure too unavoidable (no defensive recourse).
- Makes KO pressure too weak to matter (combat becomes irrelevant
  to scoring).
- Makes knockback direction unclear (player can't predict where the
  hit will send them).
- Makes stagger state unclear (player can't read their own or
  enemy KO risk).
- Adds VFX or overlays that hide the arena edge (the load-bearing
  visual cue for KO risk).

The overall design rule: **a KO should feel earned (by the
attacker) and avoidable-in-hindsight (by the defender)**. Any
feature that breaks either side of that contract drifts toward
unfun.

## Engine bridge (one-link summary)

Combat-related engine names are partially documented today:

- **Knockback classification.** `EKnockBackType` enum applies to
  both Core knockback and player knockback. `EKnockBackType::Redirect = 2`
  is the Core-redirect case; player-knockback enum values are TBD
  in this docset. See
  [glossary → "Core (a.k.a. Rock)"](../glossary.md#core-aka-rock)
  for the confirmed enum location.
- **Per-match counters.** Per-player KO/stagger counters likely
  live on `PMPlayerMatchSummary` alongside `RedirectRock` and
  `HitRockIntoGoalArea`; specific field names for combat counters
  are TBD. See
  [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) → *Per-match runtime
  data* for the counter cluster's home.
- **Respawn UFunctions / events.** Likely on `PMPlayerState` /
  `PMPlayerController_Game_C` with names involving `Respawn`,
  `KnockedOut`, or similar. Not catalogued here. **TBD.**

Per ADR 0003, the engine search-target list does not live in this
player-side doc. Start from
[`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) and follow into the
(planned) `docs/engine/combat.md`.

## Open questions

- **Exact stagger reset rules.** When does stagger fully reset?
  On KO-respawn (player-observed)? On round-end? On set-end? Never
  within a match? Player intuition is "on KO and on round-end" but
  unconfirmed. **TBD.**
- **Per-Striker stagger thresholds.** Some kits visibly tank more
  hits before going down. Whether this is a per-Striker `MaxStagger`
  stat, an Awakening modifier, or a derived value — unclear from
  player perspective. **TBD; per-Striker matrix lives in
  `strikers-and-abilities.md` *(planned)*.**
- **Respawn timer and location rules.** Player sees "respawn after
  ~few seconds at team spawn" but the exact delay, the exact
  location, and whether they vary by mode/Awakening are TBD.
- **The combat-side of the per-match counter cluster.** KO inflicted,
  KO received, stagger applied, edge-pushes — likely all live on
  `PMPlayerMatchSummary` but field names are not catalogued in
  this docset. **TBD; will surface during the engine doc migration.**
- **Damage source attribution edge cases.** When a player gets KO'd
  by a hit chained from a different player's prior hit, who gets
  credit? Probably the last-hit player, but TBD for
  ability-deployable cases.
- **Whether ring-out is binary or has fall-zones.** Player
  observation: yes, a player either lands inside the arena or KO's
  if punted past the edge. Nuances (e.g., partial-fall recovery via
  Evade) — TBD.

## Cross-references

- Roles whose play centers on combat read: [`roles.md`](./roles.md)
- Energy resources used to escape combat or commit to it: [`energy-evade-burst.md`](./energy-evade-burst.md)
- Power Orbs that grant stagger recovery: [`power-orbs.md`](./power-orbs.md)
- Match flow context (KO-respawns happen mid-round): [`match-lifecycle.md` → "Player states (in-match)"](./match-lifecycle.md#player-states-in-match)
- HUD discipline (do not hide arena edge): [`in-match-hud.md` → "HUD discipline rules"](./in-match-hud.md#hud-discipline-rules)
- Engine bridge for knockback enums: [glossary → "Core (a.k.a. Rock)"](../glossary.md#core-aka-rock)
- Sibling docs index: [`docs/game/README.md`](./README.md)
