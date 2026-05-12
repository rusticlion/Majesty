-- talent_catalog.lua
-- Canonical talent grouping for training legality and light metadata.

local M = {}

local function normalize(value)
    return tostring(value or "")
        :lower()
        :gsub("[’']", "")
        :gsub("[^%w]+", "_")
        :gsub("^_+", "")
        :gsub("_+$", "")
end

M.PATH_TALENTS = {
    swords = {
        "aegis",
        "doom_eye",
        "heavy_metal_machine",
        "monster_hunter",
        "beast_hunter",
        "elemental_hunter",
        "man_hunter",
        "spirit_hunter",
        "undead_hunter",
        "witch_hunter",
        "reaver",
        "two_handed_focus",
        "war_stories",
    },
    pentacles = {
        "acrobat",
        "ambusher",
        "con_artist",
        "fight_dirty",
        "quick",
        "sneak",
        "up_my_sleeve",
    },
    cups = {
        "alchemy",
        "beast_master",
        "bookworm",
        "chirurgeon",
        "counsel",
        "high_chant",
        "loremaster",
    },
    wands = {
        "counter_spell",
        "dwimmercraft",
        "sorcery",
        "gramarye",
        "magic_of_the_wastes",
        "magic_of_the_weald",
        "magic_of_the_weird",
        "magic_of_the_welkin",
    },
}

M.KIN_TALENTS = {
    proud_and_ancient = { kith = "human", kin = "human" },
    turncloak = { kith = "human", kin = "human", optional = true },
    read_the_past = { kith = "fay", kin = "high_elf" },
    foretell = { kith = "fay", kin = "dark_elf" },
    keen_senses = { kith = "fay", kin = "wood_elf" },
    weird_wise_ancient = { kith = "fay", kin = "gnome" },
    labor_unending = { kith = "underfolk", kin = "dwarf" },
    hale_and_hearty = { kith = "underfolk", kin = "halfling" },
    giants_strength = { kith = "underfolk", kin = "troll" },
    quicksilver_blood = { kith = "orc", kin = "earthblooded" },
    blur = { kith = "orc", kin = "stormblooded" },
    poison_blood = { kith = "orc", kin = "seablooded" },
    berserkergang = { kith = "orc", kin = "fireblooded" },
}

M.ARETE_TALENTS = {
    byname = { kith = "human", kin = "human" },
    akashic_consciousness = { kith = "fay", kin = "high_elf" },
    spout_doom = { kith = "fay", kin = "dark_elf" },
    area_sense = { kith = "fay", kin = "wood_elf" },
    uncanny_knowledge = { kith = "fay", kin = "gnome" },
    iron_beards = { kith = "underfolk", kin = "dwarf" },
    underfoot = { kith = "underfolk", kin = "halfling" },
    colossal = { kith = "underfolk", kin = "troll" },
    jarl = { kith = "orc" },
}

local TALENT_INDEX = {}

local function addTalent(id, info)
    local normalizedId = normalize(id)
    local record = {}
    for key, value in pairs(info or {}) do
        record[key] = value
    end
    record.id = normalizedId
    TALENT_INDEX[normalizedId] = record
end

for path, talents in pairs(M.PATH_TALENTS) do
    for _, talentId in ipairs(talents) do
        addTalent(talentId, {
            kind = "path",
            path = normalize(path),
            trainable = true,
        })
    end
end

for talentId, info in pairs(M.KIN_TALENTS) do
    local record = {
        kind = "kin",
        kith = normalize(info.kith),
        kin = normalize(info.kin),
        optional = info.optional == true,
        trainable = false,
    }
    addTalent(talentId, record)
end

for talentId, info in pairs(M.ARETE_TALENTS) do
    local record = {
        kind = "arete",
        kith = normalize(info.kith),
        kin = normalize(info.kin),
        trainable = false,
    }
    addTalent(talentId, record)
end

function M.normalizeId(value)
    return normalize(value)
end

function M.normalizePath(value)
    local normalized = normalize(value):gsub("^path_of_", "")
    if normalized == "sword" then
        return "swords"
    elseif normalized == "pentacle" or normalized == "disks" or normalized == "disk" then
        return "pentacles"
    elseif normalized == "cup" then
        return "cups"
    elseif normalized == "wand" or normalized == "batons" or normalized == "baton" then
        return "wands"
    end
    return normalized
end

function M.normalizeKin(value)
    local normalized = normalize(value)
    local aliases = {
        humans = "human",
        high_elves = "high_elf",
        wood_elves = "wood_elf",
        dark_elves = "dark_elf",
        gnomes = "gnome",
        dwarves = "dwarf",
        halflings = "halfling",
        trolls = "troll",
        stormblooded_orc = "stormblooded",
        earthblooded_orc = "earthblooded",
        seablooded_orc = "seablooded",
        fireblooded_orc = "fireblooded",
    }
    return aliases[normalized] or normalized
end

function M.getTalentInfo(talentId)
    return TALENT_INDEX[normalize(talentId)]
end

function M.isKinOrAreteTalent(talentId)
    local info = M.getTalentInfo(talentId)
    return info and (info.kind == "kin" or info.kind == "arete") or false
end

function M.isPathTalent(talentId)
    local info = M.getTalentInfo(talentId)
    return info and info.kind == "path" or false
end

function M.getActorPath(actor)
    return M.normalizePath(actor and (actor.path or actor.pathName or actor.role or actor.class or actor.suit))
end

function M.validateTraining(actor, talentId, options)
    options = options or {}
    local normalizedTalentId = normalize(talentId)
    if normalizedTalentId == "" then
        return false, { reason = "Choose a talent to train" }
    end

    local info = M.getTalentInfo(normalizedTalentId)
    if not info then
        return true, {
            talentId = normalizedTalentId,
            kind = "custom",
            mentored = options.hasTrainer == true or options.cityExpert == true,
            unknownCanonicalTalent = true,
        }
    end

    if info.kind == "kin" or info.kind == "arete" then
        return false, {
            reason = "Kin talents cannot be trained",
            talentId = normalizedTalentId,
            kind = info.kind,
            kith = info.kith,
            kin = info.kin,
        }
    end

    local actorPath = M.getActorPath(actor)
    local ownPath = actorPath ~= "" and actorPath == info.path
    local needsMentor = not ownPath
    if needsMentor and options.trainerAvailable == false then
        return false, {
            reason = "Trainer unavailable",
            talentId = normalizedTalentId,
            kind = info.kind,
            path = info.path,
            actorPath = actorPath ~= "" and actorPath or nil,
        }
    end

    return true, {
        talentId = normalizedTalentId,
        kind = info.kind,
        path = info.path,
        actorPath = actorPath ~= "" and actorPath or nil,
        ownPath = ownPath,
        mentored = needsMentor,
    }
end

return M
