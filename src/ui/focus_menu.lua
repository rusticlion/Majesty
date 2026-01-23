-- focus_menu.lua
-- Focus Menu (Scrutiny UI) for Majesty
-- Ticket T2_13: Menu for choosing scrutiny focus actions
--
-- Design:
-- - Appears near mouse when POI is clicked
-- - Populated from POI's scrutiny verbs (T2_8)
-- - Locks UI until choice is made or menu closed
-- - Triggers time penalty animation on choice

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- DEFAULT STYLES
--------------------------------------------------------------------------------
M.STYLES = {
    background      = { 0.15, 0.15, 0.18, 0.95 },
    border          = { 0.4, 0.4, 0.45, 1.0 },
    button_normal   = { 0.2, 0.2, 0.25, 1.0 },
    button_hover    = { 0.3, 0.5, 0.6, 1.0 },
    button_pressed  = { 0.2, 0.4, 0.5, 1.0 },
    text_normal     = { 0.9, 0.9, 0.85, 1.0 },
    text_hover      = { 1.0, 1.0, 1.0, 1.0 },
    title           = { 0.7, 0.85, 1.0, 1.0 },
}

--------------------------------------------------------------------------------
-- FOCUS MENU FACTORY
--------------------------------------------------------------------------------

--- Create a new FocusMenu
-- @param config table: { inputManager, roomManager, eventBus, font }
-- @return FocusMenu instance
function M.createFocusMenu(config)
    config = config or {}

    local menu = {
        -- References
        inputManager = config.inputManager,
        roomManager  = config.roomManager,
        eventBus     = config.eventBus or events.globalBus,

        -- Font
        font = config.font,

        -- State
        isOpen       = false,
        x            = 0,
        y            = 0,
        width        = 200,
        height       = 0,  -- Calculated based on options

        -- Current POI
        poiId        = nil,
        poiData      = nil,
        roomId       = nil,

        -- Menu options
        options      = {},  -- Array of { verb, description, callback }
        hoveredIndex = nil,
        pressedIndex = nil,

        -- Visual
        styles       = config.styles or M.STYLES,
        buttonHeight = config.buttonHeight or 32,
        padding      = config.padding or 8,
        titleHeight  = config.titleHeight or 28,

        -- Animation
        animationTime = 0,
        fadeIn        = true,
        fadeAlpha     = 0,
    }

    ----------------------------------------------------------------------------
    -- OPENING / CLOSING
    ----------------------------------------------------------------------------

    --- Open the menu for a POI
    -- @param poiId string: The POI identifier
    -- @param poiData table: POI data (from feature)
    -- @param roomId string: Current room
    -- @param screenX, screenY number: Where to position menu
    function menu:open(poiId, poiData, roomId, screenX, screenY)
        self.isOpen = true
        self.poiId = poiId
        self.poiData = poiData
        self.roomId = roomId

        -- Position menu near click, but keep on screen
        self.x = screenX
        self.y = screenY

        -- Get scrutiny verbs from room manager
        self.options = {}
        if self.roomManager then
            local verbs = self.roomManager:getScrutinyVerbs(poiData)
            for i, verbData in ipairs(verbs) do
                self.options[i] = {
                    verb = verbData.verb,
                    description = verbData.desc or verbData.description or verbData.verb,
                    callback = function()
                        self:selectOption(verbData.verb)
                    end,
                }
            end
        end

        -- Add "Cancel" option
        self.options[#self.options + 1] = {
            verb = "cancel",
            description = "Cancel",
            callback = function()
                self:close()
            end,
        }

        -- Calculate height based on options
        self.height = self.titleHeight + (self.buttonHeight * #self.options) + (self.padding * 2)

        -- Adjust position to keep on screen
        self:clampToScreen()

        -- Lock UI
        if self.inputManager then
            self.inputManager:lockUI(self)
        end

        -- Reset animation
        self.animationTime = 0
        self.fadeIn = true
        self.fadeAlpha = 0

        -- Emit event
        self.eventBus:emit(events.EVENTS.MENU_OPENED, {
            menuType = "focus",
            poiId = poiId,
        })
    end

    --- Close the menu
    function menu:close()
        if not self.isOpen then return end

        self.isOpen = false
        self.poiId = nil
        self.poiData = nil
        self.options = {}
        self.hoveredIndex = nil

        -- Unlock UI
        if self.inputManager then
            self.inputManager:unlockUI()
        end

        -- Emit event
        self.eventBus:emit(events.EVENTS.MENU_CLOSED, {
            menuType = "focus",
        })
    end

    --- Keep menu on screen
    function menu:clampToScreen()
        if not love then return end

        local screenW, screenH = love.graphics.getDimensions()

        -- Clamp X
        if self.x + self.width > screenW then
            self.x = screenW - self.width - 10
        end
        if self.x < 10 then
            self.x = 10
        end

        -- Clamp Y
        if self.y + self.height > screenH then
            self.y = screenH - self.height - 10
        end
        if self.y < 10 then
            self.y = 10
        end
    end

    ----------------------------------------------------------------------------
    -- SELECTION
    ----------------------------------------------------------------------------

    --- Handle option selection
    function menu:selectOption(verb)
        if verb == "cancel" then
            self:close()
            return
        end

        -- Get POI info at scrutiny level
        local result = nil
        if self.roomManager then
            result = self.roomManager:getPOIInfo(self.roomId, self.poiId, "scrutinize", verb)
        end

        -- Emit selection event
        self.eventBus:emit(events.EVENTS.SCRUTINY_SELECTED, {
            poiId = self.poiId,
            roomId = self.roomId,
            verb = verb,
            result = result,
        })

        -- Close menu
        self:close()
    end

    ----------------------------------------------------------------------------
    -- INPUT HANDLING
    ----------------------------------------------------------------------------

    --- Handle mouse press
    function menu:onMousePressed(x, y, button)
        if not self.isOpen or button ~= 1 then return false end

        -- Check if click is inside menu
        if not self:isPointInside(x, y) then
            self:close()
            return true
        end

        -- Check which button was pressed
        local index = self:getButtonAt(x, y)
        if index then
            self.pressedIndex = index
        end

        return true  -- Consumed the input
    end

    --- Handle mouse release
    function menu:onMouseReleased(x, y, button)
        if not self.isOpen or button ~= 1 then return false end

        local index = self:getButtonAt(x, y)

        -- If released on same button that was pressed, activate it
        if index and index == self.pressedIndex then
            local option = self.options[index]
            if option and option.callback then
                option.callback()
            end
        end

        self.pressedIndex = nil
        return true
    end

    --- Handle mouse movement
    function menu:onMouseMoved(x, y)
        if not self.isOpen then return end

        self.hoveredIndex = self:getButtonAt(x, y)
    end

    --- Check if point is inside menu
    function menu:isPointInside(x, y)
        return x >= self.x and x <= self.x + self.width and
               y >= self.y and y <= self.y + self.height
    end

    --- Get button index at position
    function menu:getButtonAt(x, y)
        if not self:isPointInside(x, y) then
            return nil
        end

        -- Check each button
        local buttonY = self.y + self.titleHeight + self.padding
        for i, _ in ipairs(self.options) do
            if y >= buttonY and y < buttonY + self.buttonHeight then
                return i
            end
            buttonY = buttonY + self.buttonHeight
        end

        return nil
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    --- Update the menu
    function menu:update(dt)
        if not self.isOpen then return end

        -- Fade in animation
        if self.fadeIn then
            self.animationTime = self.animationTime + dt
            self.fadeAlpha = math.min(1.0, self.animationTime * 5)  -- Fade in over 0.2s

            if self.fadeAlpha >= 1.0 then
                self.fadeIn = false
            end
        end
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    ----------------------------------------------------------------------------

    --- Draw the menu
    function menu:draw()
        if not self.isOpen or not love then return end

        local alpha = self.fadeAlpha

        -- Draw background with border
        love.graphics.setColor(
            self.styles.background[1],
            self.styles.background[2],
            self.styles.background[3],
            self.styles.background[4] * alpha
        )
        love.graphics.rectangle("fill", self.x, self.y, self.width, self.height, 4, 4)

        love.graphics.setColor(
            self.styles.border[1],
            self.styles.border[2],
            self.styles.border[3],
            self.styles.border[4] * alpha
        )
        love.graphics.rectangle("line", self.x, self.y, self.width, self.height, 4, 4)

        -- Draw title
        local title = self.poiData and self.poiData.name or "Scrutinize"
        love.graphics.setColor(
            self.styles.title[1],
            self.styles.title[2],
            self.styles.title[3],
            alpha
        )

        local oldFont = love.graphics.getFont()
        if self.font then
            love.graphics.setFont(self.font)
        end

        love.graphics.printf(
            title,
            self.x + self.padding,
            self.y + self.padding,
            self.width - self.padding * 2,
            "center"
        )

        -- Draw buttons
        local buttonY = self.y + self.titleHeight + self.padding
        for i, option in ipairs(self.options) do
            local isHovered = (i == self.hoveredIndex)
            local isPressed = (i == self.pressedIndex)

            -- Button background
            local bgColor = self.styles.button_normal
            if isPressed then
                bgColor = self.styles.button_pressed
            elseif isHovered then
                bgColor = self.styles.button_hover
            end

            love.graphics.setColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] * alpha)
            love.graphics.rectangle(
                "fill",
                self.x + self.padding,
                buttonY,
                self.width - self.padding * 2,
                self.buttonHeight - 2,
                2, 2
            )

            -- Button text
            local textColor = isHovered and self.styles.text_hover or self.styles.text_normal
            love.graphics.setColor(textColor[1], textColor[2], textColor[3], alpha)
            love.graphics.printf(
                option.description,
                self.x + self.padding * 2,
                buttonY + (self.buttonHeight - 16) / 2,
                self.width - self.padding * 4,
                "left"
            )

            buttonY = buttonY + self.buttonHeight
        end

        -- Restore font
        if oldFont then
            love.graphics.setFont(oldFont)
        end
    end

    return menu
end

return M
