local UEHelpers = require("UEHelpers")
local cfg = require("config")
local log = require("log")

local M = {}

M.spriteMaterials = {}
M.pingSounds = {}
M.cachedBPClass = nil
M.cachedWidgetClass = nil
M.cachedGPS = nil
M.loaded = false

local cachedAssetRegistryHelpers = nil

local function getAssetRegistryHelpers()
    if cachedAssetRegistryHelpers and cachedAssetRegistryHelpers:IsValid() then
        return cachedAssetRegistryHelpers
    end
    cachedAssetRegistryHelpers = StaticFindObject("/Script/AssetRegistry.Default__AssetRegistryHelpers")
    return cachedAssetRegistryHelpers
end

function M.findAsset(assetPath)
    local assetName = assetPath:match("[^/]+$")

    local tryPaths = {
        assetPath .. "." .. assetName,
        "MaterialInstanceConstant " .. assetPath .. "." .. assetName,
        "Texture2D " .. assetPath .. "." .. assetName,
    }
    for _, path in ipairs(tryPaths) do
        local ok, obj = pcall(StaticFindObject, path)
        if ok and obj and type(obj) == "userdata" then
            local validOk, isValid = pcall(function() return obj:IsValid() end)
            if validOk and isValid then return obj end
        end
    end

    local arh = getAssetRegistryHelpers()
    if not arh or not arh:IsValid() then return nil end

    local ok, result = pcall(function()
        local assetData = {
            ["PackageName"] = UEHelpers.FindOrAddFName(assetPath),
            ["AssetName"] = UEHelpers.FindOrAddFName(assetName),
        }
        return arh:GetAsset(assetData)
    end)
    if ok and result then
        local validOk, isValid = pcall(function() return result:IsValid() end)
        if validOk and isValid then return result end
    end
    return nil
end

function M.loadBPClass(packagePath, className)
    local arh = getAssetRegistryHelpers()
    if not arh or not arh:IsValid() then return nil end

    local ok, cls = pcall(function()
        local assetData = {
            ["PackageName"] = UEHelpers.FindOrAddFName(packagePath),
            ["AssetName"] = UEHelpers.FindOrAddFName(className .. "_C"),
        }
        return arh:GetAsset(assetData)
    end)
    if ok and cls then
        local v, isV = pcall(function() return cls:IsValid() end)
        if v and isV then return cls end
    end

    local ok2, bp = pcall(function()
        local assetData = {
            ["PackageName"] = UEHelpers.FindOrAddFName(packagePath),
            ["AssetName"] = UEHelpers.FindOrAddFName(className),
        }
        return arh:GetAsset(assetData)
    end)
    if ok2 and bp then
        local v2, isV2 = pcall(function() return bp:IsValid() end)
        if v2 and isV2 then
            local ok3, gen = pcall(function() return bp.GeneratedClass end)
            if ok3 and gen then
                local v3, isV3 = pcall(function() return gen:IsValid() end)
                if v3 and isV3 then return gen end
            end
        end
    end

    local fallbacks = {
        "BlueprintGeneratedClass " .. packagePath .. "." .. className .. "_C",
        "WidgetBlueprintGeneratedClass " .. packagePath .. "." .. className .. "_C",
        packagePath .. "." .. className .. "_C",
    }
    for _, p in ipairs(fallbacks) do
        local ok4, cls4 = pcall(StaticFindObject, p)
        if ok4 and cls4 then
            local v4, isV4 = pcall(function() return cls4:IsValid() end)
            if v4 and isV4 then return cls4 end
        end
    end

    return nil
end

function M.loadAll()
    log.log("--- Loading ping assets ---")
    local loaded = 0
    for key, path in pairs(cfg.PING_SPRITE_MATS) do
        local mat = M.findAsset(path)
        if mat then
            M.spriteMaterials[key] = mat
            loaded = loaded + 1
            log.log("  MI: " .. key .. " -> " .. log.safeFullName(mat))
        else
            log.log("  MI NOT found: " .. key)
        end
    end
    log.log("Materials: " .. loaded .. "/6")

    log.log("--- BP_PingMarker ---")
    M.cachedBPClass = M.loadBPClass("/Game/CustomPings/VFX/BP_PingMarker", "BP_PingMarker")
    if M.cachedBPClass then
        log.log("  Loaded: " .. log.safeFullName(M.cachedBPClass))
    else
        log.log("  BP_PingMarker NOT found!")
    end

    log.log("--- SFX ---")
    for key, path in pairs(cfg.PING_SFX) do
        local sfx = M.findAsset(path)
        if sfx then
            M.pingSounds[key] = sfx
            log.log("  SFX: " .. key .. " -> " .. log.safeFullName(sfx))
        else
            log.log("  SFX NOT found: " .. key)
        end
    end

    log.log("--- UGameplayStatics ---")
    M.cachedGPS = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    if M.cachedGPS then
        log.log("  Loaded: " .. log.safeFullName(M.cachedGPS))
    else
        log.log("  UGameplayStatics NOT found!")
    end

    log.log("--- WBP_PingWheel ---")
    M.cachedWidgetClass = M.loadBPClass("/Game/CustomPings/UI/WBP_PingWheel", "WBP_PingWheel")
    if M.cachedWidgetClass then
        log.log("  Loaded: " .. log.safeFullName(M.cachedWidgetClass))
    else
        log.log("  WBP_PingWheel NOT found!")
    end

    M.loaded = true
    return loaded
end

function M.ensureLoaded()
    if M.loaded then return end
    log.try("loadAssets", M.loadAll)
end

function M.ensureMaterialValid(key)
    local mat = M.spriteMaterials[key]
    if mat then
        local ok, valid = pcall(function() return mat:IsValid() end)
        if ok and valid then return mat end
    end
    local path = cfg.PING_SPRITE_MATS[key]
    if not path then return nil end
    local newMat = M.findAsset(path)
    if newMat then
        M.spriteMaterials[key] = newMat
        log.log("  Material refreshed: " .. key)
    end
    return newMat
end

function M.reset()
    M.spriteMaterials = {}
    M.pingSounds = {}
    M.cachedBPClass = nil
    M.cachedWidgetClass = nil
    M.cachedGPS = nil
    M.loaded = false
end

return M
