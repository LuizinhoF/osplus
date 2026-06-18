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
local i18n   = require("localization")
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
-- Truncate log + write header BEFORE module inits; module inits log
-- via append, and a later truncation would wipe their startup output.
log.ensureDir()
local f = io.open(cfg.LOG_FILE, "w")
if f then
    f:write("=== OSPlus " .. cfg.VERSION .. " ===\n")
    f:write("Started: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
    f:close()
end

i18n.init()
chat.init()
profile.init()

-- Production emote-tab override. Hooks WBP_Panel_StrikerCosmetics_C:SetActivePanel
-- via RegisterCustomEvent, redirects Emote-sub-tab clicks to our cooked
-- WBP_OSPlusEmoteLoadout widget. See mod/OSPlus/scripts/emote_loadout.lua and
-- docs/learnings/customize-page-tab-routing-architecture.md.
local emote_loadout = require("emote_loadout"); emote_loadout.init()

-- swap_test_a1 disarmed 2026-05-17 — production module (emote_loadout) supersedes
-- the throwaway validation experiments. Keeping the file in tree for future
-- debug reference; can delete entirely once we're comfortable.
-- local swap_test_a1 = require("swap_test_a1"); swap_test_a1.init()

-- ============================================================================
-- Sidecar auto-launch
-- ============================================================================

local function launchSidecar()
    -- Kill any leftover sidecar from a previous session
    os.execute('taskkill /f /im OSPlus.exe >nul 2>&1')

    -- Under Proton/Wine, wscript/VBS is less reliable than launching the
    -- Windows sidecar exe directly. The sidecar still runs inside the same
    -- Windows compatibility environment as the game, which keeps
    -- %LOCALAPPDATA%\OSPlus shared with the Lua IPC files.
    local runningUnderProton =
        os.getenv("STEAM_COMPAT_DATA_PATH") ~= nil or
        os.getenv("STEAM_COMPAT_CLIENT_INSTALL_PATH") ~= nil or
        os.getenv("WINEPREFIX") ~= nil

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
            if vbsCheck and not runningUnderProton then
                vbsCheck:close()
                os.execute('start "" wscript.exe "' .. vbsLauncher .. '" "OSPlus.exe"')
                log.log("[SIDECAR] Launched (hidden) " .. sidecarExe)
            else
                if vbsCheck then vbsCheck:close() end
                -- Fallback: visible console launch if shim is missing.
                -- On Proton/Wine this is the preferred path; console-window
                -- behavior is owned by the compatibility layer rather than by
                -- native Windows shell UX.
                os.execute('start "" /D "' .. sidecarDir .. '" "' .. sidecarExe .. '"')
                if runningUnderProton then
                    log.log("[SIDECAR] Launched direct for Proton/Wine " .. sidecarExe)
                else
                    log.log("[SIDECAR] Launched (visible, no vbs shim) " .. sidecarExe)
                end
            end
            return
        end
    end

    log.log("[SIDECAR] Exe not found in any known Mods path, skipping auto-launch")
end

-- ============================================================================
-- Initialization
-- ============================================================================

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
    pcall(i18n.tick)
    pcall(profile.tick)
    ipc.poll()

    return false
end)

log.log("Ready! Press Enter in-match to chat.")
