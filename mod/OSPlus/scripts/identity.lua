local cfg   = require("config")
local log   = require("log")
local utils = require("utils")

local M = {}

local cachedPlayerName = nil
local didProfileDiagnosticDump = false
local didRejectMachineName = false
local localMachineName = (os.getenv("COMPUTERNAME") or os.getenv("HOSTNAME") or ""):upper()

local function looksLikeAccountId(s)
    -- Pure lowercase hex, 20+ chars. Real friendly names contain non-hex
    -- characters (most usernames have at least one letter outside [a-f] or
    -- a digit / symbol) or are shorter than 20 chars.
    return type(s) == "string" and #s >= 20 and s:match("^[0-9a-f]+$") ~= nil
end

local function looksLikeMachineName(s)
    if type(s) ~= "string" or localMachineName == "" then return false end
    return s:upper() == localMachineName
end

local function isUsableDisplayName(s)
    return type(s) == "string"
        and s ~= ""
        and s ~= "None"
        and not looksLikeAccountId(s)
        and not looksLikeMachineName(s)
end

local function makeFallbackName()
    local steamId = M.resolveSteamId()
    if steamId and #steamId >= 4 then
        return "Player-" .. steamId:sub(-4)
    end
    return cfg.CHAT_PLAYER_NAME
end

function M.getLocalAccountId()
    local id = nil
    pcall(function()
        local pc = utils.getPlayerController()
        if pc and pc:IsValid() then
            local ps = pc.PlayerState
            if ps and ps:IsValid() then
                id = ps.PlayerNamePrivate:ToString()
            end
        end
    end)
    if id == "" then return nil end
    return id
end

function M.resolveSteamId()
    local ok, steamId = pcall(function()
        local subsystem = FindFirstOf("PMIdentitySubsystem")
        if not subsystem or not subsystem:IsValid() then return nil end
        return subsystem:GetSteamId()
    end)
    if not ok or not steamId then return nil end

    if type(steamId) == "userdata" then
        local sok, s = pcall(function() return steamId:ToString() end)
        if sok then steamId = s end
    end

    steamId = tostring(steamId)
    if steamId == "" or steamId == "None" then return nil end
    return steamId
end

local function readProfileField(struct, fieldName)
    local ok, val = pcall(function() return struct[fieldName] end)
    if not ok or val == nil then return nil end

    -- Userdata (the common case for UE properties): the ONLY meaningful read
    -- is :ToString(). Lua's tostring(userdata) returns "TypeName: <ptr>" (e.g.
    -- "FString: 000001A59408D928") which is never the value we want. Falling
    -- back to it makes a half-populated FString look like a successful read —
    -- the v27 identity-hook chase resolved with that exact failure mode.
    if type(val) == "userdata" then
        local sok, s = pcall(function() return val:ToString() end)
        if sok and type(s) == "string" and s ~= "" and s ~= "None" then return s end
        return nil
    end

    -- Non-userdata fallback (Lua string / number / bool the engine occasionally
    -- hands back directly): plain tostring is fine, no userdata-shape risk.
    local s = tostring(val)
    if s and s ~= "" and s ~= "None" then return s end
    return nil
end

local function findFriendlyNameByAccountId(localId)
    if not localId then return nil end
    local ok, profiles = pcall(FindAllOf, "PMPlayerPublicProfile")
    if not ok or not profiles then return nil end
    for _, prof in ipairs(profiles) do
        if prof:IsValid() then
            local sok, struct = pcall(function() return prof.PlayerPublicProfile end)
            if sok and struct then
                local pid = readProfileField(struct, "PlayerId")
                if pid == localId then
                    for _, field in ipairs({ "Username", "DisplayName", "PlayerName" }) do
                        local v = readProfileField(struct, field)
                        if v then return v, field end
                    end
                end
            end
        end
    end
    return nil
end

function M.findPlayerIdByDisplayName(displayName)
    if type(displayName) ~= "string" or displayName == "" then return nil, nil end

    local ok, profiles = pcall(FindAllOf, "PMPlayerPublicProfile")
    if not ok or not profiles then return nil, nil end

    for _, prof in ipairs(profiles) do
        if prof:IsValid() then
            local sok, struct = pcall(function() return prof.PlayerPublicProfile end)
            if sok and struct then
                local playerId = readProfileField(struct, "PlayerId")
                for _, field in ipairs({ "Username", "DisplayName", "PlayerName", "Name" }) do
                    local value = readProfileField(struct, field)
                    if value == displayName and playerId then
                        return playerId, field
                    end
                end
            end
        end
    end

    return nil, nil
end

local function dumpProfileDiagnostics(localId)
    if didProfileDiagnosticDump then return end
    didProfileDiagnosticDump = true
    log.log("[IDENTITY] === Player profile diagnostic (one-shot) ===")
    log.log("[IDENTITY] localId (PlayerState.PlayerNamePrivate): " .. tostring(localId))
    local ok, profiles = pcall(FindAllOf, "PMPlayerPublicProfile")
    if not ok or not profiles then
        log.log("[IDENTITY] PMPlayerPublicProfile: FindAllOf returned nothing")
        return
    end
    log.log("[IDENTITY] PMPlayerPublicProfile instance count: " .. #profiles)
    local probeFields = { "PlayerId", "Username", "DisplayName", "PlayerName", "Name", "AccountId" }
    for i, prof in ipairs(profiles) do
        if prof:IsValid() then
            local sok, struct = pcall(function() return prof.PlayerPublicProfile end)
            if sok and struct then
                local parts = {}
                for _, f in ipairs(probeFields) do
                    local v = readProfileField(struct, f)
                    if v then parts[#parts + 1] = f .. "=" .. v end
                end
                log.log("[IDENTITY]   [" .. i .. "] " .. (parts[1] and table.concat(parts, ", ") or "(no probe fields populated)"))
            else
                log.log("[IDENTITY]   [" .. i .. "] PlayerPublicProfile struct unreadable")
            end
        end
    end
end

function M.resolveDisplayName()
    if cachedPlayerName then return cachedPlayerName end
    local localId = M.getLocalAccountId()
    if not localId then return nil end

    -- Fast path: PlayerNamePrivate already holds the friendly name.
    if isUsableDisplayName(localId) then
        cachedPlayerName = localId
        log.log("[IDENTITY] Resolved display name: " .. localId)
        return localId
    end

    if looksLikeMachineName(localId) and not didRejectMachineName then
        didRejectMachineName = true
        log.log("[IDENTITY] Ignoring local machine name from PlayerNamePrivate: " .. localId)
    end

    -- Slow path: PlayerNamePrivate is currently the account ID. Try the
    -- profile cache (usually a miss for the local player but cheap to check).
    local friendly, sourceField = findFriendlyNameByAccountId(localId)
    if isUsableDisplayName(friendly) then
        cachedPlayerName = friendly
        log.log("[IDENTITY] Resolved display name: " .. friendly
            .. " (PMPlayerPublicProfile." .. sourceField .. ", accountId=" .. localId .. ")")
        return friendly
    end

    -- Profile not loaded yet, or the field currently holds a non-game value
    -- (account ID or local machine name). Return nil so callers can fall back
    -- to a synthetic runtime label without ever persisting/broadcasting the
    -- bad value. See docs/learnings/playernameprivate-transient-account-id.md
    -- and docs/learnings/playernameprivate-machine-name-out-of-match.md.
    if cfg.DEBUG then dumpProfileDiagnostics(localId) end
    return nil
end

function M.getFriendlyDisplayName()
    return cachedPlayerName
end

function M.getBestLocalName()
    return cachedPlayerName or makeFallbackName()
end

function M.reset()
    cachedPlayerName = nil
    didProfileDiagnosticDump = false
    didRejectMachineName = false
    -- NOTE: cachedPrometheusId is intentionally NOT reset on map transitions.
    -- The local player's Prometheus ID is session-stable and the hook that
    -- resolves it self-unregisters on first success — re-resetting would
    -- leave the value permanently nil for the rest of the session.
end

-- ---------------------------------------------------------------------------
-- Local Prometheus ID resolution (R-B substrate from ADR 0001)
-- ---------------------------------------------------------------------------
-- The local player's Prometheus ID is read from PMIdentitySubsystem via the
-- GetAuthenticatedPlayerId UFunction (out-params: Valid:Bool, OutPlayerId:Str).
-- We hook GetIdentityState as an "identity flow tick" — it fires multiple
-- times during cold-start; on each fire we attempt the read. Early fires
-- return Valid=false (login still in progress); the first fire with
-- Valid=true gives us the canonical Prometheus ID, at which point we cache,
-- notify subscribers, and self-unregister the hook.
--
-- Why GetAuthenticatedPlayerId (vs walking PMPlayerPublicProfile cache):
--   - "Authenticated" by definition refers to the LOCAL player who logged in
--     to Odyssey's service — exactly one per session, no disambiguation
--     needed. The v25-v29 PMPlayerPublicProfile-walk approach was falsified:
--     construction order is unreliable and PlayerState.PlayerNamePrivate is
--     the Windows hostname during cold-start, not an account ID.
--
-- Why hook GetIdentityState (vs the other 3 UFunctions Pass 6 v2 caught firing):
--   - Earliest fire in the identity bootstrap window
--   - Host UObject (PMIdentitySubsystem) is singleton-stable
--   - Independent of PMPlayerModel.WasCached (which is false during the
--     identity bootstrap window — making PMPlayerModel-side reads unreliable)
--   - Doesn't fire on every-frame paths like HasFeatureFlag
--
-- Why register RegisterHook directly at module load (no FindFirstOf /
-- NotifyOnNewObject dance):
--   - RegisterHook hooks the UFunction in the class table, which is loaded
--     when /Script/Prometheus loads (engine startup). NO instance is required.
--   - Pass 6 v2's two-phase pattern was for a DISCOVERY probe that needed an
--     instance to enumerate UFunctions via ForEachFunction. We know the exact
--     path, so we skip that machinery.
--   - The first revision of this module did use the two-phase pattern + an
--     ExecuteInGameThread defer. It missed the GetIdentityState fire by
--     ~30ms (subsystem constructed → callback fires → defer to next tick →
--     install runs → already too late).
--
-- Why self-unhook on first resolution:
--   - PlayerId is stable for the session — re-resolving has zero value
--   - GetIdentityState fires multiple times during/after login; without
--     unhooking we'd re-run readAuthenticatedPlayerId on every fire forever
--
-- See:
--   - docs/decisions/0001-identity-model.md (R-B substrate definition)
--   - docs/learnings/ue4ss-cold-start-hook-install-pattern.md (when each
--     install pattern applies)
--   - docs/learnings/ue4ss-ufunction-out-param-marshaling-3-0-1.md (the
--     empty-table out-param convention used by readAuthenticatedPlayerId,
--     pinned to UE4SS 3.0.1)

local PROMETHEUS_HOOK_PATH = "/Script/Prometheus.PMIdentitySubsystem:GetIdentityState"

local cachedPrometheusId = nil
local resolveListeners = {}
local hookPreId = nil
local hookPostId = nil

-- Normalize a UFunction return value into a Lua string. Handles both shapes
-- UE4SS produces: a Lua string (already unwrapped) or an FString userdata
-- (must call :ToString()). Returns nil for empty / "None" / anything else.
local function toLuaString(val)
    if val == nil then return nil end
    if type(val) == "string" then
        if val == "" or val == "None" then return nil end
        return val
    end
    if type(val) == "userdata" then
        local ok, s = pcall(function() return val:ToString() end)
        if ok and type(s) == "string" and s ~= "" and s ~= "None" then return s end
    end
    return nil
end

-- Walk an out-param bucket list looking for paramName.
--
-- UE4SS 3.0.1's two-out-param marshaling (empirically observed v35 run):
-- both base-type out-params collapse into the FIRST bucket, keyed by
-- ParamName; the second bucket stays empty. Issue #971 documents the
-- collapse. We iterate both buckets so the code stays correct if a future
-- UE4SS build splits them across buckets as the docs imply.
local function pluckOutParam(buckets, paramName, expectedType)
    for _, bucket in ipairs(buckets) do
        if type(bucket) == "table" then
            local v = bucket[paramName]
            if v ~= nil and (expectedType == nil or type(v) == expectedType) then
                return v
            end
        end
    end
    return nil
end

-- Read PMIdentitySubsystem:GetAuthenticatedPlayerId. Returns (pid|nil, reason).
--
-- UE4SS 3.0.1 out-param convention: pass an empty Lua table per declared
-- out-param. UE4SS uses the table as a by-reference container (the only
-- by-ref type in Lua) and writes results into bucket.<ParamName>. See
-- docs/learnings/ue4ss-ufunction-out-param-marshaling-3-0-1.md for the
-- v33→v34→v35 derivation and the rejected shapes that don't work.
local function readAuthenticatedPlayerId()
    local instance
    pcall(function() instance = FindFirstOf("PMIdentitySubsystem") end)
    if not instance or not instance:IsValid() then
        return nil, "subsystem-not-found"
    end

    local validBucket = {}
    local pidBucket = {}
    local ok, err = pcall(function()
        instance:GetAuthenticatedPlayerId(validBucket, pidBucket)
    end)
    if not ok then
        return nil, "call-errored:" .. tostring(err)
    end

    local valid = pluckOutParam({validBucket, pidBucket}, "Valid", "boolean")
    if valid == nil then return nil, "Valid-out-param-not-found" end
    if valid ~= true then return nil, "not-yet-authenticated(Valid=false)" end

    local pid = toLuaString(pluckOutParam({validBucket, pidBucket}, "OutPlayerId"))
    if not pid then return nil, "OutPlayerId-empty" end
    return pid
end

local function fireResolvedListeners(pid)
    -- Snapshot the listener list before iterating so a subscriber that calls
    -- onPrometheusIdResolved during its own callback doesn't re-fire itself.
    local listeners = resolveListeners
    resolveListeners = {}
    for _, cb in ipairs(listeners) do
        pcall(cb, pid)
    end
end

local function deferredUnregisterHook()
    if hookPreId == nil and hookPostId == nil then return end
    local preId, postId = hookPreId, hookPostId
    hookPreId, hookPostId = nil, nil
    -- Defer to next tick to avoid mutating the RegisterHook dispatcher
    -- mid-fire. UnregisterHook from inside a hook callback IS supported
    -- (ConsoleEnablerMod precedent + UE4SS Issue #455), but deferring is
    -- the safer pattern when we don't need an immediate stop.
    ExecuteInGameThread(function()
        local ok, err = pcall(function()
            UnregisterHook(PROMETHEUS_HOOK_PATH, preId, postId)
        end)
        if not ok then
            log.log("[IDENTITY] [!] UnregisterHook failed: " .. tostring(err))
        end
    end)
end

local function onIdentityHookFire(...)
    if select("#", ...) == 0 then return end
    if cachedPrometheusId then return end

    local pid = readAuthenticatedPlayerId()
    -- Pre-Valid=true fires return nil (login still in progress); stay quiet
    -- so production logs don't spam — first successful fire produces the
    -- only [IDENTITY] line in healthy cold-start.
    if not pid then return end

    cachedPrometheusId = pid
    log.log("[IDENTITY] resolved local Prometheus ID: " .. pid)

    fireResolvedListeners(pid)
    deferredUnregisterHook()
end

function M.getLocalPrometheusId()
    return cachedPrometheusId
end

function M.onPrometheusIdResolved(cb)
    if type(cb) ~= "function" then return end
    -- Late subscribers see the cached value immediately so callers don't
    -- have to special-case "subscribed too late."
    if cachedPrometheusId then
        pcall(cb, cachedPrometheusId)
        return
    end
    resolveListeners[#resolveListeners + 1] = cb
end

-- ---- Module-load hook install ----
-- Direct RegisterHook on the known UFunction path. UFunctions exist in the
-- class table from /Script/Prometheus package load (engine startup) — no
-- instance required, no defer required. Mirrors the existing
-- /Script/Engine.GameState:OnRep_MatchState hook pattern in main.lua.

local ok, preId, postId = pcall(RegisterHook, PROMETHEUS_HOOK_PATH, onIdentityHookFire)
if not ok then
    log.log("[IDENTITY] [!] RegisterHook failed: " .. tostring(preId))
else
    hookPreId, hookPostId = preId, postId
end

return M