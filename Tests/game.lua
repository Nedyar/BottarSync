-- What the game gives that the shared harness does not simulate, for every
-- test file. The clients load the guild's other addons too (see run.lua), so
-- Guild Builds' own additions come first (its Tests/game.lua, from the folder
-- next to this addon's). Then, what the bot's file needs to read builds
-- (TalentTree.lua):
--   - the game's import strings in their real format (H.EncodeBuild), which
--     Guild Builds shares;
--   - a tree for each of two classes (the harness's H.TREE for hunters,
--     H.MAGE_TREE for mages): a client reads only its own class's tree with
--     its own configs, and any other through the view config, set up by
--     C_ClassTalents.InitializeViewLoadout (recorded in client.viewLoadouts).
return function(H)
    dofile(ADDON_PATH .. "/../GuildBuilds/Tests/game.lua")(H)

    -- Edit boxes have the keyboard while a test says so (_focus).
    H.FrameMethods.HasFocus = function(self)
        return self._focus == true
    end
    -- A check box's label, and widget looks the tests do not check.
    H.TemplateRegions.UICheckButtonTemplate = H.TemplateRegions.UICheckButtonTemplate or { Text = "FontString" }
    H.NoOpMethods.SetHighlightAtlas = true
    -- A text's height: 12 pixels a line, its lines as wide as the text is
    -- set to be (6 pixels a character, as GetStringWidth).
    H.FrameMethods.GetStringHeight = function(self)
        local width = 6 * #(self._text or "")
        return 12 * math.max(1, math.ceil(width / (self._width or math.huge)))
    end

    H.MAGE_TREE = {
        id = 774,
        tabs = { { groupID = 21, name = "Arcane" }, { groupID = 22, name = "Fire" }, { groupID = 23, name = "Frost" } },
        -- id, tab, column, row, max rank (as H.TREE).
        nodes = {
            { 1101, 1, 1, 1, 5 }, { 1102, 1, 2, 1, 5 }, { 1103, 1, 2, 2, 3 },
            { 1201, 2, 2, 1, 5 }, { 1202, 2, 1, 2, 2 },
            { 1301, 3, 2, 1, 5 }, { 1302, 3, 3, 1, 3 }, { 1303, 3, 1, 3, 1 },
        },
    }
    -- Each class's spec ID (WoW Forever has one per class) and tree.
    H.SPECS = { [3] = 255, [8] = 62 }
    local TREE_OF_SPEC = { [255] = H.TREE, [62] = H.MAGE_TREE }
    H.LOADOUT_VERSION = 2
    local VIEW = -3

    local function TreeByID(treeID)
        return treeID == H.MAGE_TREE.id and H.MAGE_TREE or H.TREE
    end
    -- A tree's node IDs, in the game's order (ascending), and its nodes.
    local function TreeNodes(tree)
        local ids, byID = {}, {}
        for _, node in ipairs(tree.nodes) do
            ids[#ids + 1] = node[1]
            byID[node[1]] = node
        end
        if tree.hidden then
            ids[#ids + 1] = tree.hidden[1]
            byID[tree.hidden[1]] = tree.hidden
        end
        table.sort(ids)
        return ids, byID
    end
    function H.TreeHash(tree)
        local hash = {}
        for i = 1, 16 do
            hash[i] = (tree.id * i) % 256
        end
        return hash
    end

    -- Bits, lowest first, six to a Base64 character (as the game's ExportUtil).
    local BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local function BitWriter()
        local bits, writer = {}, {}
        function writer.Add(width, value)
            for _ = 1, width do
                bits[#bits + 1] = value % 2
                value = math.floor(value / 2)
            end
        end
        function writer.Text()
            local out = {}
            for i = 1, #bits, 6 do
                local value = 0
                for j = 0, 5 do
                    value = value + (bits[i + j] or 0) * 2 ^ j
                end
                out[#out + 1] = BASE64:sub(value + 1, value + 1)
            end
            return table.concat(out)
        end
        return writer
    end

    -- A build's import string in the game's format. ranks = { [node ID] =
    -- rank }; options: version, hash (16 bytes), granted = { [node ID] = true },
    -- choices = { [node ID] = entry index }.
    function H.EncodeBuild(specID, ranks, options)
        options = options or {}
        local tree = TREE_OF_SPEC[specID]
        local ids, byID = TreeNodes(tree)
        local writer = BitWriter()
        writer.Add(8, options.version or H.LOADOUT_VERSION)
        writer.Add(16, specID)
        for _, byte in ipairs(options.hash or H.TreeHash(tree)) do
            writer.Add(8, byte)
        end
        for _, nodeID in ipairs(ids) do
            local rank = ranks[nodeID] or 0
            local granted = options.granted and options.granted[nodeID]
            writer.Add(1, (rank > 0 or granted) and 1 or 0)
            if granted then
                writer.Add(1, 0)
            elseif rank > 0 then
                writer.Add(1, 1)
                local partial = rank ~= byID[nodeID][5]
                writer.Add(1, partial and 1 or 0)
                if partial then
                    writer.Add(6, rank)
                end
                local choice = options.choices and options.choices[nodeID]
                writer.Add(1, choice and 1 or 0)
                if choice then
                    writer.Add(2, choice - 1)
                end
            end
        end
        return writer.Text()
    end

    local NewWorld = H.NewWorld
    function H.NewWorld(options)
        local world = NewWorld(options)
        local MakeEnv = world.MakeEnv
        world.MakeEnv = function(self, client)
            local env = MakeEnv(self, client)
            client.viewLoadouts = {}
            local ownTree = client.classID == 8 and H.MAGE_TREE or H.TREE
            local viewTree
            local function TreeOfConfig(configID)
                if configID == VIEW then
                    return viewTree
                end
                return ownTree
            end
            local function Ranks(configID)
                local groups = client.talents and client.talents.groups
                return configID ~= VIEW and groups and groups[configID - 500] or {}
            end
            local Traits = env.C_Traits
            Traits.GetConfigInfo = function(configID)
                local tree = TreeOfConfig(configID)
                return tree and { ID = configID, treeIDs = { tree.id } } or nil
            end
            Traits.GetTreeNodes = function(treeID)
                return (TreeNodes(TreeByID(treeID)))
            end
            Traits.GetNodeInfo = function(configID, nodeID)
                local tree = TreeOfConfig(configID)
                local _, byID = TreeNodes(tree or {})
                local node = tree and byID[nodeID]
                if not node then
                    return { ID = 0 }
                end
                local rank = Ranks(configID)[nodeID] or 0
                local x, y = H.NodePosition(node)
                return {
                    ID = nodeID, isVisible = node ~= tree.hidden, type = 0, posX = x, posY = y, maxRanks = node[5],
                    activeRank = rank, ranksPurchased = rank, currentRank = rank,
                    groupIDs = { 1, tree.tabs[node[2]].groupID },
                    entryIDs = { nodeID * 10 }, activeEntry = { entryID = nodeID * 10, rank = rank },
                }
            end
            Traits.GetGroupDisplayInfoByTreeID = function(treeID)
                local tree, list = TreeByID(treeID), {}
                for i, tab in ipairs(tree.tabs) do
                    list[i] = { groupID = tab.groupID, treeID = tree.id, displayName = tab.name, icon = i, orderIndex = i }
                end
                return list
            end
            Traits.GetGroupCurrencyInfo = function(configID, groupIDs)
                local tree = TreeOfConfig(configID)
                local _, byID = TreeNodes(tree)
                local list = {}
                for _, groupID in ipairs(groupIDs) do
                    local spent = 0
                    for nodeID, rank in pairs(Ranks(configID)) do
                        local node = byID[nodeID]
                        if node and tree.tabs[node[2]].groupID == groupID then
                            spent = spent + rank
                        end
                    end
                    list[#list + 1] = { traitNodeGroupID = groupID, currencyInfos = { { spent = spent, quantity = 0 } } }
                end
                return list
            end
            Traits.GetLoadoutSerializationVersion = function()
                return H.LOADOUT_VERSION
            end
            Traits.GetTreeHash = function(treeID)
                return H.TreeHash(TreeByID(treeID))
            end
            Traits.GenerateImportString = function(configID)
                local ranks = Ranks(configID)
                if not next(ranks) and not (client.talents and client.talents.groups[configID - 500]) then
                    return nil
                end
                return H.EncodeBuild(H.SPECS[client.classID] or 255, ranks)
            end
            env.C_ClassTalents.InitializeViewLoadout = function(specID, level)
                client.viewLoadouts[#client.viewLoadouts + 1] = { specID = specID, level = level }
                viewTree = TREE_OF_SPEC[specID]
            end
            env.C_ClassTalents.GetTraitTreeForSpec = function(specID)
                return TREE_OF_SPEC[specID] and TREE_OF_SPEC[specID].id
            end
            env.Constants = env.Constants or {}
            env.Constants.TraitConsts = { VIEW_TRAIT_CONFIG_ID = VIEW }
            return env
        end
        return world
    end
end
