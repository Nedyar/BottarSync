-- Export.lua: the file the Bot'tar bot reads.
--
-- An addon cannot write files of its own: the client only writes the saved
-- variables, to WTF\Account\<account>\SavedVariables\BottarSync.lua, when
-- the character logs out or the interface reloads. So at that moment the
-- whole data set is written as one JSON text into the saved variable
-- BottarSyncJSON, which the bot reads from that file (see Bot/README.md in
-- https://github.com/Nedyar/BottarSync for the format and the readers; they
-- are left out of the addon's package).
--
-- The data travels between clients as IDs; names (classes, races,
-- professions, recipes, talents, items) are looked up here, in the language
-- of this client.
local _, ns = ...
local L = ns.L
local Json = ns.Json

local Export = {}
ns.Export = Export

Export.FORMAT = 1

local Object, Array = Json.Object, Json.Array

local SLOT_NAMES = {
    [1] = "head", [2] = "neck", [3] = "shoulder", [4] = "shirt", [5] = "chest", [6] = "waist", [7] = "legs",
    [8] = "feet", [9] = "wrist", [10] = "hands", [11] = "finger1", [12] = "finger2", [13] = "trinket1",
    [14] = "trinket2", [15] = "back", [16] = "mainHand", [17] = "offHand", [18] = "ranged", [19] = "tabard",
}
local SEXES = { [2] = "male", [3] = "female" }
local FACTIONS = { [1] = "Alliance", [2] = "Horde", [3] = "Neutral" }

function Export.Enabled()
    return ns.db.settings.export ~= false
end

-- Names, looked up once per session ----------------------------------------------

local spellNames, recipeItems, classes, races = {}, {}, nil, {}

local function Text(value)
    value = ns.Plain(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end
    return value
end

local function SpellName(spellID)
    if not spellID or spellID == 0 then
        return nil
    end
    local name = spellNames[spellID]
    if name == nil then
        name = Text(ns.Try(C_Spell.GetSpellName, spellID)) or false
        spellNames[spellID] = name
    end
    return name or nil
end

-- The item a recipe makes, when it makes one.
local function RecipeItem(recipeID)
    local itemID = recipeItems[recipeID]
    if itemID == nil then
        local schematic = ns.Try(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
        itemID = ns.CanRead(schematic) and ns.Number(schematic.outputItemID) or false
        if itemID == 0 then
            itemID = false
        end
        recipeItems[recipeID] = itemID
    end
    return itemID or nil
end

-- [classID] and [class file] = { id, token, name }.
local function Classes()
    if classes then
        return classes
    end
    classes = {}
    for classID = 1, 30 do
        local name, file, id
        local info = C_CreatureInfo and ns.Try(C_CreatureInfo.GetClassInfo, classID)
        if ns.CanRead(info) then
            name, file, id = info.className, info.classFile, info.classID
        elseif GetClassInfo then
            name, file, id = ns.Try(GetClassInfo, classID)
        end
        file = Text(file)
        if file then
            local class = { id = ns.Number(id) or classID, token = file, name = Text(name) }
            classes[class.id] = class
            classes[file] = class
        end
    end
    return classes
end

local function ClassJSON(key)
    local class = key and Classes()[key]
    if not class then
        if type(key) == "string" then
            return Object("id", nil, "token", key, "name", nil)
        end
        return nil
    end
    return Object("id", class.id, "token", class.token, "name", class.name)
end

local function RaceJSON(raceID)
    if not raceID or raceID == 0 then
        return nil
    end
    local race = races[raceID]
    if race == nil then
        local info = C_CreatureInfo and ns.Try(C_CreatureInfo.GetRaceInfo, raceID)
        race = ns.CanRead(info) and { token = Text(info.clientFileString), name = Text(info.raceName) } or false
        races[raceID] = race
    end
    return Object("id", raceID, "token", race and race.token or nil, "name", race and race.name or nil)
end

-- An item's name and quality, when this client has the item loaded.
local function ItemInfo(itemString, itemID)
    local name, _, quality = ns.Try(C_Item.GetItemInfo, itemString)
    name, quality = Text(name), ns.Number(quality)
    if not name and itemID then
        name = Text(ns.Try(C_Item.GetItemNameByID, itemID))
    end
    if not quality and itemID then
        quality = ns.Number(ns.Try(C_Item.GetItemQualityByID, itemID))
    end
    return name, quality
end

local function ItemFields(itemString)
    local itemID, enchantID = itemString:match("^item:(%d+):?(%d*)")
    return tonumber(itemID), tonumber(enchantID)
end

-- Item data comes from the server on request; asking ahead means names are
-- known by the time the file is written.
local warmQueue, warmTicker, warmed = {}, nil, {}
local WARM_PER_TICK = 10

local function Warm(record)
    if not record or not record.g or not C_Item.RequestLoadItemDataByID then
        return
    end
    for _, item in ipairs(record.g) do
        local itemID = ItemFields(item.i)
        if itemID and not warmed[itemID] then
            warmed[itemID] = true
            warmQueue[#warmQueue + 1] = itemID
        end
    end
    if #warmQueue > 0 and not warmTicker then
        warmTicker = C_Timer.NewTicker(0.5, function()
            for _ = 1, WARM_PER_TICK do
                local itemID = table.remove(warmQueue)
                if not itemID then
                    warmTicker:Cancel()
                    warmTicker = nil
                    return
                end
                ns.Try(C_Item.RequestLoadItemDataByID, itemID)
            end
        end)
    end
end

-- One member ---------------------------------------------------------------------

local function ProfessionsJSON(record)
    local list = {}
    for _, prof in ipairs(ns.Data.SortedProfessions(record)) do
        local recipes
        if prof.k == false then
            recipes = Array({})
        elseif type(prof.k) == "table" then
            local items = {}
            for i, recipeID in ipairs(prof.k) do
                items[i] = Object("id", recipeID, "name", SpellName(recipeID), "itemId", RecipeItem(recipeID))
            end
            recipes = Array(items)
        end
        list[#list + 1] = Object(
            "id", prof.sl,
            "name", ns.ProfessionName(prof.sl, prof.lk),
            "rank", prof.r,
            "maxRank", prof.m,
            "recipes", recipes)
    end
    return Array(list)
end

local function TalentsJSON(talents)
    local specs = {}
    for _, spec in ipairs(talents.s) do
        local tabs, summary = {}, {}
        for i, tab in ipairs(spec.tb) do
            tabs[i] = Object("index", i, "name", tab.n, "pointsSpent", tab.sp)
            summary[i] = tostring(tab.sp)
        end
        local list = {}
        for _, talent in ipairs(spec.t) do
            local tab = spec.tb[talent.tb]
            list[#list + 1] = Object(
                "tab", talent.tb > 0 and talent.tb or nil,
                "tabName", tab and tab.n or nil,
                "row", talent.rw > 0 and talent.rw or nil,
                "column", talent.cl > 0 and talent.cl or nil,
                "name", SpellName(talent.sp),
                "spellId", talent.sp > 0 and talent.sp or nil,
                "nodeId", talent.nd,
                "rank", talent.r,
                "maxRank", talent.m,
                "posX", talent.x,
                "posY", talent.y)
        end
        specs[#specs + 1] = Object(
            "group", spec.gr,
            "active", spec.gr == talents.ag,
            "summary", table.concat(summary, "/"),
            "tabs", Array(tabs),
            "talents", Array(list))
    end
    return Object(
        "activeSpec", talents.ag,
        "specCount", talents.ng,
        "unspentPoints", talents.un,
        "treeId", talents.tr ~= 0 and talents.tr or nil,
        "specs", Array(specs))
end

local function EquipmentJSON(gear)
    local list = {}
    for _, item in ipairs(gear) do
        local itemID, enchantID = ItemFields(item.i)
        local name, quality = ItemInfo(item.i, itemID)
        list[#list + 1] = Object(
            "slot", item.s,
            "slotName", SLOT_NAMES[item.s],
            "itemId", itemID,
            "name", name,
            "quality", quality,
            "itemLevel", item.il > 0 and item.il or nil,
            "enchantId", enchantID ~= 0 and enchantID or nil,
            "itemString", item.i)
    end
    return Array(list)
end

-- entry: the member's roster entry (nil when not in the roster read);
-- record: what their addon shared (nil without the addon).
local function MemberJSON(guid, entry, record, now)
    local level = record and record.l ~= 0 and record.l or nil
    if entry and entry.l and (not level or entry.l > level) then
        level = entry.l
    end
    local class = record and record.c ~= 0 and record.c or (entry and entry.c)
    local online, lastOnline
    if entry then
        online = entry.on == true
        lastOnline = online and now or entry.lo
    end
    return Object(
        "guid", guid,
        "name", (entry and entry.n) or (record and record.n),
        "realm", record and record.rl or nil,
        "level", level,
        "class", ClassJSON(class),
        "race", record and RaceJSON(record.r) or nil,
        "sex", record and SEXES[record.sx] or nil,
        "faction", record and FACTIONS[record.f] or nil,
        "inRoster", entry ~= nil,
        "rank", entry and entry.rk and Object("index", entry.ri, "name", entry.rk) or nil,
        "note", entry and entry.nt or nil,
        "online", online,
        "lastOnline", lastOnline,
        "hasAddon", record ~= nil,
        "updatedAt", record and record.t or nil,
        "addonVersion", record and record.av > 0 and ns.VersionString(record.av) or nil,
        "itemLevel", record and record.il and record.il / 100 or nil,
        "professions", record and ProfessionsJSON(record) or nil,
        "talents", record and record.tl and TalentsJSON(record.tl) or nil,
        "equipment", record and record.g and EquipmentJSON(record.g) or nil)
end

-- The whole file ---------------------------------------------------------------------

local function SortedMembers(guild)
    local roster = guild.roster and guild.roster.m
    local list = {}
    if roster then
        for guid, entry in pairs(roster) do
            list[#list + 1] = { guid = guid, entry = entry, record = ns.Data.IsShareable(guild.members[guid]) and guild.members[guid] or nil }
        end
    else
        -- Never read the roster of this guild: what the addon users shared.
        for guid, record in pairs(guild.members) do
            if ns.Data.IsShareable(record) then
                list[#list + 1] = { guid = guid, record = record }
            end
        end
    end
    for _, item in ipairs(list) do
        item.sortName = ((item.entry and item.entry.n) or (item.record and item.record.n) or ""):lower()
    end
    table.sort(list, function(a, b)
        if a.sortName ~= b.sortName then
            return a.sortName < b.sortName
        end
        return a.guid < b.guid
    end)
    return list
end

local function GuildJSON(guildKey, guild, now)
    local members, withAddon = {}, 0
    for _, item in ipairs(SortedMembers(guild)) do
        members[#members + 1] = MemberJSON(item.guid, item.entry, item.record, now)
        if item.record then
            withAddon = withAddon + 1
        end
    end
    return Object(
        "name", guildKey,
        "rosterUpdatedAt", guild.roster and guild.roster.t or nil,
        "memberCount", #members,
        "membersWithAddon", withAddon,
        "members", Array(members))
end

local function SortedGuildKeys()
    local keys = {}
    for key in pairs(ns.db.guilds) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

-- The JSON text of everything this client knows.
function Export.Build()
    local now = ns.Now()
    local guilds = {}
    for _, key in ipairs(SortedGuildKeys()) do
        guilds[#guilds + 1] = GuildJSON(key, ns.db.guilds[key], now)
    end
    return Json.Encode(Object(
        "format", Export.FORMAT,
        "addon", ns.TITLE,
        "addonVersion", ns.VERSION,
        "generatedAt", now,
        "generatedAtUtc", date("!%Y-%m-%dT%H:%M:%SZ", now),
        "locale", GetLocale(),
        "exportedBy", Object("name", ns.playerName, "realm", ns.realm, "guid", ns.playerGUID),
        "guilds", Array(guilds)))
end

-- Runs at logout, right before the client writes the saved variables.
function Export.WriteSaved()
    if not Export.Enabled() then
        BottarSyncJSON = nil
        return
    end
    local started = debugprofilestop and debugprofilestop()
    BottarSyncJSON = Export.Build()
    if started then
        ns.Debug("file for the bot built in %d ms", debugprofilestop() - started)
    end
end

-- Commands ------------------------------------------------------------------------------

function Export.Describe()
    if Export.Enabled() then
        return L["file for the bot: on. It is written when you log out or reload the interface (/bottar save)."]
    end
    return L["file for the bot: off on this computer (/bottar export on to turn it on)."]
end

function Export.SaveNow()
    if not Export.Enabled() then
        ns.Print(Export.Describe())
        return
    end
    ReloadUI()
end

local window

local function ShowText(title, text)
    if not window then
        window = CreateFrame("Frame", "BottarSyncWindow", UIParent, "PortraitFrameTemplate")
        window:SetSize(680, 500)
        window:SetPoint("CENTER")
        window:SetFrameStrata("DIALOG")
        window:SetMovable(true)
        window:EnableMouse(true)
        window:RegisterForDrag("LeftButton")
        window:SetScript("OnDragStart", window.StartMoving)
        window:SetScript("OnDragStop", window.StopMovingOrSizing)
        window:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Note_01")
        tinsert(UISpecialFrames, window:GetName())

        local hint = window:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        hint:SetPoint("TOPLEFT", 70, -36)
        hint:SetPoint("RIGHT", -20, 0)
        hint:SetJustifyH("LEFT")
        hint:SetText(L["Press Ctrl+A, then Ctrl+C, to copy the text."])

        local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -66)
        scroll:SetPoint("BOTTOMRIGHT", -34, 16)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(620)
        pcall(edit.SetMaxLetters, edit, 0)
        pcall(edit.SetMaxBytes, edit, 0)
        edit:SetScript("OnEscapePressed", function()
            window:Hide()
        end)
        scroll:SetScrollChild(edit)
        window.Edit = edit
    end
    window:SetTitle(title)
    window.Edit:SetText(text)
    window:Show()
    window.Edit:SetFocus()
    window.Edit:HighlightText()
end

-- Shows one member's part of the file, as the bot gets it. name: nil for
-- the current character.
function Export.Show(name)
    local guildKey = ns.Roster.guildKey
    local guild = ns.Data.GetGuild(guildKey)
    if not guild then
        ns.Print(L["you are not in a guild (or the guild has not loaded yet)."])
        return
    end
    local guid = name and ns.Data.FindByName(guild, name) or (not name and ns.playerGUID)
    if not guid then
        ns.Print(L["no guild member called %s."], name)
        return
    end
    local roster = guild.roster and guild.roster.m
    local record = guild.members[guid]
    local entry = (roster and roster[guid]) or ns.Roster.members[guid]
    if not ns.Data.IsShareable(record) then
        record = nil
    end
    local text = Json.Encode(MemberJSON(guid, entry, record, ns.Now()), true)
    ShowText(ns.TITLE .. " - " .. ((entry and entry.n) or (record and record.n) or guid), text)
end

function Export.Init()
    ns.On("RecordChanged", function(_, record)
        Warm(record)
    end)
    -- What was loaded from the saved file, a little after the login.
    C_Timer.After(20, function()
        for _, guild in pairs(ns.db.guilds) do
            for _, record in pairs(guild.members) do
                Warm(record)
            end
        end
    end)
end
