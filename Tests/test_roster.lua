-- The Statistics window, its filters and its list of members (Filters.lua,
-- Stats.lua), and what Bot'tar Sync adds to the game's roster
-- (RosterView.lua), on a stand-in for the game's member list.
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
    -- Its "Offline members" box's click, as the game's: its own field, its
    -- setting, and the list filled again.
    rawset(list, "SetShowOfflinePlayers", function(self, show)
        self.showOfflinePlayers = show
        client.showOffline = show
        self:RefreshListDisplay()
    end)
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
    -- How many times it ran, and the provider it made last: the game's own.
    list._refreshes = 0
    rawset(list, "RefreshListDisplay", function(self)
        self._refreshes = self._refreshes + 1
        local provider = Provider()
        for _, member in ipairs(client.world.roster) do
            local online = member.client ~= nil and member.client.loggedIn
            if online or client.showOffline then
                provider:Insert({ memberInfo = { guid = member.guid, name = member.short, guildRank = member.rank } })
            end
        end
        self._made = provider
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
        COMMUNITIES_MEMBER_LIST_SHOW_OFFLINE = "Offline members",
        SAVE = "Save",
        DECLINE = "Decline",
        CreateDataProvider = Provider,
        -- The roster's "Offline members" box, as the game keeps it.
        GetCVarBool = function(name)
            return name == "communitiesShowOffline" and client.showOffline or false
        end,
        LOCALIZED_CLASS_NAMES_MALE = { HUNTER = "Hunter", MAGE = "Mage", WARRIOR = "Warrior" },
        -- The guild window's key: counts the clicks.
        ToggleGuildFrame = function()
            client.guildToggles = (client.guildToggles or 0) + 1
        end,
        -- How the game's roster tells how long ago a member was online.
        TimeUtil = {
            GetRecentTimeDate = function(years, months, days, hours)
                if (years or 0) > 0 then
                    return years .. " years"
                elseif (months or 0) > 0 then
                    return months .. " months"
                elseif (days or 0) > 0 then
                    return days .. " days"
                elseif (hours or 0) > 0 then
                    return hours .. " hours"
                end
                return "< 1 hour"
            end,
        },
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
local function InRoster(client)
    local names = {}
    for _, data in ipairs(client.env.CommunitiesFrame.MemberList.ScrollBox._provider.elements) do
        names[#names + 1] = data.memberInfo.name
    end
    return table.concat(names, ", ")
end

-- The names in the Statistics window's list, in its order.
local function Listed(client)
    local names = {}
    for _, entry in ipairs(client.ns.Stats.Window().Members._provider.elements) do
        names[#names + 1] = entry.name
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
world.officerRanks = { [1] = true }
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

H.section("Roster: the game's own")
-- The Statistics button is on the guild window's title bar (see
-- test_kinfolk.lua): nothing of ours on the Roster tab, and the game's
-- Offline members box stays in its place.
local button = ns.Stats.guildWindowButton
H.check(button ~= nil and button._parent == env.CommunitiesFrame and button:IsShown(), "a Statistics button on the guild window")
H.eq(ns.RosterView.statsButton, nil, "none on the Roster tab")
H.eq(list.ShowOfflineButton._point, nil, "the game's Offline members box is not moved")
-- A script of the guild window or its list hooked with HookScript runs in
-- the same execution as the scripts of the window's children that follow
-- it, and taints the roster's rows (and then the game blocks changing a
-- member's notes): the guild's addons hook their methods securely instead.
local function Hooked(frame)
    local names = {}
    for name in pairs(rawget(frame, "_hooked") or {}) do
        names[#names + 1] = name
    end
    return table.concat(names, ", ")
end
H.eq(Hooked(env.CommunitiesFrame), "", "no addon hooks a script of the guild window")
H.eq(Hooked(list), "", "nor of its roster")
local everyone = "Kantrul Steadyshot, Nedyar Cazador, Caja Fuerte, Viejo Guerrero, Nedyar Mago"
list:RefreshListDisplay()
local refreshes = list._refreshes
H.eq(InRoster(officer), everyone, "the roster lists everyone, the bank character too")
H.check(list.ScrollBox._provider == list._made, "in the list the game made: rows our code drew would block notes and ranks")
Filters.ToggleKind("main")
Filters.Invalidate()
world:RunFor(5)
H.check(list._refreshes == refreshes and list.ScrollBox._provider == list._made,
    "changing the filters, or the guild's data, never draws the roster again")
Filters.ToggleKind("all")
Errors(world, "the game's own")

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
H.check(byClass.HUNTER == 2 and byClass.MAGE == 1 and byClass.WARRIOR == 2 and counts.classTotal == 5,
    "classes: 2 hunters, 1 mage, 2 warriors (the bank character too)")
H.eq(counts.classes[1].class, "HUNTER", "the most numerous first (ties by name)")
H.check(counts.levels[1] == 1 and counts.levels[2] == 1 and counts.levels[4] == 1 and counts.levels[7] == 2,
    "levels: one of 1-9 (the bank character), one of 10-19, one of 30-39, two of 60")
Filters.ToggleKind("bank")
counts = Filters.Counts()
H.check(counts.classTotal == 1 and counts.levels[7] == 0 and counts.kinds.main == 3 and counts.all == 5,
    "with one kind chosen, the other numbers count that kind; the kinds' own numbers do not")
Filters.ToggleKind("bank")
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
H.check(window._point ~= nil and window._point[2] == env.CommunitiesFrame, "beside the guild window, as tall as it")
-- Dragged elsewhere: it leaves the guild window's side where it was, as tall.
window._left, window._top, window._height = 900, 700, 480
window._scripts.OnDragStart(window)
H.check(window._point[1] == "TOPLEFT" and window._point[2] == env.UIParent and window._point[4] == 900 and window._point[5] == 700,
    "it can be dragged away from the guild window")
window._scripts.OnDragStart(window)
H.eq(window._point[4], 900, "dragged again, it just moves")
Click(button)
Click(button)
H.check(window:IsShown() and window._point[2] == env.CommunitiesFrame, "opened again, it is beside the guild window")
-- The guild tabard on its title bar, as on KinFolk's window.
local guildButton = window.GuildButton
H.check(guildButton ~= nil and guildButton._parent == window and guildButton.Icon ~= nil,
    "a button with the guild tabard on its title bar")
guildButton._scripts.OnEnter(guildButton)
H.eq(env.GameTooltip._text, "Guild", "its tooltip names the guild window")
Click(guildButton)
H.eq(officer.guildToggles, 1, "it closes the game's guild window")
Click(guildButton)
H.eq(officer.guildToggles, 2, "and opens it again")
H.check(window:IsShown(), "the Statistics window stays open")
local cards = window.kindCards
H.check(cards.main.Number._text == "3" and cards.alt.Number._text == "1" and cards.bank.Number._text == "1" and cards.all.Number._text == "5",
    "a card for each kind, with its number")
H.check(cards.all._point[2] == 0 and cards.main._point[2] > 0, "All is the first card, on the left")
local function Chosen()
    local chosen = {}
    for _, kind in ipairs({ "all", "main", "alt", "bank" }) do
        if cards[kind].Selected:IsShown() then
            chosen[#chosen + 1] = kind
        end
    end
    return table.concat(chosen, ", ")
end
H.eq(Chosen(), "all", "chosen at first, alone")
local all = "Caja Fuerte, Kantrul Steadyshot, Nedyar Cazador, Nedyar Mago, Viejo Guerrero"
H.eq(Listed(officer), all, "the list beside the numbers: every member, by name")
H.eq(window.MembersHeading._text, "Members (5)", "and how many")
-- Offline members: the game's own box, beside the Characters heading.
local offlineBox = window.OfflineBox
H.check(offlineBox ~= nil and offlineBox._point[2] == window.KindsHeading and offlineBox.Text._text == "Offline members",
    "the game's Offline members box beside the Characters heading, with the game's text")
H.check(offlineBox:GetChecked(), "ticked, as the game's roster box was left")
local before = list._refreshes
offlineBox:SetChecked(false)
Click(offlineBox)
world:RunFor(1)
H.eq(cards.all.Number._text, "2", "unticked: the numbers count the online members only")
H.eq(Listed(officer), "Kantrul Steadyshot, Nedyar Mago", "and the list too")
H.check(list._refreshes == before and list.showOfflinePlayers == nil and officer.showOffline == true,
    "the game's roster is left as it was (telling it would make our code draw its rows)")
list:SetShowOfflinePlayers(false)
list:SetShowOfflinePlayers(true)
world:RunFor(1)
H.check(offlineBox:GetChecked() and cards.all.Number._text == "5", "a click on the game's own box: ours follows it")
list:SetShowOfflinePlayers(false)
world:RunFor(1)
H.check(not offlineBox:GetChecked() and cards.all.Number._text == "2", "both ways")
list:SetShowOfflinePlayers(true)
world:RunFor(1)
refreshes = list._refreshes
Click(cards.main)
world:RunFor(1)
H.eq(Chosen(), "main", "a click on Mains chooses it alone")
H.eq(Listed(officer), "Kantrul Steadyshot, Nedyar Cazador, Viejo Guerrero", "only the mains: members without the addon count as mains")
Click(cards.bank)
world:RunFor(1)
H.eq(Chosen(), "bank", "a click on another card chooses that one instead")
H.eq(Listed(officer), "Caja Fuerte", "only the bank character")
Click(cards.bank)
world:RunFor(1)
H.eq(Chosen(), "all", "the chosen card clicked again: All")
Click(cards.alt)
Click(cards.all)
world:RunFor(1)
H.eq(Chosen(), "all", "and All chooses every kind")
H.eq(Listed(officer), all, "in the list")
H.eq(InRoster(officer), everyone, "the roster still lists everyone, as the game does")
Click(cards.main)
world:RunFor(1)
H.eq(Listed(officer), "Kantrul Steadyshot, Nedyar Cazador, Viejo Guerrero", "the list follows the filters")
H.eq(window.MembersHeading._text, "Members (3)", "and so does how many")
Click(cards.all)
world:RunFor(1)

-- Searching the list.
local search = window.Search
local function Search(text)
    search:SetText(text)
    search._scripts.OnTextChanged(search, true)
end
Search("CAZ")
H.eq(Listed(officer), "Nedyar Cazador", "the search box finds a member by name, in any case")
H.eq(window.MembersHeading._text, "Members (1)", "and the heading counts what the list shows")
Search("nedyar94")
H.eq(Listed(officer), "Nedyar Cazador, Nedyar Mago", "or by their player's Discord username")
Click(cards.main)
world:RunFor(1)
H.eq(Listed(officer), "Nedyar Cazador", "among the members the filters let through")
H.check(cards.main.Number._text == "3" and cards.all.Number._text == "5", "the numbers do not count the search")
Click(cards.all)
world:RunFor(1)
Search("zzz")
H.check(window.Nobody:IsShown() and window.MembersHeading._text == "Members (0)", "nobody by that name: the list says so")
Search("")
H.eq(Listed(officer), all, "emptied, everyone again")

-- A member in the list.
local view = window.Members._view
local rowFor = {}
for _, entry in ipairs(window.Members._provider.elements) do
    local row = H.NewObject(officer, "Button")
    view.init(row, entry)
    rowFor[entry.name] = row
end
local cazador = rowFor["Nedyar Cazador"]
H.check(cazador.Name._text:find("Nedyar Cazador", 1, true) ~= nil, "a member's row, in columns: their name")
H.eq(cazador.Level._text, "37", "their level")
H.check(cazador.Status._text:find("1 hours", 1, true) ~= nil,
    "and, offline, how long ago they were online, from the game's guild roster")
H.check(rowFor["Viejo Guerrero"].Status._text:find("2 days", 1, true) and not rowFor["Viejo Guerrero"].Status._text:find("Offline", 1, true),
    "told as the game's roster tells it")
H.check(cazador.Name._text:find("|cff808080Nedyar Cazador", 1, true) ~= nil, "grey while offline")
H.check(rowFor["Nedyar Mago"].Level._text == "12" and rowFor["Nedyar Mago"].Status._text:find("Online", 1, true)
    and not rowFor["Nedyar Mago"].Name._text:find("|cff808080", 1, true), "online: Online, the name in its class's color")

-- Sorting by the columns' headers.
local headers = window.headers
H.check(headers.name._text == "Name" and headers.level._text == "Level" and headers.online._text == "Last online",
    "a header over each column")
Click(headers.level)
world:RunFor(1)
H.eq(Listed(officer), "Kantrul Steadyshot, Viejo Guerrero, Nedyar Cazador, Nedyar Mago, Caja Fuerte",
    "a click on Level sorts by it, the highest first (ties by name)")
Click(headers.level)
world:RunFor(1)
H.eq(Listed(officer), "Caja Fuerte, Nedyar Mago, Nedyar Cazador, Kantrul Steadyshot, Viejo Guerrero", "another click, the other way")
Click(headers.online)
world:RunFor(1)
H.eq(Listed(officer), "Kantrul Steadyshot, Nedyar Mago, Nedyar Cazador, Caja Fuerte, Viejo Guerrero",
    "Last online: those online first, then the most recent")
Click(headers.name)
Click(headers.name)
world:RunFor(1)
H.eq(Listed(officer), "Viejo Guerrero, Nedyar Mago, Nedyar Cazador, Kantrul Steadyshot, Caja Fuerte", "Name, twice: Z to A")
Click(headers.name)
world:RunFor(1)
H.eq(Listed(officer), all, "and A to Z again")
tooltip._owner = nil
cazador._scripts.OnEnter(cazador)
H.check(tooltip._owner == cazador and Lines():find("Discord: nedyar94", 1, true) and Lines():find("Alts: Nedyar Mago", 1, true),
    "its tooltip has who plays it")
H.check(Lines():find("Click to manage their player.", 1, true) ~= nil, "and, for an officer, what a click does")
Click(cazador)
local myData = ns.MyData.Window()
H.check(myData and myData:IsShown() and myData.view and myData.view.dc == "nedyar94", "which opens their player in My data")
myData:Hide()
local altView = alt.ns
alt.env.GameTooltip._lines = {}
rawset(alt.env.GameTooltip, "SetOwner", function(self, owner)
    self._owner, self._lines = owner, {}
end)
altView.Stats.Toggle()
local altRow = H.NewObject(alt, "Button")
altView.Stats.Window().Members._view.init(altRow, altView.Stats.Window().Members._provider.elements[1])
altRow._scripts.OnEnter(altRow)
H.check(not table.concat(alt.env.GameTooltip._lines, " / "):find("Click to manage", 1, true), "not for another member")
Click(altRow)
H.check(altView.MyData.Window() == nil or not altView.MyData.Window():IsShown(), "whose click does nothing")
altView.Stats.Hide()

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
-- The specializations, before a class is chosen: every class's.
local function SpecSections()
    local shown = {}
    for _, section in ipairs(window.SpecBar.sections) do
        if section:IsShown() then
            shown[#shown + 1] = section
        end
    end
    return shown
end
local function SpecNames()
    local names = {}
    for _, section in ipairs(SpecSections()) do
        names[#names + 1] = section.item.class .. " " .. section.item.tab
    end
    return table.concat(names, ", ")
end
H.check(window.SpecBar:IsShown() and window.SpecHeading._text == "Specializations", "the specializations' bar shows with no class chosen")
local levelsY = window.LevelsHeading._point[3]
H.check(window.Dual:IsShown(), "with the line on dual specs")
H.eq(SpecNames(), "HUNTER 1, HUNTER 2, HUNTER 3, MAGE 1",
    "with every class's, in the class bar's order (the warriors have no builds)")
local mageSpec = SpecSections()[4]
Click(mageSpec)
world:RunFor(1)
H.check(Filters.spec and Filters.spec.class == "MAGE" and Filters.spec.tab == 1 and Filters.class == nil,
    "a click on one filters by it, without choosing its class")
H.eq(Listed(officer), "Nedyar Mago", "the list shows that specialization's members")
H.eq(SpecNames(), "HUNTER 1, HUNTER 2, HUNTER 3, MAGE 1", "and the bar still has every class's")
H.check(SpecSections()[4].item.chosen and not SpecSections()[1].item.chosen, "the chosen one stands out")
Click(SpecSections()[4])
world:RunFor(1)
H.eq(Filters.spec, nil, "clicked again, no longer")
Filters.ToggleSpec("HUNTER", 3)
Click(hunter)
H.eq(Filters.class, "HUNTER", "a click on a class filters by it")
H.check(Filters.spec and Filters.spec.class == "HUNTER", "and keeps a specialization of that class")
world:RunFor(1)
H.eq(Listed(officer), "Kantrul Steadyshot", "both apply")
Filters.ToggleSpec("HUNTER", 3)
world:RunFor(1)
H.eq(Listed(officer), "Kantrul Steadyshot, Nedyar Cazador", "the list shows the hunters")
H.eq(window.SpecHeading._text, "Specializations: Hunter", "and the bar their specializations")
counts = Filters.Counts()
local hunters = counts.specs.HUNTER
H.check(counts.specTotal == 2 and hunters[1].count == 1 and hunters[2].count == 1 and hunters[3].count == 1 and counts.specs.MAGE == nil,
    "the main's two specs count in both trees, the officer's in the third; no other class")
H.check(hunters[1].primary == 1 and hunters[2].secondary == 1 and hunters[3].primary == 1,
    "told apart: in the primary build, or only in the secondary")
H.eq(counts.dual, 1, "one hunter has two different specializations")
H.check(window.Dual:IsShown() and window.Dual._text:find("1", 1, true) ~= nil, "and the window says so")
H.eq(SpecNames(), "HUNTER 1, HUNTER 2, HUNTER 3", "a section for each of the three trees")
Filters.ToggleSpec("HUNTER", 2)
world:RunFor(1)
H.eq(Listed(officer), "Nedyar Cazador", "a specialization filters by it, also when only the secondary build has it")
Filters.ToggleSpec("HUNTER", 2)
world:RunFor(1)
H.eq(Listed(officer), "Kantrul Steadyshot, Nedyar Cazador", "clicked again, no longer")
-- The warriors have no builds in Guild Builds.
Filters.ToggleClass("WARRIOR")
world:RunFor(1)
counts = Filters.Counts()
H.check(next(counts.specs) == nil and counts.specTotal == 0, "members without builds count in no specialization")
H.check(window.SpecBar.Empty:IsShown(), "the bar has no section for them")
H.check(not window.Dual:IsShown() and window.LevelsHeading._point[3] == levelsY,
    "without the line on dual specs, the levels stay where they were")
H.eq(Listed(officer), "Caja Fuerte, Viejo Guerrero", "the class lists them")
Filters.ToggleClass("HUNTER")
world:RunFor(1)
Filters.ToggleSpec("HUNTER", 3)
Click(hunter)
H.check(Filters.class == nil and Filters.spec == nil, "the class clicked again: no class filter, nor its specialization's")
world:RunFor(1)
H.eq(SpecNames(), "HUNTER 1, HUNTER 2, HUNTER 3, MAGE 1", "the bar has every class's specializations again")
H.eq(Listed(officer), all, "everyone again")

-- Levels.
Click(window.levelCards[7])
world:RunFor(1)
H.eq(Listed(officer), "Kantrul Steadyshot, Viejo Guerrero", "the level 60 card filters by it")
H.eq(window.levelCards[7].Label._text, "60", "labelled 60")
H.check(cards.main.Number._text == "2" and cards.alt.Number._text == "0", "the kind cards count the level filter in")
Click(window.levelCards[2])
world:RunFor(1)
H.eq(Listed(officer), "Nedyar Mago", "another range replaces it")
H.eq(window.levelCards[2].Label._text, "10-19", "labelled 10-19")
Click(cards.bank)
world:RunFor(1)
H.check(window.Nobody:IsShown() and window.MembersHeading._text == "Members (0)", "a list with nobody says so")
-- Closing the window takes its filters away.
Filters.ToggleClass("MAGE")
search:SetText("mago")
window:Hide()
window._scripts.OnHide(window)
H.check(Filters.kind == nil and Filters.class == nil and Filters.level == nil, "closing the window removes its filters, the kind too")
H.eq(search:GetText(), "", "and empties its search box")
local names = {}
for _, entry in ipairs(Filters.Listed()) do
    names[#names + 1] = entry.name
end
H.eq(table.concat(names, ", "), all, "so it opens with All chosen again")
H.check(list._refreshes == refreshes and list.ScrollBox._provider == list._made,
    "the roster was never drawn by Bot'tar Sync")
H.eq(InRoster(officer), everyone, "and lists everyone")
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
