local Json = {}

local function isArray(t)
    if type(t) ~= "table" then return false end
    local n = #t
    if n == 0 then
        for _ in pairs(t) do return false end
        return true
    end
    local count = 0
    for k in pairs(t) do
        if type(k) ~= "number" then return false end
        count = count + 1
    end
    return count == n
end

local escapes = {
    ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
    ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
}

local function encodeString(s)
    return '"' .. s:gsub('[%z\1-\31"\\]', function(c)
        return escapes[c] or string.format('\\u%04x', c:byte())
    end) .. '"'
end

local function encodeValue(v)
    local t = type(v)
    if v == nil then return "null" end
    if t == "boolean" then return tostring(v) end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        return string.format("%.14g", v)
    end
    if t == "string" then return encodeString(v) end
    if t == "table" then
        local parts = {}
        if isArray(v) then
            for i = 1, #v do
                parts[#parts + 1] = encodeValue(v[i])
            end
        else
            local keys = {}
            for k in pairs(v) do keys[#keys + 1] = k end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for _, k in ipairs(keys) do
                local key = type(k) == "string" and encodeString(k) or encodeString(tostring(k))
                parts[#parts + 1] = key .. ":" .. encodeValue(v[k])
            end
        end
        if #parts == 0 then
            return isArray(v) and "[]" or "{}"
        end
        if isArray(v) then
            return "[" .. table.concat(parts, ",") .. "]"
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    error("Json: cannot encode value of type " .. t)
end

function Json.encode(v)
    return encodeValue(v)
end

local function decodeError(str, pos, msg)
    error("Json: parse error at position " .. pos .. ": " .. msg .. " (near '" .. str:sub(math.max(1, pos - 10), pos + 20) .. "')", 0)
end

local parseValue

local function skipWs(str, pos)
    local _, e = str:find("^[ \t\r\n]*", pos)
    return (e or pos - 1) + 1
end

local function parseString(str, pos)
    if str:sub(pos, pos) ~= '"' then decodeError(str, pos, "expected string") end
    pos = pos + 1
    local buf = {}
    while true do
        local c = str:sub(pos, pos)
        if c == "" then decodeError(str, pos, "unterminated string") end
        if c == '"' then return table.concat(buf), pos + 1 end
        if c == "\\" then
            local esc = str:sub(pos + 1, pos + 1)
            pos = pos + 2
            local map = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }
            if esc == 'u' then
                local hex = str:sub(pos, pos + 3)
                local code = tonumber(hex, 16)
                if not code then decodeError(str, pos, "bad unicode escape") end
                buf[#buf + 1] = string.char(code < 256 and code or 63)
                pos = pos + 4
            elseif map[esc] then
                buf[#buf + 1] = map[esc]
            else
                decodeError(str, pos - 2, "bad escape \\" .. esc)
            end
        else
            buf[#buf + 1] = c
            pos = pos + 1
        end
    end
end

local function parseNumber(str, pos)
    local s, e, num = str:find("^(%-?%d+%.?%d*[eE]?[+-]?%d*)", pos)
    if not s then decodeError(str, pos, "expected number") end
    return tonumber(num), e + 1
end

local function parseLiteral(str, pos, lit, value)
    if str:sub(pos, pos + #lit - 1) == lit then return value, pos + #lit end
    decodeError(str, pos, "expected " .. lit)
end

local function parseArray(str, pos)
    local arr = {}
    pos = skipWs(str, pos + 1)
    if str:sub(pos, pos) == "]" then return arr, pos + 1 end
    local i = 1
    while true do
        local v
        v, pos = parseValue(str, pos)
        arr[i] = v
        i = i + 1
        pos = skipWs(str, pos)
        local c = str:sub(pos, pos)
        if c == "," then pos = skipWs(str, pos + 1)
        elseif c == "]" then return arr, pos + 1
        else decodeError(str, pos, "expected , or ]") end
    end
end

local function parseObject(str, pos)
    local obj = {}
    pos = skipWs(str, pos + 1)
    if str:sub(pos, pos) == "}" then return obj, pos + 1 end
    while true do
        local key
        key, pos = parseString(str, pos)
        pos = skipWs(str, pos)
        if str:sub(pos, pos) ~= ":" then decodeError(str, pos, "expected :") end
        local v
        v, pos = parseValue(str, pos + 1)
        obj[key] = v
        pos = skipWs(str, pos)
        local c = str:sub(pos, pos)
        if c == "," then pos = skipWs(str, pos + 1)
        elseif c == "}" then return obj, pos + 1
        else decodeError(str, pos, "expected , or }") end
    end
end

parseValue = function(str, pos)
    pos = skipWs(str, pos)
    local c = str:sub(pos, pos)
    if c == '{' then return parseObject(str, pos)
    elseif c == '[' then return parseArray(str, pos)
    elseif c == '"' then return parseString(str, pos)
    elseif c == '-' or c:match("%d") then return parseNumber(str, pos)
    elseif str:sub(pos, pos + 3) == "true" then return parseLiteral(str, pos, "true", true)
    elseif str:sub(pos, pos + 4) == "false" then return parseLiteral(str, pos, "false", false)
    elseif str:sub(pos, pos + 3) == "null" then return parseLiteral(str, pos, "null", nil)
    end
    decodeError(str, pos, "unexpected character '" .. c .. "'")
end

function Json.decode(str)
    if type(str) ~= "string" then error("Json.decode: expected string", 2) end
    local v = parseValue(str, 1)
    return v
end

return Json
