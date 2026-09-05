local cfg   = require("config")
local log   = require("log")
local utils = require("utils")
local assets = require("assets")
local identity = require("identity")

local M = {}

M.widget  = nil
-- Typing state lives on the widget BP (`IsTyping` bool), so BP's outside-click
-- catcher and Lua-driven closes share one source of truth. Read via
-- M.isTyping(); write only by calling OpenInput / CloseInput on the BP.
M.visible = false
M.inMatch = false
M.currentRoom = nil
M.currentSeed = nil
M.currentTeam = nil
M.currentSpectator = false
M.currentUsername = nil
M.currentRevealOpponents = false
-- Monotonic for this Lua session, including map resets. Echoed by the relay
-- so queued snapshots from an earlier room/team cannot restore hidden names.
M.presenceRevision = 0
local presenceSeed = nil
local opponentsRevealed = false
M.roomDelayTicks = 0
M.messages = {}
M.feedTicks = 0
M.feedVisible = false
M.selectedChannel = nil
M.channelRole = nil
M.channelTouched = false
M.overlayFlags = { settings = false }
-- Latest presence list from the relay. Cached so a freshly respawned widget
-- can show the current member list immediately on reattach (see ensureWidget),
-- without waiting for the next server-side membership change.
M.presence = {}
M.onChatSent = nil
M.onRoomChange = nil
M.onRoomLeave = nil
M.onMatchEnded = nil

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
local MESSAGE_MARKER = "\xE2\x94\x83"

local function escapeForRichText(s)
    -- Prevent user-typed angle brackets from being parsed as tags. RichTextBlock
    -- recognizes the standard XML entities for these.
    return (s:gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function audienceStyle(audience, targetTeam)
    if audience == "all" then return "MessageAll" end
    if audience == "team" then
        local n = tonumber(targetTeam)
        if n == 0 then return "MessageTeam1" end
        if n == 1 then return "MessageTeam2" end
        return "MessageTeam"
    end
    return "MessageAll"
end

local function formatMessageLine(msg)
    local style = audienceStyle(msg.audience, msg.targetTeam)
    local senderLine = MESSAGE_MARKER .. "  " .. escapeForRichText(msg.sender)
    return "<" .. style .. ">" .. senderLine .. "</>\n"
        .. "   " .. escapeForRichText(msg.text)
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
        pcall(function() M.widget.ChatBackground:SetVisibility(cfg.VIS_COLLAPSED) end)
        pcall(function() M.widget.SizeBox_89:SetHeightOverride(cfg.CHAT_PASSIVE_HEIGHT) end)
        pcall(function() M.widget.HistoryContentSize:SetMinDesiredHeight(72) end)
        pcall(function()
            M.widget.FocusedHeight = cfg.CHAT_FOCUSED_HEIGHT
            M.widget.IsResizing = false
        end)
        M.visible = false
        M.feedVisible = false
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

local function widgetChild(name)
    if not widgetAlive() then return nil end
    local ok, child = pcall(function() return M.widget[name] end)
    if not ok or not child then return nil end
    local validOk, valid = pcall(function() return child:IsValid() end)
    if validOk and not valid then return nil end
    return child
end

-- Keep these in sync with WBP_ModChat's fixed chrome: the composer always
-- reserves 40 px, the history border uses 12 px of vertical padding, and the
-- focused-only presence/resize rows use 26 + 12 px. The history content's
-- minimum height fills the remaining viewport so short histories anchor to
-- the composer instead of floating at the top.
local PASSIVE_HISTORY_CHROME_HEIGHT = 52
local FOCUSED_HISTORY_CHROME_HEIGHT = 90
local historyAnchorTicks = 0

local function scrollHistoryToEnd()
    local history = widgetChild("ChatScroll")
    if not history then return end
    pcall(function() history:ScrollToEnd() end)
end

local function requestHistoryEndAnchor()
    -- ScrollBox applies its new viewport size on a later Slate pass.
    scrollHistoryToEnd()
    historyAnchorTicks = 2
end

local function setChatHeight(height, focused)
    local sizeBox = widgetChild("SizeBox_89")
    if sizeBox then
        pcall(function() sizeBox:SetHeightOverride(height) end)
    end

    local historyContent = widgetChild("HistoryContentSize")
    if historyContent then
        local chromeHeight = focused
            and FOCUSED_HISTORY_CHROME_HEIGHT
            or PASSIVE_HISTORY_CHROME_HEIGHT
        local minHistoryHeight = math.max(0, height - chromeHeight)
        pcall(function() historyContent:SetMinDesiredHeight(minHistoryHeight) end)
    end
    requestHistoryEndAnchor()
end

local resizeDrag = {
    active = false,
    startMouseY = nil,
    startHeight = nil,
    appliedHeight = nil,
}
local resizeMouseReadFailed = false
local widgetLayoutLibrary = nil
local widgetLayoutLibraryLoadFailed = false

local function clampFocusedHeight(value)
    local height = tonumber(value) or cfg.CHAT_FOCUSED_HEIGHT
    return math.max(cfg.CHAT_FOCUSED_MIN_HEIGHT, math.min(cfg.CHAT_FOCUSED_MAX_HEIGHT, height))
end

local function readFocusedHeight()
    if not widgetAlive() then return cfg.CHAT_FOCUSED_HEIGHT end
    local ok, value = pcall(function() return M.widget.FocusedHeight end)
    if not ok then return cfg.CHAT_FOCUSED_HEIGHT end
    return clampFocusedHeight(value)
end

local function applyFocusedHeight(value)
    local height = clampFocusedHeight(value)
    pcall(function() M.widget.FocusedHeight = height end)
    setChatHeight(height, true)
    return height
end

local function readMouseY()
    -- Slate owns the captured drag, so PlayerController cursor data can lag
    -- until release. See docs/learnings/chat-widget-drag-and-layout-stability.md.
    if not widgetLayoutLibrary and not widgetLayoutLibraryLoadFailed then
        local ok, value = pcall(
            StaticFindObject,
            "/Script/UMG.Default__WidgetLayoutLibrary"
        )
        if ok and value then
            widgetLayoutLibrary = value
        else
            widgetLayoutLibraryLoadFailed = true
        end
    end

    if widgetLayoutLibrary then
        local ok, position = pcall(function()
            return widgetLayoutLibrary:GetMousePositionOnViewport(M.widget)
        end)
        if ok and position then
            local yOk, value = pcall(function() return position.Y end)
            if yOk and value ~= nil then return tonumber(value) end
        end
    end

    local pc = utils.getPlayerController()
    if not pc or not pc:IsValid() then return nil end

    local xBucket = {}
    local yBucket = {}
    local ok = pcall(function()
        pc:GetMousePosition(xBucket, yBucket)
    end)
    if not ok then return nil end

    for _, bucket in ipairs({ xBucket, yBucket }) do
        local value = bucket.LocationY
        if value ~= nil then return tonumber(value) end
    end
    return nil
end

local function resetResizeDrag(clearWidgetState)
    resizeDrag.active = false
    resizeDrag.startMouseY = nil
    resizeDrag.startHeight = nil
    resizeDrag.appliedHeight = nil
    if clearWidgetState and widgetAlive() then
        pcall(function() M.widget.IsResizing = false end)
    end
end

local function tickChatResize()
    if not widgetAlive() or not M.isTyping() then
        resetResizeDrag(false)
        return
    end

    local ok, resizing = pcall(function() return M.widget.IsResizing end)
    if not ok or resizing ~= true then
        resetResizeDrag(false)
        return
    end

    local mouseY = readMouseY()
    if not mouseY then
        if not resizeMouseReadFailed then
            resizeMouseReadFailed = true
            log.log("[CHAT] Resize disabled: mouse position is unavailable")
        end
        resetResizeDrag(true)
        return
    end

    if not resizeDrag.active then
        resizeDrag.active = true
        resizeDrag.startMouseY = mouseY
        resizeDrag.startHeight = readFocusedHeight()
        resizeDrag.appliedHeight = resizeDrag.startHeight
        return
    end

    local nextHeight = clampFocusedHeight(
        resizeDrag.startHeight + resizeDrag.startMouseY - mouseY
    )
    if math.abs(nextHeight - resizeDrag.appliedHeight) >= 0.5 then
        resizeDrag.appliedHeight = applyFocusedHeight(nextHeight)
    end
end

local function overlaysActive()
    return M.overlayFlags.settings == true
end

local function setFeedVisible(wanted)
    local background = widgetChild("ChatBackground")
    if not background then return end
    local visible = wanted == true and M.inMatch and not overlaysActive()
    pcall(function()
        background:SetVisibility(visible and cfg.VIS_VISIBLE or cfg.VIS_COLLAPSED)
    end)
    M.feedVisible = visible
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

function M.setPresence(members, room, revision, revealOpponents)
    -- Missing metadata (including an old relay) fails closed. Names alone
    -- cannot be safely classified as teammates in Lua.
    if not M.currentRoom or room ~= M.currentRoom
        or type(revision) ~= "number" or revision ~= M.presenceRevision
        or type(revealOpponents) ~= "boolean"
        or revealOpponents ~= M.currentRevealOpponents then
        return false
    end
    M.presence = members or {}
    rebuildPresence()
    return true
end

local notificationSound = nil
local gameplayStatics = nil
local notificationLoadFailed = false

local function playIncomingNotification()
    if not notificationSound then
        notificationSound = assets.findAsset(cfg.CHAT_NOTIFICATION_SFX)
        if not notificationSound then
            if not notificationLoadFailed then
                notificationLoadFailed = true
                log.log("[CHAT] Notification sound not found: " .. tostring(cfg.CHAT_NOTIFICATION_SFX))
            end
            return
        end
    end

    local soundValid, isSoundValid = pcall(function() return notificationSound:IsValid() end)
    if not soundValid or not isSoundValid then
        notificationSound = nil
        return
    end

    if not gameplayStatics then
        local ok, value = pcall(StaticFindObject, "/Script/Engine.Default__GameplayStatics")
        if ok then gameplayStatics = value end
    end
    if not gameplayStatics then return end

    local world = utils.getWorld()
    if not world then return end
    local ok, err = pcall(function()
        gameplayStatics:PlaySound2D(
            world,
            notificationSound,
            cfg.CHAT_NOTIFICATION_VOLUME,
            1.0,
            0.0,
            nil,
            nil,
            true
        )
    end)
    if not ok then log.log("[CHAT] Notification sound failed: " .. tostring(err)) end
end

function M.addMessage(sender, text, audience, targetTeam, notify)
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
    if notify == true then playIncomingNotification() end
    M.feedTicks = cfg.CHAT_FEED_TICKS
    if M.inMatch then
        M.showWidget()
        setFeedVisible(true)
    end
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

-- Chat identity is local-session identity, not match-actor state. Spectators
-- may have no gameplay pawn and PlayerNamePrivate is not authoritative even
-- for players. Presence and sender labels therefore share identity.lua's
-- UPMPlayerUIData-backed resolver.
-- See docs/learnings/identity-display-name-substrate-replaces-heuristics.md.

-- ---------------------------------------------------------------------------
-- Match detection
-- Gate: GameState_Game_C.CurrentMatchSeed is non-zero.
-- The seed is replicated from the server when a match starts and stays
-- stable until the match ends. Pawn-based detection (used previously) gave
-- false negatives during KOs / round resets where the local Pawn is briefly
-- nil, causing the chat to vanish mid-match. The seed doesn't blip.
-- ---------------------------------------------------------------------------

local function readMatchState()
    local ok, seed, phase = pcall(function()
        local gs = FindFirstOf("GameState_Game_C")
        if not gs or not gs:IsValid() then
            gs = FindFirstOf("GameState_Tutorial_C")
        end
        if not gs or not gs:IsValid() then return nil end
        local matchSeed = gs.CurrentMatchSeed
        -- The field/EMatchPhase.InGame=5 are present in the stored game dump.
        -- A failed phase read must not break the established seed room gate.
        local phaseOk, matchPhase = pcall(function() return gs.CurrentMatchPhase end)
        return matchSeed, phaseOk and matchPhase or nil
    end)
    if ok and seed and type(seed) == "number" and seed ~= 0 then
        return seed, type(phase) == "number" and phase or nil
    end
    return nil
end

local function readMatchSeed()
    return (readMatchState())
end

local function isInMatch()
    return readMatchSeed() ~= nil
end

local matchProbeTimer = 0
local MATCH_PROBE_TICKS = 30  -- retry every ~1s while waiting for seed

function M.showWidget()
    if not widgetAlive() or overlaysActive() then return end
    if M.visible then return end
    pcall(function() M.widget:SetVisibility(cfg.VIS_HIT_TEST_INVISIBLE) end)
    M.visible = true
    log.log("[CHAT] Widget attached for match")
end

function M.hideWidget()
    if not widgetAlive() then return end
    setFeedVisible(false)
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

local function normalizeAssignedTeam(team)
    local n = tonumber(team)
    -- EAssignedTeam is TeamZero=0, TeamOne=1, TeamTwo=2.
    -- The relay uses compact routing indices: TeamOne -> 0, TeamTwo -> 1.
    if n == 1 then return 0 end
    if n == 2 then return 1 end
    return nil
end

local function teamLabel(team)
    local n = tonumber(team)
    if n ~= 0 and n ~= 1 then n = nil end
    if n == nil then return "unknown" end
    return "Team " .. tostring(n + 1)
end

local function boolLabel(value)
    if value == true then return "true" end
    if value == false then return "false" end
    return "nil"
end

local function readValidObject(obj)
    if not obj then return false end
    local ok, valid = pcall(function() return obj:IsValid() end)
    if ok then return valid == true end
    return true
end

local function readLocalPlayerChatState()
    local state = {
        team = nil,
        rawTeam = nil,
        isSpectator = false,
        signals = {
            isOnlyFn = nil,
            isOnlyField = nil,
            isSpectatorFn = nil,
            isSpectatorField = nil,
            hasSpectatorPawn = nil,
            hasSpectatedPlayer = nil,
        },
    }

    local ok = pcall(function()
        local pc = utils.getPlayerController()
        if not pc or not pc:IsValid() then return end
        local ps = pc.PlayerState
        if not ps or not ps:IsValid() then return end

        state.rawTeam = tonumber(ps.AssignedTeam)

        local okOnlyFn, onlyFn = pcall(function() return ps:IsOnlyASpectator() end)
        if okOnlyFn then state.signals.isOnlyFn = onlyFn == true end

        local okOnlyField, onlyField = pcall(function() return ps.bOnlySpectator end)
        if okOnlyField then state.signals.isOnlyField = onlyField == true end

        local okSpecFn, specFn = pcall(function() return ps:IsSpectator() end)
        if okSpecFn then state.signals.isSpectatorFn = specFn == true end

        local okSpecField, specField = pcall(function() return ps.bIsSpectator end)
        if okSpecField then state.signals.isSpectatorField = specField == true end

        local okSpectatorPawn, spectatorPawn = pcall(function() return pc:GetSpectatorPawn() end)
        if okSpectatorPawn then state.signals.hasSpectatorPawn = readValidObject(spectatorPawn) end

        local okSpectatedPlayer, spectatedPlayer = pcall(function() return ps:GetSpectatedPlayer() end)
        if okSpectatedPlayer then state.signals.hasSpectatedPlayer = readValidObject(spectatedPlayer) end
    end)

    if not ok then return state end

    state.isSpectator =
        state.signals.isOnlyFn == true or
        state.signals.isOnlyField == true or
        state.signals.isSpectatorFn == true or
        state.signals.isSpectatorField == true

    if not state.isSpectator then
        state.team = normalizeAssignedTeam(state.rawTeam)
    end

    return state
end

local CHANNEL_WIDGETS = {
    all = "ChannelAll",
    team = "ChannelTeam",
    team1 = "ChannelTeam1",
    team2 = "ChannelTeam2",
}

local CHANNEL_HINTS = {
    all = "Message everyone",
    team = "Message team",
    team1 = "Message Team 1",
    team2 = "Message Team 2",
}

local function channelOrderForState(state)
    if state.isSpectator == true then
        return { "all", "team1", "team2" }
    end
    if state.team ~= nil then
        return { "team", "all" }
    end
    return { "all" }
end

local function channelAllowed(state, channel)
    for _, candidate in ipairs(channelOrderForState(state)) do
        if candidate == channel then return true end
    end
    return false
end

local function defaultChannelForState(state)
    if state.isSpectator == true then return "all" end
    if state.team ~= nil then return "team" end
    return "all"
end

local function channelRoleForState(state)
    if state.isSpectator == true then return "spectator" end
    if state.team ~= nil then return "player:" .. tostring(state.team) end
    return "unknown"
end

local function applyAudienceControls(state, restoreInputFocus)
    if not widgetAlive() then return end
    local role = channelRoleForState(state)
    if M.channelRole ~= role then
        M.channelRole = role
        if not M.channelTouched then
            M.selectedChannel = defaultChannelForState(state)
        end
    end
    if not channelAllowed(state, M.selectedChannel) then
        M.selectedChannel = defaultChannelForState(state)
    end

    for channel, widgetName in pairs(CHANNEL_WIDGETS) do
        local control = widgetChild(widgetName)
        if control then
            local allowed = channelAllowed(state, channel)
            local selected = allowed and channel == M.selectedChannel
            pcall(function()
                control:SetVisibility(selected and cfg.VIS_VISIBLE or cfg.VIS_COLLAPSED)
                control:SetIsChecked(selected)
            end)
        end
    end

    local input = widgetChild("ChatInput")
    if input then
        local hint = CHANNEL_HINTS[M.selectedChannel] or "Message"
        pcall(function() input:SetHintText(FText(hint)) end)
    end

    if restoreInputFocus then
        if input then pcall(function() input:SetKeyboardFocus() end) end
    end
end

local function selectChannel(channel, restoreInputFocus)
    local state = readLocalPlayerChatState()
    if not channelAllowed(state, channel) then return false end
    M.selectedChannel = channel
    M.channelTouched = true
    applyAudienceControls(state, restoreInputFocus == true)
    return true
end

local function cycleChannel(direction)
    if not M.isTyping() then return end
    local state = readLocalPlayerChatState()
    local order = channelOrderForState(state)
    if #order < 2 then return end

    local index = 1
    for i, channel in ipairs(order) do
        if channel == M.selectedChannel then
            index = i
            break
        end
    end
    local nextIndex = ((index - 1 + direction) % #order) + 1
    selectChannel(order[nextIndex], true)
end

local function pollAudienceControls()
    if not M.isTyping() then return end
    local state = readLocalPlayerChatState()
    if not channelAllowed(state, M.selectedChannel) then
        M.selectedChannel = defaultChannelForState(state)
        applyAudienceControls(state, false)
        return
    end

    -- Only the selected recipient control is visible. Clicking it toggles the
    -- checkbox off; treat that as a request to cycle to the next valid target.
    local selected = widgetChild(CHANNEL_WIDGETS[M.selectedChannel])
    local ok, checked = pcall(function() return selected and selected:IsChecked() end)
    if ok and checked == false then
        cycleChannel(1)
    elseif not ok then
        applyAudienceControls(state, true)
    end
end

local function selectedAudienceForState(state)
    if M.selectedChannel == "all" then return "all", nil end
    if M.selectedChannel == "team" and state.isSpectator ~= true and state.team ~= nil then
        return "team", state.team
    end
    if M.selectedChannel == "team1" and state.isSpectator == true then return "team", 0 end
    if M.selectedChannel == "team2" and state.isSpectator == true then return "team", 1 end
    return "all", nil
end

local function spectatorSignalSummary(state)
    local signals = state.signals or {}
    return "specSignals{onlyFn=" .. boolLabel(signals.isOnlyFn)
        .. ", onlyField=" .. boolLabel(signals.isOnlyField)
        .. ", specFn=" .. boolLabel(signals.isSpectatorFn)
        .. ", specField=" .. boolLabel(signals.isSpectatorField)
        .. ", spectatorPawn=" .. boolLabel(signals.hasSpectatorPawn)
        .. ", spectatedPlayer=" .. boolLabel(signals.hasSpectatedPlayer)
        .. "}"
end

function M.deriveRoomCode()
    local seed = readMatchSeed()
    if not seed then return nil end
    local code = seedToCode(seed)
    return code
end

local function parseChatAudience(text)
    local trimmed = text:match("^%s*(.-)%s*$") or ""
    if trimmed == "" then return nil end

    local state = readLocalPlayerChatState()
    local defaultTeam = state.team
    local isSpectator = state.isSpectator == true
    local cmd, rest = trimmed:match("^/(%S+)%s*(.*)$")
    if not cmd then
        local audience, targetTeam = selectedAudienceForState(state)
        return audience, targetTeam, trimmed
    end

    local lower = cmd:lower()
    local body = (rest or ""):match("^%s*(.-)%s*$") or ""

    if lower == "all" or lower == "a" then
        if body == "" then return nil end
        return "all", nil, body
    end

    if lower == "team" or lower == "t" then
        if body == "" then return nil end
        if isSpectator then
            local audience, targetTeam = selectedAudienceForState(state)
            if audience == "team" then return audience, targetTeam, body end
            return nil, nil, nil, "Choose Team 1 or Team 2 before using /team."
        end
        if defaultTeam == nil then return nil end
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
        if isSpectator then
            return "team", targetTeam, body
        end
        if defaultTeam == nil then
            return nil, nil, nil, "Your team is not known yet. Use /all or try again in a moment."
        end
        if targetTeam ~= defaultTeam then
            return nil, nil, nil, "Only spectators can send directly to the other team. Use /all to message everyone."
        end
        return "team", targetTeam, body
    end

    -- Unknown slash commands are treated as normal chat text so a player can
    -- still send "/shrug" without the command parser eating the message.
    local audience, targetTeam = selectedAudienceForState(state)
    return audience, targetTeam, trimmed
end

local function tryJoinRoom()
    local seed, phase = readMatchState()
    local code = seed and seedToCode(seed) or nil
    if seed ~= presenceSeed then
        presenceSeed = seed
        opponentsRevealed = false
        M.currentRevealOpponents = false
    end
    -- EMatchPhase is NOT ordered: bans are 19 and preselection is 20.
    -- Unlock only on explicit gameplay evidence for this seed, then retain
    -- it through KOs, goals and between-set drafts. Never gate on Pawn.
    if seed and phase == 5 then opponentsRevealed = true end
    local state = readLocalPlayerChatState()
    local team = state.team
    local rawTeam = state.rawTeam
    local isSpectator = state.isSpectator == true
    local friendlyName = identity.resolveDisplayName()
    local username = friendlyName or M.currentUsername or identity.getBestLocalName()
    if seed == M.currentSeed and code == M.currentRoom and team == M.currentTeam
        and isSpectator == M.currentSpectator and username == M.currentUsername
        and opponentsRevealed == M.currentRevealOpponents then return end
    -- Invalidate before identity retries too: a delayed display-name read must
    -- not leave a previous team/room's names visible while waiting to rejoin.
    -- Mark the cached join invalid even if the metadata later reverts; the
    -- new revision still needs a relay round-trip before it can accept names.
    M.currentSeed = nil
    M.presenceRevision = M.presenceRevision + 1
    M.presence = {}
    rebuildPresence()
    -- Resolve the name on every attempt. identity.lua caches only the
    -- authoritative UPMPlayerUIData value, so a non-nil result is safe to put
    -- in ws._username on the relay side.
    --
    -- Why this gate matters: the relay caches `ws._username` from the JOIN
    -- frame and uses it for every subsequent presence broadcast. Waiting here
    -- prevents a transient or synthetic fallback from becoming the long-lived
    -- roster label. If the budget expires, the periodic room check upgrades a
    -- fallback join as soon as identity resolution succeeds.
    local missing = nil
    if not code then
        missing = "match room"
    elseif not friendlyName then
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
    if missing and not M.currentRoom then
        -- Friendly name never resolved within the budget. Fall back so chat
        -- still works locally; presence uses a neutral Player-#### / "Me"
        -- fallback and upgrades automatically when the friendly name resolves.
        log.log("[CHAT] Friendly name never resolved within " .. ROOM_MAX_RETRIES .. " retries; joining with fallback")
    end
    M.currentRoom = code
    M.currentSeed = seed
    M.currentTeam = team
    M.currentSpectator = isSpectator
    M.currentUsername = username
    M.currentRevealOpponents = opponentsRevealed
    local roleLabel = isSpectator and "spectator" or "player"
    log.log("[CHAT] Joining room: " .. code .. " as " .. username
        .. " (" .. roleLabel .. ", relay team: " .. teamLabel(team)
        .. ", raw team: " .. tostring(rawTeam) .. ", "
        .. spectatorSignalSummary(state) .. ", presence: "
        .. (opponentsRevealed and "match" or "teammates")
        .. ", phase: " .. tostring(phase) .. ")")
    if M.onRoomChange then
        pcall(function()
            M.onRoomChange(code, username, team, isSpectator, opponentsRevealed, M.presenceRevision)
        end)
    end
end

local function leaveRoom()
    presenceSeed = nil
    opponentsRevealed = false
    M.currentRevealOpponents = false
    if not M.currentRoom then return end
    log.log("[CHAT] Leaving room: " .. M.currentRoom)
    M.currentRoom = nil
    M.currentSeed = nil
    M.currentTeam = nil
    M.currentSpectator = false
    M.currentUsername = nil
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
    M.feedTicks = 0
    M.selectedChannel = nil
    M.channelRole = nil
    M.channelTouched = false
    rebuildHistory()
    M.hideWidget()
    leaveRoom()
    matchProbeTimer = MATCH_PROBE_TICKS
    if M.onMatchEnded then
        pcall(M.onMatchEnded, reason)
    end
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
                setFeedVisible(false)
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
            else
                tryJoinRoom()
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Open / Close
-- Blueprint handles: IsTyping, input focus/mode, the outside-click catcher,
--                    and focused-only presence visibility.
-- Lua handles: keybind gating, text clearing, audience state, match gating,
--              panel height, and passive/settings visibility.
-- ---------------------------------------------------------------------------

local wasTyping = false

local function applyClosedPresentation()
    setChatHeight(cfg.CHAT_PASSIVE_HEIGHT, false)
    if overlaysActive() then
        M.hideWidget()
        return
    end
    if M.inMatch then
        M.showWidget()
        pcall(function() M.widget:SetVisibility(cfg.VIS_HIT_TEST_INVISIBLE) end)
        setFeedVisible(M.feedTicks > 0)
    end
end

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
    if overlaysActive() then
        log.log("[CHAT] Cannot open: native menu is active")
        return
    end
    M.showWidget()
    pcall(function() M.widget:SetVisibility(cfg.VIS_SELF_HIT_TEST_INVIS) end)
    applyFocusedHeight(readFocusedHeight())
    setFeedVisible(true)
    applyAudienceControls(readLocalPlayerChatState(), false)
    clearInputText()
    pcall(function() M.widget.PendingMessage = "" end)
    -- BP OpenInput sets IsTyping=true and plays the open animation.
    log.try("OpenInput", function() M.widget:OpenInput() end)
    wasTyping = M.isTyping()
end

function M.close()
    if not widgetAlive() then return end
    resetResizeDrag(true)
    -- BP CloseInput sets IsTyping=false, plays close anim, and resets visibility
    -- back to HitTestInvisible. Don't touch typing state or visibility here.
    log.try("CloseInput", function() M.widget:CloseInput() end)
    wasTyping = false
    applyClosedPresentation()
end

local function unwrapHookValue(value)
    if value == nil then return nil end
    local ok, unwrapped = pcall(function() return value:get() end)
    if ok and unwrapped then return unwrapped end
    return value
end

local function overlayKindFromContext(context)
    local object = unwrapHookValue(context)
    if not object then return nil end
    local ok, className = pcall(function()
        return object:GetClass():GetFName():ToString()
    end)
    if not ok or not className then return nil end
    -- WBP_InGameMenu_PC is the always-on match HUD, not the Escape screen.
    -- See docs/learnings/chat-settings-lifecycle-suppression.md.
    if className:find("WBP_SettingsHub", 1, true) then return "settings" end
    return nil
end

local function setOverlayFlag(kind, active, source)
    if not kind or M.overlayFlags[kind] == active then return end
    M.overlayFlags[kind] = active
    log.log("[CHAT] Native overlay " .. kind .. "=" .. tostring(active) .. " (" .. source .. ")")

    if overlaysActive() then
        if M.isTyping() then M.close() else M.hideWidget() end
    elseif M.inMatch then
        M.showWidget()
        applyClosedPresentation()
    end
end

local function handleOverlayNavigation(context, active, source)
    local kind = overlayKindFromContext(context)
    if kind then setOverlayFlag(kind, active, source) end
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

local function tickChatPresentation()
    if historyAnchorTicks > 0 then
        scrollHistoryToEnd()
        historyAnchorTicks = historyAnchorTicks - 1
    end

    local typing = M.isTyping()
    if typing then
        tickChatResize()
        pollAudienceControls()
    elseif wasTyping then
        applyClosedPresentation()
    end
    wasTyping = typing

    if not typing and M.feedTicks > 0 then
        M.feedTicks = M.feedTicks - 1
        if M.feedTicks == 0 then setFeedVisible(false) end
    end
end

function M.pollPending()
    if not widgetAlive() then return end
    tickChatPresentation()

    local raw = readPending()
    if not raw or raw == "" then return end

    pcall(function() M.widget.PendingMessage = "" end)
    M.close()

    local str = raw:match("^%s*(.-)%s*$") or ""
    if str == "" then return end
    local audience, targetTeam, body, errorMessage = parseChatAudience(str)
    if errorMessage then
        M.addMessage("OSPlus", errorMessage, "all", nil)
        return
    end
    if not body or body == "" then return end

    local sender = identity.resolveDisplayName() or M.currentUsername or identity.getBestLocalName()
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
    local matchEndedByMapLoad = M.inMatch
    -- The previous map's widget is being destroyed by the engine right now.
    -- Touching it (SetVisibility, CloseInput, anything) can crash natively
    -- because pcall does NOT catch C++ access violations on freed UObjects.
    -- Just drop our reference; ensureWidget() will find a fresh widget
    -- on the new map after BPModLoader respawns ModActor.
    M.widget = nil
    leaveRoom()
    M.visible = false
    M.inMatch = false
    M.currentRoom = nil
    M.currentTeam = nil
    M.currentSpectator = false
    M.currentUsername = nil
    M.roomDelayTicks = 0
    M.feedTicks = 0
    M.feedVisible = false
    M.selectedChannel = nil
    M.channelRole = nil
    M.channelTouched = false
    M.overlayFlags = { settings = false }
    wasTyping = false
    roomRetries = 0
    matchProbeTimer = 0
    matchExitTimer = 0
    M.messages = {}
    M.presence = {}
    notificationSound = nil
    gameplayStatics = nil
    notificationLoadFailed = false
    resizeMouseReadFailed = false
    resetResizeDrag(false)
    if matchEndedByMapLoad and M.onMatchEnded then
        pcall(M.onMatchEnded, "map loaded")
    end
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

    RegisterKeyBind(cfg.CHAT_CHANNEL_KEY, function()
        ExecuteInGameThread(function() cycleChannel(1) end)
    end)

    local shiftTabOk, shiftTabErr = pcall(function()
        RegisterKeyBind(cfg.CHAT_CHANNEL_KEY, { ModifierKey.SHIFT }, function()
            ExecuteInGameThread(function() cycleChannel(-1) end)
        end)
    end)
    if not shiftTabOk then
        log.log("[CHAT] Shift+Tab channel keybind failed: " .. tostring(shiftTabErr))
    end

    local navToOk, navToErr = pcall(function()
        RegisterCustomEvent("OnNavigatedTo", function(context)
            handleOverlayNavigation(context, true, "OnNavigatedTo")
        end)
    end)
    if not navToOk then log.log("[CHAT] OnNavigatedTo event failed: " .. tostring(navToErr)) end

    local navAwayOk, navAwayErr = pcall(function()
        RegisterCustomEvent("OnNavigatedAway", function(context)
            handleOverlayNavigation(context, false, "OnNavigatedAway")
        end)
    end)
    if not navAwayOk then log.log("[CHAT] OnNavigatedAway event failed: " .. tostring(navAwayErr)) end

    local navBackOk, navBackErr = pcall(function()
        RegisterCustomEvent("OnNavBack", function(context)
            handleOverlayNavigation(context, false, "OnNavBack")
        end)
    end)
    if not navBackOk then log.log("[CHAT] OnNavBack event failed: " .. tostring(navBackErr)) end

    local closeSelfOk, closeSelfErr = pcall(function()
        RegisterHook("/Script/OdyUI.OdyMenu:CloseSelf", function() end, function(context)
            handleOverlayNavigation(context, false, "CloseSelf")
        end)
    end)
    if not closeSelfOk then log.log("[CHAT] CloseSelf hook failed: " .. tostring(closeSelfErr)) end

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
