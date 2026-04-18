local UEHelpers = require("UEHelpers")
local cfg    = require("config")
local log    = require("log")
local utils  = require("utils")
local assets = require("assets")
local pings  = require("pings")

local M = {}

M.widget = nil
M.open = false
M.selectedIndex = 1

local centerX, centerY = 960, 540
local selectionLogCount = 0

-- ---------------------------------------------------------------------------
-- Widget creation (tries multiple UE4SS approaches)
-- ---------------------------------------------------------------------------

local function createWidget()
    if not assets.cachedWidgetClass then
        log.log("[WHEEL] No widget class, reloading assets...")
        assets.reset()
        log.try("loadAssets", assets.loadAll)
    end

    local classValid = false
    if assets.cachedWidgetClass then
        local ok, v = pcall(function() return assets.cachedWidgetClass:IsValid() end)
        classValid = ok and v
    end
    if not classValid then
        log.log("[WHEEL] Widget class nil or stale, reloading...")
        assets.reset()
        log.try("loadAssets", assets.loadAll)
        if not assets.cachedWidgetClass then
            log.log("[WHEEL] Still no widget class after reload")
            return false
        end
    end

    local pc = utils.getPlayerController()
    if not pc or not pc:IsValid() then
        log.log("[WHEEL] No PlayerController")
        return false
    end

    -- Method 1: WidgetBlueprintLibrary::Create with all 4 params
    local ok1, w1 = log.try("WBL::Create(PingWheel, 4-param)", function()
        local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
        if not wbl or not wbl:IsValid() then error("WBL CDO not found") end
        return wbl:Create(pc, assets.cachedWidgetClass, pc, FName("PingWheelWidget"))
    end)
    if ok1 and w1 then
        local v, isV = pcall(function() return w1:IsValid() end)
        if v and isV then M.widget = w1 end
    end

    -- Method 2: StaticConstructObject fallback
    if not M.widget then
        local ok2, w2 = log.try("StaticConstructObject(PingWheel)", function()
            return StaticConstructObject(assets.cachedWidgetClass, pc, FName("PingWheelWidget"))
        end)
        if ok2 and w2 then
            local v, isV = pcall(function() return w2:IsValid() end)
            if v and isV then M.widget = w2 end
        end
    end

    -- Method 3: CreateWidget global
    if not M.widget then
        local ok3, w3 = log.try("CreateWidget(PingWheel)", function()
            return CreateWidget(pc, assets.cachedWidgetClass)
        end)
        if ok3 and w3 then
            local v, isV = pcall(function() return w3:IsValid() end)
            if v and isV then M.widget = w3 end
        end
    end

    if not M.widget then
        log.log("[WHEEL] All widget creation methods failed")
        return false
    end

    local addOk = log.try("AddToViewport(PingWheel)", function()
        M.widget:AddToViewport(100)
    end)
    if not addOk then return false end

    log.try("SetVisibility(PingWheel, Collapsed)", function()
        M.widget:SetVisibility(cfg.VIS_COLLAPSED)
    end)

    return true
end

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

local function updateHighlight()
    if not M.widget then return end
    local ok, err = pcall(function()
        M.widget:SetSelection(M.selectedIndex)
    end)
    if not ok then
        log.log("[HIGHLIGHT] SetSelection error: " .. tostring(err))
    end
end

local function positionAtCursor()
    if not M.widget then return end

    local pc = utils.getPlayerController()
    if not pc or not pc:IsValid() then return end

    local cursorPos = pings.getCursorWorldPos()
    if not cursorPos then return end

    local screenPos = utils.makeVec(0, 0, 0)
    local projected = false
    pcall(function()
        projected = pc:ProjectWorldLocationToScreen(cursorPos, screenPos, false)
    end)

    if projected then
        local sx = tonumber(screenPos.X) or 960
        local sy = tonumber(screenPos.Y) or 540
        centerX = sx
        centerY = sy

        pcall(function()
            local kml = UEHelpers.GetKismetMathLibrary()
            M.widget:SetAlignmentInViewport(kml:MakeVector2D(0.5, 0.5))
            M.widget:SetDesiredSizeInViewport(kml:MakeVector2D(500, 500))
            M.widget:SetPositionInViewport(kml:MakeVector2D(sx, sy), true)
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function M.show()
    if not M.widget then
        if not createWidget() then return false end
    end

    local ok, err = pcall(function()
        if M.widget and M.widget:IsValid() then
            positionAtCursor()
            M.widget:SetVisibility(cfg.VIS_SELF_HIT_TEST_INVIS)
            updateHighlight()
        end
    end)
    if not ok then
        log.log("[WHEEL] Show failed: " .. tostring(err))
        return false
    end
    return true
end

function M.hide()
    pcall(function()
        if M.widget and M.widget:IsValid() then
            M.widget:SetVisibility(cfg.VIS_COLLAPSED)
        end
    end)
end

function M.updateSelection(pc)
    local mouseX, mouseY = 0, 0
    local gotMouse = false

    pcall(function()
        local mx = { X = 0.0, Y = 0.0 }
        local result = pc:GetMousePosition(mx.X, mx.Y)
        if result then
            mouseX = mx.X
            mouseY = mx.Y
            gotMouse = true
        end
    end)

    if not gotMouse then
        pcall(function()
            local floatX = 0.0
            local floatY = 0.0
            pc:GetMousePosition(floatX, floatY)
            if floatX ~= 0 or floatY ~= 0 then
                mouseX = floatX
                mouseY = floatY
                gotMouse = true
            end
        end)
    end

    if not gotMouse then
        local cursorPos = pings.getCursorWorldPos()
        if not cursorPos then return end
        local cursorScreen = utils.makeVec(0, 0, 0)
        local okB = pcall(function()
            pc:ProjectWorldLocationToScreen(cursorPos, cursorScreen, false)
        end)
        if okB then
            mouseX = tonumber(cursorScreen.X) or 0
            mouseY = tonumber(cursorScreen.Y) or 0
            gotMouse = (mouseX ~= 0 or mouseY ~= 0)
        end
    end

    if not gotMouse then return end

    local dx = mouseX - centerX
    local dy = mouseY - centerY
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < cfg.WHEEL_DEADZONE then return end

    local screenAngle = math.atan(dy, dx)
    local wedgeArc = cfg.TWO_PI / #cfg.PING_TYPES
    local offset = (screenAngle - cfg.WHEEL_START_ANG + wedgeArc / 2) % cfg.TWO_PI
    local newIndex = math.floor(offset / wedgeArc) % #cfg.PING_TYPES + 1

    if newIndex ~= M.selectedIndex then
        M.selectedIndex = newIndex
        updateHighlight()
        if selectionLogCount < 20 then
            selectionLogCount = selectionLogCount + 1
            log.log(string.format("[WHEEL] Selection: %d (%s)", newIndex, cfg.PING_TYPES[newIndex].name))
        end
    end
end

function M.fireSelected()
    local pt = cfg.PING_TYPES[M.selectedIndex]
    if not pt then return end
    pings.fireAtCursor(pt)
end

function M.reset()
    M.widget = nil
end

return M
