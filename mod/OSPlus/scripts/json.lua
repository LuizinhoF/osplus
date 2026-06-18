-- Small JSON codec used by UE4SS Lua.
-- Supports objects, arrays, strings, numbers, booleans, and null. Kept local
-- to the mod so runtime metadata does not depend on external Lua libraries.

local json = {}

local escape_map = {
    ['"'] = '\\"',
    ['\\'] = '\\\\',
    ['\b'] = '\\b',
    ['\f'] = '\\f',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
}

local function escape_string(s)
    return '"' .. tostring(s):gsub('[%z\1-\31"\\]', function(c)
        return escape_map[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function is_array(tbl)
    local max = 0
    local count = 0
    for k, _ in pairs(tbl) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
            return false
        end
        if k > max then max = k end
        count = count + 1
    end
    return max == count
end

local encode_value

local function encode_array(tbl)
    local parts = {}
    for i = 1, #tbl do
        parts[i] = encode_value(tbl[i])
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

local function encode_object(tbl)
    local parts = {}
    for k, v in pairs(tbl) do
        parts[#parts + 1] = escape_string(k) .. ":" .. encode_value(v)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

encode_value = function(v)
    local t = type(v)
    if t == "string" then
        return escape_string(v)
    elseif t == "number" then
        if v ~= v then
            return "null"
        elseif v == math.huge then
            return "1e308"
        elseif v == -math.huge then
            return "-1e308"
        end
        return string.format("%.17g", v)
    elseif t == "boolean" then
        return v and "true" or "false"
    elseif t == "table" then
        if is_array(v) then return encode_array(v) end
        return encode_object(v)
    elseif v == nil then
        return "null"
    end
    return escape_string(tostring(v))
end

function json.encode(value)
    return encode_value(value)
end

local function utf8_from_codepoint(cp)
    if not cp then return "" end
    if cp < 0x80 then
        return string.char(cp)
    elseif cp < 0x800 then
        return string.char(
            0xC0 + math.floor(cp / 0x40),
            0x80 + (cp % 0x40)
        )
    elseif cp < 0x10000 then
        return string.char(
            0xE0 + math.floor(cp / 0x1000),
            0x80 + (math.floor(cp / 0x40) % 0x40),
            0x80 + (cp % 0x40)
        )
    elseif cp < 0x110000 then
        return string.char(
            0xF0 + math.floor(cp / 0x40000),
            0x80 + (math.floor(cp / 0x1000) % 0x40),
            0x80 + (math.floor(cp / 0x40) % 0x40),
            0x80 + (cp % 0x40)
        )
    end
    return ""
end

function json.decode(str)
    if type(str) ~= "string" then return nil end

    local pos = 1
    local len = #str

    local function skip_ws()
        while pos <= len and str:sub(pos, pos):match("%s") do
            pos = pos + 1
        end
    end

    local parse_value

    local function parse_string()
        if str:sub(pos, pos) ~= '"' then return nil end
        pos = pos + 1
        local out = {}

        while pos <= len do
            local c = str:sub(pos, pos)
            if c == '"' then
                pos = pos + 1
                return table.concat(out)
            elseif c == "\\" then
                local n = str:sub(pos + 1, pos + 1)
                if n == '"' or n == "\\" or n == "/" then
                    out[#out + 1] = n
                    pos = pos + 2
                elseif n == "b" then
                    out[#out + 1] = "\b"
                    pos = pos + 2
                elseif n == "f" then
                    out[#out + 1] = "\f"
                    pos = pos + 2
                elseif n == "n" then
                    out[#out + 1] = "\n"
                    pos = pos + 2
                elseif n == "r" then
                    out[#out + 1] = "\r"
                    pos = pos + 2
                elseif n == "t" then
                    out[#out + 1] = "\t"
                    pos = pos + 2
                elseif n == "u" then
                    local hex = str:sub(pos + 2, pos + 5)
                    out[#out + 1] = utf8_from_codepoint(tonumber(hex, 16))
                    pos = pos + 6
                else
                    return nil
                end
            else
                out[#out + 1] = c
                pos = pos + 1
            end
        end
        return nil
    end

    local function parse_array()
        if str:sub(pos, pos) ~= "[" then return nil end
        pos = pos + 1
        local arr = {}
        skip_ws()
        if str:sub(pos, pos) == "]" then
            pos = pos + 1
            return arr
        end

        while pos <= len do
            local val = parse_value()
            arr[#arr + 1] = val
            skip_ws()
            local c = str:sub(pos, pos)
            if c == "]" then
                pos = pos + 1
                return arr
            elseif c ~= "," then
                return nil
            end
            pos = pos + 1
        end
        return nil
    end

    local function parse_object()
        if str:sub(pos, pos) ~= "{" then return nil end
        pos = pos + 1
        local obj = {}
        skip_ws()
        if str:sub(pos, pos) == "}" then
            pos = pos + 1
            return obj
        end

        while pos <= len do
            skip_ws()
            local key = parse_string()
            if key == nil then return nil end
            skip_ws()
            if str:sub(pos, pos) ~= ":" then return nil end
            pos = pos + 1
            obj[key] = parse_value()
            skip_ws()
            local c = str:sub(pos, pos)
            if c == "}" then
                pos = pos + 1
                return obj
            elseif c ~= "," then
                return nil
            end
            pos = pos + 1
        end
        return nil
    end

    local function parse_number()
        local start = pos
        local c = str:sub(pos, pos)
        if c == "-" then pos = pos + 1 end

        while pos <= len and str:sub(pos, pos):match("%d") do
            pos = pos + 1
        end
        if str:sub(pos, pos) == "." then
            pos = pos + 1
            while pos <= len and str:sub(pos, pos):match("%d") do
                pos = pos + 1
            end
        end
        c = str:sub(pos, pos)
        if c == "e" or c == "E" then
            pos = pos + 1
            c = str:sub(pos, pos)
            if c == "+" or c == "-" then pos = pos + 1 end
            while pos <= len and str:sub(pos, pos):match("%d") do
                pos = pos + 1
            end
        end

        if pos == start then return nil end
        return tonumber(str:sub(start, pos - 1))
    end

    parse_value = function()
        skip_ws()
        local c = str:sub(pos, pos)
        if c == '"' then return parse_string() end
        if c == "{" then return parse_object() end
        if c == "[" then return parse_array() end
        if c == "-" or c:match("%d") then return parse_number() end
        if str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        end
        if str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        end
        if str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        end
        return nil
    end

    local value = parse_value()
    skip_ws()
    if pos <= len then return nil end
    return value
end

return json
