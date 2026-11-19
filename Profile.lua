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
--
-- Officers: what the guild master and the officers set (Officers.lua)
-- prevails over all of this. A rename changes the username a player's
-- profiles show as; a character they set to a player is that player's, a
-- main or an alt as they say, and not pending; one they set to nobody is
-- nobody's. The player cannot change what they set: their username once
-- the officers set anything about them, and those characters. A character
-- set to a player goes by that player's profile on its own (as if it had
-- accepted), so it is not asked for a username.
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
-- a player added that goes by no profile, set = true for one an officer
-- set } }, for each character that goes by a profile, that a player added
-- or that an officer set to a player (it may have no record). effective:
-- what the officers set (Officers.Effective of the same records), when the
-- caller has it.
function Profile.Resolve(records, effective)
    effective = effective or ns.Officers.Effective(records)
    local Rename = ns.Officers.Rename
    local newest, newestGUID = NewestProfiles(records)
    -- Each character's Discord username, and each player's profiles.
    local result, profiles = {}, {}
    for guid, record in pairs(records) do
        local profile = record.ak and newest[record.ak]
        if profile then
            local dc = Rename(effective, profile.dc)
            result[guid] = { dc = dc, main = false }
            profiles[dc] = profiles[dc] or {}
            profiles[dc][guid] = record
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
        result[guid] = { dc = Rename(effective, record.dc), main = record.ch[guid] == true, pending = true }
    end
    -- What the officers set prevails.
    for guid, item in pairs(effective.a) do
        result[guid] = item.d and { dc = item.d, main = item.m, set = true } or nil
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

-- Views -----------------------------------------------------------------------------------
--
-- The My data window (MyData.lua) shows one player at a time, a view: nil
-- for the current character's player, { dc = username } for another player
-- (an officer's), or { guid = GUID } for a character that is nobody's, to
-- give it a player (an officer's).

-- What the views look at: { records, effective (what the officers set),
-- who (Resolve), officer (we are one), myName (the username the current
-- character's player shows as), mine (the profile the character goes by is
-- that player's, so the player's own changes go into it) }.
local function Context()
    local records = GuildRecords()
    local effective = ns.Officers.Effective(records)
    local who = Profile.Resolve(records, effective)
    local own = Profile.Own()
    local context = { records = records, effective = effective, who = who, officer = ns.Officers.AmI() }
    local ownName = ns.Officers.Rename(effective, own.dc)
    local current = who[ns.playerGUID]
    if current and not current.pending then
        context.myName = current.dc
    else
        context.myName = ownName
    end
    context.mine = own.key ~= nil and ownName == context.myName
    return context
end

local function NewItem(context, guid, state, main)
    local record, entry = context.records[guid], ns.Roster.members[guid]
    if not (record or entry) then
        return nil
    end
    return {
        guid = guid, name = (entry and entry.n) or (record and record.n) or guid,
        level = math.max(record and record.l or 0, entry and entry.l or 0), class = ClassFileOf(record, entry),
        main = main, own = guid == ns.playerGUID, state = state,
    }
end

-- Mains first, then by level, then by name.
local function SortItems(list)
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
end

-- The characters of a view's player (name: their username, nil without
-- one) in the current guild: { guid, name, level, class (file), main, own
-- (the current one), state, set }. state: "mine" (theirs), "pending"
-- (added, and it goes by no profile yet) or "other" (in the player's own
-- list but another player's; only in their own view). set: an officer set
-- it. Ours is always in our own view.
local function Characters(context, view, name)
    local list, seen = {}, {}
    local function Add(guid, state, main)
        if seen[guid] then
            return
        end
        local item = NewItem(context, guid, state, main)
        if item then
            seen[guid] = true
            item.set = state ~= "other" and context.effective.a[guid] ~= nil
            list[#list + 1] = item
        end
    end
    if view and view.guid then
        Add(view.guid, "mine", true)
        return list
    end
    local who = context.who
    if not view then
        local current = who[ns.playerGUID]
        if current and not current.pending then
            Add(ns.playerGUID, "mine", current.main)
        else
            Add(ns.playerGUID, "mine", Profile.Own().ch[ns.playerGUID] == true)
        end
    end
    if name then
        for guid, resolved in pairs(who) do
            if resolved.dc == name then
                Add(guid, resolved.pending and "pending" or "mine", resolved.main)
            end
        end
    end
    -- The ones in the player's own lists that are another player's: ours,
    -- and the newest of each of their profiles (older copies may name
    -- characters taken out since).
    if not view and name and context.mine then
        local profile = Profile.Own()
        local lists = { profile.ch }
        for key, record in pairs((NewestProfiles(context.records))) do
            if key ~= profile.key and record.ch and ns.Officers.Rename(context.effective, record.dc) == name then
                lists[#lists + 1] = record.ch
            end
        end
        for _, ch in ipairs(lists) do
            for guid in pairs(ch) do
                local resolved = who[guid]
                if resolved and resolved.dc ~= name then
                    Add(guid, "other", false)
                elseif not resolved and not context.effective.a[guid] and ch == profile.ch then
                    -- Not shared yet.
                    Add(guid, "pending", ch[guid] == true)
                end
            end
        end
    end
    SortItems(list)
    return list
end

-- What the window shows for a view: { name = the player's username (nil
-- while they have none), items = their characters (see Characters, each
-- with canMain: its box can be ticked, and canRemove: it can be taken
-- out), officer = we are one, canName = the username can be changed,
-- canAdd = characters can be added }. A player changes their own view but
-- what the officers set; an officer changes any.
function Profile.View(view)
    local context = Context()
    local name
    if view then
        name = view.dc
    else
        name = context.myName
    end
    local result = { name = name, officer = context.officer, items = Characters(context, view, name) }
    local own = Profile.Own()
    if view then
        result.canName = context.officer
        result.canAdd = context.officer and name ~= nil
    else
        local managed = name and ns.Officers.Managed(context.effective)[name]
        result.canName = context.officer or not own.key or (context.mine and not managed)
        result.canAdd = name ~= nil and (context.mine or context.officer)
    end
    for _, item in ipairs(result.items) do
        local free = context.officer or not item.set
        item.canMain = result.canAdd and item.state ~= "other" and free
        item.canRemove = result.canAdd and free and (view ~= nil or item.state ~= "mine")
    end
    return result
end

-- The player's characters in the current guild, as their own view lists
-- them.
function Profile.MyCharacters()
    return Profile.View(nil).items
end

-- Whether a character is set to someone else than a view's player (name),
-- or to nobody, by an officer, or goes by another player's profile.
local function Taken(context, guid, name)
    local resolved = context.who[guid]
    return context.effective.a[guid] ~= nil or (resolved ~= nil and not resolved.pending and resolved.dc ~= name)
end

-- The guild's characters that can be added to a view's player: in the
-- roster and not theirs yet; for a player, only those no officer set and
-- that go by no other player's profile. { guid, name, level, class, owner
-- (for an officer: the username of the player it is now, if any) } by
-- name.
function Profile.Addable(view)
    local context = Context()
    local name = view and view.dc or context.myName
    local listed = {}
    for _, item in ipairs(Characters(context, view, name)) do
        listed[item.guid] = true
    end
    local list = {}
    for guid, entry in pairs(ns.Roster.members) do
        if not listed[guid] and (context.officer or not Taken(context, guid, name)) then
            local resolved = context.who[guid]
            list[#list + 1] = {
                guid = guid, name = entry.n or guid, level = entry.l or 0, class = entry.c,
                owner = context.officer and resolved and resolved.dc or nil,
            }
        end
    end
    table.sort(list, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    return list
end

-- The guild's players, for an officer's search: { [username] = how many of
-- their characters are in the roster }, and who plays each character (see
-- Resolve).
function Profile.Players()
    local context = Context()
    local players = {}
    for guid, resolved in pairs(context.who) do
        if ns.Roster.members[guid] then
            players[resolved.dc] = (players[resolved.dc] or 0) + 1
        end
    end
    return players, context.who
end

-- Changes ------------------------------------------------------------------------------

-- How a change to a character in a view goes: "profile" (into the profile
-- the current character goes by), "officer" (an officer's, Officers.lua),
-- or nil (not allowed).
local function Way(context, view, guid)
    if view then
        return context.officer and "officer" or nil
    end
    local resolved = context.who[guid]
    local setHere = context.effective.a[guid] ~= nil and (resolved == nil or resolved.dc == context.myName)
    if context.mine and not setHere then
        return "profile"
    end
    return context.officer and "officer" or nil
end

-- The current character's own list as the window shows it, so the profile
-- that is now the newest of the player agrees with it.
local function Snapshot(context)
    local ch, count = {}, 0
    for _, item in ipairs(Characters(context, nil, context.myName)) do
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

-- Sets the Discord username of a view's player (a cleaned one). Returns
-- the view to show then (the player's new username, for another player's).
-- In our own view it goes into the profile the character goes by: the
-- first time, the account gets its key, and the current character is its
-- first main. An officer renames the player instead once the officers set
-- something about them.
function Profile.SetDiscord(name, view)
    local context = Context()
    if view and view.guid then
        if context.officer and ns.Officers.Assign(view.guid, name, true) then
            return { dc = name }
        end
        return view
    end
    local current = view and view.dc or context.myName
    local profile = Profile.Own()
    local managed = current and ns.Officers.Managed(context.effective)[current]
    if not view and (not profile.key or (context.mine and not managed)) then
        if not profile.key then
            profile = Profile.Account()
            profile.key = Profile.NewKey()
            profile.ch = { [ns.playerGUID] = true }
        end
        profile.dc = name
        profile.pt = math.max(ns.Now(), (profile.pt or 0) + 1)
        Profile.Publish()
        return nil
    end
    if context.officer and current and ns.Officers.RenamePlayer(current, name) then
        return view and { dc = name } or nil
    end
    return view
end

-- Marks a character of a view's player as a main or an alt.
function Profile.SetMain(guid, main, view)
    local context = Context()
    local way = Way(context, view, guid)
    if way == "officer" then
        local name = view and view.dc or context.myName
        return name ~= nil and ns.Officers.Assign(guid, name, main) or false
    elseif way == "profile" then
        local ch = Snapshot(context)
        ch[guid] = main == true
        SaveList(ch)
        return true
    end
    return false
end

-- Adds a character of the guild to a view's player, as an alt. Returns
-- true, or false and why ("full": the list holds as many as it can).
function Profile.Add(guid, view)
    if not ns.Data.IsGUID(guid) then
        return false
    end
    local context = Context()
    local name = view and view.dc or context.myName
    if not name then
        return false
    end
    local taken = Taken(context, guid, name)
    if not view and not taken and context.mine then
        local ch, count = Snapshot(context)
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
    if context.officer then
        return ns.Officers.Assign(guid, name, false)
    end
    return false
end

-- Takes a character out of a view's player's list: in our own view one we
-- added that is not ours (pending, or another player's); for an officer,
-- any (it is then nobody's).
function Profile.Remove(guid, view)
    local context = Context()
    local way = Way(context, view, guid)
    if way == "officer" then
        return ns.Officers.Assign(guid, false)
    elseif way == "profile" then
        local ch = Snapshot(context)
        if ch[guid] == nil then
            return false
        end
        ch[guid] = nil
        SaveList(ch)
        return true
    end
    return false
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
-- it goes by none: the record that carries it, or nil. None once an
-- officer set whose it is.
function Profile.ClaimOnMe()
    local records = GuildRecords()
    if ns.Officers.Effective(records).a[ns.playerGUID] then
        return nil
    end
    local newest, newestGUID = NewestProfiles(records)
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

-- A character an officer set to a player goes by that player's profile, as
-- if it had accepted: the newest that shows as their username, or else a
-- new one of its own with it. Only that character, not its account.
function Profile.FollowOfficers()
    if not ns.Roster.guildKey then
        return
    end
    local records = GuildRecords()
    local effective = ns.Officers.Effective(records)
    local item = effective.a[ns.playerGUID]
    local own = Profile.Own()
    if not (item and item.d) or (own.key and ns.Officers.Rename(effective, own.dc) == item.d) then
        return
    end
    local newest, newestGUID = NewestProfiles(records)
    local best, bestGUID
    for key, record in pairs(newest) do
        local guid = newestGUID[key]
        if ns.Officers.Rename(effective, record.dc) == item.d and Newer(guid, record, bestGUID, best) then
            best, bestGUID = record, guid
        end
    end
    if best then
        ns.Debug("going by %s's profile, as an officer set", item.d)
        Profile.AcceptClaim(best)
    elseif ns.Officers.Rename(effective, item.d) == item.d then
        ns.Debug("a profile of %s, as an officer set", item.d)
        ns.Data.OwnState().profile = {
            key = Profile.NewKey(), dc = item.d, pt = ns.Now(), ch = { [ns.playerGUID] = item.m == true },
        }
        Profile.Publish()
    end
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
        Profile.FollowOfficers()
        -- Nor is it asked once an officer set whose it is.
        if Profile.HasName() or not ns.Roster.guildKey or ns.Officers.Current().a[ns.playerGUID] then
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
    -- An officer set whose the character is: once the guild had time to
    -- send its records (until then the prompt's timer looks).
    ns.On("OfficersChanged", function()
        if not promptTimer then
            ns.Debounce("FollowOfficers", 5, Profile.FollowOfficers)
        end
    end)
end
