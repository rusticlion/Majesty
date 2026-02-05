-- deck.lua
-- Deck Lifecycle Manager for Majesty
-- Ticket T1_2: Manages draw_pile, discard_pile, shuffle, draw, and discard operations

local M = {}

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
        -- S12.6: Greater/Lesser Doom classification
        isGreaterDoom = card.isGreaterDoom,
        isLesserDoom  = card.isLesserDoom,
    }
end

--------------------------------------------------------------------------------
-- S12.6: GREATER / LESSER DOOM HELPERS
-- Greater Doom: Major Arcana I-XIV (The Magician through Temperance)
-- Lesser Doom: Major Arcana XV-XXI (The Devil through The World)
--------------------------------------------------------------------------------

--- Check if a card is a Greater Doom (Major Arcana 1-14)
function M.isGreaterDoom(card)
    if not card or not card.is_major then return false end
    return card.value >= 1 and card.value <= 14
end

--- Check if a card is a Lesser Doom (Major Arcana 15-21)
function M.isLesserDoom(card)
    if not card or not card.is_major then return false end
    return card.value >= 15 and card.value <= 21
end

--- Get the Doom classification of a card
-- @param card table: The card to check
-- @return string: "greater", "lesser", or nil if not Major Arcana
function M.getDoomType(card)
    if not card or not card.is_major then return nil end
    if card.value >= 1 and card.value <= 14 then
        return "greater"
    elseif card.value >= 15 and card.value <= 21 then
        return "lesser"
    end
    return nil
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
-- Note: Random seed must be initialized via game_clock:init() before use
--------------------------------------------------------------------------------
local function fisherYatesShuffle(t)
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
    local deck = {
        draw_pile    = {},
        discard_pile = {},
        onDraw       = nil,
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
        local card = table.remove(self.draw_pile)
        if card and self.onDraw then
            self.onDraw(card)
        end
        return card
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
