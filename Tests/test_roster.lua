-- The guild roster's filters and the Statistics window (Filters.lua,
-- RosterView.lua, Stats.lua), on a stand-in for the game's member list.
local H = ...

local MODES = {
    CHAT = { "Chat", "InviteButton", "CommunitiesControlFrame" },
    ROSTER = { "MemberList", "CommunitiesControlFrame" },
}

-- The game's data providers, as far as the filters use them.
local function Provider(elements)
    local provider = { elements = elements or {} }
    function provider:Insert(data)
        table.insert(self.elements, data)
    end
    function provider:ForEach(fn)
        for _, data in ipairs(self.elements) do
            fn(data)
        end
    end
    return provider
end

-- The game's member list (CommunitiesFrame.MemberList): RefreshListDisplay
-- puts every roster member in a new provider (the online ones only without
-- the "Offline members" box), and the scroll box makes a row for each,
-- telling the callbacks of new rows. A row's own OnEnter shows nothing, as
-- the game's on the Roster tab when no text is cut.
local function MemberList(client)
    local list = H.NewObject(client, "Frame")
    list.expandedDisplay = true
    list.clubType = 2
    rawset(list, "GetSelectedClubInfo", function(self)
        return { clubType = self.clubType }
    end)
    rawset(list, "RefreshLayout", function() end)
    list.ShowOfflineButton = H.NewObject(client, "CheckButton")
    list.ShowOfflineButton.Text = H.NewObject(client, "FontString")
    local scrollBox = H.NewObject(client, "Frame")
    scrollBox._callbacks = {}
    scrollBox._rows = {}
    rawset(scrollBox, "SetDataProvider", function(self, provider)
        self._provider = provider
        self._rows = {}
        for _, data in ipairs(provider.elements) do
            local row = H.NewObject(client, "Button")
            row.memberInfo = data.memberInfo
            rawset(row, "GetMemberInfo", function(r)
                return r.memberInfo
            end)
            row:SetScript("OnEnter", function() end)
            table.insert(self._rows, row)
            for _, callback in ipairs(self._callbacks) do
                callback(row)
            end
        end
    end)
    rawset(scrollBox, "GetDataProvider", function(self)
        return self._provider
    end)
    rawset(scrollBox, "ForEachFrame", function(self, fn)
        for _, row in ipairs(self._rows) do
            fn(row)
        end
    end)
    list.ScrollBox = scrollBox
    rawset(list, "RefreshListDisplay", function(self)
        local provider = Provider()
        for _, member in ipairs(client.world.roster) do
            local online = member.client ~= nil and member.client.loggedIn
            if online or client.showOffline then
                provider:Insert({ memberInfo = { guid = member.guid, name = member.short, guildRank = member.rank } })
            end
        end
        self.ScrollBox:SetDataProvider(provider)
    end)
    return list
end

local function GuildWindow(client)
    local frame = H.FakeCommunities(client)
    frame.MemberList = MemberList(client)
    frame.InviteButton = H.NewObject(client, "Button")
    frame.CommunitiesControlFrame = H.NewObject(client, "Frame")
    frame.CommunitiesControlFrame.GuildControlButton = H.NewObject(client, "Button")
    rawset(frame, "GetDisplayMode", function()
        return MODES.ROSTER
    end)
    rawset(frame, "GetSelectedClubId", function()
        return 1
    end)
    return frame
end

local function Globals(client)
    return {
        COMMUNITIES_FRAME_DISPLAY_MODES = MODES,
        C_Club = {
            GetClubInfo = function()
                return { clubType = 2 }
            end,
        },
        ACCEPT = "Accept",
        SAVE = "Save",
        CreateDataProvider = Provider,
        -- The roster's "Offline members" box, as the game keeps it.
        GetCVarBool = function(name)
            return name == "communitiesShowOffline" and client.showOffline or false
        end,
        LOCALIZED_CLASS_NAMES_MALE = { HUNTER = "Hunter", MAGE = "Mage", WARRIOR = "Warrior" },
        ScrollUtil = {
            InitScrollBoxListWithScrollBar = function(scrollBox, _, view)
                rawset(scrollBox, "_view", view)
                rawset(scrollBox, "SetDataProvider", function(self, provider)
                    self._provider = provider
                end)
            end,
            InitScrollFrameWithScrollBar = function() end,
            -- Every addon's callback, the guild's other addons' too.
            AddAcquiredFrameCallback = function(scrollBox, callback, owner)
                table.insert(scrollBox._callbacks, function(row)
                    callback(owner, row)
                end)
            end,
        },
    }
end

local function NewClient(world, name, options)
    local client = world:NewClient(name, options)
    client.showOffline = true
    client.globals = Globals(client) -- set in its environment at login
    return client
end

local function Errors(world, label)
    H.eq(#world.errors, 0, "no errors: " .. label)
    for _, err in ipairs(world.errors) do
        print("   " .. err)
    end
    world.errors = {}
end

-- The names in the roster's list, in its order.
local function Listed(client)
    local names = {}
    for _, data in ipairs(client.env.CommunitiesFrame.MemberList.ScrollBox._provider.elements) do
        names[#names + 1] = data.memberInfo.name
    end
    return table.concat(names, ", ")
end

local function Click(button)
    button._scripts.OnClick(button)
end

-- The guild: an officer who looks at the roster (a hunter, all in its
-- third tree), a player's main (a hunter with two specs in different
-- trees) and alt (a mage of the same WoW account), a bank character and a
-- warrior without the addon, both offline.
local world = H.NewWorld({ seed = 73, communities = GuildWindow, senderFormat = "short", strictWhispers = true })
local officer = NewClient(world, "Kantrul Steadyshot", { rank = "Officer", rankIndex = 1, level = 60,
    talents = { active = 1, groups = { [1] = { [301] = 5, [302] = 5 } }, unspent = 0 } })
local main = NewClient(world, "Nedyar Cazador", { level = 37,
    talents = { active = 1, groups = { [1] = { [101] = 5, [102] = 5 }, [2] = { [201] = 5, [202] = 5 } }, unspent = 0 } })
world:AddMember("Caja Fuerte", nil, { class = "WARRIOR", level = 5, rank = "Banco" })
world:AddMember("Viejo Guerrero", nil, { class = "WARRIOR", level = 60 })
world:Login(officer)
world:RunFor(5)
world:Login(main)
world:RunFor(20)
main.ns.Profile.SetDiscord("nedyar94")
world:RunFor(30)
world:Logout(main)
local alt = NewClient(world, "Nedyar Mago", { saved = main.saved, level = 12, classID = 8,
    talents = { active = 1, groups = { [1] = { [1101] = 5 } }, unspent = 0 } })
world:Login(alt)
world:RunFor(60)

local ns = officer.ns
local env = officer.env
local Filters = ns.Filters
local list = env.CommunitiesFrame.MemberList

H.section("Roster: the boxes")
local button = ns.RosterView.statsButton
local checks = ns.RosterView.checks
H.check(button ~= nil and button:IsShown(), "a Statistics button on the guild's Roster tab")
H.check(button._point ~= nil, "placed where the game's Offline members box was")
H.eq(#checks, 3, "three boxes: Mains, Alts and Banks")
H.check(checks[1]:GetChecked() and checks[2]:GetChecked() and not checks[3]:GetChecked(), "mains and alts ticked, banks not")
list:RefreshListDisplay()
H.eq(Listed(officer), "Kantrul Steadyshot, Nedyar Cazador, Viejo Guerrero, Nedyar Mago",
    "the roster leaves out the bank character; members without the addon count as mains")
checks[3]:SetChecked(true)
Click(checks[3])
H.eq(Listed(officer), "Kantrul Steadyshot, Nedyar Cazador, Caja Fuerte, Viejo Guerrero, Nedyar Mago", "Banks ticked: it shows")
H.check(ns.db.settings.roster.bank == true, "and the box is saved")
checks[1]:SetChecked(false)
Click(checks[1])
H.eq(Listed(officer), "Caja Fuerte, Nedyar Mago", "Mains unticked: only the alt and the bank character")
Filters.SetKind("main", true)
Filters.SetKind("bank", false)
world:RunFor(1)
H.check(checks[1]:GetChecked() and not checks[3]:GetChecked(), "the boxes follow the filters")
H.eq(Listed(officer), "Kantrul Steadyshot, Nedyar Cazador, Viejo Guerrero, Nedyar Mago", "and so does the list")
-- Another community's roster: no buttons, no filters.
list.clubType = 1
list:RefreshListDisplay()
H.check(not button:IsShown() and not checks[1]:IsShown(), "nothing on another community's roster")
H.eq(Listed(officer), "Kantrul Steadyshot, Nedyar Cazador, Caja Fuerte, Viejo Guerrero, Nedyar Mago", "which lists everyone")
list.clubType = 2
list:RefreshListDisplay()
H.check(button:IsShown(), "back on the guild's")
Errors(world, "the boxes")

H.section("Roster: a member's tooltip")
local tooltip = env.GameTooltip
rawset(tooltip, "SetOwner", function(self, owner)
    self._owner, self._text, self._lines = owner, nil, {}
end)
rawset(tooltip, "IsOwned", function(self, owner)
    return self._owner == owner
end)
local rows = list.ScrollBox._rows
local function RowOf(name)
    for _, row in ipairs(rows) do
        if row.memberInfo.name == name then
            return row
        end
    end
end
local function Lines()
    return table.concat(tooltip._lines, " / ")
end
tooltip._owner = nil
RowOf("Nedyar Mago")._scripts.OnEnter(RowOf("Nedyar Mago"))
H.check(tooltip._owner == RowOf("Nedyar Mago") and tooltip._lines[1] == "Nedyar Mago",
    "a row's tooltip shows even when the game shows none (no text cut)")
H.check(Lines():find("Discord: nedyar94", 1, true) ~= nil, "with its player's Discord username")
H.check(Lines():find("Mains: Nedyar Cazador", 1, true) and Lines():find("Alts: Nedyar Mago", 1, true),
    "and their mains and alts")
-- When the game shows its own (a text is cut), ours are added to it.
local cut = H.NewObject(officer, "Button")
cut.memberInfo = RowOf("Nedyar Cazador").memberInfo
rawset(cut, "GetMemberInfo", function(self)
    return self.memberInfo
end)
cut:SetScript("OnEnter", function(row)
    tooltip:SetOwner(row)
    tooltip:AddLine("the game's lines")
end)
for _, callback in ipairs(list.ScrollBox._callbacks) do
    callback(cut)
end
cut._scripts.OnEnter(cut)
H.check(tooltip._lines[1] == "the game's lines" and tooltip._lines[2] ~= "Nedyar Cazador" and Lines():find("Discord: nedyar94", 1, true),
    "the game's own tooltip gets the player's lines, and keeps its own")
tooltip._owner = nil
RowOf("Viejo Guerrero")._scripts.OnEnter(RowOf("Viejo Guerrero"))
H.check(tooltip._lines[1] == "Viejo Guerrero" and not Lines():find("Discord", 1, true),
    "a member without the addon: the game's lines only")
Errors(world, "the tooltip")

H.section("Roster: the numbers")
local counts = Filters.Counts()
H.check(counts.kinds.main == 3 and counts.kinds.alt == 1 and counts.kinds.bank == 1 and counts.all == 5,
    "3 mains, 1 alt, 1 bank character, 5 in all")
local byClass = {}
for _, each in ipairs(counts.classes) do
    byClass[each.class] = each.count
end
H.check(byClass.HUNTER == 2 and byClass.MAGE == 1 and byClass.WARRIOR == 1 and counts.classTotal == 4,
    "classes count the kinds shown: 2 hunters, 1 mage, 1 warrior (not the bank character)")
H.eq(counts.classes[1].class, "HUNTER", "the most numerous first")
H.check(counts.levels[1] == 0 and counts.levels[2] == 1 and counts.levels[4] == 1 and counts.levels[7] == 2,
    "levels: none of 1-9 (the bank character), one of 10-19, one of 30-39, two of 60")
officer.showOffline = false
counts = Filters.Counts()
H.check(counts.all == 2 and counts.kinds.main == 1 and counts.kinds.alt == 1, "without offline members, the online ones only")
officer.showOffline = true
Errors(world, "the numbers")

H.section("Roster: the Statistics window")
Click(button)
local Stats = ns.Stats
local window = Stats.Window()
H.check(window ~= nil and window:IsShown(), "the button opens the window")
H.check(window._point ~= nil, "beside the guild window, as tall as it")
local cards = window.kindCards
H.check(cards.main.Number._text == "3" and cards.alt.Number._text == "1" and cards.bank.Number._text == "1" and cards.all.Number._text == "5",
    "a card for each kind, with its number")
H.check(not cards.all.Selected:IsShown() and not cards.main.Selected:IsShown(), "mains and alts shown: no card stands for that")
Click(cards.bank)
H.check(checks[3]:GetChecked() and not checks[1]:GetChecked() and not checks[2]:GetChecked(), "the Banks card shows only banks: it sets the boxes")
H.eq(Listed(officer), "Caja Fuerte", "in the roster too")
world:RunFor(1)
H.check(cards.bank.Selected:IsShown(), "and stands chosen")
Click(cards.all)
H.eq(Listed(officer), "Kantrul Steadyshot, Nedyar Cazador, Caja Fuerte, Viejo Guerrero, Nedyar Mago", "All: everyone")
Filters.SetKind("bank", false)
world:RunFor(1)

-- Classes.
local classBar = window.ClassBar
local hunter
for _, section in ipairs(classBar.sections) do
    if section:IsShown() and section.item.class == "HUNTER" then
        hunter = section
    end
end
H.check(hunter ~= nil and hunter.item.count == 2, "a section of the class bar for the hunters")
local widths = Stats.Widths({ 2, 1, 1 }, 100)
H.check(widths[1] == 50 and widths[2] == 25 and widths[3] == 25, "each section as wide as its share")
widths = Stats.Widths({ 200, 1 }, 100)
H.check(widths[2] == Stats.MIN_SECTION and widths[1] + widths[2] == 100, "never too narrow to point at, and filling the bar")
Click(hunter)
H.eq(Filters.class, "HUNTER", "a click on it filters by that class")
H.eq(Listed(officer), "Kantrul Steadyshot, Nedyar Cazador", "the roster shows the hunters")
world:RunFor(1)
H.check(window.SpecBar:IsShown(), "and the window shows their specializations")
counts = Filters.Counts()
H.check(counts.specTotal == 2 and counts.specs[1].count == 1 and counts.specs[2].count == 1 and counts.specs[3].count == 1,
    "the main's two specs count in both trees, the officer's in the third")
H.check(counts.specs[1].primary == 1 and counts.specs[2].secondary == 1 and counts.specs[3].primary == 1,
    "told apart: in the primary build, or only in the secondary")
H.eq(counts.dual, 1, "one hunter has two different specializations")
H.check(window.Dual:IsShown() and window.Dual._text:find("1", 1, true) ~= nil, "and the window says so")
local specSections = 0
for _, section in ipairs(window.SpecBar.sections) do
    if section:IsShown() then
        specSections = specSections + 1
    end
end
H.eq(specSections, 3, "a section for each of the three trees")
Filters.ToggleSpec(2)
H.eq(Listed(officer), "Nedyar Cazador", "a specialization filters by it, also when only the secondary build has it")
Filters.ToggleSpec(2)
H.eq(Listed(officer), "Kantrul Steadyshot, Nedyar Cazador", "clicked again, no longer")
Filters.ToggleSpec(3)
Click(hunter)
H.check(Filters.class == nil and Filters.spec == nil, "the class clicked again: no class filter, nor its specialization's")
world:RunFor(1)
H.check(not window.SpecBar:IsShown(), "nor its specializations")
H.eq(Listed(officer), "Kantrul Steadyshot, Nedyar Cazador, Viejo Guerrero, Nedyar Mago", "the roster as the boxes say")

-- Levels.
Click(window.levelCards[7])
H.eq(Listed(officer), "Kantrul Steadyshot, Viejo Guerrero", "the level 60 card filters by it")
H.eq(window.levelCards[7].Label._text, "60", "labelled 60")
world:RunFor(1)
H.check(cards.main.Number._text == "2" and cards.alt.Number._text == "0", "the kind cards count the level filter in")
Click(window.levelCards[2])
H.eq(Listed(officer), "Nedyar Mago", "another range replaces it")
H.eq(window.levelCards[2].Label._text, "10-19", "labelled 10-19")
-- Closing the window takes its filters away.
Filters.ToggleClass("MAGE")
window:Hide()
window._scripts.OnHide(window)
H.check(Filters.class == nil and Filters.level == nil, "closing the window removes its filters")
H.eq(Listed(officer), "Kantrul Steadyshot, Nedyar Cazador, Viejo Guerrero, Nedyar Mago", "and the roster shows the boxes' kinds again")
Errors(world, "the window")

H.section("Roster: bank characters from Guild Bank Alts")
local fake = { ADDON_NAME = "GuildBankAlts", Fire = function() end,
    Ranks = { IsBank = function(guid) return guid == main.guid end } }
table.insert(env.LibGuildSync.attached, fake)
Filters.Invalidate()
H.eq(Filters.Member(main.guid).kind, "bank", "Guild Bank Alts' bank ranks decide")
H.eq(Filters.Member(officer.guid).kind, "main", "and only them")
for i, other in ipairs(env.LibGuildSync.attached) do
    if other == fake then
        table.remove(env.LibGuildSync.attached, i)
    end
end
Filters.Invalidate()
H.eq(Filters.Member(main.guid).kind, "main", "without it, the rank Banco")
Errors(world, "Guild Bank Alts")
