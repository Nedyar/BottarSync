-- KinFolk: buttons between the game's guild window and KinFolk's.
--
-- KinFolk (a guild hub addon by another author) comes with Bot'tar Sync for
-- the guild's members. Bot'tar Sync puts a button with KinFolk's logo on the
-- game's guild window, left of its minimize and close buttons, that opens
-- and closes KinFolk; and a button with the guild tabard on KinFolk's
-- window, left of its close button, that opens and closes the game's guild
-- window. Each button only opens and closes its own target: the other
-- window stays as it is. A key binding (the game's Key Bindings, AddOns)
-- also opens and closes KinFolk. Nothing here reads KinFolk's data.
--
-- Only KinFolk's public pieces are used: the global function of its addon
-- menu entry (named in its TOC) or its /kinfolk command, its logo file and
-- the global name of its window. KinFolk builds its window the first time it
-- opens, so the button goes on it right after one of the usual ways to open
-- it (the addon menu, /kinfolk, its minimap button, its J key option, our
-- button and key), and whenever the guild window opens. Nothing polls.
local _, ns = ...
local L = ns.L

local KinFolk = {}
ns.KinFolk = KinFolk

-- The buttons look like the game's own title bar buttons: the red frame of
-- its close button, with its pressed and highlight looks, as big as the
-- window's close button and as far from its neighbor as the game's buttons
-- are from each other. The close button's cross is covered by its own plain
-- red (a thin column left of the cross, stretched), and our icon goes on
-- it, square, a little bigger than the cross. KinFolk's logo is a round
-- emblem (a gold ring around a red disc with a book and a quill): the crop
-- keeps the largest square inside the red disc. The game's icons carry a
-- border of their own, which the usual crop leaves out. The tabard's shape
-- weighs on its lower half, so it goes a pixel higher (raise) to look
-- centered, as seen in game.
KinFolk.LOGO = "Interface\\AddOns\\KinFolk\\Media\\KinFolk_Icon"
KinFolk.LOGO_CROP = { 0.2, 0.8, 0.2, 0.8 }
KinFolk.GUILD_ICON = "Interface\\Icons\\INV_Shirt_GuildTabard_01"
KinFolk.GUILD_ICON_CROP = { 0.08, 0.92, 0.08, 0.92, raise = 1 }
KinFolk.FRAME = "RedButton-Exit"
KinFolk.FRAME_PRESSED = "RedButton-Exit-Pressed"
KinFolk.FRAME_HIGHLIGHT = "RedButton-Highlight"
KinFolk.SIZE = 24 -- when the window's close button has no size
KinFolk.RIM = 0.125 -- the frame's rim, part of the size: the red starts there
KinFolk.PLAIN = { 0.17, 0.22 } -- a column of the frame with only red in it
KinFolk.ICON = 0.19 -- the margin around the icon, part of the size
KinFolk.GAP = 2 -- between title bar buttons, when it cannot be measured
KinFolk.WINDOW = "KinFolkMainWindow"
KinFolk.BROKER = "KinFolk"
KinFolk.J_KEY_BUTTON = "KinFolkJKeyButton"

local guildWindowButton -- ours, on the game's guild window
local windowButton -- ours, on KinFolk's window

-- KinFolk is loaded (it loads before Bot'tar Sync: OptionalDeps).
function KinFolk.IsLoaded()
    return type(KinFolk_OnCompartmentClick) == "function" or type(SlashCmdList.KINFOLK) == "function"
end

local function HasAtlas(name)
    return C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil and C_Texture.GetAtlasInfo(name) ~= nil
end

local function SizeOf(close)
    local width = close and close.GetWidth and close:GetWidth()
    return (width and width > 0) and width or KinFolk.SIZE
end

-- Right of our button: neighbor, as far from it as neighbor is from close.
local function PlaceLeftOf(button, neighbor, close)
    local gap = KinFolk.GAP
    if neighbor ~= close and close and neighbor.GetRight and close.GetLeft then
        local right, left = neighbor:GetRight(), close:GetLeft()
        if right and left and left - right >= 0 and left - right <= 8 then
            gap = left - right
        end
    end
    button:ClearAllPoints()
    button:SetPoint("RIGHT", neighbor, "LEFT", -gap, 0)
end

local function NewButton(parent, neighbor, size, icon, crop, title, line, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    if neighbor.GetFrameLevel then
        button:SetFrameLevel(neighbor:GetFrameLevel())
    end
    local native = HasAtlas(KinFolk.FRAME)
    local rim = math.floor(size * KinFolk.RIM + 0.5)
    local margin = native and math.floor(size * KinFolk.ICON + 0.5) or 1
    button.Frame = button:CreateTexture(nil, "BACKGROUND")
    button.Frame:SetAllPoints()
    if native then
        button.Frame:SetAtlas(KinFolk.FRAME)
        button.Fill = button:CreateTexture(nil, "BORDER")
        button.Fill:SetPoint("TOPLEFT", rim, -rim)
        button.Fill:SetPoint("BOTTOMRIGHT", -rim, rim)
    else
        -- A thin dark border, should the game lack its red button.
        button.Frame:SetColorTexture(0, 0, 0, 1)
    end
    -- The plain red column of an atlas, from the rim down to the rim.
    local function Fill(atlas)
        local info = button.Fill and C_Texture.GetAtlasInfo(atlas)
        local file = info and (info.file or info.filename)
        if not file then
            return
        end
        local du, dv = info.rightTexCoord - info.leftTexCoord, info.bottomTexCoord - info.topTexCoord
        button.Fill:SetTexture(file)
        button.Fill:SetTexCoord(info.leftTexCoord + du * KinFolk.PLAIN[1], info.leftTexCoord + du * KinFolk.PLAIN[2],
            info.topTexCoord + dv * KinFolk.RIM, info.bottomTexCoord - dv * KinFolk.RIM)
    end
    Fill(KinFolk.FRAME)
    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetTexture(icon)
    button.Icon:SetTexCoord(unpack(crop))
    local raise = crop.raise or 0
    local function PlaceIcon(offset)
        button.Icon:ClearAllPoints()
        button.Icon:SetPoint("TOPLEFT", margin + offset, -margin - offset + raise)
        button.Icon:SetPoint("BOTTOMRIGHT", -margin + offset, margin - offset + raise)
    end
    PlaceIcon(0)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    if native and HasAtlas(KinFolk.FRAME_HIGHLIGHT) then
        highlight:SetAtlas(KinFolk.FRAME_HIGHLIGHT)
    else
        highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    end
    highlight:SetBlendMode("ADD")
    -- Pressed: the frame's pressed look, and the icon a pixel down and right.
    local pressed = native and HasAtlas(KinFolk.FRAME_PRESSED)
    button:SetScript("OnMouseDown", function()
        if pressed then
            button.Frame:SetAtlas(KinFolk.FRAME_PRESSED)
            Fill(KinFolk.FRAME_PRESSED)
        end
        PlaceIcon(1)
    end)
    button:SetScript("OnMouseUp", function()
        if pressed then
            button.Frame:SetAtlas(KinFolk.FRAME)
            Fill(KinFolk.FRAME)
        end
        PlaceIcon(0)
    end)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(title)
        GameTooltip:AddLine(line, 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
end

-- Puts our button on KinFolk's window, once it exists.
function KinFolk.AttachToWindow()
    local window = _G[KinFolk.WINDOW]
    if windowButton or type(window) ~= "table" or not window.CreateTexture then
        return
    end
    local close = window.CloseButton
    windowButton = NewButton(window, close or window, SizeOf(close), KinFolk.GUILD_ICON, KinFolk.GUILD_ICON_CROP,
        GUILD or "Guild", L["Open or close the game's guild window"], KinFolk.ToggleGuildWindow)
    if close then
        PlaceLeftOf(windowButton, close, close)
    else
        windowButton:SetPoint("TOPRIGHT", window, "TOPRIGHT", -30, -4)
    end
    KinFolk.windowButton = windowButton
end

-- Opens or closes KinFolk, the way its addon menu entry does.
function KinFolk.Toggle()
    if type(KinFolk_OnCompartmentClick) == "function" then
        KinFolk_OnCompartmentClick()
    elseif type(SlashCmdList.KINFOLK) == "function" then
        SlashCmdList.KINFOLK("")
    else
        ns.Print(L["KinFolk is not installed, or it is turned off."])
        return
    end
    KinFolk.AttachToWindow()
end

-- Opens or closes the game's guild window, as its key does.
function KinFolk.ToggleGuildWindow()
    if type(ToggleGuildFrame) == "function" then
        ToggleGuildFrame()
    end
end

-- Our button on the game's guild window, left of its minimize button.
local function SetupGuildWindow()
    local communities = CommunitiesFrame
    if guildWindowButton or not (communities and communities.CreateTexture) then
        return
    end
    local close = communities.CloseButton
    -- The minimize and maximize buttons take turns in the same spot.
    local frame = communities.MaximizeMinimizeFrame
    local neighbor = frame and (frame.MinimizeButton or frame.MaximizeButton or frame) or close
    guildWindowButton = NewButton(communities, neighbor or communities, SizeOf(close), KinFolk.LOGO, KinFolk.LOGO_CROP,
        "KinFolk", L["Open or close KinFolk"], KinFolk.Toggle)
    local function Place()
        if neighbor then
            PlaceLeftOf(guildWindowButton, neighbor, close)
        else
            guildWindowButton:SetPoint("TOPRIGHT", communities, "TOPRIGHT", -30, -4)
        end
    end
    Place()
    KinFolk.guildWindowButton = guildWindowButton
    communities:HookScript("OnShow", function()
        -- The gap between the game's buttons can be measured once shown.
        Place()
        -- KinFolk may have opened by itself (its welcome page, a notice).
        KinFolk.AttachToWindow()
    end)
    KinFolk.AttachToWindow()
end

-- KinFolk's minimap button is a LibDataBroker launcher: its click is
-- looked up on every click, so a hook on it runs after KinFolk's.
local function HookBroker(object)
    if type(object) == "table" and type(object.OnClick) == "function" then
        hooksecurefunc(object, "OnClick", KinFolk.AttachToWindow)
    end
end

function KinFolk.Init()
    if not KinFolk.IsLoaded() then
        return
    end
    if type(KinFolk_OnCompartmentClick) == "function" then
        hooksecurefunc("KinFolk_OnCompartmentClick", KinFolk.AttachToWindow)
    end
    if type(SlashCmdList.KINFOLK) == "function" then
        hooksecurefunc(SlashCmdList, "KINFOLK", KinFolk.AttachToWindow)
    end
    local broker = LibStub and LibStub("LibDataBroker-1.1", true)
    if broker then
        local object = broker:GetDataObjectByName(KinFolk.BROKER)
        if object then
            HookBroker(object)
        elseif broker.RegisterCallback then
            -- KinFolk makes it later, or never if its button is hidden.
            broker.RegisterCallback(KinFolk, "LibDataBroker_DataObjectCreated_" .. KinFolk.BROKER, function(_, _, created)
                HookBroker(created)
            end)
        end
    end
    -- KinFolk's J key option clicks this hidden button of its own.
    local jKey = _G[KinFolk.J_KEY_BUTTON]
    if type(jKey) == "table" and jKey.HookScript then
        jKey:HookScript("OnClick", KinFolk.AttachToWindow)
    end
    EventUtil.ContinueOnAddOnLoaded("Blizzard_Communities", SetupGuildWindow)
end

-- The key binding (Bindings.xml).
BINDING_HEADER_BOTTARSYNC = "Bot'tar Sync"
BINDING_NAME_BOTTARSYNC_KINFOLK = L["Open or close KinFolk"]

function BottarSync_ToggleKinFolk()
    KinFolk.Toggle()
end
