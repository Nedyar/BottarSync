local H = ...

local function Errors(world, label)
    H.eq(#world.errors, 0, "no errors: " .. label)
    for _, err in ipairs(world.errors) do
        print("   " .. err)
    end
    world.errors = {}
end

local function RecordOf(client, other)
    local guild = client.ns.Data.GetGuild("Test Guild")
    return guild and guild.members[other.guid]
end

local LEATHER = { sl = 165, r = 300, m = 300, spell = 10662, hasRecipes = true }
local SKINNING = { sl = 393, r = 300, m = 300, spell = 10768, hasRecipes = false }

H.section("Sync: two members online")
local world = H.NewWorld({ seed = 7, senderFormat = "short", strictWhispers = true })
local alice = world:NewClient("Alice Smith", {
    professions = { LEATHER, SKINNING },
    talents = { active = 1, groups = { [1] = { [101] = 5, [201] = 3 } }, unspent = 0 },
    gear = { [1] = { link = "|cffa335ee|Hitem:16939:0:0:0:0:0:0:1:60|h[Helm]|h|r", il = 76 } },
    itemLevel = 60.5,
})
local bob = world:NewClient("Bob Jones", { classID = 1, raceID = 3, sex = 2, professions = {} })
local carol = world:NewClient("Carol White", { classID = 8, raceID = 1 })
world:AddMember("Dan Brown", nil, { class = "PRIEST", level = 42 })
world:Login(alice)
world:RunFor(5)
world:OpenProfession(alice, 165, { 1001, 1002, 1003, 1004 }, { 1001, 1003 })
world:Login(bob)
world:RunFor(120)
Errors(world, "two members online")
local aliceAtBob = RecordOf(bob, alice)
H.check(aliceAtBob ~= nil, "Bob has Alice's record")
if aliceAtBob then
    H.eq(aliceAtBob.c, 3, "with her class")
    H.check(aliceAtBob.p[165] and H.SameList(aliceAtBob.p[165].k, { 1001, 1003 }), "with her recipes")
    H.check(aliceAtBob.p[393] and aliceAtBob.p[393].k == false, "a profession without recipes")
    H.check(aliceAtBob.tl and #aliceAtBob.tl.s[1].t == 2, "with her talents")
    H.check(aliceAtBob.g and aliceAtBob.g[1].s == 1, "with her items")
    H.eq(aliceAtBob.il, 6050, "with her item level")
end
H.check(RecordOf(alice, bob) ~= nil and RecordOf(alice, bob).c == 1, "Alice has Bob's record")

H.section("Sync: the bot's admin logs in later")
world:Logout(bob)
world:RunFor(10)
world:Login(carol)
world:RunUntil(function()
    return RecordOf(carol, bob) ~= nil and RecordOf(carol, alice) ~= nil
end, 180)
Errors(world, "admin logs in")
H.check(RecordOf(carol, bob) ~= nil, "Carol gets Bob's record from Alice, though Bob is offline")
H.check(RecordOf(carol, alice) ~= nil and RecordOf(carol, alice).tl ~= nil, "and Alice's, talents included")
H.check(RecordOf(carol, alice) and not RecordOf(carol, bob).fh, "Bob's copy is marked as relayed")

H.section("Sync: changes are announced")
local before = RecordOf(carol, alice).t
alice.gear[1] = { link = "|cffa335ee|Hitem:16955:0:0:0:0:0:0:1:60|h[Better Helm]|h|r", il = 83 }
alice.itemLevel = 61
world:FireEvent(alice, "PLAYER_EQUIPMENT_CHANGED", 1, false)
world:RunFor(150)
Errors(world, "a change")
local updated = RecordOf(carol, alice)
H.check(updated.t > before, "Carol gets Alice's newer record")
H.eq(updated.g[1].i:match("item:(%d+)"), "16955", "with the new item")
H.eq(updated.il, 6100, "and the new item level")
alice.talents.groups[1][102] = 2
world:FireEvent(alice, "TRAIT_CONFIG_UPDATED", 501)
world:RunFor(150)
H.eq(#RecordOf(carol, alice).tl.s[1].t, 3, "a talent learned reaches Carol")
local sent = world.stats.guild
world:RunFor(600)
H.check(world.stats.guild - sent <= 2, "quiet when nothing changes (" .. (world.stats.guild - sent) .. " guild messages in 10 min)")

H.section("Sync: saved data")
world:Logout(carol)
world:RunFor(5)
H.eq(type(carol.saved.BottarSyncDB.guilds["Test Guild"].members[alice.guid].b), "string", "records are saved packed")
world:Login(carol)
world:RunFor(5)
H.check(RecordOf(carol, alice) ~= nil and RecordOf(carol, alice).tl ~= nil, "records come back after logging in again")
Errors(world, "saved data")

-- A character whose saved data was lost gets its recipe list back.
world:Logout(alice)
world:RunFor(5)
world:Login(alice, { brokenSavedVariables = true })
world:RunUntil(function()
    local own = alice.ns.Data.GetOwnRecord(false)
    return own and own.p[165] and type(own.p[165].k) == "table"
end, 240)
local own = alice.ns.Data.GetOwnRecord(false)
H.check(own and own.p[165] and H.SameList(own.p[165].k, { 1001, 1003 }), "lost recipes come back from the guild")
Errors(world, "lost data")

H.section("Sync: members who leave")
world:Login(bob)
world:RunFor(60)
world:Logout(bob)
world:RemoveMember(bob.key)
world:RosterChanged()
world:RunFor(150)
local guild = carol.ns.Data.GetGuild("Test Guild")
H.check(guild.roster.m[bob.guid] == nil, "Bob is gone from Carol's copy of the roster")
H.check(guild.members[bob.guid] ~= nil, "his record stays for a while, in case the roster read was partial")
Errors(world, "a member leaves")

H.section("Sync: /bottar sync")
local printed = #carol.printed
carol.env.SlashCmdList.BOTTARSYNC("sync")
world:RunFor(30)
local lines = {}
for i = printed + 1, #carol.printed do
    lines[#lines + 1] = carol.printed[i]
end
local text = table.concat(lines, "\n")
H.check(text:find("asking the guild", 1, true) ~= nil, "manual sync says it is asking")
H.check(text:find("nobody online has data you are missing", 1, true) ~= nil or text:find("sync finished", 1, true) ~= nil, "and how it ended")
Errors(world, "manual sync")
