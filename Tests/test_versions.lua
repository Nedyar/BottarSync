local H = ...

-- Members on the last release and members on this version share one guild.
-- This version talks a new protocol (4: an officer's record carries what
-- the officers set), which the release would leave out of the copies it
-- passes on: this version still hears the release's changes (protocol 3),
-- the release gets nothing from it and is told to update, or, while this
-- version is tried in game (trial), does not hear it at all. The release is
-- taken from its git tag (H.Release). Both run the guild's other addons, as
-- the CurseForge app installs them.
local RELEASE = "v0.7.0"

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

local function ToldToUpdate(client)
    for _, line in ipairs(client.printed) do
        if line:find("cannot talk to", 1, true) then
            return true
        end
    end
    return false
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
    current.ns.Profile.SetDiscord("current.player")
    release.ns.Profile.SetDiscord("release.player")
    world:RunFor(300)
    -- A change of the release's while both are online.
    release.level = 61
    world:FireEvent(release, "PLAYER_LEVEL_UP", 61)
    world:RunFor(150)
    local atCurrent = RecordOf(current, release)
    H.check(atCurrent ~= nil and atCurrent.l == 61 and atCurrent.dc == "release.player",
        label .. ": this version hears the release's changes, with its profile")
    H.eq(RecordOf(release, current), nil, label .. ": the release gets nothing from this version")
    if current.ns.TRIAL then
        H.check(not ToldToUpdate(release), label .. ": while this version is tried, the release is not told to update")
    else
        H.check(ToldToUpdate(release), label .. ": the release is told to update")
    end
    Errors(world, label)
    -- This version's file has both members, the release's recipes and
    -- builds from the other addons, which still share between versions.
    world:Logout(first)
    world:Logout(second)
    local data = H.DecodeJSON(current.saved.BottarSyncJSON or "{}")
    local members = data.guilds and data.guilds[1] and data.guilds[1].members
    local mine, theirs = Find(members, current.name), Find(members, release.name)
    H.check(mine and theirs and mine.discord == "current.player" and mine.pending == false,
        label .. ": this version's file has both members, with its own Discord username")
    H.check(theirs and type(theirs.professions) == "table" and #theirs.professions == 1 and #theirs.professions[1].recipes == 2,
        label .. ": and the release member's recipes, from Guild Professions & Recipes")
    H.check(theirs and type(theirs.talents) == "table" and type(theirs.equipment) == "table",
        label .. ": and their builds and items, from Guild Builds")
    data = H.DecodeJSON(release.saved.BottarSyncJSON or "{}")
    members = data.guilds and data.guilds[1] and data.guilds[1].members
    H.check(Find(members, current.name) ~= nil, label .. ": the release's file still lists this version's member, from the roster")
end
