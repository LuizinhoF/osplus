# OS concept glossary

Bidirectional cross-reference between **player-facing concepts** (the
vocabulary of [`docs/game/`](./game/)) and **engine-facing
implementation** (the vocabulary of [`KNOWLEDGEBASE.md`](../KNOWLEDGEBASE.md)
and the planned [`docs/engine/`](./engine/) subtree). Use this when:

- A player concept appears in feature work and you need to know what
  engine representation(s) to grep for, or
- An engine class appears in code/learnings and you need to know what
  the player calls it.

This is a **catalog**, not a dictionary. Entries appear here only when
there's real ambiguity — most often when one player concept maps to
multiple engine representations across different contexts (in-match
vs. menu vs. cosmetic), or when player vocabulary and engine
vocabulary genuinely don't agree (e.g. *Core* vs. *Rock*).

Every entry has the same shape: **player concept → engine
representation(s) → identity key (where applicable) → cross-references**.

## Conventions

- *Confirmed* — observed via runtime probe, dump tool, or production-shipping code.
- *TBD* — not yet investigated. Do not assume the obvious answer is correct; probe.
- Entries should never restate detail from `docs/game/`,
  `KNOWLEDGEBASE.md`, or learnings. They cross-reference. If a fact
  appears here that doesn't appear in those, either it's wrong or
  those docs need updating.
- New entries earn their place by demonstrating real ambiguity. A
  clean 1:1 mapping (e.g. *"basic Strike = `StrikeReleased`
  UFunction"*) doesn't need an entry; just put the engine name in the
  relevant `docs/game/<topic>.md`.

## Entries

- [Striker](#striker)
- [Core (a.k.a. Rock)](#core-aka-rock)
- [Player identity](#player-identity)
- [Match](#match)
- [Emote / Emoticon](#emote--emoticon)
- [Cosmetic loadout](#cosmetic-loadout)
- [Map / Arena](#map--arena)
- [Goalie / Forward (role)](#goalie--forward-role)
- [Awakening](#awakening)
- [Goal & Barrier](#goal--barrier)
- [Stub entries](#stub-entries) — Strike, Energy / Energy Burst, Power Orb, Stagger / KO

---

## Striker

**Player concept.** A playable character with a unique kit (basic
Strike + primary + secondary + special abilities). The player's
primary identity in a match. See `docs/game/strikers-and-abilities.md`
*(planned)*.

**Engine, varies by context:**

- **In-match (combat Pawn) — confirmed.** Spawned as
  `C_<InternalName>_C` (e.g. `C_FlexibleBrawler_C` = Juliette,
  `C_NimbleBlaster_C` = Drek'ar). One per active player. Held by
  `PlayerController.Pawn`. Lives only during the gameplay phase.
  Internal-name table in [`KNOWLEDGEBASE.md`](../KNOWLEDGEBASE.md)
  → *Characters (confirmed via F10 dump + runtime Pawn inspection)*.
- **Striker select / draft UI — TBD.** Likely uses
  preview/visualization classes (candidate widgets:
  `WBP_StrikerSelect_ChoosePhases_C`,
  `WBP_CharacterSelectPlayerCard_C`). Animated 3D model + ability
  descriptions. Engine class probably *not* the combat Pawn class —
  needs a probe pass.
- **Lobby home hub display — TBD.** Equipped Striker rendered in
  `WBP_HomeHub_PC_C` (specifically the `WBP_FitActorToRect_C` "3D
  character model in hub" child). Visualization actor class TBD.
- **Cosmetics / roster screens — TBD.** Striker as menu item / card.
  Engine class TBD.

**Identity key.** Across all engine contexts, the equipped Striker is
identified by a backend ID. The exact field name on `MeResponseV1` /
`PMPlayerPublicProfile` is TBD — probe needed.

**Cross-references.**
- Player perspective: `docs/game/strikers-and-abilities.md` *(planned)*.
- Engine perspective: `docs/engine/strikers.md` *(planned)* — internal-name table.
- Open questions: identity-key Clarion field; whether striker-select
  preview meshes share assets with combat `C_*_C` classes.

---

## Core (a.k.a. Rock)

**Player concept.** The puck-like object both teams fight over.
Central to every gameplay decision. See `docs/game/core-and-strike.md`
*(planned)* or [`docs/game/OMEGA_STRIKERS_GAME.md`](./game/OMEGA_STRIKERS_GAME.md)
Sec 5.

**Engine, naming gap.** **The internal name is "Rock", not "Core" /
"Puck" / "Ball".** All grep work must use `Rock`.

- **In-match actor — confirmed.** `PMRockCharacter`. Single instance
  per match. Owns `LastRedirectKnockBack` (per-event detail surface).
- **Per-match aggregate — confirmed.**
  `PMPlayerMatchSummary.RedirectRock` counts per-player redirects (the
  canonical OSPlus capture target). Documented in
  [`KNOWLEDGEBASE.md`](../KNOWLEDGEBASE.md) → *Per-match runtime data*.
- **Knockback classification — confirmed.**
  `EKnockBackType::Redirect = 2` classifies a redirect-on-Core
  knockback specifically.
- **Goal-explosion VFX — partial.** Folder
  `/Game/Prometheus/.../GoalScore/` contains art/VFX classes;
  specifics TBD.

**Cross-references.**
- Player perspective: `docs/game/core-and-strike.md` *(planned)*.
- Engine perspective: `docs/engine/rock-and-strike.md` *(planned)*.

---

## Player identity

**Player concept.** "Who am I?" / "Who is that other player?" — the
human behind a Striker. See `docs/game/player-systems.md` *(planned)*
or [`docs/game/OMEGA_STRIKERS_GAME.md`](./game/OMEGA_STRIKERS_GAME.md)
Sec 19.

**Engine: three identifier namespaces — distinct, not derivable from each other.**

| Identifier | Shape | Stable? | Source | Used by |
|---|---|---|---|---|
| **SteamID** | 17-digit decimal (`76561198022185004`) | Yes, cross-session | `PMIdentitySubsystem:GetSteamId()` | Steam; OSPlus profile binding today |
| **Prometheus ID** | 24-char hex (`6333a58673a37dc7cb11a7a7`) | Yes (assumed) | `PMPlayerPublicProfile.PlayerId` | Odyssey backend + every OS tracker |
| **Display name** | Mutable string (`Ispicas`) | No — user-mutable | `PlayerState.PlayerNamePrivate` (after replication) | Human UI |

**`PlayerNamePrivate` has THREE observed modes** — see
[`docs/learnings/playernameprivate-transient-account-id.md`](./learnings/playernameprivate-transient-account-id.md)
and [`docs/learnings/playernameprivate-machine-name-out-of-match.md`](./learnings/playernameprivate-machine-name-out-of-match.md).
Don't trust the value without checking which mode you're in.

**Cache vs. local.** `FindAllOf("PMPlayerPublicProfile")` returns
~100+ cached profiles of *other* players. **The local player is NOT in
this cache** — local identity comes from the `PMPlayerModel` getters,
not the public-profile cache. Full reachability matrix in
[`KNOWLEDGEBASE.md`](../KNOWLEDGEBASE.md) → *Player Identity Reference*.

**Cross-references.**
- Player perspective: `docs/game/player-systems.md` *(planned)*.
- Engine perspective: `docs/engine/identity-and-api.md` *(planned)*.
- Learnings:
  [`playernameprivate-transient-account-id`](./learnings/playernameprivate-transient-account-id.md),
  [`playernameprivate-machine-name-out-of-match`](./learnings/playernameprivate-machine-name-out-of-match.md),
  [`identity-display-name-substrate-replaces-heuristics`](./learnings/identity-display-name-substrate-replaces-heuristics.md),
  [`os-prometheus-api-ecosystem`](./learnings/os-prometheus-api-ecosystem.md).

---

## Match

**Player concept.** A queued PvP game from start (Striker select) to
finish (victory/defeat). See `docs/game/match-lifecycle.md`
*(planned)* or [`docs/game/OMEGA_STRIKERS_GAME.md`](./game/OMEGA_STRIKERS_GAME.md)
Sec 6.

**Engine, varies by mode:**

- **Online match — confirmed.** `GameState_Game_C` is the GameState
  class. Phase model documented in
  [`KNOWLEDGEBASE.md`](../KNOWLEDGEBASE.md) → *Game Lifecycle & Phase Detection*.
- **Practice mode — confirmed.** `GameState_Tutorial_C`. Different
  PlayerController (`PlayerController_Practice_C`).
  `PlayerNamePrivate` returns hex Prometheus ID instead of display
  name in this mode.
- **Custom lobby — TBD.** Whether custom lobbies use
  `GameState_Game_C` or a different class is not yet investigated.

**Identity key — `CurrentMatchSeed`.** The canonical "is a match
active" signal lives at `GameState_Game_C.CurrentMatchSeed` (non-zero
⇒ match in progress; stable across KOs, respawns, awakening
transitions, round resets). See
[`docs/learnings/chat-match-detection-via-seed.md`](./learnings/chat-match-detection-via-seed.md).
**Do not gate match-active state on local-player presence
(`Pawn ~= nil`)** — that signal blips during normal mid-match events.

**Cross-references.**
- Player perspective: `docs/game/match-lifecycle.md` *(planned)*.
- Engine perspective: `docs/engine/game-state-phases.md` *(planned)*.
- Learning: [`chat-match-detection-via-seed`](./learnings/chat-match-detection-via-seed.md) (the seed-vs-pawn lesson).

---

## Emote / Emoticon

**Player concept.** A reaction the player triggers during a match,
displayed visually + audibly to other players. The native game uses an
on-screen reaction wheel bound to the **`1`-`7` hotkeys** (per the
emote learning below).

**Engine: TWO data classes for ONE player concept.**

| Engine class | What it is | Asset weight |
|---|---|---|
| **`PMEmoteData`** | Striker-specific animated reaction (e.g. `EmoteData_Asher_Delighted` references `/Game/Prometheus/Characters/Shieldz/.../AM_ShieldUser_Default_Emote_Happy`) | Heavier — bakes in striker animation refs |
| **`PMEmoticonData`** | Lighter icon+audio reaction (texture + Wwise event; e.g. `EmoticonData_JulietteComfy`). No striker animation dependency | Lighter — works for any striker |

Both render through the same UI shell (`WBP_ReactionButton` /
`WBP_ReactionModal` / `WBP_ReactionModalItem`) and gameplay path
(`BTT_UseReactionAndWait` calls `ShowEmote` / `ShowEmoticon`).
`WBP_ReactionModal_C` is the live runtime owner of the reaction render
call — `ShowSelectedReaction` on the modal triggers a native reaction.

**Identity key.** The player's *equipped* loadout includes ONE
emoticon slot (`MeResponseV1.EmoticonId`) — see *Cosmetic loadout*
below. Whether a custom OSPlus reaction is a `PMEmoteData` or a
`PMEmoticonData` in practice is a feature-design choice (the lighter
`PMEmoticonData` is the safer first probe).

**Cross-references.**
- Player perspective: `docs/game/ux/in-match-hud.md` *(planned)* — describes the reaction wheel.
- Engine perspective: `docs/engine/widgets.md` *(planned)* — `WBP_ReactionButtonPanel_C` cluster.
- Feature: [`docs/features/unlockable-earning-emotes.md`](./features/unlockable-earning-emotes.md) (currently stashed).
- Learning: [`docs/learnings/native-reaction-showemoticon-pmemoticondata.md`](./learnings/native-reaction-showemoticon-pmemoticondata.md).

---

## Cosmetic loadout

**Player concept.** "What does my character/profile look like to
others?" — the customization slots on the player's profile.

**Engine: FOUR distinct slots — confirmed.** Per `MeResponseV1` /
`PMPlayerPublicProfile`:

| Slot | Field | Player-visible as |
|---|---|---|
| **Logo** | `LogoId` | TBD — probably a graphic shown alongside the name |
| **Nameplate** | `NameplateId` | Background plate behind player name (lobby + nameplates) |
| **Emoticon** | `EmoticonId` | One of the equipped reactions on the in-match wheel (see *Emote / Emoticon* above) |
| **Title** | `TitleId` | TBD — likely a text label shown alongside name |

The player vocabulary "cosmetics" collapses these four slots; in code
they're four distinct fields with four distinct setter/getter paths.
Whether players also have a *skin* slot for striker-skin cosmetics
(referenced by [`OMEGA_STRIKERS_GAME.md`](./game/OMEGA_STRIKERS_GAME.md)
Sec 1 as "Skin/cosmetics") is a separate question — TBD whether that's
a fifth ID on the profile or held elsewhere.

**Cross-references.**
- Player perspective: `docs/game/player-systems.md` *(planned)*.
- Engine perspective: `docs/engine/identity-and-api.md` *(planned)* — `MeResponseV1` shape.
- KNOWLEDGEBASE: [`KNOWLEDGEBASE.md`](../KNOWLEDGEBASE.md) → *Player Identity Reference* → `MeResponseV1` extends `PlayerPublicProfile` with these fields.

---

## Map / Arena

**Player concept.** The arena where a match is played. Affects
scoring routes, hazards, orb spawns, Striker viability. See
`docs/game/maps.md` *(planned)* or
[`docs/game/OMEGA_STRIKERS_GAME.md`](./game/OMEGA_STRIKERS_GAME.md)
Sec 17.

**Engine: a level asset path × game mode × visualization actors.**

- **Level asset paths — partially confirmed.**
  - `MainMenuMap` → `/Game/Prometheus/Maps/MainMenuMap/MainMenuMap` (lobby)
  - `GameMapPractice` → `/Game/Prometheus/Maps/GameMap/GameMapPractice` (practice)
  - `GameMapAhtenCity` → `/Game/Prometheus/Maps/GameMap/GameMapAhtenCity` (one online arena)
  - **Other arenas exist but are not catalogued.** Folder
    `/Game/Prometheus/Maps/GameMap/` is the right place to look.
- **Mode-locking — TBD.** Whether each map is available in all modes
  is not documented. Practice has its own dedicated map.

**Cross-references.**
- Player perspective: `docs/game/maps.md` *(planned)*.
- Engine perspective: `docs/engine/setup.md` *(planned)* — full map table.
- KNOWLEDGEBASE: [`KNOWLEDGEBASE.md`](../KNOWLEDGEBASE.md) → *Maps*.
- Open question: complete map list + per-mode availability.

---

## Goalie / Forward (role)

**Player concept.** Tactical position on a team — goalie plays near
the team's own goal, forward plays upfield. See `docs/game/roles.md`
*(planned)* or
[`docs/game/OMEGA_STRIKERS_GAME.md`](./game/OMEGA_STRIKERS_GAME.md)
Sec 8.

**Engine: NO ENGINE CLASS — purely tactical.** There is no `Role`
enum, no `IsGoalie()` UFunction, no role-tagged spawn slot. Roles
emerge from where the player chooses to position themselves and which
Striker they chose (some kits favor goalie, others forward).

**Caveat — backend tracks role anyway.** The Clarion API exposes
`character × role × gamemode` aggregates (per
[`KNOWLEDGEBASE.md`](../KNOWLEDGEBASE.md) → *Backend Ecosystem*),
which means *the backend* classifies role per match. *How* it
classifies role from in-match behavior is not documented — likely from
goal-area dwell time or final position, but TBD.

**Cross-references.**
- Player perspective: `docs/game/roles.md` *(planned)*.
- Engine perspective: no dedicated engine doc — see
  `docs/engine/identity-and-api.md` *(planned)* for the Clarion role
  field.

---

## Awakening

**Player concept.** In-match draftable upgrade. Drafted at match
start and between sets. The current-version build expression system.
See `docs/game/awakenings.md` *(planned)* or
[`docs/game/OMEGA_STRIKERS_GAME.md`](./game/OMEGA_STRIKERS_GAME.md)
Sec 15.

**Engine — TBD.** What's known:

- **Phase exists in the lifecycle.** Detection: same as active
  gameplay (`PlayerState_Game_C` + valid Pawn) — see
  [`KNOWLEDGEBASE.md`](../KNOWLEDGEBASE.md) → *Awakening Select*.
  KB labels this phase "between rounds" but the player-side authority
  ([`OMEGA_STRIKERS_GAME.md`](./game/OMEGA_STRIKERS_GAME.md) Sec 15)
  says **"between sets"** — KB is the suspected stale doc.
- **Engine class for Awakening data — TBD.** No class confirmed yet.
  Probably under `/Script/Prometheus.*` with `Awakening` in the name.
- **Draft UI widget — TBD.** Probably under the `WBP_*Awakening*`
  family.
- **Per-player drafted-Awakening list runtime location — TBD.**
  Likely on `PMPlayerState` or a sibling structure.

**Forces a probe.** Any feature touching Awakenings will hit at least
two TBDs from this entry. Plan for a Stage-3 RE pass per
[`docs/dev-cycle.md`](./dev-cycle.md).

**Cross-references.**
- Player perspective: `docs/game/awakenings.md` *(planned)*.
- Engine perspective: `docs/engine/awakenings.md` *(planned, blocked on probe)*.
- Open question: KB "between rounds" vs game-doc "between sets" — confirm and reconcile.

---

## Goal & Barrier

**Player concept.** The net you score on; protected by one or more
breakable barriers. See `docs/game/goals-and-barriers.md` *(planned)*
or [`docs/game/OMEGA_STRIKERS_GAME.md`](./game/OMEGA_STRIKERS_GAME.md)
Sec 7.

**Engine — partially known:**

- **Goal explosion VFX — confirmed.** `SpawnGoalEffects` UFunction on
  both `GameState_Game_C` and `GameState_Tutorial_C`. Folder
  `/Game/Prometheus/.../GoalScore/` contains art/VFX classes.
- **Goal-area entry per player — confirmed.**
  `PMPlayerMatchSummary.HitRockIntoGoalArea` is a per-player counter
  (matches `EPMEndOfGameStat::ShotsOnGoal`).
- **Match-phase events — confirmed.** `MatchPhaseChanged` fires on
  phase transitions including (presumably) goal scored → round reset.
- **Barrier object class — TBD.** Player-doc Sec 7 implies a distinct
  breakable object. Engine class not confirmed; candidate search
  terms: `Gate`, `Barrier`, `GoalBarrier`, `GoalArc`.
- **Barrier regeneration rules — TBD.** Per-round, per-set, never —
  unclear from existing docs.

**Cross-references.**
- Player perspective: `docs/game/goals-and-barriers.md` *(planned)*.
- Engine perspective: `docs/engine/game-state-class.md` *(planned)*.

---

## Stub entries

These player concepts have a clean (or near-clean) 1:1 engine mapping
and don't yet warrant a full glossary entry. They appear here as
anchors so future contributors know an entry could grow if ambiguity
surfaces.

- **Strike** (basic Strike) — `StrikeReleased`, `StrikeDragged`
  UFunctions on `PlayerController_Game_C`. Drag-release input (per
  UFunction names). `HoldToStrikeModeEnabledChanged` toggles a
  related input mode. Player-side: see
  [`OMEGA_STRIKERS_GAME.md`](./game/OMEGA_STRIKERS_GAME.md) Sec 11.
- **Energy / Energy Burst** — `TryResetEnergy`, `TryUnlockSpecial` on
  `PlayerState_Game_C`. Mechanic detail (button, cost, visual) TBD.
  Player-side: see
  [`OMEGA_STRIKERS_GAME.md`](./game/OMEGA_STRIKERS_GAME.md) Sec 13.
- **Power Orb** — `IncrementOrbTracking`, `ResetOrbTracking` on
  `PlayerState_Game_C`; `Set Random Power Orb` /
  `SwitchToNextPowerUp` on `GameState_Tutorial_C`;
  `PMPlayerMatchSummary.PowerUpsPickedUpCount` is the per-player
  counter. Visualization actor TBD. Player-side: see
  [`OMEGA_STRIKERS_GAME.md`](./game/OMEGA_STRIKERS_GAME.md) Sec 14.
- **Stagger / KO** — `DamageChanged` (damage tracking),
  `SpawnEffectsOnCharacterKnockedOut` (KO event) on
  `PlayerState_Game_C`. Stagger ↔ damage relationship TBD per
  [`OMEGA_STRIKERS_GAME.md`](./game/OMEGA_STRIKERS_GAME.md) Sec 12
  ambiguity.

Promote a stub into a full entry when ambiguity surfaces — for
example, if a feature reveals that `Strike` actually has multiple
engine-side variants (basic vs. ability-driven), grow `Strike` into a
full entry.

---

## When this doc lies

Glossary entries are only as accurate as the most recent probe. If you
find an entry that contradicts what the engine actually does:

1. The engine is the truth. Open the doc, fix the inaccuracy in the
   same branch as the work that exposed it.
2. If a TBD blocks your feature, do the probe (Stage 3 of
   [`docs/dev-cycle.md`](./dev-cycle.md)) and update the entry as part
   of the same branch.
3. If you find an entry contradicts a learning, update both — the
   learning typically wins on facts; the glossary entry is the
   navigable summary.

This doc is referenced from [`AGENTS.md`](../AGENTS.md) pre-work
reading.
