-- InfoTab.lua: Bot'tar Sync's pieces on the game's Guild Info tab
-- (CommunitiesFrame.GuildDetailsFrame.Info, Blizzard_Communities'
-- GuildInfo.xml), in its left column, three panels laid out like the
-- game's own (a divider, a header, the text under it):
--   - the message of the day, whole: the game shows it in a box three lines
--     high, with arrows to scroll the rest; ours shows all of it, in the
--     game's place for it;
--   - Discord: the guild's Discord link (Officers.lua), which the officers
--     change (an Edit link on its header, as the game's panels have) and
--     anyone copies;
--   - the guild information, from right under the Discord panel down to the
--     bottom (the game's box was 93 pixels high, at the bottom, with an
--     empty panel above it), scrolling when it does not fit.
-- The room comes from the guild challenges, which this version of the game
-- does not have (the game then puts the message of the day at the top and
-- leaves the middle empty). Should the game show challenges, nothing here
-- shows, and the game's tab is as it was.
--
-- The game blocks some actions when an addon's code took part in them
-- (changing the message of the day or the guild information among them),
-- so no code of the game's runs from ours: our frames are our own, on top
-- of the game's pieces, which only turn invisible (their alpha). The
-- guild information's Edit link stays the game's own, as changing it must,
-- moved onto our header (its place and frame level, which run no code of
-- the game's). Secure hooks (hooksecurefunc) and our own events tell our
-- frames when to update; they have no OnShow or OnHide scripts, which
-- would run with the game's own as the tab opens.
--
-- Copying: the game lets no addon write to the clipboard (CopyToClipboard
-- is protected), so the copy button selects the link in its box, for the
-- player's own Ctrl+C.
local _, ns = ...
local L = ns.L

local InfoTab = {}
ns.InfoTab = InfoTab

-- The game's measures (GuildInfo.xml).
InfoTab.TEXT_WIDTH = 246      -- its text boxes
InfoTab.BAR_WIDTH = 223       -- its dividers
InfoTab.BAR_END_WIDTH = 70
InfoTab.BAR_HEIGHT = 16
InfoTab.HEADER_WIDTH, InfoTab.HEADER_HEIGHT = 280, 22
InfoTab.HEADER_X, InfoTab.HEADER_Y = 7, -11 -- a header, from its divider's top left
InfoTab.TEXT_X, InfoTab.TEXT_Y = 14, -1     -- a text box, from its header's bottom left
InfoTab.BAR_FROM_TEXT = -22   -- a divider, from the text above's left edge
InfoTab.TEXT_RIGHT = 263      -- the text boxes' right edge, from the column's left edge
InfoTab.DETAILS_TOP = -4      -- the guild information, in its box
InfoTab.SCROLL_BAR_X, InfoTab.SCROLL_BAR_BOTTOM = 6, -1
InfoTab.EDIT_COLOR = { 0.973, 0.937, 0.580 }
-- Ours.
InfoTab.GAP = 2                -- between a panel's content and the next divider
InfoTab.BOX_HEIGHT = 20
InfoTab.BOX_X, InfoTab.BOX_Y = 19, -4 -- the link's box, from its header's bottom left
InfoTab.BOX_BELOW = 4          -- under the link's box (its border), before the next divider
InfoTab.COPY_SIZE = 18
InfoTab.MIN_TEXT = 12
InfoTab.MIN_DETAILS = 60       -- the guild information's box, at least
InfoTab.BOTTOM = 1             -- its box, above the column's bottom
-- From a panel's content down: the next divider and header.
InfoTab.SECTION_TOP = InfoTab.GAP - InfoTab.HEADER_Y + InfoTab.HEADER_HEIGHT
InfoTab.DISCORD_HEIGHT = InfoTab.SECTION_TOP - InfoTab.BOX_Y + InfoTab.BOX_HEIGHT + InfoTab.BOX_BELOW
InfoTab.DEFAULT_ROOM = 120     -- for the message, while the column cannot be measured
InfoTab.COPY_ICON = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up"
InfoTab.COPY_ICON_FALLBACK = "Interface\\Icons\\INV_Misc_Note_01"

local info, panel, motd, box, edit, copy, details
local gamePieces = {}  -- the game's guild information pieces, made invisible
local gameHeader       -- its header, where its Edit link goes back to
local editing = false
local laidOut = nil    -- whether ours shows, as last laid out

-- The game's layout without guild challenges (CommunitiesGuildInfoFrame_
-- HideChallenges): the message of the day at the top.
local function Applies()
    return info.Header2 ~= nil and not info.Header2:IsShown()
end

-- The message of the day as the game shows it: its markup as plain text.
local function MessageText()
    local text = C_GuildInfo and C_GuildInfo.GetMOTD and ns.Plain(ns.Try(C_GuildInfo.GetMOTD))
    return text and (text:gsub("|", "||")) or ""
end

-- The guild information as the game shows it (infoText: the one just
-- saved, which the game passes on before the server has it).
local function DetailsText(infoText)
    if type(infoText) == "string" then
        return infoText
    end
    local text = C_GuildInfo and C_GuildInfo.GetInfoText and ns.Plain(ns.Try(C_GuildInfo.GetInfoText))
    return text or ""
end

-- The room for the message: the column's height under its top, less our
-- panels, the guild information's box keeping its least height.
local function Room()
    local top = info.MOTDScrollFrame.GetTop and info.MOTDScrollFrame:GetTop()
    local bottom = info.GetBottom and info:GetBottom()
    if not (top and bottom) or top <= bottom then
        return InfoTab.DEFAULT_ROOM
    end
    return top - bottom - InfoTab.DISCORD_HEIGHT - InfoTab.SECTION_TOP + InfoTab.TEXT_Y
        - InfoTab.MIN_DETAILS - InfoTab.BOTTOM
end

-- Whether we may change the link: the game lets us edit the guild
-- information, and the other members' clients count us as an officer.
function InfoTab.CanEdit()
    return CanEditGuildInfo ~= nil and ns.Try(CanEditGuildInfo) == true and ns.Officers.AmI()
end

local function ShowLink()
    box:SetText(ns.Officers.GuildLink() or "")
    box:SetCursorPosition(0)
end

-- The game's guild information pieces: invisible under ours, and its Edit
-- link on our header; or back as the game had them.
local function LayOut(applies)
    if laidOut == applies then
        return
    end
    laidOut = applies
    info.MOTDScrollFrame:SetAlpha(applies and 0 or 1)
    for _, piece in ipairs(gamePieces) do
        piece:SetAlpha(applies and 0 or 1)
    end
    local gameEdit = info.EditDetailsButton
    if gameEdit then
        if applies then
            gameEdit:ClearAllPoints()
            gameEdit:SetPoint("RIGHT", panel.DetailsHeader, "RIGHT", -8, 0)
            gameEdit:SetFrameLevel(panel:GetFrameLevel() + 5)
        elseif gameHeader then
            gameEdit:ClearAllPoints()
            gameEdit:SetPoint("RIGHT", gameHeader, "RIGHT", -8, 0)
        end
    end
end

function InfoTab.Refresh(infoText)
    if not panel then
        return
    end
    local applies = Applies()
    panel:SetShown(applies)
    LayOut(applies)
    if not applies then
        return
    end
    motd.Text:SetHeight(0)
    motd.Text:SetText(MessageText())
    local height = math.max(motd.Text:GetStringHeight() or 0, InfoTab.MIN_TEXT)
    height = math.min(height, math.max(Room(), InfoTab.MIN_TEXT))
    motd.Text:SetHeight(height)
    motd:SetHeight(height)
    local text = DetailsText(infoText)
    if details.Text:GetText() ~= text then
        details.Text:SetText(text)
        details.Child:SetHeight((details.Text:GetStringHeight() or 0) - InfoTab.DETAILS_TOP)
        details:SetVerticalScroll(0)
    end
    local link = ns.Officers.GuildLink()
    if not editing then
        ShowLink()
    end
    box.Empty:SetShown(not link and not editing)
    copy:SetEnabled(link ~= nil and not editing)
    copy.Icon:SetDesaturated(link == nil or editing)
    edit:SetShown(InfoTab.CanEdit() and not editing)
end

-- Editing ------------------------------------------------------------------------------------

local function StopEditing()
    editing = false
    box:ClearFocus()
    InfoTab.Refresh()
end

function InfoTab.StartEditing()
    if not InfoTab.CanEdit() then
        return
    end
    editing = true
    box.Empty:Hide()
    edit:Hide()
    copy:SetEnabled(false)
    box:SetFocus()
    box:HighlightText()
end

function InfoTab.Save()
    if editing then
        ns.Officers.SetGuildLink(box:GetText() or "")
    end
    StopEditing()
end

-- Selects the link, for the player's Ctrl+C.
function InfoTab.Copy()
    if editing or not ns.Officers.GuildLink() then
        return
    end
    box:SetFocus()
    box:HighlightText()
end

-- Setup -----------------------------------------------------------------------------------------

local function ShowTooltip(owner, title, text)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title)
    GameTooltip:AddLine(text, 1, 1, 1, true)
    GameTooltip:Show()
end

-- A divider and a header under a panel's content (below), as the game's:
-- the divider dx from below's left edge, and extra pixels lower than
-- usual. Returns the header.
local function NewSection(below, dx, extra, title)
    local bar = panel:CreateTexture(nil, "ARTWORK")
    bar:SetTexture("Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar")
    bar:SetTexCoord(0, 1, 0, 0.25)
    bar:SetSize(InfoTab.BAR_WIDTH, InfoTab.BAR_HEIGHT)
    bar:SetPoint("TOPLEFT", below, "BOTTOMLEFT", dx, -InfoTab.GAP - extra)
    local barEnd = panel:CreateTexture(nil, "ARTWORK")
    barEnd:SetTexture("Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar")
    barEnd:SetTexCoord(0, 0.29296875, 0.25, 0.5)
    barEnd:SetSize(InfoTab.BAR_END_WIDTH, InfoTab.BAR_HEIGHT)
    barEnd:SetPoint("LEFT", bar, "RIGHT")
    local header = panel:CreateTexture(nil, "BACKGROUND")
    header:SetTexture("Interface\\GuildFrame\\GuildFrame")
    header:SetTexCoord(0.00097656, 0.31445313, 0.93164063, 0.97460938)
    header:SetSize(InfoTab.HEADER_WIDTH, InfoTab.HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", bar, "TOPLEFT", InfoTab.HEADER_X, InfoTab.HEADER_Y)
    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("LEFT", header, "LEFT", 10, 0)
    label:SetText(title)
    header.Label = label
    return header
end

-- The game's guild information pieces: its box, and its divider, header
-- and title (by name, or anchored to them).
local function FindGamePieces()
    local name = info.GetName and info:GetName()
    local bar = name and _G[name .. "Bar2Left"]
    gameHeader = name and _G[name .. "Header3"]
    local pieces = { info.DetailsFrame, bar, gameHeader }
    if info.GetRegions and (bar or gameHeader) then
        for _, region in ipairs({ info:GetRegions() }) do
            local anchor = region.GetPoint and select(2, region:GetPoint(1))
            if anchor ~= nil and (anchor == bar or anchor == gameHeader) then
                pieces[#pieces + 1] = region
            end
        end
    end
    for i = 1, #pieces do
        if pieces[i] and pieces[i].SetAlpha then
            gamePieces[#gamePieces + 1] = pieces[i]
        end
    end
end

local function CreatePanel()
    panel = CreateFrame("Frame", nil, info)
    panel:SetAllPoints(info)
    panel:SetFrameLevel(info.MOTDScrollFrame:GetFrameLevel() + 10)

    -- The message of the day, where the game's box is. It takes the mouse,
    -- so the game's arrows beneath it, invisible, take no clicks.
    motd = CreateFrame("Frame", nil, panel)
    motd:SetPoint("TOPLEFT", info.MOTDScrollFrame, "TOPLEFT")
    motd:SetWidth(InfoTab.TEXT_WIDTH)
    motd:SetHeight(InfoTab.MIN_TEXT)
    motd:EnableMouse(true)
    motd.Text = motd:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    motd.Text:SetPoint("TOPLEFT")
    motd.Text:SetWidth(InfoTab.TEXT_WIDTH)
    motd.Text:SetJustifyH("LEFT")
    motd.Text:SetJustifyV("TOP")
    motd.Text:SetSpacing(2)
    motd.Text:SetTextColor(1, 1, 1)
    motd.Text:SetWordWrap(true)
    InfoTab.motd = motd

    -- Discord.
    local header = NewSection(motd, InfoTab.BAR_FROM_TEXT, 0, "Discord")
    panel.Header = header

    -- Edit, as the game's own link on its panels' headers.
    edit = CreateFrame("Button", nil, panel)
    edit:SetNormalFontObject("GameFontNormalSmall")
    edit:SetText(GUILD_EDIT_TEXT_LINK or EDIT or "Edit")
    local editText = edit:GetFontString()
    if editText then
        editText:SetTextColor(unpack(InfoTab.EDIT_COLOR))
        edit:SetSize((editText:GetStringWidth() or 30) + 4, (editText:GetStringHeight() or 12) + 4)
    end
    edit:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    edit:SetScript("OnClick", InfoTab.StartEditing)
    edit:SetScript("OnEnter", function(self)
        ShowTooltip(self, L["The guild's Discord link"], L["Enter saves it; Esc leaves it as it was."])
    end)
    edit:SetScript("OnLeave", GameTooltip_Hide)
    InfoTab.edit = edit

    -- The link, in a box to select it from.
    box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    box:SetAutoFocus(false)
    box:SetMaxLetters(ns.Pack.LIMITS.link)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetHeight(InfoTab.BOX_HEIGHT)
    box:SetPoint("TOPLEFT", header, "BOTTOMLEFT", InfoTab.BOX_X, InfoTab.BOX_Y)
    box:SetPoint("RIGHT", info, "RIGHT", -(InfoTab.COPY_SIZE + 14), 0)
    box.Empty = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    box.Empty:SetPoint("LEFT", 2, 0)
    box.Empty:SetText(L["No link yet."])
    -- Only an officer, after Edit, changes it: anyone else's typing is
    -- undone, and a click selects it all, ready to copy.
    box:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput and not editing then
            ShowLink()
            self:HighlightText()
        end
    end)
    box:SetScript("OnEnterPressed", function()
        if editing then
            InfoTab.Save()
        else
            box:ClearFocus()
        end
    end)
    box:SetScript("OnEscapePressed", StopEditing)
    box:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        if editing then
            StopEditing()
        end
    end)
    InfoTab.box = box

    copy = CreateFrame("Button", nil, panel)
    copy:SetSize(InfoTab.COPY_SIZE, InfoTab.COPY_SIZE)
    copy:SetPoint("LEFT", box, "RIGHT", 6, 0)
    copy.Icon = copy:CreateTexture(nil, "ARTWORK")
    copy.Icon:SetAllPoints()
    if copy.Icon:SetTexture(InfoTab.COPY_ICON) == false then
        copy.Icon:SetTexture(InfoTab.COPY_ICON_FALLBACK)
    end
    copy:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    copy:SetMotionScriptsWhileDisabled(true)
    copy:SetScript("OnClick", InfoTab.Copy)
    copy:SetScript("OnEnter", function(self)
        ShowTooltip(self, L["Select the link to copy"], L["Selects the link: press Ctrl+C to copy it."])
    end)
    copy:SetScript("OnLeave", GameTooltip_Hide)
    InfoTab.copy = copy

    -- The guild information, down to the column's bottom (the game's own
    -- Edit link goes on this header).
    local detailsHeader = NewSection(box, -InfoTab.BOX_X - InfoTab.HEADER_X, InfoTab.BOX_BELOW,
        GUILD_INFORMATION or "Guild Information")
    panel.DetailsHeader = detailsHeader
    details = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
    details:SetPoint("TOPLEFT", detailsHeader, "BOTTOMLEFT", InfoTab.TEXT_X, InfoTab.TEXT_Y)
    details:SetPoint("BOTTOMRIGHT", info, "BOTTOMLEFT", InfoTab.TEXT_RIGHT, InfoTab.BOTTOM)
    if details.ScrollBar then
        details.ScrollBar:ClearAllPoints()
        details.ScrollBar:SetPoint("TOPLEFT", details, "TOPRIGHT", InfoTab.SCROLL_BAR_X, 0)
        details.ScrollBar:SetPoint("BOTTOMLEFT", details, "BOTTOMRIGHT", InfoTab.SCROLL_BAR_X, InfoTab.SCROLL_BAR_BOTTOM)
        if details.ScrollBar.SetHideIfUnscrollable then
            details.ScrollBar:SetHideIfUnscrollable(true)
        end
    end
    details.Child = CreateFrame("Frame", nil, details)
    details.Child:SetSize(InfoTab.TEXT_WIDTH, InfoTab.MIN_TEXT)
    details:SetScrollChild(details.Child)
    details.Text = details.Child:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    details.Text:SetPoint("TOPLEFT", 0, InfoTab.DETAILS_TOP)
    details.Text:SetWidth(InfoTab.TEXT_WIDTH)
    details.Text:SetJustifyH("LEFT")
    details.Text:SetJustifyV("TOP")
    details.Text:SetSpacing(2)
    details.Text:SetNonSpaceWrap(true)
    details.Text:SetTextColor(1, 1, 1)
    InfoTab.details = details
    InfoTab.panel = panel
end

local function Setup()
    local frame = CommunitiesFrame and CommunitiesFrame.GuildDetailsFrame
    info = frame and frame.Info
    if panel or not (info and info.MOTDScrollFrame and info.Header2) then
        return
    end
    FindGamePieces()
    CreatePanel()
    -- The game's own updates of the tab: its texts (as it opens, when the
    -- roster changes, and as one is saved), who may edit them, and its
    -- layout.
    hooksecurefunc("CommunitiesGuildInfoFrame_UpdateText", function(_, infoText)
        InfoTab.Refresh(infoText)
    end)
    for _, name in ipairs({ "CommunitiesGuildInfoFrame_UpdatePermissions", "CommunitiesGuildInfoFrame_UpdateChallenges",
        "CommunitiesGuildInfoFrame_HideChallenges" }) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, function()
                InfoTab.Refresh()
            end)
        end
    end
    local events = CreateFrame("Frame")
    ns.RegisterEvents(events, "GUILD_MOTD")
    events:SetScript("OnEvent", function()
        InfoTab.Refresh()
    end)
    ns.On("OfficersChanged", function()
        InfoTab.Refresh()
    end)
    ns.On("RosterUpdated", function()
        InfoTab.Refresh()
    end)
    InfoTab.Refresh()
end

function InfoTab.Init()
    EventUtil.ContinueOnAddOnLoaded("Blizzard_Communities", Setup)
end
