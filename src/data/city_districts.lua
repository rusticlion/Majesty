-- city_districts.lua
-- Appendix D City creation procedure and district special-action registry.

local constants = require('constants')

local M = {}

local SUITS = constants.SUITS
local FACE_VALUES = constants.FACE_VALUES

M.rulebookSuitNames = {
    [SUITS.SWORDS] = "Swords",
    [SUITS.PENTACLES] = "Disks",
    [SUITS.CUPS] = "Cups",
    [SUITS.WANDS] = "Batons",
}

M.centralPowers = {
    [SUITS.SWORDS] = {
        id = "griffin_king",
        name = "The Griffin King",
        seat = "Three-Faced Castle",
        summary = "The Griffin King and his knights rule from the air currents above the City.",
    },
    [SUITS.PENTACLES] = {
        id = "tyrant_emperor",
        name = "The Tyrant Emperor",
        seat = "Iron Palace",
        taxCollector = "All-Watch",
        summary = "The Tyrant Emperor rules through crushing taxation and the All-Watch.",
    },
    [SUITS.CUPS] = {
        id = "cult_of_mythrys",
        name = "Cult of Mythrys",
        ruler = "Secret Pope",
        seat = "High Mithraeum",
        enforcement = "Inquisition",
        summary = "The Secret Pope's bulls become law, enforced by the Inquisition.",
    },
    [SUITS.WANDS] = {
        id = "cult_of_the_god_king",
        name = "Cult of the God-King",
        ruler = "Crow-Headed Queen",
        seat = "Temple of the God-Kings",
        summary = "The Crow-Headed Queen rules by sorcery and will be deified at death.",
    },
}

M.gates = {
    { id = "gods_gate", value = 1, name = "The God's Gate" },
    { id = "grain_gate", value = 2, name = "The Grain Gate" },
    { id = "muddy_door", value = 3, name = "The Muddy Door" },
    { id = "bloody_gate", value = 4, name = "The Bloody Gate" },
    { id = "stolen_gate", value = 5, name = "The Stolen Gate" },
    { id = "needles_eye", value = 6, name = "The Needle's Eye" },
    { id = "victory_gate", value = 7, name = "The Victory Gate" },
    { id = "bone_gate", value = 8, name = "The Bone Gate" },
    { id = "gate_of_sighs", value = 9, name = "The Gate of Sighs" },
    { id = "gate_of_storms", value = 10, name = "The Gate of Storms" },
    { id = "onyx_gate", value = 11, name = "The Onyx Gate" },
    { id = "ammonite_gate", value = 12, name = "The Ammonite Gate" },
    { id = "suns_door", value = 13, name = "The Sun's Door" },
    { id = "cursed_gate", value = 14, name = "The Cursed Gate" },
}

M.layout = {
    centralPowerCards = 1,
    coreDistrictCards = 4,
    corePositions = { "north", "south", "east", "west" },
    minUniqueDistricts = 4,
    maxUniqueDistricts = 20,
    faceCardCentralPowerUsesDistrict = true,
}

M.sprawlCardsByCoreSuit = {
    [SUITS.SWORDS] = 0,
    [SUITS.PENTACLES] = 1,
    [SUITS.CUPS] = 2,
    [SUITS.WANDS] = 3,
}

M.suitDistrictProfiles = {
    [SUITS.SWORDS] = {
        id = "military_complex",
        socialOrder = "martial powers",
        summary = "Swords districts support or center on the martial powers of the City.",
    },
    [SUITS.PENTACLES] = {
        id = "lower_classes_illicit_systems",
        socialOrder = "lower classes and illicit systems",
        commonLanguage = "cant",
        summary = "Pentacles districts represent the lower classes and systems that reinforce or profit from illicit activity.",
    },
    [SUITS.CUPS] = {
        id = "religious_and_funded_institutions",
        socialOrder = "religious elements and funded institutions",
        commonLanguage = "vetus",
        summary = "Cups districts represent religious elements and institutions they fund: banking, academia, and hospitals.",
    },
    [SUITS.WANDS] = {
        id = "queer_mystic_sorcerous",
        socialOrder = "drugs, mystics, astrologers, and sorcerers",
        summary = "Wands districts represent queer things: drugs, mystics, astrologers, and sorcerers.",
    },
}

M.valueProfiles = {
    numbered = {
        values = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 },
        power = "middling",
        wealth = "poor",
    },
    face = {
        values = { FACE_VALUES.PAGE, FACE_VALUES.KNIGHT, FACE_VALUES.QUEEN, FACE_VALUES.KING },
        power = "powerful institution",
        wealth = "rich",
        commonLanguage = "chivalric",
    },
}

M.constants = {
    grey = {
        id = "grey",
        name = "The Grey",
        kind = "constant",
        specialCityActions = {},
        summary = "The Black and White tributaries join into the Grey, the river artery of the City.",
    },
    ossuary = {
        id = "ossuary",
        name = "The Ossuary",
        kind = "constant",
        specialCityActions = {},
        summary = "A bone-lined catacomb and membrane between the Underworld and the lands of the living.",
    },
    omphalic_market = {
        id = "omphalic_market",
        name = "The Omphalic Market",
        kind = "constant",
        upkeepAssumed = true,
        specialCityActions = {},
        summary = "The great bazaar surrounds the Umbilical Stone and is assumed during City Phase Upkeep.",
    },
}

local function action(id, name, summary, mechanics)
    return {
        id = id,
        name = name,
        summary = summary,
        mechanics = mechanics or {},
    }
end

local function district(suit, value, id, name, specialCityActions, opts)
    opts = opts or {}
    local entry = {
        id = id,
        name = name,
        card = {
            suit = suit,
            value = value,
        },
        specialCityActions = specialCityActions or {},
    }

    for key, valueOpt in pairs(opts) do
        entry[key] = valueOpt
    end

    return entry
end

M.districts = {
    [SUITS.SWORDS] = {
        [1] = district(SUITS.SWORDS, 1, "mortuary_of_the_god_kings", "The Mortuary of the God-Kings", {
            action("pale_prophecies", "Pale prophecies", "Spend the night in the Mortuary to hear the old deified kings whisper sad prophecies.", {
                spendNight = true,
                information = "prophecy",
            }),
        }),
        [2] = district(SUITS.SWORDS, 2, "temple_of_strength", "The Temple of Strength", {
            action("get_autographs", "Get autographs", "Secure autographs from one of the City's celebrated athletes."),
            action("wrestle_hereclus", "Wrestle Hereclus", "Try to defeat Hereclus the Strong for a standing 500g prize.", {
                prizeGold = 500,
                impossibleWhileFeetOnSolidGround = true,
            }),
        }),
        [3] = district(SUITS.SWORDS, 3, "hangmans_hill", "Hangman's Hill", {
            action("explore_hangmans_hill", "Explore Hangman's Hill", "Brave the haunted hill at night and see if the dead hold anything of worth.", {
                nighttime = true,
            }),
        }),
        [4] = district(SUITS.SWORDS, 4, "iron_street", "Iron Street", {
            action("duel", "Duel", "Argue sword theory, accept a duel, and win the opponent's sword if victorious.", {
                reward = "opponents_sword",
            }),
        }, {
            districtRules = {
                noMagic = true,
            },
        }),
        [5] = district(SUITS.SWORDS, 5, "vinegar_district", "The Vinegar District", {
            action("loosen_lips", "Loosen lips", "Spend gold on drinks to ask a normally guarded GM character one direct question.", {
                test = "fate",
                bonusPerGold = 20,
                maxBonus = 5,
                success = "honest_answer",
            }),
        }),
        [6] = district(SUITS.SWORDS, 6, "bridge_of_mourning", "The Bridge of Mourning", {
            action("seek_the_cursed_king", "Seek the Cursed King", "Search for the cursed king and the secret of his blasphemous immortality.", {
                test = "wands",
            }),
        }),
        [7] = district(SUITS.SWORDS, 7, "shrine_of_teeth", "The Shrine of Teeth", {
            action("fit_prosthetics", "Fit prosthetics", "Acquire a crude prosthetic for a lost limb without gold cost.", {
                costGold = 0,
                requiresLostLimb = true,
            }),
        }),
        [8] = district(SUITS.SWORDS, 8, "bellringers_district", "Bellringer's District", {
            action("keep_an_ear_to_the_ground", "Keep an ear to the ground", "Hear one rumor from the GM's City Events table.", {
                revealsCityEventRumor = true,
            }),
            action("spread_rumors", "Spread rumors", "Spend gold to spread a rumor that less discerning citizens count as credible.", {
                test = "fate",
                bonusPerGold = 20,
                maxBonus = 5,
            }),
        }),
        [9] = district(SUITS.SWORDS, 9, "grey_docks", "The Grey Docks", {
            action("get_tattoos", "Get tattoos", "Receive a cool tattoo from the river tattoo subculture.", {
                cosmetic = true,
            }),
        }),
        [10] = district(SUITS.SWORDS, 10, "silent_quarter", "The Silent Quarter", {
            action("visit_grave", "Visit grave", "Pay grave gifts at a comrade's bones to cure one Curse effect with GM permission.", {
                costGold = 100,
                requiresFuneral = true,
                cures = "curse_effect",
                gmPermission = true,
            }),
        }),
        [FACE_VALUES.PAGE] = district(SUITS.SWORDS, FACE_VALUES.PAGE, "court_martial", "The Court Martial", {
            action("trial_by_combat", "Trial by combat", "Demand a trial by combat when accused of breaking the City's peace.", {
                createsChallenge = true,
                languageHelps = "chivalric",
            }),
        }),
        [FACE_VALUES.KNIGHT] = district(SUITS.SWORDS, FACE_VALUES.KNIGHT, "temple_militant", "The Temple Militant", {
            action("seal_away", "Seal away", "Convince the templars to imprison an unholy Underworld abomination.", {
                requiresConvincingTemplars = true,
            }),
        }),
        [FACE_VALUES.QUEEN] = district(SUITS.SWORDS, FACE_VALUES.QUEEN, "brothel_of_battle", "The Brothel of Battle", {
            action("join_the_swordwhores", "Join the Swordwhores", "Pay dues to join the mercenary company and gain cheaper iron and steel armor access.", {
                costGold = 100,
                membership = "swordwhores",
                armorUpkeepTier = "impoverished",
            }),
        }),
        [FACE_VALUES.KING] = district(SUITS.SWORDS, FACE_VALUES.KING, "court_of_swords", "The Court of Swords", {
            action("fight", "Fight!", "Bet on yourself in the fighting pits and resolve the bout with blackjack.", {
                minWoundsOnBust = 1,
                winProfitPercent = 25,
                loseCondition = "stressed_next_crawl",
            }),
        }),
    },

    [SUITS.PENTACLES] = {
        [1] = district(SUITS.PENTACLES, 1, "licehouse", "Licehouse", {
            action("dispose_of_bodies", "Dispose of bodies", "Have pig keepers disappear body-shaped bundles of meat, no questions asked."),
        }),
        [2] = district(SUITS.PENTACLES, 2, "orphanarium", "Orphanarium", {
            action("adopt", "Adopt", "Adopt a ward who may serve as City support staff and possible inheritor.", {
                createsWard = true,
            }),
        }),
        [3] = district(SUITS.PENTACLES, 3, "the_gambol", "The Gambol", {
            action("lay_high", "Lay high", "Hide out above the City until an offended party wastes their hunt for you."),
        }, {
            specialPlacement = {
                drawAgain = true,
                relationToSecondDistrict = "above",
                note = "The Gambol is the top story; the second district is the bottom story.",
            },
        }),
        [4] = district(SUITS.PENTACLES, 4, "curio_curia", "The Curio Curia", {
            action("fence_goods", "Fence goods", "Fence possessions that would be unwise to sell through traditional channels.", {
                usesPriceProcedure = true,
            }),
        }),
        [5] = district(SUITS.PENTACLES, 5, "little_birds_district", "Little Birds' District", {
            action("send_letter", "Send letter", "Send a discreet letter anywhere in the Wide World.", {
                costGold = 10,
                failureChance = "1_in_14",
            }),
        }),
        [6] = district(SUITS.PENTACLES, 6, "lampwrights_street", "Lampwright's Street", {
            action("purchase_fireworks", "Purchase fireworks", "Buy fireworks that can create Blinding lights or Piercing Wounds during a Challenge.", {
                costGold = 25,
                costUnit = "per_rocket",
                misfireChancePercent = 25,
            }),
        }),
        [7] = district(SUITS.PENTACLES, 7, "cloaca_maxima", "The Cloaca Maxima", {
            action("mutation", "Mutation", "Gain a random mutation for hanging out in the sewer.", {
                randomMutation = true,
            }),
        }),
        [8] = district(SUITS.PENTACLES, 8, "mount_of_broken_amphorae", "The Mount of Broken Amphorae", {
            action("doodlebug", "Doodlebug", "Search the refuse for a legitimately lost Underworld item.", {
                recoveryChancePercent = 50,
                requiresLostItem = true,
            }),
        }),
        [9] = district(SUITS.PENTACLES, 9, "lichyard_market", "The Lichyard Market", {
            action("attend_miss_kinseys_dining_club", "Attend Miss Kinsey's Dining Club", "Share strange monster meat and ask one Underworld question.", {
                cost = "one_steak_from_strange_monster_or_beast",
                questionScope = "underworld",
            }),
        }),
        [10] = district(SUITS.PENTACLES, 10, "master_hugo_underhills_menagerie", "Master Hugo Underhill's Menagerie", {
            action("harvest_alchemical_reagents", "Harvest alchemical reagents", "Buy harvested monster reagents from the menagerie.", {
                costGold = 25,
                costUnit = "per_reagent",
            }),
        }),
        [FACE_VALUES.PAGE] = district(SUITS.PENTACLES, FACE_VALUES.PAGE, "the_colonies", "The Colonies", {
            action("commission_dwarven_mastercraft", "Commission dwarven mastercraft", "Commission superior dwarven work priced by syllable.", {
                costGold = 50,
                costUnit = "per_syllable",
                improvedCraft = true,
            }),
        }, {
            specialPlacement = {
                drawAgain = true,
                relationToSecondDistrict = "beneath",
                note = "The Colonies are beneath whichever district is drawn second.",
            },
        }),
        [FACE_VALUES.KNIGHT] = district(SUITS.PENTACLES, FACE_VALUES.KNIGHT, "whorestown", "Whorestown", {
            action("pillow_talk", "Pillow talk", "Spend gold to learn a City character's likes or dislikes as rumor.", {
                costGold = 10,
                reveals = "city_character_like_or_dislike",
            }),
        }),
        [FACE_VALUES.QUEEN] = district(SUITS.PENTACLES, FACE_VALUES.QUEEN, "street_of_beggars", "The Street of Beggars", {
            action("join_the_beggars_guild", "Join the Beggars Guild", "Pay dues to use the guild's secret Underworld entrance.", {
                costGold = 100,
                membership = "beggars_guild",
                bypassesCoinTax = true,
                portalCost = "one_item_of_the_guilds_choice",
            }),
        }),
        [FACE_VALUES.KING] = district(SUITS.PENTACLES, FACE_VALUES.KING, "court_of_coins", "The Court of Coins", {
            action("contract_assassination", "Contract assassination", "Pay the Court of Coins to kill a named target in the Wide World.", {
                minCostGold = 5000,
                maxCost = "dragons_egg",
                targetScope = "wide_world_only",
            }),
        }),
    },

    [SUITS.CUPS] = {
        [1] = district(SUITS.CUPS, 1, "thermae", "The Thermae", {
            action("makeover", "Makeover", "Rewrite your adventurer's appearance.", {
                costGold = 10,
                changesAppearance = true,
            }),
        }),
        [2] = district(SUITS.CUPS, 2, "perfume_district", "The Perfume District", {
            action("beg_for_scraps", "Beg for scraps", "Fill your pack with disgusting rations that also work as animal feed.", {
                requiresDestitute = true,
                grants = "disgusting_rations",
            }),
        }),
        [3] = district(SUITS.CUPS, 3, "stone", "Stone", {
            action("commission_gargoyle", "Commission gargoyle", "Commission a gargoyle of anything you want.", {
                costGold = 50,
            }),
        }),
        [4] = district(SUITS.CUPS, 4, "hippodrome_of_amet", "The Hippodrome of Amet", {
            action("purchase_animal_companion", "Purchase animal companion", "Buy an exotic animal that enters service knowing one command.", {
                minCostGold = 100,
                maxCostGold = 1000,
                commandsKnown = 1,
            }),
        }),
        [5] = district(SUITS.CUPS, 5, "rouge_road", "Rouge Road", {
            action("marriage_feast", "Marriage feast", "Spend Crawl gold on a wedding feast for XP.", {
                cost = "all_gold_from_last_crawl",
                selfXP = 2,
                attendeeXP = 1,
            }),
        }),
        [6] = district(SUITS.CUPS, 6, "madrasa_of_maiden_wisdom", "The Madrasa of Maiden Wisdom", {
            action("study_language", "Study language", "Study the grammar of one of the City's main languages.", {
                costGold = 200,
                grants = "one_language",
            }),
        }),
        [7] = district(SUITS.CUPS, 7, "plaza_of_the_stylites", "The Plaza of the Stylites", {
            action("doomsaying", "Doomsaying", "Donate to a stylite and draw a four-card prophecy that may later refill Resolve.", {
                costGold = 10,
                minorCardsDrawn = 4,
                futureReward = "refill_resolve",
            }),
        }),
        [8] = district(SUITS.CUPS, 8, "philosophers_forum", "The Philosophers' Forum", {
            action("seek_truth", "Seek truth", "Spend gold to test a hypothesis against a crowd of philosophers.", {
                costGold = 50,
                reveals = "hypothesis_veracity",
            }),
        }),
        [9] = district(SUITS.CUPS, 9, "shrine_of_the_fig_of_fate", "The Shrine of the Fig of Fate", {
            action("purchase_fate_honey", "Purchase fate honey", "Add fate honey jars to your pack; each can restore one lore bid during a Crawl.", {
                item = "fate_honey",
                itemSlots = 1,
                restores = "one_lore_bid",
            }),
        }),
        [10] = district(SUITS.CUPS, 10, "alchemists_hall", "Alchemists' Hall", {
            action("sell_reagents", "Sell reagents", "Sell hermetically preserved monster parts to alchemists.", {
                fallbackValue = "5g_x_total_hd",
            }),
        }),
        [FACE_VALUES.PAGE] = district(SUITS.CUPS, FACE_VALUES.PAGE, "hospital_of_st_berenthu", "The Hospital of St. Berenthu", {
            action("rest_and_recuperate", "Rest and recuperate", "Spend a City Action at the Hospital to heal all Wounds.", {
                requiresNotDestitute = true,
                heals = "all_wounds",
            }),
            action("undergo_leeching", "Undergo leeching", "Heal an affliction by paying per stage.", {
                costGold = 20,
                costUnit = "per_affliction_stage",
            }),
        }),
        [FACE_VALUES.KNIGHT] = district(SUITS.CUPS, FACE_VALUES.KNIGHT, "old_queens_library", "The Old Queen's Library", {
            action("copy_texts", "Copy texts", "Pay a scribe to copy a book on an available topic.", {
                minCostGold = 100,
                maxCostGold = 1400,
            }),
        }),
        [FACE_VALUES.QUEEN] = district(SUITS.CUPS, FACE_VALUES.QUEEN, "centrum_bank", "The Centrum Bank", {
            action("take_out_a_loan", "Take out a loan", "Borrow almost any amount at high interest.", {
                interestPercent = 30,
            }),
        }),
        [FACE_VALUES.KING] = district(SUITS.CUPS, FACE_VALUES.KING, "court_of_the_grail", "The Court of the Grail", {
            action("seek_initiation", "Seek initiation", "Join the Cult of Mythrys and advance by answering initiation riddles.", {
                initiationRanks = 21,
                grantsFavorOverLowerRanks = true,
            }),
        }),
    },

    [SUITS.WANDS] = {
        [1] = district(SUITS.WANDS, 1, "prestidigitators_theater", "Prestidigitators' Theater", {
            action("commission_puppet", "Commission puppet", "Commission a lifelike puppet of yourself or someone else.", {
                costGold = 10,
            }),
        }),
        [2] = district(SUITS.WANDS, 2, "newt_row", "Newt Row", {
            action("purchase_amulets", "Purchase amulets", "Buy amulets that each remove disfavor once.", {
                costGold = 10,
                removes = "disfavor",
                consumedOnUse = true,
            }),
        }),
        [3] = district(SUITS.WANDS, 3, "lotus_eaters_district", "The Lotus Eater's District", {
            action("buy_exotic_drugs", "Buy exotic drugs", "Purchase black honey, ghost lotus, or other GM-authored exotic drugs.", {
                prices = {
                    black_honey = 35,
                    ghost_lotus = 5,
                },
            }),
        }),
        [4] = district(SUITS.WANDS, 4, "kobalosgaard", "Kobalosgaard", {
            action("blood_feast", "Blood feast", "Bring gifts and a monster carcass to feast with the orcs and receive a nickname.", {
                costGold = 50,
                cost = "underworld_monster_carcass",
                grants = "orc_nickname",
            }),
        }),
        [5] = district(SUITS.WANDS, 5, "plaza_numina", "The Plaza Numina", {
            action("huff_fumes", "Huff fumes", "Use a GM-prepared Mad Lib to produce nonsense prophecy.", {
                produces = "mad_lib_prophecy",
            }),
        }),
        [6] = district(SUITS.WANDS, 6, "street_of_heretics", "The Street of Heretics", {
            action("strange_communions", "Strange communions", "Attend an important religious service to draw later Challenge cards from deck or discard.", {
                nextExpeditionChallengeDrawChoice = true,
            }),
        }),
        [7] = district(SUITS.WANDS, 7, "sidereal_house", "The Sidereal House", {
            action("as_above_so_below", "As above so below", "Draw the top three minor arcana cards and place them back in any order.", {
                minorCardsDrawn = 3,
                reorderDrawnCards = true,
            }),
        }),
        [8] = district(SUITS.WANDS, 8, "garden_of_ravenous_roses", "Garden of Ravenous Roses", {
            action("picnic", "Picnic", "Invite adventurers to share unknown backstory in the terrible garden.", {
                promptsBackstory = true,
            }),
        }),
        [9] = district(SUITS.WANDS, 9, "labyrinth", "The Labyrinth", {
            action("enter_the_underworld", "Enter the Underworld", "Begin the Crawl in a random Underworld location, different each time.", {
                startsCrawl = true,
                randomUnderworldLocation = true,
            }),
        }),
        [10] = district(SUITS.WANDS, 10, "starfall_pit", "The Starfall Pit", {
            action("visit_the_pit", "Visit the Pit", "Let the table alter or swap one thing on your adventurer sheet within normal bounds.", {
                altersCharacterSheet = true,
            }),
        }),
        [FACE_VALUES.PAGE] = district(SUITS.WANDS, FACE_VALUES.PAGE, "broken_smiles_district", "The Broken Smiles District", {
            action("the_plays_the_thing", "The play's the thing", "Take a companion to a play and gauge their opinion about its subject.", {
                costGold = 25,
                reveals = "companion_opinion",
            }),
        }),
        [FACE_VALUES.KNIGHT] = district(SUITS.WANDS, FACE_VALUES.KNIGHT, "temple_of_gods_wives", "The Temple of God's Wives", {
            action("exchange_gifts", "Exchange gifts", "Give a gift and Test Cups to receive either a funny item or a random antique.", {
                test = "cups",
                failureReward = "small_funny_item",
                successReward = "random_antique",
            }),
        }),
        [FACE_VALUES.QUEEN] = district(SUITS.WANDS, FACE_VALUES.QUEEN, "tower_gnostic", "The Tower Gnostic", {
            action("research_a_new_spell", "Research a new spell", "Spend gold per tile drawn from a Scrabble bag until the spell name is completed.", {
                costGold = 25,
                costUnit = "per_tile",
                persistentResearch = true,
            }),
        }, {
            languages = { "chivalric", "tylwyth" },
        }),
        [FACE_VALUES.KING] = district(SUITS.WANDS, FACE_VALUES.KING, "court_of_wands", "The Court of Wands", {
            action("join_the_court_of_wands", "Join the Court of Wands", "Pay dues to join the Court and receive an archwood staff.", {
                costGold = 100,
                membership = "court_of_wands",
                grants = "archwood_staff",
            }),
        }, {
            languages = { "chivalric", "tylwyth" },
        }),
    },
}

M.districtList = {}
for _, suit in ipairs({ SUITS.SWORDS, SUITS.PENTACLES, SUITS.CUPS, SUITS.WANDS }) do
    for _, value in ipairs({
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
        FACE_VALUES.PAGE, FACE_VALUES.KNIGHT, FACE_VALUES.QUEEN, FACE_VALUES.KING,
    }) do
        local entry = M.districts[suit][value]
        M.districtList[#M.districtList + 1] = entry
    end
end

function M.getDistrict(suit, value)
    return M.districts[suit] and M.districts[suit][value] or nil
end

function M.getCentralPower(card)
    if not card then
        return nil
    end
    local value = tonumber(card.value)
    if value and M.districts[card.suit] and M.districts[card.suit][value] and value >= FACE_VALUES.PAGE then
        return {
            id = "district_ruler",
            district = M.districts[card.suit][value],
        }
    end
    return M.centralPowers[card.suit]
end

return M
