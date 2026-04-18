--[[
    Omega Strikers UE Object Explorer
    ==================================
    Reverse-engineering tool for discovering game internals.
    Run in-game across different phases (menu, queue, char select,
    awakening draft, match, post-match) and check the output file.

    USAGE:
    1. Enable in mods.txt
    2. Launch the game
    3. Press keys at each game phase to dump data
    4. Check output at: %LOCALAPPDATA%\OSPlus\explorer_output.txt

    KEYBINDS:
      F1  = Filtered object dump (interesting keywords)
      F2  = GameState / core classes + their UFunctions
      F3  = All active widgets (class names + hierarchy)
      F4  = Deep game state (player names, teams, scores, match data)
      F5  = FULL object dump (warning: huge)
      F9  = ScrollBox investigation (find game's own ScrollBox instances)
      F10 = Character / striker class dump
]]

-- ============================================================================
-- Configuration
-- ============================================================================

local OUTPUT_DIR = os.getenv("LOCALAPPDATA") .. "\\OSPlus"
local OUTPUT_FILE = OUTPUT_DIR .. "\\explorer_output.txt"

-- Keywords to filter interesting classes/objects
local INTERESTING_KEYWORDS = {
    "select", "draft", "awaken", "character", "striker", "lobby",
    "match", "game", "phase", "state", "hud", "widget", "menu",
    "pick", "ban", "team", "player", "roster", "champion", "hero",
    "queue", "ready", "load", "score", "result", "end", "post",
    "core", "round", "set"
}

-- ============================================================================
-- Utility Functions
-- ============================================================================

local outputBuffer = {}

local function ensureDirectory()
    os.execute('mkdir "' .. OUTPUT_DIR .. '" 2>nul')
end

local function log(msg)
    table.insert(outputBuffer, msg)
    print("[Explorer] " .. msg .. "\n")
end

local function flushToFile(header)
    ensureDirectory()
    local file = io.open(OUTPUT_FILE, "a")
    if file then
        file:write("\n")
        file:write("============================================================\n")
        file:write("  " .. header .. "\n")
        file:write("  Timestamp: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
        file:write("============================================================\n\n")
        
        for _, msg in ipairs(outputBuffer) do
            file:write(msg .. "\n")
        end
        
        file:write("\n")
        file:close()
        print("[Explorer] Output appended to: " .. OUTPUT_FILE .. "\n")
    else
        print("[Explorer] ERROR: Could not write to: " .. OUTPUT_FILE .. "\n")
    end
    
    outputBuffer = {}
end

--- Check if a string contains any of the interesting keywords (case insensitive)
local function isInteresting(name)
    local lower = string.lower(name)
    for _, keyword in ipairs(INTERESTING_KEYWORDS) do
        if string.find(lower, keyword, 1, true) then
            return true
        end
    end
    return false
end

--- Safely get the full name of a UObject
local function safeGetFullName(obj)
    local success, result = pcall(function()
        return obj:GetFullName()
    end)
    if success then
        return result
    end
    return "<could not get name>"
end

--- Safely get the class name of a UObject
local function safeGetClassName(obj)
    local success, result = pcall(function()
        local class = obj:GetClass()
        if class and class:IsValid() then
            return class:GetFullName()
        end
        return "<no class>"
    end)
    if success then
        return result
    end
    return "<could not get class>"
end

-- ============================================================================
-- Explorer Functions
-- ============================================================================

--- F1: Dump filtered objects (only interesting ones)
local function dumpFilteredObjects()
    log("=== FILTERED OBJECT DUMP (interesting keywords) ===")
    log("")
    
    local count = 0
    ForEachUObject(function(object, chunkIndex, objectIndex)
        if object:IsValid() then
            local fullName = safeGetFullName(object)
            if isInteresting(fullName) then
                log("[" .. objectIndex .. "] " .. fullName)
                count = count + 1
            end
        end
    end)
    
    log("")
    log("Total interesting objects found: " .. count)
    flushToFile("FILTERED OBJECT DUMP")
end

--- F2: Dump GameState class info and UFunctions
local function dumpGameState()
    log("=== GAME STATE EXPLORATION ===")
    log("")
    
    -- Try to find GameState objects
    local gameStateClasses = {
        "GameStateBase",
        "GameState", 
        "GameModeBase",
        "GameMode",
        "PlayerController",
        "PlayerState",
        "HUD"
    }
    
    for _, className in ipairs(gameStateClasses) do
        local obj = FindFirstOf(className)
        if obj and obj:IsValid() then
            log("FOUND: " .. className)
            log("  Full Name: " .. safeGetFullName(obj))
            log("  Class: " .. safeGetClassName(obj))
            
            -- Try to list properties/functions
            local success, err = pcall(function()
                local class = obj:GetClass()
                if class and class:IsValid() then
                    log("  Class Full Name: " .. class:GetFullName())
                end
            end)
            if not success then
                log("  (Could not inspect further: " .. tostring(err) .. ")")
            end
            log("")
        else
            log("NOT FOUND: " .. className)
        end
    end
    
    -- Also search for Omega Strikers specific objects
    log("")
    log("--- Searching for OS-specific objects ---")
    local osKeywords = {
        "OmegaStrikers", "OS_", "Striker", "Awakening",
        "CharSelect", "Draft", "Lobby", "Match",
        "GamePhase", "PhaseManager"
    }
    
    for _, keyword in ipairs(osKeywords) do
        local success, result = pcall(function()
            return FindAllOf(keyword)
        end)
        if success and result then
            for _, obj in ipairs(result) do
                if obj:IsValid() then
                    log("  [" .. keyword .. "] " .. safeGetFullName(obj))
                end
            end
        end
    end
    
    flushToFile("GAME STATE EXPLORATION")
end

--- F3: Dump all current widgets
local function dumpWidgets()
    log("=== WIDGET DUMP ===")
    log("")
    
    -- Search for UserWidget instances
    local widgetClasses = {
        "UserWidget",
        "Widget",
        "UMGSequencePlayer"
    }
    
    for _, className in ipairs(widgetClasses) do
        local success, objects = pcall(function()
            return FindAllOf(className)
        end)
        
        if success and objects then
            log("--- " .. className .. " instances ---")
            local count = 0
            for _, obj in ipairs(objects) do
                if obj:IsValid() then
                    local fullName = safeGetFullName(obj)
                    log("  " .. fullName)
                    count = count + 1
                end
            end
            log("  Count: " .. count)
            log("")
        else
            log("--- " .. className .. ": not found or error ---")
        end
    end
    
    flushToFile("WIDGET DUMP")
end

--- F5: Dump ALL objects (warning: huge output!)
local function dumpAllObjects()
    log("=== FULL OBJECT DUMP (ALL) ===")
    log("WARNING: This can be very large!")
    log("")
    
    local count = 0
    ForEachUObject(function(object, chunkIndex, objectIndex)
        if object:IsValid() then
            log("[" .. objectIndex .. "] " .. safeGetFullName(object))
            count = count + 1
        end
    end)
    
    log("")
    log("Total objects: " .. count)
    flushToFile("FULL OBJECT DUMP")
end

--- F4: Deep game state — player info, teams, scores, match properties
local function dumpDeepGameState()
    log("=== DEEP GAME STATE ===")
    log("")

    local function dumpProperties(obj, label, maxDepth)
        maxDepth = maxDepth or 1
        local cls = obj:GetClass()
        if not cls or not cls:IsValid() then
            log("  " .. label .. ": could not get class")
            return
        end
        log("  --- " .. label .. " properties ---")
        local propCount = 0
        pcall(function()
            cls:ForEachFunction(function(func)
                local fname = func:GetFName():ToString()
                propCount = propCount + 1
                log("    UFunc: " .. fname)
            end)
        end)
        log("  (total UFunctions: " .. propCount .. ")")
    end

    local coreClasses = {
        { name = "GameStateBase",  search = "GameStateBase" },
        { name = "PlayerState",    search = "PlayerState" },
        { name = "PlayerController", search = "PlayerController" },
    }

    for _, entry in ipairs(coreClasses) do
        local ok, obj = pcall(FindFirstOf, entry.search)
        if ok and obj and obj:IsValid() then
            log(entry.name .. ": " .. safeGetFullName(obj))
            log("  Class: " .. safeGetClassName(obj))
            dumpProperties(obj, entry.name)
            log("")
        end
    end

    log("--- PlayerState_Game_C search ---")
    local psgOk, psgAll = pcall(FindAllOf, "PlayerState_Game_C")
    if psgOk and psgAll then
        for i, ps in ipairs(psgAll) do
            if ps:IsValid() then
                log("  [" .. i .. "] " .. safeGetFullName(ps))

                local nameFound = false
                pcall(function()
                    local pname = ps.PlayerNamePrivate
                    if pname then
                        local tok, str = pcall(function() return pname:ToString() end)
                        if tok and str then
                            log("    PlayerNamePrivate: " .. str)
                            nameFound = true
                        end
                    end
                end)
                if not nameFound then
                    pcall(function()
                        log("    PlayerNamePrivate (raw): " .. tostring(ps.PlayerNamePrivate))
                    end)
                end

                pcall(function()
                    local pid = ps.PlayerId
                    if pid then log("    PlayerId: " .. tostring(pid)) end
                end)
                pcall(function()
                    local tid = ps.TeamId
                    if tid then log("    TeamId (raw): " .. tostring(tid)) end
                end)
            end
        end
    else
        log("  PlayerState_Game_C: not found")
    end

    log("")
    log("--- GameInstance_Base_C ---")
    local giOk, gi = pcall(FindFirstOf, "GameInstance_Base_C")
    if giOk and gi and gi:IsValid() then
        log("  " .. safeGetFullName(gi))
        dumpProperties(gi, "GameInstance")
    end

    flushToFile("DEEP GAME STATE")
end

--- F9: ScrollBox investigation
local function dumpScrollBoxes()
    log("=== SCROLLBOX INVESTIGATION ===")
    log("")

    local scrollClasses = { "ScrollBox", "SScrollBox", "ScrollBar" }
    for _, cls in ipairs(scrollClasses) do
        local ok, objs = pcall(FindAllOf, cls)
        if ok and objs then
            log("--- " .. cls .. " instances ---")
            local count = 0
            for _, obj in ipairs(objs) do
                if obj:IsValid() then
                    log("  " .. safeGetFullName(obj))
                    pcall(function()
                        log("    Class: " .. obj:GetClass():GetFullName())
                    end)
                    count = count + 1
                end
            end
            log("  Count: " .. count)
        else
            log("--- " .. cls .. ": not found ---")
        end
        log("")
    end

    log("--- ForEachUObject: scroll-related ---")
    local scrollCount = 0
    ForEachUObject(function(object, chunkIndex, objectIndex)
        if object:IsValid() then
            local fullName = safeGetFullName(object)
            local lower = string.lower(fullName)
            if string.find(lower, "scroll", 1, true) then
                log("  [" .. objectIndex .. "] " .. fullName)
                scrollCount = scrollCount + 1
            end
        end
    end)
    log("Total scroll-related objects: " .. scrollCount)

    flushToFile("SCROLLBOX INVESTIGATION")
end

--- F10: Character / striker class dump
local function dumpCharacters()
    log("=== CHARACTER / STRIKER DUMP ===")
    log("")

    log("--- ForEachUObject: character classes ---")
    local charCount = 0
    local seen = {}
    ForEachUObject(function(object, chunkIndex, objectIndex)
        if object:IsValid() then
            local fullName = safeGetFullName(object)
            if string.find(fullName, "/Game/Prometheus/Characters/", 1, true) then
                if not seen[fullName] then
                    seen[fullName] = true
                    log("  " .. fullName)
                    charCount = charCount + 1
                end
            end
        end
    end)
    log("Total character-related objects: " .. charCount)
    log("")

    log("--- Pawn class ---")
    local UEHelpers = require("UEHelpers")
    local pc = UEHelpers.GetPlayerController()
    if pc and pc:IsValid() then
        local pawn = pc.Pawn
        if pawn and pawn:IsValid() then
            log("  Pawn: " .. safeGetFullName(pawn))
            log("  Class: " .. safeGetClassName(pawn))

            pcall(function()
                local cls = pawn:GetClass()
                cls:ForEachFunction(function(func)
                    local fname = func:GetFName():ToString()
                    log("    UFunc: " .. fname)
                end)
            end)
        else
            log("  Pawn: NONE")
        end
    end

    flushToFile("CHARACTER / STRIKER DUMP")
end

--- F11: Player identity / display name investigation
local function dumpPlayerIdentity()
    log("=== PLAYER IDENTITY v3 ===")
    log("")

    local function safeToString(val)
        if val == nil then return nil end
        if type(val) == "string" then return val end
        if type(val) == "userdata" then
            local tok, str = pcall(function() return val:ToString() end)
            if tok and str then return str end
            local tok2, str2 = pcall(function() return tostring(val) end)
            if tok2 then return str2 end
            return "<userdata>"
        end
        return tostring(val)
    end

    -- 1) PMPlayerModel: enumerate its own properties + try out-param calls
    log("--- PMPlayerModel: properties & out-param calls ---")
    local pmOk, pm = pcall(FindFirstOf, "PMPlayerModel")
    if pmOk and pm and pm:IsValid() then
        log("  Found: " .. safeGetFullName(pm))
        pcall(function()
            pm:GetClass():ForEachProperty(function(prop)
                local pname = prop:GetFName():ToString()
                log("    prop: " .. pname)
                local rok, rval = pcall(function() return pm[pname] end)
                if rok and rval ~= nil then
                    log("      = " .. safeToString(rval))
                end
            end)
        end)

        -- Try out-param pattern: pass dummy values for out params
        log("  Trying GetCachedPlayerPublicProfile('') with out-param...")
        local cpOk, cpRes = pcall(function() return pm:GetCachedPlayerPublicProfile("") end)
        if cpOk then
            log("    returned: " .. safeToString(cpRes) .. " type=" .. type(cpRes))
        else
            log("    FAILED: " .. tostring(cpRes))
        end

        log("  Trying GetCachedMeResponseV1({})...")
        local cmOk, cmRes = pcall(function() return pm:GetCachedMeResponseV1({}) end)
        if cmOk then
            log("    returned: " .. safeToString(cmRes) .. " type=" .. type(cmRes))
        else
            log("    FAILED: " .. tostring(cmRes))
        end
    else
        log("  PMPlayerModel: not found")
    end

    -- 1b) PMIdentitySubsystem: try GetAuthenticatedPlayerId with out-param
    log("")
    log("--- PMIdentitySubsystem: out-param calls ---")
    local idOk2, idSub2 = pcall(FindFirstOf, "PMIdentitySubsystem")
    if idOk2 and idSub2 and idSub2:IsValid() then
        log("  Trying GetAuthenticatedPlayerId('')...")
        local apOk, apRes = pcall(function() return idSub2:GetAuthenticatedPlayerId("") end)
        if apOk then
            log("    returned: " .. safeToString(apRes) .. " type=" .. type(apRes))
        else
            log("    FAILED: " .. tostring(apRes))
        end

        log("  Trying GetIdentityState(0)...")
        local isOk, isRes = pcall(function() return idSub2:GetIdentityState(0) end)
        if isOk then
            log("    returned: " .. safeToString(isRes) .. " type=" .. type(isRes))
        else
            log("    FAILED: " .. tostring(isRes))
        end
    end

    -- 2a) Deep-read struct fields on first profile
    log("")
    log("--- PMPlayerPublicProfile struct field enumeration (instance 1) ---")
    local ppOk, pps = pcall(FindAllOf, "PMPlayerPublicProfile")
    if ppOk and pps and #pps > 0 then
        log("  Total: " .. #pps)
        local obj = pps[1]
        if obj:IsValid() then
            log("  " .. safeGetFullName(obj))
            local structOk, ppStruct = pcall(function() return obj.PlayerPublicProfile end)
            if structOk and ppStruct ~= nil then
                local allFieldNames = {
                    "DisplayName", "PlayerName", "Name", "Username",
                    "AccountName", "Nickname", "ProfileName", "PlayerId",
                    "AccountId", "Level", "Title", "AvatarId", "Region",
                    "SteamId", "PlatformId", "PlatformName", "Id",
                    "PlayerDisplayName", "CachedDisplayName", "UniqueId",
                    "NameTag", "GamerTag", "Tag", "Handle",
                    "EpicAccountId", "ExternalId", "PlatformUserId",
                    "DisplayNameStatus", "NameStatus", "Status",
                    "Rank", "RankName", "TitleId", "IconId",
                    "TeamId", "PartyId", "MatchId", "SeasonId",
                    "Xp", "Experience", "Wins", "Losses",
                    "FriendCode", "Code",
                    "EquippedTitle", "EquippedIcon", "EquippedBanner",
                    "BannerLevel", "Prestige", "PrestigeLevel",
                }
                for _, fn in ipairs(allFieldNames) do
                    local fok, fval = pcall(function() return ppStruct[fn] end)
                    if fok and fval ~= nil then
                        log("    ." .. fn .. " = " .. safeToString(fval))
                    end
                end
            end
        end

        -- 2b) Scan ALL profiles: dump Username + PlayerId to find local player
        log("")
        log("--- All PMPlayerPublicProfile usernames ---")
        for i = 1, #pps do
            local obj2 = pps[i]
            if obj2:IsValid() then
                local sok, s = pcall(function() return obj2.PlayerPublicProfile end)
                if sok and s then
                    local uOk, uname = pcall(function() return s.Username end)
                    local pOk, pid = pcall(function() return s.PlayerId end)
                    local un = (uOk and uname) and safeToString(uname) or "?"
                    local pi = (pOk and pid) and safeToString(pid) or "?"
                    if un ~= "?" or pi ~= "?" then
                        log("  [" .. i .. "] Username=" .. un .. "  PlayerId=" .. pi)
                    end
                end
            end
        end
    else
        log("  PMPlayerPublicProfile: not found")
    end

    -- 3) Targeted text scan: search for player name across all text widget types
    log("")
    log("--- Targeted text widget scan (Nameplate + RichTextBlock + EditableText) ---")

    local textClasses = {"RichTextBlock", "MultiLineEditableText", "EditableText", "EditableTextBox"}
    for _, cls in ipairs(textClasses) do
        local cOk, cObjs = pcall(FindAllOf, cls)
        if cOk and cObjs then
            log("  " .. cls .. " instances: " .. #cObjs)
            for _, obj in ipairs(cObjs) do
                if obj:IsValid() then
                    local tok, text = pcall(function() return obj.Text:ToString() end)
                    if tok and text and text ~= "" and #text > 1 then
                        log("    " .. safeGetFullName(obj) .. " => \"" .. text .. "\"")
                    end
                end
            end
        end
    end

    -- Check nameplate widgets for player name
    log("")
    log("--- WBP_CharacterNameplate_Base: all properties ---")
    local npOk, nps = pcall(FindAllOf, "WBP_CharacterNameplate_Base_C")
    if npOk and nps then
        log("  Total: " .. #nps)
        for i, np in ipairs(nps) do
            if np:IsValid() then
                log("  [" .. i .. "] " .. safeGetFullName(np))
                pcall(function()
                    np:GetClass():ForEachProperty(function(prop)
                        local pname = prop:GetFName():ToString()
                        local rok, rval = pcall(function() return np[pname] end)
                        if rok and rval ~= nil then
                            local str = safeToString(rval)
                            if #str < 200 then
                                log("    " .. pname .. " = " .. str)
                            end
                        end
                    end)
                end)
            end
        end
    else
        log("  WBP_CharacterNameplate_Base_C: not found")
    end

    -- 4) Nameplate NameText widget: read text directly
    log("")
    log("--- Nameplate NameText direct read ---")
    local npOk2, nps2 = pcall(FindAllOf, "WBP_CharacterNameplate_Base_C")
    if npOk2 and nps2 then
        for i, np in ipairs(nps2) do
            if np:IsValid() then
                log("  [" .. i .. "] " .. safeGetFullName(np))
                local ntOk, nameTextWidget = pcall(function() return np.NameText end)
                if ntOk and nameTextWidget then
                    log("    NameText widget: " .. safeToString(nameTextWidget))
                    local textOk, text = pcall(function() return nameTextWidget.Text:ToString() end)
                    if textOk and text then
                        log("    >>> NameText.Text = \"" .. text .. "\"")
                    else
                        log("    >>> NameText.Text: FAILED - " .. tostring(text))
                    end
                    local tok2, t2 = pcall(function() return nameTextWidget:GetText():ToString() end)
                    if tok2 and t2 then
                        log("    >>> GetText() = \"" .. t2 .. "\"")
                    end
                end
                local own = pcall(function()
                    local os2 = np.NameplateOwnerState
                    if os2 then
                        log("    OwnerState: " .. safeToString(os2))
                        local pnOk, pn = pcall(function() return os2.PlayerNamePrivate:ToString() end)
                        if pnOk and pn then log("      PlayerNamePrivate = " .. pn) end
                    end
                end)
            end
        end
    else
        log("  WBP_CharacterNameplate_Base_C: not found")
    end

    -- 5) PlayerState_Game_C: enumerate all properties
    log("")
    log("--- PlayerState_Game_C: all properties ---")
    local psOk, pss = pcall(FindAllOf, "PlayerState_Game_C")
    if psOk and pss then
        log("  Total: " .. #pss)
        for i, ps in ipairs(pss) do
            if ps:IsValid() then
                log("  [" .. i .. "] " .. safeGetFullName(ps))
                pcall(function()
                    ps:GetClass():ForEachProperty(function(prop)
                        local pname = prop:GetFName():ToString()
                        local rok, rval = pcall(function() return ps[pname] end)
                        if rok and rval ~= nil then
                            local str = safeToString(rval)
                            if #str < 200 and not string.find(str, "MulticastDelegateProperty", 1, true) then
                                log("    " .. pname .. " = " .. str)
                            end
                        end
                    end)
                end)
            end
        end
    else
        log("  PlayerState_Game_C: not found")
    end

    -- 6) PMIdentitySubsystem: try with correct param counts
    log("")
    log("--- PMIdentitySubsystem ---")
    local idOk, idSub = pcall(FindFirstOf, "PMIdentitySubsystem")
    if idOk and idSub and idSub:IsValid() then
        log("  Found: " .. safeGetFullName(idSub))
        -- GetAuthenticatedPlayerId expects 2 params: try (input, out)
        local attempts = {
            {"GetAuthenticatedPlayerId('', '')", function() return idSub:GetAuthenticatedPlayerId("", "") end},
            {"GetAuthenticatedPlayerId(0, '')", function() return idSub:GetAuthenticatedPlayerId(0, "") end},
            {"GetIdentityState()", function() return idSub:GetIdentityState() end},
        }
        for _, att in ipairs(attempts) do
            local aOk, aRes = pcall(att[2])
            if aOk then
                log("  " .. att[1] .. " => " .. safeToString(aRes) .. " type=" .. type(aRes))
            else
                log("  " .. att[1] .. " FAILED: " .. tostring(aRes))
            end
        end
        local sidOk, sid = pcall(function() return idSub:GetSteamId() end)
        if sidOk and sid then
            log("  GetSteamId() => " .. safeToString(sid))
        end
    end

    flushToFile("PLAYER IDENTITY v3")
end

-- ============================================================================
-- Key Bindings
-- ============================================================================

RegisterKeyBind(0x70, function() -- F1
    print("[Explorer] F1 pressed - Dumping filtered objects...\n")
    ExecuteInGameThread(function()
        dumpFilteredObjects()
    end)
end)

RegisterKeyBind(0x71, function() -- F2
    print("[Explorer] F2 pressed - Dumping GameState info...\n")
    ExecuteInGameThread(function()
        dumpGameState()
    end)
end)

RegisterKeyBind(0x72, function() -- F3
    print("[Explorer] F3 pressed - Dumping widgets...\n")
    ExecuteInGameThread(function()
        dumpWidgets()
    end)
end)

RegisterKeyBind(0x73, function() -- F4
    print("[Explorer] F4 pressed - Deep game state...\n")
    ExecuteInGameThread(function()
        dumpDeepGameState()
    end)
end)

RegisterKeyBind(0x74, function() -- F5
    print("[Explorer] F5 pressed - Dumping ALL objects (this may take a while)...\n")
    ExecuteInGameThread(function()
        dumpAllObjects()
    end)
end)

RegisterKeyBind(0x78, function() -- F9
    print("[Explorer] F9 pressed - ScrollBox investigation...\n")
    ExecuteInGameThread(function()
        dumpScrollBoxes()
    end)
end)

RegisterKeyBind(0x79, function() -- F10
    print("[Explorer] F10 pressed - Character dump...\n")
    ExecuteInGameThread(function()
        dumpCharacters()
    end)
end)

RegisterKeyBind(0x7A, function() -- F11
    print("[Explorer] F11 pressed - Player identity...\n")
    ExecuteInGameThread(function()
        dumpPlayerIdentity()
    end)
end)

RegisterKeyBind(0x7B, function() -- F12
    print("[Explorer] F12 pressed - ScrollBox instantiation test...\n")
    ExecuteInGameThread(function()
        log("=== SCROLLBOX INSTANTIATION TEST ===")

        local className = "/Game/Mods/OmegaStrikersMod/WBP_TestScroll.WBP_TestScroll_C"
        log("Loading class: " .. className)
        local classOk, cls = pcall(StaticFindObject, className)
        if not classOk or not cls or not cls:IsValid() then
            log("  StaticFindObject failed, trying LoadObject...")
            classOk, cls = pcall(function()
                return StaticFindObject(className)
            end)
        end

        if classOk and cls and cls:IsValid() then
            log("  Class loaded: " .. safeGetFullName(cls))
            log("  Attempting CreateWidget...")
            local gi = FindFirstOf("GameInstance")
            if gi and gi:IsValid() then
                local world = gi:GetWorld()
                local cwOk, widget = pcall(function()
                    return StaticConstructObject(cls, world, 0, 0, 0, nil, false, false, nil)
                end)
                if cwOk and widget then
                    log("  >>> Widget created: " .. safeGetFullName(widget))
                    log("  >>> SUCCESS - ScrollBox widget instantiated without crash!")
                else
                    log("  >>> CreateWidget FAILED: " .. tostring(widget))
                end
            else
                log("  GameInstance not found")
            end
        else
            log("  Class not found: " .. className)
        end

        flushToFile("SCROLLBOX TEST")
    end)
end)

-- ============================================================================
-- Auto-dump on load
-- ============================================================================

-- Auto-dumps disabled (too heavy for normal use)
-- ExecuteWithDelay(5000, function()
--     print("[Explorer] Auto-dumping filtered objects after 5s delay...\n")
--     dumpFilteredObjects()
-- end)

RegisterLoadMapPostHook(function(Engine, WorldContext, URL, PendingGame, Error)
    local mapUrl = "unknown"
    pcall(function() mapUrl = tostring(URL) end)
    log("*** MAP CHANGED: " .. mapUrl .. " ***")
    flushToFile("MAP CHANGE: " .. mapUrl)
end)

-- ============================================================================
-- Init
-- ============================================================================

ensureDirectory()

print("==============================================\n")
print("[Explorer] Omega Strikers Explorer loaded!\n")
print("[Explorer] Key binds:\n")
print("[Explorer]   F1  = Dump filtered objects\n")
print("[Explorer]   F2  = Dump GameState + UFunctions\n")
print("[Explorer]   F3  = Dump widgets\n")
print("[Explorer]   F4  = Deep state (players, teams, scores)\n")
print("[Explorer]   F5  = Dump ALL objects (large!)\n")
print("[Explorer]   F9  = ScrollBox investigation\n")
print("[Explorer]   F10 = Character / striker classes\n")
print("[Explorer]   F11 = Player identity / display name\n")
print("[Explorer] Output: " .. OUTPUT_FILE .. "\n")
print("==============================================\n")
