-- spell_registry.lua
-- Data-backed spell definitions for Speak Incantation.

local constants = require('constants')

local M = {}

M.BRANCHES = {
    WASTES = "wastes",
    WEALD = "weald",
    WEIRD = "weird",
    WELKIN = "welkin",
}

M.spells = {
    brainfever = {
        id = "brainfever",
        name = "Brainfever",
        branch = M.BRANCHES.WASTES,
        talent = "magic_of_the_wastes",
        componentId = "component_brainfever",
        targetMode = "unwilling_creature",
        ongoing = true,
        concentration = true,
        effect = {
            type = "brainfever",
        },
    },

    control_undead = {
        id = "control_undead",
        name = "Control Undead",
        branch = M.BRANCHES.WASTES,
        talent = "magic_of_the_wastes",
        componentId = "component_control_undead",
        targetMode = "unwilling_creature",
        ongoing = true,
        effect = {
            type = "control",
            targetTrait = "undead",
        },
    },

    necromancy = {
        id = "necromancy",
        name = "Necromancy",
        branch = M.BRANCHES.WASTES,
        talent = "magic_of_the_wastes",
        componentId = "component_necromancy",
        targetMode = "dead_person",
        ongoing = true,
        concentration = true,
        effect = {
            type = "necromancy",
        },
    },

    malediction = {
        id = "malediction",
        name = "Malediction",
        branch = M.BRANCHES.WASTES,
        talent = "magic_of_the_wastes",
        componentId = "component_malediction",
        targetMode = "unwilling_creature",
        ongoing = true,
        effect = {
            type = "malediction",
        },
    },

    fleshcraft = {
        id = "fleshcraft",
        name = "Fleshcraft",
        branch = M.BRANCHES.WASTES,
        talent = "magic_of_the_wastes",
        componentId = "component_fleshcraft",
        targetMode = "self",
        ongoing = true,
        concentration = true,
        effect = {
            type = "fleshcraft",
        },
    },

    raise_zombie = {
        id = "raise_zombie",
        name = "Raise Zombie",
        branch = M.BRANCHES.WASTES,
        talent = "magic_of_the_wastes",
        componentId = "component_raise_zombie",
        targetMode = "dead_body",
        ongoing = true,
        effect = {
            type = "raise_zombie",
        },
    },

    control_animal = {
        id = "control_animal",
        name = "Control Animal",
        branch = M.BRANCHES.WEALD,
        talent = "magic_of_the_weald",
        componentId = "component_control_animal",
        targetMode = "unwilling_creature",
        ongoing = true,
        effect = {
            type = "control",
            targetTrait = "animal",
        },
    },

    flare = {
        id = "flare",
        name = "Flare",
        branch = M.BRANCHES.WEALD,
        talent = "magic_of_the_weald",
        componentId = "component_flare",
        targetMode = "environment_or_creature",
        effect = {
            type = "flare",
        },
    },

    defy_depths = {
        id = "defy_depths",
        name = "Defy Depths",
        branch = M.BRANCHES.WEALD,
        talent = "magic_of_the_weald",
        componentId = "component_defy_depths",
        targetMode = "creature_or_object",
        ongoing = true,
        concentration = true,
        baseTargets = 1,
        extraTargetResolve = 1,
        effect = {
            type = "defy_depths",
        },
    },

    gust_of_wind = {
        id = "gust_of_wind",
        name = "Gust of Wind",
        branch = M.BRANCHES.WEALD,
        talent = "magic_of_the_weald",
        componentId = "component_gust_of_wind",
        targetMode = "unwilling_creature",
        effect = {
            type = "gust_of_wind",
        },
    },

    protection_from_elements = {
        id = "protection_from_elements",
        name = "Protection from the Elements",
        branch = M.BRANCHES.WEALD,
        talent = "magic_of_the_weald",
        componentId = "component_protection_from_elements",
        targetMode = "creature",
        ongoing = true,
        concentration = true,
        baseElements = 1,
        extraElementResolve = 1,
        baseTargets = 1,
        extraTargetResolve = 1,
        effect = {
            type = "protection_from_elements",
        },
    },

    speak_to_animal = {
        id = "speak_to_animal",
        name = "Speak to Animal",
        branch = M.BRANCHES.WEALD,
        talent = "magic_of_the_weald",
        componentId = "component_speak_to_animal",
        targetMode = "self",
        ongoing = true,
        concentration = true,
        effect = {
            type = "speak_to_animal",
        },
    },

    thunderclap = {
        id = "thunderclap",
        name = "Thunderclap",
        branch = M.BRANCHES.WEALD,
        talent = "magic_of_the_weald",
        componentId = "component_thunderclap",
        targetMode = "environment",
        effect = {
            type = "thunderclap",
        },
    },

    totem = {
        id = "totem",
        name = "Totem",
        branch = M.BRANCHES.WEALD,
        talent = "magic_of_the_weald",
        componentId = "component_totem",
        targetMode = "creature",
        ongoing = true,
        effect = {
            type = "totem",
        },
    },

    wall_of_elements = {
        id = "wall_of_elements",
        name = "Wall of Elements",
        branch = M.BRANCHES.WEALD,
        talent = "magic_of_the_weald",
        componentId = "component_wall_of_elements",
        targetMode = "environment",
        ongoing = true,
        concentration = true,
        effect = {
            type = "wall_of_elements",
        },
    },

    woodweave = {
        id = "woodweave",
        name = "Woodweave",
        branch = M.BRANCHES.WEALD,
        talent = "magic_of_the_weald",
        componentId = "component_woodweave",
        targetMode = "environment_or_creature",
        effect = {
            type = "woodweave",
        },
    },

    darklight = {
        id = "darklight",
        name = "Darklight",
        branch = M.BRANCHES.WASTES,
        talent = "magic_of_the_wastes",
        componentId = "component_darklight",
        targetMode = "object",
        ongoing = true,
        concentration = true,
        effect = {
            type = "darklight",
        },
    },

    fear = {
        id = "fear",
        name = "Fear",
        branch = M.BRANCHES.WASTES,
        talent = "magic_of_the_wastes",
        componentId = "component_fear",
        targetMode = "unwilling_creature",
        ongoing = true,
        concentration = true,
        effect = {
            type = "emotional_illusion",
            disposition = "fear",
        },
    },

    augury = {
        id = "augury",
        name = "Augury",
        branch = M.BRANCHES.WELKIN,
        talent = "magic_of_the_welkin",
        componentId = "component_augury",
        targetMode = "environment",
        effect = {
            type = "augury",
        },
    },

    binding = {
        id = "binding",
        name = "Binding",
        branch = M.BRANCHES.WELKIN,
        talent = "magic_of_the_welkin",
        componentId = "component_binding",
        targetMode = "named_creatures",
        ongoing = true,
        concentration = true,
        effect = {
            type = "binding",
        },
    },

    charm = {
        id = "charm",
        name = "Charm",
        branch = M.BRANCHES.WELKIN,
        talent = "magic_of_the_welkin",
        componentId = "component_charm",
        targetMode = "person",
        ongoing = true,
        concentration = true,
        effect = {
            type = "charm",
        },
    },

    circle_of_protection = {
        id = "circle_of_protection",
        name = "Circle of Protection",
        branch = M.BRANCHES.WELKIN,
        talent = "magic_of_the_welkin",
        componentId = "component_circle_of_protection",
        targetMode = "environment",
        ongoing = true,
        concentration = true,
        baseRealms = 1,
        extraRealmResolve = 1,
        radiusFeet = 10,
        requiresPreparedCircle = true,
        effect = {
            type = "circle_of_protection",
        },
    },

    feather = {
        id = "feather",
        name = "Feather",
        branch = M.BRANCHES.WELKIN,
        talent = "magic_of_the_welkin",
        componentId = "component_feather",
        targetMode = "creature_or_object",
        ongoing = true,
        concentration = true,
        effect = {
            type = "feather",
        },
    },

    guardian_angel = {
        id = "guardian_angel",
        name = "Guardian Angel",
        branch = M.BRANCHES.WELKIN,
        talent = "magic_of_the_welkin",
        componentId = "component_guardian_angel",
        targetMode = "ally",
        effect = {
            type = "guardian_angel",
        },
    },

    heavenfire = {
        id = "heavenfire",
        name = "Heavenfire",
        branch = M.BRANCHES.WELKIN,
        talent = "magic_of_the_welkin",
        componentId = "component_heavenfire",
        targetMode = "creature_or_object",
        effect = {
            type = "heavenfire",
        },
    },

    animate_object = {
        id = "animate_object",
        name = "Animate Object",
        branch = M.BRANCHES.WEIRD,
        talent = "magic_of_the_weird",
        componentId = "component_animate_object",
        targetMode = "object",
        ongoing = true,
        effect = {
            type = "animate_object",
        },
    },

    change_size = {
        id = "change_size",
        name = "Change Size",
        branch = M.BRANCHES.WEIRD,
        talent = "magic_of_the_weird",
        componentId = "component_change_size",
        targetMode = "creature",
        ongoing = true,
        concentration = true,
        effect = {
            type = "change_size",
        },
    },

    enrage = {
        id = "enrage",
        name = "Enrage",
        branch = M.BRANCHES.WEIRD,
        talent = "magic_of_the_weird",
        componentId = "component_enrage",
        targetMode = "unwilling_creature",
        ongoing = true,
        concentration = true,
        effect = {
            type = "emotional_illusion",
            disposition = "anger",
        },
    },

    give_form_to_nothingness = {
        id = "give_form_to_nothingness",
        name = "Give Form to Nothingness",
        branch = M.BRANCHES.WEIRD,
        talent = "magic_of_the_weird",
        componentId = "component_give_form_to_nothingness",
        targetMode = "environment",
        ongoing = true,
        baseRooms = 1,
        extraRoomResolve = 1,
        effect = {
            type = "give_form_to_nothingness",
        },
    },

    portable_hole = {
        id = "portable_hole",
        name = "Portable Hole",
        branch = M.BRANCHES.WEIRD,
        talent = "magic_of_the_weird",
        componentId = "component_portable_hole",
        targetMode = "object",
        ongoing = true,
        concentration = true,
        effect = {
            type = "portable_hole",
        },
    },

    illusion = {
        id = "illusion",
        name = "Illusion",
        branch = M.BRANCHES.WEIRD,
        talent = "magic_of_the_weird",
        componentId = "component_illusion",
        targetMode = "environment",
        ongoing = true,
        concentration = true,
        effect = {
            type = "visual_illusion",
        },
    },

    mirror_meld = {
        id = "mirror_meld",
        name = "Mirror Meld",
        branch = M.BRANCHES.WEIRD,
        talent = "magic_of_the_weird",
        componentId = "component_mirror_meld",
        targetMode = "object",
        ongoing = true,
        effect = {
            type = "mirror_meld",
        },
    },

    sleep = {
        id = "sleep",
        name = "Sleep",
        branch = M.BRANCHES.WEIRD,
        talent = "magic_of_the_weird",
        componentId = "component_sleep",
        targetMode = "unwilling_creature",
        effect = {
            type = "sleep",
        },
    },

    shroud = {
        id = "shroud",
        name = "Shroud",
        branch = M.BRANCHES.WEIRD,
        talent = "magic_of_the_weird",
        componentId = "component_shroud",
        targetMode = "creature",
        ongoing = true,
        concentration = true,
        effect = {
            type = "shroud",
        },
    },

    scry = {
        id = "scry",
        name = "Scry",
        branch = M.BRANCHES.WEIRD,
        talent = "magic_of_the_weird",
        componentId = "component_scry",
        targetMode = "environment",
        ongoing = true,
        concentration = true,
        effect = {
            type = "scry",
        },
    },

    stinking_cloud = {
        id = "stinking_cloud",
        name = "Stinking Cloud",
        branch = M.BRANCHES.WASTES,
        talent = "magic_of_the_wastes",
        componentId = "component_stinking_cloud",
        targetMode = "environment",
        ongoing = true,
        concentration = true,
        effect = {
            type = "stinking_cloud",
        },
    },

    withering = {
        id = "withering",
        name = "Withering",
        branch = M.BRANCHES.WASTES,
        talent = "magic_of_the_wastes",
        componentId = "component_withering",
        targetMode = "unwilling_creature_or_object",
        effect = {
            type = "withering",
        },
    },

    life = {
        id = "life",
        name = "Life",
        branch = M.BRANCHES.WELKIN,
        talent = "magic_of_the_welkin",
        componentId = "component_life",
        targetMode = "creature",
        multiTarget = true,
        effect = {
            type = "life",
        },
    },

    veritas = {
        id = "veritas",
        name = "Veritas",
        branch = M.BRANCHES.WELKIN,
        talent = "magic_of_the_welkin",
        componentId = "component_veritas",
        targetMode = "person",
        ongoing = true,
        concentration = true,
        effect = {
            type = "veritas",
        },
    },

    seal_pact = {
        id = "seal_pact",
        name = "Seal Pact",
        branch = M.BRANCHES.WELKIN,
        talent = "magic_of_the_welkin",
        componentId = "component_seal_pact",
        targetMode = "willing_parties",
        baseParties = 2,
        extraPartyResolve = 1,
        effect = {
            type = "seal_pact",
        },
    },
}

M.TOTEM_CHART = {
    [constants.SUITS.SWORDS] = {
        [1] = "Ape",
        [2] = "Armadillo",
        [3] = "Badger",
        [4] = "Bat",
        [5] = "Bear",
        [6] = "Cat",
        [7] = "Cattle",
        [8] = "Crab",
        [9] = "Crocodile",
        [10] = "Deer",
        [11] = "Dog",
        [12] = "Eagle",
        [13] = "Elk",
        [14] = "Fox",
    },
    [constants.SUITS.PENTACLES] = {
        [1] = "Frog",
        [2] = "Goat",
        [3] = "Hedgehog",
        [4] = "Hog",
        [5] = "Hyena",
        [6] = "Jackdaw",
        [7] = "Kangaroo",
        [8] = "Leopard",
        [9] = "Lion",
        [10] = "Mouse",
        [11] = "Mule",
        [12] = "Opossum",
        [13] = "Otter",
        [14] = "Owl",
    },
    [constants.SUITS.CUPS] = {
        [1] = "Rat",
        [2] = "Pelican",
        [3] = "Peacock",
        [4] = "Rabbit",
        [5] = "Raccoon",
        [6] = "Seal",
        [7] = "Snake",
        [8] = "Stoat",
        [9] = "Swan",
        [10] = "Tiger",
        [11] = "Turtle",
        [12] = "Vulture",
        [13] = "Walrus",
        [14] = "Wolf",
    },
    [constants.SUITS.WANDS] = {
        [1] = "Bonnacon",
        [2] = "Capricorn",
        [3] = "Dire Centipede",
        [4] = "Coatl",
        [5] = "Dire Grasshopper",
        [6] = "Griffin",
        [7] = "Hippogriff",
        [8] = "Mammoth",
        [9] = "Owlbear",
        [10] = "Dire Rat",
        [11] = "Roc",
        [12] = "Dire Snail",
        [13] = "Dire Spider",
        [14] = "Thunder Lizard",
    },
}

M.MALEDICTION_CURSES = {
    [1] = {
        rank = "I",
        id = "dogs_hate_you",
        name = "Dogs Hate You",
        flags = {
            dogsHateYou = true,
            dogAttackPriority = true,
            cityPhaseDogCurse = true,
        },
        metadata = {
            cityPhaseConditionChance = {
                staggered = 0.5,
                stressed = 0.5,
            },
        },
    },
    [2] = {
        rank = "II",
        id = "bad_dreams",
        name = "Bad Dreams",
        flags = {
            badDreams = true,
        },
        metadata = {
            wakeStressedChance = 0.5,
        },
    },
    [3] = {
        rank = "III",
        id = "ash_food",
        name = "Ash Food",
        flags = {
            foodMayTurnToAsh = true,
        },
        metadata = {
            rationAshChance = 0.5,
        },
    },
    [4] = {
        rank = "IV",
        id = "doomed",
        name = "Doomed",
        conditions = {
            exhausted = true,
        },
        nonRecoverableConditions = {
            exhausted = "malediction",
        },
        flags = {
            doomedByMalediction = true,
        },
    },
    [5] = {
        rank = "V",
        id = "desiccated_corpse",
        name = "Desiccated Corpse",
        flags = {
            appearsAsDesiccatedCorpse = true,
            gmCharactersUsuallyHostile = true,
            undeadUsuallyIgnore = true,
            intimacyUsuallyRejected = true,
        },
    },
    [6] = {
        rank = "VI",
        id = "speak_in_rhymes",
        name = "Speak in Rhymes",
        flags = {
            mustSpeakInRhymes = true,
        },
    },
    [7] = {
        rank = "VII",
        id = "rusting_weapons",
        name = "Rusting Weapons",
        flags = {
            weaponRustMalediction = true,
            maledictionWeaponNotchThreshold = 10,
        },
    },
    [8] = {
        rank = "VIII",
        id = "changed_anatomy",
        name = "Changed Anatomy",
        flags = {
            sexualAnatomyChanged = true,
        },
    },
    [9] = {
        rank = "IX",
        id = "beloved_by_vermin",
        name = "Beloved by Vermin",
        flags = {
            verminFollow = true,
        },
        metadata = {
            nightlyPackSwapChance = 0.5,
        },
    },
    [10] = {
        rank = "X",
        id = "shame_bell",
        name = "Shame Bell",
        flags = {
            stealthImpossible = true,
            shameBellFootsteps = true,
        },
    },
    [11] = {
        rank = "Page",
        id = "sick_and_infirm",
        name = "Sick and Infirm",
        conditions = {
            infirm = true,
        },
        flags = {
            maledictionExtraBondRecoveryCost = true,
            immuneToHeal = true,
            immuneToHealEffect = true,
        },
    },
    [12] = {
        rank = "Knight",
        id = "old_crone",
        name = "Old Crone",
        flags = {
            sightRangeFeet = 30,
            cannotDash = true,
        },
    },
    [13] = {
        rank = "Queen",
        id = "tylwyth_only",
        name = "Tylwyth Only",
        flags = {
            languageLocked = "tylwyth",
            speaksGibberishToNonTylwyth = true,
        },
    },
    [14] = {
        rank = "King",
        id = "chicken_doom",
        name = "Chicken Doom",
        flags = {
            stressChickenTest = true,
        },
    },
}

local function normalize(value)
    value = tostring(value or ""):lower()
    value = value:gsub("[’']", "")
    value = value:gsub("%s+", "_")
    value = value:gsub("[^%w_]", "")
    return value
end

function M.normalizeId(value)
    return normalize(value)
end

function M.getSpell(spellRef)
    if type(spellRef) == "table" then
        return spellRef
    end

    local id = normalize(spellRef)
    return M.spells[id]
end

function M.getTotemForCard(card)
    if not card then
        return nil
    end

    local suitChart = M.TOTEM_CHART[card.suit]
    return suitChart and suitChart[card.value] or nil
end

function M.getMaledictionCurseForCard(card)
    if not card or card.is_major then
        return nil
    end

    local value = math.floor(tonumber(card.value) or 0)
    return M.MALEDICTION_CURSES[value]
end

function M.listSpells()
    local spells = {}
    for _, spell in pairs(M.spells) do
        spells[#spells + 1] = spell
    end
    table.sort(spells, function(a, b)
        return a.name < b.name
    end)
    return spells
end

return M
