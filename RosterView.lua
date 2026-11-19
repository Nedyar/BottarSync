-- RosterView.lua: Bot'tar Sync's pieces on the guild's Roster tab of the
-- game's guild window (CommunitiesFrame.MemberList):
--   - a Statistics button, where the game's "Offline members" box was (the
--     box moves right of it), which opens the Statistics window (Stats.lua);
--   - a member's tooltip always shows (the game's only did when a text was
--     cut), with their player's Discord username, mains and alts.
--
-- Its list stays the game's own, with every member: the game blocks
-- changing a member's notes or rank (and removing them) from a row that an
-- addon's code drew, and taking members out of the list, or having it
-- drawn again, makes our code draw its rows. Until 0.8 the roster had boxes
-- to hide kinds of characters; the Statistics window lists them instead.
-- So this file only hooks the game's functions (hooksecurefunc), moves its
-- box, and adds to tooltips. Nothing here runs while the roster shows
-- another community.
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
RosterView.DISCORD_COLOR = { 0.6, 0.65, 1 }

local memberList, statsButton
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

-- Our button shows on the guild's roster, and the game's box moves for it.
local function UpdateControls(list)
    local active = Active(list)
    statsButton:SetShown(active)
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

-- Runs after the game fills the list (also when its "Offline members" box
-- changes, which the Statistics window counts by): it changes nothing in
-- the list.
local function ListShown(list)
    UpdateControls(list)
    if Active(list) then
        ns.Fire("RosterShown")
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
            names[i] = entry.pending and L["%s (pending)"]:format(ColoredName(entry)) or ColoredName(entry)
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

-- Adds to the tooltip who plays a member (Filters.Member's entry): their
-- player's Discord username, mains and alts. Nothing without a player.
function RosterView.AddPlayerLines(entry)
    if not (entry and entry.dc) then
        return
    end
    local mains, alts = PlayerCharacters(entry.dc)
    GameTooltip:AddLine(" ")
    local discord = entry.pending and L["Discord: %s (pending)"] or L["Discord: %s"]
    GameTooltip:AddLine(discord:format(entry.dc), unpack(RosterView.DISCORD_COLOR))
    if #mains > 0 then
        GameTooltip:AddLine(L["Mains: %s"]:format(table.concat(mains, ", ")), 1, 1, 1, true)
    end
    if #alts > 0 then
        GameTooltip:AddLine(L["Alts: %s"]:format(table.concat(alts, ", ")), 1, 1, 1, true)
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
    RosterView.AddPlayerLines(Filters.Member(guid))
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
        ShowTooltip(self, L["Statistics"], L["The guild's members in numbers, and a list of them to filter."])
    end)
    statsButton:SetScript("OnLeave", GameTooltip_Hide)
    statsButton:Hide()
    RosterView.statsButton = statsButton

    hooksecurefunc(list, "RefreshListDisplay", ListShown)
    ScrollUtil.AddAcquiredFrameCallback(list.ScrollBox, function(_, row)
        HookRow(row)
    end, RosterView, false)
    list.ScrollBox:ForEachFrame(HookRow)
    UpdateControls(list)
end

function RosterView.Init()
    EventUtil.ContinueOnAddOnLoaded("Blizzard_Communities", Setup)
end
