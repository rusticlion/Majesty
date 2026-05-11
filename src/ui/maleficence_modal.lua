-- maleficence_modal.lua
-- Passive presentation for resolved sorcery maleficence.

local events = require('logic.events')

local M = {}

M.COLORS = {
    backdrop = { 0.03, 0.02, 0.02, 0.72 },
    panel_bg = { 0.13, 0.08, 0.07, 0.97 },
    panel_border = { 0.62, 0.34, 0.26, 1.0 },
    title = { 0.96, 0.86, 0.74, 1.0 },
    text = { 0.86, 0.80, 0.72, 1.0 },
    dim_text = { 0.62, 0.56, 0.50, 1.0 },
    accent = { 0.86, 0.45, 0.34, 1.0 },
    button_bg = { 0.28, 0.18, 0.15, 1.0 },
    button_hover = { 0.40, 0.24, 0.19, 1.0 },
    button_text = { 0.94, 0.88, 0.80, 1.0 },
}

M.WIDTH = 560
M.HEIGHT = 360
M.PADDING = 22
M.BUTTON_WIDTH = 120
M.BUTTON_HEIGHT = 38

local function titleCase(value)
    value = tostring(value or "")
    return (value:gsub("^%l", string.upper))
end

local function count(items)
    if type(items) ~= "table" then
        return 0
    end
    return #items
end

function M.createMaleficenceModal(config)
    config = config or {}

    local modal = {
        eventBus = config.eventBus or events.globalBus,
        isVisible = false,
        result = nil,
        x = 0,
        y = 0,
        closeButtonBounds = nil,
        hoveredButton = nil,
        colors = M.COLORS,
    }

    function modal:init()
        self.eventBus:on(events.EVENTS.MALEFICENCE_RESOLVED, function(data)
            self:show(data)
        end)
    end

    function modal:show(result)
        if not result then
            return
        end

        self.result = result
        local sw, sh = 800, 600
        if love and love.graphics then
            sw, sh = love.graphics.getDimensions()
        end

        self.x = (sw - M.WIDTH) / 2
        self.y = (sh - M.HEIGHT) / 2
        self.isVisible = true
    end

    function modal:hide()
        self.isVisible = false
        self.result = nil
        self.closeButtonBounds = nil
        self.hoveredButton = nil
    end

    function modal:draw()
        if not self.isVisible or not love then
            return
        end

        local result = self.result or {}
        local entry = result.entry or {}
        local card = result.card or {}
        local sw, sh = love.graphics.getDimensions()

        love.graphics.setColor(self.colors.backdrop)
        love.graphics.rectangle("fill", 0, 0, sw, sh)

        love.graphics.setColor(self.colors.panel_bg)
        love.graphics.rectangle("fill", self.x, self.y, M.WIDTH, M.HEIGHT, 8, 8)

        love.graphics.setColor(self.colors.panel_border)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", self.x, self.y, M.WIDTH, M.HEIGHT, 8, 8)
        love.graphics.setLineWidth(1)

        local contentX = self.x + M.PADDING
        local contentW = M.WIDTH - M.PADDING * 2
        local y = self.y + M.PADDING

        love.graphics.setColor(self.colors.title)
        love.graphics.printf("Maleficence", contentX, y, contentW, "center")
        y = y + 34

        love.graphics.setColor(self.colors.accent)
        local branch = titleCase(result.branch)
        local rank = result.rank or "?"
        local cardName = card.name or ("Value " .. tostring(card.value or "?"))
        love.graphics.printf(branch .. " " .. rank .. " - " .. (entry.title or "Unstable Magic"),
            contentX, y, contentW, "center")
        y = y + 30

        love.graphics.setColor(self.colors.dim_text)
        love.graphics.printf("Draw: " .. cardName, contentX, y, contentW, "center")
        y = y + 34

        love.graphics.setColor(self.colors.text)
        love.graphics.printf(entry.summary or result.description or "Magic goes wrong.",
            contentX, y, contentW, "left")
        y = y + 92

        local automated = count(result.effects)
        local pending = count(result.unappliedEffects) + count(result.gmAdjudicationHooks)
        love.graphics.setColor(self.colors.dim_text)
        local detail = string.format("Automated effects: %d    GM adjudication hooks: %d", automated, pending)
        love.graphics.printf(detail, contentX, y, contentW, "left")

        self:drawCloseButton()
    end

    function modal:drawCloseButton()
        local buttonX = self.x + M.WIDTH - M.PADDING - M.BUTTON_WIDTH
        local buttonY = self.y + M.HEIGHT - M.PADDING - M.BUTTON_HEIGHT
        local isHover = self.hoveredButton == "close"

        love.graphics.setColor(isHover and self.colors.button_hover or self.colors.button_bg)
        love.graphics.rectangle("fill", buttonX, buttonY, M.BUTTON_WIDTH, M.BUTTON_HEIGHT, 4, 4)

        love.graphics.setColor(self.colors.panel_border)
        love.graphics.rectangle("line", buttonX, buttonY, M.BUTTON_WIDTH, M.BUTTON_HEIGHT, 4, 4)

        love.graphics.setColor(self.colors.button_text)
        love.graphics.printf("Continue", buttonX, buttonY + 11, M.BUTTON_WIDTH, "center")

        self.closeButtonBounds = {
            x = buttonX,
            y = buttonY,
            w = M.BUTTON_WIDTH,
            h = M.BUTTON_HEIGHT,
        }
    end

    function modal:mousepressed(x, y, button)
        if not self.isVisible or button ~= 1 then
            return false
        end

        local bounds = self.closeButtonBounds
        if bounds and x >= bounds.x and x <= bounds.x + bounds.w and
            y >= bounds.y and y <= bounds.y + bounds.h then
            self:hide()
            return true
        end

        return true
    end

    function modal:mousemoved(x, y)
        if not self.isVisible then
            return false
        end

        self.hoveredButton = nil
        local bounds = self.closeButtonBounds
        if bounds and x >= bounds.x and x <= bounds.x + bounds.w and
            y >= bounds.y and y <= bounds.y + bounds.h then
            self.hoveredButton = "close"
        end

        return true
    end

    function modal:keypressed(key)
        if not self.isVisible then
            return false
        end

        if key == "escape" or key == "return" or key == "space" then
            self:hide()
            return true
        end

        return true
    end

    return modal
end

return M
