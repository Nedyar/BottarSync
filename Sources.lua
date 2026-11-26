-- Sources.lua: what the guild's other addons share, which the bot's file
-- puts together with Bot'tar Sync's own records:
--   Guild Professions & Recipes: each member's professions and recipes
--       (its records' p, see its Pack.lua);
--   Guild Builds: each member's talents, the items they wear and their item
--       level (its records' lv, tr, ag, tb, s, un, w and il, see its
--       Pack.lua). Talents come as the game's import strings, which
--       TalentTree.lua reads.
--   Guild Raids & Events: the guild's events and their sign-ups, through
--       its public API (below).
-- Each addon shares and keeps its own data; this only reads their records,
-- through LibGuildSync, and finds nothing when an addon is missing or turned
-- off. Their checks (each addon's Data.CleanRecord) already ran on every
-- record they keep.
local _, ns = ...

local Sources = {}
ns.Sources = Sources

Sources.PROFESSIONS = "GuildProfessionsRecipes"
Sources.BUILDS = "GuildBuilds"
Sources.EVENTS = "GuildRaidsEvents"

-- The namespace of an addon attached to LibGuildSync, or nil.
function Sources.Find(addonName)
    for _, other in ipairs(LibGuildSync.attached) do
        if other.ADDON_NAME == addonName then
            return other
        end
    end
end

-- Whether an addon's data can be read: it is loaded and has its database.
function Sources.Has(addonName)
    local other = Sources.Find(addonName)
    return other ~= nil and type(other.db) == "table" and type(other.Data) == "table"
end

-- The records an addon keeps of a guild's members: { [GUID] = record }, a
-- table of our own, without records never shared. Also at logout, after
-- that addon packed its own for the saved variables (LibGuildSync 0.3.0's
-- Data.Records).
function Sources.Records(addonName, guildKey)
    local records = {}
    if not guildKey or not Sources.Has(addonName) then
        return records
    end
    local other = Sources.Find(addonName)
    local all
    if other.Data.Records then
        all = other.Data.Records(guildKey)
    else
        -- An older library: as they are now (unreadable once packed).
        local guild = other.db.guilds[guildKey]
        all = guild and guild.members or {}
    end
    for guid, record in pairs(all) do
        if type(record) == "table" and type(record.t) == "number" and record.t > 0 then
            records[guid] = record
        end
    end
    return records
end

-- The title the player sees for an addon.
function Sources.Title(addonName)
    local other = Sources.Find(addonName)
    if other and other.TITLE then
        return other.TITLE
    end
    local title = C_AddOns and ns.Try(C_AddOns.GetAddOnMetadata, addonName, "Title")
    return type(title) == "string" and title ~= "" and title or addonName
end

-- Calls fn(record) for each record an addon changes from now on (its own
-- RecordChanged event), while it is loaded.
function Sources.OnRecordChanged(addonName, fn)
    local other = Sources.Find(addonName)
    if other and other.On then
        other.On("RecordChanged", function(_, record)
            fn(record)
        end)
    end
end

-- Guild Raids & Events ------------------------------------------------------------------------

-- Its public API (the global GuildRaidsEvents, its API.lua), or nil while
-- it is missing or turned off. It builds each event, with its sign-ups as
-- the game's calendar shows them, from every member's record.
local function EventsAPI()
    local api = _G[Sources.EVENTS]
    if type(api) == "table" and type(api.GetEvents) == "function" then
        return api
    end
end

function Sources.HasEvents()
    return EventsAPI() ~= nil
end

-- The API cannot be read at logout once that addon packed its records for
-- saving (addons get the logout one after the other), so the bot's file
-- takes a copy: { guildKey, events = its GetEvents("all") }, taken again
-- whenever its events change, the roster is read again, and as the player
-- leaves the world (a reload or a logout starts there).
local eventsCopy

function Sources.TakeEvents()
    local api = EventsAPI()
    local guildKey = ns.Roster.guildKey
    if not api or not guildKey then
        return
    end
    local ok, events = pcall(api.GetEvents, "all")
    if ok and type(events) == "table" then
        eventsCopy = { guildKey = guildKey, events = events }
    end
end

-- The events of a guild (as GetEvents gives them), or nil when they are
-- not known: Guild Raids & Events is missing, or they are another guild's.
function Sources.Events(guildKey)
    if eventsCopy and eventsCopy.guildKey == guildKey then
        return eventsCopy.events
    end
end

function Sources.WatchEvents()
    local api = EventsAPI()
    if not api then
        return
    end
    local function Soon()
        ns.Debounce("Events", 1, Sources.TakeEvents)
    end
    if type(api.OnChange) == "function" then
        api.OnChange(Soon)
    end
    ns.On("RosterUpdated", Soon)
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LEAVING_WORLD")
    frame:SetScript("OnEvent", Sources.TakeEvents)
    Soon()
end
