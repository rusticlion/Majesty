-- resolver.lua
-- Test of Fate Resolution Logic for Majesty
-- Ticket T1_4: Pure function library for resolving Tests of Fate and Pushing Fate
--
-- This module is STATELESS - it knows nothing about Decks or Players.
-- It just takes numbers and cards and returns results.

local M = {}

--------------------------------------------------------------------------------
-- RESULT TYPES
--------------------------------------------------------------------------------
M.RESULTS = {
    SUCCESS       = "success",
    GREAT_SUCCESS = "great_success",
    FAILURE       = "failure",
    GREAT_FAILURE = "great_failure",
}

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------
local TARGET_VALUE = 14  -- Threshold for success
local FAVOR_BONUS = 3    -- Bonus/penalty for favor/disfavor

--------------------------------------------------------------------------------
-- RESULT FACTORY
-- Creates a standardized result object
--------------------------------------------------------------------------------
local function createResult(resultType, total, cards)
    local isSuccess = (resultType == M.RESULTS.SUCCESS or resultType == M.RESULTS.GREAT_SUCCESS)
    local isGreat = (resultType == M.RESULTS.GREAT_SUCCESS or resultType == M.RESULTS.GREAT_FAILURE)

    return {
        result   = resultType,
        success  = isSuccess,
        isGreat  = isGreat,
        total    = total,
        cards    = cards or {},
    }
end

--------------------------------------------------------------------------------
-- RESOLVE INITIAL TEST
-- Called when an adventurer draws a card for a Test of Fate
--
-- @param attribute number: The adventurer's attribute value (1-4)
-- @param targetSuit number: The suit being tested (from constants.SUITS)
-- @param card table: The drawn card { name, suit, value, is_major }
-- @param favor boolean|nil: true = favor (+3), false = disfavor (-3), nil = neither
-- @return Result object
--------------------------------------------------------------------------------
function M.resolveTest(attribute, targetSuit, card, favor)
    local total = card.value + attribute

    -- Apply favor/disfavor (non-cumulative, binary)
    if favor == true then
        total = total + FAVOR_BONUS
    elseif favor == false then
        total = total - FAVOR_BONUS
    end

    local cards = { card }

    if total >= TARGET_VALUE then
        -- Success! Check for Great Success
        -- Great Success requires: matching suit on INITIAL draw (not push)
        if card.suit == targetSuit then
            return createResult(M.RESULTS.GREAT_SUCCESS, total, cards)
        else
            return createResult(M.RESULTS.SUCCESS, total, cards)
        end
    else
        -- Failure (can be pushed)
        return createResult(M.RESULTS.FAILURE, total, cards)
    end
end

--------------------------------------------------------------------------------
-- RESOLVE PUSH
-- Called when an adventurer pushes fate after an initial failure
--
-- @param previousTotal number: The total from the initial test (before push)
-- @param previousCards table: Array of cards from initial test
-- @param pushCard table: The second card drawn when pushing
-- @return Result object
--
-- Rules:
-- - If pushCard is The Fool → Great Failure (automatic)
-- - If new total >= 14 → Success (NEVER Great Success)
-- - If new total < 14 → Great Failure
--------------------------------------------------------------------------------
function M.resolvePush(previousTotal, previousCards, pushCard)
    local cards = {}
    for _, c in ipairs(previousCards) do
        cards[#cards + 1] = c
    end
    cards[#cards + 1] = pushCard

    -- The Fool when pushing = automatic Great Failure
    if pushCard.name == "The Fool" then
        -- Total includes Fool's value (0), but it's still Great Failure
        local total = previousTotal + pushCard.value
        return createResult(M.RESULTS.GREAT_FAILURE, total, cards)
    end

    local total = previousTotal + pushCard.value

    if total >= TARGET_VALUE then
        -- Success (never Great Success from pushing)
        return createResult(M.RESULTS.SUCCESS, total, cards)
    else
        -- Great Failure
        return createResult(M.RESULTS.GREAT_FAILURE, total, cards)
    end
end

--------------------------------------------------------------------------------
-- UTILITY: Check if a result can be pushed
-- Only failures (not great failures) can be pushed
--------------------------------------------------------------------------------
function M.canPush(result)
    return result.result == M.RESULTS.FAILURE
end

--------------------------------------------------------------------------------
-- UTILITY: Calculate minimum card value needed for success
-- Useful for UI hints
--------------------------------------------------------------------------------
function M.minimumCardNeeded(attribute, favor)
    local bonus = 0
    if favor == true then
        bonus = FAVOR_BONUS
    elseif favor == false then
        bonus = -FAVOR_BONUS
    end
    return TARGET_VALUE - attribute - bonus
end

return M
