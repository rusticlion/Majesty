-- tutorial_level.lua
-- A small 5-room tutorial dungeon for testing
-- Ticket T2_1: Data-driven dungeon definition
--
-- Layout:
--
--     [Treasure Room]
--           |
--           | (locked door)
--           |
--     [Guard Room] ----(secret)---- [Hidden Alcove]
--           |
--           |
--     [Main Hall]
--           |
--           | (one-way chute down)
--           v
--     [Pit Trap Room]
--

local M = {}

M.data = {
    name = "Tutorial Dungeon",

    rooms = {
        {
            id          = "main_hall",
            name        = "Main Hall",
            description = "A grand entrance hall with crumbling pillars. Dust motes dance in the pale light filtering through cracks above.",
            -- Multiple zones for tactical combat (T2_3)
            zones = {
                { id = "entrance", name = "Entrance", description = "The main doorway into the hall." },
                { id = "pillars", name = "Among the Pillars", description = "Crumbling stone pillars provide partial cover." },
                { id = "balcony", name = "Balcony", description = "A crumbling balcony overlooks the hall.",
                  adjacent_to = { "pillars" } },  -- Balcony only adjacent to pillars, not entrance
            },
        },
        {
            id          = "guard_room",
            name        = "Guard Room",
            description = "Rusted weapon racks line the walls. A skeleton slumps in the corner, still clutching a broken spear.",
            zones = {
                { id = "main", name = "Main", description = "The center of the guard room." },
                { id = "weapon_racks", name = "Weapon Racks", description = "Rusted weapons hang on the walls." },
            },
        },
        {
            id          = "treasure_room",
            name        = "Treasure Room",
            description = "Gold coins glitter in the torchlight. A heavy iron chest sits against the far wall.",
            -- Single zone (uses default if omitted, but explicit here)
            zones = {
                { id = "main", name = "Main", description = "The treasure chamber." },
            },
        },
        {
            id          = "hidden_alcove",
            name        = "Hidden Alcove",
            description = "A tiny chamber behind a loose stone. Someone has scratched 'TURN BACK' into the wall.",
            -- No zones specified - will get default "main" zone
        },
        {
            id          = "pit_trap_room",
            name        = "Pit Trap Room",
            description = "The bottom of a deep pit. Bones of previous victims litter the floor. The walls are too smooth to climb.",
            -- No zones - single default zone
        },
    },

    connections = {
        -- Main Hall <-> Guard Room (normal two-way)
        {
            from = "main_hall",
            to   = "guard_room",
            properties = {
                direction = "north",
            },
        },

        -- Guard Room <-> Treasure Room (locked door)
        {
            from = "guard_room",
            to   = "treasure_room",
            properties = {
                direction   = "north",
                is_locked   = true,
                key_id      = "rusty_key",
                description = "A heavy iron door with an ornate lock.",
            },
        },

        -- Guard Room <-> Hidden Alcove (secret passage)
        {
            from = "guard_room",
            to   = "hidden_alcove",
            properties = {
                direction   = "east",
                is_secret   = true,
                description = "A loose stone that swings aside.",
            },
        },

        -- Main Hall -> Pit Trap Room (one-way chute!)
        {
            from = "main_hall",
            to   = "pit_trap_room",
            properties = {
                direction   = "down",
                is_one_way  = true,
                description = "A concealed chute. Once you fall in, there's no climbing back.",
            },
        },
    },
}

return M
