-- maleficence_tables.lua
-- Compact, data-backed Appendix A maleficence lookup tables.

local M = {}

M.BRANCHES = {
    WASTES = "wastes",
    WEALD = "weald",
    WEIRD = "weird",
    WELKIN = "welkin",
}

local RANKS = {
    [1] = "I",
    [2] = "II",
    [3] = "III",
    [4] = "IV",
    [5] = "V",
    [6] = "VI",
    [7] = "VII",
    [8] = "VIII",
    [9] = "IX",
    [10] = "X",
    [11] = "Page",
    [12] = "Knight",
    [13] = "Queen",
    [14] = "King",
}

local function entry(value, title, summary, effects)
    return {
        value = value,
        rank = RANKS[value],
        title = title,
        summary = summary,
        effects = effects or {},
    }
end

M.tables = {
    wastes = {
        [1] = entry(1, "Imps Manifest", "Imps appear based on the top minor discard.", {
            { type = "spawn", mobId = "imp", countFrom = "minor_discard_value" },
        }),
        [2] = entry(2, "Diseased Ratbirth", "A diseased rat swarm horror contaminates the area.", {
            { type = "room_hazard", hazard = "diseased_ratbirth", tag = "disease", disease = true, contaminatesArea = true, vomitedPregnantRat = true, explodesIntoBabyRats = true, bloodilySpills = true, diseaseOozes = true, physicalSource = "undulating_mass" },
            { type = "gm_adjudicate", tag = "disease" },
        }),
        [3] = entry(3, "Mass-Grave Stench", "Remaining in the area stresses the guild.", {
            { type = "area_condition", condition = "stressed", target = "guild", smell = "putrid_mass_grave", stressTrigger = "stay_in_area" },
        }),
        [4] = entry(4, "Rust Fog", "Exposed metal carried by the guild suffers two Notches.", {
            { type = "notch_items", material = "metal", amount = 2 },
        }),
        [5] = entry(5, "Demonic Flies", "Perishables in the room are ruined by a demonic swarm.", {
            { type = "destroy_items", tag = "perishable", scope = "room" },
        }),
        [6] = entry(6, "Wounds Refuse Closure", "Talent wounds and Injured cannot heal until the next Fool reshuffle.", {
            { type = "healing_block", ["until"] = "fool_reshuffle", woundTypes = { "talent", "injured" } },
        }),
        [7] = entry(7, "Blood Tears", "The sorcerer suffers vision-based disfavor until the next Fool reshuffle.", {
            { type = "condition", condition = "bloody_tears", ["until"] = "fool_reshuffle", visionObscured = true, ruinsRobes = true },
        }),
        [8] = entry(8, "Undead Mark", "Undead are supernaturally drawn to the sorcerer until cleansed.", {
            { type = "condition", condition = "undead_mark", ["until"] = "cleansed", invisibleForeheadMark = true, undeadDesires = { "talk", "touch", "kiss", "hurt", "make_understand" } },
        }),
        [9] = entry(9, "Wayward Shadow", "The sorcerer's shadow leaves to cause trouble.", {
            { type = "condition", condition = "shadowless", ["until"] = "shadow_returns", shadowDeparted = true, performsMischief = true },
        }),
        [10] = entry(10, "Parasitic Twin", "The sorcerer is Stunned for a watch as the maleficence passes.", {
            { type = "condition", condition = "stunned", duration = "watch", tag = "parasitic_twin", chunks = { "hands", "eyes", "hair", "teeth" }, canDoVeryLittle = true },
        }),
        [11] = entry(11, "Golden Eyes", "The sorcerer's eyes permanently change.", {
            { type = "body_change", change = "golden_eyes", permanent = true, irisColor = "golden", resembles = "wolf" },
        }),
        [12] = entry(12, "Black Horns", "The sorcerer grows permanent horns.", {
            { type = "body_change", change = "black_horns", permanent = true, hornType = "black_goat_like", removableBySaw = true, painlessRemoval = true, stumpsRemain = true },
        }),
        [13] = entry(13, "Decaying Reflection", "The sorcerer's reflection permanently decays.", {
            { type = "body_change", change = "decaying_reflection", permanent = true, affectsReflections = true, decaysOverTime = true, finalReflection = "bleached_white_skull" },
        }),
        [14] = entry(14, "Regional Blight", "The surrounding region suffers a severe blight.", {
            { type = "world_consequence", scope = "region", plantLife = "wither_and_die", stillbirths = true, civilizationConsequences = true },
        }),
    },

    weald = {
        [1] = entry(1, "Hairless Ape Omen", "A grotesque ape omen manifests and dies.", {
            { type = "omen" },
        }),
        [2] = entry(2, "Shrieker Bloom", "Shriekers make movement noisy enough to risk a Meatgrinder draw.", {
            { type = "room_hazard", hazard = "shriekers", movementRaisesRuckus = true, provokesMeatgrinderDraw = true },
        }),
        [3] = entry(3, "Thornburst", "Thorns fill the sorcerer's zone, Rooting everyone there.", {
            { type = "zone_condition", condition = "rooted", zone = "actor" },
        }),
        [4] = entry(4, "Underworld Weather", "Violent weather fills the local caverns.", {
            { type = "environment_shift", scope = "area", physicalManifestation = true, fillsCaverns = true, weatherTypes = { "torrential_rain", "blizzard", "simoom" } },
        }),
        [5] = entry(5, "Potion Detonation", "The sorcerer's carried potions explode and damage adjacent inventory.", {
            { type = "destroy_items", tag = "potion", owner = "actor" },
            { type = "gm_adjudicate", tag = "adjacent_inventory_ruin" },
        }),
        [6] = entry(6, "Lightning Through Metal", "Lightning Wounds everyone carrying metal in the room.", {
            { type = "room_metal_wound" },
        }),
        [7] = entry(7, "Animal Convergence", "Regional animals are drawn into the next watch.", {
            { type = "force_encounter", filter = "animals" },
        }),
        [8] = entry(8, "Wood Warps", "Wooden objects nearby are destroyed and related traps may trigger.", {
            { type = "destroy_items", material = "wood", scope = "room" },
        }),
        [9] = entry(9, "Earthquake", "Unstable structures nearby collapse.", {
            { type = "environment_shift", scope = "mile", radius = "one_mile", unstableStructuresDestroyed = true },
        }),
        [10] = entry(10, "Self-Ignition", "The sorcerer takes a Wound and burns until Recover or equivalent action.", {
            { type = "damage", amount = 1 },
            { type = "condition", condition = "burning", ["until"] = "recover", clothesAndGearOnFire = true, recoverActionRequired = true, gmArbitratedConsequences = true },
        }),
        [11] = entry(11, "Goat Legs", "The sorcerer's legs permanently change.", {
            { type = "body_change", change = "goat_legs", permanent = true, legs = "backwards", furred = true, resembles = "goat" },
        }),
        [12] = entry(12, "Fungal Growth", "A persistent fungal growth afflicts the sorcerer.", {
            { type = "condition", condition = "fungal_growth", ["until"] = "cured", permanent = true, edible = true, addictiveWhenEaten = true },
        }),
        [13] = entry(13, "Lycanthropy", "The sorcerer is Cursed with lycanthropy.", {
            { type = "condition", condition = "lycanthropy", ["until"] = "cured", permanent = true, moonTriggered = true, uncontrolled = true, violent = true },
            { type = "condition", condition = "cursed", ["until"] = "cured", permanent = true, curse = "lycanthropy" },
        }),
        [14] = entry(14, "Wild Hunt", "The guild becomes the quarry of a Wild Hunt.", {
            { type = "world_consequence", scope = "guild", tag = "wild_hunt", messenger = "gnome", headStartDays = 1, hunters = "wood_elves", intent = "kill_guild" },
        }),
    },

    weird = {
        [1] = entry(1, "Lost Voice", "The sorcerer is Silenced until the next Fool reshuffle.", {
            { type = "condition", condition = "silenced", ["until"] = "fool_reshuffle", relativesHearVoiceLater = true, voiceFromDarkness = true },
        }),
        [2] = entry(2, "Invisible Idol-Builders", "Nightmarish idols are rapidly assembled nearby.", {
            { type = "room_feature", feature = "nightmare_idols", builtByInvisibleHands = true, rapidlyBuilt = true, materials = "available_near_sorcerer", manifestation = "jungian" },
        }),
        [3] = entry(3, "Sleep Test", "Everyone in the room must test Wands or be Knocked Out.", {
            { type = "room_test", attribute = "wands", failCondition = "knocked_out" },
        }),
        [4] = entry(4, "Random Inspiration", "Everyone in the sorcerer's zone is Inspired with a random Disposition.", {
            { type = "zone_condition", condition = "inspired_random_disposition", zone = "actor" },
        }),
        [5] = entry(5, "Prophetic Mouth", "A Tylwyth-speaking mouth delivers a rumor until the next Fool reshuffle.", {
            { type = "condition", condition = "prophetic_mouth", ["until"] = "fool_reshuffle", language = "tylwyth", deliversRumor = true, drooling = true },
        }),
        [6] = entry(6, "Ooze Tears", "The sorcerer weeps small oozes into the dungeon.", {
            { type = "spawn", mobId = "small_ooze", count = "several", tears = "gooey_saline", crawlsAway = true, eatsAndGrows = true },
        }),
        [7] = entry(7, "Visible Interior", "The sorcerer becomes visibly skeletal until the next Fool reshuffle.", {
            { type = "condition", condition = "visible_interior", ["until"] = "fool_reshuffle", skinInvisible = true, organsInvisible = true, musclesInvisible = true, appearance = "animate_skeleton", horrifiesGMCharacters = true },
        }),
        [8] = entry(8, "Living Illusion", "The sorcerer becomes an illusion until the next Fool reshuffle.", {
            { type = "condition", condition = "living_illusion", ["until"] = "fool_reshuffle" },
        }),
        [9] = entry(9, "Rhymebound", "The sorcerer can only speak in rhyming couplets until after next Camp.", {
            { type = "condition", condition = "rhymebound", ["until"] = "next_camp_complete", speechForm = "rhyming_couplets", inCharacterSpeechOnly = true },
        }),
        [10] = entry(10, "Embodied Nightmare", "The sorcerer's worst nightmare manifests at the next Camp.", {
            { type = "delayed_consequence", timing = "next_camp_phase", step = 3, manifestation = "worst_nightmare", requiresPlayerGMDiscussion = true },
        }),
        [11] = entry(11, "Milky Pallor", "The sorcerer's coloring permanently pales.", {
            { type = "body_change", change = "milky_pallor", permanent = true, hairColor = "milky_white", skinColor = "milky_white", irisColor = "milky_white" },
        }),
        [12] = entry(12, "Third Eye", "The sorcerer grows a permanent third eye tied to Dwimmercraft.", {
            { type = "body_change", change = "third_eye", permanent = true, location = "forehead", opensOn = "dwimmercraft", otherwiseUnnoticeable = true },
        }),
        [13] = entry(13, "Hekatephage", "A magic-eating spirit follows the sorcerer until dealt with.", {
            { type = "spawn", mobId = "hekatephage", hostile = true, shrouded = true, intangible = true, followsSorcerer = true, devoursMagic = true, banishOrDefeatRequired = true, endsNonConcentrationSpells = true },
        }),
        [14] = entry(14, "Permanent Silence Curse", "The sorcerer is permanently Cursed with Silence but can still cast.", {
            { type = "condition", condition = "silenced", permanent = true, canCastSpells = true, illusoryTextSpeech = true },
            { type = "condition", condition = "cursed", permanent = true },
        }),
    },

    welkin = {
        [1] = entry(1, "Vicarious Healing", "Nearby players' adventurers are healed; the sorcerer takes matching Wounds.", {
            { type = "vicarious_healing", tag = "left_right_healing" },
        }),
        [2] = entry(2, "Celestial Boils", "The sorcerer takes a Wound and becomes Stressed.", {
            { type = "damage", amount = 1 },
            { type = "condition", condition = "stressed", painfulBoils = true, cause = "undiluted_celestial_radiation" },
        }),
        [3] = entry(3, "Tainted Rations", "Rations in the room become fleshly and unsafe unless purely vegan.", {
            { type = "taint_items", tag = "ration", scope = "room", exceptDiet = "vegan", taint = "celestial_flesh", unsafe = true },
            { type = "taint_items", tag = "water", scope = "room", taint = "blood", unsafe = true },
        }),
        [4] = entry(4, "Divine Locusts", "Metallic locusts destroy foliage on the dungeon level.", {
            { type = "environment_shift", scope = "level", locusts = true, hardGoldenMetallicShells = true, humanFaces = true, destroyFoliage = true, plantLife = "destroyed" },
        }),
        [5] = entry(5, "Angelic Chant", "Beautiful loud chanting makes stealth impossible until the next Fool reshuffle.", {
            { type = "condition", condition = "angelic_chant", ["until"] = "fool_reshuffle", musicBeautiful = true, musicLoud = true, stealthImpossible = true },
        }),
        [6] = entry(6, "Piteous Stigmata", "The sorcerer is Exhausted until prayer in the City.", {
            { type = "condition", condition = "exhausted", ["until"] = "city_prayer", stigmataOf = "Mythrys", prayerLocation = "mythraeum" },
        }),
        [7] = entry(7, "Weapons to Tools", "Non-iron weapons in the room permanently become similar tools.", {
            { type = "transform_items", from = "weapon", to = "tool", scope = "room", exceptMaterial = "iron" },
        }),
        [8] = entry(8, "Halo", "The sorcerer gains a halo that draws hostile spirit attention.", {
            { type = "condition", condition = "halo", ["until"] = "city_prayer", browHalo = true, suitablyImpressive = true, spiritsReactNegatively = true, spiritCombatPriority = true, prayerLocation = "mythraeum" },
        }),
        [9] = entry(9, "Ghostly Prophecy", "A ghostly hand writes a doom prophecy nearby.", {
            { type = "room_feature", feature = "doom_prophecy", writer = "ghostly_hand", language = "vetus", surface = "nearby", foretellsDoom = true, requirementsSpecific = true, requirementsUnlikely = true },
        }),
        [10] = entry(10, "Firstborn Doom", "A grim family tragedy is reported after returning to the City.", {
            { type = "delayed_consequence", timing = "return_to_city", target = "guild_parent_firstborns", death = true, runeName = "sorcerer" },
        }),
        [11] = entry(11, "Scarabs of Greed", "Precious coins and gems on the sorcerer become scarabs.", {
            { type = "transform_items", from = "treasure", to = "scarabs", owner = "actor" },
        }),
        [12] = entry(12, "Stone Twin", "An animate stone twin emerges to kill and replace the sorcerer.", {
            { type = "spawn", mobId = "stone_twin", hostile = true, appearance = "stony_twin", resemblesSorcerer = true, mission = "kill_and_replace_sorcerer" },
        }),
        [13] = entry(13, "Semi-Divine Pregnancy", "The sorcerer becomes Exhausted by a semi-divine pregnancy.", {
            { type = "condition", condition = "semi_divine_pregnancy", ["until"] = "term", monthsPregnant = 8, child = "semi_divine" },
            { type = "condition", condition = "exhausted", ["until"] = "term" },
            { type = "delayed_consequence", timing = "term", tag = "semi_divine_child" },
        }),
        [14] = entry(14, "Meteor Star", "A star foretells a district-destroying meteor.", {
            { type = "delayed_consequence", timing = "third_night", tag = "meteor_star", starColor = "discharge_brown" },
            { type = "world_consequence", scope = "city_district", tag = "meteor", randomDistrict = true, cityUninhabitableWeeks = true },
        }),
    },
}

local function normalizeBranch(branch)
    branch = tostring(branch or ""):lower()
    branch = branch:gsub("[^%w_]", "")
    return branch
end

function M.getRank(value)
    return RANKS[value]
end

function M.getEntry(branch, value)
    local tableForBranch = M.tables[normalizeBranch(branch)]
    if not tableForBranch then
        return nil
    end

    return tableForBranch[value]
end

function M.listEntries(branch)
    local tableForBranch = M.tables[normalizeBranch(branch)] or {}
    local entries = {}
    for value = 1, 14 do
        if tableForBranch[value] then
            entries[#entries + 1] = tableForBranch[value]
        end
    end
    return entries
end

return M
