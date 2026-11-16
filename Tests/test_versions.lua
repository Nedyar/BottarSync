local H = ...

-- Members on the last release and members on this version share one guild:
-- both must keep talking. The release is taken from its git tag
-- (H.Release). Both run the guild's other addons, as the CurseForge app
-- installs them.
local RELEASE = "v0.3.1"

H.section("Versions: against " .. RELEASE)
local old = H.Release(RELEASE)
if not old then
    print("   NOTE: " .. RELEASE .. " could not be extracted with git: skipped")
    return
end
local OLD = { H.ADDONS[1], H.SOURCES[1], H.SOURCES[2], old }

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

local function Character(world, name, addons)
    return world:NewClient(name, {
        addons = addons,
        professions = { LEATHER },
        talents = { active = 1, groups = { [1] = { [101] = 5, [201] = 3 } }, unspent = 0 },
        gear = { [1] = { link = "|cffa335ee|Hitem:16939:0:0:0:0:0:0:1:60|h[Helm]|h|r", il = 76 } },
        itemLevel = 60.5,
    })
end

local function Find(list, name)
    for _, member in ipairs(list or {}) do
        if member.name == name then
            return member
        end
    end
end

for _, case in ipairs({
    { "this version first, then " .. RELEASE, nil, OLD },
    { RELEASE .. " first, then this version", OLD, nil },
}) do
    local label, firstAddons, secondAddons = case[1], case[2], case[3]
    local world = H.NewWorld({ seed = #label, senderFormat = "short", strictWhispers = true })
    local first = Character(world, "First Member", firstAddons)
    local second = Character(world, "Second Member", secondAddons)
    local current = firstAddons and second or first
    local release = firstAddons and first or second
    world:Login(first)
    world:RunFor(5)
    world:OpenProfession(first, 165, { 1001, 1002, 1003, 1004 }, { 1001, 1003 })
    world:Login(second)
    world:RunFor(10)
    world:OpenProfession(second, 165, { 1001, 1002, 1003, 1004 }, { 1001, 1003 })
    world:RunFor(300)
    local atCurrent, atRelease = RecordOf(current, release), RecordOf(release, current)
    H.check(atCurrent ~= nil and atCurrent.c == 3 and atCurrent.l == 60, label .. ": this version has the release's character")
    H.check(atCurrent ~= nil and atCurrent.p == nil and atCurrent.tl == nil and atCurrent.g == nil,
        label .. ": without the professions, talents and items the release still shares")
    H.check(atRelease ~= nil and atRelease.c == 3 and type(atRelease.p) == "table", label .. ": the release reads this version's records")
    -- A change while both are online.
    current.level = 61
    world:FireEvent(current, "PLAYER_LEVEL_UP", 61)
    world:RunFor(150)
    H.eq(RecordOf(release, current).l, 61, label .. ": a new level reaches the release")
    Errors(world, label)
    -- Both write the same members into the bot's file; this version takes
    -- professions and talents from the other addons.
    world:Logout(first)
    world:Logout(second)
    for _, client in ipairs({ first, second }) do
        local data = H.DecodeJSON(client.saved.BottarSyncJSON or "{}")
        local members = data.guilds and data.guilds[1] and data.guilds[1].members
        local a, b = Find(members, "First Member"), Find(members, "Second Member")
        H.check(a and b and a.hasAddon == true and b.hasAddon == true, label .. ": " .. client.name .. "'s file has both members")
    end
    local data = H.DecodeJSON(current.saved.BottarSyncJSON or "{}")
    local member = Find(data.guilds[1].members, release.name)
    H.check(member and type(member.professions) == "table" and #member.professions == 1 and #member.professions[1].recipes == 2,
        label .. ": this version's file has the release member's recipes, from Guild Professions & Recipes")
    H.check(member and type(member.talents) == "table" and type(member.equipment) == "table",
        label .. ": and their builds and items, from Guild Builds")
end
