local H = ...

-- Members on the last release and members on this version share one guild:
-- both must keep talking. The release is taken from its git tag
-- (H.Release).
local RELEASE = "v0.1.1"

H.section("Versions: against " .. RELEASE)
local old = H.Release(RELEASE)
if not old then
    print("   NOTE: " .. RELEASE .. " could not be extracted with git: skipped")
    return
end
local OLD = { old }

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

local function Character(world, name, addons)
    return world:NewClient(name, {
        addons = addons,
        professions = { LEATHER, SKINNING },
        talents = { active = 1, groups = { [1] = { [101] = 5, [201] = 3 } }, unspent = 0 },
        gear = { [1] = { link = "|cffa335ee|Hitem:16939:0:0:0:0:0:0:1:60|h[Helm]|h|r", il = 76 } },
        itemLevel = 60.5,
    })
end

-- Everything one character shares, as another client keeps it.
local function Complete(record)
    return record ~= nil and record.p[165] ~= nil and type(record.p[165].k) == "table" and #record.p[165].k == 2
        and record.p[393] ~= nil and record.p[393].k == false and record.tl ~= nil and #record.tl.s[1].t == 2
        and record.g ~= nil and record.il == 6050
end

for _, case in ipairs({
    { "this version first, then " .. RELEASE, nil, OLD },
    { RELEASE .. " first, then this version", OLD, nil },
}) do
    local label, firstAddons, secondAddons = case[1], case[2], case[3]
    local world = H.NewWorld({ seed = #label, senderFormat = "short", strictWhispers = true })
    local first = Character(world, "First Member", firstAddons)
    local second = Character(world, "Second Member", secondAddons)
    world:Login(first)
    world:RunFor(5)
    world:OpenProfession(first, 165, { 1001, 1002, 1003, 1004 }, { 1001, 1003 })
    world:Login(second)
    world:RunFor(10)
    world:OpenProfession(second, 165, { 1001, 1002, 1003, 1004 }, { 1001, 1003 })
    world:RunFor(300)
    H.check(Complete(RecordOf(second, first)), label .. ": the one who logged in later has the other's whole record")
    H.check(Complete(RecordOf(first, second)), label .. ": and the other way round")
    -- A change while both are online.
    first.talents.groups[1][102] = 2
    world:FireEvent(first, "TRAIT_CONFIG_UPDATED", 501)
    world:RunFor(150)
    local record = RecordOf(second, first)
    H.check(record and #record.tl.s[1].t == 3, label .. ": a talent learned reaches the other")
    Errors(world, label)
    -- Both write the same members into the bot's file.
    world:Logout(first)
    world:Logout(second)
    for _, client in ipairs({ first, second }) do
        local data = H.DecodeJSON(client.saved.BottarSyncJSON or "{}")
        local names = {}
        for _, member in ipairs(data.guilds and data.guilds[1] and data.guilds[1].members or {}) do
            names[member.name] = member.hasAddon
        end
        H.check(names["First Member"] == true and names["Second Member"] == true,
            label .. ": " .. client.name .. "'s file has both members")
    end
end
