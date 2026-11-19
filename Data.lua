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
--   settings = { locale, export },
--   own = { [GUID] = { sentFP, sentGuild } },
--   account = the WoW account's profile: { key, dc = Discord name, pt =
--       time of its last change, ch = { [GUID] = true for a main, false for
--       an alt } }, or { ch = {} } until the player gives a Discord name
--       (see Profile.lua),
-- }
--
-- Since 0.4.0 a record holds the character alone: name, realm, level, class,
-- race, sex and faction, and since 0.5.0 its WoW account's profile (the
-- player's Discord name, their mains and alts: Profile.lua). Professions, items worn and talents are shared by
-- the addons that own them (see Sources.lua). Records from earlier versions
-- still carry them; they are dropped when read.
local _, ns = ...
local Lib = LibGuildSync
local Data = ns.Data

-- How complete a copy is. Versions before 0.4 counted professions, recipes,
-- and items and talents known; the sync sends as many numbers as there are
-- stats, so there are still three, always 0 now that records carry none of
-- those.
Data.STATS = 3

local IsCount = Lib.IsCount

-- Checks -------------------------------------------------------------------

-- A checked copy of a record, or nil when it cannot be trusted. now is given
-- for records from other clients, which may not be dated in the future.
function Data.CleanRecord(record, now)
    local clean = Data.CleanBase(record, now)
    if not clean then
        return nil
    end
    clean.c = IsCount(record.c, 1000) and record.c or 0
    clean.r = IsCount(record.r, 1000) and record.r or 0
    clean.sx = IsCount(record.sx, 3) and record.sx or 0
    clean.f = IsCount(record.f, 3) and record.f or 0
    clean.l = IsCount(record.l, 1000) and record.l or 0
    -- The account's profile (Profile.lua), whole or not at all; one dated
    -- in the future would win over every later change.
    local key, discord = ns.Profile.CleanKey(record.ak), ns.Profile.CleanDiscord(record.dc)
    local ch = ns.Profile.CleanCharacters(record.ch, ns.Pack.LIMITS.profile)
    if key and discord and ch and Lib.IsTime(record.pt) and not (now and record.pt > now + 300) then
        clean.ak, clean.dc, clean.pt, clean.ch = key, discord, record.pt, ch
    end
    return clean
end

function Data.Stats()
    return 0, 0, 0
end

-- The saved database -----------------------------------------------------------

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
-- guild's roster. (Versions before 0.4 also kept a catalog of every recipe
-- of each profession, which is dropped.)
function Data.SanitizeExtra(clean, db)
    for guildKey, cleanGuild in pairs(clean.guilds) do
        local roster = type(db.guilds) == "table" and type(db.guilds[guildKey]) == "table" and db.guilds[guildKey].roster
        if type(roster) == "table" and type(roster.t) == "number" and type(roster.m) == "table" then
            cleanGuild.roster = { t = roster.t, m = {} }
            for guid, entry in pairs(roster.m) do
                cleanGuild.roster.m[guid] = Data.IsGUID(guid) and CleanRosterEntry(entry) or nil
            end
        end
    end
    for _, state in pairs(clean.own) do
        state.hinted = nil
    end
    -- The WoW account's profile (Profile.lua), whole or empty.
    local account = type(db.account) == "table" and db.account or {}
    local key, discord = ns.Profile.CleanKey(account.key), ns.Profile.CleanDiscord(account.dc)
    local ch = ns.Profile.CleanCharacters(account.ch, ns.Pack.LIMITS.profile)
    if key and discord and ch and Lib.IsTime(account.pt) then
        clean.account = { key = key, dc = discord, pt = account.pt, ch = ch }
    else
        clean.account = { ch = {} }
    end
end

-- After a complete roster read, the roster is kept for the bot's file: it is
-- the only source for members who do not run the addon.
function Data.OnPrune(guild, present, now)
    guild.roster = { t = now, m = present }
end

-- Professions from Guild Professions & Recipes --------------------------------

-- The professions of a record of Guild Professions & Recipes ({ [skillLine]
-- = { r = rank, m = max rank, o = order, lk = the profession's spell, k =
-- recipe IDs, false without recipes, nil not read yet } }) as a list ordered
-- like the character sheet: { sl = skillLine, r, m, o, lk, k }. Anything
-- unexpected is left out.
function Data.SortedProfessions(professions)
    local list = {}
    if type(professions) == "table" then
        for skillLine, prof in pairs(professions) do
            if Lib.IsID(skillLine) and type(prof) == "table" and IsCount(prof.r, 100000) and IsCount(prof.m, 100000) then
                local k = prof.k
                if k ~= false and type(k) ~= "table" then
                    k = nil
                end
                list[#list + 1] = {
                    sl = skillLine, r = prof.r, m = prof.m, o = IsCount(prof.o, 1000) and prof.o or 0,
                    lk = Lib.IsID(prof.lk) and prof.lk or nil, k = k,
                }
            end
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
