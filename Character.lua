-- Character.lua: reads the player's own character: level, class, race, sex
-- and faction. What it wears and its talents are Guild Builds' to share,
-- its professions Guild Professions & Recipes' (see Sources.lua).
local _, ns = ...

local Character = {}
ns.Character = Character

Character.ready = false  -- the character has been read once this session

local FACTIONS = { Alliance = 1, Horde = 2, Neutral = 3 }

local pendingLevel  -- PLAYER_LEVEL_UP's level, ahead of UnitLevel for a moment

local Number = ns.Number

-- Brings our record's character data up to date.
function Character.Update()
    local record = ns.Data.GetOwnRecord(true)
    if not record then
        return
    end
    local level = Number(UnitLevel("player")) or 0
    if pendingLevel and pendingLevel > level then
        level = pendingLevel
    end
    local _, _, classID = UnitClass("player")
    local _, _, raceID = UnitRace("player")
    local values = {
        l = level,
        c = Number(classID) or 0,
        r = Number(raceID) or 0,
        sx = Number(UnitSex("player")) or 0,
        f = FACTIONS[ns.Plain(UnitFactionGroup("player"))] or 0,
    }
    local changed = not ns.Data.IsShareable(record) or record.av ~= ns.VERSION_NUM
    for key, value in pairs(values) do
        if not ns.Same(record[key], value) then
            record[key] = value
            changed = true
        end
    end
    Character.ready = true
    if changed then
        ns.Data.TouchOwn(record)
        ns.Debug("own character updated")
    end
end

function Character.Init()
    local events = CreateFrame("Frame")
    ns.RegisterEvents(events, "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP")
    events:SetScript("OnEvent", function(_, event, level)
        if event == "PLAYER_LEVEL_UP" then
            pendingLevel = Number(level)
        end
        ns.Debounce("CharacterUpdate", 2, Character.Update)
    end)
    ns.On("GuildChanged", function()
        ns.Debounce("CharacterUpdate", 2, Character.Update)
    end)
    Character.Update()
end
