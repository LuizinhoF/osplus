# Omega Strikers Player Context for OSPlus Agents

This document explains what it is like to play **Omega Strikers** from the perspective of a player, for use by coding agents working on reverse engineering, feature design, UX changes, gameplay systems, or mod development.

The goal is to help an agent understand the *game context* behind the code it is modifying.

> **Migration complete (player-side).** Per [ADR 0003](../decisions/0003-knowledge-substrate-structure.md),
> this monolith was decomposed into per-topic files under
> `docs/game/`. **All player-side sections are now migrated.** The
> two sections that remain in this file are **deliberately retained
> here**, not pending migration:
>
> - **Sec 26 — Reverse Engineering Search Targets.** Engine-side
>   material; will move to `docs/engine/` when that subtree
>   migrates out of [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md).
> - **Sec 28 — Good OSPlus Feature Categories.** Belongs in
>   [`docs/ROADMAP.md`](../ROADMAP.md), not in `docs/game/`.
>
> **Where to start instead:**
>
> - New agent / first-time read → [`overview.md`](./overview.md)
> - Player ↔ engine concept bridge → [`docs/glossary.md`](../glossary.md)
> - Full topic index → [`docs/game/README.md`](./README.md)
>
> **Migrated:**
>
> - **Batch 1 (2026-04-29):** §1, §2, §3, §4, §5, §6, §18, §19, §23, §25, §29, §30
> - **Batch 2 (2026-04-30):** §7, §11, §15, §21, §22
> - **Batch 3 (2026-04-30):** §8 (incl. §8.1-8.3), §12, §13, §14
> - **Batch 4 (2026-05-01):** §9, §10, §16, §17, §20, §24, §27 (incl. §27.1-27.7)

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

> **Migrated → [`strikers-and-abilities.md` → "What a Striker is"](./strikers-and-abilities.md#what-a-striker-is).**
> Engine-side bridge: [`docs/glossary.md` → "Striker"](../glossary.md#striker).
> Section retained as a stub so existing references (Sec 9) still resolve.

---

# 10. Abilities

> **Migrated → [`strikers-and-abilities.md` → "Abilities — what they actually do"](./strikers-and-abilities.md#abilities--what-they-actually-do).**
> Section retained as a stub so existing references (Sec 10) still resolve.

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

> **Migrated → [`gear.md`](./gear.md).**
> The three-build-layer mental model (kit / gear / Awakenings) is preserved verbatim
> in [gear.md → "The three build layers"](./gear.md#the-three-build-layers-preserved-from-source).
> Section retained as a stub so existing references (Sec 16) still resolve.

---

# 17. Maps / Arenas

> **Migrated → [`maps.md`](./maps.md).**
> Specifically: ["What a map varies on"](./maps.md#what-a-map-varies-on),
> ["How map shapes the rest of the game"](./maps.md#how-map-shapes-the-rest-of-the-game),
> ["Bad map design symptoms"](./maps.md#bad-map-design-symptoms-preserved-from-source).
> Engine-side bridge: [`docs/glossary.md` → "Map / Arena"](../glossary.md#map--arena).
> Section retained as a stub so existing references (Sec 17) still resolve.

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

> **Migrated → [`striker-select.md`](./striker-select.md).**
> Specifically: ["What the player wants to know here"](./striker-select.md#what-the-player-wants-to-know-here)
> and ["Current-version warning"](./striker-select.md#current-version-warning-preserve-verbatim-from-source).
> Section retained as a stub so existing references (Sec 20) still resolve.

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

> **Migrated → [`post-match.md`](./post-match.md).**
> Specifically: ["What the player wants to know here"](./post-match.md#what-the-player-wants-to-know-here)
> and ["Wrap-up framing"](./post-match.md#wrap-up-framing-preserve-from-source) (the
> "queue again, change something" framing preserved verbatim from this section).
> Section retained as a stub so existing references (Sec 24) still resolve.

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

> **Migrated → [`design-principles.md`](./design-principles.md).**
> All seven sub-principles (27.1-27.7) live there in long form. Compact
> seven-bullet summary at [`overview.md` → "OSPlus design principles (compact)"](./overview.md#osplus-design-principles-compact).
> Section retained as a stub so existing references (Sec 27) still resolve.

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
