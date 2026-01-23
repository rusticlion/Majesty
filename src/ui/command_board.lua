-- command_board.lua
-- Categorized Command Board for Majesty
-- Ticket S6.2: Suit-grouped grid of actions
--
-- Displays a grid of actions organized by suit when a card is selected.
-- Enforces suit restrictions during Minor Action windows.

local events = require('logic.events')
local action_registry = require('data.action_registry')

local M = {}

--------------------------------------------------------------------------------
-- COLORS
--------------------------------------------------------------------------------
M.COLORS = {
    -- Background
    board_bg        = { 0.15, 0.12, 0.10, 0.95 },
    board_border    = { 0.40, 0.35, 0.30, 1.0 },

    -- Column headers
    header_swords   = { 0.65, 0.25, 0.25, 1.0 },
    header_pentacles= { 0.25, 0.55, 0.30, 1.0 },
    header_cups     = { 0.25, 0.40, 0.70, 1.0 },
    header_wands    = { 0.70, 0.50, 0.20, 1.0 },
    header_misc     = { 0.45, 0.42, 0.40, 1.0 },
    header_text     = { 0.95, 0.92, 0.88, 1.0 },

    -- Action buttons
    button_enabled  = { 0.30, 0.28, 0.25, 1.0 },
    button_disabled = { 0.20, 0.18, 0.16, 0.6 },
    button_hover    = { 0.40, 0.38, 0.35, 1.0 },
    button_selected = { 0.50, 0.45, 0.30, 1.0 },
    button_border   = { 0.50, 0.45, 0.40, 1.0 },
    button_text     = { 0.90, 0.88, 0.82, 1.0 },
    button_text_dis = { 0.50, 0.48, 0.45, 0.6 },

    -- Tooltip
    tooltip_bg      = { 0.10, 0.08, 0.06, 0.95 },
    tooltip_border  = { 0.60, 0.55, 0.45, 1.0 },
    tooltip_text    = { 0.95, 0.92, 0.85, 1.0 },
    tooltip_value   = { 0.90, 0.80, 0.40, 1.0 },
}

--------------------------------------------------------------------------------
-- LAYOUT CONSTANTS
--------------------------------------------------------------------------------
M.COLUMN_WIDTH = 130
M.HEADER_HEIGHT = 30
M.BUTTON_HEIGHT = 36
M.BUTTON_PADDING = 4
M.BOARD_PADDING = 12
M.TOOLTIP_WIDTH = 220
M.TOOLTIP_LINE_HEIGHT = 18

--------------------------------------------------------------------------------
-- COMMAND BOARD FACTORY
--------------------------------------------------------------------------------

--- Create a new CommandBoard
-- @param config table: { eventBus, challengeController }
-- @return CommandBoard instance
function M.createCommandBoard(config)
    config = config or {}

    local board = {
        eventBus = config.eventBus or events.globalBus,
        challengeController = config.challengeController,

        -- State
        isVisible = false,
        selectedCard = nil,
        selectedEntity = nil,
        isPrimaryTurn = true,  -- vs Minor Window

        -- Layout
        x = 0,
        y = 0,
        width = 0,
        height = 0,

        -- Interaction
        hoveredAction = nil,
        buttons = {},  -- { action, x, y, width, height, enabled }

        -- Colors
        colors = M.COLORS,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function board:init()
        -- Listen for card selection
        self.eventBus:on("card_selected", function(data)
            if data.card and data.entity then
                self:show(data.card, data.entity, data.isPrimaryTurn)
            end
        end)

        -- Listen for card deselection
        self.eventBus:on("card_deselected", function()
            self:hide()
        end)

        -- Listen for challenge state changes
        self.eventBus:on("challenge_state_changed", function(data)
            if data.newState == "minor_window" then
                self.isPrimaryTurn = false
            elseif data.newState == "awaiting_action" then
                self.isPrimaryTurn = true
            end
        end)

        -- Listen for challenge end
        self.eventBus:on(events.EVENTS.CHALLENGE_END, function()
            self:hide()
        end)
    end

    ----------------------------------------------------------------------------
    -- VISIBILITY
    ----------------------------------------------------------------------------

    --- Show the command board for a selected card
    function board:show(card, entity, isPrimaryTurn)
        self.isVisible = true
        self.selectedCard = card
        self.selectedEntity = entity
        self.isPrimaryTurn = isPrimaryTurn ~= false  -- Default true

        -- Calculate position (center of screen area)
        local screenW, screenH = love.graphics.getDimensions()
        local numColumns = 5  -- Swords, Pentacles, Cups, Wands, Misc
        self.width = numColumns * M.COLUMN_WIDTH + M.BOARD_PADDING * 2 + (numColumns - 1) * M.BUTTON_PADDING
        self.height = self:calculateHeight()
        self.x = (screenW - self.width) / 2
        self.y = (screenH - self.height) / 2 - 50  -- Slightly above center

        -- Build button layout
        self:buildButtons()
    end

    function board:hide()
        self.isVisible = false
        self.selectedCard = nil
        self.selectedEntity = nil
        self.hoveredAction = nil
        self.buttons = {}
    end

    --- Calculate total board height based on max column length
    function board:calculateHeight()
        local maxActions = 0
        local suits = { action_registry.SUITS.SWORDS, action_registry.SUITS.PENTACLES,
                        action_registry.SUITS.CUPS, action_registry.SUITS.WANDS,
                        action_registry.SUITS.MISC }

        for _, suit in ipairs(suits) do
            local actions = action_registry.getActionsForSuit(suit)
            maxActions = math.max(maxActions, #actions)
        end

        return M.BOARD_PADDING * 2 + M.HEADER_HEIGHT +
               maxActions * (M.BUTTON_HEIGHT + M.BUTTON_PADDING) + M.BUTTON_PADDING
    end

    --- Build the button layout
    function board:buildButtons()
        self.buttons = {}

        local suits = {
            { id = action_registry.SUITS.SWORDS, name = "Swords", color = self.colors.header_swords },
            { id = action_registry.SUITS.PENTACLES, name = "Pentacles", color = self.colors.header_pentacles },
            { id = action_registry.SUITS.CUPS, name = "Cups", color = self.colors.header_cups },
            { id = action_registry.SUITS.WANDS, name = "Wands", color = self.colors.header_wands },
            { id = action_registry.SUITS.MISC, name = "Misc", color = self.colors.header_misc },
        }

        local cardSuit = action_registry.cardSuitToActionSuit(self.selectedCard.suit)

        for col, suitInfo in ipairs(suits) do
            local colX = self.x + M.BOARD_PADDING + (col - 1) * (M.COLUMN_WIDTH + M.BUTTON_PADDING)
            local actions = action_registry.getActionsForSuit(suitInfo.id)

            -- Column is enabled if:
            -- 1. It's the primary turn (all columns enabled)
            -- 2. It's minor window AND this column matches the card's suit
            local columnEnabled = self.isPrimaryTurn or (suitInfo.id == cardSuit)

            -- Misc column is disabled during minor window
            if suitInfo.id == action_registry.SUITS.MISC and not self.isPrimaryTurn then
                columnEnabled = false
            end

            for i, action in ipairs(actions) do
                local btnY = self.y + M.BOARD_PADDING + M.HEADER_HEIGHT + M.BUTTON_PADDING +
                             (i - 1) * (M.BUTTON_HEIGHT + M.BUTTON_PADDING)

                local enabled = columnEnabled
                local disabledReason = nil

                -- Additional requirements check
                -- S13: Check for weapon in hands with proper type matching
                if enabled and action.requiresWeaponType then
                    local entity = self.selectedEntity
                    local hasRequiredWeapon = false

                    -- Check inventory hands for weapons
                    if entity and entity.inventory then
                        local weapon = entity.inventory:getWieldedWeapon()
                        if weapon then
                            if action.requiresWeaponType == "ranged" then
                                hasRequiredWeapon = weapon.isRanged == true
                            elseif action.requiresWeaponType == "melee" then
                                hasRequiredWeapon = weapon.isMelee == true or (weapon.isWeapon and not weapon.isRanged)
                            else
                                hasRequiredWeapon = weapon.weaponType == action.requiresWeaponType
                            end
                        end
                    end

                    if not hasRequiredWeapon then
                        enabled = false
                        disabledReason = "Requires " .. action.requiresWeaponType .. " weapon in hands"
                    end
                end

                -- S12.2: Ranged restriction when engaged
                if enabled and action.isRanged then
                    local entity = self.selectedEntity
                    if entity and entity.is_engaged then
                        enabled = false
                        disabledReason = "Cannot use ranged weapons while engaged"
                    end
                end

                self.buttons[#self.buttons + 1] = {
                    action = action,
                    x = colX,
                    y = btnY,
                    width = M.COLUMN_WIDTH,
                    height = M.BUTTON_HEIGHT,
                    enabled = enabled,
                    disabledReason = disabledReason,  -- S12.2: Tooltip for why disabled
                    suitColor = suitInfo.color,
                }
            end

            -- Store column header info
            self.buttons["header_" .. col] = {
                x = colX,
                y = self.y + M.BOARD_PADDING,
                width = M.COLUMN_WIDTH,
                height = M.HEADER_HEIGHT,
                name = suitInfo.name,
                color = suitInfo.color,
                enabled = columnEnabled,
            }
        end
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function board:update(dt)
        -- Animation updates if needed
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    ----------------------------------------------------------------------------

    function board:draw()
        if not love or not self.isVisible then return end

        -- Draw board background
        love.graphics.setColor(self.colors.board_bg)
        love.graphics.rectangle("fill", self.x, self.y, self.width, self.height, 8, 8)

        -- Draw board border
        love.graphics.setColor(self.colors.board_border)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", self.x, self.y, self.width, self.height, 8, 8)
        love.graphics.setLineWidth(1)

        -- Draw title
        love.graphics.setColor(self.colors.header_text)
        local title = self.isPrimaryTurn and "Choose Action (Primary Turn)" or "Choose Minor Action"
        love.graphics.printf(title, self.x, self.y - 25, self.width, "center")

        -- Draw column headers
        for i = 1, 5 do
            local header = self.buttons["header_" .. i]
            if header then
                self:drawColumnHeader(header)
            end
        end

        -- Draw action buttons
        for _, btn in ipairs(self.buttons) do
            if btn.action then
                self:drawActionButton(btn)
            end
        end

        -- Draw tooltip
        if self.hoveredAction then
            self:drawTooltip()
        end
    end

    --- Draw a column header
    function board:drawColumnHeader(header)
        local alpha = header.enabled and 1.0 or 0.4

        -- Header background
        love.graphics.setColor(header.color[1], header.color[2], header.color[3], alpha)
        love.graphics.rectangle("fill", header.x, header.y, header.width, header.height, 4, 4)

        -- Header text
        love.graphics.setColor(self.colors.header_text[1], self.colors.header_text[2],
                               self.colors.header_text[3], alpha)
        love.graphics.printf(header.name, header.x, header.y + 7, header.width, "center")
    end

    --- Draw an action button
    function board:drawActionButton(btn)
        local isHovered = (self.hoveredAction == btn.action)

        -- Button background
        local bgColor
        if not btn.enabled then
            bgColor = self.colors.button_disabled
        elseif isHovered then
            bgColor = self.colors.button_hover
        else
            bgColor = self.colors.button_enabled
        end
        love.graphics.setColor(bgColor)
        love.graphics.rectangle("fill", btn.x, btn.y, btn.width, btn.height, 4, 4)

        -- Button border (tinted by suit)
        if btn.enabled then
            love.graphics.setColor(btn.suitColor[1], btn.suitColor[2], btn.suitColor[3], 0.8)
        else
            love.graphics.setColor(self.colors.button_border[1], self.colors.button_border[2],
                                   self.colors.button_border[3], 0.3)
        end
        love.graphics.setLineWidth(btn.enabled and 2 or 1)
        love.graphics.rectangle("line", btn.x, btn.y, btn.width, btn.height, 4, 4)
        love.graphics.setLineWidth(1)

        -- Button text
        local textColor = btn.enabled and self.colors.button_text or self.colors.button_text_dis
        love.graphics.setColor(textColor)

        -- Truncate name if too long
        local displayName = btn.action.name
        if #displayName > 14 then
            displayName = displayName:sub(1, 12) .. ".."
        end
        love.graphics.printf(displayName, btn.x + 4, btn.y + 10, btn.width - 8, "center")
    end

    --- Draw tooltip for hovered action
    function board:drawTooltip()
        local action = self.hoveredAction
        local button = self.hoveredButton
        if not action then return end

        local mx, my = love.mouse.getPosition()

        -- Build tooltip content
        local lines = {}
        lines[#lines + 1] = { text = action.name, color = self.colors.tooltip_text }
        lines[#lines + 1] = { text = "", color = self.colors.tooltip_text }  -- Spacer
        lines[#lines + 1] = { text = action.description, color = self.colors.tooltip_text, wrap = true }

        -- S12.2: Show disabled reason if action is blocked
        if button and not button.enabled and button.disabledReason then
            lines[#lines + 1] = { text = "", color = self.colors.tooltip_text }  -- Spacer
            lines[#lines + 1] = { text = "UNAVAILABLE:", color = { 0.9, 0.3, 0.3, 1.0 } }
            lines[#lines + 1] = { text = button.disabledReason, color = { 0.9, 0.5, 0.5, 1.0 }, wrap = true }
        end

        -- Calculate total value (only for enabled actions)
        if button and button.enabled then
            if action.attribute and self.selectedEntity then
                lines[#lines + 1] = { text = "", color = self.colors.tooltip_text }  -- Spacer
                local cardVal = self.selectedCard.value or 0
                local attrVal = self.selectedEntity[action.attribute] or 0
                local total = cardVal + attrVal
                local attrName = action.attribute:sub(1, 1):upper() .. action.attribute:sub(2)
                local calcText = string.format("Card (%d) + %s (%d) = %d", cardVal, attrName, attrVal, total)
                lines[#lines + 1] = { text = calcText, color = self.colors.tooltip_value }
            elseif not action.attribute then
                lines[#lines + 1] = { text = "", color = self.colors.tooltip_text }
                lines[#lines + 1] = { text = "Face value only", color = self.colors.tooltip_value }
            end
        end

        -- Calculate tooltip height
        local tooltipHeight = M.BOARD_PADDING * 2
        for _, line in ipairs(lines) do
            if line.wrap then
                -- Estimate wrapped text height
                local textWidth = M.TOOLTIP_WIDTH - M.BOARD_PADDING * 2
                local _, wrappedLines = love.graphics.getFont():getWrap(line.text, textWidth)
                tooltipHeight = tooltipHeight + #wrappedLines * M.TOOLTIP_LINE_HEIGHT
            else
                tooltipHeight = tooltipHeight + M.TOOLTIP_LINE_HEIGHT
            end
        end

        -- Position tooltip (avoid going off screen)
        local tooltipX = mx + 15
        local tooltipY = my + 15
        local screenW, screenH = love.graphics.getDimensions()

        if tooltipX + M.TOOLTIP_WIDTH > screenW then
            tooltipX = mx - M.TOOLTIP_WIDTH - 5
        end
        if tooltipY + tooltipHeight > screenH then
            tooltipY = my - tooltipHeight - 5
        end

        -- Draw tooltip background
        love.graphics.setColor(self.colors.tooltip_bg)
        love.graphics.rectangle("fill", tooltipX, tooltipY, M.TOOLTIP_WIDTH, tooltipHeight, 4, 4)

        -- Draw tooltip border
        love.graphics.setColor(self.colors.tooltip_border)
        love.graphics.rectangle("line", tooltipX, tooltipY, M.TOOLTIP_WIDTH, tooltipHeight, 4, 4)

        -- Draw tooltip text
        local textY = tooltipY + M.BOARD_PADDING
        for _, line in ipairs(lines) do
            love.graphics.setColor(line.color)
            if line.wrap then
                love.graphics.printf(line.text, tooltipX + M.BOARD_PADDING, textY,
                                     M.TOOLTIP_WIDTH - M.BOARD_PADDING * 2, "left")
                local _, wrappedLines = love.graphics.getFont():getWrap(line.text, M.TOOLTIP_WIDTH - M.BOARD_PADDING * 2)
                textY = textY + #wrappedLines * M.TOOLTIP_LINE_HEIGHT
            else
                love.graphics.print(line.text, tooltipX + M.BOARD_PADDING, textY)
                textY = textY + M.TOOLTIP_LINE_HEIGHT
            end
        end
    end

    ----------------------------------------------------------------------------
    -- INPUT HANDLING
    ----------------------------------------------------------------------------

    function board:mousepressed(x, y, button)
        if not self.isVisible then return false end
        if button ~= 1 then return false end

        -- Check if clicking on a button
        for _, btn in ipairs(self.buttons) do
            if btn.action and btn.enabled then
                if x >= btn.x and x <= btn.x + btn.width and
                   y >= btn.y and y <= btn.y + btn.height then
                    -- Emit action selection
                    self.eventBus:emit("action_selected", {
                        action = btn.action,
                        card = self.selectedCard,
                        entity = self.selectedEntity,
                        isPrimaryTurn = self.isPrimaryTurn,
                    })
                    self:hide()
                    return true
                end
            end
        end

        -- Clicking outside hides the board
        if x < self.x or x > self.x + self.width or
           y < self.y or y > self.y + self.height then
            self:hide()
            return true
        end

        return false
    end

    function board:mousemoved(x, y, dx, dy)
        if not self.isVisible then return end

        -- Update hovered action (including disabled ones for tooltip)
        self.hoveredAction = nil
        self.hoveredButton = nil  -- S12.2: Track full button for disabled reason
        for _, btn in ipairs(self.buttons) do
            if btn.action then
                if x >= btn.x and x <= btn.x + btn.width and
                   y >= btn.y and y <= btn.y + btn.height then
                    self.hoveredAction = btn.action
                    self.hoveredButton = btn
                    break
                end
            end
        end
    end

    function board:keypressed(key)
        if not self.isVisible then return false end

        -- ESC to close
        if key == "escape" then
            self:hide()
            return true
        end

        return false
    end

    return board
end

return M
