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
-- @param config table: { eventBus, playerDeck, gmDeck, guild, zoneSystem }
-- @return ChallengeController instance
function M.createChallengeController(config)
    config = config or {}

    local controller = {
        eventBus   = config.eventBus or events.globalBus,
        playerDeck = config.playerDeck,
        gmDeck     = config.gmDeck,
        guild      = config.guild or {},  -- PC entities
        zoneSystem = config.zoneSystem,   -- S12.1: Zone registry for engagement tracking

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

        -- S12.1: Clear all engagements when challenge ends
        if self.zoneSystem then
            self.zoneSystem:clearAllEngagements()
        end

        -- Clear is_engaged flag on all combatants
        for _, entity in ipairs(self.allCombatants) do
            entity.is_engaged = false
        end

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
