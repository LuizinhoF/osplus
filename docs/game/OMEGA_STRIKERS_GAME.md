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
> **Migrated so far:**
>
> - **Batch 1 (2026-04-29):** §1, §2, §3, §4, §5, §6, §18, §19, §23, §25, §29, §30
> - **Batch 2 (2026-04-30):** §7, §11, §15, §21, §22
> - **Batch 3 (2026-04-30):** §8 (incl. §8.1-8.3), §12, §13, §14

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

> **Migrated.** High-level take: [`overview.md` → "The Core is the main gameplay object"](./overview.md#the-core-is-the-main-gameplay-object).
> Player-side mechanic depth: [`core-and-strike.md`](./core-and-strike.md).
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

> **Migrated → [`goals-and-barriers.md`](./goals-and-barriers.md).**
> Engine-side bridge: [`docs/glossary.md` → "Goal & Barrier"](../glossary.md#goal--barrier).
> Section retained as a stub so existing references (Sec 7) still resolve.

---

# 8. Player Roles

> **Migrated → [`roles.md`](./roles.md).**
> Subsections 8.1 (Goalie), 8.2 (Forward), 8.3 (Flexible / Rotational
> Play) are all in that file. Engine-side bridge:
> [`docs/glossary.md` → "Goalie / Forward (role)"](../glossary.md#goalie--forward-role)
> — note that there is **no engine class for role**; roles are
> emergent.
> Section retained as a stub so existing references (Sec 8) still resolve.

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

> **Migrated → [`core-and-strike.md` → "The basic Strike"](./core-and-strike.md#the-basic-strike).**
> Engine-side bridge: [`docs/glossary.md` → "Core (a.k.a. Rock)"](../glossary.md#core-aka-rock).
> Section retained as a stub so existing references (Sec 11) still resolve.

---

# 12. Stagger and KO

> **Migrated → [`combat.md`](./combat.md).**
> Specifically: ["What 'damage' actually means"](./combat.md#what-damage-actually-means),
> ["Stagger as accumulated pressure"](./combat.md#stagger-as-accumulated-pressure),
> ["KO as a match-state shift"](./combat.md#ko-as-a-match-state-shift).
> Engine-side bridge for knockback: [`docs/glossary.md` → "Core (a.k.a. Rock)"](../glossary.md#core-aka-rock)
> (`EKnockBackType` enum applies to player knockback as well).
> Section retained as a stub so existing references (Sec 12) still resolve.

---

# 13. Energy, Evade, and Energy Burst

> **Migrated → [`energy-evade-burst.md`](./energy-evade-burst.md).**
> Specifically: ["The Energy resource"](./energy-evade-burst.md#the-energy-resource),
> ["Evade"](./energy-evade-burst.md#evade--defensive-avoidance),
> ["Energy Burst"](./energy-evade-burst.md#energy-burst--high-impact-core-control--emergency-reversal),
> ["Why they share a meter"](./energy-evade-burst.md#why-they-share-a-meter).
> The five-question Energy-feature evaluation checklist from this section
> is preserved verbatim in
> [energy-evade-burst.md → "Sec 13's checklist"](./energy-evade-burst.md#sec-13s-checklist-preserved).
> Section retained as a stub so existing references (Sec 13) still resolve.

---

# 14. Power Orbs

> **Migrated → [`power-orbs.md`](./power-orbs.md).**
> Specifically: ["What an Orb gives the player"](./power-orbs.md#what-an-orb-gives-the-player),
> ["Why Orbs distort positioning"](./power-orbs.md#why-orbs-distort-positioning),
> ["Orbs as the comeback engine"](./power-orbs.md#orbs-as-the-comeback-engine).
> Section retained as a stub so existing references (Sec 14) still resolve.

---

# 15. Awakenings

> **Migrated → [`awakenings.md`](./awakenings.md).**
> Specifically: ["What an Awakening is"](./awakenings.md#what-an-awakening-is)
> and ["OSPlus framing rules"](./awakenings.md#osplus-framing-rules).
> Engine-side bridge: [`docs/glossary.md` → "Awakening"](../glossary.md#awakening).
> Section retained as a stub so existing references (Sec 15) still resolve.

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

> **Migrated → [`awakenings.md` → "Starting Awakening (match start)"](./awakenings.md#1-starting-awakening-match-start).**
> Section retained as a stub so existing references (Sec 21) still resolve.

---

# 22. Between-Set Awakening Draft UX

> **Migrated → [`awakenings.md` → "Between-set Awakening drafts"](./awakenings.md#2-between-set-awakening-drafts).**
> Section retained as a stub so existing references (Sec 22) still resolve.

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
