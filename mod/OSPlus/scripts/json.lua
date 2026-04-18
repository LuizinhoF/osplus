-- Minimal JSON encode/decode for flat objects (no nested tables/arrays).
-- Sufficient for IPC messages like {"type":"ping","key":"DANGER","x":1234.5}

local json = {}

function json.encode(tbl)
    local parts = {}
    for k, v in pairs(tbl) do
        local vStr
        if type(v) == "string" then
            vStr = '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"'
        elseif type(v) == "number" then
            if v ~= v then
                vStr = "null"
            elseif v == math.huge then
                vStr = "1e308"
            elseif v == -math.huge then
                vStr = "-1e308"
            else
                vStr = string.format("%.6g", v)
            end
        elseif type(v) == "boolean" then
            vStr = v and "true" or "false"
        elseif v == nil then
            vStr = "null"
        else
            vStr = '"' .. tostring(v) .. '"'
        end
        parts[#parts + 1] = '"' .. tostring(k) .. '":' .. vStr
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

function json.decode(str)
    if type(str) ~= "string" then return nil end
    str = str:match("^%s*(.-)%s*$")
    if str == "" or str:sub(1, 1) ~= "{" then return nil end

    local result = {}
    local inner = str:sub(2, -2)

    local pos = 1
    local len = #inner

    local function skipWhitespace()
        while pos <= len and inner:sub(pos, pos):match("%s") do pos = pos + 1 end
    end

    local function readString()
        if inner:sub(pos, pos) ~= '"' then return nil end
        pos = pos + 1
        local start = pos
        local s = {}
        while pos <= len do
            local c = inner:sub(pos, pos)
            if c == '\\' then
                local next_c = inner:sub(pos + 1, pos + 1)
                if next_c == '"' then s[#s + 1] = '"'
                elseif next_c == '\\' then s[#s + 1] = '\\'
                elseif next_c == 'n' then s[#s + 1] = '\n'
                elseif next_c == 't' then s[#s + 1] = '\t'
                else s[#s + 1] = next_c end
                pos = pos + 2
            elseif c == '"' then
                pos = pos + 1
                return table.concat(s)
            else
                s[#s + 1] = c
                pos = pos + 1
            end
        end
        return table.concat(s)
    end

    local function readValue()
        skipWhitespace()
        local c = inner:sub(pos, pos)
        if c == '"' then
            return readString()
        end
        local rest = inner:sub(pos)
        local num = rest:match("^(-?%d+%.?%d*[eE]?[+-]?%d*)")
        if num then
            pos = pos + #num
            return tonumber(num)
        end
        if rest:sub(1, 4) == "true" then
            pos = pos + 4
            return true
        end
        if rest:sub(1, 5) == "false" then
            pos = pos + 5
            return false
        end
        if rest:sub(1, 4) == "null" then
            pos = pos + 4
            return nil
        end
        return nil
    end

    while pos <= len do
        skipWhitespace()
        if pos > len then break end

        local key = readString()
        if not key then break end

        skipWhitespace()
        if inner:sub(pos, pos) ~= ':' then break end
        pos = pos + 1

        local val = readValue()
        result[key] = val

        skipWhitespace()
        if inner:sub(pos, pos) == ',' then pos = pos + 1 end
    end

    return result
end

return json
