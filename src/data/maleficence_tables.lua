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
            { type = "gm_adjudicate", tag = "disease" },
        }),
        [3] = entry(3, "Mass-Grave Stench", "Remaining in the area stresses the guild.", {
            { type = "area_condition", condition = "stressed", target = "guild" },
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
            { type = "condition", condition = "bloody_tears", ["until"] = "fool_reshuffle" },
        }),
        [8] = entry(8, "Undead Mark", "Undead are supernaturally drawn to the sorcerer until cleansed.", {
            { type = "condition", condition = "undead_mark", ["until"] = "cleansed" },
        }),
        [9] = entry(9, "Wayward Shadow", "The sorcerer's shadow leaves to cause trouble.", {
            { type = "condition", condition = "shadowless", ["until"] = "shadow_returns" },
        }),
        [10] = entry(10, "Parasitic Twin", "The sorcerer is Stunned for a watch as the maleficence passes.", {
            { type = "condition", condition = "stunned", duration = "watch" },
        }),
        [11] = entry(11, "Golden Eyes", "The sorcerer's eyes permanently change.", {
            { type = "body_change", change = "golden_eyes", permanent = true },
        }),
        [12] = entry(12, "Black Horns", "The sorcerer grows permanent horns.", {
            { type = "body_change", change = "black_horns", permanent = true },
        }),
        [13] = entry(13, "Decaying Reflection", "The sorcerer's reflection permanently decays.", {
            { type = "body_change", change = "decaying_reflection", permanent = true },
        }),
        [14] = entry(14, "Regional Blight", "The surrounding region suffers a severe blight.", {
            { type = "world_consequence", scope = "region" },
        }),
    },

    weald = {
        [1] = entry(1, "Hairless Ape Omen", "A grotesque ape omen manifests and dies.", {
            { type = "omen" },
        }),
        [2] = entry(2, "Shrieker Bloom", "Shriekers make movement noisy enough to risk a Meatgrinder draw.", {
            { type = "room_hazard", hazard = "shriekers" },
        }),
        [3] = entry(3, "Thornburst", "Thorns fill the sorcerer's zone, Rooting everyone there.", {
            { type = "zone_condition", condition = "rooted", zone = "actor" },
        }),
        [4] = entry(4, "Underworld Weather", "Violent weather fills the local caverns.", {
            { type = "environment_shift", scope = "area" },
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
            { type = "environment_shift", scope = "mile" },
        }),
        [10] = entry(10, "Self-Ignition", "The sorcerer takes a Wound and burns until Recover or equivalent action.", {
            { type = "damage", amount = 1 },
            { type = "condition", condition = "burning", ["until"] = "recover" },
        }),
        [11] = entry(11, "Goat Legs", "The sorcerer's legs permanently change.", {
            { type = "body_change", change = "goat_legs", permanent = true },
        }),
        [12] = entry(12, "Fungal Growth", "A persistent fungal growth afflicts the sorcerer.", {
            { type = "condition", condition = "fungal_growth", ["until"] = "cured" },
        }),
        [13] = entry(13, "Lycanthropy", "The sorcerer is Cursed with lycanthropy.", {
            { type = "condition", condition = "lycanthropy", permanent = true },
            { type = "condition", condition = "cursed", permanent = true },
        }),
        [14] = entry(14, "Wild Hunt", "The guild becomes the quarry of a Wild Hunt.", {
            { type = "world_consequence", scope = "guild" },
        }),
    },

    weird = {
        [1] = entry(1, "Lost Voice", "The sorcerer is Silenced until the next Fool reshuffle.", {
            { type = "condition", condition = "silenced", ["until"] = "fool_reshuffle" },
        }),
        [2] = entry(2, "Invisible Idol-Builders", "Nightmarish idols are rapidly assembled nearby.", {
            { type = "room_feature", feature = "nightmare_idols" },
        }),
        [3] = entry(3, "Sleep Test", "Everyone in the room must test Wands or be Knocked Out.", {
            { type = "room_test", attribute = "wands", failCondition = "knocked_out" },
        }),
        [4] = entry(4, "Random Inspiration", "Everyone in the sorcerer's zone is Inspired with a random Disposition.", {
            { type = "zone_condition", condition = "inspired_random_disposition", zone = "actor" },
        }),
        [5] = entry(5, "Prophetic Mouth", "A Tylwyth-speaking mouth delivers a rumor until the next Fool reshuffle.", {
            { type = "condition", condition = "prophetic_mouth", ["until"] = "fool_reshuffle" },
        }),
        [6] = entry(6, "Ooze Tears", "The sorcerer weeps small oozes into the dungeon.", {
            { type = "spawn", mobId = "small_ooze", count = "several" },
        }),
        [7] = entry(7, "Visible Interior", "The sorcerer becomes visibly skeletal until the next Fool reshuffle.", {
            { type = "condition", condition = "visible_interior", ["until"] = "fool_reshuffle" },
        }),
        [8] = entry(8, "Living Illusion", "The sorcerer becomes an illusion until the next Fool reshuffle.", {
            { type = "condition", condition = "living_illusion", ["until"] = "fool_reshuffle" },
        }),
        [9] = entry(9, "Rhymebound", "The sorcerer can only speak in rhyming couplets until after next Camp.", {
            { type = "condition", condition = "rhymebound", ["until"] = "next_camp_complete" },
        }),
        [10] = entry(10, "Embodied Nightmare", "The sorcerer's worst nightmare manifests at the next Camp.", {
            { type = "delayed_consequence", timing = "next_camp_phase" },
        }),
        [11] = entry(11, "Milky Pallor", "The sorcerer's coloring permanently pales.", {
            { type = "body_change", change = "milky_pallor", permanent = true },
        }),
        [12] = entry(12, "Third Eye", "The sorcerer grows a permanent third eye tied to Dwimmercraft.", {
            { type = "body_change", change = "third_eye", permanent = true },
        }),
        [13] = entry(13, "Hekatephage", "A magic-eating spirit follows the sorcerer until dealt with.", {
            { type = "spawn", mobId = "hekatephage", hostile = true },
        }),
        [14] = entry(14, "Permanent Silence Curse", "The sorcerer is permanently Cursed with Silence but can still cast.", {
            { type = "condition", condition = "silenced", permanent = true },
            { type = "condition", condition = "cursed", permanent = true },
        }),
    },

    welkin = {
        [1] = entry(1, "Vicarious Healing", "Nearby players' adventurers are healed; the sorcerer takes matching Wounds.", {
            { type = "gm_adjudicate", tag = "left_right_healing" },
        }),
        [2] = entry(2, "Celestial Boils", "The sorcerer takes a Wound and becomes Stressed.", {
            { type = "damage", amount = 1 },
            { type = "condition", condition = "stressed" },
        }),
        [3] = entry(3, "Tainted Rations", "Rations in the room become fleshly and unsafe unless purely vegan.", {
            { type = "destroy_items", tag = "ration", scope = "room" },
        }),
        [4] = entry(4, "Divine Locusts", "Metallic locusts destroy foliage on the dungeon level.", {
            { type = "environment_shift", scope = "level" },
        }),
        [5] = entry(5, "Angelic Chant", "Beautiful loud chanting makes stealth impossible until the next Fool reshuffle.", {
            { type = "condition", condition = "angelic_chant", ["until"] = "fool_reshuffle" },
        }),
        [6] = entry(6, "Piteous Stigmata", "The sorcerer is Exhausted until prayer in the City.", {
            { type = "condition", condition = "exhausted", ["until"] = "city_prayer" },
        }),
        [7] = entry(7, "Weapons to Tools", "Non-iron weapons in the room permanently become similar tools.", {
            { type = "transform_items", from = "weapon", to = "tool", scope = "room", exceptMaterial = "iron" },
        }),
        [8] = entry(8, "Halo", "The sorcerer gains a halo that draws hostile spirit attention.", {
            { type = "condition", condition = "halo", ["until"] = "city_prayer" },
        }),
        [9] = entry(9, "Ghostly Prophecy", "A ghostly hand writes a doom prophecy nearby.", {
            { type = "room_feature", feature = "doom_prophecy" },
        }),
        [10] = entry(10, "Firstborn Doom", "A grim family tragedy is reported after returning to the City.", {
            { type = "delayed_consequence", timing = "return_to_city" },
        }),
        [11] = entry(11, "Scarabs of Greed", "Precious coins and gems on the sorcerer become scarabs.", {
            { type = "transform_items", from = "treasure", to = "scarabs", owner = "actor" },
        }),
        [12] = entry(12, "Stone Twin", "An animate stone twin emerges to kill and replace the sorcerer.", {
            { type = "spawn", mobId = "stone_twin", hostile = true },
        }),
        [13] = entry(13, "Semi-Divine Pregnancy", "The sorcerer becomes Exhausted by a semi-divine pregnancy.", {
            { type = "condition", condition = "exhausted" },
            { type = "delayed_consequence", timing = "term" },
        }),
        [14] = entry(14, "Meteor Star", "A star foretells a district-destroying meteor.", {
            { type = "delayed_consequence", timing = "third_night" },
            { type = "world_consequence", scope = "city_district" },
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
