-- DiscordPrompt.lua: the box that asks a guild member for their Discord
-- name, when their WoW account has none yet (see Profile.SchedulePrompt):
-- a text, a box to type it and an Accept button, which only takes a name
-- Discord could have (Profile.CleanDiscord). It stays until the name is
-- given; the window of the guild window's "My data" button changes it later.
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
local ACCEPT_HEIGHT = 22

local frame

-- Makes the box tall enough for its texts, which take more lines in some
-- languages: the title, the text, the box to type in, the text for a name
-- Discord could not have (room is kept for it) and the Accept button.
local function Layout()
    local height = 20 + frame.Title:GetStringHeight() + 8 + frame.Text:GetStringHeight() + 12
        + INPUT_HEIGHT + 4 + frame.Invalid:GetStringHeight() + 8 + ACCEPT_HEIGHT + 16
    frame:SetHeight(math.max(DiscordPrompt.HEIGHT, math.ceil(height)))
end

local function Update()
    local text = frame.Input:GetText() or ""
    local name = ns.Profile.CleanDiscord(text)
    frame.Accept:SetEnabled(name ~= nil)
    frame.Invalid:SetShown(name == nil and strtrim(text) ~= "")
end

function DiscordPrompt.Accept()
    local name = frame and ns.Profile.CleanDiscord(frame.Input:GetText())
    if not name then
        return
    end
    frame.Input:ClearFocus()
    frame:Hide()
    ns.Profile.SetDiscord(name)
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
    frame.Title:SetText(L["Your Discord username"])

    -- The username, not the display name nor a server nickname: the box's
    -- tooltip tells where Discord shows it.
    frame.Text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.Text:SetPoint("TOP", frame.Title, "BOTTOM", 0, -8)
    frame.Text:SetWidth(DiscordPrompt.WIDTH - 40)
    frame.Text:SetText(L["Type your Discord username (your account's unique one, in small letters), not your display name nor your server nickname. Bot'tar then knows which characters are yours."])

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
    frame.Accept:SetSize(128, ACCEPT_HEIGHT)
    frame.Accept:SetPoint("BOTTOM", 0, 16)
    frame.Accept:SetText(ACCEPT)
    frame.Accept:SetScript("OnClick", DiscordPrompt.Accept)
end

function DiscordPrompt.Show()
    if not frame then
        Create()
    end
    if frame:IsShown() then
        return
    end
    frame.Input:SetText("")
    Update()
    Layout()
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
