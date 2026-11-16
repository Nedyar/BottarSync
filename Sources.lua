-- Sources.lua: what the guild's other addons share, which the bot's file
-- puts together with Bot'tar Sync's own records:
--   Guild Professions & Recipes: each member's professions and recipes
--       (its records' p, see its Pack.lua);
--   Guild Builds: each member's talents, the items they wear and their item
--       level (its records' lv, tr, ag, tb, s, un, w and il, see its
--       Pack.lua). Talents come as the game's import strings, which
--       TalentTree.lua reads.
-- Each addon shares and keeps its own data; this only reads their records,
-- through LibGuildSync, and finds nothing when an addon is missing or turned
-- off. Their checks (each addon's Data.CleanRecord) already ran on every
-- record they keep.
local _, ns = ...

local Sources = {}
ns.Sources = Sources

Sources.PROFESSIONS = "GuildProfessionsRecipes"
Sources.BUILDS = "GuildBuilds"

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
