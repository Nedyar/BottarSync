-- Locales: the addon's texts in the client's language (GetLocale).
--
-- The English text is the key, so the code reads in English and any text a
-- language file lacks shows in English. Each language file registers its
-- texts with ns.RegisterLocale; esMX starts from esES and only overrides
-- what differs. "/bottar language" can force another language for the
-- addon's own texts (names of professions, recipes and items always come
-- from the client).
--
-- Every client language is translated. The client has no Japanese; enGB
-- uses the English texts and ptPT the Brazilian Portuguese ones. Counts use
-- the game's plural markup, "%d |4recipe:recipes;" (Russian has three forms:
-- "|4one:few:many;").
local _, ns = ...

local CLIENT_LOCALE = ({ enGB = "enUS", ptPT = "ptBR" })[GetLocale()] or GetLocale()
local CHAINS = { esMX = { "esES", "esMX" } }
local fills = {}

ns.CLIENT_LOCALE = CLIENT_LOCALE
ns.LOCALE = CLIENT_LOCALE
ns.LOCALES = { "enUS", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }

ns.L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})

local function Chain(code)
    return CHAINS[code] or { code }
end

function ns.RegisterLocale(code, fill)
    fills[code] = fill
    for _, part in ipairs(Chain(ns.LOCALE)) do
        if part == code then
            fill(ns.L)
        end
    end
end

-- code is nil for the client's language. Texts already on screen keep the
-- old language until they are shown again (or after /reload).
function ns.SetLocale(code)
    code = code or CLIENT_LOCALE
    if code == ns.LOCALE then
        return
    end
    ns.LOCALE = code
    wipe(ns.L)
    for _, part in ipairs(Chain(code)) do
        if fills[part] then
            fills[part](ns.L)
        end
    end
end
