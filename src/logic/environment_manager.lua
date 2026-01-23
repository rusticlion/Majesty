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
