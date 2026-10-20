-- Character.lua: reads the player's own character: level, class, race, sex,
-- faction, item level and equipped items.
local _, ns = ...

local Character = {}
ns.Character = Character

Character.ready = false  -- the character has been read once this session

local FIRST_SLOT = INVSLOT_FIRST_EQUIPPED or 1
local LAST_SLOT = INVSLOT_LAST_EQUIPPED or 19

local FACTIONS = { Alliance = 1, Horde = 2, Neutral = 3 }

local pendingLevel  -- PLAYER_LEVEL_UP's level, ahead of UnitLevel for a moment

local Number = ns.Number

-- "item:19019:1900:0:0:0:0:0:1234567:60:0:..." -> the same without the
-- fields that change on their own (unique ID, the player's level and spec),
-- which would make an unchanged item look new. Fields are numbers, except
-- the crafter's GUID that crafted items carry ("Player-4613-010B766A");
-- a field with anything else is left blank. nil for anything that is not
-- an item.
function Character.ItemString(link)
    if type(link) ~= "string" then
        return nil
    end
    local text = link:match("|H(item:[^|]+)|h") or link:match("^(item:[^|]+)$")
    if not text then
        return nil
    end
    local fields = {}
    for field in (text .. ":"):gmatch("([^:]*):") do
        fields[#fields + 1] = field
    end
    if not (fields[2] and fields[2]:find("^%d+$")) then
        return nil
    end
    for i = 3, #fields do
        -- 9, 10 and 11 are the unique ID, link level and spec.
        if (i >= 9 and i <= 11) or not fields[i]:find("^[%w%-]*$") then
            fields[i] = ""
        end
    end
    local itemString = table.concat(fields, ":")
    if #itemString > ns.Pack.LIMITS.item then
        return "item:" .. fields[2]
    end
    return itemString
end

local function ItemLevel(slot, link)
    local level
    if ItemLocation and C_Item.GetCurrentItemLevel then
        local location = ns.Try(ItemLocation.CreateFromEquipmentSlot, ItemLocation, slot)
        if location then
            level = Number(ns.Try(C_Item.GetCurrentItemLevel, location))
        end
    end
    if not level and C_Item.GetDetailedItemLevelInfo then
        level = Number(ns.Try(C_Item.GetDetailedItemLevelInfo, link))
    end
    if level then
        return math.max(math.floor(level + 0.5), 0)
    end
    return 0
end

local function ReadGear()
    local gear = {}
    for slot = FIRST_SLOT, LAST_SLOT do
        local link = ns.Plain(ns.Try(GetInventoryItemLink, "player", slot))
        local itemString = Character.ItemString(link)
        if itemString then
            gear[#gear + 1] = { s = slot, i = itemString, il = ItemLevel(slot, link) }
        end
    end
    return gear
end

-- The equipped items' average item level, in hundredths.
local function ReadItemLevel()
    local _, equipped = ns.Try(GetAverageItemLevel)
    equipped = Number(equipped)
    if not equipped or equipped < 0 then
        return nil
    end
    return math.floor(equipped * 100 + 0.5)
end

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
        il = ReadItemLevel(),
        g = ReadGear(),
    }
    local changed = not ns.Data.IsShareable(record)
    for key, value in pairs(values) do
        if not ns.Same(record[key], value) then
            record[key] = value
            changed = true
        end
    end
    if record.il and not values.il then
        record.il = nil
        changed = true
    end
    Character.ready = true
    if changed then
        ns.Data.TouchOwn(record)
        ns.Debug("own character updated")
    end
end

function Character.Init()
    local events = CreateFrame("Frame")
    ns.RegisterEvents(events, "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_AVG_ITEM_LEVEL_UPDATE")
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
