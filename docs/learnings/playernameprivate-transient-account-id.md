# playernameprivate-transient-account-id

| Field | Value |
|---|---|
| Date | 2026-04-19 |
| Area | mod |
| Tags | chat, player-identity, ue4ss, playerstate, replication-timing |
| Status | confirmed |

## Symptom

Chat sender labels and presence list entries displayed a 20-character lowercase hex string (e.g. `632680c154686dedd652`) instead of the friendly username (e.g. `Ispicas`). Initially assumed to be a practice-mode artifact; reproduced in matchmaking too. The same player name resolver code returned the friendly name on a fresh launch and the account ID on a different launch — same field, different value.

A subtler manifestation of the same race surfaced after the first round of fixes: the chat history showed the friendly name (because a per-call resolver retrieves it at message-send time, after replication has finished) while the presence list still showed the account ID (because the relay caches `ws._username` from the JOIN frame and uses it for every subsequent presence broadcast — the JOIN happens earlier, ~3s after match start, while replication is still in flight). Two views of "the local player's name" disagreed, depending on which side cached the early value.

## Root cause

`PlayerState.PlayerNamePrivate` on Omega Strikers' `APMPlayerState` (or whatever subclass replicates it) holds **two different things at different times**:

1. **Before the player profile finishes replicating** (early in map load, brief window): the raw account ID — a lowercase hex string, observed at both 20 and 24 characters depending on account vintage.
2. **After replication completes** (which is most of the time the chat actually queries it): the friendly display name — `Ispicas`, `Lnk3x`, `王TDAH王`, etc.

The first chat resolver cached the first value it saw. If `resolvePlayerName()` happened to fire during the brief pre-replication window — which is plausible because the chat's room-derivation path tries to join the room as soon as the match seed and team become available — it would lock in the account ID and reuse it for every subsequent message and presence broadcast for the rest of the session.

## Why the obvious fallback (`PMPlayerPublicProfile` lookup) doesn't help

UE exposes `PMPlayerPublicProfile` instances via `FindAllOf` — one per known player. Each holds a `PlayerPublicProfile` struct with both `PlayerId` (matches the account ID) and `Username` (the friendly name). It would be natural to resolve the local player by walking `FindAllOf("PMPlayerPublicProfile")` and matching `PlayerId == localId`.

This works for *other* players (whose profiles are cached because they were recently in a match with you). It almost never works for the *local* player — running the diagnostic dump from a real lobby returned 109 profile instances, none of which matched the local account ID. The local player's profile lives somewhere else (likely `PMLocalPlayer` or a similar local-only object that isn't a `PMPlayerPublicProfile`).

So the `PMPlayerPublicProfile` lookup is a defensive fallback — kept because it's cheap and might pay off in some edge case — but it isn't the primary fix.

## Fix

Three changes in `mod/OSPlus/scripts/chat.lua`. Each addresses a different layer of the race; all three are needed.

**1. `resolvePlayerName()` — don't cache values that look like account IDs.** Heuristic: pure lowercase hex, ≥20 chars. If `PlayerNamePrivate` looks like an ID, return it without caching, so the next call (which happens on the next chat send, presence update, or match start) gets a fresh look at the field. By the time the user has actually typed and sent a message, replication has invariably finished.

```lua
local function looksLikeAccountId(s)
    return type(s) == "string" and #s >= 20 and s:match("^[0-9a-f]+$") ~= nil
end

local function resolvePlayerName()
    if cachedPlayerName then return cachedPlayerName end
    local localId = getLocalAccountId()
    if not localId then return nil end
    if not looksLikeAccountId(localId) then
        cachedPlayerName = localId  -- already friendly, lock it in
        return localId
    end
    -- ... slow-path PMPlayerPublicProfile lookup, then return localId without caching ...
end
```

This alone fixes the chat-history sender label (resolver re-runs at send time and gets the friendly name).

**2. `tryJoinRoom()` — defer the relay JOIN until the friendly name is cached.** This is the second-order fix. The relay caches `ws._username` from the JOIN frame and uses it for every subsequent presence broadcast — so even if our per-call resolver becomes correct later, anything that the relay has already cached is wrong forever for that connection. The fix is to refuse to JOIN until `cachedPlayerName` is set:

```lua
local function tryJoinRoom()
    local code = M.deriveRoomCode()
    resolvePlayerName()  -- populate cache if friendly name is ready
    local missing = (not code and "team") or (not cachedPlayerName and "friendly name") or nil
    if missing and roomRetries < ROOM_MAX_RETRIES then
        roomRetries = roomRetries + 1
        log.log("[CHAT] " .. missing .. " not available yet, retry " .. roomRetries .. "/" .. ROOM_MAX_RETRIES)
        M.roomDelayTicks = ROOM_RETRY_TICKS
        return
    end
    -- ... fallthrough joins with cachedPlayerName or last-resort fallback ...
end
```

`ROOM_MAX_RETRIES` was bumped from 10 (~10s) to 20 (~20s) so the budget outlasts profile replication in slower cases.

**3. Diagnostic dump gated to `cfg.DEBUG`.** The 109-line `PMPlayerPublicProfile` dump was useful for figuring out where the friendly name actually lives, but in production it fires on every match start where the local profile isn't in the cache (which is almost every match start, since the local player isn't a `PMPlayerPublicProfile` entry — see next section). Now opt-in only.

Bumped `M.VERSION` to `v22-name-resolver-fast-path`, then `v23-defer-room-join-on-name` after fix #2 was added.

## Lesson

For any UE replicated property whose value depends on cross-network state, **assume the first read can be a placeholder**. Don't cache the first value blindly. Either:

- Validate it against a domain-specific shape check before caching (the approach here — friendly names don't look like hex IDs), or
- Cache only after a known-stable lifecycle event (e.g. the player has spawned a Pawn, or the lobby's `BeginPlay` has fired), or
- Don't cache at all if the per-call cost is trivial.

The same shape will recur for any other identity-ish field that gets initialized to a default and later replaced (`AccountId`, `DisplayName`, `Region`, etc.). The diagnostic dump pattern (one-shot, gated to DEBUG, prints all candidate fields with their values) is also reusable — keep it as scaffolding rather than throwing it away after the first investigation.

## Related

- Files: `mod/OSPlus/scripts/chat.lua` (`resolvePlayerName`, `looksLikeAccountId`, `findFriendlyNameByAccountId`, `dumpProfileDiagnostics`)
- `docs/architecture/state-contract.md` finding #3 (`cachedPlayerName` invalidation, now partially addressed by the don't-cache-the-ID rule — full mid-session rename invalidation is still deferred)
- `docs/learnings/chat-presence.md` — the chat-presence pipeline that consumes the resolved name
