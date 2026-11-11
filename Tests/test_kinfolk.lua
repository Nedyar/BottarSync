-- The buttons between the game's guild window and KinFolk's, and the key
-- binding (KinFolk.lua).
local H = ...

-- The game's guild window, with its minimize (or maximize) and close
-- buttons.
local function GuildWindow(client)
    local frame = H.FakeCommunities(client)
    frame.MaximizeMinimizeFrame = H.NewObject(client, "Frame")
    frame.MaximizeMinimizeFrame.MinimizeButton = H.NewObject(client, "Button")
    frame.MaximizeMinimizeFrame.MaximizeButton = H.NewObject(client, "Button")
    frame.CloseButton = H.NewObject(client, "Button")
    return frame
end

-- A stand-in for KinFolk, by its public pieces: the addon menu's function,
-- /kinfolk, its window (built the first time it opens), and, if asked, its
-- minimap launcher (LibDataBroker, now or later) and its J key button. The
-- game's ToggleGuildFrame counts the clicks.
local function FakeKinFolk(client, options)
    options = options or {}
    local kinfolk = {}
    local function Window()
        local env = client.env
        local window = env.KinFolkMainWindow
        if not window then
            window = env.CreateFrame("Frame", "KinFolkMainWindow", env.UIParent, "PortraitFrameTemplate")
            window.CloseButton = env.CreateFrame("Button", nil, window, "UIPanelCloseButton")
            window:Hide()
        end
        return window
    end
    function kinfolk.Toggle()
        local window = Window()
        window:SetShown(not window:IsShown())
    end
    -- KinFolk opening by itself (its welcome page, a notice).
    function kinfolk.Open()
        Window():Show()
    end
    local globals = {
        ToggleGuildFrame = function()
            client.guildToggles = (client.guildToggles or 0) + 1
        end,
    }
    if options.absent then
        return kinfolk, globals
    end
    globals.KinFolk_OnCompartmentClick = function()
        kinfolk.Toggle()
    end
    globals.SlashCmdList = {
        KINFOLK = function()
            kinfolk.Toggle()
        end,
    }
    if options.broker then
        local objects, callbacks = {}, {}
        kinfolk.broker = {
            GetDataObjectByName = function(_, name)
                return objects[name]
            end,
            RegisterCallback = function(_, event, fn)
                callbacks[event] = fn
            end,
        }
        function kinfolk.CreateLauncher()
            local object = {
                OnClick = function()
                    kinfolk.Toggle()
                end,
            }
            objects.KinFolk = object
            kinfolk.launcher = object
            local fire = callbacks["LibDataBroker_DataObjectCreated_KinFolk"]
            if fire then
                fire("LibDataBroker_DataObjectCreated_KinFolk", "KinFolk", object)
            end
        end
        if options.broker == "now" then
            kinfolk.CreateLauncher()
        end
        globals.LibStub = function(name)
            return name == "LibDataBroker-1.1" and kinfolk.broker or nil
        end
    end
    if options.jKey then
        local button = H.NewObject(client, "Button")
        button:SetScript("OnClick", function()
            kinfolk.Toggle()
        end)
        globals.KinFolkJKeyButton = button
        kinfolk.jKey = button
    end
    return kinfolk, globals
end

local function Setup(name, options)
    local world = H.NewWorld({ seed = 41, communities = GuildWindow })
    local client = world:NewClient(name, options and options.client)
    local kinfolk, globals = FakeKinFolk(client, options)
    client.globals = globals
    world:Login(client)
    world:RunFor(5)
    H.eq(#world.errors, 0, name .. ": no errors while loading and starting")
    for _, err in ipairs(world.errors) do
        print("   " .. err)
    end
    return client, kinfolk, client.ns.KinFolk
end

local function Click(button)
    button._scripts.OnClick(button)
end

local function ChildrenOf(client, parent)
    local count = 0
    for _, frame in ipairs(client.created or {}) do
        if frame._parent == parent then
            count = count + 1
        end
    end
    return count
end

H.section("KinFolk: the button on the guild window")
local client, kinfolk, KF = Setup("Kin Main")
local env = client.env
local communities = env.CommunitiesFrame
local button = KF.guildWindowButton
H.check(button ~= nil and button._parent == communities, "the guild window has our KinFolk button")
H.check(button._point[1] == "RIGHT" and button._point[2] == communities.MaximizeMinimizeFrame.MinimizeButton
    and button._point[3] == "LEFT" and button._point[4] == -2, "the button sits left of the minimize button, 2 pixels away")
button._scripts.OnMouseDown(button)
button._scripts.OnMouseUp(button)
communities._scripts.OnShow(communities)
H.check(button._point[2] == communities.MaximizeMinimizeFrame.MinimizeButton, "it stays there as the guild window opens")
button._scripts.OnEnter(button)
H.eq(env.GameTooltip._text, "KinFolk", "its tooltip names KinFolk")
H.eq(env.KinFolkMainWindow, nil, "KinFolk's window does not exist before it opens")
H.eq(KF.windowButton, nil, "nor does our button on it")

Click(button)
local window = env.KinFolkMainWindow
H.check(window ~= nil and window:IsShown(), "the button opens KinFolk")
local back = KF.windowButton
H.check(back ~= nil and back._parent == window, "KinFolk's window gets our guild window button as it opens")
H.check(back._point[1] == "RIGHT" and back._point[2] == window.CloseButton and back._point[3] == "LEFT",
    "the button sits left of KinFolk's close button")
back._scripts.OnEnter(back)
H.eq(env.GameTooltip._text, "Guild", "its tooltip names the guild window")

Click(back)
H.eq(client.guildToggles, 1, "the button on KinFolk opens the game's guild window")
H.check(window:IsShown(), "and KinFolk stays open")
Click(back)
H.eq(client.guildToggles, 2, "a second click closes the guild window again")

Click(button)
H.check(not window:IsShown(), "a second click on the guild window's button closes KinFolk")
H.eq(client.guildToggles, 2, "and leaves the guild window alone")
Click(button)
Click(button)
H.check(KF.windowButton == back and ChildrenOf(client, window) == 2,
    "KinFolk's window keeps a single button of ours (next to its close button)")

H.section("KinFolk: its own ways to open")
client, kinfolk, KF = Setup("Kin Slash")
client.env.SlashCmdList.KINFOLK("")
H.check(KF.windowButton ~= nil and KF.windowButton._parent == client.env.KinFolkMainWindow, "/kinfolk: the button goes on its window")

client, kinfolk, KF = Setup("Kin Menu")
client.env.KinFolk_OnCompartmentClick()
H.check(KF.windowButton ~= nil, "the addon menu entry: the button goes on its window")

client, kinfolk, KF = Setup("Kin Minimap", { broker = "now" })
kinfolk.launcher.OnClick()
H.check(KF.windowButton ~= nil, "its minimap button: the button goes on its window")

client, kinfolk, KF = Setup("Kin Later", { broker = "later" })
kinfolk.CreateLauncher()
kinfolk.launcher.OnClick()
H.check(KF.windowButton ~= nil, "a minimap button KinFolk makes after login: the button goes on its window")

client, kinfolk, KF = Setup("Kin Key", { jKey = true })
Click(kinfolk.jKey)
H.check(KF.windowButton ~= nil, "its J key option: the button goes on its window")

client, kinfolk, KF = Setup("Kin Alone")
kinfolk.Open()
H.eq(KF.windowButton, nil, "KinFolk opening by itself, first: no button yet")
communities = client.env.CommunitiesFrame
communities._scripts.OnShow(communities)
H.check(KF.windowButton ~= nil, "the button goes on its window when the guild window opens")

H.section("KinFolk: the key binding")
client, kinfolk, KF = Setup("Kin Bind")
H.eq(client.env.BINDING_HEADER_BOTTARSYNC, "Bot'tar Sync", "the binding's header is the addon's name")
H.eq(client.env.BINDING_NAME_BOTTARSYNC_KINFOLK, "Open or close KinFolk", "the binding has a name")
client.env.BottarSync_ToggleKinFolk()
H.check(client.env.KinFolkMainWindow ~= nil and client.env.KinFolkMainWindow:IsShown(), "the key opens KinFolk")
H.check(KF.windowButton ~= nil, "and the button goes on its window")
client.env.BottarSync_ToggleKinFolk()
H.check(not client.env.KinFolkMainWindow:IsShown(), "the key closes KinFolk")

client = Setup("Kin Spanish", { client = { locale = "esES" } })
H.eq(client.env.BINDING_NAME_BOTTARSYNC_KINFOLK, "Abrir o cerrar KinFolk", "the binding's name is translated")

local handle = io.open(H.ADDON .. "/Bindings.xml", "rb")
local bindings = handle and handle:read("*a")
if handle then
    handle:close()
end
H.check(bindings ~= nil and bindings:find('name="BOTTARSYNC_KINFOLK"', 1, true) ~= nil
    and bindings:find('header="BOTTARSYNC"', 1, true) ~= nil and bindings:find("BottarSync_ToggleKinFolk()", 1, true) ~= nil,
    "Bindings.xml declares the binding and calls the addon's function")

H.section("KinFolk: not installed")
client, kinfolk, KF = Setup("Kin Absent", { absent = true })
H.eq(KF.guildWindowButton, nil, "without KinFolk the guild window gets no button")
local printed = #client.printed
client.env.BottarSync_ToggleKinFolk()
H.check(#client.printed == printed + 1 and client.printed[#client.printed]:find("KinFolk is not installed", 1, true) ~= nil,
    "the key says KinFolk is missing")
H.eq(client.env.KinFolkMainWindow, nil, "and opens nothing")
