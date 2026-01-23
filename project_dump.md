# Project Source Dump

- Root: /Users/russellbates/JunkDrawer/HMTW/Majesty
- Generated: 2026-01-22T20:29:23Z

---

## File: main.lua

```lua
-- main.lua
-- Majesty - The Vertical Slice
-- Ticket T3_4: Wire up the Tomb of Golden Ghosts to the UI
--
-- This file initializes all systems and launches the Crawl Screen.

-- Add src to the require path
package.path = package.path .. ";src/?.lua;src/?/init.lua"

--------------------------------------------------------------------------------
-- REQUIRE MODULES
--------------------------------------------------------------------------------

-- Core constants
local constants = require('constants')

-- Logic systems
local deck = require('logic.deck')
local game_clock = require('logic.game_clock')
local watch_manager = require('logic.watch_manager')
local room_manager = require('logic.room_manager')
local events = require('logic.events')
local light_system = require('logic.light_system')
local environment_manager = require('logic.environment_manager')
local inventory = require('logic.inventory')

-- Challenge systems (Sprint 4)
local challenge_controller = require('logic.challenge_controller')
local action_resolver = require('logic.action_resolver')
local npc_ai = require('logic.npc_ai')

-- UI systems
local action_sequencer = require('ui.action_sequencer')
local wound_walk = require('ui.wound_walk')
local player_hand = require('ui.player_hand')
local combat_display = require('ui.combat_display')
local inspect_panel = require('ui.inspect_panel')
local arena_view = require('ui.arena_view')
local command_board = require('ui.command_board')
local minor_action_panel = require('ui.minor_action_panel')
local floating_text = require('ui.floating_text')
local sound_manager = require('ui.sound_manager')

-- World systems
local dungeon_graph = require('world.dungeon_graph')

-- Entity systems
local adventurer = require('entities.adventurer')

-- Map data
local tomb_data = require('data.maps.tomb_of_golden_ghosts')

-- UI Screens
local crawl_screen = require('ui.screens.crawl_screen')
local camp_screen = require('ui.screens.camp_screen')
local end_of_demo_screen = require('ui.screens.end_of_demo_screen')
local character_sheet = require('ui.screens.character_sheet')
local loot_modal = require('ui.loot_modal')

-- Camp system (Sprint 8-9)
local camp_controller = require('logic.camp_controller')

--------------------------------------------------------------------------------
-- GAME STATE
--------------------------------------------------------------------------------

local gameState = {
    -- Core systems (initialized in love.load)
    gameClock         = nil,
    gmDeck            = nil,
    playerDeck        = nil,
    dungeon           = nil,
    roomManager       = nil,
    watchManager      = nil,
    lightSystem       = nil,
    environmentManager = nil,

    -- Challenge systems (Sprint 4)
    challengeController = nil,
    actionResolver      = nil,
    actionSequencer     = nil,
    npcAI               = nil,
    woundWalk           = nil,
    playerHand          = nil,
    combatDisplay       = nil,  -- S5.3: Defense slots & initiative visualization
    inspectPanel        = nil,  -- S5.4: Inspect context overlay
    arenaView           = nil,  -- S6.1: Arena tactical schematic
    commandBoard        = nil,  -- S6.2: Categorized command board
    minorActionPanel    = nil,  -- S6.4: Minor action declaration panel

    -- Camp systems (Sprint 8-9)
    campController      = nil,
    campScreen          = nil,

    -- S11.1: Character sheet modal
    characterSheet      = nil,

    -- S11.3: Loot modal
    lootModal           = nil,

    -- Party
    guild             = {},    -- Array of adventurer entities

    -- Current screen
    currentScreen     = nil,

    -- Event bus
    eventBus          = events.globalBus,

    -- Game phase
    phase             = "crawl",  -- "crawl", "challenge", "camp", "town"

    -- Victory condition tracking
    vellumMapFound    = false,
}

-- Combat input state (for multi-step selection flow)
-- Defined here so it's accessible from event listeners in love.load
local combatInputState = {
    selectedCard = nil,
    selectedCardIndex = nil,
    selectedEntity = nil,      -- The PC making the action
    selectedAction = nil,      -- Action chosen from command board
    awaitingTarget = false,    -- True when waiting for target selection
    awaitingZone = false,      -- True when waiting for zone selection (Move action)
    availableZones = nil,      -- Array of zones player can move to
    minorPC = nil,             -- PC selected for minor action (1-4 keys)
}

--- Reset combat input state
local function resetCombatInputState()
    combatInputState.selectedCard = nil
    combatInputState.selectedCardIndex = nil
    combatInputState.selectedEntity = nil
    combatInputState.selectedAction = nil
    combatInputState.awaitingTarget = false
    combatInputState.awaitingZone = false
    combatInputState.availableZones = nil
    combatInputState.minorPC = nil
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

function love.load()
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

    -- Create challenge systems (Sprint 4)
    gameState.actionResolver = action_resolver.createActionResolver({
        eventBus = gameState.eventBus,
    })

    gameState.challengeController = challenge_controller.createChallengeController({
        eventBus   = gameState.eventBus,
        playerDeck = gameState.playerDeck,
        gmDeck     = gameState.gmDeck,
        guild      = gameState.guild,
    })
    gameState.challengeController:init()

    gameState.actionSequencer = action_sequencer.createActionSequencer({
        eventBus = gameState.eventBus,
    })
    gameState.actionSequencer:init()

    gameState.npcAI = npc_ai.createNPCAI({
        eventBus            = gameState.eventBus,
        challengeController = gameState.challengeController,
        actionResolver      = gameState.actionResolver,
        gmDeck              = gameState.gmDeck,
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

    -- S5.3: Combat display for defense slots and initiative visualization
    gameState.combatDisplay = combat_display.createCombatDisplay({
        eventBus = gameState.eventBus,
        challengeController = gameState.challengeController,
    })
    gameState.combatDisplay:init()

    -- S5.4: Inspect context overlay
    gameState.inspectPanel = inspect_panel.createInspectPanel({
        eventBus = gameState.eventBus,
    })
    gameState.inspectPanel:init()

    -- S6.1: Arena view for tactical combat visualization
    local w, h = love.graphics.getDimensions()
    gameState.arenaView = arena_view.createArenaView({
        eventBus = gameState.eventBus,
        x = 210,  -- After left rail
        y = 90,   -- Below header
        width = w - 430,  -- Leave room for right rail
        height = h - 250, -- Leave room for hand display
    })
    gameState.arenaView:init()

    -- S6.2: Command board for action selection
    gameState.commandBoard = command_board.createCommandBoard({
        eventBus = gameState.eventBus,
        challengeController = gameState.challengeController,
    })
    gameState.commandBoard:init()

    -- S6.4: Minor action panel for declaration loop
    gameState.minorActionPanel = minor_action_panel.createMinorActionPanel({
        eventBus = gameState.eventBus,
        challengeController = gameState.challengeController,
    })
    gameState.minorActionPanel:init()

    -- S10.2: Initialize sound manager
    sound_manager.init()

    -- S11.1: Create character sheet modal
    gameState.characterSheet = character_sheet.createCharacterSheet({
        eventBus = gameState.eventBus,
        guild = gameState.guild,
    })

    -- S11.3: Create loot modal
    gameState.lootModal = loot_modal.createLootModal({
        eventBus = gameState.eventBus,
        guild = gameState.guild,
        roomManager = gameState.roomManager,
    })

    -- Wire up challenge action resolution
    gameState.eventBus:on(events.EVENTS.CHALLENGE_ACTION, function(data)
        local result = gameState.actionResolver:resolve(data)
        gameState.challengeController:resolveAction(data)
    end)

    -- Wire up action selection from command board
    gameState.eventBus:on("action_selected", function(data)
        -- Store the selected action
        combatInputState.selectedAction = data.action

        -- Check if this is a Move action - needs zone selection
        if data.action.id == "move" or data.action.id == "dash" then
            -- Get available zones from challenge controller
            local controller = gameState.challengeController
            local zones = controller.zones or {}
            local currentZone = combatInputState.selectedEntity and combatInputState.selectedEntity.zone

            -- Filter to only adjacent/different zones
            local availableZones = {}
            for _, zone in ipairs(zones) do
                if zone.id ~= currentZone then
                    availableZones[#availableZones + 1] = zone
                end
            end

            if #availableZones > 0 then
                combatInputState.awaitingZone = true
                combatInputState.availableZones = availableZones

                print("[COMBAT] Select destination zone (1-" .. #availableZones .. "):")
                for i, z in ipairs(availableZones) do
                    print("  " .. i .. ": " .. z.name)
                end
            else
                print("[COMBAT] No other zones to move to!")
                resetCombatInputState()
                gameState.eventBus:emit("card_deselected", {})
            end
            return
        end

        -- Check if action requires a target
        if data.action.requiresTarget then
            -- Start target selection
            combatInputState.awaitingTarget = true

            -- Show available targets
            local controller = gameState.challengeController
            local targets = {}
            local targetType = data.action.targetType or "enemy"
            local actorZone = combatInputState.selectedEntity and combatInputState.selectedEntity.zone

            -- Check if this is a melee action (requires same zone)
            local isMelee = (data.action.id == "melee" or data.action.id == "grapple" or
                            data.action.id == "trip" or data.action.id == "disarm" or
                            data.action.id == "displace")

            if targetType == "enemy" or targetType == "any" then
                for i, npc in ipairs(controller.npcs or {}) do
                    if not (npc.conditions and npc.conditions.dead) then
                        -- For melee, only include targets in same zone
                        if isMelee then
                            if npc.zone == actorZone then
                                targets[#targets + 1] = npc
                            end
                        else
                            targets[#targets + 1] = npc
                        end
                    end
                end
            end
            if targetType == "ally" or targetType == "any" then
                for i, pc in ipairs(controller.pcs or {}) do
                    if not (pc.conditions and pc.conditions.dead) then
                        -- For melee, only include targets in same zone
                        if isMelee then
                            if pc.zone == actorZone then
                                targets[#targets + 1] = pc
                            end
                        else
                            targets[#targets + 1] = pc
                        end
                    end
                end
            end

            -- Check if we have valid targets
            if #targets == 0 then
                if isMelee then
                    print("[COMBAT] No enemies in your zone! Use Move to get closer.")
                else
                    print("[COMBAT] No valid targets available!")
                end
                combatInputState.awaitingTarget = false
                resetCombatInputState()
                gameState.eventBus:emit("card_deselected", {})
                return
            end

            print("[COMBAT] Select target (1-" .. #targets .. "):")
            for i, t in ipairs(targets) do
                local zoneInfo = t.zone and (" [" .. t.zone .. "]") or ""
                print("  " .. i .. ": " .. (t.name or t.id) .. zoneInfo)
            end
        else
            -- No target needed, execute immediately
            executeSelectedAction(nil)
        end
    end)

    -- Create and initialize the crawl screen
    gameState.currentScreen = crawl_screen.createCrawlScreen({
        eventBus     = gameState.eventBus,
        roomManager  = gameState.roomManager,
        watchManager = gameState.watchManager,
        gameState    = gameState,
    })
    gameState.currentScreen:init()

    -- Set the guild on the screen
    gameState.currentScreen:setGuild(gameState.guild)

    -- Subscribe to victory condition
    gameState.eventBus:on(events.EVENTS.INVESTIGATION_COMPLETE, function(data)
        checkVictoryCondition(data)
    end)

    -- S9.4: Subscribe to phase changes for screen transitions
    gameState.eventBus:on(events.EVENTS.PHASE_CHANGED, function(data)
        handlePhaseChange(data)
    end)

    -- S11.4: Subscribe to random encounters for automatic combat trigger
    gameState.eventBus:on(events.EVENTS.RANDOM_ENCOUNTER, function(data)
        -- Only trigger if in crawl phase and not already in combat
        if gameState.phase == "crawl" and not gameState.challengeController:isActive() then
            print("[ENCOUNTER] Random encounter triggered! Card value: " .. data.value)
            triggerRandomEncounter(data)
        end
    end)

    -- S10.2: Combat damage feedback - floating text and sounds
    gameState.eventBus:on(events.EVENTS.WOUND_TAKEN, function(data)
        local entity = data.entity
        local result = data.result
        local damageType = data.damageType or "normal"

        -- Get entity position from arena token, fallback to center screen
        local x = entity._tokenX or (love.graphics.getWidth() / 2)
        local y = entity._tokenY or (love.graphics.getHeight() / 2)

        -- Spawn appropriate floating text based on wound result
        if result == "armor_notched" then
            floating_text.spawnBlock(x, y)
            sound_manager.playCombatMiss(true)  -- wasBlocked = true
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
            floating_text.spawnDamage(1, x, y, true)  -- Show as critical
            floating_text.spawnCondition("Death's Door!", x, y - 20)
            sound_manager.playCombatHit(nil, true)  -- Critical hit sound
            sound_manager.playConditionSound("deaths_door")
        elseif result == "dead" then
            floating_text.spawnDamage(1, x, y, true)
            floating_text.spawnCondition("DEFEATED", x, y - 20)
            sound_manager.playConditionSound("dead")
        else
            -- Generic damage
            floating_text.spawnDamage(1, x, y, false)
            sound_manager.playCombatHit(nil, false)
        end
    end)

    -- S10.2: Card play sound
    gameState.eventBus:on(events.EVENTS.CHALLENGE_ACTION, function(data)
        sound_manager.playCardSound("play")
    end)

    -- S10.2: Challenge start/end sounds
    gameState.eventBus:on(events.EVENTS.CHALLENGE_START, function(data)
        sound_manager.play(sound_manager.SOUNDS.ROUND_START)
        sound_manager.playMusic(sound_manager.SOUNDS.COMBAT_MUSIC)
    end)

    gameState.eventBus:on(events.EVENTS.CHALLENGE_END, function(data)
        sound_manager.stopMusic()
        if data.victory then
            sound_manager.play(sound_manager.SOUNDS.VICTORY)
        end
    end)

    -- Enter the starting room
    gameState.currentScreen:enterRoom("101_entrance")

    print("=== Majesty Vertical Slice Loaded ===")
    print("Tomb of Golden Ghosts - 5 rooms")
    print("Guild size: " .. #gameState.guild)
    print("GM Deck: " .. gameState.gmDeck:totalCards() .. " cards")
    print("Player Deck: " .. gameState.playerDeck:totalCards() .. " cards")
end

--- Create the starting guild of 4 adventurers
function createGuild()
    -- Adventurer 1: The Fighter
    local fighter = adventurer.createAdventurer({
        name = "Grim",
        swords = 3,
        pentacles = 2,
        cups = 1,
        wands = 1,
        motifs = { "Veteran Soldier", "Scarred" },
        armorSlots = 2,  -- Fighter has armor
    })
    fighter:addTalent("aegis", true)
    fighter.weapon = { name = "Sword", type = "sword" }
    giveStartingItems(fighter, { "Sword", "Torch", "Torch" })

    -- Adventurer 2: The Thief
    local thief = adventurer.createAdventurer({
        name = "Whisper",
        swords = 1,
        pentacles = 3,
        cups = 2,
        wands = 1,
        motifs = { "Former Burglar", "Quick Fingers" },
    })
    thief:addTalent("finesse", true)
    thief.weapon = { name = "Dagger", type = "dagger" }
    giveStartingItems(thief, { "Dagger", "Lockpicks", "Rope" })

    -- Adventurer 3: The Sage
    local sage = adventurer.createAdventurer({
        name = "Ember",
        swords = 1,
        pentacles = 1,
        cups = 3,
        wands = 2,
        motifs = { "Hedge Witch", "Bookish" },
    })
    sage:addTalent("ritualist", false)  -- In training
    sage.weapon = { name = "Staff", type = "staff" }
    giveStartingItems(sage, { "Staff", "Lantern", "Chalk" })

    -- Adventurer 4: The Scout
    local scout = adventurer.createAdventurer({
        name = "Fern",
        swords = 2,
        pentacles = 2,
        cups = 1,
        wands = 2,
        motifs = { "Wilderness Guide", "Sharp Eyes" },
    })
    scout:addTalent("pathfinder", true)
    scout.weapon = { name = "Bow", type = "bow", uses_ammo = true }
    scout.ammo = 10  -- Starting arrows
    giveStartingItems(scout, { "Bow", "Torch", "Rations" })

    -- Add to guild
    gameState.guild = { fighter, thief, sage, scout }

    -- Set up bonds between party members
    fighter:setBond(thief.id, "rivalry")
    thief:setBond(fighter.id, "rivalry")
    sage:setBond(scout.id, "friendship")
    scout:setBond(sage.id, "friendship")
end

--- Give starting items to an adventurer
function giveStartingItems(entity, itemNames)
    entity.inventory = inventory.createInventory()

    for _, itemName in ipairs(itemNames) do
        local item = inventory.createItem({
            name = itemName,
            size = inventory.SIZE.NORMAL,
        })

        -- Special handling for light sources
        if itemName == "Torch" then
            item.properties = { flicker_count = 3, light_source = true }
        elseif itemName == "Lantern" then
            item.properties = { flicker_count = 6, light_source = true }
        end

        -- Add to belt for quick access
        entity.inventory:addItem(item, inventory.LOCATIONS.BELT)
    end
end

--- Check for victory condition (Vellum Map retrieved)
function checkVictoryCondition(data)
    -- In full implementation, check if the item retrieved is the Vellum Map
    -- For now, just flag based on room (would be from a chest in final room)
    if data.poiId and data.poiId:find("vellum") then
        gameState.vellumMapFound = true
        print("=== VICTORY! Vellum Map Retrieved! ===")
        showEndOfDemoScreen("vellum_map")
    end
end

--------------------------------------------------------------------------------
-- END OF DEMO / CITY STUB (S10.1)
--------------------------------------------------------------------------------

--- Show the end of demo screen
-- @param reason string: "vellum_map", "exited", or "completed"
function showEndOfDemoScreen(reason)
    print("=== SHOWING END OF DEMO SCREEN ===")

    gameState.currentScreen = end_of_demo_screen.createEndOfDemoScreen({
        eventBus = gameState.eventBus,
        guild = gameState.guild,
        victoryReason = reason,
        onReturnToCity = returnToCity,
    })
    gameState.currentScreen:init()
    gameState.phase = "end_of_demo"
end

--- Return to city - reset game state for another expedition
function returnToCity()
    print("=== RETURNING TO CITY ===")

    -- 1. Deduct 50% Gold (if we had gold)
    for _, pc in ipairs(gameState.guild) do
        if pc.gold then
            pc.gold = math.floor(pc.gold / 2)
        end
    end

    -- 2. Heal all wounds/conditions (Luxurious Upkeep simulation)
    for _, pc in ipairs(gameState.guild) do
        -- Clear all conditions
        pc.conditions = {}

        -- Reset wound state if using wound track
        if pc.resetWounds then
            pc:resetWounds()
        end

        -- Clear starvation
        pc.starvationCount = 0

        -- Recharge all bonds
        if pc.bonds then
            for _, bond in pairs(pc.bonds) do
                bond.charged = true
            end
        end

        -- Refill lore bids
        pc.loreBids = 4
    end

    -- 3. Refill arrows/torches/rations (Shopping simulation)
    for _, pc in ipairs(gameState.guild) do
        -- Refill ammo
        if pc.ammo ~= nil then
            pc.ammo = 10
        end

        -- Add torches and rations to inventory if they have one
        if pc.inventory then
            -- Clear and refill with fresh supplies
            -- For simplicity, just ensure they have light and food
            local hasTorch = pc.inventory:findItemByPredicate(function(item)
                return item.properties and item.properties.light_source
            end)
            if not hasTorch then
                local torch = inventory.createItem({
                    name = "Torch",
                    size = inventory.SIZE.NORMAL,
                    properties = { flicker_count = 3, light_source = true },
                })
                pc.inventory:addItem(torch, inventory.LOCATIONS.BELT)
            end

            local hasRation = pc.inventory:findItemByPredicate(function(item)
                return item.isRation or item.type == "ration" or
                       (item.name and item.name:lower():find("ration"))
            end)
            if not hasRation then
                local ration = inventory.createItem({
                    name = "Ration",
                    stackable = true,
                    stackSize = 3,
                    quantity = 3,
                    isRation = true,
                })
                pc.inventory:addItem(ration, inventory.LOCATIONS.PACK)
            end
        end
    end

    -- 4. Reset dungeon state
    gameState.dungeon:reset()
    gameState.roomManager:reset(tomb_data.data.rooms)

    -- Reset watch manager to entrance
    gameState.watchManager.currentRoom = "101_entrance"
    gameState.watchManager.watchCount = 0

    -- Reset victory flag
    gameState.vellumMapFound = false

    -- 5. Transition back to crawl screen
    gameState.currentScreen = crawl_screen.createCrawlScreen({
        eventBus     = gameState.eventBus,
        roomManager  = gameState.roomManager,
        watchManager = gameState.watchManager,
        gameState    = gameState,
    })
    gameState.currentScreen:init()
    gameState.currentScreen:setGuild(gameState.guild)
    gameState.currentScreen:enterRoom("101_entrance")

    gameState.phase = "crawl"

    print("=== READY FOR NEW EXPEDITION ===")
end

--------------------------------------------------------------------------------
-- CAMP PHASE (Sprint 9)
--------------------------------------------------------------------------------

--- Start the camp phase (S9.4)
function startCampPhase()
    if gameState.phase ~= "crawl" then
        print("[CAMP] Can only camp from crawl phase!")
        return
    end

    print("=== STARTING CAMP PHASE ===")

    -- Create camp controller
    gameState.campController = camp_controller.createCampController({
        eventBus = gameState.eventBus,
        guild = gameState.guild,
        watchManager = gameState.watchManager,
    })

    -- Create camp screen
    gameState.campScreen = camp_screen.createCampScreen({
        eventBus = gameState.eventBus,
        campController = gameState.campController,
        guild = gameState.guild,
    })
    gameState.campScreen:init()

    -- Determine shelter/bedroll status from inventory
    local hasBedrolls = false
    local hasShelter = false
    for _, pc in ipairs(gameState.guild) do
        if pc.inventory and pc.inventory.findItemByPredicate then
            -- Check for bedroll
            local bedroll = pc.inventory:findItemByPredicate(function(item)
                return item.name and item.name:lower():find("bedroll")
            end)
            if bedroll then hasBedrolls = true end

            -- Check for tent/shelter
            local tent = pc.inventory:findItemByPredicate(function(item)
                return item.name and (item.name:lower():find("tent") or item.name:lower():find("shelter"))
            end)
            if tent then hasShelter = true end
        end
    end

    -- Start camp
    gameState.campController:startCamp({
        hasShelter = hasShelter,
        hasBedrolls = hasBedrolls,
    })

    -- Switch to camp screen
    gameState.currentScreen = gameState.campScreen
    gameState.phase = "camp"

    print("[CAMP] Camp started! Shelter: " .. tostring(hasShelter) .. ", Bedrolls: " .. tostring(hasBedrolls))
end

--- Handle phase changes (S9.4)
function handlePhaseChange(data)
    if data.newPhase == "crawl" and data.oldPhase == "camp" then
        -- Return to crawl screen
        print("[PHASE] Returning to crawl phase")

        -- Recreate crawl screen (state is preserved in managers)
        gameState.currentScreen = crawl_screen.createCrawlScreen({
            eventBus     = gameState.eventBus,
            roomManager  = gameState.roomManager,
            watchManager = gameState.watchManager,
            gameState    = gameState,
        })
        gameState.currentScreen:init()
        gameState.currentScreen:setGuild(gameState.guild)

        -- Re-enter current room
        local currentRoom = gameState.watchManager:getCurrentRoom()
        gameState.currentScreen:enterRoom(currentRoom)

        gameState.phase = "crawl"
        gameState.campController = nil
        gameState.campScreen = nil

    elseif data.newPhase == "camp" then
        startCampPhase()
    end
end

--------------------------------------------------------------------------------
-- S11.4: ORGANIC COMBAT TRIGGER
--------------------------------------------------------------------------------

--- Trigger a random encounter from meatgrinder result
function triggerRandomEncounter(data)
    print("=== RANDOM ENCOUNTER! ===")

    -- Get current room for zone setup
    local currentRoom = gameState.watchManager:getCurrentRoom()
    local roomData = gameState.roomManager:getRoom(currentRoom)

    -- Get room danger level for enemy scaling
    local dangerLevel = 1
    if roomData then
        dangerLevel = roomData.danger_level or 1
    end

    -- Create default zones
    local zones = {
        { id = "near", name = "Near Side", description = "Closer to the entrance." },
        { id = "center", name = "Center", description = "The middle of the room." },
        { id = "far", name = "Far Side", description = "The far end of the room." },
    }

    -- Create enemy based on meatgrinder value and room context
    -- Higher card values = tougher enemies
    local enemyCount = 1
    if data.value >= 19 then
        enemyCount = 2  -- Tougher encounter
    end

    local enemies = {}
    for i = 1, enemyCount do
        local enemy = {
            id = "encounter_enemy_" .. i,
            name = "Tomb Guardian",
            isPC = false,
            rank = "soldier",
            zone = zones[#zones].id,  -- Enemies start in far zone

            -- Stats scaled by danger level
            swords = 1 + dangerLevel,
            pentacles = 1,
            cups = 0,
            wands = 1,

            -- Combat state
            armorNotches = dangerLevel > 1 and 1 or 0,
            conditions = {},
            morale = 6 + dangerLevel,

            -- Weapon
            weapon = { name = "Rusty Blade", type = "sword" },

            -- Simple wound handling for NPC
            takeWound = function(self, pierceArmor)
                if not pierceArmor and self.armorNotches > 0 then
                    self.armorNotches = self.armorNotches - 1
                    return "armor_notched"
                elseif not self.conditions.staggered then
                    self.conditions.staggered = true
                    return "staggered"
                elseif not self.conditions.injured then
                    self.conditions.injured = true
                    return "injured"
                elseif not self.conditions.deaths_door then
                    self.conditions.deaths_door = true
                    return "deaths_door"
                else
                    self.conditions.dead = true
                    return "dead"
                end
            end,
        }
        enemies[#enemies + 1] = enemy
    end

    -- Set starting zones for PCs
    local pcStartZone = zones[1].id
    for _, pc in ipairs(gameState.guild) do
        pc.zone = pcStartZone
    end

    print("[ENCOUNTER] Spawning " .. #enemies .. " enemies in " .. currentRoom)
    print("[ENCOUNTER] Danger level: " .. dangerLevel)

    -- Start the challenge
    gameState.challengeController:startChallenge({
        npcs = enemies,
        pcs = gameState.guild,
        challengeType = "combat",
        roomId = currentRoom,
        zones = zones,
    })
end

--------------------------------------------------------------------------------
-- DEBUG: TEST COMBAT
--------------------------------------------------------------------------------

--- Start a test combat encounter
function startTestCombat()
    print("=== STARTING TEST COMBAT ===")

    -- Get current room data for zones
    local currentRoom = gameState.watchManager:getCurrentRoom()
    local roomData = gameState.roomManager:getRoom(currentRoom) if roomData then roomData = roomData.data end

    -- Get zones from room data, or use defaults
    local zones = nil
    if roomData and roomData.zones then
        zones = roomData.zones
    else
        -- Default zones for combat
        zones = {
            { id = "near", name = "Near Side", description = "Closer to the entrance." },
            { id = "center", name = "Center", description = "The middle of the room." },
            { id = "far", name = "Far Side", description = "The far end of the room." },
        }
    end

    -- Create a test enemy (placed in "far" zone by default)
    local testEnemy = {
        id = "test_skeleton_1",
        name = "Skeleton Warrior",
        isPC = false,
        rank = "soldier",
        zone = zones[#zones].id,  -- Put enemy in the last zone (far end)

        -- Stats (same structure as adventurers)
        swords = 2,
        pentacles = 1,
        cups = 0,
        wands = 1,

        -- Combat state
        armorNotches = 1,
        conditions = {},
        morale = 8,

        -- Weapon
        weapon = { name = "Rusty Sword", type = "sword" },

        -- Simple wound handling for NPC
        takeWound = function(self, pierceArmor)
            if not pierceArmor and self.armorNotches > 0 then
                self.armorNotches = self.armorNotches - 1
                return "armor_notched"
            elseif not self.conditions.staggered then
                self.conditions.staggered = true
                return "staggered"
            elseif not self.conditions.injured then
                self.conditions.injured = true
                return "injured"
            elseif not self.conditions.deaths_door then
                self.conditions.deaths_door = true
                return "deaths_door"
            else
                self.conditions.dead = true
                return "dead"
            end
        end,
    }

    -- Set starting zones for PCs (near the entrance)
    local pcStartZone = zones[1].id
    for _, pc in ipairs(gameState.guild) do
        pc.zone = pcStartZone
    end

    print("[COMBAT] Room zones: " .. #zones)
    for i, z in ipairs(zones) do
        print("  " .. i .. ". " .. z.name .. " (" .. z.id .. ")")
    end
    print("[COMBAT] PCs start in: " .. pcStartZone)
    print("[COMBAT] Enemy starts in: " .. testEnemy.zone)

    -- Start the challenge with zone data
    gameState.challengeController:startChallenge({
        npcs = { testEnemy },
        pcs = gameState.guild,
        challengeType = "combat",
        roomId = currentRoom,
        zones = zones,  -- Pass zones to challenge controller
    })
end

--- Handle input during challenge phase
-- New flow: Q/W/E selects card → Command Board → Select Action → Select Target → Execute
function handleChallengeInput(key)
    local controller = gameState.challengeController
    local hand = gameState.playerHand
    local state = controller:getState()

    -- Handle initiative submission phase (PRE_ROUND)
    if state == "pre_round" then
        handleInitiativeInput(key)
        return
    end

    -- Handle minor action window (S6.4)
    if state == "minor_window" then
        handleMinorWindowInput(key)
        return
    end

    -- Only accept combat input when awaiting action
    if state ~= "awaiting_action" then
        return
    end

    local activeEntity = controller:getActiveEntity()
    if not activeEntity or not activeEntity.isPC then
        return  -- Not a PC's turn
    end

    -- If awaiting zone selection, handle number keys for zone
    if combatInputState.awaitingZone then
        handleZoneSelection(key)
        return
    end

    -- If awaiting target selection, handle number keys for target
    if combatInputState.awaitingTarget then
        handleTargetSelection(key)
        return
    end

    -- Q/W/E: Select card and show command board
    local cardKeys = { q = 1, w = 2, e = 3 }
    if cardKeys[key] then
        local cardIndex = cardKeys[key]
        local cards = hand:getHand(activeEntity)

        if cardIndex <= #cards then
            local card = cards[cardIndex]

            -- Store selection state
            combatInputState.selectedCard = card
            combatInputState.selectedCardIndex = cardIndex
            combatInputState.selectedEntity = activeEntity

            -- Emit card_selected to show command board
            gameState.eventBus:emit("card_selected", {
                card = card,
                entity = activeEntity,
                isPrimaryTurn = true,
                cardIndex = cardIndex,
            })

            print("[COMBAT] " .. activeEntity.name .. " selected " .. card.name .. " - choose action from Command Board")
        else
            print("[COMBAT] No card at position " .. cardIndex)
        end
        return
    end

    -- Show hand info when pressing H
    if key == "h" then
        local cards = hand:getHand(activeEntity)
        print("[HAND] " .. activeEntity.name .. "'s cards:")
        for i, card in ipairs(cards) do
            local keyLetter = ({ "Q", "W", "E" })[i]
            local suitName = hand:getSuitName(card.suit)
            print("  " .. keyLetter .. ": " .. card.name .. " (" .. suitName .. ", " .. card.value .. ")")
        end
        return
    end

    -- SPACE: Pass turn (skip action)
    if key == "space" then
        print("[COMBAT] " .. (activeEntity.name or "PC") .. " passes")
        resetCombatInputState()
        gameState.eventBus:emit(events.EVENTS.UI_SEQUENCE_COMPLETE, {})
    end

    -- ESC: Cancel current selection
    if key == "escape" then
        if combatInputState.selectedCard then
            resetCombatInputState()
            gameState.eventBus:emit("card_deselected", {})
            print("[COMBAT] Selection cancelled")
        end
    end
end

--- Handle input during minor action window
function handleMinorWindowInput(key)
    local controller = gameState.challengeController
    local hand = gameState.playerHand

    -- If awaiting target selection for a minor action, handle that first
    if combatInputState.awaitingTarget then
        handleTargetSelection(key)
        return
    end

    -- Number keys 1-4: Select which PC will declare a minor
    local keyNum = tonumber(key)
    if keyNum and keyNum >= 1 and keyNum <= 4 then
        local pc = gameState.guild[keyNum]
        if pc then
            local cards = hand:getHand(pc)
            if #cards > 0 then
                combatInputState.minorPC = pc
                print("[MINOR] Select a card for " .. pc.name .. " (Q/W/E)")
            else
                print("[MINOR] " .. pc.name .. " has no cards!")
            end
        end
        return
    end

    -- Q/W/E: Select card for minor action (if PC selected)
    if combatInputState.minorPC then
        local cardKeys = { q = 1, w = 2, e = 3 }
        if cardKeys[key] then
            local cardIndex = cardKeys[key]
            local cards = hand:getHand(combatInputState.minorPC)

            if cardIndex <= #cards then
                local card = cards[cardIndex]

                -- Store selection and show command board (with minor filtering)
                combatInputState.selectedCard = card
                combatInputState.selectedCardIndex = cardIndex
                combatInputState.selectedEntity = combatInputState.minorPC

                gameState.eventBus:emit("card_selected", {
                    card = card,
                    entity = combatInputState.minorPC,
                    isPrimaryTurn = false,  -- Minor action = suit restricted
                    cardIndex = cardIndex,
                })

                print("[MINOR] " .. combatInputState.minorPC.name .. " selected " .. card.name .. " for minor action")
            end
            return
        end

        -- ESC to cancel PC selection
        if key == "escape" then
            combatInputState.minorPC = nil
            gameState.eventBus:emit("card_deselected", {})
            print("[MINOR] PC selection cancelled")
            return
        end
    end

    -- SPACE: Resume from minor window (handled by minor_action_panel)
    -- But also allow keyboard shortcut here
    if key == "space" or key == "return" then
        controller:resumeFromMinorWindow()
        resetCombatInputState()
    end
end

--- Handle zone selection (number keys to select destination zone for Move)
function handleZoneSelection(key)
    local zones = combatInputState.availableZones

    if not zones or #zones == 0 then
        combatInputState.awaitingZone = false
        return
    end

    -- Number keys to select zone
    local keyNum = tonumber(key)
    if keyNum and keyNum >= 1 and keyNum <= #zones then
        local selectedZone = zones[keyNum]
        executeSelectedAction(nil, selectedZone.id)
        return
    end

    -- ESC to cancel
    if key == "escape" then
        combatInputState.awaitingZone = false
        combatInputState.availableZones = nil
        resetCombatInputState()
        gameState.eventBus:emit("card_deselected", {})
        print("[COMBAT] Zone selection cancelled")
    end
end

--- Handle target selection (number keys to select target)
function handleTargetSelection(key)
    local controller = gameState.challengeController
    local action = combatInputState.selectedAction
    local actorZone = combatInputState.selectedEntity and combatInputState.selectedEntity.zone

    if not action then
        combatInputState.awaitingTarget = false
        return
    end

    -- Check if this is a melee action (requires same zone)
    local isMelee = (action.id == "melee" or action.id == "grapple" or
                    action.id == "trip" or action.id == "disarm" or
                    action.id == "displace")

    -- Get valid targets based on action type
    local targets = {}
    if action.targetType == "enemy" then
        for _, npc in ipairs(controller.npcs or {}) do
            if not (npc.conditions and npc.conditions.dead) then
                if isMelee then
                    if npc.zone == actorZone then
                        targets[#targets + 1] = npc
                    end
                else
                    targets[#targets + 1] = npc
                end
            end
        end
    elseif action.targetType == "ally" then
        for _, pc in ipairs(controller.pcs or {}) do
            if not (pc.conditions and pc.conditions.dead) then
                if isMelee then
                    if pc.zone == actorZone then
                        targets[#targets + 1] = pc
                    end
                else
                    targets[#targets + 1] = pc
                end
            end
        end
    else
        -- "any" - include all living entities
        for _, npc in ipairs(controller.npcs or {}) do
            if not (npc.conditions and npc.conditions.dead) then
                if isMelee then
                    if npc.zone == actorZone then
                        targets[#targets + 1] = npc
                    end
                else
                    targets[#targets + 1] = npc
                end
            end
        end
        for _, pc in ipairs(controller.pcs or {}) do
            if not (pc.conditions and pc.conditions.dead) then
                if isMelee then
                    if pc.zone == actorZone then
                        targets[#targets + 1] = pc
                    end
                else
                    targets[#targets + 1] = pc
                end
            end
        end
    end

    -- Number keys to select target
    local keyNum = tonumber(key)
    if keyNum and keyNum >= 1 and keyNum <= #targets then
        local target = targets[keyNum]
        executeSelectedAction(target)
        return
    end

    -- ESC to cancel
    if key == "escape" then
        combatInputState.awaitingTarget = false
        resetCombatInputState()
        gameState.eventBus:emit("card_deselected", {})
        print("[COMBAT] Target selection cancelled")
    end
end

--- Execute the selected action with the chosen target or destination zone
function executeSelectedAction(target, destinationZone)
    local controller = gameState.challengeController
    local hand = gameState.playerHand
    local state = controller:getState()

    local card = combatInputState.selectedCard
    local entity = combatInputState.selectedEntity
    local action = combatInputState.selectedAction
    local cardIndex = combatInputState.selectedCardIndex

    if not card or not entity or not action then
        print("[COMBAT] Invalid action state")
        resetCombatInputState()
        return
    end

    -- Check if this is a minor action declaration or primary action
    local isMinor = (state == "minor_window")

    if isMinor then
        -- Add to pending minors instead of executing immediately
        local cards = hand:getHand(entity)
        table.remove(cards, cardIndex)
        gameState.playerDeck:discard(card)

        controller:declareMinorAction(entity, card, {
            type = action.id,
            target = target,
            destinationZone = destinationZone,
            weapon = entity.weapon,
        })

        print("[MINOR] " .. entity.name .. " declares " .. action.name)
        combatInputState.minorPC = nil  -- Clear PC selection
    else
        -- Execute primary action immediately
        local cards = hand:getHand(entity)
        table.remove(cards, cardIndex)
        gameState.playerDeck:discard(card)

        local fullAction = {
            actor = entity,
            target = target,
            card = card,
            type = action.id,
            destinationZone = destinationZone,
            weapon = entity.weapon or { name = "Fists", type = "staff" },
            allEntities = controller.allCombatants,  -- Pass all entities for parting blow checks
        }

        if destinationZone then
            print("[COMBAT] " .. entity.name .. " uses " .. action.name .. " to move to " .. destinationZone)
        else
            print("[COMBAT] " .. entity.name .. " uses " .. action.name .. " on " .. (target and target.name or "no target"))
        end
        gameState.eventBus:emit(events.EVENTS.CHALLENGE_ACTION, fullAction)
    end

    resetCombatInputState()
    gameState.eventBus:emit("card_deselected", {})
end

--- Handle input during initiative submission phase
-- Two-step selection:
-- 1. Press 1-4 to select which PC
-- 2. Press Q/W/E/R to select which card from their hand (or auto-pick first)
function handleInitiativeInput(key)
    local controller = gameState.challengeController
    local hand = gameState.playerHand

    -- If a PC is selected, Q/W/E/R picks a card from their hand
    if hand.selectedPC and controller.awaitingInitiative[hand.selectedPC.id] then
        local cardKeys = { q = 1, w = 2, e = 3, r = 4 }
        if cardKeys[key] then
            local cardIndex = cardKeys[key]
            local card = hand:useForInitiative(hand.selectedPC, cardIndex)
            if card then
                controller:submitInitiative(hand.selectedPC, card)
                hand:clearSelection()
            else
                print("[INITIATIVE] Invalid card selection!")
            end
            return
        end

        -- ESC to cancel selection
        if key == "escape" then
            hand:clearSelection()
            return
        end
    end

    -- Number keys 1-4: Select which PC to submit for
    local keyNum = tonumber(key)
    if keyNum and keyNum >= 1 and keyNum <= 4 then
        local pc = gameState.guild[keyNum]
        if pc and controller.awaitingInitiative[pc.id] then
            local cards = hand:getHand(pc)
            if #cards > 0 then
                -- Select this PC (highlight their hand)
                hand.selectedPC = pc
                print("[INITIATIVE] Select a card for " .. pc.name .. " (Q/W/E/R)")

                -- Show their hand
                for i, card in ipairs(cards) do
                    local keyLetter = ({ "Q", "W", "E", "R" })[i]
                    print("  " .. keyLetter .. ": " .. card.name .. " (" .. card.value .. ")")
                end
            else
                print("[INITIATIVE] " .. pc.name .. " has no cards!")
            end
        elseif pc then
            print("[INITIATIVE] " .. pc.name .. " has already submitted initiative")
        end
    end

    -- SPACE: Auto-submit for all remaining PCs (use first card)
    if key == "space" then
        for _, pc in ipairs(gameState.guild) do
            if controller.awaitingInitiative[pc.id] then
                local cards = hand:getHand(pc)
                if #cards > 0 then
                    local card = hand:useForInitiative(pc, 1)
                    if card then
                        controller:submitInitiative(pc, card)
                    end
                end
            end
        end
        hand:clearSelection()
    end
end

--------------------------------------------------------------------------------
-- LÖVE 2D CALLBACKS
--------------------------------------------------------------------------------

function love.update(dt)
    if gameState.currentScreen then
        gameState.currentScreen:update(dt)
    end

    -- Update challenge systems
    if gameState.challengeController then
        gameState.challengeController:update(dt)
    end
    if gameState.actionSequencer then
        gameState.actionSequencer:update(dt)
    end
    if gameState.woundWalk then
        gameState.woundWalk:update(dt)
    end
    -- S5.3: Update combat display
    if gameState.combatDisplay then
        gameState.combatDisplay:update(dt)
    end
    -- S5.4: Update inspect panel
    if gameState.inspectPanel then
        gameState.inspectPanel:update(dt)
    end
    -- S6.1: Update arena view
    if gameState.arenaView then
        gameState.arenaView:update(dt)
    end
    -- S6.2: Update command board
    if gameState.commandBoard then
        gameState.commandBoard:update(dt)
    end
    -- S6.4: Update minor action panel
    if gameState.minorActionPanel then
        gameState.minorActionPanel:update(dt)
    end

    -- S10.2: Update floating text
    floating_text.update(dt)

    -- S11.1: Update character sheet
    if gameState.characterSheet then
        gameState.characterSheet:update(dt)
    end

    -- S11.3: Update loot modal
    if gameState.lootModal then
        gameState.lootModal:update(dt)
    end
end

function love.draw()
    if gameState.currentScreen then
        gameState.currentScreen:draw()
    end

    -- S6.1: Draw arena view during challenges
    if gameState.arenaView and gameState.arenaView.isVisible then
        gameState.arenaView:draw()
    end

    -- Draw challenge overlay if active
    if gameState.challengeController and gameState.challengeController:isActive() then
        drawChallengeOverlay()
    end

    -- Draw action sequencer visuals
    if gameState.actionSequencer then
        drawActionVisuals()
    end

    -- S6.2: Draw command board (above action visuals)
    if gameState.commandBoard then
        gameState.commandBoard:draw()
    end

    -- S6.4: Draw minor action panel (with dim overlay)
    if gameState.minorActionPanel then
        gameState.minorActionPanel:draw()
    end

    -- S5.4: Draw inspect panel (on top of everything)
    if gameState.inspectPanel then
        gameState.inspectPanel:draw()
    end

    -- S10.2: Draw floating text (damage numbers, etc.)
    floating_text.draw()

    -- S11.1: Draw character sheet (on top of everything except debug)
    if gameState.characterSheet then
        gameState.characterSheet:draw()
    end

    -- S11.3: Draw loot modal (on top of everything except debug)
    if gameState.lootModal then
        gameState.lootModal:draw()
    end

    -- Draw debug info
    love.graphics.setColor(1, 1, 1, 0.5)
    local challengeInfo = ""
    if gameState.challengeController and gameState.challengeController:isActive() then
        challengeInfo = string.format(" | COMBAT Turn %d/%d",
            gameState.challengeController:getCurrentTurn(),
            gameState.challengeController:getMaxTurns())
    end
    love.graphics.print(
        string.format("Watch: %d | Light: %s | FPS: %d%s",
            gameState.watchManager:getWatchCount(),
            gameState.lightSystem:getLightLevel() or "?",
            love.timer.getFPS(),
            challengeInfo),
        10,
        love.graphics.getHeight() - 20
    )
end

--- Draw challenge phase overlay
function drawChallengeOverlay()
    local controller = gameState.challengeController
    local w, h = love.graphics.getDimensions()
    local state = controller:getState()

    -- Semi-transparent combat banner at top
    love.graphics.setColor(0.2, 0, 0, 0.8)
    love.graphics.rectangle("fill", 0, 0, w, 80)

    -- Phase-specific display
    if state == "pre_round" then
        -- Initiative submission phase
        love.graphics.setColor(1, 0.8, 0.2, 1)
        love.graphics.print("=== INITIATIVE PHASE ===", w/2 - 100, 10)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("Round " .. controller:getCurrentRound(), w/2 - 30, 35)

        -- Show who needs to submit initiative
        love.graphics.setColor(0.8, 0.8, 0.8, 1)
        local yOffset = 55
        for i, pc in ipairs(gameState.guild) do
            local submitted = not controller.awaitingInitiative[pc.id]
            local status = submitted and "[Ready]" or "[Press " .. i .. "]"
            local color = submitted and {0.3, 1, 0.3, 1} or {1, 1, 0.3, 1}
            love.graphics.setColor(color)
            love.graphics.print(i .. ". " .. pc.name .. " " .. status, 20 + (i-1) * 150, yOffset)
        end

        -- Prompt
        love.graphics.setColor(1, 1, 0, 1)
        love.graphics.print("Press 1-4 to submit initiative cards for each guild member", 20, h - 50)
    else
        -- Count-up / combat phase
        love.graphics.setColor(1, 0.3, 0.3, 1)
        love.graphics.print("=== CHALLENGE PHASE ===", w/2 - 100, 10)

        -- Round and count info
        love.graphics.setColor(1, 1, 1, 1)
        local countText = string.format("Round %d | Count: %d / %d",
            controller:getCurrentRound(),
            controller:getCurrentCount(),
            controller:getMaxTurns())
        love.graphics.print(countText, w/2 - 70, 35)

        -- Active entity indicator
        local activeEntity = controller:getActiveEntity()
        if activeEntity then
            local actorName = activeEntity.name or "Unknown"
            local isPC = activeEntity.isPC

            love.graphics.setColor(isPC and {0.3, 1, 0.3, 1} or {1, 0.3, 0.3, 1})
            love.graphics.print(actorName .. "'s turn (" .. state .. ")", 20, 55)

            -- Show initiative card value
            local slot = controller:getInitiativeSlot(activeEntity.id)
            if slot and slot.revealed then
                love.graphics.setColor(0.9, 0.85, 0.7, 1)
                love.graphics.print("Initiative: " .. slot.value, 20, 35)
            end

            -- If PC turn and awaiting action, draw their hand and show prompt
            if isPC and state == "awaiting_action" then
                drawPlayerHand(activeEntity)

                love.graphics.setColor(1, 1, 0, 1)
                if combatInputState.awaitingZone then
                    -- Show zone selection prompt
                    local zones = combatInputState.availableZones or {}
                    love.graphics.print("Select destination zone (1-" .. #zones .. "), ESC to cancel", 20, h - 50)
                elseif combatInputState.awaitingTarget then
                    -- Show target selection prompt
                    love.graphics.print("Select target (1-N), ESC to cancel", 20, h - 50)
                elseif combatInputState.selectedCard then
                    -- Card selected, waiting for action from command board
                    love.graphics.print("Choose action from Command Board, ESC to cancel", 20, h - 50)
                else
                    love.graphics.print("Press Q/W/E to select card, H for hand info, SPACE to pass", 20, h - 50)
                end
            end
        end

        -- Minor window state
        if state == "minor_window" then
            love.graphics.setColor(0.8, 0.6, 0.2, 1)
            love.graphics.print("=== MINOR ACTION WINDOW ===", w/2 - 120, 55)

            -- Show which PCs can declare minors
            love.graphics.setColor(0.8, 0.8, 0.8, 1)
            local hand = gameState.playerHand
            for i, pc in ipairs(gameState.guild) do
                local cards = hand:getHand(pc)
                local cardCount = #cards
                local status = cardCount > 0 and string.format("[%d cards]", cardCount) or "[no cards]"
                local color = cardCount > 0 and {0.7, 1, 0.7, 1} or {0.5, 0.5, 0.5, 1}
                love.graphics.setColor(color)
                love.graphics.print(i .. ". " .. pc.name .. " " .. status, 20 + (i-1) * 160, 55)
            end

            -- Draw selected PC's hand if one is selected
            if combatInputState.minorPC then
                drawPlayerHand(combatInputState.minorPC)
            end

            love.graphics.setColor(1, 1, 0, 1)
            if combatInputState.awaitingTarget then
                love.graphics.print("Select target (1-N) for minor action, ESC to cancel", 20, h - 50)
            elseif combatInputState.selectedCard then
                love.graphics.print("Choose action from Command Board, ESC to cancel", 20, h - 50)
            elseif combatInputState.minorPC then
                love.graphics.print("Press Q/W/E to select card for " .. combatInputState.minorPC.name .. ", ESC to cancel", 20, h - 50)
            else
                love.graphics.print("Press 1-4 to select PC for minor action, SPACE to resume", 20, h - 50)
            end
        end
    end

    -- During initiative phase, show selected PC's hand
    if state == "pre_round" then
        local hand = gameState.playerHand
        if hand.selectedPC then
            drawPlayerHand(hand.selectedPC)
            love.graphics.setColor(1, 1, 0, 1)
            love.graphics.print("Press Q/W/E/R to select initiative card, ESC to cancel, SPACE for auto-all", 20, h - 50)
        end
    end

    -- S5.3: Draw combatants with initiative and defense slots
    local combatDsp = gameState.combatDisplay
    local activeEntity = controller:getActiveEntity()

    -- Draw NPCs on the right side
    local npcs = controller.npcs or {}
    local npcStartX = w - 220
    local npcStartY = 85

    for i, npc in ipairs(npcs) do
        local isActive = (activeEntity == npc)
        combatDsp:drawCombatantRow(npc, npcStartX, npcStartY + (i-1) * 65, isActive)
    end

    -- Draw count-up bar (if in count-up phase)
    if state == "count_up" or state == "awaiting_action" or state == "resolving" then
        local barWidth = w - 40
        combatDsp:drawCountUpBar(20, h - 30, barWidth, controller:getCurrentCount(), controller:getMaxTurns())
    end
end

--- Draw a PC's hand of cards at the bottom of the screen
function drawPlayerHand(pc)
    local hand = gameState.playerHand
    local cards = hand:getHand(pc)
    local w, h = love.graphics.getDimensions()

    if #cards == 0 then return end

    -- Card dimensions
    local cardWidth = 100
    local cardHeight = 140
    local cardSpacing = 20
    local totalWidth = (#cards * cardWidth) + ((#cards - 1) * cardSpacing)
    local startX = (w - totalWidth) / 2
    local startY = h - cardHeight - 70

    -- Get mouse position for hover detection
    local mouseX, mouseY = love.mouse.getPosition()

    -- Background for hand area
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", startX - 10, startY - 30, totalWidth + 20, cardHeight + 60, 8, 8)

    -- Header
    love.graphics.setColor(0.9, 0.9, 0.9, 1)
    love.graphics.print(pc.name .. "'s Hand", startX, startY - 25)

    -- Draw each card
    local keyLetters = { "Q", "W", "E", "R" }
    for i, card in ipairs(cards) do
        local x = startX + (i - 1) * (cardWidth + cardSpacing)
        local y = startY

        -- S10.2: Determine card state
        local isSelected = (combatInputState.selectedCardIndex == i and combatInputState.selectedEntity == pc)
        local isHovered = mouseX >= x and mouseX < x + cardWidth and mouseY >= y and mouseY < y + cardHeight
        local isGrayed = false  -- Could check if card is playable this turn

        -- Card background (color by suit)
        local suitColors = {
            [1] = { 0.8, 0.3, 0.3 },  -- Swords - red
            [2] = { 0.3, 0.7, 0.3 },  -- Pentacles - green
            [3] = { 0.3, 0.5, 0.9 },  -- Cups - blue
            [4] = { 0.8, 0.6, 0.2 },  -- Wands - orange
        }
        local bgColor = suitColors[card.suit] or { 0.5, 0.4, 0.6 }  -- Major Arcana - purple

        -- S10.2: Adjust colors based on state
        local alpha = 0.9
        if isGrayed then
            -- Gray out unavailable cards
            bgColor = { 0.35, 0.35, 0.35 }
            alpha = 0.6
        end

        -- S10.2: Draw selection glow (behind card)
        if isSelected then
            love.graphics.setColor(1, 0.9, 0.3, 0.6)
            love.graphics.rectangle("fill", x - 4, y - 4, cardWidth + 8, cardHeight + 8, 8, 8)
        end

        -- Draw card background
        love.graphics.setColor(bgColor[1], bgColor[2], bgColor[3], alpha)
        love.graphics.rectangle("fill", x, y, cardWidth, cardHeight, 6, 6)

        -- S10.2: Draw hover highlight
        if isHovered and not isSelected then
            love.graphics.setColor(1, 1, 1, 0.3)
            love.graphics.rectangle("fill", x, y, cardWidth, cardHeight, 6, 6)
        end

        -- Card border (thicker if selected or hovered)
        if isSelected then
            love.graphics.setColor(1, 0.85, 0.2, 1)
            love.graphics.setLineWidth(3)
        elseif isHovered then
            love.graphics.setColor(1, 1, 1, 0.9)
            love.graphics.setLineWidth(2)
        else
            love.graphics.setColor(0.2, 0.2, 0.2, 1)
            love.graphics.setLineWidth(1)
        end
        love.graphics.rectangle("line", x, y, cardWidth, cardHeight, 6, 6)
        love.graphics.setLineWidth(1)

        -- Key prompt (brighter if hovered)
        local promptColor = isHovered and {1, 1, 0.5, 1} or {1, 1, 0, 1}
        if isGrayed then promptColor = {0.5, 0.5, 0.5, 0.7} end
        love.graphics.setColor(promptColor)
        love.graphics.print("[" .. keyLetters[i] .. "]", x + cardWidth/2 - 10, y + 5)

        -- Card value (large)
        local textColor = isGrayed and {0.6, 0.6, 0.6, 1} or {1, 1, 1, 1}
        love.graphics.setColor(textColor)
        love.graphics.print(tostring(card.value or "?"), x + cardWidth/2 - 5, y + 25)

        -- Suit name
        love.graphics.setColor(isGrayed and {0.5, 0.5, 0.5, 1} or {0.9, 0.9, 0.9, 1})
        local suitName = hand:getSuitName(card.suit)
        love.graphics.print(suitName, x + 5, y + 55)

        -- Card name (may need to truncate)
        local cardName = card.name or "Unknown"
        if #cardName > 12 then
            cardName = string.sub(cardName, 1, 10) .. ".."
        end
        love.graphics.print(cardName, x + 5, y + 75)

        -- Action type
        local actionInfo = hand:getActionsForCard(card)
        if actionInfo then
            love.graphics.setColor(0.7, 0.7, 0.7, 1)
            love.graphics.print(actionInfo.primary, x + 5, y + cardHeight - 25)
        end
    end
end

--- Draw action sequencer visuals
function drawActionVisuals()
    local sequencer = gameState.actionSequencer
    local visuals = sequencer:getActiveVisuals()

    if #visuals == 0 then return end

    local w, h = love.graphics.getDimensions()

    for _, visual in ipairs(visuals) do
        if visual.type == "card_slap" then
            -- Draw card being played
            local cardData = visual.data.card
            if cardData then
                local cardX = w/2 - 60
                local cardY = h/2 - 80 + (1 - visual.progress) * 100

                -- Card background
                love.graphics.setColor(0.9, 0.85, 0.7, visual.progress)
                love.graphics.rectangle("fill", cardX, cardY, 120, 160, 8, 8)

                -- Card border
                love.graphics.setColor(0.3, 0.2, 0.1, visual.progress)
                love.graphics.rectangle("line", cardX, cardY, 120, 160, 8, 8)

                -- Card text
                love.graphics.setColor(0.1, 0.1, 0.1, visual.progress)
                love.graphics.print(cardData.name or "Card", cardX + 10, cardY + 70)
                love.graphics.print("Value: " .. (cardData.value or "?"), cardX + 30, cardY + 100)
            end

        elseif visual.type == "math_overlay" then
            -- Draw calculation
            local data = visual.data
            local text = string.format("%d + %d = %d vs %d",
                data.cardValue or 0,
                data.modifier or 0,
                data.total or 0,
                data.difficulty or 10)

            love.graphics.setColor(0, 0, 0, 0.7 * visual.progress)
            love.graphics.rectangle("fill", w/2 - 100, h/2 + 100, 200, 40)

            love.graphics.setColor(1, 1, 1, visual.progress)
            love.graphics.print(text, w/2 - 80, h/2 + 110)

        elseif visual.type == "damage_result" then
            -- Draw result
            local data = visual.data
            local resultText = data.success and "HIT!" or "MISS!"
            local color = data.success and {0.3, 1, 0.3, visual.progress} or {1, 0.3, 0.3, visual.progress}

            love.graphics.setColor(color)
            love.graphics.print(resultText, w/2 - 30, h/2 + 150)

            if data.damageDealt and data.damageDealt > 0 then
                love.graphics.print(data.damageDealt .. " Wound(s)!", w/2 - 40, h/2 + 175)
            end
        end
    end
end

function love.resize(w, h)
    if gameState.currentScreen then
        gameState.currentScreen:resize(w, h)
    end
end

function love.mousepressed(x, y, button)
    -- S11.3: Loot modal mouse handling (highest priority when open)
    if gameState.lootModal and gameState.lootModal.isOpen then
        if gameState.lootModal:mousepressed(x, y, button) then
            return
        end
    end

    -- S11.1: Character sheet mouse handling (highest priority when open)
    if gameState.characterSheet and gameState.characterSheet.isOpen then
        if gameState.characterSheet:mousepressed(x, y, button) then
            return
        end
    end

    -- S5.4: Right-click to inspect during combat
    if button == 2 and gameState.inspectPanel then
        -- Check if clicking on a guild member (left rail)
        local w, h = love.graphics.getDimensions()
        if x < 200 then  -- Left rail width
            local yOffset = 50 + 10  -- HEADER_HEIGHT + PADDING
            for i, adventurer in ipairs(gameState.guild) do
                local plateY = yOffset + (i - 1) * 80  -- Approximate plate height
                if y >= plateY and y < plateY + 70 then
                    gameState.inspectPanel:show(adventurer, "entity", x, y)
                    return
                end
            end
        end

        -- Check if clicking on an NPC during combat
        if gameState.challengeController and gameState.challengeController:isActive() then
            local npcStartX = w - 220
            local npcStartY = 85
            local npcs = gameState.challengeController.npcs or {}
            for i, npc in ipairs(npcs) do
                local npcY = npcStartY + (i - 1) * 65
                if x >= npcStartX and x < w - 10 and y >= npcY and y < npcY + 60 then
                    gameState.inspectPanel:show(npc, "entity", x, y)
                    return
                end
            end
        end

        -- Hide panel if clicking elsewhere
        gameState.inspectPanel:hide()
    end

    -- S6.4: Minor action panel click handling (highest priority)
    if gameState.minorActionPanel and gameState.minorActionPanel.isVisible then
        if gameState.minorActionPanel:mousepressed(x, y, button) then
            return  -- Minor panel handled the click
        end
    end

    -- S6.2: Command board click handling (highest priority during combat)
    if gameState.commandBoard and gameState.commandBoard.isVisible then
        if gameState.commandBoard:mousepressed(x, y, button) then
            return  -- Command board handled the click
        end
    end

    -- S6.1: Arena view drag handling
    if gameState.arenaView and gameState.arenaView.isVisible then
        if gameState.arenaView:mousepressed(x, y, button) then
            return  -- Arena handled the click
        end
    end

    if gameState.currentScreen then
        gameState.currentScreen:mousepressed(x, y, button)
    end
end

function love.mousereleased(x, y, button)
    -- S11.1: Character sheet drag release
    if gameState.characterSheet and gameState.characterSheet.isOpen then
        if gameState.characterSheet:mousereleased(x, y, button) then
            return
        end
    end

    -- S6.1: Arena view drag release
    if gameState.arenaView and gameState.arenaView.isVisible then
        if gameState.arenaView:mousereleased(x, y, button) then
            return  -- Arena handled the release
        end
    end

    if gameState.currentScreen then
        gameState.currentScreen:mousereleased(x, y, button)
    end
end

function love.mousemoved(x, y, dx, dy)
    -- S11.3: Loot modal hover (highest priority)
    if gameState.lootModal and gameState.lootModal.isOpen then
        gameState.lootModal:mousemoved(x, y, dx, dy)
        return  -- Don't pass to other systems when loot modal is open
    end

    -- S11.1: Character sheet hover
    if gameState.characterSheet and gameState.characterSheet.isOpen then
        gameState.characterSheet:mousemoved(x, y, dx, dy)
        return  -- Don't pass to other systems when sheet is open
    end

    -- S6.4: Minor action panel hover for button
    if gameState.minorActionPanel and gameState.minorActionPanel.isVisible then
        gameState.minorActionPanel:mousemoved(x, y, dx, dy)
    end

    -- S6.2: Command board hover for tooltips
    if gameState.commandBoard and gameState.commandBoard.isVisible then
        gameState.commandBoard:mousemoved(x, y, dx, dy)
    end

    -- S6.1: Arena view hover tracking for drag
    if gameState.arenaView and gameState.arenaView.isVisible then
        gameState.arenaView:mousemoved(x, y, dx, dy)
    end

    if gameState.currentScreen then
        gameState.currentScreen:mousemoved(x, y, dx, dy)
    end
end

function love.keypressed(key)
    -- S11.3: Loot modal keyboard handling (highest priority when open)
    if gameState.lootModal and gameState.lootModal.isOpen then
        if gameState.lootModal:keypressed(key) then
            return  -- Loot modal handled the key
        end
    end

    -- S11.1: Character sheet keyboard handling (highest priority when open)
    if gameState.characterSheet then
        if gameState.characterSheet:keypressed(key) then
            return  -- Character sheet handled the key
        end
    end

    -- S6.4: Minor action panel keyboard handling (highest priority)
    if gameState.minorActionPanel and gameState.minorActionPanel.isVisible then
        if gameState.minorActionPanel:keypressed(key) then
            return  -- Minor panel handled the key
        end
    end

    -- S6.2: Command board keyboard handling
    if gameState.commandBoard and gameState.commandBoard.isVisible then
        if gameState.commandBoard:keypressed(key) then
            return  -- Command board handled the key
        end
    end

    -- ESC to quit (for now, only if no modal is open)
    if key == "escape" then
        love.event.quit()
    end

    -- Debug: D to draw from GM deck
    if key == "d" then
        local result = gameState.watchManager:drawMeatgrinder()
        if result then
            print("Drew: " .. result.card.name .. " (" .. result.value .. ") - " .. result.category)
        end
    end

    -- Debug: M to move party (advance watch)
    if key == "m" then
        local result = gameState.watchManager:incrementWatch()
        print("Watch " .. result.watchNumber .. " passed")
    end

    -- S11.4: Debug keys removed - combat now triggers via meatgrinder, camp via UI button
    -- To test combat manually, uncomment below:
    -- if key == "c" and not gameState.challengeController:isActive() then
    --     startTestCombat()
    -- end

    -- Camp is now triggered via the "Make Camp" button in the right rail
    -- if key == "k" and gameState.phase == "crawl" and not gameState.challengeController:isActive() then
    --     startCampPhase()
    -- end

    -- X to exit dungeon / end expedition (S10.1)
    if key == "x" and gameState.phase == "crawl" and not gameState.challengeController:isActive() then
        -- Only allow exit from entrance room
        local currentRoom = gameState.watchManager:getCurrentRoom()
        if currentRoom == "101_entrance" then
            showEndOfDemoScreen("exited")
        else
            print("[EXIT] You can only exit from the entrance room!")
        end
    end

    -- Challenge phase input
    if gameState.challengeController and gameState.challengeController:isActive() then
        handleChallengeInput(key)
        return  -- Don't pass to screen during combat
    end

    -- Pass to screen
    if gameState.currentScreen then
        gameState.currentScreen:keypressed(key)
    end
end

```

---

## File: src/data/action_registry.lua

```lua
-- action_registry.lua
-- Data registry of all actions for Majesty
-- Ticket S6.2: Categorized Command Board
--
-- Defines all actions from the rulebook (p. 116-120) with their suit tags,
-- attributes, and descriptions.

local M = {}

--------------------------------------------------------------------------------
-- SUIT CONSTANTS
--------------------------------------------------------------------------------
M.SUITS = {
    SWORDS    = "swords",
    PENTACLES = "pentacles",
    CUPS      = "cups",
    WANDS     = "wands",
    MISC      = "misc",  -- Miscellaneous (any suit)
}

--------------------------------------------------------------------------------
-- ACTION DEFINITIONS
--------------------------------------------------------------------------------
-- Each action has:
--   id            - Unique identifier
--   name          - Display name
--   suit          - Required suit (SWORDS, PENTACLES, CUPS, WANDS, or MISC)
--   attribute     - Stat added to card value (swords, pentacles, cups, wands)
--   description   - Short description for tooltip
--   allowMinor    - Whether this can be used as a Minor Action (default: true for suit-matched)
--   requiresTarget - Whether a target is needed

M.ACTIONS = {
    ----------------------------------------------------------------------------
    -- SWORDS (Combat / Physical Aggression)
    ----------------------------------------------------------------------------
    {
        id = "melee",
        name = "Attack (Melee)",
        suit = M.SUITS.SWORDS,
        attribute = "swords",
        description = "Strike an enemy in your zone with a melee weapon.",
        requiresTarget = true,
        targetType = "enemy",
    },
    {
        id = "missile",
        name = "Attack (Ranged)",
        suit = M.SUITS.SWORDS,
        attribute = "swords",
        description = "Fire at an enemy in range with a ranged weapon.",
        requiresTarget = true,
        targetType = "enemy",
        requiresWeaponType = "ranged",
    },
    {
        id = "grapple",
        name = "Grapple",
        suit = M.SUITS.SWORDS,
        attribute = "swords",
        description = "Seize an enemy. Success engages and prevents their movement.",
        requiresTarget = true,
        targetType = "enemy",
    },
    {
        id = "intimidate",
        name = "Intimidate",
        suit = M.SUITS.SWORDS,
        attribute = "swords",
        description = "Threaten an enemy to reduce their morale.",
        requiresTarget = true,
        targetType = "enemy",
    },

    ----------------------------------------------------------------------------
    -- PENTACLES (Agility / Technical Skill)
    ----------------------------------------------------------------------------
    {
        id = "avoid",
        name = "Avoid",
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        description = "Prepare to dodge an incoming attack. Also clears engagement safely.",
        requiresTarget = false,
    },
    {
        id = "trip",
        name = "Trip",
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        description = "Knock an enemy prone, reducing their defense.",
        requiresTarget = true,
        targetType = "enemy",
    },
    {
        id = "disarm",
        name = "Disarm",
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        description = "Remove an item from an enemy's hands.",
        requiresTarget = true,
        targetType = "enemy",
    },
    {
        id = "displace",
        name = "Displace",
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        description = "Push an enemy to an adjacent zone.",
        requiresTarget = true,
        targetType = "enemy",
    },
    {
        id = "pick_lock",
        name = "Pick Lock",
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        description = "Attempt to open a locked door or container.",
        requiresTarget = false,
        requiresItem = "lockpicks",
    },
    {
        id = "disarm_trap",
        name = "Disarm Trap",
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        description = "Safely disarm a detected trap.",
        requiresTarget = false,
    },
    {
        id = "dash",
        name = "Dash",
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        description = "Move quickly through a zone, potentially avoiding obstacles.",
        requiresTarget = false,
    },

    ----------------------------------------------------------------------------
    -- CUPS (Social / Emotional / Defense)
    ----------------------------------------------------------------------------
    {
        id = "defend",
        name = "Defend",
        suit = M.SUITS.CUPS,
        attribute = "cups",
        description = "Take a defensive stance, gaining +2 to defense until your next turn.",
        requiresTarget = false,
    },
    {
        id = "dodge",
        name = "Dodge",
        suit = M.SUITS.CUPS,
        attribute = "cups",
        description = "Prepare to dodge. Card value adds to defense difficulty when attacked.",
        requiresTarget = false,
    },
    {
        id = "riposte",
        name = "Riposte",
        suit = M.SUITS.CUPS,
        attribute = "cups",
        description = "Prepare to counter-attack. If attacked, strike back with this card.",
        requiresTarget = false,
    },
    {
        id = "heal",
        name = "Heal",
        suit = M.SUITS.CUPS,
        attribute = "cups",
        description = "Attempt to heal a wound on yourself or an ally.",
        requiresTarget = true,
        targetType = "ally",
    },
    {
        id = "parley",
        name = "Parley",
        suit = M.SUITS.CUPS,
        attribute = "cups",
        description = "Attempt to negotiate or reason with an NPC.",
        requiresTarget = true,
        targetType = "any",
    },
    {
        id = "rally",
        name = "Rally",
        suit = M.SUITS.CUPS,
        attribute = "cups",
        description = "Inspire an ally, removing a condition or boosting morale.",
        requiresTarget = true,
        targetType = "ally",
    },
    {
        id = "aid",
        name = "Aid Another",
        suit = M.SUITS.CUPS,
        attribute = "cups",
        description = "Bank a bonus for an ally's next action (card value + Cups).",
        requiresTarget = true,
        targetType = "ally",
    },

    ----------------------------------------------------------------------------
    -- WANDS (Magic / Perception)
    ----------------------------------------------------------------------------
    {
        id = "cast",
        name = "Cast Spell",
        suit = M.SUITS.WANDS,
        attribute = "wands",
        description = "Channel a prepared spell effect.",
        requiresTarget = false,  -- Depends on spell
    },
    {
        id = "banter",
        name = "Banter",
        suit = M.SUITS.WANDS,
        attribute = "wands",
        description = "Distract an enemy with wit, reducing their next action's effectiveness.",
        requiresTarget = true,
        targetType = "enemy",
    },
    {
        id = "investigate",
        name = "Investigate",
        suit = M.SUITS.WANDS,
        attribute = "wands",
        description = "Search for hidden details, secrets, or clues.",
        requiresTarget = false,
    },
    {
        id = "detect_magic",
        name = "Detect Magic",
        suit = M.SUITS.WANDS,
        attribute = "wands",
        description = "Sense magical auras or enchantments nearby.",
        requiresTarget = false,
    },
    {
        id = "recover",
        name = "Recover",
        suit = M.SUITS.WANDS,
        attribute = "wands",
        description = "Clear a negative status effect (rooted, prone, blind, deaf, disarmed).",
        requiresTarget = false,
    },

    ----------------------------------------------------------------------------
    -- MISCELLANEOUS (Any Suit on Primary Turn)
    ----------------------------------------------------------------------------
    {
        id = "move",
        name = "Move",
        suit = M.SUITS.MISC,
        attribute = nil,  -- No stat added
        description = "Move to an adjacent zone. No test required unless obstacles.",
        requiresTarget = false,
        allowMinor = false,  -- Cannot be a Minor action (normally)
    },
    {
        id = "pull_item",
        name = "Pull Item",
        suit = M.SUITS.MISC,
        attribute = nil,
        description = "Ready an item from your pack to your belt.",
        requiresTarget = false,
        allowMinor = false,
    },
    {
        id = "use_item",
        name = "Use Item",
        suit = M.SUITS.MISC,
        attribute = nil,  -- Depends on item
        description = "Activate an item's special ability.",
        requiresTarget = false,
        allowMinor = false,
    },
    {
        id = "interact",
        name = "Interact",
        suit = M.SUITS.MISC,
        attribute = nil,
        description = "Interact with the environment (pull lever, open door, etc.)",
        requiresTarget = false,
        allowMinor = false,
    },
    {
        id = "reload",
        name = "Reload",
        suit = M.SUITS.MISC,
        attribute = nil,
        description = "Reload a crossbow (required after each shot).",
        requiresTarget = false,
        allowMinor = false,
        requiresWeaponType = "crossbow",
    },
}

--------------------------------------------------------------------------------
-- LOOKUP TABLES (built at load time)
--------------------------------------------------------------------------------

M.byId = {}
M.bySuit = {
    [M.SUITS.SWORDS] = {},
    [M.SUITS.PENTACLES] = {},
    [M.SUITS.CUPS] = {},
    [M.SUITS.WANDS] = {},
    [M.SUITS.MISC] = {},
}

-- Build lookup tables
for _, action in ipairs(M.ACTIONS) do
    M.byId[action.id] = action
    if M.bySuit[action.suit] then
        table.insert(M.bySuit[action.suit], action)
    end
end

--------------------------------------------------------------------------------
-- QUERY FUNCTIONS
--------------------------------------------------------------------------------

--- Get an action by ID
function M.getAction(actionId)
    return M.byId[actionId]
end

--- Get all actions for a suit
function M.getActionsForSuit(suit)
    return M.bySuit[suit] or {}
end

--- Get actions available for a given card and context
-- @param card table: The card being played (with .suit field)
-- @param isPrimaryTurn boolean: True if this is the entity's primary turn
-- @param entity table: The acting entity (to check requirements)
-- @return table: Array of available action definitions
function M.getAvailableActions(card, isPrimaryTurn, entity)
    local available = {}
    local cardSuit = M.cardSuitToActionSuit(card.suit)

    for _, action in ipairs(M.ACTIONS) do
        local canUse = false

        if isPrimaryTurn then
            -- On primary turn, any action is available
            canUse = true
        else
            -- On minor turn, only suit-matched actions (excluding misc)
            if action.suit == cardSuit and action.allowMinor ~= false then
                canUse = true
            end
        end

        -- Check additional requirements
        if canUse and action.requiresWeaponType then
            if not entity or not entity.weapon or entity.weapon.type ~= action.requiresWeaponType then
                canUse = false
            end
        end

        if canUse and action.requiresItem then
            -- Check if entity has required item
            if entity and entity.inventory then
                local hasItem = entity.inventory:hasItemOfType(action.requiresItem)
                if not hasItem then
                    canUse = false
                end
            else
                canUse = false
            end
        end

        if canUse then
            available[#available + 1] = action
        end
    end

    return available
end

--- Convert card deck suit number to action suit string
-- Card suits: 1=Swords, 2=Pentacles, 3=Cups, 4=Wands, nil/0=Major Arcana
function M.cardSuitToActionSuit(cardSuit)
    local suitMap = {
        [1] = M.SUITS.SWORDS,
        [2] = M.SUITS.PENTACLES,
        [3] = M.SUITS.CUPS,
        [4] = M.SUITS.WANDS,
    }
    return suitMap[cardSuit] or M.SUITS.MISC
end

--- Get the display name for a suit
function M.getSuitDisplayName(suit)
    local names = {
        [M.SUITS.SWORDS]    = "Swords",
        [M.SUITS.PENTACLES] = "Pentacles",
        [M.SUITS.CUPS]      = "Cups",
        [M.SUITS.WANDS]     = "Wands",
        [M.SUITS.MISC]      = "Misc",
    }
    return names[suit] or suit
end

--- Calculate the total value for an action
-- @param card table: The card being played
-- @param action table: The action definition
-- @param entity table: The acting entity
-- @return number: Card value + attribute (if any)
function M.calculateTotal(card, action, entity)
    local cardValue = card.value or 0

    if action.attribute and entity then
        local attrValue = entity[action.attribute] or 0
        return cardValue + attrValue
    end

    return cardValue
end

return M

```

---

## File: src/data/blueprints/mobs.lua

```lua
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
        armorSlots = 0,
        talentWoundSlots = 0,  -- Skeletons don't have talents to wound
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
        armorSlots = 0,
        talentWoundSlots = 0,
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
        armorSlots = 0,
        talentWoundSlots = 0,
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
        armorSlots = 0,
        talentWoundSlots = 1,
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
        armorSlots = 0,
        talentWoundSlots = 0,
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
        armorSlots = 3,  -- Heavy armor
        talentWoundSlots = 2,
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
        armorSlots = 1,  -- Chitinous hide
        talentWoundSlots = 1,
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
        armorSlots = 0,  -- Already dried and dead
        talentWoundSlots = 0,
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
        armorSlots = 1,  -- Hard carapace
        talentWoundSlots = 0,
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
        armorSlots = 2,  -- Reinforced carapace
        talentWoundSlots = 3,
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

}

return M

```

---

## File: src/data/blueprints/rooms.lua

```lua
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

```

---

## File: src/data/camp_prompts.lua

```lua
-- camp_prompts.lua
-- Campfire Discussion Prompts for Majesty
-- Ticket S9.3: Fellowship roleplay prompts
--
-- Reference: Rulebook pg. 189 "Campfire Discussions"
-- These prompts encourage character development and party bonding.

local M = {}

--------------------------------------------------------------------------------
-- DISCUSSION PROMPTS
-- Each prompt is a question to spark roleplay between characters
--------------------------------------------------------------------------------

M.PROMPTS = {
    -- Personal History
    "What is your earliest memory?",
    "What is your greatest achievement?",
    "What is your deepest regret?",
    "Where did you grow up, and what was it like?",
    "Who taught you your trade or skills?",
    "What drove you to become an adventurer?",
    "Have you ever been in love?",
    "What is the worst thing you've ever done?",
    "What is the kindest thing anyone has ever done for you?",
    "What do you miss most about home?",

    -- Dreams and Fears
    "What do you dream of at night?",
    "What is your greatest fear?",
    "If you could change one thing about your past, what would it be?",
    "What would you do if you found a fortune in the dungeon?",
    "How do you want to be remembered?",
    "What keeps you going when things seem hopeless?",
    "What would make you abandon the guild?",
    "What do you think happens after death?",
    "Is there anyone you would die for?",
    "What scares you more: dying alone, or dying forgotten?",

    -- Beliefs and Values
    "Do you believe in the gods? Which ones?",
    "What is the most important virtue a person can have?",
    "Is there such a thing as a justified lie?",
    "When is violence the right answer?",
    "What do you think of the Crown and its laws?",
    "Is there honor among thieves?",
    "Would you sacrifice one life to save many?",
    "What do you think of magic and those who wield it?",
    "Is revenge ever justified?",
    "What makes someone truly evil?",

    -- Relationships
    "What do you think of the others in our guild?",
    "Who do you trust most in this group?",
    "Have you ever betrayed someone's trust?",
    "What would you never forgive?",
    "Do you have any living family?",
    "Who was your best friend growing up?",
    "Have you ever lost someone close to you?",
    "What makes a true friend?",
    "Is there anyone from your past you wish you could see again?",
    "Who is your greatest enemy?",

    -- The Dungeon
    "What is the strangest thing you've seen in the Underworld?",
    "Do you think we'll ever find what we're looking for down here?",
    "What do you think created these dungeons?",
    "Have you ever felt pity for a monster?",
    "What treasure would make all this worth it?",
    "Do you think we'll make it out alive?",
    "What do you think about when you're on watch?",
    "What's the first thing you'll do when we return to the surface?",
    "Have you ever been tempted by something you found in the depths?",
    "What's the most dangerous situation you've survived?",
}

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------

--- Get a random prompt (seeded for determinism)
-- @param seed number: Optional seed for reproducibility
-- @return string: A random discussion prompt
function M.getRandomPrompt(seed)
    if seed then
        math.randomseed(seed)
    end
    local index = math.random(1, #M.PROMPTS)
    return M.PROMPTS[index]
end

--- Get a specific prompt by index
-- @param index number: 1-based index
-- @return string: The prompt at that index
function M.getPrompt(index)
    return M.PROMPTS[index] or M.PROMPTS[1]
end

--- Get the total number of prompts
function M.getPromptCount()
    return #M.PROMPTS
end

return M

```

---

## File: src/data/item_templates.lua

```lua
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

    ----------------------------------------------------------------------------
    -- LIGHT SOURCES
    ----------------------------------------------------------------------------

    torch = {
        name = "Torch",
        size = 1,
        durability = 1,
        properties = { flicker_count = 3, light_source = true },
    },

    lantern = {
        name = "Lantern",
        size = 1,
        durability = 2,
        properties = { flicker_count = 6, light_source = true },
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

    healing_potion = {
        name = "Healing Potion",
        size = 1,
        durability = 1,
        properties = { potion = true, effect = "heal_wound" },
    },

    antidote = {
        name = "Antidote",
        size = 1,
        durability = 1,
        properties = { potion = true, effect = "cure_poison" },
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

    tinkers_kit = {
        name = "Tinker's Kit",
        size = 1,
        durability = 3,
        properties = { tool = true, toolType = "tinker" },
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

    ----------------------------------------------------------------------------
    -- MISCELLANEOUS
    ----------------------------------------------------------------------------

    waterskin = {
        name = "Waterskin",
        size = 1,
        durability = 1,
        properties = { water_container = true, charges = 3 },
    },

    bedroll = {
        name = "Bedroll",
        size = 2,
        properties = { camping = true },
    },

    tent = {
        name = "Tent",
        size = 2,
        oversized = true,
        properties = { camping = true, shelter = true },
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

```

---

## File: src/data/maps/tomb_of_golden_ghosts.lua

```lua
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
                },
                {
                    id = "west_mural",
                    name = "faded mural",
                    type = "decoration",
                    description = "A mural depicting a robed sorcerer observing the night sky. Stars and constellations surround him.",
                    hidden_description = "One star in the mural seems slightly raised from the wall...",
                    secrets = "Pressing the raised star reveals a hidden latch! A secret door swings open.",
                    investigate_test = { attribute = "pentacles", difficulty = 12 },
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

```

---

## File: src/data/maps/tutorial_level.lua

```lua
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

```

---

## File: src/entities/adventurer.lua

```lua
-- adventurer.lua
-- Adventurer Schema (PC Specialization) for Majesty
-- Ticket T1_6: Extends Entity with Resolve, Motifs, Bonds, Talents
--
-- Design: Composition over inheritance.
-- An Adventurer wraps a base Entity and adds PC-specific components.

local base_entity = require('entities.base_entity')

local M = {}

--------------------------------------------------------------------------------
-- BOND STATUS CONSTANTS
--------------------------------------------------------------------------------
M.BOND_STATUS = {
    LOVE            = "love",
    GUARDIANSHIP    = "guardianship",
    RIVALRY         = "rivalry",
    FRIENDSHIP      = "friendship",
    UNREQUITED_LOVE = "unrequited_love",
    DEBT            = "debt",
}

--------------------------------------------------------------------------------
-- ADVENTURER FACTORY
--------------------------------------------------------------------------------

--- Create a new Adventurer (Player Character)
-- @param config table: Entity config plus PC-specific fields
-- @return Adventurer instance (Entity + PC components)
function M.createAdventurer(config)
    config = config or {}

    -- Create base entity first
    local adventurer = base_entity.createEntity(config)

    -- Mark as player character
    adventurer.isPC = true

    ----------------------------------------------------------------------------
    -- RESOLVE
    -- Default 4/4, but max is mutable (War Stories talent allows 5)
    ----------------------------------------------------------------------------
    adventurer.resolve = {
        current = config.resolve or 4,
        max     = config.resolveMax or 4,
    }

    --- Spend resolve points
    -- @param amount number: How much to spend
    -- @return boolean: true if successful, false if insufficient
    function adventurer:spendResolve(amount)
        amount = amount or 1
        if self.resolve.current < amount then
            return false, "insufficient_resolve"
        end
        self.resolve.current = self.resolve.current - amount
        return true
    end

    --- Regain resolve points (capped at max)
    function adventurer:regainResolve(amount)
        amount = amount or 1
        self.resolve.current = math.min(
            self.resolve.current + amount,
            self.resolve.max
        )
        return self
    end

    --- Check if resolve is available
    function adventurer:hasResolve(amount)
        amount = amount or 1
        return self.resolve.current >= amount
    end

    --- Set max resolve (for talents like War Stories)
    function adventurer:setMaxResolve(newMax)
        self.resolve.max = newMax
        -- Don't exceed new max
        if self.resolve.current > newMax then
            self.resolve.current = newMax
        end
        return self
    end

    ----------------------------------------------------------------------------
    -- MOTIFS
    -- Strings representing character background (Failed Career, Origin, etc.)
    -- Used for Favor on related tests
    ----------------------------------------------------------------------------
    adventurer.motifs = config.motifs or {}

    --- Add a motif
    function adventurer:addMotif(motif)
        self.motifs[#self.motifs + 1] = motif
        return self
    end

    --- Check if adventurer has a motif (case-insensitive partial match)
    function adventurer:hasMotif(searchTerm)
        local searchLower = string.lower(searchTerm)
        for _, motif in ipairs(self.motifs) do
            if string.find(string.lower(motif), searchLower, 1, true) then
                return true, motif
            end
        end
        return false
    end

    --- Get all motifs
    function adventurer:getMotifs()
        return self.motifs
    end

    ----------------------------------------------------------------------------
    -- BONDS
    -- Maps entity_id -> { status, charged }
    -- Bonds power rest/recovery mechanics
    ----------------------------------------------------------------------------
    adventurer.bonds = config.bonds or {}

    --- Create or update a bond with another entity
    -- @param entityId string: The other entity's ID
    -- @param status string: One of BOND_STATUS constants
    function adventurer:setBond(entityId, status)
        if not self.bonds[entityId] then
            self.bonds[entityId] = { status = status, charged = false }
        else
            self.bonds[entityId].status = status
        end
        return self
    end

    --- Charge a bond (usually during Crawl phase)
    function adventurer:chargeBond(entityId)
        if self.bonds[entityId] then
            self.bonds[entityId].charged = true
            return true
        end
        return false
    end

    --- Spend a charged bond (during Camp phase for healing)
    -- @return boolean: true if bond was charged and is now spent
    function adventurer:spendBond(entityId)
        if self.bonds[entityId] and self.bonds[entityId].charged then
            self.bonds[entityId].charged = false
            return true
        end
        return false
    end

    --- Check if a bond is charged
    function adventurer:isBondCharged(entityId)
        return self.bonds[entityId] and self.bonds[entityId].charged or false
    end

    --- Get bond info
    function adventurer:getBond(entityId)
        return self.bonds[entityId]
    end

    --- Count charged bonds
    function adventurer:countChargedBonds()
        local count = 0
        for _, bond in pairs(self.bonds) do
            if bond.charged then
                count = count + 1
            end
        end
        return count
    end

    ----------------------------------------------------------------------------
    -- TALENTS
    -- Maps talent_id -> { mastered, wounded, xp_invested }
    -- NO hardcoded talent logic here - just data storage
    -- ChallengeManager will look up what talents actually do
    ----------------------------------------------------------------------------
    adventurer.talents = config.talents or {}

    --- Add a talent
    -- @param talentId string: The talent's ID (e.g., "aegis", "war_stories")
    -- @param mastered boolean: Whether it's mastered (default false = in training)
    function adventurer:addTalent(talentId, mastered)
        self.talents[talentId] = {
            mastered    = mastered or false,
            wounded     = false,
            xp_invested = 0,
        }
        return self
    end

    --- Check if adventurer has a talent
    function adventurer:hasTalent(talentId)
        return self.talents[talentId] ~= nil
    end

    --- Check if talent is mastered
    function adventurer:isTalentMastered(talentId)
        return self.talents[talentId] and self.talents[talentId].mastered or false
    end

    --- Check if talent is wounded
    function adventurer:isTalentWounded(talentId)
        return self.talents[talentId] and self.talents[talentId].wounded or false
    end

    --- Check if talent is usable (has it, mastered or in-training, not wounded)
    function adventurer:canUseTalent(talentId)
        local talent = self.talents[talentId]
        if not talent then return false end
        if talent.wounded then return false end
        return true
    end

    --- Wound a specific talent
    function adventurer:woundTalent(talentId)
        if self.talents[talentId] then
            self.talents[talentId].wounded = true
            return true
        end
        return false
    end

    --- Heal a specific talent
    function adventurer:healTalent(talentId)
        if self.talents[talentId] then
            self.talents[talentId].wounded = false
            return true
        end
        return false
    end

    --- Invest XP in a talent
    function adventurer:investXP(talentId, amount)
        if self.talents[talentId] then
            self.talents[talentId].xp_invested =
                self.talents[talentId].xp_invested + amount
            return true
        end
        return false
    end

    --- Master a talent (usually after enough XP)
    function adventurer:masterTalent(talentId)
        if self.talents[talentId] then
            self.talents[talentId].mastered = true
            return true
        end
        return false
    end

    --- Get list of wounded talent IDs
    function adventurer:getWoundedTalents()
        local wounded = {}
        for id, talent in pairs(self.talents) do
            if talent.wounded then
                wounded[#wounded + 1] = id
            end
        end
        return wounded
    end

    return adventurer
end

return M

```

---

## File: src/entities/base_entity.lua

```lua
-- base_entity.lua
-- Base Entity Component for Majesty
-- Ticket T1_5: Generic entity that can act or take damage
--
-- Design: Component tables, NOT deep inheritance.
-- An Adventurer is just an Entity + Bonds + Resolve, etc.

local M = {}

-- Import SUITS for attribute mapping
local constants = require('constants')
local SUITS = constants.SUITS

--------------------------------------------------------------------------------
-- CONDITION CONSTANTS
-- Using simple booleans for easy UI queries ("Red Flashing" effects)
--------------------------------------------------------------------------------
M.CONDITIONS = {
    STRESSED    = "stressed",
    STAGGERED   = "staggered",
    INJURED     = "injured",
    DEATHS_DOOR = "deaths_door",
}

--------------------------------------------------------------------------------
-- ENTITY FACTORY
--------------------------------------------------------------------------------

local nextId = 0

--- Create a new Entity
-- @param config table: { name, attributes, location, ... }
-- @return Entity instance
function M.createEntity(config)
    config = config or {}

    nextId = nextId + 1

    local entity = {
        -- Identity
        id   = config.id or ("entity_" .. nextId),
        name = config.name or "Unknown",

        -- Attributes: SUIT -> value (1-4 for PCs, 0-6 for NPCs)
        attributes = {
            [SUITS.SWORDS]    = config.swords or config.attributes and config.attributes[SUITS.SWORDS] or 1,
            [SUITS.PENTACLES] = config.pentacles or config.attributes and config.attributes[SUITS.PENTACLES] or 1,
            [SUITS.CUPS]      = config.cups or config.attributes and config.attributes[SUITS.CUPS] or 1,
            [SUITS.WANDS]     = config.wands or config.attributes and config.attributes[SUITS.WANDS] or 1,
        },

        -- Shorthand attribute access (for convenient entity.swords style access)
        swords    = config.swords or config.attributes and config.attributes[SUITS.SWORDS] or 1,
        pentacles = config.pentacles or config.attributes and config.attributes[SUITS.PENTACLES] or 1,
        cups      = config.cups or config.attributes and config.attributes[SUITS.CUPS] or 1,
        wands     = config.wands or config.attributes and config.attributes[SUITS.WANDS] or 1,

        -- Conditions: simple booleans for UI transparency
        conditions = {
            stressed    = false,
            staggered   = false,
            injured     = false,
            deaths_door = false,
            dead        = false,  -- Terminal state
        },

        -- Protection slots (for wound absorption)
        armorSlots = config.armorSlots or 0,  -- How many armor notches available
        armorNotches = 0,                      -- Current notches taken

        talentWoundSlots = config.talentWoundSlots or 2,  -- Max wounded talents (usually 2)
        woundedTalents = 0,                                -- Current wounded talents

        -- Talents table (empty for base mobs, populated for adventurers)
        -- Used to verify there are actual talents to wound
        talents = config.talents or {},

        -- Location reference (Room ID)
        location = config.location or nil,

        -- Zone within current room (T2_3)
        -- Simple assignment: entity.zone = "Balcony" (no coordinate systems)
        zone = config.zone or "main",

        -- Defensive action slot (S4.9)
        -- Holds a prepared defense: { type = "dodge"|"riposte", card = {...} }
        pendingDefense = nil,
    }

    ----------------------------------------------------------------------------
    -- ATTRIBUTE ACCESS
    ----------------------------------------------------------------------------

    function entity:getAttribute(suit)
        return self.attributes[suit] or 0
    end

    function entity:setAttribute(suit, value)
        self.attributes[suit] = value
        return self
    end

    ----------------------------------------------------------------------------
    -- ZONE ACCESS (T2_3)
    ----------------------------------------------------------------------------

    function entity:getZone()
        return self.zone
    end

    function entity:setZone(zoneId)
        self.zone = zoneId
        return self
    end

    ----------------------------------------------------------------------------
    -- DEFENSIVE ACTIONS (S4.9)
    ----------------------------------------------------------------------------

    --- Prepare a defensive action for later in the round
    -- @param defenseType string: "dodge" or "riposte"
    -- @param card table: The card being used
    -- @return boolean: success
    function entity:prepareDefense(defenseType, card)
        if self.pendingDefense then
            return false, "already_has_defense"
        end

        self.pendingDefense = {
            type = defenseType,
            card = card,
            value = card.value or 0,
        }
        return true
    end

    --- Check if entity has a pending defense
    function entity:hasDefense()
        return self.pendingDefense ~= nil
    end

    --- Get the pending defense
    function entity:getDefense()
        return self.pendingDefense
    end

    --- Consume (use up) the pending defense
    -- @return table|nil: The defense that was consumed
    function entity:consumeDefense()
        local defense = self.pendingDefense
        self.pendingDefense = nil
        return defense
    end

    --- Clear the pending defense without using it
    function entity:clearDefense()
        self.pendingDefense = nil
    end

    ----------------------------------------------------------------------------
    -- CONDITION QUERIES (for UI)
    ----------------------------------------------------------------------------

    function entity:isStressed()
        return self.conditions.stressed
    end

    function entity:isStaggered()
        return self.conditions.staggered
    end

    function entity:isInjured()
        return self.conditions.injured
    end

    function entity:isAtDeathsDoor()
        return self.conditions.deaths_door
    end

    function entity:isAlive()
        return not self.conditions.deaths_door
    end

    ----------------------------------------------------------------------------
    -- CONDITION SETTERS
    ----------------------------------------------------------------------------

    function entity:setCondition(condition, value)
        if self.conditions[condition] ~= nil then
            self.conditions[condition] = value
        end
        return self
    end

    function entity:clearCondition(condition)
        return self:setCondition(condition, false)
    end

    ----------------------------------------------------------------------------
    -- TAKE WOUND (S7.7: Updated with damage types)
    -- Priority order: Notch Armor → Wound Talent → Staggered → Injured → Death's Door
    -- Returns: string describing what absorbed the wound, or nil if dead
    -- @param damageType string|boolean: "normal", "piercing", "critical", or legacy boolean
    --   - "normal" (or false/nil): Standard damage, full cascade
    --   - "piercing" (or true): Skip armor, start at talents
    --   - "critical": Skip armor, talents, staggered - go straight to injured
    ----------------------------------------------------------------------------

    function entity:takeWound(damageType)
        -- Handle legacy boolean parameter (true = piercing)
        if damageType == true then
            damageType = "piercing"
        elseif not damageType or damageType == false then
            damageType = "normal"
        end

        -- S7.7: Critical damage skips armor, talents, and staggered
        if damageType == "critical" then
            -- Go straight to injured cascade
            if not self.conditions.injured then
                self.conditions.injured = true
                return "injured"
            end

            if not self.conditions.deaths_door then
                self.conditions.deaths_door = true
                return "deaths_door"
            end

            self.conditions.dead = true
            return "dead"
        end

        -- Priority 1: Notch Armor (if available and not piercing/critical)
        if damageType == "normal" and self.armorSlots > 0 and self.armorNotches < self.armorSlots then
            self.armorNotches = self.armorNotches + 1
            return "armor_notched"
        end

        -- Priority 2: Wound a Talent (up to max, usually 2)
        -- Must have actual talents to wound, not just empty slots
        local talentCount = self.talents and #self.talents or 0
        if self.woundedTalents < self.talentWoundSlots and talentCount > 0 and self.woundedTalents < talentCount then
            self.woundedTalents = self.woundedTalents + 1
            return "talent_wounded"
        end

        -- Priority 3: Mark Staggered (if not already)
        if not self.conditions.staggered then
            self.conditions.staggered = true
            return "staggered"
        end

        -- Priority 4: Mark Injured (if not already)
        if not self.conditions.injured then
            self.conditions.injured = true
            return "injured"
        end

        -- Priority 5: Mark Death's Door
        if not self.conditions.deaths_door then
            self.conditions.deaths_door = true
            return "deaths_door"
        end

        -- Already at Death's Door - this wound is fatal
        self.conditions.dead = true
        return "dead"
    end

    ----------------------------------------------------------------------------
    -- HEALING
    -- Note: Stress is a "Recovery Gate" (p. 31) - must clear stress first
    ----------------------------------------------------------------------------

    --- Attempt to heal a wound
    -- @return string, string: result, errorReason (if blocked by stress)
    function entity:healWound()
        -- Stress Gate Check (p. 31): Cannot clear any condition until stressed is removed
        if self.conditions.stressed then
            return nil, "must_clear_stress_first"
        end

        -- Reverse priority: Death's Door → Injured → Staggered → Talents → Armor
        if self.conditions.deaths_door then
            self.conditions.deaths_door = false
            return "deaths_door_healed", nil
        end

        if self.conditions.injured then
            self.conditions.injured = false
            return "injured_healed", nil
        end

        if self.conditions.staggered then
            self.conditions.staggered = false
            return "staggered_healed", nil
        end

        if self.woundedTalents > 0 then
            self.woundedTalents = self.woundedTalents - 1
            return "talent_healed", nil
        end

        if self.armorNotches > 0 then
            self.armorNotches = self.armorNotches - 1
            return "armor_repaired", nil
        end

        return "fully_healed", nil
    end

    --- Clear stress condition (separate from wound healing)
    -- Stress must be cleared before other conditions can heal
    function entity:clearStress()
        if self.conditions.stressed then
            self.conditions.stressed = false
            return true
        end
        return false
    end

    ----------------------------------------------------------------------------
    -- UTILITY
    ----------------------------------------------------------------------------

    --- Get count of available wound absorption slots
    function entity:remainingProtection()
        local remaining = 0

        -- Armor slots
        remaining = remaining + (self.armorSlots - self.armorNotches)

        -- Talent wound slots (limited by actual talent count)
        local talentCount = self.talents and #self.talents or 0
        local availableTalentSlots = math.min(self.talentWoundSlots, talentCount)
        remaining = remaining + (availableTalentSlots - self.woundedTalents)

        -- Condition slots (staggered, injured)
        if not self.conditions.staggered then remaining = remaining + 1 end
        if not self.conditions.injured then remaining = remaining + 1 end

        return remaining
    end

    --- How many wounds until death?
    function entity:woundsUntilDeath()
        if self.conditions.deaths_door then
            return 0
        end
        return self:remainingProtection() + 1  -- +1 for death's door itself
    end

    return entity
end

return M

```

---

## File: src/entities/factory.lua

```lua
-- factory.lua
-- Entity Factory (The Spawner) for Majesty
-- Ticket T1_8: Centralized factory using data-driven blueprints
--
-- Design: Data-driven, not code-driven.
-- Add new monsters by editing blueprints, not by writing new functions.

--------------------------------------------------------------------------------
-- DEPENDENCIES
--------------------------------------------------------------------------------
local base_entity = require('base_entity')
local adventurer_module = require('adventurer')
local inventory = require('inventory')
local mob_blueprints = require('blueprints.mobs')

local M = {}

--------------------------------------------------------------------------------
-- BLUEPRINT REGISTRY
-- Combine all blueprint sources into one lookup table
--------------------------------------------------------------------------------
local blueprints = {}

-- Load mob blueprints
for id, blueprint in pairs(mob_blueprints.blueprints) do
    blueprints[id] = blueprint
end

--- Register additional blueprints (for expansion packs, custom content)
function M.registerBlueprint(id, blueprint)
    blueprints[id] = blueprint
end

--- Check if a blueprint exists
function M.hasBlueprint(id)
    return blueprints[id] ~= nil
end

--- List all available blueprint IDs
function M.listBlueprints()
    local ids = {}
    for id, _ in pairs(blueprints) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end

--------------------------------------------------------------------------------
-- ITEM INSTANTIATION
-- Create actual item instances from gear templates
--------------------------------------------------------------------------------
local function instantiateGear(gearList)
    local items = {}
    for _, template in ipairs(gearList or {}) do
        local item = inventory.createItem({
            name       = template.name,
            size       = template.size or inventory.SIZE.NORMAL,
            durability = template.durability or inventory.DURABILITY.NORMAL,
            oversized  = template.oversized or false,
            stackable  = template.stackable or false,
            stackSize  = template.stackSize or 1,
            quantity   = template.quantity or 1,
            isArmor    = template.isArmor or false,
            properties = template.properties or {},
        })
        items[#items + 1] = item
    end
    return items
end

--------------------------------------------------------------------------------
-- CREATE ENTITY (NPCs / Mobs)
-- Data-driven: looks up template_id in blueprints table
--------------------------------------------------------------------------------

--- Create an NPC entity from a blueprint
-- @param template_id string: Blueprint ID (e.g., "skeleton_brute")
-- @param overrides table: Optional overrides for specific properties
-- @return Entity with inventory and starting gear, or nil if blueprint not found
function M.createEntity(template_id, overrides)
    local blueprint = blueprints[template_id]
    if not blueprint then
        return nil, "blueprint_not_found"
    end

    overrides = overrides or {}

    -- Create base entity
    local entity = base_entity.createEntity({
        name             = overrides.name or blueprint.name,
        swords           = blueprint.attributes.swords,
        pentacles        = blueprint.attributes.pentacles,
        cups             = blueprint.attributes.cups,
        wands            = blueprint.attributes.wands,
        armorSlots       = blueprint.armorSlots or 0,
        talentWoundSlots = blueprint.talentWoundSlots or 0,
        location         = overrides.location or nil,
    })

    -- Mark as NPC
    entity.isPC = false
    entity.blueprintId = template_id

    -- Attach inventory
    entity.inventory = inventory.createInventory()

    -- Instantiate and place starting gear
    local gear = blueprint.starting_gear or {}

    -- Hands
    if gear.hands then
        local handItems = instantiateGear(gear.hands)
        for _, item in ipairs(handItems) do
            entity.inventory:addItem(item, "hands")
        end
    end

    -- Belt
    if gear.belt then
        local beltItems = instantiateGear(gear.belt)
        for _, item in ipairs(beltItems) do
            entity.inventory:addItem(item, "belt")
        end
    end

    -- Pack
    if gear.pack then
        local packItems = instantiateGear(gear.pack)
        for _, item in ipairs(packItems) do
            entity.inventory:addItem(item, "pack")
        end
    end

    return entity
end

--------------------------------------------------------------------------------
-- CREATE ADVENTURER (PCs)
-- Specialized version with Resolve, Bonds, Motifs, Talents
--------------------------------------------------------------------------------

--- Create a player character adventurer
-- @param pc_data table: Character data from session 0 / character creation
-- @return Adventurer with inventory and starting gear
function M.createAdventurer(pc_data)
    pc_data = pc_data or {}

    -- Create adventurer (extends base entity)
    local pc = adventurer_module.createAdventurer({
        name             = pc_data.name or "Unnamed Adventurer",
        swords           = pc_data.swords or pc_data.attributes and pc_data.attributes.swords or 2,
        pentacles        = pc_data.pentacles or pc_data.attributes and pc_data.attributes.pentacles or 2,
        cups             = pc_data.cups or pc_data.attributes and pc_data.attributes.cups or 2,
        wands            = pc_data.wands or pc_data.attributes and pc_data.attributes.wands or 2,
        armorSlots       = pc_data.armorSlots or 0,
        talentWoundSlots = pc_data.talentWoundSlots or 2,
        resolve          = pc_data.resolve or 4,
        resolveMax       = pc_data.resolveMax or 4,
        motifs           = pc_data.motifs or {},
        bonds            = pc_data.bonds or {},
        talents          = pc_data.talents or {},
        location         = pc_data.location or nil,
    })

    -- Attach inventory
    pc.inventory = inventory.createInventory()

    -- Add starting gear if provided
    local gear = pc_data.starting_gear or {}

    if gear.hands then
        local handItems = instantiateGear(gear.hands)
        for _, item in ipairs(handItems) do
            pc.inventory:addItem(item, "hands")
        end
    end

    if gear.belt then
        local beltItems = instantiateGear(gear.belt)
        for _, item in ipairs(beltItems) do
            pc.inventory:addItem(item, "belt")
        end
    end

    if gear.pack then
        local packItems = instantiateGear(gear.pack)
        for _, item in ipairs(packItems) do
            pc.inventory:addItem(item, "pack")
        end
    end

    return pc
end

--------------------------------------------------------------------------------
-- QUICK SPAWN HELPERS
--------------------------------------------------------------------------------

--- Spawn multiple entities of the same type
-- @param template_id string: Blueprint ID
-- @param count number: How many to spawn
-- @return table: Array of entities
function M.spawnGroup(template_id, count)
    local group = {}
    for i = 1, count do
        local entity, err = M.createEntity(template_id)
        if entity then
            group[#group + 1] = entity
        end
    end
    return group
end

return M

```

---

## File: src/logic/action_resolver.lua

```lua
-- action_resolver.lua
-- Challenge Action Resolution for Majesty
-- Ticket S4.4: Maps suits to mechanical effects
--
-- Suits and their actions:
-- - SWORDS: Melee (requires engagement), Missile (bypasses engagement)
-- - PENTACLES: Roughhouse (Trip, Disarm, Displace)
-- - CUPS: Defense, healing, social
-- - WANDS: Banter (attacks Morale), magic
--
-- Great Success (face cards on matching suit) triggers weapon bonuses

local events = require('logic.events')
local constants = require('constants')

local M = {}

--------------------------------------------------------------------------------
-- ACTION TYPES
--------------------------------------------------------------------------------
M.ACTION_TYPES = {
    -- Swords
    MELEE      = "melee",       -- Requires engagement
    MISSILE    = "missile",     -- Bypasses engagement, ammo cost

    -- Pentacles
    TRIP       = "trip",        -- Knock prone
    DISARM     = "disarm",      -- Remove weapon
    DISPLACE   = "displace",    -- Push to different zone
    GRAPPLE    = "grapple",     -- Establish grapple

    -- Cups
    DEFEND     = "defend",      -- Defensive stance
    HEAL       = "heal",        -- Healing action
    SHIELD     = "shield",      -- Protect another
    AID        = "aid",         -- S7.1: Aid Another (bank bonus for ally)

    -- Wands
    BANTER     = "banter",      -- Attack morale
    CAST       = "cast",        -- Use magic
    INTIMIDATE = "intimidate",  -- Fear effect
    RECOVER    = "recover",     -- S7.4: Clear negative status effects

    -- Special
    FLEE       = "flee",        -- Attempt to escape
    MOVE       = "move",        -- Change zone
    USE_ITEM   = "use_item",    -- Use an item

    -- Defensive Actions (S4.9)
    DODGE      = "dodge",       -- Adds card value to defense difficulty
    RIPOSTE    = "riposte",     -- Counter-attack when attacked

    -- Interrupt Actions (S4.9)
    FOOL_INTERRUPT = "fool_interrupt",  -- The Fool: take immediate action out of turn

    -- Engagement Actions (S6.3)
    AVOID      = "avoid",       -- Escape engagement without parting blows
    DASH       = "dash",        -- Quick move (subject to parting blows)

    -- S7.8: Ammunition
    RELOAD     = "reload",      -- Reload a crossbow
}

--------------------------------------------------------------------------------
-- S7.6: WEAPON TYPES (for specialization logic)
--------------------------------------------------------------------------------
M.WEAPON_TYPES = {
    -- Blades: Riposte deals 2 damage
    BLADE   = { "sword", "dagger", "axe" },
    -- Hammers: Double damage threshold
    HAMMER  = { "mace", "hammer", "staff" },
    -- Daggers: Piercing vs vulnerable targets
    DAGGER  = { "dagger" },
    -- Flails: Ties count as success
    FLAIL   = { "flail" },
    -- Axes: Cleave on defeat
    AXE     = { "axe" },
    -- Ranged
    BOW     = { "bow" },
    CROSSBOW = { "crossbow" },
}

--------------------------------------------------------------------------------
-- WEAPON TYPES & GREAT SUCCESS BONUSES
--------------------------------------------------------------------------------
M.WEAPON_BONUSES = {
    -- Blade weapons: +1 wound on Great Success
    sword       = { great_bonus = "extra_wound", wound_bonus = 1 },
    dagger      = { great_bonus = "extra_wound", wound_bonus = 1 },
    axe         = { great_bonus = "extra_wound", wound_bonus = 1 },

    -- Blunt weapons: Stagger on Great Success
    mace        = { great_bonus = "stagger" },
    hammer      = { great_bonus = "stagger" },
    staff       = { great_bonus = "stagger" },

    -- Piercing weapons: Ignore armor on Great Success
    spear       = { great_bonus = "pierce_armor" },
    pike        = { great_bonus = "pierce_armor" },

    -- Ranged weapons
    bow         = { great_bonus = "extra_wound", wound_bonus = 1, uses_ammo = true },
    crossbow    = { great_bonus = "pierce_armor", uses_ammo = true },
    thrown      = { great_bonus = "extra_wound", wound_bonus = 1, uses_ammo = true },
}

--------------------------------------------------------------------------------
-- THE FOOL HELPER (S4.9)
--------------------------------------------------------------------------------

--- Check if a card is The Fool
-- @param card table: Card to check
-- @return boolean: true if card is The Fool
function M.isFool(card)
    if not card then return false end
    return card.name == "The Fool" or (card.is_major and card.value == 0)
end

--------------------------------------------------------------------------------
-- S7.6: WEAPON TYPE HELPERS
--------------------------------------------------------------------------------

--- Check if a weapon is of a specific category
-- @param weapon table: Weapon to check
-- @param category string: Category key from WEAPON_TYPES
-- @return boolean
function M.isWeaponType(weapon, category)
    if not weapon then return false end
    local weaponType = (weapon.type or weapon.name or ""):lower()
    local types = M.WEAPON_TYPES[category]
    if not types then return false end

    for _, t in ipairs(types) do
        if weaponType == t or weaponType:find(t) then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- ACTION RESOLVER FACTORY
--------------------------------------------------------------------------------

--- Create a new ActionResolver
-- @param config table: { eventBus, zoneSystem }
-- @return ActionResolver instance
function M.createActionResolver(config)
    config = config or {}

    local resolver = {
        eventBus   = config.eventBus or events.globalBus,
        zoneSystem = config.zoneSystem,
        -- S6.3: Track engagements { [entityId] = { [enemyId] = true, ... } }
        engagements = {},
        -- S7.1: Track active aids { [targetId] = { val = bonus, source = actorName } }
        activeAids = {},
    }

    ----------------------------------------------------------------------------
    -- MAIN RESOLUTION ENTRY POINT
    ----------------------------------------------------------------------------

    --- Resolve an action
    -- @param action table: { actor, target, type, card, weapon, ... }
    -- @return table: { success, isGreat, damageDealt, effects, description }
    function resolver:resolve(action)
        local result = {
            success = false,
            isGreat = false,
            damageDealt = 0,
            effects = {},
            description = "",
            cardValue = 0,
            modifier = 0,
            testValue = 0,
            difficulty = 10,
        }

        if not action.actor or not action.card then
            result.description = "Invalid action"
            return result
        end

        -- Get card info
        local card = action.card
        result.cardValue = card.value or 0

        -- S4.9: Check for The Fool interrupt
        if M.isFool(card) then
            return self:resolveFoolInterrupt(action, result)
        end

        -- Calculate modifier from actor's stat
        local suit = card.suit
        local statMod = self:getStatModifier(action.actor, suit)
        result.modifier = statMod

        -- Total test value
        result.testValue = result.cardValue + result.modifier

        -- Get difficulty (target's defense or fixed value)
        result.difficulty = self:getDifficulty(action)

        -- Check for success
        result.success = result.testValue >= result.difficulty

        -- Check for Great Success (face card matching suit)
        result.isGreat = self:isGreatSuccess(card, action.actor)

        -- Route to specific resolution based on ACTION TYPE (not card suit)
        -- This allows using any card for any action on primary turns
        local actionType = action.type or "generic"

        -- Swords actions (combat)
        if actionType == M.ACTION_TYPES.MELEE or actionType == M.ACTION_TYPES.MISSILE then
            self:resolveSwordsAction(action, result)
        -- Pentacles actions (agility/technical)
        elseif actionType == M.ACTION_TYPES.TRIP or actionType == M.ACTION_TYPES.DISARM or
               actionType == M.ACTION_TYPES.DISPLACE or actionType == M.ACTION_TYPES.GRAPPLE or
               actionType == M.ACTION_TYPES.AVOID or actionType == M.ACTION_TYPES.DASH then
            self:resolvePentaclesAction(action, result)
        -- Cups actions (defense/social)
        elseif actionType == M.ACTION_TYPES.DEFEND or actionType == M.ACTION_TYPES.DODGE or
               actionType == M.ACTION_TYPES.RIPOSTE or actionType == M.ACTION_TYPES.HEAL or
               actionType == M.ACTION_TYPES.SHIELD or actionType == M.ACTION_TYPES.AID then
            self:resolveCupsAction(action, result)
        -- Wands actions (magic/perception)
        elseif actionType == M.ACTION_TYPES.BANTER or actionType == M.ACTION_TYPES.CAST or
               actionType == M.ACTION_TYPES.INTIMIDATE or actionType == M.ACTION_TYPES.RECOVER then
            self:resolveWandsAction(action, result)
        -- Movement and misc
        elseif actionType == M.ACTION_TYPES.MOVE then
            self:resolveMove(action, result, action.allEntities)
        elseif actionType == M.ACTION_TYPES.FLEE then
            self:resolveGenericAction(action, result)
        elseif actionType == M.ACTION_TYPES.RELOAD then
            -- S7.8: Reload crossbow
            self:resolveReload(action, result)
        else
            -- Unknown action type - fall back to suit-based routing
            if suit == constants.SUITS.SWORDS then
                self:resolveSwordsAction(action, result)
            elseif suit == constants.SUITS.PENTACLES then
                self:resolvePentaclesAction(action, result)
            elseif suit == constants.SUITS.CUPS then
                self:resolveCupsAction(action, result)
            elseif suit == constants.SUITS.WANDS then
                self:resolveWandsAction(action, result)
            else
                self:resolveGenericAction(action, result)
            end
        end

        -- Attach result to action for event emission
        action.result = result

        return result
    end

    ----------------------------------------------------------------------------
    -- STAT MODIFIER CALCULATION
    ----------------------------------------------------------------------------

    --- Get the stat modifier for a given suit
    function resolver:getStatModifier(entity, suit)
        if not entity then return 0 end

        if suit == constants.SUITS.SWORDS then
            return entity.swords or 0
        elseif suit == constants.SUITS.PENTACLES then
            return entity.pentacles or 0
        elseif suit == constants.SUITS.CUPS then
            return entity.cups or 0
        elseif suit == constants.SUITS.WANDS then
            return entity.wands or 0
        end

        return 0
    end

    ----------------------------------------------------------------------------
    -- S7.1: AID ANOTHER SYSTEM
    ----------------------------------------------------------------------------

    --- Apply any active aids to an actor's result
    -- @param actor table: The acting entity
    -- @param result table: Result to modify
    function resolver:applyActiveAids(actor, result)
        if not actor or not actor.id then return end

        local aid = self.activeAids[actor.id]
        if aid then
            result.modifier = (result.modifier or 0) + aid.val
            result.testValue = result.cardValue + result.modifier
            result.description = (result.description or "") .. "(Aided by " .. aid.source .. " +" .. aid.val .. ") "
            result.effects[#result.effects + 1] = "aided"

            -- Clear the aid (one-time use)
            self.activeAids[actor.id] = nil
            print("[AID] " .. (actor.name or actor.id) .. " used aid bonus +" .. aid.val .. " from " .. aid.source)
        end
    end

    --- Register an aid for a target
    -- @param target table: Entity receiving the aid
    -- @param value number: Bonus value (card value + cups)
    -- @param source string: Name of the aiding entity
    function resolver:registerAid(target, value, source)
        if not target or not target.id then return end

        -- Overwrite any existing aid (per S7.1 design notes)
        self.activeAids[target.id] = {
            val = value,
            source = source,
        }
        print("[AID] " .. source .. " aids " .. (target.name or target.id) .. " with +" .. value .. " bonus")
    end

    ----------------------------------------------------------------------------
    -- DIFFICULTY CALCULATION
    ----------------------------------------------------------------------------

    --- Get the difficulty for an action
    function resolver:getDifficulty(action)
        local target = action.target

        -- Default difficulty
        local difficulty = 10

        if target then
            -- Combat: Use target's defense value
            if action.type == M.ACTION_TYPES.MELEE or
               action.type == M.ACTION_TYPES.MISSILE then
                -- Defense = 10 + Pentacles (or custom defense stat)
                difficulty = 10 + (target.pentacles or 0)
                if target.conditions and target.conditions.defending then
                    difficulty = difficulty + 2
                end

                -- S4.9: Check for Dodge defense
                if target.hasDefense and target:hasDefense() then
                    local defense = target:getDefense()
                    if defense and defense.type == "dodge" then
                        -- Dodge adds card value to difficulty
                        difficulty = difficulty + (defense.value or 0)
                        action.dodgeUsed = true
                    end
                end
            elseif action.type == M.ACTION_TYPES.BANTER then
                -- Banter: Attack vs Morale
                difficulty = target.morale or (10 + (target.wands or 0))
            elseif action.type == M.ACTION_TYPES.TRIP or
                   action.type == M.ACTION_TYPES.DISARM or
                   action.type == M.ACTION_TYPES.DISPLACE then
                -- Roughhouse: vs Pentacles
                difficulty = 10 + (target.pentacles or 0)
            end
        end

        return difficulty
    end

    ----------------------------------------------------------------------------
    -- GREAT SUCCESS CHECK
    ----------------------------------------------------------------------------

    --- Check if this is a Great Success
    -- Great = Face card (11-14) AND card suit matches actor's highest stat
    function resolver:isGreatSuccess(card, actor)
        if not card or card.value < 11 then
            return false
        end

        -- Check if card suit matches actor's specialization
        -- (simplified: check if this suit is their highest)
        local suit = card.suit
        local statValue = self:getStatModifier(actor, suit)

        -- For now, any face card on a stat >= 2 is Great
        return statValue >= 2
    end

    ----------------------------------------------------------------------------
    -- SWORDS RESOLUTION (Melee & Missile)
    ----------------------------------------------------------------------------

    function resolver:resolveSwordsAction(action, result)
        local actionType = action.type or M.ACTION_TYPES.MELEE

        if actionType == M.ACTION_TYPES.MISSILE then
            self:resolveMissile(action, result)
        else
            self:resolveMelee(action, result)
        end
    end

    --- Resolve melee attack
    function resolver:resolveMelee(action, result)
        local target = action.target

        -- S7.1: Apply any active aids to this attack
        self:applyActiveAids(action.actor, result)

        -- Recalculate success after aid bonus
        result.success = result.testValue >= result.difficulty

        -- Check engagement (must be in same zone as target)
        if self.zoneSystem and target then
            local actorZone = action.actor.zone
            local targetZone = target.zone

            if actorZone ~= targetZone then
                result.success = false
                result.description = "Target is not engaged (different zone)"
                result.effects[#result.effects + 1] = "not_engaged"
                return
            end
        end

        -- S4.9: Check for and handle defensive actions
        local riposteTriggered = false
        local riposteDefense = nil

        if target and target.hasDefense and target:hasDefense() then
            local defense = target:getDefense()
            if defense then
                if defense.type == "dodge" then
                    -- Dodge was already applied to difficulty, consume it
                    target:consumeDefense()
                    result.effects[#result.effects + 1] = "dodged"
                    if not result.success then
                        result.description = "Dodged! "
                    end
                elseif defense.type == "riposte" then
                    -- Riposte: will counter-attack after resolution
                    riposteTriggered = true
                    riposteDefense = target:consumeDefense()
                    result.effects[#result.effects + 1] = "riposte_ready"
                end
            end
        end

        -- S7.6: Flail specialization - ties count as success
        if not result.success and action.weapon and M.isWeaponType(action.weapon, "FLAIL") then
            if result.testValue == result.difficulty then
                result.success = true
                result.description = "Flail tie-breaker! "
                result.effects[#result.effects + 1] = "flail_tie"
            end
        end

        if result.success then
            result.damageDealt = 1
            result.description = (result.description or "") .. "Hit! "

            -- S6.3: Form engagement on successful melee attack
            if target and action.actor then
                self:formEngagement(action.actor, target)
            end

            -- S7.6: Hammer/Mace specialization - double damage on overwhelming hit
            if action.weapon and M.isWeaponType(action.weapon, "HAMMER") then
                if result.testValue >= (result.difficulty * 2) then
                    result.damageDealt = 2
                    result.description = result.description .. "Crushing blow! "
                    result.effects[#result.effects + 1] = "hammer_crush"
                end
            end

            -- S7.6: Dagger specialization - piercing vs vulnerable targets
            if action.weapon and M.isWeaponType(action.weapon, "DAGGER") then
                if target and target.conditions then
                    if target.conditions.rooted or target.conditions.prone or target.conditions.disarmed then
                        result.effects[#result.effects + 1] = "piercing"
                        result.description = result.description .. "Exploits vulnerability! "
                    end
                end
            end

            -- Check for Great Success weapon bonus
            if result.isGreat and action.weapon then
                local weaponType = action.weapon.type or action.weapon.name
                local bonus = M.WEAPON_BONUSES[weaponType:lower()]

                if bonus then
                    if bonus.great_bonus == "extra_wound" then
                        result.damageDealt = result.damageDealt + (bonus.wound_bonus or 1)
                        result.description = result.description .. "Great Success! +" .. bonus.wound_bonus .. " wound. "
                    elseif bonus.great_bonus == "stagger" then
                        result.effects[#result.effects + 1] = "stagger"
                        result.description = result.description .. "Great Success! Target staggered. "
                    elseif bonus.great_bonus == "pierce_armor" then
                        result.effects[#result.effects + 1] = "pierce_armor"
                        result.description = result.description .. "Great Success! Armor pierced. "
                    end
                end
            end

            -- Apply damage to target (with weapon for cleave check)
            if target then
                self:applyDamage(target, result.damageDealt, result.effects, action.weapon, action.allEntities)
            end
        else
            if action.dodgeUsed then
                result.description = "Dodged! Attack missed."
            else
                result.description = "Miss!"
            end
        end

        -- S4.9: Resolve Riposte counter-attack
        if riposteTriggered and riposteDefense and target then
            local riposteResult = self:resolveRiposte(target, action.actor, riposteDefense)
            result.riposteResult = riposteResult
            result.description = result.description .. " Riposte! "
            if riposteResult.success then
                result.description = result.description .. "Counter-attack hits!"
            else
                result.description = result.description .. "Counter-attack misses."
            end
        end
    end

    --- Resolve missile attack
    function resolver:resolveMissile(action, result)
        -- S7.1: Apply any active aids to this attack
        self:applyActiveAids(action.actor, result)

        -- S7.5: Ranged engagement penalty - shooting while engaged is hard
        if action.actor.is_engaged then
            result.modifier = result.modifier - 3
            result.testValue = result.cardValue + result.modifier
            result.description = "(Engaged -3) "
            result.effects[#result.effects + 1] = "engaged_ranged_penalty"
        end

        -- Recalculate success after modifiers
        result.success = result.testValue >= result.difficulty

        -- S7.8: Crossbow must be loaded
        if action.weapon and M.isWeaponType(action.weapon, "CROSSBOW") then
            if not action.weapon.isLoaded then
                result.success = false
                result.description = (result.description or "") .. "Reload required!"
                result.effects[#result.effects + 1] = "not_loaded"
                return
            end
        end

        -- Check ammo
        if action.weapon and action.weapon.uses_ammo then
            local ammo = action.actor.ammo or 0
            if ammo <= 0 then
                result.success = false
                result.description = "Out of ammo!"
                result.effects[#result.effects + 1] = "no_ammo"
                return
            end

            -- Consume ammo
            action.actor.ammo = ammo - 1
            result.effects[#result.effects + 1] = "ammo_used"
        end

        -- Missile bypasses engagement - no zone check needed

        -- S7.8: Unload crossbow after firing
        if action.weapon and M.isWeaponType(action.weapon, "CROSSBOW") then
            action.weapon.isLoaded = false
            result.effects[#result.effects + 1] = "crossbow_fired"
        end

        if result.success then
            result.damageDealt = 1
            result.description = (result.description or "") .. "Hit! "

            -- Great Success bonuses (same as melee)
            if result.isGreat and action.weapon then
                local weaponType = action.weapon.type or action.weapon.name or "bow"
                local bonus = M.WEAPON_BONUSES[weaponType:lower()]

                if bonus then
                    if bonus.great_bonus == "extra_wound" then
                        result.damageDealt = result.damageDealt + (bonus.wound_bonus or 1)
                        result.description = result.description .. "Great Success! "
                    elseif bonus.great_bonus == "pierce_armor" then
                        result.effects[#result.effects + 1] = "pierce_armor"
                        result.description = result.description .. "Armor pierced! "
                    end
                end
            end

            if action.target then
                self:applyDamage(action.target, result.damageDealt, result.effects)
            end
        else
            result.description = (result.description or "") .. "Miss!"
        end
    end

    ----------------------------------------------------------------------------
    -- RIPOSTE COUNTER-ATTACK (S4.9)
    ----------------------------------------------------------------------------

    --- Resolve a Riposte counter-attack
    -- @param defender table: Entity performing the riposte
    -- @param attacker table: Original attacker being counter-attacked
    -- @param defense table: The consumed defense { type, card, value }
    -- @return table: Result of the riposte attack
    function resolver:resolveRiposte(defender, attacker, defense)
        local riposteResult = {
            success = false,
            isGreat = false,
            damageDealt = 0,
            effects = {},
            description = "",
        }

        if not defender or not attacker or not defense then
            return riposteResult
        end

        -- Riposte uses the card that was prepared
        local card = defense.card
        local cardValue = defense.value or (card and card.value) or 0

        -- Stat modifier (Riposte uses Swords for counter-attack)
        local statMod = defender.swords or 0
        local testValue = cardValue + statMod

        -- Difficulty is attacker's defense
        local difficulty = 10 + (attacker.pentacles or 0)

        riposteResult.success = testValue >= difficulty

        if riposteResult.success then
            riposteResult.damageDealt = 1

            -- S7.6: Blade specialization - riposte deals 2 damage with swords
            if defender.weapon and M.isWeaponType(defender.weapon, "BLADE") then
                riposteResult.damageDealt = 2
                riposteResult.description = "Riposte connects with blade! (2 wounds)"
            else
                riposteResult.description = "Riposte connects!"
            end

            -- Apply damage to the original attacker
            self:applyDamage(attacker, riposteResult.damageDealt, riposteResult.effects)

            -- Emit event for visual feedback
            self.eventBus:emit("riposte_hit", {
                defender = defender,
                attacker = attacker,
                damage = riposteResult.damageDealt,
            })
        else
            riposteResult.description = "Riposte parried!"
        end

        return riposteResult
    end

    ----------------------------------------------------------------------------
    -- PENTACLES RESOLUTION (Roughhouse)
    ----------------------------------------------------------------------------

    function resolver:resolvePentaclesAction(action, result)
        local actionType = action.type or M.ACTION_TYPES.TRIP

        if actionType == M.ACTION_TYPES.TRIP then
            self:resolveTrip(action, result)
        elseif actionType == M.ACTION_TYPES.DISARM then
            self:resolveDisarm(action, result)
        elseif actionType == M.ACTION_TYPES.DISPLACE then
            self:resolveDisplace(action, result)
        elseif actionType == M.ACTION_TYPES.GRAPPLE then
            -- S7.2: Grapple sets rooted condition
            self:resolveGrapple(action, result)
        elseif actionType == M.ACTION_TYPES.AVOID then
            -- S6.3: Avoid action to escape engagement
            self:resolveAvoid(action, result)
        elseif actionType == M.ACTION_TYPES.DASH then
            -- S6.3: Dash is a Pentacles-based quick move
            self:resolveDash(action, result, action.allEntities)
        else
            self:resolveTrip(action, result)  -- Default
        end
    end

    function resolver:resolveTrip(action, result)
        if result.success then
            result.description = "Knocked down!"
            result.effects[#result.effects + 1] = "prone"

            if action.target and action.target.conditions then
                action.target.conditions.prone = true
            end
        else
            result.description = "Failed to trip!"
        end
    end

    --- S7.3: Disarm with inventory drop
    function resolver:resolveDisarm(action, result)
        local target = action.target

        if not target then
            result.success = false
            result.description = "No target to disarm!"
            return
        end

        -- Check if target has anything in hands
        local droppedItem = nil
        if target.inventory and target.inventory.getItems then
            local handsItems = target.inventory:getItems("hands")
            if handsItems and #handsItems > 0 then
                -- Remove the first item from hands
                droppedItem = handsItems[1]
                if target.inventory.removeItem then
                    target.inventory:removeItem(droppedItem.id)
                end
            end
        elseif target.weapon then
            -- Fallback: if no inventory system, just clear weapon
            droppedItem = target.weapon
            target.weapon = nil
        end

        if result.success then
            if droppedItem then
                result.description = "Disarmed [" .. (droppedItem.name or "item") .. "]!"
                result.effects[#result.effects + 1] = "disarmed"
                result.droppedItem = droppedItem

                -- Set disarmed condition on target
                if target.conditions then
                    target.conditions.disarmed = true
                end
            else
                -- Can't disarm someone with nothing in hands
                result.success = false
                result.description = "Target has nothing to disarm!"
            end
        else
            result.description = "Failed to disarm!"
        end
    end

    --- S7.2: Grapple sets rooted condition
    function resolver:resolveGrapple(action, result)
        local target = action.target

        if not target then
            result.success = false
            result.description = "No target to grapple!"
            return
        end

        if result.success then
            result.description = "Grappled! Target is rooted."
            result.effects[#result.effects + 1] = "grappled"
            result.effects[#result.effects + 1] = "rooted"

            -- Set rooted condition on target
            if target.conditions then
                target.conditions.rooted = true
            else
                target.conditions = { rooted = true }
            end

            -- Also form engagement
            self:formEngagement(action.actor, target)
        else
            result.description = "Failed to grapple!"
        end
    end

    function resolver:resolveDisplace(action, result)
        if result.success then
            result.description = "Pushed back!"
            result.effects[#result.effects + 1] = "displaced"

            -- Would move target to adjacent zone
            if action.target and action.destinationZone then
                action.target.zone = action.destinationZone
            end

            -- S6.3: Break engagement when target is displaced
            if action.target and action.actor then
                self:breakEngagement(action.actor, action.target)
            end
        else
            result.description = "Failed to push!"
        end
    end

    ----------------------------------------------------------------------------
    -- CUPS RESOLUTION (Defense/Social)
    ----------------------------------------------------------------------------

    function resolver:resolveCupsAction(action, result)
        local actionType = action.type or M.ACTION_TYPES.DEFEND

        if actionType == M.ACTION_TYPES.DEFEND then
            result.success = true
            result.description = "Taking defensive stance"
            result.effects[#result.effects + 1] = "defending"

            if action.actor.conditions then
                action.actor.conditions.defending = true
            end
        elseif actionType == M.ACTION_TYPES.DODGE then
            -- S4.9: Prepare Dodge defense
            self:resolveDodge(action, result)
        elseif actionType == M.ACTION_TYPES.RIPOSTE then
            -- S4.9: Prepare Riposte defense
            self:resolveRipostePrepare(action, result)
        elseif actionType == M.ACTION_TYPES.HEAL then
            self:resolveHeal(action, result)
        elseif actionType == M.ACTION_TYPES.SHIELD then
            result.success = true
            result.description = "Shielding " .. (action.target and action.target.name or "ally")
            result.effects[#result.effects + 1] = "shielding"
        elseif actionType == M.ACTION_TYPES.AID then
            -- S7.1: Aid Another
            self:resolveAidAnother(action, result)
        end
    end

    --- S7.1: Aid Another - bank a bonus for an ally's next action
    function resolver:resolveAidAnother(action, result)
        local actor = action.actor
        local target = action.target
        local card = action.card

        if not target then
            result.success = false
            result.description = "No ally to aid!"
            return
        end

        if not target.isPC and actor.isPC then
            result.success = false
            result.description = "Can only aid allies!"
            return
        end

        -- Aid always succeeds (no test required)
        result.success = true

        -- Calculate bonus: card value + Cups stat
        local cardValue = card.value or 0
        local cupsBonus = actor.cups or 0
        local totalBonus = cardValue + cupsBonus

        -- Register the aid for the target
        self:registerAid(target, totalBonus, actor.name or "ally")

        result.description = "Aided " .. (target.name or "ally") .. "! (+" .. totalBonus .. " to next action)"
        result.effects[#result.effects + 1] = "aid_banked"
    end

    --- Prepare a Dodge defense (S4.9)
    -- Dodge adds card value to defense difficulty when attacked
    function resolver:resolveDodge(action, result)
        local actor = action.actor
        local card = action.card

        if not actor or not card then
            result.success = false
            result.description = "Invalid dodge attempt"
            return
        end

        -- Check if entity already has a defense prepared
        if actor.hasDefense and actor:hasDefense() then
            result.success = false
            result.description = "Already has a defense prepared!"
            return
        end

        -- Prepare the dodge defense
        local success, err = actor:prepareDefense("dodge", card)

        if success then
            result.success = true
            result.description = "Preparing to dodge! (+" .. (card.value or 0) .. " to defense)"
            result.effects[#result.effects + 1] = "dodge_prepared"

            self.eventBus:emit("defense_prepared", {
                entity = actor,
                type = "dodge",
                value = card.value or 0,
            })
        else
            result.success = false
            result.description = "Cannot prepare dodge: " .. (err or "unknown")
        end
    end

    --- Prepare a Riposte defense (S4.9)
    -- Riposte triggers a counter-attack when attacked
    function resolver:resolveRipostePrepare(action, result)
        local actor = action.actor
        local card = action.card

        if not actor or not card then
            result.success = false
            result.description = "Invalid riposte attempt"
            return
        end

        -- Check if entity already has a defense prepared
        if actor.hasDefense and actor:hasDefense() then
            result.success = false
            result.description = "Already has a defense prepared!"
            return
        end

        -- Prepare the riposte defense
        local success, err = actor:prepareDefense("riposte", card)

        if success then
            result.success = true
            result.description = "Ready to riposte! (Counter-attack with value " .. (card.value or 0) .. ")"
            result.effects[#result.effects + 1] = "riposte_prepared"

            self.eventBus:emit("defense_prepared", {
                entity = actor,
                type = "riposte",
                value = card.value or 0,
            })
        else
            result.success = false
            result.description = "Cannot prepare riposte: " .. (err or "unknown")
        end
    end

    function resolver:resolveHeal(action, result)
        if result.success then
            local target = action.target or action.actor

            -- Attempt to heal wound (respects stress gate)
            local healResult, err = target:healWound()

            if healResult then
                result.description = "Healed: " .. healResult
                result.effects[#result.effects + 1] = "healed"
            else
                result.success = false
                result.description = "Cannot heal: " .. (err or "unknown")
            end
        else
            result.description = "Healing failed!"
        end
    end

    ----------------------------------------------------------------------------
    -- WANDS RESOLUTION (Banter/Magic)
    ----------------------------------------------------------------------------

    function resolver:resolveWandsAction(action, result)
        local actionType = action.type or M.ACTION_TYPES.BANTER

        if actionType == M.ACTION_TYPES.BANTER then
            self:resolveBanter(action, result)
        elseif actionType == M.ACTION_TYPES.CAST then
            self:resolveCast(action, result)
        elseif actionType == M.ACTION_TYPES.INTIMIDATE then
            self:resolveIntimidate(action, result)
        elseif actionType == M.ACTION_TYPES.RECOVER then
            -- S7.4: Recover action
            self:resolveRecover(action, result)
        else
            self:resolveBanter(action, result)
        end
    end

    --- S7.4: Recover - clear one negative status effect in priority order
    function resolver:resolveRecover(action, result)
        local actor = action.actor

        if not actor or not actor.conditions then
            result.success = false
            result.description = "Nothing to recover from."
            return
        end

        -- Priority order for clearing conditions (per S7.4 spec)
        local conditions = actor.conditions
        local cleared = nil

        if conditions.rooted then
            conditions.rooted = false
            cleared = "rooted"
        elseif conditions.prone then
            conditions.prone = false
            cleared = "prone"
        elseif conditions.blind then
            conditions.blind = false
            cleared = "blind"
        elseif conditions.deaf then
            conditions.deaf = false
            cleared = "deaf"
        elseif conditions.disarmed then
            conditions.disarmed = false
            cleared = "disarmed"
            result.description = "Recovered Weapon!"
            result.effects[#result.effects + 1] = "weapon_recovered"
        end

        if cleared then
            result.success = true
            if not result.description or result.description == "" then
                result.description = "Recovered from " .. cleared .. "!"
            end
            result.effects[#result.effects + 1] = "recovered_" .. cleared
        else
            result.success = false
            result.description = "Nothing to recover from."
        end
    end

    --- Resolve Banter (attacks Morale instead of Health)
    function resolver:resolveBanter(action, result)
        -- Banter compares vs target's Morale (p. 119)
        -- On success, deal "morale damage"

        if result.success then
            result.description = "Verbal hit! "
            result.effects[#result.effects + 1] = "morale_damage"

            if action.target then
                -- Reduce target's morale
                local moraleDamage = 1
                if result.isGreat then
                    moraleDamage = 2
                    result.description = result.description .. "Great Success! "
                end

                action.target.morale = (action.target.morale or 10) - moraleDamage

                -- Check for morale break
                if action.target.morale <= 0 then
                    result.effects[#result.effects + 1] = "morale_broken"
                    result.description = result.description .. "Morale broken!"

                    if action.target.conditions then
                        action.target.conditions.fleeing = true
                    end
                end
            end
        else
            result.description = "Banter ineffective!"
        end
    end

    function resolver:resolveCast(action, result)
        -- Magic would be spell-specific
        if result.success then
            result.description = "Spell cast successfully!"
            result.effects[#result.effects + 1] = "spell_cast"
        else
            result.description = "Spell fizzled!"
        end
    end

    function resolver:resolveIntimidate(action, result)
        if result.success then
            result.description = "Target is frightened!"
            result.effects[#result.effects + 1] = "frightened"

            if action.target and action.target.conditions then
                action.target.conditions.frightened = true
            end
        else
            result.description = "Intimidation failed!"
        end
    end

    ----------------------------------------------------------------------------
    -- GENERIC RESOLUTION
    ----------------------------------------------------------------------------

    function resolver:resolveGenericAction(action, result)
        if result.success then
            result.description = "Action succeeded!"
        else
            result.description = "Action failed!"
        end
    end

    ----------------------------------------------------------------------------
    -- S7.8: RELOAD ACTION
    ----------------------------------------------------------------------------

    --- Resolve reload action for crossbows
    function resolver:resolveReload(action, result)
        local actor = action.actor
        local weapon = actor.weapon

        -- Must have a crossbow equipped
        if not weapon or not M.isWeaponType(weapon, "CROSSBOW") then
            result.success = false
            result.description = "No crossbow to reload!"
            return
        end

        -- Check if already loaded
        if weapon.isLoaded then
            result.success = false
            result.description = "Crossbow is already loaded!"
            return
        end

        -- Reload succeeds (no test required)
        result.success = true
        weapon.isLoaded = true
        result.description = "Crossbow reloaded!"
        result.effects[#result.effects + 1] = "reloaded"
    end

    ----------------------------------------------------------------------------
    -- S6.3: ENGAGEMENT SYSTEM
    ----------------------------------------------------------------------------

    --- Form engagement between two entities
    function resolver:formEngagement(entity1, entity2)
        if not entity1 or not entity2 then return end

        local id1 = entity1.id
        local id2 = entity2.id

        -- Initialize engagement tables if needed
        self.engagements[id1] = self.engagements[id1] or {}
        self.engagements[id2] = self.engagements[id2] or {}

        -- Set mutual engagement
        self.engagements[id1][id2] = true
        self.engagements[id2][id1] = true

        -- Set is_engaged flag on entities
        entity1.is_engaged = true
        entity2.is_engaged = true

        -- Emit event for UI
        self.eventBus:emit(events.EVENTS.ENTITIES_ENGAGED, {
            entity1 = entity1,
            entity2 = entity2,
        })

        -- Also emit arena event
        self.eventBus:emit("engagement_formed", {
            entity1 = entity1,
            entity2 = entity2,
        })
    end

    --- Break engagement between two specific entities
    function resolver:breakEngagement(entity1, entity2)
        if not entity1 or not entity2 then return end

        local id1 = entity1.id
        local id2 = entity2.id

        -- Clear mutual engagement
        if self.engagements[id1] then
            self.engagements[id1][id2] = nil
        end
        if self.engagements[id2] then
            self.engagements[id2][id1] = nil
        end

        -- Update is_engaged flag based on remaining engagements
        entity1.is_engaged = self:hasAnyEngagement(entity1)
        entity2.is_engaged = self:hasAnyEngagement(entity2)

        -- Emit event for UI
        self.eventBus:emit(events.EVENTS.ENTITIES_DISENGAGED, {
            entity1 = entity1,
            entity2 = entity2,
        })

        -- Also emit arena event
        self.eventBus:emit("engagement_broken", {
            entity1 = entity1,
            entity2 = entity2,
        })
    end

    --- Clear all engagements for an entity (on defeat)
    function resolver:clearAllEngagements(entity)
        if not entity then return end

        local id = entity.id
        local engaged = self.engagements[id]

        if engaged then
            -- Break each engagement
            for enemyId, _ in pairs(engaged) do
                -- Find the enemy entity and clear their side too
                if self.engagements[enemyId] then
                    self.engagements[enemyId][id] = nil
                end
            end
            self.engagements[id] = nil
        end

        entity.is_engaged = false
    end

    --- Check if entity has any engagements
    function resolver:hasAnyEngagement(entity)
        if not entity then return false end

        local engaged = self.engagements[entity.id]
        if not engaged then return false end

        for _ in pairs(engaged) do
            return true  -- At least one engagement exists
        end
        return false
    end

    --- Check if two entities are engaged
    function resolver:areEngaged(entity1, entity2)
        if not entity1 or not entity2 then return false end

        local engaged = self.engagements[entity1.id]
        return engaged and engaged[entity2.id] == true
    end

    --- Get all entities engaged with a given entity
    -- @param entity table: The entity to check
    -- @param allEntities table: Array of all entities in the challenge
    -- @return table: Array of engaged entities
    function resolver:getEngagedEnemies(entity, allEntities)
        if not entity then return {} end

        local engaged = self.engagements[entity.id]
        if not engaged then return {} end

        local enemies = {}
        for _, e in ipairs(allEntities or {}) do
            if engaged[e.id] then
                enemies[#enemies + 1] = e
            end
        end
        return enemies
    end

    ----------------------------------------------------------------------------
    -- S6.3: PARTING BLOWS
    ----------------------------------------------------------------------------

    --- Check and apply parting blows when entity tries to move while engaged
    -- @param entity table: The moving entity
    -- @param allEntities table: All entities in the challenge
    -- @return table: { blocked = bool, wounds = number, attackers = { ... } }
    function resolver:checkPartingBlows(entity, allEntities)
        local result = {
            blocked = false,
            wounds = 0,
            attackers = {},
        }

        if not entity or not entity.is_engaged then
            return result
        end

        -- Find all engaged enemies in the same zone
        local engaged = self.engagements[entity.id]
        if not engaged then return result end

        for _, e in ipairs(allEntities or {}) do
            if engaged[e.id] and e.zone == entity.zone then
                -- Enemy gets a free parting blow
                result.attackers[#result.attackers + 1] = e
                result.wounds = result.wounds + 1

                -- Emit parting blow event
                self.eventBus:emit(events.EVENTS.PARTING_BLOW, {
                    attacker = e,
                    victim = entity,
                })
            end
        end

        -- Apply wounds to the mover
        if result.wounds > 0 then
            for _ = 1, result.wounds do
                local woundResult = entity:takeWound(false)

                self.eventBus:emit(events.EVENTS.WOUND_TAKEN, {
                    entity = entity,
                    result = woundResult,
                    source = "parting_blow",
                })

                -- Check if mover is incapacitated
                if entity.conditions and entity.conditions.deaths_door then
                    result.blocked = true
                    break
                end
                if entity.conditions and entity.conditions.dead then
                    result.blocked = true
                    break
                end
            end
        end

        return result
    end

    ----------------------------------------------------------------------------
    -- S6.3: MOVE/DASH/AVOID RESOLUTION
    ----------------------------------------------------------------------------

    --- Resolve movement action (subject to parting blows)
    function resolver:resolveMove(action, result, allEntities)
        local actor = action.actor
        local destZone = action.destinationZone
        local oldZone = actor.zone

        -- S7.2: Check for rooted condition
        if actor.conditions and actor.conditions.rooted then
            result.success = false
            result.description = "Rooted! Cannot move."
            result.effects[#result.effects + 1] = "rooted_blocked"
            return
        end

        -- Check for parting blows if engaged
        if actor.is_engaged then
            local partingResult = self:checkPartingBlows(actor, allEntities)

            if partingResult.blocked then
                result.success = false
                result.description = "Movement blocked! "
                if #partingResult.attackers > 0 then
                    result.description = result.description .. "Took " .. partingResult.wounds .. " parting blow(s) and fell!"
                end
                result.effects[#result.effects + 1] = "parting_blow_blocked"
                return
            end

            if partingResult.wounds > 0 then
                result.effects[#result.effects + 1] = "parting_blows"
                result.partingBlows = partingResult
            end
        end

        -- Movement succeeds
        result.success = true
        if destZone then
            actor.zone = destZone
            result.description = "Moved to " .. destZone

            -- Emit event for arena view to update display
            self.eventBus:emit("entity_zone_changed", {
                entity = actor,
                oldZone = oldZone,
                newZone = destZone,
            })

            print("[MOVE] " .. (actor.name or actor.id) .. " moved from " .. (oldZone or "?") .. " to " .. destZone)
        else
            result.description = "Movement complete"
        end
        result.effects[#result.effects + 1] = "moved"

        -- Clear engagements (they're now in different zones)
        if actor.is_engaged then
            self:clearAllEngagements(actor)
        end
    end

    --- Resolve Dash action (faster move, still subject to parting blows)
    function resolver:resolveDash(action, result, allEntities)
        local actor = action.actor

        -- S7.2: Check for rooted condition
        if actor.conditions and actor.conditions.rooted then
            result.success = false
            result.description = "Rooted! Cannot dash."
            result.effects[#result.effects + 1] = "rooted_blocked"
            return
        end

        -- Dash is similar to move but might cover more distance
        self:resolveMove(action, result, allEntities)

        if result.success then
            result.description = "Dashed! " .. (result.description or "")
            result.effects[#result.effects + 1] = "dashed"
        end
    end

    --- Resolve Avoid action (escape engagement without parting blows)
    function resolver:resolveAvoid(action, result)
        local actor = action.actor
        local card = action.card

        -- S7.2: Check for rooted condition
        if actor.conditions and actor.conditions.rooted then
            result.success = false
            result.description = "Rooted! Cannot avoid."
            result.effects[#result.effects + 1] = "rooted_blocked"
            return
        end

        -- Calculate test value
        local statMod = actor.pentacles or 0
        local testValue = (card.value or 0) + statMod

        -- Difficulty: 10 (or based on number of engaged enemies)
        local difficulty = 10
        local engagedCount = 0
        local engaged = self.engagements[actor.id]
        if engaged then
            for _ in pairs(engaged) do
                engagedCount = engagedCount + 1
            end
        end
        difficulty = difficulty + (engagedCount - 1) * 2  -- +2 per additional engaged enemy

        result.testValue = testValue
        result.difficulty = difficulty
        result.success = testValue >= difficulty

        if result.success then
            result.description = "Slipped away! Ready to move safely."
            result.effects[#result.effects + 1] = "avoid_success"

            -- Set flag that allows next move without parting blows
            actor.avoidedThisTurn = true

            -- Clear engagements immediately
            self:clearAllEngagements(actor)

            -- Can now move without taking parting blows
            if action.destinationZone then
                actor.zone = action.destinationZone
                result.description = result.description .. " Moved to " .. action.destinationZone
            end
        else
            result.description = "Failed to disengage!"
            result.effects[#result.effects + 1] = "avoid_failed"
        end
    end

    ----------------------------------------------------------------------------
    -- THE FOOL INTERRUPT (S4.9)
    -- The Fool allows an immediate action out of turn order
    -- Playing The Fool grants a free action with a follow-up card
    ----------------------------------------------------------------------------

    --- Resolve The Fool interrupt
    -- @param action table: { actor, card (The Fool), followUpCard, followUpAction, target }
    -- @param result table: Result to populate
    -- @return table: The result
    function resolver:resolveFoolInterrupt(action, result)
        result.success = true
        result.isFoolInterrupt = true
        result.effects[#result.effects + 1] = "fool_interrupt"

        -- The Fool by itself just grants the interrupt opportunity
        -- If there's a follow-up action specified, resolve that instead
        if action.followUpCard and action.followUpAction then
            -- Create a sub-action using the follow-up card
            local followUpAction = {
                actor = action.actor,
                target = action.target,
                card = action.followUpCard,
                type = action.followUpAction,
                weapon = action.weapon,
            }

            -- Resolve the follow-up action
            local followUpResult = self:resolve(followUpAction)

            -- Merge results
            result.followUpResult = followUpResult
            result.description = "The Fool! Immediate action: " .. (followUpResult.description or "")
            result.damageDealt = followUpResult.damageDealt
            result.isGreat = followUpResult.isGreat

            -- Copy effects from follow-up
            for _, effect in ipairs(followUpResult.effects) do
                result.effects[#result.effects + 1] = effect
            end
        else
            -- No follow-up specified - Fool grants free movement or simple action
            result.description = "The Fool! You may take an immediate action."
            result.effects[#result.effects + 1] = "pending_fool_action"

            -- Emit event for UI to prompt for follow-up action
            self.eventBus:emit("fool_interrupt", {
                actor = action.actor,
                awaitingFollowUp = true,
            })
        end

        -- Attach result
        action.result = result

        return result
    end

    ----------------------------------------------------------------------------
    -- DAMAGE APPLICATION (S7.6: Updated with weapon cleave, S7.7: damage types)
    ----------------------------------------------------------------------------

    --- Apply damage to an entity
    -- @param entity table: Target entity
    -- @param amount number: Number of wounds
    -- @param effects table: Effect flags (pierce_armor, piercing, critical, etc.)
    -- @param weapon table: Optional weapon for cleave check
    -- @param allEntities table: Optional list of all entities for cleave targeting
    function resolver:applyDamage(entity, amount, effects, weapon, allEntities)
        effects = effects or {}

        -- S7.7: Determine damage type from effects
        local damageType = "normal"
        for _, eff in ipairs(effects) do
            if eff == "critical" then
                damageType = "critical"
                break
            elseif eff == "piercing" or eff == "pierce_armor" then
                damageType = "piercing"
            end
        end

        local wasDefeated = false
        for _ = 1, amount do
            -- Call entity's takeWound with damage type (S7.7)
            local woundResult = entity:takeWound(damageType)

            print("[DAMAGE] " .. (entity.name or entity.id) .. " takes " .. damageType .. " wound -> " .. (woundResult or "?"))
            print("  Armor: " .. (entity.armorNotches or 0) ..
                  " | Conditions: stag=" .. tostring(entity.conditions and entity.conditions.staggered) ..
                  " inj=" .. tostring(entity.conditions and entity.conditions.injured) ..
                  " dd=" .. tostring(entity.conditions and entity.conditions.deaths_door) ..
                  " dead=" .. tostring(entity.conditions and entity.conditions.dead))

            -- Emit wound event for visual
            self.eventBus:emit(events.EVENTS.WOUND_TAKEN, {
                entity = entity,
                result = woundResult,
                damageType = damageType,
            })

            -- Check for defeat
            if entity.conditions and (entity.conditions.dead or entity.conditions.deaths_door) then
                wasDefeated = true
                if entity.conditions.dead then
                    print("[DEFEAT] " .. (entity.name or entity.id) .. " is DEAD!")
                    -- S6.3: Clear all engagements when defeated
                    self:clearAllEngagements(entity)

                    self.eventBus:emit(events.EVENTS.ENTITY_DEFEATED, {
                        entity = entity,
                    })
                end
                break
            end
        end

        -- S7.6: Axe Cleave - on defeat, free attack on another enemy in same zone
        if wasDefeated and weapon and M.isWeaponType(weapon, "AXE") and allEntities then
            self:triggerAxeCleave(entity, weapon, allEntities)
        end
    end

    --- S7.6: Trigger axe cleave attack on another enemy in same zone
    function resolver:triggerAxeCleave(defeatedEntity, weapon, allEntities)
        local zone = defeatedEntity.zone
        local cleaveTarget = nil

        -- Find another enemy in the same zone
        for _, e in ipairs(allEntities or {}) do
            if e ~= defeatedEntity and e.zone == zone then
                if not (e.conditions and e.conditions.dead) then
                    -- Prefer enemies over allies
                    if e.isPC ~= defeatedEntity.isPC then
                        cleaveTarget = e
                        break
                    elseif not cleaveTarget then
                        cleaveTarget = e
                    end
                end
            end
        end

        if cleaveTarget then
            print("[CLEAVE] Axe cleaves into " .. (cleaveTarget.name or cleaveTarget.id) .. "!")

            -- Deal 1 wound to cleave target
            self:applyDamage(cleaveTarget, 1, {}, nil, nil)

            -- Emit cleave event for visual feedback
            self.eventBus:emit("axe_cleave", {
                source = defeatedEntity,
                target = cleaveTarget,
            })
        end
    end

    return resolver
end

return M

```

---

## File: src/logic/camp_actions.lua

```lua
-- camp_actions.lua
-- Data registry of Camp Actions for Majesty
-- Ticket S8.3: Camp Actions Implementation
--
-- Defines the actions players can take during Step 1 of Camp Phase.
-- Reference: Rulebook p. 137-139

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- CAMP ACTION CATEGORIES
--------------------------------------------------------------------------------
M.CATEGORIES = {
    MAINTENANCE = "maintenance",  -- Item/gear repair
    SOCIAL      = "social",       -- Bond interactions
    EXPLORATION = "exploration",  -- Scouting, recon
    REST        = "rest",         -- Recovery/healing
}

--------------------------------------------------------------------------------
-- CAMP ACTION DEFINITIONS
--------------------------------------------------------------------------------
-- Each action has:
--   id            - Unique identifier
--   name          - Display name
--   category      - Action category
--   description   - Short description for tooltip
--   requiresTarget - Whether a target is needed
--   targetType    - "pc" (party member), "item", "companion"
--   requiresItem  - Item needed to perform (optional)
--   testSuit      - If a test is required, which suit
--   resolve       - Function to execute the action

M.ACTIONS = {
    ----------------------------------------------------------------------------
    -- MAINTENANCE ACTIONS
    ----------------------------------------------------------------------------
    {
        id = "repair",
        name = "Repair",
        category = M.CATEGORIES.MAINTENANCE,
        description = "Remove 1 Notch from an item. Requires Tinker's Kit.",
        requiresTarget = true,
        targetType = "item",
        requiresItem = "tinkers_kit",
    },

    ----------------------------------------------------------------------------
    -- SOCIAL ACTIONS
    ----------------------------------------------------------------------------
    {
        id = "fellowship",
        name = "Fellowship",
        category = M.CATEGORIES.SOCIAL,
        description = "Share a moment with a companion. Both charge a Bond with each other.",
        requiresTarget = true,
        targetType = "pc",
    },
    {
        id = "heal_companion",
        name = "Heal Companion",
        category = M.CATEGORIES.SOCIAL,
        description = "Clear Injured from an animal companion. Requires Bond.",
        requiresTarget = true,
        targetType = "companion",
        requiresBond = true,
    },

    ----------------------------------------------------------------------------
    -- EXPLORATION ACTIONS
    ----------------------------------------------------------------------------
    {
        id = "scout",
        name = "Scout",
        category = M.CATEGORIES.EXPLORATION,
        description = "Test Pentacles to reveal information about adjacent rooms.",
        requiresTarget = false,
        testSuit = "pentacles",
    },
    {
        id = "patrol",
        name = "Patrol",
        category = M.CATEGORIES.EXPLORATION,
        description = "Keep watch. Draw twice from Meatgrinder during Watch phase.",
        requiresTarget = false,
    },

    ----------------------------------------------------------------------------
    -- REST ACTIONS
    ----------------------------------------------------------------------------
    {
        id = "rest",
        name = "Rest",
        category = M.CATEGORIES.REST,
        description = "Simply rest. No cost, no benefit beyond safety.",
        requiresTarget = false,
    },
    {
        id = "tend_affliction",
        name = "Tend Affliction",
        category = M.CATEGORIES.REST,
        description = "Test Cups to clear an Affliction from yourself or an ally.",
        requiresTarget = true,
        targetType = "pc",
        testSuit = "cups",
    },
}

--------------------------------------------------------------------------------
-- LOOKUP TABLES
--------------------------------------------------------------------------------

M.byId = {}
M.byCategory = {
    [M.CATEGORIES.MAINTENANCE] = {},
    [M.CATEGORIES.SOCIAL] = {},
    [M.CATEGORIES.EXPLORATION] = {},
    [M.CATEGORIES.REST] = {},
}

-- Build lookup tables
for _, action in ipairs(M.ACTIONS) do
    M.byId[action.id] = action
    if M.byCategory[action.category] then
        table.insert(M.byCategory[action.category], action)
    end
end

--------------------------------------------------------------------------------
-- QUERY FUNCTIONS
--------------------------------------------------------------------------------

--- Get an action by ID
function M.getAction(actionId)
    return M.byId[actionId]
end

--- Get all actions for a category
function M.getActionsForCategory(category)
    return M.byCategory[category] or {}
end

--- Get actions available for a given entity
-- @param entity table: The adventurer
-- @param guild table: The party (for fellowship targets)
-- @return table: Array of available action definitions
function M.getAvailableActions(entity, guild)
    local available = {}

    for _, action in ipairs(M.ACTIONS) do
        local canUse = true

        -- Check item requirements
        if action.requiresItem then
            if entity and entity.inventory and entity.inventory.hasItemOfType then
                local hasItem = entity.inventory:hasItemOfType(action.requiresItem)
                if not hasItem then
                    canUse = false
                end
            else
                canUse = false
            end
        end

        -- Check if targeting PC but no other PCs available
        if action.targetType == "pc" and action.id ~= "tend_affliction" then
            local hasOtherPCs = false
            if guild then
                for _, pc in ipairs(guild) do
                    if pc.id ~= entity.id then
                        hasOtherPCs = true
                        break
                    end
                end
            end
            if not hasOtherPCs then
                canUse = false
            end
        end

        -- Check companion requirements
        if action.targetType == "companion" then
            local hasCompanion = entity.animalCompanions and #entity.animalCompanions > 0
            if not hasCompanion then
                canUse = false
            end
        end

        if canUse then
            available[#available + 1] = action
        end
    end

    return available
end

--------------------------------------------------------------------------------
-- ACTION RESOLUTION
--------------------------------------------------------------------------------

--- Resolve a camp action
-- @param actionData table: { type, actor, target, ... }
-- @param context table: { eventBus, guild, ... }
-- @return boolean, string: success, result message
function M.resolveAction(actionData, context)
    local actionDef = M.byId[actionData.type]
    if not actionDef then
        return false, "Unknown action: " .. tostring(actionData.type)
    end

    local actor = actionData.actor
    local target = actionData.target
    local eventBus = context.eventBus or events.globalBus

    -- Dispatch to specific handler
    if actionData.type == "repair" then
        return M.resolveRepair(actor, target, eventBus)
    elseif actionData.type == "fellowship" then
        return M.resolveFellowship(actor, target, eventBus)
    elseif actionData.type == "rest" then
        return M.resolveRest(actor, eventBus)
    elseif actionData.type == "heal_companion" then
        return M.resolveHealCompanion(actor, target, eventBus)
    elseif actionData.type == "scout" then
        return M.resolveScout(actor, context, eventBus)
    elseif actionData.type == "patrol" then
        return M.resolvePatrol(actor, context, eventBus)
    elseif actionData.type == "tend_affliction" then
        return M.resolveTendAffliction(actor, target, context, eventBus)
    end

    return false, "Action not implemented: " .. actionData.type
end

--------------------------------------------------------------------------------
-- REPAIR (S8.3)
--------------------------------------------------------------------------------
-- Remove 1 Notch from an item. Requires Tinker's Kit.

function M.resolveRepair(actor, targetItem, eventBus)
    if not targetItem then
        return false, "No item targeted for repair"
    end

    -- Check if item has notches to remove
    if not targetItem.notches or targetItem.notches <= 0 then
        return false, "Item has no notches to repair"
    end

    -- Check for Tinker's Kit
    local hasTinkersKit = false
    if actor.inventory and actor.inventory.hasItemOfType then
        hasTinkersKit = actor.inventory:hasItemOfType("tinkers_kit")
    end

    if not hasTinkersKit then
        return false, "Requires Tinker's Kit"
    end

    -- Perform repair
    targetItem.notches = targetItem.notches - 1

    eventBus:emit("camp_action_resolved", {
        action = "repair",
        actor = actor,
        target = targetItem,
        result = "notch_removed",
    })

    print("[CAMP] " .. actor.name .. " repaired " .. (targetItem.name or "item") ..
          " (notches: " .. targetItem.notches .. ")")

    return true, "repaired"
end

--------------------------------------------------------------------------------
-- FELLOWSHIP (S8.3)
--------------------------------------------------------------------------------
-- Target another PC. Both charge a Bond with each other.

function M.resolveFellowship(actor, targetPC, eventBus)
    if not targetPC then
        return false, "No companion targeted for fellowship"
    end

    if actor.id == targetPC.id then
        return false, "Cannot fellowship with yourself"
    end

    -- Initialize bonds tables if needed
    if not actor.bonds then actor.bonds = {} end
    if not targetPC.bonds then targetPC.bonds = {} end

    -- Initialize specific bonds if they don't exist
    if not actor.bonds[targetPC.id] then
        actor.bonds[targetPC.id] = { charged = false, name = targetPC.name }
    end
    if not targetPC.bonds[actor.id] then
        targetPC.bonds[actor.id] = { charged = false, name = actor.name }
    end

    -- Charge both bonds
    actor.bonds[targetPC.id].charged = true
    targetPC.bonds[actor.id].charged = true

    eventBus:emit("camp_action_resolved", {
        action = "fellowship",
        actor = actor,
        target = targetPC,
        result = "bonds_charged",
    })

    print("[CAMP] " .. actor.name .. " and " .. targetPC.name .. " share fellowship (bonds charged)")

    return true, "fellowship_complete"
end

--------------------------------------------------------------------------------
-- REST (S8.3)
--------------------------------------------------------------------------------
-- Generic fallback - no cost, no benefit other than safety.

function M.resolveRest(actor, eventBus)
    eventBus:emit("camp_action_resolved", {
        action = "rest",
        actor = actor,
        result = "rested",
    })

    print("[CAMP] " .. actor.name .. " rests quietly")

    return true, "rested"
end

--------------------------------------------------------------------------------
-- HEAL COMPANION (S8.3)
--------------------------------------------------------------------------------
-- Clear Injured from an animal companion. Requires a charged bond.

function M.resolveHealCompanion(actor, companion, eventBus)
    if not companion then
        return false, "No companion targeted"
    end

    -- Check if companion is injured
    if not companion.conditions or not companion.conditions.injured then
        return false, "Companion is not injured"
    end

    -- Check if actor has a charged bond (with anyone - represents care/attention)
    local hasChargedBond = false
    if actor.bonds then
        for _, bond in pairs(actor.bonds) do
            if bond.charged then
                hasChargedBond = true
                -- Spend the bond
                bond.charged = false
                break
            end
        end
    end

    if not hasChargedBond then
        return false, "Requires a charged bond"
    end

    -- Clear injured condition
    companion.conditions.injured = false

    eventBus:emit("camp_action_resolved", {
        action = "heal_companion",
        actor = actor,
        target = companion,
        result = "companion_healed",
    })

    print("[CAMP] " .. actor.name .. " tends to " .. (companion.name or "companion") ..
          " (injured cleared)")

    return true, "companion_healed"
end

--------------------------------------------------------------------------------
-- SCOUT (S8.3)
--------------------------------------------------------------------------------
-- Test Pentacles to reveal information about adjacent rooms.
-- Note: Full implementation requires room/map integration.

function M.resolveScout(actor, context, eventBus)
    -- This would normally involve a Pentacles test
    -- For MVP, mark actor as having scouted

    eventBus:emit("camp_action_resolved", {
        action = "scout",
        actor = actor,
        result = "scouted",
        requiresTest = true,
        testSuit = "pentacles",
    })

    print("[CAMP] " .. actor.name .. " scouts the area (test required)")

    return true, "scout_initiated"
end

--------------------------------------------------------------------------------
-- PATROL (S8.3)
--------------------------------------------------------------------------------
-- Keep watch. Draw twice from Meatgrinder during Watch phase.

function M.resolvePatrol(actor, context, eventBus)
    -- Mark that patrol was taken - affects Watch phase
    context.patrolActive = true
    context.patrolActor = actor

    eventBus:emit("camp_action_resolved", {
        action = "patrol",
        actor = actor,
        result = "patrolling",
    })

    print("[CAMP] " .. actor.name .. " takes patrol duty (double Meatgrinder draw)")

    return true, "patrol_active"
end

--------------------------------------------------------------------------------
-- TEND AFFLICTION (S8.3)
--------------------------------------------------------------------------------
-- Test Cups to clear an Affliction from yourself or an ally.
-- Note: Full implementation requires affliction system.

function M.resolveTendAffliction(actor, target, context, eventBus)
    target = target or actor

    -- Check if target has any affliction
    local hasAffliction = false
    local afflictionName = nil

    if target.afflictions then
        for name, _ in pairs(target.afflictions) do
            hasAffliction = true
            afflictionName = name
            break
        end
    end

    if not hasAffliction then
        return false, "Target has no affliction to tend"
    end

    eventBus:emit("camp_action_resolved", {
        action = "tend_affliction",
        actor = actor,
        target = target,
        affliction = afflictionName,
        result = "tend_initiated",
        requiresTest = true,
        testSuit = "cups",
    })

    print("[CAMP] " .. actor.name .. " tends to " .. target.name ..
          "'s " .. (afflictionName or "affliction") .. " (test required)")

    return true, "tend_initiated"
end

--------------------------------------------------------------------------------
-- CATEGORY DISPLAY NAME
--------------------------------------------------------------------------------

function M.getCategoryDisplayName(category)
    local names = {
        [M.CATEGORIES.MAINTENANCE] = "Maintenance",
        [M.CATEGORIES.SOCIAL] = "Social",
        [M.CATEGORIES.EXPLORATION] = "Exploration",
        [M.CATEGORIES.REST] = "Rest",
    }
    return names[category] or category
end

return M

```

---

## File: src/logic/camp_controller.lua

```lua
-- camp_controller.lua
-- Camp Phase State Machine for Majesty
-- Ticket S8.1: Orchestrates the 5 steps of the Camp Phase
--
-- Flow (Rulebook p. 136):
-- 1. SETUP    - Verify shelter/bedroll availability
-- 2. ACTIONS  - Each adventurer takes a camp action
-- 3. BREAK_BREAD - Consume rations (starvation if none)
-- 4. WATCH    - Meatgrinder draw for overnight events
-- 5. RECOVERY - Burn bonds to heal, clear stress
-- 6. TEARDOWN - Return to Crawl phase

local events = require('logic.events')
local campActions = require('logic.camp_actions')

local M = {}

--------------------------------------------------------------------------------
-- CAMP STATES
--------------------------------------------------------------------------------
M.STATES = {
    INACTIVE    = "inactive",
    SETUP       = "setup",
    ACTIONS     = "actions",
    BREAK_BREAD = "break_bread",
    WATCH       = "watch",
    RECOVERY    = "recovery",
    TEARDOWN    = "teardown",
}

--------------------------------------------------------------------------------
-- CAMP EVENTS
--------------------------------------------------------------------------------
M.EVENTS = {
    CAMP_START         = "camp_start",
    CAMP_END           = "camp_end",
    CAMP_STEP_CHANGED  = "camp_step_changed",
    RATION_CONSUMED    = "ration_consumed",
    STARVATION_WARNING = "starvation_warning",
    BOND_SPENT         = "bond_spent",
    CAMP_ACTION_TAKEN  = "camp_action_taken",
}

--------------------------------------------------------------------------------
-- CAMP CONTROLLER FACTORY
--------------------------------------------------------------------------------

--- Create a new CampController
-- @param config table: { eventBus, guild, watchManager, inventory }
-- @return CampController instance
function M.createCampController(config)
    config = config or {}

    local controller = {
        eventBus     = config.eventBus or events.globalBus,
        guild        = config.guild or {},
        watchManager = config.watchManager,
        meatgrinder  = config.meatgrinder,

        -- State tracking
        state        = M.STATES.INACTIVE,
        currentStep  = 0,

        -- Per-camp tracking
        actionsCompleted   = {},  -- { [entityId] = actionData }
        rationsConsumed    = {},  -- { [entityId] = true }
        recoveryCompleted  = {},  -- { [entityId] = true }
        watchResolved      = false,
        patrolActive       = false,  -- True if someone took Patrol action

        -- Shelter status (affects recovery quality)
        hasShelter   = false,
        hasBedrolls  = false,
    }

    ----------------------------------------------------------------------------
    -- STATE QUERIES
    ----------------------------------------------------------------------------

    function controller:getState()
        return self.state
    end

    function controller:getCurrentStep()
        return self.currentStep
    end

    function controller:isActive()
        return self.state ~= M.STATES.INACTIVE
    end

    ----------------------------------------------------------------------------
    -- START CAMP
    ----------------------------------------------------------------------------

    --- Start the camp phase
    -- @param campConfig table: { hasShelter, hasBedrolls }
    -- @return boolean, string: success, error message
    function controller:startCamp(campConfig)
        if self.state ~= M.STATES.INACTIVE then
            return false, "Camp already in progress"
        end

        campConfig = campConfig or {}

        -- Reset tracking
        self.actionsCompleted = {}
        self.rationsConsumed = {}
        self.recoveryCompleted = {}
        self.watchResolved = false
        self.patrolActive = false

        -- Check shelter/bedroll
        self.hasShelter = campConfig.hasShelter or false
        self.hasBedrolls = campConfig.hasBedrolls or false

        -- Emit start event
        self.eventBus:emit(M.EVENTS.CAMP_START, {
            guild = self.guild,
            hasShelter = self.hasShelter,
            hasBedrolls = self.hasBedrolls,
        })

        -- Move to setup
        self:transitionTo(M.STATES.SETUP)

        return true
    end

    ----------------------------------------------------------------------------
    -- STATE TRANSITIONS
    ----------------------------------------------------------------------------

    --- Transition to a new state
    function controller:transitionTo(newState)
        local oldState = self.state
        self.state = newState

        -- Map state to step number
        local stepMap = {
            [M.STATES.SETUP]       = 0,
            [M.STATES.ACTIONS]     = 1,
            [M.STATES.BREAK_BREAD] = 2,
            [M.STATES.WATCH]       = 3,
            [M.STATES.RECOVERY]    = 4,
            [M.STATES.TEARDOWN]    = 5,
        }
        self.currentStep = stepMap[newState] or 0

        self.eventBus:emit(M.EVENTS.CAMP_STEP_CHANGED, {
            oldState = oldState,
            newState = newState,
            step = self.currentStep,
        })

        print("[CAMP] Transitioned to: " .. newState .. " (Step " .. self.currentStep .. ")")

        -- Auto-execute certain steps
        if newState == M.STATES.SETUP then
            self:executeSetup()
        end
    end

    --- Advance to next step
    function controller:advanceStep()
        if self.state == M.STATES.SETUP then
            self:transitionTo(M.STATES.ACTIONS)
        elseif self.state == M.STATES.ACTIONS then
            if self:canAdvanceFromActions() then
                self:transitionTo(M.STATES.BREAK_BREAD)
            else
                return false, "Not all adventurers have taken actions"
            end
        elseif self.state == M.STATES.BREAK_BREAD then
            if self:canAdvanceFromBreakBread() then
                self:transitionTo(M.STATES.WATCH)
            else
                return false, "Rations not resolved for all adventurers"
            end
        elseif self.state == M.STATES.WATCH then
            if self.watchResolved then
                self:transitionTo(M.STATES.RECOVERY)
            else
                return false, "Watch not resolved"
            end
        elseif self.state == M.STATES.RECOVERY then
            self:transitionTo(M.STATES.TEARDOWN)
        elseif self.state == M.STATES.TEARDOWN then
            self:endCamp()
        end

        return true
    end

    ----------------------------------------------------------------------------
    -- STEP 0: SETUP
    ----------------------------------------------------------------------------

    function controller:executeSetup()
        -- Check shelter conditions
        if not self.hasShelter then
            print("[CAMP] Warning: No shelter - reduced recovery quality")
        end

        -- Auto-advance to actions after brief setup
        self:transitionTo(M.STATES.ACTIONS)
    end

    ----------------------------------------------------------------------------
    -- STEP 1: ACTIONS (S8.3)
    ----------------------------------------------------------------------------

    --- Submit a camp action for an adventurer
    -- @param entity table: The adventurer
    -- @param actionData table: { type, target, ... }
    function controller:submitAction(entity, actionData)
        if self.state ~= M.STATES.ACTIONS then
            return false, "Not in actions phase"
        end

        -- Add actor to action data
        actionData.actor = entity

        -- Resolve the action through camp_actions module
        local context = {
            eventBus = self.eventBus,
            guild = self.guild,
            patrolActive = self.patrolActive,
        }

        local success, result = campActions.resolveAction(actionData, context)

        if success then
            -- Track patrol status for watch phase
            if actionData.type == "patrol" then
                self.patrolActive = true
            end

            self.actionsCompleted[entity.id] = actionData

            self.eventBus:emit(M.EVENTS.CAMP_ACTION_TAKEN, {
                entity = entity,
                action = actionData,
                result = result,
            })

            print("[CAMP] " .. entity.name .. " takes action: " .. (actionData.type or "unknown"))
        end

        return success, result
    end

    --- Get available camp actions for an entity
    function controller:getAvailableActions(entity)
        return campActions.getAvailableActions(entity, self.guild)
    end

    function controller:canAdvanceFromActions()
        -- Check all guild members have submitted actions
        for _, pc in ipairs(self.guild) do
            if not self.actionsCompleted[pc.id] then
                return false
            end
        end
        return true
    end

    ----------------------------------------------------------------------------
    -- STEP 2: BREAK BREAD (S8.2)
    ----------------------------------------------------------------------------

    --- Consume a ration for an adventurer (S9.2)
    -- @param entity table: The adventurer
    -- @return boolean, string: success, result description
    function controller:consumeRation(entity)
        if self.state ~= M.STATES.BREAK_BREAD then
            return false, "Not in break bread phase"
        end

        -- Check inventory for rations using predicate search
        local rationItem = nil
        local rationLocation = nil

        if entity.inventory and entity.inventory.findItemByPredicate then
            rationItem, rationLocation = entity.inventory:findItemByPredicate(function(item)
                return item.isRation or
                       item.type == "ration" or
                       item.itemType == "ration" or
                       (item.properties and item.properties.isRation) or
                       (item.name and item.name:lower():find("ration"))
            end)
        end

        if rationItem then
            -- Consume the ration using proper inventory method
            if entity.inventory.removeItemQuantity then
                entity.inventory:removeItemQuantity(rationItem.id, 1)
            elseif entity.inventory.removeItem then
                entity.inventory:removeItem(rationItem.id)
            end

            -- Reset starvation counter
            entity.starvationCount = 0

            -- Clear starving condition if they were starving
            if entity.conditions and entity.conditions.starving then
                entity.conditions.starving = false
            end

            self.rationsConsumed[entity.id] = true

            self.eventBus:emit(M.EVENTS.RATION_CONSUMED, {
                entity = entity,
                item = rationItem,
            })

            print("[CAMP] " .. entity.name .. " ate a ration")
            return true, "ration_consumed"
        else
            -- No ration - apply starvation logic
            entity.starvationCount = (entity.starvationCount or 0) + 1

            -- First missed meal: Stressed
            if not entity.conditions then
                entity.conditions = {}
            end
            entity.conditions.stressed = true

            -- Second consecutive missed meal: Starving
            if entity.starvationCount >= 2 then
                entity.conditions.starving = true
                self.eventBus:emit(M.EVENTS.STARVATION_WARNING, {
                    entity = entity,
                    severity = "starving",
                })
                print("[CAMP] " .. entity.name .. " is STARVING!")
            else
                self.eventBus:emit(M.EVENTS.STARVATION_WARNING, {
                    entity = entity,
                    severity = "hungry",
                })
                print("[CAMP] " .. entity.name .. " goes hungry (stressed)")
            end

            self.rationsConsumed[entity.id] = true  -- Mark as resolved (even if hungry)
            return false, "no_ration"
        end
    end

    --- Skip eating for an adventurer (explicit choice to starve)
    function controller:skipRation(entity)
        return self:consumeRation(entity)  -- Same logic as not having a ration
    end

    function controller:canAdvanceFromBreakBread()
        for _, pc in ipairs(self.guild) do
            if not self.rationsConsumed[pc.id] then
                return false
            end
        end
        return true
    end

    ----------------------------------------------------------------------------
    -- STEP 3: WATCH
    ----------------------------------------------------------------------------

    --- Resolve the watch (overnight encounter check)
    -- @param doubleDraw boolean: True if someone took Patrol action (auto-detected if nil)
    function controller:resolveWatch(doubleDraw)
        if self.state ~= M.STATES.WATCH then
            return false, "Not in watch phase"
        end

        -- Auto-detect patrol if not specified
        if doubleDraw == nil then
            doubleDraw = self.patrolActive or false
        end

        -- Draw from meatgrinder
        if self.meatgrinder then
            local drawCount = doubleDraw and 2 or 1
            for _ = 1, drawCount do
                local result = self.meatgrinder:draw()
                if result then
                    print("[CAMP] Meatgrinder draw: " .. (result.description or "event"))
                    -- Handle the meatgrinder result
                    self.eventBus:emit("meatgrinder_result", result)
                end
            end
        end

        self.watchResolved = true
        print("[CAMP] Watch resolved" .. (doubleDraw and " (patrol active)" or ""))

        return true
    end

    ----------------------------------------------------------------------------
    -- STEP 4: RECOVERY (S8.4)
    ----------------------------------------------------------------------------

    --- Begin recovery for an adventurer
    -- Auto-clears staggered (unless stressed) and refills lore bids
    function controller:beginRecovery(entity)
        if self.state ~= M.STATES.RECOVERY then
            return false, "Not in recovery phase"
        end

        -- Refill lore bids (always happens)
        entity.loreBids = 4

        -- Auto-clear staggered (UNLESS stressed)
        if entity.conditions and not entity.conditions.stressed then
            entity.conditions.staggered = false
            print("[CAMP] " .. entity.name .. " clears Staggered")
        end

        return true
    end

    --- Spend a bond for recovery
    -- @param entity table: The adventurer
    -- @param bondTargetId string: ID of the bond partner
    -- @param spendType string: "heal_wound", "regain_resolve", or "clear_stress"
    function controller:spendBondForRecovery(entity, bondTargetId, spendType)
        if self.state ~= M.STATES.RECOVERY then
            return false, "Not in recovery phase"
        end

        -- Check if entity has the bond and it's charged
        if not entity.bonds or not entity.bonds[bondTargetId] then
            return false, "No bond with that entity"
        end

        if not entity.bonds[bondTargetId].charged then
            return false, "Bond is not charged"
        end

        -- STRESS GATE: If stressed, MUST clear stress first
        if entity.conditions and entity.conditions.stressed then
            if spendType ~= "clear_stress" then
                return false, "Must clear stress first"
            end
        end

        -- Spend the bond
        entity.bonds[bondTargetId].charged = false

        -- Apply benefit
        local result = "unknown"
        if spendType == "clear_stress" then
            if entity.conditions then
                entity.conditions.stressed = false
            end
            result = "stress_cleared"
        elseif spendType == "heal_wound" then
            -- Use entity's healWound method (respects injury gate)
            if entity.healWound then
                local healResult, err = entity:healWound()
                if healResult then
                    result = healResult
                else
                    -- Refund the bond if healing failed
                    entity.bonds[bondTargetId].charged = true
                    return false, err or "cannot_heal"
                end
            end
        elseif spendType == "regain_resolve" then
            if entity.regainResolve then
                entity:regainResolve(1)
                result = "resolve_regained"
            end
        end

        self.eventBus:emit(M.EVENTS.BOND_SPENT, {
            entity = entity,
            bondTargetId = bondTargetId,
            spendType = spendType,
            result = result,
        })

        print("[CAMP] " .. entity.name .. " spent bond with " .. bondTargetId .. " for: " .. result)

        return true, result
    end

    --- Mark recovery complete for an entity
    function controller:completeRecovery(entity)
        self.recoveryCompleted[entity.id] = true
    end

    ----------------------------------------------------------------------------
    -- STEP 5: TEARDOWN / END CAMP (S9.4)
    ----------------------------------------------------------------------------

    function controller:endCamp()
        -- Process end-of-camp effects for all guild members
        for _, pc in ipairs(self.guild) do
            self:processEndOfCampEffects(pc)
        end

        self.state = M.STATES.INACTIVE

        -- Emit camp end event
        self.eventBus:emit(M.EVENTS.CAMP_END, {
            guild = self.guild,
        })

        -- S9.4: Emit phase change to transition back to crawl
        self.eventBus:emit("phase_changed", {
            oldPhase = "camp",
            newPhase = "crawl",
        })

        print("[CAMP] Camp phase ended - returning to crawl")
    end

    --- Process end-of-camp effects for a single entity (S9.4)
    function controller:processEndOfCampEffects(entity)
        if not entity.conditions then
            entity.conditions = {}
        end

        -- 1. Advance afflictions (if entity has any)
        if entity.afflictions then
            for afflictionName, affliction in pairs(entity.afflictions) do
                -- Only advance if not cured this camp
                if not affliction.curedThisCamp then
                    affliction.stage = (affliction.stage or 1) + 1
                    print("[CAMP] " .. entity.name .. "'s " .. afflictionName ..
                          " advanced to stage " .. affliction.stage)

                    -- Check for affliction climax (stage 4+ typically)
                    if affliction.stage >= 4 and affliction.onClimax then
                        affliction.onClimax(entity)
                    end
                else
                    -- Reset cured flag for next camp
                    affliction.curedThisCamp = false
                end
            end
        end

        -- 2. Check shelter/bedroll - apply Stressed if missing
        -- hasBedrolls is checked at camp level
        if not self.hasBedrolls and not self.hasShelter then
            entity.conditions.stressed = true
            print("[CAMP] " .. entity.name .. " wakes Stressed (no bedroll/shelter)")
        end

        -- 3. Animal companions also need to be checked
        if entity.animalCompanions then
            for _, companion in ipairs(entity.animalCompanions) do
                self:processEndOfCampEffects(companion)
            end
        end
    end

    ----------------------------------------------------------------------------
    -- UTILITY
    ----------------------------------------------------------------------------

    --- Get list of adventurers who haven't completed current step
    function controller:getPendingAdventurers()
        local pending = {}

        for _, pc in ipairs(self.guild) do
            local isPending = false

            if self.state == M.STATES.ACTIONS then
                isPending = not self.actionsCompleted[pc.id]
            elseif self.state == M.STATES.BREAK_BREAD then
                isPending = not self.rationsConsumed[pc.id]
            elseif self.state == M.STATES.RECOVERY then
                isPending = not self.recoveryCompleted[pc.id]
            end

            if isPending then
                pending[#pending + 1] = pc
            end
        end

        return pending
    end

    return controller
end

return M

```

---

## File: src/logic/challenge_controller.lua

```lua
-- challenge_controller.lua
-- Challenge Phase Controller for Majesty
-- Tickets S4.1, S4.6, S4.7: Turn-based state machine with initiative and count-up
--
-- Flow:
-- 1. PRE_ROUND: All entities submit initiative cards (facedown)
-- 2. COUNT_UP: Count from 1-14 (Ace to King), entities act when their card is called
-- 3. Each action: AWAITING_ACTION -> RESOLVING -> VISUAL_SYNC -> MINOR_WINDOW
-- 4. After count reaches 14, new round starts at PRE_ROUND
--
-- The controller PAUSES after each action until UI_SEQUENCE_COMPLETE fires.

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- CHALLENGE STATES
--------------------------------------------------------------------------------
M.STATES = {
    IDLE            = "idle",             -- No challenge active
    STARTING        = "starting",         -- Challenge is initializing
    PRE_ROUND       = "pre_round",        -- Initiative submission phase (S4.6)
    COUNT_UP        = "count_up",         -- Counting 1-14 for turn order (S4.7)
    AWAITING_ACTION = "awaiting_action",  -- Waiting for active entity to act
    RESOLVING       = "resolving",        -- Processing action result
    VISUAL_SYNC     = "visual_sync",      -- Waiting for UI to complete animation
    MINOR_WINDOW    = "minor_window",     -- Minor action opportunity (2 sec)
    ENDING          = "ending",           -- Challenge wrapping up
}

--------------------------------------------------------------------------------
-- CHALLENGE OUTCOMES
--------------------------------------------------------------------------------
M.OUTCOMES = {
    VICTORY     = "victory",     -- All enemies defeated
    DEFEAT      = "defeat",      -- All PCs defeated
    FLED        = "fled",        -- Party successfully fled
    TIME_OUT    = "time_out",    -- 14 turns elapsed
    NEGOTIATED  = "negotiated",  -- Combat ended via Banter
}

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------
local MAX_TURNS = 14
local MINOR_ACTION_WINDOW_DURATION = 2.0  -- seconds

--------------------------------------------------------------------------------
-- CHALLENGE CONTROLLER FACTORY
--------------------------------------------------------------------------------

--- Create a new ChallengeController
-- @param config table: { eventBus, playerDeck, gmDeck, guild }
-- @return ChallengeController instance
function M.createChallengeController(config)
    config = config or {}

    local controller = {
        eventBus   = config.eventBus or events.globalBus,
        playerDeck = config.playerDeck,
        gmDeck     = config.gmDeck,
        guild      = config.guild or {},  -- PC entities

        -- Challenge state
        state           = M.STATES.IDLE,
        currentRound    = 0,          -- Which round of combat (can have multiple)
        activeEntity    = nil,        -- Current acting entity

        -- Combatants
        pcs             = {},         -- PC entities in this challenge
        npcs            = {},         -- NPC/Mob entities in this challenge
        allCombatants   = {},         -- Combined list

        -- Initiative tracking (S4.6)
        initiativeSlots = {},         -- entity.id -> { card, revealed }
        awaitingInitiative = {},      -- Entities that haven't submitted initiative yet

        -- Count-up tracking (S4.7)
        currentCount    = 0,          -- Current initiative count (1-14)
        actedThisRound  = {},         -- entity.id -> true if already acted

        -- Minor action tracking (S6.4: Declaration Loop)
        minorActionTimer    = 0,
        minorActionUsed     = false,
        pendingMinors       = {},     -- Committed minor actions { actor, card, action, target }
        minorWindowActive   = false,  -- True while in minor window (paused)
        resolvingMinors     = false,  -- True while resolving pending minor actions

        -- Visual sync
        awaitingVisualSync  = false,
        pendingAction       = nil,    -- Action waiting for visual completion

        -- Challenge context
        roomId          = nil,
        zoneId          = nil,
        zones           = nil,        -- Array of zone definitions { id, name, description }
        challengeType   = nil,        -- "combat", "trap", "hazard", "social"

        -- Fool interrupt tracking (S4.9)
        pendingFoolRestore = nil,     -- { state, activeEntity } to restore after Fool
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    --- Initialize and subscribe to events
    function controller:init()
        -- Listen for visual completion
        self.eventBus:on(events.EVENTS.UI_SEQUENCE_COMPLETE, function(data)
            self:onVisualComplete(data)
        end)

        -- Listen for minor actions
        self.eventBus:on(events.EVENTS.MINOR_ACTION_USED, function(data)
            self:onMinorActionUsed(data)
        end)
    end

    ----------------------------------------------------------------------------
    -- CHALLENGE LIFECYCLE
    ----------------------------------------------------------------------------

    --- Start a new challenge
    -- @param config table: { pcs, npcs, roomId, zoneId, challengeType }
    -- @return boolean, string: success, error
    function controller:startChallenge(challengeConfig)
        if self.state ~= M.STATES.IDLE then
            return false, "challenge_already_active"
        end

        challengeConfig = challengeConfig or {}

        -- Set up combatants
        self.pcs = challengeConfig.pcs or self.guild
        self.npcs = challengeConfig.npcs or {}
        self.roomId = challengeConfig.roomId
        self.zoneId = challengeConfig.zoneId
        self.zones = challengeConfig.zones  -- Store zone data for arena view
        self.challengeType = challengeConfig.challengeType or "combat"

        -- Validate we have combatants
        if #self.pcs == 0 then
            return false, "no_pcs"
        end
        if #self.npcs == 0 and self.challengeType == "combat" then
            return false, "no_npcs"
        end

        -- Build combatant list
        self:buildCombatantList()

        -- Initialize state
        self.state = M.STATES.STARTING
        self.currentRound = 0

        -- Emit start event
        self.eventBus:emit(events.EVENTS.CHALLENGE_START, {
            pcs = self.pcs,
            npcs = self.npcs,
            roomId = self.roomId,
            zones = self.zones,  -- Pass zones to arena view
            challengeType = self.challengeType,
        })

        -- Begin first round (initiative submission)
        self:startNewRound()

        return true
    end

    --- End the current challenge
    -- @param outcome string: One of OUTCOMES
    -- @param data table: Additional outcome data
    function controller:endChallenge(outcome, data)
        data = data or {}
        data.outcome = outcome
        data.finalTurn = self.currentTurn
        data.pcs = self.pcs
        data.npcs = self.npcs

        self.state = M.STATES.ENDING

        -- Emit end event
        self.eventBus:emit(events.EVENTS.CHALLENGE_END, data)

        -- Reset state
        self:reset()
    end

    --- Reset controller to idle state
    function controller:reset()
        self.state = M.STATES.IDLE
        self.currentRound = 0
        self.activeEntity = nil
        self.pcs = {}
        self.npcs = {}
        self.allCombatants = {}

        -- Initiative tracking
        self.initiativeSlots = {}
        self.awaitingInitiative = {}

        -- Count-up tracking
        self.currentCount = 0
        self.actedThisRound = {}

        -- Minor action
        self.minorActionTimer = 0
        self.minorActionUsed = false
        self.pendingMinors = {}
        self.minorWindowActive = false
        self.resolvingMinors = false

        -- Visual sync
        self.awaitingVisualSync = false
        self.pendingAction = nil
    end

    ----------------------------------------------------------------------------
    -- COMBATANT MANAGEMENT
    ----------------------------------------------------------------------------

    --- Build the list of all combatants (not ordered - initiative determines order)
    function controller:buildCombatantList()
        self.allCombatants = {}

        -- Add all living PCs
        for _, pc in ipairs(self.pcs) do
            if not self:isDefeated(pc) then
                self.allCombatants[#self.allCombatants + 1] = pc
            end
        end

        -- Add all living NPCs
        for _, npc in ipairs(self.npcs) do
            if not self:isDefeated(npc) then
                self.allCombatants[#self.allCombatants + 1] = npc
            end
        end
    end

    ----------------------------------------------------------------------------
    -- ROUND MANAGEMENT (S4.6)
    ----------------------------------------------------------------------------

    --- Start a new round of combat
    function controller:startNewRound()
        self.currentRound = self.currentRound + 1

        -- Check end conditions before starting new round
        local outcome = self:checkEndConditions()
        if outcome then
            self:endChallenge(outcome)
            return
        end

        -- Rebuild combatant list (in case someone died)
        self:buildCombatantList()

        -- Reset round tracking
        self.initiativeSlots = {}
        self.awaitingInitiative = {}
        self.actedThisRound = {}
        self.currentCount = 0

        -- Mark all living combatants as needing initiative
        for _, entity in ipairs(self.allCombatants) do
            self.awaitingInitiative[entity.id] = true
        end

        -- Enter pre-round state
        self.state = M.STATES.PRE_ROUND

        -- Emit event for UI
        self.eventBus:emit("initiative_phase_start", {
            round = self.currentRound,
            combatants = self.allCombatants,
        })

        -- Trigger NPC initiative selection
        for _, entity in ipairs(self.allCombatants) do
            if not entity.isPC then
                self:triggerNPCInitiative(entity)
            end
        end

        print("[Challenge] Round " .. self.currentRound .. " - Awaiting initiative from " .. #self.allCombatants .. " combatants")
    end

    --- Submit initiative card for an entity (S4.6)
    -- @param entity table: The entity submitting
    -- @param card table: The card being used for initiative
    -- @return boolean, string: success, error
    function controller:submitInitiative(entity, card)
        if self.state ~= M.STATES.PRE_ROUND then
            return false, "not_in_pre_round"
        end

        if not entity or not entity.id then
            return false, "invalid_entity"
        end

        if not self.awaitingInitiative[entity.id] then
            return false, "already_submitted"
        end

        if not card then
            return false, "no_card"
        end

        -- Store the initiative card (facedown)
        self.initiativeSlots[entity.id] = {
            card = card,
            revealed = false,
            value = card.value or 0,
        }

        -- Remove from awaiting list
        self.awaitingInitiative[entity.id] = nil

        print("[Initiative] " .. (entity.name or entity.id) .. " submitted: " .. (card.name or "?") .. " (value " .. (card.value or 0) .. ")")

        -- Emit event
        self.eventBus:emit("initiative_submitted", {
            entity = entity,
            -- Don't include card details - it's facedown!
        })

        -- Check if all initiatives are in
        if self:allInitiativesSubmitted() then
            self:beginCountUp()
        end

        return true
    end

    --- Check if all combatants have submitted initiative
    function controller:allInitiativesSubmitted()
        for id, _ in pairs(self.awaitingInitiative) do
            return false  -- At least one is still waiting
        end
        return true
    end

    ----------------------------------------------------------------------------
    -- COUNT-UP SYSTEM (S4.7)
    ----------------------------------------------------------------------------

    --- Begin the count-up phase after all initiatives submitted
    function controller:beginCountUp()
        self.state = M.STATES.COUNT_UP
        self.currentCount = 0

        print("[Challenge] All initiatives submitted. Beginning count-up!")

        self.eventBus:emit("count_up_start", {
            round = self.currentRound,
        })

        -- Start counting
        self:advanceCount()
    end

    --- Advance to the next count value
    function controller:advanceCount()
        -- Check end conditions
        local outcome = self:checkEndConditions()
        if outcome then
            self:endChallenge(outcome)
            return
        end

        self.currentCount = self.currentCount + 1

        -- Round complete when count exceeds 14 (King)
        if self.currentCount > MAX_TURNS then
            print("[Challenge] Round " .. self.currentRound .. " complete!")
            self:startNewRound()
            return
        end

        -- Emit count event for UI
        self.eventBus:emit("count_up_tick", {
            count = self.currentCount,
            round = self.currentRound,
        })

        -- Find entities whose initiative matches current count
        local actingEntities = self:getEntitiesAtCount(self.currentCount)

        if #actingEntities > 0 then
            -- Sort by PC first (tie-breaker: PCs act before NPCs, p.112)
            table.sort(actingEntities, function(a, b)
                -- PCs go first unless NPC has shield (simplified for now)
                if a.isPC and not b.isPC then return true end
                if b.isPC and not a.isPC then return false end
                return false  -- Same type, maintain order
            end)

            -- Start first entity's turn
            self:startEntityTurn(actingEntities[1])
        else
            -- No one acts at this count, continue immediately
            self:advanceCount()
        end
    end

    --- Get all entities whose initiative matches a count value
    function controller:getEntitiesAtCount(count)
        local result = {}
        for _, entity in ipairs(self.allCombatants) do
            if not self:isDefeated(entity) and not self.actedThisRound[entity.id] then
                local slot = self.initiativeSlots[entity.id]
                if slot and slot.value == count then
                    result[#result + 1] = entity
                end
            end
        end
        return result
    end

    --- Start a specific entity's turn
    function controller:startEntityTurn(entity)
        self.activeEntity = entity
        self.state = M.STATES.AWAITING_ACTION

        -- Reveal their initiative card
        local slot = self.initiativeSlots[entity.id]
        if slot then
            slot.revealed = true
        end

        -- Emit turn start
        self.eventBus:emit(events.EVENTS.CHALLENGE_TURN_START, {
            count = self.currentCount,
            round = self.currentRound,
            activeEntity = self.activeEntity,
            isPC = self.activeEntity.isPC,
            initiativeCard = slot and slot.card,
        })

        print("[Turn] Count " .. self.currentCount .. ": " .. (entity.name or entity.id) .. "'s turn")

        -- If NPC, trigger AI decision
        if not self.activeEntity.isPC then
            self:triggerNPCAction()
        end
        -- If PC, wait for player input (handled externally)
    end

    --- Called after an entity completes their turn
    function controller:completeTurn()
        if self.activeEntity then
            self.actedThisRound[self.activeEntity.id] = true
        end

        self.activeEntity = nil

        -- Check for more entities at current count
        local moreAtCount = self:getEntitiesAtCount(self.currentCount)
        if #moreAtCount > 0 then
            self:startEntityTurn(moreAtCount[1])
        else
            -- Continue counting
            self:advanceCount()
        end
    end

    --- Check if challenge should end
    -- @return string|nil: Outcome or nil if challenge continues
    function controller:checkEndConditions()
        -- Count surviving PCs
        local survivingPCs = 0
        for _, pc in ipairs(self.pcs) do
            if not self:isDefeated(pc) then
                survivingPCs = survivingPCs + 1
            end
        end

        -- Count surviving NPCs
        local survivingNPCs = 0
        for _, npc in ipairs(self.npcs) do
            if not self:isDefeated(npc) then
                survivingNPCs = survivingNPCs + 1
            end
        end

        -- All NPCs defeated = victory
        if survivingNPCs == 0 and #self.npcs > 0 then
            return M.OUTCOMES.VICTORY
        end

        -- All PCs defeated = defeat
        if survivingPCs == 0 then
            return M.OUTCOMES.DEFEAT
        end

        return nil
    end

    --- Check if an entity is defeated
    function controller:isDefeated(entity)
        if not entity then return true end
        if entity.conditions and entity.conditions.dead then
            return true
        end
        if entity.conditions and entity.conditions.deaths_door then
            -- Could be defeated but not dead
            return false
        end
        return false
    end

    ----------------------------------------------------------------------------
    -- ACTION HANDLING
    ----------------------------------------------------------------------------

    --- Submit an action for the active entity
    -- @param action table: { type, target, card, ... }
    -- @return boolean, string: success, error
    function controller:submitAction(action)
        if self.state ~= M.STATES.AWAITING_ACTION then
            return false, "not_awaiting_action"
        end

        if not self.activeEntity then
            return false, "no_active_entity"
        end

        action.actor = self.activeEntity
        action.round = self.currentRound
        action.count = self.currentCount

        -- Move to resolving state
        self.state = M.STATES.RESOLVING
        self.pendingAction = action

        -- Emit action event for resolution
        self.eventBus:emit(events.EVENTS.CHALLENGE_ACTION, action)

        -- Resolution happens in action resolver, which will call back
        -- For now, simulate immediate resolution
        self:resolveAction(action)

        return true
    end

    --- Resolve an action (called by action resolver)
    function controller:resolveAction(action)
        -- Store the result
        local result = action.result or { success = false }

        -- Emit resolution event
        self.eventBus:emit(events.EVENTS.CHALLENGE_RESOLUTION, {
            action = action,
            result = result,
        })

        -- Enter visual sync - wait for UI to show the result
        self.state = M.STATES.VISUAL_SYNC
        self.awaitingVisualSync = true

        -- The ActionSequencer will emit UI_SEQUENCE_COMPLETE when done
    end

    --- Called when visual sequence completes
    function controller:onVisualComplete(data)
        if not self.awaitingVisualSync then
            return
        end

        self.awaitingVisualSync = false
        self.pendingAction = nil

        -- S4.9: Check if this was a Fool interrupt
        if self.pendingFoolRestore then
            self:completeFoolInterrupt()
            return
        end

        -- S6.4: Check if we're resolving minor actions
        if self.resolvingMinors then
            -- Process next minor action if any remain
            if #self.pendingMinors > 0 then
                self:processNextMinorAction()
            else
                -- All minors resolved
                self.resolvingMinors = false
                self:completeTurn()
            end
            return
        end

        -- Emit turn end
        self.eventBus:emit(events.EVENTS.CHALLENGE_TURN_END, {
            count = self.currentCount,
            round = self.currentRound,
            entity = self.activeEntity,
        })

        -- Enter minor action window
        self:startMinorActionWindow()
    end

    ----------------------------------------------------------------------------
    -- MINOR ACTION WINDOW (S6.4: Declaration Loop)
    ----------------------------------------------------------------------------

    --- Start the minor action opportunity window
    -- The count-up PAUSES here until Resume is clicked
    function controller:startMinorActionWindow()
        self.state = M.STATES.MINOR_WINDOW
        self.pendingMinors = {}
        self.minorWindowActive = true

        -- Emit state change for UI
        self.eventBus:emit("challenge_state_changed", {
            newState = "minor_window",
            count = self.currentCount,
            round = self.currentRound,
        })

        self.eventBus:emit(events.EVENTS.MINOR_ACTION_WINDOW, {
            count = self.currentCount,
            round = self.currentRound,
            paused = true,  -- Indicate this is a paused window
        })

        print("[MINOR WINDOW] Paused for minor action declarations. Click Resume to continue.")
    end

    --- Declare a minor action (adds to pending list)
    -- @param entity table: The entity declaring the minor action
    -- @param card table: The card being used (must match action suit)
    -- @param action table: { type, target, ... }
    -- @return boolean, string: success, error
    function controller:declareMinorAction(entity, card, action)
        if self.state ~= M.STATES.MINOR_WINDOW then
            return false, "not_in_minor_window"
        end

        if not entity or not card or not action then
            return false, "invalid_minor_declaration"
        end

        -- Verify card suit matches action suit (S6.2/S6.4 requirement)
        local actionRegistry = require('data.action_registry')
        local cardSuit = actionRegistry.cardSuitToActionSuit(card.suit)
        local actionDef = actionRegistry.getAction(action.type)

        if actionDef then
            if actionDef.suit ~= cardSuit and actionDef.suit ~= actionRegistry.SUITS.MISC then
                return false, "suit_mismatch"
            end
            if actionDef.suit == actionRegistry.SUITS.MISC then
                return false, "misc_not_allowed"  -- Misc actions not allowed as minors
            end
        end

        -- Add to pending minors
        local declaration = {
            entity = entity,
            card = card,
            action = action,
            declaredAt = #self.pendingMinors + 1,  -- Order of declaration
        }

        self.pendingMinors[#self.pendingMinors + 1] = declaration

        print("[MINOR] " .. (entity.name or entity.id) .. " declares " ..
              (action.type or "action") .. " with " .. (card.name or "card"))

        self.eventBus:emit("minor_action_declared", {
            entity = entity,
            card = card,
            action = action,
            position = #self.pendingMinors,
        })

        return true
    end

    --- Remove a declared minor action
    function controller:undeclareMinorAction(index)
        if self.state ~= M.STATES.MINOR_WINDOW then
            return false, "not_in_minor_window"
        end

        if index < 1 or index > #self.pendingMinors then
            return false, "invalid_index"
        end

        local removed = table.remove(self.pendingMinors, index)

        self.eventBus:emit("minor_action_undeclared", {
            entity = removed.entity,
            position = index,
        })

        return true
    end

    --- Resume from minor window and resolve all pending minors
    -- Called when "Resume" button is clicked
    function controller:resumeFromMinorWindow()
        if self.state ~= M.STATES.MINOR_WINDOW then
            return false, "not_in_minor_window"
        end

        print("[MINOR WINDOW] Resuming with " .. #self.pendingMinors .. " pending actions")

        self.minorWindowActive = false

        -- Emit state change
        self.eventBus:emit("challenge_state_changed", {
            newState = "resolving_minors",
            pendingCount = #self.pendingMinors,
        })

        -- Process pending minors in declaration order
        if #self.pendingMinors > 0 then
            self:processNextMinorAction()
        else
            -- No minors declared, continue to next turn
            self:completeTurn()
        end

        return true
    end

    --- Process the next pending minor action
    function controller:processNextMinorAction()
        if #self.pendingMinors == 0 then
            -- All minors processed, continue turn
            self:completeTurn()
            return
        end

        -- Get next minor in order
        local minor = table.remove(self.pendingMinors, 1)

        print("[MINOR RESOLVE] Processing " .. (minor.entity.name or minor.entity.id) ..
              "'s " .. (minor.action.type or "action"))

        -- Build the full action
        local fullAction = minor.action
        fullAction.actor = minor.entity
        fullAction.card = minor.card
        fullAction.isMinorAction = true  -- Flag for resolver (uses face value only)

        -- Emit action for resolution
        self.eventBus:emit(events.EVENTS.CHALLENGE_ACTION, fullAction)

        -- Wait for visual sync before processing next minor
        self.state = M.STATES.VISUAL_SYNC
        self.awaitingVisualSync = true
        self.pendingAction = fullAction

        -- The onVisualComplete will be called after animation
        -- We need to track that we're resolving minors
        self.resolvingMinors = true
    end

    --- Called when a minor action is used (legacy compatibility)
    function controller:onMinorActionUsed(data)
        if self.state ~= M.STATES.MINOR_WINDOW then
            return
        end

        -- Legacy: single minor action used
        self.minorActionUsed = true

        -- Continue to next entity/count
        self:completeTurn()
    end

    --- Update function (call from love.update)
    function controller:update(dt)
        -- S6.4: Minor window is now paused indefinitely, no timer
        -- The window only ends when Resume is clicked
    end

    ----------------------------------------------------------------------------
    -- NPC AI TRIGGERS
    ----------------------------------------------------------------------------

    --- Trigger AI to choose initiative card (S4.6)
    function controller:triggerNPCInitiative(npc)
        self.eventBus:emit("npc_choose_initiative", {
            npc = npc,
            round = self.currentRound,
        })
    end

    --- Trigger AI to decide NPC action
    function controller:triggerNPCAction()
        -- The AI system will listen for CHALLENGE_TURN_START where isPC = false
        -- and submit an action via submitAction()
        self.eventBus:emit("npc_turn", {
            npc = self.activeEntity,
            count = self.currentCount,
            round = self.currentRound,
            pcs = self.pcs,
        })
    end

    ----------------------------------------------------------------------------
    -- FLEE HANDLING
    ----------------------------------------------------------------------------

    --- Attempt to flee from the challenge
    -- @param entity table: The entity attempting to flee
    -- @return boolean: success
    function controller:attemptFlee(entity)
        -- Flee logic would involve a test
        -- For now, simplified: flee always succeeds if no engagement
        local success = true

        if success then
            -- Remove entity from combatants
            for i, e in ipairs(self.allCombatants) do
                if e == entity then
                    table.remove(self.allCombatants, i)
                    break
                end
            end

            -- Check if all PCs fled
            local remainingPCs = 0
            for _, e in ipairs(self.allCombatants) do
                if e.isPC then
                    remainingPCs = remainingPCs + 1
                end
            end

            if remainingPCs == 0 then
                self:endChallenge(M.OUTCOMES.FLED)
            end
        end

        return success
    end

    ----------------------------------------------------------------------------
    -- THE FOOL INTERRUPT (S4.9)
    -- The Fool allows immediate out-of-turn action
    ----------------------------------------------------------------------------

    --- Play The Fool to interrupt and take an immediate action
    -- @param entity table: The entity playing The Fool
    -- @param foolCard table: The Fool card being played
    -- @param followUpCard table: Optional follow-up card for the action
    -- @param action table: Optional action to take immediately
    -- @return boolean, string: success, error
    function controller:playFoolInterrupt(entity, foolCard, followUpCard, action)
        -- Can only interrupt during COUNT_UP, AWAITING_ACTION, or MINOR_WINDOW
        if self.state ~= M.STATES.COUNT_UP and
           self.state ~= M.STATES.AWAITING_ACTION and
           self.state ~= M.STATES.MINOR_WINDOW then
            return false, "cannot_interrupt_now"
        end

        if not entity or not foolCard then
            return false, "invalid_fool_interrupt"
        end

        -- Verify it's The Fool
        if foolCard.name ~= "The Fool" and not (foolCard.is_major and foolCard.value == 0) then
            return false, "not_the_fool"
        end

        print("[FOOL INTERRUPT] " .. (entity.name or entity.id) .. " plays The Fool!")

        -- Store the current state to restore after interrupt
        local previousState = self.state
        local previousActive = self.activeEntity

        -- Emit interrupt event
        self.eventBus:emit("fool_interrupt_start", {
            entity = entity,
            card = foolCard,
            previousState = previousState,
            previousActive = previousActive,
        })

        -- Temporarily make the interrupting entity active
        self.activeEntity = entity
        self.state = M.STATES.RESOLVING

        -- Build the interrupt action
        local interruptAction = action or {
            actor = entity,
            card = foolCard,
            type = "fool_interrupt",
            followUpCard = followUpCard,
            followUpAction = action and action.type,
            target = action and action.target,
        }

        -- Emit the action for resolution
        self.eventBus:emit(events.EVENTS.CHALLENGE_ACTION, interruptAction)

        -- If no follow-up specified, wait for player to choose
        if not followUpCard and not action then
            self.eventBus:emit("fool_awaiting_followup", {
                entity = entity,
            })
        end

        -- Note: Resolution will call back via resolveAction()
        -- After resolution, we need to restore the previous state
        self.pendingFoolRestore = {
            state = previousState,
            activeEntity = previousActive,
        }

        return true
    end

    --- Called after Fool interrupt resolves to restore state
    function controller:completeFoolInterrupt()
        if self.pendingFoolRestore then
            self.state = self.pendingFoolRestore.state
            self.activeEntity = self.pendingFoolRestore.activeEntity
            self.pendingFoolRestore = nil

            self.eventBus:emit("fool_interrupt_complete", {})

            print("[FOOL INTERRUPT] Complete, resuming normal turn order")
        end
    end

    ----------------------------------------------------------------------------
    -- QUERIES
    ----------------------------------------------------------------------------

    function controller:isActive()
        return self.state ~= M.STATES.IDLE
    end

    function controller:getCurrentCount()
        return self.currentCount
    end

    function controller:getCurrentRound()
        return self.currentRound
    end

    --- Legacy compatibility: getCurrentTurn returns count
    function controller:getCurrentTurn()
        return self.currentCount
    end

    function controller:getMaxTurns()
        return MAX_TURNS
    end

    function controller:getActiveEntity()
        return self.activeEntity
    end

    function controller:getState()
        return self.state
    end

    function controller:getCombatants()
        return self.allCombatants
    end

    function controller:isPlayerTurn()
        return self.activeEntity and self.activeEntity.isPC
    end

    function controller:isAwaitingInitiative()
        return self.state == M.STATES.PRE_ROUND
    end

    function controller:getAwaitingInitiativeList()
        local list = {}
        for id, _ in pairs(self.awaitingInitiative) do
            list[#list + 1] = id
        end
        return list
    end

    function controller:getInitiativeSlot(entityId)
        return self.initiativeSlots[entityId]
    end

    --- S6.4: Check if in minor action window
    function controller:isInMinorWindow()
        return self.state == M.STATES.MINOR_WINDOW
    end

    --- S6.4: Get pending minor actions
    function controller:getPendingMinors()
        return self.pendingMinors
    end

    return controller
end

return M

```

---

## File: src/logic/environment_manager.lua

```lua
-- environment_manager.lua
-- Environmental Stress Handler for Majesty
-- Ticket T3_3: Implements "Environmental Stress" (p. 96)
--
-- Stressors: Travel Events (XI-XV) with "Gross" or "Terrifying" outcomes
-- Stress Gate: Entity cannot clear any other condition until stressed is removed

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- STRESS REASONS
-- Different sources that can cause stress
--------------------------------------------------------------------------------
M.STRESS_REASONS = {
    GROSS      = "gross",        -- Disturbing physical things
    TERRIFYING = "terrifying",   -- Fear-inducing encounters
    TRAUMA     = "trauma",       -- Witnessing death/suffering
    EXHAUSTION = "exhaustion",   -- Physical/mental fatigue
    DARKNESS   = "darkness",     -- Prolonged time without light
}

--------------------------------------------------------------------------------
-- TRAVEL EVENT OUTCOMES THAT CAUSE STRESS
-- These are triggered by Travel Events (Major Arcana XI-XV)
--------------------------------------------------------------------------------
M.STRESSFUL_OUTCOMES = {
    -- Gross outcomes
    "rotting_corpse",
    "disease_cloud",
    "vermin_swarm",
    "sewage_pool",
    "gore_scene",

    -- Terrifying outcomes
    "ghostly_apparition",
    "ominous_whispers",
    "stalker_presence",
    "trapped_alive",
    "void_glimpse",
}

--------------------------------------------------------------------------------
-- ENVIRONMENT MANAGER FACTORY
--------------------------------------------------------------------------------

--- Create a new EnvironmentManager
-- @param config table: { eventBus, guild }
-- @return EnvironmentManager instance
function M.createEnvironmentManager(config)
    config = config or {}

    local manager = {
        eventBus = config.eventBus or events.globalBus,
        guild    = config.guild or {},    -- Array of adventurer entities

        -- Track stress history for debugging/narrative
        stressLog = {},
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    --- Initialize and subscribe to events
    function manager:init()
        -- Subscribe to Travel Events (XI-XV)
        self.eventBus:on(events.EVENTS.TRAVEL_EVENT, function(data)
            self:handleTravelEvent(data)
        end)

        -- Subscribe to trap triggered events (traps can stress)
        self.eventBus:on(events.EVENTS.TRAP_TRIGGERED, function(data)
            if data.outcome and data.outcome.stressful then
                self:applyStressToParty(data.outcome.stressReason or M.STRESS_REASONS.TRAUMA)
            end
        end)

        -- Subscribe to darkness (prolonged darkness causes stress)
        self.eventBus:on("darkness_fell", function(data)
            -- Note: Darkness stress happens over time, not immediately
            -- This is tracked separately via watch count in darkness
        end)
    end

    ----------------------------------------------------------------------------
    -- STRESS APPLICATION
    ----------------------------------------------------------------------------

    --- Apply stress to a single entity
    -- @param entity table: The entity to stress
    -- @param reason string: One of STRESS_REASONS
    -- @return boolean: true if stress was newly applied
    function manager:applyStress(entity, reason)
        if not entity or not entity.conditions then
            return false
        end

        -- Check if already stressed
        if entity.conditions.stressed then
            -- Log the additional stress source but don't double-stress
            self:logStress(entity, reason, false)
            return false
        end

        -- Apply stress condition
        entity.conditions.stressed = true

        -- Log for narrative/debugging
        self:logStress(entity, reason, true)

        -- Emit event for UI
        self.eventBus:emit("entity_stressed", {
            entity = entity,
            reason = reason,
        })

        return true
    end

    --- Apply stress to the entire party
    -- @param reason string: One of STRESS_REASONS
    -- @return number: Count of entities newly stressed
    function manager:applyStressToParty(reason)
        local count = 0

        for _, entity in ipairs(self.guild) do
            if self:applyStress(entity, reason) then
                count = count + 1
            end
        end

        if count > 0 then
            self.eventBus:emit("party_stressed", {
                reason = reason,
                count  = count,
            })
        end

        return count
    end

    ----------------------------------------------------------------------------
    -- STRESS RECOVERY
    ----------------------------------------------------------------------------

    --- Clear stress from an entity (requires explicit action like rest/camp)
    -- @param entity table: The entity to recover
    -- @return boolean: true if stress was cleared
    function manager:clearStress(entity)
        if not entity or not entity.conditions then
            return false
        end

        if not entity.conditions.stressed then
            return false
        end

        entity.conditions.stressed = false

        self.eventBus:emit("stress_cleared", {
            entity = entity,
        })

        return true
    end

    ----------------------------------------------------------------------------
    -- STRESS GATE CHECK
    -- The "Recovery Gate" rule: stressed entities cannot heal other conditions
    ----------------------------------------------------------------------------

    --- Check if an entity can recover from conditions
    -- @param entity table: The entity to check
    -- @return boolean, string: canRecover, reason
    function manager:canRecover(entity)
        if not entity or not entity.conditions then
            return true, nil
        end

        if entity.conditions.stressed then
            return false, "must_clear_stress_first"
        end

        return true, nil
    end

    --- Attempt to heal a wound with stress check
    -- This wraps the base entity healWound logic
    -- @param entity table: The entity to heal
    -- @return string, string: healResult or nil, errorReason
    function manager:healWoundWithStressCheck(entity)
        local canHeal, reason = self:canRecover(entity)

        if not canHeal then
            self.eventBus:emit("heal_blocked", {
                entity = entity,
                reason = reason,
            })
            return nil, reason
        end

        -- Delegate to entity's heal method
        if entity.healWound then
            local result = entity:healWound()
            return result, nil
        end

        return nil, "no_heal_method"
    end

    ----------------------------------------------------------------------------
    -- TRAVEL EVENT HANDLING
    ----------------------------------------------------------------------------

    --- Handle Travel Events from Meatgrinder (Major Arcana XI-XV)
    -- @param data table: { card, category, value }
    function manager:handleTravelEvent(data)
        -- Travel events don't always cause stress
        -- The specific outcome determines if it's stressful
        -- For now, we'll use a simple probability based on card value

        -- Higher values (XIV, XV) are more likely to be terrifying
        local stressChance = (data.value - 10) * 0.15  -- 15% at XI, 75% at XV

        -- In a full implementation, this would check a travel event table
        -- For now, emit event for narrative system to determine outcome
        self.eventBus:emit("travel_event_check", {
            card          = data.card,
            value         = data.value,
            stressChance  = stressChance,
            checkStress   = function(outcomeType)
                return self:checkOutcomeStressful(outcomeType)
            end,
            applyPartyStress = function(reason)
                return self:applyStressToParty(reason)
            end,
        })
    end

    --- Check if an outcome type is stressful
    -- @param outcomeType string: The outcome identifier
    -- @return boolean
    function manager:checkOutcomeStressful(outcomeType)
        for _, stressful in ipairs(M.STRESSFUL_OUTCOMES) do
            if stressful == outcomeType then
                return true
            end
        end
        return false
    end

    ----------------------------------------------------------------------------
    -- STRESS LOGGING
    ----------------------------------------------------------------------------

    --- Log a stress event
    function manager:logStress(entity, reason, applied)
        self.stressLog[#self.stressLog + 1] = {
            entityId  = entity.id,
            entityName = entity.name,
            reason    = reason,
            applied   = applied,
            timestamp = os.time(),
        }

        -- Keep log bounded
        if #self.stressLog > 100 then
            table.remove(self.stressLog, 1)
        end
    end

    --- Get stress history for an entity
    function manager:getStressHistory(entityId)
        local history = {}
        for _, entry in ipairs(self.stressLog) do
            if entry.entityId == entityId then
                history[#history + 1] = entry
            end
        end
        return history
    end

    ----------------------------------------------------------------------------
    -- QUERIES
    ----------------------------------------------------------------------------

    --- Check if entity is stressed
    function manager:isStressed(entity)
        return entity and entity.conditions and entity.conditions.stressed
    end

    --- Count stressed guild members
    function manager:getStressedCount()
        local count = 0
        for _, entity in ipairs(self.guild) do
            if self:isStressed(entity) then
                count = count + 1
            end
        end
        return count
    end

    --- Check if anyone in guild is stressed
    function manager:anyStressed()
        return self:getStressedCount() > 0
    end

    --- Set the guild (for updates during gameplay)
    function manager:setGuild(guildMembers)
        self.guild = guildMembers
    end

    return manager
end

return M

```

---

## File: src/logic/events.lua

```lua
-- events.lua
-- Simple Event System for Majesty
-- Provides loose coupling between systems (e.g., WatchManager fires events,
-- Light/Inventory systems listen)

local M = {}

--------------------------------------------------------------------------------
-- EVENT TYPES
--------------------------------------------------------------------------------
M.EVENTS = {
    -- Watch & Time
    WATCH_PASSED      = "watch_passed",
    TORCHES_GUTTER    = "torches_gutter",

    -- Meatgrinder Results
    MEATGRINDER_ROLL  = "meatgrinder_roll",
    CURIOSITY         = "curiosity",
    TRAVEL_EVENT      = "travel_event",
    RANDOM_ENCOUNTER  = "random_encounter",
    QUEST_RUMOR       = "quest_rumor",

    -- Movement
    PARTY_MOVED       = "party_moved",
    ROOM_ENTERED      = "room_entered",

    -- Combat/Challenge
    CHALLENGE_START       = "challenge_start",
    CHALLENGE_END         = "challenge_end",
    CHALLENGE_TURN_START  = "challenge_turn_start",
    CHALLENGE_TURN_END    = "challenge_turn_end",
    CHALLENGE_ACTION      = "challenge_action",
    CHALLENGE_RESOLUTION  = "challenge_resolution",
    MINOR_ACTION_WINDOW   = "minor_action_window",
    MINOR_ACTION_USED     = "minor_action_used",
    UI_SEQUENCE_COMPLETE  = "ui_sequence_complete",

    -- Wound/Damage
    WOUND_TAKEN           = "wound_taken",
    WOUND_HEALED          = "wound_healed",
    ENTITY_DEFEATED       = "entity_defeated",
    ARMOR_NOTCHED         = "armor_notched",
    TALENT_WOUNDED        = "talent_wounded",

    -- Phase Changes
    PHASE_CHANGED     = "phase_changed",

    -- Zones (T2_3)
    ZONE_CHANGED        = "zone_changed",
    ENTITIES_ENGAGED    = "entities_engaged",
    ENTITIES_DISENGAGED = "entities_disengaged",
    PARTING_BLOW        = "parting_blow",

    -- Room Features (T2_5)
    FEATURE_STATE_CHANGED = "feature_state_changed",
    FEATURE_UPDATED       = "feature_updated",  -- S11.3: arbitrary feature updates

    -- Interaction (T2_6)
    INTERACTION = "interaction",

    -- POI Info-Gating (T2_8)
    POI_DISCOVERED      = "poi_discovered",
    SCRUTINY_TIME_COST  = "scrutiny_time_cost",

    -- Investigation Bridge (T2_9)
    INVESTIGATION_COMPLETE = "investigation_complete",
    TRAP_TRIGGERED         = "trap_triggered",

    -- Item Interaction (T2_10)
    TRAP_DETECTED         = "trap_detected",
    ITEM_DAMAGE_ABSORBED  = "item_damage_absorbed",

    -- UI Input (T2_11)
    DRAG_BEGIN       = "drag_begin",
    DRAG_CANCELLED   = "drag_cancelled",
    DROP_ON_TARGET   = "drop_on_target",
    POI_CLICKED      = "poi_clicked",
    BUTTON_CLICKED   = "button_clicked",

    -- Focus Menu (T2_13)
    SCRUTINY_SELECTED = "scrutiny_selected",
    MENU_OPENED       = "menu_opened",
    MENU_CLOSED       = "menu_closed",
}

--------------------------------------------------------------------------------
-- EVENT BUS FACTORY
--------------------------------------------------------------------------------

--- Create a new EventBus
-- @return EventBus instance
function M.createEventBus()
    local bus = {
        listeners = {},  -- event_type -> { callback1, callback2, ... }
        history   = {},  -- Recent events for debugging
    }

    ----------------------------------------------------------------------------
    -- SUBSCRIBE
    ----------------------------------------------------------------------------

    --- Subscribe to an event
    -- @param eventType string: One of EVENTS constants
    -- @param callback function: Called with (eventData) when event fires
    -- @return function: Unsubscribe function
    function bus:on(eventType, callback)
        if not self.listeners[eventType] then
            self.listeners[eventType] = {}
        end

        local listeners = self.listeners[eventType]
        listeners[#listeners + 1] = callback

        -- Return unsubscribe function
        return function()
            for i, cb in ipairs(listeners) do
                if cb == callback then
                    table.remove(listeners, i)
                    break
                end
            end
        end
    end

    --- Subscribe to an event (fires only once)
    function bus:once(eventType, callback)
        local unsubscribe
        unsubscribe = self:on(eventType, function(data)
            unsubscribe()
            callback(data)
        end)
        return unsubscribe
    end

    ----------------------------------------------------------------------------
    -- EMIT
    ----------------------------------------------------------------------------

    --- Emit an event to all listeners
    -- @param eventType string: One of EVENTS constants
    -- @param data table: Event-specific data
    function bus:emit(eventType, data)
        data = data or {}
        data.eventType = eventType
        data.timestamp = os.time()

        -- Record in history (keep last 50)
        self.history[#self.history + 1] = data
        if #self.history > 50 then
            table.remove(self.history, 1)
        end

        -- Notify listeners
        local listeners = self.listeners[eventType]
        if listeners then
            for _, callback in ipairs(listeners) do
                callback(data)
            end
        end
    end

    ----------------------------------------------------------------------------
    -- UTILITY
    ----------------------------------------------------------------------------

    --- Get listener count for an event
    function bus:listenerCount(eventType)
        local listeners = self.listeners[eventType]
        return listeners and #listeners or 0
    end

    --- Clear all listeners for an event (useful for testing)
    function bus:clear(eventType)
        if eventType then
            self.listeners[eventType] = {}
        else
            self.listeners = {}
        end
    end

    --- Get recent event history
    function bus:getHistory()
        return self.history
    end

    return bus
end

--------------------------------------------------------------------------------
-- GLOBAL EVENT BUS (singleton for convenience)
--------------------------------------------------------------------------------
M.globalBus = M.createEventBus()

return M

```

---

## File: src/logic/interaction.lua

```lua
-- interaction.lua
-- Interaction Verb System for Majesty
-- Ticket T2_6: Glance, Scrutinize, Investigate info-gates
--
-- Design: Three levels of information revelation
-- - Glance: Free, automatic (what you see at first look)
-- - Scrutinize: Hidden info (requires "say more about what you're doing")
-- - Investigate: May require Test of Fate if risky
--
-- Anti-pattern warning: Players should think, not spam clicks.
-- Investigating a trap improperly has a high chance of triggering it.

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- INTERACTION LEVELS (Info-Gates)
--------------------------------------------------------------------------------
M.LEVELS = {
    GLANCE      = "glance",       -- Free, immediate
    SCRUTINIZE  = "scrutinize",   -- Requires description of method
    INVESTIGATE = "investigate",  -- May require Test of Fate
}

--------------------------------------------------------------------------------
-- INTERACTION TYPES
-- Common verbs for interacting with objects
--------------------------------------------------------------------------------
M.ACTIONS = {
    EXAMINE   = "examine",    -- Look at/describe
    SEARCH    = "search",     -- Look for hidden things
    TAKE      = "take",       -- Pick up
    USE       = "use",        -- Activate/operate
    OPEN      = "open",       -- Open container/door
    CLOSE     = "close",      -- Close container/door
    UNLOCK    = "unlock",     -- Unlock with key
    FORCE     = "force",      -- Break open
    LIGHT     = "light",      -- Set on fire/illuminate
    CLIMB     = "climb",      -- Climb on/over
    PUSH      = "push",       -- Push/shove
    PULL      = "pull",       -- Pull/yank
    TALK      = "talk",       -- Speak to
    ATTACK    = "attack",     -- Harm
    TRAP_CHECK = "trap_check", -- Check for traps (risky!)
}

--------------------------------------------------------------------------------
-- INTERACTION RESULT
--------------------------------------------------------------------------------

local function createResult(config)
    return {
        success       = config.success ~= false,
        level         = config.level,
        action        = config.action,
        target        = config.target,
        description   = config.description or "",
        hidden_info   = config.hidden_info,    -- Revealed at SCRUTINIZE+
        requires_test = config.requires_test,  -- For INVESTIGATE
        test_config   = config.test_config,    -- { attribute, difficulty, consequences }
        triggered     = config.triggered,      -- Did we trigger something bad?
        items_found   = config.items_found,    -- Array of item IDs
        state_change  = config.state_change,   -- { feature_id, new_state }
    }
end

--------------------------------------------------------------------------------
-- INTERACTION HANDLER REGISTRY
-- Maps action types to handler functions
--------------------------------------------------------------------------------

local defaultHandlers = {}

--- Default EXAMINE handler (works for most things)
defaultHandlers[M.ACTIONS.EXAMINE] = function(target, level, context)
    local result = {
        level  = level,
        action = M.ACTIONS.EXAMINE,
        target = target,
    }

    -- Glance: Just the basic description
    if level == M.LEVELS.GLANCE then
        result.description = target.name or "Something."
        return createResult(result)
    end

    -- Scrutinize: Full description
    if level == M.LEVELS.SCRUTINIZE then
        result.description = target.description or target.name or "You look more closely."

        -- Reveal any hidden info at this level
        if target.hidden_description then
            result.hidden_info = target.hidden_description
        end

        return createResult(result)
    end

    -- Investigate: Detailed examination, may find more
    if level == M.LEVELS.INVESTIGATE then
        result.description = target.description or "You examine it thoroughly."

        -- At investigate level, we might find hidden things
        if target.secrets then
            result.hidden_info = target.secrets
        end

        return createResult(result)
    end

    return createResult(result)
end

--- Default SEARCH handler
defaultHandlers[M.ACTIONS.SEARCH] = function(target, level, context)
    local result = {
        level  = level,
        action = M.ACTIONS.SEARCH,
        target = target,
    }

    if level == M.LEVELS.GLANCE then
        result.description = "You would need to look more carefully to search this."
        result.success = false
        return createResult(result)
    end

    if level == M.LEVELS.SCRUTINIZE then
        result.description = "Describe how you're searching to investigate properly."
        if target.loot and #target.loot > 0 then
            result.hidden_info = "There might be something here..."
        end
        return createResult(result)
    end

    -- Investigate: Actually search
    if level == M.LEVELS.INVESTIGATE then
        if target.state == "searched" or target.state == "empty" then
            result.description = "You've already searched this."
            return createResult(result)
        end

        -- Check for traps first!
        if target.trap and not target.trap.detected and not target.trap.disarmed then
            -- Searching without checking for traps first is dangerous
            result.requires_test = true
            result.test_config = {
                attribute     = "pentacles",
                difficulty    = target.trap.difficulty or 14,
                success_desc  = "You find the trap before it springs.",
                failure_desc  = "You trigger the trap!",
                failure_effect = { type = "trap_triggered", trap = target.trap },
            }
        end

        -- Found items
        if target.loot and #target.loot > 0 then
            result.items_found = target.loot
            result.description = "You find something!"
        else
            result.description = "You search thoroughly but find nothing of interest."
        end

        result.state_change = { new_state = "searched" }
        return createResult(result)
    end

    return createResult(result)
end

--- Default TRAP_CHECK handler
-- Checking for traps is itself risky!
defaultHandlers[M.ACTIONS.TRAP_CHECK] = function(target, level, context)
    local result = {
        level  = level,
        action = M.ACTIONS.TRAP_CHECK,
        target = target,
    }

    if level ~= M.LEVELS.INVESTIGATE then
        result.description = "You need to investigate properly to check for traps."
        result.success = false
        return createResult(result)
    end

    -- No trap present
    if not target.trap then
        result.description = "You find no traps."
        return createResult(result)
    end

    -- Already detected or disarmed
    if target.trap.detected then
        result.description = "You've already detected a trap here: " .. (target.trap.description or "some kind of trap.")
        return createResult(result)
    end

    if target.trap.disarmed then
        result.description = "The trap here has been disarmed."
        return createResult(result)
    end

    -- Requires a test to detect safely
    -- "Investigating a trap improperly has a high chance of triggering it"
    result.requires_test = true
    result.test_config = {
        attribute     = "pentacles",
        difficulty    = target.trap.difficulty or 14,
        success_desc  = "You detect and avoid the trap: " .. (target.trap.description or "a hidden mechanism."),
        failure_desc  = "You trigger the trap while searching for it!",
        failure_effect = { type = "trap_triggered", trap = target.trap },
        success_effect = { type = "trap_detected" },
    }

    return createResult(result)
end

--- Default OPEN handler
defaultHandlers[M.ACTIONS.OPEN] = function(target, level, context)
    local result = {
        level  = level,
        action = M.ACTIONS.OPEN,
        target = target,
    }

    if target.state == "open" then
        result.description = "It's already open."
        result.success = false
        return createResult(result)
    end

    if target.state == "locked" then
        result.description = "It's locked."
        result.success = false
        return createResult(result)
    end

    -- Can open
    result.description = "You open it."
    result.state_change = { new_state = "open" }
    return createResult(result)
end

--- Default UNLOCK handler
defaultHandlers[M.ACTIONS.UNLOCK] = function(target, level, context)
    local result = {
        level  = level,
        action = M.ACTIONS.UNLOCK,
        target = target,
    }

    if target.state ~= "locked" then
        result.description = "It's not locked."
        result.success = false
        return createResult(result)
    end

    -- Check if player has the key
    if target.lock and target.lock.key_id then
        if context.hasItem and context.hasItem(target.lock.key_id) then
            result.description = "You unlock it with the " .. target.lock.key_id .. "."
            result.state_change = { new_state = "unlocked" }
        else
            result.description = "You need a key to unlock this."
            result.success = false
        end
    else
        -- No specific key required
        result.description = "You unlock it."
        result.state_change = { new_state = "unlocked" }
    end

    return createResult(result)
end

--------------------------------------------------------------------------------
-- INTERACTION SYSTEM FACTORY
--------------------------------------------------------------------------------

--- Create a new InteractionSystem
-- @param config table: { eventBus, roomManager, resolver }
-- @return InteractionSystem instance
function M.createInteractionSystem(config)
    config = config or {}

    local system = {
        eventBus    = config.eventBus or events.globalBus,
        roomManager = config.roomManager,
        resolver    = config.resolver,
        -- Custom handlers can override defaults
        customHandlers = {},
    }

    ----------------------------------------------------------------------------
    -- HANDLER REGISTRATION
    ----------------------------------------------------------------------------

    --- Register a custom action handler
    function system:registerHandler(action, handler)
        self.customHandlers[action] = handler
    end

    --- Get handler for an action
    local function getHandler(self, action)
        return self.customHandlers[action] or defaultHandlers[action]
    end

    ----------------------------------------------------------------------------
    -- CONTEXT MENU
    -- Determines valid actions for a target
    ----------------------------------------------------------------------------

    --- Get valid actions for a target
    -- @param target table: Feature or entity to interact with
    -- @return table: Array of { action, level_required, description }
    function system:getValidActions(target)
        local actions = {}

        -- Check target's declared interactions
        if target.interactions then
            for _, action in ipairs(target.interactions) do
                local handler = getHandler(self, action)
                if handler then
                    actions[#actions + 1] = {
                        action         = action,
                        level_required = self:getRequiredLevel(action, target),
                        description    = self:getActionDescription(action),
                    }
                end
            end
        else
            -- Default interactions based on type
            actions[#actions + 1] = { action = M.ACTIONS.EXAMINE, level_required = M.LEVELS.GLANCE }

            if target.type == "container" then
                actions[#actions + 1] = { action = M.ACTIONS.SEARCH, level_required = M.LEVELS.INVESTIGATE }
                actions[#actions + 1] = { action = M.ACTIONS.OPEN, level_required = M.LEVELS.GLANCE }
            end

            if target.type == "corpse" then
                actions[#actions + 1] = { action = M.ACTIONS.SEARCH, level_required = M.LEVELS.INVESTIGATE }
            end

            if target.trap then
                actions[#actions + 1] = { action = M.ACTIONS.TRAP_CHECK, level_required = M.LEVELS.INVESTIGATE }
            end
        end

        return actions
    end

    --- Get required level for an action
    function system:getRequiredLevel(action, target)
        -- Actions that are always safe
        if action == M.ACTIONS.EXAMINE then
            return M.LEVELS.GLANCE
        end

        -- Actions that need description
        if action == M.ACTIONS.SEARCH then
            return M.LEVELS.SCRUTINIZE
        end

        -- Risky actions need investigation level
        if action == M.ACTIONS.TRAP_CHECK or
           action == M.ACTIONS.FORCE or
           action == M.ACTIONS.CLIMB then
            return M.LEVELS.INVESTIGATE
        end

        return M.LEVELS.GLANCE
    end

    --- Get human-readable description of action
    function system:getActionDescription(action)
        local descriptions = {
            [M.ACTIONS.EXAMINE]    = "Look at",
            [M.ACTIONS.SEARCH]     = "Search",
            [M.ACTIONS.TAKE]       = "Take",
            [M.ACTIONS.USE]        = "Use",
            [M.ACTIONS.OPEN]       = "Open",
            [M.ACTIONS.CLOSE]      = "Close",
            [M.ACTIONS.UNLOCK]     = "Unlock",
            [M.ACTIONS.FORCE]      = "Force open",
            [M.ACTIONS.LIGHT]      = "Light",
            [M.ACTIONS.CLIMB]      = "Climb",
            [M.ACTIONS.PUSH]       = "Push",
            [M.ACTIONS.PULL]       = "Pull",
            [M.ACTIONS.TALK]       = "Talk to",
            [M.ACTIONS.ATTACK]     = "Attack",
            [M.ACTIONS.TRAP_CHECK] = "Check for traps",
        }
        return descriptions[action] or action
    end

    ----------------------------------------------------------------------------
    -- INTERACTION EXECUTION
    ----------------------------------------------------------------------------

    --- Execute an interaction
    -- @param entity table: The entity performing the action
    -- @param target table: The target (feature, entity, etc.)
    -- @param action string: One of ACTIONS
    -- @param level string: One of LEVELS
    -- @param context table: Additional context { hasItem, method_description, ... }
    -- @return table: Interaction result
    function system:interact(entity, target, action, level, context)
        context = context or {}

        -- Check if action is valid for target
        local validActions = self:getValidActions(target)
        local isValid = false
        local requiredLevel = M.LEVELS.GLANCE

        for _, va in ipairs(validActions) do
            if va.action == action then
                isValid = true
                requiredLevel = va.level_required
                break
            end
        end

        if not isValid then
            return createResult({
                success     = false,
                level       = level,
                action      = action,
                target      = target,
                description = "You can't do that with this.",
            })
        end

        -- Check level requirement
        local levelOrder = { [M.LEVELS.GLANCE] = 1, [M.LEVELS.SCRUTINIZE] = 2, [M.LEVELS.INVESTIGATE] = 3 }
        if levelOrder[level] < levelOrder[requiredLevel] then
            return createResult({
                success     = false,
                level       = level,
                action      = action,
                target      = target,
                description = "You need to look more carefully to do that.",
            })
        end

        -- Get and execute handler
        local handler = getHandler(self, action)
        if not handler then
            return createResult({
                success     = false,
                level       = level,
                action      = action,
                target      = target,
                description = "You're not sure how to do that.",
            })
        end

        local result = handler(target, level, context)

        -- Handle state changes
        if result.success and result.state_change and self.roomManager then
            local roomId = context.roomId
            if roomId and target.id then
                self.roomManager:setFeatureState(roomId, target.id, result.state_change.new_state)
            end
        end

        -- Emit event
        self.eventBus:emit(events.EVENTS.INTERACTION, {
            entity = entity,
            target = target,
            action = action,
            level  = level,
            result = result,
        })

        return result
    end

    --- Convenience method for glance
    function system:glance(entity, target, context)
        return self:interact(entity, target, M.ACTIONS.EXAMINE, M.LEVELS.GLANCE, context)
    end

    --- Convenience method for scrutinize
    function system:scrutinize(entity, target, action, context)
        return self:interact(entity, target, action or M.ACTIONS.EXAMINE, M.LEVELS.SCRUTINIZE, context)
    end

    --- Convenience method for investigate
    function system:investigate(entity, target, action, context)
        return self:interact(entity, target, action or M.ACTIONS.SEARCH, M.LEVELS.INVESTIGATE, context)
    end

    return system
end

return M

```

---

## File: src/logic/inventory.lua

```lua
-- inventory.lua
-- Slot-Based Inventory Manager for Majesty
-- Ticket T1_7: Belt vs Pack system with notch tracking
--
-- Locations: HANDS (active), BELT (quick access), PACK (stored)
-- Items have unique instance IDs - two torches are separate objects

local M = {}

--------------------------------------------------------------------------------
-- SLOT CONSTANTS
--------------------------------------------------------------------------------
M.SLOTS = {
    HANDS = 2,
    BELT  = 4,
    PACK  = 21,
}

M.LOCATIONS = {
    HANDS = "hands",
    BELT  = "belt",
    PACK  = "pack",
}

--------------------------------------------------------------------------------
-- ITEM SIZE CONSTANTS
--------------------------------------------------------------------------------
M.SIZE = {
    NORMAL    = 1,  -- Most items, one-handed
    LARGE     = 2,  -- Two-handed items
    OVERSIZED = 2,  -- 2 slots AND belt-only
}

--------------------------------------------------------------------------------
-- DURABILITY CONSTANTS
--------------------------------------------------------------------------------
M.DURABILITY = {
    FRAGILE        = 1,  -- Breaks after 1 notch
    NORMAL         = 2,  -- Breaks after 2 notches
    TEMPERED_STEEL = 3,  -- Breaks after 3 notches
}

--------------------------------------------------------------------------------
-- ITEM FACTORY
-- Every item gets a unique instance ID
--------------------------------------------------------------------------------
local nextItemId = 0

--- Create a new Item instance
-- @param config table: { name, size, durability, stackable, stackSize, oversized, ... }
-- @return Item instance with unique ID
function M.createItem(config)
    config = config or {}

    nextItemId = nextItemId + 1

    local item = {
        -- Identity
        id   = config.id or ("item_" .. nextItemId),
        name = config.name or "Unknown Item",

        -- Size (slots consumed)
        size      = config.size or M.SIZE.NORMAL,
        oversized = config.oversized or false,  -- If true, belt-only

        -- Durability
        durability = config.durability or M.DURABILITY.NORMAL,
        notches    = 0,
        destroyed  = false,

        -- Stacking (for arrows, coins, etc.)
        stackable = config.stackable or false,
        stackSize = config.stackSize or 1,  -- Max per slot
        quantity  = config.quantity or 1,

        -- Armor flag (worn armor uses belt slots)
        isArmor = config.isArmor or false,

        -- Custom properties
        properties = config.properties or {},
    }

    return item
end

--- S11.3: Create an item from a template ID
-- @param templateId string: The template ID from item_templates.lua
-- @param overrides table: Optional property overrides
-- @return Item instance or nil if template not found
function M.createItemFromTemplate(templateId, overrides)
    -- Lazy-load templates to avoid circular dependency
    local item_templates = require('data.item_templates')

    local template = item_templates.getTemplate(templateId)
    if not template then
        print("[INVENTORY] Unknown template: " .. tostring(templateId))
        return nil
    end

    -- Merge template with overrides
    local config = {}
    for k, v in pairs(template) do
        config[k] = v
    end
    if overrides then
        for k, v in pairs(overrides) do
            config[k] = v
        end
    end

    -- Store the template ID for reference
    config.templateId = templateId

    return M.createItem(config)
end

--- Add a notch to an item
-- @return string: "notched", "destroyed", or "already_destroyed"
function M.addNotch(item)
    if item.destroyed then
        return "already_destroyed"
    end

    item.notches = item.notches + 1

    if item.notches >= item.durability then
        item.destroyed = true
        return "destroyed"
    end

    return "notched"
end

--- Repair an item (remove one notch)
function M.repairNotch(item)
    if item.notches > 0 then
        item.notches = item.notches - 1
        if item.destroyed and item.notches < item.durability then
            item.destroyed = false
        end
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- INVENTORY CONTAINER
-- Manages hands, belt, and pack for an entity
--------------------------------------------------------------------------------

--- Create a new Inventory for an entity
-- @param config table: { beltSlots, packSlots } - optional overrides
-- @return Inventory instance
function M.createInventory(config)
    config = config or {}

    local inventory = {
        -- Slot limits (can be customized for special cases)
        limits = {
            hands = M.SLOTS.HANDS,
            belt  = config.beltSlots or M.SLOTS.BELT,
            pack  = config.packSlots or M.SLOTS.PACK,
        },

        -- Item storage by location
        hands = {},  -- Active/held items
        belt  = {},  -- Quick-access items (and worn armor)
        pack  = {},  -- Stored items
    }

    ----------------------------------------------------------------------------
    -- SLOT COUNTING
    ----------------------------------------------------------------------------

    --- Count slots used in a location
    local function countUsedSlots(location)
        local items = inventory[location]
        local used = 0
        for _, item in ipairs(items) do
            if item.stackable then
                used = used + 1  -- Stacked items use 1 slot regardless of quantity
            else
                used = used + item.size
            end
        end
        return used
    end

    --- Get available slots in a location
    function inventory:availableSlots(location)
        return self.limits[location] - countUsedSlots(location)
    end

    --- Get used slots in a location
    function inventory:usedSlots(location)
        return countUsedSlots(location)
    end

    ----------------------------------------------------------------------------
    -- ADD ITEM
    ----------------------------------------------------------------------------

    --- Add an item to a location
    -- @param item table: Item instance
    -- @param location string: "hands", "belt", or "pack"
    -- @return boolean, string: success, error_reason
    function inventory:addItem(item, location)
        location = location or M.LOCATIONS.PACK

        -- Validate location
        if not self[location] then
            return false, "invalid_location"
        end

        -- Oversized items can ONLY go on belt
        if item.oversized and location ~= M.LOCATIONS.BELT then
            return false, "oversized_belt_only"
        end

        -- Worn armor can ONLY go on belt (p. 37: "carried in your belt slots")
        -- Armor in pack would be "loot" and should not have isArmor=true
        if item.isArmor and location ~= M.LOCATIONS.BELT then
            return false, "armor_belt_only"
        end

        -- Check slot availability
        local slotsNeeded = item.stackable and 1 or item.size
        if self:availableSlots(location) < slotsNeeded then
            return false, "insufficient_slots"
        end

        -- Handle stacking
        if item.stackable then
            -- Look for existing stack of same item type
            for _, existing in ipairs(self[location]) do
                if existing.name == item.name and existing.quantity < existing.stackSize then
                    local canAdd = existing.stackSize - existing.quantity
                    local toAdd = math.min(canAdd, item.quantity)
                    existing.quantity = existing.quantity + toAdd
                    item.quantity = item.quantity - toAdd
                    if item.quantity <= 0 then
                        return true, "stacked"
                    end
                end
            end
        end

        -- Add as new item
        self[location][#self[location] + 1] = item
        return true, "added"
    end

    ----------------------------------------------------------------------------
    -- REMOVE ITEM
    ----------------------------------------------------------------------------

    --- Remove an item by ID from any location
    -- @param itemId string: The item's unique ID
    -- @return item, location: The removed item and where it was, or nil
    function inventory:removeItem(itemId)
        for _, location in ipairs({ "hands", "belt", "pack" }) do
            for i, item in ipairs(self[location]) do
                if item.id == itemId then
                    table.remove(self[location], i)
                    return item, location
                end
            end
        end
        return nil, nil
    end

    ----------------------------------------------------------------------------
    -- FIND ITEM
    ----------------------------------------------------------------------------

    --- Find an item by ID
    -- @return item, location or nil, nil
    function inventory:findItem(itemId)
        for _, location in ipairs({ "hands", "belt", "pack" }) do
            for _, item in ipairs(self[location]) do
                if item.id == itemId then
                    return item, location
                end
            end
        end
        return nil, nil
    end

    --- Find items by name
    -- @return table of { item, location } pairs
    function inventory:findItemsByName(name)
        local results = {}
        for _, location in ipairs({ "hands", "belt", "pack" }) do
            for _, item in ipairs(self[location]) do
                if item.name == name then
                    results[#results + 1] = { item = item, location = location }
                end
            end
        end
        return results
    end

    --- Find first item matching a predicate function (S9.2)
    -- @param predicate function(item): returns true if item matches
    -- @return item, location or nil, nil
    function inventory:findItemByPredicate(predicate)
        for _, location in ipairs({ "hands", "belt", "pack" }) do
            for _, item in ipairs(self[location]) do
                if predicate(item) then
                    return item, location
                end
            end
        end
        return nil, nil
    end

    --- Check if inventory has an item of a specific type (S9.2)
    -- @param itemType string: Type to check for (e.g., "ration", "tinkers_kit")
    -- @return boolean
    function inventory:hasItemOfType(itemType)
        local item = self:findItemByPredicate(function(i)
            return i.type == itemType or
                   i.itemType == itemType or
                   (i.properties and i.properties.type == itemType)
        end)
        return item ~= nil
    end

    --- Count items matching a predicate (S9.2)
    -- @param predicate function(item): returns true if item matches
    -- @return number: Total count (respects stackable quantity)
    function inventory:countItemsByPredicate(predicate)
        local count = 0
        for _, location in ipairs({ "hands", "belt", "pack" }) do
            for _, item in ipairs(self[location]) do
                if predicate(item) then
                    count = count + (item.quantity or 1)
                end
            end
        end
        return count
    end

    --- Remove one unit of an item (handles stackables) (S9.2)
    -- @param itemId string: The item's unique ID
    -- @param amount number: Amount to remove (default 1)
    -- @return boolean, string: success, result
    function inventory:removeItemQuantity(itemId, amount)
        amount = amount or 1

        for _, location in ipairs({ "hands", "belt", "pack" }) do
            for i, item in ipairs(self[location]) do
                if item.id == itemId then
                    if item.stackable and item.quantity then
                        if item.quantity > amount then
                            item.quantity = item.quantity - amount
                            return true, "decremented"
                        else
                            -- Remove entire stack
                            table.remove(self[location], i)
                            return true, "removed"
                        end
                    else
                        -- Non-stackable, remove entirely
                        table.remove(self[location], i)
                        return true, "removed"
                    end
                end
            end
        end
        return false, "not_found"
    end

    ----------------------------------------------------------------------------
    -- SWAP / MOVE
    ----------------------------------------------------------------------------

    --- Move an item between locations
    -- @param itemId string: The item's unique ID
    -- @param toLoc string: Destination location
    -- @return boolean, string: success, reason
    function inventory:swap(itemId, toLoc)
        local item, fromLoc = self:findItem(itemId)

        if not item then
            return false, "item_not_found"
        end

        if fromLoc == toLoc then
            return true, "already_there"
        end

        -- Validate destination
        if not self[toLoc] then
            return false, "invalid_destination"
        end

        -- Oversized check
        if item.oversized and toLoc ~= M.LOCATIONS.BELT then
            return false, "oversized_belt_only"
        end

        -- Armor check (worn armor must stay on belt)
        if item.isArmor and toLoc ~= M.LOCATIONS.BELT then
            return false, "armor_belt_only"
        end

        -- Check destination has room
        local slotsNeeded = item.stackable and 1 or item.size
        if self:availableSlots(toLoc) < slotsNeeded then
            return false, "destination_full"
        end

        -- Perform the move
        self:removeItem(itemId)
        self[toLoc][#self[toLoc] + 1] = item

        return true, "moved"
    end

    ----------------------------------------------------------------------------
    -- HANDS UTILITIES
    ----------------------------------------------------------------------------

    --- Check if hands are free
    function inventory:handsFree()
        return self:availableSlots("hands")
    end

    --- Check if holding a specific item type
    function inventory:isHolding(itemName)
        for _, item in ipairs(self.hands) do
            if item.name == itemName then
                return true, item
            end
        end
        return false, nil
    end

    ----------------------------------------------------------------------------
    -- LIST ITEMS
    ----------------------------------------------------------------------------

    --- Get all items in a location
    function inventory:getItems(location)
        return self[location] or {}
    end

    --- Get all items across all locations
    function inventory:getAllItems()
        local all = {}
        for _, location in ipairs({ "hands", "belt", "pack" }) do
            for _, item in ipairs(self[location]) do
                all[#all + 1] = { item = item, location = location }
            end
        end
        return all
    end

    return inventory
end

return M

```

---

## File: src/logic/item_interaction.lua

```lua
-- item_interaction.lua
-- Item-Based Interaction for Majesty
-- Ticket T2_10: Allow items to bypass or aid in interactions (p. 16)
--
-- Design: Items can be used to probe POIs instead of adventurers.
-- On failure, items take notches instead of adventurers taking wounds.
-- This enables "orthogonal problem solving" - creative item use.
--
-- Example: Investigating a "Pit" with a "10-foot Pole" skips wound logic
-- and instead notches the pole.

local events = require('logic.events')
local inventory = require('logic.inventory')

local M = {}

--------------------------------------------------------------------------------
-- ITEM INTERACTION TYPES
-- What an item can do when used on a POI
--------------------------------------------------------------------------------
M.INTERACTION_TYPES = {
    PROBE    = "probe",     -- Test for traps/hazards (pole, stick)
    UNLOCK   = "unlock",    -- Open locks (key, lockpick)
    TRIGGER  = "trigger",   -- Activate from distance (thrown rock)
    LIGHT    = "light",     -- Illuminate (torch, lantern)
    PROTECT  = "protect",   -- Shield from effect (shield, umbrella)
    BREAK    = "break",     -- Destroy obstacle (hammer, axe)
    RETRIEVE = "retrieve",  -- Grab distant items (hook, rope)
}

--------------------------------------------------------------------------------
-- ITEM PROPERTY TAGS
-- Tags that enable special interactions
--------------------------------------------------------------------------------
M.ITEM_TAGS = {
    REACH      = "reach",       -- Can probe from distance (poles, spears)
    KEY        = "key",         -- Can unlock specific locks
    LIGHT_SOURCE = "light_source", -- Provides illumination
    TOOL       = "tool",        -- General-purpose tool
    PROBE      = "probe",       -- Can safely probe hazards
    HEAVY      = "heavy",       -- Can trigger pressure plates
    SHARP      = "sharp",       -- Can cut things
    FRAGILE    = "fragile",     -- Extra vulnerable to notching
}

--------------------------------------------------------------------------------
-- ITEM INTERACTION DEFINITIONS
-- Maps item properties to what they can do with POIs
--------------------------------------------------------------------------------

-- Which items can do which interaction types
local itemCapabilities = {
    ["10-foot Pole"]  = { M.INTERACTION_TYPES.PROBE, M.INTERACTION_TYPES.TRIGGER },
    ["Rope"]          = { M.INTERACTION_TYPES.RETRIEVE },
    ["Grappling Hook"] = { M.INTERACTION_TYPES.RETRIEVE, M.INTERACTION_TYPES.TRIGGER },
    ["Lockpick"]      = { M.INTERACTION_TYPES.UNLOCK },
    ["Crowbar"]       = { M.INTERACTION_TYPES.BREAK, M.INTERACTION_TYPES.PROBE },
    ["Hammer"]        = { M.INTERACTION_TYPES.BREAK, M.INTERACTION_TYPES.TRIGGER },
    ["Torch"]         = { M.INTERACTION_TYPES.LIGHT },
    ["Lantern"]       = { M.INTERACTION_TYPES.LIGHT },
    ["Shield"]        = { M.INTERACTION_TYPES.PROTECT },
}

-- Generic capabilities based on item tags
local tagCapabilities = {
    [M.ITEM_TAGS.REACH]   = { M.INTERACTION_TYPES.PROBE, M.INTERACTION_TYPES.TRIGGER },
    [M.ITEM_TAGS.PROBE]   = { M.INTERACTION_TYPES.PROBE },
    [M.ITEM_TAGS.KEY]     = { M.INTERACTION_TYPES.UNLOCK },
    [M.ITEM_TAGS.TOOL]    = { M.INTERACTION_TYPES.PROBE, M.INTERACTION_TYPES.BREAK },
    [M.ITEM_TAGS.HEAVY]   = { M.INTERACTION_TYPES.TRIGGER },
    [M.ITEM_TAGS.LIGHT_SOURCE] = { M.INTERACTION_TYPES.LIGHT },
}

--------------------------------------------------------------------------------
-- ITEM INTERACTION SYSTEM FACTORY
--------------------------------------------------------------------------------

--- Create a new ItemInteractionSystem
-- @param config table: { eventBus, roomManager }
-- @return ItemInteractionSystem instance
function M.createItemInteractionSystem(config)
    config = config or {}

    local system = {
        eventBus    = config.eventBus or events.globalBus,
        roomManager = config.roomManager,
    }

    ----------------------------------------------------------------------------
    -- CAPABILITY CHECKING
    ----------------------------------------------------------------------------

    --- Get all interaction types an item can perform
    -- @param item table: The item
    -- @return table: Array of interaction types
    function system:getItemCapabilities(item)
        local capabilities = {}
        local seen = {}

        -- Check by item name first
        if itemCapabilities[item.name] then
            for _, cap in ipairs(itemCapabilities[item.name]) do
                if not seen[cap] then
                    capabilities[#capabilities + 1] = cap
                    seen[cap] = true
                end
            end
        end

        -- Check by item tags
        if item.properties and item.properties.tags then
            for _, tag in ipairs(item.properties.tags) do
                if tagCapabilities[tag] then
                    for _, cap in ipairs(tagCapabilities[tag]) do
                        if not seen[cap] then
                            capabilities[#capabilities + 1] = cap
                            seen[cap] = true
                        end
                    end
                end
            end
        end

        return capabilities
    end

    --- Check if an item can perform a specific interaction type
    function system:canPerform(item, interactionType)
        local caps = self:getItemCapabilities(item)
        for _, cap in ipairs(caps) do
            if cap == interactionType then
                return true
            end
        end
        return false
    end

    --- Check if an item can be used on a POI
    -- @param item table: The item
    -- @param poi table: The POI/feature
    -- @return boolean, string: canUse, reason
    function system:canUseItemOnPOI(item, poi)
        -- Check if POI accepts items
        if poi.item_blocked then
            return false, "poi_rejects_items"
        end

        -- Check if item has any relevant capability
        local itemCaps = self:getItemCapabilities(item)
        if #itemCaps == 0 then
            return false, "item_has_no_capabilities"
        end

        -- Check for specific key requirements
        if poi.lock and poi.lock.key_id then
            if item.properties and item.properties.key_id == poi.lock.key_id then
                return true, "key_matches"
            end
        end

        -- Check if item can probe hazards
        if poi.trap or poi.type == "hazard" then
            if self:canPerform(item, M.INTERACTION_TYPES.PROBE) then
                return true, "can_probe_hazard"
            end
        end

        -- Generic capability match
        return true, "has_capabilities"
    end

    ----------------------------------------------------------------------------
    -- ITEM INTERACTION EXECUTION
    ----------------------------------------------------------------------------

    --- Use an item to interact with a POI
    -- @param item table: The item being used
    -- @param poi table: The POI/feature
    -- @param interactionType string: One of INTERACTION_TYPES
    -- @param context table: { roomId, adventurer, ... }
    -- @return table: { success, description, itemDamaged, itemDestroyed, poiStateChange }
    function system:useItemOnPOI(item, poi, interactionType, context)
        context = context or {}

        local result = {
            success = false,
            description = "",
            itemDamaged = false,
            itemDestroyed = false,
            poiStateChange = nil,
        }

        -- Check if item can do this interaction
        if not self:canPerform(item, interactionType) then
            result.description = "This " .. item.name .. " can't be used that way."
            return result
        end

        -- Handle different interaction types
        if interactionType == M.INTERACTION_TYPES.PROBE then
            return self:handleProbe(item, poi, context)
        elseif interactionType == M.INTERACTION_TYPES.UNLOCK then
            return self:handleUnlock(item, poi, context)
        elseif interactionType == M.INTERACTION_TYPES.TRIGGER then
            return self:handleTrigger(item, poi, context)
        elseif interactionType == M.INTERACTION_TYPES.LIGHT then
            return self:handleLight(item, poi, context)
        elseif interactionType == M.INTERACTION_TYPES.BREAK then
            return self:handleBreak(item, poi, context)
        end

        result.description = "Nothing happens."
        return result
    end

    ----------------------------------------------------------------------------
    -- INTERACTION HANDLERS
    ----------------------------------------------------------------------------

    --- Handle PROBE interaction (safely check for traps/hazards)
    function system:handleProbe(item, poi, context)
        local result = {
            success = true,
            description = "",
            itemDamaged = false,
            itemDestroyed = false,
        }

        -- Probing a trap
        if poi.trap then
            if poi.trap.detected then
                result.description = "You've already detected a trap here."
                return result
            end

            -- Probing with a pole/tool detects the trap safely!
            result.description = "Using your " .. item.name .. ", you detect " ..
                (poi.trap.description or "a trap") .. "!"

            -- Mark trap as detected
            if self.roomManager and context.roomId then
                local feature = self.roomManager:getFeature(context.roomId, poi.id)
                if feature and feature.trap then
                    feature.trap.detected = true
                end
            end

            -- But the item might still take damage from the probing
            if poi.trap.damages_probe then
                local notchResult = inventory.addNotch(item)
                result.itemDamaged = true
                result.itemDestroyed = (notchResult == "destroyed")

                if result.itemDestroyed then
                    result.description = result.description .. " Your " .. item.name .. " is destroyed in the process!"
                else
                    result.description = result.description .. " Your " .. item.name .. " is slightly damaged."
                end
            end

            -- Emit trap detected event
            self.eventBus:emit(events.EVENTS.TRAP_DETECTED, {
                roomId = context.roomId,
                poiId = poi.id,
                trap = poi.trap,
                method = "item_probe",
                item = item.id,
            })

            return result
        end

        -- Probing a hazard (pit, unstable floor, etc.)
        if poi.type == "hazard" then
            result.description = "You probe the " .. (poi.name or "hazard") .. " with your " .. item.name .. "."

            if poi.hazard_description then
                result.description = result.description .. " " .. poi.hazard_description
            end

            return result
        end

        -- Generic probing
        result.description = "You poke at the " .. (poi.name or "object") .. " with your " .. item.name .. ". Nothing notable happens."
        return result
    end

    --- Handle UNLOCK interaction
    function system:handleUnlock(item, poi, context)
        local result = {
            success = false,
            description = "",
            itemDamaged = false,
            itemDestroyed = false,
        }

        if not poi.lock then
            result.description = "There's nothing to unlock here."
            return result
        end

        -- Check for key match
        if poi.lock.key_id then
            if item.properties and item.properties.key_id == poi.lock.key_id then
                result.success = true
                result.description = "The " .. item.name .. " fits! You unlock it."
                result.poiStateChange = "unlocked"

                if self.roomManager and context.roomId then
                    self.roomManager:setFeatureState(context.roomId, poi.id, "unlocked")
                end

                return result
            else
                result.description = "This " .. item.name .. " doesn't fit the lock."
                return result
            end
        end

        -- Lockpick attempt (would normally require a test)
        if item.name == "Lockpick" or (item.properties and item.properties.lockpick) then
            result.requiresTest = true
            result.testConfig = {
                attribute = "pentacles",
                difficulty = poi.lock.difficulty or 14,
            }
            result.description = "You attempt to pick the lock..."
            return result
        end

        result.description = "You can't unlock this with a " .. item.name .. "."
        return result
    end

    --- Handle TRIGGER interaction (activate from distance)
    function system:handleTrigger(item, poi, context)
        local result = {
            success = true,
            description = "",
            itemDamaged = false,
            itemDestroyed = false,
        }

        -- Triggering a known trap from distance
        if poi.trap and poi.trap.detected then
            result.description = "You trigger the trap from a safe distance using your " .. item.name .. "."

            -- Trap is triggered but no one is hurt
            if self.roomManager and context.roomId then
                local feature = self.roomManager:getFeature(context.roomId, poi.id)
                if feature and feature.trap then
                    feature.trap.disarmed = true  -- Triggered = disarmed
                end
            end

            self.eventBus:emit(events.EVENTS.TRAP_TRIGGERED, {
                roomId = context.roomId,
                poiId = poi.id,
                trap = poi.trap,
                method = "item_trigger",
                item = item.id,
                safelyTriggered = true,
            })

            return result
        end

        -- Triggering a mechanism
        if poi.type == "mechanism" then
            result.description = "You activate the " .. (poi.name or "mechanism") .. " with your " .. item.name .. "."
            return result
        end

        result.description = "You poke at it with your " .. item.name .. "."
        return result
    end

    --- Handle LIGHT interaction
    function system:handleLight(item, poi, context)
        local result = {
            success = true,
            description = "",
        }

        if poi.type == "light" and poi.state == "unlit" then
            result.description = "You light the " .. (poi.name or "light source") .. " with your " .. item.name .. "."
            result.poiStateChange = "lit"

            if self.roomManager and context.roomId then
                self.roomManager:setFeatureState(context.roomId, poi.id, "lit")
            end

            return result
        end

        result.description = "You wave your " .. item.name .. " around, casting dancing shadows."
        return result
    end

    --- Handle BREAK interaction
    function system:handleBreak(item, poi, context)
        local result = {
            success = false,
            description = "",
            itemDamaged = false,
            itemDestroyed = false,
        }

        -- Can't break indestructible things
        if poi.indestructible then
            result.description = "The " .. (poi.name or "object") .. " is far too sturdy to break."
            return result
        end

        -- Breaking something usually requires a test or just succeeds for fragile things
        if poi.fragile or poi.breakable then
            result.success = true
            result.description = "You smash the " .. (poi.name or "object") .. " with your " .. item.name .. "!"
            result.poiStateChange = "destroyed"

            if self.roomManager and context.roomId then
                self.roomManager:setFeatureState(context.roomId, poi.id, "destroyed")
            end

            -- Breaking things may damage the tool
            if not poi.fragile then  -- Only fragile things break without tool damage
                local notchResult = inventory.addNotch(item)
                result.itemDamaged = (notchResult == "notched")
                result.itemDestroyed = (notchResult == "destroyed")
            end

            return result
        end

        result.description = "You'd need more than a " .. item.name .. " to break that."
        return result
    end

    ----------------------------------------------------------------------------
    -- DAMAGE ABSORPTION
    -- Items can take notches instead of adventurers taking wounds
    ----------------------------------------------------------------------------

    --- Have an item absorb damage that would wound an adventurer
    -- @param item table: The item absorbing damage
    -- @return table: { absorbed, itemDestroyed, description }
    function system:absorbDamage(item)
        local result = {
            absorbed = false,
            itemDestroyed = false,
            description = "",
        }

        -- Item must be able to absorb damage (shields, armor, tools in hands)
        if item.destroyed then
            result.description = "The " .. item.name .. " is already destroyed."
            return result
        end

        local notchResult = inventory.addNotch(item)

        result.absorbed = true
        result.itemDestroyed = (notchResult == "destroyed")

        if result.itemDestroyed then
            result.description = "Your " .. item.name .. " takes the blow and shatters!"
        else
            result.description = "Your " .. item.name .. " takes the blow and is notched."
        end

        self.eventBus:emit(events.EVENTS.ITEM_DAMAGE_ABSORBED, {
            itemId = item.id,
            destroyed = result.itemDestroyed,
        })

        return result
    end

    return system
end

return M

```

---

## File: src/logic/light_system.lua

```lua
-- light_system.lua
-- Light Economy System for Majesty
-- Ticket T3_2: Torch flickering and darkness penalties
--
-- Major Arcana I-V (Torches Gutter) causes light sources to degrade.
-- When no light source exists in a Zone, all entities gain BLIND effect.

local events = require('logic.events')
local inventory = require('logic.inventory')

local M = {}

--------------------------------------------------------------------------------
-- LIGHT SOURCE DEFINITIONS
-- Items that can provide light and their flicker capacities
--------------------------------------------------------------------------------
M.LIGHT_SOURCES = {
    ["Torch"]       = { flicker_max = 3, consumable = true },
    ["Lantern"]     = { flicker_max = 6, consumable = false },  -- Uses oil
    ["Candle"]      = { flicker_max = 2, consumable = true },
    ["Glowstone"]   = { flicker_max = 0, consumable = false },  -- Never gutters
}

--------------------------------------------------------------------------------
-- LIGHT LEVELS
--------------------------------------------------------------------------------
M.LIGHT_LEVELS = {
    BRIGHT = "bright",       -- Multiple light sources
    NORMAL = "normal",       -- One active light source
    DIM    = "dim",          -- Light source low on flickers
    DARK   = "dark",         -- No light source
}

--------------------------------------------------------------------------------
-- LIGHT SYSTEM FACTORY
--------------------------------------------------------------------------------

--- Create a new LightSystem
-- @param config table: { eventBus, guild, zoneSystem }
-- @return LightSystem instance
function M.createLightSystem(config)
    config = config or {}

    local system = {
        eventBus   = config.eventBus or events.globalBus,
        guild      = config.guild or {},    -- Array of adventurers with inventories
        zoneSystem = config.zoneSystem,     -- Optional: for zone-based darkness

        -- Track current light level per zone
        zoneLightLevels = {},

        -- UI callback for darkness effect
        onDarknessChanged = config.onDarknessChanged,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    --- Initialize and subscribe to events
    function system:init()
        -- Subscribe to torches gutter events
        self.eventBus:on(events.EVENTS.TORCHES_GUTTER, function(data)
            self:handleTorchesGutter(data)
        end)

        -- Initial light check
        self:recalculateLightLevel()
    end

    ----------------------------------------------------------------------------
    -- LIGHT SOURCE TRACKING
    ----------------------------------------------------------------------------

    --- Check if an item is a light source
    -- @param item table: Inventory item
    -- @return boolean, table: isLightSource, lightSourceConfig
    function system:isLightSource(item)
        if not item or item.destroyed then
            return false, nil
        end

        local config = M.LIGHT_SOURCES[item.name]
        if config then
            return true, config
        end

        -- Check for light_source property on custom items
        if item.properties and item.properties.light_source then
            return true, item.properties.light_source
        end

        return false, nil
    end

    --- Find all active light sources in the guild
    -- @return table: Array of { entity, item, location }
    function system:findActiveLightSources()
        local sources = {}

        for _, entity in ipairs(self.guild) do
            if entity.inventory then
                -- Only check hands and belt (active locations)
                for _, loc in ipairs({ "hands", "belt" }) do
                    local items = entity.inventory:getItems(loc)
                    for _, item in ipairs(items) do
                        local isLight, lightConfig = self:isLightSource(item)
                        if isLight then
                            -- Check if light has flickers remaining
                            local flickerCount = item.properties and item.properties.flicker_count
                            if not flickerCount or flickerCount > 0 then
                                sources[#sources + 1] = {
                                    entity      = entity,
                                    item        = item,
                                    location    = loc,
                                    lightConfig = lightConfig,
                                }
                            end
                        end
                    end
                end
            end
        end

        return sources
    end

    ----------------------------------------------------------------------------
    -- TORCHES GUTTER HANDLING
    -- Called when Major Arcana I-V is drawn
    ----------------------------------------------------------------------------

    --- Handle the Torches Gutter event
    -- @param data table: { card, category, value }
    function system:handleTorchesGutter(data)
        local sources = self:findActiveLightSources()

        if #sources == 0 then
            -- No light sources to degrade - darkness intensifies
            self:recalculateLightLevel()
            return
        end

        -- Find the primary light holder (first adventurer holding light in hands)
        local primarySource = nil
        for _, source in ipairs(sources) do
            if source.location == "hands" then
                primarySource = source
                break
            end
        end

        -- Fall back to first available source
        if not primarySource then
            primarySource = sources[1]
        end

        -- Decrement flicker count
        local item = primarySource.item
        local lightConfig = primarySource.lightConfig

        -- Initialize flicker_count if not set
        if not item.properties then
            item.properties = {}
        end
        if not item.properties.flicker_count then
            item.properties.flicker_count = lightConfig.flicker_max
        end

        -- Decrement
        item.properties.flicker_count = item.properties.flicker_count - 1

        -- Emit event for UI updates
        self.eventBus:emit("light_flickered", {
            entity       = primarySource.entity,
            item         = item,
            remaining    = item.properties.flicker_count,
            cardValue    = data.value,
        })

        -- Check if extinguished
        if item.properties.flicker_count <= 0 then
            self:extinguishLight(primarySource)
        end

        -- Recalculate overall light level
        self:recalculateLightLevel()
    end

    --- Extinguish a light source
    -- @param source table: { entity, item, location, lightConfig }
    function system:extinguishLight(source)
        local item = source.item
        local lightConfig = source.lightConfig

        if lightConfig.consumable then
            -- Consumable lights are destroyed (torches, candles)
            item.destroyed = true
            item.properties.extinguished = true

            self.eventBus:emit("light_destroyed", {
                entity = source.entity,
                item   = item,
            })
        else
            -- Non-consumable lights need refueling (lanterns)
            item.properties.extinguished = true

            self.eventBus:emit("light_extinguished", {
                entity = source.entity,
                item   = item,
                needsFuel = true,
            })
        end
    end

    ----------------------------------------------------------------------------
    -- LIGHT LEVEL CALCULATION
    ----------------------------------------------------------------------------

    --- Recalculate the current light level for the party
    function system:recalculateLightLevel()
        local sources = self:findActiveLightSources()

        local previousLevel = self.currentLightLevel
        local newLevel

        if #sources == 0 then
            newLevel = M.LIGHT_LEVELS.DARK
        elseif #sources == 1 then
            -- Check if the single source is running low
            local source = sources[1]
            local remaining = source.item.properties and source.item.properties.flicker_count
            local max = source.lightConfig.flicker_max
            if remaining and max > 0 and remaining <= math.floor(max / 3) then
                newLevel = M.LIGHT_LEVELS.DIM
            else
                newLevel = M.LIGHT_LEVELS.NORMAL
            end
        else
            newLevel = M.LIGHT_LEVELS.BRIGHT
        end

        self.currentLightLevel = newLevel

        -- Emit change event if level changed
        if previousLevel ~= newLevel then
            self.eventBus:emit("light_level_changed", {
                previous = previousLevel,
                current  = newLevel,
                sources  = #sources,
            })

            -- Apply darkness penalties if now dark
            if newLevel == M.LIGHT_LEVELS.DARK then
                self:applyDarknessPenalty()
            elseif previousLevel == M.LIGHT_LEVELS.DARK then
                self:removeDarknessPenalty()
            end

            -- Notify UI callback
            if self.onDarknessChanged then
                self.onDarknessChanged(newLevel)
            end
        end
    end

    ----------------------------------------------------------------------------
    -- DARKNESS PENALTIES
    -- When in darkness, all entities gain BLIND effect
    ----------------------------------------------------------------------------

    --- Apply darkness penalty (BLIND) to all guild members
    function system:applyDarknessPenalty()
        for _, entity in ipairs(self.guild) do
            if entity.conditions then
                entity.conditions.blind = true
            end
        end

        self.eventBus:emit("darkness_fell", {
            affectedCount = #self.guild,
        })
    end

    --- Remove darkness penalty when light is restored
    function system:removeDarknessPenalty()
        for _, entity in ipairs(self.guild) do
            if entity.conditions then
                entity.conditions.blind = false
            end
        end

        self.eventBus:emit("darkness_lifted", {
            affectedCount = #self.guild,
        })
    end

    ----------------------------------------------------------------------------
    -- LIGHT ITEM UTILITIES
    ----------------------------------------------------------------------------

    --- Light a new torch/candle (set initial flicker count)
    -- @param item table: The light source item
    -- @return boolean: success
    function system:lightSource(item)
        local isLight, lightConfig = self:isLightSource(item)
        if not isLight then
            return false
        end

        if item.destroyed then
            return false
        end

        if not item.properties then
            item.properties = {}
        end

        item.properties.flicker_count = lightConfig.flicker_max
        item.properties.extinguished = false

        self:recalculateLightLevel()
        return true
    end

    --- Refuel a lantern (reset flicker count)
    -- @param lantern table: The lantern item
    -- @param fuel table: The oil/fuel item (will be consumed)
    -- @return boolean: success
    function system:refuelLantern(lantern, fuel)
        if lantern.name ~= "Lantern" then
            return false
        end

        if not fuel or fuel.destroyed then
            return false
        end

        -- Consume fuel
        if fuel.stackable and fuel.quantity > 1 then
            fuel.quantity = fuel.quantity - 1
        else
            fuel.destroyed = true
        end

        -- Reset lantern
        if not lantern.properties then
            lantern.properties = {}
        end
        lantern.properties.flicker_count = M.LIGHT_SOURCES["Lantern"].flicker_max
        lantern.properties.extinguished = false

        self:recalculateLightLevel()
        return true
    end

    ----------------------------------------------------------------------------
    -- QUERIES
    ----------------------------------------------------------------------------

    --- Get the current light level
    function system:getLightLevel()
        return self.currentLightLevel or M.LIGHT_LEVELS.DARK
    end

    --- Check if party is in darkness
    function system:isDark()
        return self.currentLightLevel == M.LIGHT_LEVELS.DARK
    end

    --- Get total remaining flickers across all light sources
    function system:getTotalFlickers()
        local sources = self:findActiveLightSources()
        local total = 0

        for _, source in ipairs(sources) do
            local remaining = source.item.properties and source.item.properties.flicker_count
            if remaining then
                total = total + remaining
            else
                total = total + source.lightConfig.flicker_max
            end
        end

        return total
    end

    --- Set the guild (for updates during gameplay)
    function system:setGuild(guildMembers)
        self.guild = guildMembers
        self:recalculateLightLevel()
    end

    return system
end

return M

```

---

## File: src/logic/meatgrinder.lua

```lua
-- meatgrinder.lua
-- Meatgrinder Procedural Engine for Majesty
-- Ticket T2_4: Random event table consuming Major Arcana draws
--
-- Design: Uses callback pattern instead of giant switch statements.
-- Rooms can override specific results for context-sensitive events.
--
-- Rules Reference (p. 91, p. 340):
-- I-V:     Torches Gutter (light sources flicker)
-- VI-X:    Curiosity (room-specific flavor text)
-- XI-XV:   Travel Event (traps/stress/resource tax)
-- XVI-XX:  Random Encounter (spawn mobs)
-- XXI:     Quest Rumor (hint towards current quest)

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- MEATGRINDER CATEGORIES
-- Matches watch_manager.lua categories
--------------------------------------------------------------------------------
M.CATEGORIES = {
    TORCHES_GUTTER   = "torches_gutter",
    CURIOSITY        = "curiosity",
    TRAVEL_EVENT     = "travel_event",
    RANDOM_ENCOUNTER = "random_encounter",
    QUEST_RUMOR      = "quest_rumor",
}

--------------------------------------------------------------------------------
-- RESULT OBJECT FACTORY
-- Standardized result for all Meatgrinder events
--------------------------------------------------------------------------------

local function createResult(category, data)
    return {
        category    = category,
        description = data.description or "",
        effects     = data.effects or {},
        spawns      = data.spawns or {},
        consumed    = data.consumed or false,  -- Mark off after triggering
        raw         = data,
    }
end

--------------------------------------------------------------------------------
-- DEFAULT EVENT HANDLERS
-- These are used when a room doesn't provide custom handlers
--------------------------------------------------------------------------------

local defaultHandlers = {}

--- I-V: Torches Gutter
-- Light sources flicker and may go out
defaultHandlers[M.CATEGORIES.TORCHES_GUTTER] = function(card, room, context)
    return createResult(M.CATEGORIES.TORCHES_GUTTER, {
        description = "The torches flicker and sputter. Shadows dance on the walls.",
        effects = {
            { type = "light_flicker", severity = 1 },
        },
    })
end

--- VI-X: Curiosity
-- Atmospheric flavor, hints at dangers ahead
defaultHandlers[M.CATEGORIES.CURIOSITY] = function(card, room, context)
    -- Default curiosities - rooms should override for thematic content
    local curiosities = {
        "You hear distant echoes - footsteps? Dripping water? Impossible to tell.",
        "A cold draft brushes past you, carrying the scent of old stone.",
        "Scratches on the wall mark the passage of others before you.",
        "Something glints briefly in the darkness, then is gone.",
        "The silence here feels heavy, oppressive.",
    }

    -- Use card value to pick a curiosity (deterministic based on draw)
    local index = ((card.value - 6) % #curiosities) + 1

    return createResult(M.CATEGORIES.CURIOSITY, {
        description = curiosities[index],
        effects = {},  -- Curiosities are usually just flavor
    })
end

--- XI-XV: Travel Event
-- Resource tax, traps, hazards requiring choices or tests
defaultHandlers[M.CATEGORIES.TRAVEL_EVENT] = function(card, room, context)
    -- Default travel events - rooms should override for specific hazards
    local travelEvents = {
        {
            description = "The path ahead is treacherous. Test Pentacles or take a wound from a fall.",
            effects = { { type = "test_required", attribute = "pentacles", failure = "wound" } },
        },
        {
            description = "A loose stone triggers a grinding noise behind you. Something is alerted.",
            effects = { { type = "noise", severity = 1 } },
        },
        {
            description = "Your pack catches on a jagged outcropping. One random item is damaged.",
            effects = { { type = "item_damage", target = "random" } },
        },
        {
            description = "The air grows thin and stale. Everyone becomes Stressed unless you turn back.",
            effects = { { type = "choice", options = { "stress_all", "turn_back" } } },
        },
        {
            description = "A hidden pit! The first in marching order must test Pentacles or fall.",
            effects = { { type = "trap", trap_type = "pit", target = "first_in_march" } },
        },
    }

    local index = ((card.value - 11) % #travelEvents) + 1

    return createResult(M.CATEGORIES.TRAVEL_EVENT, travelEvents[index])
end

--- XVI-XX: Random Encounter
-- Meet denizens of the Underworld
defaultHandlers[M.CATEGORIES.RANDOM_ENCOUNTER] = function(card, room, context)
    -- Default encounters - rooms MUST override for thematic content
    -- This is just a placeholder that spawns generic threats
    return createResult(M.CATEGORIES.RANDOM_ENCOUNTER, {
        description = "Something stirs in the darkness...",
        spawns = {
            { blueprint_id = "skeleton_brute", count = 1 },
        },
        effects = {
            { type = "encounter_start" },
        },
    })
end

--- XXI: Quest Rumor
-- Hint towards current quest goal
defaultHandlers[M.CATEGORIES.QUEST_RUMOR] = function(card, room, context)
    -- Default rumor - should be overridden by quest system
    return createResult(M.CATEGORIES.QUEST_RUMOR, {
        description = "You sense you're on the right path. Something important lies deeper within.",
        effects = {
            { type = "quest_progress", hint = true },
        },
    })
end

--------------------------------------------------------------------------------
-- MEATGRINDER ENGINE FACTORY
--------------------------------------------------------------------------------

--- Create a new Meatgrinder engine
-- @param config table: { eventBus, entityFactory, questSystem }
-- @return Meatgrinder instance
function M.createMeatgrinder(config)
    config = config or {}

    local grinder = {
        eventBus      = config.eventBus or events.globalBus,
        entityFactory = config.entityFactory,
        questSystem   = config.questSystem,
        -- Track consumed events (p. 91: "mark it off")
        consumed      = {},
        -- Custom handlers for specific rooms/dungeons
        customHandlers = {},
    }

    ----------------------------------------------------------------------------
    -- HANDLER REGISTRATION
    -- Allows dungeons/rooms to register custom Meatgrinder entries
    ----------------------------------------------------------------------------

    --- Register a custom handler for a category
    -- @param category string: One of CATEGORIES
    -- @param roomId string|nil: Room ID (nil for dungeon-wide)
    -- @param handler function(card, room, context) -> result
    function grinder:registerHandler(category, roomId, handler)
        local key = roomId and (roomId .. ":" .. category) or ("default:" .. category)
        self.customHandlers[key] = handler
    end

    --- Register a complete custom table for a room
    -- @param roomId string
    -- @param handlers table: { category -> handler }
    function grinder:registerRoomTable(roomId, handlers)
        for category, handler in pairs(handlers) do
            self:registerHandler(category, roomId, handler)
        end
    end

    ----------------------------------------------------------------------------
    -- EVENT RESOLUTION
    ----------------------------------------------------------------------------

    --- Get the appropriate handler for a category and room
    local function getHandler(self, category, roomId)
        -- Priority 1: Room-specific handler
        if roomId then
            local roomKey = roomId .. ":" .. category
            if self.customHandlers[roomKey] then
                return self.customHandlers[roomKey]
            end
        end

        -- Priority 2: Dungeon-wide custom handler
        local dungeonKey = "default:" .. category
        if self.customHandlers[dungeonKey] then
            return self.customHandlers[dungeonKey]
        end

        -- Priority 3: Default handler
        return defaultHandlers[category]
    end

    --- Categorize a card draw (same logic as watch_manager)
    local function categorizeCard(cardValue)
        if cardValue >= 1 and cardValue <= 5 then
            return M.CATEGORIES.TORCHES_GUTTER
        elseif cardValue >= 6 and cardValue <= 10 then
            return M.CATEGORIES.CURIOSITY
        elseif cardValue >= 11 and cardValue <= 15 then
            return M.CATEGORIES.TRAVEL_EVENT
        elseif cardValue >= 16 and cardValue <= 20 then
            return M.CATEGORIES.RANDOM_ENCOUNTER
        elseif cardValue == 21 then
            return M.CATEGORIES.QUEST_RUMOR
        end
        return nil
    end

    --- Create a unique key for tracking consumed events
    local function makeConsumedKey(category, roomId)
        return (roomId or "global") .. ":" .. category
    end

    --- Resolve a Meatgrinder event
    -- @param card table: The Major Arcana card drawn
    -- @param currentRoom table: The room the party is in
    -- @param context table: Additional context { party, dungeon, ... }
    -- @return table: Result object with description, effects, spawns
    function grinder:resolveEvent(card, currentRoom, context)
        context = context or {}

        local category = categorizeCard(card.value)
        if not category then
            return nil
        end

        local roomId = currentRoom and currentRoom.id

        -- Check if this specific event was already consumed (p. 91)
        -- "If the cards are shuffled and the GM draws the same event twice,
        -- nothing happens and the guild has a watch of respite."
        local consumedKey = makeConsumedKey(category, roomId)
        if self.consumed[consumedKey] then
            return createResult(category, {
                description = "A moment of respite. The Underworld holds its breath.",
                effects = { { type = "respite" } },
                consumed = true,
            })
        end

        -- Get appropriate handler
        local handler = getHandler(self, category, roomId)
        if not handler then
            return nil
        end

        -- Execute handler
        local result = handler(card, currentRoom, context)

        -- Mark as consumed
        self.consumed[consumedKey] = true
        result.consumed = true

        -- Emit event for other systems
        self.eventBus:emit(events.EVENTS.MEATGRINDER_ROLL, {
            card     = card,
            category = category,
            roomId   = roomId,
            result   = result,
        })

        return result
    end

    ----------------------------------------------------------------------------
    -- TABLE MANAGEMENT
    ----------------------------------------------------------------------------

    --- Reset consumed events (called after City Phase)
    function grinder:resetConsumed()
        self.consumed = {}
    end

    --- Check if an event type is consumed for a room
    function grinder:isConsumed(category, roomId)
        local key = makeConsumedKey(category, roomId)
        return self.consumed[key] or false
    end

    --- Get all consumed events
    function grinder:getConsumedEvents()
        local list = {}
        for key, _ in pairs(self.consumed) do
            list[#list + 1] = key
        end
        return list
    end

    ----------------------------------------------------------------------------
    -- CONVENIENCE METHODS
    ----------------------------------------------------------------------------

    --- Resolve just by card value (for testing)
    function grinder:resolveByValue(cardValue, currentRoom, context)
        local mockCard = { value = cardValue, suit = 5 }  -- suit 5 = Major
        return self:resolveEvent(mockCard, currentRoom, context)
    end

    --- Get category for a card value
    function grinder:getCategory(cardValue)
        return categorizeCard(cardValue)
    end

    return grinder
end

return M

```

---

## File: src/logic/npc_ai.lua

```lua
-- npc_ai.lua
-- NPC "Dread" AI System for Majesty
-- Ticket S4.5: Basic NPC decision-making for challenges
--
-- AI Decision Logic:
-- 1. Elite/Lord NPCs with Greater Doom (15-21) use it immediately
-- 2. Otherwise, attack the PC with lowest current defense
-- 3. Mob Rule: NPCs in same zone get Favor/Piercing bonuses
--
-- This is intentionally simple - NPCs should feel dangerous but fair.

local events = require('logic.events')
local constants = require('constants')
local action_resolver = require('logic.action_resolver')

local M = {}

--------------------------------------------------------------------------------
-- NPC RANKS (determines AI aggression)
--------------------------------------------------------------------------------
M.RANKS = {
    MINION  = "minion",    -- Basic enemy, simple tactics
    SOLDIER = "soldier",   -- Standard enemy
    ELITE   = "elite",     -- Uses Greater Dooms aggressively
    LORD    = "lord",      -- Boss-level, always uses best card
}

--------------------------------------------------------------------------------
-- GREATER DOOM THRESHOLD
-- Major Arcana cards 15-21 (Devil through World) are "Greater Dooms"
--------------------------------------------------------------------------------
local GREATER_DOOM_MIN = 15

--------------------------------------------------------------------------------
-- NPC AI FACTORY
--------------------------------------------------------------------------------

--- Create a new NPC AI manager
-- @param config table: { eventBus, challengeController, actionResolver, gmDeck, zoneSystem }
-- @return NPCAI instance
function M.createNPCAI(config)
    config = config or {}

    local ai = {
        eventBus            = config.eventBus or events.globalBus,
        challengeController = config.challengeController,
        actionResolver      = config.actionResolver,
        gmDeck              = config.gmDeck,
        zoneSystem          = config.zoneSystem,

        -- GM's hand (cards available for NPC actions)
        hand = {},
        handSize = 3,  -- NPCs typically have access to 3 cards
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function ai:init()
        -- Listen for NPC turns
        self.eventBus:on("npc_turn", function(data)
            self:handleNPCTurn(data)
        end)

        -- Listen for NPC initiative selection (S4.6)
        self.eventBus:on("npc_choose_initiative", function(data)
            self:handleNPCInitiative(data)
        end)

        -- Listen for challenge start to draw initial hand
        self.eventBus:on(events.EVENTS.CHALLENGE_START, function(data)
            self:drawHand()
        end)

        -- Listen for challenge end to discard hand
        self.eventBus:on(events.EVENTS.CHALLENGE_END, function(data)
            self:discardHand()
        end)
    end

    ----------------------------------------------------------------------------
    -- INITIATIVE SELECTION (S4.6)
    ----------------------------------------------------------------------------

    --- Handle NPC initiative card selection
    -- @param data table: { npc, round }
    function ai:handleNPCInitiative(data)
        local npc = data.npc
        if not npc then return end

        -- Ensure we have cards
        if #self.hand == 0 then
            self:drawHand()
        end

        if #self.hand == 0 then
            print("[NPC AI] No cards for initiative!")
            return
        end

        -- Choose initiative card based on rank/behavior
        local cardIndex = self:chooseInitiativeCard(npc)
        local card = self:useCard(cardIndex)

        if card then
            print("[NPC AI] " .. (npc.name or "NPC") .. " chose initiative: " .. (card.name or "?") .. " (value " .. (card.value or 0) .. ")")

            -- Submit to challenge controller
            if self.challengeController then
                self.challengeController:submitInitiative(npc, card)
            end
        end
    end

    --- Choose which card to use for initiative based on NPC behavior
    -- Aggressive mobs pick LOW values (act early)
    -- Cowardly/defensive mobs pick HIGH values (act late, react to others)
    -- @param npc table: The NPC entity
    -- @return number: Index of card to use
    function ai:chooseInitiativeCard(npc)
        local rank = npc.rank or M.RANKS.SOLDIER
        local behavior = npc.behavior or "aggressive"

        -- Sort hand by value for easier selection
        local sorted = {}
        for i, card in ipairs(self.hand) do
            sorted[#sorted + 1] = { index = i, value = card.value or 0 }
        end
        table.sort(sorted, function(a, b)
            return a.value < b.value
        end)

        -- Aggressive: pick lowest value (act first)
        if behavior == "aggressive" or rank == M.RANKS.LORD then
            return sorted[1].index
        end

        -- Cowardly/defensive: pick highest value (act last, defensive)
        if behavior == "cowardly" or behavior == "defensive" then
            return sorted[#sorted].index
        end

        -- Default (soldier): pick middle value
        local middleIdx = math.ceil(#sorted / 2)
        return sorted[middleIdx].index
    end

    ----------------------------------------------------------------------------
    -- HAND MANAGEMENT
    ----------------------------------------------------------------------------

    --- Draw cards into GM hand
    function ai:drawHand()
        self.hand = {}
        if not self.gmDeck then return end

        for _ = 1, self.handSize do
            local card = self.gmDeck:draw()
            if card then
                self.hand[#self.hand + 1] = card
            end
        end
    end

    --- Discard all cards in hand
    function ai:discardHand()
        if not self.gmDeck then return end

        for _, card in ipairs(self.hand) do
            self.gmDeck:discard(card)
        end
        self.hand = {}
    end

    --- Draw a single card (after using one)
    function ai:drawCard()
        if not self.gmDeck then return nil end
        local card = self.gmDeck:draw()
        if card then
            self.hand[#self.hand + 1] = card
        end
        return card
    end

    --- Use a card from hand (remove and return it)
    function ai:useCard(index)
        if index and index <= #self.hand then
            local card = table.remove(self.hand, index)
            if self.gmDeck then
                self.gmDeck:discard(card)
            end
            -- Draw replacement
            self:drawCard()
            return card
        end
        return nil
    end

    ----------------------------------------------------------------------------
    -- MAIN DECISION ENTRY POINT
    ----------------------------------------------------------------------------

    --- Handle an NPC's turn
    -- @param data table: { npc, turn, pcs }
    function ai:handleNPCTurn(data)
        local npc = data.npc
        local pcs = data.pcs or {}

        if not npc then
            print("[NPC AI] No NPC provided!")
            return
        end

        print("[NPC AI] " .. (npc.name or "NPC") .. " is deciding...")

        -- Make decision
        local decision = self:decide(npc, pcs)

        if decision then
            -- Submit action to challenge controller
            if self.challengeController then
                self.challengeController:submitAction(decision)
            end
        else
            -- No valid action, pass turn
            print("[NPC AI] " .. (npc.name or "NPC") .. " has no valid action")
            self.eventBus:emit(events.EVENTS.UI_SEQUENCE_COMPLETE, {})
        end
    end

    --- Main decision function
    -- @param npc table: The NPC entity
    -- @param pcs table: Array of PC entities
    -- @return table: Action to take, or nil
    function ai:decide(npc, pcs)
        if #self.hand == 0 then
            self:drawHand()
        end

        if #self.hand == 0 then
            return nil  -- No cards available
        end

        local rank = npc.rank or M.RANKS.SOLDIER

        -- Step 1: Check for Greater Doom usage (Elite/Lord only)
        if rank == M.RANKS.ELITE or rank == M.RANKS.LORD then
            local greaterDoomIndex = self:findGreaterDoom()
            if greaterDoomIndex then
                local target = self:selectTarget(npc, pcs, true)  -- melee only
                if target then
                    local card = self:useCard(greaterDoomIndex)
                    return self:createAttackAction(npc, target, card)
                end
            end
        end

        -- Step 2: Try melee attack (same zone only)
        local meleeTarget = self:selectTarget(npc, pcs, true)  -- melee only
        if meleeTarget then
            -- Select best card for attack (highest value)
            local cardIndex = self:selectBestCard()
            local card = self:useCard(cardIndex)

            if card then
                print("[NPC AI] " .. (npc.name or "NPC") .. " attacks " .. (meleeTarget.name or "PC") .. " in zone " .. (npc.zone or "?"))
                return self:createAttackAction(npc, meleeTarget, card)
            end
        end

        -- Step 3: No melee target - try to move toward a target
        local anyTarget = self:selectTarget(npc, pcs, false)  -- any target
        if anyTarget and anyTarget.zone ~= npc.zone then
            -- Move toward the target's zone
            local cardIndex = self:selectBestCard()
            local card = self:useCard(cardIndex)

            if card then
                print("[NPC AI] " .. (npc.name or "NPC") .. " moves from " .. (npc.zone or "?") .. " to " .. (anyTarget.zone or "?"))
                return self:createMoveAction(npc, anyTarget.zone, card)
            end
        end

        -- No valid action
        print("[NPC AI] " .. (npc.name or "NPC") .. " has no valid targets or movement options")
        return nil
    end

    ----------------------------------------------------------------------------
    -- CARD SELECTION
    ----------------------------------------------------------------------------

    --- Find a Greater Doom (15-21) in hand
    -- @return number|nil: Index of Greater Doom card, or nil
    function ai:findGreaterDoom()
        for i, card in ipairs(self.hand) do
            if card.is_major and card.value >= GREATER_DOOM_MIN then
                return i
            end
        end
        return nil
    end

    --- Select the best card for an attack
    -- @return number: Index of best card (highest value)
    function ai:selectBestCard()
        local bestIndex = 1
        local bestValue = 0

        for i, card in ipairs(self.hand) do
            local value = card.value or 0
            if value > bestValue then
                bestValue = value
                bestIndex = i
            end
        end

        return bestIndex
    end

    --- Select a card matching a specific suit
    -- @param suit number: Suit constant
    -- @return number|nil: Index of matching card, or nil
    function ai:selectCardBySuit(suit)
        for i, card in ipairs(self.hand) do
            if card.suit == suit then
                return i
            end
        end
        return nil
    end

    ----------------------------------------------------------------------------
    -- TARGET SELECTION
    ----------------------------------------------------------------------------

    --- Select the best target from available PCs
    -- Logic: Target PC with lowest current defense, preferring same zone
    -- @param npc table: The attacking NPC
    -- @param pcs table: Array of PC entities
    -- @param meleeOnly boolean: If true, only return targets in same zone
    -- @return table|nil: Target PC entity
    function ai:selectTarget(npc, pcs, meleeOnly)
        local validTargets = {}

        for _, pc in ipairs(pcs) do
            -- Skip defeated PCs
            if pc.conditions and pc.conditions.dead then
                goto continue
            end

            -- Check zone (for melee, must be in same zone)
            local inRange = (npc.zone == pc.zone)

            -- If meleeOnly, skip out-of-range targets
            if meleeOnly and not inRange then
                goto continue
            end

            validTargets[#validTargets + 1] = {
                pc = pc,
                inRange = inRange,
                defense = self:calculateDefense(pc),
            }

            ::continue::
        end

        if #validTargets == 0 then
            return nil
        end

        -- Sort by defense (lowest first)
        table.sort(validTargets, function(a, b)
            return a.defense < b.defense
        end)

        -- Prefer in-range targets
        for _, target in ipairs(validTargets) do
            if target.inRange then
                return target.pc
            end
        end

        -- Fall back to any target (only if not meleeOnly)
        if not meleeOnly then
            return validTargets[1].pc
        end

        return nil
    end

    --- Calculate a PC's current defense value
    function ai:calculateDefense(pc)
        local defense = 10

        -- Base defense from Pentacles
        defense = defense + (pc.pentacles or 0)

        -- Armor bonus
        if pc.armorNotches and pc.armorNotches > 0 then
            defense = defense + 2
        end

        -- Defensive stance
        if pc.conditions and pc.conditions.defending then
            defense = defense + 2
        end

        -- Wounded penalty
        if pc.conditions then
            if pc.conditions.staggered then
                defense = defense - 1
            end
            if pc.conditions.injured then
                defense = defense - 2
            end
            if pc.conditions.deaths_door then
                defense = defense - 4
            end
        end

        return defense
    end

    ----------------------------------------------------------------------------
    -- ACTION CREATION
    ----------------------------------------------------------------------------

    --- Create an attack action
    function ai:createAttackAction(npc, target, card)
        local action = {
            actor = npc,
            target = target,
            card = card,
            type = action_resolver.ACTION_TYPES.MELEE,
            weapon = npc.weapon,
            allEntities = self.challengeController and self.challengeController.allCombatants,
        }

        -- Check for mob rule bonuses
        local mobBonus = self:checkMobRule(npc, target)
        if mobBonus then
            action.mobRuleBonus = mobBonus
        end

        return action
    end

    --- Create a move action
    function ai:createMoveAction(npc, destinationZone, card)
        local action = {
            actor = npc,
            card = card,
            type = action_resolver.ACTION_TYPES.MOVE,
            destinationZone = destinationZone,
            allEntities = self.challengeController and self.challengeController.allCombatants,
        }
        return action
    end

    ----------------------------------------------------------------------------
    -- MOB RULE
    -- When multiple mobs are in the same zone, they gain bonuses
    ----------------------------------------------------------------------------

    --- Check for Mob Rule bonuses
    -- @param npc table: The attacking NPC
    -- @param target table: The target
    -- @return table|nil: Bonus info { favor, piercing }
    function ai:checkMobRule(npc, target)
        if not self.zoneSystem then
            return nil
        end

        -- Count other NPCs in the same zone as the target
        local alliesInZone = 0

        -- This would require access to all NPCs in the challenge
        -- For now, simplified implementation
        if self.challengeController then
            local npcs = self.challengeController.npcs or {}
            for _, otherNpc in ipairs(npcs) do
                if otherNpc ~= npc and otherNpc.zone == target.zone then
                    if not (otherNpc.conditions and otherNpc.conditions.dead) then
                        alliesInZone = alliesInZone + 1
                    end
                end
            end
        end

        if alliesInZone > 0 then
            return {
                favor = true,          -- Attack with Favor (advantage)
                piercing = alliesInZone >= 2,  -- Pierce armor if 2+ allies
                alliesCount = alliesInZone,
            }
        end

        return nil
    end

    ----------------------------------------------------------------------------
    -- SPECIAL AI BEHAVIORS
    ----------------------------------------------------------------------------

    --- Check if NPC should flee (low morale)
    function ai:shouldFlee(npc)
        if npc.morale and npc.morale <= 0 then
            return true
        end
        if npc.conditions and npc.conditions.fleeing then
            return true
        end
        return false
    end

    --- Check if NPC should use a special ability
    function ai:shouldUseSpecial(npc, pcs)
        -- Bosses with special abilities would check here
        if npc.specialAbility and npc.specialAbilityCooldown == 0 then
            -- 50% chance to use special
            return math.random() > 0.5
        end
        return false
    end

    return ai
end

return M

```

---

## File: src/logic/room_manager.lua

```lua
-- room_manager.lua
-- Room Manager for Majesty
-- Ticket T2_5: Logic for room state, features, and descriptions
--
-- Design: All data in blueprints/rooms.lua, all logic here.
-- Rooms can "remember" state changes (destroyed features, etc.)

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- ROOM INSTANCE FACTORY
-- Creates a mutable room instance from a blueprint
--------------------------------------------------------------------------------

--- Create a room instance from a blueprint
-- @param blueprint table: Room blueprint from rooms.lua
-- @param roomId string: Unique ID for this instance
-- @return RoomInstance
function M.createRoomInstance(blueprint, roomId)
    -- Deep copy features so each instance has mutable state
    local features = {}
    for i, feat in ipairs(blueprint.features or {}) do
        features[i] = {}
        for k, v in pairs(feat) do
            features[i][k] = v
        end
    end

    local instance = {
        id               = roomId,
        blueprintId      = blueprint.id,
        name             = blueprint.name,
        -- Support both base_description and description (tomb map uses description)
        base_description = blueprint.base_description or blueprint.description,
        description      = blueprint.description,
        danger_level     = blueprint.danger_level or 1,
        features         = features,
        verbs            = blueprint.verbs or {},
        meatgrinder_overrides = blueprint.meatgrinder_overrides or {},

        -- Runtime state
        mobs             = {},  -- Entity IDs of mobs currently in room
        visited          = false,
        discovered       = false,
    }

    return instance
end

--------------------------------------------------------------------------------
-- ROOM MANAGER FACTORY
--------------------------------------------------------------------------------

--- Create a new RoomManager
-- @param config table: { eventBus }
-- @return RoomManager instance
function M.createRoomManager(config)
    config = config or {}

    local manager = {
        rooms    = {},  -- roomId -> RoomInstance
        eventBus = config.eventBus or events.globalBus,
    }

    ----------------------------------------------------------------------------
    -- ROOM REGISTRATION
    ----------------------------------------------------------------------------

    --- Register a room instance
    function manager:registerRoom(roomInstance)
        self.rooms[roomInstance.id] = roomInstance
    end

    --- Get a room by ID
    function manager:getRoom(roomId)
        return self.rooms[roomId]
    end

    ----------------------------------------------------------------------------
    -- FEATURE MANAGEMENT
    ----------------------------------------------------------------------------

    --- Get a feature from a room
    function manager:getFeature(roomId, featureId)
        local room = self.rooms[roomId]
        if not room then return nil end

        for _, feat in ipairs(room.features) do
            if feat.id == featureId then
                return feat
            end
        end
        return nil
    end

    --- Update a feature's state
    function manager:setFeatureState(roomId, featureId, newState)
        local feature = self:getFeature(roomId, featureId)
        if feature then
            local oldState = feature.state
            feature.state = newState

            self.eventBus:emit(events.EVENTS.FEATURE_STATE_CHANGED, {
                roomId    = roomId,
                featureId = featureId,
                oldState  = oldState,
                newState  = newState,
            })

            return true
        end
        return false
    end

    --- Check if a feature is in a specific state
    function manager:isFeatureState(roomId, featureId, state)
        local feature = self:getFeature(roomId, featureId)
        return feature and feature.state == state
    end

    --- S11.3: Update arbitrary feature properties (for loot, flags, etc.)
    -- @param roomId string: Room containing the feature
    -- @param featureId string: Feature to update
    -- @param updates table: Key-value pairs to merge into feature
    -- @return boolean: success
    function manager:updateFeatureState(roomId, featureId, updates)
        local feature = self:getFeature(roomId, featureId)
        if not feature then
            return false
        end

        for key, value in pairs(updates) do
            feature[key] = value
        end

        self.eventBus:emit(events.EVENTS.FEATURE_UPDATED, {
            roomId = roomId,
            featureId = featureId,
            updates = updates,
        })

        return true
    end

    --- Get all features of a specific type in a room
    function manager:getFeaturesByType(roomId, featureType)
        local room = self.rooms[roomId]
        if not room then return {} end

        local result = {}
        for _, feat in ipairs(room.features) do
            if feat.type == featureType then
                result[#result + 1] = feat
            end
        end
        return result
    end

    --- Get all interactable features in a room
    function manager:getInteractableFeatures(roomId)
        local room = self.rooms[roomId]
        if not room then return {} end

        local result = {}
        for _, feat in ipairs(room.features) do
            -- Skip destroyed/removed features
            if feat.state ~= "destroyed" and feat.state ~= "removed" then
                result[#result + 1] = feat
            end
        end
        return result
    end

    ----------------------------------------------------------------------------
    -- MOB MANAGEMENT
    ----------------------------------------------------------------------------

    --- Add a mob to a room
    function manager:addMob(roomId, entityId)
        local room = self.rooms[roomId]
        if room then
            room.mobs[#room.mobs + 1] = entityId
        end
    end

    --- Remove a mob from a room
    function manager:removeMob(roomId, entityId)
        local room = self.rooms[roomId]
        if room then
            for i, id in ipairs(room.mobs) do
                if id == entityId then
                    table.remove(room.mobs, i)
                    return true
                end
            end
        end
        return false
    end

    --- Get all mobs in a room
    function manager:getMobs(roomId)
        local room = self.rooms[roomId]
        return room and room.mobs or {}
    end

    ----------------------------------------------------------------------------
    -- DESCRIPTION GENERATION
    -- Concatenates base text with active features and mobs
    ----------------------------------------------------------------------------

    --- Generate description for a feature based on its state
    local function describeFeature(feature)
        -- State-specific descriptions could be added here
        -- For now, return the base description
        if feature.state == "destroyed" then
            return "The remains of " .. (feature.name or "something") .. " lie scattered here."
        elseif feature.state == "hidden" then
            return nil  -- Hidden features aren't described
        else
            return feature.description
        end
    end

    --- Get full room description (base + features + mobs)
    -- @param roomId string
    -- @param context table: { entityRegistry, showHidden }
    -- @return string
    function manager:getDescription(roomId, context)
        context = context or {}
        local room = self.rooms[roomId]
        if not room then
            return "You see nothing remarkable."
        end

        local parts = { room.base_description }

        -- Add feature descriptions
        for _, feature in ipairs(room.features) do
            local showHidden = context.showHidden or false

            -- Skip hidden features unless explicitly shown
            if feature.state == "hidden" and not showHidden then
                -- Don't describe
            else
                local desc = describeFeature(feature)
                if desc then
                    parts[#parts + 1] = desc
                end
            end
        end

        -- Add mob descriptions (requires entity registry to look up names)
        if #room.mobs > 0 and context.entityRegistry then
            local mobNames = {}
            for _, entityId in ipairs(room.mobs) do
                local entity = context.entityRegistry:get(entityId)
                if entity then
                    mobNames[#mobNames + 1] = entity.name
                end
            end

            if #mobNames > 0 then
                if #mobNames == 1 then
                    parts[#parts + 1] = "A " .. mobNames[1] .. " lurks here."
                else
                    local list = table.concat(mobNames, ", ", 1, #mobNames - 1)
                    list = list .. " and " .. mobNames[#mobNames]
                    parts[#parts + 1] = list .. " lurk here."
                end
            end
        end

        return table.concat(parts, " ")
    end

    --- Get a short/glance description (just base text)
    function manager:getGlanceDescription(roomId)
        local room = self.rooms[roomId]
        if not room then
            return "A room."
        end
        return room.name .. ": " .. room.base_description
    end

    ----------------------------------------------------------------------------
    -- ROOM STATE
    ----------------------------------------------------------------------------

    --- Mark a room as visited
    function manager:markVisited(roomId)
        local room = self.rooms[roomId]
        if room then
            room.visited = true
            room.discovered = true
        end
    end

    --- Check if room has been visited
    function manager:isVisited(roomId)
        local room = self.rooms[roomId]
        return room and room.visited
    end

    --- Get room danger level
    function manager:getDangerLevel(roomId)
        local room = self.rooms[roomId]
        return room and room.danger_level or 1
    end

    ----------------------------------------------------------------------------
    -- MEATGRINDER INTEGRATION
    ----------------------------------------------------------------------------

    --- Get custom Meatgrinder entries for a room
    function manager:getMeatgrinderOverrides(roomId)
        local room = self.rooms[roomId]
        return room and room.meatgrinder_overrides or {}
    end

    --- Get room-specific verbs for Meatgrinder flavor
    function manager:getVerbs(roomId)
        local room = self.rooms[roomId]
        return room and room.verbs or {}
    end

    --- Pick a random verb for a category
    function manager:getRandomVerb(roomId, category)
        local verbs = self:getVerbs(roomId)
        local categoryVerbs = verbs[category]

        if categoryVerbs and #categoryVerbs > 0 then
            return categoryVerbs[math.random(#categoryVerbs)]
        end
        return nil
    end

    ----------------------------------------------------------------------------
    -- POI (POINT OF INTEREST) INFO-GATING (T2_8)
    -- Three layers: glance, scrutinize, investigate
    -- Scrutinize requires specific sub-verbs (feel, listen, look closely, etc.)
    ----------------------------------------------------------------------------

    -- Internal state for POI discovery
    local discoveredPOIs = {}      -- poi_id -> { layer -> revealed }
    local scrutinizeCount = 0      -- Track for time cost
    local SCRUTINIZE_TIME_COST = 3 -- Every N scrutinizes triggers Meatgrinder check

    --- Reset POI discovery state (call at start of new Crawl)
    function manager:resetPOIDiscovery()
        discoveredPOIs = {}
        scrutinizeCount = 0
    end

    --- Check if a POI layer has been discovered
    function manager:isPOIDiscovered(poiId, layer)
        if not discoveredPOIs[poiId] then
            return false
        end
        return discoveredPOIs[poiId][layer] or false
    end

    --- Mark a POI layer as discovered
    function manager:discoverPOI(poiId, layer)
        if not discoveredPOIs[poiId] then
            discoveredPOIs[poiId] = {}
        end
        discoveredPOIs[poiId][layer] = true

        self.eventBus:emit(events.EVENTS.POI_DISCOVERED, {
            poiId = poiId,
            layer = layer,
        })
    end

    --- Get valid sub-verbs for scrutinizing a POI
    -- @param poi table: The feature/POI to scrutinize
    -- @return table: Array of { verb, description }
    function manager:getScrutinyVerbs(poi)
        -- Default verbs based on POI type
        local defaultVerbs = {
            container   = { { verb = "feel", desc = "Feel for hidden compartments" }, { verb = "look", desc = "Look more closely" } },
            decoration  = { { verb = "examine", desc = "Examine the details" }, { verb = "feel", desc = "Feel the surface" } },
            mechanism   = { { verb = "listen", desc = "Listen for mechanisms" }, { verb = "feel", desc = "Feel for seams" } },
            corpse      = { { verb = "search", desc = "Search the remains" }, { verb = "examine", desc = "Examine for clues" } },
            hazard      = { { verb = "study", desc = "Study the hazard" }, { verb = "test", desc = "Test with a pole" } },
            door        = { { verb = "feel", desc = "Feel for drafts" }, { verb = "listen", desc = "Listen at the door" } },
            light       = { { verb = "examine", desc = "Examine the source" } },
            creature    = { { verb = "observe", desc = "Observe behavior" }, { verb = "listen", desc = "Listen carefully" } },
        }

        -- POI can define custom scrutiny verbs
        local verbs = {}
        if poi.scrutiny_verbs then
            for _, v in ipairs(poi.scrutiny_verbs) do
                verbs[#verbs + 1] = v
            end
        else
            local typeVerbs = defaultVerbs[poi.type] or { { verb = "examine", desc = "Look more closely" } }
            for _, v in ipairs(typeVerbs) do
                verbs[#verbs + 1] = v
            end
        end

        -- S11.3: Add "Search" verb for containers/corpses with loot
        if poi.loot and #poi.loot > 0 and poi.state ~= "empty" then
            -- Add search option at the beginning
            table.insert(verbs, 1, { verb = "search", desc = "Search for items" })
        end

        return verbs
    end

    --- Get POI info at a specific layer
    -- @param roomId string
    -- @param poiId string
    -- @param layer string: "glance", "scrutinize", or "investigate"
    -- @param subVerb string: For scrutinize, which verb is used (feel, listen, etc.)
    -- @return table: { text, revealed, subVerb, timeCostTriggered }
    function manager:getPOIInfo(roomId, poiId, layer, subVerb)
        local feature = self:getFeature(roomId, poiId)
        if not feature then
            return { text = "You see nothing there.", revealed = false }
        end

        local result = {
            text = "",
            revealed = false,
            timeCostTriggered = false,
        }

        -- GLANCE: Always available, just the basic description
        if layer == "glance" then
            result.text = feature.name or "Something."
            result.revealed = true
            return result
        end

        -- SCRUTINIZE: Requires saying HOW you're looking
        if layer == "scrutinize" then
            -- Increment scrutinize counter and check time cost
            scrutinizeCount = scrutinizeCount + 1
            if scrutinizeCount >= SCRUTINIZE_TIME_COST then
                scrutinizeCount = 0
                result.timeCostTriggered = true

                self.eventBus:emit(events.EVENTS.SCRUTINY_TIME_COST, {
                    roomId = roomId,
                    poiId = poiId,
                })
            end

            -- Check for verb-specific hidden info
            local hiddenKey = "scrutiny_" .. (subVerb or "examine")
            local hiddenInfo = feature[hiddenKey] or feature.hidden_description

            if hiddenInfo then
                result.text = hiddenInfo
                result.revealed = true
                self:discoverPOI(poiId, "scrutinize")
            else
                -- Generic scrutiny response
                result.text = feature.description or "You look more closely but find nothing unusual."
                result.revealed = true
            end

            return result
        end

        -- INVESTIGATE: May require a test, reveals secrets
        if layer == "investigate" then
            -- Check if already discovered at this level
            if self:isPOIDiscovered(poiId, "investigate") then
                result.text = feature.secrets or feature.investigate_description or "You've already thoroughly investigated this."
                result.revealed = true
                return result
            end

            -- Check if investigation requires a test
            if feature.investigate_test then
                result.requiresTest = true
                result.testConfig = feature.investigate_test
                result.text = "This requires careful investigation."
                return result
            end

            -- Reveal investigation info
            local investigateInfo = feature.secrets or feature.investigate_description
            if investigateInfo then
                result.text = investigateInfo
                result.revealed = true
                self:discoverPOI(poiId, "investigate")
            else
                result.text = "Your thorough investigation reveals nothing more."
                result.revealed = true
            end

            return result
        end

        return result
    end

    --- Get all discovered info for a POI (combines all revealed layers)
    function manager:getDiscoveredPOIInfo(roomId, poiId)
        local feature = self:getFeature(roomId, poiId)
        if not feature then
            return nil
        end

        local info = {
            id = poiId,
            name = feature.name,
            glance = feature.name,
            scrutinize = nil,
            investigate = nil,
        }

        if self:isPOIDiscovered(poiId, "scrutinize") then
            info.scrutinize = feature.hidden_description or feature.description
        end

        if self:isPOIDiscovered(poiId, "investigate") then
            info.investigate = feature.secrets or feature.investigate_description
        end

        return info
    end

    ----------------------------------------------------------------------------
    -- INVESTIGATION / TEST-OF-FATE BRIDGE (T2_9, T2_14)
    -- Connects the interaction system to the Tarot resolver
    -- Items can provide bonuses, auto-success, or take damage as proxy
    ----------------------------------------------------------------------------

    --- Conduct an investigation test on a POI
    -- @param adventurer table: The adventurer entity
    -- @param roomId string
    -- @param poiId string
    -- @param drawnCard table: The card drawn from the deck (nil if item auto-success)
    -- @param resolver table: The resolver module
    -- @param item table: Optional item being used for investigation
    -- @return table: { result, stateChange, trapTriggered, description, itemNotched, itemDestroyed }
    function manager:conductInvestigation(adventurer, roomId, poiId, drawnCard, resolver, item)
        local feature = self:getFeature(roomId, poiId)
        if not feature then
            return {
                result = nil,
                description = "There's nothing to investigate there.",
            }
        end

        local result = {
            result = nil,
            stateChange = nil,
            trapTriggered = false,
            itemNotched = false,
            itemDestroyed = false,
            description = "",
        }

        -- T2_14: Check for key_item_id automatic success
        -- If POI has a key_item_id and that item is used, skip test and succeed
        if item and feature.key_item_id then
            local itemKeyId = item.properties and item.properties.key_id
            if itemKeyId == feature.key_item_id or item.name == feature.key_item_id then
                -- Auto-success with the right item!
                self:discoverPOI(poiId, "investigate")

                result.result = { success = true, isGreat = false, total = 0, cards = {} }
                result.description = "The " .. item.name .. " works perfectly! " ..
                    (feature.secrets or feature.investigate_description or "Success!")

                -- Apply success state change
                local testConfig = feature.investigate_test or {}
                if testConfig.success_state then
                    self:setFeatureState(roomId, poiId, testConfig.success_state)
                    result.stateChange = testConfig.success_state
                end

                self.eventBus:emit(events.EVENTS.INVESTIGATION_COMPLETE, {
                    adventurer = adventurer.id,
                    roomId = roomId,
                    poiId = poiId,
                    result = result.result,
                    usedItem = item.id,
                    autoSuccess = true,
                })

                return result
            end
        end

        -- Determine test parameters from POI
        local testConfig = feature.investigate_test or {}
        local attribute = testConfig.attribute or "pentacles"
        local difficulty = testConfig.difficulty or 14

        -- Get adventurer's attribute value
        local constants = require('constants')
        local suitId = constants.SUITS[string.upper(attribute)] or constants.SUITS.PENTACLES
        local attributeValue = adventurer:getAttribute(suitId)

        -- Check favor/disfavor based on scrutiny
        local favor = nil
        if self:isPOIDiscovered(poiId, "scrutinize") then
            favor = nil  -- Neutral - they scrutinized first
        else
            favor = false  -- Disfavor - investigating blind
        end

        -- T2_14: Item provides favor bonus
        -- Certain items give favor when used appropriately
        if item then
            local itemBonus = self:getItemInvestigationBonus(item, feature)
            if itemBonus == "favor" then
                favor = true  -- Item grants favor
            elseif itemBonus == "negate_disfavor" and favor == false then
                favor = nil  -- Item negates disfavor from not scrutinizing
            end
        end

        -- Additional favor from adventurer motifs or abilities
        if testConfig.favor_condition then
            favor = testConfig.favor_condition(adventurer) or favor
        end

        -- Resolve the test
        local testResult = resolver.resolveTest(attributeValue, suitId, drawnCard, favor)
        result.result = testResult

        -- Handle results
        if testResult.success then
            -- Success! Reveal the secrets
            self:discoverPOI(poiId, "investigate")

            result.description = feature.secrets or feature.investigate_description or "You successfully investigate and find what you're looking for."

            -- Apply success state change
            if testConfig.success_state then
                self:setFeatureState(roomId, poiId, testConfig.success_state)
                result.stateChange = testConfig.success_state
            end

            -- Great Success bonus
            if testResult.isGreat then
                result.description = result.description .. " A great success!"
                if testConfig.great_success_bonus then
                    result.bonus = testConfig.great_success_bonus
                end
            end
        else
            -- Failure
            result.description = "Your investigation yields nothing."

            -- Check for Great Failure consequences
            if testResult.isGreat then
                result.description = "Your investigation goes terribly wrong!"

                -- T2_14: Item-as-proxy - item takes notch instead of wound
                if item and feature.trap then
                    local inventory = require('logic.inventory')
                    local notchResult = inventory.addNotch(item)

                    result.itemNotched = true
                    result.itemDestroyed = (notchResult == "destroyed")

                    if result.itemDestroyed then
                        result.description = "Your " .. item.name .. " takes the brunt of the trap and is destroyed!"
                    else
                        result.description = "Your " .. item.name .. " takes the brunt of the trap and is notched."
                    end

                    -- Trap was triggered but adventurer is safe
                    result.trapTriggered = true
                    result.trap = feature.trap
                    result.adventurerSafe = true

                    self.eventBus:emit(events.EVENTS.TRAP_TRIGGERED, {
                        roomId = roomId,
                        poiId = poiId,
                        trap = feature.trap,
                        adventurer = adventurer.id,
                        itemProxy = item.id,
                        adventurerSafe = true,
                    })
                elseif feature.trap then
                    -- No item to absorb damage - adventurer suffers
                    result.trapTriggered = true
                    result.trap = feature.trap

                    self.eventBus:emit(events.EVENTS.TRAP_TRIGGERED, {
                        roomId = roomId,
                        poiId = poiId,
                        trap = feature.trap,
                        adventurer = adventurer.id,
                    })

                    result.description = result.description .. " " .. (feature.trap.description or "A trap springs!")
                end

                -- Apply failure state change
                if testConfig.failure_state then
                    self:setFeatureState(roomId, poiId, testConfig.failure_state)
                    result.stateChange = testConfig.failure_state
                end

                -- Custom failure callback
                if testConfig.failure_callback then
                    testConfig.failure_callback(adventurer, feature, self)
                end
            end
        end

        -- Emit investigation event
        self.eventBus:emit(events.EVENTS.INVESTIGATION_COMPLETE, {
            adventurer = adventurer.id,
            roomId = roomId,
            poiId = poiId,
            result = testResult,
            trapTriggered = result.trapTriggered,
            usedItem = item and item.id or nil,
            itemNotched = result.itemNotched,
        })

        return result
    end

    --- Determine if an item provides a bonus for investigating a POI
    -- @param item table: The item being used
    -- @param poi table: The POI/feature
    -- @return string|nil: "favor", "negate_disfavor", or nil
    function manager:getItemInvestigationBonus(item, poi)
        -- Check for explicit item_bonuses in POI
        if poi.item_bonuses and poi.item_bonuses[item.name] then
            return poi.item_bonuses[item.name]
        end

        -- Generic item bonus rules
        local itemName = item.name:lower()

        -- Crowbar on locked things = favor
        if (itemName:find("crowbar") or itemName:find("prybar")) and
           (poi.type == "container" or poi.lock) then
            return "favor"
        end

        -- Lockpick on locks = favor
        if itemName:find("lockpick") and poi.lock then
            return "favor"
        end

        -- 10-foot pole on hazards/traps = negate disfavor (safer probing)
        if (itemName:find("pole") or itemName:find("staff")) and
           (poi.trap or poi.type == "hazard") then
            return "negate_disfavor"
        end

        -- Magnifying glass on scrutiny = favor
        if itemName:find("magnif") or itemName:find("lens") then
            return "favor"
        end

        return nil
    end

    --- Check if a POI requires an investigation test
    function manager:requiresInvestigationTest(roomId, poiId)
        local feature = self:getFeature(roomId, poiId)
        if not feature then
            return false
        end
        return feature.investigate_test ~= nil
    end

    --- Get investigation test details for UI
    function manager:getInvestigationTestInfo(roomId, poiId)
        local feature = self:getFeature(roomId, poiId)
        if not feature or not feature.investigate_test then
            return nil
        end

        local testConfig = feature.investigate_test
        return {
            attribute = testConfig.attribute or "pentacles",
            hasTrap = feature.trap ~= nil,
            trapDetected = feature.trap and feature.trap.detected,
            hasScrutinized = self:isPOIDiscovered(poiId, "scrutinize"),
        }
    end

    ----------------------------------------------------------------------------
    -- RESET (S10.1)
    ----------------------------------------------------------------------------

    --- Reset all rooms to initial state for a new expedition
    -- @param blueprints table: Original room blueprints to restore from
    function manager:reset(blueprints)
        -- Reset POI discovery state
        self:resetPOIDiscovery()

        -- Reset all rooms
        for roomId, room in pairs(self.rooms) do
            -- Clear visited/discovered flags
            room.visited = false
            room.discovered = false

            -- Clear mobs
            room.mobs = {}

            -- Reset features to initial state
            -- Find original blueprint if provided
            local blueprint = nil
            if blueprints then
                for _, bp in ipairs(blueprints) do
                    if bp.id == room.blueprintId or bp.id == roomId then
                        blueprint = bp
                        break
                    end
                end
            end

            -- Reset feature states
            for i, feature in ipairs(room.features) do
                -- Restore original state
                if blueprint and blueprint.features then
                    for _, origFeat in ipairs(blueprint.features) do
                        if origFeat.id == feature.id then
                            feature.state = origFeat.state or nil
                            break
                        end
                    end
                else
                    -- No blueprint - just clear state
                    feature.state = nil
                end

                -- Reset trap detection
                if feature.trap then
                    feature.trap.detected = false
                    feature.trap.disarmed = false
                end
            end
        end

        print("[ROOM_MANAGER] All rooms reset to initial state")
    end

    return manager
end

return M

```

---

## File: src/logic/watch_manager.lua

```lua
-- watch_manager.lua
-- Watch Manager & Movement Logic for Majesty
-- Ticket T2_2: Time tracking via Watches, triggers Meatgrinder
--
-- Design: Uses events for loose coupling. WatchManager fires events,
-- other systems (Light, Inventory) subscribe and respond.

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- MEATGRINDER RESULT CATEGORIES
-- Based on Major Arcana value (I-XXI)
--------------------------------------------------------------------------------
M.MEATGRINDER = {
    TORCHES_GUTTER   = "torches_gutter",    -- I-V (1-5)
    CURIOSITY        = "curiosity",          -- VI-X (6-10)
    TRAVEL_EVENT     = "travel_event",       -- XI-XV (11-15)
    RANDOM_ENCOUNTER = "random_encounter",   -- XVI-XX (16-20)
    QUEST_RUMOR      = "quest_rumor",        -- XXI (21)
}

--- Categorize a Major Arcana draw for Meatgrinder
-- @param cardValue number: The card's value (1-21)
-- @return string: One of MEATGRINDER categories
local function categorizeMeatgrinderDraw(cardValue)
    if cardValue >= 1 and cardValue <= 5 then
        return M.MEATGRINDER.TORCHES_GUTTER
    elseif cardValue >= 6 and cardValue <= 10 then
        return M.MEATGRINDER.CURIOSITY
    elseif cardValue >= 11 and cardValue <= 15 then
        return M.MEATGRINDER.TRAVEL_EVENT
    elseif cardValue >= 16 and cardValue <= 20 then
        return M.MEATGRINDER.RANDOM_ENCOUNTER
    elseif cardValue == 21 then
        return M.MEATGRINDER.QUEST_RUMOR
    end
    return nil
end

--------------------------------------------------------------------------------
-- WATCH MANAGER FACTORY
--------------------------------------------------------------------------------

--- Create a new WatchManager
-- @param config table: { gameClock, gmDeck, dungeon, guild, eventBus }
-- @return WatchManager instance
function M.createWatchManager(config)
    config = config or {}

    local manager = {
        gameClock   = config.gameClock,
        gmDeck      = config.gmDeck,
        dungeon     = config.dungeon,
        guild       = config.guild or {},      -- Array of adventurer entities
        eventBus    = config.eventBus or events.globalBus,
        watchCount  = 0,
        currentRoom = config.startingRoom or nil,
    }

    ----------------------------------------------------------------------------
    -- MEATGRINDER DRAW
    -- Draws from GM deck and categorizes result
    ----------------------------------------------------------------------------

    --- Draw from Meatgrinder (GM deck) and emit appropriate event
    -- @return table: { card, category, value }
    function manager:drawMeatgrinder()
        if not self.gmDeck then
            return nil
        end

        local card = self.gmDeck:draw()
        if not card then
            return nil
        end

        -- Notify GameClock about the draw (for Fool tracking)
        if self.gameClock and self.gameClock.onCardDrawn then
            self.gameClock:onCardDrawn(card)
        end

        local category = categorizeMeatgrinderDraw(card.value)

        local result = {
            card     = card,
            category = category,
            value    = card.value,
        }

        -- Emit the general meatgrinder event
        self.eventBus:emit(events.EVENTS.MEATGRINDER_ROLL, result)

        -- Emit category-specific event
        if category == M.MEATGRINDER.TORCHES_GUTTER then
            self.eventBus:emit(events.EVENTS.TORCHES_GUTTER, result)
        elseif category == M.MEATGRINDER.RANDOM_ENCOUNTER then
            self.eventBus:emit(events.EVENTS.RANDOM_ENCOUNTER, result)
        elseif category == M.MEATGRINDER.CURIOSITY then
            self.eventBus:emit(events.EVENTS.CURIOSITY, result)
        elseif category == M.MEATGRINDER.TRAVEL_EVENT then
            self.eventBus:emit(events.EVENTS.TRAVEL_EVENT, result)
        elseif category == M.MEATGRINDER.QUEST_RUMOR then
            self.eventBus:emit(events.EVENTS.QUEST_RUMOR, result)
        end

        -- Discard the card
        self.gmDeck:discard(card)

        return result
    end

    ----------------------------------------------------------------------------
    -- INCREMENT WATCH
    -- Called when time passes (movement, long tasks, phase changes)
    ----------------------------------------------------------------------------

    --- Increment the watch counter and trigger Meatgrinder
    -- @param options table: { careful = bool, loud = bool }
    -- @return table: { watchNumber, meatgrinderResults[] }
    function manager:incrementWatch(options)
        options = options or {}

        self.watchCount = self.watchCount + 1

        local results = {
            watchNumber        = self.watchCount,
            meatgrinderResults = {},
        }

        -- Draw from Meatgrinder
        local firstDraw = self:drawMeatgrinder()
        if firstDraw then
            results.meatgrinderResults[#results.meatgrinderResults + 1] = firstDraw
        end

        -- "Moving Carefully" (p. 91): Draw again, keep if torches gutter
        if options.careful and firstDraw then
            local secondDraw = self:drawMeatgrinder()
            if secondDraw then
                if secondDraw.category == M.MEATGRINDER.TORCHES_GUTTER then
                    -- Keep the torches gutter result
                    results.meatgrinderResults[#results.meatgrinderResults + 1] = secondDraw
                    results.carefulTorchesGutter = true
                end
                -- Otherwise second draw is ignored (but card was still drawn/discarded)
            end
        end

        -- Emit watch passed event
        self.eventBus:emit(events.EVENTS.WATCH_PASSED, {
            watchNumber = self.watchCount,
            careful     = options.careful or false,
            results     = results.meatgrinderResults,
        })

        return results
    end

    ----------------------------------------------------------------------------
    -- LOUD NOISE
    -- Special Meatgrinder check - only triggers on random encounter
    ----------------------------------------------------------------------------

    --- Check for encounters due to loud noise
    -- @return table: { triggered, result } - triggered is true if encounter occurs
    function manager:checkLoudNoise()
        local draw = self:drawMeatgrinder()

        if draw and draw.category == M.MEATGRINDER.RANDOM_ENCOUNTER then
            return { triggered = true, result = draw }
        end

        return { triggered = false, result = draw }
    end

    ----------------------------------------------------------------------------
    -- PARTY MOVEMENT
    -- Updates location of all guild members and advances watch
    ----------------------------------------------------------------------------

    --- Move the entire party to a new room
    -- @param targetRoomId string: The room to move to
    -- @param options table: { careful = bool }
    -- @return boolean, table: success, { watchResult, previousRoom, newRoom }
    function manager:moveParty(targetRoomId, options)
        options = options or {}

        if not self.dungeon then
            return false, { error = "no_dungeon" }
        end

        local targetRoom = self.dungeon:getRoom(targetRoomId)
        if not targetRoom then
            return false, { error = "room_not_found" }
        end

        -- Check if movement is valid (room is adjacent and accessible)
        if self.currentRoom then
            local connection = self.dungeon:getConnection(self.currentRoom, targetRoomId)
            if not connection then
                return false, { error = "no_connection" }
            end
            if connection.is_locked then
                return false, { error = "connection_locked" }
            end
            if connection.is_secret and not connection.discovered then
                return false, { error = "connection_secret" }
            end
        end

        local previousRoom = self.currentRoom

        -- Update party location
        self.currentRoom = targetRoomId

        -- Update each guild member's location
        for _, member in ipairs(self.guild) do
            member.location = targetRoomId
        end

        -- Emit room entered event
        self.eventBus:emit(events.EVENTS.ROOM_ENTERED, {
            roomId   = targetRoomId,
            room     = targetRoom,
            previous = previousRoom,
        })

        -- Increment the watch (triggers Meatgrinder)
        local watchResult = self:incrementWatch({ careful = options.careful })

        -- Emit party moved event
        self.eventBus:emit(events.EVENTS.PARTY_MOVED, {
            from        = previousRoom,
            to          = targetRoomId,
            watchNumber = watchResult.watchNumber,
        })

        return true, {
            watchResult  = watchResult,
            previousRoom = previousRoom,
            newRoom      = targetRoomId,
        }
    end

    ----------------------------------------------------------------------------
    -- UTILITY
    ----------------------------------------------------------------------------

    --- Get current watch count
    function manager:getWatchCount()
        return self.watchCount
    end

    --- Get current room
    function manager:getCurrentRoom()
        return self.currentRoom
    end

    --- Set guild members
    function manager:setGuild(guildMembers)
        self.guild = guildMembers
        return self
    end

    --- Add a member to the guild
    function manager:addGuildMember(entity)
        self.guild[#self.guild + 1] = entity
        entity.location = self.currentRoom
        return self
    end

    return manager
end

return M

```

---

## File: src/ui/action_sequencer.lua

```lua
-- action_sequencer.lua
-- Visual Action Sequencer for Majesty
-- Ticket S4.2: Converts logic events into visual timelines
--
-- IMPORTANT: Uses dt-based timers in update(), NOT love.timer.sleep()!
-- sleep() would freeze the entire application.
--
-- Sequence flow:
-- 1. Logic emits CHALLENGE_ACTION / CHALLENGE_RESOLUTION
-- 2. Sequencer queues visual steps: card_slap -> math_overlay -> damage_result
-- 3. Each step has a duration, when done -> next step
-- 4. When all steps done -> emit UI_SEQUENCE_COMPLETE

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- ANIMATION STEP TYPES
--------------------------------------------------------------------------------
M.STEP_TYPES = {
    CARD_SLAP      = "card_slap",       -- Show the card being played
    MATH_OVERLAY   = "math_overlay",    -- Show the calculation (e.g., "7 + 2 = 9")
    DAMAGE_RESULT  = "damage_result",   -- Show the outcome (hit/miss/wound)
    WOUND_WALK     = "wound_walk",      -- Show defense layers being checked
    TEXT_POPUP     = "text_popup",      -- Generic text display
    ENTITY_SHAKE   = "entity_shake",    -- Shake an entity portrait
    FLASH          = "flash",           -- Flash a UI element
    DELAY          = "delay",           -- Simple pause
}

--------------------------------------------------------------------------------
-- DEFAULT DURATIONS (in seconds)
--------------------------------------------------------------------------------
M.DURATIONS = {
    card_slap      = 0.6,
    math_overlay   = 0.5,
    damage_result  = 0.5,
    wound_walk     = 0.8,
    text_popup     = 0.7,
    entity_shake   = 0.3,
    flash          = 0.2,
    delay          = 0.3,
}

--------------------------------------------------------------------------------
-- ACTION SEQUENCER FACTORY
--------------------------------------------------------------------------------

--- Create a new ActionSequencer
-- @param config table: { eventBus }
-- @return ActionSequencer instance
function M.createActionSequencer(config)
    config = config or {}

    local sequencer = {
        eventBus = config.eventBus or events.globalBus,

        -- Queue of pending sequences
        -- Each sequence is an array of steps
        sequenceQueue = {},

        -- Current sequence being played
        currentSequence = nil,
        currentStepIndex = 0,
        currentStep = nil,

        -- Timing
        stepTimer = 0,
        stepDuration = 0,

        -- State
        playing = false,
        isPaused = false,

        -- Visual state for rendering
        activeVisuals = {},  -- { type, data, progress }

        -- Callbacks for custom rendering
        onStepStart = nil,   -- function(step)
        onStepEnd = nil,     -- function(step)
        onSequenceComplete = nil,  -- function(sequence)
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    --- Initialize and subscribe to events
    function sequencer:init()
        -- Listen for challenge actions to visualize
        self.eventBus:on(events.EVENTS.CHALLENGE_RESOLUTION, function(data)
            self:queueActionSequence(data)
        end)

        -- Listen for wound events to visualize
        self.eventBus:on(events.EVENTS.WOUND_TAKEN, function(data)
            self:queueWoundSequence(data)
        end)
    end

    ----------------------------------------------------------------------------
    -- QUEUE MANAGEMENT
    ----------------------------------------------------------------------------

    --- Queue a generic sequence of steps
    -- @param steps table: Array of { type, duration, data }
    function sequencer:push(steps)
        if not steps or #steps == 0 then
            return
        end

        -- Normalize steps (add default durations if missing)
        for _, step in ipairs(steps) do
            if not step.duration then
                step.duration = M.DURATIONS[step.type] or 0.5
            end
        end

        self.sequenceQueue[#self.sequenceQueue + 1] = steps

        -- Start playing if not already
        if not self.playing then
            self:startNextSequence()
        end
    end

    --- Queue a single step
    function sequencer:pushStep(stepType, data, duration)
        self:push({
            {
                type = stepType,
                data = data or {},
                duration = duration or M.DURATIONS[stepType] or 0.5,
            }
        })
    end

    --- Queue a standard action sequence (card -> math -> result)
    function sequencer:queueActionSequence(resolutionData)
        local action = resolutionData.action or {}
        local result = resolutionData.result or {}

        local steps = {}

        -- Step 1: Card slap (if a card was played)
        if action.card then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.CARD_SLAP,
                data = {
                    card = action.card,
                    actor = action.actor,
                    target = action.target,
                },
            }
        end

        -- Step 2: Math overlay (show the test calculation)
        if result.testValue or result.difficulty then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.MATH_OVERLAY,
                data = {
                    cardValue = result.cardValue or (action.card and action.card.value),
                    modifier = result.modifier or 0,
                    total = result.testValue,
                    difficulty = result.difficulty,
                    success = result.success,
                    isGreat = result.isGreat,
                },
            }
        end

        -- Step 3: Damage result (if damage was dealt)
        if result.damageDealt or result.success ~= nil then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.DAMAGE_RESULT,
                data = {
                    success = result.success,
                    damageDealt = result.damageDealt or 0,
                    target = action.target,
                    description = result.description,
                    isGreat = result.isGreat,
                },
            }
        end

        if #steps > 0 then
            self:push(steps)
        else
            -- No steps to show, emit complete immediately
            self:emitComplete()
        end
    end

    --- Queue a wound visualization sequence
    function sequencer:queueWoundSequence(woundData)
        local steps = {
            {
                type = M.STEP_TYPES.WOUND_WALK,
                data = {
                    entity = woundData.entity,
                    armorAbsorbed = woundData.armorAbsorbed,
                    talentAbsorbed = woundData.talentAbsorbed,
                    conditionApplied = woundData.conditionApplied,
                    finalResult = woundData.finalResult,
                },
                duration = M.DURATIONS.wound_walk,
            }
        }
        self:push(steps)
    end

    ----------------------------------------------------------------------------
    -- PLAYBACK CONTROL
    ----------------------------------------------------------------------------

    --- Start playing the next sequence in queue
    function sequencer:startNextSequence()
        if #self.sequenceQueue == 0 then
            self.playing = false
            self.currentSequence = nil
            self.currentStep = nil
            self.activeVisuals = {}
            return
        end

        self.currentSequence = table.remove(self.sequenceQueue, 1)
        self.currentStepIndex = 0
        self.playing = true

        self:advanceStep()
    end

    --- Advance to the next step in current sequence
    function sequencer:advanceStep()
        if not self.currentSequence then
            self:startNextSequence()
            return
        end

        -- Call onStepEnd for previous step
        if self.currentStep and self.onStepEnd then
            self.onStepEnd(self.currentStep)
        end

        self.currentStepIndex = self.currentStepIndex + 1

        if self.currentStepIndex > #self.currentSequence then
            -- Sequence complete
            self:completeSequence()
            return
        end

        -- Start next step
        self.currentStep = self.currentSequence[self.currentStepIndex]
        self.stepTimer = 0
        self.stepDuration = self.currentStep.duration

        -- Set up active visual
        self.activeVisuals = {
            {
                type = self.currentStep.type,
                data = self.currentStep.data,
                progress = 0,
            }
        }

        -- Call onStepStart callback
        if self.onStepStart then
            self.onStepStart(self.currentStep)
        end

        -- Emit step event for UI
        self.eventBus:emit("action_step_start", {
            step = self.currentStep,
            stepIndex = self.currentStepIndex,
            totalSteps = #self.currentSequence,
        })
    end

    --- Complete the current sequence
    function sequencer:completeSequence()
        local completedSequence = self.currentSequence

        -- Call callback
        if self.onSequenceComplete then
            self.onSequenceComplete(completedSequence)
        end

        self.currentSequence = nil
        self.currentStep = nil
        self.activeVisuals = {}

        -- Emit completion event for challenge controller
        self:emitComplete()

        -- Start next sequence if any
        self:startNextSequence()
    end

    --- Emit the UI_SEQUENCE_COMPLETE event
    function sequencer:emitComplete()
        self.eventBus:emit(events.EVENTS.UI_SEQUENCE_COMPLETE, {
            timestamp = love and love.timer.getTime() or os.time(),
        })
    end

    --- Pause playback
    function sequencer:pause()
        self.isPaused = true
    end

    --- Resume playback
    function sequencer:resume()
        self.isPaused = false
    end

    --- Skip current sequence (for impatient players)
    function sequencer:skip()
        if self.currentSequence then
            self:completeSequence()
        end
    end

    --- Clear all pending sequences
    function sequencer:clear()
        self.sequenceQueue = {}
        self.currentSequence = nil
        self.currentStep = nil
        self.currentStepIndex = 0
        self.playing = false
        self.activeVisuals = {}
    end

    ----------------------------------------------------------------------------
    -- UPDATE (call from love.update)
    ----------------------------------------------------------------------------

    --- Update the sequencer (MUST be called every frame)
    -- @param dt number: Delta time in seconds
    function sequencer:update(dt)
        if not self.playing or self.isPaused then
            return
        end

        if not self.currentStep then
            return
        end

        -- Advance timer
        self.stepTimer = self.stepTimer + dt

        -- Update progress for active visuals
        for _, visual in ipairs(self.activeVisuals) do
            if self.stepDuration > 0 then
                visual.progress = math.min(1, self.stepTimer / self.stepDuration)
            else
                visual.progress = 1
            end
        end

        -- Check if step is complete
        if self.stepTimer >= self.stepDuration then
            self:advanceStep()
        end
    end

    ----------------------------------------------------------------------------
    -- RENDERING HELPERS
    ----------------------------------------------------------------------------

    --- Get current active visuals for rendering
    -- @return table: Array of { type, data, progress }
    function sequencer:getActiveVisuals()
        return self.activeVisuals
    end

    --- Check if a specific visual type is active
    function sequencer:isVisualActive(visualType)
        for _, visual in ipairs(self.activeVisuals) do
            if visual.type == visualType then
                return true, visual
            end
        end
        return false
    end

    --- Get current step progress (0 to 1)
    function sequencer:getProgress()
        if self.stepDuration > 0 then
            return math.min(1, self.stepTimer / self.stepDuration)
        end
        return 1
    end

    ----------------------------------------------------------------------------
    -- QUERIES
    ----------------------------------------------------------------------------

    function sequencer:isPlaying()
        return self.playing == true
    end

    function sequencer:getQueueLength()
        return #self.sequenceQueue
    end

    function sequencer:getCurrentStep()
        return self.currentStep
    end

    return sequencer
end

return M

```

---

## File: src/ui/arena_view.lua

```lua
-- arena_view.lua
-- Arena Vellum (Tactical Schematic) for Majesty
-- Ticket S6.1: Zone-based battle map with tactical tokens
--
-- Replaces the narrative text view during challenges with a schematic
-- showing zone buckets and entity positions.

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- COLORS
--------------------------------------------------------------------------------
M.COLORS = {
    -- Zone buckets
    zone_bg         = { 0.85, 0.80, 0.70, 0.6 },    -- Parchment tint
    zone_border     = { 0.35, 0.30, 0.25, 1.0 },    -- Dark ink
    zone_active     = { 0.90, 0.80, 0.30, 0.3 },    -- Gold highlight for active zone
    zone_hover      = { 0.70, 0.85, 0.70, 0.3 },    -- Green for valid drop target

    -- Zone labels
    label_bg        = { 0.25, 0.22, 0.18, 0.9 },
    label_text      = { 0.90, 0.85, 0.75, 1.0 },

    -- Tactical tokens
    token_pc        = { 0.25, 0.45, 0.35, 1.0 },    -- Green for PCs
    token_npc       = { 0.55, 0.25, 0.25, 1.0 },    -- Red for NPCs
    token_border    = { 0.15, 0.12, 0.10, 1.0 },
    token_active    = { 0.95, 0.85, 0.30, 1.0 },    -- Gold ring for active entity
    token_text      = { 0.95, 0.92, 0.88, 1.0 },

    -- Engagement
    clash_line      = { 0.80, 0.30, 0.20, 0.8 },    -- Red line
    clash_icon      = { 0.90, 0.40, 0.30, 1.0 },    -- Clash icon

    -- Drag ghost
    drag_ghost      = { 1.0, 1.0, 1.0, 0.5 },

    -- S10.2: Targeting reticle
    target_reticle  = { 0.95, 0.35, 0.25, 0.9 },    -- Red targeting
    target_valid    = { 0.35, 0.85, 0.35, 0.9 },    -- Green for valid target
    target_invalid  = { 0.60, 0.60, 0.60, 0.5 },    -- Grey for invalid
}

--------------------------------------------------------------------------------
-- LAYOUT CONSTANTS
--------------------------------------------------------------------------------
M.TOKEN_SIZE = 40
M.TOKEN_SPACING = 8
M.ZONE_PADDING = 15
M.ZONE_LABEL_HEIGHT = 24
M.ZONE_MIN_WIDTH = 150
M.ZONE_MIN_HEIGHT = 120

--------------------------------------------------------------------------------
-- ARENA VIEW FACTORY
--------------------------------------------------------------------------------

--- Create a new ArenaView
-- @param config table: { eventBus, x, y, width, height }
-- @return ArenaView instance
function M.createArenaView(config)
    config = config or {}

    local arena = {
        eventBus = config.eventBus or events.globalBus,

        -- Position and size
        x = config.x or 0,
        y = config.y or 0,
        width = config.width or 600,
        height = config.height or 500,

        -- State
        isVisible = false,
        roomData = nil,
        zones = {},              -- { id -> { x, y, width, height, name, entities } }
        entities = {},           -- All entities in the arena
        engagements = {},        -- { [entityId1..entityId2] -> true }

        -- Interaction
        hoveredZone = nil,
        hoveredEntity = nil,     -- S10.2: Entity under mouse
        draggedEntity = nil,
        dragOffsetX = 0,
        dragOffsetY = 0,

        -- Active entity highlight
        activeEntityId = nil,

        -- S10.2: Targeting mode
        targetingMode = false,
        validTargets = {},       -- Array of valid target entity IDs
        targetReticleTimer = 0,  -- For animation

        colors = M.COLORS,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function arena:init()
        -- Listen for challenge start
        self.eventBus:on(events.EVENTS.CHALLENGE_START, function(data)
            self:setupArena(data)
        end)

        -- Listen for challenge end
        self.eventBus:on(events.EVENTS.CHALLENGE_END, function(data)
            self:hide()
        end)

        -- Listen for turn changes to highlight active entity
        self.eventBus:on(events.EVENTS.CHALLENGE_TURN_START, function(data)
            if data.activeEntity then
                self.activeEntityId = data.activeEntity.id
            end
        end)

        -- Listen for engagement changes
        self.eventBus:on("engagement_formed", function(data)
            self:addEngagement(data.entity1, data.entity2)
        end)

        self.eventBus:on("engagement_broken", function(data)
            self:removeEngagement(data.entity1, data.entity2)
        end)

        -- Listen for zone changes (from action resolver)
        self.eventBus:on("entity_zone_changed", function(data)
            if data.entity and data.newZone then
                self:syncEntityZone(data.entity, data.newZone)
            end
        end)
    end

    ----------------------------------------------------------------------------
    -- ARENA SETUP
    ----------------------------------------------------------------------------

    --- Set up the arena for a challenge
    function arena:setupArena(challengeData)
        self.isVisible = true
        self.entities = {}
        self.engagements = {}
        self.zones = {}

        -- Get room data for zones
        local roomId = challengeData.roomId
        -- For now, create default zones if room data doesn't have them
        local zoneData = challengeData.zones or self:getDefaultZones()

        -- Calculate zone layout
        self:layoutZones(zoneData)

        -- Add combatants
        local allCombatants = {}
        for _, pc in ipairs(challengeData.pcs or {}) do
            allCombatants[#allCombatants + 1] = pc
        end
        for _, npc in ipairs(challengeData.npcs or {}) do
            allCombatants[#allCombatants + 1] = npc
        end

        -- Place entities in zones
        for _, entity in ipairs(allCombatants) do
            local zoneId = entity.zone or "main"
            self:addEntity(entity, zoneId)
        end

        self.eventBus:emit("arena_ready", { zones = self.zones })
    end

    --- Get default zones if room doesn't specify any
    function arena:getDefaultZones()
        return {
            { id = "main", name = "Battlefield" },
        }
    end

    --- Calculate zone bucket layout
    function arena:layoutZones(zoneData)
        local numZones = #zoneData
        if numZones == 0 then
            numZones = 1
            zoneData = self:getDefaultZones()
        end

        -- Calculate grid layout (prefer horizontal arrangement)
        local cols, rows
        if numZones <= 2 then
            cols, rows = numZones, 1
        elseif numZones <= 4 then
            cols, rows = 2, 2
        elseif numZones <= 6 then
            cols, rows = 3, 2
        else
            cols = math.ceil(math.sqrt(numZones))
            rows = math.ceil(numZones / cols)
        end

        local zoneWidth = math.max(M.ZONE_MIN_WIDTH, (self.width - M.ZONE_PADDING * (cols + 1)) / cols)
        local zoneHeight = math.max(M.ZONE_MIN_HEIGHT, (self.height - M.ZONE_PADDING * (rows + 1)) / rows)

        -- Create zone buckets
        local idx = 1
        for row = 1, rows do
            for col = 1, cols do
                if idx <= numZones then
                    local zd = zoneData[idx]
                    local zx = self.x + M.ZONE_PADDING + (col - 1) * (zoneWidth + M.ZONE_PADDING)
                    local zy = self.y + M.ZONE_PADDING + (row - 1) * (zoneHeight + M.ZONE_PADDING)

                    self.zones[zd.id] = {
                        id = zd.id,
                        name = zd.name or zd.id,
                        description = zd.description,
                        x = zx,
                        y = zy,
                        width = zoneWidth,
                        height = zoneHeight,
                        entities = {},
                    }
                    idx = idx + 1
                end
            end
        end
    end

    ----------------------------------------------------------------------------
    -- ENTITY MANAGEMENT
    ----------------------------------------------------------------------------

    --- Add an entity to a zone
    function arena:addEntity(entity, zoneId)
        zoneId = zoneId or "main"

        -- Ensure zone exists
        if not self.zones[zoneId] then
            zoneId = next(self.zones) -- Use first available zone
        end

        if not self.zones[zoneId] then
            return -- No zones available
        end

        -- Store entity reference
        self.entities[entity.id] = {
            entity = entity,
            zoneId = zoneId,
        }

        -- Add to zone's entity list
        local zone = self.zones[zoneId]
        zone.entities[#zone.entities + 1] = entity

        -- Update entity's zone property
        entity.zone = zoneId
    end

    --- Move an entity to a different zone
    function arena:moveEntity(entity, newZoneId)
        local entityData = self.entities[entity.id]
        if not entityData then return false end

        local oldZoneId = entityData.zoneId
        local oldZone = self.zones[oldZoneId]
        local newZone = self.zones[newZoneId]

        if not newZone then return false end

        -- Remove from old zone
        if oldZone then
            for i, e in ipairs(oldZone.entities) do
                if e.id == entity.id then
                    table.remove(oldZone.entities, i)
                    break
                end
            end
        end

        -- Add to new zone
        newZone.entities[#newZone.entities + 1] = entity
        entityData.zoneId = newZoneId
        entity.zone = newZoneId

        -- Emit event
        self.eventBus:emit("entity_zone_changed", {
            entity = entity,
            oldZone = oldZoneId,
            newZone = newZoneId,
        })

        return true
    end

    --- Sync entity zone from external changes (e.g., action resolver)
    -- Updates internal tracking when entity.zone is changed externally
    function arena:syncEntityZone(entity, newZoneId)
        local entityData = self.entities[entity.id]
        if not entityData then return false end

        local oldZoneId = entityData.zoneId
        if oldZoneId == newZoneId then return true end  -- Already in sync

        local oldZone = self.zones[oldZoneId]
        local newZone = self.zones[newZoneId]

        if not newZone then return false end

        -- Remove from old zone
        if oldZone then
            for i, e in ipairs(oldZone.entities) do
                if e.id == entity.id then
                    table.remove(oldZone.entities, i)
                    break
                end
            end
        end

        -- Add to new zone
        newZone.entities[#newZone.entities + 1] = entity
        entityData.zoneId = newZoneId

        return true
    end

    ----------------------------------------------------------------------------
    -- ENGAGEMENT
    ----------------------------------------------------------------------------

    --- Add engagement between two entities
    function arena:addEngagement(entity1, entity2)
        local key = self:engagementKey(entity1, entity2)
        self.engagements[key] = true
    end

    --- Remove engagement between two entities
    function arena:removeEngagement(entity1, entity2)
        local key = self:engagementKey(entity1, entity2)
        self.engagements[key] = nil
    end

    --- Check if two entities are engaged
    function arena:areEngaged(entity1, entity2)
        local key = self:engagementKey(entity1, entity2)
        return self.engagements[key] == true
    end

    --- Generate a consistent key for an engagement pair
    function arena:engagementKey(entity1, entity2)
        local id1 = entity1.id or tostring(entity1)
        local id2 = entity2.id or tostring(entity2)
        if id1 < id2 then
            return id1 .. "_" .. id2
        else
            return id2 .. "_" .. id1
        end
    end

    ----------------------------------------------------------------------------
    -- VISIBILITY
    ----------------------------------------------------------------------------

    function arena:show()
        self.isVisible = true
    end

    function arena:hide()
        self.isVisible = false
        self.zones = {}
        self.entities = {}
        self.engagements = {}
        self.activeEntityId = nil
    end

    function arena:setPosition(x, y)
        self.x = x
        self.y = y
        -- Recalculate zone positions
        if self.roomData then
            self:layoutZones(self.roomData.zones or self:getDefaultZones())
        end
    end

    function arena:resize(width, height)
        self.width = width
        self.height = height
        -- Recalculate zone positions
        if next(self.zones) then
            local zoneData = {}
            for _, zone in pairs(self.zones) do
                zoneData[#zoneData + 1] = { id = zone.id, name = zone.name, description = zone.description }
            end
            self:layoutZones(zoneData)
        end
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function arena:update(dt)
        -- S10.2: Update targeting reticle animation
        if self.targetingMode then
            self.targetReticleTimer = self.targetReticleTimer + dt
        end
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    ----------------------------------------------------------------------------

    function arena:draw()
        if not love or not self.isVisible then return end

        -- Draw zone buckets
        for _, zone in pairs(self.zones) do
            self:drawZone(zone)
        end

        -- Draw engagement lines
        self:drawEngagements()

        -- S10.2: Draw targeting indicators (behind tokens)
        if self.targetingMode then
            self:drawTargetingIndicators()
        end

        -- Draw entity tokens
        for _, zone in pairs(self.zones) do
            self:drawZoneEntities(zone)
        end

        -- Draw drag ghost
        if self.draggedEntity then
            self:drawDragGhost()
        end
    end

    --- Draw a zone bucket
    function arena:drawZone(zone)
        local colors = self.colors
        local isHovered = (self.hoveredZone == zone.id)
        local hasActiveEntity = false

        -- Check if active entity is in this zone
        for _, entity in ipairs(zone.entities) do
            if entity.id == self.activeEntityId then
                hasActiveEntity = true
                break
            end
        end

        -- Background
        if hasActiveEntity then
            love.graphics.setColor(colors.zone_active)
        elseif isHovered and self.draggedEntity then
            love.graphics.setColor(colors.zone_hover)
        else
            love.graphics.setColor(colors.zone_bg)
        end
        love.graphics.rectangle("fill", zone.x, zone.y, zone.width, zone.height, 6, 6)

        -- Border
        love.graphics.setColor(colors.zone_border)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", zone.x, zone.y, zone.width, zone.height, 6, 6)
        love.graphics.setLineWidth(1)

        -- Label
        self:drawZoneLabel(zone)
    end

    --- Draw zone label
    function arena:drawZoneLabel(zone)
        local colors = self.colors
        local labelWidth = math.min(zone.width - 20, 120)
        local labelX = zone.x + (zone.width - labelWidth) / 2
        local labelY = zone.y + 5

        -- Label background
        love.graphics.setColor(colors.label_bg)
        love.graphics.rectangle("fill", labelX, labelY, labelWidth, M.ZONE_LABEL_HEIGHT, 3, 3)

        -- Label text
        love.graphics.setColor(colors.label_text)
        love.graphics.printf(zone.name, labelX, labelY + 4, labelWidth, "center")
    end

    --- Draw entities in a zone
    function arena:drawZoneEntities(zone)
        local tokenSize = M.TOKEN_SIZE
        local spacing = M.TOKEN_SPACING
        local startY = zone.y + M.ZONE_LABEL_HEIGHT + 15
        local contentWidth = zone.width - M.ZONE_PADDING * 2
        local contentX = zone.x + M.ZONE_PADDING

        -- Calculate grid layout for tokens
        local tokensPerRow = math.max(1, math.floor(contentWidth / (tokenSize + spacing)))

        for i, entity in ipairs(zone.entities) do
            local row = math.floor((i - 1) / tokensPerRow)
            local col = (i - 1) % tokensPerRow

            local tokenX = contentX + col * (tokenSize + spacing)
            local tokenY = startY + row * (tokenSize + spacing)

            -- Store token position for hit detection
            entity._tokenX = tokenX
            entity._tokenY = tokenY

            -- Draw token (skip if being dragged)
            if self.draggedEntity ~= entity then
                self:drawToken(entity, tokenX, tokenY, tokenSize)
            end
        end
    end

    --- Draw a tactical token
    function arena:drawToken(entity, x, y, size)
        local colors = self.colors
        local isPC = entity.isPC
        local isActive = (entity.id == self.activeEntityId)
        local isDead = entity.conditions and entity.conditions.dead

        -- Active glow
        if isActive then
            love.graphics.setColor(colors.token_active)
            love.graphics.circle("fill", x + size/2, y + size/2, size/2 + 4)
        end

        -- Token background
        if isDead then
            love.graphics.setColor(0.3, 0.3, 0.3, 0.7)
        elseif isPC then
            love.graphics.setColor(colors.token_pc)
        else
            love.graphics.setColor(colors.token_npc)
        end
        love.graphics.circle("fill", x + size/2, y + size/2, size/2)

        -- Border
        love.graphics.setColor(colors.token_border)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", x + size/2, y + size/2, size/2)
        love.graphics.setLineWidth(1)

        -- Initials or short name
        local initials = self:getInitials(entity.name or "??")
        love.graphics.setColor(colors.token_text)
        love.graphics.printf(initials, x, y + size/2 - 8, size, "center")

        -- Dead X
        if isDead then
            love.graphics.setColor(0.8, 0.2, 0.2, 0.9)
            love.graphics.setLineWidth(3)
            love.graphics.line(x + 5, y + 5, x + size - 5, y + size - 5)
            love.graphics.line(x + size - 5, y + 5, x + 5, y + size - 5)
            love.graphics.setLineWidth(1)
        end
    end

    --- Get initials from a name
    function arena:getInitials(name)
        local words = {}
        for word in name:gmatch("%S+") do
            words[#words + 1] = word
        end

        if #words >= 2 then
            return words[1]:sub(1, 1):upper() .. words[2]:sub(1, 1):upper()
        else
            return name:sub(1, 2):upper()
        end
    end

    --- Draw engagement lines between engaged entities
    function arena:drawEngagements()
        local colors = self.colors

        for key, _ in pairs(self.engagements) do
            -- Parse key to get entity IDs
            local id1, id2 = key:match("(.+)_(.+)")
            local data1 = self.entities[id1]
            local data2 = self.entities[id2]

            if data1 and data2 then
                local e1 = data1.entity
                local e2 = data2.entity

                -- Only draw if both have valid positions
                if e1._tokenX and e2._tokenX then
                    local x1 = e1._tokenX + M.TOKEN_SIZE / 2
                    local y1 = e1._tokenY + M.TOKEN_SIZE / 2
                    local x2 = e2._tokenX + M.TOKEN_SIZE / 2
                    local y2 = e2._tokenY + M.TOKEN_SIZE / 2

                    -- Draw clash line
                    love.graphics.setColor(colors.clash_line)
                    love.graphics.setLineWidth(3)
                    love.graphics.line(x1, y1, x2, y2)

                    -- Draw clash icon at midpoint
                    local midX = (x1 + x2) / 2
                    local midY = (y1 + y2) / 2

                    love.graphics.setColor(colors.clash_icon)
                    love.graphics.circle("fill", midX, midY, 8)
                    love.graphics.setColor(colors.token_border)
                    love.graphics.setLineWidth(2)
                    love.graphics.circle("line", midX, midY, 8)

                    -- Crossed swords icon (simplified)
                    love.graphics.setColor(1, 1, 1, 1)
                    love.graphics.line(midX - 4, midY - 4, midX + 4, midY + 4)
                    love.graphics.line(midX + 4, midY - 4, midX - 4, midY + 4)

                    love.graphics.setLineWidth(1)
                end
            end
        end
    end

    --- Draw drag ghost
    function arena:drawDragGhost()
        if not self.draggedEntity then return end

        local mx, my = love.mouse.getPosition()
        local x = mx - self.dragOffsetX
        local y = my - self.dragOffsetY

        love.graphics.setColor(self.colors.drag_ghost)
        self:drawToken(self.draggedEntity, x, y, M.TOKEN_SIZE)
    end

    ----------------------------------------------------------------------------
    -- INPUT HANDLING
    ----------------------------------------------------------------------------

    function arena:mousepressed(x, y, button)
        if not self.isVisible then return false end
        if button ~= 1 then return false end

        -- Check if clicking on a token
        for _, zone in pairs(self.zones) do
            for _, entity in ipairs(zone.entities) do
                if entity._tokenX and self:isInsideToken(x, y, entity._tokenX, entity._tokenY) then
                    -- Start dragging
                    self.draggedEntity = entity
                    self.dragOffsetX = x - entity._tokenX
                    self.dragOffsetY = y - entity._tokenY
                    return true
                end
            end
        end

        return false
    end

    function arena:mousereleased(x, y, button)
        if not self.isVisible then return false end
        if button ~= 1 then return false end

        if self.draggedEntity then
            -- Check if dropped on a different zone
            local targetZone = self:getZoneAt(x, y)
            if targetZone and targetZone ~= self.entities[self.draggedEntity.id].zoneId then
                -- Emit move intent (logic will handle parting blows etc.)
                self.eventBus:emit("entity_move_intent", {
                    entity = self.draggedEntity,
                    fromZone = self.entities[self.draggedEntity.id].zoneId,
                    toZone = targetZone,
                })

                -- For now, just move directly (S6.3 will add parting blow checks)
                self:moveEntity(self.draggedEntity, targetZone)
            end

            self.draggedEntity = nil
            self.hoveredZone = nil
            return true
        end

        return false
    end

    function arena:mousemoved(x, y, dx, dy)
        if not self.isVisible then return end

        -- Update hovered zone for drop target highlighting
        if self.draggedEntity then
            self.hoveredZone = self:getZoneAt(x, y)
        end

        -- S10.2: Track hovered entity for targeting mode
        if self.targetingMode then
            self.hoveredEntity = self:getEntityAt(x, y)
        else
            self.hoveredEntity = nil
        end
    end

    --- Check if a point is inside a token
    function arena:isInsideToken(px, py, tokenX, tokenY)
        local cx = tokenX + M.TOKEN_SIZE / 2
        local cy = tokenY + M.TOKEN_SIZE / 2
        local dx = px - cx
        local dy = py - cy
        return (dx * dx + dy * dy) <= (M.TOKEN_SIZE / 2) * (M.TOKEN_SIZE / 2)
    end

    --- Get zone at a position
    function arena:getZoneAt(x, y)
        for zoneId, zone in pairs(self.zones) do
            if x >= zone.x and x <= zone.x + zone.width and
               y >= zone.y and y <= zone.y + zone.height then
                return zoneId
            end
        end
        return nil
    end

    ----------------------------------------------------------------------------
    -- TARGETING MODE (S10.2)
    ----------------------------------------------------------------------------

    --- Enter targeting mode
    -- @param validTargetIds table: Array of valid target entity IDs
    function arena:enterTargetingMode(validTargetIds)
        self.targetingMode = true
        self.validTargets = validTargetIds or {}
        self.targetReticleTimer = 0
        print("[ArenaView] Entered targeting mode with " .. #self.validTargets .. " valid targets")
    end

    --- Exit targeting mode
    function arena:exitTargetingMode()
        self.targetingMode = false
        self.validTargets = {}
    end

    --- Check if an entity is a valid target
    function arena:isValidTarget(entityId)
        for _, id in ipairs(self.validTargets) do
            if id == entityId then
                return true
            end
        end
        return false
    end

    --- Get entity at position
    function arena:getEntityAt(x, y)
        for _, entity in ipairs(self.entities) do
            local zoneId = entity.zone or "main"
            local zone = self.zones[zoneId]
            if zone then
                -- Calculate entity's screen position in zone
                local tokenIndex = self:getEntityIndexInZone(entity, zoneId)
                local tokenX, tokenY = self:getTokenPosition(zone, tokenIndex)
                if self:isInsideToken(x, y, tokenX, tokenY) then
                    return entity
                end
            end
        end
        return nil
    end

    --- Get index of entity within its zone (for positioning)
    function arena:getEntityIndexInZone(entity, zoneId)
        local index = 0
        for _, e in ipairs(self.entities) do
            if (e.zone or "main") == zoneId then
                index = index + 1
                if e.id == entity.id then
                    return index
                end
            end
        end
        return 1
    end

    --- Draw targeting reticle on entity token
    function arena:drawTargetingReticle(tokenX, tokenY, isValid)
        local cx = tokenX + M.TOKEN_SIZE / 2
        local cy = tokenY + M.TOKEN_SIZE / 2
        local radius = M.TOKEN_SIZE / 2 + 8

        -- Animated pulse
        local pulse = math.sin(self.targetReticleTimer * 6) * 0.2 + 0.8

        -- Color based on validity
        local color = isValid and self.colors.target_valid or self.colors.target_reticle

        -- Outer ring (pulsing)
        love.graphics.setColor(color[1], color[2], color[3], color[4] * pulse)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", cx, cy, radius)

        -- Crosshairs
        local crossSize = 8
        love.graphics.setColor(color[1], color[2], color[3], color[4])
        love.graphics.setLineWidth(2)
        -- Top
        love.graphics.line(cx, cy - radius - 5, cx, cy - radius + crossSize)
        -- Bottom
        love.graphics.line(cx, cy + radius + 5, cx, cy + radius - crossSize)
        -- Left
        love.graphics.line(cx - radius - 5, cy, cx - radius + crossSize, cy)
        -- Right
        love.graphics.line(cx + radius + 5, cy, cx + radius - crossSize, cy)

        love.graphics.setLineWidth(1)
    end

    --- Draw targeting indicators on all valid targets
    function arena:drawTargetingIndicators()
        if not self.targetingMode then return end

        for _, targetId in ipairs(self.validTargets) do
            for _, entity in ipairs(self.entities) do
                if entity.id == targetId then
                    local zoneId = entity.zone or "main"
                    local zone = self.zones[zoneId]
                    if zone then
                        local tokenIndex = self:getEntityIndexInZone(entity, zoneId)
                        local tokenX, tokenY = self:getTokenPosition(zone, tokenIndex)

                        -- Draw pulsing ring indicator on valid targets
                        local cx = tokenX + M.TOKEN_SIZE / 2
                        local cy = tokenY + M.TOKEN_SIZE / 2
                        local pulse = math.sin(self.targetReticleTimer * 4) * 0.3 + 0.7

                        love.graphics.setColor(self.colors.target_valid[1],
                                               self.colors.target_valid[2],
                                               self.colors.target_valid[3],
                                               pulse * 0.5)
                        love.graphics.circle("fill", cx, cy, M.TOKEN_SIZE / 2 + 6)
                    end
                end
            end
        end

        -- Draw reticle on hovered entity
        if self.hoveredEntity then
            local zoneId = self.hoveredEntity.zone or "main"
            local zone = self.zones[zoneId]
            if zone then
                local tokenIndex = self:getEntityIndexInZone(self.hoveredEntity, zoneId)
                local tokenX, tokenY = self:getTokenPosition(zone, tokenIndex)
                local isValid = self:isValidTarget(self.hoveredEntity.id)
                self:drawTargetingReticle(tokenX, tokenY, isValid)
            end
        end
    end

    return arena
end

return M

```

---

## File: src/ui/belt_hotbar.lua

```lua
-- belt_hotbar.lua
-- Belt Hotbar HUD for Majesty
-- Ticket S10.3: Quick-access belt items and ammo display
--
-- Displays belt items for the selected PC with one-click use.
-- Also shows ammo counts for ranged characters.

local M = {}

local events = require('logic.events')

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

M.SLOT_SIZE = 48
M.SLOT_SPACING = 6
M.SLOT_PADDING = 8
M.MAX_SLOTS = 4  -- Belt has 4 slots

--------------------------------------------------------------------------------
-- BELT HOTBAR FACTORY
--------------------------------------------------------------------------------

--- Create a new BeltHotbar instance
-- @param config table: { eventBus, guild, x, y }
-- @return BeltHotbar instance
function M.createBeltHotbar(config)
    config = config or {}

    local hotbar = {
        eventBus = config.eventBus or events.globalBus,
        guild = config.guild or {},
        x = config.x or 10,
        y = config.y or 400,

        -- Currently selected PC (0 = none, 1-4 = guild index)
        selectedPC = 1,

        -- Hover state
        hoveredSlot = nil,

        -- Visibility
        isVisible = true,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function hotbar:init()
        -- Listen for PC selection changes if we add that later
    end

    ----------------------------------------------------------------------------
    -- PC SELECTION
    ----------------------------------------------------------------------------

    --- Set the currently selected PC
    function hotbar:setSelectedPC(index)
        if index >= 1 and index <= #self.guild then
            self.selectedPC = index
        end
    end

    --- Get the currently selected PC
    function hotbar:getSelectedPC()
        if self.selectedPC >= 1 and self.selectedPC <= #self.guild then
            return self.guild[self.selectedPC]
        end
        return nil
    end

    ----------------------------------------------------------------------------
    -- ITEM USE
    ----------------------------------------------------------------------------

    --- Use an item from the belt
    -- @param slotIndex number: 1-4 belt slot
    function hotbar:useItem(slotIndex)
        local pc = self:getSelectedPC()
        if not pc or not pc.inventory then return false end

        local beltItems = pc.inventory:getItems("belt")
        if slotIndex > #beltItems then return false end

        local item = beltItems[slotIndex]
        if not item then return false end

        -- Handle different item types
        if item.properties and item.properties.light_source then
            -- Torch/Lantern - activate light
            self:useLight(pc, item)
            return true
        elseif item.isRation or item.type == "ration" or
               (item.name and item.name:lower():find("ration")) then
            -- Ration - eat it
            self:useRation(pc, item)
            return true
        elseif item.name and item.name:lower():find("potion") then
            -- Potion - use it
            self:usePotion(pc, item)
            return true
        end

        print("[HOTBAR] Cannot use item: " .. item.name)
        return false
    end

    --- Use a light source
    function hotbar:useLight(pc, item)
        local flickerCount = item.properties.flicker_count or 3

        -- Check if already lit
        if item.properties.is_lit then
            print("[HOTBAR] " .. pc.name .. " extinguishes " .. item.name)
            item.properties.is_lit = false
            self.eventBus:emit("light_source_toggled", {
                entity = pc,
                item = item,
                lit = false,
            })
        else
            print("[HOTBAR] " .. pc.name .. " lights " .. item.name .. " (" .. flickerCount .. " flickers remaining)")
            item.properties.is_lit = true
            self.eventBus:emit("light_source_toggled", {
                entity = pc,
                item = item,
                lit = true,
            })
        end
    end

    --- Use a ration
    function hotbar:useRation(pc, item)
        print("[HOTBAR] " .. pc.name .. " eats a ration")

        -- Remove one ration
        pc.inventory:removeItemQuantity(item.id, 1)

        -- Heal starvation if present
        if pc.starvationCount and pc.starvationCount > 0 then
            pc.starvationCount = pc.starvationCount - 1
            print("[HOTBAR] Starvation reduced to " .. pc.starvationCount)
        end

        self.eventBus:emit("ration_consumed", {
            entity = pc,
            item = item,
        })
    end

    --- Use a potion
    function hotbar:usePotion(pc, item)
        print("[HOTBAR] " .. pc.name .. " drinks " .. item.name)

        -- Remove potion
        pc.inventory:removeItem(item.id)

        -- TODO: Apply potion effects based on type
        self.eventBus:emit("potion_consumed", {
            entity = pc,
            item = item,
        })
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function hotbar:update(dt)
        -- Update hover state based on mouse position
        if not self.isVisible then return end

        local mouseX, mouseY = love.mouse.getPosition()
        self.hoveredSlot = nil

        local pc = self:getSelectedPC()
        if not pc or not pc.inventory then return end

        local beltItems = pc.inventory:getItems("belt")
        for i = 1, M.MAX_SLOTS do
            local slotX = self.x + (i - 1) * (M.SLOT_SIZE + M.SLOT_SPACING)
            local slotY = self.y

            if mouseX >= slotX and mouseX < slotX + M.SLOT_SIZE and
               mouseY >= slotY and mouseY < slotY + M.SLOT_SIZE then
                self.hoveredSlot = i
                break
            end
        end
    end

    ----------------------------------------------------------------------------
    -- DRAW
    ----------------------------------------------------------------------------

    function hotbar:draw()
        if not self.isVisible then return end
        if not love then return end

        local pc = self:getSelectedPC()
        if not pc then return end

        local beltItems = {}
        if pc.inventory then
            beltItems = pc.inventory:getItems("belt")
        end

        -- Draw PC name label
        love.graphics.setColor(0.8, 0.8, 0.8, 0.9)
        love.graphics.print(pc.name .. "'s Belt", self.x, self.y - 18)

        -- Draw belt slots
        for i = 1, M.MAX_SLOTS do
            local slotX = self.x + (i - 1) * (M.SLOT_SIZE + M.SLOT_SPACING)
            local slotY = self.y
            local item = beltItems[i]

            -- Slot background
            local isHovered = (self.hoveredSlot == i)
            if item and isHovered then
                love.graphics.setColor(0.4, 0.4, 0.5, 0.9)
            elseif item then
                love.graphics.setColor(0.25, 0.25, 0.3, 0.9)
            else
                love.graphics.setColor(0.15, 0.15, 0.18, 0.7)
            end
            love.graphics.rectangle("fill", slotX, slotY, M.SLOT_SIZE, M.SLOT_SIZE, 4, 4)

            -- Slot border
            if isHovered and item then
                love.graphics.setColor(1, 0.9, 0.4, 1)
                love.graphics.setLineWidth(2)
            else
                love.graphics.setColor(0.5, 0.5, 0.55, 0.8)
                love.graphics.setLineWidth(1)
            end
            love.graphics.rectangle("line", slotX, slotY, M.SLOT_SIZE, M.SLOT_SIZE, 4, 4)
            love.graphics.setLineWidth(1)

            -- Slot number key (1-4)
            love.graphics.setColor(0.6, 0.6, 0.6, 0.7)
            love.graphics.print(tostring(i), slotX + 3, slotY + 2)

            -- Draw item if present
            if item then
                self:drawItemIcon(item, slotX, slotY, M.SLOT_SIZE)

                -- Show tooltip on hover
                if isHovered then
                    self:drawItemTooltip(item, slotX, slotY - 40)
                end
            end
        end

        -- Draw ammo display (if PC has ammo)
        if pc.ammo ~= nil then
            self:drawAmmoDisplay(pc)
        end
    end

    --- Draw an item icon in a slot
    function hotbar:drawItemIcon(item, x, y, size)
        -- Item icon background color based on type
        local iconColor = { 0.6, 0.6, 0.6 }

        if item.properties and item.properties.light_source then
            if item.properties.is_lit then
                iconColor = { 1, 0.8, 0.3 }  -- Lit torch = orange/yellow
            else
                iconColor = { 0.7, 0.4, 0.2 }  -- Unlit torch = brown
            end
        elseif item.isRation or (item.name and item.name:lower():find("ration")) then
            iconColor = { 0.5, 0.7, 0.4 }  -- Ration = green
        elseif item.name and item.name:lower():find("potion") then
            iconColor = { 0.4, 0.5, 0.8 }  -- Potion = blue
        end

        -- Draw icon circle
        love.graphics.setColor(iconColor[1], iconColor[2], iconColor[3], 0.9)
        love.graphics.circle("fill", x + size/2, y + size/2, size/3)

        -- Draw item initial/symbol
        love.graphics.setColor(1, 1, 1, 1)
        local initial = string.sub(item.name, 1, 1):upper()
        love.graphics.print(initial, x + size/2 - 4, y + size/2 - 6)

        -- Draw quantity if stackable
        if item.stackable and item.quantity and item.quantity > 1 then
            love.graphics.setColor(1, 1, 1, 0.9)
            love.graphics.print("x" .. item.quantity, x + size - 20, y + size - 14)
        end

        -- Draw lit indicator
        if item.properties and item.properties.is_lit then
            love.graphics.setColor(1, 0.9, 0.3, 0.8)
            love.graphics.circle("fill", x + size - 8, y + 8, 4)
        end
    end

    --- Draw item tooltip
    function hotbar:drawItemTooltip(item, x, y)
        local text = item.name
        if item.stackable and item.quantity then
            text = text .. " (x" .. item.quantity .. ")"
        end
        if item.properties and item.properties.flicker_count then
            text = text .. " [" .. item.properties.flicker_count .. " flickers]"
        end

        -- Tooltip background
        local textWidth = love.graphics.getFont():getWidth(text)
        love.graphics.setColor(0.1, 0.1, 0.12, 0.95)
        love.graphics.rectangle("fill", x - 4, y - 2, textWidth + 8, 20, 3, 3)

        -- Tooltip text
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(text, x, y)
    end

    --- Draw ammo counter
    function hotbar:drawAmmoDisplay(pc)
        local ammoX = self.x + M.MAX_SLOTS * (M.SLOT_SIZE + M.SLOT_SPACING) + 10
        local ammoY = self.y

        -- Ammo icon
        love.graphics.setColor(0.6, 0.5, 0.3, 0.9)
        love.graphics.rectangle("fill", ammoX, ammoY, 60, M.SLOT_SIZE, 4, 4)

        love.graphics.setColor(0.5, 0.5, 0.55, 0.8)
        love.graphics.rectangle("line", ammoX, ammoY, 60, M.SLOT_SIZE, 4, 4)

        -- Ammo count
        local ammoText = tostring(pc.ammo or 0)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("Ammo", ammoX + 8, ammoY + 4)

        -- Color based on ammo level
        if pc.ammo <= 0 then
            love.graphics.setColor(1, 0.3, 0.3, 1)  -- Red = empty
        elseif pc.ammo <= 3 then
            love.graphics.setColor(1, 0.8, 0.3, 1)  -- Yellow = low
        else
            love.graphics.setColor(0.3, 1, 0.3, 1)  -- Green = good
        end
        love.graphics.print(ammoText, ammoX + 25, ammoY + 22)
    end

    ----------------------------------------------------------------------------
    -- INPUT
    ----------------------------------------------------------------------------

    function hotbar:mousepressed(x, y, button)
        if not self.isVisible then return false end
        if button ~= 1 then return false end  -- Left click only

        -- Check if clicked on a slot
        if self.hoveredSlot then
            self:useItem(self.hoveredSlot)
            return true
        end

        return false
    end

    function hotbar:keypressed(key)
        if not self.isVisible then return false end

        -- Number keys 1-4 to use belt items
        local keyNum = tonumber(key)
        if keyNum and keyNum >= 1 and keyNum <= M.MAX_SLOTS then
            return self:useItem(keyNum)
        end

        -- Tab to cycle selected PC
        if key == "tab" then
            self.selectedPC = (self.selectedPC % #self.guild) + 1
            return true
        end

        return false
    end

    return hotbar
end

return M

```

---

## File: src/ui/character_plate.lua

```lua
-- character_plate.lua
-- Extended Character Plate Component for Majesty
-- Ticket S5.1: Condition glyphs, talent tray, wound flow animation
--
-- Design: "Ink on Parchment" aesthetic
-- - Muted, desaturated colors
-- - Bold strokes for mastered elements
-- - Faint sketchy lines for in-training elements
-- - Red accents only for wounds/danger

local events = require('logic.events')
local item_view = require('ui.item_view')

local M = {}

--------------------------------------------------------------------------------
-- COLORS (Ink on Parchment palette)
--------------------------------------------------------------------------------
M.COLORS = {
    -- Base inks
    ink_dark      = { 0.15, 0.12, 0.10, 1.0 },   -- Dark sepia ink
    ink_medium    = { 0.35, 0.30, 0.25, 1.0 },   -- Medium ink
    ink_faint     = { 0.55, 0.50, 0.45, 0.6 },   -- Faint pencil sketch

    -- Condition colors (muted, not saturated)
    stressed      = { 0.65, 0.55, 0.20, 1.0 },   -- Ochre/amber
    staggered     = { 0.50, 0.45, 0.55, 1.0 },   -- Muted purple
    injured       = { 0.60, 0.25, 0.20, 1.0 },   -- Dark red
    deaths_door   = { 0.45, 0.15, 0.15, 1.0 },   -- Deep crimson

    -- Talent states
    mastered      = { 0.20, 0.35, 0.50, 1.0 },   -- Deep blue ink
    training      = { 0.50, 0.48, 0.45, 0.5 },   -- Faint grey
    wounded       = { 0.55, 0.20, 0.15, 1.0 },   -- Red

    -- Highlight for wound flow animation
    highlight     = { 0.90, 0.70, 0.20, 1.0 },   -- Gold flash
    highlight_bg  = { 0.90, 0.70, 0.20, 0.3 },   -- Gold glow

    -- Bond colors (S9.1)
    bond_charged  = { 0.70, 0.55, 0.85, 1.0 },   -- Purple glow for charged
    bond_spent    = { 0.40, 0.40, 0.45, 0.5 },   -- Grey for spent
}

--------------------------------------------------------------------------------
-- CONDITION GLYPH DEFINITIONS
-- Each condition has a draw function that renders its iconic symbol
--------------------------------------------------------------------------------
M.CONDITION_GLYPHS = {
    stressed = {
        name = "Stressed",
        draw = function(x, y, size, color)
            -- Cracked mind symbol: spiral with crack
            love.graphics.setColor(color)
            love.graphics.setLineWidth(2)

            -- Spiral
            local cx, cy = x + size/2, y + size/2
            local r = size * 0.35
            for i = 0, 8 do
                local a1 = (i / 8) * math.pi * 2
                local a2 = ((i + 1) / 8) * math.pi * 2
                local r1 = r * (1 - i * 0.08)
                local r2 = r * (1 - (i+1) * 0.08)
                love.graphics.line(
                    cx + math.cos(a1) * r1,
                    cy + math.sin(a1) * r1,
                    cx + math.cos(a2) * r2,
                    cy + math.sin(a2) * r2
                )
            end

            -- Crack through it
            love.graphics.line(cx - r*0.5, cy - r*0.3, cx + r*0.5, cy + r*0.3)
            love.graphics.line(cx + r*0.2, cy, cx + r*0.5, cy - r*0.4)

            love.graphics.setLineWidth(1)
        end,
    },

    staggered = {
        name = "Staggered",
        draw = function(x, y, size, color)
            -- Dizzy stars / vertigo symbol
            love.graphics.setColor(color)
            love.graphics.setLineWidth(1.5)

            local cx, cy = x + size/2, y + size/2

            -- Three small stars in a curve
            for i = 1, 3 do
                local angle = math.pi * 0.3 + (i - 1) * 0.5
                local dist = size * 0.25
                local sx = cx + math.cos(angle) * dist
                local sy = cy + math.sin(angle) * dist
                local starSize = size * 0.12

                -- 4-point star
                love.graphics.line(sx - starSize, sy, sx + starSize, sy)
                love.graphics.line(sx, sy - starSize, sx, sy + starSize)
            end

            -- Wavy line underneath
            love.graphics.line(
                cx - size*0.3, cy + size*0.2,
                cx - size*0.1, cy + size*0.25,
                cx + size*0.1, cy + size*0.15,
                cx + size*0.3, cy + size*0.2
            )

            love.graphics.setLineWidth(1)
        end,
    },

    injured = {
        name = "Injured",
        draw = function(x, y, size, color)
            -- Blood drop symbol
            love.graphics.setColor(color)
            love.graphics.setLineWidth(2)

            local cx, cy = x + size/2, y + size/2

            -- Teardrop/blood drop shape
            local points = {}
            local segments = 12
            for i = 0, segments do
                local t = i / segments
                local angle = math.pi * 0.5 + t * math.pi * 2
                local r = size * 0.3

                -- Modify radius for teardrop shape
                if t < 0.5 then
                    r = r * (0.3 + t * 1.4)
                else
                    r = r * (0.3 + (1 - t) * 1.4)
                end

                -- Point at top
                if i == 0 then
                    points[#points + 1] = cx
                    points[#points + 1] = cy - size * 0.35
                else
                    points[#points + 1] = cx + math.cos(angle) * r
                    points[#points + 1] = cy + math.sin(angle) * r * 0.8
                end
            end

            if #points >= 6 then
                love.graphics.polygon("line", points)
            end

            love.graphics.setLineWidth(1)
        end,
    },

    deaths_door = {
        name = "Death's Door",
        draw = function(x, y, size, color)
            -- Skull symbol (simplified)
            love.graphics.setColor(color)
            love.graphics.setLineWidth(2)

            local cx, cy = x + size/2, y + size/2

            -- Skull outline (oval)
            love.graphics.ellipse("line", cx, cy - size*0.05, size*0.3, size*0.35)

            -- Eye sockets
            love.graphics.circle("fill", cx - size*0.1, cy - size*0.1, size*0.06)
            love.graphics.circle("fill", cx + size*0.1, cy - size*0.1, size*0.06)

            -- Nose (inverted triangle)
            love.graphics.polygon("fill",
                cx, cy + size*0.02,
                cx - size*0.04, cy + size*0.12,
                cx + size*0.04, cy + size*0.12
            )

            -- Jaw line
            love.graphics.line(
                cx - size*0.15, cy + size*0.2,
                cx, cy + size*0.25,
                cx + size*0.15, cy + size*0.2
            )

            love.graphics.setLineWidth(1)
        end,
    },
}

--------------------------------------------------------------------------------
-- CHARACTER PLATE FACTORY
--------------------------------------------------------------------------------

--- Create a new CharacterPlate component
-- @param config table: { eventBus, entity, x, y, width }
-- @return CharacterPlate instance
function M.createCharacterPlate(config)
    config = config or {}

    local plate = {
        eventBus = config.eventBus or events.globalBus,
        entity   = config.entity,

        -- Position and size
        x      = config.x or 0,
        y      = config.y or 0,
        width  = config.width or 180,

        -- Layout constants
        portraitSize    = 50,
        glyphSize       = 18,
        talentDotSize   = 8,
        padding         = 6,

        -- Animation state
        highlightTarget = nil,    -- "stressed", "talent_3", etc.
        highlightTimer  = 0,
        highlightDuration = 0.8,

        -- Colors
        colors = config.colors or M.COLORS,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function plate:init()
        -- Subscribe to wound events for animation
        self.eventBus:on(events.EVENTS.WOUND_TAKEN, function(data)
            if data.entity == self.entity then
                self:triggerWoundAnimation(data.result)
            end
        end)
    end

    ----------------------------------------------------------------------------
    -- SETTERS
    ----------------------------------------------------------------------------

    function plate:setEntity(entity)
        self.entity = entity
    end

    function plate:setPosition(x, y)
        self.x = x
        self.y = y
    end

    ----------------------------------------------------------------------------
    -- WOUND FLOW ANIMATION
    ----------------------------------------------------------------------------

    --- Trigger highlight animation for wound flow
    -- @param woundResult string: "armor_notched", "talent_wounded", "staggered", etc.
    function plate:triggerWoundAnimation(woundResult)
        -- Map wound result to highlight target
        if woundResult == "talent_wounded" then
            -- Highlight the next wounded talent slot
            local woundedCount = self.entity and self.entity.woundedTalents or 0
            self.highlightTarget = "talent_" .. woundedCount
        elseif woundResult == "staggered" then
            self.highlightTarget = "staggered"
        elseif woundResult == "injured" then
            self.highlightTarget = "injured"
        elseif woundResult == "deaths_door" then
            self.highlightTarget = "deaths_door"
        elseif woundResult == "armor_notched" then
            self.highlightTarget = "armor"
        end

        self.highlightTimer = self.highlightDuration
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function plate:update(dt)
        -- Update highlight animation
        if self.highlightTimer > 0 then
            self.highlightTimer = self.highlightTimer - dt
            if self.highlightTimer <= 0 then
                self.highlightTarget = nil
            end
        end

        -- S9.1: Track time for bond glow animation
        self.animTimer = (self.animTimer or 0) + dt
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    ----------------------------------------------------------------------------

    --- Draw the complete character plate
    function plate:draw()
        if not love or not self.entity then return end

        local e = self.entity
        local y = self.y

        -- Portrait
        self:drawPortrait(self.x, y)
        local nameX = self.x + self.portraitSize + self.padding

        -- Name
        love.graphics.setColor(self.colors.ink_dark)
        love.graphics.print(e.name or "Unknown", nameX, y + 2)

        -- Condition glyphs (row below name)
        local glyphY = y + 16
        self:drawConditionGlyphs(nameX, glyphY)

        -- S5.2: Armor pips (if entity has armor)
        if e.armorSlots and e.armorSlots > 0 then
            local armorY = glyphY + self.glyphSize + 2
            self:drawArmorPips(nameX, armorY)
        end

        -- Talent tray (below portrait)
        local talentY = y + self.portraitSize + self.padding
        self:drawTalentTray(self.x, talentY)

        -- Resolve pips (if entity has resolve)
        if e.resolve then
            local resolveY = talentY + self.talentDotSize + self.padding
            self:drawResolvePips(self.x, resolveY)
        end
    end

    --- Draw the portrait placeholder
    function plate:drawPortrait(x, y)
        local e = self.entity

        -- S9.1: Draw bond glow if has charged bonds
        local chargedBondCount = self:countChargedBonds()
        if chargedBondCount > 0 then
            -- Pulsing glow effect
            local pulseAlpha = 0.3 + math.sin((self.animTimer or 0) * 3) * 0.15
            love.graphics.setColor(self.colors.bond_charged[1], self.colors.bond_charged[2],
                                   self.colors.bond_charged[3], pulseAlpha)
            love.graphics.circle("fill", x + self.portraitSize/2, y + self.portraitSize/2,
                                self.portraitSize/2 + 8)
        end

        -- Background
        love.graphics.setColor(0.25, 0.30, 0.35, 1.0)
        love.graphics.rectangle("fill", x, y, self.portraitSize, self.portraitSize, 3, 3)

        -- Border
        love.graphics.setColor(self.colors.ink_medium)
        love.graphics.rectangle("line", x, y, self.portraitSize, self.portraitSize, 3, 3)

        -- If at death's door, add red border
        if e.conditions and e.conditions.deaths_door then
            love.graphics.setColor(self.colors.deaths_door)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", x-1, y-1, self.portraitSize+2, self.portraitSize+2, 4, 4)
            love.graphics.setLineWidth(1)
        -- S9.1: If has charged bonds, add purple border
        elseif chargedBondCount > 0 then
            love.graphics.setColor(self.colors.bond_charged)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", x-1, y-1, self.portraitSize+2, self.portraitSize+2, 4, 4)
            love.graphics.setLineWidth(1)
        end
    end

    --- Count charged bonds for this entity (S9.1)
    function plate:countChargedBonds()
        local e = self.entity
        if not e or not e.bonds then return 0 end

        local count = 0
        for _, bond in pairs(e.bonds) do
            if bond.charged then
                count = count + 1
            end
        end
        return count
    end

    --- Draw condition glyphs in a row
    function plate:drawConditionGlyphs(x, y)
        local e = self.entity
        if not e.conditions then return end

        local glyphX = x
        local glyphSpacing = self.glyphSize + 4

        -- Draw each active condition
        local conditions = { "stressed", "staggered", "injured", "deaths_door" }

        for _, condName in ipairs(conditions) do
            if e.conditions[condName] then
                local glyph = M.CONDITION_GLYPHS[condName]
                if glyph then
                    local color = self.colors[condName] or self.colors.ink_dark

                    -- Highlight background if this is the animation target
                    if self.highlightTarget == condName and self.highlightTimer > 0 then
                        local alpha = math.sin(self.highlightTimer * 10) * 0.5 + 0.5
                        love.graphics.setColor(self.colors.highlight_bg[1], self.colors.highlight_bg[2], self.colors.highlight_bg[3], alpha)
                        love.graphics.rectangle("fill", glyphX - 2, y - 2, self.glyphSize + 4, self.glyphSize + 4, 2, 2)
                    end

                    -- Draw the glyph
                    glyph.draw(glyphX, y, self.glyphSize, color)

                    glyphX = glyphX + glyphSpacing
                end
            end
        end
    end

    --- Draw the talent tray (7 dots)
    function plate:drawTalentTray(x, y)
        local e = self.entity
        local talents = e.talents or {}
        local woundedCount = e.woundedTalents or 0

        local dotSpacing = self.talentDotSize + 4
        local maxTalents = 7

        for i = 1, maxTalents do
            local dotX = x + (i - 1) * dotSpacing
            local talent = talents[i]

            -- Determine dot state
            local state = "empty"
            if talent then
                if i <= woundedCount then
                    state = "wounded"
                elseif talent.mastered then
                    state = "mastered"
                else
                    state = "training"
                end
            end

            -- Check for highlight animation
            local isHighlighted = (self.highlightTarget == "talent_" .. i) and self.highlightTimer > 0

            -- Draw the dot
            self:drawTalentDot(dotX, y, state, isHighlighted)
        end
    end

    --- Draw a single talent dot
    -- @param x, y number: Position
    -- @param state string: "empty", "mastered", "training", "wounded"
    -- @param highlighted boolean: Whether to show highlight animation
    function plate:drawTalentDot(x, y, state, highlighted)
        local size = self.talentDotSize

        -- Highlight glow
        if highlighted then
            local alpha = math.sin(self.highlightTimer * 10) * 0.5 + 0.5
            love.graphics.setColor(self.colors.highlight[1], self.colors.highlight[2], self.colors.highlight[3], alpha)
            love.graphics.circle("fill", x + size/2, y + size/2, size * 0.8)
        end

        if state == "mastered" then
            -- Solid blue ink circle
            love.graphics.setColor(self.colors.mastered)
            love.graphics.circle("fill", x + size/2, y + size/2, size/2)
            -- Dark border for definition
            love.graphics.setColor(self.colors.ink_dark)
            love.graphics.circle("line", x + size/2, y + size/2, size/2)

        elseif state == "training" then
            -- Faint grey circle (pencil sketch look)
            love.graphics.setColor(self.colors.training)
            love.graphics.circle("line", x + size/2, y + size/2, size/2)
            -- Dashed inner for "incomplete" feel
            love.graphics.setColor(self.colors.ink_faint)
            love.graphics.circle("fill", x + size/2, y + size/2, size/4)

        elseif state == "wounded" then
            -- Red X over the dot
            love.graphics.setColor(self.colors.wounded)
            love.graphics.circle("fill", x + size/2, y + size/2, size/2)
            -- X mark
            love.graphics.setColor(self.colors.ink_dark)
            love.graphics.setLineWidth(2)
            love.graphics.line(x + 2, y + 2, x + size - 2, y + size - 2)
            love.graphics.line(x + size - 2, y + 2, x + 2, y + size - 2)
            love.graphics.setLineWidth(1)

        else
            -- Empty slot (very faint outline)
            love.graphics.setColor(self.colors.ink_faint)
            love.graphics.circle("line", x + size/2, y + size/2, size/2)
        end
    end

    --- Draw armor pips (S5.2)
    function plate:drawArmorPips(x, y)
        local e = self.entity
        if not e.armorSlots or e.armorSlots <= 0 then return end

        local slots = e.armorSlots
        local notches = e.armorNotches or 0
        local pipSize = 8
        local pipSpacing = pipSize + 3

        -- Small shield icon
        love.graphics.setColor(self.colors.ink_medium)
        love.graphics.print("Armor:", x, y)

        local pipX = x + 40
        for i = 1, slots do
            if i <= notches then
                -- Notched (damaged) - red with X
                love.graphics.setColor(0.55, 0.25, 0.20, 1.0)
                love.graphics.rectangle("fill", pipX + (i-1) * pipSpacing, y + 2, pipSize, pipSize, 1, 1)
                -- X mark
                love.graphics.setColor(self.colors.ink_dark)
                love.graphics.line(
                    pipX + (i-1) * pipSpacing + 1, y + 3,
                    pipX + (i-1) * pipSpacing + pipSize - 1, y + pipSize + 1
                )
            else
                -- Intact - steel grey
                love.graphics.setColor(0.50, 0.55, 0.60, 1.0)
                love.graphics.rectangle("fill", pipX + (i-1) * pipSpacing, y + 2, pipSize, pipSize, 1, 1)
            end
            -- Border
            love.graphics.setColor(self.colors.ink_faint)
            love.graphics.rectangle("line", pipX + (i-1) * pipSpacing, y + 2, pipSize, pipSize, 1, 1)
        end
    end

    --- Draw resolve pips (if the entity has resolve)
    function plate:drawResolvePips(x, y)
        local e = self.entity
        if not e.resolve then return end

        local current = e.resolve.current or 0
        local max = e.resolve.max or 4
        local pipSize = 6
        local pipSpacing = pipSize + 3

        love.graphics.setColor(self.colors.ink_faint)
        love.graphics.print("Resolve:", x, y)

        local pipX = x + 50
        for i = 1, max do
            if i <= current then
                -- Filled pip
                love.graphics.setColor(self.colors.mastered)
                love.graphics.rectangle("fill", pipX + (i-1) * pipSpacing, y + 2, pipSize, pipSize, 1, 1)
            else
                -- Empty pip
                love.graphics.setColor(self.colors.ink_faint)
                love.graphics.rectangle("line", pipX + (i-1) * pipSpacing, y + 2, pipSize, pipSize, 1, 1)
            end
        end
    end

    --- Calculate total height of the plate
    function plate:getHeight()
        local height = self.portraitSize + self.padding
        height = height + self.talentDotSize + self.padding

        if self.entity and self.entity.resolve then
            height = height + 16  -- Resolve pips height
        end

        return height
    end

    return plate
end

return M

```

---

## File: src/ui/combat_display.lua

```lua
-- combat_display.lua
-- Combat Display Component for Majesty
-- Ticket S5.3: Defense Slots & Initiative Visualization
--
-- Features:
-- - Defense slot display (facedown card when defense prepared)
-- - Initiative slot with card flip animation
-- - Active entity highlighting during count-up
-- - Combatant portraits with status

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- COLORS
--------------------------------------------------------------------------------
M.COLORS = {
    -- Card colors
    card_back       = { 0.25, 0.15, 0.30, 1.0 },   -- Deep purple
    card_border     = { 0.50, 0.40, 0.55, 1.0 },
    card_face       = { 0.90, 0.85, 0.75, 1.0 },   -- Parchment

    -- Highlight
    active_glow     = { 0.90, 0.80, 0.20, 1.0 },   -- Gold
    active_bg       = { 0.90, 0.80, 0.20, 0.3 },

    -- Defense types
    defense_dodge   = { 0.30, 0.50, 0.70, 1.0 },   -- Blue tint
    defense_riposte = { 0.70, 0.30, 0.30, 1.0 },   -- Red tint
    defense_unknown = { 0.40, 0.35, 0.45, 1.0 },   -- Neutral

    -- Text
    text_light      = { 0.90, 0.88, 0.80, 1.0 },
    text_dark       = { 0.15, 0.12, 0.10, 1.0 },

    -- Status
    pc_bg           = { 0.20, 0.35, 0.25, 1.0 },
    npc_bg          = { 0.35, 0.20, 0.20, 1.0 },
}

--------------------------------------------------------------------------------
-- ANIMATION CONSTANTS
--------------------------------------------------------------------------------
M.FLIP_DURATION = 0.4    -- Card flip animation duration
M.GLOW_SPEED = 4.0       -- Active entity glow pulse speed

--------------------------------------------------------------------------------
-- COMBAT DISPLAY FACTORY
--------------------------------------------------------------------------------

--- Create a new CombatDisplay component
-- @param config table: { eventBus, challengeController }
-- @return CombatDisplay instance
function M.createCombatDisplay(config)
    config = config or {}

    local display = {
        eventBus = config.eventBus or events.globalBus,
        controller = config.challengeController,

        -- Card flip animations: entityId -> { progress, cardData, startTime }
        flipAnimations = {},

        -- Defense reveal animations
        defenseReveals = {},

        -- Active glow timer
        glowTimer = 0,

        -- Layout
        cardWidth = 60,
        cardHeight = 84,
        portraitSize = 50,
        slotSpacing = 8,

        -- Engagement tracking (from action resolver)
        engagements = {},  -- { entityId -> { enemyId -> true } }

        colors = M.COLORS,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function display:init()
        -- Listen for initiative reveal
        self.eventBus:on("count_up_tick", function(data)
            -- Trigger flip animations for entities at this count
            self:triggerInitiativeFlips(data.count)
        end)

        -- Listen for defense prepared
        self.eventBus:on("defense_prepared", function(data)
            -- Could add visual feedback here
        end)

        -- Listen for defense triggered (dodge/riposte used)
        self.eventBus:on("riposte_hit", function(data)
            self:triggerDefenseReveal(data.defender, "riposte")
        end)

        -- Listen for engagement changes
        self.eventBus:on("engagement_formed", function(data)
            if data.entity1 and data.entity2 then
                self:addEngagement(data.entity1.id, data.entity2.id)
            end
        end)

        self.eventBus:on("engagement_broken", function(data)
            if data.entity1 and data.entity2 then
                self:removeEngagement(data.entity1.id, data.entity2.id)
            end
        end)

        -- Clear engagements when challenge ends
        self.eventBus:on(events.EVENTS.CHALLENGE_END, function(data)
            self.engagements = {}
        end)
    end

    --- Add engagement between two entities
    function display:addEngagement(id1, id2)
        self.engagements[id1] = self.engagements[id1] or {}
        self.engagements[id2] = self.engagements[id2] or {}
        self.engagements[id1][id2] = true
        self.engagements[id2][id1] = true
    end

    --- Remove engagement between two entities
    function display:removeEngagement(id1, id2)
        if self.engagements[id1] then
            self.engagements[id1][id2] = nil
        end
        if self.engagements[id2] then
            self.engagements[id2][id1] = nil
        end
    end

    --- Check if entity is engaged
    function display:isEngaged(entityId)
        local engaged = self.engagements[entityId]
        if not engaged then return false end
        for _ in pairs(engaged) do
            return true
        end
        return false
    end

    ----------------------------------------------------------------------------
    -- ANIMATION TRIGGERS
    ----------------------------------------------------------------------------

    --- Trigger initiative card flip for entities at a count
    function display:triggerInitiativeFlips(count)
        if not self.controller then return end

        local entities = self.controller:getEntitiesAtCount(count)
        for _, entity in ipairs(entities) do
            self.flipAnimations[entity.id] = {
                progress = 0,
                duration = M.FLIP_DURATION,
            }
        end
    end

    --- Trigger defense card reveal animation
    function display:triggerDefenseReveal(entity, defenseType)
        if not entity then return end

        self.defenseReveals[entity.id] = {
            progress = 0,
            duration = M.FLIP_DURATION,
            type = defenseType,
        }
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function display:update(dt)
        -- Update glow timer
        self.glowTimer = self.glowTimer + dt * M.GLOW_SPEED

        -- Update flip animations
        for id, anim in pairs(self.flipAnimations) do
            anim.progress = anim.progress + dt / anim.duration
            if anim.progress >= 1.0 then
                self.flipAnimations[id] = nil
            end
        end

        -- Update defense reveals
        for id, anim in pairs(self.defenseReveals) do
            anim.progress = anim.progress + dt / anim.duration
            if anim.progress >= 1.0 then
                self.defenseReveals[id] = nil
            end
        end
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    ----------------------------------------------------------------------------

    --- Draw a combatant row (portrait + initiative slot + defense slot)
    -- @param entity table: The combatant entity
    -- @param x, y number: Position
    -- @param isActive boolean: Whether this entity is currently active
    function display:drawCombatantRow(entity, x, y, isActive)
        if not love or not entity then return end

        local colors = self.colors

        -- Active entity glow background
        if isActive then
            local glowAlpha = math.sin(self.glowTimer) * 0.3 + 0.5
            love.graphics.setColor(
                colors.active_bg[1],
                colors.active_bg[2],
                colors.active_bg[3],
                glowAlpha
            )
            love.graphics.rectangle("fill",
                x - 4, y - 4,
                self.portraitSize + self.cardWidth * 2 + self.slotSpacing * 3 + 8,
                self.portraitSize + 8,
                4, 4
            )
        end

        -- Portrait
        self:drawPortrait(entity, x, y)

        -- Initiative slot (to the right of portrait)
        local initX = x + self.portraitSize + self.slotSpacing
        self:drawInitiativeSlot(entity, initX, y)

        -- Defense slot (to the right of initiative)
        local defX = initX + self.cardWidth + self.slotSpacing
        self:drawDefenseSlot(entity, defX, y)
    end

    --- Draw entity portrait
    function display:drawPortrait(entity, x, y)
        local colors = self.colors
        local isPC = entity.isPC

        -- Background color based on faction
        love.graphics.setColor(isPC and colors.pc_bg or colors.npc_bg)
        love.graphics.rectangle("fill", x, y, self.portraitSize, self.portraitSize, 3, 3)

        -- Border
        love.graphics.setColor(colors.card_border)
        love.graphics.rectangle("line", x, y, self.portraitSize, self.portraitSize, 3, 3)

        -- Engagement indicator (crossed swords icon in corner)
        if entity.id and self:isEngaged(entity.id) then
            -- Draw a small crossed swords indicator
            love.graphics.setColor(0.9, 0.4, 0.3, 1.0)
            local ix, iy = x + self.portraitSize - 12, y + 2
            love.graphics.setLineWidth(2)
            love.graphics.line(ix, iy, ix + 10, iy + 10)
            love.graphics.line(ix + 10, iy, ix, iy + 10)
            love.graphics.setLineWidth(1)
        end

        -- Name (truncated)
        local name = entity.name or "???"
        if #name > 6 then name = string.sub(name, 1, 5) .. "." end
        love.graphics.setColor(colors.text_light)
        love.graphics.print(name, x + 3, y + self.portraitSize - 14)

        -- Zone indicator (small text)
        if entity.zone then
            love.graphics.setColor(0.6, 0.6, 0.6, 0.8)
            local zoneText = string.sub(entity.zone, 1, 4)
            love.graphics.print(zoneText, x + 3, y + 2)
        end

        -- Death's door / dead indicator
        if entity.conditions then
            if entity.conditions.dead then
                love.graphics.setColor(0.8, 0.2, 0.2, 0.8)
                love.graphics.setLineWidth(3)
                love.graphics.line(x, y, x + self.portraitSize, y + self.portraitSize)
                love.graphics.line(x + self.portraitSize, y, x, y + self.portraitSize)
                love.graphics.setLineWidth(1)
            elseif entity.conditions.deaths_door then
                love.graphics.setColor(0.8, 0.2, 0.2, 1)
                love.graphics.setLineWidth(2)
                love.graphics.rectangle("line", x - 1, y - 1, self.portraitSize + 2, self.portraitSize + 2, 4, 4)
                love.graphics.setLineWidth(1)
            end
        end
    end

    --- Draw initiative slot
    function display:drawInitiativeSlot(entity, x, y)
        local colors = self.colors
        local slot = self.controller and self.controller:getInitiativeSlot(entity.id)

        -- Mini card dimensions
        local cardW = self.cardWidth
        local cardH = self.portraitSize  -- Match portrait height

        if not slot then
            -- No initiative submitted yet - empty slot
            love.graphics.setColor(0.2, 0.2, 0.2, 0.5)
            love.graphics.rectangle("line", x, y, cardW, cardH, 3, 3)
            love.graphics.setColor(0.4, 0.4, 0.4, 0.5)
            love.graphics.print("Init", x + 15, y + cardH/2 - 6)
            return
        end

        -- Check for flip animation
        local flipAnim = self.flipAnimations[entity.id]
        local flipProgress = flipAnim and flipAnim.progress or (slot.revealed and 1.0 or 0.0)

        -- Draw card with flip effect
        self:drawCard(x, y, cardW, cardH, slot.card, slot.revealed, flipProgress)
    end

    --- Draw defense slot
    function display:drawDefenseSlot(entity, x, y)
        local colors = self.colors

        -- Mini card dimensions
        local cardW = self.cardWidth
        local cardH = self.portraitSize

        -- Check if entity has a defense prepared
        local hasDefense = entity.hasDefense and entity:hasDefense()
        local defense = hasDefense and entity:getDefense()

        -- Check for reveal animation
        local revealAnim = self.defenseReveals[entity.id]
        local revealProgress = revealAnim and revealAnim.progress or 0

        if not hasDefense and revealProgress == 0 then
            -- Empty defense slot
            love.graphics.setColor(0.2, 0.2, 0.2, 0.3)
            love.graphics.rectangle("line", x, y, cardW, cardH, 3, 3)
            love.graphics.setColor(0.3, 0.3, 0.3, 0.4)
            love.graphics.print("Def", x + 17, y + cardH/2 - 6)
            return
        end

        -- Defense is prepared - draw facedown card
        if revealProgress > 0 then
            -- Being revealed
            local fakeCard = { value = defense and defense.value or "?", name = defense and defense.type or "Defense" }
            self:drawCard(x, y, cardW, cardH, fakeCard, true, revealProgress)
        else
            -- Facedown
            self:drawCard(x, y, cardW, cardH, nil, false, 0)

            -- Add subtle icon hint based on known type (if revealed earlier)
            -- For now, just show "?"
            love.graphics.setColor(colors.text_light)
            love.graphics.print("?", x + cardW/2 - 4, y + cardH/2 - 6)
        end
    end

    --- Draw a card (facedown or face up with flip animation)
    -- @param x, y number: Position
    -- @param w, h number: Dimensions
    -- @param card table: Card data (or nil for facedown)
    -- @param revealed boolean: Whether card is face up
    -- @param flipProgress number: 0.0 (facedown) to 1.0 (face up)
    function display:drawCard(x, y, w, h, card, revealed, flipProgress)
        local colors = self.colors

        -- Calculate flip effect (horizontal scale)
        local midFlip = 0.5
        local isFaceUp = flipProgress >= midFlip
        local scaleX = math.abs(flipProgress - midFlip) * 2

        -- Prevent zero scale
        scaleX = math.max(scaleX, 0.1)

        -- Adjust x for centered flip
        local drawX = x + (w * (1 - scaleX)) / 2
        local drawW = w * scaleX

        if isFaceUp and revealed and card then
            -- Draw face up card
            love.graphics.setColor(colors.card_face)
            love.graphics.rectangle("fill", drawX, y, drawW, h, 2, 2)

            -- Border
            love.graphics.setColor(colors.card_border)
            love.graphics.rectangle("line", drawX, y, drawW, h, 2, 2)

            -- Card value (if room)
            if drawW > 20 then
                love.graphics.setColor(colors.text_dark)
                local valueStr = tostring(card.value or "?")
                love.graphics.print(valueStr, drawX + drawW/2 - 6, y + h/2 - 8)
            end
        else
            -- Draw facedown card (back)
            love.graphics.setColor(colors.card_back)
            love.graphics.rectangle("fill", drawX, y, drawW, h, 2, 2)

            -- Border
            love.graphics.setColor(colors.card_border)
            love.graphics.rectangle("line", drawX, y, drawW, h, 2, 2)

            -- Pattern on back (simple cross-hatch)
            if drawW > 15 then
                love.graphics.setColor(colors.card_border[1], colors.card_border[2], colors.card_border[3], 0.5)
                love.graphics.setLineWidth(1)
                love.graphics.line(drawX + 5, y + 5, drawX + drawW - 5, y + h - 5)
                love.graphics.line(drawX + drawW - 5, y + 5, drawX + 5, y + h - 5)
            end
        end
    end

    --- Draw the count-up indicator bar
    -- @param x, y number: Position
    -- @param width number: Total width
    -- @param currentCount number: Current count (1-14)
    -- @param maxCount number: Maximum count (14)
    function display:drawCountUpBar(x, y, width, currentCount, maxCount)
        local colors = self.colors
        maxCount = maxCount or 14

        local segmentWidth = width / maxCount
        local segmentHeight = 20

        for i = 1, maxCount do
            local segX = x + (i - 1) * segmentWidth

            -- Background
            if i < currentCount then
                -- Past
                love.graphics.setColor(0.3, 0.3, 0.3, 0.8)
            elseif i == currentCount then
                -- Current (pulsing)
                local pulse = math.sin(self.glowTimer) * 0.2 + 0.8
                love.graphics.setColor(colors.active_glow[1] * pulse, colors.active_glow[2] * pulse, colors.active_glow[3], 1)
            else
                -- Future
                love.graphics.setColor(0.2, 0.2, 0.2, 0.5)
            end

            love.graphics.rectangle("fill", segX + 1, y, segmentWidth - 2, segmentHeight, 2, 2)

            -- Border
            love.graphics.setColor(0.4, 0.4, 0.4, 0.8)
            love.graphics.rectangle("line", segX + 1, y, segmentWidth - 2, segmentHeight, 2, 2)

            -- Number
            love.graphics.setColor(colors.text_light)
            local numStr = i == 1 and "A" or (i == 11 and "J" or (i == 12 and "Q" or (i == 13 and "K" or (i == 14 and "A" or tostring(i)))))
            -- Simplify: just use numbers
            love.graphics.print(tostring(i), segX + segmentWidth/2 - 4, y + 3)
        end
    end

    return display
end

return M

```

---

## File: src/ui/command_board.lua

```lua
-- command_board.lua
-- Categorized Command Board for Majesty
-- Ticket S6.2: Suit-grouped grid of actions
--
-- Displays a grid of actions organized by suit when a card is selected.
-- Enforces suit restrictions during Minor Action windows.

local events = require('logic.events')
local action_registry = require('data.action_registry')

local M = {}

--------------------------------------------------------------------------------
-- COLORS
--------------------------------------------------------------------------------
M.COLORS = {
    -- Background
    board_bg        = { 0.15, 0.12, 0.10, 0.95 },
    board_border    = { 0.40, 0.35, 0.30, 1.0 },

    -- Column headers
    header_swords   = { 0.65, 0.25, 0.25, 1.0 },
    header_pentacles= { 0.25, 0.55, 0.30, 1.0 },
    header_cups     = { 0.25, 0.40, 0.70, 1.0 },
    header_wands    = { 0.70, 0.50, 0.20, 1.0 },
    header_misc     = { 0.45, 0.42, 0.40, 1.0 },
    header_text     = { 0.95, 0.92, 0.88, 1.0 },

    -- Action buttons
    button_enabled  = { 0.30, 0.28, 0.25, 1.0 },
    button_disabled = { 0.20, 0.18, 0.16, 0.6 },
    button_hover    = { 0.40, 0.38, 0.35, 1.0 },
    button_selected = { 0.50, 0.45, 0.30, 1.0 },
    button_border   = { 0.50, 0.45, 0.40, 1.0 },
    button_text     = { 0.90, 0.88, 0.82, 1.0 },
    button_text_dis = { 0.50, 0.48, 0.45, 0.6 },

    -- Tooltip
    tooltip_bg      = { 0.10, 0.08, 0.06, 0.95 },
    tooltip_border  = { 0.60, 0.55, 0.45, 1.0 },
    tooltip_text    = { 0.95, 0.92, 0.85, 1.0 },
    tooltip_value   = { 0.90, 0.80, 0.40, 1.0 },
}

--------------------------------------------------------------------------------
-- LAYOUT CONSTANTS
--------------------------------------------------------------------------------
M.COLUMN_WIDTH = 130
M.HEADER_HEIGHT = 30
M.BUTTON_HEIGHT = 36
M.BUTTON_PADDING = 4
M.BOARD_PADDING = 12
M.TOOLTIP_WIDTH = 220
M.TOOLTIP_LINE_HEIGHT = 18

--------------------------------------------------------------------------------
-- COMMAND BOARD FACTORY
--------------------------------------------------------------------------------

--- Create a new CommandBoard
-- @param config table: { eventBus, challengeController }
-- @return CommandBoard instance
function M.createCommandBoard(config)
    config = config or {}

    local board = {
        eventBus = config.eventBus or events.globalBus,
        challengeController = config.challengeController,

        -- State
        isVisible = false,
        selectedCard = nil,
        selectedEntity = nil,
        isPrimaryTurn = true,  -- vs Minor Window

        -- Layout
        x = 0,
        y = 0,
        width = 0,
        height = 0,

        -- Interaction
        hoveredAction = nil,
        buttons = {},  -- { action, x, y, width, height, enabled }

        -- Colors
        colors = M.COLORS,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function board:init()
        -- Listen for card selection
        self.eventBus:on("card_selected", function(data)
            if data.card and data.entity then
                self:show(data.card, data.entity, data.isPrimaryTurn)
            end
        end)

        -- Listen for card deselection
        self.eventBus:on("card_deselected", function()
            self:hide()
        end)

        -- Listen for challenge state changes
        self.eventBus:on("challenge_state_changed", function(data)
            if data.newState == "minor_window" then
                self.isPrimaryTurn = false
            elseif data.newState == "awaiting_action" then
                self.isPrimaryTurn = true
            end
        end)

        -- Listen for challenge end
        self.eventBus:on(events.EVENTS.CHALLENGE_END, function()
            self:hide()
        end)
    end

    ----------------------------------------------------------------------------
    -- VISIBILITY
    ----------------------------------------------------------------------------

    --- Show the command board for a selected card
    function board:show(card, entity, isPrimaryTurn)
        self.isVisible = true
        self.selectedCard = card
        self.selectedEntity = entity
        self.isPrimaryTurn = isPrimaryTurn ~= false  -- Default true

        -- Calculate position (center of screen area)
        local screenW, screenH = love.graphics.getDimensions()
        local numColumns = 5  -- Swords, Pentacles, Cups, Wands, Misc
        self.width = numColumns * M.COLUMN_WIDTH + M.BOARD_PADDING * 2 + (numColumns - 1) * M.BUTTON_PADDING
        self.height = self:calculateHeight()
        self.x = (screenW - self.width) / 2
        self.y = (screenH - self.height) / 2 - 50  -- Slightly above center

        -- Build button layout
        self:buildButtons()
    end

    function board:hide()
        self.isVisible = false
        self.selectedCard = nil
        self.selectedEntity = nil
        self.hoveredAction = nil
        self.buttons = {}
    end

    --- Calculate total board height based on max column length
    function board:calculateHeight()
        local maxActions = 0
        local suits = { action_registry.SUITS.SWORDS, action_registry.SUITS.PENTACLES,
                        action_registry.SUITS.CUPS, action_registry.SUITS.WANDS,
                        action_registry.SUITS.MISC }

        for _, suit in ipairs(suits) do
            local actions = action_registry.getActionsForSuit(suit)
            maxActions = math.max(maxActions, #actions)
        end

        return M.BOARD_PADDING * 2 + M.HEADER_HEIGHT +
               maxActions * (M.BUTTON_HEIGHT + M.BUTTON_PADDING) + M.BUTTON_PADDING
    end

    --- Build the button layout
    function board:buildButtons()
        self.buttons = {}

        local suits = {
            { id = action_registry.SUITS.SWORDS, name = "Swords", color = self.colors.header_swords },
            { id = action_registry.SUITS.PENTACLES, name = "Pentacles", color = self.colors.header_pentacles },
            { id = action_registry.SUITS.CUPS, name = "Cups", color = self.colors.header_cups },
            { id = action_registry.SUITS.WANDS, name = "Wands", color = self.colors.header_wands },
            { id = action_registry.SUITS.MISC, name = "Misc", color = self.colors.header_misc },
        }

        local cardSuit = action_registry.cardSuitToActionSuit(self.selectedCard.suit)

        for col, suitInfo in ipairs(suits) do
            local colX = self.x + M.BOARD_PADDING + (col - 1) * (M.COLUMN_WIDTH + M.BUTTON_PADDING)
            local actions = action_registry.getActionsForSuit(suitInfo.id)

            -- Column is enabled if:
            -- 1. It's the primary turn (all columns enabled)
            -- 2. It's minor window AND this column matches the card's suit
            local columnEnabled = self.isPrimaryTurn or (suitInfo.id == cardSuit)

            -- Misc column is disabled during minor window
            if suitInfo.id == action_registry.SUITS.MISC and not self.isPrimaryTurn then
                columnEnabled = false
            end

            for i, action in ipairs(actions) do
                local btnY = self.y + M.BOARD_PADDING + M.HEADER_HEIGHT + M.BUTTON_PADDING +
                             (i - 1) * (M.BUTTON_HEIGHT + M.BUTTON_PADDING)

                local enabled = columnEnabled

                -- Additional requirements check
                if enabled and action.requiresWeaponType then
                    local entity = self.selectedEntity
                    if not entity or not entity.weapon or entity.weapon.type ~= action.requiresWeaponType then
                        enabled = false
                    end
                end

                self.buttons[#self.buttons + 1] = {
                    action = action,
                    x = colX,
                    y = btnY,
                    width = M.COLUMN_WIDTH,
                    height = M.BUTTON_HEIGHT,
                    enabled = enabled,
                    suitColor = suitInfo.color,
                }
            end

            -- Store column header info
            self.buttons["header_" .. col] = {
                x = colX,
                y = self.y + M.BOARD_PADDING,
                width = M.COLUMN_WIDTH,
                height = M.HEADER_HEIGHT,
                name = suitInfo.name,
                color = suitInfo.color,
                enabled = columnEnabled,
            }
        end
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function board:update(dt)
        -- Animation updates if needed
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    ----------------------------------------------------------------------------

    function board:draw()
        if not love or not self.isVisible then return end

        -- Draw board background
        love.graphics.setColor(self.colors.board_bg)
        love.graphics.rectangle("fill", self.x, self.y, self.width, self.height, 8, 8)

        -- Draw board border
        love.graphics.setColor(self.colors.board_border)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", self.x, self.y, self.width, self.height, 8, 8)
        love.graphics.setLineWidth(1)

        -- Draw title
        love.graphics.setColor(self.colors.header_text)
        local title = self.isPrimaryTurn and "Choose Action (Primary Turn)" or "Choose Minor Action"
        love.graphics.printf(title, self.x, self.y - 25, self.width, "center")

        -- Draw column headers
        for i = 1, 5 do
            local header = self.buttons["header_" .. i]
            if header then
                self:drawColumnHeader(header)
            end
        end

        -- Draw action buttons
        for _, btn in ipairs(self.buttons) do
            if btn.action then
                self:drawActionButton(btn)
            end
        end

        -- Draw tooltip
        if self.hoveredAction then
            self:drawTooltip()
        end
    end

    --- Draw a column header
    function board:drawColumnHeader(header)
        local alpha = header.enabled and 1.0 or 0.4

        -- Header background
        love.graphics.setColor(header.color[1], header.color[2], header.color[3], alpha)
        love.graphics.rectangle("fill", header.x, header.y, header.width, header.height, 4, 4)

        -- Header text
        love.graphics.setColor(self.colors.header_text[1], self.colors.header_text[2],
                               self.colors.header_text[3], alpha)
        love.graphics.printf(header.name, header.x, header.y + 7, header.width, "center")
    end

    --- Draw an action button
    function board:drawActionButton(btn)
        local isHovered = (self.hoveredAction == btn.action)

        -- Button background
        local bgColor
        if not btn.enabled then
            bgColor = self.colors.button_disabled
        elseif isHovered then
            bgColor = self.colors.button_hover
        else
            bgColor = self.colors.button_enabled
        end
        love.graphics.setColor(bgColor)
        love.graphics.rectangle("fill", btn.x, btn.y, btn.width, btn.height, 4, 4)

        -- Button border (tinted by suit)
        if btn.enabled then
            love.graphics.setColor(btn.suitColor[1], btn.suitColor[2], btn.suitColor[3], 0.8)
        else
            love.graphics.setColor(self.colors.button_border[1], self.colors.button_border[2],
                                   self.colors.button_border[3], 0.3)
        end
        love.graphics.setLineWidth(btn.enabled and 2 or 1)
        love.graphics.rectangle("line", btn.x, btn.y, btn.width, btn.height, 4, 4)
        love.graphics.setLineWidth(1)

        -- Button text
        local textColor = btn.enabled and self.colors.button_text or self.colors.button_text_dis
        love.graphics.setColor(textColor)

        -- Truncate name if too long
        local displayName = btn.action.name
        if #displayName > 14 then
            displayName = displayName:sub(1, 12) .. ".."
        end
        love.graphics.printf(displayName, btn.x + 4, btn.y + 10, btn.width - 8, "center")
    end

    --- Draw tooltip for hovered action
    function board:drawTooltip()
        local action = self.hoveredAction
        if not action then return end

        local mx, my = love.mouse.getPosition()

        -- Build tooltip content
        local lines = {}
        lines[#lines + 1] = { text = action.name, color = self.colors.tooltip_text }
        lines[#lines + 1] = { text = "", color = self.colors.tooltip_text }  -- Spacer
        lines[#lines + 1] = { text = action.description, color = self.colors.tooltip_text, wrap = true }

        -- Calculate total value
        if action.attribute and self.selectedEntity then
            lines[#lines + 1] = { text = "", color = self.colors.tooltip_text }  -- Spacer
            local cardVal = self.selectedCard.value or 0
            local attrVal = self.selectedEntity[action.attribute] or 0
            local total = cardVal + attrVal
            local attrName = action.attribute:sub(1, 1):upper() .. action.attribute:sub(2)
            local calcText = string.format("Card (%d) + %s (%d) = %d", cardVal, attrName, attrVal, total)
            lines[#lines + 1] = { text = calcText, color = self.colors.tooltip_value }
        elseif not action.attribute then
            lines[#lines + 1] = { text = "", color = self.colors.tooltip_text }
            lines[#lines + 1] = { text = "Face value only", color = self.colors.tooltip_value }
        end

        -- Calculate tooltip height
        local tooltipHeight = M.BOARD_PADDING * 2
        for _, line in ipairs(lines) do
            if line.wrap then
                -- Estimate wrapped text height
                local textWidth = M.TOOLTIP_WIDTH - M.BOARD_PADDING * 2
                local _, wrappedLines = love.graphics.getFont():getWrap(line.text, textWidth)
                tooltipHeight = tooltipHeight + #wrappedLines * M.TOOLTIP_LINE_HEIGHT
            else
                tooltipHeight = tooltipHeight + M.TOOLTIP_LINE_HEIGHT
            end
        end

        -- Position tooltip (avoid going off screen)
        local tooltipX = mx + 15
        local tooltipY = my + 15
        local screenW, screenH = love.graphics.getDimensions()

        if tooltipX + M.TOOLTIP_WIDTH > screenW then
            tooltipX = mx - M.TOOLTIP_WIDTH - 5
        end
        if tooltipY + tooltipHeight > screenH then
            tooltipY = my - tooltipHeight - 5
        end

        -- Draw tooltip background
        love.graphics.setColor(self.colors.tooltip_bg)
        love.graphics.rectangle("fill", tooltipX, tooltipY, M.TOOLTIP_WIDTH, tooltipHeight, 4, 4)

        -- Draw tooltip border
        love.graphics.setColor(self.colors.tooltip_border)
        love.graphics.rectangle("line", tooltipX, tooltipY, M.TOOLTIP_WIDTH, tooltipHeight, 4, 4)

        -- Draw tooltip text
        local textY = tooltipY + M.BOARD_PADDING
        for _, line in ipairs(lines) do
            love.graphics.setColor(line.color)
            if line.wrap then
                love.graphics.printf(line.text, tooltipX + M.BOARD_PADDING, textY,
                                     M.TOOLTIP_WIDTH - M.BOARD_PADDING * 2, "left")
                local _, wrappedLines = love.graphics.getFont():getWrap(line.text, M.TOOLTIP_WIDTH - M.BOARD_PADDING * 2)
                textY = textY + #wrappedLines * M.TOOLTIP_LINE_HEIGHT
            else
                love.graphics.print(line.text, tooltipX + M.BOARD_PADDING, textY)
                textY = textY + M.TOOLTIP_LINE_HEIGHT
            end
        end
    end

    ----------------------------------------------------------------------------
    -- INPUT HANDLING
    ----------------------------------------------------------------------------

    function board:mousepressed(x, y, button)
        if not self.isVisible then return false end
        if button ~= 1 then return false end

        -- Check if clicking on a button
        for _, btn in ipairs(self.buttons) do
            if btn.action and btn.enabled then
                if x >= btn.x and x <= btn.x + btn.width and
                   y >= btn.y and y <= btn.y + btn.height then
                    -- Emit action selection
                    self.eventBus:emit("action_selected", {
                        action = btn.action,
                        card = self.selectedCard,
                        entity = self.selectedEntity,
                        isPrimaryTurn = self.isPrimaryTurn,
                    })
                    self:hide()
                    return true
                end
            end
        end

        -- Clicking outside hides the board
        if x < self.x or x > self.x + self.width or
           y < self.y or y > self.y + self.height then
            self:hide()
            return true
        end

        return false
    end

    function board:mousemoved(x, y, dx, dy)
        if not self.isVisible then return end

        -- Update hovered action
        self.hoveredAction = nil
        for _, btn in ipairs(self.buttons) do
            if btn.action and btn.enabled then
                if x >= btn.x and x <= btn.x + btn.width and
                   y >= btn.y and y <= btn.y + btn.height then
                    self.hoveredAction = btn.action
                    break
                end
            end
        end
    end

    function board:keypressed(key)
        if not self.isVisible then return false end

        -- ESC to close
        if key == "escape" then
            self:hide()
            return true
        end

        return false
    end

    return board
end

return M

```

---

## File: src/ui/floating_text.lua

```lua
-- floating_text.lua
-- Floating Text System for Majesty
-- Ticket S10.2: Damage numbers and combat feedback
--
-- Creates animated text that floats upward and fades out.
-- Used for damage numbers, healing, status effects, etc.

local M = {}

--------------------------------------------------------------------------------
-- TEXT TYPES & COLORS
--------------------------------------------------------------------------------
M.TYPES = {
    DAMAGE        = "damage",
    HEAL          = "heal",
    BLOCK         = "block",
    MISS          = "miss",
    CRITICAL      = "critical",
    CONDITION     = "condition",
    BONUS         = "bonus",
    INFO          = "info",
}

M.COLORS = {
    [M.TYPES.DAMAGE]    = { 0.90, 0.30, 0.25, 1.0 },   -- Red
    [M.TYPES.HEAL]      = { 0.35, 0.75, 0.40, 1.0 },   -- Green
    [M.TYPES.BLOCK]     = { 0.70, 0.65, 0.55, 1.0 },   -- Grey/bronze
    [M.TYPES.MISS]      = { 0.60, 0.60, 0.60, 1.0 },   -- Grey
    [M.TYPES.CRITICAL]  = { 1.00, 0.85, 0.20, 1.0 },   -- Gold
    [M.TYPES.CONDITION] = { 0.80, 0.60, 0.90, 1.0 },   -- Purple
    [M.TYPES.BONUS]     = { 0.50, 0.80, 0.95, 1.0 },   -- Blue
    [M.TYPES.INFO]      = { 0.90, 0.90, 0.85, 1.0 },   -- White
}

--------------------------------------------------------------------------------
-- ANIMATION CONSTANTS
--------------------------------------------------------------------------------
M.FLOAT_SPEED = 50      -- Pixels per second
M.DURATION = 1.2        -- Seconds before fully faded
M.FADE_START = 0.6      -- When to start fading (percentage of duration)
M.SCALE_BOUNCE = 0.15   -- Initial scale bounce amount
M.BOUNCE_DURATION = 0.2 -- Duration of scale bounce

--------------------------------------------------------------------------------
-- FLOATING TEXT MANAGER
--------------------------------------------------------------------------------

local manager = {
    texts = {},  -- Array of active floating texts
}

--------------------------------------------------------------------------------
-- TEXT SPAWNING
--------------------------------------------------------------------------------

--- Spawn a floating text
-- @param text string: The text to display
-- @param x number: Starting X position (screen coordinates)
-- @param y number: Starting Y position (screen coordinates)
-- @param textType string: One of TYPES constants
-- @param options table: { scale, duration, floatSpeed }
function M.spawn(text, x, y, textType, options)
    options = options or {}

    local floatingText = {
        text = text,
        x = x,
        y = y,
        startY = y,
        textType = textType or M.TYPES.INFO,
        color = M.COLORS[textType] or M.COLORS[M.TYPES.INFO],

        -- Animation state
        timer = 0,
        duration = options.duration or M.DURATION,
        floatSpeed = options.floatSpeed or M.FLOAT_SPEED,
        scale = 1.0 + M.SCALE_BOUNCE,
        alpha = 1.0,

        -- Visual options
        baseScale = options.scale or 1.0,
        outline = options.outline ~= false,  -- Default true
    }

    manager.texts[#manager.texts + 1] = floatingText

    return floatingText
end

--- Spawn damage number at entity position
-- @param amount number: Damage amount
-- @param entityX number: Entity's X position
-- @param entityY number: Entity's Y position
-- @param isCritical boolean: Is this a critical hit?
function M.spawnDamage(amount, entityX, entityY, isCritical)
    local textType = isCritical and M.TYPES.CRITICAL or M.TYPES.DAMAGE
    local text = "-" .. tostring(amount)
    if isCritical then
        text = "CRIT! " .. text
    end

    -- Add some horizontal scatter
    local offsetX = (math.random() - 0.5) * 30
    M.spawn(text, entityX + offsetX, entityY - 20, textType, {
        scale = isCritical and 1.3 or 1.0,
    })
end

--- Spawn healing number
function M.spawnHeal(amount, entityX, entityY)
    local text = "+" .. tostring(amount)
    local offsetX = (math.random() - 0.5) * 30
    M.spawn(text, entityX + offsetX, entityY - 20, M.TYPES.HEAL)
end

--- Spawn block indicator
function M.spawnBlock(entityX, entityY)
    M.spawn("BLOCK", entityX, entityY - 20, M.TYPES.BLOCK)
end

--- Spawn miss indicator
function M.spawnMiss(entityX, entityY)
    M.spawn("MISS", entityX, entityY - 20, M.TYPES.MISS)
end

--- Spawn condition text
function M.spawnCondition(conditionName, entityX, entityY)
    local text = string.upper(conditionName)
    M.spawn(text, entityX, entityY - 25, M.TYPES.CONDITION)
end

--- Spawn bonus/modifier text
function M.spawnBonus(text, entityX, entityY)
    M.spawn(text, entityX, entityY - 30, M.TYPES.BONUS)
end

--------------------------------------------------------------------------------
-- UPDATE & DRAW
--------------------------------------------------------------------------------

--- Update all floating texts
-- @param dt number: Delta time
function M.update(dt)
    -- Update each text and remove expired ones
    local i = 1
    while i <= #manager.texts do
        local ft = manager.texts[i]
        ft.timer = ft.timer + dt

        -- Float upward
        ft.y = ft.startY - (ft.timer * ft.floatSpeed)

        -- Scale bounce (shrink back to normal)
        if ft.timer < M.BOUNCE_DURATION then
            local bounceProgress = ft.timer / M.BOUNCE_DURATION
            ft.scale = ft.baseScale + M.SCALE_BOUNCE * (1 - bounceProgress)
        else
            ft.scale = ft.baseScale
        end

        -- Fade out
        local fadeStart = ft.duration * M.FADE_START
        if ft.timer > fadeStart then
            local fadeProgress = (ft.timer - fadeStart) / (ft.duration - fadeStart)
            ft.alpha = 1 - fadeProgress
        end

        -- Remove if expired
        if ft.timer >= ft.duration then
            table.remove(manager.texts, i)
        else
            i = i + 1
        end
    end
end

--- Draw all floating texts
function M.draw()
    if not love then return end

    for _, ft in ipairs(manager.texts) do
        local r, g, b = ft.color[1], ft.color[2], ft.color[3]
        local a = ft.alpha

        -- Draw outline for readability
        if ft.outline then
            love.graphics.setColor(0, 0, 0, a * 0.7)
            for ox = -1, 1 do
                for oy = -1, 1 do
                    if ox ~= 0 or oy ~= 0 then
                        love.graphics.print(
                            ft.text,
                            ft.x + ox,
                            ft.y + oy,
                            0,
                            ft.scale, ft.scale
                        )
                    end
                end
            end
        end

        -- Draw main text
        love.graphics.setColor(r, g, b, a)
        love.graphics.print(ft.text, ft.x, ft.y, 0, ft.scale, ft.scale)
    end
end

--- Clear all floating texts
function M.clear()
    manager.texts = {}
end

--- Get count of active texts
function M.getCount()
    return #manager.texts
end

return M

```

---

## File: src/ui/focus_menu.lua

```lua
-- focus_menu.lua
-- Focus Menu (Scrutiny UI) for Majesty
-- Ticket T2_13: Menu for choosing scrutiny focus actions
--
-- Design:
-- - Appears near mouse when POI is clicked
-- - Populated from POI's scrutiny verbs (T2_8)
-- - Locks UI until choice is made or menu closed
-- - Triggers time penalty animation on choice

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- DEFAULT STYLES
--------------------------------------------------------------------------------
M.STYLES = {
    background      = { 0.15, 0.15, 0.18, 0.95 },
    border          = { 0.4, 0.4, 0.45, 1.0 },
    button_normal   = { 0.2, 0.2, 0.25, 1.0 },
    button_hover    = { 0.3, 0.5, 0.6, 1.0 },
    button_pressed  = { 0.2, 0.4, 0.5, 1.0 },
    text_normal     = { 0.9, 0.9, 0.85, 1.0 },
    text_hover      = { 1.0, 1.0, 1.0, 1.0 },
    title           = { 0.7, 0.85, 1.0, 1.0 },
}

--------------------------------------------------------------------------------
-- FOCUS MENU FACTORY
--------------------------------------------------------------------------------

--- Create a new FocusMenu
-- @param config table: { inputManager, roomManager, eventBus, font }
-- @return FocusMenu instance
function M.createFocusMenu(config)
    config = config or {}

    local menu = {
        -- References
        inputManager = config.inputManager,
        roomManager  = config.roomManager,
        eventBus     = config.eventBus or events.globalBus,

        -- Font
        font = config.font,

        -- State
        isOpen       = false,
        x            = 0,
        y            = 0,
        width        = 200,
        height       = 0,  -- Calculated based on options

        -- Current POI
        poiId        = nil,
        poiData      = nil,
        roomId       = nil,

        -- Menu options
        options      = {},  -- Array of { verb, description, callback }
        hoveredIndex = nil,
        pressedIndex = nil,

        -- Visual
        styles       = config.styles or M.STYLES,
        buttonHeight = config.buttonHeight or 32,
        padding      = config.padding or 8,
        titleHeight  = config.titleHeight or 28,

        -- Animation
        animationTime = 0,
        fadeIn        = true,
        fadeAlpha     = 0,
    }

    ----------------------------------------------------------------------------
    -- OPENING / CLOSING
    ----------------------------------------------------------------------------

    --- Open the menu for a POI
    -- @param poiId string: The POI identifier
    -- @param poiData table: POI data (from feature)
    -- @param roomId string: Current room
    -- @param screenX, screenY number: Where to position menu
    function menu:open(poiId, poiData, roomId, screenX, screenY)
        self.isOpen = true
        self.poiId = poiId
        self.poiData = poiData
        self.roomId = roomId

        -- Position menu near click, but keep on screen
        self.x = screenX
        self.y = screenY

        -- Get scrutiny verbs from room manager
        self.options = {}
        if self.roomManager then
            local verbs = self.roomManager:getScrutinyVerbs(poiData)
            for i, verbData in ipairs(verbs) do
                self.options[i] = {
                    verb = verbData.verb,
                    description = verbData.desc or verbData.description or verbData.verb,
                    callback = function()
                        self:selectOption(verbData.verb)
                    end,
                }
            end
        end

        -- Add "Cancel" option
        self.options[#self.options + 1] = {
            verb = "cancel",
            description = "Cancel",
            callback = function()
                self:close()
            end,
        }

        -- Calculate height based on options
        self.height = self.titleHeight + (self.buttonHeight * #self.options) + (self.padding * 2)

        -- Adjust position to keep on screen
        self:clampToScreen()

        -- Lock UI
        if self.inputManager then
            self.inputManager:lockUI(self)
        end

        -- Reset animation
        self.animationTime = 0
        self.fadeIn = true
        self.fadeAlpha = 0

        -- Emit event
        self.eventBus:emit(events.EVENTS.MENU_OPENED, {
            menuType = "focus",
            poiId = poiId,
        })
    end

    --- Close the menu
    function menu:close()
        if not self.isOpen then return end

        self.isOpen = false
        self.poiId = nil
        self.poiData = nil
        self.options = {}
        self.hoveredIndex = nil

        -- Unlock UI
        if self.inputManager then
            self.inputManager:unlockUI()
        end

        -- Emit event
        self.eventBus:emit(events.EVENTS.MENU_CLOSED, {
            menuType = "focus",
        })
    end

    --- Keep menu on screen
    function menu:clampToScreen()
        if not love then return end

        local screenW, screenH = love.graphics.getDimensions()

        -- Clamp X
        if self.x + self.width > screenW then
            self.x = screenW - self.width - 10
        end
        if self.x < 10 then
            self.x = 10
        end

        -- Clamp Y
        if self.y + self.height > screenH then
            self.y = screenH - self.height - 10
        end
        if self.y < 10 then
            self.y = 10
        end
    end

    ----------------------------------------------------------------------------
    -- SELECTION
    ----------------------------------------------------------------------------

    --- Handle option selection
    function menu:selectOption(verb)
        if verb == "cancel" then
            self:close()
            return
        end

        -- Get POI info at scrutiny level
        local result = nil
        if self.roomManager then
            result = self.roomManager:getPOIInfo(self.roomId, self.poiId, "scrutinize", verb)
        end

        -- Emit selection event
        self.eventBus:emit(events.EVENTS.SCRUTINY_SELECTED, {
            poiId = self.poiId,
            roomId = self.roomId,
            verb = verb,
            result = result,
        })

        -- Close menu
        self:close()
    end

    ----------------------------------------------------------------------------
    -- INPUT HANDLING
    ----------------------------------------------------------------------------

    --- Handle mouse press
    function menu:onMousePressed(x, y, button)
        if not self.isOpen or button ~= 1 then return false end

        -- Check if click is inside menu
        if not self:isPointInside(x, y) then
            self:close()
            return true
        end

        -- Check which button was pressed
        local index = self:getButtonAt(x, y)
        if index then
            self.pressedIndex = index
        end

        return true  -- Consumed the input
    end

    --- Handle mouse release
    function menu:onMouseReleased(x, y, button)
        if not self.isOpen or button ~= 1 then return false end

        local index = self:getButtonAt(x, y)

        -- If released on same button that was pressed, activate it
        if index and index == self.pressedIndex then
            local option = self.options[index]
            if option and option.callback then
                option.callback()
            end
        end

        self.pressedIndex = nil
        return true
    end

    --- Handle mouse movement
    function menu:onMouseMoved(x, y)
        if not self.isOpen then return end

        self.hoveredIndex = self:getButtonAt(x, y)
    end

    --- Check if point is inside menu
    function menu:isPointInside(x, y)
        return x >= self.x and x <= self.x + self.width and
               y >= self.y and y <= self.y + self.height
    end

    --- Get button index at position
    function menu:getButtonAt(x, y)
        if not self:isPointInside(x, y) then
            return nil
        end

        -- Check each button
        local buttonY = self.y + self.titleHeight + self.padding
        for i, _ in ipairs(self.options) do
            if y >= buttonY and y < buttonY + self.buttonHeight then
                return i
            end
            buttonY = buttonY + self.buttonHeight
        end

        return nil
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    --- Update the menu
    function menu:update(dt)
        if not self.isOpen then return end

        -- Fade in animation
        if self.fadeIn then
            self.animationTime = self.animationTime + dt
            self.fadeAlpha = math.min(1.0, self.animationTime * 5)  -- Fade in over 0.2s

            if self.fadeAlpha >= 1.0 then
                self.fadeIn = false
            end
        end
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    ----------------------------------------------------------------------------

    --- Draw the menu
    function menu:draw()
        if not self.isOpen or not love then return end

        local alpha = self.fadeAlpha

        -- Draw background with border
        love.graphics.setColor(
            self.styles.background[1],
            self.styles.background[2],
            self.styles.background[3],
            self.styles.background[4] * alpha
        )
        love.graphics.rectangle("fill", self.x, self.y, self.width, self.height, 4, 4)

        love.graphics.setColor(
            self.styles.border[1],
            self.styles.border[2],
            self.styles.border[3],
            self.styles.border[4] * alpha
        )
        love.graphics.rectangle("line", self.x, self.y, self.width, self.height, 4, 4)

        -- Draw title
        local title = self.poiData and self.poiData.name or "Scrutinize"
        love.graphics.setColor(
            self.styles.title[1],
            self.styles.title[2],
            self.styles.title[3],
            alpha
        )

        local oldFont = love.graphics.getFont()
        if self.font then
            love.graphics.setFont(self.font)
        end

        love.graphics.printf(
            title,
            self.x + self.padding,
            self.y + self.padding,
            self.width - self.padding * 2,
            "center"
        )

        -- Draw buttons
        local buttonY = self.y + self.titleHeight + self.padding
        for i, option in ipairs(self.options) do
            local isHovered = (i == self.hoveredIndex)
            local isPressed = (i == self.pressedIndex)

            -- Button background
            local bgColor = self.styles.button_normal
            if isPressed then
                bgColor = self.styles.button_pressed
            elseif isHovered then
                bgColor = self.styles.button_hover
            end

            love.graphics.setColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] * alpha)
            love.graphics.rectangle(
                "fill",
                self.x + self.padding,
                buttonY,
                self.width - self.padding * 2,
                self.buttonHeight - 2,
                2, 2
            )

            -- Button text
            local textColor = isHovered and self.styles.text_hover or self.styles.text_normal
            love.graphics.setColor(textColor[1], textColor[2], textColor[3], alpha)
            love.graphics.printf(
                option.description,
                self.x + self.padding * 2,
                buttonY + (self.buttonHeight - 16) / 2,
                self.width - self.padding * 4,
                "left"
            )

            buttonY = buttonY + self.buttonHeight
        end

        -- Restore font
        if oldFont then
            love.graphics.setFont(oldFont)
        end
    end

    return menu
end

return M

```

---

## File: src/ui/input_manager.lua

```lua
-- input_manager.lua
-- Global Input & Drag-and-Drop Manager for Majesty
-- Ticket T2_11: Handle clicking POIs for "Looking" and dragging entities/items for "Acting"
--
-- Design:
-- - Click on POI = Open scrutiny menu (T2_13)
-- - Drag Adventurer/Item onto POI = Trigger investigation
-- - Uses AABB collision for "sticky" targets

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- DRAG STATE CONSTANTS
--------------------------------------------------------------------------------
M.DRAG_TYPES = {
    NONE       = "none",
    ADVENTURER = "adventurer",
    ITEM       = "item",
}

-- Minimum movement to distinguish drag from click (pixels)
local CLICK_THRESHOLD = 5

--------------------------------------------------------------------------------
-- INPUT MANAGER FACTORY
--------------------------------------------------------------------------------

--- Create a new InputManager
-- @param config table: { eventBus, roomManager }
-- @return InputManager instance
function M.createInputManager(config)
    config = config or {}

    local manager = {
        eventBus    = config.eventBus or events.globalBus,
        roomManager = config.roomManager,

        -- Drag state
        isDragging     = false,
        dragType       = M.DRAG_TYPES.NONE,
        dragSource     = nil,       -- The object being dragged
        dragStartX     = 0,
        dragStartY     = 0,
        currentMouseX  = 0,
        currentMouseY  = 0,

        -- Click detection
        pressStartX    = 0,
        pressStartY    = 0,
        pressTarget    = nil,       -- What was under mouse on press
        pressTime      = 0,

        -- UI state
        isLocked       = false,     -- True when a menu is open
        activeMenu     = nil,       -- Current open menu (focus_menu)

        -- Registered hitboxes
        -- Each entry: { id, type, x, y, width, height, data }
        hitboxes       = {},

        -- Drop targets (POIs that can receive drops)
        dropTargets    = {},
    }

    ----------------------------------------------------------------------------
    -- HITBOX REGISTRATION
    -- UI components register their clickable areas here
    ----------------------------------------------------------------------------

    --- Register a hitbox for click/drop detection
    -- @param id string: Unique identifier
    -- @param hitboxType string: "poi", "adventurer", "item", "button"
    -- @param x, y, width, height number: Bounding box
    -- @param data table: Associated data (entity, poi, etc.)
    function manager:registerHitbox(id, hitboxType, x, y, width, height, data)
        self.hitboxes[id] = {
            id     = id,
            type   = hitboxType,
            x      = x,
            y      = y,
            width  = width,
            height = height,
            data   = data or {},
        }

        -- POIs are also drop targets
        if hitboxType == "poi" then
            self.dropTargets[id] = self.hitboxes[id]
        end
    end

    --- Unregister a hitbox
    function manager:unregisterHitbox(id)
        self.hitboxes[id] = nil
        self.dropTargets[id] = nil
    end

    --- Clear all hitboxes (call when room changes)
    function manager:clearHitboxes()
        self.hitboxes = {}
        self.dropTargets = {}
    end

    --- Update a hitbox position (for text reflow)
    function manager:updateHitbox(id, x, y, width, height)
        local hb = self.hitboxes[id]
        if hb then
            hb.x = x
            hb.y = y
            if width then hb.width = width end
            if height then hb.height = height end
        end
    end

    ----------------------------------------------------------------------------
    -- COLLISION DETECTION (AABB)
    ----------------------------------------------------------------------------

    --- Check if point is inside a hitbox
    local function pointInBox(px, py, box)
        return px >= box.x and px <= box.x + box.width and
               py >= box.y and py <= box.y + box.height
    end

    --- Get hitbox at a screen position
    -- @param x, y number: Screen coordinates
    -- @param filterType string|nil: Only return hitboxes of this type
    -- @return hitbox or nil
    function manager:getHitboxAt(x, y, filterType)
        for _, hb in pairs(self.hitboxes) do
            if pointInBox(x, y, hb) then
                if not filterType or hb.type == filterType then
                    return hb
                end
            end
        end
        return nil
    end

    --- Get drop target at a screen position
    -- @return hitbox or nil
    function manager:getDropTarget(x, y)
        for _, hb in pairs(self.dropTargets) do
            if pointInBox(x, y, hb) then
                return hb
            end
        end
        return nil
    end

    ----------------------------------------------------------------------------
    -- DRAG/DROP LIFECYCLE
    ----------------------------------------------------------------------------

    --- Begin dragging an object
    -- @param source table: The object being dragged (adventurer, item)
    -- @param dragType string: One of DRAG_TYPES
    -- @param x, y number: Start position
    function manager:beginDrag(source, dragType, x, y)
        self.isDragging = true
        self.dragType = dragType
        self.dragSource = source
        self.dragStartX = x
        self.dragStartY = y
        self.currentMouseX = x
        self.currentMouseY = y

        self.eventBus:emit(events.EVENTS.DRAG_BEGIN, {
            source = source,
            dragType = dragType,
            x = x,
            y = y,
        })
    end

    --- Update drag position (call from love.mousemoved)
    function manager:updateDrag(x, y)
        if self.isDragging then
            self.currentMouseX = x
            self.currentMouseY = y
        end
    end

    --- End dragging and check for drop
    -- @param x, y number: Release position
    -- @return table: { success, target, action }
    function manager:endDrag(x, y)
        if not self.isDragging then
            return { success = false }
        end

        local result = {
            success = false,
            source = self.dragSource,
            dragType = self.dragType,
            target = nil,
            action = nil,
        }

        -- Check for valid drop target
        local target = self:getDropTarget(x, y)
        if target then
            result.success = true
            result.target = target

            -- Determine action based on drag type
            if self.dragType == M.DRAG_TYPES.ADVENTURER then
                result.action = "investigate"
            elseif self.dragType == M.DRAG_TYPES.ITEM then
                result.action = "use_item"
            end

            self.eventBus:emit(events.EVENTS.DROP_ON_TARGET, {
                source = self.dragSource,
                dragType = self.dragType,
                target = target,
                action = result.action,
            })
        else
            -- No valid target - return to origin
            self.eventBus:emit(events.EVENTS.DRAG_CANCELLED, {
                source = self.dragSource,
                dragType = self.dragType,
            })
        end

        -- Reset drag state
        self.isDragging = false
        self.dragType = M.DRAG_TYPES.NONE
        self.dragSource = nil

        return result
    end

    --- Cancel current drag
    function manager:cancelDrag()
        if self.isDragging then
            self.eventBus:emit(events.EVENTS.DRAG_CANCELLED, {
                source = self.dragSource,
                dragType = self.dragType,
            })
        end

        self.isDragging = false
        self.dragType = M.DRAG_TYPES.NONE
        self.dragSource = nil
    end

    ----------------------------------------------------------------------------
    -- CLICK DETECTION
    ----------------------------------------------------------------------------

    --- Handle mouse press
    -- @param x, y number: Screen position
    -- @param button number: Mouse button (1 = left)
    function manager:onMousePressed(x, y, button)
        if button ~= 1 then return end  -- Only handle left click
        if self.isLocked then return end  -- UI is locked

        self.pressStartX = x
        self.pressStartY = y
        self.pressTime = love and love.timer.getTime() or os.time()
        self.pressTarget = self:getHitboxAt(x, y)

        -- Check if pressing on a draggable
        if self.pressTarget then
            local hbType = self.pressTarget.type
            if hbType == "adventurer" then
                self:beginDrag(self.pressTarget.data, M.DRAG_TYPES.ADVENTURER, x, y)
            elseif hbType == "item" then
                self:beginDrag(self.pressTarget.data, M.DRAG_TYPES.ITEM, x, y)
            end
        end
    end

    --- Handle mouse release
    -- @param x, y number: Screen position
    -- @param button number: Mouse button
    function manager:onMouseReleased(x, y, button)
        if button ~= 1 then return end

        -- If we were dragging, handle drop
        if self.isDragging then
            local dragDistance = math.sqrt(
                (x - self.pressStartX)^2 + (y - self.pressStartY)^2
            )

            if dragDistance < CLICK_THRESHOLD then
                -- Didn't move enough - treat as click, not drag
                self:cancelDrag()
                self:handleClick(x, y)
            else
                -- Actual drag completed
                self:endDrag(x, y)
            end
            return
        end

        -- Regular click handling
        self:handleClick(x, y)
    end

    --- Handle a click (press + release without significant drag)
    function manager:handleClick(x, y)
        local target = self:getHitboxAt(x, y)

        if not target then
            -- Clicked empty space - close any open menu
            if self.activeMenu then
                self:closeMenu()
            end
            return
        end

        -- Handle based on target type
        if target.type == "poi" then
            -- Open scrutiny menu for this POI
            self.eventBus:emit(events.EVENTS.POI_CLICKED, {
                poiId = target.id,
                poi = target.data,
                x = x,
                y = y,
            })
        elseif target.type == "button" then
            -- Button clicked
            if target.data.onClick then
                target.data.onClick()
            end
            self.eventBus:emit(events.EVENTS.BUTTON_CLICKED, {
                buttonId = target.id,
                data = target.data,
            })
        end
    end

    --- Handle mouse movement
    function manager:onMouseMoved(x, y, dx, dy)
        self.currentMouseX = x
        self.currentMouseY = y

        if self.isDragging then
            self:updateDrag(x, y)
        end
    end

    ----------------------------------------------------------------------------
    -- UI LOCKING (for menus)
    ----------------------------------------------------------------------------

    --- Lock UI (prevent interaction while menu is open)
    function manager:lockUI(menu)
        self.isLocked = true
        self.activeMenu = menu
    end

    --- Unlock UI
    function manager:unlockUI()
        self.isLocked = false
        self.activeMenu = nil
    end

    --- Close the active menu
    function manager:closeMenu()
        if self.activeMenu and self.activeMenu.close then
            self.activeMenu:close()
        end
        self:unlockUI()
    end

    ----------------------------------------------------------------------------
    -- RENDERING HELPERS
    ----------------------------------------------------------------------------

    --- Get drag ghost position and data for rendering
    -- @return table|nil: { source, dragType, x, y } or nil if not dragging
    function manager:getDragGhost()
        if not self.isDragging then
            return nil
        end

        return {
            source   = self.dragSource,
            dragType = self.dragType,
            x        = self.currentMouseX,
            y        = self.currentMouseY,
        }
    end

    --- Check if a drop target is currently hovered
    function manager:isHoveringDropTarget()
        if not self.isDragging then
            return false, nil
        end

        local target = self:getDropTarget(self.currentMouseX, self.currentMouseY)
        return target ~= nil, target
    end

    ----------------------------------------------------------------------------
    -- LÖVE 2D INTEGRATION HELPERS
    ----------------------------------------------------------------------------

    --- Convenience function to hook into love.mousepressed
    function manager:mousepressed(x, y, button)
        self:onMousePressed(x, y, button)
    end

    --- Convenience function to hook into love.mousereleased
    function manager:mousereleased(x, y, button)
        self:onMouseReleased(x, y, button)
    end

    --- Convenience function to hook into love.mousemoved
    function manager:mousemoved(x, y, dx, dy)
        self:onMouseMoved(x, y, dx, dy)
    end

    return manager
end

return M

```

---

## File: src/ui/inspect_panel.lua

```lua
-- inspect_panel.lua
-- Inspect Context Overlay for Majesty
-- Ticket S5.4: Detailed info overlay for entities and POIs
--
-- Trigger: Hover (0.5s delay) or Right-Click
-- Shows: Full name, origin, known items, HP/defense (gated by discovery)

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------
M.HOVER_DELAY = 0.5     -- Seconds before hover triggers panel
M.PANEL_WIDTH = 220
M.PANEL_PADDING = 12
M.LINE_HEIGHT = 16

--------------------------------------------------------------------------------
-- COLORS (Ink on Parchment palette)
--------------------------------------------------------------------------------
M.COLORS = {
    panel_bg     = { 0.92, 0.88, 0.78, 0.95 },   -- Parchment
    panel_border = { 0.35, 0.30, 0.25, 1.0 },
    shadow       = { 0.10, 0.08, 0.05, 0.4 },

    -- Text
    text_header  = { 0.20, 0.15, 0.10, 1.0 },    -- Dark ink
    text_body    = { 0.30, 0.25, 0.20, 1.0 },    -- Medium ink
    text_faint   = { 0.50, 0.45, 0.40, 0.8 },    -- Faint
    text_danger  = { 0.60, 0.25, 0.20, 1.0 },    -- Red ink

    -- Pips
    pip_full     = { 0.55, 0.25, 0.20, 1.0 },    -- Health pip
    pip_empty    = { 0.40, 0.38, 0.35, 0.5 },
    pip_armor    = { 0.50, 0.55, 0.60, 1.0 },    -- Armor pip

    -- Discovery state
    undiscovered = { 0.50, 0.48, 0.45, 0.6 },    -- Unknown info
}

--------------------------------------------------------------------------------
-- INSPECT PANEL FACTORY
--------------------------------------------------------------------------------

--- Create a new InspectPanel
-- @param config table: { eventBus }
-- @return InspectPanel instance
function M.createInspectPanel(config)
    config = config or {}

    local panel = {
        eventBus = config.eventBus or events.globalBus,

        -- State
        isVisible = false,
        target = nil,           -- Entity or POI being inspected
        targetType = nil,       -- "entity", "poi", "item"

        -- Position (follows mouse/target)
        x = 0,
        y = 0,

        -- Hover tracking
        hoverTarget = nil,
        hoverTimer = 0,
        hoverX = 0,
        hoverY = 0,

        -- Discovery cache (entityId/poiId -> { discovered fields })
        discoveryCache = {},

        colors = M.COLORS,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function panel:init()
        -- Listen for scrutiny results (discoveries)
        self.eventBus:on(events.EVENTS.SCRUTINY_SELECTED, function(data)
            if data.poiId then
                self:markDiscovered(data.poiId, data.verb)
            end
        end)
    end

    ----------------------------------------------------------------------------
    -- HOVER TRACKING
    ----------------------------------------------------------------------------

    --- Called when mouse hovers over a target
    function panel:onHover(target, targetType, x, y)
        if self.hoverTarget == target then
            return -- Already tracking this target
        end

        self.hoverTarget = target
        self.hoverTimer = 0
        self.hoverX = x
        self.hoverY = y
    end

    --- Called when mouse leaves a target
    function panel:onHoverEnd()
        self.hoverTarget = nil
        self.hoverTimer = 0
    end

    --- Right-click to immediately show panel
    function panel:onRightClick(target, targetType, x, y)
        self:show(target, targetType, x, y)
    end

    ----------------------------------------------------------------------------
    -- VISIBILITY
    ----------------------------------------------------------------------------

    --- Show the panel for a target
    function panel:show(target, targetType, x, y)
        self.isVisible = true
        self.target = target
        self.targetType = targetType or "entity"

        -- Position panel near the target but within screen bounds
        self:positionPanel(x, y)
    end

    --- Hide the panel
    function panel:hide()
        self.isVisible = false
        self.target = nil
    end

    --- Position panel relative to target, keeping on screen
    function panel:positionPanel(x, y)
        if not love then
            self.x, self.y = x + 15, y + 15
            return
        end

        local w, h = love.graphics.getDimensions()
        local panelHeight = self:calculateHeight()

        -- Default: to the right and below cursor
        self.x = x + 15
        self.y = y + 15

        -- Keep on screen horizontally
        if self.x + M.PANEL_WIDTH > w - 10 then
            self.x = x - M.PANEL_WIDTH - 15
        end

        -- Keep on screen vertically
        if self.y + panelHeight > h - 10 then
            self.y = h - panelHeight - 10
        end

        -- Don't go above screen
        if self.y < 10 then
            self.y = 10
        end
    end

    ----------------------------------------------------------------------------
    -- DISCOVERY (Information Gating)
    ----------------------------------------------------------------------------

    --- Mark info as discovered for a target
    function panel:markDiscovered(targetId, infoType)
        if not self.discoveryCache[targetId] then
            self.discoveryCache[targetId] = {}
        end
        self.discoveryCache[targetId][infoType] = true
    end

    --- Check if info is discovered
    function panel:isDiscovered(targetId, infoType)
        if not self.discoveryCache[targetId] then
            return false
        end
        return self.discoveryCache[targetId][infoType] == true
    end

    --- Check if any info is discovered for target
    function panel:hasAnyDiscovery(targetId)
        return self.discoveryCache[targetId] ~= nil
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function panel:update(dt)
        -- Update hover timer
        if self.hoverTarget then
            self.hoverTimer = self.hoverTimer + dt
            if self.hoverTimer >= M.HOVER_DELAY then
                self:show(self.hoverTarget,
                    self.hoverTarget.isPC and "entity" or "entity",
                    self.hoverX, self.hoverY)
                self.hoverTarget = nil
            end
        end
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    ----------------------------------------------------------------------------

    function panel:draw()
        if not love or not self.isVisible or not self.target then return end

        local colors = self.colors
        local x, y = self.x, self.y
        local panelHeight = self:calculateHeight()

        -- Shadow
        love.graphics.setColor(colors.shadow)
        love.graphics.rectangle("fill", x + 4, y + 4, M.PANEL_WIDTH, panelHeight, 4, 4)

        -- Panel background
        love.graphics.setColor(colors.panel_bg)
        love.graphics.rectangle("fill", x, y, M.PANEL_WIDTH, panelHeight, 4, 4)

        -- Border
        love.graphics.setColor(colors.panel_border)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", x, y, M.PANEL_WIDTH, panelHeight, 4, 4)
        love.graphics.setLineWidth(1)

        -- Content
        if self.targetType == "entity" then
            self:drawEntityInfo(x + M.PANEL_PADDING, y + M.PANEL_PADDING)
        elseif self.targetType == "poi" then
            self:drawPOIInfo(x + M.PANEL_PADDING, y + M.PANEL_PADDING)
        elseif self.targetType == "item" then
            self:drawItemInfo(x + M.PANEL_PADDING, y + M.PANEL_PADDING)
        end
    end

    --- Draw entity (adventurer or NPC) info
    function panel:drawEntityInfo(x, y)
        local e = self.target
        local colors = self.colors
        local lineY = y

        -- Name (always visible)
        love.graphics.setColor(colors.text_header)
        love.graphics.print(e.name or "Unknown", x, lineY)
        lineY = lineY + M.LINE_HEIGHT + 4

        -- Origin/Career (if available)
        if e.career or e.origin then
            love.graphics.setColor(colors.text_faint)
            local originText = (e.career or "") .. (e.origin and (" of " .. e.origin) or "")
            love.graphics.print(originText, x, lineY)
            lineY = lineY + M.LINE_HEIGHT
        end

        -- Separator
        lineY = lineY + 4
        love.graphics.setColor(colors.panel_border)
        love.graphics.line(x, lineY, x + M.PANEL_WIDTH - M.PANEL_PADDING * 2, lineY)
        lineY = lineY + 8

        -- Health/Wounds (pips)
        love.graphics.setColor(colors.text_body)
        love.graphics.print("Health:", x, lineY)
        lineY = lineY + M.LINE_HEIGHT
        self:drawHealthPips(x, lineY, e)
        lineY = lineY + 14

        -- Armor (if present)
        if e.armorSlots and e.armorSlots > 0 then
            love.graphics.setColor(colors.text_body)
            love.graphics.print("Armor:", x, lineY)
            lineY = lineY + M.LINE_HEIGHT
            self:drawArmorPips(x, lineY, e)
            lineY = lineY + 14
        end

        -- Defense status
        if e.hasDefense and e:hasDefense() then
            love.graphics.setColor(colors.text_danger)
            love.graphics.print("Defense Prepared!", x, lineY)
            lineY = lineY + M.LINE_HEIGHT
        end

        -- Conditions
        if e.conditions then
            local conditionTexts = {}
            if e.conditions.stressed then conditionTexts[#conditionTexts + 1] = "Stressed" end
            if e.conditions.staggered then conditionTexts[#conditionTexts + 1] = "Staggered" end
            if e.conditions.injured then conditionTexts[#conditionTexts + 1] = "Injured" end
            if e.conditions.deaths_door then conditionTexts[#conditionTexts + 1] = "Death's Door" end
            if e.conditions.dead then conditionTexts[#conditionTexts + 1] = "DEAD" end

            if #conditionTexts > 0 then
                love.graphics.setColor(colors.text_danger)
                love.graphics.print(table.concat(conditionTexts, ", "), x, lineY)
                lineY = lineY + M.LINE_HEIGHT
            end
        end

        -- Items in hands/belt (for PCs or discovered NPCs)
        if e.isPC or self:isDiscovered(e.id, "inventory") then
            if e.inventory then
                lineY = lineY + 4
                love.graphics.setColor(colors.text_body)
                love.graphics.print("Equipment:", x, lineY)
                lineY = lineY + M.LINE_HEIGHT

                local items = e.inventory:getItems("hands")
                for _, item in ipairs(items) do
                    love.graphics.setColor(colors.text_faint)
                    love.graphics.print("  " .. (item.name or "?"), x, lineY)
                    lineY = lineY + M.LINE_HEIGHT
                end
            end
        end

        -- NPC-specific: Hates/Wants (only if discovered via Banter/Con Artist)
        if not e.isPC then
            if e.hates and self:isDiscovered(e.id, "hates") then
                lineY = lineY + 4
                love.graphics.setColor(colors.text_body)
                love.graphics.print("Hates:", x, lineY)
                lineY = lineY + M.LINE_HEIGHT
                love.graphics.setColor(colors.text_faint)
                love.graphics.print("  " .. table.concat(e.hates, ", "), x, lineY)
                lineY = lineY + M.LINE_HEIGHT
            end

            if e.wants and self:isDiscovered(e.id, "wants") then
                love.graphics.setColor(colors.text_body)
                love.graphics.print("Wants:", x, lineY)
                lineY = lineY + M.LINE_HEIGHT
                love.graphics.setColor(colors.text_faint)
                love.graphics.print("  " .. table.concat(e.wants, ", "), x, lineY)
                lineY = lineY + M.LINE_HEIGHT
            end

            -- Show "???" for undiscovered info
            if not self:hasAnyDiscovery(e.id) then
                lineY = lineY + 4
                love.graphics.setColor(colors.undiscovered)
                love.graphics.print("(More info unknown)", x, lineY)
            end
        end
    end

    --- Draw health pips
    function panel:drawHealthPips(x, y, entity)
        local colors = self.colors
        local pipSize = 10
        local pipSpacing = 3

        -- Calculate wounds taken
        local woundsUntilDeath = 4  -- Default
        if entity.woundsUntilDeath then
            woundsUntilDeath = entity:woundsUntilDeath()
        end

        local maxHealth = 5  -- Simplified
        local currentHealth = math.max(0, woundsUntilDeath)

        for i = 1, maxHealth do
            local pipX = x + (i - 1) * (pipSize + pipSpacing)

            if i <= currentHealth then
                love.graphics.setColor(colors.pip_full)
                love.graphics.rectangle("fill", pipX, y, pipSize, pipSize, 2, 2)
            else
                love.graphics.setColor(colors.pip_empty)
                love.graphics.rectangle("fill", pipX, y, pipSize, pipSize, 2, 2)
            end

            love.graphics.setColor(colors.panel_border)
            love.graphics.rectangle("line", pipX, y, pipSize, pipSize, 2, 2)
        end
    end

    --- Draw armor pips
    function panel:drawArmorPips(x, y, entity)
        local colors = self.colors
        local pipSize = 10
        local pipSpacing = 3

        local slots = entity.armorSlots or 0
        local notches = entity.armorNotches or 0
        local remaining = slots - notches

        for i = 1, slots do
            local pipX = x + (i - 1) * (pipSize + pipSpacing)

            if i <= remaining then
                love.graphics.setColor(colors.pip_armor)
                love.graphics.rectangle("fill", pipX, y, pipSize, pipSize, 2, 2)
            else
                love.graphics.setColor(colors.pip_empty)
                love.graphics.rectangle("fill", pipX, y, pipSize, pipSize, 2, 2)
                -- X mark for notched
                love.graphics.setColor(colors.text_danger)
                love.graphics.line(pipX + 2, y + 2, pipX + pipSize - 2, y + pipSize - 2)
                love.graphics.line(pipX + pipSize - 2, y + 2, pipX + 2, y + pipSize - 2)
            end

            love.graphics.setColor(colors.panel_border)
            love.graphics.rectangle("line", pipX, y, pipSize, pipSize, 2, 2)
        end
    end

    --- Draw POI info
    function panel:drawPOIInfo(x, y)
        local poi = self.target
        local colors = self.colors
        local lineY = y

        -- Name
        love.graphics.setColor(colors.text_header)
        love.graphics.print(poi.name or "Unknown", x, lineY)
        lineY = lineY + M.LINE_HEIGHT + 4

        -- Description
        if poi.description then
            love.graphics.setColor(colors.text_body)
            -- Word wrap would go here; for now just print
            love.graphics.printf(poi.description, x, lineY, M.PANEL_WIDTH - M.PANEL_PADDING * 2)
            lineY = lineY + M.LINE_HEIGHT * 2
        end

        -- Discovered info
        if self:isDiscovered(poi.id, "examine") then
            lineY = lineY + 4
            love.graphics.setColor(colors.text_faint)
            love.graphics.print("(Examined)", x, lineY)
        end
    end

    --- Draw item info
    function panel:drawItemInfo(x, y)
        local item = self.target
        local colors = self.colors
        local lineY = y

        -- Name
        love.graphics.setColor(colors.text_header)
        love.graphics.print(item.name or "Unknown Item", x, lineY)
        lineY = lineY + M.LINE_HEIGHT + 4

        -- Durability
        if item.durability then
            love.graphics.setColor(colors.text_body)
            local durText = string.format("Durability: %d/%d", item.durability - (item.notches or 0), item.durability)
            love.graphics.print(durText, x, lineY)
            lineY = lineY + M.LINE_HEIGHT
        end

        -- Destroyed
        if item.destroyed then
            love.graphics.setColor(colors.text_danger)
            love.graphics.print("DESTROYED", x, lineY)
            lineY = lineY + M.LINE_HEIGHT
        end

        -- Properties
        if item.properties then
            for key, value in pairs(item.properties) do
                love.graphics.setColor(colors.text_faint)
                love.graphics.print(key .. ": " .. tostring(value), x, lineY)
                lineY = lineY + M.LINE_HEIGHT
            end
        end
    end

    --- Calculate panel height based on content
    function panel:calculateHeight()
        -- Base height
        local height = M.PANEL_PADDING * 2 + M.LINE_HEIGHT * 4

        if self.targetType == "entity" and self.target then
            height = height + M.LINE_HEIGHT * 6  -- Name, origin, health, etc.

            if self.target.armorSlots and self.target.armorSlots > 0 then
                height = height + M.LINE_HEIGHT + 14
            end

            if self.target.conditions then
                local hasConditions = self.target.conditions.stressed or
                    self.target.conditions.staggered or
                    self.target.conditions.injured or
                    self.target.conditions.deaths_door
                if hasConditions then
                    height = height + M.LINE_HEIGHT
                end
            end
        end

        return math.min(height, 300)  -- Cap at max height
    end

    return panel
end

return M

```

---

## File: src/ui/item_view.lua

```lua
-- item_view.lua
-- Item Notch Visualization Component for Majesty
-- Ticket S5.2: Visual durability with scratches, cracks, and destruction FX
--
-- Renders items with:
-- - Base icon (placeholder rectangle for now)
-- - Notch scratches/cracks overlay
-- - Destroyed state (greyed out, crossed through)
-- - Armor pips for NPCs

local M = {}

--------------------------------------------------------------------------------
-- COLORS (Ink on Parchment palette)
--------------------------------------------------------------------------------
M.COLORS = {
    -- Base
    item_bg         = { 0.25, 0.22, 0.20, 1.0 },
    item_border     = { 0.40, 0.35, 0.30, 1.0 },

    -- Notch colors
    scratch_light   = { 0.55, 0.35, 0.30, 0.6 },   -- Light scratch
    scratch_medium  = { 0.50, 0.25, 0.20, 0.8 },   -- Medium scratch
    scratch_heavy   = { 0.45, 0.15, 0.10, 1.0 },   -- Deep gouge

    -- Destroyed
    destroyed_tint  = { 0.35, 0.35, 0.35, 0.7 },
    destroyed_x     = { 0.60, 0.20, 0.15, 0.9 },

    -- Armor pips
    armor_full      = { 0.50, 0.55, 0.60, 1.0 },   -- Steel grey
    armor_notched   = { 0.35, 0.25, 0.20, 0.8 },   -- Damaged
    armor_border    = { 0.30, 0.28, 0.25, 1.0 },

    -- Text
    text_light      = { 0.85, 0.80, 0.70, 1.0 },
    text_dark       = { 0.15, 0.12, 0.10, 1.0 },
}

--------------------------------------------------------------------------------
-- SCRATCH PATTERNS
-- Pre-defined scratch line patterns for each notch level
--------------------------------------------------------------------------------
M.SCRATCH_PATTERNS = {
    -- Notch 1: Single light scratch
    [1] = {
        { 0.2, 0.1, 0.8, 0.9, "light" },
    },
    -- Notch 2: Two crossing scratches
    [2] = {
        { 0.15, 0.15, 0.85, 0.85, "medium" },
        { 0.85, 0.2, 0.2, 0.8, "light" },
    },
    -- Notch 3+: Heavy damage, multiple gouges
    [3] = {
        { 0.1, 0.1, 0.9, 0.9, "heavy" },
        { 0.9, 0.15, 0.15, 0.85, "heavy" },
        { 0.3, 0.05, 0.7, 0.95, "medium" },
    },
}

--------------------------------------------------------------------------------
-- ITEM VIEW FUNCTIONS
--------------------------------------------------------------------------------

--- Draw an item icon with notch visualization
-- @param item table: Item with { name, notches, durability, destroyed }
-- @param x, y number: Position
-- @param size number: Icon size (square)
-- @param options table: { showName, showDurability }
function M.drawItem(item, x, y, size, options)
    if not love or not item then return end

    options = options or {}
    local colors = M.COLORS

    -- Base icon background
    if item.destroyed then
        love.graphics.setColor(colors.destroyed_tint)
    else
        love.graphics.setColor(colors.item_bg)
    end
    love.graphics.rectangle("fill", x, y, size, size, 3, 3)

    -- Border
    love.graphics.setColor(colors.item_border)
    love.graphics.rectangle("line", x, y, size, size, 3, 3)

    -- Draw notch scratches
    if item.notches and item.notches > 0 then
        M.drawNotchScratches(x, y, size, item.notches)
    end

    -- Destroyed overlay
    if item.destroyed then
        M.drawDestroyedOverlay(x, y, size)
    end

    -- Item name (if requested)
    if options.showName then
        love.graphics.setColor(colors.text_light)
        local nameY = y + size + 2
        love.graphics.printf(
            item.name or "???",
            x - 10,
            nameY,
            size + 20,
            "center"
        )
    end

    -- Durability pips (if requested)
    if options.showDurability and item.durability then
        M.drawDurabilityPips(x, y + size + 2, size, item.durability, item.notches or 0)
    end
end

--- Draw notch scratches on an item
-- @param x, y number: Item position
-- @param size number: Item size
-- @param notches number: Number of notches taken
function M.drawNotchScratches(x, y, size, notches)
    local colors = M.COLORS

    -- Get pattern for this notch level (max at 3)
    local patternLevel = math.min(notches, 3)
    local pattern = M.SCRATCH_PATTERNS[patternLevel]

    if not pattern then return end

    for _, scratch in ipairs(pattern) do
        local x1 = x + scratch[1] * size
        local y1 = y + scratch[2] * size
        local x2 = x + scratch[3] * size
        local y2 = y + scratch[4] * size
        local severity = scratch[5]

        -- Set color based on severity
        if severity == "heavy" then
            love.graphics.setColor(colors.scratch_heavy)
            love.graphics.setLineWidth(3)
        elseif severity == "medium" then
            love.graphics.setColor(colors.scratch_medium)
            love.graphics.setLineWidth(2)
        else
            love.graphics.setColor(colors.scratch_light)
            love.graphics.setLineWidth(1.5)
        end

        -- Draw the scratch line with slight jitter for hand-drawn feel
        local midX = (x1 + x2) / 2 + (math.random() - 0.5) * size * 0.1
        local midY = (y1 + y2) / 2 + (math.random() - 0.5) * size * 0.1

        love.graphics.line(x1, y1, midX, midY, x2, y2)
    end

    love.graphics.setLineWidth(1)
end

--- Draw destroyed overlay (heavy X through item)
function M.drawDestroyedOverlay(x, y, size)
    local colors = M.COLORS
    local padding = size * 0.1

    -- Heavy ink X through the item
    love.graphics.setColor(colors.destroyed_x)
    love.graphics.setLineWidth(4)

    -- Main X
    love.graphics.line(
        x + padding, y + padding,
        x + size - padding, y + size - padding
    )
    love.graphics.line(
        x + size - padding, y + padding,
        x + padding, y + size - padding
    )

    -- Additional "shattered" lines for emphasis
    love.graphics.setLineWidth(2)
    love.graphics.line(x + size/2, y + padding/2, x + size/2, y + size - padding/2)
    love.graphics.line(x + padding/2, y + size/2, x + size - padding/2, y + size/2)

    love.graphics.setLineWidth(1)
end

--- Draw durability pips below item
function M.drawDurabilityPips(x, y, width, durability, notches)
    local colors = M.COLORS
    local pipSize = 6
    local pipSpacing = pipSize + 3
    local totalWidth = durability * pipSpacing - 3
    local startX = x + (width - totalWidth) / 2

    for i = 1, durability do
        local pipX = startX + (i - 1) * pipSpacing

        if i <= notches then
            -- Notched pip (damaged)
            love.graphics.setColor(colors.armor_notched)
            love.graphics.rectangle("fill", pipX, y, pipSize, pipSize, 1, 1)
            -- X through notched
            love.graphics.setColor(colors.destroyed_x)
            love.graphics.line(pipX + 1, y + 1, pipX + pipSize - 1, y + pipSize - 1)
        else
            -- Full pip (intact)
            love.graphics.setColor(colors.armor_full)
            love.graphics.rectangle("fill", pipX, y, pipSize, pipSize, 1, 1)
        end

        -- Border
        love.graphics.setColor(colors.armor_border)
        love.graphics.rectangle("line", pipX, y, pipSize, pipSize, 1, 1)
    end
end

--------------------------------------------------------------------------------
-- ARMOR DISPLAY FOR NPCs
--------------------------------------------------------------------------------

--- Draw armor indicator for an NPC (shield icon with pips)
-- @param entity table: Entity with armorSlots and armorNotches
-- @param x, y number: Position
-- @param size number: Icon size
function M.drawNPCArmor(entity, x, y, size)
    if not love or not entity then return end
    if not entity.armorSlots or entity.armorSlots <= 0 then return end

    local colors = M.COLORS
    local slots = entity.armorSlots
    local notches = entity.armorNotches or 0

    -- Draw shield shape
    love.graphics.setColor(colors.armor_full)

    -- Shield outline (simplified heraldic shape)
    local points = {
        x + size * 0.5, y,                      -- Top center
        x + size, y + size * 0.3,               -- Top right
        x + size, y + size * 0.6,               -- Middle right
        x + size * 0.5, y + size,               -- Bottom point
        x, y + size * 0.6,                      -- Middle left
        x, y + size * 0.3,                      -- Top left
    }
    love.graphics.polygon("fill", points)

    -- Shield border
    love.graphics.setColor(colors.armor_border)
    love.graphics.setLineWidth(2)
    love.graphics.polygon("line", points)
    love.graphics.setLineWidth(1)

    -- Draw armor pips inside shield
    local pipSize = math.min(size * 0.15, 8)
    local pipY = y + size * 0.35
    local totalPipWidth = slots * (pipSize + 2) - 2
    local pipStartX = x + (size - totalPipWidth) / 2

    for i = 1, slots do
        local pipX = pipStartX + (i - 1) * (pipSize + 2)

        if i <= notches then
            -- Notched (damaged)
            love.graphics.setColor(colors.armor_notched)
            love.graphics.circle("fill", pipX + pipSize/2, pipY, pipSize/2)
            -- Crack line
            love.graphics.setColor(colors.destroyed_x)
            love.graphics.setLineWidth(1.5)
            love.graphics.line(pipX, pipY - pipSize/3, pipX + pipSize, pipY + pipSize/3)
            love.graphics.setLineWidth(1)
        else
            -- Intact
            love.graphics.setColor(colors.armor_full)
            love.graphics.circle("fill", pipX + pipSize/2, pipY, pipSize/2)
        end
    end

    -- Show if fully damaged
    if notches >= slots then
        -- Broken shield indicator
        love.graphics.setColor(colors.destroyed_x)
        love.graphics.setLineWidth(3)
        love.graphics.line(x + size * 0.2, y + size * 0.2, x + size * 0.8, y + size * 0.8)
        love.graphics.setLineWidth(1)
    end
end

--------------------------------------------------------------------------------
-- INVENTORY TRAY RENDERING
--------------------------------------------------------------------------------

--- Draw an inventory location (hands, belt, or pack)
-- @param inventory table: Inventory instance
-- @param location string: "hands", "belt", or "pack"
-- @param x, y number: Position
-- @param config table: { itemSize, columns, padding }
function M.drawInventoryTray(inventory, location, x, y, config)
    if not love or not inventory then return end

    config = config or {}
    local itemSize = config.itemSize or 40
    local columns = config.columns or 4
    local padding = config.padding or 4

    local items = inventory:getItems(location)

    -- Draw slot backgrounds
    local limit = inventory.limits[location] or 4
    for i = 0, limit - 1 do
        local col = i % columns
        local row = math.floor(i / columns)
        local slotX = x + col * (itemSize + padding)
        local slotY = y + row * (itemSize + padding)

        -- Empty slot background
        love.graphics.setColor(0.15, 0.12, 0.10, 0.5)
        love.graphics.rectangle("fill", slotX, slotY, itemSize, itemSize, 2, 2)
        love.graphics.setColor(0.30, 0.25, 0.20, 0.5)
        love.graphics.rectangle("line", slotX, slotY, itemSize, itemSize, 2, 2)
    end

    -- Draw items
    for i, item in ipairs(items) do
        local col = (i - 1) % columns
        local row = math.floor((i - 1) / columns)
        local itemX = x + col * (itemSize + padding)
        local itemY = y + row * (itemSize + padding)

        M.drawItem(item, itemX, itemY, itemSize, { showDurability = true })
    end
end

return M

```

---

## File: src/ui/loot_modal.lua

```lua
-- loot_modal.lua
-- Loot Modal for Majesty
-- Ticket S11.3: UI for looting containers and corpses
--
-- Opens when clicking a searchable container POI.
-- Displays items inside and allows Take/Take All.

local events = require('logic.events')
local inventory = require('logic.inventory')

local M = {}

--------------------------------------------------------------------------------
-- LAYOUT CONSTANTS
--------------------------------------------------------------------------------

M.LAYOUT = {
    WIDTH = 350,
    HEIGHT = 400,
    PADDING = 15,
    SLOT_SIZE = 48,
    SLOT_SPACING = 6,
    BUTTON_HEIGHT = 35,
}

--------------------------------------------------------------------------------
-- COLORS
--------------------------------------------------------------------------------

M.COLORS = {
    overlay = { 0, 0, 0, 0.7 },
    panel_bg = { 0.15, 0.13, 0.12, 0.98 },
    panel_border = { 0.5, 0.4, 0.3, 1 },
    header_bg = { 0.2, 0.17, 0.15, 1 },
    text = { 0.9, 0.88, 0.82, 1 },
    text_dim = { 0.6, 0.58, 0.55, 1 },
    text_highlight = { 1, 0.9, 0.6, 1 },
    slot_empty = { 0.12, 0.12, 0.14, 1 },
    slot_filled = { 0.25, 0.22, 0.18, 1 },
    slot_hover = { 0.35, 0.3, 0.25, 1 },
    button = { 0.25, 0.22, 0.18, 1 },
    button_hover = { 0.35, 0.3, 0.25, 1 },
    button_text = { 0.9, 0.88, 0.82, 1 },
}

--------------------------------------------------------------------------------
-- LOOT MODAL FACTORY
--------------------------------------------------------------------------------

function M.createLootModal(config)
    config = config or {}

    local modal = {
        eventBus = config.eventBus or events.globalBus,
        roomManager = config.roomManager,

        -- State
        isOpen = false,
        containerPOI = nil,      -- The POI being looted
        containerRoomId = nil,   -- Room the container is in
        containerName = "",      -- Display name

        -- Instantiated loot items (created from template IDs)
        lootItems = {},

        -- Selected recipient PC
        recipientPC = nil,
        recipientPCIndex = 1,
        guild = config.guild or {},

        -- Layout
        x = 0,
        y = 0,

        -- Hover state
        hoveredSlot = nil,
        hoveredButton = nil,

        -- Tooltip
        tooltip = nil,
    }

    ----------------------------------------------------------------------------
    -- OPEN/CLOSE
    ----------------------------------------------------------------------------

    --- Open the loot modal for a container POI
    -- @param poi table: The POI data
    -- @param roomId string: The room ID
    function modal:open(poi, roomId)
        if not poi then return end

        self.isOpen = true
        self.containerPOI = poi
        self.containerRoomId = roomId
        self.containerName = poi.name or "Container"

        -- Set default recipient
        if #self.guild > 0 then
            self.recipientPC = self.guild[self.recipientPCIndex]
        end

        -- Instantiate loot items from the POI's loot array
        self:instantiateLoot()

        -- Center the modal
        if love then
            local screenW, screenH = love.graphics.getDimensions()
            self.x = (screenW - M.LAYOUT.WIDTH) / 2
            self.y = (screenH - M.LAYOUT.HEIGHT) / 2
        end

        self.eventBus:emit("loot_modal_opened", { poi = poi, roomId = roomId })
    end

    function modal:close()
        -- Any items not taken remain in the container
        -- (Already handled by room state updates)
        self.isOpen = false
        self.containerPOI = nil
        self.containerRoomId = nil
        self.lootItems = {}
        self.hoveredSlot = nil
        self.hoveredButton = nil
        self.tooltip = nil

        self.eventBus:emit("loot_modal_closed", {})
    end

    ----------------------------------------------------------------------------
    -- LOOT INSTANTIATION
    ----------------------------------------------------------------------------

    --- Instantiate loot items from template IDs
    function modal:instantiateLoot()
        self.lootItems = {}

        if not self.containerPOI then return end

        -- Check for loot array in POI
        local lootIds = self.containerPOI.loot or {}

        -- Also check for secrets loot (if container was searched)
        if self.containerPOI.state == "searched" and self.containerPOI.secrets_loot then
            for _, lootId in ipairs(self.containerPOI.secrets_loot) do
                lootIds[#lootIds + 1] = lootId
            end
        end

        -- Instantiate each item
        for _, lootId in ipairs(lootIds) do
            local item = nil

            -- If it's a string, treat as template ID
            if type(lootId) == "string" then
                item = inventory.createItemFromTemplate(lootId)
            elseif type(lootId) == "table" then
                -- If it's a table, use it directly as config
                item = inventory.createItem(lootId)
            end

            if item then
                self.lootItems[#self.lootItems + 1] = item
            end
        end
    end

    ----------------------------------------------------------------------------
    -- TAKE ITEMS
    ----------------------------------------------------------------------------

    --- Take a single item from the loot
    -- @param index number: Index in lootItems
    function modal:takeItem(index)
        local item = self.lootItems[index]
        if not item then return false end
        if not self.recipientPC or not self.recipientPC.inventory then return false end

        -- Try to add to recipient's inventory (prefer pack)
        local success, reason = self.recipientPC.inventory:addItem(item, inventory.LOCATIONS.PACK)

        if success then
            -- Remove from loot
            table.remove(self.lootItems, index)

            -- Update POI state
            self:updateContainerLoot()

            print("[LOOT] " .. self.recipientPC.name .. " took " .. item.name)
            self.eventBus:emit("item_looted", {
                item = item,
                recipient = self.recipientPC,
                poi = self.containerPOI,
            })

            -- Close if empty
            if #self.lootItems == 0 then
                self:markContainerEmpty()
            end

            return true
        else
            print("[LOOT] Cannot take " .. item.name .. ": " .. (reason or "unknown"))
            return false
        end
    end

    --- Take all items from the loot
    function modal:takeAll()
        -- Take items in reverse order to avoid index issues
        for i = #self.lootItems, 1, -1 do
            self:takeItem(i)
        end
    end

    --- Update the container's loot array to reflect remaining items
    function modal:updateContainerLoot()
        if not self.containerPOI then return end

        -- Update the POI's loot to only contain remaining items
        -- Store as inline configs (not template IDs) since they're now instantiated
        local remainingLoot = {}
        for _, item in ipairs(self.lootItems) do
            -- Convert item back to a config for storage
            remainingLoot[#remainingLoot + 1] = {
                name = item.name,
                size = item.size,
                durability = item.durability,
                stackable = item.stackable,
                stackSize = item.stackSize,
                quantity = item.quantity,
                properties = item.properties,
                templateId = item.templateId,
                keyId = item.keyId,
            }
        end

        self.containerPOI.loot = remainingLoot

        -- Update room manager state
        if self.roomManager then
            self.roomManager:updateFeatureState(
                self.containerRoomId,
                self.containerPOI.id,
                { loot = remainingLoot }
            )
        end
    end

    --- Mark container as empty
    function modal:markContainerEmpty()
        if not self.containerPOI then return end

        self.containerPOI.state = "empty"
        self.containerPOI.loot = {}

        -- Update room manager
        if self.roomManager then
            self.roomManager:updateFeatureState(
                self.containerRoomId,
                self.containerPOI.id,
                { state = "empty", loot = {} }
            )
        end

        self.eventBus:emit("container_emptied", {
            poi = self.containerPOI,
            roomId = self.containerRoomId,
        })
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function modal:update(dt)
        -- No animations needed for now
    end

    ----------------------------------------------------------------------------
    -- DRAW
    ----------------------------------------------------------------------------

    function modal:draw()
        if not self.isOpen or not love then return end

        -- Dark overlay
        love.graphics.setColor(M.COLORS.overlay)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())

        -- Main panel
        love.graphics.setColor(M.COLORS.panel_bg)
        love.graphics.rectangle("fill", self.x, self.y, M.LAYOUT.WIDTH, M.LAYOUT.HEIGHT, 8, 8)

        love.graphics.setColor(M.COLORS.panel_border)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", self.x, self.y, M.LAYOUT.WIDTH, M.LAYOUT.HEIGHT, 8, 8)
        love.graphics.setLineWidth(1)

        -- Header
        love.graphics.setColor(M.COLORS.header_bg)
        love.graphics.rectangle("fill", self.x, self.y, M.LAYOUT.WIDTH, 40, 8, 0)

        love.graphics.setColor(M.COLORS.text_highlight)
        love.graphics.print(self.containerName, self.x + M.LAYOUT.PADDING, self.y + 12)

        -- Close button
        love.graphics.setColor(M.COLORS.text_dim)
        love.graphics.print("[X]", self.x + M.LAYOUT.WIDTH - 35, self.y + 12)

        -- Recipient selector
        local recipientY = self.y + 50
        love.graphics.setColor(M.COLORS.text)
        love.graphics.print("Take to:", self.x + M.LAYOUT.PADDING, recipientY)

        -- PC tabs
        local tabX = self.x + 80
        for i, pc in ipairs(self.guild) do
            local isSelected = (i == self.recipientPCIndex)
            local tabW = 55

            if isSelected then
                love.graphics.setColor(0.3, 0.25, 0.2, 1)
            else
                love.graphics.setColor(0.18, 0.16, 0.14, 1)
            end
            love.graphics.rectangle("fill", tabX + (i-1) * (tabW + 4), recipientY - 2, tabW, 22, 3, 3)

            love.graphics.setColor(isSelected and M.COLORS.text_highlight or M.COLORS.text_dim)
            local shortName = string.sub(pc.name, 1, 6)
            love.graphics.print(shortName, tabX + (i-1) * (tabW + 4) + 4, recipientY)
        end

        -- Loot grid
        local gridY = recipientY + 35
        love.graphics.setColor(M.COLORS.text)
        love.graphics.print("Contents:", self.x + M.LAYOUT.PADDING, gridY)
        gridY = gridY + 22

        local slotSize = M.LAYOUT.SLOT_SIZE
        local spacing = M.LAYOUT.SLOT_SPACING
        local cols = 5
        local maxSlots = 15

        for i = 1, maxSlots do
            local row = math.floor((i - 1) / cols)
            local col = (i - 1) % cols
            local slotX = self.x + M.LAYOUT.PADDING + col * (slotSize + spacing)
            local slotY = gridY + row * (slotSize + spacing)

            local item = self.lootItems[i]
            local isHovered = (self.hoveredSlot == i)

            -- Slot background
            if item then
                love.graphics.setColor(isHovered and M.COLORS.slot_hover or M.COLORS.slot_filled)
            else
                love.graphics.setColor(M.COLORS.slot_empty)
            end
            love.graphics.rectangle("fill", slotX, slotY, slotSize, slotSize, 4, 4)

            -- Slot border
            if isHovered and item then
                love.graphics.setColor(M.COLORS.text_highlight)
                love.graphics.setLineWidth(2)
            else
                love.graphics.setColor(0.4, 0.4, 0.4, 0.5)
                love.graphics.setLineWidth(1)
            end
            love.graphics.rectangle("line", slotX, slotY, slotSize, slotSize, 4, 4)
            love.graphics.setLineWidth(1)

            -- Item display
            if item then
                love.graphics.setColor(M.COLORS.text)
                local initial = string.sub(item.name or "?", 1, 2)
                love.graphics.print(initial, slotX + 4, slotY + 4)

                if item.stackable and item.quantity and item.quantity > 1 then
                    love.graphics.setColor(M.COLORS.text_dim)
                    love.graphics.print("x" .. item.quantity, slotX + slotSize - 22, slotY + slotSize - 14)
                end
            end
        end

        -- Buttons
        local buttonY = self.y + M.LAYOUT.HEIGHT - M.LAYOUT.BUTTON_HEIGHT - M.LAYOUT.PADDING
        local buttonW = (M.LAYOUT.WIDTH - M.LAYOUT.PADDING * 3) / 2

        -- Take All button
        local takeAllHovered = (self.hoveredButton == "take_all")
        love.graphics.setColor(takeAllHovered and M.COLORS.button_hover or M.COLORS.button)
        love.graphics.rectangle("fill", self.x + M.LAYOUT.PADDING, buttonY, buttonW, M.LAYOUT.BUTTON_HEIGHT, 4, 4)
        love.graphics.setColor(M.COLORS.button_text)
        love.graphics.print("Take All", self.x + M.LAYOUT.PADDING + 25, buttonY + 10)

        -- Close button
        local closeHovered = (self.hoveredButton == "close")
        love.graphics.setColor(closeHovered and M.COLORS.button_hover or M.COLORS.button)
        love.graphics.rectangle("fill", self.x + M.LAYOUT.PADDING * 2 + buttonW, buttonY, buttonW, M.LAYOUT.BUTTON_HEIGHT, 4, 4)
        love.graphics.setColor(M.COLORS.button_text)
        love.graphics.print("Close", self.x + M.LAYOUT.PADDING * 2 + buttonW + 35, buttonY + 10)

        -- Empty message
        if #self.lootItems == 0 then
            love.graphics.setColor(M.COLORS.text_dim)
            love.graphics.print("Empty", self.x + M.LAYOUT.WIDTH/2 - 20, gridY + 50)
        end

        -- Tooltip
        self:drawTooltip()
    end

    function modal:drawTooltip()
        if not self.tooltip then return end

        local mouseX, mouseY = love.mouse.getPosition()
        local padding = 6
        local font = love.graphics.getFont()
        local textWidth = font:getWidth(self.tooltip)
        local textHeight = font:getHeight()

        local tipX = mouseX + 12
        local tipY = mouseY + 8
        local tipW = textWidth + padding * 2
        local tipH = textHeight + padding * 2

        -- Keep on screen
        local screenW, screenH = love.graphics.getDimensions()
        if tipX + tipW > screenW then tipX = mouseX - tipW - 5 end
        if tipY + tipH > screenH then tipY = mouseY - tipH - 5 end

        love.graphics.setColor(0.1, 0.1, 0.12, 0.95)
        love.graphics.rectangle("fill", tipX, tipY, tipW, tipH, 3, 3)

        love.graphics.setColor(M.COLORS.text)
        love.graphics.print(self.tooltip, tipX + padding, tipY + padding)
    end

    ----------------------------------------------------------------------------
    -- INPUT
    ----------------------------------------------------------------------------

    function modal:keypressed(key)
        if not self.isOpen then return false end

        if key == "escape" then
            self:close()
            return true
        end

        -- Number keys to switch recipient
        local keyNum = tonumber(key)
        if keyNum and keyNum >= 1 and keyNum <= #self.guild then
            self.recipientPCIndex = keyNum
            self.recipientPC = self.guild[keyNum]
            return true
        end

        return true
    end

    function modal:mousepressed(x, y, button)
        if not self.isOpen then return false end

        -- Check if clicking outside to close
        if x < self.x or x > self.x + M.LAYOUT.WIDTH or
           y < self.y or y > self.y + M.LAYOUT.HEIGHT then
            self:close()
            return true
        end

        -- Close X button
        if x >= self.x + M.LAYOUT.WIDTH - 40 and x < self.x + M.LAYOUT.WIDTH and
           y >= self.y and y < self.y + 40 then
            self:close()
            return true
        end

        -- PC tabs
        local recipientY = self.y + 50
        local tabX = self.x + 80
        for i = 1, #self.guild do
            local tabW = 55
            local tx = tabX + (i-1) * (tabW + 4)
            if x >= tx and x < tx + tabW and y >= recipientY - 2 and y < recipientY + 20 then
                self.recipientPCIndex = i
                self.recipientPC = self.guild[i]
                return true
            end
        end

        -- Loot slots (click to take)
        if self.hoveredSlot and self.lootItems[self.hoveredSlot] then
            self:takeItem(self.hoveredSlot)
            return true
        end

        -- Buttons
        local buttonY = self.y + M.LAYOUT.HEIGHT - M.LAYOUT.BUTTON_HEIGHT - M.LAYOUT.PADDING
        local buttonW = (M.LAYOUT.WIDTH - M.LAYOUT.PADDING * 3) / 2

        if y >= buttonY and y < buttonY + M.LAYOUT.BUTTON_HEIGHT then
            if x >= self.x + M.LAYOUT.PADDING and x < self.x + M.LAYOUT.PADDING + buttonW then
                self:takeAll()
                self:close()
                return true
            elseif x >= self.x + M.LAYOUT.PADDING * 2 + buttonW and x < self.x + M.LAYOUT.WIDTH - M.LAYOUT.PADDING then
                self:close()
                return true
            end
        end

        return true
    end

    function modal:mousemoved(x, y, dx, dy)
        if not self.isOpen then return false end

        self.hoveredSlot = nil
        self.hoveredButton = nil
        self.tooltip = nil

        -- Check loot slots
        local gridY = self.y + 50 + 35 + 22
        local slotSize = M.LAYOUT.SLOT_SIZE
        local spacing = M.LAYOUT.SLOT_SPACING
        local cols = 5

        for i = 1, #self.lootItems do
            local row = math.floor((i - 1) / cols)
            local col = (i - 1) % cols
            local slotX = self.x + M.LAYOUT.PADDING + col * (slotSize + spacing)
            local slotY = gridY + row * (slotSize + spacing)

            if x >= slotX and x < slotX + slotSize and
               y >= slotY and y < slotY + slotSize then
                self.hoveredSlot = i
                local item = self.lootItems[i]
                if item then
                    self.tooltip = item.name
                end
                return true
            end
        end

        -- Check buttons
        local buttonY = self.y + M.LAYOUT.HEIGHT - M.LAYOUT.BUTTON_HEIGHT - M.LAYOUT.PADDING
        local buttonW = (M.LAYOUT.WIDTH - M.LAYOUT.PADDING * 3) / 2

        if y >= buttonY and y < buttonY + M.LAYOUT.BUTTON_HEIGHT then
            if x >= self.x + M.LAYOUT.PADDING and x < self.x + M.LAYOUT.PADDING + buttonW then
                self.hoveredButton = "take_all"
            elseif x >= self.x + M.LAYOUT.PADDING * 2 + buttonW and x < self.x + M.LAYOUT.WIDTH - M.LAYOUT.PADDING then
                self.hoveredButton = "close"
            end
        end

        return true
    end

    return modal
end

return M

```

---

## File: src/ui/minor_action_panel.lua

```lua
-- minor_action_panel.lua
-- Minor Action Declaration Panel for Majesty
-- Ticket S6.4: UI for the minor action declaration loop
--
-- Shows when the combat pauses for minor action declarations.
-- Displays pending minors and Resume button.

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- COLORS
--------------------------------------------------------------------------------
M.COLORS = {
    -- Panel
    panel_bg        = { 0.10, 0.08, 0.06, 0.90 },
    panel_border    = { 0.60, 0.55, 0.45, 1.0 },

    -- Header
    header_bg       = { 0.25, 0.22, 0.18, 1.0 },
    header_text     = { 0.95, 0.85, 0.65, 1.0 },

    -- Pending list
    list_bg         = { 0.15, 0.12, 0.10, 1.0 },
    list_item       = { 0.85, 0.82, 0.75, 1.0 },
    list_item_pc    = { 0.70, 0.85, 0.70, 1.0 },
    list_empty      = { 0.50, 0.48, 0.45, 0.8 },

    -- Resume button
    button_bg       = { 0.35, 0.55, 0.35, 1.0 },
    button_hover    = { 0.45, 0.65, 0.45, 1.0 },
    button_text     = { 0.95, 0.95, 0.90, 1.0 },

    -- Dim overlay
    dim_overlay     = { 0.0, 0.0, 0.0, 0.4 },
}

--------------------------------------------------------------------------------
-- LAYOUT CONSTANTS
--------------------------------------------------------------------------------
M.PANEL_WIDTH = 280
M.PANEL_PADDING = 12
M.HEADER_HEIGHT = 36
M.LIST_ITEM_HEIGHT = 28
M.BUTTON_HEIGHT = 40
M.BUTTON_MARGIN = 10

--------------------------------------------------------------------------------
-- MINOR ACTION PANEL FACTORY
--------------------------------------------------------------------------------

--- Create a new MinorActionPanel
-- @param config table: { eventBus, challengeController }
-- @return MinorActionPanel instance
function M.createMinorActionPanel(config)
    config = config or {}

    local panel = {
        eventBus = config.eventBus or events.globalBus,
        challengeController = config.challengeController,

        -- State
        isVisible = false,
        pendingMinors = {},

        -- Layout (computed)
        x = 0,
        y = 0,
        width = M.PANEL_WIDTH,
        height = 0,

        -- Interaction
        buttonHovered = false,

        colors = M.COLORS,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function panel:init()
        -- Listen for minor window start
        self.eventBus:on(events.EVENTS.MINOR_ACTION_WINDOW, function(data)
            if data.paused then
                self:show()
            end
        end)

        -- Listen for state changes
        self.eventBus:on("challenge_state_changed", function(data)
            if data.newState == "minor_window" then
                self:show()
            elseif data.newState == "resolving_minors" or
                   data.newState == "awaiting_action" or
                   data.newState == "count_up" then
                self:hide()
            end
        end)

        -- Listen for minor action declarations
        self.eventBus:on("minor_action_declared", function(data)
            self:updatePendingList()
        end)

        self.eventBus:on("minor_action_undeclared", function(data)
            self:updatePendingList()
        end)

        -- Listen for challenge end
        self.eventBus:on(events.EVENTS.CHALLENGE_END, function()
            self:hide()
        end)
    end

    ----------------------------------------------------------------------------
    -- VISIBILITY
    ----------------------------------------------------------------------------

    function panel:show()
        self.isVisible = true
        self:updatePendingList()
        self:updateLayout()
    end

    function panel:hide()
        self.isVisible = false
        self.pendingMinors = {}
    end

    function panel:updatePendingList()
        if self.challengeController then
            self.pendingMinors = self.challengeController:getPendingMinors() or {}
        else
            self.pendingMinors = {}
        end
        self:updateLayout()
    end

    function panel:updateLayout()
        local screenW, screenH = love.graphics.getDimensions()

        -- Calculate height based on pending count
        local listHeight = math.max(1, #self.pendingMinors) * M.LIST_ITEM_HEIGHT + M.PANEL_PADDING
        self.height = M.HEADER_HEIGHT + listHeight + M.BUTTON_HEIGHT + M.BUTTON_MARGIN * 2 + M.PANEL_PADDING * 2

        -- Position on right side of screen, below combat display
        self.x = screenW - self.width - 20
        self.y = screenH / 2 - self.height / 2
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function panel:update(dt)
        -- Could add animations here
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    ----------------------------------------------------------------------------

    function panel:draw()
        if not love or not self.isVisible then return end

        local screenW, screenH = love.graphics.getDimensions()

        -- Draw dim overlay behind panel (indicates paused state)
        love.graphics.setColor(self.colors.dim_overlay)
        love.graphics.rectangle("fill", 0, 0, screenW, screenH)

        -- Panel background
        love.graphics.setColor(self.colors.panel_bg)
        love.graphics.rectangle("fill", self.x, self.y, self.width, self.height, 6, 6)

        -- Panel border
        love.graphics.setColor(self.colors.panel_border)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", self.x, self.y, self.width, self.height, 6, 6)
        love.graphics.setLineWidth(1)

        -- Header
        self:drawHeader()

        -- Pending list
        self:drawPendingList()

        -- Resume button
        self:drawResumeButton()
    end

    function panel:drawHeader()
        local headerY = self.y

        -- Header background
        love.graphics.setColor(self.colors.header_bg)
        love.graphics.rectangle("fill", self.x, headerY, self.width, M.HEADER_HEIGHT, 6, 0)

        -- Header text
        love.graphics.setColor(self.colors.header_text)
        love.graphics.printf("Waiting for Minors...", self.x, headerY + 10, self.width, "center")
    end

    function panel:drawPendingList()
        local listY = self.y + M.HEADER_HEIGHT + M.PANEL_PADDING
        local listHeight = math.max(1, #self.pendingMinors) * M.LIST_ITEM_HEIGHT

        -- List background
        love.graphics.setColor(self.colors.list_bg)
        love.graphics.rectangle("fill", self.x + M.PANEL_PADDING, listY,
                                self.width - M.PANEL_PADDING * 2, listHeight, 4, 4)

        if #self.pendingMinors == 0 then
            -- Empty state
            love.graphics.setColor(self.colors.list_empty)
            love.graphics.printf("(None declared)", self.x + M.PANEL_PADDING,
                                 listY + 6, self.width - M.PANEL_PADDING * 2, "center")
        else
            -- List pending minors
            for i, minor in ipairs(self.pendingMinors) do
                local itemY = listY + (i - 1) * M.LIST_ITEM_HEIGHT + 4

                local textColor = minor.entity.isPC and self.colors.list_item_pc or self.colors.list_item
                love.graphics.setColor(textColor)

                local text = string.format("%d. %s - %s",
                    i,
                    minor.entity.name or "?",
                    minor.action.type or "action")

                love.graphics.print(text, self.x + M.PANEL_PADDING + 8, itemY)
            end
        end
    end

    function panel:drawResumeButton()
        local btnX = self.x + M.BUTTON_MARGIN
        local btnY = self.y + self.height - M.BUTTON_HEIGHT - M.BUTTON_MARGIN
        local btnW = self.width - M.BUTTON_MARGIN * 2
        local btnH = M.BUTTON_HEIGHT

        -- Button background
        local bgColor = self.buttonHovered and self.colors.button_hover or self.colors.button_bg
        love.graphics.setColor(bgColor)
        love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 6, 6)

        -- Button border
        love.graphics.setColor(self.colors.panel_border)
        love.graphics.rectangle("line", btnX, btnY, btnW, btnH, 6, 6)

        -- Button text
        love.graphics.setColor(self.colors.button_text)
        local btnText = #self.pendingMinors > 0 and
            string.format("Resume (%d pending)", #self.pendingMinors) or
            "Resume (None)"
        love.graphics.printf(btnText, btnX, btnY + 12, btnW, "center")
    end

    ----------------------------------------------------------------------------
    -- INPUT HANDLING
    ----------------------------------------------------------------------------

    function panel:mousepressed(x, y, button)
        if not self.isVisible then return false end
        if button ~= 1 then return false end

        -- Check Resume button
        local btnX = self.x + M.BUTTON_MARGIN
        local btnY = self.y + self.height - M.BUTTON_HEIGHT - M.BUTTON_MARGIN
        local btnW = self.width - M.BUTTON_MARGIN * 2
        local btnH = M.BUTTON_HEIGHT

        if x >= btnX and x <= btnX + btnW and y >= btnY and y <= btnY + btnH then
            -- Resume button clicked
            if self.challengeController then
                self.challengeController:resumeFromMinorWindow()
            end
            return true
        end

        return false
    end

    function panel:mousemoved(x, y, dx, dy)
        if not self.isVisible then return end

        -- Check if hovering Resume button
        local btnX = self.x + M.BUTTON_MARGIN
        local btnY = self.y + self.height - M.BUTTON_HEIGHT - M.BUTTON_MARGIN
        local btnW = self.width - M.BUTTON_MARGIN * 2
        local btnH = M.BUTTON_HEIGHT

        self.buttonHovered = (x >= btnX and x <= btnX + btnW and
                              y >= btnY and y <= btnY + btnH)
    end

    function panel:keypressed(key)
        if not self.isVisible then return false end

        -- SPACE or ENTER to resume
        if key == "space" or key == "return" then
            if self.challengeController then
                self.challengeController:resumeFromMinorWindow()
            end
            return true
        end

        return false
    end

    return panel
end

return M

```

---

## File: src/ui/narrative_view.lua

```lua
-- narrative_view.lua
-- Narrative Feed / POI Scrawler for Majesty
-- Ticket T2_12: Render room descriptions with POI highlighting
--
-- Design:
-- - Parse "Rich Text" with POI markers: {poi:id:Display Text}
-- - Render POIs in a different color
-- - Track screen-space coordinates for hitbox registration
-- - Optional typewriter effect

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- RICH TEXT TOKEN TYPES
--------------------------------------------------------------------------------
M.TOKEN_TYPES = {
    TEXT = "text",
    POI  = "poi",
}

--------------------------------------------------------------------------------
-- DEFAULT COLORS
--------------------------------------------------------------------------------
M.COLORS = {
    text       = { 0.9, 0.9, 0.85, 1.0 },   -- Off-white for normal text
    poi        = { 0.4, 0.8, 1.0, 1.0 },    -- Cyan for POIs
    poi_hover  = { 0.6, 1.0, 1.0, 1.0 },    -- Brighter cyan on hover
    background = { 0.1, 0.1, 0.12, 0.95 },  -- Dark background
}

--------------------------------------------------------------------------------
-- RICH TEXT PARSER
-- Parses strings like: "A heavy {poi:chest_01:ancient chest} sits here."
--------------------------------------------------------------------------------

--- Parse rich text into tokens
-- @param text string: Raw text with {poi:id:display} markers
-- @return table: Array of { type, text, poiId? }
function M.parseRichText(text)
    local tokens = {}
    local pos = 1
    local len = #text

    while pos <= len do
        -- Look for POI marker
        local startPos = text:find("{poi:", pos, true)

        if startPos then
            -- Add any text before the marker
            if startPos > pos then
                local plainText = text:sub(pos, startPos - 1)
                tokens[#tokens + 1] = {
                    type = M.TOKEN_TYPES.TEXT,
                    text = plainText,
                }
            end

            -- Parse the POI marker: {poi:id:display}
            local endPos = text:find("}", startPos, true)
            if endPos then
                local markerContent = text:sub(startPos + 5, endPos - 1)  -- Skip "{poi:"
                local colonPos = markerContent:find(":", 1, true)

                if colonPos then
                    local poiId = markerContent:sub(1, colonPos - 1)
                    local displayText = markerContent:sub(colonPos + 1)

                    tokens[#tokens + 1] = {
                        type = M.TOKEN_TYPES.POI,
                        text = displayText,
                        poiId = poiId,
                    }
                else
                    -- Malformed marker, treat as text
                    tokens[#tokens + 1] = {
                        type = M.TOKEN_TYPES.TEXT,
                        text = text:sub(startPos, endPos),
                    }
                end

                pos = endPos + 1
            else
                -- No closing brace, treat rest as text
                tokens[#tokens + 1] = {
                    type = M.TOKEN_TYPES.TEXT,
                    text = text:sub(startPos),
                }
                break
            end
        else
            -- No more markers, add remaining text
            tokens[#tokens + 1] = {
                type = M.TOKEN_TYPES.TEXT,
                text = text:sub(pos),
            }
            break
        end
    end

    return tokens
end

--------------------------------------------------------------------------------
-- NARRATIVE VIEW FACTORY
--------------------------------------------------------------------------------

--- Create a new NarrativeView
-- @param config table: { x, y, width, height, font, inputManager, eventBus }
-- @return NarrativeView instance
function M.createNarrativeView(config)
    config = config or {}

    local view = {
        -- Position and size
        x      = config.x or 0,
        y      = config.y or 0,
        width  = config.width or 400,
        height = config.height or 300,

        -- Font (LÖVE font object, or nil for default)
        font       = config.font,
        lineHeight = config.lineHeight or 20,
        padding    = config.padding or 10,

        -- Colors
        colors = config.colors or M.COLORS,

        -- References
        inputManager = config.inputManager,
        eventBus     = config.eventBus or events.globalBus,

        -- Current content
        tokens       = {},          -- Parsed tokens
        rawText      = "",          -- Original text
        poiHitboxes  = {},          -- POI id -> { x, y, width, height }

        -- Typewriter effect
        typewriterEnabled = config.typewriterEnabled or false,
        typewriterSpeed   = config.typewriterSpeed or 30,  -- chars per second
        typewriterPos     = 0,       -- Current character position
        typewriterTime    = 0,       -- Accumulated time

        -- Hover state
        hoveredPOI = nil,
    }

    ----------------------------------------------------------------------------
    -- CONTENT MANAGEMENT
    ----------------------------------------------------------------------------

    --- Set the narrative text
    -- @param text string: Rich text with POI markers
    -- @param instant boolean: If true, skip typewriter effect
    function view:setText(text, instant)
        self.rawText = text
        self.tokens = M.parseRichText(text)
        self.poiHitboxes = {}

        if self.typewriterEnabled and not instant then
            self.typewriterPos = 0
            self.typewriterTime = 0
        else
            self.typewriterPos = #text
        end

        -- Recalculate hitboxes
        self:calculateHitboxes()
    end

    --- Append text to current content
    function view:appendText(text)
        self:setText(self.rawText .. text)
    end

    --- Clear all content
    function view:clear()
        self.rawText = ""
        self.tokens = {}
        self.poiHitboxes = {}
        self.typewriterPos = 0

        -- Unregister hitboxes from input manager
        if self.inputManager then
            for poiId, _ in pairs(self.poiHitboxes) do
                self.inputManager:unregisterHitbox(poiId)
            end
        end
    end

    ----------------------------------------------------------------------------
    -- HITBOX CALCULATION
    -- Calculate screen positions for POI text areas
    ----------------------------------------------------------------------------

    --- Calculate hitboxes for all POIs
    function view:calculateHitboxes()
        -- Clear old hitboxes from input manager
        if self.inputManager then
            for poiId, _ in pairs(self.poiHitboxes) do
                self.inputManager:unregisterHitbox(poiId)
            end
        end

        self.poiHitboxes = {}

        -- Simulate text layout to find POI positions
        local x = self.x + self.padding
        local y = self.y + self.padding
        local maxWidth = self.width - (self.padding * 2)

        -- Get font metrics (use default values if not in LÖVE context)
        local charWidth = 8   -- Approximate
        local charHeight = self.lineHeight
        local spaceWidth = charWidth

        if love then
            local font = self.font or love.graphics.getFont()
            if font then
                charHeight = font:getHeight()
                charWidth = font:getWidth("M")
                spaceWidth = font:getWidth(" ")
            end
        end

        for _, token in ipairs(self.tokens) do
            local text = token.text

            -- Split by newlines first (matching draw logic)
            local lines = {}
            local currentPos = 1
            while currentPos <= #text do
                local newlinePos = text:find("\n", currentPos, true)
                if newlinePos then
                    lines[#lines + 1] = text:sub(currentPos, newlinePos - 1)
                    currentPos = newlinePos + 1
                else
                    lines[#lines + 1] = text:sub(currentPos)
                    break
                end
            end

            -- Track POI start position (for multi-word POIs)
            local poiStartX = x
            local poiStartY = y

            for lineIdx, line in ipairs(lines) do
                -- Process words in this line
                for word in line:gmatch("%S+") do
                    local wordWidth = #word * charWidth
                    if love then
                        local font = self.font or love.graphics.getFont()
                        if font then
                            wordWidth = font:getWidth(word)
                        end
                    end

                    -- Check for line wrap
                    if x + wordWidth > self.x + maxWidth then
                        x = self.x + self.padding
                        y = y + charHeight
                    end

                    -- Advance position
                    x = x + wordWidth + spaceWidth
                end

                -- Move to next line if there are more lines
                if lineIdx < #lines then
                    x = self.x + self.padding
                    y = y + charHeight
                end
            end

            -- If this is a POI token, record hitbox for entire POI
            if token.type == M.TOKEN_TYPES.POI then
                -- Calculate POI width (simple approximation)
                local poiWidth = 0
                if love then
                    local font = self.font or love.graphics.getFont()
                    if font then
                        -- Get width of POI text without newlines
                        local cleanText = token.text:gsub("\n", " ")
                        poiWidth = font:getWidth(cleanText)
                    end
                else
                    poiWidth = #token.text * charWidth
                end

                self.poiHitboxes[token.poiId] = {
                    x = poiStartX,
                    y = poiStartY,
                    width = poiWidth,
                    height = charHeight,
                }

                -- Register with input manager
                if self.inputManager then
                    self.inputManager:registerHitbox(
                        token.poiId,
                        "poi",
                        poiStartX, poiStartY, poiWidth, charHeight,
                        { poiId = token.poiId, displayText = token.text }
                    )
                end
            end
        end
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    --- Update the view (for typewriter effect)
    -- @param dt number: Delta time in seconds
    function view:update(dt)
        -- Typewriter effect
        if self.typewriterEnabled and self.typewriterPos < #self.rawText then
            self.typewriterTime = self.typewriterTime + dt
            local charsToShow = math.floor(self.typewriterTime * self.typewriterSpeed)
            self.typewriterPos = math.min(charsToShow, #self.rawText)
        end

        -- Check for hover (if input manager tracks mouse position)
        if self.inputManager then
            local mx = self.inputManager.currentMouseX
            local my = self.inputManager.currentMouseY

            self.hoveredPOI = nil
            for poiId, hb in pairs(self.poiHitboxes) do
                if mx >= hb.x and mx <= hb.x + hb.width and
                   my >= hb.y and my <= hb.y + hb.height then
                    self.hoveredPOI = poiId
                    break
                end
            end
        end
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    -- Note: Actual rendering requires LÖVE 2D context
    ----------------------------------------------------------------------------

    --- Draw the narrative view
    -- Call this from love.draw()
    function view:draw()
        if not love then
            return  -- Can't draw without LÖVE
        end

        -- Draw background
        love.graphics.setColor(self.colors.background)
        love.graphics.rectangle("fill", self.x, self.y, self.width, self.height)

        -- Set font
        local oldFont = love.graphics.getFont()
        if self.font then
            love.graphics.setFont(self.font)
        end

        -- Draw text with POI highlighting
        local x = self.x + self.padding
        local y = self.y + self.padding
        local maxWidth = self.width - (self.padding * 2)
        local charHeight = love.graphics.getFont():getHeight()
        local charsDrawn = 0

        for _, token in ipairs(self.tokens) do
            -- Check typewriter limit
            if charsDrawn >= self.typewriterPos then
                break
            end

            -- Set color based on token type
            if token.type == M.TOKEN_TYPES.POI then
                if self.hoveredPOI == token.poiId then
                    love.graphics.setColor(self.colors.poi_hover)
                else
                    love.graphics.setColor(self.colors.poi)
                end
            else
                love.graphics.setColor(self.colors.text)
            end

            -- Draw text with proper newline and word wrapping
            local text = token.text
            local remainingChars = self.typewriterPos - charsDrawn

            -- Truncate for typewriter
            if #text > remainingChars then
                text = text:sub(1, remainingChars)
            end

            -- Split by newlines first
            local lines = {}
            local currentPos = 1
            while currentPos <= #text do
                local newlinePos = text:find("\n", currentPos, true)
                if newlinePos then
                    lines[#lines + 1] = text:sub(currentPos, newlinePos - 1)
                    currentPos = newlinePos + 1
                else
                    lines[#lines + 1] = text:sub(currentPos)
                    break
                end
            end

            for lineIdx, line in ipairs(lines) do
                -- Process words in this line
                for word in line:gmatch("%S+") do
                    local wordWidth = love.graphics.getFont():getWidth(word)
                    local spaceWidth = love.graphics.getFont():getWidth(" ")

                    -- Line wrap
                    if x + wordWidth > self.x + maxWidth then
                        x = self.x + self.padding
                        y = y + charHeight
                    end

                    -- Draw word
                    love.graphics.print(word, x, y)
                    x = x + wordWidth + spaceWidth
                end

                -- Move to next line if there are more lines (newline was in original text)
                if lineIdx < #lines then
                    x = self.x + self.padding
                    y = y + charHeight
                end
            end

            charsDrawn = charsDrawn + #token.text
        end

        -- Restore font
        if oldFont then
            love.graphics.setFont(oldFont)
        end
    end

    ----------------------------------------------------------------------------
    -- UTILITY
    ----------------------------------------------------------------------------

    --- Get POI at screen position
    function view:getPOIAt(screenX, screenY)
        for poiId, hb in pairs(self.poiHitboxes) do
            if screenX >= hb.x and screenX <= hb.x + hb.width and
               screenY >= hb.y and screenY <= hb.y + hb.height then
                return poiId
            end
        end
        return nil
    end

    --- Check if typewriter effect is complete
    function view:isTypewriterComplete()
        return self.typewriterPos >= #self.rawText
    end

    --- Skip to end of typewriter effect
    function view:skipTypewriter()
        self.typewriterPos = #self.rawText
    end

    --- Resize the view
    function view:resize(width, height)
        self.width = width
        self.height = height
        self:calculateHitboxes()
    end

    --- Move the view
    function view:setPosition(x, y)
        self.x = x
        self.y = y
        self:calculateHitboxes()
    end

    return view
end

return M

```

---

## File: src/ui/player_hand.lua

```lua
-- player_hand.lua
-- Player Hand Management for Majesty
-- Ticket S4.8: Interactive card play with visible hand
--
-- Each PC has a hand of 4 cards at the start of a round.
-- 1 card is used for initiative, leaving 3 for actions.
-- Players select cards from their hand to perform actions.
--
-- Suit -> Action mapping (p. 111-115):
-- - SWORDS: Attack (melee requires engagement, missile uses ammo)
-- - PENTACLES: Roughhouse (Trip, Disarm, Displace)
-- - WANDS: Banter (attacks Morale), Intimidate
-- - CUPS: Defend, Aid Another, Heal

local events = require('logic.events')
local constants = require('constants')

local M = {}

--------------------------------------------------------------------------------
-- HAND SIZE CONSTANTS
--------------------------------------------------------------------------------
M.FULL_HAND_SIZE = 4      -- Cards drawn at start of round
M.COMBAT_HAND_SIZE = 3    -- Cards remaining after initiative

--------------------------------------------------------------------------------
-- ACTION MAPPING BY SUIT
--------------------------------------------------------------------------------
M.SUIT_ACTIONS = {
    [constants.SUITS.SWORDS] = {
        primary = "attack",
        options = { "melee", "missile" },
        description = "Attack - deal wounds",
    },
    [constants.SUITS.PENTACLES] = {
        primary = "roughhouse",
        options = { "trip", "disarm", "displace", "grapple" },
        description = "Roughhouse - battlefield control",
    },
    [constants.SUITS.WANDS] = {
        primary = "banter",
        options = { "banter", "intimidate", "cast" },
        description = "Banter - attack morale",
    },
    [constants.SUITS.CUPS] = {
        primary = "defend",
        options = { "defend", "dodge", "riposte", "heal", "aid", "shield" },
        description = "Defend - protect and support",
    },
}

--------------------------------------------------------------------------------
-- PLAYER HAND FACTORY
--------------------------------------------------------------------------------

--- Create a new PlayerHand manager
-- @param config table: { eventBus, playerDeck, guild }
-- @return PlayerHand instance
function M.createPlayerHand(config)
    config = config or {}

    local hand = {
        eventBus   = config.eventBus or events.globalBus,
        playerDeck = config.playerDeck,
        guild      = config.guild or {},

        -- Hand state per PC: pcId -> { cards = {}, initiativeCard = nil }
        hands = {},

        -- Currently selected card (for action)
        selectedCard = nil,
        selectedCardIndex = nil,
        selectedPC = nil,

        -- UI state
        hoveredCardIndex = nil,
        isDragging = false,
        dragCard = nil,
        dragX = 0,
        dragY = 0,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function hand:init()
        -- Listen for round start to draw hands
        self.eventBus:on("initiative_phase_start", function(data)
            self:drawAllHands()
        end)

        -- Listen for challenge end to discard all hands
        self.eventBus:on(events.EVENTS.CHALLENGE_END, function(data)
            self:discardAllHands()
        end)
    end

    ----------------------------------------------------------------------------
    -- HAND MANAGEMENT
    ----------------------------------------------------------------------------

    --- Draw full hands for all PCs at start of round
    function hand:drawAllHands()
        for _, pc in ipairs(self.guild) do
            self:drawHand(pc)
        end
        print("[PlayerHand] Drew hands for " .. #self.guild .. " PCs")
    end

    --- Draw a full hand for a specific PC
    function hand:drawHand(pc)
        if not pc or not pc.id then return end
        if not self.playerDeck then return end

        self.hands[pc.id] = {
            cards = {},
            initiativeCard = nil,
        }

        -- Draw FULL_HAND_SIZE cards
        for _ = 1, M.FULL_HAND_SIZE do
            local card = self.playerDeck:draw()
            if card then
                self.hands[pc.id].cards[#self.hands[pc.id].cards + 1] = card
            end
        end

        print("[PlayerHand] " .. pc.name .. " drew " .. #self.hands[pc.id].cards .. " cards")
    end

    --- Discard all hands back to deck
    function hand:discardAllHands()
        for pcId, handData in pairs(self.hands) do
            -- Discard remaining cards
            for _, card in ipairs(handData.cards) do
                if self.playerDeck then
                    self.playerDeck:discard(card)
                end
            end
            -- Discard initiative card if still held
            if handData.initiativeCard and self.playerDeck then
                self.playerDeck:discard(handData.initiativeCard)
            end
        end
        self.hands = {}
        self.selectedCard = nil
        self.selectedCardIndex = nil
        self.selectedPC = nil
        print("[PlayerHand] Discarded all hands")
    end

    --- Get a PC's current hand
    function hand:getHand(pc)
        if not pc or not pc.id then return {} end
        local handData = self.hands[pc.id]
        return handData and handData.cards or {}
    end

    --- Get card count for a PC
    function hand:getCardCount(pc)
        return #self:getHand(pc)
    end

    ----------------------------------------------------------------------------
    -- INITIATIVE CARD MANAGEMENT
    ----------------------------------------------------------------------------

    --- Use a card from hand for initiative
    -- @param pc table: The PC
    -- @param cardIndex number: Index in hand (1-4)
    -- @return table|nil: The card used, or nil if invalid
    function hand:useForInitiative(pc, cardIndex)
        local handData = self.hands[pc.id]
        if not handData then return nil end

        local cards = handData.cards
        if cardIndex < 1 or cardIndex > #cards then return nil end

        -- Remove card from hand and store as initiative
        local card = table.remove(cards, cardIndex)
        handData.initiativeCard = card

        print("[PlayerHand] " .. pc.name .. " used " .. card.name .. " for initiative")
        return card
    end

    --- Get the initiative card a PC submitted
    function hand:getInitiativeCard(pc)
        local handData = self.hands[pc.id]
        return handData and handData.initiativeCard
    end

    ----------------------------------------------------------------------------
    -- CARD SELECTION FOR ACTIONS
    ----------------------------------------------------------------------------

    --- Select a card from a PC's hand
    -- @param pc table: The PC
    -- @param cardIndex number: Index in hand (1-3)
    -- @return boolean: success
    function hand:selectCard(pc, cardIndex)
        local cards = self:getHand(pc)
        if cardIndex < 1 or cardIndex > #cards then
            return false
        end

        self.selectedPC = pc
        self.selectedCardIndex = cardIndex
        self.selectedCard = cards[cardIndex]

        self.eventBus:emit("card_selected", {
            pc = pc,
            card = self.selectedCard,
            cardIndex = cardIndex,
            suitActions = M.SUIT_ACTIONS[self.selectedCard.suit],
        })

        print("[PlayerHand] " .. pc.name .. " selected: " .. self.selectedCard.name)
        return true
    end

    --- Clear card selection
    function hand:clearSelection()
        self.selectedPC = nil
        self.selectedCardIndex = nil
        self.selectedCard = nil

        self.eventBus:emit("card_deselected", {})
    end

    --- Use the selected card for an action (removes from hand)
    -- @return table|nil: The card used
    function hand:useSelectedCard()
        if not self.selectedPC or not self.selectedCardIndex then
            return nil
        end

        local handData = self.hands[self.selectedPC.id]
        if not handData then return nil end

        local card = table.remove(handData.cards, self.selectedCardIndex)

        -- Discard the used card
        if self.playerDeck then
            self.playerDeck:discard(card)
        end

        local usedCard = self.selectedCard
        self:clearSelection()

        print("[PlayerHand] Used card: " .. usedCard.name)
        return usedCard
    end

    --- Get the currently selected card
    function hand:getSelectedCard()
        return self.selectedCard
    end

    --- Check if a card is selected
    function hand:hasSelection()
        return self.selectedCard ~= nil
    end

    ----------------------------------------------------------------------------
    -- SUIT HELPERS
    ----------------------------------------------------------------------------

    --- Get valid actions for a card's suit
    function hand:getActionsForCard(card)
        if not card or not card.suit then
            return nil
        end
        return M.SUIT_ACTIONS[card.suit]
    end

    --- Check if a card can be used for a specific action type
    function hand:canUseForAction(card, actionType)
        local suitActions = self:getActionsForCard(card)
        if not suitActions then return false end

        for _, opt in ipairs(suitActions.options) do
            if opt == actionType then
                return true
            end
        end
        return false
    end

    --- Get the primary action for a card's suit
    function hand:getPrimaryAction(card)
        local suitActions = self:getActionsForCard(card)
        return suitActions and suitActions.primary
    end

    ----------------------------------------------------------------------------
    -- QUERIES
    ----------------------------------------------------------------------------

    function hand:getSelectedPC()
        return self.selectedPC
    end

    function hand:getSelectedCardIndex()
        return self.selectedCardIndex
    end

    --- Get suit name for display
    function hand:getSuitName(suit)
        if suit == constants.SUITS.SWORDS then return "Swords"
        elseif suit == constants.SUITS.PENTACLES then return "Pentacles"
        elseif suit == constants.SUITS.CUPS then return "Cups"
        elseif suit == constants.SUITS.WANDS then return "Wands"
        else return "Major Arcana"
        end
    end

    return hand
end

return M

```

---

## File: src/ui/screens/camp_screen.lua

```lua
-- camp_screen.lua
-- The Camp Screen UI for Majesty
-- Ticket S8.5: Camp Phase visualization and interaction
--
-- Layout:
-- +------------------------------------------+
-- |           STEP INDICATOR BAR             |
-- +----------+------------------+------------+
-- |  Char 1  |                  |  Char 3    |
-- +----------+    CAMPFIRE      +------------+
-- |  Char 2  |    (center)      |  Char 4    |
-- +----------+------------------+------------+
-- |          ACTION PANEL (context-aware)    |
-- +------------------------------------------+
--
-- Reuses character_plate.lua from S5.1

local events = require('logic.events')
local character_plate = require('ui.character_plate')
local camp_controller = require('logic.camp_controller')
local camp_actions = require('logic.camp_actions')
local camp_prompts = require('data.camp_prompts')

local M = {}

--------------------------------------------------------------------------------
-- LAYOUT CONSTANTS
--------------------------------------------------------------------------------
M.LAYOUT = {
    STEP_BAR_HEIGHT   = 50,
    ACTION_PANEL_HEIGHT = 120,
    PADDING           = 15,
    PLATE_WIDTH       = 200,
    FIRE_SIZE         = 150,
}

--------------------------------------------------------------------------------
-- COLORS
--------------------------------------------------------------------------------
M.COLORS = {
    background     = { 0.05, 0.05, 0.08, 1.0 },   -- Dark night sky
    step_bar_bg    = { 0.10, 0.10, 0.12, 0.95 },
    step_active    = { 0.85, 0.65, 0.25, 1.0 },   -- Warm gold for current step
    step_complete  = { 0.35, 0.55, 0.35, 1.0 },   -- Muted green for done
    step_pending   = { 0.35, 0.35, 0.40, 1.0 },   -- Grey for not yet
    step_text      = { 0.90, 0.85, 0.75, 1.0 },
    fire_outer     = { 0.80, 0.40, 0.10, 0.8 },
    fire_inner     = { 1.00, 0.75, 0.30, 1.0 },
    fire_glow      = { 0.95, 0.60, 0.20, 0.15 },
    panel_bg       = { 0.12, 0.12, 0.14, 0.95 },
    panel_border   = { 0.30, 0.28, 0.25, 1.0 },
    button_bg      = { 0.18, 0.18, 0.20, 1.0 },
    button_hover   = { 0.25, 0.25, 0.28, 1.0 },
    button_text    = { 0.90, 0.85, 0.80, 1.0 },
    bond_charged   = { 0.70, 0.55, 0.85, 1.0 },   -- Purple for charged bonds
    bond_spent     = { 0.40, 0.40, 0.45, 0.5 },   -- Grey for spent bonds
    warning        = { 0.85, 0.40, 0.35, 1.0 },   -- Red for warnings
}

--------------------------------------------------------------------------------
-- STEP NAMES
--------------------------------------------------------------------------------
M.STEP_NAMES = {
    [0] = "Setup",
    [1] = "Actions",
    [2] = "Break Bread",
    [3] = "Watch",
    [4] = "Recovery",
    [5] = "Teardown",
}

--------------------------------------------------------------------------------
-- CAMP SCREEN FACTORY
--------------------------------------------------------------------------------

--- Create a new CampScreen
-- @param config table: { eventBus, campController, guild }
-- @return CampScreen instance
function M.createCampScreen(config)
    config = config or {}

    local screen = {
        -- Core systems
        eventBus       = config.eventBus or events.globalBus,
        campController = config.campController,
        guild          = config.guild or {},

        -- UI state
        width          = 800,
        height         = 600,
        characterPlates = {},
        hoverButton    = nil,
        selectedPC     = nil,      -- PC currently selecting action
        selectedAction = nil,      -- Action currently being configured

        -- Action menu state
        actionMenuOpen = false,
        actionMenuItems = {},
        actionMenuX    = 0,
        actionMenuY    = 0,

        -- Fellowship selection mode (S9.1)
        fellowshipMode = false,
        fellowshipActor = nil,      -- First PC selected for fellowship
        fellowshipActorIndex = nil,

        -- Drop zones (for ration drag-drop)
        dropZones      = {},

        -- Bond interaction
        hoveredBond    = nil,
        hoveredPlateIndex = nil,    -- Track which plate is hovered

        -- Prompt overlay (S9.3)
        promptOverlay  = nil,       -- { text, callback }

        -- Fire animation
        fireTimer      = 0,

        -- Colors
        colors         = config.colors or M.COLORS,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function screen:init()
        -- Create character plates for guild
        self:createCharacterPlates()

        -- Subscribe to camp events
        self:subscribeEvents()

        -- Initial layout
        if love then
            self:resize(love.graphics.getDimensions())
        end
    end

    function screen:subscribeEvents()
        -- Camp step changed
        self.eventBus:on(camp_controller.EVENTS.CAMP_STEP_CHANGED, function(data)
            self:onStepChanged(data)
        end)

        -- Camp action taken
        self.eventBus:on(camp_controller.EVENTS.CAMP_ACTION_TAKEN, function(data)
            self:onActionTaken(data)
        end)

        -- Ration consumed
        self.eventBus:on(camp_controller.EVENTS.RATION_CONSUMED, function(data)
            self:onRationConsumed(data)
        end)

        -- Bond spent
        self.eventBus:on(camp_controller.EVENTS.BOND_SPENT, function(data)
            self:onBondSpent(data)
        end)
    end

    ----------------------------------------------------------------------------
    -- EVENT HANDLERS
    ----------------------------------------------------------------------------

    function screen:onStepChanged(data)
        print("[CampScreen] Step changed to: " .. data.newState)
        -- Close any open menus and cancel fellowship mode
        self.actionMenuOpen = false
        self.selectedPC = nil
        self.fellowshipMode = false
        self.fellowshipActor = nil
        self.fellowshipActorIndex = nil
    end

    function screen:onActionTaken(data)
        print("[CampScreen] " .. data.entity.name .. " took action: " .. data.action.type)

        -- S9.3: Show campfire prompt for fellowship actions
        if data.action.type == "fellowship" and data.action.target then
            self:showFellowshipPrompt(data.entity, data.action.target)
        end
    end

    function screen:onRationConsumed(data)
        print("[CampScreen] " .. data.entity.name .. " ate")
    end

    function screen:onBondSpent(data)
        print("[CampScreen] Bond spent: " .. data.result)
    end

    ----------------------------------------------------------------------------
    -- CHARACTER PLATES
    ----------------------------------------------------------------------------

    function screen:createCharacterPlates()
        self.characterPlates = {}

        for i, adventurer in ipairs(self.guild) do
            local plate = character_plate.createCharacterPlate({
                eventBus = self.eventBus,
                entity = adventurer,
                x = 0,  -- Positioned in calculateLayout
                y = 0,
                width = M.LAYOUT.PLATE_WIDTH,
            })
            plate:init()

            -- Add bond drawing capability
            plate.drawBonds = function(p)
                self:drawBondsForPlate(p, i)
            end

            self.characterPlates[#self.characterPlates + 1] = plate
        end
    end

    function screen:setGuild(guild)
        self.guild = guild or {}
        self:createCharacterPlates()
        self:calculateLayout()
    end

    ----------------------------------------------------------------------------
    -- LAYOUT
    ----------------------------------------------------------------------------

    function screen:calculateLayout()
        local padding = M.LAYOUT.PADDING
        local plateW = M.LAYOUT.PLATE_WIDTH
        local stepH = M.LAYOUT.STEP_BAR_HEIGHT
        local actionH = M.LAYOUT.ACTION_PANEL_HEIGHT

        -- Available area for character plates and fire
        local contentY = stepH + padding
        local contentH = self.height - stepH - actionH - (padding * 2)

        -- Fire center position
        self.fireX = self.width / 2
        self.fireY = contentY + contentH / 2

        -- Position plates around the fire
        local count = #self.characterPlates
        local radius = math.min(self.width, contentH) * 0.35

        for i, plate in ipairs(self.characterPlates) do
            -- Distribute plates in a circle around the fire
            local angle = (i - 1) * (math.pi * 2 / count) - math.pi / 2
            local px = self.fireX + math.cos(angle) * radius - plateW / 2
            local py = self.fireY + math.sin(angle) * radius - plate:getHeight() / 2

            -- Keep within bounds
            px = math.max(padding, math.min(px, self.width - plateW - padding))
            py = math.max(contentY, math.min(py, contentY + contentH - plate:getHeight()))

            plate:setPosition(px, py)
        end

        -- Calculate drop zones for ration interaction
        self:calculateDropZones()
    end

    function screen:calculateDropZones()
        self.dropZones = {}

        -- Each character plate is a drop zone during Break Bread phase
        for i, plate in ipairs(self.characterPlates) do
            self.dropZones[#self.dropZones + 1] = {
                id = "plate_" .. i,
                entityIndex = i,
                x = plate.x,
                y = plate.y,
                width = M.LAYOUT.PLATE_WIDTH,
                height = plate:getHeight(),
            }
        end
    end

    function screen:resize(w, h)
        self.width = w
        self.height = h
        self:calculateLayout()
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function screen:update(dt)
        -- Fire animation
        self.fireTimer = self.fireTimer + dt

        -- Update character plates
        for _, plate in ipairs(self.characterPlates) do
            plate:update(dt)
        end
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    ----------------------------------------------------------------------------

    function screen:draw()
        if not love then return end

        -- Background
        love.graphics.setColor(self.colors.background)
        love.graphics.rectangle("fill", 0, 0, self.width, self.height)

        -- Fire glow (large area)
        self:drawFireGlow()

        -- Step indicator bar
        self:drawStepBar()

        -- Campfire
        self:drawCampfire()

        -- Character plates with bonds
        self:drawCharacterPlates()

        -- Action panel (context-aware)
        self:drawActionPanel()

        -- Action menu (if open)
        if self.actionMenuOpen then
            self:drawActionMenu()
        end

        -- S9.3: Prompt overlay (on top of everything)
        if self.promptOverlay then
            self:drawPromptOverlay()
        end
    end

    --- Draw the campfire prompt overlay (S9.3)
    function screen:drawPromptOverlay()
        if not self.promptOverlay then return end

        -- Darken background
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", 0, 0, self.width, self.height)

        -- Calculate prompt box dimensions
        local boxW = math.min(500, self.width - 60)
        local boxH = 200
        local boxX = (self.width - boxW) / 2
        local boxY = (self.height - boxH) / 2

        -- Draw speech bubble background (parchment-like)
        love.graphics.setColor(0.85, 0.80, 0.70, 1.0)
        love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 12, 12)

        -- Border
        love.graphics.setColor(0.50, 0.45, 0.35, 1.0)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 12, 12)
        love.graphics.setLineWidth(1)

        -- Header: "Campfire Discussion"
        love.graphics.setColor(0.30, 0.25, 0.20, 1.0)
        love.graphics.printf("CAMPFIRE DISCUSSION", boxX, boxY + 15, boxW, "center")

        -- Participants
        if self.promptOverlay.actor and self.promptOverlay.target then
            love.graphics.setColor(0.50, 0.45, 0.40, 1.0)
            local participants = self.promptOverlay.actor.name .. " & " .. self.promptOverlay.target.name
            love.graphics.printf(participants, boxX, boxY + 35, boxW, "center")
        end

        -- Separator line
        love.graphics.setColor(0.60, 0.55, 0.45, 0.5)
        love.graphics.line(boxX + 30, boxY + 55, boxX + boxW - 30, boxY + 55)

        -- The prompt text
        love.graphics.setColor(0.20, 0.15, 0.10, 1.0)
        love.graphics.printf(
            "\"" .. self.promptOverlay.text .. "\"",
            boxX + 20, boxY + 70,
            boxW - 40, "center"
        )

        -- Click to dismiss instruction
        love.graphics.setColor(0.50, 0.45, 0.40, 0.8)
        love.graphics.printf(
            "(Click anywhere to continue)",
            boxX, boxY + boxH - 30,
            boxW, "center"
        )

        -- Decorative fire icon
        local fireX = boxX + boxW / 2
        local fireY = boxY + boxH - 55
        self:drawMiniFlame(fireX, fireY)
    end

    --- Draw a small decorative flame icon
    function screen:drawMiniFlame(x, y)
        local size = 12

        -- Outer flame
        love.graphics.setColor(0.80, 0.40, 0.10, 0.8)
        love.graphics.polygon("fill",
            x, y - size,
            x - size * 0.6, y + size * 0.3,
            x + size * 0.6, y + size * 0.3
        )

        -- Inner flame
        love.graphics.setColor(1.0, 0.75, 0.30, 0.9)
        love.graphics.polygon("fill",
            x, y - size * 0.6,
            x - size * 0.3, y + size * 0.2,
            x + size * 0.3, y + size * 0.2
        )
    end

    --- Show fellowship prompt (S9.3)
    function screen:showFellowshipPrompt(actor, target)
        -- Use a seed based on game state for determinism
        local seed = os.time() + (actor.id and #actor.id or 0) + (target.id and #target.id or 0)
        local promptText = camp_prompts.getRandomPrompt(seed)

        self.promptOverlay = {
            text = promptText,
            actor = actor,
            target = target,
        }

        print("[CampScreen] Showing fellowship prompt: " .. promptText)
    end

    --- Dismiss the prompt overlay (S9.3)
    function screen:dismissPromptOverlay()
        self.promptOverlay = nil
    end

    function screen:drawStepBar()
        local barY = 0
        local barH = M.LAYOUT.STEP_BAR_HEIGHT

        -- Background
        love.graphics.setColor(self.colors.step_bar_bg)
        love.graphics.rectangle("fill", 0, barY, self.width, barH)

        -- Border
        love.graphics.setColor(self.colors.panel_border)
        love.graphics.line(0, barH, self.width, barH)

        -- Current step indicator
        local currentStep = self.campController and self.campController:getCurrentStep() or 0

        -- Draw step indicators
        local stepCount = 6  -- 0-5
        local stepWidth = (self.width - M.LAYOUT.PADDING * 2) / stepCount
        local stepY = barY + 10

        for i = 0, 5 do
            local stepX = M.LAYOUT.PADDING + i * stepWidth
            local stepName = M.STEP_NAMES[i] or "Step " .. i

            -- Determine color
            local bgColor, textColor
            if i == currentStep then
                bgColor = self.colors.step_active
                textColor = { 0.1, 0.1, 0.1, 1.0 }
            elseif i < currentStep then
                bgColor = self.colors.step_complete
                textColor = self.colors.step_text
            else
                bgColor = self.colors.step_pending
                textColor = { 0.6, 0.6, 0.6, 1.0 }
            end

            -- Step box
            love.graphics.setColor(bgColor)
            love.graphics.rectangle("fill", stepX + 2, stepY, stepWidth - 4, barH - 20, 4, 4)

            -- Step text
            love.graphics.setColor(textColor)
            love.graphics.printf(stepName, stepX + 2, stepY + 8, stepWidth - 4, "center")
        end
    end

    function screen:drawCampfire()
        local cx, cy = self.fireX, self.fireY
        local baseSize = M.LAYOUT.FIRE_SIZE / 2

        -- Flickering effect
        local flicker = math.sin(self.fireTimer * 8) * 0.1 +
                        math.sin(self.fireTimer * 12) * 0.05 +
                        math.cos(self.fireTimer * 5) * 0.08

        -- Outer flame (orange)
        love.graphics.setColor(self.colors.fire_outer)
        local outerSize = baseSize * (1 + flicker)
        self:drawFlameShape(cx, cy, outerSize)

        -- Inner flame (yellow)
        love.graphics.setColor(self.colors.fire_inner)
        local innerSize = baseSize * 0.6 * (1 + flicker * 0.5)
        self:drawFlameShape(cx, cy, innerSize)

        -- Core (white-yellow)
        love.graphics.setColor(1.0, 0.95, 0.8, 0.9)
        local coreSize = baseSize * 0.25
        love.graphics.circle("fill", cx, cy + baseSize * 0.2, coreSize)

        -- Embers (small particles)
        love.graphics.setColor(1.0, 0.6, 0.2, 0.7)
        for i = 1, 5 do
            local emberAngle = self.fireTimer * 2 + i * 1.2
            local emberDist = baseSize * 0.4 + math.sin(emberAngle * 3) * 10
            local emberX = cx + math.cos(emberAngle) * emberDist * 0.3
            local emberY = cy - math.sin(self.fireTimer * 3 + i) * emberDist * 0.5
            love.graphics.circle("fill", emberX, emberY, 2 + math.sin(emberAngle) * 1)
        end
    end

    function screen:drawFlameShape(cx, cy, size)
        -- Simple flame polygon
        local points = {}
        local segments = 8

        for i = 0, segments do
            local t = i / segments
            local angle = math.pi * (0.3 + t * 1.4) - math.pi / 2

            -- Flame shape: wider at bottom, pointed at top
            local r = size
            if t < 0.5 then
                r = r * (0.5 + t)
            else
                r = r * (1.5 - t)
            end

            -- Add some randomness
            r = r * (0.9 + math.sin(self.fireTimer * 6 + i) * 0.1)

            points[#points + 1] = cx + math.cos(angle) * r * 0.6
            points[#points + 1] = cy + math.sin(angle) * r
        end

        if #points >= 6 then
            love.graphics.polygon("fill", points)
        end
    end

    function screen:drawFireGlow()
        local cx, cy = self.fireX, self.fireY
        local glowSize = M.LAYOUT.FIRE_SIZE * 2

        -- Radial glow
        for i = 5, 1, -1 do
            local alpha = 0.03 * i
            love.graphics.setColor(self.colors.fire_glow[1], self.colors.fire_glow[2], self.colors.fire_glow[3], alpha)
            love.graphics.circle("fill", cx, cy, glowSize * (i / 5))
        end
    end

    function screen:drawCharacterPlates()
        local currentState = self.campController and self.campController:getState()

        for i, plate in ipairs(self.characterPlates) do
            -- Draw selection highlight for fellowship mode (S9.1)
            if self.fellowshipMode then
                self:drawFellowshipHighlight(plate, i)
            end

            plate:draw()

            -- Draw bonds for this plate (if in recovery phase OR actions phase to show existing bonds)
            if currentState == camp_controller.STATES.RECOVERY or
               currentState == camp_controller.STATES.ACTIONS then
                self:drawBondsForPlate(plate, i)
            end

            -- Draw pending action indicator
            local pc = self.guild[i]
            if pc then
                self:drawPCStatus(plate, pc, i)
            end
        end

        -- Draw fellowship connection line (S9.1)
        if self.fellowshipMode and self.fellowshipActorIndex then
            self:drawFellowshipLine()
        end
    end

    --- Draw fellowship selection highlight (S9.1)
    function screen:drawFellowshipHighlight(plate, index)
        local isActor = (index == self.fellowshipActorIndex)
        local isHovered = (index == self.hoveredPlateIndex)
        local pc = self.guild[index]

        -- Check if this PC can be selected as target
        local canSelect = true
        if self.fellowshipActor and pc then
            -- Can't select self
            if pc.id == self.fellowshipActor.id then
                canSelect = false
            end
            -- Check if bond already charged
            if self.fellowshipActor.bonds and self.fellowshipActor.bonds[pc.id] then
                if self.fellowshipActor.bonds[pc.id].charged then
                    canSelect = false  -- Bond already charged
                end
            end
        end

        -- Draw highlight
        if isActor then
            -- Selected actor - gold highlight
            love.graphics.setColor(0.85, 0.65, 0.25, 0.4)
            love.graphics.rectangle("fill", plate.x - 4, plate.y - 4,
                M.LAYOUT.PLATE_WIDTH + 8, plate:getHeight() + 8, 6, 6)
            love.graphics.setColor(0.85, 0.65, 0.25, 1.0)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", plate.x - 4, plate.y - 4,
                M.LAYOUT.PLATE_WIDTH + 8, plate:getHeight() + 8, 6, 6)
            love.graphics.setLineWidth(1)
        elseif isHovered and canSelect and not isActor then
            -- Valid target - purple hover
            love.graphics.setColor(0.70, 0.55, 0.85, 0.3)
            love.graphics.rectangle("fill", plate.x - 2, plate.y - 2,
                M.LAYOUT.PLATE_WIDTH + 4, plate:getHeight() + 4, 4, 4)
        elseif not canSelect and not isActor then
            -- Invalid target - red tint
            love.graphics.setColor(0.6, 0.3, 0.3, 0.2)
            love.graphics.rectangle("fill", plate.x, plate.y,
                M.LAYOUT.PLATE_WIDTH, plate:getHeight(), 4, 4)
        end
    end

    --- Draw connecting line during fellowship selection (S9.1)
    function screen:drawFellowshipLine()
        if not self.fellowshipActorIndex then return end

        local actorPlate = self.characterPlates[self.fellowshipActorIndex]
        if not actorPlate then return end

        -- Line start: center of actor plate
        local startX = actorPlate.x + M.LAYOUT.PLATE_WIDTH / 2
        local startY = actorPlate.y + actorPlate:getHeight() / 2

        -- Line end: either hovered plate center or mouse position
        local endX, endY
        if self.hoveredPlateIndex and self.hoveredPlateIndex ~= self.fellowshipActorIndex then
            local targetPlate = self.characterPlates[self.hoveredPlateIndex]
            if targetPlate then
                endX = targetPlate.x + M.LAYOUT.PLATE_WIDTH / 2
                endY = targetPlate.y + targetPlate:getHeight() / 2
            end
        end

        if not endX and love then
            endX, endY = love.mouse.getPosition()
        end

        if endX and endY then
            -- Draw glowing line
            love.graphics.setColor(0.70, 0.55, 0.85, 0.3)
            love.graphics.setLineWidth(6)
            love.graphics.line(startX, startY, endX, endY)

            love.graphics.setColor(0.70, 0.55, 0.85, 0.8)
            love.graphics.setLineWidth(2)
            love.graphics.line(startX, startY, endX, endY)

            love.graphics.setLineWidth(1)
        end
    end

    function screen:drawPCStatus(plate, pc, index)
        local currentState = self.campController and self.campController:getState()

        -- Show status based on current phase
        if currentState == camp_controller.STATES.ACTIONS then
            -- Show if action taken
            local actionTaken = self.campController.actionsCompleted[pc.id]
            local statusColor = actionTaken and self.colors.step_complete or self.colors.warning

            love.graphics.setColor(statusColor)
            local statusText = actionTaken and "Done" or "Needs Action"
            love.graphics.print(statusText, plate.x, plate.y - 15)

        elseif currentState == camp_controller.STATES.BREAK_BREAD then
            -- Show if ate
            local ate = self.campController.rationsConsumed[pc.id]
            local statusColor = ate and self.colors.step_complete or self.colors.warning

            love.graphics.setColor(statusColor)
            local statusText = ate and "Fed" or "Hungry"
            love.graphics.print(statusText, plate.x, plate.y - 15)

            -- S9.2: Show warning if no rations in inventory
            if not ate then
                local rationCount = self:countRationsFor(pc)
                if rationCount == 0 then
                    -- Draw warning icon (exclamation triangle)
                    self:drawNoRationWarning(plate.x + M.LAYOUT.PLATE_WIDTH - 25, plate.y + 5)
                else
                    -- Show ration count
                    love.graphics.setColor(self.colors.step_text)
                    love.graphics.print("x" .. rationCount, plate.x + M.LAYOUT.PLATE_WIDTH - 25, plate.y + 5)
                end
            end

        elseif currentState == camp_controller.STATES.RECOVERY then
            -- S9.2: Show stress gate warning
            if pc.conditions and pc.conditions.stressed then
                love.graphics.setColor(self.colors.warning)
                love.graphics.print("STRESSED - Must clear first!", plate.x, plate.y - 15)
            end
        end
    end

    --- Count rations in a PC's inventory (S9.2)
    function screen:countRationsFor(pc)
        if not pc.inventory or not pc.inventory.countItemsByPredicate then
            return 0
        end

        return pc.inventory:countItemsByPredicate(function(item)
            return item.isRation or
                   item.type == "ration" or
                   item.itemType == "ration" or
                   (item.properties and item.properties.isRation) or
                   (item.name and item.name:lower():find("ration"))
        end)
    end

    --- Draw no-ration warning icon (S9.2)
    function screen:drawNoRationWarning(x, y)
        -- Triangle with exclamation
        local size = 18

        -- Warning triangle background
        love.graphics.setColor(self.colors.warning)
        love.graphics.polygon("fill",
            x + size/2, y,
            x, y + size,
            x + size, y + size
        )

        -- Exclamation mark
        love.graphics.setColor(0.1, 0.1, 0.1, 1.0)
        love.graphics.rectangle("fill", x + size/2 - 1.5, y + 5, 3, 7)
        love.graphics.circle("fill", x + size/2, y + size - 4, 2)
    end

    function screen:drawBondsForPlate(plate, pcIndex)
        local pc = self.guild[pcIndex]
        if not pc or not pc.bonds then return end

        -- Draw bond indicators as small circles on the plate
        local bondX = plate.x + M.LAYOUT.PLATE_WIDTH - 30
        local bondY = plate.y + 5
        local bondSize = 12
        local bondSpacing = bondSize + 4

        local bondIndex = 0
        for targetId, bond in pairs(pc.bonds) do
            local bx = bondX
            local by = bondY + bondIndex * bondSpacing

            -- Bond circle
            local bondColor = bond.charged and self.colors.bond_charged or self.colors.bond_spent
            love.graphics.setColor(bondColor)
            love.graphics.circle("fill", bx, by, bondSize / 2)

            -- Border
            love.graphics.setColor(self.colors.panel_border)
            love.graphics.circle("line", bx, by, bondSize / 2)

            -- Hover highlight
            if self.hoveredBond and self.hoveredBond.pcIndex == pcIndex and self.hoveredBond.targetId == targetId then
                love.graphics.setColor(1, 1, 1, 0.3)
                love.graphics.circle("fill", bx, by, bondSize / 2 + 3)
            end

            bondIndex = bondIndex + 1
        end
    end

    function screen:drawActionPanel()
        local panelY = self.height - M.LAYOUT.ACTION_PANEL_HEIGHT
        local panelH = M.LAYOUT.ACTION_PANEL_HEIGHT

        -- Background
        love.graphics.setColor(self.colors.panel_bg)
        love.graphics.rectangle("fill", 0, panelY, self.width, panelH)

        -- Border
        love.graphics.setColor(self.colors.panel_border)
        love.graphics.line(0, panelY, self.width, panelY)

        -- Content based on current state
        local currentState = self.campController and self.campController:getState() or camp_controller.STATES.INACTIVE

        if currentState == camp_controller.STATES.ACTIONS then
            self:drawActionsPanel(panelY)
        elseif currentState == camp_controller.STATES.BREAK_BREAD then
            self:drawBreakBreadPanel(panelY)
        elseif currentState == camp_controller.STATES.WATCH then
            self:drawWatchPanel(panelY)
        elseif currentState == camp_controller.STATES.RECOVERY then
            self:drawRecoveryPanel(panelY)
        else
            self:drawGenericPanel(panelY, currentState)
        end

        -- Advance button (if applicable)
        if currentState ~= camp_controller.STATES.INACTIVE and currentState ~= camp_controller.STATES.TEARDOWN then
            self:drawAdvanceButton(panelY)
        end
    end

    function screen:drawActionsPanel(panelY)
        -- Different instructions for fellowship mode (S9.1)
        if self.fellowshipMode then
            love.graphics.setColor(self.colors.bond_charged)
            if self.fellowshipActor then
                love.graphics.print("FELLOWSHIP - Click another character to share a moment with " ..
                    self.fellowshipActor.name .. " (ESC to cancel)", M.LAYOUT.PADDING, panelY + 10)
            else
                love.graphics.print("FELLOWSHIP - Click a character to select them", M.LAYOUT.PADDING, panelY + 10)
            end

            love.graphics.setColor(self.colors.step_text)
            love.graphics.print("Both characters will charge their bond with each other.", M.LAYOUT.PADDING, panelY + 30)
            return
        end

        love.graphics.setColor(self.colors.step_text)
        love.graphics.print("CAMP ACTIONS - Click a character to assign their action", M.LAYOUT.PADDING, panelY + 10)

        -- Show pending characters
        local pending = self.campController:getPendingAdventurers()
        local pendingText = "Waiting: "
        for i, pc in ipairs(pending) do
            if i > 1 then pendingText = pendingText .. ", " end
            pendingText = pendingText .. pc.name
        end
        love.graphics.setColor(self.colors.warning)
        love.graphics.print(pendingText, M.LAYOUT.PADDING, panelY + 30)
    end

    function screen:drawBreakBreadPanel(panelY)
        love.graphics.setColor(self.colors.step_text)
        love.graphics.print("BREAK BREAD - Click characters to consume rations or go hungry", M.LAYOUT.PADDING, panelY + 10)

        local pending = self.campController:getPendingAdventurers()
        local pendingText = "Need to eat: "
        for i, pc in ipairs(pending) do
            if i > 1 then pendingText = pendingText .. ", " end
            pendingText = pendingText .. pc.name
        end
        love.graphics.setColor(self.colors.warning)
        love.graphics.print(pendingText, M.LAYOUT.PADDING, panelY + 30)
    end

    function screen:drawWatchPanel(panelY)
        love.graphics.setColor(self.colors.step_text)
        love.graphics.print("THE WATCH - Click to draw from the Meatgrinder", M.LAYOUT.PADDING, panelY + 10)

        if self.campController.patrolActive then
            love.graphics.setColor(self.colors.step_active)
            love.graphics.print("Patrol active - drawing twice!", M.LAYOUT.PADDING, panelY + 30)
        end
    end

    function screen:drawRecoveryPanel(panelY)
        love.graphics.setColor(self.colors.step_text)
        love.graphics.print("RECOVERY - Click charged bonds to heal wounds, regain resolve, or clear stress", M.LAYOUT.PADDING, panelY + 10)
        love.graphics.print("Stressed characters must clear stress first!", M.LAYOUT.PADDING, panelY + 30)
    end

    function screen:drawGenericPanel(panelY, state)
        love.graphics.setColor(self.colors.step_text)
        love.graphics.print("Camp Phase: " .. (state or "Unknown"), M.LAYOUT.PADDING, panelY + 10)
    end

    function screen:drawAdvanceButton(panelY)
        local btnW, btnH = 120, 35
        local btnX = self.width - btnW - M.LAYOUT.PADDING
        local btnY = panelY + M.LAYOUT.ACTION_PANEL_HEIGHT / 2 - btnH / 2

        -- S9.3: Cannot advance while prompt overlay is showing
        local isBlocked = self.promptOverlay ~= nil
        local isHover = self.hoverButton == "advance" and not isBlocked

        local btnColor
        if isBlocked then
            btnColor = { 0.25, 0.25, 0.25, 0.5 }  -- Greyed out
        elseif isHover then
            btnColor = self.colors.button_hover
        else
            btnColor = self.colors.button_bg
        end

        love.graphics.setColor(btnColor)
        love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 4, 4)

        love.graphics.setColor(self.colors.panel_border)
        love.graphics.rectangle("line", btnX, btnY, btnW, btnH, 4, 4)

        local textColor = isBlocked and { 0.5, 0.5, 0.5, 0.7 } or self.colors.button_text
        love.graphics.setColor(textColor)
        love.graphics.printf("Next Step", btnX, btnY + 10, btnW, "center")

        -- Store button bounds for click detection (nil if blocked)
        self.advanceButtonBounds = isBlocked and nil or { x = btnX, y = btnY, w = btnW, h = btnH }
    end

    function screen:drawActionMenu()
        local menuX = self.actionMenuX
        local menuY = self.actionMenuY
        local menuW = 200
        local itemH = 30
        local menuH = #self.actionMenuItems * itemH + 10

        -- Keep menu on screen
        if menuX + menuW > self.width then
            menuX = self.width - menuW - 10
        end
        if menuY + menuH > self.height - M.LAYOUT.ACTION_PANEL_HEIGHT then
            menuY = self.height - M.LAYOUT.ACTION_PANEL_HEIGHT - menuH - 10
        end

        -- Background
        love.graphics.setColor(self.colors.panel_bg)
        love.graphics.rectangle("fill", menuX, menuY, menuW, menuH, 4, 4)

        -- Border
        love.graphics.setColor(self.colors.panel_border)
        love.graphics.rectangle("line", menuX, menuY, menuW, menuH, 4, 4)

        -- Items
        for i, item in ipairs(self.actionMenuItems) do
            local itemY = menuY + 5 + (i - 1) * itemH
            local isHover = self.hoverButton == "action_" .. i

            if isHover then
                love.graphics.setColor(self.colors.button_hover)
                love.graphics.rectangle("fill", menuX + 2, itemY, menuW - 4, itemH - 2, 2, 2)
            end

            love.graphics.setColor(self.colors.button_text)
            love.graphics.print(item.name, menuX + 10, itemY + 6)
        end

        -- Store bounds
        self.actionMenuBounds = { x = menuX, y = menuY, w = menuW, h = menuH, itemH = itemH }
    end

    ----------------------------------------------------------------------------
    -- INPUT HANDLING
    ----------------------------------------------------------------------------

    function screen:mousepressed(x, y, button)
        if button ~= 1 then return end

        local currentState = self.campController and self.campController:getState()

        -- S9.3: Check prompt overlay click (dismisses it)
        if self.promptOverlay then
            self:dismissPromptOverlay()
            return
        end

        -- S9.1: Handle fellowship mode clicks
        if self.fellowshipMode then
            self:handleFellowshipClick(x, y)
            return
        end

        -- Check action menu click
        if self.actionMenuOpen then
            if self:handleActionMenuClick(x, y) then
                return
            else
                self.actionMenuOpen = false
            end
        end

        -- Check advance button
        if self.advanceButtonBounds then
            local btn = self.advanceButtonBounds
            if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
                self:handleAdvanceClick()
                return
            end
        end

        -- Check character plate clicks
        for i, plate in ipairs(self.characterPlates) do
            if x >= plate.x and x <= plate.x + M.LAYOUT.PLATE_WIDTH and
               y >= plate.y and y <= plate.y + plate:getHeight() then

                if currentState == camp_controller.STATES.ACTIONS then
                    self:openActionMenuFor(i, x, y)
                elseif currentState == camp_controller.STATES.BREAK_BREAD then
                    self:handleBreakBreadClick(i)
                elseif currentState == camp_controller.STATES.RECOVERY then
                    self:handleRecoveryClick(i, x, y)
                end
                return
            end
        end
    end

    function screen:mousereleased(x, y, button)
        -- Nothing special for now
    end

    function screen:mousemoved(x, y, dx, dy)
        self.hoverButton = nil
        self.hoveredBond = nil
        self.hoveredPlateIndex = nil

        -- Check which plate is hovered (for fellowship mode)
        for i, plate in ipairs(self.characterPlates) do
            if x >= plate.x and x <= plate.x + M.LAYOUT.PLATE_WIDTH and
               y >= plate.y and y <= plate.y + plate:getHeight() then
                self.hoveredPlateIndex = i
                break
            end
        end

        -- Check advance button hover
        if self.advanceButtonBounds then
            local btn = self.advanceButtonBounds
            if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
                self.hoverButton = "advance"
            end
        end

        -- Check action menu hover
        if self.actionMenuOpen and self.actionMenuBounds then
            local menu = self.actionMenuBounds
            if x >= menu.x and x <= menu.x + menu.w and y >= menu.y and y <= menu.y + menu.h then
                local itemIndex = math.floor((y - menu.y - 5) / menu.itemH) + 1
                if itemIndex >= 1 and itemIndex <= #self.actionMenuItems then
                    self.hoverButton = "action_" .. itemIndex
                end
            end
        end

        -- Check bond hover (during recovery)
        local currentState = self.campController and self.campController:getState()
        if currentState == camp_controller.STATES.RECOVERY then
            for i, plate in ipairs(self.characterPlates) do
                local pc = self.guild[i]
                if pc and pc.bonds then
                    local bondX = plate.x + M.LAYOUT.PLATE_WIDTH - 30
                    local bondY = plate.y + 5
                    local bondSize = 12
                    local bondSpacing = bondSize + 4

                    local bondIndex = 0
                    for targetId, bond in pairs(pc.bonds) do
                        local bx = bondX
                        local by = bondY + bondIndex * bondSpacing
                        local dist = math.sqrt((x - bx)^2 + (y - by)^2)
                        if dist < bondSize then
                            self.hoveredBond = { pcIndex = i, targetId = targetId, bond = bond }
                        end
                        bondIndex = bondIndex + 1
                    end
                end
            end
        end
    end

    function screen:keypressed(key)
        if key == "escape" then
            -- Cancel fellowship mode first, then action menu
            if self.fellowshipMode then
                self:cancelFellowshipMode()
            elseif self.actionMenuOpen then
                self.actionMenuOpen = false
            end
        end
    end

    --- Cancel fellowship selection mode (S9.1)
    function screen:cancelFellowshipMode()
        self.fellowshipMode = false
        self.fellowshipActor = nil
        self.fellowshipActorIndex = nil
        print("[CampScreen] Fellowship cancelled")
    end

    ----------------------------------------------------------------------------
    -- ACTION HANDLERS
    ----------------------------------------------------------------------------

    function screen:openActionMenuFor(pcIndex, x, y)
        local pc = self.guild[pcIndex]
        if not pc then return end

        -- Check if already submitted action
        if self.campController.actionsCompleted[pc.id] then
            return
        end

        self.selectedPC = pc
        self.actionMenuX = x
        self.actionMenuY = y

        -- Get available actions
        self.actionMenuItems = camp_actions.getAvailableActions(pc, self.guild)
        self.actionMenuOpen = true
    end

    function screen:handleActionMenuClick(x, y)
        if not self.actionMenuBounds then return false end

        local menu = self.actionMenuBounds
        if x < menu.x or x > menu.x + menu.w or y < menu.y or y > menu.y + menu.h then
            return false
        end

        local itemIndex = math.floor((y - menu.y - 5) / menu.itemH) + 1
        if itemIndex >= 1 and itemIndex <= #self.actionMenuItems then
            local action = self.actionMenuItems[itemIndex]
            self:submitCampAction(self.selectedPC, action)
            self.actionMenuOpen = false
            return true
        end

        return false
    end

    function screen:submitCampAction(pc, actionDef)
        if not pc or not actionDef then return end

        -- S9.1: Fellowship requires two-character selection mode
        if actionDef.id == "fellowship" then
            self:enterFellowshipMode(pc)
            return
        end

        -- Build action data
        local actionData = {
            type = actionDef.id,
        }

        -- Handle target selection for actions that need it
        if actionDef.requiresTarget then
            if actionDef.targetType == "pc" then
                -- For other PC-targeting actions, pick first other PC (simplified)
                for _, other in ipairs(self.guild) do
                    if other.id ~= pc.id then
                        actionData.target = other
                        break
                    end
                end
            end
            -- Other target types would need more UI (item picker, etc.)
        end

        -- Submit to controller
        local success, result = self.campController:submitAction(pc, actionData)
        if success then
            print("[CampScreen] Action submitted: " .. actionDef.name)
        else
            print("[CampScreen] Action failed: " .. (result or "unknown"))
        end
    end

    --- Enter fellowship selection mode (S9.1)
    function screen:enterFellowshipMode(actorPC)
        -- Find actor's index
        local actorIndex = nil
        for i, pc in ipairs(self.guild) do
            if pc.id == actorPC.id then
                actorIndex = i
                break
            end
        end

        self.fellowshipMode = true
        self.fellowshipActor = actorPC
        self.fellowshipActorIndex = actorIndex
        self.actionMenuOpen = false

        print("[CampScreen] Entering fellowship mode for " .. actorPC.name)
    end

    --- Handle clicks during fellowship mode (S9.1)
    function screen:handleFellowshipClick(x, y)
        -- Check if clicking on a character plate
        for i, plate in ipairs(self.characterPlates) do
            if x >= plate.x and x <= plate.x + M.LAYOUT.PLATE_WIDTH and
               y >= plate.y and y <= plate.y + plate:getHeight() then

                local targetPC = self.guild[i]
                if not targetPC then return end

                -- Clicking self cancels selection
                if self.fellowshipActor and targetPC.id == self.fellowshipActor.id then
                    self:cancelFellowshipMode()
                    return
                end

                -- Check if bond already charged
                if self.fellowshipActor and self.fellowshipActor.bonds and
                   self.fellowshipActor.bonds[targetPC.id] and
                   self.fellowshipActor.bonds[targetPC.id].charged then
                    print("[CampScreen] Bond with " .. targetPC.name .. " is already charged!")
                    return
                end

                -- Submit fellowship action with target
                local actionData = {
                    type = "fellowship",
                    target = targetPC,
                }

                local success, result = self.campController:submitAction(self.fellowshipActor, actionData)
                if success then
                    print("[CampScreen] Fellowship completed: " .. self.fellowshipActor.name ..
                          " and " .. targetPC.name)
                else
                    print("[CampScreen] Fellowship failed: " .. (result or "unknown"))
                end

                -- Exit fellowship mode
                self:cancelFellowshipMode()
                return
            end
        end

        -- Clicking elsewhere cancels
        self:cancelFellowshipMode()
    end

    function screen:handleBreakBreadClick(pcIndex)
        local pc = self.guild[pcIndex]
        if not pc then return end

        -- Check if already resolved
        if self.campController.rationsConsumed[pc.id] then
            return
        end

        -- Try to consume ration
        local success, result = self.campController:consumeRation(pc)
        print("[CampScreen] Break bread for " .. pc.name .. ": " .. (result or "?"))
    end

    function screen:handleRecoveryClick(pcIndex, x, y)
        local pc = self.guild[pcIndex]
        if not pc then return end

        -- Check if clicked on a bond
        if self.hoveredBond and self.hoveredBond.pcIndex == pcIndex then
            local bond = self.hoveredBond.bond
            local targetId = self.hoveredBond.targetId

            if bond.charged then
                -- Determine spend type based on conditions
                local spendType = "heal_wound"
                if pc.conditions and pc.conditions.stressed then
                    spendType = "clear_stress"
                end

                local success, result = self.campController:spendBondForRecovery(pc, targetId, spendType)
                print("[CampScreen] Bond spent: " .. (result or "failed"))
            else
                print("[CampScreen] Bond is not charged")
            end
        end
    end

    function screen:handleAdvanceClick()
        if not self.campController then return end

        local success, err = self.campController:advanceStep()
        if success then
            print("[CampScreen] Advanced to next step")
        else
            print("[CampScreen] Cannot advance: " .. (err or "unknown"))
        end
    end

    return screen
end

return M

```

---

## File: src/ui/screens/character_sheet.lua

```lua
-- character_sheet.lua
-- Character Sheet Modal for Majesty
-- Ticket S11.1: Full stats, talents, and inventory view
--
-- Layout:
-- +----------+------------------+----------+
-- |  LEFT    |     CENTER       |  RIGHT   |
-- |  Stats   |    Inventory     | Talents  |
-- +----------+------------------+----------+

local events = require('logic.events')
local inventory = require('logic.inventory')

local M = {}

--------------------------------------------------------------------------------
-- LAYOUT CONSTANTS
--------------------------------------------------------------------------------

M.LAYOUT = {
    PADDING = 15,
    HEADER_HEIGHT = 60,
    LEFT_WIDTH = 200,
    RIGHT_WIDTH = 200,
    SLOT_SIZE = 42,
    SLOT_SPACING = 4,
}

--------------------------------------------------------------------------------
-- COLORS
--------------------------------------------------------------------------------

M.COLORS = {
    overlay = { 0, 0, 0, 0.85 },
    panel_bg = { 0.12, 0.12, 0.15, 0.98 },
    panel_border = { 0.4, 0.35, 0.3, 1 },
    header_bg = { 0.18, 0.15, 0.12, 1 },
    text = { 0.9, 0.88, 0.82, 1 },
    text_dim = { 0.6, 0.58, 0.55, 1 },
    text_highlight = { 1, 0.9, 0.6, 1 },
    slot_empty = { 0.15, 0.15, 0.18, 1 },
    slot_filled = { 0.25, 0.22, 0.2, 1 },
    slot_hover = { 0.35, 0.32, 0.28, 1 },
    condition_bad = { 0.9, 0.3, 0.25, 1 },
    condition_neutral = { 0.7, 0.65, 0.5, 1 },
    talent_mastered = { 0.4, 0.7, 0.4, 1 },
    talent_training = { 0.7, 0.6, 0.3, 1 },
    talent_wounded = { 0.7, 0.3, 0.3, 1 },
}

--------------------------------------------------------------------------------
-- CHARACTER SHEET FACTORY
--------------------------------------------------------------------------------

function M.createCharacterSheet(config)
    config = config or {}

    local sheet = {
        eventBus = config.eventBus or events.globalBus,
        guild = config.guild or {},

        -- State
        isOpen = false,
        selectedPC = nil,
        selectedPCIndex = 1,

        -- Layout (calculated on open)
        x = 0,
        y = 0,
        width = 0,
        height = 0,

        -- Hover state
        hoveredSlot = nil,
        hoveredSlotLocation = nil,
        hoveredTalent = nil,

        -- Tooltip
        tooltip = nil,

        -- Drag state (for S11.2)
        dragging = nil,
        dragOffsetX = 0,
        dragOffsetY = 0,
        dragSourceLocation = nil,
        dragSourceIndex = nil,

        -- S11.2: Slot bounds for drop detection
        slotBounds = {},  -- { location_index = { x, y, w, h, location, index } }
    }

    ----------------------------------------------------------------------------
    -- OPEN/CLOSE
    ----------------------------------------------------------------------------

    function sheet:open(pcIndex)
        self.isOpen = true
        self.selectedPCIndex = pcIndex or self.selectedPCIndex
        if self.selectedPCIndex > #self.guild then
            self.selectedPCIndex = 1
        end
        self.selectedPC = self.guild[self.selectedPCIndex]
        self:calculateLayout()
        self.eventBus:emit("character_sheet_opened", { pc = self.selectedPC })
    end

    function sheet:close()
        self.isOpen = false
        self.selectedPC = nil
        self.hoveredSlot = nil
        self.hoveredTalent = nil
        self.tooltip = nil
        self.dragging = nil
        self.eventBus:emit("character_sheet_closed", {})
    end

    function sheet:toggle(pcIndex)
        if self.isOpen then
            self:close()
        else
            self:open(pcIndex)
        end
    end

    ----------------------------------------------------------------------------
    -- LAYOUT
    ----------------------------------------------------------------------------

    function sheet:calculateLayout()
        if not love then return end

        local screenW, screenH = love.graphics.getDimensions()
        local padding = 40

        self.width = screenW - padding * 2
        self.height = screenH - padding * 2
        self.x = padding
        self.y = padding

        -- Calculate column widths
        self.leftColumnX = self.x + M.LAYOUT.PADDING
        self.leftColumnW = M.LAYOUT.LEFT_WIDTH

        self.rightColumnX = self.x + self.width - M.LAYOUT.RIGHT_WIDTH - M.LAYOUT.PADDING
        self.rightColumnW = M.LAYOUT.RIGHT_WIDTH

        self.centerColumnX = self.leftColumnX + self.leftColumnW + M.LAYOUT.PADDING
        self.centerColumnW = self.rightColumnX - self.centerColumnX - M.LAYOUT.PADDING
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function sheet:update(dt)
        if not self.isOpen then return end
        -- Animation updates could go here
    end

    ----------------------------------------------------------------------------
    -- DRAW
    ----------------------------------------------------------------------------

    function sheet:draw()
        if not self.isOpen or not love then return end
        if not self.selectedPC then return end

        local pc = self.selectedPC

        -- Dark overlay
        love.graphics.setColor(M.COLORS.overlay)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())

        -- Main panel
        love.graphics.setColor(M.COLORS.panel_bg)
        love.graphics.rectangle("fill", self.x, self.y, self.width, self.height, 8, 8)

        love.graphics.setColor(M.COLORS.panel_border)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", self.x, self.y, self.width, self.height, 8, 8)
        love.graphics.setLineWidth(1)

        -- Header
        self:drawHeader(pc)

        -- Three columns
        local contentY = self.y + M.LAYOUT.HEADER_HEIGHT + M.LAYOUT.PADDING

        self:drawLeftColumn(pc, contentY)
        self:drawCenterColumn(pc, contentY)
        self:drawRightColumn(pc, contentY)

        -- Tooltip (on top)
        self:drawTooltip()

        -- Draw dragged item (on very top)
        self:drawDraggedItem()

        -- Instructions
        love.graphics.setColor(M.COLORS.text_dim)
        love.graphics.print("Tab: Close | 1-4: Switch Character", self.x + 10, self.y + self.height - 25)
    end

    function sheet:drawHeader(pc)
        local headerY = self.y
        local headerH = M.LAYOUT.HEADER_HEIGHT

        -- Header background
        love.graphics.setColor(M.COLORS.header_bg)
        love.graphics.rectangle("fill", self.x, headerY, self.width, headerH, 8, 0)

        -- Character name
        love.graphics.setColor(M.COLORS.text_highlight)
        love.graphics.print(pc.name or "Unknown", self.x + M.LAYOUT.PADDING, headerY + 10)

        -- Motifs
        love.graphics.setColor(M.COLORS.text_dim)
        local motifText = table.concat(pc.motifs or {}, " | ")
        love.graphics.print(motifText, self.x + M.LAYOUT.PADDING, headerY + 32)

        -- Gold and XP (right side)
        local rightX = self.x + self.width - M.LAYOUT.PADDING - 150
        love.graphics.setColor(M.COLORS.text)
        love.graphics.print("Gold: " .. (pc.gold or 0), rightX, headerY + 10)
        love.graphics.print("XP: " .. (pc.xp or 0), rightX, headerY + 32)

        -- PC selector tabs
        local tabX = self.x + 200
        for i, guildPC in ipairs(self.guild) do
            local isSelected = (i == self.selectedPCIndex)
            local tabW = 80
            local tx = tabX + (i - 1) * (tabW + 5)

            if isSelected then
                love.graphics.setColor(0.3, 0.25, 0.2, 1)
            else
                love.graphics.setColor(0.15, 0.13, 0.12, 1)
            end
            love.graphics.rectangle("fill", tx, headerY + 5, tabW, 25, 4, 4)

            love.graphics.setColor(isSelected and M.COLORS.text_highlight or M.COLORS.text_dim)
            love.graphics.print(guildPC.name, tx + 5, headerY + 10)
        end
    end

    function sheet:drawLeftColumn(pc, startY)
        local x = self.leftColumnX
        local y = startY
        local w = self.leftColumnW

        -- Section: Attributes
        love.graphics.setColor(M.COLORS.text_highlight)
        love.graphics.print("ATTRIBUTES", x, y)
        y = y + 25

        local attributes = {
            { name = "Swords", value = pc.swords or 0, color = {0.8, 0.3, 0.3} },
            { name = "Pentacles", value = pc.pentacles or 0, color = {0.3, 0.7, 0.3} },
            { name = "Cups", value = pc.cups or 0, color = {0.3, 0.5, 0.9} },
            { name = "Wands", value = pc.wands or 0, color = {0.8, 0.6, 0.2} },
        }

        for _, attr in ipairs(attributes) do
            love.graphics.setColor(attr.color)
            love.graphics.print(attr.name .. ":", x, y)
            love.graphics.setColor(M.COLORS.text)
            love.graphics.print(tostring(attr.value), x + 90, y)
            y = y + 22
        end

        y = y + 15

        -- Section: Resolve
        love.graphics.setColor(M.COLORS.text_highlight)
        love.graphics.print("RESOLVE", x, y)
        y = y + 25

        local resolve = pc.resolve or { current = 4, max = 4 }
        love.graphics.setColor(M.COLORS.text)
        love.graphics.print(resolve.current .. " / " .. resolve.max, x, y)

        -- Draw resolve pips
        local pipX = x + 60
        for i = 1, resolve.max do
            if i <= resolve.current then
                love.graphics.setColor(0.3, 0.7, 0.9, 1)
                love.graphics.circle("fill", pipX + (i - 1) * 18, y + 8, 6)
            else
                love.graphics.setColor(0.3, 0.3, 0.3, 1)
                love.graphics.circle("line", pipX + (i - 1) * 18, y + 8, 6)
            end
        end
        y = y + 30

        -- Section: Conditions
        love.graphics.setColor(M.COLORS.text_highlight)
        love.graphics.print("CONDITIONS", x, y)
        y = y + 25

        local conditions = pc.conditions or {}
        local conditionList = { "staggered", "injured", "deaths_door", "stressed", "rooted" }
        local hasCondition = false

        for _, cond in ipairs(conditionList) do
            if conditions[cond] then
                hasCondition = true
                love.graphics.setColor(M.COLORS.condition_bad)
                love.graphics.print("* " .. cond:gsub("_", " "):upper(), x, y)
                y = y + 20
            end
        end

        if not hasCondition then
            love.graphics.setColor(M.COLORS.text_dim)
            love.graphics.print("None", x, y)
        end

        y = y + 25

        -- Section: Armor
        love.graphics.setColor(M.COLORS.text_highlight)
        love.graphics.print("ARMOR", x, y)
        y = y + 25

        local armorSlots = pc.armorSlots or 0
        local armorNotches = pc.armorNotches or 0
        love.graphics.setColor(M.COLORS.text)
        love.graphics.print("Notches: " .. armorNotches .. " / " .. armorSlots, x, y)
    end

    function sheet:drawCenterColumn(pc, startY)
        local x = self.centerColumnX
        local y = startY
        local slotSize = M.LAYOUT.SLOT_SIZE
        local spacing = M.LAYOUT.SLOT_SPACING

        -- S11.2: Clear slot bounds at start of draw
        self.slotBounds = {}

        -- Section: Hands (2 slots)
        love.graphics.setColor(M.COLORS.text_highlight)
        love.graphics.print("HANDS", x, y)
        y = y + 25

        local hands = pc.inventory and pc.inventory:getItems("hands") or {}
        for i = 1, 2 do
            local item = hands[i]
            self:drawInventorySlot(x + (i - 1) * (slotSize + spacing), y, slotSize, item, "hands", i)
        end
        y = y + slotSize + 20

        -- Section: Belt (4 slots)
        love.graphics.setColor(M.COLORS.text_highlight)
        love.graphics.print("BELT", x, y)
        y = y + 25

        local belt = pc.inventory and pc.inventory:getItems("belt") or {}
        for i = 1, 4 do
            local item = belt[i]
            self:drawInventorySlot(x + (i - 1) * (slotSize + spacing), y, slotSize, item, "belt", i)
        end
        y = y + slotSize + 20

        -- Section: Pack (21 slots in grid)
        love.graphics.setColor(M.COLORS.text_highlight)
        love.graphics.print("PACK", x, y)
        y = y + 25

        local pack = pc.inventory and pc.inventory:getItems("pack") or {}
        local cols = 7
        for i = 1, 21 do
            local row = math.floor((i - 1) / cols)
            local col = (i - 1) % cols
            local item = pack[i]
            local slotX = x + col * (slotSize + spacing)
            local slotY = y + row * (slotSize + spacing)
            self:drawInventorySlot(slotX, slotY, slotSize, item, "pack", i)
        end
    end

    function sheet:drawInventorySlot(x, y, size, item, location, index)
        local isHovered = (self.hoveredSlot == index and self.hoveredSlotLocation == location)
        local isDragSource = (self.dragging and self.dragSourceLocation == location and self.dragSourceIndex == index)

        -- S11.2: Store slot bounds for drop detection (always, not just for filled slots)
        local boundsKey = location .. "_" .. index
        self.slotBounds[boundsKey] = { x = x, y = y, w = size, h = size, location = location, index = index }

        -- S11.2: Check if this is a valid drop target
        local isValidDropTarget = false
        local isInvalidDropTarget = false
        if self.dragging and not isDragSource then
            isValidDropTarget = self:canDropAt(location, index)
            isInvalidDropTarget = not isValidDropTarget
        end

        -- Slot background
        if isDragSource then
            -- Dim the source slot while dragging
            love.graphics.setColor(0.1, 0.1, 0.12, 0.5)
        elseif isValidDropTarget then
            -- Highlight valid drop targets
            love.graphics.setColor(0.2, 0.4, 0.3, 0.9)
        elseif isInvalidDropTarget then
            -- Show invalid drop targets
            love.graphics.setColor(0.3, 0.15, 0.15, 0.9)
        elseif item then
            love.graphics.setColor(isHovered and M.COLORS.slot_hover or M.COLORS.slot_filled)
        else
            love.graphics.setColor(M.COLORS.slot_empty)
        end
        love.graphics.rectangle("fill", x, y, size, size, 4, 4)

        -- Slot border
        if isValidDropTarget then
            love.graphics.setColor(0.3, 0.8, 0.4, 1)
            love.graphics.setLineWidth(2)
        elseif isInvalidDropTarget then
            love.graphics.setColor(0.8, 0.3, 0.3, 1)
            love.graphics.setLineWidth(2)
        elseif isHovered and item then
            love.graphics.setColor(M.COLORS.text_highlight)
            love.graphics.setLineWidth(2)
        else
            love.graphics.setColor(0.4, 0.4, 0.4, 0.6)
            love.graphics.setLineWidth(1)
        end
        love.graphics.rectangle("line", x, y, size, size, 4, 4)
        love.graphics.setLineWidth(1)

        -- Item display (skip if this is the drag source)
        if item and not isDragSource then
            -- Item icon (first letter)
            love.graphics.setColor(M.COLORS.text)
            local initial = string.sub(item.name or "?", 1, 2)
            love.graphics.print(initial, x + 4, y + 4)

            -- Quantity for stackables
            if item.stackable and item.quantity and item.quantity > 1 then
                love.graphics.setColor(M.COLORS.text_dim)
                love.graphics.print("x" .. item.quantity, x + size - 20, y + size - 14)
            end

            -- Durability indicator (notches)
            if item.notches and item.notches > 0 then
                love.graphics.setColor(M.COLORS.condition_bad)
                for n = 1, item.notches do
                    love.graphics.rectangle("fill", x + size - 6, y + 4 + (n - 1) * 6, 4, 4)
                end
            end
        end

        -- Store slot bounds on item too for backward compatibility
        if item then
            item._slotBounds = self.slotBounds[boundsKey]
        end
    end

    --- S11.2: Check if dragged item can be dropped at location
    function sheet:canDropAt(location, index)
        if not self.dragging then return false end

        local item = self.dragging

        -- Oversized items can only go on belt
        if item.oversized and location ~= "belt" then
            return false
        end

        -- Armor can only go on belt
        if item.isArmor and location ~= "belt" then
            return false
        end

        -- Check if slot has room
        if not self.selectedPC or not self.selectedPC.inventory then
            return false
        end

        -- For now, allow dropping anywhere with available slots
        -- The inventory:swap() method will handle actual validation
        return true
    end

    function sheet:drawRightColumn(pc, startY)
        local x = self.rightColumnX
        local y = startY
        local w = self.rightColumnW

        -- Section: Talents
        love.graphics.setColor(M.COLORS.text_highlight)
        love.graphics.print("TALENTS", x, y)
        y = y + 25

        local talents = pc.talents or {}
        local hasTalents = false

        for talentId, talentData in pairs(talents) do
            hasTalents = true
            local isHovered = (self.hoveredTalent == talentId)

            -- Background for hover
            if isHovered then
                love.graphics.setColor(0.25, 0.22, 0.2, 1)
                love.graphics.rectangle("fill", x - 5, y - 2, w + 10, 22, 3, 3)
            end

            -- Talent name with status color
            if talentData.wounded then
                love.graphics.setColor(M.COLORS.talent_wounded)
            elseif talentData.mastered then
                love.graphics.setColor(M.COLORS.talent_mastered)
            else
                love.graphics.setColor(M.COLORS.talent_training)
            end

            local displayName = talentId:gsub("_", " "):gsub("^%l", string.upper)
            local status = talentData.mastered and "[M]" or "[T]"
            if talentData.wounded then status = "[W]" end

            love.graphics.print(status .. " " .. displayName, x, y)
            y = y + 24
        end

        if not hasTalents then
            love.graphics.setColor(M.COLORS.text_dim)
            love.graphics.print("None", x, y)
        end

        y = y + 25

        -- Section: Bonds
        love.graphics.setColor(M.COLORS.text_highlight)
        love.graphics.print("BONDS", x, y)
        y = y + 25

        local bonds = pc.bonds or {}
        local hasBonds = false

        for entityId, bondData in pairs(bonds) do
            hasBonds = true
            local bondedPC = nil
            for _, gpc in ipairs(self.guild) do
                if gpc.id == entityId then
                    bondedPC = gpc
                    break
                end
            end

            local name = bondedPC and bondedPC.name or entityId
            local status = bondData.status:gsub("_", " ")
            local charged = bondData.charged and "*" or ""

            love.graphics.setColor(bondData.charged and M.COLORS.talent_mastered or M.COLORS.text_dim)
            love.graphics.print(charged .. name .. ": " .. status, x, y)
            y = y + 20
        end

        if not hasBonds then
            love.graphics.setColor(M.COLORS.text_dim)
            love.graphics.print("None", x, y)
        end
    end

    function sheet:drawTooltip()
        if not self.tooltip then return end

        local mouseX, mouseY = love.mouse.getPosition()
        local padding = 8
        local maxWidth = 250

        -- Measure text
        local font = love.graphics.getFont()
        local textWidth = math.min(font:getWidth(self.tooltip.text), maxWidth)
        local textHeight = font:getHeight() * math.ceil(font:getWidth(self.tooltip.text) / maxWidth)

        local tipX = mouseX + 15
        local tipY = mouseY + 10
        local tipW = textWidth + padding * 2
        local tipH = textHeight + padding * 2

        -- Keep on screen
        local screenW, screenH = love.graphics.getDimensions()
        if tipX + tipW > screenW then tipX = mouseX - tipW - 5 end
        if tipY + tipH > screenH then tipY = mouseY - tipH - 5 end

        -- Background
        love.graphics.setColor(0.1, 0.1, 0.12, 0.95)
        love.graphics.rectangle("fill", tipX, tipY, tipW, tipH, 4, 4)

        love.graphics.setColor(0.4, 0.35, 0.3, 1)
        love.graphics.rectangle("line", tipX, tipY, tipW, tipH, 4, 4)

        -- Text
        love.graphics.setColor(M.COLORS.text)
        love.graphics.printf(self.tooltip.text, tipX + padding, tipY + padding, maxWidth)
    end

    function sheet:drawDraggedItem()
        if not self.dragging then return end

        local mouseX, mouseY = love.mouse.getPosition()
        local size = M.LAYOUT.SLOT_SIZE

        love.graphics.setColor(0.4, 0.35, 0.3, 0.9)
        love.graphics.rectangle("fill", mouseX - size/2, mouseY - size/2, size, size, 4, 4)

        love.graphics.setColor(M.COLORS.text)
        local initial = string.sub(self.dragging.name or "?", 1, 2)
        love.graphics.print(initial, mouseX - size/2 + 4, mouseY - size/2 + 4)
    end

    ----------------------------------------------------------------------------
    -- INPUT
    ----------------------------------------------------------------------------

    function sheet:keypressed(key)
        if not self.isOpen then
            -- Tab opens sheet
            if key == "tab" then
                self:open(1)
                return true
            end
            return false
        end

        -- Tab closes sheet
        if key == "tab" or key == "escape" then
            self:close()
            return true
        end

        -- Number keys switch character
        local keyNum = tonumber(key)
        if keyNum and keyNum >= 1 and keyNum <= #self.guild then
            self.selectedPCIndex = keyNum
            self.selectedPC = self.guild[keyNum]
            return true
        end

        return true  -- Consume all input when open
    end

    function sheet:mousepressed(x, y, button)
        if not self.isOpen then return false end

        -- Check if clicking outside panel to close
        if x < self.x or x > self.x + self.width or
           y < self.y or y > self.y + self.height then
            self:close()
            return true
        end

        -- Check PC tabs in header
        local tabX = self.x + 200
        local tabY = self.y + 5
        for i = 1, #self.guild do
            local tx = tabX + (i - 1) * 85
            if x >= tx and x < tx + 80 and y >= tabY and y < tabY + 25 then
                self.selectedPCIndex = i
                self.selectedPC = self.guild[i]
                return true
            end
        end

        -- Check inventory slots for drag start (S11.2)
        if button == 1 and self.hoveredSlot and self.hoveredSlotLocation then
            local items = self.selectedPC.inventory:getItems(self.hoveredSlotLocation)
            local item = items[self.hoveredSlot]
            if item then
                self.dragging = item
                self.dragSourceLocation = self.hoveredSlotLocation
                self.dragSourceIndex = self.hoveredSlot
                return true
            end
        end

        return true  -- Consume all clicks when open
    end

    function sheet:mousereleased(x, y, button)
        if not self.isOpen then return false end

        -- Handle drag drop (S11.2)
        if self.dragging and button == 1 then
            self:handleDrop(x, y)
            self.dragging = nil
            self.dragSourceLocation = nil
            self.dragSourceIndex = nil
            return true
        end

        return true
    end

    function sheet:mousemoved(x, y, dx, dy)
        if not self.isOpen then return false end

        self.hoveredSlot = nil
        self.hoveredSlotLocation = nil
        self.hoveredTalent = nil
        self.tooltip = nil

        if not self.selectedPC then return true end

        -- S11.2: Check inventory slot hover using slotBounds (works for empty slots too)
        for boundsKey, bounds in pairs(self.slotBounds) do
            if x >= bounds.x and x < bounds.x + bounds.w and
               y >= bounds.y and y < bounds.y + bounds.h then
                self.hoveredSlot = bounds.index
                self.hoveredSlotLocation = bounds.location

                -- Get item at this slot
                local items = self.selectedPC.inventory and self.selectedPC.inventory:getItems(bounds.location) or {}
                local item = items[bounds.index]

                if item then
                    -- Build tooltip
                    local tipLines = { item.name }
                    if item.properties then
                        if item.properties.light_source then
                            table.insert(tipLines, "Light source (" .. (item.properties.flicker_count or 0) .. " flickers)")
                        end
                    end
                    if item.durability then
                        table.insert(tipLines, "Durability: " .. (item.durability - (item.notches or 0)) .. "/" .. item.durability)
                    end
                    if item.size and item.size > 1 then
                        table.insert(tipLines, "Size: " .. item.size .. " slots")
                    end
                    if item.oversized then
                        table.insert(tipLines, "Oversized (Belt only)")
                    end

                    self.tooltip = { text = table.concat(tipLines, "\n") }
                end
                return true
            end
        end

        -- Check talent hover
        local talents = self.selectedPC.talents or {}
        local ty = self.y + M.LAYOUT.HEADER_HEIGHT + M.LAYOUT.PADDING + 25
        for talentId, talentData in pairs(talents) do
            if x >= self.rightColumnX and x < self.rightColumnX + self.rightColumnW and
               y >= ty and y < ty + 22 then
                self.hoveredTalent = talentId

                -- Build talent tooltip
                local status = talentData.mastered and "Mastered" or "In Training"
                if talentData.wounded then status = "Wounded" end
                self.tooltip = { text = talentId:gsub("_", " "):upper() .. "\n" .. status }
                return true
            end
            ty = ty + 24
        end

        return true
    end

    ----------------------------------------------------------------------------
    -- DRAG & DROP (S11.2)
    ----------------------------------------------------------------------------

    function sheet:handleDrop(x, y)
        if not self.dragging or not self.selectedPC then return end

        -- Find target slot using slotBounds
        local targetLoc = nil
        local targetIndex = nil

        for boundsKey, bounds in pairs(self.slotBounds) do
            if x >= bounds.x and x < bounds.x + bounds.w and
               y >= bounds.y and y < bounds.y + bounds.h then
                targetLoc = bounds.location
                targetIndex = bounds.index
                break
            end
        end

        -- Check if valid drop
        if not targetLoc then
            print("[INVENTORY] Dropped outside slots - cancelled")
            return
        end

        -- Same slot - no action
        if targetLoc == self.dragSourceLocation and targetIndex == self.dragSourceIndex then
            return
        end

        -- Check if we can drop here
        if not self:canDropAt(targetLoc, targetIndex) then
            print("[INVENTORY] Invalid drop location: " .. targetLoc)
            return
        end

        -- Perform the move
        local success, reason = self.selectedPC.inventory:swap(self.dragging.id, targetLoc)
        if success then
            print("[INVENTORY] Moved " .. self.dragging.name .. " to " .. targetLoc)
            self.eventBus:emit("inventory_changed", {
                entity = self.selectedPC,
                item = self.dragging,
                from = self.dragSourceLocation,
                to = targetLoc,
            })
        else
            print("[INVENTORY] Move failed: " .. (reason or "unknown"))
            -- Visual feedback for failure could be added here
        end
    end

    --- Get the slot at a given position
    function sheet:getSlotAt(x, y)
        for boundsKey, bounds in pairs(self.slotBounds) do
            if x >= bounds.x and x < bounds.x + bounds.w and
               y >= bounds.y and y < bounds.y + bounds.h then
                return bounds.location, bounds.index
            end
        end
        return nil, nil
    end

    return sheet
end

return M

```

---

## File: src/ui/screens/crawl_screen.lua

```lua
-- crawl_screen.lua
-- The Crawl Screen Controller for Majesty
-- Ticket T3_1: Main game screen with three-column layout
--
-- Layout:
-- +----------+------------------+----------+
-- |  LEFT    |     CENTER       |  RIGHT   |
-- |  RAIL    |     VELLUM       |  RAIL    |
-- | (Guild)  | (NarrativeView)  | (Dread)  |
-- +----------+------------------+----------+
--
-- Ties together: NarrativeView, FocusMenu, InputManager

local events = require('logic.events')
local input_manager = require('ui.input_manager')
local narrative_view = require('ui.narrative_view')
local focus_menu = require('ui.focus_menu')
local character_plate = require('ui.character_plate')
local belt_hotbar = require('ui.belt_hotbar')

local M = {}

--------------------------------------------------------------------------------
-- LAYOUT CONSTANTS
--------------------------------------------------------------------------------
M.LAYOUT = {
    LEFT_RAIL_WIDTH  = 200,
    RIGHT_RAIL_WIDTH = 200,
    PADDING          = 10,
    HEADER_HEIGHT    = 40,
}

--------------------------------------------------------------------------------
-- COLORS
--------------------------------------------------------------------------------
M.COLORS = {
    background    = { 0.08, 0.08, 0.1, 1.0 },
    rail_bg       = { 0.12, 0.12, 0.14, 0.95 },
    rail_border   = { 0.25, 0.25, 0.3, 1.0 },
    vellum_bg     = { 0.85, 0.8, 0.7, 1.0 },  -- Parchment color
    text_dark     = { 0.15, 0.12, 0.1, 1.0 },  -- Dark text on vellum
    header_text   = { 0.9, 0.85, 0.75, 1.0 },
    dread_card_bg = { 0.15, 0.1, 0.12, 1.0 },
}

--------------------------------------------------------------------------------
-- CRAWL SCREEN FACTORY
--------------------------------------------------------------------------------

--- Create a new CrawlScreen
-- @param config table: { eventBus, roomManager, watchManager, gameState }
-- @return CrawlScreen instance
function M.createCrawlScreen(config)
    config = config or {}

    local screen = {
        -- Core systems
        eventBus     = config.eventBus or events.globalBus,
        roomManager  = config.roomManager,
        watchManager = config.watchManager,
        gameState    = config.gameState,

        -- UI Components (created in init)
        inputManager  = nil,
        narrativeView = nil,
        focusMenu     = nil,
        beltHotbar    = nil,  -- S10.3: Belt item quick access

        -- Layout dimensions (calculated on resize)
        width  = 800,
        height = 600,
        leftRailX     = 0,
        leftRailWidth = M.LAYOUT.LEFT_RAIL_WIDTH,
        centerX       = 0,
        centerWidth   = 0,
        rightRailX    = 0,
        rightRailWidth = M.LAYOUT.RIGHT_RAIL_WIDTH,

        -- Current state
        currentRoomId = nil,
        guild         = {},       -- Array of adventurer entities
        characterPlates = {},     -- S5.1: Extended character plate components
        dreadCard     = nil,      -- Currently displayed Major Arcana
        exitHitboxes  = {},       -- Room exit clickable areas

        -- Textures (loaded in init)
        vellumTexture = nil,

        -- Colors
        colors = config.colors or M.COLORS,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    --- Initialize the screen (call once after creation)
    function screen:init()
        -- Create input manager
        self.inputManager = input_manager.createInputManager({
            eventBus = self.eventBus,
            roomManager = self.roomManager,
        })

        -- Create narrative view (positioned in calculateLayout)
        self.narrativeView = narrative_view.createNarrativeView({
            eventBus = self.eventBus,
            inputManager = self.inputManager,
            typewriterEnabled = true,
            typewriterSpeed = 40,
            colors = {
                text       = self.colors.text_dark,
                poi        = { 0.1, 0.4, 0.6, 1.0 },  -- Dark blue-ish for POIs on parchment
                poi_hover  = { 0.0, 0.3, 0.5, 1.0 },
                background = { 0, 0, 0, 0 },  -- Transparent (vellum provides bg)
            },
        })

        -- Create focus menu
        self.focusMenu = focus_menu.createFocusMenu({
            eventBus = self.eventBus,
            inputManager = self.inputManager,
            roomManager = self.roomManager,
        })

        -- S10.3: Create belt hotbar (positioned in calculateLayout)
        self.beltHotbar = belt_hotbar.createBeltHotbar({
            eventBus = self.eventBus,
            guild = self.guild,
        })
        self.beltHotbar:init()

        -- Subscribe to events
        self:subscribeEvents()

        -- Initial layout calculation
        if love then
            self:resize(love.graphics.getDimensions())
        end

        -- Try to load vellum texture
        self:loadTextures()
    end

    --- Load texture assets
    function screen:loadTextures()
        if not love then return end

        -- Try to load parchment texture (graceful fallback to solid color)
        local success, result = pcall(function()
            return love.graphics.newImage("assets/textures/vellum.png")
        end)

        if success then
            self.vellumTexture = result
        end
    end

    --- Subscribe to relevant events
    function screen:subscribeEvents()
        -- POI clicked -> check if exit or feature
        self.eventBus:on(events.EVENTS.POI_CLICKED, function(data)
            -- Check if this is an exit POI
            if data.poiId and data.poiId:sub(1, 5) == "exit_" then
                -- Extract target room ID from "exit_<roomId>"
                local targetRoomId = data.poiId:sub(6)
                self:handleExitClick(targetRoomId)
                return
            end

            -- Otherwise, it's a feature POI -> open focus menu
            if self.focusMenu and self.roomManager then
                local feature = self.roomManager:getFeature(self.currentRoomId, data.poiId)
                if feature then
                    self.focusMenu:open(data.poiId, feature, self.currentRoomId, data.x, data.y)
                end
            end
        end)

        -- Drop on target -> trigger investigation or movement
        self.eventBus:on(events.EVENTS.DROP_ON_TARGET, function(data)
            self:handleDrop(data)
        end)

        -- Meatgrinder roll -> update dread card
        self.eventBus:on(events.EVENTS.MEATGRINDER_ROLL, function(data)
            self.dreadCard = data.card
        end)

        -- Watch passed -> could update UI
        self.eventBus:on(events.EVENTS.WATCH_PASSED, function(data)
            -- Refresh room description or show event
        end)

        -- Room entered -> update display
        self.eventBus:on(events.EVENTS.ROOM_ENTERED, function(data)
            self:enterRoom(data.roomId)
        end)

        -- Scrutiny selected -> show result in narrative
        self.eventBus:on(events.EVENTS.SCRUTINY_SELECTED, function(data)
            self:handleScrutinyResult(data)
        end)
    end

    --- Handle scrutiny result and display it
    function screen:handleScrutinyResult(data)
        -- S11.3: Check if this is a "search" on a container with loot
        if data.verb == "search" then
            local feature = self.roomManager:getFeature(data.roomId, data.poiId)
            if feature and feature.loot and #feature.loot > 0 then
                -- Open the loot modal instead of showing narrative
                if self.gameState and self.gameState.lootModal then
                    self.gameState.lootModal:open(feature, data.roomId)
                    return
                end
            end
        end

        if not data.result then return end

        local resultText = data.result.text or "You find nothing of note."

        -- Append to narrative (or could show in a popup)
        print("[Scrutiny] " .. data.verb .. " on " .. data.poiId .. ": " .. resultText)

        -- For now, re-enter the room to refresh, then append the result
        -- A better approach would be to have a separate "discovery" panel
        if self.narrativeView then
            local currentText = self.narrativeView.rawText or ""
            local newText = currentText .. "\n\n--- " .. data.verb:upper() .. " ---\n" .. resultText
            self.narrativeView:setText(newText, true)
        end
    end

    --- Handle clicking on an exit to move the party
    function screen:handleExitClick(targetRoomId)
        if not self.watchManager then
            print("[handleExitClick] No watchManager!")
            return
        end

        print("[handleExitClick] Moving party to: " .. targetRoomId)

        local success, result = self.watchManager:moveParty(targetRoomId)

        if success then
            print("[handleExitClick] Move successful! Watch: " .. result.watchResult.watchNumber)
            -- Room change is handled by ROOM_ENTERED event
        else
            print("[handleExitClick] Move failed: " .. (result.error or "unknown"))

            -- S11.3: Handle locked door - check if party has matching key
            if result.error == "connection_locked" then
                local connection = self.watchManager.dungeon:getConnection(self.currentRoomId, targetRoomId)

                -- Check if any party member has the matching key
                local foundKey, foundPC = self:findMatchingKey(connection.key_id)

                if foundKey then
                    -- Auto-unlock with the found key
                    connection.is_locked = false

                    -- Show success message
                    if self.narrativeView then
                        local currentText = self.narrativeView.rawText or ""
                        local newText = currentText .. "\n\n--- UNLOCKED ---\n" ..
                            foundPC.name .. " uses the " .. (foundKey.name or "key") ..
                            " to unlock the passage. It swings open with a creak."
                        self.narrativeView:setText(newText, true)
                    end

                    print("[KEY] Door unlocked with " .. (foundKey.name or "key") .. " by " .. foundPC.name)

                    -- Emit unlock event
                    self.eventBus:emit("door_unlocked", {
                        from = self.currentRoomId,
                        to = targetRoomId,
                        keyItem = foundKey,
                        unlocker = foundPC,
                    })

                    -- Refresh room display and then auto-move
                    self:enterRoom(self.currentRoomId)

                    -- Now try to move through the unlocked door
                    local moveSuccess, moveResult = self.watchManager:moveParty(targetRoomId)
                    if moveSuccess then
                        print("[handleExitClick] Move successful after unlock!")
                    end
                else
                    -- No matching key - show locked message
                    local msg = "The passage is locked."
                    if connection and connection.description then
                        msg = connection.description
                    end

                    if self.narrativeView then
                        local currentText = self.narrativeView.rawText or ""
                        local newText = currentText .. "\n\n--- LOCKED ---\n" .. msg .. "\n(Find the right key to unlock this passage)"
                        self.narrativeView:setText(newText, true)
                    end
                end
            end
        end
    end

    ----------------------------------------------------------------------------
    -- LAYOUT
    ----------------------------------------------------------------------------

    --- Calculate layout based on screen size
    function screen:calculateLayout()
        local padding = M.LAYOUT.PADDING

        -- Left rail
        self.leftRailX = 0
        self.leftRailWidth = M.LAYOUT.LEFT_RAIL_WIDTH

        -- Right rail
        self.rightRailWidth = M.LAYOUT.RIGHT_RAIL_WIDTH
        self.rightRailX = self.width - self.rightRailWidth

        -- Center (vellum) area
        self.centerX = self.leftRailWidth + padding
        self.centerWidth = self.width - self.leftRailWidth - self.rightRailWidth - (padding * 2)

        -- Update narrative view position
        if self.narrativeView then
            self.narrativeView:setPosition(
                self.centerX + padding,
                M.LAYOUT.HEADER_HEIGHT + padding
            )
            self.narrativeView:resize(
                self.centerWidth - (padding * 2),
                self.height - M.LAYOUT.HEADER_HEIGHT - (padding * 2)
            )
        end

        -- S10.3: Position belt hotbar at bottom left
        if self.beltHotbar then
            self.beltHotbar.x = self.leftRailWidth + padding
            self.beltHotbar.y = self.height - 70
        end
    end

    --- Handle window resize
    function screen:resize(w, h)
        self.width = w
        self.height = h
        self:calculateLayout()
    end

    ----------------------------------------------------------------------------
    -- ROOM MANAGEMENT
    ----------------------------------------------------------------------------

    --- Enter a new room
    function screen:enterRoom(roomId)
        self.currentRoomId = roomId

        -- Clear old hitboxes
        self.inputManager:clearHitboxes()
        self.exitHitboxes = {}

        -- Get room data
        local room = self.roomManager and self.roomManager:getRoom(roomId)
        if not room then
            self.narrativeView:setText("You are nowhere.", true)
            return
        end

        -- Debug: Print room data
        print("[enterRoom] Room: " .. (room.name or "?"))
        print("[enterRoom] base_description: " .. tostring(room.base_description))
        print("[enterRoom] description: " .. tostring(room.description))
        print("[enterRoom] features count: " .. (room.features and #room.features or 0))
        if room.features then
            for i, f in ipairs(room.features) do
                print("  Feature " .. i .. ": " .. (f.name or f.id or "?"))
            end
        end

        -- Build rich text description
        local description = self:buildRoomDescription(room)
        print("[enterRoom] Built description: " .. description)
        self.narrativeView:setText(description)

        -- Register exit hitboxes (based on connections)
        self:registerExitHitboxes(room)
    end

    --- Build rich text description for a room
    function screen:buildRoomDescription(room)
        local parts = {}

        -- Room name as header
        parts[#parts + 1] = room.name .. "\n\n"

        -- Base description
        parts[#parts + 1] = room.base_description or room.description or ""

        -- Features as POIs
        if room.features then
            for _, feature in ipairs(room.features) do
                if feature.state ~= "destroyed" and feature.state ~= "hidden" then
                    -- Format as rich text POI
                    parts[#parts + 1] = " "
                    parts[#parts + 1] = "{poi:" .. feature.id .. ":" .. feature.name .. "}"
                end
            end
        end

        -- Exits from dungeon connections (as clickable POIs)
        parts[#parts + 1] = "\n\nExits: "

        if self.watchManager and self.watchManager.dungeon then
            local adjacent = self.watchManager.dungeon:getAdjacentRooms(room.id)
            local first = true

            for _, adj in ipairs(adjacent) do
                local conn = adj.connection
                local targetRoom = adj.room

                -- Build exit display text
                local directionText = ""
                if conn.direction then
                    directionText = conn.direction:sub(1,1):upper() .. conn.direction:sub(2)
                else
                    directionText = "Passage"
                end

                local displayText = directionText .. " to " .. targetRoom.name
                if conn.is_locked then
                    displayText = displayText .. " (locked)"
                end

                -- Add separator
                if not first then
                    parts[#parts + 1] = ", "
                end
                first = false

                -- Format as POI with exit_ prefix for identification
                -- Store target room ID in the POI id
                local exitId = "exit_" .. targetRoom.id
                parts[#parts + 1] = "{poi:" .. exitId .. ":" .. displayText .. "}"
            end

            if first then
                parts[#parts + 1] = "None"
            end
        else
            parts[#parts + 1] = "None"
        end

        return table.concat(parts)
    end

    --- Register exit areas as hitboxes
    function screen:registerExitHitboxes(room)
        -- Exits would be rendered as clickable text at the bottom
        -- For now, this is a placeholder
        -- In full implementation, each connection would get a hitbox
    end

    ----------------------------------------------------------------------------
    -- GUILD MANAGEMENT
    ----------------------------------------------------------------------------

    --- Set the guild (party of adventurers)
    function screen:setGuild(adventurers)
        self.guild = adventurers or {}
        self:createCharacterPlates()
        self:registerGuildHitboxes()

        -- S10.3: Update belt hotbar guild reference
        if self.beltHotbar then
            self.beltHotbar.guild = self.guild
        end
    end

    --- Create character plate components for each guild member (S5.1)
    function screen:createCharacterPlates()
        self.characterPlates = {}

        local y = M.LAYOUT.HEADER_HEIGHT + M.LAYOUT.PADDING
        local plateWidth = self.leftRailWidth - (M.LAYOUT.PADDING * 2)

        for i, adventurer in ipairs(self.guild) do
            local plate = character_plate.createCharacterPlate({
                eventBus = self.eventBus,
                entity = adventurer,
                x = self.leftRailX + M.LAYOUT.PADDING,
                y = y,
                width = plateWidth,
            })
            plate:init()

            self.characterPlates[#self.characterPlates + 1] = plate

            -- Advance y by plate height
            y = y + plate:getHeight() + M.LAYOUT.PADDING
        end
    end

    --- Register guild member portraits as draggable
    function screen:registerGuildHitboxes()
        local y = M.LAYOUT.HEADER_HEIGHT + M.LAYOUT.PADDING
        local portraitSize = 60
        local padding = 10

        for i, adventurer in ipairs(self.guild) do
            local hitboxId = "adventurer_" .. (adventurer.id or i)
            self.inputManager:registerHitbox(
                hitboxId,
                "adventurer",
                self.leftRailX + padding,
                y,
                portraitSize,
                portraitSize,
                adventurer
            )
            y = y + portraitSize + padding
        end
    end

    ----------------------------------------------------------------------------
    -- INPUT HANDLING
    ----------------------------------------------------------------------------

    --- Handle drop events
    function screen:handleDrop(data)
        if data.action == "investigate" and data.target then
            -- Dragged adventurer onto POI
            print("Investigating " .. (data.target.id or "unknown") ..
                  " with " .. (data.source.name or "adventurer"))

            -- Would call roomManager:conductInvestigation here
        elseif data.action == "use_item" and data.target then
            -- Dragged item onto POI
            print("Using item on " .. (data.target.id or "unknown"))

            -- S11.3: Check if using a key on a locked exit
            if data.targetId and data.targetId:sub(1, 5) == "exit_" then
                local targetRoomId = data.targetId:sub(6)
                self:handleKeyOnLockedExit(data.source, targetRoomId)
            end
        end
    end

    --- S11.3: Handle using a key on a locked exit
    function screen:handleKeyOnLockedExit(item, targetRoomId)
        if not item or not self.watchManager then return end

        -- Check if item is a key
        local isKey = item.keyId or (item.properties and item.properties.key)
        if not isKey then
            -- Show message that item can't be used on door
            if self.narrativeView then
                local currentText = self.narrativeView.rawText or ""
                local newText = currentText .. "\n\n" .. (item.name or "This item") .. " cannot be used on the door."
                self.narrativeView:setText(newText, true)
            end
            return
        end

        -- Get the connection to check if it's locked and if key matches
        local connection = self.watchManager.dungeon:getConnection(self.currentRoomId, targetRoomId)
        if not connection then
            print("[KEY] No connection to " .. targetRoomId)
            return
        end

        if not connection.is_locked then
            -- Door is already unlocked
            if self.narrativeView then
                local currentText = self.narrativeView.rawText or ""
                local newText = currentText .. "\n\nThe passage is already open."
                self.narrativeView:setText(newText, true)
            end
            return
        end

        -- Check if key matches the lock
        local keyId = item.keyId or (item.properties and item.properties.keyId)
        if keyId ~= connection.key_id then
            -- Wrong key
            if self.narrativeView then
                local currentText = self.narrativeView.rawText or ""
                local newText = currentText .. "\n\nThe " .. (item.name or "key") .. " doesn't fit this lock."
                self.narrativeView:setText(newText, true)
            end
            return
        end

        -- Key matches! Unlock the door
        connection.is_locked = false

        -- Show success message
        if self.narrativeView then
            local currentText = self.narrativeView.rawText or ""
            local newText = currentText .. "\n\n--- UNLOCKED ---\nYou use the " .. (item.name or "key") .. " to unlock the passage. It swings open with a creak."
            self.narrativeView:setText(newText, true)
        end

        print("[KEY] Door unlocked with " .. (item.name or "key"))

        -- Emit unlock event
        self.eventBus:emit("door_unlocked", {
            from = self.currentRoomId,
            to = targetRoomId,
            keyItem = item,
        })

        -- Refresh room display to update the exit text
        self:enterRoom(self.currentRoomId)
    end

    --- S11.3: Find a matching key in any party member's inventory
    -- @param requiredKeyId string: The key_id required by the lock
    -- @return item, pc or nil, nil
    function screen:findMatchingKey(requiredKeyId)
        if not requiredKeyId then return nil, nil end

        for _, pc in ipairs(self.guild) do
            if pc.inventory then
                -- Check all items in all locations
                local allItems = pc.inventory:getAllItems()
                for _, entry in ipairs(allItems) do
                    local item = entry.item
                    -- Check if item is a key with matching keyId
                    local itemKeyId = item.keyId or (item.properties and item.properties.keyId)
                    if itemKeyId == requiredKeyId then
                        return item, pc
                    end
                end
            end
        end

        return nil, nil
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    --- Update the screen
    function screen:update(dt)
        -- Update narrative view (typewriter effect)
        if self.narrativeView then
            self.narrativeView:update(dt)
        end

        -- Update focus menu
        if self.focusMenu then
            self.focusMenu:update(dt)
        end

        -- S5.1: Update character plates (for wound flow animation)
        for _, plate in ipairs(self.characterPlates) do
            plate:update(dt)
        end

        -- S10.3: Update belt hotbar
        if self.beltHotbar then
            self.beltHotbar:update(dt)
        end
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    ----------------------------------------------------------------------------

    --- Draw the screen
    function screen:draw()
        if not love then return end

        -- Background
        love.graphics.setColor(self.colors.background)
        love.graphics.rectangle("fill", 0, 0, self.width, self.height)

        -- Draw three columns
        self:drawLeftRail()
        self:drawCenter()
        self:drawRightRail()

        -- Draw narrative view
        if self.narrativeView then
            self.narrativeView:draw()
        end

        -- Draw focus menu (on top)
        if self.focusMenu then
            self.focusMenu:draw()
        end

        -- S10.3: Draw belt hotbar
        if self.beltHotbar then
            self.beltHotbar:draw()
        end

        -- Draw drag ghost (on very top)
        self:drawDragGhost()
    end

    --- Draw the left rail (Guild)
    function screen:drawLeftRail()
        -- Background
        love.graphics.setColor(self.colors.rail_bg)
        love.graphics.rectangle("fill", self.leftRailX, 0, self.leftRailWidth, self.height)

        -- Border
        love.graphics.setColor(self.colors.rail_border)
        love.graphics.rectangle("line", self.leftRailX, 0, self.leftRailWidth, self.height)

        -- Header
        love.graphics.setColor(self.colors.header_text)
        love.graphics.printf("GUILD", self.leftRailX, 10, self.leftRailWidth, "center")

        -- S5.1: Draw character plates for each guild member
        for _, plate in ipairs(self.characterPlates) do
            plate:draw()
        end
    end

    --- Draw the center area (Vellum)
    function screen:drawCenter()
        -- Vellum background
        if self.vellumTexture then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(
                self.vellumTexture,
                self.centerX,
                0,
                0,
                self.centerWidth / self.vellumTexture:getWidth(),
                self.height / self.vellumTexture:getHeight()
            )
        else
            -- Fallback: solid parchment color
            love.graphics.setColor(self.colors.vellum_bg)
            love.graphics.rectangle("fill", self.centerX, 0, self.centerWidth, self.height)
        end

        -- Header
        love.graphics.setColor(self.colors.text_dark)
        love.graphics.printf("THE UNDERWORLD", self.centerX, 10, self.centerWidth, "center")
    end

    --- Draw the right rail (Map / Dread)
    function screen:drawRightRail()
        -- Background
        love.graphics.setColor(self.colors.rail_bg)
        love.graphics.rectangle("fill", self.rightRailX, 0, self.rightRailWidth, self.height)

        -- Border
        love.graphics.setColor(self.colors.rail_border)
        love.graphics.rectangle("line", self.rightRailX, 0, self.rightRailWidth, self.height)

        -- Header
        love.graphics.setColor(self.colors.header_text)
        love.graphics.printf("DREAD", self.rightRailX, 10, self.rightRailWidth, "center")

        -- Dread card display
        if self.dreadCard then
            local cardX = self.rightRailX + 20
            local cardY = M.LAYOUT.HEADER_HEIGHT + 20
            local cardW = self.rightRailWidth - 40
            local cardH = cardW * 1.4  -- Tarot proportions

            -- Card background
            love.graphics.setColor(self.colors.dread_card_bg)
            love.graphics.rectangle("fill", cardX, cardY, cardW, cardH, 4, 4)

            -- Card border
            love.graphics.setColor(0.6, 0.5, 0.3, 1.0)
            love.graphics.rectangle("line", cardX, cardY, cardW, cardH, 4, 4)

            -- Card name
            love.graphics.setColor(self.colors.header_text)
            love.graphics.printf(
                self.dreadCard.name or "???",
                cardX + 5,
                cardY + cardH/2 - 10,
                cardW - 10,
                "center"
            )

            -- Card value
            love.graphics.printf(
                tostring(self.dreadCard.value or ""),
                cardX + 5,
                cardY + cardH/2 + 10,
                cardW - 10,
                "center"
            )
        else
            -- No card drawn yet
            love.graphics.setColor(0.4, 0.4, 0.4, 1.0)
            love.graphics.printf(
                "No card drawn",
                self.rightRailX + 10,
                M.LAYOUT.HEADER_HEIGHT + 40,
                self.rightRailWidth - 20,
                "center"
            )
        end

        -- Watch indicator (below card)
        local watchY = M.LAYOUT.HEADER_HEIGHT + 200
        love.graphics.setColor(self.colors.header_text)
        love.graphics.printf("WATCH", self.rightRailX, watchY, self.rightRailWidth, "center")

        -- Would show watch count, torch pips, etc.

        -- S11.4: Camp button at bottom of right rail
        local campBtnW = self.rightRailWidth - 20
        local campBtnH = 40
        local campBtnX = self.rightRailX + 10
        local campBtnY = self.height - campBtnH - 60

        -- Store button bounds for click detection
        self.campButtonBounds = { x = campBtnX, y = campBtnY, w = campBtnW, h = campBtnH }

        -- Check if hovering
        local mouseX, mouseY = love.mouse.getPosition()
        local isHovered = mouseX >= campBtnX and mouseX < campBtnX + campBtnW and
                          mouseY >= campBtnY and mouseY < campBtnY + campBtnH

        -- Button background
        if isHovered then
            love.graphics.setColor(0.35, 0.3, 0.25, 1)
        else
            love.graphics.setColor(0.25, 0.22, 0.18, 1)
        end
        love.graphics.rectangle("fill", campBtnX, campBtnY, campBtnW, campBtnH, 4, 4)

        -- Button border
        love.graphics.setColor(0.5, 0.4, 0.3, 1)
        love.graphics.rectangle("line", campBtnX, campBtnY, campBtnW, campBtnH, 4, 4)

        -- Button text
        love.graphics.setColor(self.colors.header_text)
        love.graphics.printf("Make Camp", campBtnX, campBtnY + 12, campBtnW, "center")
    end

    --- Draw the drag ghost
    function screen:drawDragGhost()
        local ghost = self.inputManager:getDragGhost()
        if not ghost then return end

        -- Draw a semi-transparent version of what's being dragged
        love.graphics.setColor(1, 1, 1, 0.6)

        if ghost.dragType == "adventurer" then
            -- Adventurer ghost
            love.graphics.rectangle("fill", ghost.x - 30, ghost.y - 30, 60, 60)
            love.graphics.setColor(0, 0, 0, 0.8)
            love.graphics.print(ghost.source.name or "?", ghost.x - 25, ghost.y - 10)
        elseif ghost.dragType == "item" then
            -- Item ghost
            love.graphics.rectangle("fill", ghost.x - 20, ghost.y - 20, 40, 40)
            love.graphics.setColor(0, 0, 0, 0.8)
            love.graphics.print(ghost.source.name or "?", ghost.x - 15, ghost.y - 5)
        end

        -- Highlight drop target if hovering
        local isHovering, target = self.inputManager:isHoveringDropTarget()
        if isHovering and target then
            love.graphics.setColor(0.2, 0.8, 0.4, 0.3)
            love.graphics.rectangle(
                "fill",
                target.x - 2,
                target.y - 2,
                target.width + 4,
                target.height + 4
            )
        end
    end

    ----------------------------------------------------------------------------
    -- LÖVE 2D CALLBACKS
    ----------------------------------------------------------------------------

    function screen:mousepressed(x, y, button)
        -- Focus menu gets priority
        if self.focusMenu and self.focusMenu.isOpen then
            self.focusMenu:onMousePressed(x, y, button)
            return
        end

        -- S10.3: Belt hotbar click handling
        if self.beltHotbar and self.beltHotbar:mousepressed(x, y, button) then
            return
        end

        -- S11.4: Camp button click handling
        if button == 1 and self.campButtonBounds then
            local btn = self.campButtonBounds
            if x >= btn.x and x < btn.x + btn.w and
               y >= btn.y and y < btn.y + btn.h then
                -- Trigger camp phase
                self.eventBus:emit(events.EVENTS.PHASE_CHANGED, {
                    oldPhase = "crawl",
                    newPhase = "camp",
                })
                return
            end
        end

        self.inputManager:mousepressed(x, y, button)
    end

    function screen:mousereleased(x, y, button)
        if self.focusMenu and self.focusMenu.isOpen then
            self.focusMenu:onMouseReleased(x, y, button)
            return
        end

        self.inputManager:mousereleased(x, y, button)
    end

    function screen:mousemoved(x, y, dx, dy)
        if self.focusMenu and self.focusMenu.isOpen then
            self.focusMenu:onMouseMoved(x, y)
        end

        self.inputManager:mousemoved(x, y, dx, dy)
    end

    function screen:keypressed(key)
        -- ESC closes menu
        if key == "escape" then
            if self.focusMenu and self.focusMenu.isOpen then
                self.focusMenu:close()
            end
        end

        -- Space skips typewriter
        if key == "space" then
            if self.narrativeView and not self.narrativeView:isTypewriterComplete() then
                self.narrativeView:skipTypewriter()
            end
        end

        -- S10.3: Belt hotbar keyboard shortcuts (1-4 for items, Tab to cycle PC)
        -- Note: Only active in crawl phase, not during challenges
        if self.beltHotbar then
            self.beltHotbar:keypressed(key)
        end
    end

    return screen
end

return M

```

---

## File: src/ui/screens/end_of_demo_screen.lua

```lua
-- end_of_demo_screen.lua
-- End of Demo / City Stub Screen for Majesty
-- Ticket S10.1: Loop closure for playtesting
--
-- Displays when the party exits the dungeon or retrieves the Vellum Map.
-- Provides a "Return to City" button that resets the game for another run.

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- COLORS
--------------------------------------------------------------------------------
M.COLORS = {
    background     = { 0.08, 0.06, 0.10, 1.0 },
    title          = { 0.95, 0.85, 0.60, 1.0 },   -- Gold
    subtitle       = { 0.75, 0.70, 0.65, 1.0 },
    text           = { 0.85, 0.82, 0.78, 1.0 },
    panel_bg       = { 0.12, 0.10, 0.14, 0.95 },
    panel_border   = { 0.40, 0.35, 0.30, 1.0 },
    button_bg      = { 0.25, 0.20, 0.15, 1.0 },
    button_hover   = { 0.35, 0.30, 0.20, 1.0 },
    button_text    = { 0.95, 0.90, 0.80, 1.0 },
    stat_good      = { 0.50, 0.75, 0.45, 1.0 },   -- Green
    stat_bad       = { 0.75, 0.45, 0.45, 1.0 },   -- Red
    stat_neutral   = { 0.70, 0.65, 0.60, 1.0 },
}

--------------------------------------------------------------------------------
-- END OF DEMO SCREEN FACTORY
--------------------------------------------------------------------------------

--- Create a new EndOfDemoScreen
-- @param config table: { eventBus, guild, onReturnToCity, victoryReason }
-- @return EndOfDemoScreen instance
function M.createEndOfDemoScreen(config)
    config = config or {}

    local screen = {
        eventBus        = config.eventBus or events.globalBus,
        guild           = config.guild or {},
        onReturnToCity  = config.onReturnToCity,  -- Callback function
        victoryReason   = config.victoryReason or "completed",  -- "vellum_map", "exited", "completed"

        -- Layout
        width           = 800,
        height          = 600,

        -- Button state
        hoverButton     = nil,

        -- Colors
        colors          = M.COLORS,

        -- Animation
        fadeIn          = 0,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function screen:init()
        self.fadeIn = 0
    end

    function screen:resize(w, h)
        self.width = w
        self.height = h
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function screen:update(dt)
        -- Fade in animation
        if self.fadeIn < 1 then
            self.fadeIn = math.min(1, self.fadeIn + dt * 2)
        end
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    ----------------------------------------------------------------------------

    function screen:draw()
        if not love then return end

        local alpha = self.fadeIn

        -- Background
        love.graphics.setColor(self.colors.background[1], self.colors.background[2],
                               self.colors.background[3], alpha)
        love.graphics.rectangle("fill", 0, 0, self.width, self.height)

        -- Central panel
        local panelW = math.min(600, self.width - 60)
        local panelH = 450
        local panelX = (self.width - panelW) / 2
        local panelY = (self.height - panelH) / 2

        -- Panel background
        love.graphics.setColor(self.colors.panel_bg[1], self.colors.panel_bg[2],
                               self.colors.panel_bg[3], alpha * 0.95)
        love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 12, 12)

        -- Panel border
        love.graphics.setColor(self.colors.panel_border[1], self.colors.panel_border[2],
                               self.colors.panel_border[3], alpha)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 12, 12)
        love.graphics.setLineWidth(1)

        -- Title
        local title = self:getTitle()
        love.graphics.setColor(self.colors.title[1], self.colors.title[2],
                               self.colors.title[3], alpha)
        love.graphics.printf(title, panelX, panelY + 25, panelW, "center")

        -- Subtitle
        local subtitle = self:getSubtitle()
        love.graphics.setColor(self.colors.subtitle[1], self.colors.subtitle[2],
                               self.colors.subtitle[3], alpha)
        love.graphics.printf(subtitle, panelX, panelY + 55, panelW, "center")

        -- Separator line
        love.graphics.setColor(self.colors.panel_border[1], self.colors.panel_border[2],
                               self.colors.panel_border[3], alpha * 0.5)
        love.graphics.line(panelX + 40, panelY + 85, panelX + panelW - 40, panelY + 85)

        -- Guild summary
        self:drawGuildSummary(panelX + 20, panelY + 100, panelW - 40, alpha)

        -- City effects description
        self:drawCityEffects(panelX + 20, panelY + 280, panelW - 40, alpha)

        -- Return to City button
        self:drawReturnButton(panelX, panelY + panelH - 70, panelW, alpha)
    end

    function screen:getTitle()
        if self.victoryReason == "vellum_map" then
            return "VICTORY!"
        elseif self.victoryReason == "exited" then
            return "RETURNED TO SURFACE"
        else
            return "EXPEDITION COMPLETE"
        end
    end

    function screen:getSubtitle()
        if self.victoryReason == "vellum_map" then
            return "The Vellum Map has been retrieved!"
        elseif self.victoryReason == "exited" then
            return "The guild has escaped the dungeon."
        else
            return "The dungeon awaits another expedition."
        end
    end

    function screen:drawGuildSummary(x, y, w, alpha)
        love.graphics.setColor(self.colors.text[1], self.colors.text[2],
                               self.colors.text[3], alpha)
        love.graphics.print("EXPEDITION REPORT", x, y)

        local lineY = y + 25
        local lineH = 28

        for i, adventurer in ipairs(self.guild) do
            -- Name
            love.graphics.setColor(self.colors.text[1], self.colors.text[2],
                                   self.colors.text[3], alpha)
            love.graphics.print(adventurer.name, x + 10, lineY)

            -- Wounds status
            local woundText = self:getWoundStatus(adventurer)
            local woundColor = adventurer.conditions and
                (adventurer.conditions.dead and self.colors.stat_bad or
                 adventurer.conditions.deaths_door and self.colors.stat_bad or
                 adventurer.conditions.injured and self.colors.stat_bad or
                 self.colors.stat_good)
            love.graphics.setColor(woundColor[1], woundColor[2], woundColor[3], alpha)
            love.graphics.print(woundText, x + 150, lineY)

            -- Conditions
            local condText = self:getConditionText(adventurer)
            love.graphics.setColor(self.colors.stat_neutral[1], self.colors.stat_neutral[2],
                                   self.colors.stat_neutral[3], alpha)
            love.graphics.print(condText, x + 280, lineY)

            lineY = lineY + lineH
        end
    end

    function screen:getWoundStatus(adventurer)
        if adventurer.conditions then
            if adventurer.conditions.dead then
                return "DEAD"
            elseif adventurer.conditions.deaths_door then
                return "Death's Door!"
            elseif adventurer.conditions.injured then
                return "Injured"
            elseif adventurer.conditions.staggered then
                return "Staggered"
            end
        end
        return "Healthy"
    end

    function screen:getConditionText(adventurer)
        local conditions = {}
        if adventurer.conditions then
            if adventurer.conditions.stressed then
                conditions[#conditions + 1] = "Stressed"
            end
            if adventurer.conditions.starving then
                conditions[#conditions + 1] = "Starving"
            end
        end
        if #conditions == 0 then
            return ""
        end
        return table.concat(conditions, ", ")
    end

    function screen:drawCityEffects(x, y, w, alpha)
        love.graphics.setColor(self.colors.subtitle[1], self.colors.subtitle[2],
                               self.colors.subtitle[3], alpha)
        love.graphics.print("RETURNING TO THE CITY WILL:", x, y)

        local effects = {
            "* Heal all wounds and conditions",
            "* Deduct 50% of gold (upkeep)",
            "* Refill torches, rations, and arrows",
            "* Reset the dungeon for another run",
        }

        local lineY = y + 25
        love.graphics.setColor(self.colors.text[1], self.colors.text[2],
                               self.colors.text[3], alpha * 0.85)
        for _, effect in ipairs(effects) do
            love.graphics.print(effect, x + 10, lineY)
            lineY = lineY + 20
        end
    end

    function screen:drawReturnButton(panelX, y, panelW, alpha)
        local btnW, btnH = 200, 45
        local btnX = panelX + (panelW - btnW) / 2

        local isHover = self.hoverButton == "return"
        local btnColor = isHover and self.colors.button_hover or self.colors.button_bg

        love.graphics.setColor(btnColor[1], btnColor[2], btnColor[3], alpha)
        love.graphics.rectangle("fill", btnX, y, btnW, btnH, 6, 6)

        love.graphics.setColor(self.colors.panel_border[1], self.colors.panel_border[2],
                               self.colors.panel_border[3], alpha)
        love.graphics.rectangle("line", btnX, y, btnW, btnH, 6, 6)

        love.graphics.setColor(self.colors.button_text[1], self.colors.button_text[2],
                               self.colors.button_text[3], alpha)
        love.graphics.printf("Return to City", btnX, y + 13, btnW, "center")

        -- Store bounds
        self.returnButtonBounds = { x = btnX, y = y, w = btnW, h = btnH }
    end

    ----------------------------------------------------------------------------
    -- INPUT HANDLING
    ----------------------------------------------------------------------------

    function screen:mousepressed(x, y, button)
        if button ~= 1 then return end

        -- Check return button
        if self.returnButtonBounds then
            local btn = self.returnButtonBounds
            if x >= btn.x and x <= btn.x + btn.w and
               y >= btn.y and y <= btn.y + btn.h then
                if self.onReturnToCity then
                    self.onReturnToCity()
                end
            end
        end
    end

    function screen:mousereleased(x, y, button)
        -- Nothing
    end

    function screen:mousemoved(x, y, dx, dy)
        self.hoverButton = nil

        if self.returnButtonBounds then
            local btn = self.returnButtonBounds
            if x >= btn.x and x <= btn.x + btn.w and
               y >= btn.y and y <= btn.y + btn.h then
                self.hoverButton = "return"
            end
        end
    end

    function screen:keypressed(key)
        -- Enter or Space also triggers return
        if key == "return" or key == "space" then
            if self.onReturnToCity then
                self.onReturnToCity()
            end
        end
    end

    return screen
end

return M

```

---

## File: src/ui/sound_manager.lua

```lua
-- sound_manager.lua
-- Sound Manager for Majesty
-- Ticket S10.2: Audio architecture stubs
--
-- Placeholder implementation that logs sound requests.
-- Replace with actual audio loading when assets are available.

local M = {}

--------------------------------------------------------------------------------
-- SOUND TYPES
--------------------------------------------------------------------------------
M.SOUNDS = {
    -- Combat
    SWORD_HIT     = "sword_hit",
    SWORD_MISS    = "sword_miss",
    ARROW_FIRE    = "arrow_fire",
    ARROW_HIT     = "arrow_hit",
    BLOCK         = "block",
    DODGE         = "dodge",
    CRITICAL_HIT  = "critical_hit",

    -- Cards
    CARD_FLIP     = "card_flip",
    CARD_PLAY     = "card_play",
    CARD_DRAW     = "card_draw",
    CARD_SHUFFLE  = "card_shuffle",

    -- UI
    BUTTON_CLICK  = "button_click",
    BUTTON_HOVER  = "button_hover",
    MENU_OPEN     = "menu_open",
    MENU_CLOSE    = "menu_close",

    -- Combat events
    TURN_START    = "turn_start",
    ROUND_START   = "round_start",
    VICTORY       = "victory",
    DEFEAT        = "defeat",

    -- Conditions
    STAGGERED     = "staggered",
    INJURED       = "injured",
    DEATHS_DOOR   = "deaths_door",
    DEATH         = "death",

    -- Ambience
    DUNGEON_AMBIENT = "dungeon_ambient",
    CAMP_FIRE       = "camp_fire",
    COMBAT_MUSIC    = "combat_music",
}

--------------------------------------------------------------------------------
-- SOUND MANAGER SINGLETON
--------------------------------------------------------------------------------

local soundManager = {
    enabled = true,
    volume = 1.0,
    musicVolume = 0.7,
    sfxVolume = 1.0,

    -- Loaded sounds cache
    sounds = {},

    -- Currently playing music
    currentMusic = nil,

    -- Debug mode - logs all sound requests
    debug = true,
}

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

--- Initialize the sound manager
function M.init()
    -- In a full implementation, this would load sound files
    -- For now, just set up the structure
    print("[SoundManager] Initialized (stub mode)")
end

--------------------------------------------------------------------------------
-- SOUND PLAYBACK
--------------------------------------------------------------------------------

--- Play a sound effect
-- @param soundId string: One of SOUNDS constants
-- @param options table: { volume, pitch, loop }
function M.play(soundId, options)
    options = options or {}

    if not soundManager.enabled then return end

    local volume = (options.volume or 1.0) * soundManager.sfxVolume * soundManager.volume

    if soundManager.debug then
        print("[SoundManager] Play: " .. soundId .. " (vol: " .. string.format("%.2f", volume) .. ")")
    end

    -- In full implementation:
    -- local sound = soundManager.sounds[soundId]
    -- if sound then
    --     sound:setVolume(volume)
    --     if options.pitch then sound:setPitch(options.pitch) end
    --     sound:play()
    -- end
end

--- Play background music
-- @param musicId string: Music track ID
-- @param fadeIn number: Fade in time in seconds (optional)
function M.playMusic(musicId, fadeIn)
    if not soundManager.enabled then return end

    if soundManager.debug then
        print("[SoundManager] Music: " .. musicId)
    end

    soundManager.currentMusic = musicId

    -- In full implementation:
    -- if soundManager.currentMusic then
    --     soundManager.currentMusic:stop()
    -- end
    -- local music = soundManager.sounds[musicId]
    -- if music then
    --     music:setLooping(true)
    --     music:setVolume(soundManager.musicVolume * soundManager.volume)
    --     music:play()
    --     soundManager.currentMusic = music
    -- end
end

--- Stop current music
-- @param fadeOut number: Fade out time in seconds (optional)
function M.stopMusic(fadeOut)
    if soundManager.debug then
        print("[SoundManager] Stop music")
    end
    soundManager.currentMusic = nil
end

--------------------------------------------------------------------------------
-- CONVENIENCE METHODS
--------------------------------------------------------------------------------

--- Play combat hit sound based on weapon type
function M.playCombatHit(weaponType, isCritical)
    if isCritical then
        M.play(M.SOUNDS.CRITICAL_HIT)
    elseif weaponType == "bow" or weaponType == "crossbow" then
        M.play(M.SOUNDS.ARROW_HIT)
    else
        M.play(M.SOUNDS.SWORD_HIT)
    end
end

--- Play combat miss sound
function M.playCombatMiss(wasBlocked)
    if wasBlocked then
        M.play(M.SOUNDS.BLOCK)
    else
        M.play(M.SOUNDS.SWORD_MISS)
    end
end

--- Play card sound
function M.playCardSound(action)
    if action == "draw" then
        M.play(M.SOUNDS.CARD_DRAW)
    elseif action == "play" then
        M.play(M.SOUNDS.CARD_PLAY)
    elseif action == "flip" then
        M.play(M.SOUNDS.CARD_FLIP)
    elseif action == "shuffle" then
        M.play(M.SOUNDS.CARD_SHUFFLE)
    end
end

--- Play condition sound
function M.playConditionSound(condition)
    local conditionSounds = {
        staggered = M.SOUNDS.STAGGERED,
        injured = M.SOUNDS.INJURED,
        deaths_door = M.SOUNDS.DEATHS_DOOR,
        dead = M.SOUNDS.DEATH,
    }
    local soundId = conditionSounds[condition]
    if soundId then
        M.play(soundId)
    end
end

--------------------------------------------------------------------------------
-- SETTINGS
--------------------------------------------------------------------------------

--- Enable/disable all sounds
function M.setEnabled(enabled)
    soundManager.enabled = enabled
    print("[SoundManager] Sound " .. (enabled and "enabled" or "disabled"))
end

--- Set master volume (0.0 - 1.0)
function M.setVolume(volume)
    soundManager.volume = math.max(0, math.min(1, volume))
end

--- Set music volume (0.0 - 1.0)
function M.setMusicVolume(volume)
    soundManager.musicVolume = math.max(0, math.min(1, volume))
end

--- Set SFX volume (0.0 - 1.0)
function M.setSFXVolume(volume)
    soundManager.sfxVolume = math.max(0, math.min(1, volume))
end

--- Enable/disable debug logging
function M.setDebug(enabled)
    soundManager.debug = enabled
end

return M

```

---

## File: src/ui/wound_walk.lua

```lua
-- wound_walk.lua
-- Wound Walk Visual Feedback System for Majesty
-- Ticket S4.3: Visually demonstrate defense layer priority
--
-- When takeWound() is called, shows the cascade:
-- 1. Armor -> Flash armor icon, show notch appearing
-- 2. Talent -> Highlight talents, show X over wounded talent
-- 3. Condition -> Shake health pips on portrait
--
-- This helps players understand their defense layers working (or failing).

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- ANIMATION STATES
--------------------------------------------------------------------------------
M.STATES = {
    IDLE         = "idle",
    ARMOR_CHECK  = "armor_check",
    TALENT_CHECK = "talent_check",
    CONDITION    = "condition",
    COMPLETE     = "complete",
}

--------------------------------------------------------------------------------
-- ANIMATION DURATIONS (seconds)
--------------------------------------------------------------------------------
M.DURATIONS = {
    armor_flash   = 0.3,
    notch_appear  = 0.2,
    talent_flash  = 0.3,
    talent_x      = 0.2,
    health_shake  = 0.4,
    transition    = 0.1,
}

--------------------------------------------------------------------------------
-- WOUND WALK FACTORY
--------------------------------------------------------------------------------

--- Create a new WoundWalk visual controller
-- @param config table: { eventBus, onComplete }
-- @return WoundWalk instance
function M.createWoundWalk(config)
    config = config or {}

    local walk = {
        eventBus   = config.eventBus or events.globalBus,
        onComplete = config.onComplete,

        -- Current state
        state      = M.STATES.IDLE,
        timer      = 0,
        duration   = 0,

        -- Current wound being visualized
        woundData  = nil,
        entity     = nil,

        -- Visual effects currently active
        activeEffects = {},

        -- Flash/shake parameters
        flashAlpha   = 0,
        shakeOffset  = { x = 0, y = 0 },
        shakeMagnitude = 5,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function walk:init()
        -- Listen for wound events
        self.eventBus:on(events.EVENTS.WOUND_TAKEN, function(data)
            self:startWalk(data)
        end)
    end

    ----------------------------------------------------------------------------
    -- WALK LIFECYCLE
    ----------------------------------------------------------------------------

    --- Start visualizing a wound
    -- @param data table: { entity, result, pierced }
    function walk:startWalk(data)
        if self.state ~= M.STATES.IDLE then
            -- Queue this wound? For now, skip if busy
            return
        end

        self.woundData = data
        self.entity = data.entity
        self.activeEffects = {}

        local result = data.result or ""

        -- Determine starting state based on what absorbed the wound
        if result == "armor_notched" then
            self:startArmorPhase()
        elseif result == "talent_wounded" then
            self:startTalentPhase()
        elseif result == "staggered" or
               result == "injured" or
               result == "deaths_door" or
               result == "dead" then
            self:startConditionPhase(result)
        else
            -- Unknown result, skip animation
            self:completeWalk()
        end
    end

    ----------------------------------------------------------------------------
    -- ARMOR PHASE
    -- Flash the armor icon and show a notch appearing
    ----------------------------------------------------------------------------

    function walk:startArmorPhase()
        self.state = M.STATES.ARMOR_CHECK
        self.timer = 0
        self.duration = M.DURATIONS.armor_flash + M.DURATIONS.notch_appear

        self.activeEffects = {
            {
                type = "armor_flash",
                target = self.entity,
                duration = M.DURATIONS.armor_flash,
                progress = 0,
            },
            {
                type = "notch_appear",
                target = self.entity,
                duration = M.DURATIONS.notch_appear,
                delay = M.DURATIONS.armor_flash,
                progress = 0,
            },
        }

        -- Emit event for UI to render
        self.eventBus:emit("wound_walk_phase", {
            phase = "armor",
            entity = self.entity,
            effects = self.activeEffects,
        })
    end

    ----------------------------------------------------------------------------
    -- TALENT PHASE
    -- Highlight the talents section and show an X over the wounded talent
    ----------------------------------------------------------------------------

    function walk:startTalentPhase()
        self.state = M.STATES.TALENT_CHECK
        self.timer = 0
        self.duration = M.DURATIONS.talent_flash + M.DURATIONS.talent_x

        -- Find which talent was wounded
        local woundedTalent = nil
        if self.entity and self.entity.talents then
            for talentId, talent in pairs(self.entity.talents) do
                if talent.wounded then
                    woundedTalent = talentId
                    break
                end
            end
        end

        self.activeEffects = {
            {
                type = "talent_flash",
                target = self.entity,
                talentId = woundedTalent,
                duration = M.DURATIONS.talent_flash,
                progress = 0,
            },
            {
                type = "talent_x",
                target = self.entity,
                talentId = woundedTalent,
                duration = M.DURATIONS.talent_x,
                delay = M.DURATIONS.talent_flash,
                progress = 0,
            },
        }

        self.eventBus:emit("wound_walk_phase", {
            phase = "talent",
            entity = self.entity,
            talentId = woundedTalent,
            effects = self.activeEffects,
        })
    end

    ----------------------------------------------------------------------------
    -- CONDITION PHASE
    -- Shake the health pips / portrait
    ----------------------------------------------------------------------------

    function walk:startConditionPhase(condition)
        self.state = M.STATES.CONDITION
        self.timer = 0
        self.duration = M.DURATIONS.health_shake

        -- Determine shake intensity based on severity
        local intensity = 1
        if condition == "injured" then
            intensity = 1.5
        elseif condition == "deaths_door" then
            intensity = 2
        elseif condition == "dead" then
            intensity = 3
        end

        self.activeEffects = {
            {
                type = "health_shake",
                target = self.entity,
                condition = condition,
                intensity = intensity,
                duration = M.DURATIONS.health_shake,
                progress = 0,
            },
        }

        -- Add color flash for severe conditions
        if condition == "deaths_door" or condition == "dead" then
            self.activeEffects[#self.activeEffects + 1] = {
                type = "danger_flash",
                target = self.entity,
                color = condition == "dead" and { 0.3, 0, 0 } or { 0.5, 0.1, 0.1 },
                duration = M.DURATIONS.health_shake,
                progress = 0,
            }
        end

        self.eventBus:emit("wound_walk_phase", {
            phase = "condition",
            entity = self.entity,
            condition = condition,
            effects = self.activeEffects,
        })
    end

    ----------------------------------------------------------------------------
    -- COMPLETE WALK
    ----------------------------------------------------------------------------

    function walk:completeWalk()
        self.state = M.STATES.COMPLETE

        self.eventBus:emit("wound_walk_complete", {
            entity = self.entity,
            woundData = self.woundData,
        })

        -- Reset state
        self.state = M.STATES.IDLE
        self.woundData = nil
        self.entity = nil
        self.activeEffects = {}
        self.timer = 0

        -- Call completion callback
        if self.onComplete then
            self.onComplete()
        end
    end

    ----------------------------------------------------------------------------
    -- UPDATE (call from love.update)
    ----------------------------------------------------------------------------

    function walk:update(dt)
        if self.state == M.STATES.IDLE then
            return
        end

        self.timer = self.timer + dt

        -- Update effect progress
        for _, effect in ipairs(self.activeEffects) do
            local effectStart = effect.delay or 0
            local effectTime = self.timer - effectStart

            if effectTime >= 0 then
                effect.progress = math.min(1, effectTime / effect.duration)
            end
        end

        -- Calculate shake offset for condition phase
        if self.state == M.STATES.CONDITION then
            local progress = self.timer / self.duration
            local shakeAmount = self.shakeMagnitude * (1 - progress)
            self.shakeOffset.x = math.sin(self.timer * 50) * shakeAmount
            self.shakeOffset.y = math.cos(self.timer * 40) * shakeAmount * 0.5
        else
            self.shakeOffset.x = 0
            self.shakeOffset.y = 0
        end

        -- Check for phase completion
        if self.timer >= self.duration then
            self:completeWalk()
        end
    end

    ----------------------------------------------------------------------------
    -- RENDERING HELPERS
    ----------------------------------------------------------------------------

    --- Get current active effects for rendering
    function walk:getActiveEffects()
        return self.activeEffects
    end

    --- Get shake offset for portrait rendering
    function walk:getShakeOffset()
        return self.shakeOffset
    end

    --- Check if walk is active
    function walk:isActive()
        return self.state ~= M.STATES.IDLE
    end

    --- Get current state
    function walk:getState()
        return self.state
    end

    --- Get flash alpha for armor/talent flash
    function walk:getFlashAlpha()
        if #self.activeEffects == 0 then
            return 0
        end

        for _, effect in ipairs(self.activeEffects) do
            if effect.type == "armor_flash" or
               effect.type == "talent_flash" or
               effect.type == "danger_flash" then
                -- Pulse effect: fade in then fade out
                local progress = effect.progress
                if progress < 0.5 then
                    return progress * 2  -- Fade in
                else
                    return (1 - progress) * 2  -- Fade out
                end
            end
        end

        return 0
    end

    --- Get the entity being animated
    function walk:getEntity()
        return self.entity
    end

    return walk
end

return M

```

---

## File: src/world/dungeon_graph.lua

```lua
-- dungeon_graph.lua
-- Dungeon Graph (Nodes & Edges) for Majesty
-- Ticket T2_1: Graph data structure for dungeon layout
--
-- Design: Rooms are nodes, Connections are edges with properties.
-- Store only room_id in connections (not full Room tables) to avoid
-- infinite recursion when serializing for save files.

local M = {}

--------------------------------------------------------------------------------
-- DIRECTION CONSTANTS
--------------------------------------------------------------------------------
M.DIRECTIONS = {
    NORTH = "north",
    SOUTH = "south",
    EAST  = "east",
    WEST  = "west",
    UP    = "up",
    DOWN  = "down",
}

-- Opposite directions for two-way connections
local OPPOSITE = {
    north = "south",
    south = "north",
    east  = "west",
    west  = "east",
    up    = "down",
    down  = "up",
}

--------------------------------------------------------------------------------
-- ROOM FACTORY
--------------------------------------------------------------------------------

--- Default zone for rooms (T2_3)
local DEFAULT_ZONE = {
    id          = "main",
    name        = "Main",
    description = "The main area of this room.",
}

--- Create a new Room
-- @param config table: { id, name, description, zones }
-- @return Room table
function M.createRoom(config)
    config = config or {}

    -- Ensure room has at least one zone (default: "Main")
    local zones = config.zones
    if not zones or #zones == 0 then
        zones = { DEFAULT_ZONE }
    end

    return {
        id          = config.id or error("Room requires an id"),
        name        = config.name or "Unknown Room",
        description = config.description or "",
        zones       = zones,                     -- Internal zones (T2_3) - always has at least "main"
        connections = {},                        -- Populated by graph:addConnection
        discovered  = config.discovered or true, -- Has this room been found?
        properties  = config.properties or {},   -- Custom room properties
    }
end

--------------------------------------------------------------------------------
-- CONNECTION FACTORY
-- Connections are objects - they can hold logic (locked doors, traps, etc.)
--------------------------------------------------------------------------------

--- Create a Connection (edge) between rooms
-- @param targetRoomId string: The room this connection leads to
-- @param properties table: { direction, is_secret, is_locked, is_one_way, ... }
-- @return Connection table
local function createConnection(targetRoomId, properties)
    properties = properties or {}

    return {
        target_room_id = targetRoomId,
        direction      = properties.direction or nil,
        is_secret      = properties.is_secret or false,
        is_locked      = properties.is_locked or false,
        is_one_way     = properties.is_one_way or false,
        discovered     = not (properties.is_secret or false),  -- Secrets start undiscovered
        key_id         = properties.key_id or nil,              -- What unlocks this?
        trap           = properties.trap or nil,                -- Trap data (future)
        description    = properties.description or nil,         -- "A heavy iron door"
    }
end

--------------------------------------------------------------------------------
-- DUNGEON GRAPH FACTORY
--------------------------------------------------------------------------------

--- Create a new DungeonGraph
-- @return DungeonGraph instance
function M.createGraph()
    local graph = {
        rooms = {},       -- room_id -> Room
        name  = "Unnamed Dungeon",
    }

    ----------------------------------------------------------------------------
    -- ROOM MANAGEMENT
    ----------------------------------------------------------------------------

    --- Add a room to the graph
    -- @param room table: Room created by createRoom()
    function graph:addRoom(room)
        if not room.id then
            return false, "room_missing_id"
        end
        self.rooms[room.id] = room
        return true
    end

    --- Get a room by ID
    function graph:getRoom(roomId)
        return self.rooms[roomId]
    end

    --- Check if a room exists
    function graph:hasRoom(roomId)
        return self.rooms[roomId] ~= nil
    end

    --- Create and add a room in one call
    function graph:createRoom(config)
        local room = M.createRoom(config)
        self:addRoom(room)
        return room
    end

    ----------------------------------------------------------------------------
    -- CONNECTION MANAGEMENT
    ----------------------------------------------------------------------------

    --- Add a connection between two rooms
    -- @param roomA_id string: Source room ID
    -- @param roomB_id string: Target room ID
    -- @param properties table: { direction, is_secret, is_locked, is_one_way, ... }
    -- @return boolean, string: success, error_reason
    function graph:addConnection(roomA_id, roomB_id, properties)
        properties = properties or {}

        local roomA = self.rooms[roomA_id]
        local roomB = self.rooms[roomB_id]

        if not roomA then
            return false, "source_room_not_found"
        end
        if not roomB then
            return false, "target_room_not_found"
        end

        -- Create the connection from A to B
        local connectionAtoB = createConnection(roomB_id, properties)
        roomA.connections[#roomA.connections + 1] = connectionAtoB

        -- If not one-way, create reverse connection from B to A
        if not properties.is_one_way then
            local reverseProps = {}
            for k, v in pairs(properties) do
                reverseProps[k] = v
            end
            -- Flip the direction for the reverse connection
            if properties.direction and OPPOSITE[properties.direction] then
                reverseProps.direction = OPPOSITE[properties.direction]
            end

            local connectionBtoA = createConnection(roomA_id, reverseProps)
            roomB.connections[#roomB.connections + 1] = connectionBtoA
        end

        return true
    end

    --- Add a one-way connection (convenience method)
    function graph:addOneWayConnection(fromId, toId, properties)
        properties = properties or {}
        properties.is_one_way = true
        return self:addConnection(fromId, toId, properties)
    end

    ----------------------------------------------------------------------------
    -- QUERIES
    ----------------------------------------------------------------------------

    --- Get adjacent rooms from a given room
    -- @param roomId string: The room to query from
    -- @param options table: { include_secret, include_locked }
    -- @return table: Array of { room, connection } pairs
    function graph:getAdjacentRooms(roomId, options)
        options = options or {}
        local includeSecret = options.include_secret or false
        local includeLocked = options.include_locked ~= false  -- Default true

        local room = self.rooms[roomId]
        if not room then
            return {}
        end

        local adjacent = {}
        for _, connection in ipairs(room.connections) do
            local include = true

            -- Filter out undiscovered secrets unless requested
            if connection.is_secret and not connection.discovered and not includeSecret then
                include = false
            end

            -- Optionally filter locked connections
            if connection.is_locked and not includeLocked then
                include = false
            end

            if include then
                local targetRoom = self.rooms[connection.target_room_id]
                if targetRoom then
                    adjacent[#adjacent + 1] = {
                        room       = targetRoom,
                        connection = connection,
                    }
                end
            end
        end

        return adjacent
    end

    --- Get a connection between two rooms (if it exists)
    function graph:getConnection(fromId, toId)
        local room = self.rooms[fromId]
        if not room then return nil end

        for _, conn in ipairs(room.connections) do
            if conn.target_room_id == toId then
                return conn
            end
        end
        return nil
    end

    --- Discover a secret connection
    function graph:discoverConnection(fromId, toId)
        local conn = self:getConnection(fromId, toId)
        if conn then
            conn.discovered = true
            return true
        end
        return false
    end

    --- Unlock a locked connection
    function graph:unlockConnection(fromId, toId)
        local conn = self:getConnection(fromId, toId)
        if conn then
            conn.is_locked = false
            -- Also unlock the reverse if it exists
            local reverse = self:getConnection(toId, fromId)
            if reverse then
                reverse.is_locked = false
            end
            return true
        end
        return false
    end

    ----------------------------------------------------------------------------
    -- PATHFINDING HELPERS
    ----------------------------------------------------------------------------

    --- Get all room IDs in the graph
    function graph:getAllRoomIds()
        local ids = {}
        for id, _ in pairs(self.rooms) do
            ids[#ids + 1] = id
        end
        return ids
    end

    --- Count rooms
    function graph:roomCount()
        local count = 0
        for _ in pairs(self.rooms) do
            count = count + 1
        end
        return count
    end

    ----------------------------------------------------------------------------
    -- RESET (S10.1)
    ----------------------------------------------------------------------------

    --- Reset the dungeon to its initial state
    -- Clears discovered flags, re-locks doors, hides secrets
    function graph:reset()
        for _, room in pairs(self.rooms) do
            -- Reset room discovery (keep entrance discovered)
            -- room.discovered = false  -- Uncomment if you want fog of war

            -- Reset all connections
            for _, conn in ipairs(room.connections) do
                -- Re-lock locked doors
                if conn.key_id then
                    conn.is_locked = true
                end

                -- Re-hide secrets
                if conn.is_secret then
                    conn.discovered = false
                end
            end
        end

        print("[DUNGEON] Graph reset to initial state")
    end

    return graph
end

--------------------------------------------------------------------------------
-- DATA LOADER
-- Load a dungeon from a data table (for map files)
--------------------------------------------------------------------------------

--- Load a dungeon graph from a data definition
-- @param data table: { name, rooms = {}, connections = {} }
-- @return DungeonGraph instance
function M.loadFromData(data)
    local graph = M.createGraph()
    graph.name = data.name or "Unnamed Dungeon"

    -- Add all rooms first
    for _, roomData in ipairs(data.rooms or {}) do
        graph:createRoom(roomData)
    end

    -- Then add connections
    for _, connData in ipairs(data.connections or {}) do
        graph:addConnection(connData.from, connData.to, connData.properties)
    end

    return graph
end

return M

```

---

## File: src/world/map_loader.lua

```lua
-- map_loader.lua
-- Map Generation Utility for Majesty
-- Ticket T2_7: Import maps from various formats into DungeonGraph
--
-- Supports:
-- 1. Standard Lua table format (as used by tutorial_level.lua)
-- 2. Simplified connection string format: "room1 -> room2 [props]"
-- 3. Room blueprint references

local dungeon_graph = require('dungeon_graph')

local M = {}

--------------------------------------------------------------------------------
-- EDGE PROPERTY PARSER
-- Parses edge properties from string format like [locked, secret, direction=north]
--------------------------------------------------------------------------------

local function parseEdgeProperties(propString)
    local props = {}

    if not propString or propString == "" then
        return props
    end

    -- Remove brackets if present
    propString = propString:gsub("^%[", ""):gsub("%]$", "")

    -- Split by comma
    for prop in propString:gmatch("[^,]+") do
        prop = prop:match("^%s*(.-)%s*$")  -- Trim whitespace

        -- Check for key=value format
        local key, value = prop:match("^(%w+)%s*=%s*(.+)$")
        if key then
            -- Handle quoted strings
            value = value:gsub("^[\"']", ""):gsub("[\"']$", "")

            -- Convert boolean strings
            if value == "true" then value = true
            elseif value == "false" then value = false
            end

            props[key] = value
        else
            -- Shorthand properties
            if prop == "locked" then
                props.is_locked = true
            elseif prop == "secret" then
                props.is_secret = true
            elseif prop == "oneway" or prop == "one_way" then
                props.is_one_way = true
            elseif prop:match("^north") or prop:match("^south") or
                   prop:match("^east") or prop:match("^west") or
                   prop:match("^up") or prop:match("^down") then
                props.direction = prop
            end
        end
    end

    return props
end

--------------------------------------------------------------------------------
-- CONNECTION STRING PARSER
-- Format: "room_a -> room_b [properties]"
-- or: "room_a -- room_b [properties]" (bidirectional)
-- or: "room_a <- room_b [properties]" (reverse)
--------------------------------------------------------------------------------

local function parseConnectionString(line)
    -- Match: room_a -> room_b [props] or room_a -- room_b [props]
    local from, arrow, to, propsStr = line:match("^%s*(%S+)%s*([%-<>]+)%s*(%S+)%s*(%[.-%])?%s*$")

    if not from or not to then
        return nil, "Invalid connection format"
    end

    local props = parseEdgeProperties(propsStr)

    -- Handle arrow direction
    if arrow == "<-" then
        -- Reverse direction
        from, to = to, from
    elseif arrow == "->" then
        props.is_one_way = true
    end
    -- "--" is bidirectional (default)

    return {
        from = from,
        to = to,
        properties = props
    }
end

--------------------------------------------------------------------------------
-- ROOM STRING PARSER
-- Format: "room_id: Room Name - Description"
-- or: "room_id: Room Name [props]"
--------------------------------------------------------------------------------

local function parseRoomString(line)
    -- Match: room_id: Name - Description
    local id, rest = line:match("^%s*(%S+):%s*(.+)$")

    if not id then
        return nil, "Invalid room format"
    end

    local name, description, propsStr

    -- Check for properties in brackets at end
    propsStr = rest:match("%[.-%]$")
    if propsStr then
        rest = rest:gsub("%s*%[.-%]$", "")
    end

    -- Split name and description by " - "
    name, description = rest:match("^(.-)%s+%-%s+(.+)$")
    if not name then
        name = rest:match("^%s*(.-)%s*$")
        description = ""
    end

    local props = parseEdgeProperties(propsStr)

    return {
        id = id,
        name = name,
        description = description,
        zones = props.zones,
        danger_level = props.danger_level,
    }
end

--------------------------------------------------------------------------------
-- TEXT FORMAT LOADER
-- Loads dungeon from a multi-line text format
--------------------------------------------------------------------------------

--- Load dungeon from text format
-- @param text string: Multi-line text defining rooms and connections
-- @return table: Data suitable for dungeon_graph.loadFromData
function M.parseTextFormat(text)
    local data = {
        name = "Unnamed Dungeon",
        rooms = {},
        connections = {},
    }

    local section = "header"  -- header, rooms, connections
    local roomsById = {}

    for line in text:gmatch("[^\r\n]+") do
        -- Skip empty lines and comments
        if not line:match("^%s*$") and not line:match("^%s*#") and not line:match("^%s*%-%-") then

            -- Section headers
            if line:match("^%[rooms%]") or line:match("^ROOMS:") then
                section = "rooms"
            elseif line:match("^%[connections%]") or line:match("^CONNECTIONS:") then
                section = "connections"
            elseif line:match("^%[name%]") or line:match("^NAME:") then
                section = "name"
            elseif section == "name" then
                data.name = line:match("^%s*(.-)%s*$")
                section = "header"
            elseif section == "rooms" then
                local room, err = parseRoomString(line)
                if room then
                    data.rooms[#data.rooms + 1] = room
                    roomsById[room.id] = room
                end
            elseif section == "connections" then
                local conn, err = parseConnectionString(line)
                if conn then
                    data.connections[#data.connections + 1] = conn
                end
            end
        end
    end

    return data
end

--------------------------------------------------------------------------------
-- SIMPLIFIED LOADER HELPERS
--------------------------------------------------------------------------------

--- Quick room definition helper
-- @param id string
-- @param name string
-- @param description string (optional)
-- @return table: Room data
function M.room(id, name, description)
    return {
        id = id,
        name = name or id,
        description = description or "",
    }
end

--- Quick connection helper
-- @param from string
-- @param to string
-- @param props table (optional): { direction, locked, secret, one_way, key_id }
-- @return table: Connection data
function M.connect(from, to, props)
    props = props or {}
    return {
        from = from,
        to = to,
        properties = {
            direction   = props.direction,
            is_locked   = props.locked,
            is_secret   = props.secret,
            is_one_way  = props.one_way,
            key_id      = props.key_id,
            description = props.description,
        },
    }
end

--- Quick locked door connection
function M.lockedDoor(from, to, direction, keyId)
    return M.connect(from, to, {
        direction = direction,
        locked = true,
        key_id = keyId,
    })
end

--- Quick secret passage connection
function M.secretPassage(from, to, direction)
    return M.connect(from, to, {
        direction = direction,
        secret = true,
    })
end

--- Quick one-way connection (chute, drop, etc.)
function M.oneWay(from, to, direction)
    return M.connect(from, to, {
        direction = direction,
        one_way = true,
    })
end

--------------------------------------------------------------------------------
-- MAIN LOADER FUNCTIONS
--------------------------------------------------------------------------------

--- Load dungeon from Lua table (wraps dungeon_graph.loadFromData)
-- @param data table: { name, rooms, connections }
-- @return DungeonGraph
function M.loadFromTable(data)
    return dungeon_graph.loadFromData(data)
end

--- Load dungeon from text format
-- @param text string: Multi-line text
-- @return DungeonGraph
function M.loadFromText(text)
    local data = M.parseTextFormat(text)
    return dungeon_graph.loadFromData(data)
end

--- Load dungeon from a Lua file
-- @param path string: Path to Lua file returning { data = {...} }
-- @return DungeonGraph
function M.loadFromFile(path)
    local module = require(path)
    if module.data then
        return dungeon_graph.loadFromData(module.data)
    end
    return nil, "File does not contain 'data' table"
end

--------------------------------------------------------------------------------
-- BUILDER PATTERN
-- Fluent interface for creating dungeons programmatically
--------------------------------------------------------------------------------

--- Create a new DungeonBuilder
-- @param name string: Dungeon name
-- @return DungeonBuilder
function M.builder(name)
    local builder = {
        data = {
            name = name or "Unnamed Dungeon",
            rooms = {},
            connections = {},
        }
    }

    --- Add a room
    function builder:addRoom(id, name, description, config)
        config = config or {}
        self.data.rooms[#self.data.rooms + 1] = {
            id = id,
            name = name or id,
            description = description or "",
            zones = config.zones,
            danger_level = config.danger_level,
        }
        return self
    end

    --- Add a bidirectional connection
    function builder:connect(from, to, direction, props)
        props = props or {}
        self.data.connections[#self.data.connections + 1] = {
            from = from,
            to = to,
            properties = {
                direction   = direction,
                is_locked   = props.locked,
                is_secret   = props.secret,
                is_one_way  = false,
                key_id      = props.key_id,
                description = props.description,
            },
        }
        return self
    end

    --- Add a locked door
    function builder:lockedDoor(from, to, direction, keyId)
        return self:connect(from, to, direction, { locked = true, key_id = keyId })
    end

    --- Add a secret passage
    function builder:secretPassage(from, to, direction)
        return self:connect(from, to, direction, { secret = true })
    end

    --- Add a one-way connection
    function builder:oneWay(from, to, direction)
        self.data.connections[#self.data.connections + 1] = {
            from = from,
            to = to,
            properties = {
                direction = direction,
                is_one_way = true,
            },
        }
        return self
    end

    --- Build the DungeonGraph
    function builder:build()
        return dungeon_graph.loadFromData(self.data)
    end

    return builder
end

return M

```

---

## File: src/world/zone_system.lua

```lua
-- zone_system.lua
-- Internal Room Zones for Majesty
-- Ticket T2_3: Spatial positioning within rooms for combat and interaction
--
-- Design: Zones are NOT Rooms. Rooms = navigation/exploration. Zones = tactical range.
-- Keep it simple: entity.zone = "Balcony" (no coordinate systems)
--
-- Rules Reference (p. 109):
-- - Zones demarcate different parts of dungeon rooms
-- - You can interact with things and characters in the same zone
-- - Move or Dash to go to a new zone
-- - Engaged characters moving to a new zone trigger parting blows

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- ZONE FACTORY
--------------------------------------------------------------------------------

--- Create a new Zone
-- @param config table: { id, name, description, adjacent_to, special_rules }
-- @return Zone table
function M.createZone(config)
    config = config or {}

    return {
        id           = config.id or error("Zone requires an id"),
        name         = config.name or config.id,
        description  = config.description or "",
        -- Specific adjacencies (if nil, zone is adjacent to all other zones in room)
        adjacent_to  = config.adjacent_to or nil,
        -- Special rules for this zone (e.g., "requires Pentacles test to enter")
        special_rules = config.special_rules or {},
    }
end

--- Create a default "Main" zone for rooms without defined zones
function M.createDefaultZone()
    return M.createZone({
        id          = "main",
        name        = "Main",
        description = "The main area of this room.",
    })
end

--------------------------------------------------------------------------------
-- ZONE REGISTRY
-- Tracks which entities are in which zones, and engagement states
--------------------------------------------------------------------------------

--- Create a new ZoneRegistry
-- @param config table: { eventBus }
-- @return ZoneRegistry instance
function M.createZoneRegistry(config)
    config = config or {}

    local registry = {
        -- zone_id -> { entity_id1, entity_id2, ... }
        zoneOccupants = {},
        -- entity_id -> zone_id
        entityZones = {},
        -- entity_id -> { engaged_with_id1, engaged_with_id2, ... }
        engagements = {},
        -- Reference to room's zones (set via setRoomZones)
        currentZones = {},
        eventBus = config.eventBus or events.globalBus,
    }

    ----------------------------------------------------------------------------
    -- ZONE SETUP
    ----------------------------------------------------------------------------

    --- Set the zones for the current room
    -- @param zones table: Array of Zone objects
    function registry:setRoomZones(zones)
        self.currentZones = {}
        for _, zone in ipairs(zones) do
            self.currentZones[zone.id] = zone
        end

        -- Clear occupants for new room (entities should be re-placed)
        self.zoneOccupants = {}
        self.entityZones = {}
        -- Note: engagements persist until explicitly broken
    end

    --- Get a zone by id
    function registry:getZone(zoneId)
        return self.currentZones[zoneId]
    end

    --- Get all zone ids
    function registry:getAllZoneIds()
        local ids = {}
        for id, _ in pairs(self.currentZones) do
            ids[#ids + 1] = id
        end
        return ids
    end

    ----------------------------------------------------------------------------
    -- ZONE ADJACENCY
    -- By default, all zones in a room are adjacent unless specified otherwise
    ----------------------------------------------------------------------------

    --- Check if two zones are adjacent
    -- @param zoneA_id string
    -- @param zoneB_id string
    -- @return boolean
    function registry:areZonesAdjacent(zoneA_id, zoneB_id)
        if zoneA_id == zoneB_id then
            return true  -- Same zone is "adjacent" to itself
        end

        local zoneA = self.currentZones[zoneA_id]
        local zoneB = self.currentZones[zoneB_id]

        if not zoneA or not zoneB then
            return false
        end

        -- If zoneA has specific adjacencies defined, check them
        if zoneA.adjacent_to then
            for _, adjId in ipairs(zoneA.adjacent_to) do
                if adjId == zoneB_id then
                    return true
                end
            end
            return false
        end

        -- If zoneB has specific adjacencies, check if A is in them
        if zoneB.adjacent_to then
            for _, adjId in ipairs(zoneB.adjacent_to) do
                if adjId == zoneA_id then
                    return true
                end
            end
            return false
        end

        -- Default: all zones are adjacent
        return true
    end

    --- Get all zones adjacent to a given zone
    function registry:getAdjacentZones(zoneId)
        local adjacent = {}
        for id, _ in pairs(self.currentZones) do
            if id ~= zoneId and self:areZonesAdjacent(zoneId, id) then
                adjacent[#adjacent + 1] = id
            end
        end
        return adjacent
    end

    ----------------------------------------------------------------------------
    -- ENTITY PLACEMENT
    ----------------------------------------------------------------------------

    --- Place an entity in a zone
    -- @param entityId string
    -- @param zoneId string
    -- @return boolean, string: success, error_reason
    function registry:placeEntity(entityId, zoneId)
        if not self.currentZones[zoneId] then
            return false, "zone_not_found"
        end

        -- Remove from previous zone if any
        local previousZone = self.entityZones[entityId]
        if previousZone and self.zoneOccupants[previousZone] then
            for i, id in ipairs(self.zoneOccupants[previousZone]) do
                if id == entityId then
                    table.remove(self.zoneOccupants[previousZone], i)
                    break
                end
            end
        end

        -- Add to new zone
        if not self.zoneOccupants[zoneId] then
            self.zoneOccupants[zoneId] = {}
        end
        self.zoneOccupants[zoneId][#self.zoneOccupants[zoneId] + 1] = entityId
        self.entityZones[entityId] = zoneId

        return true
    end

    --- Get an entity's current zone
    function registry:getEntityZone(entityId)
        return self.entityZones[entityId]
    end

    --- Get all entities in a zone
    function registry:getEntitiesInZone(zoneId)
        return self.zoneOccupants[zoneId] or {}
    end

    --- Remove an entity from zone tracking
    function registry:removeEntity(entityId)
        local zoneId = self.entityZones[entityId]
        if zoneId and self.zoneOccupants[zoneId] then
            for i, id in ipairs(self.zoneOccupants[zoneId]) do
                if id == entityId then
                    table.remove(self.zoneOccupants[zoneId], i)
                    break
                end
            end
        end
        self.entityZones[entityId] = nil
        self.engagements[entityId] = nil

        -- Also remove from other entities' engagement lists
        for otherId, engaged in pairs(self.engagements) do
            for i, id in ipairs(engaged) do
                if id == entityId then
                    table.remove(engaged, i)
                    break
                end
            end
        end
    end

    ----------------------------------------------------------------------------
    -- ENGAGEMENT SYSTEM
    -- Characters are either engaged or disengaged during Challenges
    ----------------------------------------------------------------------------

    --- Engage two entities with each other (mutual)
    function registry:engage(entityA_id, entityB_id)
        if not self.engagements[entityA_id] then
            self.engagements[entityA_id] = {}
        end
        if not self.engagements[entityB_id] then
            self.engagements[entityB_id] = {}
        end

        -- Add B to A's engagement list (if not already)
        local foundB = false
        for _, id in ipairs(self.engagements[entityA_id]) do
            if id == entityB_id then foundB = true; break end
        end
        if not foundB then
            self.engagements[entityA_id][#self.engagements[entityA_id] + 1] = entityB_id
        end

        -- Add A to B's engagement list (if not already)
        local foundA = false
        for _, id in ipairs(self.engagements[entityB_id]) do
            if id == entityA_id then foundA = true; break end
        end
        if not foundA then
            self.engagements[entityB_id][#self.engagements[entityB_id] + 1] = entityA_id
        end

        self.eventBus:emit(events.EVENTS.ENTITIES_ENGAGED, {
            entityA = entityA_id,
            entityB = entityB_id,
        })
    end

    --- Disengage two specific entities
    function registry:disengage(entityA_id, entityB_id)
        if self.engagements[entityA_id] then
            for i, id in ipairs(self.engagements[entityA_id]) do
                if id == entityB_id then
                    table.remove(self.engagements[entityA_id], i)
                    break
                end
            end
        end

        if self.engagements[entityB_id] then
            for i, id in ipairs(self.engagements[entityB_id]) do
                if id == entityA_id then
                    table.remove(self.engagements[entityB_id], i)
                    break
                end
            end
        end

        self.eventBus:emit(events.EVENTS.ENTITIES_DISENGAGED, {
            entityA = entityA_id,
            entityB = entityB_id,
        })
    end

    --- Disengage an entity from all opponents
    function registry:disengageAll(entityId)
        local engaged = self.engagements[entityId] or {}
        for _, otherId in ipairs(engaged) do
            self:disengage(entityId, otherId)
        end
    end

    --- Check if entity is engaged with anyone
    function registry:isEngaged(entityId)
        local engaged = self.engagements[entityId]
        return engaged and #engaged > 0
    end

    --- Get all entities an entity is engaged with
    function registry:getEngagedWith(entityId)
        return self.engagements[entityId] or {}
    end

    ----------------------------------------------------------------------------
    -- ZONE MOVEMENT
    -- Handles parting blows when engaged entity moves
    ----------------------------------------------------------------------------

    --- Move an entity to a new zone
    -- @param entityId string
    -- @param targetZoneId string
    -- @return table: { success, partingBlows[], previousZone, newZone, error }
    function registry:moveToZone(entityId, targetZoneId)
        local currentZone = self.entityZones[entityId]

        -- Validate target zone exists
        if not self.currentZones[targetZoneId] then
            return { success = false, error = "zone_not_found" }
        end

        -- Already in target zone
        if currentZone == targetZoneId then
            return { success = true, previousZone = currentZone, newZone = targetZoneId, partingBlows = {} }
        end

        -- Check adjacency (if we have a current zone)
        if currentZone and not self:areZonesAdjacent(currentZone, targetZoneId) then
            return { success = false, error = "zones_not_adjacent" }
        end

        -- Check for parting blows from engaged opponents
        local partingBlows = {}
        if self:isEngaged(entityId) then
            local engaged = self:getEngagedWith(entityId)
            for _, opponentId in ipairs(engaged) do
                -- Each engaged opponent may deal 1 Wound or allow passage
                -- We emit an event and let the combat system handle the choice
                partingBlows[#partingBlows + 1] = {
                    opponent = opponentId,
                    mover    = entityId,
                }
            end

            -- Emit parting blow event for combat system to handle
            if #partingBlows > 0 then
                self.eventBus:emit(events.EVENTS.PARTING_BLOW, {
                    mover       = entityId,
                    fromZone    = currentZone,
                    toZone      = targetZoneId,
                    opponents   = partingBlows,
                })
            end

            -- Disengage from all opponents after moving
            self:disengageAll(entityId)
        end

        -- Perform the move
        self:placeEntity(entityId, targetZoneId)

        -- Emit zone changed event
        self.eventBus:emit(events.EVENTS.ZONE_CHANGED, {
            entityId     = entityId,
            previousZone = currentZone,
            newZone      = targetZoneId,
        })

        return {
            success      = true,
            previousZone = currentZone,
            newZone      = targetZoneId,
            partingBlows = partingBlows,
        }
    end

    ----------------------------------------------------------------------------
    -- QUERIES
    -- For Aid Another, Light Source checks, etc.
    ----------------------------------------------------------------------------

    --- Check if two entities are in the same zone
    function registry:inSameZone(entityA_id, entityB_id)
        local zoneA = self.entityZones[entityA_id]
        local zoneB = self.entityZones[entityB_id]
        return zoneA and zoneB and zoneA == zoneB
    end

    --- Get all other entities in the same zone as an entity
    function registry:getZonemates(entityId)
        local zoneId = self.entityZones[entityId]
        if not zoneId then
            return {}
        end

        local mates = {}
        for _, id in ipairs(self.zoneOccupants[zoneId] or {}) do
            if id ~= entityId then
                mates[#mates + 1] = id
            end
        end
        return mates
    end

    --- Check if entities are within interaction range (same or adjacent zone)
    function registry:canInteract(entityA_id, entityB_id)
        local zoneA = self.entityZones[entityA_id]
        local zoneB = self.entityZones[entityB_id]

        if not zoneA or not zoneB then
            return false
        end

        return self:areZonesAdjacent(zoneA, zoneB)
    end

    return registry
end

return M

```

---

## File: .claude/settings.local.json

```json
{
  "permissions": {
    "allow": [
      "Bash(lua:*)",
      "Bash(cat:*)",
      "Bash(grep:*)",
      "Bash(luac:*)",
      "Bash(for f in /Users/russellbates/JunkDrawer/HMTW/Majesty/src/logic/challenge_controller.lua /Users/russellbates/JunkDrawer/HMTW/Majesty/src/ui/action_sequencer.lua /Users/russellbates/JunkDrawer/HMTW/Majesty/src/logic/action_resolver.lua /Users/russellbates/JunkDrawer/HMTW/Majesty/src/logic/npc_ai.lua)",
      "Bash(do luac:*)",
      "Bash(echo:*)",
      "Bash(done)",
      "Bash(timeout:*)",
      "Bash(for f in src/ui/arena_view.lua src/ui/command_board.lua src/ui/minor_action_panel.lua src/data/action_registry.lua src/logic/action_resolver.lua src/logic/challenge_controller.lua)",
      "Bash(for:*)"
    ]
  }
}

```

---

## File: .gitignore

```
/sprints/
/rulebook/
/.claude/
```

---

## File: constants.lua

```lua
-- constants.lua
-- Tarot card data structures and constant tables for Majesty
-- Ticket T1_1: Tarot Data Structures & Constants

local M = {}

--------------------------------------------------------------------------------
-- SUIT CONSTANTS (use these for logic, not string comparisons)
--------------------------------------------------------------------------------
M.SUITS = {
    SWORDS    = 1,
    PENTACLES = 2,
    CUPS      = 3,
    WANDS     = 4,
    MAJOR     = 5,  -- For major arcana cards
}

-- Reverse lookup: ID -> name (useful for display/debugging)
M.SUIT_NAMES = {
    [1] = "Swords",
    [2] = "Pentacles",
    [3] = "Cups",
    [4] = "Wands",
    [5] = "Major",
}

--------------------------------------------------------------------------------
-- FACE CARD VALUES
--------------------------------------------------------------------------------
M.FACE_VALUES = {
    PAGE   = 11,
    KNIGHT = 12,
    QUEEN  = 13,
    KING   = 14,
}

--------------------------------------------------------------------------------
-- CARD FACTORY
--------------------------------------------------------------------------------
local function createCard(name, suit, value, is_major)
    return {
        name     = name,
        suit     = suit,
        value    = value,
        is_major = is_major or false,
    }
end

--------------------------------------------------------------------------------
-- MINOR ARCANA (56 cards + The Fool = 57 cards in player deck)
--------------------------------------------------------------------------------
local function buildMinorArcana()
    local cards = {}
    local SUITS = M.SUITS
    local FACE_VALUES = M.FACE_VALUES

    -- Suit data: { suit_id, suit_name_for_cards }
    local suits = {
        { SUITS.SWORDS,    "Swords" },
        { SUITS.PENTACLES, "Pentacles" },
        { SUITS.CUPS,      "Cups" },
        { SUITS.WANDS,     "Wands" },
    }

    -- Number card names (Ace through Ten)
    local numberNames = {
        "Ace", "Two", "Three", "Four", "Five",
        "Six", "Seven", "Eight", "Nine", "Ten"
    }

    -- Face card names in order of value
    local faceCards = {
        { "Page",   FACE_VALUES.PAGE },
        { "Knight", FACE_VALUES.KNIGHT },
        { "Queen",  FACE_VALUES.QUEEN },
        { "King",   FACE_VALUES.KING },
    }

    -- Build all 56 suited cards
    for _, suitData in ipairs(suits) do
        local suitId, suitName = suitData[1], suitData[2]

        -- Number cards (Ace = 1 through Ten = 10)
        for value = 1, 10 do
            local name = numberNames[value] .. " of " .. suitName
            cards[#cards + 1] = createCard(name, suitId, value, false)
        end

        -- Face cards
        for _, faceData in ipairs(faceCards) do
            local faceName, faceValue = faceData[1], faceData[2]
            local name = faceName .. " of " .. suitName
            cards[#cards + 1] = createCard(name, suitId, faceValue, false)
        end
    end

    -- The Fool (value 0, belongs with minor arcana in player deck)
    cards[#cards + 1] = createCard("The Fool", SUITS.MAJOR, 0, true)

    return cards
end

--------------------------------------------------------------------------------
-- MAJOR ARCANA (21 cards, I-XXI, used by GM)
--------------------------------------------------------------------------------
local function buildMajorArcana()
    local cards = {}
    local SUITS = M.SUITS

    -- Major Arcana names in order (I through XXI)
    -- Note: The Fool (0) is NOT included here; it's in the minor arcana deck
    local majorNames = {
        "The Magician",         -- I
        "The High Priestess",   -- II
        "The Empress",          -- III
        "The Emperor",          -- IV
        "The Hierophant",       -- V
        "The Lovers",           -- VI
        "The Chariot",          -- VII
        "Strength",             -- VIII
        "The Hermit",           -- IX
        "Wheel of Fortune",     -- X
        "Justice",              -- XI
        "The Hanged Man",       -- XII
        "Death",                -- XIII
        "Temperance",           -- XIV
        "The Devil",            -- XV
        "The Tower",            -- XVI
        "The Star",             -- XVII
        "The Moon",             -- XVIII
        "The Sun",              -- XIX
        "Judgement",            -- XX
        "The World",            -- XXI
    }

    for i, name in ipairs(majorNames) do
        cards[#cards + 1] = createCard(name, SUITS.MAJOR, i, true)
    end

    return cards
end

--------------------------------------------------------------------------------
-- EXPORT CONSTANT TABLES
--------------------------------------------------------------------------------
M.MinorArcana = buildMinorArcana()  -- 57 cards (56 suited + The Fool)
M.MajorArcana = buildMajorArcana()  -- 21 cards (I-XXI)

return M

```

---

## File: scripts/dump_project_markdown.sh

~~~bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: dump_project_markdown.sh [-r ROOT_DIR] [-o OUTPUT_MD]

Create a single Markdown file containing the project's text files with clear
per-file separators and language-aware code fences, respecting .gitignore.

Options:
  -r, --root   Project root directory (default: current directory)
  -o, --out    Output Markdown file path (default: project_dump.md, created under root)
  -h, --help   Show this help and exit

Notes:
- Prefers ripgrep (rg) for file discovery; falls back to 'git ls-files'.
  Either ripgrep must be installed or ROOT_DIR must be a Git repo.
- Binary files are skipped.
EOF
}

ROOT_DIR="$(pwd)"
OUTPUT_PATH="project_dump.md"

while [ $# -gt 0 ]; do
  case "$1" in
    -r|--root)
      [ $# -ge 2 ] || { echo "Missing argument for $1" >&2; exit 1; }
      ROOT_DIR="$2"
      shift 2
      ;;
    -o|--out)
      [ $# -ge 2 ] || { echo "Missing argument for $1" >&2; exit 1; }
      OUTPUT_PATH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

# Normalize ROOT_DIR
if [ ! -d "$ROOT_DIR" ]; then
  echo "Root directory does not exist: $ROOT_DIR" >&2
  exit 1
fi
ROOT_DIR="$(cd "$ROOT_DIR" && pwd)"

# Normalize OUTPUT_PATH (make absolute if relative)
case "$OUTPUT_PATH" in
  /*) : ;; # absolute already
  *) OUTPUT_PATH="$ROOT_DIR/$OUTPUT_PATH" ;;
esac

mkdir -p "$(dirname "$OUTPUT_PATH")"

# Collect files respecting .gitignore
FILE_LIST="$(mktemp)"
TMP_OUT=""
cleanup() {
  rm -f "$FILE_LIST"
  if [ -n "${TMP_OUT:-}" ]; then rm -f "$TMP_OUT"; fi
}
trap cleanup EXIT

if command -v rg >/dev/null 2>&1; then
  # ripgrep respects .gitignore by default
  ( cd "$ROOT_DIR" && rg --files --hidden --follow --glob '!.git' ) > "$FILE_LIST"
elif [ -d "$ROOT_DIR/.git" ] && command -v git >/dev/null 2>&1; then
  # git files incl. untracked, excluding standard ignores
  ( cd "$ROOT_DIR" && git ls-files -co --exclude-standard ) > "$FILE_LIST"
else
  echo "Error: Need ripgrep (rg) installed or a Git repo to honor .gitignore." >&2
  exit 1
fi

# Additional filtering: ensure top-level directories/files specified with
# root-anchored patterns in .gitignore (e.g., /sprints/, /rulebook/, /.claude/)
# are excluded from FILE_LIST even when using 'git ls-files' that may include
# already-tracked files. Use awk-based string matching for macOS compatibility.
if [ -f "$ROOT_DIR/.gitignore" ]; then
  DIRS_CSV=""
  FILES_CSV=""
  while IFS= read -r raw; do
    # Strip trailing comments and whitespace
    line="${raw%%#*}"
    line="$(printf '%s' "$line" | sed -e 's/[[:space:]]*$//')"
    [ -n "$line" ] || continue
    # Only handle root-anchored patterns for directories/files
    case "$line" in
      /*/)
        name="${line#/}"; name="${name%/}"
        DIRS_CSV="${DIRS_CSV}${name},"
        ;;
      /*)
        name="${line#/}"
        FILES_CSV="${FILES_CSV}${name},"
        ;;
      *)
        # Non-root-anchored or other complex patterns are ignored here;
        # they are already handled by ripgrep when available.
        :
        ;;
    esac
  done < "$ROOT_DIR/.gitignore"

  if [ -n "$DIRS_CSV$FILES_CSV" ]; then
    TMP_LIST="$(mktemp)"
    awk -v dirs="$DIRS_CSV" -v files="$FILES_CSV" '
      BEGIN{
        n=split(dirs,d,","); for(i=1;i<=n;i++) if(d[i]!="") D[d[i]]=1;
        m=split(files,f,","); for(i=1;i<=m;i++) if(f[i]!="") F[f[i]]=1;
      }
      {
        path=$0
        slash=index(path,"/")
        if (slash>0) {
          comp=substr(path,1,slash-1)
          if (comp in D) next
        } else {
          if (path in F) next
        }
        print path
      }' "$FILE_LIST" > "$TMP_LIST"
    mv "$TMP_LIST" "$FILE_LIST"
  fi
fi

# Temporary output to avoid partial writes
TMP_OUT="$(mktemp)"

# Header
{
  echo "# Project Source Dump"
  echo
  echo "- Root: $ROOT_DIR"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  echo "---"
  echo
} >> "$TMP_OUT"

guess_lang() {
  # Echo a Markdown code fence language based on file extension
  # Falls back to empty (no language hint)
  file="$1"
  ext="${file##*.}"
  case "$ext" in
    lua) echo "lua" ;;
    md|markdown) echo "markdown" ;;
    txt|text|license|licence) echo "text" ;;
    sh|bash|zsh) echo "bash" ;;
    js|jsx|mjs|cjs) echo "javascript" ;;
    ts|tsx) echo "typescript" ;;
    json) echo "json" ;;
    yml|yaml) echo "yaml" ;;
    html|htm) echo "html" ;;
    css|scss|sass|less) echo "css" ;;
    py) echo "python" ;;
    go) echo "go" ;;
    rs) echo "rust" ;;
    java) echo "java" ;;
    kt|kts) echo "kotlin" ;;
    c) echo "c" ;;
    h) echo "c" ;;
    cpp|cxx|cc) echo "cpp" ;;
    hpp|hh|hxx) echo "cpp" ;;
    m) echo "objective-c" ;;
    mm) echo "objective-c++" ;;
    swift) echo "swift" ;;
    rb) echo "ruby" ;;
    php) echo "php" ;;
    *) echo "" ;;
  esac
}

is_text_file() {
  # Heuristic: grep -Iq returns success for text files
  # Using LC_ALL=C for consistent behavior across locales
  LC_ALL=C grep -Iq . -- "$1"
}

# Compute absolute path to skip if output resides under root
SKIP_ABS="$OUTPUT_PATH"

while IFS= read -r rel; do
  # Skip empty lines
  [ -n "$rel" ] || continue

  abs="$ROOT_DIR/$rel"

  # Skip non-regular files
  if [ ! -f "$abs" ]; then
    continue
  fi

  # Skip the output file itself if it lives in the tree
  if [ "$abs" = "$SKIP_ABS" ]; then
    continue
  fi

  # Skip binaries
  if ! is_text_file "$abs"; then
    continue
  fi

  # Decide on fence; if file contains triple backticks, use tildes
  fence='```'
  if grep -q '```' -- "$abs"; then
    fence='~~~'
  fi

  lang="$(guess_lang "$rel")"

  {
    echo "## File: $rel"
    echo
    if [ -n "$lang" ]; then
      echo "${fence}${lang}"
    else
      echo "${fence}"
    fi
    cat -- "$abs"
    echo
    echo "${fence}"
    echo
    echo "---"
    echo
  } >> "$TMP_OUT"
done < "$FILE_LIST"

mv -f "$TMP_OUT" "$OUTPUT_PATH"

echo "Wrote Markdown to: $OUTPUT_PATH"



~~~

---

## File: src/logic/deck.lua

```lua
-- deck.lua
-- Deck Lifecycle Manager for Majesty
-- Ticket T1_2: Manages draw_pile, discard_pile, shuffle, draw, and discard operations

local M = {}

--------------------------------------------------------------------------------
-- DEEP COPY HELPER
-- Prevents the "reference trap" where modifying a drawn card affects the registry
--------------------------------------------------------------------------------
local function deepCopyCard(card)
    return {
        name     = card.name,
        suit     = card.suit,
        value    = card.value,
        is_major = card.is_major,
    }
end

local function deepCopyCards(cards)
    local copy = {}
    for i, card in ipairs(cards) do
        copy[i] = deepCopyCard(card)
    end
    return copy
end

--------------------------------------------------------------------------------
-- FISHER-YATES SHUFFLE (in-place)
-- Note: Random seed must be initialized via game_clock:init() before use
--------------------------------------------------------------------------------
local function fisherYatesShuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

--------------------------------------------------------------------------------
-- DECK FACTORY
--------------------------------------------------------------------------------

--- Create a new Deck instance
-- @param cards table: Array of card data from constants.lua (MinorArcana or MajorArcana)
-- @return Deck instance with draw_pile, discard_pile, and methods
function M.createDeck(cards)
    local deck = {
        draw_pile    = {},
        discard_pile = {},
    }

    -- Deep copy cards into draw pile (avoid reference trap)
    if cards and #cards > 0 then
        deck.draw_pile = deepCopyCards(cards)
    end

    ----------------------------------------------------------------------------
    -- SHUFFLE: Randomize the draw pile in-place
    ----------------------------------------------------------------------------
    function deck:shuffle()
        fisherYatesShuffle(self.draw_pile)
        return self
    end

    ----------------------------------------------------------------------------
    -- DRAW: Remove and return the top card from draw pile
    -- Auto-reshuffles discard into draw pile if draw pile is empty
    ----------------------------------------------------------------------------
    function deck:draw()
        -- If draw pile is empty, check discard pile
        if #self.draw_pile == 0 then
            if #self.discard_pile == 0 then
                -- Both piles empty, nothing to draw
                return nil
            end

            -- Move discard pile to draw pile and shuffle
            self.draw_pile = self.discard_pile
            self.discard_pile = {}
            self:shuffle()
        end

        -- Remove and return top card (last element for O(1) removal)
        return table.remove(self.draw_pile)
    end

    ----------------------------------------------------------------------------
    -- DISCARD: Move a card to the discard pile
    ----------------------------------------------------------------------------
    function deck:discard(card)
        if card then
            self.discard_pile[#self.discard_pile + 1] = card
        end
        return self
    end

    ----------------------------------------------------------------------------
    -- UTILITY: Get counts for debugging/UI
    ----------------------------------------------------------------------------
    function deck:drawPileCount()
        return #self.draw_pile
    end

    function deck:discardPileCount()
        return #self.discard_pile
    end

    function deck:totalCards()
        return #self.draw_pile + #self.discard_pile
    end

    ----------------------------------------------------------------------------
    -- UTILITY: Peek at top of discard pile (some rules check this)
    ----------------------------------------------------------------------------
    function deck:peekDiscard()
        if #self.discard_pile == 0 then
            return nil
        end
        return self.discard_pile[#self.discard_pile]
    end

    ----------------------------------------------------------------------------
    -- RESET: Return all cards to draw pile and shuffle (full reshuffle)
    ----------------------------------------------------------------------------
    function deck:reset()
        -- Move all discarded cards back to draw pile
        for i = 1, #self.discard_pile do
            self.draw_pile[#self.draw_pile + 1] = self.discard_pile[i]
        end
        self.discard_pile = {}
        self:shuffle()
        return self
    end

    return deck
end

--------------------------------------------------------------------------------
-- CONVENIENCE CONSTRUCTORS
--------------------------------------------------------------------------------

--- Create the Player's Deck (Minor Arcana + The Fool)
-- @param constants table: The constants module from constants.lua
function M.createPlayerDeck(constants)
    local deck = M.createDeck(constants.MinorArcana)
    deck:shuffle()
    return deck
end

--- Create the GM's Deck (Major Arcana, I-XXI)
-- @param constants table: The constants module from constants.lua
function M.createGMDeck(constants)
    local deck = M.createDeck(constants.MajorArcana)
    deck:shuffle()
    return deck
end

return M

```

---

## File: src/logic/game_clock.lua

```lua
-- game_clock.lua
-- Game State and Round Manager for Majesty
-- Ticket T1_3: Tracks game phase and handles end-of-round triggers (Fool reshuffle)

local M = {}

--------------------------------------------------------------------------------
-- GLOBAL INITIALIZATION
-- Call once at game startup, before creating any decks
--------------------------------------------------------------------------------
local initialized = false

--- Initialize the random seed for the entire game
-- Must be called once before any deck shuffling occurs
-- Uses a combination of time and a high-precision counter to avoid
-- identical shuffles when multiple decks are created in the same millisecond
function M.init()
    if not initialized then
        -- Combine os.time() with os.clock() for better entropy
        local seed = os.time() + math.floor(os.clock() * 1000)
        math.randomseed(seed)
        -- Warm up the generator (first few values can be predictable)
        for _ = 1, 10 do math.random() end
        initialized = true
    end
end

--- Check if the system has been initialized
function M.isInitialized()
    return initialized
end

--------------------------------------------------------------------------------
-- PHASE CONSTANTS
--------------------------------------------------------------------------------
M.PHASES = {
    CRAWL     = 1,
    CHALLENGE = 2,
    CAMP      = 3,
    CITY      = 4,
}

M.PHASE_NAMES = {
    [1] = "Crawl",
    [2] = "Challenge",
    [3] = "Camp",
    [4] = "City",
}

--------------------------------------------------------------------------------
-- GAME CLOCK FACTORY
--------------------------------------------------------------------------------

--- Create a new GameClock instance
-- @param playerDeck Deck: The player's deck (Minor Arcana + Fool)
-- @param gmDeck Deck: The GM's deck (Major Arcana)
-- @return GameClock instance
function M.createGameClock(playerDeck, gmDeck)
    local clock = {
        currentPhase    = M.PHASES.CITY,  -- Games typically start in City phase
        pendingReshuffle = false,
        playerDeck      = playerDeck,
        gmDeck          = gmDeck,
        roundNumber     = 0,
    }

    ----------------------------------------------------------------------------
    -- PHASE MANAGEMENT
    ----------------------------------------------------------------------------

    --- Set the current game phase
    -- @param phase number: One of PHASES constants
    function clock:setPhase(phase)
        self.currentPhase = phase
        return self
    end

    --- Get the current phase
    function clock:getPhase()
        return self.currentPhase
    end

    --- Get the current phase name (for display/debugging)
    function clock:getPhaseName()
        return M.PHASE_NAMES[self.currentPhase] or "Unknown"
    end

    ----------------------------------------------------------------------------
    -- CARD DRAWN LISTENER
    -- Called whenever a card is drawn; checks for The Fool
    ----------------------------------------------------------------------------

    --- Notify the clock that a card was drawn
    -- If The Fool is drawn, sets pendingReshuffle flag
    -- @param card table: The card that was drawn
    -- @return card table: Returns the same card (for chaining/passthrough)
    function clock:onCardDrawn(card)
        if card and card.name == "The Fool" then
            self.pendingReshuffle = true
        end
        -- Return the card unchanged - Fool's value (0) is still used for resolution
        return card
    end

    ----------------------------------------------------------------------------
    -- END OF ROUND
    -- Handles the Fool-triggered dual-deck reshuffle
    ----------------------------------------------------------------------------

    --- End the current round
    -- If The Fool was drawn this round, reshuffles both decks
    -- @return boolean: true if reshuffle occurred, false otherwise
    function clock:endRound()
        self.roundNumber = self.roundNumber + 1

        if self.pendingReshuffle then
            -- Reset both decks: move all discards back and shuffle
            if self.playerDeck then
                self.playerDeck:reset()
            end
            if self.gmDeck then
                self.gmDeck:reset()
            end

            self.pendingReshuffle = false
            return true  -- Reshuffle occurred
        end

        return false  -- No reshuffle needed
    end

    ----------------------------------------------------------------------------
    -- UTILITY
    ----------------------------------------------------------------------------

    --- Check if a reshuffle is pending
    function clock:isReshufflePending()
        return self.pendingReshuffle
    end

    --- Get current round number
    function clock:getRoundNumber()
        return self.roundNumber
    end

    --- Manually trigger reshuffle (for edge cases/testing)
    function clock:forceReshuffle()
        self.pendingReshuffle = true
        return self
    end

    return clock
end

return M

```

---

## File: src/logic/resolver.lua

```lua
-- resolver.lua
-- Test of Fate Resolution Logic for Majesty
-- Ticket T1_4: Pure function library for resolving Tests of Fate and Pushing Fate
--
-- This module is STATELESS - it knows nothing about Decks or Players.
-- It just takes numbers and cards and returns results.

local M = {}

--------------------------------------------------------------------------------
-- RESULT TYPES
--------------------------------------------------------------------------------
M.RESULTS = {
    SUCCESS       = "success",
    GREAT_SUCCESS = "great_success",
    FAILURE       = "failure",
    GREAT_FAILURE = "great_failure",
}

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------
local TARGET_VALUE = 14  -- Threshold for success
local FAVOR_BONUS = 3    -- Bonus/penalty for favor/disfavor

--------------------------------------------------------------------------------
-- RESULT FACTORY
-- Creates a standardized result object
--------------------------------------------------------------------------------
local function createResult(resultType, total, cards)
    local isSuccess = (resultType == M.RESULTS.SUCCESS or resultType == M.RESULTS.GREAT_SUCCESS)
    local isGreat = (resultType == M.RESULTS.GREAT_SUCCESS or resultType == M.RESULTS.GREAT_FAILURE)

    return {
        result   = resultType,
        success  = isSuccess,
        isGreat  = isGreat,
        total    = total,
        cards    = cards or {},
    }
end

--------------------------------------------------------------------------------
-- RESOLVE INITIAL TEST
-- Called when an adventurer draws a card for a Test of Fate
--
-- @param attribute number: The adventurer's attribute value (1-4)
-- @param targetSuit number: The suit being tested (from constants.SUITS)
-- @param card table: The drawn card { name, suit, value, is_major }
-- @param favor boolean|nil: true = favor (+3), false = disfavor (-3), nil = neither
-- @return Result object
--------------------------------------------------------------------------------
function M.resolveTest(attribute, targetSuit, card, favor)
    local total = card.value + attribute

    -- Apply favor/disfavor (non-cumulative, binary)
    if favor == true then
        total = total + FAVOR_BONUS
    elseif favor == false then
        total = total - FAVOR_BONUS
    end

    local cards = { card }

    if total >= TARGET_VALUE then
        -- Success! Check for Great Success
        -- Great Success requires: matching suit on INITIAL draw (not push)
        if card.suit == targetSuit then
            return createResult(M.RESULTS.GREAT_SUCCESS, total, cards)
        else
            return createResult(M.RESULTS.SUCCESS, total, cards)
        end
    else
        -- Failure (can be pushed)
        return createResult(M.RESULTS.FAILURE, total, cards)
    end
end

--------------------------------------------------------------------------------
-- RESOLVE PUSH
-- Called when an adventurer pushes fate after an initial failure
--
-- @param previousTotal number: The total from the initial test (before push)
-- @param previousCards table: Array of cards from initial test
-- @param pushCard table: The second card drawn when pushing
-- @return Result object
--
-- Rules:
-- - If pushCard is The Fool → Great Failure (automatic)
-- - If new total >= 14 → Success (NEVER Great Success)
-- - If new total < 14 → Great Failure
--------------------------------------------------------------------------------
function M.resolvePush(previousTotal, previousCards, pushCard)
    local cards = {}
    for _, c in ipairs(previousCards) do
        cards[#cards + 1] = c
    end
    cards[#cards + 1] = pushCard

    -- The Fool when pushing = automatic Great Failure
    if pushCard.name == "The Fool" then
        -- Total includes Fool's value (0), but it's still Great Failure
        local total = previousTotal + pushCard.value
        return createResult(M.RESULTS.GREAT_FAILURE, total, cards)
    end

    local total = previousTotal + pushCard.value

    if total >= TARGET_VALUE then
        -- Success (never Great Success from pushing)
        return createResult(M.RESULTS.SUCCESS, total, cards)
    else
        -- Great Failure
        return createResult(M.RESULTS.GREAT_FAILURE, total, cards)
    end
end

--------------------------------------------------------------------------------
-- UTILITY: Check if a result can be pushed
-- Only failures (not great failures) can be pushed
--------------------------------------------------------------------------------
function M.canPush(result)
    return result.result == M.RESULTS.FAILURE
end

--------------------------------------------------------------------------------
-- UTILITY: Calculate minimum card value needed for success
-- Useful for UI hints
--------------------------------------------------------------------------------
function M.minimumCardNeeded(attribute, favor)
    local bonus = 0
    if favor == true then
        bonus = FAVOR_BONUS
    elseif favor == false then
        bonus = -FAVOR_BONUS
    end
    return TARGET_VALUE - attribute - bonus
end

return M

```

---

