-- wound_walk.lua
-- Wound Walk Visual Feedback System for Majesty
-- Ticket S4.3: Visually demonstrate defense layer priority
--
-- When takeWound() is called, shows the cascade:
-- 1. Armor -> Flash armor icon, show notch appearing
-- 2. Talent -> Highlight talents, show X over wounded talent
-- 3. Condition -> Shake health pips on portrait
--
-- This helps players understand their defense layers working (or failing).

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- ANIMATION STATES
--------------------------------------------------------------------------------
M.STATES = {
    IDLE         = "idle",
    ARMOR_CHECK  = "armor_check",
    TALENT_CHECK = "talent_check",
    CONDITION    = "condition",
    COMPLETE     = "complete",
}

--------------------------------------------------------------------------------
-- ANIMATION DURATIONS (seconds)
--------------------------------------------------------------------------------
M.DURATIONS = {
    armor_flash   = 0.3,
    notch_appear  = 0.2,
    talent_flash  = 0.3,
    talent_x      = 0.2,
    health_shake  = 0.4,
    transition    = 0.1,
}

--------------------------------------------------------------------------------
-- WOUND WALK FACTORY
--------------------------------------------------------------------------------

--- Create a new WoundWalk visual controller
-- @param config table: { eventBus, onComplete }
-- @return WoundWalk instance
function M.createWoundWalk(config)
    config = config or {}

    local walk = {
        eventBus   = config.eventBus or events.globalBus,
        onComplete = config.onComplete,

        -- Current state
        state      = M.STATES.IDLE,
        timer      = 0,
        duration   = 0,

        -- Current wound being visualized
        woundData  = nil,
        entity     = nil,

        -- Visual effects currently active
        activeEffects = {},

        -- Flash/shake parameters
        flashAlpha   = 0,
        shakeOffset  = { x = 0, y = 0 },
        shakeMagnitude = 5,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function walk:init()
        -- Listen for wound events
        self.eventBus:on(events.EVENTS.WOUND_TAKEN, function(data)
            self:startWalk(data)
        end)
    end

    ----------------------------------------------------------------------------
    -- WALK LIFECYCLE
    ----------------------------------------------------------------------------

    --- Start visualizing a wound
    -- @param data table: { entity, result, pierced }
    function walk:startWalk(data)
        if self.state ~= M.STATES.IDLE then
            -- Queue this wound? For now, skip if busy
            return
        end

        self.woundData = data
        self.entity = data.entity
        self.activeEffects = {}

        local result = data.result or ""

        -- Determine starting state based on what absorbed the wound
        if result == "armor_notched" then
            self:startArmorPhase()
        elseif result == "talent_wounded" then
            self:startTalentPhase()
        elseif result == "staggered" or
               result == "injured" or
               result == "deaths_door" or
               result == "dead" then
            self:startConditionPhase(result)
        else
            -- Unknown result, skip animation
            self:completeWalk()
        end
    end

    ----------------------------------------------------------------------------
    -- ARMOR PHASE
    -- Flash the armor icon and show a notch appearing
    ----------------------------------------------------------------------------

    function walk:startArmorPhase()
        self.state = M.STATES.ARMOR_CHECK
        self.timer = 0
        self.duration = M.DURATIONS.armor_flash + M.DURATIONS.notch_appear

        self.activeEffects = {
            {
                type = "armor_flash",
                target = self.entity,
                duration = M.DURATIONS.armor_flash,
                progress = 0,
            },
            {
                type = "notch_appear",
                target = self.entity,
                duration = M.DURATIONS.notch_appear,
                delay = M.DURATIONS.armor_flash,
                progress = 0,
            },
        }

        -- Emit event for UI to render
        self.eventBus:emit("wound_walk_phase", {
            phase = "armor",
            entity = self.entity,
            effects = self.activeEffects,
        })
    end

    ----------------------------------------------------------------------------
    -- TALENT PHASE
    -- Highlight the talents section and show an X over the wounded talent
    ----------------------------------------------------------------------------

    function walk:startTalentPhase()
        self.state = M.STATES.TALENT_CHECK
        self.timer = 0
        self.duration = M.DURATIONS.talent_flash + M.DURATIONS.talent_x

        -- Find which talent was wounded
        local woundedTalent = nil
        if self.entity and self.entity.talents then
            for talentId, talent in pairs(self.entity.talents) do
                if talent.wounded then
                    woundedTalent = talentId
                    break
                end
            end
        end

        self.activeEffects = {
            {
                type = "talent_flash",
                target = self.entity,
                talentId = woundedTalent,
                duration = M.DURATIONS.talent_flash,
                progress = 0,
            },
            {
                type = "talent_x",
                target = self.entity,
                talentId = woundedTalent,
                duration = M.DURATIONS.talent_x,
                delay = M.DURATIONS.talent_flash,
                progress = 0,
            },
        }

        self.eventBus:emit("wound_walk_phase", {
            phase = "talent",
            entity = self.entity,
            talentId = woundedTalent,
            effects = self.activeEffects,
        })
    end

    ----------------------------------------------------------------------------
    -- CONDITION PHASE
    -- Shake the health pips / portrait
    ----------------------------------------------------------------------------

    function walk:startConditionPhase(condition)
        self.state = M.STATES.CONDITION
        self.timer = 0
        self.duration = M.DURATIONS.health_shake

        -- Determine shake intensity based on severity
        local intensity = 1
        if condition == "injured" then
            intensity = 1.5
        elseif condition == "deaths_door" then
            intensity = 2
        elseif condition == "dead" then
            intensity = 3
        end

        self.activeEffects = {
            {
                type = "health_shake",
                target = self.entity,
                condition = condition,
                intensity = intensity,
                duration = M.DURATIONS.health_shake,
                progress = 0,
            },
        }

        -- Add color flash for severe conditions
        if condition == "deaths_door" or condition == "dead" then
            self.activeEffects[#self.activeEffects + 1] = {
                type = "danger_flash",
                target = self.entity,
                color = condition == "dead" and { 0.3, 0, 0 } or { 0.5, 0.1, 0.1 },
                duration = M.DURATIONS.health_shake,
                progress = 0,
            }
        end

        self.eventBus:emit("wound_walk_phase", {
            phase = "condition",
            entity = self.entity,
            condition = condition,
            effects = self.activeEffects,
        })
    end

    ----------------------------------------------------------------------------
    -- COMPLETE WALK
    ----------------------------------------------------------------------------

    function walk:completeWalk()
        self.state = M.STATES.COMPLETE

        self.eventBus:emit("wound_walk_complete", {
            entity = self.entity,
            woundData = self.woundData,
        })

        -- Reset state
        self.state = M.STATES.IDLE
        self.woundData = nil
        self.entity = nil
        self.activeEffects = {}
        self.timer = 0

        -- Call completion callback
        if self.onComplete then
            self.onComplete()
        end
    end

    ----------------------------------------------------------------------------
    -- UPDATE (call from love.update)
    ----------------------------------------------------------------------------

    function walk:update(dt)
        if self.state == M.STATES.IDLE then
            return
        end

        self.timer = self.timer + dt

        -- Update effect progress
        for _, effect in ipairs(self.activeEffects) do
            local effectStart = effect.delay or 0
            local effectTime = self.timer - effectStart

            if effectTime >= 0 then
                effect.progress = math.min(1, effectTime / effect.duration)
            end
        end

        -- Calculate shake offset for condition phase
        if self.state == M.STATES.CONDITION then
            local progress = self.timer / self.duration
            local shakeAmount = self.shakeMagnitude * (1 - progress)
            self.shakeOffset.x = math.sin(self.timer * 50) * shakeAmount
            self.shakeOffset.y = math.cos(self.timer * 40) * shakeAmount * 0.5
        else
            self.shakeOffset.x = 0
            self.shakeOffset.y = 0
        end

        -- Check for phase completion
        if self.timer >= self.duration then
            self:completeWalk()
        end
    end

    ----------------------------------------------------------------------------
    -- RENDERING HELPERS
    ----------------------------------------------------------------------------

    --- Get current active effects for rendering
    function walk:getActiveEffects()
        return self.activeEffects
    end

    --- Get shake offset for portrait rendering
    function walk:getShakeOffset()
        return self.shakeOffset
    end

    --- Check if walk is active
    function walk:isActive()
        return self.state ~= M.STATES.IDLE
    end

    --- Get current state
    function walk:getState()
        return self.state
    end

    --- Get flash alpha for armor/talent flash
    function walk:getFlashAlpha()
        if #self.activeEffects == 0 then
            return 0
        end

        for _, effect in ipairs(self.activeEffects) do
            if effect.type == "armor_flash" or
               effect.type == "talent_flash" or
               effect.type == "danger_flash" then
                -- Pulse effect: fade in then fade out
                local progress = effect.progress
                if progress < 0.5 then
                    return progress * 2  -- Fade in
                else
                    return (1 - progress) * 2  -- Fade out
                end
            end
        end

        return 0
    end

    --- Get the entity being animated
    function walk:getEntity()
        return self.entity
    end

    return walk
end

return M
