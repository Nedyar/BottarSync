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
    gear = { [1] = { link = "|cffa335ee|Hitem:16939:1503:0:0:0:0:0:123456:60:0:0:0:0|h[Dragonstalker's Helm]|h|r", il = 76 } },
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
H.check(ns.Sources.Has("GuildProfessionsRecipes") and ns.Sources.Has("GuildBuilds"), "the other addons' data can be read")
H.eq(ns.Sources.Title("GuildBuilds"), "Guild Builds", "with their titles")
H.check(not ns.Sources.Has("NoSuchAddon") and next(ns.Sources.Records("NoSuchAddon", "Test Guild")) == nil,
    "an addon that is missing gives nothing")

H.section("Pack: records")
local GUID = "Player-1-0000000A"
local record = { n = "Solo Name", rl = "TestRealm", t = now, av = 400, c = 3, r = 4, sx = 3, f = 1, l = 60 }
local key, back = Pack.ReadRecord(Pack.Reader(Pack.RecordString(GUID, record)))
H.eq(key, GUID, "record key (the GUID)")
H.check(back.p ~= nil and next(back.p) == nil and back.g == nil and back.tl == nil and back.il == nil,
    "no professions, items, talents or item level any more (written empty, for older versions)")
back.p = nil
H.check(ns.Same(back, record), "record round trip, every field")
H.check(back.ak == nil and back.dc == nil and back.pt == nil and back.ch == nil, "no profile while the account has none")
-- With the account's profile (0.5).
local profiled = H.DeepCopy(record)
profiled.ak, profiled.dc, profiled.pt = "AbCdEf123456", "solo.name", now - 5
profiled.ch = { [GUID] = true, ["Player-1-0000000B"] = false }
key, back = Pack.ReadRecord(Pack.Reader(Pack.RecordString(GUID, profiled)))
back.p = nil
H.check(ns.Same(back, profiled), "record round trip with the profile: key, Discord name, time, mains and alts")
-- A record cut where an older version's ends: of 0.4 or before after the
-- talents (an empty profile is 4 bytes, and nothing set by officers 4: two
-- empty lists, and the guild's link, empty and undated), of 0.5 to 0.7
-- after the profile, of 0.8 before the guild's link.
local function Cut(guid, rec, bytes)
    local body0 = Pack.RecordString(guid, rec)
    local reader0 = Pack.Reader(body0)
    local length0 = reader0:UInt()
    local short = Pack.Writer()
    short:Str(body0:sub(reader0.pos, reader0.pos + length0 - 1 - bytes))
    return Pack.ReadRecord(Pack.Reader(short:Result()))
end
key, back = Cut(GUID, record, 4 + 4)
H.check(key == GUID and back.l == 60 and back.ak == nil and back.ch == nil, "a record from before 0.5 reads, without a profile")
key, back = Cut(GUID, profiled, 4)
H.check(key == GUID and back.dc == "solo.name" and back.ch[GUID] == true and back.ov == nil,
    "a record of 0.5 to 0.7 reads, with its profile and nothing set by officers")
-- With what the officers set (0.8).
local officered = H.DeepCopy(profiled)
officered.ov = {
    r = { ["old.name"] = { n = "new.name", t = now - 3 }, ["kept"] = { n = "kept", t = now - 2 } },
    a = { ["Player-1-0000000B"] = { d = "new.name", m = true, t = now - 1 },
        ["Player-1-0000000C"] = { d = false, m = false, t = now } },
}
key, back = Pack.ReadRecord(Pack.Reader(Pack.RecordString(GUID, officered)))
back.p = nil
H.check(ns.Same(back, officered), "record round trip with what the officers set: renames, and whose each character is")
key, back = Cut(GUID, officered, 2)
back.p = nil
H.check(ns.Same(back, officered), "a record of 0.8 reads, with what the officers set and no guild link")
-- With the guild's Discord link (0.9), and once taken away.
local linked = H.DeepCopy(officered)
linked.ov.g = { v = "https://discord.gg/abc123", t = now - 5 }
key, back = Pack.ReadRecord(Pack.Reader(Pack.RecordString(GUID, linked)))
back.p = nil
H.check(ns.Same(back, linked), "record round trip with the guild's Discord link")
local unlinked = H.DeepCopy(profiled)
unlinked.ov = { r = {}, a = {}, g = { v = "", t = now } }
key, back = Pack.ReadRecord(Pack.Reader(Pack.RecordString(GUID, unlinked)))
back.p = nil
H.check(ns.Same(back, unlinked), "and with the link taken away, which still counts")
local long = H.DeepCopy(profiled)
long.ov = { r = {}, a = {}, g = { v = ("x"):rep(Pack.LIMITS.link + 1), t = now } }
H.check(not pcall(Pack.ReadRecord, Pack.Reader(Pack.RecordString(GUID, long))), "a link too long is refused")
key, back = Pack.ReadRecord(Pack.Reader(Pack.RecordString(GUID, profiled)))
H.eq(back.ov, nil, "a record that sets nothing reads without it")
local crowded = H.DeepCopy(officered)
for i = 1, Pack.LIMITS.assignments + 1 do
    crowded.ov.a[("Player-1-%08X"):format(5000 + i)] = { d = "x.y", m = false, t = now }
end
H.check(not pcall(Pack.ReadRecord, Pack.Reader(Pack.RecordString(GUID, crowded))), "one that sets too many characters is refused")
local crowd = H.DeepCopy(profiled)
for i = 1, 61 do
    crowd.ch[("Player-1-%08X"):format(1000 + i)] = false
end
H.check(not pcall(Pack.ReadRecord, Pack.Reader(Pack.RecordString(GUID, crowd))), "a profile with too many characters is refused")
-- A record from a version before 0.4, with what other addons share now.
local legacy = {
    n = "Old Name", t = now, av = 301, c = 3, r = 4, sx = 3, f = 1, l = 60, il = 5238,
    p = { [171] = { r = 150, m = 225, o = 1, lk = 2259, k = { 2330, 2331 } }, [182] = { r = 200, m = 225, o = 2, k = false } },
    g = { { s = 1, i = "item:16939:1503", il = 76 } },
    tl = { tr = 773, ag = 1, ng = 1, un = 0, s = { { gr = 1, tb = { { g = 11, n = "Beast Mastery", sp = 5 } },
        t = { { nd = 101, sp = 40101, r = 5, m = 5, tb = 1, rw = 1, cl = 1, x = 1200, y = 1500 } } } } },
}
key, back = Pack.ReadRecord(Pack.Reader(Pack.RecordString(GUID, legacy)))
H.check(back.p[171] ~= nil and back.tl ~= nil, "a record from before 0.4 still reads")
local clean = Data.CleanRecord(back, now)
H.check(clean ~= nil and clean.c == 3 and clean.l == 60, "and passes, as a character")
H.check(clean.p == nil and clean.g == nil and clean.tl == nil and clean.il == nil, "without what other addons share now")

-- A later version's extra fields are skipped, and the next record still reads.
local body = Pack.RecordString(GUID, record)
local reader = Pack.Reader(body)
local length = reader:UInt()
local longer = Pack.Writer()
longer:Str(body:sub(reader.pos, reader.pos + length - 1) .. "\1\2\3")
longer:Raw(Pack.RecordString("Player-1-0000000B", record))
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
H.eq(Data.CleanRecord({ t = now + 3600 }, now), nil, "a record from the future is refused")
local copy = H.DeepCopy(record)
copy.n = "Evil|cffff0000Name"
H.eq(Data.CleanRecord(copy, now).n, "Evilcffff0000Name", "escape sequences stripped from names")
copy.c, copy.l = "x", -1
clean = Data.CleanRecord(copy, now)
H.check(clean.c == 0 and clean.l == 0, "odd numbers become unknown")
H.check(H.SameList({ Data.Stats(clean) }, { 0, 0, 0 }) and Data.STATS == 3,
    "three stats, as versions before 0.4 send, all 0")
clean = Data.CleanRecord(profiled, now)
H.check(clean.ak == "AbCdEf123456" and clean.dc == "solo.name" and clean.pt == now - 5 and clean.ch[GUID] == true,
    "a record's profile passes")
local function ProfileOf(change)
    local bad = H.DeepCopy(profiled)
    change(bad)
    local result = Data.CleanRecord(bad, now)
    return result.ak or result.dc or result.pt or result.ch
end
H.eq(ProfileOf(function(bad) bad.dc = "Not A Name" end), nil, "a profile with a Discord name Discord could not have is dropped whole")
H.eq(ProfileOf(function(bad) bad.ak = "short" end), nil, "and one with an odd account key")
H.eq(ProfileOf(function(bad) bad.pt = now + 3600 end), nil, "and one dated in the future")
H.eq(ProfileOf(function(bad) bad.ch = "x" end), nil, "and one without its characters")
clean = Data.CleanRecord((function()
    local odd = H.DeepCopy(profiled)
    odd.ch["not a GUID"] = true
    odd.ch["Player-1-0000000C"] = "yes"
    return odd
end)(), now)
H.check(clean.ch["not a GUID"] == nil and clean.ch["Player-1-0000000C"] == nil and clean.ch[GUID] == true,
    "characters that are not GUIDs with true or false are left out")
clean = Data.CleanRecord(officered, now)
H.check(ns.Same(clean.ov, officered.ov), "what the officers set passes")
clean = Data.CleanRecord((function()
    local odd = H.DeepCopy(officered)
    odd.ov.r["Not A Name"] = { n = "fine", t = now }
    odd.ov.r["fine.too"] = { n = "Bad Name", t = now }
    odd.ov.a["not a GUID"] = { d = "x.y", m = true, t = now }
    odd.ov.a["Player-1-0000000D"] = { d = "x.y", m = true, t = now + 3600 }
    odd.ov.a["Player-1-0000000E"] = { d = "Bad Name", m = true, t = now }
    odd.ov.a["Player-1-0000000C"].m = true
    return odd
end)(), now)
H.check(clean.ov.r["Not A Name"] == nil and clean.ov.r["fine.too"] == nil and clean.ov.r["old.name"].n == "new.name",
    "renames from or to a name Discord could not have are left out")
H.check(clean.ov.a["not a GUID"] == nil and clean.ov.a["Player-1-0000000D"] == nil and clean.ov.a["Player-1-0000000E"] == nil
    and clean.ov.a["Player-1-0000000B"].d == "new.name", "and characters that are not GUIDs, set in the future or to such a name")
H.check(clean.ov.a["Player-1-0000000C"].d == false and clean.ov.a["Player-1-0000000C"].m == false, "nobody's is nobody's main")
H.eq(Data.CleanRecord(record, now).ov, nil, "a record that sets nothing has none")

H.section("Profile: Discord names")
local Profile = ns.Profile
for _, case in ipairs({
    { "solo.name", "solo.name" }, { "  Solo_Name99 ", "solo_name99" }, { "@nedyar", "nedyar" },
    { "a", nil }, { ("x"):rep(33), nil }, { ("x"):rep(32), ("x"):rep(32) }, { "two words", nil },
    { "dots..twice", nil }, { "ñandú", nil }, { "name#1234", nil }, { "", nil }, { 42, nil },
}) do
    H.eq(Profile.CleanDiscord(case[1]), case[2], "Discord name " .. tostring(case[1]))
end
H.check(Profile.CleanKey(Profile.NewKey()) ~= nil and Profile.NewKey() ~= Profile.NewKey(), "new account keys are good and differ")

H.section("Profile: who plays each character")
local A1, A2, A3 = "Player-1-000000A1", "Player-1-000000A2", "Player-1-000000A3"
local B1, C1, D1 = "Player-1-000000B1", "Player-1-000000C1", "Player-1-000000D1"
local function Rec(ak, dc, pt, ch)
    return { ak = ak, dc = dc, pt = pt, ch = ch }
end
-- Account A: A1 made the profile (A1 main), A2 later changed it (A2 main
-- too, the name renamed, and A3 added, an alt); A3 never logged in since
-- the profile began. Account B, the same player on another WoW account; C
-- another player, who added A1 (theirs already) and E1 (no one's yet; so
-- did the player, earlier); D someone without a profile; F1 a character
-- without a record that C added.
local E1, F1 = "Player-1-000000E1", "Player-1-000000F1"
local who = Profile.Resolve({
    [A1] = Rec("KeyAAAAAAAAA", "first", 100, { [A1] = true }),
    [A2] = Rec("KeyAAAAAAAAA", "player", 200, { [A1] = true, [A2] = true, [A3] = false, [E1] = true }),
    [A3] = {},
    [B1] = Rec("KeyBBBBBBBBB", "player", 150, { [B1] = true }),
    [C1] = Rec("KeyCCCCCCCCC", "other", 300, { [C1] = false, [A1] = false, [E1] = false, [F1] = true }),
    [D1] = {},
    [E1] = {},
})
H.check(who[A1].dc == "player" and who[A2].dc == "player", "an account's characters take its newest profile's Discord name")
H.check(who[A1].main and who[A2].main, "mains, from the newest profile of the player that speaks of them")
H.check(who[B1].dc == "player" and who[B1].main, "another account of the same player keeps what it says of its own")
H.check(who[C1].dc == "other" and not who[C1].main and not who[C1].pending, "another player's alt")
H.check(who[A1].main and not who[A1].pending, "and another player's list cannot make someone else's main theirs, nor an alt")
H.check(who[A3] and who[A3].dc == "player" and who[A3].main == false and who[A3].pending,
    "a character with no profile that a player added counts as theirs, pending")
H.check(who[E1] and who[E1].dc == "other" and who[E1].main == false and who[E1].pending, "added by two players: the newest list wins")
H.check(who[F1] and who[F1].dc == "other" and who[F1].main and who[F1].pending, "also one without a record")
H.eq(who[D1], nil, "no profile and added by no one: no Discord name")
who = Profile.Resolve({
    [A1] = Rec("KeyAAAAAAAAA", "player", 100, { [A1] = true }),
    [B1] = Rec("KeyBBBBBBBBB", "player", 150, { [B1] = true, [A1] = false }),
})
H.check(not who[A1].main and who[B1].main, "the player's newest profile wins, from any of their accounts")
-- What the officers set: "first" renamed to "player" (account B's name),
-- A2 set to C's player as a main, B1 to nobody, D1 (no record) to the
-- renamed player as an alt, and E1, which C added, to C as a main.
who = Profile.Resolve({
    [A1] = Rec("KeyAAAAAAAAA", "first", 100, { [A1] = true, [A2] = false }),
    [A2] = Rec("KeyAAAAAAAAA", "first", 100, { [A1] = true, [A2] = false }),
    [B1] = Rec("KeyBBBBBBBBB", "player", 150, { [B1] = true, [A1] = false }),
    [C1] = Rec("KeyCCCCCCCCC", "other", 300, { [C1] = false, [E1] = false }),
}, {
    r = { first = { n = "player", t = 400 } },
    a = { [A2] = { d = "other", m = true, t = 400 }, [B1] = { d = false, m = false, t = 400 },
        [D1] = { d = "player", m = false, t = 400 }, [E1] = { d = "other", m = true, t = 400 } },
})
H.check(who[A1].dc == "player" and not who[A1].set, "a renamed player's characters go by the new name")
H.check(not who[A1].main, "and count as one player with the other account that has it: its newest list decides")
H.check(who[A2].dc == "other" and who[A2].main and who[A2].set and not who[A2].pending, "a character set to another player is theirs")
H.eq(who[B1], nil, "one set to nobody is nobody's, although its own profile says otherwise")
H.check(who[D1] and who[D1].dc == "player" and who[D1].main == false and not who[D1].pending, "one without a record, set to a player")
H.check(who[E1].main and not who[E1].pending, "one a player added and an officer set: not pending, as the officer says")

H.section("Data: saved form")
local db = ns.db
local savedGuild = Data.GetGuild("Test Guild", true)
savedGuild.members[GUID] = Data.CleanRecord(record)
local packed = H.DeepCopy(db)
packed.cache = { catalog = { [171] = "AAAA" } }
for _, state in pairs(packed.own) do
    state.hinted = { [171] = true }
end
Data.PackForSave(packed)
H.eq(type(packed.guilds["Test Guild"].members[GUID].b), "string", "records are saved packed")
local loaded = Data.Sanitize(packed)
H.eq(loaded.guilds["Test Guild"].members[GUID].c, 3, "and come back")
H.check(loaded.guilds["Test Guild"].roster ~= nil and next(loaded.guilds["Test Guild"].roster.m) ~= nil, "the roster survives saving")
H.eq(loaded.cache, nil, "the catalogs of versions before 0.4 are dropped")
local hinted = false
for _, state in pairs(loaded.own) do
    hinted = hinted or state.hinted ~= nil
end
H.check(not hinted, "and so are their profession hints")
local garbage = H.DeepCopy(packed)
garbage.guilds["Test Guild"].members[GUID] = { b = "!!!" }
garbage.guilds["Test Guild"].members["Player-1-0000000F"] = packed.guilds["Test Guild"].members[GUID]
loaded = Data.Sanitize(garbage)
H.check(loaded.guilds["Test Guild"].members[GUID] == nil, "an unreadable saved record is dropped")
H.check(loaded.guilds["Test Guild"].members["Player-1-0000000F"] == nil, "a record saved under another GUID is dropped")
H.check(next(Data.Sanitize("nonsense").guilds) == nil, "a broken database starts empty")
H.check(next(Data.Sanitize("nonsense").account.ch) == nil, "with an empty profile")
local withAccount = H.DeepCopy(packed)
withAccount.account = { key = "AbCdEf123456", dc = "solo.name", pt = now, ch = { [GUID] = true, bad = 1 } }
loaded = Data.Sanitize(withAccount)
H.check(loaded.account.key == "AbCdEf123456" and loaded.account.dc == "solo.name" and loaded.account.ch[GUID] == true
    and loaded.account.ch.bad == nil, "the account's profile is saved and checked")
withAccount.account.dc = "Not Valid"
H.check(Data.Sanitize(withAccount).account.key == nil, "a broken profile is dropped")
savedGuild.members[GUID] = nil

H.section("Data: professions of Guild Professions & Recipes")
local sorted = Data.SortedProfessions({
    [185] = { r = 10, m = 75, o = 5 }, [171] = { r = 150, m = 225, o = 1, lk = 2259, k = { 2330 } },
    [182] = { r = 200, m = 225, o = 2, k = false }, [999] = "odd", [0] = { r = 1, m = 1 },
})
H.eq(#sorted, 3, "only what is usable")
H.check(sorted[1].sl == 171 and sorted[2].sl == 182 and sorted[3].sl == 185, "in the character sheet's order")
H.check(type(sorted[1].k) == "table" and sorted[2].k == false and sorted[3].k == nil, "recipes, none, or not read yet")
H.eq(#Data.SortedProfessions(nil), 0, "nothing without professions")


H.section("Character: own record")
local own = Data.GetOwnRecord(false)
H.check(own ~= nil and Data.IsShareable(own), "own record stamped")
H.eq(own.l, 60, "level")
H.eq(own.c, 3, "class ID")
H.eq(own.r, 4, "race ID")
H.eq(own.sx, 3, "sex")
H.eq(own.f, 1, "faction")
H.eq(own.rl, "TestRealm", "realm")
H.check(own.p == nil and own.g == nil and own.tl == nil and own.il == nil,
    "nothing that other addons share: professions, items, talents, item level")
solo.level = 61
world:FireEvent(solo, "PLAYER_LEVEL_UP", 62)
world:RunFor(3)
H.eq(Data.GetOwnRecord(false).l, 62, "the level from PLAYER_LEVEL_UP, ahead of UnitLevel")

-- A character whose saved record came from a version before 0.4.
local old = world:NewClient("Old Timer", { talents = H.DeepCopy(HUNTER_TALENTS) })
local oldRecord = H.DeepCopy(legacy)
oldRecord.n, oldRecord.t, oldRecord.av = "Old Timer", now - 1000, 205
old.saved = { BottarSyncDB = { schema = 1, guilds = { ["Test Guild"] = { seen = now, members = {
    [old.guid] = { b = Pack.ToBase64(Pack.RecordString(old.guid, oldRecord)), fh = true },
} } } } }
world:Login(old)
world:RunFor(10)
local renewed = old.ns.Data.GetOwnRecord(false)
H.check(renewed ~= nil and renewed.p == nil and renewed.tl == nil and renewed.g == nil, "its old fields are gone")
H.check(renewed.t > now - 1000 and renewed.av == old.ns.VERSION_NUM, "and it is shared again, with this version")
H.eq(#world.errors, 0, "no errors")

H.section("TalentTree: build strings")
local Tree = ns.TalentTree
local text = H.EncodeBuild(255, { [101] = 5, [102] = 3, [303] = 1 })
local build = Tree.Decode(text, 14)
H.check(build ~= nil, "a build string reads")
H.check(build.version == H.LOADOUT_VERSION and build.specID == 255, "its header: version and spec")
H.check(H.SameList(build.hash, H.TreeHash(H.TREE)), "and the tree's hash")
H.check(build.nodes[1].selected and not build.nodes[1].granted and build.nodes[1].ranks == nil, "a talent with all its ranks")
H.check(build.nodes[2].selected and build.nodes[2].ranks == 3, "a talent with some")
H.check(not build.nodes[3].selected, "a talent not learned")
H.check(build.nodes[13].selected and build.nodes[13].ranks == 1, "the last talent of the tree")
H.check(not build.nodes[14].selected, "and a hidden node")
build = Tree.Decode(H.EncodeBuild(255, { [102] = 2 }, { granted = { [101] = true }, choices = { [102] = 3 } }), 14)
H.check(build.nodes[1].selected and build.nodes[1].granted, "a granted node")
H.check(build.nodes[2].choice == 3 and build.nodes[2].ranks == 2, "a choice node, with the entry chosen")
H.eq(Tree.Decode(text, 40), nil, "a string too short for the tree")
H.eq(Tree.Decode("ab!d" .. text, 14), nil, "anything that is not Base64")
H.eq(Tree.Decode("AAAA", 1), nil, "no room for the header")

H.section("TalentTree: our own class's builds")
local builds = solo.namespaces.GuildBuilds
builds.Talents.SetShared(1, true)
builds.Talents.SetShared(2, true)
world:RunFor(3)
local Records = ns.Sources.Records
local mine = Records("GuildBuilds", "Test Guild")[solo.guid]
H.check(mine ~= nil and mine.s[1].x ~= nil, "Guild Builds shares the builds")
local talents = Tree.Talents(mine)
H.check(talents ~= nil, "read from its record")
H.check(talents.tr == 773 and talents.ag == 1 and talents.ng == 2 and talents.un == 2, "tree, active spec, specs and unspent points")
local spec = talents.s[1]
H.check(spec.shared and #spec.tb == 3, "a shared build with its three tabs")
H.check(spec.tb[1].n == "Beast Mastery" and spec.tb[1].sp == 10 and spec.tb[2].sp == 6 and spec.tb[3].sp == 0, "names and points")
H.eq(#spec.t, 5, "only learned talents, and no hidden node")
local expected = { [101] = { 1, 1, 1 }, [102] = { 1, 1, 2 }, [103] = { 1, 2, 1 }, [201] = { 2, 1, 2 }, [205] = { 2, 4, 4 } }
for _, talent in ipairs(spec.t) do
    local want = expected[talent.nd]
    H.check(want and talent.tb == want[1] and talent.rw == want[2] and talent.cl == want[3],
        ("talent %d in tab %d, row %d, column %d"):format(talent.nd, talent.tb, talent.rw, talent.cl))
    H.eq(talent.sp, 40000 + talent.nd, "spell of talent " .. talent.nd)
end
H.check(spec.t[1].nd == 101 and spec.t[5].nd == 205, "by tab, row and column")
H.check(spec.t[1].r == 5 and spec.t[2].r == 3 and spec.t[2].m == 5, "ranks and max ranks")
H.check(talents.s[2].gr == 2 and #talents.s[2].t == 1 and talents.s[2].tb[3].sp == 5, "the second spec")
H.eq(#solo.viewLoadouts, 0, "our own class's tree needs no view config")
builds.Talents.SetShared(2, false)
world:RunFor(3)
talents = Tree.Talents(Records("GuildBuilds", "Test Guild")[solo.guid])
H.check(not talents.s[2].shared and #talents.s[2].t == 0 and talents.s[2].tb[3].sp == 5, "a build not shared: points, no talents")

H.section("TalentTree: another class's builds")
local mage = world:NewClient("Mage Name", { classID = 8, talents = { active = 1, groups = { [1] = { [1101] = 5, [1103] = 2, [1302] = 3 } } } })
world:Login(mage)
world:RunFor(5)
mage.namespaces.GuildBuilds.Talents.SetShared(1, true)
world:RunUntil(function()
    local copy = Records("GuildBuilds", "Test Guild")[mage.guid]
    return copy ~= nil and copy.s ~= nil and copy.s[1].x ~= nil
end, 180)
local mageTalents = Tree.Talents(Records("GuildBuilds", "Test Guild")[mage.guid])
H.check(mageTalents ~= nil and mageTalents.tr == 774, "a mage's build, read by a hunter")
spec = mageTalents and mageTalents.s[1]
H.check(spec and spec.tb[1].n == "Arcane" and spec.tb[3].n == "Frost", "with the mage's tab names")
H.check(spec and #spec.t == 3 and spec.t[1].nd == 1101 and spec.t[2].nd == 1103 and spec.t[3].nd == 1302, "and talents")
H.check(spec and spec.t[2].rw == 2 and spec.t[2].cl == 2 and spec.t[3].tb == 3 and spec.t[3].cl == 3, "rows and columns")
H.check(#solo.viewLoadouts == 1 and solo.viewLoadouts[1].specID == 62, "through the view config, set up for the mage's spec")
Tree.Talents(Records("GuildBuilds", "Test Guild")[mage.guid])
H.eq(#solo.viewLoadouts, 1, "once a session")
H.eq(#world.errors, 0, "no errors")

H.section("TalentTree: builds this client cannot read")
local MAGE_TABS = { { g = 21, i = 1 }, { g = 22, i = 2 }, { g = 23, i = 3 } }
local function MageRecord(x)
    return { t = now, tr = 774, ag = 1, lv = 60, tb = MAGE_TABS, s = { { gr = 1, x = x, p = { 5, 0, 3 } } } }
end
local readable = MageRecord(H.EncodeBuild(62, { [1101] = 5 }))
H.eq(#Tree.Talents(readable).s[1].t, 1, "a mage's build reads")
local other = Tree.Talents(MageRecord(H.EncodeBuild(62, { [1101] = 5 }, { version = 9 })))
H.check(other.s[1].shared and #other.s[1].t == 0 and other.s[1].tb[1].sp == 5,
    "made by another version of the game: shared, with points, without talents")
local hash = H.TreeHash(H.MAGE_TREE)
hash[3] = (hash[3] + 1) % 256
other = Tree.Talents(MageRecord(H.EncodeBuild(62, { [1101] = 5 }, { hash = hash })))
H.eq(#other.s[1].t, 0, "made from a tree that has changed since")
local empty = {}
for i = 1, 16 do
    empty[i] = 0
end
H.eq(#Tree.Talents(MageRecord(H.EncodeBuild(62, { [1101] = 5 }, { hash = empty }))).s[1].t, 1,
    "an empty hash is not checked (other sites make strings so)")
H.eq(#Tree.Talents(MageRecord("!!!")).s[1].t, 0, "a broken string")
H.eq(Tree.Talents({ t = now }), nil, "no builds, no talents")

-- Another client, with the talent window open.
local viewer = world:NewClient("Viewer Name", { talents = H.DeepCopy(HUNTER_TALENTS) })
world:Login(viewer)
world:RunFor(5)
viewer.env.PlayerSpellsFrame = { IsShown = function()
    return true
end }
local ViewerTree = viewer.ns.TalentTree
H.eq(#ViewerTree.Talents(readable).s[1].t, 0, "while the talent window is open, another class's tree is not read")
H.eq(#viewer.viewLoadouts, 0, "so the window is left as it is")
ViewerTree.loggingOut = true
H.eq(#ViewerTree.Talents(readable).s[1].t, 1, "at logout it is")
ViewerTree.loggingOut = false
H.eq(#world.errors, 0, "no errors")

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
-- A guild member installs Bot'tar Sync alone: the CurseForge app brings the
-- library, the guild's other addons and KinFolk with it.
H.check(pkgmeta ~= nil and pkgmeta:find("required%-dependencies:\n    %- lib%-guild%-sync\n    %- guild%-professions%-recipes\n    %- guild%-bank%-alts\n    %- guild%-builds\n    %- guild%-raids%-events\n    %- kinfolk%-guild%-hub\n") ~= nil,
    ".pkgmeta makes LibGuildSync, the guild's other addons and KinFolk required relations on CurseForge")
H.check(toc:find("## OptionalDeps: GuildProfessionsRecipes, GuildBankAlts, GuildBuilds, GuildRaidsEvents, KinFolk", 1, true) ~= nil,
    "Bot'tar Sync loads after the guild's other addons and KinFolk, without needing them")
H.check(toc:find("## SavedVariables: BottarSyncDB, BottarSyncJSON", 1, true) ~= nil, "both saved variables are declared")
local announced = Read("Core.lua"):match('\nlocal ANNOUNCE_AS = "([%d%.]+)"')
if announced then
    print(("  NOTE: Core.lua tells the guild this is %s: set ANNOUNCE_AS to nil before tagging a release"):format(announced))
end
if Read("Core.lua"):find("\n    trial = true,", 1, true) then
    print("  NOTE: Core.lua talks on the trial prefix: set trial = false before tagging a release")
end
H.check(toc:find("## Dependencies: LibGuildSync", 1, true) ~= nil, "LibGuildSync is a dependency")
-- The game reads Bindings.xml by itself: not in the TOC, but in the package.
H.check(Read("Bindings.xml") ~= nil and pkgmeta ~= nil and pkgmeta:find("Bindings", 1, true) == nil,
    "Bindings.xml is packaged with the addon")
