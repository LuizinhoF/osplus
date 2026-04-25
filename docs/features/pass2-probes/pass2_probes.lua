--[[
    Feasibility Pass 2 + Pass 3 + Pass 4 + Pass 5 probes for
    docs/features/in-game-profile-mvp.md.

    NOT shipped with OSPlus. Installed as a separate UE4SS mod named
    `OSPlusProbes`. See docs/features/pass2-probes/README.md for install.

    Keybinds:
      F11 — Pass 2 one-shot snapshot battery: A1 + A3 + B1 + B2
      F12 — Pass 2 A2 polling: PlayerNamePrivate every 500ms for 15s
      F9  — Pass 3 battery: C1 (Pawn components) + C2 (PMPlayerModel
            UFunction signatures) + C3 (PlayerState_Game_C property
            + UFunction dump)
      F8  — Pass 4 spike (ADR 0001 acceptance prereq, retrospective):
            D2 = cache fetch (PMPlayerModel:GetCachedMeResponseV1)
            D1 = subscription (PMPlayerModel.GetMeRequestV1Completed
                 multicast bind via Rev-4 introspection-only)
      F7  — Pass 5 micro-probe (BP-path viability for ADR 0001 R-B):
            E1 = bind a nonexistent FName via prop:Add(model, fake)
                 to see whether Add validates name resolution.
            E2 = (only if E1 errors) bind a real UFunction with
                 truncated signature via prop:Add(model, "GetDisplayNameV1")
                 to see whether Add validates signature.
            Each bind is immediately Remove()'d so nothing lingers.
      F6  — Pass 5 step 2 BP-fire test (run FIRST in any session):
            E3 = locate ModActor, register UE4SS RegisterHook on
                 ModActor.OnMeResponseFired (a 0-param BP UFunction
                 the user added), and bind it to
                 PMPlayerModel.GetMeRequestV1Completed.
                 No force-trigger — :GetMeV1 hits the same
                 out-param marshaling bug as the GetCached* family.
                 Hook+bind LEFT IN PLACE for natural fires.
      F4  — Pass 5 step 2.5 broadcast bind (run AFTER F6):
            E5 = bind the SAME OnMeResponseFired UFunction to all
                 40 PMPlayerModel multicast delegates at once
                 (loadout/profile/character/region/etc). Whichever
                 fires first triggers our hook. Validates substrate
                 without needing to wait for natural MeRequestV1.
                 Hook can't tell us WHICH delegate fired — that's
                 fine for the validation question.
      F5  — Pass 5 parallel exploration:
            E4 = enumerate ALL UProperties on PMPlayerModel,
                 read each defensively, flag identity-relevant
                 names with ★. Tests the deferred Pass-4 question:
                 is identity available as a direct UProperty
                 (bypassing the broken GetCached* UFunctions)?
      F3  — Pass 5 step 4 ground-truth probe (iter 2):
            E6 = walk PMPlayerModel SuperStruct chain (up to depth 5),
                 log per-class total UFunction count + first 20 names,
                 detect delegate signatures via FUNC_Delegate flag
                 (0x100000) AND __DelegateSignature suffix as
                 independent signals. Iter 1 returned 0 with no
                 unfiltered total; iter 2 makes the search empirical.
                 Also disambiguates the F6 FindFirstOf result
                 (instance vs class) via :GetFullName() token
                 + FindAllOf count.
      F2  — Pass 5 step 5 controlled-broadcast probe (run AFTER F6):
            E7 = three phases.
                 Phase A: pairs(getmetatable(prop)) on a PMPlayerModel
                          delegate property — looking for any
                          undocumented signature-accessor methods.
                 Phase B: StaticFindObject sweep across class-scoped,
                          package-scoped, and shared-signature paths.
                 Phase C: prop:Broadcast() with 0 args + GetBindings()
                          persistence check. The 0-arg Broadcast()
                          errored with a leaked signature path:
                          /Script/Prometheus.MeRequestV1Completed
                          __DelegateSignature — proving signatures are
                          PACKAGE-scoped and the delegate type name
                          drops the 'Get' prefix from the property.
      F1  — Pass 5 step 6 signature-fetch + Broadcast-with-args
            (run AFTER F6 — depends on cached ModActor/hook):
            E8 = three phases.
                 Phase A: StaticFindObject the now-known signature
                          path, ForEachProperty to dump full param
                          list (count + names + types + flags).
                          Resolves the signature mystery for ADR 0001.
                 Phase B: Add/Remove cycle with GetBindings() between
                          each call. Tests whether GetBindings tracks
                          our cross-actor BP-target binding (resolves
                          the F2/E7 "Add OK but GetBindings == 0"
                          discrepancy).
                 Phase C: Broadcast() with progressive arg counts
                          1..NumParams, defaults constructed from the
                          Phase-A signature. DECISIVE substrate test:
                          if any arity makes our 0-arg hook fire, the
                          binding IS there + dispatch works (no
                          fire-time silent-skip), and ADR 0001 R-B is
                          unblocked at the substrate level.
      F10 — Pass 5 step 7 E8 Phase D bind shape variations
            (run AFTER F6): D0 prop UClass introspection, D1
            pairs(prop), D2 API-surface enumeration (~25 method
            names), D3 same-actor bind, D4 explicit FName bind,
            D5 :Bind() if present, D6 cross-actor reconfirm.
            Triangulated F1/E8's verdict: prop:Add() is a
            UNIVERSAL silent no-op on this UE4SS build. Pivoted
            ADR 0001 R-B from "ModActor BP wrapper for delegate
            binding" to "RegisterHook on engine-side originating
            UFunction" (UE4SS Issue #455 maintainer recommendation).
      NUM_SIX — Pass 6 v2 E9 RegisterHook discovery probe (summary key).
            Install runs at MODULE LOAD via NotifyOnNewObject (+ a
            FindFirstOf one-shot for instances that already exist):
            mass-hooks every UFunction on PMPlayerModel (44 known
            from F3 iter 2) AND PMIdentitySubsystem (35 confirmed
            by Pass 6 v1) with a per-UFunction signature dump.
            v1 keypress install missed the natural identity flow
            (MeRequestV1 only fires at login, before any user can
            press a key — see [E9.boot] log block). v2 NUM_SIX
            keypress is now PURE SUMMARY: dumps install state,
            per-UFunction fire counts, and ambient PlayerId.
            Each fire-time callback dumps the unwrapped parameter
            values + an ambient PlayerId snapshot from
            PMPlayerPublicProfile. Output identifies which engine
            UFunction(s) ADR 0001 R-B should hook.

    Output: Binaries/Win64/UE4SS.log (search for [A1], [A2], [A3],
    [B1], [B2], [C1], [C2], [C3], [D1], [D2], [Pass4], [E1], [E2],
    [E3], [E3.HOOK], [E4], [E5], [E6], [E7], [E8], [E8.D], [E9],
    [E9.boot], [E9.A], [E9.B], [E9.HOOK], [Pass5], [Pass6]) and
    any mirrored external console window.
    Some UE4SS installs place the log under Binaries/Win64/ue4ss/
    — check yours.

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

-- =============================================================
-- Pass 5 micro-probe: Add() validation level (BP-path viability)
-- =============================================================
-- Builds on Pass-4 Rev-4 introspection, which discovered that the
-- six real methods on the GetMeRequestV1Completed prop userdata
-- are: Add, Remove, Clear, Broadcast, GetFName, GetClass — and
-- that prop:Add(UObject, FName-or-string) is the documented
-- signature (UE4SS docs + PR #1073). Pass-4 stopped at
-- introspection: it never actually called Add().
--
-- Pass 5's question: does Add() validate the FName resolves to
-- a real UFunction on the target — and, if so, does it ALSO
-- validate the signature matches the delegate's signature?
--
-- This question is the critical input to ADR 0001's R-B path.
-- The delegate's signature is
--   (Succeeded: Bool, RequestId: Str, MeResponse: MeResponseV1,
--    ErrorResponse: ErrorResponse)
-- and MeResponseV1 + ErrorResponse are /Script/Prometheus
-- USTRUCTs not visible to our UE editor. So a BP UFunction we
-- author in our project CANNOT have parameters of those exact
-- types. Whether Add accepts a wrong-signature BP UFunction
-- determines whether step 2 (BP work) is straightforward or
-- structurally blocked:
--
--   (a) Add silently accepts a non-existent name        →
--       Add does no validation at bind. Step 2 can use any
--       signature; we just need ANY BP UFunction.
--
--   (b) Add rejects nonexistent names but accepts a real
--       UFunction with wrong/truncated signature         →
--       Add validates name only. Step 2 can use a truncated
--       BP signature (e.g. OnMeResponse(Succeeded: Bool)).
--       Whether the engine does anything useful at fire
--       time with a truncated UFunction is a separate test
--       deferred to step 2.
--
--   (c) Add rejects a real UFunction with wrong signature →
--       Add validates signature too. BP-from-our-project is
--       structurally blocked — pivot to a UE4SS C++ mod
--       (or pursue some way to expose Prometheus types to
--       the editor, which is unlikely).
--
-- DESIGN: minimum risk.
--   - Bind ONE name at a time, log the result, immediately
--     Remove it before binding the next. Nothing persists
--     across the F7 invocation.
--   - Do NOT trigger fire (no model:GetMeV1 call). The fire
--     test is risky on a wrong-shape binding because the
--     engine packs delegate args into a buffer matching
--     the delegate's layout and calls our UFunction reading
--     from that buffer at the UFunction's parameter offsets.
--     Wrong sizes = arbitrary memory reads. Defer fire to
--     step 2 with a controlled BP UFunction.
--   - flog() bracketing on every native call so a crash
--     leaves the killer line on disk.
-- =============================================================

local PROBE5_FAKE_FNAME = "DefinitelyNonexistentXYZ_Probe5"
local PROBE5_REAL_FNAME = "GetDisplayNameV1"  -- known real UFn on PMPlayerModel; signature (OutDisplayName: Str&) -> Bool

local function tryAddBind(prop, target, fname, label)
    flog(string.format("[%s] >>> ATTEMPT prop:Add(model, %q)", label, fname))
    flog(string.format("[%s]   (if game crashes, last on-disk log line is this ATTEMPT)", label))
    local addRet
    local addOk, addErr = pcall(function() addRet = prop:Add(target, fname) end)
    if addOk then
        flog(string.format("[%s]   BIND ACCEPTED (Add returned: %s, lua-type=%s)",
            label, tostring(addRet), type(addRet)))
        return true, addRet
    end
    flog(string.format("[%s]   BIND REJECTED: %s", label, tostring(addErr)))
    return false, addErr
end

local function tryRemove(prop, target, fname, label)
    flog(string.format("[%s] >>> prop:Remove(model, %q) (cleanup)", label, fname))
    local rmRet
    local rmOk, rmErr = pcall(function() rmRet = prop:Remove(target, fname) end)
    if rmOk then
        flog(string.format("[%s]   Remove returned: %s (lua-type=%s)",
            label, tostring(rmRet), type(rmRet)))
    else
        flog(string.format("[%s]   Remove failed: %s (binding may persist until login flow tear-down)",
            label, tostring(rmErr)))
    end
end

local function probeE()
    flog("=== [Pass5] E micro-probe @ " .. os.date("%H:%M:%S") .. " ===")

    flog("[Pass5] step 0 >>> ATTEMPT FindFirstOf('PMPlayerModel')")
    local model = FindFirstOf("PMPlayerModel")
    if not model or not model:IsValid() then
        flog("[Pass5] PMPlayerModel not found — login flow not initialized? (try post-login)")
        flog("=== [Pass5] E aborted ===")
        return
    end
    flog("[Pass5] PMPlayerModel: " .. model:GetClass():GetFullName())

    flog("[Pass5] step 1 >>> ATTEMPT property access: model.GetMeRequestV1Completed")
    local prop
    local okProp, propErr = pcall(function() prop = model.GetMeRequestV1Completed end)
    if not okProp or prop == nil then
        flog("[Pass5] property access failed: " .. tostring(propErr))
        flog("=== [Pass5] E aborted ===")
        return
    end
    flog("[Pass5] prop accessed OK; lua-type=" .. type(prop))

    flog("[E1] --- bind with NONEXISTENT UFunction name ---")
    local e1Bound = tryAddBind(prop, model, PROBE5_FAKE_FNAME, "E1")
    if e1Bound then
        tryRemove(prop, model, PROBE5_FAKE_FNAME, "E1")
        flog("[E1] FINDING: Add does NOT validate FName → fully permissive at bind time.")
        flog("[E1] CONCLUSION → outcome (a): step 2 (BP work) can proceed; any BP UFunction signature will bind.")
        flog("[E1]   Open question for step 2: does the ENGINE fire a wrong-shape UFunction at runtime, or silently skip it?")
        flog("[E1]   (Answer that with a controlled BP UFunction in the editor — safer than firing into garbage here.)")
        flog("=== [Pass5] E complete (E2 not needed) ===")
        return
    end

    flog("[E1] FINDING: Add validates FName resolution at bind time.")
    flog("[E1] PROCEEDING to E2 to test whether Add ALSO validates signature.")

    flog(string.format("[E2] --- bind with REAL UFunction (%q) but wrong signature ---", PROBE5_REAL_FNAME))
    flog("[E2]   target signature: (OutDisplayName: Str&) -> Bool   (1 param)")
    flog("[E2]   delegate signature: (Bool, Str, MeResponseV1, ErrorResponse) (4 params)")
    local e2Bound = tryAddBind(prop, model, PROBE5_REAL_FNAME, "E2")
    if e2Bound then
        tryRemove(prop, model, PROBE5_REAL_FNAME, "E2")
        flog("[E2] FINDING: Add validates name only, NOT signature.")
        flog("[E2] CONCLUSION → outcome (b): step 2 (BP work) can use a truncated-signature BP UFunction.")
        flog("[E2]   Open question for step 2: does the ENGINE actually invoke a truncated UFunction at fire time,")
        flog("[E2]   or does it skip / crash? Answer with a controlled BP UFunction in the editor.")
    else
        flog("[E2] FINDING: Add validates signature at bind time.")
        flog("[E2] CONCLUSION → outcome (c): BP-from-our-project is structurally BLOCKED.")
        flog("[E2]   Reason: the delegate's MeResponseV1 + ErrorResponse types live in /Script/Prometheus,")
        flog("[E2]   which our UE editor doesn't see. ADR 0001 R-B path needs to pivot — likely UE4SS C++ mod.")
    end

    flog("=== [Pass5] E complete ===")
end

RegisterKeyBind(Key.F7, function()
    ExecuteInGameThread(function() probeE() end)
end)

-- =============================================================
-- Pass 5 step 2 (E3): BP-fire validation via F6
-- =============================================================
-- After E1 confirmed Add() is permissive at bind, the open
-- question is: does the engine actually INVOKE our wrong-shape
-- BP UFunction when the delegate fires?
--
-- This probe assumes the OSPlus mod's ModActor has been updated
-- with a UFunction `OnMeResponseFired`:
--   - Inputs: NONE (cheapest possible signature; 0 vs delegate's 4)
--   - Body: a Print String "[OSPlus] OnMeResponseFired native-fired"
--     with "Print to Log" enabled
-- (Only the UFunction NAME matters for binding — the parameter
--  count is what we're testing at fire time.)
--
-- Two-layer detection:
--   1. UE4SS RegisterHook (post-hook) on the BP UFunction: fires
--      whenever ProcessEvent dispatches OnMeResponseFired. This
--      tells us "engine reached the UFunction" independent of
--      whether the BP body executed.
--   2. Print String in the BP body: tells us "BP body actually
--      ran". UE4SS forwards Print String to UE4SS.log when
--      "Print to Log" is enabled in the BP node.
--
-- Outcomes:
--   (i)   Both fire        → engine fires AND BP body runs.
--                            Event-driven path FULLY VALIDATED.
--   (ii)  Only hook fires  → engine reaches UFunction but BP body
--                            doesn't run. Surprising; would
--                            indicate the BP VM rejects truncated
--                            args mid-dispatch.
--   (iii) Neither fires    → engine silently no-ops on signature
--                            mismatch. Truncated BP UFunction is
--                            a dead end; pivot needed.
--   (iv)  Crash on fire    → fire-time signature validation is
--                            fatal. Pass 4-style forensics flow;
--                            last on-disk line is the killer.
--
-- DESIGN: idempotent (Remove + Add at start of every F6 press so
-- bindings don't accumulate across presses). Hook registered
-- once per session. Binding LEFT IN PLACE after trigger so
-- natural delegate fires (UI nav, etc.) also fire our hook
-- and BP body — broader observation surface.
-- =============================================================

local E3_HOOK_REGISTERED = false
local E3_HOOK_FIRES = 0
local E3_MODACTOR = nil  -- cached reference; set when Lua_ModInitialized fires

RegisterCustomEvent("Lua_ModInitialized", function(modActor)
    pcall(function()
        if modActor and modActor:get() and modActor:get():IsValid() then
            E3_MODACTOR = modActor:get()
            flog("[E3.init] cached OSPlus ModActor: " .. E3_MODACTOR:GetClass():GetFullName())
        else
            flog("[E3.init] Lua_ModInitialized fired but ModActor invalid")
        end
    end)
end)

local function probeE3()
    flog("=== [Pass5] E3 BP-fire test @ " .. os.date("%H:%M:%S") .. " ===")

    -- step 0: locate ModActor (cached or FindFirstOf fallback)
    local modActor = E3_MODACTOR
    if not modActor or not modActor:IsValid() then
        flog("[E3] cached ModActor missing/invalid; trying FindFirstOf fallback")
        for _, candidate in ipairs({"ModActor_C", "ModActor"}) do
            local found = FindFirstOf(candidate)
            if found and found:IsValid() then
                modActor = found
                E3_MODACTOR = found
                flog(string.format("[E3] FindFirstOf(%q): %s",
                    candidate, found:GetClass():GetFullName()))
                break
            end
        end
    else
        flog("[E3] using cached ModActor: " .. modActor:GetClass():GetFullName())
    end
    if not modActor or not modActor:IsValid() then
        flog("[E3] could not locate OSPlus ModActor — is OSPlus mod loaded?")
        flog("=== [Pass5] E3 aborted ===")
        return
    end

    -- step 1: verify OnMeResponseFired UFunction exists on the ModActor class
    flog("[E3] step 1 >>> verify OnMeResponseFired UFunction exists on class")
    local fnFound, fnNumParms = false, nil
    pcall(function()
        modActor:GetClass():ForEachFunction(function(fn)
            local fname
            pcall(function() fname = fn:GetFName():ToString() end)
            if fname == "OnMeResponseFired" then
                fnFound = true
                pcall(function() fnNumParms = fn.NumParms end)
            end
        end)
    end)
    if not fnFound then
        flog("[E3] OnMeResponseFired NOT found on ModActor class")
        flog("[E3]   → BP may not have been recooked / repacked / redeployed correctly")
        flog("[E3]   → check the .pak mtime in <GameDir>/.../LogicMods/OSPlus.pak")
        flog("[E3]   → run F11 to see ModActor's full UFunction list, or use the GUI dumper")
        flog("=== [Pass5] E3 aborted ===")
        return
    end
    flog(string.format("[E3]   FOUND OnMeResponseFired (NumParms=%s)", tostring(fnNumParms)))

    -- step 2: register hook (one-time per session; lazy because BP class
    -- may not be loaded at script-load time)
    if not E3_HOOK_REGISTERED then
        local classFullName = modActor:GetClass():GetFullName()
        -- GetFullName returns e.g. "BlueprintGeneratedClass /Game/Mods/OSPlus/ModActor.ModActor_C"
        local classPath = classFullName:match("(/Game/[^%s]+)")
        if classPath then
            local hookPath = classPath .. ":OnMeResponseFired"
            flog("[E3] step 2 >>> RegisterHook(" .. hookPath .. ")")
            local hookOk, hookErr = pcall(function()
                RegisterHook(hookPath, function(Context)
                    E3_HOOK_FIRES = E3_HOOK_FIRES + 1
                    -- log cap: first 5 fires verbose, then every 20th
                    -- (E5 binds this UFunction to ALL 40 PMPlayerModel
                    -- delegates — a chatty one could otherwise spam)
                    if E3_HOOK_FIRES <= 5 or E3_HOOK_FIRES % 20 == 0 then
                        local self
                        pcall(function() self = Context:get() end)
                        flog(string.format("[E3.HOOK] FIRE #%d — engine invoked OnMeResponseFired (self=%s)",
                            E3_HOOK_FIRES, tostring(self)))
                    end
                end)
                E3_HOOK_REGISTERED = true
            end)
            if not hookOk then
                flog("[E3]   hook registration failed: " .. tostring(hookErr))
                flog("[E3]   (continuing — Print String in BP body remains as fallback signal)")
            else
                flog("[E3]   hook registered OK")
            end
        else
            flog("[E3] could not extract /Game/ path from class full name: " .. classFullName)
            flog("[E3]   (continuing without hook — Print String fallback only)")
        end
    else
        flog(string.format("[E3] step 2 >>> hook already registered; fires so far this session: %d",
            E3_HOOK_FIRES))
    end

    -- step 3: get model + delegate prop
    flog("[E3] step 3 >>> ATTEMPT FindFirstOf('PMPlayerModel')")
    local model = FindFirstOf("PMPlayerModel")
    if not model or not model:IsValid() then
        flog("[E3] PMPlayerModel not found — try post-login")
        flog("=== [Pass5] E3 aborted ===")
        return
    end
    local prop
    local okProp, propErr = pcall(function() prop = model.GetMeRequestV1Completed end)
    if not okProp or prop == nil then
        flog("[E3] property access failed: " .. tostring(propErr))
        flog("=== [Pass5] E3 aborted ===")
        return
    end

    -- step 4: idempotent rebind (Remove old + Add fresh) so multiple F6
    -- presses don't accumulate bindings.
    flog("[E3] step 4a >>> prop:Remove(modActor, 'OnMeResponseFired') (clear any prior)")
    pcall(function() prop:Remove(modActor, "OnMeResponseFired") end)
    flog("[E3] step 4b >>> ATTEMPT prop:Add(modActor, 'OnMeResponseFired')")
    flog("[E3]   (if game crashes here, last on-disk log line is this ATTEMPT)")
    local bindOk, bindErr = pcall(function() prop:Add(modActor, "OnMeResponseFired") end)
    if not bindOk then
        flog("[E3]   BIND FAILED at Lua level: " .. tostring(bindErr))
        flog("=== [Pass5] E3 aborted ===")
        return
    end
    flog("[E3]   BIND ACCEPTED")

    -- step 5: NO force-trigger.
    --
    -- We previously called model:GetMeV1(false, nil) here. It hits the
    -- exact same out-param marshaling failure as the GetCached* family
    -- (see docs/learnings/ue4ss-outparam-marshaling-failure.md). Trigger
    -- is unreachable from Lua. Run F4 (E5) afterwards to broadcast-bind
    -- this same UFunction to the other 39 delegates; UI nav (loadout
    -- screen, character select, profile screen) provokes natural fires
    -- on any of them, which exercises the same code path.
    flog("[E3] step 5 >>> SIGNALS TO WATCH (until session end):")
    flog("[E3]   '[E3.HOOK] FIRE #N' in OSPlusProbes.log → engine reached the UFunction")
    flog("[E3]   '[OSPlus] OnMeResponseFired native-fired' in UE4SS.log → BP body executed")
    flog("[E3]   both     = outcome (i):  event-driven path FULLY VALIDATED")
    flog("[E3]   only hook= outcome (ii): BP VM rejects truncated args mid-dispatch")
    flog("[E3]   neither  = outcome (iii): engine silently no-ops on signature mismatch")
    flog(string.format("[E3] hook fire count BEFORE this F6 press: %d", E3_HOOK_FIRES))
    flog("[E3] (binding LEFT IN PLACE — natural delegate fires exercise the path)")
    flog("[E3] NEXT: press F4 to broadcast-bind to all 40 delegates, then nav UI.")
    flog("=== [Pass5] E3 complete ===")
end

RegisterKeyBind(Key.F6, function()
    ExecuteInGameThread(function() probeE3() end)
end)

-- =============================================================
-- Pass 5 step 2.5 (E5): broadcast-bind probe via F4
-- =============================================================
-- Why this exists:
--   F6 (E3) confirmed bind succeeds and the hook is registered,
--   but couldn't observe a fire because:
--     1. Force-trigger via model:GetMeV1(false, nil) hits the
--        same out-param marshaling bug as the GetCached* family
--        (see ue4ss-outparam-marshaling-failure.md).
--     2. Natural MeRequestV1 fires haven't been observed during
--        main-menu activity — only at login, before our bind
--        was placed.
--
-- Key insight from F5 (E4): PMPlayerModel exposes 40
-- MulticastInlineDelegateProperty fields, ALL of the SAME UE
-- type. Whatever the engine does at fire time for one delegate,
-- it does for all. So validating the substrate doesn't require
-- triggering MeRequestV1 specifically — ANY of the 40 firing
-- with our bound BP UFunction is sufficient evidence that the
-- truncated-signature dispatch works.
--
-- This probe binds OnMeResponseFired (the same 0-param BP
-- UFunction E3 used) to all 40 delegates at once. UI navigation
-- (loadout screen → fetches loadouts; character select → fetches
-- characters; profile screen → fetches profile) then provokes
-- natural fires on whichever *RequestCompleted / *Changed
-- delegates the screen exercises.
--
-- Limitation by design: the hook can't tell us which delegate
-- fired (same UFunction = same hook). For the validation
-- question that doesn't matter — any fire = substrate works.
-- For future feature use we'd assign a distinct BP UFunction
-- per delegate (out of scope for this spike).
--
-- Names below are copied verbatim from F5's enumeration on
-- 2026-04-25 — all 40 confirmed present at that time.
-- =============================================================

local E5_TARGET_DELEGATES = {
    "AcceptEulaV1RequestCompleted",
    "CreateLinkCodeV1RequestCompleted",
    "SubmitLinkCodeV1RequestCompleted",
    "ConfirmLinkV1RequestCompleted",
    "GetLinkOptionsV1RequestCompleted",
    "AccountLinkCodeChanged",
    "AccountLinkOptionsChanged",
    "PlayerLoadoutsV2RequestCompleted",
    "PlayerLoadoutsV2Changed",
    "PlayerLoadoutPresetsV1RequestCompleted",
    "UpdatePlayerCharacterLoadoutPresetsV1RequestCompleted",
    "PlayerLoadoutPresetsV1Changed",
    "UpdatePlayerSocialUrlV1RequestCompleted",
    "PlayerMatchmakingConstraintsV1RequestCompleted",
    "UpdatePlayerMatchmakingConstraintsV1RequestCompleted",
    "UpdatePlayerCharacterLoadoutPresetsRequestCompleted",
    "PlayerMatchmakingConstraintsV1Changed",
    "NativePlaformSanitizerCompleted",
    "GetMeRequestV1Completed",
    "UpdateDisplayNameV1Completed",
    "GetDisplayNameV1Completed",
    "GetPlayerCharactersV1RequestCompleted",
    "GetPlayerPowerUpsV1RequestCompleted",
    "GetPlayerEmoticonsV1RequestCompleted",
    "GetPlayerLoadoutsV1RequestCompleted",
    "GetPlayerLoadoutsV2RequestCompleted",
    "CreateOrUpdateLoadoutsV1RequestCompleted",
    "PlayerSetSelectedLoadoutV1RequestCompleted",
    "PlayerGetSelectedLoadoutV1RequestCompleted",
    "PlayerDeleteLoadoutV1RequestCompleted",
    "GetPlayerFeatureFlagsV1RequestCompleted",
    "PlayerCharactersV1Changed",
    "PlayerPowerUpsV1Changed",
    "PlayerEmoticonsV1Changed",
    "PlayerPublicProfileChanged",
    "PlayerLoadoutsV1Changed",
    "PlayerSelectedLoadoutV1Changed",
    "PlayerFeatureFlagsChanged",
    "RegionsV1Changed",
    "OnRegionsV1RequestCompleted",
}

local function probeE5()
    flog("=== [Pass5] E5 broadcast-bind @ " .. os.date("%H:%M:%S") .. " ===")

    -- Prereq: ModActor located + hook registered. F6 (E3) does both
    -- as a side effect, so require at least one F6 press first.
    if not E3_MODACTOR or not E3_MODACTOR:IsValid() then
        flog("[E5] no cached ModActor — press F6 first to locate it")
        flog("=== [Pass5] E5 aborted ===")
        return
    end
    if not E3_HOOK_REGISTERED then
        flog("[E5] WARNING: hook on OnMeResponseFired NOT yet registered")
        flog("[E5]   press F6 first so the hook gets installed; otherwise we'd")
        flog("[E5]   bind to all 40 delegates with no observability.")
        flog("=== [Pass5] E5 aborted ===")
        return
    end

    local model = FindFirstOf("PMPlayerModel")
    if not model or not model:IsValid() then
        flog("[E5] PMPlayerModel not found — try post-login")
        flog("=== [Pass5] E5 aborted ===")
        return
    end

    flog(string.format("[E5] target ModActor: %s", E3_MODACTOR:GetClass():GetFullName()))
    flog(string.format("[E5] hook fires so far this session: %d", E3_HOOK_FIRES))
    flog(string.format("[E5] binding OnMeResponseFired to %d delegates...", #E5_TARGET_DELEGATES))

    local boundCount, missingCount, failedCount = 0, 0, 0
    for _, delegateName in ipairs(E5_TARGET_DELEGATES) do
        local prop
        local okProp = pcall(function() prop = model[delegateName] end)
        if not okProp or prop == nil then
            flog(string.format("[E5]   %s: property not found, skipping", delegateName))
            missingCount = missingCount + 1
        else
            -- Idempotent: Remove first then Add. Pcall both because
            -- both are native calls that *could* trip a fault on a
            -- pathological prop (no evidence they would, just safety).
            pcall(function() prop:Remove(E3_MODACTOR, "OnMeResponseFired") end)
            local addOk, addErr = pcall(function() prop:Add(E3_MODACTOR, "OnMeResponseFired") end)
            if addOk then
                boundCount = boundCount + 1
                -- per-delegate success log is verbose; only summary at end
            else
                flog(string.format("[E5]   %s: BIND FAILED: %s", delegateName, tostring(addErr)))
                failedCount = failedCount + 1
            end
        end
    end

    flog(string.format("[E5] === bound %d, missing %d, failed %d (of %d) ===",
        boundCount, missingCount, failedCount, #E5_TARGET_DELEGATES))
    flog("[E5] NEXT: nav game UI (open Loadouts → switch character →")
    flog("[E5]   open Profile → close → reopen). Watch OSPlusProbes.log")
    flog("[E5]   for [E3.HOOK] FIRE entries. Each fire = engine successfully")
    flog("[E5]   invoked our truncated BP UFunction = substrate VALIDATED.")
    flog("[E5] After ~60s, press F4 again to see the running fire count.")
    flog("=== [Pass5] E5 complete ===")
end

RegisterKeyBind(Key.F4, function()
    ExecuteInGameThread(function() probeE5() end)
end)

-- =============================================================
-- Pass 5 step 3 (E4): PMPlayerModel property dump via F5
-- =============================================================
-- Parallel exploration deferred from Pass 4. If PMPlayerModel
-- exposes identity-relevant data as direct UProperties (readable
-- from Lua without UFunction marshaling), we have a SECOND path
-- to identity that bypasses the broken GetCached* UFunctions
-- and supplements the (now-being-validated) delegate-binding path.
--
-- Observed in Pass 4: model.GetMeRequestV1Completed reads cleanly
-- as a userdata (the multicast-delegate property). So at least
-- delegate properties are Lua-accessible. Do other properties on
-- PMPlayerModel give us PlayerId, DisplayName, MeResponse cache,
-- ProfileData, etc., directly?
--
-- This probe enumerates ALL properties on the class via
-- ForEachProperty (Pass 3 confirmed this works in this UE4SS
-- build for UFunctions and classes), reads each value defensively
-- via pcall, and flags identity-relevant names with ★.
--
-- Output: full property listing in OSPlusProbes.log (potentially
-- 50+ lines), plus a focused "★ identity-relevant" summary at
-- the end. Read-only — no fire risk, no native call risk beyond
-- the per-property read which is wrapped in pcall.
-- =============================================================

local E4_IDENTITY_PATTERNS = {
    "playerid", "userid", "accountid", "promid", "promethid",
    "displayname", "username",
    "response", "meresponse", "profile", "publicprofile",
    "identity", "linkcode", "platform",
    "cached", "current", "local", "self",
}

local function e4MatchesIdentity(name)
    if not name then return false end
    local lower = name:lower()
    for _, p in ipairs(E4_IDENTITY_PATTERNS) do
        if lower:find(p, 1, true) then return true end
    end
    return false
end

local function e4ReadValue(obj, pname)
    if not pname then return "<no name>" end
    local val
    local readOk, readErr = pcall(function() val = obj[pname] end)
    if not readOk then return "<read errored: " .. tostring(readErr) .. ">" end
    if val == nil then return "<nil>" end
    local t = type(val)
    if t == "string" or t == "number" or t == "boolean" then
        return tostring(val)
    end
    if t == "userdata" then
        local s
        local tsOk = pcall(function() s = val:ToString() end)
        if tsOk and type(s) == "string" then
            return string.format("<userdata:%q>", s)
        end
        return "<userdata>"
    end
    return "<" .. t .. ">"
end

local function probeE4()
    flog("=== [Pass5] E4 PMPlayerModel property dump @ " .. os.date("%H:%M:%S") .. " ===")
    local model = FindFirstOf("PMPlayerModel")
    if not model or not model:IsValid() then
        flog("[E4] PMPlayerModel not found — try post-login")
        flog("=== [Pass5] E4 aborted ===")
        return
    end
    flog("[E4] PMPlayerModel: " .. model:GetClass():GetFullName())

    local total = 0
    local interesting = {}
    local enumOk = pcall(function()
        model:GetClass():ForEachProperty(function(prop)
            total = total + 1
            local pname, ptype
            pcall(function() pname = prop:GetFName():ToString() end)
            pcall(function() ptype = prop:GetClass():GetFName():ToString() end)
            local valStr = e4ReadValue(model, pname)
            local marker = e4MatchesIdentity(pname) and " ★" or ""
            flog(string.format("[E4]   %s%s : %s = %s",
                tostring(pname), marker, tostring(ptype), valStr))
            if e4MatchesIdentity(pname) then
                table.insert(interesting, string.format("%s : %s = %s",
                    tostring(pname), tostring(ptype), valStr))
            end
        end)
    end)
    if not enumOk then
        flog("[E4] ForEachProperty failed on PMPlayerModel class")
        flog("=== [Pass5] E4 aborted ===")
        return
    end

    flog(string.format("[E4] === total properties: %d ===", total))
    if #interesting > 0 then
        flog(string.format("[E4] === %d identity-relevant properties (★) ===", #interesting))
        for _, s in ipairs(interesting) do
            flog("[E4]   ★ " .. s)
        end
    else
        flog("[E4] no property names matched identity-pattern filters")
        flog("[E4]   (full listing above — search manually for unfamiliar names)")
    end
    flog("=== [Pass5] E4 complete ===")
end

RegisterKeyBind(Key.F5, function()
    ExecuteInGameThread(function() probeE4() end)
end)

-- =============================================================
-- Pass 5 step 4 (E6): delegate signature ground-truth via F3
-- =============================================================
-- Iteration 2 (2026-04-25): the first iteration filtered ForEachFunction
-- output by name suffix '__DelegateSignature' and reported total=0 on
-- PMPlayerModel. F5's earlier dump found 40 delegate properties on this
-- exact class via ForEachProperty, so SOMETHING is here. The first
-- iteration was too narrow — it never logged the unfiltered total or any
-- sample names, so we couldn't tell whether (a) ForEachFunction returned
-- 0 functions at all, (b) returned many functions but none with the
-- suffix, or (c) the signatures live on a parent class.
--
-- This iteration is empirical:
--   Phase A: ModActor instance verification (unchanged).
--   Phase B: walk the SuperStruct chain from PMPlayerModel up to 5 levels
--            of parents. For each class in the chain:
--              - Total ForEachFunction count.
--              - First 20 function names as samples.
--              - For each function, check FUNC_Delegate flag (0x100000)
--                AND the '__DelegateSignature' name suffix as independent
--                signals. Functions matching EITHER are dumped with their
--                NumProps (param count via ForEachProperty).
--   Phase C: verdict, accounting for whether any delegate signatures
--            were found anywhere in the chain.
--
-- The two-signal check (flag OR suffix) is robust: per UE4SS source
-- (UEGenerator/Common.cpp, is_delegate_signature_function) both are
-- typically true together, but checking each independently lets us
-- distinguish unusual conventions in this game build.
--
-- LuaJIT bit.band is used for the flag check (UE4SS Lua = LuaJIT 2.1).
-- =============================================================

local E6_DELEGATE_SUFFIX = "__DelegateSignature"
local E6_FUNC_DELEGATE = 0x00100000  -- EFunctionFlags::FUNC_Delegate
local E6_MAX_CHAIN_DEPTH = 5
local E6_MAX_SAMPLE_NAMES = 20

local function e6CountParams(fn)
    local n = 0
    local types = {}
    pcall(function()
        fn:ForEachProperty(function(p)
            n = n + 1
            local pt
            pcall(function() pt = p:GetClass():GetName() end)
            table.insert(types, tostring(pt))
        end)
    end)
    return n, types
end

local function e6BuildClassChain(startCls)
    local chain = {}
    local cur = startCls
    for _ = 1, E6_MAX_CHAIN_DEPTH do
        if not cur or not cur:IsValid() then break end
        chain[#chain + 1] = cur
        local super
        pcall(function() super = cur:GetSuperStruct() end)
        if not super or not super:IsValid() or super == cur then break end
        cur = super
    end
    return chain
end

local function e6EnumClass(cls)
    local clsName
    pcall(function() clsName = cls:GetFullName() end)
    flog(string.format("[E6] === class: %s ===", tostring(clsName)))

    local total = 0
    local sampleNames = {}
    local delegateFns = {}
    local enumOk = pcall(function()
        cls:ForEachFunction(function(fn)
            total = total + 1
            local fname, flags
            pcall(function() fname = fn:GetFName():ToString() end)
            pcall(function() flags = fn:GetFunctionFlags() end)

            if total <= E6_MAX_SAMPLE_NAMES then
                table.insert(sampleNames, tostring(fname))
            end

            local hasDelegateFlag = false
            if type(flags) == "number" then
                -- LuaJIT bit.band; falls back to a coarse mask check
                -- via math if bit isn't loaded.
                if bit and bit.band then
                    hasDelegateFlag = bit.band(flags, E6_FUNC_DELEGATE) ~= 0
                else
                    hasDelegateFlag = (flags % 0x200000) >= 0x100000
                end
            end
            local hasSuffix = fname and fname:find(E6_DELEGATE_SUFFIX, 1, true) ~= nil

            if hasDelegateFlag or hasSuffix then
                local n, types = e6CountParams(fn)
                table.insert(delegateFns, {
                    name = fname,
                    flags = flags,
                    flag = hasDelegateFlag,
                    suffix = hasSuffix,
                    n = n,
                    types = types,
                })
            end
        end)
    end)
    if not enumOk then
        flog("[E6]   ForEachFunction errored on this class")
        return 0, 0
    end

    flog(string.format("[E6]   total UFunctions on this class: %d", total))
    if #sampleNames > 0 then
        flog(string.format("[E6]   first %d names (samples):", #sampleNames))
        for i, n in ipairs(sampleNames) do
            flog(string.format("[E6]     [%d] %s", i, n))
        end
        if total > E6_MAX_SAMPLE_NAMES then
            flog(string.format("[E6]     ... and %d more", total - E6_MAX_SAMPLE_NAMES))
        end
    end

    if #delegateFns > 0 then
        flog(string.format("[E6]   --- %d delegate-signature candidates on this class ---", #delegateFns))
        for _, d in ipairs(delegateFns) do
            flog(string.format(
                "[E6]     %s  (flags=0x%X delegate-flag=%s suffix=%s NumProps=%d [%s])",
                tostring(d.name), d.flags or 0,
                tostring(d.flag), tostring(d.suffix),
                d.n, table.concat(d.types, ", ")))
        end
    else
        flog("[E6]   no delegate-signature candidates on this class")
    end
    return total, #delegateFns
end

local function probeE6()
    flog("=== [Pass5] E6 ground-truth probe @ " .. os.date("%H:%M:%S") .. " ===")

    -- ---- Phase A: ModActor instance verification ----
    flog("[E6] --- Phase A: verify FindFirstOf returned an INSTANCE ---")
    local modActor
    pcall(function() modActor = FindFirstOf("ModActor_C") end)
    if not modActor or not modActor:IsValid() then
        flog("[E6] FindFirstOf('ModActor_C') returned invalid — skipping Phase A")
    else
        local fullName
        pcall(function() fullName = modActor:GetFullName() end)
        flog(string.format("[E6]   modActor:GetFullName() = %s", tostring(fullName)))
        if type(fullName) == "string" and fullName:match("^ModActor_C ") then
            flog("[E6]   → INSTANCE (full name starts with 'ModActor_C ')")
        elseif type(fullName) == "string" and fullName:match("^BlueprintGeneratedClass ") then
            flog("[E6]   → CLASS (full name starts with 'BlueprintGeneratedClass ' — wrong target)")
        else
            flog("[E6]   → ambiguous full name; manual inspection needed")
        end
    end

    local actors
    pcall(function() actors = FindAllOf("ModActor_C") end)
    if not actors then
        flog("[E6]   FindAllOf('ModActor_C') = nil → 0 instances spawned")
    else
        flog(string.format("[E6]   FindAllOf('ModActor_C') returned %d instance(s):", #actors))
        for i, a in ipairs(actors) do
            local fn
            pcall(function() fn = a:GetFullName() end)
            flog(string.format("[E6]     [%d] %s", i, tostring(fn)))
        end
    end

    -- ---- Phase B: walk PMPlayerModel inheritance chain, enumerate UFunctions ----
    flog("[E6] --- Phase B: enumerate UFunctions on PMPlayerModel + parent classes ---")
    local model
    pcall(function() model = FindFirstOf("PMPlayerModel") end)
    if not model or not model:IsValid() then
        flog("[E6] PMPlayerModel not found — Phase B skipped (run after login)")
        flog("=== [Pass5] E6 aborted ===")
        return
    end

    local chain = e6BuildClassChain(model:GetClass())
    flog(string.format("[E6] inheritance chain depth: %d (capped at %d)", #chain, E6_MAX_CHAIN_DEPTH))

    local grandTotalFns, grandTotalDelegates = 0, 0
    for _, cls in ipairs(chain) do
        local fnCount, delCount = e6EnumClass(cls)
        grandTotalFns = grandTotalFns + fnCount
        grandTotalDelegates = grandTotalDelegates + delCount
    end

    -- ---- Phase C: verdict ----
    flog("[E6] --- Phase C: verdict ---")
    flog(string.format("[E6]   grand totals across chain: %d UFunctions, %d delegate-signature candidates",
        grandTotalFns, grandTotalDelegates))

    if grandTotalDelegates == 0 then
        flog("[E6] → 0 delegate-signature candidates anywhere in the chain. Either:")
        flog("[E6]     (a) ForEachFunction in this UE4SS build doesn't expose")
        flog("[E6]         delegate signature UFunctions at all (filters them out)")
        flog("[E6]     (b) Prometheus uses a different macro family (sparse delegates")
        flog("[E6]         + hand-registered signatures, or some custom path)")
        flog("[E6]     (c) The signatures live on a class outside the chain we walked")
        flog("[E6]   Next step: try StaticFindObject for a known candidate path,")
        flog("[E6]   e.g. /Script/Prometheus.PMPlayerModel.GetMeRequestV1Completed__DelegateSignature")
        flog("[E6]   from the in-game UE4SS console, OR consult the GUI object dumper")
        flog("[E6]   for delegate signature entries on PMPlayerModel.")
    elseif grandTotalDelegates > 0 then
        flog(string.format("[E6] → found %d delegate-signature candidates total", grandTotalDelegates))
        flog("[E6]   See per-class entries above for NumProps per delegate.")
        flog("[E6]   If ANY have NumProps=0, our 0-param OnMeResponseFired matches")
        flog("[E6]   and our broadcast bind in F4 would have hooked them. If those")
        flog("[E6]   never fired during nav, the bug is fire-side (delegate not")
        flog("[E6]   broadcast naturally), not bind-side.")
        flog("[E6]   If ALL have NumProps≥1, signature-mismatch silent-skip is")
        flog("[E6]   confirmed — outcome (iii) for ADR 0001's R-B path.")
    end

    flog("=== [Pass5] E6 complete ===")
end

RegisterKeyBind(Key.F3, function()
    ExecuteInGameThread(function() probeE6() end)
end)

-- =============================================================
-- Pass 5 step 5 (E7): controlled prop:Broadcast() + GetBindings
-- =============================================================
-- F3/E6 iter 2 confirmed: PMPlayerModel has 44 UFunctions, NONE
-- with FUNC_Delegate flag, NONE with __DelegateSignature suffix.
-- F5 confirmed 40 MulticastInlineDelegateProperty properties on
-- the same class. Conclusion: signature UFunctions live somewhere
-- ForEachFunction can't reach (most likely the /Script/Prometheus
-- package outer, shared across multiple delegate properties).
--
-- Direct introspection is now expensive (would need GUI dumper or
-- StaticFindObject sweeps). But there's a cheaper question we can
-- answer right now: does the bind/dispatch substrate work AT ALL?
--
-- Approach: call prop:Broadcast() with 0 args from Lua. The
-- engine's ProcessMulticastDelegate dispatches to every binding;
-- our 0-arg OnMeResponseFired reads no buffer and just runs its
-- body. If our hook fires, the substrate is wired correctly and
-- "0 hooks during nav" is either signature-mismatch silent-skip
-- on engine-side natural broadcasts (outcome iii) or no natural
-- broadcast actually happens during the navs we tried.
--
-- Bonus checks:
--   Phase A: pairs(getmetatable(prop)) — surface any undocumented
--            methods on the prop userdata (e.g. a hidden
--            :GetSignatureFunction()).
--   Phase B: StaticFindObject sweep — try common candidate paths
--            for the GetMeRequestV1Completed signature, both
--            class-scoped and package-scoped.
--   Phase C: prop:Broadcast() controlled fire + GetBindings()
--            persistence check.
-- =============================================================

local function e7DumpPropMethods(prop, propName)
    flog("[E7.A] introspecting property userdata for: " .. propName)
    local mt = getmetatable(prop)
    if not mt then
        flog("[E7.A]   no metatable on prop")
    else
        local count, methods = 0, {}
        for k, v in pairs(mt) do
            count = count + 1
            table.insert(methods, string.format("%s : %s", tostring(k), type(v)))
        end
        flog(string.format("[E7.A]   metatable has %d entries:", count))
        table.sort(methods)
        for _, m in ipairs(methods) do
            flog("[E7.A]     " .. m)
        end
    end

    -- Probe common candidate names (false-friend trap aware: only
    -- report 'function' types, since UE4SS __index returns userdata
    -- for unknown keys).
    local candidates = {
        "GetSignatureFunction", "SignatureFunction", "GetSignature",
        "Signature", "GetSignatureFn", "GetSig",
        "GetParameters", "GetParms", "GetNumParms", "GetParameterCount",
        "GetDelegate", "GetTargetFunction", "GetTargets",
        "Reflection", "GetClass",
    }
    flog("[E7.A]   candidate-name probe (only 'function' results listed):")
    for _, name in ipairs(candidates) do
        local val
        pcall(function() val = prop[name] end)
        if type(val) == "function" then
            flog(string.format("[E7.A]     %s = function (REAL!)", name))
        end
    end
end

local function e7TryStaticFind(path)
    local obj
    pcall(function() obj = StaticFindObject(path) end)
    if obj and obj:IsValid() then
        local fn
        pcall(function() fn = obj:GetFullName() end)
        flog(string.format("[E7.B]   FOUND: %s -> %s", path, tostring(fn)))
        local n = 0
        pcall(function()
            obj:ForEachProperty(function(p) n = n + 1 end)
        end)
        flog(string.format("[E7.B]     NumProps via ForEachProperty: %d", n))
        return obj
    else
        flog(string.format("[E7.B]   not found: %s", path))
        return nil
    end
end

local function probeE7()
    flog("=== [Pass5] E7 controlled-broadcast probe @ " .. os.date("%H:%M:%S") .. " ===")

    local model
    pcall(function() model = FindFirstOf("PMPlayerModel") end)
    if not model or not model:IsValid() then
        flog("[E7] PMPlayerModel not found — abort (run after login)")
        flog("=== [Pass5] E7 complete ===")
        return
    end

    local prop
    pcall(function() prop = model.GetMeRequestV1Completed end)
    if not prop then
        flog("[E7] property access failed — abort")
        flog("=== [Pass5] E7 complete ===")
        return
    end

    -- ---- Phase A: introspect prop userdata ----
    e7DumpPropMethods(prop, "GetMeRequestV1Completed")

    -- ---- Phase B: StaticFindObject sweep ----
    flog("[E7.B] --- StaticFindObject sweep for candidate signature paths ---")
    local candidates = {
        -- class-scoped (the assumption that failed in F3)
        "/Script/Prometheus.PMPlayerModel.GetMeRequestV1Completed__DelegateSignature",
        "/Script/Prometheus.PMPlayerModel:GetMeRequestV1Completed__DelegateSignature",
        -- package-scoped per-property
        "/Script/Prometheus.GetMeRequestV1Completed__DelegateSignature",
        -- delegate-type-named (when DECLARE_DELEGATE_* is at file scope)
        "/Script/Prometheus.GetMeRequestV1CompletedDelegate__DelegateSignature",
        "/Script/Prometheus.GetMeRequestV1CompletedSignature__DelegateSignature",
        -- shared signature naming (if all 40 props share one sig)
        "/Script/Prometheus.RequestCompletedDelegate__DelegateSignature",
        "/Script/Prometheus.MeResponseV1Delegate__DelegateSignature",
        "/Script/Prometheus.PMRequestCompletedDelegate__DelegateSignature",
    }
    for _, path in ipairs(candidates) do
        e7TryStaticFind(path)
    end

    -- ---- Phase C: controlled Broadcast + GetBindings ----
    flog("[E7.C] --- controlled Broadcast() + GetBindings() ---")
    if not E3_MODACTOR or not E3_MODACTOR:IsValid() then
        flog("[E7.C] no cached ModActor — press F6 first; abort Phase C")
        flog("=== [Pass5] E7 complete ===")
        return
    end
    if not E3_HOOK_REGISTERED then
        flog("[E7.C] hook not registered — press F6 first; abort Phase C")
        flog("=== [Pass5] E7 complete ===")
        return
    end

    -- Re-bind to be sure (idempotent: Remove then Add)
    pcall(function() prop:Remove(E3_MODACTOR, "OnMeResponseFired") end)
    local bindOk = pcall(function() prop:Add(E3_MODACTOR, "OnMeResponseFired") end)
    flog(string.format("[E7.C]   re-bind: %s", bindOk and "OK" or "FAILED"))

    -- GetBindings: verify our bind actually persisted
    flog("[E7.C]   --- GetBindings() persistence check ---")
    local bindings
    pcall(function() bindings = prop:GetBindings() end)
    if bindings == nil then
        flog("[E7.C]     GetBindings() returned nil (no bindings, OR method failed)")
    else
        flog(string.format("[E7.C]     GetBindings() returned %d binding(s):", #bindings))
        for i, b in ipairs(bindings) do
            local objName, fnName
            pcall(function() objName = b.Object and b.Object:GetFullName() or "nil" end)
            pcall(function() fnName = b.FunctionName and tostring(b.FunctionName) or "nil" end)
            flog(string.format("[E7.C]       [%d] obj=%s fn=%s", i, tostring(objName), tostring(fnName)))
        end
    end

    -- The actual test: controlled 0-arg broadcast
    local before = E3_HOOK_FIRES
    flog(string.format("[E7.C]   hook fires BEFORE Broadcast(): %d", before))
    flog("[E7.C]   >>> ATTEMPT prop:Broadcast() with 0 args")
    flog("[E7.C]     (if game crashes, last on-disk line is this ATTEMPT)")
    local broadcastOk, broadcastErr = pcall(function() prop:Broadcast() end)
    if not broadcastOk then
        flog("[E7.C]   Broadcast() errored: " .. tostring(broadcastErr))
    else
        flog("[E7.C]   Broadcast() returned cleanly")
    end
    local after = E3_HOOK_FIRES
    flog(string.format("[E7.C]   hook fires AFTER Broadcast(): %d (delta=%d)", after, after - before))

    -- ---- Verdict ----
    flog("[E7.C] --- verdict ---")
    if not broadcastOk then
        flog("[E7.C] Broadcast() rejected at Lua level. UE4SS validates broadcast")
        flog("[E7.C]   args against the signature; we can't 0-arg-fire. Read the")
        flog("[E7.C]   error message above to see what arity/types it expected — that's")
        flog("[E7.C]   actually a free signature reveal.")
    elseif (after - before) > 0 then
        flog(string.format("[E7.C] +%d hook fire(s) from controlled Broadcast(). SUBSTRATE WORKS.", after - before))
        flog("[E7.C]   Bind + dispatch + RegisterHook are all wired correctly.")
        flog("[E7.C]   '0 hooks during nav' is therefore EITHER:")
        flog("[E7.C]     (i)  signature-mismatch silent-skip on engine-side natural")
        flog("[E7.C]          broadcasts (outcome iii) — only Lua-issued broadcasts work")
        flog("[E7.C]     (ii) no natural broadcast happens during the navs we tried")
        flog("[E7.C]   ADR 0001 R-B path is unblocked at the substrate level either way.")
        flog("[E7.C]   Path forward: GUI dumper to confirm signature mismatch, or")
        flog("[E7.C]     game restart to catch the login-time MeRequestV1 fire (our bind")
        flog("[E7.C]     would need to be installed BEFORE login — different injection point).")
    else
        flog("[E7.C] +0 hook fires from controlled Broadcast(). SUBSTRATE BROKEN at bind/dispatch.")
        flog("[E7.C]   Possible causes:")
        flog("[E7.C]     - prop:Broadcast() in this UE4SS build is a no-op for cross-actor binds")
        flog("[E7.C]     - Our bind is stored in a separate list from natural binds (and Broadcast")
        flog("[E7.C]       only iterates one list)")
        flog("[E7.C]     - RegisterHook on the BP UFunction isn't actually attached at runtime")
        flog("[E7.C]   Cross-check the GetBindings() output above: if our bind isn't listed,")
        flog("[E7.C]   prop:Add() was a silent no-op and that's the root cause.")
    end

    flog("=== [Pass5] E7 complete ===")
end

RegisterKeyBind(Key.F2, function()
    ExecuteInGameThread(function() probeE7() end)
end)

-- =============================================================
-- Pass 5 step 6 (E8): signature-fetch + Broadcast-with-proper-args
-- =============================================================
-- F2/E7 produced TWO breakthroughs:
--   1. Broadcast() error leaked the signature path:
--      /Script/Prometheus.MeRequestV1Completed__DelegateSignature
--      → signatures are PACKAGE-scoped (not class-scoped), and
--      → delegate type name drops the 'Get' prefix from the property.
--      F3 was walking the wrong outer; not a UE4SS bug.
--   2. GetBindings() returned 0 right after a successful Add().
--      Either Add is a silent no-op OR GetBindings is broken.
--
-- E8 resolves both with the signature path now in hand:
--   Phase A: StaticFindObject the signature, ForEachProperty to
--            dump the full param list (count + names + types).
--            Resolves the outstanding signature mystery for ADR 0001.
--   Phase B: Bind, GetBindings, bind again, GetBindings — does the
--            binding count grow? Tells us if GetBindings is tracking.
--   Phase C: Broadcast() with progressive arg counts matching the
--            Phase-A signature (1, 2, 3, ... up to NumParams).
--            For each successful Broadcast, log hook fire delta.
--            DECIDES the substrate question:
--              hook fires (any arg count) → substrate works; "0 fires
--                during nav" = signature-mismatch silent-skip on
--                engine-side natural broadcasts (outcome iii) and
--                Lua-issued Broadcasts work. ADR 0001 unblocked.
--              hook never fires + Add no-ops → bind path broken at
--                a fundamental level. ADR 0001 needs a different
--                bridge mechanism (UE4SS C++ mod).
-- =============================================================

local E8_SIG_PATH = "/Script/Prometheus.MeRequestV1Completed__DelegateSignature"

-- LuaJIT 2.1 has both `unpack` global and `table.unpack`. We dispatch
-- by intended arity (NOT #args) because args may contain trailing nils
-- and #t stops at nil — would underreport the real arity.
local function e8CallBroadcast(prop, arity, args)
    if arity == 0 then return prop:Broadcast() end
    if arity == 1 then return prop:Broadcast(args[1]) end
    if arity == 2 then return prop:Broadcast(args[1], args[2]) end
    if arity == 3 then return prop:Broadcast(args[1], args[2], args[3]) end
    if arity == 4 then return prop:Broadcast(args[1], args[2], args[3], args[4]) end
    if arity == 5 then return prop:Broadcast(args[1], args[2], args[3], args[4], args[5]) end
    error("e8CallBroadcast: arity " .. tostring(arity) .. " not supported")
end

-- Defaults by param NAME — robust even when type introspection fails
-- (which it did in E8 v1: p:GetClass():GetName() returned nil for all
-- four params on this delegate signature). The four MeRequestV1Completed
-- param names are known from E8 v1's Phase A; the broader fallbacks
-- (Id/Name/Has/Is/Response/Error) cover other delegates we'd run E8 on.
local function e8DefaultArgForName(pname)
    if not pname then return nil end
    -- exact known names
    if pname == "Succeeded" then return false end           -- Bool
    if pname == "RequestId" then return "e8-pass5-test" end -- Str
    if pname == "MeResponse" then return nil end            -- Struct
    if pname == "ErrorResponse" then return nil end         -- Struct
    -- name heuristics for unknown delegates
    local lower = pname:lower()
    if lower:find("succeeded") or lower:find("isvalid") or lower:find("ishandled") then return false end
    if lower:find("^is") or lower:find("^has") or lower:find("^was") or lower:find("^bool") then return false end
    if lower:find("id$") or lower:find("name") or lower:find("string") or lower:find("text$") then return "" end
    if lower:find("count$") or lower:find("index$") or lower:find("number$") then return 0 end
    if lower:find("response") or lower:find("error") or lower:find("data") or lower:find("info") then return nil end
    return nil
end

-- Type-driven fallback (kept for completeness; not used as primary in v2
-- because Phase A type introspection is unreliable).
local function e8DefaultArgForType(ptype)
    if ptype == "BoolProperty" then return false end
    if ptype == "StrProperty" or ptype == "NameProperty" or ptype == "TextProperty" then return "" end
    if ptype == "IntProperty" or ptype == "Int32Property" or ptype == "Int64Property" then return 0 end
    if ptype == "FloatProperty" or ptype == "DoubleProperty" then return 0.0 end
    if ptype == "ByteProperty" or ptype == "EnumProperty" then return 0 end
    return nil
end

-- Try multiple paths to recover a property's type, returning the first
-- non-nil string-or-userdata result. UE4SS Lua exposes property types
-- inconsistently across UFunction-property contexts; one of these paths
-- usually works.
local function e8IntrospectPropertyType(p)
    local results = {}
    local function tryPath(label, fn)
        local ok, val = pcall(fn)
        if ok and val ~= nil then
            local s
            if type(val) == "string" then s = val
            elseif type(val) == "userdata" then
                pcall(function() s = val:ToString() end)
                if not s then pcall(function() s = val:GetName() end) end
            else s = tostring(val) end
            if s and s ~= "nil" and s ~= "" then
                results[label] = s
            end
        end
    end
    tryPath("Class:GetName",        function() return p:GetClass():GetName() end)
    tryPath("Class:GetFullName",    function() return p:GetClass():GetFullName() end)
    tryPath("Class:GetFName:Tostr", function() return p:GetClass():GetFName():ToString() end)
    tryPath("GetCPPType",           function() return p:GetCPPType() end)
    tryPath("GetClassPrivate:Name", function() return p:GetClassPrivate():GetName() end)
    return results
end

local function probeE8()
    flog("=== [Pass5] E8 signature-fetch + Broadcast-with-args (v2) @ " .. os.date("%H:%M:%S") .. " ===")

    -- ---- Phase A: fetch the signature UFunction + introspect params ----
    flog("[E8.A] --- fetch signature UFunction ---")
    flog("[E8.A] >>> StaticFindObject(" .. E8_SIG_PATH .. ")")
    local sig
    pcall(function() sig = StaticFindObject(E8_SIG_PATH) end)
    if not sig or not sig:IsValid() then
        flog("[E8.A]   not found — abort")
        flog("=== [Pass5] E8 complete ===")
        return
    end
    local sigName
    pcall(function() sigName = sig:GetFullName() end)
    flog("[E8.A]   FOUND: " .. tostring(sigName))

    local sigFlags
    pcall(function() sigFlags = sig:GetFunctionFlags() end)
    if type(sigFlags) == "number" then
        flog(string.format("[E8.A]   GetFunctionFlags() = 0x%X", sigFlags))
        if bit and bit.band then
            flog(string.format("[E8.A]   FUNC_Delegate (0x100000) set: %s",
                tostring(bit.band(sigFlags, 0x100000) ~= 0)))
            flog(string.format("[E8.A]   FUNC_MulticastDelegate (0x10000) set: %s",
                tostring(bit.band(sigFlags, 0x10000) ~= 0)))
        end
    else
        flog("[E8.A]   GetFunctionFlags() returned non-number (" .. type(sigFlags) .. ")")
    end

    -- Enumerate params, capturing names + multi-path type introspection.
    -- Don't use ipairs on `params` later — we use `paramCount` because
    -- some entries may have nil fields.
    local params = {}
    local paramCount = 0
    pcall(function()
        sig:ForEachProperty(function(p)
            paramCount = paramCount + 1
            local pname
            pcall(function() pname = p:GetFName():ToString() end)
            local typeResults = e8IntrospectPropertyType(p)
            params[paramCount] = { name = pname, types = typeResults }
        end)
    end)

    flog(string.format("[E8.A]   signature has %d params:", paramCount))
    for i = 1, paramCount do
        local entry = params[i]
        local pname = entry and entry.name or "?"
        flog(string.format("[E8.A]     [%d] %s", i - 1, tostring(pname)))
        local typeResults = entry and entry.types or {}
        local anyType = false
        for label, val in pairs(typeResults) do
            anyType = true
            flog(string.format("[E8.A]       %s = %s", label, tostring(val)))
        end
        if not anyType then
            flog("[E8.A]       (all 5 type-introspection paths returned nil)")
        end
    end

    -- ---- Phase B: GetBindings cross-check ----
    flog("[E8.B] --- GetBindings cross-check (Add/Remove/Add) ---")
    if not E3_MODACTOR or not E3_MODACTOR:IsValid() then
        flog("[E8.B] no cached ModActor — press F6 first; abort B/C")
        flog("=== [Pass5] E8 complete ===")
        return
    end
    if not E3_HOOK_REGISTERED then
        flog("[E8.B] hook not registered — press F6 first; abort B/C")
        flog("=== [Pass5] E8 complete ===")
        return
    end

    local model
    pcall(function() model = FindFirstOf("PMPlayerModel") end)
    if not model or not model:IsValid() then
        flog("[E8.B] PMPlayerModel not found — abort B/C")
        flog("=== [Pass5] E8 complete ===")
        return
    end
    local prop
    pcall(function() prop = model.GetMeRequestV1Completed end)
    if not prop then
        flog("[E8.B] property access failed — abort B/C")
        flog("=== [Pass5] E8 complete ===")
        return
    end

    local function dumpBindings(label)
        local bindings
        pcall(function() bindings = prop:GetBindings() end)
        local n = bindings and #bindings or 0
        flog(string.format("[E8.B]   %s: GetBindings() = %d binding(s)", label, n))
        if bindings then
            for i, b in ipairs(bindings) do
                local objName, fnName
                pcall(function() objName = b.Object and b.Object:GetFullName() or "nil" end)
                pcall(function() fnName = b.FunctionName and tostring(b.FunctionName) or "nil" end)
                flog(string.format("[E8.B]     [%d] obj=%s fn=%s", i, tostring(objName), tostring(fnName)))
            end
        end
        return n
    end

    pcall(function() prop:Remove(E3_MODACTOR, "OnMeResponseFired") end)
    local n0 = dumpBindings("after Remove (baseline)")
    pcall(function() prop:Add(E3_MODACTOR, "OnMeResponseFired") end)
    local n1 = dumpBindings("after Add #1")
    pcall(function() prop:Add(E3_MODACTOR, "OnMeResponseFired") end)
    local _n2 = dumpBindings("after Add #2 (idempotent? duplicate?)")
    pcall(function() prop:Remove(E3_MODACTOR, "OnMeResponseFired") end)
    local _n3 = dumpBindings("after Remove (cleanup)")
    pcall(function() prop:Add(E3_MODACTOR, "OnMeResponseFired") end)
    local n4 = dumpBindings("after Add #3 (final, for Phase C)")

    if n4 > n0 then
        flog("[E8.B]   → GetBindings TRACKS Add. Our binding IS in the list.")
    else
        flog("[E8.B]   → GetBindings does NOT increase after Add. Either:")
        flog("[E8.B]       (a) Add is a silent no-op (root cause of '0 fires during nav')")
        flog("[E8.B]       (b) GetBindings doesn't surface our binding type (false-zero)")
        flog("[E8.B]       Phase C resolves the ambiguity.")
    end

    -- ---- Phase C: Broadcast with NAME-driven defaults + progressive arity ----
    flog("[E8.C] --- Broadcast with name-driven defaults + progressive arity ---")
    flog(string.format("[E8.C] Phase A revealed %d params; will try arities 1..%d", paramCount, paramCount))

    -- Build args by NAME first (which we KNOW from Phase A), falling back
    -- to type if name is unknown, falling back to nil otherwise.
    local fullArgs = {}
    for i = 1, paramCount do
        local entry = params[i]
        local pname = entry and entry.name or nil
        local v = e8DefaultArgForName(pname)
        if v == nil then
            -- Try type-driven fallback using whichever introspection path returned a string
            for _, val in pairs(entry and entry.types or {}) do
                v = e8DefaultArgForType(val)
                if v ~= nil then break end
            end
        end
        fullArgs[i] = v
    end

    -- Numeric loop (NOT ipairs — args may contain nils).
    flog("[E8.C] args constructed (by name first, then type fallback):")
    for i = 1, paramCount do
        local entry = params[i]
        local pname = entry and entry.name or "?"
        flog(string.format("[E8.C]   args[%d] (%s) = %s (lua-type=%s)",
            i, tostring(pname), tostring(fullArgs[i]), type(fullArgs[i])))
    end

    -- Try arities 1..paramCount (skip 0-arg, we know it errors).
    local totalFires = 0
    for arity = 1, paramCount do
        local fireBefore = E3_HOOK_FIRES
        flog(string.format("[E8.C] >>> ATTEMPT prop:Broadcast(<arity %d>)", arity))
        flog("[E8.C]   (if game crashes, last on-disk line is this ATTEMPT)")
        local ok, err = pcall(function() e8CallBroadcast(prop, arity, fullArgs) end)
        local fireAfter = E3_HOOK_FIRES
        local delta = fireAfter - fireBefore
        totalFires = totalFires + delta
        if ok then
            flog(string.format("[E8.C]   arity-%d Broadcast: OK; hook fires +%d", arity, delta))
        else
            local errFull = tostring(err)
            local errLine = errFull:match("[^\n]+") or errFull
            flog(string.format("[E8.C]   arity-%d Broadcast: ERR; hook fires +%d", arity, delta))
            flog(string.format("[E8.C]     err (first line): %s", errLine))
            -- Also log up to 3 more lines of the error — the property path
            -- (free signature reveal) lives on a continuation line in
            -- push_strproperty/push_objectproperty messages.
            local lineCount = 0
            for line in errFull:gmatch("[^\n]+") do
                lineCount = lineCount + 1
                if lineCount > 1 and lineCount <= 6 then
                    flog(string.format("[E8.C]     err (cont. %d): %s", lineCount, line))
                end
            end
        end
    end

    -- ---- Verdict ----
    flog("[E8] --- verdict ---")
    flog(string.format("[E8] total hook fires from Phase C Broadcasts: %d", totalFires))
    flog(string.format("[E8] GetBindings final count (n4): %d (baseline n0=%d)", n4, n0))
    if totalFires > 0 then
        flog("[E8] → SUBSTRATE WORKS. Lua-issued Broadcast reaches our 0-arg hook.")
        flog("[E8]   This proves the binding IS there (regardless of GetBindings result),")
        flog("[E8]   that prop:Add() did create a real binding, that RegisterHook is")
        flog("[E8]   attached, and that the engine's dispatch path invokes our truncated")
        flog("[E8]   UFunction without signature-mismatch silent-skip.")
        flog("[E8]   '0 hook fires during nav' must therefore be:")
        flog("[E8]     - either no natural broadcast happens during the navs we tried")
        flog("[E8]     - or engine-side natural broadcasts use a different dispatch path")
        flog("[E8]       than Lua-issued broadcasts (would still be outcome-iii-like)")
        flog("[E8]   ADR 0001 R-B path is unblocked at the substrate level.")
    elseif n4 == n0 then
        flog("[E8] → STRONG SIGNAL: bind path looks broken.")
        flog("[E8]   GetBindings stayed at " .. tostring(n0) .. " across 3 Add calls AND no")
        flog("[E8]   Broadcast arity made our hook fire. Either prop:Add is a silent")
        flog("[E8]   no-op OR our hook isn't actually attached at runtime (despite the")
        flog("[E8]   'Registered script hook' log line). Inspect the Phase C error")
        flog("[E8]   continuation lines — if every arity errored at the SAME slot, we")
        flog("[E8]   never reached dispatch (marshaling rejected before bind state mattered).")
        flog("[E8]   Pivot path: UE4SS C++ mod or accept R-B requires a different bridge.")
    else
        flog("[E8] → AMBIGUOUS. GetBindings tracked Add but no fires happened.")
        flog("[E8]   Likely fire-time silent-skip even on Lua-issued Broadcast (means")
        flog("[E8]   the engine validates signature against the bound UFunction's")
        flog("[E8]   ParmsSize before invoking). Outcome (iii) is then mechanism-")
        flog("[E8]   confirmed. Pivot path same as the no-op case above.")
    end

    flog("=== [Pass5] E8 complete ===")
end

RegisterKeyBind(Key.F1, function()
    ExecuteInGameThread(function() probeE8() end)
end)

-- ============================================================================
-- F10 = E8 Phase D — bind shape variations.
--
-- E8 v2 verdict was "STRONG SIGNAL: bind path looks broken". Phase D
-- triangulates whether prop:Add() is a UNIVERSAL no-op on this UE4SS
-- build vs only broken for the cross-actor / BP-target shape we tried,
-- and surfaces any alternate API names we may have missed.
--
-- Six sub-probes, each isolated so one failure doesn't abort the rest:
--   D0 — introspect the property's UClass (MulticastInline vs Sparse vs
--        regular MulticastDelegate). We have NEVER confirmed which one
--        we're talking to.
--   D1 — pairs(prop) iteration. Surfaces userdata-side fields like
--        InvocationList if any are exposed.
--   D2 — API surface enumeration. Tries ~25 plausible method names,
--        logs which return function/userdata via the false-friend trap
--        check (type(prop[name]) == "function").
--   D3 — SAME-actor bind: prop:Add(model, "<UFunction on PMPlayerModel>").
--        If GetBindings goes 0→1 here, cross-actor is the broken case.
--        If still 0, Add is a universal no-op.
--   D4 — explicit FName bind. prop:Add(modActor, FName("...")). Tests
--        whether the string→FName conversion path inside UE4SS is the
--        broken one.
--   D5 — :Bind() if present. Tests alternate API name that single-cast
--        delegates use; might be a hidden working path.
--   D6 — re-confirm the original cross-actor shape + Broadcast(arity 4).
--        Sanity check that the v2 verdict reproduces.
--
-- Prereqs: F6 (E3) must have run first to seed E3_MODACTOR + register
-- the hook on ModActor_C:OnMeResponseFired.
-- ============================================================================

local function probeE8D()
    flog("=== [Pass5] E8 Phase D bind shape variations @ " .. os.date("%H:%M:%S") .. " ===")

    if not E3_MODACTOR or not E3_MODACTOR:IsValid() then
        flog("[E8.D] no cached ModActor — press F6 first; abort")
        flog("=== [Pass5] E8 Phase D complete ===")
        return
    end
    if not E3_HOOK_REGISTERED then
        flog("[E8.D] hook not registered — press F6 first; abort")
        flog("=== [Pass5] E8 Phase D complete ===")
        return
    end

    local model
    pcall(function() model = FindFirstOf("PMPlayerModel") end)
    if not model or not model:IsValid() then
        flog("[E8.D] PMPlayerModel not found — abort")
        flog("=== [Pass5] E8 Phase D complete ===")
        return
    end
    local prop
    pcall(function() prop = model.GetMeRequestV1Completed end)
    if not prop then
        flog("[E8.D] property access failed — abort")
        flog("=== [Pass5] E8 Phase D complete ===")
        return
    end

    -- ---- helpers ----
    local function getBindCount()
        local b
        pcall(function() b = prop:GetBindings() end)
        return b and #b or 0
    end
    local function tryBroadcast4(label)
        local before = E3_HOOK_FIRES
        local ok, err = pcall(function()
            prop:Broadcast(false, "e8d-test", nil, nil)
        end)
        local after = E3_HOOK_FIRES
        local delta = after - before
        if ok then
            flog(string.format("[E8.D]     %s Broadcast(4): OK; hook fires +%d", label, delta))
        else
            local errLine = tostring(err):match("[^\n]+") or "?"
            flog(string.format("[E8.D]     %s Broadcast(4): ERR; hook fires +%d", label, delta))
            flog(string.format("[E8.D]       err: %s", errLine))
        end
        return delta
    end

    -- ---- D0: introspect the property's UClass ----
    flog("[E8.D] --- D0: introspect prop UClass ---")
    local propClassFull, propClassShort
    pcall(function() propClassFull = prop:GetClass():GetFullName() end)
    pcall(function() propClassShort = prop:GetClass():GetFName():ToString() end)
    flog(string.format("[E8.D]   prop:GetClass():GetFullName()       = %s", tostring(propClassFull)))
    flog(string.format("[E8.D]   prop:GetClass():GetFName():ToString = %s", tostring(propClassShort)))
    flog("[E8.D]   (expecting MulticastInlineDelegateProperty or MulticastSparseDelegateProperty)")

    -- ---- D1: pairs(prop) — surface internal Lua-side fields ----
    flog("[E8.D] --- D1: pairs(prop) iteration ---")
    local keyCount = 0
    local pairsOk = pcall(function()
        for k, v in pairs(prop) do
            keyCount = keyCount + 1
            if keyCount <= 30 then
                flog(string.format("[E8.D]   pairs[%d]: key=%s (lua-type=%s)",
                    keyCount, tostring(k), type(v)))
            end
        end
    end)
    if not pairsOk then
        flog("[E8.D]   pairs(prop) errored — userdata not directly iterable")
    elseif keyCount == 0 then
        flog("[E8.D]   pairs(prop) yielded 0 entries — no exposed Lua-side keys")
    else
        flog(string.format("[E8.D]   pairs(prop) yielded %d entries", keyCount))
    end

    -- ---- D2: API surface enumeration ----
    -- Avoid the false-friend trap (UE4SS __index returns userdata for
    -- unknown keys). Only count names that return a CALLABLE.
    flog("[E8.D] --- D2: API surface enumeration ---")
    local apiNames = {
        "Add", "AddUnique", "AddDynamic", "AddUFunction", "AddStatic",
        "AddRaw", "AddLambda", "AddObject",
        "Bind", "BindUObject", "BindUFunction", "BindDynamic",
        "BindStatic", "BindLambda",
        "Remove", "RemoveAll", "Clear", "Unbind", "UnbindAll",
        "Broadcast", "Execute", "ExecuteIfBound",
        "GetBindings", "GetAllObjects", "GetAllFunctionNames",
        "Contains", "IsBound", "IsValid", "ContainsByPredicate",
    }
    local foundCallables = 0
    for _, name in ipairs(apiNames) do
        local v
        pcall(function() v = prop[name] end)
        if type(v) == "function" then
            foundCallables = foundCallables + 1
            flog(string.format("[E8.D]   prop.%-22s = function  ★", name))
        end
    end
    flog(string.format("[E8.D]   total callable API names found: %d", foundCallables))

    -- ---- D3: same-actor bind ----
    -- Bind a UFunction that lives ON the property's owner (PMPlayerModel),
    -- not a cross-actor BP target. If GetBindings tracks this, cross-actor
    -- is the broken case. If still 0, Add is universally no-op on this build.
    flog("[E8.D] --- D3: same-actor bind (target = PMPlayerModel itself) ---")
    local sameActorFns = { "GetMeV1", "GetDisplayNameV1", "GetCachedMeResponseV1" }
    for _, fname in ipairs(sameActorFns) do
        pcall(function() prop:Remove(model, fname) end)
        local n0 = getBindCount()
        local addOk = pcall(function() prop:Add(model, fname) end)
        local n1 = getBindCount()
        local delta = n1 - n0
        local mark = (delta > 0) and " ★ TRACKED" or ""
        flog(string.format("[E8.D]   prop:Add(model, '%s')  ok=%s  bindings %d→%d  Δ=%d%s",
            fname, tostring(addOk), n0, n1, delta, mark))
        if delta > 0 then
            tryBroadcast4(string.format("(post-D3 Add %s)", fname))
        end
        pcall(function() prop:Remove(model, fname) end)
    end

    -- ---- D4: explicit FName bind ----
    flog("[E8.D] --- D4: cross-actor bind with explicit FName ---")
    local fnameOk, fnameVal = pcall(function() return FName("OnMeResponseFired") end)
    if not fnameOk or not fnameVal then
        flog("[E8.D]   FName(...) constructor not callable — skip")
    else
        flog(string.format("[E8.D]   FName('OnMeResponseFired') constructed (lua-type=%s)", type(fnameVal)))
        pcall(function() prop:Remove(E3_MODACTOR, "OnMeResponseFired") end)
        local n0 = getBindCount()
        local addOk = pcall(function() prop:Add(E3_MODACTOR, fnameVal) end)
        local n1 = getBindCount()
        local delta = n1 - n0
        local mark = (delta > 0) and " ★ TRACKED" or ""
        flog(string.format("[E8.D]   prop:Add(modActor, FName(...))  ok=%s  bindings %d→%d  Δ=%d%s",
            tostring(addOk), n0, n1, delta, mark))
        if delta > 0 then
            tryBroadcast4("(post-D4 FName Add)")
        end
        pcall(function() prop:Remove(E3_MODACTOR, fnameVal) end)
    end

    -- ---- D5: :Bind() if present ----
    flog("[E8.D] --- D5: try prop:Bind() if it exists ---")
    if type(prop.Bind) ~= "function" then
        flog("[E8.D]   prop.Bind is not a callable function — skip")
    else
        local n0 = getBindCount()
        local bindOk, bindErr = pcall(function() prop:Bind(E3_MODACTOR, "OnMeResponseFired") end)
        local n1 = getBindCount()
        flog(string.format("[E8.D]   prop:Bind(modActor, 'OnMeResponseFired')  ok=%s  bindings %d→%d",
            tostring(bindOk), n0, n1))
        if not bindOk then
            flog(string.format("[E8.D]     err: %s", tostring(bindErr):match("[^\n]+") or ""))
        end
        if (n1 - n0) > 0 then
            tryBroadcast4("(post-D5 Bind)")
        end
        pcall(function() prop:Unbind() end)
        pcall(function() prop:Remove(E3_MODACTOR, "OnMeResponseFired") end)
    end

    -- ---- D6: re-confirm original cross-actor shape ----
    flog("[E8.D] --- D6: re-confirm original cross-actor shape ---")
    pcall(function() prop:Remove(E3_MODACTOR, "OnMeResponseFired") end)
    local n0 = getBindCount()
    pcall(function() prop:Add(E3_MODACTOR, "OnMeResponseFired") end)
    local n1 = getBindCount()
    flog(string.format("[E8.D]   prop:Add(modActor, 'OnMeResponseFired')  bindings %d→%d", n0, n1))
    tryBroadcast4("(post-D6 cross-actor Add)")
    pcall(function() prop:Remove(E3_MODACTOR, "OnMeResponseFired") end)

    -- ---- Verdict scaffolding ----
    flog("[E8.D] --- decision matrix (read against the per-section results above) ---")
    flog("[E8.D]   D2 finds AddDynamic/AddUFunction/Bind etc. → alt API exists; try it as a workaround.")
    flog("[E8.D]   D3 Δ>0 (any same-actor bind tracked)        → CROSS-ACTOR is the broken case.")
    flog("[E8.D]   D3 Δ=0 across all 3 fns                     → Add is a UNIVERSAL no-op on this build.")
    flog("[E8.D]   D4 Δ>0 (FName variant tracked)              → string→FName conversion is the bug.")
    flog("[E8.D]   D5 Bind() worked (Δ>0 + hook fired)         → wrong API was being called all along.")
    flog("[E8.D]   D1 surfaced InvocationList                  → can read C++ side state directly.")
    flog("[E8.D]   ALL Δ=0 + nothing surfaced                  → bind path is unreachable from Lua;")
    flog("[E8.D]                                                  pivot to UE4SS C++ mod or alternate")
    flog("[E8.D]                                                  hook target (Pass 6 UFunction-hook discovery).")

    flog("=== [Pass5] E8 Phase D complete ===")
end

RegisterKeyBind(Key.F10, function()
    ExecuteInGameThread(function() probeE8D() end)
end)

-- ============================================================================
-- Pass 6 v2 (E9): RegisterHook discovery probe on PMPlayerModel UFunctions.
--
-- Pass-5 verdict: prop:Add() is a universal silent no-op on this UE4SS
-- build for MulticastInlineDelegateProperty (likely vtable-offset mismatch
-- in UE4SS's binary parser; see docs/learnings/ue4ss-multicast-delegate-add-silent-noop.md).
-- ADR 0001 R-B pivoted from "ModActor BP wrapper for delegate binding" to
-- "RegisterHook on the engine-side originating UFunction that drives the
-- multicast broadcast" — maintainer-recommended pattern per UE4SS Issue #455.
--
-- Pass 6's question: WHICH UFunction on PMPlayerModel fires reliably during
-- natural identity flow (login), and what identity state is available at
-- the time of the fire? We mass-hook all UFunctions on the class and
-- observe.
--
-- Methodology — β (mass-hook) over α (one-at-a-time):
--   Same shape as F4 (E5) which mass-bound to all 40 delegates. One
--   relog reveals every UFunction that participates in the identity
--   flow, instead of N relogs to try one candidate at a time.
--
-- Pass 6 v1 → v2 (2026-04-25): v1 installed hooks on a NUM_SIX keypress
-- → ran AFTER login completed → 0 fires captured for the only natural
-- identity flow we care about. v1 also confirmed RegisterHook works on
-- 79/79 UFunctions of PMPlayerModel + PMIdentitySubsystem with no
-- /Script/Prometheus restriction (substrate question settled). v2 fixes
-- install timing by registering at MODULE LOAD via NotifyOnNewObject (+
-- a FindFirstOf one-shot covering instances that already exist).
-- NUM_SIX becomes a pure summary endpoint.
--
-- Phase A — Enumerate + signature-dump
--   Walk PMPlayerModel via instance:GetClass → ForEachFunction.
--   For each UFunction: name, function flags hex, NumParms, per-param
--   name + type via the same multi-path introspector as E8 v2.
--   Save E9_SIGS[name] = { paramNames... } so Phase B callbacks can
--   read each parameter via context[i+1] (UE4SS passes one Context per
--   param after the self Context).
--   Repeats the same enumeration on PMIdentitySubsystem.
--
-- Phase B — Mass RegisterHook on every PMPlayerModel + PMIdentitySubsystem
-- UFunction. Each registration is pcall-wrapped so one failure doesn't
-- abort the rest. Each callback writes a single-line fire-log entry,
-- reads each named parameter via context unwrapping, plus an ambient
-- PlayerId snapshot read from PMPlayerPublicProfile.
--
-- Logging cap (avoid drowning the file when chatty UFunctions fire
-- repeatedly): verbose for first 3 fires per UFunction-name, then every
-- 25th — same heuristic as F4 (E5).
--
-- Hook-position note: UE4SS's RegisterHook(funcName, cb) registers BOTH
-- pre and post positions with the same callback (returns Pre, Post IDs
-- you could use to unregister selectively). So each ProcessEvent
-- invocation fires our callback twice. We accept this noise — state
-- readback on each fire reveals when identity becomes available.
--
-- Workflow: deploy → restart game → log in normally. Hooks install
-- automatically when the engine constructs the first PMPlayerModel /
-- PMIdentitySubsystem (look for [E9.boot] NotifyOnNewObject … fired in
-- the log). After login, press NUM_SIX any time for fire-count summary.
-- No teardown — restart the game between probe runs (RegisterHook can't
-- be unhooked from Lua).
-- ============================================================================

local E9_INSTALLED_FOR = {}        -- [instanceClassName] = true
local E9_SIGS = {}                 -- UFunction name → { paramNames... }
local E9_FIRE_COUNT = {}           -- UFunction name → fire count (this session)
local E9_TOTAL_FIRES = 0
local E9_VERBOSE_PER_NAME = 3      -- first N fires per UFunction: full detail
local E9_VERBOSE_NTH = 25          -- after that, every Nth fire

local function e9DescribeValue(v)
    if v == nil then return "nil" end
    local t = type(v)
    if t == "string" then
        if #v > 80 then return "<str:" .. #v .. " chars: '" .. v:sub(1, 60) .. "...'>" end
        return "'" .. v .. "'"
    end
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "userdata" then
        local s
        pcall(function() s = v:ToString() end)
        if s and s ~= "" and s ~= "None" then
            if #s > 80 then return "<ud:'" .. s:sub(1, 60) .. "...'>" end
            return "<ud:'" .. s .. "'>"
        end
        local fn
        pcall(function() fn = v:GetFullName() end)
        if fn then
            if #fn > 80 then return "<ud:" .. fn:sub(1, 80) .. "...>" end
            return "<ud:" .. fn .. ">"
        end
        return "<userdata>"
    end
    return tostring(v)
end

-- Walk PMPlayerPublicProfile instances and return the first non-empty
-- PlayerId. Cheapest deterministic identity check we can do at fire time
-- — confirms whether identity is reachable right now via the existing
-- (Pass-2-validated) runtime path.
local function e9SnapshotPlayerId()
    local pid
    pcall(function()
        local profiles = FindAllOf("PMPlayerPublicProfile")
        if not profiles then return end
        for _, prof in ipairs(profiles) do
            if prof:IsValid() then
                local sok, struct = pcall(function() return prof.PlayerPublicProfile end)
                if sok and struct then
                    local sok2, candidate = pcall(function()
                        local v = struct.PlayerId
                        if type(v) == "userdata" then
                            local s
                            pcall(function() s = v:ToString() end)
                            return s
                        end
                        return v
                    end)
                    if sok2 and candidate and candidate ~= "" and candidate ~= "None" then
                        pid = candidate
                        return
                    end
                end
            end
        end
    end)
    return pid
end

local function e9DumpUFunctionSignature(label, fn)
    local fname
    pcall(function() fname = fn:GetFName():ToString() end)
    if not fname then return nil, nil end

    local flags
    pcall(function() flags = fn:GetFunctionFlags() end)
    local numParms
    pcall(function() numParms = fn.NumParms end)

    flog(string.format("[E9.A]   %s.%s flags=0x%X NumParms=%s",
        label, fname, flags or 0, tostring(numParms)))

    local paramNames = {}
    pcall(function()
        fn:ForEachProperty(function(p)
            local pname
            pcall(function() pname = p:GetFName():ToString() end)
            -- Reuse E8 v2's multi-path introspector for type discovery.
            local typeResults = e8IntrospectPropertyType(p)
            local typeStr
            for _, val in pairs(typeResults) do typeStr = val; break end
            paramNames[#paramNames + 1] = pname or "?"
            flog(string.format("[E9.A]     [%d] %s : %s",
                #paramNames - 1, tostring(pname), tostring(typeStr or "?")))
        end)
    end)

    return fname, paramNames
end

local function e9MakeHookCallback(name)
    return function(...)
        E9_TOTAL_FIRES = E9_TOTAL_FIRES + 1
        local n = (E9_FIRE_COUNT[name] or 0) + 1
        E9_FIRE_COUNT[name] = n

        local verbose = (n <= E9_VERBOSE_PER_NAME) or (n % E9_VERBOSE_NTH == 0)
        if not verbose then return end

        -- args[1] is `self` Context, args[2..] are param Contexts in
        -- declaration order. We unwrap each via :get().
        local args = { ... }

        local selfFull = "?"
        if args[1] then
            local s
            pcall(function() s = args[1]:get():GetFullName() end)
            if s then selfFull = s end
        end

        flog(string.format("[E9.HOOK] #%d %s — fire #%d for this UFunction (self=%s)",
            E9_TOTAL_FIRES, name, n, selfFull))

        local sigParams = E9_SIGS[name] or {}
        for i, pname in ipairs(sigParams) do
            local ctx = args[i + 1]
            if ctx then
                local v
                pcall(function() v = ctx:get() end)
                if v ~= nil then
                    flog(string.format("[E9.HOOK]   %s = %s",
                        pname, e9DescribeValue(v)))
                end
            end
        end

        local pid = e9SnapshotPlayerId()
        flog(string.format("[E9.HOOK]   ambient PlayerId=%s", tostring(pid)))
    end
end

local function e9InstallHooksOnInstance(label, instance, hookPathPrefix)
    if not instance or not instance:IsValid() then
        flog(string.format("[E9.A] %s instance invalid — skip", label))
        return 0, 0, 0
    end

    local cls
    pcall(function() cls = instance:GetClass() end)
    if not cls or not cls:IsValid() then
        flog(string.format("[E9.A] %s:GetClass() failed — skip", label))
        return 0, 0, 0
    end

    local clsFull
    pcall(function() clsFull = cls:GetFullName() end)
    flog(string.format("[E9.A] === %s class: %s ===", label, tostring(clsFull)))

    -- Phase A: collect every UFunction on this class.
    local ufnList = {}
    pcall(function()
        cls:ForEachFunction(function(fn) ufnList[#ufnList + 1] = fn end)
    end)
    flog(string.format("[E9.A] %s: %d UFunction(s) enumerated", label, #ufnList))

    if #ufnList == 0 then
        return 0, 0, 0
    end

    -- Phase B: register a Pre+Post hook on each UFunction.
    local hookOk, hookFail = 0, 0
    for _, fn in ipairs(ufnList) do
        local fname, paramNames = e9DumpUFunctionSignature(label, fn)
        if fname then
            E9_SIGS[fname] = paramNames or {}
            local hookPath = hookPathPrefix .. fname
            -- Pre-call ATTEMPT marker so a native crash leaves the killer
            -- as the last on-disk line (same forensic pattern as F8/F1).
            flog(string.format("[E9.B] >>> ATTEMPT RegisterHook %s", hookPath))
            local ok, err = pcall(function()
                RegisterHook(hookPath, e9MakeHookCallback(fname))
            end)
            if ok then
                hookOk = hookOk + 1
            else
                hookFail = hookFail + 1
                flog(string.format("[E9.B]   FAILED: %s — %s",
                    fname, tostring(err)))
            end
        end
    end
    flog(string.format("[E9.B] %s: %d hooks ok, %d failed (of %d UFunctions)",
        label, hookOk, hookFail, #ufnList))
    return hookOk, hookFail, #ufnList
end

-- Idempotent: only installs once per instanceClassName per process lifetime.
-- Tries FindFirstOf (covers case where instance already exists, e.g., when
-- this is called from the NUM_SIX summary path as a courtesy).
local function e9TryInstallByLookup(label, instanceClassName, hookPathPrefix)
    if E9_INSTALLED_FOR[instanceClassName] then return false end
    local instance
    pcall(function() instance = FindFirstOf(instanceClassName) end)
    if not instance or not instance:IsValid() then
        flog(string.format("[E9.A] no %s instance via FindFirstOf — waiting for NotifyOnNewObject", instanceClassName))
        return false
    end
    e9InstallHooksOnInstance(label, instance, hookPathPrefix)
    E9_INSTALLED_FOR[instanceClassName] = true
    return true
end

local function probeE9()
    flog("=== [Pass6] E9 fire-count summary @ " .. os.date("%H:%M:%S") .. " ===")
    flog(string.format("[E9]   PMPlayerModel hooks installed:        %s",
        tostring(E9_INSTALLED_FOR["PMPlayerModel"] or false)))
    flog(string.format("[E9]   PMIdentitySubsystem hooks installed:  %s",
        tostring(E9_INSTALLED_FOR["PMIdentitySubsystem"] or false)))

    -- Courtesy: if either side hasn't installed yet (instance never came
    -- into existence during this process's lifetime, OR NotifyOnNewObject
    -- registered too late), try right now via FindFirstOf. Catches edge
    -- cases without losing the at-load install.
    if not E9_INSTALLED_FOR["PMPlayerModel"] then
        flog("[E9]   PMPlayerModel not yet installed — retrying via FindFirstOf")
        e9TryInstallByLookup("PMPlayerModel", "PMPlayerModel", "/Script/Prometheus.PMPlayerModel:")
    end
    if not E9_INSTALLED_FOR["PMIdentitySubsystem"] then
        flog("[E9]   PMIdentitySubsystem not yet installed — retrying via FindFirstOf")
        e9TryInstallByLookup("PMIdentitySubsystem", "PMIdentitySubsystem", "/Script/Prometheus.PMIdentitySubsystem:")
    end

    flog(string.format("[E9]   total fires across all hooks (counts pre+post): %d", E9_TOTAL_FIRES))
    local sorted = {}
    for fname, count in pairs(E9_FIRE_COUNT) do
        sorted[#sorted + 1] = { name = fname, count = count }
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)
    if #sorted == 0 then
        flog("[E9]   no hooked UFunctions have fired yet")
        flog("[E9]   if you've already logged in this session, identity-flow UFunctions")
        flog("[E9]     may not fire on passive main-menu activity. Try navigating to")
        flog("[E9]     loadout / character-select / profile screen and press NUM_SIX again.")
        flog("[E9]   if hooks aren't installed at all (above), the instance never appeared")
        flog("[E9]     during this process's lifetime — restart the game and watch the")
        flog("[E9]     [E9.boot] block at module load to confirm install fires at login.")
    else
        flog(string.format("[E9]   %d unique UFunctions have fired:", #sorted))
        for i, entry in ipairs(sorted) do
            flog(string.format("[E9]   %2d. %s — %d fire(s)", i, entry.name, entry.count))
        end
    end
    flog(string.format("[E9]   ambient PlayerId right now: %s",
        tostring(e9SnapshotPlayerId())))
    flog("=== [Pass6] E9 complete ===")
end

RegisterKeyBind(Key.NUM_SIX, function()
    ExecuteInGameThread(function() probeE9() end)
end)

-- ---- Pass 6 v2 module-load install ----
-- Two paths to install hooks before the natural identity flow happens:
--   (1) FindFirstOf right now — covers the case where Lua loads AFTER the
--       instance was constructed (e.g., if UE4SS late-loads the script,
--       or if mod-restart-without-process-restart ever becomes a thing).
--   (2) NotifyOnNewObject — covers the case where Lua loads BEFORE the
--       instance is constructed (the normal case: UE4SS loads scripts
--       during engine init, instances appear during/after login). This
--       is the maintainer-recommended pattern from UE4SS Issue #455 and
--       the path called out in our ADR 0001 + the silent-noop learning.
--
-- Both write [E9.boot] log lines so we can confirm which path actually
-- triggered the install.

flog("[E9.boot] === Pass 6 v2 module-load install (NotifyOnNewObject + FindFirstOf) ===")

local pmNow = e9TryInstallByLookup("PMPlayerModel", "PMPlayerModel", "/Script/Prometheus.PMPlayerModel:")
local subsysNow = e9TryInstallByLookup("PMIdentitySubsystem", "PMIdentitySubsystem", "/Script/Prometheus.PMIdentitySubsystem:")
flog(string.format("[E9.boot]   PMPlayerModel install at-load: %s", tostring(pmNow)))
flog(string.format("[E9.boot]   PMIdentitySubsystem install at-load: %s", tostring(subsysNow)))

-- The NotifyOnNewObject callback may run on the game thread (object
-- construction) — defer the heavy install via ExecuteInGameThread to be
-- safe + to put it on the same thread our other probes use.
local okPM, errPM = pcall(function()
    NotifyOnNewObject("/Script/Prometheus.PMPlayerModel", function(instance)
        if E9_INSTALLED_FOR["PMPlayerModel"] then return end
        local fname
        pcall(function() fname = instance and instance:GetFullName() or "?" end)
        flog(string.format("[E9.boot] NotifyOnNewObject(PMPlayerModel) fired: %s", tostring(fname)))
        ExecuteInGameThread(function()
            if E9_INSTALLED_FOR["PMPlayerModel"] then return end
            e9InstallHooksOnInstance("PMPlayerModel", instance, "/Script/Prometheus.PMPlayerModel:")
            E9_INSTALLED_FOR["PMPlayerModel"] = true
        end)
    end)
end)
flog(string.format("[E9.boot]   NotifyOnNewObject(PMPlayerModel) registered: %s%s",
    tostring(okPM), okPM and "" or (" — err: " .. tostring(errPM))))

local okSub, errSub = pcall(function()
    NotifyOnNewObject("/Script/Prometheus.PMIdentitySubsystem", function(instance)
        if E9_INSTALLED_FOR["PMIdentitySubsystem"] then return end
        local fname
        pcall(function() fname = instance and instance:GetFullName() or "?" end)
        flog(string.format("[E9.boot] NotifyOnNewObject(PMIdentitySubsystem) fired: %s", tostring(fname)))
        ExecuteInGameThread(function()
            if E9_INSTALLED_FOR["PMIdentitySubsystem"] then return end
            e9InstallHooksOnInstance("PMIdentitySubsystem", instance, "/Script/Prometheus.PMIdentitySubsystem:")
            E9_INSTALLED_FOR["PMIdentitySubsystem"] = true
        end)
    end)
end)
flog(string.format("[E9.boot]   NotifyOnNewObject(PMIdentitySubsystem) registered: %s%s",
    tostring(okSub), okSub and "" or (" — err: " .. tostring(errSub))))

flog("[E9.boot] === module-load complete; press NUM_SIX any time for fire-count summary ===")

-- Open with a session marker so the user can find this run's
-- block in OSPlusProbes.log even after multiple launches.
flog(string.format(
    "==== [OSPlusProbes] session start %s — F11 Pass2, F12 A2 poll, F9 Pass3, F8 Pass4 Rev 4, F7 Pass5 E1/E2 (Add validation), F6 Pass5 E3 (BP-fire test, hook+bind), F4 Pass5 E5 (broadcast bind to 40 delegates), F5 Pass5 E4 (property dump), F3 Pass5 E6 iter2 (chain-walk delegate sig), F2 Pass5 E7 (controlled broadcast + GetBindings), F1 Pass5 E8 v2 (signature fetch + Broadcast w/ args), F10 Pass5 E8 Phase D (bind shape variations), NUM_SIX Pass6 E9 (RegisterHook discovery on PMPlayerModel + PMIdentitySubsystem UFunctions), persistent log to %s ====",
    os.date("%Y-%m-%d %H:%M:%S"), PROBE_LOG_PATH))
