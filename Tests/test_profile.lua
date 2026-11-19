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

local world = H.NewWorld({ seed = 61, communities = GuildWindow, senderFormat = "short", strictWhispers = true })
-- An officer who stays online all along, and writes the bot's file.
local officer = world:NewClient("Kantrul Steadyshot", { globals = Globals(), rank = "Officer", rankIndex = 1 })
local main = world:NewClient("Nedyar Cazador", { globals = Globals(), level = 37 })
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
H.check(not third.ns.DiscordPrompt.IsShown(), "it is not asked")
H.eq(third.ns.Profile.Account().key, alt.ns.Profile.Account().key, "it took the account's profile from the guild")
H.eq(third.ns.Profile.Account().dc, "from.elsewhere", "with its Discord name")
Errors(world, "another computer")

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
H.check(byName["Kantrul Steadyshot"].discord == H.NULL and byName["Kantrul Steadyshot"].main == H.NULL,
    "both are null for a member who gave no name")
Errors(world, "the bot's file")
