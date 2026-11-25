-- KinFolk: a button from KinFolk's window to the game's guild window.
--
-- KinFolk (a guild hub addon by another author) comes with Bot'tar Sync for
-- the guild's members. Bot'tar Sync puts a button with the guild tabard on
-- KinFolk's window, left of its close button, that opens and closes the
-- game's guild window (the other window stays as it is): the same as on
-- the Statistics window (TitleButton.lua). A key binding (the
-- game's Key Bindings, AddOns) opens and closes KinFolk. Nothing here reads
-- KinFolk's data. Until 0.9 the game's guild window had a button with
-- KinFolk's logo too, where its Statistics button is now (Stats.lua).
--
-- Only KinFolk's public pieces are used: the global function of its addon
-- menu entry (named in its TOC) or its /kinfolk command, and the global
-- name of its window. KinFolk builds its window the first time it opens, so
-- the button goes on it right after one of the usual ways to open it (the
-- addon menu, /kinfolk, its minimap button, its J key option, our key), and
-- whenever the guild window opens. Nothing polls.
local _, ns = ...
local L = ns.L
local TitleButton = ns.TitleButton

local KinFolk = {}
ns.KinFolk = KinFolk

KinFolk.WINDOW = "KinFolkMainWindow"
KinFolk.BROKER = "KinFolk"
KinFolk.J_KEY_BUTTON = "KinFolkJKeyButton"

local windowButton -- ours, on KinFolk's window

-- KinFolk is loaded (it loads before Bot'tar Sync: OptionalDeps).
function KinFolk.IsLoaded()
    return type(KinFolk_OnCompartmentClick) == "function" or type(SlashCmdList.KINFOLK) == "function"
end

-- Puts our button on KinFolk's window, once it exists.
function KinFolk.AttachToWindow()
    local window = _G[KinFolk.WINDOW]
    if windowButton or type(window) ~= "table" or not window.CreateTexture then
        return
    end
    windowButton = TitleButton.NewGuildButton(window)
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

-- KinFolk may open by itself (its welcome page, a notice): our button goes
-- on its window when the guild window opens, too.
local function SetupGuildWindow()
    local communities = CommunitiesFrame
    -- A secure hook of the window's own OnShow (its XML calls the method by
    -- name), never HookScript: a hooked script runs in the same execution
    -- as the scripts of the window's children that follow it, and taints
    -- them (the roster's rows, from which the game then refuses to change a
    -- member's notes or rank).
    if communities and type(communities.OnShow) == "function" then
        hooksecurefunc(communities, "OnShow", KinFolk.AttachToWindow)
    end
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
