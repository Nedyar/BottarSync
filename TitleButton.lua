-- TitleButton.lua: a button with an icon for a window's title bar, beside
-- its close button: the Statistics button on the game's guild window
-- (Stats.lua) and the guild button on KinFolk's window (KinFolk.lua).
--
-- It looks like the game's own title bar buttons: the red frame of its
-- close button, with its pressed and highlight looks, as big as the
-- window's close button and as far from its neighbor as the game's buttons
-- are from each other. The close button's cross is covered by its own plain
-- red (a thin column left of the cross, stretched), and the icon goes on
-- it, square, a little bigger than the cross. The game's icons carry a
-- border of their own, which the usual crop leaves out (crop: left, right,
-- top, bottom, and raise: pixels up, for an icon whose shape weighs on its
-- lower half, to look centered).
local _, ns = ...

local TitleButton = {}
ns.TitleButton = TitleButton

TitleButton.FRAME = "RedButton-Exit"
TitleButton.FRAME_PRESSED = "RedButton-Exit-Pressed"
TitleButton.FRAME_HIGHLIGHT = "RedButton-Highlight"
TitleButton.SIZE = 24 -- when the window's close button has no size
TitleButton.RIM = 0.125 -- the frame's rim, part of the size: the red starts there
TitleButton.PLAIN = { 0.17, 0.22 } -- a column of the frame with only red in it
TitleButton.ICON = 0.19 -- the margin around the icon, part of the size
TitleButton.GAP = 2 -- between title bar buttons, when it cannot be measured
TitleButton.ICON_CROP = { 0.08, 0.92, 0.08, 0.92 } -- a game icon without its border

local function HasAtlas(name)
    return C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil and C_Texture.GetAtlasInfo(name) ~= nil
end

-- The size of a window's close button, for ours to match.
function TitleButton.SizeOf(close)
    local width = close and close.GetWidth and close:GetWidth()
    return (width and width > 0) and width or TitleButton.SIZE
end

-- Right of the button: neighbor, as far from it as neighbor is from close.
function TitleButton.PlaceLeftOf(button, neighbor, close)
    local gap = TitleButton.GAP
    if neighbor ~= close and close and neighbor.GetRight and close.GetLeft then
        local right, left = neighbor:GetRight(), close:GetLeft()
        if right and left and left - right >= 0 and left - right <= 8 then
            gap = left - right
        end
    end
    button:ClearAllPoints()
    button:SetPoint("RIGHT", neighbor, "LEFT", -gap, 0)
end

-- A new button on parent, at neighbor's frame level. Its tooltip: title,
-- and line under it.
function TitleButton.New(parent, neighbor, size, icon, crop, title, line, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    if neighbor.GetFrameLevel then
        button:SetFrameLevel(neighbor:GetFrameLevel())
    end
    local native = HasAtlas(TitleButton.FRAME)
    local rim = math.floor(size * TitleButton.RIM + 0.5)
    local margin = native and math.floor(size * TitleButton.ICON + 0.5) or 1
    button.Frame = button:CreateTexture(nil, "BACKGROUND")
    button.Frame:SetAllPoints()
    if native then
        button.Frame:SetAtlas(TitleButton.FRAME)
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
        button.Fill:SetTexCoord(info.leftTexCoord + du * TitleButton.PLAIN[1], info.leftTexCoord + du * TitleButton.PLAIN[2],
            info.topTexCoord + dv * TitleButton.RIM, info.bottomTexCoord - dv * TitleButton.RIM)
    end
    Fill(TitleButton.FRAME)
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
    if native and HasAtlas(TitleButton.FRAME_HIGHLIGHT) then
        highlight:SetAtlas(TitleButton.FRAME_HIGHLIGHT)
    else
        highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    end
    highlight:SetBlendMode("ADD")
    -- Pressed: the frame's pressed look, and the icon a pixel down and right.
    local pressed = native and HasAtlas(TitleButton.FRAME_PRESSED)
    button:SetScript("OnMouseDown", function()
        if pressed then
            button.Frame:SetAtlas(TitleButton.FRAME_PRESSED)
            Fill(TitleButton.FRAME_PRESSED)
        end
        PlaceIcon(1)
    end)
    button:SetScript("OnMouseUp", function()
        if pressed then
            button.Frame:SetAtlas(TitleButton.FRAME)
            Fill(TitleButton.FRAME)
        end
        PlaceIcon(0)
    end)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(title)
        GameTooltip:AddLine(line, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
end
