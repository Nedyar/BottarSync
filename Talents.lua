-- Talents.lua: reads the player's own talents.
--
-- WoW Forever's talents are a trait tree (C_Traits), one per class, as in
-- Blizzard's Camelot talent window (Blizzard_PlayerSpells): the three
-- classic tabs are node groups of that tree (GetGroupDisplayInfoByTreeID),
-- and each talent node belongs to one of them through its groupIDs. With
-- dual spec, each spec group has its own config
-- (GetCombatConfigIDForSpecGroup). The client gives no rows or columns,
-- only positions in tree units, so they are worked out from the positions
-- of all the tab's talents.
local _, ns = ...

local Talents = {}
ns.Talents = Talents

Talents.ready = false  -- read at least once this session
Talents.lastError = nil

local Number = ns.Number
local RETRY_INTERVAL = 10
local MAX_RETRIES = 30

local function ActiveSpecGroup()
    local Spec = C_SpecializationInfo
    return Number(Spec and ns.Try(Spec.GetActiveSpecGroup)) or 1
end

local function SpecGroupCount()
    local count = Number(ns.Try(GetNumSpecGroups))
    return count and count >= 1 and count or 1
end

local function ConfigForSpecGroup(group, active)
    local Spec = C_SpecializationInfo
    local configID = Spec and Number(ns.Try(Spec.GetCombatConfigIDForSpecGroup, group))
    if not configID and active and C_ClassTalents then
        configID = Number(ns.Try(C_ClassTalents.GetActiveConfigID))
    end
    return configID
end

local function TreeOf(configID)
    local info = ns.Try(C_Traits.GetConfigInfo, configID)
    if not ns.CanRead(info) or type(info.treeIDs) ~= "table" then
        return nil
    end
    return Number(info.treeIDs[1])
end

-- The tree's tabs, left to right: { g = group ID, n = name }.
local function ReadTabs(treeID)
    local tabs = {}
    local infos = ns.Try(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
    if not ns.CanRead(infos) then
        return tabs
    end
    for _, info in ipairs(infos) do
        if ns.CanRead(info) and Number(info.groupID) then
            tabs[#tabs + 1] = { g = info.groupID, n = ns.Data.CleanName(ns.Plain(info.displayName)) }
        end
    end
    return tabs
end

local function SpentPerTab(configID, tabs)
    local spent, ids, index = {}, {}, {}
    for i, tab in ipairs(tabs) do
        ids[i] = tab.g
        index[tab.g] = i
    end
    local infos = #ids > 0 and ns.Try(C_Traits.GetGroupCurrencyInfo, configID, ids)
    if ns.CanRead(infos) then
        for _, info in ipairs(infos) do
            local i = ns.CanRead(info) and index[info.traitNodeGroupID]
            local currency = i and ns.CanRead(info.currencyInfos) and info.currencyInfos[1]
            if currency and ns.CanRead(currency) and Number(currency.spent) then
                spent[i] = currency.spent
            end
        end
    end
    return spent
end

local function UnspentPoints(configID, treeID)
    local infos = ns.Try(C_Traits.GetTreeCurrencyInfo, configID, treeID, true)
    local first = ns.CanRead(infos) and infos[1]
    return first and ns.CanRead(first) and Number(first.quantity) or 0
end

local function IsTalentNode(node)
    if not ns.CanRead(node) or Number(node.ID) == nil or node.ID == 0 or node.isVisible == false or node.subTreeID then
        return false
    end
    local types = Enum.TraitNodeType
    return not (types and types.SubTreeSelection and node.type == types.SubTreeSelection)
end

local function SpellOf(configID, node)
    local entryID = ns.CanRead(node.activeEntry) and Number(node.activeEntry.entryID)
    if not entryID and ns.CanRead(node.entryIDs) then
        entryID = Number(node.entryIDs[1])
    end
    local entry = entryID and ns.Try(C_Traits.GetEntryInfo, configID, entryID)
    local definitionID = ns.CanRead(entry) and Number(entry.definitionID)
    local definition = definitionID and ns.Try(C_Traits.GetDefinitionInfo, definitionID)
    return ns.CanRead(definition) and Number(definition.spellID) or nil
end

-- Rows and columns from positions: a row per distinct height in the tab, a
-- column per step of the smallest horizontal gap in the tree.
local function PlaceTalents(nodes)
    local xs, step = {}, nil
    for _, node in ipairs(nodes) do
        xs[#xs + 1] = node.x
    end
    table.sort(xs)
    for i = 2, #xs do
        local gap = xs[i] - xs[i - 1]
        if gap > 0 and (not step or gap < step) then
            step = gap
        end
    end
    local byTab = {}
    for _, node in ipairs(nodes) do
        local tab = byTab[node.tb]
        if not tab then
            tab = { minX = node.x, ys = {} }
            byTab[node.tb] = tab
        end
        tab.minX = math.min(tab.minX, node.x)
        tab.ys[node.y] = true
    end
    for _, tab in pairs(byTab) do
        local ys = {}
        for y in pairs(tab.ys) do
            ys[#ys + 1] = y
        end
        table.sort(ys)
        tab.row = {}
        for i, y in ipairs(ys) do
            tab.row[y] = i
        end
    end
    for _, node in ipairs(nodes) do
        local tab = byTab[node.tb]
        node.rw = tab.row[node.y]
        node.cl = step and math.floor((node.x - tab.minX) / step + 0.5) + 1 or 1
    end
end

-- One spec group's talents: { gr, tb = tabs with points spent, t = learned
-- talents }, or nil when its config cannot be read.
local function ReadSpec(group, configID, treeID, tabs)
    local nodeIDs = ns.Try(C_Traits.GetTreeNodes, treeID)
    if not ns.CanRead(nodeIDs) then
        return nil
    end
    local tabOf = {}
    for i, tab in ipairs(tabs) do
        tabOf[tab.g] = i
    end
    local nodes, sums = {}, {}
    for _, nodeID in ipairs(nodeIDs) do
        local node = ns.Try(C_Traits.GetNodeInfo, configID, nodeID)
        if IsTalentNode(node) then
            local tab = 0
            if ns.CanRead(node.groupIDs) then
                for _, groupID in ipairs(node.groupIDs) do
                    if tabOf[groupID] then
                        tab = tabOf[groupID]
                        break
                    end
                end
            end
            -- activeRank is what the character has now; the other two can
            -- include changes not yet applied.
            local rank = Number(node.activeRank) or Number(node.ranksPurchased) or Number(node.currentRank) or 0
            nodes[#nodes + 1] = {
                nd = nodeID, r = rank, m = Number(node.maxRanks) or rank, tb = tab,
                x = math.floor(Number(node.posX) or 0), y = math.floor(Number(node.posY) or 0),
                info = node,
            }
            sums[tab] = (sums[tab] or 0) + rank
        end
    end
    if #nodes == 0 then
        return nil
    end
    PlaceTalents(nodes)
    local spent = SpentPerTab(configID, tabs)
    local spec = { gr = group, tb = {}, t = {} }
    for i, tab in ipairs(tabs) do
        spec.tb[i] = { g = tab.g, n = tab.n, sp = spent[i] or sums[i] or 0 }
    end
    for _, node in ipairs(nodes) do
        if node.r > 0 then
            node.sp = SpellOf(configID, node.info) or 0
            spec.t[#spec.t + 1] = node
        end
        node.info = nil
    end
    table.sort(spec.t, function(a, b)
        if a.tb ~= b.tb then
            return a.tb < b.tb
        end
        if a.rw ~= b.rw then
            return a.rw < b.rw
        end
        if a.cl ~= b.cl then
            return a.cl < b.cl
        end
        return a.nd < b.nd
    end)
    return spec
end

-- Every spec group's talents, or nil (with Talents.lastError) when the
-- client cannot give them yet.
function Talents.Read()
    if not (C_Traits and C_Traits.GetConfigInfo) then
        Talents.lastError = "no C_Traits"
        return nil
    end
    local active = ActiveSpecGroup()
    local activeConfig = ConfigForSpecGroup(active, true)
    if not activeConfig then
        Talents.lastError = "no talent config yet"
        return nil
    end
    if ns.Try(C_Traits.ConfigHasStagedChanges, activeConfig) == true then
        -- Talents picked in the window but not applied yet.
        Talents.lastError = "changes not applied yet"
        return nil
    end
    local treeID = TreeOf(activeConfig)
    if not treeID then
        Talents.lastError = "no talent tree"
        return nil
    end
    local tabs = ReadTabs(treeID)
    local talents = { tr = treeID, ag = active, ng = SpecGroupCount(), un = UnspentPoints(activeConfig, treeID), s = {} }
    for group = 1, talents.ng do
        local configID = group == active and activeConfig or ConfigForSpecGroup(group, false)
        local spec = configID and ReadSpec(group, configID, treeID, tabs)
        if spec then
            talents.s[#talents.s + 1] = spec
        elseif group == active then
            Talents.lastError = "the active talents could not be read"
            return nil
        end
    end
    Talents.lastError = nil
    return talents
end

function Talents.Update()
    local record = ns.Data.GetOwnRecord(true)
    if not record then
        return false
    end
    local talents = Talents.Read()
    if not talents then
        ns.Debug("talents not read: %s", tostring(Talents.lastError))
        return false
    end
    Talents.ready = true
    if not ns.Same(record.tl, talents) then
        record.tl = talents
        ns.Data.TouchOwn(record)
        ns.Debug("own talents updated")
    end
    return true
end

function Talents.Init()
    local events = CreateFrame("Frame")
    ns.RegisterEvents(events,
        "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_TALENT_UPDATE",
        "TRAIT_CONFIG_LIST_UPDATED", "TRAIT_CONFIG_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED",
        "ACTIVE_COMBAT_CONFIG_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED")
    events:SetScript("OnEvent", function()
        ns.Debounce("TalentsUpdate", 2, Talents.Update)
    end)
    ns.On("GuildChanged", function()
        ns.Debounce("TalentsUpdate", 2, Talents.Update)
    end)
    -- The talent config can arrive a while after login.
    local tries = 0
    local ticker
    ticker = C_Timer.NewTicker(RETRY_INTERVAL, function()
        tries = tries + 1
        if Talents.ready or tries > MAX_RETRIES then
            ticker:Cancel()
            return
        end
        Talents.Update()
    end)
    Talents.Update()
end
