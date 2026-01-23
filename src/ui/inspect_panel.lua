-- inspect_panel.lua
-- Inspect Context Overlay for Majesty
-- Ticket S5.4: Detailed info overlay for entities and POIs
--
-- Trigger: Hover (0.5s delay) or Right-Click
-- Shows: Full name, origin, known items, HP/defense (gated by discovery)

local events = require('logic.events')
local disposition_module = require('logic.disposition')

local M = {}

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------
M.HOVER_DELAY = 0.5     -- Seconds before hover triggers panel
M.PANEL_WIDTH = 220
M.PANEL_PADDING = 12
M.LINE_HEIGHT = 16

--------------------------------------------------------------------------------
-- COLORS (Ink on Parchment palette)
--------------------------------------------------------------------------------
M.COLORS = {
    panel_bg     = { 0.92, 0.88, 0.78, 0.95 },   -- Parchment
    panel_border = { 0.35, 0.30, 0.25, 1.0 },
    shadow       = { 0.10, 0.08, 0.05, 0.4 },

    -- Text
    text_header  = { 0.20, 0.15, 0.10, 1.0 },    -- Dark ink
    text_body    = { 0.30, 0.25, 0.20, 1.0 },    -- Medium ink
    text_faint   = { 0.50, 0.45, 0.40, 0.8 },    -- Faint
    text_danger  = { 0.60, 0.25, 0.20, 1.0 },    -- Red ink

    -- Pips
    pip_full     = { 0.55, 0.25, 0.20, 1.0 },    -- Health pip
    pip_empty    = { 0.40, 0.38, 0.35, 0.5 },
    pip_armor    = { 0.50, 0.55, 0.60, 1.0 },    -- Armor pip

    -- Discovery state
    undiscovered = { 0.50, 0.48, 0.45, 0.6 },    -- Unknown info

    -- Disposition colors (emotional wheel)
    disp_anger    = { 0.75, 0.25, 0.20, 1.0 },   -- Red
    disp_distaste = { 0.60, 0.40, 0.55, 1.0 },   -- Purple
    disp_sadness  = { 0.35, 0.45, 0.65, 1.0 },   -- Blue
    disp_joy      = { 0.85, 0.75, 0.30, 1.0 },   -- Yellow
    disp_surprise = { 0.90, 0.55, 0.25, 1.0 },   -- Orange
    disp_trust    = { 0.35, 0.65, 0.45, 1.0 },   -- Green
    disp_fear     = { 0.50, 0.50, 0.55, 1.0 },   -- Gray

    -- Morale bar
    morale_high   = { 0.35, 0.65, 0.45, 1.0 },   -- Green
    morale_mid    = { 0.85, 0.75, 0.30, 1.0 },   -- Yellow
    morale_low    = { 0.75, 0.25, 0.20, 1.0 },   -- Red
    morale_bg     = { 0.30, 0.28, 0.25, 0.5 },
}

--------------------------------------------------------------------------------
-- INSPECT PANEL FACTORY
--------------------------------------------------------------------------------

--- Create a new InspectPanel
-- @param config table: { eventBus }
-- @return InspectPanel instance
function M.createInspectPanel(config)
    config = config or {}

    local panel = {
        eventBus = config.eventBus or events.globalBus,

        -- State
        isVisible = false,
        target = nil,           -- Entity or POI being inspected
        targetType = nil,       -- "entity", "poi", "item"

        -- Position (follows mouse/target)
        x = 0,
        y = 0,

        -- Hover tracking
        hoverTarget = nil,
        hoverTimer = 0,
        hoverX = 0,
        hoverY = 0,

        -- Discovery cache (entityId/poiId -> { discovered fields })
        discoveryCache = {},

        colors = M.COLORS,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function panel:init()
        -- Listen for scrutiny results (discoveries)
        self.eventBus:on(events.EVENTS.SCRUTINY_SELECTED, function(data)
            if data.poiId then
                self:markDiscovered(data.poiId, data.verb)
            end
        end)

        -- Listen for social discoveries (from Banter/Intimidate)
        self.eventBus:on("social_discovery", function(data)
            if data.targetId and data.discoveries then
                for _, discovery in ipairs(data.discoveries) do
                    self:markDiscovered(data.targetId, discovery)
                end
            end
        end)
    end

    ----------------------------------------------------------------------------
    -- HOVER TRACKING
    ----------------------------------------------------------------------------

    --- Called when mouse hovers over a target
    function panel:onHover(target, targetType, x, y)
        if self.hoverTarget == target then
            return -- Already tracking this target
        end

        self.hoverTarget = target
        self.hoverTimer = 0
        self.hoverX = x
        self.hoverY = y
    end

    --- Called when mouse leaves a target
    function panel:onHoverEnd()
        self.hoverTarget = nil
        self.hoverTimer = 0
    end

    --- Right-click to immediately show panel
    function panel:onRightClick(target, targetType, x, y)
        self:show(target, targetType, x, y)
    end

    ----------------------------------------------------------------------------
    -- VISIBILITY
    ----------------------------------------------------------------------------

    --- Show the panel for a target
    function panel:show(target, targetType, x, y)
        self.isVisible = true
        self.target = target
        self.targetType = targetType or "entity"

        -- Position panel near the target but within screen bounds
        self:positionPanel(x, y)
    end

    --- Hide the panel
    function panel:hide()
        self.isVisible = false
        self.target = nil
    end

    --- Position panel relative to target, keeping on screen
    function panel:positionPanel(x, y)
        if not love then
            self.x, self.y = x + 15, y + 15
            return
        end

        local w, h = love.graphics.getDimensions()
        local panelHeight = self:calculateHeight()

        -- Default: to the right and below cursor
        self.x = x + 15
        self.y = y + 15

        -- Keep on screen horizontally
        if self.x + M.PANEL_WIDTH > w - 10 then
            self.x = x - M.PANEL_WIDTH - 15
        end

        -- Keep on screen vertically
        if self.y + panelHeight > h - 10 then
            self.y = h - panelHeight - 10
        end

        -- Don't go above screen
        if self.y < 10 then
            self.y = 10
        end
    end

    ----------------------------------------------------------------------------
    -- DISCOVERY (Information Gating)
    ----------------------------------------------------------------------------

    --- Mark info as discovered for a target
    function panel:markDiscovered(targetId, infoType)
        if not self.discoveryCache[targetId] then
            self.discoveryCache[targetId] = {}
        end
        self.discoveryCache[targetId][infoType] = true
    end

    --- Check if info is discovered
    function panel:isDiscovered(targetId, infoType)
        if not self.discoveryCache[targetId] then
            return false
        end
        return self.discoveryCache[targetId][infoType] == true
    end

    --- Check if any info is discovered for target
    function panel:hasAnyDiscovery(targetId)
        return self.discoveryCache[targetId] ~= nil
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function panel:update(dt)
        -- Update hover timer
        if self.hoverTarget then
            self.hoverTimer = self.hoverTimer + dt
            if self.hoverTimer >= M.HOVER_DELAY then
                self:show(self.hoverTarget,
                    self.hoverTarget.isPC and "entity" or "entity",
                    self.hoverX, self.hoverY)
                self.hoverTarget = nil
            end
        end
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    ----------------------------------------------------------------------------

    function panel:draw()
        if not love or not self.isVisible or not self.target then return end

        local colors = self.colors
        local x, y = self.x, self.y
        local panelHeight = self:calculateHeight()

        -- Shadow
        love.graphics.setColor(colors.shadow)
        love.graphics.rectangle("fill", x + 4, y + 4, M.PANEL_WIDTH, panelHeight, 4, 4)

        -- Panel background
        love.graphics.setColor(colors.panel_bg)
        love.graphics.rectangle("fill", x, y, M.PANEL_WIDTH, panelHeight, 4, 4)

        -- Border
        love.graphics.setColor(colors.panel_border)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", x, y, M.PANEL_WIDTH, panelHeight, 4, 4)
        love.graphics.setLineWidth(1)

        -- Content
        if self.targetType == "entity" then
            self:drawEntityInfo(x + M.PANEL_PADDING, y + M.PANEL_PADDING)
        elseif self.targetType == "poi" then
            self:drawPOIInfo(x + M.PANEL_PADDING, y + M.PANEL_PADDING)
        elseif self.targetType == "item" then
            self:drawItemInfo(x + M.PANEL_PADDING, y + M.PANEL_PADDING)
        end
    end

    --- Draw entity (adventurer or NPC) info
    function panel:drawEntityInfo(x, y)
        local e = self.target
        local colors = self.colors
        local lineY = y

        -- Name (always visible)
        love.graphics.setColor(colors.text_header)
        love.graphics.print(e.name or "Unknown", x, lineY)
        lineY = lineY + M.LINE_HEIGHT + 4

        -- Origin/Career (if available)
        if e.career or e.origin then
            love.graphics.setColor(colors.text_faint)
            local originText = (e.career or "") .. (e.origin and (" of " .. e.origin) or "")
            love.graphics.print(originText, x, lineY)
            lineY = lineY + M.LINE_HEIGHT
        end

        -- Separator
        lineY = lineY + 4
        love.graphics.setColor(colors.panel_border)
        love.graphics.line(x, lineY, x + M.PANEL_WIDTH - M.PANEL_PADDING * 2, lineY)
        lineY = lineY + 8

        -- Health display depends on PC vs NPC
        if e.isPC then
            -- PC: Full wound track with pips
            love.graphics.setColor(colors.text_body)
            love.graphics.print("Health:", x, lineY)
            lineY = lineY + M.LINE_HEIGHT
            self:drawHealthPips(x, lineY, e)
            lineY = lineY + 14

            -- Armor (if present)
            if e.armorSlots and e.armorSlots > 0 then
                love.graphics.setColor(colors.text_body)
                love.graphics.print("Armor:", x, lineY)
                lineY = lineY + M.LINE_HEIGHT
                self:drawArmorPips(x, lineY, e)
                lineY = lineY + 14
            end
        else
            -- NPC: Health/Defense (HD) system
            love.graphics.setColor(colors.text_body)
            love.graphics.print("HD (Health/Defense):", x, lineY)
            lineY = lineY + M.LINE_HEIGHT
            self:drawHDBar(x, lineY, e)
            lineY = lineY + 28
        end

        -- Defense status
        if e.hasDefense and e:hasDefense() then
            love.graphics.setColor(colors.text_danger)
            love.graphics.print("Defense Prepared!", x, lineY)
            lineY = lineY + M.LINE_HEIGHT
        end

        -- Conditions
        if e.conditions then
            local conditionTexts = {}
            if e.conditions.stressed then conditionTexts[#conditionTexts + 1] = "Stressed" end
            if e.conditions.staggered then conditionTexts[#conditionTexts + 1] = "Staggered" end
            if e.conditions.injured then conditionTexts[#conditionTexts + 1] = "Injured" end
            if e.conditions.deaths_door then conditionTexts[#conditionTexts + 1] = "Death's Door" end
            if e.conditions.dead then conditionTexts[#conditionTexts + 1] = "DEAD" end

            if #conditionTexts > 0 then
                love.graphics.setColor(colors.text_danger)
                love.graphics.print(table.concat(conditionTexts, ", "), x, lineY)
                lineY = lineY + M.LINE_HEIGHT
            end
        end

        -- Items in hands/belt (for PCs or discovered NPCs)
        if e.isPC or self:isDiscovered(e.id, "inventory") then
            if e.inventory then
                lineY = lineY + 4
                love.graphics.setColor(colors.text_body)
                love.graphics.print("Equipment:", x, lineY)
                lineY = lineY + M.LINE_HEIGHT

                local items = e.inventory:getItems("hands")
                for _, item in ipairs(items) do
                    love.graphics.setColor(colors.text_faint)
                    love.graphics.print("  " .. (item.name or "?"), x, lineY)
                    lineY = lineY + M.LINE_HEIGHT
                end
            end
        end

        -- NPC-specific info
        if not e.isPC then
            -- Disposition (revealed by successful Banter/Intimidate)
            lineY = lineY + 4
            love.graphics.setColor(colors.text_body)
            love.graphics.print("Disposition:", x, lineY)
            lineY = lineY + M.LINE_HEIGHT

            if self:isDiscovered(e.id, "disposition") then
                self:drawDispositionWheel(x, lineY, e)
                lineY = lineY + 24
            else
                love.graphics.setColor(colors.undiscovered)
                love.graphics.print("  ??? (try Banter)", x, lineY)
                lineY = lineY + M.LINE_HEIGHT
            end

            -- Morale (revealed by successful Banter/Intimidate)
            love.graphics.setColor(colors.text_body)
            love.graphics.print("Morale:", x, lineY)
            lineY = lineY + M.LINE_HEIGHT

            if self:isDiscovered(e.id, "morale") then
                self:drawMoraleBar(x, lineY, e)
                lineY = lineY + 14
            else
                love.graphics.setColor(colors.undiscovered)
                love.graphics.print("  ??? (try Banter)", x, lineY)
                lineY = lineY + M.LINE_HEIGHT
            end

            -- Hates/Wants (only if discovered via great success or Con Artist)
            if e.hates and self:isDiscovered(e.id, "hates") then
                lineY = lineY + 4
                love.graphics.setColor(colors.text_body)
                love.graphics.print("Hates:", x, lineY)
                lineY = lineY + M.LINE_HEIGHT
                love.graphics.setColor(colors.text_faint)
                local hatesText = type(e.hates) == "table" and table.concat(e.hates, ", ") or tostring(e.hates)
                love.graphics.print("  " .. hatesText, x, lineY)
                lineY = lineY + M.LINE_HEIGHT
            end

            if e.wants and self:isDiscovered(e.id, "wants") then
                love.graphics.setColor(colors.text_body)
                love.graphics.print("Wants:", x, lineY)
                lineY = lineY + M.LINE_HEIGHT
                love.graphics.setColor(colors.text_faint)
                local wantsText = type(e.wants) == "table" and table.concat(e.wants, ", ") or tostring(e.wants)
                love.graphics.print("  " .. wantsText, x, lineY)
                lineY = lineY + M.LINE_HEIGHT
            end

            -- Show hint for fully undiscovered NPCs
            if not self:hasAnyDiscovery(e.id) then
                lineY = lineY + 4
                love.graphics.setColor(colors.undiscovered)
                love.graphics.print("(Social info hidden)", x, lineY)
            end
        end
    end

    --- Draw disposition wheel indicator
    function panel:drawDispositionWheel(x, y, entity)
        local colors = self.colors
        local currentDisp = entity.disposition or "distaste"
        local props = disposition_module.getProperties(currentDisp)

        -- Draw small wheel segment indicators
        local segmentWidth = 20
        local segmentHeight = 16
        local spacing = 2

        for i, disp in ipairs(disposition_module.WHEEL) do
            local segX = x + (i - 1) * (segmentWidth + spacing)
            local colorKey = "disp_" .. disp
            local segColor = colors[colorKey] or colors.undiscovered

            -- Highlight current disposition
            if disp == currentDisp then
                -- Draw highlighted segment
                love.graphics.setColor(segColor)
                love.graphics.rectangle("fill", segX, y, segmentWidth, segmentHeight, 2, 2)
                love.graphics.setColor(colors.panel_border)
                love.graphics.setLineWidth(2)
                love.graphics.rectangle("line", segX, y, segmentWidth, segmentHeight, 2, 2)
                love.graphics.setLineWidth(1)
            else
                -- Draw faded segment
                love.graphics.setColor(segColor[1], segColor[2], segColor[3], 0.3)
                love.graphics.rectangle("fill", segX, y, segmentWidth, segmentHeight, 2, 2)
            end
        end

        -- Draw disposition name and description below
        local dispColor = colors["disp_" .. currentDisp] or colors.text_body
        love.graphics.setColor(dispColor)
        love.graphics.print(props.name or currentDisp, x, y + segmentHeight + 2)
    end

    --- Draw NPC Health/Defense bar (HD system)
    function panel:drawHDBar(x, y, entity)
        local colors = self.colors
        local pipSize = 12
        local pipSpacing = 3

        local health = entity.npcHealth or 3
        local maxHealth = entity.npcMaxHealth or 3
        local defense = entity.npcDefense or 0
        local maxDefense = entity.npcMaxDefense or 0

        local startX = x

        -- Draw Defense pips first (blue/gray)
        if maxDefense > 0 then
            love.graphics.setColor(colors.text_faint)
            love.graphics.print("Def:", x, y - 2)
            x = x + 28

            for i = 1, maxDefense do
                local pipX = x + (i - 1) * (pipSize + pipSpacing)

                if i <= defense then
                    -- Full defense pip
                    love.graphics.setColor(colors.pip_armor)
                    love.graphics.rectangle("fill", pipX, y, pipSize, pipSize, 2, 2)
                else
                    -- Empty defense pip (depleted)
                    love.graphics.setColor(colors.pip_empty)
                    love.graphics.rectangle("fill", pipX, y, pipSize, pipSize, 2, 2)
                end

                love.graphics.setColor(colors.panel_border)
                love.graphics.rectangle("line", pipX, y, pipSize, pipSize, 2, 2)
            end

            x = x + maxDefense * (pipSize + pipSpacing) + 8
        end

        -- Draw Health pips (red)
        love.graphics.setColor(colors.text_faint)
        love.graphics.print("HP:", startX, y + pipSize + 4)
        x = startX + 28

        for i = 1, maxHealth do
            local pipX = x + (i - 1) * (pipSize + pipSpacing)

            if i <= health then
                -- Full health pip
                love.graphics.setColor(colors.pip_full)
                love.graphics.rectangle("fill", pipX, y + pipSize + 4, pipSize, pipSize, 2, 2)
            else
                -- Empty health pip (wounded)
                love.graphics.setColor(colors.pip_empty)
                love.graphics.rectangle("fill", pipX, y + pipSize + 4, pipSize, pipSize, 2, 2)
                -- X mark for lost health
                love.graphics.setColor(colors.text_danger)
                love.graphics.line(pipX + 2, y + pipSize + 6, pipX + pipSize - 2, y + pipSize + pipSize + 2)
                love.graphics.line(pipX + pipSize - 2, y + pipSize + 6, pipX + 2, y + pipSize + pipSize + 2)
            end

            love.graphics.setColor(colors.panel_border)
            love.graphics.rectangle("line", pipX, y + pipSize + 4, pipSize, pipSize, 2, 2)
        end

        -- Show Death's Door or Dead status
        if entity.conditions then
            if entity.conditions.dead then
                love.graphics.setColor(colors.text_danger)
                love.graphics.print("DEFEATED", startX + 80, y + pipSize + 4)
            elseif entity.conditions.deaths_door then
                love.graphics.setColor(colors.text_danger)
                love.graphics.print("DEATH'S DOOR", startX + 80, y + pipSize + 4)
            end
        end
    end

    --- Draw morale bar
    function panel:drawMoraleBar(x, y, entity)
        local colors = self.colors
        local barWidth = M.PANEL_WIDTH - M.PANEL_PADDING * 2 - 40
        local barHeight = 10

        -- Get current morale
        local currentMorale = 10
        if entity.getMorale then
            currentMorale = entity:getMorale()
        elseif entity.baseMorale then
            currentMorale = entity.baseMorale - (entity.moraleModifier or 0)
        end

        local baseMorale = entity.baseMorale or 14
        local moralePercent = math.max(0, math.min(1, currentMorale / baseMorale))

        -- Background
        love.graphics.setColor(colors.morale_bg)
        love.graphics.rectangle("fill", x, y, barWidth, barHeight, 2, 2)

        -- Fill color based on morale level
        local fillColor
        if moralePercent > 0.6 then
            fillColor = colors.morale_high
        elseif moralePercent > 0.3 then
            fillColor = colors.morale_mid
        else
            fillColor = colors.morale_low
        end

        love.graphics.setColor(fillColor)
        love.graphics.rectangle("fill", x, y, barWidth * moralePercent, barHeight, 2, 2)

        -- Border
        love.graphics.setColor(colors.panel_border)
        love.graphics.rectangle("line", x, y, barWidth, barHeight, 2, 2)

        -- Value text
        love.graphics.setColor(colors.text_body)
        love.graphics.print(string.format("%d", currentMorale), x + barWidth + 4, y - 2)
    end

    --- Draw health pips
    function panel:drawHealthPips(x, y, entity)
        local colors = self.colors
        local pipSize = 10
        local pipSpacing = 3

        -- Calculate wounds taken
        local woundsUntilDeath = 4  -- Default
        if entity.woundsUntilDeath then
            woundsUntilDeath = entity:woundsUntilDeath()
        end

        local maxHealth = 5  -- Simplified
        local currentHealth = math.max(0, woundsUntilDeath)

        for i = 1, maxHealth do
            local pipX = x + (i - 1) * (pipSize + pipSpacing)

            if i <= currentHealth then
                love.graphics.setColor(colors.pip_full)
                love.graphics.rectangle("fill", pipX, y, pipSize, pipSize, 2, 2)
            else
                love.graphics.setColor(colors.pip_empty)
                love.graphics.rectangle("fill", pipX, y, pipSize, pipSize, 2, 2)
            end

            love.graphics.setColor(colors.panel_border)
            love.graphics.rectangle("line", pipX, y, pipSize, pipSize, 2, 2)
        end
    end

    --- Draw armor pips
    function panel:drawArmorPips(x, y, entity)
        local colors = self.colors
        local pipSize = 10
        local pipSpacing = 3

        local slots = entity.armorSlots or 0
        local notches = entity.armorNotches or 0
        local remaining = slots - notches

        for i = 1, slots do
            local pipX = x + (i - 1) * (pipSize + pipSpacing)

            if i <= remaining then
                love.graphics.setColor(colors.pip_armor)
                love.graphics.rectangle("fill", pipX, y, pipSize, pipSize, 2, 2)
            else
                love.graphics.setColor(colors.pip_empty)
                love.graphics.rectangle("fill", pipX, y, pipSize, pipSize, 2, 2)
                -- X mark for notched
                love.graphics.setColor(colors.text_danger)
                love.graphics.line(pipX + 2, y + 2, pipX + pipSize - 2, y + pipSize - 2)
                love.graphics.line(pipX + pipSize - 2, y + 2, pipX + 2, y + pipSize - 2)
            end

            love.graphics.setColor(colors.panel_border)
            love.graphics.rectangle("line", pipX, y, pipSize, pipSize, 2, 2)
        end
    end

    --- Draw POI info
    function panel:drawPOIInfo(x, y)
        local poi = self.target
        local colors = self.colors
        local lineY = y

        -- Name
        love.graphics.setColor(colors.text_header)
        love.graphics.print(poi.name or "Unknown", x, lineY)
        lineY = lineY + M.LINE_HEIGHT + 4

        -- Description
        if poi.description then
            love.graphics.setColor(colors.text_body)
            -- Word wrap would go here; for now just print
            love.graphics.printf(poi.description, x, lineY, M.PANEL_WIDTH - M.PANEL_PADDING * 2)
            lineY = lineY + M.LINE_HEIGHT * 2
        end

        -- Discovered info
        if self:isDiscovered(poi.id, "examine") then
            lineY = lineY + 4
            love.graphics.setColor(colors.text_faint)
            love.graphics.print("(Examined)", x, lineY)
        end
    end

    --- Draw item info
    function panel:drawItemInfo(x, y)
        local item = self.target
        local colors = self.colors
        local lineY = y

        -- Name
        love.graphics.setColor(colors.text_header)
        love.graphics.print(item.name or "Unknown Item", x, lineY)
        lineY = lineY + M.LINE_HEIGHT + 4

        -- Durability
        if item.durability then
            love.graphics.setColor(colors.text_body)
            local durText = string.format("Durability: %d/%d", item.durability - (item.notches or 0), item.durability)
            love.graphics.print(durText, x, lineY)
            lineY = lineY + M.LINE_HEIGHT
        end

        -- Destroyed
        if item.destroyed then
            love.graphics.setColor(colors.text_danger)
            love.graphics.print("DESTROYED", x, lineY)
            lineY = lineY + M.LINE_HEIGHT
        end

        -- Properties
        if item.properties then
            for key, value in pairs(item.properties) do
                love.graphics.setColor(colors.text_faint)
                love.graphics.print(key .. ": " .. tostring(value), x, lineY)
                lineY = lineY + M.LINE_HEIGHT
            end
        end
    end

    --- Calculate panel height based on content
    function panel:calculateHeight()
        -- Base height
        local height = M.PANEL_PADDING * 2 + M.LINE_HEIGHT * 4

        if self.targetType == "entity" and self.target then
            local e = self.target
            height = height + M.LINE_HEIGHT * 4  -- Name, origin, separator

            -- Health display
            if e.isPC then
                -- PC: Health pips + optional armor
                height = height + M.LINE_HEIGHT + 14  -- Health label + pips
                if e.armorSlots and e.armorSlots > 0 then
                    height = height + M.LINE_HEIGHT + 14
                end
            else
                -- NPC: HD bar (two rows)
                height = height + M.LINE_HEIGHT + 28
            end

            -- PC conditions
            if e.isPC and e.conditions then
                local hasConditions = e.conditions.stressed or
                    e.conditions.staggered or
                    e.conditions.injured or
                    e.conditions.deaths_door
                if hasConditions then
                    height = height + M.LINE_HEIGHT
                end
            end

            -- Defense prepared
            if e.hasDefense and e:hasDefense() then
                height = height + M.LINE_HEIGHT
            end

            -- PC conditions display
            if e.isPC and e.conditions then
                height = height + M.LINE_HEIGHT  -- For conditions line
            end

            -- NPC disposition and morale sections
            if not e.isPC then
                -- Disposition section
                height = height + M.LINE_HEIGHT + 4  -- "Disposition:" label
                if self:isDiscovered(e.id, "disposition") then
                    height = height + 24 + M.LINE_HEIGHT  -- Wheel + name
                else
                    height = height + M.LINE_HEIGHT  -- "???" text
                end

                -- Morale section
                height = height + M.LINE_HEIGHT  -- "Morale:" label
                if self:isDiscovered(e.id, "morale") then
                    height = height + 14  -- Bar
                else
                    height = height + M.LINE_HEIGHT  -- "???" text
                end

                -- Hates/Wants if discovered
                if e.hates and self:isDiscovered(e.id, "hates") then
                    height = height + M.LINE_HEIGHT * 2 + 4
                end
                if e.wants and self:isDiscovered(e.id, "wants") then
                    height = height + M.LINE_HEIGHT * 2
                end
            end
        end

        return math.min(height, 450)  -- Cap at max height
    end

    return panel
end

return M
