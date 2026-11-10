-- Pack.lua: the packed form of Bot'tar Sync's records (LibGuildSync's
-- Pack.lua has the numbers, texts, lists, Base64 and hashing they are made
-- of). Plain Lua with no game API, so it can be tested outside the game.
local _, ns = ...

local Pack = ns.Pack

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
            prof.k = Pack.ReadList(reader, LIMITS.recipes)
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
