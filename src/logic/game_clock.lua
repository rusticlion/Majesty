-- game_clock.lua
-- Game State and Round Manager for Majesty
-- Ticket T1_3: Tracks game phase and handles end-of-round triggers (Fool reshuffle)

local M = {}

--------------------------------------------------------------------------------
-- GLOBAL INITIALIZATION
-- Call once at game startup, before creating any decks
--------------------------------------------------------------------------------
local initialized = false

--- Initialize the random seed for the entire game
-- Must be called once before any deck shuffling occurs
-- Uses a combination of time and a high-precision counter to avoid
-- identical shuffles when multiple decks are created in the same millisecond
function M.init()
    if not initialized then
        -- Combine os.time() with os.clock() for better entropy
        local seed = os.time() + math.floor(os.clock() * 1000)
        math.randomseed(seed)
        -- Warm up the generator (first few values can be predictable)
        for _ = 1, 10 do math.random() end
        initialized = true
    end
end

--- Check if the system has been initialized
function M.isInitialized()
    return initialized
end

--------------------------------------------------------------------------------
-- PHASE CONSTANTS
--------------------------------------------------------------------------------
M.PHASES = {
    CRAWL     = 1,
    CHALLENGE = 2,
    CAMP      = 3,
    CITY      = 4,
}

M.PHASE_NAMES = {
    [1] = "Crawl",
    [2] = "Challenge",
    [3] = "Camp",
    [4] = "City",
}

--------------------------------------------------------------------------------
-- GAME CLOCK FACTORY
--------------------------------------------------------------------------------

--- Create a new GameClock instance
-- @param playerDeck Deck: The player's deck (Minor Arcana + Fool)
-- @param gmDeck Deck: The GM's deck (Major Arcana)
-- @return GameClock instance
function M.createGameClock(playerDeck, gmDeck)
    local clock = {
        currentPhase    = M.PHASES.CITY,  -- Games typically start in City phase
        pendingReshuffle = false,
        playerDeck      = playerDeck,
        gmDeck          = gmDeck,
        roundNumber     = 0,
    }

    ----------------------------------------------------------------------------
    -- PHASE MANAGEMENT
    ----------------------------------------------------------------------------

    --- Set the current game phase
    -- @param phase number: One of PHASES constants
    function clock:setPhase(phase)
        self.currentPhase = phase
        return self
    end

    --- Get the current phase
    function clock:getPhase()
        return self.currentPhase
    end

    --- Get the current phase name (for display/debugging)
    function clock:getPhaseName()
        return M.PHASE_NAMES[self.currentPhase] or "Unknown"
    end

    ----------------------------------------------------------------------------
    -- CARD DRAWN LISTENER
    -- Called whenever a card is drawn; checks for The Fool
    ----------------------------------------------------------------------------

    --- Notify the clock that a card was drawn
    -- If The Fool is drawn, sets pendingReshuffle flag
    -- @param card table: The card that was drawn
    -- @return card table: Returns the same card (for chaining/passthrough)
    function clock:onCardDrawn(card)
        if card and (card.name == "The Fool" or (card.is_major and card.value == 0)) then
            self.pendingReshuffle = true
        end
        -- Return the card unchanged - Fool's value (0) is still used for resolution
        return card
    end

    ----------------------------------------------------------------------------
    -- END OF ROUND
    -- Handles the Fool-triggered dual-deck reshuffle
    ----------------------------------------------------------------------------

    --- End the current round
    -- If The Fool was drawn this round, reshuffles both decks
    -- @return boolean: true if reshuffle occurred, false otherwise
    function clock:endRound()
        self.roundNumber = self.roundNumber + 1

        if self.pendingReshuffle then
            -- Reset both decks: move all discards back and shuffle
            if self.playerDeck then
                self.playerDeck:reset()
            end
            if self.gmDeck then
                self.gmDeck:reset()
            end

            self.pendingReshuffle = false
            return true  -- Reshuffle occurred
        end

        return false  -- No reshuffle needed
    end

    ----------------------------------------------------------------------------
    -- UTILITY
    ----------------------------------------------------------------------------

    --- Check if a reshuffle is pending
    function clock:isReshufflePending()
        return self.pendingReshuffle
    end

    --- Get current round number
    function clock:getRoundNumber()
        return self.roundNumber
    end

    --- Manually trigger reshuffle (for edge cases/testing)
    function clock:forceReshuffle()
        self.pendingReshuffle = true
        return self
    end

    return clock
end

return M
