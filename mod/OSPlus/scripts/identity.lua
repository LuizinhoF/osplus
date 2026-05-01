local cfg = require("config")
local log = require("log")

local M = {}

-- ---------------------------------------------------------------------------
-- Local-player display-name resolution (v42 — three-path UPMPlayerUIData read)
-- ---------------------------------------------------------------------------
-- The local player's friendly display name lives on UPMPlayerUIData, the
-- UI data model the in-game widget binds to. Every player visible in any
-- Prometheus UI surface (friends list, leaderboard, lobby, the local
-- player's own profile header) gets a UPMPlayerUIData instance. Discovered
-- by grepping the UE4SS type-stub dump at:
--
--     <game>/Binaries/Win64/Mods/shared/types/Prometheus.lua
--
-- (UE4SS's UHT-Compatible-Header-Generator dumps every UClass it loads.
-- Always check those stubs FIRST before crashing the game with reflection
-- — see docs/learnings/ue4ss-type-stubs-as-canonical-source.md.)
--
-- The relevant fields on UPMPlayerUIData (Prometheus.lua line ~13679):
--   PlayerId      : FString             -- the Prometheus ID (disambiguator)
--   Username      : FOdyUITextBinding   -- friendly display name (binding wrapper)
--   Profile       : FPlayerPublicProfile -- embedded struct (has direct Username FString)
--   IsLocalPlayer : FOdyUIBoolBinding   -- true on the local player's row
--
-- FPlayerPublicProfile (Prometheus.lua line ~6747) has a direct
-- `Username : FString` field — no binding indirection. This is the cheapest
-- read and the v42 primary path.
--
-- FOdyUITextBinding (OdyUI.lua line 121-123) is a struct with one reflected
-- field `InitialValue : FText`. The struct's *live* current value is held
-- in non-reflected C++ members, reachable only via the BlueprintFunctionLibrary
-- accessor `UOdyUITextBindingFunctionLibrary:TextBinding_GetValue(binding)`
-- (OdyUI.lua line 633). v41 assumed `InitialValue` would carry the live
-- value; v41 telemetry showed `username-binding-InitialValue-empty` because
-- the BP sets the binding via `TextBinding_SetValue(...)` post-construction
-- rather than as a struct constructor default — `InitialValue` literally
-- means "the value the binding was constructed with."
--
-- Resolver flow (three paths, cheapest first):
--   1. ui.Profile.Username                       — direct FString. v42 primary.
--   2. ui.Username.InitialValue                  — binding compile-time default.
--   3. TextBinding_GetValue(ui.Username)         — canonical live accessor.
--
-- Path 1 should succeed in nearly all cases since the embedded struct is
-- populated when the UPMPlayerUIData instance is constructed. Paths 2-3 are
-- belt-and-suspenders for the case where Profile.Username is somehow empty
-- but the binding-driven UI text is populated.
--
-- Why NOT walk by IsLocalPlayer instead of PlayerId:
--   IsLocalPlayer is a binding too — same indirection risk. PlayerId is a
--   plain FString set before any UI is shown.
--
-- Previously-tried paths and why they failed:
--   v25-v34: PlayerState.PlayerNamePrivate → Windows hostname during cold
--            start; falsified.
--   v35-v36: Walk PMPlayerPublicProfile cache → cache stayed empty for
--            2+ minutes at main menu in v37 session.
--   v37: PMPlayerModel:GetCachedMeResponseV1 / GetCachedPlayerPublicProfile
--            → WasCached=false for 2+ minutes; the menu never warms those
--            caches at all.
--   v38: NotifyOnNewObject "first PMPlayerPublicProfile constructed = local
--            player" → captured "Greedom" (a friend in the cache).
--   v41: ui.Username.InitialValue alone → InitialValue empty (the BP uses
--            SetValue, not a struct constructor default). Falsified by
--            user-machine telemetry: `username-binding-InitialValue-empty`.
--
-- See: docs/learnings/identity-display-name-substrate-replaces-heuristics.md
-- See: docs/learnings/ue4ss-type-stubs-as-canonical-source.md
-- See: docs/learnings/ody-ui-binding-initialvalue-vs-live.md (v42 — to write
--      after the path-1 read confirms successful resolution; the InitialValue-
--      vs-live distinction is a transferable Prometheus-UI fact)

local cachedPlayerName = nil

-- Forward declarations for helpers defined further down (next to the
-- Prometheus-ID resolver that originally introduced them). The display-name
-- resolver above needs to call them through these upvalue slots.
local pluckOutParam
local toLuaString

local function makeFallbackName()
    local steamId = M.resolveSteamId()
    if steamId and #steamId >= 4 then
        return "Player-" .. steamId:sub(-4)
    end
    return cfg.CHAT_PLAYER_NAME
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

-- Read an FString or FText userdata into a plain Lua string.
-- Returns nil for empty / "None" / unreadable values.
local function userdataToString(v)
    if v == nil then return nil end
    if type(v) == "string" then
        if v == "" or v == "None" then return nil end
        return v
    end
    if type(v) == "userdata" then
        local ok, s = pcall(function() return v:ToString() end)
        if ok and type(s) == "string" and s ~= "" and s ~= "None" then return s end
    end
    return nil
end

-- Cached BlueprintFunctionLibrary CDO for the live-binding fallback path.
-- Resolved lazily on first use, then reused. Reading the CDO via
-- StaticFindObject (preferred — exact path) or FindFirstOf (fallback) is
-- cheap, but we still cache because the resolver runs on every tick.
local cachedTextBindingLib = nil

local function getTextBindingFunctionLibrary()
    if cachedTextBindingLib and cachedTextBindingLib:IsValid() then
        return cachedTextBindingLib
    end
    local lib
    pcall(function()
        lib = StaticFindObject("/Script/OdyUI.Default__OdyUITextBindingFunctionLibrary")
    end)
    if not lib or not lib:IsValid() then
        pcall(function() lib = FindFirstOf("OdyUITextBindingFunctionLibrary") end)
    end
    if lib and lib:IsValid() then
        cachedTextBindingLib = lib
        return lib
    end
    return nil
end

-- Read the LIVE FText value from an FOdyUITextBinding struct via the
-- canonical BP accessor `UOdyUITextBindingFunctionLibrary:TextBinding_GetValue`.
-- Used when the binding's `InitialValue` field is empty — which happens when
-- the BP set the value via `TextBinding_SetValue(binding, NewText)` post-
-- construction rather than as the struct's compile-time default.
local function readTextBindingViaAccessor(binding)
    local lib = getTextBindingFunctionLibrary()
    if not lib then return nil, "no-OdyUITextBindingFunctionLibrary-CDO" end

    local result
    local ok, err = pcall(function() result = lib:TextBinding_GetValue(binding) end)
    if not ok then return nil, "TextBinding_GetValue-call-failed:" .. tostring(err) end
    return userdataToString(result)
end

-- Walk UPMPlayerUIData instances and find the one whose PlayerId matches
-- the supplied Prometheus ID — that's the local player's UI data row.
-- Returns (nameStr, sourceLabel) on success or (nil, reason) on failure.
--
-- Three read paths in order of cost (cheapest first):
--   1. ui.Profile.Username          — embedded FPlayerPublicProfile struct,
--                                     plain FString, no indirection.
--   2. ui.Username.InitialValue     — binding's compile-time default; only
--                                     populated for bindings whose value was
--                                     set as a constructor argument.
--   3. TextBinding_GetValue(ui.Username) — canonical live accessor via the
--                                     BlueprintFunctionLibrary CDO; works
--                                     even when the binding was updated via
--                                     SetValue after construction.
--
-- See header docstring for the full discovery story (v41/v42).
local function readLocalPlayerUIData(prometheusId)
    if not prometheusId then return nil, "no-prometheusId" end

    local instances
    pcall(function() instances = FindAllOf("PMPlayerUIData") end)
    if not instances or #instances == 0 then
        return nil, "no-PMPlayerUIData-instances"
    end

    for _, ui in ipairs(instances) do
        if ui and ui:IsValid() then
            local pidVal
            pcall(function() pidVal = ui.PlayerId end)
            local pidStr = userdataToString(pidVal)
            if pidStr == prometheusId then
                -- Path 1: embedded Profile struct's Username field (FString).
                local profile
                pcall(function() profile = ui.Profile end)
                if profile then
                    local uname
                    pcall(function() uname = profile.Username end)
                    local s = userdataToString(uname)
                    if s then return s, "PMPlayerUIData.Profile.Username" end
                end

                -- Path 2 & 3: the Username binding (FOdyUITextBinding struct).
                local binding
                pcall(function() binding = ui.Username end)
                if not binding then
                    return nil, "no-Profile.Username-and-no-Username-binding"
                end

                local initVal
                pcall(function() initVal = binding.InitialValue end)
                local sInit = userdataToString(initVal)
                if sInit then return sInit, "PMPlayerUIData.Username.InitialValue" end

                local sLive, liveErr = readTextBindingViaAccessor(binding)
                if sLive then return sLive, "PMPlayerUIData.Username.TextBinding_GetValue" end

                return nil, "username-binding-empty-on-all-paths(GetValue=" .. tostring(liveErr) .. ")"
            end
        end
    end
    return nil, "no-PMPlayerUIData-instance-matched-our-pid"
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

-- Track whether we've already logged the "looking for PID, no UI data yet"
-- breadcrumb. Without this, profile.tick at 30 Hz would spam the log with
-- the same waiting message every frame while the UPMPlayerUIData instance
-- is still being constructed by the post-login UI bootstrap.
local loggedWaitingReason = nil

function M.resolveDisplayName()
    if cachedPlayerName then return cachedPlayerName end

    local pid = M.getLocalPrometheusId()
    if not pid then return nil end

    local friendly, source = readLocalPlayerUIData(pid)
    if friendly then
        cachedPlayerName = friendly
        log.log("[IDENTITY] Resolved display name: " .. friendly .. " (" .. source .. ")")
        return friendly
    end

    -- Log the failure reason once per distinct reason — gives visibility
    -- into the "still waiting" state without per-frame spam. The reason
    -- transitions naturally as bootstrap progresses: typically
    -- no-PMPlayerUIData-instances → no-PMPlayerUIData-instance-matched-our-pid
    -- (UI data exists but local player's row hasn't been added yet) →
    -- resolved.
    if source ~= loggedWaitingReason then
        loggedWaitingReason = source
        log.log("[IDENTITY] [waiting] resolveDisplayName: " .. tostring(source))
    end
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
    loggedWaitingReason = nil
    -- NOTE: cachedPrometheusId is intentionally NOT reset on map transitions.
    -- It's session-stable; the RegisterHook stays registered for the session
    -- but its body short-circuits cheaply once cachedPrometheusId is set, so
    -- there's no benefit to forcing a re-resolve here — and a wipe would
    -- leave it permanently nil for the rest of the session anyway since the
    -- engine empirically stops calling GetIdentityState post-authentication.
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
-- Why we DON'T self-unhook on first resolution (changed in v46):
--   - PlayerId is stable for the session — re-resolving has zero value
--   - GetIdentityState fires multiple times during the cold-start identity
--     flow, but the engine empirically stops calling it once the local
--     player is authenticated (v45 instrumented session: hookFires held
--     at 2 across 93 minutes), so leaving the hook registered is free.
--   - Calling UnregisterHook (even via ExecuteInGameThread) mutates
--     UE4SS's m_engine_tick_actions vector, which UE4SS Issue #1180 and
--     our own bisection pin as the cause of an access-violation crash
--     ~60-90 minutes into a session in this codebase.
--   - The hook callback (onIdentityHookFire) early-returns on the cached
--     PID, so any rare post-resolution fire is essentially free.
--
-- See:
--   - docs/decisions/0001-identity-model.md (R-B substrate definition)
--   - docs/learnings/ue4ss-cold-start-hook-install-pattern.md (when each
--     install pattern applies)
--   - docs/learnings/ue4ss-ufunction-out-param-marshaling-3-0-1.md (the
--     empty-table out-param convention used by readAuthenticatedPlayerId,
--     pinned to UE4SS 3.0.1)
--   - docs/learnings/ue4ss-execute-in-game-thread-unregister-hook-corruption.md
--     (why we removed the self-unregister; UE4SS Issue #1180 alignment)

local PROMETHEUS_HOOK_PATH = "/Script/Prometheus.PMIdentitySubsystem:GetIdentityState"

local cachedPrometheusId = nil
local resolveListeners = {}
local hookPreId = nil
local hookPostId = nil

-- Normalize a UFunction return value into a Lua string. Handles both shapes
-- UE4SS produces: a Lua string (already unwrapped) or an FString userdata
-- (must call :ToString()). Returns nil for empty / "None" / anything else.
function toLuaString(val)  -- assigns to the forward-declared upvalue at the top of the file
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
function pluckOutParam(buckets, paramName, expectedType)  -- forward-declared upvalue
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

local function onIdentityHookFire(...)
    if select("#", ...) == 0 then return end
    -- Cheap early-return for any post-resolution fire. The hook stays
    -- registered for the session lifetime — no UnregisterHook call,
    -- because UE4SS Issue #1180 (ExecuteInGameThread→UnregisterHook can
    -- corrupt UE4SS's m_engine_tick_actions vector via mid-iteration
    -- reallocation, surfacing as access violations 60-90 minutes later).
    -- Leaving the hook registered is the chat-only build's pattern for
    -- OnRep_MatchState, which has been stable for hundreds of player-
    -- hours. The engine empirically stops calling GetIdentityState once
    -- the local player is authenticated, so this branch is taken at most
    -- a handful of times per session anyway. See
    -- docs/learnings/ue4ss-execute-in-game-thread-unregister-hook-corruption.md.
    if cachedPrometheusId then return end

    local pid = readAuthenticatedPlayerId()
    -- Pre-Valid=true fires return nil (login still in progress); stay quiet
    -- so production logs don't spam — first successful fire produces the
    -- only [IDENTITY] line in healthy cold-start.
    if not pid then return end

    cachedPrometheusId = pid
    log.log("[IDENTITY] resolved local Prometheus ID: " .. pid)

    fireResolvedListeners(pid)
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

-- ---- Module-load installs ----
-- One install: RegisterHook on PMIdentitySubsystem:GetIdentityState as the
-- read trigger for the Prometheus ID via GetAuthenticatedPlayerId.
--
-- Must install at module load (NOT on a user keypress) — the cold-start
-- identity flow fires before any user interaction is possible. See
-- docs/learnings/ue4ss-cold-start-hook-install-pattern.md.
--
-- The previous revision also installed NotifyOnNewObject on
-- PMPlayerPublicProfile to "capture the first instance constructed = local
-- player" per os-runtime-data-model.md's R-B v27 documented pattern. That
-- pattern was empirically falsified — for accounts with non-empty friend
-- lists, the first PMPlayerPublicProfile constructed is a friend, not the
-- local player. The display-name resolver now goes through PMPlayerModel
-- (path 1) and a PID-matched cache walk (path 2) instead. See
-- docs/learnings/identity-display-name-substrate-replaces-heuristics.md.

local hookOk, hookPre, hookPost = pcall(RegisterHook, PROMETHEUS_HOOK_PATH, onIdentityHookFire)
if not hookOk then
    log.log("[IDENTITY] [!] RegisterHook failed: " .. tostring(hookPre))
else
    hookPreId, hookPostId = hookPre, hookPost
end

return M