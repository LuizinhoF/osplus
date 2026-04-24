--[[
    Feasibility Pass 2 + Pass 3 probes for docs/features/in-game-profile-mvp.md.

    NOT shipped with OSPlus. Installed as a separate UE4SS mod named
    `OSPlusProbes`. See docs/features/pass2-probes/README.md for install.

    Keybinds:
      F11 — Pass 2 one-shot snapshot battery: A1 + A3 + B1 + B2
      F12 — Pass 2 A2 polling: PlayerNamePrivate every 500ms for 15s
      F9  — Pass 3 battery: C1 (Pawn components) + C2 (PMPlayerModel
            UFunction signatures) + C3 (PlayerState_Game_C property
            + UFunction dump)

    Output: Binaries/Win64/UE4SS.log (search for [A1], [A2], [A3],
    [B1], [B2], [C1], [C2], [C3]) and any mirrored external console
    window. Some UE4SS installs place the log under
    Binaries/Win64/ue4ss/ — check yours.

    Self-contained — uses only UE4SS Lua globals (FindFirstOf, FindAllOf,
    RegisterKeyBind, ExecuteInGameThread, LoopAsync, Key).
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

print("[OSPlusProbes] loaded. F11 = Pass2 battery, F12 = A2 poll (15s), F9 = Pass3 battery (C1+C2+C3)")
