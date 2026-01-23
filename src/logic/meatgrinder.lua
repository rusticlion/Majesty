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
