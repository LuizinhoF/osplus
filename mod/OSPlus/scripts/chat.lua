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
M.currentTeam = nil
M.roomDelayTicks = 0
M.messages = {}
-- Latest presence list from the relay. Cached so a freshly respawned widget
-- can show the current member list immediately on reattach (see ensureWidget),
-- without waiting for the next server-side membership change.
M.presence = {}
M.onChatSent = nil
M.onRoomChange = nil
M.onRoomLeave = nil

-- ---------------------------------------------------------------------------
-- Rich text formatting
-- WBP_ModChat's ChatHistory and PresenceList are RichTextBlocks with a
-- shared Text Style Set DataTable (DT_ChatRichTextStyles) that must define:
--   Default       — message bodies (white)
--   Sender        — sender labels in chat history (bold accent, full size)
--   PresenceName  — names in the presence roster (lighter accent, smaller)
-- The two accent styles share a hue but differ in weight/size so the eye
-- can tell "this is the roster" apart from "this is who said the message".
-- Stock UE 5.1 RichTextBlock does NOT support arbitrary <color value="...">;
-- it only matches tag names against rows in that DataTable.
-- See docs/learnings/ue-richtextblock-named-rows.md.
--
-- Layout note: chat history joins entries with "\n" (one message per line);
-- presence joins entries with PRESENCE_SEPARATOR (one horizontal row, with
-- RichTextBlock auto-wrap handling overflow when many players are present).
-- ---------------------------------------------------------------------------

-- Mid-dot (U+00B7) padded with regular spaces. Renders in the Default (white)
-- style, so it visually recedes vs. the accent-styled names on either side.
local PRESENCE_SEPARATOR = " \xC2\xB7 "

local function escapeForRichText(s)
    -- Prevent user-typed angle brackets from being parsed as tags. RichTextBlock
    -- recognizes the standard XML entities for these.
    return (s:gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function senderTag(name)
    return "<Sender>[" .. escapeForRichText(name) .. "]</>"
end

local function audienceLabel(audience, targetTeam)
    if audience == "all" then return "All" end
    if audience == "team" then
        local n = tonumber(targetTeam)
        if n == 0 or n == 1 then
            return "Team " .. tostring(n + 1)
        end
        return "Team"
    end
    return nil
end

local function formatMessageLine(msg)
    local parts = {}
    local audience = audienceLabel(msg.audience, msg.targetTeam)
    if audience then
        parts[#parts + 1] = senderTag(audience)
    end
    parts[#parts + 1] = senderTag(msg.sender)
    parts[#parts + 1] = escapeForRichText(msg.text)
    return table.concat(parts, " ")
end

local function presenceTag(name)
    return "<PresenceName>" .. escapeForRichText(name) .. "</>"
end

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
        -- Sync the fresh widget's RichTextBlock to our current message list
        -- AND presence list. Without this, a new map's widget displays stale
        -- text from a previous SetHistory call (or its BP default), since
        -- Lua's reset clears M.messages but never touches the
        -- destroyed-then-respawned widget. Calling these here makes the
        -- widget always reflect Lua's truth from the moment we get a
        -- reference to it.
        local lines = {}
        for _, msg in ipairs(M.messages) do
            lines[#lines + 1] = formatMessageLine(msg)
        end
        log.try("SetHistory(initial)", function()
            M.widget:SetHistory(table.concat(lines, "\n"))
        end)

        local nameLines = {}
        for _, name in ipairs(M.presence) do
            nameLines[#nameLines + 1] = presenceTag(name)
        end
        log.try("SetPresence(initial)", function()
            M.widget:SetPresence(table.concat(nameLines, PRESENCE_SEPARATOR))
        end)
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- History display
-- BP's SetHistory implements follow-tail scrolling: it captures wasAtEnd
-- before SetText, then ScrollToEnd if (NOT IsTyping) OR wasAtEnd. Lua just
-- pushes the formatted string and trusts the BP to scroll appropriately.
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
        lines[#lines + 1] = formatMessageLine(msg)
    end
    log.try("SetHistory", function()
        M.widget:SetHistory(table.concat(lines, "\n"))
    end)
end

local function rebuildPresence()
    if not widgetAlive() then return end
    local lines = {}
    for _, name in ipairs(M.presence) do
        lines[#lines + 1] = presenceTag(name)
    end
    log.try("SetPresence", function()
        M.widget:SetPresence(table.concat(lines, PRESENCE_SEPARATOR))
    end)
end

function M.setPresence(members)
    M.presence = members or {}
    rebuildPresence()
end

function M.addMessage(sender, text, audience, targetTeam)
    table.insert(M.messages, {
        sender = sender,
        text = text,
        audience = audience or "team",
        targetTeam = targetTeam,
        time = os.clock(),
    })
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
--
-- `PlayerState.PlayerNamePrivate` USUALLY holds the friendly display name
-- ("Ispicas"), but during the brief window between map load and profile
-- replication it can transiently hold the account ID instead — a 20-24 char
-- lowercase hex string like "632680c154686dedd652". A naive cache catches
-- that transient and locks the chat into showing the ID forever.
--
-- Strategy:
--   1. If PlayerNamePrivate doesn't look like an account ID → it's the
--      friendly name; cache and return.
--   2. If it does look like an account ID → try the `PMPlayerPublicProfile`
--      cache as a fallback. The local player's profile usually isn't in that
--      cache (it's mostly populated by recently-seen opponents / friends),
--      but it's cheap to check.
--   3. If neither succeeds → return the ID *without* caching so the next
--      call retries once the engine has finished populating the profile.
--      Dump a one-shot diagnostic only when DEBUG is on, to avoid spamming
--      the log on every match start in production.
--
-- See docs/learnings/playernameprivate-transient-account-id.md.
-- ---------------------------------------------------------------------------

local cachedPlayerName = nil
local didProfileDiagnosticDump = false

local function looksLikeAccountId(s)
    -- Pure lowercase hex, 20+ chars. Real friendly names contain non-hex
    -- characters (most usernames have at least one letter outside [a-f] or
    -- a digit / symbol) or are shorter than 20 chars.
    return type(s) == "string" and #s >= 20 and s:match("^[0-9a-f]+$") ~= nil
end

local function getLocalAccountId()
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

local function readProfileField(struct, fieldName)
    local ok, val = pcall(function() return struct[fieldName] end)
    if not ok or val == nil then return nil end
    -- FString fields are returned as Lua strings already; FName/FText come
    -- through as objects with :ToString(). Try ToString first, fall back
    -- to tostring().
    local sok, s = pcall(function() return val:ToString() end)
    if sok and s and s ~= "" and s ~= "None" then return s end
    local s2 = tostring(val)
    if s2 and s2 ~= "" and s2 ~= "None" then return s2 end
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

local function dumpProfileDiagnostics(localId)
    if didProfileDiagnosticDump then return end
    didProfileDiagnosticDump = true
    log.log("[CHAT] === Player profile diagnostic (one-shot) ===")
    log.log("[CHAT] localId (PlayerState.PlayerNamePrivate): " .. tostring(localId))
    local ok, profiles = pcall(FindAllOf, "PMPlayerPublicProfile")
    if not ok or not profiles then
        log.log("[CHAT] PMPlayerPublicProfile: FindAllOf returned nothing")
        return
    end
    log.log("[CHAT] PMPlayerPublicProfile instance count: " .. #profiles)
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
                log.log("[CHAT]   [" .. i .. "] " .. (parts[1] and table.concat(parts, ", ") or "(no probe fields populated)"))
            else
                log.log("[CHAT]   [" .. i .. "] PlayerPublicProfile struct unreadable")
            end
        end
    end
end

local function resolvePlayerName()
    if cachedPlayerName then return cachedPlayerName end
    local localId = getLocalAccountId()
    if not localId then return nil end

    -- Fast path: PlayerNamePrivate already holds the friendly name.
    if not looksLikeAccountId(localId) then
        cachedPlayerName = localId
        log.log("[CHAT] Resolved player name: " .. localId)
        return localId
    end

    -- Slow path: PlayerNamePrivate is currently the account ID. Try the
    -- profile cache (usually a miss for the local player but cheap to check).
    local friendly, sourceField = findFriendlyNameByAccountId(localId)
    if friendly then
        cachedPlayerName = friendly
        log.log("[CHAT] Resolved player name: " .. friendly
            .. " (PMPlayerPublicProfile." .. sourceField .. ", accountId=" .. localId .. ")")
        return friendly
    end

    -- Profile not loaded yet. Return the ID *without* caching so the next
    -- call retries once replication catches up. Dump diagnostics in DEBUG
    -- only — in production this fires on every match start where the user's
    -- profile isn't in the local PMPlayerPublicProfile cache, which is noisy.
    if cfg.DEBUG then dumpProfileDiagnostics(localId) end
    return localId
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
-- Room = matchSeed. Individual messages carry an audience:
--   all  = everyone in the match room
--   team = one team in that match room
-- This keeps players and spectators connected to the same relay room while
-- still letting the relay filter a message to the intended side.
-- ---------------------------------------------------------------------------

local ROOM_SETTLE_TICKS = 30  -- ~1 second at 30ms/tick (just enough for GS to replicate)
local ROOM_RETRY_TICKS  = 30  -- retry interval if match room / friendly name not available yet
local ROOM_MAX_RETRIES  = 20  -- give up after ~20 seconds (need to outlast profile replication)
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

local function normalizeTeam(team)
    local n = tonumber(team)
    if n == 0 or n == 1 then return n end
    return nil
end

local function teamLabel(team)
    local n = normalizeTeam(team)
    if n == nil then return "unknown" end
    return "Team " .. tostring(n + 1)
end

local function readLocalTeam()
    local ok, team = pcall(function()
        local pc = utils.getPlayerController()
        if not pc or not pc:IsValid() then return nil end
        local ps = pc.PlayerState
        if not ps or not ps:IsValid() then return nil end
        return ps.AssignedTeam
    end)
    if ok then return normalizeTeam(team) end
    return nil
end

function M.deriveRoomCode()
    local seed = readMatchSeed()
    if not seed then return nil end
    local code = seedToCode(seed)
    log.log("[CHAT] MatchSeed: " .. tostring(seed)
        .. " local team: " .. teamLabel(readLocalTeam()) .. " => room " .. code)
    return code
end

local function parseChatAudience(text)
    local trimmed = text:match("^%s*(.-)%s*$") or ""
    if trimmed == "" then return nil end

    local defaultTeam = readLocalTeam()
    local cmd, rest = trimmed:match("^/(%S+)%s*(.*)$")
    if not cmd then
        if defaultTeam ~= nil then
            return "team", defaultTeam, trimmed
        end
        return "all", nil, trimmed
    end

    local lower = cmd:lower()
    local body = (rest or ""):match("^%s*(.-)%s*$") or ""

    if lower == "all" or lower == "a" then
        if body == "" then return nil end
        return "all", nil, body
    end

    if lower == "team" or lower == "t" then
        if body == "" or defaultTeam == nil then return nil end
        return "team", defaultTeam, body
    end

    local targetByCommand = {
        t0 = 0, team0 = 0,
        t1 = 0, team1 = 0, ["1"] = 0, blue = 0,
        t2 = 1, team2 = 1, ["2"] = 1, orange = 1,
    }
    local targetTeam = targetByCommand[lower]
    if targetTeam ~= nil then
        if body == "" then return nil end
        return "team", targetTeam, body
    end

    -- Unknown slash commands are treated as normal chat text so a player can
    -- still send "/shrug" without the command parser eating the message.
    if defaultTeam ~= nil then
        return "team", defaultTeam, trimmed
    end
    return "all", nil, trimmed
end

local function tryJoinRoom()
    local code = M.deriveRoomCode()
    local team = readLocalTeam()
    -- Resolve the name on every attempt — v22 resolvePlayerName() only caches
    -- friendly-shaped values, so cachedPlayerName being set is our signal that
    -- we have something safe to put in ws._username on the relay side.
    --
    -- Why this gate matters: the relay caches `ws._username` from the JOIN
    -- frame and uses it for every subsequent presence broadcast. If we join
    -- before profile replication finishes (3-10s window after match start),
    -- we'd send the transient account ID and the presence list would show
    -- the ID for the rest of the connection — even after later sends resolve
    -- to the friendly name correctly. See
    -- docs/learnings/playernameprivate-transient-account-id.md.
    resolvePlayerName()
    local missing = nil
    if not code then
        missing = "match room"
    elseif not cachedPlayerName then
        missing = "friendly name"
    end
    if missing and roomRetries < ROOM_MAX_RETRIES then
        roomRetries = roomRetries + 1
        log.log("[CHAT] " .. missing .. " not available yet, retry " .. roomRetries .. "/" .. ROOM_MAX_RETRIES)
        M.roomDelayTicks = ROOM_RETRY_TICKS
        return
    end
    if not code then
        log.log("[CHAT] Could not derive room after " .. ROOM_MAX_RETRIES .. " retries; giving up")
        return
    end
    if code == M.currentRoom and team == M.currentTeam then return end
    if missing then
        -- Friendly name never resolved within the budget. Fall back so chat
        -- still works locally; presence list will show whatever PlayerNamePrivate
        -- holds (account ID) or "Me" if it's empty too.
        log.log("[CHAT] Friendly name never resolved within " .. ROOM_MAX_RETRIES .. " retries; joining with fallback")
    end
    M.currentRoom = code
    M.currentTeam = team
    local username = cachedPlayerName or getLocalAccountId() or cfg.CHAT_PLAYER_NAME
    log.log("[CHAT] Joining room: " .. code .. " as " .. username .. " (" .. teamLabel(team) .. ")")
    if M.onRoomChange then
        pcall(function() M.onRoomChange(code, username, team) end)
    end
end

local function leaveRoom()
    if not M.currentRoom then return end
    log.log("[CHAT] Leaving room: " .. M.currentRoom)
    M.currentRoom = nil
    M.currentTeam = nil
    -- Presence is room-scoped; drop the cached list so a new room (or rejoin)
    -- doesn't briefly show stale members from the previous room.
    M.presence = {}
    rebuildPresence()
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
    local audience, targetTeam, body = parseChatAudience(str)
    if not body or body == "" then return end

    local sender = resolvePlayerName() or cfg.CHAT_PLAYER_NAME
    log.log("[CHAT] Received: " .. body)
    M.addMessage(sender, body, audience, targetTeam)
    if M.onChatSent then
        pcall(function() M.onChatSent(sender, body, audience, targetTeam) end)
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
    M.currentTeam = nil
    M.roomDelayTicks = 0
    roomRetries = 0
    matchProbeTimer = 0
    matchExitTimer = 0
    M.messages = {}
    M.presence = {}
    cachedPlayerName = nil
    didProfileDiagnosticDump = false
end

-- ---------------------------------------------------------------------------
-- Init: chat owns its engine integration
-- ---------------------------------------------------------------------------
-- Per .cursor/rules/mod-architecture.mdc "feature owns its engine
-- integration": every UE registration (keybind, UFunction hook, native
-- delegate) that exists in service of this feature is registered here, by
-- this module, not in main.lua. Callers wire chat by calling M.init() once
-- at module load and never thinking about it again.
--
-- Engine-global lifecycle triggers (RegisterLoadMapPostHook) remain in
-- main.lua as a multiplexer because they cross multiple features (map load
-- resets chat AND truncates the IPC inbox); main fans out to each
-- feature's M.onMapLoaded / M.reset hooks from there.
function M.init()
    RegisterKeyBind(cfg.CHAT_KEY, function()
        ExecuteInGameThread(function()
            if not M.isTyping() then
                M.open()
            end
        end)
    end)

    RegisterKeyBind(cfg.CHAT_CANCEL_KEY, function()
        ExecuteInGameThread(function()
            if M.isTyping() then
                M.close()
            end
        end)
    end)

    -- OnRep_MatchState fires when the GameState's MatchState replicates
    -- from server. Covers match-end transitions that don't come with a
    -- map change (return-to-lobby flows where the lobby is the same map).
    local hookOk, hookErr = pcall(function()
        RegisterHook("/Script/Engine.GameState:OnRep_MatchState", function()
            ExecuteInGameThread(function()
                M.onMatchStateChanged()
            end)
        end)
    end)
    if hookOk then
        log.log("[HOOK] OnRep_MatchState registered")
    else
        log.log("[HOOK] OnRep_MatchState failed: " .. tostring(hookErr))
    end
end

return M
