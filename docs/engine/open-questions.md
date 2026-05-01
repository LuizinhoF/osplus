# Open questions — engine RE TODO catalog

The cross-cutting "what we don't yet know about the engine"
catalog. Each per-topic engine doc has its own *Open questions*
section listing TBDs scoped to that topic; **this file is the
landing page for the topics that are bigger than one doc, plus
the "we just haven't probed yet" buckets that don't naturally
slot into a topic file.**

Distilled from [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md)
"Known Unknowns / Investigation Needed" section, refactored to
the new `docs/engine/` substrate. RESOLVED items from the KB
list are preserved with a one-line note pointing at where they
landed; all currently-open items were re-categorized by the
topic doc most likely to absorb the answer when probed.

> **Status:** seeded 2026-05-01. Items added here over time
> should follow the rule **"if it slots cleanly into one of the
> per-topic docs, add it there instead — only land here when
> the question is cross-cutting or when no topic doc owns it
> yet."**
>
> **Stability:** this is a working list, not a stable reference.
> Items move out (when probed) and in (as new gaps surface)
> continuously. Don't link to specific items from other docs —
> link to the relevant per-topic doc's *Open questions* section
> instead.

## How to use this doc

- **Picking up RE work?** Skim the table of contents below and
  pick a question that gates a feature you care about.
- **Adding a new question?** First check whether the question
  belongs in a per-topic doc's *Open questions* section — most
  do. Only add here if the answer would inform multiple per-topic
  docs or if no topic owns it yet.
- **Closing a question?** Move the answer into the appropriate
  per-topic doc, mark this entry RESOLVED with a one-line link.

## Table of contents

- [Game state, lifecycle, and routing](#game-state-lifecycle-and-routing)
- [UI and the game's own widgets](#ui-and-the-games-own-widgets)
- [Networking and player data](#networking-and-player-data)
- [Audio](#audio)
- [Input](#input)
- [Resolved (kept for reference)](#resolved-kept-for-reference)

## Game state, lifecycle, and routing

These are open at the engine layer; many also appear in the
*Open questions* section of a per-topic doc with more depth.
Cross-references inline.

- **Full list of arena maps.** Only `GameMapAhtenCity` is
  confirmed for online play. The folder
  `/Game/Prometheus/Maps/GameMap/` is the right place to look,
  but a complete enumeration (online vs practice vs custom
  availability) is missing.
  See also: [`setup.md` → "Maps"](./setup.md#maps).
- **Game phase transitions — `MatchPhaseChanged` enum values.**
  The UFunction fires reliably at every phase transition; the
  argument's actual phase enum value is **not catalogued**.
  Probing the param shape inside a `RegisterHook` callback
  closes this. High-value because every match-phase feature
  currently has to use class-tuple detection.
  See also: [`game-state.md` → "Open questions"](./game-state.md#open-questions).
- **What triggers map loads.** Is there a `MatchManager` or
  similar coordinator? KB flagged this; still unanswered.
  Affects any feature that wants to react to a *deliberate*
  map-load (vs the engine-level `LoadMapPostHook` which fires
  for any map change).
- **`GameState_Game_C` readable properties.** UFunctions are
  enumerated in [`game-state.md`](./game-state.md); the
  *property fields* (round number, score, team data, match
  timer) have **not been probed.** Capturing live match score
  needs this.
- **Awakening Select phase boundary.** Per
  [glossary → Awakening](../glossary.md#awakening), the engine
  surface for awakenings is **blocked on probe.** The KB called
  this phase "between rounds"; the player-side canonical
  doc calls it "between sets" (drafts at match start AND between
  sets). Engine-side reconciliation requires probing
  `MatchPhaseChanged` argument values + finding the
  Awakening-specific UFunction (if any).
- **Post-match phase class-tuple shape.** What classes are live
  during the post-match results screen? Affects any feature
  that wants to surface during/after the match-end moment but
  not during the next match. (Player-side perception in
  [`docs/game/post-match.md`](../game/post-match.md).)
- **Match-end capture path.** Does `MatchSummary` fire pre-EOG
  or post-EOG? Does it carry the per-match data, or just signal
  that the data is ready elsewhere? Critical for any post-match
  capture feature.

## UI and the game's own widgets

- **`Router_OutOfGame_C` — how does it manage screen transitions?**
  This is the screens-router for everything outside of an
  active match. Hooking into it would enable feature work that
  needs lobby/menu phase awareness (toggling a panel based on
  current screen, surfacing OSPlus state in the right context,
  etc.). Not yet probed.
  See also: [`widgets.md`](./widgets.md).
- **Game's existing notification / toast system.** Can we
  piggyback on it? OSPlus currently has no native notification
  surface; if the game exposes one, we should use it for
  consistency rather than rendering our own. Not yet probed.
- **In-match widget tree.** The menu widget tree was captured
  via F3 dump (see [`widgets.md` → "Persistent widgets"](./widgets.md#persistent-widgets-parented-to-gameinstance_base_c));
  the in-match equivalent has not been captured. An F3 dump
  during active gameplay closes this.

## Networking and player data

- **Match ID / room ID / lobby ID.** Does the game expose any
  identifier we can read for the current match / lobby? Today
  OSPlus chat derives a room code from the
  `GameState_Game_C.CurrentMatchSeed` field (per
  [`docs/learnings/chat-match-detection-via-seed.md`](../learnings/chat-match-detection-via-seed.md))
  — that's a content-derived seed, not a true match ID. A real
  ID would be useful for things like cross-tracker matchmaking,
  party-invite-by-link, etc.
- **Can we read other players' PlayerStates?** The most
  important open question on the per-player surface. F4 dump
  only found 1 `PlayerState_Game_C` per phase; might need
  `FindAllOf` to enumerate all 6 in an online match. Gates any
  feature that wants to observe opponents' damage / KO /
  orb-pickup events.
  See also: [`player-state.md` → "Local vs remote players"](./player-state.md#local-vs-remote-players).
- **`TeamId` field shape.** `TeamId` exists on `PlayerState`
  but returns a UObject (not a primitive). Needs a deeper
  probe to determine the team-membership data shape.
- **`PMPlayerPublicProfile` cache update semantics.** When new
  players are observed (joining a lobby, queuing into a match),
  do they get appended to the cache? Is there a flush event?
  Catalogued at one moment in time; the dynamics are open.
  See also: [`identity-and-api.md` → "Open questions"](./identity-and-api.md#open-questions).

## Audio

- **Game's sound classes / sound mixes.** Can we play custom
  sounds without conflicting with the game's own audio mix?
  Today the chat feature emits no sound; the abandoned ping
  prototype used `PlaySound2D` directly. If a future feature
  needs distinctive audio, knowing how the game's audio
  routing works is a precondition.
- **Volume control.** Does the game's audio settings UI affect
  our custom `PlaySound2D` calls, or do we render past the
  user's volume preferences? **Not respecting volume settings
  is a hostile-mod posture** — would need to be solved before
  any audio-emitting feature ships.

## Input

- **Full list of game keybinds.** Knowing what bindings the
  game uses lets us avoid keybind conflicts in OSPlus features.
  Currently we use `Enter` (chat send) and `Esc` (chat dismiss);
  both happen to align with what the game uses *because* the
  intent overlaps, but we have no documented map of safe-to-use
  vs reserved keys.
- **Enhanced Input vs legacy.** Does the game use Enhanced Input
  or the legacy input system? Affects how we'd register a new
  binding from a feature module — Enhanced Input requires
  IA + IMC assets cooked into a pak; legacy input takes
  RegisterKeyBind / Lua-side keybinds.
- **Mouse position in world space.** Can we read mouse-to-world
  position without doing a line trace? Some features (e.g. the
  abandoned ping wheel) need a world-space cursor target
  without the cost of a per-tick trace.

## Resolved (kept for reference)

Items previously open in the KB that have since been answered
or migrated. Kept in this doc so a search lands on the resolved
status rather than thinking the question is still open.

| Question | Resolution | Lives at |
|---|---|---|
| All character internal names | 26 catalogued; 3 confirmed display-name mappings | [`strikers.md`](./strikers.md) |
| What widgets does the game's own HUD use? | Full menu widget tree captured via F3 | [`widgets.md` → "Persistent widgets"](./widgets.md#persistent-widgets-parented-to-gameinstance_base_c) |
| How does the game's DM/chat popup work? | `WBP_FriendChatModal_C:MessagesScrollBox` confirmed | [`widgets.md` → "ScrollBox usage in OS's own UI"](./widgets.md#scrollbox-usage-in-oss-own-ui) |
| Can we read the player's display name? | `PlayerState_Game_C.PlayerNamePrivate:ToString()` works in custom/real games (3-mode caveats apply) | [`identity-and-api.md` → "PlayerNamePrivate has three modes"](./identity-and-api.md#playernameprivate-has-three-modes) |
| Player Identity Reference (whole sub-section) | Three-namespace model + reachability matrix migrated | [`identity-and-api.md`](./identity-and-api.md) |
| ScrollBox crash root cause | `CanUseUnversionedPropertySerialization=False` in DefaultEngine.ini | [`widgets.md` → "ScrollBox crash — root cause"](./widgets.md#scrollbox-crash--root-cause), [`setup.md` → "DefaultEngine.ini"](./setup.md#defaultengineini) |

## Cross-references

- **Sibling docs (each has its own Open questions):**
  - [`overview.md`](./overview.md), [`setup.md`](./setup.md),
    [`ue4ss-version-and-gotchas.md`](./ue4ss-version-and-gotchas.md),
    [`widgets.md`](./widgets.md), [`game-state.md`](./game-state.md),
    [`player-state.md`](./player-state.md),
    [`identity-and-api.md`](./identity-and-api.md),
    [`data-model.md`](./data-model.md),
    [`rock-and-strike.md`](./rock-and-strike.md),
    [`strikers.md`](./strikers.md)
- **Glossary entries with TBDs:** [`docs/glossary.md`](../glossary.md)
- **Player-side feature paper trails (often surface engine TBDs):** [`docs/features/`](../features/)
- **Sibling docs index:** [`docs/engine/README.md`](./README.md)
