-- RosterView.lua: Bot'tar Sync's pieces on the guild's Roster tab of the
-- game's guild window (CommunitiesFrame.MemberList):
--   - a Statistics button, where the game's "Offline members" box was (the
--     box moves right of it), which opens the Statistics window (Stats.lua);
--   - right of that box, three boxes for the kinds of characters the roster
--     shows: Mains and Alts (ticked at first) and Banks (Filters.lua);
--   - the roster lists only the members the filters let through;
--   - a member's tooltip always shows (the game's only did when a text was
--     cut), with their player's Discord username, mains and alts.
--
-- The game builds the list in RefreshListDisplay, on every change (roster,
-- sort, offline box, tab, community); a hook after it takes out the members
-- the filters hide. The list's rows are then set up from addon code, which
-- the game's code reads later (a whisper from a row's menu...). Nothing
-- here runs while the roster shows another community.
local _, ns = ...
local L = ns.L
local Filters = ns.Filters

local RosterView = {}
ns.RosterView = RosterView

-- The game's place for its "Offline members" box: above the list's top
-- left corner.
local OFFLINE_X, OFFLINE_Y = 0, 26
RosterView.BUTTON_Y = 31   -- our button, level with that box
RosterView.BUTTON_HEIGHT = 22
RosterView.GAP = 10        -- between the boxes
local DISCORD_COLOR = { 0.6, 0.65, 1 }

local memberList, statsButton
local checks = {}
local offlineMoved = false
local hooked = setmetatable({}, { __mode = "k" })

local function IsGuild(list)
    local info = list.GetSelectedClubInfo and ns.Try(list.GetSelectedClubInfo, list)
    return ns.CanRead(info) and Enum.ClubType ~= nil and ns.Plain(info.clubType) == Enum.ClubType.Guild
end

-- The roster of the guild, on the Roster tab (where the game shows its
-- columns and its "Offline members" box).
local function Active(list)
    return list.expandedDisplay == true and IsGuild(list)
end

-- The list ---------------------------------------------------------------------------------

local function Keep(data)
    local info = type(data) == "table" and data.memberInfo
    if not ns.CanRead(info) or info.professionHeaderId then
        return true
    end
    return Filters.Shows(ns.Plain(info.guid))
end

-- Our boxes show the kinds shown, and the game's box moves for our button.
local function UpdateControls(list)
    local active = Active(list)
    statsButton:SetShown(active)
    local kinds = Filters.Kinds()
    for _, check in ipairs(checks) do
        check:SetShown(active)
        check:SetChecked(kinds[check.kind])
    end
    local offline = list.ShowOfflineButton
    if offline and offlineMoved ~= active then
        offlineMoved = active
        offline:ClearAllPoints()
        if active then
            offline:SetPoint("LEFT", statsButton, "RIGHT", 6, 0)
        else
            offline:SetPoint("BOTTOMLEFT", list, "TOPLEFT", OFFLINE_X, OFFLINE_Y)
        end
    end
end

-- Runs after the game fills the list: the members the filters hide go.
-- Nothing is set when none must go.
local function FilterList(list)
    UpdateControls(list)
    if not Active(list) then
        return
    end
    local scrollBox = list.ScrollBox
    local provider = scrollBox and scrollBox.GetDataProvider and scrollBox:GetDataProvider()
    if not (provider and provider.ForEach) then
        return
    end
    local hide = false
    provider:ForEach(function(data)
        if not Keep(data) then
            hide = true
        end
    end)
    if hide then
        local shown = CreateDataProvider()
        provider:ForEach(function(data)
            if Keep(data) then
                shown:Insert(data)
            end
        end)
        scrollBox:SetDataProvider(shown, ScrollBoxConstants.RetainScrollPosition)
        -- As the game does after setting its own.
        scrollBox:ForEachFrame(function(row)
            if row.SetExpanded then
                row:SetExpanded(list.expandedDisplay)
            end
        end)
    end
    ns.Fire("RosterShown")
end

-- Shows the list again with the filters as they are now.
function RosterView.Refresh()
    if memberList then
        if memberList:IsVisible() and Active(memberList) then
            memberList:RefreshListDisplay()
        else
            UpdateControls(memberList)
        end
    end
end

-- The tooltip of a member --------------------------------------------------------------------

local function ColoredName(entry)
    local name = entry.name or "?"
    local color = entry.class and C_ClassColor and ns.Try(C_ClassColor.GetClassColor, entry.class)
    if color and color.WrapTextInColorCode then
        return color:WrapTextInColorCode(name)
    end
    return name
end

-- The names of the guild's characters of a player, mains and alts.
local function PlayerCharacters(discord)
    local mains, alts = {}, {}
    for _, entry in ipairs(Filters.Everyone()) do
        if entry.dc == discord then
            table.insert(entry.main and mains or alts, entry)
        end
    end
    local function Sorted(list)
        table.sort(list, function(a, b)
            if a.level ~= b.level then
                return a.level > b.level
            end
            return (a.name or "") < (b.name or "")
        end)
        local names = {}
        for i, entry in ipairs(list) do
            names[i] = ColoredName(entry)
        end
        return names
    end
    return Sorted(mains), Sorted(alts)
end

-- The game's lines (CommunitiesMemberListEntryMixin:OnEnter), for the rows
-- where it shows none: on the Roster tab, it only does when a text is cut.
local function GameLines(row, info)
    GameTooltip:SetOwner(row)
    GameTooltip:AddLine(ns.Plain(info.name) or "")
    GameTooltip:AddLine(ns.Plain(info.guildRank) or "")
    local level, race, classID = ns.Plain(info.level), ns.Plain(info.race), ns.Plain(info.classID)
    if level and race and classID and C_CreatureInfo and COMMUNITY_MEMBER_CHARACTER_INFO_FORMAT then
        local raceInfo = ns.Try(C_CreatureInfo.GetRaceInfo, race)
        local classInfo = ns.Try(C_CreatureInfo.GetClassInfo, classID)
        if ns.CanRead(raceInfo) and ns.CanRead(classInfo) then
            GameTooltip:AddLine(COMMUNITY_MEMBER_CHARACTER_INFO_FORMAT:format(level, raceInfo.raceName, classInfo.className), 1, 1, 1, true)
        end
    end
    local presence = ns.Plain(info.presence)
    local zone = ns.Plain(info.zone)
    if Enum.ClubMemberPresence and presence == Enum.ClubMemberPresence.OnlineMobile and COMMUNITIES_PRESENCE_MOBILE_CHAT then
        GameTooltip:AddLine(COMMUNITIES_PRESENCE_MOBILE_CHAT, 1, 1, 1, true)
    elseif zone then
        GameTooltip:AddLine(zone, 1, 1, 1, true)
    end
    local note = ns.Plain(info.memberNote)
    if note and COMMUNITY_MEMBER_NOTE_FORMAT then
        GameTooltip:AddLine(COMMUNITY_MEMBER_NOTE_FORMAT:format(note), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
    end
end

-- After the game's OnEnter of a row: its tooltip always, with who plays it.
local function RowOnEnter(row)
    if not (memberList and IsGuild(memberList)) or row.isInvitation then
        return
    end
    local info = row.GetMemberInfo and row:GetMemberInfo()
    if not ns.CanRead(info) or info.professionHeaderId then
        return
    end
    local guid = ns.Plain(info.guid)
    if not guid then
        return
    end
    if not GameTooltip:IsOwned(row) then
        GameLines(row, info)
    end
    local entry = Filters.Member(guid)
    if entry and entry.dc then
        local mains, alts = PlayerCharacters(entry.dc)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Discord: %s"]:format(entry.dc), unpack(DISCORD_COLOR))
        if #mains > 0 then
            GameTooltip:AddLine(L["Mains: %s"]:format(table.concat(mains, ", ")), 1, 1, 1, true)
        end
        if #alts > 0 then
            GameTooltip:AddLine(L["Alts: %s"]:format(table.concat(alts, ", ")), 1, 1, 1, true)
        end
    end
    GameTooltip:Show()
end

local function HookRow(row)
    if hooked[row] or not row.HookScript then
        return
    end
    hooked[row] = true
    row:HookScript("OnEnter", RowOnEnter)
end

-- Setup --------------------------------------------------------------------------------------

local function ShowTooltip(owner, title, text)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(title)
    GameTooltip:AddLine(text, 1, 1, 1, true)
    GameTooltip:Show()
end

local function CreateCheck(kind, label, tip, after)
    local check = CreateFrame("CheckButton", nil, memberList, "UICheckButtonTemplate")
    check.kind = kind
    if check.Text then
        check.Text:SetText(label)
    end
    check:SetPoint("LEFT", after.Text or after, "RIGHT", RosterView.GAP, 0)
    check:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        Filters.SetKind(self.kind, self:GetChecked())
    end)
    check:SetScript("OnEnter", function(self)
        ShowTooltip(self, label, tip)
    end)
    check:SetScript("OnLeave", GameTooltip_Hide)
    check:Hide()
    checks[#checks + 1] = check
    return check
end

local function Setup()
    local communities = CommunitiesFrame
    local list = communities and communities.MemberList
    if memberList or not (list and list.ScrollBox and list.ShowOfflineButton and list.RefreshListDisplay) then
        return
    end
    memberList = list

    statsButton = CreateFrame("Button", nil, list, "UIPanelButtonTemplate")
    statsButton:SetHeight(RosterView.BUTTON_HEIGHT)
    statsButton:SetPoint("BOTTOMLEFT", list, "TOPLEFT", OFFLINE_X, RosterView.BUTTON_Y)
    statsButton:SetText(L["Statistics"])
    ns.MyData.FitToText(statsButton, 0)
    statsButton:SetScript("OnClick", function()
        ns.Stats.Toggle()
    end)
    statsButton:SetScript("OnEnter", function(self)
        ShowTooltip(self, L["Statistics"], L["The guild's members in numbers: click one to filter the roster."])
    end)
    statsButton:SetScript("OnLeave", GameTooltip_Hide)
    statsButton:Hide()
    RosterView.statsButton = statsButton

    local after = list.ShowOfflineButton
    after = CreateCheck("main", L["Mains"], L["Shows the mains. Members without Bot'tar Sync, or without a Discord username, count as mains."], after)
    after = CreateCheck("alt", L["Alts"], L["Shows the alts: the characters their players did not tick as mains."], after)
    CreateCheck("bank", L["Banks"], L["Shows the bank characters: those with a bank rank of Guild Bank Alts."], after)
    RosterView.checks = checks

    hooksecurefunc(list, "RefreshListDisplay", FilterList)
    ScrollUtil.AddAcquiredFrameCallback(list.ScrollBox, function(_, row)
        HookRow(row)
    end, RosterView, false)
    list.ScrollBox:ForEachFrame(HookRow)
    UpdateControls(list)
    if list:IsVisible() then
        list:RefreshListDisplay()
    end

    ns.On("FiltersChanged", RosterView.Refresh)
end

function RosterView.Init()
    EventUtil.ContinueOnAddOnLoaded("Blizzard_Communities", Setup)
end
