-- interaction.lua
-- Interaction Verb System for Majesty
-- Ticket T2_6: Glance, Scrutinize, Investigate info-gates
--
-- Design: Three levels of information revelation
-- - Glance: Free, automatic (what you see at first look)
-- - Scrutinize: Hidden info (requires "say more about what you're doing")
-- - Investigate: May require Test of Fate if risky
--
-- Anti-pattern warning: Players should think, not spam clicks.
-- Investigating a trap improperly has a high chance of triggering it.

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- INTERACTION LEVELS (Info-Gates)
--------------------------------------------------------------------------------
M.LEVELS = {
    GLANCE      = "glance",       -- Free, immediate
    SCRUTINIZE  = "scrutinize",   -- Requires description of method
    INVESTIGATE = "investigate",  -- May require Test of Fate
}

--------------------------------------------------------------------------------
-- INTERACTION TYPES
-- Common verbs for interacting with objects
--------------------------------------------------------------------------------
M.ACTIONS = {
    EXAMINE   = "examine",    -- Look at/describe
    SEARCH    = "search",     -- Look for hidden things
    TAKE      = "take",       -- Pick up
    USE       = "use",        -- Activate/operate
    OPEN      = "open",       -- Open container/door
    CLOSE     = "close",      -- Close container/door
    UNLOCK    = "unlock",     -- Unlock with key
    FORCE     = "force",      -- Break open
    LIGHT     = "light",      -- Set on fire/illuminate
    CLIMB     = "climb",      -- Climb on/over
    PUSH      = "push",       -- Push/shove
    PULL      = "pull",       -- Pull/yank
    TALK      = "talk",       -- Speak to
    ATTACK    = "attack",     -- Harm
    TRAP_CHECK = "trap_check", -- Check for traps (risky!)
}

--------------------------------------------------------------------------------
-- INTERACTION RESULT
--------------------------------------------------------------------------------

local function createResult(config)
    return {
        success       = config.success ~= false,
        level         = config.level,
        action        = config.action,
        target        = config.target,
        description   = config.description or "",
        hidden_info   = config.hidden_info,    -- Revealed at SCRUTINIZE+
        requires_test = config.requires_test,  -- For INVESTIGATE
        test_config   = config.test_config,    -- { attribute, difficulty, consequences }
        triggered     = config.triggered,      -- Did we trigger something bad?
        items_found   = config.items_found,    -- Array of item IDs
        state_change  = config.state_change,   -- { feature_id, new_state }
    }
end

--------------------------------------------------------------------------------
-- INTERACTION HANDLER REGISTRY
-- Maps action types to handler functions
--------------------------------------------------------------------------------

local defaultHandlers = {}

--- Default EXAMINE handler (works for most things)
defaultHandlers[M.ACTIONS.EXAMINE] = function(target, level, context)
    local result = {
        level  = level,
        action = M.ACTIONS.EXAMINE,
        target = target,
    }

    -- Glance: Just the basic description
    if level == M.LEVELS.GLANCE then
        result.description = target.name or "Something."
        return createResult(result)
    end

    -- Scrutinize: Full description
    if level == M.LEVELS.SCRUTINIZE then
        result.description = target.description or target.name or "You look more closely."

        -- Reveal any hidden info at this level
        if target.hidden_description then
            result.hidden_info = target.hidden_description
        end

        return createResult(result)
    end

    -- Investigate: Detailed examination, may find more
    if level == M.LEVELS.INVESTIGATE then
        result.description = target.description or "You examine it thoroughly."

        -- At investigate level, we might find hidden things
        if target.secrets then
            result.hidden_info = target.secrets
        end

        return createResult(result)
    end

    return createResult(result)
end

--- Default SEARCH handler
defaultHandlers[M.ACTIONS.SEARCH] = function(target, level, context)
    local result = {
        level  = level,
        action = M.ACTIONS.SEARCH,
        target = target,
    }

    if level == M.LEVELS.GLANCE then
        result.description = "You would need to look more carefully to search this."
        result.success = false
        return createResult(result)
    end

    if level == M.LEVELS.SCRUTINIZE then
        result.description = "Describe how you're searching to investigate properly."
        if target.loot and #target.loot > 0 then
            result.hidden_info = "There might be something here..."
        end
        return createResult(result)
    end

    -- Investigate: Actually search
    if level == M.LEVELS.INVESTIGATE then
        if target.state == "searched" or target.state == "empty" then
            result.description = "You've already searched this."
            return createResult(result)
        end

        -- Check for traps first!
        if target.trap and not target.trap.detected and not target.trap.disarmed then
            -- Searching without checking for traps first is dangerous
            result.requires_test = true
            result.test_config = {
                attribute     = "pentacles",
                difficulty    = target.trap.difficulty or 14,
                success_desc  = "You find the trap before it springs.",
                failure_desc  = "You trigger the trap!",
                failure_effect = { type = "trap_triggered", trap = target.trap },
            }
        end

        -- Found items
        if target.loot and #target.loot > 0 then
            result.items_found = target.loot
            result.description = "You find something!"
        else
            result.description = "You search thoroughly but find nothing of interest."
        end

        result.state_change = { new_state = "searched" }
        return createResult(result)
    end

    return createResult(result)
end

--- Default TRAP_CHECK handler
-- Checking for traps is itself risky!
defaultHandlers[M.ACTIONS.TRAP_CHECK] = function(target, level, context)
    local result = {
        level  = level,
        action = M.ACTIONS.TRAP_CHECK,
        target = target,
    }

    if level ~= M.LEVELS.INVESTIGATE then
        result.description = "You need to investigate properly to check for traps."
        result.success = false
        return createResult(result)
    end

    -- No trap present
    if not target.trap then
        result.description = "You find no traps."
        return createResult(result)
    end

    -- Already detected or disarmed
    if target.trap.detected then
        result.description = "You've already detected a trap here: " .. (target.trap.description or "some kind of trap.")
        return createResult(result)
    end

    if target.trap.disarmed then
        result.description = "The trap here has been disarmed."
        return createResult(result)
    end

    -- Requires a test to detect safely
    -- "Investigating a trap improperly has a high chance of triggering it"
    result.requires_test = true
    result.test_config = {
        attribute     = "pentacles",
        difficulty    = target.trap.difficulty or 14,
        success_desc  = "You detect and avoid the trap: " .. (target.trap.description or "a hidden mechanism."),
        failure_desc  = "You trigger the trap while searching for it!",
        failure_effect = { type = "trap_triggered", trap = target.trap },
        success_effect = { type = "trap_detected" },
    }

    return createResult(result)
end

--- Default OPEN handler
defaultHandlers[M.ACTIONS.OPEN] = function(target, level, context)
    local result = {
        level  = level,
        action = M.ACTIONS.OPEN,
        target = target,
    }

    if target.state == "open" then
        result.description = "It's already open."
        result.success = false
        return createResult(result)
    end

    if target.state == "locked" then
        result.description = "It's locked."
        result.success = false
        return createResult(result)
    end

    -- Can open
    result.description = "You open it."
    result.state_change = { new_state = "open" }
    return createResult(result)
end

--- Default UNLOCK handler
defaultHandlers[M.ACTIONS.UNLOCK] = function(target, level, context)
    local result = {
        level  = level,
        action = M.ACTIONS.UNLOCK,
        target = target,
    }

    if target.state ~= "locked" then
        result.description = "It's not locked."
        result.success = false
        return createResult(result)
    end

    -- Check if player has the key
    if target.lock and target.lock.key_id then
        if context.hasItem and context.hasItem(target.lock.key_id) then
            result.description = "You unlock it with the " .. target.lock.key_id .. "."
            result.state_change = { new_state = "unlocked" }
        else
            result.description = "You need a key to unlock this."
            result.success = false
        end
    else
        -- No specific key required
        result.description = "You unlock it."
        result.state_change = { new_state = "unlocked" }
    end

    return createResult(result)
end

--------------------------------------------------------------------------------
-- INTERACTION SYSTEM FACTORY
--------------------------------------------------------------------------------

--- Create a new InteractionSystem
-- @param config table: { eventBus, roomManager, resolver }
-- @return InteractionSystem instance
function M.createInteractionSystem(config)
    config = config or {}

    local system = {
        eventBus    = config.eventBus or events.globalBus,
        roomManager = config.roomManager,
        resolver    = config.resolver,
        -- Custom handlers can override defaults
        customHandlers = {},
    }

    ----------------------------------------------------------------------------
    -- HANDLER REGISTRATION
    ----------------------------------------------------------------------------

    --- Register a custom action handler
    function system:registerHandler(action, handler)
        self.customHandlers[action] = handler
    end

    --- Get handler for an action
    local function getHandler(self, action)
        return self.customHandlers[action] or defaultHandlers[action]
    end

    ----------------------------------------------------------------------------
    -- CONTEXT MENU
    -- Determines valid actions for a target
    ----------------------------------------------------------------------------

    --- Get valid actions for a target
    -- @param target table: Feature or entity to interact with
    -- @return table: Array of { action, level_required, description }
    function system:getValidActions(target)
        local actions = {}

        -- Check target's declared interactions
        if target.interactions then
            for _, action in ipairs(target.interactions) do
                local handler = getHandler(self, action)
                if handler then
                    actions[#actions + 1] = {
                        action         = action,
                        level_required = self:getRequiredLevel(action, target),
                        description    = self:getActionDescription(action),
                    }
                end
            end
        else
            -- Default interactions based on type
            actions[#actions + 1] = { action = M.ACTIONS.EXAMINE, level_required = M.LEVELS.GLANCE }

            if target.type == "container" then
                actions[#actions + 1] = { action = M.ACTIONS.SEARCH, level_required = M.LEVELS.INVESTIGATE }
                actions[#actions + 1] = { action = M.ACTIONS.OPEN, level_required = M.LEVELS.GLANCE }
            end

            if target.type == "corpse" then
                actions[#actions + 1] = { action = M.ACTIONS.SEARCH, level_required = M.LEVELS.INVESTIGATE }
            end

            if target.trap then
                actions[#actions + 1] = { action = M.ACTIONS.TRAP_CHECK, level_required = M.LEVELS.INVESTIGATE }
            end
        end

        return actions
    end

    --- Get required level for an action
    function system:getRequiredLevel(action, target)
        -- Actions that are always safe
        if action == M.ACTIONS.EXAMINE then
            return M.LEVELS.GLANCE
        end

        -- Actions that need description
        if action == M.ACTIONS.SEARCH then
            return M.LEVELS.SCRUTINIZE
        end

        -- Risky actions need investigation level
        if action == M.ACTIONS.TRAP_CHECK or
           action == M.ACTIONS.FORCE or
           action == M.ACTIONS.CLIMB then
            return M.LEVELS.INVESTIGATE
        end

        return M.LEVELS.GLANCE
    end

    --- Get human-readable description of action
    function system:getActionDescription(action)
        local descriptions = {
            [M.ACTIONS.EXAMINE]    = "Look at",
            [M.ACTIONS.SEARCH]     = "Search",
            [M.ACTIONS.TAKE]       = "Take",
            [M.ACTIONS.USE]        = "Use",
            [M.ACTIONS.OPEN]       = "Open",
            [M.ACTIONS.CLOSE]      = "Close",
            [M.ACTIONS.UNLOCK]     = "Unlock",
            [M.ACTIONS.FORCE]      = "Force open",
            [M.ACTIONS.LIGHT]      = "Light",
            [M.ACTIONS.CLIMB]      = "Climb",
            [M.ACTIONS.PUSH]       = "Push",
            [M.ACTIONS.PULL]       = "Pull",
            [M.ACTIONS.TALK]       = "Talk to",
            [M.ACTIONS.ATTACK]     = "Attack",
            [M.ACTIONS.TRAP_CHECK] = "Check for traps",
        }
        return descriptions[action] or action
    end

    ----------------------------------------------------------------------------
    -- INTERACTION EXECUTION
    ----------------------------------------------------------------------------

    --- Execute an interaction
    -- @param entity table: The entity performing the action
    -- @param target table: The target (feature, entity, etc.)
    -- @param action string: One of ACTIONS
    -- @param level string: One of LEVELS
    -- @param context table: Additional context { hasItem, method_description, ... }
    -- @return table: Interaction result
    function system:interact(entity, target, action, level, context)
        context = context or {}

        -- Check if action is valid for target
        local validActions = self:getValidActions(target)
        local isValid = false
        local requiredLevel = M.LEVELS.GLANCE

        for _, va in ipairs(validActions) do
            if va.action == action then
                isValid = true
                requiredLevel = va.level_required
                break
            end
        end

        if not isValid then
            return createResult({
                success     = false,
                level       = level,
                action      = action,
                target      = target,
                description = "You can't do that with this.",
            })
        end

        -- Check level requirement
        local levelOrder = { [M.LEVELS.GLANCE] = 1, [M.LEVELS.SCRUTINIZE] = 2, [M.LEVELS.INVESTIGATE] = 3 }
        if levelOrder[level] < levelOrder[requiredLevel] then
            return createResult({
                success     = false,
                level       = level,
                action      = action,
                target      = target,
                description = "You need to look more carefully to do that.",
            })
        end

        -- Get and execute handler
        local handler = getHandler(self, action)
        if not handler then
            return createResult({
                success     = false,
                level       = level,
                action      = action,
                target      = target,
                description = "You're not sure how to do that.",
            })
        end

        local result = handler(target, level, context)

        -- Handle state changes
        if result.success and result.state_change and self.roomManager then
            local roomId = context.roomId
            if roomId and target.id then
                self.roomManager:setFeatureState(roomId, target.id, result.state_change.new_state)
            end
        end

        -- Emit event
        self.eventBus:emit(events.EVENTS.INTERACTION, {
            entity = entity,
            target = target,
            action = action,
            level  = level,
            result = result,
        })

        return result
    end

    --- Convenience method for glance
    function system:glance(entity, target, context)
        return self:interact(entity, target, M.ACTIONS.EXAMINE, M.LEVELS.GLANCE, context)
    end

    --- Convenience method for scrutinize
    function system:scrutinize(entity, target, action, context)
        return self:interact(entity, target, action or M.ACTIONS.EXAMINE, M.LEVELS.SCRUTINIZE, context)
    end

    --- Convenience method for investigate
    function system:investigate(entity, target, action, context)
        return self:interact(entity, target, action or M.ACTIONS.SEARCH, M.LEVELS.INVESTIGATE, context)
    end

    return system
end

return M
