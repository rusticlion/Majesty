-- rooms.lua
-- Data-driven room blueprints for Majesty
-- Ticket T2_5: Room metadata with features, verbs, danger levels
--
-- IMPORTANT: This file should be 100% tables. No logic here!
-- Logic belongs in src/logic/room_manager.lua
--
-- Schema:
--   id: string - Unique identifier
--   name: string - Display name
--   base_description: string - Base room description text
--   features: table[] - Interactive objects in the room
--   verbs: table - Room-specific Meatgrinder activities
--   danger_level: number - Affects Meatgrinder draw weights (0-5)
--   meatgrinder_overrides: table - Custom Meatgrinder entries for this room

local M = {}

--------------------------------------------------------------------------------
-- FEATURE TYPES
-- Used to categorize interactive objects
--------------------------------------------------------------------------------
M.FEATURE_TYPES = {
    CONTAINER   = "container",    -- Chests, barrels, crates
    MECHANISM   = "mechanism",    -- Levers, buttons, pressure plates
    HAZARD      = "hazard",       -- Traps, dangerous terrain
    CREATURE    = "creature",     -- NPCs, monsters, beasts
    DECORATION  = "decoration",   -- Statues, paintings, furnishings
    LIGHT       = "light",        -- Torches, braziers, glowing things
    DOOR        = "door",         -- Special doors beyond basic connections
    EXPERIMENT  = "experiment",   -- Magical/alchemical apparatus
    TREASURE    = "treasure",     -- Valuable objects
    CORPSE      = "corpse",       -- Dead bodies (searchable)
}

--------------------------------------------------------------------------------
-- ROOM BLUEPRINTS
-- Each room template can be instantiated in a dungeon
--------------------------------------------------------------------------------

M.blueprints = {

    ----------------------------------------------------------------------------
    -- TUTORIAL DUNGEON ROOMS
    ----------------------------------------------------------------------------

    tutorial_main_hall = {
        name = "Main Hall",
        base_description = "A grand entrance hall with crumbling pillars. Dust motes dance in the pale light filtering through cracks above.",
        danger_level = 1,

        -- Combat zones (for tactical movement during challenges)
        zones = {
            { id = "entrance", name = "Entrance", description = "The main doorway and entry area." },
            { id = "center", name = "Center Hall", description = "The central portion of the hall, between the pillars." },
            { id = "far_end", name = "Far End", description = "The far end of the hall, near the exits." },
        },

        features = {
            {
                id = "ancient_brazier",
                type = "light",
                name = "Ancient Brazier",
                description = "A bronze brazier, cold and dark. Soot stains the ceiling above it.",
                state = "unlit",  -- Can be: unlit, lit, destroyed
                interactions = { "light", "examine", "search" },
            },
            {
                id = "crumbling_pillar",
                type = "decoration",
                name = "Crumbling Pillar",
                description = "One of several stone pillars. Deep cracks run through its surface.",
                state = "intact",  -- Can be: intact, damaged, collapsed
                interactions = { "examine", "climb", "push" },
            },
        },

        -- Room-specific activities for Meatgrinder flavor
        verbs = {
            curiosity = { "echoing", "crumbling", "watching" },
            travel_event = { "falling_debris", "unstable_floor" },
        },

        -- Custom Meatgrinder entries (overrides defaults)
        meatgrinder_overrides = {
            curiosity = {
                "Dust cascades from the ceiling as something shifts above.",
                "You hear footsteps echoing - but they don't match your own.",
                "One of the pillars groans ominously.",
            },
        },
    },

    tutorial_guard_room = {
        name = "Guard Room",
        base_description = "Rusted weapon racks line the walls. A skeleton slumps in the corner, still clutching a broken spear.",
        danger_level = 2,

        -- Combat zones
        zones = {
            { id = "doorway", name = "Doorway", description = "The narrow entry point." },
            { id = "weapon_area", name = "Weapon Racks", description = "Near the rusted weapon racks along the walls." },
        },

        features = {
            {
                id = "dead_guard",
                type = "corpse",
                name = "Skeletal Guard",
                description = "Long dead. The remains of leather armor hang loosely on yellowed bones.",
                state = "unsearched",  -- Can be: unsearched, searched, disturbed
                interactions = { "examine", "search", "disturb" },
                loot = { "rusty_key" },  -- Item IDs found when searched
            },
            {
                id = "weapon_rack",
                type = "container",
                name = "Weapon Rack",
                description = "Rusted blades and broken polearms. Mostly useless, but perhaps something remains.",
                state = "full",  -- Can be: full, searched, empty
                interactions = { "examine", "search", "take" },
            },
        },

        verbs = {
            curiosity = { "rattling", "rusting", "watching" },
            travel_event = { "weapon_falls", "disturbed_bones" },
        },

        meatgrinder_overrides = {
            curiosity = {
                "A weapon clatters to the floor - did it fall on its own?",
                "The skeleton's empty eye sockets seem to follow you.",
                "You smell old blood and rust.",
            },
            random_encounter = {
                blueprint_id = "skeleton_brute",
                count_range = { 1, 2 },  -- 1-2 skeletons
                description = "The bones begin to stir. The dead do not rest easy here.",
            },
        },
    },

    tutorial_treasure_room = {
        name = "Treasure Room",
        base_description = "Gold coins glitter in the torchlight. A heavy iron chest sits against the far wall.",
        danger_level = 3,

        -- Combat zones
        zones = {
            { id = "entry", name = "Entry", description = "The entrance to the treasure room." },
            { id = "chest_area", name = "Chest Area", description = "Near the heavy iron chest." },
            { id = "coin_piles", name = "Coin Piles", description = "Among the scattered coins." },
        },

        features = {
            {
                id = "iron_chest",
                type = "container",
                name = "Iron Chest",
                description = "Massive and ornate. The lock looks complicated.",
                state = "locked",  -- Can be: locked, unlocked, open, looted, destroyed
                interactions = { "examine", "unlock", "force", "trap_check" },
                lock = { difficulty = 3, key_id = "rusty_key" },
                trap = { type = "poison_needle", damage = 1, detected = false },
            },
            {
                id = "scattered_coins",
                type = "treasure",
                name = "Scattered Coins",
                description = "Gold and silver coins litter the floor. Remnants of a hasty exit?",
                state = "present",  -- Can be: present, collected
                interactions = { "examine", "collect" },
                value = 50,  -- Gold pieces
            },
        },

        verbs = {
            curiosity = { "glinting", "clicking", "watching" },
            travel_event = { "trap_triggered", "weight_shifted" },
        },

        meatgrinder_overrides = {
            curiosity = {
                "Something glints in the shadows - just a coin catching the light.",
                "You hear a faint clicking, like a mechanism resetting.",
                "The gold seems to glow with its own light for a moment.",
            },
        },
    },

    tutorial_hidden_alcove = {
        name = "Hidden Alcove",
        base_description = "A tiny chamber behind a loose stone. Someone has scratched 'TURN BACK' into the wall.",
        danger_level = 1,

        -- Combat zones (small space)
        zones = {
            { id = "alcove", name = "Alcove", description = "The cramped hidden chamber." },
        },

        features = {
            {
                id = "warning_inscription",
                type = "decoration",
                name = "Scratched Warning",
                description = "'TURN BACK' - gouged into the stone with desperate strokes.",
                state = "readable",
                interactions = { "examine", "trace" },
            },
            {
                id = "hidden_cache",
                type = "container",
                name = "Loose Stone",
                description = "One stone in the corner seems slightly offset.",
                state = "hidden",  -- Can be: hidden, found, opened, empty
                interactions = { "examine", "search", "pry" },
            },
        },

        verbs = {
            curiosity = { "whispering", "scratching", "breathing" },
        },

        meatgrinder_overrides = {
            curiosity = {
                "You hear faint scratching from within the walls.",
                "The warning seems to shimmer in the torchlight.",
                "A cold breath of air flows from somewhere unseen.",
            },
        },
    },

    tutorial_pit_trap_room = {
        name = "Pit Trap Room",
        base_description = "The bottom of a deep pit. Bones of previous victims litter the floor. The walls are too smooth to climb.",
        danger_level = 2,

        -- Combat zones (limited in a pit)
        zones = {
            { id = "pit_floor", name = "Pit Floor", description = "The bone-littered floor of the pit." },
        },

        features = {
            {
                id = "victim_remains",
                type = "corpse",
                name = "Scattered Bones",
                description = "Several skeletons, picked clean. Some look very old.",
                state = "unsearched",
                interactions = { "examine", "search" },
            },
            {
                id = "smooth_walls",
                type = "hazard",
                name = "Smooth Walls",
                description = "Polished stone, impossibly smooth. No handholds.",
                state = "impassable",
                interactions = { "examine", "climb" },
                climb_difficulty = 5,  -- Very hard
            },
        },

        verbs = {
            curiosity = { "dripping", "scurrying", "moaning" },
            travel_event = { "bone_snap", "something_falls" },
        },

        meatgrinder_overrides = {
            curiosity = {
                "Water drips from somewhere high above.",
                "Something small scurries among the bones.",
                "The wind moans through the pit opening above.",
            },
        },
    },

    ----------------------------------------------------------------------------
    -- GENERIC ROOM TEMPLATES
    -- For procedural generation or quick dungeons
    ----------------------------------------------------------------------------

    generic_corridor = {
        name = "Corridor",
        base_description = "A stone passageway stretches into darkness.",
        danger_level = 1,
        zones = {
            { id = "near_end", name = "Near End", description = "This end of the corridor." },
            { id = "far_end", name = "Far End", description = "The far end of the corridor." },
        },
        features = {},
        verbs = {
            curiosity = { "echoing", "dripping", "drafting" },
        },
    },

    generic_chamber = {
        name = "Chamber",
        base_description = "An unremarkable stone chamber.",
        danger_level = 1,
        zones = {
            { id = "chamber", name = "Chamber", description = "The main chamber." },
        },
        features = {},
        verbs = {
            curiosity = { "dust", "silence", "shadows" },
        },
    },

}

return M
