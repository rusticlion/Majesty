-- disposition.lua
-- Disposition System for Majesty
-- Ticket S12.4: 7-disposition emotional wheel for NPCs
--
-- The disposition wheel (from HMTW rulebook):
--   ANGER → DISTASTE → SADNESS → JOY → SURPRISE → TRUST → FEAR → (back to ANGER)
--
-- Dispositions affect:
--   - NPC reactions to social actions
--   - Available negotiation options
--   - Banter and Parley effectiveness

local M = {}

--------------------------------------------------------------------------------
-- DISPOSITION CONSTANTS
--------------------------------------------------------------------------------

M.DISPOSITIONS = {
    ANGER     = "anger",
    DISTASTE  = "distaste",
    SADNESS   = "sadness",
    JOY       = "joy",
    SURPRISE  = "surprise",
    TRUST     = "trust",
    FEAR      = "fear",
}

-- Ordered wheel (for transitions)
M.WHEEL = {
    "anger",
    "distaste",
    "sadness",
    "joy",
    "surprise",
    "trust",
    "fear",
}

-- Wheel position lookup
M.WHEEL_INDEX = {}
for i, disp in ipairs(M.WHEEL) do
    M.WHEEL_INDEX[disp] = i
end

--------------------------------------------------------------------------------
-- DISPOSITION PROPERTIES
-- Each disposition has properties that affect social interactions
--------------------------------------------------------------------------------

M.PROPERTIES = {
    anger = {
        name = "Anger",
        description = "Hostile and aggressive. May attack or refuse to negotiate.",
        combatLikelihood = 0.8,  -- 80% likely to fight
        negotiable = false,      -- Cannot parley while angry
        banterDifficulty = -2,   -- Easier to banter (they're distracted by rage)
        intimidateDifficulty = 2, -- Harder to intimidate (already aggressive)
    },
    distaste = {
        name = "Distaste",
        description = "Dismissive and contemptuous. May ignore or insult.",
        combatLikelihood = 0.4,
        negotiable = true,
        banterDifficulty = 0,
        intimidateDifficulty = 0,
    },
    sadness = {
        name = "Sadness",
        description = "Melancholy and withdrawn. May be susceptible to sympathy.",
        combatLikelihood = 0.2,
        negotiable = true,
        banterDifficulty = 2,    -- Harder to banter (they don't care)
        intimidateDifficulty = -2, -- Easier to intimidate (already demoralized)
    },
    joy = {
        name = "Joy",
        description = "Happy and generous. Most likely to negotiate or help.",
        combatLikelihood = 0.1,
        negotiable = true,
        banterDifficulty = 2,    -- Harder to banter (good mood)
        intimidateDifficulty = 2, -- Harder to intimidate (confident)
    },
    surprise = {
        name = "Surprise",
        description = "Startled and uncertain. Reactions are unpredictable.",
        combatLikelihood = 0.5,
        negotiable = true,
        banterDifficulty = 0,
        intimidateDifficulty = -2, -- Easier to intimidate (off-balance)
    },
    trust = {
        name = "Trust",
        description = "Open and believing. May reveal information or provide aid.",
        combatLikelihood = 0.1,
        negotiable = true,
        banterDifficulty = 4,    -- Very hard to banter (they trust you)
        intimidateDifficulty = 4, -- Very hard to intimidate (they trust you)
    },
    fear = {
        name = "Fear",
        description = "Frightened and defensive. May flee or submit.",
        combatLikelihood = 0.3,  -- Might fight from desperation
        negotiable = true,
        banterDifficulty = 0,
        intimidateDifficulty = -4, -- Very easy to intimidate (already scared)
    },
}

--------------------------------------------------------------------------------
-- DISPOSITION TRANSITIONS
-- How actions shift disposition around the wheel
--------------------------------------------------------------------------------

-- Shift directions
M.SHIFT = {
    CLOCKWISE = 1,
    COUNTER_CLOCKWISE = -1,
}

-- What causes disposition shifts
M.TRIGGERS = {
    -- Successful banter: shifts toward Fear/Sadness (clockwise from most)
    banter_success = { direction = M.SHIFT.CLOCKWISE, amount = 1 },
    banter_great = { direction = M.SHIFT.CLOCKWISE, amount = 2 },

    -- Failed banter: shifts toward Anger (counter-clockwise)
    banter_fail = { direction = M.SHIFT.COUNTER_CLOCKWISE, amount = 1 },

    -- Successful intimidate: shifts toward Fear
    intimidate_success = { target = "fear", amount = 1 },
    intimidate_great = { target = "fear", amount = 2 },

    -- Combat damage: shifts toward Anger or Fear (based on advantage)
    damage_dealt = { direction = M.SHIFT.COUNTER_CLOCKWISE, amount = 1 },  -- NPC angry
    damage_taken = { direction = M.SHIFT.CLOCKWISE, amount = 1 },          -- NPC fearful

    -- Gifts/Aid: shifts toward Trust/Joy
    gift_given = { target = "trust", amount = 1 },
    ally_helped = { target = "joy", amount = 1 },

    -- Parley success: stabilizes toward Trust
    parley_success = { target = "trust", amount = 1 },
}

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------

--- Get the next disposition in the wheel
-- @param current string: Current disposition
-- @param direction number: SHIFT.CLOCKWISE or SHIFT.COUNTER_CLOCKWISE
-- @return string: New disposition
function M.getNextDisposition(current, direction)
    local index = M.WHEEL_INDEX[current]
    if not index then return current end

    local newIndex = index + direction
    if newIndex < 1 then newIndex = #M.WHEEL end
    if newIndex > #M.WHEEL then newIndex = 1 end

    return M.WHEEL[newIndex]
end

--- Shift a disposition by amount in a direction
-- @param current string: Current disposition
-- @param direction number: SHIFT.CLOCKWISE or SHIFT.COUNTER_CLOCKWISE
-- @param amount number: How many steps to shift
-- @return string: New disposition
function M.shiftDisposition(current, direction, amount)
    local result = current
    for _ = 1, amount do
        result = M.getNextDisposition(result, direction)
    end
    return result
end

--- Move disposition toward a target disposition
-- @param current string: Current disposition
-- @param target string: Target disposition
-- @param amount number: Maximum steps to move
-- @return string: New disposition (may not reach target)
function M.moveToward(current, target, amount)
    if current == target then return current end

    local currentIndex = M.WHEEL_INDEX[current]
    local targetIndex = M.WHEEL_INDEX[target]
    if not currentIndex or not targetIndex then return current end

    -- Calculate shortest path around the wheel
    local clockwiseDist = (targetIndex - currentIndex) % #M.WHEEL
    local counterClockwiseDist = (currentIndex - targetIndex) % #M.WHEEL

    local direction
    if clockwiseDist <= counterClockwiseDist then
        direction = M.SHIFT.CLOCKWISE
    else
        direction = M.SHIFT.COUNTER_CLOCKWISE
    end

    return M.shiftDisposition(current, direction, math.min(amount, math.min(clockwiseDist, counterClockwiseDist)))
end

--- Apply a trigger to shift disposition
-- @param current string: Current disposition
-- @param triggerName string: Name of the trigger (from M.TRIGGERS)
-- @return string: New disposition
function M.applyTrigger(current, triggerName)
    local trigger = M.TRIGGERS[triggerName]
    if not trigger then return current end

    if trigger.target then
        -- Move toward specific disposition
        return M.moveToward(current, trigger.target, trigger.amount)
    elseif trigger.direction then
        -- Shift in direction
        return M.shiftDisposition(current, trigger.direction, trigger.amount)
    end

    return current
end

--- Get properties for a disposition
-- @param disposition string: The disposition
-- @return table: Properties table
function M.getProperties(disposition)
    return M.PROPERTIES[disposition] or M.PROPERTIES.distaste
end

--- Check if NPC is willing to negotiate
-- @param disposition string: The disposition
-- @return boolean: Can negotiate
function M.canNegotiate(disposition)
    local props = M.getProperties(disposition)
    return props.negotiable
end

--- Get combat likelihood (0-1)
-- @param disposition string: The disposition
-- @return number: Probability of combat
function M.getCombatLikelihood(disposition)
    local props = M.getProperties(disposition)
    return props.combatLikelihood
end

--- Get difficulty modifier for social actions
-- @param disposition string: The disposition
-- @param actionType string: "banter" or "intimidate"
-- @return number: Modifier to add to difficulty
function M.getSocialModifier(disposition, actionType)
    local props = M.getProperties(disposition)
    if actionType == "banter" then
        return props.banterDifficulty or 0
    elseif actionType == "intimidate" then
        return props.intimidateDifficulty or 0
    end
    return 0
end

return M
