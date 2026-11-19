-- Stats.lua: the Statistics window, beside the game's guild window and as
-- tall as it (scrolling when its content does not fit), opened by the
-- Statistics button of the Roster tab (RosterView.lua). It counts the
-- guild's members (Filters.lua), and a click on a number filters the
-- roster:
--   - Characters: a card each for Mains, Alts, Banks and All; a click shows
--     only that kind in the roster (it sets the roster's boxes);
--   - Classes: a bar with a section of each class's color, as wide as its
--     share; a click filters by that class (again: no longer) and shows a
--     second bar with that class's specializations, which filter the same
--     way. A character with two different specializations (dual spec)
--     counts in both, and the window says how many do;
--   - Levels: a card for each range of ten levels, and one for level 60;
--     a click filters by it (again: no longer).
-- The class, specialization and level filters last while the window is
-- open.
local _, ns = ...
local L = ns.L
local Filters = ns.Filters

local Stats = {}
ns.Stats = Stats

Stats.ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"
Stats.WIDTH = 400
Stats.CONTENT_WIDTH = Stats.WIDTH - 36
Stats.GAP = 6
Stats.CARD_HEIGHT = 56
Stats.LEVEL_CARD_HEIGHT = 44
Stats.BAR_HEIGHT = 24
Stats.MIN_SECTION = 4   -- a section is never narrower, so it can be pointed at
Stats.ICON_SIZE = 16
local DIM_ALPHA = 0.35  -- the sections not chosen while one is
local UNKNOWN_ICON = 134400 -- the question mark
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
    if tab == Filters.UNKNOWN then
        return L["Unknown"]
    end
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

local KIND_ORDER = { "main", "alt", "bank", "all" }

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
    if card.kind == "all" then
        lines[#lines + 1] = { L["Click to show every kind in the roster."], unpack(CLICK_COLOR) }
    else
        lines[#lines + 1] = { L["Click to show only these in the roster."], unpack(CLICK_COLOR) }
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
    return { L["Click to filter the roster."], unpack(CLICK_COLOR) }
end

local function LevelCardOnEnter(card)
    ShowTooltip(card, L["Level %s"]:format(LevelLabel(card.index)), {
        { L["%d |4character:characters;"]:format(card.count) },
        FilterHint(Filters.level == card.index),
    })
end

local function Create()
    window = CreateFrame("Frame", "BottarSyncStats", UIParent, "PortraitFrameTemplate")
    window:SetWidth(Stats.WIDTH)
    window:SetFrameStrata("HIGH")
    window:SetToplevel(true)
    window:EnableMouse(true)
    window:Hide()
    tinsert(UISpecialFrames, window:GetName())
    window:SetTitle(L["Guild statistics"])
    window:SetPortraitToAsset(Stats.ICON)
    window:SetScript("OnHide", function()
        Filters.ClearWindow()
        ns.MyData.Place()
    end)

    window.Hint = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    window.Hint:SetPoint("TOPLEFT", 64, -34)
    window.Hint:SetPoint("RIGHT", -12, 0)
    window.Hint:SetJustifyH("LEFT")
    window.Hint:SetText(L["Click a number or a bar to filter the roster."])

    local scrollFrame = CreateFrame("ScrollFrame", nil, window)
    scrollFrame:SetPoint("TOPLEFT", 12, -64)
    scrollFrame:SetPoint("BOTTOMRIGHT", -24, 10)
    local scrollBar = CreateFrame("EventFrame", nil, window, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 6, 0)
    content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(Stats.CONTENT_WIDTH)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    ScrollUtil.InitScrollFrameWithScrollBar(scrollFrame, scrollBar)
    -- The bar only while the content does not fit (the guild window may
    -- get shorter).
    scrollFrame:SetScript("OnSizeChanged", function()
        Stats.UpdateScrollBar()
    end)
    window.ScrollFrame, window.ScrollBar, window.Content = scrollFrame, scrollBar, content

    local gap = Stats.GAP
    local y = 0
    window.KindsHeading = Heading(L["Characters"], y)
    y = y - 20
    window.kindCards = {}
    local width = (Stats.CONTENT_WIDTH - 3 * gap) / 4
    for i, kind in ipairs(KIND_ORDER) do
        local card = CreateCard(width, Stats.CARD_HEIGHT, "GameFontHighlightHuge", function(self)
            Filters.ShowOnly(self.kind)
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

local function SpecItems(counts)
    local class = Filters.class
    local r, g, b = ClassColor(class)
    local tabs = {}
    for tab in pairs(counts.specs) do
        tabs[#tabs + 1] = tab
    end
    -- The trees in the game's order, the unknown last.
    table.sort(tabs, function(a, c)
        if a == Filters.UNKNOWN or c == Filters.UNKNOWN then
            return c == Filters.UNKNOWN and a ~= Filters.UNKNOWN
        end
        return a < c
    end)
    local items = {}
    for _, tab in ipairs(tabs) do
        local spec = counts.specs[tab]
        local shade = SPEC_SHADES[tab]
        local item = { count = spec.count, chosen = Filters.spec == tab }
        if tab == Filters.UNKNOWN or not shade then
            item.r, item.g, item.b, item.icon = 0.35, 0.35, 0.35, UNKNOWN_ICON
        else
            local _, icon = Filters.SpecInfo(class, tab)
            item.r, item.g, item.b, item.icon = r * shade, g * shade, b * shade, icon or UNKNOWN_ICON
        end
        item.onClick = function()
            Filters.ToggleSpec(tab)
        end
        item.onEnter = function(section)
            local lines = { { L["%d |4character:characters; (%d%%)"]:format(spec.count, Percent(spec.count, counts.specTotal)) } }
            if tab == Filters.UNKNOWN then
                lines[#lines + 1] = { L["Without builds shared through Guild Builds."], 0.7, 0.7, 0.7 }
            elseif spec.secondary > 0 then
                lines[#lines + 1] = { L["%d in their primary build, %d only in their secondary one."]:format(spec.primary, spec.secondary), 0.8, 0.8, 0.8 }
            end
            lines[#lines + 1] = FilterHint(Filters.spec == tab)
            ShowTooltip(section, SpecName(class, tab), lines)
        end
        items[#items + 1] = item
    end
    return items
end

-- Shows the numbers as they are now.
local function Draw()
    local counts = Filters.Counts()
    local only = Filters.OnlyKind()
    for _, kind in ipairs(KIND_ORDER) do
        local count = kind == "all" and counts.all or counts.kinds[kind]
        SetCard(window.kindCards[kind], count, KindLabel(kind), only == kind)
    end
    DrawBar(window.ClassBar, ClassItems(counts))

    local y = window.classY
    local class = Filters.class
    window.SpecHeading:SetShown(class ~= nil)
    window.SpecBar:SetShown(class ~= nil)
    window.Dual:SetShown(class ~= nil and counts.dual > 0)
    if class then
        window.SpecHeading:ClearAllPoints()
        window.SpecHeading:SetPoint("TOPLEFT", 2, y)
        window.SpecHeading:SetText(L["Specializations: %s"]:format(ClassName(class)))
        y = y - 20
        window.SpecBar:ClearAllPoints()
        window.SpecBar:SetPoint("TOPLEFT", 0, y)
        DrawBar(window.SpecBar, SpecItems(counts))
        y = y - Stats.BAR_HEIGHT - 4
        if counts.dual > 0 then
            window.Dual:ClearAllPoints()
            window.Dual:SetPoint("TOPLEFT", 2, y)
            window.Dual:SetText(L["%d |4character has two different specializations and counts:characters have two different specializations and count; in both."]:format(counts.dual))
            y = y - 16
        end
        y = y - 10
    end

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
    window.contentHeight = -y
    Stats.UpdateScrollBar()
end

function Stats.UpdateScrollBar()
    if window and window.contentHeight then
        window.ScrollBar:SetShown(window.contentHeight > (window.ScrollFrame:GetHeight() or 0))
    end
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

function Stats.Init()
    -- It belongs to the guild window: it goes with it.
    EventUtil.ContinueOnAddOnLoaded("Blizzard_Communities", function()
        if CommunitiesFrame and CommunitiesFrame.HookScript then
            CommunitiesFrame:HookScript("OnHide", Stats.Hide)
        end
    end)
end
