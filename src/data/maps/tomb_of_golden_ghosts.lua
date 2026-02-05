-- tomb_of_golden_ghosts.lua
-- The Tomb of Golden Ghosts - Example dungeon from HMtW Appendix E
-- Ticket T2_7: Vertical slice micro-dungeon
--
-- A tomb haunted by golden ghosts and infested by brain spiders.
-- Features secret doors hidden in murals, traps, and interesting NPCs.

local M = {}

M.data = {
    name = "The Tomb of Golden Ghosts",

    rooms = {
        -- Entrance area
        {
            id          = "101_entrance",
            name        = "Entrance",
            description = "The entrance to the tomb yields to two hallways, one going north and one going east.",
            danger_level = 1,
            zones = {
                { id = "main", name = "Main", description = "The entrance chamber." },
                { id = "north_hall", name = "Northern Hallway", description = "A hallway leading north with a mural on the west wall." },
                { id = "east_hall", name = "Eastern Hallway", description = "A hallway heading east." },
            },
            features = {
                {
                    id = "ruined_door",
                    name = "ruined door",
                    type = "decoration",
                    description = "A heavy iron door, twisted completely off its hinges. Whatever did this was strong.",
                    hidden_description = "Deep claw marks score the metal. Something large forced its way in.",
                    secrets = "Wedged in the twisted frame you find a discarded torch and a stick of chalk.",
                    investigate_test = { attribute = "swords", difficulty = 10 },
                    loot = { "torch", "chalk" },
                },
                {
                    id = "west_mural",
                    name = "faded mural",
                    type = "decoration",
                    description = "A mural depicting a robed sorcerer observing the night sky. Stars and constellations surround him.",
                    hidden_description = "One star in the mural seems slightly raised from the wall...",
                    secrets = "Pressing the raised star reveals a hidden latch! A secret door swings open.",
                    investigate_test = { attribute = "pentacles", difficulty = 12 },
                    reveal_connection = { to = "112_hidden_sanctum" },
                },
            },
        },
        {
            id          = "102_scriptorium",
            name        = "Scriptorium",
            description = "A small room. Each wall holds crumbling bookshelves, laden with ancient, moldering scrolls. A moldy smell pervades.",
            danger_level = 1,
            features = {
                {
                    id = "bookshelves",
                    name = "crumbling bookshelves",
                    type = "container",
                    description = "Dozens of scrolls and codices, most ruined by age and moisture.",
                    hidden_description = "Most texts are illegible, but a few fragments mention 'the sleeper' and 'the silver crown'.",
                    secrets = "You find a intact scroll: a partial map of the tomb's lower levels.",
                    investigate_test = { attribute = "cups", difficulty = 10 },
                    -- S11.3: Loot items from item templates
                    loot = { "partial_map", "torch" },
                },
                {
                    id = "moldy_smell",
                    name = "moldy smell",
                    type = "hazard",
                    description = "The air is thick with spores. Breathing deeply might not be wise.",
                    hidden_description = "The mold seems to be growing from something beneath the floorboards.",
                },
            },
        },
        {
            id          = "103_antechamber",
            name        = "Antechamber of Centipedes",
            description = "An oblong room. The ground is churned and soft here. There is a putrid smell.",
            danger_level = 3,
            features = {
                {
                    id = "churned_ground",
                    name = "churned ground",
                    type = "hazard",
                    description = "The earth has been disturbed repeatedly. Tunnel holes dot the floor.",
                    hidden_description = "The tunnels are sized for something dog-sized. Many somethings.",
                    trap = { damage = 1, description = "A giant centipede bursts from the ground!" },
                    investigate_test = { attribute = "pentacles", difficulty = 14 },
                },
            },
        },
        {
            id          = "104_corpse",
            name        = "A Corpse",
            description = "A stinking corpse, mostly eaten, slumped in the corner.",
            danger_level = 2,
            features = {
                {
                    id = "dead_adventurer",
                    name = "corpse",
                    type = "corpse",
                    description = "A dead adventurer, partially devoured. Their face is frozen in terror.",
                    hidden_description = "The wounds suggest centipede bites. They died badly.",
                    secrets = "In their clenched fist: a crumpled note reading 'The crown - don't let them take the crown!'",
                    investigate_test = { attribute = "cups", difficulty = 8 },
                },
                {
                    id = "torn_pack",
                    name = "torn pack",
                    type = "container",
                    description = "A leather backpack, torn open. Contents scattered.",
                    secrets = "You find: 2 torches, a waterskin, and 15 silver coins.",
                    investigate_test = { attribute = "pentacles", difficulty = 6 },
                    -- S11.3: Loot items from item templates
                    loot = { "torch", "torch", "waterskin", "silver_spider_key" },
                },
                -- S10.4: The key to the laboratory door
                {
                    id = "silver_key",
                    name = "silver key",
                    type = "item",
                    state = "hidden",  -- Must search torn_pack first
                    description = "A tarnished silver key with a spider emblem.",
                    secrets = "This key bears the mark of the Brain Spiders. It must unlock something important.",
                    item = {
                        id = "laboratory_key",
                        name = "Silver Spider Key",
                        size = 1,
                        keyId = "laboratory_door",  -- Links to the locked door
                    },
                },
            },
        },
        -- Hall and burial areas
        {
            id          = "105_hall_of_solemnity",
            name        = "Hall of Solemnity",
            description = "A long hall held up by a central line of mighty stone columns chiseled from the living stone. The northern wall has crumbled away, revealing a large natural cavern.",
            danger_level = 2,
            zones = {
                { id = "west", name = "Western Hall", description = "The columns stretch into shadow." },
                { id = "center", name = "Central Hall", description = "Among the mighty columns." },
                { id = "east_webbed", name = "Webbed Passage", description = "Silvery webs block the eastern passage." },
            },
            features = {
                {
                    id = "stone_columns",
                    name = "stone columns",
                    type = "decoration",
                    description = "Massive columns carved directly from the bedrock. Ancient and immovable.",
                    hidden_description = "Faint carvings on one column depict a procession of mourners.",
                },
                {
                    id = "silvery_webs",
                    name = "silvery webs",
                    type = "hazard",
                    description = "Thick, silvery webs block the eastern passage. They shimmer with an unnatural light.",
                    hidden_description = "These webs are too strong to break by hand. Fire would work, but might attract attention.",
                    trap = { damage = 0, description = "The webs are sticky! You're entangled!" },
                    investigate_test = { attribute = "wands", difficulty = 10 },
                },
            },
        },
        {
            id          = "106_burial_chambers",
            name        = "Burial Chambers",
            description = "The hallway bends around into a semi-circular shape. There is a mural on the northeastern wall of an astronomer pointing in alarm towards a comet.",
            danger_level = 2,
            features = {
                {
                    id = "astronomer_mural",
                    name = "astronomer mural",
                    type = "decoration",
                    description = "A robed figure points at a blazing comet. Their expression shows terror.",
                    hidden_description = "The comet appears to be falling toward a cradle. An omen of doom?",
                    secrets = "A loose stone behind the mural conceals a secret passage!",
                    investigate_test = { attribute = "cups", difficulty = 12 },
                },
            },
        },
        {
            id          = "107_looted_tomb",
            name        = "The Looted Tomb",
            description = "A circular chamber holding seven empty stone sarcophagi. The lids of these coffins are cast off, broken, onto the ground.",
            danger_level = 3,
            features = {
                {
                    id = "golden_ghosts",
                    name = "golden ghosts",
                    type = "creature",
                    description = "Seven semi-transparent golden figures cluster around you, weeping golden tears and making wild gesticulations.",
                    hidden_description = "They seem to be trying to communicate. One points repeatedly toward the south.",
                    secrets = "If you can understand them, they warn: 'The crown! She seeks the crown! Do not let her take it!'",
                    investigate_test = { attribute = "cups", difficulty = 8 },
                },
                {
                    id = "sarcophagi",
                    name = "stone sarcophagi",
                    type = "container",
                    description = "Seven stone coffins, all opened and emptied long ago. The lids lie shattered on the floor.",
                    hidden_description = "One sarcophagus has a false bottom...",
                    secrets = "A hidden compartment contains a golden amulet shaped like a weeping eye.",
                    investigate_test = { attribute = "pentacles", difficulty = 14 },
                },
            },
        },
        {
            id          = "108_tripartite_statue",
            name        = "Tripartite Statue",
            description = "A three-sided, gold-plated stone statue stands in a niche: one side depicts a maiden, one a pregnant woman, and one a crone. A desiccated corpse lies at the statue's feet. The three heads share a single silver crown.",
            danger_level = 4,
        },
        -- Spider territory
        {
            id          = "109_guard_room",
            name        = "Guard Room of the Puppet-Mummies",
            description = "A long room about 10' wide and 30' long. The room's north section crumbles away into a river.",
            danger_level = 3,
            zones = {
                { id = "entrance", name = "Entrance", description = "The southern doorway." },
                { id = "main", name = "Main Chamber", description = "The center of the guard room." },
                { id = "river", name = "Riverbank", description = "Where the floor crumbles into the underground river." },
            },
        },
        -- S10.4: Group Test trap (testing resolver.lua group logic)
        {
            id          = "110_trapped_hallway",
            name        = "Trapped Hallway",
            description = "A curving hallway with three short flights of stairs towards a door. A large boulder tied to the ceiling with silvery webs hangs ominously. Several thin, silvery webs criss-cross the path.",
            danger_level = 4,
            zones = {
                { id = "entrance", name = "Entrance", description = "The northern stairs." },
                { id = "middle", name = "Trapped Section", description = "The webbed corridor beneath the boulder." },
                { id = "exit", name = "Exit", description = "The southern stairs leading to the treasure room." },
            },
            features = {
                {
                    id = "web_trigger",
                    name = "silvery trip-webs",
                    type = "trap",
                    description = "Nearly invisible silvery webs stretch across the corridor at ankle height.",
                    hidden_description = "These webs are connected to the boulder above. Triggering them would be catastrophic.",
                    -- S10.4: Group test trap - the whole party must work together
                    trap = {
                        damage = 2,
                        description = "The boulder crashes down! The guild must scatter!",
                        isGroupTest = true,  -- Requires group test to avoid
                        attribute = "pentacles",
                        difficulty = 12,
                        failureText = "The boulder rolls through the corridor! Those who fail their test are crushed for 2 wounds!",
                        successText = "The guild works together, each member timing their movement perfectly. The boulder crashes harmlessly past.",
                    },
                    investigate_test = { attribute = "pentacles", difficulty = 10 },
                },
                {
                    id = "hanging_boulder",
                    name = "suspended boulder",
                    type = "hazard",
                    description = "A massive stone sphere hangs from silvery webs attached to the ceiling. It looks ready to fall.",
                    hidden_description = "The webs connecting it to the trip-wires below are extremely taut.",
                },
            },
        },
        {
            id          = "111_spiders_treasure",
            name        = "The Spiders' Treasure",
            description = "A large treasure chest sits in the middle of the room. On the southern wall, a faded mural of a weeping woman with a moon-like halo.",
            danger_level = 2,
            features = {
                {
                    id = "treasure_chest",
                    name = "treasure chest",
                    type = "container",
                    description = "A heavy iron-bound chest. Surprisingly, it appears unlocked.",
                    hidden_description = "Fine silvery threads connect the lid to... something above. A trap?",
                    secrets = "Inside: gold coins, a ruby ring, and a rolled vellum map of the surrounding region!",
                    trap = { damage = 1, description = "The lid triggers a web-net trap! Sticky strands fall from above!" },
                    investigate_test = { attribute = "pentacles", difficulty = 12 },
                    -- S11.3: Loot items from item templates
                    loot = { "gold_coins_15", "ruby_ring", "vellum_map" },
                },
                {
                    id = "vellum_map_item",
                    name = "vellum map",
                    type = "container",
                    state = "hidden",  -- Only appears after chest is opened
                    description = "A detailed map on aged vellum, showing the tomb and surrounding lands.",
                    secrets = "This is what you came for! The map shows routes to three other dungeons.",
                },
                {
                    id = "weeping_mural",
                    name = "weeping woman mural",
                    type = "decoration",
                    description = "A woman with a moon-like halo weeps silver tears. Her hands reach toward something unseen.",
                    hidden_description = "The tears are actual silver inlay. The hands point toward the western wall.",
                    secrets = "Pressing where her hands point reveals a hidden door!",
                    investigate_test = { attribute = "cups", difficulty = 14 },
                },
            },
        },
        {
            id          = "112_hidden_sanctum",
            name        = "The Hidden Sanctum",
            description = "This room is dusty and undisturbed. A thin trickle of water dribbles from the ceiling into a puddle. Moss covers the west wall where a large pale snail grazes.",
            danger_level = 1,
        },
        {
            id          = "113_pit_of_bones",
            name        = "The Pit of Bones",
            description = "A sprawling, shadowy natural cavern. Uneven flooring, dripping with stalactites, covered in puddles. A narrow crevasse 50' deep runs like a wound through this cavern. A foul stench emanates from the pit.",
            danger_level = 3,
        },
        {
            id          = "114_laboratory",
            name        = "Magical Laboratory",
            description = "The brain spider's laboratory - a writing desk, shelves of reagents, ingredients, and arcane tools. In the corner, a large glass tank holds a giant sleeping baby that sheds steady silvery light.",
            danger_level = 4,
        },
        {
            id          = "115_book_worm",
            name        = "The Book Worm's Closet",
            description = "A small closet. A dire centipede who calls herself 'Book Worm' lives here. She speaks only Vetus.",
            danger_level = 1,
        },
        -- S10.4: Boss room with Greater Doom enemy
        {
            id          = "116_glaura_nest",
            name        = "Glaura's Nest",
            description = "A spacious room covered in webs. A clutch of eggs the size of basketballs is plastered to the cavern walls. The southern wall has a dilapidated mural. A massive brain spider dominates the center of the chamber, her many eyes gleaming with malevolent intelligence.",
            danger_level = 5,  -- Boss room
            zones = {
                { id = "entrance", name = "Entrance", description = "The doorway into the nest." },
                { id = "center", name = "Glaura's Throne", description = "Where the spider queen waits." },
                { id = "egg_wall", name = "Egg Clutch", description = "The wall covered in spider eggs." },
            },
            features = {
                {
                    id = "glaura_boss",
                    name = "Glaura Glossolalia",
                    type = "creature",
                    description = "A brain spider the size of a horse. Her bulbous head pulses with psychic energy, and she speaks directly into your mind: 'Little morsels... you should not have come here.'",
                    hidden_description = "Glaura is connected to the star-child in the laboratory. If threatened, she can channel its power.",
                    -- Boss encounter data
                    encounter = {
                        blueprint_id = "brain_spider_queen",
                        count = 1,
                        reinforcements = { blueprint_id = "brain_spider", count = 2, trigger = "on_injured" },
                    },
                },
                {
                    id = "spider_eggs",
                    name = "spider eggs",
                    type = "hazard",
                    description = "Dozens of leathery eggs, each pulsing faintly with movement from within.",
                    hidden_description = "These eggs are close to hatching. Disturbing them would be unwise.",
                    trap = { damage = 0, description = "The eggs burst! Tiny brain spiders swarm everywhere!" },
                },
                {
                    id = "dilapidated_mural",
                    name = "dilapidated mural",
                    type = "decoration",
                    description = "A faded painting showing a crowned figure descending into the earth. Stars fall around them.",
                    hidden_description = "The crowned figure appears to be carrying an infant wreathed in silver light.",
                    secrets = "The mural conceals a secret door leading to the burial chambers!",
                    investigate_test = { attribute = "cups", difficulty = 14 },
                },
            },
        },
        {
            id          = "117_kodi_nest",
            name        = "Kodi's Nest",
            description = "A spacious room covered in webs. A few fat sacks of webs hang from the ceiling here.",
            danger_level = 4,
        },

        -- S12.8: Social Encounter POC - The Tomb Guardian
        {
            id          = "118_chamber_of_vigilant",
            name        = "Chamber of the Vigilant",
            description = "A circular chamber of polished black stone. An ancient altar stands at its center, covered in faded offerings of gold coins and dried flowers. Carved tablets line the walls, inscribed with the names of those interred here. A spectral figure materializes as you enter, its golden form flickering with ancient power.",
            danger_level = 2,  -- Not inherently dangerous if handled socially
            zones = {
                { id = "entrance", name = "Entrance", description = "The threshold into the chamber." },
                { id = "altar", name = "Ancient Altar", description = "Before the offering altar." },
                { id = "tablets", name = "Memorial Tablets", description = "Among the carved stone tablets." },
            },
            features = {
                {
                    id = "tomb_guardian",
                    name = "Tomb Guardian Spirit",
                    type = "creature",
                    description = "A translucent golden figure wearing ancient ceremonial robes. It watches you with eyes that have seen centuries pass.",
                    hidden_description = "The guardian seems more curious than hostile. Perhaps it can be reasoned with.",
                    -- S12.8: Social encounter configuration
                    encounter = {
                        blueprint_id = "tomb_guardian_spirit",
                        count = 1,
                        isSocialEncounter = true,  -- Flags this as a social encounter
                        initiatesDialogue = true,  -- Guardian speaks first
                    },
                },
                {
                    id = "ancient_altar",
                    name = "ancient altar",
                    type = "container",
                    description = "A stone altar covered in offerings - gold coins, dried flower petals, and small personal effects left by mourners long dead.",
                    hidden_description = "The offerings seem to please the guardian. Leaving something of value might earn its favor.",
                    secrets = "Among the offerings, you notice a golden medallion still radiating faint warmth.",
                    investigate_test = { attribute = "cups", difficulty = 10 },
                    -- S12.8: Offering interaction
                    acceptsOffering = true,
                    offeringEffect = {
                        type = "disposition_shift",
                        target = "tomb_guardian",
                        direction = 1,  -- Toward Trust/Joy
                        amount = 2,
                    },
                    loot = { "golden_medallion" },
                },
                {
                    id = "inscribed_tablets",
                    name = "inscribed tablets",
                    type = "decoration",
                    description = "Stone tablets carved with names, dates, and epitaphs in an ancient script. Some are still legible.",
                    hidden_description = "The tablets tell the story of this tomb - a resting place for the astronomers who predicted the Comet of Woe.",
                    secrets = "Reading the tablets aloud seems to please the guardian. The names resonate with meaning: Kethran the Seer, Miravel Starwatcher, Ossian of the Silver Eye...",
                    investigate_test = { attribute = "wands", difficulty = 8 },
                    -- S12.8: Lore interaction - grants social bonus
                    grantsLore = "tomb_history",
                    loreEffect = {
                        type = "social_favor",
                        target = "tomb_guardian",
                        description = "Knowledge of the tomb's history grants +2 to social attempts with the guardian.",
                        modifier = 2,
                    },
                },
            },
            -- S12.8: Room-level social encounter configuration
            socialEncounter = {
                guardian = "tomb_guardian",
                -- Opening dialogue based on disposition
                onEnter = {
                    event = "guardian_materializes",
                    description = "The guardian materializes from the walls, golden light pooling into a humanoid form.",
                },
                -- Options available to players
                playerOptions = {
                    { action = "attack", description = "Attack (triggers combat)" },
                    { action = "banter", description = "Speak with respect (Banter - Wands)" },
                    { action = "offer", description = "Make an offering at the altar" },
                    { action = "read_tablets", description = "Study the inscribed tablets" },
                    { action = "leave", description = "Back away slowly and leave" },
                },
                -- Resolution outcomes
                outcomes = {
                    trust_success = {
                        description = "The guardian bows deeply. 'You have honored the dead. Take this blessing, and may the path ahead open before you.'",
                        effect = "reveal_secret_passage",
                        reward = "guardian_blessing",
                    },
                    fear_success = {
                        description = "The guardian's form wavers, then fades into the walls with a mournful wail. The chamber falls silent.",
                        effect = "guardian_retreats",
                    },
                    anger_combat = {
                        description = "The guardian's eyes blaze with fury. 'DEFILERS!' Its form solidifies, ready for battle.",
                        effect = "combat_start",
                    },
                },
            },
        },
    },

    connections = {
        -- Entrance area connections
        { from = "101_entrance", to = "102_scriptorium", properties = { direction = "east" } },
        { from = "101_entrance", to = "103_antechamber", properties = { direction = "north" } },
        { from = "101_entrance", to = "112_hidden_sanctum", properties = {
            direction = "west",
            is_secret = true,
            description = "A mural of a sorcerer observing the night sky hides a hidden latch.",
        }},

        -- Entrance area east side
        { from = "102_scriptorium", to = "104_corpse", properties = { direction = "east" } },
        { from = "102_scriptorium", to = "115_book_worm", properties = { direction = "south" } },

        -- North from entrance
        { from = "103_antechamber", to = "105_hall_of_solemnity", properties = { direction = "north" } },

        -- Hall of Solemnity branches
        { from = "105_hall_of_solemnity", to = "113_pit_of_bones", properties = { direction = "north" } },
        { from = "105_hall_of_solemnity", to = "106_burial_chambers", properties = {
            direction = "east",
            description = "Silvery webs block the passage. Brain spider webs keep ghosts contained.",
        }},

        -- Burial chambers loop
        { from = "106_burial_chambers", to = "107_looted_tomb", properties = { direction = "east" } },
        { from = "107_looted_tomb", to = "108_tripartite_statue", properties = { direction = "south" } },
        { from = "106_burial_chambers", to = "116_glaura_nest", properties = {
            direction = "south",
            is_secret = true,
            is_one_way = true,  -- Can only be opened from 116 side
            description = "A secret door in the mural. Cannot be opened from this side.",
        }},

        -- Spider territory
        -- S10.4: Locked door requiring the Silver Spider Key
        { from = "113_pit_of_bones", to = "114_laboratory", properties = {
            direction = "east",
            is_locked = true,
            key_id = "laboratory_door",
            description = "A heavy iron door blocks the passage. A spider emblem is engraved above the lock.",
        }},
        { from = "114_laboratory", to = "109_guard_room", properties = { direction = "east" } },
        { from = "109_guard_room", to = "110_trapped_hallway", properties = { direction = "south" } },
        { from = "110_trapped_hallway", to = "111_spiders_treasure", properties = {
            direction = "south",
            description = "A boulder tied to the ceiling with webs threatens to fall.",
        }},

        -- Secret sanctum connections
        { from = "111_spiders_treasure", to = "112_hidden_sanctum", properties = {
            direction = "west",
            is_secret = true,
            description = "A mural of a weeping woman hides a secret door.",
        }},

        -- Spider nests
        { from = "114_laboratory", to = "116_glaura_nest", properties = { direction = "north" } },
        { from = "114_laboratory", to = "117_kodi_nest", properties = { direction = "south" } },
        { from = "109_guard_room", to = "117_kodi_nest", properties = {
            direction = "east",
            description = "An illusory wall conceals this passage.",
        }},

        -- S12.8: Connection to the Chamber of the Vigilant
        { from = "106_burial_chambers", to = "118_chamber_of_vigilant", properties = {
            direction = "west",
            description = "An archway leads to a circular chamber. Faint golden light emanates from within.",
        }},
    },
}

-- Meatgrinder overrides for this dungeon (referenced by meatgrinder.lua)
M.meatgrinder = {
    -- Torches gutter (I-V): Standard
    torches_gutter = {
        description = "Your torches flicker. The darkness of the tomb presses in.",
    },

    -- Curiosities (VI-X)
    curiosity = {
        [1] = "You hear the distant sound of weeping echoing through stone corridors.",
        [2] = "Golden light flickers briefly from somewhere deeper in the tomb.",
        [3] = "A cold draft carries the scent of old incense and decay.",
        [4] = "Scratching sounds come from within the walls - something with many legs.",
        [5] = "You glimpse a golden, translucent figure drifting past a doorway.",
    },

    -- Travel events (XI-XV)
    travel_event = {
        [1] = { description = "Droppings. Someone steps in something foul. Become Stressed unless cleaned soon.", effect = "stress_threat" },
        [2] = { description = "The guild encounters a rushing underground river blocking the path.", effect = "obstacle" },
        [3] = { description = "Trap webs! First in marching order tests Cups to notice the snare.", effect = "trap", attribute = "cups" },
        [4] = { description = "A distant earthquake - the cavern shakes. Test Pentacles or take a Wound.", effect = "damage_test", attribute = "pentacles" },
        [5] = { description = "Giant centipedes have churned the soft ground. First in march may sink in.", effect = "trap", attribute = "pentacles" },
    },

    -- Random encounters (XVI-XX)
    random_encounter = {
        [1] = { blueprint_id = "puppet_mummy", count = "adventurers", description = "Puppet-mummies controlled by unseen webs jerkily attack!" },
        [2] = { blueprint_id = "brain_spider", count = 1, description = "Glaura Glossolalia is weaving webs. She hisses a telepathic warning." },
        [3] = { description = "A weeping golden ghost appears. It cannot speak but gestures wildly.", npc = "golden_ghost" },
        [4] = { description = "Rival adventurers Finch and Justin Pepperoni, chased by centipedes!", npc = "rivals" },
        [5] = { blueprint_id = "giant_centipede", count = "adventurers-1", description = "Giant centipedes block the way!" },
    },

    -- Quest rumor (XXI)
    quest_rumor = {
        description = "A vision or hint about the star-child and its terrible power...",
    },
}

return M
