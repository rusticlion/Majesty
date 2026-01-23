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
