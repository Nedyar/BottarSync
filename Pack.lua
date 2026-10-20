-- Pack.lua: the compact binary form records travel in, Base64, and hashing.
-- Plain Lua with no game API, so it can be tested outside the game.
local _, ns = ...

local Pack = {}
ns.Pack = Pack

local byte, char, floor, sub = string.byte, string.char, math.floor, string.sub
local concat = table.concat

-- The most a record may hold. Anything bigger is refused when read.
Pack.LIMITS = {
    professions = 10,
    recipes = 1500,
    rank = 1000,
    text = 64,
    item = 255,      -- length of an item string
    slots = 20,
    specs = 4,
    tabs = 6,
    talents = 150,   -- learned talents of one spec
    coordinate = 1000000,
}

local TWO_32 = 4294967296
local TWO_53 = 9007199254740992

-- Writer ---------------------------------------------------------------------

local Writer = {}
Writer.__index = Writer

function Pack.Writer()
    return setmetatable({ n = 0 }, Writer)
end

function Writer:Byte(value)
    self.n = self.n + 1
    self[self.n] = char(value)
end

-- Unsigned integers take 7 bits per byte (LEB128): 1 byte below 128,
-- 3 bytes for recipe IDs above a million.
function Writer:UInt(value)
    value = floor(value)
    if value < 0 or value >= TWO_53 then
        error("number out of range: " .. tostring(value), 2)
    end
    while value >= 128 do
        self:Byte(value % 128 + 128)
        value = floor(value / 128)
    end
    self:Byte(value)
end

-- Signed integers: 0, -1, 1, -2... become 0, 1, 2, 3...
function Writer:Int(value)
    value = floor(value)
    self:UInt(value >= 0 and value * 2 or -value * 2 - 1)
end

function Writer:Str(text)
    self:UInt(#text)
    self:Raw(text)
end

-- Appends bytes that are already packed.
function Writer:Raw(text)
    self.n = self.n + 1
    self[self.n] = text
end

function Writer:Size()
    local size = 0
    for i = 1, self.n do
        size = size + #self[i]
    end
    return size
end

function Writer:Result()
    return concat(self, "", 1, self.n)
end

-- Reader ---------------------------------------------------------------------

-- Every read raises on malformed input; callers read under pcall.
local Reader = {}
Reader.__index = Reader

function Pack.Reader(text)
    return setmetatable({ s = text, pos = 1, len = #text }, Reader)
end

function Reader:Byte()
    local value = byte(self.s, self.pos)
    if not value or self.pos > self.len then
        error("truncated message", 0)
    end
    self.pos = self.pos + 1
    return value
end

function Reader:UInt()
    local value, scale = 0, 1
    for _ = 1, 8 do
        local b = self:Byte()
        if b < 128 then
            return value + b * scale
        end
        value = value + (b - 128) * scale
        scale = scale * 128
    end
    error("malformed number", 0)
end

function Reader:Int()
    local value = self:UInt()
    if value % 2 == 0 then
        return value / 2
    end
    return -(value + 1) / 2
end

function Reader:Str(maxLength)
    local length = self:UInt()
    if length > (maxLength or Pack.LIMITS.text) then
        error("text too long", 0)
    end
    if self.pos + length - 1 > self.len then
        error("truncated message", 0)
    end
    local text = sub(self.s, self.pos, self.pos + length - 1)
    self.pos = self.pos + length
    return text
end

-- A reader over the next length bytes, which this reader skips.
function Reader:Sub(length)
    if self.pos + length - 1 > self.len then
        error("truncated message", 0)
    end
    local inner = Pack.Reader(sub(self.s, self.pos, self.pos + length - 1))
    self.pos = self.pos + length
    return inner
end

function Reader:AtEnd()
    return self.pos > self.len
end

-- Recipe lists ---------------------------------------------------------------

-- A sorted list of distinct recipe IDs, stored as the gaps between them:
-- most gaps fit in one byte even where the IDs themselves need three.
function Pack.WriteList(writer, list)
    writer:UInt(#list)
    local previous = 0
    for i = 1, #list do
        writer:UInt(list[i] - previous)
        previous = list[i]
    end
end

function Pack.ReadList(reader, max)
    local count = reader:UInt()
    if count > (max or Pack.LIMITS.recipes) then
        error("too many recipes", 0)
    end
    local list, previous = {}, 0
    for i = 1, count do
        local gap = reader:UInt()
        if gap == 0 then
            error("recipe list not sorted", 0)
        end
        previous = previous + gap
        list[i] = previous
    end
    return list
end

-- Records --------------------------------------------------------------------

-- A record is what one character shares about itself, under its GUID:
--   n = name, rl = realm, t = time of its last change, av = addon version,
--   c = class ID, r = race ID, sx = sex (2 male, 3 female), f = faction
--   (1 Alliance, 2 Horde, 3 neutral), l = level, il = average item level
--   of the equipped items in hundredths,
--   p = professions: { [skillLineID] = { r = rank, m = max rank,
--       o = display order, lk = the profession's spell, k = recipes } },
--       k being a sorted list of recipe IDs, false for professions without
--       recipes, or nil while they have not been read,
--   g = equipped items, nil until read: list of { s = slot, i = item string,
--       il = item level }, by slot,
--   tl = talents, nil until read: { tr = tree ID, ag = active spec group,
--       ng = spec groups, un = unspent points, s = list of specs:
--       { gr = spec group, tb = tabs { { g = group ID, n = name,
--       sp = points spent } }, t = learned talents { nd = node ID,
--       sp = spell ID, r = rank, m = max rank, tb = tab, rw = row,
--       cl = column, x, y = position in the tree } } }.
-- A packed record is prefixed by its length, so fields added later are
-- skipped by older readers.
local K_UNKNOWN, K_NONE, K_LIST = 0, 1, 2
local ABSENT, PRESENT = 0, 1

local LIMITS = Pack.LIMITS

local function SortedKeys(map)
    local keys = {}
    for key in pairs(map) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

local function WriteProfessions(writer, professions)
    local skillLines = SortedKeys(professions)
    writer:UInt(#skillLines)
    for _, skillLine in ipairs(skillLines) do
        local prof = professions[skillLine]
        writer:UInt(skillLine)
        writer:UInt(prof.r)
        writer:UInt(prof.m)
        writer:UInt(prof.o or 0)
        writer:UInt(prof.lk or 0)
        if prof.k == nil then
            writer:Byte(K_UNKNOWN)
        elseif prof.k == false then
            writer:Byte(K_NONE)
        else
            writer:Byte(K_LIST)
            Pack.WriteList(writer, prof.k)
        end
    end
end

local function ReadProfessions(reader)
    local count = reader:UInt()
    if count > LIMITS.professions then
        error("too many professions", 0)
    end
    local professions = {}
    for _ = 1, count do
        local skillLine = reader:UInt()
        local prof = { r = reader:UInt(), m = reader:UInt(), o = reader:UInt(), lk = reader:UInt() }
        if prof.lk == 0 then
            prof.lk = nil
        end
        local state = reader:Byte()
        if state == K_NONE then
            prof.k = false
        elseif state == K_LIST then
            prof.k = Pack.ReadList(reader)
        elseif state ~= K_UNKNOWN then
            error("bad recipe state", 0)
        end
        professions[skillLine] = prof
    end
    return professions
end

local function WriteGear(writer, gear)
    if not gear then
        writer:Byte(ABSENT)
        return
    end
    writer:Byte(PRESENT)
    writer:UInt(#gear)
    for _, item in ipairs(gear) do
        writer:UInt(item.s)
        writer:Str(item.i)
        writer:UInt(item.il or 0)
    end
end

local function ReadGear(reader)
    if reader:Byte() == ABSENT then
        return nil
    end
    local count = reader:UInt()
    if count > LIMITS.slots then
        error("too many items", 0)
    end
    local gear = {}
    for i = 1, count do
        gear[i] = { s = reader:UInt(), i = reader:Str(LIMITS.item), il = reader:UInt() }
    end
    return gear
end

local function WriteTalents(writer, talents)
    if not talents then
        writer:Byte(ABSENT)
        return
    end
    writer:Byte(PRESENT)
    writer:UInt(talents.tr or 0)
    writer:UInt(talents.ag or 0)
    writer:UInt(talents.ng or 0)
    writer:UInt(talents.un or 0)
    writer:UInt(#talents.s)
    for _, spec in ipairs(talents.s) do
        writer:UInt(spec.gr)
        writer:UInt(#spec.tb)
        for _, tab in ipairs(spec.tb) do
            writer:UInt(tab.g or 0)
            writer:Str(tab.n or "")
            writer:UInt(tab.sp or 0)
        end
        writer:UInt(#spec.t)
        for _, talent in ipairs(spec.t) do
            writer:UInt(talent.nd)
            writer:UInt(talent.sp or 0)
            writer:UInt(talent.r)
            writer:UInt(talent.m)
            writer:UInt(talent.tb or 0)
            writer:UInt(talent.rw or 0)
            writer:UInt(talent.cl or 0)
            writer:Int(talent.x or 0)
            writer:Int(talent.y or 0)
        end
    end
end

local function ReadTalents(reader)
    if reader:Byte() == ABSENT then
        return nil
    end
    local talents = { tr = reader:UInt(), ag = reader:UInt(), ng = reader:UInt(), un = reader:UInt(), s = {} }
    local specs = reader:UInt()
    if specs > LIMITS.specs then
        error("too many specs", 0)
    end
    for i = 1, specs do
        local spec = { gr = reader:UInt(), tb = {}, t = {} }
        local tabs = reader:UInt()
        if tabs > LIMITS.tabs then
            error("too many tabs", 0)
        end
        for j = 1, tabs do
            spec.tb[j] = { g = reader:UInt(), n = reader:Str(), sp = reader:UInt() }
        end
        local count = reader:UInt()
        if count > LIMITS.talents then
            error("too many talents", 0)
        end
        for j = 1, count do
            spec.t[j] = {
                nd = reader:UInt(), sp = reader:UInt(), r = reader:UInt(), m = reader:UInt(),
                tb = reader:UInt(), rw = reader:UInt(), cl = reader:UInt(), x = reader:Int(), y = reader:Int(),
            }
        end
        talents.s[i] = spec
    end
    return talents
end

-- The record's own bytes, without the length prefix.
local function RecordBody(guid, record)
    local writer = Pack.Writer()
    writer:Str(guid)
    writer:Str(record.n or "")
    writer:UInt(record.t)
    writer:UInt(record.av or 0)
    writer:Str(record.rl or "")
    writer:UInt(record.c or 0)
    writer:UInt(record.r or 0)
    writer:UInt(record.sx or 0)
    writer:UInt(record.f or 0)
    writer:UInt(record.l or 0)
    -- 0 means unknown, so the item level is stored plus one.
    writer:UInt(record.il and record.il + 1 or 0)
    WriteProfessions(writer, record.p)
    WriteGear(writer, record.g)
    WriteTalents(writer, record.tl)
    return writer:Result()
end

function Pack.WriteRecord(writer, guid, record)
    writer:Str(RecordBody(guid, record))
end

local MAX_RECORD = 20000

-- Returns guid, record. The record still has to be checked (Data.CleanRecord).
function Pack.ReadRecord(reader)
    local length = reader:UInt()
    if length > MAX_RECORD then
        error("record too long", 0)
    end
    reader = reader:Sub(length)
    local guid = reader:Str()
    local name = reader:Str()
    local record = { t = reader:UInt(), av = reader:UInt() }
    local realm = reader:Str()
    record.n = name ~= "" and name or nil
    record.rl = realm ~= "" and realm or nil
    record.c, record.r, record.sx, record.f, record.l = reader:UInt(), reader:UInt(), reader:UInt(), reader:UInt(), reader:UInt()
    local itemLevel = reader:UInt()
    record.il = itemLevel > 0 and itemLevel - 1 or nil
    record.p = ReadProfessions(reader)
    record.g = ReadGear(reader)
    record.tl = ReadTalents(reader)
    -- Anything after this was added by a later version.
    return guid, record
end

function Pack.RecordString(key, record)
    local writer = Pack.Writer()
    Pack.WriteRecord(writer, key, record)
    return writer:Result()
end

-- Hashing --------------------------------------------------------------------

-- djb2, kept to 32 bits. Exact with Lua's doubles, so no bit library is needed.
function Pack.Hash(text, seed)
    local hash = seed or 5381
    for i = 1, #text do
        hash = (hash * 33 + byte(text, i)) % TWO_32
    end
    return hash
end

function Pack.AddHash(a, b)
    return (a + b) % TWO_32
end

-- Base64 ---------------------------------------------------------------------

-- The client's C_EncodingUtil does this natively; this version is the
-- fallback, and the digits are reused for the message headers.
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DIGIT, VALUE = {}, {}
for i = 1, 64 do
    local c = sub(ALPHABET, i, i)
    DIGIT[i - 1] = c
    VALUE[c] = i - 1
end

-- A single Base64 digit: 0..63 <-> one character.
function Pack.Digit(value)
    return DIGIT[value]
end

function Pack.DigitValue(c)
    return VALUE[c]
end

function Pack.ToBase64(text)
    local out = {}
    for i = 1, #text, 3 do
        local a, b, c = byte(text, i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        out[#out + 1] = DIGIT[floor(n / 262144)] .. DIGIT[floor(n / 4096) % 64]
            .. (b and DIGIT[floor(n / 64) % 64] or "=") .. (c and DIGIT[n % 64] or "=")
    end
    return concat(out)
end

function Pack.FromBase64(text)
    if #text % 4 ~= 0 then
        return nil
    end
    local out = {}
    for i = 1, #text, 4 do
        local c1, c2, c3, c4 = sub(text, i, i), sub(text, i + 1, i + 1), sub(text, i + 2, i + 2), sub(text, i + 3, i + 3)
        local v1, v2 = VALUE[c1], VALUE[c2]
        local v3, v4 = VALUE[c3], VALUE[c4]
        if not v1 or not v2 or (not v3 and c3 ~= "=") or (not v4 and c4 ~= "=") then
            return nil
        end
        -- Padding only at the very end, and "x=y" is never valid.
        if (not v4 and i + 3 < #text) or (not v3 and v4) then
            return nil
        end
        local n = v1 * 262144 + v2 * 4096 + (v3 or 0) * 64 + (v4 or 0)
        out[#out + 1] = char(floor(n / 65536))
        if v3 then
            out[#out + 1] = char(floor(n / 256) % 256)
        end
        if v4 then
            out[#out + 1] = char(n % 256)
        end
    end
    return concat(out)
end
