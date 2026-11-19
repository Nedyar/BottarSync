-- Officers.lua: what the guild master and the officers set about who plays
-- each character. It prevails over what the players say themselves
-- (Profile.lua).
--
-- The officers are the guild master and the members whose rank has the
-- game's "Has officer privileges" (in the guild's rank settings): each
-- client checks the rank of a change's author in the guild roster, and
-- leaves out the changes of anyone else. An officer's changes travel in the
-- record of the character that made them (ov):
--   r = { [username] = { n = new username, t = time } }: renames. The
--       characters whose player's own profile gives that Discord username
--       go by the new one (n == the username itself: they keep it, which
--       undoes an older rename);
--   a = { [GUID] = { d = username, or false for nobody, m = true for a
--       main, t = time } }: whose a character is, and whether it is a main.
--       d is the username as it shows after the renames, and a rename
--       changes it in each of them.
-- The newest of each, among the records of the guild's current officers,
-- holds. Each officer's client keeps all of them in its own record, so they
-- last while any officer is around, also when the one who made them no
-- longer is one.
local _, ns = ...

local Officers = {}
ns.Officers = Officers

-- The game's rank permission "Has officer privileges" (GuildControlUI's
-- OfficerCheckbox).
Officers.FLAG = 22

local rankCache = {} -- [rank index] = whether the rank has it

-- Who is an officer ----------------------------------------------------------------------

-- rankIndex: as the roster gives it, 0 for the guild master.
function Officers.IsOfficerRank(rankIndex)
    if rankIndex == 0 then
        return true
    end
    if type(rankIndex) ~= "number" then
        return false
    end
    local officer = rankCache[rankIndex]
    if officer == nil then
        local flags = C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags
            and ns.Try(C_GuildInfo.GuildControlGetRankFlags, rankIndex + 1)
        officer = ns.CanRead(flags) and ns.Plain(flags[Officers.FLAG]) == true
        rankCache[rankIndex] = officer
    end
    return officer
end

-- Whether a member of the current guild is an officer, by their rank in the
-- roster.
function Officers.IsOfficer(guid)
    local entry = guid and ns.Roster.members[guid]
    return entry ~= nil and Officers.IsOfficerRank(entry.ri)
end

-- Whether the current character is one.
function Officers.AmI()
    return Officers.IsOfficer(ns.playerGUID)
end

-- Checks -----------------------------------------------------------------------------------

-- A checked copy of a record's ov, or nil when it holds nothing (or too
-- much). now is given for records from other clients: what is dated in the
-- future is left out, as it would win over every later change.
function Officers.Clean(ov, now)
    if type(ov) ~= "table" or type(ov.r) ~= "table" or type(ov.a) ~= "table" then
        return nil
    end
    local limits = ns.Pack.LIMITS
    local function Dated(item)
        return type(item) == "table" and LibGuildSync.IsTime(item.t) and not (now and item.t > now + 300)
    end
    local clean, renames, assignments = { r = {}, a = {} }, 0, 0
    for name, item in pairs(ov.r) do
        local from, to = ns.Profile.CleanDiscord(name), Dated(item) and ns.Profile.CleanDiscord(item.n)
        if from and from == name and to then
            renames = renames + 1
            clean.r[from] = { n = to, t = item.t }
        end
    end
    for guid, item in pairs(ov.a) do
        if ns.Data.IsGUID(guid) and Dated(item) then
            local who = false
            if item.d ~= false then
                who = ns.Profile.CleanDiscord(item.d)
            end
            if who ~= nil then
                assignments = assignments + 1
                clean.a[guid] = { d = who, m = who ~= false and item.m == true, t = item.t }
            end
        end
    end
    if renames > limits.renames or assignments > limits.assignments then
        return nil
    end
    if renames + assignments == 0 then
        return nil
    end
    return clean
end

-- What holds -------------------------------------------------------------------------------

-- Whether item a is newer than item b. A tie (two officers in the same
-- second) goes to the one that sorts last, so every client picks the same.
local function Newer(a, b)
    if not b then
        return true
    end
    if a.t ~= b.t then
        return a.t > b.t
    end
    local ka = tostring(a.n or a.d) .. (a.m and "1" or "0")
    local kb = tostring(b.n or b.d) .. (b.m and "1" or "0")
    return ka > kb
end

-- The newest of each change among the officers' records ({ [GUID] = record
-- }): { r = renames, a = assignments }, as in a record's ov. Its items are
-- the records' own: not to be changed.
function Officers.Effective(records)
    local effective = { r = {}, a = {} }
    for guid, record in pairs(records) do
        local ov = type(record) == "table" and record.ov
        if ov and Officers.IsOfficer(guid) then
            for name, item in pairs(ov.r) do
                if Newer(item, effective.r[name]) then
                    effective.r[name] = item
                end
            end
            for target, item in pairs(ov.a) do
                if Newer(item, effective.a[target]) then
                    effective.a[target] = item
                end
            end
        end
    end
    return effective
end

-- The username a player's own profile name shows as.
function Officers.Rename(effective, name)
    local item = name and effective.r[name]
    return item and item.n or name
end

-- The usernames the officers have set something about: { [username] = true }.
function Officers.Managed(effective)
    local managed = {}
    for name, item in pairs(effective.r) do
        if item.n ~= name then
            managed[item.n] = true
        end
    end
    for _, item in pairs(effective.a) do
        if item.d then
            managed[item.d] = true
        end
    end
    return managed
end

-- The current guild's records, ours included.
local function GuildRecords()
    local guild = ns.Data.CurrentGuild()
    return guild and guild.members or {}
end

function Officers.Current()
    return Officers.Effective(GuildRecords())
end

-- An officer's own copy ---------------------------------------------------------------------

local function Copy(effective)
    local copy = { r = {}, a = {} }
    for name, item in pairs(effective.r) do
        copy.r[name] = { n = item.n, t = item.t }
    end
    for guid, item in pairs(effective.a) do
        copy.a[guid] = { d = item.d, m = item.m, t = item.t }
    end
    return copy
end

local function Count(map)
    local count = 0
    for _ in pairs(map) do
        count = count + 1
    end
    return count
end

-- Shares our record with what changed in it.
local function Touch(record)
    if ns.Character.ready and ns.Data.IsShareable(record) then
        ns.Data.TouchOwn(record, "officers")
    end
    ns.Fire("OfficersChanged")
end

-- Keeps in our record every officer's changes, while we are one.
function Officers.Merge()
    if not Officers.AmI() then
        return
    end
    local record = ns.Data.GetOwnRecord(true)
    if not record then
        return
    end
    local copy = Copy(Officers.Current())
    if next(copy.r) == nil and next(copy.a) == nil then
        copy = nil
    end
    if not ns.Same(record.ov, copy) then
        record.ov = copy
        Touch(record)
    end
end

-- Our record, holding every officer's changes, to change it; and the
-- changes that hold now. nil when we are not an officer.
local function Writable()
    if not Officers.AmI() then
        return nil
    end
    local record = ns.Data.GetOwnRecord(true)
    if not record then
        return nil
    end
    local effective = Officers.Current()
    record.ov = Copy(effective)
    return record, effective
end

-- A time newer than the change it replaces.
local function Stamp(previous)
    return math.max(ns.Now(), previous and previous.t + 1 or 0)
end

-- Whether the changes fit in a record; when there are too many characters,
-- those no longer in the guild are left out first.
local function Fits(ov)
    if Count(ov.a) > ns.Pack.LIMITS.assignments and ns.Roster.ready then
        for guid in pairs(ov.a) do
            if not ns.Roster.members[guid] then
                ov.a[guid] = nil
            end
        end
    end
    return Count(ov.a) <= ns.Pack.LIMITS.assignments and Count(ov.r) <= ns.Pack.LIMITS.renames
end

-- Changes ---------------------------------------------------------------------------------------

-- Sets whose a character is (a username, or false for nobody) and whether it
-- is a main. Returns true, or false and why ("full").
function Officers.Assign(guid, name, main)
    local record, effective = Writable()
    if not record or not ns.Data.IsGUID(guid) then
        return false
    end
    record.ov.a[guid] = { d = name or false, m = name and main == true or false, t = Stamp(effective.a[guid]) }
    if not Fits(record.ov) then
        record.ov = Copy(effective)
        return false, "full"
    end
    Touch(record)
    return true
end

-- Changes the username of a player, as it shows (from), to another (to):
-- the profiles that show as from show as to, and so do the characters set
-- to from. With a username another player has, the two become one.
function Officers.RenamePlayer(from, to)
    local record, effective = Writable()
    if not record or from == to then
        return false
    end
    local ov = record.ov
    -- The players' own names that show as from, from itself included
    -- unless it shows as another.
    local names = {}
    for name, item in pairs(effective.r) do
        if item.n == from then
            names[name] = true
        end
    end
    if not effective.r[from] then
        names[from] = true
    end
    for name in pairs(names) do
        ov.r[name] = { n = to, t = Stamp(effective.r[name]) }
    end
    for guid, item in pairs(effective.a) do
        if item.d == from then
            ov.a[guid] = { d = to, m = item.m, t = Stamp(item) }
        end
    end
    if not Fits(ov) then
        record.ov = Copy(effective)
        return false, "full"
    end
    Touch(record)
    return true
end

-- Startup ------------------------------------------------------------------------------------------

local function Forget()
    wipe(rankCache)
end

function Officers.Init()
    local events = CreateFrame("Frame")
    ns.RegisterEvents(events, "GUILD_RANKS_UPDATE")
    events:SetScript("OnEvent", function()
        Forget()
        ns.Fire("OfficersChanged")
        ns.Debounce("OfficersMerge", 2, Officers.Merge)
    end)
    ns.On("RosterUpdated", function()
        Forget()
        ns.Debounce("OfficersMerge", 2, Officers.Merge)
    end)
    ns.On("GuildChanged", Forget)
    ns.On("RecordChanged", function(guid, record)
        if guid ~= ns.playerGUID and type(record) == "table" and record.ov then
            ns.Fire("OfficersChanged")
            ns.Debounce("OfficersMerge", 2, Officers.Merge)
        end
    end)
    ns.Debounce("OfficersMerge", 2, Officers.Merge)
end
