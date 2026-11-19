-- Profile.lua: who plays each character, for Bot'tar: the player's Discord
-- username and which of their characters are mains and which alts. A
-- player may have several mains.
--
-- A profile is a key of its own, made up the first time (ak), the Discord
-- username (dc), the time of its last change (pt) and the player's list of
-- characters (ch = { [GUID] = true for a main, false for an alt }). A WoW
-- account keeps one (BottarSyncDB.account, saved for the whole account),
-- which its characters go by. A character that accepted to be another
-- player's (see Claims below) goes by that player's profile instead
-- (BottarSyncDB.own[GUID].profile): only that character, not the rest of
-- its account. Every character carries the profile it goes by in the
-- record it shares, so a change made on any character of a player reaches
-- the guild at once, and the player's other characters follow it although
-- they are offline:
--   - a character's Discord username is the one of the newest profile with
--     its key;
--   - a character is a main when the newest list of its player (the
--     profiles that go by the same username) that names it says so, and an
--     alt otherwise. So a player sees and sets all their characters from
--     any of them.
--
-- Claims: a player may add to their list any character of the guild that
-- is not theirs yet. A character that goes by no profile (it never gave a
-- username, or has no Bot'tar Sync) counts as theirs at once, pending, as
-- the newest list that names it says (main or alt). When it logs in without
-- a username, it is asked whether it is that player's: accepting makes it
-- go by their profile; rejecting asks for its own username. A character
-- that goes by another player's profile stays theirs: the list shows it as
-- another player's, and it does not count.
--
-- Only a record's owner ever changes it (LibGuildSync's Store.lua), so no
-- one can put a character under their name without that character.
local _, ns = ...

local Profile = {}
ns.Profile = Profile

Profile.DISCORD_MIN = 2
Profile.DISCORD_MAX = 32
Profile.KEY_LENGTH = 12
-- Seconds after logging in (or joining the guild) before asking for the
-- Discord username: time for the guild to send its records.
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

-- A checked copy of a saved profile ({ key, dc, pt, ch }), or nil.
function Profile.CleanProfile(profile)
    if type(profile) ~= "table" then
        return nil
    end
    local key, discord = Profile.CleanKey(profile.key), Profile.CleanDiscord(profile.dc)
    local ch = Profile.CleanCharacters(profile.ch, ns.Pack.LIMITS.profile)
    if key and discord and ch and LibGuildSync.IsTime(profile.pt) then
        return { key = key, dc = discord, pt = profile.pt, ch = ch }
    end
end

local function Copy(ch)
    local copy = {}
    for guid, main in pairs(ch) do
        copy[guid] = main
    end
    return copy
end

-- The profiles kept ------------------------------------------------------------------

-- BottarSyncDB.account: { key, dc, pt, ch }, all nil but ch until a
-- character of the account gives a Discord username (Data.SanitizeExtra
-- checks it when loading).
function Profile.Account()
    return ns.db.account
end

-- The profile the current character goes by: the one of the player it
-- accepted to be, or its account's.
function Profile.Own()
    return ns.Data.OwnState().profile or Profile.Account()
end

function Profile.HasName()
    return Profile.Own().dc ~= nil
end

-- Puts the profile the character goes by in our own record. Returns true
-- when the record changed (the caller stamps it).
function Profile.ApplyOwn(record)
    local profile = Profile.Own()
    local values = { ak = profile.key, dc = profile.dc, pt = profile.key and profile.pt or nil }
    local changed = false
    for _, key in ipairs({ "ak", "dc", "pt" }) do
        if record[key] ~= values[key] then
            record[key] = values[key]
            changed = true
        end
    end
    local ch = profile.key and Copy(profile.ch) or nil
    if not ns.Same(record.ch, ch) then
        record.ch = ch
        changed = true
    end
    return changed
end

-- Shares the profile at once, in our own record.
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

-- Each key's newest profile: { [key] = record }, { [key] = its GUID }.
local function NewestProfiles(records)
    local newest, newestGUID = {}, {}
    for guid, record in pairs(records) do
        local key = record.ak
        if key and record.dc and Newer(guid, record, newestGUID[key], newest[key]) then
            newest[key], newestGUID[key] = record, guid
        end
    end
    return newest, newestGUID
end

-- For a guild's records ({ [GUID] = Bot'tar Sync record }): { [GUID] = {
-- dc = Discord username, main = true/false, pending = true for a character
-- a player added that goes by no profile } }, for each character that goes
-- by a profile or that a player added (it may have no record).
function Profile.Resolve(records)
    local newest, newestGUID = NewestProfiles(records)
    -- Each character's Discord username, and each player's profiles.
    local result, profiles = {}, {}
    for guid, record in pairs(records) do
        local profile = record.ak and newest[record.ak]
        if profile then
            result[guid] = { dc = profile.dc, main = false }
            profiles[profile.dc] = profiles[profile.dc] or {}
            profiles[profile.dc][guid] = record
        end
    end
    -- Mains: the newest of the player's profiles that names the character.
    for guid, who in pairs(result) do
        local best, bestGUID
        for otherGUID, record in pairs(profiles[who.dc]) do
            if record.ch and record.ch[guid] ~= nil and Newer(otherGUID, record, bestGUID, best) then
                best, bestGUID = record, otherGUID
            end
        end
        who.main = best ~= nil and best.ch[guid] == true
    end
    -- Characters added by players that go by no profile: the newest list
    -- that names them.
    local claims, claimGUID = {}, {}
    for key, record in pairs(newest) do
        for guid in pairs(record.ch or {}) do
            if not result[guid] and Newer(newestGUID[key], record, claimGUID[guid], claims[guid]) then
                claims[guid], claimGUID[guid] = record, newestGUID[key]
            end
        end
    end
    for guid, record in pairs(claims) do
        result[guid] = { dc = record.dc, main = record.ch[guid] == true, pending = true }
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

local function ClassFileOf(record, entry)
    if entry and type(entry.c) == "string" then
        return entry.c
    end
    local classID = record and record.c
    if classID and classID ~= 0 and C_CreatureInfo then
        local info = ns.Try(C_CreatureInfo.GetClassInfo, classID)
        return ns.CanRead(info) and info.classFile or nil
    end
end

-- The player's characters in the current guild, as the window lists them:
-- { guid, name, level, class (file), main, own (the current one), state }.
-- state: "mine" (it goes by the player's profile), "pending" (added, and
-- it goes by none yet) or "other" (added, but another player's). Ours is
-- always among them. Mains first, then by level, then by name.
function Profile.MyCharacters()
    local profile = Profile.Own()
    local records = GuildRecords()
    local roster = ns.Roster.members
    local who = Profile.Resolve(records)
    local list, seen = {}, {}
    local function Add(guid, state, main)
        local record, entry = records[guid], roster[guid]
        if seen[guid] or not (record or entry) then
            return
        end
        seen[guid] = true
        local level = math.max(record and record.l or 0, entry and entry.l or 0)
        list[#list + 1] = {
            guid = guid, name = (entry and entry.n) or (record and record.n) or guid, level = level,
            class = ClassFileOf(record, entry), main = main, own = guid == ns.playerGUID, state = state,
        }
    end
    -- The characters that go by the player's profiles.
    for guid, record in pairs(records) do
        local resolved = who[guid]
        local mine = guid == ns.playerGUID
            or (profile.key and record.ak == profile.key)
            or (profile.dc and resolved and not resolved.pending and resolved.dc == profile.dc)
        if mine then
            local main
            if resolved and not resolved.pending then
                main = resolved.main
            else
                main = profile.ch[guid] == true
            end
            Add(guid, "mine", main)
        end
    end
    -- The ones the player added, in any of their lists: ours, and the
    -- newest of each of their profiles (older copies may name characters
    -- taken out since).
    if profile.dc then
        local lists = { profile.ch }
        for key, record in pairs((NewestProfiles(records))) do
            if key ~= profile.key and record.dc == profile.dc and record.ch then
                lists[#lists + 1] = record.ch
            end
        end
        for _, ch in ipairs(lists) do
            for guid in pairs(ch) do
                local resolved = who[guid]
                if resolved and resolved.dc == profile.dc then
                    Add(guid, "pending", resolved.main)
                elseif resolved then
                    Add(guid, "other", false)
                elseif ch == profile.ch then
                    -- Not shared yet.
                    Add(guid, "pending", ch[guid] == true)
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.main ~= b.main then
            return a.main
        end
        if a.level ~= b.level then
            return a.level > b.level
        end
        local na, nb = a.name:lower(), b.name:lower()
        if na ~= nb then
            return na < nb
        end
        return a.guid < b.guid
    end)
    return list
end

-- The guild's characters that can be added to the player's list: in the
-- roster, not in the list, and going by no other player's profile.
-- { guid, name, level, class } by name.
function Profile.Addable()
    local profile = Profile.Own()
    local mine = {}
    for _, item in ipairs(Profile.MyCharacters()) do
        mine[item.guid] = true
    end
    local who = Profile.Resolve(GuildRecords())
    local list = {}
    for guid, entry in pairs(ns.Roster.members) do
        local resolved = who[guid]
        local owned = resolved and not resolved.pending and resolved.dc ~= profile.dc
        if not mine[guid] and not owned then
            list[#list + 1] = { guid = guid, name = entry.n or guid, level = entry.l or 0, class = entry.c }
        end
    end
    table.sort(list, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    return list
end

-- Changes ------------------------------------------------------------------------------

-- Sets the Discord username of the profile the character goes by (a
-- cleaned one). The first time, the account gets its key, and the current
-- character is its first main.
function Profile.SetDiscord(name)
    local profile = Profile.Own()
    if not profile.key then
        profile = Profile.Account()
        profile.key = Profile.NewKey()
        profile.ch = { [ns.playerGUID] = true }
    end
    profile.dc = name
    profile.pt = math.max(ns.Now(), (profile.pt or 0) + 1)
    Profile.Publish()
end

-- The list as the window shows it, so the profile that is now the newest
-- of the player agrees with it.
local function Snapshot()
    local ch, count = {}, 0
    for _, item in ipairs(Profile.MyCharacters()) do
        ch[item.guid] = item.main
        count = count + 1
    end
    return ch, count
end

local function SaveList(ch)
    local profile = Profile.Own()
    profile.ch = ch
    profile.pt = math.max(ns.Now(), (profile.pt or 0) + 1)
    Profile.Publish()
end

-- Marks one of the player's characters as a main or an alt.
function Profile.SetMain(guid, main)
    if not Profile.Own().key then
        return
    end
    local ch = Snapshot()
    ch[guid] = main == true
    SaveList(ch)
end

-- Adds a character of the guild to the player's list, as an alt. Returns
-- true, or false and why ("full": the list holds as many as it can).
function Profile.Add(guid)
    if not Profile.Own().key or not ns.Data.IsGUID(guid) then
        return false
    end
    local ch, count = Snapshot()
    if ch[guid] ~= nil then
        return false
    end
    if count >= ns.Pack.LIMITS.profile then
        return false, "full"
    end
    ch[guid] = false
    SaveList(ch)
    return true
end

-- Takes out of the list a character the player added that is not theirs
-- (pending, or another player's).
function Profile.Remove(guid)
    if not Profile.Own().key then
        return false
    end
    local ch = Snapshot()
    if ch[guid] == nil then
        return false
    end
    ch[guid] = nil
    SaveList(ch)
    return true
end

-- Profiles from the guild -------------------------------------------------------------

-- Takes a newer copy of a profile we keep (the account's, or the one of the
-- player this character accepted to be), changed by another character of
-- the player. Returns true when it took it.
function Profile.Adopt(guid, record)
    if guid == ns.playerGUID or not (record and record.ak and record.dc and record.ch) then
        return false
    end
    local taken = false
    for _, profile in ipairs({ Profile.Account(), ns.Data.OwnState().profile or {} }) do
        if profile.key and record.ak == profile.key and record.pt > (profile.pt or 0) then
            profile.dc, profile.pt, profile.ch = record.dc, record.pt, Copy(record.ch)
            taken = true
        end
    end
    if taken then
        ns.Debug("profile taken from %s", tostring(record.n or guid))
        Profile.Publish()
    end
    return taken
end

-- Claims on the current character ----------------------------------------------------

-- The newest profile of the guild that names the current character, while
-- it goes by none: the record that carries it, or nil.
function Profile.ClaimOnMe()
    local newest, newestGUID = NewestProfiles(GuildRecords())
    local best, bestGUID
    for key, record in pairs(newest) do
        local guid = newestGUID[key]
        if guid ~= ns.playerGUID and record.ch and record.ch[ns.playerGUID] ~= nil and Newer(guid, record, bestGUID, best) then
            best, bestGUID = record, guid
        end
    end
    return best
end

-- The current character accepts to be the player of a claim (a record):
-- it goes by their profile from now on, the rest of its account does not.
function Profile.AcceptClaim(record)
    ns.Data.OwnState().profile = { key = record.ak, dc = record.dc, pt = record.pt, ch = Copy(record.ch) }
    Profile.Publish()
end

-- Asking for the Discord username ------------------------------------------------------------

local promptTimer

-- Asks, in a little while, if the character then goes by no profile and is
-- in a guild: whether it is the player's who added it, or else its own
-- Discord username.
function Profile.SchedulePrompt()
    if promptTimer then
        promptTimer:Cancel()
    end
    promptTimer = C_Timer.NewTimer(Profile.PROMPT_DELAY, function()
        promptTimer = nil
        if Profile.HasName() or not ns.Roster.guildKey then
            return
        end
        local claim = Profile.ClaimOnMe()
        if claim then
            ns.DiscordPrompt.ShowClaim(claim)
        else
            ns.DiscordPrompt.Show()
        end
    end)
end

function Profile.Init()
    ns.On("RecordChanged", function(guid, record)
        Profile.Adopt(guid, record)
        -- A player who lists the character, come while the box asks for
        -- its username: it asks whether it is theirs instead.
        if not Profile.HasName() and record and record.ch and record.ch[ns.playerGUID] ~= nil
            and ns.DiscordPrompt.AsksName() then
            local claim = Profile.ClaimOnMe()
            if claim then
                ns.DiscordPrompt.ShowClaim(claim)
            end
        end
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
