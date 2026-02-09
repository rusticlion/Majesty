-- bootstrap.lua
-- Application bootstrap for Majesty:
-- builds core systems, challenge systems, UI systems, and event wiring.

local constants = require('constants')

local deck = require('logic.deck')
local game_clock = require('logic.game_clock')
local watch_manager = require('logic.watch_manager')
local room_manager = require('logic.room_manager')
local events = require('logic.events')
local light_system = require('logic.light_system')
local environment_manager = require('logic.environment_manager')

local challenge_controller = require('logic.challenge_controller')
local action_resolver = require('logic.action_resolver')
local npc_ai = require('logic.npc_ai')
local challenge_input_controller = require('controllers.challenge_input_controller')
local key_input_router = require('controllers.key_input_router')
local mouse_input_router = require('controllers.mouse_input_router')

local action_sequencer = require('ui.action_sequencer')
local wound_walk = require('ui.wound_walk')
local player_hand = require('ui.player_hand')
local combat_display = require('ui.combat_display')
local inspect_panel = require('ui.inspect_panel')
local arena_view = require('ui.arena_view')
local challenge_overlay = require('ui.challenge_overlay')
local layout_manager = require('ui.layout_manager')
local command_board = require('ui.command_board')
local minor_action_panel = require('ui.minor_action_panel')
local floating_text = require('ui.floating_text')
local sound_manager = require('ui.sound_manager')
local test_of_fate_modal = require('ui.test_of_fate_modal')
local character_sheet = require('ui.screens.character_sheet')
local loot_modal = require('ui.loot_modal')
local crawl_screen = require('ui.screens.crawl_screen')

local dungeon_graph = require('world.dungeon_graph')
local zone_system = require('world.zone_system')

local tomb_data = require('data.maps.tomb_of_golden_ghosts')

local M = {}

function M.initialize(config)
    config = config or {}

    local gameState = assert(config.gameState, "bootstrap.initialize requires gameState")
    local combatInputState = assert(config.combatInputState, "bootstrap.initialize requires combatInputState")

    local callbacks = config.callbacks or {}
    local createGuild = assert(callbacks.createGuild, "bootstrap.initialize requires callbacks.createGuild")
    local checkVictoryCondition = assert(callbacks.checkVictoryCondition, "bootstrap.initialize requires callbacks.checkVictoryCondition")
    local handlePhaseChange = assert(callbacks.handlePhaseChange, "bootstrap.initialize requires callbacks.handlePhaseChange")
    local triggerRandomEncounter = assert(callbacks.triggerRandomEncounter, "bootstrap.initialize requires callbacks.triggerRandomEncounter")
    local showEndOfDemoScreen = assert(callbacks.showEndOfDemoScreen, "bootstrap.initialize requires callbacks.showEndOfDemoScreen")

    -- Set up window
    love.window.setTitle("Majesty - Tomb of Golden Ghosts")
    love.window.setMode(1280, 800, {
        resizable = true,
        minwidth = 800,
        minheight = 600,
    })

    -- Initialize random seed (module-level function)
    game_clock.init()

    -- Create decks
    gameState.gmDeck = deck.createGMDeck(constants)
    gameState.playerDeck = deck.createPlayerDeck(constants)

    -- Create game clock with deck references
    gameState.gameClock = game_clock.createGameClock(gameState.playerDeck, gameState.gmDeck)
    -- Track The Fool draws for reshuffle logic
    if gameState.gameClock and gameState.gameClock.onCardDrawn then
        gameState.playerDeck.onDraw = function(card) gameState.gameClock:onCardDrawn(card) end
        gameState.gmDeck.onDraw = function(card) gameState.gameClock:onCardDrawn(card) end
    end

    -- Load dungeon
    gameState.dungeon = dungeon_graph.loadFromData(tomb_data.data)

    -- Create room manager
    gameState.roomManager = room_manager.createRoomManager({
        eventBus = gameState.eventBus,
    })

    -- Register rooms from dungeon into room manager
    for _, roomData in ipairs(tomb_data.data.rooms) do
        local roomInstance = room_manager.createRoomInstance(roomData, roomData.id)
        gameState.roomManager:registerRoom(roomInstance)
    end

    -- Create the guild (4 adventurers)
    createGuild()

    -- Create watch manager
    gameState.watchManager = watch_manager.createWatchManager({
        gameClock    = gameState.gameClock,
        gmDeck       = gameState.gmDeck,
        dungeon      = gameState.dungeon,
        guild        = gameState.guild,
        eventBus     = gameState.eventBus,
        startingRoom = "101_entrance",
    })

    -- Create light system
    gameState.lightSystem = light_system.createLightSystem({
        eventBus = gameState.eventBus,
        guild    = gameState.guild,
    })
    gameState.lightSystem:init()

    -- Create environment manager
    gameState.environmentManager = environment_manager.createEnvironmentManager({
        eventBus = gameState.eventBus,
        guild    = gameState.guild,
    })
    gameState.environmentManager:init()

    -- S12.1: Create zone registry for engagement tracking
    gameState.zoneRegistry = zone_system.createZoneRegistry({
        eventBus = gameState.eventBus,
    })

    -- Create challenge systems
    gameState.actionResolver = action_resolver.createActionResolver({
        eventBus   = gameState.eventBus,
        zoneSystem = gameState.zoneRegistry,
    })

    gameState.challengeController = challenge_controller.createChallengeController({
        eventBus   = gameState.eventBus,
        playerDeck = gameState.playerDeck,
        gmDeck     = gameState.gmDeck,
        gameClock  = gameState.gameClock,
        guild      = gameState.guild,
        zoneSystem = gameState.zoneRegistry,
    })
    gameState.challengeController:init()
    gameState.actionResolver.challengeController = gameState.challengeController

    gameState.actionSequencer = action_sequencer.createActionSequencer({
        eventBus = gameState.eventBus,
    })
    gameState.actionSequencer:init()

    gameState.npcAI = npc_ai.createNPCAI({
        eventBus            = gameState.eventBus,
        challengeController = gameState.challengeController,
        actionResolver      = gameState.actionResolver,
        gmDeck              = gameState.gmDeck,
        zoneSystem          = gameState.zoneRegistry,
    })
    gameState.npcAI:init()

    gameState.woundWalk = wound_walk.createWoundWalk({
        eventBus = gameState.eventBus,
    })
    gameState.woundWalk:init()

    gameState.playerHand = player_hand.createPlayerHand({
        eventBus = gameState.eventBus,
        playerDeck = gameState.playerDeck,
        guild = gameState.guild,
    })
    gameState.playerHand:init()

    gameState.combatDisplay = combat_display.createCombatDisplay({
        eventBus = gameState.eventBus,
        challengeController = gameState.challengeController,
    })
    gameState.combatDisplay:init()

    gameState.inspectPanel = inspect_panel.createInspectPanel({
        eventBus = gameState.eventBus,
    })
    gameState.inspectPanel:init()

    gameState.layoutManager = layout_manager.createLayoutManager({
        eventBus = gameState.eventBus,
        leftRailWidth = crawl_screen.LAYOUT.LEFT_RAIL_WIDTH,
        rightRailWidth = crawl_screen.LAYOUT.RIGHT_RAIL_WIDTH,
        padding = crawl_screen.LAYOUT.PADDING,
        headerHeight = crawl_screen.LAYOUT.HEADER_HEIGHT,
        bottomReserve = 200,
        equipmentBarOffset = 80,
    })
    gameState.layoutManager:init()
    if love then
        local lw, lh = love.graphics.getDimensions()
        gameState.layoutManager:resize(lw, lh)
    end
    gameState.layoutManager:setStage(gameState.phase, true)

    local w, h = love.graphics.getDimensions()
    gameState.arenaView = arena_view.createArenaView({
        eventBus = gameState.eventBus,
        x = 210,
        y = 90,
        width = w - 430,
        height = h - 250,
        inspectPanel = gameState.inspectPanel,
        zoneSystem = gameState.zoneRegistry,
    })
    gameState.arenaView:init()

    if gameState.layoutManager then
        gameState.layoutManager:register("arena_view", gameState.arenaView, {
            apply = function(arena, layout)
                if layout.x and layout.y then
                    if arena.x ~= layout.x or arena.y ~= layout.y then
                        arena:setPosition(layout.x, layout.y)
                    end
                end
                if layout.width and layout.height then
                    if arena.width ~= layout.width or arena.height ~= layout.height then
                        arena:resize(layout.width, layout.height)
                    end
                end
                arena.alpha = layout.alpha or 1
                arena.isVisible = layout.visible
            end,
        })
    end

    gameState.commandBoard = command_board.createCommandBoard({
        eventBus = gameState.eventBus,
        challengeController = gameState.challengeController,
    })
    gameState.commandBoard:init()

    gameState.minorActionPanel = minor_action_panel.createMinorActionPanel({
        eventBus = gameState.eventBus,
        challengeController = gameState.challengeController,
    })
    gameState.minorActionPanel:init()

    gameState.challengeOverlay = challenge_overlay.createChallengeOverlay({
        gameState = gameState,
        inputState = combatInputState,
    })

    sound_manager.init()

    gameState.characterSheet = character_sheet.createCharacterSheet({
        eventBus = gameState.eventBus,
        guild = gameState.guild,
    })

    gameState.lootModal = loot_modal.createLootModal({
        eventBus = gameState.eventBus,
        guild = gameState.guild,
        roomManager = gameState.roomManager,
    })

    gameState.testOfFateModal = test_of_fate_modal.createTestOfFateModal({
        eventBus = gameState.eventBus,
        deck = gameState.playerDeck,
    })
    gameState.testOfFateModal:init()

    gameState.eventBus:on(events.EVENTS.CHALLENGE_ACTION, function(data)
        local result = gameState.actionResolver:resolve(data)
        if result and result.pendingTestOfFate then
            gameState.pendingTestAction = data
            return
        end
        gameState.challengeController:resolveAction(data)
    end)

    gameState.eventBus:on(events.EVENTS.TEST_OF_FATE_COMPLETE, function(data)
        if not gameState.pendingTestAction then
            return
        end

        local action = gameState.pendingTestAction
        gameState.pendingTestAction = nil

        gameState.actionResolver:resolveTestOfFateOutcome(action, data.result)
        gameState.challengeController:resolveAction(action)
    end)

    gameState.challengeInputController = challenge_input_controller.createChallengeInputController({
        gameState = gameState,
        eventBus = gameState.eventBus,
        inputState = combatInputState,
    })
    gameState.challengeInputController:init()

    gameState.mouseInputRouter = mouse_input_router.createMouseInputRouter({
        gameState = gameState,
    })

    gameState.keyInputRouter = key_input_router.createKeyInputRouter({
        gameState = gameState,
        showEndOfDemoScreen = showEndOfDemoScreen,
        challengeVictoryOutcome = challenge_controller.OUTCOMES.VICTORY,
    })

    gameState.currentScreen = crawl_screen.createCrawlScreen({
        eventBus     = gameState.eventBus,
        roomManager  = gameState.roomManager,
        watchManager = gameState.watchManager,
        gameState    = gameState,
        layoutManager = gameState.layoutManager,
    })
    gameState.currentScreen:init()
    gameState.currentScreen:setGuild(gameState.guild)

    gameState.eventBus:on(events.EVENTS.INVESTIGATION_COMPLETE, function(data)
        checkVictoryCondition(data)
    end)

    gameState.eventBus:on(events.EVENTS.PHASE_CHANGED, function(data)
        handlePhaseChange(data)
    end)

    gameState.eventBus:on(events.EVENTS.RANDOM_ENCOUNTER, function(data)
        if gameState.phase == "crawl" and not gameState.challengeController:isActive() then
            print("[ENCOUNTER] Random encounter triggered! Card value: " .. data.value)
            triggerRandomEncounter(data)
        end
    end)

    gameState.eventBus:on(events.EVENTS.WOUND_TAKEN, function(data)
        local entity = data.entity
        local result = data.result

        local x = entity._tokenX or (love.graphics.getWidth() / 2)
        local y = entity._tokenY or (love.graphics.getHeight() / 2)

        if result == "armor_notched" then
            floating_text.spawnBlock(x, y)
            sound_manager.playCombatMiss(true)
        elseif result == "staggered" then
            floating_text.spawnDamage(1, x, y, false)
            floating_text.spawnCondition("Staggered", x, y - 20)
            sound_manager.playCombatHit(nil, false)
            sound_manager.playConditionSound("staggered")
        elseif result == "injured" then
            floating_text.spawnDamage(1, x, y, false)
            floating_text.spawnCondition("Injured", x, y - 20)
            sound_manager.playCombatHit(nil, false)
            sound_manager.playConditionSound("injured")
        elseif result == "deaths_door" then
            floating_text.spawnDamage(1, x, y, true)
            floating_text.spawnCondition("Death's Door!", x, y - 20)
            sound_manager.playCombatHit(nil, true)
            sound_manager.playConditionSound("deaths_door")
        elseif result == "dead" then
            floating_text.spawnDamage(1, x, y, true)
            floating_text.spawnCondition("DEFEATED", x, y - 20)
            sound_manager.playConditionSound("dead")
        else
            floating_text.spawnDamage(1, x, y, false)
            sound_manager.playCombatHit(nil, false)
        end
    end)

    gameState.eventBus:on(events.EVENTS.CHALLENGE_ACTION, function(_)
        sound_manager.playCardSound("play")
    end)

    gameState.eventBus:on(events.EVENTS.CHALLENGE_START, function(_)
        local oldPhase = gameState.phase
        gameState.phase = "challenge"
        gameState.eventBus:emit(events.EVENTS.PHASE_CHANGED, {
            oldPhase = oldPhase,
            newPhase = "challenge",
        })
        sound_manager.play(sound_manager.SOUNDS.ROUND_START)
        sound_manager.playMusic(sound_manager.SOUNDS.COMBAT_MUSIC)
    end)

    gameState.eventBus:on(events.EVENTS.CHALLENGE_END, function(data)
        local oldPhase = gameState.phase
        gameState.phase = "crawl"
        gameState.eventBus:emit(events.EVENTS.PHASE_CHANGED, {
            oldPhase = oldPhase,
            newPhase = "crawl",
        })
        gameState.pendingTestAction = nil
        if gameState.testOfFateModal then
            gameState.testOfFateModal:hide()
        end
        sound_manager.stopMusic()
        if data.victory then
            sound_manager.play(sound_manager.SOUNDS.VICTORY)
        end
    end)

    gameState.currentScreen:enterRoom("101_entrance")

    print("=== Majesty Vertical Slice Loaded ===")
    print("Tomb of Golden Ghosts - 5 rooms")
    print("Guild size: " .. #gameState.guild)
    print("GM Deck: " .. gameState.gmDeck:totalCards() .. " cards")
    print("Player Deck: " .. gameState.playerDeck:totalCards() .. " cards")
end

return M
