-- language_catalog.lua
-- Rulebook language metadata and normalization helpers.

local M = {}

M.COMMON_CITY_LANGUAGES = {
    "vulgaris",
    "cant",
    "chivalric",
    "tylwyth",
    "vetus",
}

M.LANGUAGES = {
    vulgaris = {
        id = "vulgaris",
        name = "Vulgaris",
        commonCity = true,
        role = "common_tongue",
        description = "The most common language spoken by humans, underfolk, and orcs in the Wide World.",
        derivedFrom = { "ancient_mannish", "vetus", "tylwyth" },
    },
    cant = {
        id = "cant",
        name = "Cant",
        commonCity = true,
        role = "lowborn_thieves",
        description = "The lowborn language of thieves, scoundrels, rogues, and ne'er-do-wells.",
        derivedFrom = { "vulgaris" },
        unintelligibleWithoutProficiency = true,
    },
    chivalric = {
        id = "chivalric",
        name = "Chivalric",
        commonCity = true,
        role = "nobility_law_court",
        description = "The language of nobles, legal proceedings, and courtly proceedings.",
        derivedFrom = { "vulgaris" },
        unintelligibleWithoutProficiency = true,
    },
    tylwyth = {
        id = "tylwyth",
        name = "Tylwyth",
        commonCity = true,
        role = "fay_spirit",
        description = "The ancestral language of the fay, spirits, and many minor divinities.",
        speakers = { "fay", "spirits", "minor_divinities" },
    },
    vetus = {
        id = "vetus",
        name = "Vetus",
        commonCity = true,
        role = "cult_scholarly",
        description = "The official language of the Cult of Mythrys and most scholarly writing.",
        writingSystem = "right_to_left_abjad",
        onlyWrittenLanguageInCity = true,
    },
    ancient_tongue = {
        id = "ancient_tongue",
        name = "Ancient Tongue",
        commonCity = false,
        ancient = true,
        role = "historical",
        description = "A historical mode of speech with few remaining texts and almost no native speakers.",
    },
    ancient_mannish = {
        id = "ancient_mannish",
        name = "Ancient Mannish",
        commonCity = false,
        ancient = true,
        role = "historical",
        description = "One of the historical roots of Vulgaris.",
    },
}

local ALIASES = {
    common = "vulgaris",
    common_tongue = "vulgaris",
    vulgar = "vulgaris",
    thieves_cant = "cant",
    thief_cant = "cant",
    lowborn = "cant",
    noble = "chivalric",
    courtly = "chivalric",
    law = "chivalric",
    legal = "chivalric",
    fay = "tylwyth",
    fae = "tylwyth",
    fairy = "tylwyth",
    spirit = "tylwyth",
    cult = "vetus",
    mythrys = "vetus",
    scholarly = "vetus",
    ancient = "ancient_tongue",
    ancient_language = "ancient_tongue",
    ancient_languages = "ancient_tongue",
    ancient_mannish = "ancient_mannish",
}

local function copyLanguage(info)
    if not info then
        return nil
    end
    local copy = {}
    for key, value in pairs(info) do
        if type(value) == "table" then
            local list = {}
            for i, item in ipairs(value) do
                list[i] = item
            end
            copy[key] = list
        else
            copy[key] = value
        end
    end
    return copy
end

function M.normalizeLanguage(value)
    if type(value) ~= "string" then
        return nil
    end
    local normalized = value:lower()
    normalized = normalized:gsub("[’']", "")
    normalized = normalized:gsub("^%s+", ""):gsub("%s+$", "")
    normalized = normalized:gsub("[^%w]+", "_")
    normalized = normalized:gsub("^_+", ""):gsub("_+$", "")
    if normalized == "" then
        return nil
    end
    return ALIASES[normalized] or normalized
end

function M.getLanguage(value)
    local id = M.normalizeLanguage(value)
    return copyLanguage(id and M.LANGUAGES[id] or nil)
end

function M.isCommonCityLanguage(value)
    local info = M.getLanguage(value)
    return info and info.commonCity == true or false
end

function M.validateStartingLanguages(languages, opts)
    opts = opts or {}
    if not languages or #languages == 0 then
        if opts.required then
            return false, "Choose two languages"
        end
        return true, "languages_optional", {
            languages = {},
            languageInfo = {},
            trackingEnabled = false,
        }
    end
    if #languages ~= 2 then
        return false, "Choose two languages"
    end

    local normalized = {}
    local infoById = {}
    local seen = {}
    for index, language in ipairs(languages) do
        local id = M.normalizeLanguage(language)
        if not id then
            return false, "Choose two languages"
        end
        if seen[id] then
            return false, "Choose two distinct languages"
        end
        local info = M.getLanguage(id) or {
            id = id,
            name = tostring(language),
            commonCity = false,
            uncommon = true,
        }
        if opts.strictCommonCity == true and info.commonCity ~= true then
            return false, "Choose languages from the rulebook list"
        end
        seen[id] = true
        normalized[index] = id
        infoById[id] = info
    end

    return true, "languages_selected", {
        languages = normalized,
        languageInfo = infoById,
        trackingEnabled = true,
    }
end

return M
