# Omega Strikers Player Context for OSPlus Agents

This document explains what it is like to play **Omega Strikers** from the perspective of a player, for use by coding agents working on reverse engineering, feature design, UX changes, gameplay systems, or mod development.

The goal is to help an agent understand the *game context* behind the code it is modifying.

> **Migration in progress.** Per [ADR 0003](../decisions/0003-knowledge-substrate-structure.md),
> this monolithic doc is being decomposed into per-topic files under
> `docs/game/`. Sections that have moved are stubbed (heading retained,
> body replaced with a redirect). Untouched sections remain canonical
> here until they too are migrated.
>
> **Where to start instead:**
>
> - New agent / first-time read → [`overview.md`](./overview.md)
> - Player ↔ engine concept bridge → [`docs/glossary.md`](../glossary.md)
> - Full topic index + status table → [`docs/game/README.md`](./README.md)
>
> **Migrated so far (batch 1, 2026-04-29):** §1, §2, §3, §4, §5, §6,
> §18, §19, §23, §25, §29, §30.

---

# 1. Baseline Assumption

> **Migrated → [`overview.md` → "Current-version baseline"](./overview.md#current-version-baseline-required-reading).**
> Section retained as a stub so existing references (Sec 1) still resolve.

---

# 2. One-Sentence Identity

> **Migrated → [`overview.md` → "One-sentence identity"](./overview.md#one-sentence-identity).**
> Section retained as a stub so existing references (Sec 2) still resolve.

---

# 3. Core Player Session Flow

> **Migrated → [`match-lifecycle.md` → "Session flow"](./match-lifecycle.md#session-flow).**
> Section retained as a stub so existing references (Sec 3) still resolve.

---

# 4. Main Gameplay Objective

> **Migrated → [`overview.md` → "Main gameplay objective"](./overview.md#main-gameplay-objective).**
> Section retained as a stub so existing references (Sec 4) still resolve.

---

# 5. The Core Is the Main Gameplay Object

> **Migrated → [`overview.md` → "The Core is the main gameplay object"](./overview.md#the-core-is-the-main-gameplay-object).**
> Engine-side bridge: [`docs/glossary.md` → "Core (a.k.a. Rock)"](../glossary.md#core-aka-rock).
> Section retained as a stub so existing references (Sec 5) still resolve.

---

# 6. Match Structure

> **Migrated → [`match-lifecycle.md`](./match-lifecycle.md).**
> Specifically: ["Match structure"](./match-lifecycle.md#match-structure-sets-rounds-goals),
> ["State machine"](./match-lifecycle.md#state-machine),
> ["Player states"](./match-lifecycle.md#player-states-in-match),
> ["Core states"](./match-lifecycle.md#core-states-in-match),
> ["High-pressure states"](./match-lifecycle.md#high-pressure--endgame-states).
> Section retained as a stub so existing references (Sec 6) still resolve.

---

# 7. Goals and Barriers

Goals are not simply open nets at all times.

The game uses goal barriers/gates that must usually be broken before the goal is fully open.

The player constantly tracks:

```text
Which enemy barriers are still up
Which friendly barriers are still up
Whether the goal is open
Which barrier is vulnerable
Whether a shot should target the barrier or the open goal
```

Gameplay implications:

```text
Breaking a barrier is often a major strategic step before scoring.
A team can be under pressure even before conceding if its barriers are broken.
Goalies defend both the barriers and the goal itself.
Forwards often coordinate pressure to break barriers, then score afterward.
```

For agents:

```text
Goal barrier state is not cosmetic.
It affects tactical decisions, scoring routes, UI priority, camera attention, and player stress.
```

---

# 8. Player Roles

Omega Strikers has role-like behavior, especially goalie and forward.

These roles are not completely rigid, but they strongly shape player expectations.

---

## 8.1 Goalie

The goalie usually plays closer to their own goal.

The goalie cares about:

```text
Clearing the Core safely
Blocking shots
Protecting goal barriers
Defending an open goal
Avoiding enemy stuffing
Avoiding wasted Strike timing
Managing cooldowns defensively
Tracking enemy forwards
Using Energy Burst for clutch saves
Preventing rebounds near the goal
```

Goalie gameplay is about discipline and reaction.

A goalie feature should prioritize:

```text
Core readability
Threat readability
Cooldown visibility
Clear direction feedback
Barrier state visibility
Energy availability
Enemy pressure awareness
```

A change is dangerous if it:

```text
Makes close-range stuffing unavoidable
Makes the Core visually unclear near the goal
Removes the goalie's ability to react
Punishes correct defensive positioning too hard
Adds visual clutter in the goal area
```

---

## 8.2 Forward

Forwards usually play farther upfield and pressure the enemy side.

A forward cares about:

```text
Scoring
Breaking barriers
Pressuring the enemy goalie
Passing
Controlling midfield
KOing or staggering enemies
Denying clears
Creating Core angles
Collecting or denying Power Orbs
Punishing enemy cooldowns
```

Forward gameplay is about pressure, timing, positioning, and opportunity creation.

A forward feature should prioritize:

```text
Aim feedback
Core angle readability
Enemy stagger information
Cooldown combo clarity
Barrier targeting
Orb awareness
Passing lane readability
```

A change is dangerous if it:

```text
Makes scoring too automatic
Removes defensive counterplay
Over-rewards blind aggression
Makes KO pressure too dominant
Makes midfield control irrelevant
```

---

## 8.3 Flexible / Rotational Play

Good players often rotate between offense and defense.

Do not assume:

```text
Goalie always stays inside goal
Forwards never defend
The same player always touches the Core
The map has fixed lanes like a MOBA
```

Omega Strikers is fluid.

A forward may rotate back to save.
A goalie may step forward to clear or pressure.
Teams constantly shift based on Core position, cooldowns, barrier state, and stagger state.

---

# 9. Strikers

A **Striker** is a playable character with a unique kit.

A Striker usually has:

```text
Basic Strike
Primary ability
Secondary ability
Special ability
Unique stats
Unique role tendencies
Unique ability interactions with players and the Core
```

Strikers are not just skins.
They define how the player interacts with the match.

For reverse engineering, search for concepts like:

```text
StrikerDefinition
CharacterDefinition
HeroDefinition
AbilityPrimary
AbilitySecondary
AbilitySpecial
AbilityCooldown
AbilityHitbox
AbilityProjectile
AbilityCastTime
AbilityRange
AbilityDamage
AbilityKnockback
CoreHitModifier
PlayerHitModifier
StatusEffect
Buff
Debuff
```

Design rule:

```text
A good feature preserves Striker identity.
A bad feature makes every Striker feel the same or breaks the intended rhythm of a kit.
```

Examples of broad Striker identity patterns:

```text
Close-range brawler
Projectile poke
Defensive goalie
Area control
Summoner / deployable control
Mobility assassin
Hook / displacement specialist
Support / buff / utility character
```

---

# 10. Abilities

Abilities are central to both combat and Core control.

An ability may be used to:

```text
Hit the Core
Redirect the Core
Accelerate the Core
Stop or slow the Core
Damage enemies
Stagger enemies
Knock enemies away
KO enemies
Create terrain or obstacles
Buff allies
Debuff enemies
Move the player
Control space
Deny an area
Force enemy cooldowns
```

Important:

```text
Do not treat abilities as only combat tools.
Do not treat abilities as only ball-control tools.
Most ability design exists in the overlap between fighting and Core control.
```

For reverse engineering, ability logic may have different behavior depending on target:

```text
onCoreHit
onPlayerHit
onAllyHit
onEnemyHit
onBarrierHit
onTerrainHit
onProjectileExpire
onRecast
onChargeStart
onChargeRelease
onDeployableSpawn
onDeployableExpire
```

Feature design should ask:

```text
How does this affect Core control?
How does this affect enemy pressure?
How does this affect goalie defense?
How does this affect KO threat?
How does this affect visual readability?
How does this interact with Awakenings?
```

---

# 11. Strike

The basic Strike is one of the most important actions in the game.

Strike is used to hit the Core and redirect it.

Strike timing matters because:

```text
Players can bait each other's Strike
A wasted Strike can open a scoring window
Goalies often lose goals after mistimed Strikes
Forwards can stuff the Core through defenders after forcing Strike
Cooldown timing creates mind games
```

For agents:

```text
Strike is not just a simple input.
It is a timing-based interaction with high tactical importance.
```

Potential related systems:

```text
Strike cooldown
Strike direction
Strike hitbox
Strike priority
Core ownership
Input buffering
Aim assist
Controller behavior
Latency compensation
Prediction
```

---

# 12. Stagger and KO

Players can take damage and become vulnerable to knockback.

As pressure builds, a player can be knocked out of the arena and temporarily removed from play.

This creates temporary advantage.

Important concepts:

```text
Damage does not only mean killing.
Damage increases positional danger.
Low stagger makes edges and corners more dangerous.
KOs create scoring windows.
KO pressure can force enemies to retreat or waste resources.
```

For gameplay design:

```text
A KO is not just a reward.
It changes team numbers, map control, and Core pressure.
```

Dangerous changes:

```text
Too much unavoidable KO pressure
Too little KO threat, making combat irrelevant
Unclear knockback direction
Unclear stagger state
Effects that hide ring-out danger
```

---

# 13. Energy, Evade, and Energy Burst

Players have an Energy resource.

Energy-related actions are extremely important for survival and clutch plays.

Broadly:

```text
Evade = defensive avoidance / survival tool
Energy Burst = high-impact Core control and emergency reversal tool
```

Energy affects:

```text
Goalie clutch saves
Forward stuffing
Survival against KO pressure
Core priority
Late-set comeback potential
High-pressure defensive plays
```

For agents:

```text
Do not change Energy lightly.
Energy affects both combat survivability and Core control.
```

A mod feature involving Energy should consider:

```text
Does this make goalies too safe?
Does this make forwards too oppressive?
Does this remove clutch saves?
Does this make KO pressure meaningless?
Does this create too much Core priority?
```

---

# 14. Power Orbs

Power Orbs are neutral pickups that appear during play.

They typically matter because they can provide value such as:

```text
Stagger recovery
Experience
Energy gain
Map control incentives
```

Power Orbs create micro-objectives.

Players may fight over them because they can:

```text
Keep a low-stagger player alive
Enable Energy Burst sooner
Help players level
Create positional bait
Pull teams toward contested space
```

For agents:

```text
Orb spawn timing, location, pickup rules, and rewards affect match pacing and comeback potential.
```

---

# 15. Awakenings

Awakenings are the current official version's main in-match build system.

Players select Awakenings:

```text
At the start of the match
Between sets
```

Awakenings can modify things like:

```text
Ability size
Projectile size
Cooldown rate
Speed
Power
Damage
Knockback
Range
Creation/deployable size
Energy behavior
Orb effects
Special ability availability
Survivability
Scaling over the match
```

Awakenings are not just passive stats.
They are a draft-based adaptation system.

They create questions like:

```text
What does my Striker need?
What does my role need?
What does this map reward?
What is the enemy team building?
What does my team lack?
Should I draft for scoring, survival, cooldowns, size, or utility?
```

For OSPlus:

```text
Awakening systems are central to current Omega Strikers build expression.
Do not replace them accidentally with beta-era pre-match build assumptions.
```

Feature ideas should be framed as:

```text
Awakening draft assistance
Awakening recommendation logic
Post-match Awakening analysis
Practice-mode Awakening simulation
Awakening balance experiments
New Awakening design
Awakening UI improvements
```

Not as:

```text
Traditional pre-match item build editor
Full pre-match loadout planner
Static build selection before queue
```

Unless OSPlus is intentionally adding that as a new system.

---

# 16. Gear

Gear is selected before the match and gives passive role/style tuning.

Gear is not the same as a full build.

Useful model:

```text
Striker kit = base identity
Gear = pre-match role/style tuning
Awakenings = in-match build evolution
Map = environmental constraint
Team composition = strategic context
Enemy composition = counterplay context
```

Gear should be understood as a limited pre-match choice, not a complete build system.

---

# 17. Maps / Arenas

Maps are gameplay systems, not just backgrounds.

An arena may define:

```text
Goal shape
Barrier layout
Wall geometry
Core bounce behavior
Hazards
Special objectives
Orb spawn points
Spawn locations
Camera framing
Visual readability
Choke points
Safe zones
Danger zones
```

A map affects:

```text
Which Strikers are strong
Which Awakenings are valuable
How goalies defend
How forwards pressure
Where KOs happen
Where orbs are contested
How Core rebounds behave
```

Bad map design symptoms:

```text
Core becomes hard to see
Wall bounces feel unpredictable
Hazards dominate too much
Goalie has no reasonable defense
Forwards cannot reasonably break barriers
Orb spawns create runaway advantage
Visual clutter hides important state
```

---

# 18. What the Player Tracks During Gameplay

> **Migrated → [`in-match-hud.md` → "What the player tracks (perception load)"](./in-match-hud.md#what-the-player-tracks-perception-load).**
> Section retained as a stub so existing references (Sec 18) still resolve.

---

# 19. Lobby UX

> **Migrated → [`lobby.md`](./lobby.md).**
> Specifically: ["What the player wants here"](./lobby.md#what-the-player-wants-here)
> and ["What's on screen"](./lobby.md#whats-on-screen).
> Section retained as a stub so existing references (Sec 19) still resolve.

---

# 20. Striker Select UX

During Striker select, the player wants to know:

```text
What role am I playing?
What map are we on?
What has my team picked?
What has the enemy picked, if visible?
Are there bans?
Which Strikers are available?
Which Striker should I pick?
Which gear should I use?
What cosmetics are selected?
How much time remains?
```

Current-version warning:

```text
Do not add assumptions about full pre-match builds here.
Striker select is not a full build editor in the current official format.
```

---

# 21. Starting Awakening Draft UX

At the start of a match, players select an initial Awakening.

The player wants to know:

```text
What options are available?
What does each Awakening do?
Which one works with my Striker?
Which one works with my role?
Which one works on this map?
Which one counters or complements team compositions?
How much time remains?
```

For agents:

```text
This is the start of the player's actual build path.
```

---

# 22. Between-Set Awakening Draft UX

Between sets, players draft more Awakenings.

The player wants to know:

```text
Who won the last set?
What went wrong or right?
What Awakenings are available now?
What has my team already drafted?
What have enemies drafted?
What does my Striker need next?
Do I need offense, defense, cooldowns, size, speed, survival, or utility?
How much time remains?
```

This is a strategic adaptation moment.

A good OSPlus feature could help the player understand:

```text
Why an Awakening is good
Whether it fits the Striker
Whether it fits the map
Whether it helps the current match state
```

---

# 23. Gameplay HUD UX

> **Migrated → [`in-match-hud.md`](./in-match-hud.md).**
> Specifically: ["HUD elements"](./in-match-hud.md#hud-elements),
> ["Reaction wheel"](./in-match-hud.md#reaction-wheel-emotes--emoticons),
> ["HUD discipline rules"](./in-match-hud.md#hud-discipline-rules).
> Section retained as a stub so existing references (Sec 23) still resolve.

---

# 24. Post-Match UX

After a match, the player wants to know:

```text
Did we win or lose?
How did I perform?
Did my rank change?
Did I complete missions?
Did I earn rewards?
Which stats mattered?
Do I want to queue again?
Do I want to change Striker, cosmetics, role, party, or mode?
Do I want to report, add, or commend someone?
```

Do not phrase post-match flow as:

```text
Change build and queue again
```

Better:

```text
Queue again, change Striker/cosmetics/mode, inspect stats/progression, party up, or leave.
```

If discussing builds post-match, frame it as:

```text
Review Awakening choices
Review gear choice
Review Striker fit
Review map/team/enemy interaction
```

---

# 25. Screens / States a Player May See

> **Migrated → [`screens.md`](./screens.md).**
> Specifically: ["At a glance"](./screens.md#at-a-glance) (categorized
> inventory with engine-class hooks),
> ["Per-screen detail"](./screens.md#per-screen-detail), and
> ["Navigation graph"](./screens.md#navigation-graph) (Mermaid).
> Section retained as a stub so existing references (Sec 25) still resolve.

---

# 26. Reverse Engineering Search Targets

When exploring the codebase, search for conceptual clusters.

Match state:

```text
Match
GameMode
Round
Set
Score
Victory
Defeat
Overtime
MatchState
GameState
```

Core:

```text
Core
Puck
Ball
Strike
Redirect
Knockback
CoreHit
CoreFlip
CoreVelocity
CoreCollision
EnergyBurst
```

Goals and barriers:

```text
Goal
GoalGate
GoalBarrier
Barrier
GoalArc
GoalLine
OpenGoal
Gate
```

Players and Strikers:

```text
Player
Striker
Character
Hero
Pawn
Avatar
Team
Role
Goalie
Forward
```

Abilities:

```text
Ability
Primary
Secondary
Special
Cooldown
Cast
Recast
Projectile
Hitbox
Area
Creation
Deployable
```

Combat:

```text
Damage
Stagger
Knockback
KO
Respawn
StatusEffect
Buff
Debuff
Stun
Slow
Banish
```

Progression and builds:

```text
XP
Level
Awakening
Gear
Mission
Affinity
Reward
Rank
```

UI:

```text
HUD
Scoreboard
Draft
AwakeningDraft
StrikerSelect
Lobby
Queue
PostMatch
Reward
Store
Settings
```

Networking:

```text
Replication
Prediction
ServerAuthority
ClientState
Matchmaking
Reconnect
Latency
Rollback
Input
```

---

# 27. OSPlus Feature Design Principles

Use these as design constraints.

---

## 27.1 Preserve Core Readability

The Core must always be easy to see and understand.

Avoid:

```text
Large opaque VFX over the Core
UI overlays near the Core
Skins that hide Core direction
Map art that blends with the Core
Too many simultaneous indicators
```

---

## 27.2 Preserve Goalie Agency

Goalies need reasonable tools to defend.

Avoid:

```text
Unreactable scoring patterns
Unavoidable stuffing
Visual clutter in the goal area
Too many forced open-goal states
Abilities that remove defensive counterplay
```

---

## 27.3 Preserve Forward Pressure

Forwards need ways to create threats.

Avoid:

```text
Goalies becoming too safe
Defensive tools that erase all pressure
Barrier systems that are too hard to break
Maps where offense cannot create angles
```

---

## 27.4 Respect Cooldown Mind Games

Players often bait and punish cooldowns.

Important interactions:

```text
Bait Strike
Force goalie ability
Punish wasted evade
Wait for enemy projectile
Use Core timing to force bad reactions
```

Do not accidentally remove this timing layer.

---

## 27.5 Respect Striker Identity

Each Striker should keep a recognizable rhythm.

Avoid:

```text
Universal mechanics that make kits feel samey
Awakenings that erase weaknesses too easily
Balance changes that remove signature play patterns
```

---

## 27.6 Avoid Visual Pollution

Omega Strikers is already visually busy.

A feature should be visually quiet unless it communicates something very important.

Ask:

```text
Does this help the player make a decision?
Can it be smaller?
Can it be shown only when relevant?
Can it be moved away from the Core?
Can it be represented with existing UI language?
```

---

## 27.7 Design Around Sets, Not Just Goals

The match evolves across sets through Awakening drafts.

A feature should consider:

```text
Early set state
Late set state
Match point
Comebacks
Awakening scaling
Enemy adaptation
Team adaptation
```

---

# 28. Good OSPlus Feature Categories

Useful OSPlus features could include:

```text
Awakening draft helper
Post-match Awakening analysis
Striker matchup notes
Map-specific tips
Goalie training tools
Core trajectory practice
Replay or highlight tools
Custom lobby improvements
Spectator UI improvements
Damage / stagger clarity improvements
Better post-match stats
Improved Striker ability descriptions
Better onboarding tutorials
Practice drills
Balance sandbox tools
Custom Awakening experiments
Custom map experiments
```

Be careful with:

```text
Pre-match build planners
Full item systems
Heavy visual overlays
Overly automated recommendations
Features that reduce player agency
Features that make the Core harder to read
```

---

# 29. Agent Memory Summary

> **Migrated → [`overview.md`](./overview.md).**
> The entire `overview.md` doc *is* the agent memory summary; the eight
> design priorities live in
> [overview.md → "OSPlus design principles (compact)"](./overview.md#osplus-design-principles-compact).
> Section retained as a stub so existing references (Sec 29) still resolve.

---

# 30. Instruction for Coding Agents

> **Migrated → [`overview.md` → "OSPlus design principles (compact)"](./overview.md#osplus-design-principles-compact).**
> Section retained as a stub so existing references (Sec 30) still resolve.
