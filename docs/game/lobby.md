# Lobby UX

The Home Hub (`WBP_HomeHub_PC_C` per
[`docs/glossary.md`](../glossary.md)) is the default screen the
player returns to between matches. Everything non-match originates
here: queueing, party formation, customization, social interaction,
progression review.

> **Status:** seeded 2026-04-29 from
> [`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 19 +
> `KNOWLEDGEBASE.md` widget hierarchy. Some fields TBD pending
> observation.

## What the player wants here

In the lobby, the player is asking:

- **Mode.** What modes can I play right now? (Some may be locked,
  event-gated, or party-size restricted.)
- **Party.** Am I in a party? Who's in it? Are they ready?
- **Social.** Who's online? Any DMs? Friend requests?
- **Rank.** Where do I sit competitively (Ranked mode only)? Did my
  recent matches move me?
- **Progression.** What missions are active? What rewards are close?
  Daily login claimed?
- **Customization.** Can I change my Striker / cosmetics / loadout
  before queueing?
- **Friction.** Can I queue quickly without navigating five menus?
- **Events.** Any announcements, tournaments, limited-time content?

The lobby's job is to answer these with minimum click count.

## What's on screen

Per F3 widget dump of `WBP_HomeHub_PC_C` (in
[`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) → *UI Widget Tree*), the
home hub has these direct children:

| Child widget | Player-facing role |
|---|---|
| `WBP_FitActorToRect_C` | Centered 3D character model — the player's equipped Striker, animated/posed |
| `PlayerNameplateCenter` (`WBP_HomeHubGroupNameplate_C`) | Self nameplate (display name + rank + cosmetics) |
| `GroupMemberNameplateLeft` / `GroupMemberNameplateRight` (`WBP_HomeHubGroupNameplate_C`) | Party-member nameplates — left/right of self |
| `WBP_ReactionButtonPanel_C` | Equipped emote/reaction loadout — see [glossary → Emote / Emoticon](../glossary.md#emote--emoticon) |
| `PlayPanel` (`WBP_PlayPanel_C`) | The queue / play button surface |
| `WBP_GroupInvitePanel_C` | Party invite list (incoming) |
| `WBP_GameVersion_C` | Build version display |
| `TournamentAnnouncement` (`WBP_TournamentAnnouncement_C`) | Active tournament / event announcement |

Modal overlays that can open from the lobby — store, social, daily
login, settings, etc. — are catalogued in
[`screens.md`](./screens.md) → *Modals / overlays*.

## Cosmetic loadout — what the player customizes

Per [glossary → Cosmetic loadout](../glossary.md#cosmetic-loadout),
the loadout has **four distinct slots** plus the equipped Striker
itself:

| Slot | Player-facing as | Engine field on profile |
|---|---|---|
| **Striker** | The character you'll play (basic Strike + 3 abilities) | TBD identity field on `MeResponseV1` |
| **Logo** | TBD — likely a graphic shown alongside name | `LogoId` |
| **Nameplate** | Background plate behind player name (lobby + nameplates) | `NameplateId` |
| **Emoticon** | One of the equipped reactions on the in-match wheel (see [in-match-hud.md](./in-match-hud.md)) | `EmoticonId` |
| **Title** | TBD — likely a text label shown alongside name | `TitleId` |

Plus possibly **skin** (referenced as "Skin/cosmetics" in
[`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 1) — TBD
whether that's a fifth ID on the profile or held elsewhere.

**Cosmetic access flow — confirmed 2026-05-02 (partial).** From the
home hub a single "Customize" entry point opens
`WBP_Menu_Striker_C` (per [`docs/engine/widgets.md` → "Customization
screen"](../../docs/engine/widgets.md#customization-screen-home-hub--customize)),
a per-Striker page with top-level tabs Affinity / Overview /
Cosmetics. The Cosmetics tab body (`WBP_Panel_StrikerCosmetics_C`)
hosts a `UWidgetSwitcher` sub-tab cluster — Skins / **Emote** / Goal
Explosion — backing onto a 7-slot equipped row
(`DropTile1..DropTile7`) plus a selectable grid. The
`WBP_ReactionButtonPanel_C` child of the home hub itself is the
*display* of the equipped emote row, not the configuration surface.

## Profile view

The native game's profile-view UI — own profile, friend's profile —
is **TBD**. Section 25 of
[`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) lists "Friends /
party" but doesn't enumerate a profile-view screen. Whether
profile-view is:

- A modal over the home hub (probably attached to clicking own
  nameplate or a friend's name in the social modal),
- A new top-level screen,
- Inline panels in the social modal, or
- Doesn't exist as a distinct surface at all (in which case OSPlus's
  planned *In-game profile visible surface* feature would create the
  first one)

is an open question. **C5 from the OMEGA_STRIKERS_GAME.md review.**
Resolving it informs where the OSPlus profile feature attaches.

## Rank / progression display

Section 19 of the source asks "what is my rank?" but the screen
inventory (Sec 25) lists "Rank update" and "Rewards / progression"
as separate post-match screens, not as lobby-resident displays. So:

- **In the lobby**, the player's *current* rank is probably visible
  on their nameplate or in a top-bar account widget — but the *rank
  change* visualization is a post-match-only flow.
- The same is plausibly true for XP / mission progress — current
  state visible from the lobby, but the *gain* event is a post-match
  surface.

Whether the lobby has a dedicated "missions panel" / "battle pass
panel" / "season progress panel" or whether progression review is
strictly post-match is **TBD** (C6 from the review).

## Where OSPlus attaches

The lobby is the highest-traffic surface for any OSPlus feature
that's not strictly in-match:

- **OSPlus chat** (`WBP_ModChat_C`) lives at GameInstance scope so
  it appears in the lobby (and persists into matches). Visible
  primarily here.
- **Profile feature** (Roadmap Next) — when the OSPlus *In-game
  profile visible surface* lands, the home hub is the most likely
  attachment point (modal over hub or a new panel within it).
- **Unlockable-earning emotes** (Roadmap Now, currently stashed) —
  the loadout configuration step uses the existing
  `WBP_ReactionButtonPanel_C` surface in the home hub; the in-match
  rendering uses the reaction wheel covered in
  [in-match-hud.md](./in-match-hud.md).

## Match / network state at this point

- **No match active.** `GameState_Game_C` does NOT exist;
  `GameStateBase` is the engine base class.
- **Controller.** `PlayerController_Menu_C` is the active controller.
- **Pawn.** None.
- **Identity.** `PMIdentitySubsystem` is reachable (SteamID,
  Prometheus ID via `GetAuthenticatedPlayerId`).
- **Display name caveat.** `PlayerState.PlayerNamePrivate` is the
  engine base class (no `PlayerState_Game_C`). Display name out of
  match has gone through the *machine name* mode — see
  [`playernameprivate-machine-name-out-of-match`](../learnings/playernameprivate-machine-name-out-of-match.md).

## Open questions

Items deliberately left unresolved during this migration:

- **A4 (partial) — Skin slot.** Is "Skin/cosmetics" a fifth ID on
  `MeResponseV1` or held elsewhere?
- ~~**A4 (partial) — Cosmetic access flow.** Does the player
  customize via a single "customize" button → multi-tab modal, or
  per-slot shortcuts on the home hub itself, or both?~~ **Closed
  2026-05-02** — single "Customize" entry → `WBP_Menu_Striker_C`
  page with Affinity / Overview / Cosmetics tabs, Cosmetics
  containing Skins / Emote / Goal Explosion sub-tabs via
  `CosmeticsPanelSwitcher`. Logo / Nameplate / Title slot access
  remains uncatalogued (likely a separate `WBP_Menu_Account_C`-style
  page; not probed).
- **C5 — Profile view UI.** Where does the native game show profile
  detail (own / others)? Or doesn't it?
- **C6 — Lobby progression display.** Are missions / battle pass /
  season progress visible in the lobby itself, or strictly
  post-match?
- **Top bar contents.** What does the persistent top-bar account
  widget (rank icon, XP, currency) actually contain? Per-element
  inventory TBD.
- **Friend list visibility.** Is the social modal the only friend-list
  surface, or is there always-visible online-friends presence in the
  hub?

## Cross-references

- Engine perspective: [`docs/engine/widgets.md`](../engine/widgets.md)
  — `WBP_HomeHub_PC_C` cluster, customization screen widget tree.
- Glossary: [Cosmetic loadout](../glossary.md#cosmetic-loadout),
  [Player identity](../glossary.md#player-identity),
  [Striker](../glossary.md#striker).
- Sibling docs: [`screens.md`](./screens.md) (full screen inventory),
  [`in-match-hud.md`](./in-match-hud.md) (where reactions render
  in-match), [`match-lifecycle.md`](./match-lifecycle.md) (where the
  hub fits in the session flow).
- Related learnings:
  [`playernameprivate-machine-name-out-of-match`](../learnings/playernameprivate-machine-name-out-of-match.md)
  for display-name caveats out of match.
