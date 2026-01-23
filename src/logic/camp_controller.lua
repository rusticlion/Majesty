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
