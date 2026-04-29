--[[
    OSPlus — Profile upsert
    =======================
    Per ADR 0002 + in-game-profile-mvp Slice 1-C.

    Drives the Lua side of the profile lifecycle:
      1. Subscribe to identity.onPrometheusIdResolved (fired exactly once
         per session by identity.lua's GetIdentityState hook — see ADR 0001
         R-B substrate).
      2. Each tick after the PID lands, try to resolve the friendly display
         name. PMPlayerPublicProfile is typically not populated at the
         instant the PID resolves — display name lags by a few frames to
         a few seconds while the post-login cache fills.
      3. Once both PID and a usable display name are in hand, emit ONE
         `profile_upsert` IPC message to the sidecar (which in turn calls
         PUT /api/profiles/{pid} on the relay). The PUT is idempotent so
         a duplicate emit is harmless, but we suppress unchanged re-emits
         anyway to keep the relay log readable.

    Cosmetic loadout fields (logoId, nameplateId, emoticonId, titleId,
    masteryLevel) are intentionally NOT sent yet. The server schema accepts
    NULLs for all of them and the upsert is destructive (PUT not PATCH),
    so a future widening of identity.lua will simply rewrite the same row
    with the new fields populated. Discovering the right UE objects is a
    standalone RE task tracked separately.

    Per-tick discipline:
      Every snapshot field is session-immutable (Prometheus ID, display
      name, Steam ID, platform — see the LoadingFlow notes for each). After
      the first successful emit there is no work left to do this session.
      `M.tick` short-circuits on `lastSnapshot` for that reason — see the
      function-level comment for why this is load-bearing, not just nice.
--]]

local identity = require("identity")
local ipc      = require("ipc")
local log      = require("log")

local M = {}

-- The snapshot we successfully emitted (or nil if we haven't yet). Doubles
-- as the "have we emitted?" sentinel that gates `M.tick`. Kept around as
-- the snapshot itself (rather than a bare boolean) for forensic value when
-- inspecting state from a debugger or log dump.
local lastSnapshot = nil

local function buildSnapshot(pid, displayName, steamId)
    return {
        prometheusId    = pid,
        displayName     = displayName,
        steamId         = steamId,
        currentPlatform = "Steam",  -- OSPlus is Steam-only per ADR 0001 scope
    }
end

-- Per-tick attempt. After the first successful emit this short-circuits
-- to a single comparison and returns — nothing else to do for the rest
-- of the session.
--
-- LOAD-BEARING: the early return at the top is not just an optimization.
-- The pre-snapshot path calls `identity.resolveSteamId()`, which under
-- the hood is `FindFirstOf("PMIdentitySubsystem"):GetSteamId():ToString()`
-- — three UE-reflected operations that each allocate UE4SS-tracked
-- userdata wrappers. At 30 Hz over a long session that is tens of
-- thousands of short-lived UE allocations, and we crashed UE4SS itself
-- this way (a stale-slot dereference inside UE4SS's userdata-tracking
-- table — exception 0xC0000005 reading 0xFFFFFFFFFFFFFFFF, faulting at
-- UE4SS.dll+0x9211B2 after ~17 minutes idle in lobby). See:
--   docs/learnings/profile-tick-userdata-allocation-leak.md
-- The fix is not to make the polling cheaper; it is to stop polling
-- for a value that cannot change.
function M.tick()
    if lastSnapshot then return end

    local pid = identity.getLocalPrometheusId()
    if not pid then return end

    -- resolveDisplayName drives the cache walk; getFriendlyDisplayName
    -- returns the cached value (or nil if not yet resolved). The split
    -- exists so callers can re-trigger the walk without paying the cost
    -- of redundant log emission inside identity.lua.
    identity.resolveDisplayName()
    local displayName = identity.getFriendlyDisplayName()
    if not displayName then return end

    -- steamId may legitimately be nil on non-Steam builds. We send it
    -- when present (the schema column is nullable) and don't gate emit
    -- on it — for the Steam build of OSPlus this branch is always taken,
    -- but keeping the nil-tolerance keeps the future cross-platform path
    -- open without another rewrite.
    local steamId = identity.resolveSteamId()

    lastSnapshot = buildSnapshot(pid, displayName, steamId)
    log.log(string.format(
        "[PROFILE] emit profile_upsert pid=%s displayName=%s steamId=%s",
        pid, displayName, tostring(steamId)
    ))
    -- shallow-copy lastSnapshot so the IPC writer's `payload.type = ...`
    -- mutation doesn't bleed into the stored snapshot.
    pcall(ipc.writeProfileUpsertToOutbox, {
        prometheusId    = lastSnapshot.prometheusId,
        displayName     = lastSnapshot.displayName,
        steamId         = lastSnapshot.steamId,
        currentPlatform = lastSnapshot.currentPlatform,
    })
end

-- Module-load wiring. Subscribing here (rather than at the first tick)
-- makes the late-subscriber path in identity.onPrometheusIdResolved
-- irrelevant — the identity hook may fire before or after this require()
-- runs, and either way our subscriber gets the value.
function M.init()
    identity.onPrometheusIdResolved(function(pid)
        log.log("[PROFILE] PID resolved (" .. tostring(pid) .. "); waiting for displayName before first emit")
    end)
end

return M
