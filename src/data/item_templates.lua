-- item_templates.lua
-- Item Templates for Majesty
-- Ticket S11.3: Data-driven item definitions for looting
--
-- Templates define default properties for items.
-- inventory.createItemFromTemplate(templateId) instantiates these.

local M = {}

--------------------------------------------------------------------------------
-- ITEM TEMPLATES
-- Each template defines: name, size, durability, properties, etc.
--------------------------------------------------------------------------------

M.templates = {

    ----------------------------------------------------------------------------
    -- WEAPONS
    ----------------------------------------------------------------------------

    rusty_sword = {
        name = "Rusty Sword",
        size = 1,
        durability = 2,
        weaponType = "sword",
    },

    dagger = {
        name = "Dagger",
        size = 1,
        durability = 2,
        weaponType = "dagger",
    },

    longsword = {
        name = "Longsword",
        size = 1,
        durability = 3,
        weaponType = "sword",
    },

    bow = {
        name = "Bow",
        size = 2,
        durability = 2,
        weaponType = "bow",
    },

    crossbow = {
        name = "Crossbow",
        size = 2,
        durability = 3,
        weaponType = "crossbow",
        isLoaded = true,
    },

    silver_longsword = {
        name = "Silver Longsword",
        size = 1,
        durability = 3,
        weaponType = "sword",
        properties = {
            silver = true,
        },
    },

    ----------------------------------------------------------------------------
    -- ARMOR AND SHIELDS
    ----------------------------------------------------------------------------

    light_armor = {
        name = "Light Armor",
        size = 1,
        durability = 1,
        isArmor = true,
        properties = { armor = true, armorType = "light", notchCapacity = 1 },
    },

    iron_armor = {
        name = "Iron Armor",
        size = 2,
        durability = 2,
        isArmor = true,
        properties = {
            armor = true,
            armorType = "iron",
            notchCapacity = 2,
            iron = true,
            blocksTargetedSpells = true,
        },
    },

    steel_armor = {
        name = "Steel Armor",
        size = 3,
        durability = 3,
        isArmor = true,
        properties = {
            armor = true,
            armorType = "steel",
            notchCapacity = 3,
            latentIron = true,
            blocksCasting = true,
        },
    },

    helm = {
        name = "Helm",
        size = 1,
        durability = 2,
        isArmor = true,
        properties = { armor = true, armorType = "helm" },
    },

    shield_light = {
        name = "Light Shield",
        size = 1,
        durability = 1,
        properties = { shield = true, tags = { "shield" } },
    },

    shield_heavy = {
        name = "Heavy Shield",
        size = 1,
        durability = 2,
        properties = { shield = true, heavy = true, tags = { "shield" } },
    },

    ----------------------------------------------------------------------------
    -- LIGHT SOURCES
    ----------------------------------------------------------------------------

    torch = {
        name = "Torch",
        size = 1,
        durability = 1,
        properties = {
            flicker_count = 3,
            light_source = true,
            isLit = true,                -- Starts lit by default
            requires_hands = true,       -- Must be in hands to provide light
            provides_belt_light = false, -- Does NOT work from belt
            provides_dim_light = true,
            fragile_on_belt = false,
        },
    },

    lantern = {
        name = "Lantern",
        size = 1,
        durability = 2,
        properties = {
            flicker_count = 4,
            light_source = true,
            isLit = true,                -- Starts lit by default
            requires_hands = false,      -- Works from hands OR belt
            provides_belt_light = true,  -- Works from belt
            provides_dim_light = true,
            fragile_on_belt = true,      -- Breaks when taking wound while on belt
        },
    },

    candles = {
        name = "Candles",
        size = 1,
        stackable = true,
        stackSize = 6,
        quantity = 3,
        properties = {
            flicker_count = 2,
            light_source = true,
            candle = true,
            isLit = false,
            requires_hands = true,
            provides_belt_light = false,
            provides_dim_light = false,
        },
    },

    ----------------------------------------------------------------------------
    -- CONSUMABLES
    ----------------------------------------------------------------------------

    ration = {
        name = "Ration",
        size = 1,
        stackable = true,
        stackSize = 6,
        quantity = 1,
        isRation = true,
    },

    rations_3 = {
        name = "Ration",
        size = 1,
        stackable = true,
        stackSize = 6,
        quantity = 3,
        isRation = true,
    },

    animal_feed = {
        name = "Animal Feed",
        size = 1,
        stackable = true,
        stackSize = 6,
        quantity = 1,
        type = "animal_feed",
        properties = {
            isAnimalFeed = true,
            feedFor = "any",
        },
    },

    disgusting_ration = {
        name = "Disgusting Ration",
        size = 1,
        stackable = true,
        stackSize = 6,
        quantity = 1,
        type = "ration",
        isRation = true,
        properties = {
            disgusting = true,
            isAnimalFeed = true,
            feedFor = "any",
        },
    },

    lard = {
        name = "Lard",
        size = 1,
        durability = 1,
        properties = { food = true, grease = true },
    },

    leeches = {
        name = "Leeches, Jar Of",
        size = 1,
        durability = 1,
        properties = {
            consumable = true,
            consumeOnAttempt = true,
            medical = true,
            leeches = true,
            afflictionCureCharges = 2,
        },
    },

    fresh_game = {
        name = "Fresh Game",
        size = 1,
        properties = {
            freshGame = true,
            perishable = true,
            meals = 1,
            requiresCookingGear = true,
            preservableWithSalt = true,
        },
    },

    fresh_game_feast = {
        name = "Large Fresh Game",
        size = 2,
        properties = {
            freshGame = true,
            perishable = true,
            meals = "guild",
            requiresCookingGear = true,
            preservableWithSalt = true,
            greatSuccess = true,
        },
    },

    cooked_game_meal = {
        name = "Cooked Game Meal",
        size = 1,
        stackable = true,
        stackSize = 6,
        quantity = 1,
        properties = {
            isCampMeal = true,
            perishable = true,
        },
    },

    salt = {
        name = "Salt",
        size = 1,
        stackable = true,
        stackSize = 6,
        quantity = 1,
        properties = {
            consumable = true,
            consumeOnAttempt = true,
            offensive = true,
            effect = "salt_ooze",
            useEffect = {
                type = "salt_ooze",
                target = "target",
                attribute = "swords",
                affectedTags = { "ooze", "jelly", "slime" },
                damage = {
                    amount = 2,
                    effects = { "salt_reactive" },
                },
                successMessage = "The salt dries out the ooze.",
                noEffectMessage = "The salt has no special effect on this target.",
            },
        },
    },

    pipeweed = {
        name = "Pipe and Pipeweed",
        size = 1,
        durability = 1,
        properties = {
            consumable = true,
            recreational = true,
            effect = "clear_stress",
            useEffect = {
                type = "clear_conditions",
                target = "self",
                conditions = { "stressed" },
                successMessage = "Pipeweed smoked: Stressed cleared.",
                noEffectMessage = "The pipeweed is pleasant, but you were not Stressed.",
            },
        },
    },

    wolfsbane = {
        name = "Wolfsbane",
        size = 1,
        durability = 1,
        properties = { herb = true, ward = true },
    },

    booze_fancy = {
        name = "Booze, Fancy",
        size = 1,
        durability = 1,
        properties = { alcohol = true, gift = true, luxury = true },
    },

    bezoar = {
        name = "Bezoar",
        size = 1,
        durability = 1,
        properties = {
            consumable = true,
            medical = true,
            antiPoison = true,
            afflictionCureCharges = 8,
        },
    },

    firework_rocket = {
        name = "Firework Rocket",
        size = 1,
        stackable = true,
        stackSize = 6,
        quantity = 1,
        properties = {
            consumable = true,
            challengeItem = true,
            firework = true,
            misfireChancePercent = 25,
            possibleEffects = { "blinding_lights", "piercing_wounds" },
        },
    },

    fate_honey = {
        name = "Jar of Fate Honey",
        size = 1,
        properties = {
            consumable = true,
            crawlUse = true,
            restoresLoreBids = 1,
        },
    },

    newt_row_amulet = {
        name = "Newt Row Amulet",
        size = 1,
        properties = {
            consumable = true,
            consumeOnUse = true,
            removesDisfavor = true,
            grantsFavor = false,
        },
    },

    oil = {
        name = "Oil",
        size = 1,
        durability = 1,
        properties = {
            consumable = true,
            oil = true,
            fuel = true,
            effect = "refuel_lantern",
            useEffect = {
                type = "refuel_lantern",
                target = "target",
                flickers = 4,
                successMessage = "Lantern refilled with oil.",
                noEffectMessage = "Oil can only refill a lantern.",
            },
        },
    },

    healing_potion = {
        name = "Healing Potion",
        size = 1,
        durability = 1,
        properties = {
            potion = true,
            alchemical = true,
            consumable = true,
            effect = "heal_wound",
            useEffect = {
                type = "heal_wound",
                target = "self_or_target",
            },
        },
    },

    poultice = {
        name = "Poultice",
        size = 1,
        durability = 1,
        properties = {
            consumable = true,
            consumeOnAttempt = true,
            medical = true,
            effect = "poultice_deaths_door",
            useEffect = {
                type = "poultice_deaths_door",
                target = "self_or_target",
            },
        },
    },

    antidote = {
        name = "Antidote",
        size = 1,
        durability = 1,
        properties = {
            potion = true,
            alchemical = true,
            consumable = true,
            effect = "cure_poison",
            useEffect = {
                type = "clear_conditions",
                target = "self_or_target",
                conditions = { "poisoned", "poison" },
                successMessage = "Poison cured.",
            },
        },
    },

    brain_spider_potion = {
        name = "Brain Spider Potion",
        size = 1,
        durability = 1,
        properties = {
            potion = true,
            alchemical = true,
            consumable = true,
            source = "brain_spider",
            useEffect = {
                type = "apply_conditions",
                target = "self",
                duration = "watch",
                conditions = {
                    universal_speech = true,
                    psionic_voice = true,
                },
                successMessage = "Your speech carries meaning across language for a watch.",
            },
        },
    },

    brain_spider_bomb = {
        name = "Spider Sac Bomb",
        size = 1,
        durability = 1,
        properties = {
            bomb = true,
            alchemical = true,
            consumable = true,
            consumeOnAttempt = true,
            offensive = true,
            source = "brain_spider",
            useEffect = {
                type = "apply_conditions",
                target = "target",
                conditions = { rooted = true },
                successMessage = "Silver web explodes over the target, rooting them.",
            },
        },
    },

    brain_spider_oil = {
        name = "Brain Spider Glue Oil",
        size = 1,
        durability = 1,
        properties = {
            oil = true,
            alchemical = true,
            consumable = true,
            source = "brain_spider",
            useEffect = {
                type = "adhere",
                target = "target",
                duration = "watch",
                successMessage = "The oil bonds the touched objects together for a watch.",
            },
        },
    },

    devil_potion = {
        name = "Devil Potion",
        size = 1,
        durability = 1,
        properties = {
            potion = true,
            alchemical = true,
            consumable = true,
            source = "devil",
            useEffect = {
                type = "apply_conditions",
                target = "self",
                duration = "watch",
                conditions = {
                    fire_immunity = true,
                    heat_immunity = true,
                    gear_still_burns = true,
                },
                successMessage = "Fire cannot harm you for a watch, though your gear can still burn.",
            },
        },
    },

    devil_bomb = {
        name = "Devil Confession Bomb",
        size = 1,
        durability = 1,
        properties = {
            bomb = true,
            alchemical = true,
            consumable = true,
            consumeOnAttempt = true,
            offensive = true,
            source = "devil",
            useEffect = {
                type = "compel_confession",
                target = "target",
                successMessage = "The target is Controlled to confess their gravest sin.",
            },
        },
    },

    devil_oil = {
        name = "Devil Invisible Fire Oil",
        size = 1,
        durability = 1,
        properties = {
            oil = true,
            alchemical = true,
            consumable = true,
            source = "devil",
            useEffect = {
                type = "invisible_fire",
                target = "target",
                successMessage = "Invisible flame burns hot without shedding light.",
            },
        },
    },

    cockatrice_bomb = {
        name = "Cockatrice Stone-Smoke Bomb",
        size = 1,
        durability = 1,
        properties = {
            bomb = true,
            alchemical = true,
            consumable = true,
            consumeOnAttempt = true,
            offensive = true,
            source = "cockatrice",
            useEffect = {
                type = "cockatrice_stone_smoke",
                target = "target",
                successMessage = "Stone-dissolving smoke blasts the target.",
            },
        },
    },

    cockatrice_oil = {
        name = "Cockatrice Flesh-Stone Oil",
        size = 1,
        durability = 1,
        properties = {
            oil = true,
            alchemical = true,
            consumable = true,
            source = "cockatrice",
            useEffect = {
                type = "cockatrice_stone_flesh",
                target = "target",
                successMessage = "Stone softens into flesh where the oil touches.",
            },
        },
    },

    face_rat_potion = {
        name = "Face Rat Potion",
        size = 1,
        durability = 1,
        properties = {
            potion = true,
            alchemical = true,
            consumable = true,
            source = "face_rat",
            useEffect = {
                type = "apply_conditions",
                target = "self",
                duration = "watch",
                conditions = {
                    face_rat_illusion = true,
                    illusion_duplicate_pending = true,
                    visual_illusion = true,
                },
                successMessage = "An illusion settles over you, ready to copy the first creature you see.",
            },
        },
    },

    face_rat_bomb = {
        name = "Face Rat Skin Bomb",
        size = 1,
        durability = 1,
        properties = {
            bomb = true,
            alchemical = true,
            consumable = true,
            consumeOnAttempt = true,
            offensive = true,
            source = "face_rat",
            useEffect = {
                type = "apply_conditions",
                target = "target",
                conditions = {
                    blind = true,
                    blinded = true,
                    deaf = true,
                    deafened = true,
                    silenced = true,
                },
                successMessage = "Skin grows over the target's ears, eyes, and mouth.",
            },
        },
    },

    fungoid_potion = {
        name = "Fungoid Potion",
        size = 1,
        durability = 1,
        properties = {
            potion = true,
            alchemical = true,
            consumable = true,
            source = "fungoid",
            useEffect = {
                type = "heal_wound",
                target = "self_or_target",
                successMessage = "Mushrooms sprout where the wound closes.",
            },
        },
    },

    fungoid_bomb = {
        name = "Fungoid Spore Bomb",
        size = 1,
        durability = 1,
        properties = {
            bomb = true,
            alchemical = true,
            consumable = true,
            consumeOnAttempt = true,
            offensive = true,
            source = "fungoid",
            useEffect = {
                type = "apply_conditions",
                target = "target",
                conditions = {
                    exhausted = true,
                },
                successMessage = "A choking cloud of spores leaves the target exhausted.",
            },
        },
    },

    fungoid_oil = {
        name = "Fungoid Oil",
        size = 1,
        durability = 1,
        properties = {
            oil = true,
            alchemical = true,
            consumable = true,
            source = "fungoid",
            useEffect = {
                type = "mushroom_patch",
                target = "target",
                duration = "watch",
                mushroomsBySuit = {
                    [1] = { id = "giant_inky_cap", name = "giant inky cap", edible = true, poisonousWithAlcohol = true },
                    [2] = { id = "giant_destroying_angel", name = "giant destroying angel", poisonous = true },
                    [3] = { id = "giant_hen_of_the_woods", name = "giant hen of the woods", edible = true },
                    [4] = { id = "giant_shrieker", name = "giant shrieker", magical = true, screams = true },
                },
                successMessage = "Huge mushrooms erupt where the oil is poured.",
            },
        },
    },

    harpy_potion = {
        name = "Harpy Potion",
        size = 1,
        durability = 1,
        properties = {
            potion = true,
            alchemical = true,
            consumable = true,
            source = "harpy",
            useEffect = {
                type = "apply_conditions",
                target = "self",
                duration = "watch",
                conditions = {
                    harpy_wings = true,
                    flying = true,
                    flight = true,
                    arms_are_wings = true,
                    cannot_hold_items = true,
                    cannot_hover = true,
                    must_keep_flying = true,
                },
                successMessage = "Your arms become wings for a watch; you can fly but cannot hold anything.",
            },
        },
    },

    harpy_bomb = {
        name = "Harpy Distaste Bomb",
        size = 1,
        durability = 1,
        properties = {
            bomb = true,
            alchemical = true,
            consumable = true,
            consumeOnAttempt = true,
            offensive = true,
            source = "harpy",
            useEffect = {
                type = "distaste_inspiration",
                target = "target",
                duration = "watch",
                successMessage = "The victim hates the first creature they see for a watch.",
            },
        },
    },

    imp_potion = {
        name = "Imp Potion",
        size = 1,
        durability = 1,
        properties = {
            potion = true,
            alchemical = true,
            consumable = true,
            source = "imp",
            useEffect = {
                type = "purge_poison_alchemy",
                target = "self",
                successMessage = "You vomit up poisons and lingering alchemy.",
            },
        },
    },

    imp_bomb = {
        name = "Imp Stink Bomb",
        size = 1,
        durability = 1,
        properties = {
            bomb = true,
            alchemical = true,
            consumable = true,
            consumeOnAttempt = true,
            offensive = true,
            source = "imp",
            useEffect = {
                type = "imp_stink",
                target = "target",
                successMessage = "The target chokes on a terrible stink.",
            },
        },
    },

    imp_oil = {
        name = "Imp Frictionless Oil",
        size = 1,
        durability = 1,
        properties = {
            oil = true,
            alchemical = true,
            consumable = true,
            source = "imp",
            useEffect = {
                type = "frictionless_surface",
                target = "target",
                puddleDiameterFeet = 10,
                successMessage = "The touched surface becomes utterly frictionless.",
            },
        },
    },

    griffin_potion = {
        name = "Griffin Potion",
        size = 1,
        durability = 1,
        properties = {
            potion = true,
            alchemical = true,
            consumable = true,
            source = "griffin",
            useEffect = {
                type = "dungeon_bird_rumor",
                target = "self",
                arrivesInWatches = 1,
                successMessage = "A dungeon bird will seek you out with a rumor in a watch or so.",
            },
        },
    },

    griffin_oil = {
        name = "Griffin Cleansing Oil",
        size = 1,
        durability = 1,
        properties = {
            oil = true,
            alchemical = true,
            consumable = true,
            source = "griffin",
            useEffect = {
                type = "cleanse_surface",
                target = "target",
                successMessage = "Rust, flaws, impurities, and filth slide away.",
            },
        },
    },

    jinn_potion = {
        name = "Jinn Potion",
        size = 1,
        durability = 1,
        properties = {
            potion = true,
            alchemical = true,
            consumable = true,
            source = "jinn",
            useEffect = {
                type = "jinn_shroud",
                target = "self",
                duration = "visible_interaction",
                successMessage = "Smokeless fire hides you as Shrouded until you touch the visible world.",
            },
        },
    },

    jinn_bomb = {
        name = "Jinn Materializing Bomb",
        size = 1,
        durability = 1,
        properties = {
            bomb = true,
            alchemical = true,
            consumable = true,
            consumeOnAttempt = true,
            offensive = true,
            source = "jinn",
            useEffect = {
                type = "materialize_intangible",
                target = "target",
                successMessage = "The intangible target is forced into visible, tangible form.",
            },
        },
    },

    jinn_oil = {
        name = "Jinn City Oil",
        size = 1,
        durability = 1,
        properties = {
            oil = true,
            alchemical = true,
            consumable = true,
            source = "jinn",
            useEffect = {
                type = "city_portal",
                target = "target",
                duration = "one_minute",
                successMessage = "A fiery hole opens in reality toward the City.",
            },
        },
    },

    mimic_potion = {
        name = "Mimic Potion",
        size = 1,
        durability = 1,
        properties = {
            potion = true,
            alchemical = true,
            consumable = true,
            source = "mimic",
            useEffect = {
                type = "object_speech",
                target = "self",
                duration = "three_minutes_real_time",
                realTimeMinutes = 3,
                successMessage = "You can talk to objects for the next three minutes.",
            },
        },
    },

    mimic_oil = {
        name = "Mimic Awakening Oil",
        size = 1,
        durability = 1,
        properties = {
            oil = true,
            alchemical = true,
            consumable = true,
            source = "mimic",
            useEffect = {
                type = "awaken_mimic",
                target = "target",
                successMessage = "The non-living object becomes a mimic, and it is not loyal to you.",
            },
        },
    },

    kelpie_potion = {
        name = "Kelpie Potion",
        size = 1,
        durability = 1,
        properties = {
            potion = true,
            alchemical = true,
            consumable = true,
            source = "kelpie",
            useEffect = {
                type = "apply_conditions",
                target = "self",
                duration = "watch",
                conditions = {
                    water_breathing = true,
                    underwater_breathing = true,
                    gills = true,
                },
                successMessage = "Gills open along your neck; you can breathe underwater for a watch.",
            },
        },
    },

    kelpie_oil = {
        name = "Kelpie Oil",
        size = 1,
        durability = 1,
        properties = {
            oil = true,
            alchemical = true,
            consumable = true,
            source = "kelpie",
            useEffect = {
                type = "apply_properties",
                target = "target",
                duration = "watch",
                properties = {
                    rejectsWater = true,
                    hydrophobic = true,
                    buoyant = true,
                    waterWalking = true,
                    waterPlatform = true,
                },
                successMessage = "The touched surface rejects water for a watch.",
            },
        },
    },

    nymph_potion = {
        name = "Nymph Potion",
        size = 1,
        durability = 1,
        properties = {
            potion = true,
            alchemical = true,
            consumable = true,
            source = "nymph",
            useEffect = {
                type = "apply_conditions",
                target = "self",
                duration = "watch",
                conditions = {
                    nymph_beauty = true,
                    disposition_influence_favor = true,
                    inspire_immune = true,
                    control_immune = true,
                },
                successMessage = "You become supernaturally beautiful and hard to sway for a watch.",
            },
        },
    },

    nymph_bomb = {
        name = "Nymph Love Bomb",
        size = 1,
        durability = 1,
        properties = {
            bomb = true,
            alchemical = true,
            consumable = true,
            consumeOnAttempt = true,
            offensive = true,
            source = "nymph",
            useEffect = {
                type = "romantic_inspiration",
                target = "target",
                duration = "watch",
                successMessage = "The victim falls romantically in love with the first creature they see.",
            },
        },
    },

    winter_wolf_potion = {
        name = "Winter Wolf Potion",
        size = 1,
        durability = 1,
        properties = {
            potion = true,
            alchemical = true,
            consumable = true,
            source = "winter_wolf",
            useEffect = {
                type = "apply_conditions",
                target = "self",
                duration = "watch",
                conditions = {
                    cold_immunity = true,
                    ice_damage_immunity = true,
                    comfortable_in_cold = true,
                },
                successMessage = "Cold and ice cannot harm you for a watch.",
            },
        },
    },

    winter_wolf_oil = {
        name = "Winter Wolf Oil",
        size = 1,
        durability = 1,
        properties = {
            oil = true,
            alchemical = true,
            consumable = true,
            source = "winter_wolf",
            useEffect = {
                type = "apply_properties",
                target = "target",
                properties = {
                    freezing = true,
                    freezesWater = true,
                    createsIceWall = true,
                    iceWallHeightFeet = 10,
                    iceWallWidthFeet = 10,
                    iceWallThicknessFeet = 1,
                    opaque = true,
                    impermeable = true,
                },
                successMessage = "The oil freezes into an opaque wall or sheet of ice.",
            },
        },
    },

    titan_potion = {
        name = "Titan Potion",
        size = 1,
        durability = 1,
        properties = {
            potion = true,
            alchemical = true,
            consumable = true,
            source = "titan",
            useEffect = {
                type = "grow_creature",
                target = "self",
                duration = "watch",
                sizeMultiplier = 2,
                heightMultiplier = 2,
                challengeActionFavor = false,
                successMessage = "Your body swells with Titan growth for a watch.",
            },
        },
    },

    titan_oil = {
        name = "Titan Oil",
        size = 1,
        durability = 1,
        properties = {
            oil = true,
            alchemical = true,
            consumable = true,
            source = "titan",
            useEffect = {
                type = "apply_properties",
                target = "target",
                properties = {
                    weightMultiplier = 10,
                    tenTimesHeavy = true,
                    structurallyIntact = true,
                    environmentalStructuralStress = true,
                },
                successMessage = "The touched object becomes ten times as heavy.",
            },
        },
    },

    ogre_potion = {
        name = "Ogre Potion",
        size = 1,
        durability = 1,
        properties = {
            potion = true,
            alchemical = true,
            consumable = true,
            source = "ogre",
            useEffect = {
                type = "apply_conditions",
                target = "self",
                duration = "watch",
                conditions = {
                    poison_immunity = true,
                    ingestion_immunity = true,
                    harmless_swallowing = true,
                },
                successMessage = "Poisons and swallowed hazards cannot harm you for a watch.",
            },
        },
    },

    ogre_bomb = {
        name = "Ogre Pheromone Bomb",
        size = 1,
        durability = 1,
        properties = {
            bomb = true,
            alchemical = true,
            consumable = true,
            consumeOnAttempt = true,
            offensive = true,
            source = "ogre",
            useEffect = {
                type = "rage_pheromone",
                target = "target",
                successMessage = "Rage-inducing pheromones make nearby creatures furious at the target.",
            },
        },
    },

    ogre_oil = {
        name = "Ogre Solvent Oil",
        size = 1,
        durability = 1,
        properties = {
            oil = true,
            alchemical = true,
            consumable = true,
            source = "ogre",
            useEffect = {
                type = "apply_properties",
                target = "target",
                properties = {
                    universalSolvent = true,
                    breaksAdhesives = true,
                    softensMaterials = true,
                    stoneToMud = true,
                    metalBendable = true,
                    woodPaper = true,
                },
                successMessage = "The solvent breaks adhesives and makes hard materials pliable.",
            },
        },
    },

    questing_beast_potion = {
        name = "Questing Beast Potion",
        size = 1,
        durability = 1,
        properties = {
            potion = true,
            alchemical = true,
            consumable = true,
            source = "questing_beast",
            useEffect = {
                type = "location_insight",
                target = "self",
                successMessage = "A prophetic insight reveals the sought location.",
            },
        },
    },

    questing_beast_oil = {
        name = "Questing Beast Oil",
        size = 1,
        durability = 1,
        properties = {
            oil = true,
            alchemical = true,
            consumable = true,
            source = "questing_beast",
            useEffect = {
                type = "barking_lure",
                target = "target",
                duration = "watch",
                drawCount = 2,
                successMessage = "The touched object barks like a pack of hounds.",
            },
        },
    },

    ungoat_potion = {
        name = "Ungoat Potion",
        size = 1,
        durability = 1,
        properties = {
            potion = true,
            alchemical = true,
            consumable = true,
            source = "ungoat",
            useEffect = {
                type = "apply_conditions",
                target = "self",
                duration = "watch",
                conditions = {
                    ungoat_spell_ward = true,
                    spell_target_blocked = true,
                    cannot_cast_spells = true,
                },
                successMessage = "Magic treats you as iron-clad for a watch.",
            },
        },
    },

    ungoat_bomb = {
        name = "Ungoat Maleficence Bomb",
        size = 1,
        durability = 1,
        properties = {
            bomb = true,
            alchemical = true,
            consumable = true,
            consumeOnAttempt = true,
            offensive = true,
            source = "ungoat",
            useEffect = {
                type = "trigger_maleficence",
                target = "target",
                successMessage = "Maleficence erupts around the target.",
            },
        },
    },

    ungoat_oil = {
        name = "Ungoat Oil",
        size = 1,
        durability = 1,
        properties = {
            oil = true,
            alchemical = true,
            consumable = true,
            source = "ungoat",
            useEffect = {
                type = "negate_spells",
                target = "target",
                duration = "watch",
                successMessage = "Active magic on the touched target goes dormant.",
            },
        },
    },

    vampire_potion = {
        name = "Vampire Potion",
        size = 1,
        durability = 1,
        properties = {
            potion = true,
            alchemical = true,
            consumable = true,
            source = "vampire",
            useEffect = {
                type = "mist_form",
                target = "self",
                duration = "watch",
                successMessage = "You dissolve into thick mist for a watch.",
            },
        },
    },

    vampire_bomb = {
        name = "Vampire Weakness Bomb",
        size = 1,
        durability = 1,
        properties = {
            bomb = true,
            alchemical = true,
            consumable = true,
            consumeOnAttempt = true,
            offensive = true,
            source = "vampire",
            useEffect = {
                type = "vampire_weaknesses",
                target = "target",
                duration = "watch",
                successMessage = "The target suffers vampire weaknesses for a watch.",
            },
        },
    },

    slime_potion = {
        name = "Slime Potion",
        size = 1,
        durability = 1,
        properties = {
            potion = true,
            alchemical = true,
            consumable = true,
            source = "slime",
            useEffect = {
                type = "apply_conditions",
                target = "self",
                duration = "watch",
                conditions = {
                    shapeless_body = true,
                    no_fall_damage = true,
                    squeeze_through_gaps = true,
                },
                successMessage = "Your body becomes boneless and squeezable for a watch.",
            },
        },
    },

    slime_bomb = {
        name = "Slime Bomb",
        size = 1,
        durability = 1,
        properties = {
            bomb = true,
            alchemical = true,
            consumable = true,
            consumeOnAttempt = true,
            offensive = true,
            source = "slime",
            useEffect = {
                type = "destroy_armor",
                target = "target",
                successMessage = "Neon-green acid destroys the target's armor.",
            },
        },
    },

    slime_oil = {
        name = "Slime Oil",
        size = 1,
        durability = 1,
        properties = {
            oil = true,
            alchemical = true,
            consumable = true,
            source = "slime",
            useEffect = {
                type = "destroy_object_or_damage_creature",
                target = "target",
                damageIfCreature = {
                    amount = 1,
                    effects = { "critical" },
                },
                immuneMaterials = { "glass" },
                successMessage = "The acid oil dissolves what it touches.",
            },
        },
    },

    brain_spider_reagent = {
        name = "Hermetic Bottle: Brain Spider Reagent",
        size = 1,
        durability = 1,
        type = "reagent",
        properties = {
            reagent = true,
            alchemicalReagent = true,
            hermeticBottle = true,
            source = "brain_spider",
            saleValue = 20,
            brewOutputs = {
                potion = "brain_spider_potion",
                bomb = "brain_spider_bomb",
                oil = "brain_spider_oil",
            },
        },
    },

    devil_reagent = {
        name = "Hermetic Bottle: Devil Reagent",
        size = 1,
        durability = 1,
        type = "reagent",
        properties = {
            reagent = true,
            alchemicalReagent = true,
            hermeticBottle = true,
            source = "devil",
            saleValue = 25,
            brewOutputs = {
                potion = "devil_potion",
                bomb = "devil_bomb",
                oil = "devil_oil",
            },
        },
    },

    cockatrice_reagent = {
        name = "Hermetic Bottle: Cockatrice Reagent",
        size = 1,
        durability = 1,
        type = "reagent",
        properties = {
            reagent = true,
            alchemicalReagent = true,
            hermeticBottle = true,
            source = "cockatrice",
            saleValue = 25,
            brewOutputs = {
                bomb = "cockatrice_bomb",
                oil = "cockatrice_oil",
            },
        },
    },

    face_rat_reagent = {
        name = "Hermetic Bottle: Face Rat Reagent",
        size = 1,
        durability = 1,
        type = "reagent",
        properties = {
            reagent = true,
            alchemicalReagent = true,
            hermeticBottle = true,
            source = "face_rat",
            saleValue = 10,
            brewOutputs = {
                potion = "face_rat_potion",
                bomb = "face_rat_bomb",
            },
        },
    },

    fungoid_reagent = {
        name = "Hermetic Bottle: Fungoid Reagent",
        size = 1,
        durability = 1,
        type = "reagent",
        properties = {
            reagent = true,
            alchemicalReagent = true,
            hermeticBottle = true,
            source = "fungoid",
            saleValue = 15,
            brewOutputs = {
                potion = "fungoid_potion",
                bomb = "fungoid_bomb",
                oil = "fungoid_oil",
            },
        },
    },

    harpy_reagent = {
        name = "Hermetic Bottle: Harpy Reagent",
        size = 1,
        durability = 1,
        type = "reagent",
        properties = {
            reagent = true,
            alchemicalReagent = true,
            hermeticBottle = true,
            source = "harpy",
            saleValue = 20,
            brewOutputs = {
                potion = "harpy_potion",
                bomb = "harpy_bomb",
            },
        },
    },

    imp_reagent = {
        name = "Hermetic Bottle: Imp Reagent",
        size = 1,
        durability = 1,
        type = "reagent",
        properties = {
            reagent = true,
            alchemicalReagent = true,
            hermeticBottle = true,
            source = "imp",
            saleValue = 20,
            brewOutputs = {
                potion = "imp_potion",
                bomb = "imp_bomb",
                oil = "imp_oil",
            },
        },
    },

    griffin_reagent = {
        name = "Hermetic Bottle: Griffin Reagent",
        size = 1,
        durability = 1,
        type = "reagent",
        properties = {
            reagent = true,
            alchemicalReagent = true,
            hermeticBottle = true,
            source = "griffin",
            saleValue = 20,
            brewOutputs = {
                potion = "griffin_potion",
                oil = "griffin_oil",
            },
        },
    },

    jinn_reagent = {
        name = "Hermetic Bottle: Jinn Reagent",
        size = 1,
        durability = 1,
        type = "reagent",
        properties = {
            reagent = true,
            alchemicalReagent = true,
            hermeticBottle = true,
            source = "jinn",
            saleValue = 20,
            brewOutputs = {
                potion = "jinn_potion",
                bomb = "jinn_bomb",
                oil = "jinn_oil",
            },
        },
    },

    mimic_reagent = {
        name = "Hermetic Bottle: Mimic Reagent",
        size = 1,
        durability = 1,
        type = "reagent",
        properties = {
            reagent = true,
            alchemicalReagent = true,
            hermeticBottle = true,
            source = "mimic",
            saleValue = 20,
            brewOutputs = {
                potion = "mimic_potion",
                oil = "mimic_oil",
            },
        },
    },

    kelpie_reagent = {
        name = "Hermetic Bottle: Kelpie Reagent",
        size = 1,
        durability = 1,
        type = "reagent",
        properties = {
            reagent = true,
            alchemicalReagent = true,
            hermeticBottle = true,
            source = "kelpie",
            saleValue = 20,
            brewOutputs = {
                potion = "kelpie_potion",
                oil = "kelpie_oil",
            },
        },
    },

    nymph_reagent = {
        name = "Hermetic Bottle: Nymph Reagent",
        size = 1,
        durability = 1,
        type = "reagent",
        properties = {
            reagent = true,
            alchemicalReagent = true,
            hermeticBottle = true,
            source = "nymph",
            saleValue = 25,
            brewOutputs = {
                potion = "nymph_potion",
                bomb = "nymph_bomb",
            },
        },
    },

    ogre_reagent = {
        name = "Hermetic Bottle: Ogre Reagent",
        size = 1,
        durability = 1,
        type = "reagent",
        properties = {
            reagent = true,
            alchemicalReagent = true,
            hermeticBottle = true,
            source = "ogre",
            saleValue = 20,
            brewOutputs = {
                potion = "ogre_potion",
                bomb = "ogre_bomb",
                oil = "ogre_oil",
            },
        },
    },

    questing_beast_reagent = {
        name = "Hermetic Bottle: Questing Beast Reagent",
        size = 1,
        durability = 1,
        type = "reagent",
        properties = {
            reagent = true,
            alchemicalReagent = true,
            hermeticBottle = true,
            source = "questing_beast",
            saleValue = 25,
            brewOutputs = {
                potion = "questing_beast_potion",
                oil = "questing_beast_oil",
            },
        },
    },

    ungoat_reagent = {
        name = "Hermetic Bottle: Ungoat Reagent",
        size = 1,
        durability = 1,
        type = "reagent",
        properties = {
            reagent = true,
            alchemicalReagent = true,
            hermeticBottle = true,
            source = "ungoat",
            saleValue = 25,
            brewOutputs = {
                potion = "ungoat_potion",
                bomb = "ungoat_bomb",
                oil = "ungoat_oil",
            },
        },
    },

    vampire_reagent = {
        name = "Hermetic Bottle: Vampire Reagent",
        size = 1,
        durability = 1,
        type = "reagent",
        properties = {
            reagent = true,
            alchemicalReagent = true,
            hermeticBottle = true,
            source = "vampire",
            saleValue = 25,
            brewOutputs = {
                potion = "vampire_potion",
                bomb = "vampire_bomb",
            },
        },
    },

    winter_wolf_reagent = {
        name = "Hermetic Bottle: Winter Wolf Reagent",
        size = 1,
        durability = 1,
        type = "reagent",
        properties = {
            reagent = true,
            alchemicalReagent = true,
            hermeticBottle = true,
            source = "winter_wolf",
            saleValue = 20,
            brewOutputs = {
                potion = "winter_wolf_potion",
                oil = "winter_wolf_oil",
            },
        },
    },

    titan_reagent = {
        name = "Hermetic Bottle: Titan Reagent",
        size = 1,
        durability = 1,
        type = "reagent",
        properties = {
            reagent = true,
            alchemicalReagent = true,
            hermeticBottle = true,
            source = "titan",
            saleValue = 25,
            brewOutputs = {
                potion = "titan_potion",
                oil = "titan_oil",
            },
        },
    },

    slime_reagent = {
        name = "Hermetic Bottle: Slime Reagent",
        size = 1,
        durability = 1,
        type = "reagent",
        properties = {
            reagent = true,
            alchemicalReagent = true,
            hermeticBottle = true,
            source = "slime",
            saleValue = 15,
            brewOutputs = {
                potion = "slime_potion",
                bomb = "slime_bomb",
                oil = "slime_oil",
            },
        },
    },

    ----------------------------------------------------------------------------
    -- AMMUNITION
    ----------------------------------------------------------------------------

    arrows = {
        name = "Arrows",
        size = 1,
        stackable = true,
        stackSize = 20,
        quantity = 10,
        ammoType = "arrow",
    },

    bolts = {
        name = "Crossbow Bolts",
        size = 1,
        stackable = true,
        stackSize = 20,
        quantity = 10,
        ammoType = "bolt",
    },

    ----------------------------------------------------------------------------
    -- TOOLS
    ----------------------------------------------------------------------------

    lockpicks = {
        name = "Lockpicks",
        size = 1,
        durability = 2,
        properties = { tool = true, toolType = "lockpick" },
    },

    rope = {
        name = "Rope (50ft)",
        size = 1,
        durability = 2,
        properties = { tool = true, toolType = "rope" },
    },

    grappling_hook = {
        name = "Grappling Hook",
        size = 1,
        durability = 2,
        properties = { tool = true, toolType = "grapple" },
    },

    caltrops = {
        name = "Caltrops",
        size = 1,
        durability = 1,
        properties = { tool = true, areaDenial = true },
    },

    chain_10ft = {
        name = "Chain, 10ft",
        size = 1,
        durability = 3,
        properties = { tool = true, toolType = "chain", length = "10ft" },
    },

    crowbar = {
        name = "Crowbar",
        size = 1,
        durability = 3,
        properties = { tool = true, toolType = "crowbar" },
    },

    fishing_gear = {
        name = "Fishing Gear",
        size = 1,
        durability = 2,
        properties = { tool = true, toolType = "fishing" },
    },

    hammer = {
        name = "Hammer",
        size = 1,
        durability = 2,
        properties = { tool = true, toolType = "hammer" },
    },

    hatchet = {
        name = "Hatchet",
        size = 1,
        durability = 2,
        properties = { tool = true, toolType = "hatchet" },
    },

    iron_spikes = {
        name = "Iron Spikes",
        size = 1,
        stackable = true,
        stackSize = 6,
        quantity = 6,
        durability = 3,
        properties = { tool = true, toolType = "spikes", iron = true },
    },

    mirror = {
        name = "Mirror",
        size = 1,
        durability = 1,
        properties = { tool = true, reflective = true },
    },

    musical_instrument = {
        name = "Musical Instrument",
        size = 1,
        durability = 2,
        properties = { tool = true, toolType = "instrument" },
    },

    quill_and_ink = {
        name = "Quill and Ink",
        size = 1,
        durability = 1,
        properties = { tool = true, writing = true },
    },

    pole_10ft = {
        name = "Pole, 10ft",
        size = 2,
        durability = 2,
        oversized = true,
        properties = { tool = true, toolType = "pole", length = "10ft" },
    },

    pick = {
        name = "Pick",
        size = 2,
        durability = 3,
        oversized = true,
        properties = { tool = true, toolType = "pick" },
    },

    shovel = {
        name = "Shovel",
        size = 2,
        durability = 2,
        oversized = true,
        properties = { tool = true, toolType = "shovel" },
    },

    tinkers_kit = {
        name = "Tinker's Kit",
        size = 2,
        durability = 3,
        type = "tinkers_kit",
        properties = { tool = true, toolType = "tinker" },
    },

    alchemy_kit = {
        name = "Alchemy Kit",
        size = 2,
        durability = 3,
        type = "alchemy_kit",
        properties = { tool = true, toolType = "alchemy", alchemyKit = true },
    },

    hermetic_bottle = {
        name = "Hermetic Bottle",
        size = 1,
        durability = 1,
        type = "hermetic_bottle",
        properties = { hermeticBottle = true, empty = true },
    },

    cooking_gear = {
        name = "Cooking Gear",
        size = 1,
        durability = 2,
        type = "cooking_gear",
        properties = { tool = true, toolType = "cooking", cookingGear = true },
    },

    blank_book = {
        name = "Blank Book",
        size = 1,
        durability = 1,
        type = "book",
        properties = {
            book = true,
            writable = true,
        },
    },

    clothes_rags = {
        name = "Clothes, Rags",
        size = 1,
        durability = 1,
        properties = { clothes = true, quality = "rags" },
    },

    clothes_common = {
        name = "Clothes, Common",
        size = 1,
        durability = 1,
        properties = { clothes = true, quality = "common" },
    },

    clothes_finery = {
        name = "Clothes, Finery",
        size = 1,
        durability = 1,
        properties = { clothes = true, quality = "finery" },
    },

    falconry_gear = {
        name = "Falconry Gear",
        size = 1,
        durability = 2,
        properties = { tool = true, toolType = "falconry" },
    },

    hourglass = {
        name = "Hourglass",
        size = 1,
        durability = 1,
        properties = { tool = true, timekeeping = true },
    },

    manacles = {
        name = "Manacles",
        size = 1,
        durability = 3,
        properties = { tool = true, restraint = true },
    },

    spyglass = {
        name = "Spyglass",
        size = 1,
        durability = 2,
        properties = { tool = true, magnification = true },
    },

    wand_archwood = {
        name = "Wand of Archwood",
        size = 1,
        durability = 2,
        properties = { wand = true, archwood = true },
    },

    tomb_lore_book = {
        name = "Moldering Tomb Astronomies",
        size = 1,
        durability = 1,
        type = "book",
        properties = {
            book = true,
            readableBook = true,
            subjectMatter = "Guardian Shrine and tomb astronomy",
            loreSubjectId = "location_guardian_shrine",
            loreMotif = "bookish history astronomy",
        },
    },

    component_control_animal = {
        name = "Scepter of Lion Bone",
        size = 1,
        durability = 2,
        properties = {
            spellComponent = true,
            componentFor = "control_animal",
            branch = "weald",
            tags = { "spell_component" },
        },
    },

    component_flare = {
        name = "Guano of a Dire Bat",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "flare",
            branch = "weald",
            tags = { "spell_component" },
        },
    },

    component_defy_depths = {
        name = "Calcified Mermaid Fetus",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "defy_depths",
            branch = "weald",
            tags = { "spell_component" },
        },
    },

    component_gust_of_wind = {
        name = "Beetle Shells Etched with Runes",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "gust_of_wind",
            branch = "weald",
            tags = { "spell_component" },
        },
    },

    component_protection_from_elements = {
        name = "Ungoat-Stomach Bag of Beads",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "protection_from_elements",
            branch = "weald",
            tags = { "spell_component" },
        },
    },

    component_speak_to_animal = {
        name = "Mummified Dire Spider Egg",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "speak_to_animal",
            branch = "weald",
            tags = { "spell_component" },
        },
    },

    component_thunderclap = {
        name = "Shard of Broken Thunderbolt Iron",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "thunderclap",
            branch = "weald",
            tags = { "spell_component" },
        },
    },

    component_totem = {
        name = "Last Acorn of an Elder Oak",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "totem",
            branch = "weald",
            tags = { "spell_component" },
        },
    },

    component_wall_of_elements = {
        name = "Mellified Mummy Snail Shell",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "wall_of_elements",
            branch = "weald",
            tags = { "spell_component" },
        },
    },

    component_woodweave = {
        name = "Vial of Woodwose Blood",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "woodweave",
            branch = "weald",
            tags = { "spell_component" },
        },
    },

    component_brainfever = {
        name = "Pouch of Marjoram, Thyme, Verbena, and Myrtle Powder",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "brainfever",
            branch = "wastes",
            tags = { "spell_component" },
        },
    },

    component_control_undead = {
        name = "Graveyard-Grass Poppet",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "control_undead",
            branch = "wastes",
            tags = { "spell_component" },
        },
    },

    component_necromancy = {
        name = "Sigil-Tattooed Pickled Tongue",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "necromancy",
            branch = "wastes",
            tags = { "spell_component" },
        },
    },

    component_malediction = {
        name = "Pickled Miser's Eye",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "malediction",
            branch = "wastes",
            tags = { "spell_component" },
        },
    },

    component_fleshcraft = {
        name = "Silver Athame",
        size = 1,
        durability = 3,
        properties = {
            spellComponent = true,
            componentFor = "fleshcraft",
            branch = "wastes",
            silver = true,
            tags = { "spell_component", "knife" },
        },
    },

    component_raise_zombie = {
        name = "Mithril Ink",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "raise_zombie",
            branch = "wastes",
            ritualInk = true,
            tags = { "spell_component", "ink" },
        },
    },

    component_darklight = {
        name = "Pickled Left Hand of a Hanged Murderer",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "darklight",
            branch = "wastes",
            tags = { "spell_component" },
        },
    },

    component_fear = {
        name = "Black Serpent Fat Candle",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "fear",
            branch = "wastes",
            tags = { "spell_component" },
        },
    },

    component_heavenfire = {
        name = "Bull-Fat Votive Candle",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "heavenfire",
            branch = "welkin",
            tags = { "spell_component" },
        },
    },

    component_augury = {
        name = "Copy of the Codex Sophia",
        size = 1,
        durability = 2,
        properties = {
            spellComponent = true,
            componentFor = "augury",
            branch = "welkin",
            tags = { "spell_component", "book" },
        },
    },

    component_binding = {
        name = "Holy Finger Bone",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "binding",
            branch = "welkin",
            tags = { "spell_component" },
        },
    },

    component_charm = {
        name = "Oils of Myrrh in an Ivory Censer",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "charm",
            branch = "welkin",
            tags = { "spell_component" },
        },
    },

    component_circle_of_protection = {
        name = "Saint's Ashes in a Silver Monstrance",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "circle_of_protection",
            branch = "welkin",
            tags = { "spell_component" },
        },
    },

    component_feather = {
        name = "Lamassu Feather",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "feather",
            branch = "welkin",
            tags = { "spell_component" },
        },
    },

    component_guardian_angel = {
        name = "Sacred Spring Water",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "guardian_angel",
            branch = "welkin",
            tags = { "spell_component" },
        },
    },

    component_animate_object = {
        name = "Vial of Quicksilver",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "animate_object",
            branch = "weird",
            tags = { "spell_component" },
        },
    },

    component_change_size = {
        name = "Rat-King Tail Twine",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "change_size",
            branch = "weird",
            tags = { "spell_component" },
        },
    },

    component_enrage = {
        name = "Mummified Viper",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "enrage",
            branch = "weird",
            tags = { "spell_component" },
        },
    },

    component_give_form_to_nothingness = {
        name = "Rune-Painted Albino-Deer Hide Drum",
        size = 1,
        durability = 2,
        properties = {
            spellComponent = true,
            componentFor = "give_form_to_nothingness",
            branch = "weird",
            requiresTwoHandsToPlayDuringChallenges = true,
            continuousPerformance = true,
            tags = { "spell_component", "drum" },
        },
    },

    component_portable_hole = {
        name = "Midnight Black-Calf Hide Circle",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "portable_hole",
            branch = "weird",
            diameterInches = 9,
            calfskin = true,
            tags = { "spell_component", "hide", "calfskin" },
        },
    },

    component_illusion = {
        name = "Seven-Faceted Prism",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "illusion",
            branch = "weird",
            facets = 7,
            prism = true,
            tags = { "spell_component", "prism" },
        },
    },

    component_mirror_meld = {
        name = "Vial of Dreaming Children's Tears",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "mirror_meld",
            branch = "weird",
            tears = true,
            tags = { "spell_component", "vial" },
        },
    },

    component_sleep = {
        name = "Pouch of Lotus, Sand, and Wormwood Powder",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "sleep",
            branch = "weird",
            tags = { "spell_component" },
        },
    },

    component_shroud = {
        name = "Elf-Arrow Funerary Winding Sheet",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "shroud",
            branch = "weird",
            tags = { "spell_component" },
        },
    },

    component_scry = {
        name = "Crystal Ball",
        size = 1,
        durability = 2,
        properties = {
            spellComponent = true,
            componentFor = "scry",
            branch = "weird",
            crystalBall = true,
            tags = { "spell_component" },
        },
    },

    component_stinking_cloud = {
        name = "Mummified Green Frog",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "stinking_cloud",
            branch = "wastes",
            tags = { "spell_component" },
        },
    },

    component_withering = {
        name = "Jar of Etched Fingernails",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "withering",
            branch = "wastes",
            tags = { "spell_component" },
        },
    },

    component_life = {
        name = "Phoenix Feather",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "life",
            branch = "welkin",
            tags = { "spell_component" },
        },
    },

    component_veritas = {
        name = "Sacramental Wine in a Golden Ciborium",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "veritas",
            branch = "welkin",
            tags = { "spell_component" },
        },
    },

    component_seal_pact = {
        name = "Bag of Goblin Teeth and Finger Joints",
        size = 1,
        durability = 1,
        properties = {
            spellComponent = true,
            componentFor = "seal_pact",
            branch = "welkin",
            tags = { "spell_component" },
        },
    },

    chalk = {
        name = "Chalk",
        size = 1,
        stackable = true,
        stackSize = 10,
        quantity = 5,
        properties = { tool = true, toolType = "marking" },
    },

    ----------------------------------------------------------------------------
    -- KEYS
    ----------------------------------------------------------------------------

    silver_spider_key = {
        name = "Silver Spider Key",
        size = 1,
        durability = 3,
        keyId = "laboratory_door",
        properties = { key = true },
    },

    rusty_key = {
        name = "Rusty Key",
        size = 1,
        durability = 1,
        keyId = "generic_door",
        properties = { key = true },
    },

    golden_key = {
        name = "Golden Key",
        size = 1,
        durability = 3,
        keyId = "treasure_vault",
        properties = { key = true },
    },

    ----------------------------------------------------------------------------
    -- TREASURE
    ----------------------------------------------------------------------------

    gold_coins = {
        name = "Gold Coins",
        size = 1,
        stackable = true,
        stackSize = 100,
        quantity = 1,
        properties = { currency = true, value = 1 },
    },

    gold_coins_15 = {
        name = "Gold Coins",
        size = 1,
        stackable = true,
        stackSize = 100,
        quantity = 15,
        properties = { currency = true, value = 1 },
    },

    ruby_ring = {
        name = "Ruby Ring",
        size = 1,
        properties = { jewelry = true, value = 50 },
    },

    golden_amulet = {
        name = "Golden Amulet",
        size = 1,
        properties = { jewelry = true, magical = true, value = 100 },
    },

    ----------------------------------------------------------------------------
    -- QUEST ITEMS
    ----------------------------------------------------------------------------

    vellum_map = {
        name = "Vellum Map",
        size = 1,
        properties = { quest_item = true, map = true },
    },

    silver_crown = {
        name = "Silver Crown",
        size = 1,
        properties = { quest_item = true, cursed = true },
    },

    crumpled_note = {
        name = "Crumpled Note",
        size = 1,
        properties = { readable = true, text = "The crown - don't let them take the crown!" },
    },

    partial_map = {
        name = "Partial Tomb Map",
        size = 1,
        properties = { map = true, incomplete = true },
    },

    -- S12.8: Social encounter rewards
    guardian_blessing = {
        name = "Guardian's Blessing",
        size = 1,
        properties = {
            magical = true,
            blessing = true,
            effect = "protection_from_undead",
            duration = "until_rest",
            description = "A spectral blessing that shields you from hostile undead.",
        },
    },

    golden_medallion = {
        name = "Golden Medallion",
        size = 1,
        properties = {
            jewelry = true,
            magical = true,
            value = 75,
            effect = "sense_undead",
            description = "A medallion that grows warm when undead are near.",
        },
    },

    ----------------------------------------------------------------------------
    -- MISCELLANEOUS
    ----------------------------------------------------------------------------

    waterskin = {
        name = "Waterskin",
        size = 1,
        durability = 1,
        properties = { water_container = true, charges = 3 },
    },

    firewood = {
        name = "Firewood",
        size = 1,
        durability = 1,
        properties = {
            camping = true,
            firewood = true,
            felledWood = true,
            campComfort = "fire",
        },
    },

    flint_and_tinder = {
        name = "Flint and Tinder",
        size = 1,
        durability = 1,
        properties = {
            tool = true,
            toolType = "firestarter",
        },
    },

    garlic = {
        name = "Garlic",
        size = 1,
        durability = 1,
        properties = {
            ward = true,
            effect = "ward_undead",
            useEffect = {
                type = "ward_undead",
                target = "target",
                attribute = "wands",
                affectedTags = { "undead", "spirit" },
                successMessage = "The ward drives the creature back.",
                noEffectMessage = "The ward has no hold over this creature.",
            },
        },
    },

    religious_paraphernalia = {
        name = "Religious Paraphernalia",
        size = 1,
        durability = 1,
        properties = {
            ward = true,
            holy = true,
            effect = "ward_undead",
            useEffect = {
                type = "ward_undead",
                target = "target",
                attribute = "wands",
                affectedTags = { "undead", "spirit" },
                successMessage = "The icon forces the creature away.",
                noEffectMessage = "The icon has no hold over this creature.",
            },
        },
    },

    bedroll = {
        name = "Bedroll",
        size = 2,
        properties = { camping = true, bedroll = true, campComfort = "bedroll" },
    },

    tent = {
        name = "Tent",
        size = 2,
        oversized = true,
        properties = { camping = true, shelter = true, campComfort = "tent" },
    },
}

--------------------------------------------------------------------------------
-- TEMPLATE LOOKUP
--------------------------------------------------------------------------------

--- Get a template by ID
-- @param templateId string: The template ID
-- @return table or nil: The template data
function M.getTemplate(templateId)
    return M.templates[templateId]
end

--- Check if a template exists
-- @param templateId string: The template ID
-- @return boolean
function M.hasTemplate(templateId)
    return M.templates[templateId] ~= nil
end

--- Get all template IDs
-- @return table: Array of template IDs
function M.getAllTemplateIds()
    local ids = {}
    for id, _ in pairs(M.templates) do
        ids[#ids + 1] = id
    end
    return ids
end

return M
