-- mobs.lua
-- Data-driven mob blueprints for Majesty
-- Ticket T1_8: Templates for common entities
--
-- Add new monsters here - no code changes needed in factory.lua!
-- Attributes: swords, pentacles, cups, wands (0-6 for NPCs)

local M = {}

--------------------------------------------------------------------------------
-- MOB BLUEPRINTS
-- Each blueprint defines: attributes, conditions, armor, talents, starting_gear
--------------------------------------------------------------------------------

M.blueprints = {

    ----------------------------------------------------------------------------
    -- UNDEAD
    ----------------------------------------------------------------------------

    zombie = {
        name = "Zombie",
        attributes = {
            swords    = 0,
            pentacles = 0,
            cups      = 0,
            wands     = 0,
        },
        health = 1,
        defense = 0,
        instantDestruction = true,
        baseMorale = 20,
        undead = true,
        tags = { "undead", "minion", "zombie" },
        aiTags = { "undead", "zombie", "mindless", "rotting_brains" },
        social = {
            likes = { "fond_memory_of_life" },
            hates = { "living" },
        },
        notes = {
            breathlessAndUndreaming = "Ignores effects related to living processes; does not breathe or sleep and cannot be poisoned.",
            rottingBrains = "Ignores mind manipulation, is immune to Inspire, and cannot see illusions.",
            oldPossessions = "Often hold old possessions or carry the weapons they carried in life, wielded clumsily.",
            oldArmor = "Sometimes outfitted in old rusty armor; in that case, give them 1 Defense.",
        },
        zombie = {
            breathless = true,
            undreaming = true,
            livingProcessImmune = true,
            cannotBreathe = true,
            cannotSleep = true,
            cannotBePoisoned = true,
            poisonBloodImmune = true,
            rottingBrains = {
                mindManipulationImmune = true,
                inspireImmune = true,
                cannotSeeIllusions = true,
            },
            holdsOldPossessions = true,
            drawnToKnownPlaces = true,
            noMercy = true,
            clumsyFormerWeapons = true,
            optionalOldArmorDefense = 1,
            lastGrasp = {
                ignoreWoundByDiscardingGreaterDoom = true,
                severedLimb = {
                    sameInitiativeAsZombie = true,
                    health = 1,
                    cannotUseLastGrasp = true,
                    addsNewEnemy = true,
                },
            },
        },
        lesserDooms = {
            {
                id = "devour_the_living",
                name = "Devour the Living",
                description = "Devour a knocked-out or Death's Door living creature to Heal 2 Wounds.",
                effect = {
                    type = "devour_living",
                    targetStates = { "knocked_out", "deaths_door" },
                    healWounds = 2,
                },
            },
        },
        greaterDoom = {
            id = "last_grasp",
            name = "Last Grasp",
            description = "Discard a greater doom to ignore a Wound and spawn a severed limb.",
            effect = {
                type = "ignore_wound_spawn_limb",
                countsTowardTurnCard = false,
                severedLimb = {
                    sameInitiativeAsZombie = true,
                    health = 1,
                    cannotUseLastGrasp = true,
                },
            },
        },
        greaterDooms = {
            {
                id = "last_grasp",
                name = "Last Grasp",
                description = "Discard a greater doom to ignore a Wound and spawn a severed limb.",
                effect = {
                    type = "ignore_wound_spawn_limb",
                    countsTowardTurnCard = false,
                    severedLimb = {
                        sameInitiativeAsZombie = true,
                        health = 1,
                        cannotUseLastGrasp = true,
                    },
                },
            },
        },
        starting_gear = {},
    },

    skeleton_brute = {
        name = "Skeleton",
        attributes = {
            swords    = 6,
            pentacles = 1,
            cups      = 1,
            wands     = 4,
        },
        health = 6,
        defense = 0,
        instantDestruction = true,  -- Undead don't go to Death's Door, just fall apart
        baseMorale = 20,  -- S12.3: Undead feel no fear
        undead = true,
        tags = { "undead", "skeleton" },
        aiTags = { "undead", "skeleton", "mindless" },
        social = {
            likes = { "almost_nothing" },
            hates = { "life", "sound", "light" },
        },
        notes = {
            breathlessAndUndreaming = "Ignores effects related to living processes; does not breathe or sleep and cannot be poisoned.",
            emptySkulls = "Ignores attempts to manipulate their minds, is immune to Inspire, and cannot see illusions.",
            fleshless = "Immune to piercing weapons; actions targeting skeletons must exceed, not just match, their Initiative.",
        },
        skeleton = {
            breathless = true,
            undreaming = true,
            livingProcessImmune = true,
            cannotBePoisoned = true,
            poisonBloodImmune = true,
            mindManipulationImmune = true,
            inspireImmune = true,
            cannotSeeIllusions = true,
            piercingImmune = true,
            mustExceedInitiative = true,
        },
        lesserDooms = {
            {
                id = "unearthly_fear",
                name = "Unearthly Fear",
                description = "Play a lesser doom card and compare its value to each character in the same zone; add Wands if used on the skeleton's turn. Targets beaten are Stunned.",
                effect = {
                    type = "zone_stun_test",
                    attribute = "wands",
                    sameZone = true,
                },
            },
        },
        greaterDooms = {
            {
                id = "absorb_bones",
                name = "Absorb Bones",
                description = "If there is a ready source of bones in the zone, play a greater doom to Heal the skeleton.",
                effect = {
                    type = "heal_from_bones",
                },
            },
        },
        starting_gear = {
            hands = {
                { name = "Rusty Sword", size = 1, durability = 2 },
            },
        },
    },

    skeleton_archer = {
        name = "Skeleton Archer",
        attributes = {
            swords    = 2,
            pentacles = 4,
            cups      = 1,
            wands     = 3,
        },
        health = 2,   -- Frailer than brute
        defense = 0,
        instantDestruction = true,  -- Undead
        baseMorale = 20,  -- S12.3: Undead feel no fear
        undead = true,
        tags = { "undead", "skeleton" },
        aiTags = { "undead", "skeleton", "mindless" },
        starting_gear = {
            hands = {
                { name = "Cracked Bow", size = 2, durability = 1 },
            },
            belt = {
                { name = "Arrows", size = 1, stackable = true, stackSize = 12, quantity = 12 },
            },
        },
    },

    yellow_king_lich = {
        name = "Lich, The Yellow King",
        attributes = {
            swords    = 3,
            pentacles = 3,
            cups      = 3,
            wands     = 6,
        },
        health = 5,
        defense = 9,
        instantDestruction = true,
        baseMorale = 20,
        rank = "dungeon_lord",
        undead = true,
        tags = { "undead", "dungeon_lord", "lich", "yellow_king", "sorcerer" },
        aiTags = { "undead", "lich", "dungeon_lord", "phylactery", "second_sight", "mindless_immune", "spellcaster" },
        social = {
            likes = {
                "rambling_about_unrequited_love",
                "romantic_poetry",
                "performative_weeping",
                "magical_theory",
            },
            hates = {
                "being_interrupted",
                "strong_acids",
                "puns",
            },
        },
        notes = {
            phylactery = "When defeated, the body crumbles to an invulnerable crystal skull and eventually regrows unless the phylactery is destroyed.",
            crownOfArchwood = "The crown lets the Yellow King use magical powers without held components; Disarm knocks it away until he Recovers it.",
            breathlessAndUndreaming = "Ignores living-process effects, does not breathe or sleep, and cannot be poisoned.",
            secondSight = "Can see Shrouded creatures and identify magical effects.",
            rottingBrains = "Ignores mind manipulation, is immune to Inspire, and cannot see illusions.",
        },
        lich = {
            bodyCrumplesToCrystalSkullOnDefeat = true,
            bodyRegrowsIfPhylacteryIntact = true,
            phylactery = {
                object = "love_letter_from_kloe",
                location = "shelf_of_similar_letters_in_chambers",
                vulnerableObjectOfObsession = true,
                destroyToPreventRegrowth = true,
                nearby = true,
                health = 1,
                defense = 0,
            },
            crystalSkull = {
                impenetrable = true,
                invulnerable = true,
                regrowsBodyUnlessPhylacteryDestroyed = true,
            },
            body = {
                health = 5,
                defense = 9,
                deathSection = true,
                breathless = true,
                undreaming = true,
                livingProcessImmune = true,
                cannotBreathe = true,
                cannotSleep = true,
                cannotBePoisoned = true,
                poisonBloodImmune = true,
                secondSight = {
                    seesShrouded = true,
                    identifiesMagicalEffects = true,
                },
                rottingBrains = {
                    mindManipulationImmune = true,
                    inspireImmune = true,
                    cannotSeeIllusions = true,
                },
            },
            crownOfArchwood = {
                health = 1,
                defense = 4,
                enablesComponentlessMagic = true,
                notchedForWounds = 2,
                destroyedDisables = true,
                disarmKnocksFromHead = true,
                recoverRestoresCrown = true,
                saleValueGold = 1000,
                gramaryeUserMayUseAsArchwoodWand = true,
                adventurersCannotUseLichPowers = true,
                spiteAloneHoldsMeAloft = {
                    miscellaneousAction = true,
                    levitatesIndefinitely = true,
                    upperReachHover = true,
                    onlyRangedAttacksCanHit = true,
                },
                dayOfTearsAndMourning = {
                    canCastAnyAppendixASpell = true,
                    noComponentsRequired = true,
                    lesserDoomSpeakIncantation = true,
                    greaterDoomInsteadOfResolve = true,
                    additionalGreaterDoomAddsResolve = 1,
                },
            },
        },
        lesserDooms = {
            {
                id = "death_dealer",
                name = "Death Dealer",
                description = "The Yellow King manifests a hateful weapon and makes a melee Attack that deals Piercing damage.",
                effect = {
                    type = "melee_attack",
                    damageType = "piercing",
                    manifestedWeapon = true,
                },
            },
            {
                id = "may_failure_be_your_noose",
                name = "May Failure Be Your Noose",
                description = "If an adventurer fails to hit the Yellow King's Initiative, he may immediately play a card to make any standard Challenge Action against that adventurer without counting toward the one-card-per-turn limit.",
                effect = {
                    type = "reaction_after_failed_initiative_attack",
                    standardChallengeAction = true,
                    countsTowardTurnCard = false,
                },
            },
            {
                id = "sorrow_sorrow_sorrow",
                name = "Sorrow! Sorrow! Sorrow!",
                description = "After speaking about unrequited love, play a lesser doom and compare it to every listener's Initiative; add Wands on the Yellow King's turn. Beaten characters are Stunned.",
                effect = {
                    type = "audible_zone_stun_test",
                    addWandsOnOwnTurn = true,
                    condition = "stunned",
                },
            },
            {
                id = "poison_wont_take_you",
                name = "If the Poison Won't Take You My Dogs Will",
                source = "crown_of_archwood",
                description = "While wearing the crown, the Yellow King makes arcane-energy Attacks up to one zone away, adding Wands instead of Swords on his turn and never becoming engaged by the attack.",
                effect = {
                    type = "ranged_arcane_attack",
                    rangeZones = 1,
                    addAttributeOnOwnTurn = "wands",
                    doesNotEngage = true,
                    requiresCrown = true,
                },
            },
        },
        greaterDooms = {
            {
                id = "do_you_doubt_me_traitor",
                name = "Do You Doubt Me, Traitor?",
                description = "When damaged, discard a greater doom to make the attacker cross something off their character sheet until the end of their next Camp Phase; this does not count toward the one-card-per-turn limit.",
                effect = {
                    type = "damage_reaction_temporary_character_sheet_loss",
                    restoredAtEndOfNextCampPhase = true,
                    countsTowardTurnCard = false,
                },
            },
            {
                id = "faithful_servant_tender_companion",
                name = "Faithful Servant, Tender Companion",
                description = "Play a greater doom to create a temporary clone of any dead person from the guild's past; the clone knows everything they knew in life and has HD 1/0.",
                effect = {
                    type = "summon_dead_guild_clone",
                    temporary = true,
                    cloneKnowsLifeMemories = true,
                    health = 1,
                    defense = 0,
                },
            },
            {
                id = "enchant_insane_task",
                name = "Soft Is Their Throat, Soft Is Their Skull",
                description = "When the Yellow King Attacks, discard a greater doom to Control one target into an irrational task on success.",
                effect = {
                    type = "attack_control_task",
                    controlledTask = "irrational",
                },
            },
            {
                id = "day_of_tears_and_mourning",
                name = "Day of Tears and Mourning",
                source = "crown_of_archwood",
                description = "While wearing the crown, cast any Appendix A spell without components by playing a lesser doom Speak Incantation and discarding a greater doom instead of Resolve; extra greater dooms count as additional Resolve.",
                effect = {
                    type = "componentless_appendix_a_spellcasting",
                    requiresCrown = true,
                    noComponentsRequired = true,
                    lesserDoomSpeakIncantation = true,
                    greaterDoomInsteadOfResolve = true,
                    additionalGreaterDoomAddsResolve = 1,
                },
            },
        },
        alchemy = {
            noReagent = true,
            reason = "undead_lich",
        },
        starting_gear = {},
    },

    ----------------------------------------------------------------------------
    -- GOBLINS
    ----------------------------------------------------------------------------

    goblin_minion = {
        name = "Goblin Minion",
        attributes = {
            swords    = 2,
            pentacles = 3,
            cups      = 1,
            wands     = 2,
        },
        -- HD: 1/0 - One hit and they're down
        health = 1,
        defense = 0,
        baseMorale = 10,  -- S12.3: Goblins are cowardly
        disposition = "fear",  -- S12.4: Goblins start fearful
        starting_gear = {
            hands = {
                { name = "Shiv", size = 1, durability = 1 },
            },
        },
    },

    goblin_shaman = {
        name = "Goblin Shaman",
        attributes = {
            swords    = 1,
            pentacles = 2,
            cups      = 3,
            wands     = 4,
        },
        -- HD: 2/1 - Slightly tougher, has some magical protection
        health = 2,
        defense = 1,
        baseMorale = 14,  -- S12.3: Shamans have more confidence
        disposition = "distaste",  -- S12.4: Shamans are dismissive
        starting_gear = {
            hands = {
                { name = "Gnarled Staff", size = 2, durability = 2 },
            },
            belt = {
                { name = "Spell Component Pouch", size = 1 },
            },
        },
    },

    ----------------------------------------------------------------------------
    -- BEASTS
    ----------------------------------------------------------------------------

    dire_wolf = {
        name = "Dire Wolf",
        attributes = {
            swords    = 4,
            pentacles = 5,
            cups      = 2,
            wands     = 1,
        },
        -- HD: 3/1 - Tough beast, thick hide
        health = 3,
        defense = 1,  -- Thick fur/hide
        baseMorale = 14,  -- S12.3: Predator, but not suicidal
        -- No gear - natural weapons
        starting_gear = {},
    },

    face_rat = {
        name = "Face Rat",
        attributes = {
            swords    = 0,
            pentacles = 0,
            cups      = 0,
            wands     = 0,
        },
        health = 2,
        defense = 0,
        baseMorale = 10,
        rank = "minion",
        tags = { "beast", "minion", "face_rat", "rat", "thief", "affliction" },
        aiTags = { "beast", "face_rat", "scurry", "belt_thief", "face_stealer" },
        social = {
            likes = {
                "its_mate",
                "its_weird_pink_babies",
            },
            hates = {
                "fire",
            },
        },
        notes = {
            scurry = "On its turn, can Move 1 zone without spending a card.",
            stolenFace = "A successful Steal Face permanently gives the rat a face identical to the victim.",
        },
        faceRat = {
            scurryMoveZones = 1,
            freeMoveOnTurn = true,
            badLittleHands = {
                roughhouseStealsBeltItem = true,
                holdsStolenItem = true,
                cannotUseStolenItem = true,
                canScurryAwayWithStolenItem = true,
                canBreakFragileStolenItem = true,
                retrieveByDisarmOrKilling = true,
            },
            faceRatDisease = {
                affliction = true,
                stages = {
                    {
                        id = "featureless_mask",
                        cureCharges = 1,
                        wandsInfluenceDisfavor = true,
                    },
                    {
                        id = "skin_over_nose_and_mouth",
                        cureCharges = 1,
                        condition = "silenced",
                    },
                    {
                        id = "skin_over_eyes",
                        cureCharges = 2,
                        condition = "blind",
                    },
                },
            },
            stealFace = {
                blinds = true,
                silences = true,
                replacesWound = true,
                blindAndSilenceRecoverSeparately = true,
                faceCopiedPermanently = true,
            },
        },
        lesserDooms = {
            {
                id = "bad_little_hands",
                name = "Bad Little Hands",
                description = "The face rat can Roughhouse to steal one target belt item; it holds the item but cannot use it, and Disarm or killing the rat gets it back.",
                effect = {
                    type = "roughhouse_steal_belt_item",
                    targetLocation = "belt",
                    retrieveBy = { "disarm", "kill" },
                },
            },
        },
        greaterDooms = {
            {
                id = "infectious_disease",
                name = "Infectious Disease",
                description = "When the face rat Attacks, discard a greater doom to make the bite poisonous; on success, the target contracts Face Rat Disease in addition to a Wound.",
                effect = {
                    type = "attack_affliction",
                    affliction = "face_rat_disease",
                    alsoDealsWound = true,
                },
            },
            {
                id = "steal_face",
                name = "Steal Face",
                description = "When the face rat Attacks, discard a greater doom to Blind and Silence the target instead of dealing a Wound; the rat permanently copies the target's face.",
                effect = {
                    type = "attack_blind_and_silence",
                    replacesWound = true,
                    blind = true,
                    silence = true,
                    recoverSeparately = true,
                    copiesFacePermanently = true,
                },
            },
        },
        alchemy = {
            reagentTemplateId = "face_rat_reagent",
            yield = 1,
        },
        starting_gear = {},
    },

    lion = {
        name = "Lion",
        attributes = {
            swords    = 6,
            pentacles = 2,
            cups      = 1,
            wands     = 3,
        },
        health = 3,
        defense = 3,
        baseMorale = 16,
        rank = "strategist",
        tags = { "beast", "strategist", "lion", "noble", "king_of_beasts" },
        aiTags = { "beast", "lion", "fleet", "untrackable", "mercy", "roar_of_life" },
        social = {
            likes = {
                "its_mate",
                "its_young",
                "fresh_ape_meat",
            },
            hates = {
                "creaking_cart_wheels",
                "white_chickens",
                "fire",
            },
        },
        notes = {
            fleet = "On its turn, can Move 1 zone without spending a card.",
            untrackable = "If it knows it is being hunted, it covers its tracks with its tail and prevents all tracking attempts.",
            nobleMercy = "Will never kill anything that prostrates itself and asks for mercy.",
            deadCubs = "Cubs are born dead and are brought to life after the third day by their parents' roaring.",
        },
        lion = {
            kingOfBeasts = true,
            fleetMoveZones = 1,
            freeMoveOnTurn = true,
            untrackable = {
                requiresKnowingItIsHunted = true,
                coversTracksWithTail = true,
                preventsAllTracking = true,
            },
            mercy = {
                prostrationAndMercyRequestPreventsKilling = true,
            },
            reproduction = {
                cubsByLitter = { 5, 4, 3, 2, 1, 0 },
                sterileAfterSixthLitter = true,
                lionPlusPardMakesLeopard = true,
                cubsBornDead = true,
                roarAfterThirdDayBringsCubsToLife = true,
            },
            roarOfLife = {
                canReviveCreatureThatDiedWithoutSin = true,
                usuallyChildrenAreSinless = true,
                cleansedAdultsMayQualify = true,
            },
        },
        lesserDooms = {
            {
                id = "bite",
                name = "Bite",
                description = "On a successful Attack, the target is also either Disarmed or Tripped, GM's choice.",
                effect = {
                    type = "attack_plus_condition_choice",
                    choices = { "disarmed", "tripped" },
                    chooser = "gm",
                },
            },
            {
                id = "claw",
                name = "Claw",
                description = "On a successful Attack, if the lion's total Attack value is double the target's Initiative, deal 2 Wounds.",
                effect = {
                    type = "attack_double_initiative_bonus",
                    wounds = 2,
                },
            },
        },
        greaterDooms = {
            {
                id = "cautious_retreat",
                name = "Cautious Retreat",
                description = "Discard a greater doom to automatically disengage from a single adventurer; this does not count toward the one-card-per-turn limit.",
                effect = {
                    type = "disengage_one",
                    countsTowardTurnCard = false,
                },
            },
            {
                id = "roar_of_life",
                name = "Roar of Life",
                description = "If a creature dies without sin, a lion's roar can bring them back to life.",
                effect = {
                    type = "revive_sinless_dead",
                    usuallyChildrenAreSinless = true,
                    cleansedAdultsMayQualify = true,
                },
            },
        },
        alchemy = {
            noReagent = true,
            reason = "not_appendix_b_source",
        },
        starting_gear = {},
    },

    ----------------------------------------------------------------------------
    -- ARMORED FOES
    ----------------------------------------------------------------------------

    knight_errant = {
        name = "Knight Errant",
        attributes = {
            swords    = 5,
            pentacles = 2,
            cups      = 3,
            wands     = 3,
        },
        -- HD: 3/5 - Tough warrior in heavy armor (Defense represents plate armor)
        health = 3,
        defense = 5,  -- Heavy plate armor
        baseMorale = 16,  -- S12.3: Trained and disciplined
        starting_gear = {
            hands = {
                { name = "Longsword", size = 1, durability = 3 },
                { name = "Heater Shield", size = 1, durability = 2, properties = { tags = { "shield" } } },
            },
            belt = {
                { name = "Plate Armor", size = 2, isArmor = true, durability = 3 },
            },
        },
    },

    ----------------------------------------------------------------------------
    -- ELEMENTALS
    ----------------------------------------------------------------------------

    fungoid = {
        name = "Fungoid",
        attributes = {
            swords    = 4,
            pentacles = 1,
            cups      = 2,
            wands     = 3,
        },
        health = 3,
        defense = 3,
        baseMorale = 14,
        rank = "strategist",
        tags = { "elemental", "strategist", "fungoid", "mushroom", "spores", "illusionist" },
        aiTags = { "elemental", "fungoid", "spores", "illusion", "poison_immune", "regenerates" },
        social = {
            likes = {
                "learning_about_mortals",
                "dampness",
                "rain",
                "tearing_things_up",
            },
            hates = {
                "open_spaces",
                "trespassers",
            },
        },
        notes = {
            brainSpores = "Every successful melee Attack against a fungoid costs the adventurer 1 lore bid.",
            poisonImmunity = "Fungoids cannot be poisoned.",
        },
        fungoid = {
            brainSpores = {
                meleeAttackSuccessCostsLoreBids = 1,
            },
            poisonImmune = true,
            chokingSpores = {
                sameZone = true,
                condition = "silenced",
                recoverable = true,
            },
            minorIllusion = {
                nonLivingObjectOnly = true,
                imageOnly = true,
                noWeight = true,
                noSubstance = true,
                noSound = true,
                noSmell = true,
            },
            perfectImitation = {
                imitatesPerson = true,
                impossibleToDistinguishInSameZone = true,
                targetRedirectChance = 0.5,
                endsOnWound = true,
            },
        },
        lesserDooms = {
            {
                id = "choking_spores",
                name = "Choking Spores",
                description = "Play a lesser doom to Silence all creatures in the same zone as the fungoid; adventurers can Recover to clear the effect.",
                effect = {
                    type = "same_zone_condition",
                    condition = "silenced",
                    recoverable = true,
                },
            },
            {
                id = "minor_illusion",
                name = "Minor Illusion",
                description = "Play a lesser doom to create a silent, scentless, insubstantial image of any non-living object.",
                effect = {
                    type = "minor_illusion",
                    nonLivingObjectOnly = true,
                    imageOnly = true,
                },
            },
        },
        greaterDooms = {
            {
                id = "fungal_regeneration",
                name = "Fungal Regeneration",
                description = "Discard a greater doom to Heal 1 Wound; this does not count toward the one-card-per-turn limit.",
                effect = {
                    type = "heal",
                    wounds = 1,
                    countsTowardTurnCard = false,
                },
            },
            {
                id = "perfect_imitation",
                name = "Perfect Imitation",
                description = "Play a greater doom to appear as a perfect duplicate of any person; in the same zone as the original, outside observers cannot tell them apart and targeting the fungoid has a 50% chance to affect the original instead.",
                effect = {
                    type = "perfect_imitation",
                    targetRedirectChance = 0.5,
                    endsOnWound = true,
                },
            },
        },
        alchemy = {
            reagentTemplateId = "fungoid_reagent",
            yield = 1,
        },
        starting_gear = {},
    },

    harpy = {
        name = "Harpy",
        attributes = {
            swords    = 2,
            pentacles = 2,
            cups      = 0,
            wands     = 0,
        },
        health = 3,
        defense = 0,
        baseMorale = 14,
        rank = "minion",
        tags = { "elemental", "minion", "harpy", "flying" },
        aiTags = { "elemental", "harpy", "flying", "flutter", "gang_up", "shriek" },
        social = {
            likes = {
                "cruel_jokes",
                "raw_and_rotten_food",
                "shiny_treasure",
            },
            hates = {
                "clean_water",
                "beautiful_women",
                "jokes_at_their_own_expense",
            },
        },
        notes = {
            flutter = "Harpies Move 1 zone without spending a card each turn.",
            gangUp = "A harpy prefers to gang up on a single target with her sisters.",
        },
        harpy = {
            flutterMoveZones = 1,
            freeMoveOnTurn = true,
            prefersGangUp = true,
            flight = {
                requiresEnoughSpace = true,
                moveAction = true,
                avoidsMeleeEngagement = true,
                rangedWeaponsStillApply = true,
                flyByAttackAllowsMeleeTargetingThisTurn = true,
                flyByAttackDoesNotCauseEngagement = true,
            },
            peltWithStones = {
                costsAnyCard = true,
                gathersScenery = true,
                thrownAsMissileWhileFlying = true,
            },
            pullIntoTheAir = {
                addsPentaclesOnHarpyTurn = true,
                dealsPiercingDamage = true,
                harpyBecomesEngaged = true,
            },
            shriek = {
                sameZoneNonHarpiesStunned = true,
                drawsNearbyCreatures = true,
            },
        },
        lesserDooms = {
            {
                id = "flight",
                name = "Flight",
                description = "If there is enough space, the harpy can fly as a Move action; while flying, it stays out of melee engagement but remains vulnerable to ranged weapons.",
                effect = {
                    type = "fly_move",
                    requiresEnoughSpace = true,
                    avoidsMeleeEngagement = true,
                    rangedWeaponsStillApply = true,
                    flyByAttackAllowed = true,
                },
            },
            {
                id = "pelt_with_stones",
                name = "Pelt with Stones",
                description = "Play any card to pick up scenery that can be thrown while flying as a missile Attack.",
                effect = {
                    type = "prepare_thrown_scenery",
                    costsAnyCard = true,
                    missileAttackWhileFlying = true,
                },
            },
            {
                id = "pull_into_the_air",
                name = "Pull Into the Air",
                description = "Attempt to pull an adventurer into the air and drop them; on the harpy's turn, add Pentacles to the total. This deals Piercing damage and engages the harpy.",
                effect = {
                    type = "roughhouse_lift_and_drop",
                    addsPentaclesOnOwnTurn = true,
                    damageType = "piercing",
                    actorBecomesEngaged = true,
                },
            },
        },
        greaterDooms = {
            {
                id = "shriek",
                name = "Shriek",
                description = "Play a greater doom to let out an ear-splitting wail; all non-harpies in the same zone are Stunned and nearby creatures are drawn to the sound.",
                effect = {
                    type = "same_zone_stun",
                    excludeTags = { "harpy" },
                    drawsNearbyCreatures = true,
                },
            },
        },
        alchemy = {
            reagentTemplateId = "harpy_reagent",
            yield = 1,
        },
        starting_gear = {},
    },

    kelpie = {
        name = "Kelpie",
        attributes = {
            swords    = 4,
            pentacles = 6,
            cups      = 1,
            wands     = 1,
        },
        health = 5,
        defense = 0,
        baseMorale = 14,
        rank = "brute",
        tags = { "elemental", "brute", "kelpie", "aquatic", "horse" },
        aiTags = { "elemental", "kelpie", "aquatic", "threshold", "drowner" },
        social = {
            likes = {
                "young_women",
                "horses",
            },
            hates = {
                "fire",
                "silver",
            },
            languages = {
                understands = { "tylwyth" },
                cannotSpeak = true,
            },
        },
        notes = {
            bondingBack = "Anyone who attempts to ride a kelpie or touches its mane is automatically Rooted to its back; Recover clears this.",
            threshold = "Takes no damage until dealt 2 Wounds in one turn or damaged by a silver weapon, then takes damage normally.",
            waterHorse = "Can swim and walk on water; in water, it can Move 1 zone without spending a card each turn.",
        },
        kelpie = {
            bondingBack = {
                touchingManeRoots = true,
                attemptingToRideRoots = true,
                recoverable = true,
                rootedVictimMovesWithKelpie = true,
                underwaterTurnPiercingDamage = 1,
                metalArmorRecoveryUnderwaterCannotSwim = true,
            },
            threshold = {
                ignoresDamageUntil = {
                    woundsInSingleTurn = 2,
                    silverWeaponDamage = true,
                },
                thenTakesDamageNormally = true,
            },
            waterHorse = {
                swims = true,
                walksOnWater = true,
                waterMoveZones = 1,
                freeMoveInWaterOnTurn = true,
            },
            understandsTylwyth = true,
            cannotSpeak = true,
        },
        lesserDooms = {
            {
                id = "trample",
                name = "Trample",
                description = "On an unsuccessful Attack, the kelpie may use its Attack action against a second target in the same zone.",
                effect = {
                    type = "second_attack_after_miss",
                    targetScope = "same_zone",
                },
            },
        },
        alchemy = {
            reagentTemplateId = "kelpie_reagent",
            yield = 1,
        },
        starting_gear = {},
    },

    nymph = {
        name = "Nymph",
        attributes = {
            swords    = 1,
            pentacles = 3,
            cups      = 2,
            wands     = 4,
        },
        health = 3,
        defense = 0,
        baseMorale = 14,
        tags = { "elemental", "nymph" },
        aiTags = { "elemental", "nymph", "retreats_to_home" },
        social = {
            likes = {
                "music",
                "wine",
                "gossip",
                "gifts",
                "clams",
                "crabs",
                "cockles",
                "cowries",
            },
            hates = {
                "being_read_poetry",
                "drama",
                "sour_tastes",
            },
        },
        notes = {
            elementalImmunity = "Takes no damage from their chosen element.",
            elementalMeld = "Can become immaterial and step into their elemental home as a miscellaneous action.",
        },
        nymph = {
            chosenElement = "varies",
            elementalHome = "varies",
            elementalImmunity = true,
            elementalMeld = true,
            aidTravelers = true,
            knowsDomainTreasures = true,
            wantsByMinorSuit = {
                swords = "Choose the fairest nymph for a treasure reward.",
                pentacles = "Tell them the latest fashions among ladies of the City.",
                cups = "Bring sweet wine to drink.",
                wands = "Teach them a new song.",
            },
        },
        lesserDooms = {
            {
                id = "bewitching_beauty",
                name = "Bewitching Beauty",
                description = "Discard any card to automatically Displace all adventurers who can see the nymph toward her; each may spend 1 Resolve to resist.",
                effect = {
                    type = "displace_visible_adventurers",
                    direction = "toward_nymph",
                    resistResolve = 1,
                },
            },
        },
        greaterDooms = {
            {
                id = "expeditious_retreat",
                name = "Expeditious Retreat",
                description = "Discard a greater doom card to automatically disengage from all adventurers; this does not count toward the one-card-per-turn limit.",
            },
            {
                id = "sleep_song",
                name = "Sleep Song",
                description = "Speak Incantations and discard a greater doom card to Knock Out an adventurer until awoken with a sharp slap.",
                effect = {
                    type = "sleep_song",
                    action = "speak_incantation",
                    condition = "knockout",
                    wake = "sharp_slap",
                },
            },
        },
        alchemy = {
            reagentTemplateId = "nymph_reagent",
            yield = 1,
        },
        starting_gear = {},
    },

    ----------------------------------------------------------------------------
    -- SORCEROUS BRUTES
    ----------------------------------------------------------------------------

    ogre = {
        name = "Ogre",
        attributes = {
            swords    = 6,
            pentacles = 4,
            cups      = 1,
            wands     = 1,
        },
        health = 3,
        defense = 5,
        baseMorale = 16,
        tags = { "sorcerous", "brute", "ogre", "cursed", "large" },
        aiTags = { "brute", "ogre", "hungry", "bully" },
        size = "large",
        social = {
            likes = {
                "eating_anything",
                "hurting_puppies",
                "seeing_children_cry",
            },
            hates = {
                "elves",
                "laughter",
            },
        },
        notes = {
            eatEatEat = "Can play any card to eat a held object; eaten objects are Destroyed.",
            hideousStrength = "Can play any card for incredible feats of strength.",
            tough = "Actions targeting ogres must exceed, not just match, their Initiative.",
        },
        ogre = {
            cursed = true,
            canEatAnyObject = true,
            eatenObjectsDestroyed = true,
            cannotBePoisoned = true,
            poisonBloodImmune = true,
            tremendousStrength = true,
            mustExceedInitiative = true,
            attacksElvesFirst = true,
        },
        lesserDooms = {
            {
                id = "sweeping_club",
                name = "Sweeping Club",
                description = "When the ogre Attacks on its turn, the Attack targets all adventurers in its zone.",
                effect = {
                    type = "zone_attack",
                    targets = "all_adventurers_in_zone",
                },
            },
        },
        greaterDooms = {
            {
                id = "bully",
                name = "Bully",
                description = "Discard a greater doom card to force a particular adventurer to erase the charge on one charged Bond.",
                effect = {
                    type = "erase_charged_bond",
                },
            },
            {
                id = "overwhelming_attack",
                name = "Overwhelming Attack",
                description = "The ogre can play a greater doom as an Attack action.",
                effect = {
                    type = "greater_doom_attack",
                },
            },
        },
        alchemy = {
            reagentTemplateId = "ogre_reagent",
            yield = 1,
        },
        starting_gear = {
            hands = {
                { name = "Massive Club", size = 2, durability = 2, weaponType = "club", isWeapon = true },
            },
        },
    },

    ----------------------------------------------------------------------------
    -- HERALDIC BEASTS
    ----------------------------------------------------------------------------

    questing_beast = {
        name = "Questing Beast",
        attributes = {
            swords    = 1,
            pentacles = 4,
            cups      = 2,
            wands     = 3,
        },
        health = 3,
        defense = 3,
        baseMorale = 14,
        tags = { "beast", "strategist", "questing_beast", "heraldic" },
        aiTags = { "beast", "strategist", "fast", "evasive", "noisy" },
        social = {
            likes = {
                "bright_colors",
                "fish",
                "horses",
                "hunting_horns",
            },
            hates = {
                "falcons",
                "perfume",
            },
        },
        notes = {
            fleet = "On its turn, can Move 2 zones without spending a card.",
            slippery = "Can discard any card to avoid a dungeon hazard without counting toward the one-card-per-turn limit.",
            noisyQuest = "Its barking draws attention from creatures a few rooms away and it intentionally triggers traps as it runs past.",
        },
        questingBeast = {
            fleetMoveZones = 2,
            freeMoveOnTurn = true,
            slipperyHazardAvoidance = true,
            hazardAvoidanceCostsAnyCard = true,
            hazardAvoidanceCountsAsTurnCard = false,
            noisyBarkingDrawsAttention = true,
            intentionallyTriggersTraps = true,
            canDashWithAnyLesserDoom = true,
        },
        lesserDooms = {
            {
                id = "nip",
                name = "Nip",
                description = "On a successful Riposte, the questing beast deals 2 Wounds.",
                effect = {
                    type = "riposte_damage",
                    wounds = 2,
                },
            },
            {
                id = "trample",
                name = "Trample",
                description = "On an unsuccessful Attack, the questing beast may use their Attack action against a second target in the same zone.",
                effect = {
                    type = "second_attack_after_miss",
                    targetScope = "same_zone",
                },
            },
        },
        greaterDooms = {
            {
                id = "evasive",
                name = "Evasive",
                description = "The questing beast can play a greater doom as a Dodge action.",
                effect = {
                    type = "greater_doom_dodge",
                },
            },
            {
                id = "expeditious_retreat",
                name = "Expeditious Retreat",
                description = "Discard a greater doom card to automatically disengage from all combatants; this does not count toward the one-card-per-turn limit.",
            },
            {
                id = "resilient",
                name = "Resilient",
                description = "Discard a greater doom card to automatically Recover from all effects; this does not count toward the one-card-per-turn limit.",
                effect = {
                    type = "recover_all_effects",
                },
            },
            {
                id = "tactics",
                name = "Tactics",
                description = "Discard a greater doom card to turn a standard Challenge Action into an interrupt.",
                effect = {
                    type = "standard_action_as_interrupt",
                },
            },
        },
        alchemy = {
            reagentTemplateId = "questing_beast_reagent",
            yield = 1,
        },
        starting_gear = {},
    },

    cockatrice = {
        name = "Cockatrice",
        attributes = {
            swords    = 4,
            pentacles = 4,
            cups      = 4,
            wands     = 4,
        },
        health = 5,
        defense = 0,
        baseMorale = 14,
        rank = "elite",
        tags = { "beast", "elite", "cockatrice", "flying", "petrifying" },
        aiTags = { "beast", "elite", "cockatrice", "gaze", "petrification", "flying" },
        social = {
            likes = {
                "warmth_and_heat",
                "its_young",
                "dire_rats",
                "shiny_objects",
            },
            hates = {
                "normal_chickens",
            },
        },
        notes = {
            gazeOfTheCockatrice = "Once per round, automatically focuses its gaze on one creature without spending a card. Phase 1 Roots the target; Phase 2 petrifies an already Rooted target as a Curse.",
            mirrorImmunity = "The gaze effect is not reflected by mirrors.",
            freshBloodCuresStone = "Very fresh cockatrice blood reverses petrification.",
        },
        cockatrice = {
            trueEyesInSerpentHead = true,
            chickenBodyIsTail = true,
            canAttackAndFlyWithChickenBody = true,
            gaze = {
                oncePerRound = true,
                automatic = true,
                spendsCard = false,
                reflectedByMirrors = false,
                phase1 = {
                    condition = "rooted",
                    recoverable = true,
                },
                phase2 = {
                    requiresCondition = "rooted",
                    condition = "petrified",
                    curse = true,
                    recoverable = false,
                },
            },
            bloodCuresPetrification = {
                mustBeVeryFresh = true,
                restoresStoneToFlesh = true,
            },
        },
        lesserDooms = {
            {
                id = "tail_bite",
                name = "Tail Bite",
                description = "On a successful Attack, the target both takes a Wound and is Displaced.",
                effect = {
                    type = "attack_wound_and_displace",
                    wounds = 1,
                    displace = true,
                },
            },
        },
        greaterDooms = {
            {
                id = "backwards_charge",
                name = "Backwards Charge",
                description = "When the cockatrice Attacks, discard a greater doom to Move up to 2 zones and cut at a foe with its spurs; on success, the target is Wounded and Tripped. The cockatrice can maintain its gaze and charge.",
                effect = {
                    type = "attack_charge",
                    moveZones = 2,
                    wounds = 1,
                    trips = true,
                    canMaintainGaze = true,
                },
            },
            {
                id = "flutter",
                name = "Flutter",
                description = "Play a greater doom card to automatically disengage from all adventurers and fly 1 zone away.",
                effect = {
                    type = "disengage_and_move",
                    disengageAll = true,
                    moveZones = 1,
                    flying = true,
                },
            },
        },
        alchemy = {
            reagentTemplateId = "cockatrice_reagent",
            yield = 1,
        },
        starting_gear = {},
    },

    dragon = {
        name = "Dragon",
        attributes = {
            swords    = 6,
            pentacles = 3,
            cups      = 3,
            wands     = 3,
        },
        health = 5,
        defense = 10,
        baseMorale = 18,
        rank = "elite",
        size = "huge",
        tags = { "beast", "elite", "dragon", "huge", "flying", "fire_breath", "tough" },
        aiTags = { "beast", "elite", "dragon", "huge", "tough", "flight", "fire_breath", "tail_whip" },
        social = {
            likes = {
                "fire",
                "gold",
                "royalty",
                "traps",
            },
            hates = {
                "cold",
                "panthers",
            },
            languages = {
                intelligent = true,
                successfullyCommunicated = false,
            },
        },
        notes = {
            dragonfear = "Seeing a dragon for the first time is awe-inspiring and terrifying.",
            huge = "Immune to being Roughhoused unless the adventurer can affect a creature of giant size.",
            tough = "Actions that target the dragon must exceed, not just match, its Initiative.",
            flight = "If there is enough space, the dragon can fly as a Move action and lazily circle out of melee engagement.",
        },
        dragon = {
            enigmatic = true,
            intelligent = true,
            noKnownSuccessfulCommunication = true,
            dragonfear = true,
            huge = {
                immuneToRoughhouseUnlessGiantSized = true,
                giantSizeRequired = true,
            },
            tough = {
                mustExceedInitiative = true,
            },
            flight = {
                requiresEnoughSpace = true,
                moveAction = true,
                avoidsMeleeEngagement = true,
                rangedWeaponsStillApply = true,
                flyByAttackAllowsMeleeTargetingThisTurn = true,
                flyByAttackDoesNotCauseEngagement = true,
            },
            breathOfFire = {
                rangeZones = 1,
                metalArmorCriticalDamage = true,
                unarmoredWounds = 3,
            },
        },
        lesserDooms = {
            {
                id = "claw",
                name = "Claw",
                description = "On a successful Attack, if the dragon's total Attack value is double the target's Initiative, deal 2 Wounds.",
                effect = {
                    type = "attack_double_initiative_bonus",
                    wounds = 2,
                },
            },
            {
                id = "flight",
                name = "Flight",
                description = "If there is enough space, the dragon can fly as a Move action; while flying, it stays out of melee engagement but remains vulnerable to ranged weapons.",
                effect = {
                    type = "fly_move",
                    requiresEnoughSpace = true,
                    avoidsMeleeEngagement = true,
                    rangedWeaponsStillApply = true,
                    flyByAttackAllowed = true,
                },
            },
            {
                id = "tail_whip",
                name = "Tail Whip",
                description = "The dragon's Attack targets all adventurers in its zone.",
                effect = {
                    type = "attack_all_adventurers_in_zone",
                },
            },
        },
        greaterDooms = {
            {
                id = "armored_scales",
                name = "Armored Scales",
                description = "The dragon can play a greater doom card as its Initiative.",
                effect = {
                    type = "greater_doom_as_initiative",
                },
            },
            {
                id = "breath_of_fire",
                name = "Breath of Fire",
                description = "When the dragon Attacks, discard a greater doom to breathe fire up to 1 zone away; metal-armored targets take Critical damage on a hit, while unarmored targets take 3 Wounds.",
                effect = {
                    type = "attack_fire_breath",
                    rangeZones = 1,
                    metalArmorDamageType = "critical",
                    unarmoredWounds = 3,
                },
            },
            {
                id = "overwhelming_bite",
                name = "Overwhelming Bite",
                description = "The dragon can play a greater doom as an Attack action; on success, the target takes a Wound and is either Disarmed or Tripped.",
                effect = {
                    type = "greater_doom_attack_action",
                    wounds = 1,
                    choices = { "disarmed", "tripped" },
                },
            },
        },
        alchemy = {
            noReagent = true,
            reason = "not_appendix_b_source",
        },
        starting_gear = {},
    },

    griffin = {
        name = "Griffin",
        attributes = {
            swords    = 4,
            pentacles = 3,
            cups      = 1,
            wands     = 1,
        },
        health = 7,
        defense = 0,
        baseMorale = 14,
        rank = "brute",
        tags = { "beast", "brute", "griffin", "heraldic", "flying" },
        aiTags = { "beast", "brute", "griffin", "fleet", "flying", "grabber", "fly_by" },
        social = {
            likes = {
                "compliments",
                "its_mate",
                "its_nest",
                "other_birds",
            },
            hates = {
                "fire",
                "harpies",
                "lions",
            },
            languages = {
                understands = { "chivalric" },
                cannotSpeak = true,
            },
        },
        notes = {
            fleet = "On its turn, can Move 2 zones without spending a card.",
            flight = "Can fly as a Move action when there is enough space; while flying, it stays out of melee engagement but remains vulnerable to ranged weapons.",
            flyByAttack = "A fly-by Attack lets melee attacks target the griffin that turn without making it engaged.",
        },
        griffin = {
            fleetMoveZones = 2,
            freeMoveOnTurn = true,
            understandsChivalric = true,
            cannotSpeak = true,
            flight = {
                requiresEnoughSpace = true,
                moveAction = true,
                avoidsMeleeEngagement = true,
                rangedWeaponsStillApply = true,
                flyByAttackAllowsMeleeTargetingThisTurn = true,
                flyByAttackDoesNotCauseEngagement = true,
            },
            talons = {
                doubleTargetInitiativeDealsWounds = 2,
            },
            grab = {
                roughhouseGreaterDoom = true,
                targetRooted = true,
                targetMovesWithGriffin = true,
                canDropVictimAsFreeActionWhileFlying = true,
                droppedVictimSuffersFallingDamage = true,
                recoverAllowed = true,
                recoverWhileFlyingCausesFallingDamage = true,
                missedAttacksHitGrabbedVictim = true,
            },
        },
        lesserDooms = {
            {
                id = "flight",
                name = "Flight",
                description = "If there is enough space, the griffin can fly as a Move action; while flying, it stays out of melee engagement but remains vulnerable to ranged weapons.",
                effect = {
                    type = "fly_move",
                    requiresEnoughSpace = true,
                    avoidsMeleeEngagement = true,
                    rangedWeaponsStillApply = true,
                    flyByAttackAllowed = true,
                },
            },
            {
                id = "talons",
                name = "Talons",
                description = "On a successful Attack, if the griffin's total Attack value is double the target's Initiative, deal 2 Wounds.",
                effect = {
                    type = "attack_double_initiative_bonus",
                    wounds = 2,
                },
            },
        },
        greaterDooms = {
            {
                id = "grab",
                name = "Grab",
                description = "When the griffin Roughhouses, discard a greater doom to grab the target; on success, the target is Rooted and moves with the griffin.",
                effect = {
                    type = "roughhouse_grab",
                    targetRooted = true,
                    targetMovesWithActor = true,
                    missedAttacksHitGrabbedVictim = true,
                    flyingDrop = {
                        freeAction = true,
                        causesFallingDamage = true,
                        recoverAlsoCausesFallingDamage = true,
                    },
                },
            },
        },
        alchemy = {
            reagentTemplateId = "griffin_reagent",
            yield = 1,
        },
        starting_gear = {},
    },

    ----------------------------------------------------------------------------
    -- SORCEROUS CONSTRUCTS
    ----------------------------------------------------------------------------

    animate_statue = {
        name = "Animate Statue",
        attributes = {
            swords    = 5,
            pentacles = 5,
            cups      = 1,
            wands     = 1,
        },
        health = 1,
        defense = 15,
        baseMorale = 14,
        rank = "brute",
        construct = true,
        tags = { "sorcerous", "construct", "brute", "animate_statue", "bronze", "magic_sensitive" },
        aiTags = { "construct", "animate_statue", "tough", "magic_null", "sense_magic", "grabber" },
        social = {
            likes = {
                "sleeping",
                "being_admired",
                "sculptors",
            },
            hates = {
                "sorcerers",
                "iconoclasts",
            },
            languages = {
                intelligent = true,
                cannotSpeak = true,
            },
        },
        notes = {
            boundSpirit = "Animated by a bound spirit in a bronze statue body.",
            runeWeakSpot = "Low Health and high Defense represent the magical rune weak point that binds the spirit.",
            construct = "Treats Notches as 2 Wounds.",
            magicallyNull = "Immune to magic except magic that specifically targets objects, at GM discretion.",
            senseMagic = "Can sense magical effects and identify sorcerers by sight.",
            tough = "Actions that target the animate statue must exceed, not just match, its Initiative.",
        },
        animateStatue = {
            boundSpirit = true,
            bronzeBody = true,
            intelligent = true,
            cannotSpeak = true,
            runeWeakSpot = true,
            treatsNotchesAsWounds = 2,
            magicNull = {
                immuneToMagic = true,
                objectTargetingMagicMayAffect = true,
                gmDiscretion = true,
            },
            senseMagic = {
                sensesMagicalEffects = true,
                identifiesSorcerersBySight = true,
            },
            tough = {
                mustExceedInitiative = true,
            },
            grab = {
                targetRooted = true,
                targetMovesWithStatue = true,
                holdCapacity = 2,
                enablesSqueeze = true,
                missedAttacksHitGrabbedTarget = true,
            },
        },
        lesserDooms = {
            {
                id = "haymaker",
                name = "Haymaker",
                description = "When the animate statue Attacks on its turn, the Attack targets all adventurers in its zone.",
                effect = {
                    type = "attack_all_adventurers_in_zone",
                    onlyOnOwnTurn = true,
                },
            },
            {
                id = "grab",
                name = "Grab",
                description = "The animate statue can Roughhouse to grab a foe; grabbed adventurers are Rooted, move with the statue, can be squeezed, and missed Attacks against the statue hit a grabbed foe instead.",
                effect = {
                    type = "roughhouse_grab",
                    targetRooted = true,
                    targetMovesWithActor = true,
                    holdCapacity = 2,
                    enablesSqueeze = true,
                    missedAttacksHitGrabbedTarget = true,
                },
            },
            {
                id = "throw_stones",
                name = "Throw Stones",
                description = "The animate statue can Attack by throwing heavy things such as armor, stones, or held foes; a thrown grabbed adventurer automatically takes a Wound.",
                effect = {
                    type = "throw_heavy_object",
                    canThrowHeldFoe = true,
                    thrownHeldFoeAutomaticWound = true,
                },
            },
        },
        greaterDooms = {
            {
                id = "squeeze",
                name = "Squeeze",
                description = "Play a greater doom to squeeze all grabbed adventurers, automatically dealing each a Wound.",
                effect = {
                    type = "wound_grabbed_targets",
                    wounds = 1,
                },
            },
        },
        alchemy = {
            noReagent = true,
            reason = "construct",
        },
        starting_gear = {},
    },

    ----------------------------------------------------------------------------
    -- SORCEROUS MINIONS
    ----------------------------------------------------------------------------

    bloodybones = {
        name = "Bloodybones",
        attributes = {
            swords    = 0,
            pentacles = 0,
            cups      = 0,
            wands     = 0,
        },
        health = 999999,
        defense = 0,
        infiniteHealth = true,
        neverTakesWounds = true,
        baseMorale = 14,
        rank = "minion",
        tags = { "sorcerous", "minion", "ooze", "bloodybones", "invulnerable", "magic_sensitive" },
        aiTags = { "sorcerous", "bloodybones", "invulnerable", "smell_magic", "unthinking" },
        social = {
            likes = {
                "screams_of_pain",
                "eating_nerve_clusters",
                "uranium_deposits",
            },
            hates = {
                "music",
                "childrens_laughter",
            },
            languages = {
                speechless = true,
                cannotSpeak = true,
            },
        },
        notes = {
            oozeSkeleton = "A speechless, unthinking ooze shaped like a skeleton; it is not undead.",
            immuneToDamage = "Invulnerable to every type of harm, has effectively infinite Health, and never takes a Wound.",
            practicalWeakness = "Weakness is procedural: it can be trapped, pushed into hazards, or simply walked away from.",
            smellMagic = "Can smell magical effects and identify sorcerers by scent.",
        },
        bloodybones = {
            sorcerousMinion = true,
            oozeShapedLikeSkeleton = true,
            notUndead = true,
            speechless = true,
            unthinking = true,
            invulnerable = {
                immuneToAllHarm = true,
                infiniteHealth = true,
                neverTakesWounds = true,
                canBeTrapped = true,
                canBePushedIntoPits = true,
                canBeAvoided = true,
            },
            smellMagic = {
                smellsMagicalEffects = true,
                identifiesSorcerersByScent = true,
            },
        },
        lesserDooms = {},
        greaterDooms = {},
        alchemy = {
            noReagent = true,
            reason = "not_appendix_b_source",
        },
        starting_gear = {},
    },

    ----------------------------------------------------------------------------
    -- SORCEROUS CONSTRUCTS
    ----------------------------------------------------------------------------

    mimic = {
        name = "Mimic",
        attributes = {
            swords    = 4,
            pentacles = 0,
            cups      = 1,
            wands     = 1,
        },
        health = 2,
        defense = 6,
        baseMorale = 14,
        construct = true,
        tags = { "sorcerous", "construct", "mimic" },
        aiTags = { "construct", "mimic", "camouflaged" },
        social = {
            likes = { "sleeping" },
            hates = { "itself" },
        },
        notes = {
            construct = "Treats Notches as 2 Wounds.",
            tough = "Actions that target mimics must exceed, not just match, their Initiative.",
            camouflage = "At rest, looks exactly like a normal object.",
        },
        mimic = {
            camouflagedAsObject = true,
            treatsNotchesAsWounds = 2,
            mustExceedInitiative = true,
            ambushTest = {
                attribute = "cups",
                failure = "piercing_wound",
            },
        },
        greaterDooms = {
            {
                id = "harden",
                name = "Harden",
                description = "Discard a greater doom card to become immune to the last weapon type that Wounded the mimic.",
                effect = {
                    type = "mimic_harden_weapon_immunity",
                    countsTowardTurnCard = false,
                },
            },
            {
                id = "riot_of_teeth",
                name = "Riot of Teeth",
                description = "Discard a greater doom card when the mimic Attacks; on success, the Attack deals Piercing damage.",
                effect = {
                    type = "attack_piercing",
                },
            },
        },
        alchemy = {
            reagentTemplateId = "mimic_reagent",
            yield = 1,
        },
        starting_gear = {},
    },

    ----------------------------------------------------------------------------
    -- BRAIN SPIDERS (Tomb of Golden Ghosts)
    -- S10.4: Content expansion enemies
    ----------------------------------------------------------------------------

    brain_spider = {
        name = "Brain Spider",
        attributes = {
            swords    = 1,
            pentacles = 4,
            cups      = 2,
            wands     = 3,
        },
        health = 3,
        defense = 3,
        baseMorale = 14,
        rank = "strategist",
        tags = { "sorcerous", "strategist", "arachnid", "brain_spider", "telepathic" },
        aiTags = { "sorcerous", "brain_spider", "strategist", "leaper", "wall_crawler", "webber" },
        social = {
            likes = {
                "eating_brains",
                "puzzles_and_riddles",
            },
            hates = {
                "paladins",
                "feeling_stupid",
            },
            languages = {
                telepathic = true,
                communicatesWithAnyLanguage = true,
            },
        },
        notes = {
            squishy = "Immune to bludgeoning and smashing weapons, such as hammers and maces.",
            telepathic = "Speaks telepathically and can communicate with anyone regardless of language.",
        },
        brainSpider = {
            squishy = {
                immuneToBludgeoning = true,
                immuneToSmashing = true,
                examples = { "hammers", "maces" },
            },
            telepathic = {
                speaksTelepathically = true,
                communicatesRegardlessOfLanguage = true,
            },
            greatLeap = {
                dashJumpZones = 2,
                clearsInterveningObstacles = true,
            },
            wallCrawling = {
                effortlessClimb = true,
                moveOntoWallCanAvoidAndLeave = true,
            },
            web = {
                replacesAttackDamage = true,
                targetRootedUntilAllLimbsFreed = true,
                recoverFreesOneLimbAtATime = true,
            },
        },
        alchemy = {
            reagentTemplateId = "brain_spider_reagent",
            yield = 1,
        },
        starting_gear = {},
        lesserDooms = {
            {
                id = "great_leap",
                name = "Great Leap",
                description = "The brain spider can jump 2 zones when Dashing, clearing intervening obstacles such as pits, hazardous terrain, or blocking adventurers.",
                effect = {
                    type = "dash_jump",
                    moveZones = 2,
                    clearsInterveningObstacles = true,
                },
            },
            {
                id = "wall_crawling",
                name = "Wall Crawling",
                description = "The brain spider can effortlessly climb walls; moving onto a wall can let it avoid adventurers and leave the area unless they can keep up.",
                effect = {
                    type = "wall_crawl",
                    avoidsAdventurers = true,
                    canLeaveArea = true,
                },
            },
        },
        greaterDooms = {
            {
                id = "tactics",
                name = "Tactics",
                description = "Discard a greater doom card to turn a standard Challenge Action into an interrupt.",
                effect = {
                    type = "standard_action_as_interrupt",
                },
            },
            {
                id = "web",
                name = "Web",
                activation = "attack_rider",
                description = "When the brain spider Attacks, discard a greater doom to wrap the target in webs instead of dealing damage. The target is Rooted until each limb is freed with Recover.",
                effect = {
                    type = "web",
                    limbs = 4,
                    suppressDamage = true,
                    rootUntilAllLimbsFreed = true,
                    recoverFreesOneLimb = true,
                },
            },
        },
    },

    puppet_mummy = {
        name = "Puppet-Mummy",
        attributes = {
            swords    = 4,
            pentacles = 2,
            cups      = 1,
            wands     = 1,
        },
        -- HD: 2/0 - Dried corpses, no armor but must be hacked apart
        health = 2,
        defense = 0,
        instantDestruction = true,  -- Undead puppet, just stops moving
        baseMorale = 20,  -- S12.3: Mindless undead, controlled by their master
        starting_gear = {
            hands = {
                { name = "Corroded Khopesh", size = 1, durability = 1 },
            },
        },
    },

    giant_centipede = {
        name = "Giant Centipede",
        attributes = {
            swords    = 3,
            pentacles = 5,
            cups      = 1,
            wands     = 2,
        },
        -- HD: 2/2 - Hard carapace, segmented body
        health = 2,
        defense = 2,  -- Hard chitinous shell
        baseMorale = 12,  -- S12.3: Instinctive beast, will flee if badly hurt
        starting_gear = {},  -- Venomous mandibles
    },

    -- BOSS: Glaura Glossolalia, the Brain Spider Queen
    -- S10.4: Enemy with a "Greater Doom" (Major Arcana)
    brain_spider_queen = {
        name = "Glaura Glossolalia",
        attributes = {
            swords    = 4,
            pentacles = 5,
            cups      = 6,  -- Master psychic
            wands     = 6,  -- Powerful caster
        },
        -- HD: 5/4 - Boss-level durability with reinforced carapace
        health = 5,
        defense = 4,  -- Reinforced psychic carapace
        baseMorale = 18,  -- S12.3: Cunning boss, will use every trick before fleeing
        tags = { "monster", "arachnid", "brain_spider", "boss" },
        alchemy = {
            reagentTemplateId = "brain_spider_reagent",
            yield = 1,
        },
        starting_gear = {},

        -- Greater Doom: A devastating special ability
        greaterDoom = {
            name = "Star-Child's Scream",
            description = "Glaura channels the psychic power of the sleeping star-child. All adventurers must test Cups vs 14 or become Stressed and take 1 Wound.",
            trigger = "on_staggered",  -- Triggers when first staggered
            effect = {
                type = "group_test",
                attribute = "cups",
                difficulty = 14,
                onFailure = { condition = "stressed", damage = 1 },
            },
        },

        -- Boss-specific AI behaviors
        aiTags = { "boss", "psychic", "summons_minions" },
    },

    slime = {
        name = "Slime",
        attributes = {
            swords    = 6,
            pentacles = 6,
            cups      = 0,
            wands     = 0,
        },
        health = 6,
        defense = 0,
        baseMorale = 20,
        tags = { "sorcerous", "elite", "ooze", "slime" },
        aiTags = { "ooze", "slime", "mindless", "engulfer" },
        social = {
            likes = {
                "warmth",
                "movement",
                "dead_corpses_it_can_crush_and_digest",
            },
            hates = {
                "elephants",
                "salt",
                "fire",
            },
        },
        notes = {
            acidic = "Weapons that damage a slime are automatically Notched.",
            impermeableMembrane = "Immune to slashing and crushing weapons; takes damage normally from sharp piercing attacks.",
            saltReactive = "Salt in hand can be thrown as an Attack that inflicts 2 Wounds on success.",
            shapelessBody = "Immune to being Displaced, Rooted, or Tripped.",
        },
        slime = {
            dynamicSwordsPentaclesFromHealth = true,
            acidicNotchesDamagingWeapons = true,
            immuneWeaponTypes = { "slashing", "crushing" },
            saltAttackWounds = 2,
            canPassKeyholeSpaces = true,
            immuneToDisplaced = true,
            immuneToRooted = true,
            immuneToTripped = true,
        },
        lesserDooms = {
            {
                id = "protoplasmic_attack",
                name = "Protoplasmic Attack",
                description = "On a successful Roughhouse, the target is engulfed, Rooted, moves with the slime, takes 1 Wound at turn start, and belt/worn gear are Notched.",
                effect = {
                    type = "engulf",
                    rooted = true,
                    turnStartWounds = 1,
                    notchWornAndBeltGear = true,
                    escapeTest = "swords",
                },
            },
        },
        greaterDooms = {
            {
                id = "grind",
                name = "Grind",
                description = "Discard a greater doom card to automatically deal 1 Wound to all creatures currently engulfed; this does not count toward the one-card-per-turn limit.",
                effect = {
                    type = "wound_engulfed_targets",
                    wounds = 1,
                },
            },
            {
                id = "regenerate",
                name = "Regenerate",
                description = "Discard a greater doom card to Heal the slime unless salt has been spread on it this turn; this does not count toward the one-card-per-turn limit.",
                effect = {
                    type = "heal_self",
                    blockedBySaltThisTurn = true,
                },
            },
        },
        alchemy = {
            reagentTemplateId = "slime_reagent",
            yield = 1,
        },
        starting_gear = {},
    },

    small_ooze = {
        name = "Small Ooze",
        attributes = {
            swords    = 2,
            pentacles = 1,
            cups      = 0,
            wands     = 2,
        },
        health = 2,
        defense = 1,
        baseMorale = 20,
        tags = { "monster", "ooze", "slime" },
        aiTags = { "ooze", "mindless" },
        alchemy = {
            reagentTemplateId = "slime_reagent",
            yield = 1,
        },
        starting_gear = {},
    },

    titan_sporehulk = {
        name = "Titan, The Sporehulk Rune",
        attributes = {
            swords    = 7,
            pentacles = 3,
            cups      = 3,
            wands     = 3,
        },
        -- The Torso is the death section; other section HD lives in titan.sections.
        health = 5,
        defense = 10,
        baseMorale = 20,
        rank = "dungeon_lord",
        size = "huge",
        tags = { "elemental", "dungeon_lord", "titan", "sporehulk", "multi_section" },
        aiTags = { "dungeon_lord", "titan", "sporehulk", "multi_section", "battlefield_body" },
        social = {
            likes = {
                "flowers",
                "small_woodland_mammals",
            },
            hates = {
                "crowds",
                "public_places",
                "open_areas",
                "disturbing_the_tombs",
            },
            languages = {
                understands = { "tylwyth" },
                cannotSpeak = true,
            },
        },
        notes = {
            gentleGuardian = "Gentle unless someone disturbs the sepulchers it guards.",
            cannotSpeak = "The Sporehulk has no mouth but understands Tylwyth.",
            battlefieldBody = "Its body is a battlefield split into section-zones that are antagonists in their own right.",
        },
        titan = {
            singleInitiativeForAllSections = true,
            battlefieldBody = true,
            sectionOrder = { "legs", "left_arm", "right_arm", "torso" },
            runeOfProtection = {
                section = "torso",
                onBack = true,
                damageImmuneUntilDestroyed = true,
                successfulAttackDealsTorsoWound = 1,
                meleeRequiresClimbingTorso = true,
                missileAllowedFromGroundIfVisible = true,
            },
            climb = {
                action = "dash",
                sectionsPerDash = 1,
                groundMeleeTargets = { "legs" },
                afterLegsDefeatedGroundMeleeTargets = { "legs", "left_arm", "right_arm", "torso" },
                meleeTargetsCurrentClimbedSection = true,
            },
            sections = {
                legs = {
                    name = "Legs",
                    health = 4,
                    defense = 0,
                    zone = true,
                    defeatedCrumplesSporehulk = true,
                    armsAndTorsoMeleeTargetableWhenDefeated = true,
                    crawlingMoveAllowedIfArmsIntact = true,
                    dashBlockedWhenDefeated = true,
                    lesserDooms = { "kick" },
                    greaterDooms = { "rampage" },
                },
                left_arm = {
                    name = "Left Arm",
                    health = 5,
                    defense = 0,
                    zone = true,
                    holdCapacity = 2,
                    lesserDooms = { "grab", "throw_stones" },
                    greaterDooms = { "smash", "squeeze" },
                },
                right_arm = {
                    name = "Right Arm",
                    health = 5,
                    defense = 0,
                    zone = true,
                    holdCapacity = 2,
                    lesserDooms = { "grab", "throw_stones" },
                    greaterDooms = { "smash", "squeeze" },
                },
                torso = {
                    name = "Torso",
                    health = 5,
                    defense = 10,
                    zone = true,
                    deathSection = true,
                    notes = {
                        toughMustExceedInitiative = true,
                    },
                    lesserDooms = { "shake" },
                    greaterDooms = {},
                },
            },
        },
        lesserDooms = {
            {
                id = "kick",
                name = "Kick",
                section = "legs",
                description = "The Sporehulk makes an Attack that targets all adventurers in its zone.",
                effect = {
                    type = "attack_all_in_zone",
                },
            },
            {
                id = "grab",
                name = "Grab",
                section = "arm",
                description = "The Sporehulk Roughhouses to grab a foe; grabbed foes are Rooted, move with it, and can be squeezed.",
                effect = {
                    type = "roughhouse_grab",
                    rooted = true,
                    movesWithSource = true,
                    holdCapacity = 2,
                    missedAttacksHitGrabbedFoe = true,
                },
            },
            {
                id = "throw_stones",
                name = "Throw Stones",
                section = "arm",
                description = "The Sporehulk Attacks by throwing heavy things such as armor, stones, or held foes.",
                effect = {
                    type = "throw_heavy_object",
                    grabbedTargetTakesAutomaticWound = true,
                },
            },
            {
                id = "shake",
                name = "Shake",
                section = "torso",
                description = "The Sporehulk Roughhouses all adventurers climbing him; a hit drops them, Trips them, and deals Piercing damage.",
                effect = {
                    type = "roughhouse_climbers",
                    fallToGround = true,
                    condition = "tripped",
                    damageType = "piercing",
                },
            },
        },
        greaterDooms = {
            {
                id = "rampage",
                name = "Rampage",
                section = "legs",
                description = "The Sporehulk can play a greater doom as his Initiative.",
                effect = {
                    type = "greater_doom_as_initiative",
                },
            },
            {
                id = "smash",
                name = "Smash",
                section = "arm",
                description = "The Sporehulk can play a greater doom as an Attack action.",
                effect = {
                    type = "greater_doom_attack_action",
                },
            },
            {
                id = "squeeze",
                name = "Squeeze",
                section = "arm",
                description = "Play a greater doom card to squeeze all grabbed adventurers, automatically dealing them a Wound.",
                effect = {
                    type = "wound_grabbed_targets",
                    wounds = 1,
                },
            },
        },
        alchemy = {
            reagentTemplateId = "titan_reagent",
            yield = 1,
        },
        starting_gear = {},
    },

    ungoat = {
        name = "Ungoat",
        attributes = {
            swords    = 0,
            pentacles = 0,
            cups      = 0,
            wands     = 0,
        },
        health = 2,
        defense = 0,
        baseMorale = 8,
        rank = "minion",
        tags = { "sorcerous", "minion", "ooze_kin", "ungoat" },
        aiTags = { "sorcerous", "ungoat", "magic_scavenger", "rummager", "poor_defense" },
        social = {
            likes = {
                "eating_spell_reagents",
                "opening_packs",
                "spilling_things",
            },
            hates = {
                "enclosures",
                "smell_of_lavender",
                "loud_sounds",
            },
        },
        notes = {
            magicScavenger = "Tries to get into packs and eat spell reagents, archwood wands, and other sorcerous implements.",
            maleficentRetribution = "Direct Wounds make the attacker draw from a random maleficence table.",
            saltReactive = "Salt thrown from hand is an Attack that inflicts 2 Wounds on success.",
            smellMagic = "Can smell magical effects and identify sorcerers by scent.",
        },
        ungoat = {
            relatedToOoze = true,
            bleatsPiteouslyIfAttacked = true,
            poorSelfDefense = true,
            alwaysEscapesEnclosures = true,
            magicDietTargets = {
                "spell_reagents",
                "archwood_wands",
                "sorcerous_implements",
            },
            maleficentRetribution = {
                directWoundsTriggerRandomMaleficence = true,
                saltDoesNotTrigger = true,
                nonDirectAttacksDoNotTrigger = true,
            },
            saltReactive = {
                attackWithSaltInHand = true,
                successWounds = 2,
            },
            smellMagic = {
                canSmellMagicalEffects = true,
                identifiesSorcerersByScent = true,
            },
            rummage = {
                roughhousePullsItemFromBackpack = true,
                itemDroppedToGround = true,
                adventurersRecoverDroppedItems = true,
                canPickUpDroppedItemsWithAnyCard = true,
            },
        },
        lesserDooms = {
            {
                id = "rummage",
                name = "Rummage",
                description = "When the ungoat Roughhouses, it can pull an item out of the target's backpack and drop it to the ground.",
                effect = {
                    type = "pull_item_from_backpack",
                    droppedToGround = true,
                    recoverable = true,
                    ungoatCanPickUpWithAnyCard = true,
                },
            },
        },
        alchemy = {
            reagentTemplateId = "ungoat_reagent",
            yield = 1,
        },
        starting_gear = {},
    },

    vampire = {
        name = "Vampire",
        attributes = {
            swords    = 4,
            pentacles = 4,
            cups      = 4,
            wands     = 4,
        },
        health = 7,
        defense = 2,
        baseMorale = 18,
        rank = "elite",
        undead = true,
        tags = { "undead", "elite", "vampire", "predator" },
        aiTags = { "undead", "vampire", "elite", "predator", "mesmerist" },
        social = {
            likes = {
                "blood",
                "virgin_blood",
                "giving_long_soliloquies",
                "playing_with_its_food",
                "nocturnal_predators",
                "counting_things",
            },
            hates = {
                "sunlight",
                "fresh_herbs",
                "running_water",
                "religious_iconography",
            },
        },
        notes = {
            breathlessAndAgeless = "Does not age or breathe, but still sleeps and can be poisoned.",
            feed = "If an Attack Wounds a condition or talent, the vampire can discard any card to feed and Heal.",
            invulnerable = "Ignores damage except from silver weapons, magic, and fire unless negated by wholesome herbs or sunlight.",
            finalDeath = "If slain, rises the following night unless the corpse is ritually desecrated.",
        },
        vampire = {
            breathless = true,
            ageless = true,
            sleeps = true,
            poisonable = true,
            feed = {
                attackWoundsConditionOrTalent = true,
                excludesArmorOrShieldNotches = true,
                discardAnyCardToHeal = true,
            },
            invulnerable = {
                ignoresDamageExcept = {
                    "silver_weapons",
                    "magic",
                    "fire",
                },
                negatedBy = {
                    "wholesome_herbs",
                    "garlic",
                    "sunlight",
                },
            },
            finalDeath = {
                risesFollowingNightUnlessDesecrated = true,
                trueRumorsChosenByGM = 4,
                loreBidRevealsOneRumor = true,
                rumors = {
                    "drive_wooden_stake_through_heart",
                    "decapitate",
                    "decapitate_with_silver_weapon",
                    "burn_decapitated_head",
                    "stuff_mouth_with_garlic",
                    "stuff_mouth_with_holy_testaments_of_mythrys",
                    "bury_in_wild_rose_petals",
                    "cover_body_with_salt",
                    "say_prayers_to_mythrys_over_body",
                },
            },
        },
        lesserDooms = {
            {
                id = "call_bats",
                name = "Call Bats",
                description = "Play a lesser doom card to summon a cloud of bats; the card is the bats' Initiative, and active bats add +2 GM Challenge cards each round.",
                effect = {
                    type = "summon_bat_cloud",
                    initiativeFromDoomCard = true,
                    summonedStats = {
                        tags = { "beast", "minion", "bats" },
                        health = 2,
                        defense = 0,
                    },
                    gmChallengeCardsBonus = 2,
                },
            },
            {
                id = "supernatural_grace",
                name = "Supernatural Grace",
                description = "The vampire may have any number of Dodge cards facedown and chooses which one counters each Attack, but still uses only one card per Attack.",
                effect = {
                    type = "unlimited_facedown_dodge",
                    oneDodgePerAttack = true,
                    oneCardPerTurnStillApplies = true,
                },
            },
            {
                id = "supernatural_speed",
                name = "Supernatural Speed",
                description = "Discard any number of lesser doom cards to Move 1 zone per card; this does not count toward the one-card-per-turn limit.",
                effect = {
                    type = "move_per_lesser_doom",
                    zonesPerCard = 1,
                    countsTowardTurnCard = false,
                },
            },
        },
        greaterDooms = {
            {
                id = "bat_form",
                name = "Bat Form",
                description = "Play a greater doom card to become a monstrous bat; while in this form, the vampire can fly 1 zone as a Move action.",
                effect = {
                    type = "bat_form",
                    flyMoveZones = 1,
                },
            },
            {
                id = "mesmerize",
                name = "Mesmerize",
                description = "When the vampire Attacks, discard a greater doom to Control a target looking in its eyes instead of dealing damage.",
                effect = {
                    type = "mesmerize_on_attack",
                    requiresEyeContact = true,
                    avoidGazeCausesDisfavor = true,
                    commandedActionUsesAttackValue = true,
                },
            },
            {
                id = "mist_form",
                name = "Mist Form",
                description = "Play a greater doom card to become intangible mist; physical objects pass harmlessly through the vampire.",
                effect = {
                    type = "mist_form",
                    intangible = true,
                    physicalObjectsPassThrough = true,
                },
            },
        },
        alchemy = {
            reagentTemplateId = "vampire_reagent",
            yield = 1,
        },
        starting_gear = {},
    },

    wraith = {
        name = "Wraith",
        attributes = {
            swords    = 4,
            pentacles = 1,
            cups      = 2,
            wands     = 3,
        },
        health = 4,
        defense = 0,
        instantDestruction = true,
        baseMorale = 20,
        rank = "strategist",
        undead = true,
        tags = { "undead", "strategist", "wraith", "spirit", "intangible", "spectral" },
        aiTags = { "undead", "wraith", "spirit", "intangible", "light_averse", "xp_drain" },
        social = {
            likes = {
                "sympathy",
                "cataloging_its_agonies",
            },
            hates = {
                "its_continuous_existence",
                "bright_light",
            },
        },
        notes = {
            shadowForm = "Naturally intangible; physical objects pass harmlessly through it unless it chooses to interact.",
            brightLightTangible = "Bright light makes a wraith tangible.",
            torchOrLanternAction = "An adventurer with a torch or lantern can spend any card to shine light on the wraith, making it tangible to everyone until round end.",
            spectral = "Immune to biology and mental-control effects, and cannot see illusions.",
            noReagent = "A wraith has no guts and yields no reagent.",
        },
        wraith = {
            shadowForm = {
                naturallyIntangible = true,
                physicalObjectsPassThrough = true,
                canChooseToInteractPhysically = true,
                tangibleInBrightLight = true,
                torchOrLanternMiscActionMakesTangible = true,
                tangibleUntilRoundEnd = true,
            },
            spectral = {
                nonPhysical = true,
                biologyEffectImmune = true,
                mentalControlImmune = true,
                cannotSeeIllusions = true,
            },
            lightAvoidance = true,
            xpDrain = {
                restoredIfWraithDestroyed = true,
            },
        },
        lesserDooms = {
            {
                id = "fear",
                name = "Fear",
                description = "Play a lesser doom and compare it to each same-zone character's Initiative; if used on the wraith's turn, add Wands. Beaten adventurers are Displaced to an adjacent zone of the player's choice.",
                effect = {
                    type = "same_zone_fear_displace",
                    compareTo = "initiative",
                    sameZone = true,
                    addWandsOnOwnTurn = true,
                    displacedByPlayerChoice = true,
                },
            },
            {
                id = "retreat_into_the_shadows",
                name = "Retreat Into the Shadows",
                description = "Discard any card to automatically disengage from all adventurers; this does not count toward the one-card-per-turn limit.",
                effect = {
                    type = "disengage_all",
                    costsAnyCard = true,
                    countsTowardTurnCard = false,
                },
            },
        },
        greaterDooms = {
            {
                id = "dolorous_kiss",
                name = "Dolorous Kiss",
                description = "When the wraith Attacks, discard a greater doom to drain life energy; on success, the adventurer loses 1 XP in addition to a Wound. This XP is restored if the wraith is destroyed.",
                effect = {
                    type = "attack_xp_drain",
                    xpLost = 1,
                    woundAlsoApplies = true,
                    xpRestoredIfDestroyed = true,
                },
            },
        },
        alchemy = {
            noReagent = true,
            reason = "no_guts",
        },
        starting_gear = {},
    },

    winter_wolf = {
        name = "Winter Wolf",
        attributes = {
            swords    = 0,
            pentacles = 0,
            cups      = 0,
            wands     = 0,
        },
        health = 4,
        defense = 0,
        baseMorale = 14,
        rank = "minion",
        tags = { "elemental", "minion", "winter_wolf", "wolf", "ice" },
        aiTags = { "elemental", "winter_wolf", "pack", "ice", "fire_vulnerable" },
        social = {
            likes = {
                "its_pack",
                "its_cubs",
                "stormblooded_orcs",
            },
            hates = {
                "heat_and_fire",
                "salamanders",
            },
            languages = {
                speaksSimple = { "tylwyth" },
            },
        },
        notes = {
            auraOfIce = "Anyone who begins their turn engaged with a winter wolf is automatically Rooted.",
            vulnerableToFire = "Fire damage deals 2 Wounds; a torch or lantern can be used this way but is Destroyed.",
            elementalTravel = "Can walk on water and treat clouds, vapors, and mists as solid.",
        },
        winterWolf = {
            body = {
                howlingWindsConstrainedByLivingIce = true,
                wolfShape = true,
            },
            packAnimal = true,
            lowAnimalisticIntelligence = true,
            speaksSimpleTylwyth = true,
            auraOfIce = {
                rootEngagedAtTurnStart = true,
            },
            vulnerableToFire = {
                fireDamageWounds = 2,
                torchOrLanternCanDealFireDamage = true,
                torchOrLanternDestroyedOnUse = true,
            },
            elementalTravel = {
                walksOnWater = true,
                freezesWaterUnderPaws = true,
                treatsCloudsAsSolid = true,
                treatsVaporsAsSolid = true,
                treatsMistsAsSolid = true,
            },
        },
        greaterDooms = {
            {
                id = "breath_of_ice",
                name = "Breath of Ice",
                description = "When the winter wolf Attacks, discard a greater doom to breathe ice against all adventurers in its zone; on success, deal a Wound and Destroy all liquid belt items.",
                effect = {
                    type = "zone_ice_attack",
                    sameZone = true,
                    wounds = 1,
                    destroyLiquidBeltItems = true,
                    liquidItems = { "potions", "hermetic_bottles" },
                },
            },
        },
        alchemy = {
            reagentTemplateId = "winter_wolf_reagent",
            yield = 1,
        },
        starting_gear = {},
    },

    devil = {
        name = "Devil, Gluttony",
        attributes = {
            swords    = 1,
            pentacles = 5,
            cups      = 2,
            wands     = 3,
        },
        health = 3,
        defense = 0,
        baseMorale = 18,
        rank = "strategist",
        tags = { "spirit", "strategist", "devil", "gluttony", "wastes" },
        aiTags = { "spirit", "devil", "gluttony", "contract", "bite", "swallow", "stinking_cloud" },
        social = {
            likes = {
                "making_contracts",
                "eating_people",
                "turning_people_into_cannibals",
            },
            hates = {
                "vegans",
                "clean_water",
            },
            languages = {
                contracts = { "archaic_vetus" },
                loremasterReadableContract = true,
            },
        },
        notes = {
            deadlySinExample = "Gluttony is the example devil; other devils can be made by varying this template.",
            contract = "Offers a lifetime of desired food in exchange for permission to devour the adventurer after death.",
            endlessGullet = "Cannot be poisoned and is immune to seablooded orc Poison Blood.",
            untouchedByHotIron = "Immune to crafted or forged weapons, but vulnerable to natural dangers and improvised natural weapons.",
        },
        devil = {
            type = "gluttony",
            deadlySinsTemplate = true,
            contract = {
                offersDesiredFoodForLife = true,
                claimsBodyAfterDeath = true,
                contractMaterial = "hogskin",
                writtenInFilth = true,
                language = "archaic_vetus",
                onlyLoremastersReadProperly = true,
                loopholes = {
                    mustEatAllDevilBroughtFood = true,
                    cannotGiveAwayDevilBroughtFood = true,
                    devouredCannotReturnFromDeathsDoor = true,
                },
            },
            endlessGullet = {
                poisonImmune = true,
                poisonBloodImmune = true,
            },
            untouchedByHotIron = {
                immuneToCraftedWeapons = true,
                immuneToForgedWeapons = true,
                vulnerableToNaturalDangers = {
                    "fire",
                    "falls",
                    "drowning",
                },
                vulnerableToImprovisedNaturalWeapons = {
                    "branch",
                    "stone",
                },
            },
            bite = {
                action = "roughhouse",
                targetRooted = true,
                targetMovesWithDevil = true,
                maxBittenTargets = 4,
                enablesSwallow = true,
                missedAttacksHitBittenTarget = true,
            },
            stinkingCloud = {
                spellId = "stinking_cloud",
                sameZoneOrOneZoneAway = true,
                otherCreaturesBeginRoundStunned = true,
                otherCreaturesDrawOneFewerCard = true,
            },
            swallow = {
                requiresBittenTarget = true,
                extradimensionalHolding = true,
                defeatingDevilReleasesSwallowed = true,
                testFate = {
                    attribute = "swords",
                    successesToEscape = 3,
                    failuresToAnnihilation = 3,
                },
            },
        },
        lesserDooms = {
            {
                id = "bite",
                name = "Bite",
                description = "The devil can Roughhouse to bite a foe; while bitten, the target is Rooted, moves with the devil, can be swallowed, and missed Attacks against the devil hit a bitten foe instead.",
                effect = {
                    type = "roughhouse_bite_hold",
                    targetRooted = true,
                    targetMovesWithActor = true,
                    maxHeldTargets = 4,
                    enablesSwallow = true,
                    missedAttacksHitHeldTarget = true,
                },
            },
        },
        greaterDooms = {
            {
                id = "fiendish_retreat",
                name = "Fiendish Retreat",
                description = "Discard a greater doom to automatically disengage from an adventurer; this does not count toward the one-card-per-turn limit.",
                effect = {
                    type = "disengage_one",
                    countsTowardTurnCard = false,
                },
            },
            {
                id = "stinking_cloud",
                name = "Stinking Cloud",
                description = "Play a greater doom to create Stinking Cloud in the devil's zone or one zone away; other creatures beginning the round in the cloud are Stunned and draw 1 fewer card.",
                effect = {
                    type = "cast_spell_like_effect",
                    spellId = "stinking_cloud",
                    zoneRange = 1,
                    excludeSelf = true,
                    beginRoundCondition = "stunned",
                    drawPenalty = 1,
                },
            },
            {
                id = "swallow",
                name = "Swallow",
                description = "If holding someone in its mouth, play a greater doom to swallow them into an extradimensional space; three Swords Test Fate successes make the devil vomit them up, while three failures annihilate them.",
                effect = {
                    type = "swallow_held_target",
                    requiresHeldTarget = true,
                    extradimensionalHolding = true,
                    escapeTest = {
                        action = "test_fate",
                        attribute = "swords",
                        successesToEscape = 3,
                        failuresToAnnihilation = 3,
                    },
                },
            },
        },
        alchemy = {
            reagentTemplateId = "devil_reagent",
            yield = 1,
        },
        starting_gear = {},
    },

    jinn = {
        name = "Jinn",
        attributes = {
            swords    = 4,
            pentacles = 4,
            cups      = 4,
            wands     = 4,
        },
        health = 7,
        defense = 0,
        baseMorale = 20,
        rank = "elite",
        tags = { "spirit", "elite", "jinn", "weird" },
        aiTags = { "spirit", "jinn", "elite", "second_sight", "shrouded" },
        social = {
            likes = {
                "flattery",
                "drugs",
                "rare_books",
                "human_dreams",
            },
            hates = {
                "iron",
                "rudeness",
                "violence",
            },
            languages = {
                speaks = { "tylwyth" },
            },
        },
        notes = {
            secondSight = "Can see Shrouded creatures and instantly identify magical effects.",
            nicheWisdom = "Embodies one concept, emotion, or science and gives excellent advice about that subject when pleased.",
        },
        jinn = {
            secondSight = {
                seesShrouded = true,
                identifiesMagicalEffects = true,
            },
            nicheWisdom = {
                subjectChosenByGM = true,
            },
            bodyOfSmokelessFire = {
                canBecomeTangibleOrIntangible = true,
                physicalObjectsPassThroughWhileIntangible = true,
                countsTowardTurnCard = false,
            },
            invisible = {
                becomesShrouded = true,
                stillAndQuietCannotBeDeliberatelyTargeted = true,
                physicalInteractionEndsEffect = true,
            },
        },
        lesserDooms = {
            {
                id = "body_of_smokeless_fire",
                name = "Body of Smokeless Fire",
                description = "Discard any card to become tangible or intangible; while intangible, physical objects pass harmlessly through the jinn.",
                effect = {
                    type = "toggle_tangibility",
                    costsAnyCard = true,
                    countsTowardTurnCard = false,
                },
            },
            {
                id = "invisible",
                name = "Invisible",
                description = "Play any card to become Shrouded until the jinn interacts with the physical world.",
                effect = {
                    type = "become_shrouded",
                    costsAnyCard = true,
                    endsOnPhysicalInteraction = true,
                },
            },
        },
        greaterDooms = {
            {
                id = "possess",
                name = "Possess",
                description = "When the jinn Attacks, discard a greater doom to Control the target into an immediate commanded action instead of dealing damage.",
                effect = {
                    type = "attack_control_command",
                    replacesWound = true,
                    controlledActionValue = "attack_lesser_doom_value",
                },
            },
        },
        alchemy = {
            reagentTemplateId = "jinn_reagent",
            yield = 1,
        },
        starting_gear = {},
    },

    ----------------------------------------------------------------------------
    -- MALEFICENCE SPAWNS
    ----------------------------------------------------------------------------

    imp = {
        name = "Imp",
        attributes = {
            swords    = 0,
            pentacles = 0,
            cups      = 0,
            wands     = 0,
        },
        health = 2,
        defense = 0,
        baseMorale = 20,
        tags = { "spirit", "imp" },
        aiTags = { "imp", "spirit", "wimp", "lowest_initiative" },
        social = {
            likes = { "weird_stinks" },
            hates = { "iron", "cats", "clean_water" },
        },
        notes = {
            wimps = "Imps always play the lowest card for their Initiative.",
            desireByMinorDiscard = "The top minor discard sets what the imp wants.",
        },
        imp = {
            wimps = {
                alwaysLowestInitiative = true,
            },
            wantsByMinorSuit = {
                swords = "meat",
                pentacles = "shiniest_thing_then_deep_pit",
                cups = "pet",
                wands = "sorcerer_blood",
            },
            reproducesFromViolence = true,
            badLuckMachine = {
                interruptRetargetsAction = true,
                newTargetSameZone = true,
                actionGainsDisfavor = true,
            },
        },
        lesserDooms = {
            {
                id = "vomit",
                name = "Vomit",
                description = "A successful Attack can deal no damage and Notch one target item.",
            },
            {
                id = "piss_and_shit",
                name = "Piss and Shit",
                description = "A successful Roughhouse can also make the target Stressed.",
            },
        },
        greaterDooms = {
            {
                id = "bad_luck_machine",
                name = "Bad Luck Machine",
                description = "Discard a greater doom as an interrupt to retarget an action against the imp to another same-zone creature with disfavor.",
                effect = {
                    type = "interrupt_retarget_action",
                    newTargetSameZone = true,
                    appliesDisfavor = true,
                },
            },
        },
        alchemy = {
            reagentTemplateId = "imp_reagent",
            yield = 1,
        },
        starting_gear = {},
    },

    hekatephage = {
        name = "Hekatephage",
        attributes = {
            swords    = 0,
            pentacles = 4,
            cups      = 0,
            wands     = 6,
        },
        health = 4,
        defense = 0,
        baseMorale = 20,
        instantDestruction = true,
        tags = { "spirit", "shrouded", "intangible", "magic_eater" },
        aiTags = { "spirit", "shrouded", "intangible", "magic_eater" },
        starting_gear = {},
    },

    stone_twin = {
        name = "Stone Twin",
        attributes = {
            swords    = 4,
            pentacles = 4,
            cups      = 0,
            wands     = 0,
        },
        health = 4,
        defense = 4,
        baseMorale = 20,
        instantDestruction = true,
        construct = true,
        automaton = true,
        tags = { "construct", "stone", "twin" },
        aiTags = { "construct", "stone_twin", "assassin" },
        starting_gear = {},
    },

    ----------------------------------------------------------------------------
    -- S12.8: SOCIAL ENCOUNTER NPCs
    -- These entities are designed for non-combat resolution
    ----------------------------------------------------------------------------

    tomb_guardian_spirit = {
        name = "Tomb Guardian Spirit",
        attributes = {
            swords    = 4,  -- Can fight if needed
            pentacles = 3,
            cups      = 5,  -- Strong will
            wands     = 6,  -- Perceptive and magical
        },
        -- HD: 4/2 - Spectral being, partially incorporeal
        health = 4,
        defense = 2,  -- Incorporeal nature provides some protection
        instantDestruction = true,  -- Spirit dissipates when defeated
        baseMorale = 16,  -- S12.3: Confident but not aggressive
        disposition = "trust",  -- S12.4: Open to parley initially

        -- S12.8: Social encounter data
        social = {
            likes = { "respect", "offerings", "knowledge_of_tomb" },
            dislikes = { "grave_robbing", "disrespect", "lies" },
            -- Dialogue hooks for different dispositions
            dialogue = {
                trust = "You carry yourself with respect. Speak your purpose here.",
                joy = "Ah, seekers of knowledge! The tomb welcomes those who honor the dead.",
                fear = "The guardian's form wavers and dims...",
                anger = "DEFILERS! You shall join the sleepers in eternal darkness!",
                sadness = "So many have come... so many have fallen... why do you disturb this place?",
                distaste = "More grave robbers. State your business quickly.",
                surprise = "You... you know the old words? Perhaps there is hope yet.",
            },
            -- Failure threshold before forced combat
            failureThreshold = 3,
            -- Rewards for successful social resolution
            trustReward = {
                description = "The guardian reveals a secret passage and blesses your journey.",
                items = { "guardian_blessing" },
                revealSecret = true,
            },
            fearReward = {
                description = "The guardian retreats into the walls, leaving the chamber accessible.",
            },
        },

        -- Greater Doom: Spectral Wail
        greaterDoom = {
            name = "Spectral Wail",
            description = "The guardian unleashes a terrifying scream that echoes through the tomb. All adventurers must test Cups vs 14 or gain the Frightened condition.",
            trigger = "on_combat_start",  -- Triggers when combat begins
            effect = {
                type = "group_test",
                attribute = "cups",
                difficulty = 14,
                onFailure = { condition = "frightened" },
            },
        },

        -- AI tags
        aiTags = { "spirit", "social_priority", "guardian" },
    },

}

return M
