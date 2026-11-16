-- TalentTree.lua: turns a member's builds, as Guild Builds shares them, into
-- the talents of the bot's file, with the fields Bot'tar Sync wrote before
-- 0.4 (see Bot/README.md).
--
-- A build travels as the game's import string (C_Traits.GenerateImportString),
-- the text the talent window shows another build from, in Blizzard's format
-- (Blizzard_ClassTalentImportExport.lua and ExportUtil.lua): Base64
-- characters of 6 bits, each read from its lowest bit; a header with the
-- serialization version (8 bits), the spec ID (16) and the tree's hash
-- (16 x 8); then, for every node of the class's tree in C_Traits.GetTreeNodes
-- order: selected (1 bit); if selected, purchased (1); if purchased,
-- partially ranked (1) and then its ranks (6), and a choice node (1) and then
-- the entry chosen (2, from 0). A node selected but not purchased is granted,
-- at rank 1; a node purchased and not partially ranked has all its ranks.
--
-- The string has no positions, names or ranks of the nodes: they come from
-- the tree, read with a config that holds it: ours for our own class, else
-- the game's view config, which C_ClassTalents.InitializeViewLoadout sets up
-- for any spec, as the talent window does to show another build. That
-- changes what the window would show, so it is only done while the window is
-- closed, or at logout. Each tree is read once per session.
local _, ns = ...

local Tree = {}
ns.TalentTree = Tree

local Number = ns.Number
local floor = math.floor

-- Set while the file is written at logout: the talent window no longer
-- matters.
Tree.loggingOut = false

-- Reading the string ----------------------------------------------------------------

local BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local VALUE = {}
for i = 1, #BASE64 do
    VALUE[BASE64:sub(i, i)] = i - 1
end

-- A reader of a string's bits: Read(width) gives the next value, or nil past
-- the end. nil for a string with anything that is not Base64.
function Tree.BitReader(text)
    if type(text) ~= "string" then
        return nil
    end
    local values = {}
    for i = 1, #text do
        local value = VALUE[text:sub(i, i)]
        if not value then
            return nil
        end
        values[i] = value
    end
    local position = 0  -- bits read so far
    local reader = {}
    function reader.Read(width)
        local value, factor = 0, 1
        for _ = 1, width do
            local char = values[floor(position / 6) + 1]
            if not char then
                return nil
            end
            local bit = floor(char / 2 ^ (position % 6)) % 2
            value = value + bit * factor
            factor = factor * 2
            position = position + 1
        end
        return value
    end
    function reader.Bits()
        return #values * 6
    end
    return reader
end

-- A build string's header and nodes: { version, specID, hash = 16 bytes,
-- nodes = { { selected, granted, ranks (partially ranked) or nil, choice
-- (entry index, from 1) or nil } } in tree order }, or nil when the string
-- cannot hold that many nodes.
function Tree.Decode(text, nodeCount)
    local reader = Tree.BitReader(text)
    if not reader or reader.Bits() < 8 + 16 + 128 then
        return nil
    end
    local build = { version = reader.Read(8), specID = reader.Read(16), hash = {}, nodes = {} }
    for i = 1, 16 do
        build.hash[i] = reader.Read(8)
    end
    for i = 1, nodeCount do
        local selected = reader.Read(1)
        if selected == nil then
            return nil
        end
        local node = { selected = selected == 1 }
        if node.selected then
            local purchased = reader.Read(1)
            node.granted = purchased == 0
            if purchased == 1 then
                if reader.Read(1) == 1 then
                    node.ranks = reader.Read(6)
                end
                if reader.Read(1) == 1 then
                    local entry = reader.Read(2)
                    node.choice = entry and entry + 1
                end
            end
            if purchased == nil then
                return nil
            end
        end
        build.nodes[i] = node
    end
    return build
end

-- The trees, from the game ----------------------------------------------------------

local trees = {}     -- [treeID] = tree (see ReadTree), or false when unreadable
local tabNames = {}  -- [treeID] = { [group ID] = name }

local function IsTalentNode(node)
    if not ns.CanRead(node) or Number(node.ID) == nil or node.ID == 0 or node.isVisible == false or node.subTreeID then
        return false
    end
    local types = Enum.TraitNodeType
    return not (types and types.SubTreeSelection and node.type == types.SubTreeSelection)
end

local function SpellOf(configID, entryID)
    local entry = entryID and ns.Try(C_Traits.GetEntryInfo, configID, entryID)
    local definitionID = ns.CanRead(entry) and Number(entry.definitionID)
    local definition = definitionID and ns.Try(C_Traits.GetDefinitionInfo, definitionID)
    return ns.CanRead(definition) and Number(definition.spellID) or 0
end

local function OwnConfig()
    local Spec = C_SpecializationInfo
    local group = Number(Spec and ns.Try(Spec.GetActiveSpecGroup)) or 1
    local configID = Spec and Number(ns.Try(Spec.GetCombatConfigIDForSpecGroup, group))
    if not configID and C_ClassTalents then
        configID = Number(ns.Try(C_ClassTalents.GetActiveConfigID))
    end
    return configID
end

local function TreeOfConfig(configID)
    local info = configID and ns.Try(C_Traits.GetConfigInfo, configID)
    return ns.CanRead(info) and type(info.treeIDs) == "table" and Number(info.treeIDs[1]) or nil
end

local function TalentWindowShown()
    return PlayerSpellsFrame ~= nil and PlayerSpellsFrame.IsShown ~= nil and PlayerSpellsFrame:IsShown() == true
end

-- A config that holds a tree, or nil: ours, or the view config set up for
-- the spec (only when that cannot disturb the talent window).
local function ConfigFor(treeID, specID, level)
    local own = OwnConfig()
    if own and TreeOfConfig(own) == treeID then
        return own
    end
    local view = Constants and Constants.TraitConsts and Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID
    if not (view and specID and C_ClassTalents and C_ClassTalents.InitializeViewLoadout) then
        return nil
    end
    if TalentWindowShown() and not Tree.loggingOut then
        return nil
    end
    ns.Try(C_ClassTalents.InitializeViewLoadout, specID, level or 60)
    return view
end

-- A tree's nodes: { ids = node IDs in the game's order, nodes = { [node ID]
-- = { x, y, m = max rank, groups, talent = shown as a talent, spells = by
-- entry } } }, or nil when it cannot be read now.
local function ReadTree(treeID, specID, level)
    if trees[treeID] ~= nil then
        return trees[treeID] or nil
    end
    local ids = ns.Try(C_Traits.GetTreeNodes, treeID)
    local configID = ns.CanRead(ids) and ConfigFor(treeID, specID, level)
    if not configID then
        -- Maybe later (the talent window open): not remembered.
        return nil
    end
    local tree, known = { ids = {}, nodes = {} }, 0
    for i, nodeID in ipairs(ids) do
        tree.ids[i] = nodeID
        local node = ns.Try(C_Traits.GetNodeInfo, configID, nodeID)
        if ns.CanRead(node) and Number(node.ID) and node.ID ~= 0 then
            known = known + 1
            local info = {
                x = floor(Number(node.posX) or 0), y = floor(Number(node.posY) or 0),
                m = Number(node.maxRanks) or 1, groups = ns.CanRead(node.groupIDs) and node.groupIDs or {},
                talent = IsTalentNode(node), spells = {},
            }
            for j, entryID in ipairs(ns.CanRead(node.entryIDs) and node.entryIDs or {}) do
                info.spells[j] = SpellOf(configID, Number(entryID))
            end
            tree.nodes[nodeID] = info
        end
    end
    trees[treeID] = known > 0 and tree or false
    return trees[treeID] or nil
end

local function TabNames(treeID)
    if not tabNames[treeID] then
        local names = {}
        local infos = ns.Try(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
        for _, info in ipairs(ns.CanRead(infos) and infos or {}) do
            if ns.CanRead(info) and Number(info.groupID) then
                names[info.groupID] = ns.Data.CleanName(ns.Plain(info.displayName))
            end
        end
        tabNames[treeID] = names
    end
    return tabNames[treeID]
end

-- Whether a build string was made from the tree as this client knows it.
local function SameTree(build, treeID)
    local version = C_Traits.GetLoadoutSerializationVersion and Number(ns.Try(C_Traits.GetLoadoutSerializationVersion))
    if version and build.version ~= version then
        return false
    end
    local empty = true
    for _, byte in ipairs(build.hash) do
        empty = empty and byte == 0
    end
    local hash = not empty and C_Traits.GetTreeHash and ns.Try(C_Traits.GetTreeHash, treeID)
    if ns.CanRead(hash) then
        for i = 1, 16 do
            if Number(hash[i]) ~= build.hash[i] then
                return false
            end
        end
    end
    return true
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
        node.cl = step and floor((node.x - tab.minX) / step + 0.5) + 1 or 1
    end
end

-- The learned talents of a build string: { nd, sp, r, m, tb, rw, cl, x, y },
-- by tab, row and column; nil when it cannot be read.
local function LearnedTalents(text, record)
    local reader = Tree.BitReader(text)
    local specID = reader and reader.Bits() >= 24 and (reader.Read(8) and reader.Read(16))
    local tree = specID and ReadTree(record.tr, specID, record.lv)
    local build = tree and Tree.Decode(text, #tree.ids)
    if not build or not SameTree(build, record.tr) then
        return nil
    end
    local tabOf = {}
    for i, tab in ipairs(record.tb) do
        tabOf[tab.g] = i
    end
    local all, learned = {}, {}
    for i, nodeID in ipairs(tree.ids) do
        local info = tree.nodes[nodeID]
        if info and info.talent then
            local tab = 0
            for _, groupID in ipairs(info.groups) do
                if tabOf[groupID] then
                    tab = tabOf[groupID]
                    break
                end
            end
            local node = { nd = nodeID, m = info.m, tb = tab, x = info.x, y = info.y }
            all[#all + 1] = node
            local state = build.nodes[i]
            if state.selected then
                node.r = state.granted and 1 or state.ranks or info.m
                node.sp = info.spells[state.choice or 1] or info.spells[1] or 0
                learned[#learned + 1] = node
            end
        end
    end
    PlaceTalents(all)
    table.sort(learned, function(a, b)
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
    return learned
end

-- A member's talents for the bot's file, from their Guild Builds record:
-- { tr, ag, ng, un, s = { { gr, shared, tb = { { n, sp } }, t = learned
-- talents } } }, or nil without builds. A build not shared (or that this
-- client cannot read) has its tabs and points, and no talents.
function Tree.Talents(record)
    if type(record) ~= "table" or type(record.s) ~= "table" or type(record.tb) ~= "table" or not Number(record.tr) then
        return nil
    end
    local names = TabNames(record.tr)
    local talents = { tr = record.tr, ag = record.ag, ng = #record.s, un = record.un, s = {} }
    for _, spec in ipairs(record.s) do
        local out = { gr = spec.gr, shared = spec.x ~= nil, tb = {}, t = {} }
        for i, tab in ipairs(record.tb) do
            out.tb[i] = { n = names[tab.g], sp = type(spec.p) == "table" and Number(spec.p[i]) or 0 }
        end
        if spec.x then
            local ok, learned = pcall(LearnedTalents, spec.x, record)
            if ok and learned then
                out.t = learned
            else
                ns.Debug("talents of a build not read: %s", ok and "not this tree" or tostring(learned))
            end
        end
        talents.s[#talents.s + 1] = out
    end
    table.sort(talents.s, function(a, b)
        return a.gr < b.gr
    end)
    return talents
end
