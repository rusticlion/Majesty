-- tomb_of_golden_ghosts.lua
-- The Tomb of Golden Ghosts - Example dungeon from HMtW Appendix E
-- Ticket T2_7: Vertical slice micro-dungeon
--
-- A tomb haunted by golden ghosts and infested by brain spiders.
-- Features secret doors hidden in murals, traps, and interesting NPCs.

local M = {}

M.data = {
    name = "The Tomb of Golden Ghosts",

    environment = {
        defaultCorridors = {
            dark = true,
            material = "natural_limestone_caverns",
            unlessOtherwiseNoted = true,
        },
        sensory = {
            riverChurningToNorth = true,
            smellsOfDampEarth = true,
        },
    },

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
                    description = "A ruined door, twisted off its hinges, lies on the ground.",
                    twistedOffHinges = true,
                },
                {
                    id = "west_mural",
                    name = "faded mural",
                    type = "decoration",
                    description = "A mural depicts a sorcerer observing the night sky via a reflecting pool.",
                    hidden_description = "One star in the mural seems slightly raised from the wall...",
                    secrets = "Pressing the raised star reveals a hidden latch! A secret door swings open.",
                    investigate_test = { attribute = "pentacles", difficulty = 12 },
                    reflectingPool = true,
                    reveal_connection = { to = "112_hidden_sanctum" },
                    spidersUnaware = true,
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
                    description = "Ancient, moldering scrolls sag across the shelves. Many crack at a touch.",
                    hidden_description = "Careful handling preserves a few royal records about taxes and gifts collected by the sealed family.",
                    secrets = "Antiquarians in the City prize intact scrolls at 10-100g each, but they require special care to transport.",
                    investigate_test = { attribute = "cups", difficulty = 10 },
                    fragileScrolls = {
                        requiresCarefulOpening = true,
                        requiresRightEnvironment = true,
                        mishandledOutcome = "crack_and_fall_to_dust",
                        antiquarianValueRange = { min = 10, max = 100, currency = "gold", per = "scroll" },
                        specialCareToTransport = true,
                        carefulReadSubject = "royal family taxes and gifts collected in the tomb",
                    },
                    loot = { "fragile_royal_scroll" },
                },
                {
                    id = "sealed_scroll_case",
                    name = "sealed scroll case",
                    type = "curiosity",
                    description = "One scroll case remains in surprisingly good condition.",
                    hidden_description = "Its ancient Vetus inscription reads: Do not open unless special occasion.",
                    secrets = "If opened, the scroll chronicles everything that happens to the opener minute by minute.",
                    investigate_test = { attribute = "cups", difficulty = 12 },
                    vetusInscription = "Do not open unless special occasion",
                    chronicle = {
                        openerOnly = true,
                        minuteByMinute = true,
                        becomesInfinitelyLong = true,
                        growsUntilDestroyed = true,
                    },
                    loot = { "sealed_vetus_chronicle_scroll" },
                },
                {
                    id = "moldy_smell",
                    name = "moldy smell",
                    type = "atmosphere",
                    description = "A moldy smell fills the small room.",
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
                    investigate_test = { attribute = "pentacles", difficulty = 14 },
                    centipedesEmergeOnEntry = true,
                },
                {
                    id = "dire_centipedes",
                    name = "dire centipedes",
                    type = "creature",
                    description = "Three dire centipedes emerge from the churned ground when the guild enters.",
                    encounter = {
                        blueprint_id = "giant_centipede",
                        count = 3,
                        emergesOnEnter = true,
                        blocksPassage = true,
                        pursuesOnlyIfAntagonized = true,
                    },
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
                    secrets = "The corpse belongs to an unlucky adventurer, mostly devoured by dire centipedes.",
                    investigate_test = { attribute = "cups", difficulty = 8 },
                },
                {
                    id = "torn_pack",
                    name = "torn pack",
                    type = "container",
                    description = "A leather backpack, torn open. Contents scattered.",
                    secrets = "The only intact thing of value is the Alchemical Treatise of Francis Stewbrew, a book partially detailing the alchemical reagents of this level.",
                    investigate_test = { attribute = "pentacles", difficulty = 6 },
                    loot = { "alchemical_treatise_francis_stewbrew" },
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
                    description = "Silvery webs cover a thirty-foot stretch of hallway at the eastern end.",
                    hidden_description = "The webs are solid for tangible and intangible creatures alike.",
                    investigate_test = { attribute = "wands", difficulty = 10 },
                    stretchFeet = 30,
                    brainSpiderWebs = {
                        solidToTangible = true,
                        solidToIntangible = true,
                        blocksGhosts = true,
                        destroyFreesGhosts = true,
                        containedRooms = { "106_burial_chambers", "107_looted_tomb", "108_tripartite_statue" },
                        escapedGhostPossibleViaMeatgrinder = true,
                        alternateEscapeThrough = "116_glaura_nest",
                    },
                },
            },
        },
        {
            id          = "106_burial_chambers",
            name        = "Burial Chambers",
            description = "The hallway bends around into a semi-circular shape. There is a mural on the northeastern wall of an astronomer pointing in alarm towards a comet.",
            danger_level = 2,
            goldenGhostActivity = {
                sourceRoom = "107_looted_tomb",
                freeToMoveThroughRooms = { "106_burial_chambers", "107_looted_tomb", "108_tripartite_statue" },
                hinderExplorersTheyHear = true,
            },
            features = {
                {
                    id = "astronomer_mural",
                    name = "astronomer mural",
                    type = "decoration",
                    description = "A robed astronomer points in alarm toward a comet.",
                    hidden_description = "The mural's edge outlines a secret door, but no latch or purchase exists on this side.",
                    secrets = "There is a secret door in the mural that leads to room 116, but it cannot be opened from this room.",
                    investigate_test = { attribute = "cups", difficulty = 12 },
                    reveal_connection = { to = "116_glaura_nest" },
                    cannotOpenFromThisSide = true,
                    opensFromOtherSide = "116_glaura_nest",
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
                    hidden_description = "They are mute and desperately trying to communicate by gesture.",
                    secrets = "The ghosts demand the return of seven golden death masks: six from room 111 and one from Kodi's nest in room 117.",
                    investigate_test = { attribute = "cups", difficulty = 8 },
                    haunting = {
                        count = 7,
                        mute = true,
                        communicatesByCharades = true,
                        demands = {
                            itemProperty = "deathMask",
                            total = 7,
                            locations = {
                                { roomId = "111_spiders_treasure", count = 6 },
                                { roomId = "117_kodi_nest", count = 1 },
                            },
                        },
                        appeasedOutcome = "return_to_sleep_of_death",
                        freedUnappeasedOutcome = "natural_disaster",
                        hinderRooms = { "106_burial_chambers", "107_looted_tomb", "108_tripartite_statue" },
                    },
                },
                {
                    id = "sarcophagi",
                    name = "stone sarcophagi",
                    type = "container",
                    description = "Seven stone coffins, all opened and emptied long ago. The lids lie shattered on the floor.",
                    hidden_description = "There are no bodies and no grave goods left inside.",
                    secrets = "The sarcophagi are empty.",
                },
            },
        },
        {
            id          = "108_tripartite_statue",
            name        = "Tripartite Statue",
            description = "A three-sided, gold-plated stone statue stands in a niche: one side depicts a maiden, one a pregnant woman, and one a crone. A desiccated corpse lies at the statue's feet. The three heads share a single silver crown.",
            danger_level = 4,
            features = {
                {
                    id = "tripartite_statue",
                    name = "tripartite statue",
                    type = "statue",
                    description = "A gold-plated three-sided statue depicts a maiden, a pregnant woman, and a crone sharing one silver crown decorated with thorn-covered antlers.",
                    hidden_description = "Each face has two eyes that align toward the room if the crown is disturbed.",
                    ghostInterference = {
                        activeUntilDeathMasksReturned = true,
                        deathMasksRequired = 7,
                    },
                    crown = {
                        loot = "silver_crown",
                        safeRemovalRequires = "astrological_pedestal_solved",
                    },
                    trap = {
                        trigger = "remove_crown_before_puzzle_solved",
                        sixEyeAgingBeams = true,
                        agingYears = 1000,
                        instantDeathForNonFay = true,
                        immuneKin = { "fay" },
                        defenseTest = {
                            attribute = "pentacles",
                            objective = "dive_out_of_sight",
                        },
                        dwimmercraftStillTriggers = true,
                    },
                },
                {
                    id = "desiccated_corpse",
                    name = "desiccated corpse",
                    type = "corpse",
                    description = "A bog-mummy-like corpse lies at the statue's feet, but its clothes and gear are modern.",
                    hidden_description = "The corpse belongs to an unlucky adventurer aged a thousand years by the statue trap.",
                    agedYears = 1000,
                    modernGear = true,
                },
                {
                    id = "astrological_pedestal",
                    name = "astrological pedestal",
                    type = "puzzle",
                    description = "A pedestal partially hidden by the corpse bears sun, moon, and star symbols set on rotating tracks.",
                    hidden_description = "The symbols can be lined up with the three statue faces.",
                    puzzle = {
                        symbols = { "sun", "moon", "star" },
                        solution = {
                            maiden = "sun",
                            mother = "moon",
                            crone = "star",
                        },
                        success = {
                            disarmsTrap = "tripartite_statue",
                            safeCrownRemoval = true,
                        },
                    },
                },
            },
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
            features = {
                {
                    id = "puppet_mummies",
                    name = "puppet-mummies",
                    type = "creature",
                    description = "Puppet-mummies jerkily attack as the guild enters, yanked into motion by unseen web rigging.",
                    encounter = {
                        blueprint_id = "puppet_mummy",
                        count = "adventurers",
                        emergesOnEnter = true,
                        cannotLeaveRoom = true,
                        controlledBy = "kodi_dove_devourer",
                    },
                },
                {
                    id = "kodi_illusory_wall",
                    name = "illusory wall",
                    type = "hidden_creature",
                    state = "hidden",
                    description = "A blank stretch of wall behind the puppet-mummies.",
                    hidden_description = "Kodi Dove-devourer controls the puppet-mummies from behind an illusory wall.",
                    reveal = {
                        secondSight = true,
                        missileAttacksFromOutsideRoom = true,
                    },
                    encounter = {
                        blueprint_id = "brain_spider_kodi",
                        count = 1,
                        hiddenByIllusion = true,
                        escapesWhenRevealedByMissileFire = true,
                    },
                },
                {
                    id = "big_cheese",
                    name = "Big Cheese",
                    type = "creature",
                    description = "A dire catfish named Big Cheese lurks in the underground river.",
                    nonHostile = true,
                    riverDenizen = true,
                    behavior = {
                        spitsBackThrownObjects = true,
                        thrownObjectDestination = "riverbank",
                    },
                },
            },
        },
        -- S10.4: Group Test trap (testing resolver.lua group logic)
        {
            id          = "110_trapped_hallway",
            name        = "Trapped Hallway",
            description = "A curving hallway with three short flights of stairs toward the treasure-room door. A large boulder tied to the ceiling with silvery webs blocks the door, and several thin silvery webs criss-cross the path.",
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
                        damage = 1,
                        woundType = "critical",
                        effects = { "critical" },
                        description = "The boulder tumbles down the stairs, bursts into room 109, and slams into the wall.",
                        isGroupTest = true,  -- Requires group test to avoid
                        attribute = "pentacles",
                        difficulty = 12,
                        failureText = "The boulder rolls through the corridor! Those who fail their test suffer a Critical wound.",
                        successText = "The guild scatters, each member timing their movement perfectly. The boulder crashes harmlessly past.",
                        rankModifiers = {
                            firstRank = "disfavor",
                            firstRankReason = "closest_to_boulder",
                            lastRank = "favor",
                            lastRankReason = "farthest_from_boulder",
                        },
                        trigger = {
                            tripwiresBroken = true,
                            burstsInto = "109_guard_room",
                            clearsBlockedConnection = "111_spiders_treasure",
                        },
                    },
                    investigate_test = { attribute = "pentacles", difficulty = 10 },
                },
                {
                    id = "hanging_boulder",
                    name = "suspended boulder",
                    type = "hazard",
                    description = "A massive stone sphere hangs from silvery webs attached to the ceiling, blocking the door to the treasure room.",
                    hidden_description = "The webs connecting it to the trip-wires below are extremely taut.",
                    blocksConnection = {
                        to = "111_spiders_treasure",
                        untilTriggered = "web_trigger",
                        alternateRoute = "112_hidden_sanctum",
                    },
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
                    description = "A heavy iron-bound chest with a spider-marked lock.",
                    hidden_description = "The lock matches the key hidden in Kodi's nest. A careful hand could also try to pick it.",
                    secrets = "Inside: 1260 gold, six golden death masks, and twenty jeweled scarabs.",
                    locked = true,
                    key_item_id = "111_spiders_treasure_chest",
                    lock = { difficulty = 12, key_id = "111_spiders_treasure_chest" },
                    investigate_test = {
                        attribute = "pentacles",
                        difficulty = 12,
                        success_state = "unlocked",
                    },
                    loot = { "gold_coins_1260", "golden_death_masks_6", "jeweled_scarabs_20" },
                    goldenGhosts = {
                        deathMasksHere = 6,
                        deathMasksRequired = 7,
                        scarabsAcknowledgedButGifted = true,
                    },
                },
                {
                    id = "weeping_mural",
                    name = "weeping woman mural",
                    type = "decoration",
                    description = "A woman with a moon-like halo weeps silver tears. Her hands reach toward something unseen.",
                    hidden_description = "The tears are actual silver inlay. The hands point toward the western wall.",
                    secrets = "Pressing where her hands point reveals a hidden door!",
                    investigate_test = { attribute = "cups", difficulty = 14 },
                    reveal_connection = { to = "112_hidden_sanctum" },
                    spidersUnaware = true,
                },
            },
        },
        {
            id          = "112_hidden_sanctum",
            name        = "The Hidden Sanctum",
            description = "This room is dusty and undisturbed. A thin trickle of water dribbles from the ceiling into a puddle. Moss covers the west wall where a large pale snail grazes.",
            danger_level = 1,
            safe = true,
            safeBecauseSecret = true,
            features = {
                {
                    id = "north_mural",
                    name = "north wall mural",
                    type = "decoration",
                    description = "A naked green-skinned man reaches up to snatch one of two flying silvery women from the sky.",
                    hidden_description = "The edge of the painted sky hides a latch.",
                    secrets = "The mural hides a secret door that connects to the weeping mural in room 111.",
                    investigate_test = { attribute = "cups", difficulty = 14 },
                    reveal_connection = { to = "111_spiders_treasure" },
                },
                {
                    id = "pale_snail",
                    name = "large pale snail",
                    type = "creature",
                    nonHostile = true,
                    description = "A large pale snail grazes slowly across the mossy west wall.",
                    hidden_description = "The snail brightens in color while eating the moss.",
                    observations = {
                        brightensWhileEatingMoss = true,
                    },
                },
                {
                    id = "healing_moss",
                    name = "west wall moss",
                    type = "vegetation",
                    description = "Moss covers the west wall where the pale snail grazes.",
                    hidden_description = "The moss smells fresh and sharp, almost like green onions.",
                    secrets = "There is only enough moss for one meal. It counts as a ration that grants the Heal effect.",
                    singleMeal = true,
                    loot = { "healing_moss_ration" },
                },
                {
                    id = "east_mural",
                    name = "east wall mural",
                    type = "decoration",
                    description = "A stern-looking woman crowned with a corona castigates a green-skinned man with a rod.",
                    hidden_description = "The rod is painted over the outline of a hidden latch.",
                    secrets = "The mural hides a secret door that connects to the mural in room 101.",
                    investigate_test = { attribute = "cups", difficulty = 14 },
                    reveal_connection = { to = "101_entrance" },
                },
            },
        },
        {
            id          = "113_pit_of_bones",
            name        = "The Pit of Bones",
            description = "A sprawling, shadowy natural cavern. Uneven flooring, dripping with stalactites, covered in puddles. A narrow crevasse 50' deep runs like a wound through this cavern. A foul stench emanates from the pit.",
            danger_level = 3,
            features = {
                {
                    id = "bone_pit",
                    name = "50-foot bone crevasse",
                    type = "hazard",
                    description = "A narrow crevasse drops fifty feet into darkness. Bones, garbage, and slime-slick puddles line its edges.",
                    hidden_description = "The stench rises from discarded garbage in the pit rather than ordinary rot.",
                    investigate_test = { attribute = "pentacles", difficulty = 12 },
                    depthFeet = 50,
                    fallHazard = true,
                    investigateTriggersEncounter = true,
                    triggeredEncounterFeatureId = "pit_slime",
                },
                {
                    id = "discarded_garbage",
                    name = "discarded garbage",
                    type = "debris",
                    description = "Old refuse and gnawed remains have been dumped into the crevasse.",
                    feedsPitSlime = true,
                },
                {
                    id = "pit_slime",
                    name = "pit slime",
                    type = "encounter",
                    hidden = true,
                    description = "A slime lives in the pit, feeding on the discarded garbage below.",
                    encounter = {
                        blueprint_id = "slime",
                        count = 1,
                        livesInPit = true,
                        feedsOnDiscardedGarbage = true,
                        attacksOnInvestigate = true,
                        attacksAfterTarryWatches = 1,
                    },
                },
            },
        },
        {
            id          = "114_laboratory",
            name        = "Magical Laboratory",
            description = "The brain spider's laboratory - a writing desk, shelves of reagents, ingredients, and arcane tools. In the corner, a large glass tank holds a giant sleeping baby that sheds steady silvery light.",
            danger_level = 4,
            brainSpiderMeatgrinderResponse = {
                triggersWhenEncounteredHereByMeatgrinder = true,
                appliesTo = { "brain_spider_kodi", "brain_spider_queen" },
                behavior = "fight_to_the_death_to_protect_star_child",
                protectsFeatureId = "star_child_tank",
            },
            features = {
                {
                    id = "star_child_tank",
                    name = "sleeping star-child",
                    type = "cosmic_entity",
                    description = "A giant inhuman baby floats asleep inside a glass tank, shedding steady silvery light.",
                    environmentalLight = true,
                    starChild = {
                        hibernating = true,
                        immortal = true,
                        meaningfulHarmUnlikely = true,
                        communicationUnlikely = true,
                    },
                    wakeEffect = {
                        trigger = "attempt_to_wake",
                        description = "The star-child opens one eye, forms a mudra, sings an OHM, and returns to sleep.",
                        type = "random_maleficence",
                        environmentalOnly = true,
                        redrawPlayerTargetingEffects = true,
                        returnsToSleep = true,
                    },
                },
                {
                    id = "laboratory_spell_components",
                    name = "spell components",
                    type = "container",
                    description = "Shelves of reagents, ingredients, and arcane tools line the laboratory.",
                    loot = {
                        "component_portable_hole",
                        "component_woodweave",
                        "component_sleep",
                    },
                },
            },
        },
        {
            id          = "115_book_worm",
            name        = "The Book Worm's Closet",
            description = "A small closet. A dire centipede who calls herself 'Book Worm' lives here. She speaks only Vetus.",
            danger_level = 1,
            features = {
                {
                    id = "book_worm",
                    name = "Book Worm",
                    type = "creature",
                    description = "A sentient dire centipede who ate so many scrolls from the Scriptorium that she learned to talk.",
                    encounter = {
                        blueprint_id = "dire_centipede_book_worm",
                        count = 1,
                    },
                    social = {
                        disposition = "amiable",
                        languages = {
                            vetus = true,
                            only = "vetus",
                        },
                    },
                    rumors = {
                        {
                            id = "glaura_star_child_egg",
                            truth = "partial",
                            summary = "Glaura Glossolalia has some magic god child egg that she is trying to hatch through magic. She thinks this will make her immortal.",
                        },
                        {
                            id = "statue_eye_beams",
                            truth = "true",
                            summary = "The statue in room 108 killed an adventurer with eye beams.",
                        },
                    },
                    giftRumor = {
                        requires = {
                            itemType = "book",
                            properties = { book = true },
                        },
                        id = "hidden_mural_doors",
                        truth = "true",
                        summary = "There are hidden doors in the murals.",
                    },
                },
            },
        },
        -- S10.4: Boss room with Greater Doom enemy
        {
            id          = "116_glaura_nest",
            name        = "Glaura's Nest",
            description = "A spacious room covered in webs. A clutch of eggs the size of basketballs is plastered to the cavern walls by sticky, white webs. The southern wall has a dilapidated mural, its contents too damaged to discern.",
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
                    description = "Glaura Glossolalia is a sorcerously inclined brain spider in her private quarters.",
                    hidden_description = "She is obsessed with the star-child and believes she can put it into one of her eggs to ascend into godhood.",
                    -- Boss encounter data
                    encounter = {
                        blueprint_id = "brain_spider_queen",
                        count = 1,
                        unlessAlreadyEncountered = true,
                        conditionalAllies = {
                            {
                                blueprint_id = "brain_spider_kodi",
                                count = 1,
                                condition = "minor_arcana_discard_face_card",
                                response = "rushes_to_glaura_aid_on_commotion",
                                rushesIfNotCurrentlyInRoom = true,
                                trigger = "sound_of_commotion",
                            },
                        },
                    },
                },
                {
                    id = "spider_eggs",
                    name = "spider eggs",
                    type = "feature",
                    description = "A clutch of eggs the size of basketballs is plastered to the cavern walls by sticky, white webs.",
                    eggClutch = {
                        basketballSized = true,
                        plasteredToCavernWalls = true,
                        stickyWhiteWebs = true,
                        tiedToGlauraStarChildPlan = true,
                    },
                },
                {
                    id = "dilapidated_mural",
                    name = "dilapidated mural",
                    type = "decoration",
                    description = "The contents of this southern-wall mural are too damaged to discern.",
                    hidden_description = "A hidden latch survives beneath the flaking paint.",
                    secrets = "The mural hides a hidden latch that opens a secret door to room 106.",
                    investigate_test = { attribute = "cups", difficulty = 14 },
                    contentsTooDamagedToDiscern = true,
                    reveal_connection = { to = "106_burial_chambers" },
                    spidersUnaware = true,
                },
            },
        },
        {
            id          = "117_kodi_nest",
            name        = "Kodi's Nest",
            description = "A spacious room covered in webs. A few fat sacks of webs hang from the ceiling here.",
            danger_level = 4,
            features = {
                {
                    id = "kodi_dove_devourer",
                    name = "Kodi Dove-devourer",
                    type = "creature",
                    description = "A particularly large brain spider guards the web sacks as if everything caught in them belongs to him.",
                    encounter = {
                        blueprint_id = "brain_spider_kodi",
                        count = 1,
                        unlessAlreadyEncountered = true,
                        conditionalAllies = {
                            {
                                blueprint_id = "brain_spider_queen",
                                count = 1,
                                condition = "minor_arcana_discard_face_card",
                                response = "rushes_to_kodi_aid_on_commotion",
                                rushesIfNotCurrentlyInRoom = true,
                                trigger = "sound_of_commotion",
                            },
                        },
                    },
                },
                {
                    id = "web_sacks",
                    name = "fat web sacks",
                    type = "container",
                    description = "A few fat sacks of webs hang from the ceiling.",
                    secrets = "The sacks contain 54 gold, a key to the chest in room 111, lamp oil, fine brandy, a golden death mask, and an orcish golden goat idol.",
                    loot = {
                        "gold_coins_54",
                        "chest_111_key",
                        "lamp_oil",
                        "fine_brandy",
                        "golden_death_mask",
                        "orcish_golden_goat_idol",
                    },
                },
            },
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
                        disposition = "trust",
                        severity = 2,
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
            blocked_by = "silvery_webs",
            blocks_ghosts = true,
            blocks_intangible = true,
            destroying_webs_frees_ghosts = true,
            description = "Silvery webs block the passage. Brain spider webs keep ghosts contained.",
        }},

        -- Burial chambers loop
        { from = "106_burial_chambers", to = "107_looted_tomb", properties = { direction = "east" } },
        { from = "107_looted_tomb", to = "108_tripartite_statue", properties = { direction = "south" } },
        { from = "116_glaura_nest", to = "106_burial_chambers", properties = {
            direction = "north",
            is_secret = true,
            is_one_way = true,  -- Can only be opened from 116 side
            opens_from = "116_glaura_nest",
            revealed_by = "dilapidated_mural",
            spiders_unaware = true,
            description = "A secret door in Glaura's southern mural opens toward room 106. It cannot be opened from the room 106 side.",
        }},

        -- Spider territory
        { from = "113_pit_of_bones", to = "114_laboratory", properties = {
            direction = "east",
            description = "A passage leads east to the brain spider laboratory.",
        }},
        { from = "114_laboratory", to = "109_guard_room", properties = { direction = "east" } },
        { from = "109_guard_room", to = "110_trapped_hallway", properties = { direction = "south" } },
        { from = "110_trapped_hallway", to = "111_spiders_treasure", properties = {
            direction = "south",
            is_blocked = true,
            blocked_by = "hanging_boulder",
            cleared_by = "web_trigger",
            alternate_route = "112_hidden_sanctum",
            description = "A boulder tied to the ceiling with webs blocks the door until the trap is triggered or the guild bypasses it through room 112.",
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
        [1] = { description = "Faint shreds of cobwebs hang from the ceiling here, blowing gently." },
        [2] = { description = "The guild glimpses something golden disappearing around a corner." },
        [3] = {
            description = "The ground here is strewn with gross black fewmets.",
            loreReveal = "centipede_scat",
        },
        [4] = { description = "The distant rumbling of an earthquake shakes for a few moments, then stands still." },
        [5] = { description = "A cold wind blows down the corridor, reminiscent of the exhalation of the unquiet dead." },
    },

    -- Travel events (XI-XV)
    travel_event = {
        [1] = {
            description = "Quicksand. Giant centipedes have churned the soft ground in this area.",
            effect = "quicksand",
            target = "first_human_orc_troll_stature_adventurer",
            rescueRequired = true,
            rescuedVictimBecomesStressed = true,
        },
        [2] = {
            description = "Illusory walls cover all doors and exits to this room, except the one the guild just came through.",
            effect = "illusory_exits",
            excludesEntryExit = true,
        },
        [3] = {
            description = "Room choked with webs. It is impossible to explore unless care is taken to systematically clear the webbing.",
            effect = "web_choked_room",
            torchesMayClear = true,
            torchFlickersConsumed = 3,
        },
        [4] = {
            description = "Trap webs. If not moving carefully, first in marching order tests Cups to notice the snare.",
            effect = "trap_webs",
            attribute = "cups",
            target = "first_in_marching_order",
            failure = "pulled_feet_first_20_feet_into_air",
            heightFeet = 20,
        },
        [5] = {
            description = "A distant earthquake - the cavern begins crashing down around the guild.",
            effect = "earthquake_damage_test",
            attribute = "pentacles",
            target = "each_player",
            failure = "wound_from_falling_rock_or_twisted_ankle",
        },
    },

    -- Random encounters (XVI-XX)
    random_encounter = {
        [1] = {
            blueprint_id = "puppet_mummy",
            count = "adventurers",
            controller_blueprint_id = "brain_spider_kodi",
            controllerHiddenByIllusion = true,
            revealedBySecondSight = true,
            description = "Puppet-mummies controlled by Kodi Dove-devourer from behind an illusory wall jerkily attack!",
        },
        [2] = {
            blueprint_id = "brain_spider_queen",
            count = 1,
            description = "Glaura Glossolalia is weaving webs throughout this room. She hisses a telepathic warning to leave this place, then uses Wall Crawling to quickly escape.",
            weavingWebs = true,
            telepathicWarning = true,
            usesWallCrawlingToEscape = true,
        },
        [3] = {
            description = "A weeping golden ghost appears. It cannot speak, but engages in charades to articulate its grievances.",
            npc = "golden_ghost",
            mute = true,
            communicatesByCharades = true,
        },
        [4] = {
            description = "Rival adventurers Finch and Justin Pepperoni are being chased by giant centipedes.",
            npc = "rivals",
            rivals = {
                { name = "Finch", kin = "wood_elf", role = "naturalist" },
                { name = "Justin Pepperoni", kin = "halfling", role = "cook" },
            },
            chasedBy = {
                blueprint_id = "giant_centipede",
                count = "discard",
            },
            roughShape = true,
            rescueRewards = { "signet_ring_20", "slime_bomb" },
            slimeBombInHermeticBottle = true,
        },
        [5] = {
            blueprint_id = "giant_centipede",
            count = "adventurers-1",
            description = "The guild encounters [adventurers - 1] giant centipedes in this room. They will not let anybody enter without a fight, but will not pursue the fleeing guild.",
            blocksEntry = true,
            willNotPursueFleeingGuild = true,
        },
    },

    -- Quest rumor (XXI)
    quest_rumor = {
        description = "Provide a clue for the next step of the guild's quest, delivered in context of the dungeon.",
    },
}

return M
