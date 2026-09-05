-- ============================================================
-- Feature: Update availability notification
--
-- BP-owned (UI-reactive state):
--   Card visibility, entrance animation, notification sound, and rendered text.
--   Active release-link click target, button enabled/hover state, and tooltip.
--
-- Lua-owned (domain / operational state):
--   Latest available version, pending notice, versions already shown this
--   session, Home Hub visit state, trigger timing, native-container
--   attachment, cached widget reference, and the visible release fact used
--   when restoring the widget or refreshing its language. Native Settings
--   and loading-cover state gate link input without ending the Home Hub visit.
--
-- Lua -> BP (display / orchestration):
--   :OSPlus_SetLocalizedText(titleString, versionLineString)
--   :OSPlus_SetReleaseLink(releaseUrlString, tooltipString)
--   :OSPlus_ShowUpdateNotice(latestVersion)
--   :OSPlus_PlayUpdateNoticeCue()
--   :OSPlus_HideUpdateNotice()
--
-- BP -> Lua:
--   None. Blueprint opens the validated release URL directly on click.
--
-- State explicitly NOT synchronized:
--   Blueprint animation/visibility state and Lua IPC/match state.
-- ============================================================

local log = require("log")
local i18n = require("localization")

local M = {}

local WIDGET_CLASS = "WBP_OSPlusUpdateNotice_C"
local WIDGET_CLASS_PATH =
    "/Game/Mods/OSPlus/UpdateAvailability/WBP_OSPlusUpdateNotice.WBP_OSPlusUpdateNotice_C"
local HOME_HUB_CLASS = "WBP_HomeHub_PC_C"
local SETTINGS_HUB_CLASS = "WBP_SettingsHub_C"
local LOADING_SCREEN_CLASS = "WBP_LoadingScreen_C"
local WIDGET_NOT_SHOWING = 0
local WIDGET_ANIMATING_IN = 1
local WIDGET_SHOWING = 2
local MATCHMAKING_QUEUED = 2
local HOME_HUB_NOTICE_Z_ORDER = 2
local VIS_HIT_TEST_INVISIBLE = 3
local VIS_SELF_HIT_TEST_INVISIBLE = 4
local RELEASE_TAG_URL_PREFIX = "https://github.com/LuizinhoF/osplus/releases/tag/v"
local MAX_SAFE_VERSION_PART = "9007199254740991"

M.widget = nil
M.homeHub = nil
M.hostContainer = nil
M.widgetAttached = false
M.homeHubActive = false
M.settingsOpen = false
M.latestVersion = nil
M.pendingUpdate = nil
M.notifiedVersions = {}
M.cuedVersions = {}
M.visibleVersion = nil
M.visibleReleaseUrl = nil
M.pendingCueVersion = nil
M.loadingScreenActive = true
M.lastMatchmakingState = nil
M.presentationQueued = false
M.localizationRefreshQueued = false
M.cueRecoveryQueued = false
M.cueRecoveryAttemptedVersions = {}
M.lifecycleGeneration = 0
M.onUpdateCheckRequested = nil

local localizedTextFunctionMissingLogged = false
local releaseLinkFunctionMissingLogged = false

local function validatedReleaseUrl(version, releaseUrl)
    -- Opening an external page is narrower than accepting an informational
    -- release fact: only the exact OSPlus tag for this displayed stable version
    -- is clickable. Do not normalize arbitrary URLs into a trusted destination.
    if type(version) ~= "string" or #version > 64 or
            not version:match("^%d+%.%d+%.%d+$") then
        return ""
    end
    for part in version:gmatch("%d+") do
        if (#part > 1 and part:sub(1, 1) == "0") or
                #part > #MAX_SAFE_VERSION_PART or
                (#part == #MAX_SAFE_VERSION_PART and part > MAX_SAFE_VERSION_PART) then
            return ""
        end
    end
    local expected = RELEASE_TAG_URL_PREFIX .. version
    if releaseUrl ~= expected then return "" end
    return expected
end

local function unwrapHookValue(value)
    if value == nil then return nil end
    local ok, unwrapped = pcall(function() return value:get() end)
    if ok then return unwrapped end
    return value
end

local function safeFullName(object)
    if not object then return nil end
    local ok, fullName = pcall(function() return object:GetFullName() end)
    if not ok or type(fullName) ~= "string" then return nil end
    return fullName
end

local function contextClassName(context)
    local object = unwrapHookValue(context)
    local fullName = safeFullName(object)
    if not fullName then return nil end
    return fullName:match("^(%S+)")
end

local function hookNumber(value)
    local unwrapped = unwrapHookValue(value)
    if type(unwrapped) == "number" then return unwrapped end
    local ok, number = pcall(tonumber, unwrapped)
    if ok then return number end
    return nil
end

local function objectAlive(object)
    if not object then return false end
    local ok, valid = pcall(function() return object:IsValid() end)
    return ok and valid == true
end

local function safeObjectField(object, fieldName)
    if not objectAlive(object) then return nil end
    local ok, value = pcall(function() return object[fieldName] end)
    if not ok then return nil end
    return unwrapHookValue(value)
end

local function sameObject(left, right)
    if not objectAlive(left) or not objectAlive(right) then return false end
    local equalityOk, equal = pcall(function() return left == right end)
    if equalityOk and equal then return true end
    local leftName = safeFullName(left)
    local rightName = safeFullName(right)
    return leftName ~= nil and leftName == rightName
end

local function widgetParent(widget)
    if not objectAlive(widget) then return nil end
    local ok, parent = pcall(function() return widget:GetParent() end)
    if not ok then return nil end
    return unwrapHookValue(parent)
end

local function widgetAlive()
    if objectAlive(M.widget) then return true end
    M.widget = nil
    M.widgetAttached = false
    return false
end

local function ensureWidget()
    if widgetAlive() then return true end

    local ok, widget = pcall(FindFirstOf, WIDGET_CLASS)
    if not ok or not objectAlive(widget) then return false end

    M.widget = widget
    log.log("[UPDATE] Found notification widget: " .. log.safeFullName(widget))
    return true
end

local function requestUpdateCheck(reason)
    if not M.onUpdateCheckRequested then
        log.log("[UPDATE] Check callback is not wired (" .. tostring(reason) .. ")")
        return
    end

    local ok, sent = pcall(M.onUpdateCheckRequested, reason)
    if not ok then
        log.log("[UPDATE] Check request failed (" .. tostring(reason) .. "): " .. tostring(sent))
    elseif sent == false then
        log.log("[UPDATE] Check request could not be written (" .. tostring(reason) .. ")")
    else
        log.log("[UPDATE] Check requested: " .. tostring(reason))
    end
end

local function widgetIsInHost()
    if not widgetAlive() or not objectAlive(M.hostContainer) then
        M.widgetAttached = false
        return false
    end
    M.widgetAttached = sameObject(widgetParent(M.widget), M.hostContainer)
    return M.widgetAttached
end

local function attachWidgetToHomeHub(homeHub, source)
    if contextClassName(homeHub) ~= HOME_HUB_CLASS then return false end

    local host = safeObjectField(homeHub, "UIContainer")
    if not objectAlive(host) or not ensureWidget() then return false end

    M.homeHub = homeHub
    M.hostContainer = host
    if widgetIsInHost() then return true end

    -- PlayPanel is a direct child of this same native UIContainer at z-order 2.
    -- Hosting the notice beside it makes the Home Hub/loading transition cover
    -- and reveal both together. Native group invites and modal overlays use
    -- higher layers, so they remain above the advisory card.
    local attachOk, slotOrError = pcall(function()
        -- The outer UUserWidget remains visible while it is hosted in the
        -- native canvas. Collapse the BP-owned inner root before reparenting so
        -- a persistent widget can never expose stale content for one frame.
        M.widget:OSPlus_HideUpdateNotice()
        M.widget:RemoveFromParent()
        local slot = host:AddChildToCanvas(M.widget)
        if not slot then error("AddChildToCanvas returned nil") end
        slot:SetAnchors({
            Minimum = { X = 0.0, Y = 0.0 },
            Maximum = { X = 1.0, Y = 1.0 },
        })
        slot:SetOffsets({
            Left = 0.0,
            Top = 0.0,
            Right = 0.0,
            Bottom = 0.0,
        })
        slot:SetAlignment({ X = 0.0, Y = 0.0 })
        slot:SetAutoSize(false)
        slot:SetZOrder(HOME_HUB_NOTICE_Z_ORDER)
        -- The full-screen host must ignore pointer hits without preventing the
        -- card's own button from receiving them.
        M.widget:SetVisibility(VIS_SELF_HIT_TEST_INVISIBLE)
        return slot
    end)
    if not attachOk then
        M.widgetAttached = false
        log.log("[UPDATE] Native Home Hub attachment failed (" ..
            tostring(source) .. "): " .. tostring(slotOrError))
        return false
    end

    M.widgetAttached = true
    log.log("[UPDATE] Notification attached to the native Home Hub layer (" ..
        tostring(source) .. ")")
    return true
end

local function prepareHomeHub(homeHub, source)
    return attachWidgetToHomeHub(homeHub, source)
end

local function hideWidget(source)
    if not widgetAlive() then return end
    local ok, err = pcall(function()
        M.widget:OSPlus_HideUpdateNotice()
    end)
    if not ok then
        M.widget = nil
        M.widgetAttached = false
        log.log("[UPDATE] Hide notification failed (" ..
            tostring(source) .. "): " .. tostring(err))
    end
end

local function applyLocalizedText(widget, version)
    if not objectAlive(widget) or type(version) ~= "string" or version == "" then
        return false
    end

    local ok, err = pcall(function()
        widget:OSPlus_SetLocalizedText(
            i18n.text("update_notification.title", "OSPLUS UPDATE"),
            i18n.text(
                "update_notification.version_available",
                "v{version} available",
                { version = version }
            )
        )
    end)
    if not ok and not localizedTextFunctionMissingLogged then
        localizedTextFunctionMissingLogged = true
        log.log("[UPDATE] Localized notice text could not be applied: " .. tostring(err))
    end
    return ok
end

local function applyReleaseLink(widget, version, releaseUrl)
    if not objectAlive(widget) then return false end
    local blockedByNativeOverlay = M.settingsOpen or M.loadingScreenActive
    local url = blockedByNativeOverlay and "" or validatedReleaseUrl(version, releaseUrl)
    local ok, err = pcall(function()
        widget:OSPlus_SetReleaseLink(
            url,
            url ~= "" and i18n.text(
                "update_notification.view_release",
                "View release on GitHub"
            ) or ""
        )
    end)
    -- A mismatched/older cooked widget can still show the advisory, but must
    -- never retain an interactive destination after the setter failed.
    pcall(function()
        widget:SetVisibility(ok and not blockedByNativeOverlay and
            VIS_SELF_HIT_TEST_INVISIBLE or VIS_HIT_TEST_INVISIBLE)
    end)
    if not ok and not releaseLinkFunctionMissingLogged then
        releaseLinkFunctionMissingLogged = true
        log.log("[UPDATE] Release link disabled because it could not be applied: " .. tostring(err))
    end
    return ok
end

local function refreshVisibleReleaseLink()
    if not M.homeHubActive or not M.visibleVersion or not widgetAlive() then return end
    applyReleaseLink(M.widget, M.visibleVersion, M.visibleReleaseUrl)
end

local function setSettingsInputCover(active)
    if M.settingsOpen ~= active then
        M.settingsOpen = active
        -- Settings overlays the still-active Home Hub. Keep its input cover
        -- until the native router reports NotShowing, including its exit
        -- animation, without consuming/replaying the update visit/cue.
        -- See docs/learnings/chat-settings-lifecycle-suppression.md.
        refreshVisibleReleaseLink()
        log.log("[UPDATE] Settings input cover=" .. tostring(active) ..
            " (router display state)")
    end
end

local function restoreVisiblePresentation(source)
    local version = M.visibleVersion
    if not version or not widgetIsInHost() then return false end

    local ok, restoredOrError = pcall(function()
        if not applyLocalizedText(M.widget, version) then return false end
        applyReleaseLink(M.widget, version, M.visibleReleaseUrl)
        M.widget:OSPlus_ShowUpdateNotice(version)
        return true
    end)
    if not ok then
        M.widget = nil
        M.widgetAttached = false
        log.log("[UPDATE] Restore notification failed (" ..
            tostring(source) .. "): " .. tostring(restoredOrError))
        return false
    end
    if restoredOrError ~= true then
        log.log("[UPDATE] Restore deferred until localized text is available (" ..
            tostring(source) .. ")")
        return false
    end

    log.log("[UPDATE] Notification restored for " .. tostring(version) ..
        " (" .. tostring(source) .. ")")
    return true
end

local function tryPlayPendingCue()
    local version = M.pendingCueVersion
    if not version or M.loadingScreenActive or not M.homeHubActive then return end
    if M.visibleVersion ~= version then
        M.pendingCueVersion = nil
        return
    end
    -- A native menu rebuild can briefly detach or replace the widget. Keep the
    -- one-shot cue pending until constructed-widget recovery restores the card.
    if not widgetIsInHost() then return end
    if M.cuedVersions[version] then
        M.pendingCueVersion = nil
        return
    end

    local ok, err = pcall(function()
        M.widget:OSPlus_PlayUpdateNoticeCue()
    end)
    if not ok then
        M.widget = nil
        M.widgetAttached = false
        log.log("[UPDATE] Notification cue failed: " .. tostring(err))

        -- A stale UI wrapper can fail on the final loading-complete edge, when
        -- no further router event is guaranteed. Queue exactly one recovery
        -- turn for this version: reacquire/reparent, restore text and visibility,
        -- then retry the still-pending cue.
        if not M.cueRecoveryQueued and
                not M.cueRecoveryAttemptedVersions[version] then
            M.cueRecoveryQueued = true
            M.cueRecoveryAttemptedVersions[version] = true
            local generation = M.lifecycleGeneration
            local dispatchOk, dispatchErr = pcall(function()
                ExecuteInGameThread(function()
                    M.cueRecoveryQueued = false
                    if generation ~= M.lifecycleGeneration or
                            M.pendingCueVersion ~= version or
                            not M.homeHubActive then
                        return
                    end
                    if objectAlive(M.homeHub) and
                            prepareHomeHub(M.homeHub, "cue recovery") then
                        restoreVisiblePresentation("cue recovery")
                        tryPlayPendingCue()
                    end
                end)
            end)
            if not dispatchOk then
                M.cueRecoveryQueued = false
                M.cueRecoveryAttemptedVersions[version] = nil
                log.log("[UPDATE] Could not enqueue notification-cue recovery: " ..
                    tostring(dispatchErr))
            end
        end
        return
    end

    M.pendingCueVersion = nil
    M.cuedVersions[version] = true
    M.cueRecoveryAttemptedVersions[version] = nil
    log.log("[UPDATE] Notification cue played for " .. tostring(version))
end

local function tryShowPending()
    local pending = M.pendingUpdate
    if not M.homeHubActive or not pending then return end

    if not widgetIsInHost() then
        local attached = false
        if objectAlive(M.homeHub) then
            attached = prepareHomeHub(M.homeHub, "presentation")
        end
        if not attached then return end
    end

    local version = pending.latestVersion
    if M.notifiedVersions[version] then
        M.pendingUpdate = nil
        return
    end

    local ok, shownOrError = pcall(function()
        if not applyLocalizedText(M.widget, version) then return false end
        applyReleaseLink(M.widget, version, pending.releaseUrl)
        M.widget:OSPlus_ShowUpdateNotice(version)
        return true
    end)
    if not ok then
        M.widget = nil
        M.widgetAttached = false
        log.log("[UPDATE] Show notification failed: " .. tostring(shownOrError))
        return
    end
    if shownOrError ~= true then
        -- Do not consume the release fact or expose the authored English
        -- fallback when the cooked localization bridge is unavailable.
        log.log("[UPDATE] Presentation deferred until localized text is available")
        return
    end

    M.notifiedVersions[version] = true
    M.visibleVersion = version
    M.visibleReleaseUrl = pending.releaseUrl
    M.pendingUpdate = nil
    M.pendingCueVersion = version
    log.log("[UPDATE] Notification shown for " .. tostring(version) ..
        " (locale=" .. tostring(i18n.currentLocale()) .. ")")
    tryPlayPendingCue()
end

local function refreshLocalizedText(locale)
    local version = M.visibleVersion
    if not version or not widgetAlive() or M.localizationRefreshQueued then return end

    M.localizationRefreshQueued = true
    local generation = M.lifecycleGeneration
    local dispatchOk, dispatchErr = pcall(function()
        ExecuteInGameThread(function()
            if generation ~= M.lifecycleGeneration then return end
            M.localizationRefreshQueued = false
            if M.visibleVersion ~= version or not widgetAlive() then return end
            if applyLocalizedText(M.widget, version) then
                applyReleaseLink(M.widget, version, M.visibleReleaseUrl)
                log.log("[UPDATE] Localized notice text refreshed (locale=" ..
                    tostring(locale) .. ")")
            end
        end)
    end)
    if not dispatchOk then
        M.localizationRefreshQueued = false
        log.log("[UPDATE] Could not enqueue localized-text refresh: " ..
            tostring(dispatchErr))
    end
end

local function queuePresentationAttempt()
    -- IPC is polled by LoopAsync, so a release fact may arrive off the game
    -- thread. Queue one bounded presentation attempt only after the router
    -- reports the Home Hub in its native Showing state.
    if M.presentationQueued or not M.pendingUpdate or not M.homeHubActive then return end

    M.presentationQueued = true
    local generation = M.lifecycleGeneration
    local dispatchOk, dispatchErr = pcall(function()
        ExecuteInGameThread(function()
            if generation ~= M.lifecycleGeneration then return end
            M.presentationQueued = false
            local showOk, showErr = pcall(tryShowPending)
            if not showOk then
                log.log("[UPDATE] Presentation attempt failed: " .. tostring(showErr))
            end
        end)
    end)
    if not dispatchOk then
        M.presentationQueued = false
        log.log("[UPDATE] Could not enqueue presentation: " .. tostring(dispatchErr))
    end
end

local function hideForHomeHubExit(source)
    local wasActive = M.homeHubActive
    local wasVisible = M.visibleVersion ~= nil
    M.homeHubActive = false
    M.pendingCueVersion = nil

    if wasActive or wasVisible then
        hideWidget(source)
    end

    M.visibleVersion = nil
    M.visibleReleaseUrl = nil
    if wasActive then
        log.log("[UPDATE] Home Hub visit ended (" .. tostring(source) .. ")")
    end
end

local function onLoadingScreenAnimateIn(context)
    if contextClassName(context) ~= LOADING_SCREEN_CLASS then return end
    M.loadingScreenActive = true
    refreshVisibleReleaseLink()
    log.log("[UPDATE] Loading transition began")
end

local function onLoadingScreenAnimateOutComplete(context)
    if contextClassName(context) ~= LOADING_SCREEN_CLASS then return end
    M.loadingScreenActive = false
    refreshVisibleReleaseLink()
    log.log("[UPDATE] Loading transition finished")
    tryPlayPendingCue()
end

local function applyLoadingScreenState(loadingScreen, source)
    if not objectAlive(loadingScreen) then return false end
    local state = hookNumber(safeObjectField(loadingScreen, "DisplayState"))
    if state == nil then return false end
    M.loadingScreenActive = state ~= WIDGET_NOT_SHOWING
    refreshVisibleReleaseLink()
    log.log("[UPDATE] Loading transition state = " .. tostring(state) ..
        " (" .. tostring(source) .. ")")
    tryPlayPendingCue()
    return true
end

local function refreshLoadingScreenState(source)
    local ok, loadingScreen = pcall(FindFirstOf, LOADING_SCREEN_CLASS)
    if ok and applyLoadingScreenState(loadingScreen, source) then return end

    -- Once the native Home Hub is Showing, absence of a loading-screen object
    -- is a concrete proof that no loading layer can cover the cue.
    if M.homeHubActive then
        M.loadingScreenActive = false
        refreshVisibleReleaseLink()
        log.log("[UPDATE] Loading transition is absent (" ..
            tostring(source) .. ")")
        tryPlayPendingCue()
    end
end

local function onLoadingScreenConstructed(context)
    if contextClassName(context) ~= LOADING_SCREEN_CLASS then return end
    local constructed = unwrapHookValue(context)

    -- Construction can race with the first AnimateIn call. Latch immediately,
    -- then read the settled native display state on the game thread.
    M.loadingScreenActive = true
    refreshVisibleReleaseLink()
    local generation = M.lifecycleGeneration
    local dispatchOk, dispatchErr = pcall(function()
        ExecuteInGameThread(function()
            if generation ~= M.lifecycleGeneration then return end
            if not applyLoadingScreenState(
                    constructed,
                    "loading screen constructed"
                ) then
                refreshLoadingScreenState("loading construction recovery")
            end
        end)
    end)
    if not dispatchOk then
        log.log("[UPDATE] Could not enqueue loading-screen state recovery: " ..
            tostring(dispatchErr))
    end
end

local function beginHomeHubShowing(homeHub, source)
    M.homeHub = homeHub
    if not M.homeHubActive then
        M.homeHubActive = true
        log.log("[UPDATE] Home Hub active (" .. tostring(source) .. ")")
    end

    if not prepareHomeHub(homeHub, source) then
        log.log("[UPDATE] Home Hub active but native notice slot is unavailable (" ..
            tostring(source) .. ")")
        return
    end

    -- A widget can survive a map transition as a child of the persistent Home
    -- Hub. Reset deliberately avoids touching old UObjects, so collapse any
    -- stale presentation when the new visit has no pending fact.
    if not M.pendingUpdate and not M.visibleVersion then
        hideWidget("new Home Hub visit without pending update")
    end
    if M.visibleVersion then
        restoreVisiblePresentation(source)
    end

    -- Reparent/restore before releasing a pending cue. Otherwise the attachment
    -- path's defensive Hide call could immediately stop a just-started cue.
    refreshLoadingScreenState(tostring(source) .. " / Home Hub showing")
    tryShowPending()
    tryPlayPendingCue()
end

local function onNoticeWidgetConstructed(widget)
    local constructed = unwrapHookValue(widget)
    if contextClassName(constructed) ~= WIDGET_CLASS then return end

    M.widget = constructed
    M.widgetAttached = false

    -- NotifyOnNewObject fires during object construction. Defer the UI work
    -- until the widget tree and the ModActor's initial AddToViewport call have
    -- completed, then recover the startup case where Home Hub was already
    -- Showing before the notice existed.
    local generation = M.lifecycleGeneration
    local dispatchOk, dispatchErr = pcall(function()
        ExecuteInGameThread(function()
            if generation ~= M.lifecycleGeneration or not M.homeHubActive then return end
            if not objectAlive(M.homeHub) then return end
            if prepareHomeHub(M.homeHub, "notice constructed") then
                restoreVisiblePresentation("notice constructed")
                refreshLoadingScreenState("notice constructed")
                tryShowPending()
                tryPlayPendingCue()
            end
        end)
    end)
    if not dispatchOk then
        log.log("[UPDATE] Could not enqueue constructed-widget recovery: " ..
            tostring(dispatchErr))
    end
end

local function readHomeHubDisplayState(homeHub)
    return hookNumber(safeObjectField(homeHub, "DisplayState"))
end

local function refreshHomeHubState(source)
    local ok, homeHub = pcall(FindFirstOf, HOME_HUB_CLASS)
    if not ok or not objectAlive(homeHub) then return end

    local state = readHomeHubDisplayState(homeHub)
    if state == WIDGET_SHOWING then
        beginHomeHubShowing(homeHub, source)
    elseif state == WIDGET_ANIMATING_IN then
        prepareHomeHub(homeHub, source)
    end
end

local function onHomeHubNavigatedTo(context)
    if contextClassName(context) ~= HOME_HUB_CLASS then return end
    local homeHub = unwrapHookValue(context)
    local state = readHomeHubDisplayState(homeHub)
    if state == WIDGET_SHOWING then
        beginHomeHubShowing(homeHub, "OnNavigatedTo")
    else
        prepareHomeHub(homeHub, "OnNavigatedTo")
    end
end

local function onHomeHubNavigatedAway(context)
    if contextClassName(context) ~= HOME_HUB_CLASS then return end
    hideForHomeHubExit("OnNavigatedAway")
end

local function onHomeHubNavBack(context)
    if contextClassName(context) ~= HOME_HUB_CLASS then return end
    hideForHomeHubExit("OnNavBack")
end

local function onHomeHubCloseSelf(context)
    if contextClassName(context) ~= HOME_HUB_CLASS then return end
    hideForHomeHubExit("CloseSelf")
end

local function onMatchmakingStateChanged(context, oldValue, newValue)
    if contextClassName(context) ~= HOME_HUB_CLASS then return end

    local oldState = hookNumber(oldValue)
    local newState = hookNumber(newValue)
    if newState == nil then
        log.log("[UPDATE] Ignored matchmaking event with unreadable NewValue")
        return
    end

    local previousState = oldState
    if previousState == nil then previousState = M.lastMatchmakingState end
    M.lastMatchmakingState = newState

    if newState == MATCHMAKING_QUEUED and previousState ~= MATCHMAKING_QUEUED then
        requestUpdateCheck("queue_entered")
    end
end

local function onMenuDisplayStateChanged(context, menuWidget, oldState, newState)
    local className = contextClassName(menuWidget)
    local displayState = hookNumber(newState)
    if className == SETTINGS_HUB_CLASS then
        -- UE4SS 3.0.1 RegisterCustomEvent keeps only the first registration for
        -- a short name. Chat already owns the navigation event names, so use
        -- this native router hook instead of competing for those callbacks.
        if displayState ~= nil then
            setSettingsInputCover(displayState ~= WIDGET_NOT_SHOWING)
        end
        return
    end
    if className ~= HOME_HUB_CLASS then return end

    local homeHub = unwrapHookValue(menuWidget)
    if displayState == WIDGET_ANIMATING_IN then
        -- Attach as soon as the native transition begins so the loading/menu
        -- layers can cover and reveal the card with the rest of PlayPanel.
        prepareHomeHub(homeHub, "router animating in")
    elseif displayState == WIDGET_SHOWING then
        beginHomeHubShowing(homeHub, "router display state")
    elseif displayState == WIDGET_NOT_SHOWING then
        hideForHomeHubExit("router display state")
    end
end

function M.onUpdateAvailable(latestVersion, installedVersion, releaseUrl, assetUrl)
    -- IPC checks the flat fact before dispatch. The browser destination needs
    -- stricter validation than informational URLs; rejected links do not hide
    -- the advisory itself.
    if type(latestVersion) ~= "string" or latestVersion == "" then
        log.log("[UPDATE] Ignored update without a valid latest version")
        return
    end
    M.latestVersion = latestVersion

    if M.notifiedVersions[latestVersion] then
        log.log("[UPDATE] Already notified this session: " .. tostring(latestVersion))
        return
    end

    M.pendingUpdate = {
        latestVersion = latestVersion,
        installedVersion = installedVersion,
        releaseUrl = validatedReleaseUrl(latestVersion, releaseUrl),
        assetUrl = assetUrl,
    }
    log.log("[UPDATE] Update available: " .. tostring(latestVersion))
    queuePresentationAttempt()
end

function M.onMatchCompleted()
    requestUpdateCheck("match_completed")
end

function M.reset()
    -- Map changes can invalidate UObjects. Never touch old references here;
    -- pending update facts and one-session de-duplication deliberately survive.
    M.lifecycleGeneration = M.lifecycleGeneration + 1
    M.widget = nil
    M.homeHub = nil
    M.hostContainer = nil
    M.widgetAttached = false
    M.homeHubActive = false
    M.settingsOpen = false
    M.visibleVersion = nil
    M.visibleReleaseUrl = nil
    M.lastMatchmakingState = nil
    M.presentationQueued = false
    M.localizationRefreshQueued = false
    M.cueRecoveryQueued = false
    M.pendingCueVersion = nil
    M.loadingScreenActive = true
end

function M.onMapLoaded()
    -- No visual settle timer: read the Home Hub's own display state once and
    -- let its native parent/transition own presentation. Router events cover
    -- later state changes and the case where the widget is not constructed yet.
    local generation = M.lifecycleGeneration
    local dispatchOk, dispatchErr = pcall(function()
        ExecuteInGameThread(function()
            if generation ~= M.lifecycleGeneration then return end
            refreshLoadingScreenState("map state")
            refreshHomeHubState("map state")
        end)
    end)
    if not dispatchOk then
        log.log("[UPDATE] Could not enqueue map-state refresh: " .. tostring(dispatchErr))
    end
end

function M.init()
    i18n.onLocaleChanged(refreshLocalizedText)

    local constructedOk, constructedErr = pcall(function()
        NotifyOnNewObject(WIDGET_CLASS_PATH, onNoticeWidgetConstructed)
    end)
    if constructedOk then
        log.log("[UPDATE] Notification construction listener registered")
    else
        log.log("[UPDATE] Notification construction listener failed: " ..
            tostring(constructedErr))
    end

    local loadingInOk, loadingInErr = pcall(function()
        RegisterCustomEvent("AnimateIn", onLoadingScreenAnimateIn)
    end)
    if loadingInOk then
        log.log("[UPDATE] Loading-screen AnimateIn event registered")
    else
        log.log("[UPDATE] Loading-screen AnimateIn event failed: " ..
            tostring(loadingInErr))
    end

    local loadingOutOk, loadingOutErr = pcall(function()
        RegisterHook(
            "/Script/OdyUI.OdyWidget:AnimateOutComplete",
            function() end,
            onLoadingScreenAnimateOutComplete
        )
    end)
    if loadingOutOk then
        log.log("[UPDATE] Loading-screen completion hook registered")
    else
        log.log("[UPDATE] Loading-screen completion hook failed: " ..
            tostring(loadingOutErr))
    end

    local loadingConstructOk, loadingConstructErr = pcall(function()
        RegisterCustomEvent("Construct", onLoadingScreenConstructed)
    end)
    if loadingConstructOk then
        log.log("[UPDATE] Loading-screen Construct event registered")
    else
        log.log("[UPDATE] Loading-screen Construct event failed: " ..
            tostring(loadingConstructErr))
    end

    -- Best-effort legacy Home Hub fallbacks only: UE4SS 3.0.1 accepts the first
    -- same-name custom event registration, which can already belong to chat.
    -- Home Hub and Settings state primarily use the native router hook below.
    local navToOk, navToErr = pcall(function()
        RegisterCustomEvent("OnNavigatedTo", onHomeHubNavigatedTo)
    end)
    if navToOk then
        log.log("[UPDATE] OnNavigatedTo event registered")
    else
        log.log("[UPDATE] OnNavigatedTo event failed: " .. tostring(navToErr))
    end

    local navAwayOk, navAwayErr = pcall(function()
        RegisterCustomEvent("OnNavigatedAway", onHomeHubNavigatedAway)
    end)
    if navAwayOk then
        log.log("[UPDATE] OnNavigatedAway event registered")
    else
        log.log("[UPDATE] OnNavigatedAway event failed: " .. tostring(navAwayErr))
    end

    local navBackOk, navBackErr = pcall(function()
        RegisterCustomEvent("OnNavBack", onHomeHubNavBack)
    end)
    if navBackOk then
        log.log("[UPDATE] OnNavBack event registered")
    else
        log.log("[UPDATE] OnNavBack event failed: " .. tostring(navBackErr))
    end

    local matchmakingOk, matchmakingErr = pcall(function()
        RegisterCustomEvent("OnMatchmakingStateChanged", onMatchmakingStateChanged)
    end)
    if matchmakingOk then
        log.log("[UPDATE] OnMatchmakingStateChanged event registered")
    else
        log.log("[UPDATE] OnMatchmakingStateChanged event failed: " .. tostring(matchmakingErr))
    end

    local closeSelfOk, closeSelfErr = pcall(function()
        RegisterHook("/Script/OdyUI.OdyMenu:CloseSelf", function() end, onHomeHubCloseSelf)
    end)
    if closeSelfOk then
        log.log("[UPDATE] CloseSelf hook registered")
    else
        log.log("[UPDATE] CloseSelf hook failed: " .. tostring(closeSelfErr))
    end

    local displayOk, displayErr = pcall(function()
        RegisterHook(
            "/Script/OdyUI.OdyUIRouter:OnMenuDisplayStateChanged",
            function() end,
            onMenuDisplayStateChanged
        )
    end)
    if displayOk then
        log.log("[UPDATE] Router display-state hook registered")
    else
        log.log("[UPDATE] Router display-state hook failed: " .. tostring(displayErr))
    end
end

return M
