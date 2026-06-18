--[[
    OSPlus — Emote Loadout (feature: native-emote tab rework, v1)
    ==============================================================
    Production override module for the customize-page Emote sub-tab.

    When the user clicks the Emote sub-tab on the customize page, this module
    redirects display from the native WBP_Panel_StrikerEmoticons panel to our
    cooked WBP_OSPlusEmoteLoadout widget. Native Skins and Goal Explosion
    sub-tabs are untouched.

    Mechanism: RegisterCustomEvent on the pure-BP SetActivePanel function;
    when fired with the native Emoticons panel as target, construct (or reuse)
    an OSPlus widget instance as a child of CosmeticsPanelSwitcher and
    recursively call SetActivePanel with the OSPlus instance. Recursion guard
    prevents infinite re-entry on the inner call.

    Data path (Path 2 — locked 2026-05-17):
      Lua extracts display primitives (FString name, UTexture2D icon, FName id)
      from entitlement DataAssets via catalog.lua helpers and pushes them into
      the cooked widget. BP renders the primitives directly — no FOdyUI*Binding
      reflection on the BP side, no Prometheus/OdyUI module dependency in the
      dev project. The cooked widget exposes a FOSPlusEmoteDisplay BP struct
      with { Id: Name, Name: String, Icon: Texture2D } fields; Lua marshals
      Lua array-tables of Lua tables into TArray<FOSPlusEmoteDisplay> params.

    References:
      docs/features/emote-loadout-ui-improvement.md (Design section)
      docs/learnings/customize-page-tab-routing-architecture.md
      docs/learnings/ue4ss-registerhook-vs-registercustomevent.md
      docs/learnings/ue4ss-3.0.1-tarray-tmap-lua-api.md
      docs/decisions/0004-emote-loadout-as-osplus-layer.md (revised 2026-05-16)
--]]

local M = {}
local log = require("log")
local catalog = require("catalog")
local i18n = require("localization")

local PREFIX = "[EmoteLoadout]"

-- Cooked widget class short name. Used to filter the OSPlus_OnEmoteEquipRequested
-- RegisterCustomEvent callback so it only fires for our widget (the event is
-- pure-BP and RegisterCustomEvent matches by short name globally).
local OSPLUS_WIDGET_CLASS_SHORT = "WBP_OSPlusEmoteLoadout_C"
-- ============================================================================
-- Asset constants
-- ============================================================================

-- Cooked OSPlus widget shipped via OSPlus.pak (LogicMods, BPModLoaderMod).
-- Class path matches what ue-assets/package_logicmod.ps1 mounts at.
local OSPLUS_WIDGET_CLASS_PATH = "/Game/Mods/OSPlus/UI/WBP_OSPlusEmoteLoadout.WBP_OSPlusEmoteLoadout_C"

-- The native parent class whose SetActivePanel we hook. SetActivePanel exists
-- on multiple classes in the routing chain (WBP_Menu_Striker_C also has one
-- for the Affinity/Overview/Cosmetics top-level tabs); the class filter is
-- mandatory because RegisterCustomEvent matches by short name globally.
local PARENT_PANEL_CLASS = "WBP_Panel_StrikerCosmetics_C"

-- The native sub-panel we replace in display. Only this target class triggers
-- the redirect; Skins and Goal Explosion fire SetActivePanel too but pass a
-- different class as arg[2], so the redirect is filtered by panel target.
local NATIVE_EMOTICONS_CLASS = "WBP_Panel_StrikerEmoticons_C"

-- ============================================================================
-- State
-- ============================================================================

-- Constructed OSPlus widget instances, cached per-parent-panel-instance.
local osplusInstancesByParent = {}

-- Cached UClass for our cooked widget. Resolved once on first need.
local cachedOSPlusClass = nil

-- Recursion guard for the SetActivePanel redirect — the inner recursive call
-- must not re-fire this hook.
local inRedirect = false

-- Per-widget character UObject. Cached at push time keyed by widget full name
-- so the equip-request callback can pass the right character into
-- catalog.equipEmoticonToSlot.
local widgetCharacterByKey = {}

-- Per-widget map of emote id (string) -> UPMEmoticonUIData UObject. Built at
-- pushOwnedEmotesOnce time. The equip-request callback receives the FName id
-- from BP and resolves it through this map (BP doesn't have the UObject —
-- it only has the primitive display data we pushed).
local widgetEmoteByIdByKey = {}

-- Per-widget "owned emotes pushed" flag. The owned list is static within a
-- session — push once per widget instance, not on every sub-tab navigation.
-- Cleared with the instance cache on rebuild.
local widgetOwnedPushedByKey = {}

-- Per-widget selected emote id, tracked so refresh-after-equip can preserve
-- the footer inspection state instead of reverting to the localized empty copy.
local widgetSelectedEmoteIdByKey = {}

local localizedTextFunctionMissingLogged = false

local pushSelectedEmoteDetails

-- ============================================================================
-- Widget discovery / construction
-- ============================================================================

local function isValidObj(o)
    if not o then return false end
    local v = false
    pcall(function() v = o:IsValid() end)
    return v
end

-- ModActor references WBP_OSPlusEmoteLoadout as a hard class reference, so
-- UE's loader loads it transitively when ModActor's CDO loads at level load
-- (BPModLoaderMod → SpawnActor on map load). The class is memory-resident
-- by the time any user interaction triggers our hook — StaticFindObject
-- resolves on first call, no LoadAsset / dynamic-load API gymnastics.
local function getOSPlusWidgetClass()
    if isValidObj(cachedOSPlusClass) then return cachedOSPlusClass end
    cachedOSPlusClass = nil

    local cls = nil
    pcall(function() cls = StaticFindObject(OSPLUS_WIDGET_CLASS_PATH) end)
    if isValidObj(cls) then
        cachedOSPlusClass = cls
        return cls
    end

    log.log(PREFIX .. " widget class not found at " .. OSPLUS_WIDGET_CLASS_PATH ..
        " — confirm ModActor holds a hard class reference to it (otherwise the loader won't pull it in)")
    return nil
end

-- Find the live CosmeticsPanelSwitcher via FindAllOf. WidgetTree:GetRootWidget()
-- returned nil from inside the SetActivePanel hook callback (UE4SS / live-tree
-- access flakiness). Prefer a switcher whose full name path starts with
-- "/Engine/Transient" (live instance) over the CDO template path.
local function findSwitcher(parentPanel)
    local switchers = nil
    pcall(function() switchers = FindAllOf("WidgetSwitcher") end)
    if not switchers then return nil end

    local count = 0
    pcall(function() count = #switchers end)
    if count == 0 then return nil end

    local fallback = nil
    for i = 1, count do
        local s = switchers[i]
        if s then
            local fn = nil
            pcall(function() fn = s:GetFullName() end)
            if fn then
                local leaf = fn:match("([^%.:]+)$")
                if leaf == "CosmeticsPanelSwitcher" then
                    local valid = false
                    pcall(function() valid = s:IsValid() end)
                    if valid then
                        if fn:find("/Engine/Transient", 1, true) then
                            return s
                        end
                        if not fallback then fallback = s end
                    end
                end
            end
        end
    end
    return fallback
end

local function getOrConstructInstance(parentPanel)
    local key = nil
    pcall(function() key = parentPanel:GetFullName() end)
    if not key then return nil end

    local cached = osplusInstancesByParent[key]
    if cached then
        local valid = false
        pcall(function() valid = cached:IsValid() end)
        if valid then return cached end
        osplusInstancesByParent[key] = nil
    end

    local cls = getOSPlusWidgetClass()
    if not cls then
        log.log(PREFIX .. " widget class not loaded: " .. OSPLUS_WIDGET_CLASS_PATH)
        return nil
    end

    local switcher = findSwitcher(parentPanel)
    if not switcher then
        log.log(PREFIX .. " CosmeticsPanelSwitcher not found in parent")
        return nil
    end

    local owningPlayer = nil
    pcall(function() owningPlayer = parentPanel:GetOwningPlayer() end)
    if not owningPlayer then
        log.log(PREFIX .. " no owning player on parent panel")
        return nil
    end

    local wbLib = nil
    pcall(function() wbLib = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary") end)
    if not wbLib then
        log.log(PREFIX .. " WidgetBlueprintLibrary CDO not found")
        return nil
    end

    local instance = nil
    local ok, err = pcall(function() instance = wbLib:Create(owningPlayer, cls, nil) end)
    if not ok or not instance then
        log.log(string.format("%s widget construction FAILED: %s", PREFIX, tostring(err)))
        return nil
    end

    local addOk, addErr = pcall(function() switcher:AddChild(instance) end)
    if not addOk then
        log.log(string.format("%s AddChild to switcher FAILED: %s", PREFIX, tostring(addErr)))
        return nil
    end

    osplusInstancesByParent[key] = instance
    log.log(PREFIX .. " OSPlus widget constructed and added to CosmeticsPanelSwitcher")
    return instance
end

-- ============================================================================
-- Data push
-- ============================================================================

-- v1 widget BP interface (per docs/features/emote-loadout-ui-improvement.md):
--   OSPlus_SetStrikerContext(StrikerName: String, StrikerIcon: Texture2D,
--                            EquippedSlots: TArray<FOSPlusEmoteDisplay>)
--   OSPlus_SetOwnedEmotes(OwnedEmotes: TArray<FOSPlusEmoteDisplay>)
--   OSPlus_OnEmoteEquipRequested(EmoteId: Name, SlotIndex: int32) [widget -> Lua]
-- FOSPlusEmoteDisplay { Id: Name, Name: String, Icon: Texture2D } defined in
-- the dev project. Lua marshals Lua arrays of Lua tables to TArray<struct>.

local function widgetKey(widget)
    local key = nil
    pcall(function() key = widget:GetFullName() end)
    return key
end

local function applyLocalizedText(widget, strikerName)
    if not isValidObj(widget) then return end

    local ownedHeading = ""
    if strikerName and strikerName ~= "" then
        ownedHeading = i18n.text("emote_loadout.owned_heading", "EMOTES", { striker = strikerName })
    else
        ownedHeading = i18n.text("emote_loadout.owned_heading_fallback", "EMOTES")
    end

    local ok, err = pcall(function()
        widget:OSPlus_SetLocalizedText(
            i18n.text("emote_loadout.search_hint", "Search emotes"),
            i18n.text("emote_loadout.equipped_heading", "EQUIPPED EMOTES"),
            ownedHeading,
            i18n.text("emote_loadout.footer.empty_title", "Select an emote"),
            i18n.text("emote_loadout.footer.empty_kind", "EMOTE"),
            i18n.text("emote_loadout.footer.empty_description", "Choose a slot, then pick an owned emote."),
            i18n.text("emote_loadout.equip", "Equip"),
            ""
        )
    end)
    if not ok and not localizedTextFunctionMissingLogged then
        localizedTextFunctionMissingLogged = true
        log.log(string.format("%s static text localization skipped: %s", PREFIX, tostring(err)))
    end
end

local function addEquippedSlot(widget, slotIndex, d)
    widget:OSPlus_AddEquippedSlot(
        slotIndex,
        FName(d.Id or ""),
        d.Name or "",
        d.Icon or "",
        d.Description or "",
        d.TagsPacked or "[]",
        d.SearchText or "",
        d.Source or "native",
        d.VisualAssetPath or d.Icon or ""
    )
end

local function addOwnedEmote(widget, d)
    widget:OSPlus_AddOwnedEmote(
        FName(d.Id or ""),
        d.Name or "",
        d.Icon or "",
        d.Description or "",
        d.TagsPacked or "[]",
        d.SearchText or "",
        d.Source or "native",
        d.VisualAssetPath or d.Icon or ""
    )
end

local function pushFilterChips(widget, displays)
    local chips = catalog.getEmoteFilterChips(displays)
    log.log(string.format("%s pushing filter chips (%d)", PREFIX, #chips))
    widget:OSPlus_BeginFilterChips()
    local chipLabels = {}
    for _, chip in ipairs(chips) do
        chipLabels[#chipLabels + 1] = chip.Label or ""
        widget:OSPlus_AddFilterChip(chip.Key or "", chip.Label or "")
    end
    log.log(string.format("%s filter chip labels: %s", PREFIX, table.concat(chipLabels, ", ")))
    local ok, count = pcall(function()
        local row = widget.OSPlusTagFilterRow
        if row and row.GetChildrenCount then
            return row:GetChildrenCount()
        end
        return -1
    end)
    if ok then
        log.log(string.format("%s filter chip row child count after push: %s", PREFIX, tostring(count)))
    else
        log.log(string.format("%s filter chip row child count probe failed: %s", PREFIX, tostring(count)))
    end
end

local iconClassLogged = false
local equippedDiagLogged = false
local function pushStrikerContext(widget, character, reactions)
    if not character then
        log.log(PREFIX .. " pushStrikerContext skipped: missing character")
        return false
    end

    local charDisplay = catalog.getCharacterDisplay(character)
    if not charDisplay then
        log.log(PREFIX .. " pushStrikerContext: getCharacterDisplay returned nil")
        return false
    end

    -- One-shot: log the icon path string we're about to push to BP, so we
    -- can verify the asset path is what we expect.
    if not iconClassLogged and charDisplay.icon then
        iconClassLogged = true
        log.log(string.format("%s icon path = %s", PREFIX, tostring(charDisplay.icon)))
    end

    -- Drip-feed API: scalar-only BP calls because UE4SS 3.0.1 doesn't marshal
    -- Lua tables to TArray in-params (per issue #378 + sub-agent research —
    -- both TArray<FStruct> and TArray<primitive> silently arrive empty
    -- BP-side). One header call + per-element calls; BP owns the resulting
    -- container of tile widgets.
    --
    -- FName params: UE4SS 3.0.1 does NOT auto-coerce Lua strings to FName for
    -- BP UFunction inputs (it does for FString). Passing a raw Lua string into
    -- a NameProperty slot writes 12 bytes of garbage and corrupts alignment
    -- for the next param → silent process termination, no pcall-catchable
    -- error. EmoteId in AddEquippedSlot/AddOwnedEmote is NameProperty, so we
    -- MUST wrap with FName(...). See docs/learnings/ue4ss-3.0.1-fname-param.md.
    local headerOk, headerErr = pcall(function()
        widget:OSPlus_SetStrikerHeader(charDisplay.name or "", charDisplay.icon or "")
    end)
    if not headerOk then
        log.log(string.format("%s OSPlus_SetStrikerHeader FAILED: %s", PREFIX, tostring(headerErr)))
        return false
    end
    applyLocalizedText(widget, charDisplay.name or "")

    -- Clear + repopulate the equipped row.
    pcall(function() widget:OSPlus_BeginEquippedRow() end)

    local equippedDisplays = catalog.getEquippedEmoteDisplays(reactions)
    local equippedPushed = 0
    for i, d in ipairs(equippedDisplays) do
        addEquippedSlot(widget, i, d)
        equippedPushed = equippedPushed + 1
    end

    local key = widgetKey(widget)
    local selectedEmoteId = key and widgetSelectedEmoteIdByKey[key] or nil
    if key then
        local previousCharacter = widgetCharacterByKey[key]
        if previousCharacter and previousCharacter ~= character then
            selectedEmoteId = nil
            widgetSelectedEmoteIdByKey[key] = nil
        end
        widgetCharacterByKey[key] = character
    end
    log.log(string.format("%s striker context pushed (name=%q, equipped=%d/%d)",
        PREFIX, charDisplay.name or "", equippedPushed, #equippedDisplays))

    if selectedEmoteId and pushSelectedEmoteDetails then
        pushSelectedEmoteDetails(widget, selectedEmoteId)
    end

    return true
end

local function pushOwnedEmotesOnce(widget)
    local key = widgetKey(widget)
    if not key then return end
    if widgetOwnedPushedByKey[key] then return end

    -- Drip-feed: scalar-only per-element BP calls (same TArray-marshaling
    -- cliff as pushStrikerContext). One Begin call to clear the grid, then
    -- one Add call per emote. BP owns the resulting tile container.
    -- EmoteId is FName; see FName(...) note in pushStrikerContext.
    local displays, byId = catalog.getOwnedEmoteDisplays()
    if #displays == 0 then
        log.log(PREFIX .. " pushOwnedEmotesOnce: no owned emotes")
        return
    end

    pushFilterChips(widget, displays)
    widget:OSPlus_BeginOwnedGrid()

    local pushed = 0
    for _, d in ipairs(displays) do
        addOwnedEmote(widget, d)
        pushed = pushed + 1
    end

    widgetOwnedPushedByKey[key] = true
    widgetEmoteByIdByKey[key] = byId
    log.log(string.format("%s OSPlus_AddOwnedEmote drip-feed complete (%d/%d)",
        PREFIX, pushed, #displays))
end

local function refreshOwnedEmotes(widget)
    local key = widgetKey(widget)
    if not key then return end

    widgetOwnedPushedByKey[key] = nil
    pushOwnedEmotesOnce(widget)

    -- Locale changes rebuild display records so names/search/tag labels update.
    -- Re-apply the BP-owned filter/search pass so the refreshed widgets respect
    -- the current UI state instead of briefly showing all.
    pcall(function() widget:RefreshOwnedFilter() end)
end

local function refreshLocalizedWidgets(locale)
    log.log(string.format("%s refreshing localized widget text (locale=%s)", PREFIX, tostring(locale)))

    for _, widget in pairs(osplusInstancesByParent) do
        if isValidObj(widget) then
            local key = widgetKey(widget)
            local character = key and widgetCharacterByKey[key] or nil
            if isValidObj(character) then
                local reactions = catalog.getReactionsForCharacter(character)
                pushStrikerContext(widget, character, reactions)
            else
                applyLocalizedText(widget, "")
            end

            refreshOwnedEmotes(widget)
        end
    end
end

-- ============================================================================
-- Hook callback: SetActivePanel
-- ============================================================================

local function onSetActivePanelFire(...)
    if inRedirect then return end

    local n = select("#", ...)
    if n < 2 then return end

    local Context = select(1, ...)
    local self_ = nil
    pcall(function() self_ = Context:get() end)
    if not self_ then return end

    local cls = nil
    pcall(function() cls = self_:GetClass():GetFName():ToString() end)
    if cls ~= PARENT_PANEL_CLASS then return end

    local PanelParam = select(2, ...)
    local panel = nil
    pcall(function() panel = PanelParam:get() end)
    if not panel then return end

    local panelCls = nil
    pcall(function() panelCls = panel:GetClass():GetFName():ToString() end)
    if panelCls ~= NATIVE_EMOTICONS_CLASS then return end

    local osplusWidget = getOrConstructInstance(self_)
    if not osplusWidget then
        log.log(PREFIX .. " redirect SKIPPED: could not get OSPlus widget")
        return
    end

    -- Striker switch fires SetActivePanel BEFORE OnUIDataSet, so self_.UIData
    -- here is the PREVIOUS striker's. Pushing context now would flash the old
    -- data into the widget for one frame before OnUIDataSet corrects it. Skip
    -- the context push if we already pushed for this widget — OnUIDataSet owns
    -- subsequent updates. The first-visit case (no cached character yet) still
    -- pushes here so the widget isn't blank on opening.
    local wkey = widgetKey(osplusWidget)
    if wkey and not widgetCharacterByKey[wkey] then
        local character = nil
        pcall(function() character = self_.UIData end)
        local reactions = character and catalog.getReactionsForCharacter(character) or nil
        pushStrikerContext(osplusWidget, character, reactions)
    end
    pushOwnedEmotesOnce(osplusWidget)

    log.log(PREFIX .. " redirecting native Emoticons → OSPlus widget")
    inRedirect = true
    local ok, err = pcall(function() self_:SetActivePanel(osplusWidget) end)
    inRedirect = false
    if not ok then
        log.log(string.format("%s redirect FAILED: %s", PREFIX, tostring(err)))
    end
end

-- ============================================================================
-- Hook callback: OnUIDataSet on parent panel
-- ============================================================================

-- The customize page fires SetActivePanel on a sub-tab BEFORE the parent
-- panel's UIData reflects the newly-selected striker. Our SetActivePanel
-- callback then sees stale character data. Fix: hook OnUIDataSet, the BP-
-- implementable callback UOdyWidget exposes post-update (OdyUI.lua line 779).
-- SetUIData itself is native on OdyWidget so RegisterCustomEvent doesn't
-- catch it (per ue4ss-registerhook-vs-registercustomevent.md); OnUIDataSet
-- is the pure-BP override entry point sub-tabs use, which we CAN catch.
local function onSetUIDataFire(...)
    local n = select("#", ...)
    if n < 2 then return end

    local Context = select(1, ...)
    local self_ = nil
    pcall(function() self_ = Context:get() end)
    if not self_ then return end

    local cls = nil
    pcall(function() cls = self_:GetClass():GetFName():ToString() end)
    if cls ~= PARENT_PANEL_CLASS then return end

    local UIDataParam = select(2, ...)
    local newCharacter = nil
    pcall(function() newCharacter = UIDataParam:get() end)
    if not isValidObj(newCharacter) then return end

    -- Find the cached OSPlus widget for this parent panel (if any). If we
    -- haven't built one yet, no-op — the next SetActivePanel redirect will
    -- construct it with the correct context.
    local parentKey = nil
    pcall(function() parentKey = self_:GetFullName() end)
    if not parentKey then return end

    local widget = osplusInstancesByParent[parentKey]
    if not isValidObj(widget) then return end

    local reactions = catalog.getReactionsForCharacter(newCharacter)
    pushStrikerContext(widget, newCharacter, reactions)
end

-- ============================================================================
-- Hook callback: OSPlus_OnEmoteEquipRequested
-- ============================================================================

-- Pure-BP event the cooked widget fires when the user assigns an emote to a
-- slot. The widget passes the emote's Id (FName from FOSPlusEmoteDisplay.Id);
-- Lua resolves it to the UPMEmoticonUIData via the cached byId map and calls
-- catalog.equipEmoticonToSlot. Refresh-after-equip re-pushes striker context
-- so the equipped row reflects the new state (option (a) from the spec).
local function onEmoteEquipRequestedFire(...)
    local n = select("#", ...)
    if n < 3 then return end

    local Context = select(1, ...)
    local widget = nil
    pcall(function() widget = Context:get() end)
    if not isValidObj(widget) then return end

    -- Filter: only our cooked widget. RegisterCustomEvent matches short names
    -- globally; any other widget defining a function with the same short name
    -- would otherwise fire this callback.
    local cls = nil
    pcall(function() cls = widget:GetClass():GetFName():ToString() end)
    if cls ~= OSPLUS_WIDGET_CLASS_SHORT then return end

    local EmoteIdParam = select(2, ...)
    local SlotParam = select(3, ...)
    local emoteIdRaw, slotIndex
    pcall(function() emoteIdRaw = EmoteIdParam:get() end)
    pcall(function() slotIndex = SlotParam:get() end)

    local emoteIdStr = nil
    if type(emoteIdRaw) == "string" then
        emoteIdStr = emoteIdRaw
    elseif type(emoteIdRaw) == "userdata" then
        pcall(function() emoteIdStr = emoteIdRaw:ToString() end)
    end
    if type(emoteIdStr) ~= "string" or emoteIdStr == "" then
        log.log(PREFIX .. " equip request: missing/invalid emote id (" .. tostring(emoteIdRaw) .. ")")
        return
    end

    if type(slotIndex) ~= "number" then
        log.log(PREFIX .. " equip request: non-numeric slotIndex (" .. type(slotIndex) .. ")")
        return
    end

    local key = widgetKey(widget)
    local character = key and widgetCharacterByKey[key] or nil
    if not isValidObj(character) then
        log.log(PREFIX .. " equip request: no cached character for widget; ignoring")
        return
    end

    local byId = key and widgetEmoteByIdByKey[key] or nil
    local emote = byId and byId[emoteIdStr] or nil
    if not isValidObj(emote) then
        log.log(string.format("%s equip request: id %q not found in owned map",
            PREFIX, emoteIdStr))
        return
    end

    local success = catalog.equipEmoticonToSlot(emote, character, slotIndex)
    if not success then
        log.log(string.format("%s equip FAILED (id=%s, slot=%d)", PREFIX, emoteIdStr, slotIndex))
        return
    end

    -- Refresh equipped row by re-pushing context. The catalog's
    -- ReactionsByCharacterId entry now reflects the new assignment, so a
    -- fresh lookup gives the widget current data without per-slot mutation.
    local reactions = catalog.getReactionsForCharacter(character)
    pushStrikerContext(widget, character, reactions)
end

local selectedDetailsFunctionMissingLogged = false

local function selectedEmoteIdFromParam(param)
    local emoteIdRaw = nil
    pcall(function() emoteIdRaw = param:get() end)

    local emoteIdStr = nil
    if type(emoteIdRaw) == "string" then
        emoteIdStr = emoteIdRaw
    elseif type(emoteIdRaw) == "userdata" then
        pcall(function() emoteIdStr = emoteIdRaw:ToString() end)
    end

    if type(emoteIdStr) ~= "string" or emoteIdStr == "" or emoteIdStr == "None" then
        return nil
    end
    return emoteIdStr
end

local function widgetFromCustomEventContext(Context)
    local widget = nil
    pcall(function() widget = Context:get() end)
    if not isValidObj(widget) then return nil end

    local cls = nil
    pcall(function() cls = widget:GetClass():GetFName():ToString() end)
    if cls ~= OSPLUS_WIDGET_CLASS_SHORT then return nil end

    return widget
end

pushSelectedEmoteDetails = function(widget, emoteIdStr)
    local key = widgetKey(widget)
    local byId = key and widgetEmoteByIdByKey[key] or nil
    local emote = byId and byId[emoteIdStr] or nil
    if not isValidObj(emote) then return end

    local display = catalog.getEmoteDisplay(emote)
    if not display then return end

    local ok, err = pcall(function()
        widget:OSPlus_SetSelectedEmoteDetails(
            display.name or "",
            display.description or "",
            display.tags_display or "",
            display.visual_asset_path or display.icon or ""
        )
    end)
    if not ok and not selectedDetailsFunctionMissingLogged then
        selectedDetailsFunctionMissingLogged = true
        log.log(string.format("%s selected-emote footer update skipped: %s", PREFIX, tostring(err)))
    end
end

local function onEmoteSelectedFire(...)
    local n = select("#", ...)
    if n < 2 then return end

    local widget = widgetFromCustomEventContext(select(1, ...))
    if not widget then return end

    local emoteIdStr = selectedEmoteIdFromParam(select(2, ...))
    if not emoteIdStr then return end

    local key = widgetKey(widget)
    if key then widgetSelectedEmoteIdByKey[key] = emoteIdStr end
    pushSelectedEmoteDetails(widget, emoteIdStr)
end

-- ============================================================================
-- Init
-- ============================================================================

function M.init()
    i18n.onLocaleChanged(refreshLocalizedWidgets)
    i18n.init()

    local ok1, err1 = pcall(RegisterCustomEvent, "SetActivePanel", onSetActivePanelFire)
    if ok1 then
        log.log(PREFIX .. " RegisterCustomEvent installed: SetActivePanel (filter: " .. PARENT_PANEL_CLASS .. ", redirect target: " .. NATIVE_EMOTICONS_CLASS .. ")")
    else
        log.log(string.format("%s SetActivePanel install FAILED: %s", PREFIX, tostring(err1)))
    end

    local ok2, err2 = pcall(RegisterCustomEvent, "OSPlus_OnEmoteEquipRequested", onEmoteEquipRequestedFire)
    if ok2 then
        log.log(PREFIX .. " RegisterCustomEvent installed: OSPlus_OnEmoteEquipRequested (filter: " .. OSPLUS_WIDGET_CLASS_SHORT .. ")")
    else
        log.log(string.format("%s OSPlus_OnEmoteEquipRequested install FAILED: %s", PREFIX, tostring(err2)))
    end

    local ok3, err3 = pcall(RegisterCustomEvent, "OnUIDataSet", onSetUIDataFire)
    if ok3 then
        log.log(PREFIX .. " RegisterCustomEvent installed: OnUIDataSet (filter: " .. PARENT_PANEL_CLASS .. ")")
    else
        log.log(string.format("%s OnUIDataSet install FAILED: %s", PREFIX, tostring(err3)))
    end

    local ok5, err5 = pcall(RegisterCustomEvent, "OSPlus_OnEmoteSelected", onEmoteSelectedFire)
    if ok5 then
        log.log(PREFIX .. " RegisterCustomEvent installed: OSPlus_OnEmoteSelected (footer metadata on first click)")
    else
        log.log(string.format("%s OSPlus_OnEmoteSelected install FAILED: %s", PREFIX, tostring(err5)))
    end

end

return M
