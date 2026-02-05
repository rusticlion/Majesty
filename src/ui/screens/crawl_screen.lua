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
local interaction = require('logic.interaction')
local item_interaction = require('logic.item_interaction')
local resolver = require('logic.resolver')
local constants = require('constants')

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

local function formatLightLevel(level)
    if level == "bright" then
        return "BRIGHT"
    elseif level == "dim" then
        return "DIM"
    elseif level == "dark" then
        return "DARK"
    end
    return "UNKNOWN"
end

local function getLightLevelColor(level)
    if level == "bright" then
        return 0.75, 0.9, 0.45, 1
    elseif level == "dim" then
        return 0.95, 0.8, 0.35, 1
    else
        return 0.95, 0.45, 0.4, 1
    end
end

local function getNowSeconds()
    if love and love.timer and love.timer.getTime then
        return love.timer.getTime()
    end
    return os.clock()
end

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
        layoutManager = config.layoutManager,

        -- UI Components (created in init)
        inputManager  = nil,
        narrativeView = nil,
        focusMenu     = nil,
        equipmentBar    = nil,  -- Hands + Belt item display with drag-to-use
        roomContextPanel = nil, -- S13.2: Slim room context panel during challenges

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
        currentRoomDescription = nil,
        pendingTestOfFate = nil,
        testHistoryDrawer = {
            isExpanded = false,
            collapsedHeight = 28,
            expandedHeight = 180,
            headerHeight = 28,
            padding = 8,
            lineHeight = 18,
            entries = {},
            maxEntries = 50,
        },
        lightNarrative = {
            pendingToggle = nil,
            combineWindow = 0.25,
        },

        -- Textures (loaded in init)
        vellumTexture = nil,

        -- Colors
        colors = config.colors or M.COLORS,
    }

    local function describeEntity(entity)
        return (entity and entity.name) or "Someone"
    end

    local function describeItem(item)
        return (item and item.name) or "light source"
    end

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

        -- Create interaction systems
        self.interactionSystem = interaction.createInteractionSystem({
            eventBus = self.eventBus,
            roomManager = self.roomManager,
        })

        self.itemInteractionSystem = item_interaction.createItemInteractionSystem({
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
            interactionSystem = self.interactionSystem,
        })

        -- Create equipment bar (hands + belt, positioned in calculateLayout)
        self.equipmentBar = equipment_bar.createEquipmentBar({
            eventBus = self.eventBus,
            inputManager = self.inputManager,
            guild = self.guild,
        })
        self.equipmentBar:init()

        -- S13.2: Slim room context panel for challenge phase
        self.roomContextPanel = {
            x = 0,
            y = 0,
            width = 0,
            height = 0,
            alpha = 0,
            isVisible = false,
            padding = 12,
        }

        -- Register layout-managed elements
        if self.layoutManager then
            self:registerLayoutElements()
        end

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

        -- POI action selected -> resolve interaction
        self.eventBus:on(events.EVENTS.POI_ACTION_SELECTED, function(data)
            self:handlePoiActionSelected(data)
        end)

        -- Bound by Fate note (disabled actions)
        self.eventBus:on(events.EVENTS.BOUND_BY_FATE_BLOCKED, function()
            self:notifyBoundByFate()
        end)

        -- Test of Fate result -> resolve pending crawl investigations
        self.eventBus:on(events.EVENTS.TEST_OF_FATE_COMPLETE, function(data)
            self:handleTestOfFateComplete(data)
        end)

        -- Item used on POI -> handle interaction (keys on doors, poles on traps, etc.)
        self.eventBus:on(events.EVENTS.USE_ITEM_ON_POI, function(data)
            self:handleItemOnPOI(data)
        end)

        -- Light-system narrative hooks
        self.eventBus:on(events.EVENTS.LIGHT_SOURCE_TOGGLED, function(data)
            self:handleLightSourceToggled(data)
        end)
        self.eventBus:on(events.EVENTS.LIGHT_FLICKERED, function(data)
            self:handleLightFlickered(data)
        end)
        self.eventBus:on(events.EVENTS.LIGHT_DESTROYED, function(data)
            self:handleLightDestroyed(data)
        end)
        self.eventBus:on(events.EVENTS.LIGHT_EXTINGUISHED, function(data)
            self:handleLightExtinguished(data)
        end)
        self.eventBus:on(events.EVENTS.LANTERN_BROKEN, function(data)
            self:handleLanternBroken(data)
        end)
        self.eventBus:on(events.EVENTS.PARTY_LIGHT_CHANGED, function(data)
            self:handlePartyLightChanged(data)
        end)
        self.eventBus:on(events.EVENTS.DARKNESS_FELL, function(data)
            self:handleDarknessFell(data)
        end)
        self.eventBus:on(events.EVENTS.DARKNESS_LIFTED, function(data)
            self:handleDarknessLifted(data)
        end)
    end

    --- Register UI elements with the layout manager
    function screen:registerLayoutElements()
        if not self.layoutManager then return end

        self.layoutManager:register("narrative_view", self.narrativeView, {
            apply = function(view, layout)
                if layout.x and layout.y then
                    if view.x ~= layout.x or view.y ~= layout.y then
                        view:setPosition(layout.x, layout.y)
                    end
                end
                if layout.width and layout.height then
                    if view.width ~= layout.width or view.height ~= layout.height then
                        view:resize(layout.width, layout.height)
                    end
                end
                view.alpha = layout.alpha or 1
                if view.setVisible then
                    view:setVisible(layout.visible)
                else
                    view.isVisible = layout.visible
                end
            end,
        })

        self.layoutManager:register("equipment_bar", self.equipmentBar, {
            apply = function(bar, layout)
                if layout.x and layout.y then
                    if bar.x ~= layout.x or bar.y ~= layout.y then
                        bar.x = layout.x
                        bar.y = layout.y
                        bar:calculateLayout()
                    end
                end
                bar.alpha = layout.alpha or 1
                bar.isVisible = layout.visible
            end,
        })

        self.layoutManager:register("room_context_panel", self.roomContextPanel, {
            apply = function(panel, layout)
                if layout.x then panel.x = layout.x end
                if layout.y then panel.y = layout.y end
                if layout.width then panel.width = layout.width end
                if layout.height then panel.height = layout.height end
                panel.alpha = layout.alpha or 1
                panel.isVisible = layout.visible
            end,
        })
    end

    --- Handle scrutiny result and display it
    function screen:handleScrutinyResult(data)
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

    --- Get the currently active PC for crawl interactions
    function screen:getActivePC()
        if self.gameState and self.gameState.activePCIndex and self.gameState.guild then
            return self.gameState.guild[self.gameState.activePCIndex] or self.gameState.guild[1]
        end
        return self.guild and self.guild[1] or nil
    end

    --- Append a labeled block to the narrative view
    function screen:appendNarrativeBlock(title, text)
        if not self.narrativeView then return end
        local currentText = self.narrativeView.rawText or ""
        local newText = currentText .. "\n\n--- " .. title .. " ---\n" .. text
        self.narrativeView:setText(newText, true)
    end

    --- Notify that a Test of Fate result stands (Bound by Fate)
    function screen:notifyBoundByFate()
        self:appendNarrativeBlock("BOUND BY FATE", "The result stands unless circumstances change (a different tool or a changed situation).")
    end

    --- Only append automatic system logs while this crawl screen is active.
    function screen:canAppendSystemNarrative()
        if not self.narrativeView then
            return false
        end
        if self.gameState and self.gameState.currentScreen and self.gameState.currentScreen ~= self then
            return false
        end
        return true
    end

    function screen:buildLightToggleMessage(data)
        local actor = describeEntity(data and data.entity)
        local itemName = describeItem(data and data.item)
        if data and data.lit then
            return string.format("%s lights %s.", actor, itemName)
        end
        return string.format("%s extinguishes %s.", actor, itemName)
    end

    function screen:buildPartyLightShiftMessage(data)
        local current = formatLightLevel(data and data.current)
        local previous = formatLightLevel(data and data.previous)
        if current == previous then
            return nil
        end

        local sources = data and data.sources
        local sourceSuffix = ""
        if type(sources) == "number" then
            sourceSuffix = string.format(" (%d active source%s)", sources, sources == 1 and "" or "s")
        end

        return string.format("Party light shifts from %s to %s%s.", previous, current, sourceSuffix)
    end

    function screen:flushPendingLightNarrative(force)
        if not self:canAppendSystemNarrative() then
            return
        end

        local tracker = self.lightNarrative
        local pending = tracker and tracker.pendingToggle
        if not pending then
            return
        end

        local now = getNowSeconds()
        local window = tracker.combineWindow or 0.25
        if not force and (now - pending.timestamp) < window then
            return
        end

        self:appendNarrativeBlock("LIGHT", self:buildLightToggleMessage(pending))
        tracker.pendingToggle = nil
    end

    function screen:handleLightSourceToggled(data)
        if not self:canAppendSystemNarrative() then return end
        if not self.lightNarrative then
            self.lightNarrative = { pendingToggle = nil, combineWindow = 0.25 }
        end
        self.lightNarrative.pendingToggle = {
            entity = data and data.entity,
            item = data and data.item,
            lit = data and data.lit,
            timestamp = getNowSeconds(),
        }
    end

    function screen:handleLightFlickered(data)
        if not self:canAppendSystemNarrative() then return end
        local remaining = (data and data.remaining) or 0
        -- Extinguish/destroy logs carry the terminal event; suppress duplicate flicker->0 lines.
        if remaining <= 0 then
            return
        end
        local actor = describeEntity(data and data.entity)
        local itemName = describeItem(data and data.item)
        local cardSuffix = ""
        if data and data.cardValue then
            cardSuffix = " (Meatgrinder " .. tostring(data.cardValue) .. ")"
        end
        local message = string.format("%s's %s flickers%s. %d remaining.", actor, itemName, cardSuffix, remaining)
        self:appendNarrativeBlock("LIGHT", message)
    end

    function screen:handleLightDestroyed(data)
        if not self:canAppendSystemNarrative() then return end
        local actor = describeEntity(data and data.entity)
        local itemName = describeItem(data and data.item)
        self:appendNarrativeBlock("LIGHT", string.format("%s's %s gutters out and is spent.", actor, itemName))
    end

    function screen:handleLightExtinguished(data)
        if not self:canAppendSystemNarrative() then return end
        local actor = describeEntity(data and data.entity)
        local itemName = describeItem(data and data.item)
        self:appendNarrativeBlock("LIGHT", string.format("%s's %s goes dark and needs fuel.", actor, itemName))
    end

    function screen:handleLanternBroken(data)
        if not self:canAppendSystemNarrative() then return end
        local actor = describeEntity(data and data.entity)
        local itemName = describeItem(data and data.item)
        self:appendNarrativeBlock("LIGHT", string.format("%s's %s breaks.", actor, itemName))
    end

    function screen:handlePartyLightChanged(data)
        if not self:canAppendSystemNarrative() then return end
        local shiftMessage = self:buildPartyLightShiftMessage(data)
        if not shiftMessage then
            return
        end

        local tracker = self.lightNarrative
        local pending = tracker and tracker.pendingToggle
        local now = getNowSeconds()
        local window = (tracker and tracker.combineWindow) or 0.25
        if pending and (now - pending.timestamp) <= window then
            self:appendNarrativeBlock("LIGHT", self:buildLightToggleMessage(pending) .. " " .. shiftMessage)
            tracker.pendingToggle = nil
            return
        end

        self:appendNarrativeBlock("LIGHT", shiftMessage)
    end

    function screen:handleDarknessFell(data)
        if not self:canAppendSystemNarrative() then return end
        local affected = (data and data.affectedCount) or 0
        if affected == 1 then
            self:appendNarrativeBlock("DARKNESS", "Darkness falls. 1 adventurer is now blind.")
        else
            self:appendNarrativeBlock("DARKNESS", string.format("Darkness falls. %d adventurers are now blind.", affected))
        end
    end

    function screen:handleDarknessLifted(data)
        if not self:canAppendSystemNarrative() then return end
        local affected = (data and data.affectedCount) or 0
        self:appendNarrativeBlock("DARKNESS", string.format("Light returns. Blindness clears for %d adventurer%s.", affected, affected == 1 and "" or "s"))
    end

    local function formatTestResult(result)
        if not result then return "UNKNOWN" end
        if result.result == resolver.RESULTS.GREAT_SUCCESS then
            return "GREAT SUCCESS"
        elseif result.result == resolver.RESULTS.SUCCESS then
            return "SUCCESS"
        elseif result.result == resolver.RESULTS.GREAT_FAILURE then
            return "GREAT FAILURE"
        elseif result.result == resolver.RESULTS.FAILURE then
            return "FAILURE"
        end
        return "UNKNOWN"
    end

    local function formatFavor(favor)
        if favor == true then
            return "Favor"
        elseif favor == false then
            return "Disfavor"
        end
        return "Neutral"
    end

    local function formatCardList(cards)
        if not cards or #cards == 0 then return "No cards" end
        local parts = {}
        for _, card in ipairs(cards) do
            if card.name then
                parts[#parts + 1] = card.name
            elseif card.value then
                parts[#parts + 1] = tostring(card.value)
            end
        end
        return table.concat(parts, ", ")
    end

    --- Record a Test of Fate result in the drawer history
    function screen:recordTestHistory(data)
        if not data or not data.result then return end
        local drawer = self.testHistoryDrawer
        if not drawer then return end

        local config = data.config or {}
        local entity = data.entity
        local description = config.description or "Test of Fate"
        local attribute = config.attribute or "?"
        local favor = formatFavor(config.favor)
        local resultText = formatTestResult(data.result)
        local total = data.result.total or 0
        local cards = formatCardList(data.result.cards)
        local actorName = entity and entity.name or "Unknown"

        local summary = string.format("%s (%d) - %s", resultText, total, description)

        drawer.entries[#drawer.entries + 1] = {
            description = description,
            attribute = attribute,
            favor = favor,
            resultText = resultText,
            total = total,
            cards = cards,
            actorName = actorName,
            summary = summary,
        }

        if #drawer.entries > drawer.maxEntries then
            table.remove(drawer.entries, 1)
        end
    end

    --- Refresh the room description while preserving appended narrative
    function screen:refreshRoomDescription()
        if not self.narrativeView or not self.roomManager or not self.currentRoomId then return end

        local room = self.roomManager:getRoom(self.currentRoomId)
        if not room then return end

        local newDescription = self:buildRoomDescription(room)
        local existingText = self.narrativeView.rawText or ""
        local suffix = ""

        if self.currentRoomDescription and existingText:sub(1, #self.currentRoomDescription) == self.currentRoomDescription then
            suffix = existingText:sub(#self.currentRoomDescription + 1)
        else
            suffix = existingText
        end

        self.currentRoomDescription = newDescription
        self.narrativeView:setText(newDescription .. suffix, true)
    end

    --- Handle Test of Fate completion for crawl actions
    function screen:handleTestOfFateComplete(data)
        self:recordTestHistory(data)
        if not self.pendingTestOfFate then return end

        local pending = self.pendingTestOfFate
        self.pendingTestOfFate = nil

        if pending.kind == "poi_investigation" then
            if not self.roomManager or not pending.feature then return end
            if not data or not data.result then
                self:appendNarrativeBlock("TEST OF FATE", "No result was recorded.")
                return
            end

            local result = self.roomManager:conductInvestigation(
                pending.actor,
                pending.roomId or self.currentRoomId,
                pending.feature.id,
                nil,
                resolver,
                pending.item,
                { testResult = data and data.result or nil }
            )

            self:applyInvestigationOutcome(pending.feature, result)
            return
        end

        if pending.kind == "item_interaction" then
            if not self.roomManager or not pending.feature then return end
            if not data or not data.result then
                self:appendNarrativeBlock("TEST OF FATE", "No result was recorded.")
                return
            end

            local testResult = data.result
            local result = pending.baseResult or {}
            local interactionType = pending.interactionType
            local roomId = pending.roomId or self.currentRoomId

            if testResult.success then
                if interactionType == item_interaction.INTERACTION_TYPES.UNLOCK then
                    self.roomManager:setFeatureState(roomId, pending.feature.id, "unlocked")
                    result.description = "You pick the lock successfully."
                else
                    result.description = (pending.testConfig and pending.testConfig.success_desc) or "Your efforts succeed."
                end
            else
                result.description = (pending.testConfig and pending.testConfig.failure_desc) or "Your attempt fails."
            end

            -- Record Bound by Fate (result stands unless circumstances change)
            local testKey = pending.testKey or "item_interaction"
            self.roomManager:recordBoundByFate(roomId, pending.feature.id, testKey, {
                item = pending.item,
            }, testResult)

            if result.description then
                self:appendNarrativeBlock("ITEM", result.description)
            end
        end
    end

    --- Spend a watch and surface the time cost in the narrative
    function screen:spendWatch(reason)
        if not self.watchManager then return nil end
        local watchResult = self.watchManager:incrementWatch()
        local message = reason or "Time passes as you work."
        if watchResult and watchResult.watchNumber then
            message = message .. " (Watch " .. watchResult.watchNumber .. ")"
        end
        self:appendNarrativeBlock("TIME PASSES", message)
        return watchResult
    end

    --- Apply investigation results (narrative + rewards)
    function screen:applyInvestigationOutcome(feature, result)
        if result and result.description then
            self:appendNarrativeBlock("INVESTIGATE", result.description)
        end

        -- Open loot modal on successful investigation if loot is present
        if result and result.result and result.result.success then
            if feature.type == "container" or feature.type == "corpse" then
                self.roomManager:updateFeatureState(self.currentRoomId, feature.id, { state = "searched" })
            end
            if feature.loot and #feature.loot > 0 then
                if self.gameState and self.gameState.lootModal then
                    self.gameState.lootModal:open(feature, self.currentRoomId)
                end
            end

            -- Reveal any secret connections linked to this POI
            if feature.reveal_connection or feature.reveal_connections then
                self:revealFeatureConnections(feature)
            end
        end
    end

    --- Reveal connections linked to a feature (secret passages, etc.)
    function screen:revealFeatureConnections(feature)
        if not feature or not self.watchManager or not self.watchManager.dungeon then return end

        local reveal = feature.reveal_connections or feature.reveal_connection
        if not reveal then return end

        local connections = {}
        if type(reveal) == "string" then
            connections = { { to = reveal } }
        elseif type(reveal) == "table" and reveal[1] then
            connections = reveal
        elseif type(reveal) == "table" then
            connections = { reveal }
        end

        local dungeon = self.watchManager.dungeon
        local revealedAny = false

        for _, connInfo in ipairs(connections) do
            local fromId = connInfo.from or self.currentRoomId
            local toId = connInfo.to or connInfo.target or connInfo.roomId
            if toId then
                local conn = dungeon:getConnection(fromId, toId)
                if conn then
                    dungeon:discoverConnection(fromId, toId)
                    if not conn.is_one_way then
                        dungeon:discoverConnection(toId, fromId)
                    end
                    revealedAny = true
                end
            end
        end

        if revealedAny then
            self:refreshRoomDescription()
        end
    end

    --- Get a Bound by Fate key for item-based tests
    function screen:getItemTestKey(interactionType)
        if not interactionType then
            return "item_interaction"
        end
        return "item_" .. tostring(interactionType)
    end

    --- Resolve a POI investigation (Test of Fate) in the Crawl
    function screen:resolvePoiInvestigation(actor, feature, context)
        if not actor or not feature or not self.roomManager then return end

        if (feature.type == "container" or feature.type == "corpse") and
            (feature.state == "empty" or feature.state == "searched") then
            self:appendNarrativeBlock("INVESTIGATE", "You've already searched this.")
            return
        end

        local item = context and context.item or nil

        -- Auto-success with key item (if applicable)
        if item and feature.key_item_id then
            local itemKeyId = item.keyId or (item.properties and (item.properties.key_id or item.properties.keyId))
            if itemKeyId == feature.key_item_id or item.name == feature.key_item_id then
                local result = self.roomManager:conductInvestigation(
                    actor,
                    self.currentRoomId,
                    feature.id,
                    nil,
                    resolver,
                    item
                )
                self:applyInvestigationOutcome(feature, result)
                return result
            end
        end

        -- Ensure deck is available before opening the modal
        if not self.gameState or not self.gameState.playerDeck or self.gameState.playerDeck:totalCards() == 0 then
            self:appendNarrativeBlock("INVESTIGATE", "You cannot draw a card right now.")
            return
        end

        if self.pendingTestOfFate then
            self:appendNarrativeBlock("TEST OF FATE", "A Test of Fate is already underway.")
            return
        end

        local boundStatus = self.roomManager:getBoundByFateStatus(self.currentRoomId, feature.id, "investigate", {
            item = item,
        })
        if boundStatus and boundStatus.allowed == false then
            self:notifyBoundByFate()
            return
        end

        if context and context.watchCost then
            local verb = context.action or "investigate"
            self:spendWatch("You take time to " .. verb .. ".")
        end

        local testInfo = self.roomManager:computeInvestigationTest(actor, self.currentRoomId, feature.id, item)
        if not testInfo then
            self:appendNarrativeBlock("INVESTIGATE", "You cannot investigate that right now.")
            return
        end

        local title = "Investigate"
        if feature.name then
            title = "Investigate: " .. feature.name
        end

        self.pendingTestOfFate = {
            kind = "poi_investigation",
            actor = actor,
            feature = feature,
            roomId = self.currentRoomId,
            item = item,
        }

        self.eventBus:emit(events.EVENTS.REQUEST_TEST_OF_FATE, {
            entity = actor,
            attribute = testInfo.attribute,
            targetSuit = testInfo.suitId,
            favor = testInfo.favor,
            description = title,
        })
    end

    --- Resolve a simple Test of Fate for crawl interactions
    function screen:resolveSimpleTest(actor, attributeName, favor)
        if not self.gameState or not self.gameState.playerDeck then
            return nil
        end
        local card = self.gameState.playerDeck:draw()
        if not card then
            return nil
        end

        local suitId = constants.SUITS[string.upper(attributeName or "pentacles")] or constants.SUITS.PENTACLES
        local attributeValue = 0
        if actor and actor.getAttribute then
            attributeValue = actor:getAttribute(suitId)
        end

        local testResult = resolver.resolveTest(attributeValue, suitId, card, favor)
        self.gameState.playerDeck:discard(card)
        return testResult
    end

    --- Determine the most relevant item interaction for a POI
    function screen:selectItemInteraction(item, feature)
        if not self.itemInteractionSystem or not item or not feature then
            return nil
        end

        if feature.lock and self.itemInteractionSystem:canPerform(item, item_interaction.INTERACTION_TYPES.UNLOCK) then
            return item_interaction.INTERACTION_TYPES.UNLOCK
        end

        if (feature.trap or feature.type == "hazard") and
           self.itemInteractionSystem:canPerform(item, item_interaction.INTERACTION_TYPES.PROBE) then
            return item_interaction.INTERACTION_TYPES.PROBE
        end

        if feature.type == "mechanism" and
           self.itemInteractionSystem:canPerform(item, item_interaction.INTERACTION_TYPES.TRIGGER) then
            return item_interaction.INTERACTION_TYPES.TRIGGER
        end

        if feature.type == "light" and
           self.itemInteractionSystem:canPerform(item, item_interaction.INTERACTION_TYPES.LIGHT) then
            return item_interaction.INTERACTION_TYPES.LIGHT
        end

        if (feature.fragile or feature.breakable) and
           self.itemInteractionSystem:canPerform(item, item_interaction.INTERACTION_TYPES.BREAK) then
            return item_interaction.INTERACTION_TYPES.BREAK
        end

        local caps = self.itemInteractionSystem:getItemCapabilities(item)
        return caps and caps[1] or nil
    end

    --- Handle action selections from the POI menu
    function screen:handlePoiActionSelected(data)
        if not data or not data.poiId then return end
        local feature = self.roomManager and self.roomManager:getFeature(data.roomId, data.poiId)
        if not feature then return end

        local actor = self:getActivePC()

        if data.watchCost then
            self:spendWatch("You take time to " .. (data.action or "act") .. ".")
        end

        -- Map investigation-style actions to the Test of Fate flow
        if data.action == "investigate" or data.action == "search" or data.action == "trap_check" then
            self:resolvePoiInvestigation(actor, feature, {
                watchCost = data.watchCost,
                action = data.action,
            })
            return
        end

        -- Default interaction handling
        if data.watchCost then
            self:spendWatch("You take time to " .. (data.action or "act") .. ".")
        end

        if self.interactionSystem then
            local result = self.interactionSystem:interact(actor, feature, data.action, data.level, {
                roomId = self.currentRoomId,
                hasItem = function(keyId)
                    local item, _ = self:findMatchingKey(keyId)
                    return item ~= nil
                end,
            })

            if result and result.description then
                self:appendNarrativeBlock(string.upper(data.action or "ACT"), result.description)
            end
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

        if self.layoutManager then
            self.layoutManager:resize(self.width, self.height)
        else
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
        self.currentRoomDescription = description
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
                displayText = displayText .. " (Watch)"

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
            local targetId = data.target.id
            if targetId and targetId:sub(1, 5) == "exit_" then
                local targetRoomId = targetId:sub(6)
                self:handleExitClick(targetRoomId)
                return
            end

            self:handlePoiActionSelected({
                poiId = data.target.id,
                roomId = self.currentRoomId,
                action = "investigate",
                level = "investigate",
                watchCost = true,
            })
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
        if feature and self.itemInteractionSystem then
            local canUse, reason = self.itemInteractionSystem:canUseItemOnPOI(item, feature)
            if not canUse then
                self:appendNarrativeBlock("ITEM", "That doesn't seem to work here.")
                return
            end

            local interactionType = self:selectItemInteraction(item, feature)
            if not interactionType then
                self:appendNarrativeBlock("ITEM", "You're not sure how to use that here.")
                return
            end

            local result = self.itemInteractionSystem:useItemOnPOI(item, feature, interactionType, {
                roomId = self.currentRoomId,
                adventurer = user,
            })

            if result and result.requiresTest and result.testConfig then
                if self.pendingTestOfFate then
                    self:appendNarrativeBlock("TEST OF FATE", "A Test of Fate is already underway.")
                    return
                end

                local testKey = self:getItemTestKey(interactionType)
                local boundStatus = self.roomManager:getBoundByFateStatus(self.currentRoomId, feature.id, testKey, {
                    item = item,
                })
                if boundStatus and boundStatus.allowed == false then
                    self:notifyBoundByFate()
                    return
                end

                self:spendWatch("You take time to work with the " .. (item.name or "item") .. ".")

                local actor = user or self:getActivePC()
                local attribute = result.testConfig.attribute or "pentacles"
                local suitId = constants.SUITS[string.upper(attribute or "pentacles")] or constants.SUITS.PENTACLES
                local title = "Use " .. (item.name or "Item")
                if feature and feature.name then
                    title = title .. " on " .. feature.name
                end

                self.pendingTestOfFate = {
                    kind = "item_interaction",
                    actor = actor,
                    feature = feature,
                    roomId = self.currentRoomId,
                    item = item,
                    interactionType = interactionType,
                    testConfig = result.testConfig,
                    baseResult = result,
                    testKey = testKey,
                }

                self.eventBus:emit(events.EVENTS.REQUEST_TEST_OF_FATE, {
                    entity = actor,
                    attribute = attribute,
                    targetSuit = suitId,
                    favor = nil,
                    description = title,
                })

                return
            end

            if result and result.description then
                self:appendNarrativeBlock("ITEM", result.description)
            end

            return
        end

        self:appendNarrativeBlock("ITEM", "Nothing happens.")
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    --- Update the screen
    function screen:update(dt)
        self:flushPendingLightNarrative(false)

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

        -- Draw narrative view when visible
        if self.narrativeView and self.narrativeView.isVisible then
            self.narrativeView:draw()
            self:drawTestHistoryDrawer()
        end

        -- S13.2: Slim room context panel (challenge stage)
        self:drawRoomContextPanel()

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

    --- S13.2: Draw slim room context panel during Challenge phase
    function screen:drawRoomContextPanel()
        local panel = self.roomContextPanel
        if not panel or not panel.isVisible or (panel.alpha or 0) <= 0 then return end
        if not self.currentRoomId then return end

        local roomData = self.roomManager and self.roomManager:getRoom(self.currentRoomId)
        if not roomData then return end

        if (panel.width or 0) <= 0 or (panel.height or 0) <= 0 then
            return
        end

        local alpha = panel.alpha or 1
        local pad = panel.padding or 12
        local headerHeight = 24
        local x, y = panel.x, panel.y
        local w, h = panel.width, panel.height

        -- Background
        love.graphics.setColor(0.1, 0.08, 0.06, 0.92 * alpha)
        love.graphics.rectangle("fill", x, y, w, h, 6, 6)

        -- Border
        love.graphics.setColor(0.4, 0.35, 0.3, 1 * alpha)
        love.graphics.rectangle("line", x, y, w, h, 6, 6)

        -- Room name
        love.graphics.setColor(0.9, 0.85, 0.75, 1 * alpha)
        local roomName = roomData.name or self.currentRoomId
        love.graphics.print(roomName, x + pad, y + pad)

        -- Room description
        local description = roomData.base_description or roomData.description or ""
        local textX = x + pad
        local textY = y + pad + headerHeight
        local textW = w - (pad * 2)
        local textH = h - headerHeight - (pad * 2)
        if textW <= 0 or textH <= 0 then
            return
        end

        love.graphics.setColor(0.85, 0.8, 0.7, 0.9 * alpha)
        love.graphics.setScissor(textX, textY, textW, textH)
        love.graphics.printf(description, textX, textY, textW, "left")
        love.graphics.setScissor()
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
        local cardBottomY = M.LAYOUT.HEADER_HEIGHT + 120
        if self.dreadCard then
            local cardX = self.rightRailX + 20
            local cardY = M.LAYOUT.HEADER_HEIGHT + 20
            local cardW = self.rightRailWidth - 40
            local cardH = cardW * 1.4  -- Tarot proportions
            cardBottomY = cardY + cardH

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
        local watchY = cardBottomY + 16
        love.graphics.setColor(self.colors.header_text)
        love.graphics.printf("WATCH", self.rightRailX, watchY, self.rightRailWidth, "center")

        local watchCount = (self.watchManager and self.watchManager.getWatchCount and self.watchManager:getWatchCount()) or 0
        love.graphics.setColor(0.85, 0.8, 0.72, 1)
        love.graphics.printf("Current: " .. tostring(watchCount), self.rightRailX, watchY + 22, self.rightRailWidth, "center")

        love.graphics.setColor(self.colors.header_text)
        love.graphics.printf("LIGHT", self.rightRailX, watchY + 52, self.rightRailWidth, "center")

        local activePC = self:getActivePC()
        local lightSystem = self.gameState and self.gameState.lightSystem or nil
        local activeLight = lightSystem and activePC and lightSystem:getEntityLightLevel(activePC) or "dark"
        local partyLight = lightSystem and lightSystem:getLightLevel() or activeLight
        local totalFlickers = lightSystem and lightSystem:getTotalFlickers() or 0

        local lightR, lightG, lightB, lightA = getLightLevelColor(activeLight)
        love.graphics.setColor(lightR, lightG, lightB, lightA)
        love.graphics.printf(
            string.format("%s: %s", activePC and activePC.name or "Active", formatLightLevel(activeLight)),
            self.rightRailX + 12,
            watchY + 74,
            self.rightRailWidth - 24,
            "left"
        )

        local partyR, partyG, partyB, partyA = getLightLevelColor(partyLight)
        love.graphics.setColor(partyR, partyG, partyB, partyA)
        love.graphics.printf(
            "Party: " .. formatLightLevel(partyLight),
            self.rightRailX + 12,
            watchY + 94,
            self.rightRailWidth - 24,
            "left"
        )

        love.graphics.setColor(0.82, 0.78, 0.7, 1)
        love.graphics.printf(
            "Flickers: " .. tostring(totalFlickers),
            self.rightRailX + 12,
            watchY + 114,
            self.rightRailWidth - 24,
            "left"
        )

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

    --- Draw Test of Fate history drawer in the narrative panel
    function screen:drawTestHistoryDrawer()
        local view = self.narrativeView
        local drawer = self.testHistoryDrawer
        if not view or not drawer then return end
        if not view.isVisible or (view.alpha or 0) <= 0 then return end

        local x = view.x
        local w = view.width
        local height = drawer.isExpanded and drawer.expandedHeight or drawer.collapsedHeight
        local y = view.y + view.height - height
        local alpha = view.alpha or 1

        local pad = drawer.padding
        local headerH = drawer.headerHeight
        local lineH = drawer.lineHeight

        -- Background
        love.graphics.setColor(0.12, 0.11, 0.1, 0.95 * alpha)
        love.graphics.rectangle("fill", x, y, w, height, 6, 6)

        -- Border
        love.graphics.setColor(0.4, 0.35, 0.3, 0.9 * alpha)
        love.graphics.rectangle("line", x, y, w, height, 6, 6)

        -- Header
        love.graphics.setColor(0.9, 0.85, 0.75, 1 * alpha)
        local count = #drawer.entries
        local label = "Test History (" .. count .. ")"
        local toggleGlyph = drawer.isExpanded and "^" or "v"
        love.graphics.print(label .. " " .. toggleGlyph, x + pad, y + 6)

        if not drawer.isExpanded then
            local lastEntry = drawer.entries[#drawer.entries]
            if lastEntry and lastEntry.summary then
                love.graphics.setColor(0.8, 0.76, 0.68, 0.9 * alpha)
                love.graphics.printf(lastEntry.summary, x + pad + 140, y + 6, w - (pad * 2) - 140, "left")
            end
            return
        end

        -- Expanded entries
        local listX = x + pad
        local listY = y + headerH
        local listW = w - (pad * 2)
        local listH = height - headerH - pad
        if listW <= 0 or listH <= 0 then return end

        love.graphics.setScissor(listX, listY, listW, listH)
        local maxLines = math.floor(listH / lineH)
        local totalEntries = #drawer.entries
        local startIndex = math.max(1, totalEntries - maxLines + 1)
        local yCursor = listY

        for i = startIndex, totalEntries do
            local entry = drawer.entries[i]
            local attr = entry.attribute and entry.attribute:upper() or "?"
            local line = string.format("%s %d - %s (%s, %s) %s",
                entry.resultText,
                entry.total or 0,
                entry.description,
                attr,
                entry.favor,
                entry.actorName
            )
            love.graphics.setColor(0.82, 0.78, 0.7, 0.9 * alpha)
            love.graphics.printf(line, listX, yCursor, listW, "left")
            yCursor = yCursor + lineH
        end
        love.graphics.setScissor()
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

        -- Test history drawer toggle
        if button == 1 and self.narrativeView and self.narrativeView.isVisible and self.testHistoryDrawer then
            local view = self.narrativeView
            local drawer = self.testHistoryDrawer
            local height = drawer.isExpanded and drawer.expandedHeight or drawer.collapsedHeight
            local drawerX = view.x
            local drawerY = view.y + view.height - height
            local drawerW = view.width
            local drawerH = height
            if x >= drawerX and x <= drawerX + drawerW and y >= drawerY and y <= drawerY + drawerH then
                -- Toggle only if clicking header area
                if y <= drawerY + drawer.headerHeight then
                    drawer.isExpanded = not drawer.isExpanded
                    return
                end
            end
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
