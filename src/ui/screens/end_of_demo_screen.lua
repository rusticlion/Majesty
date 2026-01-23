-- end_of_demo_screen.lua
-- End of Demo / City Stub Screen for Majesty
-- Ticket S10.1: Loop closure for playtesting
--
-- Displays when the party exits the dungeon or retrieves the Vellum Map.
-- Provides a "Return to City" button that resets the game for another run.

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- COLORS
--------------------------------------------------------------------------------
M.COLORS = {
    background     = { 0.08, 0.06, 0.10, 1.0 },
    title          = { 0.95, 0.85, 0.60, 1.0 },   -- Gold
    subtitle       = { 0.75, 0.70, 0.65, 1.0 },
    text           = { 0.85, 0.82, 0.78, 1.0 },
    panel_bg       = { 0.12, 0.10, 0.14, 0.95 },
    panel_border   = { 0.40, 0.35, 0.30, 1.0 },
    button_bg      = { 0.25, 0.20, 0.15, 1.0 },
    button_hover   = { 0.35, 0.30, 0.20, 1.0 },
    button_text    = { 0.95, 0.90, 0.80, 1.0 },
    stat_good      = { 0.50, 0.75, 0.45, 1.0 },   -- Green
    stat_bad       = { 0.75, 0.45, 0.45, 1.0 },   -- Red
    stat_neutral   = { 0.70, 0.65, 0.60, 1.0 },
}

--------------------------------------------------------------------------------
-- END OF DEMO SCREEN FACTORY
--------------------------------------------------------------------------------

--- Create a new EndOfDemoScreen
-- @param config table: { eventBus, guild, onReturnToCity, victoryReason }
-- @return EndOfDemoScreen instance
function M.createEndOfDemoScreen(config)
    config = config or {}

    local screen = {
        eventBus        = config.eventBus or events.globalBus,
        guild           = config.guild or {},
        onReturnToCity  = config.onReturnToCity,  -- Callback function
        victoryReason   = config.victoryReason or "completed",  -- "vellum_map", "exited", "completed"

        -- Layout
        width           = 800,
        height          = 600,

        -- Button state
        hoverButton     = nil,

        -- Colors
        colors          = M.COLORS,

        -- Animation
        fadeIn          = 0,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function screen:init()
        self.fadeIn = 0
    end

    function screen:resize(w, h)
        self.width = w
        self.height = h
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function screen:update(dt)
        -- Fade in animation
        if self.fadeIn < 1 then
            self.fadeIn = math.min(1, self.fadeIn + dt * 2)
        end
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    ----------------------------------------------------------------------------

    function screen:draw()
        if not love then return end

        local alpha = self.fadeIn

        -- Background
        love.graphics.setColor(self.colors.background[1], self.colors.background[2],
                               self.colors.background[3], alpha)
        love.graphics.rectangle("fill", 0, 0, self.width, self.height)

        -- Central panel
        local panelW = math.min(600, self.width - 60)
        local panelH = 450
        local panelX = (self.width - panelW) / 2
        local panelY = (self.height - panelH) / 2

        -- Panel background
        love.graphics.setColor(self.colors.panel_bg[1], self.colors.panel_bg[2],
                               self.colors.panel_bg[3], alpha * 0.95)
        love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 12, 12)

        -- Panel border
        love.graphics.setColor(self.colors.panel_border[1], self.colors.panel_border[2],
                               self.colors.panel_border[3], alpha)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 12, 12)
        love.graphics.setLineWidth(1)

        -- Title
        local title = self:getTitle()
        love.graphics.setColor(self.colors.title[1], self.colors.title[2],
                               self.colors.title[3], alpha)
        love.graphics.printf(title, panelX, panelY + 25, panelW, "center")

        -- Subtitle
        local subtitle = self:getSubtitle()
        love.graphics.setColor(self.colors.subtitle[1], self.colors.subtitle[2],
                               self.colors.subtitle[3], alpha)
        love.graphics.printf(subtitle, panelX, panelY + 55, panelW, "center")

        -- Separator line
        love.graphics.setColor(self.colors.panel_border[1], self.colors.panel_border[2],
                               self.colors.panel_border[3], alpha * 0.5)
        love.graphics.line(panelX + 40, panelY + 85, panelX + panelW - 40, panelY + 85)

        -- Guild summary
        self:drawGuildSummary(panelX + 20, panelY + 100, panelW - 40, alpha)

        -- City effects description
        self:drawCityEffects(panelX + 20, panelY + 280, panelW - 40, alpha)

        -- Return to City button
        self:drawReturnButton(panelX, panelY + panelH - 70, panelW, alpha)
    end

    function screen:getTitle()
        if self.victoryReason == "vellum_map" then
            return "VICTORY!"
        elseif self.victoryReason == "exited" then
            return "RETURNED TO SURFACE"
        else
            return "EXPEDITION COMPLETE"
        end
    end

    function screen:getSubtitle()
        if self.victoryReason == "vellum_map" then
            return "The Vellum Map has been retrieved!"
        elseif self.victoryReason == "exited" then
            return "The guild has escaped the dungeon."
        else
            return "The dungeon awaits another expedition."
        end
    end

    function screen:drawGuildSummary(x, y, w, alpha)
        love.graphics.setColor(self.colors.text[1], self.colors.text[2],
                               self.colors.text[3], alpha)
        love.graphics.print("EXPEDITION REPORT", x, y)

        local lineY = y + 25
        local lineH = 28

        for i, adventurer in ipairs(self.guild) do
            -- Name
            love.graphics.setColor(self.colors.text[1], self.colors.text[2],
                                   self.colors.text[3], alpha)
            love.graphics.print(adventurer.name, x + 10, lineY)

            -- Wounds status
            local woundText = self:getWoundStatus(adventurer)
            local woundColor = adventurer.conditions and
                (adventurer.conditions.dead and self.colors.stat_bad or
                 adventurer.conditions.deaths_door and self.colors.stat_bad or
                 adventurer.conditions.injured and self.colors.stat_bad or
                 self.colors.stat_good)
            love.graphics.setColor(woundColor[1], woundColor[2], woundColor[3], alpha)
            love.graphics.print(woundText, x + 150, lineY)

            -- Conditions
            local condText = self:getConditionText(adventurer)
            love.graphics.setColor(self.colors.stat_neutral[1], self.colors.stat_neutral[2],
                                   self.colors.stat_neutral[3], alpha)
            love.graphics.print(condText, x + 280, lineY)

            lineY = lineY + lineH
        end
    end

    function screen:getWoundStatus(adventurer)
        if adventurer.conditions then
            if adventurer.conditions.dead then
                return "DEAD"
            elseif adventurer.conditions.deaths_door then
                return "Death's Door!"
            elseif adventurer.conditions.injured then
                return "Injured"
            elseif adventurer.conditions.staggered then
                return "Staggered"
            end
        end
        return "Healthy"
    end

    function screen:getConditionText(adventurer)
        local conditions = {}
        if adventurer.conditions then
            if adventurer.conditions.stressed then
                conditions[#conditions + 1] = "Stressed"
            end
            if adventurer.conditions.starving then
                conditions[#conditions + 1] = "Starving"
            end
        end
        if #conditions == 0 then
            return ""
        end
        return table.concat(conditions, ", ")
    end

    function screen:drawCityEffects(x, y, w, alpha)
        love.graphics.setColor(self.colors.subtitle[1], self.colors.subtitle[2],
                               self.colors.subtitle[3], alpha)
        love.graphics.print("RETURNING TO THE CITY WILL:", x, y)

        local effects = {
            "* Heal all wounds and conditions",
            "* Deduct 50% of gold (upkeep)",
            "* Refill torches, rations, and arrows",
            "* Reset the dungeon for another run",
        }

        local lineY = y + 25
        love.graphics.setColor(self.colors.text[1], self.colors.text[2],
                               self.colors.text[3], alpha * 0.85)
        for _, effect in ipairs(effects) do
            love.graphics.print(effect, x + 10, lineY)
            lineY = lineY + 20
        end
    end

    function screen:drawReturnButton(panelX, y, panelW, alpha)
        local btnW, btnH = 200, 45
        local btnX = panelX + (panelW - btnW) / 2

        local isHover = self.hoverButton == "return"
        local btnColor = isHover and self.colors.button_hover or self.colors.button_bg

        love.graphics.setColor(btnColor[1], btnColor[2], btnColor[3], alpha)
        love.graphics.rectangle("fill", btnX, y, btnW, btnH, 6, 6)

        love.graphics.setColor(self.colors.panel_border[1], self.colors.panel_border[2],
                               self.colors.panel_border[3], alpha)
        love.graphics.rectangle("line", btnX, y, btnW, btnH, 6, 6)

        love.graphics.setColor(self.colors.button_text[1], self.colors.button_text[2],
                               self.colors.button_text[3], alpha)
        love.graphics.printf("Return to City", btnX, y + 13, btnW, "center")

        -- Store bounds
        self.returnButtonBounds = { x = btnX, y = y, w = btnW, h = btnH }
    end

    ----------------------------------------------------------------------------
    -- INPUT HANDLING
    ----------------------------------------------------------------------------

    function screen:mousepressed(x, y, button)
        if button ~= 1 then return end

        -- Check return button
        if self.returnButtonBounds then
            local btn = self.returnButtonBounds
            if x >= btn.x and x <= btn.x + btn.w and
               y >= btn.y and y <= btn.y + btn.h then
                if self.onReturnToCity then
                    self.onReturnToCity()
                end
            end
        end
    end

    function screen:mousereleased(x, y, button)
        -- Nothing
    end

    function screen:mousemoved(x, y, dx, dy)
        self.hoverButton = nil

        if self.returnButtonBounds then
            local btn = self.returnButtonBounds
            if x >= btn.x and x <= btn.x + btn.w and
               y >= btn.y and y <= btn.y + btn.h then
                self.hoverButton = "return"
            end
        end
    end

    function screen:keypressed(key)
        -- Enter or Space also triggers return
        if key == "return" or key == "space" then
            if self.onReturnToCity then
                self.onReturnToCity()
            end
        end
    end

    return screen
end

return M
