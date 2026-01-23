-- combat_display.lua
-- Combat Display Component for Majesty
-- Ticket S5.3: Defense Slots & Initiative Visualization
--
-- Features:
-- - Defense slot display (facedown card when defense prepared)
-- - Initiative slot with card flip animation
-- - Active entity highlighting during count-up
-- - Combatant portraits with status

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- COLORS
--------------------------------------------------------------------------------
M.COLORS = {
    -- Card colors
    card_back       = { 0.25, 0.15, 0.30, 1.0 },   -- Deep purple
    card_border     = { 0.50, 0.40, 0.55, 1.0 },
    card_face       = { 0.90, 0.85, 0.75, 1.0 },   -- Parchment

    -- Highlight
    active_glow     = { 0.90, 0.80, 0.20, 1.0 },   -- Gold
    active_bg       = { 0.90, 0.80, 0.20, 0.3 },

    -- Defense types
    defense_dodge   = { 0.30, 0.50, 0.70, 1.0 },   -- Blue tint
    defense_riposte = { 0.70, 0.30, 0.30, 1.0 },   -- Red tint
    defense_unknown = { 0.40, 0.35, 0.45, 1.0 },   -- Neutral

    -- Text
    text_light      = { 0.90, 0.88, 0.80, 1.0 },
    text_dark       = { 0.15, 0.12, 0.10, 1.0 },

    -- Status
    pc_bg           = { 0.20, 0.35, 0.25, 1.0 },
    npc_bg          = { 0.35, 0.20, 0.20, 1.0 },
}

--------------------------------------------------------------------------------
-- ANIMATION CONSTANTS
--------------------------------------------------------------------------------
M.FLIP_DURATION = 0.4    -- Card flip animation duration
M.GLOW_SPEED = 4.0       -- Active entity glow pulse speed

--------------------------------------------------------------------------------
-- COMBAT DISPLAY FACTORY
--------------------------------------------------------------------------------

--- Create a new CombatDisplay component
-- @param config table: { eventBus, challengeController }
-- @return CombatDisplay instance
function M.createCombatDisplay(config)
    config = config or {}

    local display = {
        eventBus = config.eventBus or events.globalBus,
        controller = config.challengeController,

        -- Card flip animations: entityId -> { progress, cardData, startTime }
        flipAnimations = {},

        -- Defense reveal animations
        defenseReveals = {},

        -- Active glow timer
        glowTimer = 0,

        -- Layout
        cardWidth = 60,
        cardHeight = 84,
        portraitSize = 50,
        slotSpacing = 8,

        -- Engagement tracking (from action resolver)
        engagements = {},  -- { entityId -> { enemyId -> true } }

        colors = M.COLORS,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function display:init()
        -- Listen for initiative reveal
        self.eventBus:on("count_up_tick", function(data)
            -- Trigger flip animations for entities at this count
            self:triggerInitiativeFlips(data.count)
        end)

        -- Listen for defense prepared
        self.eventBus:on("defense_prepared", function(data)
            -- Could add visual feedback here
        end)

        -- Listen for defense triggered (dodge/riposte used)
        self.eventBus:on("riposte_hit", function(data)
            self:triggerDefenseReveal(data.defender, "riposte")
        end)

        -- Listen for engagement changes
        self.eventBus:on("engagement_formed", function(data)
            if data.entity1 and data.entity2 then
                self:addEngagement(data.entity1.id, data.entity2.id)
            end
        end)

        self.eventBus:on("engagement_broken", function(data)
            if data.entity1 and data.entity2 then
                self:removeEngagement(data.entity1.id, data.entity2.id)
            end
        end)

        -- Clear engagements when challenge ends
        self.eventBus:on(events.EVENTS.CHALLENGE_END, function(data)
            self.engagements = {}
        end)
    end

    --- Add engagement between two entities
    function display:addEngagement(id1, id2)
        self.engagements[id1] = self.engagements[id1] or {}
        self.engagements[id2] = self.engagements[id2] or {}
        self.engagements[id1][id2] = true
        self.engagements[id2][id1] = true
    end

    --- Remove engagement between two entities
    function display:removeEngagement(id1, id2)
        if self.engagements[id1] then
            self.engagements[id1][id2] = nil
        end
        if self.engagements[id2] then
            self.engagements[id2][id1] = nil
        end
    end

    --- Check if entity is engaged
    function display:isEngaged(entityId)
        local engaged = self.engagements[entityId]
        if not engaged then return false end
        for _ in pairs(engaged) do
            return true
        end
        return false
    end

    ----------------------------------------------------------------------------
    -- ANIMATION TRIGGERS
    ----------------------------------------------------------------------------

    --- Trigger initiative card flip for entities at a count
    function display:triggerInitiativeFlips(count)
        if not self.controller then return end

        local entities = self.controller:getEntitiesAtCount(count)
        for _, entity in ipairs(entities) do
            self.flipAnimations[entity.id] = {
                progress = 0,
                duration = M.FLIP_DURATION,
            }
        end
    end

    --- Trigger defense card reveal animation
    function display:triggerDefenseReveal(entity, defenseType)
        if not entity then return end

        self.defenseReveals[entity.id] = {
            progress = 0,
            duration = M.FLIP_DURATION,
            type = defenseType,
        }
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function display:update(dt)
        -- Update glow timer
        self.glowTimer = self.glowTimer + dt * M.GLOW_SPEED

        -- Update flip animations
        for id, anim in pairs(self.flipAnimations) do
            anim.progress = anim.progress + dt / anim.duration
            if anim.progress >= 1.0 then
                self.flipAnimations[id] = nil
            end
        end

        -- Update defense reveals
        for id, anim in pairs(self.defenseReveals) do
            anim.progress = anim.progress + dt / anim.duration
            if anim.progress >= 1.0 then
                self.defenseReveals[id] = nil
            end
        end
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    ----------------------------------------------------------------------------

    --- Draw a combatant row (portrait + initiative slot + defense slot)
    -- @param entity table: The combatant entity
    -- @param x, y number: Position
    -- @param isActive boolean: Whether this entity is currently active
    function display:drawCombatantRow(entity, x, y, isActive)
        if not love or not entity then return end

        local colors = self.colors

        -- Active entity glow background
        if isActive then
            local glowAlpha = math.sin(self.glowTimer) * 0.3 + 0.5
            love.graphics.setColor(
                colors.active_bg[1],
                colors.active_bg[2],
                colors.active_bg[3],
                glowAlpha
            )
            love.graphics.rectangle("fill",
                x - 4, y - 4,
                self.portraitSize + self.cardWidth * 2 + self.slotSpacing * 3 + 8,
                self.portraitSize + 8,
                4, 4
            )
        end

        -- Portrait
        self:drawPortrait(entity, x, y)

        -- Initiative slot (to the right of portrait)
        local initX = x + self.portraitSize + self.slotSpacing
        self:drawInitiativeSlot(entity, initX, y)

        -- Defense slot (to the right of initiative)
        local defX = initX + self.cardWidth + self.slotSpacing
        self:drawDefenseSlot(entity, defX, y)
    end

    --- Draw entity portrait
    function display:drawPortrait(entity, x, y)
        local colors = self.colors
        local isPC = entity.isPC

        -- Background color based on faction
        love.graphics.setColor(isPC and colors.pc_bg or colors.npc_bg)
        love.graphics.rectangle("fill", x, y, self.portraitSize, self.portraitSize, 3, 3)

        -- Border
        love.graphics.setColor(colors.card_border)
        love.graphics.rectangle("line", x, y, self.portraitSize, self.portraitSize, 3, 3)

        -- Engagement indicator (crossed swords icon in corner)
        if entity.id and self:isEngaged(entity.id) then
            -- Draw a small crossed swords indicator
            love.graphics.setColor(0.9, 0.4, 0.3, 1.0)
            local ix, iy = x + self.portraitSize - 12, y + 2
            love.graphics.setLineWidth(2)
            love.graphics.line(ix, iy, ix + 10, iy + 10)
            love.graphics.line(ix + 10, iy, ix, iy + 10)
            love.graphics.setLineWidth(1)
        end

        -- Name (truncated)
        local name = entity.name or "???"
        if #name > 6 then name = string.sub(name, 1, 5) .. "." end
        love.graphics.setColor(colors.text_light)
        love.graphics.print(name, x + 3, y + self.portraitSize - 14)

        -- Zone indicator (small text)
        if entity.zone then
            love.graphics.setColor(0.6, 0.6, 0.6, 0.8)
            local zoneText = string.sub(entity.zone, 1, 4)
            love.graphics.print(zoneText, x + 3, y + 2)
        end

        -- Death's door / dead indicator
        if entity.conditions then
            if entity.conditions.dead then
                love.graphics.setColor(0.8, 0.2, 0.2, 0.8)
                love.graphics.setLineWidth(3)
                love.graphics.line(x, y, x + self.portraitSize, y + self.portraitSize)
                love.graphics.line(x + self.portraitSize, y, x, y + self.portraitSize)
                love.graphics.setLineWidth(1)
            elseif entity.conditions.deaths_door then
                love.graphics.setColor(0.8, 0.2, 0.2, 1)
                love.graphics.setLineWidth(2)
                love.graphics.rectangle("line", x - 1, y - 1, self.portraitSize + 2, self.portraitSize + 2, 4, 4)
                love.graphics.setLineWidth(1)
            end
        end
    end

    --- Draw initiative slot
    function display:drawInitiativeSlot(entity, x, y)
        local colors = self.colors
        local slot = self.controller and self.controller:getInitiativeSlot(entity.id)

        -- Mini card dimensions
        local cardW = self.cardWidth
        local cardH = self.portraitSize  -- Match portrait height

        if not slot then
            -- No initiative submitted yet - empty slot
            love.graphics.setColor(0.2, 0.2, 0.2, 0.5)
            love.graphics.rectangle("line", x, y, cardW, cardH, 3, 3)
            love.graphics.setColor(0.4, 0.4, 0.4, 0.5)
            love.graphics.print("Init", x + 15, y + cardH/2 - 6)
            return
        end

        -- Check for flip animation
        local flipAnim = self.flipAnimations[entity.id]
        local flipProgress = flipAnim and flipAnim.progress or (slot.revealed and 1.0 or 0.0)

        -- Draw card with flip effect
        self:drawCard(x, y, cardW, cardH, slot.card, slot.revealed, flipProgress)
    end

    --- Draw defense slot
    function display:drawDefenseSlot(entity, x, y)
        local colors = self.colors

        -- Mini card dimensions
        local cardW = self.cardWidth
        local cardH = self.portraitSize

        -- Check if entity has a defense prepared
        local hasDefense = entity.hasDefense and entity:hasDefense()
        local defense = hasDefense and entity:getDefense()

        -- Check for reveal animation
        local revealAnim = self.defenseReveals[entity.id]
        local revealProgress = revealAnim and revealAnim.progress or 0

        if not hasDefense and revealProgress == 0 then
            -- Empty defense slot
            love.graphics.setColor(0.2, 0.2, 0.2, 0.3)
            love.graphics.rectangle("line", x, y, cardW, cardH, 3, 3)
            love.graphics.setColor(0.3, 0.3, 0.3, 0.4)
            love.graphics.print("Def", x + 17, y + cardH/2 - 6)
            return
        end

        -- Defense is prepared - draw facedown card
        if revealProgress > 0 then
            -- Being revealed
            local fakeCard = { value = defense and defense.value or "?", name = defense and defense.type or "Defense" }
            self:drawCard(x, y, cardW, cardH, fakeCard, true, revealProgress)
        else
            -- Facedown
            self:drawCard(x, y, cardW, cardH, nil, false, 0)

            -- Add subtle icon hint based on known type (if revealed earlier)
            -- For now, just show "?"
            love.graphics.setColor(colors.text_light)
            love.graphics.print("?", x + cardW/2 - 4, y + cardH/2 - 6)
        end
    end

    --- Draw a card (facedown or face up with flip animation)
    -- @param x, y number: Position
    -- @param w, h number: Dimensions
    -- @param card table: Card data (or nil for facedown)
    -- @param revealed boolean: Whether card is face up
    -- @param flipProgress number: 0.0 (facedown) to 1.0 (face up)
    function display:drawCard(x, y, w, h, card, revealed, flipProgress)
        local colors = self.colors

        -- Calculate flip effect (horizontal scale)
        local midFlip = 0.5
        local isFaceUp = flipProgress >= midFlip
        local scaleX = math.abs(flipProgress - midFlip) * 2

        -- Prevent zero scale
        scaleX = math.max(scaleX, 0.1)

        -- Adjust x for centered flip
        local drawX = x + (w * (1 - scaleX)) / 2
        local drawW = w * scaleX

        if isFaceUp and revealed and card then
            -- Draw face up card
            love.graphics.setColor(colors.card_face)
            love.graphics.rectangle("fill", drawX, y, drawW, h, 2, 2)

            -- Border
            love.graphics.setColor(colors.card_border)
            love.graphics.rectangle("line", drawX, y, drawW, h, 2, 2)

            -- Card value (if room)
            if drawW > 20 then
                love.graphics.setColor(colors.text_dark)
                local valueStr = tostring(card.value or "?")
                love.graphics.print(valueStr, drawX + drawW/2 - 6, y + h/2 - 8)
            end
        else
            -- Draw facedown card (back)
            love.graphics.setColor(colors.card_back)
            love.graphics.rectangle("fill", drawX, y, drawW, h, 2, 2)

            -- Border
            love.graphics.setColor(colors.card_border)
            love.graphics.rectangle("line", drawX, y, drawW, h, 2, 2)

            -- Pattern on back (simple cross-hatch)
            if drawW > 15 then
                love.graphics.setColor(colors.card_border[1], colors.card_border[2], colors.card_border[3], 0.5)
                love.graphics.setLineWidth(1)
                love.graphics.line(drawX + 5, y + 5, drawX + drawW - 5, y + h - 5)
                love.graphics.line(drawX + drawW - 5, y + 5, drawX + 5, y + h - 5)
            end
        end
    end

    --- Draw the count-up indicator bar
    -- @param x, y number: Position
    -- @param width number: Total width
    -- @param currentCount number: Current count (1-14)
    -- @param maxCount number: Maximum count (14)
    function display:drawCountUpBar(x, y, width, currentCount, maxCount)
        local colors = self.colors
        maxCount = maxCount or 14

        local segmentWidth = width / maxCount
        local segmentHeight = 20

        for i = 1, maxCount do
            local segX = x + (i - 1) * segmentWidth

            -- Background
            if i < currentCount then
                -- Past
                love.graphics.setColor(0.3, 0.3, 0.3, 0.8)
            elseif i == currentCount then
                -- Current (pulsing)
                local pulse = math.sin(self.glowTimer) * 0.2 + 0.8
                love.graphics.setColor(colors.active_glow[1] * pulse, colors.active_glow[2] * pulse, colors.active_glow[3], 1)
            else
                -- Future
                love.graphics.setColor(0.2, 0.2, 0.2, 0.5)
            end

            love.graphics.rectangle("fill", segX + 1, y, segmentWidth - 2, segmentHeight, 2, 2)

            -- Border
            love.graphics.setColor(0.4, 0.4, 0.4, 0.8)
            love.graphics.rectangle("line", segX + 1, y, segmentWidth - 2, segmentHeight, 2, 2)

            -- Number
            love.graphics.setColor(colors.text_light)
            local numStr = i == 1 and "A" or (i == 11 and "J" or (i == 12 and "Q" or (i == 13 and "K" or (i == 14 and "A" or tostring(i)))))
            -- Simplify: just use numbers
            love.graphics.print(tostring(i), segX + segmentWidth/2 - 4, y + 3)
        end
    end

    return display
end

return M
