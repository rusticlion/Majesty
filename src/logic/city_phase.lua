-- city_phase.lua
-- Minimal City Phase action facade.

local events = require('logic.events')
local alchemy = require('logic.alchemy')
local camp_actions = require('logic.camp_actions')
local currency = require('logic.currency')
local constants = require('constants')
local inventory = require('logic.inventory')
local city_events = require('data.city_events')
local city_districts = require('data.city_districts')
local city_layout = require('logic.city_layout')
local item_templates = require('data.item_templates')
local spell_registry = require('data.spell_registry')
local talent_catalog = require('data.talent_catalog')
local fate_resolver = require('logic.resolver')
local disposition = require('logic.disposition')
local animal_companions = require('data.animal_companions')
local bid_lore_engine = require('logic.bid_lore_engine')
local adventurer_module = require('entities.adventurer')
local quest_rules = require('logic.quest_rules')
local language_catalog = require('data.language_catalog')
local motif_catalog = require('data.motif_catalog')

local M = {}

function M.copyCityPhaseMetadata(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, entry in pairs(value) do
        copy[M.copyCityPhaseMetadata(key)] = M.copyCityPhaseMetadata(entry)
    end
    return copy
end

M.TAX_RATE = 0.5
M.TRAINING_COST_PER_XP = 50
M.BUILD_COST_PER_SYLLABLE = 50
M.FUNERAL_COST_PER_XP = 100
M.QUEST_XP_AWARD = 3
M.RESEARCH_COST = 50
M.BANKING_RETURN_RATE = 0.02
M.LEECHING_COST_PER_STAGE = 20
M.SPELL_RESEARCH_COST_PER_TILE = 25
M.LOAN_INTEREST_RATE = 30
M.VISIT_GRAVE_COST = 100
M.MAKEOVER_COST = 10
M.PILLOW_TALK_COST = 10
M.PLAY_OUTING_COST = 25
M.COURT_OF_WANDS_DUES = 100
M.BLOOD_FEAST_COST = 50
M.SWORDWHORES_DUES = 100
M.DOOMSAYING_COST = 10
M.SEEK_TRUTH_COST = 50
M.BEGGARS_GUILD_DUES = 100
M.SEND_LETTER_COST = 10
M.STUDY_LANGUAGE_COST = 200
M.ANIMAL_COMPANION_TRAINING_COST = 100
M.MAX_FAME = 5
M.MAX_MYTHRYS_INITIATION = 21
M.generateCityLayout = city_layout.generateCityLayout

M.SUPPORT_CONTRIBUTION_IMPACTS = {
    {
        id = "dramatic",
        label = "dramatic statement",
        minimumGold = 1000,
    },
    {
        id = "significant",
        label = "significant impact",
        minimumGold = 100,
    },
    {
        id = "humble_meaningful",
        label = "humble but meaningful impact",
        minimumGold = 50,
    },
    {
        id = "small",
        label = "small impact",
        minimumGold = 25,
    },
}

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

M.CITY_PHASE_STEP_ORDER = {
    M.STEPS.DEATH_AND_TAXES,
    M.STEPS.NOTEWORTHY_DEEDS,
    M.STEPS.CITY_EVENTS,
    M.STEPS.TURN_IN_CONTRACTS,
    M.STEPS.UPKEEP,
    M.STEPS.CITY_ACTIONS,
    M.STEPS.PLAN_NEXT_CRAWL,
    M.STEPS.RESTOCK_UNDERWORLD,
}

M.CITY_PHASE_STEP_DETAILS = {
    {
        index = 1,
        key = M.STEPS.DEATH_AND_TAXES,
        label = "Death and taxes",
        summary = "Each adventurer pays the All-Watch 50% of carried liquid gold after returning through an Underworld gate.",
        gmRole = "Demand the fixed tax and adjudicate any smuggling or bribery fallout.",
        playerRole = "Declare carried liquid gold and pay from coin, not art or extravagant treasure.",
        rules = {
            taxRate = M.TAX_RATE,
            liquidAssets = "gold coins",
            nonLiquidAssets = "art and extravagance such as gems, books, decorative weapons, jewelry, and statues",
        },
    },
    {
        index = 2,
        key = M.STEPS.NOTEWORTHY_DEEDS,
        label = "Noteworthy deeds",
        summary = "Erase the oldest deed, review the last Crawl, and record table-approved accomplishments as active guild deeds.",
        gmRole = "Arbitrate whether suggested accomplishments are actually noteworthy.",
        playerRole = "Suggest deeds and choose which five active deeds remain if the roster exceeds the Fame cap.",
        rules = {
            fameCap = M.MAX_FAME,
            emptyReturnPenalty = "erase the oldest deed and lose 1 Fame",
        },
    },
    {
        index = 3,
        key = M.STEPS.CITY_EVENTS,
        label = "City Events",
        summary = "Draw a numbered Major Arcana City Event, interpreting I-V as curiosities, VI-X as happenings, XI-XV as rumors, XVI-XX as travel events, and XXI as Signs and Portents.",
        gmRole = "Maintain the twenty-one-entry City Events table and interpret the result through the City Phase.",
        playerRole = "Respond to the event's framing, limits, rumors, or travel complications.",
        rules = {
            deck = "GM major arcana",
            excludes = "The Fool",
            signsAndPortents = "XXI consults the top minor arcana discard",
            categories = {
                [1] = "curiosities",
                [6] = "happenings",
                [11] = "rumors",
                [16] = "travel_events",
                [21] = "signs_and_portents",
            },
        },
    },
    {
        index = 4,
        key = M.STEPS.TURN_IN_CONTRACTS,
        label = "Turn in contracts",
        summary = "Turn in completed contracts for the promised reward and 1 XP per fulfilled contract.",
        gmRole = "Play the patron scene and confirm completed objectives.",
        playerRole = "Choose eligible completed contracts to turn in and divide rewards.",
        rules = {
            xpPerContract = 1,
            incompleteContracts = "remain active",
        },
    },
    {
        index = 5,
        key = M.STEPS.UPKEEP,
        label = "Upkeep",
        summary = "Each adventurer pays for a lifestyle tier, refills qualifying Omphalic Market gear, and may recover through common or luxurious upkeep.",
        gmRole = "Apply current City Event price or action restrictions before resolving upkeep choices.",
        playerRole = "Choose destitute, impoverished, common, or luxurious upkeep and any allowed refill or recovery choices.",
        rules = {
            tiers = {
                destitute = 0,
                impoverished = 25,
                common = 50,
                luxurious = 100,
            },
            destituteConsequence = "begin the next Crawl Stressed",
            commonRecovery = "may burn charged Bonds as in Camp Recovery",
            luxuriousRecovery = "heal all Wounds and refresh all Resolve",
        },
    },
    {
        index = 6,
        key = M.STEPS.CITY_ACTIONS,
        label = "City Actions",
        summary = "Each active adventurer performs one City Action, including common actions, Camp Actions, and discovered special district actions.",
        gmRole = "Provide common actions, discovered district actions, and rulings for unusual proposals.",
        playerRole = "Declare one concrete action and pay any required lump-sum cost.",
        rules = {
            actionsPerAdventurer = 1,
            broadException = "Beg and Busk is the main listed action that does not require a cash lump sum",
        },
    },
    {
        index = 7,
        key = M.STEPS.PLAN_NEXT_CRAWL,
        label = "Plan the next Crawl",
        summary = "Reassemble in a tavern, review quests and contracts, and choose the guild's next destination or job.",
        gmRole = "Offer four to six possible contracts or confirm continued quest/destination plans.",
        playerRole = "Role-play the debrief and collectively sign up for a contract or choose the next objective.",
        rules = {
            offeredContracts = "four to six",
            agreement = "guild decision",
        },
    },
    {
        index = 8,
        key = M.STEPS.RESTOCK_UNDERWORLD,
        label = "Restock the Underworld",
        summary = "Before the next session, replace used Meatgrinder, City Event, and Signs and Portents entries and record map or faction changes.",
        gmRole = "Refresh consumed random-table entries and update the Underworld based on the guild's consequences.",
        playerRole = "Usually no direct action; table choices from the prior Crawl inform the restock.",
        rules = {
            tables = {
                "Meatgrinder",
                "City Events",
                "Signs and Portents",
            },
        },
    },
}

M.CITY_PHASE_PROCEDURE = {
    source = "Core Rules Chapter 9: The City Phase",
    trigger = "When the guild returns to civilization after a Crawl",
    purpose = "Pursue long-term goals, research next steps, restock supplies, and refresh the Underworld before the next delve.",
    steps = M.CITY_PHASE_STEP_DETAILS,
}

local CITY_PHASE_STEP_INDEX = {}
for index, step in ipairs(M.CITY_PHASE_STEP_ORDER) do
    CITY_PHASE_STEP_INDEX[step] = index
end

local CITY_PHASE_STEP_ALIASES = {
    death = M.STEPS.DEATH_AND_TAXES,
    tax = M.STEPS.DEATH_AND_TAXES,
    taxes = M.STEPS.DEATH_AND_TAXES,
    death_and_tax = M.STEPS.DEATH_AND_TAXES,
    death_and_taxes = M.STEPS.DEATH_AND_TAXES,
    noteworthy = M.STEPS.NOTEWORTHY_DEEDS,
    deeds = M.STEPS.NOTEWORTHY_DEEDS,
    noteworthy_deed = M.STEPS.NOTEWORTHY_DEEDS,
    noteworthy_deeds = M.STEPS.NOTEWORTHY_DEEDS,
    city_event = M.STEPS.CITY_EVENTS,
    city_events = M.STEPS.CITY_EVENTS,
    contract = M.STEPS.TURN_IN_CONTRACTS,
    contracts = M.STEPS.TURN_IN_CONTRACTS,
    turn_in_contract = M.STEPS.TURN_IN_CONTRACTS,
    turn_in_contracts = M.STEPS.TURN_IN_CONTRACTS,
    upkeep = M.STEPS.UPKEEP,
    action = M.STEPS.CITY_ACTIONS,
    actions = M.STEPS.CITY_ACTIONS,
    city_action = M.STEPS.CITY_ACTIONS,
    city_actions = M.STEPS.CITY_ACTIONS,
    plan = M.STEPS.PLAN_NEXT_CRAWL,
    next_crawl = M.STEPS.PLAN_NEXT_CRAWL,
    plan_next_crawl = M.STEPS.PLAN_NEXT_CRAWL,
    restock = M.STEPS.RESTOCK_UNDERWORLD,
    restock_underworld = M.STEPS.RESTOCK_UNDERWORLD,
}

local function normalizeCityPhaseStep(step)
    if type(step) == "table" then
        step = step.step or step.id or step.name
    end
    local normalized = tostring(step or ""):lower()
    normalized = normalized:gsub("^%s+", ""):gsub("%s+$", "")
    normalized = normalized:gsub("[%s%-]+", "_")
    return CITY_PHASE_STEP_ALIASES[normalized] or normalized
end

local function cityPhaseStepIndex(step)
    return CITY_PHASE_STEP_INDEX[normalizeCityPhaseStep(step)]
end

function M.normalizeCityPhaseStep(step)
    return normalizeCityPhaseStep(step)
end

function M.getCityPhaseStepOrder()
    local order = {}
    for index, step in ipairs(M.CITY_PHASE_STEP_ORDER) do
        order[index] = step
    end
    return order
end

function M.getCityPhaseProcedure()
    return M.copyCityPhaseMetadata(M.CITY_PHASE_PROCEDURE)
end

function M.getCityPhaseStepDetails(step)
    if step == nil then
        return M.copyCityPhaseMetadata(M.CITY_PHASE_STEP_DETAILS)
    end
    local stepId = normalizeCityPhaseStep(step)
    for _, detail in ipairs(M.CITY_PHASE_STEP_DETAILS) do
        if detail.key == stepId then
            return M.copyCityPhaseMetadata(detail)
        end
    end
    return nil
end

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
    CHANGE_MOTIF = "change_motif",
    CHOOSE_MONSTER_HUNTER_FOE = "choose_monster_hunter_foe",
    COMMISSION_CRAFT = "commission_craft",
    HOLD_FUNERAL = "hold_funeral",
    RETIRE_ADVENTURER = "retire_adventurer",
    DECLARE_NEW_QUEST = "declare_new_quest",
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
    TRAIN_ANIMAL_COMPANION = "train_animal_companion",
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

M.STANDARD_CITY_ACTION_DETAILS = {
    [M.ACTIONS.BANKING] = {
        key = M.ACTIONS.BANKING,
        label = "Banking",
        category = "common_city_action",
        summary = "Store extra items and coin in Cult-run banks where gear is safe and total gold investment earns a 2% City Phase return.",
        cost = "none",
        returnRate = M.BANKING_RETURN_RATE,
        preservesGear = true,
        consumesCityAction = true,
    },
    [M.ACTIONS.BEG_AND_BUSK] = {
        key = M.ACTIONS.BEG_AND_BUSK,
        label = "Beg and Busk",
        category = "common_city_action",
        summary = "Sing or perform in the streets and winesinks, drawing from the minor arcana for gold equal to card value plus Wands.",
        cost = "none",
        deck = "minor_arcana",
        attribute = "wands",
        consumesCityAction = "on success",
    },
    [M.ACTIONS.BUILD] = {
        key = M.ACTIONS.BUILD,
        label = "Build",
        category = "common_city_action",
        summary = "Create a permanent building, monument, or civic improvement described in a few words and priced by syllable.",
        costGoldPerSyllable = M.BUILD_COST_PER_SYLLABLE,
        requiresGMApproval = true,
        consumesCityAction = true,
    },
    [M.ACTIONS.CAMP_ACTION] = {
        key = M.ACTIONS.CAMP_ACTION,
        label = "Camp Action",
        category = "common_city_action",
        summary = "Perform any supported Camp Action during the City Phase, such as Use a Talent or Use an Item.",
        delegatesTo = "Camp Actions",
        consumesCityAction = true,
    },
    [M.ACTIONS.CAROUSE] = {
        key = M.ACTIONS.CAROUSE,
        label = "Carouse",
        category = "common_city_action",
        summary = "Spend 50% or 100% of brought-back gold for 1 or 2 XP, then draw a Major Arcana hangover complication.",
        spendOptions = {
            { broughtBackGoldPercent = 50, xp = 1 },
            { broughtBackGoldPercent = 100, xp = 2 },
        },
        hangoverDeck = "GM major arcana",
        consumesCityAction = true,
    },
    [M.ACTIONS.COMMISSION_CRAFT] = {
        key = M.ACTIONS.COMMISSION_CRAFT,
        label = "Commission Craft",
        category = "common_city_action",
        summary = "Commission a bespoke item outside the Omphalic Market after the GM confirms it is reasonable and names an appropriate merchant.",
        costs = {
            { scale = "farmer", goldPerSyllable = M.COMMISSION_CRAFT_RATES.farmer },
            { scale = "adventurer", goldPerSyllable = M.COMMISSION_CRAFT_RATES.adventurer },
            { scale = "noble", goldPerSyllable = M.COMMISSION_CRAFT_RATES.noble },
            { scale = "novel", goldPerSyllable = M.COMMISSION_CRAFT_RATES.novel },
        },
        requiresGMApproval = true,
        consumesCityAction = true,
    },
    [M.ACTIONS.HOLD_FUNERAL] = {
        key = M.ACTIONS.HOLD_FUNERAL,
        label = "Hold a Funeral",
        category = "common_city_action",
        summary = "Haul a dead adventurer from the Underworld and spend funeral expenses so the player's new adventurer can reclaim previous XP.",
        costGoldPerXP = M.FUNERAL_COST_PER_XP,
        requiresDeadAdventurer = true,
        consumesCityAction = true,
    },
    [M.ACTIONS.PREPARE_COMPONENTS] = {
        key = M.ACTIONS.PREPARE_COMPONENTS,
        label = "Prepare Components",
        category = "common_city_action",
        summary = "Fill pack slots with chosen Appendix A spell components through talismongers, rituals, or gathering outside the City.",
        sourceCatalog = "Appendix A spell components",
        slotsPerComponent = 1,
        consumesCityAction = true,
    },
    [M.ACTIONS.RESEARCH] = {
        key = M.ACTIONS.RESEARCH,
        label = "Research",
        category = "common_city_action",
        summary = "Spend gold and test Cups to ask the GM one question on a success or three questions on a great success.",
        costGold = M.RESEARCH_COST,
        attribute = "cups",
        successQuestions = 1,
        greatSuccessQuestions = 3,
        consumesCityAction = true,
    },
    [M.ACTIONS.SUPPORT] = {
        key = M.ACTIONS.SUPPORT,
        label = "Support",
        category = "common_city_action",
        summary = "Advance a GM-approved long-term project by spending money in a way that supports the goal.",
        complexityRange = { min = 2, max = 8 },
        contributionImpacts = M.SUPPORT_CONTRIBUTION_IMPACTS,
        requiresGMApproval = true,
        consumesCityAction = true,
    },
    [M.ACTIONS.TRAIN] = {
        key = M.ACTIONS.TRAIN,
        label = "Train",
        category = "common_city_action",
        summary = "Seek an available expert and spend 50 gold per XP invested in a talent, preparing uses equal to XP invested.",
        costGoldPerXP = M.TRAINING_COST_PER_XP,
        preparesUsesEqualXP = true,
        consumesCityAction = true,
    },
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
    train_animal_companion = M.ACTIONS.TRAIN_ANIMAL_COMPANION,
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
    change_motif = M.ACTIONS.CHANGE_MOTIF,
    rewrite_motif = M.ACTIONS.CHANGE_MOTIF,
    rewrite_motif_descriptor = M.ACTIONS.CHANGE_MOTIF,
    choose_monster_hunter_foe = M.ACTIONS.CHOOSE_MONSTER_HUNTER_FOE,
    change_monster_hunter_foe = M.ACTIONS.CHOOSE_MONSTER_HUNTER_FOE,
    monster_hunter_foe = M.ACTIONS.CHOOSE_MONSTER_HUNTER_FOE,
    choose_hated_foe = M.ACTIONS.CHOOSE_MONSTER_HUNTER_FOE,
    commission_craft = M.ACTIONS.COMMISSION_CRAFT,
    commission = M.ACTIONS.COMMISSION_CRAFT,
    craft = M.ACTIONS.COMMISSION_CRAFT,
    hold_funeral = M.ACTIONS.HOLD_FUNERAL,
    funeral = M.ACTIONS.HOLD_FUNERAL,
    retire = M.ACTIONS.RETIRE_ADVENTURER,
    retirement = M.ACTIONS.RETIRE_ADVENTURER,
    retire_adventurer = M.ACTIONS.RETIRE_ADVENTURER,
    declare_new_quest = M.ACTIONS.DECLARE_NEW_QUEST,
    new_quest = M.ACTIONS.DECLARE_NEW_QUEST,
    continue_questing = M.ACTIONS.DECLARE_NEW_QUEST,
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
    train_animal_companion = M.ACTIONS.TRAIN_ANIMAL_COMPANION,
    hire_animal_trainer = M.ACTIONS.TRAIN_ANIMAL_COMPANION,
    animal_trainer = M.ACTIONS.TRAIN_ANIMAL_COMPANION,
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

local function refreshCityLayoutCounts(layout)
    if type(layout) ~= "table" then
        return
    end
    layout.counts = layout.counts or {}
    layout.counts.districtPlacements = #(layout.districts or {})
    layout.counts.coreDistricts = #(layout.coreDistricts or {})
    layout.counts.sprawlDistricts = #(layout.sprawlDistricts or {})
    layout.counts.constants = #(layout.constants or {})
    layout.counts.specialCityActions = #(layout.specialCityActions or {})
    layout.counts.totalUniqueDistricts = layout.counts.districtPlacements + layout.counts.constants
end

local function cityLayoutDistrictId(placement)
    return placement and placement.district and placement.district.id or placement and placement.districtId
end

local function addDistrictToCityLayout(layout, card, placement)
    if type(layout) ~= "table" or type(card) ~= "table" then
        return nil, "District card required"
    end

    local district = city_districts.getDistrict(card.suit, tonumber(card.value))
    if not district then
        return nil, "District card must map to an Appendix D district"
    end

    local entry = {
        placement = placement or "city_event",
        card = card,
        district = district,
    }
    layout.districts = layout.districts or {}
    layout.specialCityActions = layout.specialCityActions or {}
    layout.districts[#layout.districts + 1] = entry

    for _, specialAction in ipairs(district.specialCityActions or {}) do
        layout.specialCityActions[#layout.specialCityActions + 1] = {
            districtId = district.id,
            districtName = district.name,
            action = specialAction,
        }
    end

    refreshCityLayoutCounts(layout)
    return entry
end

local function findDistrictPlacement(layout, districtId)
    if type(layout) ~= "table" then
        return nil, nil
    end

    local wanted = districtId and tostring(districtId) or nil
    for index, placement in ipairs(layout.districts or {}) do
        if not wanted or tostring(cityLayoutDistrictId(placement) or "") == wanted then
            return placement, index
        end
    end
    return nil, nil
end

local function removeDistrictFromCityLayout(layout, districtId)
    local placement, index = findDistrictPlacement(layout, districtId)
    if not placement then
        return nil
    end

    local removedId = cityLayoutDistrictId(placement)
    table.remove(layout.districts, index)
    for i = #(layout.specialCityActions or {}), 1, -1 do
        if tostring(layout.specialCityActions[i].districtId or "") == tostring(removedId or "") then
            table.remove(layout.specialCityActions, i)
        end
    end

    refreshCityLayoutCounts(layout)
    return placement
end

local function findDistrictActionEntry(layout, districtId)
    if type(layout) ~= "table" then
        return nil
    end

    local wanted = districtId and tostring(districtId) or nil
    for _, entry in ipairs(layout.specialCityActions or {}) do
        if not entry.blockedByCityEvent and (not wanted or tostring(entry.districtId or "") == wanted) then
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
        maxStage = 2,
        stageCosts = {
            [1] = 5,
            [2] = 1,
        },
        stageEffects = {
            [1] = "May draw five Challenge cards instead of four, then spit out 1-4 teeth.",
            [2] = "Cups equals 1; disfavor on fine motor tests of fate.",
        },
        quitCharges = 5,
        recentlyTakenEffect = "draw_five_challenge_cards",
        reexposureClearsCuredStage = 2,
    },
    ghost_lotus = {
        id = "ghost_lotus",
        name = "Ghost Lotus",
        cost = 5,
        affliction = "ghost_lotus",
        maxStage = 3,
        stageRecovery = {
            [1] = { xp = 1, charges = 0 },
            [2] = { charges = 2 },
            [3] = { charges = 1 },
        },
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

function M.getCityActionDetails(action)
    if action == nil then
        return M.copyCityPhaseMetadata(M.STANDARD_CITY_ACTION_DETAILS)
    end
    local actionId = action
    if type(action) == "table" then
        actionId = action.type or action.action or action.id
    end
    return M.copyCityPhaseMetadata(M.STANDARD_CITY_ACTION_DETAILS[normalizeActionId(actionId)])
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
    return actor and
        not (actor.conditions and actor.conditions.dead) and
        actor.dead ~= true and
        actor.retired ~= true and
        actor.lost ~= true and
        actor.status ~= "dead" and
        actor.status ~= "retired" and
        actor.status ~= "lost"
end

local function isDeadAdventurer(actor)
    local conditions = actor and actor.conditions or {}
    return actor ~= nil and (conditions.dead == true or actor.dead == true or actor.status == "dead")
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

local function getPentacles(actor)
    if actor and actor.getAttribute then
        return actor:getAttribute(constants.SUITS.PENTACLES)
    end
    return tonumber(actor and actor.pentacles) or 0
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
    return language_catalog.normalizeLanguage(value)
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

local function normalizedResearchAnswer(value)
    if type(value) == "table" then
        return shallowClone(value)
    end
    if type(value) == "string" then
        local text = value:gsub("^%s+", ""):gsub("%s+$", "")
        if text ~= "" then
            return {
                summary = text,
                details = {},
                implication = "",
                sourceRefs = {},
            }
        end
    end
    return nil
end

local function loreAnswerResponse(answer)
    if type(answer) ~= "table" then
        return nil
    end
    return {
        summary = answer.summary or "",
        details = shallowClone(answer.details or {}),
        implication = answer.implication or "",
        sourceRefs = shallowClone(answer.sourceRefs or {}),
    }
end

local function collectResearchQuestionRequests(request)
    request = request or {}
    local raw = request.questionRequests or request.researchQuestions or request.questionsToAsk or
        request.ask or request.asks
    if not raw and type(request.questions) == "table" then
        raw = request.questions
    end

    local requests = {}
    local function add(item)
        if type(item) == "string" then
            requests[#requests + 1] = { question = item }
        elseif type(item) == "table" then
            requests[#requests + 1] = item
        end
    end

    if type(raw) == "string" then
        add(raw)
    elseif type(raw) == "table" then
        if raw.subjectId or raw.loreSubjectId or raw.questionType or raw.questionTypeId or raw.questionId or
           raw.answer or raw.response or raw.gmAnswer or raw.question then
            add(raw)
        else
            for _, item in ipairs(raw) do
                add(item)
            end
        end
    elseif request.subjectId or request.loreSubjectId or request.questionType or request.questionTypeId or
           request.questionId or request.answer or request.response or request.gmAnswer then
        add(request)
    end

    return requests
end

local function resolveResearchQuestionRequests(controller, request, allowedQuestions)
    allowedQuestions = math.max(0, math.floor(tonumber(allowedQuestions) or 0))
    local requested = collectResearchQuestionRequests(request)
    local answers = {}
    local pending = {}
    local overflow = {}
    local answeredCount = math.min(allowedQuestions, #requested)
    local engine = nil

    if answeredCount > 0 then
        engine = request.bidLoreEngine or request.loreEngine or controller.bidLoreEngine or
            bid_lore_engine.createBidLoreEngine({})
    end

    for index = 1, answeredCount do
        local questionRequest = requested[index] or {}
        local subjectId = questionRequest.subjectId or questionRequest.loreSubjectId or request.subjectId or
            request.loreSubjectId
        local questionType = questionRequest.questionType or questionRequest.questionTypeId or
            questionRequest.questionId or request.questionType or request.questionTypeId or request.questionId
        local answer = normalizedResearchAnswer(questionRequest.answer or questionRequest.response or
            questionRequest.gmAnswer)
        local source = answer and "gm" or nil
        local subject = subjectId and engine:getSubject(subjectId) or nil
        local question = questionType and engine:getQuestionType(questionType) or nil

        if not answer and subject and questionType then
            answer = loreAnswerResponse(subject.answers and subject.answers[questionType])
            if answer then
                source = "lore_catalog"
            end
        end

        local record = {
            question = questionRequest.question or questionRequest.prompt,
            subjectId = subjectId,
            subjectName = questionRequest.subjectName or (subject and subject.name),
            questionType = questionType,
            questionName = questionRequest.questionName or (question and question.name),
            response = answer,
            source = source,
            loreSpend = false,
        }

        if answer then
            answers[#answers + 1] = record
        else
            record.response = nil
            pending[#pending + 1] = record
        end
    end

    for index = answeredCount + 1, #requested do
        overflow[#overflow + 1] = shallowClone(requested[index])
    end

    return answers, pending, overflow, math.max(0, allowedQuestions - answeredCount)
end

local function contractCardValue(card)
    local value = math.floor(tonumber(card and card.value) or -1)
    if value >= 1 and value <= 14 then
        return value
    end
    return nil
end

local function contractTableEntryForValue(contractTable, value)
    if type(contractTable) ~= "table" or not value then
        return nil
    end

    if contractTable[value] then
        return contractTable[value]
    end

    for _, entry in ipairs(contractTable) do
        local entryValue = contractCardValue(entry)
        if not entryValue then
            entryValue = math.floor(tonumber(entry.cardValue or entry.value) or -1)
        end
        if entryValue == value then
            return entry
        end
    end

    return nil
end

local function jobBoardContractTable(opts)
    local tableSource = "rulebook_example_contracts"
    local contractTable = opts.contractTable or opts.jobBoardTable or opts.contractsTable or opts.contractTemplates
    if contractTable then
        tableSource = opts.contractTableSource or opts.tableSource or "custom_contract_table"
        return contractTable, tableSource
    end
    return M.EXAMPLE_CONTRACTS, tableSource
end

local function generateContractOffer(card, index, opts)
    opts = opts or {}
    local value = contractCardValue(card)
    if not value then
        return nil, "Job board cards must map to contracts I through King"
    end

    local contractTable, tableSource = jobBoardContractTable(opts)
    local template = contractTableEntryForValue(contractTable, value)
    if not template then
        return nil, "Job board contract table entry missing"
    end

    local offer = shallowClone(template)
    local suitName = constants.SUIT_NAMES[card and card.suit] or card and card.suitName
    local prefix = opts.idPrefix or opts.boardId or "job_board"
    local templateId = template.id or template.templateId or slugify(template.title or template.name or ("contract_" .. tostring(value)))
    offer.id = string.format("%s_%02d_%s_%s", slugify(prefix), index, templateId, slugify(suitName or card and card.name))
    offer.templateId = templateId
    offer.name = offer.name or offer.title
    offer.status = offer.status or "offered"
    offer.generated = true
    offer.source = tableSource
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
            local candidate = entry.templateId or entry.itemTemplate or entry.itemTemplateId or entry.template or
                entry.itemId or entry.id or entry[1]
            local templateId = nil
            if candidate and item_templates.getTemplate(candidate) then
                templateId = candidate
            end
            local name = entry.name or entry.itemName or (not templateId and candidate)
            requests[#requests + 1] = {
                templateId = templateId,
                customId = entry.customId or (not templateId and (entry.itemId or entry.id)),
                name = name,
                tier = entry.tier or entry.marketTier or entry.priceLevel or entry.upkeepTier,
                custom = entry.custom == true or entry.everyday == true or entry.gmApproved == true or
                    entry.approved == true,
                quantity = math.max(1, math.floor(tonumber(entry.quantity or entry.count) or 1)),
                location = entry.location or inventory.LOCATIONS.PACK,
                forTalent = entry.forTalent == true,
                talentRequired = entry.talentRequired == true,
                requiredForTalent = entry.requiredForTalent == true,
                talentItem = entry.talentItem == true,
                size = math.max(1, math.floor(tonumber(entry.size or entry.slots) or inventory.SIZE.NORMAL)),
                oversized = entry.oversized == true,
                stackable = entry.stackable == true,
                stackSize = math.max(1, math.floor(tonumber(entry.stackSize or entry.stack_size) or 1)),
                itemType = entry.type or entry.itemType,
                properties = entry.properties,
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

local MEATGRINDER_RESTOCK_SECTIONS = {
    curiosity = { key = "curiosity", offset = 5 },
    travel_event = { key = "travel_event", offset = 10 },
    random_encounter = { key = "random_encounter", offset = 15 },
    quest_rumor = { key = "quest_rumor", singleton = true },
}

local function cityEventCategoryForValue(value)
    return city_events.categoryForValue(value)
end

local function parseConsumedMeatgrinderKey(key)
    if type(key) ~= "string" then
        return nil
    end

    local roomId, category, cardValue = key:match("^([^:]+):([^:]+):([^:]+)$")
    if roomId then
        return {
            raw = key,
            roomId = roomId,
            category = category,
            cardValue = tonumber(cardValue),
        }
    end

    roomId, category = key:match("^([^:]+):([^:]+)$")
    if roomId then
        return {
            raw = key,
            roomId = roomId,
            category = category,
        }
    end

    return nil
end

local function replacementEntry(replacement)
    return replacement.entry or replacement.replacement or replacement.newEntry or replacement
end

local function withConsumedReplacementDefaults(replacements, consumedEntries)
    if type(replacements) ~= "table" or #replacements == 0 then
        return replacements
    end

    local out = {}
    for index, replacement in ipairs(replacements) do
        if type(replacement) == "table" then
            local copy = {}
            for key, value in pairs(replacement) do
                copy[key] = value
            end
            local consumed = consumedEntries and consumedEntries[index]
            if consumed and copy.key == nil and copy.index == nil and copy.cardValue == nil and copy.value == nil then
                copy.key = consumed.value or consumed.cardValue or consumed.key or consumed.index
            end
            out[#out + 1] = copy
        else
            out[#out + 1] = replacement
        end
    end
    return out
end

local function applyNestedMeatgrinderReplacement(tableRef, replacement)
    local category = replacement.category or replacement.eventCategory
    local section = category and MEATGRINDER_RESTOCK_SECTIONS[category]
    if not section or type(tableRef[section.key]) ~= "table" then
        return nil
    end

    local key = replacement.key or replacement.value or replacement.cardValue or replacement.index
    local cardValue = tonumber(replacement.cardValue or replacement.value or replacement.key)
    local newEntry = replacementEntry(replacement)

    if section.singleton then
        local oldEntry = tableRef[section.key]
        tableRef[section.key] = newEntry
        return {
            key = cardValue or section.key,
            category = category,
            tableKey = section.key,
            oldEntry = oldEntry,
            newEntry = newEntry,
        }
    end

    local index = tonumber(replacement.index)
    if not index and cardValue then
        index = cardValue - section.offset
    end
    if not index then
        index = tonumber(key)
    end
    if not index then
        return nil
    end

    local oldEntry = tableRef[section.key][index]
    tableRef[section.key][index] = newEntry
    return {
        key = cardValue or key or index,
        category = category,
        tableKey = section.key,
        index = index,
        oldEntry = oldEntry,
        newEntry = newEntry,
    }
end

local function applyTableReplacements(tableRef, replacements)
    local details = {}
    if type(tableRef) ~= "table" then
        return details
    end

    for _, replacement in ipairs(replacementEntries(replacements)) do
        local nestedDetail = applyNestedMeatgrinderReplacement(tableRef, replacement)
        if nestedDetail then
            details[#details + 1] = nestedDetail
        else
            local key = replacement.key or replacement.value or replacement.cardValue or replacement.index or replacement.category
            if key ~= nil then
                local newEntry = replacementEntry(replacement)
                local oldEntry = tableRef[key]
                tableRef[key] = newEntry
                details[#details + 1] = {
                    key = key,
                    oldEntry = oldEntry,
                    newEntry = newEntry,
                }
            end
        end
    end
    return details
end

local function firstRestockFact(opts)
    if opts.notes then
        return opts.notes
    end
    local faction = opts.factionUpdates and opts.factionUpdates[1]
    if faction then
        return "Faction response: " .. tostring(faction.response or faction.status or faction.faction or "changed")
    end
    local mapUpdate = opts.mapUpdates and opts.mapUpdates[1]
    if mapUpdate then
        return "Map update: " .. tostring(mapUpdate.roomId or mapUpdate.room or mapUpdate.state or "changed")
    end
    return "The Underworld changes in response to the guild's last Crawl."
end

local function generateRestockReplacements(opts)
    opts = opts or {}
    local generated = {
        meatgrinder = {},
        cityEvents = {},
        signsAndPortents = {},
    }

    local consequence = firstRestockFact(opts)
    for _, consumedKey in ipairs(opts.consumedMeatgrinder or {}) do
        local parsed = parseConsumedMeatgrinderKey(consumedKey)
        if parsed and parsed.cardValue and parsed.category ~= "torches_gutter" then
            local roomText = parsed.roomId and parsed.roomId ~= "global" and (" in " .. parsed.roomId) or ""
            local categoryText = tostring(parsed.category or "event"):gsub("_", " ")
            local description = "Consequence restock: the " .. categoryText .. roomText ..
                " changes after the guild's last Crawl. " .. consequence
            if parsed.category == "quest_rumor" then
                description = "A new quest rumor points to consequences of the guild's last Crawl. " .. consequence
            end

            generated.meatgrinder[#generated.meatgrinder + 1] = {
                category = parsed.category,
                cardValue = parsed.cardValue,
                entry = {
                    value = parsed.cardValue,
                    category = parsed.category,
                    description = description,
                    generated = true,
                    source = "restock_underworld",
                    replacesConsumedKey = consumedKey,
                    roomId = parsed.roomId,
                    mapUpdates = opts.mapUpdates,
                    factionUpdates = opts.factionUpdates,
                    notes = opts.notes,
                },
            }
        end
    end

    local cityEventValue = opts.cityEventValue
    local lastCityEvent = opts.lastCityEvent
    if not cityEventValue and lastCityEvent then
        cityEventValue = (lastCityEvent.card and lastCityEvent.card.value) or
            (lastCityEvent.event and lastCityEvent.event.value)
    end
    cityEventValue = tonumber(cityEventValue)
    if cityEventValue then
        local oldCategory = lastCityEvent and
            ((lastCityEvent.event and lastCityEvent.event.category) or lastCityEvent.category)
        local category = oldCategory or cityEventCategoryForValue(cityEventValue)
        generated.cityEvents[#generated.cityEvents + 1] = {
            key = cityEventValue,
            entry = {
                value = cityEventValue,
                category = category,
                title = category == city_events.CATEGORIES.RUMOR and
                    "Rumors from Below" or "Consequences from Below",
                summary = "Word spreads through the City: " .. consequence,
                generated = true,
                source = "restock_underworld",
                basedOnMeatgrinder = generated.meatgrinder,
            },
        }
    end

    return generated
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

local function contractPatronRecord(contract, source, index)
    local record = nil
    if type(source) == "table" then
        record = shallowClone(source)
    elseif source ~= nil then
        record = {
            scene = tostring(source),
        }
    else
        record = {}
    end

    record.contractId = record.contractId or contractId(contract)
    record.contractName = record.contractName or contract.name or contract.title
    record.index = record.index or index
    record.patron = record.patron or contract.patron or contract.client or contract.issuer or contract.faction
    record.patronId = record.patronId or contract.patronId or contract.clientId or contract.issuerId or
        (type(record.patron) == "table" and (record.patron.id or record.patron.key))
    record.patronName = record.patronName or contract.patronName or contract.clientName or contract.issuerName or
        (type(record.patron) == "table" and (record.patron.name or record.patron.title)) or
        (type(record.patron) == "string" and record.patron or nil)
    record.scene = record.scene or record.roleplay or record.description or record.text or record.notes
    record.reaction = record.reaction or record.outcome or record.response or contract.patronReaction
    record.disposition = record.disposition or contract.patronDisposition
    record.notes = record.notes or record.gmNotes or record.authorNotes

    if not record.patron and not record.patronName and not record.scene and not record.reaction and
       not record.disposition and not record.notes then
        return nil
    end

    if type(record.patron) == "table" then
        if record.disposition then
            record.patron.disposition = record.disposition
        end
        if record.reaction then
            record.patron.lastContractReaction = record.reaction
        end
        record.patron.lastContractTurnIn = record
    end

    return record
end

local function contractPatronSource(sources, contract, index)
    if type(sources) ~= "table" then
        return sources
    end

    local id = contractId(contract)
    if id and sources[id] ~= nil then
        return sources[id]
    end
    if sources[index] ~= nil then
        return sources[index]
    end

    for _, entry in ipairs(sources) do
        if type(entry) == "table" and (
            entry.contract == contract or
            (id and (entry.contractId == id or entry.id == id))
        ) then
            return entry
        end
    end

    return nil
end

function M.getTurnInContractsOptions(opts)
    opts = opts or {}
    local request = opts.request or opts.turnInContracts or opts.contractTurnIn or opts
    local contracts = request.contracts or opts.contracts or {}
    local selectedRefs = normalizeList(request.selectedContractIds or request.contractIds or request.selectedContracts or
        request.selectedContractId or request.contractId)
    local selectedOnly = #selectedRefs > 0
    local function asRecipientList(value)
        if not value then
            return {}
        end
        if actorId(value) then
            return { value }
        end
        return value
    end

    local recipients = asRecipientList(request.recipients or opts.recipients or request.guild or opts.guild)
    if #recipients == 0 then
        recipients = activeAdventurers(opts.guild or {})
    end
    local xpPerContract = math.max(0, math.floor(tonumber(request.xpPerContract or opts.xpPerContract) or 1))
    local treasury = request.guildTreasury or opts.guildTreasury or opts.treasury
    local patronSources = request.patronInteractions or request.patronRoleplay or request.patronScenes or
        request.patrons or opts.patronInteractions or opts.patronRoleplay or opts.patronScenes or opts.patrons

    local function distributionPreview(total, recipientList)
        total = math.max(0, math.floor(tonumber(total) or 0))
        recipientList = asRecipientList(recipientList)
        if total <= 0 or #recipientList == 0 then
            return {
                total = total,
                perRecipient = 0,
                remainder = total,
                recipients = {},
                projectedTreasuryGold = treasury and ((tonumber(treasury.gold) or 0) + total) or nil,
            }
        end

        local perRecipient = math.floor(total / #recipientList)
        local remainder = total - (perRecipient * #recipientList)
        local recipientPreviews = {}
        for _, recipient in ipairs(recipientList) do
            recipientPreviews[#recipientPreviews + 1] = {
                actor = recipient,
                actorId = actorId(recipient),
                name = recipient and recipient.name or actorId(recipient),
                gold = perRecipient,
                currentGold = recipient and currency.getGold(recipient) or nil,
                projectedGold = recipient and (currency.getGold(recipient) + perRecipient) or nil,
            }
        end

        return {
            total = total,
            perRecipient = perRecipient,
            remainder = remainder,
            recipients = recipientPreviews,
            projectedTreasuryGold = treasury and ((tonumber(treasury.gold) or 0) + remainder) or nil,
        }
    end

    local function patronPreview(contract, source, index)
        local record = nil
        if type(source) == "table" then
            record = shallowClone(source)
        elseif source ~= nil then
            record = {
                scene = tostring(source),
            }
        else
            record = {}
        end

        record.contractId = record.contractId or contractId(contract)
        record.contractName = record.contractName or contract.name or contract.title
        record.index = record.index or index
        record.patron = record.patron or contract.patron or contract.client or contract.issuer or contract.faction
        record.patronId = record.patronId or contract.patronId or contract.clientId or contract.issuerId or
            (type(record.patron) == "table" and (record.patron.id or record.patron.key))
        record.patronName = record.patronName or contract.patronName or contract.clientName or contract.issuerName or
            (type(record.patron) == "table" and (record.patron.name or record.patron.title)) or
            (type(record.patron) == "string" and record.patron or nil)
        record.scene = record.scene or record.roleplay or record.description or record.text or record.notes
        record.reaction = record.reaction or record.outcome or record.response or contract.patronReaction
        record.disposition = record.disposition or contract.patronDisposition
        record.notes = record.notes or record.gmNotes or record.authorNotes

        if not record.patron and not record.patronName and not record.scene and not record.reaction and
           not record.disposition and not record.notes then
            return nil
        end
        return record
    end

    local selectedSet = {}
    for _, ref in ipairs(selectedRefs) do
        selectedSet[tostring(type(ref) == "table" and contractId(ref) or ref)] = true
    end

    local contractOptions = {}
    for index, contract in ipairs(contracts) do
        local id = contractId(contract)
        local complete = isContractComplete(contract)
        local turnedIn = contract and contract.turnedIn == true
        local disabled = not complete or turnedIn
        local reason = nil
        if not complete then
            reason = "Selected contract incomplete"
        elseif turnedIn then
            reason = "Selected contract already turned in"
        end
        local rewardGold = contractRewardGold(contract)
        local contractRecipients = asRecipientList(contract.recipients or recipients)
        contractOptions[#contractOptions + 1] = {
            id = id,
            contractId = id,
            contract = contract,
            name = contract.name or contract.title,
            completed = complete,
            turnedIn = turnedIn,
            rewardGold = rewardGold,
            quantity = contract.quantity or contract.deliveredCount or contract.count,
            rewardPerItem = contract.rewardPerItem or contract.goldPerItem or contract.rewardGoldPerItem,
            selected = selectedSet[tostring(id)] == true,
            distribution = distributionPreview(rewardGold, contractRecipients),
            patronInteraction = patronPreview(
                contract,
                contractPatronSource(patronSources, contract, index) or
                    contract.patronInteraction or contract.patronRoleplay or contract.turnInScene,
                index
            ),
            disabled = disabled,
            unavailableReason = reason,
        }
    end

    local selectedContracts = {}
    local selectedContractIds = {}
    local invalidSelectedContracts = {}
    local turnInQueue = {}
    local disabled = false
    local unavailableReason = nil

    if request.contractsResolved == true or opts.contractsResolved == true then
        disabled = true
        unavailableReason = "Contracts already turned in"
    elseif selectedOnly then
        for _, ref in ipairs(selectedRefs) do
            local refId = type(ref) == "table" and contractId(ref) or ref
            local contract = refId and findContractById(contracts, refId) or nil
            if not contract and type(ref) == "table" and hasContract(contracts, ref) then
                contract = ref
            end
            local reason = nil
            if not contract then
                reason = "Selected contract not active"
            elseif not isContractComplete(contract) then
                reason = "Selected contract incomplete"
            elseif contract.turnedIn == true then
                reason = "Selected contract already turned in"
            end
            if reason then
                invalidSelectedContracts[#invalidSelectedContracts + 1] = {
                    contractId = refId,
                    contract = contract,
                    reason = reason,
                }
                if not disabled then
                    disabled = true
                    unavailableReason = reason
                end
            else
                selectedContracts[#selectedContracts + 1] = contract
                selectedContractIds[#selectedContractIds + 1] = contractId(contract)
                turnInQueue[#turnInQueue + 1] = contract
            end
        end
    else
        for _, contract in ipairs(contracts) do
            if isContractComplete(contract) and contract.turnedIn ~= true then
                turnInQueue[#turnInQueue + 1] = contract
            end
        end
    end

    local turnInContracts = {}
    local patronInteractions = {}
    local totalGold = 0
    for index, contract in ipairs(turnInQueue) do
        local rewardGold = contractRewardGold(contract)
        local distribution = distributionPreview(rewardGold, contract.recipients or recipients)
        local patronInteraction = patronPreview(
            contract,
            contractPatronSource(patronSources, contract, index) or
                contract.patronInteraction or contract.patronRoleplay or contract.turnInScene,
            index
        )
        if patronInteraction then
            patronInteractions[#patronInteractions + 1] = patronInteraction
        end
        totalGold = totalGold + rewardGold
        turnInContracts[#turnInContracts + 1] = {
            contract = contract,
            contractId = contractId(contract),
            name = contract.name or contract.title,
            rewardGold = rewardGold,
            distribution = distribution,
            selected = selectedOnly,
            patronInteraction = patronInteraction,
        }
    end

    local completedCount = #turnInContracts
    local xpAwarded = completedCount * xpPerContract
    local xpRecipients = {}
    if xpAwarded > 0 then
        for _, recipient in ipairs(recipients) do
            xpRecipients[#xpRecipients + 1] = {
                actor = recipient,
                actorId = actorId(recipient),
                name = recipient and recipient.name or actorId(recipient),
                xp = xpAwarded,
                currentXP = tonumber(recipient and recipient.xp) or 0,
                projectedXP = (tonumber(recipient and recipient.xp) or 0) + xpAwarded,
            }
        end
    end

    return {
        step = M.STEPS.TURN_IN_CONTRACTS,
        contractsResolved = request.contractsResolved == true or opts.contractsResolved == true,
        contracts = contractOptions,
        selected = selectedOnly,
        selectedContracts = selectedContracts,
        selectedContractIds = selectedContractIds,
        invalidSelectedContracts = invalidSelectedContracts,
        turnInContracts = turnInContracts,
        completedCount = completedCount,
        totalGold = totalGold,
        patronInteractions = patronInteractions,
        xpPerContract = xpPerContract,
        xpAwarded = xpAwarded,
        xpRecipients = xpRecipients,
        recipientCount = #recipients,
        recipients = recipients,
        guildTreasury = treasury,
        resultPreview = completedCount > 0 and "contracts_turned_in" or "no_completed_contracts",
        disabled = disabled,
        unavailableReason = unavailableReason,
    }
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

    local _, tableSource = jobBoardContractTable(opts)
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
        contractTableSource = tableSource,
        result = "job_board_generated",
    }
end

function M.getPlanNextCrawlOptions(opts)
    opts = opts or {}
    local request = opts.request or opts.plan or opts.nextCrawl or opts
    local roster = request.guildRoster or request.roster or opts.guildRoster or opts.roster or {}
    local currentContracts = request.contracts or request.currentContracts or opts.contracts or opts.currentContracts or
        roster.currentContracts or {}
    local offers = request.jobBoard or request.offers or request.availableContracts or request.contractOffers or
        opts.jobBoard or opts.offers or opts.availableContracts or opts.contractOffers or {}
    local cards = normalizeList(request.jobBoardCards or request.contractCards or request.cards or
        opts.jobBoardCards or opts.contractCards or opts.cards)
    local wantsGeneratedBoard = request.generateJobBoard == true or opts.generateJobBoard == true or #cards > 0
    local generatedJobBoard = nil
    local generationError = nil

    if #cards > 0 then
        local generated, detail = M.generateJobBoard({
            jobBoardCards = cards,
            idPrefix = request.idPrefix or request.boardId or opts.idPrefix or opts.boardId,
            contractTable = request.contractTable or request.jobBoardTable or request.contractsTable or
                opts.contractTable or opts.jobBoardTable or opts.contractsTable,
            contractTableSource = request.contractTableSource or request.tableSource or
                opts.contractTableSource or opts.tableSource,
            allowNonStandardCount = request.allowNonStandardCount or opts.allowNonStandardCount,
            discardDraws = false,
        })
        if generated then
            offers = generated
            generatedJobBoard = detail
        else
            generationError = detail
        end
    end

    local selectedRefs = normalizeList(
        request.selectedContractIds or request.contractIds or request.selectedContracts or request.contractId or
        opts.selectedContractIds or opts.contractIds or opts.selectedContracts or opts.contractId
    )
    local selectedById = {}
    for _, ref in ipairs(selectedRefs) do
        local refId = type(ref) == "table" and contractId(ref) or ref
        if refId then
            selectedById[tostring(refId)] = true
        end
    end

    local jobBoardOptions = {}
    for index, contract in ipairs(offers or {}) do
        if type(contract) == "table" then
            local id = contractId(contract) or tostring(index)
            local completed = contract.completed == true or contract.turnedIn == true
            jobBoardOptions[#jobBoardOptions + 1] = {
                id = id,
                contractId = id,
                contract = contract,
                name = contract.name or contract.title or id,
                title = contract.title or contract.name,
                patron = contract.patron or contract.client or contract.issuer or contract.faction,
                objective = contract.objective or contract.summary or contract.description,
                rewardGold = contractRewardGold(contract),
                rewardNote = contract.rewardNote or contract.rewardDescription,
                contractType = contract.contractType or contract.type,
                templateId = contract.templateId,
                source = contract.source,
                cardValue = contract.cardValue,
                cardRank = contract.cardRank,
                cardSuit = contract.cardSuit,
                status = contract.status,
                active = hasContract(currentContracts, contract),
                signed = contract.signed == true or contract.sealed == true,
                selected = selectedById[tostring(id)] == true,
                completed = completed,
                disabled = completed,
                unavailableReason = completed and "Selected contract already completed" or nil,
            }
        end
    end

    local selectedContracts = {}
    local selectedContractIds = {}
    local invalidSelectedContracts = {}
    local disabled = false
    local unavailableReason = nil
    if request.nextCrawlPlanned == true or opts.nextCrawlPlanned == true then
        disabled = true
        unavailableReason = "Next Crawl already planned"
    elseif generationError then
        disabled = true
        unavailableReason = generationError
    elseif request.requireJobBoard ~= false and opts.requireJobBoard ~= false and (#offers < 4 or #offers > 6) then
        disabled = true
        unavailableReason = "Job board should offer four to six contracts"
    else
        for _, ref in ipairs(selectedRefs) do
            local contract = type(ref) == "table" and ref or findContractById(offers, ref)
            local refId = type(ref) == "table" and contractId(ref) or ref
            if not contract or (type(ref) == "table" and not hasContract(offers, ref)) then
                disabled = true
                unavailableReason = "Selected contract not on job board"
                invalidSelectedContracts[#invalidSelectedContracts + 1] = {
                    contractId = refId,
                    contract = type(ref) == "table" and ref or nil,
                    unavailableReason = unavailableReason,
                }
            elseif contract.completed == true or contract.turnedIn == true then
                disabled = true
                unavailableReason = "Selected contract already completed"
                invalidSelectedContracts[#invalidSelectedContracts + 1] = {
                    contractId = contractId(contract),
                    contract = contract,
                    unavailableReason = unavailableReason,
                }
            else
                selectedContracts[#selectedContracts + 1] = contract
                selectedContractIds[#selectedContractIds + 1] = contractId(contract)
            end
            if disabled then
                break
            end
        end
    end

    local deck = request.deck or request.playerDeck or request.minorDeck or opts.deck or opts.playerDeck or opts.minorDeck
    local requiresJobBoardDraw = wantsGeneratedBoard and #cards == 0
    local currentQuest = request.currentQuest or request.quest or roster.currentQuest
    local destination = request.destination or request.nextDestination or roster.nextDestination
    local notes = request.notes or request.debrief or request.plan or roster.nextCrawlNotes
    local continuationPlanned = #selectedRefs == 0 and (currentQuest ~= nil or destination ~= nil or notes ~= nil)

    return {
        step = M.STEPS.PLAN_NEXT_CRAWL,
        jobBoard = offers,
        jobBoardOptions = jobBoardOptions,
        offeredCount = #offers,
        currentContracts = currentContracts,
        currentContractCount = #currentContracts,
        selectedContracts = selectedContracts,
        selectedContractIds = selectedContractIds,
        selectedCount = #selectedContracts,
        invalidSelectedContracts = invalidSelectedContracts,
        currentQuest = currentQuest,
        destination = destination,
        notes = notes,
        continuationPlanned = continuationPlanned,
        continueCurrentQuestOption = {
            id = "continue_current_quest",
            label = "Continue current quest",
            currentQuest = currentQuest,
            destination = destination,
            notes = notes,
            selected = continuationPlanned,
            disabled = false,
        },
        generatedJobBoard = generatedJobBoard,
        generationCards = generatedJobBoard and generatedJobBoard.cards or nil,
        generationError = generationError,
        requiresJobBoardDraw = requiresJobBoardDraw,
        autoDrawAvailable = requiresJobBoardDraw and deck ~= nil,
        deck = requiresJobBoardDraw and "minor_arcana" or nil,
        requireJobBoard = request.requireJobBoard ~= false and opts.requireJobBoard ~= false,
        disabled = disabled,
        unavailableReason = unavailableReason,
    }
end

function M.getRestockUnderworldOptions(opts)
    opts = opts or {}
    local request = opts.request or opts.restock or opts.underworldRestock or opts
    local meatgrinder = request.meatgrinder or opts.meatgrinder
    local consumedMeatgrinder = normalizeList(request.consumedMeatgrinder or request.consumedMeatgrinderEvents or
        opts.consumedMeatgrinder or opts.consumedMeatgrinderEvents)
    if meatgrinder and meatgrinder.getConsumedEvents then
        consumedMeatgrinder = normalizeList(meatgrinder:getConsumedEvents())
    end
    local consumedCityEvents = normalizeList(request.consumedCityEvents or opts.consumedCityEvents)
    local consumedSignsAndPortents = normalizeList(
        request.consumedSignsAndPortents or request.consumedSigns or opts.consumedSignsAndPortents or opts.consumedSigns
    )
    local mapUpdates = normalizeList(request.mapUpdates or request.changedRooms or request.mapNotes or
        opts.mapUpdates or opts.changedRooms or opts.mapNotes)
    local factionUpdates = normalizeList(request.factionUpdates or request.factions or opts.factionUpdates or opts.factions)
    local generateReplacements = request.generateReplacements or request.autoGenerateReplacements or
        request.generateRestockEntries or opts.generateReplacements or opts.autoGenerateReplacements or
        opts.generateRestockEntries
    local generatedReplacements = nil
    if generateReplacements then
        generatedReplacements = generateRestockReplacements({
            consumedMeatgrinder = consumedMeatgrinder,
            lastCityEvent = request.lastCityEvent or opts.lastCityEvent,
            cityEventValue = request.cityEventValue or request.cityEventCardValue or
                opts.cityEventValue or opts.cityEventCardValue,
            mapUpdates = mapUpdates,
            factionUpdates = factionUpdates,
            notes = request.notes or request.restockNotes or opts.notes or opts.restockNotes,
        })
    end

    local meatgrinderReplacementInput = request.meatgrinderReplacements or request.meatgrinderEntries or
        opts.meatgrinderReplacements or opts.meatgrinderEntries
    if not meatgrinderReplacementInput and generatedReplacements then
        meatgrinderReplacementInput = generatedReplacements.meatgrinder
    end
    local cityEventReplacementInput = request.cityEventReplacements or request.cityEvents or
        opts.cityEventReplacements or opts.cityEvents
    if not cityEventReplacementInput and generatedReplacements then
        cityEventReplacementInput = generatedReplacements.cityEvents
    end
    cityEventReplacementInput = withConsumedReplacementDefaults(cityEventReplacementInput, consumedCityEvents)
    local signReplacementInput = request.signsAndPortentsReplacements or request.signsAndPortents or
        opts.signsAndPortentsReplacements or opts.signsAndPortents
    if not signReplacementInput and generatedReplacements then
        signReplacementInput = generatedReplacements.signsAndPortents
    end
    signReplacementInput = withConsumedReplacementDefaults(signReplacementInput, consumedSignsAndPortents)

    local function previewTableReplacements(tableRef, replacements)
        local details = {}
        if type(tableRef) ~= "table" then
            return details
        end
        for _, replacement in ipairs(replacementEntries(replacements)) do
            local category = type(replacement) == "table" and (replacement.category or replacement.eventCategory) or nil
            local section = category and MEATGRINDER_RESTOCK_SECTIONS[category]
            local key = type(replacement) == "table" and
                (replacement.key or replacement.value or replacement.cardValue or replacement.index or replacement.category) or nil
            local cardValue = type(replacement) == "table" and
                tonumber(replacement.cardValue or replacement.value or replacement.key) or nil
            local newEntry = type(replacement) == "table" and replacementEntry(replacement) or replacement
            if section and type(tableRef[section.key]) == "table" then
                if section.singleton then
                    details[#details + 1] = {
                        key = cardValue or section.key,
                        category = category,
                        tableKey = section.key,
                        oldEntry = tableRef[section.key],
                        newEntry = newEntry,
                    }
                else
                    local index = type(replacement) == "table" and tonumber(replacement.index) or nil
                    if not index and cardValue then
                        index = cardValue - section.offset
                    end
                    if not index then
                        index = tonumber(key)
                    end
                    if index then
                        details[#details + 1] = {
                            key = cardValue or key or index,
                            category = category,
                            tableKey = section.key,
                            index = index,
                            oldEntry = tableRef[section.key][index],
                            newEntry = newEntry,
                        }
                    end
                end
            elseif key ~= nil then
                details[#details + 1] = {
                    key = key,
                    oldEntry = tableRef[key],
                    newEntry = newEntry,
                }
            end
        end
        return details
    end

    local state = request.underworldState or opts.underworldState or
        (request.cityState and request.cityState.underworldState) or (opts.cityState and opts.cityState.underworldState) or {}
    local mapUpdateOptions = {}
    for _, update in ipairs(mapUpdates) do
        if type(update) == "table" then
            local roomId = update.roomId or update.room or update.locationId or update.id
            mapUpdateOptions[#mapUpdateOptions + 1] = {
                roomId = roomId and tostring(roomId) or nil,
                update = update,
                currentState = roomId and state.rooms and state.rooms[tostring(roomId)] or nil,
            }
        end
    end

    local factionUpdateOptions = {}
    for _, update in ipairs(factionUpdates) do
        if type(update) == "table" then
            local factionId = update.factionId or update.faction or update.id or update.name
            local normalizedFactionId = factionId and slugify(factionId) or nil
            local currentState = normalizedFactionId and state.factions and state.factions[normalizedFactionId] or nil
            local strengthDelta = tonumber(update.strengthDelta or update.powerDelta or update.influenceDelta)
            local heatDelta = tonumber(update.heatDelta or update.alertDelta or update.threatDelta)
            factionUpdateOptions[#factionUpdateOptions + 1] = {
                factionId = normalizedFactionId,
                update = update,
                currentState = currentState,
                strengthDelta = strengthDelta,
                projectedStrength = strengthDelta and ((currentState and tonumber(currentState.strength) or 0) + strengthDelta) or nil,
                heatDelta = heatDelta,
                projectedHeat = heatDelta and ((currentState and tonumber(currentState.heat) or 0) + heatDelta) or nil,
            }
        end
    end

    local disabled = request.underworldRestocked == true or opts.underworldRestocked == true
    return {
        step = M.STEPS.RESTOCK_UNDERWORLD,
        consumedMeatgrinder = consumedMeatgrinder,
        consumedCityEvents = consumedCityEvents,
        consumedSignsAndPortents = consumedSignsAndPortents,
        meatgrinderReplacementOptions = previewTableReplacements(
            request.meatgrinderTable or opts.meatgrinderTable,
            meatgrinderReplacementInput
        ),
        cityEventReplacementOptions = previewTableReplacements(
            request.cityEventsTable or opts.cityEventsTable,
            cityEventReplacementInput
        ),
        signsAndPortentsReplacementOptions = previewTableReplacements(
            request.signsAndPortentsTable or opts.signsAndPortentsTable,
            signReplacementInput
        ),
        generatedReplacements = generatedReplacements,
        mapUpdates = mapUpdates,
        factionUpdates = factionUpdates,
        mapUpdateOptions = mapUpdateOptions,
        factionUpdateOptions = factionUpdateOptions,
        mapsReviewed = request.mapsReviewed ~= false and opts.mapsReviewed ~= false,
        notes = request.notes or request.restockNotes or opts.notes or opts.restockNotes,
        disabled = disabled,
        unavailableReason = disabled and "Underworld already restocked" or nil,
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

local appendActorRecord

local function cityEventActorOption(source, actor, index)
    if source == nil then
        return nil, false
    end
    if type(source) ~= "table" then
        return source, true
    end

    local id = actorId(actor)
    if id and source[id] ~= nil then
        return source[id], true
    end
    if source[index] ~= nil then
        return source[index], true
    end

    for _, entry in ipairs(source) do
        if entry == actor then
            return true, true
        end
        if id and tostring(entry) == tostring(id) then
            return true, true
        end
        if type(entry) == "table" then
            local entryId = entry.actorId or entry.actor_id or entry.id or actorId(entry.actor)
            if id and tostring(entryId or "") == tostring(id) then
                return entry, true
            end
        end
    end

    return nil, false
end

local function positiveFlag(value)
    if type(value) == "boolean" then
        return value
    end
    if type(value) == "number" then
        return value ~= 0
    end

    local normalized = tostring(value or ""):lower():gsub("%s+", "_")
    if normalized == "true" or normalized == "yes" or normalized == "success" or
       normalized == "succeeded" or normalized == "pass" or normalized == "passed" then
        return true
    end
    if normalized == "false" or normalized == "no" or normalized == "failure" or
       normalized == "failed" or normalized == "fail" or normalized == "lose" or
       normalized == "lost" then
        return false
    end

    return value ~= nil
end

local function coerceFireEscapeFailure(value, booleanTrueMeansFailure)
    if value == nil then
        return nil
    end
    if type(value) == "table" then
        if value.failed ~= nil then
            return positiveFlag(value.failed)
        end
        if value.failure ~= nil then
            return positiveFlag(value.failure)
        end
        if value.success ~= nil then
            return not positiveFlag(value.success)
        end
        if value.passed ~= nil then
            return not positiveFlag(value.passed)
        end
        if value.result ~= nil then
            return coerceFireEscapeFailure(value.result, booleanTrueMeansFailure)
        end
        if value.outcome ~= nil then
            return coerceFireEscapeFailure(value.outcome, booleanTrueMeansFailure)
        end
        return true
    end
    if type(value) == "boolean" then
        return booleanTrueMeansFailure and value or not value
    end
    if type(value) == "number" then
        return booleanTrueMeansFailure and value ~= 0 or value == 0
    end

    local normalized = tostring(value or ""):lower():gsub("%s+", "_")
    if normalized == "failure" or normalized == "failed" or normalized == "fail" or
       normalized == "lose" or normalized == "lost" then
        return true
    end
    if normalized == "success" or normalized == "succeeded" or normalized == "pass" or
       normalized == "passed" then
        return false
    end
    if normalized == "true" or normalized == "yes" then
        return booleanTrueMeansFailure
    end
    if normalized == "false" or normalized == "no" then
        return not booleanTrueMeansFailure
    end

    return booleanTrueMeansFailure
end

local function fireEscapeFailureForActor(actor, opts, index)
    opts = opts or {}
    local failures = firstProvided(
        opts.fireEscapeFailures,
        opts.fireFailures,
        opts.failedFireEscapeActors,
        opts.cityEventFailures
    )
    if failures ~= nil then
        local value, found = cityEventActorOption(failures, actor, index)
        if not found then
            return false
        end
        return coerceFireEscapeFailure(value, true)
    end

    local outcomes = firstProvided(
        opts.fireEscapeResults,
        opts.fireEscapeOutcomes,
        opts.cityEventTestResults,
        opts.cityEventTests,
        opts.pentaclesTestResults,
        opts.testResults
    )
    if outcomes ~= nil then
        local value, found = cityEventActorOption(outcomes, actor, index)
        if not found then
            return nil
        end
        return coerceFireEscapeFailure(value, false)
    end

    local single = firstProvided(opts.fireEscapeFailed, opts.cityEventTestFailed)
    if single ~= nil then
        return coerceFireEscapeFailure(single, true)
    end

    return nil
end

local function taxEvasionRequestForActor(actor, opts, index)
    opts = opts or {}
    local request = indexedOpt(firstProvided(
        opts.taxEvasion,
        opts.taxEvasions,
        opts.smuggling,
        opts.smugglingAttempts,
        opts.hiddenAssets
    ), index, actor)
    if type(request) ~= "table" then
        request = request ~= nil and { hiddenGold = request } or {}
    end

    local hiddenGold = firstProvided(
        request.hiddenGold,
        request.smuggledGold,
        request.concealedGold,
        indexedOpt(opts.hiddenGold, index, actor),
        indexedOpt(opts.smuggledGold, index, actor),
        indexedOpt(opts.concealedGold, index, actor)
    )
    local bribeGold = firstProvided(
        request.bribeGold,
        request.bribe,
        indexedOpt(opts.bribeGold, index, actor),
        indexedOpt(opts.bribes, index, actor)
    )

    local detected = firstProvided(request.detected, request.caught, request.failed)
    local success = firstProvided(request.success, request.succeeded)
    if detected == nil and success ~= nil then
        detected = not positiveFlag(success)
    elseif detected ~= nil then
        detected = positiveFlag(detected)
    else
        detected = false
    end

    local bribeAccepted = firstProvided(request.bribeAccepted, request.accepted, request.bribeSucceeded)
    if bribeAccepted ~= nil then
        bribeAccepted = positiveFlag(bribeAccepted)
    else
        bribeAccepted = not detected
    end

    return {
        hiddenGold = math.max(0, math.floor(tonumber(hiddenGold) or 0)),
        bribeGold = math.max(0, math.floor(tonumber(bribeGold) or 0)),
        detected = detected,
        bribeAccepted = bribeAccepted,
        method = request.method or request.type or request.scheme,
        notes = request.notes or request.note,
    }
end

local function collectDeathAndTaxesForActor(actor, rate, opts, index)
    local evasion = taxEvasionRequestForActor(actor, opts, index)
    local startingGold = currency.getGold(actor)
    local hiddenGold = math.min(startingGold, evasion.hiddenGold or 0)
    local taxableGold = evasion.detected and startingGold or math.max(0, startingGold - hiddenGold)
    local taxPaid = math.floor(taxableGold * rate)
    local bribePaid = 0

    if evasion.bribeGold > 0 and evasion.bribeAccepted then
        if not currency.spendGold(actor, evasion.bribeGold) then
            return false, "Not enough gold"
        end
        bribePaid = evasion.bribeGold
    end
    if taxPaid > 0 and not currency.spendGold(actor, taxPaid) then
        return false, "Not enough gold"
    end

    local consequence = nil
    if evasion.detected then
        consequence = {
            id = "tax_evasion_detected",
            authority = "All-Watch",
            hiddenGold = hiddenGold,
            method = evasion.method,
            notes = evasion.notes,
        }
        appendActorRecord(actor, "legalTroubles", consequence)
    elseif hiddenGold > 0 or evasion.bribeGold > 0 then
        consequence = {
            id = hiddenGold > 0 and "tax_evasion_success" or "bribe_paid",
            authority = "All-Watch",
            hiddenGold = hiddenGold,
            bribePaid = bribePaid,
            method = evasion.method,
            notes = evasion.notes,
        }
        appendActorRecord(actor, "taxEvasions", consequence)
    end

    return true, {
        actor = actor,
        startingGold = startingGold,
        taxableGold = taxableGold,
        hiddenGold = hiddenGold,
        taxPaid = taxPaid,
        bribePaid = bribePaid,
        remainingGold = currency.getGold(actor),
        rate = rate,
        evasion = hiddenGold > 0 or evasion.bribeGold > 0 or evasion.detected,
        evasionDetected = evasion.detected,
        bribeAccepted = evasion.bribeAccepted,
        consequence = consequence,
    }
end

function M.getDeathAndTaxesOptions(opts)
    opts = opts or {}
    local request = opts.request or opts.taxes or opts.deathAndTaxes or opts
    local guild = request.guild or opts.guild
    if not guild and request.actor then
        guild = { request.actor }
    end
    guild = guild or {}
    local rate = M.TAX_RATE
    local details = {}
    local totalTax = 0
    local totalBribes = 0
    local disabled = request.taxesResolved == true or opts.taxesResolved == true
    local unavailableReason = disabled and "Death and taxes already resolved" or nil

    for index, actor in ipairs(guild) do
        local evasion = taxEvasionRequestForActor(actor, request, index)
        local startingGold = currency.getGold(actor)
        local hiddenGold = math.min(startingGold, evasion.hiddenGold or 0)
        local taxableGold = evasion.detected and startingGold or math.max(0, startingGold - hiddenGold)
        local taxPaid = math.floor(taxableGold * rate)
        local bribePaid = evasion.bribeGold > 0 and evasion.bribeAccepted and evasion.bribeGold or 0
        local totalDue = taxPaid + bribePaid
        local actorDisabled = totalDue > startingGold
        if actorDisabled and not disabled then
            disabled = true
            unavailableReason = "Not enough gold"
        end

        local liquidItemOptions = {}
        local exemptTreasureOptions = {}
        local inv = actor and actor.inventory
        if inv and inv.getAllItems then
            for _, entry in ipairs(inv:getAllItems()) do
                local item = entry.item
                local props = item and item.properties or {}
                if currency.isCurrencyItem(item) then
                    liquidItemOptions[#liquidItemOptions + 1] = {
                        id = item.id,
                        itemId = item.id,
                        item = item,
                        name = item.name,
                        location = entry.location,
                        quantity = item.quantity or 1,
                        valueEach = tonumber(props.value) or 0,
                        totalGold = (item.quantity or 1) * (tonumber(props.value) or 0),
                    }
                else
                    local treasure = item and currency.isCurrencyItem(item) ~= true and (
                        props.treasure == true or
                        props.jewelry == true or
                        props.art == true or
                        props.extravagance == true or
                        props.saleValue ~= nil or
                        props.value ~= nil
                    )
                    if treasure then
                        exemptTreasureOptions[#exemptTreasureOptions + 1] = {
                            id = item.id,
                            itemId = item.id,
                            item = item,
                            name = item.name,
                            location = entry.location,
                            saleValue = math.max(0, math.floor(tonumber(props.saleValue or props.value) or 0)),
                            reason = "non_liquid_treasure",
                        }
                    end
                end
            end
        end

        local consequencePreview = nil
        if evasion.detected then
            consequencePreview = {
                id = "tax_evasion_detected",
                authority = "All-Watch",
                hiddenGold = hiddenGold,
                method = evasion.method,
                notes = evasion.notes,
            }
        elseif hiddenGold > 0 or evasion.bribeGold > 0 then
            consequencePreview = {
                id = hiddenGold > 0 and "tax_evasion_success" or "bribe_paid",
                authority = "All-Watch",
                hiddenGold = hiddenGold,
                bribePaid = bribePaid,
                method = evasion.method,
                notes = evasion.notes,
            }
        end

        details[#details + 1] = {
            actor = actor,
            actorId = actorId(actor),
            name = actor and actor.name or actorId(actor),
            purseGold = tonumber(actor and actor.gold) or 0,
            carriedLiquidGold = currency.getCarriedGold(actor),
            startingGold = startingGold,
            rate = rate,
            taxableGold = taxableGold,
            hiddenGold = hiddenGold,
            taxPaid = taxPaid,
            bribeGold = evasion.bribeGold,
            bribePaid = bribePaid,
            bribeAccepted = evasion.bribeAccepted,
            evasion = hiddenGold > 0 or evasion.bribeGold > 0 or evasion.detected,
            evasionDetected = evasion.detected,
            method = evasion.method,
            notes = evasion.notes,
            projectedRemainingGold = math.max(0, startingGold - totalDue),
            liquidItemOptions = liquidItemOptions,
            exemptTreasureOptions = exemptTreasureOptions,
            consequencePreview = consequencePreview,
            disabled = actorDisabled,
            unavailableReason = actorDisabled and "Not enough gold" or nil,
        }
        totalTax = totalTax + taxPaid
        totalBribes = totalBribes + bribePaid
    end

    return {
        step = M.STEPS.DEATH_AND_TAXES,
        rate = rate,
        requestedRate = request.taxRate or opts.taxRate,
        details = details,
        totalTax = totalTax,
        totalBribes = totalBribes,
        totalDue = totalTax + totalBribes,
        disabled = disabled,
        unavailableReason = unavailableReason,
    }
end

local function removeBottomPackItems(actor, count)
    local removed = {}
    local inv = actor and actor.inventory
    local pack = inv and inv.getItems and inv:getItems(inventory.LOCATIONS.PACK) or inv and inv.pack
    if type(pack) ~= "table" then
        return removed
    end

    for _ = 1, math.max(0, math.floor(tonumber(count) or 0)) do
        local index = #pack
        if index <= 0 then
            break
        end
        local item = table.remove(pack, index)
        removed[#removed + 1] = {
            actor = actor,
            item = item,
            location = inventory.LOCATIONS.PACK,
            index = index,
        }
    end

    return removed
end

local function cityEventEntryFromDetail(detail)
    if type(detail) ~= "table" then
        return nil
    end
    return detail.event or detail
end

local function isDisasterFireCityEvent(eventEntry)
    if type(eventEntry) ~= "table" then
        return false
    end
    return tonumber(eventEntry.value) == 20 or tostring(eventEntry.title or ""):lower() == "a disaster: fire"
end

local function resolveFireCityEventConsequences(controller, opts)
    opts = opts or {}
    local cityEventDetail = opts.cityEventDetail or opts.cityEvent or controller.lastCityEvent
    local eventEntry = opts.eventEntry or opts.event or cityEventEntryFromDetail(cityEventDetail)
    if not isDisasterFireCityEvent(eventEntry) then
        return nil, false
    end

    local effects = opts.cityEventEffects or opts.effects or
        (type(cityEventDetail) == "table" and cityEventDetail.effects) or
        (eventEntry and eventEntry.effects) or controller.cityEventEffects or {}
    local participants = normalizeRecipientList(opts.participants or opts.actors or opts.guild or controller.guild)
    if #participants == 0 then
        participants = activeAdventurers(controller.guild)
    end

    local detail = {
        event = eventEntry,
        timing = effects.timing or "after_city_actions",
        testSuit = effects.testSuit or "pentacles",
        failedActors = {},
        successfulActors = {},
        pendingActors = {},
        lostItems = {},
        stressedActors = {},
        consequences = {},
        complete = false,
        result = "city_event_fire_pending",
    }
    local outcomes = {}

    for index, actor in ipairs(participants) do
        if isActiveAdventurer(actor) then
            local failed = fireEscapeFailureForActor(actor, opts, index)
            if failed == nil then
                detail.pendingActors[#detail.pendingActors + 1] = {
                    actor = actor,
                    testSuit = detail.testSuit,
                    reason = "test_outcome_required",
                }
            else
                outcomes[#outcomes + 1] = {
                    actor = actor,
                    failed = failed,
                }
            end
        end
    end

    if #detail.pendingActors > 0 then
        return detail, false
    end

    for _, outcome in ipairs(outcomes) do
        local actor = outcome.actor
        if outcome.failed then
            actor.conditions = actor.conditions or {}
            actor.conditions.stressed = true
            actor.nextCrawlConditions = actor.nextCrawlConditions or {}
            actor.nextCrawlConditions.stressed = true

            local lostItems = removeBottomPackItems(actor, 2)
            for _, lost in ipairs(lostItems) do
                detail.lostItems[#detail.lostItems + 1] = lost
            end
            detail.failedActors[#detail.failedActors + 1] = actor
            detail.stressedActors[#detail.stressedActors + 1] = actor
            detail.consequences[#detail.consequences + 1] = {
                actor = actor,
                outcome = "failed",
                condition = "stressed",
                nextCrawlCondition = "stressed",
                lostItems = lostItems,
            }
        else
            detail.successfulActors[#detail.successfulActors + 1] = actor
            detail.consequences[#detail.consequences + 1] = {
                actor = actor,
                outcome = "succeeded",
                lostItems = {},
            }
        end
    end

    detail.complete = true
    detail.result = "city_event_fire_resolved"
    return detail, true
end

local function resolveNextCrawlConditionCityEventConsequences(controller, opts)
    opts = opts or {}
    local cityEventDetail = opts.cityEventDetail or opts.cityEvent or controller.lastCityEvent
    local eventEntry = opts.eventEntry or opts.event or cityEventEntryFromDetail(cityEventDetail)
    local effects = opts.cityEventEffects or opts.effects or
        (type(cityEventDetail) == "table" and cityEventDetail.effects) or
        (eventEntry and eventEntry.effects) or controller.cityEventEffects or {}
    local condition = effects.nextCrawlCondition or effects.nextCrawl_condition
    if not condition then
        return nil, false
    end

    local conditionId = tostring(condition):lower():gsub("%s+", "_")
    local participants = normalizeRecipientList(opts.participants or opts.actors or opts.guild or controller.guild)
    if #participants == 0 then
        participants = activeAdventurers(controller.guild)
    end

    local detail = {
        event = eventEntry,
        sign = type(cityEventDetail) == "table" and cityEventDetail.sign or nil,
        condition = conditionId,
        affectedActors = {},
        consequences = {},
        complete = true,
        result = "city_event_next_crawl_condition_resolved",
    }

    for _, actor in ipairs(participants) do
        if isActiveAdventurer(actor) then
            actor.nextCrawlConditions = actor.nextCrawlConditions or {}
            actor.nextCrawlConditions[conditionId] = true
            if conditionId == "stressed" then
                actor.conditions = actor.conditions or {}
                actor.conditions.stressed = true
            end

            detail.affectedActors[#detail.affectedActors + 1] = actor
            detail.consequences[#detail.consequences + 1] = {
                actor = actor,
                condition = conditionId,
                nextCrawlCondition = conditionId,
            }
        end
    end

    return detail, true
end

local function dreamSecretsOmenFromDetail(cityEventDetail, effects)
    local sign = type(cityEventDetail) == "table" and cityEventDetail.sign or nil
    local omen = effects and (effects.cityOmen or effects.city_omen) or nil
    if type(omen) == "table" and (omen.requiresPlayerSecrets or omen.id == "wandering_dreams") then
        return omen
    end
    if type(sign) == "table" and (tonumber(sign.value) == 6 or sign.title == "Dreams") then
        return sign.effects and (sign.effects.cityOmen or sign.effects.city_omen) or { id = "wandering_dreams" }
    end
    return nil
end

local function fallbackDreamSecretRecipient(actors, teller, index)
    if #actors < 2 then
        return nil
    end
    for offset = 1, #actors - 1 do
        local candidate = actors[((index - 1 + offset) % #actors) + 1]
        if candidate ~= teller and isActiveAdventurer(candidate) then
            return candidate
        end
    end
    return nil
end

local function resolveDreamActorReference(ref, actors)
    if not ref then
        return nil
    end
    if actorId(ref) then
        return ref
    end
    if type(ref) == "table" and ref.actor then
        return resolveDreamActorReference(ref.actor, actors)
    end

    local wanted = tostring(ref)
    for _, actor in ipairs(actors or {}) do
        if tostring(actorId(actor) or "") == wanted then
            return actor
        end
    end
    return nil
end

local function indexedDreamSecretEntry(secrets, actor, index, actors)
    if type(secrets) ~= "table" then
        return nil
    end

    local id = actorId(actor)
    if id and secrets[id] ~= nil then
        return secrets[id]
    end
    if secrets[index] ~= nil then
        local entry = secrets[index]
        if type(entry) ~= "table" then
            return entry
        end
        local fromRef = entry.teller or entry.fromActor or entry.from or entry.actor or entry.player or entry[1]
        if fromRef == nil or resolveDreamActorReference(fromRef, actors) == actor or tostring(fromRef) == tostring(id) then
            return entry
        end
    end

    for _, entry in ipairs(secrets) do
        if type(entry) == "table" then
            local fromRef = entry.teller or entry.fromActor or entry.from or entry.actor or entry.player or entry[1]
            if resolveDreamActorReference(fromRef, actors) == actor or tostring(fromRef or "") == tostring(id) then
                return entry
            end
        end
    end

    return nil
end

local function normalizeDreamSecretEntry(entry, teller, index, actors)
    if entry == nil then
        return nil, nil, "secret_required"
    end

    local secret = nil
    local recipientRef = nil
    if type(entry) == "table" then
        secret = entry.secret or entry.text or entry.note or entry[3]
        recipientRef = entry.dreamer or entry.recipient or entry.toActor or entry.to or entry.targetActor or
            entry.target or entry[2]
        if secret == nil and type(entry[1]) == "string" and recipientRef == nil then
            secret = entry[1]
        end
    else
        secret = entry
    end

    secret = tostring(secret or "")
    if secret == "" then
        return nil, nil, "secret_required"
    end

    local recipient = resolveDreamActorReference(recipientRef, actors) or fallbackDreamSecretRecipient(actors, teller, index)
    if not recipient or recipient == teller then
        return nil, nil, "another_dreamer_required"
    end

    return secret, recipient, nil
end

local function resolveDreamSecretsCityEventConsequences(controller, opts)
    opts = opts or {}
    local cityEventDetail = opts.cityEventDetail or opts.cityEvent or controller.lastCityEvent
    local eventEntry = opts.eventEntry or opts.event or cityEventEntryFromDetail(cityEventDetail)
    local effects = opts.cityEventEffects or opts.effects or
        (type(cityEventDetail) == "table" and cityEventDetail.effects) or
        (eventEntry and eventEntry.effects) or controller.cityEventEffects or {}
    local omen = dreamSecretsOmenFromDetail(cityEventDetail, effects)
    if type(omen) ~= "table" then
        return nil, false
    end

    local actors = activeAdventurers(opts.guild or controller.guild)
    local secrets = opts.dreamSecrets or opts.secrets or opts.playerSecrets or opts.secretExchange
    local cityState = opts.cityState or opts.worldState or controller.cityState
    local detail = {
        event = eventEntry,
        sign = type(cityEventDetail) == "table" and cityEventDetail.sign or nil,
        omen = omen,
        exchanges = {},
        pendingActors = {},
        complete = false,
        result = "city_event_dream_secrets_pending",
    }

    for index, actor in ipairs(actors) do
        local entry = indexedDreamSecretEntry(secrets, actor, index, actors)
        local secret, recipient, reason = normalizeDreamSecretEntry(entry, actor, index, actors)
        if not secret then
            detail.pendingActors[#detail.pendingActors + 1] = {
                actor = actor,
                actorId = actorId(actor),
                reason = reason,
            }
        else
            detail.exchanges[#detail.exchanges + 1] = {
                teller = actor,
                tellerId = actorId(actor),
                dreamer = recipient,
                dreamerId = actorId(recipient),
                secret = secret,
            }
        end
    end

    if #detail.pendingActors > 0 then
        cityState.pendingDreamSecrets = #detail.pendingActors
        return detail, false
    end

    cityState.pendingDreamSecrets = 0
    cityState.dreamSecrets = cityState.dreamSecrets or {}
    for _, exchange in ipairs(detail.exchanges) do
        local record = {
            id = "wandering_dream",
            source = "signs_dreams",
            eventValue = eventEntry and eventEntry.value,
            eventTitle = eventEntry and eventEntry.title,
            signValue = detail.sign and detail.sign.value,
            signTitle = detail.sign and detail.sign.title,
            tellerId = exchange.tellerId,
            dreamerId = exchange.dreamerId,
            secret = exchange.secret,
        }
        appendActorRecord(exchange.teller, "cityDreamSecretsTold", record)
        appendActorRecord(exchange.dreamer, "cityDreamSecrets", record)
        cityState.dreamSecrets[#cityState.dreamSecrets + 1] = record
        exchange.record = record
    end

    detail.complete = true
    detail.result = "city_event_dream_secrets_resolved"
    return detail, true
end

function M._citySuccessionEffectFromDetail(cityEventDetail, effects)
    local succession = effects and (effects.citySuccession or effects.city_succession) or nil
    if type(succession) == "table" then
        return succession
    end
    local eventEntry = cityEventEntryFromDetail(cityEventDetail)
    if eventEntry and tonumber(eventEntry.value) == 10 then
        return {
            id = "king_is_dead",
            source = "city_event_king_is_dead",
            recordField = "citySuccessions",
        }
    end
    return nil
end

function M._normalizeCityRulerRecord(value)
    if value == nil then
        return nil
    end
    if type(value) == "table" then
        local record = shallowClone(value)
        record.name = record.name or record.ruler or record.title or record.id
        return record
    end
    local name = tostring(value or "")
    if name == "" then
        return nil
    end
    return {
        name = name,
    }
end

function M._citySuccessionRulerFromOpts(opts)
    return M._normalizeCityRulerRecord(firstProvided(
        opts.newRuler,
        opts.new_ruler,
        opts.successor,
        opts.ruler,
        opts.currentRuler,
        opts.current_ruler,
        opts.throneHolder,
        opts.regime
    ))
end

function M._citySuccessionGoneReason(opts, effect)
    return firstProvided(
        opts.oldRulerGoneReason,
        opts.goneReason,
        opts.rulerGoneReason,
        opts.successionReason,
        opts.regimeChange,
        effect and effect.goneReason
    )
end

function M._markCitySuccessionPending(controller, eventEntry, sign, effect, opts)
    opts = opts or {}
    local cityState = opts.cityState or opts.worldState or controller.cityState
    local oldRuler = M._normalizeCityRulerRecord(firstProvided(
        opts.oldRuler,
        opts.previousRuler,
        cityState.currentRuler,
        cityState.ruler
    ))
    local pending = {
        id = effect.id or "king_is_dead",
        source = effect.source or "city_event_king_is_dead",
        eventValue = eventEntry and eventEntry.value,
        eventTitle = eventEntry and eventEntry.title,
        signValue = sign and sign.value,
        signTitle = sign and sign.title,
        oldRuler = oldRuler,
        goneReason = M._citySuccessionGoneReason(opts, effect),
        status = "pending",
    }
    cityState.pendingSuccession = pending
    cityState.pendingCitySuccession = pending
    return pending, cityState
end

function M._markCityUndeadPlague(controller, eventEntry, sign, effect, opts)
    opts = opts or {}
    local cityState = opts.cityState or opts.worldState or controller.cityState
    local record = {
        id = effect.id or "what_is_dead_may_never_die",
        source = effect.source or "signs_what_is_dead_may_never_die",
        eventValue = eventEntry and eventEntry.value,
        eventTitle = eventEntry and eventEntry.title,
        signValue = sign and sign.value,
        signTitle = sign and sign.title,
        blocksCityActions = effect.blocksCityActions ~= false,
        sourceRequired = effect.sourceRequired ~= false,
        underworldSource = opts.undeadSource or opts.source or effect.underworldSource,
        active = true,
        status = "active",
    }
    cityState.undeadPlague = record
    cityState.cityActionsBlockedByUndead = record.blocksCityActions
    cityState.cityUndeadPlagues = cityState.cityUndeadPlagues or {}
    cityState.cityUndeadPlagues[#cityState.cityUndeadPlagues + 1] = record
    return record, cityState
end

local function resolveCitySuccessionCityEventConsequences(controller, opts)
    opts = opts or {}
    local cityEventDetail = opts.cityEventDetail or opts.cityEvent or controller.lastCityEvent
    local eventEntry = opts.eventEntry or opts.event or cityEventEntryFromDetail(cityEventDetail)
    local effects = opts.cityEventEffects or opts.effects or
        (type(cityEventDetail) == "table" and cityEventDetail.effects) or
        (eventEntry and eventEntry.effects) or controller.cityEventEffects or {}
    local effect = M._citySuccessionEffectFromDetail(cityEventDetail, effects)
    if type(effect) ~= "table" then
        return nil, false
    end

    local cityState = opts.cityState or opts.worldState or controller.cityState
    local pending = cityState.pendingSuccession or cityState.pendingCitySuccession
    if not pending then
        pending = M._markCitySuccessionPending(controller, eventEntry, type(cityEventDetail) == "table" and
            cityEventDetail.sign or nil, effect, opts)
    end

    local newRuler = M._citySuccessionRulerFromOpts(opts)
    if not newRuler then
        return {
            event = eventEntry,
            effect = effect,
            pending = pending,
            cityState = cityState,
            complete = false,
            reason = "new_ruler_required",
            result = "city_event_succession_pending",
        }, false
    end

    local record = shallowClone(pending)
    record.newRuler = newRuler
    record.currentRuler = newRuler
    record.status = "resolved"
    record.resolved = true
    record.goneReason = M._citySuccessionGoneReason(opts, effect) or record.goneReason
    record.regimeNotes = opts.regimeNotes or opts.notes or opts.note

    cityState.previousRuler = record.oldRuler
    cityState.currentRuler = newRuler
    cityState.ruler = newRuler
    cityState.citySuccessions = cityState.citySuccessions or {}
    cityState.citySuccessions[#cityState.citySuccessions + 1] = record
    cityState.lastCitySuccession = record
    cityState.pendingSuccession = nil
    cityState.pendingCitySuccession = nil

    return {
        event = eventEntry,
        effect = effect,
        oldRuler = record.oldRuler,
        newRuler = newRuler,
        record = record,
        cityState = cityState,
        complete = true,
        result = "city_event_succession_resolved",
    }, true
end

local function suitScore(actor, suit)
    suit = tostring(suit or ""):lower()
    if suit == "swords" then
        return getSwords(actor)
    elseif suit == "pentacles" or suit == "disks" then
        return getPentacles(actor)
    elseif suit == "cups" then
        return getCups(actor)
    elseif suit == "wands" or suit == "batons" then
        return getWands(actor)
    end
    return 0
end

local pathSuitByName = {
    swords = constants.SUITS.SWORDS,
    pentacles = constants.SUITS.PENTACLES,
    disks = constants.SUITS.PENTACLES,
    cups = constants.SUITS.CUPS,
    wands = constants.SUITS.WANDS,
    batons = constants.SUITS.WANDS,
}

local function actorPathSuit(actor)
    if not actor then
        return nil
    end
    if actor.pathSuit or actor.path_suit then
        return actor.pathSuit or actor.path_suit
    end
    local path = actor.path or actor.pathName or actor.suit
    if type(path) == "string" then
        path = path:lower():gsub("^path of ", "")
        return pathSuitByName[path]
    end
    return nil
end

local function selectRandomAdventurerFromMinorDiscard(actors, card)
    local candidates = {}
    local active = {}
    for _, actor in ipairs(actors or {}) do
        if isActiveAdventurer(actor) then
            active[#active + 1] = actor
            if card and actorPathSuit(actor) == card.suit then
                candidates[#candidates + 1] = actor
            end
        end
    end

    if #candidates == 0 then
        candidates = active
    end
    if #candidates == 0 then
        return nil
    end
    if #candidates == 1 then
        return candidates[1]
    end
    return candidates[(tonumber(card and card.value) or 1) % 2 == 1 and 1 or #candidates]
end

local function resolveActorReference(ref, actors)
    if not ref then
        return nil
    end
    if actorId(ref) then
        return ref
    end
    if type(ref) == "table" and ref.actor then
        return resolveActorReference(ref.actor, actors)
    end

    local wanted = tostring(ref)
    for _, actor in ipairs(actors or {}) do
        if tostring(actorId(actor) or "") == wanted then
            return actor
        end
    end
    return nil
end

local function lastActiveInOrder(order, actors)
    local fallback = nil
    for _, actor in ipairs(actors or {}) do
        if isActiveAdventurer(actor) then
            fallback = actor
        end
    end

    if type(order) ~= "table" then
        return fallback
    end

    local selected = nil
    for _, ref in ipairs(order) do
        local actor = resolveActorReference(ref, actors)
        if isActiveAdventurer(actor) then
            selected = actor
        end
    end
    return selected or fallback
end

local function selectSuitTarget(actors, suit, mode)
    local selected = nil
    local selectedScore = nil
    for _, actor in ipairs(actors or {}) do
        if isActiveAdventurer(actor) then
            local score = suitScore(actor, suit)
            if not selected or (mode == "lowest" and score < selectedScore) or
               (mode ~= "lowest" and score > selectedScore) then
                selected = actor
                selectedScore = score
            end
        end
    end
    return selected, selectedScore
end

local function selectTravelCityEventTarget(travelEvent, actors, opts)
    opts = opts or {}
    local explicit = opts.travelEventTarget or opts.cityEventTarget or opts.targetActor or opts.target
    local actor = resolveActorReference(explicit, actors)
    if actor then
        return actor, {
            targetRule = "explicit",
        }
    end

    local targetRule = travelEvent and travelEvent.target
    if targetRule == "back_rank" then
        return lastActiveInOrder(opts.marchingOrder or opts.marching_order or opts.travelOrder, actors), {
            targetRule = targetRule,
        }
    elseif targetRule == "highest_suit" then
        local selected, score = selectSuitTarget(actors, travelEvent.suit, "highest")
        return selected, {
            targetRule = targetRule,
            suit = travelEvent.suit,
            suitValue = score,
        }
    elseif targetRule == "lowest_suit" then
        local selected, score = selectSuitTarget(actors, travelEvent.suit, "lowest")
        return selected, {
            targetRule = targetRule,
            suit = travelEvent.suit,
            suitValue = score,
        }
    end

    return actors and actors[1] or nil, {
        targetRule = targetRule or "first_active",
    }
end

local function recordTravelCityEvent(actor, record)
    if not actor then
        return
    end
    actor.cityTravelEvents = actor.cityTravelEvents or {}
    actor.cityTravelEvents[#actor.cityTravelEvents + 1] = record
end

local function applyTravelCityEventProperty(actor, property, record)
    if not actor or type(property) ~= "table" then
        return nil
    end

    local propertyRecord = {}
    for key, value in pairs(property) do
        propertyRecord[key] = value
    end
    propertyRecord.sourceCityEvent = record

    actor.cityProperties = actor.cityProperties or {}
    actor.cityProperties[propertyRecord.id or propertyRecord.name or ("city_property_" .. tostring(#actor.cityProperties + 1))] =
        propertyRecord
    return propertyRecord
end

local function resolveTravelCityEventConsequences(controller, opts)
    opts = opts or {}
    local cityEventDetail = opts.cityEventDetail or opts.cityEvent or controller.lastCityEvent
    local eventEntry = opts.eventEntry or opts.event or cityEventEntryFromDetail(cityEventDetail)
    local effects = opts.cityEventEffects or opts.effects or
        (type(cityEventDetail) == "table" and cityEventDetail.effects) or
        (eventEntry and eventEntry.effects) or controller.cityEventEffects or {}
    local travelEvent = effects.travelEvent or effects.travel_event
    if type(travelEvent) ~= "table" or eventEntry and eventEntry.category ~= city_events.CATEGORIES.TRAVEL_EVENT then
        return nil, false
    end

    local actors = normalizeRecipientList(opts.participants or opts.actors or opts.guild or controller.guild)
    if #actors == 0 then
        actors = activeAdventurers(controller.guild)
    end

    local target, targetDetail = selectTravelCityEventTarget(travelEvent, actors, opts)
    if not target then
        return {
            event = eventEntry,
            consequence = travelEvent.consequence,
            targetRule = targetDetail and targetDetail.targetRule,
            complete = false,
            result = "city_event_travel_pending",
            reason = "target_required",
        }, false
    end

    local record = {
        id = travelEvent.consequence or ("city_event_" .. tostring(eventEntry and eventEntry.value or "travel")),
        eventValue = eventEntry and eventEntry.value,
        eventTitle = eventEntry and eventEntry.title,
        category = city_events.CATEGORIES.TRAVEL_EVENT,
        targetRule = targetDetail.targetRule,
        suit = targetDetail.suit,
        suitValue = targetDetail.suitValue,
        status = "pending",
    }
    recordTravelCityEvent(target, record)

    local property = applyTravelCityEventProperty(target, travelEvent.property, record)
    local detail = {
        event = eventEntry,
        target = target,
        targetRule = targetDetail.targetRule,
        suit = targetDetail.suit,
        suitValue = targetDetail.suitValue,
        consequence = travelEvent.consequence,
        record = record,
        property = property,
        complete = true,
        result = "city_event_travel_resolved",
    }

    return detail, true
end

local function resolvePendingCityEventConsequences(controller, opts)
    local detail, complete = resolveFireCityEventConsequences(controller, opts)
    if detail then
        return detail, complete
    end
    detail, complete = resolveNextCrawlConditionCityEventConsequences(controller, opts)
    if detail then
        return detail, complete
    end
    detail, complete = resolveDreamSecretsCityEventConsequences(controller, opts)
    if detail then
        return detail, complete
    end
    detail, complete = resolveCitySuccessionCityEventConsequences(controller, opts)
    if detail then
        return detail, complete
    end
    return resolveTravelCityEventConsequences(controller, opts)
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

local function saleMetadataValue(source, itemId)
    if type(source) == "table" then
        return source[itemId]
    end
    return source
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

function M.getNoteworthyDeedsOptions(opts)
    opts = opts or {}
    local request = opts.request or opts.noteworthyDeeds or opts.deedsRequest or opts
    local roster = request.guildRoster or request.roster or opts.guildRoster or opts.roster or {}
    local currentDeeds = normalizeDeedList(
        request.currentDeeds or request.activeDeeds or opts.currentDeeds or opts.activeDeeds or
            roster.noteworthyDeeds or roster.deeds
    )
    local previousFame = #currentDeeds
    local erased = nil
    if #currentDeeds > 0 then
        erased = table.remove(currentDeeds, 1)
    end

    local proposed = normalizeDeedList(
        request.deeds or request.newDeeds or request.proposedDeeds or request.accomplishments or
            request.noteworthyDeeds
    )
    local added = {}
    local rejected = {}
    local proposedOptions = {}
    for _, deed in ipairs(proposed) do
        local approved = deed.approved == true
        proposedOptions[#proposedOptions + 1] = {
            id = deed.id,
            deed = deed,
            title = deed.title,
            description = deed.description,
            approved = approved,
            selected = approved,
            disabled = not approved,
            unavailableReason = not approved and "Deed not approved" or nil,
        }
        if approved then
            currentDeeds[#currentDeeds + 1] = deed
            added[#added + 1] = deed
        else
            rejected[#rejected + 1] = deed
        end
    end

    local activeDeeds, dropped = selectActiveDeeds(currentDeeds, request)
    local fame = #activeDeeds
    local fameReaction = disposition.getFameReaction(fame, {
        reputation = request.reputation or request.deedTone or request.fameTone or roster.reputation or roster.fameTone,
        favorable = request.favorable,
    })
    local selectedSet = selectedDeedSet(request)
    local activeSet = {}
    for _, deed in ipairs(activeDeeds) do
        activeSet[deed.id] = true
    end

    local currentDeedOptions = {}
    if erased then
        currentDeedOptions[#currentDeedOptions + 1] = {
            id = erased.id,
            deed = erased,
            title = erased.title,
            description = erased.description,
            willErase = true,
            selected = false,
            disabled = true,
            unavailableReason = "Oldest deed erased",
        }
    end
    for _, deed in ipairs(currentDeeds) do
        currentDeedOptions[#currentDeedOptions + 1] = {
            id = deed.id,
            deed = deed,
            title = deed.title,
            description = deed.description,
            selected = activeSet[deed.id] == true,
            explicitlySelected = selectedSet and (selectedSet[deed.id] or selectedSet[deed.description] or selectedSet[deed.title]) or nil,
            disabled = activeSet[deed.id] ~= true,
            unavailableReason = activeSet[deed.id] ~= true and "Dropped by Fame cap" or nil,
        }
    end

    local resolved = request.noteworthyDeedsResolved == true or opts.noteworthyDeedsResolved == true
    return {
        step = M.STEPS.NOTEWORTHY_DEEDS,
        previousFame = previousFame,
        maxFame = math.max(0, math.floor(tonumber(request.maxFame) or M.MAX_FAME)),
        erased = erased,
        added = added,
        rejected = rejected,
        dropped = dropped,
        activeDeeds = activeDeeds,
        deeds = activeDeeds,
        currentDeedOptions = currentDeedOptions,
        proposedDeedOptions = proposedOptions,
        curationRequired = #currentDeeds > math.max(0, math.floor(tonumber(request.maxFame) or M.MAX_FAME)),
        selectedDeedIds = request.selectedDeedIds or request.keepDeedIds or request.selectedDeeds,
        fame = fame,
        projectedFame = fame,
        fameReaction = fameReaction,
        fameDispositionFrame = fameReaction.dispositionFrame,
        resultPreview = #added > 0 and "noteworthy_deeds_recorded" or "noteworthy_deeds_aged",
        disabled = resolved,
        unavailableReason = resolved and "Noteworthy deeds already resolved" or nil,
    }
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

local function isFoolMinorDeckCard(card)
    if type(card) ~= "table" then
        return false
    end
    local name = tostring(card.name or card.id or ""):lower()
    if name == "the fool" or name == "fool" then
        return true
    end
    local suit = card.suit
    local suitName = type(suit) == "string" and suit:lower() or nil
    return tonumber(card.value) == 0 and (card.is_major == true or suit == constants.SUITS.MAJOR or suitName == "major")
end

local function isMinorDeckCard(card)
    if type(card) ~= "table" then
        return false
    end
    if isFoolMinorDeckCard(card) then
        return true
    end

    local suit = card.suit
    if suit == constants.SUITS.SWORDS or suit == constants.SUITS.PENTACLES or
       suit == constants.SUITS.CUPS or suit == constants.SUITS.WANDS then
        return true
    end

    if type(suit) == "string" then
        local normalized = suit:lower():gsub("%s+", "_")
        return normalized == "swords" or normalized == "pentacles" or normalized == "disks" or
            normalized == "cups" or normalized == "wands" or normalized == "batons"
    end

    return false
end

local function isMajorDeckCard(card)
    if type(card) ~= "table" or isFoolMinorDeckCard(card) then
        return false
    end
    local value = tonumber(card.value)
    if not value or value < 1 or value > 21 then
        return false
    end

    local suit = card.suit
    local suitName = type(suit) == "string" and suit:lower() or nil
    return card.is_major == true or suit == constants.SUITS.MAJOR or suitName == "major"
end

local function getTopMinorDiscard(controller, opts)
    opts = opts or {}
    local minorDeck = opts.playerDeck or opts.minorDeck or controller.playerDeck
    local card = nil
    if minorDeck and minorDeck.peekDiscard then
        card = minorDeck:peekDiscard()
    end
    return card or opts.minorDiscardCard or opts.minorDiscard or
        opts.topMinorDiscardCard or opts.topMinorDiscard
end

function M.getCityEventOptions(opts)
    opts = opts or {}
    local request = opts.request or opts.cityEvent or opts.cityEvents or opts
    local explicitCard = request.majorCard or request.card
    local majorDeck = request.gmDeck or request.majorDeck or opts.gmDeck or opts.majorDeck
    local cardValid = explicitCard and isMajorDeckCard(explicitCard) or nil
    local card = cardValid and explicitCard or nil
    local disabled = false
    local unavailableReason = nil
    if request.cityEventResolved == true or opts.cityEventResolved == true then
        disabled = true
        unavailableReason = "City Event already resolved"
    elseif explicitCard and not cardValid then
        disabled = true
        unavailableReason = "Requires major arcana draw"
    elseif not explicitCard and not (majorDeck and majorDeck.draw) then
        disabled = true
        unavailableReason = "Requires major arcana draw"
    end

    local rawEventsTable = request.cityEventsTable or request.city_events_table or opts.cityEventsTable or
        city_events.DEFAULT_EVENTS
    local eventsTableMeta = request.cityEventsTableMeta or opts.cityEventsTableMeta
    local eventsTable = rawEventsTable
    if rawEventsTable ~= city_events.DEFAULT_EVENTS then
        eventsTable = M.copyCityPhaseMetadata(rawEventsTable)
        eventsTable, eventsTableMeta = city_events.normalizeEventTable(eventsTable, {
            tableName = "city_events",
            source = request.cityEventsTableSource or request.cityEventTableSource or
                request.city_events_table_source or opts.cityEventsTableSource or opts.cityEventTableSource or
                eventsTableMeta and eventsTableMeta.source,
            requireComplete = request.requireCompleteCityEventsTable == true or
                request.requireCompleteCityEventTable == true or opts.requireCompleteCityEventsTable == true or
                opts.requireCompleteCityEventTable == true or eventsTableMeta and eventsTableMeta.requireComplete == true,
        })
    elseif not eventsTableMeta then
        eventsTableMeta = {
            tableName = "city_events",
            source = "default",
            missing = {},
            invalid = {},
            count = 21,
            complete = true,
            requireComplete = false,
        }
    end
    if not disabled and eventsTableMeta and eventsTableMeta.requireComplete and not eventsTableMeta.complete then
        disabled = true
        unavailableReason = "City Event table incomplete"
    end

    local eventEntry = nil
    local eventCategory = nil
    if card and not (eventsTableMeta and eventsTableMeta.requireComplete and not eventsTableMeta.complete) then
        eventEntry = city_events.getEvent(card.value, eventsTable)
        if eventEntry then
            eventEntry = M.copyCityPhaseMetadata(eventEntry)
            eventCategory = eventEntry.category or cityEventCategoryForValue(eventEntry.value or card.value)
            eventEntry.category = eventCategory
        elseif not disabled then
            disabled = true
            unavailableReason = "City Event table entry missing"
        end
    end

    local minorDeck = request.playerDeck or request.minorDeck or opts.playerDeck or opts.minorDeck
    local minorDiscard = nil
    if minorDeck and minorDeck.peekDiscard then
        minorDiscard = minorDeck:peekDiscard()
    end
    minorDiscard = minorDiscard or request.minorDiscardCard or request.minorDiscard or
        request.topMinorDiscardCard or request.topMinorDiscard
    local minorDiscardValid = minorDiscard and isMinorDeckCard(minorDiscard) or nil
    local sign = nil
    local signsTable = request.signsAndPortentsTable or request.signsTable or opts.signsAndPortentsTable or
        opts.signsTable or city_events.SIGNS_AND_PORTENTS
    local signsTableMeta = request.signsAndPortentsTableMeta or request.signsTableMeta or
        opts.signsAndPortentsTableMeta or opts.signsTableMeta
    if eventCategory == city_events.CATEGORIES.SIGNS_AND_PORTENTS then
        if not minorDiscard or not minorDiscardValid then
            if not disabled then
                disabled = true
                unavailableReason = "Requires minor discard for Signs and Portents"
            end
        else
            if signsTable ~= city_events.SIGNS_AND_PORTENTS then
                signsTable = M.copyCityPhaseMetadata(signsTable)
                signsTable, signsTableMeta = city_events.normalizeEventTable(signsTable, {
                    tableName = "signs_and_portents",
                    source = request.signsAndPortentsTableSource or request.signsTableSource or
                        opts.signsAndPortentsTableSource or opts.signsTableSource or
                        signsTableMeta and signsTableMeta.source,
                    defaultCategory = city_events.CATEGORIES.SIGNS_AND_PORTENTS,
                    maxValue = 14,
                    requireComplete = request.requireCompleteSignsAndPortentsTable == true or
                        request.requireCompleteSignsTable == true or opts.requireCompleteSignsAndPortentsTable == true or
                        opts.requireCompleteSignsTable == true or
                        signsTableMeta and signsTableMeta.requireComplete == true,
                })
            elseif not signsTableMeta then
                signsTableMeta = {
                    tableName = "signs_and_portents",
                    source = "default",
                    missing = {},
                    invalid = {},
                    count = 14,
                    complete = true,
                    requireComplete = false,
                }
            end
            if signsTableMeta and signsTableMeta.requireComplete and not signsTableMeta.complete then
                if not disabled then
                    disabled = true
                    unavailableReason = "Signs and Portents table incomplete"
                end
            else
                sign = city_events.getSign(minorDiscard.value, signsTable)
                if sign then
                    sign = M.copyCityPhaseMetadata(sign)
                    sign.category = sign.category or city_events.CATEGORIES.SIGNS_AND_PORTENTS
                elseif not disabled then
                    disabled = true
                    unavailableReason = "Signs and Portents table entry missing"
                end
            end
        end
    end

    local effects = nil
    local effectPreview = nil
    if eventEntry then
        effects = mergeCityEventEffects({}, eventEntry.effects)
        effects = mergeCityEventEffects(effects, sign and sign.effects)
        local actors = activeAdventurers(request.guild or opts.guild or {})
        local randomEffect = effects.randomAdventurer or effects.random_adventurer
        local targetedEffect = effects.targetedAdventurer or effects.targeted_adventurer
        local randomTarget = nil
        if type(randomEffect) == "table" and minorDiscardValid then
            randomTarget = selectRandomAdventurerFromMinorDiscard(actors, minorDiscard)
        end
        local targetedTarget, targetedTargetDetail = nil, nil
        if type(targetedEffect) == "table" then
            if targetedEffect.target == "highest_suit" then
                targetedTarget, targetedTargetDetail = selectSuitTarget(actors, targetedEffect.suit, "highest")
                targetedTargetDetail = {
                    targetRule = targetedEffect.target,
                    suit = targetedEffect.suit,
                    suitValue = targetedTargetDetail,
                }
            elseif targetedEffect.target == "lowest_suit" then
                targetedTarget, targetedTargetDetail = selectSuitTarget(actors, targetedEffect.suit, "lowest")
                targetedTargetDetail = {
                    targetRule = targetedEffect.target,
                    suit = targetedEffect.suit,
                    suitValue = targetedTargetDetail,
                }
            end
        end
        local travelTarget, travelTargetDetail = nil, nil
        if type(effects.travelEvent or effects.travel_event) == "table" then
            travelTarget, travelTargetDetail = selectTravelCityEventTarget(effects.travelEvent or effects.travel_event, actors, request)
        end
        effectPreview = {
            effects = effects,
            upkeepCosts = effects.upkeepCosts,
            allowedCityActions = effects.allowedCityActions,
            blockedCityActions = effects.blockedCityActions,
            rationUpkeepTier = effects.rationUpkeepTier,
            randomAdventurer = type(randomEffect) == "table" and {
                effect = randomEffect,
                minorDiscard = minorDiscardValid and minorDiscard or nil,
                target = randomTarget,
                targetId = actorId(randomTarget),
                pending = randomTarget == nil,
                reason = randomTarget == nil and (minorDiscardValid and "requires_active_adventurer" or "requires_minor_discard") or nil,
            } or nil,
            targetedAdventurer = type(targetedEffect) == "table" and {
                effect = targetedEffect,
                target = targetedTarget,
                targetId = actorId(targetedTarget),
                targetRule = targetedTargetDetail and targetedTargetDetail.targetRule,
                suit = targetedTargetDetail and targetedTargetDetail.suit,
                suitValue = targetedTargetDetail and targetedTargetDetail.suitValue,
                pending = targetedTarget == nil,
                reason = targetedTarget == nil and "requires_active_adventurer" or nil,
            } or nil,
            travelEvent = type(effects.travelEvent or effects.travel_event) == "table" and {
                effect = effects.travelEvent or effects.travel_event,
                target = travelTarget,
                targetId = actorId(travelTarget),
                targetRule = travelTargetDetail and travelTargetDetail.targetRule,
                suit = travelTargetDetail and travelTargetDetail.suit,
                suitValue = travelTargetDetail and travelTargetDetail.suitValue,
                pending = travelTarget == nil,
                reason = travelTarget == nil and "target_required" or nil,
            } or nil,
            animalCompanionOpportunity = effects.animalCompanionOpportunity or effects.animal_companion_opportunity,
            animalCompanionCatastrophe = effects.animalCompanionCatastrophe or effects.animal_companion_catastrophe,
            cityOmen = effects.cityOmen or effects.city_omen,
            citySuccession = effects.citySuccession or effects.city_succession,
            undeadPlague = effects.undeadPlague or effects.undead_plague,
            nextCrawlCondition = effects.nextCrawlCondition or effects.nextCrawl_condition,
            timing = effects.timing,
            testSuit = effects.testSuit,
        }
    end

    local consumedPreviews = {}
    if eventEntry then
        consumedPreviews[#consumedPreviews + 1] = {
            value = eventEntry.value,
            title = eventEntry.title,
            category = eventEntry.category,
            id = eventEntry.id,
            source = eventEntry.source,
            tableSource = eventEntry.tableSource,
            table = "city_events",
        }
    end
    if sign then
        consumedPreviews[#consumedPreviews + 1] = {
            value = sign.value,
            title = sign.title,
            category = sign.category,
            id = sign.id,
            source = sign.source,
            tableSource = sign.tableSource,
            table = "signs_and_portents",
        }
    end

    return {
        step = M.STEPS.CITY_EVENTS,
        card = explicitCard,
        cardValid = explicitCard == nil and nil or cardValid == true,
        requiresDraw = explicitCard == nil,
        autoDrawAvailable = explicitCard == nil and majorDeck and majorDeck.draw ~= nil or false,
        event = eventEntry,
        category = eventCategory,
        cityEventsTable = eventsTableMeta,
        cityEventsTableSource = eventsTableMeta and eventsTableMeta.source,
        signCard = eventCategory == city_events.CATEGORIES.SIGNS_AND_PORTENTS and minorDiscard or nil,
        signCardValid = eventCategory == city_events.CATEGORIES.SIGNS_AND_PORTENTS and
            (minorDiscard == nil and nil or minorDiscardValid == true) or nil,
        sign = sign,
        signsAndPortentsTable = signsTableMeta,
        signsAndPortentsTableSource = signsTableMeta and signsTableMeta.source,
        effects = effects,
        effectPreview = effectPreview,
        consumedEntryPreviews = consumedPreviews,
        resultPreview = eventEntry and not disabled and "city_event_resolved" or nil,
        disabled = disabled,
        unavailableReason = unavailableReason,
    }
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

function appendActorRecord(actor, field, record)
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

function M.getUpkeepOptions(opts)
    opts = opts or {}
    local actor = opts.actor or opts
    local request = opts.request or opts.upkeep or opts.upkeepRequest or opts
    actor = request.actor or actor

    local selectedTierId = normalizeUpkeepTier(request.tier or request.upkeepTier)
    local selectedTier = M.UPKEEP_TIERS[selectedTierId]
    local cityEventEffects = request.cityEventEffects or opts.cityEventEffects or opts.effects or {}
    local upkeepCosts = cityEventEffects.upkeepCosts or {}
    local completed = opts.upkeepCompleted or opts.completedUpkeep or request.upkeepCompleted or {}
    local id = actorId(actor)
    local gold = actor and currency.getGold(actor) or math.floor(tonumber(opts.gold or request.gold) or 0)

    local function upkeepCost(tier)
        local override = upkeepCosts[tier.id]
        if override ~= nil then
            return math.max(0, math.floor(tonumber(override) or tier.cost))
        end
        return tier.cost
    end

    local tierOrder = { "destitute", "impoverished", "common", "luxurious" }
    local tierOptions = {}
    for _, tierId in ipairs(tierOrder) do
        local tier = M.UPKEEP_TIERS[tierId]
        local cost = upkeepCost(tier)
        tierOptions[#tierOptions + 1] = {
            id = tier.id,
            tier = tier.id,
            cost = cost,
            baseCost = tier.cost,
            costModified = cost ~= tier.cost,
            affordable = gold >= cost,
            refillTier = tier.refillTier,
            recoveryAllowed = tier.recoveryAllowed,
            luxurious = tier.luxurious,
            selected = tier.id == selectedTierId,
            disabled = gold < cost,
            unavailableReason = gold < cost and "Not enough gold" or nil,
            consequencePreview = tier.id == "destitute" and {
                condition = "stressed",
                nextCrawlCondition = "stressed",
                source = "destitute_upkeep",
            } or nil,
        }
    end

    local marketItemOptions = {}
    for templateId, itemTier in pairs(M.MARKET_TIERS) do
        local template = item_templates.getTemplate(templateId)
        if template then
            local location = template.isArmor and inventory.LOCATIONS.BELT or inventory.LOCATIONS.PACK
            local covered = selectedTier and selectedTier.refillTier and
                canBuyMarketTier(selectedTier.refillTier, itemTier) or false
            marketItemOptions[#marketItemOptions + 1] = {
                id = templateId,
                templateId = templateId,
                name = template.name or templateId,
                tier = itemTier,
                size = template.size or inventory.SIZE.NORMAL,
                stackable = template.stackable == true,
                stackSize = template.stackSize,
                defaultQuantity = template.quantity or 1,
                defaultLocation = location,
                coveredBySelectedTier = covered,
                disabled = selectedTier ~= nil and not covered or nil,
                unavailableReason = selectedTier ~= nil and not covered and "Gear tier not covered by upkeep" or nil,
            }
        end
    end
    table.sort(marketItemOptions, function(a, b)
        if a.tier ~= b.tier then
            return (MARKET_TIER_RANK[a.tier] or 0) < (MARKET_TIER_RANK[b.tier] or 0)
        end
        return tostring(a.name or a.templateId) < tostring(b.name or b.templateId)
    end)

    local selectedRefillItems = {}
    local plannedGear = {}
    local gearRequests = normalizeGearRequests(request.refillItems or request.refillGear or request.gear or request.items)
    local gearError = nil
    if #gearRequests > 0 then
        if not selectedTier or not selectedTier.refillTier then
            gearError = selectedTier and "Upkeep tier cannot refill gear" or "Unknown upkeep tier"
        elseif not actor or not actor.inventory or not actor.inventory.addItem then
            gearError = "No inventory for upkeep gear"
        end
        if not gearError then
            for _, refill in ipairs(gearRequests) do
                local templateId = refill.templateId and tostring(refill.templateId) or nil
                local itemTier = nil
                local item = nil
                local custom = not templateId
                local reason = nil
                if templateId then
                    local template = item_templates.getTemplate(templateId)
                    if not template then
                        reason = "Unknown market item"
                    else
                        itemTier = M.MARKET_TIERS[templateId]
                        item = inventory.createItemFromTemplate(templateId, {
                            quantity = refill.quantity,
                        })
                    end
                else
                    local itemName = refill.name and tostring(refill.name):gsub("^%s+", ""):gsub("%s+$", "")
                    if not refill.custom or not itemName or itemName == "" then
                        reason = "Unknown market item"
                    else
                        itemTier = normalizeUpkeepTier(refill.tier)
                        if not MARKET_TIER_RANK[itemTier] then
                            reason = "Custom gear tier required"
                        else
                            local properties = shallowClone(refill.properties or {})
                            properties.upkeepCustom = true
                            properties.marketTier = itemTier
                            item = inventory.createItem({
                                id = refill.customId,
                                name = itemName,
                                size = refill.size,
                                oversized = refill.oversized,
                                stackable = refill.stackable,
                                stackSize = refill.stackSize,
                                quantity = refill.quantity,
                                type = refill.itemType,
                                properties = properties,
                            })
                            item.marketTier = itemTier
                            item.upkeepCustom = true
                        end
                    end
                end
                if not reason and not canBuyMarketTier(selectedTier.refillTier, itemTier) then
                    reason = "Gear tier not covered by upkeep"
                elseif not reason and not item then
                    reason = "Unknown market item"
                end

                local option = {
                    templateId = templateId,
                    item = item,
                    itemId = item and item.id or refill.customId,
                    name = item and item.name or refill.name or templateId,
                    tier = itemTier,
                    quantity = refill.quantity,
                    location = refill.location or inventory.LOCATIONS.PACK,
                    custom = custom,
                    coveredBySelectedTier = reason == nil,
                    disabled = reason ~= nil,
                    unavailableReason = reason,
                }
                selectedRefillItems[#selectedRefillItems + 1] = option
                if reason and not gearError then
                    gearError = reason
                elseif item then
                    plannedGear[#plannedGear + 1] = {
                        item = item,
                        location = option.location,
                    }
                end
            end
            if not gearError and #plannedGear > 0 then
                local canAdd, reason = canAddPlannedItemsToInventory(actor.inventory, plannedGear)
                if not canAdd then
                    gearError = reason
                end
            end
        end
    end

    local repairItemOptions = {}
    local inv = actor and actor.inventory
    if inv and inv.getAllItems then
        for _, entry in ipairs(inv:getAllItems()) do
            local item = entry.item
            if item and (item.destroyed == true or (tonumber(item.notches) or 0) > 0) then
                local repairTier = itemMarketTier(item, {})
                local covered = selectedTier and selectedTier.refillTier and
                    canBuyMarketTier(selectedTier.refillTier, repairTier) or false
                repairItemOptions[#repairItemOptions + 1] = {
                    id = item.id,
                    itemId = item.id,
                    item = item,
                    name = item.name,
                    location = entry.location,
                    tier = repairTier,
                    notches = item.notches or 0,
                    destroyed = item.destroyed == true,
                    coveredBySelectedTier = covered,
                    disabled = selectedTier ~= nil and not covered or nil,
                    unavailableReason = selectedTier ~= nil and not covered and "Repair tier not covered by upkeep" or nil,
                }
            end
        end
    end

    local selectedRepairItems = {}
    local repairRequests = normalizeRepairRequests(request.repairItems or request.repairGear or request.repairs or request.repairItemIds)
    local repairError = nil
    if #repairRequests > 0 then
        if not selectedTier or not selectedTier.refillTier then
            repairError = selectedTier and "Upkeep tier cannot repair gear" or "Unknown upkeep tier"
        elseif not inv or not inv.findItem then
            repairError = "No inventory for upkeep repair"
        end
        if not repairError then
            for _, repair in ipairs(repairRequests) do
                local item = inv:findItem(repair.itemId)
                local repairTier = item and itemMarketTier(item, repair) or nil
                local reason = nil
                if not item then
                    reason = "Repair item not found"
                elseif not item.destroyed and (not item.notches or item.notches <= 0) then
                    reason = "Item is not damaged"
                elseif not canBuyMarketTier(selectedTier.refillTier, repairTier) then
                    reason = "Repair tier not covered by upkeep"
                end
                selectedRepairItems[#selectedRepairItems + 1] = {
                    item = item,
                    itemId = repair.itemId,
                    templateId = repair.templateId or item and item.templateId,
                    name = item and item.name,
                    tier = repairTier,
                    wasDestroyed = item and item.destroyed == true or nil,
                    previousNotches = item and item.notches or nil,
                    coveredBySelectedTier = reason == nil,
                    disabled = reason ~= nil,
                    unavailableReason = reason,
                }
                if reason and not repairError then
                    repairError = reason
                end
            end
        end
    end

    local chargedBonds = {}
    local bondOptions = {}
    for targetId, bond in pairs(actor and actor.bonds or {}) do
        bondOptions[#bondOptions + 1] = {
            targetId = targetId,
            bond = bond,
            status = bond.status or bond.type,
            charged = bond.charged == true,
            disabled = bond.charged ~= true,
            unavailableReason = bond.charged ~= true and "Bond is not charged" or nil,
        }
        if bond.charged == true then
            chargedBonds[#chargedBonds + 1] = targetId
        end
    end
    table.sort(bondOptions, function(a, b)
        return tostring(a.targetId) < tostring(b.targetId)
    end)

    local recoveryAllowed = selectedTier and selectedTier.recoveryAllowed or false
    local needsExtraBond = recoveryNeedsExtraBond(actor)
    local recoverySpendOptions = {}
    local function addRecoverySpend(idValue, label, result, disabled, reason, bondCost)
        recoverySpendOptions[#recoverySpendOptions + 1] = {
            id = idValue,
            spendType = idValue,
            label = label,
            result = result,
            bondCost = bondCost or 1,
            disabled = disabled,
            unavailableReason = reason,
        }
    end
    local noChargedBonds = #chargedBonds == 0
    addRecoverySpend("clear_stress", "Clear Stressed", "stress_cleared",
        not recoveryAllowed or noChargedBonds or not (actor and actor.conditions and actor.conditions.stressed),
        not recoveryAllowed and "Upkeep tier does not allow recovery" or
            noChargedBonds and "Bond is not charged" or
            not (actor and actor.conditions and actor.conditions.stressed) and "No stress to clear" or nil)
    addRecoverySpend("heal_wound", "Heal Wound", nextRecoveryWoundResult(actor),
        not recoveryAllowed or noChargedBonds or
            (actor and actor.conditions and actor.conditions.stressed == true) or
            nextRecoveryWoundResult(actor) == "fully_healed" or
            (needsExtraBond and #chargedBonds < 2),
        not recoveryAllowed and "Upkeep tier does not allow recovery" or
            noChargedBonds and "Bond is not charged" or
            (actor and actor.conditions and actor.conditions.stressed == true) and "Must clear stress first" or
            nextRecoveryWoundResult(actor) == "fully_healed" and "No wound to heal" or
            (needsExtraBond and #chargedBonds < 2) and "Requires two charged Bonds" or nil,
        needsExtraBond and 2 or 1)
    addRecoverySpend("regain_resolve", "Regain Resolve", "resolve_regained",
        not recoveryAllowed or noChargedBonds,
        not recoveryAllowed and "Upkeep tier does not allow recovery" or
            noChargedBonds and "Bond is not charged" or nil)

    local resolveMax = type(actor and actor.resolve) == "table" and actor.resolve.max or
        tonumber(actor and (actor.resolveMax or actor.maxResolve))
    local resolveCurrent = type(actor and actor.resolve) == "table" and actor.resolve.current or
        tonumber(actor and actor.resolve)
    local luxuriousHealingPreview = selectedTier and selectedTier.luxurious and {
        armorNotches = actor and actor.armorNotches or 0,
        woundedTalents = actor and actor.woundedTalents or 0,
        staggered = actor and actor.conditions and actor.conditions.staggered == true or false,
        injured = actor and actor.conditions and actor.conditions.injured == true or false,
        deathsDoor = actor and actor.conditions and actor.conditions.deaths_door == true or false,
        resolveCurrent = resolveCurrent,
        resolveMax = resolveMax,
        resolveRefreshed = resolveMax or resolveCurrent,
    } or nil

    local disabled = false
    local unavailableReason = nil
    if not id then
        disabled = true
        unavailableReason = "No active adventurer"
    elseif completed[id] then
        disabled = true
        unavailableReason = "Upkeep already paid"
    elseif selectedTierId ~= "" and not selectedTier then
        disabled = true
        unavailableReason = "Unknown upkeep tier"
    elseif selectedTier and gold < upkeepCost(selectedTier) then
        disabled = true
        unavailableReason = "Not enough gold"
    elseif gearError then
        disabled = true
        unavailableReason = gearError
    elseif repairError then
        disabled = true
        unavailableReason = repairError
    end

    local selectedCost = selectedTier and upkeepCost(selectedTier) or nil
    return {
        step = M.STEPS.UPKEEP,
        actor = actor,
        actorId = id,
        name = actor and actor.name or id,
        gold = gold,
        selectedTier = selectedTier and {
            id = selectedTier.id,
            tier = selectedTier.id,
            cost = selectedCost,
            baseCost = selectedTier.cost,
            costModified = selectedCost ~= selectedTier.cost,
            refillTier = selectedTier.refillTier,
            recoveryAllowed = selectedTier.recoveryAllowed,
            luxurious = selectedTier.luxurious,
        } or nil,
        selectionRequired = selectedTierId == "",
        tierOptions = tierOptions,
        marketItemOptions = marketItemOptions,
        selectedRefillItems = selectedRefillItems,
        repairItemOptions = repairItemOptions,
        selectedRepairItems = selectedRepairItems,
        recoveryPreview = {
            recoveryAllowed = recoveryAllowed,
            chargedBondCount = #chargedBonds,
            bonds = bondOptions,
            spendOptions = recoverySpendOptions,
            nextWoundResult = nextRecoveryWoundResult(actor),
            maledictionExtraBondRecoveryCost = needsExtraBond,
        },
        luxuriousHealingPreview = luxuriousHealingPreview,
        destituteConsequencePreview = selectedTier and selectedTier.id == "destitute" and {
            condition = "stressed",
            nextCrawlCondition = "stressed",
            source = "destitute_upkeep",
        } or nil,
        projectedGold = selectedCost and math.max(0, gold - selectedCost) or nil,
        disabled = disabled,
        unavailableReason = unavailableReason,
    }
end

function M.getNewAdventurerStartingGearOptions(opts)
    opts = opts or {}
    local request = opts.request or opts.startingGearRequest or opts.gearRequest or opts
    local actor = request.actor or request.adventurer or request.newAdventurer or
        opts.actor or opts.adventurer or opts.newAdventurer
    local itemRequests = normalizeGearRequests(request.items or request.gear or request.startingGear or
        request.marketItems or opts.items or opts.gear or opts.startingGear or opts.marketItems)

    local talentItemSet = {}
    for _, entry in ipairs(normalizeList(request.talentItems or request.talentGear or request.requiredTalentItems or
        opts.talentItems or opts.talentGear or opts.requiredTalentItems)) do
        local templateId = entry
        if type(entry) == "table" then
            templateId = entry.templateId or entry.itemTemplate or entry.itemTemplateId or entry.id or entry[1]
        end
        if templateId then
            talentItemSet[tostring(templateId)] = true
        end
    end

    local marketItemOptions = {}
    for templateId, itemTier in pairs(M.MARKET_TIERS) do
        local template = item_templates.getTemplate(templateId)
        if template then
            local location = (template.isArmor or template.oversized) and inventory.LOCATIONS.BELT or
                inventory.LOCATIONS.PACK
            marketItemOptions[#marketItemOptions + 1] = {
                id = templateId,
                templateId = templateId,
                name = template.name or templateId,
                tier = itemTier,
                size = template.size or inventory.SIZE.NORMAL,
                stackable = template.stackable == true,
                stackSize = template.stackSize,
                defaultQuantity = template.quantity or 1,
                defaultLocation = location,
                canCountAsTalentItem = true,
            }
        end
    end
    table.sort(marketItemOptions, function(a, b)
        if a.tier ~= b.tier then
            return (MARKET_TIER_RANK[a.tier] or 0) < (MARKET_TIER_RANK[b.tier] or 0)
        end
        return tostring(a.name or a.templateId) < tostring(b.name or b.templateId)
    end)

    local tierCounts = {
        impoverished = 0,
        common = 0,
        luxurious = 0,
    }
    local selectedItems = {}
    local plannedItems = {}
    local selectionError = nil
    for _, gearRequest in ipairs(itemRequests) do
        local templateId = gearRequest.templateId and tostring(gearRequest.templateId) or nil
        local template = templateId and item_templates.getTemplate(templateId) or nil
        local baseTier = templateId and M.MARKET_TIERS[templateId] or nil
        local itemTier = baseTier
        local talentRequired = false
        if templateId and (
            gearRequest.forTalent == true or gearRequest.talentRequired == true or
            gearRequest.requiredForTalent == true or gearRequest.talentItem == true or
            talentItemSet[templateId] == true
        ) then
            itemTier = "impoverished"
            talentRequired = baseTier ~= "impoverished"
        end

        local reason = nil
        local item = nil
        if not templateId then
            reason = "Unknown market item"
        elseif not template then
            reason = "Unknown market item"
        elseif not MARKET_TIER_RANK[itemTier] then
            reason = "Unknown market item"
        else
            item = inventory.createItemFromTemplate(templateId, {
                quantity = gearRequest.quantity,
            })
            if not item then
                reason = "Unknown market item"
            end
        end

        local location = gearRequest.location or inventory.LOCATIONS.PACK
        if item and (item.isArmor or item.oversized) then
            location = inventory.LOCATIONS.BELT
        end

        local option = {
            id = templateId,
            templateId = templateId,
            name = item and item.name or template and template.name or gearRequest.name or templateId,
            item = item,
            itemId = item and item.id,
            tier = itemTier,
            marketTier = baseTier,
            quantity = gearRequest.quantity,
            requestedLocation = gearRequest.location,
            location = location,
            size = item and item.size or template and template.size or gearRequest.size,
            stackable = item and item.stackable == true or template and template.stackable == true or nil,
            stackSize = item and item.stackSize or template and template.stackSize,
            isArmor = item and item.isArmor == true or template and template.isArmor == true or nil,
            oversized = item and item.oversized == true or template and template.oversized == true or nil,
            talentRequired = talentRequired or nil,
            tierReason = talentRequired and "talent_required_gear" or nil,
            disabled = reason ~= nil,
            unavailableReason = reason,
        }
        selectedItems[#selectedItems + 1] = option
        if reason and not selectionError then
            selectionError = reason
        elseif item then
            tierCounts[itemTier] = (tierCounts[itemTier] or 0) + gearRequest.quantity
            plannedItems[#plannedItems + 1] = {
                templateId = templateId,
                tier = itemTier,
                item = item,
                quantity = gearRequest.quantity,
                location = location,
                talentRequired = talentRequired or nil,
            }
        end
    end

    local previewInventory = nil
    local usesDefaultInventory = false
    if actor then
        if actor.inventory ~= nil and actor.inventory ~= false then
            previewInventory = actor.inventory
        else
            previewInventory = inventory.createInventory()
            usesDefaultInventory = true
        end
    end

    local capacityPreview = {
        usesDefaultInventory = usesDefaultInventory,
        availableByLocation = {},
        requiredByLocation = {},
        fits = nil,
    }
    if previewInventory and previewInventory.availableSlots then
        for _, location in ipairs({ inventory.LOCATIONS.HANDS, inventory.LOCATIONS.BELT, inventory.LOCATIONS.PACK }) do
            capacityPreview.availableByLocation[location] = previewInventory:availableSlots(location)
        end
        for _, planned in ipairs(plannedItems) do
            local location = planned.location or inventory.LOCATIONS.PACK
            local slotsNeeded = planned.item.stackable and 1 or planned.item.size
            capacityPreview.requiredByLocation[location] =
                (capacityPreview.requiredByLocation[location] or 0) + slotsNeeded
        end
    end

    local requireComplete = firstProvided(request.requireComplete, opts.requireComplete)
    requireComplete = requireComplete ~= false
    local disabled = false
    local unavailableReason = nil
    if not actor then
        disabled = true
        unavailableReason = "New adventurer required"
    elseif not previewInventory or not previewInventory.addItem then
        disabled = true
        unavailableReason = "No inventory for starting gear"
    elseif #itemRequests == 0 then
        disabled = true
        unavailableReason = "Starting gear required"
    elseif selectionError then
        disabled = true
        unavailableReason = selectionError
    elseif tierCounts.luxurious > 1 then
        disabled = true
        unavailableReason = "Starting gear allows one luxurious item"
    elseif tierCounts.common > 5 then
        disabled = true
        unavailableReason = "Starting gear allows five common items"
    elseif requireComplete and tierCounts.luxurious ~= 1 then
        disabled = true
        unavailableReason = "Starting gear requires one luxurious item"
    elseif requireComplete and tierCounts.common ~= 5 then
        disabled = true
        unavailableReason = "Starting gear requires five common items"
    else
        local canAdd, reason = canAddPlannedItemsToInventory(previewInventory, plannedItems)
        if not canAdd then
            disabled = true
            unavailableReason = reason
        end
    end
    capacityPreview.fits = not disabled or unavailableReason ~= "invalid_location" and
        unavailableReason ~= "oversized_belt_only" and unavailableReason ~= "armor_belt_only" and
        unavailableReason ~= "insufficient_slots"
    capacityPreview.unavailableReason = capacityPreview.fits and nil or unavailableReason

    return {
        actor = actor,
        actorId = actorId(actor),
        actorName = actor and actor.name,
        rulebookChecklist = {
            luxurious = 1,
            common = 5,
            impoverished = "unlimited",
            talentItemsCountAs = "impoverished",
        },
        requiredLuxurious = 1,
        requiredCommon = 5,
        allowedCommon = 5,
        unlimitedImpoverished = true,
        requireComplete = requireComplete,
        selectionRequired = #itemRequests == 0,
        marketItemOptions = marketItemOptions,
        selectedItems = selectedItems,
        items = selectedItems,
        plannedItems = plannedItems,
        tierCounts = tierCounts,
        counts = tierCounts,
        complete = tierCounts.luxurious == 1 and tierCounts.common == 5,
        capacityPreview = capacityPreview,
        disabled = disabled,
        unavailableReason = unavailableReason,
        resultPreview = not disabled and "starting_gear_selected" or nil,
    }
end

function M.getDistrictActionOptions(opts)
    opts = opts or {}
    local request = opts.request or opts.districtActionRequest or opts
    local actor = request.actor or request.adventurer or opts.actor or opts.adventurer
    local actorKey = actorId(actor)
    local actionsCompleted = opts.actionsCompleted or request.actionsCompleted or {}
    local effects = opts.cityEventEffects or request.cityEventEffects or opts.effects or request.effects or {}
    local cityState = opts.cityState or request.cityState or {}
    local ignoreActorGates = opts.ignoreActorGates == true or request.ignoreActorGates == true
    local actionSource = request.districtActions or request.specialCityActions or opts.districtActions or
        opts.specialCityActions or request.cityLayout and request.cityLayout.specialCityActions or
        opts.cityLayout and opts.cityLayout.specialCityActions or {}
    local selectedActionId = request.districtAction or request.districtActionId or
        request.specialCityAction or request.specialCityActionId or request.action or request.actionId or
        request.type or request.id
    if selectedActionId ~= nil then
        selectedActionId = tostring(selectedActionId)
        if selectedActionId == "" then
            selectedActionId = nil
        end
    end

    local options = {}
    local optionsByDistrictActionId = {}
    local selectedAction = nil
    local availableCount = 0
    local implementedCount = 0

    local function addOption(key, entry)
        local actionEntry = type(entry) == "table" and entry.action or entry
        local districtActionId = nil
        if type(actionEntry) == "table" then
            districtActionId = actionEntry.id or actionEntry.action or actionEntry.type
        else
            districtActionId = actionEntry
        end
        if not districtActionId and type(entry) == "table" then
            districtActionId = entry.districtAction or entry.districtActionId or entry.specialCityAction or
                entry.id or key
        end
        districtActionId = districtActionId and tostring(districtActionId) or nil

        local actionId = districtActionAlias(districtActionId)
        local districtId = type(entry) == "table" and
            (entry.districtId or entry.district_id or entry.district and entry.district.id) or nil
        local districtName = type(entry) == "table" and
            (entry.districtName or entry.district_name or entry.district and entry.district.name) or nil
        local actionName = type(actionEntry) == "table" and actionEntry.name or districtActionId
        local blockedDistricts = effects.blockedDistrictIds or {}
        local blockedDistrictActions = effects.blockedDistrictActions or {}
        local disabled = false
        local unavailableReason = nil
        local cityActionAllowed = true
        local cityActionUnavailableReason = nil
        local districtBlocked = type(entry) == "table" and entry.blockedByCityEvent == true or false
        if districtId and blockedDistricts[districtId] then
            districtBlocked = true
        end
        if districtActionId and blockedDistrictActions[districtActionId] then
            districtBlocked = true
        end
        if actionId and blockedDistrictActions[actionId] then
            districtBlocked = true
        end

        if districtBlocked then
            disabled = true
            unavailableReason = "District City Action blocked by City Event"
        elseif not actionId then
            disabled = true
            unavailableReason = "District City Action not implemented"
        else
            implementedCount = implementedCount + 1
            local blocked = effects.blockedCityActions
            if blocked == "all" then
                cityActionAllowed = false
                cityActionUnavailableReason = "City Actions blocked by City Event"
            elseif cityState.cityActionsBlockedByUndead and
               (type(cityState.undeadPlague) ~= "table" or cityState.undeadPlague.active ~= false) then
                cityActionAllowed = false
                cityActionUnavailableReason = "City Actions blocked by undead plague"
            elseif effects.allowedCityActions and not effects.allowedCityActions[actionId] then
                cityActionAllowed = false
                cityActionUnavailableReason = "City Action not available during this City Event"
            elseif type(blocked) == "table" and blocked[actionId] then
                cityActionAllowed = false
                cityActionUnavailableReason = "City Action blocked by City Event"
            end
            if not cityActionAllowed then
                disabled = true
                unavailableReason = cityActionUnavailableReason
            elseif not ignoreActorGates then
                if not isActiveAdventurer(actor) then
                    disabled = true
                    unavailableReason = "No active adventurer"
                elseif actorKey and actionsCompleted[actorKey] then
                    disabled = true
                    unavailableReason = "City Action already taken"
                end
            end
        end

        local option = {
            key = key,
            id = districtActionId,
            districtActionId = districtActionId,
            actionId = actionId,
            canonicalAction = actionId,
            name = actionName,
            label = actionName,
            summary = type(actionEntry) == "table" and actionEntry.summary or nil,
            mechanics = type(actionEntry) == "table" and M.copyCityPhaseMetadata(actionEntry.mechanics) or {},
            action = type(actionEntry) == "table" and M.copyCityPhaseMetadata(actionEntry) or {
                id = districtActionId,
                name = actionName,
            },
            districtId = districtId,
            districtName = districtName,
            district = type(entry) == "table" and M.copyCityPhaseMetadata(entry.district) or nil,
            source = type(entry) == "table" and M.copyCityPhaseMetadata(entry) or nil,
            implemented = actionId ~= nil,
            cityActionAllowed = cityActionAllowed,
            cityActionUnavailableReason = cityActionUnavailableReason,
            blockedByCityEvent = districtBlocked,
            selected = selectedActionId ~= nil and districtActionId == selectedActionId,
            disabled = disabled,
            unavailableReason = unavailableReason,
            resultPreview = not disabled and "district_action_ready" or nil,
        }
        options[#options + 1] = option
        if districtActionId then
            optionsByDistrictActionId[districtActionId] = option
        end
        if option.selected then
            selectedAction = option
        end
        if not disabled then
            availableCount = availableCount + 1
        end
    end

    for key, entry in ipairs(actionSource) do
        addOption(key, entry)
    end
    for key, entry in pairs(actionSource) do
        if type(key) ~= "number" then
            addOption(key, entry)
        end
    end

    if selectedActionId and not selectedAction then
        selectedAction = {
            id = selectedActionId,
            districtActionId = selectedActionId,
            actionId = districtActionAlias(selectedActionId),
            selected = true,
            disabled = true,
            unavailableReason = "District City Action unavailable",
        }
    end

    return {
        actor = actor,
        actorId = actorKey,
        actorName = actor and actor.name,
        districtActions = options,
        actions = options,
        actionsByDistrictActionId = optionsByDistrictActionId,
        selectedAction = selectedAction,
        selectedActionId = selectedActionId,
        selectionRequired = selectedActionId == nil,
        totalCount = #options,
        availableCount = availableCount,
        implementedCount = implementedCount,
        cityEventRestrictions = {
            allowedCityActions = M.copyCityPhaseMetadata(effects.allowedCityActions),
            blockedCityActions = M.copyCityPhaseMetadata(effects.blockedCityActions),
            blockedDistrictIds = M.copyCityPhaseMetadata(effects.blockedDistrictIds),
            blockedDistrictActions = M.copyCityPhaseMetadata(effects.blockedDistrictActions),
            cityActionsBlockedByUndead = cityState.cityActionsBlockedByUndead == true,
            undeadPlague = M.copyCityPhaseMetadata(cityState.undeadPlague),
        },
        disabled = selectedAction ~= nil and selectedAction.disabled or false,
        unavailableReason = selectedAction and selectedAction.unavailableReason or nil,
        resultPreview = selectedAction and selectedAction.resultPreview or nil,
    }
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

local function actorsMatch(a, b)
    local aId = actorId(a)
    local bId = actorId(b)
    if aId and bId then
        return aId == bId
    end
    return a == b
end

local function addActorToList(list, actor)
    if type(list) ~= "table" or not actor then
        return false
    end
    for _, entry in ipairs(list) do
        if actorsMatch(entry, actor) then
            return false
        end
    end
    list[#list + 1] = actor
    return true
end

local function removeActorFromList(list, actor)
    if type(list) ~= "table" or not actor then
        return false
    end
    for index = #list, 1, -1 do
        if actorsMatch(list[index], actor) then
            table.remove(list, index)
            return true
        end
    end
    return false
end

local function getRosterAdventurers(roster)
    if type(roster) ~= "table" then
        return nil
    end
    if type(roster.adventurers) == "table" then
        return roster.adventurers
    end
    if type(roster.members) == "table" then
        roster.adventurers = roster.members
        return roster.adventurers
    end
    roster.adventurers = {}
    return roster.adventurers
end

function M.discoveryRumorKey(discovery)
    if type(discovery) == "table" then
        return discovery.id or discovery.key or discovery.roomId or discovery.room_id or discovery.featureId or
            discovery.feature_id or discovery.connectionId or discovery.connection_id or discovery.text or
            discovery.summary or discovery.description or discovery.name
    end
    return discovery
end

function M.isWithheldFromRumorMill(discovery)
    if type(discovery) ~= "table" then
        return false
    end
    return discovery.keptSecret == true or discovery.keepSecret == true or discovery.withheld == true or
        discovery.withheldFromRumorMill == true or discovery.private == true or
        discovery.rumorMill == false or discovery.commonKnowledge == false or discovery.public == false
end

function M.appendRumorMillDiscovery(discoveries, seen, discovery)
    if not discovery or M.isWithheldFromRumorMill(discovery) then
        return false
    end
    if type(discovery) == "table" and discovery.rumorMillDiscoverable == false then
        return false
    end

    local key = M.discoveryRumorKey(discovery)
    if key then
        key = tostring(key)
        if seen[key] then
            return false
        end
        seen[key] = true
    end

    discoveries[#discoveries + 1] = shallowClone(discovery)
    return true
end

function M.collectRumorMillDiscoveries(roster, opts)
    opts = opts or {}
    local discoveries = {}
    local seen = {}

    local function ingest(source)
        if type(source) ~= "table" then
            M.appendRumorMillDiscovery(discoveries, seen, source)
            return
        end
        for key, entry in pairs(source) do
            if type(key) == "number" then
                M.appendRumorMillDiscovery(discoveries, seen, entry)
            elseif type(entry) == "table" then
                local record = shallowClone(entry)
                record.id = record.id or key
                M.appendRumorMillDiscovery(discoveries, seen, record)
            elseif entry == true then
                M.appendRumorMillDiscovery(discoveries, seen, {
                    id = key,
                    text = key,
                })
            elseif entry then
                M.appendRumorMillDiscovery(discoveries, seen, {
                    id = key,
                    text = entry,
                })
            end
        end
    end

    local sources = {}
    local function addSource(source)
        if source ~= nil then
            sources[#sources + 1] = source
        end
    end

    addSource(opts.rumorMill)
    addSource(opts.rumorMillDiscoveries)
    addSource(opts.discoveries)
    addSource(opts.knownDiscoveries)
    if type(roster) == "table" then
        addSource(roster.rumorMill)
        addSource(roster.rumorMillDiscoveries)
        addSource(roster.commonKnowledge)
        addSource(roster.knownDiscoveries)
        addSource(roster.discoveries)
        addSource(roster.underworldDiscoveries)
        addSource(roster.mapDiscoveries)
    end

    for _, source in ipairs(sources) do
        ingest(source)
    end

    return discoveries
end

local function appendRosterRecords(roster, key, records)
    if type(roster) ~= "table" or type(key) ~= "string" or key == "" then
        return {}
    end
    local added = {}
    local list = roster[key]
    if type(list) ~= "table" then
        list = {}
        roster[key] = list
    end

    local function append(record)
        local copy = shallowClone(record)
        list[#list + 1] = copy
        added[#added + 1] = copy
    end

    if type(records) == "table" then
        if records.id or records.name or records.title or records.description then
            append(records)
        else
            for _, record in ipairs(records) do
                append(record)
            end
        end
    elseif records ~= nil then
        append({ name = tostring(records) })
    end

    return added
end

local function mergeSupportState(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then
        return {}
    end

    local changed = {}
    for key, value in pairs(source) do
        if type(value) == "table" and type(target[key]) == "table" and not value[1] then
            changed[key] = mergeSupportState(target[key], value)
        else
            target[key] = shallowClone(value)
            changed[key] = shallowClone(value)
        end
    end
    return changed
end

local function normalizeSupportCompletionEffects(project, request)
    local effects = request.completionEffects or request.completion or request.effects or request.outcomeEffects or
        project.completionEffects or project.completion or project.effects
    if type(effects) ~= "table" then
        effects = {}
    else
        effects = shallowClone(effects)
    end

    local outcome = request.outcome or request.outcomeDescription or request.resultDescription or request.resultNote or
        effects.outcome or effects.description or effects.note or project.outcome
    if outcome and not effects.outcome then
        effects.outcome = outcome
    end
    return effects
end

local function normalizeSupportComplexity(request)
    local complexity = tonumber(request.complexity or request.stepsRequired or request.totalSteps)
    if not complexity then
        return nil, "Project complexity required"
    end
    if complexity ~= math.floor(complexity) then
        return nil, "Project complexity must be a whole number"
    end
    if complexity < 2 or complexity > 8 then
        return nil, "Project complexity must be 2-8"
    end
    return complexity
end

function M.classifySupportContributionImpact(amount)
    local gold = math.floor(tonumber(amount) or 0)
    for _, band in ipairs(M.SUPPORT_CONTRIBUTION_IMPACTS) do
        if gold >= band.minimumGold then
            return {
                id = band.id,
                label = band.label,
                minimumGold = band.minimumGold,
                gold = gold,
            }
        end
    end

    return {
        id = "below_small",
        label = "below small impact",
        minimumGold = 1,
        gold = gold,
    }
end

local function applySupportCompletionEffects(controller, project, actor, request)
    local effects = normalizeSupportCompletionEffects(project, request)
    local detail = {
        actor = actor,
        projectId = project.id,
        outcome = effects.outcome,
        cityStateUpdates = {},
        cityStateFlags = {},
        rosterUpdates = {},
        projectFlags = {},
    }

    if effects.outcome then
        project.outcome = effects.outcome
    end

    local stateUpdates = effects.cityState or effects.worldState or effects.state
    if type(stateUpdates) == "table" then
        detail.cityStateUpdates = mergeSupportState(controller.cityState, stateUpdates)
    end

    local flags = normalizeList(effects.flags or effects.cityStateFlags or effects.worldFlags)
    if #flags > 0 then
        controller.cityState.flags = controller.cityState.flags or {}
        for _, flag in ipairs(flags) do
            local key = tostring(flag or "")
            if key ~= "" then
                controller.cityState.flags[key] = true
                detail.cityStateFlags[#detail.cityStateFlags + 1] = key
            end
        end
    end

    local projectFlags = normalizeList(effects.projectFlags)
    if #projectFlags > 0 then
        project.flags = project.flags or {}
        for _, flag in ipairs(projectFlags) do
            local key = tostring(flag or "")
            if key ~= "" then
                project.flags[key] = true
                detail.projectFlags[#detail.projectFlags + 1] = key
            end
        end
    end

    local rosterEffects = effects.guildRoster or effects.roster
    if type(rosterEffects) == "table" then
        for key, records in pairs(rosterEffects) do
            local added = appendRosterRecords(controller.guildRoster, key, records)
            if #added > 0 then
                detail.rosterUpdates[key] = added
            end
        end
    end

    project.completedBy = actor
    project.completedById = actorId(actor)
    project.completionEffects = effects
    project.completionDetail = detail
    project.completionEffectsApplied = true
    return detail
end

local function applyRestockStateUpdates(controller, mapUpdates, factionUpdates)
    local state = controller.underworldState or controller.cityState.underworldState or {}
    controller.underworldState = state
    controller.cityState.underworldState = state
    state.rooms = state.rooms or {}
    state.factions = state.factions or {}

    local detail = {
        mapStateUpdates = {},
        factionStateUpdates = {},
    }

    for _, update in ipairs(mapUpdates or {}) do
        if type(update) == "table" then
            local roomId = update.roomId or update.room or update.locationId or update.id
            if roomId then
                roomId = tostring(roomId)
                local roomState = state.rooms[roomId] or {}
                state.rooms[roomId] = roomState
                roomState.history = roomState.history or {}
                roomState.history[#roomState.history + 1] = shallowClone(update)
                mergeSupportState(roomState, update)
                detail.mapStateUpdates[#detail.mapStateUpdates + 1] = {
                    roomId = roomId,
                    state = roomState,
                    update = shallowClone(update),
                }
            end
        end
    end

    for _, update in ipairs(factionUpdates or {}) do
        if type(update) == "table" then
            local factionId = update.factionId or update.faction or update.id or update.name
            if factionId then
                factionId = slugify(factionId)
                local factionState = state.factions[factionId] or {}
                state.factions[factionId] = factionState
                factionState.id = factionState.id or factionId
                factionState.history = factionState.history or {}
                factionState.history[#factionState.history + 1] = shallowClone(update)
                mergeSupportState(factionState, update)

                local strengthDelta = tonumber(update.strengthDelta or update.powerDelta or update.influenceDelta)
                if strengthDelta then
                    factionState.strength = (tonumber(factionState.strength) or 0) + strengthDelta
                end
                local heatDelta = tonumber(update.heatDelta or update.alertDelta or update.threatDelta)
                if heatDelta then
                    factionState.heat = (tonumber(factionState.heat) or 0) + heatDelta
                end

                detail.factionStateUpdates[#detail.factionStateUpdates + 1] = {
                    factionId = factionId,
                    state = factionState,
                    update = shallowClone(update),
                }
            end
        end
    end

    return detail
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

local function carouseFactionState(cityState, factionId)
    if not cityState or not factionId then
        return nil
    end
    local id = slugify(factionId)
    cityState.factions = cityState.factions or {}
    local faction = cityState.factions[id] or {}
    cityState.factions[id] = faction
    faction.id = faction.id or id
    faction.history = faction.history or {}
    return faction, id
end

local function applyCarouseFactionHeat(cityState, record)
    if not record.factionId or not record.heatDelta then
        return
    end
    local faction = carouseFactionState(cityState, record.factionId)
    if not faction then
        return
    end
    faction.heat = (tonumber(faction.heat) or 0) + record.heatDelta
    faction.history[#faction.history + 1] = {
        source = "carouse",
        type = record.type,
        actorId = record.actorId,
        hangoverId = record.hangoverId,
        heatDelta = record.heatDelta,
        notes = record.notes,
    }
end

local function carouseConsequenceDrafts(outcome)
    if not outcome or outcome.applied == false then
        return {}
    end

    local id = outcome.id
    if id == "stocks" then
        return {
            { type = "public_humiliation", category = "social", legalHeatDelta = 1, notes = "left in the stocks" },
        }
    elseif id == "cowbell" then
        return {
            { type = "noisy_reputation", category = "social", stealthDisfavor = true, notes = "cowbell chain" },
        }
    elseif id == "marriage_ring" then
        return {
            { type = "unknown_spouse", category = "social", relationshipHook = true },
        }
    elseif id == "angry_creditors" then
        return {
            { type = "angry_creditors", category = "social", factionId = "creditors", heatDelta = 1 },
        }
    elseif id == "high_priest" then
        return {
            {
                type = "clergy_scandal",
                category = "social",
                factionId = "temple_authorities",
                heatDelta = 1,
                figure = outcome.figure,
            },
        }
    elseif id == "tavern_ban" then
        return {
            { type = "tavern_ban", category = "social", venue = "favorite_tavern" },
        }
    elseif id == "wanted_poster" then
        return {
            {
                type = "wanted_poster",
                category = "social",
                factionId = "all_watch",
                heatDelta = 2,
                legalHeatDelta = 2,
                charge = outcome.charge,
            },
        }
    elseif id == "soul_invoice" then
        return {
            { type = "infernal_contract", category = "world", factionId = "infernal_powers", heatDelta = 1 },
        }
    elseif id == "hogtied_noble" then
        return {
            { type = "noble_scandal", category = "social", factionId = "nobility", heatDelta = 1 },
        }
    elseif id == "broken_shop" then
        return {
            { type = "merchant_restitution", category = "social", factionId = "merchants", heatDelta = 1 },
        }
    elseif id == "candle_fire" then
        return {
            {
                type = "district_fire",
                category = "world",
                districtsBurned = outcome.districtsBurned,
                fireSpirit = outcome.fireSpirit,
                factionId = outcome.fireSpirit and "sorcerers" or nil,
                heatDelta = outcome.fireSpirit and 1 or nil,
            },
        }
    elseif id == "dark_pact" then
        return {
            { type = "dark_pact_obligation", category = "world", factionId = "dark_pact_cult", heatDelta = 1 },
        }
    elseif id == "missing_hand" then
        return {
            { type = "crawling_missing_hand", category = "world", bodyHorror = true },
        }
    elseif id == "puncture_marks" then
        return {
            { type = "blood_attention", category = "world", factionId = "blood_drinkers", heatDelta = 1 },
        }
    end

    return {}
end

local function recordCarouseConsequences(controller, actor, hangover, outcome, opts)
    opts = opts or {}
    local cityState = opts.cityState or opts.worldState or controller.cityState
    local drafts = carouseConsequenceDrafts(outcome)
    local records = {}
    if #drafts == 0 then
        return records
    end

    cityState.carouseConsequences = cityState.carouseConsequences or {}
    cityState.socialConsequences = cityState.socialConsequences or {}
    cityState.worldConsequences = cityState.worldConsequences or {}
    actor.carouseConsequences = actor.carouseConsequences or {}

    for _, draft in ipairs(drafts) do
        local record = shallowClone(draft)
        record.source = "carouse"
        record.actorId = actorId(actor)
        record.actorName = actor and actor.name
        record.hangoverId = outcome.id
        record.hangoverTitle = outcome.title or (hangover and hangover.title)
        record.result = "carouse_consequence_recorded"

        cityState.carouseConsequences[#cityState.carouseConsequences + 1] = record
        actor.carouseConsequences[#actor.carouseConsequences + 1] = record
        if record.category == "social" then
            cityState.socialConsequences[#cityState.socialConsequences + 1] = record
        end
        if record.category == "world" then
            cityState.worldConsequences[#cityState.worldConsequences + 1] = record
        end
        if record.legalHeatDelta then
            cityState.legalHeat = (tonumber(cityState.legalHeat) or 0) + record.legalHeatDelta
        end
        if record.type == "district_fire" then
            cityState.carouseDistrictsBurned = (tonumber(cityState.carouseDistrictsBurned) or 0) +
                math.max(0, math.floor(tonumber(record.districtsBurned) or 0))
            if record.fireSpirit then
                cityState.roamingFireSpirit = true
            end
        end
        applyCarouseFactionHeat(cityState, record)
        records[#records + 1] = record
    end

    return records
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
    context.cityAction = true
    context.cityPhase = true
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
    local rawSyllables = request.syllables or request.syllableCount
    local syllables = tonumber(rawSyllables)
    if syllables then
        if syllables ~= math.floor(syllables) then
            return nil, "Syllable count must be a whole number"
        end
        return math.max(0, syllables)
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

function M.getPrepareComponentOptions(opts)
    opts = opts or {}
    local actor = opts.actor or opts
    local availablePackSlots = nil
    if actor and actor.inventory and actor.inventory.availableSlots then
        availablePackSlots = actor.inventory:availableSlots(inventory.LOCATIONS.PACK)
    end

    local options = {}
    for _, spell in ipairs(spell_registry.listSpells()) do
        local componentId = spell.componentId
        local template = componentId and item_templates.getTemplate(componentId)
        local props = template and template.properties or {}
        if componentId and template and props.spellComponent == true then
            local size = template.stackable and 1 or template.size or 1
            local option = {
                id = componentId,
                componentId = componentId,
                componentName = template.name or componentId,
                spellId = spell.id,
                spellName = spell.name or spell.id,
                branch = spell.branch or props.branch,
                talent = spell.talent,
                targetMode = spell.targetMode,
                componentAction = spell.effect and spell.effect.componentAction or nil,
                slots = size,
                label = (spell.name or spell.id) .. " - " .. (template.name or componentId),
            }
            if availablePackSlots ~= nil and availablePackSlots < size then
                option.disabled = true
                option.unavailableReason = "insufficient_pack_slots"
            end
            options[#options + 1] = option
        end
    end

    table.sort(options, function(a, b)
        local aBranch = tostring(a.branch or "")
        local bBranch = tostring(b.branch or "")
        if aBranch ~= bBranch then
            return aBranch < bBranch
        end
        return tostring(a.spellName or a.spellId) < tostring(b.spellName or b.spellId)
    end)

    return options
end

local function normalizeTalentId(talentId)
    return talent_catalog.normalizeId(talentId)
end

local function requestedTrainingXP(request)
    local rawAmount = request.xp or request.amount or request.xpInvested
    local xpAmount = tonumber(rawAmount)
    if not xpAmount then
        xpAmount = 1
    end
    if xpAmount < 1 or xpAmount ~= math.floor(xpAmount) then
        return nil, "Training XP must be a positive whole number"
    end
    return xpAmount
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

function M.formatTalentLabel(talentId)
    local text = tostring(talentId or "Talent"):gsub("_", " ")
    return text:gsub("(%a)([%w']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
end

function M.getCityTrainingOptions(opts)
    opts = opts or {}
    local actor = opts.actor or opts
    local gold = actor and currency.getGold(actor) or 0
    local costPerXP = M.TRAINING_COST_PER_XP
    local maxAffordableXP = math.floor(gold / costPerXP)
    local actorPath = talent_catalog.getActorPath(actor)
    local paths = { "swords", "pentacles", "cups", "wands" }
    local unavailableExperts = opts.unavailableExperts or opts.unavailableTalents or {}
    local availableExperts = opts.availableExperts or opts.trainersAvailable
    if type(unavailableExperts) ~= "table" then
        unavailableExperts = {}
    end

    local function hasExpert(talentId, path)
        if opts.trainerAvailable == false then
            return false
        end
        if unavailableExperts[talentId] == true or unavailableExperts[path] == true then
            return false
        end
        if type(availableExperts) == "table" and
           (availableExperts[talentId] == false or availableExperts[path] == false) then
            return false
        end
        return true
    end

    local options = {}
    for _, path in ipairs(paths) do
        for _, talentId in ipairs(talent_catalog.PATH_TALENTS[path] or {}) do
            local normalizedTalentId = normalizeTalentId(talentId)
            local existingTalent = getTalentEntry(actor, normalizedTalentId)
            local currentXP = type(existingTalent) == "table" and
                math.max(0, math.floor(tonumber(existingTalent.xp_invested) or 0)) or 0
            local mastered = type(existingTalent) == "table" and existingTalent.mastered == true
            local expertAvailable = hasExpert(normalizedTalentId, path)
            local trainingOk, training = talent_catalog.validateTraining(actor, normalizedTalentId, {
                cityExpert = true,
                trainerAvailable = expertAvailable,
            })
            training = training or {}
            local xpNeeded = mastered and 0 or math.max(1, 7 - currentXP)
            local maxInvestableXP = mastered and 0 or math.min(maxAffordableXP, xpNeeded)
            local xpOptions = {}
            for xp = 1, maxInvestableXP do
                xpOptions[#xpOptions + 1] = {
                    xp = xp,
                    cost = xp * costPerXP,
                    totalXPInvested = currentXP + xp,
                    mastersTalent = currentXP + xp >= 7,
                }
            end

            local disabled = false
            local unavailableReason = nil
            if not trainingOk then
                disabled = true
                unavailableReason = training.reason
            elseif mastered then
                disabled = true
                unavailableReason = "Talent already mastered"
            elseif maxAffordableXP < 1 then
                disabled = true
                unavailableReason = "Not enough gold"
            end

            options[#options + 1] = {
                id = normalizedTalentId,
                talentId = normalizedTalentId,
                talentName = M.formatTalentLabel(normalizedTalentId),
                label = M.formatTalentLabel(normalizedTalentId),
                path = path,
                actorPath = actorPath ~= "" and actorPath or nil,
                ownPath = training.ownPath == true,
                mentored = training.mentored == true,
                cityExpert = training.mentored == true,
                trainerAvailable = expertAvailable,
                currentXP = currentXP,
                xpNeededForMastery = xpNeeded,
                costPerXP = costPerXP,
                maxAffordableXP = maxAffordableXP,
                maxInvestableXP = maxInvestableXP,
                xpOptions = xpOptions,
                mastered = mastered,
                disabled = disabled,
                unavailableReason = unavailableReason,
            }
        end
    end

    return options
end

local function hasUsableTalent(actor, talentId)
    local talent = getTalentEntry(actor, talentId)
    if type(talent) == "table" then
        return talent.wounded ~= true
    end
    return talent == true
end

function M.getGoblinHordeOptions(opts)
    opts = opts or {}
    local request = opts.request or opts.horde or opts
    local actor = opts.actor or request.actor
    local active = isActiveAdventurer(actor)
    local currentXP = math.max(0, tonumber(actor and actor.xp) or 0)
    local currentWholeXP = math.floor(currentXP)
    local maxGoblins = 8
    local baseGoblinRecruitment = 2
    local horde = nil
    for _, companion in ipairs(actor and actor.animalCompanions or {}) do
        if type(companion) == "table" and companion.goblinHorde == true then
            horde = companion
            break
        end
    end

    local existingCount = math.max(0, math.floor(tonumber(horde and (horde.goblinCount or horde.count)) or 0))
    local available = math.max(0, maxGoblins - existingCount)
    local hasJarl = hasUsableTalent(actor, "jarl")
    local alreadyActed = false
    if type(opts.actionsCompleted) == "table" then
        alreadyActed = opts.actionsCompleted[actorId(actor)] ~= nil
    end

    local selectedXP = firstProvided(request.xp, request.xpSpent, request.amount)
    local selectedProvided = selectedXP ~= nil
    selectedXP = tonumber(selectedXP)
    local function recruitmentPreview(xpSpend)
        local requested = baseGoblinRecruitment + xpSpend
        local recruited = math.min(requested, available)
        return {
            xp = xpSpend,
            xpSpent = xpSpend,
            xpAfter = currentXP - xpSpend,
            requestedGoblins = requested,
            recruited = recruited,
            projectedGoblinCount = existingCount + recruited,
            projectedPorterSlots = existingCount + recruited,
            capped = recruited < requested,
            disabled = not active or not hasJarl or alreadyActed or available <= 0 or currentXP < xpSpend,
            unavailableReason = not active and "No active adventurer" or
                (not hasJarl and "Requires Jarl talent") or
                (alreadyActed and "City Action already taken") or
                (available <= 0 and "Goblin horde at capacity") or
                (currentXP < xpSpend and "Not enough XP") or nil,
        }
    end

    local xpOptions = {}
    for xp = 0, currentWholeXP do
        xpOptions[#xpOptions + 1] = recruitmentPreview(xp)
    end

    local selectedPreview = nil
    local disabled = not active or not hasJarl or alreadyActed or available <= 0
    local unavailableReason = not active and "No active adventurer" or
        (not hasJarl and "Requires Jarl talent") or
        (alreadyActed and "City Action already taken") or
        (available <= 0 and "Goblin horde at capacity") or nil
    if selectedProvided then
        if selectedXP == nil then
            disabled = true
            unavailableReason = "Jarl XP must be a whole number"
        elseif selectedXP < 0 then
            disabled = true
            unavailableReason = "XP spend cannot be negative"
        elseif selectedXP ~= math.floor(selectedXP) then
            disabled = true
            unavailableReason = "Jarl XP must be a whole number"
        elseif currentXP < selectedXP then
            disabled = true
            unavailableReason = "Not enough XP"
        else
            selectedPreview = recruitmentPreview(selectedXP)
            if selectedPreview.disabled then
                disabled = true
                unavailableReason = selectedPreview.unavailableReason
            end
        end
    end

    return {
        action = M.ACTIONS.ASSEMBLE_GOBLIN_HORDE,
        actor = actor,
        actorId = actorId(actor),
        actorName = actor and actor.name,
        active = active,
        hasJarl = hasJarl,
        alreadyActed = alreadyActed,
        currentXP = currentXP,
        maxSpendableXP = currentWholeXP,
        existingHorde = horde,
        existingGoblinCount = existingCount,
        maxGoblins = maxGoblins,
        availableGoblinSlots = available,
        baseGoblinRecruitment = baseGoblinRecruitment,
        countsAsAnimalCompanion = true,
        countsAsOneCreature = true,
        suppliesOwnFood = true,
        oneWordCommandsOnly = true,
        porterSlotsPerGoblin = 1,
        xpOptions = xpOptions,
        selectedXP = selectedXP,
        selectedPreview = selectedPreview,
        disabled = disabled,
        unavailableReason = unavailableReason,
        resultPreview = selectedPreview and not disabled and "goblin_horde_assembled" or nil,
    }
end

function M.getRetirementChoiceOptions(opts)
    opts = opts or {}
    local request = opts.request or opts.retirement or opts.newQuestDeclaration or opts
    local adventurer = request.adventurer or request.retiree or request.completedAdventurer or opts.retiree or opts.actor
    local successor = request.newAdventurer or request.successor or request.nextAdventurer or request.heir or opts.successor
    local questComplete = request.questCompleted == true or request.questComplete == true or
        (request.completedQuest ~= nil and request.completedQuest ~= false) or
        adventurer and (
            adventurer.questCompleted == true or
            (adventurer.completedQuest ~= nil and adventurer.completedQuest ~= false) or
            adventurer.questStatus == "complete" or
            (type(adventurer.quest) == "table" and adventurer.quest.completed == true)
        )
    local living = adventurer ~= nil and not isDeadAdventurer(adventurer) and
        adventurer.lost ~= true and adventurer.status ~= "lost"
    local retiredXP = tonumber(request.retiredXP or request.previousXP or adventurer and (adventurer.xp or adventurer.XP)) or 0
    retiredXP = math.max(0, math.floor(retiredXP))
    local benefitSlots = math.floor(retiredXP / 10)

    local benefitRequests = {}
    local function addBenefit(raw)
        if type(raw) == "table" then
            local count = math.max(1, math.floor(tonumber(raw.count or raw.amount) or 1))
            local kind = normalizeTalentId(raw.type or raw.kind or "")
            if kind == "arete" or kind == "arete_check" or kind == "arete_check_mark" or raw.areteCheck == true then
                for _ = 1, count do
                    benefitRequests[#benefitRequests + 1] = {
                        type = "arete_check",
                        triggerId = raw.triggerId or raw.trigger or raw.areteTrigger or raw.id or raw.name,
                    }
                end
            else
                benefitRequests[#benefitRequests + 1] = {
                    type = "mastered_talent",
                    talentId = normalizeTalentId(raw.talentId or raw.talent or raw.id or raw.name),
                }
            end
        elseif raw ~= nil then
            benefitRequests[#benefitRequests + 1] = {
                type = "mastered_talent",
                talentId = normalizeTalentId(raw),
            }
        end
    end
    if type(request.benefits) == "table" then
        for _, benefit in ipairs(request.benefits) do
            addBenefit(benefit)
        end
    end
    local masteredTalents = request.masteredTalents or request.masteredTalent
    if type(masteredTalents) == "table" then
        for _, talentId in ipairs(masteredTalents) do
            addBenefit({ type = "talent", talentId = talentId })
        end
    else
        addBenefit(masteredTalents)
    end
    if request.talentId or request.talent then
        addBenefit({ type = "talent", talentId = request.talentId or request.talent })
    end
    local areteChecks = math.max(0, math.floor(tonumber(request.areteChecks or request.areteCheckMarks or
        request.areteMarks) or 0))
    for _ = 1, areteChecks do
        addBenefit({ type = "arete_check" })
    end

    local benefitChoices = {
        {
            type = "mastered_talent",
            label = "1 mastered talent from any path",
            slots = 1,
        },
        {
            type = "arete_check",
            label = "1 arete check mark",
            slots = 1,
        },
    }
    local roster = opts.guildRoster or opts.roster
    local rosterAdventurers = type(roster) == "table" and (roster.adventurers or roster.members) or nil
    local function containsActor(list, actor)
        if type(list) ~= "table" or not actor then
            return false
        end
        for _, entry in ipairs(list) do
            if actorsMatch(entry, actor) then
                return true
            end
        end
        return false
    end
    local updateRoster = request.updateRoster ~= false
    local rosterPreview = {
        updated = updateRoster,
        removeRetireeFromGuild = (updateRoster and request.removeRetiree ~= false and
            containsActor(opts.guild, adventurer)) or false,
        removeRetireeFromRoster = (updateRoster and request.removeRetiree ~= false and
            containsActor(rosterAdventurers, adventurer)) or false,
        addSuccessorToGuild = (updateRoster and successor ~= nil and request.addSuccessorToGuild ~= false and
            not containsActor(opts.guild, successor)) or false,
        addSuccessorToRoster = (updateRoster and successor ~= nil and request.addSuccessorToGuild ~= false and
            not containsActor(rosterAdventurers, successor)) or false,
        markSuccessorActed = successor ~= nil and request.markSuccessorActed ~= false,
    }

    local retirementDisabled = false
    local retirementReason = nil
    if not adventurer then
        retirementDisabled = true
        retirementReason = "Retiring adventurer required"
    elseif not questComplete then
        retirementDisabled = true
        retirementReason = "Quest must be complete"
    elseif not living then
        retirementDisabled = true
        retirementReason = "Retirement requires a living adventurer"
    elseif #benefitRequests > benefitSlots then
        retirementDisabled = true
        retirementReason = "Retirement benefits exceed available slots"
    elseif #benefitRequests > 0 and not successor then
        retirementDisabled = true
        retirementReason = "Successor adventurer required"
    end

    local newQuest = request.newQuest or request.nextQuest or request.questTitle or request.objective or request.quest
    if type(newQuest) == "string" then
        newQuest = newQuest:gsub("^%s+", ""):gsub("%s+$", "")
        if newQuest == "" then
            newQuest = nil
        end
    end
    local newQuestDisabled = false
    local newQuestReason = nil
    if not adventurer then
        newQuestDisabled = true
        newQuestReason = "Adventurer required"
    elseif not questComplete then
        newQuestDisabled = true
        newQuestReason = "Quest must be complete"
    elseif not living then
        newQuestDisabled = true
        newQuestReason = "New quest requires a living adventurer"
    elseif not newQuest then
        newQuestDisabled = true
        newQuestReason = "New quest required"
    end

    local previousQuest = request.completedQuest or request.previousQuest or
        adventurer and (adventurer.completedQuest or adventurer.quest)
    return {
        actor = adventurer,
        actorId = actorId(adventurer),
        actorName = adventurer and adventurer.name,
        previousQuest = previousQuest,
        questComplete = questComplete == true,
        living = living == true,
        retiredXP = retiredXP,
        benefitSlots = benefitSlots,
        benefitChoices = benefitChoices,
        selectedBenefits = benefitRequests,
        selectedBenefitCount = #benefitRequests,
        unspentBenefitSlots = math.max(0, benefitSlots - #benefitRequests),
        successor = successor,
        successorId = actorId(successor),
        rosterPreview = rosterPreview,
        retirement = {
            action = M.ACTIONS.RETIRE_ADVENTURER,
            disabled = retirementDisabled,
            unavailableReason = retirementReason,
            resultPreview = not retirementDisabled and "adventurer_retired" or nil,
            benefitSlots = benefitSlots,
            selectedBenefits = benefitRequests,
            unspentBenefitSlots = math.max(0, benefitSlots - #benefitRequests),
            rosterPreview = rosterPreview,
        },
        newQuest = {
            action = M.ACTIONS.DECLARE_NEW_QUEST,
            quest = newQuest,
            previousQuest = previousQuest,
            xpGained = 3,
            projectedXP = adventurer and (tonumber(adventurer.xp) or 0) + 3 or nil,
            disabled = newQuestDisabled,
            unavailableReason = newQuestReason,
            resultPreview = not newQuestDisabled and "new_quest_declared" or nil,
        },
    }
end

local function normalizeProjectId(projectId)
    return tostring(projectId or ""):lower():gsub("%s+", "_"):gsub("[^%w_]", "")
end

function M.getSupportContributionOptions(opts)
    opts = opts or {}
    local actor = opts.actor or opts
    local gold = opts.gold
    if gold == nil and actor then
        gold = currency.getGold(actor)
    end
    gold = math.max(0, math.floor(tonumber(gold) or 0))

    local options = {}
    for i = #M.SUPPORT_CONTRIBUTION_IMPACTS, 1, -1 do
        local band = M.SUPPORT_CONTRIBUTION_IMPACTS[i]
        local disabled = gold < band.minimumGold
        options[#options + 1] = {
            id = band.id,
            label = band.label,
            contribution = band.minimumGold,
            minimumGold = band.minimumGold,
            impact = M.classifySupportContributionImpact(band.minimumGold),
            disabled = disabled,
            unavailableReason = disabled and "Not enough gold" or nil,
        }
    end
    return options
end

function M.getSupportProjectOptions(opts)
    opts = opts or {}
    local projects = opts.projects or opts.cityProjects or {}
    local contributionOptions = M.getSupportContributionOptions(opts)
    local options = {}

    for key, project in pairs(projects) do
        if type(project) == "table" then
            local projectId = normalizeProjectId(project.id or project.projectId or key)
            local complexity = math.max(1, math.floor(tonumber(project.complexity) or 1))
            local progress = math.max(0, math.floor(tonumber(project.progress) or 0))
            local complete = project.complete == true or progress >= complexity
            options[#options + 1] = {
                id = projectId,
                projectId = projectId,
                name = project.name or project.title or projectId,
                progress = progress,
                complexity = complexity,
                remainingSteps = math.max(0, complexity - progress),
                complete = complete,
                contributions = project.contributions or {},
                contributionCount = #(project.contributions or {}),
                contributionOptions = contributionOptions,
                disabled = complete,
                unavailableReason = complete and "Project already complete" or nil,
            }
        end
    end

    table.sort(options, function(a, b)
        return tostring(a.name or a.projectId) < tostring(b.name or b.projectId)
    end)
    return options
end

function M.getBuildProjectOption(opts)
    opts = opts or {}
    local actor = opts.actor or opts
    local request = opts.request or opts.build or opts.project or opts
    local description = tostring(request.description or request.name or request.title or "")
    local projectId = description ~= "" and normalizeProjectId(request.projectId or request.id or description) or nil
    local syllables, syllableError = resolveSyllables(request)
    if syllables and description == "" then
        syllables = 0
    end

    local gold = actor and currency.getGold(actor) or tonumber(opts.gold) or 0
    local cost = syllables and syllables * M.BUILD_COST_PER_SYLLABLE or nil
    local buildings = opts.buildings or opts.existingBuildings or {}
    local cityLayout = request.cityLayout or opts.cityLayout
    local districtInput = request.district or request.cityDistrict or request.districtRecord
    local districtId = request.districtId or request.cityDistrictId or request.district_id
    local districtName = request.districtName or request.cityDistrictName
    if type(districtInput) == "table" then
        districtId = districtId or districtInput.id or districtInput.districtId
        districtName = districtName or districtInput.name or districtInput.title
    elseif districtInput then
        districtId = districtId or districtInput
        districtName = districtName or districtInput
    end

    local districtPlacement = nil
    if cityLayout and districtId then
        districtPlacement = findDistrictPlacement(cityLayout, districtId)
        if districtPlacement and not districtName then
            districtName = districtPlacement.district and districtPlacement.district.name or districtPlacement.districtName
        end
    end

    local districtOptions = {}
    for _, placement in ipairs(cityLayout and cityLayout.districts or {}) do
        local id = cityLayoutDistrictId(placement)
        districtOptions[#districtOptions + 1] = {
            id = id,
            districtId = id,
            name = placement.district and placement.district.name or placement.districtName or id,
            selected = districtId ~= nil and tostring(id or "") == tostring(districtId or ""),
        }
    end

    local disabled = false
    local unavailableReason = nil
    if request.reasonable == false or request.approved == false then
        disabled = true
        unavailableReason = "Building project not approved"
    elseif description == "" then
        disabled = true
        unavailableReason = "Building description required"
    elseif not syllables then
        disabled = true
        unavailableReason = syllableError
    elseif syllables <= 0 then
        disabled = true
        unavailableReason = "Building description required"
    elseif projectId and buildings[projectId] then
        disabled = true
        unavailableReason = "Building project already exists"
    elseif cityLayout and districtId and not districtPlacement and request.requireDistrict ~= false then
        disabled = true
        unavailableReason = "City district not found"
    elseif cost and gold < cost then
        disabled = true
        unavailableReason = "Not enough gold"
    end

    return {
        action = M.ACTIONS.BUILD,
        description = description ~= "" and description or nil,
        projectId = projectId,
        name = request.name or request.title or description,
        syllables = syllables,
        syllableError = syllableError,
        costPerSyllable = M.BUILD_COST_PER_SYLLABLE,
        cost = cost,
        gold = gold,
        affordable = cost ~= nil and gold >= cost,
        requiresGMApproval = true,
        approved = request.approved ~= false and request.reasonable ~= false,
        artisan = request.artisan or request.designer,
        districtId = districtId,
        districtName = districtName,
        districtFound = districtId == nil or districtPlacement ~= nil,
        districtOptions = districtOptions,
        disabled = disabled,
        unavailableReason = unavailableReason,
    }
end

function M.getFuneralOptions(opts)
    opts = opts or {}
    local actor = opts.actor or opts
    local request = opts.request or opts.funeral or opts
    local deceasedRef = request.deceased or request.deadAdventurer or request.previousAdventurer
    local deceasedId = request.deceasedId or request.deadAdventurerId or request.previousAdventurerId
    local heir = request.newAdventurer or request.heir or request.recipient or actor
    local gold = actor and currency.getGold(actor) or tonumber(opts.gold) or 0

    local candidates = {}
    local seen = {}
    local function addCandidate(candidate)
        if type(candidate) ~= "table" then
            return
        end
        local id = actorId(candidate) or candidate.name
        local key = tostring(id or (#candidates + 1))
        if seen[key] then
            return
        end
        seen[key] = true
        candidates[#candidates + 1] = candidate
    end

    for _, candidate in ipairs(normalizeList(opts.deceasedOptions or opts.deceasedAdventurers or opts.deadAdventurers)) do
        addCandidate(candidate)
    end
    addCandidate(deceasedRef)
    for _, candidate in ipairs(getRosterAdventurers(opts.guildRoster or opts.roster) or {}) do
        addCandidate(candidate)
    end
    for _, candidate in ipairs(opts.guild or {}) do
        addCandidate(candidate)
    end

    local selectedDeceased = type(deceasedRef) == "table" and deceasedRef or nil
    if not selectedDeceased and deceasedId then
        for _, candidate in ipairs(candidates) do
            if tostring(actorId(candidate) or "") == tostring(deceasedId) then
                selectedDeceased = candidate
                break
            end
        end
    end

    local deceasedOptions = {}
    for _, candidate in ipairs(candidates) do
        local candidateXP = math.max(0, math.floor(tonumber(candidate.xp) or 0))
        local selected = selectedDeceased == candidate or
            (deceasedId ~= nil and tostring(actorId(candidate) or "") == tostring(deceasedId))
        local xpOptions = {}
        for xp = 1, candidateXP do
            local cost = xp * M.FUNERAL_COST_PER_XP
            xpOptions[#xpOptions + 1] = {
                xp = xp,
                cost = cost,
                affordable = gold >= cost,
                disabled = gold < cost,
                unavailableReason = gold < cost and "Not enough gold" or nil,
            }
        end
        deceasedOptions[#deceasedOptions + 1] = {
            id = actorId(candidate),
            actor = candidate,
            name = candidate.name or actorId(candidate),
            previousXP = candidateXP,
            maxReclaimableXP = candidateXP,
            dead = isDeadAdventurer(candidate),
            funeralHeld = candidate.funeralHeld == true,
            selected = selected,
            disabled = not isDeadAdventurer(candidate),
            unavailableReason = not isDeadAdventurer(candidate) and "Adventurer must be dead" or nil,
            xpOptions = xpOptions,
        }
    end

    table.sort(deceasedOptions, function(a, b)
        return tostring(a.name or a.id) < tostring(b.name or b.id)
    end)

    local previousXP = tonumber(request.previousXP or request.deceasedXP or (selectedDeceased and selectedDeceased.xp))
    local xpReclaimed = tonumber(request.xpReclaimed or request.xp or request.amount)
    local cost = xpReclaimed and xpReclaimed * M.FUNERAL_COST_PER_XP or nil
    local xpOptions = {}
    if previousXP and previousXP > 0 then
        for xp = 1, math.floor(previousXP) do
            local optionCost = xp * M.FUNERAL_COST_PER_XP
            xpOptions[#xpOptions + 1] = {
                xp = xp,
                cost = optionCost,
                affordable = gold >= optionCost,
                selected = xpReclaimed == xp,
                disabled = gold < optionCost,
                unavailableReason = gold < optionCost and "Not enough gold" or nil,
            }
        end
    end

    local disabled = false
    local unavailableReason = nil
    if not xpReclaimed or xpReclaimed <= 0 then
        disabled = true
        unavailableReason = "Funeral XP required"
    elseif xpReclaimed ~= math.floor(xpReclaimed) then
        disabled = true
        unavailableReason = "Funeral XP must be a positive whole number"
    elseif not previousXP then
        disabled = true
        unavailableReason = "Deceased XP required"
    elseif selectedDeceased and not isDeadAdventurer(selectedDeceased) then
        disabled = true
        unavailableReason = "Adventurer must be dead"
    elseif xpReclaimed > previousXP then
        disabled = true
        unavailableReason = "Cannot reclaim more XP than the deceased had"
    elseif not heir then
        disabled = true
        unavailableReason = "Funeral recipient required"
    elseif cost and gold < cost then
        disabled = true
        unavailableReason = "Not enough gold"
    end

    return {
        action = M.ACTIONS.HOLD_FUNERAL,
        actor = actor,
        payerGold = gold,
        costPerXP = M.FUNERAL_COST_PER_XP,
        deceased = selectedDeceased,
        deceasedId = selectedDeceased and actorId(selectedDeceased) or deceasedId,
        deceasedName = request.deceasedName or (selectedDeceased and selectedDeceased.name),
        previousXP = previousXP,
        xpReclaimed = xpReclaimed,
        cost = cost,
        affordable = cost ~= nil and gold >= cost,
        recipient = heir,
        recipientId = actorId(heir),
        recipientName = heir and heir.name,
        deceasedOptions = deceasedOptions,
        xpOptions = xpOptions,
        updateRoster = request.updateRoster ~= false,
        removeDeceased = request.removeDeceased ~= false,
        addHeirToGuild = request.addHeirToGuild ~= false,
        disabled = disabled,
        unavailableReason = unavailableReason,
    }
end

function M.getBankingOptions(opts)
    opts = opts or {}
    local actor = opts.actor or opts
    local request = opts.request or opts.banking or opts
    local mode = tostring(request.mode or request.operation or ""):lower()
    local withdrawMode = mode == "withdraw" or mode == "withdrawal"
    local depositGold = math.floor(tonumber(request.depositGold or (not withdrawMode and request.gold) or
        (not withdrawMode and request.amount)) or 0)
    local withdrawGold = math.floor(tonumber(request.withdrawGold or request.goldWithdrawal or
        request.withdrawAmount or request.withdraw) or 0)
    if withdrawMode and withdrawGold <= 0 then
        withdrawGold = math.floor(tonumber(request.gold or request.amount) or 0)
    end

    local depositItemIds = normalizeList(request.depositItemIds or request.depositItems or
        (not withdrawMode and request.itemIds) or (not withdrawMode and request.items) or
        (not withdrawMode and request.itemId))
    local withdrawItemIds = normalizeList(request.withdrawItemIds or request.withdrawItems or request.withdrawItemId)
    if withdrawMode and #withdrawItemIds == 0 then
        withdrawItemIds = normalizeList(request.itemIds or request.items or request.itemId)
    end

    local function hasSelectedId(list, itemId)
        local wanted = tostring(itemId or "")
        for _, selectedId in ipairs(list or {}) do
            if tostring(selectedId or "") == wanted then
                return true
            end
        end
        return false
    end

    local inv = actor and actor.inventory
    local carriedGold = actor and currency.getGold(actor) or tonumber(opts.gold) or 0
    local bank = actor and actor.bank or {}
    local bankedGold = tonumber(bank.gold) or 0
    local bankedItems = bank.items or {}
    local withdrawalLocation = request.withdrawLocation or request.location or inventory.LOCATIONS.PACK
    local carriedItemOptions = {}
    for _, location in ipairs({ inventory.LOCATIONS.HANDS, inventory.LOCATIONS.BELT, inventory.LOCATIONS.PACK }) do
        for _, item in ipairs(inv and inv[location] or {}) do
            carriedItemOptions[#carriedItemOptions + 1] = {
                id = item.id,
                item = item,
                name = item.name,
                location = location,
                slots = item.stackable and 1 or item.size,
                selected = hasSelectedId(depositItemIds, item.id),
            }
        end
    end

    local bankedItemOptions = {}
    for _, item in ipairs(bankedItems) do
        local canWithdraw, reason = true, nil
        if inv and inv.addItem then
            canWithdraw, reason = canAddBankedItemsToInventory(inv, { item }, withdrawalLocation)
        elseif #withdrawItemIds > 0 or withdrawMode then
            canWithdraw, reason = false, "No inventory for banking"
        end
        bankedItemOptions[#bankedItemOptions + 1] = {
            id = item.id,
            item = item,
            name = item.name,
            slots = item.stackable and 1 or item.size,
            selected = hasSelectedId(withdrawItemIds, item.id),
            withdrawalLocation = withdrawalLocation,
            disabled = not canWithdraw,
            unavailableReason = not canWithdraw and reason or nil,
        }
    end

    local disabled = false
    local unavailableReason = nil
    if depositGold <= 0 and #depositItemIds == 0 and withdrawGold <= 0 and #withdrawItemIds == 0 then
        disabled = true
        unavailableReason = "Nothing to bank"
    elseif depositGold > 0 and carriedGold < depositGold then
        disabled = true
        unavailableReason = "Not enough gold"
    elseif withdrawGold > bankedGold then
        disabled = true
        unavailableReason = "Not enough banked gold"
    elseif #depositItemIds > 0 and (not inv or not inv.findItem or not inv.removeItem) then
        disabled = true
        unavailableReason = "No inventory for banking"
    else
        for _, itemId in ipairs(depositItemIds) do
            if inv and inv.findItem and not inv:findItem(itemId) then
                disabled = true
                unavailableReason = "Banking item not found"
                break
            end
        end
        if not disabled and #withdrawItemIds > 0 and (not inv or not inv.addItem) then
            disabled = true
            unavailableReason = "No inventory for banking"
        end
        if not disabled then
            local requestedWithdrawItems = {}
            for _, itemId in ipairs(withdrawItemIds) do
                local item = findBankedItem(bank, itemId)
                if not item then
                    disabled = true
                    unavailableReason = "Banked item not found"
                    break
                end
                requestedWithdrawItems[#requestedWithdrawItems + 1] = item
            end
            if not disabled and #requestedWithdrawItems > 0 then
                local canAdd, reason = canAddBankedItemsToInventory(inv, requestedWithdrawItems, withdrawalLocation)
                if not canAdd then
                    disabled = true
                    unavailableReason = reason
                end
            end
        end
    end

    local projectedInterest = math.floor(bankedGold * M.BANKING_RETURN_RATE)
    return {
        action = M.ACTIONS.BANKING,
        operation = withdrawMode and "withdraw" or "deposit",
        carriedGold = carriedGold,
        bankedGold = bankedGold,
        returnRate = M.BANKING_RETURN_RATE,
        projectedInterest = projectedInterest,
        projectedBankedGoldAfterReturn = bankedGold + projectedInterest,
        depositGold = depositGold,
        withdrawGold = withdrawGold,
        depositItemIds = depositItemIds,
        withdrawItemIds = withdrawItemIds,
        carriedItemOptions = carriedItemOptions,
        bankedItemOptions = bankedItemOptions,
        withdrawalLocation = withdrawalLocation,
        disabled = disabled,
        unavailableReason = unavailableReason,
    }
end

function M.getBegAndBuskOptions(opts)
    opts = opts or {}
    local actor = opts.actor or opts
    local request = opts.request or opts.begAndBusk or opts.beg_and_busk or opts
    local explicitCard = request.card or request.drawnCard
    local deck = request.deck or request.playerDeck or request.minorDeck or opts.playerDeck or opts.minorDeck
    local wands = getWands(actor)
    local validCard = explicitCard and isMinorDeckCard(explicitCard) or nil
    local projectedGold = nil
    if validCard then
        projectedGold = math.max(0, (tonumber(explicitCard.value) or 0) + wands)
    end

    local disabled = false
    local unavailableReason = nil
    if explicitCard and not validCard then
        disabled = true
        unavailableReason = "Requires minor arcana draw"
    elseif not explicitCard and not deck then
        disabled = true
        unavailableReason = "Requires minor arcana draw"
    end

    return {
        action = M.ACTIONS.BEG_AND_BUSK,
        attribute = constants.SUITS.WANDS,
        wands = wands,
        deck = "minor_arcana",
        autoDrawAvailable = explicitCard == nil and deck ~= nil,
        requiresDraw = explicitCard == nil,
        card = explicitCard,
        cardValid = explicitCard == nil and nil or validCard == true,
        projectedGold = projectedGold,
        formula = "card_value_plus_wands",
        consumesCityAction = "on_success",
        disabled = disabled,
        unavailableReason = unavailableReason,
    }
end

function M.getCarouseOptions(opts)
    opts = opts or {}
    local actor = opts.actor or opts
    local request = opts.request or opts.carouse or opts
    local percent, xpGained = normalizeCarouseSpend(request)
    local baseGold = math.floor(tonumber(request.goldBroughtBack or request.broughtBackGold or request.earnings) or
        (actor and currency.getGold(actor) or tonumber(opts.gold) or 0))
    local carriedGold = actor and currency.getGold(actor) or tonumber(opts.gold) or 0
    local spend = percent and math.floor(baseGold * percent) or nil
    local explicitCard = request.hangoverCard or request.majorCard or request.card
    local deck = request.gmDeck or request.majorDeck or opts.gmDeck or opts.majorDeck
    local cardValid = explicitCard and isMajorDeckCard(explicitCard) or nil
    local hangover = cardValid and (M.HANGOVER_TABLE[explicitCard.value] or {
        id = "unknown_hangover",
        title = "Unknown Hangover",
    }) or nil

    local minorDeck = request.playerDeck or request.minorDeck or opts.playerDeck or opts.minorDeck
    local minorDiscard = nil
    if minorDeck and minorDeck.peekDiscard then
        minorDiscard = minorDeck:peekDiscard()
    end
    minorDiscard = minorDiscard or request.minorDiscardCard or request.minorDiscard or
        request.topMinorDiscardCard or request.topMinorDiscard
    local invalidMinorDiscard = nil
    if minorDiscard and not isMinorDeckCard(minorDiscard) then
        invalidMinorDiscard = minorDiscard
        minorDiscard = nil
    end

    local function previewHangoverOutcome(entry, discard)
        local outcome = {
            id = entry and entry.id or "unknown_hangover",
            title = entry and entry.title or "Unknown Hangover",
            applied = false,
        }
        local id = outcome.id
        local value = minorDiscardValue(discard)
        if id == "headache_windfall" then
            outcome.goldGained = value
            outcome.applied = value > 0
            outcome.requiresMinorDiscard = value <= 0
        elseif id == "high_priest" then
            if value <= 0 then
                outcome.requiresMinorDiscard = true
            else
                outcome.figure = (value % 2 == 0) and "high_priest" or "high_priestess"
                outcome.applied = true
            end
        elseif id == "new_tattoo" then
            local location = minorSuitChoice(discard, {
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
                outcome.applied = true
            end
        elseif id == "duel_invitation" then
            if value <= 0 then
                outcome.requiresMinorDiscard = true
            else
                outcome.duelInDays = value
                outcome.applied = true
            end
        elseif id == "wanted_poster" then
            local charge = minorSuitChoice(discard, {
                swords = "armed_robbery",
                pentacles = "attempted_pickpocketing",
                cups = "lewd_acts",
                wands = "consorting_with_dark_entities",
            })
            if not charge then
                outcome.requiresMinorDiscard = true
            else
                outcome.charge = charge
                outcome.applied = true
            end
        elseif id == "candle_fire" then
            local fire = minorSuitChoice(discard, {
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
                outcome.applied = true
            end
        elseif entry then
            outcome.applied = true
        else
            outcome.requiresAdjudication = true
        end
        return outcome
    end

    local spendOptions = {}
    for _, option in ipairs({
        { id = "half", percent = 0.5, xp = 1 },
        { id = "all", percent = 1, xp = 2 },
    }) do
        local optionSpend = math.floor(baseGold * option.percent)
        spendOptions[#spendOptions + 1] = {
            id = option.id,
            percent = option.percent,
            xpGained = option.xp,
            baseGold = baseGold,
            goldSpent = optionSpend,
            affordable = carriedGold >= optionSpend and optionSpend > 0,
            selected = percent == option.percent,
            disabled = carriedGold < optionSpend or optionSpend <= 0,
            unavailableReason = optionSpend <= 0 and "No gold to carouse" or
                (carriedGold < optionSpend and "Not enough gold" or nil),
        }
    end

    local disabled = false
    local unavailableReason = nil
    if not percent then
        disabled = true
        unavailableReason = "Choose 50% or 100% carousing spend"
    elseif spend and spend <= 0 then
        disabled = true
        unavailableReason = "No gold to carouse"
    elseif spend and carriedGold < spend then
        disabled = true
        unavailableReason = "Not enough gold"
    elseif explicitCard and not cardValid then
        disabled = true
        unavailableReason = "Requires major arcana draw"
    elseif not explicitCard and not deck then
        disabled = true
        unavailableReason = "Requires major arcana draw"
    end

    return {
        action = M.ACTIONS.CAROUSE,
        percent = percent,
        xpGained = xpGained,
        baseGold = baseGold,
        carriedGold = carriedGold,
        goldSpent = spend,
        spendOptions = spendOptions,
        hangoverDeck = "gm_major_arcana",
        autoDrawAvailable = explicitCard == nil and deck ~= nil,
        requiresHangoverDraw = explicitCard == nil,
        hangoverCard = explicitCard,
        hangoverCardValid = explicitCard == nil and nil or cardValid == true,
        hangover = hangover,
        hangoverOutcomePreview = hangover and previewHangoverOutcome(hangover, minorDiscard) or nil,
        minorDiscard = minorDiscard,
        invalidMinorDiscard = invalidMinorDiscard,
        minorDiscardAvailable = minorDiscard ~= nil,
        disabled = disabled,
        unavailableReason = unavailableReason,
    }
end

function M.getCityCampActionOptions(opts)
    opts = opts or {}
    local actor = opts.actor or opts
    local guild = opts.guild or {}
    local context = opts.context or opts.campContext or {}
    context.guild = context.guild or guild
    context.cityAction = true
    context.cityPhase = true
    local request = opts.request or opts.campActionRequest or opts
    local selectedCampActionId = normalizeCampActionId(
        request.campAction or
        request.campActionId or
        request.camp_action or
        request.camp_action_id or
        request.campType
    )

    local availableById = {}
    for _, action in ipairs(camp_actions.getAvailableActions(actor, guild, context)) do
        availableById[action.id] = true
    end

    local function hasOtherPC()
        for _, pc in ipairs(guild or {}) do
            if pc and pc.isPC == true and actor and pc.id ~= actor.id then
                return true
            end
        end
        return false
    end

    local function reasonFor(action)
        if action.requiresItem then
            if not actor or not actor.inventory or not actor.inventory.hasItemOfType or
               not actor.inventory:hasItemOfType(action.requiresItem) then
                return "Requires " .. tostring(action.requiresItem)
            end
        end
        if action.requiresFletchAmmo and not camp_actions.hasMissileWeapon(actor) then
            return "Requires a bow or crossbow"
        end
        if action.requiresRangedAmmo and not camp_actions.canHunt(actor, context) then
            return "Requires ranged ammunition or hunting tools"
        end
        if action.requiresReadableBook and not camp_actions.hasReadableBook(actor) then
            return "Requires a readable book"
        end
        if action.requiresAlchemy and not camp_actions.canBrewAlchemy(actor) then
            return "Requires Alchemy, an alchemy kit, and bottled reagents"
        end
        if action.requiresCampUsableItem and not camp_actions.hasCampUsableItem(actor) then
            return "Requires a Camp-usable item"
        end
        if action.requiresCampTalent and not camp_actions.hasCampTalent(actor) then
            return "Requires a Camp talent"
        end
        if action.requiresActivePact and not camp_actions.findUnbrokenActivePact(actor, action.requiresActivePact) then
            return "Requires active pact"
        end
        if action.targetType == "pc" and not hasOtherPC() then
            return "Requires another guild member"
        end
        if action.targetType == "companion" and not (actor and actor.animalCompanions and #actor.animalCompanions > 0) then
            return "Requires animal companion"
        end
        return nil
    end

    local options = {}
    local selectedOption = nil
    for _, action in ipairs(camp_actions.ACTIONS) do
        local available = availableById[action.id] == true
        local option = {
            id = action.id,
            campAction = action.id,
            name = action.name,
            category = action.category,
            description = action.description,
            requiresTarget = action.requiresTarget,
            targetType = action.targetType,
            requiresItem = action.requiresItem,
            selected = selectedCampActionId == action.id,
            disabled = not available,
            unavailableReason = not available and reasonFor(action) or nil,
        }
        options[#options + 1] = option
        if option.selected then
            selectedOption = option
        end
    end

    local disabled = false
    local unavailableReason = nil
    if selectedCampActionId ~= "" then
        if not camp_actions.getAction(selectedCampActionId) then
            disabled = true
            unavailableReason = "Unknown Camp Action"
        elseif selectedOption and selectedOption.disabled then
            disabled = true
            unavailableReason = selectedOption.unavailableReason or "Camp Action unavailable"
        end
    end

    return {
        action = M.ACTIONS.CAMP_ACTION,
        selectedCampAction = selectedCampActionId ~= "" and selectedCampActionId or nil,
        selectedOption = selectedOption,
        options = options,
        availableCount = #camp_actions.getAvailableActions(actor, guild, context),
        selectionRequired = selectedCampActionId == "",
        disabled = disabled,
        unavailableReason = unavailableReason,
    }
end

function M.getResearchQuestionOptions(opts)
    opts = opts or {}
    local actor = opts.actor or opts
    local cost = M.RESEARCH_COST
    local gold = actor and currency.getGold(actor) or tonumber(opts.gold) or 0
    local engine = opts.bidLoreEngine or opts.loreEngine or bid_lore_engine.createBidLoreEngine({})
    local subjectId = opts.subjectId or opts.loreSubjectId
    local subject = subjectId and engine:getSubject(subjectId) or nil
    local topic = opts.topic or opts.subject or opts.subjectName or subject and subject.name
    local questions = subjectId and engine:getQuestionTypesForSubject(subjectId) or engine:getQuestionTypes()
    local questionOptions = {}
    for _, question in ipairs(questions or {}) do
        questionOptions[#questionOptions + 1] = {
            id = question.id,
            questionType = question.id,
            name = question.name,
            prompt = question.prompt,
            tags = shallowClone(question.tags or {}),
            answerAvailable = subject and type(subject.answers) == "table" and subject.answers[question.id] ~= nil or nil,
        }
    end

    local disabled = false
    local unavailableReason = nil
    if not topic or tostring(topic) == "" then
        disabled = true
        unavailableReason = "Research topic required"
    elseif gold < cost then
        disabled = true
        unavailableReason = "Not enough gold"
    end

    return {
        action = M.ACTIONS.RESEARCH,
        topic = topic,
        subjectId = subjectId,
        subjectName = subject and subject.name or opts.subjectName,
        cost = cost,
        gold = gold,
        affordable = gold >= cost,
        questionOptions = questionOptions,
        disabled = disabled,
        unavailableReason = unavailableReason,
    }
end

function M.summarizeResearchResult(detail)
    detail = detail or {}
    local summary = {
        action = M.ACTIONS.RESEARCH,
        topic = detail.topic,
        questions = detail.questions or 0,
        answeredCount = #(detail.answers or {}),
        pendingCount = #(detail.pendingQuestions or {}),
        overflowCount = #(detail.overflowQuestions or {}),
        answers = {},
        pendingQuestions = {},
        overflowQuestions = {},
    }

    for _, answer in ipairs(detail.answers or {}) do
        local response = answer.response or {}
        summary.answers[#summary.answers + 1] = {
            question = answer.question,
            questionType = answer.questionType,
            questionName = answer.questionName,
            subjectId = answer.subjectId,
            subjectName = answer.subjectName,
            summary = response.summary,
            source = answer.source,
            loreSpend = answer.loreSpend == true,
        }
    end

    for _, question in ipairs(detail.pendingQuestions or {}) do
        summary.pendingQuestions[#summary.pendingQuestions + 1] = {
            question = question.question,
            questionType = question.questionType,
            questionName = question.questionName,
            subjectId = question.subjectId,
            subjectName = question.subjectName,
        }
    end

    for _, question in ipairs(detail.overflowQuestions or {}) do
        summary.overflowQuestions[#summary.overflowQuestions + 1] = shallowClone(question)
    end

    return summary
end

function M.getMenagerieReagentPurchaseOptions(opts)
    opts = opts or {}
    local actor = opts.actor or opts
    local request = opts.request or opts.purchase or opts.reagentPurchase or opts
    local stock = request.stock or request.catalog or opts.stock or opts.menagerieStock or opts.catalog
    local quantity = math.max(1, tonumber(request.quantity or request.count) or 1)
    local location = request.location or opts.location or inventory.LOCATIONS.PACK
    local carriedGold = actor and currency.getGold(actor) or tonumber(opts.gold) or 0

    local function normalizeAlchemyKey(value)
        return tostring(value or ""):lower():gsub("%s+", "_")
    end

    local function templateFor(record)
        if type(record) ~= "table" then
            return record
        end
        local templateId = record.reagentTemplateId or record.templateId or record.itemTemplateId or record.template
        if templateId then
            return templateId
        end
        return alchemy.MENAGERIE_REAGENTS[normalizeAlchemyKey(record.source or record.creature or record.monster or record.reagent)]
    end

    local function isReagentTemplate(templateId)
        local template = item_templates.getTemplate(templateId)
        local props = template and template.properties or {}
        return template ~= nil and (template.type == "reagent" or props.reagent == true or
            props.alchemicalReagent == true)
    end

    local function stockQuantity(record)
        if type(record) ~= "table" then
            return nil
        end
        local value = record.quantityAvailable
        if value == nil then
            value = record.available
        end
        if value == nil then
            value = record.stock
        end
        if value == nil then
            value = record.countAvailable
        end
        return value ~= nil and math.max(0, math.floor(tonumber(value) or 0)) or nil
    end

    local stockLookup = request.stockId or request.reagentStockId or request.catalogId or request.source or
        request.creature or request.monster or request.reagent or request.reagentTemplateId or request.templateId
    local stockLookupText = tostring(stockLookup or "")
    local stockLookupKey = normalizeAlchemyKey(stockLookupText)
    local selectedStock = nil
    local selectedStockId = nil
    local stockOptions = {}
    if type(stock) == "table" then
        for key, entry in pairs(stock) do
            local record = type(entry) == "table" and entry or { id = key, reagentTemplateId = entry }
            local stockId = record.id or record.stockId or record.catalogId or key
            local templateId = templateFor(record)
            local template = item_templates.getTemplate(templateId)
            local available = stockQuantity(record)
            local costPerReagent = tonumber(record.costPerReagent or record.pricePerReagent or record.price or
                record.cost) or alchemy.MENAGERIE_REAGENT_COST
            local candidates = {
                key,
                stockId,
                record.source,
                record.creature,
                record.monster,
                record.reagent,
                templateId,
                record.name,
                record.title,
            }
            local selected = false
            for _, candidate in ipairs(candidates) do
                if stockLookupText ~= "" and candidate ~= nil then
                    local text = tostring(candidate)
                    if text == stockLookupText or normalizeAlchemyKey(text) == stockLookupKey then
                        selected = true
                        break
                    end
                end
            end
            if selected and not selectedStock then
                selectedStock = record
                selectedStockId = stockId
            end
            stockOptions[#stockOptions + 1] = {
                id = stockId,
                stockId = stockId,
                name = record.name or record.title or (template and template.name) or stockId,
                reagentTemplateId = templateId,
                reagentName = template and template.name or templateId,
                costPerReagent = costPerReagent,
                quantityAvailable = available,
                stockRemainingAfterPurchase = available and math.max(0, available - quantity) or nil,
                locationName = record.locationName or record.location,
                selected = selected,
                disabled = available ~= nil and quantity > available,
                unavailableReason = available ~= nil and quantity > available and "Reagent stock unavailable" or nil,
            }
        end
        table.sort(stockOptions, function(a, b)
            return tostring(a.name or a.stockId) < tostring(b.name or b.stockId)
        end)
    end

    local reagentOptions = {}
    for source, templateId in pairs(alchemy.MENAGERIE_REAGENTS) do
        local template = item_templates.getTemplate(templateId)
        local selected = not selectedStock and (
            request.source == source or request.creature == source or request.monster == source or
            request.reagent == source or request.reagentTemplateId == templateId or request.templateId == templateId
        )
        reagentOptions[#reagentOptions + 1] = {
            id = source,
            source = source,
            reagentTemplateId = templateId,
            name = template and template.name or templateId,
            costPerReagent = alchemy.MENAGERIE_REAGENT_COST,
            selected = selected,
        }
    end
    table.sort(reagentOptions, function(a, b)
        return tostring(a.name or a.source) < tostring(b.name or b.source)
    end)

    local selectedTemplateId = selectedStock and templateFor(selectedStock) or
        (request.reagentTemplateId or request.templateId or request.itemTemplateId or request.template or
            alchemy.MENAGERIE_REAGENTS[normalizeAlchemyKey(request.source or request.creature or request.monster or
                request.reagent)])
    local selectedTemplate = item_templates.getTemplate(selectedTemplateId)
    local selectedAvailable = stockQuantity(selectedStock)
    local costPerReagent = tonumber(opts.costPerReagent or request.costPerReagent or request.pricePerReagent or
        (selectedStock and (selectedStock.costPerReagent or selectedStock.pricePerReagent or selectedStock.price or
            selectedStock.cost))) or alchemy.MENAGERIE_REAGENT_COST
    local cost = quantity * costPerReagent
    local slotsNeeded = selectedTemplate and (selectedTemplate.stackable and 1 or selectedTemplate.size or 1) * quantity or nil
    local availableSlots = actor and actor.inventory and actor.inventory.availableSlots and actor.inventory:availableSlots(location) or nil

    local disabled = false
    local unavailableReason = nil
    if not selectedTemplateId or not isReagentTemplate(selectedTemplateId) then
        disabled = true
        unavailableReason = "Unknown alchemical reagent"
    elseif selectedAvailable ~= nil and quantity > selectedAvailable then
        disabled = true
        unavailableReason = "Reagent stock unavailable"
    elseif not actor or not actor.inventory or not actor.inventory.addItem then
        disabled = true
        unavailableReason = "No inventory for reagent"
    elseif carriedGold < cost then
        disabled = true
        unavailableReason = "Not enough gold"
    elseif availableSlots ~= nil and slotsNeeded and availableSlots < slotsNeeded then
        disabled = true
        unavailableReason = "insufficient_slots"
    end

    return {
        action = M.ACTIONS.MENAGERIE_REAGENT_PURCHASE,
        reagentOptions = reagentOptions,
        stockOptions = stockOptions,
        selectedStock = selectedStock,
        selectedStockId = selectedStockId,
        selectedTemplateId = selectedTemplateId,
        selectedReagentName = selectedTemplate and selectedTemplate.name or selectedTemplateId,
        quantity = quantity,
        costPerReagent = costPerReagent,
        cost = cost,
        carriedGold = carriedGold,
        affordable = carriedGold >= cost,
        location = location,
        slotsNeeded = slotsNeeded,
        availableSlots = availableSlots,
        stockRemainingAfterPurchase = selectedAvailable and math.max(0, selectedAvailable - quantity) or nil,
        disabled = disabled,
        unavailableReason = unavailableReason,
    }
end

function M.getReagentSaleOptions(opts)
    opts = opts or {}
    local actor = opts.actor or opts
    local request = opts.request or opts.sale or opts.reagentSale or opts
    local inv = actor and actor.inventory
    local explicitValue = request.price or request.value or request.gold or opts.price or opts.value or opts.gold
    local wantedId = request.reagentId or request.itemId or request.id
    local wantedTemplate = request.reagentTemplateId or request.templateId
    local wantedSource = request.source or request.creature or request.monster
    local selectedReagent = nil
    local selectedLocation = nil
    local reagentOptions = {}

    local function normalizeAlchemyKey(value)
        return tostring(value or ""):lower():gsub("%s+", "_")
    end

    local function isReagentItem(item)
        local props = item and item.properties or {}
        return item ~= nil and (item.type == "reagent" or props.reagent == true or props.alchemicalReagent == true)
    end

    if inv and inv.getAllItems then
        for _, entry in ipairs(inv:getAllItems()) do
            local item = entry.item
            local props = item and item.properties or {}
            if isReagentItem(item) then
                local matches = true
                if type(request.reagent) == "table" and item.id ~= request.reagent.id then
                    matches = false
                end
                if wantedId and item.id ~= wantedId then
                    matches = false
                end
                if wantedTemplate and item.templateId ~= wantedTemplate then
                    matches = false
                end
                if wantedSource and normalizeAlchemyKey(props.source) ~= normalizeAlchemyKey(wantedSource) then
                    matches = false
                end
                local saleValue = alchemy.calculateReagentSaleValue(item, {
                    price = explicitValue,
                    value = explicitValue,
                    gold = explicitValue,
                })
                local selected = matches and selectedReagent == nil
                if selected and not selectedReagent then
                    selectedReagent = item
                    selectedLocation = entry.location
                end
                reagentOptions[#reagentOptions + 1] = {
                    id = item.id,
                    itemId = item.id,
                    item = item,
                    name = item.name,
                    templateId = item.templateId,
                    source = props.source,
                    sourceTotalHD = props.sourceTotalHD or props.totalHD or props.hd,
                    location = entry.location,
                    hermeticBottle = props.hermeticBottle == true,
                    saleValue = saleValue,
                    explicitValue = explicitValue,
                    selected = selected,
                    disabled = props.hermeticBottle ~= true or saleValue == nil,
                    unavailableReason = props.hermeticBottle ~= true and "Requires bottled reagent" or
                        (saleValue == nil and "Reagent value unknown" or nil),
                }
            end
        end
    end

    local selectedValue = selectedReagent and alchemy.calculateReagentSaleValue(selectedReagent, {
        price = explicitValue,
        value = explicitValue,
        gold = explicitValue,
    }) or nil
    local selectedProps = selectedReagent and selectedReagent.properties or {}
    local disabled = false
    local unavailableReason = nil
    if not selectedReagent then
        disabled = true
        unavailableReason = "Requires bottled reagent"
    elseif selectedProps.hermeticBottle ~= true then
        disabled = true
        unavailableReason = "Requires bottled reagent"
    elseif selectedValue == nil then
        disabled = true
        unavailableReason = "Reagent value unknown"
    elseif not inv or not inv.removeItem then
        disabled = true
        unavailableReason = "No inventory for reagent"
    end

    return {
        action = M.ACTIONS.SELL_REAGENT,
        reagentOptions = reagentOptions,
        selectedReagent = selectedReagent,
        selectedItemId = selectedReagent and selectedReagent.id or nil,
        selectedLocation = selectedLocation,
        saleValue = selectedValue,
        explicitValue = explicitValue,
        disabled = disabled,
        unavailableReason = unavailableReason,
    }
end

function M.getSellTreasureOptions(opts)
    opts = opts or {}
    local actor = opts.actor or opts
    local request = opts.request or opts.sale or opts.treasureSale or opts
    local inv = actor and actor.inventory
    local selectedRefs = normalizeList(request.itemIds or request.items or request.itemId or opts.itemIds or opts.items or
        opts.itemId)
    local values = request.values or request.prices or opts.values or opts.prices or {}
    local appraisals = request.appraisals or request.appraisalNotes or request.appraisal or
        opts.appraisals or opts.appraisalNotes or opts.appraisal
    local buyers = request.buyers or request.buyerByItem or request.buyer or opts.buyers or opts.buyerByItem or opts.buyer
    local markets = request.markets or request.marketByItem or request.market or
        opts.markets or opts.marketByItem or opts.market
    local appraisers = request.appraisers or request.appraiserByItem or request.appraiser or
        opts.appraisers or opts.appraiserByItem or opts.appraiser
    local saleNotes = request.notes or request.saleNotes or opts.notes or opts.saleNotes
    local selectedById = {}
    for _, ref in ipairs(selectedRefs) do
        local itemId = type(ref) == "table" and ref.id or ref
        if itemId then
            selectedById[tostring(itemId)] = ref
        end
    end

    local itemOptions = {}
    if inv and inv.getAllItems then
        for _, entry in ipairs(inv:getAllItems()) do
            local item = entry.item
            local props = item and item.properties or {}
            local selectedRef = item and selectedById[tostring(item.id)]
            local explicitValue = type(selectedRef) == "table" and
                (selectedRef.value or selectedRef.price or selectedRef.saleValue or selectedRef.appraisedValue) or
                (item and values[item.id])
            local saleValue = treasureSaleValue(item, explicitValue)
            local treasure = isTreasureItem(item)
            itemOptions[#itemOptions + 1] = {
                id = item.id,
                itemId = item.id,
                item = item,
                name = item.name,
                templateId = item.templateId,
                location = entry.location,
                treasure = treasure,
                liquidCurrency = currency.isCurrencyItem(item) == true,
                provenance = props.provenance or props.origin or props.source or item.provenance,
                saleValue = saleValue,
                explicitValue = explicitValue,
                appraisal = type(selectedRef) == "table" and
                    (selectedRef.appraisal or selectedRef.appraisalNotes or selectedRef.notes) or
                    saleMetadataValue(appraisals, item.id),
                buyer = type(selectedRef) == "table" and selectedRef.buyer or saleMetadataValue(buyers, item.id),
                market = type(selectedRef) == "table" and selectedRef.market or saleMetadataValue(markets, item.id),
                appraiser = type(selectedRef) == "table" and selectedRef.appraiser or
                    saleMetadataValue(appraisers, item.id),
                notes = type(selectedRef) == "table" and (selectedRef.saleNotes or selectedRef.notes) or
                    saleMetadataValue(saleNotes, item.id),
                selected = selectedRef ~= nil,
                disabled = not treasure or saleValue <= 0,
                unavailableReason = not treasure and "Item is not non-liquid treasure" or
                    (saleValue <= 0 and "Treasure value required" or nil),
            }
        end
    end

    local selectedItems = {}
    local totalGold = 0
    local disabled = false
    local unavailableReason = nil
    if #selectedRefs == 0 then
        disabled = true
        unavailableReason = "Treasure item required"
    elseif not inv or not inv.findItem or not inv.removeItem then
        disabled = true
        unavailableReason = "No inventory for treasure sale"
    else
        for _, ref in ipairs(selectedRefs) do
            local itemId = type(ref) == "table" and ref.id or ref
            local itemOverrides = type(ref) == "table" and ref or {}
            local explicitValue = type(ref) == "table" and
                (ref.value or ref.price or ref.saleValue or ref.appraisedValue) or values[itemId]
            local item = inv:findItem(itemId)
            if not item then
                disabled = true
                unavailableReason = "Treasure item not found"
            elseif not isTreasureItem(item) then
                disabled = true
                unavailableReason = "Item is not non-liquid treasure"
            else
                local value = treasureSaleValue(item, explicitValue)
                if value <= 0 then
                    disabled = true
                    unavailableReason = "Treasure value required"
                else
                    local props = item.properties or {}
                    selectedItems[#selectedItems + 1] = {
                        item = item,
                        itemId = item.id,
                        name = item.name,
                        value = value,
                        provenance = itemOverrides.provenance or itemOverrides.origin or props.provenance or
                            props.origin or props.source or item.provenance,
                        appraisal = itemOverrides.appraisal or itemOverrides.appraisalNotes or itemOverrides.notes or
                            saleMetadataValue(appraisals, item.id),
                        buyer = itemOverrides.buyer or saleMetadataValue(buyers, item.id),
                        market = itemOverrides.market or saleMetadataValue(markets, item.id),
                        appraiser = itemOverrides.appraiser or saleMetadataValue(appraisers, item.id),
                        notes = itemOverrides.saleNotes or itemOverrides.notes or saleMetadataValue(saleNotes, item.id),
                    }
                    totalGold = totalGold + value
                end
            end
            if disabled then
                break
            end
        end
    end

    return {
        action = "sell_treasure",
        step = M.STEPS.TURN_IN_CONTRACTS,
        itemOptions = itemOptions,
        selectedItems = selectedItems,
        selectedCount = #selectedItems,
        totalGold = totalGold,
        currentGold = actor and currency.getGold(actor) or tonumber(opts.gold) or 0,
        projectedGold = actor and (currency.getGold(actor) + totalGold) or nil,
        disabled = disabled,
        unavailableReason = unavailableReason,
    }
end

local function merchantRecordMatches(entry, key, wanted, wantedId)
    local candidates = { key }
    if type(entry) == "table" then
        candidates[#candidates + 1] = entry.id
        candidates[#candidates + 1] = entry.merchantId
        candidates[#candidates + 1] = entry.name
        candidates[#candidates + 1] = entry.title
    else
        candidates[#candidates + 1] = entry
    end

    for _, candidate in ipairs(candidates) do
        if candidate ~= nil then
            local text = tostring(candidate)
            if text == wanted or normalizeProjectId(text) == wantedId then
                return true
            end
        end
    end
    return false
end

local function cloneMerchantRecord(entry, fallbackId)
    if type(entry) == "table" then
        local record = shallowClone(entry)
        record.id = record.id or record.merchantId or fallbackId
        return record
    elseif type(entry) == "string" then
        return {
            id = fallbackId,
            name = entry,
        }
    end
    return nil
end

local function findMerchantRecord(merchants, merchantRef)
    if type(merchantRef) == "table" then
        local lookup = merchantRef.id or merchantRef.merchantId or merchantRef.name or merchantRef.title
        local registryRecord = nil
        local registryState = nil
        local registryKey = nil
        if lookup then
            registryRecord, registryState, registryKey = findMerchantRecord(merchants, lookup)
        end

        local record = registryRecord or {}
        for key, value in pairs(merchantRef) do
            record[key] = shallowClone(value)
        end
        record.id = record.id or record.merchantId
        return record, registryState, registryKey
    end

    local wanted = tostring(merchantRef or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if wanted == "" or type(merchants) ~= "table" then
        return nil
    end

    local wantedId = normalizeProjectId(wanted)
    local direct = merchants[wanted] or merchants[wantedId]
    if direct ~= nil then
        local record = cloneMerchantRecord(direct, wanted)
        if record then
            return record, type(direct) == "table" and direct or nil, wanted
        end
    end

    for key, entry in pairs(merchants) do
        if merchantRecordMatches(entry, key, wanted, wantedId) then
            local fallbackId = type(key) ~= "number" and key or wanted
            local record = cloneMerchantRecord(entry, fallbackId)
            if record then
                return record, type(entry) == "table" and entry or nil, key
            end
        end
    end
    return nil
end

local function merchantDisplayName(merchantInput, merchantRecord)
    if type(merchantRecord) == "table" then
        return merchantRecord.name or merchantRecord.title or merchantRecord.id or merchantRecord.merchantId
    elseif type(merchantInput) == "table" then
        return merchantInput.name or merchantInput.title or merchantInput.id or merchantInput.merchantId
    end
    return merchantInput
end

function M.getCommissionCraftOptions(opts)
    opts = opts or {}
    local actor = opts.actor or opts
    local request = opts.request or opts.commission or opts.craft or opts
    local description = tostring(request.description or request.name or request.title or "")
    local commissionId = description ~= "" and normalizeProjectId(request.commissionId or request.id or description) or nil
    local syllables, syllableError = resolveSyllables(request)
    if syllables and description == "" then
        syllables = 0
    end

    local gold = actor and currency.getGold(actor) or tonumber(opts.gold) or 0
    local selectedScale = normalizeCommissionScale(request.scale or request.category or request.tier)
    local rate = M.COMMISSION_CRAFT_RATES[selectedScale]
    local selectedCost = rate and syllables and syllables * rate or nil
    local commissions = opts.commissions or opts.existingCommissions or {}
    local merchants = opts.merchants or opts.merchantRegistry or {}
    local merchantInput = request.merchant or request.merchantId or request.artisan or request.artisanId or
        request.crafter or request.crafterId
    local merchantRecord, _, merchantKey = findMerchantRecord(merchants, merchantInput)
    local merchantName = merchantDisplayName(merchantInput, merchantRecord)

    local scaleOptions = {}
    local scaleOrder = { "farmer", "adventurer", "noble", "novel" }
    for _, scale in ipairs(scaleOrder) do
        local scaleRate = M.COMMISSION_CRAFT_RATES[scale]
        local scaleCost = syllables and syllables * scaleRate or nil
        local affordable = scaleCost ~= nil and gold >= scaleCost
        scaleOptions[#scaleOptions + 1] = {
            id = scale,
            scale = scale,
            ratePerSyllable = scaleRate,
            syllables = syllables,
            cost = scaleCost,
            affordable = affordable,
            selected = scale == selectedScale,
            disabled = scaleCost ~= nil and not affordable or nil,
            unavailableReason = scaleCost ~= nil and not affordable and "Not enough gold" or nil,
        }
    end

    local merchantOptions = {}
    for key, merchant in pairs(merchants) do
        local record = cloneMerchantRecord(merchant, type(key) ~= "number" and key or nil)
        if record then
            local id = record.id or record.merchantId or (type(key) ~= "number" and key or nil)
            merchantOptions[#merchantOptions + 1] = {
                id = id,
                merchantId = id,
                name = record.name or record.title or id,
                districtId = record.districtId or record.cityDistrictId or record.district_id,
                districtName = record.districtName or record.cityDistrictName or record.district,
                specialties = shallowClone(record.specialties or record.craftSpecialties or record.commissionSpecialties or {}),
                selected = merchantKey ~= nil and tostring(key) == tostring(merchantKey),
            }
        end
    end
    table.sort(merchantOptions, function(a, b)
        return tostring(a.name or a.merchantId) < tostring(b.name or b.merchantId)
    end)

    local wantsDelivery = request.deliver == true or request.addToInventory == true or
        request.deliverToInventory == true or request.deliverItem ~= nil or request.item ~= nil or
        request.itemSpec ~= nil or request.rewardItem ~= nil or request.itemTemplateId ~= nil or
        request.templateId ~= nil
    local availablePackSlots = nil
    if actor and actor.inventory and actor.inventory.availableSlots then
        availablePackSlots = actor.inventory:availableSlots(request.location or request.itemLocation or inventory.LOCATIONS.PACK)
    end

    local disabled = false
    local unavailableReason = nil
    if request.reasonable == false or request.approved == false then
        disabled = true
        unavailableReason = "Commission not approved"
    elseif description == "" then
        disabled = true
        unavailableReason = "Commission description required"
    elseif selectedScale == "" or not rate then
        disabled = true
        unavailableReason = "Commission scale required"
    elseif not syllables then
        disabled = true
        unavailableReason = syllableError
    elseif syllables <= 0 then
        disabled = true
        unavailableReason = "Commission description required"
    elseif commissionId and commissions[commissionId] then
        disabled = true
        unavailableReason = "Commission already exists"
    elseif request.requireMerchant == true and not merchantRecord then
        disabled = true
        unavailableReason = "Commission merchant not found"
    elseif selectedCost and gold < selectedCost then
        disabled = true
        unavailableReason = "Not enough gold"
    end

    return {
        action = M.ACTIONS.COMMISSION_CRAFT,
        description = description ~= "" and description or nil,
        commissionId = commissionId,
        name = request.name or request.title or description,
        syllables = syllables,
        syllableError = syllableError,
        gold = gold,
        scale = selectedScale ~= "" and selectedScale or nil,
        ratePerSyllable = rate,
        cost = selectedCost,
        affordable = selectedCost ~= nil and gold >= selectedCost,
        requiresGMApproval = true,
        approved = request.approved ~= false and request.reasonable ~= false,
        requiresMerchant = request.requireMerchant == true,
        merchant = merchantName,
        merchantId = merchantRecord and (merchantRecord.id or merchantRecord.merchantId or merchantKey) or nil,
        merchantRecord = merchantRecord,
        merchantFound = merchantInput == nil or merchantRecord ~= nil,
        merchantOptions = merchantOptions,
        scaleOptions = scaleOptions,
        deliveryRequested = wantsDelivery,
        deliveryLocation = request.location or request.itemLocation or inventory.LOCATIONS.PACK,
        availableDeliverySlots = availablePackSlots,
        disabled = disabled,
        unavailableReason = unavailableReason,
    }
end

local function appendCommissionToMerchant(merchantRecord, commissionId)
    if type(merchantRecord) ~= "table" or not commissionId then
        return nil
    end

    merchantRecord.commissions = merchantRecord.commissions or {}
    for _, existingId in ipairs(merchantRecord.commissions) do
        if existingId == commissionId then
            return merchantRecord.commissions
        end
    end
    merchantRecord.commissions[#merchantRecord.commissions + 1] = commissionId
    return merchantRecord.commissions
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

    local rawCityEventsTable = config.cityEventsTable or config.city_events_table or config.cityEventTable or
        config.customCityEventsTable or config.customCityEventTable or city_events.DEFAULT_EVENTS
    local cityEventsTableMeta = {
        tableName = "city_events",
        source = "default",
        missing = {},
        invalid = {},
        count = 21,
        complete = true,
        requireComplete = false,
    }
    if rawCityEventsTable ~= city_events.DEFAULT_EVENTS or config.normalizeCityEventsTable then
        rawCityEventsTable, cityEventsTableMeta = city_events.normalizeEventTable(rawCityEventsTable, {
            tableName = "city_events",
            source = config.cityEventsTableSource or config.cityEventTableSource or config.city_events_table_source,
            requireComplete = config.requireCompleteCityEventsTable == true or
                config.requireCompleteCityEventTable == true or
                config.require_complete_city_events_table == true,
        })
    end

    local rawSignsAndPortentsTable = config.signsAndPortentsTable or config.signsTable or
        config.customSignsAndPortentsTable or config.customSignsTable or city_events.SIGNS_AND_PORTENTS
    local signsAndPortentsTableMeta = {
        tableName = "signs_and_portents",
        source = "default",
        missing = {},
        invalid = {},
        count = 14,
        complete = true,
        requireComplete = false,
    }
    if rawSignsAndPortentsTable ~= city_events.SIGNS_AND_PORTENTS or config.normalizeSignsAndPortentsTable then
        rawSignsAndPortentsTable, signsAndPortentsTableMeta = city_events.normalizeEventTable(rawSignsAndPortentsTable, {
            tableName = "signs_and_portents",
            source = config.signsAndPortentsTableSource or config.signsTableSource or
                config.signs_and_portents_table_source,
            defaultCategory = city_events.CATEGORIES.SIGNS_AND_PORTENTS,
            maxValue = 14,
            requireComplete = config.requireCompleteSignsAndPortentsTable == true or
                config.requireCompleteSignsTable == true,
        })
    end

    local controller = {
        eventBus = config.eventBus or events.globalBus,
        actionResolver = config.actionResolver,
        bidLoreEngine = config.bidLoreEngine or config.loreEngine,
        guild = config.guild or {},
        guildRoster = config.guildRoster or config.roster or {},
        playerDeck = config.playerDeck or config.minorDeck,
        gmDeck = config.gmDeck or config.majorDeck,
        cityEventsTable = rawCityEventsTable,
        cityEventsTableMeta = cityEventsTableMeta,
        signsAndPortentsTable = rawSignsAndPortentsTable,
        signsAndPortentsTableMeta = signsAndPortentsTableMeta,
        consumedCityEvents = config.consumedCityEvents or {},
        consumedSignsAndPortents = config.consumedSignsAndPortents or {},
        cityEventEffects = config.cityEventEffects or {},
        cityLayout = config.cityLayout or config.cityMap,
        cityState = config.cityState or config.worldState or {},
        underworldState = config.underworldState or config.dungeonState or config.mapState,
        districtActions = config.districtActions or
            ((config.cityLayout or config.cityMap) and (config.cityLayout or config.cityMap).specialCityActions) or {},
        meatgrinder = config.meatgrinder,
        meatgrinderTable = config.meatgrinderTable or config.meatgrinderEntries,
        contracts = config.contracts or config.cityContracts or {},
        jobBoard = config.jobBoard or config.availableContracts or config.contractOffers or {},
        contractTable = config.contractTable or config.jobBoardTable or config.contractsTable,
        menagerieStock = config.menagerieStock or config.menagerieReagents or config.menagerieCatalog,
        guildTreasury = config.guildTreasury or config.treasury or { gold = 0 },
        projects = config.projects or config.cityProjects or {},
        researchLog = config.researchLog or config.cityResearchLog or {},
        buildings = config.buildings or config.cityBuildings or {},
        commissions = config.commissions or config.cityCommissions or {},
        merchants = config.merchants or config.cityMerchants or {},
        funerals = config.funerals or config.funeralRecords or {},
        retirements = config.retirements or config.retirementRecords or {},
        questDeclarations = config.questDeclarations or config.newQuestDeclarations or {},
        questCompletions = config.questCompletions or config.completedQuests or {},
        guildJoins = config.guildJoins or config.newAdventurerJoins or {},
        newAdventurerReplacementRecords = config.newAdventurerReplacementRecords or
            config.newAdventurerReplacements or {},
        startingGearSelections = config.startingGearSelections or config.newAdventurerStartingGear or {},
        newAdventurerBondRecords = config.newAdventurerBondRecords or config.newAdventurerBonds or {},
        motifChanges = config.motifChanges or config.cityMotifChanges or {},
        bankReturnsApplied = config.bankReturnsApplied or {},
        actionsCompleted = config.actionsCompleted or {},
        upkeepCompleted = config.upkeepCompleted or {},
        taxesResolved = config.taxesResolved or false,
        noteworthyDeedsResolved = config.noteworthyDeedsResolved or false,
        cityEventResolved = config.cityEventResolved or false,
        cityEventConsequencesResolved = config.cityEventConsequencesResolved or false,
        contractsResolved = config.contractsResolved or false,
        nextCrawlPlanned = config.nextCrawlPlanned or false,
        underworldRestocked = config.underworldRestocked or false,
        cityPhaseEnded = config.cityPhaseEnded or false,
        strictCityPhaseOrder = config.strictCityPhaseOrder or config.strictStepOrder or false,
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

    function controller:getDistrictActionOptions(actor, opts)
        if type(actor) == "table" and opts == nil and
           (actor.actor or actor.adventurer or actor.districtAction or actor.districtActionId or
            actor.specialCityAction or actor.action or actor.request or actor.districtActions or
            actor.specialCityActions or actor.ignoreActorGates) then
            opts = actor
            actor = opts.actor or opts.adventurer
        end
        opts = opts or {}
        opts.actor = actor or opts.actor
        opts.districtActions = opts.districtActions or self:getAvailableDistrictActions()
        opts.cityEventEffects = opts.cityEventEffects or self.cityEventEffects
        opts.cityState = opts.cityState or self.cityState
        opts.actionsCompleted = opts.actionsCompleted or self.actionsCompleted
        return M.getDistrictActionOptions(opts)
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

    function controller:isCityPhaseStepComplete(step)
        local stepId = normalizeCityPhaseStep(step)
        if stepId == M.STEPS.DEATH_AND_TAXES then
            return self.taxesResolved == true
        elseif stepId == M.STEPS.NOTEWORTHY_DEEDS then
            return self.noteworthyDeedsResolved == true
        elseif stepId == M.STEPS.CITY_EVENTS then
            return self.cityEventResolved == true
        elseif stepId == M.STEPS.TURN_IN_CONTRACTS then
            return self.contractsResolved == true
        elseif stepId == M.STEPS.UPKEEP then
            for _, actor in ipairs(self.guild or {}) do
                if isActiveAdventurer(actor) and not self:hasUpkeep(actor) then
                    return false
                end
            end
            return true
        elseif stepId == M.STEPS.CITY_ACTIONS then
            return self:canAdvance()
        elseif stepId == M.STEPS.PLAN_NEXT_CRAWL then
            return self.nextCrawlPlanned == true
        elseif stepId == M.STEPS.RESTOCK_UNDERWORLD then
            return self.underworldRestocked == true
        end
        return false
    end

    function controller:getCityPhaseFlowStatus()
        local steps = {}
        local nextStep = nil
        for index, step in ipairs(M.CITY_PHASE_STEP_ORDER) do
            local complete = self:isCityPhaseStepComplete(step)
            if not complete and not nextStep then
                nextStep = step
            end
            steps[index] = {
                index = index,
                step = step,
                complete = complete,
            }
        end

        for _, entry in ipairs(steps) do
            entry.current = entry.step == nextStep
        end

        return {
            steps = steps,
            stepOrder = M.getCityPhaseStepOrder(),
            currentStep = nextStep,
            nextStep = nextStep,
            complete = nextStep == nil,
            readyToEnd = nextStep == nil and self.cityPhaseEnded ~= true,
            cityPhaseEnded = self.cityPhaseEnded == true,
            strictOrder = self.strictCityPhaseOrder == true,
        }
    end

    function controller:getCityActionTurnOptions(opts)
        opts = opts or {}
        local selectedRequest = opts.actionData or opts.cityAction or opts.action
        local selectedActionId = normalizeActionId(type(selectedRequest) == "table" and
            (selectedRequest.type or selectedRequest.action or selectedRequest.id) or selectedRequest)
        if selectedActionId == "" then
            selectedActionId = nil
        end

        local selectedActorInput = opts.actor or type(selectedRequest) == "table" and selectedRequest.actor or nil
        local function matchesActor(actor, wanted)
            if wanted == nil then
                return false
            end
            if actor == wanted then
                return true
            end
            if type(wanted) == "table" then
                return actorId(actor) == actorId(wanted)
            end
            return tostring(actorId(actor) or "") == tostring(wanted)
        end

        local activeActors = activeAdventurers(self.guild)
        local actorOptions = {}
        local completedActors = {}
        local pendingActors = {}
        local selectedActorOption = nil
        for index, actor in ipairs(activeActors) do
            local id = actorId(actor)
            local completed = id and self.actionsCompleted[id] or nil
            local option = {
                index = index,
                actor = actor,
                actorId = id,
                actorName = actor and actor.name,
                active = true,
                hasActed = completed ~= nil,
                canAct = completed == nil,
                action = completed and completed.action or nil,
                result = completed and completed.result or nil,
                actionRecord = completed and {
                    action = completed.action,
                    result = completed.result,
                } or nil,
            }
            actorOptions[#actorOptions + 1] = option
            if completed then
                completedActors[#completedActors + 1] = option
            else
                pendingActors[#pendingActors + 1] = option
            end
            if matchesActor(actor, selectedActorInput) then
                selectedActorOption = option
            end
        end

        local commonActionChoices = {}
        for actionId, detail in pairs(M.getCityActionDetails()) do
            local allowed, reason = self:checkCityActionRestrictions(actionId)
            detail.allowed = allowed == true
            detail.disabled = allowed ~= true
            detail.unavailableReason = allowed ~= true and reason or nil
            commonActionChoices[actionId] = detail
        end

        local districtActionOptionData = self:getDistrictActionOptions({
            ignoreActorGates = true,
        })
        local districtActionChoices = {}
        for _, choice in ipairs(districtActionOptionData.actions or {}) do
            choice.allowed = not choice.disabled
            districtActionChoices[choice.key] = choice
        end

        local gateAvailable, gateReason, gateDetail = self:canResolveCityPhaseStep(M.STEPS.CITY_ACTIONS, opts)
        local selectedAction = nil
        if selectedActorInput ~= nil or selectedActionId ~= nil then
            selectedAction = {
                actor = selectedActorOption and selectedActorOption.actor or
                    (type(selectedActorInput) == "table" and selectedActorInput or nil),
                actorId = selectedActorOption and selectedActorOption.actorId or
                    (type(selectedActorInput) == "table" and actorId(selectedActorInput) or selectedActorInput),
                action = selectedActionId,
                actionDetail = selectedActionId and M.getCityActionDetails(selectedActionId) or nil,
                available = false,
                disabled = true,
            }
            if not selectedActorOption then
                selectedAction.unavailableReason = "No active adventurer"
            elseif not gateAvailable then
                selectedAction.unavailableReason = gateReason
                selectedAction.gateDetail = gateDetail
            elseif selectedActorOption.hasActed then
                selectedAction.unavailableReason = "City Action already taken"
            elseif not selectedActionId then
                selectedAction.unavailableReason = "City Action required"
            else
                local allowed, reason = self:checkCityActionRestrictions(selectedActionId)
                selectedAction.available = allowed == true
                selectedAction.disabled = allowed ~= true
                selectedAction.unavailableReason = allowed ~= true and reason or nil
            end
        end

        local effects = self.cityEventEffects or {}
        return {
            step = M.STEPS.CITY_ACTIONS,
            stepDetail = M.getCityPhaseStepDetails(M.STEPS.CITY_ACTIONS),
            actionsPerAdventurer = 1,
            strictOrder = self.strictCityPhaseOrder == true,
            stepGate = {
                available = gateAvailable == true,
                unavailableReason = gateAvailable ~= true and gateReason or nil,
                detail = gateDetail,
            },
            actors = actorOptions,
            activeActors = actorOptions,
            completedActors = completedActors,
            pendingActors = pendingActors,
            activeCount = #actorOptions,
            requiredCount = #actorOptions,
            completedCount = #completedActors,
            pendingCount = #pendingActors,
            allComplete = #pendingActors == 0,
            canAdvance = #pendingActors == 0,
            commonActionChoices = commonActionChoices,
            districtActionChoices = districtActionChoices,
            districtActionOptionData = districtActionOptionData,
            selectedAction = selectedAction,
            cityEventRestrictions = {
                allowedCityActions = M.copyCityPhaseMetadata(effects.allowedCityActions),
                blockedCityActions = M.copyCityPhaseMetadata(effects.blockedCityActions),
                cityActionsBlockedByUndead = self.cityState and self.cityState.cityActionsBlockedByUndead == true or false,
                undeadPlague = M.copyCityPhaseMetadata(self.cityState and self.cityState.undeadPlague),
            },
            resultPreview = #pendingActors == 0 and "city_actions_complete" or "city_actions_pending",
        }
    end

    function controller:canResolveCityPhaseStep(step, opts)
        opts = opts or {}
        local stepId = normalizeCityPhaseStep(step or opts.step)
        if not cityPhaseStepIndex(stepId) then
            return false, "Unknown City Phase step", {
                step = stepId,
            }
        end

        local strictOrder = self.strictCityPhaseOrder == true
        if opts.strictOrder ~= nil then
            strictOrder = opts.strictOrder == true
        elseif opts.strictCityPhaseOrder ~= nil then
            strictOrder = opts.strictCityPhaseOrder == true
        end

        if strictOrder then
            local targetIndex = cityPhaseStepIndex(stepId)
            for index = 1, targetIndex - 1 do
                local priorStep = M.CITY_PHASE_STEP_ORDER[index]
                if not self:isCityPhaseStepComplete(priorStep) then
                    return false, "Previous City Phase steps incomplete", {
                        step = stepId,
                        blockedBy = priorStep,
                    }
                end
            end
        end

        return true, "city_phase_step_available", {
            step = stepId,
        }
    end

    function controller:resolveCityPhaseStep(step, opts)
        if opts == nil and type(step) == "table" and (step.step or step.id) then
            opts = step
            step = opts.step or opts.id
        end
        opts = opts or {}
        local stepId = normalizeCityPhaseStep(step or opts.step)
        local available, reason, gateDetail = self:canResolveCityPhaseStep(stepId, opts)
        if not available then
            return false, reason, gateDetail
        end

        if stepId == M.STEPS.DEATH_AND_TAXES then
            return self:resolveDeathAndTaxes(opts)
        elseif stepId == M.STEPS.NOTEWORTHY_DEEDS then
            return self:resolveNoteworthyDeeds(opts)
        elseif stepId == M.STEPS.CITY_EVENTS then
            return self:resolveCityEvent(opts)
        elseif stepId == M.STEPS.TURN_IN_CONTRACTS then
            return self:resolveTurnInContracts(opts)
        elseif stepId == M.STEPS.UPKEEP then
            local request = opts.upkeep or opts.upkeepRequest or opts
            if type(request) ~= "table" then
                request = opts
            end
            local actor = opts.actor or request.actor
            if not actor then
                return false, "Upkeep actor required", {
                    step = stepId,
                }
            end
            return self:resolveUpkeep(actor, request)
        elseif stepId == M.STEPS.CITY_ACTIONS then
            local actionData = opts.actionData or opts.cityAction or opts.action or opts
            if type(actionData) ~= "table" then
                actionData = { type = actionData }
            end
            local actor = opts.actor or actionData.actor
            if not actor then
                return false, "City Action actor required", {
                    step = stepId,
                }
            end
            return self:resolveAction(actor, actionData)
        elseif stepId == M.STEPS.PLAN_NEXT_CRAWL then
            return self:resolvePlanNextCrawl(opts)
        elseif stepId == M.STEPS.RESTOCK_UNDERWORLD then
            return self:resolveRestockUnderworld(opts)
        end

        return false, "Unknown City Phase step", {
            step = stepId,
        }
    end

    function controller:resolveEndOfCityPhase(opts)
        opts = opts or {}
        if self.cityPhaseEnded then
            return false, "City Phase already ended"
        end

        local cityEventConsequences = self.lastCityEventConsequences
        if opts.resolveCityEventConsequences ~= false and not self.cityEventConsequencesResolved then
            local consequenceDetail, complete = resolvePendingCityEventConsequences(self, opts)
            if consequenceDetail then
                cityEventConsequences = consequenceDetail
                self.lastCityEventConsequences = consequenceDetail
                self.cityEventConsequencesResolved = complete == true
            end
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
            cityEventConsequences = cityEventConsequences,
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

    function controller:resolveCityEventConsequences(opts)
        opts = opts or {}
        if self.cityEventConsequencesResolved then
            return false, "City Event consequences already resolved"
        end

        local detail, complete = resolvePendingCityEventConsequences(self, opts)
        if not detail then
            return false, "No pending City Event consequence"
        end

        self.lastCityEventConsequences = detail
        self.cityEventConsequencesResolved = complete == true

        return true, detail.result, detail
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

    function controller:applyCityEventDistrictEffects(eventEntry, sign, opts)
        opts = opts or {}
        local effects = mergeCityEventEffects({}, eventEntry and eventEntry.effects)
        effects = mergeCityEventEffects(effects, sign and sign.effects)
        local layout = opts.cityLayout or opts.cityMap or self.cityLayout
        local detail = {}

        if effects.drawAdditionalDistrict then
            local card = opts.additionalDistrictCard or opts.ancientQuarterCard or opts.cityEventDistrictCard
            local added, reason = addDistrictToCityLayout(layout, card, "ancient_quarter")
            detail.addedDistrict = added and {
                placement = added,
                districtId = added.district.id,
                districtName = added.district.name,
                card = card,
            } or nil
            detail.addDistrictPending = added == nil
            detail.addDistrictReason = added and nil or reason
        end

        if effects.removeRandomDistrict then
            local districtId = opts.removedDistrictId or opts.slimeCatastropheDistrictId or opts.cityEventDistrictId or
                opts.districtId
            local removed = removeDistrictFromCityLayout(layout, districtId)
            detail.removedDistrict = removed and {
                placement = removed,
                districtId = cityLayoutDistrictId(removed),
                districtName = removed.district and removed.district.name or removed.districtName,
            } or nil
            detail.removeDistrictPending = removed == nil
        end

        if effects.blockRandomDistrictAction then
            local districtId = opts.blockedDistrictId or opts.mushroomForestDistrictId or opts.cityEventDistrictId or
                opts.districtId
            local blocked = findDistrictActionEntry(layout, districtId)
            if blocked then
                blocked.blockedByCityEvent = true
                blocked.blockedReason = "mushroom_forest"
                self.cityEventEffects.blockedDistrictActions = self.cityEventEffects.blockedDistrictActions or {}
                self.cityEventEffects.blockedDistrictActions[blocked.action and blocked.action.id or ""] = true
                self.cityEventEffects.blockedDistrictIds = self.cityEventEffects.blockedDistrictIds or {}
                self.cityEventEffects.blockedDistrictIds[blocked.districtId] = true
                detail.blockedDistrictAction = {
                    districtId = blocked.districtId,
                    districtName = blocked.districtName,
                    actionId = blocked.action and blocked.action.id,
                    reason = "mushroom_forest",
                }
            else
                detail.blockedDistrictActionPending = true
            end
        end

        if detail.addedDistrict or detail.removedDistrict or detail.blockedDistrictAction or
           detail.addDistrictPending or detail.removeDistrictPending or detail.blockedDistrictActionPending then
            self.lastCityEventLayoutEffects = detail
            return detail
        end
        return nil
    end

    function controller:applyCityEventOmenEffects(eventEntry, sign, opts)
        opts = opts or {}
        local effects = mergeCityEventEffects({}, eventEntry and eventEntry.effects)
        effects = mergeCityEventEffects(effects, sign and sign.effects)
        local omen = effects.cityOmen or effects.city_omen
        if type(omen) ~= "table" then
            return nil
        end

        local cityState = opts.cityState or opts.worldState or self.cityState
        cityState.cityOmens = cityState.cityOmens or {}

        local record = {}
        for key, value in pairs(omen) do
            record[key] = value
        end
        record.eventValue = eventEntry and eventEntry.value
        record.eventTitle = eventEntry and eventEntry.title
        record.signValue = sign and sign.value
        record.signTitle = sign and sign.title

        cityState.cityOmens[#cityState.cityOmens + 1] = record
        if record.flag then
            cityState[record.flag] = true
        end
        if record.years then
            cityState.yearsElapsed = (tonumber(cityState.yearsElapsed) or 0) + math.floor(tonumber(record.years) or 0)
        end
        if record.requiresPlayerSecrets then
            cityState.pendingDreamSecrets = opts.pendingDreamSecrets or #activeAdventurers(self.guild)
        end

        local detail = {
            omen = record,
            cityState = cityState,
            result = "city_omen_recorded",
        }
        self.lastCityEventOmen = detail
        return detail
    end

    function controller:applyCityEventSuccessionEffects(eventEntry, sign, opts)
        opts = opts or {}
        local effects = mergeCityEventEffects({}, eventEntry and eventEntry.effects)
        effects = mergeCityEventEffects(effects, sign and sign.effects)
        local succession = effects.citySuccession or effects.city_succession
        if type(succession) ~= "table" then
            return nil
        end

        local pending, cityState = M._markCitySuccessionPending(self, eventEntry, sign, succession, opts)
        local detail = {
            effect = succession,
            pending = pending,
            cityState = cityState,
            result = "city_event_succession_pending",
        }
        self.lastCityEventSuccession = detail
        return detail
    end

    function controller:applyCityEventUndeadPlagueEffects(eventEntry, sign, opts)
        opts = opts or {}
        local effects = mergeCityEventEffects({}, eventEntry and eventEntry.effects)
        effects = mergeCityEventEffects(effects, sign and sign.effects)
        local plague = effects.undeadPlague or effects.undead_plague
        if type(plague) ~= "table" then
            return nil
        end

        local record, cityState = M._markCityUndeadPlague(self, eventEntry, sign, plague, opts)
        local detail = {
            effect = plague,
            plague = record,
            cityState = cityState,
            result = "city_event_undead_plague_active",
        }
        self.lastCityEventUndeadPlague = detail
        return detail
    end

    function controller:applyCityEventRandomTargetEffects(eventEntry, sign, opts)
        opts = opts or {}
        local effects = mergeCityEventEffects({}, eventEntry and eventEntry.effects)
        effects = mergeCityEventEffects(effects, sign and sign.effects)
        local randomEffect = effects.randomAdventurer or effects.random_adventurer
        if type(randomEffect) ~= "table" then
            return nil
        end

        local minorDiscard = getTopMinorDiscard(self, opts)
        if not minorDiscard or not isMinorDeckCard(minorDiscard) then
            return {
                pending = true,
                reason = "requires_minor_discard",
                effect = randomEffect,
            }
        end

        local actors = activeAdventurers(opts.guild or self.guild)
        local target = selectRandomAdventurerFromMinorDiscard(actors, minorDiscard)
        if not target then
            return {
                pending = true,
                reason = "requires_active_adventurer",
                effect = randomEffect,
                minorDiscard = minorDiscard,
            }
        end

        local record = {
            id = randomEffect.id or "city_event_random_adventurer",
            type = randomEffect.type or "city_event_random_adventurer",
            source = randomEffect.source or "city_event",
            eventValue = eventEntry and eventEntry.value,
            eventTitle = eventEntry and eventEntry.title,
            minorDiscard = minorDiscard,
        }
        local recordField = randomEffect.recordField or "cityEventRandomTargets"
        appendActorRecord(target, recordField, record)

        local detail = {
            target = target,
            targetId = actorId(target),
            effect = randomEffect,
            record = record,
            recordField = recordField,
            minorDiscard = minorDiscard,
            result = "city_event_random_target_resolved",
        }
        self.lastCityEventRandomTarget = detail
        return detail
    end

    local function selectTargetedCityEventAdventurer(effect, actors, opts)
        opts = opts or {}
        local explicit = opts.targetedAdventurer or opts.cityEventTarget or opts.targetActor or opts.target
        local actor = resolveActorReference(explicit, actors)
        if actor then
            return actor, {
                targetRule = "explicit",
            }
        end

        local targetRule = effect and (effect.target or effect.targetRule)
        if targetRule == "highest_suit" then
            local selected, score = selectSuitTarget(actors, effect.suit, "highest")
            return selected, {
                targetRule = targetRule,
                suit = effect.suit,
                suitValue = score,
            }
        elseif targetRule == "lowest_suit" then
            local selected, score = selectSuitTarget(actors, effect.suit, "lowest")
            return selected, {
                targetRule = targetRule,
                suit = effect.suit,
                suitValue = score,
            }
        end

        return actors and actors[1] or nil, {
            targetRule = targetRule or "first_active",
        }
    end

    function controller:applyCityEventTargetedAdventurerEffects(eventEntry, sign, opts)
        opts = opts or {}
        local effects = mergeCityEventEffects({}, eventEntry and eventEntry.effects)
        effects = mergeCityEventEffects(effects, sign and sign.effects)
        local targetedEffect = effects.targetedAdventurer or effects.targeted_adventurer
        if type(targetedEffect) ~= "table" then
            return nil
        end

        local actors = activeAdventurers(opts.guild or self.guild)
        local target, targetDetail = selectTargetedCityEventAdventurer(targetedEffect, actors, opts)
        if not target then
            return {
                pending = true,
                reason = "requires_active_adventurer",
                effect = targetedEffect,
                targetRule = targetDetail and targetDetail.targetRule,
            }
        end

        local record = {
            id = targetedEffect.id or "city_event_targeted_adventurer",
            type = targetedEffect.type or "city_event_targeted_adventurer",
            source = targetedEffect.source or "city_event",
            eventValue = eventEntry and eventEntry.value,
            eventTitle = eventEntry and eventEntry.title,
            targetRule = targetDetail.targetRule,
            suit = targetDetail.suit,
            suitValue = targetDetail.suitValue,
        }
        local recordField = targetedEffect.recordField or "cityEventTargetedAdventurers"
        appendActorRecord(target, recordField, record)

        local detail = {
            target = target,
            targetId = actorId(target),
            targetRule = targetDetail.targetRule,
            suit = targetDetail.suit,
            suitValue = targetDetail.suitValue,
            effect = targetedEffect,
            record = record,
            recordField = recordField,
            result = "city_event_targeted_adventurer_resolved",
        }
        self.lastCityEventTargetedAdventurer = detail
        return detail
    end

    local function normalizeCityCompanionKey(value)
        return tostring(value or "")
            :lower()
            :gsub("[’']", "")
            :gsub("[^%w]+", "_")
            :gsub("^_+", "")
            :gsub("_+$", "")
    end

    local function addCityCompanionCandidate(candidates, value)
        if type(value) == "table" then
            for _, entry in ipairs(value) do
                addCityCompanionCandidate(candidates, entry)
            end
            return
        end
        local normalized = normalizeCityCompanionKey(value)
        if normalized ~= "" then
            candidates[normalized] = true
        end
    end

    local function cityEventCompanionMatchesCriteria(companion, effect)
        local wanted = {}
        addCityCompanionCandidate(wanted, effect.targetSpecies or effect.target_species or effect.species or
            effect.feedFor or effect.feed_for or effect.templateId or effect.companionTemplateId)
        if next(wanted) == nil then
            return true
        end

        local candidates = {}
        addCityCompanionCandidate(candidates, companion.templateId)
        addCityCompanionCandidate(candidates, companion.id)
        addCityCompanionCandidate(candidates, companion.name)
        addCityCompanionCandidate(candidates, companion.species)
        addCityCompanionCandidate(candidates, companion.animalType)
        addCityCompanionCandidate(candidates, companion.feedType)
        addCityCompanionCandidate(candidates, companion.aliases)

        local template = animal_companions.getTemplate(companion.templateId or companion.species or
            companion.animalType or companion.feedType or companion.name)
        if template then
            addCityCompanionCandidate(candidates, template.id)
            addCityCompanionCandidate(candidates, template.name)
            addCityCompanionCandidate(candidates, template.species)
            addCityCompanionCandidate(candidates, template.animalType)
            addCityCompanionCandidate(candidates, template.feedType)
            addCityCompanionCandidate(candidates, template.aliases)
        end

        for key in pairs(wanted) do
            if candidates[key] then
                return true
            end
        end
        return false
    end

    local function isCityEventRationItem(item)
        local props = item and item.properties or {}
        local templateId = item and item.templateId
        return item and (item.isRation == true or props.isRation == true or props.ration == true or
            item.type == "ration" or item.itemType == "ration" or props.type == "ration" or
            templateId == "ration" or templateId == "rations_3" or templateId == "disgusting_ration")
    end

    local function isCityEventAnimalFeedItem(item)
        local props = item and item.properties or {}
        return item and (item.type == "animal_feed" or item.itemType == "animal_feed" or
            props.isAnimalFeed == true or props.animalFeed == true)
    end

    local function cityEventAnimalFeedMatches(item, opportunity)
        if isCityEventRationItem(item) then
            return opportunity.acceptsRations ~= false
        end
        if not isCityEventAnimalFeedItem(item) then
            return false
        end

        local props = item.properties or {}
        local feedFor = normalizeCityCompanionKey(props.feedFor or props.animalType or props.animalKind)
        if feedFor == "" or feedFor == "any" then
            return true
        end

        local candidates = {}
        local function addCandidate(value)
            if type(value) == "table" then
                for _, entry in ipairs(value) do
                    addCandidate(entry)
                end
                return
            end
            local normalized = normalizeCityCompanionKey(value)
            if normalized ~= "" then
                candidates[normalized] = true
            end
        end

        addCandidate(opportunity.feedFor)
        addCandidate(opportunity.templateId or opportunity.companionTemplateId)
        addCandidate(opportunity.species or opportunity.animalType or opportunity.kind)
        local template = animal_companions.getTemplate(opportunity.templateId or opportunity.companionTemplateId or
            opportunity.species or opportunity.animalType or opportunity.kind)
        if template then
            addCandidate(template.id)
            addCandidate(template.name)
            addCandidate(template.species)
            addCandidate(template.animalType)
            addCandidate(template.feedType)
            addCandidate(template.aliases)
        end

        return candidates[feedFor] == true
    end

    local function findCityEventFeedItem(owner, opportunity, opts)
        opts = opts or {}
        local inv = owner and owner.inventory
        if not inv then
            return nil, nil
        end

        local explicitItem = opts.cityEventFeedItem or opts.feedItem or opts.dogFeedItem
        if type(explicitItem) == "table" and cityEventAnimalFeedMatches(explicitItem, opportunity) then
            return explicitItem
        end

        local explicitId = opts.cityEventFeedItemId or opts.feedItemId or opts.dogFeedItemId
        if explicitId and inv.findItem then
            local item, location = inv:findItem(explicitId)
            if item and cityEventAnimalFeedMatches(item, opportunity) then
                return item, location
            end
            return nil, nil
        end

        if inv.findItemByPredicate then
            return inv:findItemByPredicate(function(item)
                return cityEventAnimalFeedMatches(item, opportunity)
            end)
        end
        return nil, nil
    end

    local function consumeCityEventFeedItem(owner, item)
        local inv = owner and owner.inventory
        if not inv or not item then
            return false, "not_found"
        end
        if inv.removeItemQuantity then
            return inv:removeItemQuantity(item.id, 1)
        end
        if inv.removeItem then
            local removed = inv:removeItem(item.id)
            return removed ~= nil, removed and "removed" or "not_found"
        end
        return false, "not_found"
    end

    local function cityEventCompanionOwner(controller, opts)
        local explicit = opts.animalCompanionOwner or opts.cityEventCompanionOwner or opts.dogOwner or
            opts.owner or opts.targetActor or opts.target
        if actorId(explicit) then
            return explicit
        end

        local actors = activeAdventurers(opts.guild or controller.guild)
        if explicit ~= nil then
            local wanted = tostring(explicit)
            for _, actor in ipairs(actors) do
                if tostring(actorId(actor) or "") == wanted then
                    return actor
                end
            end
        end
        return actors[1]
    end

    function controller:applyCityEventAnimalCompanionEffects(eventEntry, sign, opts)
        opts = opts or {}
        local effects = mergeCityEventEffects({}, eventEntry and eventEntry.effects)
        effects = mergeCityEventEffects(effects, sign and sign.effects)
        local opportunity = effects.animalCompanionOpportunity or effects.animal_companion_opportunity
        if type(opportunity) ~= "table" then
            return nil
        end

        local wantsToFeed = positiveFlag(firstProvided(
            opts.feedCityEventCompanion,
            opts.feedAnimalCompanion,
            opts.feedDog,
            opts.dogFed,
            opts.adoptDog,
            opts.cityEventCompanionFed,
            opts.animalCompanionOpportunity and opts.animalCompanionOpportunity.feed,
            opts.doggy and opts.doggy.feed
        ))
        local detail = {
            opportunity = opportunity,
            eventValue = eventEntry and eventEntry.value,
            eventTitle = eventEntry and eventEntry.title,
            pending = not wantsToFeed,
            result = wantsToFeed and "city_event_animal_companion_feed_pending" or
                "city_event_animal_companion_opportunity",
        }
        if not wantsToFeed then
            self.lastCityEventAnimalCompanion = detail
            return detail
        end

        local owner = cityEventCompanionOwner(self, opts)
        if not owner then
            detail.pending = true
            detail.reason = "requires_active_adventurer"
            self.lastCityEventAnimalCompanion = detail
            return detail
        end

        local feedItem, feedLocation = findCityEventFeedItem(owner, opportunity, opts)
        if opportunity.feedRequired ~= false and not feedItem and opts.feedProvided ~= true then
            detail.pending = true
            detail.owner = owner
            detail.ownerId = actorId(owner)
            detail.reason = "requires_matching_food"
            self.lastCityEventAnimalCompanion = detail
            return detail
        end

        local consumed = false
        local consumeStatus = "provided"
        if feedItem then
            consumed, consumeStatus = consumeCityEventFeedItem(owner, feedItem)
            if not consumed then
                detail.pending = true
                detail.owner = owner
                detail.ownerId = actorId(owner)
                detail.feedItem = feedItem
                detail.feedItemId = feedItem.id
                detail.feedLocation = feedLocation
                detail.reason = consumeStatus or "feed_not_consumed"
                self.lastCityEventAnimalCompanion = detail
                return detail
            end
        end

        local companion = animal_companions.createCompanion(opportunity.templateId or
            opportunity.companionTemplateId or opportunity.species or "hound", {
                id = opts.companionId or opts.dogCompanionId or
                    string.format("%s_city_event_%s", slugify(actorId(owner)), slugify(opportunity.id or "companion")),
                name = opts.companionName or opts.dogName or opportunity.defaultName or "City Event Companion",
                source = opportunity.source or "city_event",
                knownCommands = {},
            })
        companion.cityEventFollower = true
        companion.followedBecauseFed = true
        companion.eventValue = eventEntry and eventEntry.value
        companion.eventTitle = eventEntry and eventEntry.title

        owner.animalCompanions = owner.animalCompanions or {}
        owner.animalCompanions[#owner.animalCompanions + 1] = companion

        local record = {
            id = opportunity.id or "city_event_companion",
            source = opportunity.source or "city_event",
            eventValue = eventEntry and eventEntry.value,
            eventTitle = eventEntry and eventEntry.title,
            companion = companion,
            companionId = companion.id,
            companionName = companion.name,
            fed = true,
            feedItem = feedItem,
            feedItemId = feedItem and feedItem.id,
            feedLocation = feedLocation,
            feedConsumed = consumed,
            feedStatus = consumeStatus,
        }
        appendActorRecord(owner, opportunity.recordField or "cityEventAnimalCompanions", record)

        detail.pending = false
        detail.owner = owner
        detail.ownerId = actorId(owner)
        detail.companion = companion
        detail.companionId = companion.id
        detail.record = record
        detail.feedItem = feedItem
        detail.feedItemId = feedItem and feedItem.id
        detail.feedLocation = feedLocation
        detail.feedConsumed = consumed
        detail.feedStatus = consumeStatus
        detail.result = "city_event_animal_companion_joined"
        self.lastCityEventAnimalCompanion = detail
        return detail
    end

    function controller:applyCityEventAnimalCompanionCatastropheEffects(eventEntry, sign, opts)
        opts = opts or {}
        local effects = mergeCityEventEffects({}, eventEntry and eventEntry.effects)
        effects = mergeCityEventEffects(effects, sign and sign.effects)
        local catastrophe = effects.animalCompanionCatastrophe or effects.animal_companion_catastrophe
        if type(catastrophe) ~= "table" then
            return nil
        end

        local condition = catastrophe.condition or "dead"
        local casualties = {}
        local owners = activeAdventurers(opts.guild or self.guild)
        for _, owner in ipairs(owners) do
            local seen = {}
            local function visit(companion)
                if type(companion) ~= "table" or seen[companion] then
                    return
                end
                seen[companion] = true
                if cityEventCompanionMatchesCriteria(companion, catastrophe) then
                    companion.conditions = companion.conditions or {}
                    companion.conditions[condition] = true
                    if condition == "dead" then
                        companion.dead = true
                        companion.status = "dead"
                    end
                    companion.cityEventCatastrophe = catastrophe.id or "city_event_animal_catastrophe"
                    companion.cityEventCatastropheSource = catastrophe.source or "city_event"

                    local record = {
                        id = catastrophe.id or "city_event_animal_catastrophe",
                        type = catastrophe.type or "animal_catastrophe",
                        source = catastrophe.source or "city_event",
                        eventValue = eventEntry and eventEntry.value,
                        eventTitle = eventEntry and eventEntry.title,
                        signValue = sign and sign.value,
                        signTitle = sign and sign.title,
                        companion = companion,
                        companionId = companion.id,
                        companionName = companion.name,
                        condition = condition,
                    }
                    appendActorRecord(owner, catastrophe.recordField or "cityEventAnimalCompanionCasualties", record)
                    casualties[#casualties + 1] = {
                        owner = owner,
                        ownerId = actorId(owner),
                        companion = companion,
                        companionId = companion.id,
                        condition = condition,
                        record = record,
                    }
                end
            end

            visit(owner.companion)
            for _, collection in ipairs({ owner.animalCompanions or false, owner.companions or false }) do
                if type(collection) == "table" then
                    for _, companion in pairs(collection) do
                        visit(companion)
                    end
                end
            end
        end

        local detail = {
            effect = catastrophe,
            casualties = casualties,
            casualtyCount = #casualties,
            result = #casualties > 0 and "city_event_animal_companion_catastrophe_resolved" or
                "city_event_animal_companion_catastrophe_no_targets",
        }
        self.lastCityEventAnimalCompanionCatastrophe = detail
        return detail
    end

    function controller:recordConsumedCityEventEntries(eventEntry, sign)
        if eventEntry then
            self.consumedCityEvents[#self.consumedCityEvents + 1] = {
                value = eventEntry.value,
                title = eventEntry.title,
                category = eventEntry.category,
                id = eventEntry.id,
                source = eventEntry.source,
                tableSource = eventEntry.tableSource,
                table = "city_events",
            }
        end
        if sign then
            self.consumedSignsAndPortents[#self.consumedSignsAndPortents + 1] = {
                value = sign.value,
                title = sign.title,
                category = sign.category,
                id = sign.id,
                source = sign.source,
                tableSource = sign.tableSource,
                table = "signs_and_portents",
            }
        end
    end

    function controller:checkCityActionRestrictions(actionId)
        local effects = self.cityEventEffects or {}
        local blocked = effects.blockedCityActions
        if blocked == "all" then
            return false, "City Actions blocked by City Event"
        end

        local plague = self.cityState and self.cityState.undeadPlague
        if self.cityState and self.cityState.cityActionsBlockedByUndead and
           (type(plague) ~= "table" or plague.active ~= false) then
            return false, "City Actions blocked by undead plague"
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

    function controller:resolveCityUndeadPlague(opts)
        opts = opts or {}
        local cityState = opts.cityState or opts.worldState or self.cityState
        local plague = cityState and cityState.undeadPlague
        if type(plague) ~= "table" or plague.active == false then
            return false, "No active undead plague"
        end

        local source = firstProvided(
            opts.undeadSource,
            opts.source,
            opts.sourceLocation,
            opts.underworldSource,
            plague.underworldSource
        )
        if source == nil or tostring(source) == "" then
            return false, "Undead source required"
        end

        local quelled = positiveFlag(firstProvided(
            opts.sourceQuelled,
            opts.quelled,
            opts.quellSource,
            opts.resolved,
            opts.destroyed
        ))
        if not quelled then
            return false, "Undead source not quelled"
        end

        plague.active = false
        plague.status = "quelled"
        plague.underworldSource = source
        plague.quellNotes = opts.notes or opts.note
        plague.quellResult = opts.result or "source_quelled"
        cityState.cityActionsBlockedByUndead = false
        cityState.undeadPlagueQuelled = true
        cityState.lastUndeadPlagueResolution = plague

        local detail = {
            plague = plague,
            cityState = cityState,
            source = source,
            result = "city_undead_plague_quelled",
        }
        self.lastCityUndeadPlagueResolution = detail
        return true, "city_undead_plague_quelled", detail
    end

    function controller:resolveDeathAndTaxes(opts)
        opts = opts or {}
        if self.taxesResolved then
            return false, "Death and taxes already resolved"
        end

        local rate = M.TAX_RATE
        local details = {}
        local totalTax = 0
        local totalBribes = 0
        for index, actor in ipairs(opts.guild or self.guild or {}) do
            local ok, tax = collectDeathAndTaxesForActor(actor, rate, opts, index)
            if not ok then
                return false, tax
            end
            details[#details + 1] = tax
            totalTax = totalTax + (tax.taxPaid or 0)
            totalBribes = totalBribes + (tax.bribePaid or 0)
        end

        local result = {
            step = M.STEPS.DEATH_AND_TAXES,
            rate = rate,
            totalTax = totalTax,
            totalBribes = totalBribes,
            details = details,
            result = "death_and_taxes_resolved",
        }

        self.taxesResolved = true
        self.eventBus:emit(events.EVENTS.CITY_DEATH_AND_TAXES_RESOLVED, result)

        return true, "death_and_taxes_resolved", result
    end

    function controller:getDeathAndTaxesOptions(opts)
        opts = opts or {}
        opts.guild = opts.guild or self.guild
        opts.taxesResolved = opts.taxesResolved or self.taxesResolved
        return M.getDeathAndTaxesOptions(opts)
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
        roster.fameReaction = disposition.getFameReaction(roster.fame, {
            reputation = opts.reputation or opts.deedTone or opts.fameTone or roster.reputation or roster.fameTone,
            favorable = opts.favorable,
        })
        roster.fameDispositionFrame = roster.fameReaction.dispositionFrame

        local detail = {
            step = M.STEPS.NOTEWORTHY_DEEDS,
            roster = roster,
            previousFame = previousFame,
            fame = roster.fame,
            fameReaction = roster.fameReaction,
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

    function controller:getNoteworthyDeedsOptions(opts)
        opts = opts or {}
        opts.guildRoster = opts.guildRoster or opts.roster or self.guildRoster
        if opts.noteworthyDeedsResolved == nil then
            opts.noteworthyDeedsResolved = self.noteworthyDeedsResolved
        end
        return M.getNoteworthyDeedsOptions(opts)
    end

    function controller:getCityEventOptions(opts)
        opts = opts or {}
        opts.guild = opts.guild or self.guild
        opts.gmDeck = opts.gmDeck or self.gmDeck
        opts.playerDeck = opts.playerDeck or self.playerDeck
        opts.cityEventsTable = opts.cityEventsTable or self.cityEventsTable
        opts.cityEventsTableMeta = opts.cityEventsTableMeta or self.cityEventsTableMeta
        opts.signsAndPortentsTable = opts.signsAndPortentsTable or self.signsAndPortentsTable
        opts.signsAndPortentsTableMeta = opts.signsAndPortentsTableMeta or self.signsAndPortentsTableMeta
        if opts.cityEventResolved == nil then
            opts.cityEventResolved = self.cityEventResolved
        end
        return M.getCityEventOptions(opts)
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

        local cityEventsTable = opts.cityEventsTable or opts.city_events_table or self.cityEventsTable
        local cityEventsTableMeta = self.cityEventsTableMeta
        if opts.cityEventsTable or opts.city_events_table then
            cityEventsTable, cityEventsTableMeta = city_events.normalizeEventTable(cityEventsTable, {
                tableName = "city_events",
                source = opts.cityEventsTableSource or opts.cityEventTableSource or opts.city_events_table_source,
                requireComplete = opts.requireCompleteCityEventsTable == true or
                    opts.requireCompleteCityEventTable == true,
            })
        end

        if cityEventsTableMeta and cityEventsTableMeta.requireComplete and not cityEventsTableMeta.complete then
            return false, "City Event table incomplete", cityEventsTableMeta
        end

        local eventEntry = city_events.getEvent(card.value, cityEventsTable)
        if not eventEntry then
            return false, "City Event table entry missing"
        end
        local eventCategory = eventEntry.category or cityEventCategoryForValue(eventEntry.value or card.value)
        eventEntry.category = eventEntry.category or eventCategory

        local minorDeck = opts.playerDeck or opts.minorDeck or self.playerDeck
        local minorDiscard = nil
        if eventCategory == city_events.CATEGORIES.SIGNS_AND_PORTENTS then
            if minorDeck and minorDeck.peekDiscard then
                minorDiscard = minorDeck:peekDiscard()
            end
            minorDiscard = minorDiscard or opts.minorDiscardCard or opts.minorDiscard or
                opts.topMinorDiscardCard or opts.topMinorDiscard
        end

        local sign = nil
        local signsAndPortentsTable = opts.signsAndPortentsTable or opts.signsTable or self.signsAndPortentsTable
        local signsAndPortentsTableMeta = self.signsAndPortentsTableMeta
        if eventCategory == city_events.CATEGORIES.SIGNS_AND_PORTENTS then
            if not minorDiscard then
                return false, "Requires minor discard for Signs and Portents"
            end
            if not isMinorDeckCard(minorDiscard) then
                return false, "Requires minor discard for Signs and Portents"
            end
            if opts.signsAndPortentsTable or opts.signsTable then
                signsAndPortentsTable, signsAndPortentsTableMeta = city_events.normalizeEventTable(signsAndPortentsTable, {
                    tableName = "signs_and_portents",
                    source = opts.signsAndPortentsTableSource or opts.signsTableSource or
                        opts.signs_and_portents_table_source,
                    defaultCategory = city_events.CATEGORIES.SIGNS_AND_PORTENTS,
                    maxValue = 14,
                    requireComplete = opts.requireCompleteSignsAndPortentsTable == true or
                        opts.requireCompleteSignsTable == true,
                })
            end
            if signsAndPortentsTableMeta and signsAndPortentsTableMeta.requireComplete and
                not signsAndPortentsTableMeta.complete then
                return false, "Signs and Portents table incomplete", signsAndPortentsTableMeta
            end
            sign = city_events.getSign(minorDiscard.value, signsAndPortentsTable)
            if not sign then
                return false, "Signs and Portents table entry missing"
            end
        end

        if shouldDiscard and drawnDeck and drawnDeck.discard then
            drawnDeck:discard(card)
        end

        local effects = self:applyCityEventEffects(eventEntry, sign)
        local layoutEffects = self:applyCityEventDistrictEffects(eventEntry, sign, opts)
        local omenEffects = self:applyCityEventOmenEffects(eventEntry, sign, opts)
        local successionEffects = self:applyCityEventSuccessionEffects(eventEntry, sign, opts)
        local undeadPlagueEffects = self:applyCityEventUndeadPlagueEffects(eventEntry, sign, opts)
        local randomTargetEffects = self:applyCityEventRandomTargetEffects(eventEntry, sign, opts)
        local targetedAdventurerEffects = self:applyCityEventTargetedAdventurerEffects(eventEntry, sign, opts)
        local animalCompanionEffects = self:applyCityEventAnimalCompanionEffects(eventEntry, sign, opts)
        local animalCompanionCatastropheEffects = self:applyCityEventAnimalCompanionCatastropheEffects(
            eventEntry, sign, opts
        )
        self:recordConsumedCityEventEntries(eventEntry, sign)
        local detail = {
            step = M.STEPS.CITY_EVENTS,
            card = card,
            event = eventEntry,
            category = eventCategory,
            cityEventsTable = cityEventsTableMeta,
            cityEventsTableSource = cityEventsTableMeta and cityEventsTableMeta.source,
            signCard = minorDiscard,
            sign = sign,
            signsAndPortentsTable = signsAndPortentsTableMeta,
            signsAndPortentsTableSource = signsAndPortentsTableMeta and signsAndPortentsTableMeta.source,
            effects = effects,
            layoutEffects = layoutEffects,
            omenEffects = omenEffects,
            successionEffects = successionEffects,
            undeadPlagueEffects = undeadPlagueEffects,
            randomTargetEffects = randomTargetEffects,
            targetedAdventurerEffects = targetedAdventurerEffects,
            animalCompanionEffects = animalCompanionEffects,
            animalCompanionCatastropheEffects = animalCompanionCatastropheEffects,
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
        local selectedRefs = normalizeList(opts.selectedContractIds or opts.contractIds or opts.selectedContracts or
            opts.selectedContractId or opts.contractId)
        local selectedOnly = #selectedRefs > 0
        local turnInQueue = contracts
        local selectedContractIds = {}
        if selectedOnly then
            turnInQueue = {}
            for _, ref in ipairs(selectedRefs) do
                local refId = type(ref) == "table" and contractId(ref) or ref
                local contract = refId and findContractById(contracts, refId) or nil
                if not contract and type(ref) == "table" and hasContract(contracts, ref) then
                    contract = ref
                end
                if not contract then
                    return false, "Selected contract not active"
                end
                if not isContractComplete(contract) then
                    return false, "Selected contract incomplete"
                end
                if contract.turnedIn == true then
                    return false, "Selected contract already turned in"
                end
                turnInQueue[#turnInQueue + 1] = contract
                selectedContractIds[#selectedContractIds + 1] = contractId(contract)
            end
        end

        local recipients = normalizeRecipientList(opts.recipients or opts.guild or self.guild)
        if #recipients == 0 then
            recipients = activeAdventurers(self.guild)
        end

        local details = {}
        local patronInteractions = {}
        local patronSources = opts.patronInteractions or opts.patronRoleplay or opts.patronScenes or opts.patrons
        local completedCount = 0
        local totalGold = 0
        for index, contract in ipairs(turnInQueue) do
            if isContractComplete(contract) and contract.turnedIn ~= true then
                completedCount = completedCount + 1
                local rewardGold = contractRewardGold(contract)
                local distribution = distributeGold(rewardGold, contract.recipients or recipients, self.guildTreasury)
                local patronInteraction = contractPatronRecord(
                    contract,
                    contractPatronSource(patronSources, contract, index) or
                        contract.patronInteraction or contract.patronRoleplay or contract.turnInScene,
                    index
                )
                contract.turnedIn = true
                contract.turnedInResult = {
                    rewardGold = rewardGold,
                    distribution = distribution,
                    patronInteraction = patronInteraction,
                }
                if patronInteraction then
                    contract.patronHistory = contract.patronHistory or {}
                    contract.patronHistory[#contract.patronHistory + 1] = patronInteraction
                    patronInteractions[#patronInteractions + 1] = patronInteraction
                end
                totalGold = totalGold + rewardGold
                details[#details + 1] = {
                    contract = contract,
                    contractId = contract.id,
                    name = contract.name or contract.title,
                    rewardGold = rewardGold,
                    distribution = distribution,
                    selected = selectedOnly,
                    patronInteraction = patronInteraction,
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
            selected = selectedOnly,
            selectedContractIds = selectedContractIds,
            completedCount = completedCount,
            totalGold = totalGold,
            patronInteractions = patronInteractions,
            xpPerContract = xpPerContract,
            xpAwarded = xpAwarded,
            xpRecipients = xpRecipients,
            guildTreasury = self.guildTreasury,
            result = completedCount > 0 and "contracts_turned_in" or "no_completed_contracts",
        }

        if #patronInteractions > 0 then
            self.guildRoster.contractPatronInteractions = self.guildRoster.contractPatronInteractions or {}
            for _, interaction in ipairs(patronInteractions) do
                self.guildRoster.contractPatronInteractions[#self.guildRoster.contractPatronInteractions + 1] =
                    interaction
            end
        end

        self.contractsResolved = true
        self.eventBus:emit(events.EVENTS.CITY_CONTRACTS_TURNED_IN, result)

        return true, result.result, result
    end

    function controller:getTurnInContractsOptions(opts)
        opts = opts or {}
        opts.contracts = opts.contracts or self.contracts
        opts.guild = opts.guild or self.guild
        opts.guildTreasury = opts.guildTreasury or self.guildTreasury
        if opts.contractsResolved == nil then
            opts.contractsResolved = self.contractsResolved
        end
        return M.getTurnInContractsOptions(opts)
    end

    function controller:resolveDeclareGuildQuest(opts)
        opts = opts or {}
        local quest = opts.quest or opts.currentQuest or opts.newQuest or opts.title or opts.objective
        if type(quest) == "string" then
            quest = quest:gsub("^%s+", ""):gsub("%s+$", "")
            if quest == "" then
                quest = nil
            end
        end
        if not quest then
            return false, "Quest required"
        end
        if opts.requireAgreement ~= false and
            opts.guildAgrees ~= true and opts.everybodyAgrees ~= true and
            opts.agreed ~= true and opts.approved ~= true then
            return false, "Guild agreement required"
        end
        if self.guildRoster.currentQuest and not opts.allowReplaceQuest then
            return false, "Guild already pursuing a quest"
        end
        local questReview = opts.questReview
        if not questReview then
            local _, _, reviewed = quest_rules.reviewQuest({
                quest = quest,
                discrete = opts.discrete,
                achievable = opts.achievable,
                afterCompletion = opts.afterCompletion or opts.newQuestAfterCompletion,
                relatedToPreviousAdventure = opts.relatedToPreviousAdventure,
            })
            questReview = reviewed
        end
        if opts.validateQuest ~= false and questReview and questReview.valid == false then
            return false, questReview.message or "Quest should be discrete and achievable", {
                questReview = questReview,
                result = questReview.result,
            }
        end
        local questPrep = opts.questPrep
        if not questPrep and (opts.objectivePlacement or opts.placement or opts.location or opts.roomId or
            opts.featureId or opts.hints or opts.rumors or opts.associatedCharacters or opts.characters or
            opts.npcs or opts.challenges or opts.obstacles or opts.pathsToVictory or opts.paths) then
            local _, _, prepared = quest_rules.prepareQuest({
                quest = quest,
                discrete = opts.discrete,
                achievable = opts.achievable,
                objectivePlacement = opts.objectivePlacement or opts.placement,
                location = opts.location,
                roomId = opts.roomId,
                featureId = opts.featureId,
                hints = opts.hints,
                rumors = opts.rumors,
                associatedCharacters = opts.associatedCharacters or opts.characters or opts.npcs,
                challenges = opts.challenges or opts.obstacles,
                pathsToVictory = opts.pathsToVictory or opts.paths,
                twists = opts.twists,
                competition = opts.competition,
                trouble = opts.trouble,
            })
            questPrep = prepared
        end

        local recipients = normalizeRecipientList(opts.recipients or opts.guild or self.guild)
        if #recipients == 0 then
            recipients = activeAdventurers(self.guild)
        end
        local xpAwarded = math.max(0, math.floor(tonumber(opts.xpAwarded or opts.xpAward or opts.xp) or
            M.QUEST_XP_AWARD))
        local xpRecipients = {}
        for _, participant in ipairs(recipients) do
            addXP(participant, xpAwarded)
            participant.guildQuest = quest
            appendActorRecord(participant, "questXP", {
                quest = quest,
                xp = xpAwarded,
                reason = "quest_declared",
            })
            xpRecipients[#xpRecipients + 1] = {
                actor = participant,
                actorId = actorId(participant),
                xp = xpAwarded,
            }
        end

        local declaration = {
            quest = quest,
            xpAwarded = xpAwarded,
            xpRecipients = xpRecipients,
            declaredBy = opts.declaredBy or opts.actor,
            declaredById = actorId(opts.declaredBy or opts.actor),
            agreed = true,
            questReview = questReview,
            questPrep = questPrep,
            notes = opts.notes,
        }
        self.guildRoster.currentQuest = quest
        self.guildRoster.currentQuestRecord = declaration
        self.guildRoster.currentQuestReview = questReview
        self.guildRoster.currentQuestPrep = questPrep
        self.guildRoster.questHistory = self.guildRoster.questHistory or {}
        self.guildRoster.questHistory[#self.guildRoster.questHistory + 1] = declaration
        self.questDeclarations[#self.questDeclarations + 1] = declaration

        local detail = {
            quest = quest,
            declaration = declaration,
            xpAwarded = xpAwarded,
            xpRecipients = xpRecipients,
            result = "guild_quest_declared",
        }
        self.eventBus:emit(events.EVENTS.CITY_QUEST_DECLARED, detail)
        return true, "guild_quest_declared", detail
    end

    function controller:resolveCompleteGuildQuest(opts)
        opts = opts or {}
        local quest = opts.quest or opts.currentQuest or self.guildRoster.currentQuest
        if not quest then
            return false, "Current quest required"
        end
        if self.guildRoster.currentQuestCompleted == true and not opts.allowRepeat then
            return false, "Quest already completed"
        end

        local recipients = normalizeRecipientList(opts.recipients or opts.guild or self.guild)
        if #recipients == 0 then
            recipients = activeAdventurers(self.guild)
        end
        local xpAwarded = math.max(0, math.floor(tonumber(opts.xpAwarded or opts.xpAward or opts.xp) or
            M.QUEST_XP_AWARD))
        local xpRecipients = {}
        for _, participant in ipairs(recipients) do
            addXP(participant, xpAwarded)
            participant.completedQuest = quest
            participant.questCompleted = true
            participant.lastCompletedQuest = quest
            appendActorRecord(participant, "questXP", {
                quest = quest,
                xp = xpAwarded,
                reason = "quest_completed",
            })
            xpRecipients[#xpRecipients + 1] = {
                actor = participant,
                actorId = actorId(participant),
                xp = xpAwarded,
            }
        end

        local completion = {
            quest = quest,
            xpAwarded = xpAwarded,
            xpRecipients = xpRecipients,
            notes = opts.notes,
        }
        self.guildRoster.completedQuests = self.guildRoster.completedQuests or {}
        self.guildRoster.completedQuests[#self.guildRoster.completedQuests + 1] = completion
        self.guildRoster.lastCompletedQuest = quest
        self.guildRoster.currentQuestCompleted = true
        if opts.keepCurrentQuest ~= true then
            self.guildRoster.currentQuest = nil
            self.guildRoster.currentQuestRecord = nil
        end
        self.questCompletions[#self.questCompletions + 1] = completion

        local detail = {
            quest = quest,
            completion = completion,
            xpAwarded = xpAwarded,
            xpRecipients = xpRecipients,
            result = "guild_quest_completed",
        }
        self.eventBus:emit(events.EVENTS.CITY_QUEST_COMPLETED, detail)
        return true, "guild_quest_completed", detail
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
        local appraisals = opts.appraisals or opts.appraisalNotes or opts.appraisal
        local buyers = opts.buyers or opts.buyerByItem or opts.buyer
        local markets = opts.markets or opts.marketByItem or opts.market
        local appraisers = opts.appraisers or opts.appraiserByItem or opts.appraiser
        local saleNotes = opts.notes or opts.saleNotes
        local salePlan = {}
        local totalGold = 0
        for _, itemRef in ipairs(itemIds) do
            local itemId = type(itemRef) == "table" and itemRef.id or itemRef
            local itemOverrides = type(itemRef) == "table" and itemRef or {}
            local explicitValue = type(itemRef) == "table" and
                (itemRef.value or itemRef.price or itemRef.saleValue or itemRef.appraisedValue) or values[itemId]
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
            local props = item.properties or {}
            salePlan[#salePlan + 1] = {
                item = item,
                itemId = item.id,
                value = value,
                provenance = itemOverrides.provenance or itemOverrides.origin or props.provenance or props.origin or
                    props.source or item.provenance,
                appraisal = itemOverrides.appraisal or itemOverrides.appraisalNotes or itemOverrides.notes or
                    saleMetadataValue(appraisals, item.id),
                buyer = itemOverrides.buyer or saleMetadataValue(buyers, item.id),
                market = itemOverrides.market or saleMetadataValue(markets, item.id),
                appraiser = itemOverrides.appraiser or saleMetadataValue(appraisers, item.id),
                notes = itemOverrides.saleNotes or itemOverrides.notes or saleMetadataValue(saleNotes, item.id),
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
                    provenance = shallowClone(sale.provenance),
                    appraisal = shallowClone(sale.appraisal),
                    buyer = sale.buyer,
                    market = sale.market,
                    appraiser = sale.appraiser,
                    notes = shallowClone(sale.notes),
                }
            end
        end

        currency.addGold(actor, totalGold)
        local saleRecord = {
            actorId = actorId(actor),
            items = sold,
            totalGold = totalGold,
            buyer = opts.buyer,
            market = opts.market,
            appraiser = opts.appraiser,
            notes = opts.notes,
        }
        appendActorRecord(actor, "treasureSales", saleRecord)

        local result = {
            step = M.STEPS.TURN_IN_CONTRACTS,
            actor = actor,
            items = sold,
            sale = saleRecord,
            totalGold = totalGold,
            result = "treasure_sold",
        }
        self.eventBus:emit(events.EVENTS.CITY_TREASURE_SOLD, result)

        return true, "treasure_sold", result
    end

    function controller:getSellTreasureOptions(actor, opts)
        opts = opts or {}
        opts.actor = actor or opts.actor
        return M.getSellTreasureOptions(opts)
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
                contractTable = opts.contractTable or opts.jobBoardTable or opts.contractsTable or self.contractTable,
                contractTableSource = opts.contractTableSource or opts.tableSource,
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

    function controller:getPlanNextCrawlOptions(opts)
        opts = opts or {}
        opts.guildRoster = opts.guildRoster or self.guildRoster
        opts.contracts = opts.contracts or self.contracts
        opts.jobBoard = opts.jobBoard or self.jobBoard
        opts.contractTable = opts.contractTable or self.contractTable
        opts.playerDeck = opts.playerDeck or self.playerDeck
        opts.nextCrawlPlanned = opts.nextCrawlPlanned or self.nextCrawlPlanned
        return M.getPlanNextCrawlOptions(opts)
    end

    function controller:resolveNewAdventurerJoinGuild(opts)
        opts = opts or {}
        local adventurer = opts.adventurer or opts.newAdventurer or opts.actor
        if not adventurer then
            return false, "New adventurer required"
        end

        local currentQuest = opts.currentQuest or opts.quest or self.guildRoster.currentQuest
        if not currentQuest and opts.allowNoCurrentQuest ~= true then
            return false, "Current quest required"
        end
        if opts.requireCompleteBonds ~= false and adventurer.newAdventurerBondComplete ~= true then
            return false, "Complete guild Bonds required"
        end
        local role = opts.role or opts.guildRole or adventurer.guildRole
        local marchingOrder = opts.marchingOrder or opts.marchingRank or adventurer.marchingOrder
        if opts.requireRosterDetails ~= false then
            if role == nil or tostring(role):gsub("^%s+", ""):gsub("%s+$", "") == "" then
                return false, "Guild role required"
            end
            if marchingOrder == nil or tostring(marchingOrder):gsub("^%s+", ""):gsub("%s+$", "") == "" then
                return false, "Marching order required"
            end
        end

        local rosterAdventurers = getRosterAdventurers(self.guildRoster)
        local rosterChange = {
            addedToGuild = addActorToList(self.guild, adventurer),
            addedToRoster = addActorToList(rosterAdventurers, adventurer),
        }

        local xpAwarded = 0
        if currentQuest and opts.awardXP ~= false then
            xpAwarded = math.max(0, math.floor(tonumber(opts.xpAwarded or opts.xpAward or opts.xp) or
                M.QUEST_XP_AWARD))
            addXP(adventurer, xpAwarded)
        end

        adventurer.joinedGuild = true
        adventurer.guildRole = role
        adventurer.marchingOrder = marchingOrder
        adventurer.guildQuest = currentQuest or adventurer.guildQuest
        local inheritedDiscoveries = {}
        if opts.applyRumorMill ~= false then
            local rumorMillDiscoveries = M.collectRumorMillDiscoveries(self.guildRoster, opts)
            if #rumorMillDiscoveries > 0 then
                local actorDiscoveries = adventurer.rumorMillDiscoveries or adventurer.knownDiscoveries or {}
                local seen = {}
                for _, discovery in ipairs(actorDiscoveries) do
                    local key = M.discoveryRumorKey(discovery)
                    if key then
                        seen[tostring(key)] = true
                    end
                end
                for _, discovery in ipairs(rumorMillDiscoveries) do
                    if M.appendRumorMillDiscovery(actorDiscoveries, seen, discovery) then
                        inheritedDiscoveries[#inheritedDiscoveries + 1] = shallowClone(discovery)
                    end
                end
                adventurer.rumorMillDiscoveries = actorDiscoveries
                adventurer.knownDiscoveries = actorDiscoveries
            end
        end
        appendActorRecord(adventurer, "guildJoins", {
            currentQuest = currentQuest,
            role = adventurer.guildRole,
            marchingOrder = adventurer.marchingOrder,
            xpAwarded = xpAwarded,
            rumorMillDiscoveries = inheritedDiscoveries,
        })

        local join = {
            adventurer = adventurer,
            adventurerId = actorId(adventurer),
            currentQuest = currentQuest,
            role = adventurer.guildRole,
            marchingOrder = adventurer.marchingOrder,
            xpAwarded = xpAwarded,
            rumorMillDiscoveries = inheritedDiscoveries,
            rumorMillDiscoveryCount = #inheritedDiscoveries,
            rosterChange = rosterChange,
        }
        self.guildJoins[#self.guildJoins + 1] = join

        local detail = {
            adventurer = adventurer,
            currentQuest = currentQuest,
            xpAwarded = xpAwarded,
            rumorMillDiscoveries = inheritedDiscoveries,
            rumorMillDiscoveryCount = #inheritedDiscoveries,
            rosterChange = rosterChange,
            join = join,
            result = "new_adventurer_joined_guild",
        }
        self.eventBus:emit(events.EVENTS.CITY_GUILD_JOINED, detail)
        return true, "new_adventurer_joined_guild", detail
    end

    function controller:resolveNewAdventurerDeclineGuild(opts)
        opts = opts or {}
        local adventurer = opts.adventurer or opts.newAdventurer or opts.actor
        if not adventurer then
            return false, "New adventurer required"
        end
        if opts.requireCompleteBonds ~= false and adventurer.newAdventurerBondComplete ~= true then
            return false, "Complete guild Bonds required"
        end

        local rosterAdventurers = getRosterAdventurers(self.guildRoster)
        local rosterChange = {
            removedFromGuild = removeActorFromList(self.guild, adventurer),
            removedFromRoster = removeActorFromList(rosterAdventurers, adventurer),
        }
        adventurer.joinedGuild = false
        adventurer.newAdventurerDeclinedGuild = true
        adventurer.electedReplacementAdventurer = true

        local replacement = {
            adventurer = adventurer,
            adventurerId = actorId(adventurer),
            reason = opts.reason or opts.notes,
            replacementAdventurer = opts.replacementAdventurer or opts.replacement or opts.nextAdventurer,
            replacementName = opts.replacementName,
            rosterChange = rosterChange,
            result = "new_adventurer_replacement_elected",
        }
        appendActorRecord(adventurer, "newAdventurerReplacements", replacement)
        self.newAdventurerReplacementRecords[#self.newAdventurerReplacementRecords + 1] = replacement
        self.guildRoster.newAdventurerReplacements = self.guildRoster.newAdventurerReplacements or {}
        self.guildRoster.newAdventurerReplacements[#self.guildRoster.newAdventurerReplacements + 1] = replacement

        local detail = {
            adventurer = adventurer,
            replacement = replacement,
            rosterChange = rosterChange,
            result = "new_adventurer_replacement_elected",
        }
        self.eventBus:emit(events.EVENTS.CITY_GUILD_JOIN_DECLINED, detail)
        return true, "new_adventurer_replacement_elected", detail
    end

    function controller:resolveNewAdventurerBonds(actor, opts)
        opts = opts or {}
        actor = actor or opts.actor or opts.adventurer or opts.newAdventurer
        if not actor then
            return false, "New adventurer required"
        end

        local actorKey = actorId(actor)
        if not actorKey then
            return false, "New adventurer id required"
        end

        local requireAllGuildMembers = opts.requireAllGuildMembers == true or opts.completeGuildBonds == true or
            opts.secondSession == true
        local targetRefs = normalizeList(opts.targets or opts.players or opts.guildMembers or opts.bondTargets or opts.bonds)
        if #targetRefs == 0 and requireAllGuildMembers then
            targetRefs = activeAdventurers(opts.guild or self.guild)
        end

        local selected = {}
        local targetSeen = {}
        local guildById = {}
        for _, member in ipairs(activeAdventurers(opts.guild or self.guild)) do
            local id = actorId(member)
            if id then
                guildById[id] = member
            end
        end

        for _, ref in ipairs(targetRefs) do
            local entry = type(ref) == "table" and ref or {}
            local explicitTarget = entry.target or entry.player or entry.guildMember or entry.adventurer or entry.actor
            local target = type(ref) == "table" and (explicitTarget or ref) or guildById[ref]
            if type(target) ~= "table" then
                target = guildById[tostring(ref)]
            end
            local targetId = actorId(target)
            if target and targetId and targetId ~= actorKey and not targetSeen[targetId] then
                local status = opts.defaultStatus or "friendship"
                if explicitTarget or entry.bondStatus or entry.bond or entry.relationship or entry.reciprocalStatus then
                    status = entry.status or entry.bondStatus or entry.bond or entry.relationship or status
                end
                local bondInfo = adventurer_module.getBondInfo(status)
                if opts.strictBondTypes == true and not bondInfo then
                    return false, "Unknown Bond type"
                end
                local reciprocalStatus = entry.reciprocalStatus or entry.targetStatus or entry.returnStatus
                selected[#selected + 1] = {
                    target = target,
                    targetId = targetId,
                    status = status,
                    bondInfo = bondInfo,
                    reciprocalStatus = reciprocalStatus,
                }
                targetSeen[targetId] = true
            end
        end

        if requireAllGuildMembers then
            for _, member in ipairs(activeAdventurers(opts.guild or self.guild)) do
                local id = actorId(member)
                if id and id ~= actorKey and not targetSeen[id] then
                    return false, "Bond with every guild member required"
                end
            end
        else
            if #selected < 2 then
                return false, "Choose two Bond targets"
            end
            if #selected > 2 and opts.allowExtraBonds ~= true then
                return false, "Choose exactly two Bond targets"
            end
        end

        actor.bonds = actor.bonds or {}
        local bonds = {}
        for _, selection in ipairs(selected) do
            actor.bonds[selection.targetId] = actor.bonds[selection.targetId] or {}
            actor.bonds[selection.targetId].status = selection.status
            actor.bonds[selection.targetId].charged = actor.bonds[selection.targetId].charged or false
            actor.bonds[selection.targetId].name = selection.target.name
            adventurer_module.applyBondMetadata(actor.bonds[selection.targetId], selection.status)
            bonds[#bonds + 1] = {
                from = actorKey,
                to = selection.targetId,
                status = selection.status,
                bondType = selection.bondInfo and selection.bondInfo.id or nil,
                rulebookName = selection.bondInfo and selection.bondInfo.name or nil,
                chargeTrigger = selection.bondInfo and selection.bondInfo.chargeTrigger or nil,
            }

            if selection.reciprocalStatus then
                local reciprocalInfo = adventurer_module.getBondInfo(selection.reciprocalStatus)
                if opts.strictBondTypes == true and not reciprocalInfo then
                    return false, "Unknown Bond type"
                end
                selection.target.bonds = selection.target.bonds or {}
                selection.target.bonds[actorKey] = selection.target.bonds[actorKey] or {}
                selection.target.bonds[actorKey].status = selection.reciprocalStatus
                selection.target.bonds[actorKey].charged = selection.target.bonds[actorKey].charged or false
                selection.target.bonds[actorKey].name = actor.name
                adventurer_module.applyBondMetadata(selection.target.bonds[actorKey], selection.reciprocalStatus)
            end
        end

        local record = {
            actor = actor,
            actorId = actorKey,
            stage = requireAllGuildMembers and "second_session" or "first_session",
            bonds = bonds,
            completeGuildBonds = requireAllGuildMembers,
        }
        actor.newAdventurerBondStage = record.stage
        actor.newAdventurerBondComplete = requireAllGuildMembers
        appendActorRecord(actor, "newAdventurerBonds", record)
        self.newAdventurerBondRecords[#self.newAdventurerBondRecords + 1] = record
        self.guildRoster.newAdventurerBonds = self.guildRoster.newAdventurerBonds or {}
        self.guildRoster.newAdventurerBonds[#self.guildRoster.newAdventurerBonds + 1] = record

        local detail = {
            actor = actor,
            stage = record.stage,
            bonds = bonds,
            record = record,
            result = "new_adventurer_bonds_selected",
        }
        self.eventBus:emit(events.EVENTS.CITY_NEW_ADVENTURER_BONDS_SELECTED, detail)
        return true, "new_adventurer_bonds_selected", detail
    end

    function controller:getNewAdventurerStartingGearOptions(actor, opts)
        if type(actor) == "table" and opts == nil and
           (actor.actor or actor.adventurer or actor.newAdventurer or actor.items or actor.gear or
            actor.startingGear or actor.marketItems or actor.request) then
            opts = actor
            actor = opts.actor or opts.adventurer or opts.newAdventurer
        end
        opts = opts or {}
        opts.actor = actor or opts.actor
        return M.getNewAdventurerStartingGearOptions(opts)
    end

    function controller:getStartingGearOptions(actor, opts)
        return self:getNewAdventurerStartingGearOptions(actor, opts)
    end

    function controller:resolveNewAdventurerStartingGear(actor, opts)
        opts = opts or {}
        actor = actor or opts.actor or opts.adventurer or opts.newAdventurer
        if not actor then
            return false, "New adventurer required"
        end
        actor.inventory = actor.inventory or inventory.createInventory()
        if not actor.inventory or not actor.inventory.addItem then
            return false, "No inventory for starting gear"
        end

        local talentItemSet = {}
        for _, entry in ipairs(normalizeList(opts.talentItems or opts.talentGear or opts.requiredTalentItems)) do
            local templateId = entry
            if type(entry) == "table" then
                templateId = entry.templateId or entry.itemTemplate or entry.itemTemplateId or entry.id or entry[1]
            end
            if templateId then
                talentItemSet[tostring(templateId)] = true
            end
        end

        local requests = normalizeGearRequests(opts.items or opts.gear or opts.startingGear or opts.marketItems)
        if #requests == 0 then
            return false, "Starting gear required"
        end

        local tierCounts = {
            impoverished = 0,
            common = 0,
            luxurious = 0,
        }
        local planned = {}
        for _, request in ipairs(requests) do
            local templateId = request.templateId and tostring(request.templateId) or nil
            if not templateId then
                return false, "Unknown market item"
            end
            if not item_templates.getTemplate(templateId) then
                return false, "Unknown market item"
            end

            local itemTier = M.MARKET_TIERS[templateId]
            if request.forTalent == true or request.talentRequired == true or request.requiredForTalent == true or
                request.talentItem == true or talentItemSet[templateId] == true then
                itemTier = "impoverished"
            end
            if not MARKET_TIER_RANK[itemTier] then
                return false, "Unknown market item"
            end

            local item = inventory.createItemFromTemplate(templateId, {
                quantity = request.quantity,
            })
            if not item then
                return false, "Unknown market item"
            end
            local location = request.location or inventory.LOCATIONS.PACK
            if item.isArmor or item.oversized then
                location = inventory.LOCATIONS.BELT
            end
            planned[#planned + 1] = {
                templateId = templateId,
                tier = itemTier,
                item = item,
                quantity = request.quantity,
                location = location,
                talentRequired = itemTier == "impoverished" and M.MARKET_TIERS[templateId] ~= "impoverished" or nil,
            }
            tierCounts[itemTier] = (tierCounts[itemTier] or 0) + request.quantity
        end

        if tierCounts.luxurious > 1 then
            return false, "Starting gear allows one luxurious item"
        end
        if tierCounts.common > 5 then
            return false, "Starting gear allows five common items"
        end
        if opts.requireComplete ~= false then
            if tierCounts.luxurious ~= 1 then
                return false, "Starting gear requires one luxurious item"
            end
            if tierCounts.common ~= 5 then
                return false, "Starting gear requires five common items"
            end
        end

        local canAdd, reason = canAddPlannedItemsToInventory(actor.inventory, planned)
        if not canAdd then
            return false, reason
        end

        local added = {}
        for _, itemPlan in ipairs(planned) do
            local ok = actor.inventory:addItem(itemPlan.item, itemPlan.location)
            if ok then
                added[#added + 1] = itemPlan
            end
        end

        local selection = {
            actor = actor,
            actorId = actorId(actor),
            tierCounts = tierCounts,
            counts = tierCounts,
            items = added,
            complete = tierCounts.luxurious == 1 and tierCounts.common == 5,
        }
        actor.startingGearSelected = true
        actor.startingGearSelection = selection
        actor.startingGear = selection
        appendActorRecord(actor, "startingGearSelections", selection)
        self.startingGearSelections[#self.startingGearSelections + 1] = selection

        local detail = {
            actor = actor,
            tierCounts = tierCounts,
            counts = tierCounts,
            items = added,
            selection = selection,
            result = "starting_gear_selected",
        }
        self.eventBus:emit(events.EVENTS.CITY_STARTING_GEAR_SELECTED, detail)
        return true, "starting_gear_selected", detail
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
        local consumedCityEvents = normalizeList(opts.consumedCityEvents or self.consumedCityEvents)
        local consumedSignsAndPortents = normalizeList(
            opts.consumedSignsAndPortents or opts.consumedSigns or self.consumedSignsAndPortents
        )

        local mapUpdates = normalizeList(opts.mapUpdates or opts.changedRooms or opts.mapNotes)
        local factionUpdates = normalizeList(opts.factionUpdates or opts.factions)
        local generateReplacements = opts.generateReplacements or opts.autoGenerateReplacements or
            opts.generateRestockEntries
        local generatedReplacements = nil
        if generateReplacements then
            generatedReplacements = generateRestockReplacements({
                consumedMeatgrinder = consumedMeatgrinder,
                lastCityEvent = opts.lastCityEvent or self.lastCityEvent,
                cityEventValue = opts.cityEventValue or opts.cityEventCardValue,
                mapUpdates = mapUpdates,
                factionUpdates = factionUpdates,
                notes = opts.notes or opts.restockNotes,
            })
        end

        local meatgrinderReplacementInput = opts.meatgrinderReplacements or opts.meatgrinderEntries
        if not meatgrinderReplacementInput and generatedReplacements then
            meatgrinderReplacementInput = generatedReplacements.meatgrinder
        end
        local cityEventReplacementInput = opts.cityEventReplacements or opts.cityEvents
        if not cityEventReplacementInput and generatedReplacements then
            cityEventReplacementInput = generatedReplacements.cityEvents
        end
        cityEventReplacementInput = withConsumedReplacementDefaults(cityEventReplacementInput, consumedCityEvents)
        local signReplacementInput = opts.signsAndPortentsReplacements or opts.signsAndPortents
        if not signReplacementInput and generatedReplacements then
            signReplacementInput = generatedReplacements.signsAndPortents
        end
        signReplacementInput = withConsumedReplacementDefaults(signReplacementInput, consumedSignsAndPortents)

        local meatgrinderReplacements = applyTableReplacements(
            opts.meatgrinderTable or self.meatgrinderTable,
            meatgrinderReplacementInput
        )
        local cityEventReplacements = applyTableReplacements(
            opts.cityEventsTable or self.cityEventsTable,
            cityEventReplacementInput
        )
        local signReplacements = applyTableReplacements(
            opts.signsAndPortentsTable or self.signsAndPortentsTable,
            signReplacementInput
        )
        local restockStateUpdates = applyRestockStateUpdates(self, mapUpdates, factionUpdates)

        if meatgrinder and meatgrinder.resetConsumed then
            meatgrinder:resetConsumed()
        end
        self.consumedCityEvents = {}
        self.consumedSignsAndPortents = {}

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
            consumedCityEvents = consumedCityEvents,
            consumedSignsAndPortents = consumedSignsAndPortents,
            meatgrinderReplacements = meatgrinderReplacements,
            cityEventReplacements = cityEventReplacements,
            signsAndPortentsReplacements = signReplacements,
            generatedReplacements = generatedReplacements,
            mapUpdates = mapUpdates,
            factionUpdates = factionUpdates,
            stateUpdates = restockStateUpdates,
            mapsReviewed = self.guildRoster.mapsReviewed,
            notes = note.notes,
            result = "underworld_restocked",
        }

        self.underworldRestocked = true
        self.eventBus:emit(events.EVENTS.CITY_UNDERWORLD_RESTOCKED, detail)

        return true, "underworld_restocked", detail
    end

    function controller:getRestockUnderworldOptions(opts)
        opts = opts or {}
        opts.meatgrinder = opts.meatgrinder or self.meatgrinder
        opts.meatgrinderTable = opts.meatgrinderTable or self.meatgrinderTable
        opts.cityEventsTable = opts.cityEventsTable or self.cityEventsTable
        opts.signsAndPortentsTable = opts.signsAndPortentsTable or self.signsAndPortentsTable
        opts.consumedCityEvents = opts.consumedCityEvents or self.consumedCityEvents
        opts.consumedSignsAndPortents = opts.consumedSignsAndPortents or self.consumedSignsAndPortents
        opts.underworldState = opts.underworldState or self.underworldState
        opts.cityState = opts.cityState or self.cityState
        opts.lastCityEvent = opts.lastCityEvent or self.lastCityEvent
        opts.underworldRestocked = opts.underworldRestocked or self.underworldRestocked
        return M.getRestockUnderworldOptions(opts)
    end

    function controller:getUpkeepOptions(actor, opts)
        opts = opts or {}
        opts.actor = actor or opts.actor
        opts.cityEventEffects = opts.cityEventEffects or self.cityEventEffects
        opts.upkeepCompleted = opts.upkeepCompleted or self.upkeepCompleted
        return M.getUpkeepOptions(opts)
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
                local templateId = request.templateId and tostring(request.templateId) or nil
                local itemTier
                local item
                local custom = not templateId
                if templateId then
                    if not item_templates.getTemplate(templateId) then
                        return false, "Unknown market item"
                    end
                    itemTier = M.MARKET_TIERS[templateId]
                    item = inventory.createItemFromTemplate(templateId, {
                        quantity = request.quantity,
                    })
                else
                    local itemName = request.name and tostring(request.name):gsub("^%s+", ""):gsub("%s+$", "")
                    if not request.custom or not itemName or itemName == "" then
                        return false, "Unknown market item"
                    end
                    itemTier = normalizeUpkeepTier(request.tier)
                    if not MARKET_TIER_RANK[itemTier] then
                        return false, "Custom gear tier required"
                    end
                    local properties = shallowClone(request.properties or {})
                    properties.upkeepCustom = true
                    properties.marketTier = itemTier
                    item = inventory.createItem({
                        id = request.customId,
                        name = itemName,
                        size = request.size,
                        oversized = request.oversized,
                        stackable = request.stackable,
                        stackSize = request.stackSize,
                        quantity = request.quantity,
                        type = request.itemType,
                        properties = properties,
                    })
                    item.marketTier = itemTier
                    item.upkeepCustom = true
                end
                if not canBuyMarketTier(tier.refillTier, itemTier) then
                    return false, "Gear tier not covered by upkeep"
                end
                if not item then
                    return false, "Unknown market item"
                end
                plannedGear[#plannedGear + 1] = {
                    templateId = templateId,
                    tier = itemTier,
                    item = item,
                    location = request.location or inventory.LOCATIONS.PACK,
                    custom = custom,
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
        local nextCrawlConditions = nil
        local upkeepConsequences = {}
        if tier.id == "destitute" then
            actor.conditions = actor.conditions or {}
            actor.conditions.stressed = true
            actor.nextCrawlConditions = actor.nextCrawlConditions or {}
            actor.nextCrawlConditions.stressed = true
            nextCrawlConditions = actor.nextCrawlConditions
            upkeepConsequences[#upkeepConsequences + 1] = {
                condition = "stressed",
                nextCrawlCondition = "stressed",
                source = "destitute_upkeep",
            }
        end
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
            nextCrawlConditions = nextCrawlConditions,
            consequences = upkeepConsequences,
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
        local explicitCard = actionData.card or actionData.drawnCard
        if explicitCard then
            if not isMinorDeckCard(explicitCard) then
                return nil, false
            end
            return explicitCard, false
        end

        local deck = actionData.deck or actionData.playerDeck or actionData.minorDeck or self.playerDeck
        if deck and deck.draw then
            local card = deck:draw()
            if not isMinorDeckCard(card) then
                return nil, false, deck
            end
            return card, true, deck
        end

        return nil, false, deck
    end

    function controller:drawMajorCard(actionData)
        actionData = actionData or {}
        local explicitCard = actionData.hangoverCard or actionData.majorCard or actionData.card
        if explicitCard then
            if not isMajorDeckCard(explicitCard) then
                return nil, false
            end
            return explicitCard, false
        end

        local deck = actionData.gmDeck or actionData.majorDeck or self.gmDeck
        if deck and deck.draw then
            local card = deck:draw()
            if not isMajorDeckCard(card) then
                return nil, false, deck
            end
            return card, true, deck
        end

        return nil, false, deck
    end

    function controller:applyBankingReturns(actorOrGuild, opts)
        opts = opts or {}
        local actors = actorOrGuild or self.guild or {}
        if actorId(actors) then
            actors = { actors }
        end

        local rate = M.BANKING_RETURN_RATE
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

    function controller:getBankingOptions(actor, opts)
        opts = opts or {}
        opts.actor = actor or opts.actor
        return M.getBankingOptions(opts)
    end

    function controller:getBegAndBuskOptions(actor, opts)
        opts = opts or {}
        opts.actor = actor or opts.actor
        opts.playerDeck = opts.playerDeck or self.playerDeck
        return M.getBegAndBuskOptions(opts)
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

        local syllables, syllableError = resolveSyllables(request)
        if not syllables then
            return false, syllableError
        end
        if syllables <= 0 then
            return false, "Building description required"
        end

        local projectId = normalizeProjectId(request.projectId or request.id or description)
        if self.buildings[projectId] then
            return false, "Building project already exists"
        end

        local artisanInput = request.artisan or request.designer
        local artisanRecord = type(artisanInput) == "table" and shallowClone(artisanInput) or nil
        local artisanName = artisanRecord and (artisanRecord.name or artisanRecord.id) or artisanInput
        local districtInput = request.district or request.cityDistrict or request.districtRecord
        local districtId = request.districtId or request.cityDistrictId or request.district_id
        local districtName = request.districtName or request.cityDistrictName
        if type(districtInput) == "table" then
            districtId = districtId or districtInput.id or districtInput.districtId
            districtName = districtName or districtInput.name or districtInput.title
        elseif districtInput then
            districtId = districtId or districtInput
            districtName = districtName or districtInput
        end
        if artisanRecord then
            districtId = districtId or artisanRecord.districtId or artisanRecord.cityDistrictId
            districtName = districtName or artisanRecord.districtName or artisanRecord.cityDistrictName
        end

        local cityLayout = request.cityLayout or self.cityLayout
        local districtPlacement = nil
        if cityLayout and districtId then
            districtPlacement = findDistrictPlacement(cityLayout, districtId)
            if not districtPlacement and request.requireDistrict ~= false then
                return false, "City district not found"
            end
            if districtPlacement and not districtName then
                districtName = districtPlacement.district and districtPlacement.district.name or districtPlacement.districtName
            end
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
            artisan = artisanName,
            artisanRecord = artisanRecord,
            districtId = districtId,
            districtName = districtName,
            syllables = syllables,
            cost = cost,
            builtBy = actor,
            builtById = actorId(actor),
            complete = true,
        }
        self.buildings[projectId] = building

        local cityLayoutEntry = nil
        if cityLayout then
            cityLayout.buildings = cityLayout.buildings or {}
            cityLayoutEntry = {
                buildingId = projectId,
                name = building.name,
                districtId = districtId,
                districtName = districtName,
                builtById = building.builtById,
                artisan = artisanName,
            }
            cityLayout.buildings[#cityLayout.buildings + 1] = cityLayoutEntry
            if districtPlacement then
                districtPlacement.buildings = districtPlacement.buildings or {}
                districtPlacement.buildings[#districtPlacement.buildings + 1] = cityLayoutEntry
            end
            building.cityLayoutEntry = cityLayoutEntry
        end

        return true, "building_complete", {
            actor = actor,
            action = M.ACTIONS.BUILD,
            building = building,
            projectId = projectId,
            cityLayoutEntry = cityLayoutEntry,
            syllables = syllables,
            cost = cost,
            result = "building_complete",
        }
    end

    function controller:getBuildProjectOption(actor, opts)
        opts = opts or {}
        opts.actor = actor or opts.actor
        opts.buildings = opts.buildings or self.buildings
        opts.cityLayout = opts.cityLayout or self.cityLayout
        return M.getBuildProjectOption(opts)
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

    function controller:getCityCampActionOptions(actor, opts)
        opts = opts or {}
        opts.actor = actor or opts.actor
        opts.guild = opts.guild or self.guild
        opts.context = opts.context or opts.campContext or cityCampActionContext(self, opts)
        return M.getCityCampActionOptions(opts)
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

        local syllables, syllableError = resolveSyllables(request)
        if not syllables then
            return false, syllableError
        end
        if syllables <= 0 then
            return false, "Commission description required"
        end

        local commissionId = normalizeProjectId(request.commissionId or request.id or description)
        if self.commissions[commissionId] then
            return false, "Commission already exists"
        end

        local merchantInput = request.merchant or request.merchantId or request.artisan or request.artisanId or
            request.crafter or request.crafterId
        local merchantRecord, merchantState, merchantKey = findMerchantRecord(self.merchants, merchantInput)
        if request.requireMerchant == true and not merchantRecord then
            return false, "Commission merchant not found"
        end
        local merchantName = merchantDisplayName(merchantInput, merchantRecord)
        local merchantId = merchantRecord and (merchantRecord.id or merchantRecord.merchantId or merchantKey) or nil
        local merchantDistrictId = merchantRecord and
            (merchantRecord.districtId or merchantRecord.cityDistrictId or merchantRecord.district_id) or nil
        local merchantDistrictName = merchantRecord and
            (merchantRecord.districtName or merchantRecord.cityDistrictName or merchantRecord.district) or nil
        local merchantSpecialties = merchantRecord and
            (merchantRecord.specialties or merchantRecord.craftSpecialties or merchantRecord.commissionSpecialties) or nil

        local cost = syllables * rate
        local deliveryRequest = request.deliverItem or request.item or request.itemSpec or request.rewardItem
        local wantsDelivery = request.deliver == true or request.addToInventory == true or
            request.deliverToInventory == true or deliveryRequest ~= nil or
            request.itemTemplateId ~= nil or request.templateId ~= nil
        local deliveryPlan = nil
        if wantsDelivery then
            if not actor or not actor.inventory or not actor.inventory.addItem then
                return false, "No inventory for commissioned item"
            end

            local templateId = request.itemTemplateId or request.templateId
            if not templateId and type(deliveryRequest) == "string" then
                templateId = deliveryRequest
            end

            local item = nil
            if templateId then
                item = inventory.createItemFromTemplate(templateId, request.itemOverrides or request.overrides)
                if not item then
                    return false, "Unknown commissioned item"
                end
            elseif type(deliveryRequest) == "table" then
                item = inventory.createItem(shallowClone(deliveryRequest))
            else
                item = inventory.createItem({
                    id = request.itemId or (commissionId .. "_item"),
                    name = request.itemName or request.name or request.title or description,
                    type = request.itemType or "commissioned_craft",
                    size = request.size,
                    oversized = request.oversized,
                    properties = shallowClone(request.itemProperties or request.properties or {}),
                })
            end

            item.name = request.itemName or item.name or request.name or request.title or description
            item.properties = item.properties or {}
            item.properties.commissioned = true
            item.properties.commissionId = commissionId
            item.properties.commissionScale = scale
            item.properties.commissionMerchant = merchantName
            item.properties.commissionMerchantId = merchantId
            item.properties.commissionMerchantDistrictId = merchantDistrictId
            deliveryPlan = {
                item = item,
                location = request.location or request.itemLocation or inventory.LOCATIONS.PACK,
            }

            local canAdd, reason = canAddPlannedItemsToInventory(actor.inventory, { deliveryPlan })
            if not canAdd then
                return false, reason
            end
        end

        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end
        if not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        local deliveredItem = nil
        if deliveryPlan then
            local added, reason = addPlannedItems(actor.inventory, { deliveryPlan })
            if not added then
                return false, reason or "insufficient_slots"
            end
            deliveredItem = added[1]
        end

        appendCommissionToMerchant(merchantState, commissionId)
        if merchantRecord then
            appendCommissionToMerchant(merchantRecord, commissionId)
        end

        local commission = {
            id = commissionId,
            name = request.name or request.title or description,
            description = description,
            merchant = merchantName,
            merchantId = merchantId,
            merchantRecord = merchantRecord,
            merchantRegistryKey = merchantKey,
            merchantDistrictId = merchantDistrictId,
            merchantDistrictName = merchantDistrictName,
            merchantSpecialties = merchantSpecialties and shallowClone(merchantSpecialties) or nil,
            scale = scale,
            ratePerSyllable = rate,
            syllables = syllables,
            cost = cost,
            commissionedBy = actor,
            commissionedById = actorId(actor),
            complete = true,
            delivered = deliveredItem ~= nil,
            deliveredItem = deliveredItem,
            deliveredItemId = deliveredItem and deliveredItem.id or nil,
            deliveredLocation = deliveryPlan and deliveryPlan.location or nil,
        }
        self.commissions[commissionId] = commission

        return true, "commission_complete", {
            actor = actor,
            action = M.ACTIONS.COMMISSION_CRAFT,
            commission = commission,
            commissionId = commissionId,
            deliveredItem = deliveredItem,
            deliveredLocation = deliveryPlan and deliveryPlan.location or nil,
            scale = scale,
            merchant = merchantName,
            merchantId = merchantId,
            merchantRecord = merchantRecord,
            ratePerSyllable = rate,
            syllables = syllables,
            cost = cost,
            result = "commission_complete",
        }
    end

    function controller:getCommissionCraftOptions(actor, opts)
        opts = opts or {}
        opts.actor = actor or opts.actor
        opts.commissions = opts.commissions or self.commissions
        opts.merchants = opts.merchants or self.merchants
        return M.getCommissionCraftOptions(opts)
    end

    function controller:resolveHoldFuneral(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.funeral or actionData
        local deceased = request.deceased or request.deadAdventurer or request.previousAdventurer
        local heir = request.newAdventurer or request.heir or request.recipient or actor
        local previousXP = tonumber(request.previousXP or request.deceasedXP or (deceased and deceased.xp))
        local xpReclaimed = tonumber(request.xpReclaimed or request.xp or request.amount)

        if not xpReclaimed or xpReclaimed <= 0 then
            return false, "Funeral XP required"
        end
        if xpReclaimed ~= math.floor(xpReclaimed) then
            return false, "Funeral XP must be a positive whole number"
        end
        if not previousXP then
            return false, "Deceased XP required"
        end
        if deceased and not isDeadAdventurer(deceased) then
            return false, "Adventurer must be dead"
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
        heir.replacesAdventurerId = actorId(deceased)

        local rosterChange = {
            updated = request.updateRoster ~= false,
            removedDeceasedFromGuild = false,
            removedDeceasedFromRoster = false,
            addedHeirToGuild = false,
            addedHeirToRoster = false,
        }
        if rosterChange.updated then
            local rosterAdventurers = getRosterAdventurers(self.guildRoster)
            if deceased and request.removeDeceased ~= false then
                rosterChange.removedDeceasedFromGuild = removeActorFromList(self.guild, deceased)
                rosterChange.removedDeceasedFromRoster = removeActorFromList(rosterAdventurers, deceased)
                deceased.funeralHeld = true
                deceased.replacedById = actorId(heir)
            end
            if heir and request.addHeirToGuild ~= false then
                rosterChange.addedHeirToGuild = addActorToList(self.guild, heir)
                rosterChange.addedHeirToRoster = addActorToList(rosterAdventurers, heir)
            end
        end

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
            rosterChange = rosterChange,
        }
        self.funerals[#self.funerals + 1] = funeral

        return true, "funeral_held", {
            actor = actor,
            action = M.ACTIONS.HOLD_FUNERAL,
            funeral = funeral,
            xpReclaimed = xpReclaimed,
            cost = cost,
            recipient = heir,
            rosterChange = rosterChange,
            result = "funeral_held",
        }
    end

    function controller:getFuneralOptions(actor, opts)
        opts = opts or {}
        opts.actor = actor or opts.actor
        opts.guild = opts.guild or self.guild
        opts.guildRoster = opts.guildRoster or self.guildRoster
        return M.getFuneralOptions(opts)
    end

    function controller:getRetirementChoiceOptions(actor, opts)
        if type(actor) == "table" and opts == nil and
           (actor.actor or actor.request or actor.retirement or actor.newQuestDeclaration or actor.newQuest) then
            opts = actor
            actor = opts.actor or opts.adventurer or opts.retiree
        end
        opts = opts or {}
        opts.actor = actor or opts.actor or opts.adventurer or opts.retiree
        opts.guild = opts.guild or self.guild
        opts.guildRoster = opts.guildRoster or self.guildRoster
        local options = M.getRetirementChoiceOptions(opts)
        local alreadyActed = self:hasActed(options.actor)
        options.alreadyActed = alreadyActed

        local retirementAllowed, retirementReason = self:checkCityActionRestrictions(M.ACTIONS.RETIRE_ADVENTURER)
        options.retirement.cityActionAllowed = retirementAllowed == true
        options.retirement.cityActionUnavailableReason = retirementAllowed ~= true and retirementReason or nil
        if alreadyActed and not options.retirement.disabled then
            options.retirement.disabled = true
            options.retirement.unavailableReason = "City Action already taken"
        elseif retirementAllowed ~= true and not options.retirement.disabled then
            options.retirement.disabled = true
            options.retirement.unavailableReason = retirementReason
        end
        options.retirement.resultPreview = not options.retirement.disabled and "adventurer_retired" or nil

        local questAllowed, questReason = self:checkCityActionRestrictions(M.ACTIONS.DECLARE_NEW_QUEST)
        options.newQuest.cityActionAllowed = questAllowed == true
        options.newQuest.cityActionUnavailableReason = questAllowed ~= true and questReason or nil
        if alreadyActed and not options.newQuest.disabled then
            options.newQuest.disabled = true
            options.newQuest.unavailableReason = "City Action already taken"
        elseif questAllowed ~= true and not options.newQuest.disabled then
            options.newQuest.disabled = true
            options.newQuest.unavailableReason = questReason
        end
        options.newQuest.resultPreview = not options.newQuest.disabled and "new_quest_declared" or nil
        return options
    end

    function controller:getRetirementOptions(actor, opts)
        return self:getRetirementChoiceOptions(actor, opts)
    end

    function controller:getDeclareNewQuestOptions(actor, opts)
        return self:getRetirementChoiceOptions(actor, opts)
    end

    function controller:resolveRetireAdventurer(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.retirement or actionData
        local retiree = request.retiree or request.adventurer or request.completedAdventurer or actor
        if not retiree then
            return false, "Retiring adventurer required"
        end

        local questComplete = request.questCompleted == true or
            request.questComplete == true or
            (request.completedQuest ~= nil and request.completedQuest ~= false) or
            retiree.questCompleted == true or
            (retiree.completedQuest ~= nil and retiree.completedQuest ~= false) or
            retiree.questStatus == "complete" or
            (type(retiree.quest) == "table" and retiree.quest.completed == true)
        if not questComplete then
            return false, "Quest must be complete"
        end
        if isDeadAdventurer(retiree) or retiree.lost == true or retiree.status == "lost" then
            return false, "Retirement requires a living adventurer"
        end

        local retiredXP = tonumber(request.retiredXP or request.previousXP or retiree.xp or retiree.XP) or 0
        retiredXP = math.max(0, math.floor(retiredXP))
        local benefitSlots = math.floor(retiredXP / 10)
        local successor = request.newAdventurer or request.successor or request.nextAdventurer or request.heir
        local benefitRequests = {}
        if type(request.benefits) == "table" then
            for _, benefit in ipairs(request.benefits) do
                if type(benefit) == "table" then
                    local count = math.max(1, math.floor(tonumber(benefit.count or benefit.amount) or 1))
                    local kind = normalizeTalentId(benefit.type or benefit.kind or "")
                    if kind == "arete" or kind == "arete_check" or kind == "arete_check_mark" then
                        for _ = 1, count do
                            benefitRequests[#benefitRequests + 1] = { type = "arete_check" }
                        end
                    else
                        benefitRequests[#benefitRequests + 1] = benefit
                    end
                else
                    benefitRequests[#benefitRequests + 1] = benefit
                end
            end
        end

        local masteredTalents = request.masteredTalents or request.masteredTalent
        if type(masteredTalents) == "table" then
            for _, talentId in ipairs(masteredTalents) do
                benefitRequests[#benefitRequests + 1] = { type = "talent", talentId = talentId }
            end
        elseif masteredTalents then
            benefitRequests[#benefitRequests + 1] = { type = "talent", talentId = masteredTalents }
        end
        if request.talentId or request.talent then
            benefitRequests[#benefitRequests + 1] = { type = "talent", talentId = request.talentId or request.talent }
        end
        local areteChecks = tonumber(request.areteChecks or request.areteCheckMarks or request.areteMarks) or 0
        areteChecks = math.max(0, math.floor(areteChecks))
        for _ = 1, areteChecks do
            benefitRequests[#benefitRequests + 1] = { type = "arete_check" }
        end

        if #benefitRequests > benefitSlots then
            return false, "Retirement benefits exceed available slots"
        end
        if #benefitRequests > 0 and not successor then
            return false, "Successor adventurer required"
        end

        local appliedBenefits = {}
        if successor then
            successor.retirementBenefits = successor.retirementBenefits or {}
        end
        for _, rawBenefit in ipairs(benefitRequests) do
            local benefit = rawBenefit
            if type(benefit) == "string" then
                benefit = { type = "talent", talentId = benefit }
            elseif type(benefit) ~= "table" then
                return false, "Retirement benefit invalid"
            end

            local kind = normalizeTalentId(benefit.type or benefit.kind or "")
            if kind == "arete" or kind == "arete_check" or kind == "arete_check_mark" or benefit.areteCheck == true then
                successor.arete = successor.arete or
                    talent_catalog.getAreteSetup(successor.kin or successor.species or successor.race, successor.kith)

                local triggerRef = benefit.triggerId or benefit.trigger or benefit.areteTrigger or benefit.id or benefit.name
                if not triggerRef and successor.arete then
                    for _, trigger in ipairs(successor.arete.triggers or {}) do
                        if trigger.checked ~= true then
                            triggerRef = trigger.id
                            break
                        end
                    end
                end

                local applied = {
                    type = "arete_check",
                    sourceAdventurerId = actorId(retiree),
                }
                if successor.arete then
                    if not triggerRef then
                        return false, "No unchecked arete triggers"
                    end
                    local areteOk, areteResult = talent_catalog.recordAreteTrigger(successor, triggerRef)
                    if not areteOk then
                        return false, areteResult
                    end
                    if areteResult.alreadyChecked then
                        return false, "Arete trigger already checked"
                    end
                    applied.triggerId = areteResult.triggerId
                    applied.talentId = areteResult.talentId
                    applied.checkCount = areteResult.checkCount
                    applied.requiredChecks = areteResult.requiredChecks
                    applied.completed = areteResult.completed
                    applied.learned = areteResult.learned
                else
                    successor.areteCheckMarks = (tonumber(successor.areteCheckMarks) or 0) + 1
                    applied.checkCount = successor.areteCheckMarks
                    applied.triggerId = triggerRef
                end
                successor.retirementAreteCheckMarks = (tonumber(successor.retirementAreteCheckMarks) or 0) + 1
                appliedBenefits[#appliedBenefits + 1] = applied
                successor.retirementBenefits[#successor.retirementBenefits + 1] = applied
            else
                local talentId = normalizeTalentId(benefit.talentId or benefit.talent or benefit.id or benefit.name)
                if talentId == "" then
                    return false, "Retirement talent required"
                end

                successor.talents = successor.talents or {}
                local talent = successor.talents[talentId]
                if type(talent) ~= "table" then
                    talent = {}
                    successor.talents[talentId] = talent
                end
                local talentInfo = talent_catalog.getTalentInfo(talentId)
                talent.mastered = true
                talent.wounded = talent.wounded == true
                talent.xp_invested = math.max(tonumber(talent.xp_invested) or 0, 7)
                talent.retirementBenefit = true
                talent.path = talent.path or (talentInfo and talentInfo.path)
                talent.trainingKind = talent.trainingKind or (talentInfo and talentInfo.kind) or "retirement"

                local applied = {
                    type = "mastered_talent",
                    talentId = talentId,
                    sourceAdventurerId = actorId(retiree),
                }
                appliedBenefits[#appliedBenefits + 1] = applied
                successor.retirementBenefits[#successor.retirementBenefits + 1] = applied
            end
        end

        local rosterChange = {
            updated = request.updateRoster ~= false,
            removedRetireeFromGuild = false,
            removedRetireeFromRoster = false,
            addedSuccessorToGuild = false,
            addedSuccessorToRoster = false,
        }
        if rosterChange.updated then
            local rosterAdventurers = getRosterAdventurers(self.guildRoster)
            if request.removeRetiree ~= false then
                rosterChange.removedRetireeFromGuild = removeActorFromList(self.guild, retiree)
                rosterChange.removedRetireeFromRoster = removeActorFromList(rosterAdventurers, retiree)
            end
            if successor and request.addSuccessorToGuild ~= false then
                rosterChange.addedSuccessorToGuild = addActorToList(self.guild, successor)
                rosterChange.addedSuccessorToRoster = addActorToList(rosterAdventurers, successor)
            end
        end

        retiree.retired = true
        retiree.retiredInCity = true
        retiree.livesInCity = true
        retiree.controlledByGM = true
        retiree.gmControlled = true
        retiree.status = "retired"
        retiree.replacedById = actorId(successor)
        if successor then
            successor.replacesAdventurerId = actorId(retiree)
        end

        local retirement = {
            retiree = retiree,
            retireeId = actorId(retiree),
            retireeName = request.retireeName or retiree.name,
            retiredXP = retiredXP,
            benefitSlots = benefitSlots,
            unspentBenefitSlots = benefitSlots - #appliedBenefits,
            successor = successor,
            successorId = actorId(successor),
            benefits = appliedBenefits,
            rosterChange = rosterChange,
            quest = request.completedQuest or retiree.completedQuest or retiree.quest,
        }
        retiree.retirementRecord = retirement
        self.retirements[#self.retirements + 1] = retirement

        local additionalCityActors = nil
        if successor and request.markSuccessorActed ~= false and
            (rosterChange.addedSuccessorToGuild or rosterChange.addedSuccessorToRoster) then
            additionalCityActors = {
                {
                    actor = successor,
                    action = M.ACTIONS.RETIRE_ADVENTURER,
                    result = "successor_arrived",
                },
            }
        end

        return true, "adventurer_retired", {
            actor = retiree,
            action = M.ACTIONS.RETIRE_ADVENTURER,
            retirement = retirement,
            retiredXP = retiredXP,
            benefitSlots = benefitSlots,
            benefits = appliedBenefits,
            successor = successor,
            rosterChange = rosterChange,
            additionalCityActors = additionalCityActors,
            result = "adventurer_retired",
        }
    end

    function controller:resolveDeclareNewQuest(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.newQuestDeclaration or actionData
        local adventurer = request.adventurer or request.retiree or actor
        if not adventurer then
            return false, "Adventurer required"
        end

        local questComplete = request.questCompleted == true or
            request.questComplete == true or
            (request.completedQuest ~= nil and request.completedQuest ~= false) or
            adventurer.questCompleted == true or
            (adventurer.completedQuest ~= nil and adventurer.completedQuest ~= false) or
            adventurer.questStatus == "complete" or
            (type(adventurer.quest) == "table" and adventurer.quest.completed == true)
        if not questComplete then
            return false, "Quest must be complete"
        end
        if isDeadAdventurer(adventurer) or adventurer.lost == true or adventurer.status == "lost" then
            return false, "New quest requires a living adventurer"
        end

        local newQuest = request.newQuest or request.nextQuest or request.questTitle or request.objective or request.quest
        if type(newQuest) == "string" then
            newQuest = newQuest:gsub("^%s+", ""):gsub("%s+$", "")
            if newQuest == "" then
                newQuest = nil
            end
        end
        if not newQuest then
            return false, "New quest required"
        end

        local previousQuest = request.completedQuest or request.previousQuest or adventurer.completedQuest or adventurer.quest
        addXP(adventurer, 3)
        adventurer.questHistory = adventurer.questHistory or {}
        adventurer.questHistory[#adventurer.questHistory + 1] = {
            quest = previousQuest,
            completed = true,
            xpAwarded = 3,
            continuedWith = newQuest,
        }
        adventurer.lastCompletedQuest = previousQuest
        adventurer.completedQuest = nil
        adventurer.questCompleted = false
        adventurer.questStatus = "active"
        adventurer.quest = newQuest
        adventurer.retired = false

        local declaration = {
            adventurer = adventurer,
            adventurerId = actorId(adventurer),
            previousQuest = previousQuest,
            newQuest = newQuest,
            xpGained = 3,
        }
        self.questDeclarations[#self.questDeclarations + 1] = declaration

        return true, "new_quest_declared", {
            actor = adventurer,
            action = M.ACTIONS.DECLARE_NEW_QUEST,
            declaration = declaration,
            previousQuest = previousQuest,
            newQuest = newQuest,
            xpGained = 3,
            result = "new_quest_declared",
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

        local minorDeck = request.playerDeck or request.minorDeck or self.playerDeck
        local minorDiscard = nil
        if minorDeck and minorDeck.peekDiscard then
            minorDiscard = minorDeck:peekDiscard()
        end
        minorDiscard = minorDiscard or request.minorDiscardCard or request.minorDiscard or
            request.topMinorDiscardCard or request.topMinorDiscard
        local invalidMinorDiscard = nil
        if minorDiscard and not isMinorDeckCard(minorDiscard) then
            invalidMinorDiscard = minorDiscard
            minorDiscard = nil
        end

        local hangover = M.HANGOVER_TABLE[hangoverCard.value] or {
            id = "unknown_hangover",
            title = "Unknown Hangover",
        }
        local hangoverOutcome = resolveHangoverOutcome(actor, hangover, minorDiscard)
        local carouseConsequences = recordCarouseConsequences(self, actor, hangover, hangoverOutcome, request)

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
            carouseConsequences = carouseConsequences,
            minorDiscard = minorDiscard,
            invalidMinorDiscard = invalidMinorDiscard,
            result = "carouse_resolved",
        }
        actor.lastCarouse = detail
        appendActorRecord(actor, "carouseHangovers", hangoverOutcome)

        return true, "carouse_resolved", detail
    end

    function controller:getCarouseOptions(actor, opts)
        opts = opts or {}
        opts.actor = actor or opts.actor
        opts.gmDeck = opts.gmDeck or self.gmDeck
        opts.playerDeck = opts.playerDeck or self.playerDeck
        return M.getCarouseOptions(opts)
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
        if location ~= inventory.LOCATIONS.PACK then
            return false, "components_pack_only"
        end
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

    function controller:getPrepareComponentOptions(actor)
        return M.getPrepareComponentOptions({ actor = actor })
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

        local xpAmount, xpError = requestedTrainingXP(request)
        if not xpAmount then
            return false, xpError
        end
        local costPerXP = M.TRAINING_COST_PER_XP
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

    function controller:getCityTrainingOptions(actor, opts)
        opts = opts or {}
        opts.actor = actor
        return M.getCityTrainingOptions(opts)
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
        if request.reasonable == false or request.approved == false then
            return false, "Support project not approved"
        end

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
            local complexity, complexityError = normalizeSupportComplexity(request)
            if not complexity then
                return false, complexityError
            end
            project = {
                id = projectId,
                name = request.name or request.title or projectId,
                complexity = complexity,
                progress = tonumber(request.progress or request.stepsCompleted) or 0,
                contributions = {},
                completionEffects = request.completionEffects or request.completion or request.effects,
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
        local contributionImpact = M.classifySupportContributionImpact(contribution)
        local contributionRecord = {
            actor = actor,
            actorId = actorId(actor),
            gold = contribution,
            impact = contributionImpact,
            impactId = contributionImpact.id,
            impactLabel = contributionImpact.label,
            description = request.description or request.method,
        }
        project.contributions[#project.contributions + 1] = contributionRecord
        local completionDetail = nil
        if project.progress >= (project.complexity or 1) then
            project.complete = true
            completionDetail = applySupportCompletionEffects(self, project, actor, request)
        end

        return true, "project_supported", {
            actor = actor,
            action = M.ACTIONS.SUPPORT,
            project = project,
            projectId = project.id,
            contribution = contribution,
            contributionImpact = contributionImpact,
            contributionRecord = contributionRecord,
            progress = project.progress,
            complexity = project.complexity,
            complete = project.complete,
            completionDetail = completionDetail,
            result = "project_supported",
        }
    end

    function controller:getSupportContributionOptions(actor, opts)
        opts = opts or {}
        opts.actor = actor
        return M.getSupportContributionOptions(opts)
    end

    function controller:getSupportProjectOptions(actor, opts)
        opts = opts or {}
        opts.actor = actor
        opts.projects = opts.projects or self.projects
        return M.getSupportProjectOptions(opts)
    end

    function controller:resolveResearch(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.research or actionData
        local topic = request.topic or request.subject or request.subjectName or request.question or request.subjectId or
            request.loreSubjectId
        if not topic or tostring(topic) == "" then
            return false, "Research topic required"
        end

        local cost = M.RESEARCH_COST
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

        local answers, pendingQuestions, overflowQuestions, remainingQuestions =
            resolveResearchQuestionRequests(self, request, questions)

        local detail = {
            actor = actor,
            action = M.ACTIONS.RESEARCH,
            topic = topic,
            cost = cost,
            card = card,
            testResult = testResult,
            questions = questions,
            answers = answers,
            pendingQuestions = pendingQuestions,
            overflowQuestions = overflowQuestions,
            remainingQuestions = remainingQuestions,
            result = "research_complete",
        }
        actor.lastCityResearch = detail
        self.researchLog[#self.researchLog + 1] = detail

        return true, "research_complete", detail
    end

    function controller:getResearchQuestionOptions(actor, opts)
        opts = opts or {}
        opts.actor = actor
        opts.bidLoreEngine = opts.bidLoreEngine or self.bidLoreEngine
        return M.getResearchQuestionOptions(opts)
    end

    function controller:summarizeResearchResult(detail)
        return M.summarizeResearchResult(detail)
    end

    function controller:getMenagerieReagentPurchaseOptions(actor, opts)
        opts = opts or {}
        opts.actor = actor or opts.actor
        opts.menagerieStock = opts.menagerieStock or self.menagerieStock
        return M.getMenagerieReagentPurchaseOptions(opts)
    end

    function controller:getReagentSaleOptions(actor, opts)
        opts = opts or {}
        opts.actor = actor or opts.actor
        return M.getReagentSaleOptions(opts)
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

        local costPerItem = tonumber(config.costPerItem) or 0
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
        local cost = M.VISIT_GRAVE_COST
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

        local cost = M.MAKEOVER_COST
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

    function controller:resolveChangeMotif(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.motifChange or actionData
        if request.approved ~= true and request.gmApproved ~= true and request.tableApproved ~= true and
            request.requireApproval ~= false then
            return false, "Motif change requires GM approval"
        end
        if type(actor and actor.motifs) ~= "table" then
            return false, "Motif required"
        end

        local index = math.max(1, math.floor(tonumber(request.index or request.motifIndex) or 1))
        local oldMotif = actor.motifs[index]
        if not oldMotif then
            return false, "Motif required"
        end

        local replacement = request.newDescriptor or request.replacementDescriptor or request.descriptor
        local newMotif = request.newMotif or request.rewrittenMotif or request.motif
        if not newMotif then
            if not replacement or tostring(replacement) == "" then
                return false, "Replacement motif required"
            end
            local oldInfo = motif_catalog.parseMotif(oldMotif)
            if not oldInfo or not oldInfo.profession then
                return false, "Motif requires a profession"
            end
            local profession = tostring(oldInfo.profession):gsub("_", " ")
            profession = profession:gsub("(%a)([%w']*)", function(first, rest)
                return first:upper() .. rest:lower()
            end)
            newMotif = tostring(replacement) .. " " .. profession
        end

        local parsed, parseReason = motif_catalog.parseMotif(newMotif)
        if not parsed then
            return false, parseReason
        end
        if request.requireStructuredMotif == true and not parsed.structured then
            return false, "Motifs require a descriptor and profession"
        end
        if request.strictRulebookMotif == true and not parsed.sampleMotif then
            return false, "Motif must use a rulebook descriptor and profession"
        end

        actor.motifs[index] = parsed.text
        actor.motifInfo = motif_catalog.describeMotifs(actor.motifs)
        local record = {
            actor = actor,
            actorId = actorId(actor),
            action = M.ACTIONS.CHANGE_MOTIF,
            index = index,
            oldMotif = oldMotif,
            newMotif = parsed.text,
            motifInfo = actor.motifInfo and actor.motifInfo[index] or parsed,
            reason = request.reason or request.cause,
            approved = true,
        }
        appendActorRecord(actor, "motifChanges", record)
        self.motifChanges[#self.motifChanges + 1] = record

        return true, "motif_changed", {
            actor = actor,
            action = M.ACTIONS.CHANGE_MOTIF,
            index = index,
            oldMotif = oldMotif,
            newMotif = parsed.text,
            motifInfo = record.motifInfo,
            record = record,
            result = "motif_changed",
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

        local cost = tonumber(config.cost) or 0
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

        local cost = M.PILLOW_TALK_COST
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
            local syllableError = nil
            syllables, syllableError = resolveSyllables({
                syllables = request.syllables or request.syllableCount,
                description = description,
                name = description,
            })
            if not syllables then
                return false, syllableError
            end
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
        local syllables, syllableError = resolveSyllables(request)
        if not syllables then
            return false, syllableError
        end
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

        local cost = M.PLAY_OUTING_COST
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
        local cost = M.COURT_OF_WANDS_DUES
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
            local cost = config and tonumber(config.cost) or tonumber(entry.cost or entry.costGold or entry.price)
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
                        afflictionName = entry.afflictionName or (config and config.name) or name,
                        maxStage = entry.maxStage or (config and config.maxStage),
                        stageCosts = shallowClone(entry.stageCosts or (config and config.stageCosts)),
                        stageRecovery = shallowClone(entry.stageRecovery or (config and config.stageRecovery)),
                        stageEffects = shallowClone(entry.stageEffects or (config and config.stageEffects)),
                        quitCharges = entry.quitCharges or (config and config.quitCharges),
                        recentlyTakenEffect = entry.recentlyTakenEffect or (config and config.recentlyTakenEffect),
                        reexposureClearsCuredStage = entry.reexposureClearsCuredStage or
                            (config and config.reexposureClearsCuredStage),
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

        local cost = M.BLOOD_FEAST_COST
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
        local availableSources = request.availableSources or request.sources or { "minor_deck_top", "minor_discard_top" }
        local communion = {
            source = "street_of_heretics",
            service = request.service or request.faith or request.religion or "important religious service",
            expires = "next_expedition",
            uses = 1,
            challengeDrawChoice = true,
            sources = availableSources,
            availableSources = availableSources,
            drawSources = request.drawSources or request.selectedSources,
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

        local costPerTile = M.SPELL_RESEARCH_COST_PER_TILE
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
        local cost = M.SWORDWHORES_DUES
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
        local costPerStage = M.LEECHING_COST_PER_STAGE
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
        local cost = M.DOOMSAYING_COST
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

        local cost = M.SEEK_TRUTH_COST
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
        local cost = M.BEGGARS_GUILD_DUES
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

    local function findCityAnimalCompanion(actor, companionId)
        if not actor then
            return nil
        end

        local function matches(companion, key)
            if type(companion) ~= "table" then
                return false
            end
            if not companionId then
                return true
            end
            return companion.id == companionId or companion.name == companionId or key == companionId
        end

        if matches(actor.companion, "companion") then
            return actor.companion
        end

        for _, collection in ipairs({ actor.animalCompanions or false, actor.companions or false }) do
            if type(collection) == "table" then
                for key, companion in pairs(collection) do
                    if matches(companion, key) then
                        return companion
                    end
                end
            end
        end

        return nil
    end

    local function companionKnowsCommand(commandList, command)
        local wanted = animal_companions.normalizeCommandName(command)
        for key, known in pairs(commandList or {}) do
            if animal_companions.normalizeCommandName(animal_companions.getCommandEntryName(known, key)) == wanted then
                return true
            end
        end
        return false
    end

    function controller:resolveTrainAnimalCompanion(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.training or actionData
        local companion = request.companion or request.target or
            findCityAnimalCompanion(actor, request.companionId or request.companion_id or request.targetId)
        if not companion then
            return false, "Choose an animal companion"
        end

        local conditions = companion.conditions or {}
        if companion.abandoned or conditions.abandoned then
            return false, "Companion has abandoned the guild"
        end
        if conditions.dead or companion.dead then
            return false, "Companion is dead"
        end

        local command = request.commandName or request.command or request.knownCommand
        if not command or tostring(command) == "" then
            return false, "Choose a command to teach"
        end

        companion.knownCommands = companion.knownCommands or companion.commands or {}
        companion.commands = companion.knownCommands

        local commandDisplay = animal_companions.getCommandDisplayName(command)
        local commandKey = animal_companions.normalizeCommandName(command)
        if companionKnowsCommand(companion.knownCommands, commandKey) then
            return false, "Companion already knows command"
        end

        local replacement = request.replaceCommand or request.replace_command
        local commandLimit = animal_companions.getCommandLimit(companion)
        local trained = "taught"
        local replacementIndex = nil
        if #companion.knownCommands >= commandLimit then
            if not replacement then
                if commandLimit == 5 then
                    return false, "Familiar already knows five commands"
                end
                return false, "Companion already knows three commands"
            end

            for index, known in ipairs(companion.knownCommands) do
                if animal_companions.normalizeCommandName(animal_companions.getCommandEntryName(known, index)) ==
                   animal_companions.normalizeCommandName(replacement) then
                    replacementIndex = index
                    trained = "retrained"
                    break
                end
            end
            if not replacementIndex then
                return false, "Replacement command not known"
            end
        end

        local cost = M.ANIMAL_COMPANION_TRAINING_COST
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end
        if cost > 0 and not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        if replacementIndex then
            companion.knownCommands[replacementIndex] = commandDisplay
        else
            companion.knownCommands[#companion.knownCommands + 1] = commandDisplay
        end

        local training = {
            companion = companion,
            command = commandDisplay,
            replacedCommand = replacement,
            cost = cost,
            result = trained,
            source = "hippodrome_of_amet",
        }
        appendActorRecord(actor, "animalCompanionTraining", training)

        return true, "animal_companion_trained", {
            actor = actor,
            action = M.ACTIONS.TRAIN_ANIMAL_COMPANION,
            companion = companion,
            command = commandDisplay,
            replacedCommand = replacement,
            cost = cost,
            training = training,
            result = "animal_companion_trained",
        }
    end

    function controller:resolvePurchaseAnimalCompanion(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.purchase or actionData
        local hasExplicitCompanionSpec = type(request.companion) == "table" or type(request.animal) == "table"
        local companionSpec = type(request.companion) == "table" and request.companion or
            (type(request.animal) == "table" and request.animal or request)
        local templateId = request.templateId or request.companionTemplateId or request.animalTemplateId or
            companionSpec.templateId or companionSpec.companionTemplateId
        local template = nil
        if templateId then
            template = animal_companions.getTemplate(templateId)
        end
        if not template then
            template, templateId = animal_companions.getTemplate(companionSpec.species or
                companionSpec.animalType or companionSpec.kind)
        end
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

        local cost = math.floor(tonumber((template and template.rarityCost) or request.cost or request.costGold or
            request.price or request.rarityCost) or 0)
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
        local index = #actor.animalCompanions + 1
        local companionOverrides = hasExplicitCompanionSpec and shallowClone(companionSpec) or {
            name = request.name or request.companionName,
            species = request.species,
            animalType = request.animalType,
            kind = request.kind,
        }
        local companion = animal_companions.createCompanion(templateId, companionOverrides)
        local species = companion.species or companion.animalType or companion.kind or "exotic animal"
        local name = companion.name or request.companionName or ("Hippodrome " .. tostring(species))
        companion.id = companion.id or request.companionId or string.format("%s_companion_%02d_%s",
            slugify(actorId(actor)), index, slugify(name))
        companion.name = name
        companion.species = species
        companion.animalType = companion.animalType or species
        companion.type = companion.type or "animal_companion"
        companion.conditions = companion.conditions or {}
        companion.knownCommands = { animal_companions.getCommandDisplayName(command) }
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

    function controller:getGoblinHordeOptions(actor, opts)
        if type(actor) == "table" and opts == nil and
           (actor.actor or actor.request or actor.horde or actor.xpSpent or actor.amount) then
            opts = actor
            actor = opts.actor
        end
        opts = opts or {}
        opts.actor = actor or opts.actor
        opts.actionsCompleted = opts.actionsCompleted or self.actionsCompleted
        local options = M.getGoblinHordeOptions(opts)
        local allowed, reason = self:checkCityActionRestrictions(M.ACTIONS.ASSEMBLE_GOBLIN_HORDE)
        options.cityActionAllowed = allowed == true
        options.cityActionUnavailableReason = allowed ~= true and reason or nil
        if allowed ~= true and not options.disabled then
            options.disabled = true
            options.unavailableReason = reason
        end
        return options
    end

    function controller:getJarlGoblinHordeOptions(actor, opts)
        return self:getGoblinHordeOptions(actor, opts)
    end

    function controller:resolveAssembleGoblinHorde(actor, actionData)
        actionData = actionData or {}
        local request = actionData.request or actionData.horde or actionData
        if not hasUsableTalent(actor, "jarl") then
            return false, "Requires Jarl talent"
        end

        local xpSpend = tonumber(request.xp or request.xpSpent or request.amount) or 0
        if xpSpend < 0 then
            return false, "XP spend cannot be negative"
        end
        if xpSpend ~= math.floor(xpSpend) then
            return false, "Jarl XP must be a whole number"
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

        local interestRate = M.LOAN_INTEREST_RATE
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

        local cost = M.SEND_LETTER_COST
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

        local cost = M.STUDY_LANGUAGE_COST
        if currency.getGold(actor) < cost then
            return false, "Not enough gold"
        end
        if cost > 0 and not currency.spendGold(actor, cost) then
            return false, "Not enough gold"
        end

        actor.languages = actor.languages or {}
        actor.languages[#actor.languages + 1] = language
        actor.languageInfo = actor.languageInfo or {}
        actor.languageInfo[language] = language_catalog.getLanguage(language)

        return true, "language_studied", {
            actor = actor,
            action = M.ACTIONS.STUDY_LANGUAGE,
            language = language,
            languageInfo = actor.languageInfo[language],
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
        elseif actionId == M.ACTIONS.CHANGE_MOTIF then
            ok, result, detail = self:resolveChangeMotif(actor, actionData)
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
        elseif actionId == M.ACTIONS.RETIRE_ADVENTURER then
            ok, result, detail = self:resolveRetireAdventurer(actor, actionData)
        elseif actionId == M.ACTIONS.DECLARE_NEW_QUEST then
            ok, result, detail = self:resolveDeclareNewQuest(actor, actionData)
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
                menagerieStock = self.menagerieStock,
            })
        elseif actionId == M.ACTIONS.PURCHASE_AMULETS then
            ok, result, detail = self:resolvePurchaseAmulets(actor, actionData)
        elseif actionId == M.ACTIONS.PURCHASE_ANIMAL_COMPANION then
            ok, result, detail = self:resolvePurchaseAnimalCompanion(actor, actionData)
        elseif actionId == M.ACTIONS.TRAIN_ANIMAL_COMPANION then
            ok, result, detail = self:resolveTrainAnimalCompanion(actor, actionData)
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
        local blockedDistricts = self.cityEventEffects and self.cityEventEffects.blockedDistrictIds
        local blockedActions = self.cityEventEffects and self.cityEventEffects.blockedDistrictActions
        if districtEntry.blockedByCityEvent or
           (blockedDistricts and blockedDistricts[districtEntry.districtId]) or
           (blockedActions and blockedActions[requestedActionId]) then
            return false, "District City Action blocked by City Event"
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
