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
local equipment_bar = require('ui.equipment_bar')

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
        equipmentBar    = nil,  -- Hands + Belt item display with drag-to-use

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

        -- Create equipment bar (hands + belt, positioned in calculateLayout)
        self.equipmentBar = equipment_bar.createEquipmentBar({
            eventBus = self.eventBus,
            inputManager = self.inputManager,
            guild = self.guild,
        })
        self.equipmentBar:init()

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

        -- Item used on POI -> handle interaction (keys on doors, poles on traps, etc.)
        self.eventBus:on(events.EVENTS.USE_ITEM_ON_POI, function(data)
            self:handleItemOnPOI(data)
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

            -- Handle locked door - require dragging a key to unlock
            if result.error == "connection_locked" then
                local connection = self.watchManager.dungeon:getConnection(self.currentRoomId, targetRoomId)

                local msg = "The passage is locked."
                if connection and connection.description then
                    msg = connection.description
                end

                -- Show locked message with drag hint
                if self.narrativeView then
                    local currentText = self.narrativeView.rawText or ""
                    local newText = currentText .. "\n\n--- LOCKED ---\n" .. msg ..
                        "\n\n(Drag a key from your hands or belt onto this exit to unlock it.)"
                    self.narrativeView:setText(newText, true)
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

        -- Position equipment bar at bottom of center area
        if self.equipmentBar then
            self.equipmentBar.x = self.centerX + padding
            self.equipmentBar.y = self.height - 80
            self.equipmentBar:calculateLayout()
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
        if self.equipmentBar then
            self.equipmentBar.guild = self.guild
        end
    end

    --- Create character plate components for each guild member (S5.1)
    function screen:createCharacterPlates()
        self.characterPlates = {}

        local y = M.LAYOUT.HEADER_HEIGHT + M.LAYOUT.PADDING
        local plateWidth = self.leftRailWidth - (M.LAYOUT.PADDING * 2)

        -- Get active PC index from gameState (global)
        local activePCIndex = 1
        if gameState and gameState.activePCIndex then
            activePCIndex = gameState.activePCIndex
        end

        for i, adventurer in ipairs(self.guild) do
            local plate = character_plate.createCharacterPlate({
                eventBus = self.eventBus,
                entity = adventurer,
                x = self.leftRailX + M.LAYOUT.PADDING,
                y = y,
                width = plateWidth,
                isActive = (i == activePCIndex),
            })
            plate:init()

            self.characterPlates[#self.characterPlates + 1] = plate

            -- Advance y by plate height
            y = y + plate:getHeight() + M.LAYOUT.PADDING
        end

        -- Subscribe to active PC changes
        self.eventBus:on(events.EVENTS.ACTIVE_PC_CHANGED, function(data)
            self:updateActivePlate(data.newIndex)
        end)
    end

    --- Update which plate shows as active
    function screen:updateActivePlate(newIndex)
        for i, plate in ipairs(self.characterPlates) do
            plate:setActive(i == newIndex)
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
            local targetId = data.target.id
            if targetId and targetId:sub(1, 5) == "exit_" then
                local targetRoomId = targetId:sub(6)
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

    --- Handle dragging an item onto a POI
    -- @param data table: { item, itemLocation, poiId, poi, user }
    function screen:handleItemOnPOI(data)
        local item = data.item
        local poiId = data.poiId
        local user = data.user

        if not item or not poiId then return end

        print("[USE ITEM] " .. (user and user.name or "Someone") .. " uses " ..
              (item.name or "item") .. " on " .. poiId)

        -- Check if target is an exit (for key-door interactions)
        if poiId:sub(1, 5) == "exit_" then
            local targetRoomId = poiId:sub(6)
            self:handleKeyOnLockedExit(item, targetRoomId)
            return
        end

        -- Check if target is a room feature
        local feature = self.roomManager:getFeature(self.currentRoomId, poiId)
        if feature then
            -- Handle different item types on features
            local isKey = item.keyId or (item.properties and item.properties.key)
            local isPole = item.properties and item.properties.toolType == "pole"
            local isRope = item.properties and item.properties.toolType == "rope"

            if isKey then
                -- Using a key on a non-door feature
                if self.narrativeView then
                    local currentText = self.narrativeView.rawText or ""
                    local newText = currentText .. "\n\nThe " .. (item.name or "key") ..
                        " doesn't seem to have a lock to fit."
                    self.narrativeView:setText(newText, true)
                end
            elseif isPole then
                -- Using a pole to check for traps
                if feature.trap then
                    if self.narrativeView then
                        local currentText = self.narrativeView.rawText or ""
                        local newText = currentText .. "\n\n" .. (user and user.name or "You") ..
                            " carefully prods the " .. (feature.name or "feature") ..
                            " with the pole. You sense something dangerous - a trap!"
                        self.narrativeView:setText(newText, true)
                    end
                else
                    if self.narrativeView then
                        local currentText = self.narrativeView.rawText or ""
                        local newText = currentText .. "\n\n" .. (user and user.name or "You") ..
                            " prods the " .. (feature.name or "feature") ..
                            " cautiously. It seems safe."
                        self.narrativeView:setText(newText, true)
                    end
                end
            elseif isRope then
                -- Using rope on a feature
                if self.narrativeView then
                    local currentText = self.narrativeView.rawText or ""
                    local newText = currentText .. "\n\n" .. (user and user.name or "You") ..
                        " consider how to use the rope with the " .. (feature.name or "feature") .. "..."
                    self.narrativeView:setText(newText, true)
                end
            else
                -- Generic item use
                if self.narrativeView then
                    local currentText = self.narrativeView.rawText or ""
                    local newText = currentText .. "\n\nYou're not sure how to use the " ..
                        (item.name or "item") .. " on the " .. (feature.name or "feature") .. "."
                    self.narrativeView:setText(newText, true)
                end
            end
            return
        end

        -- Unknown target
        if self.narrativeView then
            local currentText = self.narrativeView.rawText or ""
            local newText = currentText .. "\n\nNothing happens."
            self.narrativeView:setText(newText, true)
        end
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
        if self.equipmentBar then
            self.equipmentBar:update(dt)
        end
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    ----------------------------------------------------------------------------

    --- Draw the screen
    function screen:draw()
        if not love then return end

        -- S13.2: Determine current layout stage based on game phase
        local currentPhase = self.gameState and self.gameState.phase or "crawl"
        local isChallenge = (currentPhase == "challenge")

        -- Background
        love.graphics.setColor(self.colors.background)
        love.graphics.rectangle("fill", 0, 0, self.width, self.height)

        -- Draw three columns
        self:drawLeftRail()
        self:drawCenter(isChallenge)
        self:drawRightRail()

        -- S13.2: During Challenge, show only minimal room context instead of full narrative
        if isChallenge then
            -- Draw collapsed room header only
            self:drawChallengeRoomContext()
        else
            -- Draw full narrative view during Crawl
            if self.narrativeView then
                self.narrativeView:draw()
            end
        end

        -- Draw focus menu (on top)
        if self.focusMenu then
            self.focusMenu:draw()
        end

        -- S10.3: Draw belt hotbar
        if self.equipmentBar then
            self.equipmentBar:draw()
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
    -- S13.2: Accept isChallenge flag to adjust header
    function screen:drawCenter(isChallenge)
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

        -- S13.2: Header changes based on phase
        love.graphics.setColor(self.colors.text_dark)
        if isChallenge then
            -- During challenge, arena is drawn on top, so just leave space
            -- Header will be drawn by challenge overlay
        else
            love.graphics.printf("THE UNDERWORLD", self.centerX, 10, self.centerWidth, "center")
        end
    end

    --- S13.2: Draw minimal room context during Challenge phase
    -- Shows room name in a collapsed bar that doesn't overlap with arena
    function screen:drawChallengeRoomContext()
        if not self.currentRoomId then return end

        local roomData = self.roomManager and self.roomManager:getRoom(self.currentRoomId)
        if not roomData then return end

        -- Draw a small context bar at the bottom of the center area
        local barHeight = 32
        local barY = self.height - barHeight - 80  -- Above equipment bar area
        local barX = self.centerX + 10
        local barWidth = self.centerWidth - 20

        -- Background
        love.graphics.setColor(0.1, 0.08, 0.06, 0.85)
        love.graphics.rectangle("fill", barX, barY, barWidth, barHeight, 4, 4)

        -- Border
        love.graphics.setColor(0.4, 0.35, 0.3, 1)
        love.graphics.rectangle("line", barX, barY, barWidth, barHeight, 4, 4)

        -- Room name
        love.graphics.setColor(0.9, 0.85, 0.75, 1)
        local roomName = roomData.name or self.currentRoomId
        love.graphics.printf(roomName, barX + 10, barY + 8, barWidth - 20, "center")
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
        -- S13.6: State-based action gating
        local campBtnW = self.rightRailWidth - 20
        local campBtnH = 40
        local campBtnX = self.rightRailX + 10
        local campBtnY = self.height - campBtnH - 60

        -- Store button bounds for click detection
        self.campButtonBounds = { x = campBtnX, y = campBtnY, w = campBtnW, h = campBtnH }

        -- S13.6: Check if camping is allowed (only during crawl phase)
        local canCamp = self.gameState and self.gameState.phase == "crawl"
        local disabledReason = nil
        if not canCamp then
            if self.gameState and self.gameState.phase == "challenge" then
                disabledReason = "Cannot camp during combat"
            elseif self.gameState and self.gameState.phase == "camp" then
                disabledReason = "Already camping"
            else
                disabledReason = "Cannot camp now"
            end
        end

        -- Check if hovering
        local mouseX, mouseY = love.mouse.getPosition()
        local isHovered = mouseX >= campBtnX and mouseX < campBtnX + campBtnW and
                          mouseY >= campBtnY and mouseY < campBtnY + campBtnH

        -- Button background (greyed out if disabled)
        if not canCamp then
            love.graphics.setColor(0.2, 0.2, 0.2, 0.6)  -- Disabled grey
        elseif isHovered then
            love.graphics.setColor(0.35, 0.3, 0.25, 1)
        else
            love.graphics.setColor(0.25, 0.22, 0.18, 1)
        end
        love.graphics.rectangle("fill", campBtnX, campBtnY, campBtnW, campBtnH, 4, 4)

        -- Button border
        if not canCamp then
            love.graphics.setColor(0.3, 0.3, 0.3, 0.6)  -- Disabled border
        else
            love.graphics.setColor(0.5, 0.4, 0.3, 1)
        end
        love.graphics.rectangle("line", campBtnX, campBtnY, campBtnW, campBtnH, 4, 4)

        -- Button text
        if not canCamp then
            love.graphics.setColor(0.5, 0.5, 0.5, 0.8)  -- Disabled text
        else
            love.graphics.setColor(self.colors.header_text)
        end
        love.graphics.printf("Make Camp", campBtnX, campBtnY + 12, campBtnW, "center")

        -- S13.6: Tooltip for disabled state
        if isHovered and not canCamp and disabledReason then
            local tooltipW = 160
            local tooltipH = 24
            local tooltipX = campBtnX + (campBtnW - tooltipW) / 2
            local tooltipY = campBtnY - tooltipH - 4

            -- Tooltip background
            love.graphics.setColor(0.1, 0.1, 0.1, 0.9)
            love.graphics.rectangle("fill", tooltipX, tooltipY, tooltipW, tooltipH, 3, 3)
            love.graphics.setColor(0.6, 0.3, 0.3, 1)
            love.graphics.rectangle("line", tooltipX, tooltipY, tooltipW, tooltipH, 3, 3)

            -- Tooltip text
            love.graphics.setColor(0.9, 0.6, 0.6, 1)
            love.graphics.printf(disabledReason, tooltipX, tooltipY + 5, tooltipW, "center")
        end
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
        if self.equipmentBar and self.equipmentBar:mousepressed(x, y, button) then
            return
        end

        -- S11.4: Camp button click handling
        -- S13.6: Only allow during crawl phase
        if button == 1 and self.campButtonBounds then
            local btn = self.campButtonBounds
            if x >= btn.x and x < btn.x + btn.w and
               y >= btn.y and y < btn.y + btn.h then
                -- S13.6: Validate phase before triggering
                if self.gameState and self.gameState.phase == "crawl" then
                    self.eventBus:emit(events.EVENTS.PHASE_CHANGED, {
                        oldPhase = "crawl",
                        newPhase = "camp",
                    })
                end
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

        -- Equipment bar drag release
        if self.equipmentBar and self.equipmentBar:mousereleased(x, y, button) then
            return
        end

        self.inputManager:mousereleased(x, y, button)
    end

    function screen:mousemoved(x, y, dx, dy)
        if self.focusMenu and self.focusMenu.isOpen then
            self.focusMenu:onMouseMoved(x, y)
        end

        -- Equipment bar drag tracking
        if self.equipmentBar then
            self.equipmentBar:mousemoved(x, y, dx, dy)
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

        -- S10.3: Belt hotbar keyboard shortcuts (1-4 for items, ` to cycle PC)
        -- Note: Only active in crawl phase when character sheet is closed
        if self.equipmentBar then
            self.equipmentBar:keypressed(key)
        end
    end

    return screen
end

return M
