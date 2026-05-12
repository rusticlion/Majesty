-- city_phase.lua
-- Minimal City Phase action facade.

local events = require('logic.events')
local alchemy = require('logic.alchemy')
local camp_actions = require('logic.camp_actions')
local currency = require('logic.currency')
local constants = require('constants')
local inventory = require('logic.inventory')
local city_events = require('data.city_events')
local city_layout = require('logic.city_layout')
local item_templates = require('data.item_templates')
local spell_registry = require('data.spell_registry')
local talent_catalog = require('data.talent_catalog')
local fate_resolver = require('logic.resolver')

local M = {}

M.TAX_RATE = 0.5
M.TRAINING_COST_PER_XP = 50
M.BUILD_COST_PER_SYLLABLE = 50
M.FUNERAL_COST_PER_XP = 100
M.MAX_FAME = 5
M.MAX_MYTHRYS_INITIATION = 21
M.generateCityLayout = city_layout.generateCityLayout

M.COMMISSION_CRAFT_RATES = {
    farmer = 1,
    adventurer = 5,
    noble = 10,
    novel = 25,
}

M.STEPS = {
    DEATH_AND_TAXES = "death_and_taxes",
    NOTEWORTHY_DEEDS = "noteworthy_deeds",
    CITY_EVENTS = "city_events",
    TURN_IN_CONTRACTS = "turn_in_contracts",
    UPKEEP = "upkeep",
    CITY_ACTIONS = "city_actions",
    PLAN_NEXT_CRAWL = "plan_next_crawl",
    RESTOCK_UNDERWORLD = "restock_underworld",
}

M.UPKEEP_TIERS = {
    destitute = {
        id = "destitute",
        cost = 0,
        refillTier = nil,
        recoveryAllowed = false,
        luxurious = false,
    },
    impoverished = {
        id = "impoverished",
        cost = 25,
        refillTier = "impoverished",
        recoveryAllowed = false,
        luxurious = false,
    },
    common = {
        id = "common",
        cost = 50,
        refillTier = "common",
        recoveryAllowed = true,
        luxurious = false,
    },
    luxurious = {
        id = "luxurious",
        cost = 100,
        refillTier = "luxurious",
        recoveryAllowed = true,
        luxurious = true,
    },
}

M.ACTIONS = {
    BANKING = "banking",
    BEG_AND_BUSK = "beg_and_busk",
    BUILD = "build",
    CAMP_ACTION = "camp_action",
    CAROUSE = "carouse",
    CHOOSE_MONSTER_HUNTER_FOE = "choose_monster_hunter_foe",
    COMMISSION_CRAFT = "commission_craft",
    HOLD_FUNERAL = "hold_funeral",
    PREPARE_COMPONENTS = "prepare_components",
    PRAY_AT_MYTHRAEUM = "pray_at_mythraeum",
    TRAIN = "train",
    SUPPORT = "support",
    RESEARCH = "research",
    AS_ABOVE_SO_BELOW = "as_above_so_below",
    BLOOD_FEAST = "blood_feast",
    BUY_EXOTIC_DRUGS = "buy_exotic_drugs",
    MENAGERIE_REAGENT_PURCHASE = "menagerie_reagent_purchase",
    HARVEST_ALCHEMICAL_REAGENTS = "harvest_alchemical_reagents",
    BEG_FOR_SCRAPS = "beg_for_scraps",
    ATTEND_MISS_KINSEYS_DINING_CLUB = "attend_miss_kinseys_dining_club",
    COMMISSION_DWARVEN_MASTERCRAFT = "commission_dwarven_mastercraft",
    COMMISSION_GARGOYLE = "commission_gargoyle",
    COMMISSION_PUPPET = "commission_puppet",
    CONTRACT_ASSASSINATION = "contract_assassination",
    COPY_TEXTS = "copy_texts",
    ADOPT = "adopt",
    DISPOSE_OF_BODIES = "dispose_of_bodies",
    DOODLEBUG = "doodlebug",
    DOOMSAYING = "doomsaying",
    DUEL = "duel",
    EXPLORE_HANGMANS_HILL = "explore_hangmans_hill",
    EXCHANGE_GIFTS = "exchange_gifts",
    FENCE_GOODS = "fence_goods",
    FIT_PROSTHETICS = "fit_prosthetics",
    FIGHT = "fight",
    GET_AUTOGRAPHS = "get_autographs",
    GET_TATTOOS = "get_tattoos",
    HUFF_FUMES = "huff_fumes",
    ENTER_THE_UNDERWORLD = "enter_the_underworld",
    JOIN_BEGGARS_GUILD = "join_the_beggars_guild",
    JOIN_COURT_OF_WANDS = "join_the_court_of_wands",
    JOIN_SWORDWHORES = "join_the_swordwhores",
    ASSEMBLE_GOBLIN_HORDE = "assemble_goblin_horde",
    KEEP_AN_EAR_TO_THE_GROUND = "keep_an_ear_to_the_ground",
    LAY_HIGH = "lay_high",
    LOOSEN_LIPS = "loosen_lips",
    MAKEOVER = "makeover",
    MARRIAGE_FEAST = "marriage_feast",
    MUTATION = "mutation",
    PALE_PROPHECIES = "pale_prophecies",
    PILLOW_TALK = "pillow_talk",
    PICNIC = "picnic",
    PURCHASE_AMULETS = "purchase_amulets",
    PURCHASE_ANIMAL_COMPANION = "purchase_animal_companion",
    PURCHASE_FATE_HONEY = "purchase_fate_honey",
    PURCHASE_FIREWORKS = "purchase_fireworks",
    RESEARCH_A_NEW_SPELL = "research_a_new_spell",
    REST_AND_RECUPERATE = "rest_and_recuperate",
    SEAL_AWAY = "seal_away",
    SEEK_INITIATION = "seek_initiation",
    SEEK_TRUTH = "seek_truth",
    SEND_LETTER = "send_letter",
    SEEK_THE_CURSED_KING = "seek_the_cursed_king",
    SELL_REAGENT = "sell_reagent",
    SELL_REAGENTS = "sell_reagents",
    SPREAD_RUMORS = "spread_rumors",
    STRANGE_COMMUNIONS = "strange_communions",
    STUDY_LANGUAGE = "study_language",
    TAKE_OUT_LOAN = "take_out_a_loan",
    THE_PLAYS_THE_THING = "the_plays_the_thing",
    TRIAL_BY_COMBAT = "trial_by_combat",
    UNDERGO_LEECHING = "undergo_leeching",
    VISIT_GRAVE = "visit_grave",
    VISIT_THE_PIT = "visit_the_pit",
    WRESTLE_HERECLUS = "wrestle_hereclus",
}

M.DISTRICT_ACTION_ALIASES = {
    adopt = M.ACTIONS.ADOPT,
    as_above_so_below = M.ACTIONS.AS_ABOVE_SO_BELOW,
    attend_miss_kinseys_dining_club = M.ACTIONS.ATTEND_MISS_KINSEYS_DINING_CLUB,
    beg_for_scraps = M.ACTIONS.BEG_FOR_SCRAPS,
    blood_feast = M.ACTIONS.BLOOD_FEAST,
    buy_exotic_drugs = M.ACTIONS.BUY_EXOTIC_DRUGS,
    commission_dwarven_mastercraft = M.ACTIONS.COMMISSION_DWARVEN_MASTERCRAFT,
    commission_gargoyle = M.ACTIONS.COMMISSION_GARGOYLE,
    commission_puppet = M.ACTIONS.COMMISSION_PUPPET,
    contract_assassination = M.ACTIONS.CONTRACT_ASSASSINATION,
    copy_texts = M.ACTIONS.COPY_TEXTS,
    dispose_of_bodies = M.ACTIONS.DISPOSE_OF_BODIES,
    doodlebug = M.ACTIONS.DOODLEBUG,
    doomsaying = M.ACTIONS.DOOMSAYING,
    duel = M.ACTIONS.DUEL,
    explore_hangmans_hill = M.ACTIONS.EXPLORE_HANGMANS_HILL,
    exchange_gifts = M.ACTIONS.EXCHANGE_GIFTS,
    fence_goods = M.ACTIONS.FENCE_GOODS,
    fit_prosthetics = M.ACTIONS.FIT_PROSTHETICS,
    fight = M.ACTIONS.FIGHT,
    get_autographs = M.ACTIONS.GET_AUTOGRAPHS,
    get_tattoos = M.ACTIONS.GET_TATTOOS,
    huff_fumes = M.ACTIONS.HUFF_FUMES,
    enter_the_underworld = M.ACTIONS.ENTER_THE_UNDERWORLD,
    join_the_beggars_guild = M.ACTIONS.JOIN_BEGGARS_GUILD,
    join_the_court_of_wands = M.ACTIONS.JOIN_COURT_OF_WANDS,
    join_the_swordwhores = M.ACTIONS.JOIN_SWORDWHORES,
    keep_an_ear_to_the_ground = M.ACTIONS.KEEP_AN_EAR_TO_THE_GROUND,
    lay_high = M.ACTIONS.LAY_HIGH,
    loosen_lips = M.ACTIONS.LOOSEN_LIPS,
    harvest_alchemical_reagents = M.ACTIONS.MENAGERIE_REAGENT_PURCHASE,
    makeover = M.ACTIONS.MAKEOVER,
    marriage_feast = M.ACTIONS.MARRIAGE_FEAST,
    mutation = M.ACTIONS.MUTATION,
    pale_prophecies = M.ACTIONS.PALE_PROPHECIES,
    pillow_talk = M.ACTIONS.PILLOW_TALK,
    picnic = M.ACTIONS.PICNIC,
    purchase_amulets = M.ACTIONS.PURCHASE_AMULETS,
    purchase_animal_companion = M.ACTIONS.PURCHASE_ANIMAL_COMPANION,
    purchase_fate_honey = M.ACTIONS.PURCHASE_FATE_HONEY,
    purchase_fireworks = M.ACTIONS.PURCHASE_FIREWORKS,
    research_a_new_spell = M.ACTIONS.RESEARCH_A_NEW_SPELL,
    rest_and_recuperate = M.ACTIONS.REST_AND_RECUPERATE,
    seal_away = M.ACTIONS.SEAL_AWAY,
    seek_initiation = M.ACTIONS.SEEK_INITIATION,
    seek_truth = M.ACTIONS.SEEK_TRUTH,
    send_letter = M.ACTIONS.SEND_LETTER,
    seek_the_cursed_king = M.ACTIONS.SEEK_THE_CURSED_KING,
    sell_reagents = M.ACTIONS.SELL_REAGENT,
    spread_rumors = M.ACTIONS.SPREAD_RUMORS,
    strange_communions = M.ACTIONS.STRANGE_COMMUNIONS,
    study_language = M.ACTIONS.STUDY_LANGUAGE,
    take_out_a_loan = M.ACTIONS.TAKE_OUT_LOAN,
    the_plays_the_thing = M.ACTIONS.THE_PLAYS_THE_THING,
    trial_by_combat = M.ACTIONS.TRIAL_BY_COMBAT,
    undergo_leeching = M.ACTIONS.UNDERGO_LEECHING,
    visit_grave = M.ACTIONS.VISIT_GRAVE,
    visit_the_pit = M.ACTIONS.VISIT_THE_PIT,
    wrestle_hereclus = M.ACTIONS.WRESTLE_HERECLUS,
}

local ACTION_ALIASES = {
    banking = M.ACTIONS.BANKING,
    bank = M.ACTIONS.BANKING,
    beg_and_busk = M.ACTIONS.BEG_AND_BUSK,
    beg_busk = M.ACTIONS.BEG_AND_BUSK,
    beg = M.ACTIONS.BEG_AND_BUSK,
    build = M.ACTIONS.BUILD,
    camp_action = M.ACTIONS.CAMP_ACTION,
    camp = M.ACTIONS.CAMP_ACTION,
    perform_camp_action = M.ACTIONS.CAMP_ACTION,
    carouse = M.ACTIONS.CAROUSE,
    choose_monster_hunter_foe = M.ACTIONS.CHOOSE_MONSTER_HUNTER_FOE,
    change_monster_hunter_foe = M.ACTIONS.CHOOSE_MONSTER_HUNTER_FOE,
    monster_hunter_foe = M.ACTIONS.CHOOSE_MONSTER_HUNTER_FOE,
    choose_hated_foe = M.ACTIONS.CHOOSE_MONSTER_HUNTER_FOE,
    commission_craft = M.ACTIONS.COMMISSION_CRAFT,
    commission = M.ACTIONS.COMMISSION_CRAFT,
    craft = M.ACTIONS.COMMISSION_CRAFT,
    hold_funeral = M.ACTIONS.HOLD_FUNERAL,
    funeral = M.ACTIONS.HOLD_FUNERAL,
    prepare_components = M.ACTIONS.PREPARE_COMPONENTS,
    prepare_spell_components = M.ACTIONS.PREPARE_COMPONENTS,
    pray_at_mythraeum = M.ACTIONS.PRAY_AT_MYTHRAEUM,
    city_prayer = M.ACTIONS.PRAY_AT_MYTHRAEUM,
    pray = M.ACTIONS.PRAY_AT_MYTHRAEUM,
    train = M.ACTIONS.TRAIN,
    city_train = M.ACTIONS.TRAIN,
    support = M.ACTIONS.SUPPORT,
    support_project = M.ACTIONS.SUPPORT,
    research = M.ACTIONS.RESEARCH,
    as_above_so_below = M.ACTIONS.AS_ABOVE_SO_BELOW,
    stargaze = M.ACTIONS.AS_ABOVE_SO_BELOW,
    blood_feast = M.ACTIONS.BLOOD_FEAST,
    buy_exotic_drugs = M.ACTIONS.BUY_EXOTIC_DRUGS,
    buy_drugs = M.ACTIONS.BUY_EXOTIC_DRUGS,
    menagerie_reagent_purchase = M.ACTIONS.MENAGERIE_REAGENT_PURCHASE,
    harvest_alchemical_reagents = M.ACTIONS.MENAGERIE_REAGENT_PURCHASE,
    harvest_reagents_menagerie = M.ACTIONS.MENAGERIE_REAGENT_PURCHASE,
    adopt = M.ACTIONS.ADOPT,
    attend_miss_kinseys_dining_club = M.ACTIONS.ATTEND_MISS_KINSEYS_DINING_CLUB,
    miss_kinseys_dining_club = M.ACTIONS.ATTEND_MISS_KINSEYS_DINING_CLUB,
    beg_for_scraps = M.ACTIONS.BEG_FOR_SCRAPS,
    commission_dwarven_mastercraft = M.ACTIONS.COMMISSION_DWARVEN_MASTERCRAFT,
    dwarven_mastercraft = M.ACTIONS.COMMISSION_DWARVEN_MASTERCRAFT,
    commission_gargoyle = M.ACTIONS.COMMISSION_GARGOYLE,
    commission_puppet = M.ACTIONS.COMMISSION_PUPPET,
    contract_assassination = M.ACTIONS.CONTRACT_ASSASSINATION,
    assassinate = M.ACTIONS.CONTRACT_ASSASSINATION,
    copy_text = M.ACTIONS.COPY_TEXTS,
    copy_texts = M.ACTIONS.COPY_TEXTS,
    dispose_bodies = M.ACTIONS.DISPOSE_OF_BODIES,
    dispose_of_bodies = M.ACTIONS.DISPOSE_OF_BODIES,
    doodlebug = M.ACTIONS.DOODLEBUG,
    doodlebugging = M.ACTIONS.DOODLEBUG,
    doomsaying = M.ACTIONS.DOOMSAYING,
    duel = M.ACTIONS.DUEL,
    explore_hangmans_hill = M.ACTIONS.EXPLORE_HANGMANS_HILL,
    explore_hangmans_hill_at_night = M.ACTIONS.EXPLORE_HANGMANS_HILL,
    exchange_gifts = M.ACTIONS.EXCHANGE_GIFTS,
    gift_exchange = M.ACTIONS.EXCHANGE_GIFTS,
    fence = M.ACTIONS.FENCE_GOODS,
    fence_goods = M.ACTIONS.FENCE_GOODS,
    fit_prosthetics = M.ACTIONS.FIT_PROSTHETICS,
    fight = M.ACTIONS.FIGHT,
    fight_in_pits = M.ACTIONS.FIGHT,
    get_autograph = M.ACTIONS.GET_AUTOGRAPHS,
    get_autographs = M.ACTIONS.GET_AUTOGRAPHS,
    get_tattoo = M.ACTIONS.GET_TATTOOS,
    get_tattoos = M.ACTIONS.GET_TATTOOS,
    huff_fumes = M.ACTIONS.HUFF_FUMES,
    sacred_fumes = M.ACTIONS.HUFF_FUMES,
    enter_the_underworld = M.ACTIONS.ENTER_THE_UNDERWORLD,
    labyrinth_entry = M.ACTIONS.ENTER_THE_UNDERWORLD,
    join_beggars_guild = M.ACTIONS.JOIN_BEGGARS_GUILD,
    join_the_beggars_guild = M.ACTIONS.JOIN_BEGGARS_GUILD,
    join_court_of_wands = M.ACTIONS.JOIN_COURT_OF_WANDS,
    join_the_court_of_wands = M.ACTIONS.JOIN_COURT_OF_WANDS,
    join_swordwhores = M.ACTIONS.JOIN_SWORDWHORES,
    join_the_swordwhores = M.ACTIONS.JOIN_SWORDWHORES,
    assemble_goblin_horde = M.ACTIONS.ASSEMBLE_GOBLIN_HORDE,
    gather_goblin_horde = M.ACTIONS.ASSEMBLE_GOBLIN_HORDE,
    hatch_goblin_horde = M.ACTIONS.ASSEMBLE_GOBLIN_HORDE,
    gather_goblins = M.ACTIONS.ASSEMBLE_GOBLIN_HORDE,
    jarl = M.ACTIONS.ASSEMBLE_GOBLIN_HORDE,
    keep_an_ear_to_the_ground = M.ACTIONS.KEEP_AN_EAR_TO_THE_GROUND,
    hear_city_rumor = M.ACTIONS.KEEP_AN_EAR_TO_THE_GROUND,
    lay_high = M.ACTIONS.LAY_HIGH,
    hide_out = M.ACTIONS.LAY_HIGH,
    loosen_lips = M.ACTIONS.LOOSEN_LIPS,
    buy_drinks_for_answer = M.ACTIONS.LOOSEN_LIPS,
    makeover = M.ACTIONS.MAKEOVER,
    marriage_feast = M.ACTIONS.MARRIAGE_FEAST,
    mutation = M.ACTIONS.MUTATION,
    random_mutation = M.ACTIONS.MUTATION,
    pale_prophecies = M.ACTIONS.PALE_PROPHECIES,
    pillow_talk = M.ACTIONS.PILLOW_TALK,
    picnic = M.ACTIONS.PICNIC,
    purchase_amulets = M.ACTIONS.PURCHASE_AMULETS,
    buy_amulets = M.ACTIONS.PURCHASE_AMULETS,
    purchase_animal_companion = M.ACTIONS.PURCHASE_ANIMAL_COMPANION,
    purchase_companion = M.ACTIONS.PURCHASE_ANIMAL_COMPANION,
    buy_animal_companion = M.ACTIONS.PURCHASE_ANIMAL_COMPANION,
    purchase_fate_honey = M.ACTIONS.PURCHASE_FATE_HONEY,
    buy_fate_honey = M.ACTIONS.PURCHASE_FATE_HONEY,
    purchase_fireworks = M.ACTIONS.PURCHASE_FIREWORKS,
    buy_fireworks = M.ACTIONS.PURCHASE_FIREWORKS,
    research_a_new_spell = M.ACTIONS.RESEARCH_A_NEW_SPELL,
    spell_research = M.ACTIONS.RESEARCH_A_NEW_SPELL,
    rest_and_recuperate = M.ACTIONS.REST_AND_RECUPERATE,
    hospital_rest = M.ACTIONS.REST_AND_RECUPERATE,
    seal_away = M.ACTIONS.SEAL_AWAY,
    seal_abomination = M.ACTIONS.SEAL_AWAY,
    seek_initiation = M.ACTIONS.SEEK_INITIATION,
    mythrys_initiation = M.ACTIONS.SEEK_INITIATION,
    seek_truth = M.ACTIONS.SEEK_TRUTH,
    test_hypothesis = M.ACTIONS.SEEK_TRUTH,
    send_letter = M.ACTIONS.SEND_LETTER,
    seek_the_cursed_king = M.ACTIONS.SEEK_THE_CURSED_KING,
    cursed_king = M.ACTIONS.SEEK_THE_CURSED_KING,
    sell_reagent = M.ACTIONS.SELL_REAGENT,
    sell_reagents = M.ACTIONS.SELL_REAGENT,
    spread_rumor = M.ACTIONS.SPREAD_RUMORS,
    spread_rumors = M.ACTIONS.SPREAD_RUMORS,
    strange_communions = M.ACTIONS.STRANGE_COMMUNIONS,
    attend_communion = M.ACTIONS.STRANGE_COMMUNIONS,
    study_language = M.ACTIONS.STUDY_LANGUAGE,
    loan = M.ACTIONS.TAKE_OUT_LOAN,
    take_loan = M.ACTIONS.TAKE_OUT_LOAN,
    take_out_a_loan = M.ACTIONS.TAKE_OUT_LOAN,
    play = M.ACTIONS.THE_PLAYS_THE_THING,
    the_plays_the_thing = M.ACTIONS.THE_PLAYS_THE_THING,
    trial_by_combat = M.ACTIONS.TRIAL_BY_COMBAT,
    court_martial_trial = M.ACTIONS.TRIAL_BY_COMBAT,
    undergo_leeching = M.ACTIONS.UNDERGO_LEECHING,
    leeching = M.ACTIONS.UNDERGO_LEECHING,
    visit_grave = M.ACTIONS.VISIT_GRAVE,
    visit_the_pit = M.ACTIONS.VISIT_THE_PIT,
    wrestle_hereclus = M.ACTIONS.WRESTLE_HERECLUS,
}

local function districtActionAlias(actionId)
    return M.DISTRICT_ACTION_ALIASES[actionId] or ACTION_ALIASES[actionId]
end

local function findDistrictAction(cityLayout, actionId)
    for _, entry in ipairs(cityLayout and cityLayout.specialCityActions or {}) do
        local action = entry.action or {}
        if action.id == actionId then
            return entry
        end
    end
    return nil
end

M.HANGOVER_TABLE = {
    [1] = { id = "headache_windfall", title = "Headache Windfall" },
    [2] = { id = "stocks", title = "In the Stocks" },
    [3] = { id = "cowbell", title = "Cowbell Chain" },
    [4] = { id = "marriage_ring", title = "Marriage Ring" },
    [5] = { id = "angry_creditors", title = "Angry Creditors" },
    [6] = { id = "loose_finger", title = "Loose Finger" },
    [7] = { id = "high_priest", title = "High Priest" },
    [8] = { id = "tavern_ban", title = "Favorite Tavern Ban" },
    [9] = { id = "new_tattoo", title = "New Tattoo" },
    [10] = { id = "clothes_swap", title = "Alley Clothes Swap" },
    [11] = { id = "duel_invitation", title = "Duel Invitation" },
    [12] = { id = "cistern", title = "Cistern Awakening" },
    [13] = { id = "wanted_poster", title = "Wanted Posters" },
    [14] = { id = "soul_invoice", title = "Soul Invoice" },
    [15] = { id = "hogtied_noble", title = "Hogtied Noble" },
    [16] = { id = "broken_shop", title = "Broken Shop" },
    [17] = { id = "burning_water", title = "Burning Water" },
    [18] = { id = "dark_pact", title = "Dark Pact" },
    [19] = { id = "missing_hand", title = "Missing Hand" },
    [20] = { id = "candle_fire", title = "Candle Dare Fire" },
    [21] = { id = "puncture_marks", title = "Circular Punctures" },
}

M.DOOMSAYING_PROPHECY = {
    [1] = {
        [constants.SUITS.SWORDS] = { id = "beast_first_house", text = "The Beast enters the First House" },
        [constants.SUITS.PENTACLES] = { id = "grey_turns_red", text = "The Grey turns red" },
        [constants.SUITS.CUPS] = { id = "eldest_falls", text = "The eldest falls" },
        [constants.SUITS.WANDS] = { id = "western_sunrise", text = "The sun rises in the west" },
    },
    [2] = {
        [constants.SUITS.SWORDS] = { id = "hunger_loosed", text = "Hunger is loosed" },
        [constants.SUITS.PENTACLES] = { id = "last_queen_blinded", text = "The Last Queen blinds herself" },
        [constants.SUITS.CUPS] = { id = "second_mouth_sings", text = "A second mouth begins to sing" },
        [constants.SUITS.WANDS] = { id = "earth_birth_pangs", text = "The earth groans with birth pangs" },
    },
    [3] = {
        [constants.SUITS.SWORDS] = { id = "moon_dies", text = "The moon dies" },
        [constants.SUITS.PENTACLES] = { id = "new_river_rises", text = "A new river rises" },
        [constants.SUITS.CUPS] = { id = "new_star_kindled", text = "A new star is kindled" },
        [constants.SUITS.WANDS] = { id = "worm_arises", text = "His Majesty the Worm arises" },
    },
    [4] = {
        [constants.SUITS.SWORDS] = { id = "ascend_heaven", text = "Ascend the stairs of Heaven" },
        [constants.SUITS.PENTACLES] = { id = "seven_crowns_stolen", text = "The seven crowns are stolen" },
        [constants.SUITS.CUPS] = { id = "blood_blasphemy_sung", text = "The Blood Blasphemy is sung again" },
        [constants.SUITS.WANDS] = { id = "clarion_wound", text = "The Clarion of Altheia is wound" },
    },
}

M.MARKET_TIERS = {
    -- Current item-template subset of the Omphalic Market.
    animal_feed = "impoverished",
    bedroll = "impoverished",
    candles = "impoverished",
    chalk = "impoverished",
    clothes_rags = "impoverished",
    dagger = "impoverished",
    firewood = "impoverished",
    flint_and_tinder = "impoverished",
    lard = "impoverished",
    leeches = "impoverished",
    pipeweed = "impoverished",
    pole_10ft = "impoverished",
    poultice = "impoverished",
    ration = "impoverished",
    rations_3 = "impoverished",
    religious_paraphernalia = "impoverished",
    rope = "impoverished",
    rusty_sword = "impoverished",
    bow = "impoverished",
    crossbow = "impoverished",
    longsword = "impoverished",

    blank_book = "common",
    caltrops = "common",
    chain_10ft = "common",
    clothes_common = "common",
    cooking_gear = "common",
    crowbar = "common",
    fishing_gear = "common",
    garlic = "common",
    grappling_hook = "common",
    hammer = "common",
    hatchet = "common",
    helm = "common",
    hermetic_bottle = "common",
    iron_spikes = "common",
    light_armor = "common",
    lockpicks = "common",
    mirror = "common",
    musical_instrument = "common",
    pick = "common",
    quill_and_ink = "common",
    shield_light = "common",
    shovel = "common",
    tinkers_kit = "common",
    torch = "common",
    wolfsbane = "common",

    alchemy_kit = "luxurious",
    bezoar = "luxurious",
    booze_fancy = "luxurious",
    clothes_finery = "luxurious",
    falconry_gear = "luxurious",
    hourglass = "luxurious",
    iron_armor = "luxurious",
    lantern = "luxurious",
    manacles = "luxurious",
    oil = "luxurious",
    salt = "luxurious",
    shield_heavy = "luxurious",
    silver_longsword = "luxurious",
    spyglass = "luxurious",
    steel_armor = "luxurious",
    tent = "luxurious",
    wand_archwood = "luxurious",
}

local EXOTIC_DRUGS = {
    black_honey = {
        id = "black_honey",
        name = "Black Honey",
        cost = 35,
        affliction = "black_honey",
        stageEffects = {
            [1] = "May draw five Challenge cards instead of four, then spit out 1-4 teeth.",
            [2] = "Cups equals 1; disfavor on fine motor tests of fate.",
        },
        quitCharges = 5,
    },
    ghost_lotus = {
        id = "ghost_lotus",
        name = "Ghost Lotus",
        cost = 5,
        affliction = "ghost_lotus",
        stageEffects = {
            [1] = "Euphoria cancels effects that hamper sleep.",
            [2] = "Cannot read or write and is immune to illusions.",
            [3] = "Rewrite one motif descriptor.",
        },
    },
}

local HUNTER_DEFAULT_FOES = {
    beast_hunter = "Beast",
    elemental_hunter = "Elemental",
    man_hunter = "Man",
    spirit_hunter = "Spirit",
    undead_hunter = "Undead",
    witch_hunter = "Witch",
}

local HUNTER_TALENT_IDS = {
    "monster_hunter",
    "beast_hunter",
    "elemental_hunter",
    "man_hunter",
    "spirit_hunter",
    "undead_hunter",
    "witch_hunter",
}

local HUNTER_FOE_LABELS = {
    beast = "Beast",
    elemental = "Elemental",
    man = "Man",
    spirit = "Spirit",
    undead = "Undead",
    witch = "Witch",
}

local MARKET_TIER_RANK = {
    impoverished = 1,
    common = 2,
    luxurious = 3,
}

local CONTRACT_CARD_RANKS = {
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

M.EXAMPLE_CONTRACTS = {
    [1] = {
        id = "tricky_woo",
        title = "Return Tricky Woo",
        patron = "Lady Lumphrey",
        hook = "A cherished pet has run into the Mouth of the Underworld.",
        objective = "Return Tricky Woo safely.",
        rewardGoldPerMember = 100,
        rewardNote = "100g to each guild member, plus a will promise.",
        contractType = "rescue",
    },
    [2] = {
        id = "lyfitt_crowell",
        title = "Find Lyfitt Crowell",
        patron = "Miranda Crowell",
        hook = "A missing husband disappeared in the Underworld.",
        objective = "Bring Lyfitt Crowell back alive.",
        rewardNote = "Miranda offers what she can.",
        contractType = "rescue",
    },
    [3] = {
        id = "pash_torchier",
        title = "Retrieve Pash the Torchier",
        patron = "Mirima Merriweather",
        hook = "A young heir has decided he is an adventurer.",
        objective = "Bring Pash back alive.",
        rewardNote = "The guild may keep Pash's adventuring gear.",
        contractType = "rescue",
    },
    [4] = {
        id = "underhill_cockatrice",
        title = "Capture a Cockatrice",
        patron = "Master Hugo Underhill",
        hook = "The Malign Menagerie wants a living cockatrice specimen.",
        objective = "Capture, do not kill or injure, the cockatrice.",
        rewardGold = 1000,
        rewardNote = "Worth up to 1000g if pristine.",
        contractType = "capture",
    },
    [5] = {
        id = "onion_jack",
        title = "Bounty on Onion Jack",
        patron = "Lord Captain Barlett",
        hook = "The head of the All-Watch has posted a bounty.",
        objective = "Bring Onion Jack back alive.",
        rewardGold = 500,
        contractType = "bounty",
    },
    [6] = {
        id = "dire_spider_silk",
        title = "Harvest Dire Spider Silk",
        patron = "Anhilda Weaver",
        hook = "The Colonies need rare silk from dire spiders.",
        objective = "Return with usable dire spider silk.",
        rewardNote = "Fine garments woven from spider silk.",
        contractType = "gather",
    },
    [7] = {
        id = "grimnir_gold_ring",
        title = "Recover a Gold Ring",
        patron = "Annatar Giftgiver",
        hook = "Grinnin' Grimnir, an Underworld peddler, carries the patron's ring.",
        objective = "Return the ring.",
        rewardNote = "Handsome payment.",
        contractType = "recover",
    },
    [8] = {
        id = "ogre_heads_mythrii",
        title = "Ogre Heads for Athleta Mythrii",
        patron = "Ser Francis Oddwold",
        hook = "The Temple Militant accepts proof of worthy violence.",
        objective = "Deliver ogre heads.",
        rewardNote = "Each head buys one adventurer passage into Athleta Mythrii.",
        contractType = "slay",
    },
    [9] = {
        id = "crossed_destinies_wedding",
        title = "Wedding at the Castle of Crossed Destinies",
        patron = "Master Alonz and Mistress Sara Pennywise",
        hook = "A couple wants a Mythric cleric to wed them in the Underworld.",
        objective = "Escort or secure the wedding ceremony.",
        rewardNote = "Wedding invitation and station-appropriate gifts.",
        contractType = "escort",
    },
    [10] = {
        id = "phoenix_feather",
        title = "Phoenix Feather",
        patron = "Lady Mary Arzon",
        hook = "A noble searches for a still-burning phoenix feather.",
        objective = "Return a phoenix feather while keeping it aflame.",
        rewardNote = "Great riches.",
        contractType = "recover",
    },
    [11] = {
        id = "undine_elemental_water",
        title = "Jar of Elemental Water",
        patron = "Church of the Maiden Wisdom",
        hook = "The church wants water taken from an undine.",
        objective = "Bring back a jar of elemental water.",
        rewardNote = "A prophecy.",
        contractType = "gather",
    },
    [12] = {
        id = "sealed_slime_bottles",
        title = "Sealed Slime Bottles",
        patron = "Hermanos the Wise",
        hook = "Slime is needed to make Takalashi Jelly.",
        objective = "Return sealed slime bottles.",
        rewardPerItem = 5,
        rewardNote = "5g per sealed bottle.",
        contractType = "gather",
    },
    [13] = {
        id = "brom_moral_luck",
        title = "News of Brom of House Noname",
        patron = "The Cult",
        hook = "A revered seeker retreated below to meditate on life and death.",
        objective = "If alive, ask Brom about moral luck; if dead, recover a relic.",
        rewardNote = "Cult favor.",
        contractType = "inquire",
    },
    [14] = {
        id = "gardener_mushroom_notes",
        title = "Gardener's Mushroom Field Notes",
        patron = "Thomlin Gardener",
        hook = "The Alchemist's Guild needs field research on unusual mushrooms.",
        objective = "Record formula exposure on three mushroom types, with samples if possible.",
        rewardNote = "Pay commensurate with detail and samples.",
        contractType = "research",
    },
}

local function normalizeActionId(actionId)
    return ACTION_ALIASES[tostring(actionId or "")] or tostring(actionId or "")
end

local function actorId(actor)
    return actor and (actor.id or actor.name)
end

local function getMythrysMembership(actor)
    local memberships = actor and actor.memberships
    if type(memberships) ~= "table" then
        return nil
    end
    return memberships.cult_of_mythrys or memberships.mythrys or memberships.cultOfMythrys
end

function M.getMythrysInitiationRank(actor)
    local membership = getMythrysMembership(actor)
    return math.max(0, math.floor(tonumber(membership and (membership.rank or membership.initiationRank)) or 0))
end

function M.hasMythrysInitiationFavor(actor, target)
    local actorRank = M.getMythrysInitiationRank(actor)
    local targetRank = M.getMythrysInitiationRank(target)
    return actorRank > 0 and targetRank > 0 and actorRank > targetRank
end

local function normalizeUpkeepTier(tier)
    return tostring(tier or ""):lower():gsub("%s+", "_")
end

local function isActiveAdventurer(actor)
    return actor and not (actor.conditions and actor.conditions.dead)
end

local function getWands(actor)
    if actor and actor.getAttribute then
        return actor:getAttribute(constants.SUITS.WANDS)
    end
    return tonumber(actor and actor.wands) or 0
end

local function getSwords(actor)
    if actor and actor.getAttribute then
        return actor:getAttribute(constants.SUITS.SWORDS)
    end
    return tonumber(actor and actor.swords) or 0
end

local function getCups(actor)
    if actor and actor.getAttribute then
        return actor:getAttribute(constants.SUITS.CUPS)
    end
    return tonumber(actor and actor.cups) or 0
end

local function addXP(actor, amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if not actor or amount <= 0 then
        return false
    end
    actor.xp = (tonumber(actor.xp) or 0) + amount
    return true
end

local function normalizeList(value)
    if not value then
        return {}
    end
    if type(value) == "table" then
        return value
    end
    return { value }
end

local function normalizeLanguage(value)
    if type(value) ~= "string" then
        return nil
    end
    local normalized = value:lower()
    normalized = normalized:gsub("^%s+", ""):gsub("%s+$", "")
    normalized = normalized:gsub("[%s%-]+", "_")
    return normalized ~= "" and normalized or nil
end

local function languageListHas(source, language)
    language = normalizeLanguage(language)
    if not language then
        return false
    end
    if type(source) == "string" then
        return normalizeLanguage(source) == language
    end
    if type(source) == "table" then
        if source[language] == true then
            return true
        end
        for _, item in ipairs(source) do
            if normalizeLanguage(item) == language then
                return true
            end
        end
    end
    return false
end

local function normalizeInitiationAnswer(value)
    if type(value) ~= "string" then
        return nil
    end
    local normalized = value:lower()
    normalized = normalized:gsub("^%s+", ""):gsub("%s+$", "")
    normalized = normalized:gsub("%s+", " ")
    return normalized ~= "" and normalized or nil
end

local function slugify(value)
    local slug = tostring(value or ""):lower():gsub("[^%w]+", "_")
    slug = slug:gsub("^_+", ""):gsub("_+$", "")
    return slug ~= "" and slug or "card"
end

local function shallowClone(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, entry in pairs(value) do
        copy[key] = shallowClone(entry)
    end
    return copy
end

local function contractCardValue(card)
    local value = math.floor(tonumber(card and card.value) or -1)
    if value >= 1 and value <= 14 then
        return value
    end
    return nil
end

local function generateContractOffer(card, index, opts)
    opts = opts or {}
    local value = contractCardValue(card)
    if not value then
        return nil, "Job board cards must map to contracts I through King"
    end

    local template = M.EXAMPLE_CONTRACTS[value]
    if not template then
        return nil, "Job board contract table entry missing"
    end

    local offer = shallowClone(template)
    local suitName = constants.SUIT_NAMES[card and card.suit] or card and card.suitName
    local prefix = opts.idPrefix or opts.boardId or "job_board"
    offer.id = string.format("%s_%02d_%s_%s", slugify(prefix), index, template.id, slugify(suitName or card and card.name))
    offer.templateId = template.id
    offer.name = offer.name or offer.title
    offer.status = offer.status or "offered"
    offer.generated = true
    offer.source = "rulebook_example_contracts"
    offer.card = card
    offer.cardValue = value
    offer.cardRank = CONTRACT_CARD_RANKS[value]
    offer.cardSuit = suitName

    return offer
end

local function normalizeGearRequests(value)
    local requests = {}
    for _, entry in ipairs(normalizeList(value)) do
        if type(entry) == "table" then
            local templateId = entry.templateId or entry.itemTemplate or entry.itemId or entry.id or entry[1]
            requests[#requests + 1] = {
                templateId = templateId,
                quantity = math.max(1, math.floor(tonumber(entry.quantity or entry.count) or 1)),
                location = entry.location or inventory.LOCATIONS.PACK,
            }
        else
            requests[#requests + 1] = {
                templateId = entry,
                quantity = 1,
                location = inventory.LOCATIONS.PACK,
            }
        end
    end
    return requests
end

local function normalizeRepairRequests(value)
    local requests = {}
    for _, entry in ipairs(normalizeList(value)) do
        if type(entry) == "table" then
            requests[#requests + 1] = {
                itemId = entry.itemId or entry.id or entry[1],
                templateId = entry.templateId or entry.itemTemplate,
                tier = entry.tier or entry.marketTier,
            }
        else
            requests[#requests + 1] = {
                itemId = entry,
            }
        end
    end
    return requests
end

local function canBuyMarketTier(upkeepTier, itemTier)
    local upkeepRank = MARKET_TIER_RANK[upkeepTier]
    local itemRank = MARKET_TIER_RANK[itemTier]
    return upkeepRank ~= nil and itemRank ~= nil and itemRank <= upkeepRank
end

local function hasMaledictionFlag(actor, flag)
    if not actor then
        return false
    end
    if actor[flag] == true then
        return true
    end

    local malediction = actor.malediction
    local curse = malediction and malediction.curse
    local flags = curse and curse.flags
    return malediction and malediction.active ~= false and flags and flags[flag] == true
end

local function maledictionMetadata(actor)
    local malediction = actor and actor.malediction
    if malediction and malediction.active ~= false then
        return malediction.metadata or {}
    end
    return {}
end

local function firstProvided(...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if value ~= nil then
            return value
        end
    end
    return nil
end

local function nextRecoveryWoundResult(actor)
    if not actor or not actor.conditions then
        return nil
    end
    if actor.conditions.deaths_door then
        return "deaths_door_healed"
    end
    if actor.conditions.stressed then
        return nil
    end
    if actor.conditions.injured then
        return "injured_healed"
    end
    if actor.conditions.staggered then
        return "staggered_healed"
    end
    if (actor.woundedTalents or 0) > 0 then
        return "talent_healed"
    end
    if (actor.armorNotches or 0) > 0 then
        return "armor_repaired"
    end
    return "fully_healed"
end

local function recoveryNeedsExtraBond(actor)
    if not hasMaledictionFlag(actor, "maledictionExtraBondRecoveryCost") then
        return false
    end
    local nextResult = nextRecoveryWoundResult(actor)
    return nextResult == "injured_healed" or nextResult == "talent_healed"
end

local function selectExtraRecoveryBond(actor, primaryBondTargetId, opts)
    opts = opts or {}
    local requested = opts.extraBondTargetId or opts.secondBondTargetId or
        opts.additionalBondTargetId or opts.extraRecoveryBondTargetId
    if requested and requested == primaryBondTargetId then
        return nil, "Second recovery Bond must be different"
    end
    if requested then
        local bond = actor.bonds and actor.bonds[requested]
        if not bond or not bond.charged then
            return nil, "Requires two charged Bonds"
        end
        return requested, nil
    end

    for targetId, bond in pairs(actor.bonds or {}) do
        if targetId ~= primaryBondTargetId and bond.charged then
            return targetId, nil
        end
    end

    return nil, "Requires two charged Bonds"
end

local function indexedOpt(value, index, actor)
    if type(value) ~= "table" then
        return value
    end
    if value[index] ~= nil then
        return value[index]
    end
    local id = actorId(actor)
    if id and value[id] ~= nil then
        return value[id]
    end
    return nil
end

local function dogCurseCityOutcome(actor, opts, index)
    opts = opts or {}
    if not hasMaledictionFlag(actor, "cityPhaseDogCurse") then
        return nil
    end

    local explicit = indexedOpt(firstProvided(
        opts.dogCurseCondition,
        opts.dogCurseOutcome,
        opts.cityPhaseDogCurse
    ), index, actor)
    if explicit ~= nil then
        explicit = tostring(explicit):lower()
        if explicit == "staggered" or explicit == "stressed" then
            return explicit
        end
        return explicit == "true" and "staggered" or nil
    end

    local metadata = maledictionMetadata(actor)
    local chances = metadata.cityPhaseConditionChance or {}
    local staggeredChance = tonumber(chances.staggered) or 0.5
    local roll = indexedOpt(firstProvided(opts.dogCurseRoll, opts.cityPhaseDogCurseRoll), index, actor)
    if roll ~= nil then
        return (tonumber(roll) or 1) <= staggeredChance and "staggered" or "stressed"
    end

    return math.random() <= staggeredChance and "staggered" or "stressed"
end

local function itemMarketTier(item, request)
    return request and request.tier or
           M.MARKET_TIERS[request and request.templateId] or
           M.MARKET_TIERS[item and item.templateId] or
           (item and item.properties and item.properties.marketTier)
end

local function normalizeActionSet(actions)
    if actions == "all" then
        return "all"
    end

    local set = {}
    for _, action in ipairs(normalizeList(actions)) do
        set[normalizeActionId(action)] = true
    end
    return set
end

local function mergeAllowedActionSet(current, incoming)
    if incoming == nil or incoming == "all" then
        return current
    end
    if not current then
        return incoming
    end

    local merged = {}
    for actionId in pairs(current) do
        if incoming[actionId] then
            merged[actionId] = true
        end
    end
    return merged
end

local function mergeBlockedActionSet(current, incoming)
    if incoming == nil then
        return current
    end
    if current == "all" or incoming == "all" then
        return "all"
    end

    current = current or {}
    for actionId in pairs(incoming) do
        current[actionId] = true
    end
    return current
end

local function mergeCityEventEffects(target, effects)
    target = target or {}
    effects = effects or {}

    if effects.upkeepCosts then
        target.upkeepCosts = target.upkeepCosts or {}
        for tierId, cost in pairs(effects.upkeepCosts) do
            target.upkeepCosts[normalizeUpkeepTier(tierId)] = math.max(0, math.floor(tonumber(cost) or 0))
        end
    end

    if effects.allowedCityActions ~= nil then
        target.allowedCityActions = mergeAllowedActionSet(target.allowedCityActions, normalizeActionSet(effects.allowedCityActions))
    end
    if effects.blockedCityActions ~= nil then
        target.blockedCityActions = mergeBlockedActionSet(target.blockedCityActions, normalizeActionSet(effects.blockedCityActions))
    end

    for key, value in pairs(effects) do
        if key ~= "upkeepCosts" and key ~= "allowedCityActions" and key ~= "blockedCityActions" then
            target[key] = value
        end
    end

    return target
end

local function activeAdventurers(guild)
    local active = {}
    for _, actor in ipairs(guild or {}) do
        if isActiveAdventurer(actor) then
            active[#active + 1] = actor
        end
    end
    return active
end

local function isContractComplete(contract)
    return contract and (
        contract.completed == true or
        contract.fulfilled == true or
        contract.status == "completed" or
        contract.status == "fulfilled"
    )
end

local function contractId(contract)
    return contract and (contract.id or contract.name or contract.title)
end

local function findContractById(contracts, id)
    local wanted = tostring(id or "")
    for _, contract in ipairs(contracts or {}) do
        if tostring(contractId(contract) or "") == wanted then
            return contract
        end
    end
    return nil
end

local function replacementEntries(replacements)
    local out = {}
    if type(replacements) ~= "table" then
        return out
    end

    if #replacements > 0 then
        for _, replacement in ipairs(replacements) do
            out[#out + 1] = replacement
        end
        return out
    end

    for key, entry in pairs(replacements) do
        if type(entry) == "table" then
            local replacement = {}
            for k, v in pairs(entry) do
                replacement[k] = v
            end
            replacement.key = replacement.key or key
            replacement.value = replacement.value or (type(key) == "number" and key or nil)
            out[#out + 1] = replacement
        else
            out[#out + 1] = {
                key = key,
                entry = entry,
            }
        end
    end
    return out
end

local function applyTableReplacements(tableRef, replacements)
    local details = {}
    if type(tableRef) ~= "table" then
        return details
    end

    for _, replacement in ipairs(replacementEntries(replacements)) do
        local key = replacement.key or replacement.value or replacement.cardValue or replacement.index or replacement.category
        if key ~= nil then
            local newEntry = replacement.entry or replacement.replacement or replacement.newEntry or replacement
            local oldEntry = tableRef[key]
            tableRef[key] = newEntry
            details[#details + 1] = {
                key = key,
                oldEntry = oldEntry,
                newEntry = newEntry,
            }
        end
    end
    return details
end

local function hasContract(contracts, contract)
    local id = contractId(contract)
    if not id then
        return false
    end
    return findContractById(contracts, id) ~= nil
end

local function contractRewardGold(contract)
    local quantity = tonumber(contract.quantity or contract.deliveredCount or contract.count) or 1
    local perItem = tonumber(contract.rewardPerItem or contract.goldPerItem or contract.rewardGoldPerItem)
    if perItem then
        return math.max(0, math.floor(perItem * quantity))
    end
    return math.max(0, math.floor(tonumber(contract.rewardGold or contract.gold or contract.reward) or 0))
end

function M.generateJobBoard(opts)
    opts = opts or {}

    local cards = normalizeList(opts.jobBoardCards or opts.contractCards or opts.cards)
    local drawnFromDeck = false
    local deck = opts.deck or opts.playerDeck or opts.minorDeck
    local skippedCards = {}
    if #cards == 0 and deck and deck.draw then
        local count = math.floor(tonumber(opts.count or opts.cardCount) or 5)
        local maxDraws = math.max(count, math.floor(tonumber(opts.maxDraws) or (count + 10)))
        local drawAttempts = 0
        while #cards < count do
            drawAttempts = drawAttempts + 1
            if drawAttempts > maxDraws then
                return nil, "Job board deck did not yield enough contract cards"
            end
            local card = deck:draw()
            if not card then
                return nil, "Job board deck ran out of cards"
            end
            if contractCardValue(card) then
                cards[#cards + 1] = card
            else
                skippedCards[#skippedCards + 1] = card
                if opts.discardDraws ~= false and deck.discard then
                    deck:discard(card)
                end
            end
        end
        drawnFromDeck = true
    end

    if #cards == 0 then
        return nil, "Job board generation requires cards or a deck"
    end

    if opts.allowNonStandardCount ~= true and (#cards < 4 or #cards > 6) then
        return nil, "Job board should offer four to six contracts"
    end

    local offers = {}
    for index, card in ipairs(cards) do
        local offer, err = generateContractOffer(card, index, opts)
        if not offer then
            return nil, err
        end
        offers[#offers + 1] = offer
    end

    if drawnFromDeck and opts.discardDraws ~= false and deck and deck.discard then
        for _, card in ipairs(cards) do
            deck:discard(card)
        end
    end

    return offers, {
        cards = cards,
        cardCount = #cards,
        drawnFromDeck = drawnFromDeck,
        skippedCards = skippedCards,
        result = "job_board_generated",
    }
end

local function normalizeRecipientList(recipients)
    if not recipients then
        return {}
    end
    if actorId(recipients) then
        return { recipients }
    end
    return recipients
end

local function distributeGold(total, recipients, guildTreasury)
    total = math.max(0, math.floor(tonumber(total) or 0))
    recipients = normalizeRecipientList(recipients)
    if total <= 0 or #recipients == 0 then
        if total > 0 and guildTreasury then
            guildTreasury.gold = (tonumber(guildTreasury.gold) or 0) + total
        end
        return {
            total = total,
            perRecipient = 0,
            remainder = total,
            recipients = {},
        }
    end

    local perRecipient = math.floor(total / #recipients)
    local remainder = total - (perRecipient * #recipients)
    local details = {}
    for _, recipient in ipairs(recipients) do
        if perRecipient > 0 then
            currency.addGold(recipient, perRecipient)
        end
        details[#details + 1] = {
            actor = recipient,
            actorId = actorId(recipient),
            gold = perRecipient,
        }
    end

    if remainder > 0 and guildTreasury then
        guildTreasury.gold = (tonumber(guildTreasury.gold) or 0) + remainder
    end

    return {
        total = total,
        perRecipient = perRecipient,
        remainder = remainder,
        recipients = details,
    }
end

local function isTreasureItem(item)
    local props = item and item.properties or {}
    return item and currency.isCurrencyItem(item) ~= true and (
        props.treasure == true or
        props.jewelry == true or
        props.art == true or
        props.extravagance == true or
        props.saleValue ~= nil or
        props.value ~= nil
    )
end

local function treasureSaleValue(item, explicitValue)
    local props = item and item.properties or {}
    return math.max(0, math.floor(tonumber(explicitValue or props.saleValue or props.value) or 0))
end

local function normalizeDeedId(description)
    return tostring(description or ""):lower():gsub("%s+", "_"):gsub("[^%w_]", "")
end

local function normalizeDeed(deed)
    if type(deed) == "table" then
        local description = deed.description or deed.title or deed.name or deed.id
        if not description or tostring(description) == "" then
            return nil
        end
        return {
            id = deed.id or normalizeDeedId(description),
            description = tostring(description),
            title = deed.title or deed.name or tostring(description),
            approved = deed.approved ~= false and deed.noteworthy ~= false,
            source = deed.source,
        }
    end

    if deed == nil or tostring(deed) == "" then
        return nil
    end
    return {
        id = normalizeDeedId(deed),
        description = tostring(deed),
        title = tostring(deed),
        approved = true,
    }
end

local function normalizeDeedList(deeds)
    local out = {}
    if type(deeds) == "table" and (deeds.description or deeds.title or deeds.name or deeds.id) then
        deeds = { deeds }
    end
    for _, deed in ipairs(normalizeList(deeds)) do
        local normalized = normalizeDeed(deed)
        if normalized then
            out[#out + 1] = normalized
        end
    end
    return out
end

local function selectedDeedSet(opts)
    local selected = opts.selectedDeedIds or opts.keepDeedIds or opts.selectedDeeds
    if not selected then
        return nil
    end
    local set = {}
    for _, value in ipairs(normalizeList(selected)) do
        local id = type(value) == "table" and (value.id or value.description or value.title or value.name) or value
        set[tostring(id)] = true
        set[normalizeDeedId(id)] = true
    end
    return set
end

local function selectActiveDeeds(deeds, opts)
    opts = opts or {}
    local maxFame = math.max(0, math.floor(tonumber(opts.maxFame) or M.MAX_FAME))
    if #deeds <= maxFame then
        return deeds, {}
    end

    local selectedSet = selectedDeedSet(opts)
    local selected = {}
    local dropped = {}
    if selectedSet then
        for _, deed in ipairs(deeds) do
            if #selected < maxFame and (selectedSet[deed.id] or selectedSet[deed.description] or selectedSet[deed.title]) then
                selected[#selected + 1] = deed
            else
                dropped[#dropped + 1] = deed
            end
        end
        for _, deed in ipairs(dropped) do
            if #selected < maxFame then
                selected[#selected + 1] = deed
            end
        end

        local finalSet = {}
        for _, deed in ipairs(selected) do
            finalSet[deed] = true
        end
        local finalDropped = {}
        for _, deed in ipairs(deeds) do
            if not finalSet[deed] then
                finalDropped[#finalDropped + 1] = deed
            end
        end
        return selected, finalDropped
    end

    local start = #deeds - maxFame + 1
    for i, deed in ipairs(deeds) do
        if i >= start then
            selected[#selected + 1] = deed
        else
            dropped[#dropped + 1] = deed
        end
    end
    return selected, dropped
end

local function normalizeCarouseSpend(request)
    local spend = tostring(request.spend or request.portion or request.level or request.amount or ""):lower()
    local percent = tonumber(request.percent or request.percentage)
    if not percent then
        if spend == "half" or spend == "50" or spend == "50%" then
            percent = 0.5
        elseif spend == "all" or spend == "full" or spend == "100" or spend == "100%" then
            percent = 1
        end
    elseif percent > 1 then
        percent = percent / 100
    end

    if percent == 0.5 then
        return 0.5, 1
    elseif percent == 1 then
        return 1, 2
    end

    return nil, nil
end

local function getBank(actor)
    if not actor then
        return nil
    end
    actor.bank = actor.bank or {
        gold = 0,
        items = {},
    }
    actor.bank.gold = tonumber(actor.bank.gold) or 0
    actor.bank.items = actor.bank.items or {}
    return actor.bank
end

local function findBankedItem(bank, itemId)
    local wanted = tostring(itemId or "")
    for index, item in ipairs(bank and bank.items or {}) do
        if tostring(item.id or "") == wanted then
            return item, index
        end
    end
    return nil, nil
end

local function canAddBankedItemsToInventory(inv, items, location)
    if not inv or not inv.availableSlots or not inv[location] then
        return false, "invalid_location"
    end

    local remainingSlots = inv:availableSlots(location)
    for _, item in ipairs(items or {}) do
        if item.oversized and location ~= inventory.LOCATIONS.BELT then
            return false, "oversized_belt_only"
        end
        if item.isArmor and location ~= inventory.LOCATIONS.BELT then
            return false, "armor_belt_only"
        end

        local slotsNeeded = item.stackable and 1 or item.size
        if remainingSlots < slotsNeeded then
            return false, "insufficient_slots"
        end
        remainingSlots = remainingSlots - slotsNeeded
    end

    return true
end

local function canAddPlannedItemsToInventory(inv, plannedItems)
    if not inv or not inv.availableSlots then
        return false, "invalid_location"
    end

    local remainingByLocation = {}
    for _, planned in ipairs(plannedItems or {}) do
        local item = planned.item
        local location = planned.location or inventory.LOCATIONS.PACK
        if not inv[location] then
            return false, "invalid_location"
        end
        if item.oversized and location ~= inventory.LOCATIONS.BELT then
            return false, "oversized_belt_only"
        end
        if item.isArmor and location ~= inventory.LOCATIONS.BELT then
            return false, "armor_belt_only"
        end

        if remainingByLocation[location] == nil then
            remainingByLocation[location] = inv:availableSlots(location)
        end

        local slotsNeeded = item.stackable and 1 or item.size
        if remainingByLocation[location] < slotsNeeded then
            return false, "insufficient_slots"
        end
        remainingByLocation[location] = remainingByLocation[location] - slotsNeeded
    end

    return true
end

local function createPlannedTemplateItems(templateId, quantity, location)
    local planned = {}
    local firstItem = inventory.createItemFromTemplate(templateId)
    if not firstItem then
        return nil, "Unknown item"
    end
    if firstItem.stackable then
        local remaining = math.max(1, math.floor(tonumber(quantity) or 1))
        local stackSize = math.max(1, math.floor(tonumber(firstItem.stackSize) or remaining))
        local item = firstItem
        while remaining > 0 do
            item.quantity = math.min(stackSize, remaining)
            planned[#planned + 1] = {
                item = item,
                location = location or inventory.LOCATIONS.PACK,
            }
            remaining = remaining - item.quantity
            if remaining > 0 then
                item = inventory.createItemFromTemplate(templateId)
                if not item then
                    return nil, "Unknown item"
                end
            end
        end
        return planned
    end

    planned[#planned + 1] = {
        item = firstItem,
        location = location or inventory.LOCATIONS.PACK,
    }
    for _ = 2, quantity do
        local item = inventory.createItemFromTemplate(templateId)
        if not item then
            return nil, "Unknown item"
        end
        planned[#planned + 1] = {
            item = item,
            location = location or inventory.LOCATIONS.PACK,
        }
    end
    return planned
end

local function addPlannedItems(inv, plannedItems)
    local added = {}
    for _, planned in ipairs(plannedItems or {}) do
        local ok, reason = inv:addItem(planned.item, planned.location)
        if not ok then
            return nil, reason or "insufficient_slots"
        end
        added[#added + 1] = planned.item
    end
    return added
end

local function minorDiscardValue(card)
    return math.floor(tonumber(card and card.value) or 0)
end

local function minorSuitChoice(card, choices)
    local suit = card and card.suit
    if suit == constants.SUITS.SWORDS then
        return choices.swords
    elseif suit == constants.SUITS.PENTACLES then
        return choices.pentacles or choices.disks
    elseif suit == constants.SUITS.CUPS then
        return choices.cups
    elseif suit == constants.SUITS.WANDS then
        return choices.wands or choices.batons
    end
    return nil
end

local function appendActorRecord(actor, field, record)
    if not actor then
        return
    end
    actor[field] = actor[field] or {}
    actor[field][#actor[field] + 1] = record
end

local function findCarriedItem(actor, request, idKeys, tableKeys)
    request = request or {}
    local inv = actor and actor.inventory
    if not inv then
        return nil, nil
    end

    for _, key in ipairs(idKeys or {}) do
        local itemId = request[key]
        if itemId and inv.findItem then
            local item, location = inv:findItem(itemId)
            if item then
                return item, location
            end
        end
    end

    for _, key in ipairs(tableKeys or {}) do
        local candidate = request[key]
        if type(candidate) == "table" then
            if candidate.id and inv.findItem then
                local item, location = inv:findItem(candidate.id)
                if item then
                    return item, location
                end
            end
            return candidate, nil
        end
    end

    return nil, nil
end

local function normalizeTiles(value)
    local tiles = {}
    local function addTile(tile)
        if type(tile) == "table" then
            addTile(tile.tile or tile.letter or tile.value or tile[1])
            return
        end
        if tile == nil then
            return
        end
        local text = tostring(tile):upper()
        for char in text:gmatch("%a") do
            tiles[#tiles + 1] = char
        end
    end

    if type(value) == "table" then
        for _, tile in ipairs(value) do
            addTile(tile)
        end
    else
        addTile(value)
    end

    return tiles
end

local function lettersNeededForName(name)
    local needed = {}
    for char in tostring(name or ""):upper():gmatch("%a") do
        needed[char] = (needed[char] or 0) + 1
    end
    return needed
end

local function tilesCompleteName(name, tiles)
    local remaining = lettersNeededForName(name)
    for _, tile in ipairs(tiles or {}) do
        local char = tostring(tile or ""):upper():match("%a")
        if char and remaining[char] then
            remaining[char] = remaining[char] - 1
            if remaining[char] <= 0 then
                remaining[char] = nil
            end
        end
    end
    return next(remaining) == nil, remaining
end

local function getActorCityUpkeep(controller, actor)
    local id = actorId(actor)
    return (id and controller and controller.upkeepCompleted[id]) or (actor and actor.cityUpkeep)
end

local function actorIsDestitute(controller, actor, request)
    if request and request.destitute ~= nil then
        return request.destitute == true
    end
    local tier = request and (request.upkeepTier or request.tier)
    if tier then
        return normalizeUpkeepTier(tier) == "destitute"
    end
    local upkeep = getActorCityUpkeep(controller, actor)
    return normalizeUpkeepTier(upkeep and upkeep.tier or actor and actor.upkeepTier) == "destitute"
end

local function findLostLimb(actor, request)
    request = request or {}
    local requested = request.limb or request.bodyPart or request.lostLimb or request.prostheticFor
    if requested and tostring(requested) ~= "" then
        return tostring(requested):lower()
    end

    local lostLimbs = actor and (actor.lostLimbs or actor.missingLimbs)
    if type(lostLimbs) == "string" then
        return lostLimbs:lower()
    elseif type(lostLimbs) == "table" then
        for key, value in pairs(lostLimbs) do
            if value == true then
                return tostring(key):lower()
            elseif type(key) == "number" and value then
                return tostring(value):lower()
            end
        end
    end

    for _, ailment in ipairs(actor and actor.carouseAilments or {}) do
        if ailment and ailment.type == "missing_hand" then
            return "hand"
        end
    end

    return nil
end

local function findFuneralRecord(funerals, request)
    request = request or {}
    if type(request.funeralRecord) == "table" then
        return request.funeralRecord
    end

    local deceased = request.deceased or request.deadAdventurer or request.comrade
    local deceasedId = request.deceasedId or actorId(deceased)
    local deceasedName = request.deceasedName or request.comradeName or (deceased and deceased.name)
    for _, funeral in ipairs(funerals or {}) do
        if deceasedId and (funeral.deceasedId == deceasedId or actorId(funeral.deceased) == deceasedId) then
            return funeral
        end
        if deceasedName and (funeral.deceasedName == deceasedName or
           (funeral.deceased and funeral.deceased.name == deceasedName)) then
            return funeral
        end
    end

    return nil
end

local function removeCurseFromList(curses, curseId)
    if type(curses) ~= "table" then
        return nil
    end

    if curseId and curses[curseId] then
        local curse = curses[curseId]
        curses[curseId] = nil
        return curse
    end

    for index, curse in ipairs(curses) do
        if not curseId or curse.id == curseId or curse.name == curseId then
            table.remove(curses, index)
            return curse
        end
    end

    return nil
end

local function cureCurseEffect(controller, target, request)
    request = request or {}
    target = target or request.target
    if not target then
        return nil
    end

    local curseId = request.curseId or request.curseEffectId or request.curseEffect
    if type(curseId) == "table" then
        curseId = curseId.id or curseId.name
    end

    local removed = removeCurseFromList(target.curses, curseId)
    if removed then
        return {
            type = "curse_record",
            curse = removed,
            curseId = removed.id or curseId,
        }
    end

    if target.malediction and target.malediction.active ~= false then
        local resolver = controller and controller.actionResolver
        if resolver and resolver.dismissMalediction then
            local dismissed = resolver:dismissMalediction(nil, target, "visit_grave")
            if dismissed and dismissed.success then
                return {
                    type = "malediction",
                    result = dismissed,
                    curseId = target.malediction and target.malediction.curseId or curseId,
                }
            end
        end

        local malediction = target.malediction
        target.malediction = nil
        if target.conditions then
            target.conditions.maledicted = false
        end
        return {
            type = "malediction",
            curse = malediction,
            curseId = malediction.curseId or curseId,
            partial = true,
        }
    end

    if target.conditions and target.conditions.cursed then
        target.conditions.cursed = false
        return {
            type = "condition",
            curseId = curseId or "cursed",
        }
    end

    return nil
end

local function findActorAffliction(actor, afflictionName)
    if not actor or type(actor.afflictions) ~= "table" then
        return nil, nil
    end

    if afflictionName and actor.afflictions[afflictionName] then
        return actor.afflictions[afflictionName], afflictionName
    end

    for name, affliction in pairs(actor.afflictions) do
        return affliction, name
    end

    return nil, nil
end

local function removeAllCarriedItems(actor)
    local removed = {}
    local inv = actor and actor.inventory
    if not inv or not inv.getAllItems or not inv.removeItem then
        return removed
    end

    for _, entry in ipairs(inv:getAllItems()) do
        local item = entry.item
        if item then
            local removedItem = inv:removeItem(item.id)
            if removedItem then
                removed[#removed + 1] = {
                    item = removedItem,
                    location = entry.location,
                }
            end
        end
    end
    return removed
end

local function resolveHangoverOutcome(actor, hangover, minorDiscard)
    local outcome = {
        id = hangover and hangover.id or "unknown_hangover",
        title = hangover and hangover.title or "Unknown Hangover",
        applied = false,
    }
    local id = outcome.id
    local value = minorDiscardValue(minorDiscard)

    if id == "headache_windfall" then
        outcome.goldGained = value
        if value > 0 then
            currency.addGold(actor, value)
            outcome.applied = true
        else
            outcome.requiresMinorDiscard = true
        end
    elseif id == "stocks" then
        appendActorRecord(actor, "legalTroubles", {
            source = "carouse",
            type = "stocks",
            publicHumiliation = true,
        })
        outcome.applied = true
    elseif id == "cowbell" then
        appendActorRecord(actor, "carouseEncumbrances", {
            source = "carouse",
            type = "cowbell_chain",
            noisy = true,
        })
        outcome.noisy = true
        outcome.applied = true
    elseif id == "marriage_ring" then
        appendActorRecord(actor, "carouseMarriages", {
            source = "carouse",
            unknownSpouse = true,
        })
        outcome.unknownSpouse = true
        outcome.applied = true
    elseif id == "angry_creditors" then
        appendActorRecord(actor, "carouseDebts", {
            source = "carouse",
            angryCreditors = true,
        })
        outcome.angryCreditors = true
        outcome.applied = true
    elseif id == "loose_finger" then
        appendActorRecord(actor, "carouseOddities", {
            source = "carouse",
            type = "ring_on_severed_finger",
        })
        outcome.applied = true
    elseif id == "high_priest" then
        if value <= 0 then
            outcome.requiresMinorDiscard = true
        else
            outcome.figure = (value % 2 == 0) and "high_priest" or "high_priestess"
            outcome.applied = true
        end
    elseif id == "tavern_ban" then
        appendActorRecord(actor, "tavernBans", {
            source = "carouse",
            favorite = true,
            active = true,
        })
        outcome.banned = true
        outcome.applied = true
    elseif id == "new_tattoo" then
        local location = minorSuitChoice(minorDiscard, {
            swords = "arm",
            pentacles = "leg",
            cups = "backside",
            wands = "face",
        })
        if not location or value <= 0 then
            outcome.requiresMinorDiscard = true
        else
            local quality = "pretty_sweet"
            if value <= 2 then
                quality = "horribly_offensive"
            elseif value <= 8 then
                quality = "cringe_misspelled"
            end
            outcome.location = location
            outcome.quality = quality
            appendActorRecord(actor, "tattoos", {
                source = "carouse",
                location = location,
                quality = quality,
            })
            outcome.applied = true
        end
    elseif id == "clothes_swap" then
        appendActorRecord(actor, "clothesSwaps", {
            source = "carouse",
            evenTrade = true,
        })
        outcome.evenTrade = true
        outcome.applied = true
    elseif id == "duel_invitation" then
        if value <= 0 then
            outcome.requiresMinorDiscard = true
        else
            outcome.duelInDays = value
            appendActorRecord(actor, "pendingDuels", {
                source = "carouse",
                days = value,
            })
            outcome.applied = true
        end
    elseif id == "cistern" then
        local missing = removeAllCarriedItems(actor)
        actor.lostCarouseItems = actor.lostCarouseItems or {}
        actor.lostCarouseItems[#actor.lostCarouseItems + 1] = {
            source = "carouse",
            reason = "cistern",
            items = missing,
        }
        outcome.itemsMissing = #missing
        outcome.lostItems = missing
        outcome.applied = true
    elseif id == "wanted_poster" then
        local charge = minorSuitChoice(minorDiscard, {
            swords = "armed_robbery",
            pentacles = "attempted_pickpocketing",
            cups = "lewd_acts",
            wands = "consorting_with_dark_entities",
        })
        if not charge then
            outcome.requiresMinorDiscard = true
        else
            outcome.charge = charge
            appendActorRecord(actor, "wantedPosters", {
                source = "carouse",
                charge = charge,
            })
            outcome.applied = true
        end
    elseif id == "soul_invoice" then
        appendActorRecord(actor, "infernalContracts", {
            source = "carouse",
            price = "one_soul",
            consideration = "one_beer",
        })
        outcome.applied = true
    elseif id == "hogtied_noble" then
        appendActorRecord(actor, "carouseComplications", {
            source = "carouse",
            type = "hogtied_noble",
        })
        outcome.applied = true
    elseif id == "broken_shop" then
        appendActorRecord(actor, "shopDamages", {
            source = "carouse",
            brokenPlates = true,
            constablesAngry = true,
        })
        outcome.applied = true
    elseif id == "burning_water" then
        appendActorRecord(actor, "carouseAilments", {
            source = "carouse",
            type = "burning_water",
        })
        outcome.applied = true
    elseif id == "dark_pact" then
        appendActorRecord(actor, "darkPacts", {
            source = "carouse",
            active = true,
        })
        outcome.applied = true
    elseif id == "missing_hand" then
        appendActorRecord(actor, "carouseAilments", {
            source = "carouse",
            type = "missing_hand",
        })
        outcome.applied = true
    elseif id == "candle_fire" then
        local fire = minorSuitChoice(minorDiscard, {
            swords = { districtsBurned = 1, fireSpirit = false },
            pentacles = { districtsBurned = 2, fireSpirit = false },
            cups = { districtsBurned = 3, fireSpirit = false },
            wands = { districtsBurned = 3, fireSpirit = true },
        })
        if not fire then
            outcome.requiresMinorDiscard = true
        else
            outcome.districtsBurned = fire.districtsBurned
            outcome.fireSpirit = fire.fireSpirit
            appendActorRecord(actor, "cityFireIncidents", {
                source = "carouse",
                districtsBurned = fire.districtsBurned,
                fireSpirit = fire.fireSpirit,
            })
            outcome.applied = true
        end
    elseif id == "puncture_marks" then
        appendActorRecord(actor, "carouseAilments", {
            source = "carouse",
            type = "circular_puncture_marks",
        })
        outcome.applied = true
    else
        outcome.requiresAdjudication = true
    end

    return outcome
end

local function shallowCopy(value)
    local copy = {}
    for k, v in pairs(value or {}) do
        copy[k] = v
    end
    return copy
end

local function normalizeCampActionId(actionId)
    return tostring(actionId or ""):lower():gsub("%s+", "_")
end

local function cityCampActionContext(controller, actionData)
    local context = shallowCopy(actionData.context or actionData.campContext or {})
    context.eventBus = context.eventBus or controller.eventBus
    context.guild = context.guild or controller.guild
    context.actionsCompleted = context.actionsCompleted or controller.actionsCompleted
    return context
end

local function countWordSyllables(word)
    word = tostring(word or ""):lower():gsub("[^a-z]", "")
    if word == "" then
        return 0
    end

    local groups = 0
    local inVowels = false
    for i = 1, #word do
        local char = word:sub(i, i)
        local isVowel = char:match("[aeiouy]") ~= nil
        if isVowel and not inVowels then
            groups = groups + 1
        end
        inVowels = isVowel
    end

    if #word > 2 and word:sub(-1) == "e" and not word:match("[aeiouy]le$") and not word:match("tue$") and groups > 1 then
        groups = groups - 1
    end

    return math.max(1, groups)
end

local function estimateSyllables(description)
    local total = 0
    for word in tostring(description or ""):gmatch("[%a']+") do
        total = total + countWordSyllables(word)
    end
    return total
end

local function resolveSyllables(request)
    local syllables = tonumber(request.syllables or request.syllableCount)
    if syllables then
        return math.max(0, math.floor(syllables))
    end
    return estimateSyllables(request.description or request.name or request.title)
end

local function normalizeCommissionScale(scale)
    local value = tostring(scale or ""):lower():gsub("%s+", "_")
    local aliases = {
        peasant = "farmer",
        commoner = "farmer",
        common = "farmer",
        farm = "farmer",
        adventuring = "adventurer",
        delver = "adventurer",
        nobleman = "noble",
        noblewoman = "noble",
        luxury = "noble",
        unique = "novel",
        new = "novel",
        brand_new = "novel",
        nobody = "novel",
        no_one_has = "novel",
    }
    return aliases[value] or value
end

local function resolveComponentTemplateId(ref)
    local value = tostring(ref or "")
    local spell = spell_registry.getSpell(value)
    if spell and spell.componentId then
        return spell.componentId
    end
    if item_templates.hasTemplate(value) then
        return value
    end
    return nil
end

local function normalizeTalentId(talentId)
    return talent_catalog.normalizeId(talentId)
end

local function getTalentEntry(actor, talentId)
    if type(actor and actor.talents) ~= "table" then
        return nil, nil
    end

    local requested = normalizeTalentId(talentId)
    for key, talent in pairs(actor.talents) do
        if normalizeTalentId(key) == requested then
            return talent, key
        end
        if type(talent) == "table" and normalizeTalentId(talent.id or talent.name or talent.talentId) == requested then
            return talent, key
        end
    end

    return nil, nil
end

local function hasUsableTalent(actor, talentId)
    local talent = getTalentEntry(actor, talentId)
    if type(talent) == "table" then
        return talent.wounded ~= true
    end
    return talent == true
end

local function normalizeProjectId(projectId)
    return tostring(projectId or ""):lower():gsub("%s+", "_"):gsub("[^%w_]", "")
end

local function healAllWounds(actor)
    local healed = {
        armorNotches = actor.armorNotches or 0,
        woundedTalents = actor.woundedTalents or 0,
        staggered = actor.conditions and actor.conditions.staggered == true,
        injured = actor.conditions and actor.conditions.injured == true,
        deathsDoor = actor.conditions and actor.conditions.deaths_door == true,
    }

    actor.armorNotches = 0
    actor.woundedTalents = 0
    actor._woundedTalentOrder = {}

    for _, talent in pairs(actor.talents or {}) do
        if type(talent) == "table" then
            talent.wounded = false
        end
    end

    if actor.conditions then
        actor.conditions.staggered = false
        actor.conditions.injured = false
        actor.conditions.deaths_door = false
    end

    return healed
end

local function refreshResolve(actor)
    if type(actor.resolve) == "table" then
        actor.resolve.current = actor.resolve.max or actor.resolve.current or 0
        return actor.resolve.current
    end

    if actor.resolve ~= nil then
        local maxResolve = tonumber(actor.resolveMax or actor.maxResolve) or 4
        actor.resolve = math.max(tonumber(actor.resolve) or 0, maxResolve)
        return actor.resolve
    end

    return nil
end

function M.createCityPhaseController(config)
    config = config or {}

    local controller = {
        eventBus = config.eventBus or events.globalBus,
        actionResolver = config.actionResolver,
        guild = config.guild or {},
        guildRoster = config.guildRoster or config.roster or {},
        playerDeck = config.playerDeck or config.minorDeck,
        gmDeck = config.gmDeck or config.majorDeck,
        cityEventsTable = config.cityEventsTable or config.city_events_table or city_events.DEFAULT_EVENTS,
        signsAndPortentsTable = config.signsAndPortentsTable or config.signsTable or city_events.SIGNS_AND_PORTENTS,
        cityEventEffects = config.cityEventEffects or {},
        cityLayout = config.cityLayout or config.cityMap,
        districtActions = config.districtActions or
            ((config.cityLayout or config.cityMap) and (config.cityLayout or config.cityMap).specialCityActions) or {},
        meatgrinder = config.meatgrinder,
        meatgrinderTable = config.meatgrinderTable or config.meatgrinderEntries,
        contracts = config.contracts or config.cityContracts or {},
        jobBoard = config.jobBoard or config.availableContracts or config.contractOffers or {},
        guildTreasury = config.guildTreasury or config.treasury or { gold = 0 },
        projects = config.projects or config.cityProjects or {},
        buildings = config.buildings or config.cityBuildings or {},
        commissions = config.commissions or config.cityCommissions or {},
        funerals = config.funerals or config.funeralRecords or {},
        bankReturnsApplied = config.bankReturnsApplied or {},
        actionsCompleted = config.actionsCompleted or {},
        upkeepCompleted = config.upkeepCompleted or {},
        taxesResolved = config.taxesResolved or false,
        noteworthyDeedsResolved = config.noteworthyDeedsResolved or false,
        cityEventResolved = config.cityEventResolved or false,
        contractsResolved = config.contractsResolved or false,
        nextCrawlPlanned = config.nextCrawlPlanned or false,
        underworldRestocked = config.underworldRestocked or false,
        cityPhaseEnded = config.cityPhaseEnded or false,
    }

    function controller:hasActed(actor)
        local id = actorId(actor)
        return id ~= nil and self.actionsCompleted[id] ~= nil
    end

    function controller:generateCityLayout(opts)
        opts = opts or {}
        if not opts.deck and not opts.playerDeck and not opts.minorDeck then
            opts.playerDeck = self.playerDeck
        end

        local layout, detail = M.generateCityLayout(opts)
        if not layout then
            return nil, detail
        end

        self.cityLayout = layout
        self.districtActions = layout.specialCityActions or {}
        return layout, detail
    end

    function controller:getAvailableDistrictActions()
        if self.cityLayout and self.cityLayout.specialCityActions then
            return self.cityLayout.specialCityActions
        end
        return self.districtActions or {}
    end

    function controller:getDistrictAction(actionId)
        return findDistrictAction({ specialCityActions = self:getAvailableDistrictActions() }, actionId)
    end

    function controller:canAct(actor)
        if not isActiveAdventurer(actor) then
            return false, "No active adventurer"
        end
        if self:hasActed(actor) then
            return false, "City Action already taken"
        end
        return true
    end

    function controller:markActed(actor, actionId, result)
        local id = actorId(actor)
        if not id then
            return
        end
        self.actionsCompleted[id] = {
            actor = actor,
            action = actionId,
            result = result,
        }
    end

    function controller:breakPactsForRecoveryResult(actor, recoveryResult)
        return camp_actions.breakPactsForRecoveryResult(actor, recoveryResult, {
            eventBus = self.eventBus,
            actionResolver = self.actionResolver,
        })
    end

    function controller:canAdvance()
        for _, actor in ipairs(self.guild or {}) do
            if isActiveAdventurer(actor) and not self:hasActed(actor) then
                return false
            end
        end
        return true
    end

    function controller:resolveEndOfCityPhase(opts)
        opts = opts or {}
        if self.cityPhaseEnded then
            return false, "City Phase already ended"
        end

        local dogCurseConsequences = {}
        for index, actor in ipairs(self.guild or {}) do
            if isActiveAdventurer(actor) then
                local condition = dogCurseCityOutcome(actor, opts, index)
                if condition then
                    actor.conditions = actor.conditions or {}
                    actor.conditions[condition] = true
                    dogCurseConsequences[#dogCurseConsequences + 1] = {
                        actor = actor,
                        condition = condition,
                        curseId = actor.maledictionCurseId or "dogs_hate_you",
                    }
                end
            end
        end

        self.cityPhaseEnded = true
        local detail = {
            guild = self.guild,
            dogCurseConsequences = dogCurseConsequences,
            result = "city_phase_ended",
        }
        self.eventBus:emit(events.EVENTS.CITY_PHASE_ENDED, detail)
        self.eventBus:emit(events.EVENTS.PHASE_CHANGED, {
            oldPhase = "city",
            newPhase = opts.nextPhase or "crawl",
        })

        return true, "city_phase_ended", detail
    end

    function controller:hasUpkeep(actor)
        local id = actorId(actor)
        return id ~= nil and self.upkeepCompleted[id] ~= nil
    end

    function controller:getUpkeepCost(tierId)
        tierId = normalizeUpkeepTier(tierId)
        local tier = M.UPKEEP_TIERS[tierId]
        if not tier then
            return nil
        end
        local override = self.cityEventEffects and self.cityEventEffects.upkeepCosts and
            self.cityEventEffects.upkeepCosts[tierId]
        if override ~= nil then
            return override
        end
        return tier.cost
    end

    function controller:applyCityEventEffects(eventEntry, sign)
        self.cityEventEffects = mergeCityEventEffects(self.cityEventEffects, eventEntry and eventEntry.effects)
        self.cityEventEffects = mergeCityEventEffects(self.cityEventEffects, sign and sign.effects)
        return self.cityEventEffects
    end

    function controller:checkCityActionRestrictions(actionId)
        local effects = self.cityEventEffects or {}
        local blocked = effects.blockedCityActions
        if blocked == "all" then
            return false, "City Actions blocked by City Event"
        end

        local allowed = effects.allowedCityActions
        if allowed and not allowed[actionId] then
            return false, "City Action not available during this City Event"
        end

        if blocked and blocked[actionId] then
            return false, "City Action blocked by City Event"
        end

        return true
    end

    function controller:resolveDeathAndTaxes(opts)
        opts = opts or {}
        if self.taxesResolved then
            return false, "Death and taxes already resolved"
        end

        local rate = tonumber(opts.taxRate) or M.TAX_RATE
        local details = {}
        local totalTax = 0
        for _, actor in ipairs(opts.guild or self.guild or {}) do
            local ok, tax = currency.collectPercentTax(actor, rate)
            if not ok then
                return false, tax
            end
            details[#details + 1] = tax
            totalTax = totalTax + (tax.taxPaid or 0)
        end

        local result = {
            step = M.STEPS.DEATH_AND_TAXES,
            rate = rate,
            totalTax = totalTax,
            details = details,
            result = "death_and_taxes_resolved",
        }

        self.taxesResolved = true
        self.eventBus:emit(events.EVENTS.CITY_DEATH_AND_TAXES_RESOLVED, result)

        return true, "death_and_taxes_resolved", result
    end

    function controller:resolveNoteworthyDeeds(opts)
        opts = opts or {}
        if self.noteworthyDeedsResolved then
            return false, "Noteworthy deeds already resolved"
        end

        local roster = opts.guildRoster or opts.roster or self.guildRoster
        roster.noteworthyDeeds = normalizeDeedList(
            opts.currentDeeds or opts.activeDeeds or roster.noteworthyDeeds or roster.deeds
        )

        local previousFame = #roster.noteworthyDeeds
        local erased = nil
        if #roster.noteworthyDeeds > 0 then
            erased = table.remove(roster.noteworthyDeeds, 1)
        end

        local proposed = normalizeDeedList(
            opts.deeds or opts.newDeeds or opts.proposedDeeds or opts.accomplishments or opts.noteworthyDeeds
        )
        local added = {}
        local rejected = {}
        for _, deed in ipairs(proposed) do
            if deed.approved then
                roster.noteworthyDeeds[#roster.noteworthyDeeds + 1] = deed
                added[#added + 1] = deed
            else
                rejected[#rejected + 1] = deed
            end
        end

        local dropped = {}
        roster.noteworthyDeeds, dropped = selectActiveDeeds(roster.noteworthyDeeds, opts)
        roster.deeds = roster.noteworthyDeeds
        roster.fame = #roster.noteworthyDeeds
        roster.Fame = roster.fame

        local detail = {
            step = M.STEPS.NOTEWORTHY_DEEDS,
            roster = roster,
            previousFame = previousFame,
            fame = roster.fame,
            erased = erased,
            added = added,
            rejected = rejected,
            dropped = dropped,
            deeds = roster.noteworthyDeeds,
            result = #added > 0 and "noteworthy_deeds_recorded" or "noteworthy_deeds_aged",
        }

        self.noteworthyDeedsResolved = true
        self.eventBus:emit(events.EVENTS.CITY_NOTEWORTHY_DEEDS_RESOLVED, detail)

        return true, detail.result, detail
    end

    function controller:resolveCityEvent(opts)
        opts = opts or {}
        if self.cityEventResolved then
            return false, "City Event already resolved"
        end

        local card, shouldDiscard, drawnDeck = self:drawMajorCard(opts)
        if not card then
            return false, "Requires major arcana draw"
        end

        local eventEntry = city_events.getEvent(card.value, opts.cityEventsTable or self.cityEventsTable)
        if not eventEntry then
            return false, "City Event table entry missing"
        end

        local minorDiscard = opts.minorDiscardCard or opts.minorDiscard
        local minorDeck = opts.playerDeck or opts.minorDeck or self.playerDeck
        if not minorDiscard and eventEntry.category == city_events.CATEGORIES.SIGNS_AND_PORTENTS and
            minorDeck and minorDeck.peekDiscard then
            minorDiscard = minorDeck:peekDiscard()
        end

        local sign = nil
        if eventEntry.category == city_events.CATEGORIES.SIGNS_AND_PORTENTS then
            if not minorDiscard then
                return false, "Requires minor discard for Signs and Portents"
            end
            sign = city_events.getSign(minorDiscard.value, opts.signsAndPortentsTable or self.signsAndPortentsTable)
            if not sign then
                return false, "Signs and Portents table entry missing"
            end
        end

        if shouldDiscard and drawnDeck and drawnDeck.discard then
            drawnDeck:discard(card)
        end

        local detail = {
            step = M.STEPS.CITY_EVENTS,
            card = card,
            event = eventEntry,
            category = eventEntry.category,
            signCard = minorDiscard,
            sign = sign,
            effects = self:applyCityEventEffects(eventEntry, sign),
            result = "city_event_resolved",
        }

        self.lastCityEvent = detail
        self.cityEventResolved = true
        self.eventBus:emit(events.EVENTS.CITY_EVENT_RESOLVED, detail)

        return true, "city_event_resolved", detail
    end

    function controller:resolveTurnInContracts(opts)
        opts = opts or {}
        if self.contractsResolved then
            return false, "Contracts already turned in"
        end

        local contracts = opts.contracts or self.contracts or {}
        local recipients = normalizeRecipientList(opts.recipients or opts.guild or self.guild)
        if #recipients == 0 then
            recipients = activeAdventurers(self.guild)
        end

        local details = {}
        local completedCount = 0
        local totalGold = 0
        for _, contract in ipairs(contracts) do
            if isContractComplete(contract) and contract.turnedIn ~= true then
                completedCount = completedCount + 1
                local rewardGold = contractRewardGold(contract)
                local distribution = distributeGold(rewardGold, contract.recipients or recipients, self.guildTreasury)
                contract.turnedIn = true
                contract.turnedInResult = {
                    rewardGold = rewardGold,
                    distribution = distribution,
                }
                totalGold = totalGold + rewardGold
                details[#details + 1] = {
                    contract = contract,
                    contractId = contract.id,
                    name = contract.name or contract.title,
                    rewardGold = rewardGold,
                    distribution = distribution,
                }
            end
        end

        local xpPerContract = math.max(0, math.floor(tonumber(opts.xpPerContract) or 1))
        local xpAwarded = completedCount * xpPerContract
        local xpRecipients = {}
        if xpAwarded > 0 then
            for _, actor in ipairs(recipients) do
                addXP(actor, xpAwarded)
                xpRecipients[#xpRecipients + 1] = {
                    actor = actor,
                    actorId = actorId(actor),
                    xp = xpAwarded,
                }
            end
        end

        local result = {
            step = M.STEPS.TURN_IN_CONTRACTS,
            contracts = details,
            completedCount = completedCount,
            totalGold = totalGold,
            xpPerContract = xpPerContract,
            xpAwarded = xpAwarded,
            xpRecipients = xpRecipients,
            guildTreasury = self.guildTreasury,
            result = completedCount > 0 and "contracts_turned_in" or "no_completed_contracts",
        }

        self.contractsResolved = true
        self.eventBus:emit(events.EVENTS.CITY_CONTRACTS_TURNED_IN, result)

        return true, result.result, result
    end

    function controller:resolveSellTreasure(actor, opts)
        opts = opts or {}
        local itemIds = normalizeList(opts.itemIds or opts.items or opts.itemId)
        if #itemIds == 0 then
            return false, "Treasure item required"
        end

        local inv = actor and actor.inventory
        if not inv or not inv.findItem or not inv.removeItem then
            return false, "No inventory for treasure sale"
        end

        local values = opts.values or opts.prices or {}
        local salePlan = {}
        local totalGold = 0
        for _, itemRef in ipairs(itemIds) do
            local itemId = type(itemRef) == "table" and itemRef.id or itemRef
            local explicitValue = type(itemRef) == "table" and (itemRef.value or itemRef.price) or values[itemId]
            local item = inv:findItem(itemId)
            if not item then
                return false, "Treasure item not found"
            end
            if not isTreasureItem(item) then
                return false, "Item is not non-liquid treasure"
            end
            local value = treasureSaleValue(item, explicitValue)
            if value <= 0 then
                return false, "Treasure value required"
            end
            salePlan[#salePlan + 1] = {
                item = item,
                itemId = item.id,
                value = value,
            }
            totalGold = totalGold + value
        end

        local sold = {}
        for _, sale in ipairs(salePlan) do
            local removed = inv:removeItem(sale.itemId)
            if removed then
                sold[#sold + 1] = {
                    item = removed,
                    itemId = removed.id,
                    name = removed.name,
                    value = sale.value,
                }
            end
        end

        currency.addGold(actor, totalGold)

        local result = {
            step = M.STEPS.TURN_IN_CONTRACTS,
            actor = actor,
            items = sold,
            totalGold = totalGold,
            result = "treasure_sold",
        }
        self.eventBus:emit(events.EVENTS.CITY_TREASURE_SOLD, result)

        return true, "treasure_sold", result
    end

    function controller:resolvePlanNextCrawl(opts)
        opts = opts or {}
        if self.nextCrawlPlanned then
            return false, "Next Crawl already planned"
        end

        local offers = opts.jobBoard or opts.offers or opts.availableContracts or self.jobBoard or {}
        local generatedJobBoard = nil
        if opts.generateJobBoard or opts.jobBoardCards or opts.contractCards or opts.cards then
            local generated, generationDetail = M.generateJobBoard({
                jobBoardCards = opts.jobBoardCards or opts.contractCards or opts.cards,
                playerDeck = opts.playerDeck or opts.minorDeck or self.playerDeck,
                deck = opts.deck,
                count = opts.count or opts.cardCount,
                idPrefix = opts.idPrefix or opts.boardId,
                allowNonStandardCount = opts.allowNonStandardCount,
                discardDraws = opts.discardDraws,
            })
            if not generated then
                return false, generationDetail
            end
            offers = generated
            self.jobBoard = generated
            generatedJobBoard = generationDetail
        end

        if opts.requireJobBoard ~= false and (#offers < 4 or #offers > 6) then
            return false, "Job board should offer four to six contracts"
        end

        local selected = normalizeList(
            opts.selectedContractIds or opts.contractIds or opts.selectedContracts or opts.contractId
        )
        local signedContracts = {}
        for _, ref in ipairs(selected) do
            local contract = type(ref) == "table" and ref or findContractById(offers, ref)
            if not contract then
                return false, "Selected contract not on job board"
            end
            if type(ref) == "table" and not hasContract(offers, ref) then
                return false, "Selected contract not on job board"
            end
            if contract.completed == true or contract.turnedIn == true then
                return false, "Selected contract already completed"
            end
            signedContracts[#signedContracts + 1] = contract
        end

        for _, contract in ipairs(signedContracts) do
            contract.status = contract.status or "active"
            contract.signed = true
            contract.sealed = true
            contract.signedDuringCityPhase = true
            if not hasContract(self.contracts, contract) then
                self.contracts[#self.contracts + 1] = contract
            end
        end

        self.guildRoster.currentContracts = self.guildRoster.currentContracts or self.contracts
        for _, contract in ipairs(signedContracts) do
            if not hasContract(self.guildRoster.currentContracts, contract) then
                self.guildRoster.currentContracts[#self.guildRoster.currentContracts + 1] = contract
            end
        end
        self.guildRoster.currentQuest = opts.currentQuest or opts.quest or self.guildRoster.currentQuest
        self.guildRoster.nextDestination = opts.destination or opts.nextDestination or self.guildRoster.nextDestination
        self.guildRoster.nextCrawlNotes = opts.notes or opts.debrief or opts.plan or self.guildRoster.nextCrawlNotes

        local detail = {
            step = M.STEPS.PLAN_NEXT_CRAWL,
            jobBoard = offers,
            offeredCount = #offers,
            generatedJobBoard = generatedJobBoard,
            generationCards = generatedJobBoard and generatedJobBoard.cards or nil,
            signedContracts = signedContracts,
            signedCount = #signedContracts,
            currentContracts = self.contracts,
            currentQuest = self.guildRoster.currentQuest,
            destination = self.guildRoster.nextDestination,
            notes = self.guildRoster.nextCrawlNotes,
            result = "next_crawl_planned",
        }

        self.nextCrawlPlanned = true
        self.eventBus:emit(events.EVENTS.CITY_NEXT_CRAWL_PLANNED, detail)

        return true, "next_crawl_planned", detail
    end

    function controller:resolveRestockUnderworld(opts)
        opts = opts or {}
        if self.underworldRestocked then
            return false, "Underworld already restocked"
        end

        local meatgrinder = opts.meatgrinder or self.meatgrinder
        local consumedMeatgrinder = {}
        if meatgrinder and meatgrinder.getConsumedEvents then
            consumedMeatgrinder = meatgrinder:getConsumedEvents()
        end

        local meatgrinderReplacements = applyTableReplacements(
            opts.meatgrinderTable or self.meatgrinderTable,
            opts.meatgrinderReplacements or opts.meatgrinderEntries
        )
        local cityEventReplacements = applyTableReplacements(
            opts.cityEventsTable or self.cityEventsTable,
            opts.cityEventReplacements or opts.cityEvents
        )
        local signReplacements = applyTableReplacements(
            opts.signsAndPortentsTable or self.signsAndPortentsTable,
            opts.signsAndPortentsReplacements or opts.signsAndPortents
        )

        if meatgrinder and meatgrinder.resetConsumed then
            meatgrinder:resetConsumed()
        end

        local mapUpdates = normalizeList(opts.mapUpdates or opts.changedRooms or opts.mapNotes)
        local factionUpdates = normalizeList(opts.factionUpdates or opts.factions)
        self.guildRoster.restockNotes = self.guildRoster.restockNotes or {}
        local note = {
            mapUpdates = mapUpdates,
            factionUpdates = factionUpdates,
            notes = opts.notes or opts.restockNotes,
        }
        self.guildRoster.restockNotes[#self.guildRoster.restockNotes + 1] = note
        self.guildRoster.mapsReviewed = opts.mapsReviewed ~= false

        local detail = {
            step = M.STEPS.RESTOCK_UNDERWORLD,
            consumedMeatgrinder = consumedMeatgrinder,
            meatgrinderReplacements = meatgrinderReplacements,
            cityEventReplacements = cityEventReplacements,
            signsAndPortentsReplacements = signReplacements,
            mapUpdates = mapUpdates,
            factionUpdates = factionUpdates,
            mapsReviewed = self.guildRoster.mapsReviewed,
            notes = note.notes,
            result = "underworld_restocked",
        }

        self.underworldRestocked = true
        self.eventBus:emit(events.EVENTS.CITY_UNDERWORLD_RESTOCKED, detail)

        return true, "underworld_restocked", detail
    end

    function controller:resolveUpkeep(actor, opts)
        opts = opts or {}
        actor = actor or opts.actor
        local id = actorId(actor)
        if not id then
            return false, "No active adventurer"
        end
        if self:hasUpkeep(actor) then
            return false, "Upkeep already paid"
        end

        local tierId = normalizeUpkeepTier(opts.tier or opts.upkeepTier)
        local tier = M.UPKEEP_TIERS[tierId]
        if not tier then
            return false, "Unknown upkeep tier"
        end

        local cost = self:getUpkeepCost(tier.id)
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end

        local gearRequests = normalizeGearRequests(opts.refillItems or opts.refillGear or opts.gear or opts.items)
        local plannedGear = {}
        if #gearRequests > 0 then
            if not tier.refillTier then
                return false, "Upkeep tier cannot refill gear"
            end
            if not actor.inventory or not actor.inventory.addItem then
                return false, "No inventory for upkeep gear"
            end
            for _, request in ipairs(gearRequests) do
                local templateId = tostring(request.templateId or "")
                if not item_templates.getTemplate(templateId) then
                    return false, "Unknown market item"
                end
                local itemTier = M.MARKET_TIERS[templateId]
                if not canBuyMarketTier(tier.refillTier, itemTier) then
                    return false, "Gear tier not covered by upkeep"
                end
                local item = inventory.createItemFromTemplate(templateId, {
                    quantity = request.quantity,
                })
                if not item then
                    return false, "Unknown market item"
                end
                plannedGear[#plannedGear + 1] = {
                    templateId = templateId,
                    tier = itemTier,
                    item = item,
                    location = request.location or inventory.LOCATIONS.PACK,
                }
            end

            local canAdd, reason = canAddPlannedItemsToInventory(actor.inventory, plannedGear)
            if not canAdd then
                return false, reason
            end
        end

        local repairRequests = normalizeRepairRequests(opts.repairItems or opts.repairGear or opts.repairs or opts.repairItemIds)
        local plannedRepairs = {}
        if #repairRequests > 0 then
            if not tier.refillTier then
                return false, "Upkeep tier cannot repair gear"
            end
            if not actor.inventory or not actor.inventory.findItem then
                return false, "No inventory for upkeep repair"
            end
            for _, request in ipairs(repairRequests) do
                local item = actor.inventory:findItem(request.itemId)
                if not item then
                    return false, "Repair item not found"
                end
                if not item.destroyed and (not item.notches or item.notches <= 0) then
                    return false, "Item is not damaged"
                end

                local repairTier = itemMarketTier(item, request)
                if not canBuyMarketTier(tier.refillTier, repairTier) then
                    return false, "Repair tier not covered by upkeep"
                end
                plannedRepairs[#plannedRepairs + 1] = {
                    item = item,
                    itemId = item.id,
                    templateId = request.templateId or item.templateId,
                    tier = repairTier,
                    wasDestroyed = item.destroyed == true,
                    previousNotches = item.notches or 0,
                }
            end
        end

        if not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        local refilledGear = {}
        for _, planned in ipairs(plannedGear) do
            local added = actor.inventory:addItem(planned.item, planned.location)
            if added then
                refilledGear[#refilledGear + 1] = planned
            end
        end

        local repairedGear = {}
        for _, repair in ipairs(plannedRepairs) do
            repair.item.destroyed = false
            repair.item.notches = 0
            repairedGear[#repairedGear + 1] = repair
        end

        local healing = nil
        local resolveRefreshed = nil
        local pactBreaks = nil
        if tier.luxurious then
            healing = healAllWounds(actor)
            pactBreaks = self:breakPactsForRecoveryResult(actor, "all_wounds_healed")
            resolveRefreshed = refreshResolve(actor)
        end

        local detail = {
            actor = actor,
            step = M.STEPS.UPKEEP,
            tier = tier.id,
            cost = cost,
            baseCost = tier.cost,
            refillTier = tier.refillTier,
            refilledGear = refilledGear,
            repairedGear = repairedGear,
            recoveryAllowed = tier.recoveryAllowed,
            luxurious = tier.luxurious,
            healing = healing,
            pactBreaks = pactBreaks,
            resolveRefreshed = resolveRefreshed,
            remainingGold = currency.getGold(actor),
            result = "upkeep_resolved",
        }

        actor.cityUpkeep = detail
        self.upkeepCompleted[id] = detail
        self.eventBus:emit(events.EVENTS.CITY_UPKEEP_RESOLVED, detail)

        return true, "upkeep_resolved", detail
    end

    function controller:spendBondForUpkeepRecovery(actor, bondTargetId, spendType, opts)
        opts = opts or {}
        local id = actorId(actor)
        if not id then
            return false, "No active adventurer"
        end

        local upkeep = self.upkeepCompleted[id] or actor.cityUpkeep
        if not upkeep then
            return false, "Upkeep not resolved"
        end
        if not upkeep.recoveryAllowed then
            return false, "Upkeep tier does not allow recovery"
        end
        if actor.conditions and actor.conditions.starving then
            return false, "Starving adventurers cannot recover"
        end

        if not actor.bonds or not actor.bonds[bondTargetId] then
            return false, "No bond with that entity"
        end
        if not actor.bonds[bondTargetId].charged then
            return false, "Bond is not charged"
        end

        if actor.conditions and actor.conditions.stressed and spendType ~= "clear_stress" then
            return false, "Must clear stress first"
        end

        local extraBondTargetId = nil
        if spendType == "heal_wound" and recoveryNeedsExtraBond(actor) then
            local err = nil
            extraBondTargetId, err = selectExtraRecoveryBond(actor, bondTargetId, opts)
            if not extraBondTargetId then
                return false, err
            end
        end

        actor.bonds[bondTargetId].charged = false
        if extraBondTargetId then
            actor.bonds[extraBondTargetId].charged = false
        end

        local result = "unknown"
        local pactBreaks = {}
        if spendType == "clear_stress" then
            if actor.conditions then
                actor.conditions.stressed = false
            end
            result = "stress_cleared"
            pactBreaks = self:breakPactsForRecoveryResult(actor, result)
        elseif spendType == "heal_wound" then
            if actor.healWound then
                local healResult, err = actor:healWound()
                if healResult then
                    result = healResult
                    pactBreaks = self:breakPactsForRecoveryResult(actor, result)
                else
                    actor.bonds[bondTargetId].charged = true
                    if extraBondTargetId then
                        actor.bonds[extraBondTargetId].charged = true
                    end
                    return false, err or "cannot_heal"
                end
            else
                actor.bonds[bondTargetId].charged = true
                if extraBondTargetId then
                    actor.bonds[extraBondTargetId].charged = true
                end
                return false, "cannot_heal"
            end
        elseif spendType == "regain_resolve" then
            if actor.regainResolve then
                actor:regainResolve(1)
            else
                actor.resolve = actor.resolve or { current = 0, max = 0 }
                actor.resolve.current = math.min(actor.resolve.max or actor.resolve.current or 0, (actor.resolve.current or 0) + 1)
            end
            result = "resolve_regained"
        else
            actor.bonds[bondTargetId].charged = true
            return false, "Unknown recovery spend"
        end

        if actor.conditions and not actor.conditions.stressed and actor.conditions.staggered then
            actor.conditions.staggered = false
            local staggeredBreaks = self:breakPactsForRecoveryResult(actor, "staggered_healed")
            for _, pactBreak in ipairs(staggeredBreaks) do
                pactBreaks[#pactBreaks + 1] = pactBreak
            end
        end

        local detail = {
            actor = actor,
            step = M.STEPS.UPKEEP,
            bondTargetId = bondTargetId,
            extraBondTargetId = extraBondTargetId,
            bondCost = extraBondTargetId and 2 or 1,
            spendType = spendType,
            result = result,
            maledictionExtraBondRecoveryCost = extraBondTargetId ~= nil,
            pactBreaks = pactBreaks,
        }
        upkeep.recoveryBondSpends = upkeep.recoveryBondSpends or {}
        upkeep.recoveryBondSpends[#upkeep.recoveryBondSpends + 1] = detail
        self.eventBus:emit(events.EVENTS.CITY_UPKEEP_RECOVERY_BOND_SPENT, detail)

        return true, result, detail
    end

    function controller:drawMinorCard(actionData)
        actionData = actionData or {}
        if actionData.card or actionData.drawnCard then
            return actionData.card or actionData.drawnCard, false
        end

        local deck = actionData.deck or actionData.playerDeck or actionData.minorDeck or self.playerDeck
        if deck and deck.draw then
            return deck:draw(), true, deck
        end

        return nil, false, deck
    end

    function controller:drawMajorCard(actionData)
        actionData = actionData or {}
        if actionData.hangoverCard or actionData.majorCard or actionData.card then
            return actionData.hangoverCard or actionData.majorCard or actionData.card, false
        end

        local deck = actionData.gmDeck or actionData.majorDeck or self.gmDeck
        if deck and deck.draw then
            return deck:draw(), true, deck
        end

        return nil, false, deck
    end

    function controller:applyBankingReturns(actorOrGuild, opts)
        opts = opts or {}
        local actors = actorOrGuild or self.guild or {}
        if actorId(actors) then
            actors = { actors }
        end

        local rate = tonumber(opts.rate) or 0.02
        local details = {}
        for _, actor in ipairs(actors or {}) do
            local id = actorId(actor)
            local bank = getBank(actor)
            local principal = bank and bank.gold or 0
            local interest = 0
            if id and not self.bankReturnsApplied[id] then
                interest = math.floor(principal * rate)
                bank.gold = principal + interest
                self.bankReturnsApplied[id] = true
            end
            details[#details + 1] = {
                actor = actor,
                principal = principal,
                interest = interest,
                balance = bank and bank.gold or 0,
                applied = interest > 0 or (id ~= nil and self.bankReturnsApplied[id] == true),
            }
        end

        return true, "banking_returns_applied", details
    end

    function controller:resolveBanking(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.banking or actionData
        local mode = tostring(request.mode or request.operation or ""):lower()
        local withdrawMode = mode == "withdraw" or mode == "withdrawal"
        local depositGold = math.floor(tonumber(request.depositGold or (not withdrawMode and request.gold) or (not withdrawMode and request.amount)) or 0)
        local withdrawGold = math.floor(tonumber(request.withdrawGold or request.goldWithdrawal or request.withdrawAmount or request.withdraw) or 0)
        if withdrawMode and withdrawGold <= 0 then
            withdrawGold = math.floor(tonumber(request.gold or request.amount) or 0)
        end

        local itemIds = normalizeList(request.depositItemIds or request.depositItems or (not withdrawMode and request.itemIds) or (not withdrawMode and request.items) or (not withdrawMode and request.itemId))
        local withdrawItemIds = normalizeList(request.withdrawItemIds or request.withdrawItems or request.withdrawItemId)
        if withdrawMode and #withdrawItemIds == 0 then
            withdrawItemIds = normalizeList(request.itemIds or request.items or request.itemId)
        end

        if depositGold <= 0 and #itemIds == 0 and withdrawGold <= 0 and #withdrawItemIds == 0 then
            return false, "Nothing to bank"
        end
        if depositGold > 0 and currency.getGold(actor) < depositGold then
            return false, "Not enough gold"
        end

        local bank = getBank(actor)
        if withdrawGold > bank.gold then
            return false, "Not enough banked gold"
        end

        local inv = actor and actor.inventory
        local itemsToDeposit = {}
        if #itemIds > 0 then
            if not inv or not inv.findItem or not inv.removeItem then
                return false, "No inventory for banking"
            end
            for _, itemId in ipairs(itemIds) do
                local item = inv:findItem(itemId)
                if not item then
                    return false, "Banking item not found"
                end
                itemsToDeposit[#itemsToDeposit + 1] = item
            end
        end

        local itemsToWithdraw = {}
        if #withdrawItemIds > 0 then
            if not inv or not inv.addItem then
                return false, "No inventory for banking"
            end
            for _, itemId in ipairs(withdrawItemIds) do
                local item = findBankedItem(bank, itemId)
                if not item then
                    return false, "Banked item not found"
                end
                itemsToWithdraw[#itemsToWithdraw + 1] = item
            end

            local location = request.withdrawLocation or request.location or inventory.LOCATIONS.PACK
            local canAdd, reason = canAddBankedItemsToInventory(inv, itemsToWithdraw, location)
            if not canAdd then
                return false, reason
            end
        end

        if depositGold > 0 and not currency.spendGold(actor, depositGold) then
            return false, "Not enough gold"
        end

        local depositedItems = {}
        for _, item in ipairs(itemsToDeposit) do
            local removed = inv:removeItem(item.id)
            if removed then
                bank.items[#bank.items + 1] = removed
                depositedItems[#depositedItems + 1] = removed
            end
        end
        bank.gold = bank.gold + depositGold

        local withdrawnItems = {}
        local withdrawalLocation = request.withdrawLocation or request.location or inventory.LOCATIONS.PACK
        if withdrawGold > 0 then
            bank.gold = bank.gold - withdrawGold
            currency.addGold(actor, withdrawGold)
        end
        for _, item in ipairs(itemsToWithdraw) do
            local _, index = findBankedItem(bank, item.id)
            local removed = index and table.remove(bank.items, index)
            if removed then
                local added = inv:addItem(removed, withdrawalLocation)
                if added then
                    withdrawnItems[#withdrawnItems + 1] = removed
                end
            end
        end

        return true, "banking_complete", {
            actor = actor,
            action = M.ACTIONS.BANKING,
            bank = bank,
            goldDeposited = depositGold,
            itemsDeposited = depositedItems,
            goldWithdrawn = withdrawGold,
            itemsWithdrawn = withdrawnItems,
            bankedGold = bank.gold,
            result = "banking_complete",
        }
    end

    function controller:resolveBegAndBusk(actor, actionData)
        local card, shouldDiscard, drawnDeck = self:drawMinorCard(actionData)
        if not card then
            return false, "Requires minor arcana draw"
        end

        local wands = getWands(actor)
        local gold = math.max(0, (tonumber(card.value) or 0) + wands)
        currency.addGold(actor, gold)

        if shouldDiscard and drawnDeck and drawnDeck.discard then
            drawnDeck:discard(card)
        end

        return true, "beg_and_busk_resolved", {
            actor = actor,
            action = M.ACTIONS.BEG_AND_BUSK,
            card = card,
            wands = wands,
            gold = gold,
            result = "beg_and_busk_resolved",
        }
    end

    function controller:resolveBuild(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.build or actionData
        if request.reasonable == false or request.approved == false then
            return false, "Building project not approved"
        end

        local description = tostring(request.description or request.name or request.title or "")
        if description == "" then
            return false, "Building description required"
        end

        local syllables = resolveSyllables(request)
        if syllables <= 0 then
            return false, "Building description required"
        end

        local projectId = normalizeProjectId(request.projectId or request.id or description)
        if self.buildings[projectId] then
            return false, "Building project already exists"
        end

        local cost = syllables * M.BUILD_COST_PER_SYLLABLE
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end
        if not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        local building = {
            id = projectId,
            name = request.name or request.title or description,
            description = description,
            artisan = request.artisan or request.designer,
            syllables = syllables,
            cost = cost,
            builtBy = actor,
            builtById = actorId(actor),
            complete = true,
        }
        self.buildings[projectId] = building

        return true, "building_complete", {
            actor = actor,
            action = M.ACTIONS.BUILD,
            building = building,
            projectId = projectId,
            syllables = syllables,
            cost = cost,
            result = "building_complete",
        }
    end

    function controller:resolveCampAction(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.campActionRequest or actionData
        local campActionId = normalizeCampActionId(
            request.campAction or
            request.campActionId or
            request.camp_action or
            request.camp_action_id or
            request.campType
        )
        if campActionId == "" then
            return false, "Camp Action required"
        end

        local actionDef = camp_actions.getAction(campActionId)
        if not actionDef then
            return false, "Unknown Camp Action"
        end

        local campActionData = shallowCopy(actionData)
        if type(request) == "table" then
            for k, v in pairs(request) do
                if campActionData[k] == nil then
                    campActionData[k] = v
                end
            end
        end
        campActionData.type = campActionId
        campActionData.actor = actor
        campActionData.target = campActionData.target or request.target

        local context = cityCampActionContext(self, actionData)
        local ok, result, payload = camp_actions.resolveAction(campActionData, context)
        if not ok then
            return false, result
        end

        local additionalCityActors = {}
        if campActionId == "train" and campActionData.target then
            additionalCityActors[#additionalCityActors + 1] = {
                actor = campActionData.target,
                action = M.ACTIONS.CAMP_ACTION,
                result = "camp_train_mentor",
            }
        end

        return true, "camp_action_complete", {
            actor = actor,
            action = M.ACTIONS.CAMP_ACTION,
            campAction = campActionId,
            campActionName = actionDef.name,
            campResult = result,
            payload = payload,
            additionalCityActors = additionalCityActors,
            result = "camp_action_complete",
        }
    end

    function controller:resolveCommissionCraft(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.commission or actionData.craft or actionData
        if request.reasonable == false or request.approved == false then
            return false, "Commission not approved"
        end

        local description = tostring(request.description or request.name or request.title or "")
        if description == "" then
            return false, "Commission description required"
        end

        local scale = normalizeCommissionScale(request.scale or request.category or request.tier)
        local rate = M.COMMISSION_CRAFT_RATES[scale]
        if not rate then
            return false, "Commission scale required"
        end

        local syllables = resolveSyllables(request)
        if syllables <= 0 then
            return false, "Commission description required"
        end

        local commissionId = normalizeProjectId(request.commissionId or request.id or description)
        if self.commissions[commissionId] then
            return false, "Commission already exists"
        end

        local cost = syllables * rate
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end
        if not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        local commission = {
            id = commissionId,
            name = request.name or request.title or description,
            description = description,
            merchant = request.merchant or request.artisan or request.crafter,
            scale = scale,
            ratePerSyllable = rate,
            syllables = syllables,
            cost = cost,
            commissionedBy = actor,
            commissionedById = actorId(actor),
            complete = true,
        }
        self.commissions[commissionId] = commission

        return true, "commission_complete", {
            actor = actor,
            action = M.ACTIONS.COMMISSION_CRAFT,
            commission = commission,
            commissionId = commissionId,
            scale = scale,
            ratePerSyllable = rate,
            syllables = syllables,
            cost = cost,
            result = "commission_complete",
        }
    end

    function controller:resolveHoldFuneral(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.funeral or actionData
        local deceased = request.deceased or request.deadAdventurer or request.previousAdventurer
        local heir = request.newAdventurer or request.heir or request.recipient or actor
        local previousXP = tonumber(request.previousXP or request.deceasedXP or (deceased and deceased.xp))
        local xpReclaimed = math.floor(tonumber(request.xpReclaimed or request.xp or request.amount) or 0)

        if xpReclaimed <= 0 then
            return false, "Funeral XP required"
        end
        if not previousXP then
            return false, "Deceased XP required"
        end
        if xpReclaimed > previousXP then
            return false, "Cannot reclaim more XP than the deceased had"
        end
        if not heir then
            return false, "Funeral recipient required"
        end

        local cost = xpReclaimed * M.FUNERAL_COST_PER_XP
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end
        if not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        addXP(heir, xpReclaimed)
        heir.inheritedXP = (tonumber(heir.inheritedXP) or 0) + xpReclaimed

        local funeral = {
            deceased = deceased,
            deceasedId = actorId(deceased),
            deceasedName = request.deceasedName or (deceased and deceased.name),
            previousXP = previousXP,
            heir = heir,
            heirId = actorId(heir),
            xpReclaimed = xpReclaimed,
            cost = cost,
            paidBy = actor,
            paidById = actorId(actor),
        }
        self.funerals[#self.funerals + 1] = funeral

        return true, "funeral_held", {
            actor = actor,
            action = M.ACTIONS.HOLD_FUNERAL,
            funeral = funeral,
            xpReclaimed = xpReclaimed,
            cost = cost,
            recipient = heir,
            result = "funeral_held",
        }
    end

    function controller:resolveCarouse(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.carouse or actionData
        local percent, xpGained = normalizeCarouseSpend(request)
        if not percent then
            return false, "Choose 50% or 100% carousing spend"
        end

        local baseGold = math.floor(tonumber(request.goldBroughtBack or request.broughtBackGold or request.earnings) or currency.getGold(actor))
        local spend = math.floor(baseGold * percent)
        if spend <= 0 then
            return false, "No gold to carouse"
        end
        if currency.getGold(actor) < spend then
            return false, "Not enough gold"
        end

        local hangoverCard, shouldDiscard, drawnDeck = self:drawMajorCard(actionData)
        if not hangoverCard then
            return false, "Requires major arcana draw"
        end

        if not currency.spendGold(actor, spend) then
            return false, "Not enough gold"
        end
        addXP(actor, xpGained)

        if shouldDiscard and drawnDeck and drawnDeck.discard then
            drawnDeck:discard(hangoverCard)
        end

        local minorDiscard = request.minorDiscardCard
        local minorDeck = request.playerDeck or request.minorDeck or self.playerDeck
        if not minorDiscard and minorDeck and minorDeck.peekDiscard then
            minorDiscard = minorDeck:peekDiscard()
        end

        local hangover = M.HANGOVER_TABLE[hangoverCard.value] or {
            id = "unknown_hangover",
            title = "Unknown Hangover",
        }
        local hangoverOutcome = resolveHangoverOutcome(actor, hangover, minorDiscard)

        local detail = {
            actor = actor,
            action = M.ACTIONS.CAROUSE,
            percent = percent,
            baseGold = baseGold,
            goldSpent = spend,
            xpGained = xpGained,
            hangoverCard = hangoverCard,
            hangover = hangover,
            hangoverOutcome = hangoverOutcome,
            minorDiscard = minorDiscard,
            result = "carouse_resolved",
        }
        actor.lastCarouse = detail
        appendActorRecord(actor, "carouseHangovers", hangoverOutcome)

        return true, "carouse_resolved", detail
    end

    function controller:resolvePrepareComponents(actor, actionData)
        actionData = actionData or {}
        if not actor or not actor.inventory or not actor.inventory.addItem then
            return false, "No inventory for components"
        end

        local requested = normalizeList(
            actionData.componentIds or actionData.components or actionData.componentId or actionData.spellIds or actionData.spellId
        )
        if #requested == 0 then
            return false, "components_required"
        end

        local components = {}
        local slotsNeeded = 0
        for _, ref in ipairs(requested) do
            local templateId = resolveComponentTemplateId(ref)
            if not templateId then
                return false, "Unknown spell component"
            end
            local item = inventory.createItemFromTemplate(templateId)
            if not item then
                return false, "Unknown spell component"
            end
            local props = item.properties or {}
            if props.spellComponent ~= true then
                return false, "Unknown spell component"
            end
            components[#components + 1] = item
            slotsNeeded = slotsNeeded + (item.stackable and 1 or item.size or 1)
        end

        local location = actionData.location or inventory.LOCATIONS.PACK
        if not actor.inventory[location] then
            return false, "invalid_location"
        end
        if actor.inventory.availableSlots and actor.inventory:availableSlots(location) < slotsNeeded then
            return false, "insufficient_slots"
        end

        for _, item in ipairs(components) do
            local added, reason = actor.inventory:addItem(item, location)
            if not added then
                return false, reason or "insufficient_slots"
            end
        end

        return true, "components_prepared", {
            actor = actor,
            action = M.ACTIONS.PREPARE_COMPONENTS,
            components = components,
            count = #components,
            location = location,
            result = "components_prepared",
        }
    end

    function controller:resolvePrayAtMythraeum(actor, actionData)
        actionData = actionData or {}
        local durations = actor and actor.conditionDurations
        local cleared = {}

        if durations then
            for condition, duration in pairs(durations) do
                if duration and duration["until"] == "city_prayer" then
                    if actor.conditions then
                        actor.conditions[condition] = false
                    end
                    if actor[condition] ~= nil then
                        actor[condition] = false
                    end
                    durations[condition] = nil
                    cleared[#cleared + 1] = condition
                    self.eventBus:emit(events.EVENTS.CONDITION_EXPIRED, {
                        actor = actor,
                        condition = condition,
                        timing = "city_prayer",
                        action = M.ACTIONS.PRAY_AT_MYTHRAEUM,
                    })
                end
            end

            if next(durations) == nil then
                actor.conditionDurations = nil
            end
        end

        if #cleared == 0 then
            return false, "No city-prayer maleficence to clear"
        end

        local detail = {
            actor = actor,
            action = M.ACTIONS.PRAY_AT_MYTHRAEUM,
            location = actionData.location or "mythraeum",
            conditionsCleared = cleared,
            result = "city_prayer_complete",
        }
        actor.lastCityPrayer = detail

        return true, "city_prayer_complete", detail
    end

    function controller:resolveTrain(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.training or actionData
        local talentId = normalizeTalentId(request.talentId or request.talent or request.id)
        if talentId == "" then
            return false, "Choose a talent to train"
        end

        local trainingOk, training = talent_catalog.validateTraining(actor, talentId, {
            cityExpert = true,
            trainerAvailable = request.trainerAvailable,
        })
        if not trainingOk then
            return false, training.reason
        end

        local xpAmount = math.max(1, tonumber(request.xp or request.amount or request.xpInvested) or 1)
        local costPerXP = tonumber(request.costPerXP or actionData.costPerXP) or M.TRAINING_COST_PER_XP
        local cost = xpAmount * costPerXP
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end

        actor.talents = actor.talents or {}
        local talent = actor.talents[talentId]
        if type(talent) == "table" and talent.mastered == true then
            return false, "Talent already mastered"
        end

        if not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        if type(talent) ~= "table" then
            talent = {
                mastered = false,
                wounded = false,
                xp_invested = 0,
            }
            actor.talents[talentId] = talent
        end

        talent.mastered = talent.mastered == true
        talent.wounded = talent.wounded == true
        talent.mentored = training.mentored == true
        talent.pathTrained = training.ownPath == true
        talent.path = training.path or talent.path
        talent.trainingKind = training.kind
        talent.cityTrained = true
        talent.trainerId = request.trainerId or request.expertId
        talent.trainerName = request.trainerName or request.expertName
        talent.xp_invested = (talent.xp_invested or 0) + xpAmount
        talent.prepared_uses = talent.xp_invested
        talent.uses_remaining = (talent.uses_remaining or 0) + xpAmount
        if talent.xp_invested >= 7 then
            talent.mastered = true
        end

        return true, "training_complete", {
            actor = actor,
            action = M.ACTIONS.TRAIN,
            talentId = talentId,
            xpInvested = xpAmount,
            totalXPInvested = talent.xp_invested,
            usesRemaining = talent.uses_remaining,
            mastered = talent.mastered,
            cost = cost,
            costPerXP = costPerXP,
            trainingKind = training.kind,
            path = training.path,
            actorPath = training.actorPath,
            mentored = talent.mentored,
            pathTrained = talent.pathTrained,
            talent = talent,
            result = "training_complete",
        }
    end

    function controller:resolveChooseMonsterHunterFoe(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.hunter or actionData
        if type(actor and actor.talents) ~= "table" then
            return false, "Requires Monster Hunter talent"
        end

        local function findTalentById(wanted)
            wanted = normalizeTalentId(wanted)
            if wanted == "" then
                return nil, nil
            end
            for key, value in pairs(actor.talents) do
                if normalizeTalentId(key) == wanted then
                    return key, value
                end
                if type(value) == "table" and normalizeTalentId(value.id or value.name or value.talentId) == wanted then
                    return key, value
                end
            end
            return nil, nil
        end

        local talentKey, talent = findTalentById(request.talentId or request.talent)
        if not talentKey then
            local requestedFoeKey = normalizeTalentId(request.foe or request.hatedFoe or request.category)
            if requestedFoeKey ~= "" then
                talentKey, talent = findTalentById(requestedFoeKey .. "_hunter")
            end
        end
        if not talentKey then
            for _, candidate in ipairs(HUNTER_TALENT_IDS) do
                talentKey, talent = findTalentById(candidate)
                if talentKey then
                    break
                end
            end
        end
        if not talentKey then
            return false, "Requires Monster Hunter talent"
        end
        if type(talent) == "table" and talent.wounded == true then
            return false, "Monster Hunter talent is wounded"
        end

        if type(talent) ~= "table" then
            talent = {
                mastered = talent == true,
                wounded = false,
            }
            actor.talents[talentKey] = talent
        end

        local function foeLabel(value)
            local key = normalizeTalentId(value)
            if HUNTER_FOE_LABELS[key] then
                return HUNTER_FOE_LABELS[key]
            end
            local text = tostring(value or ""):gsub("_", " ")
            text = text:gsub("(%a)([%w']*)", function(first, rest)
                return first:upper() .. rest:lower()
            end)
            return text
        end

        local foe = request.foe or request.hatedFoe or request.category or talent.foe or HUNTER_DEFAULT_FOES[normalizeTalentId(talentKey)]
        if not foe or tostring(foe) == "" then
            return false, "Choose hated foe"
        end
        foe = foeLabel(foe)

        local specialization = request.specialization or request.speciality or request.specialty or request.creature or
            request.species or request.targetType
        if not specialization or tostring(specialization) == "" then
            return false, "Choose hunter specialization"
        end
        specialization = tostring(specialization)

        local tags = {}
        local function addTag(value)
            if value == nil then
                return
            end
            local tag = slugify(value)
            if tag ~= "" then
                tags[#tags + 1] = tag
            end
        end
        addTag(specialization)
        for _, tag in ipairs(normalizeList(request.specializationTags or request.tags)) do
            addTag(tag)
        end

        local previous = {
            foe = talent.foe,
            specialization = talent.specialization,
            specializationTags = talent.specializationTags,
        }
        talent.foe = foe
        talent.hatedFoe = foe
        talent.specialization = specialization
        talent.specializationTags = tags
        talent.motif = foe .. " Hunter"
        talent.changedInCity = true

        local change = {
            action = M.ACTIONS.CHOOSE_MONSTER_HUNTER_FOE,
            talentId = normalizeTalentId(talentKey),
            previous = previous,
            foe = foe,
            specialization = specialization,
            specializationTags = tags,
            reason = request.reason or request.cause,
            motif = talent.motif,
        }
        appendActorRecord(actor, "monsterHunterChanges", change)

        return true, "monster_hunter_foe_chosen", {
            actor = actor,
            action = M.ACTIONS.CHOOSE_MONSTER_HUNTER_FOE,
            change = change,
            talent = talent,
            talentId = change.talentId,
            foe = foe,
            specialization = specialization,
            specializationTags = tags,
            result = "monster_hunter_foe_chosen",
        }
    end

    function controller:resolveSupport(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.project or actionData
        local projectId = normalizeProjectId(request.projectId or request.id or request.name)
        if projectId == "" then
            return false, "Choose a project to support"
        end

        local contribution = math.floor(tonumber(request.gold or request.cost or request.contribution or request.spend) or 0)
        if contribution <= 0 then
            return false, "Support requires gold"
        end

        local project = self.projects[projectId]
        if not project then
            local complexity = tonumber(request.complexity or request.stepsRequired or request.totalSteps)
            if not complexity then
                return false, "Project complexity required"
            end
            complexity = math.floor(complexity)
            if complexity < 2 or complexity > 8 then
                return false, "Project complexity must be 2-8"
            end
            project = {
                id = projectId,
                name = request.name or request.title or projectId,
                complexity = complexity,
                progress = tonumber(request.progress or request.stepsCompleted) or 0,
                contributions = {},
                complete = false,
            }
            self.projects[projectId] = project
        end

        if project.complete then
            return false, "Project already complete"
        end

        if currency.getGold(actor) < contribution then
            return false, "Not enough gold"
        end
        if not currency.spendGold(actor, contribution) then
            return false, "Not enough gold"
        end

        project.progress = math.min((project.progress or 0) + 1, project.complexity or 1)
        project.contributions = project.contributions or {}
        project.contributions[#project.contributions + 1] = {
            actor = actor,
            actorId = actorId(actor),
            gold = contribution,
            description = request.description or request.method,
        }
        if project.progress >= (project.complexity or 1) then
            project.complete = true
        end

        return true, "project_supported", {
            actor = actor,
            action = M.ACTIONS.SUPPORT,
            project = project,
            projectId = project.id,
            contribution = contribution,
            progress = project.progress,
            complexity = project.complexity,
            complete = project.complete,
            result = "project_supported",
        }
    end

    function controller:resolveResearch(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.research or actionData
        local topic = request.topic or request.subject or request.question
        if not topic or tostring(topic) == "" then
            return false, "Research topic required"
        end

        local cost = tonumber(request.cost or request.gold) or 50
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end

        local testResult = request.testResult or request.outcome
        local card, shouldDiscard, drawnDeck
        if not testResult then
            card, shouldDiscard, drawnDeck = self:drawMinorCard(actionData)
            if not card then
                return false, "Requires minor arcana draw"
            end
            testResult = fate_resolver.resolveTest(getCups(actor), constants.SUITS.CUPS, card, request.favor)
        end

        if not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        if shouldDiscard and drawnDeck and drawnDeck.discard then
            drawnDeck:discard(card)
        end

        local resultId = testResult.result or testResult.degree
        local questions = 0
        if resultId == fate_resolver.RESULTS.GREAT_SUCCESS or resultId == "great success" then
            questions = 3
        elseif testResult.success == true or resultId == fate_resolver.RESULTS.SUCCESS then
            questions = 1
        end

        local detail = {
            actor = actor,
            action = M.ACTIONS.RESEARCH,
            topic = topic,
            cost = cost,
            card = card,
            testResult = testResult,
            questions = questions,
            result = "research_complete",
        }
        actor.lastCityResearch = detail

        return true, "research_complete", detail
    end

    function controller:resolveDistrictItemPurchase(actor, actionData, config)
        actionData = actionData or {}
        config = config or {}
        local request = actionData.request or actionData.purchase or actionData
        if not actor or not actor.inventory or not actor.inventory.addItem then
            return false, "No inventory for purchase"
        end

        local quantity = math.max(1, math.floor(tonumber(request.quantity or request.count) or 1))
        local location = request.location or config.location or inventory.LOCATIONS.PACK
        local plannedItems, itemErr = createPlannedTemplateItems(config.templateId, quantity, location)
        if not plannedItems then
            return false, itemErr
        end

        local canAdd, reason = canAddPlannedItemsToInventory(actor.inventory, plannedItems)
        if not canAdd then
            return false, reason
        end

        local costPerItem = tonumber(request.costPerItem or config.costPerItem) or 0
        local cost = math.max(0, costPerItem * quantity)
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end
        if cost > 0 and not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        local items, addErr = addPlannedItems(actor.inventory, plannedItems)
        if not items then
            return false, addErr
        end

        return true, config.result, {
            actor = actor,
            action = config.action,
            items = items,
            templateId = config.templateId,
            quantity = quantity,
            cost = cost,
            costPerItem = costPerItem,
            location = location,
            result = config.result,
        }
    end

    function controller:resolvePurchaseAmulets(actor, actionData)
        return self:resolveDistrictItemPurchase(actor, actionData, {
            action = M.ACTIONS.PURCHASE_AMULETS,
            templateId = "newt_row_amulet",
            costPerItem = 10,
            result = "amulets_purchased",
        })
    end

    function controller:resolvePurchaseFateHoney(actor, actionData)
        return self:resolveDistrictItemPurchase(actor, actionData, {
            action = M.ACTIONS.PURCHASE_FATE_HONEY,
            templateId = "fate_honey",
            costPerItem = 0,
            result = "fate_honey_purchased",
        })
    end

    function controller:resolvePurchaseFireworks(actor, actionData)
        return self:resolveDistrictItemPurchase(actor, actionData, {
            action = M.ACTIONS.PURCHASE_FIREWORKS,
            templateId = "firework_rocket",
            costPerItem = 25,
            result = "fireworks_purchased",
        })
    end

    function controller:resolveFitProsthetics(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.prosthetic or actionData
        local limb = findLostLimb(actor, request)
        if not limb then
            return false, "Lost limb required"
        end

        actor.prosthetics = actor.prosthetics or {}
        if actor.prosthetics[limb] then
            return false, "Prosthetic already fitted"
        end

        local prosthetic = {
            limb = limb,
            description = request.description or request.name or ("crude " .. limb .. " prosthetic"),
            crude = true,
            cost = 0,
        }
        actor.prosthetics[limb] = prosthetic
        appendActorRecord(actor, "prostheticFittings", prosthetic)

        return true, "prosthetic_fitted", {
            actor = actor,
            action = M.ACTIONS.FIT_PROSTHETICS,
            prosthetic = prosthetic,
            limb = limb,
            cost = 0,
            result = "prosthetic_fitted",
        }
    end

    function controller:resolveVisitGrave(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.graveVisit or actionData
        local funeral = findFuneralRecord(self.funerals, request)
        if not funeral then
            return false, "Funeral record required"
        end

        local target = request.target or request.recipient or actor
        local cost = tonumber(request.cost or request.costGold) or 100
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end

        local cured = cureCurseEffect(self, target, request)
        if not cured then
            return false, "No curse effect to cure"
        end

        if cost > 0 and not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        local graveVisit = {
            funeral = funeral,
            target = target,
            cured = cured,
            cost = cost,
        }
        appendActorRecord(actor, "graveVisits", graveVisit)

        return true, "grave_visited", {
            actor = actor,
            action = M.ACTIONS.VISIT_GRAVE,
            funeral = funeral,
            target = target,
            cured = cured,
            cost = cost,
            result = "grave_visited",
        }
    end

    function controller:resolveMakeover(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.makeover or actionData
        local appearance = request.appearance or request.newAppearance or request.description
        if not appearance or tostring(appearance) == "" then
            return false, "Appearance required"
        end

        local cost = tonumber(request.cost or request.costGold) or 10
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end
        if cost > 0 and not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        local previous = actor.appearance
        actor.appearance = tostring(appearance)
        local record = {
            previousAppearance = previous,
            appearance = actor.appearance,
            cost = cost,
        }
        appendActorRecord(actor, "makeovers", record)

        return true, "makeover_complete", {
            actor = actor,
            action = M.ACTIONS.MAKEOVER,
            previousAppearance = previous,
            appearance = actor.appearance,
            cost = cost,
            result = "makeover_complete",
        }
    end

    function controller:resolveBegForScraps(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.scraps or actionData
        if not actorIsDestitute(self, actor, request) then
            return false, "Destitute upkeep required"
        end
        if not actor or not actor.inventory or not actor.inventory.addItem then
            return false, "No inventory for scraps"
        end

        local template = item_templates.getTemplate("disgusting_ration")
        local stackSize = math.max(1, math.floor(tonumber(template and template.stackSize) or 1))
        local quantity = tonumber(request.quantity or request.count)
        if not quantity then
            quantity = math.max(1, actor.inventory:availableSlots(inventory.LOCATIONS.PACK) * stackSize)
        end
        quantity = math.max(1, math.floor(quantity))

        local plannedItems, itemErr = createPlannedTemplateItems("disgusting_ration", quantity, inventory.LOCATIONS.PACK)
        if not plannedItems then
            return false, itemErr
        end
        local canAdd, reason = canAddPlannedItemsToInventory(actor.inventory, plannedItems)
        if not canAdd then
            return false, reason
        end

        local items, addErr = addPlannedItems(actor.inventory, plannedItems)
        if not items then
            return false, addErr
        end

        return true, "scraps_gathered", {
            actor = actor,
            action = M.ACTIONS.BEG_FOR_SCRAPS,
            items = items,
            templateId = "disgusting_ration",
            quantity = quantity,
            result = "scraps_gathered",
        }
    end

    function controller:resolveFixedCommission(actor, actionData, config)
        actionData = actionData or {}
        config = config or {}
        local request = actionData.request or actionData.commission or actionData
        local description = tostring(request.description or request.subject or request.likeness or request.name or "")
        if description == "" then
            return false, config.requiredMessage or "Commission description required"
        end

        local cost = tonumber(request.cost or request.costGold) or config.cost or 0
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end

        local commissionId = normalizeProjectId(request.commissionId or request.id or (config.kind .. ":" .. description))
        if self.commissions[commissionId] then
            return false, "Commission already exists"
        end
        if cost > 0 and not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        local commission = {
            id = commissionId,
            kind = config.kind,
            name = request.name or description,
            description = description,
            cost = cost,
            commissionedBy = actor,
            commissionedById = actorId(actor),
            complete = true,
        }
        for key, value in pairs(config.extra or {}) do
            commission[key] = value
        end
        self.commissions[commissionId] = commission

        return true, config.result, {
            actor = actor,
            action = config.action,
            commission = commission,
            commissionId = commissionId,
            cost = cost,
            result = config.result,
        }
    end

    function controller:resolveCommissionGargoyle(actor, actionData)
        return self:resolveFixedCommission(actor, actionData, {
            action = M.ACTIONS.COMMISSION_GARGOYLE,
            kind = "gargoyle",
            cost = 50,
            result = "gargoyle_commissioned",
            requiredMessage = "Gargoyle description required",
            extra = {
                admiredInStone = true,
            },
        })
    end

    function controller:resolveCommissionPuppet(actor, actionData)
        return self:resolveFixedCommission(actor, actionData, {
            action = M.ACTIONS.COMMISSION_PUPPET,
            kind = "puppet",
            cost = 10,
            result = "puppet_commissioned",
            requiredMessage = "Puppet likeness required",
            extra = {
                lifelike = true,
            },
        })
    end

    function controller:resolvePillowTalk(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.pillowTalk or actionData
        local character = request.character or request.npc or request.target
        local characterName = request.characterName or request.name or (character and character.name)
        if not characterName or tostring(characterName) == "" then
            return false, "City character required"
        end

        local preference = tostring(request.preference or request.kind or "likes"):lower()
        if preference ~= "likes" and preference ~= "dislikes" then
            return false, "Choose likes or dislikes"
        end

        local social = character and (character.social or character) or {}
        local options = social[preference] or {}
        local rumor = request.rumor or options[1]
        if not rumor or tostring(rumor) == "" then
            return false, "Preference rumor required"
        end

        local cost = tonumber(request.cost or request.costGold) or 10
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end
        if cost > 0 and not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        local record = {
            characterName = characterName,
            preference = preference,
            rumor = rumor,
            cost = cost,
        }
        appendActorRecord(actor, "cityRumors", record)

        return true, "pillow_talk_complete", {
            actor = actor,
            action = M.ACTIONS.PILLOW_TALK,
            characterName = characterName,
            preference = preference,
            rumor = rumor,
            cost = cost,
            result = "pillow_talk_complete",
        }
    end

    function controller:resolveDisposeOfBodies(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.bodyDisposal or actionData
        local body, location = findCarriedItem(actor, request,
            { "bodyId", "corpseId", "itemId" },
            { "body", "corpse", "item" })
        local description = request.description or request.bodyDescription or
            (body and (body.name or body.id)) or request.bodyName
        local count = math.max(1, math.floor(tonumber(request.count or request.quantity) or 1))
        if not body and (not description or tostring(description) == "") then
            return false, "Body required"
        end

        local removed = nil
        if body and body.id and actor and actor.inventory and actor.inventory.removeItem and location then
            removed = actor.inventory:removeItem(body.id)
        end

        local disposal = {
            source = "licehouse",
            description = tostring(description or "body-shaped bundle of meat"),
            count = count,
            item = removed or body,
            removedFromInventory = removed ~= nil,
            location = location,
            noQuestionsAsked = true,
        }
        appendActorRecord(actor, "disposedBodies", disposal)

        return true, "bodies_disposed", {
            actor = actor,
            action = M.ACTIONS.DISPOSE_OF_BODIES,
            disposal = disposal,
            removedItem = removed,
            result = "bodies_disposed",
        }
    end

    function controller:resolveAdopt(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.adoption or actionData
        actor.wards = actor.wards or {}
        local wardName = request.name or request.wardName or request.childName or
            string.format("%s's ward", actor and actor.name or "adventurer")
        local ward = type(request.ward) == "table" and shallowClone(request.ward) or {}
        ward.id = ward.id or request.wardId or string.format("%s_ward_%02d_%s",
            slugify(actorId(actor)), #actor.wards + 1, slugify(wardName))
        ward.name = ward.name or tostring(wardName)
        ward.source = ward.source or "orphanarium"
        ward.citySupportStaff = true
        ward.supportStaff = true
        ward.accompaniesCrawl = false
        ward.canEnterUnderworld = false
        ward.inheritor = request.soleInheritor ~= false and request.inheritor ~= false

        actor.wards[#actor.wards + 1] = ward
        if ward.inheritor then
            actor.soleInheritor = ward
            actor.inheritor = ward
        end

        return true, "ward_adopted", {
            actor = actor,
            action = M.ACTIONS.ADOPT,
            ward = ward,
            soleInheritor = ward.inheritor,
            result = "ward_adopted",
        }
    end

    function controller:resolveLayHigh(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.layHigh or actionData
        local pursuer = request.pursuer or request.offendedParty or request.angryParty or request.creditor or
            "offended party"
        local duration = request.duration or request.time or request.cityActions or request.days or "GM-determined"
        local record = {
            source = "the_gambol",
            pursuer = tostring(pursuer),
            duration = duration,
            heatDiedDown = request.heatDiedDown ~= false,
            pursuerWastesTimeAndMoney = true,
        }
        appendActorRecord(actor, "layingHigh", record)

        return true, "laid_high", {
            actor = actor,
            action = M.ACTIONS.LAY_HIGH,
            layHigh = record,
            result = "laid_high",
        }
    end

    function controller:resolveFenceGoods(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.fence or actionData
        local item, location = findCarriedItem(actor, request,
            { "itemId", "goodsId", "possessionId" },
            { "item", "goods", "possession" })
        local description = request.description or request.name or request.title or
            (item and (item.name or item.id))
        if not item and (not description or tostring(description) == "") then
            return false, "Goods required"
        end

        local price = tonumber(request.price or request.fairPrice or request.salePrice or request.gold)
        local scale = nil
        local syllables = nil
        local rate = nil
        if not price then
            scale = normalizeCommissionScale(request.scale or request.category or request.tier or "adventurer")
            rate = M.COMMISSION_CRAFT_RATES[scale]
            if not rate then
                return false, "Fence price scale required"
            end
            syllables = resolveSyllables({
                syllables = request.syllables or request.syllableCount,
                description = description,
                name = description,
            })
            if syllables <= 0 then
                return false, "Goods required"
            end
            price = syllables * rate
        end
        price = math.max(0, math.floor(price))

        local removed = nil
        if item and item.id and actor and actor.inventory and actor.inventory.removeItem and location then
            removed = actor.inventory:removeItem(item.id)
        end
        currency.addGold(actor, price)

        local sale = {
            source = "curio_curia",
            description = tostring(description or "illicit goods"),
            item = removed or item,
            removedFromInventory = removed ~= nil,
            location = location,
            price = price,
            fairPriceProcedure = true,
            scale = scale,
            syllables = syllables,
            ratePerSyllable = rate,
        }
        appendActorRecord(actor, "fencedGoods", sale)

        return true, "goods_fenced", {
            actor = actor,
            action = M.ACTIONS.FENCE_GOODS,
            sale = sale,
            goldGained = price,
            removedItem = removed,
            result = "goods_fenced",
        }
    end

    function controller:resolveMutation(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.mutation or actionData
        local mutation = {
            source = "cloaca_maxima",
            table = request.tableName or request.sourceTable or "external_random_mutation_table",
            name = request.name or request.mutationName or request.result or "GM-supplied random mutation",
            description = request.description or request.effect,
            random = request.random ~= false,
        }
        actor.mutations = actor.mutations or {}
        actor.mutations[#actor.mutations + 1] = mutation
        appendActorRecord(actor, "cityMutations", mutation)

        return true, "mutation_gained", {
            actor = actor,
            action = M.ACTIONS.MUTATION,
            mutation = mutation,
            result = "mutation_gained",
        }
    end

    function controller:resolveDoodlebug(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.doodlebug or actionData
        if request.destroyed == true or request.givenAway == true or request.given_away == true or
           request.stolen == true then
            return false, "Only legitimately lost Underworld items can be doodlebugged"
        end

        local lostItem = type(request.lostItem) == "table" and request.lostItem or
            (type(request.item) == "table" and request.item or nil)
        local itemName = request.itemName or request.name or request.description or (lostItem and lostItem.name)
        if not itemName or tostring(itemName) == "" then
            return false, "Lost item required"
        end

        local found = request.found
        local roll = request.roll or request.chanceRoll
        if found == nil then
            if roll ~= nil then
                found = (tonumber(roll) or 1) <= 0.5
            else
                found = math.random() <= 0.5
            end
        end

        local returnedItem = nil
        local location = request.location or inventory.LOCATIONS.PACK
        if found then
            returnedItem = lostItem or inventory.createItem({
                id = request.itemId,
                name = tostring(itemName),
                type = request.itemType,
                templateId = request.templateId,
                properties = request.properties or {},
            })
            if actor.inventory and actor.inventory.addItem then
                local added, reason = actor.inventory:addItem(returnedItem, location)
                if not added then
                    return false, reason or "No inventory space"
                end
            end
        end

        local search = {
            source = "mount_of_broken_amphorae",
            itemName = tostring(itemName),
            found = found == true,
            chance = 0.5,
            roll = roll,
            returnedItem = returnedItem,
        }
        appendActorRecord(actor, "doodlebugSearches", search)

        return true, found and "lost_item_found" or "lost_item_not_found", {
            actor = actor,
            action = M.ACTIONS.DOODLEBUG,
            search = search,
            item = returnedItem,
            result = found and "lost_item_found" or "lost_item_not_found",
        }
    end

    function controller:resolveAttendMissKinseysDiningClub(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.diningClub or actionData
        local meat, location = findCarriedItem(actor, request,
            { "meatId", "steakId", "itemId" },
            { "meat", "steak", "item" })
        if not meat and actor.inventory and actor.inventory.findItemByPredicate then
            meat, location = actor.inventory:findItemByPredicate(function(item)
                local props = item.properties or {}
                return item.isMonsterMeat == true or item.type == "monster_meat" or
                    props.monsterMeat == true or props.underworldMeat == true or props.strangeMeat == true
            end)
        end
        if not meat then
            return false, "Strange monster meat required"
        end

        local question = request.question or request.subject
        if not question or tostring(question) == "" then
            return false, "Underworld question required"
        end

        local removed = nil
        if meat.id and actor.inventory and actor.inventory.removeItem and location then
            removed = actor.inventory:removeItem(meat.id)
        end
        local dinner = {
            source = "lichyard_market",
            meat = removed or meat,
            question = tostring(question),
            rumor = request.rumor or request.answer or "something resembling a helpful Underworld rumor",
            attendees = request.attendees or request.guilds,
        }
        appendActorRecord(actor, "missKinseyDinners", dinner)

        return true, "miss_kinseys_dinner_attended", {
            actor = actor,
            action = M.ACTIONS.ATTEND_MISS_KINSEYS_DINING_CLUB,
            dinner = dinner,
            rumor = dinner.rumor,
            removedItem = removed,
            result = "miss_kinseys_dinner_attended",
        }
    end

    function controller:resolveCommissionDwarvenMastercraft(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.commission or actionData.craft or actionData
        if request.reasonable == false or request.approved == false then
            return false, "Commission not approved"
        end

        local description = tostring(request.description or request.name or request.title or "")
        if description == "" then
            return false, "Commission description required"
        end
        local syllables = resolveSyllables(request)
        if syllables <= 0 then
            return false, "Commission description required"
        end
        local cost = syllables * 50
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end
        if not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        local commissionId = normalizeProjectId(request.commissionId or request.id or description)
        local commission = {
            id = commissionId,
            source = "colonies",
            name = request.name or request.title or description,
            description = description,
            syllables = syllables,
            cost = cost,
            mastercraft = true,
            dwarven = true,
            improvement = request.improvement or request.bonus or "GM-determined mastercraft improvement",
            commissionedBy = actor,
            commissionedById = actorId(actor),
        }
        self.commissions[commissionId] = commission

        return true, "dwarven_mastercraft_commissioned", {
            actor = actor,
            action = M.ACTIONS.COMMISSION_DWARVEN_MASTERCRAFT,
            commission = commission,
            commissionId = commissionId,
            syllables = syllables,
            cost = cost,
            result = "dwarven_mastercraft_commissioned",
        }
    end

    function controller:resolveContractAssassination(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.assassination or actionData
        local targetName = request.targetName or request.name or (request.target and request.target.name)
        if not targetName or tostring(targetName) == "" then
            return false, "Assassination target required"
        end
        if request.underworld == true or request.inUnderworld == true or request.location == "underworld" then
            return false, "Court of Coins only targets the Wide World"
        end

        local price = math.floor(tonumber(request.price or request.cost or request.gold or request.priceGold) or 0)
        local paymentItem, paymentLocation = findCarriedItem(actor, request,
            { "paymentItemId", "itemId" },
            { "paymentItem", "payment" })
        if price <= 0 and not paymentItem then
            return false, "Assassination price required"
        end
        if price > 0 and currency.getGold(actor) < price then
            return false, "Not enough gold"
        end
        if price > 0 and not currency.spendGold(actor, price) then
            return false, "Not enough gold"
        end

        local removedPayment = nil
        if paymentItem and paymentItem.id and actor.inventory and actor.inventory.removeItem and paymentLocation then
            removedPayment = actor.inventory:removeItem(paymentItem.id)
        end
        local contract = {
            source = "court_of_coins",
            targetName = tostring(targetName),
            targetScope = "wide_world",
            price = price,
            paymentItem = removedPayment or paymentItem,
            withinMonth = true,
            consented = true,
        }
        appendActorRecord(actor, "assassinationContracts", contract)

        return true, "assassination_contracted", {
            actor = actor,
            action = M.ACTIONS.CONTRACT_ASSASSINATION,
            contract = contract,
            price = price,
            paymentItem = contract.paymentItem,
            result = "assassination_contracted",
        }
    end

    function controller:resolvePicnic(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.picnic or actionData
        local participants = normalizeList(request.participants or request.adventurers or request.invitees)
        local backstories = request.backstories or request.revelations or {}
        local shares = {}
        local seen = {}
        local function addShare(participant, fallback)
            local id = actorId(participant) or tostring(#shares + 1)
            if seen[id] then
                return
            end
            seen[id] = true
            local revelation = backstories[id] or backstories[#shares + 1] or fallback
            shares[#shares + 1] = {
                actor = participant,
                actorId = id,
                revelation = revelation or "An unknown backstory detail is shared.",
            }
        end

        addShare(actor, request.backstory or request.revelation)
        for _, participant in ipairs(participants) do
            addShare(participant)
        end

        local additional = {}
        for _, share in ipairs(shares) do
            if actorId(share.actor) ~= actorId(actor) then
                additional[#additional + 1] = {
                    actor = share.actor,
                    action = M.ACTIONS.PICNIC,
                    result = "picnic_participant",
                }
            end
        end

        local picnic = {
            source = "garden_of_ravenous_roses",
            shares = shares,
            dramaticBackstory = true,
        }
        appendActorRecord(actor, "picnics", picnic)

        return true, "picnic_shared", {
            actor = actor,
            action = M.ACTIONS.PICNIC,
            picnic = picnic,
            shares = shares,
            additionalCityActors = additional,
            result = "picnic_shared",
        }
    end

    function controller:resolveVisitThePit(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.pitVisit or actionData
        local alterations = {}
        if type(request.alterations) == "table" then
            alterations = shallowClone(request.alterations)
        end

        if request.swapAttributes then
            local first = request.swapAttributes[1] or request.swapAttributes.a
            local second = request.swapAttributes[2] or request.swapAttributes.b
            if first and second then
                local oldFirst = actor[first]
                local oldSecond = actor[second]
                actor[first], actor[second] = oldSecond, oldFirst
                if actor.attributes then
                    actor.attributes[first], actor.attributes[second] = actor[first], actor[second]
                end
                alterations[#alterations + 1] = {
                    type = "swap",
                    first = first,
                    second = second,
                    oldFirst = oldFirst,
                    oldSecond = oldSecond,
                }
            end
        end

        local field = request.field or request.attribute
        if field and request.value ~= nil then
            local oldValue = actor[field]
            actor[field] = request.value
            if actor.attributes and actor.attributes[field] ~= nil then
                actor.attributes[field] = request.value
            end
            alterations[#alterations + 1] = {
                type = "set",
                field = field,
                oldValue = oldValue,
                newValue = request.value,
            }
        end

        if #alterations == 0 then
            return false, "Pit alteration required"
        end

        local visit = {
            source = "starfall_pit",
            alterations = alterations,
            tableEditedSheet = true,
            actorInsistsAlwaysTrue = true,
        }
        appendActorRecord(actor, "starfallPitVisits", visit)

        return true, "pit_altered_sheet", {
            actor = actor,
            action = M.ACTIONS.VISIT_THE_PIT,
            visit = visit,
            alterations = alterations,
            result = "pit_altered_sheet",
        }
    end

    function controller:resolveThePlaysTheThing(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.play or actionData
        local companion = request.companion or request.target or request.character
        local companionName = request.companionName or request.characterName or (companion and companion.name)
        local subject = request.subject or request.playSubject or request.topic
        if not companionName or tostring(companionName) == "" then
            return false, "Companion required"
        end
        if not subject or tostring(subject) == "" then
            return false, "Play subject required"
        end

        local cost = tonumber(request.cost or request.costGold) or 25
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end
        if cost > 0 and not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        local outing = {
            source = "broken_smiles_district",
            companion = companion,
            companionName = tostring(companionName),
            subject = tostring(subject),
            opinion = request.opinion or request.reaction or "GM-revealed opinion",
            cost = cost,
        }
        appendActorRecord(actor, "playOutings", outing)

        return true, "companion_opinion_gauged", {
            actor = actor,
            action = M.ACTIONS.THE_PLAYS_THE_THING,
            outing = outing,
            opinion = outing.opinion,
            cost = cost,
            result = "companion_opinion_gauged",
        }
    end

    function controller:resolveExchangeGifts(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.giftExchange or actionData
        local gift, giftLocation = findCarriedItem(actor, request,
            { "giftId", "itemId" },
            { "gift", "item" })
        local giftDescription = request.giftDescription or request.description or (gift and (gift.name or gift.id))
        if not gift and (not giftDescription or tostring(giftDescription) == "") then
            return false, "Gift required"
        end

        local testResult = request.testResult or request.outcome
        local card, shouldDiscard, drawnDeck
        if not testResult then
            card, shouldDiscard, drawnDeck = self:drawMinorCard(actionData)
            if not card then
                return false, "Requires minor arcana draw"
            end
            testResult = fate_resolver.resolveTest(getCups(actor), nil, card, request.favor)
        end

        local removedGift = nil
        if gift and gift.id and actor.inventory and actor.inventory.removeItem and giftLocation then
            removedGift = actor.inventory:removeItem(gift.id)
        end
        if shouldDiscard and drawnDeck and drawnDeck.discard then
            drawnDeck:discard(card)
        end

        local rewardName = testResult.success == true and
            (request.rewardName or request.antiqueName or "Random Antique") or
            (request.rewardName or request.funnyItemName or "Small Funny Item")
        local reward = type(request.rewardItem) == "table" and request.rewardItem or inventory.createItem({
            name = rewardName,
            type = testResult.success == true and "antique" or "funny_item",
            properties = {
                templeGift = true,
                antique = testResult.success == true,
                funny = testResult.success ~= true,
            },
        })
        if actor.inventory and actor.inventory.addItem then
            local added, reason = actor.inventory:addItem(reward, request.location or inventory.LOCATIONS.PACK)
            if not added then
                return false, reason or "No inventory space"
            end
        end

        local exchange = {
            source = "temple_of_gods_wives",
            gift = removedGift or gift,
            giftDescription = tostring(giftDescription or "ceremonial gift"),
            reward = reward,
            success = testResult.success == true,
            testResult = testResult,
        }
        appendActorRecord(actor, "giftExchanges", exchange)

        return true, exchange.success and "antique_received" or "funny_item_received", {
            actor = actor,
            action = M.ACTIONS.EXCHANGE_GIFTS,
            exchange = exchange,
            reward = reward,
            card = card,
            testResult = testResult,
            result = exchange.success and "antique_received" or "funny_item_received",
        }
    end

    function controller:resolveJoinCourtOfWands(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.membership or actionData
        local cost = tonumber(request.cost or request.costGold) or 100
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end
        if cost > 0 and not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        local staff = inventory.createItemFromTemplate("wand_archwood", {
            name = request.staffName or "Archwood Staff",
            weaponType = "staff",
            isWeapon = true,
            isMelee = true,
            properties = {
                archwood = true,
                wand = true,
                staff = true,
                polearm = true,
                gramaryeFocus = true,
            },
        })
        if actor.inventory and actor.inventory.addItem then
            local added, reason = actor.inventory:addItem(staff, request.location or inventory.LOCATIONS.PACK)
            if not added then
                currency.addGold(actor, cost)
                return false, reason or "No inventory space"
            end
        end

        actor.memberships = actor.memberships or {}
        actor.memberships.court_of_wands = {
            joined = true,
            duesPaid = cost,
            archwoodStaffIssued = true,
            gramaryeFocus = true,
        }

        return true, "court_of_wands_joined", {
            actor = actor,
            action = M.ACTIONS.JOIN_COURT_OF_WANDS,
            membership = actor.memberships.court_of_wands,
            staff = staff,
            cost = cost,
            result = "court_of_wands_joined",
        }
    end

    function controller:resolveBuyExoticDrugs(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.purchase or actionData
        if not actor or not actor.inventory or not actor.inventory.addItem then
            return false, "No inventory for purchase"
        end

        local orders = normalizeList(request.drugs or request.items or request.drug or request.drugId or request.id)
        if #orders == 0 then
            return false, "Choose exotic drug"
        end

        local planned = {}
        local purchases = {}
        local totalCost = 0
        local location = request.location or inventory.LOCATIONS.PACK
        for _, order in ipairs(orders) do
            local entry = type(order) == "table" and order or { id = order }
            local drugId = slugify(entry.drugId or entry.id or entry.name or entry.drug or entry[1])
            local config = EXOTIC_DRUGS[drugId]
            local name = entry.name or (config and config.name) or tostring(entry.drugId or entry.id or entry.drug or "Exotic Drug")
            local cost = tonumber(entry.cost or entry.costGold or entry.price or (config and config.cost))
            if not cost then
                return false, "Drug price required"
            end
            local quantity = math.max(1, math.floor(tonumber(entry.quantity or entry.count) or 1))
            local stackSize = math.max(1, math.floor(tonumber(entry.stackSize or (config and config.stackSize)) or 6))
            local remaining = quantity
            while remaining > 0 do
                local itemQuantity = math.min(stackSize, remaining)
                local item = inventory.createItem({
                    name = name,
                    size = 1,
                    stackable = true,
                    stackSize = stackSize,
                    quantity = itemQuantity,
                    properties = {
                        consumable = true,
                        drug = true,
                        exoticDrug = true,
                        dose = true,
                        affliction = entry.affliction or (config and config.affliction) or drugId,
                        stageEffects = entry.stageEffects or (config and config.stageEffects),
                        quitCharges = entry.quitCharges or (config and config.quitCharges),
                    },
                })
                item.drugId = drugId
                planned[#planned + 1] = { item = item, location = entry.location or location }
                remaining = remaining - itemQuantity
            end
            totalCost = totalCost + (cost * quantity)
            purchases[#purchases + 1] = {
                drugId = drugId,
                name = name,
                quantity = quantity,
                costPerDose = cost,
            }
        end

        local canAdd, reason = canAddPlannedItemsToInventory(actor.inventory, planned)
        if not canAdd then
            return false, reason
        end
        if currency.getGold(actor) < totalCost then
            return false, "Not enough gold"
        end
        if totalCost > 0 and not currency.spendGold(actor, totalCost) then
            return false, "Not enough gold"
        end

        local items, addErr = addPlannedItems(actor.inventory, planned)
        if not items then
            currency.addGold(actor, totalCost)
            return false, addErr
        end

        local record = {
            source = "lotus_eaters_district",
            purchases = purchases,
            items = items,
            cost = totalCost,
        }
        appendActorRecord(actor, "exoticDrugPurchases", record)

        return true, "exotic_drugs_purchased", {
            actor = actor,
            action = M.ACTIONS.BUY_EXOTIC_DRUGS,
            purchases = purchases,
            items = items,
            cost = totalCost,
            result = "exotic_drugs_purchased",
        }
    end

    function controller:resolveBloodFeast(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.feast or actionData
        local carcass, carcassLocation = findCarriedItem(actor, request,
            { "carcassId", "monsterCarcassId", "itemId" },
            { "carcass", "monsterCarcass", "item" })
        local carcassDescription = request.carcassDescription or request.monster or request.monsterName or
            (carcass and carcass.name)
        if not carcass and not carcassDescription then
            return false, "Underworld monster carcass required"
        end

        local cost = tonumber(request.cost or request.costGold) or 50
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end
        if cost > 0 and not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        local consumedCarcass = nil
        if carcass and carcassLocation and actor.inventory and actor.inventory.removeItem then
            consumedCarcass = actor.inventory:removeItem(carcass.id)
        else
            consumedCarcass = carcass
        end

        local feast = {
            source = "kobalosgaard",
            cost = cost,
            carcass = consumedCarcass,
            carcassDescription = tostring(carcassDescription or "Underworld monster carcass"),
            nickname = request.nickname or request.orcNickname or "Blood-Friend",
            gifts = request.gifts or "50g in gifts",
        }
        actor.orcNicknames = actor.orcNicknames or {}
        actor.orcNicknames[#actor.orcNicknames + 1] = feast.nickname
        appendActorRecord(actor, "bloodFeasts", feast)

        return true, "blood_feast_joined", {
            actor = actor,
            action = M.ACTIONS.BLOOD_FEAST,
            feast = feast,
            cost = cost,
            nickname = feast.nickname,
            result = "blood_feast_joined",
        }
    end

    function controller:resolveHuffFumes(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.prophecy or actionData
        local words = normalizeList(request.words or request.prompts or request.madLibWords)
        local prophecy = request.prophecy or request.madLib or request.text
        if not prophecy and #words > 0 then
            prophecy = table.concat(words, " ")
        end
        prophecy = prophecy or "The sacred fumes produce an unfinished nonsense prophecy."

        local record = {
            source = "plaza_numina",
            words = words,
            prophecy = prophecy,
            gmMayUseInUnderworldPlanning = true,
        }
        appendActorRecord(actor, "fumeProphecies", record)

        return true, "fume_prophecy_babbled", {
            actor = actor,
            action = M.ACTIONS.HUFF_FUMES,
            prophecy = prophecy,
            words = words,
            result = "fume_prophecy_babbled",
        }
    end

    function controller:resolveStrangeCommunions(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.communion or actionData
        local communion = {
            source = "street_of_heretics",
            service = request.service or request.faith or request.religion or "important religious service",
            expires = "next_expedition",
            uses = 1,
            challengeDrawChoice = true,
            sources = request.sources or { "minor_deck_top", "minor_discard_top" },
        }
        actor.nextExpeditionChallengeDrawChoice = communion
        appendActorRecord(actor, "strangeCommunions", communion)

        return true, "strange_communion_attended", {
            actor = actor,
            action = M.ACTIONS.STRANGE_COMMUNIONS,
            communion = communion,
            result = "strange_communion_attended",
        }
    end

    function controller:resolveAsAboveSoBelow(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.stargazing or actionData
        local deck = request.deck or request.playerDeck or request.minorDeck or self.playerDeck
        local cards = normalizeList(request.cards or request.drawnCards)
        local drewFromDeck = false

        if #cards == 0 then
            if not deck or not deck.draw then
                return false, "Requires minor arcana deck"
            end
            for _ = 1, 3 do
                local card = deck:draw()
                if not card then
                    return false, "Requires three minor arcana cards"
                end
                cards[#cards + 1] = card
            end
            drewFromDeck = true
        end
        if #cards < 3 then
            return false, "Requires three minor arcana cards"
        end

        local ordered = {}
        local order = normalizeList(request.order or request.cardOrder)
        if #order > 0 then
            for _, ref in ipairs(order) do
                local index = tonumber(ref)
                if index and cards[index] then
                    ordered[#ordered + 1] = cards[index]
                else
                    local wanted = tostring(ref)
                    for _, card in ipairs(cards) do
                        if tostring(card.id or card.name or "") == wanted then
                            ordered[#ordered + 1] = card
                            break
                        end
                    end
                end
            end
        else
            ordered = normalizeList(request.orderedCards)
            if #ordered == 0 then
                ordered = cards
            end
        end
        if #ordered ~= #cards then
            return false, "Reorder all drawn cards"
        end

        if drewFromDeck and deck and deck.draw_pile then
            for i = #ordered, 1, -1 do
                deck.draw_pile[#deck.draw_pile + 1] = ordered[i]
            end
        end

        local stargazing = {
            source = "sidereal_house",
            drawnCards = cards,
            orderedCards = ordered,
            reorderedDeck = drewFromDeck and deck and deck.draw_pile ~= nil,
        }
        appendActorRecord(actor, "stargazingReadings", stargazing)

        return true, "minor_deck_reordered", {
            actor = actor,
            action = M.ACTIONS.AS_ABOVE_SO_BELOW,
            drawnCards = cards,
            orderedCards = ordered,
            stargazing = stargazing,
            result = "minor_deck_reordered",
        }
    end

    function controller:resolveEnterUnderworld(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.entry or actionData
        local history = self.guildRoster.labyrinthEntries or {}
        local seen = {}
        for _, entry in ipairs(history) do
            seen[entry.location] = true
        end

        local location = request.location or request.startingRoom or request.roomId
        if not location then
            local candidates = normalizeList(request.locations or request.randomLocations or request.underworldLocations)
            for _, candidate in ipairs(candidates) do
                local id = type(candidate) == "table" and (candidate.id or candidate.roomId or candidate.name) or candidate
                if id and not seen[id] then
                    location = id
                    break
                end
            end
        end
        location = location or "random_underworld_location"
        if seen[location] and request.allowRepeat ~= true then
            return false, "Labyrinth entry must be different each time"
        end

        local entry = {
            source = "labyrinth",
            location = location,
            randomLocation = true,
            neverSame = true,
            notes = request.notes,
        }
        history[#history + 1] = entry
        self.guildRoster.labyrinthEntries = history
        self.guildRoster.nextCrawlStart = entry
        appendActorRecord(actor, "labyrinthEntries", entry)

        return true, "underworld_entry_planned", {
            actor = actor,
            action = M.ACTIONS.ENTER_THE_UNDERWORLD,
            entry = entry,
            nextCrawlStart = entry,
            result = "underworld_entry_planned",
        }
    end

    function controller:resolveResearchNewSpell(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.research or actionData
        local spellName = request.spellName or request.name or request.title or
            (type(request.spell) == "table" and request.spell.name)
        if not spellName or tostring(spellName) == "" then
            return false, "Spell name required"
        end

        local tiles = normalizeTiles(request.tiles or request.drawnTiles or request.tile)
        if #tiles == 0 then
            return false, "Research tiles required"
        end

        local costPerTile = tonumber(request.costPerTile or request.costGold) or 25
        local cost = costPerTile * #tiles
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end
        if cost > 0 and not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        actor.spellResearch = actor.spellResearch or {}
        local spellId = slugify(request.spellId or spellName)
        local project = actor.spellResearch[spellId] or {
            id = spellId,
            spellName = tostring(spellName),
            tiles = {},
            spentGold = 0,
            source = "tower_gnostic",
            mechanics = request.mechanics or (type(request.spell) == "table" and request.spell.mechanics),
        }
        for _, tile in ipairs(tiles) do
            project.tiles[#project.tiles + 1] = tile
        end
        project.spentGold = (project.spentGold or 0) + cost
        local complete, remaining = tilesCompleteName(project.spellName, project.tiles)
        project.complete = complete
        project.remainingLetters = remaining
        actor.spellResearch[spellId] = project

        if complete then
            actor.knownSpells = actor.knownSpells or {}
            actor.knownSpells[spellId] = actor.knownSpells[spellId] or {
                id = spellId,
                name = project.spellName,
                custom = true,
                researched = true,
                mechanics = project.mechanics,
            }
        end

        return true, complete and "spell_research_complete" or "spell_research_progress", {
            actor = actor,
            action = M.ACTIONS.RESEARCH_A_NEW_SPELL,
            project = project,
            spellId = spellId,
            spellName = project.spellName,
            tiles = tiles,
            cost = cost,
            complete = complete,
            result = complete and "spell_research_complete" or "spell_research_progress",
        }
    end

    function controller:resolveTrialByCombat(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.trial or actionData
        if request.accused == false then
            return false, "Accusation required"
        end

        local survived = request.survived
        if survived == nil and request.success ~= nil then
            survived = request.success == true
        end
        local trial = {
            source = "court_martial",
            accusation = request.accusation or request.charge or "breaking the City's peace",
            perceivedGuilt = request.perceivedGuilt or request.guilt or "uncertain",
            strictures = normalizeList(request.strictures or request.tournamentStrictures),
            chivalricArgument = request.chivalricArgument == true or languageListHas(actor.languages or actor.knownLanguages, "chivalric"),
            survived = survived,
            challenge = request.challenge or request.challengeResult,
        }

        local result = "trial_by_combat_scheduled"
        if survived == true then
            trial.declaredInnocent = true
            result = "declared_innocent"
        elseif survived == false then
            actor.conditions = actor.conditions or {}
            actor.conditions.dead = true
            actor.dead = true
            trial.declaredGuilty = true
            trial.dead = true
            result = "found_guilty_dead"
        end
        appendActorRecord(actor, "trialsByCombat", trial)

        return true, result, {
            actor = actor,
            action = M.ACTIONS.TRIAL_BY_COMBAT,
            trial = trial,
            result = result,
        }
    end

    function controller:resolveSealAway(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.seal or actionData
        local target = request.target or request.abomination or request.monster
        local targetName = request.targetName or request.monsterName or request.name or (target and target.name)
        if not target and not targetName then
            return false, "Underworld abomination required"
        end

        local convinced = request.convinced
        local testResult = request.testResult or request.outcome
        if convinced == nil and testResult then
            convinced = testResult.success == true
        end
        if convinced == false then
            return false, "Templars not convinced"
        end

        if type(target) == "table" then
            target.sealedAway = true
            target.state = target.state or "sealed_away"
            target.conditions = target.conditions or {}
            target.conditions.sealed = true
        end

        local sealed = {
            source = "temple_militant",
            target = target,
            targetName = targetName or "Underworld abomination",
            convincedTemplars = convinced ~= false,
            evidence = request.evidence,
            mythrysWill = request.mythrysWill or request.argument,
        }
        appendActorRecord(actor, "sealedAbominations", sealed)

        return true, "abomination_sealed_away", {
            actor = actor,
            action = M.ACTIONS.SEAL_AWAY,
            sealed = sealed,
            target = target,
            result = "abomination_sealed_away",
        }
    end

    function controller:resolveJoinSwordwhores(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.membership or actionData
        local cost = tonumber(request.cost or request.costGold) or 100
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end
        if cost > 0 and not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        actor.memberships = actor.memberships or {}
        actor.memberships.swordwhores = {
            joined = true,
            duesPaid = cost,
            armorUpkeepTier = "impoverished",
            ironAndSteelArmorAccess = true,
        }

        return true, "swordwhores_joined", {
            actor = actor,
            action = M.ACTIONS.JOIN_SWORDWHORES,
            membership = actor.memberships.swordwhores,
            cost = cost,
            result = "swordwhores_joined",
        }
    end

    function controller:resolveFight(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.fight or actionData
        local bet = math.floor(tonumber(request.bet or request.gold or request.wager) or 0)
        if bet <= 0 then
            return false, "Bet required"
        end
        if currency.getGold(actor) < bet then
            return false, "Not enough gold"
        end

        local outcome = request.outcome or request.result
        local bust = tonumber(request.bust or request.bustBy)
        local playerTotal = tonumber(request.playerTotal)
        if not bust and playerTotal and playerTotal > 21 then
            bust = playerTotal - 21
        end
        if not outcome then
            if bust then
                outcome = "bust"
            elseif request.won ~= nil then
                outcome = request.won and "win" or "lose"
            end
        end
        outcome = tostring(outcome or ""):lower()
        if outcome ~= "win" and outcome ~= "won" and outcome ~= "lose" and outcome ~= "lost" and outcome ~= "bust" then
            return false, "Fight outcome required"
        end

        if not currency.spendGold(actor, bet) then
            return false, "Not enough gold"
        end

        local winnings = 0
        local wounds = 0
        local woundResults = {}
        local nextCrawlConditions = nil
        local result = "pit_fight_lost"

        if outcome == "win" or outcome == "won" then
            winnings = bet + math.floor(bet * 0.25)
            currency.addGold(actor, winnings)
            result = "pit_fight_won"
        elseif outcome == "bust" then
            bust = math.max(1, math.floor(bust or 1))
            wounds = math.max(1, bust - getSwords(actor))
            actor.conditions = actor.conditions or {}
            for _ = 1, wounds do
                local woundResult
                if actor.takeWound then
                    woundResult = actor:takeWound("normal")
                else
                    woundResult = "wound"
                end
                if woundResult == "deaths_door" then
                    actor.conditions.dead = true
                    actor.dead = true
                    woundResult = "dead"
                end
                woundResults[#woundResults + 1] = woundResult
                if woundResult == "dead" then
                    break
                end
            end
            result = "pit_fight_busted"
        else
            actor.nextCrawlConditions = actor.nextCrawlConditions or {}
            actor.nextCrawlConditions.stressed = true
            nextCrawlConditions = actor.nextCrawlConditions
        end

        local fight = {
            source = "court_of_swords",
            bet = bet,
            outcome = outcome,
            winnings = winnings,
            bust = bust,
            wounds = wounds,
            woundResults = woundResults,
            nextCrawlConditions = nextCrawlConditions,
        }
        appendActorRecord(actor, "pitFights", fight)

        return true, result, {
            actor = actor,
            action = M.ACTIONS.FIGHT,
            fight = fight,
            bet = bet,
            winnings = winnings,
            wounds = wounds,
            woundResults = woundResults,
            result = result,
        }
    end

    function controller:resolvePaleProphecies(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.prophecy or actionData
        local prophecy = {
            source = "mortuary_of_the_god_kings",
            spentNight = true,
            text = request.text or request.prophecyText or request.message or "The old kings whisper a sad prophecy.",
        }
        appendActorRecord(actor, "paleProphecies", prophecy)

        return true, "pale_prophecy_heard", {
            actor = actor,
            action = M.ACTIONS.PALE_PROPHECIES,
            prophecy = prophecy,
            result = "pale_prophecy_heard",
        }
    end

    function controller:resolveExploreHangmansHill(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.exploration or actionData
        local foundGold = math.max(0, math.floor(tonumber(request.gold or request.foundGold) or 0))
        if foundGold > 0 then
            currency.addGold(actor, foundGold)
        end
        local exploration = {
            source = "hangmans_hill",
            nighttime = true,
            finding = request.finding or request.treasure or request.description or "The dead had nothing of obvious worth.",
            goldFound = foundGold,
        }
        appendActorRecord(actor, "hangmansHillExplorations", exploration)

        return true, "hangmans_hill_explored", {
            actor = actor,
            action = M.ACTIONS.EXPLORE_HANGMANS_HILL,
            exploration = exploration,
            goldFound = foundGold,
            result = "hangmans_hill_explored",
        }
    end

    function controller:resolveDuel(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.duel or actionData
        local testResult = request.testResult or request.outcome
        local won = request.won
        if won == nil and testResult then
            won = testResult.success == true
        end
        if won == nil then
            return false, "Duel outcome required"
        end

        local sword = nil
        if won then
            sword = request.sword or request.prizeSword or request.opponentsSword or {
                name = request.swordName or "opponent's sword",
                prettySweet = request.prettySweet ~= false,
            }
            appendActorRecord(actor, "duelPrizes", sword)
        end

        local duel = {
            source = "iron_street",
            opponent = request.opponent or request.opponentName or "sword nerd",
            won = won == true,
            sword = sword,
            testResult = testResult,
        }
        appendActorRecord(actor, "cityDuels", duel)

        return true, won and "duel_won" or "duel_lost", {
            actor = actor,
            action = M.ACTIONS.DUEL,
            duel = duel,
            sword = sword,
            testResult = testResult,
            result = won and "duel_won" or "duel_lost",
        }
    end

    function controller:resolveGetAutographs(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or (type(actionData.autograph) == "table" and actionData.autograph) or actionData
        local autograph = {
            source = "temple_of_strength",
            athlete = request.athlete or request.signer or request.name or "celebrated athlete",
            inscription = request.inscription,
        }
        appendActorRecord(actor, "autographs", autograph)

        return true, "autograph_received", {
            actor = actor,
            action = M.ACTIONS.GET_AUTOGRAPHS,
            autograph = autograph,
            result = "autograph_received",
        }
    end

    function controller:resolveWrestleHereclus(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.wrestle or actionData
        local offSolidGround = request.offSolidGround == true or request.feetOnSolidGround == false
        local testResult = request.testResult or request.outcome
        local won = request.won
        if won == nil and testResult then
            won = testResult.success == true
        end
        if not offSolidGround then
            won = false
        elseif won == nil then
            return false, "Wrestling outcome required"
        end

        local prizeGold = tonumber(request.prizeGold) or 500
        if won then
            currency.addGold(actor, prizeGold)
        end
        local bout = {
            source = "temple_of_strength",
            opponent = "Hereclus the Strong",
            offSolidGround = offSolidGround,
            won = won == true,
            prizeGold = won and prizeGold or 0,
            testResult = testResult,
        }
        appendActorRecord(actor, "hereclusBouts", bout)

        return true, won and "hereclus_defeated" or "hereclus_unbeaten", {
            actor = actor,
            action = M.ACTIONS.WRESTLE_HERECLUS,
            bout = bout,
            prizeGold = bout.prizeGold,
            testResult = testResult,
            result = won and "hereclus_defeated" or "hereclus_unbeaten",
        }
    end

    function controller:resolveGetTattoos(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or (type(actionData.tattoo) == "table" and actionData.tattoo) or actionData
        local tattoo = {
            source = "grey_docks",
            description = request.description or request.design or "cool tattoo",
            location = request.location,
            style = request.style or request.artistStyle,
        }
        appendActorRecord(actor, "tattoos", tattoo)

        return true, "tattoo_received", {
            actor = actor,
            action = M.ACTIONS.GET_TATTOOS,
            tattoo = tattoo,
            result = "tattoo_received",
        }
    end

    function controller:resolveKeepAnEarToTheGround(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or (type(actionData.rumor) == "table" and actionData.rumor) or actionData
        local eventEntry = type(request.event) == "table" and request.event or nil
        local eventValue = request.eventValue or request.value or request.cardValue
        if not eventEntry and eventValue then
            eventEntry = city_events.getEvent(eventValue, request.cityEventsTable or self.cityEventsTable)
        end
        if not eventEntry and request.rumor then
            eventEntry = {
                category = city_events.CATEGORIES.RUMOR,
                title = request.title or "Rumor",
                summary = tostring(request.rumor),
            }
        end
        if not eventEntry then
            local tableRef = request.cityEventsTable or self.cityEventsTable or city_events.DEFAULT_EVENTS
            for value = 1, 21 do
                local candidate = tableRef[value]
                if candidate and candidate.category == city_events.CATEGORIES.RUMOR then
                    eventEntry = candidate
                    eventValue = value
                    break
                end
            end
        end
        if not eventEntry or eventEntry.category ~= city_events.CATEGORIES.RUMOR then
            return false, "City Event rumor required"
        end

        local record = {
            source = "bellringers_district",
            eventValue = eventValue or eventEntry.value,
            title = eventEntry.title,
            rumor = eventEntry.summary or eventEntry.title,
            event = eventEntry,
        }
        appendActorRecord(actor, "cityRumors", record)

        return true, "city_event_rumor_heard", {
            actor = actor,
            action = M.ACTIONS.KEEP_AN_EAR_TO_THE_GROUND,
            rumor = record,
            event = eventEntry,
            result = "city_event_rumor_heard",
        }
    end

    function controller:resolveSpreadRumors(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or (type(actionData.rumor) == "table" and actionData.rumor) or actionData
        local rumor = request.rumor or request.description or request.claim
        if not rumor or tostring(rumor) == "" then
            return false, "Rumor required"
        end

        local goldSpent = math.max(0, math.floor(tonumber(request.gold or request.cost or request.costGold) or 0))
        if currency.getGold(actor) < goldSpent then
            return false, "Not enough gold"
        end

        local testResult = request.testResult or request.outcome
        local card, shouldDiscard, drawnDeck
        if not testResult then
            card, shouldDiscard, drawnDeck = self:drawMinorCard(actionData)
            if not card then
                return false, "Requires minor arcana draw"
            end
            local bonus = math.min(math.floor(goldSpent / 20), 5)
            testResult = fate_resolver.resolveTest(bonus, nil, card, request.favor)
        end

        if goldSpent > 0 and not currency.spendGold(actor, goldSpent) then
            return false, "Not enough gold"
        end
        if shouldDiscard and drawnDeck and drawnDeck.discard then
            drawnDeck:discard(card)
        end

        local bonus = math.min(math.floor(goldSpent / 20), 5)
        local record = {
            source = "bellringers_district",
            rumor = tostring(rumor),
            goldSpent = goldSpent,
            bonus = bonus,
            credible = testResult.success == true,
            testResult = testResult,
        }
        appendActorRecord(actor, "spreadRumors", record)

        return true, "rumor_spread", {
            actor = actor,
            action = M.ACTIONS.SPREAD_RUMORS,
            rumor = record,
            goldSpent = goldSpent,
            bonus = bonus,
            credible = record.credible,
            card = card,
            testResult = testResult,
            result = "rumor_spread",
        }
    end

    function controller:resolveLoosenLips(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.loosenLips or actionData
        local character = request.character or request.npc or request.target
        local characterName = request.characterName or request.name or (character and character.name)
        local question = request.question
        if not characterName or tostring(characterName) == "" then
            return false, "GM character required"
        end
        if not question or tostring(question) == "" then
            return false, "Direct question required"
        end

        local goldSpent = math.max(0, math.floor(tonumber(request.gold or request.cost or request.costGold) or 0))
        if currency.getGold(actor) < goldSpent then
            return false, "Not enough gold"
        end

        local testResult = request.testResult or request.outcome
        local card, shouldDiscard, drawnDeck
        if not testResult then
            card, shouldDiscard, drawnDeck = self:drawMinorCard(actionData)
            if not card then
                return false, "Requires minor arcana draw"
            end
            local bonus = math.min(math.floor(goldSpent / 20), 5)
            testResult = fate_resolver.resolveTest(bonus, nil, card, request.favor)
        end

        if goldSpent > 0 and not currency.spendGold(actor, goldSpent) then
            return false, "Not enough gold"
        end
        if shouldDiscard and drawnDeck and drawnDeck.discard then
            drawnDeck:discard(card)
        end

        local bonus = math.min(math.floor(goldSpent / 20), 5)
        local record = {
            source = "vinegar_district",
            characterName = characterName,
            question = tostring(question),
            answer = testResult.success == true and request.answer or nil,
            goldSpent = goldSpent,
            bonus = bonus,
            honestAnswer = testResult.success == true,
            testResult = testResult,
        }
        appendActorRecord(actor, "loosenedLips", record)

        return true, record.honestAnswer and "lips_loosened" or "lips_not_loosened", {
            actor = actor,
            action = M.ACTIONS.LOOSEN_LIPS,
            inquiry = record,
            goldSpent = goldSpent,
            bonus = bonus,
            honestAnswer = record.honestAnswer,
            card = card,
            testResult = testResult,
            result = record.honestAnswer and "lips_loosened" or "lips_not_loosened",
        }
    end

    function controller:resolveSeekTheCursedKing(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.search or actionData
        local testResult = request.testResult or request.outcome
        local card, shouldDiscard, drawnDeck
        if not testResult then
            card, shouldDiscard, drawnDeck = self:drawMinorCard(actionData)
            if not card then
                return false, "Requires minor arcana draw"
            end
            testResult = fate_resolver.resolveTest(getWands(actor), constants.SUITS.WANDS, card, request.favor)
        end
        if shouldDiscard and drawnDeck and drawnDeck.discard then
            drawnDeck:discard(card)
        end

        local record = {
            source = "bridge_of_mourning",
            success = testResult.success == true,
            terribleChoice = testResult.success == true and (request.terribleChoice or request.choice or true) or nil,
            testResult = testResult,
        }
        appendActorRecord(actor, record.success and "cursedKingEncounters" or "cursedKingSearches", record)

        return true, record.success and "cursed_king_found" or "cursed_king_legend", {
            actor = actor,
            action = M.ACTIONS.SEEK_THE_CURSED_KING,
            search = record,
            card = card,
            testResult = testResult,
            result = record.success and "cursed_king_found" or "cursed_king_legend",
        }
    end

    function controller:resolveRestAndRecuperate(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.rest or actionData
        if actorIsDestitute(self, actor, request) then
            return false, "Non-destitute upkeep required"
        end

        local healing = healAllWounds(actor)
        appendActorRecord(actor, "hospitalCare", {
            type = "rest_and_recuperate",
            healing = healing,
            cost = 0,
        })

        return true, "rested_and_recuperated", {
            actor = actor,
            action = M.ACTIONS.REST_AND_RECUPERATE,
            healing = healing,
            cost = 0,
            result = "rested_and_recuperated",
        }
    end

    function controller:resolveUndergoLeeching(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.leeching or actionData
        local afflictionName = request.affliction or request.afflictionName or request.targetAffliction
        local affliction, resolvedName = findActorAffliction(actor, afflictionName)
        if not affliction then
            return false, "No affliction to heal"
        end

        local stages = math.max(1, math.floor(tonumber(request.stages or request.stageCount or affliction.stage) or 1))
        local costPerStage = tonumber(request.costPerStage or request.costGoldPerStage) or 20
        local cost = math.max(0, stages * costPerStage)
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end
        if cost > 0 and not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        actor.afflictions[resolvedName] = nil
        appendActorRecord(actor, "hospitalCare", {
            type = "undergo_leeching",
            affliction = resolvedName,
            stages = stages,
            cost = cost,
        })

        return true, "affliction_leeched", {
            actor = actor,
            action = M.ACTIONS.UNDERGO_LEECHING,
            affliction = resolvedName,
            stages = stages,
            cost = cost,
            costPerStage = costPerStage,
            result = "affliction_leeched",
        }
    end

    function controller:resolveDoomsaying(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.doomsaying or actionData
        local cost = tonumber(request.cost or request.costGold) or 10
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end

        local cards = request.cards or request.prophecyCards or {}
        local drawn = {}
        local drawnDeck = request.deck or request.playerDeck or request.minorDeck or self.playerDeck
        local shouldDiscard = false
        if #cards == 0 and drawnDeck and drawnDeck.draw then
            for _ = 1, 4 do
                local card = drawnDeck:draw()
                if card then
                    cards[#cards + 1] = card
                    drawn[#drawn + 1] = card
                end
            end
            shouldDiscard = true
        end
        if #cards < 4 then
            return false, "Requires four minor arcana cards"
        end

        if cost > 0 and not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end
        if shouldDiscard and drawnDeck and drawnDeck.discard then
            for _, card in ipairs(drawn) do
                drawnDeck:discard(card)
            end
        end

        local fragments = {}
        for index = 1, 4 do
            local card = cards[index]
            local suitFragments = M.DOOMSAYING_PROPHECY[index] or {}
            fragments[index] = suitFragments[card and card.suit] or {
                id = "unclear_omen",
                text = "An unclear omen",
            }
        end

        local prophecy = {
            cards = { cards[1], cards[2], cards[3], cards[4] },
            fragments = fragments,
            cost = cost,
            fulfilled = false,
            reward = "refill_resolve",
        }
        appendActorRecord(actor, "prophecies", prophecy)

        return true, "prophecy_received", {
            actor = actor,
            action = M.ACTIONS.DOOMSAYING,
            prophecy = prophecy,
            cards = prophecy.cards,
            fragments = fragments,
            cost = cost,
            result = "prophecy_received",
        }
    end

    function controller:resolveSeekTruth(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.truth or actionData
        local hypothesis = request.hypothesis or request.question or request.theory
        if not hypothesis or tostring(hypothesis) == "" then
            return false, "Hypothesis required"
        end

        local response = tostring(request.response or request.outcome or request.verdict or ""):lower()
        local veracity = nil
        if request.correct == true or request.truth == true then
            veracity = "mostly_correct"
            response = response ~= "" and response or "cheer"
        elseif request.correct == false or request.truth == false then
            veracity = "incorrect"
            response = response ~= "" and response or "boo"
        elseif response == "cheer" or response == "cheers" or response == "mostly_correct" or response == "correct" then
            veracity = "mostly_correct"
        elseif response == "boo" or response == "boos" or response == "incorrect" or response == "wrong" then
            veracity = "incorrect"
        elseif response == "debate" or response == "debates" or response == "kernel" or response == "partial" then
            veracity = "kernel_of_truth"
        else
            return false, "Truth outcome required"
        end

        local cost = tonumber(request.cost or request.costGold) or 50
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end
        if cost > 0 and not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        local record = {
            hypothesis = tostring(hypothesis),
            response = response,
            veracity = veracity,
            cost = cost,
        }
        appendActorRecord(actor, "truthsSought", record)

        return true, "truth_sought", {
            actor = actor,
            action = M.ACTIONS.SEEK_TRUTH,
            hypothesis = record.hypothesis,
            response = response,
            veracity = veracity,
            cost = cost,
            result = "truth_sought",
        }
    end

    function controller:resolveSeekInitiation(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.initiation or actionData
        actor.memberships = actor.memberships or {}

        local membership = getMythrysMembership(actor)
        if not membership then
            local koan = request.koan or request.riddle or request.nextKoan or request.nextRiddle or
                "The first mystery is veiled."
            membership = {
                joined = true,
                cult = "cult_of_mythrys",
                rank = 1,
                initiationRank = 1,
                maxRank = M.MAX_MYTHRYS_INITIATION,
                currentKoan = tostring(koan),
                currentRiddle = tostring(koan),
                expectedAnswer = request.answerKey or request.expectedAnswer or request.koanAnswer,
                favorOverLowerRanks = true,
                cityInfluenceFavor = "lower_mythrys_initiates",
                history = {},
            }
            actor.memberships.cult_of_mythrys = membership

            local entry = {
                result = "cult_initiated",
                rank = 1,
                koan = membership.currentKoan,
            }
            membership.history[#membership.history + 1] = entry
            appendActorRecord(actor, "mythrysInitiations", entry)

            return true, "cult_initiated", {
                actor = actor,
                action = M.ACTIONS.SEEK_INITIATION,
                membership = membership,
                rank = 1,
                koan = membership.currentKoan,
                favorOverLowerRanks = true,
                result = "cult_initiated",
            }
        end

        membership.history = membership.history or {}
        local rank = M.getMythrysInitiationRank(actor)
        if rank >= M.MAX_MYTHRYS_INITIATION then
            return false, "Highest initiation already reached"
        end

        local answer = request.answer or request.guess or request.riddleAnswer
        local correct
        if request.correct ~= nil then
            correct = request.correct == true
        else
            local normalizedAnswer = normalizeInitiationAnswer(answer)
            local expected = normalizeInitiationAnswer(membership.expectedAnswer or membership.answerKey or
                membership.currentAnswer)
            if not normalizedAnswer then
                return false, "Initiation answer required"
            end
            if not expected then
                return false, "Initiation answer adjudication required"
            end
            correct = normalizedAnswer == expected
        end

        local attempt = {
            rank = rank,
            koan = membership.currentKoan or membership.currentRiddle,
            answer = answer,
            correct = correct,
        }
        membership.history[#membership.history + 1] = attempt
        appendActorRecord(actor, "mythrysInitiations", attempt)

        if not correct then
            return true, "initiation_answer_incorrect", {
                actor = actor,
                action = M.ACTIONS.SEEK_INITIATION,
                membership = membership,
                rank = rank,
                attempt = attempt,
                result = "initiation_answer_incorrect",
            }
        end

        local newRank = rank + 1
        membership.rank = newRank
        membership.initiationRank = newRank
        membership.maxRank = membership.maxRank or M.MAX_MYTHRYS_INITIATION
        membership.favorOverLowerRanks = true
        membership.cityInfluenceFavor = membership.cityInfluenceFavor or "lower_mythrys_initiates"
        local nextKoan = request.nextKoan or request.nextRiddle or
            string.format("The mystery of initiation %d is veiled.", newRank)
        membership.currentKoan = tostring(nextKoan)
        membership.currentRiddle = tostring(nextKoan)
        membership.expectedAnswer = request.nextAnswerKey or request.nextExpectedAnswer or request.nextKoanAnswer
        attempt.advancedTo = newRank
        attempt.nextKoan = membership.currentKoan

        return true, "initiation_advanced", {
            actor = actor,
            action = M.ACTIONS.SEEK_INITIATION,
            membership = membership,
            rank = newRank,
            previousRank = rank,
            attempt = attempt,
            koan = membership.currentKoan,
            favorOverLowerRanks = true,
            result = "initiation_advanced",
        }
    end

    function controller:resolveJoinBeggarsGuild(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.membership or actionData
        local cost = tonumber(request.cost or request.costGold) or 100
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end
        if cost > 0 and not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        actor.memberships = actor.memberships or {}
        actor.memberships.beggars_guild = {
            joined = true,
            duesPaid = cost,
            secretUnderworldEntrance = true,
            coinTaxWaived = true,
            portalItemDonationRequired = true,
        }

        return true, "beggars_guild_joined", {
            actor = actor,
            action = M.ACTIONS.JOIN_BEGGARS_GUILD,
            membership = actor.memberships.beggars_guild,
            cost = cost,
            result = "beggars_guild_joined",
        }
    end

    function controller:resolvePurchaseAnimalCompanion(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.purchase or actionData
        local hasExplicitCompanionSpec = type(request.companion) == "table" or type(request.animal) == "table"
        local companionSpec = type(request.companion) == "table" and request.companion or
            (type(request.animal) == "table" and request.animal or request)
        local function firstCommand(value)
            if type(value) == "string" and value ~= "" then
                return value
            elseif type(value) == "table" then
                if value[1] then
                    local entry = value[1]
                    if type(entry) == "table" then
                        return entry.name or entry.id
                    end
                    return entry
                end
                for key, entry in pairs(value) do
                    if type(entry) == "string" then
                        return entry
                    elseif type(entry) == "table" then
                        return entry.name or entry.id
                    elseif entry then
                        return key
                    end
                end
            end
            return nil
        end

        local cost = math.floor(tonumber(request.cost or request.costGold or request.price or request.rarityCost) or 0)
        if cost < 100 or cost > 1000 then
            return false, "Animal rarity cost must be 100-1000g"
        end
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end

        local command = firstCommand(request.commandName or request.command or request.startingCommand or
            request.knownCommand or request.knownCommands or companionSpec.knownCommands or companionSpec.commands)
        if not command or tostring(command) == "" then
            return false, "Choose starting command"
        end

        if cost > 0 and not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        actor.animalCompanions = actor.animalCompanions or {}
        local species = companionSpec.species or companionSpec.animalType or companionSpec.kind or "exotic animal"
        local name = companionSpec.name or request.companionName or ("Hippodrome " .. tostring(species))
        local index = #actor.animalCompanions + 1
        local companion = hasExplicitCompanionSpec and shallowClone(companionSpec) or {}
        companion.id = companion.id or request.companionId or string.format("%s_companion_%02d_%s",
            slugify(actorId(actor)), index, slugify(name))
        companion.name = name
        companion.species = species
        companion.animalType = companion.animalType or species
        companion.type = companion.type or "animal_companion"
        companion.conditions = companion.conditions or {}
        companion.knownCommands = { tostring(command) }
        companion.commands = companion.knownCommands
        companion.purchaseCost = cost
        companion.rarityCost = cost
        companion.source = companion.source or "hippodrome_of_amet"
        companion.animalCompanion = true
        actor.animalCompanions[#actor.animalCompanions + 1] = companion

        local purchase = {
            companion = companion,
            cost = cost,
            startingCommand = companion.knownCommands[1],
            source = companion.source,
        }
        appendActorRecord(actor, "animalCompanionPurchases", purchase)

        return true, "animal_companion_purchased", {
            actor = actor,
            action = M.ACTIONS.PURCHASE_ANIMAL_COMPANION,
            companion = companion,
            purchase = purchase,
            cost = cost,
            startingCommand = companion.knownCommands[1],
            result = "animal_companion_purchased",
        }
    end

    function controller:resolveAssembleGoblinHorde(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.horde or actionData
        if not hasUsableTalent(actor, "jarl") then
            return false, "Requires Jarl talent"
        end

        local xpSpend = math.floor(tonumber(request.xp or request.xpSpent or request.amount) or 0)
        if xpSpend < 0 then
            return false, "XP spend cannot be negative"
        end
        if (actor.xp or 0) < xpSpend then
            return false, "Not enough XP"
        end

        actor.animalCompanions = actor.animalCompanions or {}

        local function installGoblinHordeBehavior(horde)
            horde.conditions = horde.conditions or {}
            horde.type = horde.type or "animal_companion"
            horde.animalCompanion = true
            horde.goblinHorde = true
            horde.countsAsOneCreature = true
            horde.suppliesOwnFood = true
            horde.commandsAny = true
            horde.oneWordCommandsOnly = true
            horde.maxGoblins = 8
            horde.goblinCount = math.max(0, math.floor(tonumber(horde.goblinCount or horde.count) or 0))
            horde.count = horde.goblinCount
            horde.porterSlots = horde.goblinCount
            horde.takeWound = horde.takeWound or function(self)
                self.goblinCount = math.max(0, math.floor(tonumber(self.goblinCount or self.count) or 0) - 1)
                self.count = self.goblinCount
                self.porterSlots = self.goblinCount
                self.goblinCasualties = (self.goblinCasualties or 0) + 1
                self.conditions = self.conditions or {}
                if self.goblinCount <= 0 then
                    self.conditions.dead = true
                    self.dead = true
                    return "goblin_horde_destroyed"
                end
                return "goblin_killed"
            end
        end

        local existingHorde = nil
        for _, companion in ipairs(actor.animalCompanions) do
            if type(companion) == "table" and companion.goblinHorde == true then
                existingHorde = companion
                installGoblinHordeBehavior(existingHorde)
                break
            end
        end

        local existingCount = existingHorde and existingHorde.goblinCount or 0
        local available = 8 - existingCount
        if available <= 0 then
            return false, "Goblin horde at capacity"
        end

        local requestedGoblins = 2 + xpSpend
        local recruited = math.min(requestedGoblins, available)
        actor.xp = (actor.xp or 0) - xpSpend

        local horde = existingHorde
        if not horde then
            local index = #actor.animalCompanions + 1
            horde = {
                id = request.hordeId or request.companionId or string.format("%s_goblin_horde_%02d",
                    slugify(actorId(actor)), index),
                name = request.name or request.hordeName or "Goblin Horde",
                species = "goblin",
                animalType = "goblin_horde",
                knownCommands = {},
                commands = {},
                source = "jarl",
            }
            installGoblinHordeBehavior(horde)
            actor.animalCompanions[#actor.animalCompanions + 1] = horde
        end

        horde.goblinCount = math.min(8, existingCount + recruited)
        horde.count = horde.goblinCount
        horde.porterSlots = horde.goblinCount
        horde.conditions.dead = horde.goblinCount <= 0
        horde.dead = horde.conditions.dead == true
        horde.lastRecruitment = {
            xpSpent = xpSpend,
            requestedGoblins = requestedGoblins,
            recruited = recruited,
        }

        actor.goblinHorde = horde
        local assembly = {
            horde = horde,
            xpSpent = xpSpend,
            requestedGoblins = requestedGoblins,
            recruited = recruited,
            goblinCount = horde.goblinCount,
            porterSlots = horde.porterSlots,
            capped = recruited < requestedGoblins,
        }
        appendActorRecord(actor, "goblinHordeAssemblies", assembly)

        return true, "goblin_horde_assembled", {
            actor = actor,
            action = M.ACTIONS.ASSEMBLE_GOBLIN_HORDE,
            horde = horde,
            assembly = assembly,
            xpSpent = xpSpend,
            requestedGoblins = requestedGoblins,
            recruited = recruited,
            goblinCount = horde.goblinCount,
            porterSlots = horde.porterSlots,
            capped = assembly.capped,
            result = "goblin_horde_assembled",
        }
    end

    function controller:resolveMarriageFeast(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.marriage or actionData
        local partner = request.partner or request.spouse
        local attendees = request.attendees or request.guests or {}
        local actorCost = math.max(0, math.floor(tonumber(request.goldFromLastCrawl or request.actorGold or currency.getGold(actor)) or 0))
        local partnerCost = 0
        if partner then
            partnerCost = math.max(0, math.floor(tonumber(request.partnerGoldFromLastCrawl or request.partnerGold or currency.getGold(partner)) or 0))
        end
        if currency.getGold(actor) < actorCost or (partner and currency.getGold(partner) < partnerCost) then
            return false, "Not enough gold"
        end

        if actorCost > 0 and not currency.spendGold(actor, actorCost) then
            return false, "Not enough gold"
        end
        if partner and partnerCost > 0 and not currency.spendGold(partner, partnerCost) then
            return false, "Not enough gold"
        end

        addXP(actor, 2)
        if partner then
            addXP(partner, 2)
        end

        local additional = {}
        local seen = {}
        seen[actorId(actor)] = true
        if partner and not seen[actorId(partner)] then
            seen[actorId(partner)] = true
            additional[#additional + 1] = {
                actor = partner,
                action = M.ACTIONS.MARRIAGE_FEAST,
                result = "marriage_partner",
            }
        end
        for _, attendee in ipairs(attendees) do
            local id = actorId(attendee)
            if id and not seen[id] then
                seen[id] = true
                addXP(attendee, 1)
                additional[#additional + 1] = {
                    actor = attendee,
                    action = M.ACTIONS.MARRIAGE_FEAST,
                    result = "marriage_guest",
                }
            end
        end

        local feast = {
            actor = actor,
            partner = partner,
            attendees = attendees,
            actorCost = actorCost,
            partnerCost = partnerCost,
            xpGained = 2,
            attendeeXP = 1,
        }
        appendActorRecord(actor, "marriageFeasts", feast)

        return true, "marriage_feast_held", {
            actor = actor,
            action = M.ACTIONS.MARRIAGE_FEAST,
            feast = feast,
            partner = partner,
            attendees = attendees,
            actorCost = actorCost,
            partnerCost = partnerCost,
            xpGained = 2,
            attendeeXP = 1,
            additionalCityActors = additional,
            result = "marriage_feast_held",
        }
    end

    function controller:resolveCopyTexts(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.copy or actionData
        local topic = request.topic or request.subject or request.title
        if not topic or tostring(topic) == "" then
            return false, "Text topic required"
        end
        if request.exists == false or request.available == false then
            return false, "Text unavailable"
        end

        local cost = math.floor(tonumber(request.cost or request.costGold or request.price) or 0)
        if cost < 100 or cost > 1400 then
            return false, "Copy cost must be 100-1400g"
        end
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end
        if cost > 0 and not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        local copy = {
            topic = tostring(topic),
            title = request.title or tostring(topic),
            cost = cost,
        }
        appendActorRecord(actor, "copiedTexts", copy)

        return true, "text_copied", {
            actor = actor,
            action = M.ACTIONS.COPY_TEXTS,
            copy = copy,
            topic = copy.topic,
            cost = cost,
            result = "text_copied",
        }
    end

    function controller:resolveTakeOutLoan(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.loan or actionData
        local amount = math.floor(tonumber(request.amount or request.gold or request.principal) or 0)
        if amount <= 0 then
            return false, "Loan amount required"
        end

        local interestRate = tonumber(request.interestRate or request.interestPercent) or 30
        local owed = math.floor(amount * (1 + interestRate / 100) + 0.5)
        currency.addGold(actor, amount)
        local loan = {
            principal = amount,
            interestRate = interestRate,
            owed = owed,
            lender = "centrum_bank",
        }
        appendActorRecord(actor, "loans", loan)

        return true, "loan_taken", {
            actor = actor,
            action = M.ACTIONS.TAKE_OUT_LOAN,
            loan = loan,
            amount = amount,
            owed = owed,
            interestRate = interestRate,
            result = "loan_taken",
        }
    end

    function controller:resolveSendLetter(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.letter or actionData
        local recipient = request.recipient or request.to
        if not recipient or tostring(recipient) == "" then
            return false, "Letter recipient required"
        end

        local cost = tonumber(request.cost or request.costGold) or 10
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end
        if cost > 0 and not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        local roll = math.floor(tonumber(request.deliveryRoll or request.roll) or math.random(1, 14))
        local arrived = roll ~= 1
        local letter = {
            recipient = recipient,
            destination = request.destination or request.location or "Wide World",
            message = request.message,
            cost = cost,
            deliveryRoll = roll,
            arrived = arrived,
        }
        actor.sentLetters = actor.sentLetters or {}
        actor.sentLetters[#actor.sentLetters + 1] = letter

        return true, "letter_sent", {
            actor = actor,
            action = M.ACTIONS.SEND_LETTER,
            letter = letter,
            cost = cost,
            deliveryRoll = roll,
            arrived = arrived,
            result = "letter_sent",
        }
    end

    function controller:resolveStudyLanguage(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.study or actionData
        local language = normalizeLanguage(request.language or request.lang)
        if not language then
            return false, "Choose a language"
        end
        if languageListHas(actor.languages or actor.knownLanguages, language) then
            return false, "Language already known"
        end

        local cost = tonumber(request.cost or request.costGold) or 200
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end
        if cost > 0 and not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        actor.languages = actor.languages or {}
        actor.languages[#actor.languages + 1] = language

        return true, "language_studied", {
            actor = actor,
            action = M.ACTIONS.STUDY_LANGUAGE,
            language = language,
            cost = cost,
            result = "language_studied",
        }
    end

    function controller:resolveAction(actor, actionData)
        actionData = actionData or {}
        actor = actor or actionData.actor

        local canAct, reason = self:canAct(actor)
        if not canAct then
            return false, reason
        end

        local actionId = normalizeActionId(actionData.type or actionData.action or actionData.id)
        local allowedByEvent, restrictionReason = self:checkCityActionRestrictions(actionId)
        if not allowedByEvent then
            return false, restrictionReason
        end

        local ok, result, detail
        if actionId == M.ACTIONS.ADOPT then
            ok, result, detail = self:resolveAdopt(actor, actionData)
        elseif actionId == M.ACTIONS.AS_ABOVE_SO_BELOW then
            ok, result, detail = self:resolveAsAboveSoBelow(actor, actionData)
        elseif actionId == M.ACTIONS.ATTEND_MISS_KINSEYS_DINING_CLUB then
            ok, result, detail = self:resolveAttendMissKinseysDiningClub(actor, actionData)
        elseif actionId == M.ACTIONS.BANKING then
            ok, result, detail = self:resolveBanking(actor, actionData)
        elseif actionId == M.ACTIONS.BEG_FOR_SCRAPS then
            ok, result, detail = self:resolveBegForScraps(actor, actionData)
        elseif actionId == M.ACTIONS.BEG_AND_BUSK then
            ok, result, detail = self:resolveBegAndBusk(actor, actionData)
        elseif actionId == M.ACTIONS.BLOOD_FEAST then
            ok, result, detail = self:resolveBloodFeast(actor, actionData)
        elseif actionId == M.ACTIONS.BUILD then
            ok, result, detail = self:resolveBuild(actor, actionData)
        elseif actionId == M.ACTIONS.BUY_EXOTIC_DRUGS then
            ok, result, detail = self:resolveBuyExoticDrugs(actor, actionData)
        elseif actionId == M.ACTIONS.CAMP_ACTION then
            ok, result, detail = self:resolveCampAction(actor, actionData)
        elseif actionId == M.ACTIONS.CAROUSE then
            ok, result, detail = self:resolveCarouse(actor, actionData)
        elseif actionId == M.ACTIONS.CHOOSE_MONSTER_HUNTER_FOE then
            ok, result, detail = self:resolveChooseMonsterHunterFoe(actor, actionData)
        elseif actionId == M.ACTIONS.COMMISSION_GARGOYLE then
            ok, result, detail = self:resolveCommissionGargoyle(actor, actionData)
        elseif actionId == M.ACTIONS.COMMISSION_PUPPET then
            ok, result, detail = self:resolveCommissionPuppet(actor, actionData)
        elseif actionId == M.ACTIONS.COMMISSION_DWARVEN_MASTERCRAFT then
            ok, result, detail = self:resolveCommissionDwarvenMastercraft(actor, actionData)
        elseif actionId == M.ACTIONS.COMMISSION_CRAFT then
            ok, result, detail = self:resolveCommissionCraft(actor, actionData)
        elseif actionId == M.ACTIONS.CONTRACT_ASSASSINATION then
            ok, result, detail = self:resolveContractAssassination(actor, actionData)
        elseif actionId == M.ACTIONS.COPY_TEXTS then
            ok, result, detail = self:resolveCopyTexts(actor, actionData)
        elseif actionId == M.ACTIONS.DISPOSE_OF_BODIES then
            ok, result, detail = self:resolveDisposeOfBodies(actor, actionData)
        elseif actionId == M.ACTIONS.DOODLEBUG then
            ok, result, detail = self:resolveDoodlebug(actor, actionData)
        elseif actionId == M.ACTIONS.DOOMSAYING then
            ok, result, detail = self:resolveDoomsaying(actor, actionData)
        elseif actionId == M.ACTIONS.DUEL then
            ok, result, detail = self:resolveDuel(actor, actionData)
        elseif actionId == M.ACTIONS.EXPLORE_HANGMANS_HILL then
            ok, result, detail = self:resolveExploreHangmansHill(actor, actionData)
        elseif actionId == M.ACTIONS.EXCHANGE_GIFTS then
            ok, result, detail = self:resolveExchangeGifts(actor, actionData)
        elseif actionId == M.ACTIONS.FENCE_GOODS then
            ok, result, detail = self:resolveFenceGoods(actor, actionData)
        elseif actionId == M.ACTIONS.FIT_PROSTHETICS then
            ok, result, detail = self:resolveFitProsthetics(actor, actionData)
        elseif actionId == M.ACTIONS.FIGHT then
            ok, result, detail = self:resolveFight(actor, actionData)
        elseif actionId == M.ACTIONS.GET_AUTOGRAPHS then
            ok, result, detail = self:resolveGetAutographs(actor, actionData)
        elseif actionId == M.ACTIONS.GET_TATTOOS then
            ok, result, detail = self:resolveGetTattoos(actor, actionData)
        elseif actionId == M.ACTIONS.HUFF_FUMES then
            ok, result, detail = self:resolveHuffFumes(actor, actionData)
        elseif actionId == M.ACTIONS.ENTER_THE_UNDERWORLD then
            ok, result, detail = self:resolveEnterUnderworld(actor, actionData)
        elseif actionId == M.ACTIONS.JOIN_BEGGARS_GUILD then
            ok, result, detail = self:resolveJoinBeggarsGuild(actor, actionData)
        elseif actionId == M.ACTIONS.JOIN_COURT_OF_WANDS then
            ok, result, detail = self:resolveJoinCourtOfWands(actor, actionData)
        elseif actionId == M.ACTIONS.JOIN_SWORDWHORES then
            ok, result, detail = self:resolveJoinSwordwhores(actor, actionData)
        elseif actionId == M.ACTIONS.ASSEMBLE_GOBLIN_HORDE then
            ok, result, detail = self:resolveAssembleGoblinHorde(actor, actionData)
        elseif actionId == M.ACTIONS.KEEP_AN_EAR_TO_THE_GROUND then
            ok, result, detail = self:resolveKeepAnEarToTheGround(actor, actionData)
        elseif actionId == M.ACTIONS.LAY_HIGH then
            ok, result, detail = self:resolveLayHigh(actor, actionData)
        elseif actionId == M.ACTIONS.HOLD_FUNERAL then
            ok, result, detail = self:resolveHoldFuneral(actor, actionData)
        elseif actionId == M.ACTIONS.LOOSEN_LIPS then
            ok, result, detail = self:resolveLoosenLips(actor, actionData)
        elseif actionId == M.ACTIONS.MAKEOVER then
            ok, result, detail = self:resolveMakeover(actor, actionData)
        elseif actionId == M.ACTIONS.MARRIAGE_FEAST then
            ok, result, detail = self:resolveMarriageFeast(actor, actionData)
        elseif actionId == M.ACTIONS.MUTATION then
            ok, result, detail = self:resolveMutation(actor, actionData)
        elseif actionId == M.ACTIONS.PALE_PROPHECIES then
            ok, result, detail = self:resolvePaleProphecies(actor, actionData)
        elseif actionId == M.ACTIONS.PILLOW_TALK then
            ok, result, detail = self:resolvePillowTalk(actor, actionData)
        elseif actionId == M.ACTIONS.PICNIC then
            ok, result, detail = self:resolvePicnic(actor, actionData)
        elseif actionId == M.ACTIONS.PREPARE_COMPONENTS then
            ok, result, detail = self:resolvePrepareComponents(actor, actionData)
        elseif actionId == M.ACTIONS.PRAY_AT_MYTHRAEUM then
            ok, result, detail = self:resolvePrayAtMythraeum(actor, actionData)
        elseif actionId == M.ACTIONS.TRAIN then
            ok, result, detail = self:resolveTrain(actor, actionData)
        elseif actionId == M.ACTIONS.SUPPORT then
            ok, result, detail = self:resolveSupport(actor, actionData)
        elseif actionId == M.ACTIONS.RESEARCH then
            ok, result, detail = self:resolveResearch(actor, actionData)
        elseif actionId == M.ACTIONS.MENAGERIE_REAGENT_PURCHASE then
            ok, result, detail = alchemy.resolveMenagerieReagentPurchase(actor, actionData, {
                eventBus = self.eventBus,
            })
        elseif actionId == M.ACTIONS.PURCHASE_AMULETS then
            ok, result, detail = self:resolvePurchaseAmulets(actor, actionData)
        elseif actionId == M.ACTIONS.PURCHASE_ANIMAL_COMPANION then
            ok, result, detail = self:resolvePurchaseAnimalCompanion(actor, actionData)
        elseif actionId == M.ACTIONS.PURCHASE_FATE_HONEY then
            ok, result, detail = self:resolvePurchaseFateHoney(actor, actionData)
        elseif actionId == M.ACTIONS.PURCHASE_FIREWORKS then
            ok, result, detail = self:resolvePurchaseFireworks(actor, actionData)
        elseif actionId == M.ACTIONS.RESEARCH_A_NEW_SPELL then
            ok, result, detail = self:resolveResearchNewSpell(actor, actionData)
        elseif actionId == M.ACTIONS.REST_AND_RECUPERATE then
            ok, result, detail = self:resolveRestAndRecuperate(actor, actionData)
        elseif actionId == M.ACTIONS.SEAL_AWAY then
            ok, result, detail = self:resolveSealAway(actor, actionData)
        elseif actionId == M.ACTIONS.SEEK_INITIATION then
            ok, result, detail = self:resolveSeekInitiation(actor, actionData)
        elseif actionId == M.ACTIONS.SEEK_TRUTH then
            ok, result, detail = self:resolveSeekTruth(actor, actionData)
        elseif actionId == M.ACTIONS.SEND_LETTER then
            ok, result, detail = self:resolveSendLetter(actor, actionData)
        elseif actionId == M.ACTIONS.SEEK_THE_CURSED_KING then
            ok, result, detail = self:resolveSeekTheCursedKing(actor, actionData)
        elseif actionId == M.ACTIONS.SELL_REAGENT then
            ok, result, detail = alchemy.resolveReagentSale(actor, actionData, {
                eventBus = self.eventBus,
                price = actionData.price,
                value = actionData.value,
                gold = actionData.gold,
            })
        elseif actionId == M.ACTIONS.SPREAD_RUMORS then
            ok, result, detail = self:resolveSpreadRumors(actor, actionData)
        elseif actionId == M.ACTIONS.STRANGE_COMMUNIONS then
            ok, result, detail = self:resolveStrangeCommunions(actor, actionData)
        elseif actionId == M.ACTIONS.STUDY_LANGUAGE then
            ok, result, detail = self:resolveStudyLanguage(actor, actionData)
        elseif actionId == M.ACTIONS.TAKE_OUT_LOAN then
            ok, result, detail = self:resolveTakeOutLoan(actor, actionData)
        elseif actionId == M.ACTIONS.THE_PLAYS_THE_THING then
            ok, result, detail = self:resolveThePlaysTheThing(actor, actionData)
        elseif actionId == M.ACTIONS.TRIAL_BY_COMBAT then
            ok, result, detail = self:resolveTrialByCombat(actor, actionData)
        elseif actionId == M.ACTIONS.UNDERGO_LEECHING then
            ok, result, detail = self:resolveUndergoLeeching(actor, actionData)
        elseif actionId == M.ACTIONS.VISIT_GRAVE then
            ok, result, detail = self:resolveVisitGrave(actor, actionData)
        elseif actionId == M.ACTIONS.VISIT_THE_PIT then
            ok, result, detail = self:resolveVisitThePit(actor, actionData)
        elseif actionId == M.ACTIONS.WRESTLE_HERECLUS then
            ok, result, detail = self:resolveWrestleHereclus(actor, actionData)
        else
            return false, "Unknown City Action"
        end

        if not ok then
            return false, result
        end

        self:markActed(actor, actionId, result)
        if detail and detail.additionalCityActors then
            for _, extra in ipairs(detail.additionalCityActors) do
                local extraActor = extra.actor or extra
                if actorId(extraActor) ~= actorId(actor) then
                    self:markActed(extraActor, extra.action or actionId, extra.result or result)
                end
            end
        end
        self.eventBus:emit(events.EVENTS.CITY_ACTION_RESOLVED, {
            actor = actor,
            action = actionId,
            result = result,
            detail = detail,
            canAdvance = self:canAdvance(),
        })

        return true, result, detail
    end

    function controller:resolveDistrictAction(actor, districtActionId, actionData)
        actionData = actionData or {}
        local requestedActionId = districtActionId or actionData.districtAction or actionData.districtActionId or
            actionData.specialCityAction or actionData.action or actionData.type or actionData.id
        if not requestedActionId then
            return false, "Choose a district City Action"
        end

        local districtEntry = self:getDistrictAction(requestedActionId)
        if not districtEntry then
            return false, "District City Action unavailable"
        end

        local actionId = districtActionAlias(requestedActionId)
        if not actionId then
            return false, "District City Action not implemented"
        end

        local request = {}
        for key, value in pairs(actionData) do
            request[key] = value
        end
        request.type = actionId
        request.action = actionId
        request.districtAction = requestedActionId
        request.districtId = districtEntry.districtId
        request.districtName = districtEntry.districtName

        local ok, result, detail = self:resolveAction(actor, request)
        if ok and detail then
            detail.districtId = districtEntry.districtId
            detail.districtName = districtEntry.districtName
            detail.districtAction = districtEntry.action
        end
        return ok, result, detail
    end

    return controller
end

return M
