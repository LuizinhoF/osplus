# chat-match-detection-via-seed

| Field | Value |
|---|---|
| Date | 2026-04-04 |
| Area | mod |
| Tags | chat, match-detection, ue4ss-gamestate, replication, false-negative |
| Status | confirmed |

## Symptom

In-game chat widget vanished mid-match (around mid-round, sometimes during KO replays / round resets) and did not return until the next match started. No errors in the UE4SS log; the widget object was still alive in `GameInstance_Base_C`, just collapsed and not re-shown until the next match-start signal fired.

## Root cause

`isInMatch()` was gated on `PlayerController.Pawn ~= nil and Pawn:IsValid()`. The local Pawn is **briefly nil** during normal mid-match events — knockouts before respawn, round resets, certain awakening transitions. The chat module polls `isInMatch()` periodically (`MATCH_EXIT_CHECK_TICKS`) and treated those windows as match-end:

1. Poll catches Pawn = nil → `endMatch("pawn gone")` → widget hidden + state cleared + room left.
2. Pawn comes back ~1 frame later, but `endMatch` had already torn down state and the only re-entry path was `RegisterLoadMapPostHook` (no map load happens for a respawn) or `OnRep_MatchState` (doesn't fire for respawns either).
3. So the chat stayed gone until the actual next map load.

Pawn-based detection is fundamentally a *local-player presence* signal masquerading as a *match-is-active* signal. Those are not the same thing.

## Fix

Switched the gate to a server-replicated value: `GameState_Game_C.CurrentMatchSeed`. Non-zero ⇒ match in progress. Zero ⇒ no match. The seed is set when the match begins and stays stable for the whole match — it does not blip on KOs, respawns, awakening picks, or round resets.

Also re-armed the periodic probe inside `endMatch()` so a *real* match end recovers within ~1 second if the server starts a back-to-back match without a map transition (defense in depth, not strictly required by the seed gate).

Changes:
- `mod/OSPlus/scripts/chat.lua` — added `readMatchSeed()`, replaced `isInMatch()` body, set `matchProbeTimer = MATCH_PROBE_TICKS` at the end of `endMatch()`, changed log reason from `"pawn gone"` to `"seed gone"`.
- `mod/OSPlus/scripts/config.lua` — bumped `M.VERSION` from `v14-chat` to `v15-chat-seed-gate`.

```lua
local function readMatchSeed()
    local ok, seed = pcall(function()
        local gs = FindFirstOf("GameState_Game_C")
        if not gs or not gs:IsValid() then
            gs = FindFirstOf("GameState_Tutorial_C")
        end
        if not gs or not gs:IsValid() then return nil end
        return gs.CurrentMatchSeed
    end)
    if ok and seed and type(seed) == "number" and seed ~= 0 then
        return seed
    end
    return nil
end
```

## Lesson

For "is the match still happening" questions, **prefer server-replicated game state values over local-player presence**. Local-player state (Pawn, PlayerController flags, even PlayerState in some cases) blips during normal game events; server-replicated match identity does not.

When designing any new gate: ask "what is the *signal* I want?" before reaching for the *first* thing that correlates with it. `Pawn ~= nil` correlates with "match active" but is not the same proposition.

## Related

- Files: `mod/OSPlus/scripts/chat.lua`, `mod/OSPlus/scripts/config.lua`
- Reference: `KNOWLEDGEBASE.md` → "Game Lifecycle & Phase Detection" section. The old proven `isInMatch()` snippet there is the buggy version — flagged for `KNOWLEDGEBASE.md` cleanup in Phase 6 (migrate + split).
- Architecture: `docs/architecture/state-contract.md` — the chat module is the worked example.
