local H = ...

local function Errors(world, label)
    H.eq(#world.errors, 0, "no errors: " .. label)
    for _, err in ipairs(world.errors) do
        print("   " .. err)
    end
    world.errors = {}
end

local function Find(list, field, value)
    for _, item in ipairs(list or {}) do
        if item[field] == value then
            return item
        end
    end
end

local NULL = H.NULL

-- A client's copy of another's record, in one of the addons it runs.
local function CopyIn(client, addonName, other)
    local guild = client.namespaces[addonName].Data.GetGuild("Test Guild")
    return guild and guild.members[other.guid]
end

local world = H.NewWorld({ seed = 3, senderFormat = "short", strictWhispers = true })
local alice = world:NewClient("Alice Smith", {
    professions = { { sl = 165, r = 300, m = 300, spell = 10662, hasRecipes = true }, { sl = 393, r = 275, m = 300, spell = 10768, hasRecipes = false } },
    talents = { active = 1, groups = { [1] = { [101] = 5, [102] = 3, [103] = 2, [201] = 5, [205] = 1 }, [2] = { [301] = 5 } }, unspent = 2 },
    gear = {
        [1] = { link = "|cffa335ee|Hitem:16939:1503:0:0:0:0:0:99:60|h[Dragonstalker's Helm]|h|r", il = 76 },
        [18] = { link = "|cff1eff00|Hitem:15287:0:0:0:0:0:1197:98:60|h[Crusader Bow]|h|r", il = 61 },
    },
    itemLevel = 52.375,
    rank = "Officer", rankIndex = 1, note = 'Main "hunter" \\ tank',
})
local carol = world:NewClient("Carol White", { classID = 8, raceID = 1, sex = 2, rank = "Guild Master", rankIndex = 0 })
world:AddMember("Dan Brown", nil, { class = "PRIEST", level = 42, rank = "Initiate", rankIndex = 4, note = "Ñoño 한국", offline = { 0, 1, 2, 5 } })
world:AddMember("Erin Gray", nil, { class = "ROGUE", level = 60 })
world:Login(alice)
world:RunFor(5)
world:OpenProfession(alice, 165, { 1001, 1002, 1003 }, { 1001, 1003 })
-- Talents go to the guild once their owner shares them (in Guild Builds).
alice.namespaces.GuildBuilds.Talents.SetShared(1, true)
alice.namespaces.GuildBuilds.Talents.SetShared(2, true)
world:Login(carol)
world:RunUntil(function()
    local crafts = CopyIn(carol, "GuildProfessionsRecipes", alice)
    local builds = CopyIn(carol, "GuildBuilds", alice)
    return crafts and crafts.p and crafts.p[165] and type(crafts.p[165].k) == "table"
        and builds and builds.s and builds.s[2] and builds.s[2].x and builds.w
end, 300)
world:RunFor(60)
Errors(world, "setup")

H.section("Export: the file at logout")
world:Logout(carol)
local jsonText = carol.saved.BottarSyncJSON
H.eq(type(jsonText), "string", "the JSON is saved in BottarSyncJSON")
local ok, data = pcall(H.DecodeJSON, jsonText or "")
H.check(ok, "it is valid JSON" .. (ok and "" or (": " .. tostring(data))))
if not ok then
    return
end
H.check(not jsonText:find("\n", 1, true), "compact: a single line")
H.eq(data.format, 1, "format version")
H.eq(data.addon, "Bot'tar Sync", "addon name")
H.eq(data.addonVersion, H.MAIN.fields.Version, "addon version, from the TOC")
H.eq(type(data.generatedAt), "number", "generation time")
H.check(type(data.generatedAtUtc) == "string" and data.generatedAtUtc:find("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$") ~= nil, "UTC time in ISO 8601")
H.eq(data.locale, "enUS", "names are in the exporting client's language")
H.eq(data.exportedBy.name, "Carol White", "who wrote the file")
H.eq(type(carol.saved.GuildProfessionsRecipesDB.guilds["Test Guild"].members[alice.guid].p[165].k), "string",
    "Guild Professions & Recipes had packed its records for saving first")
H.eq(#data.guilds, 1, "one guild")
local guild = data.guilds[1]
H.eq(guild.name, "Test Guild", "guild name")
H.eq(guild.memberCount, 4, "every roster member, with the addon or not")
H.eq(guild.membersWithAddon, 2, "two with the addon")
H.eq(type(guild.rosterUpdatedAt), "number", "when the roster was read")
local names = {}
for i, member in ipairs(guild.members) do
    names[i] = member.name
end
H.eq(table.concat(names, ","), "Alice Smith,Carol White,Dan Brown,Erin Gray", "members sorted by name")

H.section("Export: a member with the addon")
local a = Find(guild.members, "name", "Alice Smith")
H.eq(table.concat(a._order, ","),
    "guid,name,realm,level,class,race,sex,faction,inRoster,rank,note,online,lastOnline,hasAddon,updatedAt,addonVersion,discord,main,pending,itemLevel,professions,talents,equipment",
    "member fields, in the documented order")
H.eq(a.guid, alice.guid, "GUID")
H.eq(a.realm, "TestRealm", "realm")
H.eq(a.level, 60, "level")
H.eq(a.class.id, 3, "class ID")
H.eq(a.class.token, "HUNTER", "class token")
H.eq(a.class.name, "Hunter", "class name")
H.eq(a.race.token, "NightElf", "race token")
H.eq(a.race.name, "Night Elf", "race name")
H.eq(a.sex, "female", "sex")
H.eq(a.faction, "Alliance", "faction")
H.eq(a.inRoster, true, "in the roster")
H.eq(a.rank.index, 1, "rank index")
H.eq(a.rank.name, "Officer", "rank name")
H.eq(a.note, 'Main "hunter" \\ tank', "note, with quotes and a backslash")
H.eq(a.online, true, "online")
H.eq(a.lastOnline, data.generatedAt, "online now")
H.eq(a.hasAddon, true, "has the addon")
H.eq(type(a.updatedAt), "number", "update time")
-- The version each member tells the guild (ANNOUNCE_AS while a version is
-- tried before its release), not the TOC's.
H.eq(a.addonVersion, alice.ns.VersionString(alice.ns.VERSION_NUM), "their addon version, as they announce it")
-- As Guild Builds works it out from the items worn: helm and bow over 17.
H.eq(a.itemLevel, 8.06, "item level")

local leather = Find(a.professions, "id", 165)
H.check(leather ~= nil, "Leatherworking listed")
if leather then
    H.eq(leather.name, "Skill165", "profession name")
    H.eq(leather.rank, 300, "skill")
    H.eq(leather.maxRank, 300, "max skill")
    H.eq(#leather.recipes, 2, "learned recipes only")
    H.eq(leather.recipes[1].id, 1001, "recipe ID")
    H.eq(leather.recipes[1].name, "Spell1001", "recipe name")
    H.eq(leather.recipes[1].itemId, 101001, "the item it makes")
end
local skinning = Find(a.professions, "id", 393)
H.check(skinning and type(skinning.recipes) == "table" and #skinning.recipes == 0, "a profession without recipes has an empty list")

local talents = a.talents
H.check(talents ~= NULL, "talents, from Guild Builds")
H.eq(talents.activeSpec, 1, "active spec")
H.eq(talents.specCount, 2, "two specs")
H.eq(talents.unspentPoints, 2, "unspent points")
H.eq(#talents.specs, 2, "both specs exported")
local spec = talents.specs[1]
H.eq(spec.active, true, "first spec active")
H.eq(spec.shared, true, "and shared")
H.eq(table.concat(spec._order, ","), "group,active,shared,summary,tabs,talents", "spec fields")
H.eq(talents.specs[2].active, false, "second spec not")
H.eq(spec.summary, "10/6/0", "points per tab")
H.eq(spec.tabs[2].name, "Marksmanship", "tab name")
H.eq(spec.tabs[2].pointsSpent, 6, "tab points")
H.eq(#spec.talents, 5, "learned talents")
local first = spec.talents[1]
H.eq(table.concat(first._order, ","), "tab,tabName,row,column,name,spellId,nodeId,rank,maxRank,posX,posY", "talent fields")
H.eq(first.name, "Spell40101", "talent name")
H.eq(first.tabName, "Beast Mastery", "talent tab")
H.check(first.row == 1 and first.column == 1, "talent row and column")
H.eq(first.rank, 5, "talent rank")
H.eq(first.maxRank, 5, "talent max rank")
H.eq(talents.specs[2].summary, "0/0/5", "second spec's points")
H.check(#carol.viewLoadouts >= 1 and carol.viewLoadouts[1].specID == 255, "a mage wrote a hunter's talents, through the view config")

local helm = Find(a.equipment, "slot", 1)
H.check(helm ~= nil, "head item exported")
if helm then
    H.eq(helm.slotName, "head", "slot name")
    H.eq(helm.itemId, 16939, "item ID")
    H.eq(helm.enchantId, 1503, "enchant")
    H.eq(helm.itemLevel, 76, "item level")
    H.eq(helm.name, "Item 16939", "item name (loaded ahead)")
    H.eq(helm.quality, 4, "item quality")
    H.eq(helm.itemString, "item:16939:1503:0:0:0:0:0::", "item string")
end
local bow = Find(a.equipment, "slot", 18)
H.check(bow and bow.slotName == "ranged" and bow.enchantId == NULL, "ranged slot, no enchant")

H.section("Export: a build not shared")
world:Login(carol)
world:RunFor(5)
alice.namespaces.GuildBuilds.Talents.SetShared(2, false)
world:RunUntil(function()
    local builds = CopyIn(carol, "GuildBuilds", alice)
    return builds and builds.s[2] and builds.s[2].x == nil
end, 180)
world:Logout(carol)
local unshared = Find(H.DecodeJSON(carol.saved.BottarSyncJSON).guilds[1].members, "name", "Alice Smith").talents.specs[2]
H.check(unshared.shared == false and unshared.summary == "0/0/5" and #unshared.talents == 0,
    "its points, and no talents")
alice.namespaces.GuildBuilds.Talents.SetShared(2, true)
Errors(world, "a build not shared")

H.section("Export: members without the addon")
local d = Find(guild.members, "name", "Dan Brown")
H.eq(d.hasAddon, false, "no addon")
H.eq(d.class.token, "PRIEST", "class from the roster")
H.eq(d.class.id, 5, "its ID")
H.eq(d.level, 42, "level from the roster")
H.eq(d.rank.name, "Initiate", "rank")
H.eq(d.note, "Ñoño 한국", "a note in UTF-8")
H.eq(d.online, false, "offline")
H.eq(d.lastOnline, guild.rosterUpdatedAt - (30 + 2) * 86400 - 5 * 3600, "about when last online, from the roster read")
for _, field in ipairs({ "realm", "race", "sex", "faction", "updatedAt", "addonVersion", "itemLevel", "professions", "talents", "equipment" }) do
    H.check(d[field] == NULL, "unknown " .. field .. " is null")
end
H.eq(table.concat(d._order, ","), table.concat(a._order, ","), "the same fields as members with the addon")

H.section("Export: members with the other addons only")
local frank = world:NewClient("Frank Green", {
    classID = 1,
    addons = { H.ADDONS[1], H.SOURCES[1], H.SOURCES[2] },
    talents = { active = 1, groups = { [1] = { [101] = 1 } } },
    professions = { { sl = 164, r = 120, m = 150, spell = 2018, hasRecipes = true } },
    gear = { [5] = { link = "|cff1eff00|Hitem:6000::::::::20|h[Chest]|h|r", il = 20 } },
    itemLevel = 20,
})
world:Login(frank)
world:RunFor(5)
world:OpenProfession(frank, 164, { 2001, 2002 }, { 2001 })
world:Login(carol)
world:RunUntil(function()
    local crafts = CopyIn(carol, "GuildProfessionsRecipes", frank)
    local builds = CopyIn(carol, "GuildBuilds", frank)
    return crafts and crafts.p and crafts.p[164] and type(crafts.p[164].k) == "table" and builds and builds.w
end, 300)
world:Logout(carol)
local f = Find(H.DecodeJSON(carol.saved.BottarSyncJSON).guilds[1].members, "name", "Frank Green")
H.eq(f.hasAddon, false, "without Bot'tar Sync")
H.check(f.professions ~= NULL and Find(f.professions, "id", 164) ~= nil, "their professions, from Guild Professions & Recipes")
H.check(f.equipment ~= NULL and Find(f.equipment, "slot", 5) ~= nil and f.itemLevel == 1.18,
    "their items and item level, from Guild Builds (the chest over 17)")
H.check(f.talents ~= NULL and f.talents.specs[1].shared == false, "their builds, not shared")
H.check(f.race == NULL and f.sex == NULL, "but not what only Bot'tar Sync shares")
world:Logout(frank)
Errors(world, "other addons only")

H.section("Export: without the other addons")
local gina = world:NewClient("Gina Black", { classID = 5, addons = { H.ADDONS[1], H.MAIN } })
world:Login(gina)
world:RunFor(150)
gina.env.SlashCmdList.BOTTARSYNC("status")
local said = table.concat(gina.printed, "\n")
local _, missing = said:gsub("is turned off or not installed: the file for the bot goes without its data", "")
H.eq(missing, 2, "the status says what is missing")
world:Logout(gina)
local g = Find(H.DecodeJSON(gina.saved.BottarSyncJSON).guilds[1].members, "name", "Alice Smith")
H.check(g ~= nil and g.hasAddon == true and g.class.id == 3, "the file still has the members")
H.check(g.professions == NULL and g.talents == NULL and g.equipment == NULL and g.itemLevel == NULL, "without the other addons' data")
Errors(world, "without the other addons")

H.section("Export: turned off")
world:Login(carol)
world:RunFor(5)
carol.env.SlashCmdList.BOTTARSYNC("export off")
world:Logout(carol)
H.eq(carol.saved.BottarSyncJSON, nil, "no JSON when the export is off")
world:Login(carol)
world:RunFor(5)
carol.env.SlashCmdList.BOTTARSYNC("export on")
carol.env.SlashCmdList.BOTTARSYNC("save")
H.check(carol.reloaded, "/bottar save reloads the interface")
world:Logout(carol)
H.eq(type(carol.saved.BottarSyncJSON), "string", "the JSON is back once turned on")
Errors(world, "export off and on")

H.section("Export: /bottar show")
world:Login(carol)
world:RunFor(70)
carol.env.SlashCmdList.BOTTARSYNC("show alice smith")
local window = carol.env.BottarSyncWindow
H.check(window ~= nil and window.Edit ~= nil, "a window opens")
if window then
    local shown = H.DecodeJSON(window.Edit._text)
    H.eq(shown.name, "Alice Smith", "with the member's JSON")
    H.check(window.Edit._text:find("\n  \"name\": \"Alice Smith\"", 1, true) ~= nil, "indented for reading")
end
carol.env.SlashCmdList.BOTTARSYNC("show Nobody Here")
H.check(carol.printed[#carol.printed]:find("no guild member called Nobody Here", 1, true) ~= nil, "an unknown name is reported")
Errors(world, "show")

H.section("Export: a large guild")
local ns = carol.ns
local bigGuild = ns.Data.GetGuild("Big Guild", true)
local bigCrafts = carol.namespaces.GuildProfessionsRecipes.Data.GetGuild("Big Guild", true)
local template = ns.Data.GetGuild("Test Guild").members[alice.guid]
bigGuild.roster = { t = ns.Now(), m = {} }
local recipes = {}
for i = 1, 300 do
    recipes[i] = 2000 + i * 3
end
for i = 1, 900 do
    local guid = ("Player-9-%08X"):format(i)
    bigGuild.roster.m[guid] = { n = "Member " .. i, c = "MAGE", l = 60, rk = "Member", ri = 3, nt = "note " .. i, on = false, lo = ns.Now() - i * 3600 }
    if i <= 60 then
        local record = H.DeepCopy(template)
        record.n = "Member " .. i
        bigGuild.members[guid] = record
        bigCrafts.members[guid] = {
            n = record.n, t = record.t, av = 1100,
            p = { [165] = { r = 300, m = 300, o = 1, k = recipes }, [171] = { r = 300, m = 300, o = 2, k = recipes } },
        }
    end
end
local started = os.clock()
local big = ns.Export.Build()
local elapsed = os.clock() - started
local bigData = H.DecodeJSON(big)
local bigExport = Find(bigData.guilds, "name", "Big Guild")
H.eq(bigExport.memberCount, 900, "900 members exported")
H.eq(bigExport.membersWithAddon, 60, "60 with the addon")
H.eq(#Find(bigExport.members, "name", "Member 7").professions[1].recipes, 300, "their recipes")
print(("   (%d KB of JSON in %.0f ms here)"):format(#big / 1024, elapsed * 1000))
H.check(elapsed < 5, "built in reasonable time")
ns.db.guilds["Big Guild"] = nil
carol.namespaces.GuildProfessionsRecipes.db.guilds["Big Guild"] = nil

H.section("Export: the bot's reader")
-- The saved variables file as the game writes it, read by Bot/bottarsync.js.
local OUT = H.ADDON .. "/Tests/out"
os.execute('mkdir "' .. OUT:gsub("/", "\\") .. '" 2>NUL')
local function ReadFile(path)
    local handle = io.open(path, "rb")
    if not handle then
        return nil
    end
    local text = handle:read("*a")
    handle:close()
    return text
end
local function WriteFile(path, text)
    local handle = assert(io.open(path, "wb"))
    handle:write(text)
    handle:close()
end
local function Run(command)
    local code = os.execute(command)
    return code == 0 or code == true
end
-- A packaged copy has no Bot folder (see .pkgmeta).
local hasReaders = ReadFile(H.ADDON .. "/Bot/bottarsync.js") ~= nil
local hasNode = hasReaders and Run("node --version >NUL 2>NUL")
local hasPython = hasReaders and Run('python -c "import json" >NUL 2>NUL')
if not hasReaders then
    print("   (no Bot folder here: the readers are not tested)")
elseif not hasNode then
    print("   (node not found: the reader is not tested)")
end
local readers = {}
if hasNode then
    readers[#readers + 1] = { name = "node", command = 'node "' .. H.ADDON .. '/Bot/bottarsync.js"' }
end
if hasPython then
    readers[#readers + 1] = { name = "python", command = 'python "' .. H.ADDON .. '/Bot/bottarsync.py"' }
elseif hasReaders then
    print("   (python not found: the Python reader is not tested)")
end

local savedFile = OUT .. "/BottarSync.lua"
local fixtures = {
    -- The game's own style, and Lua's %q.
    { "wow", function() H.WriteSavedVariables(savedFile, { { "BottarSyncDB", carol.saved.BottarSyncDB }, { "BottarSyncJSON", carol.saved.BottarSyncJSON } }, "wow") end, carol.saved.BottarSyncJSON },
    { "%q", function() H.WriteSavedVariables(savedFile, { { "BottarSyncDB", carol.saved.BottarSyncDB }, { "BottarSyncJSON", carol.saved.BottarSyncJSON } }, "q") end, carol.saved.BottarSyncJSON },
    -- Escapes the game might write: \ddd bytes, a backslash before a line break.
    { "\\ddd and \\newline", function()
        WriteFile(savedFile, '\nBottarSyncDB = {\n["schema"] = 1,\n}\nBottarSyncJSON = "{\\"a\\":\\"\\195\\177x\\\\\\\\y\\",\\\n\\"b\\":1}"\n')
    end, '{"a":"\195\177x\\\\y","b":1}' },
    { "long string", function()
        WriteFile(savedFile, '\r\nBottarSyncJSON = [==[\r\n{"a":"]]"}]==]\r\n')
    end, '{"a":"]]"}' },
}
for _, reader in ipairs(readers) do
    for _, fixture in ipairs(fixtures) do
        fixture[2]()
        -- The fixture must be valid Lua holding the expected text.
        local chunk = loadstring(ReadFile(savedFile))
        local env = {}
        setfenv(chunk, env)
        chunk()
        local expected = fixture[3]
        H.check(env.BottarSyncJSON ~= nil, fixture[1] .. ": the fixture is valid Lua")
        local outFile = OUT .. "/read.json"
        os.remove(outFile)
        local ran = Run(reader.command .. ' "' .. savedFile .. '" > "' .. outFile .. '"')
        H.check(ran, reader.name .. " reads the " .. fixture[1] .. " file")
        local output = (ReadFile(outFile) or ""):gsub("[\r\n]+$", "")
        local decodedOutput = output ~= "" and pcall(H.DecodeJSON, output)
        H.check(decodedOutput, reader.name .. " prints valid JSON (" .. fixture[1] .. ")")
        if fixture[1] == "wow" or fixture[1] == "%q" then
            -- JSON.stringify of the parsed data gives back the exact text.
            H.check(reader.name ~= "node" or output == expected, reader.name .. " gets the addon's JSON exactly (" .. fixture[1] .. ")")
        else
            local readable, value = pcall(H.DecodeJSON, output)
            local wanted = H.DecodeJSON(expected)
            H.check(readable and value.a == wanted.a and value.b == wanted.b, reader.name .. " undoes the escapes (" .. fixture[1] .. ")")
        end
    end
    WriteFile(savedFile, "\nBottarSyncDB = {\n}\n")
    H.check(not Run(reader.command .. ' "' .. savedFile .. '" >NUL 2>NUL'), reader.name .. ": a file without the JSON is reported")
end
Errors(world, "reader")
