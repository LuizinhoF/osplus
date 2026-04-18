local cfg    = require("config")
local log    = require("log")
local utils  = require("utils")
local assets = require("assets")

local M = {}

M.activePings = {}
M.lastSfxTime = 0
M.onPingFired = nil  -- callback set by main.lua for IPC outbox

-- ---------------------------------------------------------------------------
-- Position helpers
-- ---------------------------------------------------------------------------

local function getPawnPosition()
    local pc = utils.getPlayerController()
    if not pc:IsValid() then return nil end
    local pawn = pc.Pawn
    if not pawn or not pawn:IsValid() then return nil end
    local root = pawn.RootComponent
    if not root or not root:IsValid() then return nil end
    return root:K2_GetComponentLocation()
end

local function getCursorWorldPos()
    local pc = utils.getPlayerController()
    if not pc:IsValid() then return nil end

    local ok, result = pcall(function()
        local outLoc = utils.makeVec(0, 0, 0)
        local outDir = utils.makeVec(0, 0, 0)
        pc:DeprojectMousePositionToWorld(outLoc, outDir)

        if outLoc.X ~= 0 or outLoc.Y ~= 0 or outLoc.Z ~= 0 then
            local dz = tonumber(outDir.Z) or 0
            if dz ~= 0 then
                local t = -(tonumber(outLoc.Z) or 0) / dz
                if t > 0 then
                    return utils.makeVec(
                        (tonumber(outLoc.X) or 0) + (tonumber(outDir.X) or 0) * t,
                        (tonumber(outLoc.Y) or 0) + (tonumber(outDir.Y) or 0) * t,
                        0
                    )
                end
            end
            return outLoc
        end
        return nil
    end)
    if ok and result then return result end

    return getPawnPosition()
end

M.getPawnPosition  = getPawnPosition
M.getCursorWorldPos = getCursorWorldPos

-- ---------------------------------------------------------------------------
-- Animation math
-- ---------------------------------------------------------------------------

function M.computeScale(elapsed)
    if elapsed < cfg.ANIM_POP_END then
        local t = elapsed / cfg.ANIM_POP_DUR
        t = 1 - (1 - t) * (1 - t)
        return t * cfg.ANIM_POP_SCALE

    elseif elapsed < cfg.ANIM_SETTLE_END then
        local t = (elapsed - cfg.ANIM_POP_END) / cfg.ANIM_SETTLE_DUR
        t = t * t * (3 - 2 * t)
        return cfg.ANIM_POP_SCALE - (cfg.ANIM_POP_SCALE - 1.0) * t

    elseif elapsed < cfg.ANIM_SHRINK_START then
        local pulseDur = cfg.ANIM_SHRINK_START - cfg.ANIM_SETTLE_END
        local t = (elapsed - cfg.ANIM_SETTLE_END) / pulseDur
        return 1.0 + cfg.ANIM_PULSE_AMP * math.sin(t * cfg.ANIM_PULSE_CYCLES * cfg.TWO_PI)

    elseif elapsed < cfg.PING_DURATION then
        local t = (elapsed - cfg.ANIM_SHRINK_START) / cfg.ANIM_SHRINK_DUR
        t = t * t
        return math.max(0.01, 1.0 - t)

    else
        return 0
    end
end

-- ---------------------------------------------------------------------------
-- Spawn
-- ---------------------------------------------------------------------------

function M.spawn(posVec, pingType, isRemote)
    if not posVec then
        log.log("spawnPingVisual: no position")
        return false
    end

    if #M.activePings >= cfg.MAX_ACTIVE_PINGS then
        local oldest = M.activePings[1]
        pcall(function()
            if oldest.actor and oldest.actor:IsValid() then
                oldest.actor:K2_DestroyActor()
            end
        end)
        table.remove(M.activePings, 1)
    end

    assets.ensureLoaded()
    pingType = pingType or cfg.PING_TYPES[1]
    log.log("Spawn ping: " .. pingType.name .. (isRemote and " (remote)" or ""))

    if not assets.cachedBPClass then
        log.log("ERROR: BP_PingMarker not loaded")
        return false
    end

    local world = utils.getWorld()
    if not world then
        log.log("ERROR: no World")
        return false
    end

    local spawnOk, actor = log.try("SpawnActor (" .. pingType.name .. ")", function()
        return world:SpawnActor(assets.cachedBPClass, {}, {})
    end)
    if not spawnOk or not actor or not actor:IsValid() then return false end

    pcall(function()
        actor:K2_SetActorLocation(
            utils.makeVec(posVec.X, posVec.Y, posVec.Z + 10), false, {}, false
        )
    end)

    pcall(function()
        local meshComp = actor.PingMesh
        if not meshComp or not meshComp:IsValid() then return end
        local mat = assets.ensureMaterialValid(pingType.key) or assets.ensureMaterialValid("GENERIC")
        if mat then
            meshComp:SetMaterial(0, mat)
        end
    end)

    pcall(function() actor:SetLifeSpan(cfg.PING_DURATION + 1.0) end)

    local sfx = assets.pingSounds[pingType.key]
    local now = os.clock()
    if sfx and assets.cachedGPS and (now - M.lastSfxTime) >= cfg.SFX_COOLDOWN then
        M.lastSfxTime = now
        local sfxWorld = utils.getWorld()
        local sfxOk, sfxErr = pcall(function()
            assets.cachedGPS:PlaySound2D(sfxWorld, sfx, 1.0, 1.0, 0.0, nil, nil, true)
        end)
        if sfxOk then
            log.log("  SFX played: " .. pingType.key)
        else
            log.log("  SFX PlaySound2D failed: " .. tostring(sfxErr))
            local sfxOk2, sfxErr2 = pcall(function()
                assets.cachedGPS:PlaySoundAtLocation(sfxWorld, sfx, posVec, utils.makeRot(0,0,0), 1.0, 1.0, 0.0, nil, nil, nil)
            end)
            if sfxOk2 then
                log.log("  SFX fallback PlaySoundAtLocation OK")
            else
                log.log("  SFX PlaySoundAtLocation failed: " .. tostring(sfxErr2))
            end
        end
    end

    table.insert(M.activePings, {
        actor = actor,
        x = posVec.X, y = posVec.Y, z = posVec.Z,
        pingType = pingType,
        spawnTime = os.clock(),
    })
    log.log("  Ping tracked, activePings=" .. #M.activePings)

    if not isRemote and M.onPingFired then
        pcall(function() M.onPingFired(pingType, posVec) end)
    end

    return true
end

-- ---------------------------------------------------------------------------
-- Per-tick animation update
-- ---------------------------------------------------------------------------

function M.animate()
    local now = os.clock()
    local i = 1
    while i <= #M.activePings do
        local ping = M.activePings[i]
        local elapsed = now - ping.spawnTime

        if elapsed >= cfg.PING_DURATION then
            pcall(function()
                if ping.actor and ping.actor:IsValid() then
                    ping.actor:K2_DestroyActor()
                end
            end)
            table.remove(M.activePings, i)
        else
            local s = M.computeScale(elapsed)
            pcall(function()
                if ping.actor and ping.actor:IsValid() then
                    ping.actor:SetActorScale3D(utils.makeVec(s, s, 1))
                end
            end)
            i = i + 1
        end
    end
end

-- ---------------------------------------------------------------------------
-- Convenience: fire at current cursor
-- ---------------------------------------------------------------------------

function M.fireAtCursor(pingType)
    local pt = pingType or cfg.PING_TYPES[1]
    local pos = getCursorWorldPos()
    if not pos then
        pos = getPawnPosition()
    end
    if not pos then
        log.log("Cannot fire ping: no position")
        return
    end
    M.spawn(pos, pt)
end

return M
