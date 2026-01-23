-- minor_action_panel.lua
-- Minor Action Declaration Panel for Majesty
-- Ticket S6.4: UI for the minor action declaration loop
--
-- Shows when the combat pauses for minor action declarations.
-- Displays pending minors and Resume button.

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- COLORS
--------------------------------------------------------------------------------
M.COLORS = {
    -- Panel
    panel_bg        = { 0.10, 0.08, 0.06, 0.90 },
    panel_border    = { 0.60, 0.55, 0.45, 1.0 },

    -- Header
    header_bg       = { 0.25, 0.22, 0.18, 1.0 },
    header_text     = { 0.95, 0.85, 0.65, 1.0 },

    -- Pending list
    list_bg         = { 0.15, 0.12, 0.10, 1.0 },
    list_item       = { 0.85, 0.82, 0.75, 1.0 },
    list_item_pc    = { 0.70, 0.85, 0.70, 1.0 },
    list_empty      = { 0.50, 0.48, 0.45, 0.8 },

    -- Resume button
    button_bg       = { 0.35, 0.55, 0.35, 1.0 },
    button_hover    = { 0.45, 0.65, 0.45, 1.0 },
    button_text     = { 0.95, 0.95, 0.90, 1.0 },

    -- Dim overlay
    dim_overlay     = { 0.0, 0.0, 0.0, 0.4 },
}

--------------------------------------------------------------------------------
-- LAYOUT CONSTANTS
--------------------------------------------------------------------------------
M.PANEL_WIDTH = 280
M.PANEL_PADDING = 12
M.HEADER_HEIGHT = 36
M.LIST_ITEM_HEIGHT = 28
M.BUTTON_HEIGHT = 40
M.BUTTON_MARGIN = 10

--------------------------------------------------------------------------------
-- MINOR ACTION PANEL FACTORY
--------------------------------------------------------------------------------

--- Create a new MinorActionPanel
-- @param config table: { eventBus, challengeController }
-- @return MinorActionPanel instance
function M.createMinorActionPanel(config)
    config = config or {}

    local panel = {
        eventBus = config.eventBus or events.globalBus,
        challengeController = config.challengeController,

        -- State
        isVisible = false,
        pendingMinors = {},

        -- Layout (computed)
        x = 0,
        y = 0,
        width = M.PANEL_WIDTH,
        height = 0,

        -- Interaction
        buttonHovered = false,

        colors = M.COLORS,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function panel:init()
        -- Listen for minor window start
        self.eventBus:on(events.EVENTS.MINOR_ACTION_WINDOW, function(data)
            if data.paused then
                self:show()
            end
        end)

        -- Listen for state changes
        self.eventBus:on("challenge_state_changed", function(data)
            if data.newState == "minor_window" then
                self:show()
            elseif data.newState == "resolving_minors" or
                   data.newState == "awaiting_action" or
                   data.newState == "count_up" then
                self:hide()
            end
        end)

        -- Listen for minor action declarations
        self.eventBus:on("minor_action_declared", function(data)
            self:updatePendingList()
        end)

        self.eventBus:on("minor_action_undeclared", function(data)
            self:updatePendingList()
        end)

        -- Listen for challenge end
        self.eventBus:on(events.EVENTS.CHALLENGE_END, function()
            self:hide()
        end)
    end

    ----------------------------------------------------------------------------
    -- VISIBILITY
    ----------------------------------------------------------------------------

    function panel:show()
        self.isVisible = true
        self:updatePendingList()
        self:updateLayout()
    end

    function panel:hide()
        self.isVisible = false
        self.pendingMinors = {}
    end

    function panel:updatePendingList()
        if self.challengeController then
            self.pendingMinors = self.challengeController:getPendingMinors() or {}
        else
            self.pendingMinors = {}
        end
        self:updateLayout()
    end

    function panel:updateLayout()
        local screenW, screenH = love.graphics.getDimensions()

        -- Calculate height based on pending count
        local listHeight = math.max(1, #self.pendingMinors) * M.LIST_ITEM_HEIGHT + M.PANEL_PADDING
        self.height = M.HEADER_HEIGHT + listHeight + M.BUTTON_HEIGHT + M.BUTTON_MARGIN * 2 + M.PANEL_PADDING * 2

        -- Position on right side of screen, below combat display
        self.x = screenW - self.width - 20
        self.y = screenH / 2 - self.height / 2
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function panel:update(dt)
        -- Could add animations here
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    ----------------------------------------------------------------------------

    function panel:draw()
        if not love or not self.isVisible then return end

        local screenW, screenH = love.graphics.getDimensions()

        -- Draw dim overlay behind panel (indicates paused state)
        love.graphics.setColor(self.colors.dim_overlay)
        love.graphics.rectangle("fill", 0, 0, screenW, screenH)

        -- Panel background
        love.graphics.setColor(self.colors.panel_bg)
        love.graphics.rectangle("fill", self.x, self.y, self.width, self.height, 6, 6)

        -- Panel border
        love.graphics.setColor(self.colors.panel_border)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", self.x, self.y, self.width, self.height, 6, 6)
        love.graphics.setLineWidth(1)

        -- Header
        self:drawHeader()

        -- Pending list
        self:drawPendingList()

        -- Resume button
        self:drawResumeButton()
    end

    function panel:drawHeader()
        local headerY = self.y

        -- Header background
        love.graphics.setColor(self.colors.header_bg)
        love.graphics.rectangle("fill", self.x, headerY, self.width, M.HEADER_HEIGHT, 6, 0)

        -- Header text
        love.graphics.setColor(self.colors.header_text)
        love.graphics.printf("Waiting for Minors...", self.x, headerY + 10, self.width, "center")
    end

    function panel:drawPendingList()
        local listY = self.y + M.HEADER_HEIGHT + M.PANEL_PADDING
        local listHeight = math.max(1, #self.pendingMinors) * M.LIST_ITEM_HEIGHT

        -- List background
        love.graphics.setColor(self.colors.list_bg)
        love.graphics.rectangle("fill", self.x + M.PANEL_PADDING, listY,
                                self.width - M.PANEL_PADDING * 2, listHeight, 4, 4)

        if #self.pendingMinors == 0 then
            -- Empty state
            love.graphics.setColor(self.colors.list_empty)
            love.graphics.printf("(None declared)", self.x + M.PANEL_PADDING,
                                 listY + 6, self.width - M.PANEL_PADDING * 2, "center")
        else
            -- List pending minors
            for i, minor in ipairs(self.pendingMinors) do
                local itemY = listY + (i - 1) * M.LIST_ITEM_HEIGHT + 4

                local textColor = minor.entity.isPC and self.colors.list_item_pc or self.colors.list_item
                love.graphics.setColor(textColor)

                local text = string.format("%d. %s - %s",
                    i,
                    minor.entity.name or "?",
                    minor.action.type or "action")

                love.graphics.print(text, self.x + M.PANEL_PADDING + 8, itemY)
            end
        end
    end

    function panel:drawResumeButton()
        local btnX = self.x + M.BUTTON_MARGIN
        local btnY = self.y + self.height - M.BUTTON_HEIGHT - M.BUTTON_MARGIN
        local btnW = self.width - M.BUTTON_MARGIN * 2
        local btnH = M.BUTTON_HEIGHT

        -- Button background
        local bgColor = self.buttonHovered and self.colors.button_hover or self.colors.button_bg
        love.graphics.setColor(bgColor)
        love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 6, 6)

        -- Button border
        love.graphics.setColor(self.colors.panel_border)
        love.graphics.rectangle("line", btnX, btnY, btnW, btnH, 6, 6)

        -- Button text
        love.graphics.setColor(self.colors.button_text)
        local btnText = #self.pendingMinors > 0 and
            string.format("Resume (%d pending)", #self.pendingMinors) or
            "Resume (None)"
        love.graphics.printf(btnText, btnX, btnY + 12, btnW, "center")
    end

    ----------------------------------------------------------------------------
    -- INPUT HANDLING
    ----------------------------------------------------------------------------

    function panel:mousepressed(x, y, button)
        if not self.isVisible then return false end
        if button ~= 1 then return false end

        -- Check Resume button
        local btnX = self.x + M.BUTTON_MARGIN
        local btnY = self.y + self.height - M.BUTTON_HEIGHT - M.BUTTON_MARGIN
        local btnW = self.width - M.BUTTON_MARGIN * 2
        local btnH = M.BUTTON_HEIGHT

        if x >= btnX and x <= btnX + btnW and y >= btnY and y <= btnY + btnH then
            -- Resume button clicked
            if self.challengeController then
                self.challengeController:resumeFromMinorWindow()
            end
            return true
        end

        return false
    end

    function panel:mousemoved(x, y, dx, dy)
        if not self.isVisible then return end

        -- Check if hovering Resume button
        local btnX = self.x + M.BUTTON_MARGIN
        local btnY = self.y + self.height - M.BUTTON_HEIGHT - M.BUTTON_MARGIN
        local btnW = self.width - M.BUTTON_MARGIN * 2
        local btnH = M.BUTTON_HEIGHT

        self.buttonHovered = (x >= btnX and x <= btnX + btnW and
                              y >= btnY and y <= btnY + btnH)
    end

    function panel:keypressed(key)
        if not self.isVisible then return false end

        -- SPACE or ENTER to resume
        if key == "space" or key == "return" then
            if self.challengeController then
                self.challengeController:resumeFromMinorWindow()
            end
            return true
        end

        return false
    end

    return panel
end

return M
