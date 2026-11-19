-- Filters.lua: which guild members the Statistics window (Stats.lua) lists,
-- and the numbers it gives about them.
--
-- Each member of the guild roster is one of three kinds:
--   - a bank character: its rank is one of Guild Bank Alts' bank ranks (the
--     guild master's choice there), or "Banco" without that addon;
--   - an alt: its player did not tick it as a main (Profile.lua), also while
--     it is pending (added by a player, not accepted yet);
--   - a main: the others, members without Bot'tar Sync or without a Discord
--     username too.
-- Its class and level come from the guild roster, its specializations from
-- Guild Builds: the talent tree with the most points of each of its builds
-- (Primary and Secondary). A character whose two builds go into different
-- trees has both specializations; one without a build in Guild Builds has
-- none: it counts in no specialization, and a specialization's filter
-- leaves it out.
--
-- The window's kind cards choose one kind to list (every kind at first),
-- and its bars and level cards add a class, a specialization (of any class,
-- or of the class chosen) and a level range, while it is open. Each number
-- counts the members
-- that every other filter lets through, so it tells how many a click on it
-- lists. Offline members count while the game's roster shows them (its own
-- "Offline members" box).
--
-- The game's roster itself is never filtered: the game blocks changing a
-- member's notes or rank from a row of the roster that an addon's code drew
-- (as taking members out of its list makes the rows be drawn).
local _, ns = ...

local Filters = {}
ns.Filters = Filters

-- The level ranges, the last one for the highest level.
Filters.LEVELS = { { 1, 9 }, { 10, 19 }, { 20, 29 }, { 30, 39 }, { 40, 49 }, { 50, 59 }, { 60, 999 } }
-- Guild Bank Alts' bank rank until its guild master chooses others.
local BANK_RANK = "banco"
local BANKS = "GuildBankAlts"

-- The Statistics window's filters (nil: none).
Filters.kind = nil  -- "main", "alt" or "bank"
Filters.class = nil -- a class file ("HUNTER")
Filters.spec = nil  -- a specialization: { class = file, tab = its talent tree's tab (1 to 3) }
Filters.level = nil -- an index of Filters.LEVELS

local members       -- [GUID] = what the filters look at, until something changes
local trees = {}    -- [class file] = { tree = talent tree ID, tabs = Guild Builds' tb }

-- Members ---------------------------------------------------------------------------------

local function IsBank(guid, rosterEntry)
    local banks = ns.Sources.Find(BANKS)
    if banks and type(banks.Ranks) == "table" and banks.Ranks.IsBank then
        return ns.Try(banks.Ranks.IsBank, guid) == true
    end
    return type(rosterEntry.rk) == "string" and strtrim(rosterEntry.rk):lower() == BANK_RANK
end

-- The tab with the most points of a build's points per tab, as Guild Builds
-- shows it (nil without points).
local function MainTab(points)
    local best, most = nil, 0
    for i, value in ipairs(type(points) == "table" and points or {}) do
        if type(value) == "number" and value > most then
            best, most = i, value
        end
    end
    return best
end

local function Build()
    members = {}
    local guildKey = ns.Roster.guildKey
    if not guildKey then
        return
    end
    local guild = ns.Data.GetGuild(guildKey)
    local records = {}
    for guid, record in pairs(guild and guild.members or {}) do
        records[guid] = record
    end
    local who = ns.Profile.Resolve(records)
    local builds = ns.Sources.Records(ns.Sources.BUILDS, guildKey)
    for guid, rosterEntry in pairs(ns.Roster.members) do
        local entry = {
            guid = guid,
            name = rosterEntry.n,
            class = rosterEntry.c,
            level = tonumber(rosterEntry.l) or 0,
            online = rosterEntry.on == true,
            specs = {}, -- [tab] = { [spec group] = true }
        }
        local player = who[guid]
        -- Who plays it, for its tooltip in the roster (pending: a player
        -- added it, and it has not accepted yet; it counts as theirs).
        entry.dc = player and player.dc or nil
        entry.main = player and player.main or false
        entry.pending = player and player.pending or false
        if IsBank(guid, rosterEntry) then
            entry.kind = "bank"
        elseif player and not player.main then
            entry.kind = "alt"
        else
            entry.kind = "main"
        end
        local record = builds[guid]
        if type(record) == "table" and type(record.s) == "table" then
            for _, build in ipairs(record.s) do
                local tab = type(build) == "table" and MainTab(build.p)
                if tab then
                    local group = build.gr == 2 and 2 or 1
                    entry.specs[tab] = entry.specs[tab] or {}
                    entry.specs[tab][group] = true
                end
            end
            if entry.class and type(record.tb) == "table" and not trees[entry.class] then
                trees[entry.class] = { tree = record.tr, tabs = record.tb }
            end
        end
        members[guid] = entry
    end
end

-- What the filters know of a roster member, or nil.
function Filters.Member(guid)
    if not members then
        Build()
    end
    return guid and members[guid] or nil
end

-- Every roster member.
function Filters.Everyone()
    if not members then
        Build()
    end
    local list = {}
    for _, entry in pairs(members) do
        list[#list + 1] = entry
    end
    return list
end

-- The members the numbers count: the online ones, and the offline ones
-- while the roster shows them.
function Filters.Population()
    if not members then
        Build()
    end
    local offline = ns.Try(GetCVarBool, "communitiesShowOffline")
    local list = {}
    for _, entry in pairs(members) do
        if entry.online or offline ~= false then
            list[#list + 1] = entry
        end
    end
    return list
end

-- Forgets what it knew of the members (the roster, a profile, what the
-- officers set, a build or the bank ranks changed): the window shows it
-- again.
function Filters.Invalidate()
    members = nil
    ns.Debounce("Filters", 0.3, function()
        ns.Fire("FiltersChanged")
    end)
end

-- Filtering --------------------------------------------------------------------------------

function Filters.LevelIndex(level)
    for i, range in ipairs(Filters.LEVELS) do
        if level >= range[1] and level <= range[2] then
            return i
        end
    end
end

-- Whether a member passes every filter but skip's: "kind", "class" (also
-- skips the specialization, which belongs to the class), "spec" or "level".
function Filters.Passes(entry, skip)
    if skip ~= "kind" and Filters.kind and entry.kind ~= Filters.kind then
        return false
    end
    if skip ~= "class" then
        if Filters.class and entry.class ~= Filters.class then
            return false
        end
        local spec = Filters.spec
        if skip ~= "spec" and spec and (entry.class ~= spec.class or not entry.specs[spec.tab]) then
            return false
        end
    end
    if skip ~= "level" and Filters.level then
        local range = Filters.LEVELS[Filters.level]
        if entry.level < range[1] or entry.level > range[2] then
            return false
        end
    end
    return true
end

-- The members the window lists: those of the population that every filter
-- lets through, by name.
function Filters.Listed()
    local list = {}
    for _, entry in ipairs(Filters.Population()) do
        if Filters.Passes(entry) then
            list[#list + 1] = entry
        end
    end
    table.sort(list, function(a, b)
        local na, nb = (a.name or ""):lower(), (b.name or ""):lower()
        if na ~= nb then
            return na < nb
        end
        return a.guid < b.guid
    end)
    return list
end

-- The numbers ----------------------------------------------------------------------------

-- {
--   kinds = { main = n, alt = n, bank = n }, all = n,
--   classes = { { class = file, count = n } ... } (most first), classTotal = n,
--   specs = { [class file] = { [tab] = { count, primary, secondary } } }
--     (of every class, or of the class chosen; primary: the Primary build
--     is in it; secondary: only the Secondary one), specTotal = members
--     with a specialization (those without a build in Guild Builds count in
--     none), dual = those with two specializations (they count in both),
--   levels = { [range index] = n },
-- }
function Filters.Counts()
    local counts = {
        kinds = { main = 0, alt = 0, bank = 0 }, all = 0,
        classes = {}, classTotal = 0,
        specs = {}, specTotal = 0, dual = 0,
        levels = {},
    }
    for i = 1, #Filters.LEVELS do
        counts.levels[i] = 0
    end
    local byClass = {}
    for _, entry in ipairs(Filters.Population()) do
        if Filters.Passes(entry, "kind") then
            counts.kinds[entry.kind] = counts.kinds[entry.kind] + 1
            counts.all = counts.all + 1
        end
        if entry.class and Filters.Passes(entry, "class") then
            byClass[entry.class] = (byClass[entry.class] or 0) + 1
            counts.classTotal = counts.classTotal + 1
        end
        if entry.class and next(entry.specs) and Filters.Passes(entry, "spec") then
            counts.specTotal = counts.specTotal + 1
            local tabs = 0
            local ofClass = counts.specs[entry.class] or {}
            counts.specs[entry.class] = ofClass
            for tab, groups in pairs(entry.specs) do
                tabs = tabs + 1
                local spec = ofClass[tab] or { count = 0, primary = 0, secondary = 0 }
                ofClass[tab] = spec
                spec.count = spec.count + 1
                if groups[1] then
                    spec.primary = spec.primary + 1
                else
                    spec.secondary = spec.secondary + 1
                end
            end
            if tabs > 1 then
                counts.dual = counts.dual + 1
            end
        end
        local range = Filters.LevelIndex(entry.level)
        if range and Filters.Passes(entry, "level") then
            counts.levels[range] = counts.levels[range] + 1
        end
    end
    for class, count in pairs(byClass) do
        counts.classes[#counts.classes + 1] = { class = class, count = count }
    end
    table.sort(counts.classes, function(a, b)
        if a.count ~= b.count then
            return a.count > b.count
        end
        return a.class < b.class
    end)
    return counts
end

-- A specialization's name and icon (file ID), from a build of its class in
-- Guild Builds and the client's talent tree; nil when unknown.
function Filters.SpecInfo(class, tab)
    if not members then
        Build()
    end
    local known = trees[class]
    local info = known and type(known.tabs[tab]) == "table" and known.tabs[tab]
    if not info then
        return nil
    end
    local name
    local groups = C_Traits and known.tree and ns.Try(C_Traits.GetGroupDisplayInfoByTreeID, known.tree)
    for _, group in ipairs(ns.CanRead(groups) and groups or {}) do
        if ns.CanRead(group) and group.groupID == info.g then
            name = ns.Plain(group.displayName)
        end
    end
    local icon = type(info.i) == "number" and info.i > 0 and info.i or nil
    return name, icon
end

-- Changing them ---------------------------------------------------------------------------

local function Changed()
    ns.Fire("FiltersChanged")
end

-- A kind card of the window: only that kind, or every kind again when it
-- already was; "all": every kind.
function Filters.ToggleKind(kind)
    if kind == "all" or Filters.kind == kind then
        Filters.kind = nil
    else
        Filters.kind = kind
    end
    Changed()
end

-- A class: chosen, or no longer when it already was. A specialization
-- chosen stays only when it is of the class chosen now.
function Filters.ToggleClass(class)
    Filters.class = Filters.class ~= class and class or nil
    if Filters.spec and Filters.spec.class ~= Filters.class then
        Filters.spec = nil
    end
    Changed()
end

-- A specialization (a class and its tree's tab): chosen, or no longer when
-- it already was.
function Filters.ToggleSpec(class, tab)
    local spec = Filters.spec
    if spec and spec.class == class and spec.tab == tab then
        Filters.spec = nil
    else
        Filters.spec = { class = class, tab = tab }
    end
    Changed()
end

function Filters.ToggleLevel(index)
    Filters.level = Filters.level ~= index and index or nil
    Changed()
end

-- The window's filters go when it closes.
function Filters.ClearWindow()
    if Filters.kind or Filters.class or Filters.spec or Filters.level then
        Filters.kind, Filters.class, Filters.spec, Filters.level = nil, nil, nil, nil
        Changed()
    end
end

function Filters.Init()
    -- The roster's boxes of 0.6 and 0.7 kept their kinds there.
    ns.db.settings.roster = nil
    local function Invalidate()
        Filters.Invalidate()
    end
    ns.On("RosterUpdated", Invalidate)
    ns.On("GuildChanged", Invalidate)
    ns.On("DataChanged", Invalidate)
    ns.On("ProfileChanged", Invalidate)
    -- What the officers set, and who they are (Officers.lua).
    ns.On("OfficersChanged", Invalidate)
    -- Builds, and the guild master's bank ranks, from the other addons.
    ns.Sources.OnRecordChanged(ns.Sources.BUILDS, Invalidate)
    ns.Sources.OnRecordChanged(BANKS, Invalidate)
end
