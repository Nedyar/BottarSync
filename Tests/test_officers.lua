-- What the guild master and the officers set about who plays each character
-- (Officers.lua), how it prevails over the players' own profiles
-- (Profile.lua), and how an officer manages any player from the My data
-- window (MyData.lua).
local H = ...

local MODES = {
    CHAT = { "Chat", "InviteButton", "CommunitiesControlFrame" },
    ROSTER = { "MemberList", "CommunitiesControlFrame" },
}
local GUILD_CLUB = 1

local function GuildWindow(client)
    local frame = H.FakeCommunities(client)
    frame.InviteButton = H.NewObject(client, "Button")
    frame.CommunitiesControlFrame = H.NewObject(client, "Frame")
    frame.CommunitiesControlFrame.GuildControlButton = H.NewObject(client, "Button")
    frame.mode = MODES.ROSTER
    frame.clubId = GUILD_CLUB
    rawset(frame, "GetDisplayMode", function(self)
        return self.mode
    end)
    rawset(frame, "GetSelectedClubId", function(self)
        return self.clubId
    end)
    rawset(frame, "UpdateCommunitiesButtons", function() end)
    return frame
end

-- The game's menus: what addons add to a menu, by its tag.
local function Globals()
    local mods = {}
    return {
        COMMUNITIES_FRAME_DISPLAY_MODES = MODES,
        C_Club = {
            GetClubInfo = function(clubId)
                return { clubType = clubId == GUILD_CLUB and 2 or 1 }
            end,
        },
        ACCEPT = "Accept",
        SAVE = "Save",
        DECLINE = "Decline",
        Menu = {
            mods = mods,
            ModifyMenu = function(tag, fn)
                mods[tag] = fn
            end,
        },
    }
end

local function Errors(world, label)
    H.eq(#world.errors, 0, "no errors: " .. label)
    for _, err in ipairs(world.errors) do
        print("   " .. err)
    end
    world.errors = {}
end

local function Click(button)
    button._scripts.OnClick(button)
end

local function Type(box, text)
    box:SetText(text)
    box._scripts.OnTextChanged(box, true)
end

local function RecordOf(client, other)
    local guild = client.ns.Data.GetGuild("Test Guild")
    return guild and guild.members[other.guid or other]
end

-- Who plays each character, as a client sees it.
local function Who(client)
    local guild = client.ns.Data.GetGuild("Test Guild")
    local records = {}
    for guid, record in pairs(guild and guild.members or {}) do
        records[guid] = record
    end
    return client.ns.Profile.Resolve(records)
end

-- A character in a view of a client's window (nil: its own).
local function ItemOf(client, guid, view)
    for _, item in ipairs(client.ns.Profile.View(view).items) do
        if item.guid == guid then
            return item
        end
    end
end

-- The rows a client's window shows.
local function Rows(client)
    local window = client.ns.MyData.Window()
    local rows = {}
    for i, item in ipairs(window.items) do
        rows[i] = H.NewObject(client, "Frame")
        window.ScrollBox._view.init(rows[i], item)
        rows[item.guid] = rows[i]
    end
    return rows
end

local function SetRank(world, client, index)
    for _, member in ipairs(world.roster) do
        if member.guid == client.guid then
            member.rankIndex = index
        end
    end
    world:RosterChanged()
end

local world = H.NewWorld({ seed = 71, communities = GuildWindow, senderFormat = "short", strictWhispers = true })
-- The officers' rank has "Has officer privileges"; the veterans' has not.
world.officerRanks = { [1] = true }
local gm = world:NewClient("Gran Maestre", { globals = Globals(), rank = "GM", rankIndex = 0 })
local officer = world:NewClient("Oficial Uno", { globals = Globals(), rank = "Oficial", rankIndex = 1 })
local veteran = world:NewClient("Veterano Sin", { globals = Globals(), rank = "Veterano", rankIndex = 2 })
local player = world:NewClient("Jugador Main", { globals = Globals(), level = 60 })
-- Members without the addon, and one with it who logs in later.
local _, mage = world:AddMember("Sin Addon", nil, { class = "MAGE", level = 50 })
local _, warrior = world:AddMember("Otro Sin", nil, { class = "WARRIOR", level = 30 })
local recruit = world:NewClient("Nuevo Recluta", { globals = Globals(), level = 5 })
for _, client in ipairs({ gm, officer, veteran, player }) do
    world:Login(client)
end
world:RunFor(30)
player.ns.Profile.SetDiscord("jugador.uno")
world:RunFor(10)
local playerKey = player.ns.Profile.Account().key

H.section("Officers: who they are")
local Officers = officer.ns.Officers
H.check(Officers.IsOfficer(gm.guid), "the guild master")
H.check(Officers.IsOfficer(officer.guid), "a member whose rank has officer privileges")
H.check(not Officers.IsOfficer(veteran.guid) and not Officers.IsOfficer(player.guid), "not the other ranks")
H.check(Officers.AmI() and gm.ns.Officers.AmI() and not veteran.ns.Officers.AmI(), "each client knows whether it is one")
Errors(world, "who they are")

H.section("Officers: the window")
player.ns.MyData.Toggle()
local playerWindow = player.ns.MyData.Window()
H.check(not playerWindow.PlayerSearch:IsShown() and not playerWindow.Back:IsShown(), "a member's has no search of players")
officer.ns.MyData.Toggle()
local window = officer.ns.MyData.Window()
H.check(window.PlayerSearch:IsShown() and window.Back:IsShown(), "an officer's has one, with a button back to their own data")
H.check(not window.Back:IsEnabled() and window.view == nil, "which they see first")
local MyData = officer.ns.MyData
local found = MyData.PlayerMatches("jug")
H.check(found[1].player == "jugador.uno" and found[1].count == 1, "it finds a player by their username")
H.check(found[2].guid == player.guid and found[2].owner == "jugador.uno", "and a character by its name, with its player")
found = MyData.PlayerMatches("sin")
H.check(#found == 3 and found[1].guid == warrior and found[2].guid == mage and found[3].guid == veteran.guid
    and found[1].owner == nil, "characters that are nobody's too")
Type(window.PlayerSearch, "jugador.uno")
H.check(window.PlayerResults:IsShown() and window.PlayerResults.rows[1].Text._text:find("jugador.uno", 1, true),
    "typing shows the matches under the box")
window.PlayerSearch._scripts.OnEnterPressed(window.PlayerSearch)
H.check(window.view and window.view.dc == "jugador.uno", "Enter opens the player")
H.check(window.Input:GetText() == "jugador.uno" and window.Input:IsEnabled(), "their username, which the officer may change")
H.check(#window.items == 1 and window.items[1].guid == player.guid, "and their characters")
H.check(window.Back:IsEnabled() and window.Search:IsEnabled(), "back to their own data, and characters can be added")
Errors(world, "the window")

H.section("Officers: changing a player")
Type(window.Search, "Sin Addon")
H.check(window.Results.rows[1].item.guid == mage, "the search to add finds the guild's characters")
window.Search._scripts.OnEnterPressed(window.Search)
local who = Who(officer)
H.check(who[mage] and who[mage].dc == "jugador.uno" and not who[mage].pending and who[mage].set,
    "an officer adds a character to a player: theirs at once, not pending")
world:RunFor(10)
who = Who(veteran)
H.check(who[mage] and who[mage].dc == "jugador.uno" and not who[mage].main, "the guild has it within seconds, an alt")
local rows = Rows(officer)
H.check(rows[mage].Main:IsEnabled() and rows[mage].Remove:IsShown() and rows[player.guid].Remove:IsShown(),
    "the officer may tick any of them, and take any out")
rows[mage].Main:SetChecked(true)
Click(rows[mage].Main)
world:RunFor(10)
H.check(Who(veteran)[mage].main, "and makes it a main")
-- What the player sees and may change.
world:RunFor(1)
local item = ItemOf(player, mage)
H.check(item and item.state == "mine" and item.main and item.set, "the player has it, a main")
H.check(not item.canMain and not item.canRemove, "and cannot change it")
H.check(not player.ns.Profile.SetMain(mage, false) and not player.ns.Profile.Remove(mage), "not even by other ways")
H.check(ItemOf(player, player.guid).canMain and player.ns.Profile.SetMain(player.guid, true), "what no officer set, they can")
world:RunFor(10)
H.check(Who(veteran)[player.guid].main and Who(veteran)[mage].main, "both are mains")
H.check(not player.ns.Profile.View(nil).canName, "nor can they change their username, now that the officers set something")
local playerRows = Rows(player)
H.check(not playerRows[mage].Main:IsEnabled() and not playerRows[mage].Remove:IsShown(), "their window shows it")
H.check(not playerWindow.Input:IsEnabled(), "the username's box too")
Errors(world, "changing a player")

H.section("Officers: a rename")
Type(window.Input, "Jugador.Dos")
H.check(window.Save:IsEnabled(), "an officer can save a new username")
Click(window.Save)
H.check(window.view.dc == "jugador.dos", "the window follows the player")
world:RunFor(10)
who = Who(veteran)
H.check(who[player.guid].dc == "jugador.dos" and who[mage].dc == "jugador.dos", "every character of theirs goes by it")
H.eq(RecordOf(veteran, player).dc, "jugador.uno", "though the player's own profile still says the old one")
world:RunFor(1)
H.eq(playerWindow.Input:GetText(), "jugador.dos", "the player's window shows the new one")
-- The player still adds characters of their own: they count under the new name.
H.check(player.ns.Profile.Add(warrior), "the player still adds characters")
world:RunFor(10)
who = Who(gm)
H.check(who[warrior] and who[warrior].dc == "jugador.dos" and who[warrior].pending, "pending, under the new name")
Errors(world, "a rename")

H.section("Officers: a character that is nobody's")
H.check(officer.ns.Profile.Remove(warrior, { dc = "jugador.dos" }), "an officer takes a character out of a player")
world:RunFor(10)
H.eq(Who(gm)[warrior], nil, "it is nobody's, although the player's list names it")
H.eq(ItemOf(player, warrior), nil, "and the player's window leaves it out")
MyData.ShowCharacter(warrior)
H.check(window.view.guid == warrior and #window.items == 1 and window.items[1].guid == warrior, "the officer opens it alone")
H.check(window.Input:GetText() == "" and window.Input:IsEnabled() and not window.Search:IsEnabled(),
    "to give it a username first")
Type(window.Input, "nuevo.jugador")
Click(window.Save)
H.check(window.view.dc == "nuevo.jugador", "saved, the window shows its player")
world:RunFor(10)
who = Who(veteran)
H.check(who[warrior].dc == "nuevo.jugador" and who[warrior].main and not who[warrior].pending, "whose main it is")
H.eq(MyData.PlayerMatches("nuevo")[1].player, "nuevo.jugador", "and who can be found")
Errors(world, "nobody's")

H.section("Officers: opening a player from a character")
-- Not from the roster's right-click menu: an entry an addon adds there
-- taints the menu's closing, which lays out the roster again, and the game
-- then blocks changing a member's notes.
H.eq(officer.env.Menu.mods.MENU_UNIT_COMMUNITIES_GUILD_MEMBER, nil, "nothing is added to a guild member's right-click menu")
MyData.ShowCharacter(player.guid)
H.check(window.view and window.view.dc == "jugador.dos", "a character opens its player (the Statistics window's list does)")
MyData.ShowCharacter(officer.guid)
H.eq(window.view, nil, "their own data for one of their own characters")
MyData.ShowCharacter(player.guid)
Click(window.Back)
H.eq(window.view, nil, "My data goes back to the officer's own")
Errors(world, "opening a player")

H.section("Officers: what does not count")
H.check(not veteran.ns.Profile.SetMain(player.guid, false, { dc = "jugador.dos" }), "a member cannot change another player")
H.check(not veteran.ns.Officers.Assign(player.guid, "otro"), "nor set a character")
-- A member's record that claims to set something (another addon, or an
-- older one) is left out.
local forged = RecordOf(veteran, veteran)
forged.ov = { r = {}, a = { [player.guid] = { d = "hacker", m = false, t = veteran.ns.Now() + 1 } } }
veteran.ns.Data.TouchOwn(forged)
world:RunFor(10)
H.check(RecordOf(gm, veteran).ov ~= nil, "the guild gets it")
H.eq(Who(gm)[player.guid].dc, "jugador.dos", "but not from someone who is not an officer")
forged.ov = nil
veteran.ns.Data.TouchOwn(forged, "officers")
world:RunFor(10)
H.eq(RecordOf(gm, veteran).ov, nil, "taken back, within seconds")
Errors(world, "what does not count")

H.section("Officers: every officer keeps them")
local gmCopy = RecordOf(gm, gm).ov
H.check(gmCopy and gmCopy.a[mage] and gmCopy.a[mage].d == "jugador.dos" and gmCopy.r["jugador.uno"].n == "jugador.dos",
    "the guild master's record carries the officer's changes too")
SetRank(world, officer, 2)
world:RunFor(10)
H.check(not officer.ns.Officers.AmI(), "an officer who loses the rank is no longer one")
who = Who(veteran)
H.check(who[mage].dc == "jugador.dos" and who[warrior].dc == "nuevo.jugador", "what they set still holds, from the other officers' copies")
H.check(not officer.ns.Profile.View({ dc = "jugador.dos" }).canName, "and they can no longer change it")
world:RunFor(1)
H.eq(window.view, nil, "their window goes back to their own data")
-- The guild master gives the veterans' rank officer privileges.
world.officerRanks[2] = true
for _, client in ipairs({ gm, officer, veteran, player }) do
    world:FireEvent(client, "GUILD_RANKS_UPDATE")
end
world:RunFor(5)
H.check(veteran.ns.Officers.AmI() and player.ns.Officers.IsOfficer(officer.guid), "the rank settings say who is one")
world.officerRanks[2] = nil
for _, client in ipairs({ gm, officer, veteran, player }) do
    world:FireEvent(client, "GUILD_RANKS_UPDATE")
end
world:RunFor(5)
H.check(not veteran.ns.Officers.AmI(), "and who is not")
Errors(world, "every officer")

H.section("Officers: a character set to a player logs in")
H.check(gm.ns.Profile.Add(recruit.guid, { dc = "jugador.dos" }), "the guild master gives the player a character that never logged in")
world:RunFor(10)
world:Login(recruit)
world:RunFor(30)
H.check(not recruit.ns.DiscordPrompt.IsShown(), "it is not asked for a username")
H.eq(recruit.ns.Profile.Own().key, playerKey, "it goes by the player's profile")
H.eq(recruit.ns.Profile.Account().key, nil, "only it, not its WoW account")
H.eq(recruit.ns.Profile.View(nil).name, "jugador.dos", "its window shows the player's username")
world:RunFor(10)
who = Who(gm)
H.check(who[recruit.guid].dc == "jugador.dos" and not who[recruit.guid].main, "the player's alt")
Errors(world, "logging in")

H.section("Officers: the bot's file")
world:Logout(gm)
local data = H.DecodeJSON(gm.saved.BottarSyncJSON)
local byName = {}
for _, member in ipairs(data.guilds[1].members) do
    byName[member.name] = member
end
H.check(byName["Sin Addon"].discord == "jugador.dos" and byName["Sin Addon"].main == true and byName["Sin Addon"].pending == false,
    "a member without the addon has the player the officers set")
H.check(byName["Jugador Main"].discord == "jugador.dos", "a renamed player's characters, the new username")
H.check(byName["Otro Sin"].discord == "nuevo.jugador" and byName["Otro Sin"].main == true, "a new player's")
Errors(world, "the bot's file")
