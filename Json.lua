-- Json.lua: writes JSON. Plain Lua with no game API, so it can be tested
-- outside the game.
--
-- Lua tables cannot tell an object from an array, nor keep a key whose
-- value is nil, so values to write are built with:
--   Json.Object(key1, value1, key2, value2, ...)  keys in this order; a nil
--                                                  value is written as null
--   Json.Array(list)                               list[1] .. list[#list]
-- Strings are written as UTF-8. Bytes that are not valid UTF-8 become
-- U+FFFD, so the output is always valid JSON.
local _, ns = ...

local Json = {}
ns.Json = Json

local byte, char, format, find, gsub, sub = string.byte, string.char, string.format, string.find, string.gsub, string.sub
local floor, huge = math.floor, math.huge
local concat = table.concat

local OBJECT, ARRAY = {}, {}

function Json.Object(...)
    return setmetatable({ n = select("#", ...), ... }, OBJECT)
end

function Json.Array(list)
    return setmetatable({ items = list or {} }, ARRAY)
end

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function Escape(c)
    return ESCAPES[c] or format("\\u%04x", byte(c))
end

local REPLACEMENT = "\239\191\189" -- U+FFFD

-- The text with every byte that is not part of a valid UTF-8 character
-- replaced by U+FFFD.
function Json.ValidUTF8(text)
    if not find(text, "[\128-\255]") then
        return text
    end
    local out, i, n = {}, 1, #text
    local start = 1
    while i <= n do
        local c = byte(text, i)
        local size, min
        if c < 0x80 then
            size = 1
        elseif c >= 0xC2 and c <= 0xDF then
            size, min = 2, 0x80
        elseif c >= 0xE0 and c <= 0xEF then
            size, min = 3, 0x800
        elseif c >= 0xF0 and c <= 0xF4 then
            size, min = 4, 0x10000
        end
        local valid = size ~= nil and i + size - 1 <= n
        if valid and size > 1 then
            local code = c % (2 ^ (7 - size))
            for j = i + 1, i + size - 1 do
                local continuation = byte(text, j)
                if continuation < 0x80 or continuation > 0xBF then
                    valid = false
                    break
                end
                code = code * 64 + continuation % 64
            end
            -- Overlong forms, surrogates and code points past U+10FFFF.
            if valid and (code < min or (code >= 0xD800 and code <= 0xDFFF) or code > 0x10FFFF) then
                valid = false
            end
        end
        if valid then
            i = i + size
        else
            out[#out + 1] = sub(text, start, i - 1)
            out[#out + 1] = REPLACEMENT
            i = i + 1
            start = i
        end
    end
    out[#out + 1] = sub(text, start)
    return concat(out)
end

local function String(text)
    return '"' .. gsub(Json.ValidUTF8(text), '[%c"\\]', Escape) .. '"'
end

Json.String = String

local function Number(value)
    if value ~= value or value == huge or value == -huge then
        return "null"
    end
    if value == floor(value) and value > -2 ^ 53 and value < 2 ^ 53 then
        return format("%d", value)
    end
    return format("%.14g", value)
end

-- Appends the JSON of value to out. indent: nil for compact output, else
-- the current indentation (pretty output, two spaces per level).
local function Write(out, value, indent)
    local kind = type(value)
    if value == nil then
        out[#out + 1] = "null"
    elseif kind == "boolean" then
        out[#out + 1] = value and "true" or "false"
    elseif kind == "number" then
        out[#out + 1] = Number(value)
    elseif kind == "string" then
        out[#out + 1] = String(value)
    elseif kind == "table" and getmetatable(value) == OBJECT then
        if value.n == 0 then
            out[#out + 1] = "{}"
            return
        end
        local inner = indent and (indent .. "  ")
        out[#out + 1] = "{"
        for i = 1, value.n, 2 do
            if i > 1 then
                out[#out + 1] = ","
            end
            if inner then
                out[#out + 1] = "\n" .. inner
            end
            out[#out + 1] = String(tostring(value[i]))
            out[#out + 1] = inner and ": " or ":"
            Write(out, value[i + 1], inner)
        end
        out[#out + 1] = inner and ("\n" .. indent .. "}") or "}"
    elseif kind == "table" and getmetatable(value) == ARRAY then
        local items = value.items
        if #items == 0 then
            out[#out + 1] = "[]"
            return
        end
        local inner = indent and (indent .. "  ")
        out[#out + 1] = "["
        for i = 1, #items do
            if i > 1 then
                out[#out + 1] = ","
            end
            if inner then
                out[#out + 1] = "\n" .. inner
            end
            Write(out, items[i], inner)
        end
        out[#out + 1] = inner and ("\n" .. indent .. "]") or "]"
    else
        error("cannot write a " .. kind .. " as JSON", 0)
    end
end

-- pretty: indented, one value per line (for people to read).
function Json.Encode(value, pretty)
    local out = {}
    Write(out, value, pretty and "" or nil)
    return concat(out)
end

-- Code points to UTF-8, for tests and callers that build text.
function Json.Char(code)
    if code < 0x80 then
        return char(code)
    elseif code < 0x800 then
        return char(0xC0 + floor(code / 64), 0x80 + code % 64)
    elseif code < 0x10000 then
        return char(0xE0 + floor(code / 4096), 0x80 + floor(code / 64) % 64, 0x80 + code % 64)
    end
    return char(0xF0 + floor(code / 262144), 0x80 + floor(code / 4096) % 64, 0x80 + floor(code / 64) % 64, 0x80 + code % 64)
end
