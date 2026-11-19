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
-- at once. A row too narrow for its text shows it whole in a tooltip.
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

local function UpdateSave()
    local name = ns.Profile.CleanDiscord(window.Input:GetText())
    local text = strtrim(window.Input:GetText() or "")
    window.Save:SetEnabled(name ~= nil and name ~= ns.Profile.Own().dc)
    window.Invalid:SetShown(name == nil and text ~= "")
end

local function SaveName()
    local name = ns.Profile.CleanDiscord(window.Input:GetText())
    if not name then
        return
    end
    window.Input:ClearFocus()
    if name ~= ns.Profile.Own().dc then
        ns.Profile.SetDiscord(name)
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
            ns.Profile.SetMain(self.guid, self:GetChecked())
        end)
        row.Kind = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.Kind:SetPoint("LEFT", row.Main, "RIGHT", 2, 0)
        row.Kind:SetJustifyH("LEFT")
        -- Takes an added character out of the list.
        row.Remove = CreateFrame("Button", nil, row)
        row.Remove:SetSize(16, 16)
        row.Remove:SetPoint("RIGHT", -4, 0)
        row.Remove.Icon = row.Remove:CreateTexture(nil, "ARTWORK")
        row.Remove.Icon:SetAllPoints()
        row.Remove.Icon:SetAtlas("common-icon-redx")
        row.Remove:SetHighlightAtlas("common-icon-redx", "ADD")
        row.Remove:SetScript("OnClick", function(self)
            ns.Profile.Remove(self.guid)
        end)
        row.Remove:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["Remove from your characters"])
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
    row.Main:SetEnabled(ns.Profile.HasName() and item.state ~= "other")
    row.Main:SetShown(item.state ~= "other")
    row.Kind:SetText(item.state ~= "other" and (item.main and L["Main"] or L["Alt"]) or "")
    if item.main then
        row.Kind:SetTextColor(1, 0.82, 0)
    else
        row.Kind:SetTextColor(0.6, 0.6, 0.6)
    end
    row.Remove.guid = item.guid
    row.Remove:SetShown(item.state ~= "mine")
end

-- Searching characters to add -----------------------------------------------------------------

-- The guild's characters that can be added whose name has the text typed
-- (any case): those with a word that starts with it first, then the rest,
-- each by name. nil while nothing is typed.
function MyData.Matches(text)
    local query = strtrim(text or ""):lower()
    if query == "" then
        return nil
    end
    local first, rest = {}, {}
    for _, item in ipairs(ns.Profile.Addable()) do
        local name = item.name:lower()
        local at = name:find(query, 1, true)
        if at == 1 or (at and name:sub(at - 1, at - 1) == " ") then
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

local UpdateResults

local function AddResult(item)
    if not item then
        return
    end
    local _, why = ns.Profile.Add(item.guid)
    if why == "full" then
        ns.Print(L["Your list holds up to %d characters."], ns.Pack.LIMITS.profile)
    end
    window.Search:SetText("")
    window.Search:ClearFocus()
    UpdateResults()
end

local function ResultRow(i)
    local results = window.Results
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
            AddResult(self.item)
        end)
        results.rows[i] = row
    end
    return row
end

-- Shows the characters that match what is typed, above the search box.
function UpdateResults()
    local results = window.Results
    local matches = MyData.Matches(window.Search:GetText())
    window.matches = matches
    if not matches then
        results:Hide()
        return
    end
    local shown = math.min(#matches, MyData.MAX_RESULTS)
    window.selected = shown > 0 and math.max(1, math.min(window.selected or 1, shown)) or nil
    for i = 1, shown do
        local row = ResultRow(i)
        row.item = matches[i]
        row.Text:SetText(NameAndLevel(matches[i]))
        row.Selected:SetShown(i == window.selected)
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
        results.Note:SetText(L["No character to add by that name."])
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

-- Up and down choose among the results, Enter adds the chosen one.
local function SearchArrow(_, key)
    local count = window.matches and math.min(#window.matches, MyData.MAX_RESULTS) or 0
    if count == 0 then
        return
    end
    if key == "UP" then
        window.selected = window.selected > 1 and window.selected - 1 or count
    elseif key == "DOWN" then
        window.selected = window.selected < count and window.selected + 1 or 1
    end
    UpdateResults()
end

local function CreateSearch()
    -- The game's search box, with its magnifying glass and clear button.
    local search = CreateFrame("EditBox", nil, window, "SearchBoxTemplate")
    search:SetSize(MyData.WIDTH - 44, 20)
    search:SetPoint("BOTTOMLEFT", 22, 14)
    search:SetAutoFocus(false)
    search:SetMaxLetters(40)
    if search.Instructions then
        search.Instructions:SetText(L["Add a character: type their name"])
    end
    -- After the template's own (instructions and clear button).
    search:HookScript("OnTextChanged", function(_, userInput)
        if userInput then
            window.selected = 1
        end
        UpdateResults()
    end)
    search:SetScript("OnEnterPressed", function()
        AddResult(window.matches and window.selected and window.matches[window.selected])
    end)
    search:SetScript("OnArrowPressed", SearchArrow)
    window.Search = search

    -- The matches, in a tooltip-like box above it.
    local results = CreateFrame("Frame", nil, window, "TooltipBackdropTemplate")
    results:SetPoint("BOTTOMLEFT", search, "TOPLEFT", -8, 2)
    results:SetPoint("BOTTOMRIGHT", search, "TOPRIGHT", 2, 2)
    results:SetFrameLevel(window:GetFrameLevel() + 20)
    results:EnableMouse(true)
    results.rows = {}
    results.Note = results:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    results:Hide()
    window.Results = results
end

-- Shows what the character's profile says now.
local function Draw()
    local profile = ns.Profile.Own()
    if not window.Input:HasFocus() then
        window.Input:SetText(profile.dc or "")
    end
    UpdateSave()
    window.NoName:SetShown(not ns.Profile.HasName())
    window.Search:SetEnabled(ns.Profile.HasName())
    local items = ns.Profile.MyCharacters()
    window.items = items
    window.ScrollBox:SetDataProvider(CreateDataProvider(items))
    UpdateResults()
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
    window.Label:SetPoint("TOPLEFT", 64, -34)
    window.Label:SetText(L["Discord username"])
    window.Input = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
    window.Input:SetSize(170, 20)
    window.Input:SetPoint("TOPLEFT", 70, -52)
    window.Input:SetAutoFocus(false)
    window.Input:SetMaxLetters(ns.Profile.DISCORD_MAX + 1)
    window.Input:SetScript("OnEnter", MyData.ShowUsernameTooltip)
    window.Input:SetScript("OnLeave", GameTooltip_Hide)
    window.Input:SetScript("OnTextChanged", UpdateSave)
    window.Input:SetScript("OnEnterPressed", SaveName)
    window.Input:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:SetText(ns.Profile.Own().dc or "")
    end)
    window.Save = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    window.Save:SetSize(90, 22)
    window.Save:SetPoint("LEFT", window.Input, "RIGHT", 8, 0)
    window.Save:SetText(SAVE)
    window.Save:SetScript("OnClick", SaveName)
    window.Invalid = window:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
    window.Invalid:SetPoint("TOPLEFT", 64, -76)
    window.Invalid:SetPoint("RIGHT", -12, 0)
    window.Invalid:SetJustifyH("LEFT")
    window.Invalid:SetText(L["Discord usernames have 2 to 32 letters, numbers, _ or . (no spaces)."])
    window.Invalid:Hide()

    -- The characters.
    window.Heading = window:CreateFontString(nil, "ARTWORK", "GameFontNormalMed2")
    window.Heading:SetPoint("TOPLEFT", 14, -100)
    window.Heading:SetText(L["My characters"])
    window.Hint = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    window.Hint:SetPoint("TOPLEFT", window.Heading, "BOTTOMLEFT", 0, -4)
    window.Hint:SetPoint("RIGHT", -14, 0)
    window.Hint:SetJustifyH("LEFT")
    window.Hint:SetText(L["Tick your mains; the others are alts. Add the ones missing with the search box below: they count at once, pending until they log in and accept."])
    local scrollBox = CreateFrame("Frame", nil, window, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 12, -150)
    scrollBox:SetPoint("BOTTOMRIGHT", -28, 44)
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

    -- The search box to add the guild's characters.
    CreateSearch()

    ns.On("DataChanged", MyData.Refresh)
    ns.On("ProfileChanged", MyData.Refresh)
    ns.On("RosterUpdated", MyData.Refresh)
end

-- Opens the window, beside the guild window, or closes it.
function MyData.Toggle()
    if window and window:IsShown() then
        window:Hide()
        return
    end
    if not window then
        CreateWindow()
    end
    Draw()
    window:ClearAllPoints()
    window:SetPoint("CENTER")
    window.docked = true
    window:Show()
    MyData.Place()
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
    communities:HookScript("OnShow", MyData.UpdateGuildButton)
    MyData.UpdateGuildButton()
end

function MyData.Init()
    EventUtil.ContinueOnAddOnLoaded("Blizzard_Communities", SetupGuildWindow)
end
