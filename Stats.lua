-- Stats.lua: the Statistics window, beside the game's guild window and as
-- tall as it, opened by the Statistics button on the guild window's title
-- bar (below). It can be dragged elsewhere, and opens beside the guild
-- window again. It counts the guild's members (Filters.lua), and lists
-- right of the numbers the members the filters let through; a click on a
-- number filters the list:
--   - Characters: a card for All, chosen at first, and one each for Mains,
--     Alts and Banks; one is chosen at a time, and a click on another lists
--     only that kind (again, or All: every kind);
--   - Classes: a bar with a section of each class's color, as wide as its
--     share; a click filters by that class (again: no longer);
--   - Specializations: a bar with every class's specializations, in shades
--     of its color, or only the chosen class's; a click filters by one
--     (again: no longer), without choosing its class. A character with two
--     different specializations (dual spec) counts in both, and the window
--     says how many do; one without builds in Guild Builds, in none;
--   - Levels: a card for each range of ten levels, and one for level 60;
--     a click filters by it (again: no longer).
-- The filters last while the window is open. A search box above the list
-- finds, among the members listed, those whose name or Discord username
-- has its text, and the list's heading says how many it shows. The list
-- has three columns, under the game's column headers: the member's name,
-- their level, and Online or how long ago they were online (from the
-- game's guild roster, as it tells it); a click on a header sorts by it,
-- another the other way. The levels' cards keep their place whether the
-- line on dual specs shows or not. The list scrolls on its own; a member's tooltip
-- tells their rank, level and class, note and player, and for an officer a
-- click opens their player in My data (MyData.lua). The game's roster
-- lists everyone: see RosterView.lua for why it is not filtered.
local _, ns = ...
local L = ns.L
local Filters = ns.Filters

local Stats = {}
ns.Stats = Stats

Stats.ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"
Stats.WIDTH = 400       -- the numbers, on the left
Stats.LIST_WIDTH = 320  -- the list, on the right
Stats.CONTENT_WIDTH = Stats.WIDTH - 36
Stats.GAP = 6
Stats.CARD_HEIGHT = 56
Stats.LEVEL_CARD_HEIGHT = 44
Stats.BAR_HEIGHT = 24
Stats.MIN_SECTION = 4   -- a section is never narrower, so it can be pointed at
Stats.ICON_SIZE = 16
Stats.ROW_HEIGHT = 20   -- a member in the list
-- The list's columns, each with a header that sorts by it: name, level,
-- and last online (the rest of the row).
Stats.COLUMNS = { { key = "name", width = 150 }, { key = "level", width = 46 }, { key = "online" } }
Stats.HEADER_HEIGHT = 19 -- the game's column headers (ColumnDisplayButtonTemplate)
local DIM_ALPHA = 0.35  -- the sections not chosen while one is
local OFFLINE_COLOR = "|cff808080"
local ONLINE_COLOR = "|cff40ff40"
local NO_ICON = 134400 -- the question mark, for a tree whose icon is not known
local SPEC_SHADES = { 1, 0.72, 0.5 }
local CLICK_COLOR = { 0.1, 1, 0.1 } -- the game's green for what a click does

local window, content

-- Pieces ---------------------------------------------------------------------------------------

local function ClassColor(class)
    local color = C_ClassColor and ns.Try(C_ClassColor.GetClassColor, class)
    if not color and RAID_CLASS_COLORS then
        color = RAID_CLASS_COLORS[class]
    end
    if color then
        return color.r, color.g, color.b
    end
    return 0.6, 0.6, 0.6
end

local function ClassName(class)
    local names = LOCALIZED_CLASS_NAMES_MALE
    return names and names[class] or class
end

local function SpecName(class, tab)
    local name = Filters.SpecInfo(class, tab)
    return name or L["Talent tree %d"]:format(tab)
end

local function ShowTooltip(owner, title, lines, color)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if color then
        GameTooltip:SetText(title, unpack(color))
    else
        GameTooltip:SetText(title)
    end
    for _, line in ipairs(lines) do
        GameTooltip:AddLine(line[1], line[2] or 1, line[3] or 1, line[4] or 1, true)
    end
    GameTooltip:Show()
end

local function Percent(count, total)
    return total > 0 and math.floor(count * 100 / total + 0.5) or 0
end

local function Heading(text, y)
    local heading = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    heading:SetPoint("TOPLEFT", 2, y)
    heading:SetText(text)
    return heading
end

-- A card: a big number with its label under it, in the game's inset frame,
-- with the auction house's highlight and selected looks.
local function CreateCard(width, height, numberFont, onClick, onEnter)
    local card = CreateFrame("Button", nil, content, "InsetFrameTemplate")
    card:SetSize(width, height)
    card.Number = card:CreateFontString(nil, "ARTWORK", numberFont)
    card.Number:SetPoint("CENTER", 0, 7)
    card.Label = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    card.Label:SetPoint("BOTTOM", 0, 7)
    card.Label:SetWidth(width - 6)
    card.Label:SetWordWrap(false)
    card.Selected = card:CreateTexture(nil, "BACKGROUND", nil, 2)
    card.Selected:SetPoint("TOPLEFT", 3, -3)
    card.Selected:SetPoint("BOTTOMRIGHT", -3, 3)
    card.Selected:SetAtlas("auctionhouse-ui-row-select")
    card.Selected:Hide()
    card:SetHighlightAtlas("auctionhouse-ui-row-highlight")
    card:SetScript("OnClick", onClick)
    card:SetScript("OnEnter", onEnter)
    card:SetScript("OnLeave", GameTooltip_Hide)
    return card
end

local function SetCard(card, count, label, selected)
    card.count = count
    card.Number:SetText(tostring(count))
    card.Label:SetText(label)
    card.Selected:SetShown(selected)
    if selected then
        card.Label:SetTextColor(1, 0.82, 0)
    else
        card.Label:SetTextColor(1, 1, 1)
    end
end

-- Bars ---------------------------------------------------------------------------------------

local function CreateBar()
    local bar = CreateFrame("Frame", nil, content, "InsetFrameTemplate")
    bar:SetSize(Stats.CONTENT_WIDTH, Stats.BAR_HEIGHT)
    bar.sections = {}
    bar.Empty = bar:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    bar.Empty:SetPoint("CENTER")
    bar.Empty:SetText(L["Nobody"])
    return bar
end

local function Section(bar, i)
    local section = bar.sections[i]
    if not section then
        section = CreateFrame("Button", nil, bar)
        section.Color = section:CreateTexture(nil, "ARTWORK")
        section.Color:SetAllPoints()
        section.Icon = section:CreateTexture(nil, "OVERLAY")
        section.Icon:SetSize(Stats.ICON_SIZE, Stats.ICON_SIZE)
        section.Icon:SetPoint("CENTER")
        local highlight = section:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.25)
        section:SetScript("OnLeave", GameTooltip_Hide)
        bar.sections[i] = section
    end
    return section
end

-- Each section's width, its share of the bar's, never under MIN_SECTION:
-- the widest gives up what the narrow ones take.
function Stats.Widths(counts, width)
    local total = 0
    for _, count in ipairs(counts) do
        total = total + count
    end
    local widths, used, widest = {}, 0, nil
    for i, count in ipairs(counts) do
        widths[i] = math.max(Stats.MIN_SECTION, math.floor(width * count / total + 0.5))
        used = used + widths[i]
        if not widest or count > counts[widest] then
            widest = i
        end
    end
    if widest then
        widths[widest] = widths[widest] + width - used
    end
    return widths
end

-- items: { { count, r, g, b, icon (file ID, or a class file for its icon),
-- chosen, onClick, onEnter } ... }; chosen dims the others.
local function DrawBar(bar, items)
    local counts = {}
    local anyChosen = false
    for i, item in ipairs(items) do
        counts[i] = item.count
        anyChosen = anyChosen or item.chosen
    end
    local inner = Stats.CONTENT_WIDTH - 6
    local widths = Stats.Widths(counts, inner)
    local x = 3
    for i, item in ipairs(items) do
        local section = Section(bar, i)
        section:ClearAllPoints()
        section:SetPoint("TOPLEFT", x, -3)
        section:SetSize(widths[i], Stats.BAR_HEIGHT - 6)
        section.Color:SetColorTexture(item.r, item.g, item.b)
        if type(item.icon) == "string" and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[item.icon] then
            section.Icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
            section.Icon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[item.icon]))
        elseif type(item.icon) == "number" then
            section.Icon:SetTexture(item.icon)
            section.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        section.Icon:SetShown(item.icon ~= nil and widths[i] >= Stats.ICON_SIZE + 4)
        section:SetAlpha((anyChosen and not item.chosen) and DIM_ALPHA or 1)
        section.item = item
        section:SetScript("OnClick", item.onClick)
        section:SetScript("OnEnter", item.onEnter)
        section:Show()
        x = x + widths[i]
    end
    for i = #items + 1, #bar.sections do
        bar.sections[i]:Hide()
    end
    bar.Empty:SetShown(#items == 0)
end

-- The window -------------------------------------------------------------------------------

local KIND_ORDER = { "all", "main", "alt", "bank" }

local function KindLabel(kind)
    if kind == "main" then
        return L["Mains"]
    elseif kind == "alt" then
        return L["Alts"]
    elseif kind == "bank" then
        return L["Banks"]
    end
    return L["All"]
end

local function KindCardOnEnter(card)
    local lines = { { L["%d |4character:characters;"]:format(card.count) } }
    if card.kind == "main" then
        lines[#lines + 1] = { L["Members without Bot'tar Sync, or without a Discord username, count as mains."], 0.8, 0.8, 0.8 }
    elseif card.kind == "alt" then
        lines[#lines + 1] = { L["The characters their players did not tick as mains."], 0.8, 0.8, 0.8 }
    elseif card.kind == "bank" then
        lines[#lines + 1] = { L["Characters with a bank rank of Guild Bank Alts."], 0.8, 0.8, 0.8 }
    end
    if card.kind == "all" then
        lines[#lines + 1] = { L["Click to list every kind."], unpack(CLICK_COLOR) }
    elseif Filters.kind == card.kind then
        lines[#lines + 1] = { L["Click again to remove the filter."], unpack(CLICK_COLOR) }
    else
        lines[#lines + 1] = { L["Click to list only these."], unpack(CLICK_COLOR) }
    end
    ShowTooltip(card, KindLabel(card.kind), lines)
end

local function LevelLabel(index)
    local range = Filters.LEVELS[index]
    if index == #Filters.LEVELS then
        return tostring(range[1])
    end
    return ("%d-%d"):format(range[1], range[2])
end

local function FilterHint(chosen)
    if chosen then
        return { L["Click again to remove the filter."], unpack(CLICK_COLOR) }
    end
    return { L["Click to filter the list."], unpack(CLICK_COLOR) }
end

local function LevelCardOnEnter(card)
    ShowTooltip(card, L["Level %s"]:format(LevelLabel(card.index)), {
        { L["%d |4character:characters;"]:format(card.count) },
        FilterHint(Filters.level == card.index),
    })
end

-- The list of members ---------------------------------------------------------------------------

local function MemberOnEnter(row)
    local entry = row.entry
    if not entry then
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(entry.name or "?", ClassColor(entry.class))
    local rosterEntry = ns.Roster.members[entry.guid]
    if rosterEntry and rosterEntry.rk then
        GameTooltip:AddLine(rosterEntry.rk, 1, 1, 1)
    end
    if entry.level > 0 then
        local level = FRIENDS_LEVEL_TEMPLATE and entry.class and FRIENDS_LEVEL_TEMPLATE:format(entry.level, ClassName(entry.class))
        GameTooltip:AddLine(level or L["level %d"]:format(entry.level), 1, 1, 1)
    end
    local note = rosterEntry and rosterEntry.nt
    if note and note ~= "" and COMMUNITY_MEMBER_NOTE_FORMAT then
        GameTooltip:AddLine(COMMUNITY_MEMBER_NOTE_FORMAT:format(note), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
    end
    ns.RosterView.AddPlayerLines(entry)
    if ns.Officers.AmI() then
        GameTooltip:AddLine(L["Click to manage their player."], unpack(CLICK_COLOR))
    end
    GameTooltip:Show()
end

-- For an officer, their player in My data.
local function MemberOnClick(row)
    if row.entry and ns.Officers.AmI() then
        ns.MyData.ShowCharacter(row.entry.guid)
    end
end

-- A member's row, in the list's columns: their name, in their class's
-- color (grey while offline), their level, and Online or how long ago they
-- were online.
local function InitMemberRow(row, entry)
    if not row.Name then
        local name, level = Stats.COLUMNS[1].width, Stats.COLUMNS[2].width
        row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.Name:SetPoint("LEFT", 4, 0)
        row.Name:SetWidth(name - 8)
        row.Name:SetJustifyH("LEFT")
        row.Name:SetWordWrap(false)
        row.Level = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.Level:SetPoint("LEFT", name, 0)
        row.Level:SetWidth(level)
        row.Level:SetJustifyH("CENTER")
        row.Status = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.Status:SetPoint("LEFT", name + level + 4, 0)
        row.Status:SetPoint("RIGHT", -4, 0)
        row.Status:SetJustifyH("LEFT")
        row.Status:SetWordWrap(false)
        row:SetHighlightAtlas("auctionhouse-ui-row-highlight")
        row:SetScript("OnEnter", MemberOnEnter)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row:SetScript("OnClick", MemberOnClick)
    end
    row.entry = entry
    local name = entry.name or "?"
    if entry.online then
        local r, g, b = ClassColor(entry.class)
        name = ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, name)
    else
        name = OFFLINE_COLOR .. name .. "|r"
    end
    row.Name:SetText(name)
    row.Level:SetText(entry.level > 0 and tostring(entry.level) or "")
    if entry.online then
        row.Status:SetText(ONLINE_COLOR .. L["Online"] .. "|r")
    else
        local ago = window.lastOnline and window.lastOnline[entry.guid]
        row.Status:SetText(OFFLINE_COLOR .. (ago and ago.text or L["Offline"]) .. "|r")
    end
end

-- Whether a member's name or their player's Discord username has the text
-- searched (in small letters; "" finds everyone).
function Stats.Matches(entry, query)
    if query == "" then
        return true
    end
    return (entry.name or ""):lower():find(query, 1, true) ~= nil
        or (entry.dc or ""):lower():find(query, 1, true) ~= nil
end

-- How long ago each offline member was last online, read now from the
-- game's guild roster: { [GUID] = { text = as the game's roster tells it
-- ("3 days"), hours = about how many hours ago, to sort by } }.
function Stats.LastOnline()
    local texts = {}
    if not (GetNumGuildMembers and GetGuildRosterInfo and GetGuildRosterLastOnline
        and TimeUtil and TimeUtil.GetRecentTimeDate) then
        return texts
    end
    local ok, count = pcall(GetNumGuildMembers)
    count = ok and ns.Plain(count)
    for i = 1, type(count) == "number" and count or 0 do
        local guid = ns.Plain((select(18, pcall(GetGuildRosterInfo, i))))
        if type(guid) == "string" then
            local read, years, months, days, hours = pcall(GetGuildRosterLastOnline, i)
            years, months, days, hours = ns.Plain(years), ns.Plain(months), ns.Plain(days), ns.Plain(hours)
            if read and (years or months or days or hours) then
                texts[guid] = {
                    text = ns.Try(TimeUtil.GetRecentTimeDate, years, months, days, hours),
                    hours = (((years or 0) * 365 + (months or 0) * 30 + (days or 0)) * 24) + (hours or 0),
                }
            end
        end
    end
    return texts
end

-- What a column sorts by, first (the other click reverses it): names A to
-- Z, the highest level, the members online and then the most recent.
local function SortValue(entry, key)
    if key == "level" then
        return -entry.level
    elseif key == "online" then
        if entry.online then
            return -1
        end
        local ago = window.lastOnline[entry.guid]
        return ago and ago.hours or math.huge
    end
    return (entry.name or ""):lower()
end

local function SortList(listed)
    local key, reverse = window.sortKey or "name", window.sortReverse
    table.sort(listed, function(a, b)
        local va, vb = SortValue(a, key), SortValue(b, key)
        if va ~= vb then
            if reverse then
                return va > vb
            end
            return va < vb
        end
        -- Ties by name.
        local na, nb = (a.name or ""):lower(), (b.name or ""):lower()
        if na ~= nb then
            return na < nb
        end
        return a.guid < b.guid
    end)
end

-- Sorts the list by a column ("name", "level" or "online"); by the same
-- one again, the other way.
function Stats.SortBy(key)
    if (window.sortKey or "name") == key then
        window.sortReverse = not window.sortReverse
    else
        window.sortKey, window.sortReverse = key, false
    end
    Stats.Refresh()
end

-- Shows the list: the members the filters let through whose name or
-- Discord username has the text searched, sorted, and how many they are.
local function DrawList()
    window.lastOnline = Stats.LastOnline()
    local query = strtrim(window.Search:GetText() or ""):lower()
    local listed = {}
    for _, entry in ipairs(Filters.Listed()) do
        if Stats.Matches(entry, query) then
            listed[#listed + 1] = entry
        end
    end
    SortList(listed)
    window.listed = listed
    window.MembersHeading:SetText(L["Members (%d)"]:format(#listed))
    window.Members:SetDataProvider(CreateDataProvider(listed), ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
    window.Nobody:SetShown(#listed == 0)
end

local function Create()
    window = CreateFrame("Frame", "BottarSyncStats", UIParent, "PortraitFrameTemplate")
    window:SetWidth(Stats.WIDTH + Stats.LIST_WIDTH)
    window:SetFrameStrata("HIGH")
    window:SetToplevel(true)
    window:EnableMouse(true)
    -- Dragged away, it keeps its height and leaves the guild window's side
    -- until it opens again.
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self)
        if self.docked then
            self.docked = false
            local left, top, height = self:GetLeft(), self:GetTop(), self:GetHeight()
            if left and top then
                self:ClearAllPoints()
                self:SetHeight(height)
                self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            end
        end
        self:StartMoving()
    end)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:Hide()
    tinsert(UISpecialFrames, window:GetName())
    window:SetTitle(L["Guild statistics"])
    window:SetPortraitToAsset(Stats.ICON)
    window:SetScript("OnHide", function()
        window.Search:SetText("")
        window.Search:ClearFocus()
        Filters.ClearWindow()
        ns.MyData.Place()
    end)

    window.Hint = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    window.Hint:SetPoint("TOPLEFT", 64, -34)
    window.Hint:SetPoint("RIGHT", window, "LEFT", Stats.WIDTH - 12, 0)
    window.Hint:SetJustifyH("LEFT")
    window.Hint:SetText(L["Click a number or a bar to filter the list of members."])

    content = CreateFrame("Frame", nil, window)
    content:SetPoint("TOPLEFT", 12, -64)
    content:SetWidth(Stats.CONTENT_WIDTH)
    content:SetHeight(1)
    window.Content = content

    -- The members, right of the numbers, as tall as the window, in the
    -- game's inset frame.
    window.MembersHeading = window:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    window.MembersHeading:SetPoint("TOPLEFT", Stats.WIDTH - 6, -42)
    -- The game's search box, right of it: by name or Discord username,
    -- among the members listed.
    local search = CreateFrame("EditBox", nil, window, "SearchBoxTemplate")
    search:SetSize(Stats.LIST_WIDTH - 130, 20)
    search:SetPoint("TOPRIGHT", -14, -37)
    search:SetAutoFocus(false)
    search:SetMaxLetters(40)
    if search.Instructions then
        search.Instructions:SetText(L["Search by name or Discord"])
    end
    -- After the template's own (instructions and clear button).
    search:HookScript("OnTextChanged", function()
        if window:IsShown() then
            DrawList()
        end
    end)
    window.Search = search
    local inset = CreateFrame("Frame", nil, window, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", Stats.WIDTH - 10, -64 - Stats.HEADER_HEIGHT)
    inset:SetPoint("BOTTOMRIGHT", -8, 8)
    window.ListInset = inset
    -- The columns' headers, on top of it, as the game's roster has them: a
    -- click sorts by that column, another the other way.
    local titles = { name = L["Name"], level = L["Level"], online = L["Last online"] }
    window.headers = {}
    local previous
    for i, column in ipairs(Stats.COLUMNS) do
        local header = CreateFrame("Button", nil, window, "ColumnDisplayButtonTemplate")
        header:SetHeight(Stats.HEADER_HEIGHT)
        header:SetText(titles[column.key])
        header.key = column.key
        if i == 1 then
            header:SetPoint("BOTTOMLEFT", inset, "TOPLEFT", 2, 0)
        else
            header:SetPoint("BOTTOMLEFT", previous, "BOTTOMRIGHT", -2, 0)
        end
        if column.width then
            header:SetWidth(column.width + 2)
        else
            header:SetPoint("BOTTOMRIGHT", inset, "TOPRIGHT", -2, 0)
        end
        header:SetScript("OnClick", function(self)
            Stats.SortBy(self.key)
        end)
        window.headers[column.key] = header
        previous = header
    end
    local scrollBox = CreateFrame("Frame", nil, inset, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 4, -4)
    scrollBox:SetPoint("BOTTOMRIGHT", -18, 4)
    local scrollBar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
    local view = CreateScrollBoxListLinearView(0, 0, 0, 0, 0)
    view:SetElementExtent(Stats.ROW_HEIGHT)
    view:SetElementInitializer("Button", InitMemberRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    window.Members = scrollBox
    window.Nobody = inset:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    window.Nobody:SetPoint("TOP", scrollBox, "TOP", 0, -12)
    window.Nobody:SetText(L["Nobody"])

    local gap = Stats.GAP
    local y = 0
    window.KindsHeading = Heading(L["Characters"], y)
    -- The game's own "Offline members" box, as its roster has it: offline
    -- members count while it is ticked (Filters.ShowsOffline).
    local offline = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    offline:SetPoint("LEFT", window.KindsHeading, "RIGHT", 8, 0)
    if offline.Text then
        offline.Text:SetText(COMMUNITIES_MEMBER_LIST_SHOW_OFFLINE or "Offline members")
    end
    offline:SetScript("OnClick", function(self)
        if SOUNDKIT then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
        Filters.SetShowOffline(self:GetChecked())
    end)
    window.OfflineBox = offline
    y = y - 20
    window.kindCards = {}
    local width = (Stats.CONTENT_WIDTH - 3 * gap) / 4
    for i, kind in ipairs(KIND_ORDER) do
        local card = CreateCard(width, Stats.CARD_HEIGHT, "GameFontHighlightHuge", function(self)
            Filters.ToggleKind(self.kind)
        end, KindCardOnEnter)
        card.kind = kind
        card:SetPoint("TOPLEFT", (i - 1) * (width + gap), y)
        window.kindCards[kind] = card
    end
    y = y - Stats.CARD_HEIGHT - 14

    window.ClassesHeading = Heading(L["Classes"], y)
    y = y - 20
    window.ClassBar = CreateBar()
    window.ClassBar:SetPoint("TOPLEFT", 0, y)
    window.classY = y - Stats.BAR_HEIGHT - 14

    -- The specializations of the chosen class, and what follows, are placed
    -- in Draw (they show only with a class).
    window.SpecHeading = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    window.SpecBar = CreateBar()
    window.Dual = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    window.Dual:SetWidth(Stats.CONTENT_WIDTH)
    window.Dual:SetJustifyH("LEFT")

    window.LevelsHeading = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    window.LevelsHeading:SetText(L["Levels"])
    window.levelCards = {}
    local levelWidth = (Stats.CONTENT_WIDTH - (#Filters.LEVELS - 1) * gap) / #Filters.LEVELS
    window.levelWidth = levelWidth
    for i = 1, #Filters.LEVELS do
        local card = CreateCard(levelWidth, Stats.LEVEL_CARD_HEIGHT, "GameFontHighlightLarge", function(self)
            Filters.ToggleLevel(self.index)
        end, LevelCardOnEnter)
        card.index = i
        card.Number:SetPoint("CENTER", 0, 6)
        window.levelCards[i] = card
    end

    ns.On("FiltersChanged", Stats.Refresh)
    ns.On("RosterShown", Stats.Refresh)
end

local function ClassItems(counts)
    local items = {}
    for _, each in ipairs(counts.classes) do
        local class = each.class
        local r, g, b = ClassColor(class)
        items[#items + 1] = {
            count = each.count, r = r, g = g, b = b, icon = class, class = class,
            chosen = Filters.class == class,
            onClick = function()
                Filters.ToggleClass(class)
            end,
            onEnter = function(section)
                ShowTooltip(section, ClassName(class), {
                    { L["%d |4character:characters; (%d%%)"]:format(each.count, Percent(each.count, counts.classTotal)) },
                    FilterHint(Filters.class == class),
                }, { r, g, b })
            end,
        }
    end
    return items
end

local function IsSpecChosen(class, tab)
    local spec = Filters.spec
    return spec ~= nil and spec.class == class and spec.tab == tab
end

-- The specializations of the class chosen, or of every class: each class's
-- in the class bar's order, its trees in the game's order, in shades of its
-- color.
local function SpecItems(counts)
    local classes = {}
    for _, each in ipairs(counts.classes) do
        if counts.specs[each.class] then
            classes[#classes + 1] = each.class
        end
    end
    local items = {}
    for _, class in ipairs(classes) do
        local r, g, b = ClassColor(class)
        local tabs = {}
        for tab in pairs(counts.specs[class]) do
            tabs[#tabs + 1] = tab
        end
        table.sort(tabs)
        for _, tab in ipairs(tabs) do
            local spec = counts.specs[class][tab]
            local shade = SPEC_SHADES[tab] or SPEC_SHADES[#SPEC_SHADES]
            local _, icon = Filters.SpecInfo(class, tab)
            local item = {
                count = spec.count, chosen = IsSpecChosen(class, tab), class = class, tab = tab,
                r = r * shade, g = g * shade, b = b * shade, icon = icon or NO_ICON,
            }
            item.onClick = function()
                Filters.ToggleSpec(class, tab)
            end
            item.onEnter = function(section)
                local lines = {}
                if not Filters.class then
                    lines[#lines + 1] = { ClassName(class), r, g, b }
                end
                lines[#lines + 1] = { L["%d |4character:characters; (%d%%)"]:format(spec.count, Percent(spec.count, counts.specTotal)) }
                if spec.secondary > 0 then
                    lines[#lines + 1] = { L["%d in their primary build, %d only in their secondary one."]:format(spec.primary, spec.secondary), 0.8, 0.8, 0.8 }
                end
                lines[#lines + 1] = FilterHint(IsSpecChosen(class, tab))
                ShowTooltip(section, SpecName(class, tab), lines)
            end
            items[#items + 1] = item
        end
    end
    return items
end

-- Shows the numbers as they are now.
local function Draw()
    local counts = Filters.Counts()
    window.OfflineBox:SetChecked(Filters.ShowsOffline())
    local chosen = Filters.kind or "all"
    for _, kind in ipairs(KIND_ORDER) do
        local count = kind == "all" and counts.all or counts.kinds[kind]
        SetCard(window.kindCards[kind], count, KindLabel(kind), kind == chosen)
    end
    DrawBar(window.ClassBar, ClassItems(counts))

    -- The specializations, always: of the class chosen, or of every class.
    local y = window.classY
    local class = Filters.class
    window.SpecHeading:ClearAllPoints()
    window.SpecHeading:SetPoint("TOPLEFT", 2, y)
    if class then
        window.SpecHeading:SetText(L["Specializations: %s"]:format(ClassName(class)))
    else
        window.SpecHeading:SetText(L["Specializations"])
    end
    y = y - 20
    window.SpecBar:ClearAllPoints()
    window.SpecBar:SetPoint("TOPLEFT", 0, y)
    DrawBar(window.SpecBar, SpecItems(counts))
    y = y - Stats.BAR_HEIGHT - 4
    -- The line on dual specs has its place also while it does not show, so
    -- what follows never moves.
    window.Dual:SetShown(counts.dual > 0)
    window.Dual:ClearAllPoints()
    window.Dual:SetPoint("TOPLEFT", 2, y)
    window.Dual:SetText(L["%d |4character has two different specializations and counts:characters have two different specializations and count; in both."]:format(counts.dual))
    y = y - 16 - 10

    window.LevelsHeading:ClearAllPoints()
    window.LevelsHeading:SetPoint("TOPLEFT", 2, y)
    y = y - 20
    local width = window.levelWidth
    for i, card in ipairs(window.levelCards) do
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", (i - 1) * (width + Stats.GAP), y)
        SetCard(card, counts.levels[i], LevelLabel(i), Filters.level == i)
    end
    y = y - Stats.LEVEL_CARD_HEIGHT - 4
    content:SetHeight(-y)

    DrawList()
end

function Stats.Refresh()
    if window and window:IsShown() then
        ns.Debounce("Stats", 0.1, function()
            if window:IsShown() then
                Draw()
            end
        end)
    end
end

-- Opens the window beside the guild window (as tall as it), or closes it.
function Stats.Toggle()
    if window and window:IsShown() then
        window:Hide()
        return
    end
    if not window then
        Create()
    end
    window:ClearAllPoints()
    window.docked = true
    if CommunitiesFrame and CommunitiesFrame:IsShown() then
        window:SetPoint("TOPLEFT", CommunitiesFrame, "TOPRIGHT", 10, 0)
        window:SetPoint("BOTTOMLEFT", CommunitiesFrame, "BOTTOMRIGHT", 10, 0)
    else
        window:SetPoint("CENTER")
        window:SetHeight(500)
    end
    window:Show()
    Draw()
    ns.MyData.Place()
end

function Stats.Hide()
    if window then
        window:Hide()
    end
end

function Stats.IsShown()
    return window ~= nil and window:IsShown()
end

function Stats.Window()
    return window
end

-- The button that opens it: on the guild window's title bar, left of its
-- minimize button (TitleButton.lua), while we are in a guild. Until 0.9 it
-- was on the Roster tab.
local guildWindowButton

local function UpdateGuildWindowButton()
    local communities = CommunitiesFrame
    local frame = communities.MaximizeMinimizeFrame
    local close = communities.CloseButton
    -- The minimize and maximize buttons take turns in the same spot.
    local neighbor = frame and (frame.MinimizeButton or frame.MaximizeButton or frame) or close
    if neighbor then
        ns.TitleButton.PlaceLeftOf(guildWindowButton, neighbor, close)
    else
        guildWindowButton:ClearAllPoints()
        guildWindowButton:SetPoint("TOPRIGHT", communities, "TOPRIGHT", -30, -4)
    end
    guildWindowButton:SetShown(IsInGuild() == true)
end

local function SetupGuildWindow()
    local communities = CommunitiesFrame
    if guildWindowButton or not (communities and communities.CreateTexture) then
        return
    end
    local frame = communities.MaximizeMinimizeFrame
    local close = communities.CloseButton
    local neighbor = frame and (frame.MinimizeButton or frame.MaximizeButton or frame) or close or communities
    guildWindowButton = ns.TitleButton.New(communities, neighbor, ns.TitleButton.SizeOf(close), Stats.ICON,
        ns.TitleButton.ICON_CROP, L["Statistics"], L["The guild's members in numbers, and a list of them to filter."],
        Stats.Toggle)
    Stats.guildWindowButton = guildWindowButton
    UpdateGuildWindowButton()
    -- Secure hooks of the window's own OnShow and OnHide (its XML calls the
    -- methods by name), never HookScript: see KinFolk.lua. Once shown, the
    -- gap between the game's buttons can be measured.
    if type(communities.OnShow) == "function" then
        hooksecurefunc(communities, "OnShow", UpdateGuildWindowButton)
    end
    -- The window belongs to the guild window: it goes with it.
    if type(communities.OnHide) == "function" then
        hooksecurefunc(communities, "OnHide", Stats.Hide)
    end
end

function Stats.Init()
    EventUtil.ContinueOnAddOnLoaded("Blizzard_Communities", SetupGuildWindow)
end
