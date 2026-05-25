-- spell_registry.lua
-- Data-backed spell definitions for Speak Incantation.

local constants = require('constants')

local M = {}

M.BRANCHES = {
    WASTES = "wastes",
    WEALD = "weald",
    WEIRD = "weird",
    WELKIN = "welkin",
}

M.spells = {
    brainfever = {
        id = "brainfever",
        name = "Brainfever",
        branch = M.BRANCHES.WASTES,
        talent = "magic_of_the_wastes",
        componentId = "component_brainfever",
        targetMode = "unwilling_creature",
        ongoing = true,
        concentration = true,
        effect = {
            type = "brainfever",
            componentAction = "blow_leaf_powder_toward_target",
            targetEntersRage = true,
            grantsAttackFavor = true,
            mustPlayLowestInitiative = true,
            emotionlessNoEffect = true,
        },
    },

    control_undead = {
        id = "control_undead",
        name = "Control Undead",
        branch = M.BRANCHES.WASTES,
        talent = "magic_of_the_wastes",
        componentId = "component_control_undead",
        targetMode = "unwilling_creature",
        ongoing = true,
        effect = {
            type = "control",
            targetTrait = "undead",
            componentAction = "command_with_graveyard_poppet",
            oneOrder = true,
            wordsPerResolveUsesWands = true,
            extraResolveAddsWandsWords = true,
            lastsUntilOrderFulfilled = true,
            committedResolveUntilFulfilled = true,
            suicidalOrdersAllowed = true,
        },
    },

    necromancy = {
        id = "necromancy",
        name = "Necromancy",
        branch = M.BRANCHES.WASTES,
        talent = "magic_of_the_wastes",
        componentId = "component_necromancy",
        targetMode = "dead_person",
        ongoing = true,
        concentration = true,
        effect = {
            type = "necromancy",
            componentAction = "place_pickled_tongue_inside_dead_person_skull",
            targetSpeaksAsIfAlive = true,
            deadNoCompulsion = true,
            deadNotGuaranteedHelpful = true,
            deadNotGuaranteedTruthful = true,
            canBargainNormally = true,
            likelyConcerns = {
                "unfinished_business",
                "revenge",
                "farewell",
                "loved_ones",
                "sundry_tasks",
            },
        },
    },

    malediction = {
        id = "malediction",
        name = "Malediction",
        branch = M.BRANCHES.WASTES,
        talent = "magic_of_the_wastes",
        componentId = "component_malediction",
        targetMode = "unwilling_creature",
        ongoing = true,
        effect = {
            type = "malediction",
            componentAction = "curse_with_pickled_miser_eye",
            drawsRandomCurse = true,
            permanentUntilDismissedOrCounterspelled = true,
            casterMayDismissAnyTime = true,
            cannotRecoverCurse = true,
            committedResolveNeverRefreshes = true,
        },
    },

    fleshcraft = {
        id = "fleshcraft",
        name = "Fleshcraft",
        branch = M.BRANCHES.WASTES,
        talent = "magic_of_the_wastes",
        componentId = "component_fleshcraft",
        targetMode = "self",
        ongoing = true,
        concentration = true,
        effect = {
            type = "fleshcraft",
            componentAction = "cut_off_body_part_with_silver_athame",
            detachedPartMovesIndependently = true,
            detachedPartMovesClumsily = true,
            detachedPartDamagePiercingWoundsTarget = 1,
            detachedPartDamageEndsSpell = true,
            rejoinsIfPlacedInOriginalPosition = true,
            partDetails = {
                hand = {
                    crawlsLikeSpider = true,
                    hardToNotice = true,
                    canChokeSleepingMan = true,
                    canPoisonCup = true,
                },
                eye = {
                    rollsOnGround = true,
                    targetCanSeeThroughIt = true,
                },
                ear = {
                    flopsLikeFish = true,
                    targetCanHearThroughIt = true,
                },
                mouth = {
                    speaksNormally = true,
                },
            },
            committedResolveNeverRefreshes = true,
        },
    },

    raise_zombie = {
        id = "raise_zombie",
        name = "Raise Zombie",
        branch = M.BRANCHES.WASTES,
        talent = "magic_of_the_wastes",
        componentId = "component_raise_zombie",
        targetMode = "dead_body",
        ongoing = true,
        effect = {
            type = "raise_zombie",
            componentAction = "trace_mithril_ink_symbols_around_body_for_watch",
            requiresWatchRitual = true,
            summonsWasteDevilIntoCorpse = true,
            bindsDevilToService = true,
            createsZombie = true,
            zombieHasNoAttributes = true,
            zombieIsRottingFlesh = true,
            retainsPhysicalCapabilitiesFromLife = true,
            commandActionDuringChallenges = true,
            obeysMostCommandsInGoodFaith = true,
            obeysSuicidalCommands = true,
            servicesPerResolveUsesWands = true,
            serviceEndDevilClaimsBody = true,
            committedResolveNeverRefreshes = true,
        },
    },

    control_animal = {
        id = "control_animal",
        name = "Control Animal",
        branch = M.BRANCHES.WEALD,
        talent = "magic_of_the_weald",
        componentId = "component_control_animal",
        targetMode = "unwilling_creature",
        ongoing = true,
        effect = {
            type = "control",
            targetTrait = "animal",
            componentAction = "command_with_lion_bone_scepter",
            oneOrder = true,
            targetScope = "animals_of_field_forest_or_fountains",
            wordsPerResolveUsesWands = true,
            extraResolveAddsWandsWords = true,
            animalsRefuseObviouslySuicidalOrders = true,
            lastsUntilOrderFulfilled = true,
            committedResolveUntilFulfilled = true,
        },
    },

    flare = {
        id = "flare",
        name = "Flare",
        branch = M.BRANCHES.WEALD,
        talent = "magic_of_the_weald",
        componentId = "component_flare",
        targetMode = "environment_or_creature",
        effect = {
            type = "flare",
            componentAction = "cause_light_source_to_flare_and_fizzle",
            candlesMayBeRelit = true,
            lanternsMayBeRelit = true,
            torchesCannotBeRelit = true,
            torchAndLanternWoundBearer = true,
            torchAndLanternIgniteBearer = true,
            campfireBombExplosion = true,
            campfireComparesSpeakIncantationToInitiative = true,
            campfireBlindDuration = "end_next_turn",
        },
    },

    defy_depths = {
        id = "defy_depths",
        name = "Defy Depths",
        branch = M.BRANCHES.WEALD,
        talent = "magic_of_the_weald",
        componentId = "component_defy_depths",
        targetMode = "creature_or_object",
        ongoing = true,
        concentration = true,
        baseTargets = 1,
        extraTargetResolve = 1,
        effect = {
            type = "defy_depths",
            humanSizedCreatureWalksOnWater = true,
            chestSizedObjectFloatsOnWater = true,
            floatsEvenIfSubmergedOrSunken = true,
            smallShipExtraResolve = 1,
            largeShipExtraResolve = 3,
            baseTargets = 1,
            extraTargetResolve = 1,
        },
    },

    gust_of_wind = {
        id = "gust_of_wind",
        name = "Gust of Wind",
        branch = M.BRANCHES.WEALD,
        talent = "magic_of_the_weald",
        componentId = "component_gust_of_wind",
        targetMode = "unwilling_creature",
        effect = {
            type = "gust_of_wind",
            displacesHumanSizedTarget = true,
            adjacentZoneOnly = true,
            gentleLanding = true,
            movementDoesNotHarmTarget = true,
            hazardousDestinationStillApplies = true,
            selfTargetAllowed = true,
            canCrossGaps = true,
        },
    },

    protection_from_elements = {
        id = "protection_from_elements",
        name = "Protection from the Elements",
        branch = M.BRANCHES.WEALD,
        talent = "magic_of_the_weald",
        componentId = "component_protection_from_elements",
        targetMode = "creature",
        ongoing = true,
        concentration = true,
        baseElements = 1,
        extraElementResolve = 1,
        baseTargets = 1,
        extraTargetResolve = 1,
        effect = {
            type = "protection_from_elements",
            protectsTargetAndGear = true,
            elementDetails = {
                fire = {
                    noHeatOrFlameDamage = true,
                    upTo = "forge_fire",
                },
                water = {
                    noColdOrIcyBlastDamage = true,
                },
                air = {
                    noNeedToBreathe = true,
                },
                earth = {
                    noFallingDamage = true,
                },
            },
        },
    },

    speak_to_animal = {
        id = "speak_to_animal",
        name = "Speak to Animal",
        branch = M.BRANCHES.WEALD,
        talent = "magic_of_the_weald",
        componentId = "component_speak_to_animal",
        targetMode = "self",
        ongoing = true,
        concentration = true,
        effect = {
            type = "speak_to_animal",
            componentPlacedUnderTongue = true,
            componentEggSize = "chicken_egg",
            garblesSpeechForNonAnimals = true,
            animalsSpeakAsIfNormal = true,
            animalNoCompulsion = true,
            animalsGenerallyHelpfulTruthful = true,
            normalAnimalsSimple = true,
            normalAnimalLimits = {
                "food",
                "mating",
                "safety",
            },
            ignoresOutsideSphere = true,
        },
    },

    thunderclap = {
        id = "thunderclap",
        name = "Thunderclap",
        branch = M.BRANCHES.WEALD,
        talent = "magic_of_the_weald",
        componentId = "component_thunderclap",
        targetMode = "environment",
        effect = {
            type = "thunderclap",
            componentAction = "last_syllable_resounds_like_thunderclap",
            affectsVisibleZone = true,
            shattersFragileObjects = true,
            fragileExamples = {
                "untempered_glass",
                "porcelain",
            },
            excludesSorcerer = true,
            creaturesChooseDropHeldItemsOrSuffer = true,
            dropHeldItemsCoversEars = true,
            alternativeConditions = {
                "stunned",
                "deafened",
            },
        },
    },

    totem = {
        id = "totem",
        name = "Totem",
        branch = M.BRANCHES.WEALD,
        talent = "magic_of_the_weald",
        componentId = "component_totem",
        targetMode = "creature",
        ongoing = true,
        effect = {
            type = "totem",
            componentPlacement = "mouth",
            componentCanBePlacedInTargetMouth = true,
            uniqueAnimalShape = true,
            representsSoulTotem = true,
            attributesAllZero = true,
            testOfFateBonus = 5,
            testBonusScope = "totem_known_actions",
            transformationSpeed = "near_instantaneous",
            wornItemsTransform = false,
            carriedObjectsTransform = false,
            droppedGearFallsAroundTarget = true,
            endsOnMouthUse = true,
            mouthUseEndActions = {
                "talk",
                "eat",
                "drink",
                "pick_up_with_mouth",
            },
        },
    },

    wall_of_elements = {
        id = "wall_of_elements",
        name = "Wall of Elements",
        branch = M.BRANCHES.WEALD,
        talent = "magic_of_the_weald",
        componentId = "component_wall_of_elements",
        targetMode = "environment",
        ongoing = true,
        concentration = true,
        effect = {
            type = "wall_of_elements",
            oneSectionPerResolve = true,
            maintainedByConcentration = true,
            sectionSizeFeet = {
                width = 10,
                height = 10,
                depth = 2,
            },
            elementBehaviors = {
                earth = {
                    opaque = true,
                    toughAsStone = true,
                    blocksPassage = true,
                },
                wind = {
                    opaque = false,
                    blocksMissileWeapons = true,
                    blocksFlyingCreatures = true,
                },
                fire = {
                    opaque = true,
                    permeable = true,
                    woundsOnPassage = true,
                },
                water = {
                    opaque = true,
                    impermeable = true,
                    requiresBodyOfWater = true,
                    blocksShips = true,
                    blocksWatercraft = true,
                },
            },
        },
    },

    woodweave = {
        id = "woodweave",
        name = "Woodweave",
        branch = M.BRANCHES.WEALD,
        talent = "magic_of_the_weald",
        componentId = "component_woodweave",
        targetMode = "environment_or_creature",
        effect = {
            type = "woodweave",
            controlsPlantGrowth = true,
            controlsWoodShape = true,
            modes = {
                grow = {
                    target = "living_plant",
                    growsQuickly = true,
                    appliesGrowEffect = true,
                },
                shrink = {
                    target = "living_plant",
                    withersBackToSeed = true,
                    appliesShrinkingEffect = true,
                },
                warp = {
                    target = "wooden_object",
                    notchesObject = true,
                    warpsAndReshapesWood = true,
                },
                root = {
                    requiresPlaceOfVegetation = true,
                    conjuresEntanglingVines = true,
                    rootsAllCreaturesInSingleZone = true,
                },
                shape = {
                    requiresEquivalentRawMaterials = true,
                    instantShape = true,
                    output = "wooden_object",
                },
            },
        },
    },

    darklight = {
        id = "darklight",
        name = "Darklight",
        branch = M.BRANCHES.WASTES,
        talent = "magic_of_the_wastes",
        componentId = "component_darklight",
        targetMode = "object",
        ongoing = true,
        concentration = true,
        effect = {
            type = "darklight",
            componentAction = "hold_candle_in_pickled_hand",
            heldCandleDoesNotGoOut = true,
            lightOnlyForHolder = true,
            cannotBeSeenByOthers = true,
            enablesStealthWithPerfectVisibility = true,
            ignoresTorchesGutter = true,
            extraViewerResolve = 1,
        },
    },

    fear = {
        id = "fear",
        name = "Fear",
        branch = M.BRANCHES.WASTES,
        talent = "magic_of_the_wastes",
        componentId = "component_fear",
        targetMode = "unwilling_creature",
        ongoing = true,
        concentration = true,
        effect = {
            type = "emotional_illusion",
            disposition = "fear",
            componentAction = "weave_target_only_grotesquery_illusion",
            visibleOnlyToTarget = true,
            requiresSecondWillingTarget = true,
            cloakedTargetAppearance = "terrifying_grotesquery",
            inspiresDisposition = "fear",
            fearFleeFocus = true,
            avoidCombatUnlessNecessaryToEscape = true,
            prioritizeHighInitiative = true,
            notAffectedByEmotionless = true,
            notAffectedByIllusionImmune = true,
            endsOnDispositionChange = true,
        },
    },

    augury = {
        id = "augury",
        name = "Augury",
        branch = M.BRANCHES.WELKIN,
        talent = "magic_of_the_welkin",
        componentId = "component_augury",
        targetMode = "environment",
        effect = {
            type = "augury",
            componentAction = "consult_random_codex_sophia_page",
            gmDrawsFateCard = true,
            cardHiddenFromPlayers = true,
            gmDescribesCardAsParable = true,
            noOutsideHelpForInterpretation = true,
            guildMayAttemptOrDecline = true,
            revealCardOnAttempt = true,
            canSpendResolveForFavorOnAttempt = true,
            canPushFateOnAttempt = true,
            boundByFateOnDecline = true,
            declineDiscardsCard = true,
            boundOutcomePersistsUntilSituationChanges = true,
        },
    },

    binding = {
        id = "binding",
        name = "Binding",
        branch = M.BRANCHES.WELKIN,
        talent = "magic_of_the_welkin",
        componentId = "component_binding",
        targetMode = "named_creatures",
        ongoing = true,
        concentration = true,
        effect = {
            type = "binding",
            componentAction = "hold_finger_bone_as_ward_and_name_creature",
            affectsVisibleNamedCreatures = true,
            specificNameMatchesExact = true,
            genericNameMatchesType = true,
            vagueCastingsMayCreateMaleficence = true,
            appliesRooted = true,
            rootedCannotRecover = true,
            counterOrConcentrationEndOnly = true,
        },
    },

    charm = {
        id = "charm",
        name = "Charm",
        branch = M.BRANCHES.WELKIN,
        talent = "magic_of_the_welkin",
        componentId = "component_charm",
        targetMode = "person",
        ongoing = true,
        concentration = true,
        effect = {
            type = "charm",
            componentAction = "burn_myrrh_in_ivory_censer",
            requiresSecondWillingTarget = true,
            visibleOnlyToTarget = true,
            cloakedTargetAppearance = "undefined_trusted_friend",
            inspiresDisposition = "trust",
            trustDispositionAvoidsFightInclination = true,
            nonlethalProwessTestingIfFightRequired = true,
            notAffectedByEmotionless = true,
            notAffectedByIllusionImmune = true,
            endsOnDispositionChange = true,
        },
    },

    circle_of_protection = {
        id = "circle_of_protection",
        name = "Circle of Protection",
        branch = M.BRANCHES.WELKIN,
        talent = "magic_of_the_welkin",
        componentId = "component_circle_of_protection",
        targetMode = "environment",
        ongoing = true,
        concentration = true,
        baseRealms = 1,
        extraRealmResolve = 1,
        radiusFeet = 10,
        requiresPreparedCircle = true,
        effect = {
            type = "circle_of_protection",
            preparationAction = "watch_sketch_rune_circle_with_ashes",
            componentAction = "hold_saint_ashes_in_silver_monstrance",
            empowerAction = "incant_and_select_far_realm",
            radiusFeet = 10,
            protectsAgainstFarRealmNatives = true,
            blocksNativesCrossingBoundary = true,
            blocksNativesHarmingAcrossBoundary = true,
            canTrapSpiritIfPreparedUnempowered = true,
            baseRealms = 1,
            extraRealmResolve = 1,
        },
    },

    feather = {
        id = "feather",
        name = "Feather",
        branch = M.BRANCHES.WELKIN,
        talent = "magic_of_the_welkin",
        componentId = "component_feather",
        targetMode = "creature_or_object",
        ongoing = true,
        concentration = true,
        effect = {
            type = "feather",
            componentAction = "hold_lamassu_feather",
            weightReducedTo = "feather",
            floatsGentlyToGround = true,
            quickCastFallingRequiresHeldComponent = true,
            preventsFallingDamage = true,
            preventsHazardSceneryDamage = true,
            preventsPressurePlateTrigger = true,
            heavyObjectsEasyToMove = true,
        },
    },

    guardian_angel = {
        id = "guardian_angel",
        name = "Guardian Angel",
        branch = M.BRANCHES.WELKIN,
        talent = "magic_of_the_welkin",
        componentId = "component_guardian_angel",
        targetMode = "ally",
        effect = {
            type = "guardian_angel",
            componentAction = "summon_invisible_minor_welkin_spirit",
            bindsSpiritToTarget = true,
            speakIncantationCardBecomesDefense = true,
            canDodge = true,
            canRiposte = true,
            stacksWithSameDefenseType = true,
            doesNotCountDefenseSlot = true,
            noMultipleInstances = true,
            lastsUntilUsed = true,
        },
    },

    heavenfire = {
        id = "heavenfire",
        name = "Heavenfire",
        branch = M.BRANCHES.WELKIN,
        talent = "magic_of_the_welkin",
        componentId = "component_heavenfire",
        targetMode = "creature_or_object",
        effect = {
            type = "heavenfire",
            componentAction = "summon_gout_of_heavenfire",
            brightFlameLightNoHeat = true,
            doesNotConsumeBurningObject = true,
            livingSightedBlind = true,
            challengeBlindDuration = "end_next_turn",
            undeadOrWastesSpiritPiercingDamage = true,
            objectBrightLight = true,
            canLightWandOrHat = true,
            objectExtinguishesOnTorchesGutter = true,
            actsLikeNormalFlame = true,
            extinguishableByWaterOrSuffocation = true,
        },
    },

    animate_object = {
        id = "animate_object",
        name = "Animate Object",
        branch = M.BRANCHES.WEIRD,
        talent = "magic_of_the_weird",
        componentId = "component_animate_object",
        targetMode = "object",
        ongoing = true,
        effect = {
            type = "animate_object",
            intendedPurposeOnly = true,
            invisibleHand = true,
            oneTaskPerCasting = true,
            unattendedWeaponOneStrike = true,
            actionValueFromSpeakIncantation = true,
            lastsUntilTaskFulfilled = true,
            committedResolveUntilFulfilled = true,
            wordsPerResolveUsesWands = true,
        },
    },

    change_size = {
        id = "change_size",
        name = "Change Size",
        branch = M.BRANCHES.WEIRD,
        talent = "magic_of_the_weird",
        componentId = "component_change_size",
        targetMode = "creature",
        ongoing = true,
        concentration = true,
        effect = {
            type = "change_size",
            growHeightMultiplier = 2,
            shrinkHeightMultiplier = 0.5,
            halfOrDoubleOriginalHeight = true,
            grantsFavorWhenAdvantageous = true,
            grantsDisfavorWhenDisadvantageous = true,
            attackValuesUnaffected = true,
            mayInfluenceRoughhouse = true,
        },
    },

    enrage = {
        id = "enrage",
        name = "Enrage",
        branch = M.BRANCHES.WEIRD,
        talent = "magic_of_the_weird",
        componentId = "component_enrage",
        targetMode = "unwilling_creature",
        ongoing = true,
        concentration = true,
        effect = {
            type = "emotional_illusion",
            disposition = "anger",
            visibleOnlyToTarget = true,
            requiresSecondWillingTarget = true,
            cloakedTargetAppearance = "nebulous_hated_foe",
            inspiresDisposition = "anger",
            recklessAttackFocus = true,
            notAffectedByEmotionless = true,
            notAffectedByIllusionImmune = true,
            endsOnDispositionChange = true,
        },
    },

    give_form_to_nothingness = {
        id = "give_form_to_nothingness",
        name = "Give Form to Nothingness",
        branch = M.BRANCHES.WEIRD,
        talent = "magic_of_the_weird",
        componentId = "component_give_form_to_nothingness",
        targetMode = "environment",
        ongoing = true,
        baseRooms = 1,
        extraRoomResolve = 1,
        effect = {
            type = "give_form_to_nothingness",
            componentAction = "play_rune_painted_drum",
            duration = "while_drum_played",
            requiresContinuousDrum = true,
            affectsSubjectsInRooms = true,
            affectedSubjectStates = { "intangible", "invisible" },
            makesTangible = true,
            makesVisible = true,
            restoresPreviousStateOnEnd = true,
            baseRooms = 1,
            extraRoomResolve = 1,
        },
    },

    portable_hole = {
        id = "portable_hole",
        name = "Portable Hole",
        branch = M.BRANCHES.WEIRD,
        talent = "magic_of_the_weird",
        componentId = "component_portable_hole",
        targetMode = "object",
        ongoing = true,
        concentration = true,
        effect = {
            type = "portable_hole",
            componentAction = "place_calfskin_circle_on_inanimate_material",
            calfskinCircleMaxDiameterInches = 9,
            opensThroughInanimateMaterial = true,
            windowToImmediateOtherSide = true,
            passageAllowsThingsToPass = true,
            livingTissueNoFunction = true,
            liminalLivingUnlivingGmDiscretion = true,
            noStructuralDamage = true,
            blindPocketDepthFeet = 1,
            blindPocketSwallowsItemsUndamaged = true,
            closesBackIntoComponentCircleOnEnd = true,
        },
    },

    illusion = {
        id = "illusion",
        name = "Illusion",
        branch = M.BRANCHES.WEIRD,
        talent = "magic_of_the_weird",
        componentId = "component_illusion",
        targetMode = "environment",
        ongoing = true,
        concentration = true,
        effect = {
            type = "visual_illusion",
            componentAction = "create_image_through_seven_faceted_prism",
            createsObjectOrCreatureImage = true,
            visualOnly = true,
            hologram = true,
            hasWeight = false,
            hasSubstance = false,
            hasSound = false,
            hasSmell = false,
            additiveOnly = true,
            cannotMakeExistingThingsUnseen = true,
            mentalCommands = true,
            challengeCommandRequiresMiscAction = true,
            detailResolveCost = 1,
        },
    },

    mirror_meld = {
        id = "mirror_meld",
        name = "Mirror Meld",
        branch = M.BRANCHES.WEIRD,
        talent = "magic_of_the_weird",
        componentId = "component_mirror_meld",
        targetMode = "object",
        ongoing = true,
        effect = {
            type = "mirror_meld",
            componentAction = "sprinkle_tears_on_mirror_surface",
            createsMirrorPortal = true,
            allowsCreatures = true,
            allowsItems = true,
            allowsMultipleCreatures = true,
            entrantsBecomeReflection = true,
            visibleOnlyInsideMirror = true,
            canSeeHearNearMirror = true,
            cannotInteractWithWorld = true,
            requiresMirrorLargeEnough = true,
            exitsAtWill = true,
            itemsVisibleButIntangibleFromOutside = true,
            carriedItemsKeepPackWeight = true,
            brokenMirrorCreatureWounds = 2,
            brokenMirrorDestroysItems = true,
            persistsUntilCreaturesLeaveOrMirrorBroken = true,
        },
    },

    sleep = {
        id = "sleep",
        name = "Sleep",
        branch = M.BRANCHES.WEIRD,
        talent = "magic_of_the_weird",
        componentId = "component_sleep",
        targetMode = "unwilling_creature",
        effect = {
            type = "sleep",
            componentAction = "blow_powder_toward_target",
            peacefulEffect = "knockout",
            peacefulWakeMethod = "sharp_slap",
            dangerousEffect = "stunned_drowsy",
            longSleepResolve = 4,
            longSleepNoAging = true,
            longSleepNoFoodRequired = true,
        },
    },

    shroud = {
        id = "shroud",
        name = "Shroud",
        branch = M.BRANCHES.WEIRD,
        talent = "magic_of_the_weird",
        componentId = "component_shroud",
        targetMode = "creature",
        ongoing = true,
        concentration = true,
        effect = {
            type = "shroud",
            componentAction = "spread_funeral_winding_sheet_over_target",
            coversTargetAndCarriedGear = true,
            impossibleToSeeWithoutMagicOrSpecialSenses = true,
            stillAndQuietCannotBeDeliberatelyTargeted = true,
            movementCreatesVaguePresence = true,
            targetingVaguePresenceDisfavor = true,
            harmfulActionsGainFavorAgainstUnseeing = true,
            visibleObjectInteractionRequiresResolve = true,
        },
    },

    scry = {
        id = "scry",
        name = "Scry",
        branch = M.BRANCHES.WEIRD,
        talent = "magic_of_the_weird",
        componentId = "component_scry",
        targetMode = "environment",
        ongoing = true,
        concentration = true,
        effect = {
            type = "scry",
            componentAction = "peer_into_crystal_ball",
            visitedLocationOnly = true,
            defaultSameMetaphysicalAreaOnly = true,
            outsideAreaExtraResolve = 1,
            canSeeLocation = true,
        },
    },

    stinking_cloud = {
        id = "stinking_cloud",
        name = "Stinking Cloud",
        branch = M.BRANCHES.WASTES,
        talent = "magic_of_the_wastes",
        componentId = "component_stinking_cloud",
        targetMode = "environment",
        ongoing = true,
        concentration = true,
        effect = {
            type = "stinking_cloud",
            miasma = "thousand_opened_coffins",
            expelledFrom = "sorcerer_mouth",
            zonesPerResolve = 1,
            breathingImmunity = true,
        },
    },

    withering = {
        id = "withering",
        name = "Withering",
        branch = M.BRANCHES.WASTES,
        talent = "magic_of_the_wastes",
        componentId = "component_withering",
        targetMode = "unwilling_creature_or_object",
        effect = {
            type = "withering",
            componentAction = "invoke_decay_from_rune_etched_fingernails",
            livingCreatureWounds = 1,
            livingAgingSigns = {
                "grey_hair",
                "wrinkled_skin",
                "jaundiced_eyes",
                "liver_spots",
            },
            agingLastsUntilWoundHealed = true,
            undeadNotHarmed = true,
            undeadBecomesMoreTerrible = true,
            zombieTransformsTo = "skeleton",
            skeletonTransformsTo = "wraith",
            objectShowsDecay = true,
            objectDecayByMaterial = {
                food = "rotten",
                chains = "rusted",
                wood = "moldy",
                stone = "unaffected",
            },
            objectTakesNotch = true,
            destroyedAtResolve = 2,
        },
    },

    life = {
        id = "life",
        name = "Life",
        branch = M.BRANCHES.WELKIN,
        talent = "magic_of_the_welkin",
        componentId = "component_life",
        targetMode = "creature",
        multiTarget = true,
        effect = {
            type = "life",
            componentAction = "touch_with_phoenix_feather",
            noEffectOnHealthyLiving = true,
            clearsDeathsDoor = true,
            deathsDoorTargetBecomesStressed = true,
            reducesAfflictionStage = true,
            removesFirstStageAffliction = true,
            undeadTakesWound = true,
            plantGrowsQuickly = true,
            extraTargetResolve = 1,
        },
    },

    veritas = {
        id = "veritas",
        name = "Veritas",
        branch = M.BRANCHES.WELKIN,
        talent = "magic_of_the_welkin",
        componentId = "component_veritas",
        targetMode = "person",
        ongoing = true,
        concentration = true,
        effect = {
            type = "veritas",
            componentAction = "administer_sacramental_wine",
            personOnly = true,
            casterKnowsKnowinglySpokenLies = true,
            targetUnderstandsMagicalPolygraph = true,
        },
    },

    seal_pact = {
        id = "seal_pact",
        name = "Seal Pact",
        branch = M.BRANCHES.WELKIN,
        talent = "magic_of_the_welkin",
        componentId = "component_seal_pact",
        targetMode = "willing_parties",
        baseParties = 2,
        extraPartyResolve = 1,
        effect = {
            type = "seal_pact",
            componentAction = "seal_contract_with_goblin_teeth_and_finger_joints",
            willingPartiesOnly = true,
            baseParties = 2,
            extraPartyResolve = 1,
            permanentUnlessDispelled = true,
            violationAlertsOtherParties = true,
            violatorDoomedForFutureGreatFailure = true,
            dispelTriggersAwarenessButNotDoom = true,
            violatedConsequencesIrremovable = true,
        },
    },
}

M.TOTEM_CHART = {
    [constants.SUITS.SWORDS] = {
        [1] = "Ape",
        [2] = "Armadillo",
        [3] = "Badger",
        [4] = "Bat",
        [5] = "Bear",
        [6] = "Cat",
        [7] = "Cattle",
        [8] = "Crab",
        [9] = "Crocodile",
        [10] = "Deer",
        [11] = "Dog",
        [12] = "Eagle",
        [13] = "Elk",
        [14] = "Fox",
    },
    [constants.SUITS.PENTACLES] = {
        [1] = "Frog",
        [2] = "Goat",
        [3] = "Hedgehog",
        [4] = "Hog",
        [5] = "Hyena",
        [6] = "Jackdaw",
        [7] = "Kangaroo",
        [8] = "Leopard",
        [9] = "Lion",
        [10] = "Mouse",
        [11] = "Mule",
        [12] = "Opossum",
        [13] = "Otter",
        [14] = "Owl",
    },
    [constants.SUITS.CUPS] = {
        [1] = "Rat",
        [2] = "Pelican",
        [3] = "Peacock",
        [4] = "Rabbit",
        [5] = "Raccoon",
        [6] = "Seal",
        [7] = "Snake",
        [8] = "Stoat",
        [9] = "Swan",
        [10] = "Tiger",
        [11] = "Turtle",
        [12] = "Vulture",
        [13] = "Walrus",
        [14] = "Wolf",
    },
    [constants.SUITS.WANDS] = {
        [1] = "Bonnacon",
        [2] = "Capricorn",
        [3] = "Dire Centipede",
        [4] = "Coatl",
        [5] = "Dire Grasshopper",
        [6] = "Griffin",
        [7] = "Hippogriff",
        [8] = "Mammoth",
        [9] = "Owlbear",
        [10] = "Dire Rat",
        [11] = "Roc",
        [12] = "Dire Snail",
        [13] = "Dire Spider",
        [14] = "Thunder Lizard",
    },
}

M.MALEDICTION_CURSES = {
    [1] = {
        rank = "I",
        id = "dogs_hate_you",
        name = "Dogs Hate You",
        flags = {
            dogsHateYou = true,
            dogAttackPriority = true,
            cityPhaseDogCurse = true,
        },
        metadata = {
            cityPhaseConditionChance = {
                staggered = 0.5,
                stressed = 0.5,
            },
        },
    },
    [2] = {
        rank = "II",
        id = "bad_dreams",
        name = "Bad Dreams",
        flags = {
            badDreams = true,
        },
        metadata = {
            wakeStressedChance = 0.5,
        },
    },
    [3] = {
        rank = "III",
        id = "ash_food",
        name = "Ash Food",
        flags = {
            foodMayTurnToAsh = true,
        },
        metadata = {
            rationAshChance = 0.5,
        },
    },
    [4] = {
        rank = "IV",
        id = "doomed",
        name = "Doomed",
        conditions = {
            exhausted = true,
        },
        nonRecoverableConditions = {
            exhausted = "malediction",
        },
        flags = {
            doomedByMalediction = true,
        },
    },
    [5] = {
        rank = "V",
        id = "desiccated_corpse",
        name = "Desiccated Corpse",
        flags = {
            appearsAsDesiccatedCorpse = true,
            gmCharactersUsuallyHostile = true,
            undeadUsuallyIgnore = true,
            intimacyUsuallyRejected = true,
            nobodyWantsToSleepWithYou = true,
        },
        metadata = {
            appearance = "desiccated_corpse",
            usualGmCharacterReaction = "hostile",
            usualUndeadReaction = "ignore",
            usualIntimacyReaction = "rejected",
        },
    },
    [6] = {
        rank = "VI",
        id = "speak_in_rhymes",
        name = "Speak in Rhymes",
        flags = {
            mustSpeakInRhymes = true,
        },
    },
    [7] = {
        rank = "VII",
        id = "rusting_weapons",
        name = "Rusting Weapons",
        flags = {
            weaponRustMalediction = true,
            maledictionWeaponNotchThreshold = 10,
        },
        metadata = {
            cardThreshold = 10,
            woodNotchCapacity = 1,
            ironNotchCapacity = 2,
            steelNotchCapacity = 3,
        },
    },
    [8] = {
        rank = "VIII",
        id = "changed_anatomy",
        name = "Changed Anatomy",
        flags = {
            sexualAnatomyChanged = true,
        },
    },
    [9] = {
        rank = "IX",
        id = "beloved_by_vermin",
        name = "Beloved by Vermin",
        flags = {
            verminFollow = true,
            verminWantToSleepInMouth = true,
            verminKnowUnwantedPackItems = true,
            verminReplaceWithNiceGarbage = true,
        },
        metadata = {
            nightlyPackSwapChance = 0.5,
            stolenItemSelection = "known_unwanted_pack_item",
            replacement = "nice_garbage",
        },
    },
    [10] = {
        rank = "X",
        id = "shame_bell",
        name = "Shame Bell",
        flags = {
            stealthImpossible = true,
            shameBellFootsteps = true,
        },
    },
    [11] = {
        rank = "Page",
        id = "sick_and_infirm",
        name = "Sick and Infirm",
        conditions = {
            infirm = true,
        },
        flags = {
            maledictionExtraBondRecoveryCost = true,
            immuneToHeal = true,
            immuneToHealEffect = true,
        },
    },
    [12] = {
        rank = "Knight",
        id = "old_crone",
        name = "Old Crone",
        flags = {
            sightRangeFeet = 30,
            cannotDash = true,
            oldForCurse = true,
            uglyAndUnattractive = true,
            cataracts = true,
        },
        metadata = {
            apparentAge = "withered_crone",
            sightCause = "cataracts",
        },
    },
    [13] = {
        rank = "Queen",
        id = "tylwyth_only",
        name = "Tylwyth Only",
        flags = {
            languageLocked = "tylwyth",
            speaksGibberishToNonTylwyth = true,
        },
    },
    [14] = {
        rank = "King",
        id = "chicken_doom",
        name = "Chicken Doom",
        flags = {
            stressChickenTest = true,
        },
    },
}

local function normalize(value)
    value = tostring(value or ""):lower()
    value = value:gsub("[’']", "")
    value = value:gsub("%s+", "_")
    value = value:gsub("[^%w_]", "")
    return value
end

function M.normalizeId(value)
    return normalize(value)
end

function M.getSpell(spellRef)
    if type(spellRef) == "table" then
        return spellRef
    end

    local id = normalize(spellRef)
    return M.spells[id]
end

function M.getTotemForCard(card)
    if not card then
        return nil
    end

    local suitChart = M.TOTEM_CHART[card.suit]
    return suitChart and suitChart[card.value] or nil
end

function M.getMaledictionCurseForCard(card)
    if not card or card.is_major then
        return nil
    end

    local value = math.floor(tonumber(card.value) or 0)
    return M.MALEDICTION_CURSES[value]
end

function M.listSpells()
    local spells = {}
    for _, spell in pairs(M.spells) do
        spells[#spells + 1] = spell
    end
    table.sort(spells, function(a, b)
        return a.name < b.name
    end)
    return spells
end

return M
