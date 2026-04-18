local cfg   = require("config")
local log   = require("log")
local utils = require("utils")

local M = {}

M.widget  = nil
-- Typing state lives on the widget BP (`IsTyping` bool) so BP-driven closes
-- (e.g., click-outside via OnUserMovedFocus) and Lua-driven closes share one
-- source of truth. Read via M.isTyping(); write only by calling OpenInput /
-- CloseInput on the BP — never set the variable directly from Lua.
M.visible = false
M.inMatch = false
M.currentRoom = nil
M.roomDelayTicks = 0
M.messages = {}
M.onChatSent = nil
M.onRoomChange = nil
M.onRoomLeave = nil

-- ---------------------------------------------------------------------------
-- Widget discovery (single instance, BP guards against duplicates)
-- ---------------------------------------------------------------------------

local function findWidget()
    local ok, w = pcall(FindFirstOf, "WBP_ModChat_C")
    if ok and w then
        local valid, isV = pcall(function() return w:IsValid() end)
        if valid and isV then return w end
    end
    return nil
end

local function ensureWidget()
    if M.widget then
        local ok, valid = pcall(function() return M.widget:IsValid() end)
        if ok and valid then return true end
        M.widget = nil
    end
    M.widget = findWidget()
    if M.widget then
        log.log("[CHAT] Found widget: " .. log.safeFullName(M.widget))
        pcall(function() M.widget:SetVisibility(cfg.VIS_COLLAPSED) end)
        M.visible = false
        -- Sync the fresh widget's TextBlock to our current message list.
        -- Without this, a new map's widget can display stale text from a
        -- previous SetHistory call (or its BP default), since Lua's reset
        -- clears M.messages but never touches the destroyed-then-respawned
        -- widget. Calling rebuildHistory() here makes the widget always
        -- reflect Lua's truth from the moment we get a reference to it.
        local lines = {}
        for _, msg in ipairs(M.messages) do
            lines[#lines + 1] = "[" .. msg.sender .. "] " .. msg.text
        end
        log.try("SetHistory(initial)", function()
            M.widget:SetHistory(table.concat(lines, "\n"))
        end)
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- History display (BP's SetHistory now handles ScrollToEnd)
-- ---------------------------------------------------------------------------

local function widgetAlive()
    if not M.widget then return false end
    local ok, valid = pcall(function() return M.widget:IsValid() end)
    if not ok or not valid then
        M.widget = nil
        return false
    end
    return true
end

-- Single source of truth for "is the input box currently open for typing".
-- Lives on the BP as the IsTyping boolean variable.
function M.isTyping()
    if not widgetAlive() then return false end
    local ok, t = pcall(function() return M.widget.IsTyping end)
    return ok and t == true
end

local function rebuildHistory()
    if not widgetAlive() then return end
    local lines = {}
    for _, msg in ipairs(M.messages) do
        lines[#lines + 1] = "[" .. msg.sender .. "] " .. msg.text
    end
    log.try("SetHistory", function()
        M.widget:SetHistory(table.concat(lines, "\n"))
    end)
end

function M.addMessage(sender, text)
    table.insert(M.messages, { sender = sender, text = text, time = os.clock() })
    while #M.messages > cfg.CHAT_MAX_MESSAGES do
        table.remove(M.messages, 1)
    end
    ensureWidget()
    rebuildHistory()
end

-- ---------------------------------------------------------------------------
-- Input field text clearing
-- UE 5.1 bug: SetText("") reverts at the Slate level for empty strings.
-- Non-empty SetText has been observed to work, so we clear with a space
-- and trim submitted messages on the Lua side.
-- ---------------------------------------------------------------------------

local function clearInputText()
    if not M.widget then return end
    local ok, input = pcall(function() return M.widget.ChatInput end)
    if not ok or not input then
        log.log("[CHAT] clearInput: ChatInput not found")
        return
    end
    local vok, isV = pcall(function() return input:IsValid() end)
    if not vok or not isV then
        log.log("[CHAT] clearInput: ChatInput invalid")
        return
    end

    local sok, serr = pcall(function() input:SetText(FText(" ")) end)
    if sok then
        log.log("[CHAT] clearInput: SetText(space) OK")
    else
        log.log("[CHAT] clearInput: SetText(space) FAIL: " .. tostring(serr))
    end
end

-- ---------------------------------------------------------------------------
-- Player name resolution
-- ---------------------------------------------------------------------------

local cachedPlayerName = nil

local function resolvePlayerName()
    if cachedPlayerName then return cachedPlayerName end
    local ok, name = pcall(function()
        local pc = utils.getPlayerController()
        if not pc or not pc:IsValid() then return nil end
        local ps = pc.PlayerState
        if not ps or not ps:IsValid() then return nil end
        return ps.PlayerNamePrivate:ToString()
    end)
    if ok and name and name ~= "" then
        cachedPlayerName = name
        log.log("[CHAT] Resolved player name: " .. name)
        return name
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Match detection
-- Gate: GameState_Game_C.CurrentMatchSeed is non-zero.
-- The seed is replicated from the server when a match starts and stays
-- stable until the match ends. Pawn-based detection (used previously) gave
-- false negatives during KOs / round resets where the local Pawn is briefly
-- nil, causing the chat to vanish mid-match. The seed doesn't blip.
-- ---------------------------------------------------------------------------

local function readMatchSeed()
    local ok, seed = pcall(function()
        local gs = FindFirstOf("GameState_Game_C")
        if not gs or not gs:IsValid() then
            gs = FindFirstOf("GameState_Tutorial_C")
        end
        if not gs or not gs:IsValid() then return nil end
        return gs.CurrentMatchSeed
    end)
    if ok and seed and type(seed) == "number" and seed ~= 0 then
        return seed
    end
    return nil
end

local function isInMatch()
    return readMatchSeed() ~= nil
end

local matchProbeTimer = 0
local MATCH_PROBE_TICKS = 30  -- retry every ~1s while waiting for seed

function M.showWidget()
    if M.visible or not widgetAlive() then return end
    pcall(function() M.widget:SetVisibility(cfg.VIS_HIT_TEST_INVISIBLE) end)
    M.visible = true
    log.log("[CHAT] Widget shown (match detected)")
end

function M.hideWidget()
    if not widgetAlive() then return end
    pcall(function() M.widget:SetVisibility(cfg.VIS_COLLAPSED) end)
    M.visible = false
end

-- ---------------------------------------------------------------------------
-- Room code derivation
-- Room = matchSeed + team, so only teammates share a room.
-- CurrentMatchSeed is replicated from server; AssignedTeam is per-player.
-- ---------------------------------------------------------------------------

local ROOM_SETTLE_TICKS = 30  -- ~1 second at 30ms/tick (just enough for GS to replicate)
local ROOM_RETRY_TICKS  = 30  -- retry interval if team not available yet
local ROOM_MAX_RETRIES  = 10  -- give up after ~10 seconds
local roomRetries       = 0

local function seedToCode(seed)
    local chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    local n = math.abs(seed)
    local code = ""
    for _ = 1, 8 do
        local idx = (n % #chars) + 1
        code = code .. chars:sub(idx, idx)
        n = math.floor(n / #chars)
    end
    return code
end

local function readLocalTeam()
    local ok, team = pcall(function()
        local pc = utils.getPlayerController()
        if not pc or not pc:IsValid() then return nil end
        local ps = pc.PlayerState
        if not ps or not ps:IsValid() then return nil end
        return ps.AssignedTeam
    end)
    if ok and team and type(team) == "number" then
        return team
    end
    return nil
end

function M.deriveRoomCode()
    local seed = readMatchSeed()
    if not seed then return nil end
    local team = readLocalTeam()
    if not team then return nil end
    local code = seedToCode(seed) .. "T" .. tostring(team)
    log.log("[CHAT] MatchSeed: " .. tostring(seed) .. " team: " .. tostring(team) .. " => room " .. code)
    return code
end

local function tryJoinRoom()
    local code = M.deriveRoomCode()
    if not code then
        roomRetries = roomRetries + 1
        if roomRetries <= ROOM_MAX_RETRIES then
            log.log("[CHAT] Team not available yet, retry " .. roomRetries .. "/" .. ROOM_MAX_RETRIES)
            M.roomDelayTicks = ROOM_RETRY_TICKS
        else
            log.log("[CHAT] Could not derive room after " .. ROOM_MAX_RETRIES .. " retries")
        end
        return
    end
    if code == M.currentRoom then return end
    M.currentRoom = code
    log.log("[CHAT] Joining room: " .. code)
    if M.onRoomChange then
        pcall(function() M.onRoomChange(code) end)
    end
end

local function leaveRoom()
    if not M.currentRoom then return end
    log.log("[CHAT] Leaving room: " .. M.currentRoom)
    M.currentRoom = nil
    if M.onRoomLeave then
        pcall(M.onRoomLeave)
    end
end

-- Shared cleanup when a match ends (via hook OR exit-poll).
-- Clears chat history so old match's messages don't leak into the next one.
-- Re-arms the probe so a false-positive end (or a back-to-back match without
-- a map transition) self-recovers within ~1s instead of waiting for the
-- next LoadMapPostHook.
local function endMatch(reason)
    log.log("[CHAT] Match ended (" .. reason .. "), clearing chat")
    M.close()
    M.inMatch = false
    M.messages = {}
    rebuildHistory()
    M.hideWidget()
    leaveRoom()
    matchProbeTimer = MATCH_PROBE_TICKS
end

-- Called when match state changes (via OnRep_MatchState hook).
-- The hook is our event-driven path for noticing a match end without waiting
-- for the periodic poll. The seed-cleared check is the same as the periodic
-- one — kept here so we react within a frame of the state transition.
function M.onMatchStateChanged()
    if not M.inMatch then return end
    if not isInMatch() then
        endMatch("state hook")
    end
end

function M.onMapLoaded()
    M.inMatch = false
    M.roomDelayTicks = 0
    leaveRoom()
    M.hideWidget()
    matchProbeTimer = 1
    log.log("[CHAT] Map loaded, will probe for match")
end

local MATCH_EXIT_CHECK_TICKS = 60  -- check every ~2 seconds while in match
local matchExitTimer = 0

function M.tickMatchProbe()
    if matchProbeTimer > 0 then
        matchProbeTimer = matchProbeTimer - 1
        if matchProbeTimer == 0 then
            if not ensureWidget() then
                matchProbeTimer = MATCH_PROBE_TICKS
                return
            end
            if isInMatch() then
                M.inMatch = true
                M.roomDelayTicks = ROOM_SETTLE_TICKS
                roomRetries = 0
                matchExitTimer = MATCH_EXIT_CHECK_TICKS
                M.showWidget()
                log.log("[CHAT] Match detected, waiting for room settle")
            else
                matchProbeTimer = MATCH_PROBE_TICKS
            end
        end
        return
    end

    if M.roomDelayTicks > 0 then
        M.roomDelayTicks = M.roomDelayTicks - 1
        if M.roomDelayTicks == 0 then
            tryJoinRoom()
        end
        return
    end

    if M.inMatch then
        matchExitTimer = matchExitTimer - 1
        if matchExitTimer <= 0 then
            matchExitTimer = MATCH_EXIT_CHECK_TICKS
            if not isInMatch() then
                endMatch("seed gone")
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Open / Close
-- Blueprint handles: resize animation, ChatScroll visibility, focus,
--                    input mode, keyboard focus
-- Lua handles: typing state, keybind gating, text clearing, match gating,
--              Self visibility (HitTestInvisible ↔ SelfHitTestInvisible)
-- ---------------------------------------------------------------------------

function M.open()
    if not ensureWidget() then
        log.log("[CHAT] Cannot open: widget not found")
        return
    end
    if M.isTyping() then
        log.log("[CHAT] open() blocked: already typing")
        return
    end
    if not M.inMatch then
        log.log("[CHAT] Cannot open: not in a match")
        return
    end
    M.showWidget()
    pcall(function() M.widget:SetVisibility(cfg.VIS_SELF_HIT_TEST_INVIS) end)
    clearInputText()
    pcall(function() M.widget.PendingMessage = "" end)
    -- BP OpenInput sets IsTyping=true and plays the open animation.
    log.try("OpenInput", function() M.widget:OpenInput() end)
end

function M.close()
    if not widgetAlive() then return end
    -- BP CloseInput sets IsTyping=false, plays close anim, and resets visibility
    -- back to HitTestInvisible. Don't touch typing state or visibility here.
    log.try("CloseInput", function() M.widget:CloseInput() end)
end

-- ---------------------------------------------------------------------------
-- Poll for submitted text (called from tick loop)
-- ---------------------------------------------------------------------------

local function readPending()
    local ok, raw = pcall(function() return M.widget.PendingMessage end)
    if not ok or not raw then return nil end
    if type(raw) == "string" then return raw end
    if type(raw) == "userdata" then
        local tok, ts = pcall(function() return raw:ToString() end)
        if tok and ts then return ts end
    end
    return nil
end

function M.pollPending()
    if not widgetAlive() then return end

    local raw = readPending()
    if not raw or raw == "" then return end

    pcall(function() M.widget.PendingMessage = "" end)
    M.close()

    local str = raw:match("^%s*(.-)%s*$") or ""
    if str == "" then return end

    local sender = resolvePlayerName() or cfg.CHAT_PLAYER_NAME
    log.log("[CHAT] Received: " .. str)
    M.addMessage(sender, str)
    if M.onChatSent then
        pcall(function() M.onChatSent(sender, str) end)
    end
end

-- ---------------------------------------------------------------------------
-- Reset
-- ---------------------------------------------------------------------------

function M.reset()
    leaveRoom()
    -- The previous map's widget is being destroyed by the engine right now.
    -- Touching it (SetVisibility, CloseInput, anything) can crash natively
    -- because pcall does NOT catch C++ access violations on freed UObjects.
    -- Just drop our reference; ensureWidget() will find a fresh widget
    -- on the new map after BPModLoader respawns ModActor.
    M.widget = nil
    M.visible = false
    M.inMatch = false
    M.currentRoom = nil
    M.roomDelayTicks = 0
    roomRetries = 0
    matchProbeTimer = 0
    matchExitTimer = 0
    M.messages = {}
    cachedPlayerName = nil
end

return M
