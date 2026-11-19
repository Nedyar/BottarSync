-- Filters.lua: which guild members the Roster tab shows (RosterView.lua),
-- and the numbers the Statistics window (Stats.lua) gives about them.
--
-- Each member of the guild roster is one of three kinds:
--   - a bank character: its rank is one of Guild Bank Alts' bank ranks (the
--     guild master's choice there), or "Banco" without that addon;
--   - an alt: its player did not tick it as a main (Profile.lua);
--   - a main: the others, members without Bot'tar Sync or without a Discord
--     username too.
-- Its class and level come from the guild roster, its specializations from
-- Guild Builds: the talent tree with the most points of each of its builds
-- (Primary and Secondary). A character whose two builds go into different
-- trees has both specializations; one without a build in Guild Builds has
-- an unknown one.
--
-- The roster's boxes choose the kinds it shows (mains and alts at first;
-- saved). The Statistics window adds a class, a specialization of it and a
-- level range, while it is open. Each number counts the members that every
-- other filter lets through, so it tells how many a click on it shows.
-- Offline members count while the roster shows them (its own box).
local _, ns = ...

local Filters = {}
ns.Filters = Filters

Filters.KINDS = { "main", "alt", "bank" }
Filters.DEFAULT_KINDS = { main = true, alt = true, bank = false }
-- The level ranges, the last one for the highest level.
Filters.LEVELS = { { 1, 9 }, { 10, 19 }, { 20, 29 }, { 30, 39 }, { 40, 49 }, { 50, 59 }, { 60, 999 } }
-- The specialization of the members without a build in Guild Builds.
Filters.UNKNOWN = 0
-- Guild Bank Alts' bank rank until its guild master chooses others.
local BANK_RANK = "banco"
local BANKS = "GuildBankAlts"

-- The Statistics window's filters (nil: none).
Filters.class = nil -- a class file ("HUNTER")
Filters.spec = nil  -- a tab of that class's talent tree (1 to 3), or Filters.UNKNOWN
Filters.level = nil -- an index of Filters.LEVELS

local members       -- [GUID] = what the filters look at, until something changes
local trees = {}    -- [class file] = { tree = talent tree ID, tabs = Guild Builds' tb }

-- The kinds the roster shows: { main = bool, alt = bool, bank = bool }.
function Filters.Kinds()
    local settings = ns.db.settings
    if type(settings.roster) ~= "table" then
        settings.roster = {}
    end
    local kinds = settings.roster
    for kind, default in pairs(Filters.DEFAULT_KINDS) do
        if type(kinds[kind]) ~= "boolean" then
            kinds[kind] = default
        end
    end
    return kinds
end

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
        -- Who plays it, for its tooltip in the roster.
        entry.dc = player and player.dc or nil
        entry.main = player and player.main or false
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
        entry.unknown = next(entry.specs) == nil
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

-- Forgets what it knew of the members (the roster, a profile, a build or
-- the bank ranks changed): the roster and the window show it again.
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
    if skip ~= "kind" and not Filters.Kinds()[entry.kind] then
        return false
    end
    if skip ~= "class" then
        if Filters.class and entry.class ~= Filters.class then
            return false
        end
        if skip ~= "spec" and Filters.spec then
            if Filters.spec == Filters.UNKNOWN then
                if not entry.unknown then
                    return false
                end
            elseif not entry.specs[Filters.spec] then
                return false
            end
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

-- Whether the roster shows a member (one the filters do not know yet, it
-- does).
function Filters.Shows(guid)
    local entry = Filters.Member(guid)
    return entry == nil or Filters.Passes(entry)
end

-- The numbers ----------------------------------------------------------------------------

-- {
--   kinds = { main = n, alt = n, bank = n }, all = n,
--   classes = { { class = file, count = n } ... } (most first), classTotal = n,
--   specs = { [tab or UNKNOWN] = { count, primary, secondary } } (with a
--     class only; primary: the Primary build is in it; secondary: only the
--     Secondary one), specTotal = members of the class, dual = those with
--     two specializations (they count in both),
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
        if Filters.class and Filters.Passes(entry, "spec") then
            counts.specTotal = counts.specTotal + 1
            if entry.unknown then
                local spec = counts.specs[Filters.UNKNOWN] or { count = 0, primary = 0, secondary = 0 }
                counts.specs[Filters.UNKNOWN] = spec
                spec.count = spec.count + 1
            else
                local tabs = 0
                for tab, groups in pairs(entry.specs) do
                    tabs = tabs + 1
                    local spec = counts.specs[tab] or { count = 0, primary = 0, secondary = 0 }
                    counts.specs[tab] = spec
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

function Filters.SetKind(kind, shown)
    Filters.Kinds()[kind] = shown and true or false
    Changed()
end

-- A card of the window: only that kind, or every kind ("all").
function Filters.ShowOnly(kind)
    local kinds = Filters.Kinds()
    for _, each in ipairs(Filters.KINDS) do
        kinds[each] = kind == "all" or each == kind
    end
    Changed()
end

-- The card that stands for the kinds shown ("all" for every kind), or nil.
function Filters.OnlyKind()
    local kinds, shown = Filters.Kinds(), {}
    for _, kind in ipairs(Filters.KINDS) do
        if kinds[kind] then
            shown[#shown + 1] = kind
        end
    end
    if #shown == #Filters.KINDS then
        return "all"
    end
    return #shown == 1 and shown[1] or nil
end

-- A class: chosen, or no longer when it already was. Its specialization
-- goes either way.
function Filters.ToggleClass(class)
    Filters.class = Filters.class ~= class and class or nil
    Filters.spec = nil
    Changed()
end

function Filters.ToggleSpec(tab)
    Filters.spec = Filters.spec ~= tab and tab or nil
    Changed()
end

function Filters.ToggleLevel(index)
    Filters.level = Filters.level ~= index and index or nil
    Changed()
end

-- The window's filters go when it closes.
function Filters.ClearWindow()
    if Filters.class or Filters.spec or Filters.level then
        Filters.class, Filters.spec, Filters.level = nil, nil, nil
        Changed()
    end
end

function Filters.Init()
    local function Invalidate()
        Filters.Invalidate()
    end
    ns.On("RosterUpdated", Invalidate)
    ns.On("GuildChanged", Invalidate)
    ns.On("DataChanged", Invalidate)
    ns.On("ProfileChanged", Invalidate)
    -- Builds, and the guild master's bank ranks, from the other addons.
    ns.Sources.OnRecordChanged(ns.Sources.BUILDS, Invalidate)
    ns.Sources.OnRecordChanged(BANKS, Invalidate)
end
