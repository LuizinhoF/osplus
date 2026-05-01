# Post-match

The screens and decisions that happen after a match ends. Closes
the [match lifecycle](./match-lifecycle.md) and routes the player
back to the [lobby](./lobby.md) (or to a re-queue).

> **Status:** seeded 2026-05-01 from
> [`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 24.
>
> **Last validated against game patch:** 2026-04. The post-match
> *flow shape* is mechanically stable; the *content* (which stats
> are surfaced, what reward types exist, season-pass progression
> details) is patch-volatile and will move with seasons. Re-validate
> when patch notes mention post-match UI, end-of-match stats, or
> reward systems.

This doc is the player-side phase description. The engine widget
that drives post-match is `WBP_PostMatch_C` and related (see
[`screens.md` → "Per-screen detail"](./screens.md#per-screen-detail));
per-match stat sources are documented in
[`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) → *Per-match runtime
data* (notably `PMPlayerMatchSummary`).

## TL;DR

- **Post-match is the closure phase.** The match is over; the
  player is making *next-action* decisions (queue again, swap
  Striker, leave, party up, inspect stats).
- **Stats are summarized, not analyzed.** The native screens show
  who did what; *interpreting* it is left to the player. This is a
  natural OSPlus extension point.
- **Frame the wrap-up flow as "queue again or change something",
  not as "edit your build".** OS does not have a pre-match build
  editor; the post-match flow doesn't pretend it does either.
- **Reward / rank / progression updates live here.** XP banners,
  rank movement, mission completions, season-pass progression. All
  patch-volatile.

## What the player wants to know here

| Information need | Why it matters |
|---|---|
| **Did we win or lose?** | The first piece of feedback. |
| **How did I perform?** | Per-player stats: KOs, assists, redirects, shots, saves, etc. |
| **Did my rank change?** | Rank update animation if Ranked mode. |
| **Did I complete missions?** | Mission tick-off, often with reward callouts. |
| **Did I earn rewards?** | Drops, currency, loot, season-pass progression. |
| **Which stats mattered?** | The screen surfaces an emphasis on certain stats (e.g., "highest redirects this match"); the player gets cues for what to feel about their performance. |
| **Do I want to queue again?** | Re-queue is a primary call-to-action button. |
| **Do I want to change Striker / cosmetics / role / party / mode?** | Any of these mid-flow without going back to the [lobby](./lobby.md). |
| **Do I want to report, add, or commend someone?** | Post-match social actions. |

## Wrap-up framing (preserve from source)

The source doc Sec 24 was explicit about how *not* to frame the
post-match wrap-up. Preserved here because it remains a common
beta-era misframing that should not creep back in:

> Do not phrase post-match flow as "change build and queue again".
>
> Better: "Queue again, change Striker / cosmetics / mode, inspect
> stats / progression, party up, or leave."

The reason: there is no pre-match build to "change." There's a
Striker, gear, and cosmetics — and an Awakening draft history that
*just happened in the match that ended*. Talking about "changing
the build" is borrowed vocabulary from games with a different
shape.

If the post-match retrospective genuinely needs build-related
framing, the source doc's preferred verbs are:

- Review **Awakening choices** (which drafts worked / didn't)
- Review **gear** choice (was it well-suited to the matchup?)
- Review **Striker fit** (was this the right pick for this map / team?)
- Review **map / team / enemy interaction** (what did the matchup
  demand that I underestimated?)

These are *retrospective* framings — looking back at what just
happened — not *prospective* framings that pretend the player is
about to "edit a build" before the next match.

## Phase context

Post-match sits at the end of the match, before the player returns
to the lobby:

```text
... → match end (victory / defeat) → post-match summary → lobby (or requeue)
```

Full state machine: [`match-lifecycle.md` → "State machine"](./match-lifecycle.md#state-machine).

The post-match phase typically runs through several distinct
sub-screens in sequence:

- **Victory / defeat splash** — the immediate outcome.
- **Per-match stats summary** — per-player breakdown.
- **Rank / progression updates** — if Ranked, the rank movement
  animation; otherwise, the season-pass / progression strip.
- **Reward callouts** — drops, currency, mission completions.
- **Wrap-up CTA** — re-queue, change something, leave.

Sub-screen ordering and per-screen widgets are documented (where
known) in [`screens.md` → "Per-screen detail"](./screens.md#per-screen-detail).

## Where the data comes from

Per-match stats surfaced in post-match are populated from per-match
runtime data on the engine side. Confirmed sources:

- **`PMPlayerMatchSummary`** — per-player aggregate counters.
  Notable fields used by post-match:
  - `RedirectRock` — per-player redirect count (the canonical OSPlus
    capture target for Core touches that mattered)
  - `HitRockIntoGoalArea` — per-player goal-area entries (matches
    `EPMEndOfGameStat::ShotsOnGoal`)
  - Combat counters (KOs inflicted/received, stagger applied, etc.)
    — confirmed cluster, specific field names **TBD; surface during
    engine doc migration**.
- **`EPMEndOfGameStat`** — enum-side categorization of which
  stats are end-of-game-summary-eligible. Names like
  `ShotsOnGoal` map to per-player counters.
- **`PMPlayerPublicProfile`** — for cross-referencing player
  identity (display name, cosmetics) on the summary screen.

Full reachability documented in
[`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) → *Per-match runtime
data*. See also [glossary → "Player identity"](../glossary.md#player-identity)
for the per-player identity bridge.

## Where OSPlus could attach

Post-match is the second-best feature surface in OSPlus (after the
[lobby](./lobby.md)) — the player has time, isn't time-pressured,
and is already in a reflective frame.

**Likely good feature shapes:**

- **Better stats summary.** Beyond the native end-of-match screen:
  trends, rolling-window stats, per-Striker performance, per-map
  performance, per-Awakening performance.
- **Awakening draft retrospective.** "You drafted X then Y then Z;
  here's how each draft performed compared to alternatives." The
  prospective version of this lives in
  [`awakenings.md` → "OSPlus framing rules"](./awakenings.md#osplus-framing-rules)
  ("Awakening draft helper") — but the *retrospective* version is
  also useful and lower-risk.
- **Highlight reels / replay extraction.** Post-match is the
  natural moment to surface key plays from the match that just
  ended (e.g., the KOs, the saves, the Awakening-key moments).
- **Performance feedback that the native game doesn't surface.**
  E.g., "your stagger uptime was lower than your last 10 matches"
  — the kind of trend signal that the native end-of-match screen
  doesn't show.
- **Post-match social hooks.** Friend invites, party formation,
  commendations integrated with OSPlus's own player-identity
  systems.

**Likely bad feature shapes:**

- A pre-next-match "build editor" framed off post-match results
  (the wrap-up framing rule above explicitly rules this out).
- Anything that delays the player from re-queuing (post-match is
  also a *transition* phase; OSPlus shouldn't make leaving harder).
- Visual noise during the rank-update animation (it's a moment of
  feedback — a feature shouldn't compete with it).
- Surfacing teammate / enemy data that crosses what the native game
  considers private (e.g., third-party performance scores attached
  to other players' display names without their consent).

## Engine bridge (one-link summary)

- **Phase widget cluster.** `WBP_PostMatch_C` and related — see
  [`screens.md` → "Per-screen detail"](./screens.md#per-screen-detail).
- **Per-match data sources.** `PMPlayerMatchSummary`,
  `EPMEndOfGameStat`, `PMPlayerPublicProfile` — see
  [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) → *Per-match runtime
  data*.
- **Phase detection / lifecycle hook.** Likely a `MatchPhaseChanged`
  signal on `GameState_Game_C` (also referenced in
  [glossary → "Goal & Barrier"](../glossary.md#goal--barrier) for
  the goal-scored fire). The post-match phase transition is the
  natural attach point for capture / extraction features. **Exact
  phase enum value TBD.**

Per ADR 0003, engine search-target lists do not live here.

## Open questions

- **Specific post-match sub-screen ordering.** Is rank update
  always before reward callouts? Always after stats summary? Per-
  mode variation? **TBD.**
- **Per-mode reward / progression rules.** Ranked vs. Brawl vs.
  Custom — what carries progression and what doesn't. **TBD;
  patch-volatile.**
- **Reportable / commendable actions.** What the post-match social
  layer exposes in the current version. **TBD.**
- **Replay data availability.** Whether OS exposes any replay /
  highlight bytestream after a match (vs. requiring the mod to
  capture state during the match). Critical for any
  highlight-reel feature. **TBD; route via engine doc when
  migrated.**
- **The combat-side per-match counter cluster.** Same TBD as
  [`combat.md`](./combat.md): KO inflicted, KO received, stagger
  applied, edge-pushes — likely on `PMPlayerMatchSummary` but
  field names are not catalogued in this docset.

## Cross-references

- Match-flow context (post-match is the lifecycle's exit phase):
  [`match-lifecycle.md`](./match-lifecycle.md)
- Out-of-match landing: [`lobby.md`](./lobby.md) — what the player
  returns to.
- Where the player's *next* match's choices get made: [`striker-select.md`](./striker-select.md).
- Build retrospective routes through: [`awakenings.md`](./awakenings.md), [`gear.md`](./gear.md), [`strikers-and-abilities.md`](./strikers-and-abilities.md), [`maps.md`](./maps.md).
- Engine data sources: [glossary → "Player identity"](../glossary.md#player-identity),
  [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) → *Per-match runtime data*.
- Sibling docs index: [`docs/game/README.md`](./README.md)
