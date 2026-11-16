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

H.section("Sync: two members online")
local world = H.NewWorld({ seed = 7, senderFormat = "short", strictWhispers = true })
local alice = world:NewClient("Alice Smith", {
    professions = { LEATHER },
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
    H.check(aliceAtBob.c == 3 and aliceAtBob.r == 4 and aliceAtBob.sx == 3 and aliceAtBob.f == 1 and aliceAtBob.l == 60,
        "with her class, race, sex, faction and level")
    H.check(aliceAtBob.p == nil and aliceAtBob.g == nil and aliceAtBob.tl == nil and aliceAtBob.il == nil,
        "and nothing the other addons share")
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
H.check(RecordOf(carol, alice) ~= nil and not RecordOf(carol, bob).fh, "Bob's copy is marked as relayed")

H.section("Sync: changes are announced")
local before = RecordOf(carol, alice).t
alice.level = 61
world:FireEvent(alice, "PLAYER_LEVEL_UP", 61)
world:RunFor(150)
Errors(world, "a change")
local updated = RecordOf(carol, alice)
H.check(updated.t > before and updated.l == 61, "Carol gets Alice's new level")
before = RecordOf(carol, alice).t
alice.gear[1] = { link = "|cffa335ee|Hitem:16955:0:0:0:0:0:0:1:60|h[Better Helm]|h|r", il = 83 }
world:FireEvent(alice, "PLAYER_EQUIPMENT_CHANGED", 1, false)
world:RunFor(150)
H.eq(RecordOf(carol, alice).t, before, "an item changed is not Bot'tar Sync's news")
local sent = world.stats.guild
world:RunFor(600)
H.check(world.stats.guild - sent <= 4, "quiet when nothing changes (" .. (world.stats.guild - sent) .. " guild messages in 10 min, all addons)")

H.section("Sync: saved data")
world:Logout(carol)
world:RunFor(5)
H.eq(type(carol.saved.BottarSyncDB.guilds["Test Guild"].members[alice.guid].b), "string", "records are saved packed")
world:Login(carol)
world:RunFor(5)
H.check(RecordOf(carol, alice) ~= nil and RecordOf(carol, alice).l == 61, "records come back after logging in again")
Errors(world, "saved data")

-- A character whose saved data was lost shares itself again.
world:Logout(alice)
world:RunFor(5)
world:Login(alice, { brokenSavedVariables = true })
world:RunFor(60)
local own = alice.ns.Data.GetOwnRecord(false)
H.check(own and own.c == 3 and own.l == 61, "lost data comes back from the game")
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
