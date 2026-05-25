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

M.CREATION_PATH_TALENTS = {
    swords = {
        "aegis",
        "doom_eye",
        "heavy_metal_machine",
        "monster_hunter",
        "reaver",
        "two_handed_focus",
        "war_stories",
    },
    pentacles = M.PATH_TALENTS.pentacles,
    cups = M.PATH_TALENTS.cups,
    wands = M.PATH_TALENTS.wands,
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

M.DEFAULT_KIN_TALENTS = {
    human = "proud_and_ancient",
    high_elf = "read_the_past",
    dark_elf = "foretell",
    wood_elf = "keen_senses",
    gnome = "weird_wise_ancient",
    dwarf = "labor_unending",
    halfling = "hale_and_hearty",
    troll = "giants_strength",
    earthblooded = "quicksilver_blood",
    stormblooded = "blur",
    seablooded = "poison_blood",
    fireblooded = "berserkergang",
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

M.ARETE_TRIGGERS = {
    human = {
        { id = "getting_married", description = "Getting married" },
        { id = "fulfilling_an_oath", description = "Fulfilling an oath" },
        {
            id = "defeating_rival_house_in_fair_duel",
            description = "Defeating a member of a rival house in fair tournament or duel",
        },
    },
    fay = {
        { id = "killing_without_weapon", description = "Killing something without using a weapon" },
        { id = "aiding_a_spirit", description = "Providing aid to a spirit" },
        { id = "making_kissed_person_cry", description = "Making someone they've kissed cry" },
    },
    underfolk = {
        { id = "crafting_for_centuries", description = "Crafting something that will last for centuries" },
        {
            id = "hoarding_grave_good",
            description = "Recovering a precious gem or work of fine art and hoarding it as a grave good",
        },
        { id = "discovering_secret_forgotten", description = "Discovering something secret and forgotten" },
    },
    orc = {
        {
            id = "hoarding_new_monster_skull",
            description = "Hoarding a skull from a class of monster your guild has never killed before",
        },
        { id = "hoarding_great_treasure", description = "Hoarding a treasure of great worth" },
        { id = "slaying_twice_size_monster", description = "Slaying a monster at least twice your size" },
    },
}

M.ARETE_TALENT_BY_KIN = {
    human = "byname",
    high_elf = "akashic_consciousness",
    dark_elf = "spout_doom",
    wood_elf = "area_sense",
    gnome = "uncanny_knowledge",
    dwarf = "iron_beards",
    halfling = "underfoot",
    troll = "colossal",
    earthblooded = "jarl",
    stormblooded = "jarl",
    seablooded = "jarl",
    fireblooded = "jarl",
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

function M.normalizeKith(value)
    local normalized = normalize(value)
    local aliases = {
        humans = "human",
        fey = "fay",
        fae = "fay",
        fair_folk = "fay",
        under_folk = "underfolk",
        underfolks = "underfolk",
        orcs = "orc",
    }
    return aliases[normalized] or normalized
end

function M.inferKithForKin(kin)
    local normalizedKin = M.normalizeKin(kin)
    if normalizedKin == "human" then
        return "human"
    end
    for _, info in pairs(M.KIN_TALENTS) do
        if normalize(info.kin) == normalizedKin then
            return normalize(info.kith)
        end
    end
    return nil
end

function M.getKithForKin(kin, kith)
    local normalizedKith = M.normalizeKith(kith)
    if normalizedKith ~= "" then
        return normalizedKith
    end

    return M.inferKithForKin(kin)
end

function M.validateKithKin(kin, kith)
    local normalizedKin = M.normalizeKin(kin)
    if normalizedKin == "" then
        return false, "Kin required"
    end

    local inferredKith = M.inferKithForKin(normalizedKin)
    if not inferredKith then
        return false, "Kin talent required"
    end

    local normalizedKith = M.normalizeKith(kith)
    if normalizedKith ~= "" and normalizedKith ~= inferredKith then
        return false, "Kith does not match kin", {
            kin = normalizedKin,
            kith = normalizedKith,
            expectedKith = inferredKith,
        }
    end

    return true, "kith_kin_valid", {
        kin = normalizedKin,
        kith = inferredKith,
        explicitKith = normalizedKith ~= "",
    }
end

function M.getCreationPathTalents(path)
    local normalizedPath = M.normalizePath(path)
    local source = M.CREATION_PATH_TALENTS[normalizedPath] or {}
    local talents = {}
    for _, talentId in ipairs(source) do
        talents[#talents + 1] = talentId
    end
    return talents
end

function M.isCreationPathTalent(path, talentId)
    local normalizedTalentId = normalize(talentId)
    for _, candidate in ipairs(M.getCreationPathTalents(path)) do
        if normalize(candidate) == normalizedTalentId then
            return true
        end
    end
    return false
end

function M.getDefaultKinTalent(kin, kith)
    local normalizedKin = M.normalizeKin(kin)
    if M.DEFAULT_KIN_TALENTS[normalizedKin] then
        return M.DEFAULT_KIN_TALENTS[normalizedKin]
    end

    local normalizedKith = normalize(kith)
    for talentId, info in pairs(M.KIN_TALENTS) do
        if not info.optional and
            (normalizedKin == "" or normalize(info.kin) == normalizedKin) and
            (normalizedKith == "" or normalize(info.kith) == normalizedKith) then
            return normalize(talentId)
        end
    end
    return nil
end

function M.getAreteTalent(kin, kith)
    local ok, _, detail = M.validateKithKin(kin, kith)
    if not ok then
        return nil
    end

    local normalizedKin = detail.kin
    if M.ARETE_TALENT_BY_KIN[normalizedKin] then
        return M.ARETE_TALENT_BY_KIN[normalizedKin]
    end

    if detail.kith == "orc" then
        return "jarl"
    end
    return nil
end

function M.getAreteSetup(kin, kith)
    local ok, _, detail = M.validateKithKin(kin, kith)
    if not ok then
        return nil
    end

    local normalizedKin = detail.kin
    local normalizedKith = detail.kith
    local source = normalizedKith and M.ARETE_TRIGGERS[normalizedKith]
    local talentId = M.getAreteTalent(normalizedKin, normalizedKith)
    if not source or not talentId then
        return nil
    end

    local triggers = {}
    for _, trigger in ipairs(source) do
        triggers[#triggers + 1] = {
            id = trigger.id,
            description = trigger.description,
            checked = false,
        }
    end
    return {
        kith = normalizedKith,
        kin = normalizedKin,
        talentId = talentId,
        triggers = triggers,
        checkCount = 0,
        requiredChecks = #triggers,
        completed = false,
    }
end

function M.recordAreteTrigger(actor, triggerRef, opts)
    opts = opts or {}
    if not actor then
        return false, "Adventurer required"
    end

    actor.arete = actor.arete or M.getAreteSetup(actor.kin or actor.species or actor.race, actor.kith)
    if not actor.arete then
        return false, "Arete setup required"
    end

    local wanted = normalize(triggerRef or opts.trigger or opts.id)
    local selected = nil
    for _, trigger in ipairs(actor.arete.triggers or {}) do
        if normalize(trigger.id) == wanted or normalize(trigger.description) == wanted then
            selected = trigger
            break
        end
    end
    if not selected then
        return false, "Unknown arete trigger"
    end

    local alreadyChecked = selected.checked == true
    selected.checked = true
    actor.arete.checks = actor.arete.checks or {}
    actor.arete.checks[selected.id] = true

    local checkCount = 0
    for _, trigger in ipairs(actor.arete.triggers or {}) do
        if trigger.checked then
            checkCount = checkCount + 1
        end
    end
    actor.arete.checkCount = checkCount
    actor.areteCheckMarks = checkCount

    local learned = false
    if checkCount >= (actor.arete.requiredChecks or 3) and actor.arete.talentId then
        actor.talents = actor.talents or {}
        actor.talents[actor.arete.talentId] = actor.talents[actor.arete.talentId] or {}
        actor.talents[actor.arete.talentId].mastered = true
        actor.talents[actor.arete.talentId].wounded = actor.talents[actor.arete.talentId].wounded or false
        actor.talents[actor.arete.talentId].xp_invested = actor.talents[actor.arete.talentId].xp_invested or 0
        actor.talents[actor.arete.talentId].trainingKind = "arete"
        actor.talents[actor.arete.talentId].arete = true
        actor.talents[actor.arete.talentId].kith = actor.arete.kith
        actor.arete.completed = true
        actor.areteTalentId = actor.arete.talentId
        learned = not alreadyChecked
    end

    return true, {
        trigger = selected,
        triggerId = selected.id,
        alreadyChecked = alreadyChecked,
        checkCount = checkCount,
        requiredChecks = actor.arete.requiredChecks or 3,
        completed = actor.arete.completed == true,
        learned = learned,
        talentId = actor.arete.talentId,
    }
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
