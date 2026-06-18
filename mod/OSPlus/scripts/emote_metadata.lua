-- Repo-owned emote metadata overlay.
--
-- Native catalog data remains authoritative for ownership/equip state. This
-- file only enriches display records with optional description, tags, source,
-- and an override visual asset path.

local cfg = require("config")
local json = require("json")
local i18n = require("localization")
local log = require("log")

local M = {}

local PREFIX = "[EmoteMetadata]"

local loaded = false
local catalogById = {}
local configuredFilterChips = {}
local loadedPath = nil

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

local function normalizeTags(tags)
    local out = {}
    local seen = {}
    if type(tags) ~= "table" then return out end

    for _, raw in ipairs(tags) do
        local tag = trim(raw):lower()
        if tag ~= "" and not seen[tag] then
            out[#out + 1] = tag
            seen[tag] = true
        end
    end
    table.sort(out)
    return out
end

local function normalizeSource(source)
    source = trim(source):lower()
    if source == "osplus" then return "osplus" end
    return "native"
end

local function pathWithDottedAsset(path)
    path = trim(path)
    if path == "" then return "" end
    local lastSlash = path:find("/[^/]*$")
    if lastSlash then
        local leaf = path:sub(lastSlash + 1)
        if not leaf:find(".", 1, true) then
            path = path .. "." .. leaf
        end
    end
    return path
end

local function normalizeEntry(raw)
    if type(raw) ~= "table" then return nil end
    local id = trim(raw.id or raw.Id)
    if id == "" then return nil end

    local tags = normalizeTags(raw.tags or raw.Tags)
    local entry = {
        id = id,
        name = raw.name or raw.Name,
        description = raw.description or raw.Description,
        tags = tags,
        source = normalizeSource(raw.source or raw.Source),
        visual_asset_path = pathWithDottedAsset(raw.visual_asset_path or raw.VisualAssetPath),
    }

    entry.tags_packed = json.encode(tags)
    return entry
end

local function normalizeFilterChip(raw)
    if type(raw) ~= "table" then return nil end

    local key = trim(raw.key or raw.Key):lower()
    if key == "" then return nil end

    local kind, value = key:match("^([^:]+):(.+)$")
    if kind ~= "source" and kind ~= "tag" then return nil end

    value = trim(value):lower()
    if value == "" then return nil end

    return {
        key = kind .. ":" .. value,
        kind = kind,
        value = value,
        label = raw.label or raw.Label,
    }
end

local function loadCatalog()
    if loaded then return end
    loaded = true

    local candidates = cfg.DATA_DIR_CANDIDATES or {}
    for _, dir in ipairs(candidates) do
        local path = dir .. "\\" .. cfg.EMOTE_CATALOG_FILE
        local body = readAll(path)
        if body then
            local decoded = json.decode(body)
            if type(decoded) ~= "table" then
                error(PREFIX .. " invalid JSON at " .. path)
            end
            i18n.configureFromCatalog(decoded, path)

            local entries = decoded.emotes or decoded.entries or decoded
            if type(entries) ~= "table" then
                error(PREFIX .. " no emotes array at " .. path)
            end

            local count = 0
            for _, raw in ipairs(entries) do
                local entry = normalizeEntry(raw)
                if entry then
                    catalogById[entry.id] = entry
                    count = count + 1
                end
            end

            configuredFilterChips = {}
            for _, raw in ipairs(decoded.filter_chips or decoded.filterChips or {}) do
                local chip = normalizeFilterChip(raw)
                if chip then configuredFilterChips[#configuredFilterChips + 1] = chip end
            end

            loadedPath = path
            log.log(string.format("%s loaded %d entries from %s", PREFIX, count, path))
            return
        end
    end

    error(PREFIX .. " catalog.json not found in configured data directories")
end

local function labelFromKey(key)
    key = trim(key)
    if key == "" then return "" end
    key = key:gsub("[_%-%s]+", " ")
    return (key:gsub("(%S)(%S*)", function(a, b)
        return a:upper() .. b
    end))
end

local function buildSearchText(record)
    local parts = {
        record.id or "",
        record.name or "",
        record.description or "",
        record.source or "",
        "source:" .. (record.source or ""),
    }

    for _, tag in ipairs(record.tags or {}) do
        parts[#parts + 1] = tag
        parts[#parts + 1] = "tag:" .. tag
        parts[#parts + 1] = i18n.tagLabel(tag, "")
    end

    return (" " .. table.concat(parts, " ") .. " "):lower()
end

local function buildTagsDisplay(tags)
    local labels = {}
    for _, tag in ipairs(tags or {}) do
        local label = i18n.tagLabel(tag, labelFromKey(tag))
        if label ~= "" then labels[#labels + 1] = label end
    end
    return table.concat(labels, ", ")
end

local function filterChipLabel(chip)
    if chip.label ~= nil then
        return i18n.localize(chip.label, "")
    end

    if chip.kind == "source" then
        if chip.value == "osplus" then
            return i18n.text("emote_loadout.filter.source.osplus", "OSPlus")
        end
        return i18n.text("emote_loadout.filter.source.native", "Native")
    end

    return i18n.tagLabel(chip.value, labelFromKey(chip.value))
end

local function sortChipRecords(a, b)
    local al = (a.label or a.key or ""):lower()
    local bl = (b.label or b.key or ""):lower()
    if al == bl then return (a.key or "") < (b.key or "") end
    return al < bl
end

function M.get(id)
    loadCatalog()
    if type(id) ~= "string" then return nil end
    return catalogById[id]
end

function M.mergeNative(base)
    loadCatalog()
    base = base or {}

    local id = base.id or ""
    local meta = catalogById[id] or {}
    local tags = meta.tags or {}
    local source = meta.source or "native"
    local name = source == "native"
        and i18n.localizeStrict(meta.name, "")
        or i18n.localize(meta.name, "")
    local description = source == "native"
        and i18n.localizeStrict(meta.description, "")
        or i18n.localize(meta.description, "")
    local visualPath = meta.visual_asset_path
    if not visualPath or visualPath == "" then
        visualPath = base.visual_asset_path or base.animated_texture or base.icon or ""
    end

    local record = {
        id = id,
        name = (name ~= "" and name) or base.name or "",
        icon = base.icon or "",
        description = description,
        tags = tags,
        tags_packed = meta.tags_packed or json.encode(tags),
        tags_display = buildTagsDisplay(tags),
        source = source,
        visual_asset_path = visualPath or "",
        visual_kind = base.visual_kind or "",
    }
    record.search_text = buildSearchText(record)
    return record
end

function M.buildFilterChips(displays)
    loadCatalog()

    local chips = {
        { Key = "", Label = i18n.text("emote_loadout.filter.all", "All") },
    }
    local sources = {}
    local tags = {}
    local emitted = {}

    for _, d in ipairs(displays or {}) do
        local source = trim(d.Source or d.source):lower()
        if source ~= "" then sources[source] = true end

        local tagList = d.Tags or d.tags
        if type(tagList) == "table" then
            for _, tag in ipairs(tagList) do
                tag = trim(tag):lower()
                if tag ~= "" then tags[tag] = true end
            end
        end
    end

    for _, chip in ipairs(configuredFilterChips) do
        local present = chip.kind == "source"
            and sources[chip.value]
            or chip.kind == "tag" and tags[chip.value]
        if present then
            emitted[chip.key] = true
            chips[#chips + 1] = {
                Key = chip.key,
                Label = filterChipLabel(chip),
            }
        end
    end

    local remainingTags = {}
    for tag in pairs(tags) do
        local key = "tag:" .. tag
        if not emitted[key] then
            remainingTags[#remainingTags + 1] = {
                key = key,
                label = i18n.tagLabel(tag, labelFromKey(tag)),
            }
        end
    end
    table.sort(remainingTags, sortChipRecords)
    for _, chip in ipairs(remainingTags) do
        chips[#chips + 1] = {
            Key = chip.key,
            Label = chip.label,
        }
    end

    return chips
end

function M.loadedPath()
    loadCatalog()
    return loadedPath
end

return M
