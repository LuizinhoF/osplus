local cfg = require("config")

local M = {}

function M.ensureDir()
    os.execute('mkdir "' .. cfg.LOG_DIR .. '" 2>nul')
end

function M.log(msg)
    print("[OSTest] " .. msg .. "\n")
    local f = io.open(cfg.LOG_FILE, "a")
    if f then
        f:write(os.date("[%H:%M:%S] ") .. msg .. "\n")
        f:close()
    end
end

function M.try(label, fn)
    M.log("[>] " .. label)
    local results = { pcall(fn) }
    local success = table.remove(results, 1)
    if success then
        local desc = ""
        for i, v in ipairs(results) do
            if i > 1 then desc = desc .. ", " end
            desc = desc .. tostring(v)
        end
        if cfg.DEBUG then
            M.log("[<] " .. label .. ": OK" .. (desc ~= "" and (" -> " .. desc) or ""))
        end
        return true, table.unpack(results)
    else
        M.log("[!] " .. label .. ": FAIL -> " .. tostring(results[1]))
        return false, nil
    end
end

function M.safeFullName(obj)
    if obj and type(obj) ~= "number" and type(obj) ~= "string" and type(obj) ~= "boolean" then
        local ok, name = pcall(function() return obj:GetFullName() end)
        if ok and name then return name end
    end
    return tostring(obj) or "???"
end

return M
