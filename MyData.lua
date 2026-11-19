-- MyData.lua: the "My data" window, where a member sees and changes their
-- Discord name and marks which of their characters are mains and which alts
-- (Profile.lua keeps and shares them), and the button that opens it on the
-- game's guild window.
--
-- The button sits at the bottom right of the guild window, on the Chat and
-- Roster tabs of the guild (not of other communities): the game's buttons
-- there (Invite Member on Chat, Guild Settings on Roster) move left of it
-- while it shows, and back when it does not. It looks like them: the game's
-- red panel button, as big. Moving them runs none of their code. The game's
-- Guild Settings button is widened to show its whole text, which does not
-- fit in some languages.
--
-- The window lists the player's characters in the guild (Profile.lua's
-- MyCharacters): those that go by their profile, from any of them, and
-- those the player added from the guild roster (the search box at the
-- bottom: the characters whose name has what is typed show above it),
-- pending until each logs in and accepts, or another player's when it
-- already goes by another profile; the added ones can be taken out again.
-- Each has a box: ticked it is a main, unticked an alt; a change is shared
-- at once. A row too narrow for its text shows it whole in a tooltip. What
-- an officer set (Officers.lua) cannot be changed by the player.
--
-- An officer's window has one more search box, at its top: it finds any
-- player of the guild by their username or by the name of a character of
-- theirs, and the window then shows that player's (their username, their
-- characters), to change as the player would, also adding any character of
-- the guild, and taking any out; what they change prevails over what the
-- player says. A character that is nobody's shows alone: giving it a
-- username makes it that player's. My data goes back to their own. A click
-- on a member in the Statistics window's list opens it too (Stats.lua).
-- Not the right-click menu of a member in the roster: an entry an addon
-- adds there taints the menu's closing when clicked, which lays out the
-- roster again, and the game then blocks changing a member's notes or
-- rank.
local _, ns = ...
local L = ns.L

local MyData = {}
ns.MyData = MyData

MyData.ICON = "Interface\\Icons\\INV_Misc_Note_01"
MyData.BUTTON_WIDTH = 130 -- as the game's Invite Member and Guild Settings
MyData.BUTTON_HEIGHT = 20
MyData.GAP = 2 -- between the game's buttons at the bottom of its window
-- Around a button's text, as the game's buttons that fit their text have it
-- (DynamicResizeButton_Resize).
MyData.TEXT_PADDING = 40
MyData.WIDTH = 360
MyData.HEIGHT = 420
-- An officer's window is this much taller: the search of players.
MyData.OFFICER_ROW = 30
MyData.ROW_HEIGHT = 26
-- The search box's results: at most this many, one under another.
MyData.MAX_RESULTS = 8
MyData.RESULT_HEIGHT = 20

local window, guildButton
local settingsWidth -- the game's own width for its Guild Settings button

-- Names and colors --------------------------------------------------------------------

-- A character's name in its class's color, and its level ({ name, class
-- file, level }, as Profile.lua lists them).
local function NameAndLevel(item)
    local name = item.name or "?"
    local color = item.class and C_ClassColor and ns.Try(C_ClassColor.GetClassColor, item.class)
    if color and color.WrapTextInColorCode then
        name = color:WrapTextInColorCode(name)
    end
    if item.level and item.level > 0 then
        name = name .. " |cff999999" .. L["level %d"]:format(item.level) .. "|r"
    end
    return name
end

-- The window ------------------------------------------------------------------------------
--
-- It shows one player at a time (window.view, see Profile.View): ours, or
-- for an officer, any player of the guild, found with the search box at its
-- top, or a character that is nobody's, to give it a player.

-- The player's username and what may change, as Profile.View says.
local function Shown()
    return window.data or {}
end

local function UpdateSave()
    local name = ns.Profile.CleanDiscord(window.Input:GetText())
    local text = strtrim(window.Input:GetText() or "")
    local data = Shown()
    window.Save:SetEnabled(data.canName == true and name ~= nil and name ~= data.name)
    window.Invalid:SetShown(name == nil and text ~= "")
end

local Draw

local function SaveName()
    local name = ns.Profile.CleanDiscord(window.Input:GetText())
    local data = Shown()
    if not name or not data.canName then
        return
    end
    window.Input:ClearFocus()
    if name ~= data.name then
        window.view = ns.Profile.SetDiscord(name, window.view)
        Draw()
    end
end

-- What the Discord name boxes ask for, in their tooltip (also the prompt's).
function MyData.ShowUsernameTooltip(box)
    GameTooltip:SetOwner(box, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["Discord username"])
    GameTooltip:AddLine(L["Your Discord account's unique name, in small letters: Discord shows it in your profile, under your display name. Not your display name, nor the nickname you have on a server."], 1, 1, 1, true)
    GameTooltip:Show()
end

-- A row whose text is cut ("Nedyar Cazador level 37 (thi...") shows it
-- whole in a tooltip.
local function ShowRowTooltip(row)
    if not (row.Name.IsTruncated and row.Name:IsTruncated()) then
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.Name:GetText(), 1, 1, 1)
    GameTooltip:Show()
end

local function InitRow(row, item)
    if not row.Name then
        row:EnableMouse(true)
        row:SetScript("OnEnter", ShowRowTooltip)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.Name:SetPoint("LEFT", 6, 0)
        row.Name:SetPoint("RIGHT", -140, 0)
        row.Name:SetJustifyH("LEFT")
        row.Name:SetWordWrap(false)
        row.Main = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.Main:SetSize(24, 24)
        row.Main:SetPoint("RIGHT", -84, 0)
        row.Main:SetScript("OnClick", function(self)
            ns.Profile.SetMain(self.guid, self:GetChecked(), window.view)
        end)
        row.Kind = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.Kind:SetPoint("LEFT", row.Main, "RIGHT", 2, 0)
        row.Kind:SetJustifyH("LEFT")
        -- Takes a character out of the list.
        row.Remove = CreateFrame("Button", nil, row)
        row.Remove:SetSize(16, 16)
        row.Remove:SetPoint("RIGHT", -4, 0)
        row.Remove.Icon = row.Remove:CreateTexture(nil, "ARTWORK")
        row.Remove.Icon:SetAllPoints()
        row.Remove.Icon:SetAtlas("common-icon-redx")
        row.Remove:SetHighlightAtlas("common-icon-redx", "ADD")
        row.Remove:SetScript("OnClick", function(self)
            ns.Profile.Remove(self.guid, window.view)
        end)
        row.Remove:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(window.view and L["Remove from their characters"] or L["Remove from your characters"])
            GameTooltip:Show()
        end)
        row.Remove:SetScript("OnLeave", GameTooltip_Hide)
    end
    local text = NameAndLevel(item)
    if item.own then
        text = text .. " |cff999999" .. L["(this character)"] .. "|r"
    elseif item.state == "pending" then
        text = text .. " |cff999999" .. L["(pending)"] .. "|r"
    elseif item.state == "other" then
        text = text .. " |cffff6060" .. L["(another player's)"] .. "|r"
    end
    row.Name:SetText(text)
    row.Main.guid = item.guid
    row.Main:SetChecked(item.main)
    row.Main:SetEnabled(item.canMain == true)
    row.Main:SetShown(item.state ~= "other")
    row.Kind:SetText(item.state ~= "other" and (item.main and L["Main"] or L["Alt"]) or "")
    if item.main then
        row.Kind:SetTextColor(1, 0.82, 0)
    else
        row.Kind:SetTextColor(0.6, 0.6, 0.6)
    end
    row.Remove.guid = item.guid
    row.Remove:SetShown(item.canRemove == true)
end

-- Search boxes ----------------------------------------------------------------------------
--
-- A search box shows what matches the text typed in a tooltip-like box
-- beside it: up and down choose among them, and Enter or a click takes the
-- chosen one. A picker = { box, results (rows, Note), Match(text) (a list,
-- nil while nothing is typed), Text(item), Take(item), none (the note when
-- nothing matches) }, with matches and selected while it shows.

-- Items whose name (NameOf) has the text typed (any case): those with a
-- word that starts with it first, then the rest, each in the given order.
local function Find(items, text, NameOf)
    local query = strtrim(text or ""):lower()
    if query == "" then
        return nil
    end
    local first, rest = {}, {}
    for _, item in ipairs(items) do
        local name = NameOf(item):lower()
        local at = name:find(query, 1, true)
        if at == 1 or (at and name:sub(at - 1, at - 1):find("[%s%._]")) then
            first[#first + 1] = item
        elseif at then
            rest[#rest + 1] = item
        end
    end
    for _, item in ipairs(rest) do
        first[#first + 1] = item
    end
    return first
end

local function ItemName(item)
    return item.name
end

-- The guild's characters the view's player can be given whose name has the
-- text typed. nil while nothing is typed.
function MyData.Matches(text)
    return Find(ns.Profile.Addable(window and window.view), text, ItemName)
end

-- For an officer: the players whose username has the text, then the
-- characters whose name has it ({ player = username, count } or a
-- character as Profile.Addable lists them, owner = its player's username).
function MyData.PlayerMatches(text)
    local players, who = ns.Profile.Players()
    local names = {}
    for name, count in pairs(players) do
        names[#names + 1] = { player = name, count = count }
    end
    table.sort(names, function(a, b)
        return a.player < b.player
    end)
    local list = Find(names, text, function(item)
        return item.player
    end)
    if not list then
        return nil
    end
    local characters = {}
    for guid, entry in pairs(ns.Roster.members) do
        local resolved = who[guid]
        characters[#characters + 1] = {
            guid = guid, name = entry.n or guid, level = entry.l or 0, class = entry.c,
            owner = resolved and resolved.dc or nil,
        }
    end
    table.sort(characters, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    for _, item in ipairs(Find(characters, text, ItemName)) do
        list[#list + 1] = item
    end
    return list
end

-- A character's line in the matches, with the username of its player.
local function CharacterText(item)
    local text = NameAndLevel(item)
    if item.owner then
        text = text .. " |cff999999(" .. item.owner .. ")|r"
    end
    return text
end

local function PlayerText(item)
    if item.player then
        return "|cffffd100" .. item.player .. "|r |cff999999"
            .. L["%d |4character:characters;"]:format(item.count) .. "|r"
    end
    return CharacterText(item)
end

local UpdatePicker

local function Take(picker, item)
    if not item then
        return
    end
    picker.box:SetText("")
    picker.box:ClearFocus()
    picker.Take(item)
    UpdatePicker(picker)
end

local function ResultRow(picker, i)
    local results = picker.results
    local row = results.rows[i]
    if not row then
        row = CreateFrame("Button", nil, results)
        row:SetHeight(MyData.RESULT_HEIGHT)
        row:SetPoint("TOPLEFT", 6, -6 - (i - 1) * MyData.RESULT_HEIGHT)
        row:SetPoint("RIGHT", -6, 0)
        row.Text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.Text:SetPoint("LEFT", 4, 0)
        row.Text:SetPoint("RIGHT", -4, 0)
        row.Text:SetJustifyH("LEFT")
        row.Text:SetWordWrap(false)
        row.Selected = row:CreateTexture(nil, "BACKGROUND")
        row.Selected:SetAllPoints()
        row.Selected:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.Selected:SetBlendMode("ADD")
        row.Selected:SetAlpha(0.5)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:SetScript("OnClick", function(self)
            Take(picker, self.item)
        end)
        results.rows[i] = row
    end
    return row
end

-- Shows what matches the text typed.
function UpdatePicker(picker)
    local results = picker.results
    local matches = picker.Match(picker.box:GetText())
    picker.matches = matches
    if not matches then
        results:Hide()
        return
    end
    local shown = math.min(#matches, MyData.MAX_RESULTS)
    picker.selected = shown > 0 and math.max(1, math.min(picker.selected or 1, shown)) or nil
    for i = 1, shown do
        local row = ResultRow(picker, i)
        row.item = matches[i]
        row.Text:SetText(picker.Text(matches[i]))
        row.Selected:SetShown(i == picker.selected)
        row:Show()
    end
    for i = shown + 1, #results.rows do
        results.rows[i].item = nil
        results.rows[i]:Hide()
    end
    local lines = shown
    results.Note:ClearAllPoints()
    results.Note:SetPoint("TOPLEFT", 10, -6 - shown * MyData.RESULT_HEIGHT)
    if #matches == 0 then
        results.Note:SetText(picker.none)
        lines = 1
    elseif #matches > shown then
        results.Note:SetText(L["%d more: keep typing."]:format(#matches - shown))
        lines = shown + 1
    else
        results.Note:SetText("")
    end
    results:SetHeight(lines * MyData.RESULT_HEIGHT + 12)
    results:Show()
end

-- Up and down choose among the matches.
local function PickerArrow(picker, key)
    local count = picker.matches and math.min(#picker.matches, MyData.MAX_RESULTS) or 0
    if count == 0 then
        return
    end
    if key == "UP" then
        picker.selected = picker.selected > 1 and picker.selected - 1 or count
    elseif key == "DOWN" then
        picker.selected = picker.selected < count and picker.selected + 1 or 1
    end
    UpdatePicker(picker)
end

-- The game's search box, with its magnifying glass and clear button, and
-- its matches above it (below: under it).
local function CreatePicker(picker, width, instructions, below)
    local box = CreateFrame("EditBox", nil, window, "SearchBoxTemplate")
    box:SetSize(width, 20)
    box:SetAutoFocus(false)
    box:SetMaxLetters(40)
    if box.Instructions then
        box.Instructions:SetText(instructions)
    end
    -- After the template's own (instructions and clear button).
    box:HookScript("OnTextChanged", function(_, userInput)
        if userInput then
            picker.selected = 1
        end
        UpdatePicker(picker)
    end)
    box:SetScript("OnEnterPressed", function()
        Take(picker, picker.matches and picker.selected and picker.matches[picker.selected])
    end)
    box:SetScript("OnArrowPressed", function(_, key)
        PickerArrow(picker, key)
    end)
    local results = CreateFrame("Frame", nil, window, "TooltipBackdropTemplate")
    if below then
        results:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -8, -2)
        results:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 2, -2)
    else
        results:SetPoint("BOTTOMLEFT", box, "TOPLEFT", -8, 2)
        results:SetPoint("BOTTOMRIGHT", box, "TOPRIGHT", 2, 2)
    end
    results:SetFrameLevel(window:GetFrameLevel() + 20)
    results:EnableMouse(true)
    results.rows = {}
    results.Note = results:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    results:Hide()
    picker.box, picker.results = box, results
    return picker
end

-- Adds a character of the guild to the player shown.
local function AddCharacter(item)
    local _, why = ns.Profile.Add(item.guid, window.view)
    if why == "full" and window.view then
        ns.Print(L["The officers' changes hold as many characters as they can."])
    elseif why == "full" then
        ns.Print(L["Your list holds up to %d characters."], ns.Pack.LIMITS.profile)
    end
end

-- The view of a player or a character an officer chose.
local function ViewOf(item)
    if item.player then
        return { dc = item.player }
    elseif item.owner then
        return { dc = item.owner }
    end
    return { guid = item.guid }
end

local function CreateSearches()
    local add = CreatePicker({
        Match = MyData.Matches, Text = CharacterText, Take = AddCharacter,
        none = L["No character to add by that name."],
    }, MyData.WIDTH - 44, L["Add a character: type their name"])
    add.box:SetPoint("BOTTOMLEFT", 22, 14)
    window.Search, window.Results, window.adding = add.box, add.results, add

    -- An officer's: any player.
    local players = CreatePicker({
        Match = MyData.PlayerMatches, Text = PlayerText,
        Take = function(item)
            MyData.ShowPlayer(ViewOf(item))
        end,
        none = L["No player nor character by that name."],
    }, MyData.WIDTH - 192, L["Find a player"], true)
    window.PlayerSearch, window.PlayerResults, window.players = players.box, players.results, players
    -- Its box is narrow: what to type, in its tooltip.
    players.box:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Find a player"])
        GameTooltip:AddLine(L["Type their Discord username, or the name of any character of theirs."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    players.box:HookScript("OnLeave", GameTooltip_Hide)
    window.Back = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    window.Back:SetSize(100, 22)
    window.Back:SetPoint("LEFT", players.box, "RIGHT", 8, 0)
    window.Back:SetText(L["My data"])
    window.Back:SetScript("OnClick", function()
        MyData.ShowPlayer(nil)
    end)
end

-- Places what the window holds: an officer's has the search of players at
-- its top, and the rest goes lower.
local function Layout(officer)
    local down = officer and MyData.OFFICER_ROW or 0
    window:SetHeight(MyData.HEIGHT + down)
    window.PlayerSearch:ClearAllPoints()
    window.PlayerSearch:SetPoint("TOPLEFT", 70, -34)
    window.PlayerSearch:SetShown(officer)
    window.Back:SetShown(officer)
    window.Label:ClearAllPoints()
    window.Label:SetPoint("TOPLEFT", 64, -34 - down)
    window.Input:ClearAllPoints()
    window.Input:SetPoint("TOPLEFT", 70, -52 - down)
    window.Invalid:ClearAllPoints()
    window.Invalid:SetPoint("TOPLEFT", 64, -76 - down)
    window.Invalid:SetPoint("RIGHT", -12, 0)
    window.Heading:ClearAllPoints()
    window.Heading:SetPoint("TOPLEFT", 14, -100 - down)
    window.ScrollBox:ClearAllPoints()
    window.ScrollBox:SetPoint("TOPLEFT", 12, -150 - down)
    window.ScrollBox:SetPoint("BOTTOMRIGHT", -28, 44)
end

-- Shows the player of the view now.
function Draw()
    local officer = ns.Officers.AmI()
    if not officer then
        window.view = nil
    end
    local view = window.view
    local data = ns.Profile.View(view)
    window.data = data
    Layout(officer)
    if not view then
        window:SetTitle(L["My data"])
        window.Heading:SetText(L["My characters"])
        window.Hint:SetText(L["Tick your mains; the others are alts. Add the ones missing with the search box below: they count at once, pending until they log in and accept."])
    elseif view.guid then
        window:SetTitle(L["New player"])
        window.Heading:SetText(L["Characters"])
        window.Hint:SetText(L["This character is nobody's: type the Discord username of its player, and it is theirs at once."])
    else
        window:SetTitle(L["Player: %s"]:format(view.dc))
        window.Heading:SetText(L["Characters"])
        window.Hint:SetText(L["Tick their mains; the others are alts. What you change here counts at once, over what the player says."])
    end
    window.Back:SetEnabled(view ~= nil)
    if not window.Input:HasFocus() then
        window.Input:SetText(data.name or "")
    end
    window.Input:SetEnabled(data.canName == true)
    UpdateSave()
    window.NoName:SetShown(not view and data.name == nil)
    window.Search:SetEnabled(data.canAdd == true)
    window.items = data.items
    window.ScrollBox:SetDataProvider(CreateDataProvider(data.items))
    UpdatePicker(window.adding)
    UpdatePicker(window.players)
end

function MyData.Refresh()
    if window and window:IsShown() then
        ns.Debounce("MyData", 0.2, function()
            if window:IsShown() then
                Draw()
            end
        end)
    end
end

local function CreateWindow()
    window = CreateFrame("Frame", "BottarSyncMyData", UIParent, "PortraitFrameTemplate")
    window:SetSize(MyData.WIDTH, MyData.HEIGHT)
    window:SetFrameStrata("HIGH")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self)
        self.docked = false
        self:StartMoving()
    end)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:Hide()
    tinsert(UISpecialFrames, window:GetName())
    window:SetTitle(L["My data"])
    window:SetPortraitToAsset(MyData.ICON)

    -- The Discord name, right of the portrait, with its Save button.
    window.Label = window:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    window.Label:SetText(L["Discord username"])
    window.Input = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
    window.Input:SetSize(170, 20)
    window.Input:SetAutoFocus(false)
    window.Input:SetMaxLetters(ns.Profile.DISCORD_MAX + 1)
    window.Input:SetScript("OnEnter", MyData.ShowUsernameTooltip)
    window.Input:SetScript("OnLeave", GameTooltip_Hide)
    window.Input:SetScript("OnTextChanged", UpdateSave)
    window.Input:SetScript("OnEnterPressed", SaveName)
    window.Input:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:SetText(Shown().name or "")
    end)
    window.Save = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    window.Save:SetSize(90, 22)
    window.Save:SetPoint("LEFT", window.Input, "RIGHT", 8, 0)
    window.Save:SetText(SAVE)
    window.Save:SetScript("OnClick", SaveName)
    window.Invalid = window:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
    window.Invalid:SetJustifyH("LEFT")
    window.Invalid:SetText(L["Discord usernames have 2 to 32 letters, numbers, _ or . (no spaces)."])
    window.Invalid:Hide()

    -- The characters.
    window.Heading = window:CreateFontString(nil, "ARTWORK", "GameFontNormalMed2")
    window.Heading:SetText(L["My characters"])
    window.Hint = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    window.Hint:SetPoint("TOPLEFT", window.Heading, "BOTTOMLEFT", 0, -4)
    window.Hint:SetPoint("RIGHT", -14, 0)
    window.Hint:SetJustifyH("LEFT")
    local scrollBox = CreateFrame("Frame", nil, window, "WowScrollBoxList")
    local scrollBar = CreateFrame("EventFrame", nil, window, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
    local view = CreateScrollBoxListLinearView(0, 0, 0, 0, 0)
    view:SetElementExtent(MyData.ROW_HEIGHT)
    view:SetElementInitializer("Frame", InitRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    window.ScrollBox = scrollBox
    window.NoName = window:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    window.NoName:SetPoint("CENTER", scrollBox)
    window.NoName:SetWidth(MyData.WIDTH - 60)
    window.NoName:SetText(L["Save your Discord username first."])

    -- The search boxes: to add the guild's characters, and an officer's to
    -- find any player.
    CreateSearches()
    Layout(false)

    ns.On("DataChanged", MyData.Refresh)
    ns.On("ProfileChanged", MyData.Refresh)
    ns.On("RosterUpdated", MyData.Refresh)
    ns.On("OfficersChanged", MyData.Refresh)
end

-- Opens the window on a view (nil: ours), beside the guild window.
function MyData.ShowPlayer(view)
    if not window then
        CreateWindow()
    end
    window.view = view
    Draw()
    if not window:IsShown() then
        window:ClearAllPoints()
        window:SetPoint("CENTER")
        window.docked = true
        window:Show()
        MyData.Place()
    end
end

-- Opens the window on the player of a character of the guild (ours: our
-- own view).
function MyData.ShowCharacter(guid)
    local _, who = ns.Profile.Players()
    local player = who[guid]
    if guid == ns.playerGUID or (player and player.dc == ns.Profile.View(nil).name) then
        MyData.ShowPlayer(nil)
    elseif not player then
        MyData.ShowPlayer({ guid = guid })
    else
        MyData.ShowPlayer({ dc = player.dc })
    end
end

-- Opens the window on our own data, or closes it.
function MyData.Toggle()
    if window and window:IsShown() then
        window:Hide()
        return
    end
    MyData.ShowPlayer(nil)
end

-- Places the window beside the guild window, or beside the Statistics
-- window while it shows (Stats.lua); not once the player moved it.
function MyData.Place()
    if not (window and window:IsShown() and window.docked) then
        return
    end
    local stats = ns.Stats.IsShown() and ns.Stats.Window()
    local beside = stats or (CommunitiesFrame and CommunitiesFrame:IsShown() and CommunitiesFrame)
    if beside then
        window:ClearAllPoints()
        window:SetPoint("TOPLEFT", beside, "TOPRIGHT", 10, 0)
    end
end

function MyData.Window()
    return window
end

-- The button on the guild window --------------------------------------------------------

-- Whether the guild window shows the guild's Chat or Roster.
local function ShowsGuildChatOrRoster(communities)
    local modes = COMMUNITIES_FRAME_DISPLAY_MODES
    local mode = communities.GetDisplayMode and communities:GetDisplayMode()
    if not modes or not mode or (mode ~= modes.CHAT and mode ~= modes.ROSTER) then
        return false
    end
    local clubId = communities.GetSelectedClubId and communities:GetSelectedClubId()
    local info = clubId and C_Club and ns.Try(C_Club.GetClubInfo, clubId)
    return ns.CanRead(info) and Enum.ClubType ~= nil and info.clubType == Enum.ClubType.Guild
end

-- Widens a button so its whole text shows (never narrower than minWidth).
-- The game's Guild Settings button is too narrow for its text in some
-- languages ("Ajustes de hermanda").
function MyData.FitToText(button, minWidth)
    local text = button.GetFontString and button:GetFontString()
    local width = text and text.GetUnboundedStringWidth and text:GetUnboundedStringWidth()
    if not width and button.GetTextWidth then
        width = button:GetTextWidth()
    end
    if width and width > 0 then
        button:SetWidth(math.max(minWidth, math.ceil(width) + MyData.TEXT_PADDING))
    end
end

-- Shows our button where it belongs, and places the game's buttons left of
-- it while it shows (back in their own place otherwise).
function MyData.UpdateGuildButton()
    local communities = CommunitiesFrame
    if not (guildButton and communities) then
        return
    end
    local shown = ShowsGuildChatOrRoster(communities)
    guildButton:SetShown(shown)
    local invite = communities.InviteButton
    if invite then
        invite:ClearAllPoints()
        if shown then
            invite:SetPoint("RIGHT", guildButton, "LEFT", -MyData.GAP, 0)
        else
            invite:SetPoint("BOTTOMRIGHT", communities, "BOTTOMRIGHT", -5, 5)
        end
    end
    local control = communities.CommunitiesControlFrame
    local settings = control and control.GuildControlButton
    if settings then
        settingsWidth = settingsWidth or settings:GetWidth()
        MyData.FitToText(settings, settingsWidth)
        settings:ClearAllPoints()
        if shown then
            settings:SetPoint("RIGHT", guildButton, "LEFT", -MyData.GAP, 0)
        else
            settings:SetPoint("BOTTOMRIGHT", control, "BOTTOMRIGHT", 0, 0)
        end
    end
end

local function SetupGuildWindow()
    local communities = CommunitiesFrame
    if guildButton or not (communities and communities.CreateTexture) then
        return
    end
    -- Inside the frame that holds the game's Guild Settings button: it shows
    -- on Chat and Roster, and the panels of the guild's other addons (Guild
    -- Professions & Recipes, Guild Bank Alts) fade it and cover it with the
    -- rest of the game's view.
    guildButton = CreateFrame("Button", nil, communities.CommunitiesControlFrame or communities, "UIPanelButtonTemplate")
    guildButton:SetSize(MyData.BUTTON_WIDTH, MyData.BUTTON_HEIGHT)
    guildButton:SetPoint("BOTTOMRIGHT", communities, "BOTTOMRIGHT", -5, 5)
    guildButton:SetText(L["My data"])
    MyData.FitToText(guildButton, MyData.BUTTON_WIDTH)
    guildButton:SetScript("OnClick", MyData.Toggle)
    guildButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["My data"])
        GameTooltip:AddLine(L["Your Discord username, mains and alts, for Bot'tar."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    guildButton:SetScript("OnLeave", GameTooltip_Hide)
    MyData.guildButton = guildButton
    -- The game updates its buttons on every change of tab and of community.
    if communities.UpdateCommunitiesButtons then
        hooksecurefunc(communities, "UpdateCommunitiesButtons", MyData.UpdateGuildButton)
    end
    -- A secure hook, never HookScript: see KinFolk.lua.
    if type(communities.OnShow) == "function" then
        hooksecurefunc(communities, "OnShow", MyData.UpdateGuildButton)
    end
    MyData.UpdateGuildButton()
end

function MyData.Init()
    EventUtil.ContinueOnAddOnLoaded("Blizzard_Communities", SetupGuildWindow)
end
