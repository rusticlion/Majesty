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

M.SEVERITY = {
    MILD = 1,
    BASIC = 2,
    INTENSE = 3,
}

M.SEVERITY_NAMES = {
    [M.SEVERITY.MILD] = "mild",
    [M.SEVERITY.BASIC] = "basic",
    [M.SEVERITY.INTENSE] = "intense",
}

-- Rulebook disposition states: mild | basic | intense.
M.STATES = {
    trust = { "Acceptance", "Trust", "Admiration" },
    sadness = { "Pensiveness", "Sadness", "Grief" },
    anger = { "Annoyance", "Anger", "Rage" },
    distaste = { "Boredom", "Distaste", "Loathing" },
    fear = { "Anxiety", "Fear", "Terror" },
    surprise = { "Distraction", "Surprise", "Awe" },
    joy = { "Contentment", "Joy", "Ecstasy" },
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

M.STATE_INDEX = {}
for disposition, states in pairs(M.STATES) do
    M.STATE_INDEX[disposition] = { disposition = disposition, severity = M.SEVERITY.BASIC }
    for severity, label in ipairs(states) do
        M.STATE_INDEX[label:lower()] = { disposition = disposition, severity = severity }
    end
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
    },
    distaste = {
        name = "Distaste",
        description = "Dismissive and contemptuous. May ignore or insult.",
        combatLikelihood = 0.4,
        negotiable = true,
        banterDifficulty = 0,
    },
    sadness = {
        name = "Sadness",
        description = "Melancholy and withdrawn. May be susceptible to sympathy.",
        combatLikelihood = 0.2,
        negotiable = true,
        banterDifficulty = 2,    -- Harder to banter (they don't care)
    },
    joy = {
        name = "Joy",
        description = "Happy and generous. Most likely to negotiate or help.",
        combatLikelihood = 0.1,
        negotiable = true,
        banterDifficulty = 2,    -- Harder to banter (good mood)
    },
    surprise = {
        name = "Surprise",
        description = "Startled and uncertain. Reactions are unpredictable.",
        combatLikelihood = 0.5,
        negotiable = true,
        banterDifficulty = 0,
    },
    trust = {
        name = "Trust",
        description = "Open and believing. May reveal information or provide aid.",
        combatLikelihood = 0.1,
        negotiable = true,
        banterDifficulty = 4,    -- Very hard to banter (they trust you)
    },
    fear = {
        name = "Fear",
        description = "Frightened and defensive. May flee or submit.",
        combatLikelihood = 0.3,  -- Might fight from desperation
        negotiable = true,
        banterDifficulty = 0,
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

local function normalizeText(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:lower():gsub("^%s+", ""):gsub("%s+$", "")
end

function M.normalizeSeverity(severity, fallback)
    fallback = fallback or M.SEVERITY.BASIC

    if type(severity) == "string" then
        local normalized = normalizeText(severity)
        if normalized == "mild" or normalized == "weak" or normalized == "low" then
            return M.SEVERITY.MILD
        end
        if normalized == "basic" or normalized == "core" or normalized == "normal" then
            return M.SEVERITY.BASIC
        end
        if normalized == "intense" or normalized == "strong" or normalized == "high" then
            return M.SEVERITY.INTENSE
        end
    end

    local numeric = tonumber(severity)
    if numeric then
        return math.max(M.SEVERITY.MILD, math.min(M.SEVERITY.INTENSE, math.floor(numeric)))
    end

    return fallback
end

function M.parseDisposition(disposition, severity)
    local normalized = normalizeText(disposition)
    local indexed = M.STATE_INDEX[normalized]
    if indexed then
        return indexed.disposition, M.normalizeSeverity(severity, indexed.severity)
    end

    return M.DISPOSITIONS.DISTASTE, M.normalizeSeverity(severity)
end

function M.getDispositionLabel(disposition, severity)
    local parsedDisposition, parsedSeverity = M.parseDisposition(disposition, severity)
    local states = M.STATES[parsedDisposition]
    return states and states[parsedSeverity] or parsedDisposition
end

function M.getSeverityName(severity)
    return M.SEVERITY_NAMES[M.normalizeSeverity(severity)] or "basic"
end

--- Determine a random starting Disposition from the top minor discard.
-- Rulebook table: I-II Anger, III-IV Distaste, V-VI Sadness,
-- VII-VIII Joy, IX-X Surprise, Page-Knight Trust, Queen-King Fear.
function M.dispositionFromMinorDiscard(card)
    if not card or card.is_major then
        return nil, "minor_discard_required"
    end

    local value = tonumber(card.value)
    if not value or value < 1 or value > 14 then
        return nil, "minor_discard_required"
    end

    local disposition
    if value <= 2 then
        disposition = M.DISPOSITIONS.ANGER
    elseif value <= 4 then
        disposition = M.DISPOSITIONS.DISTASTE
    elseif value <= 6 then
        disposition = M.DISPOSITIONS.SADNESS
    elseif value <= 8 then
        disposition = M.DISPOSITIONS.JOY
    elseif value <= 10 then
        disposition = M.DISPOSITIONS.SURPRISE
    elseif value <= 12 then
        disposition = M.DISPOSITIONS.TRUST
    else
        disposition = M.DISPOSITIONS.FEAR
    end

    return disposition, M.SEVERITY.BASIC, M.getDispositionLabel(disposition, M.SEVERITY.BASIC)
end

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
    current = M.parseDisposition(current)
    target = M.parseDisposition(target)

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

--- Move a full disposition state toward a target emotion.
-- Shifting to a new emotion begins at mild severity; repeated pressure on the
-- current emotion increases severity, matching the rulebook's three-ring model.
function M.moveTowardState(current, severity, target, amount)
    local currentDisposition, currentSeverity = M.parseDisposition(current, severity)
    local targetDisposition = M.parseDisposition(target)
    amount = math.max(1, tonumber(amount) or 1)

    if currentDisposition == targetDisposition then
        return currentDisposition, M.normalizeSeverity(currentSeverity + amount, M.SEVERITY.INTENSE), "intensified"
    end

    local shifted = M.moveToward(currentDisposition, targetDisposition, amount)
    if shifted == currentDisposition then
        return currentDisposition, currentSeverity, "held"
    end

    return shifted, M.SEVERITY.MILD, "shifted"
end

function M.getSocialOutcome(disposition, severity)
    local parsedDisposition, parsedSeverity = M.parseDisposition(disposition, severity)
    local label = M.getDispositionLabel(parsedDisposition, parsedSeverity)
    local outcome = {
        disposition = parsedDisposition,
        severity = parsedSeverity,
        severityName = M.getSeverityName(parsedSeverity),
        label = label,
        negotiates = false,
        fairExchange = false,
        extraAid = false,
        concession = false,
        shouldFlee = false,
        likelyChallenge = false,
        needsAlleviation = false,
        uncertain = false,
        kind = "end_conversation",
    }

    if parsedDisposition == M.DISPOSITIONS.TRUST or parsedDisposition == M.DISPOSITIONS.JOY then
        outcome.negotiates = true
        outcome.fairExchange = true
        outcome.extraAid = parsedSeverity >= M.SEVERITY.INTENSE
        outcome.kind = outcome.extraAid and "extra_aid" or "good_faith_exchange"
    elseif parsedDisposition == M.DISPOSITIONS.FEAR then
        outcome.negotiates = true
        outcome.concession = true
        outcome.shouldFlee = parsedSeverity >= M.SEVERITY.BASIC
        outcome.kind = outcome.shouldFlee and "concession_or_flee" or "end_encounter"
    elseif parsedDisposition == M.DISPOSITIONS.SADNESS then
        outcome.negotiates = true
        outcome.needsAlleviation = true
        outcome.kind = "needs_alleviation"
    elseif parsedDisposition == M.DISPOSITIONS.SURPRISE then
        outcome.negotiates = true
        outcome.uncertain = true
        outcome.kind = "uncertain"
    elseif parsedDisposition == M.DISPOSITIONS.ANGER then
        outcome.likelyChallenge = true
        outcome.kind = "combat_risk"
    elseif parsedDisposition == M.DISPOSITIONS.DISTASTE then
        outcome.likelyChallenge = parsedSeverity >= M.SEVERITY.BASIC
        outcome.kind = outcome.likelyChallenge and "end_or_combat" or "end_conversation"
    end

    return outcome
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
    disposition = M.parseDisposition(disposition)
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
-- @param actionType string: "banter"
-- @return number: Modifier to add to difficulty
function M.getSocialModifier(disposition, actionType)
    local props = M.getProperties(disposition)
    if actionType == "banter" then
        return props.banterDifficulty or 0
    end
    return 0
end

return M
