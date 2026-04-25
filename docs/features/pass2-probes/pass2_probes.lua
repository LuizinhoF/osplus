--[[
    Feasibility Pass 2 + Pass 3 + Pass 4 probes for
    docs/features/in-game-profile-mvp.md.

    NOT shipped with OSPlus. Installed as a separate UE4SS mod named
    `OSPlusProbes`. See docs/features/pass2-probes/README.md for install.

    Keybinds:
      F11 — Pass 2 one-shot snapshot battery: A1 + A3 + B1 + B2
      F12 — Pass 2 A2 polling: PlayerNamePrivate every 500ms for 15s
      F9  — Pass 3 battery: C1 (Pawn components) + C2 (PMPlayerModel
            UFunction signatures) + C3 (PlayerState_Game_C property
            + UFunction dump)
      F8  — Pass 4 spike (ADR 0001 acceptance prereq):
            D2 = cache fetch (PMPlayerModel:GetCachedMeResponseV1)
            D1 = subscription (PMPlayerModel.GetMeRequestV1Completed
                 multicast bind + force-trigger via :GetMeV1)
            Also auto-attempts D1 binding at script load to catch the
            natural login fire without needing a keypress.

    Output: Binaries/Win64/UE4SS.log (search for [A1], [A2], [A3],
    [B1], [B2], [C1], [C2], [C3], [D1], [D2], [Pass4]) and any
    mirrored external console window. Some UE4SS installs place the
    log under Binaries/Win64/ue4ss/ — check yours.

    Self-contained — uses only UE4SS Lua globals (FindFirstOf, FindAllOf,
    RegisterKeyBind, ExecuteInGameThread, LoopAsync, Key,
    RegisterCustomEvent).
]]

local function probeA1()
    local sys = FindFirstOf("PMIdentitySubsystem")
    if not sys or not sys:IsValid() then
        print("[A1] PMIdentitySubsystem not found")
        return
    end
    local sid, st = nil, nil
    pcall(function() sid = sys:GetSteamId() end)
    if type(sid) == "userdata" then
        pcall(function() sid = sid:ToString() end)
    end
    pcall(function() st = sys:GetIdentityState() end)
    print(string.format("[A1] SteamId=%s IdentityState=%s", tostring(sid), tostring(st)))
end

local function probeA2Snapshot()
    local raw, len, isHex = nil, 0, false
    pcall(function()
        local pc = FindFirstOf("PlayerController_Game_C")
        if not pc or not pc:IsValid() then return end
        local ps = pc.PlayerState
        if not ps or not ps:IsValid() then return end
        raw = ps.PlayerNamePrivate:ToString()
    end)
    if type(raw) == "string" then
        len = #raw
        isHex = raw:match("^[0-9a-f]+$") ~= nil and len >= 16
    end
    print(string.format("[A2] t=%d PlayerNamePrivate=%q len=%d hexShape=%s",
        os.time(), tostring(raw), len, tostring(isHex)))
end

local function probeA3()
    local model = FindFirstOf("PMPlayerModel")
    if not model or not model:IsValid() then
        print("[A3] PMPlayerModel not found")
        return
    end
    print("[A3] PMPlayerModel found; class=" .. model:GetClass():GetFullName())
    local function try(name)
        local ok, r = pcall(function() return model[name](model) end)
        print(string.format("[A3] %s() ok=%s ret=%s", name, tostring(ok), tostring(r)))
    end
    try("GetCachedMeResponseV1")
    try("GetDisplayNameV1")
    try("GetCachedPlayerPublicProfile")
end

local function probeB1()
    local candidates = {
        "PMIdentitySubsystem", "PMPlayerModel", "PMPlayerPublicProfile",
        "PMGameInstanceSubsystem", "PMPlayerState", "PMCombatComponent",
        "PMStrikerGameState", "PMMatchSubsystem", "PMPuckComponent",
        "PMMatchStatsComponent", "PMStrikerPlayerState", "PMStrikerCharacter",
    }
    for _, kind in ipairs(candidates) do
        local n, firstClass = 0, nil
        local ok, list = pcall(FindAllOf, kind)
        if ok and list then
            for _, o in ipairs(list) do
                if o and o:IsValid() then
                    n = n + 1
                    if not firstClass then firstClass = o:GetClass():GetFullName() end
                end
            end
        end
        if n > 0 then
            print(string.format("[B1] %s : %d instance(s), class=%s", kind, n, tostring(firstClass)))
        else
            print(string.format("[B1] %s : not found", kind))
        end
    end
end

local function probeB2()
    local patterns = {
        "[Rr]edirect", "[Hh]itPuck", "[Pp]uckHit", "[Bb]allHit",
        "[Bb]ounce", "[Kk]ick", "[Ss]mash", "[Ii]mpact",
        "[Cc]ontact", "[Dd]eflect",
    }
    local function matches(n)
        for _, p in ipairs(patterns) do
            if n:match(p) then return p end
        end
        return nil
    end

    local pc = FindFirstOf("PlayerController_Game_C")
    local pawn = pc and pc:IsValid() and pc.Pawn or nil
    if pawn and pawn:IsValid() then
        print("[B2] Pawn class: " .. pawn:GetClass():GetFullName())
        local enumOk = pcall(function()
            pawn:GetClass():ForEachFunction(function(fn)
                local n = fn:GetFName():ToString()
                local m = matches(n)
                if m then
                    print(string.format("[B2]   Pawn fn matches %q: %s", m, n))
                end
            end)
        end)
        if not enumOk then
            print("[B2]   (ForEachFunction not available in this UE4SS build)")
        end
    else
        print("[B2] No Pawn (not in active match with controller pawn)")
    end

    for _, kind in ipairs({
        "BP_Puck_C", "BP_Ball_C", "PMPuck_C", "Puck_C",
        "BP_StrikerBall_C", "PMBallActor_C",
    }) do
        local b = FindFirstOf(kind)
        if b and b:IsValid() then
            print("[B2] Ball-candidate actor: " .. kind)
            return
        end
    end
    print("[B2] (no ball class matched the guess list)")
end

local a2Active = false
local a2Remaining = 0
local A2_INTERVAL_MS = 500
local A2_DURATION_MS = 15000

local function startA2Poll()
    if a2Active then
        print("[A2] poll already running; ignoring")
        return
    end
    a2Active = true
    a2Remaining = math.floor(A2_DURATION_MS / A2_INTERVAL_MS)
    print(string.format("[A2] poll start: %d samples @ %dms", a2Remaining, A2_INTERVAL_MS))

    LoopAsync(A2_INTERVAL_MS, function()
        if not a2Active then return true end
        probeA2Snapshot()
        a2Remaining = a2Remaining - 1
        if a2Remaining <= 0 then
            a2Active = false
            print("[A2] poll complete")
            return true
        end
        return false
    end)
end

local REDIRECT_PATTERNS = {
    "[Rr]edirect", "[Hh]itPuck", "[Pp]uckHit", "[Bb]allHit",
    "[Bb]ounce", "[Kk]ick", "[Ss]mash", "[Ii]mpact",
    "[Cc]ontact", "[Dd]eflect",
}

local function matchesRedirect(name)
    for _, p in ipairs(REDIRECT_PATTERNS) do
        if name:match(p) then return p end
    end
    return nil
end

-- Try to iterate a TArray-valued property on an object. UE4SS TArray API
-- varies by build; this wrapper tries the common shapes and returns an
-- array of child objects (or nil + error string).
local function iterUObjectArrayProp(obj, propName, cb)
    local arr
    local okAccess, accessErr = pcall(function() arr = obj[propName] end)
    if not okAccess then
        return false, "access failed: " .. tostring(accessErr)
    end
    if arr == nil then return false, "property nil or absent" end

    local n
    local okN = pcall(function() n = arr:GetArrayNum() end)
    if okN and type(n) == "number" then
        for i = 1, n do
            local elem
            local ok = pcall(function() elem = arr[i] end)
            if ok and elem then cb(i, elem) end
        end
        return true, n
    end

    local okForEach = pcall(function()
        arr:ForEach(function(idx, el) cb(idx, el) end)
    end)
    if okForEach then return true, "iterated via :ForEach()" end

    return false, "no iterable access pattern worked"
end

local function probeC1()
    local pc = FindFirstOf("PlayerController_Game_C")
    local pawn = pc and pc:IsValid() and pc.Pawn or nil
    if not pawn or not pawn:IsValid() then
        print("[C1] No Pawn (not in active match with controller pawn)")
        return
    end
    print("[C1] Pawn class: " .. pawn:GetClass():GetFullName())

    local function scanComponent(label, i, comp)
        if not comp or not comp:IsValid() then return end
        local cname
        pcall(function() cname = comp:GetClass():GetFullName() end)
        print(string.format("[C1]   %s[%d] %s", label, i, tostring(cname)))
        pcall(function()
            comp:GetClass():ForEachFunction(function(fn)
                local fname = fn:GetFName():ToString()
                local m = matchesRedirect(fname)
                if m then
                    print(string.format("[C1]     fn matches %q: %s", m, fname))
                end
            end)
        end)
    end

    for _, propName in ipairs({"BlueprintCreatedComponents", "InstanceComponents"}) do
        local ok, info = iterUObjectArrayProp(pawn, propName, function(i, comp)
            scanComponent(propName, i, comp)
        end)
        if not ok then
            print(string.format("[C1]   (%s: %s)", propName, tostring(info)))
        end
    end
end

local function dumpUFunctionSignature(fn)
    local fname
    pcall(function() fname = fn:GetFName():ToString() end)
    if not fname then return end
    local numParms
    pcall(function() numParms = fn.NumParms end)

    print(string.format("[C2]   fn %s (NumParms=%s)", fname, tostring(numParms)))

    local okProps = pcall(function()
        fn:ForEachProperty(function(prop)
            local pname, ptype
            pcall(function() pname = prop:GetFName():ToString() end)
            pcall(function() ptype = prop:GetClass():GetFName():ToString() end)
            print(string.format("[C2]     param: %s : %s", tostring(pname), tostring(ptype)))
        end)
    end)
    if not okProps then
        print("[C2]     (ForEachProperty not available on UFunction in this build)")
    end
end

local function probeC2()
    local model = FindFirstOf("PMPlayerModel")
    if not model or not model:IsValid() then
        print("[C2] PMPlayerModel not found")
        return
    end
    print("[C2] PMPlayerModel class: " .. model:GetClass():GetFullName())

    local targetFns = {
        GetCachedMeResponseV1 = true,
        GetDisplayNameV1 = true,
        GetCachedPlayerPublicProfile = true,
    }
    local printedNames = {}

    local okEnum = pcall(function()
        model:GetClass():ForEachFunction(function(fn)
            local fname
            pcall(function() fname = fn:GetFName():ToString() end)
            if fname and targetFns[fname] then
                dumpUFunctionSignature(fn)
                printedNames[fname] = true
            end
        end)
    end)
    if not okEnum then
        print("[C2] (ForEachFunction on PMPlayerModel class failed)")
    end

    for fname, _ in pairs(targetFns) do
        if not printedNames[fname] then
            print("[C2]   " .. fname .. " : not found on class")
        end
    end
end

local function probeC3()
    local ps = FindFirstOf("PlayerState_Game_C")
    if not ps or not ps:IsValid() then
        print("[C3] PlayerState_Game_C not found (not in a match?)")
        return
    end
    print("[C3] PlayerState_Game_C class: " .. ps:GetClass():GetFullName())

    local propCount, redirectProps = 0, {}
    local okProps = pcall(function()
        ps:GetClass():ForEachProperty(function(prop)
            local pname, ptype
            pcall(function() pname = prop:GetFName():ToString() end)
            pcall(function() ptype = prop:GetClass():GetFName():ToString() end)
            propCount = propCount + 1
            if pname and matchesRedirect(pname) then
                table.insert(redirectProps, string.format("%s : %s", tostring(pname), tostring(ptype)))
            end
        end)
    end)
    if okProps then
        print(string.format("[C3] properties: %d total", propCount))
        if #redirectProps > 0 then
            for _, s in ipairs(redirectProps) do
                print("[C3]   redirect-shaped prop: " .. s)
            end
        else
            print("[C3]   (no property name matched redirect patterns)")
        end
    else
        print("[C3] (ForEachProperty not available on class in this build)")
    end

    local fnCount, redirectFns = 0, {}
    local okFns = pcall(function()
        ps:GetClass():ForEachFunction(function(fn)
            local fname
            pcall(function() fname = fn:GetFName():ToString() end)
            if fname then
                fnCount = fnCount + 1
                if matchesRedirect(fname) then
                    table.insert(redirectFns, fname)
                end
            end
        end)
    end)
    if okFns then
        print(string.format("[C3] ufunctions: %d total", fnCount))
        if #redirectFns > 0 then
            for _, s in ipairs(redirectFns) do
                print("[C3]   redirect-shaped fn: " .. s)
            end
        else
            print("[C3]   (no UFunction name matched redirect patterns)")
        end
    else
        print("[C3] (ForEachFunction failed)")
    end
end

RegisterKeyBind(Key.F11, function()
    ExecuteInGameThread(function()
        print("=== [Pass2] F11 battery @ " .. os.date("%H:%M:%S") .. " ===")
        probeA1()
        probeA3()
        probeB1()
        probeB2()
        print("=== [Pass2] F11 battery complete ===")
    end)
end)

RegisterKeyBind(Key.F12, function()
    ExecuteInGameThread(function()
        startA2Poll()
    end)
end)

RegisterKeyBind(Key.F9, function()
    ExecuteInGameThread(function()
        print("=== [Pass3] F9 battery @ " .. os.date("%H:%M:%S") .. " ===")
        probeC1()
        probeC2()
        probeC3()
        print("=== [Pass3] F9 battery complete ===")
    end)
end)

-- =============================================================
-- Pass 4 spike: identity delegate-binding viability
-- =============================================================
-- Acceptance prereq for docs/decisions/0001-identity-model.md
-- (R-B, event-driven path). Tests both halves of the design:
--
--   D1 (subscription, preferred): bind a Lua callback to
--       PMPlayerModel.GetMeRequestV1Completed (a
--       MulticastInlineDelegateProperty) and observe whether it
--       fires when GetMeV1 is invoked.
--   D2 (cache fetch, fallback):   call
--       PMPlayerModel:GetCachedMeResponseV1 and verify the cached
--       MeResponse arrives synchronously.
--
-- Outcomes drive the ADR:
--   D1 + D2 work       → R-B accepted, ADR can flip to accepted.
--   D2 only            → R-B falsified at the direct-binding API
--                        layer; spike pivots to a RegisterHook
--                        variant of R-B in a follow-up probe.
--   D1 only            → R-B works but no warm-cache fast-path.
--   Neither            → fall back to R-A polling.
--
-- ============================================================
-- SAFETY + FORENSICS NOTES — read before editing this section.
-- ============================================================
-- Earlier revisions crashed the game with no usable diagnostic:
--
--   Rev 1: auto-attempted D1 binding from a LoopAsync at script
--   load. UE4SS Lua's API for binding to a
--   MulticastInlineDelegateProperty is not documented, and pcall
--   does NOT catch C++ access violations
--   (lua-conventions.mdc, "the C++ AV trap"). Crash during game
--   startup with no chance to react.
--
--   Rev 2: keybind-only with print() before each call. Game
--   crashed cleanly, but UE4SS overwrites UE4SS.log on each
--   launch — and after the crash, UE4SS attaches to
--   CrashReportClient.exe and rewrites the log with PS Scan
--   spam. Forensic data lost.
--
--   Rev 3: keybind-only + persistent OSPlusProbes.log via
--   io.open + flush per call. Worked: pinpointed the killer as
--   `prop:Add(d1Callback)` on a MulticastDelegateProperty
--   userdata. Property access itself is safe; method call on
--   the property userdata native-crashed, meaning UE4SS
--   v3.0.1 doesn't define :Add() on this property type. D2
--   ALSO failed at the Lua level (caught) for all 3 attempted
--   placeholder shapes — UE4SS rejected the struct out-param
--   marshaling.
--
-- This revision (Rev 4) is INTROSPECTION-ONLY for D1: dumps the
-- prop userdata's metatable structure and probes likely method
-- names by READ access (not method invocation). For D2: skips
-- the proven-broken GetCachedMeResponseV1 and instead sweeps
-- across simpler GetCached* UFunctions with multiple arg shapes
-- to characterize the marshaling failure. No method calls on
-- the prop userdata. Output is pure data-gathering.
--
-- DO NOT call methods on the prop userdata in this revision.
-- Wait for Rev 5 (informed by the introspection output).
-- ============================================================

local D1_BOUND_VIA = nil           -- string: which API call succeeded
local D1_FIRE_COUNT = 0
local D1_LAST_TRIGGER_REQID = nil  -- last OutRequestId from GetMeV1

-- Persistent log file for crash forensics. UE4SS doesn't know
-- about this file so it survives across launches. Path is
-- relative to UE4SS's working directory (typically Binaries\Win64).
local PROBE_LOG_PATH = "OSPlusProbes.log"

-- flog = "forensic log": writes to print() AND to OSPlusProbes.log
-- with explicit flush, so a native crash on the next line still
-- leaves this line on disk.
local function flog(msg)
    print(msg)
    pcall(function()
        local f = io.open(PROBE_LOG_PATH, "a")
        if f then
            f:write(string.format("[%s] %s\n", os.date("%H:%M:%S"), msg))
            f:flush()
            f:close()
        end
    end)
end

local function safeStr(v)
    if v == nil then return "<nil>" end
    local s
    if pcall(function() s = v:ToString() end) and type(s) == "string" then
        return s
    end
    return tostring(v)
end

local function d1Callback(succeeded, requestId, meResponse, errorResponse, ...)
    D1_FIRE_COUNT = D1_FIRE_COUNT + 1
    local extra = select("#", ...)
    local pid = "<n/a>"
    pcall(function()
        if meResponse and meResponse.PlayerId then
            pid = safeStr(meResponse.PlayerId)
        end
    end)
    local reqStr = safeStr(requestId)
    local correlated = (D1_LAST_TRIGGER_REQID and reqStr == D1_LAST_TRIGGER_REQID)
        and " [matches last-trigger]" or ""
    flog(string.format(
        "[D1] FIRE #%d succeeded=%s requestId=%q PlayerId=%s extra_args=%d%s",
        D1_FIRE_COUNT,
        tostring(succeeded), reqStr, pid, extra, correlated))
end

-- D2 (Rev 4): characterize the marshaling failure across multiple
-- GetCached* UFunctions. Rev 3 proved GetCachedMeResponseV1 fails
-- at the Lua level for all 3 shapes we tried — but every shape
-- failed with "no table was on the stack" (table out-param error)
-- or "expected 2 parameters, received 0" (no-args). We now sweep
-- a SIMPLER UFunction (GetCachedLinkCodeV1: Bool out + Str out,
-- no struct) to test if the failure is struct-specific or affects
-- ALL out-params, plus GetCachedPlayerPublicProfile (same shape
-- as MeResponseV1 but smaller struct). Each call is pcall-wrapped
-- (UFunction calls error cleanly at the Lua level — only D1 has
-- crashed natively).
local function d2CacheFetch(model)
    local function tryCall(fname, args, label)
        flog(string.format("[D2] >>> ATTEMPT %s%s", fname, label))
        local results = {}
        local ok, err = pcall(function()
            local fn = model[fname]
            if fn == nil then
                error("function not exposed on model")
            end
            local r = { fn(model, table.unpack(args, 1, args.n or #args)) }
            for i, v in ipairs(r) do results[i] = v end
        end)
        if ok then
            flog(string.format("[D2]   OK %s%s returned %d values", fname, label, #results))
            for i, v in ipairs(results) do
                local extra = ""
                if type(v) == "userdata" or type(v) == "table" then
                    pcall(function()
                        if v.PlayerId then extra = " PlayerId=" .. safeStr(v.PlayerId) end
                    end)
                end
                flog(string.format("[D2]     [%d] %s = %s%s",
                    i, type(v), safeStr(v), extra))
            end
            return true
        else
            flog(string.format("[D2]   FAIL %s%s: %s", fname, label, tostring(err)))
            return false
        end
    end

    -- A. Simplest: Str out-param (no struct involved at all)
    flog("[D2] --- A. GetCachedLinkCodeV1 (Bool out, Str out) ---")
    tryCall("GetCachedLinkCodeV1", { false, nil },          "(false, nil)")
    tryCall("GetCachedLinkCodeV1", { false, "" },           '(false, "")')
    tryCall("GetCachedLinkCodeV1", table.pack(false),       "(false)")
    tryCall("GetCachedLinkCodeV1", table.pack(),            "()")

    -- B. Smaller struct out-param (PlayerPublicProfile, parent of MeResponseV1)
    flog("[D2] --- B. GetCachedPlayerPublicProfile (Bool out, Struct out) ---")
    tryCall("GetCachedPlayerPublicProfile", { false, nil }, "(false, nil)")
    tryCall("GetCachedPlayerPublicProfile", { false, {} },  "(false, {})")
    tryCall("GetCachedPlayerPublicProfile", table.pack(false), "(false)")
    tryCall("GetCachedPlayerPublicProfile", table.pack({}), "({})")
    tryCall("GetCachedPlayerPublicProfile", table.pack(),   "()")

    -- (Skipping GetCachedMeResponseV1 — Rev 3 proved it fails
    -- with the same shapes; no new info to gain from re-running.)

    flog("[D2] --- sweep complete ---")
    return nil, nil
end

-- D1 (Rev 4): INTROSPECTION ONLY. Rev 3 proved `prop:Add(cb)`
-- native-crashes the game (last log line was the >>> ATTEMPT
-- with no return marker). Property access itself is safe. Before
-- we try ANY method call on the prop userdata in a future
-- revision, we need to know what methods actually exist on it.
--
-- Strategy: dump the userdata's metatable + __index, then
-- READ-PROBE a list of likely method names (read access goes
-- through __index but doesn't invoke the method). No method
-- call is performed in this revision.

local LIKELY_DELEGATE_METHODS = {
    "Add", "AddUnique", "AddDynamic", "AddUFunction",
    "AddStatic", "AddRaw", "AddSP", "AddLambda",
    "Bind", "BindUFunction", "BindDynamic", "BindLambda",
    "Broadcast", "Clear", "Remove", "RemoveAll", "RemoveDynamic",
    "Unbind", "IsBound", "IsBoundToObject",
    "GetUObject", "GetFName", "GetName", "GetClass",
    "GetSignature", "GetType", "GetAllFunctions",
}

local function dumpUserdataInterface(label, ud)
    flog(string.format("[%s] introspect: type=%s tostring=%s",
        label, type(ud), tostring(ud)))

    flog(string.format("[%s] >>> getmetatable(ud)", label))
    local ok_mt, mt = pcall(getmetatable, ud)
    if not ok_mt then
        flog(string.format("[%s]   getmetatable errored: %s", label, tostring(mt)))
        return
    end
    if mt == nil then
        flog(string.format("[%s]   no metatable", label))
        return
    end
    flog(string.format("[%s]   metatable type=%s tostring=%s",
        label, type(mt), tostring(mt)))

    -- Direct keys on the metatable itself (e.g., __index, __call, __gc, __tostring)
    flog(string.format("[%s] >>> pairs(mt) (direct mt keys)", label))
    local mt_count = 0
    pcall(function()
        for k, v in pairs(mt) do
            flog(string.format("[%s]   mt[%s] = %s", label, tostring(k), type(v)))
            mt_count = mt_count + 1
        end
    end)
    flog(string.format("[%s]   mt direct keys total: %d", label, mt_count))

    -- __index — most methods live here when it's a table
    local idx
    pcall(function() idx = mt.__index end)
    flog(string.format("[%s] mt.__index is %s", label, type(idx)))
    if type(idx) == "table" then
        flog(string.format("[%s] >>> pairs(mt.__index)", label))
        local idx_count = 0
        pcall(function()
            for k, v in pairs(idx) do
                flog(string.format("[%s]   __index[%s] = %s",
                    label, tostring(k), type(v)))
                idx_count = idx_count + 1
            end
        end)
        flog(string.format("[%s]   __index keys total: %d", label, idx_count))
    end
end

local function probeLikelyMethods(label, ud)
    flog(string.format("[%s] >>> read-probe %d likely method names (no calls)",
        label, #LIKELY_DELEGATE_METHODS))
    local found = {}
    for _, name in ipairs(LIKELY_DELEGATE_METHODS) do
        local m
        local ok, err = pcall(function() m = ud[name] end)
        if not ok then
            flog(string.format("[%s]   ud.%s read errored: %s",
                label, name, tostring(err)))
        elseif m == nil then
            -- Skip nil entries to keep the log focused on positives.
        else
            flog(string.format("[%s]   ud.%s = %s (FOUND)",
                label, name, type(m)))
            table.insert(found, name)
        end
    end
    if #found == 0 then
        flog(string.format("[%s]   no likely methods found via read-probe", label))
    else
        flog(string.format("[%s]   FOUND methods (call candidates for Rev 5): %s",
            label, table.concat(found, ", ")))
    end
end

local function tryBinding(model)
    flog("[D1] step 1 >>> ATTEMPT property access: model.GetMeRequestV1Completed")
    local prop
    local okProp, propErr = pcall(function() prop = model.GetMeRequestV1Completed end)
    if not okProp then
        flog("[D1] step 1 returned (Lua error caught): " .. tostring(propErr))
        return nil
    end
    flog("[D1] step 1 returned (no Lua error); prop="
        .. tostring(prop) .. " (lua-type=" .. type(prop) .. ")")
    if prop == nil then
        flog("[D1] property is nil; cannot introspect")
        return nil
    end

    -- Rev 4: introspect. NO method calls. Rev 3 proved prop:Add(cb)
    -- native-crashes; we won't repeat it. Rev 5 will pick a method
    -- from the introspection output below.
    flog("[D1] step 2 >>> dump prop userdata's metatable structure")
    dumpUserdataInterface("D1.prop", prop)

    flog("[D1] step 3 >>> read-probe likely delegate-method names on prop")
    probeLikelyMethods("D1.prop", prop)

    -- Bonus: also introspect the model UObject — maybe the binding
    -- API lives on the model rather than on the property userdata
    -- (e.g., `model:BindMeRequestV1Completed(cb)` style). Read-only.
    flog("[D1] step 4 >>> probe model-level binding methods (read-only)")
    local MODEL_LIKELY = {
        "GetMeRequestV1Completed",       -- already known to work
        "BindMeRequestV1Completed",
        "AddMeRequestV1Completed",
        "OnMeRequestV1Completed",
        "RegisterMeRequestV1Completed",
    }
    for _, name in ipairs(MODEL_LIKELY) do
        local v
        local ok, err = pcall(function() v = model[name] end)
        if not ok then
            flog(string.format("[D1.model]   model.%s read errored: %s",
                name, tostring(err)))
        elseif v == nil then
            -- skip
        else
            flog(string.format("[D1.model]   model.%s = %s (lua-type=%s)",
                name, tostring(v), type(v)))
        end
    end

    flog("[D1] introspection complete. NO bind attempted in Rev 4.")
    flog("[D1] (Rev 5 will pick a binding API from the FOUND methods above.)")
    return nil  -- explicit: no bind succeeded; D1 trigger will be skipped
end

local function probeD()
    flog("=== [Pass4] D battery @ " .. os.date("%H:%M:%S") .. " ===")
    flog("[Pass4] step 0 >>> ATTEMPT FindFirstOf('PMPlayerModel')")
    local model = FindFirstOf("PMPlayerModel")
    if not model or not model:IsValid() then
        flog("[Pass4] PMPlayerModel not found — login flow not initialized? (try again post-login)")
        flog("=== [Pass4] D battery aborted ===")
        return
    end
    flog("[Pass4] PMPlayerModel: " .. model:GetClass():GetFullName())

    -- D2 first: known-safer; we always get D2 evidence even if D1 dies.
    local d2Shape, d2Pid = d2CacheFetch(model)

    -- D1: bind, then trigger.
    if not D1_BOUND_VIA then
        D1_BOUND_VIA = tryBinding(model)
    else
        flog("[D1] already bound from previous F8 press via " .. D1_BOUND_VIA)
    end

    -- Trigger only if some bind succeeded — otherwise GetMeV1 just
    -- spams a request with no observer.
    if D1_BOUND_VIA then
        flog("[D1] step 4 >>> ATTEMPT model:GetMeV1(false, nil) (force-trigger)")
        local triggerOk, triggerErr = pcall(function()
            local wasSent, outReqId = model:GetMeV1(false, nil)
            local idStr = safeStr(outReqId)
            D1_LAST_TRIGGER_REQID = idStr
            flog(string.format(
                "[D1] GetMeV1 triggered: WasSent=%s OutRequestId=%q",
                tostring(wasSent), idStr))
            if wasSent == false then
                flog("[D1]   (WasSent=false — short-circuited; delegate may NOT fire this run; press F8 again ~30s later)")
            end
        end)
        if not triggerOk then
            flog("[D1] GetMeV1 trigger failed (Lua-level): " .. tostring(triggerErr))
        end
    else
        flog("[D1] skipping GetMeV1 trigger (no successful bind)")
    end

    flog(string.format(
        "[Pass4] summary: D1_bound=%s D1_fires=%d D2_shape=%s D2_PlayerId=%s",
        tostring(D1_BOUND_VIA), D1_FIRE_COUNT,
        tostring(d2Shape), tostring(d2Pid)))
    flog("[Pass4] (delegate fires log asynchronously; re-check log after a few seconds for [D1] FIRE lines)")
    flog("=== [Pass4] D battery complete ===")
end

RegisterKeyBind(Key.F8, function()
    ExecuteInGameThread(function()
        probeD()
    end)
end)

-- Open with a session marker so the user can find this run's
-- block in OSPlusProbes.log even after multiple launches.
flog(string.format(
    "==== [OSPlusProbes] session start %s — F11 Pass2, F12 A2 poll, F9 Pass3, F8 Pass4 Rev 4 (INTROSPECTION-ONLY, no method calls on prop, persistent log to %s) ====",
    os.date("%Y-%m-%d %H:%M:%S"), PROBE_LOG_PATH))
