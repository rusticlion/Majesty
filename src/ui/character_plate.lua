-- character_plate.lua
-- Extended Character Plate Component for Majesty
-- Ticket S5.1: Condition glyphs, talent tray, wound flow animation
--
-- Design: "Ink on Parchment" aesthetic
-- - Muted, desaturated colors
-- - Bold strokes for mastered elements
-- - Faint sketchy lines for in-training elements
-- - Red accents only for wounds/danger

local events = require('logic.events')
local item_view = require('ui.item_view')

local M = {}

--------------------------------------------------------------------------------
-- COLORS (Ink on Parchment palette)
--------------------------------------------------------------------------------
M.COLORS = {
    -- Base inks
    ink_dark      = { 0.15, 0.12, 0.10, 1.0 },   -- Dark sepia ink
    ink_medium    = { 0.35, 0.30, 0.25, 1.0 },   -- Medium ink
    ink_faint     = { 0.55, 0.50, 0.45, 0.6 },   -- Faint pencil sketch

    -- Condition colors (muted, not saturated)
    stressed      = { 0.65, 0.55, 0.20, 1.0 },   -- Ochre/amber
    staggered     = { 0.50, 0.45, 0.55, 1.0 },   -- Muted purple
    injured       = { 0.60, 0.25, 0.20, 1.0 },   -- Dark red
    deaths_door   = { 0.45, 0.15, 0.15, 1.0 },   -- Deep crimson

    -- Talent states
    mastered      = { 0.20, 0.35, 0.50, 1.0 },   -- Deep blue ink
    training      = { 0.50, 0.48, 0.45, 0.5 },   -- Faint grey
    wounded       = { 0.55, 0.20, 0.15, 1.0 },   -- Red

    -- Highlight for wound flow animation
    highlight     = { 0.90, 0.70, 0.20, 1.0 },   -- Gold flash
    highlight_bg  = { 0.90, 0.70, 0.20, 0.3 },   -- Gold glow

    -- Bond colors (S9.1)
    bond_charged  = { 0.70, 0.55, 0.85, 1.0 },   -- Purple glow for charged
    bond_spent    = { 0.40, 0.40, 0.45, 0.5 },   -- Grey for spent

    -- Active PC highlight
    active_glow   = { 0.85, 0.75, 0.45, 1.0 },   -- Golden highlight for active PC
    active_border = { 0.90, 0.80, 0.40, 1.0 },   -- Gold border
}

--------------------------------------------------------------------------------
-- CONDITION GLYPH DEFINITIONS
-- Each condition has a draw function that renders its iconic symbol
--------------------------------------------------------------------------------
M.CONDITION_GLYPHS = {
    stressed = {
        name = "Stressed",
        draw = function(x, y, size, color)
            -- Cracked mind symbol: spiral with crack
            love.graphics.setColor(color)
            love.graphics.setLineWidth(2)

            -- Spiral
            local cx, cy = x + size/2, y + size/2
            local r = size * 0.35
            for i = 0, 8 do
                local a1 = (i / 8) * math.pi * 2
                local a2 = ((i + 1) / 8) * math.pi * 2
                local r1 = r * (1 - i * 0.08)
                local r2 = r * (1 - (i+1) * 0.08)
                love.graphics.line(
                    cx + math.cos(a1) * r1,
                    cy + math.sin(a1) * r1,
                    cx + math.cos(a2) * r2,
                    cy + math.sin(a2) * r2
                )
            end

            -- Crack through it
            love.graphics.line(cx - r*0.5, cy - r*0.3, cx + r*0.5, cy + r*0.3)
            love.graphics.line(cx + r*0.2, cy, cx + r*0.5, cy - r*0.4)

            love.graphics.setLineWidth(1)
        end,
    },

    staggered = {
        name = "Staggered",
        draw = function(x, y, size, color)
            -- Dizzy stars / vertigo symbol
            love.graphics.setColor(color)
            love.graphics.setLineWidth(1.5)

            local cx, cy = x + size/2, y + size/2

            -- Three small stars in a curve
            for i = 1, 3 do
                local angle = math.pi * 0.3 + (i - 1) * 0.5
                local dist = size * 0.25
                local sx = cx + math.cos(angle) * dist
                local sy = cy + math.sin(angle) * dist
                local starSize = size * 0.12

                -- 4-point star
                love.graphics.line(sx - starSize, sy, sx + starSize, sy)
                love.graphics.line(sx, sy - starSize, sx, sy + starSize)
            end

            -- Wavy line underneath
            love.graphics.line(
                cx - size*0.3, cy + size*0.2,
                cx - size*0.1, cy + size*0.25,
                cx + size*0.1, cy + size*0.15,
                cx + size*0.3, cy + size*0.2
            )

            love.graphics.setLineWidth(1)
        end,
    },

    injured = {
        name = "Injured",
        draw = function(x, y, size, color)
            -- Blood drop symbol
            love.graphics.setColor(color)
            love.graphics.setLineWidth(2)

            local cx, cy = x + size/2, y + size/2

            -- Teardrop/blood drop shape
            local points = {}
            local segments = 12
            for i = 0, segments do
                local t = i / segments
                local angle = math.pi * 0.5 + t * math.pi * 2
                local r = size * 0.3

                -- Modify radius for teardrop shape
                if t < 0.5 then
                    r = r * (0.3 + t * 1.4)
                else
                    r = r * (0.3 + (1 - t) * 1.4)
                end

                -- Point at top
                if i == 0 then
                    points[#points + 1] = cx
                    points[#points + 1] = cy - size * 0.35
                else
                    points[#points + 1] = cx + math.cos(angle) * r
                    points[#points + 1] = cy + math.sin(angle) * r * 0.8
                end
            end

            if #points >= 6 then
                love.graphics.polygon("line", points)
            end

            love.graphics.setLineWidth(1)
        end,
    },

    deaths_door = {
        name = "Death's Door",
        draw = function(x, y, size, color)
            -- Skull symbol (simplified)
            love.graphics.setColor(color)
            love.graphics.setLineWidth(2)

            local cx, cy = x + size/2, y + size/2

            -- Skull outline (oval)
            love.graphics.ellipse("line", cx, cy - size*0.05, size*0.3, size*0.35)

            -- Eye sockets
            love.graphics.circle("fill", cx - size*0.1, cy - size*0.1, size*0.06)
            love.graphics.circle("fill", cx + size*0.1, cy - size*0.1, size*0.06)

            -- Nose (inverted triangle)
            love.graphics.polygon("fill",
                cx, cy + size*0.02,
                cx - size*0.04, cy + size*0.12,
                cx + size*0.04, cy + size*0.12
            )

            -- Jaw line
            love.graphics.line(
                cx - size*0.15, cy + size*0.2,
                cx, cy + size*0.25,
                cx + size*0.15, cy + size*0.2
            )

            love.graphics.setLineWidth(1)
        end,
    },
}

--------------------------------------------------------------------------------
-- CHARACTER PLATE FACTORY
--------------------------------------------------------------------------------

--- Create a new CharacterPlate component
-- @param config table: { eventBus, entity, x, y, width }
-- @return CharacterPlate instance
function M.createCharacterPlate(config)
    config = config or {}

    local plate = {
        eventBus = config.eventBus or events.globalBus,
        entity   = config.entity,

        -- Position and size
        x      = config.x or 0,
        y      = config.y or 0,
        width  = config.width or 180,

        -- Layout constants
        portraitSize    = 50,
        glyphSize       = 18,
        talentDotSize   = 8,
        padding         = 6,

        -- Active PC state
        isActive = config.isActive or false,

        -- Animation state
        highlightTarget = nil,    -- "stressed", "talent_3", etc.
        highlightTimer  = 0,
        highlightDuration = 0.8,

        -- Colors
        colors = config.colors or M.COLORS,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function plate:init()
        -- Subscribe to wound events for animation
        self.eventBus:on(events.EVENTS.WOUND_TAKEN, function(data)
            if data.entity == self.entity then
                self:triggerWoundAnimation(data.result)
            end
        end)
    end

    ----------------------------------------------------------------------------
    -- SETTERS
    ----------------------------------------------------------------------------

    function plate:setEntity(entity)
        self.entity = entity
    end

    function plate:setPosition(x, y)
        self.x = x
        self.y = y
    end

    function plate:setActive(isActive)
        self.isActive = isActive
    end

    ----------------------------------------------------------------------------
    -- WOUND FLOW ANIMATION
    ----------------------------------------------------------------------------

    --- Trigger highlight animation for wound flow
    -- @param woundResult string: "armor_notched", "talent_wounded", "staggered", etc.
    function plate:triggerWoundAnimation(woundResult)
        -- Map wound result to highlight target
        if woundResult == "talent_wounded" then
            -- Highlight the next wounded talent slot
            local woundedCount = self.entity and self.entity.woundedTalents or 0
            self.highlightTarget = "talent_" .. woundedCount
        elseif woundResult == "staggered" then
            self.highlightTarget = "staggered"
        elseif woundResult == "injured" then
            self.highlightTarget = "injured"
        elseif woundResult == "deaths_door" then
            self.highlightTarget = "deaths_door"
        elseif woundResult == "armor_notched" then
            self.highlightTarget = "armor"
        end

        self.highlightTimer = self.highlightDuration
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function plate:update(dt)
        -- Update highlight animation
        if self.highlightTimer > 0 then
            self.highlightTimer = self.highlightTimer - dt
            if self.highlightTimer <= 0 then
                self.highlightTarget = nil
            end
        end

        -- S9.1: Track time for bond glow animation
        self.animTimer = (self.animTimer or 0) + dt
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    ----------------------------------------------------------------------------

    --- Draw the complete character plate
    function plate:draw()
        if not love or not self.entity then return end

        local e = self.entity
        local y = self.y

        -- Draw active PC highlight background
        if self.isActive then
            local plateHeight = self:getHeight()
            -- Subtle golden glow behind the entire plate
            love.graphics.setColor(self.colors.active_glow[1], self.colors.active_glow[2],
                                   self.colors.active_glow[3], 0.15)
            love.graphics.rectangle("fill", self.x - 4, y - 4, self.width + 8, plateHeight + 8, 4, 4)
            -- Golden border
            love.graphics.setColor(self.colors.active_border)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", self.x - 4, y - 4, self.width + 8, plateHeight + 8, 4, 4)
            love.graphics.setLineWidth(1)
        end

        -- Portrait
        self:drawPortrait(self.x, y)
        local nameX = self.x + self.portraitSize + self.padding

        -- Name
        love.graphics.setColor(self.colors.ink_dark)
        love.graphics.print(e.name or "Unknown", nameX, y + 2)

        -- Condition glyphs (row below name)
        local glyphY = y + 16
        self:drawConditionGlyphs(nameX, glyphY)

        -- S5.2: Armor pips (if entity has armor)
        if e.armorSlots and e.armorSlots > 0 then
            local armorY = glyphY + self.glyphSize + 2
            self:drawArmorPips(nameX, armorY)
        end

        -- Talent tray (below portrait)
        local talentY = y + self.portraitSize + self.padding
        self:drawTalentTray(self.x, talentY)

        -- Resolve pips (if entity has resolve)
        if e.resolve then
            local resolveY = talentY + self.talentDotSize + self.padding
            self:drawResolvePips(self.x, resolveY)
        end
    end

    --- Draw the portrait placeholder
    function plate:drawPortrait(x, y)
        local e = self.entity

        -- S9.1: Draw bond glow if has charged bonds
        local chargedBondCount = self:countChargedBonds()
        if chargedBondCount > 0 then
            -- Pulsing glow effect
            local pulseAlpha = 0.3 + math.sin((self.animTimer or 0) * 3) * 0.15
            love.graphics.setColor(self.colors.bond_charged[1], self.colors.bond_charged[2],
                                   self.colors.bond_charged[3], pulseAlpha)
            love.graphics.circle("fill", x + self.portraitSize/2, y + self.portraitSize/2,
                                self.portraitSize/2 + 8)
        end

        -- Background
        love.graphics.setColor(0.25, 0.30, 0.35, 1.0)
        love.graphics.rectangle("fill", x, y, self.portraitSize, self.portraitSize, 3, 3)

        -- Border
        love.graphics.setColor(self.colors.ink_medium)
        love.graphics.rectangle("line", x, y, self.portraitSize, self.portraitSize, 3, 3)

        -- If at death's door, add red border
        if e.conditions and e.conditions.deaths_door then
            love.graphics.setColor(self.colors.deaths_door)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", x-1, y-1, self.portraitSize+2, self.portraitSize+2, 4, 4)
            love.graphics.setLineWidth(1)
        -- S9.1: If has charged bonds, add purple border
        elseif chargedBondCount > 0 then
            love.graphics.setColor(self.colors.bond_charged)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", x-1, y-1, self.portraitSize+2, self.portraitSize+2, 4, 4)
            love.graphics.setLineWidth(1)
        end
    end

    --- Count charged bonds for this entity (S9.1)
    function plate:countChargedBonds()
        local e = self.entity
        if not e or not e.bonds then return 0 end

        local count = 0
        for _, bond in pairs(e.bonds) do
            if bond.charged then
                count = count + 1
            end
        end
        return count
    end

    --- Draw condition glyphs in a row
    function plate:drawConditionGlyphs(x, y)
        local e = self.entity
        if not e.conditions then return end

        local glyphX = x
        local glyphSpacing = self.glyphSize + 4

        -- Draw each active condition
        local conditions = { "stressed", "staggered", "injured", "deaths_door" }

        for _, condName in ipairs(conditions) do
            if e.conditions[condName] then
                local glyph = M.CONDITION_GLYPHS[condName]
                if glyph then
                    local color = self.colors[condName] or self.colors.ink_dark

                    -- Highlight background if this is the animation target
                    if self.highlightTarget == condName and self.highlightTimer > 0 then
                        local alpha = math.sin(self.highlightTimer * 10) * 0.5 + 0.5
                        love.graphics.setColor(self.colors.highlight_bg[1], self.colors.highlight_bg[2], self.colors.highlight_bg[3], alpha)
                        love.graphics.rectangle("fill", glyphX - 2, y - 2, self.glyphSize + 4, self.glyphSize + 4, 2, 2)
                    end

                    -- Draw the glyph
                    glyph.draw(glyphX, y, self.glyphSize, color)

                    glyphX = glyphX + glyphSpacing
                end
            end
        end
    end

    --- Draw the talent tray (7 dots)
    function plate:drawTalentTray(x, y)
        local e = self.entity
        local talents = e.talents or {}
        local woundedCount = e.woundedTalents or 0

        local dotSpacing = self.talentDotSize + 4
        local maxTalents = 7

        for i = 1, maxTalents do
            local dotX = x + (i - 1) * dotSpacing
            local talent = talents[i]

            -- Determine dot state
            local state = "empty"
            if talent then
                if i <= woundedCount then
                    state = "wounded"
                elseif talent.mastered then
                    state = "mastered"
                else
                    state = "training"
                end
            end

            -- Check for highlight animation
            local isHighlighted = (self.highlightTarget == "talent_" .. i) and self.highlightTimer > 0

            -- Draw the dot
            self:drawTalentDot(dotX, y, state, isHighlighted)
        end
    end

    --- Draw a single talent dot
    -- @param x, y number: Position
    -- @param state string: "empty", "mastered", "training", "wounded"
    -- @param highlighted boolean: Whether to show highlight animation
    function plate:drawTalentDot(x, y, state, highlighted)
        local size = self.talentDotSize

        -- Highlight glow
        if highlighted then
            local alpha = math.sin(self.highlightTimer * 10) * 0.5 + 0.5
            love.graphics.setColor(self.colors.highlight[1], self.colors.highlight[2], self.colors.highlight[3], alpha)
            love.graphics.circle("fill", x + size/2, y + size/2, size * 0.8)
        end

        if state == "mastered" then
            -- Solid blue ink circle
            love.graphics.setColor(self.colors.mastered)
            love.graphics.circle("fill", x + size/2, y + size/2, size/2)
            -- Dark border for definition
            love.graphics.setColor(self.colors.ink_dark)
            love.graphics.circle("line", x + size/2, y + size/2, size/2)

        elseif state == "training" then
            -- Faint grey circle (pencil sketch look)
            love.graphics.setColor(self.colors.training)
            love.graphics.circle("line", x + size/2, y + size/2, size/2)
            -- Dashed inner for "incomplete" feel
            love.graphics.setColor(self.colors.ink_faint)
            love.graphics.circle("fill", x + size/2, y + size/2, size/4)

        elseif state == "wounded" then
            -- Red X over the dot
            love.graphics.setColor(self.colors.wounded)
            love.graphics.circle("fill", x + size/2, y + size/2, size/2)
            -- X mark
            love.graphics.setColor(self.colors.ink_dark)
            love.graphics.setLineWidth(2)
            love.graphics.line(x + 2, y + 2, x + size - 2, y + size - 2)
            love.graphics.line(x + size - 2, y + 2, x + 2, y + size - 2)
            love.graphics.setLineWidth(1)

        else
            -- Empty slot (very faint outline)
            love.graphics.setColor(self.colors.ink_faint)
            love.graphics.circle("line", x + size/2, y + size/2, size/2)
        end
    end

    --- Draw armor pips (S5.2)
    function plate:drawArmorPips(x, y)
        local e = self.entity
        if not e.armorSlots or e.armorSlots <= 0 then return end

        local slots = e.armorSlots
        local notches = e.armorNotches or 0
        local pipSize = 8
        local pipSpacing = pipSize + 3

        -- Small shield icon
        love.graphics.setColor(self.colors.ink_medium)
        love.graphics.print("Armor:", x, y)

        local pipX = x + 40
        for i = 1, slots do
            if i <= notches then
                -- Notched (damaged) - red with X
                love.graphics.setColor(0.55, 0.25, 0.20, 1.0)
                love.graphics.rectangle("fill", pipX + (i-1) * pipSpacing, y + 2, pipSize, pipSize, 1, 1)
                -- X mark
                love.graphics.setColor(self.colors.ink_dark)
                love.graphics.line(
                    pipX + (i-1) * pipSpacing + 1, y + 3,
                    pipX + (i-1) * pipSpacing + pipSize - 1, y + pipSize + 1
                )
            else
                -- Intact - steel grey
                love.graphics.setColor(0.50, 0.55, 0.60, 1.0)
                love.graphics.rectangle("fill", pipX + (i-1) * pipSpacing, y + 2, pipSize, pipSize, 1, 1)
            end
            -- Border
            love.graphics.setColor(self.colors.ink_faint)
            love.graphics.rectangle("line", pipX + (i-1) * pipSpacing, y + 2, pipSize, pipSize, 1, 1)
        end
    end

    --- Draw resolve pips (if the entity has resolve)
    function plate:drawResolvePips(x, y)
        local e = self.entity
        if not e.resolve then return end

        local current = e.resolve.current or 0
        local max = e.resolve.max or 4
        local pipSize = 6
        local pipSpacing = pipSize + 3

        love.graphics.setColor(self.colors.ink_faint)
        love.graphics.print("Resolve:", x, y)

        local pipX = x + 50
        for i = 1, max do
            if i <= current then
                -- Filled pip
                love.graphics.setColor(self.colors.mastered)
                love.graphics.rectangle("fill", pipX + (i-1) * pipSpacing, y + 2, pipSize, pipSize, 1, 1)
            else
                -- Empty pip
                love.graphics.setColor(self.colors.ink_faint)
                love.graphics.rectangle("line", pipX + (i-1) * pipSpacing, y + 2, pipSize, pipSize, 1, 1)
            end
        end
    end

    --- Calculate total height of the plate
    function plate:getHeight()
        local height = self.portraitSize + self.padding
        height = height + self.talentDotSize + self.padding

        if self.entity and self.entity.resolve then
            height = height + 16  -- Resolve pips height
        end

        return height
    end

    return plate
end

return M
