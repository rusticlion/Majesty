-- deck.lua
-- Deck Lifecycle Manager for Majesty
-- Ticket T1_2: Manages draw_pile, discard_pile, shuffle, draw, and discard operations

local M = {}

--------------------------------------------------------------------------------
-- RANDOM SEED (call once at startup)
--------------------------------------------------------------------------------
local seeded = false

local function ensureSeeded()
    if not seeded then
        math.randomseed(os.time())
        seeded = true
    end
end

--------------------------------------------------------------------------------
-- DEEP COPY HELPER
-- Prevents the "reference trap" where modifying a drawn card affects the registry
--------------------------------------------------------------------------------
local function deepCopyCard(card)
    return {
        name     = card.name,
        suit     = card.suit,
        value    = card.value,
        is_major = card.is_major,
    }
end

local function deepCopyCards(cards)
    local copy = {}
    for i, card in ipairs(cards) do
        copy[i] = deepCopyCard(card)
    end
    return copy
end

--------------------------------------------------------------------------------
-- FISHER-YATES SHUFFLE (in-place)
--------------------------------------------------------------------------------
local function fisherYatesShuffle(t)
    ensureSeeded()
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

--------------------------------------------------------------------------------
-- DECK FACTORY
--------------------------------------------------------------------------------

--- Create a new Deck instance
-- @param cards table: Array of card data from constants.lua (MinorArcana or MajorArcana)
-- @return Deck instance with draw_pile, discard_pile, and methods
function M.createDeck(cards)
    ensureSeeded()

    local deck = {
        draw_pile    = {},
        discard_pile = {},
    }

    -- Deep copy cards into draw pile (avoid reference trap)
    if cards and #cards > 0 then
        deck.draw_pile = deepCopyCards(cards)
    end

    ----------------------------------------------------------------------------
    -- SHUFFLE: Randomize the draw pile in-place
    ----------------------------------------------------------------------------
    function deck:shuffle()
        fisherYatesShuffle(self.draw_pile)
        return self
    end

    ----------------------------------------------------------------------------
    -- DRAW: Remove and return the top card from draw pile
    -- Auto-reshuffles discard into draw pile if draw pile is empty
    ----------------------------------------------------------------------------
    function deck:draw()
        -- If draw pile is empty, check discard pile
        if #self.draw_pile == 0 then
            if #self.discard_pile == 0 then
                -- Both piles empty, nothing to draw
                return nil
            end

            -- Move discard pile to draw pile and shuffle
            self.draw_pile = self.discard_pile
            self.discard_pile = {}
            self:shuffle()
        end

        -- Remove and return top card (last element for O(1) removal)
        return table.remove(self.draw_pile)
    end

    ----------------------------------------------------------------------------
    -- DISCARD: Move a card to the discard pile
    ----------------------------------------------------------------------------
    function deck:discard(card)
        if card then
            self.discard_pile[#self.discard_pile + 1] = card
        end
        return self
    end

    ----------------------------------------------------------------------------
    -- UTILITY: Get counts for debugging/UI
    ----------------------------------------------------------------------------
    function deck:drawPileCount()
        return #self.draw_pile
    end

    function deck:discardPileCount()
        return #self.discard_pile
    end

    function deck:totalCards()
        return #self.draw_pile + #self.discard_pile
    end

    ----------------------------------------------------------------------------
    -- UTILITY: Peek at top of discard pile (some rules check this)
    ----------------------------------------------------------------------------
    function deck:peekDiscard()
        if #self.discard_pile == 0 then
            return nil
        end
        return self.discard_pile[#self.discard_pile]
    end

    ----------------------------------------------------------------------------
    -- RESET: Return all cards to draw pile and shuffle (full reshuffle)
    ----------------------------------------------------------------------------
    function deck:reset()
        -- Move all discarded cards back to draw pile
        for i = 1, #self.discard_pile do
            self.draw_pile[#self.draw_pile + 1] = self.discard_pile[i]
        end
        self.discard_pile = {}
        self:shuffle()
        return self
    end

    return deck
end

--------------------------------------------------------------------------------
-- CONVENIENCE CONSTRUCTORS
--------------------------------------------------------------------------------

--- Create the Player's Deck (Minor Arcana + The Fool)
-- @param constants table: The constants module from constants.lua
function M.createPlayerDeck(constants)
    local deck = M.createDeck(constants.MinorArcana)
    deck:shuffle()
    return deck
end

--- Create the GM's Deck (Major Arcana, I-XXI)
-- @param constants table: The constants module from constants.lua
function M.createGMDeck(constants)
    local deck = M.createDeck(constants.MajorArcana)
    deck:shuffle()
    return deck
end

return M
