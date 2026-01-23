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

        -- S12.1: Emit full engagement state for UI
        self:emitEngagementChanged()
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

        -- S12.1: Emit full engagement state for UI
        self:emitEngagementChanged()
    end

    --- Disengage an entity from all opponents
    function registry:disengageAll(entityId)
        local engaged = self.engagements[entityId] or {}
        -- Copy list since disengage modifies it
        local toDisengage = {}
        for _, otherId in ipairs(engaged) do
            toDisengage[#toDisengage + 1] = otherId
        end
        for _, otherId in ipairs(toDisengage) do
            self:disengage(entityId, otherId)
        end
    end

    --- S12.1: Clear ALL engagements (for challenge end)
    function registry:clearAllEngagements()
        self.engagements = {}
        self:emitEngagementChanged()
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

    --- S12.1: Check if two specific entities are engaged with each other
    function registry:areEngaged(entityA_id, entityB_id)
        local engaged = self.engagements[entityA_id]
        if not engaged then return false end

        for _, id in ipairs(engaged) do
            if id == entityB_id then
                return true
            end
        end
        return false
    end

    --- S12.1: Get all engagement pairs (for UI visualization)
    -- @return table: Array of { entityA_id, entityB_id } pairs
    function registry:getAllEngagementPairs()
        local result = {}
        local seen = {}  -- Track pairs we've already added

        for entityId, engagedList in pairs(self.engagements) do
            for _, otherId in ipairs(engagedList) do
                -- Create a canonical key to avoid duplicates (smaller id first)
                local key = entityId < otherId and (entityId .. "_" .. otherId) or (otherId .. "_" .. entityId)
                if not seen[key] then
                    seen[key] = true
                    result[#result + 1] = { entityId, otherId }
                end
            end
        end

        return result
    end

    --- S12.1: Emit engagement changed event (call after any engagement change)
    function registry:emitEngagementChanged()
        self.eventBus:emit(events.EVENTS.ENGAGEMENT_CHANGED, {
            pairs = self:getAllEngagementPairs(),
        })
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
