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

local events = require('logic.events')
local inventory = require('logic.inventory')
local camp_controller = require('logic.camp_controller')
local app_bootstrap = require('app.bootstrap')

-- UI systems
local floating_text = require('ui.floating_text')

-- Entity systems
local adventurer = require('entities.adventurer')
local factory = require('entities.factory')

-- Map data
local tomb_data = require('data.maps.tomb_of_golden_ghosts')

-- UI Screens
local crawl_screen = require('ui.screens.crawl_screen')
local camp_screen = require('ui.screens.camp_screen')
local end_of_demo_screen = require('ui.screens.end_of_demo_screen')

--------------------------------------------------------------------------------
-- GAME STATE
--------------------------------------------------------------------------------

-- Global game state (accessible by UI components for active PC tracking)
gameState = {
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
    challengeOverlay    = nil,  -- Challenge HUD + hand rendering
    commandBoard        = nil,  -- S6.2: Categorized command board
    minorActionPanel    = nil,  -- S6.4: Minor action declaration panel
    challengeInputController = nil,  -- Extracted Challenge input flow
    keyInputRouter      = nil,  -- Extracted keypress routing
    mouseInputRouter    = nil,  -- Extracted mouse routing
    pendingTestAction   = nil,  -- S12.5: Pending Test of Fate Challenge action

    -- Camp systems (Sprint 8-9)
    campController      = nil,
    campScreen          = nil,

    -- S11.1: Character sheet modal
    characterSheet      = nil,

    -- S11.3: Loot modal
    lootModal           = nil,

    -- S12.5: Test of Fate modal
    testOfFateModal     = nil,

    -- S13.2: Layout manager for stage-based UI
    layoutManager       = nil,

    -- Party
    guild             = {},    -- Array of adventurer entities

    -- Current screen
    currentScreen     = nil,

    -- Event bus
    eventBus          = events.globalBus,

    -- Game phase
    phase             = "crawl",  -- "crawl", "challenge", "camp", "town"

    -- Active PC tracking (for inventory, POI interaction, Tests of Fate)
    activePCIndex     = 1,

    -- Victory condition tracking
    vellumMapFound    = false,
}

-- Combat input state (for multi-step selection flow)
-- Shared between challenge_input_controller and Challenge overlay rendering.
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

--------------------------------------------------------------------------------
-- ACTIVE PC MANAGEMENT
--------------------------------------------------------------------------------

--- Get the currently active PC
function getActivePC()
    if gameState.activePCIndex and gameState.guild[gameState.activePCIndex] then
        return gameState.guild[gameState.activePCIndex]
    end
    return gameState.guild[1]
end

--- Set the active PC by index
function setActivePC(index)
    if index >= 1 and index <= #gameState.guild then
        local previousIndex = gameState.activePCIndex
        gameState.activePCIndex = index

        -- Emit event for UI components to sync
        gameState.eventBus:emit(events.EVENTS.ACTIVE_PC_CHANGED, {
            previousIndex = previousIndex,
            newIndex = index,
            pc = gameState.guild[index],
        })
    end
end

--- Cycle to the next active PC
function cycleActivePC()
    local newIndex = (gameState.activePCIndex % #gameState.guild) + 1
    setActivePC(newIndex)
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

function love.load()
    app_bootstrap.initialize({
        gameState = gameState,
        combatInputState = combatInputState,
        callbacks = {
            createGuild = createGuild,
            checkVictoryCondition = checkVictoryCondition,
            handlePhaseChange = handlePhaseChange,
            triggerRandomEncounter = triggerRandomEncounter,
            showEndOfDemoScreen = showEndOfDemoScreen,
        },
    })
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

-- Weapon definitions for proper inventory items
local WEAPON_DATA = {
    Sword   = { weaponType = "sword",   isWeapon = true, isMelee = true },
    Dagger  = { weaponType = "dagger",  isWeapon = true, isMelee = true },
    Staff   = { weaponType = "staff",   isWeapon = true, isMelee = true },
    Bow     = { weaponType = "bow",     isWeapon = true, isRanged = true, uses_ammo = true },
    Crossbow = { weaponType = "crossbow", isWeapon = true, isRanged = true, uses_ammo = true },
    Axe     = { weaponType = "axe",     isWeapon = true, isMelee = true },
    Mace    = { weaponType = "mace",    isWeapon = true, isMelee = true },
    Spear   = { weaponType = "spear",   isWeapon = true, isMelee = true },
}

--- Give starting items to an adventurer
function giveStartingItems(entity, itemNames)
    entity.inventory = inventory.createInventory()

    for _, itemName in ipairs(itemNames) do
        local item = inventory.createItem({
            name = itemName,
            size = inventory.SIZE.NORMAL,
        })

        -- Check if this is a weapon and add proper flags
        local weaponData = WEAPON_DATA[itemName]
        if weaponData then
            item.isWeapon = weaponData.isWeapon
            item.isMelee = weaponData.isMelee
            item.isRanged = weaponData.isRanged
            item.weaponType = weaponData.weaponType
            item.uses_ammo = weaponData.uses_ammo
            -- Weapons go in hands
            entity.inventory:addItem(item, inventory.LOCATIONS.HANDS)
        else
            -- Special handling for light sources
            if itemName == "Torch" then
                item.properties = {
                    flicker_count = 3,
                    light_source = true,
                    isLit = true,                -- Starts lit
                    requires_hands = true,       -- Must be in hands to provide light
                    provides_belt_light = false, -- Does NOT work from belt
                    fragile_on_belt = false,
                }
            elseif itemName == "Lantern" then
                item.properties = {
                    flicker_count = 6,
                    light_source = true,
                    isLit = true,                -- Starts lit
                    requires_hands = false,      -- Works from hands OR belt
                    provides_belt_light = true,  -- Works from belt
                    fragile_on_belt = true,      -- Breaks when taking wound while on belt
                }
            end
            -- Non-weapons go to belt for quick access
            entity.inventory:addItem(item, inventory.LOCATIONS.BELT)
        end
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
                    properties = {
                        flicker_count = 3,
                        light_source = true,
                        isLit = true,
                        requires_hands = true,
                        provides_belt_light = false,
                        fragile_on_belt = false,
                    },
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
        layoutManager = gameState.layoutManager,
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
            layoutManager = gameState.layoutManager,
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

    -- S13.4: Use room's zones if available (with descriptions), otherwise fallback to defaults
    local zones
    if roomData and roomData.zones and #roomData.zones > 0 then
        zones = roomData.zones
    else
        -- Fallback default zones
        zones = {
            { id = "near", name = "Near Side", description = "Closer to the entrance." },
            { id = "center", name = "Center", description = "The middle of the room." },
            { id = "far", name = "Far Side", description = "The far end of the room." },
        }
    end

    -- Create enemy based on meatgrinder value and room context
    -- Higher card values = tougher enemies
    local enemyCount = 1
    if data.value >= 19 then
        enemyCount = 2  -- Tougher encounter
    end

    -- Select enemy blueprint based on danger level
    local blueprintId = "skeleton_brute"  -- Default
    if dangerLevel >= 4 then
        blueprintId = "brain_spider"
    elseif dangerLevel >= 3 then
        blueprintId = "puppet_mummy"
    elseif dangerLevel >= 2 then
        blueprintId = "skeleton_brute"
    else
        blueprintId = "goblin_minion"
    end

    local enemies = {}
    for i = 1, enemyCount do
        -- Use factory to create proper entity with HD system
        local enemy = factory.createEntity(blueprintId, {
            name = "Tomb Guardian",  -- Override name for flavor
        })

        if enemy then
            enemy.id = "encounter_enemy_" .. i
            enemy.rank = "soldier"
            enemy.zone = zones[#zones].id  -- Enemies start in far zone
            -- Give enemy inventory with weapon in hands
            enemy.inventory = inventory.createInventory()
            local weapon = inventory.createItem({
                name = "Rusty Blade",
                isWeapon = true,
                isMelee = true,
                weaponType = "sword",
            })
            enemy.inventory:addItem(weapon, inventory.LOCATIONS.HANDS)
            enemies[#enemies + 1] = enemy
        end
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
    local roomData = gameState.roomManager:getRoom(currentRoom)

    -- S13.4: Use room's zones if available (with descriptions), otherwise fallback to defaults
    local zones
    if roomData and roomData.zones and #roomData.zones > 0 then
        zones = roomData.zones
    else
        -- Default zones for combat
        zones = {
            { id = "near", name = "Near Side", description = "Closer to the entrance." },
            { id = "center", name = "Center", description = "The middle of the room." },
            { id = "far", name = "Far Side", description = "The far end of the room." },
        }
    end

    -- Create a test enemy using the factory (proper HD system)
    local testEnemy = factory.createEntity("skeleton_brute", {
        name = "Skeleton Warrior",  -- Override name
    })

    if testEnemy then
        testEnemy.id = "test_skeleton_1"
        testEnemy.rank = "soldier"
        testEnemy.zone = zones[#zones].id  -- Put enemy in the last zone (far end)
        -- Give enemy inventory with weapon in hands
        testEnemy.inventory = inventory.createInventory()
        local weapon = inventory.createItem({
            name = "Rusty Sword",
            isWeapon = true,
            isMelee = true,
            weaponType = "sword",
        })
        testEnemy.inventory:addItem(weapon, inventory.LOCATIONS.HANDS)
    else
        -- Fallback if factory fails
        print("[COMBAT] Warning: Failed to create enemy from factory, using fallback")
        testEnemy = {
            id = "test_skeleton_1",
            name = "Skeleton Warrior",
            isPC = false,
            rank = "soldier",
            zone = zones[#zones].id,
            swords = 2, pentacles = 1, cups = 0, wands = 1,
            npcHealth = 3, npcDefense = 0, npcMaxHealth = 3, npcMaxDefense = 0,
            instantDestruction = true,
            conditions = {},
            baseMorale = 20,
        }
        -- Give fallback enemy inventory too
        testEnemy.inventory = inventory.createInventory()
        local weapon = inventory.createItem({
            name = "Rusty Sword",
            isWeapon = true,
            isMelee = true,
            weaponType = "sword",
        })
        testEnemy.inventory:addItem(weapon, inventory.LOCATIONS.HANDS)
    end

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

-- Challenge input flow lives in controllers/challenge_input_controller.lua.
-- main.lua now delegates keyboard/mouse handling to gameState.challengeInputController.

--------------------------------------------------------------------------------
-- LÖVE 2D CALLBACKS
--------------------------------------------------------------------------------

function love.update(dt)
    if gameState.currentScreen then
        gameState.currentScreen:update(dt)
    end
    if gameState.layoutManager then
        gameState.layoutManager:update(dt)
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
        if gameState.challengeOverlay then
            gameState.challengeOverlay:draw()
        end
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

    -- S12.5: Draw Test of Fate modal (on top of everything except debug)
    if gameState.testOfFateModal then
        gameState.testOfFateModal:draw()
    end

    -- Draw debug info
    love.graphics.setColor(1, 1, 1, 0.5)
    local challengeInfo = ""
    if gameState.challengeController and gameState.challengeController:isActive() then
        challengeInfo = string.format(" | COMBAT Turn %d/%d",
            gameState.challengeController:getCurrentTurn(),
            gameState.challengeController:getMaxTurns())
    end

    -- Get active PC's light level
    local activePC = getActivePC()
    local activePCName = activePC and activePC.name or "?"
    local activePCLight = "?"
    if activePC and gameState.lightSystem then
        activePCLight = gameState.lightSystem:getEntityLightLevel(activePC) or "?"
    end

    love.graphics.print(
        string.format("Watch: %d | %s: %s | FPS: %d%s",
            gameState.watchManager:getWatchCount(),
            activePCName,
            activePCLight,
            love.timer.getFPS(),
            challengeInfo),
        10,
        love.graphics.getHeight() - 20
    )
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
    if gameState.layoutManager then
        gameState.layoutManager:resize(w, h)
    end
end

function love.mousepressed(x, y, button)
    if gameState.mouseInputRouter then
        gameState.mouseInputRouter:mousepressed(x, y, button)
    end
end

function love.mousereleased(x, y, button)
    if gameState.mouseInputRouter then
        gameState.mouseInputRouter:mousereleased(x, y, button)
    end
end

function love.mousemoved(x, y, dx, dy)
    if gameState.mouseInputRouter then
        gameState.mouseInputRouter:mousemoved(x, y, dx, dy)
    end
end

function love.keypressed(key)
    if gameState.keyInputRouter then
        gameState.keyInputRouter:keypressed(key)
    end
end
