# Roles — goalie, forward, flexible

How the three players on a team divide the field, the Core, and the
defensive responsibility — without any of those divisions being
encoded in the engine.

> **Status:** seeded 2026-04-30 from
> [`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 8.
>
> **Last validated against game patch:** 2026-04. Role tendencies
> are emergent and have been stable for a long time; the per-Striker
> role-fit catalog (which kits play which roles best) is patch-
> volatile and lives in `strikers-and-abilities.md` *(planned)*, not
> here. Re-validate this doc only when the game itself adds an
> explicit role concept (which would be a major design change).

This doc is the player-side framing. The bridge to engine reality
(no role enum, no `IsGoalie()`, but backend *does* track role
post-hoc) is in
[glossary → "Goalie / Forward (role)"](../glossary.md#goalie--forward-role).

## TL;DR

- **Roles are tactical, not mechanical.** A "goalie" is whoever
  positioned themselves near the team's own goal *this round*; a
  "forward" is whoever pushed up. There is no role pick, no role
  lane, no role hotkey, no engine flag.
- **There are roughly three roles in practice:** goalie, forward,
  and the *flexible* player who rotates between them based on what
  the match needs.
- **Roles are not rigid.** Good players rotate fluidly within a
  round. Bad assumptions about role rigidity (e.g., "the goalie
  should always be in the goal") collapse against actual play.
- **Striker kits *bias* roles but do not *assign* them.** Some kits
  reward goalie play, some reward forward play, some are flexible.
  The bias matters for draft and positioning, but doesn't prevent a
  player from playing a "goalie" Striker as a forward (or vice
  versa) if the situation calls for it.

## Why role even exists (without an engine concept)

There is no `Role` enum at runtime. No spawn slot tags a player as
"goalie" or "forward." The engine treats all three players on a team
identically. So why does the player community talk about roles at
all?

Because the *map geometry + the rules of scoring + the team-of-three
size* makes role-shaped play emerge whether the engine encodes it
or not:

- **Three players, two ends of the field, one Core.** With three
  players and only one ball-equivalent, someone has to defend while
  others pressure; the math doesn't work otherwise.
- **Goal-area defense is positional and reactive.** If everyone on
  the team is upfield, the goal is undefended; the team that figures
  out positional discipline wins.
- **The Core spends most of its time at one end of the field.**
  Whichever end it's at creates the goalie/forward asymmetry for
  that moment.

Roles are an *emergent strategy*, not a *built-in classification*.
This is important for OSPlus features: anything that wants to "know
the role" of a player at runtime is doing inference, not lookup. The
backend (Clarion API) does this inference post-match, but the rule
isn't documented and **the engine does not expose role at runtime**
(see the [Engine bridge](#engine-bridge-one-link-summary) below).

## Goalie

The player who plays closer to their own goal and absorbs defensive
responsibility.

### What the goalie cares about

- Clearing the Core safely (not just blocking it — clearing it
  *somewhere useful*)
- Blocking shots
- Protecting goal barriers (see
  [`goals-and-barriers.md`](./goals-and-barriers.md))
- Defending the goal when barriers are down
- Avoiding enemy stuffing (point-blank shots through a committed
  goalie)
- Avoiding wasted Strike timing (a goalie whose Strike is on
  cooldown is briefly defenseless)
- Managing cooldowns defensively
- Tracking enemy forwards
- Using Energy Burst for clutch saves (see
  [`energy-evade-burst.md`](./energy-evade-burst.md))
- Preventing rebounds near the goal

Goalie play is characterized by **discipline and reaction**. A
goalie reads, waits, holds position, then commits when forced.
Beginners over-commit; experienced goalies make the forwards waste
inputs trying to bait commits.

### What good goalie features look like

A feature aimed at goalies (training drill, HUD overlay, replay
analyzer, etc.) should help with:

- Core readability (especially near-goal traffic)
- Threat readability (which enemy is the imminent shooter)
- Cooldown visibility (own and enemy)
- Clear direction feedback on Strike outputs (where did my clear
  go?)
- Barrier state visibility (which barriers cover me)
- Energy availability
- Enemy pressure awareness (where is the second forward?)

### What's dangerous for goalies

A change is hostile to goalie play if it:

- Makes close-range stuffing unavoidable (no read, no recovery)
- Makes the Core visually unclear near the goal (clutter, particles,
  glow)
- Removes the goalie's ability to react (animations they can't
  cancel, locked-in inputs)
- Punishes correct defensive positioning too hard
- Adds visual clutter inside the goal area

The HUD discipline rules in
[`in-match-hud.md` → "HUD discipline rules"](./in-match-hud.md#hud-discipline-rules)
apply *especially* to the area around the goal.

## Forward

The player who plays farther upfield and pressures the enemy side.
The two-or-three forwards on a team coordinate to create scoring
chances.

### What the forward cares about

- Scoring
- Breaking barriers (see
  [`goals-and-barriers.md`](./goals-and-barriers.md))
- Pressuring the enemy goalie (forcing Strike commitment)
- Passing
- Controlling midfield
- KOing or staggering enemies (see
  [`combat.md`](./combat.md))
- Denying clears (intercepting the enemy goalie's Strike output)
- Creating Core angles (rebounds, pass-into-shot setups)
- Collecting or denying Power Orbs (see
  [`power-orbs.md`](./power-orbs.md))
- Punishing enemy cooldowns

Forward play is characterized by **pressure, timing, positioning,
and opportunity creation**. Forwards generate the situations the
goalie is then forced to react to.

### What good forward features look like

A feature aimed at forwards should help with:

- Aim feedback (where will my next Strike actually send the Core?)
- Core angle readability (rebound prediction)
- Enemy stagger information (am I about to KO?)
- Cooldown combo clarity (which abilities are off-cooldown for the
  combo?)
- Barrier targeting (which barrier is closest to breaking?)
- Orb awareness (where's the next Power Orb?)
- Passing lane readability (which teammate is in shot range?)

### What's dangerous for forwards

A change is hostile to forward play if it:

- Makes scoring too automatic (removes the read out of "did this
  shot work?")
- Removes defensive counterplay (becomes a one-sided dunk)
- Over-rewards blind aggression (positioning stops mattering)
- Makes KO pressure too dominant (combat replaces sport-feel)
- Makes midfield control irrelevant (no positional gradient)

## Flexible / rotational play

Real games are not goalie-and-two-forwards in a static arrangement.
Good teams rotate constantly based on the state of the field.

### Things that are NOT true at high play

- "The goalie always stays inside the goal."
- "Forwards never defend."
- "The same player always touches the Core."
- "The map has fixed lanes like a MOBA."

### What actually happens

- A forward rotates back to save when the goalie is KO'd, out of
  position, or low on Energy.
- A goalie steps forward to clear the Core toward an enemy whose
  defender just used cooldowns.
- A team may shift its nominal goalie mid-set if the matchups
  changed.
- A team trailing on the score may abandon strict role discipline
  to force more chaotic exchanges (creating comeback opportunities).

### Why this matters for OSPlus

Anything that *assumes a fixed role* will be wrong some non-trivial
fraction of the time. Specifically:

- Don't show a player a HUD element that says "you are the goalie"
  — they may not be, this round, this moment.
- Don't analyze stats with role as a hard prior — a player
  classified as "goalie" by the backend may have spent half the
  match upfield.
- Don't restrict feature availability by role — there's nothing to
  restrict it on at runtime, and the player will rotate anyway.

The most useful framing for an OSPlus role-aware feature is *"this
player has been playing closer to their goal recently"* — a soft,
recent-positioning-derived signal — rather than *"this player is a
goalie"*, which is a category error at runtime.

## Engine bridge (one-link summary)

[glossary → "Goalie / Forward (role)"](../glossary.md#goalie--forward-role)
is the canonical bridge.

Two facts that surprise new agents:

- **There is NO engine class for role.** No `Role` enum. No
  `IsGoalie()` UFunction. No role-tagged spawn slot. Roles are
  purely tactical, derived from positioning and Striker choice.
- **The backend (Clarion API) DOES classify role per match.** Per
  [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) → *Backend Ecosystem*,
  the API exposes `character × role × gamemode` aggregates,
  meaning the *backend* classifies role somehow. **How** it does so
  from in-match behavior is not documented — likely from goal-area
  dwell time or final position, but TBD.

This split has implications for any feature that wants to "know the
role" of a player. Real-time role inference must be *done by the
mod itself* using positioning heuristics; the engine will not hand
it over.

## Open questions

- **How does the backend classify role per match?** Likely from
  goal-area dwell time or final positioning, but unconfirmed.
  Probing this would require comparing per-match Clarion role
  output against observed in-match behavior. **TBD.**
- **Is there a runtime-detectable "intended role" anywhere?** E.g.,
  a Striker-recommendation tag, a queue-side role-pick UI (some
  competitive modes have role queue), a pre-match self-declared
  role. None confirmed. **TBD; check Striker-select UI flow when
  `striker-select.md` is migrated.**
- **What does the per-Striker role-fit catalog look like for the
  current patch?** Some kits are recognizably goalie-favored (e.g.,
  defensive area-control kits), others forward-favored (e.g.,
  burst/scoring kits). The full matrix belongs in
  `strikers-and-abilities.md` *(planned)*, not here, and is
  patch-volatile. **TBD until that doc lands.**

## Cross-references

- Glossary engine bridge: [glossary → "Goalie / Forward (role)"](../glossary.md#goalie--forward-role)
- Goal-area mechanics roles depend on: [`goals-and-barriers.md`](./goals-and-barriers.md)
- Combat / stagger / KO context for both roles: [`combat.md`](./combat.md)
- Energy / Evade / Burst mechanics both roles need to manage: [`energy-evade-burst.md`](./energy-evade-burst.md)
- Power Orb awareness (forward priority): [`power-orbs.md`](./power-orbs.md)
- HUD discipline (especially around the goal area): [`in-match-hud.md` → "HUD discipline rules"](./in-match-hud.md#hud-discipline-rules)
- Striker / kit identity that biases role: [`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 9-10 (until migrated to `strikers-and-abilities.md`)
- Sibling docs index: [`docs/game/README.md`](./README.md)
