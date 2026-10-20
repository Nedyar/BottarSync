-- Data.lua: the saved database and the rules that merge what different
-- clients know into one view.
--
-- BottarSyncDB = {
--   schema = 1,
--   guilds = { ["Guild Name"] = {
--       seen = time,
--       members = { ["Player-1234-0ABCDEF0"] = record (see Pack.lua; on disk
--           it is packed, see Data.PackForSave) plus two local fields:
--               seen = last time the member was in the roster,
--               fh = true when the copy came from the member themselves },
--       roster = { t = time of the last complete read, m = { [GUID] = roster
--           entry (see Roster.lua) } } } },
--   cache = { catalog = { [skillLine] = every recipe ID of the profession } },
--   settings = { locale, export },
--   own = { [GUID] = { sentFP, sentGuild, hinted = { [skillLine] = true } } },
-- }
--
-- Members are known by GUID: WoW Forever names have spaces, the guild roster
-- gives them without a realm, and members of one guild live on different
-- realms. Guilds are known by name alone, because the realm the client gives
-- for a guild changes while the login loads.
--
-- Only a record's owner ever changes its contents, and the owner stamps each
-- change with a time (t) that always grows. Every client therefore keeps,
-- for each member, the copy that is newest (then the most complete), and
-- all clients end up with the same one.
local _, ns = ...
local Pack = ns.Pack

local Data = {}
ns.Data = Data

Data.SCHEMA = 1
Data.BUCKETS = 16

local DAY = 86400
local MEMBER_TTL = 30 * DAY   -- members unseen in the roster this long are dropped
local GUILD_TTL = 180 * DAY   -- guilds not visited this long are dropped
local MIN_TIME = 1600000000   -- September 2020: older times are bogus
local FUTURE_SLACK = 300      -- how far a record's time may run ahead of ours
local MAX_CATALOG = 5000      -- recipes of one profession, learned or not
local LIMITS = Pack.LIMITS

local floor = math.floor

-- Checks -------------------------------------------------------------------

local function IsCount(value, max)
    return type(value) == "number" and value >= 0 and value <= max and value == floor(value)
end

local function IsID(value)
    return type(value) == "number" and value > 0 and value < 2147483648 and value == floor(value)
end

local function IsInt(value, max)
    return type(value) == "number" and value == floor(value) and value >= -max and value <= max
end

function Data.IsGUID(guid)
    return type(guid) == "string" and #guid <= LIMITS.text and guid:find("^Player%-%d+%-%x+$") ~= nil
end

local function IsGuildKey(key)
    return type(key) == "string" and key ~= "" and #key <= LIMITS.text and not key:find("|", 1, true)
end

-- A name as given by another client, safe to show: no escape sequences.
function Data.CleanName(name)
    if type(name) ~= "string" then
        return nil
    end
    name = name:gsub("[|%c]", "")
    if name == "" or #name > LIMITS.text then
        return nil
    end
    return name
end

-- Records whose owner never stamped them are not shared or compared.
function Data.IsShareable(record)
    return record ~= nil and record.t >= MIN_TIME
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
    if type(record) ~= "table" then
        return nil
    end
    local t = record.t
    if type(t) ~= "number" or t ~= t or t < MIN_TIME or t >= 1e12 or (now and t > now + FUTURE_SLACK) then
        return nil
    end
    local professions = CleanProfessions(record.p)
    if not professions then
        return nil
    end
    local clean = {
        t = floor(t),
        av = IsCount(record.av, 999999) and record.av or 0,
        n = Data.CleanName(record.n),
        rl = Data.CleanName(record.rl),
        c = IsCount(record.c, 1000) and record.c or 0,
        r = IsCount(record.r, 1000) and record.r or 0,
        sx = IsCount(record.sx, 3) and record.sx or 0,
        f = IsCount(record.f, 3) and record.f or 0,
        l = IsCount(record.l, 1000) and record.l or 0,
        il = IsCount(record.il, 10000000) and record.il or nil,
        p = professions,
    }
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
    if type(record.seen) == "number" then
        clean.seen = record.seen
    end
    if record.fh == true then
        clean.fh = true
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

-- Positive when the first copy is the one to keep: the newer one, then the
-- more complete. Each side is t, lists, recipes, extras.
function Data.CompareStats(t1, lists1, recipes1, extras1, t2, lists2, recipes2, extras2)
    if t1 ~= t2 then
        return t1 > t2 and 1 or -1
    end
    if lists1 ~= lists2 then
        return lists1 > lists2 and 1 or -1
    end
    if recipes1 ~= recipes2 then
        return recipes1 > recipes2 and 1 or -1
    end
    if extras1 ~= extras2 then
        return extras1 > extras2 and 1 or -1
    end
    return 0
end

function Data.Compare(a, b)
    local lists1, recipes1, extras1 = Data.Stats(a)
    local lists2, recipes2, extras2 = Data.Stats(b)
    return Data.CompareStats(a.t, lists1, recipes1, extras1, b.t, lists2, recipes2, extras2)
end

-- The copy kept of a member takes what it lacks from the other copy: the
-- list of each profession whose recipes it does not know (k == nil), and
-- the items and talents. A character whose own data was lost shares its
-- levels again without wiping its recipes everywhere, whichever copy
-- arrives first. Returns true if it took any.
local function CarryMissing(kept, other)
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
    kept.n = kept.n or other.n
    kept.rl = kept.rl or other.rl
    return changed
end

-- Our own record is only ever changed by us, but if we lost a profession's
-- recipe list, a copy coming back from the guild fills it in.
local function AdoptOwnLists(own, record)
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

-- Stores a cleaned record. firsthand: it came from its owner, so it replaces
-- any older copy. Returns true when the stored data changed.
function Data.MergeRecord(guild, guid, record, firsthand)
    local old = guild.members[guid]
    if old and guid == ns.playerGUID then
        return AdoptOwnLists(old, record)
    end
    if old then
        local wins
        if firsthand then
            wins = record.t >= old.t
        else
            wins = Data.Compare(record, old) > 0
        end
        if not wins then
            return CarryMissing(old, record)
        end
        CarryMissing(record, old)
    end
    record.seen = math.max(record.seen or 0, old and old.seen or 0, ns.Now())
    record.fh = firsthand or nil
    guild.members[guid] = record
    return true
end

-- The guild database ----------------------------------------------------------

local function NewDB()
    return { schema = Data.SCHEMA, guilds = {}, cache = { catalog = {} }, settings = {}, own = {} }
end

-- Keeps the better of two copies of a member (both cleaned).
local function MergeCopies(members, guid, record)
    local old = members[guid]
    if not old or Data.Compare(record, old) > 0 then
        if old then
            CarryMissing(record, old)
            record.seen = math.max(record.seen or 0, old.seen or 0)
        end
        members[guid] = record
    else
        CarryMissing(old, record)
        old.seen = math.max(old.seen or 0, record.seen or 0)
    end
end

-- Records and catalogs are saved packed (see Data.PackForSave): the client
-- writes each number of a plain table on its own line, ten times the size.
local function UnpackRecord(saved)
    if type(saved) ~= "table" or type(saved.b) ~= "string" then
        return nil
    end
    local raw = Pack.FromBase64(saved.b)
    if not raw then
        return nil
    end
    local ok, guid, record = pcall(Pack.ReadRecord, Pack.Reader(raw))
    if not ok or type(record) ~= "table" then
        return nil
    end
    record.seen, record.fh = saved.seen, saved.fh
    return guid, record
end

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

-- A roster entry as Roster.lua makes it.
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

-- Checks a database read from disk and returns a clean copy.
function Data.Sanitize(db)
    local clean = NewDB()
    if type(db) ~= "table" then
        return clean
    end
    if type(db.guilds) == "table" then
        for guildKey, guild in pairs(db.guilds) do
            if IsGuildKey(guildKey) and type(guild) == "table" then
                local cleanGuild = { seen = type(guild.seen) == "number" and guild.seen or 0, members = {} }
                if type(guild.members) == "table" then
                    for key, saved in pairs(guild.members) do
                        local guid, record = UnpackRecord(saved)
                        local cleanRecord = guid == key and Data.IsGUID(guid) and Data.CleanRecord(record)
                        if cleanRecord then
                            MergeCopies(cleanGuild.members, guid, cleanRecord)
                        end
                    end
                end
                local roster = guild.roster
                if type(roster) == "table" and type(roster.t) == "number" and type(roster.m) == "table" then
                    cleanGuild.roster = { t = roster.t, m = {} }
                    for guid, entry in pairs(roster.m) do
                        cleanGuild.roster.m[guid] = Data.IsGUID(guid) and CleanRosterEntry(entry) or nil
                    end
                end
                clean.guilds[guildKey] = cleanGuild
            end
        end
    end
    local cache = type(db.cache) == "table" and db.cache or {}
    if type(cache.catalog) == "table" then
        for skillLine, list in pairs(cache.catalog) do
            clean.cache.catalog[skillLine] = IsID(skillLine) and CleanList(UnpackList(list), MAX_CATALOG) or nil
        end
    end
    if type(db.settings) == "table" then
        clean.settings = db.settings
    end
    if type(db.own) == "table" then
        for guid, state in pairs(db.own) do
            if Data.IsGUID(guid) and type(state) == "table" then
                clean.own[guid] = state
                if type(state.hinted) ~= "table" then
                    state.hinted = {}
                end
            end
        end
    end
    return clean
end

-- Runs at ADDON_LOADED, once the client has loaded the saved variables.
function Data.Load()
    local native = BottarSyncDB
    ns.loadInfo = { native = type(native) == "table" }
    local db = Data.Sanitize(native)
    BottarSyncDB = db
    ns.db = db
end

-- Runs at logout, right before the client writes the saved variables.
function Data.PackForSave(db)
    for _, guild in pairs(db.guilds) do
        for guid, record in pairs(guild.members) do
            if record.b == nil then
                guild.members[guid] = { b = Pack.ToBase64(Pack.RecordString(guid, record)), seen = record.seen, fh = record.fh }
            end
        end
    end
    for skillLine, list in pairs(db.cache.catalog) do
        if type(list) == "table" then
            db.cache.catalog[skillLine] = PackList(list)
        end
    end
end

function Data.GetGuild(guildKey, create)
    if not guildKey then
        return nil
    end
    local guild = ns.db.guilds[guildKey]
    if not guild and create then
        guild = { seen = ns.Now(), members = {} }
        ns.db.guilds[guildKey] = guild
    end
    return guild
end

function Data.CurrentGuild(create)
    return Data.GetGuild(ns.Roster.guildKey, create)
end

function Data.ResetGuild(guildKey)
    local guild = Data.GetGuild(guildKey)
    if not guild then
        return
    end
    -- Our own record stays: its recipe lists can only be read again by
    -- opening each profession.
    local own = ns.playerGUID and guild.members[ns.playerGUID]
    wipe(guild.members)
    if own then
        guild.members[ns.playerGUID] = own
    end
    Data.Changed(guild)
end

-- Lookups that are rebuilt whenever the data changes (never saved).
local digestCache = setmetatable({}, { __mode = "k" })

-- Every change to a guild's data ends here.
function Data.Changed(guild)
    if guild then
        digestCache[guild] = nil
    end
    ns.Debounce("DataChanged", 0.2, function()
        ns.Fire("DataChanged")
    end)
end

function Data.ForgetDigests()
    wipe(digestCache)
end

-- A record received from another client. firsthand: sent by its owner.
function Data.Accept(guildKey, guid, record, firsthand)
    if not Data.IsGUID(guid) then
        return false
    end
    record = Data.CleanRecord(record, ns.Now())
    if not record then
        ns.Debug("rejected the record of %s", guid)
        return false
    end
    local guild = Data.GetGuild(guildKey, true)
    local changed = Data.MergeRecord(guild, guid, record, firsthand)
    if changed then
        Data.Changed(guild)
        ns.Fire("RecordChanged", guid, guild.members[guid])
        if guid == ns.playerGUID then
            ns.Fire("OwnChanged")
        end
    end
    return changed
end

-- Finds a member by what the user typed ("Name", "name", "Name-Realm"):
-- the roster's names first, then the names members shared. Returns the GUID.
function Data.FindByName(guild, text)
    local wanted = strtrim(text):match("^([^%-]+)") or text
    wanted = strtrim(wanted):lower()
    for guid, member in pairs(ns.Roster.members) do
        if member.n and member.n:lower() == wanted then
            return guid
        end
    end
    for guid, record in pairs(guild and guild.members or {}) do
        if record.n and record.n:lower() == wanted then
            return guid
        end
    end
end

-- After a complete roster read: the roster is kept for the bot's file,
-- members present are marked as seen, members gone for a month are
-- dropped, and so are guilds unvisited for half a year.
function Data.Prune(guildKey, present)
    local guild = Data.GetGuild(guildKey, true)
    local now = ns.Now()
    local changed = false
    guild.seen = now
    guild.roster = { t = now, m = present }
    for guid, record in pairs(guild.members) do
        if present[guid] then
            record.seen = now
        elseif (record.seen or record.t) < now - MEMBER_TTL then
            guild.members[guid] = nil
            changed = true
        end
    end
    for otherKey, other in pairs(ns.db.guilds) do
        if otherKey ~= guildKey and other.seen < now - GUILD_TTL then
            ns.db.guilds[otherKey] = nil
        end
    end
    if changed then
        Data.Changed(guild)
    end
end

-- Our own record ----------------------------------------------------------------

local function CopyProfessions(professions)
    local copy = {}
    for skillLine, prof in pairs(professions) do
        copy[skillLine] = { r = prof.r, m = prof.m, o = prof.o, lk = prof.lk, k = prof.k }
    end
    return copy
end

-- The current character's record in the current guild. create: make it when
-- missing, starting from the copy kept in another guild, if any.
function Data.GetOwnRecord(create)
    local guild = Data.CurrentGuild(create)
    if not guild or not ns.playerGUID then
        return nil
    end
    local record = guild.members[ns.playerGUID]
    if not record and create then
        local best
        for _, other in pairs(ns.db.guilds) do
            local copy = other.members[ns.playerGUID]
            if copy and (not best or copy.t > best.t) then
                best = copy
            end
        end
        record = { t = 0, p = best and CopyProfessions(best.p) or {}, g = best and best.g, tl = best and best.tl }
        guild.members[ns.playerGUID] = record
    end
    return record
end

-- Stamps a change to our own record.
function Data.TouchOwn(record)
    local now = ns.Now()
    record.t = math.max(now, (record.t or 0) + 1)
    record.av = ns.VERSION_NUM
    record.n = Data.CleanName(ns.playerName) or record.n
    record.rl = Data.CleanName(ns.realm) or record.rl
    record.fh = true
    record.seen = now
    local guild = Data.CurrentGuild()
    Data.Changed(guild)
    ns.Fire("RecordChanged", ns.playerGUID, record)
    ns.Fire("OwnChanged")
end

function Data.OwnState()
    local state = ns.db.own[ns.playerGUID]
    if not state then
        state = { hinted = {} }
        ns.db.own[ns.playerGUID] = state
    end
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

-- Sync helpers ----------------------------------------------------------------

function Data.BucketOf(guid)
    return Pack.Hash(guid) % Data.BUCKETS + 1
end

-- Identifies one version of a member's record.
function Data.VersionHash(guid, t, lists, recipes, extras)
    return Pack.Hash(guid .. "|" .. t .. "|" .. lists .. "|" .. recipes .. "|" .. extras)
end

function Data.Fingerprint(guid, record)
    return Pack.Hash(Pack.RecordString(guid, record))
end

-- The records worth comparing with other clients: shareable ones of members
-- who are still in the guild.
function Data.ForEachShared(guild, callback)
    for guid, record in pairs(guild.members) do
        if Data.IsShareable(record) and ns.Roster.IsKnownGUID(guid) then
            callback(guid, record)
        end
    end
end

-- One number per bucket summing up the versions of the records in it. Two
-- clients with the same digests hold the same data.
function Data.Digests(guild)
    local cached = digestCache[guild]
    if cached then
        return cached.digests, cached.count
    end
    local digests, count = {}, 0
    for i = 1, Data.BUCKETS do
        digests[i] = 0
    end
    Data.ForEachShared(guild, function(guid, record)
        local bucket = Data.BucketOf(guid)
        digests[bucket] = Pack.AddHash(digests[bucket], Data.VersionHash(guid, record.t, Data.Stats(record)))
        count = count + 1
    end)
    digestCache[guild] = { digests = digests, count = count }
    return digests, count
end
