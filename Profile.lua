-- Profile.lua: who plays each character, for Bot'tar: the player's Discord
-- name and which of their characters are mains and which alts. A player may
-- have several mains.
--
-- A WoW account keeps one profile (BottarSyncDB.account, saved for the whole
-- account): a key of its own, made up the first time (ak), the Discord name
-- (dc), the time of its last change (pt) and what it says of the player's
-- characters (ch = { [GUID] = true for a main, false for an alt }). Every
-- character of the account carries the profile in the record it shares, so
-- a change made on one character reaches the guild at once, and the other
-- characters follow it although they are offline:
--   - a character's Discord name is the one of its account's newest profile
--     (the newest among the records with its account's key);
--   - a character is a main when the newest profile of its player (the
--     records whose account goes by the same Discord name) that speaks of it
--     says so, and an alt otherwise. So a player with characters on two WoW
--     accounts sees and sets all of them from either.
-- Only a record's owner ever changes it (LibGuildSync's Store.lua), so no
-- one can put another account's characters under their name: a profile
-- only counts for characters whose own account goes by the same Discord name.
--
-- A member in a guild whose account has no Discord name yet is asked for it
-- (DiscordPrompt.lua) a little after logging in or joining the guild: the
-- guild may still bring back a profile the account had (from another
-- computer, or saved data that was lost), found in the profile of another of
-- its characters that speaks of this one.
local _, ns = ...

local Profile = {}
ns.Profile = Profile

Profile.DISCORD_MIN = 2
Profile.DISCORD_MAX = 32
Profile.KEY_LENGTH = 12
-- Seconds after logging in (or joining the guild) before asking for the
-- Discord name: time for the guild to send back a profile the account had.
Profile.PROMPT_DELAY = 15

local KEY_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"

-- Checks -------------------------------------------------------------------------

-- A Discord username as Discord keeps it (2 to 32 lowercase letters, digits,
-- _ and ., never two dots in a row), from what the player typed: spaces
-- around it and a leading @ are dropped, capitals made small. nil when it
-- cannot be one.
function Profile.CleanDiscord(text)
    if type(text) ~= "string" then
        return nil
    end
    local name = text:match("^%s*@?(.-)%s*$"):lower()
    if #name < Profile.DISCORD_MIN or #name > Profile.DISCORD_MAX or not name:find("^[a-z0-9_.]+$")
        or name:find("..", 1, true) then
        return nil
    end
    return name
end

function Profile.CleanKey(key)
    if type(key) ~= "string" or #key < 8 or #key > 16 or not key:find("^[%w]+$") then
        return nil
    end
    return key
end

function Profile.NewKey()
    local chars = {}
    for i = 1, Profile.KEY_LENGTH do
        local index = math.random(1, #KEY_CHARS)
        chars[i] = KEY_CHARS:sub(index, index)
    end
    return table.concat(chars)
end

-- A checked copy of a profile's characters ({ [GUID] = true/false }), at
-- most limit of them, or nil.
function Profile.CleanCharacters(ch, limit)
    if type(ch) ~= "table" then
        return nil
    end
    local clean, count = {}, 0
    for guid, main in pairs(ch) do
        if ns.Data.IsGUID(guid) and type(main) == "boolean" then
            count = count + 1
            if count > limit then
                return nil
            end
            clean[guid] = main
        end
    end
    return clean
end

-- The account's profile ---------------------------------------------------------------

-- BottarSyncDB.account: { key, dc, pt, ch }, all nil until the player gives
-- a Discord name (Data.SanitizeExtra checks it when loading).
function Profile.Account()
    return ns.db.account
end

function Profile.HasName()
    return Profile.Account().dc ~= nil
end

-- Puts the account's profile in our own record. Returns true when the
-- record changed (the caller stamps it).
function Profile.ApplyOwn(record)
    local account = Profile.Account()
    local values = { ak = account.key, dc = account.dc, pt = account.key and account.pt or nil }
    local changed = false
    for _, key in ipairs({ "ak", "dc", "pt" }) do
        if record[key] ~= values[key] then
            record[key] = values[key]
            changed = true
        end
    end
    local ch
    if account.key then
        ch = {}
        for guid, main in pairs(account.ch) do
            ch[guid] = main
        end
    end
    if not ns.Same(record.ch, ch) then
        record.ch = ch
        changed = true
    end
    return changed
end

-- Shares the account's profile at once, in our own record.
function Profile.Publish()
    local record = ns.Data.GetOwnRecord(true)
    if record and Profile.ApplyOwn(record) and ns.Character.ready and ns.Data.IsShareable(record) then
        ns.Data.TouchOwn(record, "profile")
    end
    ns.Fire("ProfileChanged")
end

-- Who plays each character ------------------------------------------------------------

-- Whether profile a (a record) is newer than profile b; ties go to the lower
-- GUID, so every client picks the same one.
local function Newer(guidA, a, guidB, b)
    if not b then
        return true
    end
    if a.pt ~= b.pt then
        return a.pt > b.pt
    end
    return guidA < guidB
end

-- For a guild's records ({ [GUID] = Bot'tar Sync record }): { [GUID] = {
-- dc = Discord name, main = true/false } } for each character whose account
-- has a profile.
function Profile.Resolve(records)
    -- Each account's newest profile.
    local newest, newestGUID = {}, {}
    for guid, record in pairs(records) do
        local key = record.ak
        if key and record.dc and Newer(guid, record, newestGUID[key], newest[key]) then
            newest[key], newestGUID[key] = record, guid
        end
    end
    -- Each character's Discord name, and each player's profiles.
    local result, profiles = {}, {}
    for guid, record in pairs(records) do
        local profile = record.ak and newest[record.ak]
        if profile then
            result[guid] = { dc = profile.dc, main = false }
            profiles[profile.dc] = profiles[profile.dc] or {}
            profiles[profile.dc][guid] = record
        end
    end
    -- Mains: the newest of the player's profiles that speaks of the character.
    for guid, who in pairs(result) do
        local best, bestGUID
        for otherGUID, record in pairs(profiles[who.dc]) do
            if record.ch and record.ch[guid] ~= nil and Newer(otherGUID, record, bestGUID, best) then
                best, bestGUID = record, otherGUID
            end
        end
        who.main = best ~= nil and best.ch[guid] == true
    end
    return result
end

-- The current guild's Bot'tar Sync records that were shared, ours included.
local function GuildRecords()
    local guild = ns.Data.CurrentGuild()
    local records = {}
    for guid, record in pairs(guild and guild.members or {}) do
        if ns.Data.IsShareable(record) or guid == ns.playerGUID then
            records[guid] = record
        end
    end
    return records
end

-- The player's characters in the current guild, as the window lists them:
-- { guid, record, main }, ours always among them. Mains first, then by
-- level, then by name.
function Profile.MyCharacters()
    local account = Profile.Account()
    local records = GuildRecords()
    local who = Profile.Resolve(records)
    local list = {}
    for guid, record in pairs(records) do
        local mine = guid == ns.playerGUID
            or (account.key and record.ak == account.key)
            or (account.dc and who[guid] and who[guid].dc == account.dc)
        if mine then
            local main
            if who[guid] then
                main = who[guid].main
            else
                main = account.ch[guid] == true
            end
            list[#list + 1] = { guid = guid, record = record, main = main, own = guid == ns.playerGUID }
        end
    end
    table.sort(list, function(a, b)
        if a.main ~= b.main then
            return a.main
        end
        local la, lb = a.record.l or 0, b.record.l or 0
        if la ~= lb then
            return la > lb
        end
        local na, nb = (a.record.n or a.guid):lower(), (b.record.n or b.guid):lower()
        if na ~= nb then
            return na < nb
        end
        return a.guid < b.guid
    end)
    return list
end

-- Changes ------------------------------------------------------------------------------

-- Sets the account's Discord name (a cleaned one). The first time, the
-- account gets its key, and the current character is its first main.
function Profile.SetDiscord(name)
    local account = Profile.Account()
    if not account.key then
        account.key = Profile.NewKey()
        account.ch = { [ns.playerGUID] = true }
    end
    account.dc = name
    account.pt = math.max(ns.Now(), (account.pt or 0) + 1)
    Profile.Publish()
end

-- Marks one of the player's characters as a main or an alt. The profile
-- then says what the window shows of every one of them, so the profile
-- of the player that is now the newest agrees with it.
function Profile.SetMain(guid, main)
    local account = Profile.Account()
    if not account.key then
        return
    end
    local ch = {}
    for _, item in ipairs(Profile.MyCharacters()) do
        ch[item.guid] = item.main
    end
    ch[guid] = main == true
    account.ch = ch
    account.pt = math.max(ns.Now(), (account.pt or 0) + 1)
    Profile.Publish()
end

-- Profiles from the guild -------------------------------------------------------------

-- Takes a profile from the guild into the account: a newer one of the
-- account's own (changed on another computer), or, while the account has
-- none, one of another character that speaks of the current one (the
-- account lost its saved data, or plays on another computer). Returns true
-- when it took it.
function Profile.Adopt(guid, record)
    local account = Profile.Account()
    if guid == ns.playerGUID or not (record and record.ak and record.dc and record.ch) then
        return false
    end
    local take
    if account.key then
        take = record.ak == account.key and record.pt > (account.pt or 0)
    else
        take = record.ch[ns.playerGUID] ~= nil
    end
    if not take then
        return false
    end
    account.key, account.dc, account.pt = record.ak, record.dc, record.pt
    account.ch = {}
    for other, main in pairs(record.ch) do
        account.ch[other] = main
    end
    ns.Debug("profile taken from %s", tostring(record.n or guid))
    Profile.Publish()
    return true
end

-- Asking for the Discord name --------------------------------------------------------------

local promptTimer

-- Asks for the Discord name, in a little while, if the account still has
-- none then and the character is in a guild.
function Profile.SchedulePrompt()
    if promptTimer then
        promptTimer:Cancel()
    end
    promptTimer = C_Timer.NewTimer(Profile.PROMPT_DELAY, function()
        promptTimer = nil
        if Profile.HasName() or not ns.Roster.guildKey then
            return
        end
        -- A profile already known that speaks of this character: the newest.
        local best, bestGUID
        for guid, record in pairs(GuildRecords()) do
            if guid ~= ns.playerGUID and record.ak and record.dc and record.ch and record.ch[ns.playerGUID] ~= nil
                and Newer(guid, record, bestGUID, best) then
                best, bestGUID = record, guid
            end
        end
        if not (best and Profile.Adopt(bestGUID, best)) then
            ns.DiscordPrompt.Show()
        end
    end)
end

function Profile.Init()
    ns.On("RecordChanged", function(guid, record)
        Profile.Adopt(guid, record)
    end)
    -- At login (the guild's name comes a moment later) and on joining a guild.
    ns.On("GuildChanged", function(key)
        if key then
            Profile.SchedulePrompt()
        end
    end)
    if ns.Roster.guildKey then
        Profile.SchedulePrompt()
    end
    ns.On("ProfileChanged", function()
        if Profile.HasName() then
            ns.DiscordPrompt.Hide()
        end
    end)
end
