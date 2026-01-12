-- constants.lua
-- Tarot card data structures and constant tables for Majesty
-- Ticket T1_1: Tarot Data Structures & Constants

local M = {}

--------------------------------------------------------------------------------
-- SUIT CONSTANTS (use these for logic, not string comparisons)
--------------------------------------------------------------------------------
M.SUITS = {
    SWORDS    = 1,
    PENTACLES = 2,
    CUPS      = 3,
    WANDS     = 4,
    MAJOR     = 5,  -- For major arcana cards
}

-- Reverse lookup: ID -> name (useful for display/debugging)
M.SUIT_NAMES = {
    [1] = "Swords",
    [2] = "Pentacles",
    [3] = "Cups",
    [4] = "Wands",
    [5] = "Major",
}

--------------------------------------------------------------------------------
-- FACE CARD VALUES
--------------------------------------------------------------------------------
M.FACE_VALUES = {
    PAGE   = 11,
    KNIGHT = 12,
    QUEEN  = 13,
    KING   = 14,
}

--------------------------------------------------------------------------------
-- CARD FACTORY
--------------------------------------------------------------------------------
local function createCard(name, suit, value, is_major)
    return {
        name     = name,
        suit     = suit,
        value    = value,
        is_major = is_major or false,
    }
end

--------------------------------------------------------------------------------
-- MINOR ARCANA (56 cards + The Fool = 57 cards in player deck)
--------------------------------------------------------------------------------
local function buildMinorArcana()
    local cards = {}
    local SUITS = M.SUITS
    local FACE_VALUES = M.FACE_VALUES

    -- Suit data: { suit_id, suit_name_for_cards }
    local suits = {
        { SUITS.SWORDS,    "Swords" },
        { SUITS.PENTACLES, "Pentacles" },
        { SUITS.CUPS,      "Cups" },
        { SUITS.WANDS,     "Wands" },
    }

    -- Number card names (Ace through Ten)
    local numberNames = {
        "Ace", "Two", "Three", "Four", "Five",
        "Six", "Seven", "Eight", "Nine", "Ten"
    }

    -- Face card names in order of value
    local faceCards = {
        { "Page",   FACE_VALUES.PAGE },
        { "Knight", FACE_VALUES.KNIGHT },
        { "Queen",  FACE_VALUES.QUEEN },
        { "King",   FACE_VALUES.KING },
    }

    -- Build all 56 suited cards
    for _, suitData in ipairs(suits) do
        local suitId, suitName = suitData[1], suitData[2]

        -- Number cards (Ace = 1 through Ten = 10)
        for value = 1, 10 do
            local name = numberNames[value] .. " of " .. suitName
            cards[#cards + 1] = createCard(name, suitId, value, false)
        end

        -- Face cards
        for _, faceData in ipairs(faceCards) do
            local faceName, faceValue = faceData[1], faceData[2]
            local name = faceName .. " of " .. suitName
            cards[#cards + 1] = createCard(name, suitId, faceValue, false)
        end
    end

    -- The Fool (value 0, belongs with minor arcana in player deck)
    cards[#cards + 1] = createCard("The Fool", SUITS.MAJOR, 0, true)

    return cards
end

--------------------------------------------------------------------------------
-- MAJOR ARCANA (21 cards, I-XXI, used by GM)
--------------------------------------------------------------------------------
local function buildMajorArcana()
    local cards = {}
    local SUITS = M.SUITS

    -- Major Arcana names in order (I through XXI)
    -- Note: The Fool (0) is NOT included here; it's in the minor arcana deck
    local majorNames = {
        "The Magician",         -- I
        "The High Priestess",   -- II
        "The Empress",          -- III
        "The Emperor",          -- IV
        "The Hierophant",       -- V
        "The Lovers",           -- VI
        "The Chariot",          -- VII
        "Strength",             -- VIII
        "The Hermit",           -- IX
        "Wheel of Fortune",     -- X
        "Justice",              -- XI
        "The Hanged Man",       -- XII
        "Death",                -- XIII
        "Temperance",           -- XIV
        "The Devil",            -- XV
        "The Tower",            -- XVI
        "The Star",             -- XVII
        "The Moon",             -- XVIII
        "The Sun",              -- XIX
        "Judgement",            -- XX
        "The World",            -- XXI
    }

    for i, name in ipairs(majorNames) do
        cards[#cards + 1] = createCard(name, SUITS.MAJOR, i, true)
    end

    return cards
end

--------------------------------------------------------------------------------
-- EXPORT CONSTANT TABLES
--------------------------------------------------------------------------------
M.MinorArcana = buildMinorArcana()  -- 57 cards (56 suited + The Fool)
M.MajorArcana = buildMajorArcana()  -- 21 cards (I-XXI)

return M
