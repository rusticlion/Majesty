-- test_of_fate_modal.lua
-- Test of Fate Modal for Majesty Crawl Phase
-- Ticket S12.5: Push fate mechanic, favor/disfavor, great success/failure
--
-- Displays a Test of Fate with:
-- - Card drawn and result
-- - Option to Push Fate (costs 1 Resolve)
-- - Consequences of success/failure

local events = require('logic.events')
local resolver = require('logic.resolver')

local M = {}

--------------------------------------------------------------------------------
-- COLORS
--------------------------------------------------------------------------------
M.COLORS = {
    -- Modal
    bg = { 0.12, 0.10, 0.08, 0.95 },
    border = { 0.50, 0.45, 0.35, 1.0 },
    title = { 0.95, 0.90, 0.80, 1.0 },
    text = { 0.85, 0.82, 0.75, 1.0 },

    -- Results
    success = { 0.30, 0.70, 0.30, 1.0 },
    great_success = { 0.90, 0.80, 0.20, 1.0 },
    failure = { 0.70, 0.35, 0.30, 1.0 },
    great_failure = { 0.90, 0.20, 0.20, 1.0 },

    -- Buttons
    button_bg = { 0.25, 0.22, 0.18, 1.0 },
    button_hover = { 0.35, 0.30, 0.25, 1.0 },
    button_disabled = { 0.18, 0.16, 0.14, 0.6 },
    button_text = { 0.90, 0.88, 0.82, 1.0 },
    button_text_disabled = { 0.50, 0.48, 0.45, 0.6 },

    -- Card display
    card_bg = { 0.20, 0.18, 0.15, 1.0 },
    card_border = { 0.60, 0.55, 0.45, 1.0 },
}

--------------------------------------------------------------------------------
-- LAYOUT
--------------------------------------------------------------------------------
M.WIDTH = 400
M.HEIGHT = 350
M.PADDING = 20
M.BUTTON_HEIGHT = 40
M.BUTTON_WIDTH = 120

--------------------------------------------------------------------------------
-- MODAL FACTORY
--------------------------------------------------------------------------------

--- Create a Test of Fate Modal
-- @param config table: { eventBus, deck }
-- @return TestOfFateModal instance
function M.createTestOfFateModal(config)
    config = config or {}

    local modal = {
        eventBus = config.eventBus or events.globalBus,
        deck = config.deck,

        -- State
        isVisible = false,

        -- Test data
        testConfig = nil,     -- { attribute, difficulty, entity, ... }
        initialCard = nil,    -- First card drawn
        pushCard = nil,       -- Second card (if pushed)
        result = nil,         -- resolver result

        -- UI state
        x = 0,
        y = 0,
        hoverButton = nil,

        -- Colors
        colors = M.COLORS,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function modal:init()
        -- Listen for test requests
        self.eventBus:on("request_test_of_fate", function(data)
            self:startTest(data)
        end)
    end

    ----------------------------------------------------------------------------
    -- TEST FLOW
    ----------------------------------------------------------------------------

    local function getResolve(entity)
        if not entity then return 0 end
        if type(entity.resolve) == "table" then
            return entity.resolve.current or 0
        end
        return entity.resolve or 0
    end

    local function spendResolve(entity, amount)
        if not entity then return false end
        amount = amount or 1

        if entity.spendResolve then
            return entity:spendResolve(amount)
        end

        if type(entity.resolve) == "table" then
            if (entity.resolve.current or 0) < amount then
                return false
            end
            entity.resolve.current = entity.resolve.current - amount
            return true
        end

        if type(entity.resolve) == "number" then
            if entity.resolve < amount then
                return false
            end
            entity.resolve = entity.resolve - amount
            return true
        end

        return false
    end

    --- Start a Test of Fate
    -- @param config table: { attribute, difficulty, entity, favor, description, onSuccess, onFailure }
    function modal:startTest(config)
        if not config or not config.entity then return end

        self.testConfig = config
        self.pushCard = nil
        self.result = nil

        -- Draw initial card from deck (minor arcana)
        if self.deck then
            self.initialCard = self.deck:draw()
        else
            -- Fallback: simulate a card
            self.initialCard = { name = "Test Card", value = math.random(1, 14), suit = math.random(1, 4) }
        end

        -- Resolve initial test
        local attribute = config.entity[config.attribute] or 2
        local targetSuit = config.targetSuit or self.initialCard.suit
        self.result = resolver.resolveTest(attribute, targetSuit, self.initialCard, config.favor)

        -- Center on screen
        local sw, sh = 800, 600
        if love and love.graphics then
            sw, sh = love.graphics.getDimensions()
        end
        self.x = (sw - M.WIDTH) / 2
        self.y = (sh - M.HEIGHT) / 2

        self.isVisible = true
    end

    --- Push Fate (spend Resolve to try again)
    function modal:pushFate()
        if not self.testConfig or not self.result then return end
        if not resolver.canPush(self.result) then return end

        local entity = self.testConfig.entity

        -- Check if entity has Resolve to spend
        if getResolve(entity) > 0 and spendResolve(entity, 1) then

            -- Draw push card
            if self.deck then
                self.pushCard = self.deck:draw()
            else
                self.pushCard = { name = "Push Card", value = math.random(1, 14), suit = math.random(1, 4) }
            end

            -- Resolve push
            self.result = resolver.resolvePush(self.result.total, self.result.cards, self.pushCard)

            -- Emit push event
            self.eventBus:emit("test_fate_pushed", {
                entity = entity,
                pushCard = self.pushCard,
                result = self.result,
            })
        end
    end

    --- Accept the result and close
    function modal:acceptResult()
        if not self.testConfig or not self.result then
            self:hide()
            return
        end

        -- Emit result event
        self.eventBus:emit("test_of_fate_complete", {
            config = self.testConfig,
            result = self.result,
            entity = self.testConfig.entity,
        })

        -- Call callbacks
        if self.result.success then
            if self.testConfig.onSuccess then
                self.testConfig.onSuccess(self.result)
            end
        else
            if self.testConfig.onFailure then
                self.testConfig.onFailure(self.result)
            end
        end

        self:hide()
    end

    function modal:discardDrawnCards()
        if not self.deck or not self.deck.discard then return end

        if self.initialCard then
            self.deck:discard(self.initialCard)
            self.initialCard = nil
        end
        if self.pushCard then
            self.deck:discard(self.pushCard)
            self.pushCard = nil
        end
    end

    function modal:hide()
        self:discardDrawnCards()
        self.isVisible = false
        self.testConfig = nil
        self.result = nil
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    ----------------------------------------------------------------------------

    function modal:draw()
        if not self.isVisible or not love then return end

        -- Draw dimmed background
        local sw, sh = love.graphics.getDimensions()
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", 0, 0, sw, sh)

        -- Draw modal background
        love.graphics.setColor(self.colors.bg)
        love.graphics.rectangle("fill", self.x, self.y, M.WIDTH, M.HEIGHT, 8, 8)

        -- Draw border
        love.graphics.setColor(self.colors.border)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", self.x, self.y, M.WIDTH, M.HEIGHT, 8, 8)
        love.graphics.setLineWidth(1)

        -- Draw title
        love.graphics.setColor(self.colors.title)
        local title = "Test of Fate"
        if self.testConfig and self.testConfig.description then
            title = self.testConfig.description
        end
        love.graphics.printf(title, self.x + M.PADDING, self.y + M.PADDING, M.WIDTH - M.PADDING * 2, "center")

        -- Draw attribute being tested
        if self.testConfig and self.testConfig.attribute then
            love.graphics.setColor(self.colors.text)
            local attrText = string.format("Testing: %s", self.testConfig.attribute:upper())
            love.graphics.printf(attrText, self.x + M.PADDING, self.y + 50, M.WIDTH - M.PADDING * 2, "center")
        end

        -- Draw card(s)
        local cardY = self.y + 80
        self:drawCard(self.initialCard, self.x + M.WIDTH/2 - 50, cardY, "Initial Draw")

        if self.pushCard then
            self:drawCard(self.pushCard, self.x + M.WIDTH/2 + 10, cardY, "Push")
        end

        -- Draw result
        if self.result then
            self:drawResult()
        end

        -- Draw buttons
        self:drawButtons()
    end

    function modal:drawCard(card, x, y, label)
        if not card then return end

        local cardW, cardH = 80, 100

        -- Card background
        love.graphics.setColor(self.colors.card_bg)
        love.graphics.rectangle("fill", x, y, cardW, cardH, 4, 4)

        -- Card border
        love.graphics.setColor(self.colors.card_border)
        love.graphics.rectangle("line", x, y, cardW, cardH, 4, 4)

        -- Card value
        love.graphics.setColor(self.colors.title)
        love.graphics.printf(tostring(card.value or "?"), x, y + 30, cardW, "center")

        -- Card name (if major arcana)
        if card.is_major and card.name then
            love.graphics.setColor(self.colors.text)
            love.graphics.printf(card.name, x + 2, y + 55, cardW - 4, "center")
        end

        -- Label
        love.graphics.setColor(self.colors.text)
        love.graphics.printf(label or "", x, y + cardH + 5, cardW, "center")
    end

    function modal:drawResult()
        local resultY = self.y + 200
        local resultColor = self.colors.text
        local resultText = "Unknown"

        if self.result.result == resolver.RESULTS.SUCCESS then
            resultColor = self.colors.success
            resultText = "SUCCESS"
        elseif self.result.result == resolver.RESULTS.GREAT_SUCCESS then
            resultColor = self.colors.great_success
            resultText = "GREAT SUCCESS!"
        elseif self.result.result == resolver.RESULTS.FAILURE then
            resultColor = self.colors.failure
            resultText = "FAILURE"
        elseif self.result.result == resolver.RESULTS.GREAT_FAILURE then
            resultColor = self.colors.great_failure
            resultText = "GREAT FAILURE!"
        end

        love.graphics.setColor(resultColor)
        love.graphics.printf(resultText, self.x + M.PADDING, resultY, M.WIDTH - M.PADDING * 2, "center")

        -- Draw total
        love.graphics.setColor(self.colors.text)
        local totalText = string.format("Total: %d (Target: %d)", self.result.total or 0, 14)
        love.graphics.printf(totalText, self.x + M.PADDING, resultY + 25, M.WIDTH - M.PADDING * 2, "center")
    end

    function modal:drawButtons()
        local buttonY = self.y + M.HEIGHT - M.BUTTON_HEIGHT - M.PADDING

        -- Push Fate button (only if can push and has Resolve)
        local canPush = self.result and resolver.canPush(self.result)
        local entity = self.testConfig and self.testConfig.entity
        local resolveCount = getResolve(entity)
        local hasResolve = resolveCount > 0
        local showPush = canPush and hasResolve and not self.pushCard

        if showPush then
            local pushX = self.x + M.PADDING
            local isHover = self.hoverButton == "push"

            love.graphics.setColor(isHover and self.colors.button_hover or self.colors.button_bg)
            love.graphics.rectangle("fill", pushX, buttonY, M.BUTTON_WIDTH, M.BUTTON_HEIGHT, 4, 4)

            love.graphics.setColor(self.colors.border)
            love.graphics.rectangle("line", pushX, buttonY, M.BUTTON_WIDTH, M.BUTTON_HEIGHT, 4, 4)

            love.graphics.setColor(self.colors.button_text)
            local pushText = string.format("Push Fate (%d)", resolveCount)
            love.graphics.printf(pushText, pushX, buttonY + 12, M.BUTTON_WIDTH, "center")

            -- Store button bounds
            self.pushButtonBounds = { x = pushX, y = buttonY, w = M.BUTTON_WIDTH, h = M.BUTTON_HEIGHT }
        else
            self.pushButtonBounds = nil
        end

        -- Accept button
        local acceptX = self.x + M.WIDTH - M.BUTTON_WIDTH - M.PADDING
        local isHover = self.hoverButton == "accept"

        love.graphics.setColor(isHover and self.colors.button_hover or self.colors.button_bg)
        love.graphics.rectangle("fill", acceptX, buttonY, M.BUTTON_WIDTH, M.BUTTON_HEIGHT, 4, 4)

        love.graphics.setColor(self.colors.border)
        love.graphics.rectangle("line", acceptX, buttonY, M.BUTTON_WIDTH, M.BUTTON_HEIGHT, 4, 4)

        love.graphics.setColor(self.colors.button_text)
        love.graphics.printf("Accept", acceptX, buttonY + 12, M.BUTTON_WIDTH, "center")

        self.acceptButtonBounds = { x = acceptX, y = buttonY, w = M.BUTTON_WIDTH, h = M.BUTTON_HEIGHT }
    end

    ----------------------------------------------------------------------------
    -- INPUT
    ----------------------------------------------------------------------------

    function modal:mousepressed(x, y, button)
        if not self.isVisible or button ~= 1 then return false end

        -- Check push button
        if self.pushButtonBounds then
            local btn = self.pushButtonBounds
            if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
                self:pushFate()
                return true
            end
        end

        -- Check accept button
        if self.acceptButtonBounds then
            local btn = self.acceptButtonBounds
            if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
                self:acceptResult()
                return true
            end
        end

        return true  -- Consume click
    end

    function modal:mousemoved(x, y)
        if not self.isVisible then return end

        self.hoverButton = nil

        if self.pushButtonBounds then
            local btn = self.pushButtonBounds
            if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
                self.hoverButton = "push"
            end
        end

        if self.acceptButtonBounds then
            local btn = self.acceptButtonBounds
            if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
                self.hoverButton = "accept"
            end
        end
    end

    function modal:keypressed(key)
        if not self.isVisible then return false end

        if key == "escape" or key == "return" then
            self:acceptResult()
            return true
        end

        if key == "p" and self.pushButtonBounds then
            self:pushFate()
            return true
        end

        return true  -- Consume key
    end

    return modal
end

return M
