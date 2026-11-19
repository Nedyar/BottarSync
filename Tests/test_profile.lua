-- Who plays each character (Profile.lua): the box that asks for the
-- Discord name (DiscordPrompt.lua), the "My data" window and its button on
-- the guild window (MyData.lua), and how the profile travels between the
-- characters of an account and the guild.
local H = ...

-- The game's guild window, with what our button needs: its views, the
-- selected community, and the buttons at its bottom right.
local MODES = {
    CHAT = { "Chat", "InviteButton", "CommunitiesControlFrame" },
    ROSTER = { "MemberList", "CommunitiesControlFrame" },
    GUILD_INFO = { "GuildDetailsFrame", "CommunitiesControlFrame" },
    MINIMIZED = { "Chat" },
}
local GUILD_CLUB, OTHER_CLUB = 1, 2

local function GuildWindow(client)
    local frame = H.FakeCommunities(client)
    frame.InviteButton = H.NewObject(client, "Button")
    frame.CommunitiesControlFrame = H.NewObject(client, "Frame")
    -- As in the Spanish client: its text does not fit its 130 pixels (the
    -- tests' text is 6 pixels a character).
    local settings = H.NewObject(client, "Button")
    settings._text, settings._width = "Ajustes de hermandad", 130
    frame.CommunitiesControlFrame.GuildControlButton = settings
    frame.mode = MODES.CHAT
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

local function Globals()
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
    return guild and guild.members[other.guid]
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

-- The player's list as a client's window shows it: the item of a GUID.
local function ItemOf(client, guid)
    for _, item in ipairs(client.ns.Profile.MyCharacters()) do
        if item.guid == guid then
            return item
        end
    end
end

local world = H.NewWorld({ seed = 61, communities = GuildWindow, senderFormat = "short", strictWhispers = true })
-- An officer who stays online all along, and writes the bot's file.
local officer = world:NewClient("Kantrul Steadyshot", { globals = Globals(), rank = "Officer", rankIndex = 1 })
local main = world:NewClient("Nedyar Cazador", { globals = Globals(), level = 37 })
-- For "adding characters" below: a member without the addon, and two
-- characters on other WoW accounts (their own saved data) that log in later.
local _, oldFriend = world:AddMember("Viejo Amigo", nil, { class = "MAGE", level = 50 })
local other = world:NewClient("Otra Cuenta", { globals = Globals(), level = 20 })
local rejecter = world:NewClient("Rechaza Todo", { globals = Globals(), level = 10 })
world:Login(officer)
world:RunFor(5)

H.section("Profile: the Discord name is asked at login")
world:Login(main)
world:RunFor(5)
local ns = main.ns
local Prompt = ns.DiscordPrompt
H.check(not Prompt.IsShown(), "not right away: the guild may still bring back a profile")
world:RunFor(15)
H.check(Prompt.IsShown(), "a little later, while the account has no Discord name")
H.check(Prompt.IsShown() and officer.ns.DiscordPrompt.IsShown(), "every member without one is asked")
local box = Prompt.Frame()
H.check(not box.Accept:IsEnabled() and not box.Invalid:IsShown(), "Accept waits for a name")
H.check(box.Text._text:find("not your display name nor your server nickname", 1, true) ~= nil,
    "it asks for the username, not the display name nor a server nickname")
box.Input._scripts.OnEnter(box.Input)
H.check(main.env.GameTooltip._text == "Discord username" and main.env.GameTooltip._lines[2]:find("under your display name", 1, true),
    "its box's tooltip tells where Discord shows the username")
Type(box.Input, "Two Words")
H.check(not box.Accept:IsEnabled() and box.Invalid:IsShown(), "a name Discord could not have is refused, and the box says why")
box.Input._scripts.OnEnterPressed(box.Input)
H.check(Prompt.IsShown() and ns.Profile.Account().dc == nil, "Enter does not take it either")
Type(box.Input, " @Nedyar.Main ")
H.check(box.Accept:IsEnabled() and not box.Invalid:IsShown(), "a good one can be accepted")
local before = RecordOf(main, main).t
Click(box.Accept)
H.check(not Prompt.IsShown(), "accepted, the box closes")
local account = ns.Profile.Account()
H.eq(account.dc, "nedyar.main", "the account keeps the name as Discord does: small letters, no @ nor spaces")
H.check(ns.Profile.CleanKey(account.key) ~= nil, "with a key of its own")
H.check(account.ch[main.guid] == true, "the character that gave it is the account's first main")
local own = RecordOf(main, main)
H.check(own.ak == account.key and own.dc == "nedyar.main" and own.ch[main.guid] == true and own.t > before,
    "our record carries the profile, as a change")
world:RunFor(10)
local copy = RecordOf(officer, main)
H.check(copy ~= nil and copy.dc == "nedyar.main" and copy.ak == account.key, "the guild has it within seconds")
H.check(Who(officer)[main.guid].dc == "nedyar.main" and Who(officer)[main.guid].main, "and sees whose main it is")
Errors(world, "the prompt")

H.section("Profile: an alt of the same account")
world:Logout(main)
local alt = world:NewClient("Nedyar Banco", { globals = Globals(), saved = main.saved, level = 1, classID = 8 })
world:Login(alt)
world:RunFor(30)
H.check(not alt.ns.DiscordPrompt.IsShown(), "is not asked: the account has a name")
local altOwn = RecordOf(alt, alt)
H.check(altOwn.ak == account.key and altOwn.dc == "nedyar.main", "its record carries the account's profile")
world:RunFor(10)
local who = Who(officer)
H.check(who[alt.guid] ~= nil and who[alt.guid].dc == "nedyar.main" and not who[alt.guid].main,
    "for the guild it is the same player's alt")
H.check(who[main.guid].main, "while the main stays a main")
Errors(world, "an alt")

H.section("Profile: the button on the guild window")
local env = alt.env
local communities = env.CommunitiesFrame
local MyData = alt.ns.MyData
local button = MyData.guildButton
local invite, settings = communities.InviteButton, communities.CommunitiesControlFrame.GuildControlButton
H.check(button ~= nil and button._parent == communities.CommunitiesControlFrame,
    "the guild window has our button, with the game's Guild Settings button")
H.check(button._point[1] == "BOTTOMRIGHT" and button._point[2] == communities and button._point[4] == -5 and button._point[5] == 5,
    "at its bottom right, where the game's buttons were")
H.eq(button._text, "My data", "named My data")
H.check(button:IsShown(), "shown on the guild's chat")
H.check(invite._point[1] == "RIGHT" and invite._point[2] == button and invite._point[3] == "LEFT" and invite._point[4] == -2,
    "Invite Member moves left of it, as far as the game's buttons are from each other")
H.check(settings._point[2] == button and settings._point[4] == -2, "and so does Guild Settings")
H.eq(settings._width, 120 + 40, "Guild Settings is widened to show its whole text, as the game's resizing buttons")
H.eq(button._width, 130, "ours keeps the game's width, its text fits")
communities.mode = MODES.ROSTER
communities:UpdateCommunitiesButtons()
H.check(button:IsShown() and settings._point[2] == button, "shown on the roster too, Guild Settings left of it")
communities.mode = MODES.GUILD_INFO
communities:UpdateCommunitiesButtons()
H.check(not button:IsShown(), "hidden on the guild's other views")
H.check(invite._point[1] == "BOTTOMRIGHT" and invite._point[2] == communities and invite._point[4] == -5 and invite._point[5] == 5,
    "Invite Member goes back to its place")
H.check(settings._point[1] == "BOTTOMRIGHT" and settings._point[2] == communities.CommunitiesControlFrame,
    "and Guild Settings to its own")
H.eq(settings._width, 160, "still wide enough for its text")
communities.mode, communities.clubId = MODES.CHAT, OTHER_CLUB
communities:UpdateCommunitiesButtons()
H.check(not button:IsShown() and invite._point[2] == communities, "hidden on another community's chat")
communities.clubId = GUILD_CLUB
communities:UpdateCommunitiesButtons()
H.check(button:IsShown() and invite._point[2] == button, "back on the guild's")
button._scripts.OnEnter(button)
H.eq(env.GameTooltip._text, "My data", "its tooltip")

H.section("Profile: the My data window")
Click(button)
local window = MyData.Window()
H.check(window ~= nil and window:IsShown(), "the button opens the window")
H.eq(window.Input:GetText(), "nedyar.main", "with the Discord name")
H.check(not window.Save:IsEnabled(), "Save waits for a change")
H.check(not window.NoName:IsShown(), "and no request to give a name first")
local items = window.items
H.eq(#items, 2, "the player's two characters")
H.check(items[1].guid == main.guid and items[1].main, "the main first")
H.check(items[2].guid == alt.guid and not items[2].main and items[2].own, "then this character, an alt")
local view = window.ScrollBox._view
local rows = {}
for i, item in ipairs(items) do
    rows[i] = H.NewObject(alt, "Frame")
    view.init(rows[i], item)
end
H.check(rows[1].Main:GetChecked() and rows[1].Kind._text == "Main", "a main's box is ticked")
H.check(not rows[2].Main:GetChecked() and rows[2].Kind._text == "Alt", "an alt's is not")
H.check(rows[1].Name._text:find("Nedyar Cazador", 1, true) and rows[1].Name._text:find("level 37", 1, true),
    "each with its name and level")
H.check(rows[2].Name._text:find("(this character)", 1, true) ~= nil, "the current character is told apart")
-- A row too narrow for its text shows it whole in a tooltip; one where it
-- fits shows none.
local tooltip = env.GameTooltip
tooltip._text = nil
rows[1]._scripts.OnEnter(rows[1])
H.eq(tooltip._text, nil, "no tooltip on a row whose text fits")
rows[2].Name.IsTruncated = function()
    return true
end
rows[2]._scripts.OnEnter(rows[2])
H.eq(tooltip._text, rows[2].Name._text, "a row whose text is cut shows it whole in a tooltip")
window.Input._scripts.OnEnter(window.Input)
H.eq(tooltip._text, "Discord username", "the name box's tooltip says what to type, as the prompt's")
-- The alt becomes a main too: a player may have several.
rows[2].Main:SetChecked(true)
Click(rows[2].Main)
local altAccount = alt.ns.Profile.Account()
H.check(altAccount.ch[main.guid] == true and altAccount.ch[alt.guid] == true, "both are mains now")
world:RunFor(1)
H.check(window.items[1].main and window.items[2].main, "the window shows it")
world:RunFor(10)
who = Who(officer)
H.check(who[alt.guid].main and who[main.guid].main, "and the guild has it within seconds")
-- A new Discord name, for every character of the account, offline ones too.
Type(window.Input, "Two Words")
H.check(not window.Save:IsEnabled() and window.Invalid:IsShown(), "a name Discord could not have cannot be saved")
window.Input._scripts.OnEscapePressed(window.Input)
H.eq(window.Input:GetText(), "nedyar.main", "Escape puts the saved name back")
Type(window.Input, "Nedyar_New")
H.check(window.Save:IsEnabled() and not window.Invalid:IsShown(), "a new name can be saved")
Click(window.Save)
H.eq(altAccount.dc, "nedyar_new", "saved")
world:RunFor(10)
who = Who(officer)
H.check(who[alt.guid].dc == "nedyar_new" and who[main.guid].dc == "nedyar_new",
    "the guild has the new name for every character of the account, also the one offline")
H.check(RecordOf(officer, main).dc == "nedyar.main", "though the offline one's own record still has the old name")
Errors(world, "the window")

H.section("Profile: profiles from the guild")
local Profile = alt.ns.Profile
local pt = altAccount.pt
H.check(not Profile.Adopt("Player-9-00000001", { ak = "OtherKey1234", dc = "someone", pt = pt + 50, ch = {} }),
    "another account's profile is not taken")
H.check(not Profile.Adopt("Player-9-00000001", { ak = altAccount.key, dc = "older", pt = pt - 50, ch = {} }),
    "nor an older one of ours")
H.check(Profile.Adopt("Player-9-00000001", { ak = altAccount.key, dc = "from.elsewhere", pt = pt + 50, ch = { [alt.guid] = false } }),
    "a newer one of ours is: changed on another computer")
H.check(altAccount.dc == "from.elsewhere" and altAccount.ch[alt.guid] == false and RecordOf(alt, alt).dc == "from.elsewhere",
    "and our record carries it")
Errors(world, "profiles from the guild")

H.section("Profile: a computer without the account's data")
-- A third character logs in on this computer, then the alt lists it among
-- the player's characters (any change of the profile does).
world:Logout(alt)
local third = world:NewClient("Nedyar Tercero", { globals = Globals(), saved = alt.saved })
world:Login(third)
world:RunFor(20)
world:Logout(third)
alt.saved = third.saved
world:Login(alt)
world:RunFor(10)
alt.ns.Profile.SetMain(alt.guid, true)
H.check(alt.ns.Profile.Account().ch[third.guid] == false, "the profile speaks of the third character, an alt")
world:RunFor(10)
world:Logout(alt)
-- The third one on another computer: no saved data at all.
third.saved = nil
world:Login(third)
world:RunFor(25)
local thirdBox = third.ns.DiscordPrompt.Frame()
H.check(third.ns.DiscordPrompt.IsShown() and thirdBox.mode == "claim", "it is asked whether it is the player's who lists it")
H.check(thirdBox.Text._text:find("from.elsewhere", 1, true) and thirdBox.Text._text:find("as an alt", 1, true),
    "naming them, and as what")
Click(thirdBox.Accept)
H.check(not third.ns.DiscordPrompt.IsShown(), "accepted, the box closes")
local altKey = alt.ns.Profile.Account().key
H.eq(third.ns.Profile.Own().key, altKey, "it goes by the player's profile again")
H.eq(third.ns.Profile.Own().dc, "from.elsewhere", "with its Discord name")
H.eq(third.ns.Profile.Account().key, nil, "only this character: the account on this computer still has none")
world:RunFor(10)
H.check(Who(officer)[third.guid].dc == "from.elsewhere" and not Who(officer)[third.guid].pending, "for the guild it is the player's")
world:Logout(third)
Errors(world, "another computer")

H.section("Profile: adding characters")
world:Login(alt)
world:RunFor(10)
alt.ns.MyData.Toggle()
local altWindow = alt.ns.MyData.Window()
local search, results = altWindow.Search, altWindow.Results
-- The names the search box shows for a text.
local function Found(text)
    local names = {}
    for _, item in ipairs(alt.ns.MyData.Matches(text) or {}) do
        names[#names + 1] = item.name
    end
    return table.concat(names, " / ")
end
H.check(not results:IsShown(), "nothing to show while nothing is typed")
H.eq(Found("a"), "Viejo Amigo / Kantrul Steadyshot / Otra Cuenta / Rechaza Todo",
    "it finds the guild's characters that are no one's, those with a word that starts with it first")
H.eq(Found("NEDYAR"), "", "not the player's own, in any case")
Type(search, "OTRA")
H.check(results:IsShown() and results.rows[1]:IsShown() and results.rows[1].Text._text:find("Otra Cuenta", 1, true)
    and not (results.rows[2] and results.rows[2]:IsShown()), "typing shows the matches above the box")
Type(search, "zzz")
H.check(results:IsShown() and results.Note._text == "No character to add by that name.", "or says there is none")
Type(search, "")
H.check(not results:IsShown(), "and goes away when the box is emptied")
Type(search, "a")
search._scripts.OnArrowPressed(search, "DOWN")
search._scripts.OnArrowPressed(search, "DOWN")
search._scripts.OnArrowPressed(search, "DOWN")
H.check(results.rows[4].Selected:IsShown() and not results.rows[1].Selected:IsShown(), "the arrows choose among them")
search._scripts.OnArrowPressed(search, "DOWN")
H.check(results.rows[1].Selected:IsShown(), "back to the first after the last")
search._scripts.OnEnterPressed(search)
local added = ItemOf(alt, oldFriend)
H.check(added ~= nil and search:GetText() == "" and not results:IsShown(), "Enter adds the chosen one and empties the box")
H.check(added and added.state == "pending" and added.main == false, "an added character is in the list, pending, an alt")
local altView = alt.ns.MyData.Window().ScrollBox._view
local addedRow = H.NewObject(alt, "Frame")
altView.init(addedRow, added)
H.check(addedRow.Name._text:find("(pending)", 1, true) and addedRow.Remove:IsShown(), "shown as pending, with a button to take it out")
alt.ns.Profile.SetMain(oldFriend, true)
H.check(ItemOf(alt, oldFriend).main, "it can be a main")
world:RunFor(10)
local friend = Who(officer)[oldFriend]
H.check(friend and friend.dc == "from.elsewhere" and friend.main and friend.pending,
    "the guild counts it at once as the player's main, pending (it has no Bot'tar Sync)")
-- Two characters on other WoW accounts that never gave a username.
H.check(alt.ns.Profile.Add(other.guid) and alt.ns.Profile.Add(rejecter.guid), "characters on other WoW accounts too")
H.check(not alt.ns.Profile.Add(other.guid), "each once")
world:RunFor(10)
-- One accepts (the alt stays online, on its own WoW account).
world:Login(other)
world:RunFor(25)
local otherBox = other.ns.DiscordPrompt.Frame()
H.check(other.ns.DiscordPrompt.IsShown() and otherBox.mode == "claim", "an added character is asked when it logs in")
Click(otherBox.Accept)
world:RunFor(10)
local otherRecord = RecordOf(officer, other)
H.check(otherRecord.dc == "from.elsewhere" and otherRecord.ak == altKey, "accepted, it goes by the player's profile")
H.check(not Who(officer)[other.guid].pending, "and is no longer pending")
H.eq(other.ns.Profile.Account().key, nil, "its WoW account does not")
-- From it, the player manages every character of theirs.
H.check(ItemOf(other, main.guid) and ItemOf(other, alt.guid) and ItemOf(other, third.guid) and ItemOf(other, other.guid)
    and ItemOf(other, oldFriend).state == "pending", "from it, the player sees every character of theirs")
other.ns.Profile.SetMain(other.guid, true)
world:RunFor(10)
H.check(Who(officer)[other.guid].main, "and changes them")
world:Logout(other)
-- Another character of that WoW account stays out of it.
local second = world:NewClient("Otra Segunda", { globals = Globals(), saved = other.saved })
world:Login(second)
world:RunFor(25)
H.check(second.ns.DiscordPrompt.IsShown() and second.ns.DiscordPrompt.Frame().mode == "name",
    "another character of that account is asked for its own username")
world:Logout(second)
-- The other one rejects, and gives its own username.
world:Login(rejecter)
world:RunFor(25)
local rejectBox = rejecter.ns.DiscordPrompt.Frame()
H.check(rejecter.ns.DiscordPrompt.IsShown() and rejectBox.mode == "claim", "the other one is asked too")
Click(rejectBox.Reject)
H.check(rejecter.ns.DiscordPrompt.IsShown() and rejectBox.mode == "name", "rejecting asks for its own username")
Type(rejectBox.Input, "otro.jugador")
Click(rejectBox.Accept)
world:RunFor(10)
local rejected = Who(officer)[rejecter.guid]
H.check(rejected.dc == "otro.jugador" and not rejected.pending, "it is its own player's")
world:Logout(rejecter)
H.eq(ItemOf(alt, rejecter.guid).state, "other", "the player's list shows it as another player's")
H.check(Who(alt)[rejecter.guid].dc == "otro.jugador", "and does not count it")
H.check(alt.ns.Profile.Remove(rejecter.guid) and ItemOf(alt, rejecter.guid) == nil, "it can be taken out")
H.eq(Found("Rechaza"), "", "the search leaves out other players' characters")
-- The other character's acceptance, seen from the player's own.
H.eq(ItemOf(alt, other.guid).state, "mine", "the one that accepted is the player's")
Errors(world, "adding characters")

H.section("Profile: joining a guild")
local newcomer = world:NewClient("New Comer", { globals = Globals() })
newcomer.inGuild = false
world:Login(newcomer)
world:RunFor(30)
H.check(not newcomer.ns.DiscordPrompt.IsShown(), "outside a guild no one is asked")
newcomer.inGuild = true
world:FireEvent(newcomer, "PLAYER_GUILD_UPDATE")
world:RunFor(20)
H.check(newcomer.ns.DiscordPrompt.IsShown(), "on joining one, the new member is")
Errors(world, "joining")

H.section("Profile: the bot's file")
world:Logout(officer)
local data = H.DecodeJSON(officer.saved.BottarSyncJSON)
local byName = {}
for _, member in ipairs(data.guilds[1].members) do
    byName[member.name] = member
end
H.check(byName["Nedyar Cazador"].discord == "from.elsewhere" and byName["Nedyar Cazador"].main == true,
    "each character has its player's Discord name, and whether it is a main")
H.check(byName["Nedyar Tercero"].discord == "from.elsewhere" and byName["Nedyar Tercero"].main == false, "or an alt")
H.check(byName["Nedyar Cazador"].pending == false and byName["Otra Cuenta"].discord == "from.elsewhere"
    and byName["Otra Cuenta"].pending == false, "not pending once theirs")
H.check(byName["Viejo Amigo"].discord == "from.elsewhere" and byName["Viejo Amigo"].main == true and byName["Viejo Amigo"].pending == true,
    "an added character that has not accepted: its player's, pending")
H.check(byName["Kantrul Steadyshot"].discord == H.NULL and byName["Kantrul Steadyshot"].main == H.NULL,
    "both are null for a member who gave no name")
Errors(world, "the bot's file")
