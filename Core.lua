-- Bot'tar Sync: shares every guild member's characters with the guild and
-- writes them, as JSON, into the saved variables file for the Bot'tar bot.
--
-- The addon messages, the guild roster, the saved database and the sync
-- are LibGuildSync's (a separate addon this one depends on), attached
-- below. Core.lua holds the startup and the slash commands.
local ADDON_NAME, ns = ...
local L = ns.L
local Lib = LibGuildSync

ns.ADDON_NAME = ADDON_NAME

Lib.Attach(ns, {
    title = "Bot'tar Sync",
    tag = "BS",
    prefix = "BottarSync",
    protocol = "1",
    savedVariable = "BottarSyncDB",
})

-- Our own character has been read, so what we announce is current.
function ns.Sync.OwnReady()
    return ns.Character.ready and ns.Professions.ready
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
        for _, init in ipairs({ ns.Character.Init, ns.Professions.Init, ns.Talents.Init, ns.Export.Init, ns.KinFolk.Init }) do
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

    local own = ns.Data.GetOwnRecord(false)
    if own then
        local missing = {}
        for _, prof in ipairs(ns.Data.SortedProfessions(own)) do
            if prof.k == nil then
                missing[#missing + 1] = ns.ProfessionName(prof.sl, prof.lk) or ("#" .. prof.sl)
            end
        end
        if #missing > 0 then
            ns.Print(L["recipes not read yet: open %s once."], table.concat(missing, ", "))
        end
        if not own.tl then
            ns.Print(L["talents not read yet."])
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
