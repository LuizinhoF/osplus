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

    Why "one shot per change" instead of polling every tick:
      - The friendly display name is session-stable in practice (the OS
        client doesn't expose a rename mid-match path). Re-emitting on
        every tick would burn a scrypt verify on the relay every 30 frames.
      - If the user DOES somehow change their name mid-session, the next
        tick where the resolved name differs from `lastSnapshot` will
        emit a fresh upsert.

    Why not subscribe to a "display name resolved" event instead of polling:
      - identity.lua doesn't expose one (it's a transient cache walk, not
        a callback-driven flow).
      - tick() is called at 30 Hz from main.lua's LoopAsync; once the PID
        is in, the per-tick cost is two function calls and a table compare.
        That's cheaper than the machinery a callback would require.
--]]

local identity = require("identity")
local ipc      = require("ipc")
local log      = require("log")

local M = {}

-- Last successfully-emitted snapshot, keyed on the fields we actually send.
-- nil means "never emitted." Tracked so we don't re-emit unchanged rows on
-- every tick. Reset is intentionally NOT exposed — see profile.tick rationale.
local lastSnapshot = nil

local function snapshotsEqual(a, b)
    if a == nil or b == nil then return false end
    return a.prometheusId    == b.prometheusId
       and a.displayName     == b.displayName
       and a.steamId         == b.steamId
       and a.currentPlatform == b.currentPlatform
end

local function buildSnapshot(pid, displayName, steamId)
    return {
        prometheusId    = pid,
        displayName     = displayName,
        steamId         = steamId,
        currentPlatform = "Steam",  -- OSPlus is Steam-only per ADR 0001 scope
    }
end

-- Per-tick attempt. Cheap exits when nothing has changed; emits at most
-- once per snapshot delta. No internal logging on the early-exit paths so
-- production logs don't get flooded — the [PROFILE] emit line is the only
-- per-session marker callers need.
function M.tick()
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

    local snap = buildSnapshot(pid, displayName, steamId)
    if snapshotsEqual(snap, lastSnapshot) then return end

    lastSnapshot = snap
    log.log(string.format(
        "[PROFILE] emit profile_upsert pid=%s displayName=%s steamId=%s",
        pid, displayName, tostring(steamId)
    ))
    -- shallow-copy snap so the IPC writer's `payload.type = ...` mutation
    -- doesn't poison our snapshot equality check on the next tick.
    local payload = {
        prometheusId    = snap.prometheusId,
        displayName     = snap.displayName,
        steamId         = snap.steamId,
        currentPlatform = snap.currentPlatform,
    }
    pcall(ipc.writeProfileUpsertToOutbox, payload)
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
