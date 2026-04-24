--[[
    Feasibility Pass 2 probes for docs/features/in-game-profile-mvp.md.

    NOT shipped with OSPlus. Installed as a separate UE4SS mod named
    `OSPlusProbes`. See docs/features/pass2-probes/README.md for install.

    Keybinds:
      F11 — one-shot snapshot battery: A1 + A3 + B1 + B2
      F12 — start A2 polling: PlayerNamePrivate every 500ms for 15s

    Output: Binaries/Win64/ue4ss/UE4SS.log (search for [A1], [A2], [A3],
    [B1], [B2]) and any mirrored external console window.

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

print("[OSPlusProbes] loaded. F11 = A1+A3+B1+B2 battery, F12 = A2 poll (15s)")
