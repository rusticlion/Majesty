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
local fate_resolver = require('logic.resolver')

local M = {}

M.TAX_RATE = 0.5
M.TRAINING_COST_PER_XP = 50
M.BUILD_COST_PER_SYLLABLE = 50
M.FUNERAL_COST_PER_XP = 100
M.MAX_FAME = 5
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
    COMMISSION_CRAFT = "commission_craft",
    HOLD_FUNERAL = "hold_funeral",
    PREPARE_COMPONENTS = "prepare_components",
    PRAY_AT_MYTHRAEUM = "pray_at_mythraeum",
    TRAIN = "train",
    SUPPORT = "support",
    RESEARCH = "research",
    MENAGERIE_REAGENT_PURCHASE = "menagerie_reagent_purchase",
    HARVEST_ALCHEMICAL_REAGENTS = "harvest_alchemical_reagents",
    BEG_FOR_SCRAPS = "beg_for_scraps",
    COMMISSION_GARGOYLE = "commission_gargoyle",
    COMMISSION_PUPPET = "commission_puppet",
    FIT_PROSTHETICS = "fit_prosthetics",
    MAKEOVER = "makeover",
    PILLOW_TALK = "pillow_talk",
    PURCHASE_AMULETS = "purchase_amulets",
    PURCHASE_FATE_HONEY = "purchase_fate_honey",
    PURCHASE_FIREWORKS = "purchase_fireworks",
    REST_AND_RECUPERATE = "rest_and_recuperate",
    SEND_LETTER = "send_letter",
    SELL_REAGENT = "sell_reagent",
    SELL_REAGENTS = "sell_reagents",
    STUDY_LANGUAGE = "study_language",
    UNDERGO_LEECHING = "undergo_leeching",
    VISIT_GRAVE = "visit_grave",
}

M.DISTRICT_ACTION_ALIASES = {
    beg_for_scraps = M.ACTIONS.BEG_FOR_SCRAPS,
    commission_gargoyle = M.ACTIONS.COMMISSION_GARGOYLE,
    commission_puppet = M.ACTIONS.COMMISSION_PUPPET,
    fit_prosthetics = M.ACTIONS.FIT_PROSTHETICS,
    harvest_alchemical_reagents = M.ACTIONS.MENAGERIE_REAGENT_PURCHASE,
    makeover = M.ACTIONS.MAKEOVER,
    pillow_talk = M.ACTIONS.PILLOW_TALK,
    purchase_amulets = M.ACTIONS.PURCHASE_AMULETS,
    purchase_fate_honey = M.ACTIONS.PURCHASE_FATE_HONEY,
    purchase_fireworks = M.ACTIONS.PURCHASE_FIREWORKS,
    rest_and_recuperate = M.ACTIONS.REST_AND_RECUPERATE,
    send_letter = M.ACTIONS.SEND_LETTER,
    sell_reagents = M.ACTIONS.SELL_REAGENT,
    study_language = M.ACTIONS.STUDY_LANGUAGE,
    undergo_leeching = M.ACTIONS.UNDERGO_LEECHING,
    visit_grave = M.ACTIONS.VISIT_GRAVE,
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
    menagerie_reagent_purchase = M.ACTIONS.MENAGERIE_REAGENT_PURCHASE,
    harvest_alchemical_reagents = M.ACTIONS.MENAGERIE_REAGENT_PURCHASE,
    harvest_reagents_menagerie = M.ACTIONS.MENAGERIE_REAGENT_PURCHASE,
    beg_for_scraps = M.ACTIONS.BEG_FOR_SCRAPS,
    commission_gargoyle = M.ACTIONS.COMMISSION_GARGOYLE,
    commission_puppet = M.ACTIONS.COMMISSION_PUPPET,
    fit_prosthetics = M.ACTIONS.FIT_PROSTHETICS,
    makeover = M.ACTIONS.MAKEOVER,
    pillow_talk = M.ACTIONS.PILLOW_TALK,
    purchase_amulets = M.ACTIONS.PURCHASE_AMULETS,
    buy_amulets = M.ACTIONS.PURCHASE_AMULETS,
    purchase_fate_honey = M.ACTIONS.PURCHASE_FATE_HONEY,
    buy_fate_honey = M.ACTIONS.PURCHASE_FATE_HONEY,
    purchase_fireworks = M.ACTIONS.PURCHASE_FIREWORKS,
    buy_fireworks = M.ACTIONS.PURCHASE_FIREWORKS,
    rest_and_recuperate = M.ACTIONS.REST_AND_RECUPERATE,
    hospital_rest = M.ACTIONS.REST_AND_RECUPERATE,
    send_letter = M.ACTIONS.SEND_LETTER,
    sell_reagent = M.ACTIONS.SELL_REAGENT,
    sell_reagents = M.ACTIONS.SELL_REAGENT,
    study_language = M.ACTIONS.STUDY_LANGUAGE,
    undergo_leeching = M.ACTIONS.UNDERGO_LEECHING,
    leeching = M.ACTIONS.UNDERGO_LEECHING,
    visit_grave = M.ACTIONS.VISIT_GRAVE,
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
    return tostring(talentId or ""):lower():gsub("%s+", "_"):gsub("[’']", "")
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
        talent.mentored = true
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
            talent = talent,
            result = "training_complete",
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
        if actionId == M.ACTIONS.BANKING then
            ok, result, detail = self:resolveBanking(actor, actionData)
        elseif actionId == M.ACTIONS.BEG_FOR_SCRAPS then
            ok, result, detail = self:resolveBegForScraps(actor, actionData)
        elseif actionId == M.ACTIONS.BEG_AND_BUSK then
            ok, result, detail = self:resolveBegAndBusk(actor, actionData)
        elseif actionId == M.ACTIONS.BUILD then
            ok, result, detail = self:resolveBuild(actor, actionData)
        elseif actionId == M.ACTIONS.CAMP_ACTION then
            ok, result, detail = self:resolveCampAction(actor, actionData)
        elseif actionId == M.ACTIONS.CAROUSE then
            ok, result, detail = self:resolveCarouse(actor, actionData)
        elseif actionId == M.ACTIONS.COMMISSION_GARGOYLE then
            ok, result, detail = self:resolveCommissionGargoyle(actor, actionData)
        elseif actionId == M.ACTIONS.COMMISSION_PUPPET then
            ok, result, detail = self:resolveCommissionPuppet(actor, actionData)
        elseif actionId == M.ACTIONS.COMMISSION_CRAFT then
            ok, result, detail = self:resolveCommissionCraft(actor, actionData)
        elseif actionId == M.ACTIONS.FIT_PROSTHETICS then
            ok, result, detail = self:resolveFitProsthetics(actor, actionData)
        elseif actionId == M.ACTIONS.HOLD_FUNERAL then
            ok, result, detail = self:resolveHoldFuneral(actor, actionData)
        elseif actionId == M.ACTIONS.MAKEOVER then
            ok, result, detail = self:resolveMakeover(actor, actionData)
        elseif actionId == M.ACTIONS.PILLOW_TALK then
            ok, result, detail = self:resolvePillowTalk(actor, actionData)
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
        elseif actionId == M.ACTIONS.PURCHASE_FATE_HONEY then
            ok, result, detail = self:resolvePurchaseFateHoney(actor, actionData)
        elseif actionId == M.ACTIONS.PURCHASE_FIREWORKS then
            ok, result, detail = self:resolvePurchaseFireworks(actor, actionData)
        elseif actionId == M.ACTIONS.REST_AND_RECUPERATE then
            ok, result, detail = self:resolveRestAndRecuperate(actor, actionData)
        elseif actionId == M.ACTIONS.SEND_LETTER then
            ok, result, detail = self:resolveSendLetter(actor, actionData)
        elseif actionId == M.ACTIONS.SELL_REAGENT then
            ok, result, detail = alchemy.resolveReagentSale(actor, actionData, {
                eventBus = self.eventBus,
                price = actionData.price,
                value = actionData.value,
                gold = actionData.gold,
            })
        elseif actionId == M.ACTIONS.STUDY_LANGUAGE then
            ok, result, detail = self:resolveStudyLanguage(actor, actionData)
        elseif actionId == M.ACTIONS.UNDERGO_LEECHING then
            ok, result, detail = self:resolveUndergoLeeching(actor, actionData)
        elseif actionId == M.ACTIONS.VISIT_GRAVE then
            ok, result, detail = self:resolveVisitGrave(actor, actionData)
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
