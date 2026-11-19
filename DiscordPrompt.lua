-- DiscordPrompt.lua: the box that asks a guild member, while their
-- character goes by no profile (see Profile.SchedulePrompt):
--   - whether it is the character of the player who added it to their list
--     (a claim): Accept makes only this character go by that player's
--     profile; Reject asks for its own username instead;
--   - else their Discord username: a text, a box to type it and an Accept
--     button, which only takes a name Discord could have
--     (Profile.CleanDiscord). It stays until the name is given; the window
--     of the guild window's "My data" button changes it later.
--
-- It is a frame of our own with the game's dialog border, not one of the
-- game's shared popups, so the game's own dialogs never run on a frame an
-- addon has used.
local _, ns = ...
local L = ns.L

local DiscordPrompt = {}
ns.DiscordPrompt = DiscordPrompt

DiscordPrompt.WIDTH = 360
DiscordPrompt.HEIGHT = 156 -- at least; it grows with its texts (Layout)
local INPUT_HEIGHT = 20
local BUTTON_WIDTH, BUTTON_HEIGHT = 128, 22

local frame

-- Makes the box tall enough for its texts, which take more lines in some
-- languages: the title, the text, the box to type in and the text for a
-- name Discord could not have (room is kept for it) when it asks for the
-- name, and the buttons.
local function Layout()
    local height = 20 + frame.Title:GetStringHeight() + 8 + frame.Text:GetStringHeight() + 12
    if frame.mode == "name" then
        height = height + INPUT_HEIGHT + 4 + frame.Invalid:GetStringHeight()
    end
    height = height + 8 + BUTTON_HEIGHT + 16
    frame:SetHeight(math.max(DiscordPrompt.HEIGHT, math.ceil(height)))
end

local function Update()
    if frame.mode ~= "name" then
        frame.Accept:SetEnabled(true)
        return
    end
    local text = frame.Input:GetText() or ""
    local name = ns.Profile.CleanDiscord(text)
    frame.Accept:SetEnabled(name ~= nil)
    frame.Invalid:SetShown(name == nil and strtrim(text) ~= "")
end

function DiscordPrompt.Accept()
    if not frame then
        return
    end
    if frame.mode == "claim" then
        local claim = frame.claim
        frame:Hide()
        ns.Profile.AcceptClaim(claim)
        return
    end
    local name = ns.Profile.CleanDiscord(frame.Input:GetText())
    if not name then
        return
    end
    frame.Input:ClearFocus()
    frame:Hide()
    ns.Profile.SetDiscord(name)
end

-- Rejecting a claim: the box asks for the character's own username, and
-- no longer about claims.
function DiscordPrompt.Reject()
    frame.rejected = true
    DiscordPrompt.Show(true)
end

-- Whether the box shows, asking for the username with nothing typed yet,
-- and no claim was rejected: a claim that comes now may take its place.
function DiscordPrompt.AsksName()
    return frame ~= nil and frame:IsShown() and frame.mode == "name" and not frame.rejected
        and strtrim(frame.Input:GetText() or "") == ""
end

local function Create()
    frame = CreateFrame("Frame", "BottarSyncDiscordPrompt", UIParent)
    frame:SetSize(DiscordPrompt.WIDTH, DiscordPrompt.HEIGHT)
    frame:SetPoint("TOP", 0, -135)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    frame.Border = CreateFrame("Frame", nil, frame, "DialogBorderTemplate")
    frame.Border:SetAllPoints()

    frame.Title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    frame.Title:SetPoint("TOP", 0, -20)

    frame.Text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.Text:SetPoint("TOP", frame.Title, "BOTTOM", 0, -8)
    frame.Text:SetWidth(DiscordPrompt.WIDTH - 40)

    frame.Input = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.Input:SetSize(220, INPUT_HEIGHT)
    frame.Input:SetPoint("TOP", frame.Text, "BOTTOM", 0, -12)
    frame.Input:SetAutoFocus(false)
    frame.Input:SetMaxLetters(ns.Profile.DISCORD_MAX + 1)
    frame.Input:SetScript("OnEnter", function(self)
        ns.MyData.ShowUsernameTooltip(self)
    end)
    frame.Input:SetScript("OnLeave", GameTooltip_Hide)
    frame.Input:SetScript("OnTextChanged", Update)
    frame.Input:SetScript("OnEnterPressed", DiscordPrompt.Accept)
    frame.Input:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    frame.Invalid = frame:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
    frame.Invalid:SetPoint("TOP", frame.Input, "BOTTOM", 0, -4)
    frame.Invalid:SetWidth(DiscordPrompt.WIDTH - 40)
    frame.Invalid:SetText(L["Discord usernames have 2 to 32 letters, numbers, _ or . (no spaces)."])
    frame.Invalid:Hide()

    frame.Accept = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.Accept:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    frame.Accept:SetText(ACCEPT)
    frame.Accept:SetScript("OnClick", DiscordPrompt.Accept)

    frame.Reject = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.Reject:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    frame.Reject:SetPoint("BOTTOM", BUTTON_WIDTH / 2 + 4, 16)
    frame.Reject:SetText(DECLINE)
    frame.Reject:SetScript("OnClick", DiscordPrompt.Reject)
end

-- Sets the box up to ask for the username ("name") or about a claim.
local function SetMode(mode, claim)
    frame.mode, frame.claim = mode, claim
    local asking = mode == "name"
    frame.Input:SetShown(asking)
    frame.Invalid:Hide()
    frame.Reject:SetShown(not asking)
    frame.Accept:ClearAllPoints()
    if asking then
        frame.Title:SetText(L["Your Discord username"])
        -- The username, not the display name nor a server nickname: the
        -- box's tooltip tells where Discord shows it.
        frame.Text:SetText(L["Type your Discord username (your account's unique one, in small letters), not your display name nor your server nickname. Bot'tar then knows which characters are yours."])
        frame.Input:SetText("")
        frame.Accept:SetPoint("BOTTOM", 0, 16)
    else
        frame.Title:SetText(L["Whose character is this?"])
        local text
        if claim.ch[ns.playerGUID] then
            text = L["%s added this character to their characters, as a main. If it is theirs, accept: only this character goes with them. If not, reject and give your own Discord username."]
        else
            text = L["%s added this character to their characters, as an alt. If it is theirs, accept: only this character goes with them. If not, reject and give your own Discord username."]
        end
        frame.Text:SetText(text:format(claim.dc))
        frame.Accept:SetPoint("BOTTOM", -(BUTTON_WIDTH / 2 + 4), 16)
    end
    Update()
    Layout()
end

-- Asks for the username. Already showing, it stays as it is, unless again
-- is set (a claim was rejected).
function DiscordPrompt.Show(again)
    if not frame then
        Create()
    end
    if frame:IsShown() and not again then
        return
    end
    SetMode("name")
    frame:Show()
end

-- Asks whether the character is the player's who added it (claim: the
-- record that carries their profile).
function DiscordPrompt.ShowClaim(claim)
    if not frame then
        Create()
    end
    SetMode("claim", claim)
    frame:Show()
end

function DiscordPrompt.Hide()
    if frame then
        frame:Hide()
    end
end

function DiscordPrompt.IsShown()
    return frame ~= nil and frame:IsShown()
end

DiscordPrompt.Frame = function()
    return frame
end
