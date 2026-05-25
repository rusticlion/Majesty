-- motif_catalog.lua
-- Rulebook motif descriptor/profession catalog and parsing helpers.

local M = {}

M.DESCRIPTORS = {
    "apprentice",
    "arrogant",
    "bastard",
    "boisterous",
    "conscripted",
    "cowardly",
    "deformed",
    "dying",
    "errant",
    "eunuch",
    "fanatical",
    "feral",
    "gluttonous",
    "giggling_often",
    "highborn",
    "idiotic",
    "irresponsible",
    "jinxed",
    "jovial",
    "kindly",
    "kvetching",
    "lazy",
    "lowborn",
    "masochistic",
    "mute",
    "nasty",
    "naughty",
    "old_very",
    "overly_optimistic",
    "pacifist",
    "penitent",
    "quarrelsome",
    "quiet",
    "reformed",
    "rude",
    "sarcastic",
    "servant",
    "thoughtful",
    "twisted",
    "ugly",
    "unwilling",
    "veteran",
    "weird",
    "whispery",
    "xenophobic",
    "ye_olde",
    "young_very",
    "zen",
    "heretical",
}

M.PROFESSIONS = {
    "acrobat",
    "artificer",
    "assassin",
    "bard",
    "baron",
    "berserker",
    "bodyguard",
    "bounty_hunter",
    "burglar",
    "child_catcher",
    "chirugeon",
    "cleric",
    "courtier",
    "diplomat",
    "drunkard",
    "duelist",
    "engineer",
    "explorer",
    "friar",
    "gladiator",
    "grave_robber",
    "highwayman",
    "hunter",
    "illusionist",
    "inquisitor",
    "jailer",
    "jester",
    "knight",
    "necromancer",
    "noble",
    "oracle",
    "pirate",
    "raider",
    "ranger",
    "rat_catcher",
    "senator",
    "scout",
    "scribe",
    "smith",
    "soldier",
    "spy",
    "templar",
    "tomb_robber",
    "urchin",
    "vagabond",
    "wanderer",
    "witch",
    "witch_hunter",
    "wizard",
    "zealot",
}

local DESCRIPTOR_ALIASES = {
    giggling = "giggling_often",
    often_giggling = "giggling_often",
    old = "old_very",
    very_old = "old_very",
    young = "young_very",
    very_young = "young_very",
}

local PROFESSION_ALIASES = {
    chirurgeon = "chirugeon",
    childcatcher = "child_catcher",
    grave_robber = "grave_robber",
    graverobber = "grave_robber",
    ratcatcher = "rat_catcher",
    tombrobber = "tomb_robber",
    witchhunter = "witch_hunter",
}

local descriptorSet = {}
for _, id in ipairs(M.DESCRIPTORS) do
    descriptorSet[id] = true
end

local professionSet = {}
for _, id in ipairs(M.PROFESSIONS) do
    professionSet[id] = true
end

local function copyList(source)
    local out = {}
    for i, value in ipairs(source or {}) do
        out[i] = value
    end
    return out
end

local function trim(value)
    if value == nil then
        return nil
    end
    local text = tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return nil
    end
    return text
end

function M.normalizeText(value)
    local text = trim(value)
    if not text then
        return nil
    end
    text = text:lower()
    text = text:gsub("[’']", "")
    text = text:gsub("%b()", "")
    text = text:gsub("[^%w]+", "_")
    text = text:gsub("^_+", ""):gsub("_+$", "")
    if text == "" then
        return nil
    end
    return text
end

function M.getDescriptor(value)
    local id = M.normalizeText(value)
    id = id and (DESCRIPTOR_ALIASES[id] or id)
    if id and descriptorSet[id] then
        return {
            id = id,
            sample = true,
        }
    end
    return nil
end

function M.getProfession(value)
    local id = M.normalizeText(value)
    id = id and (PROFESSION_ALIASES[id] or id)
    if id and professionSet[id] then
        return {
            id = id,
            sample = true,
        }
    end
    return nil
end

local function splitWords(id)
    local words = {}
    for word in tostring(id or ""):gmatch("[^_]+") do
        words[#words + 1] = word
    end
    return words
end

local function joinWords(words, first, last)
    local parts = {}
    for index = first, last do
        parts[#parts + 1] = words[index]
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, "_")
end

local function longestProfessionSuffix(words)
    for startIndex = 1, #words do
        local suffix = joinWords(words, startIndex, #words)
        local profession = M.getProfession(suffix)
        if profession then
            return profession.id, joinWords(words, 1, startIndex - 1)
        end
    end
    return nil, nil
end

function M.parseMotif(value)
    local text = trim(value)
    if not text then
        return nil, "Motif required"
    end

    local id = M.normalizeText(text)
    local words = splitWords(id)
    local professionId, descriptorId = longestProfessionSuffix(words)
    local descriptor = M.getDescriptor(descriptorId)
    local profession = M.getProfession(professionId)

    if not professionId and #words >= 2 then
        descriptorId = joinWords(words, 1, #words - 1)
        professionId = words[#words]
        descriptor = M.getDescriptor(descriptorId)
        profession = M.getProfession(professionId)
    elseif not descriptorId and #words >= 2 then
        descriptorId = words[1]
        descriptor = M.getDescriptor(descriptorId)
    end

    return {
        text = text,
        id = id,
        descriptor = descriptor and descriptor.id or descriptorId,
        profession = profession and profession.id or professionId,
        sampleDescriptor = descriptor ~= nil,
        sampleProfession = profession ~= nil,
        sampleMotif = descriptor ~= nil and profession ~= nil,
        structured = descriptorId ~= nil and professionId ~= nil,
    }
end

function M.describeMotifs(motifs)
    local detail = {}
    for _, motif in ipairs(motifs or {}) do
        local parsed, reason = M.parseMotif(motif)
        if not parsed then
            return nil, reason
        end
        detail[#detail + 1] = parsed
    end
    return detail
end

function M.validateMotifs(motifs, opts)
    opts = opts or {}
    if not motifs or #motifs ~= 3 then
        return false, "Exactly three motifs required"
    end

    local detail, reason = M.describeMotifs(motifs)
    if not detail then
        return false, reason
    end
    if opts.requireStructured == true then
        for _, motif in ipairs(detail) do
            if not motif.structured then
                return false, "Motifs require a descriptor and profession"
            end
        end
    end
    if opts.strictSamples == true then
        for _, motif in ipairs(detail) do
            if not motif.sampleMotif then
                return false, "Motif must use a rulebook descriptor and profession"
            end
        end
    end

    return true, "motifs_valid", {
        motifs = copyList(motifs),
        motifInfo = detail,
    }
end

return M
