local H = ...

local HUNTER_TALENTS = {
    active = 1,
    groups = {
        [1] = { [101] = 5, [102] = 3, [103] = 2, [201] = 5, [205] = 1 },
        [2] = { [301] = 5 },
    },
    unspent = 2,
}

-- A single client gives access to the addon's modules.
local world = H.NewWorld({ seed = 1 })
local solo = world:NewClient("Solo Name", {
    talents = H.DeepCopy(HUNTER_TALENTS),
    itemLevel = 52.375,
    gear = {
        [1] = { link = "|cffa335ee|Hitem:16939:1503:0:0:0:0:0:123456:60:0:0:0:0|h[Dragonstalker's Helm]|h|r", il = 76 },
        [18] = { link = "|cff1eff00|Hitem:15287:0:0:0:0:0:1197:654321:60:0:0:0:0|h[Crusader Bow of the Monkey]|h|r", il = 61 },
    },
    professions = { { sl = 165, r = 300, m = 300, spell = 10662, hasRecipes = true } },
})
world:Login(solo)
world:RunFor(30)
local ns = solo.ns
local Pack, Data, Json = ns.Pack, ns.Data, ns.Json
local now = ns.Now()

H.section("Loading")
H.eq(#world.errors, 0, "no errors while loading and starting")
for _, err in ipairs(world.errors) do
    print("   " .. err)
end

H.section("Pack: records")
local GUID = "Player-1-0000000A"
local record = {
    n = "Solo Name", rl = "TestRealm", t = now, av = 100,
    c = 3, r = 4, sx = 3, f = 1, l = 60, il = 5238,
    p = {
        [171] = { r = 150, m = 225, o = 1, lk = 2259, k = { 2330, 2331, 1306126 } },
        [182] = { r = 200, m = 225, o = 2, lk = 2366, k = false },
        [185] = { r = 10, m = 75, o = 5 },
    },
    g = { { s = 1, i = "item:16939:1503:0:0:0:0:0::::0:0", il = 76 }, { s = 18, i = "item:15287:0:0:0:0:0:-1197::::", il = 61 } },
    tl = {
        tr = 773, ag = 1, ng = 2, un = 2,
        s = {
            { gr = 1, tb = { { g = 11, n = "Beast Mastery", sp = 10 }, { g = 12, n = "Marksmanship", sp = 6 } },
              t = { { nd = 101, sp = 40101, r = 5, m = 5, tb = 1, rw = 1, cl = 1, x = 1200, y = -1500 } } },
            { gr = 2, tb = {}, t = {} },
        },
    },
}
local key, back = Pack.ReadRecord(Pack.Reader(Pack.RecordString(GUID, record)))
H.eq(key, GUID, "record key (the GUID)")
H.check(ns.Same(back, record), "record round trip, every field")
local noExtras = H.DeepCopy(record)
noExtras.g, noExtras.tl, noExtras.il, noExtras.rl = nil, nil, nil, nil
_, back = Pack.ReadRecord(Pack.Reader(Pack.RecordString(GUID, noExtras)))
H.check(back.g == nil and back.tl == nil and back.il == nil and back.rl == nil, "unknown items, talents, item level and realm stay unknown")
local _, zero = Pack.ReadRecord(Pack.Reader(Pack.RecordString(GUID, { t = now, p = {}, il = 0 })))
H.eq(zero.il, 0, "item level 0 is kept apart from unknown")

-- A later version's extra fields are skipped, and the next record still reads.
local body = Pack.RecordString(GUID, record)
local reader = Pack.Reader(body)
local length = reader:UInt()
local longer = Pack.Writer()
longer:Str(body:sub(reader.pos, reader.pos + length - 1) .. "\1\2\3")
longer:Raw(Pack.RecordString("Player-1-0000000B", noExtras))
reader = Pack.Reader(longer:Result())
key = Pack.ReadRecord(reader)
H.eq(key, GUID, "a record with fields from a later version reads")
H.eq((Pack.ReadRecord(reader)), "Player-1-0000000B", "the record after it reads too")
H.check(reader:AtEnd(), "batch fully read")
local huge = Pack.Writer()
huge:UInt(30000)
H.check(not pcall(Pack.ReadRecord, Pack.Reader(huge:Result() .. ("x"):rep(30000))), "oversized record refused")

H.section("Data: checking records")
H.check(Data.CleanRecord(record) ~= nil, "a good record passes")
local function Broken(change)
    local copy = H.DeepCopy(record)
    change(copy)
    return Data.CleanRecord(copy, now) == nil
end
H.check(Broken(function(r) r.t = now + 3600 end), "record from the future refused")
H.check(Broken(function(r) r.p = "x" end), "bad professions refused")
H.check(Broken(function(r) r.g[1].i = "|Hitem:1|h" end), "item string with escapes refused")
H.check(Broken(function(r) r.g[2].s = 1 end), "two items in one slot refused")
H.check(Broken(function(r) r.tl.s[1].t[1].r = -1 end), "bad talent rank refused")
H.check(Broken(function(r) r.tl.s[1].t[1].nd = "x" end), "bad talent node refused")
local copy = H.DeepCopy(record)
copy.n = "Evil|cffff0000Name"
copy.tl.s[1].tb[1].n = "Tab|r"
local clean = Data.CleanRecord(copy, now)
H.eq(clean.n, "Evilcffff0000Name", "escape sequences stripped from names")
H.eq(clean.tl.s[1].tb[1].n, "Tabr", "escape sequences stripped from tab names")

H.section("Data: merging")
local guild = { members = {} }
local function Rec(t, extra)
    local r = { t = t, p = { [171] = { r = 1, m = 75, o = 1 } } }
    for k, v in pairs(extra or {}) do
        r[k] = v
    end
    return r
end
Data.MergeRecord(guild, GUID, Rec(now - 100, { g = { { s = 1, i = "item:1", il = 1 } } }), false)
H.check(not Data.MergeRecord(guild, GUID, Rec(now - 200), false), "an older copy loses")
Data.MergeRecord(guild, GUID, Rec(now - 50), true)
H.eq(guild.members[GUID].t, now - 50, "a newer copy wins")
H.check(guild.members[GUID].g ~= nil, "it keeps the items the older copy knew")
guild.members[GUID].tl = nil
H.check(Data.MergeRecord(guild, GUID, Rec(now - 60, { tl = record.tl }), false), "an older copy can still give the talents")
H.check(guild.members[GUID].tl ~= nil and guild.members[GUID].t == now - 50, "talents taken, newer copy kept")

H.section("Data: saved form")
local db = ns.db
local savedGuild = Data.GetGuild("Test Guild", true)
savedGuild.members[GUID] = Data.CleanRecord(record)
Data.SetCatalog(171, { 2330, 2331, 2332 })
local packed = H.DeepCopy(db)
Data.PackForSave(packed)
H.eq(type(packed.guilds["Test Guild"].members[GUID].b), "string", "records are saved packed")
local loaded = Data.Sanitize(packed)
H.check(ns.Same(loaded.guilds["Test Guild"].members[GUID].tl, record.tl), "talents survive saving")
H.check(ns.Same(loaded.guilds["Test Guild"].members[GUID].g, record.g), "items survive saving")
H.check(H.SameList(loaded.cache.catalog[171], { 2330, 2331, 2332 }), "catalogs survive saving")
H.check(loaded.guilds["Test Guild"].roster ~= nil and next(loaded.guilds["Test Guild"].roster.m) ~= nil, "the roster survives saving")
local garbage = H.DeepCopy(packed)
garbage.guilds["Test Guild"].members[GUID] = { b = "!!!" }
garbage.guilds["Test Guild"].members["Player-1-0000000F"] = packed.guilds["Test Guild"].members[GUID]
loaded = Data.Sanitize(garbage)
H.check(loaded.guilds["Test Guild"].members[GUID] == nil, "an unreadable saved record is dropped")
H.check(loaded.guilds["Test Guild"].members["Player-1-0000000F"] == nil, "a record saved under another GUID is dropped")
H.check(next(Data.Sanitize("nonsense").guilds) == nil, "a broken database starts empty")

H.section("Json: values")
local E = Json.Encode
H.eq(E(Json.Object("b", 1, "a", 2)), '{"b":1,"a":2}', "keys keep their order")
H.eq(E(Json.Object("x", nil, "y", false)), '{"x":null,"y":false}', "nil is null, false stays")
H.eq(E(Json.Object()), "{}", "empty object")
H.eq(E(Json.Array({})), "[]", "empty array")
H.eq(E(Json.Array({ 1, "a", true })), '[1,"a",true]', "array")
H.eq(E(52.38), "52.38", "fraction")
H.eq(E(1760000000), "1760000000", "large integer written whole")
H.eq(E(0 / 0), "null", "NaN is null")
H.eq(E(math.huge), "null", "infinity is null")
H.eq(E('say "hi" \\ now'), '"say \\"hi\\" \\\\ now"', "quotes and backslashes escaped")
H.eq(E("a\nb\tc\1"), '"a\\nb\\tc\\u0001"', "control characters escaped")
local unicode = "Ñandú " .. Json.Char(0xD55C) .. " " .. Json.Char(0x1F600)
H.eq(E(unicode), '"' .. unicode .. '"', "valid UTF-8 kept as it is")
H.eq(E("a\255b"), '"a\239\191\189b"', "an invalid byte becomes U+FFFD")
H.eq(E("\195"), '"\239\191\189"', "a cut character becomes U+FFFD")
H.eq(E("\192\175"), '"\239\191\189\239\191\189"', "overlong forms are refused")
H.eq(E("\237\160\128"), '"\239\191\189\239\191\189\239\191\189"', "surrogates are refused")
H.check(not pcall(E, function() end), "functions cannot be written")
local nested = Json.Object("list", Json.Array({ Json.Object("k", "v", "n", Json.Array({ 1, 2 })) }), "e", Json.Array({}), "o", Json.Object())
for _, pretty in ipairs({ false, true }) do
    local decoded = H.DecodeJSON(E(nested, pretty))
    H.check(decoded.list[1].k == "v" and decoded.list[1].n[2] == 2 and #decoded.e == 0 and #decoded.o._order == 0,
        "nested values read back (" .. (pretty and "pretty" or "compact") .. ")")
end
H.check(E(nested, true):find("\n  \"list\": [\n    {", 1, true) ~= nil, "pretty output is indented")
H.eq(H.DecodeJSON(E(unicode)), unicode, "UTF-8 reads back")

H.section("Character: item strings")
local ItemString = ns.Character.ItemString
H.eq(ItemString("|cff1eff00|Hitem:15287:0:0:0:0:0:1197:1234567:60:0:0:0:0|h[Crusader Bow of the Monkey]|h|r"),
    "item:15287:0:0:0:0:0:1197::::0:0:0", "unique ID, level and spec left out")
H.eq(ItemString("|cffffffff|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r"), "item:19019:::::::::::::", "blank fields kept")
H.eq(ItemString("|cffffffff|Hitem:1234|h[Short]|h|r"), "item:1234", "a short item string")
local crafted = ItemString("|cff1eff00|Hitem:4314::::::::19:::::::::Player-4613-010B766A:|h[Double-Stitched Woolen Shoulders]|h|r")
H.eq(crafted, "item:4314:::::::::::::::::Player-4613-010B766A:", "a crafted item keeps its crafter's GUID")
H.eq(ItemString("|cffffffff|Hitem:1234:1.5:7|h[Odd]|h|r"), "item:1234::7", "a field with anything else is left blank")
H.eq(ItemString("|cffffffff|Hitem:abc:1|h[Odd]|h|r"), nil, "no item ID, no item")
H.eq(ItemString("|cffffffff|Hitem:1234:" .. ("1:"):rep(200) .. "|h[Long]|h|r"), "item:1234", "too long: only the item ID")
H.check(Data.CleanRecord({ t = now, p = {}, g = { { s = 3, i = crafted, il = 22 } } }, now) ~= nil, "other clients accept crafted items")
H.eq(ItemString("|cff71d5ff|Hspell:133|h[Fireball]|h|r"), nil, "not an item")
H.eq(ItemString(nil), nil, "no link")

H.section("Character: own record")
local own = Data.GetOwnRecord(false)
H.check(own ~= nil and Data.IsShareable(own), "own record stamped")
H.eq(own.l, 60, "level")
H.eq(own.c, 3, "class ID")
H.eq(own.r, 4, "race ID")
H.eq(own.sx, 3, "sex")
H.eq(own.f, 1, "faction")
H.eq(own.il, 5238, "item level in hundredths")
H.eq(own.rl, "TestRealm", "realm")
H.eq(#own.g, 2, "two items equipped")
H.eq(own.g[1].i, "item:16939:1503:0:0:0:0:0::::0:0:0", "head item string")
H.eq(own.g[2].s, 18, "ranged slot")
H.eq(own.g[2].il, 61, "item level of an item")
solo.gear[1] = nil
solo.level = 61
world:FireEvent(solo, "PLAYER_EQUIPMENT_CHANGED", 1, true)
world:FireEvent(solo, "PLAYER_LEVEL_UP", 62)
world:RunFor(3)
own = Data.GetOwnRecord(false)
H.eq(#own.g, 1, "an item taken off is gone")
H.eq(own.l, 62, "the level from PLAYER_LEVEL_UP, ahead of UnitLevel")

H.section("Talents")
local tl = own.tl
H.check(tl ~= nil, "talents read")
if tl then
    H.eq(tl.tr, 773, "tree ID")
    H.eq(tl.ag, 1, "active spec group")
    H.eq(tl.ng, 2, "two spec groups")
    H.eq(tl.un, 2, "unspent points")
    H.eq(#tl.s, 2, "both specs read")
    local spec = tl.s[1]
    H.eq(#spec.tb, 3, "three tabs")
    H.eq(spec.tb[1].n, "Beast Mastery", "first tab's name")
    H.eq(spec.tb[1].sp, 10, "points in the first tab")
    H.eq(spec.tb[2].sp, 6, "points in the second tab")
    H.eq(spec.tb[3].sp, 0, "points in the third tab")
    H.eq(#spec.t, 5, "only learned talents, and no hidden node")
    local expected = { [101] = { 1, 1, 1 }, [102] = { 1, 1, 2 }, [103] = { 1, 2, 1 }, [201] = { 2, 1, 2 }, [205] = { 2, 4, 4 } }
    for _, talent in ipairs(spec.t) do
        local want = expected[talent.nd]
        H.check(want and talent.tb == want[1] and talent.rw == want[2] and talent.cl == want[3],
            ("talent %d in tab %d, row %d, column %d"):format(talent.nd, talent.tb, talent.rw, talent.cl))
        H.eq(talent.sp, 40000 + talent.nd, "spell of talent " .. talent.nd)
    end
    H.eq(spec.t[1].nd, 101, "talents ordered by tab, row and column")
    H.eq(spec.t[5].nd, 205, "last talent")
    H.eq(spec.t[1].r, 5, "rank")
    H.eq(spec.t[2].m, 5, "max rank")
    H.eq(tl.s[2].gr, 2, "second spec's group")
    H.eq(#tl.s[2].t, 1, "second spec's talents")
    H.eq(tl.s[2].tb[3].sp, 5, "second spec's points")
end
local before = own.t
solo.talents.staged = true
solo.talents.groups[1][104] = 1
world:FireEvent(solo, "TRAIT_CONFIG_UPDATED", 501)
world:RunFor(3)
H.eq(Data.GetOwnRecord(false).t, before, "talents not applied yet are not shared")
solo.talents.staged = false
world:FireEvent(solo, "TRAIT_CONFIG_UPDATED", 501)
world:RunFor(3)
H.eq(#Data.GetOwnRecord(false).tl.s[1].t, 6, "applied talents are")
solo.talents.active = 2
world:FireEvent(solo, "ACTIVE_TALENT_GROUP_CHANGED", 2, 1)
world:RunFor(3)
H.eq(Data.GetOwnRecord(false).tl.ag, 2, "switching specs is noticed")

-- A character without talents yet (no config) leaves them unknown.
local fresh = world:NewClient("Fresh Face", { level = 5 })
world:Login(fresh)
world:RunFor(5)
local freshRecord = fresh.ns.Data.GetOwnRecord(false)
H.check(freshRecord ~= nil and freshRecord.tl == nil, "no talent config: talents unknown")
H.eq(fresh.ns.Talents.lastError, "no talent config yet", "and the reason is noted")

H.section("Locales")
local function ReadKeys(path)
    local keys = {}
    for _, file in ipairs(path) do
        local handle = io.open(H.ADDON .. "/" .. file, "rb")
        local text = handle:read("*a")
        handle:close()
        for k in text:gmatch('L%["(.-)"%]') do
            keys[k] = true
        end
    end
    return keys
end
local codeFiles = {}
for _, file in ipairs(H.FILES) do
    if not file:find("^Locales/") then
        codeFiles[#codeFiles + 1] = file
    end
end
local codeKeys = ReadKeys(codeFiles)
local function Specifiers(text)
    local list = {}
    for spec in text:gmatch("%%[%d%.]*[sdf]") do
        list[#list + 1] = spec
    end
    return table.concat(list, " ")
end
for _, locale in ipairs({ "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
    local texts = {}
    local env = setmetatable({}, { __index = _G })
    local chunk = assert(loadfile(H.ADDON .. "/Locales/" .. locale .. ".lua"))
    setfenv(chunk, env)
    chunk("BottarSync", { RegisterLocale = function(_, fill) fill(texts) end })
    local missing, extra, badSpecs = {}, {}, {}
    for k in pairs(codeKeys) do
        if texts[k] == nil and locale ~= "esMX" then
            missing[#missing + 1] = k
        end
    end
    for k, v in pairs(texts) do
        if not codeKeys[k] then
            extra[#extra + 1] = k
        elseif Specifiers(k) ~= Specifiers(v) then
            badSpecs[#badSpecs + 1] = k
        end
    end
    H.check(#missing == 0, locale .. " has every text" .. (#missing > 0 and (": missing " .. table.concat(missing, " | ")) or ""))
    H.check(#extra == 0, locale .. " has no unused text" .. (#extra > 0 and (": " .. table.concat(extra, " | ")) or ""))
    H.check(#badSpecs == 0, locale .. " keeps the format specifiers" .. (#badSpecs > 0 and (": " .. table.concat(badSpecs, " | ")) or ""))
end

H.section("Release files")
local function Read(path)
    local handle = io.open(H.ADDON .. "/" .. path, "rb")
    if not handle then
        return nil
    end
    local text = handle:read("*a")
    handle:close()
    return text
end
local toc = Read("BottarSync.toc")
local changelog = Read("CHANGELOG.md")
local tocVersion = toc:match("## Version: ([%d%.]+)")
H.check(changelog ~= nil and changelog:match("## ([%d%.]+)") == tocVersion, "the TOC version is the changelog's newest")
local pkgmeta = Read(".pkgmeta")
H.check(pkgmeta ~= nil and pkgmeta:find("package%-as: BottarSync") ~= nil, ".pkgmeta packages the folder as BottarSync")
H.check(pkgmeta ~= nil and pkgmeta:find("\n    %- Tests\n") ~= nil and pkgmeta:find("\n    %- Bot\n") ~= nil,
    ".pkgmeta leaves the tests and the bot's readers out of the package")
H.check(toc:find("## SavedVariables: BottarSyncDB, BottarSyncJSON", 1, true) ~= nil, "both saved variables are declared")
H.check(toc:find("## Dependencies: LibGuildSync", 1, true) ~= nil, "LibGuildSync is a dependency")
