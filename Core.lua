-- Bot'tar Sync: shares every guild member's characters with the guild, and
-- who plays them (their Discord name, mains and alts: Profile.lua, which
-- the guild's officers may set over what the players say: Officers.lua), and
-- writes them, as JSON, into the saved variables file for the Bot'tar bot,
-- together with what the guild's other addons share (Sources.lua). From the
-- game's guild window it opens a Statistics window, with a list of the
-- members to filter (Filters.lua, Stats.lua, RosterView.lua), and its Guild
-- Info tab shows the whole message of the day and the guild's Discord link
-- (InfoTab.lua).
--
-- The addon messages, the guild roster, the saved database and the sync
-- are LibGuildSync's (a separate addon this one depends on), attached
-- below. Core.lua holds the startup and the slash commands.
local ADDON_NAME, ns = ...
local L = ns.L
local Lib = LibGuildSync

ns.ADDON_NAME = ADDON_NAME

-- While a version with a new protocol is tried in game before its release,
-- set trial = true: it then talks on trialPrefix (see LibGuildSync's
-- Core.lua). Turn it off for the release.
Lib.Attach(ns, {
    title = "Bot'tar Sync",
    tag = "BS",
    prefix = "BottarSync",
    trialPrefix = "BottarSyncTest",
    trial = false,
    -- 5: what the officers set carries the guild's Discord link (0.9),
    -- which 0.8 would leave out of the copies it passes on. Still read: 4,
    -- the changes of members on 0.8, 3, those of members on 0.7, 2, those
    -- of members on 0.5 and 0.6, and 1, those of members on 0.4 and before.
    protocol = "5",
    legacy = { ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true },
    savedVariable = "BottarSyncDB",
})

-- A change to the Discord name, mains or alts goes out within seconds, an
-- officer's too.
ns.Sync.QUICK_KINDS.profile = true
ns.Sync.QUICK_KINDS.officers = true

-- While a version that keeps the protocol is tried in game before its
-- release, it tells the guild it runs the last release (ANNOUNCE_AS): it
-- keeps sharing with the members on it, who are not told to update to a
-- version they cannot get yet. Set it to nil for the release.
local ANNOUNCE_AS = nil
if ANNOUNCE_AS then
    ns.VERSION_NUM = Lib.VersionNumber(ANNOUNCE_AS)
end

-- Our own character has been read, so what we announce is current.
function ns.Sync.OwnReady()
    return ns.Character.ready
end

-- Professions ----------------------------------------------------------------

-- Name of a skill line in the client's language. spellID (the profession's
-- own spell) is the fallback when the client cannot name it.
function ns.ProfessionName(skillLine, spellID)
    local name = ns.Try(C_TradeSkillUI.GetTradeSkillDisplayName, skillLine)
    if not name or name == "" then
        local info = ns.Try(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLine)
        name = type(info) == "table" and info.professionName or nil
    end
    if (not name or name == "") and spellID then
        name = C_Spell.GetSpellName(spellID)
    end
    return (name and name ~= "") and name or nil
end

-- Startup ------------------------------------------------------------------

local events = CreateFrame("Frame")
ns.RegisterEvents(events, "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT")
events:SetScript("OnEvent", function(self, event, name)
    if event == "PLAYER_LOGOUT" then
        -- The JSON first: it reads the data before it is packed for saving.
        xpcall(ns.Export.WriteSaved, geterrorhandler())
        ns.Data.PackForSave(ns.db)
    elseif event == "ADDON_LOADED" and name == ADDON_NAME then
        self:UnregisterEvent("ADDON_LOADED")
        ns.Data.Load()
        if ns.db.settings.locale then
            ns.SetLocale(ns.db.settings.locale)
        end
    elseif event == "PLAYER_LOGIN" then
        -- The library first: our name, the roster, the messages and the sync.
        Lib.Start(ns)
        -- Each part starts on its own, so a failure in one (reported as a normal
        -- Lua error) does not stop the others.
        for _, init in ipairs({ ns.Character.Init, ns.Officers.Init, ns.Profile.Init, ns.Export.Init, ns.KinFolk.Init,
            ns.MyData.Init, ns.Filters.Init, ns.Stats.Init, ns.RosterView.Init, ns.InfoTab.Init }) do
            xpcall(init, geterrorhandler())
        end
    end
end)

-- Slash commands -------------------------------------------------------------

local function PrintHelp()
    ns.Print(L["/bottar status - what the addon knows and is doing"])
    ns.Print(L["/bottar show [name] - the data of a guild member, as the bot gets it"])
    ns.Print(L["/bottar save - write the file for the bot now (reloads the interface)"])
    ns.Print(L["/bottar export on|off - write the file for the bot on this computer"])
    ns.Print(L["/bottar sync - ask the guild for missing data now"])
    ns.Print(L["/bottar language [code|auto] - language of the addon's texts"])
    ns.Print(L["/bottar debug - show the sync log in the chat"])
    ns.Print(L["/bottar reset - forget the data of your current guild"])
end

local function PrintStatus()
    ns.Print(L["version %s. Saved data loaded by the client: %s."], ns.VERSION, ns.loadInfo.native and YES or NO)

    local guildKey = ns.Roster.guildKey
    if not guildKey then
        ns.Print(L["you are not in a guild (or the guild has not loaded yet)."])
    else
        local guild = ns.Data.GetGuild(guildKey)
        local count = 0
        for _ in pairs(guild and guild.members or {}) do
            count = count + 1
        end
        ns.Print(L["guild %s: data on %d |4character:characters; with the addon, %d |4member:members; in the roster."], guildKey, count, ns.Roster.total)
    end

    for _, addonName in ipairs({ ns.Sources.PROFESSIONS, ns.Sources.BUILDS }) do
        if not ns.Sources.Has(addonName) then
            ns.Print(L["%s is turned off or not installed: the file for the bot goes without its data."], ns.Sources.Title(addonName))
        end
    end
    ns.Print(L["sync: %s"], ns.Sync.Describe())
    ns.Print(ns.Export.Describe())
end

SLASH_BOTTARSYNC1 = "/bottar"
SLASH_BOTTARSYNC2 = "/bottarsync"
SlashCmdList.BOTTARSYNC = function(message)
    message = strtrim(message or "")
    local command, rest = message:match("^(%S*)%s*(.-)$")
    local lower = command:lower()
    if lower == "" or lower == "status" then
        PrintStatus()
    elseif lower == "show" then
        ns.Export.Show(rest ~= "" and rest or nil)
    elseif lower == "save" then
        ns.Export.SaveNow()
    elseif lower == "export" then
        local value = rest:lower()
        if value == "on" or value == "off" then
            ns.db.settings.export = value == "on"
        end
        ns.Print(ns.Export.Describe())
    elseif lower == "sync" then
        ns.Sync.SendHello(true)
    elseif lower == "debug" then
        ns.debugEnabled = not ns.debugEnabled
        ns.Print(ns.debugEnabled and L["sync log on."] or L["sync log off."])
    elseif lower == "language" or lower == "lang" then
        -- A language code in any case ("dede" is deDE), or auto.
        local code
        for _, known in ipairs(ns.LOCALES) do
            if known:lower() == rest:lower() then
                code = known
            end
        end
        if not code and rest:lower() ~= "auto" then
            ns.Print(L["languages: %s, or auto for the client's."], table.concat(ns.LOCALES, ", "))
            return
        end
        ns.db.settings.locale = code
        ns.SetLocale(code)
        ns.Print(L["language set to %s."], ns.LOCALE)
    elseif lower == "reset" then
        if rest:lower() ~= "confirm" then
            ns.Print(L["this forgets what you know about your current guild. Type /bottar reset confirm to do it."])
        else
            ns.Data.ResetGuild(ns.Roster.guildKey)
            ns.Print(L["data of your current guild forgotten."])
        end
    else
        PrintHelp()
    end
end
