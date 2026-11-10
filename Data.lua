-- Data.lua: what Bot'tar Sync adds to its database (LibGuildSync's Store.lua
-- keeps the database, merges the copies and works out the digests).
--
-- BottarSyncDB = {
--   schema = 1,
--   guilds = { ["Guild Name"] = {
--       seen = time,
--       members = { [GUID] = record (see Pack.lua) plus seen and fh },
--       roster = { t = time of the last complete read, m = { [GUID] = roster
--           entry (see LibGuildSync's Roster.lua) } } } },
--   cache = { catalog = { [skillLine] = every recipe ID of the profession } },
--   settings = { locale, export },
--   own = { [GUID] = { sentFP, sentGuild, hinted = { [skillLine] = true } } },
-- }
local _, ns = ...
local Lib = LibGuildSync
local Pack = ns.Pack
local Data = ns.Data

-- How complete a copy is: professions with a recipe list, recipes in all,
-- and whether its items and talents are known (see Data.Stats).
Data.STATS = 3

local MAX_CATALOG = 5000      -- recipes of one profession, learned or not
local LIMITS = Pack.LIMITS

local floor = math.floor
local IsCount, IsID = Lib.IsCount, Lib.IsID

-- Checks -------------------------------------------------------------------

local function IsInt(value, max)
    return type(value) == "number" and value == floor(value) and value >= -max and value <= max
end

-- Sorted, distinct recipe IDs; nil when the list is unusable.
local function CleanList(list, max)
    if type(list) ~= "table" then
        return nil
    end
    local ids, seen = {}, {}
    for _, id in pairs(list) do
        if not IsID(id) then
            return nil
        end
        if not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    if #ids > (max or LIMITS.recipes) then
        return nil
    end
    table.sort(ids)
    return ids
end

local function CleanProfessions(professions)
    if type(professions) ~= "table" then
        return nil
    end
    local clean, count = {}, 0
    for skillLine, prof in pairs(professions) do
        if not IsID(skillLine) or type(prof) ~= "table" or not IsCount(prof.r, LIMITS.rank) or not IsCount(prof.m, LIMITS.rank) then
            return nil
        end
        local cleanProf = { r = prof.r, m = prof.m, o = IsCount(prof.o, 50) and prof.o or 0 }
        if IsID(prof.lk) then
            cleanProf.lk = prof.lk
        end
        if prof.k == false then
            cleanProf.k = false
        elseif prof.k ~= nil then
            cleanProf.k = CleanList(prof.k)
            if not cleanProf.k then
                return nil
            end
        end
        clean[skillLine] = cleanProf
        count = count + 1
        if count > LIMITS.professions then
            return nil
        end
    end
    return clean
end

-- An item string as the addon shares it (see Character.ItemString): "item:",
-- the item ID, then letters, digits, colons or dashes, nothing that could
-- be a link or an escape sequence.
local function IsItemString(text)
    return type(text) == "string" and #text <= LIMITS.item and text:find("^item:%d+[%w:%-]*$") ~= nil
end

-- Equipped items: a list by slot, or nil when unusable.
local function CleanGear(gear)
    if type(gear) ~= "table" or #gear > LIMITS.slots then
        return nil
    end
    local clean, seen = {}, {}
    for _, item in ipairs(gear) do
        if type(item) ~= "table" or not IsCount(item.s, 30) or seen[item.s] or not IsItemString(item.i) then
            return nil
        end
        seen[item.s] = true
        clean[#clean + 1] = { s = item.s, i = item.i, il = IsCount(item.il, 10000) and item.il or 0 }
    end
    table.sort(clean, function(a, b)
        return a.s < b.s
    end)
    return clean
end

local function CleanTalents(talents)
    if type(talents) ~= "table" or type(talents.s) ~= "table" or #talents.s > LIMITS.specs then
        return nil
    end
    local clean = {
        tr = IsCount(talents.tr, 2147483647) and talents.tr or 0,
        ag = IsCount(talents.ag, 10) and talents.ag or 0,
        ng = IsCount(talents.ng, 10) and talents.ng or 0,
        un = IsCount(talents.un, LIMITS.rank) and talents.un or 0,
        s = {},
    }
    for _, spec in ipairs(talents.s) do
        if type(spec) ~= "table" or not IsCount(spec.gr, 10) or type(spec.tb) ~= "table" or type(spec.t) ~= "table"
            or #spec.tb > LIMITS.tabs or #spec.t > LIMITS.talents then
            return nil
        end
        local cleanSpec = { gr = spec.gr, tb = {}, t = {} }
        for _, tab in ipairs(spec.tb) do
            if type(tab) ~= "table" then
                return nil
            end
            cleanSpec.tb[#cleanSpec.tb + 1] = {
                g = IsCount(tab.g, 2147483647) and tab.g or 0,
                n = Data.CleanName(tab.n),
                sp = IsCount(tab.sp, LIMITS.rank) and tab.sp or 0,
            }
        end
        for _, talent in ipairs(spec.t) do
            if type(talent) ~= "table" or not IsID(talent.nd) or not IsCount(talent.r, 100) or not IsCount(talent.m, 100) then
                return nil
            end
            cleanSpec.t[#cleanSpec.t + 1] = {
                nd = talent.nd,
                sp = IsID(talent.sp) and talent.sp or 0,
                r = talent.r,
                m = talent.m,
                tb = IsCount(talent.tb, LIMITS.tabs) and talent.tb or 0,
                rw = IsCount(talent.rw, 100) and talent.rw or 0,
                cl = IsCount(talent.cl, 100) and talent.cl or 0,
                x = IsInt(talent.x, LIMITS.coordinate) and talent.x or 0,
                y = IsInt(talent.y, LIMITS.coordinate) and talent.y or 0,
            }
        end
        clean.s[#clean.s + 1] = cleanSpec
    end
    return clean
end

-- A checked copy of a record, or nil when it cannot be trusted. now is given
-- for records from other clients, which may not be dated in the future.
function Data.CleanRecord(record, now)
    local clean = Data.CleanBase(record, now)
    if not clean then
        return nil
    end
    clean.p = CleanProfessions(record.p)
    if not clean.p then
        return nil
    end
    clean.c = IsCount(record.c, 1000) and record.c or 0
    clean.r = IsCount(record.r, 1000) and record.r or 0
    clean.sx = IsCount(record.sx, 3) and record.sx or 0
    clean.f = IsCount(record.f, 3) and record.f or 0
    clean.l = IsCount(record.l, 1000) and record.l or 0
    clean.il = IsCount(record.il, 10000000) and record.il or nil
    if record.g ~= nil then
        clean.g = CleanGear(record.g)
        if not clean.g then
            return nil
        end
    end
    if record.tl ~= nil then
        clean.tl = CleanTalents(record.tl)
        if not clean.tl then
            return nil
        end
    end
    return clean
end

-- Comparing and merging --------------------------------------------------------

-- How complete a record is: professions with a recipe list, recipes in all,
-- and whether its items and talents are known (1 each).
function Data.Stats(record)
    local lists, recipes = 0, 0
    for _, prof in pairs(record.p) do
        if type(prof.k) == "table" then
            lists = lists + 1
            recipes = recipes + #prof.k
        end
    end
    local extras = (record.g and 1 or 0) + (record.tl and 1 or 0)
    return lists, recipes, extras
end

-- The copy kept of a member takes what it lacks from the other copy: the
-- list of each profession whose recipes it does not know (k == nil), and
-- the items and talents. A character whose own data was lost shares its
-- levels again without wiping its recipes everywhere, whichever copy
-- arrives first. Returns true if it took any.
function Data.CarryMissing(kept, other)
    local changed = false
    for skillLine, prof in pairs(kept.p) do
        local otherProf = other.p[skillLine]
        if prof.k == nil and otherProf and type(otherProf.k) == "table" then
            prof.k = otherProf.k
            changed = true
        end
    end
    if kept.g == nil and other.g ~= nil then
        kept.g = other.g
        changed = true
    end
    if kept.tl == nil and other.tl ~= nil then
        kept.tl = other.tl
        changed = true
    end
    return changed
end

-- Our own record is only ever changed by us, but if we lost a profession's
-- recipe list, a copy coming back from the guild fills it in.
function Data.AdoptOwn(own, record)
    local changed = false
    for skillLine, prof in pairs(own.p) do
        local theirs = record.p[skillLine]
        if prof.k == nil and theirs and type(theirs.k) == "table" then
            prof.k = theirs.k
            changed = true
        end
    end
    return changed
end

-- The saved database -----------------------------------------------------------

-- Catalogs are saved packed, like the records: the client writes each
-- number of a plain table on its own line, ten times the size.
local function PackList(list)
    local writer = Pack.Writer()
    Pack.WriteList(writer, list)
    return Pack.ToBase64(writer:Result())
end

local function UnpackList(text)
    local raw = type(text) == "string" and Pack.FromBase64(text)
    if not raw then
        return nil
    end
    local ok, list = pcall(Pack.ReadList, Pack.Reader(raw), MAX_CATALOG)
    return ok and list or nil
end

-- A roster entry as LibGuildSync's Roster.lua makes it.
local function CleanRosterEntry(entry)
    if type(entry) ~= "table" or type(entry.n) ~= "string" then
        return nil
    end
    return {
        n = entry.n,
        c = type(entry.c) == "string" and entry.c or nil,
        l = IsCount(entry.l, 1000) and entry.l or nil,
        rk = type(entry.rk) == "string" and entry.rk or nil,
        ri = IsCount(entry.ri, 100) and entry.ri or nil,
        nt = type(entry.nt) == "string" and entry.nt or nil,
        on = entry.on == true,
        lo = IsCount(entry.lo, 1e10) and entry.lo or nil,
    }
end

-- What the library leaves to us when the database is read from disk: each
-- guild's roster, the catalogs, and the professions we were told about.
function Data.SanitizeExtra(clean, db)
    clean.cache = { catalog = {} }
    for guildKey, cleanGuild in pairs(clean.guilds) do
        local roster = type(db.guilds) == "table" and type(db.guilds[guildKey]) == "table" and db.guilds[guildKey].roster
        if type(roster) == "table" and type(roster.t) == "number" and type(roster.m) == "table" then
            cleanGuild.roster = { t = roster.t, m = {} }
            for guid, entry in pairs(roster.m) do
                cleanGuild.roster.m[guid] = Data.IsGUID(guid) and CleanRosterEntry(entry) or nil
            end
        end
    end
    local cache = type(db.cache) == "table" and db.cache or {}
    if type(cache.catalog) == "table" then
        for skillLine, list in pairs(cache.catalog) do
            clean.cache.catalog[skillLine] = IsID(skillLine) and CleanList(UnpackList(list), MAX_CATALOG) or nil
        end
    end
    for _, state in pairs(clean.own) do
        if type(state.hinted) ~= "table" then
            state.hinted = {}
        end
    end
end

function Data.PackExtra(db)
    for skillLine, list in pairs(db.cache.catalog) do
        if type(list) == "table" then
            db.cache.catalog[skillLine] = PackList(list)
        end
    end
end

-- After a complete roster read, the roster is kept for the bot's file: it is
-- the only source for members who do not run the addon.
function Data.OnPrune(guild, present, now)
    guild.roster = { t = now, m = present }
end

-- Our own record ----------------------------------------------------------------

local function CopyProfessions(professions)
    local copy = {}
    for skillLine, prof in pairs(professions) do
        copy[skillLine] = { r = prof.r, m = prof.m, o = prof.o, lk = prof.lk, k = prof.k }
    end
    return copy
end

-- Our record in a guild where we have none yet starts from the copy kept in
-- another guild, if any.
function Data.NewOwnRecord()
    local best
    for _, other in pairs(ns.db.guilds) do
        local copy = other.members[ns.playerGUID]
        if copy and (not best or copy.t > best.t) then
            best = copy
        end
    end
    return { t = 0, p = best and CopyProfessions(best.p) or {}, g = best and best.g, tl = best and best.tl }
end

local LibOwnState = Data.OwnState
function Data.OwnState()
    local state = LibOwnState()
    state.hinted = state.hinted or {}
    return state
end

-- A record's professions as a list ordered like the character sheet:
-- { sl = skillLine, r, m, o, lk, k }.
function Data.SortedProfessions(record)
    local list = {}
    if record then
        for skillLine, prof in pairs(record.p) do
            list[#list + 1] = { sl = skillLine, r = prof.r, m = prof.m, o = prof.o, lk = prof.lk, k = prof.k }
        end
    end
    table.sort(list, function(a, b)
        if a.o ~= b.o then
            return a.o < b.o
        end
        return a.sl < b.sl
    end)
    return list
end

-- The list of every recipe of a profession, as seen in a profession window
-- by any character of this WoW account.
function Data.Catalog(skillLine)
    return ns.db.cache.catalog[skillLine]
end

function Data.SetCatalog(skillLine, ids)
    local list = CleanList(ids, MAX_CATALOG)
    if list and #list > 0 then
        ns.db.cache.catalog[skillLine] = list
    end
end
