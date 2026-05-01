# Strikers — internal names, character classes, content layout

The *"what is each Striker called in the engine and where does
their content live"* doc — read this when designing any feature
that targets a specific Striker, dumps per-Striker assets, or
needs the bridge between the player-facing roster and engine
class names. Distilled from
[`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) "Class Hierarchy
Reference → Characters" sub-section + content-folder
observations.

> **Status:** seeded 2026-05-01 from
> [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md). The 26 internal
> names + folder layout were dump-confirmed via F10. The
> internal-name → display-name mapping is **only fully
> confirmed for 3 Strikers** (Juliette, Drek'ar, plus 3 likely
> matches by folder-name = display-name); the rest of the
> roster needs per-Striker Pawn-class observation to confirm.
>
> **Stability:** Strikers ship across patches and seasons; this
> roster is a **2026-04 snapshot** and will go stale as new
> Strikers ship. Re-validate after every season patch and add
> new entries inline. The runtime *pattern*
> (`C_<InternalName>_C`) is stable across patches.

This doc is the *engine-side roster + naming bridge*. The
*player-side mechanic layer* (what a Striker is, kit structure,
playstyle clusters) lives in
[`docs/game/strikers-and-abilities.md`](../game/strikers-and-abilities.md).
The *Striker as identity / cosmetic* lives in
[`docs/glossary.md` → "Striker"](../glossary.md#striker).

## TL;DR

- **Each Striker has an `InternalName`** (e.g. `FlexibleBrawler`,
  `NimbleBlaster`). At runtime, the in-match Pawn class is
  `C_<InternalName>_C` (e.g. `C_FlexibleBrawler_C`,
  `C_NimbleBlaster_C`).
- **26 internal names catalogued** as of 2026-04. **3 confirmed**
  display-name mappings, ~3 likely-by-folder-name; the
  remaining ~20 need per-Striker observation.
- **Confirmation is cheap.** Play any Striker in practice or a
  custom match, dump `PlayerController.Pawn` class via F4 / F10,
  read off `C_<InternalName>_C`. One Striker per session closes
  one row.
- **Striker content lives under `/Game/Prometheus/Characters/<InternalName>/`.**
  The folder layout follows a consistent pattern, with a few
  utility folders that are **not** playable Strikers (see
  [§"Utility folders"](#utility-folders)).
- **Engine class for striker-select preview, lobby home-hub
  display, and cosmetic / roster screens is TBD** — likely not
  the same as the in-match Pawn class. See
  [glossary → "Striker"](../glossary.md#striker).

## Internal name → display name table

26 internal Striker names dump-confirmed via F10. Display names
confirmed only where verified. The runtime pattern is
`C_<InternalName>` → `C_<InternalName>_C` at runtime (the `_C`
suffix appears on the spawned Blueprint class).

| Internal name | Display name | Confirmation |
|---|---|---|
| `FlexibleBrawler` | Juliette | **Confirmed** — Pawn observed in practice |
| `NimbleBlaster` | Drek'ar | **Confirmed** — Pawn observed in online match |
| `Asher` | Asher | Likely (folder = display) |
| `Dubu` | Dubu | Likely (folder = display) |
| `Estelle` | Estelle | Likely (folder = display) |
| `Shieldz` | (TBD — folder is `Shieldz`) | Likely (folder = display); also referenced indirectly via `EmoteData_Asher_Delighted` referencing `/Game/Prometheus/Characters/Shieldz/.../AM_ShieldUser_Default_Emote_Happy`, which suggests `Shieldz` is the Asher-shield-user character variant — needs confirmation |
| `AngelicSupport` | (TBD) | Unconfirmed |
| `ChaoticRocketeer` | (TBD) | Unconfirmed |
| `Chibi` | (TBD) | Unconfirmed |
| `CleverSummoner` | (TBD) | Unconfirmed |
| `DrumOni` | (TBD) | Unconfirmed |
| `EDMOni` | (TBD) | Unconfirmed |
| `EmpoweringEnchanter` | (TBD) | Unconfirmed |
| `FlashySwordsman` | (TBD) | Unconfirmed |
| `GravityMage` | (TBD) | Unconfirmed |
| `Healer` | (TBD) | Unconfirmed |
| `HulkingBeast` | (TBD) | Unconfirmed |
| `MagicalPlaymaker` | (TBD) | Unconfirmed |
| `ManipulatingMastermind` | (TBD) | Unconfirmed |
| `RockOni` | (TBD) | Unconfirmed |
| `SpeedySkirmisher` | (TBD) | Unconfirmed |
| `StalwartProtector` | (TBD) | Unconfirmed |
| `TempoSniper` | (TBD) | Unconfirmed |
| `TheAstronaut` | (TBD) | Unconfirmed |
| `UmbrellaUser` | (TBD) | Unconfirmed |
| `WhipFighter` | (TBD) | Unconfirmed |

**How to confirm a row.** Play that Striker in practice or a
custom game, then in Lua:

```lua
local pc = utils.getPlayerController()
local pawn = pc and pc.Pawn
if pawn and pawn:IsValid() then
    local className = pawn:GetClass():GetFullName()
    -- → ".../C_FlexibleBrawler_C" or similar
end
```

(`F4` / `F10` Object Dumper output of the local PlayerController
gives the same info during in-match dumps; see
[`ue4ss-version-and-gotchas.md` → "The Lua API surface"](./ue4ss-version-and-gotchas.md#the-lua-api-surface).)

**Suggestion for whoever runs the closing pass.** A single
"play one match per Striker, dump pawn class, fill in row"
session closes the table. Until then, *don't* assume the
display name from the folder name — Odyssey's internal-name
pattern is descriptive (e.g. `FlexibleBrawler`, not `Juliette`),
not a transliteration of the display name.

## Content folder layout

Striker content lives under
`/Game/Prometheus/Characters/<InternalName>/`. The expected
sub-structure (per dump observations):

| Sub-folder | Contents |
|---|---|
| `Full/` | Full-body 3D model assets (in-match render). |
| `Concept/` | Concept-art assets (probably not runtime-used). |
| `Timeline/` | Animation timeline assets. |
| `X/` | Unclear — likely an Odyssey-internal grouping convention. |
| `CloseUp/` | Close-up render assets (likely for cosmetic preview / striker select). |

These sub-folders appear *inside* each Striker's folder when the
Striker has the asset type. Not every Striker has every
sub-folder.

## Utility folders

Inside `/Game/Prometheus/Characters/`, alongside the per-Striker
folders, are several utility folders that **are NOT playable
Strikers**. Don't grep them as if they were:

| Folder | What's actually in it |
|---|---|
| `Shared/` | Common abilities (e.g. `GA_Rescue`) shared across Strikers. |
| `GoalScore/` | Goal-explosion VFX assets (per [glossary → "Goal & Barrier"](../glossary.md#goal--barrier) — `SpawnGoalEffects` UFunction triggers these). |
| `GradientGoal/` | Goal-area visual effect assets (gradient overlay on the goal zone). |
| Other art / VFX folders | Various — assume "not a Striker" by default and confirm by inspecting the contents before treating as a per-Striker reference. |

If a feature greps for "all Strikers" and ends up touching one
of these folders, it's a bug. Filter by checking for the
`C_*_C` runtime pattern, not by folder presence.

## Striker as a runtime reference

The in-match Pawn is one Striker representation. Per
[glossary → "Striker"](../glossary.md#striker), there are at
least four contexts where a Striker has *some* engine
representation, and they are **not the same class**:

1. **In-match combat Pawn** — `C_<InternalName>_C`. Confirmed.
   Held by `PlayerController.Pawn` during Active Gameplay (per
   [`game-state.md` → "Phase model"](./game-state.md#phase-model)).
2. **Striker-select preview** — TBD. Likely a separate
   visualization actor inside the striker-select widget tree
   (`WBP_StrikerSelect_*`); animated 3D model + ability
   descriptions. Engine class probably *not* the combat Pawn.
3. **Lobby home-hub display** — TBD. Equipped Striker rendered
   in `WBP_HomeHub_PC_C` (specifically the
   `WBP_FitActorToRect_C` "3D character model in hub" child).
   Visualization actor class TBD.
4. **Cosmetics / roster screens** — TBD. Striker as menu item
   / card. Engine class TBD.

**Identity key — the Striker ID.** Across all these contexts,
the equipped Striker is identified by a backend ID. The exact
field name on `MeResponseV1` / `PMPlayerPublicProfile` is **not
catalogued** (`StrikerId`? `EquippedStriker`? `CurrentCharacterId`?
none of these are confirmed). See [open questions](#open-questions).

## Cross-references

- **Player-side mechanic layer (what a Striker is):** [`docs/game/strikers-and-abilities.md`](../game/strikers-and-abilities.md)
- **The Striker glossary entry (cross-context bridge):** [`docs/glossary.md` → "Striker"](../glossary.md#striker)
- **Match phase model (when does the Pawn exist):** [`game-state.md` → "Phase model"](./game-state.md#phase-model)
- **Per-player engine surface:** [`player-state.md`](./player-state.md)
- **Identity / backend profile / cosmetic loadout:** [`identity-and-api.md` → "The local-identity surface"](./identity-and-api.md#the-local-identity-surface), [`docs/glossary.md` → "Cosmetic loadout"](../glossary.md#cosmetic-loadout)
- **Striker select screen (player-side):** [`docs/game/striker-select.md`](../game/striker-select.md)
- **Sibling docs index:** [`docs/engine/README.md`](./README.md)

## Open questions

- **Display name for ~20 of the 26 catalogued internal names.**
  Closing the roster table is the most-actionable open work on
  this surface — one Striker per practice session.
- **Striker-select preview class.** Is it the combat
  `C_<InternalName>_C` reused, or a separate preview-only
  actor / widget? Affects feature design for
  Striker-customization features.
- **Lobby home-hub display class.** Same question.
- **The equipped-Striker ID field on the local profile.** Where
  on `MeResponseV1` / `PMPlayerPublicProfile` does the
  currently-equipped Striker get represented? Without this,
  no profile-binding feature can read "what Striker did this
  player just play."
- **Striker skin slot.** Is striker-skin cosmetics a 5th field
  on `PMPlayerPublicProfile` (alongside `LogoId` / `NameplateId`
  / `EmoticonId` / `TitleId` per
  [glossary → "Cosmetic loadout"](../glossary.md#cosmetic-loadout)),
  or held elsewhere?
- **Per-Striker mastery progression structure.** The Clarion API
  exposes per-character × role × gamemode aggregates (see
  [`identity-and-api.md` → "What the backend exposes"](./identity-and-api.md#what-the-backend-exposes));
  whether the runtime client carries a per-Striker mastery
  cache locally, or always queries the backend, is open.
