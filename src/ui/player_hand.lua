-- player_hand.lua
-- Player Hand Management for Majesty
-- Ticket S4.8: Interactive card play with visible hand
--
-- Each PC has a hand of 4 cards at the start of a round.
-- 1 card is used for initiative, leaving 3 for actions.
-- Players select cards from their hand to perform actions.
--
-- Suit -> Action mapping (p. 111-115):
-- - SWORDS: Attack (melee requires engagement, missile uses ammo)
-- - PENTACLES: Roughhouse (Trip, Disarm, Displace)
-- - WANDS: Banter (attacks Morale)
-- - CUPS: Aid Another, Heal, support actions

local events = require('logic.events')
local constants = require('constants')

local M = {}

--------------------------------------------------------------------------------
-- HAND SIZE CONSTANTS
--------------------------------------------------------------------------------
M.FULL_HAND_SIZE = 4      -- Cards drawn at start of round
M.COMBAT_HAND_SIZE = 3    -- Cards remaining after initiative

--------------------------------------------------------------------------------
-- ACTION MAPPING BY SUIT
--------------------------------------------------------------------------------
M.SUIT_ACTIONS = {
    [constants.SUITS.SWORDS] = {
        primary = "attack",
        options = { "melee", "missile", "riposte" },
        description = "Offense - strike and pressure",
    },
    [constants.SUITS.PENTACLES] = {
        primary = "roughhouse",
        options = { "avoid", "dash", "dodge", "trip", "disarm", "displace", "grapple" },
        description = "Avoid & Roughhouse - mobility and control",
    },
    [constants.SUITS.WANDS] = {
        primary = "banter",
        options = { "banter", "cast", "recover", "investigate", "detect_magic" },
        description = "Wands - magic and insight",
    },
    [constants.SUITS.CUPS] = {
        primary = "aid",
        options = { "heal", "aid", "shield", "pull_item", "use_item" },
        description = "Support - sustain and prepare",
    },
}

--------------------------------------------------------------------------------
-- PLAYER HAND FACTORY
--------------------------------------------------------------------------------

--- Create a new PlayerHand manager
-- @param config table: { eventBus, playerDeck, guild }
-- @return PlayerHand instance
function M.createPlayerHand(config)
    config = config or {}

    local hand = {
        eventBus   = config.eventBus or events.globalBus,
        playerDeck = config.playerDeck,
        guild      = config.guild or {},

        -- Hand state per PC: pcId -> { cards = {}, initiativeCard = nil }
        hands = {},

        -- Currently selected card (for action)
        selectedCard = nil,
        selectedCardIndex = nil,
        selectedPC = nil,

        -- UI state
        hoveredCardIndex = nil,
        isDragging = false,
        dragCard = nil,
        dragX = 0,
        dragY = 0,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function hand:init()
        -- Listen for round start to draw hands
        self.eventBus:on("initiative_phase_start", function(data)
            self:drawAllHands()
        end)

        -- Listen for challenge end to discard all hands
        self.eventBus:on(events.EVENTS.CHALLENGE_END, function(data)
            self:discardAllHands()
        end)

        -- Discard remaining cards at end of each round
        self.eventBus:on(events.EVENTS.CHALLENGE_ROUND_END, function(data)
            self:discardAllHands()
        end)
    end

    ----------------------------------------------------------------------------
    -- HAND MANAGEMENT
    ----------------------------------------------------------------------------

    --- Draw full hands for all PCs at start of round
    function hand:drawAllHands()
        for _, pc in ipairs(self.guild) do
            self:drawHand(pc)
        end
        print("[PlayerHand] Drew hands for " .. #self.guild .. " PCs")
    end

    --- Draw a full hand for a specific PC
    function hand:drawHand(pc)
        if not pc or not pc.id then return end
        if not self.playerDeck then return end

        self.hands[pc.id] = {
            cards = {},
            initiativeCard = nil,
        }

        -- Draw FULL_HAND_SIZE cards
        for _ = 1, M.FULL_HAND_SIZE do
            local card = self.playerDeck:draw()
            if card then
                self.hands[pc.id].cards[#self.hands[pc.id].cards + 1] = card
            end
        end

        print("[PlayerHand] " .. pc.name .. " drew " .. #self.hands[pc.id].cards .. " cards")
    end

    --- Discard all hands back to deck
    function hand:discardAllHands()
        for pcId, handData in pairs(self.hands) do
            -- Discard remaining cards
            for _, card in ipairs(handData.cards) do
                if self.playerDeck then
                    self.playerDeck:discard(card)
                end
            end
            -- Discard initiative card if still held
            if handData.initiativeCard and self.playerDeck then
                self.playerDeck:discard(handData.initiativeCard)
            end
        end
        self.hands = {}
        self.selectedCard = nil
        self.selectedCardIndex = nil
        self.selectedPC = nil
        print("[PlayerHand] Discarded all hands")
    end

    --- Get a PC's current hand
    function hand:getHand(pc)
        if not pc or not pc.id then return {} end
        local handData = self.hands[pc.id]
        return handData and handData.cards or {}
    end

    --- Get card count for a PC
    function hand:getCardCount(pc)
        return #self:getHand(pc)
    end

    ----------------------------------------------------------------------------
    -- INITIATIVE CARD MANAGEMENT
    ----------------------------------------------------------------------------

    --- Use a card from hand for initiative
    -- @param pc table: The PC
    -- @param cardIndex number: Index in hand (1-4)
    -- @return table|nil: The card used, or nil if invalid
    function hand:useForInitiative(pc, cardIndex)
        local handData = self.hands[pc.id]
        if not handData then return nil end

        local cards = handData.cards
        if cardIndex < 1 or cardIndex > #cards then return nil end

        -- Remove card from hand and store as initiative
        local card = table.remove(cards, cardIndex)
        handData.initiativeCard = card

        print("[PlayerHand] " .. pc.name .. " used " .. card.name .. " for initiative")
        return card
    end

    --- Get the initiative card a PC submitted
    function hand:getInitiativeCard(pc)
        local handData = self.hands[pc.id]
        return handData and handData.initiativeCard
    end

    ----------------------------------------------------------------------------
    -- CARD SELECTION FOR ACTIONS
    ----------------------------------------------------------------------------

    --- Select a card from a PC's hand
    -- @param pc table: The PC
    -- @param cardIndex number: Index in hand (1-3)
    -- @return boolean: success
    function hand:selectCard(pc, cardIndex)
        local cards = self:getHand(pc)
        if cardIndex < 1 or cardIndex > #cards then
            return false
        end

        self.selectedPC = pc
        self.selectedCardIndex = cardIndex
        self.selectedCard = cards[cardIndex]

        self.eventBus:emit("card_selected", {
            pc = pc,
            card = self.selectedCard,
            cardIndex = cardIndex,
            suitActions = M.SUIT_ACTIONS[self.selectedCard.suit],
        })

        print("[PlayerHand] " .. pc.name .. " selected: " .. self.selectedCard.name)
        return true
    end

    --- Clear card selection
    function hand:clearSelection()
        self.selectedPC = nil
        self.selectedCardIndex = nil
        self.selectedCard = nil

        self.eventBus:emit("card_deselected", {})
    end

    --- Use the selected card for an action (removes from hand)
    -- @return table|nil: The card used
    function hand:useSelectedCard()
        if not self.selectedPC or not self.selectedCardIndex then
            return nil
        end

        local handData = self.hands[self.selectedPC.id]
        if not handData then return nil end

        local card = table.remove(handData.cards, self.selectedCardIndex)

        -- Discard the used card
        if self.playerDeck then
            self.playerDeck:discard(card)
        end

        local usedCard = self.selectedCard
        self:clearSelection()

        print("[PlayerHand] Used card: " .. usedCard.name)
        return usedCard
    end

    --- Get the currently selected card
    function hand:getSelectedCard()
        return self.selectedCard
    end

    --- Check if a card is selected
    function hand:hasSelection()
        return self.selectedCard ~= nil
    end

    ----------------------------------------------------------------------------
    -- SUIT HELPERS
    ----------------------------------------------------------------------------

    --- Get valid actions for a card's suit
    function hand:getActionsForCard(card)
        if not card or not card.suit then
            return nil
        end
        return M.SUIT_ACTIONS[card.suit]
    end

    --- Check if a card can be used for a specific action type
    function hand:canUseForAction(card, actionType)
        local suitActions = self:getActionsForCard(card)
        if not suitActions then return false end

        for _, opt in ipairs(suitActions.options) do
            if opt == actionType then
                return true
            end
        end
        return false
    end

    --- Get the primary action for a card's suit
    function hand:getPrimaryAction(card)
        local suitActions = self:getActionsForCard(card)
        return suitActions and suitActions.primary
    end

    ----------------------------------------------------------------------------
    -- QUERIES
    ----------------------------------------------------------------------------

    function hand:getSelectedPC()
        return self.selectedPC
    end

    function hand:getSelectedCardIndex()
        return self.selectedCardIndex
    end

    --- Get suit name for display
    function hand:getSuitName(suit)
        if suit == constants.SUITS.SWORDS then return "Swords"
        elseif suit == constants.SUITS.PENTACLES then return "Pentacles"
        elseif suit == constants.SUITS.CUPS then return "Cups"
        elseif suit == constants.SUITS.WANDS then return "Wands"
        else return "Major Arcana"
        end
    end

    return hand
end

return M
