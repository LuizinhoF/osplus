# In-match HUD

What the player sees, tracks, and acts on during active gameplay
(`GoalRoundActive` per [match-lifecycle.md](./match-lifecycle.md)).
The densest player-attention surface in the game — every pixel here
competes for limited cognitive budget.

> **Status:** seeded 2026-04-29 from
> [`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 18 + Sec 23,
> + reaction wheel detail from
> [`native-reaction-showemoticon-pmemoticondata`](../learnings/native-reaction-showemoticon-pmemoticondata.md).
> Several visual specifics TBD pending in-match observation.

## What the player tracks (perception load)

During active play, the player constantly tracks (in roughly
descending priority):

| Category | What | Why it matters |
|---|---|---|
| **Core** | Position; velocity; trajectory | Everything routes through Core control |
| **Self** | Position; cooldowns; stagger; Energy; role responsibility | Survival + readiness to act |
| **Team** | Teammate positions; their cooldowns (visible?); their stagger | Coordination, expecting backup |
| **Enemy** | Positions; cooldown threats (which abilities they can use *now*); stagger | Threat assessment, mind games |
| **Goals** | Barrier state (own + enemy); open-goal state | Tactical option space |
| **Map** | Power Orb spawns; map hazards; safe vs danger zones | Resource opportunity, KO risk |
| **Match** | Set score; match score; timer/pacing | Strategic context (urgency, set/match point) |

Player attention is finite. **A UI or VFX change should reduce
cognitive load, not increase it.** Every new HUD element competes
with these existing perception priorities.

## HUD elements

What the active gameplay HUD renders, organized by what each element
communicates. Per-pixel layout TBD pending in-match widget tree dump
([`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) → "Known Unknowns / UI
System" → "In-match widget tree (F3 dump during active gameplay
needed)").

| HUD element | Communicates | Engine surface (where known) |
|---|---|---|
| Score / set count | Match progress (e.g. "1-2 in set 3") | TBD widget |
| Timer / pacing | Time remaining (per round? per set?) | TBD |
| Ability cooldowns | Which of self's abilities are ready, and time-until-ready | TBD; per-Striker; primary/secondary/special trio |
| Energy state | Energy bar (drives Evade + Energy Burst) | TBD; per-player |
| Stagger state | How damaged the player is → KO vulnerability | TBD; tied to `DamageChanged` |
| Buffs / debuffs | Active status effects on self / others | TBD widget |
| KO feed | "X knocked out Y" event ticker | TBD; tied to `SpawnEffectsOnCharacterKnockedOut` |
| Goal announcements | "GOAL!" overlay when scoring happens | Tied to `SpawnGoalEffects` UFunction |
| Orb state | Power Orb spawn timer / availability | Tied to `IncrementOrbTracking` / `Set Random Power Orb` |
| Core-related alerts | Highlighting Core in danger zones | TBD |
| Player nameplates | See [Player nameplates](#player-nameplates) below | `WBP_CharacterNameplate_Base_C` |
| Reaction wheel | See [Reaction wheel](#reaction-wheel-emotes--emoticons) below | `WBP_ReactionButtonPanel_C` / `WBP_ReactionModal_C` |

The HUD should NOT distract from:
- Core visibility (the most important on-screen object)
- Player position
- Ability telegraphs (windups before enemy abilities land)
- Goal defense (especially for goalies)
- Enemy threats

## Player nameplates

Per-character above-head identity surface. **Confirmed engine class:
`WBP_CharacterNameplate_Base_C`** with `PlayerNameRichText` slot
(per [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) → "Networking /
Player Data" → display-name resolution).

What the nameplate shows is **TBD observation**. Likely candidates:
- Display name (rendered in `PlayerNameRichText`)
- Nameplate cosmetic (the `NameplateId` from
  [glossary → Cosmetic loadout](../glossary.md#cosmetic-loadout))
- Title (the `TitleId`)
- Current stagger / health indicator
- Active status effects (icons)
- Ability cooldown indicators (visible to teammates? to enemies?)
- Team color
- Country / clan / squad badge

The nameplate is **the canonical place earned cosmetics show up
visibly during play** — the OSPlus *In-game profile visible surface*
feature (Roadmap Next) hangs primarily on this surface, plus the
Home Hub.

**Open question (C3):** confirm what the nameplate actually shows in
current builds. Per-element inventory needed before any feature
attaches new content here.

## Reaction wheel (emotes / emoticons)

The native game's in-match reaction surface, bound to the **`1`-`7`
hotkeys** (per
[`native-reaction-showemoticon-pmemoticondata`](../learnings/native-reaction-showemoticon-pmemoticondata.md)).

### Player-facing shape

- **Trigger.** Press one of `1`-`7` during active gameplay → triggers
  the corresponding equipped reaction.
- **Loadout.** The player equips ≤7 reactions in the lobby (per
  `WBP_ReactionButtonPanel_C` in `WBP_HomeHub_PC_C` — see
  [lobby.md](./lobby.md)). Each loadout slot maps to one of the
  hotkeys.
- **Render.** TBD — likely above the player character, possibly with
  text in a chat-like band, possibly with audio. Per-element specifics
  pending observation.
- **Duration.** TBD — how long the reaction visual persists.
- **Frequency / spam.** TBD — whether there's a per-player cooldown,
  per-reaction cooldown, or no rate limiting.

### Two engine types, one player concept

Per [glossary → Emote / Emoticon](../glossary.md#emote--emoticon),
the native reaction wheel mixes two engine data classes:

- **`PMEmoteData`** — animated, striker-specific (e.g.
  `EmoteData_Asher_Delighted` references a Shieldz emote animation
  asset). Heavier — bakes in striker animation refs.
- **`PMEmoticonData`** — lighter icon + audio (texture + Wwise event,
  no striker animation dependency). E.g.
  `EmoticonData_JulietteComfy`.

Both render through the same UI shell (`WBP_ReactionButton` /
`WBP_ReactionModal` / `WBP_ReactionModalItem`) and the same gameplay
trigger (`BTT_UseReactionAndWait` calls `ShowEmote` /
`ShowEmoticon`). `WBP_ReactionModal_C` is the live runtime owner of
the reaction render call.

**Open question (C4):** are these two engine types presented to the
player as one undifferentiated "reaction" category, or as two
distinct types ("emote" vs "emoticon" / "sticker") with separate
loadout slots and separate UI affordances? Per-cosmetic-slot the
player has ONE `EmoticonId` — strongly suggesting the player-facing
distinction is at most "your equipped emoticon (1)" + "your equipped
emotes (≤6)" if both types share the wheel.

### OSPlus relevance

The `unlockable-earning-emotes` feature (Roadmap Now, currently
stashed in `stash@{0}`) targets this surface. Specifically:

- **Loadout step** — happens in the lobby
  (`WBP_ReactionButtonPanel_C` in `WBP_HomeHub_PC_C`). User equips
  an OSPlus-earned reaction into one of the loadout slots.
- **In-match render** — driven through `WBP_ReactionModal_C` via
  `ShowEmoticon` (the safer probe) or `ShowEmote` (animated; would
  require striker-compatible animation assets).
- **Asset class choice** — `PMEmoticonData` is the lighter probe; an
  OSPlus reaction implemented as `PMEmoticonData` works regardless
  of equipped Striker.

**Open question (C1):** the missing player-facing details for the
wheel itself (above) need answers before the feature's Stage 4
design can specify the visible behavior.

## HUD discipline rules

OSPlus's in-match UI rule (from Sec 23 of the source):

> **Extra information is only useful if it does not make the Core
> harder to track.**

Concrete checks for any new HUD element:

- Does this help the player make a decision they couldn't make
  without it?
- Can it be smaller?
- Can it be shown only when relevant (instead of always-on)?
- Can it be moved away from the Core?
- Can it be represented with existing UI language (existing colors,
  iconography, positioning conventions)?

These echo the design principles in
[`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 27 (until
migrated to `design-principles.md`).

## Match / network state at this point

- **Active gameplay phase.** `GameState_Game_C` exists,
  `PlayerState_Game_C` exists, `PlayerController.Pawn` is valid (modulo
  brief blips during respawn — see `match-lifecycle.md` → Player states).
- **Match seed.** `GameState_Game_C.CurrentMatchSeed` is non-zero —
  this is the canonical "is the match still happening" signal. See
  [`chat-match-detection-via-seed.md`](../learnings/chat-match-detection-via-seed.md).
- **Replication.** Most in-match state is server-replicated.
  `MatchPhaseChanged` fires on phase transitions; `DamageChanged`,
  `SpawnEffectsOnCharacterKnockedOut`, `IncrementOrbTracking`, etc.
  fire on per-event basis.

## Open questions

- **C1 — Reaction wheel UX.** Render position; duration; cooldown /
  spam protection; tap-vs-hold interaction; visual treatment.
- **C3 — Player nameplate inventory.** What the
  `WBP_CharacterNameplate_Base_C` nameplate actually shows in current
  builds, slot by slot.
- **C4 — Emote vs emoticon player distinction.** Whether the wheel
  presents both types as one category or two; whether equipped
  loadout slots differentiate.
- **In-match widget tree.** F3 dump during active gameplay would
  enumerate every HUD widget — currently only the menu widget tree is
  documented. (KNOWLEDGEBASE "Known Unknowns" list.)
- **HUD element layout.** Per-element on-screen position and size.
- **Visibility-of-others.** Which of (cooldowns, stagger, Energy,
  ability charges) am I shown about teammates? About enemies? Hidden
  for some?
- **Goal-area visibility cues.** What changes visually when a barrier
  is broken or the goal opens? Color shift? Outline? Particle?

## Cross-references

- Engine perspective: planned `docs/engine/widgets.md` (in-match
  widget tree); planned `docs/engine/player-state.md`
  (`DamageChanged`, KO event, etc.).
- Glossary: [Emote / Emoticon](../glossary.md#emote--emoticon),
  [Cosmetic loadout](../glossary.md#cosmetic-loadout),
  [Match](../glossary.md#match), [Striker](../glossary.md#striker).
- Sibling docs: [`match-lifecycle.md`](./match-lifecycle.md) (when
  this surface is active), [`lobby.md`](./lobby.md) (where reaction
  loadout is configured), [`screens.md`](./screens.md) (for the
  surrounding screens).
- Feature: [`docs/features/unlockable-earning-emotes.md`](../features/unlockable-earning-emotes.md)
  (currently stashed) — directly consumes this doc.
- Related learnings:
  [`native-reaction-showemoticon-pmemoticondata`](../learnings/native-reaction-showemoticon-pmemoticondata.md),
  [`chat-match-detection-via-seed`](../learnings/chat-match-detection-via-seed.md).
