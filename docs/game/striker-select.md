# Striker select

The pre-match phase between matchmaking and arena loading. Players
choose their Striker, gear, and cosmetics for the match. Often
called *the draft phase* even though most of the *build* drafting
actually happens later, inside the match
([`awakenings.md`](./awakenings.md)).

> **Status:** seeded 2026-05-01 from
> [`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 20.
>
> **Last validated against game patch:** 2026-04. The phase exists
> stably across modes; the per-mode details (whether bans are shown,
> whether enemy picks are visible, time-on-clock per pick step) are
> mode-volatile and TBD on the per-mode matrix. Re-validate when
> mode availability changes or the Striker-select UI receives a
> visual overhaul.

This doc is the player-side phase description. The engine widget
that drives this phase is `WBP_StrikerSelect_ChoosePhases_C` (see
[`screens.md` → "Per-screen detail"](./screens.md#per-screen-detail)
for the broader screen inventory).

## TL;DR

- **Striker select happens after matchmaking, before arena
  loading.** It's the first *match-bound* screen (unlike the
  out-of-match [lobby](./lobby.md)).
- **Three pre-match commitments are made here:** Striker (which
  character), gear (passive role/style tuning), cosmetics (the
  loadout from the lobby — see
  [glossary → "Cosmetic loadout"](../glossary.md#cosmetic-loadout)).
- **It is NOT a full build editor.** The actual build evolves
  in-match through Awakening drafts. Treating Striker select as a
  pre-match build screen is the beta-era model the game
  deliberately moved away from. (See [`awakenings.md` → "OSPlus framing rules"](./awakenings.md#osplus-framing-rules).)
- **Time-pressured.** A countdown gates the phase; defaults apply
  if the player doesn't choose.

## What the player wants to know here

| Information need | Why it matters |
|---|---|
| **What role am I playing?** | Drives Striker choice (some kits are goalie-favored, some forward-favored). |
| **What map are we on?** | Drives Striker + gear viability. Some Strikers are stronger on specific arenas. |
| **What has my team picked?** | Coordination — three forwards is rarely as good as a forward + flex + goalie. |
| **What has the enemy picked, if visible?** | Counter-picking, if enemy picks are revealed in the current mode. **TBD whether all modes reveal enemy picks.** |
| **Are there bans?** | Some competitive modes feature ban phases. **TBD per-mode.** |
| **Which Strikers are available to me?** | Owned + currently-rotated-free Strikers. |
| **Which Striker should I pick?** | Synthesis of the above. |
| **Which gear should I use?** | See [`gear.md`](./gear.md) — passive tuning aligned with role/Striker. |
| **What cosmetics are selected?** | The loadout from the lobby is carried over (Logo, Nameplate, Emoticon, Title); confirmable here. |
| **How much time do I have?** | The phase is on a clock; running it out applies defaults. |

## Current-version warning (preserve verbatim from source)

The source doc opened Sec 20 with a deliberate warning. Preserved
because it remains the most common misconception about this phase:

> **Do not add assumptions about full pre-match builds here.
> Striker select is not a full build editor in the current official
> format.**

Concretely, this means:

- No "build" gets locked in here that resembles, e.g., LoL rune
  pages or DOTA 2 item builds. The player picks Striker + gear +
  cosmetics — and that's it.
- The first **build commitment** of the match happens *after*
  arena loading, with the [Starting Awakening pick](./awakenings.md#1-starting-awakening-match-start).
- Any OSPlus feature that tries to "save a build for next match"
  needs to grapple with what "build" even means in OS — gear and
  cosmetics persist between matches, but Awakening choices do not.
  See [`awakenings.md` → "OSPlus framing rules"](./awakenings.md#osplus-framing-rules).

## Phase context

Striker select sits between matchmaking and active gameplay:

```text
matchmaking → Striker select → arena loading → starting Awakening pick → active play
```

(Full state machine in
[`match-lifecycle.md` → "State machine"](./match-lifecycle.md#state-machine).)

Mode-specific detail:

- **Online matches (Ranked / Brawl).** Standard Striker select
  with team awareness; enemy-pick visibility and ban rules **TBD per
  mode**.
- **Practice mode.** Striker is selected via a different flow
  (training-select screen rather than competitive Striker-select).
  See [`screens.md` → "Practice flow"](./screens.md#per-screen-detail).
- **Custom lobby.** Striker select is run by lobby rules; **TBD
  whether it reuses `WBP_StrikerSelect_ChoosePhases_C` or a custom
  lobby variant.**

## Where OSPlus could attach

Striker select is one of the higher-leverage feature surfaces in
OSPlus because it sits in a natural decision moment with reasonably
low cognitive load (compared to in-match):

**Likely good feature shapes:**

- **Striker matchup notes.** "You're picking Drek'ar against
  Atlas; here's what's worth remembering about that matchup." Pure
  information surfacing; doesn't pick for the player.
- **Map-specific Striker tips.** Cross-references the map (when
  available) with Striker viability on it.
- **Cosmetic loadout previews.** Confirms the carried-over loadout
  from [lobby](./lobby.md#cosmetic-loadout--what-the-player-customizes).
- **Pick-tracking helpers.** "You've played Drek'ar 12 of last 20
  matches" — the kind of self-awareness data the native game
  doesn't surface here.

**Likely bad feature shapes:**

- A full pre-match build editor (the deliberate anti-goal — see
  warning above).
- Auto-pick / auto-ban features that take agency away.
- Cosmetic *selection* here (cosmetics are picked in the lobby and
  carried over; selecting them here would duplicate UI for no
  reason).
- Anything visually crowded — the native screen is already
  information-dense (Striker grid, team panels, time clock).

## Engine bridge (one-link summary)

- **Phase widget.** `WBP_StrikerSelect_ChoosePhases_C` — confirmed
  in [`screens.md` → "Per-screen detail"](./screens.md#per-screen-detail).
- **Phase detection.** Likely a `GameState_Game_C` phase value;
  per-phase enum membership not catalogued in this docset. **TBD**;
  follow [`match-lifecycle.md` → "State machine"](./match-lifecycle.md#state-machine)
  into [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) → *Game
  Lifecycle & Phase Detection* when migrated to `docs/engine/`.
- **Per-pick UFunctions / events.** The "I picked X Striker" event
  almost certainly fires on a confirm-pick handler;
  `WBP_StrikerSelect_ChoosePhases_C` is the place to look. Not yet
  catalogued. **TBD.**

Per ADR 0003, engine search-target lists do not live in this
player-side doc.

## Open questions

- **Per-mode visibility rules.** Are enemy picks visible in Ranked
  but not Brawl? In Custom but not matchmaking? **TBD per-mode
  matrix.**
- **Ban phase mechanics.** Some competitive modes have a ban step.
  Whether the current official version exposes bans, in which
  modes, with what timing — **TBD.**
- **Default-pick behavior.** What gets selected when the player
  runs out the clock? Last-played Striker? Random? Lock-in to the
  hovered Striker? **TBD.**
- **Re-pick / swap rules.** Can a player swap Strikers after locking
  in (within the phase)? Can the team swap roles after seeing the
  enemy comp? **TBD; observable from a test match.**
- **Practice-mode Striker-select flow.** A different widget likely
  drives the practice training-select screen. Confirmed widget name
  TBD.
- **Custom-lobby Striker-select flow.** Whether custom lobbies use
  the matchmaking widget or a custom variant. **TBD.**

## Cross-references

- Out-of-match equivalent: [`lobby.md`](./lobby.md) — the lobby is
  where cosmetics are *picked*; Striker select is where the
  cosmetics carrying over are *confirmed*.
- The actual build moment: [`awakenings.md` → "Starting Awakening (match start)"](./awakenings.md#1-starting-awakening-match-start)
- Pre-match commitments documented elsewhere: [`gear.md`](./gear.md)
- Engine widget catalog: [`screens.md` → "Per-screen detail"](./screens.md#per-screen-detail)
- Cosmetics carried over: [glossary → "Cosmetic loadout"](../glossary.md#cosmetic-loadout)
- Match-flow context: [`match-lifecycle.md` → "State machine"](./match-lifecycle.md#state-machine)
- Sibling docs index: [`docs/game/README.md`](./README.md)
