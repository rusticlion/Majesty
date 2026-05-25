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

local function copyShallow(source)
    local copy = {}
    for key, value in pairs(source or {}) do
        copy[key] = value
    end
    return copy
end

local function selectEncounterEntry(entry, card)
    if type(entry) == "table" and #entry > 0 and not entry.description and
       not entry.blueprint_id and not entry.spawns and not entry.effects then
        local index = ((card.value - 16) % #entry) + 1
        return entry[index]
    end
    return entry
end

local function getConfiguredEncounter(card, room, context)
    context = context or {}
    room = room or {}

    local entry = context.randomEncounter or context.random_encounter or
        context.encounter or context.defaultRandomEncounter
    if not entry then
        entry = room.randomEncounter or room.random_encounter
    end
    if not entry and room.properties then
        entry = room.properties.randomEncounter or room.properties.random_encounter
    end

    return selectEncounterEntry(entry, card)
end

local function normalizeEncounterEntry(entry)
    if type(entry) == "string" then
        return {
            description = entry,
            effects = {
                { type = "encounter_start" },
            },
        }
    end

    if type(entry) ~= "table" then
        return nil
    end

    local data = copyShallow(entry)
    data.effects = data.effects or {
        { type = "encounter_start" },
    }

    if not data.spawns and data.blueprint_id then
        local spawn = copyShallow(data)
        spawn.count = spawn.count or 1
        spawn.description = nil
        spawn.effects = nil
        spawn.spawns = nil
        data.spawns = {
            spawn,
        }
    end

    return data
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
    local travelEvents = {
        {
            description = "The lead marcher steps in fresh droppings; cleanup is needed soon to avoid Stress.",
            effects = {
                {
                    type = "droppings",
                    target = "first_in_marching_order",
                    cleanupRequired = true,
                    stressIfUnclean = true,
                    loreReveal = "fresh_ogre_spoor",
                    sourceCreature = "ogre",
                    freshnessDays = 1,
                },
            },
        },
        {
            description = "A flooded rushing river blocks the way; turn back or swim through the cold current.",
            effects = {
                {
                    type = "rushing_river",
                    options = { "turn_back", "cross" },
                    attribute = "swords",
                    failure = "wound",
                    stressTarget = "crossers",
                    destroysFragilePackItems = true,
                },
            },
        },
        {
            description = "A random adventurer discovers a hole in their pack; the last listed pack item is gone.",
            effects = {
                {
                    type = "hole_in_pack",
                    target = "random_adventurer",
                    lostItem = "last_listed_pack_item",
                    backtrackingCostsWatches = true,
                },
            },
        },
        {
            description = "A field of faintly glowing mushrooms surrounds a corpse and a cracked chest.",
            effects = {
                {
                    type = "bad_scene",
                    poisonousMushrooms = true,
                    corpseHazard = "zombie",
                    chestHazard = true,
                    treasurePresent = true,
                    gmAdjudication = true,
                },
            },
        },
        {
            description = "Thick webs block the path, with hanging sacks visible above the way forward.",
            effects = {
                {
                    type = "webs",
                    blocksPath = true,
                    visibleHangingSacks = true,
                    rescueOpportunity = true,
                },
            },
        },
    }

    local index = ((card.value - 11) % #travelEvents) + 1

    return createResult(M.CATEGORIES.TRAVEL_EVENT, travelEvents[index])
end

--- XVI-XX: Random Encounter
-- Meet denizens of the Underworld
defaultHandlers[M.CATEGORIES.RANDOM_ENCOUNTER] = function(card, room, context)
    local authored = normalizeEncounterEntry(getConfiguredEncounter(card, room, context))
    if authored then
        return createResult(M.CATEGORIES.RANDOM_ENCOUNTER, authored)
    end

    return createResult(M.CATEGORIES.RANDOM_ENCOUNTER, {
        description = "A random encounter occurs; choose or author a local scenario for this dungeon.",
        effects = {
            { type = "encounter_start" },
            { type = "gm_authored_random_encounter_required" },
        },
        requiresAuthoredEncounter = true,
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
-- AUTHORED TABLE HANDLERS
--------------------------------------------------------------------------------

local categoryTableKeys = {
    [M.CATEGORIES.TORCHES_GUTTER]   = "torches_gutter",
    [M.CATEGORIES.CURIOSITY]        = "curiosity",
    [M.CATEGORIES.TRAVEL_EVENT]     = "travel_event",
    [M.CATEGORIES.RANDOM_ENCOUNTER] = "random_encounter",
    [M.CATEGORIES.QUEST_RUMOR]      = "quest_rumor",
}

local categoryOffsets = {
    [M.CATEGORIES.TORCHES_GUTTER]   = 0,
    [M.CATEGORIES.CURIOSITY]        = 5,
    [M.CATEGORIES.TRAVEL_EVENT]     = 10,
    [M.CATEGORIES.RANDOM_ENCOUNTER] = 15,
}

local function shallowCopy(source)
    local copy = {}
    for key, value in pairs(source or {}) do
        copy[key] = value
    end
    return copy
end

local function normalizeTableEntry(entry)
    if type(entry) == "string" then
        return { description = entry }
    end

    if type(entry) ~= "table" then
        return { description = tostring(entry or "") }
    end

    local data = shallowCopy(entry)

    if not data.effects and data.effect then
        local effect = shallowCopy(data)
        effect.type = data.effect
        effect.effect = nil
        effect.description = nil
        effect.spawns = nil
        data.effects = { effect }
    end

    if not data.spawns and data.blueprint_id then
        local spawn = shallowCopy(data)
        spawn.count = spawn.count or 1
        spawn.description = nil
        spawn.effects = nil
        spawn.spawns = nil
        data.spawns = {
            spawn,
        }
    end

    return data
end

local function selectTableEntry(tableData, category, cardValue)
    local tableKey = categoryTableKeys[category]
    local section = tableKey and tableData and tableData[tableKey]
    if not section then
        return nil
    end

    if category == M.CATEGORIES.QUEST_RUMOR then
        return section
    end

    if type(section) ~= "table" then
        return section
    end

    if category == M.CATEGORIES.TORCHES_GUTTER and
        (section.description or section.effect or section.effects or section.blueprint_id) then
        return section
    end

    local offset = categoryOffsets[category] or 0
    local index = cardValue - offset
    return section[index]
end

--- Create category handlers from an authored Meatgrinder table.
-- Authored tables use I-V/VI-X/etc. indexes within each section; handlers
-- convert the card value into a standard Meatgrinder result object.
function M.createTableHandlers(tableData)
    local handlers = {}

    for category, _ in pairs(categoryTableKeys) do
        handlers[category] = function(card, room, context)
            local entry = selectTableEntry(tableData, category, card.value)
            if not entry then
                local fallback = defaultHandlers[category]
                return fallback and fallback(card, room, context) or createResult(category, {})
            end

            return createResult(category, normalizeTableEntry(entry))
        end
    end

    return handlers
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

    --- Register an authored Meatgrinder table.
    -- @param tableData table: { torches_gutter, curiosity, travel_event, random_encounter, quest_rumor }
    -- @param roomId string|nil: Room ID for room-specific overrides; nil is dungeon-wide
    function grinder:registerTable(tableData, roomId)
        local handlers = M.createTableHandlers(tableData or {})
        for category, handler in pairs(handlers) do
            self:registerHandler(category, roomId, handler)
        end
        return self
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
    local function makeConsumedKey(category, roomId, cardValue)
        return (roomId or "global") .. ":" .. category .. ":" .. tostring(cardValue)
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
        local consumedKey = makeConsumedKey(category, roomId, card.value)
        local canBeConsumed = category ~= M.CATEGORIES.TORCHES_GUTTER
        if canBeConsumed and self.consumed[consumedKey] then
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
        if not result then
            return nil
        end

        -- Mark as consumed. Torches gutter results are exempt: the rulebook says
        -- they can occur multiple times and are not marked off.
        if canBeConsumed then
            self.consumed[consumedKey] = true
            result.consumed = true
        else
            result.consumed = false
        end

        -- Emit event for other systems unless a caller is adapting the result
        -- into its own event payload.
        if context.emitEvents ~= false then
            self.eventBus:emit(events.EVENTS.MEATGRINDER_ROLL, {
                card     = card,
                category = category,
                roomId   = roomId,
                result   = result,
            })
        end

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
    function grinder:isConsumed(category, roomId, cardValue)
        if cardValue ~= nil then
            local key = makeConsumedKey(category, roomId, cardValue)
            return self.consumed[key] or false
        end

        local prefix = (roomId or "global") .. ":" .. category .. ":"
        for key, _ in pairs(self.consumed or {}) do
            if string.sub(key, 1, #prefix) == prefix then
                return true
            end
        end
        return false
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
