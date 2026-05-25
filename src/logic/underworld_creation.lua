-- underworld_creation.lua
-- Backend helpers for Appendix E Underworld creation procedures.

local M = {}

M.PROCEDURE_STEPS = {
    "origins",
    "generate_layout",
    "create_maps",
    "write_room_descriptions",
    "create_meatgrinder",
}

M.PROCEDURE_STEP_DETAILS = {
    {
        key = "origins",
        label = "Origins of the Underworld",
        scope = "underworld",
        description = "Decide the nature, truths, original purpose, current contradiction, and open questions of the Underworld.",
    },
    {
        key = "generate_layout",
        label = "Generate an Underworld layout",
        scope = "underworld",
        description = "Draw Major Arcana cards, place entrances and depth, and define connections between dungeon levels.",
    },
    {
        key = "create_maps",
        label = "Create maps",
        scope = "dungeon_level",
        description = "Create or borrow a map, draw areas and pathways, key rooms, and prepare an in-character player map.",
    },
    {
        key = "write_room_descriptions",
        label = "Write room descriptions",
        scope = "dungeon_level",
        description = "Write permanent room features, dangers, treasures, denizens, clues, and interaction notes.",
    },
    {
        key = "create_meatgrinder",
        label = "Create the Meatgrinder",
        scope = "dungeon_level",
        description = "Create a Meatgrinder table for the level's reactive pressure, curiosities, events, encounters, and rumors.",
    },
}

M.PROCEDURE_CADENCE = {
    underworldWideSteps = { "origins", "generate_layout" },
    repeatedPerLevelSteps = { "create_maps", "write_room_descriptions", "create_meatgrinder" },
    guidance = "Steps 1 and 2 are done once for the entire Underworld; steps 3-5 repeat for each dungeon level.",
    scale = "Start at a small scale and repeat until the Underworld feels mythic.",
    seedUse = "Dungeon seeds are optional inspirational prompts for jumpstarting levels or replacing with original ideas.",
}

M.DUNGEON_SEEDS = {
    [1] = { cardName = "The Magician", name = "The Spires" },
    [2] = { cardName = "The High Priestess", name = "The Boundless Moat" },
    [3] = { cardName = "The Empress", name = "The Castle of Crossed Destinies" },
    [4] = { cardName = "The Emperor", name = "The Inverted Castle" },
    [5] = { cardName = "The Hierophant", name = "The City of Ruin" },
    [6] = { cardName = "The Lovers", name = "The Pits" },
    [7] = { cardName = "The Chariot", name = "Belly of the Beast" },
    [8] = { cardName = "Justice", name = "The Drowned Wedding" },
    [9] = { cardName = "The Hermit", name = "The Library Heretical" },
    [10] = { cardName = "Wheel of Fortune", name = "The Field of Reeds" },
    [11] = { cardName = "Strength", name = "The Sepulcher of Titans" },
    [12] = { cardName = "The Hanged Man", name = "Xania" },
    [13] = { cardName = "Death", name = "The Necropolis of Ot" },
    [14] = { cardName = "Temperance", name = "The Menagerie of Singular Creatures" },
    [15] = { cardName = "The Devil", name = "The Hellmarkt" },
    [16] = { cardName = "The Tower", name = "The House of Many Angles" },
    [17] = { cardName = "The Star", name = "The Augury" },
    [18] = { cardName = "The Moon", name = "The Truesilver Forge" },
    [19] = { cardName = "The Sun", name = "The White Gardens" },
    [20] = { cardName = "Judgement", name = "The Dragonbone Memorial" },
    [21] = { cardName = "The World", name = "The Undertomb" },
}

local DUNGEON_SEED_DETAILS = {
    [1] = {
        summary = "A vast dead archwood cavern forest whose trunks, bridges, and roots form the level.",
        sensory = {
            sights = "Colossal dead trees, eerie branch shadows, and islands of wood over empty space.",
            sounds = "A constant copper-locust buzz.",
            smellTaste = "Rotten pumpkin, humus, and old vegetation.",
        },
        lighting = "Dim mushroom half-light like moonlight.",
        structures = "Wooden bridges connect hanging tree islands.",
        commonMonsters = {
            "Forest Imps", "Mushroom Men", "Cockatrice", "Dire Bats", "Dire Wolves",
            "Sword Spiders", "Undead Bears", "Flower Fairies", "Dryads", "Lions",
        },
        dungeonLord = "The Locust Lich",
    },
    [2] = {
        summary = "An underground ocean of glowing water choked with shipwreck islands and worse.",
        sensory = {
            sights = "Blue bioluminescent water and floating wreckage dungeons.",
            sounds = "Huge, regular wave noise like a giant breathing.",
            smellTaste = "Salt, humidity, and rust pressure on metal gear.",
        },
        lighting = "Dim blue light from bioluminescent waters.",
        structures = "Flotsam rafts, wreckage chambers, gangplanks, and reefs.",
        commonMonsters = {
            "Brine Imps", "Sirens", "Vodyanoy", "Kraken", "Daggerfish", "Dire Man o' Wars",
            "Dire Eels", "Kelpies", "Leviathans",
        },
        dungeonLord = "The Maimed Mermaid",
    },
    [3] = {
        summary = "A decadent fallen castle of baroque art, unknowable traps, and bound servants.",
        sensory = {
            sights = "Grand old rooms full of magnificent art.",
            sounds = "Eerie silence broken by the guild's footsteps.",
            smellTaste = "Old dust and mold.",
        },
        lighting = "Candles in most rooms and halls, tended by the Lavritic.",
        structures = "Cold fitted-stone halls and chambers with wooden lever-handled doors.",
        commonMonsters = {
            "Painted Imps", "Dire Rats", "Living Armor", "Living Paintings", "Mimics",
            "Gargoyles", "The First Knights",
        },
        dungeonLord = "The Bone Chandelier",
    },
    [4] = {
        summary = "A stalactite castle warped by entombed dragon children and irrational human facsimiles.",
        sensory = {
            sights = "Escher-like halls, disproportionate furniture, and an ofuda-wrapped dragon shrine.",
            sounds = "Hourly bells echo through the hanging towers.",
            smellTaste = "Dry warmth with a faint iron tang.",
        },
        lighting = "None.",
        structures = "Cold fitted-stone chambers and wooden lever-handled doors.",
        commonMonsters = {
            "Giggling Imps", "Mummified Orcs", "Orc Raiders", "Sphinxes", "Typhon Dogs",
            "Scorpion Men", "Dire Cats", "Dire Beetles", "Mummified Dragons",
        },
        dungeonLord = "The Beastmaster",
    },
    [5] = {
        summary = "The ruined first City, stripped of most gold and full of colossal derelict architecture.",
        sensory = {
            sights = "Cyclopean ruins and colossal statues crowding streets and squares.",
            sounds = "Cold wind screaming through the avenues.",
            smellTaste = "Cold, dry, dusty air.",
        },
        lighting = "Dim red street-lamp glow outdoors; ruined buildings are dark.",
        structures = "Massive granite buildings, mostly hollow or scavenged into new interiors.",
        commonMonsters = {
            "Deconstruction Imps", "Dire Cockroaches", "Necrotic Slimes", "Face Rats",
            "Pacifist Werewolves", "Animate Columns", "Vampire Spawn", "Harpies",
        },
        dungeonLord = "The Enormous",
    },
    [6] = {
        summary = "Life-choked ratman breeding tunnels where generations turn over in a week.",
        sensory = {
            sights = "Honeycombed natural caverns, oozing holes, and swarming breeding pits.",
            sounds = "Constant chattering, squeaking, gnawing, chewing, and scurrying.",
            smellTaste = "Overpowering ammonia.",
        },
        lighting = "Dim smoky torchlight in ratman halls; otherwise dark.",
        structures = "Natural caverns and narrow tunnels slick with mold and filth.",
        commonMonsters = {
            "Effluence Imps", "Dire Lice", "Ratmen", "Goblins", "Meat Slimes",
            "Living Buboes", "Zombie Troglodytes",
        },
        dungeonLord = "The Rat King",
    },
    [7] = {
        summary = "The corpse of Apep, full of swallowed history, bile, prisoners, and organic passages.",
        sensory = {
            sights = "Strange objects of every size resting in shallow bile.",
            sounds = "Flies, digestion, and slow dripping fluids.",
            smellTaste = "Sweet preserved-organic stench.",
        },
        lighting = "None.",
        structures = "Tissue-and-cartilage tunnels with valve and sphincter doors.",
        commonMonsters = {
            "Melancholic Imps", "Dire Tapeworms", "Dire Rats", "Hellflies", "Skeleton Jellies",
            "Green Slimes", "Various Stomach Prisoners",
        },
        dungeonLord = "The Still-Beating Heart",
    },
    [8] = {
        summary = "A sunken elven wedding island preserved inside a hollow pearl beneath a lake.",
        sensory = {
            sights = "An impossibly aged gala with rotting food, wine, and cobwebbed decorations.",
            sounds = "Ghost moans, distant music, and water moving through cracks.",
            smellTaste = "Incense, rotting flowers, and salt sea air.",
        },
        lighting = "None.",
        structures = "Diamond-hard pearl shell and magically warped wooden island structures.",
        commonMonsters = {
            "Brine Imps", "Mermaids", "Vodyanoy", "Walrus Men", "Land Whales", "Dire Lice",
            "Elephantine Oozes", "Topiary Golems", "Elven Ghosts", "Draugr", "Banshees",
        },
        dungeonLord = "The Finfolk King",
    },
    [9] = {
        summary = "A cyclops-restored archive of censored texts rebuilt from book-smoke soot.",
        sensory = {
            sights = "Endless books, scroll stacks, and sprawling scriptoria.",
            sounds = "Pens scratching and pages turning.",
            smellTaste = "Dry dust with lingering acrid smoke.",
        },
        lighting = "Bright light from hanging dire-firefly jars in most rooms.",
        structures = "Gigantic bookshelf corridors, secret doors, and cyclops-sized stairs.",
        commonMonsters = {
            "Ink Imps", "Cyclops Librarians", "Origami Golems", "Bookworms", "Crawling Brains",
            "Book Mimics", "Memetic Plagues", "Speech Bubble Jellyfish",
        },
        dungeonLord = "The Librarian Lich",
    },
    [10] = {
        summary = "A treacherous swamp at the confluence of five Underworld rivers.",
        sensory = {
            sights = "Night-swamp greenery, torchlit eyeshine, vines, mud, and jagged stumps.",
            sounds = "Soft splashes and insect whines.",
            smellTaste = "Hot, wet, feverish fetid water.",
        },
        lighting = "Some swamp sections burn continuously; otherwise dark.",
        structures = "Crumbling stone ruins rising from the swamp.",
        commonMonsters = {
            "Brine Imps", "Will o' Wisps", "Bog Mummies", "Dire Spiders", "Dire Toads",
            "Hydrae", "Harpies", "Ogres",
        },
        dungeonLord = "Moonback the Dire Alligator",
    },
    [11] = {
        summary = "A close-fitting stone sepulcher for dismembered but not-dead titans.",
        sensory = {
            sights = "Claustrophobic halls opening into giant burial chambers.",
            sounds = "Holy quiet interrupted by titans shifting in tombs.",
            smellTaste = "Damp earth and pungent mold.",
        },
        lighting = "None.",
        structures = "Unworked fitted-stone rooms, natural cavern halls, and huge stone doors.",
        commonMonsters = {
            "Tunneling Imps", "Ogres", "Mummified Giants", "Disembodied Crawling Hands",
            "Furies", "Dire Spiders", "Chimerae", "Manticores",
        },
        dungeonLord = "The Sporehulk",
    },
    [12] = {
        summary = "A cloning tower where Xania is endlessly unstitched and remade from human material.",
        sensory = {
            sights = "Flesh, hair, skin, bone, and other human-derived furnishings everywhere.",
            sounds = "Busy castle labor, gossip, babies, birth sacs, nightsoil, and sweeping.",
            smellTaste = "Birthing-room odor.",
        },
        lighting = "Bright human-fat candlelight in most rooms; halls are dark.",
        structures = "Crumbling stone rooms, metal locked doors, and well-made grotesque furniture.",
        commonMonsters = {
            "Xania",
        },
        dungeonLord = "Xania",
    },
    [13] = {
        summary = "A necromantic city of the dead born from humanity's first terror of death.",
        sensory = {
            sights = "Bone pyramids, skull walls, funerary urns, and chambers of the dead.",
            sounds = "Ceaseless dead whispers that never quite resolve into words.",
            smellTaste = "Dry dust and chapped lips.",
        },
        lighting = "None.",
        structures = "Limestone buildings decorated with bones and pivoting stone doors.",
        commonMonsters = {
            "Saprovore Imps", "Ghosts", "Zombies", "Skeletons", "Wraiths", "Shadows",
            "Skin Slimes", "Tooth Fairies", "Dire Owls", "Monstrance Golems",
        },
        dungeonLord = "The First Dead",
    },
    [14] = {
        summary = "A cavern menagerie of unique creatures, each with a singular treasure, story, and danger.",
        sensory = {
            sights = "Rooms vary wildly, from gloomy caverns to crystalline sunlit vaults.",
            sounds = "Varied chamber sounds, with Echidna's glass organ never far away.",
            smellTaste = "Each room has its own odor.",
        },
        lighting = "Various; some rooms are dark and others are well lit.",
        structures = "Mostly unworked stone caverns with custom spaces for singular creatures.",
        commonMonsters = {},
        commonMonsterNote = "None.",
        dungeonLord = "The Unicorn",
    },
    [15] = {
        summary = "A far-realm crossroads market where spirits trade intangible pieces of mortal life.",
        sensory = {
            sights = "Crowded goblin stalls and spirits singing structures into existence.",
            sounds = "Inhuman trade chatter and excited invitations to buy.",
            smellTaste = "Intoxicating stall scents tied to memories.",
        },
        lighting = "Well lit by fires of many colors.",
        structures = "Outdoor-market cavern with tents, silks, and tapestries defining spaces.",
        commonMonsters = {
            "Servitor Imps", "Elf Cloneslugs", "Angels", "Devils", "Genii", "Daemons",
            "Goblins", "Dream Fairies",
        },
        dungeonLord = "The Curators",
    },
    [16] = {
        summary = "An impossible architectural infestation where idealized building-forms fold and rearrange.",
        sensory = {
            sights = "Many architectural styles jammed into improbable rooms.",
            sounds = "Beautiful, strange acoustics and distant grinding rearrangements.",
            smellTaste = "Strangely sterile air.",
        },
        lighting = "None.",
        structures = "Inconsistent chambers of black-painted pine, extinct logs, or fitted stone.",
        commonMonsters = {
            "Deconstruction Imps", "Gargoyles", "Dire Centipedes", "Prolapsedogs",
            "Inverted Horses", "Face Rats", "Non-Euclidean Snakes",
        },
        dungeonLord = "The Many-Angled Thing",
    },
    [17] = {
        summary = "A castle-scale clockwork mechanism whose alien orreries and temporal effects invite misuse.",
        sensory = {
            sights = "A huge flywheel tower with chain-bound counterweights.",
            sounds = "Loud clockwork whirring, clicking, and echoes of past conversations.",
            smellTaste = "A coppery licked-penny tang.",
        },
        lighting = "None.",
        structures = "Bronze machine supports, wooden halls, plaster walls, and arched doors.",
        commonMonsters = {
            "Clockwork Imps", "Clockwork Knights", "Intelligent Mice", "Blood Mists",
            "Degenerate Dwarves", "Oil Elementals",
        },
        dungeonLord = "Heuriko the Sorceress",
    },
    [18] = {
        summary = "A mithril mining colony and forge where truesilver sickness distorts minds and magic.",
        sensory = {
            sights = "Dull mithril veins, lava channels, and a dwarf-made forge.",
            sounds = "Mining tools, furnaces, arguments, impacts, laughter, and weeping.",
            smellTaste = "Chemical ozone.",
        },
        lighting = "Rooms are lit half the time by red-glass lamps; halls are unlit.",
        structures = "Man-made tunnels, natural caverns, sloped floors, wooden supports, and bridges.",
        commonMonsters = {
            "Hallucination Imps", "Argyric Underfolk", "Quicksilver Slimes", "Dire Ants",
            "Mutant Canaries",
        },
        dungeonLord = "The Truesilver Golem",
    },
    [19] = {
        summary = "A bright fungal cavern kingdom whose cold white light lures victims into nourishment.",
        sensory = {
            sights = "Caverns of changing size covered in anemone-like fungi.",
            sounds = "Water drips and mushrooms hiss spores.",
            smellTaste = "Damp earth, fishy spores, and mustard taste.",
        },
        lighting = "Bright LED-white light from bioluminescent mushrooms.",
        structures = "Bone-white pocked-coral cavern walls and floors.",
        commonMonsters = {
            "Spore-choked Imps", "Fungoids", "Dire Crabs", "Shrieker Mushrooms",
            "Polytechnic Polyspores", "Spore Zombies",
        },
        dungeonLord = "The Fruiting Mother",
    },
    [20] = {
        summary = "A city of dragon bones remade after the Well of Souls was stolen.",
        sensory = {
            sights = "Bone streets, open squares, a blood-filled ouroboros fountain, and fossil architecture.",
            sounds = "Dripping water, distant chimes, and deep ominous rumbling.",
            smellTaste = "Electrical-fire haze.",
        },
        lighting = "No native light, though goblins and orcs may carry torches.",
        structures = "Dry-stack bone walls, oyster-shell roads, fossil buildings, and fossil-wood doors.",
        commonMonsters = {
            "Keening Imps", "Goblins", "Orc Cultists", "Human Crusaders", "Bloody Cruciforms",
            "Shadows", "Panthers", "Sword Spiders", "Dire Rats", "Dragon Skeletons", "Dragons",
        },
        dungeonLord = "The Lamenting Lich",
    },
    [21] = {
        summary = "The central tomb and Well of Souls, where light is blasphemous and passages shift unseen.",
        sensory = {
            sights = "Partly worked stone caverns with gold-flecked religious allegory.",
            sounds = "Breathing air, pressure changes, and a yawning feeling.",
            smellTaste = "Warm sulfur and rotten eggs.",
        },
        lighting = "None; fire gutters and torchlight shrinks.",
        structures = "Partially worked cavern chambers with metal doors and complex locks.",
        commonMonsters = {
            "Katabatic Imps", "Ogre Spiders", "Statuary Golems", "Skeleton Jellies",
            "Lost Adventurers Undergoing Apotheosis", "Disassembling Angels", "Goblins", "Dragons",
        },
        dungeonLord = "His Majesty--THE WORM",
    },
}

for value, details in pairs(DUNGEON_SEED_DETAILS) do
    local seed = M.DUNGEON_SEEDS[value]
    if seed then
        for key, detail in pairs(details) do
            seed[key] = detail
        end
    end
end

local function copy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for key, child in pairs(value) do
        out[key] = copy(child)
    end
    return out
end

function M.getProcedureSteps()
    return {
        steps = copy(M.PROCEDURE_STEP_DETAILS),
        cadence = copy(M.PROCEDURE_CADENCE),
    }
end

function M.getDungeonSeed(value)
    if type(value) == "table" then
        value = value.value or value.cardValue or value.majorValue or value[1]
    end
    value = tonumber(value)
    if not value or value ~= math.floor(value) then
        return nil
    end
    return copy(M.DUNGEON_SEEDS[value])
end

function M.getTrapExample(value)
    if type(value) == "table" then
        value = value.value or value.index or value.example or value[1]
    end
    value = tonumber(value)
    if not value or value ~= math.floor(value) then
        return nil
    end
    return copy(M.TRAP_EXAMPLES[value])
end

function M.getTutorialDungeonExample(value)
    if type(value) == "table" then
        value = value.id or value.key or value.name or value[1]
    end
    local key
    if type(value) == "string" then
        key = value:gsub("^%s+", ""):gsub("%s+$", "")
    elseif value ~= nil then
        key = tostring(value)
    end
    key = key or "tomb_of_golden_ghosts"
    key = key:gsub("%s+", "_"):lower()
    if key == "tomb" or key == "golden_ghosts" or key == "the_tomb_of_golden_ghosts" then
        key = "tomb_of_golden_ghosts"
    end
    if key ~= "tomb_of_golden_ghosts" then
        return nil
    end
    return copy(M.TUTORIAL_DUNGEON_EXAMPLE)
end

M.ORIGIN_LORE_GUIDANCE = {
    traps = "Use traps to reflect what they guard or who made them.",
    treasure = "Use treasure to depict historical or recent Underworld events.",
    ruins = "Use ruins, inscriptions, and partial translations to expose old truths.",
    languages = "Use unknown or forgotten languages as discoverable lore.",
}

M.ROOM_REASON_ORDER = {
    "explore",
    "flee",
    "talk",
    "fight",
    "breathe_easy",
    "experiment",
    "surprise",
    "return",
}

M.ROOM_REASON_LABELS = {
    explore = "A reason to explore",
    flee = "A reason to flee",
    talk = "A reason to talk",
    fight = "A reason to fight",
    breathe_easy = "A reason to breathe easy",
    experiment = "A reason to experiment",
    surprise = "A reason to be surprised",
    ["return"] = "A reason to return",
}

M.ROOM_REASON_ALIASES = {
    exploration = "explore",
    reward = "explore",
    boon = "explore",
    treasure = "explore",
    escape = "flee",
    danger = "flee",
    overwhelm = "flee",
    social = "talk",
    parley = "talk",
    dialogue = "talk",
    conversation = "talk",
    combat = "fight",
    hostile = "fight",
    breathe = "breathe_easy",
    rest = "breathe_easy",
    safe = "breathe_easy",
    safe_space = "breathe_easy",
    experiment = "experiment",
    interact = "experiment",
    weird_feature = "experiment",
    be_surprised = "surprise",
    surprise = "surprise",
    secret = "surprise",
    discovery = "surprise",
    clue = "surprise",
    return_hook = "return",
    revisit = "return",
    come_back = "return",
}

M.MEATGRINDER_BANDS = {
    {
        key = "torches_gutter",
        label = "Torches gutter",
        startValue = 1,
        endValue = 5,
        aliases = { "torches", "lights", "hunger", "nothing" },
        allowSingleton = true,
    },
    {
        key = "curiosity",
        label = "Curiosity",
        startValue = 6,
        endValue = 10,
        aliases = { "curiosities" },
    },
    {
        key = "travel_event",
        label = "Travel event",
        startValue = 11,
        endValue = 15,
        aliases = { "travelEvents", "travel_events", "travel" },
    },
    {
        key = "random_encounter",
        label = "Random encounter",
        startValue = 16,
        endValue = 20,
        aliases = { "randomEncounters", "random_encounters", "encounters" },
    },
    {
        key = "quest_rumor",
        label = "Quest rumor",
        startValue = 21,
        endValue = 21,
        aliases = { "questRumor", "quest", "rumor" },
        singleton = true,
    },
}

local MEATGRINDER_CARD_LABELS = {
    "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X",
    "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX", "XXI",
}

M.MEATGRINDER_TEMPLATE = {}
for _, band in ipairs(M.MEATGRINDER_BANDS) do
    for value = band.startValue, band.endValue do
        local placeholder = band.label
        if band.key == "curiosity" then
            placeholder = "[Curiosity]"
        elseif band.key == "travel_event" then
            placeholder = "[Travel event]"
        elseif band.key == "random_encounter" then
            placeholder = "[Random encounter]"
        elseif band.key == "quest_rumor" then
            placeholder = "[Quest Rumor]"
        end
        M.MEATGRINDER_TEMPLATE[value] = {
            value = value,
            cardName = MEATGRINDER_CARD_LABELS[value],
            categoryKey = band.key,
            categoryLabel = band.label,
            placeholder = placeholder,
            bandStart = band.startValue,
            bandEnd = band.endValue,
        }
    end
end

function M.getMeatgrinderTemplate()
    return copy(M.MEATGRINDER_TEMPLATE)
end

M.ROOM_FEATURE_PROMPTS = {
    [1] = { name = "Circle of power", themes = { "gate", "far_realm", "dangerous_magic" } },
    [2] = { name = "Altar", themes = { "sacrifice", "divinity", "prayer" } },
    [3] = { name = "Cage", themes = { "prisoner", "constraint", "judgement" } },
    [4] = { name = "Throne", themes = { "authority", "control", "curse" } },
    [5] = { name = "Idol", themes = { "god", "treasure", "trap" } },
    [6] = { name = "Library", themes = { "knowledge", "translation", "fragility" } },
    [7] = { name = "Elevator", themes = { "vertical_travel", "activation", "level_connection" } },
    [8] = { name = "Hearthfire", themes = { "safe_space", "camp", "hope" } },
    [9] = { name = "Merchant", themes = { "trade", "relationship", "meatgrinder" } },
    [10] = { name = "Machine", themes = { "mechanism", "repair", "state_change" } },
    [11] = { name = "False tomb", themes = { "secret", "grave_robbery", "punishment" } },
    [12] = { name = "Magic wall", themes = { "barrier", "gate", "artifact" } },
    [13] = { name = "Sepulcher", themes = { "dead", "grave_goods", "curse" } },
    [14] = { name = "Fountain", themes = { "enchanted_water", "boon", "curse" } },
    [15] = { name = "Statue", themes = { "culture", "puzzle", "portal" } },
    [16] = { name = "Oubliette", themes = { "pit", "forgotten_prisoner", "clue" } },
    [17] = { name = "Mirror", themes = { "reflection", "trap", "portal" } },
    [18] = { name = "Painting", themes = { "art", "secret", "enchantment" } },
    [19] = { name = "River", themes = { "barrier", "transport", "uncanny_water" } },
    [20] = { name = "Waterwheel", themes = { "river_power", "lever", "dungeon_state" } },
    [21] = { name = "Well", themes = { "strange_liquid", "denizen", "wish" } },
}

M.TRAP_EXAMPLES = {
    [1] = {
        id = "mysterious_tower_acid_lake",
        name = "Mysterious tower, acid lake",
        principle = "Make the reward tempting and the danger obvious while leaving many possible solutions.",
        guarded = "mysterious island tower",
        danger = "bright-green acid lake",
        telegraphChannels = { "sight", "touch" },
        playerExperiments = {
            "test the water with items",
            "touch an item to the surface to learn the Notch risk",
        },
        solutions = {
            "cross with magic such as Gust of Wind or Defy Depths",
            "use flying monsters or other dungeon resources",
            "invent another safe crossing method",
        },
        consequences = {
            "living creatures that fall in die",
            "immersed ordinary items are Destroyed",
            "careful contact Notches items",
        },
    },
    [2] = {
        id = "arrow_trap",
        name = "Arrow trap",
        principle = "Broadcast a stock trap clearly and give players interactable parts.",
        guarded = "passage beyond the trapped hall",
        danger = "wall holes and a pressure plate fire arrows",
        telegraphChannels = { "sight", "sound" },
        playerExperiments = {
            "inspect wall holes",
            "listen for the pressure plate click",
        },
        solutions = {
            "drop flat or leap away after the click",
            "trigger the plate early with a heavy object",
            "leap over the plate",
            "plug the holes with alchemical glue",
        },
        consequences = {
            "failed reaction or hesitation deals a Wound",
            "the trap fires once until reset",
        },
    },
    [3] = {
        id = "quicksand",
        name = "Quicksand",
        principle = "Use a familiar hidden hazard that traps someone and gives the rest of the guild work to do.",
        guarded = "safe passage through swampy ground",
        danger = "swallowing swamp ground",
        telegraphChannels = { "sight", "touch" },
        playerExperiments = {
            "move carefully through suspect ground",
            "probe the terrain with tools",
        },
        solutions = {
            "use rope or a similar tool to get leverage",
            "have other guild members pull the victim free",
        },
        consequences = {
            "the first careless marcher gets stuck",
            "rope grants favor to the rescue test",
        },
    },
    [4] = {
        id = "electrified_chest",
        name = "Electrified chest",
        principle = "Use nonvisual sensory clues to broadcast a hidden danger around an obvious reward.",
        guarded = "metal chest on a plinth",
        danger = "electrified plinth and chest",
        telegraphChannels = { "smell", "touch" },
        playerExperiments = {
            "notice ozone",
            "notice hair standing on end near the plinth",
        },
        solutions = {
            "knock the chest off the plinth from reach",
            "open or manipulate it at a distance with magic",
        },
        consequences = {
            "touching the plinth or chest deals Piercing damage",
            "rough disarming may break the contents",
        },
    },
    [5] = {
        id = "big_rolling_boulder",
        name = "Big rolling boulder",
        principle = "Telegraph the trigger with staging so players can plan before the trap starts moving.",
        guarded = "Jarl Ninebones's grave goods",
        danger = "devil statue throws a massive boulder",
        telegraphChannels = { "sight", "language" },
        playerExperiments = {
            "read warnings on the sarcophagus",
            "interpret the statue's throwing pose",
        },
        solutions = {
            "hide in the sarcophagus",
            "block the boulder with a sturdy magical wall",
            "get out of the path before opening the tomb",
        },
        consequences = {
            "each adventurer in the path tests Pentacles",
            "failure deals Critical damage",
        },
    },
    [6] = {
        id = "invisible_path",
        name = "Invisible path",
        principle = "Make the danger obvious, hide the route, and allow players to leave or investigate.",
        guarded = "door across an apparently bottomless chasm",
        danger = "falling into the chasm",
        telegraphChannels = { "sight", "touch" },
        playerExperiments = {
            "touch the air in front of the door",
            "tap ahead with a ten-foot pole",
            "mark the route with paint, ink, bugs, stones, or coins",
        },
        solutions = {
            "map the bridge by probing",
            "tie off with rope while testing the path",
            "use second sight or similar magic",
        },
        consequences = {
            "careless crossing risks the fall",
            "good methods reveal the safe bridge path",
        },
    },
    [7] = {
        id = "hungry_door",
        name = "Hungry door",
        principle = "Use a gross avoidable barrier that converts progress into resource attrition or clever play.",
        guarded = "passage behind an animate mouth-door",
        danger = "chewing door-mouth",
        telegraphChannels = { "sight", "sound" },
        playerExperiments = {
            "listen to the door demand food",
            "test whether damage or feeding changes its behavior",
        },
        solutions = {
            "feed it five rations",
            "feed it a sizable living creature",
            "bring it captured dungeon prey",
            "smash it with battering-ram scale force",
        },
        consequences = {
            "small tools are chewed and spit out",
            "chewing can Notch items or Wound limbs",
        },
    },
    [8] = {
        id = "flooding_fish_statue",
        name = "Flooding fish statue",
        principle = "Make the reward so obvious that players suspect risk and can prepare before taking it.",
        guarded = "blue sapphire in a fish statue's mouth",
        danger = "sealed room flooding from the statue",
        telegraphChannels = { "sight", "sound" },
        playerExperiments = {
            "inspect the pool and statue before taking the gem",
            "plan positions and tools before looting",
        },
        solutions = {
            "put the gem or an equivalent plug back",
            "smash an exit with a crowbar or similar tool",
            "drain the water with Portable Hole",
        },
        consequences = {
            "the guild has three total actions before drowning",
            "failed escape attempts waste actions",
        },
    },
    [9] = {
        id = "pyrotechnic_mushrooms",
        name = "Pyrotechnic mushrooms",
        principle = "Use an obvious environmental danger whose interaction with light changes the problem.",
        guarded = "passage through the mushroom-choked hall",
        danger = "flammable mushroom gas and naked flame",
        telegraphChannels = { "sight", "smell", "sound" },
        playerExperiments = {
            "notice flames sputter near the mushrooms",
            "notice the sulfur smell",
        },
        solutions = {
            "extinguish flames before passing",
            "accept darkness and solve what lies beyond without light",
        },
        consequences = {
            "active flames trigger an explosion",
            "light carriers catch fire and take a Wound",
            "a flammable belt or pack item is Notched each action until extinguished",
            "adjacent marchers also take a Wound",
        },
    },
}

M.TUTORIAL_DUNGEON_EXAMPLE = {
    id = "tomb_of_golden_ghosts",
    name = "The Tomb of Golden Ghosts",
    purpose = "A focused tutorial example for building one Underworld dungeon level.",
    scope = {
        focusedSteps = { "create_maps", "write_room_descriptions", "create_meatgrinder" },
        assumes = {
            "Underworld origins are already decided",
            "Underworld layout is already decided",
        },
        seedUse = "No specific dungeon seed is used, though the level could fit the Necropolis of Ot or the City of Ruin.",
        tutorialQuest = "Find the Tripartite's crown",
        playerFraming = "This is your quest, this is the dungeon, and this is a small example to try the game out.",
    },
    mapPlan = {
        mapSource = "Premade Dyson Logos map",
        levelNumber = 1,
        roomKeyPattern = "1xx",
        gmMap = "Fully keyed map with secret doors and rooms.",
        playerMap = "Player version omits secret doors and secret rooms.",
        playerMapOmissions = { "secret doors", "secret rooms", "room contents" },
    },
    roomDefaults = {
        lighting = "dark",
        structure = "natural limestone caverns unless otherwise noted",
        sounds = "a river churning in the north",
        smellTaste = "damp earth",
    },
    brainstorm = {
        premise = "A magical royal tomb has been excavated and occupied by a pair of brain spiders.",
        factions = {
            {
                id = "brain_spiders",
                name = "Brain spiders",
                members = { "Kodi Dove-devourer", "Glaura Glossolalia" },
                wants = {
                    "feel smart",
                    "grow their power in the Underworld",
                    "hatch a new clutch of brain-spider eggs",
                    "gain new magical power",
                },
                tableTone = "Saturday morning cartoon villains with illusion-casting mad genius energy.",
            },
            {
                id = "golden_ghosts",
                name = "Golden ghosts",
                members = { "Aurumius Dynasty", "Primus", "Secundus", "Tertius" },
                wants = {
                    "their tomb treasure returned",
                    "the brain spiders destroyed",
                    "their seven death masks returned",
                },
                tableTone = "mute royal ghosts made of pure gold and trapped by spider webs.",
            },
        },
        supportingElements = {
            "puppet-mummies rigged from excavated corpses",
            "slime kept in a pit as a garbage disposal",
            "giant centipedes as natural dungeon headaches",
            "Book Worm, a sentient centipede who speaks Vetus",
            "star-child in Glaura's laboratory",
            "hidden safe sanctum behind mural secret doors",
        },
    },
    checklistReasons = {
        talk = {
            "brain spiders can be negotiated with if flattered or offered power",
            "golden ghosts want their masks and treasure returned",
            "Book Worm gives rumors if brought books",
        },
        fight = {
            "puppet-mummies guard room 109",
            "dire centipedes block room 103",
            "slime attacks in the pit of bones",
        },
        explore = {
            "the Tripartite's crown gives the level a concrete quest treasure",
            "tomb treasure includes death masks, scarabs, books, brandy, keys, oil, and an idol",
        },
        experiment = {
            "the weird sleeping star-child can trigger environmental maleficence",
            "murals, latches, symbols, webs, moss, and the crown trap all reward interaction",
        },
        ["return"] = {
            "other Underworld factions may later want someone to steal or eat the star-child",
            "recurring Tripartite symbols can make later lore point back to this level",
        },
        flee = {
            "unappeased freed golden ghosts are treated as a natural disaster, not fair enemies",
        },
        surprise = {
            "mural secret doors reward pattern recognition",
            "Kodi can control puppet-mummies from behind an illusory wall",
            "the hidden sanctum changes the map once found",
        },
        breathe_easy = {
            "the still-secret sanctum is safe for now",
        },
    },
    authoringTechniques = {
        "name factions and creatures so repeated concepts are easier to remember",
        "broadcast secrets through repeated mural patterns",
        "use treasure as art, jewelry, academic works, relics, and beasts instead of only coins",
        "put lots of treasure behind traps to incentivize exploration",
        "use recurring symbolism so later lore can create epiphanies",
        "handle some threats narratively instead of forcing everything into a stat block",
        "interpret Meatgrinder events so they harmonize with the current room",
        "separate landmark, hidden, and secret information",
    },
    meatgrinderProcess = {
        firstEntries = {
            "torches gutter for unlit dungeon pressure",
            "quest rumor for the next quest step in dungeon context",
        },
        randomEncounters = {
            "puppet-mummies controlled by Kodi from behind an illusory wall",
            "Glaura weaving webs and escaping after a telepathic warning",
            "mute weeping golden ghost communicating by charades",
            "Finch and Justin Pepperoni chased by discard-count centipedes",
            "adventurers-minus-one giant centipedes that block passage but do not pursue",
        },
        travelEvents = {
            "centipede-churned quicksand targets the first human, orc, or troll-stature adventurer",
            "illusory walls hide all exits except the entrance just used",
            "web-choked room requires careful clearing or three torch flickers",
            "trap webs hoist the first marcher 20 feet into the air after a failed Cups test",
            "earthquake makes every player test Pentacles or take a Wound",
        },
        curiosities = {
            "faint shreds of cobwebs",
            "something golden vanishing around a corner",
            "black fewmets that lore reveals as centipede scat",
            "distant earthquake rumble",
            "cold unquiet-dead wind",
        },
        commentary = {
            "marching order and stature are useful travel-event targeting tools",
            "good solutions simply work while risky solutions call for tests and consequences",
            "personal discomfort such as gross quicksand can justify Stressed",
            "obvious illusions invite investigation rather than conceal the whole problem",
            "make resource costs such as torch flickers clear up front",
            "reward careful movement by making some Meatgrinder events avoidable",
            "vary test suits across travel events",
            "include at least one whole-guild hazard to make lingering feel dangerous",
        },
    },
    statPlan = {
        options = {
            "use an example creature from Appendix C and rebrand if necessary",
            "combine a theme and threat, then adjust to suit the room",
            "make up a bespoke stat block",
        },
        tombChoices = {
            "slime and brain spiders use Appendix C examples",
            "brain spiders gain the Sorcery doom from the Strategist template",
            "puppet-mummies rebrand zombie stats as nonliving, non-undead marionette corpses",
            "dire centipedes combine the beast theme with the minion threat",
        },
    },
}

local ROOM_FEATURE_PROMPT_DETAILS = {
    [1] = {
        summary = "A leyline site or magical gate whose power is beyond one mortal sorcerer.",
        exampleHooks = {
            "dangerous travel gate",
            "harmonization puzzle",
            "far-realm boundary",
        },
    },
    [2] = {
        summary = "A sacrificial table shaped by its divinity, where prayers or offerings carry extra weight.",
        exampleHooks = {
            "living sacrifice",
            "affliction cure or divine bargain",
            "blood-stained theology",
        },
    },
    [3] = {
        summary = "A prison, gibbet, or constraint that raises questions about guilt, justice, and release.",
        exampleHooks = {
            "prisoner truth or lie",
            "simple-looking restraint",
            "crime or unjust sentence",
        },
    },
    [4] = {
        summary = "An ancient seat of rule that grants control or awareness, usually with a curse or trap.",
        exampleHooks = {
            "dungeon feature control",
            "special awareness",
            "curse for unworthy sitter",
        },
    },
    [5] = {
        summary = "A huge idol of a strange god, fossil power, or forgotten cult with tempting valuables.",
        exampleHooks = {
            "valuable eyes or offerings",
            "divine hazard",
            "colossal fossil god",
        },
    },
    [6] = {
        summary = "A hoard of books, scrolls, tablets, or stranger records that rewards careful study.",
        exampleHooks = {
            "translation time",
            "fragile records",
            "esoteric research clue",
        },
    },
    [7] = {
        summary = "A platform, chamber, or mechanism that moves through the dungeon in useful or strange ways.",
        exampleHooks = {
            "vertical level connection",
            "activation cost",
            "strange operator or engine",
        },
    },
    [8] = {
        summary = "A safe-looking remnant of old camps where rekindled fire can restore hope.",
        exampleHooks = {
            "safe camp ember",
            "Resolve or recovery boon",
            "past guild traces",
        },
    },
    [9] = {
        summary = "A dungeon trader whose essential goods, mobility, or protection make commerce strange.",
        exampleHooks = {
            "inflated essential supplies",
            "mobile stock",
            "curse-backed protection",
        },
    },
    [10] = {
        summary = "An ancient mechanism with unknown purpose, broken logic, or imperfect output.",
        exampleHooks = {
            "missing part or power source",
            "unknown purpose",
            "component output",
        },
    },
    [11] = {
        summary = "A decoy burial place that hides true chambers behind puzzles, secrets, or punishment.",
        exampleHooks = {
            "punishing grave-robber choice",
            "secret door to true tomb",
            "deadly but telegraphed trap",
        },
    },
    [12] = {
        summary = "A magical barrier that gates passage until a key, token, generator, or workaround is found.",
        exampleHooks = {
            "token or key passage",
            "disable generator",
            "alternate bypass by blindness or shroud",
        },
    },
    [13] = {
        summary = "A true burial chamber with grave goods, restless history, curses, or corpse-borne hazards.",
        exampleHooks = {
            "heavy sarcophagus",
            "grave-goods risk",
            "corpse-borne clue or disease",
        },
    },
    [14] = {
        summary = "An enchanted spring or basin activated by drinking, bathing, or dipping objects into it.",
        exampleHooks = {
            "boon with side effect",
            "item dipping",
            "speaking outlet",
        },
    },
    [15] = {
        summary = "A graven image that reveals culture, worldview, clues, puzzles, or portals.",
        exampleHooks = {
            "rotating statue puzzle",
            "creator worldview clue",
            "portal alignment",
        },
    },
    [16] = {
        summary = "A deep forgotten prison reached by trapdoor, often preserving remains and last messages.",
        exampleHooks = {
            "trapdoor access",
            "abandoned prisoner remains",
            "blood-written clue",
        },
    },
    [17] = {
        summary = "A magical reflection that can trap, duplicate, transport, or redirect what it shows.",
        exampleHooks = {
            "reflection trap",
            "body reset or duplicate",
            "light-redirection puzzle",
        },
    },
    [18] = {
        summary = "A painting, tapestry, fresco, or mosaic that hides a secret or explains nearby magic.",
        exampleHooks = {
            "painted secret door",
            "missing detail completes magic",
            "puzzle context",
        },
    },
    [19] = {
        summary = "An uncanny river whose water is dangerous at first but may become a route later.",
        exampleHooks = {
            "dangerous water property",
            "crossing problem",
            "vehicle or guide unlocks route",
        },
    },
    [20] = {
        summary = "A river-powered mechanism that changes doors, bridges, lights, or other dungeon states.",
        exampleHooks = {
            "one flow controls several features",
            "door or bridge state",
            "lighting or machinery state",
        },
    },
    [21] = {
        summary = "A well filled with something stranger than water and often claimed by a resident.",
        exampleHooks = {
            "strange liquid",
            "resident or guardian",
            "wish or bargain scam",
        },
    },
}

for value, details in pairs(ROOM_FEATURE_PROMPT_DETAILS) do
    local prompt = M.ROOM_FEATURE_PROMPTS[value]
    if prompt then
        for key, detail in pairs(details) do
            prompt[key] = detail
        end
    end
end

M.FACTION_AUTHORING_GUIDANCE = {
    wants = "Record what the faction wants so role-play can create leverage.",
    doesNotWant = "Record what the faction does not want so hostility has motives.",
    languages = "Plan spoken languages to reward linguistic range during social encounters.",
    languageContext = "Record contextually different information or hooks revealed through specific languages.",
}

M.TREASURE_AUTHORING_GUIDANCE = {
    form = "Make treasure more specific than loose coins: art, jewelry, weapons, clothing, texts, beasts, relics, or other concrete objects.",
    lore = "Use treasure to depict historical or recent events, factions, makers, minting, inscriptions, or provenance.",
    value = "Record a guessed sale value or pricing note; the rulebook gives no fixed payout budget.",
    placement = "Place treasures in keyed rooms so rewards and risks can be found on the map.",
    guarded = "Put major treasure behind traps, hazards, locks, factions, or other meaningful risks when appropriate.",
}

M.ROOM_CONTENT_AUTHORING_GUIDANCE = {
    placement = "Place entities, traps, treasures, monsters, and other permanent room content on the keyed map.",
}

M.DENIZEN_AUTHORING_GUIDANCE = {
    placement = "Place permanent denizens in specific rooms; non-permanent encounters belong on the Meatgrinder.",
    stats = "Reference or author the denizen's stat block so the room can be run at the table.",
    motives = "Record what the denizen wants, likes, dislikes, or protects so play can produce choices beyond fighting.",
    tactics = "Record tactics or special behavior for how the denizen acts when challenged.",
}

M.ROOM_NOTE_GUIDANCE = {
    interactableKeywords = "Mark important or interactable words so the GM can scan what is initially described.",
    nestedDiscoveries = "Nest information that appears only after players interact with or investigate the room.",
}

M.SAFE_ROOM_AUTHORING_GUIDANCE = {
    safeRooms = "Mark a handful of rooms as safe spaces for camping, holding a line, ambushes, or quiet scheming.",
    lookAndFeel = "Give each safe room a terse word-or-two look and feel note.",
}

M.FLEE_THREAT_AUTHORING_GUIDANCE = {
    threat = "Place large, overwhelming, or magically potent creatures or forces so not every fight can be won honestly.",
}

M.FIGHT_DISPOSITION_AUTHORING_GUIDANCE = {
    disposition = "Place creatures whose default Disposition is aggressive so some conflicts naturally become fights.",
}

M.EXPLORE_REWARD_AUTHORING_GUIDANCE = {
    reward = "Give the dungeon something players want: gold, equipment, information, helpful characters, or beneficial features.",
}

M.EXPERIMENT_FEATURE_AUTHORING_GUIDANCE = {
    feature = "Create big, obvious, weird features that players can interact with, learn, and turn to their advantage.",
}

M.SURPRISE_SECRET_AUTHORING_GUIDANCE = {
    secret = "Create secrets that are not obvious at first glance, then add clues that point to them.",
}

M.RETURN_HOOK_AUTHORING_GUIDANCE = {
    hook = "Create reasons to revisit rooms or levels by tying progress to things found elsewhere in the megadungeon.",
}

M.TALK_ENCOUNTER_AUTHORING_GUIDANCE = {
    encounter = "Give talk rooms a concrete speaker or faction plus wants, don't-wants, leverage, plans, rumors, or language context.",
}

M.MEANINGFUL_CHOICE_AUTHORING_GUIDANCE = {
    signal = "Make rewards and risks clear with clues, telegraphs, warnings, bodies, sensory details, or other readable evidence.",
}

local ROOM_REASON_FIELDS = {
    explore = { "reasonToExplore", "reason_to_explore", "exploreReason" },
    flee = { "reasonToFlee", "reason_to_flee", "fleeReason" },
    talk = { "reasonToTalk", "reason_to_talk", "talkReason" },
    fight = { "reasonToFight", "reason_to_fight", "fightReason" },
    breathe_easy = {
        "reasonToBreatheEasy",
        "reason_to_breathe_easy",
        "breatheEasyReason",
        "safeReason",
    },
    experiment = { "reasonToExperiment", "reason_to_experiment", "experimentReason" },
    surprise = {
        "reasonToBeSurprised",
        "reason_to_be_surprised",
        "surpriseReason",
    },
    ["return"] = { "reasonToReturn", "reason_to_return", "returnReason" },
}

local function trimString(value)
    if type(value) ~= "string" then
        return nil
    end
    local text = value:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return nil
    end
    return text
end

local function addText(list, value)
    local text = trimString(value)
    if text then
        list[#list + 1] = text
    end
end

local function addUniqueText(list, seen, value)
    local text = trimString(value)
    if text and not seen[text] then
        seen[text] = true
        list[#list + 1] = text
    end
end

local function normalizeTextList(...)
    local list = {}
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if type(value) == "table" then
            for _, entry in ipairs(value) do
                if type(entry) == "table" then
                    addText(list, entry.text or entry.question or entry.description or entry.name)
                else
                    addText(list, entry)
                end
            end
            for key, entry in pairs(value) do
                if type(key) ~= "number" then
                    if type(entry) == "table" then
                        addText(list, entry.text or entry.question or entry.description or entry.name)
                    else
                        addText(list, entry)
                    end
                end
            end
        else
            addText(list, value)
        end
    end
    return list
end

local function normalizeIdentifier(value)
    local text = trimString(value)
    if not text then
        return nil
    end
    text = text:lower()
    text = text:gsub("[^%w]+", "_")
    text = text:gsub("^_+", ""):gsub("_+$", "")
    if text == "" then
        return nil
    end
    return text
end

local function normalizeReasonKey(value)
    local key = normalizeIdentifier(value)
    if not key then
        return nil
    end
    key = key:gsub("^a_reason_to_be_", "")
    key = key:gsub("^a_reason_to_", "")
    key = key:gsub("^reason_to_be_", "")
    key = key:gsub("^reason_to_", "")
    key = key:gsub("^reason_", "")
    key = key:gsub("^to_", "")
    return M.ROOM_REASON_ALIASES[key] or (M.ROOM_REASON_LABELS[key] and key) or nil
end

function M.recordOrigins(opts)
    opts = opts or {}

    local truths = normalizeTextList(
        opts.truth,
        opts.truths,
        opts.nature,
        opts.underworldNature,
        opts.foundation
    )
    if #truths == 0 then
        return nil, "Underworld truth required"
    end

    local originalPurposes = normalizeTextList(
        opts.originalPurpose,
        opts.originalPurposes,
        opts.intendedUse,
        opts.pastPurpose,
        opts.pastPurposes,
        opts.purpose
    )
    if #originalPurposes == 0 then
        return nil, "Original purpose required"
    end

    local currentOccupiers = normalizeTextList(
        opts.currentOccupiers,
        opts.currentOccupation,
        opts.occupiers,
        opts.usurpers,
        opts.explorers
    )
    local contradiction = trimString(opts.occupationContradiction or opts.contradiction)
    local contradictionFlag = opts.currentOccupiersContradictOriginalPurpose or
        opts.contradictsOriginalPurpose
    if not contradiction and contradictionFlag == true then
        contradiction = "Current occupiers contradict the Underworld's intended use."
    end
    if #currentOccupiers == 0 and not contradiction then
        return nil, "Current occupation contradiction required"
    end
    if not contradiction then
        contradiction = "Current occupiers contradict the Underworld's intended use."
    end

    local openQuestions = normalizeTextList(
        opts.openQuestions,
        opts.questions,
        opts.mysteries,
        opts.openEndedQuestions
    )
    if #openQuestions == 0 then
        return nil, "Open-ended questions required"
    end

    local gmSecret = opts.gmSecret
    if gmSecret == nil then
        gmSecret = opts.playerFacing ~= true
    end
    local requiresSecrecy = opts.requiresSecrecy
    if requiresSecrecy == nil then
        requiresSecrecy = gmSecret
    end

    local record = {
        step = "origins",
        truth = truths[1],
        truths = truths,
        originalPurpose = originalPurposes[1],
        originalPurposes = originalPurposes,
        currentOccupiers = currentOccupiers,
        occupationContradiction = contradiction,
        currentOccupiersContradictOriginalPurpose = true,
        openQuestions = openQuestions,
        loreHooks = copy(opts.loreHooks or opts.dungeonLore or opts.lore or {}),
        dungeonLoreGuidance = copy(M.ORIGIN_LORE_GUIDANCE),
        gmSecret = gmSecret,
        requiresSecrecy = requiresSecrecy,
        playerFacing = opts.playerFacing == true,
        playerFacingSummary = trimString(opts.playerFacingSummary),
        readyForLayout = true,
    }

    return record, "underworld_origins_recorded", {
        origins = record,
        readyForLayout = true,
        requiredPrompts = {
            "truth",
            "original_purpose",
            "current_occupation_contradiction",
            "open_questions",
        },
        result = "underworld_origins_recorded",
    }
end

function M.validateOrigins(opts)
    local record, reason, detail = M.recordOrigins(opts)
    if not record then
        return false, reason
    end
    return true, "underworld_origins_valid", detail
end

local function addRoomReason(detail, key, source, note)
    if not key or detail.reasonFlags[key] then
        return
    end
    detail.reasonFlags[key] = true
    detail.reasons[#detail.reasons + 1] = key
    detail.reasonDetails[key] = {
        key = key,
        label = M.ROOM_REASON_LABELS[key],
        source = source,
        note = trimString(note),
    }
end

local function collectReasonValue(detail, rawKey, value, source)
    if value == nil or value == false then
        return
    end
    local key = normalizeReasonKey(rawKey)
    if not key then
        return
    end
    local note
    if type(value) == "table" then
        if value.enabled == false or value.present == false then
            return
        end
        note = value.note or value.description or value.text or value.reason
    elseif type(value) == "string" then
        note = value
    end
    addRoomReason(detail, key, source, note)
end

local function collectReasonCollection(detail, collection, source)
    if type(collection) ~= "table" then
        return
    end
    for _, value in ipairs(collection) do
        if type(value) == "table" then
            collectReasonValue(detail, value.key or value.reason or value.type or value[1], value, source)
        else
            collectReasonValue(detail, value, true, source)
        end
    end
    for key, value in pairs(collection) do
        if type(key) == "string" then
            collectReasonValue(detail, key, value, source)
        end
    end
end

local function inferFeatureReasons(detail, room)
    for _, feature in ipairs(room.features or {}) do
        local featureType = normalizeIdentifier(feature.type or feature.category)
        if featureType == "treasure" or feature.loot or feature.boon then
            addRoomReason(detail, "explore", "features", feature.description)
        elseif featureType == "hazard" or feature.trap or feature.overwhelming then
            addRoomReason(detail, "flee", "features", feature.description)
        elseif featureType == "creature" or feature.npc or feature.faction then
            if feature.defaultDisposition == "aggressive" or feature.hostile == true then
                addRoomReason(detail, "fight", "features", feature.description)
            else
                addRoomReason(detail, "talk", "features", feature.description)
            end
        elseif featureType == "experiment" or featureType == "mechanism" or featureType == "curiosity" then
            addRoomReason(detail, "experiment", "features", feature.description)
        end
        if feature.hidden_description or feature.secrets or feature.reveal_connection then
            addRoomReason(detail, "surprise", "features", feature.hidden_description or feature.secrets)
        end
        if feature.safe == true or feature.defensible == true or feature.shelter == true then
            addRoomReason(detail, "breathe_easy", "features", feature.description)
        end
        if feature.returnHook or feature.requiresOtherLevel or feature.unlocksLater then
            addRoomReason(detail, "return", "features", feature.returnHook or feature.description)
        end
    end
end

local function collectRoomReasons(room, opts)
    local detail = {
        roomId = room.id,
        roomName = room.name,
        reasons = {},
        reasonDetails = {},
        reasonFlags = {},
    }

    collectReasonCollection(detail, room.reasons, "reasons")
    collectReasonCollection(detail, room.roomReasons, "roomReasons")
    collectReasonCollection(detail, room.checklist, "checklist")
    collectReasonCollection(detail, room.reasonChecklist, "reasonChecklist")
    collectReasonCollection(detail, room.tags, "tags")
    collectReasonCollection(detail, room.roomTags, "roomTags")

    for reason, fields in pairs(ROOM_REASON_FIELDS) do
        for _, field in ipairs(fields) do
            collectReasonValue(detail, reason, room[field], field)
        end
    end

    if opts.inferFromFeatures == true then
        inferFeatureReasons(detail, room)
    end

    return detail
end

local function sensoryValue(room, opts, key)
    local sensory = room.sensory or {}
    local defaults = opts.defaultSensory or opts.sensory or {}
    return trimString(room[key] or sensory[key] or defaults[key])
end

local function addTextEntries(list, seen, value)
    if value == nil or value == false then
        return
    end
    if type(value) ~= "table" then
        addUniqueText(list, seen, value)
        return
    end
    for _, entry in ipairs(value) do
        if type(entry) == "table" then
            addUniqueText(list, seen, entry.keyword or entry.word or entry.label or entry.name or
                entry.text or entry.description or entry.note)
        else
            addUniqueText(list, seen, entry)
        end
    end
    for key, entry in pairs(value) do
        if type(key) == "string" then
            if type(entry) == "table" then
                addUniqueText(list, seen, entry.keyword or entry.word or entry.label or entry.name or
                    entry.text or entry.description or entry.note or key)
            elseif entry ~= false then
                addUniqueText(list, seen, entry == true and key or entry)
            end
        end
    end
end

local function markdownBoldWords(text)
    local list = {}
    local seen = {}
    text = trimString(text)
    if not text then
        return list
    end
    for word in text:gmatch("%*%*([^*]+)%*%*") do
        addUniqueText(list, seen, word)
    end
    return list
end

local function markdownBulletLines(text)
    local list = {}
    local seen = {}
    text = trimString(text)
    if not text then
        return list
    end
    for line in text:gmatch("[^\r\n]+") do
        local bullet = line:match("^%s*[%-%*]%s+(.+)$")
        addUniqueText(list, seen, bullet)
    end
    return list
end

local function roomUsableNotes(room)
    local keywords = {}
    local keywordSeen = {}
    addTextEntries(keywords, keywordSeen, room.interactableKeywords or room.interactiveKeywords)
    addTextEntries(keywords, keywordSeen, room.boldWords or room.importantWords or room.keywords or
        room.keyedWords)
    addTextEntries(keywords, keywordSeen, room.interactables)
    for _, word in ipairs(markdownBoldWords(room.description or room.base_description or room.summary)) do
        addUniqueText(keywords, keywordSeen, word)
    end

    local discoveries = {}
    local discoverySeen = {}
    addTextEntries(discoveries, discoverySeen, room.nestedDetails or room.discoveryDetails or
        room.discoveries or room.investigationDetails or room.hiddenDetails or room.bulletPoints)
    addTextEntries(discoveries, discoverySeen, room.interactionDetails or room.examinationDetails)
    for _, bullet in ipairs(markdownBulletLines(room.notes or room.gmNotes or room.description)) do
        addUniqueText(discoveries, discoverySeen, bullet)
    end

    return {
        interactableKeywords = keywords,
        nestedDiscoveries = discoveries,
        hasInteractableKeywords = #keywords > 0,
        hasNestedDiscoveries = #discoveries > 0,
        guidance = M.ROOM_NOTE_GUIDANCE,
    }
end

local function roomSafeNote(room, detail)
    if type(room) ~= "table" then
        return nil
    end
    return trimString(room.safeRoomNote or room.safeNotes or room.safeDescription or room.lookAndFeel or
        room.basicLook or room.basicFeel or room.atmosphere or room.feel or
        (detail.reasonDetails.breathe_easy and detail.reasonDetails.breathe_easy.note))
end

local function roomSafetyRecord(room, detail)
    local explicitlySafe = room.safe == true or room.safeSpace == true or room.defensible == true or
        room.shelter == true or room.campSafe == true
    local reasonSafe = detail.reasonFlags.breathe_easy == true
    return {
        isSafe = explicitlySafe or reasonSafe,
        basis = explicitlySafe and "room_flag" or (reasonSafe and "breathe_easy_reason" or nil),
        note = roomSafeNote(room, detail),
        guidance = M.SAFE_ROOM_AUTHORING_GUIDANCE,
    }
end

local function addFleeThreatRecord(list, source, entry)
    if type(entry) ~= "table" then
        return
    end
    local scale = normalizeIdentifier(entry.threatScale or entry.scale or entry.size or entry.power)
    local kind = normalizeIdentifier(entry.fleeThreatType or entry.threatType or entry.category or entry.type)
    local large = entry.large == true or entry.huge == true or entry.gigantic == true or
        scale == "large" or scale == "huge" or scale == "giant" or scale == "gargantuan" or scale == "titanic"
    local overwhelming = entry.overwhelming == true or entry.unwinnable == true or
        entry.tooDangerous == true or entry.cannotBeDefeated == true or
        entry.honestCombatUnwinnable == true or scale == "overwhelming" or scale == "impossible"
    local magical = entry.magicallyPotent == true or entry.magical == true or entry.magic == true or
        entry.sorcerous == true or kind == "magical" or kind == "magically_potent"
    if not (large or overwhelming or magical) then
        return
    end
    list[#list + 1] = {
        source = source,
        name = trimString(entry.name or entry.id or entry.description or entry.summary),
        large = large,
        overwhelming = overwhelming,
        magical = magical,
        scale = scale,
        kind = kind,
    }
end

local function addFleeThreatEntries(list, source, entries)
    if type(entries) ~= "table" then
        return
    end
    if entries.name or entries.id or entries.description or entries.overwhelming or entries.large or
        entries.magicallyPotent then
        addFleeThreatRecord(list, source, entries)
        return
    end
    for _, entry in ipairs(entries) do
        addFleeThreatRecord(list, source, entry)
    end
end

local function roomFleeThreatRecord(room, detail)
    local threats = {}
    addFleeThreatRecord(threats, "room", room)
    addFleeThreatEntries(threats, "features", room.features)
    addFleeThreatEntries(threats, "denizens", room.denizens or room.creatures or room.monsters or room.npcs)
    return {
        hasFleeReason = detail.reasonFlags.flee == true,
        hasThreat = #threats > 0,
        threats = threats,
        guidance = M.FLEE_THREAT_AUTHORING_GUIDANCE,
    }
end

local function dispositionIsAggressive(value)
    local disposition = normalizeIdentifier(value)
    return disposition == "aggressive" or disposition == "hostile" or disposition == "attacks_on_sight"
end

local function addFightDispositionRecord(list, source, entry)
    if type(entry) ~= "table" then
        return
    end
    local disposition = entry.defaultDisposition or entry.startingDisposition or entry.disposition
    local aggressive = dispositionIsAggressive(disposition) or entry.aggressive == true or
        entry.hostile == true or entry.attacksOnSight == true
    if not aggressive then
        return
    end
    list[#list + 1] = {
        source = source,
        name = trimString(entry.name or entry.id or entry.description or entry.summary),
        disposition = disposition,
        hostile = entry.hostile == true,
        aggressive = aggressive,
        conflict = normalizeTextList(entry.worldviewConflict, entry.conflict, entry.seesAdventurersAsFood,
            entry.hunger, entry.hates),
    }
end

local function addFightDispositionEntries(list, source, entries)
    if type(entries) ~= "table" then
        return
    end
    if entries.name or entries.id or entries.description or entries.defaultDisposition or
        entries.startingDisposition or entries.disposition or entries.hostile or entries.aggressive then
        addFightDispositionRecord(list, source, entries)
        return
    end
    for _, entry in ipairs(entries) do
        addFightDispositionRecord(list, source, entry)
    end
end

local function roomFightDispositionRecord(room, detail)
    local dispositions = {}
    addFightDispositionRecord(dispositions, "room", room)
    addFightDispositionEntries(dispositions, "features", room.features)
    addFightDispositionEntries(dispositions, "denizens", room.denizens or room.creatures or room.monsters or
        room.npcs)
    return {
        hasFightReason = detail.reasonFlags.fight == true,
        hasAggressiveDisposition = #dispositions > 0,
        dispositions = dispositions,
        guidance = M.FIGHT_DISPOSITION_AUTHORING_GUIDANCE,
    }
end

local function addExploreRewardRecord(list, source, entry)
    if type(entry) ~= "table" then
        local text = trimString(entry)
        if text then
            list[#list + 1] = {
                source = source,
                description = text,
                kinds = { "reward" },
            }
        end
        return
    end

    local kinds = {}
    local function mark(kind, value)
        if value ~= nil and value ~= false then
            kinds[kind] = true
        end
    end
    local featureType = normalizeIdentifier(entry.type or entry.category or entry.kind)
    mark("gold", entry.gold or entry.coins or entry.currency)
    mark("equipment", entry.equipment or entry.gear or entry.item or entry.items or entry.magicItem)
    mark("information", entry.information or entry.info or entry.clue or entry.clues or entry.lore or
        entry.rumor or entry.rumors or entry.questHook)
    mark("helpful_character", entry.helpfulCharacter or entry.helpfulNpc or entry.ally or entry.teacher or
        entry.trainer)
    mark("beneficial_feature", entry.beneficialFeature or entry.boon or entry.boons or entry.healing or
        entry.reward or entry.rewards or entry.benefit or entry.benefits)
    if featureType == "treasure" or
        (source ~= "room" and (entry.treasure or entry.treasures or entry.loot)) then
        kinds.treasure = true
    end

    local listKinds = {}
    for kind, present in pairs(kinds) do
        if present then
            listKinds[#listKinds + 1] = kind
        end
    end
    table.sort(listKinds)
    if #listKinds == 0 then
        return
    end
    list[#list + 1] = {
        source = source,
        name = trimString(entry.name or entry.id),
        description = trimString(entry.description or entry.summary or entry.text),
        kinds = listKinds,
        questHook = trimString(entry.questHook or entry.quest),
    }
end

local function addExploreRewardEntries(list, source, entries)
    if entries == nil then
        return
    end
    if type(entries) ~= "table" then
        addExploreRewardRecord(list, source, entries)
        return
    end
    if entries.name or entries.id or entries.description or entries.reward or entries.boon or entries.treasure or
        entries.loot or entries.gold or entries.equipment or entries.information or entries.helpfulCharacter then
        addExploreRewardRecord(list, source, entries)
        return
    end
    for _, entry in ipairs(entries) do
        addExploreRewardRecord(list, source, entry)
    end
end

local function roomExploreRewardRecord(room, detail)
    local rewards = {}
    addExploreRewardRecord(rewards, "room", room)
    addExploreRewardEntries(rewards, "features", room.features)
    addExploreRewardEntries(rewards, "treasures", room.treasures or room.treasure or room.loot)
    addExploreRewardEntries(rewards, "denizens", room.denizens or room.creatures or room.monsters or room.npcs)
    return {
        hasExploreReason = detail.reasonFlags.explore == true,
        hasReward = #rewards > 0,
        rewards = rewards,
        guidance = M.EXPLORE_REWARD_AUTHORING_GUIDANCE,
    }
end

local function experimentValuePresent(value)
    if value == nil or value == false then
        return false
    end
    if trimString(value) then
        return true
    end
    return type(value) == "table" and next(value) ~= nil
end

local function experimentFeatureKind(kind)
    return kind == "experiment" or kind == "mechanism" or kind == "machine" or kind == "curiosity" or
        kind == "weird_feature" or kind == "magical_feature" or kind == "apparatus" or kind == "idol" or
        kind == "fountain"
end

local function addExperimentFeatureRecord(list, source, entry)
    if type(entry) ~= "table" then
        local text = trimString(entry)
        if text then
            list[#list + 1] = {
                source = source,
                description = text,
                missing = { "big_obvious_weird", "interaction", "outcome" },
                concrete = false,
            }
        end
        return
    end

    local kind = normalizeIdentifier(entry.type or entry.category or entry.kind or entry.promptType)
    local markedExperimental = source ~= "room" or experimentFeatureKind(kind) or
        experimentValuePresent(entry.experimentFeature) or experimentValuePresent(entry.experimentalFeature) or
        experimentValuePresent(entry.weirdFeature) or experimentValuePresent(entry.mechanism) or
        experimentValuePresent(entry.curiosity)
    if not markedExperimental then
        return
    end

    local size = normalizeIdentifier(entry.size or entry.scale or entry.magnitude)
    local large = entry.big == true or entry.large == true or entry.huge == true or entry.gigantic == true or
        size == "big" or size == "large" or size == "huge" or size == "gargantuan"
    local obvious = entry.obvious == true or entry.visible == true or entry.telegraphed == true or
        entry.obviousFeature == true
    local weird = entry.weird == true or entry.gonzo == true or entry.strange == true or entry.bizarre == true or
        experimentValuePresent(entry.weirdness) or experimentFeatureKind(kind)
    local interactions = normalizeTextList(entry.interactions, entry.actions, entry.options, entry.trigger,
        entry.triggers, entry.activation, entry.activations, entry.requires, entry.offerings, entry.inputs,
        entry.experiment, entry.experiments)
    local outcomes = normalizeTextList(entry.effect, entry.effects, entry.stateChange, entry.stateChanges,
        entry.result, entry.results, entry.reward, entry.risk, entry.danger, entry.boon, entry.clue,
        entry.unlocks, entry.opens, entry.reveal_connection)
    local learning = normalizeTextList(entry.howItWorks, entry.learnHowItWorks, entry.operatingRule,
        entry.operatingRules, entry.feedback, entry.signals, entry.discovery, entry.discoveries)
    local hasInteraction = #interactions > 0 or experimentValuePresent(entry.trigger) or
        experimentValuePresent(entry.activation) or experimentValuePresent(entry.requires)
    local hasOutcome = #outcomes > 0 or experimentValuePresent(entry.effect) or
        experimentValuePresent(entry.stateChange) or experimentValuePresent(entry.stateChanges)
    local hasLearning = #learning > 0 or experimentValuePresent(entry.howItWorks) or
        experimentValuePresent(entry.operatingRule)
    local bigObviousWeird = large or obvious or weird
    local description = trimString(entry.description or entry.summary or entry.text or entry.name or entry.id)
    local missing = {}
    if not description then
        missing[#missing + 1] = "description"
    end
    if not bigObviousWeird then
        missing[#missing + 1] = "big_obvious_weird"
    end
    if not hasInteraction then
        missing[#missing + 1] = "interaction"
    end
    if not hasOutcome then
        missing[#missing + 1] = "outcome"
    end
    local concrete = #missing == 0
    if not (description or bigObviousWeird or hasInteraction or hasOutcome or hasLearning) then
        return
    end
    list[#list + 1] = {
        source = source,
        name = trimString(entry.name or entry.id),
        description = description,
        kind = kind,
        large = large,
        obvious = obvious,
        weird = weird,
        interactions = interactions,
        outcomes = outcomes,
        learning = learning,
        hasLearningCue = hasLearning,
        concrete = concrete,
        missing = missing,
    }
end

local function addExperimentFeatureEntries(list, source, entries)
    if entries == nil then
        return
    end
    if type(entries) ~= "table" then
        addExperimentFeatureRecord(list, source, entries)
        return
    end
    if entries.name or entries.id or entries.description or entries.type or entries.kind or entries.interactions or
        entries.effect or entries.stateChange or entries.experimentFeature or entries.weirdFeature then
        addExperimentFeatureRecord(list, source, entries)
        return
    end
    for _, entry in ipairs(entries) do
        addExperimentFeatureRecord(list, source, entry)
    end
end

local function roomExperimentFeatureRecord(room, detail)
    local features = {}
    addExperimentFeatureRecord(features, "room", room)
    addExperimentFeatureEntries(features, "experimentFeatures", room.experimentFeature or room.experimentalFeature or
        room.experimentFeatures or room.experimentalFeatures or room.weirdFeature or room.weirdFeatures)
    addExperimentFeatureEntries(features, "features", room.features or room.roomFeatures or room.interactiveFeatures)
    local concreteFeatures = {}
    for _, feature in ipairs(features) do
        if feature.concrete then
            concreteFeatures[#concreteFeatures + 1] = feature
        end
    end
    return {
        hasExperimentReason = detail.reasonFlags.experiment == true,
        hasFeature = #concreteFeatures > 0,
        features = features,
        concreteFeatures = concreteFeatures,
        guidance = M.EXPERIMENT_FEATURE_AUTHORING_GUIDANCE,
    }
end

local function surpriseSecretKind(kind)
    return kind == "secret" or kind == "secret_door" or kind == "hidden_room" or kind == "hidden_cache" or
        kind == "concealed_feature"
end

local function addSurpriseSecretRecord(list, source, entry)
    if type(entry) ~= "table" then
        local text = trimString(entry)
        if text then
            list[#list + 1] = {
                source = source,
                secret = text,
                secrets = { text },
                clues = {},
                concrete = false,
                missing = { "clue" },
            }
        end
        return
    end

    local kind = normalizeIdentifier(entry.type or entry.category or entry.kind)
    local markedSecret = source ~= "room" or surpriseSecretKind(kind) or entry.hidden == true or
        entry.isSecret == true or entry.secret == true or experimentValuePresent(entry.secret) or
        experimentValuePresent(entry.secrets) or experimentValuePresent(entry.hiddenDescription) or
        experimentValuePresent(entry.hidden_description) or experimentValuePresent(entry.revealConnection) or
        experimentValuePresent(entry.secretDoor) or experimentValuePresent(entry.hiddenRoom) or
        experimentValuePresent(entry.clue) or experimentValuePresent(entry.clues)
    if not markedSecret then
        return
    end

    local secrets = normalizeTextList(entry.secret, entry.secrets, entry.hiddenDescription,
        entry.hidden_description, entry.hiddenDetails, entry.hidden_detail, entry.reveal, entry.reveals,
        entry.revealConnection, entry.secretDoor, entry.hiddenDoor, entry.hiddenRoom, entry.hiddenTreasure,
        entry.hiddenCache)
    local clues = normalizeTextList(entry.clue, entry.clues, entry.sensoryClue, entry.sensoryClues,
        entry.patternClue, entry.patternClues, entry.telegraph, entry.telegraphs, entry.foreshadowing,
        entry.draft, entry.soot, entry.mapGap, entry.inRetrospect)
    local hasSecret = #secrets > 0 or entry.hidden == true or entry.isSecret == true or
        surpriseSecretKind(kind)
    local hasClue = #clues > 0
    local description = trimString(entry.description or entry.summary or entry.text or entry.name or entry.id)
    if not (description or hasSecret or hasClue) then
        return
    end

    local missing = {}
    if not hasSecret then
        missing[#missing + 1] = "secret"
    end
    if not hasClue then
        missing[#missing + 1] = "clue"
    end
    list[#list + 1] = {
        source = source,
        name = trimString(entry.name or entry.id),
        description = description,
        kind = kind,
        secrets = secrets,
        clues = clues,
        concrete = #missing == 0,
        missing = missing,
        notObvious = entry.hidden == true or entry.isSecret == true or surpriseSecretKind(kind),
    }
end

local function addSurpriseSecretEntries(list, source, entries)
    if entries == nil then
        return
    end
    if type(entries) ~= "table" then
        addSurpriseSecretRecord(list, source, entries)
        return
    end
    if entries.name or entries.id or entries.description or entries.type or entries.kind or entries.secret or
        entries.secrets or entries.clue or entries.clues or entries.hiddenDescription or
        entries.hidden_description or entries.revealConnection then
        addSurpriseSecretRecord(list, source, entries)
        return
    end
    for _, entry in ipairs(entries) do
        addSurpriseSecretRecord(list, source, entry)
    end
end

local function roomSurpriseSecretRecord(room, detail)
    local secrets = {}
    addSurpriseSecretRecord(secrets, "room", room)
    addSurpriseSecretEntries(secrets, "secrets", room.secrets or room.secretDoors or room.hiddenRooms or
        room.hiddenCaches)
    addSurpriseSecretEntries(secrets, "features", room.features or room.roomFeatures or room.interactiveFeatures)
    local concreteSecrets = {}
    for _, secret in ipairs(secrets) do
        if secret.concrete then
            concreteSecrets[#concreteSecrets + 1] = secret
        end
    end
    return {
        hasSurpriseReason = detail.reasonFlags.surprise == true,
        hasSecretClue = #concreteSecrets > 0,
        secrets = secrets,
        concreteSecrets = concreteSecrets,
        guidance = M.SURPRISE_SECRET_AUTHORING_GUIDANCE,
    }
end

local function addReturnHookRecord(list, source, entry)
    if type(entry) ~= "table" then
        local text = trimString(entry)
        if text then
            list[#list + 1] = {
                source = source,
                hook = text,
                dependencies = {},
                concrete = false,
                missing = { "dependency" },
            }
        end
        return
    end

    local hooks = normalizeTextList(entry.returnHook, entry.returnHooks, entry.revisitHook,
        entry.revisitReason, entry.comeBackWhen, entry.description, entry.summary, entry.text)
    local dependencies = normalizeTextList(entry.requiresOtherLevel, entry.requiresOtherRoom,
        entry.otherLevel, entry.otherRoom, entry.linkedLevel, entry.linkedRoom, entry.crossLevel,
        entry.crossRoom, entry.elsewhere, entry.remoteCondition, entry.dependency, entry.dependencies,
        entry.prerequisite, entry.prerequisites, entry.requiredItem, entry.requiredItems, entry.requiredFrom,
        entry.neededFrom, entry.missingPart, entry.missingParts, entry.deliveryTarget, entry.deliverTo,
        entry.unlockCondition, entry.unlocksLater, entry.opensWhen, entry.gatedBy)
    local markedReturn = experimentValuePresent(entry.returnHook) or experimentValuePresent(entry.returnHooks) or
        experimentValuePresent(entry.revisitHook) or experimentValuePresent(entry.revisitReason) or
        experimentValuePresent(entry.comeBackWhen) or #dependencies > 0 or entry.requiresOtherLevel == true or
        entry.requiresOtherRoom == true or entry.crossLevel == true or entry.crossRoom == true or
        entry.unlocksLater == true
    if not markedReturn then
        return
    end

    local hook = hooks[1] or trimString(entry.name or entry.id)
    local hasDependency = #dependencies > 0 or entry.requiresOtherLevel == true or
        entry.requiresOtherRoom == true or entry.crossLevel == true or entry.crossRoom == true or
        entry.unlocksLater == true
    local missing = {}
    if not hook then
        missing[#missing + 1] = "hook"
    end
    if not hasDependency then
        missing[#missing + 1] = "dependency"
    end
    list[#list + 1] = {
        source = source,
        name = trimString(entry.name or entry.id),
        hook = hook,
        hooks = hooks,
        dependencies = dependencies,
        concrete = #missing == 0,
        missing = missing,
        crossLevel = entry.requiresOtherLevel == true or entry.crossLevel == true or
            experimentValuePresent(entry.otherLevel) or experimentValuePresent(entry.linkedLevel),
        crossRoom = entry.requiresOtherRoom == true or entry.crossRoom == true or
            experimentValuePresent(entry.otherRoom) or experimentValuePresent(entry.linkedRoom),
    }
end

local function addReturnHookEntries(list, source, entries)
    if entries == nil then
        return
    end
    if type(entries) ~= "table" then
        addReturnHookRecord(list, source, entries)
        return
    end
    if entries.name or entries.id or entries.description or entries.returnHook or entries.returnHooks or
        entries.revisitHook or entries.requiresOtherLevel or entries.requiresOtherRoom or entries.otherLevel or
        entries.otherRoom or entries.requiredItem or entries.missingPart or entries.deliveryTarget then
        addReturnHookRecord(list, source, entries)
        return
    end
    for _, entry in ipairs(entries) do
        addReturnHookRecord(list, source, entry)
    end
end

local function roomReturnHookRecord(room, detail)
    local hooks = {}
    addReturnHookRecord(hooks, "room", room)
    addReturnHookEntries(hooks, "returnHooks", room.returnHooks or room.revisitHooks or room.returnRequirements)
    addReturnHookEntries(hooks, "features", room.features or room.roomFeatures or room.interactiveFeatures)
    local concreteHooks = {}
    for _, hook in ipairs(hooks) do
        if hook.concrete then
            concreteHooks[#concreteHooks + 1] = hook
        end
    end
    return {
        hasReturnReason = detail.reasonFlags["return"] == true,
        hasHook = #concreteHooks > 0,
        hooks = hooks,
        concreteHooks = concreteHooks,
        guidance = M.RETURN_HOOK_AUTHORING_GUIDANCE,
    }
end

local function addTalkEncounterRecord(list, source, entry)
    if type(entry) ~= "table" then
        local text = trimString(entry)
        if text then
            list[#list + 1] = {
                source = source,
                speaker = text,
                concrete = false,
                missing = { "social_context" },
            }
        end
        return
    end

    local speaker = trimString(entry.name or entry.id or entry.npc or entry.creature or entry.monster or
        entry.faction or entry.speaker or entry.talker)
    local wants = normalizeTextList(entry.wants, entry.want, entry.goals, entry.desires, entry.needs,
        entry.motivation, entry.motivations, entry.protects, entry.seeks)
    local doesNotWant = normalizeTextList(entry.doesNotWant, entry.doesntWant, entry.notWant, entry.hates,
        entry.avoid, entry.avoids, entry.refuses, entry.opposes, entry.taboo)
    local hooks = normalizeTextList(entry.socialHooks, entry.roleplayHooks, entry.leverage, entry.bargains,
        entry.negotiationHooks, entry.parleyHooks, entry.talkHooks, entry.information, entry.info, entry.clue,
        entry.clues, entry.rumor, entry.rumors, entry.currentPlans, entry.plans, entry.beliefSystems,
        entry.dungeonInfo, entry.insults)
    local languages = normalizeTextList(entry.languages, entry.spokenLanguages, entry.tongues,
        entry.languageContext, entry.languageClues, entry.languageHooks)
    local markedTalk = source ~= "room" or experimentValuePresent(entry.reasonToTalk) or
        experimentValuePresent(entry.talkReason) or experimentValuePresent(entry.socialEncounter) or
        experimentValuePresent(entry.talkEncounter) or entry.canTalk == true or entry.talkative == true or
        #wants > 0 or #doesNotWant > 0 or #hooks > 0 or #languages > 0
    if not markedTalk then
        return
    end

    local missing = {}
    if not speaker then
        missing[#missing + 1] = "speaker"
    end
    if #wants == 0 and #doesNotWant == 0 and #hooks == 0 then
        missing[#missing + 1] = "social_context"
    end
    list[#list + 1] = {
        source = source,
        speaker = speaker,
        wants = wants,
        doesNotWant = doesNotWant,
        hooks = hooks,
        languages = languages,
        disposition = entry.disposition or entry.startingDisposition or entry.defaultDisposition,
        concrete = #missing == 0,
        missing = missing,
    }
end

local function addTalkEncounterEntries(list, source, entries)
    if entries == nil then
        return
    end
    if type(entries) ~= "table" then
        addTalkEncounterRecord(list, source, entries)
        return
    end
    if entries.name or entries.id or entries.npc or entries.creature or entries.faction or entries.speaker or
        entries.wants or entries.goals or entries.doesNotWant or entries.doesntWant or entries.socialHooks or
        entries.leverage or entries.languages or entries.reasonToTalk then
        addTalkEncounterRecord(list, source, entries)
        return
    end
    for _, entry in ipairs(entries) do
        addTalkEncounterRecord(list, source, entry)
    end
end

local function roomTalkEncounterRecord(room, detail)
    local encounters = {}
    addTalkEncounterRecord(encounters, "room", room)
    addTalkEncounterEntries(encounters, "talkEncounters", room.talkEncounter or room.talkEncounters or
        room.socialEncounter or room.socialEncounters or room.parleyEncounters)
    addTalkEncounterEntries(encounters, "denizens", room.denizens or room.creatures or room.monsters or
        room.npcs)
    addTalkEncounterEntries(encounters, "factions", room.factions or room.levelFactions or room.powerFactions)
    local concreteEncounters = {}
    for _, encounter in ipairs(encounters) do
        if encounter.concrete then
            concreteEncounters[#concreteEncounters + 1] = encounter
        end
    end
    return {
        hasTalkReason = detail.reasonFlags.talk == true,
        hasEncounter = #concreteEncounters > 0,
        encounters = encounters,
        concreteEncounters = concreteEncounters,
        guidance = M.TALK_ENCOUNTER_AUTHORING_GUIDANCE,
    }
end

local function addMeaningfulChoiceRecord(list, source, entry)
    if type(entry) ~= "table" then
        return
    end

    local kind = normalizeIdentifier(entry.type or entry.category or entry.kind)
    local rewardSignals = normalizeTextList(entry.reward, entry.rewards, entry.treasure, entry.treasures,
        entry.loot, entry.boon, entry.benefit, entry.benefits, entry.prize, entry.prizes, entry.equipment,
        entry.item, entry.items, entry.gold, entry.coins)
    local riskSignals = normalizeTextList(entry.risk, entry.risks, entry.danger, entry.dangers, entry.hazard,
        entry.hazards, entry.trap, entry.traps, entry.curse, entry.guard, entry.guards, entry.guardedBy,
        entry.monster, entry.monsters, entry.denizen, entry.denizens, entry.consequence, entry.consequences)
    local clues = normalizeTextList(entry.clue, entry.clues, entry.telegraph, entry.telegraphs,
        entry.warning, entry.warnings, entry.sensoryClue, entry.sensoryClues, entry.visibleSign,
        entry.visibleSigns, entry.evidence, entry.foreshadowing, entry.bodies, entry.mangledBodies,
        entry.soot, entry.smell, entry.sound, entry.draft)
    local rewardPresent = #rewardSignals > 0 or kind == "treasure" or kind == "reward" or
        entry.gold ~= nil or entry.coins ~= nil or entry.equipment == true or entry.treasure == true or
        entry.loot == true or entry.boon == true
    local riskPresent = #riskSignals > 0 or kind == "trap" or kind == "hazard" or kind == "danger" or
        entry.trap == true or entry.hazard == true or entry.dangerous == true or entry.curse == true
    local cluePresent = #clues > 0
    if not (rewardPresent or riskPresent or cluePresent) then
        return
    end

    local missing = {}
    if not (rewardPresent or riskPresent) then
        missing[#missing + 1] = "reward_or_risk"
    end
    if not cluePresent then
        missing[#missing + 1] = "clue_or_telegraph"
    end
    list[#list + 1] = {
        source = source,
        name = trimString(entry.name or entry.id),
        description = trimString(entry.description or entry.summary or entry.text),
        rewards = rewardSignals,
        risks = riskSignals,
        clues = clues,
        hasReward = rewardPresent,
        hasRisk = riskPresent,
        clear = (rewardPresent or riskPresent) and cluePresent,
        missing = missing,
    }
end

local function addMeaningfulChoiceEntries(list, source, entries)
    if entries == nil then
        return
    end
    if type(entries) ~= "table" then
        return
    end
    if entries.name or entries.id or entries.description or entries.type or entries.kind or entries.reward or
        entries.treasure or entries.risk or entries.hazard or entries.trap or entries.clue or entries.telegraph then
        addMeaningfulChoiceRecord(list, source, entries)
        return
    end
    for _, entry in ipairs(entries) do
        addMeaningfulChoiceRecord(list, source, entry)
    end
end

local function roomMeaningfulChoiceRecord(room)
    local signals = {}
    addMeaningfulChoiceRecord(signals, "room", room)
    addMeaningfulChoiceEntries(signals, "features", room.features or room.roomFeatures or room.interactiveFeatures)
    addMeaningfulChoiceEntries(signals, "traps", room.traps or room.roomTraps)
    addMeaningfulChoiceEntries(signals, "treasures", room.treasures or room.treasure or room.loot)
    local clearSignals = {}
    local unclearSources = {}
    local hasRiskOrReward = false
    for _, signal in ipairs(signals) do
        if signal.hasRisk or signal.hasReward then
            hasRiskOrReward = true
        end
        if signal.clear then
            clearSignals[#clearSignals + 1] = signal
        elseif signal.hasRisk or signal.hasReward then
            unclearSources[#unclearSources + 1] = signal.name or signal.source
        end
    end
    return {
        hasRiskOrReward = hasRiskOrReward,
        hasClearSignal = #clearSignals > 0,
        signals = signals,
        clearSignals = clearSignals,
        unclearSources = unclearSources,
        guidance = M.MEANINGFUL_CHOICE_AUTHORING_GUIDANCE,
    }
end

local function addWarning(detail, key)
    detail.warningFlags[key] = true
    detail.warnings[#detail.warnings + 1] = key
end

function M.validateRoomDescription(room, opts)
    opts = opts or {}
    if type(room) ~= "table" then
        return false, "Room description required"
    end

    local detail = collectRoomReasons(room, opts)
    detail.description = trimString(room.description or room.base_description or room.summary)
    detail.standardLighting = trimString(room.lighting or room.standardLighting or room.lightLevel or
        opts.standardLighting or opts.defaultLighting)
    detail.sensory = {
        temperature = sensoryValue(room, opts, "temperature"),
        smell = sensoryValue(room, opts, "smell"),
        sound = sensoryValue(room, opts, "sound"),
    }
    detail.usableNotes = roomUsableNotes(room)
    detail.safeRoom = roomSafetyRecord(room, detail)
    detail.fleeThreat = roomFleeThreatRecord(room, detail)
    detail.fightDisposition = roomFightDispositionRecord(room, detail)
    detail.exploreReward = roomExploreRewardRecord(room, detail)
    detail.experimentFeature = roomExperimentFeatureRecord(room, detail)
    detail.surpriseSecret = roomSurpriseSecretRecord(room, detail)
    detail.returnHook = roomReturnHookRecord(room, detail)
    detail.talkEncounter = roomTalkEncounterRecord(room, detail)
    detail.meaningfulChoice = roomMeaningfulChoiceRecord(room)
    detail.missing = {}
    detail.warnings = {}
    detail.warningFlags = {}

    if opts.requireText == true and not detail.description then
        return false, "Room description text required", detail
    end
    if #detail.reasons == 0 then
        return false, "Room needs at least one Appendix E reason", detail
    end
    if opts.strictLevelDefaults == true or opts.requireLevelDefaults == true then
        if not detail.standardLighting then
            addWarning(detail, "lighting_missing")
        end
        if not detail.sensory.temperature and not detail.sensory.smell and not detail.sensory.sound then
            addWarning(detail, "sensory_defaults_missing")
        end
    end
    if opts.strictUsableNotes == true or opts.requireUsableNotes == true then
        if not detail.usableNotes.hasInteractableKeywords then
            addWarning(detail, "interactable_keywords_missing")
            detail.missing[#detail.missing + 1] = "interactable_keywords"
        end
        if not detail.usableNotes.hasNestedDiscoveries then
            addWarning(detail, "nested_discoveries_missing")
            detail.missing[#detail.missing + 1] = "nested_discoveries"
        end
    end
    if opts.requireUsableNotes == true and #detail.missing > 0 then
        return false, "Room usable notes incomplete", detail
    end

    return true, "room_description_valid", detail
end

local function roomList(rooms)
    local source = rooms and (rooms.rooms or rooms.levelRooms or rooms)
    local list = {}
    if type(source) ~= "table" then
        return list
    end
    for _, room in ipairs(source) do
        list[#list + 1] = room
    end
    if #list == 0 then
        for key, room in pairs(source) do
            if type(room) == "table" then
                list[#list + 1] = room
            end
        end
    end
    return list
end

function M.validateRoomDescriptions(rooms, opts)
    opts = opts or {}
    local list = roomList(rooms)
    if #list == 0 then
        return false, "Rooms required"
    end

    local validRooms = {}
    local invalidRooms = {}
    for _, room in ipairs(list) do
        local ok, reason, detail = M.validateRoomDescription(room, opts)
        if ok then
            validRooms[#validRooms + 1] = detail
        else
            invalidRooms[#invalidRooms + 1] = {
                roomId = detail and detail.roomId or (type(room) == "table" and room.id or nil),
                reason = reason,
                detail = detail,
            }
        end
    end
    if #invalidRooms > 0 then
        return false, "Room descriptions incomplete", {
            rooms = validRooms,
            invalidRooms = invalidRooms,
            count = #list,
        }
    end

    local roomsMissingLightingDefaults = {}
    local roomsMissingSensoryDefaults = {}
    for _, room in ipairs(validRooms) do
        if room.warningFlags and room.warningFlags.lighting_missing then
            roomsMissingLightingDefaults[#roomsMissingLightingDefaults + 1] = room.roomId
        end
        if room.warningFlags and room.warningFlags.sensory_defaults_missing then
            roomsMissingSensoryDefaults[#roomsMissingSensoryDefaults + 1] = room.roomId
        end
    end

    local talkEncounterRooms = {}
    local talkRoomsMissingEncounters = {}
    for _, room in ipairs(validRooms) do
        if room.talkEncounter and room.talkEncounter.hasEncounter then
            talkEncounterRooms[#talkEncounterRooms + 1] = {
                roomId = room.roomId,
                roomName = room.roomName,
                encounters = room.talkEncounter.concreteEncounters,
            }
        elseif room.talkEncounter and room.talkEncounter.hasTalkReason and
            opts.requireTalkEncounterEvidence == true then
            talkRoomsMissingEncounters[#talkRoomsMissingEncounters + 1] = room.roomId
        end
    end
    local minTalkEncounterRooms = opts.minTalkEncounterRooms
    if minTalkEncounterRooms == nil and opts.requireTalkEncounters == true then
        minTalkEncounterRooms = math.min(1, #validRooms)
    end
    minTalkEncounterRooms = tonumber(minTalkEncounterRooms) or 0

    local meaningfulChoiceRooms = {}
    local roomsMissingChoiceSignals = {}
    for _, room in ipairs(validRooms) do
        if room.meaningfulChoice and room.meaningfulChoice.hasClearSignal then
            meaningfulChoiceRooms[#meaningfulChoiceRooms + 1] = {
                roomId = room.roomId,
                roomName = room.roomName,
                signals = room.meaningfulChoice.clearSignals,
            }
        elseif room.meaningfulChoice and room.meaningfulChoice.hasRiskOrReward and
            opts.requireMeaningfulChoiceEvidence == true then
            roomsMissingChoiceSignals[#roomsMissingChoiceSignals + 1] = room.roomId
        end
    end
    local minMeaningfulChoiceRooms = opts.minMeaningfulChoiceRooms
    if minMeaningfulChoiceRooms == nil and opts.requireMeaningfulChoiceSignals == true then
        minMeaningfulChoiceRooms = math.min(1, #validRooms)
    end
    minMeaningfulChoiceRooms = tonumber(minMeaningfulChoiceRooms) or 0

    local fleeThreatRooms = {}
    local fleeRoomsMissingThreats = {}
    for _, room in ipairs(validRooms) do
        if room.fleeThreat and room.fleeThreat.hasThreat then
            fleeThreatRooms[#fleeThreatRooms + 1] = {
                roomId = room.roomId,
                roomName = room.roomName,
                threats = room.fleeThreat.threats,
            }
        elseif room.fleeThreat and room.fleeThreat.hasFleeReason and
            opts.requireFleeThreatEvidence == true then
            fleeRoomsMissingThreats[#fleeRoomsMissingThreats + 1] = room.roomId
        end
    end
    local minFleeThreatRooms = opts.minFleeThreatRooms
    if minFleeThreatRooms == nil and opts.requireFleeThreats == true then
        minFleeThreatRooms = math.min(1, #validRooms)
    end
    minFleeThreatRooms = tonumber(minFleeThreatRooms) or 0

    local fightDispositionRooms = {}
    local fightRoomsMissingDisposition = {}
    for _, room in ipairs(validRooms) do
        if room.fightDisposition and room.fightDisposition.hasAggressiveDisposition then
            fightDispositionRooms[#fightDispositionRooms + 1] = {
                roomId = room.roomId,
                roomName = room.roomName,
                dispositions = room.fightDisposition.dispositions,
            }
        elseif room.fightDisposition and room.fightDisposition.hasFightReason and
            opts.requireFightDispositionEvidence == true then
            fightRoomsMissingDisposition[#fightRoomsMissingDisposition + 1] = room.roomId
        end
    end
    local minFightDispositionRooms = opts.minFightDispositionRooms
    if minFightDispositionRooms == nil and opts.requireFightDisposition == true then
        minFightDispositionRooms = math.min(1, #validRooms)
    end
    minFightDispositionRooms = tonumber(minFightDispositionRooms) or 0

    local exploreRewardRooms = {}
    local exploreRoomsMissingRewards = {}
    for _, room in ipairs(validRooms) do
        if room.exploreReward and room.exploreReward.hasReward then
            exploreRewardRooms[#exploreRewardRooms + 1] = {
                roomId = room.roomId,
                roomName = room.roomName,
                rewards = room.exploreReward.rewards,
            }
        elseif room.exploreReward and room.exploreReward.hasExploreReason and
            opts.requireExploreRewardEvidence == true then
            exploreRoomsMissingRewards[#exploreRoomsMissingRewards + 1] = room.roomId
        end
    end
    local minExploreRewardRooms = opts.minExploreRewardRooms
    if minExploreRewardRooms == nil and opts.requireExploreRewards == true then
        minExploreRewardRooms = math.min(1, #validRooms)
    end
    minExploreRewardRooms = tonumber(minExploreRewardRooms) or 0

    local experimentFeatureRooms = {}
    local experimentRoomsMissingFeatures = {}
    for _, room in ipairs(validRooms) do
        if room.experimentFeature and room.experimentFeature.hasFeature then
            experimentFeatureRooms[#experimentFeatureRooms + 1] = {
                roomId = room.roomId,
                roomName = room.roomName,
                features = room.experimentFeature.concreteFeatures,
            }
        elseif room.experimentFeature and room.experimentFeature.hasExperimentReason and
            opts.requireExperimentFeatureEvidence == true then
            experimentRoomsMissingFeatures[#experimentRoomsMissingFeatures + 1] = room.roomId
        end
    end
    local minExperimentFeatureRooms = opts.minExperimentFeatureRooms
    if minExperimentFeatureRooms == nil and opts.requireExperimentFeatures == true then
        minExperimentFeatureRooms = math.min(1, #validRooms)
    end
    minExperimentFeatureRooms = tonumber(minExperimentFeatureRooms) or 0

    local surpriseSecretRooms = {}
    local surpriseRoomsMissingSecrets = {}
    for _, room in ipairs(validRooms) do
        if room.surpriseSecret and room.surpriseSecret.hasSecretClue then
            surpriseSecretRooms[#surpriseSecretRooms + 1] = {
                roomId = room.roomId,
                roomName = room.roomName,
                secrets = room.surpriseSecret.concreteSecrets,
            }
        elseif room.surpriseSecret and room.surpriseSecret.hasSurpriseReason and
            opts.requireSurpriseSecretEvidence == true then
            surpriseRoomsMissingSecrets[#surpriseRoomsMissingSecrets + 1] = room.roomId
        end
    end
    local minSurpriseSecretRooms = opts.minSurpriseSecretRooms
    if minSurpriseSecretRooms == nil and opts.requireSurpriseSecrets == true then
        minSurpriseSecretRooms = math.min(1, #validRooms)
    end
    minSurpriseSecretRooms = tonumber(minSurpriseSecretRooms) or 0

    local returnHookRooms = {}
    local returnRoomsMissingHooks = {}
    for _, room in ipairs(validRooms) do
        if room.returnHook and room.returnHook.hasHook then
            returnHookRooms[#returnHookRooms + 1] = {
                roomId = room.roomId,
                roomName = room.roomName,
                hooks = room.returnHook.concreteHooks,
            }
        elseif room.returnHook and room.returnHook.hasReturnReason and opts.requireReturnHookEvidence == true then
            returnRoomsMissingHooks[#returnRoomsMissingHooks + 1] = room.roomId
        end
    end
    local minReturnHookRooms = opts.minReturnHookRooms
    if minReturnHookRooms == nil and opts.requireReturnHooks == true then
        minReturnHookRooms = math.min(1, #validRooms)
    end
    minReturnHookRooms = tonumber(minReturnHookRooms) or 0

    local safeRooms = {}
    local safeRoomsMissingNotes = {}
    for _, room in ipairs(validRooms) do
        if room.safeRoom and room.safeRoom.isSafe then
            safeRooms[#safeRooms + 1] = {
                roomId = room.roomId,
                roomName = room.roomName,
                note = room.safeRoom.note,
                basis = room.safeRoom.basis,
            }
            if opts.requireSafeRoomNotes == true and not room.safeRoom.note then
                safeRoomsMissingNotes[#safeRoomsMissingNotes + 1] = room.roomId
            end
        end
    end
    local minSafeRooms = opts.minSafeRooms
    if minSafeRooms == nil and opts.requireSafeRooms == true then
        minSafeRooms = math.min(2, #validRooms)
    end
    minSafeRooms = tonumber(minSafeRooms) or 0
    local missing = {}
    if minSafeRooms > 0 and #safeRooms < minSafeRooms then
        missing[#missing + 1] = "safe_rooms"
    end
    if #safeRoomsMissingNotes > 0 then
        missing[#missing + 1] = "safe_room_look_and_feel"
    end
    if minTalkEncounterRooms > 0 and #talkEncounterRooms < minTalkEncounterRooms then
        missing[#missing + 1] = "talk_encounters"
    end
    if #talkRoomsMissingEncounters > 0 then
        missing[#missing + 1] = "talk_encounter_context"
    end
    if minMeaningfulChoiceRooms > 0 and #meaningfulChoiceRooms < minMeaningfulChoiceRooms then
        missing[#missing + 1] = "meaningful_choice_signals"
    end
    if #roomsMissingChoiceSignals > 0 then
        missing[#missing + 1] = "risk_reward_clarity"
    end
    if minFleeThreatRooms > 0 and #fleeThreatRooms < minFleeThreatRooms then
        missing[#missing + 1] = "overwhelming_flee_threats"
    end
    if #fleeRoomsMissingThreats > 0 then
        missing[#missing + 1] = "flee_threat_evidence"
    end
    if minFightDispositionRooms > 0 and #fightDispositionRooms < minFightDispositionRooms then
        missing[#missing + 1] = "aggressive_fight_dispositions"
    end
    if #fightRoomsMissingDisposition > 0 then
        missing[#missing + 1] = "fight_disposition_evidence"
    end
    if minExploreRewardRooms > 0 and #exploreRewardRooms < minExploreRewardRooms then
        missing[#missing + 1] = "explore_rewards"
    end
    if #exploreRoomsMissingRewards > 0 then
        missing[#missing + 1] = "explore_reward_evidence"
    end
    if minExperimentFeatureRooms > 0 and #experimentFeatureRooms < minExperimentFeatureRooms then
        missing[#missing + 1] = "experiment_features"
    end
    if #experimentRoomsMissingFeatures > 0 then
        missing[#missing + 1] = "experiment_feature_evidence"
    end
    if minSurpriseSecretRooms > 0 and #surpriseSecretRooms < minSurpriseSecretRooms then
        missing[#missing + 1] = "surprise_secrets"
    end
    if #surpriseRoomsMissingSecrets > 0 then
        missing[#missing + 1] = "surprise_secret_clues"
    end
    if minReturnHookRooms > 0 and #returnHookRooms < minReturnHookRooms then
        missing[#missing + 1] = "return_hooks"
    end
    if #returnRoomsMissingHooks > 0 then
        missing[#missing + 1] = "return_hook_dependencies"
    end
    if opts.requireLevelDefaults == true and #roomsMissingLightingDefaults > 0 then
        missing[#missing + 1] = "level_lighting_defaults"
    end
    if opts.requireLevelDefaults == true and #roomsMissingSensoryDefaults > 0 then
        missing[#missing + 1] = "level_sensory_defaults"
    end
    local levelDefaultDetail = {
        missingLightingRooms = roomsMissingLightingDefaults,
        missingSensoryRooms = roomsMissingSensoryDefaults,
    }
    local safeRoomDetail = {
        safeRooms = safeRooms,
        count = #safeRooms,
        minRequired = minSafeRooms,
        missingNotes = safeRoomsMissingNotes,
        guidance = M.SAFE_ROOM_AUTHORING_GUIDANCE,
    }
    local talkEncounterDetail = {
        rooms = talkEncounterRooms,
        count = #talkEncounterRooms,
        minRequired = minTalkEncounterRooms,
        missingEncounterRooms = talkRoomsMissingEncounters,
        guidance = M.TALK_ENCOUNTER_AUTHORING_GUIDANCE,
    }
    local meaningfulChoiceDetail = {
        rooms = meaningfulChoiceRooms,
        count = #meaningfulChoiceRooms,
        minRequired = minMeaningfulChoiceRooms,
        missingSignalRooms = roomsMissingChoiceSignals,
        guidance = M.MEANINGFUL_CHOICE_AUTHORING_GUIDANCE,
    }
    local fleeThreatDetail = {
        rooms = fleeThreatRooms,
        count = #fleeThreatRooms,
        minRequired = minFleeThreatRooms,
        missingThreatRooms = fleeRoomsMissingThreats,
        guidance = M.FLEE_THREAT_AUTHORING_GUIDANCE,
    }
    local fightDispositionDetail = {
        rooms = fightDispositionRooms,
        count = #fightDispositionRooms,
        minRequired = minFightDispositionRooms,
        missingDispositionRooms = fightRoomsMissingDisposition,
        guidance = M.FIGHT_DISPOSITION_AUTHORING_GUIDANCE,
    }
    local exploreRewardDetail = {
        rooms = exploreRewardRooms,
        count = #exploreRewardRooms,
        minRequired = minExploreRewardRooms,
        missingRewardRooms = exploreRoomsMissingRewards,
        guidance = M.EXPLORE_REWARD_AUTHORING_GUIDANCE,
    }
    local experimentFeatureDetail = {
        rooms = experimentFeatureRooms,
        count = #experimentFeatureRooms,
        minRequired = minExperimentFeatureRooms,
        missingFeatureRooms = experimentRoomsMissingFeatures,
        guidance = M.EXPERIMENT_FEATURE_AUTHORING_GUIDANCE,
    }
    local surpriseSecretDetail = {
        rooms = surpriseSecretRooms,
        count = #surpriseSecretRooms,
        minRequired = minSurpriseSecretRooms,
        missingSecretRooms = surpriseRoomsMissingSecrets,
        guidance = M.SURPRISE_SECRET_AUTHORING_GUIDANCE,
    }
    local returnHookDetail = {
        rooms = returnHookRooms,
        count = #returnHookRooms,
        minRequired = minReturnHookRooms,
        missingHookRooms = returnRoomsMissingHooks,
        guidance = M.RETURN_HOOK_AUTHORING_GUIDANCE,
    }
    if #missing > 0 then
        return false, "Room descriptions incomplete", {
            rooms = validRooms,
            invalidRooms = {},
            count = #validRooms,
            safeRooms = safeRoomDetail,
            talkEncounters = talkEncounterDetail,
            meaningfulChoices = meaningfulChoiceDetail,
            fleeThreats = fleeThreatDetail,
            fightDispositions = fightDispositionDetail,
            exploreRewards = exploreRewardDetail,
            experimentFeatures = experimentFeatureDetail,
            surpriseSecrets = surpriseSecretDetail,
            returnHooks = returnHookDetail,
            levelDefaults = levelDefaultDetail,
            missing = missing,
        }
    end

    return true, "room_descriptions_valid", {
        rooms = validRooms,
        count = #validRooms,
        safeRooms = safeRoomDetail,
        talkEncounters = talkEncounterDetail,
        meaningfulChoices = meaningfulChoiceDetail,
        fleeThreats = fleeThreatDetail,
        fightDispositions = fightDispositionDetail,
        exploreRewards = exploreRewardDetail,
        experimentFeatures = experimentFeatureDetail,
        surpriseSecrets = surpriseSecretDetail,
        returnHooks = returnHookDetail,
        levelDefaults = levelDefaultDetail,
    }
end

local function factionList(factions)
    local source = factions
    if type(source) == "table" and (source.factions or source.levelFactions or
       source.controllingFactions or source.powerFactions) then
        source = source.factions or source.levelFactions or source.controllingFactions or source.powerFactions
    end

    local list = {}
    if type(source) ~= "table" then
        return list
    end
    if source.name or source.id or source.wants or source.goals or source.doesNotWant or source.doesntWant then
        list[#list + 1] = source
        return list
    end
    for _, faction in ipairs(source) do
        list[#list + 1] = faction
    end
    if #list == 0 then
        for key, faction in pairs(source) do
            if type(faction) == "table" then
                if faction.id == nil then
                    faction.id = key
                end
                list[#list + 1] = faction
            end
        end
    end
    return list
end

local function addFactionWarning(detail, key)
    detail.warnings[#detail.warnings + 1] = key
    detail.warningFlags[key] = true
end

function M.validateFaction(faction, opts)
    opts = opts or {}
    if type(faction) ~= "table" then
        return false, "Faction required"
    end

    local wants = normalizeTextList(faction.wants, faction.want, faction.goals, faction.desires, faction.needs)
    local doesNotWant = normalizeTextList(faction.doesNotWant, faction.doesntWant, faction.notWant,
        faction.hates, faction.avoid, faction.avoids, faction.refuses, faction.opposes, faction.taboo)
    local languages = normalizeTextList(faction.languages, faction.spokenLanguages, faction.tongues)
    local languageContext = normalizeTextList(faction.languageContext, faction.languageContexts,
        faction.languageClues, faction.languageHooks, faction.translationClues, faction.linguisticHooks,
        faction.contextualLanguageInfo)
    local detail = {
        id = faction.id,
        name = trimString(faction.name or faction.faction or faction.title or faction.id),
        wants = wants,
        doesNotWant = doesNotWant,
        languages = languages,
        languageContext = languageContext,
        disposition = faction.disposition or faction.startingDisposition or faction.defaultDisposition,
        socialHooks = normalizeTextList(faction.socialHooks, faction.roleplayHooks, faction.leverage,
            faction.bargains, faction.negotiationHooks),
        notes = faction.notes,
        missing = {},
        warnings = {},
        warningFlags = {},
        guidance = M.FACTION_AUTHORING_GUIDANCE,
    }

    if not detail.name then
        detail.missing[#detail.missing + 1] = "faction_name"
    end
    if #detail.wants == 0 then
        detail.missing[#detail.missing + 1] = "faction_wants"
    end
    if #detail.doesNotWant == 0 then
        detail.missing[#detail.missing + 1] = "faction_does_not_want"
    end
    if #detail.languages == 0 and opts.warnMissingLanguages ~= false then
        addFactionWarning(detail, "languages_missing")
    end
    if #languageContext == 0 and (opts.warnMissingLanguageContext == true or opts.requireLanguageContext == true) then
        addFactionWarning(detail, "language_context_missing")
        if opts.requireLanguageContext == true then
            detail.missing[#detail.missing + 1] = "faction_language_context"
        end
    end

    if #detail.missing > 0 then
        return false, "Faction incomplete", detail
    end
    return true, "faction_valid", detail
end

function M.validateLevelFactions(factions, opts)
    opts = opts or {}
    local list = factionList(factions)
    if #list == 0 then
        return false, "Dungeon level factions required", {
            factions = {},
            invalidFactions = {},
            count = 0,
            missing = { "level_factions" },
            guidance = M.FACTION_AUTHORING_GUIDANCE,
        }
    end

    local validFactions = {}
    local invalidFactions = {}
    local warningCount = 0
    for _, faction in ipairs(list) do
        local ok, reason, detail = M.validateFaction(faction, opts)
        if ok then
            validFactions[#validFactions + 1] = detail
            warningCount = warningCount + #detail.warnings
        else
            invalidFactions[#invalidFactions + 1] = {
                factionId = detail and detail.id,
                factionName = detail and detail.name,
                reason = reason,
                detail = detail,
            }
            if detail then
                warningCount = warningCount + #detail.warnings
            end
        end
    end

    local detail = {
        factions = validFactions,
        invalidFactions = invalidFactions,
        count = #validFactions,
        warningCount = warningCount,
        guidance = M.FACTION_AUTHORING_GUIDANCE,
    }
    if #invalidFactions > 0 then
        detail.missing = { "complete_faction_wants" }
        return false, "Dungeon level factions incomplete", detail
    end
    return true, "dungeon_level_factions_valid", detail
end

local function meatgrinderInput(tableData)
    if type(tableData) ~= "table" then
        return nil
    end
    return tableData.meatgrinderTable or tableData.meatgrinder or tableData
end

local function meatgrinderSection(tableData, band)
    if tableData[band.key] ~= nil then
        return tableData[band.key], band.key
    end
    for _, key in ipairs(band.aliases or {}) do
        if tableData[key] ~= nil then
            return tableData[key], key
        end
    end
    return nil
end

local function entryHasText(entry)
    if trimString(entry) then
        return true
    end
    if type(entry) ~= "table" then
        return false
    end
    if trimString(entry.description or entry.text or entry.note or entry.name or entry.summary) then
        return true
    end
    if entry.effect or entry.effects or entry.spawns or entry.blueprint_id or entry.questRumor then
        return true
    end
    return #entry > 0
end

local function meatgrinderEntryDescription(entry)
    local text = trimString(entry)
    if text then
        return text
    end
    if type(entry) ~= "table" then
        return nil
    end
    return trimString(entry.description or entry.text or entry.note or entry.name or entry.summary)
end

local function addBandWarning(detail, key, value)
    detail.warnings = detail.warnings or {}
    detail.warningFlags = detail.warningFlags or {}
    detail.warnings[#detail.warnings + 1] = {
        key = key,
        value = value,
    }
    detail.warningFlags[key] = true
end

local function randomEncounterAuthoring(entry, value, opts)
    opts = opts or {}
    local activity = {}
    local whyThere = {}
    local disposition = nil
    local randomDisposition = false
    local socialContext = {}
    if type(entry) == "table" then
        activity = normalizeTextList(entry.activity, entry.activities, entry.currentActivity, entry.doing,
            entry.business, entry.sceneAction)
        whyThere = normalizeTextList(entry.whyThere, entry.reason, entry.purpose, entry.context,
            entry.dungeonBusiness)
        disposition = entry.disposition or entry.startingDisposition or entry.defaultDisposition
        randomDisposition = entry.randomDisposition == true or entry.uncertainDisposition == true or
            entry.rollDisposition == true
        socialContext = normalizeTextList(entry.socialContext, entry.roleplayHook, entry.roleplayHooks,
            entry.negotiationHook)
    end

    local hasContext = #activity > 0 or #whyThere > 0
    return {
        value = value,
        description = meatgrinderEntryDescription(entry),
        activity = activity,
        whyThere = whyThere,
        disposition = disposition,
        randomDisposition = randomDisposition,
        socialContext = socialContext,
        hasActivityContext = hasContext,
        missingActivityContext = not hasContext,
        requiresRandomDisposition = opts.requireRandomEncounterDisposition == true and
            disposition == nil and not randomDisposition,
    }
end

local function travelEventAuthoring(entry, value, opts)
    opts = opts or {}
    local resourceTaxes = {}
    local routeChoices = {}
    local hazards = {}
    local tests = {}
    local solutions = {}
    if type(entry) == "table" then
        resourceTaxes = normalizeTextList(entry.resourceTax, entry.resourceTaxes, entry.resourceLoss,
            entry.resourcesLost, entry.tax, entry.taxes, entry.lostResources)
        routeChoices = normalizeTextList(entry.routeChoice, entry.routeChoices, entry.choice, entry.choices,
            entry.toughChoice, entry.pathChoice, entry.pathChoices)
        hazards = normalizeTextList(entry.hazard, entry.hazards, entry.trap, entry.traps, entry.obstacle,
            entry.obstacles, entry.danger, entry.dangers)
        tests = normalizeTextList(entry.test, entry.tests, entry.testFate, entry.testOfFate,
            entry.requiredTest, entry.fateTest)
        solutions = normalizeTextList(entry.solution, entry.solutions, entry.safeSolution, entry.safeSolutions,
            entry.bypass, entry.bypassOptions, entry.playerOptions)
    end

    local hasPressure = #resourceTaxes > 0 or #routeChoices > 0 or #hazards > 0 or #tests > 0
    local hazardNeedsHandling = (#hazards > 0 or #tests > 0) and #solutions == 0 and #routeChoices == 0
    return {
        value = value,
        description = meatgrinderEntryDescription(entry),
        resourceTaxes = resourceTaxes,
        routeChoices = routeChoices,
        hazards = hazards,
        tests = tests,
        solutions = solutions,
        hasTravelPressure = hasPressure,
        missingTravelPressure = not hasPressure,
        hazardNeedsHandling = hazardNeedsHandling,
        requiresTravelPressure = opts.requireTravelEventPressure == true and not hasPressure,
        requiresHazardHandling = opts.requireTravelEventHazardHandling == true and hazardNeedsHandling,
    }
end

local function questRumorAuthoring(entry, value, opts, tableData)
    opts = opts or {}
    tableData = tableData or {}
    local reveals = type(entry) == "table" and (entry.reveals or entry.reveal or {}) or {}
    if type(reveals) ~= "table" then
        reveals = {}
    end

    local questSteps = {}
    local hazards = {}
    local destinations = {}
    local tools = {}
    if type(entry) == "table" then
        questSteps = normalizeTextList(entry.questSteps, entry.steps, entry.pathSteps, entry.pathToVictory,
            entry.milestones, entry.requiredSteps, tableData.questSteps, tableData.pathToVictory,
            tableData.questMilestones)
        hazards = normalizeTextList(entry.hazard, entry.hazards, entry.danger, entry.dangers,
            reveals.hazard, reveals.hazards, reveals.danger)
        destinations = normalizeTextList(entry.destination, entry.destinations, entry.location, entry.locations,
            entry.whereToTravel, reveals.destination, reveals.destinations, reveals.location,
            reveals.whereToTravel)
        tools = normalizeTextList(entry.tool, entry.tools, entry.item, entry.items, entry.itemOrTool,
            entry.neededTool, entry.neededItem, reveals.tool, reveals.tools, reveals.item, reveals.items,
            reveals.itemOrTool)
    else
        questSteps = normalizeTextList(tableData.questSteps, tableData.pathToVictory, tableData.questMilestones)
    end

    local stepCount = #questSteps
    local hasStepPlan = stepCount >= 3 and stepCount <= 5
    local hasReveal = #hazards > 0 or #destinations > 0 or #tools > 0
    return {
        value = value,
        description = meatgrinderEntryDescription(entry),
        questSteps = questSteps,
        stepCount = stepCount,
        hasThreeToFiveSteps = hasStepPlan,
        hazards = hazards,
        destinations = destinations,
        tools = tools,
        hasRulebookReveal = hasReveal,
        requiresQuestStepPlan = (opts.requireQuestRumorPlan == true or opts.requireQuestRumorAuthoring == true) and
            not hasStepPlan,
        requiresQuestReveal = (opts.requireQuestRumorReveal == true or opts.requireQuestRumorAuthoring == true) and
            not hasReveal,
    }
end

local function singletonMeatgrinderEntry(section)
    if type(section) ~= "table" then
        return entryHasText(section)
    end
    if section.description or section.text or section.note or section.name or section.summary or
        section.effect or section.effects or section.spawns or section.blueprint_id or section.questRumor then
        return entryHasText(section)
    end
    return false
end

local function valueRange(startValue, endValue)
    local values = {}
    for value = startValue, endValue do
        values[#values + 1] = value
    end
    return values
end

local function noteRandomEncounterAuthoring(detail, entry, value, opts)
    if detail.key ~= "random_encounter" then
        return
    end

    detail.encounters = detail.encounters or {}
    local encounter = randomEncounterAuthoring(entry, value, opts)
    detail.encounters[#detail.encounters + 1] = encounter
    if encounter.missingActivityContext then
        addBandWarning(detail, "random_encounter_activity_missing", value)
        if opts.requireRandomEncounterActivity == true then
            detail.authoringMissingValues = detail.authoringMissingValues or {}
            detail.authoringMissingValues[#detail.authoringMissingValues + 1] = value
        end
    end
    if encounter.requiresRandomDisposition then
        addBandWarning(detail, "random_encounter_disposition_missing", value)
        detail.authoringMissingValues = detail.authoringMissingValues or {}
        detail.authoringMissingValues[#detail.authoringMissingValues + 1] = value
    end
end

local function noteTravelEventAuthoring(detail, entry, value, opts)
    if detail.key ~= "travel_event" then
        return
    end

    detail.travelEvents = detail.travelEvents or {}
    local event = travelEventAuthoring(entry, value, opts)
    detail.travelEvents[#detail.travelEvents + 1] = event
    if event.missingTravelPressure then
        addBandWarning(detail, "travel_event_pressure_missing", value)
        if event.requiresTravelPressure then
            detail.authoringMissingValues = detail.authoringMissingValues or {}
            detail.authoringMissingValues[#detail.authoringMissingValues + 1] = value
        end
    end
    if event.hazardNeedsHandling then
        addBandWarning(detail, "travel_event_hazard_handling_missing", value)
        if event.requiresHazardHandling then
            detail.authoringMissingValues = detail.authoringMissingValues or {}
            detail.authoringMissingValues[#detail.authoringMissingValues + 1] = value
        end
    end
end

local function noteQuestRumorAuthoring(detail, entry, value, opts, tableData)
    if detail.key ~= "quest_rumor" then
        return
    end

    local rumor = questRumorAuthoring(entry, value, opts, tableData)
    detail.questRumor = rumor
    if rumor.stepCount == 0 then
        addBandWarning(detail, "quest_rumor_steps_missing", value)
    elseif not rumor.hasThreeToFiveSteps then
        addBandWarning(detail, "quest_rumor_step_count_out_of_range", value)
    end
    if not rumor.hasRulebookReveal then
        addBandWarning(detail, "quest_rumor_reveal_missing", value)
    end
    if rumor.requiresQuestStepPlan then
        detail.authoringMissingValues = detail.authoringMissingValues or {}
        detail.authoringMissingValues[#detail.authoringMissingValues + 1] = value
    end
    if rumor.requiresQuestReveal then
        detail.authoringMissingValues = detail.authoringMissingValues or {}
        detail.authoringMissingValues[#detail.authoringMissingValues + 1] = value
    end
end

local function validateMeatgrinderBand(tableData, band, opts)
    opts = opts or {}
    local section, sourceKey = meatgrinderSection(tableData, band)
    local detail = {
        key = band.key,
        sourceKey = sourceKey,
        label = band.label,
        startValue = band.startValue,
        endValue = band.endValue,
        coveredValues = {},
        missingValues = {},
    }
    if section == nil then
        detail.missing = true
        detail.missingValues = valueRange(band.startValue, band.endValue)
        return false, detail
    end

    if band.singleton == true or (band.allowSingleton == true and singletonMeatgrinderEntry(section)) then
        if not entryHasText(section) then
            detail.missing = true
            detail.missingValues = valueRange(band.startValue, band.endValue)
            return false, detail
        end
        detail.singleEntry = true
        detail.coveredValues = valueRange(band.startValue, band.endValue)
        noteTravelEventAuthoring(detail, section, band.startValue, opts)
        noteRandomEncounterAuthoring(detail, section, band.startValue, opts)
        noteQuestRumorAuthoring(detail, section, band.startValue, opts, tableData)
        return #(detail.authoringMissingValues or {}) == 0, detail
    end

    if type(section) ~= "table" then
        detail.missing = true
        detail.missingValues = valueRange(band.startValue, band.endValue)
        return false, detail
    end

    for value = band.startValue, band.endValue do
        local index = value - band.startValue + 1
        local entry = section[index]
        if entryHasText(entry) then
            detail.coveredValues[#detail.coveredValues + 1] = value
            noteTravelEventAuthoring(detail, entry, value, opts)
            noteRandomEncounterAuthoring(detail, entry, value, opts)
            noteQuestRumorAuthoring(detail, entry, value, opts, tableData)
        else
            detail.missingValues[#detail.missingValues + 1] = value
        end
    end

    return #detail.missingValues == 0 and #(detail.authoringMissingValues or {}) == 0, detail
end

function M.validateMeatgrinderTable(tableData, opts)
    opts = opts or {}
    local source = meatgrinderInput(tableData)
    if type(source) ~= "table" then
        return false, "Meatgrinder table required"
    end

    local categories = {}
    local missingCategories = {}
    local missingValues = {}
    local authoringBlockers = {}
    for _, band in ipairs(M.MEATGRINDER_BANDS) do
        local ok, detail = validateMeatgrinderBand(source, band, opts)
        categories[band.key] = detail
        if not ok then
            if detail.missing then
                missingCategories[#missingCategories + 1] = band.key
            end
            for _, value in ipairs(detail.missingValues or {}) do
                missingValues[#missingValues + 1] = value
            end
            for _, value in ipairs(detail.authoringMissingValues or {}) do
                authoringBlockers[#authoringBlockers + 1] = {
                    category = band.key,
                    value = value,
                }
            end
        end
    end

    local detail = {
        categories = categories,
        missingCategories = missingCategories,
        missingValues = missingValues,
        authoringBlockers = authoringBlockers,
        result = (#missingValues == 0 and #authoringBlockers == 0) and "meatgrinder_table_valid" or
            "meatgrinder_table_incomplete",
    }
    if #missingValues > 0 or #authoringBlockers > 0 then
        return false, "Meatgrinder table incomplete", detail
    end

    return true, "meatgrinder_table_valid", detail
end

local function looksLikeMeatgrinderTable(tableData)
    if type(tableData) ~= "table" then
        return false
    end
    for _, band in ipairs(M.MEATGRINDER_BANDS) do
        if meatgrinderSection(tableData, band) ~= nil then
            return true
        end
    end
    return false
end

function M.validateMeatgrinderTables(tables, opts)
    opts = opts or {}
    local source = tables and (tables.tables or tables.levelTables or tables.meatgrinders or
        tables.meatgrinderTables or tables.meatgrinder or tables.meatgrinderTable or tables)
    if type(source) ~= "table" then
        return false, "Meatgrinder tables required"
    end

    local list = {}
    if looksLikeMeatgrinderTable(source) then
        list[#list + 1] = source
    else
        for _, tableData in ipairs(source) do
            if type(tableData) == "table" then
                list[#list + 1] = tableData
            end
        end
        if #list == 0 then
            for _, tableData in pairs(source) do
                if type(tableData) == "table" then
                    list[#list + 1] = tableData
                end
            end
        end
    end
    if #list == 0 then
        return false, "Meatgrinder tables required"
    end

    local validTables = {}
    local invalidTables = {}
    for _, tableData in ipairs(list) do
        local ok, reason, detail = M.validateMeatgrinderTable(tableData, opts)
        if ok then
            validTables[#validTables + 1] = detail
        else
            invalidTables[#invalidTables + 1] = {
                reason = reason,
                detail = detail,
            }
        end
    end
    if #invalidTables > 0 then
        return false, "Meatgrinder tables incomplete", {
            tables = validTables,
            invalidTables = invalidTables,
            count = #list,
        }
    end
    return true, "meatgrinder_tables_valid", {
        tables = validTables,
        count = #validTables,
    }
end

local function featurePromptValue(feature)
    local raw = feature and (feature.promptValue or feature.featurePrompt or feature.majorValue or
        feature.cardValue or feature.value or feature.prompt)
    if type(raw) == "table" then
        raw = raw.value or raw.cardValue or raw.majorValue or raw[1]
    end
    raw = tonumber(raw)
    if raw and raw == math.floor(raw) then
        return raw
    end
    return nil
end

function M.getRoomFeaturePrompt(value)
    if type(value) == "table" then
        value = value.value or value.cardValue or value.majorValue or value[1]
    end
    value = tonumber(value)
    if not value or value ~= math.floor(value) then
        return nil
    end
    return copy(M.ROOM_FEATURE_PROMPTS[value])
end

local function hasListValue(value)
    if value == nil or value == false then
        return false
    end
    if trimString(value) then
        return true
    end
    return type(value) == "table" and next(value) ~= nil
end

local function markFeatureHook(flags, key, value)
    if hasListValue(value) then
        flags[key] = true
    end
end

local function featureHooks(feature)
    local hooks = {}
    markFeatureHook(hooks, "reward", feature.reward or feature.loot or feature.treasure or feature.boon)
    markFeatureHook(hooks, "risk", feature.risk or feature.danger or feature.curse or feature.trap or feature.hazard)
    markFeatureHook(hooks, "clue", feature.clue or feature.clues or feature.secret or feature.secrets or
        feature.hidden_description or feature.lore)
    markFeatureHook(hooks, "state_change", feature.stateChange or feature.stateChanges or feature.effect or
        feature.effects or feature.unlocks or feature.opens or feature.reveal_connection)
    markFeatureHook(hooks, "interaction", feature.interactions or feature.actions or feature.options or
        feature.trigger or feature.activation or feature.requires)
    return hooks
end

local function hookList(flags)
    local list = {}
    for key, value in pairs(flags or {}) do
        if value then
            list[#list + 1] = key
        end
    end
    table.sort(list)
    return list
end

local function addTreasureWarning(detail, warning)
    detail.warningFlags[warning] = true
    detail.warnings[#detail.warnings + 1] = warning
end

local function treasureValue(treasure)
    local value = treasure.value or treasure.goldValue or treasure.saleValue or treasure.price or
        treasure.worth or treasure.gmValue
    if value == nil and treasure.properties then
        value = treasure.properties.value or treasure.properties.goldValue or treasure.properties.price
    end
    if value == nil and (treasure.gold or treasure.coins) then
        value = treasure.gold or treasure.coins
    end
    if type(value) == "table" then
        value = value.value or value.gold or value.amount or value.price or value.note
    end
    return value
end

local function treasureKind(treasure)
    return normalizeIdentifier(treasure.type or treasure.category or treasure.kind or treasure.formType)
end

local function treasureIsCoinKind(kind)
    return kind == "coin" or kind == "coins" or kind == "currency" or kind == "gold" or kind == "money"
end

local function roomContentLocation(entry, opts)
    opts = opts or {}
    if type(entry) ~= "table" then
        return trimString(opts.roomId or opts.room or opts.location)
    end
    return trimString(entry.roomId or entry.room or entry.location or entry.placement or opts.roomId or
        opts.room or opts.location)
end

function M.validateTreasure(treasure, opts)
    opts = opts or {}
    if type(treasure) ~= "table" then
        local description = trimString(treasure)
        if not description then
            return false, "Treasure required"
        end
        treasure = {
            description = description,
        }
    end

    local description = trimString(treasure.description or treasure.summary or treasure.text or treasure.name or treasure.id)
    local kind = treasureKind(treasure)
    local forms = normalizeTextList(treasure.form, treasure.forms, treasure.material, treasure.materials,
        treasure.craft, treasure.craftsmanship, treasure.object, treasure.objects, treasure.item, treasure.items,
        treasure.art, treasure.jewelry, treasure.personalized, treasure.ancestralWeapon, treasure.academicWork,
        treasure.exoticBeast, treasure.relic)
    local lore = normalizeTextList(treasure.lore, treasure.history, treasure.provenance, treasure.origin,
        treasure.depicts, treasure.depiction, treasure.scene, treasure.event, treasure.recentEvent,
        treasure.inscription, treasure.inscriptions, treasure.minting, treasure.mintedWith,
        treasure.factionTie, treasure.factionTies, treasure.questHook)
    local value = treasureValue(treasure)
    local valueNotes = normalizeTextList(treasure.valueNote, treasure.valueNotes, treasure.pricingNote,
        treasure.pricingNotes, treasure.appraisal, treasure.appraisals, treasure.market, treasure.marketNotes)
    local guards = normalizeTextList(treasure.guardedBy, treasure.guard, treasure.guards, treasure.behindTrap,
        treasure.behindHazard, treasure.protectedBy, treasure.gatedBy, treasure.lockedBy, treasure.risk,
        treasure.hazard, treasure.trap)
    local location = roomContentLocation(treasure, opts)
    local coinish = treasureIsCoinKind(kind) or treasure.gold ~= nil or treasure.coins ~= nil or
        treasure.currency == true
    local interestingAuthored = #forms > 0 or #lore > 0 or
        (kind ~= nil and not treasureIsCoinKind(kind)) or treasure.art == true or treasure.jewelry == true or
        treasure.relic == true
    local valueAuthored = value ~= nil or #valueNotes > 0 or treasure.priceless == true or
        treasure.noFixedValue == true
    local guardedAuthored = #guards > 0
    local missing = {}
    if not description then
        missing[#missing + 1] = "treasure_description"
    end
    if opts.requireTreasureLore == true and #lore == 0 then
        missing[#missing + 1] = "treasure_lore_or_provenance"
    end
    if opts.requireTreasureValue == true and not valueAuthored then
        missing[#missing + 1] = "treasure_value_or_pricing_note"
    end
    if opts.requireGuardedTreasure == true and not guardedAuthored then
        missing[#missing + 1] = "treasure_guard_or_gate"
    end
    if opts.requireInterestingTreasure == true and not interestingAuthored then
        missing[#missing + 1] = "interesting_non_coin_treasure"
    end
    if opts.requireTreasurePlacement == true and not location then
        missing[#missing + 1] = "treasure_room_placement"
    end

    local detail = {
        id = treasure.id,
        name = trimString(treasure.name or treasure.id),
        description = description,
        kind = kind,
        location = location,
        forms = forms,
        lore = lore,
        value = value,
        valueNotes = valueNotes,
        guardedBy = guards,
        valueAuthored = valueAuthored,
        loreAuthored = #lore > 0,
        guardedAuthored = guardedAuthored,
        interestingAuthored = interestingAuthored,
        coinOnly = coinish and not interestingAuthored,
        warnings = {},
        warningFlags = {},
        missing = missing,
        guidance = M.TREASURE_AUTHORING_GUIDANCE,
    }
    if #lore == 0 then
        addTreasureWarning(detail, "treasure_lore_missing")
    end
    if not valueAuthored then
        addTreasureWarning(detail, "treasure_value_missing")
    end
    if not guardedAuthored then
        addTreasureWarning(detail, "treasure_guard_missing")
    end
    if not location and (opts.warnMissingPlacement == true or opts.requireTreasurePlacement == true) then
        addTreasureWarning(detail, "treasure_room_placement_missing")
    end
    if detail.coinOnly then
        addTreasureWarning(detail, "treasure_coin_only")
    end
    if #missing > 0 then
        return false, "Treasure incomplete", detail
    end
    return true, "treasure_valid", detail
end

local function denizenStatReference(denizen)
    local ref = denizen.statBlock or denizen.statblock or denizen.statBlockId or denizen.blueprintId or
        denizen.monsterId or denizen.creatureId or denizen.templateId or denizen.npcId
    if ref then
        return ref
    end
    if denizen.attributes or denizen.stats or denizen.health or denizen.defense or
        denizen.npcHealth or denizen.npcDefense then
        return "authored_stats"
    end
    return nil
end

function M.validateDenizen(denizen, opts)
    opts = opts or {}
    if type(denizen) ~= "table" then
        local name = trimString(denizen)
        if not name then
            return false, "Denizen required"
        end
        denizen = {
            name = name,
        }
    end

    local name = trimString(denizen.name or denizen.id or denizen.npc or denizen.creature or denizen.monster)
    local location = trimString(denizen.roomId or denizen.room or denizen.location or denizen.placement or
        opts.roomId)
    local statReference = denizenStatReference(denizen)
    local motivations = normalizeTextList(denizen.motivation, denizen.motivations, denizen.wants,
        denizen.goals, denizen.desires, denizen.protects, denizen.seeks)
    local likes = normalizeTextList(denizen.likes, denizen.like, denizen.socialLikes)
    local dislikes = normalizeTextList(denizen.dislikes, denizen.dislike, denizen.hates, denizen.avoids,
        denizen.socialDislikes)
    local tactics = normalizeTextList(denizen.tactics, denizen.tactic, denizen.behavior, denizen.behaviours,
        denizen.combatBehavior, denizen.specialBehavior, denizen.defaultAction)
    local missing = {}
    if not name then
        missing[#missing + 1] = "denizen_name"
    end
    if not location then
        missing[#missing + 1] = "denizen_room_placement"
    end
    if opts.requireDenizenStatBlock == true and not statReference then
        missing[#missing + 1] = "denizen_stat_block"
    end
    if opts.requireDenizenMotivation == true and #motivations == 0 then
        missing[#missing + 1] = "denizen_motivation"
    end
    if opts.requireDenizenTactics == true and #tactics == 0 then
        missing[#missing + 1] = "denizen_tactics"
    end
    if opts.requireDenizenSocialPreferences == true and #likes == 0 and #dislikes == 0 then
        missing[#missing + 1] = "denizen_likes_or_dislikes"
    end

    local warnings = {}
    local warningFlags = {}
    local function warn(flag)
        warningFlags[flag] = true
        warnings[#warnings + 1] = flag
    end
    if not statReference then
        warn("denizen_stat_block_missing")
    end
    if #motivations == 0 then
        warn("denizen_motivation_missing")
    end
    if #tactics == 0 then
        warn("denizen_tactics_missing")
    end
    if #likes == 0 and #dislikes == 0 then
        warn("denizen_social_preferences_missing")
    end

    local detail = {
        id = denizen.id,
        name = name,
        location = location,
        statReference = statReference,
        motivations = motivations,
        likes = likes,
        dislikes = dislikes,
        tactics = tactics,
        disposition = denizen.disposition or denizen.startingDisposition or denizen.defaultDisposition,
        faction = denizen.faction,
        warnings = warnings,
        warningFlags = warningFlags,
        missing = missing,
        guidance = M.DENIZEN_AUTHORING_GUIDANCE,
    }
    if #missing > 0 then
        return false, "Denizen incomplete", detail
    end
    return true, "denizen_valid", detail
end

function M.validateRoomFeature(feature, opts)
    opts = opts or {}
    if type(feature) ~= "table" then
        return false, "Room feature required"
    end

    local promptValue = featurePromptValue(feature)
    local prompt = promptValue and M.getRoomFeaturePrompt(promptValue) or nil
    local hooks = featureHooks(feature)
    local hooksPresent = hookList(hooks)
    local location = roomContentLocation(feature, opts)
    local missing = {}
    if not trimString(feature.name or feature.id) then
        missing[#missing + 1] = "feature_name"
    end
    if not trimString(feature.description or feature.summary) then
        missing[#missing + 1] = "feature_description"
    end
    if opts.strictPrompt == true and not prompt then
        missing[#missing + 1] = "appendix_e_feature_prompt"
    end
    if #hooksPresent == 0 then
        missing[#missing + 1] = "interactive_hook"
    end
    if opts.requireFeaturePlacement == true and not location then
        missing[#missing + 1] = "feature_room_placement"
    end

    local detail = {
        id = feature.id,
        name = feature.name,
        location = location,
        promptValue = promptValue,
        prompt = prompt,
        hooks = hooksPresent,
        hookFlags = hooks,
        missing = missing,
        guidance = M.ROOM_CONTENT_AUTHORING_GUIDANCE,
    }
    if #missing > 0 then
        return false, "Room feature incomplete", detail
    end
    return true, "room_feature_valid", detail
end

local function trapSolutions(trap)
    return normalizeTextList(
        trap.solutions,
        trap.safeSolutions,
        trap.bypassOptions,
        trap.disarmOptions,
        trap.playerOptions,
        trap.countermeasures
    )
end

local function trapTelegraphs(trap)
    return normalizeTextList(
        trap.telegraph,
        trap.telegraphs,
        trap.clues,
        trap.warning,
        trap.warnings,
        trap.sensoryClues,
        trap.sight,
        trap.smell,
        trap.sound,
        trap.touch,
        trap.taste
    )
end

local TRAP_SENSORY_FIELD_ALIASES = {
    sight = { "sight", "sights", "visual", "visible", "look" },
    sound = { "sound", "sounds", "audio", "noise", "hearing" },
    smell = { "smell", "smells", "scent", "odor", "odour" },
    touch = { "touch", "feel", "feeling", "temperature", "texture", "tactile" },
    taste = { "taste", "flavor", "flavour" },
}

local TRAP_SENSORY_ORDER = {
    "sight",
    "sound",
    "smell",
    "touch",
    "taste",
}

local function markTrapSensoryChannel(flags, channel, value)
    if hasListValue(value) then
        flags[channel] = true
    end
end

local function markTrapSensoryAliases(flags, source)
    if type(source) ~= "table" then
        return
    end
    for channel, aliases in pairs(TRAP_SENSORY_FIELD_ALIASES) do
        for _, alias in ipairs(aliases) do
            markTrapSensoryChannel(flags, channel, source[alias])
        end
    end
end

local function trapSensoryChannels(trap)
    local flags = {}
    markTrapSensoryAliases(flags, trap)
    markTrapSensoryAliases(flags, trap.sensoryClues)
    markTrapSensoryAliases(flags, trap.sensory)
    local channels = {}
    for _, channel in ipairs(TRAP_SENSORY_ORDER) do
        if flags[channel] then
            channels[#channels + 1] = channel
        end
    end
    return channels
end

function M.validateTrap(trap, opts)
    opts = opts or {}
    if type(trap) ~= "table" then
        return false, "Trap required"
    end

    local guarded = trimString(trap.guards or trap.guardedThing or trap.protects or trap.reward or
        trap.treasure or trap.prize)
    local telegraphs = trapTelegraphs(trap)
    local sensoryChannels = trapSensoryChannels(trap)
    local trigger = trimString(trap.trigger or trap.triggerCondition or trap.activatedBy)
    local consequences = trap.consequence or trap.consequences or trap.effect or trap.effects or
        trap.damage or trap.wound or trap.result
    local solutions = trapSolutions(trap)
    local talentGate = trap.requiredTalent or trap.requiresTalent or trap.onlyTalent or trap.talentGate
    local location = roomContentLocation(trap, opts)

    local missing = {}
    if not trimString(trap.name or trap.id) then
        missing[#missing + 1] = "trap_name"
    end
    if not trimString(trap.description or trap.summary) then
        missing[#missing + 1] = "trap_description"
    end
    if not guarded then
        missing[#missing + 1] = "guarded_reward"
    end
    if #telegraphs == 0 then
        missing[#missing + 1] = "telegraph"
    end
    local minSensoryChannels = tonumber(opts.minTrapSensoryChannels) or
        (opts.requireTrapSensoryTelegraphs == true and 2 or 0)
    if minSensoryChannels > 0 and #sensoryChannels < minSensoryChannels then
        missing[#missing + 1] = "sensory_telegraph_channels"
    end
    if not trigger then
        missing[#missing + 1] = "trigger"
    end
    if not hasListValue(consequences) then
        missing[#missing + 1] = "consequence"
    end
    if #solutions == 0 then
        missing[#missing + 1] = "bypass_or_disarm"
    end
    if talentGate and opts.allowTalentGate ~= true then
        missing[#missing + 1] = "no_special_talent_gate"
    end
    if opts.requireTrapPlacement == true and not location then
        missing[#missing + 1] = "trap_room_placement"
    end

    local warnings = {}
    if trap.testFateRequired == true or trap.requiresTestFate == true then
        warnings[#warnings + 1] = "test_fate_should_follow_failed_safe_handling"
    end
    if not location and (opts.warnMissingPlacement == true or opts.requireTrapPlacement == true) then
        warnings[#warnings + 1] = "trap_room_placement_missing"
    end

    local detail = {
        id = trap.id,
        name = trap.name,
        location = location,
        guarded = guarded,
        telegraphs = telegraphs,
        sensoryChannels = sensoryChannels,
        trigger = trigger,
        solutions = solutions,
        warnings = warnings,
        missing = missing,
        guidance = M.ROOM_CONTENT_AUTHORING_GUIDANCE,
    }
    if #missing > 0 then
        return false, "Trap incomplete", detail
    end
    return true, "trap_valid", detail
end

local function collectRoomFeatureList(room)
    local features = room and (room.features or room.roomFeatures or room.interactiveFeatures) or {}
    local list = {}
    for _, feature in ipairs(features) do
        list[#list + 1] = feature
    end
    return list
end

local function collectTrapList(room)
    local traps = room and (room.traps or room.roomTraps) or {}
    local list = {}
    for _, trap in ipairs(traps) do
        list[#list + 1] = trap
    end
    for _, feature in ipairs(collectRoomFeatureList(room)) do
        if feature.trap == true or type(feature.trap) == "table" or feature.type == "trap" then
            list[#list + 1] = type(feature.trap) == "table" and feature.trap or feature
        end
    end
    return list
end

local function addTreasureEntries(list, source)
    if source == nil then
        return
    end
    if type(source) == "table" and #source > 0 and
        not (source.id or source.name or source.description or source.value or source.gold or source.lore) then
        for _, entry in ipairs(source) do
            list[#list + 1] = entry
        end
    else
        list[#list + 1] = source
    end
end

local function collectTreasureList(room)
    local list = {}
    addTreasureEntries(list, room and (room.treasures or room.treasure or room.loot))
    for _, feature in ipairs(collectRoomFeatureList(room)) do
        local featureType = normalizeIdentifier(feature.type or feature.category)
        if featureType == "treasure" then
            list[#list + 1] = feature
        elseif feature.treasure ~= nil then
            if type(feature.treasure) == "table" then
                local treasure = copy(feature.treasure)
                treasure.id = treasure.id or feature.id
                treasure.name = treasure.name or feature.name
                treasure.description = treasure.description or feature.description or feature.summary
                list[#list + 1] = treasure
            else
                list[#list + 1] = {
                    id = feature.id,
                    name = feature.name,
                    description = feature.description or feature.summary or feature.treasure,
                    value = feature.value,
                    lore = feature.lore,
                    guardedBy = feature.guardedBy or feature.trap or feature.hazard,
                }
            end
        end
    end
    return list
end

local function addDenizenEntries(list, source)
    if source == nil then
        return
    end
    if type(source) == "table" and #source > 0 and
        not (source.id or source.name or source.description or source.statBlock or source.blueprintId) then
        for _, entry in ipairs(source) do
            list[#list + 1] = entry
        end
    else
        list[#list + 1] = source
    end
end

local function collectDenizenList(room)
    local list = {}
    addDenizenEntries(list, room and (room.denizens or room.creatures or room.monsters or room.npcs))
    for _, feature in ipairs(collectRoomFeatureList(room)) do
        local featureType = normalizeIdentifier(feature.type or feature.category)
        if featureType == "creature" or featureType == "monster" or featureType == "npc" or
            feature.npc or feature.creature or feature.monster then
            list[#list + 1] = feature
        end
    end
    return list
end

function M.validateRoomFeatureAuthoring(room, opts)
    opts = opts or {}
    if type(room) ~= "table" then
        return false, "Room required"
    end

    local validFeatures = {}
    local invalidFeatures = {}
    local featureOptions = copy(opts)
    featureOptions.roomId = featureOptions.roomId or room.id
    for _, feature in ipairs(collectRoomFeatureList(room)) do
        local ok, reason, detail = M.validateRoomFeature(feature, featureOptions)
        if ok then
            validFeatures[#validFeatures + 1] = detail
        else
            invalidFeatures[#invalidFeatures + 1] = {
                reason = reason,
                detail = detail,
            }
        end
    end

    local validTraps = {}
    local invalidTraps = {}
    local trapOptions = copy(opts)
    trapOptions.roomId = trapOptions.roomId or room.id
    for _, trap in ipairs(collectTrapList(room)) do
        local ok, reason, detail = M.validateTrap(trap, trapOptions)
        if ok then
            validTraps[#validTraps + 1] = detail
        else
            invalidTraps[#invalidTraps + 1] = {
                reason = reason,
                detail = detail,
            }
        end
    end

    local validTreasures = {}
    local invalidTreasures = {}
    local treasureOptions = copy(opts)
    treasureOptions.roomId = treasureOptions.roomId or room.id
    for _, treasure in ipairs(collectTreasureList(room)) do
        local ok, reason, detail = M.validateTreasure(treasure, treasureOptions)
        if ok then
            validTreasures[#validTreasures + 1] = detail
        else
            invalidTreasures[#invalidTreasures + 1] = {
                reason = reason,
                detail = detail,
            }
        end
    end

    local validDenizens = {}
    local invalidDenizens = {}
    local denizenOptions = copy(opts)
    denizenOptions.roomId = denizenOptions.roomId or room.id
    for _, denizen in ipairs(collectDenizenList(room)) do
        local ok, reason, detail = M.validateDenizen(denizen, denizenOptions)
        if ok then
            validDenizens[#validDenizens + 1] = detail
        else
            invalidDenizens[#invalidDenizens + 1] = {
                reason = reason,
                detail = detail,
            }
        end
    end

    local detail = {
        roomId = room.id,
        features = validFeatures,
        traps = validTraps,
        treasures = validTreasures,
        denizens = validDenizens,
        invalidFeatures = invalidFeatures,
        invalidTraps = invalidTraps,
        invalidTreasures = invalidTreasures,
        invalidDenizens = invalidDenizens,
        counts = {
            features = #validFeatures,
            traps = #validTraps,
            treasures = #validTreasures,
            denizens = #validDenizens,
        },
    }
    if #validFeatures == 0 and #validTreasures == 0 and #validDenizens == 0 and opts.requireFeature ~= false then
        detail.missing = { "room_feature" }
        return false, "Room feature required", detail
    end
    if #invalidFeatures > 0 or #invalidTraps > 0 or #invalidTreasures > 0 or #invalidDenizens > 0 then
        return false, "Room feature authoring incomplete", detail
    end
    return true, "room_feature_authoring_valid", detail
end

function M.validateRoomFeatureAuthoringBatch(rooms, opts)
    opts = opts or {}
    local list = roomList(rooms)
    if #list == 0 then
        return false, "Rooms required"
    end

    local validRooms = {}
    local invalidRooms = {}
    for _, room in ipairs(list) do
        local ok, reason, detail = M.validateRoomFeatureAuthoring(room, opts)
        if ok then
            validRooms[#validRooms + 1] = detail
        else
            invalidRooms[#invalidRooms + 1] = {
                roomId = detail and detail.roomId or (type(room) == "table" and room.id or nil),
                reason = reason,
                detail = detail,
            }
        end
    end
    if #invalidRooms > 0 then
        return false, "Room feature authoring incomplete", {
            rooms = validRooms,
            invalidRooms = invalidRooms,
            count = #list,
        }
    end
    return true, "room_feature_authoring_batch_valid", {
        rooms = validRooms,
        count = #validRooms,
    }
end

local function mapInput(mapData)
    if type(mapData) ~= "table" then
        return nil
    end
    return mapData.map or mapData.dungeonMap or mapData.data or mapData
end

local function roomId(room, fallback)
    if type(room) ~= "table" then
        return nil
    end
    return room.id or room.key or room.roomId or room.number or fallback
end

local function roomNumber(room)
    if type(room) ~= "table" then
        return nil
    end
    local value = room.number or room.roomNumber or room.key or room.id
    if type(value) == "number" then
        return tostring(value)
    end
    value = trimString(value)
    if not value then
        return nil
    end
    return value:match("^(%d+)")
end

local function collectMapRooms(mapData)
    local rooms = mapData.rooms or mapData.areas or {}
    local list = {}
    local byId = {}
    for _, room in ipairs(rooms) do
        local id = roomId(room)
        list[#list + 1] = room
        if id then
            byId[id] = room
        end
    end
    if #list == 0 then
        for key, room in pairs(rooms) do
            if type(room) == "table" then
                local id = roomId(room, key)
                list[#list + 1] = room
                if id then
                    byId[id] = room
                end
            end
        end
    end
    return list, byId
end

local function connectionEndpoint(connection, key, index)
    if type(connection) ~= "table" then
        return nil
    end
    return connection[key] or connection[index]
end

local function connectionProperties(connection)
    if type(connection) ~= "table" then
        return {}
    end
    return connection.properties or connection
end

local function mapRoomShape(room)
    if type(room) ~= "table" then
        return nil
    end
    return trimString(room.shape or room.areaShape or room.mapShape or room.geometry or room.outline or
        room.drawShape or room.areaType)
end

local function mapPathwayType(connection)
    local props = connectionProperties(connection)
    return trimString(props.pathwayType or props.pathType or props.routeType or props.connectionType or
        props.kind or props.type or props.shape)
end

local function mapHasAreaSpacing(source, rooms)
    if source.leaveSpaceBetweenAreas == true or source.leavesSpaceBetweenAreas == true or
        source.areaSpacing == true or source.spacing == true then
        return true
    end
    local spacing = normalizeIdentifier(source.areaSpacing or source.spacing or source.mapSpacing)
    if spacing == "spaced" or spacing == "open" or spacing == "gapped" or spacing == "blank_space" then
        return true
    end
    for _, room in ipairs(rooms or {}) do
        if type(room) ~= "table" or not (room.position or room.x or room.y or room.bounds) then
            return false
        end
    end
    return #rooms > 0
end

local function edgeKey(a, b)
    if tostring(a) < tostring(b) then
        return tostring(a) .. ":" .. tostring(b)
    end
    return tostring(b) .. ":" .. tostring(a)
end

local function mapValueSet(values)
    local set = {}
    for _, value in ipairs(values or {}) do
        set[value] = true
    end
    return set
end

local function walkMapGraph(adjacency, start, seen)
    seen[start] = true
    for neighbor, _ in pairs(adjacency[start] or {}) do
        if not seen[neighbor] then
            walkMapGraph(adjacency, neighbor, seen)
        end
    end
end

local function graphConnected(roomIds, adjacency)
    if #roomIds == 0 then
        return false
    end
    local seen = {}
    walkMapGraph(adjacency, roomIds[1], seen)
    for _, id in ipairs(roomIds) do
        if not seen[id] then
            return false
        end
    end
    return true
end

local function graphHasCycle(roomIds, adjacency)
    local seen = {}
    local function visit(id, parent)
        seen[id] = true
        for neighbor, _ in pairs(adjacency[id] or {}) do
            if not seen[neighbor] then
                if visit(neighbor, id) then
                    return true
                end
            elseif neighbor ~= parent then
                return true
            end
        end
        return false
    end
    for _, id in ipairs(roomIds) do
        if not seen[id] and visit(id, nil) then
            return true
        end
    end
    return false
end

local function graphBridgeCount(roomIds, edges, adjacency)
    local count = 0
    for _, edge in ipairs(edges) do
        local trimmed = {}
        for _, id in ipairs(roomIds) do
            trimmed[id] = {}
            for neighbor, value in pairs(adjacency[id] or {}) do
                trimmed[id][neighbor] = value
            end
        end
        trimmed[edge.from][edge.to] = nil
        trimmed[edge.to][edge.from] = nil
        if not graphConnected(roomIds, trimmed) then
            count = count + 1
        end
    end
    return count
end

local function playerMapRooms(playerMap)
    if type(playerMap) ~= "table" then
        return {}
    end
    return playerMap.rooms or playerMap.knownRooms or playerMap.roomNumbers or {}
end

local function playerMapHasContentLeaks(playerMap)
    for _, room in ipairs(playerMapRooms(playerMap)) do
        if type(room) == "table" and
            (room.contents or room.features or room.traps or room.denizens or room.treasure) then
            return true
        end
    end
    return playerMap.revealsContents == true or playerMap.includesContents == true
end

local function playerMapAllowsNotes(playerMap)
    return playerMap.blankSpaceForNotes == true or playerMap.openSpace == true or
        playerMap.allowsPlayerNotes == true or playerMap.discoverySpace == true
end

function M.validateDungeonMap(mapData, opts)
    opts = opts or {}
    local source = mapInput(mapData)
    if type(source) ~= "table" then
        return false, "Dungeon map required"
    end

    local rooms, roomById = collectMapRooms(source)
    if #rooms == 0 then
        return false, "Map rooms required"
    end
    if #rooms == 1 and opts.allowSingleRoom ~= true then
        return false, "Map requires multiple rooms"
    end

    local levelNumber = tonumber(opts.levelNumber or source.levelNumber or source.level or source.ordinal)
    local missingRoomNumbers = {}
    local wrongLevelNumbers = {}
    local roomIds = {}
    local drawingRooms = {}
    local missingAreaShapes = {}
    for index, room in ipairs(rooms) do
        local id = roomId(room, tostring(index))
        local number = roomNumber(room)
        local shape = mapRoomShape(room)
        roomIds[#roomIds + 1] = id
        drawingRooms[#drawingRooms + 1] = {
            id = id,
            shape = shape,
        }
        if not shape then
            missingAreaShapes[#missingAreaShapes + 1] = id
        end
        if not number then
            missingRoomNumbers[#missingRoomNumbers + 1] = id
        elseif levelNumber and tostring(number):sub(1, #tostring(levelNumber)) ~= tostring(levelNumber) then
            wrongLevelNumbers[#wrongLevelNumbers + 1] = id
        end
    end

    local adjacency = {}
    local edges = {}
    local invalidConnections = {}
    local seenEdges = {}
    local drawingPathways = {}
    local missingPathwayTypes = {}
    for _, id in ipairs(roomIds) do
        adjacency[id] = {}
    end
    for _, connection in ipairs(source.connections or source.pathways or {}) do
        local from = connectionEndpoint(connection, "from", 1)
        local to = connectionEndpoint(connection, "to", 2)
        local pathwayType = mapPathwayType(connection)
        if not from or not to or not roomById[from] or not roomById[to] then
            invalidConnections[#invalidConnections + 1] = copy(connection)
        else
            adjacency[from][to] = true
            adjacency[to][from] = true
            local key = edgeKey(from, to)
            if not seenEdges[key] then
                seenEdges[key] = true
                edges[#edges + 1] = {
                    from = from,
                    to = to,
                    properties = copy(connectionProperties(connection)),
                }
            end
            drawingPathways[#drawingPathways + 1] = {
                from = from,
                to = to,
                pathwayType = pathwayType,
            }
            if not pathwayType then
                missingPathwayTypes[#missingPathwayTypes + 1] = {
                    from = from,
                    to = to,
                }
            end
        end
    end

    local missing = {}
    if #missingRoomNumbers > 0 then
        missing[#missing + 1] = "room_numbers"
    end
    if #wrongLevelNumbers > 0 then
        missing[#missing + 1] = "level_keyed_room_numbers"
    end
    if #edges == 0 then
        missing[#missing + 1] = "pathways"
    end
    if #invalidConnections > 0 then
        missing[#missing + 1] = "valid_pathways"
    end
    local areaSpacing = mapHasAreaSpacing(source, rooms)
    if opts.requireMapDrawingDetails == true then
        if #missingAreaShapes > 0 then
            missing[#missing + 1] = "area_shapes"
        end
        if #missingPathwayTypes > 0 then
            missing[#missing + 1] = "pathway_types"
        end
        if not areaSpacing then
            missing[#missing + 1] = "area_spacing"
        end
    end

    local connected = graphConnected(roomIds, adjacency)
    local hasCycle = graphHasCycle(roomIds, adjacency)
    local choiceNodes = {}
    for id, neighbors in pairs(adjacency) do
        local degree = 0
        for _, _ in pairs(neighbors) do
            degree = degree + 1
        end
        if degree >= 3 then
            choiceNodes[#choiceNodes + 1] = id
        end
    end
    local shortcutCount = 0
    for _, edge in ipairs(edges) do
        local props = edge.properties or {}
        if props.is_shortcut or props.shortcut or props.is_secret or props.secret then
            shortcutCount = shortcutCount + 1
        end
    end
    local bridgeCount = #edges > 0 and graphBridgeCount(roomIds, edges, adjacency) or 0
    if not connected then
        missing[#missing + 1] = "connected_map"
    end
    if opts.requireNonLinear ~= false and not hasCycle and #choiceNodes == 0 and shortcutCount == 0 then
        missing[#missing + 1] = "non_linear_paths"
    end
    local topologyChecklist = {
        shortcuts = shortcutCount > 0,
        chokePoints = bridgeCount > 0,
        feedbackLoops = hasCycle,
    }
    if opts.requireTopologyChecklist == true then
        if not topologyChecklist.shortcuts then
            missing[#missing + 1] = "shortcut_paths"
        end
        if not topologyChecklist.chokePoints then
            missing[#missing + 1] = "choke_points"
        end
        if not topologyChecklist.feedbackLoops then
            missing[#missing + 1] = "feedback_loops"
        end
    end

    local playerMap = source.playerMap or source.playerFacingMap or source.inCharacterMap
    local playerDetail = {
        required = opts.requirePlayerMap ~= false,
        rooms = {},
        majorityRoomsShown = false,
        noContents = true,
        blankSpaceForNotes = false,
    }
    if playerMap then
        playerDetail.rooms = playerMapRooms(playerMap)
        playerDetail.majorityRoomsShown = #playerDetail.rooms >= math.floor(#rooms / 2) + 1
        playerDetail.noContents = not playerMapHasContentLeaks(playerMap)
        playerDetail.blankSpaceForNotes = playerMapAllowsNotes(playerMap)
    end
    if playerDetail.required then
        if not playerMap then
            missing[#missing + 1] = "player_map"
        else
            if not playerDetail.majorityRoomsShown then
                missing[#missing + 1] = "player_map_majority_rooms"
            end
            if not playerDetail.noContents then
                missing[#missing + 1] = "player_map_without_contents"
            end
            if not playerDetail.blankSpaceForNotes then
                missing[#missing + 1] = "player_map_blank_space"
            end
        end
    end

    local detail = {
        levelNumber = levelNumber,
        roomCount = #rooms,
        connectionCount = #edges,
        missing = missing,
        missingRoomNumbers = missingRoomNumbers,
        wrongLevelNumbers = wrongLevelNumbers,
        invalidConnections = invalidConnections,
        drawing = {
            rooms = drawingRooms,
            pathways = drawingPathways,
            areaSpacing = areaSpacing,
            missingAreaShapes = missingAreaShapes,
            missingPathwayTypes = missingPathwayTypes,
        },
        topology = {
            connected = connected,
            hasCycle = hasCycle,
            choiceNodes = choiceNodes,
            shortcutCount = shortcutCount,
            bridgeCount = bridgeCount,
            checklist = topologyChecklist,
        },
        playerMap = playerDetail,
    }

    if #missing > 0 then
        return false, "Dungeon map incomplete", detail
    end
    return true, "dungeon_map_valid", detail
end

function M.validateDungeonMaps(maps, opts)
    opts = opts or {}
    local source = maps and (maps.maps or maps.levelMaps or maps)
    if type(source) ~= "table" then
        return false, "Dungeon maps required"
    end

    local list = {}
    for _, mapData in ipairs(source) do
        list[#list + 1] = mapData
    end
    if #list == 0 then
        for _, mapData in pairs(source) do
            if type(mapData) == "table" then
                list[#list + 1] = mapData
            end
        end
    end
    if #list == 0 then
        return false, "Dungeon maps required"
    end

    local validMaps = {}
    local invalidMaps = {}
    for _, mapData in ipairs(list) do
        local ok, reason, detail = M.validateDungeonMap(mapData, opts)
        if ok then
            validMaps[#validMaps + 1] = detail
        else
            invalidMaps[#invalidMaps + 1] = {
                reason = reason,
                detail = detail,
            }
        end
    end
    if #invalidMaps > 0 then
        return false, "Dungeon maps incomplete", {
            maps = validMaps,
            invalidMaps = invalidMaps,
            count = #list,
        }
    end
    return true, "dungeon_maps_valid", {
        maps = validMaps,
        count = #validMaps,
    }
end

local function isMajorSuit(suit)
    if suit == nil then
        return true
    end
    if suit == 5 then
        return true
    end
    local normalized = tostring(suit):lower()
    return normalized == "major" or normalized == "majors" or normalized == "trump"
end

local function normalizeCard(card)
    if type(card) == "number" then
        local seed = M.DUNGEON_SEEDS[card]
        return {
            value = card,
            name = seed and seed.cardName or ("Major " .. tostring(card)),
            is_major = true,
        }
    end
    if type(card) ~= "table" then
        return nil, "Major Arcana card required"
    end

    local value = tonumber(card.value or card.cardValue or card.majorValue or card[1])
    if not value or value ~= math.floor(value) then
        return nil, "Major Arcana card required"
    end
    if value == 0 then
        return nil, "The Fool is not used for Underworld layout"
    end
    if value < 1 or value > 21 then
        return nil, "Underworld layout requires Major Arcana I-XXI"
    end
    if card.is_major == false and not isMajorSuit(card.suit) then
        return nil, "Major Arcana card required"
    end

    local seed = M.DUNGEON_SEEDS[value]
    return {
        value = value,
        name = card.name or (seed and seed.cardName) or ("Major " .. tostring(value)),
        is_major = true,
        sourceCard = card,
    }
end

local function drawMajorCards(opts)
    local cards = opts.cards or opts.majorCards or opts.draws
    if cards then
        return cards
    end

    local deck = opts.deck or opts.gmDeck or opts.majorDeck
    local count = math.floor(tonumber(opts.count or opts.dungeonCount or opts.levelCount) or 0)
    if not deck or not deck.draw then
        return nil, "Major Arcana cards required"
    end
    if count < 3 then
        return nil, "At least three dungeons required"
    end

    local drawn = {}
    for _ = 1, count do
        local card = deck:draw()
        if not card then
            return nil, "Not enough Major Arcana cards"
        end
        drawn[#drawn + 1] = card
    end
    return drawn
end

local function entranceOptions(opts, level)
    local entrances = opts.entrances or opts.surfaceEntrances or {}
    return entrances[level.value] or entrances[level.id] or entrances[level.levelNumber] or {}
end

local function positionSurfaceLevels(levels)
    local offsets = {
        { x = 1, y = 0 },
        { x = -1, y = 0 },
        { x = 0, y = -1 },
        { x = 2, y = 0 },
    }
    for index, level in ipairs(levels) do
        local pos = offsets[index] or { x = index, y = 0 }
        level.position = { x = pos.x, y = pos.y }
        level.placement = "surface_entrance"
    end
end

local function addConnection(map, connections, a, b, reason)
    if not a or not b or a.value == b.value then
        return
    end

    local first = a
    local second = b
    if first.value > second.value then
        first, second = second, first
    end

    local key = tostring(first.value) .. ":" .. tostring(second.value)
    local connection = map[key]
    if not connection then
        connection = {
            from = first.id,
            to = second.id,
            fromValue = first.value,
            toValue = second.value,
            reasons = {},
            rulebookRules = {},
        }
        map[key] = connection
        connections[#connections + 1] = connection
    end

    if not connection.rulebookRules[reason] then
        connection.rulebookRules[reason] = true
        connection.reasons[#connection.reasons + 1] = reason
    end
end

local function layoutConnectionPairKey(a, b)
    a = tonumber(a)
    b = tonumber(b)
    if not a or not b then
        return nil
    end
    if a > b then
        a, b = b, a
    end
    return tostring(a) .. ":" .. tostring(b)
end

local function connectionRefValue(ref)
    if type(ref) == "number" then
        return ref
    end
    if type(ref) == "string" then
        return tonumber(ref:match("(%d+)$") or ref)
    end
    if type(ref) ~= "table" then
        return nil
    end
    return tonumber(ref.value or ref.cardValue or ref.majorValue or ref.dungeonValue or ref.levelValue or ref[1])
end

local function connectionDefinitionMap(opts)
    local source = opts.connectionDefinitions or opts.connectionDetails or opts.connectionDescriptions or
        opts.pathwayDefinitions or opts.pathwayDetails or {}
    local map = {}
    if type(source) ~= "table" then
        return map
    end
    for key, entry in pairs(source) do
        if type(entry) == "table" then
            local from = connectionRefValue(entry.from or entry.a or entry[1])
            local to = connectionRefValue(entry.to or entry.b or entry[2])
            if (not from or not to) and type(key) == "string" then
                from, to = key:match("(%d+)%D+(%d+)")
            elseif (not from or not to) and type(key) == "number" then
                from = key
                to = connectionRefValue(entry.connectsTo or entry.target or entry.destination)
            end
            local pairKey = layoutConnectionPairKey(from, to)
            if pairKey then
                map[pairKey] = entry
            end
        end
    end
    return map
end

local function connectionDefinitionPresent(connection)
    return trimString(connection.connectionType or connection.type or connection.kind or connection.routeType) ~= nil or
        trimString(connection.description or connection.pathway or connection.route or connection.notes) ~= nil
end

local function applyConnectionDefinitions(connections, opts)
    local definitions = connectionDefinitionMap(opts or {})
    for _, connection in ipairs(connections or {}) do
        local definition = definitions[layoutConnectionPairKey(connection.fromValue, connection.toValue)]
        if definition then
            connection.connectionType = trimString(definition.connectionType or definition.type or definition.kind or
                definition.routeType or definition.pathType)
            connection.description = trimString(definition.description or definition.pathway or definition.route or
                definition.howConnected or definition.summary)
            connection.notes = definition.notes
            connection.definition = copy(definition)
        end
        connection.requiresDefinition = not connectionDefinitionPresent(connection)
    end
    return connections
end

local function manhattan(a, b)
    return math.abs((a.position.x or 0) - (b.position.x or 0)) +
        math.abs((a.position.y or 0) - (b.position.y or 0))
end

local function buildConnections(levels)
    local connections = {}
    local connectionMap = {}

    for i = 1, #levels do
        for j = i + 1, #levels do
            local a = levels[i]
            local b = levels[j]
            if a.position and b.position and manhattan(a, b) == 1 then
                addConnection(connectionMap, connections, a, b, "physically_next")
            end
            if math.abs(a.value - b.value) == 1 then
                addConnection(connectionMap, connections, a, b, "sequential")
            end
            local high = math.max(a.value, b.value)
            local low = math.min(a.value, b.value)
            if low > 0 and high % low == 0 then
                addConnection(connectionMap, connections, a, b, "divisible")
            end
        end
    end

    table.sort(connections, function(a, b)
        if a.fromValue == b.fromValue then
            return a.toValue < b.toValue
        end
        return a.fromValue < b.fromValue
    end)
    return connections
end

local function levelEndpointId(endpoint, levelsById, levelsByValue)
    if type(endpoint) == "table" then
        endpoint = endpoint.id or endpoint.key or endpoint.value or endpoint.cardValue or endpoint[1]
    end
    if levelsById[endpoint] then
        return endpoint
    end
    local value = tonumber(endpoint)
    if value and levelsByValue[value] then
        return levelsByValue[value].id
    end
    return nil
end

local function depthResourcePressure(score, deepest)
    if score <= 0 then
        return "entrance"
    end
    if deepest then
        return "deepest"
    end
    if score == 1 then
        return "lower"
    end
    if score == 2 then
        return "deep"
    end
    return "remote"
end

local function buildDepthProfiles(levels, connections)
    local levelsById = {}
    local levelsByValue = {}
    local adjacency = {}
    for index, level in ipairs(levels) do
        if not level.id then
            level.id = "dungeon_" .. tostring(index)
        end
        levelsById[level.id] = level
        if level.value then
            levelsByValue[level.value] = level
        end
        adjacency[level.id] = {}
    end

    for _, connection in ipairs(connections or {}) do
        local from = levelEndpointId(connection.from or connection.a or connection[1], levelsById, levelsByValue)
        local to = levelEndpointId(connection.to or connection.b or connection[2], levelsById, levelsByValue)
        if from and to and adjacency[from] and adjacency[to] then
            adjacency[from][to] = true
            adjacency[to][from] = true
        end
    end

    local queue = {}
    local distances = {}
    for _, level in ipairs(levels) do
        if level.surfaceEntrance or level.mainEntrance then
            distances[level.id] = 0
            queue[#queue + 1] = level.id
        end
    end
    local cursor = 1
    while queue[cursor] do
        local id = queue[cursor]
        cursor = cursor + 1
        for nextId, _ in pairs(adjacency[id] or {}) do
            if distances[nextId] == nil then
                distances[nextId] = distances[id] + 1
                queue[#queue + 1] = nextId
            end
        end
    end

    local profiles = {}
    for index, level in ipairs(levels) do
        local verticalDepth = 0
        if level.position and tonumber(level.position.y) then
            verticalDepth = math.max(0, tonumber(level.position.y))
        else
            verticalDepth = math.max(0, (tonumber(level.levelNumber) or index) - 1)
        end
        local distance = distances[level.id]
        local score = math.max(verticalDepth, distance or verticalDepth)
        local profile = {
            levelId = level.id,
            value = level.value,
            levelNumber = level.levelNumber,
            verticalDepth = verticalDepth,
            distanceFromEntrance = distance,
            resourcePressureScore = score,
            resourcePressure = depthResourcePressure(score, level.deepest == true),
            requiresMoreTorchesAndRations = score > 0,
            riskGuidance = score > 0 and
                "Consider more difficult risks for dungeon levels farther from egress." or nil,
            rewardGuidance = score > 0 and
                "Consider more extravagant rewards for dungeon levels that cost more torches and rations to reach." or nil,
            deepestQuestion = level.deepest == true and
                "What lurks inside the deepest dungeon, farthest from egress?" or nil,
        }
        level.depthProfile = profile
        profiles[#profiles + 1] = profile
    end
    return profiles
end

function M.generateLayout(opts)
    opts = opts or {}

    local origins = opts.origins or opts.origin
    if opts.requireOrigins == true or opts.validateOrigins == true then
        local originRecord, originReason = M.recordOrigins(origins)
        if not originRecord then
            return nil, originReason
        end
        origins = originRecord
    elseif origins then
        local originRecord = M.recordOrigins(origins)
        origins = originRecord or copy(origins)
    end

    local cards, drawReason = drawMajorCards(opts)
    if not cards then
        return nil, drawReason
    end

    local normalizedCards = {}
    local seenValues = {}
    for _, card in ipairs(cards) do
        local normalized, reason = normalizeCard(card)
        if not normalized then
            return nil, reason
        end
        if seenValues[normalized.value] then
            return nil, "Duplicate dungeon card"
        end
        seenValues[normalized.value] = true
        normalizedCards[#normalizedCards + 1] = normalized
    end

    if #normalizedCards < 3 then
        return nil, "At least three dungeons required"
    end

    table.sort(normalizedCards, function(a, b)
        return a.value < b.value
    end)

    local mainEntrance = normalizedCards[1]
    local deepest = normalizedCards[#normalizedCards]
    local levels = {}
    local surfaceLevels = {}
    local lowerLevels = {}

    for index, card in ipairs(normalizedCards) do
        local seed = M.getDungeonSeed(card.value) or {}
        local level = {
            id = "dungeon_" .. string.format("%02d", card.value),
            levelNumber = index,
            value = card.value,
            cardName = card.name,
            seedName = seed.name,
            seedSummary = seed.summary,
            seedLighting = seed.lighting,
            seedSensory = copy(seed.sensory),
            seedStructures = seed.structures,
            commonMonsters = copy(seed.commonMonsters or {}),
            commonMonsterNote = seed.commonMonsterNote,
            dungeonLord = seed.dungeonLord,
            dungeonSeed = copy(seed),
            mainEntrance = card == mainEntrance,
            surfaceEntrance = card == mainEntrance or card.value <= 5,
            deepest = card == deepest,
            sourceCard = copy(card.sourceCard),
        }
        levels[#levels + 1] = level
        if level.surfaceEntrance then
            surfaceLevels[#surfaceLevels + 1] = level
        else
            lowerLevels[#lowerLevels + 1] = level
        end
    end

    mainEntrance = levels[1]
    deepest = levels[#levels]
    mainEntrance.position = { x = 0, y = 0 }
    mainEntrance.placement = "main_entrance"

    local extraSurface = {}
    for _, level in ipairs(surfaceLevels) do
        if level ~= mainEntrance then
            extraSurface[#extraSurface + 1] = level
        end
    end
    positionSurfaceLevels(extraSurface)

    for index, level in ipairs(lowerLevels) do
        level.position = { x = 0, y = index }
        level.placement = level.deepest and "deepest" or "between_entrance_and_deepest"
    end

    local entranceRecords = {}
    for _, level in ipairs(levels) do
        if level.surfaceEntrance then
            local entry = entranceOptions(opts, level)
            level.entrance = {
                main = level.mainEntrance,
                surface = true,
                known = entry.known,
                traversable = entry.traversable,
                sealed = entry.sealed,
                secret = entry.secret,
                notes = entry.notes,
                requiresDecision = not level.mainEntrance and
                    entry.known == nil and entry.traversable == nil and entry.sealed == nil,
            }
            entranceRecords[#entranceRecords + 1] = {
                id = level.id,
                value = level.value,
                main = level.entrance.main,
                known = level.entrance.known,
                traversable = level.entrance.traversable,
                sealed = level.entrance.sealed,
                secret = level.entrance.secret,
                requiresDecision = level.entrance.requiresDecision,
            }
        end
    end

    local connections = applyConnectionDefinitions(buildConnections(levels), opts)
    local depthProfiles = buildDepthProfiles(levels, connections)

    local layout = {
        origins = copy(origins),
        levels = levels,
        entrances = entranceRecords,
        connections = connections,
        depthProfiles = depthProfiles,
        mainEntrance = mainEntrance,
        deepest = deepest,
        procedure = M.PROCEDURE_STEPS,
    }
    layout.counts = {
        levels = #levels,
        entrances = #entranceRecords,
        connections = #layout.connections,
        depthProfiles = #depthProfiles,
    }

    return layout, "underworld_layout_generated", {
        levels = levels,
        entrances = entranceRecords,
        connections = layout.connections,
        depthProfiles = depthProfiles,
        mainEntrance = mainEntrance,
        deepest = deepest,
        result = "underworld_layout_generated",
    }
end

local function layoutLevelList(layout)
    local source = layout and (layout.levels or layout.dungeons or layout.dungeonLevels)
    local list = {}
    if type(source) ~= "table" then
        return list
    end
    for _, level in ipairs(source) do
        if type(level) == "table" then
            list[#list + 1] = level
        end
    end
    if #list == 0 then
        for _, level in pairs(source) do
            if type(level) == "table" then
                list[#list + 1] = level
            end
        end
    end
    return list
end

local function layoutValue(record)
    if type(record) == "number" then
        return record
    end
    if type(record) == "string" then
        return tonumber(record:match("(%d+)$") or record)
    end
    if type(record) ~= "table" then
        return nil
    end
    return tonumber(record.value or record.cardValue or record.majorValue or record.dungeonValue)
end

local function layoutRefValue(ref, levels)
    local value = layoutValue(ref)
    if value then
        return value
    end
    if type(ref) ~= "string" then
        return nil
    end
    for _, level in ipairs(levels) do
        if level.id == ref or level.key == ref or level.name == ref then
            return layoutValue(level)
        end
    end
    return nil
end

local function markedLayoutValue(levels, field)
    for _, level in ipairs(levels) do
        if level[field] == true then
            return layoutValue(level)
        end
    end
    return nil
end

local function layoutConnectionList(layout)
    local source = layout and (layout.connections or layout.pathways or layout.edges)
    local list = {}
    if type(source) ~= "table" then
        return list
    end
    for _, connection in ipairs(source) do
        if type(connection) == "table" then
            list[#list + 1] = connection
        end
    end
    if #list == 0 then
        for _, connection in pairs(source) do
            if type(connection) == "table" then
                list[#list + 1] = connection
            end
        end
    end
    return list
end

local function layoutEndpointValue(endpoint, levels)
    local value = layoutValue(endpoint)
    if value then
        return value
    end
    if type(endpoint) ~= "string" then
        return nil
    end
    for _, level in ipairs(levels) do
        if level.id == endpoint or level.key == endpoint or level.name == endpoint then
            return layoutValue(level)
        end
    end
    return nil
end

local function layoutHasConnection(layout, levels, a, b)
    for _, connection in ipairs(layoutConnectionList(layout)) do
        local fromValue = tonumber(connection.fromValue or connection.aValue) or
            layoutEndpointValue(connection.from or connection.a or connection[1], levels)
        local toValue = tonumber(connection.toValue or connection.bValue) or
            layoutEndpointValue(connection.to or connection.b or connection[2], levels)
        if (fromValue == a and toValue == b) or (fromValue == b and toValue == a) then
            return true
        end
    end
    return false
end

local function layoutEntranceRecord(layout, level)
    local entrances = layout and (layout.entrances or layout.surfaceEntrances or layout.entryways) or {}
    if type(entrances) ~= "table" then
        return level.entrance
    end
    local value = layoutValue(level)
    local direct = entrances[value] or entrances[level.id] or entrances[level.key]
    if type(direct) == "table" then
        return direct
    end
    for key, entry in pairs(entrances) do
        if type(entry) == "table" and
            ((entry.id ~= nil and entry.id == level.id) or
                (entry.key ~= nil and level.key ~= nil and entry.key == level.key) or
                layoutValue(entry) == value or tonumber(key) == value) then
            return entry
        end
    end
    return level.entrance
end

function M.validateLayout(layout, opts)
    opts = opts or {}
    if type(layout) ~= "table" then
        return false, "Underworld layout required"
    end

    local levels = layoutLevelList(layout)
    local validLevels = {}
    local seenValues = {}
    local duplicateValues = {}
    local invalidLevels = {}
    for _, level in ipairs(levels) do
        local value = layoutValue(level)
        if not value or value ~= math.floor(value) or value < 1 or value > 21 then
            invalidLevels[#invalidLevels + 1] = level.id or level.name or tostring(#invalidLevels + 1)
        elseif seenValues[value] then
            duplicateValues[#duplicateValues + 1] = value
        else
            seenValues[value] = true
            validLevels[#validLevels + 1] = level
        end
    end
    table.sort(validLevels, function(a, b)
        return layoutValue(a) < layoutValue(b)
    end)

    local missing = {}
    if #levels == 0 then
        missing[#missing + 1] = "layout_levels"
    end
    if #validLevels < 3 then
        missing[#missing + 1] = "three_unique_major_arcana_levels"
    end
    if #invalidLevels > 0 then
        missing[#missing + 1] = "major_arcana_i_xxi"
    end
    if #duplicateValues > 0 then
        missing[#missing + 1] = "unique_dungeon_cards"
    end

    local mainValue = layoutRefValue(layout.mainEntrance or layout.main_entrance, validLevels) or
        markedLayoutValue(validLevels, "mainEntrance")
    local deepestValue = layoutRefValue(layout.deepest or layout.deepestDungeon, validLevels) or
        markedLayoutValue(validLevels, "deepest")
    local lowestValue = validLevels[1] and layoutValue(validLevels[1]) or nil
    local highestValue = validLevels[#validLevels] and layoutValue(validLevels[#validLevels]) or nil
    if lowestValue and mainValue ~= lowestValue then
        missing[#missing + 1] = "main_entrance_lowest_card"
    end
    if highestValue and deepestValue ~= highestValue then
        missing[#missing + 1] = "deepest_highest_card"
    end

    local pendingEntrances = {}
    local surfaceEntranceValues = {}
    for _, level in ipairs(validLevels) do
        local value = layoutValue(level)
        if value == lowestValue or value <= 5 then
            surfaceEntranceValues[#surfaceEntranceValues + 1] = value
            local entry = layoutEntranceRecord(layout, level)
            local marked = level.surfaceEntrance == true or level.mainEntrance == true or
                (type(entry) == "table" and entry.surface == true)
            if not marked then
                missing[#missing + 1] = "surface_entrances"
            end
            if value ~= lowestValue then
                if type(entry) ~= "table" or entry.requiresDecision == true or
                    (entry.known == nil and entry.traversable == nil and entry.sealed == nil) then
                    pendingEntrances[#pendingEntrances + 1] = value
                end
            end
        end
    end
    if #pendingEntrances > 0 then
        missing[#missing + 1] = "surface_entrance_decisions"
    end

    local savedConnections = layoutConnectionList(layout)
    local missingConnections = {}
    for _, connection in ipairs(buildConnections(validLevels)) do
        if not layoutHasConnection(layout, validLevels, connection.fromValue, connection.toValue) then
            missingConnections[#missingConnections + 1] = {
                fromValue = connection.fromValue,
                toValue = connection.toValue,
                reasons = copy(connection.reasons),
            }
        end
    end
    if #missingConnections > 0 then
        missing[#missing + 1] = "layout_connections"
    end

    local undefinedConnections = {}
    if opts.requireConnectionDefinitions == true then
        for _, connection in ipairs(savedConnections) do
            if not connectionDefinitionPresent(connection) then
                undefinedConnections[#undefinedConnections + 1] = {
                    fromValue = tonumber(connection.fromValue or connection.aValue) or
                        layoutEndpointValue(connection.from or connection.a or connection[1], validLevels),
                    toValue = tonumber(connection.toValue or connection.bValue) or
                        layoutEndpointValue(connection.to or connection.b or connection[2], validLevels),
                }
            end
        end
        if #undefinedConnections > 0 then
            missing[#missing + 1] = "connection_definitions"
        end
    end

    local depthProfiles = layout.depthProfiles
    if type(depthProfiles) ~= "table" or #depthProfiles == 0 then
        depthProfiles = buildDepthProfiles(validLevels, savedConnections)
    end

    local detail = {
        levels = validLevels,
        count = #validLevels,
        missing = missing,
        invalidLevels = invalidLevels,
        duplicateValues = duplicateValues,
        mainEntranceValue = mainValue,
        deepestValue = deepestValue,
        surfaceEntranceValues = surfaceEntranceValues,
        pendingEntrances = pendingEntrances,
        missingConnections = missingConnections,
        undefinedConnections = undefinedConnections,
        depthProfiles = depthProfiles,
        result = #missing == 0 and "underworld_layout_valid" or "underworld_layout_incomplete",
    }
    if #missing > 0 then
        return false, "Underworld layout incomplete", detail
    end
    return true, "underworld_layout_valid", detail
end

local function addDraftStep(report, key, ok, reason, detail)
    local step = {
        key = key,
        status = ok and "complete" or "blocked",
        complete = ok == true,
        result = ok and reason or nil,
        reason = ok and nil or reason,
        detail = detail,
    }
    report.steps[#report.steps + 1] = step
    report.stepsByKey[key] = step
    if not ok then
        report.blockers[#report.blockers + 1] = {
            step = key,
            reason = reason,
            missing = detail and detail.missing,
        }
    end
    return step
end

local function draftLayoutInput(draft, origins)
    return {
        cards = draft.cards or draft.majorCards or draft.draws,
        deck = draft.deck or draft.gmDeck or draft.majorDeck,
        count = draft.count or draft.dungeonCount or draft.levelCount,
        entrances = draft.entrances or draft.surfaceEntrances,
        origins = origins or draft.origins or draft.origin,
        requireOrigins = false,
        validateOrigins = false,
    }
end

local function draftFeatureRooms(draft)
    local source = draft.featureRooms or draft.roomFeatures or draft.rooms or
        draft.roomDescriptions or draft.levelRooms
    local rooms = roomList(source)
    if #rooms == 0 and (draft.features or draft.traps) then
        rooms[#rooms + 1] = {
            id = "underworld_features",
            features = draft.features or {},
            traps = draft.traps or {},
        }
    end
    return rooms
end

local function draftFactionInput(draft)
    return draft.factions or draft.levelFactions or draft.controllingFactions or draft.powerFactions
end

function M.validateUnderworldDraft(draft, opts)
    opts = opts or {}
    local report = {
        steps = {},
        stepsByKey = {},
        blockers = {},
        counts = {},
        readyForAuthoringUI = false,
        readyForPlay = false,
        result = "underworld_draft_incomplete",
    }
    if type(draft) ~= "table" then
        addDraftStep(report, "origins", false, "Underworld draft required")
        return false, "Underworld draft required", report
    end

    local origins, originReason, originDetail = M.recordOrigins(draft.origins or draft.origin)
    addDraftStep(report, "origins", origins ~= nil, origins and "underworld_origins_valid" or originReason,
        originDetail)
    if origins then
        report.origins = origins
        report.counts.openQuestions = #origins.openQuestions
    end

    local layout
    local layoutOk
    local layoutReason
    local layoutDetail
    if draft.layout then
        layoutOk, layoutReason, layoutDetail = M.validateLayout(draft.layout, opts.layoutOptions)
        layout = layoutOk and draft.layout or nil
    else
        layout, layoutReason, layoutDetail = M.generateLayout(draftLayoutInput(draft, origins))
        layoutOk = layout ~= nil
    end
    addDraftStep(report, "generate_layout", layoutOk, layoutOk and "underworld_layout_valid" or layoutReason,
        layoutDetail)
    if layout then
        report.layout = layout
        report.counts.levels = layout.counts and layout.counts.levels or
            (layoutDetail and layoutDetail.count) or #layoutLevelList(layout)
    end

    local mapOk, mapReason, mapDetail = M.validateDungeonMaps(draft.maps or draft.levelMaps or draft.dungeonMaps,
        opts.mapOptions)
    addDraftStep(report, "create_maps", mapOk, mapReason, mapDetail)
    if mapDetail then
        report.counts.maps = mapDetail.count
    end

    local roomOptions = copy(opts.roomOptions or opts.roomDescriptionOptions or {})
    if roomOptions.inferFromFeatures == nil then
        roomOptions.inferFromFeatures = true
    end
    local roomOk, roomReason, roomDetail = M.validateRoomDescriptions(
        draft.rooms or draft.roomDescriptions or draft.levelRooms,
        roomOptions)

    local featureOptions = copy(opts.featureOptions or opts.roomFeatureOptions or {})
    if featureOptions.strictPrompt == nil then
        featureOptions.strictPrompt = opts.strictPrompt ~= false
    end
    local featureOk, featureReason, featureDetail = M.validateRoomFeatureAuthoringBatch(draftFeatureRooms(draft),
        featureOptions)

    local factionInput = draftFactionInput(draft)
    local factionOk = true
    local factionReason = nil
    local factionDetail = nil
    local factionOptions = copy(opts.factionOptions or opts.levelFactionOptions or {})
    if factionInput ~= nil or factionOptions.requireFactions == true then
        factionOk, factionReason, factionDetail = M.validateLevelFactions(factionInput or {}, factionOptions)
    end

    local descriptionsOk = roomOk and featureOk and factionOk
    addDraftStep(report, "write_room_descriptions", descriptionsOk,
        descriptionsOk and "room_authoring_valid" or "Room authoring incomplete", {
            descriptions = roomDetail,
            descriptionReason = roomOk and nil or roomReason,
            featureAuthoring = featureDetail,
            featureReason = featureOk and nil or featureReason,
            factions = factionDetail,
            factionReason = factionOk and nil or factionReason,
        })
    if roomDetail then
        report.counts.rooms = roomDetail.count
    end
    if factionDetail then
        report.counts.factions = factionDetail.count
    end

    local meatgrinderOk, meatgrinderReason, meatgrinderDetail = M.validateMeatgrinderTables(
        draft.meatgrinders or draft.meatgrinderTables or draft.meatgrinder or draft.meatgrinderTable,
        opts.meatgrinderOptions)
    addDraftStep(report, "create_meatgrinder", meatgrinderOk, meatgrinderReason, meatgrinderDetail)
    if meatgrinderDetail then
        report.counts.meatgrinders = meatgrinderDetail.count
    end

    report.readyForAuthoringUI = report.stepsByKey.origins.complete and
        report.stepsByKey.generate_layout.complete
    report.readyForPlay = #report.blockers == 0
    if report.readyForPlay then
        report.result = "underworld_draft_valid"
        return true, "underworld_draft_valid", report
    end
    return false, "Underworld draft incomplete", report
end

function M.createAuthoringChecklist(draft, opts)
    local ok, reason, report = M.validateUnderworldDraft(draft, opts)
    report.valid = ok
    report.reason = reason
    return report, ok and "underworld_authoring_checklist_ready" or "underworld_authoring_checklist_incomplete"
end

function M.findConnection(layout, aRef, bRef)
    if type(layout) ~= "table" then
        return nil
    end

    local a = tonumber(aRef)
    local b = tonumber(bRef)
    for _, connection in ipairs(layout.connections or {}) do
        if (connection.from == aRef or connection.fromValue == a) and
            (connection.to == bRef or connection.toValue == b) then
            return connection
        end
        if (connection.from == bRef or connection.fromValue == b) and
            (connection.to == aRef or connection.toValue == a) then
            return connection
        end
    end
    return nil
end

return M
