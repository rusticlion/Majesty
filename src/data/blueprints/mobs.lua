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
            },
            {
                id = "riot_of_teeth",
                name = "Riot of Teeth",
                description = "Discard a greater doom card when the mimic Attacks; on success, the Attack deals Piercing damage.",
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
            swords    = 3,
            pentacles = 4,
            cups      = 3,
            wands     = 5,  -- Psychic powers
        },
        -- HD: 2/2 - Chitinous hide provides some defense
        health = 2,
        defense = 2,  -- Chitinous carapace
        baseMorale = 14,  -- S12.3: Cunning predators, will retreat if outmatched
        disposition = "surprise",  -- S12.4: Psychic predators assess before acting
        tags = { "monster", "arachnid", "brain_spider" },
        alchemy = {
            reagentTemplateId = "brain_spider_reagent",
            yield = 1,
        },
        starting_gear = {},  -- Natural weapons (fangs and psychic attacks)

        -- Appendix E: Web. When the brain spider Attacks, discard a greater
        -- doom card to web a target instead of dealing damage.
        greaterDooms = {
            {
                id = "web",
                name = "Web",
                activation = "attack_rider",
                description = "On a successful Attack, deal no damage but wrap the target in webs. The target is Rooted until all limbs are freed with Recover.",
                effect = {
                    type = "web",
                    limbs = 4,
                    suppressDamage = true,
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
