local cfg   = require("config")
local log   = require("log")
local json  = require("json")
local utils = require("utils")

local M = {}

M.inboxOffset = 0
M.tickCounter = 0
M.heartbeatCounter = 0
-- DISABLED: ping callbacks
-- M.spawnRemotePing = nil
M.onChatReceived     = nil  -- set by main.lua to chat.addMessage
M.onPresenceReceived = nil  -- set by main.lua to chat.setPresence
M.onUpdateAvailable  = nil  -- set by main.lua to update_notification

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- DISABLED: ping type lookup (dead code)
--[[
local function findPingTypeByKey(key)
    for _, pt in ipairs(cfg.PING_TYPES) do
        if pt.key == key then return pt end
    end
    return cfg.PING_TYPES[1]
end
]]

-- ---------------------------------------------------------------------------
-- Outbox (Lua -> sidecar)
-- ---------------------------------------------------------------------------

function M.writeChatToOutbox(sender, text, audience, targetTeam)
    local msg = json.encode({
        type       = "chat",
        sender     = sender,
        text       = text,
        audience   = audience,
        targetTeam = targetTeam,
        ts         = os.time(),
    })
    local f = io.open(cfg.OUTBOX_FILE, "a")
    if f then
        f:write(msg .. "\n")
        f:close()
    end
end

-- DISABLED: ping outbox (dead code)
--[[
function M.writePingToOutbox(pingType, posVec)
    local msg = json.encode({
        type = "ping",
        key  = pingType.key,
        x    = tonumber(posVec.X) or 0,
        y    = tonumber(posVec.Y) or 0,
        z    = tonumber(posVec.Z) or 0,
        ts   = os.time(),
    })
    local f = io.open(cfg.OUTBOX_FILE, "a")
    if f then
        f:write(msg .. "\n")
        f:close()
    end
end
]]

function M.writeRoomChange(roomCode, username, team, isSpectator, revealOpponents, presenceRevision)
    local msg = json.encode({
        type      = "room_change",
        room      = roomCode,
        username  = username,
        team      = team,
        spectator = isSpectator == true,
        revealOpponents = revealOpponents == true,
        presenceRevision = presenceRevision,
        ts        = os.time(),
    })
    local f = io.open(cfg.OUTBOX_FILE, "a")
    if f then
        f:write(msg .. "\n")
        f:close()
    end
end

function M.writeRoomLeave()
    local msg = json.encode({
        type = "room_leave",
        ts   = os.time(),
    })
    local f = io.open(cfg.OUTBOX_FILE, "a")
    if f then
        f:write(msg .. "\n")
        f:close()
    end
end

local UPDATE_CHECK_REASONS = {
    queue_entered = true,
    match_completed = true,
}

function M.writeUpdateCheck(reason)
    if type(reason) ~= "string" or not UPDATE_CHECK_REASONS[reason] then
        log.log("[IPC] Refused invalid update_check reason")
        return false
    end

    local msg = json.encode({
        type   = "update_check",
        reason = reason,
        ts     = os.time(),
    })
    local f = io.open(cfg.OUTBOX_FILE, "a")
    if not f then
        log.log("[IPC] Could not open outbox for update_check")
        return false
    end
    f:write(msg .. "\n")
    f:close()
    return true
end

-- Profile upsert (Lua -> sidecar -> relay's PUT /api/profiles/{pid}).
--
-- payload is a flat table; nil-valued fields are silently dropped by the
-- json encoder (Lua's pairs() doesn't visit unset keys), which exactly
-- matches the sidecar's `optStr` / `optInt` validators that treat absent
-- and explicit-null the same. Required: prometheusId, displayName.
-- Optional: steamId, currentPlatform, logoId, nameplateId, emoticonId,
-- titleId, masteryLevel.
function M.writeProfileUpsertToOutbox(payload)
    if type(payload) ~= "table" then return end
    payload.type = "profile_upsert"
    payload.ts   = os.time()
    local msg = json.encode(payload)
    local f = io.open(cfg.OUTBOX_FILE, "a")
    if f then
        f:write(msg .. "\n")
        f:close()
    end
end

-- ---------------------------------------------------------------------------
-- Inbox (sidecar -> Lua)
-- ---------------------------------------------------------------------------

local function cleanFlatString(value, maxLength)
    if type(value) ~= "string" then return nil end
    local cleaned = value:match("^%s*(.-)%s*$")
    if cleaned == "" or #cleaned > maxLength then return nil end
    if cleaned:find("[\r\n%z]") then return nil end
    return cleaned
end

local function cleanVersion(value)
    local version = cleanFlatString(value, 64)
    if not version then return nil end
    local body = version
    if body:sub(1, 1) == "v" then body = body:sub(2) end
    if not body:match("^%d+%.%d+%.%d+$") then return nil end
    return body
end

local function cleanOptionalVersion(value)
    if value == nil then return true, nil end
    local cleaned = cleanVersion(value)
    return cleaned ~= nil, cleaned
end

local function cleanOptionalUrl(value)
    if value == nil then return true, nil end
    local cleaned = cleanFlatString(value, 2048)
    if not cleaned then return false, nil end
    if cleaned:sub(1, 7) ~= "http://" and cleaned:sub(1, 8) ~= "https://" then
        return false, nil
    end
    return true, cleaned
end

function M.readInbox()
    local f = io.open(cfg.INBOX_FILE, "r")
    if not f then return end

    local content = f:read("*a")
    f:close()

    if not content or #content == 0 then return end
    if #content <= M.inboxOffset then return end

    local newData = content:sub(M.inboxOffset + 1)
    M.inboxOffset = #content

    for line in newData:gmatch("[^\n]+") do
        local msg = json.decode(line)
        -- DISABLED: ping handling (dead code)
        --[[
        if msg and msg.type == "ping" and msg.key and msg.x then
            local pt = findPingTypeByKey(msg.key)
            local pos = utils.makeVec(msg.x, msg.y, msg.z or 0)
            log.log("[IPC] Remote ping: " .. pt.name .. " at " .. tostring(msg.x) .. "," .. tostring(msg.y))
            if M.spawnRemotePing then
                M.spawnRemotePing(pos, pt, true)
            end
        else]]
        if msg and msg.type == "chat" and msg.sender and msg.text then
            log.log("[IPC] Remote chat: " .. tostring(msg.sender) .. ": " .. tostring(msg.text))
            if M.onChatReceived then
                M.onChatReceived(msg.sender, msg.text, msg.audience, msg.targetTeam)
            end
        elseif msg and msg.type == "presence" and type(msg.members) == "string" then
            -- Wire format: members is "\n"-joined string (json.lua is
            -- flat-objects-only so we can't ship a JSON array). Split into
            -- a table here so chat.setPresence sees a clean list and never
            -- has to know about the wire shape.
            local list = {}
            for name in msg.members:gmatch("[^\n]+") do
                list[#list + 1] = name
            end
            log.log("[IPC] Presence update: " .. tostring(#list) .. " member(s)")
            if M.onPresenceReceived then
                M.onPresenceReceived(list, msg.room, msg.presenceRevision, msg.revealOpponents)
            end
        elseif msg and msg.type == "update_available" then
            local latestVersion = cleanVersion(msg.latestVersion)
            local installedOk, installedVersion = cleanOptionalVersion(msg.installedVersion)
            local releaseOk, releaseUrl = cleanOptionalUrl(msg.releaseUrl)
            local assetOk, assetUrl = cleanOptionalUrl(msg.assetUrl)
            local timestampOk = msg.ts == nil or type(msg.ts) == "number"

            if latestVersion and installedOk and releaseOk and assetOk and timestampOk then
                log.log("[IPC] Update available: " .. latestVersion)
                if M.onUpdateAvailable then
                    M.onUpdateAvailable(latestVersion, installedVersion, releaseUrl, assetUrl)
                end
            else
                log.log("[IPC] Ignored malformed update_available message")
            end
        end
    end
end

function M.truncateInbox()
    local f = io.open(cfg.INBOX_FILE, "w")
    if f then
        f:write("")
        f:close()
    end
    M.inboxOffset = 0
end

-- ---------------------------------------------------------------------------
-- Tick polling (called from animation loop)
-- ---------------------------------------------------------------------------

-- Write a fresh timestamp so the sidecar knows the game is still alive.
-- The sidecar polls this file's content every few seconds and exits when
-- the timestamp goes stale (game closed, crashed, Alt+F4'd, killed).
function M.writeHeartbeat()
    local f = io.open(cfg.HEARTBEAT_FILE, "w")
    if f then
        f:write(tostring(os.time()))
        f:close()
    end
end

function M.poll()
    M.tickCounter = M.tickCounter + 1
    if M.tickCounter >= cfg.INBOX_POLL_INTERVAL then
        M.tickCounter = 0
        pcall(M.readInbox)
    end

    M.heartbeatCounter = M.heartbeatCounter + 1
    if M.heartbeatCounter >= cfg.HEARTBEAT_INTERVAL then
        M.heartbeatCounter = 0
        pcall(M.writeHeartbeat)
    end
end

return M
