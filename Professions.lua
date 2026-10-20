-- Professions.lua: reads the player's own professions and recipes.
--
-- Skill levels can be read at any time. The list of recipes only exists
-- while a profession window is open: reading it gives the character's
-- recipes and the profession's whole catalog, kept for every character of
-- the WoW account. With the catalog known, the recipes a character knows
-- are the catalog's spells in its spell book, so alts need no window at all
-- (see ReadFromCatalog). A recipe learned later is added as it is learned.
local _, ns = ...
local L = ns.L

local Professions = {}
ns.Professions = Professions

Professions.ready = false  -- the professions have been read once this session

local TRUST_DROPS_AFTER = 10   -- seconds after login before a missing profession counts as dropped
local HINT_DELAY = 30

-- Professions without a recipe window, for a client that cannot tell
-- (Herbalism, Skinning, Fishing).
local NO_RECIPES_FALLBACK = { [182] = true, [393] = true, [356] = true }

local TradeSkill = C_TradeSkillUI or {}

-- The professions the character has, from the character's skills.
-- [skillLine] = { r, m, o, lk, hasRecipes }
local function ReadProfessions()
    local found = {}
    local indices = { GetProfessions() }
    for order = 1, select("#", GetProfessions()) do
        local index = indices[order]
        if index then
            local _, _, rank, maxRank, _, spellOffset, skillLine = GetProfessionInfo(index)
            skillLine, rank, maxRank = ns.Plain(skillLine), ns.Plain(rank), ns.Plain(maxRank)
            if type(skillLine) == "number" and skillLine > 0 and type(rank) == "number" then
                local spellID
                local info = C_SpellBook and ns.Try(C_SpellBook.GetSpellBookItemInfo, (spellOffset or 0) + 1, Enum.SpellBookSpellBank.Player)
                if type(info) == "table" then
                    spellID = ns.Plain(info.spellID)
                end
                local hasRecipes
                if spellID then
                    hasRecipes = ns.Try(TradeSkill.CanTradeSkillShowCraftingUI, spellID)
                end
                if hasRecipes == nil then
                    hasRecipes = not NO_RECIPES_FALLBACK[skillLine]
                end
                found[skillLine] = { r = rank, m = maxRank or rank, o = order, lk = spellID, hasRecipes = hasRecipes and true or false }
            end
        end
    end
    return found
end

-- Brings our record's professions and levels up to date.
function Professions.UpdateLevels()
    local record = ns.Data.GetOwnRecord(true)
    if not record then
        return
    end
    local found = ReadProfessions()
    local trustDrops = GetTime() - (ns.loginTime or 0) >= TRUST_DROPS_AFTER
    local ranksChanged, setChanged = false, false
    local professions = {}

    for skillLine, info in pairs(found) do
        local old = record.p[skillLine]
        local k
        if old and type(old.k) == "table" then
            -- A list can only come from a recipe window, so a "no recipes"
            -- answer (possible while the client is still loading) never
            -- replaces one.
            k = old.k
        elseif not info.hasRecipes then
            k = false
        end
        professions[skillLine] = { r = info.r, m = info.m, o = info.o, lk = info.lk or (old and old.lk), k = k }
        if not old then
            setChanged = true
        elseif old.o ~= info.o or old.lk ~= professions[skillLine].lk or (old.k == false) ~= (k == false) then
            setChanged = true
        elseif old.r ~= info.r or old.m ~= info.m then
            ranksChanged = true
        end
    end
    for skillLine, old in pairs(record.p) do
        if not found[skillLine] then
            if trustDrops then
                setChanged = true
            else
                professions[skillLine] = old
            end
        end
    end

    -- A record copied from the one kept for another guild (see
    -- Data.GetOwnRecord) has never been stamped for this guild.
    if not ns.Data.IsShareable(record) and next(professions) ~= nil then
        setChanged = true
    end

    Professions.ready = Professions.ready or trustDrops or next(found) ~= nil
    if setChanged or ranksChanged then
        record.p = professions
        ns.Data.TouchOwn(record)
        ns.Debug("own professions updated (%s)", setChanged and "set" or "levels")
    end
    Professions.ReadFromCatalog()
end

-- Recipes --------------------------------------------------------------------

-- True while the open profession window shows our own profession (not a
-- linked one, a guild member's or an NPC's).
local function IsOwnSession()
    if ns.Try(TradeSkill.IsTradeSkillReady) ~= true or ns.Try(TradeSkill.IsDataSourceChanging) == true then
        return false
    end
    for _, check in ipairs({ TradeSkill.IsTradeSkillLinked, TradeSkill.IsTradeSkillGuild, TradeSkill.IsTradeSkillGuildMember, TradeSkill.IsNPCCrafting }) do
        if ns.Try(check) then
            return false
        end
    end
    return true
end

local function SessionSkillLine()
    local info = ns.Try(TradeSkill.GetChildProfessionInfo)
    if type(info) ~= "table" or not info.professionID or info.professionID == 0 then
        info = ns.Try(TradeSkill.GetBaseProfessionInfo)
    end
    if type(info) ~= "table" then
        return nil
    end
    local parent = info.parentProfessionID
    if parent and parent > 0 then
        return parent
    end
    return info.professionID
end

-- Returns the recipe IDs of the open window, and true when they are only
-- the ones its search and filters show.
local function SessionRecipeIDs()
    local ids = ns.Try(TradeSkill.GetAllRecipeIDs)
    if type(ids) == "table" and #ids > 0 then
        return ids, false
    end
    ids = ns.Try(TradeSkill.GetFilteredRecipeIDs)
    return type(ids) == "table" and ids or {}, true
end

local function SameList(a, b)
    if type(a) ~= "table" or #a ~= #b then
        return false
    end
    for i = 1, #a do
        if a[i] ~= b[i] then
            return false
        end
    end
    return true
end

local function IsSpellKnown(spellID)
    local isKnown = IsPlayerSpell or (C_SpellBook and C_SpellBook.IsSpellKnown)
    return isKnown ~= nil and ns.Try(isKnown, spellID) == true
end

-- The recipes of a profession worth checking against the spell book (see
-- ReadFromCatalog). Some of the window's entries are spells a character
-- knows without the window counting them as learned recipes; read from the
-- spell book they would show up as recipes, so our own window leaves them
-- out. A window on someone else's profession cannot tell them apart.
local function CatalogFrom(ids, own)
    local catalog, phantoms = {}, 0
    for _, recipeID in ipairs(ids) do
        local info = ns.Try(TradeSkill.GetRecipeInfo, recipeID)
        if type(info) == "table" and not info.isDummyRecipe then
            if own and not info.learned and IsSpellKnown(recipeID) then
                phantoms = phantoms + 1
            else
                catalog[#catalog + 1] = recipeID
            end
        end
    end
    return catalog, phantoms
end

function Professions.ScanOpenProfession()
    if ns.Try(TradeSkill.IsTradeSkillReady) ~= true or ns.Try(TradeSkill.IsDataSourceChanging) == true then
        return
    end
    local ids, filtered = SessionRecipeIDs()
    local skillLine = SessionSkillLine()
    local own = IsOwnSession()
    if skillLine and not filtered and (own or not ns.Data.Catalog(skillLine)) then
        local catalog, phantoms = CatalogFrom(ids, own)
        ns.Data.SetCatalog(skillLine, catalog)
        if phantoms > 0 then
            ns.Debug("%d known spells of %d are not recipes", phantoms, skillLine)
        end
    end
    if not own then
        return
    end
    local record = ns.Data.GetOwnRecord(true)
    if not skillLine or not record then
        return
    end
    if not record.p[skillLine] then
        Professions.UpdateLevels()
    end
    local prof = record.p[skillLine]
    if not prof then
        ns.Debug("open profession %s is not one of ours", tostring(skillLine))
        return
    end

    local learned, seen = {}, {}
    if filtered and type(prof.k) == "table" then
        -- Only what the window's search shows: add to the list, never cut it.
        for _, recipeID in ipairs(prof.k) do
            seen[recipeID] = true
            learned[#learned + 1] = recipeID
        end
    end
    for _, recipeID in ipairs(ids) do
        local info = ns.Try(TradeSkill.GetRecipeInfo, recipeID)
        if type(info) == "table" and info.learned and not info.isDummyRecipe and not seen[recipeID] then
            seen[recipeID] = true
            learned[#learned + 1] = recipeID
        end
    end
    table.sort(learned)
    if #learned == 0 and type(prof.k) == "table" and #prof.k > 0 then
        -- An empty answer while recipes were known is a loading hiccup.
        return
    end
    if not SameList(prof.k, learned) then
        prof.k = learned
        ns.Data.TouchOwn(record)
        ns.Debug("read %d recipes of %d", #learned, skillLine)
    end
end

-- Recipes are spells. Once any character of the account has opened a
-- profession's window, its full recipe list is known (Data.Catalog), and the
-- recipes a character knows are the ones it has as spells: its alts get
-- their lists without opening anything. This only adds recipes; the window
-- read stays the reference.
function Professions.ReadFromCatalog()
    local record = ns.Data.GetOwnRecord(false)
    if not record or not (IsPlayerSpell or (C_SpellBook and C_SpellBook.IsSpellKnown)) then
        return
    end
    local changed = false
    for skillLine, prof in pairs(record.p) do
        local catalog = ns.Data.Catalog(skillLine)
        if catalog and prof.k ~= false then
            local list, have = {}, {}
            for _, id in ipairs(type(prof.k) == "table" and prof.k or {}) do
                list[#list + 1] = id
                have[id] = true
            end
            local added = false
            for _, id in ipairs(catalog) do
                if not have[id] and IsSpellKnown(id) then
                    list[#list + 1] = id
                    have[id] = true
                    added = true
                end
            end
            if added then
                table.sort(list)
                prof.k = list
                changed = true
            end
        end
    end
    if changed then
        ns.Data.TouchOwn(record)
        ns.Debug("recipes read from the spell book")
    end
end

-- A recipe learned with no window open goes straight into its profession's
-- list, if that list is known (otherwise the next window read finds it).
local function OnRecipeLearned(recipeID)
    if not recipeID then
        return
    end
    if ns.Try(TradeSkill.IsTradeSkillReady) == true then
        ns.Debounce("ScanOpenProfession", 0.5, Professions.ScanOpenProfession)
        return
    end
    local skillLine
    local info = ns.Try(TradeSkill.GetProfessionInfoByRecipeID, recipeID)
    if type(info) == "table" then
        skillLine = info.parentProfessionID or info.professionID
    end
    if not skillLine or skillLine == 0 then
        local tradeSkillID, _, parentID = ns.Try(TradeSkill.GetTradeSkillLineForRecipe, recipeID)
        skillLine = parentID or tradeSkillID
    end
    local record = ns.Data.GetOwnRecord(true)
    local prof = record and skillLine and record.p[skillLine]
    if not prof or type(prof.k) ~= "table" then
        Professions.ReadFromCatalog()
        return
    end
    for _, id in ipairs(prof.k) do
        if id == recipeID then
            return
        end
    end
    local list = { unpack(prof.k) }
    list[#list + 1] = recipeID
    table.sort(list)
    prof.k = list
    ns.Data.TouchOwn(record)
end

-- Once per profession and character, in a single line: a reminder to open
-- the windows whose recipes have not been read yet.
local function ShowHints()
    local record = ns.Data.GetOwnRecord(false)
    if not record then
        return
    end
    local hinted = ns.Data.OwnState().hinted
    local names = {}
    for _, prof in ipairs(ns.Data.SortedProfessions(record)) do
        if prof.k == nil and not hinted[prof.sl] and not ns.Data.Catalog(prof.sl) then
            hinted[prof.sl] = true
            names[#names + 1] = ns.ProfessionName(prof.sl, prof.lk) or ("#" .. prof.sl)
        end
    end
    if #names > 0 then
        ns.Print(L["open these profession windows once so your recipes reach the guild and the bot: %s."], table.concat(names, ", "))
    end
end

function Professions.Init()
    local events = CreateFrame("Frame")
    ns.RegisterEvents(events,
        "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE",
        "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
        "NEW_RECIPE_LEARNED")
    events:SetScript("OnEvent", function(_, event, ...)
        if event == "NEW_RECIPE_LEARNED" then
            OnRecipeLearned(ns.Plain((...)))
        elseif event == "SKILL_LINES_CHANGED" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
            ns.Debounce("UpdateLevels", 2, Professions.UpdateLevels)
        else
            ns.Debounce("ScanOpenProfession", 0.5, Professions.ScanOpenProfession)
        end
    end)
    ns.On("GuildChanged", function()
        ns.Debounce("UpdateLevels", 2, Professions.UpdateLevels)
    end)
    Professions.UpdateLevels()
    -- Once more after the login has settled, when dropped professions count.
    C_Timer.After(TRUST_DROPS_AFTER + 1, Professions.UpdateLevels)
    C_Timer.After(HINT_DELAY, ShowHints)
end
