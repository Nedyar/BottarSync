-- The game's Guild Info tab (InfoTab.lua): the whole message of the day,
-- and the guild's Discord link (Officers.lua), which the officers change
-- and anyone copies.
local H = ...

-- The game's guild window, with its Guild Info tab's left column as
-- GuildInfo.xml makes it: the message box, the challenges' header (hidden
-- when the guild has no challenges, as in this version of the game), the
-- guild information's box, and the game's Edit links of both.
local function GuildWindow(client)
    local frame = H.FakeCommunities(client)
    local info = H.NewObject(client, "Frame")
    info.MOTDScrollFrame = H.NewObject(client, "Frame")
    info.Header2 = H.NewObject(client, "Texture")
    info.Header2:Hide()
    info.EditMOTDButton = H.NewObject(client, "Button")
    info.DetailsFrame = H.NewObject(client, "Frame")
    info.EditDetailsButton = H.NewObject(client, "Button")
    frame.GuildDetailsFrame.Info = info
    return frame
end

-- The game's functions that update the tab (hooked securely), and who may
-- edit the guild's texts.
local function Globals(client)
    local globals = {
        GUILD_EDIT_TEXT_LINK = "Edit",
        CanEditGuildInfo = function()
            return client.canEditInfo == true
        end,
    }
    for _, name in ipairs({ "CommunitiesGuildInfoFrame_UpdateText", "CommunitiesGuildInfoFrame_UpdatePermissions",
        "CommunitiesGuildInfoFrame_UpdateChallenges", "CommunitiesGuildInfoFrame_HideChallenges" }) do
        globals[name] = function()
            client.updates = (client.updates or 0) + 1
        end
    end
    return globals
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

local function NewClient(world, name, options)
    local client = world:NewClient(name, options)
    client.globals = Globals(client)
    return client
end

-- The message of the day, as the game tells it.
local function SetMessage(world, clients, text)
    for _, client in ipairs(clients) do
        client.env.C_GuildInfo.GetMOTD = function()
            return text
        end
        world:FireEvent(client, "GUILD_MOTD", text)
    end
end

local world = H.NewWorld({ seed = 83, communities = GuildWindow, senderFormat = "short", strictWhispers = true })
world.officerRanks = { [1] = true }
local officer = NewClient(world, "Oficial Uno", { rank = "Oficial", rankIndex = 1 })
local other = NewClient(world, "Oficial Dos", { rank = "Oficial", rankIndex = 1 })
local member = NewClient(world, "Miembro Raso", { rank = "Miembro", rankIndex = 3 })
officer.canEditInfo, other.canEditInfo = true, true
for _, client in ipairs({ officer, other, member }) do
    world:Login(client)
end
world:RunFor(30)
local everyone = { officer, other, member }

H.section("Guild Info: the message of the day")
local InfoTab = member.ns.InfoTab
local info = member.env.CommunitiesFrame.GuildDetailsFrame.Info
H.check(InfoTab.panel ~= nil and InfoTab.panel:IsShown(), "our panel shows on the tab")
H.eq(info.MOTDScrollFrame:GetAlpha(), 0, "over the game's message box, now invisible")
H.check(InfoTab.motd._point[2] == info.MOTDScrollFrame, "the message in the game's place for it")
SetMessage(world, everyone, "Raid el jueves a las 21:00 |cffff0000no faltéis|r")
H.eq(InfoTab.motd.Text._text, "Raid el jueves a las 21:00 ||cffff0000no faltéis||r",
    "the message of the day, its markup shown as text, as the game shows it")
-- Heights, as the game measures them.
local heights = {}
rawset(InfoTab.motd, "SetHeight", function(self, height)
    heights[#heights + 1] = height
end)
SetMessage(world, everyone, ("Una frase larga del mensaje del día. "):rep(6))
H.check(heights[#heights] > 24, "a long message gets as many lines as it takes")
SetMessage(world, everyone, ("x"):rep(3000))
H.eq(heights[#heights], InfoTab.DEFAULT_ROOM, "but no more than the room above the game's Guild Information")
SetMessage(world, everyone, "Corto")
H.eq(heights[#heights], 12, "a short one, a line")
Errors(world, "the message of the day")

H.section("Guild Info: the guild information")
local details = InfoTab.details
H.check(details ~= nil and details._points ~= nil, "a box for the guild information")
H.eq(info.DetailsFrame:GetAlpha(), 0, "over the game's own, now invisible")
local gameEdit = info.EditDetailsButton
H.check(gameEdit._point[1] == "RIGHT" and gameEdit._point[2] == InfoTab.panel.DetailsHeader,
    "the game's own Edit link on our header, so changing it stays the game's")
member.env.C_GuildInfo.GetInfoText = function()
    return "Si la vida te da limones"
end
member.env.CommunitiesGuildInfoFrame_UpdateText(info)
H.eq(details.Text._text, "Si la vida te da limones", "it shows the guild information")
member.env.CommunitiesGuildInfoFrame_UpdateText(info, "Recién guardada")
H.eq(details.Text._text, "Recién guardada", "and the one just saved, before the server has it")
Errors(world, "the guild information")

H.section("Guild Info: the Discord link")
H.check(InfoTab.box ~= nil and InfoTab.box._text == "", "no link at first")
H.check(InfoTab.box.Empty:IsShown(), "the box says there is none")
H.check(not InfoTab.copy:IsEnabled(), "nothing to copy")
H.check(not InfoTab.edit:IsShown(), "a member who is not an officer cannot change it")
local Mine = officer.ns.InfoTab
H.check(Mine.edit:IsShown(), "an officer who may edit the guild information can")
officer.canEditInfo = false
Mine.Refresh()
H.check(not Mine.edit:IsShown(), "not while the game does not let them edit it")
officer.canEditInfo = true
Mine.Refresh()

Click(Mine.edit)
H.check(not Mine.edit:IsShown() and not Mine.copy:IsEnabled(), "Edit: the box takes the link")
Type(Mine.box, "  https://discord.gg/abc123  ")
Mine.box._scripts.OnEnterPressed(Mine.box)
H.eq(officer.ns.Officers.GuildLink(), "https://discord.gg/abc123", "Enter saves it, trimmed")
H.eq(Mine.box._text, "https://discord.gg/abc123", "and the box shows it")
H.check(Mine.edit:IsShown() and Mine.copy:IsEnabled(), "the officer can copy it, or edit it again")
world:RunFor(30)
H.eq(member.ns.Officers.GuildLink(), "https://discord.gg/abc123", "it reaches the guild")
H.eq(InfoTab.box._text, "https://discord.gg/abc123", "every member's tab shows it")
H.check(not InfoTab.box.Empty:IsShown() and InfoTab.copy:IsEnabled(), "ready to copy")

-- Copying: the link selected in its box, for the player's own Ctrl+C.
local focused, selected = false, false
rawset(InfoTab.box, "SetFocus", function()
    focused = true
end)
rawset(InfoTab.box, "HighlightText", function()
    selected = true
end)
Click(InfoTab.copy)
H.check(focused and selected, "the copy button selects the link in its box")
InfoTab.copy._scripts.OnEnter(InfoTab.copy)
H.eq(member.env.GameTooltip._text, "Select the link to copy", "its tooltip says what it does")
Type(InfoTab.box, "https://discord.gg/otro")
H.eq(InfoTab.box._text, "https://discord.gg/abc123", "a member's typing is undone")
InfoTab.box._scripts.OnEnterPressed(InfoTab.box)
H.eq(member.ns.Officers.GuildLink(), "https://discord.gg/abc123", "and saves nothing")

-- Esc leaves it as it was.
Click(Mine.edit)
Type(Mine.box, "https://discord.gg/mal")
Mine.box._scripts.OnEscapePressed(Mine.box)
H.eq(Mine.box._text, "https://discord.gg/abc123", "Esc: the box shows the link again")
H.eq(officer.ns.Officers.GuildLink(), "https://discord.gg/abc123", "unchanged")
-- So does leaving the box.
Click(Mine.edit)
Type(Mine.box, "https://discord.gg/mal")
Mine.box._scripts.OnEditFocusLost(Mine.box)
H.eq(officer.ns.Officers.GuildLink(), "https://discord.gg/abc123", "leaving the box saves nothing either")

-- Another officer's newer link holds, everywhere.
Click(other.ns.InfoTab.edit)
Type(other.ns.InfoTab.box, "https://discord.gg/nuevo")
other.ns.InfoTab.box._scripts.OnEnterPressed(other.ns.InfoTab.box)
world:RunFor(30)
H.eq(member.ns.Officers.GuildLink(), "https://discord.gg/nuevo", "another officer's newer link holds")
H.eq(officer.ns.Officers.GuildLink(), "https://discord.gg/nuevo", "for the first officer too")
local own = officer.ns.Data.GetOwnRecord()
H.check(own.ov and own.ov.g and own.ov.g.v == "https://discord.gg/nuevo", "who keeps it in their own record too")

-- Taken away.
Click(Mine.edit)
Type(Mine.box, "")
Mine.box._scripts.OnEnterPressed(Mine.box)
world:RunFor(30)
H.eq(member.ns.Officers.GuildLink(), nil, "an officer can take it away")
H.check(InfoTab.box.Empty:IsShown() and not InfoTab.copy:IsEnabled(), "then the tab says there is none")
Errors(world, "the Discord link")

H.section("Guild Info: what does not count")
-- A member's client that sets a link in its record anyway.
local record = member.ns.Data.GetOwnRecord(true)
record.ov = { r = {}, a = {}, g = { v = "https://discord.gg/falso", t = member.ns.Now() + 10 } }
member.ns.Data.TouchOwn(record, "officers")
world:RunFor(30)
H.eq(officer.ns.Officers.GuildLink(), nil, "a link from someone who is not an officer counts for nobody")
H.eq(member.ns.Officers.SetGuildLink("https://discord.gg/x"), false, "and a member cannot set one")
H.eq(officer.ns.Officers.SetGuildLink(("x"):rep(member.ns.Pack.LIMITS.link + 1)), false, "nor anyone one too long")
H.eq(officer.ns.Officers.CleanLink(" a|cff00ff00b\n "), "acff00ff00b", "nor with the game's escapes or line breaks")
Errors(world, "what does not count")

H.section("Guild Info: the game's own")
-- With guild challenges, the game lays the tab out otherwise: ours stays
-- out of it.
info.Header2:Show()
InfoTab.Refresh()
H.check(not InfoTab.panel:IsShown() and info.MOTDScrollFrame:GetAlpha() == 1 and info.DetailsFrame:GetAlpha() == 1,
    "with guild challenges, the game's tab as it is")
info.Header2:Hide()
member.env.CommunitiesGuildInfoFrame_HideChallenges()
H.check(InfoTab.panel:IsShown() and info.MOTDScrollFrame:GetAlpha() == 0 and info.DetailsFrame:GetAlpha() == 0,
    "without them, ours again, after the game's own update")
-- Nothing of ours runs with the game's scripts as the tab opens or closes,
-- and none of the game's scripts are hooked.
for _, frame in ipairs({ InfoTab.panel, InfoTab.motd, InfoTab.box, InfoTab.edit, InfoTab.copy, InfoTab.details }) do
    H.check(frame._scripts.OnShow == nil and frame._scripts.OnHide == nil, "no OnShow or OnHide of ours")
end
H.eq(rawget(info, "_hooked"), nil, "no script of the game's tab hooked")
H.eq(rawget(info.MOTDScrollFrame, "_hooked"), nil, "nor of its message box")
Errors(world, "the game's own")
