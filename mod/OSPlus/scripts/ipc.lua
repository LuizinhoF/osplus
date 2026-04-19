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

function M.writeChatToOutbox(sender, text)
    local msg = json.encode({
        type   = "chat",
        sender = sender,
        text   = text,
        ts     = os.time(),
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

function M.writeRoomChange(roomCode, username)
    local msg = json.encode({
        type     = "room_change",
        room     = roomCode,
        username = username,
        ts       = os.time(),
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

-- ---------------------------------------------------------------------------
-- Inbox (sidecar -> Lua)
-- ---------------------------------------------------------------------------

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
                M.onChatReceived(msg.sender, msg.text)
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
                M.onPresenceReceived(list)
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
