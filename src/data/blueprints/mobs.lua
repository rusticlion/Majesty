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

    skeleton_brute = {
        name = "Skeleton Brute",
        attributes = {
            swords    = 6,
            pentacles = 1,
            cups      = 1,
            wands     = 4,
        },
        -- NPC HD System: health/defense (p. 125)
        health = 3,   -- Must be bashed apart
        defense = 0,  -- No armor, just bones
        instantDestruction = true,  -- Undead don't go to Death's Door, just fall apart
        baseMorale = 20,  -- S12.3: Undead feel no fear
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
                { name = "Heater Shield", size = 1, durability = 2 },
            },
            belt = {
                { name = "Plate Armor", size = 2, isArmor = true, durability = 3 },
            },
        },
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
        starting_gear = {},  -- Natural weapons (fangs and psychic attacks)
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
