--[[
    OSPlus — Catalog access (shared)
    ================================
    Single source of truth for any OSPlus feature that touches the live
    UI catalog (owned emotes, per-striker equipped reactions, equip writes,
    striker-id extraction). The emote-loadout module is the first consumer;
    future cosmetic-page rework features go through the same helpers.

    The live UIDataModel must be reached via PMUISubsystemBase (NOT
    FindFirstOf("PMUIDataModel"), which returns the CDO with empty
    default-constructed containers). See:
      docs/learnings/ue4ss-3.0.1-tarray-tmap-lua-api.md

    Container conventions used below (UE4SS 3.0.1):
      TArray : arr:GetArrayNum(), arr[1..N] (1-indexed)
      TMap   : #tmap, tmap:ForEach(function(k, v) ... end)
               (k, v are RemoteUnrealParam wrappers; call :get() to unwrap)
--]]

local M = {}
local log = require("log")
local metadata = require("emote_metadata")

local PREFIX = "[Catalog]"

-- Cached live catalog handle. The PMUISubsystemBase singleton is session-
-- stable; once resolved, the chain subsystem.UIDataModel.Catalog stays
-- valid for the session. If a field access ever fails we drop the cache
-- and re-resolve on next call.
local cachedCatalog = nil

local function isValidObj(o)
    if not o then return false end
    local v = false
    pcall(function() v = o:IsValid() end)
    return v
end

-- ============================================================================
-- Live catalog resolution
-- ============================================================================

-- FindFirstOf("PMUIDataModel") returns the CDO — empty containers — and is
-- a known cliff per the tarray-tmap learning. Always go through the
-- subsystem.
local function resolveCatalog()
    if isValidObj(cachedCatalog) then return cachedCatalog end
    cachedCatalog = nil

    local subsystem = nil
    pcall(function() subsystem = FindFirstOf("PMUISubsystemBase") end)
    if not isValidObj(subsystem) then
        return nil, "no-PMUISubsystemBase"
    end

    local model = nil
    pcall(function() model = subsystem.UIDataModel end)
    if not isValidObj(model) then
        return nil, "no-UIDataModel"
    end

    local catalog = nil
    pcall(function() catalog = model.Catalog end)
    if not isValidObj(catalog) then
        return nil, "no-Catalog"
    end

    cachedCatalog = catalog
    return catalog
end

function M.getCatalog()
    local c, reason = resolveCatalog()
    if not c then
        log.log(PREFIX .. " catalog unavailable: " .. tostring(reason))
    end
    return c
end

-- ============================================================================
-- Read helpers
-- ============================================================================

-- Returns the TArray<UPMEmoticonUIData> directly. Callers iterate via
-- :GetArrayNum() + arr[i] (1-indexed) per the tarray-tmap learning.
function M.getOwnedEmoticons()
    local catalog = M.getCatalog()
    if not catalog then return nil end

    local owned = nil
    pcall(function() owned = catalog.OwnedEmoticons end)
    return owned
end

-- Extract the striker identifier ("CD_AngelicSupport" etc.) from a
-- UPMCharacterUIData. Per Prometheus.lua line 10296 — bypasses every
-- FOdyUI*Binding reflection cliff.
--
-- GetIdentifierString returns the full FPrimaryAssetId in "<Type>:<Name>"
-- format (e.g. "CharacterData:CD_NimbleBlaster"). The TMap keys in
-- ReactionsByCharacterId are bare FNames ("CD_NimbleBlaster"), so we strip
-- the type prefix here to give callers a ready-to-match key.
local function stripAssetIdTypePrefix(s)
    if type(s) ~= "string" then return s end
    local colonIdx = s:find(":", 1, true)
    if colonIdx then return s:sub(colonIdx + 1) end
    return s
end

-- Generic entitlement identifier extractor — works for any UPMEntitlementUIData
-- via UPMEntitlementBaseData:GetIdentifierString().
function M.getEntitlementIdentifier(entitlement)
    if not entitlement then return nil end
    local dataAsset = nil
    pcall(function() dataAsset = entitlement.DataAsset end)
    if not dataAsset then return nil end

    local idStr = nil
    pcall(function() idStr = dataAsset:GetIdentifierString() end)
    if idStr == nil then return nil end

    local s = nil
    if type(idStr) == "userdata" then
        pcall(function() s = idStr:ToString() end)
    elseif type(idStr) == "string" then
        s = idStr
    end
    if type(s) ~= "string" or s == "" then return nil end
    return stripAssetIdTypePrefix(s)
end

function M.getCharacterIdentifier(character)
    return M.getEntitlementIdentifier(character)
end

-- ============================================================================
-- Soft pointer resolution
-- ============================================================================
-- TSoftObjectPtr method dispatch via :Method() doesn't work on UE4SS 3.0.1
-- (same wrapper-returns-default cliff as TMap). Resolution goes through
-- UKismetSystemLibrary:Conv_SoftObjectReferenceToObject (non-blocking, returns
-- nil if not yet loaded) with LoadAsset_Blocking as a fallback for the unloaded
-- case. Both validated in production via Engine.lua line 21889 / 21294.
local cachedKismet = nil
local function getKismet()
    if isValidObj(cachedKismet) then return cachedKismet end
    cachedKismet = nil
    pcall(function() cachedKismet = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end)
    return cachedKismet
end

-- The Kismet-Conv'd UObject wrapper is opaque on UE4SS 3.0.1 — `:GetFullName()`
-- returns nil and BP refuses to render the texture (silent failure: white fill).
-- Resolution goes through the path string instead: extract the asset path via
-- Conv_SoftObjectReferenceToString, then load via UE4SS's native LoadAsset /
-- StaticFindObject which produces a properly-wrapped Lua UObject.
local function tryResolveByPath(pathStr)
    -- UE4SS global LoadAsset — synchronous, force-loads if not in memory.
    local resolved = nil
    pcall(function() resolved = LoadAsset(pathStr) end)
    if isValidObj(resolved) then return resolved end

    -- StaticFindObject with the path as-is.
    pcall(function() resolved = StaticFindObject(pathStr) end)
    if isValidObj(resolved) then return resolved end

    -- The path Kismet hands us is "/Game/.../Name" without the ".Name" suffix
    -- StaticFindObject's strict form needs. Re-try with the dotted form.
    local lastSlash = pathStr:find("/[^/]*$")
    if lastSlash then
        local leaf = pathStr:sub(lastSlash + 1)
        local dottedPath = pathStr .. "." .. leaf
        pcall(function() resolved = StaticFindObject(dottedPath) end)
        if isValidObj(resolved) then return resolved end
    end

    return nil
end

function M.resolveSoftPtr(softPtr)
    if not softPtr then return nil end
    local kismet = getKismet()
    if not kismet then return nil end

    local pathStr = nil
    pcall(function() pathStr = kismet:Conv_SoftObjectReferenceToString(softPtr) end)
    if type(pathStr) == "userdata" then
        local s = nil
        pcall(function() s = pathStr:ToString() end)
        pathStr = s
    end
    if type(pathStr) == "string" and pathStr ~= "" then
        local byPath = tryResolveByPath(pathStr)
        if byPath then return byPath end
    end

    -- Fallback: original Kismet path (returns wrapper that may be opaque,
    -- but at least non-nil — last resort if path-based resolution fails).
    local conv = nil
    pcall(function() conv = kismet:Conv_SoftObjectReferenceToObject(softPtr) end)
    if conv then return conv end

    local loaded = nil
    pcall(function() loaded = kismet:LoadAsset_Blocking(softPtr) end)
    return loaded
end

-- ============================================================================
-- Display extraction
-- ============================================================================
-- Lua extracts display primitives from entitlement UObjects and packages them
-- as Lua tables BP can consume via TArray<FOSPlusEmoteDisplay> marshaling.
-- This sidesteps all FOdyUI*Binding cliffs — display fields read directly off
-- DataAsset (UPMEntitlementBaseData) which exposes plain FText / TSoftObjectPtr.

local function readFTextField(dataAsset, fieldName)
    local fText = nil
    pcall(function() fText = dataAsset[fieldName] end)
    if not fText then return "" end
    local s = ""
    pcall(function() s = fText:ToString() end)
    return s or ""
end

-- The icon field is passed to BP as a plain FString asset path. BP reconstructs
-- a soft object ref via Make Soft Object Path + Conv_SoftObjPathToSoftObjRef and
-- then Load Asset Blocking. Reason: TSoftObjectPtr<T> doesn't marshal reliably
-- through UE4SS 3.0.1 from Lua to a BP UFunction parameter — the BP-side soft
-- ref arrives empty so Load Asset Blocking returns nil. Strings marshal fine.
--
-- Conv_SoftObjectReferenceToString returns paths in package-only form like
-- `/Game/Path/Name`. UE's FSoftObjectPath::SetPath without the dotted asset-name
-- suffix parses that with AssetName=None — LoadAssetBlocking then returns nil
-- and BP's cast to Texture2D fails. Append the dotted form (`/Game/Path/Name.Name`)
-- so BP's parser identifies the actual asset within the package.
local function softPtrToPathString(softPtr)
    if not softPtr then return "" end
    local kismet = getKismet()
    if not kismet then return "" end
    local raw = nil
    pcall(function() raw = kismet:Conv_SoftObjectReferenceToString(softPtr) end)
    if type(raw) == "userdata" then
        local s = nil
        pcall(function() s = raw:ToString() end)
        raw = s
    end
    if type(raw) ~= "string" or raw == "" or raw == "None" then return "" end

    -- If the path doesn't already have a `.` after the last `/`, append the
    -- leaf as the asset-name suffix.
    local lastSlash = raw:find("/[^/]*$")
    if lastSlash then
        local leafAndDot = raw:sub(lastSlash + 1)
        if not leafAndDot:find(".", 1, true) then
            raw = raw .. "." .. leafAndDot
        end
    end
    return raw
end

-- Display table for a UPMCharacterUIData. Used for the striker header.
--
-- Icon source: `CharacterIcon` (CloseUp/face art) — the cropped portrait the
-- native character-select tiles use. `CharacterPortrait` is the full Timeline
-- splash art (too large/wide for header use). Both are TSoftObjectPtr<UTexture2D>
-- on UPMCharacterData (Prometheus.lua lines 9013/9016).
function M.getCharacterDisplay(character)
    if not character then return nil end
    local dataAsset = nil
    pcall(function() dataAsset = character.DataAsset end)
    if not dataAsset then return nil end

    local id = M.getEntitlementIdentifier(character)
    local name = readFTextField(dataAsset, "InGameName")
    local iconSoftPtr = nil
    pcall(function() iconSoftPtr = dataAsset.CharacterIcon end)
    local iconPath = softPtrToPathString(iconSoftPtr)

    return { id = id, name = name, icon = iconPath }
end

-- Display table for a single UPMEmoticonUIData. Same FString-path pattern as
-- getCharacterDisplay. Static thumbnails use `Image`; animated emotes expose
-- `AnimatedTexture` on PMEmoticonData. Metadata from data/emotes/catalog.json
-- can override the visual path and enrich description/tags/source.
function M.getEmoteDisplay(emote)
    if not emote then return nil end
    local dataAsset = nil
    pcall(function() dataAsset = emote.DataAsset end)
    if not dataAsset then return nil end

    local id = M.getEntitlementIdentifier(emote)
    local name = readFTextField(dataAsset, "InGameName")
    local iconSoftPtr = nil
    pcall(function() iconSoftPtr = dataAsset.Image end)
    local iconPath = softPtrToPathString(iconSoftPtr)

    local animatedSoftPtr = nil
    pcall(function() animatedSoftPtr = dataAsset.AnimatedTexture end)
    local animatedPath = softPtrToPathString(animatedSoftPtr)

    local visualPath = iconPath
    local visualKind = "static"
    if animatedPath ~= "" then
        visualPath = animatedPath
        visualKind = "animated"
    end

    return metadata.mergeNative({
        id = id,
        name = name,
        icon = iconPath,
        animated_texture = animatedPath,
        visual_asset_path = visualPath,
        visual_kind = visualKind,
    })
end

-- Build a Lua array of emote display tables from a TArray<UPMEmoticonUIData>.
-- The returned shape uses PascalCase keys (Id / Name / Icon) so it marshals
-- directly to a BP struct with matching field names. Also returns a parallel
-- byId map (string id -> emote UObject) so the equip-event handler can
-- resolve back from the BP-fired FName id to the UObject without re-iterating
-- the catalog every time.
local function emoteDisplaysFromArray(tarr)
    if not tarr then return {}, {} end
    local n = 0
    pcall(function() n = tarr:GetArrayNum() end)
    local displays = {}
    local byId = {}
    for i = 1, n do
        local emote = tarr[i]
        if emote then
            local d = M.getEmoteDisplay(emote)
            if d then
                displays[#displays + 1] = {
                    Id = d.id or "",
                    Name = d.name or "",
                    Icon = d.icon or "",
                    Description = d.description or "",
                    Tags = d.tags or {},
                    TagsPacked = d.tags_packed or "[]",
                    TagsDisplay = d.tags_display or "",
                    SearchText = d.search_text or "",
                    Source = d.source or "native",
                    VisualAssetPath = d.visual_asset_path or d.icon or "",
                }
                if d.id then byId[d.id] = emote end
            end
        end
    end
    return displays, byId
end

-- Returns (displays, byId). Caller pushes `displays` to BP and caches `byId`
-- to resolve emote-id strings back to UObjects on equip events.
function M.getOwnedEmoteDisplays()
    return emoteDisplaysFromArray(M.getOwnedEmoticons())
end

function M.getEmoteFilterChips(displays)
    return metadata.buildFilterChips(displays)
end

-- Returns just the displays array. The equipped emote set is a subset of
-- owned, so byId from getOwnedEmoteDisplays already covers any equip-target
-- resolution.
function M.getEquippedEmoteDisplays(reactions)
    if not reactions then return {} end
    local arr = nil
    pcall(function() arr = reactions.Emoticons end)
    local displays = emoteDisplaysFromArray(arr)
    return displays
end

-- Parallel-arrays decompositions. UE4SS 3.0.1 marshals TArray<FStruct> from
-- Lua → BP by replacing Lua table elements with LocalUnrealParam userdata
-- post-call AND leaving the BP-side struct fields empty (verified via probe:
-- the Lua tables we send have populated Id/Name/Icon, but BP-side iteration
-- gets blank values). Workaround: send three parallel primitive arrays
-- (TArray<FName>, TArray<FString>, TArray<FString>). BP zips them per index.

local function decomposeDisplays(displays)
    local ids, names, icons = {}, {}, {}
    for i, d in ipairs(displays) do
        ids[i] = d.Id or ""
        names[i] = d.Name or ""
        icons[i] = d.Icon or ""
    end
    return ids, names, icons
end

function M.getEquippedDisplaysParallel(reactions)
    return decomposeDisplays(M.getEquippedEmoteDisplays(reactions))
end

-- Returns (ids, names, icons, byId). byId is the same id→UObject map
-- getOwnedEmoteDisplays returns — caller caches for equip-event resolution.
function M.getOwnedDisplaysParallel()
    local displays, byId = M.getOwnedEmoteDisplays()
    local ids, names, icons = decomposeDisplays(displays)
    return ids, names, icons, byId
end

-- Look up the UPMReactionsUIData for a given UPMCharacterUIData by
-- matching the character's identifier string against the FName keys in
-- ReactionsByCharacterId (TMap<FName, UPMReactionsUIData>).
--
-- TMap ForEach yields RemoteUnrealParam wrappers — :get() before any
-- field access or comparison (one-iteration trap, see learning doc).
function M.getReactionsForCharacter(character)
    local idStr = M.getCharacterIdentifier(character)
    if not idStr then return nil end

    local catalog = M.getCatalog()
    if not catalog then return nil end

    local tmap = nil
    pcall(function() tmap = catalog.ReactionsByCharacterId end)
    if not tmap then return nil end

    local found = nil
    pcall(function()
        tmap:ForEach(function(k, v)
            if found then return end
            local realK = k:get()
            if not realK then return end
            local keyStr = nil
            pcall(function() keyStr = realK:ToString() end)
            if keyStr == idStr then
                found = v:get()
            end
        end)
    end)
    return found
end

-- ============================================================================
-- Write helpers
-- ============================================================================

-- Canonical equip path per Prometheus.lua line 9002.
-- catalog:EquipEmoticonToSlot(Emote, Character, SlotIndex) -> bool
-- Returns the boolean result, or false on call failure.
function M.equipEmoticonToSlot(emote, character, slotIndex)
    if not emote or not character or not slotIndex then
        log.log(PREFIX .. " equipEmoticonToSlot: missing arg (emote/character/slot)")
        return false
    end

    local catalog = M.getCatalog()
    if not catalog then return false end

    local result = false
    local ok, err = pcall(function()
        result = catalog:EquipEmoticonToSlot(emote, character, slotIndex)
    end)
    if not ok then
        log.log(string.format("%s EquipEmoticonToSlot FAILED: %s", PREFIX, tostring(err)))
        return false
    end
    return result and true or false
end

return M
