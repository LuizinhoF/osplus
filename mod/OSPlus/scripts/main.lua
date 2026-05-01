--[[
    OSPlus — Team Chat (feature 1 of N)
    ===================================
    In-match text chat between teammates via WebSocket relay.

    Keybinds:
      Enter    = Open chat input
      Escape   = Cancel chat input
]]

local cfg    = require("config")
local log    = require("log")
local utils  = require("utils")
-- DISABLED: ping system (dead code, kept for future re-enablement)
-- local assets = require("assets")
-- local pings  = require("pings")
-- local wheel  = require("wheel")
local ipc    = require("ipc")
local chat   = require("chat")
-- identity: required for the side effect of its module-load RegisterHook
-- on PMIdentitySubsystem:GetIdentityState during cold-start engine init
-- (BEFORE login completes). Per ADR 0001 R-B substrate +
-- ue4ss-cold-start-hook-install-pattern learning, a keypress-driven or
-- lazy install would miss the identity-flow window. profile.lua reads
-- the resolved PID through identity.onPrometheusIdResolved.
require("identity")
-- profile: subscribes to identity.onPrometheusIdResolved at init() time and
-- emits a single profile_upsert IPC message once display name is also
-- resolved. The sidecar then PUTs /api/profiles/{pid} on the relay. Per
-- ADR 0002 + in-game-profile-mvp Slice 1-C.
local profile = require("profile")

-- Wire cross-module callbacks
-- DISABLED: ping callbacks
-- pings.onPingFired   = function(pingType, posVec) ipc.writePingToOutbox(pingType, posVec) end
-- ipc.spawnRemotePing = pings.spawn
chat.onChatSent       = function(sender, text) ipc.writeChatToOutbox(sender, text) end
ipc.onChatReceived    = function(sender, text) chat.addMessage(sender, text) end
chat.onRoomChange     = function(room, username) ipc.writeRoomChange(room, username) end
chat.onRoomLeave      = function() ipc.writeRoomLeave() end
ipc.onPresenceReceived = function(members) chat.setPresence(members) end

-- Wire each feature's engine integration. Per .cursor/rules/mod-architecture.mdc
-- "feature owns its engine integration": each module's M.init() registers
-- its own keybinds, UFunction hooks, and native delegates — main.lua just
-- triggers them once. Engine-global lifecycle (map load, below) is the one
-- exception, multiplexed here because it crosses features.
chat.init()
profile.init()

-- ============================================================================
-- Sidecar auto-launch
-- ============================================================================

local function launchSidecar()
    -- Kill any leftover sidecar from a previous session
    os.execute('taskkill /f /im OSPlus.exe >nul 2>&1')

    local candidates = {
        ".\\ue4ss\\Mods\\OSPlus\\sidecar",
        ".\\Mods\\OSPlus\\sidecar",
    }

    for _, sidecarDir in ipairs(candidates) do
        local sidecarExe = sidecarDir .. "\\OSPlus.exe"
        local vbsLauncher = sidecarDir .. "\\launch_hidden.vbs"
        local check = io.open(sidecarExe, "r")
        if check then
            check:close()
            -- Prefer wscript+VBS shim so no console window appears.
            -- The sidecar exe is built from node.exe (console subsystem), so
            -- launching it directly always allocates a console. wscript.exe
            -- runs a .vbs silently and the .vbs spawns the exe with window
            -- state 0 (hidden), inheriting no console.
            local vbsCheck = io.open(vbsLauncher, "r")
            if vbsCheck then
                vbsCheck:close()
                os.execute('start "" wscript.exe "' .. vbsLauncher .. '" "OSPlus.exe"')
                log.log("[SIDECAR] Launched (hidden) " .. sidecarExe)
            else
                -- Fallback: visible console launch if shim is missing.
                os.execute('start "" /D "' .. sidecarDir .. '" "' .. sidecarExe .. '"')
                log.log("[SIDECAR] Launched (visible, no vbs shim) " .. sidecarExe)
            end
            return
        end
    end

    log.log("[SIDECAR] Exe not found in any known Mods path, skipping auto-launch")
end

-- ============================================================================
-- Initialization
-- ============================================================================

log.ensureDir()

local f = io.open(cfg.LOG_FILE, "w")
if f then
    f:write("=== OSPlus " .. cfg.VERSION .. " ===\n")
    f:write("Started: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
    f:close()
end

ipc.truncateInbox()
ipc.writeHeartbeat()  -- prime heartbeat before sidecar starts polling
launchSidecar()

print("==============================================\n")
print("[OSPlus] " .. cfg.VERSION .. "\n")
print("[OSPlus] Keybinds:\n")
print("[OSPlus]   Enter = Open chat\n")
print("[OSPlus]   Esc   = Cancel chat\n")
print("[OSPlus] IPC:    " .. cfg.IPC_DIR .. "\n")
print("==============================================\n")

RegisterLoadMapPostHook(function()
    log.log("[EVENT] Map loaded")
    chat.reset()
    ipc.truncateInbox()
    chat.onMapLoaded()
end)

-- Probe for the initial map (already loaded before mod starts)
chat.onMapLoaded()

local tickLoopStarted = false

LoopAsync(30, function()
    if not tickLoopStarted then
        tickLoopStarted = true
        log.log("[TICK] Tick loop running")
    end

    pcall(chat.tickMatchProbe)
    pcall(chat.pollPending)
    pcall(profile.tick)
    ipc.poll()

    return false
end)

log.log("Ready! Press Enter in-match to chat.")
