local cfg = require("config")
local json = require("json")
local log = require("log")

local M = {}

local PREFIX = "[Localization]"

local loaded = false
local loadedPaths = {}
local defaultLocale = "en"
local strings = {}
local tags = {}
local currentLocale = nil
local currentLocaleAuthoritative = false
local initialized = false
local callbacks = {}
local retryTick = 0
local lastLazyRefreshSecond = nil
local RETRY_INTERVAL_TICKS = 30
local STARTUP_PROBE_TICKS = 600
local startupProbeTicksRemaining = STARTUP_PROBE_TICKS

local function trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function readAll(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local body = f:read("*a")
    f:close()
    return body
end

local function userdataToString(v)
    if v == nil then return nil end
    if type(v) == "string" then return v end
    if type(v) == "number" or type(v) == "boolean" then return tostring(v) end
    if type(v) == "userdata" then
        local ok, s = pcall(function() return v:ToString() end)
        if ok and type(s) == "string" then return s end
    end
    return nil
end

local function normalizeLocale(raw)
    local s = trim(userdataToString(raw) or "")
    if s == "" or s == "None" then return nil end

    local lower = s:lower():gsub("_", "-")
    if lower:find("pt", 1, true)
        or lower:find("portug", 1, true)
        or lower:find("brazil", 1, true) then
        return "pt-BR"
    end

    if lower:find("en", 1, true)
        or lower:find("english", 1, true)
        or lower:find("ingl", 1, true) then
        return "en"
    end

    return nil
end

local function readKismetLocaleRaw()
    local lib = nil
    pcall(function() lib = StaticFindObject("/Script/Engine.Default__KismetInternationalizationLibrary") end)
    if not lib then return nil, nil end

    local raw = nil
    pcall(function() raw = lib:GetCurrentCulture() end)
    if normalizeLocale(raw) then return raw, "KismetInternationalizationLibrary.GetCurrentCulture" end

    pcall(function() raw = lib:GetCurrentLanguage() end)
    if normalizeLocale(raw) then return raw, "KismetInternationalizationLibrary.GetCurrentLanguage" end

    pcall(function() raw = lib:GetCurrentLocale() end)
    if normalizeLocale(raw) then return raw, "KismetInternationalizationLibrary.GetCurrentLocale" end

    return nil, nil
end

local function readGameInstanceLocaleRaw()
    local gi = nil
    pcall(function() gi = FindFirstOf("PMGameInstance") end)
    if not gi then return nil, nil end

    local raw = nil
    pcall(function() raw = gi:GetTextLanguage() end)
    if normalizeLocale(raw) then return raw, "PMGameInstance.GetTextLanguage" end

    pcall(function() raw = gi.TextLanguage end)
    if normalizeLocale(raw) then return raw, "PMGameInstance.TextLanguage" end

    pcall(function() raw = gi.CurrentTextLanguage end)
    if normalizeLocale(raw) then return raw, "PMGameInstance.CurrentTextLanguage" end

    return nil, nil
end

local function readGameLocaleRaw(opts)
    opts = opts or {}
    local allowKismetFallback = opts.allowKismetFallback ~= false

    local envLocale = os.getenv("OSPLUS_LOCALE")
    if envLocale and envLocale ~= "" then return envLocale, "OSPLUS_LOCALE", true end

    -- Prefer the game's own text-language state when polling. Kismet culture
    -- can reflect the OS/user environment before Omega Strikers' saved UI
    -- language has settled, which made OSPlus start in pt-BR on non-pt-BR game
    -- settings. Runtime language-change hooks still use their hook parameter as
    -- authoritative, avoiding the stale getter issue during an active switch.
    local raw, source = readGameInstanceLocaleRaw()
    if raw ~= nil then return raw, source, false end

    if allowKismetFallback then
        raw, source = readKismetLocaleRaw()
        if raw ~= nil then return raw, source, false end
    end

    return nil, nil, false
end

local function emitLocaleChanged(locale)
    for _, cb in ipairs(callbacks) do
        local ok, err = pcall(cb, locale)
        if not ok then
            log.log(string.format("%s locale-change callback failed: %s", PREFIX, tostring(err)))
        end
    end
end

local function setCurrentLocale(raw, emit, authoritative, source)
    local normalized = normalizeLocale(raw)
    local locale = normalized or currentLocale or defaultLocale or "en"
    local wasAuthoritative = currentLocaleAuthoritative
    if locale ~= currentLocale then
        currentLocale = locale
        log.log(string.format("%s active locale = %s%s",
            PREFIX,
            locale,
            source and (" (" .. source .. ")") or ""))
        if emit then emitLocaleChanged(locale) end
    end
    if normalized and authoritative and not currentLocaleAuthoritative then
        currentLocaleAuthoritative = true
        if wasAuthoritative ~= currentLocaleAuthoritative and locale == currentLocale then
            log.log(string.format("%s locale source locked: %s", PREFIX, source or "game"))
        end
    end
    return currentLocale
end

local function mergeStrings(source)
    if type(source) ~= "table" then return end
    for key, value in pairs(source) do
        strings[key] = value
    end
end

local function mergeTags(source)
    if type(source) ~= "table" then return end
    for key, value in pairs(source) do
        tags[key] = value
    end
end

function M.configureFromCatalog(decoded, path)
    if type(decoded) ~= "table" then return end
    defaultLocale = normalizeLocale(decoded.default_locale or decoded.defaultLocale) or defaultLocale
    mergeStrings(decoded.strings)
    mergeTags(decoded.tags)
    if path then loadedPaths[#loadedPaths + 1] = path end
end

local function configureFromLocalization(decoded, path)
    if type(decoded) ~= "table" then return end
    defaultLocale = normalizeLocale(decoded.default_locale or decoded.defaultLocale) or defaultLocale
    mergeStrings(decoded.strings or decoded)
    if path then loadedPaths[#loadedPaths + 1] = path end
end

local function tryLoadJson(relativePath)
    local candidates = cfg.DATA_DIR_CANDIDATES or {}
    for _, dir in ipairs(candidates) do
        local path = dir .. "\\" .. relativePath
        local body = readAll(path)
        if body then
            local decoded = json.decode(body)
            if type(decoded) == "table" then
                return decoded, path
            end
        end
    end
    return nil, nil
end

local function loadData()
    if loaded then return end
    loaded = true

    local catalog, catalogPath = tryLoadJson(cfg.EMOTE_CATALOG_FILE)
    if catalog then
        M.configureFromCatalog(catalog, catalogPath)
    end

    for _, relativePath in ipairs(cfg.LOCALIZATION_FILES or {}) do
        local decoded, path = tryLoadJson(relativePath)
        if decoded then
            configureFromLocalization(decoded, path)
        else
            log.log(string.format("%s localization file not found: %s", PREFIX, relativePath))
        end
    end

    if #loadedPaths > 0 then
        log.log(string.format("%s loaded data from %s", PREFIX, table.concat(loadedPaths, ", ")))
    end
end

function M.refreshFromGame(emit, opts)
    local raw, source, authoritative = readGameLocaleRaw(opts)
    return setCurrentLocale(raw, emit, authoritative, source)
end

function M.currentLocale()
    if not currentLocale then
        M.refreshFromGame(false)
    elseif not currentLocaleAuthoritative then
        local now = os.time()
        if now ~= lastLazyRefreshSecond then
            lastLazyRefreshSecond = now
            M.refreshFromGame(false)
        end
    end
    return currentLocale or defaultLocale or "en"
end

function M.isAuthoritative()
    return currentLocaleAuthoritative and true or false
end

local function localeCandidates()
    local locale = M.currentLocale()
    local out = { locale }

    local base = locale:match("^([^-]+)")
    if base and base ~= locale then out[#out + 1] = base end
    if defaultLocale and defaultLocale ~= locale then out[#out + 1] = defaultLocale end
    if defaultLocale ~= "en" then out[#out + 1] = "en" end

    return out
end

function M.localize(value, fallback)
    loadData()

    if type(value) == "string" then
        return value ~= "" and value or (fallback or "")
    end

    if type(value) ~= "table" then
        return fallback or ""
    end

    for _, locale in ipairs(localeCandidates()) do
        local direct = value[locale]
        if type(direct) == "string" and direct ~= "" then return direct end

        local lower = value[locale:lower()]
        if type(lower) == "string" and lower ~= "" then return lower end
    end

    for _, v in pairs(value) do
        if type(v) == "string" and v ~= "" then return v end
    end

    return fallback or ""
end

function M.localizeStrict(value, fallback)
    loadData()

    if type(value) == "string" then
        return value ~= "" and value or (fallback or "")
    end

    if type(value) ~= "table" then
        return fallback or ""
    end

    local locale = M.currentLocale()
    local direct = value[locale]
    if type(direct) == "string" and direct ~= "" then return direct end

    local lower = value[locale:lower()]
    if type(lower) == "string" and lower ~= "" then return lower end

    local base = locale:match("^([^-]+)")
    if base and base ~= locale then
        local baseValue = value[base] or value[base:lower()]
        if type(baseValue) == "string" and baseValue ~= "" then return baseValue end
    end

    return fallback or ""
end

local function applyParams(text, params)
    if type(params) ~= "table" then return text end
    return (text:gsub("{([%w_]+)}", function(key)
        local v = params[key]
        if v == nil then return "{" .. key .. "}" end
        return tostring(v)
    end))
end

function M.text(key, fallback, params)
    loadData()
    local value = strings[key]
    return applyParams(M.localize(value, fallback or key), params)
end

function M.tagLabel(key, fallback)
    loadData()
    local entry = tags[key]
    if type(entry) == "table" then
        return M.localize(entry.label or entry.name or entry, fallback)
    end
    return fallback or key
end

function M.onLocaleChanged(cb)
    if type(cb) ~= "function" then return end
    callbacks[#callbacks + 1] = cb
end

function M.init()
    if initialized then return end
    initialized = true
    loadData()
    M.refreshFromGame(false)

    -- See docs/learnings/localization-startup-fallback-vs-authoritative.md:
    -- a startup fallback/default must not permanently close the locale
    -- detection loop.
    local function firstLocaleParam(...)
        local raw = nil
        for i = 2, select("#", ...) do
            local param = select(i, ...)
            pcall(function() raw = param:get() end)
            if raw == nil then raw = param end
            if normalizeLocale(raw) then return raw end
            raw = nil
        end
        return nil
    end

    local function onTextLanguageChanged(source, ...)
        local raw = firstLocaleParam(...)
        if raw ~= nil then
            setCurrentLocale(raw, true, true, source)
        elseif source and source:find("KismetInternationalizationLibrary", 1, true) then
            local kismetRaw, kismetSource = readKismetLocaleRaw()
            if kismetRaw ~= nil then
                -- A Kismet culture setter can fire before the game's text
                -- language has finished settling. Treat the immediate Kismet
                -- read as a useful notification, not as a permanent lock; the
                -- global tick will keep polling PMGameInstance and emit the
                -- final locale as soon as the game state catches up.
                setCurrentLocale(kismetRaw, true, false, kismetSource or source)
            else
                M.refreshFromGame(true)
            end
        else
            M.refreshFromGame(true)
        end
    end

    local okHook, errHook = pcall(RegisterHook, "/Script/Prometheus.PMGameInstance:SetTextLanguage", function(...)
        onTextLanguageChanged("PMGameInstance.SetTextLanguage hook param", ...)
    end)
    if okHook then
        log.log(PREFIX .. " RegisterHook installed: PMGameInstance:SetTextLanguage")
    else
        log.log(string.format("%s SetTextLanguage hook unavailable: %s", PREFIX, tostring(errHook)))
    end

    local okCustom, errCustom = pcall(RegisterCustomEvent, "SetTextLanguage", function(...)
        onTextLanguageChanged("SetTextLanguage custom-event param", ...)
    end)
    if okCustom then
        log.log(PREFIX .. " RegisterCustomEvent installed: SetTextLanguage")
    else
        log.log(string.format("%s SetTextLanguage custom-event hook unavailable: %s", PREFIX, tostring(errCustom)))
    end

    local cultureHooks = {
        "/Script/Engine.KismetInternationalizationLibrary:SetCurrentCulture",
        "/Script/Engine.KismetInternationalizationLibrary:SetCurrentLanguage",
        "/Script/Engine.KismetInternationalizationLibrary:SetCurrentLanguageAndLocale",
        "/Script/Engine.KismetInternationalizationLibrary:SetCurrentLocale",
    }
    for _, path in ipairs(cultureHooks) do
        local okCulture, errCulture = pcall(RegisterHook, path, function(...)
            onTextLanguageChanged(path .. " hook param", ...)
        end)
        if okCulture then
            log.log(PREFIX .. " RegisterHook installed: " .. path)
        else
            log.log(string.format("%s culture hook unavailable (%s): %s", PREFIX, path, tostring(errCulture)))
        end
    end
end

function M.tick()
    if not initialized then return end

    retryTick = retryTick + 1
    if retryTick < RETRY_INTERVAL_TICKS then return end
    retryTick = 0

    -- Keep runtime polling alive even after startup. Language-change hooks are
    -- useful, but UE4SS can miss or stale-read some culture transitions. After
    -- startup, poll only the game instance (plus env override), not Kismet, so
    -- the OS/user culture cannot overwrite the game's selected text language.
    M.refreshFromGame(true, {
        allowKismetFallback = startupProbeTicksRemaining > 0 or currentLocale == nil
    })
    if startupProbeTicksRemaining > 0 then
        startupProbeTicksRemaining = startupProbeTicksRemaining - RETRY_INTERVAL_TICKS
    end
end

return M
