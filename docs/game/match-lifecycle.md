# Match lifecycle

Session-level and match-level flow: how a player gets from launching
the game to playing a match to returning to the lobby. The state
machine that every other in-match doc references.

> **Status:** seeded 2026-04-29 from
> [`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 3 + Sec 6.
> Set/round numbers (B1) and practice flow (A3) added beyond the
> source.

## Session flow (online play)

What a typical session looks like end-to-end. Each step transitions
the player to a different screen — full per-screen detail in
[`screens.md`](./screens.md).

```text
1.  Open game
2.  Startup / login (auth handshake, EULA)
3.  Land in Home Hub (default lobby)
4.  Choose mode (Ranked, Brawl, etc. — see screens.md → Modes)
5.  Queue
6.  Match found (accept prompt — TBD whether timed/auto)
7.  Striker select / draft
8.  Pick Striker, gear, cosmetics
9.  Arena loading (map streams in)
10. Versus / intro (TBD existence/shape)
11. Starting Awakening draft (pick first Awakening of the match)
12. Active gameplay starts — first set, first round
13. Play active goal rounds (score, concede, reset, repeat within a set)
14. Win or lose a set
15. Between-set Awakening draft (pick additional Awakening)
16. Repeat sets until match ends
17. Victory / defeat screen
18. Post-match stats / rewards / rank update (Ranked only)
19. Return to Home Hub — queue again, change Striker/cosmetics/mode,
    party up, inspect progression, or leave
```

**Important:** there is no full pre-match build creation step. The
player's build evolves *inside* the match through Awakenings — see
[`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 15 (until
migrated to `awakenings.md`). Pre-match choices are limited to:
mode, Striker, gear, cosmetics, party state.

## Practice flow (separate from online)

Practice has its own dedicated map (`GameMapPractice`) and GameState
(`GameState_Tutorial_C`). The flow diverges from online from step 4
onwards:

```text
1.  Open game
2.  Startup / login
3.  Land in Home Hub
4.  Choose Practice mode
5.  Training select modal (`WBP_TrainingSelectModal_C`) — pick scenario
6.  Arena loading (`GameMapPractice` instead of online arena)
7.  Active practice — no opponents (or AI opponents, depending on
    scenario), no match seed, no rank stake
8.  Exit at will (no victory/defeat condition unless scenario imposes one)
9.  Return to Home Hub
```

**Practice-specific consequences for OSPlus / engine code:**

- `GameState_Tutorial_C` is the GameState class (not
  `GameState_Game_C`). Detection logic that depends on
  `GameState_Game_C` will not see practice mode unless it falls back
  to `GameState_Tutorial_C` — see
  [`chat-match-detection-via-seed.md`](../learnings/chat-match-detection-via-seed.md)
  for the working dual-class detection pattern.
- `PlayerState.PlayerNamePrivate` returns the **hex Prometheus ID**
  rather than the display name in practice mode — see
  [`playernameprivate-transient-account-id.md`](../learnings/playernameprivate-transient-account-id.md).
- No Awakening draft phase in practice (typically).
- No post-match stats / rank update.

## Match structure (sets, rounds, goals)

A match is **not** a single continuous soccer-like game. It has
nested layers:

| Unit | What it is | Length / numbers |
|---|---|---|
| **Match** | The complete contest from arena load to victory/defeat | TBD — mode-dependent (B1) |
| **Set** | Scoring period within a match. A team wins a set by reaching the score target. | TBD per mode (best of N sets per match) |
| **Round** | Reset/face-off period within a set. A round ends with a goal scored. | First goal ends the round. |
| **Goal** | Single scoring event. Round-ending. | One goal per round. |

**Awakening drafts happen between sets, not between rounds.** This
is the version-current shape (per
[`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 15);
[`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) labels its detection
phase "Awakening Select (between rounds)" — the KB phrasing is
suspected stale (see [Awakening glossary entry](../glossary.md#awakening)
→ "open question"). Player-side authority wins.

**Numeric specifics (B1 — TBD):**
- Goals to win a set — TBD (3? 5? mode-dependent?).
- Sets to win a match — TBD (best of 3? best of 5?).
- Time limits per round / per set / per match — TBD.

These numbers almost certainly vary by mode (Ranked may use
different thresholds than Brawl). Worth interviewing.

## State machine

A useful abstract progression. Each state corresponds to either a
screen or an in-screen sub-state:

```text
GameLaunch
  → Lobby (Home Hub)
    → ModeSelect
      → Queue
        → MatchFound (accept) -------------------+
                                                 |
        +----------------------------------------+
        ↓
    StrikerSelect
        ↓
    ArenaLoading
        ↓
    VersusIntro                  (TBD: may not exist)
        ↓
    StartingAwakeningDraft
        ↓
    SetStart -------+
        ↓           |
    GoalRoundActive |
        ↓           |
    GoalScored      |
        ↓           |
    RoundReset -----+   (loop within a set)
        ↓
    SetWon          (one team reached score target)
        ↓
    AwakeningDraft  (between-set)
        ↓
    NextSetStart ---+
                    |
        (loop until match ends)
                    ↓
    MatchWon / MatchLost
        ↓
    PostMatch
        ↓
    Lobby (Home Hub) — back to start
```

## Player states (in-match)

Orthogonal to match structure — the player can be in any of these
states *during* `GoalRoundActive`:

| State | What it means | Engine signal (where known) |
|---|---|---|
| **PlayerAlive** | Pawn spawned, controllable | `PlayerController.Pawn` is valid |
| **PlayerCastingAbility** | Mid-cast on a primary/secondary/special | TBD |
| **PlayerEvading** | Mid-Evade (defensive avoidance) | TBD |
| **PlayerEnergyBursting** | Mid-Energy-Burst (high-impact reversal) | TBD; `TryUnlockSpecial` related |
| **PlayerStaggered** | Damaged enough to be vulnerable to knockback | TBD; `DamageChanged` event tracks damage |
| **PlayerKOd** | Knocked out of the arena, awaiting respawn | `SpawnEffectsOnCharacterKnockedOut` event |
| **PlayerRespawning** | Returning after KO; **briefly Pawn is nil** | `PlayerController.Pawn` momentarily nil |

The "briefly Pawn is nil during respawn" fact is load-bearing for
chat-state and any other in-match feature that gates on local-player
presence. **Use `GameState_Game_C.CurrentMatchSeed` as the canonical
"is the match still happening" signal**, not `Pawn ~= nil` — see
[`chat-match-detection-via-seed.md`](../learnings/chat-match-detection-via-seed.md).

## Core states (in-match)

Orthogonal to player state — the Core (engine name "Rock") can be
in any of these positions:

- **CoreNeutral** — center / neither team's threat zone.
- **CoreThreateningOwnGoal** — within reach of scoring on my team.
- **CoreThreateningEnemyGoal** — within reach of scoring on enemy team.

Plus goal-area states:

- **GoalBarrierUp / GoalBarrierBroken / GoalOpen** — see
  [`goals-and-barriers.md`](./goals-and-barriers.md) *(planned)* /
  [`OMEGA_STRIKERS_GAME.md`](./OMEGA_STRIKERS_GAME.md) Sec 7.

## High-pressure / endgame states

Within the match-level loop, certain milestones change urgency:

- **SetPoint** — one more goal wins the set.
- **MatchPoint** — one more goal wins the match.
- **OvertimeOrHighPressureState** — TBD whether OS has formal overtime
  or just escalating-pressure framing. Sudden death? Score cap? TBD.

## Open questions

- **A3 (partial) — Custom lobby flow.** What screens/states does the
  custom lobby flow involve? Lobby creation → settings → invite →
  ready → start? Whether it uses `GameState_Game_C` or a different
  class is TBD per [Match glossary entry](../glossary.md#match).
- **B1 — Set/round numbers.** Goals to win a set; sets to win a
  match; time limits per round/set/match. Almost certainly
  mode-dependent.
- **B7 — Versus / intro existence.** Does the "Versus / intro" step
  actually happen in current builds, or did it get dropped between
  versions? Has it ever existed?
- **Match-found accept timing.** Is there an accept/decline timer? Or
  auto-accept?
- **Engine event sequence.** What events fire in what order during
  match-state transitions? `MatchPhaseChanged` is known
  ([`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) → *Key UFunctions*)
  but the phase enum values are not documented.
- **Overtime / sudden death.** Does the match-level loop have a
  formal overtime, or just escalating pressure?
- **Disconnect / reconnect.** What happens to the lifecycle if a
  player disconnects mid-match? Surrender votes? AFK timeout?
  Replacement bots?

## Cross-references

- Engine perspective: [`docs/glossary.md → Match`](../glossary.md#match);
  [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) → *Game Lifecycle &
  Phase Detection*; planned `docs/engine/game-state.md`.
- Sibling docs: [`screens.md`](./screens.md) (per-screen detail
  for each lifecycle step), [`lobby.md`](./lobby.md) (the
  return-to-Home-Hub state), [`in-match-hud.md`](./in-match-hud.md)
  (what the player sees during `GoalRoundActive`).
- Related learnings:
  [`chat-match-detection-via-seed`](../learnings/chat-match-detection-via-seed.md)
  for the canonical match-active signal,
  [`playernameprivate-transient-account-id`](../learnings/playernameprivate-transient-account-id.md)
  for practice-mode display-name caveats.
