-- camp_screen.lua
-- The Camp Screen UI for Majesty
-- Ticket S8.5: Camp Phase visualization and interaction
--
-- Layout:
-- +------------------------------------------+
-- |           STEP INDICATOR BAR             |
-- +----------+------------------+------------+
-- |  Char 1  |                  |  Char 3    |
-- +----------+    CAMPFIRE      +------------+
-- |  Char 2  |    (center)      |  Char 4    |
-- +----------+------------------+------------+
-- |          ACTION PANEL (context-aware)    |
-- +------------------------------------------+
--
-- Reuses character_plate.lua from S5.1

local events = require('logic.events')
local character_plate = require('ui.character_plate')
local camp_controller = require('logic.camp_controller')
local camp_actions = require('logic.camp_actions')
local camp_prompts = require('data.camp_prompts')

local M = {}

--------------------------------------------------------------------------------
-- LAYOUT CONSTANTS
--------------------------------------------------------------------------------
M.LAYOUT = {
    STEP_BAR_HEIGHT   = 50,
    ACTION_PANEL_HEIGHT = 120,
    PADDING           = 15,
    PLATE_WIDTH       = 200,
    FIRE_SIZE         = 150,
}

--------------------------------------------------------------------------------
-- COLORS
--------------------------------------------------------------------------------
M.COLORS = {
    background     = { 0.05, 0.05, 0.08, 1.0 },   -- Dark night sky
    step_bar_bg    = { 0.10, 0.10, 0.12, 0.95 },
    step_active    = { 0.85, 0.65, 0.25, 1.0 },   -- Warm gold for current step
    step_complete  = { 0.35, 0.55, 0.35, 1.0 },   -- Muted green for done
    step_pending   = { 0.35, 0.35, 0.40, 1.0 },   -- Grey for not yet
    step_text      = { 0.90, 0.85, 0.75, 1.0 },
    fire_outer     = { 0.80, 0.40, 0.10, 0.8 },
    fire_inner     = { 1.00, 0.75, 0.30, 1.0 },
    fire_glow      = { 0.95, 0.60, 0.20, 0.15 },
    panel_bg       = { 0.12, 0.12, 0.14, 0.95 },
    panel_border   = { 0.30, 0.28, 0.25, 1.0 },
    button_bg      = { 0.18, 0.18, 0.20, 1.0 },
    button_hover   = { 0.25, 0.25, 0.28, 1.0 },
    button_text    = { 0.90, 0.85, 0.80, 1.0 },
    bond_charged   = { 0.70, 0.55, 0.85, 1.0 },   -- Purple for charged bonds
    bond_spent     = { 0.40, 0.40, 0.45, 0.5 },   -- Grey for spent bonds
    warning        = { 0.85, 0.40, 0.35, 1.0 },   -- Red for warnings
}

--------------------------------------------------------------------------------
-- STEP NAMES
--------------------------------------------------------------------------------
M.STEP_NAMES = {
    [0] = "Setup",
    [1] = "Actions",
    [2] = "Break Bread",
    [3] = "Watch",
    [4] = "Recovery",
    [5] = "Teardown",
}

--------------------------------------------------------------------------------
-- CAMP SCREEN FACTORY
--------------------------------------------------------------------------------

--- Create a new CampScreen
-- @param config table: { eventBus, campController, guild }
-- @return CampScreen instance
function M.createCampScreen(config)
    config = config or {}

    local screen = {
        -- Core systems
        eventBus       = config.eventBus or events.globalBus,
        campController = config.campController,
        guild          = config.guild or {},

        -- UI state
        width          = 800,
        height         = 600,
        characterPlates = {},
        hoverButton    = nil,
        selectedPC     = nil,      -- PC currently selecting action
        selectedAction = nil,      -- Action currently being configured

        -- Action menu state
        actionMenuOpen = false,
        actionMenuItems = {},
        actionMenuX    = 0,
        actionMenuY    = 0,

        -- Fellowship selection mode (S9.1)
        fellowshipMode = false,
        fellowshipActor = nil,      -- First PC selected for fellowship
        fellowshipActorIndex = nil,

        -- Drop zones (for ration drag-drop)
        dropZones      = {},

        -- Bond interaction
        hoveredBond    = nil,
        hoveredPlateIndex = nil,    -- Track which plate is hovered

        -- Prompt overlay (S9.3)
        promptOverlay  = nil,       -- { text, callback }

        -- Fire animation
        fireTimer      = 0,

        -- Colors
        colors         = config.colors or M.COLORS,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function screen:init()
        -- Create character plates for guild
        self:createCharacterPlates()

        -- Subscribe to camp events
        self:subscribeEvents()

        -- Initial layout
        if love then
            self:resize(love.graphics.getDimensions())
        end
    end

    function screen:subscribeEvents()
        -- Camp step changed
        self.eventBus:on(camp_controller.EVENTS.CAMP_STEP_CHANGED, function(data)
            self:onStepChanged(data)
        end)

        -- Camp action taken
        self.eventBus:on(camp_controller.EVENTS.CAMP_ACTION_TAKEN, function(data)
            self:onActionTaken(data)
        end)

        -- Ration consumed
        self.eventBus:on(camp_controller.EVENTS.RATION_CONSUMED, function(data)
            self:onRationConsumed(data)
        end)

        -- Bond spent
        self.eventBus:on(camp_controller.EVENTS.BOND_SPENT, function(data)
            self:onBondSpent(data)
        end)
    end

    ----------------------------------------------------------------------------
    -- EVENT HANDLERS
    ----------------------------------------------------------------------------

    function screen:onStepChanged(data)
        print("[CampScreen] Step changed to: " .. data.newState)
        -- Close any open menus and cancel fellowship mode
        self.actionMenuOpen = false
        self.selectedPC = nil
        self.fellowshipMode = false
        self.fellowshipActor = nil
        self.fellowshipActorIndex = nil
    end

    function screen:onActionTaken(data)
        print("[CampScreen] " .. data.entity.name .. " took action: " .. data.action.type)

        -- S9.3: Show campfire prompt for fellowship actions
        if data.action.type == "fellowship" and data.action.target then
            self:showFellowshipPrompt(data.entity, data.action.target)
        end
    end

    function screen:onRationConsumed(data)
        print("[CampScreen] " .. data.entity.name .. " ate")
    end

    function screen:onBondSpent(data)
        print("[CampScreen] Bond spent: " .. data.result)
    end

    ----------------------------------------------------------------------------
    -- CHARACTER PLATES
    ----------------------------------------------------------------------------

    function screen:createCharacterPlates()
        self.characterPlates = {}

        for i, adventurer in ipairs(self.guild) do
            local plate = character_plate.createCharacterPlate({
                eventBus = self.eventBus,
                entity = adventurer,
                x = 0,  -- Positioned in calculateLayout
                y = 0,
                width = M.LAYOUT.PLATE_WIDTH,
            })
            plate:init()

            -- Add bond drawing capability
            plate.drawBonds = function(p)
                self:drawBondsForPlate(p, i)
            end

            self.characterPlates[#self.characterPlates + 1] = plate
        end
    end

    function screen:setGuild(guild)
        self.guild = guild or {}
        self:createCharacterPlates()
        self:calculateLayout()
    end

    ----------------------------------------------------------------------------
    -- LAYOUT
    ----------------------------------------------------------------------------

    function screen:calculateLayout()
        local padding = M.LAYOUT.PADDING
        local plateW = M.LAYOUT.PLATE_WIDTH
        local stepH = M.LAYOUT.STEP_BAR_HEIGHT
        local actionH = M.LAYOUT.ACTION_PANEL_HEIGHT

        -- Available area for character plates and fire
        local contentY = stepH + padding
        local contentH = self.height - stepH - actionH - (padding * 2)

        -- Fire center position
        self.fireX = self.width / 2
        self.fireY = contentY + contentH / 2

        -- Position plates around the fire
        local count = #self.characterPlates
        local radius = math.min(self.width, contentH) * 0.35

        for i, plate in ipairs(self.characterPlates) do
            -- Distribute plates in a circle around the fire
            local angle = (i - 1) * (math.pi * 2 / count) - math.pi / 2
            local px = self.fireX + math.cos(angle) * radius - plateW / 2
            local py = self.fireY + math.sin(angle) * radius - plate:getHeight() / 2

            -- Keep within bounds
            px = math.max(padding, math.min(px, self.width - plateW - padding))
            py = math.max(contentY, math.min(py, contentY + contentH - plate:getHeight()))

            plate:setPosition(px, py)
        end

        -- Calculate drop zones for ration interaction
        self:calculateDropZones()
    end

    function screen:calculateDropZones()
        self.dropZones = {}

        -- Each character plate is a drop zone during Break Bread phase
        for i, plate in ipairs(self.characterPlates) do
            self.dropZones[#self.dropZones + 1] = {
                id = "plate_" .. i,
                entityIndex = i,
                x = plate.x,
                y = plate.y,
                width = M.LAYOUT.PLATE_WIDTH,
                height = plate:getHeight(),
            }
        end
    end

    function screen:resize(w, h)
        self.width = w
        self.height = h
        self:calculateLayout()
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function screen:update(dt)
        -- Fire animation
        self.fireTimer = self.fireTimer + dt

        -- Update character plates
        for _, plate in ipairs(self.characterPlates) do
            plate:update(dt)
        end
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    ----------------------------------------------------------------------------

    function screen:draw()
        if not love then return end

        -- Background
        love.graphics.setColor(self.colors.background)
        love.graphics.rectangle("fill", 0, 0, self.width, self.height)

        -- Fire glow (large area)
        self:drawFireGlow()

        -- Step indicator bar
        self:drawStepBar()

        -- Campfire
        self:drawCampfire()

        -- Character plates with bonds
        self:drawCharacterPlates()

        -- Action panel (context-aware)
        self:drawActionPanel()

        -- Action menu (if open)
        if self.actionMenuOpen then
            self:drawActionMenu()
        end

        -- S9.3: Prompt overlay (on top of everything)
        if self.promptOverlay then
            self:drawPromptOverlay()
        end
    end

    --- Draw the campfire prompt overlay (S9.3)
    function screen:drawPromptOverlay()
        if not self.promptOverlay then return end

        -- Darken background
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", 0, 0, self.width, self.height)

        -- Calculate prompt box dimensions
        local boxW = math.min(500, self.width - 60)
        local boxH = 200
        local boxX = (self.width - boxW) / 2
        local boxY = (self.height - boxH) / 2

        -- Draw speech bubble background (parchment-like)
        love.graphics.setColor(0.85, 0.80, 0.70, 1.0)
        love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 12, 12)

        -- Border
        love.graphics.setColor(0.50, 0.45, 0.35, 1.0)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 12, 12)
        love.graphics.setLineWidth(1)

        -- Header: "Campfire Discussion"
        love.graphics.setColor(0.30, 0.25, 0.20, 1.0)
        love.graphics.printf("CAMPFIRE DISCUSSION", boxX, boxY + 15, boxW, "center")

        -- Participants
        if self.promptOverlay.actor and self.promptOverlay.target then
            love.graphics.setColor(0.50, 0.45, 0.40, 1.0)
            local participants = self.promptOverlay.actor.name .. " & " .. self.promptOverlay.target.name
            love.graphics.printf(participants, boxX, boxY + 35, boxW, "center")
        end

        -- Separator line
        love.graphics.setColor(0.60, 0.55, 0.45, 0.5)
        love.graphics.line(boxX + 30, boxY + 55, boxX + boxW - 30, boxY + 55)

        -- The prompt text
        love.graphics.setColor(0.20, 0.15, 0.10, 1.0)
        love.graphics.printf(
            "\"" .. self.promptOverlay.text .. "\"",
            boxX + 20, boxY + 70,
            boxW - 40, "center"
        )

        -- Click to dismiss instruction
        love.graphics.setColor(0.50, 0.45, 0.40, 0.8)
        love.graphics.printf(
            "(Click anywhere to continue)",
            boxX, boxY + boxH - 30,
            boxW, "center"
        )

        -- Decorative fire icon
        local fireX = boxX + boxW / 2
        local fireY = boxY + boxH - 55
        self:drawMiniFlame(fireX, fireY)
    end

    --- Draw a small decorative flame icon
    function screen:drawMiniFlame(x, y)
        local size = 12

        -- Outer flame
        love.graphics.setColor(0.80, 0.40, 0.10, 0.8)
        love.graphics.polygon("fill",
            x, y - size,
            x - size * 0.6, y + size * 0.3,
            x + size * 0.6, y + size * 0.3
        )

        -- Inner flame
        love.graphics.setColor(1.0, 0.75, 0.30, 0.9)
        love.graphics.polygon("fill",
            x, y - size * 0.6,
            x - size * 0.3, y + size * 0.2,
            x + size * 0.3, y + size * 0.2
        )
    end

    --- Show fellowship prompt (S9.3)
    function screen:showFellowshipPrompt(actor, target)
        -- Use a seed based on game state for determinism
        local seed = os.time() + (actor.id and #actor.id or 0) + (target.id and #target.id or 0)
        local promptText = camp_prompts.getRandomPrompt(seed)

        self.promptOverlay = {
            text = promptText,
            actor = actor,
            target = target,
        }

        print("[CampScreen] Showing fellowship prompt: " .. promptText)
    end

    --- Dismiss the prompt overlay (S9.3)
    function screen:dismissPromptOverlay()
        self.promptOverlay = nil
    end

    function screen:drawStepBar()
        local barY = 0
        local barH = M.LAYOUT.STEP_BAR_HEIGHT

        -- Background
        love.graphics.setColor(self.colors.step_bar_bg)
        love.graphics.rectangle("fill", 0, barY, self.width, barH)

        -- Border
        love.graphics.setColor(self.colors.panel_border)
        love.graphics.line(0, barH, self.width, barH)

        -- Current step indicator
        local currentStep = self.campController and self.campController:getCurrentStep() or 0

        -- Draw step indicators
        local stepCount = 6  -- 0-5
        local stepWidth = (self.width - M.LAYOUT.PADDING * 2) / stepCount
        local stepY = barY + 10

        for i = 0, 5 do
            local stepX = M.LAYOUT.PADDING + i * stepWidth
            local stepName = M.STEP_NAMES[i] or "Step " .. i

            -- Determine color
            local bgColor, textColor
            if i == currentStep then
                bgColor = self.colors.step_active
                textColor = { 0.1, 0.1, 0.1, 1.0 }
            elseif i < currentStep then
                bgColor = self.colors.step_complete
                textColor = self.colors.step_text
            else
                bgColor = self.colors.step_pending
                textColor = { 0.6, 0.6, 0.6, 1.0 }
            end

            -- Step box
            love.graphics.setColor(bgColor)
            love.graphics.rectangle("fill", stepX + 2, stepY, stepWidth - 4, barH - 20, 4, 4)

            -- Step text
            love.graphics.setColor(textColor)
            love.graphics.printf(stepName, stepX + 2, stepY + 8, stepWidth - 4, "center")
        end
    end

    function screen:drawCampfire()
        local cx, cy = self.fireX, self.fireY
        local baseSize = M.LAYOUT.FIRE_SIZE / 2

        -- Flickering effect
        local flicker = math.sin(self.fireTimer * 8) * 0.1 +
                        math.sin(self.fireTimer * 12) * 0.05 +
                        math.cos(self.fireTimer * 5) * 0.08

        -- Outer flame (orange)
        love.graphics.setColor(self.colors.fire_outer)
        local outerSize = baseSize * (1 + flicker)
        self:drawFlameShape(cx, cy, outerSize)

        -- Inner flame (yellow)
        love.graphics.setColor(self.colors.fire_inner)
        local innerSize = baseSize * 0.6 * (1 + flicker * 0.5)
        self:drawFlameShape(cx, cy, innerSize)

        -- Core (white-yellow)
        love.graphics.setColor(1.0, 0.95, 0.8, 0.9)
        local coreSize = baseSize * 0.25
        love.graphics.circle("fill", cx, cy + baseSize * 0.2, coreSize)

        -- Embers (small particles)
        love.graphics.setColor(1.0, 0.6, 0.2, 0.7)
        for i = 1, 5 do
            local emberAngle = self.fireTimer * 2 + i * 1.2
            local emberDist = baseSize * 0.4 + math.sin(emberAngle * 3) * 10
            local emberX = cx + math.cos(emberAngle) * emberDist * 0.3
            local emberY = cy - math.sin(self.fireTimer * 3 + i) * emberDist * 0.5
            love.graphics.circle("fill", emberX, emberY, 2 + math.sin(emberAngle) * 1)
        end
    end

    function screen:drawFlameShape(cx, cy, size)
        -- Simple flame polygon
        local points = {}
        local segments = 8

        for i = 0, segments do
            local t = i / segments
            local angle = math.pi * (0.3 + t * 1.4) - math.pi / 2

            -- Flame shape: wider at bottom, pointed at top
            local r = size
            if t < 0.5 then
                r = r * (0.5 + t)
            else
                r = r * (1.5 - t)
            end

            -- Add some randomness
            r = r * (0.9 + math.sin(self.fireTimer * 6 + i) * 0.1)

            points[#points + 1] = cx + math.cos(angle) * r * 0.6
            points[#points + 1] = cy + math.sin(angle) * r
        end

        if #points >= 6 then
            love.graphics.polygon("fill", points)
        end
    end

    function screen:drawFireGlow()
        local cx, cy = self.fireX, self.fireY
        local glowSize = M.LAYOUT.FIRE_SIZE * 2

        -- Radial glow
        for i = 5, 1, -1 do
            local alpha = 0.03 * i
            love.graphics.setColor(self.colors.fire_glow[1], self.colors.fire_glow[2], self.colors.fire_glow[3], alpha)
            love.graphics.circle("fill", cx, cy, glowSize * (i / 5))
        end
    end

    function screen:drawCharacterPlates()
        local currentState = self.campController and self.campController:getState()

        for i, plate in ipairs(self.characterPlates) do
            -- Draw selection highlight for fellowship mode (S9.1)
            if self.fellowshipMode then
                self:drawFellowshipHighlight(plate, i)
            end

            plate:draw()

            -- Draw bonds for this plate (if in recovery phase OR actions phase to show existing bonds)
            if currentState == camp_controller.STATES.RECOVERY or
               currentState == camp_controller.STATES.ACTIONS then
                self:drawBondsForPlate(plate, i)
            end

            -- Draw pending action indicator
            local pc = self.guild[i]
            if pc then
                self:drawPCStatus(plate, pc, i)
            end
        end

        -- Draw fellowship connection line (S9.1)
        if self.fellowshipMode and self.fellowshipActorIndex then
            self:drawFellowshipLine()
        end
    end

    --- Draw fellowship selection highlight (S9.1)
    function screen:drawFellowshipHighlight(plate, index)
        local isActor = (index == self.fellowshipActorIndex)
        local isHovered = (index == self.hoveredPlateIndex)
        local pc = self.guild[index]

        -- Check if this PC can be selected as target
        local canSelect = true
        if self.fellowshipActor and pc then
            -- Can't select self
            if pc.id == self.fellowshipActor.id then
                canSelect = false
            end
            -- Check if bond already charged
            if self.fellowshipActor.bonds and self.fellowshipActor.bonds[pc.id] then
                if self.fellowshipActor.bonds[pc.id].charged then
                    canSelect = false  -- Bond already charged
                end
            end
        end

        -- Draw highlight
        if isActor then
            -- Selected actor - gold highlight
            love.graphics.setColor(0.85, 0.65, 0.25, 0.4)
            love.graphics.rectangle("fill", plate.x - 4, plate.y - 4,
                M.LAYOUT.PLATE_WIDTH + 8, plate:getHeight() + 8, 6, 6)
            love.graphics.setColor(0.85, 0.65, 0.25, 1.0)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", plate.x - 4, plate.y - 4,
                M.LAYOUT.PLATE_WIDTH + 8, plate:getHeight() + 8, 6, 6)
            love.graphics.setLineWidth(1)
        elseif isHovered and canSelect and not isActor then
            -- Valid target - purple hover
            love.graphics.setColor(0.70, 0.55, 0.85, 0.3)
            love.graphics.rectangle("fill", plate.x - 2, plate.y - 2,
                M.LAYOUT.PLATE_WIDTH + 4, plate:getHeight() + 4, 4, 4)
        elseif not canSelect and not isActor then
            -- Invalid target - red tint
            love.graphics.setColor(0.6, 0.3, 0.3, 0.2)
            love.graphics.rectangle("fill", plate.x, plate.y,
                M.LAYOUT.PLATE_WIDTH, plate:getHeight(), 4, 4)
        end
    end

    --- Draw connecting line during fellowship selection (S9.1)
    function screen:drawFellowshipLine()
        if not self.fellowshipActorIndex then return end

        local actorPlate = self.characterPlates[self.fellowshipActorIndex]
        if not actorPlate then return end

        -- Line start: center of actor plate
        local startX = actorPlate.x + M.LAYOUT.PLATE_WIDTH / 2
        local startY = actorPlate.y + actorPlate:getHeight() / 2

        -- Line end: either hovered plate center or mouse position
        local endX, endY
        if self.hoveredPlateIndex and self.hoveredPlateIndex ~= self.fellowshipActorIndex then
            local targetPlate = self.characterPlates[self.hoveredPlateIndex]
            if targetPlate then
                endX = targetPlate.x + M.LAYOUT.PLATE_WIDTH / 2
                endY = targetPlate.y + targetPlate:getHeight() / 2
            end
        end

        if not endX and love then
            endX, endY = love.mouse.getPosition()
        end

        if endX and endY then
            -- Draw glowing line
            love.graphics.setColor(0.70, 0.55, 0.85, 0.3)
            love.graphics.setLineWidth(6)
            love.graphics.line(startX, startY, endX, endY)

            love.graphics.setColor(0.70, 0.55, 0.85, 0.8)
            love.graphics.setLineWidth(2)
            love.graphics.line(startX, startY, endX, endY)

            love.graphics.setLineWidth(1)
        end
    end

    function screen:drawPCStatus(plate, pc, index)
        local currentState = self.campController and self.campController:getState()

        -- Show status based on current phase
        if currentState == camp_controller.STATES.ACTIONS then
            -- Show if action taken
            local actionTaken = self.campController.actionsCompleted[pc.id]
            local statusColor = actionTaken and self.colors.step_complete or self.colors.warning

            love.graphics.setColor(statusColor)
            local statusText = actionTaken and "Done" or "Needs Action"
            love.graphics.print(statusText, plate.x, plate.y - 15)

        elseif currentState == camp_controller.STATES.BREAK_BREAD then
            -- Show if ate
            local ate = self.campController.rationsConsumed[pc.id]
            local statusColor = ate and self.colors.step_complete or self.colors.warning

            love.graphics.setColor(statusColor)
            local statusText = ate and "Fed" or "Hungry"
            love.graphics.print(statusText, plate.x, plate.y - 15)

            -- S9.2: Show warning if no rations in inventory
            if not ate then
                local rationCount = self:countRationsFor(pc)
                if rationCount == 0 then
                    -- Draw warning icon (exclamation triangle)
                    self:drawNoRationWarning(plate.x + M.LAYOUT.PLATE_WIDTH - 25, plate.y + 5)
                else
                    -- Show ration count
                    love.graphics.setColor(self.colors.step_text)
                    love.graphics.print("x" .. rationCount, plate.x + M.LAYOUT.PLATE_WIDTH - 25, plate.y + 5)
                end
            end

        elseif currentState == camp_controller.STATES.RECOVERY then
            -- S9.2: Show stress gate warning
            if pc.conditions and pc.conditions.stressed then
                love.graphics.setColor(self.colors.warning)
                love.graphics.print("STRESSED - Must clear first!", plate.x, plate.y - 15)
            end
        end
    end

    --- Count rations in a PC's inventory (S9.2)
    function screen:countRationsFor(pc)
        if not pc.inventory or not pc.inventory.countItemsByPredicate then
            return 0
        end

        return pc.inventory:countItemsByPredicate(function(item)
            return item.isRation or
                   item.type == "ration" or
                   item.itemType == "ration" or
                   (item.properties and item.properties.isRation) or
                   (item.name and item.name:lower():find("ration"))
        end)
    end

    --- Draw no-ration warning icon (S9.2)
    function screen:drawNoRationWarning(x, y)
        -- Triangle with exclamation
        local size = 18

        -- Warning triangle background
        love.graphics.setColor(self.colors.warning)
        love.graphics.polygon("fill",
            x + size/2, y,
            x, y + size,
            x + size, y + size
        )

        -- Exclamation mark
        love.graphics.setColor(0.1, 0.1, 0.1, 1.0)
        love.graphics.rectangle("fill", x + size/2 - 1.5, y + 5, 3, 7)
        love.graphics.circle("fill", x + size/2, y + size - 4, 2)
    end

    function screen:drawBondsForPlate(plate, pcIndex)
        local pc = self.guild[pcIndex]
        if not pc or not pc.bonds then return end

        -- Draw bond indicators as small circles on the plate
        local bondX = plate.x + M.LAYOUT.PLATE_WIDTH - 30
        local bondY = plate.y + 5
        local bondSize = 12
        local bondSpacing = bondSize + 4

        local bondIndex = 0
        for targetId, bond in pairs(pc.bonds) do
            local bx = bondX
            local by = bondY + bondIndex * bondSpacing

            -- Bond circle
            local bondColor = bond.charged and self.colors.bond_charged or self.colors.bond_spent
            love.graphics.setColor(bondColor)
            love.graphics.circle("fill", bx, by, bondSize / 2)

            -- Border
            love.graphics.setColor(self.colors.panel_border)
            love.graphics.circle("line", bx, by, bondSize / 2)

            -- Hover highlight
            if self.hoveredBond and self.hoveredBond.pcIndex == pcIndex and self.hoveredBond.targetId == targetId then
                love.graphics.setColor(1, 1, 1, 0.3)
                love.graphics.circle("fill", bx, by, bondSize / 2 + 3)
            end

            bondIndex = bondIndex + 1
        end
    end

    function screen:drawActionPanel()
        local panelY = self.height - M.LAYOUT.ACTION_PANEL_HEIGHT
        local panelH = M.LAYOUT.ACTION_PANEL_HEIGHT

        -- Clear phase-specific button bounds (will be set by the appropriate panel)
        self.meatgrinderButtonBounds = nil
        self.breakCampButtonBounds = nil

        -- Background
        love.graphics.setColor(self.colors.panel_bg)
        love.graphics.rectangle("fill", 0, panelY, self.width, panelH)

        -- Border
        love.graphics.setColor(self.colors.panel_border)
        love.graphics.line(0, panelY, self.width, panelY)

        -- Content based on current state
        local currentState = self.campController and self.campController:getState() or camp_controller.STATES.INACTIVE

        if currentState == camp_controller.STATES.ACTIONS then
            self:drawActionsPanel(panelY)
        elseif currentState == camp_controller.STATES.BREAK_BREAD then
            self:drawBreakBreadPanel(panelY)
        elseif currentState == camp_controller.STATES.WATCH then
            self:drawWatchPanel(panelY)
        elseif currentState == camp_controller.STATES.RECOVERY then
            self:drawRecoveryPanel(panelY)
        elseif currentState == camp_controller.STATES.TEARDOWN then
            self:drawTeardownPanel(panelY)
        else
            self:drawGenericPanel(panelY, currentState)
        end

        -- Advance button (if applicable)
        if currentState ~= camp_controller.STATES.INACTIVE and currentState ~= camp_controller.STATES.TEARDOWN then
            self:drawAdvanceButton(panelY)
        end
    end

    function screen:drawActionsPanel(panelY)
        -- Different instructions for fellowship mode (S9.1)
        if self.fellowshipMode then
            love.graphics.setColor(self.colors.bond_charged)
            if self.fellowshipActor then
                love.graphics.print("FELLOWSHIP - Click another character to share a moment with " ..
                    self.fellowshipActor.name .. " (ESC to cancel)", M.LAYOUT.PADDING, panelY + 10)
            else
                love.graphics.print("FELLOWSHIP - Click a character to select them", M.LAYOUT.PADDING, panelY + 10)
            end

            love.graphics.setColor(self.colors.step_text)
            love.graphics.print("Both characters will charge their bond with each other.", M.LAYOUT.PADDING, panelY + 30)
            return
        end

        love.graphics.setColor(self.colors.step_text)
        love.graphics.print("CAMP ACTIONS - Click a character to assign their action", M.LAYOUT.PADDING, panelY + 10)

        -- Show pending characters
        local pending = self.campController:getPendingAdventurers()
        local pendingText = "Waiting: "
        for i, pc in ipairs(pending) do
            if i > 1 then pendingText = pendingText .. ", " end
            pendingText = pendingText .. pc.name
        end
        love.graphics.setColor(self.colors.warning)
        love.graphics.print(pendingText, M.LAYOUT.PADDING, panelY + 30)
    end

    function screen:drawBreakBreadPanel(panelY)
        love.graphics.setColor(self.colors.step_text)
        love.graphics.print("BREAK BREAD - Click characters to consume rations or go hungry", M.LAYOUT.PADDING, panelY + 10)

        local pending = self.campController:getPendingAdventurers()
        local pendingText = "Need to eat: "
        for i, pc in ipairs(pending) do
            if i > 1 then pendingText = pendingText .. ", " end
            pendingText = pendingText .. pc.name
        end
        love.graphics.setColor(self.colors.warning)
        love.graphics.print(pendingText, M.LAYOUT.PADDING, panelY + 30)
    end

    function screen:drawWatchPanel(panelY)
        love.graphics.setColor(self.colors.step_text)
        love.graphics.print("THE WATCH - Draw from the Meatgrinder to see what stirs in the night...", M.LAYOUT.PADDING, panelY + 10)

        if self.campController.patrolActive then
            love.graphics.setColor(self.colors.step_active)
            love.graphics.print("Patrol active - drawing twice!", M.LAYOUT.PADDING, panelY + 30)
        end

        -- Draw meatgrinder button (only if watch not yet resolved)
        if not self.campController.watchResolved then
            local btnW, btnH = 180, 40
            local btnX = self.width / 2 - btnW / 2
            local btnY = panelY + 50

            local isHover = self.hoverButton == "meatgrinder"

            -- Button background
            if isHover then
                love.graphics.setColor(0.45, 0.25, 0.20, 1.0)  -- Warm hover
            else
                love.graphics.setColor(0.35, 0.18, 0.15, 1.0)  -- Dark red-brown
            end
            love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 6, 6)

            -- Button border
            love.graphics.setColor(0.6, 0.35, 0.25, 1.0)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", btnX, btnY, btnW, btnH, 6, 6)
            love.graphics.setLineWidth(1)

            -- Button text
            love.graphics.setColor(self.colors.button_text)
            love.graphics.printf("Draw from Meatgrinder", btnX, btnY + 12, btnW, "center")

            -- Store bounds for click detection
            self.meatgrinderButtonBounds = { x = btnX, y = btnY, w = btnW, h = btnH }
        else
            -- Watch already resolved
            love.graphics.setColor(self.colors.step_complete)
            love.graphics.print("The night passes...", self.width / 2 - 60, panelY + 55)
            self.meatgrinderButtonBounds = nil
        end
    end

    function screen:drawRecoveryPanel(panelY)
        love.graphics.setColor(self.colors.step_text)
        love.graphics.print("RECOVERY - Click charged bonds to heal wounds, regain resolve, or clear stress", M.LAYOUT.PADDING, panelY + 10)
        love.graphics.print("Stressed characters must clear stress first!", M.LAYOUT.PADDING, panelY + 30)
    end

    function screen:drawTeardownPanel(panelY)
        love.graphics.setColor(self.colors.step_text)
        love.graphics.print("TEARDOWN - The party packs up camp and prepares to move on.", M.LAYOUT.PADDING, panelY + 10)

        -- Draw "Break Camp" button
        local btnW, btnH = 160, 40
        local btnX = self.width / 2 - btnW / 2
        local btnY = panelY + 50

        local isHover = self.hoverButton == "breakcamp"

        -- Button background
        if isHover then
            love.graphics.setColor(0.35, 0.45, 0.35, 1.0)  -- Green hover
        else
            love.graphics.setColor(0.25, 0.35, 0.25, 1.0)  -- Dark green
        end
        love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 6, 6)

        -- Button border
        love.graphics.setColor(0.4, 0.55, 0.4, 1.0)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", btnX, btnY, btnW, btnH, 6, 6)
        love.graphics.setLineWidth(1)

        -- Button text
        love.graphics.setColor(self.colors.button_text)
        love.graphics.printf("Break Camp", btnX, btnY + 12, btnW, "center")

        -- Store bounds for click detection
        self.breakCampButtonBounds = { x = btnX, y = btnY, w = btnW, h = btnH }
    end

    function screen:drawGenericPanel(panelY, state)
        love.graphics.setColor(self.colors.step_text)
        love.graphics.print("Camp Phase: " .. (state or "Unknown"), M.LAYOUT.PADDING, panelY + 10)
    end

    function screen:drawAdvanceButton(panelY)
        local btnW, btnH = 120, 35
        local btnX = self.width - btnW - M.LAYOUT.PADDING
        local btnY = panelY + M.LAYOUT.ACTION_PANEL_HEIGHT / 2 - btnH / 2

        -- S9.3: Cannot advance while prompt overlay is showing
        local isBlocked = self.promptOverlay ~= nil
        local isHover = self.hoverButton == "advance" and not isBlocked

        local btnColor
        if isBlocked then
            btnColor = { 0.25, 0.25, 0.25, 0.5 }  -- Greyed out
        elseif isHover then
            btnColor = self.colors.button_hover
        else
            btnColor = self.colors.button_bg
        end

        love.graphics.setColor(btnColor)
        love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 4, 4)

        love.graphics.setColor(self.colors.panel_border)
        love.graphics.rectangle("line", btnX, btnY, btnW, btnH, 4, 4)

        local textColor = isBlocked and { 0.5, 0.5, 0.5, 0.7 } or self.colors.button_text
        love.graphics.setColor(textColor)
        love.graphics.printf("Next Step", btnX, btnY + 10, btnW, "center")

        -- Store button bounds for click detection (nil if blocked)
        self.advanceButtonBounds = isBlocked and nil or { x = btnX, y = btnY, w = btnW, h = btnH }
    end

    function screen:drawActionMenu()
        local menuX = self.actionMenuX
        local menuY = self.actionMenuY
        local menuW = 200
        local itemH = 30
        local menuH = #self.actionMenuItems * itemH + 10

        -- Keep menu on screen
        if menuX + menuW > self.width then
            menuX = self.width - menuW - 10
        end
        if menuY + menuH > self.height - M.LAYOUT.ACTION_PANEL_HEIGHT then
            menuY = self.height - M.LAYOUT.ACTION_PANEL_HEIGHT - menuH - 10
        end

        -- Background
        love.graphics.setColor(self.colors.panel_bg)
        love.graphics.rectangle("fill", menuX, menuY, menuW, menuH, 4, 4)

        -- Border
        love.graphics.setColor(self.colors.panel_border)
        love.graphics.rectangle("line", menuX, menuY, menuW, menuH, 4, 4)

        -- Items
        for i, item in ipairs(self.actionMenuItems) do
            local itemY = menuY + 5 + (i - 1) * itemH
            local isHover = self.hoverButton == "action_" .. i

            if isHover then
                love.graphics.setColor(self.colors.button_hover)
                love.graphics.rectangle("fill", menuX + 2, itemY, menuW - 4, itemH - 2, 2, 2)
            end

            love.graphics.setColor(self.colors.button_text)
            love.graphics.print(item.name, menuX + 10, itemY + 6)
        end

        -- Store bounds
        self.actionMenuBounds = { x = menuX, y = menuY, w = menuW, h = menuH, itemH = itemH }
    end

    ----------------------------------------------------------------------------
    -- INPUT HANDLING
    ----------------------------------------------------------------------------

    function screen:mousepressed(x, y, button)
        if button ~= 1 then return end

        local currentState = self.campController and self.campController:getState()

        -- S9.3: Check prompt overlay click (dismisses it)
        if self.promptOverlay then
            self:dismissPromptOverlay()
            return
        end

        -- S9.1: Handle fellowship mode clicks
        if self.fellowshipMode then
            self:handleFellowshipClick(x, y)
            return
        end

        -- Check action menu click
        if self.actionMenuOpen then
            if self:handleActionMenuClick(x, y) then
                return
            else
                self.actionMenuOpen = false
            end
        end

        -- Check meatgrinder button (Watch phase)
        if self.meatgrinderButtonBounds then
            local btn = self.meatgrinderButtonBounds
            if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
                self:handleMeatgrinderClick()
                return
            end
        end

        -- Check break camp button (Teardown phase)
        if self.breakCampButtonBounds then
            local btn = self.breakCampButtonBounds
            if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
                self:handleBreakCampClick()
                return
            end
        end

        -- Check advance button
        if self.advanceButtonBounds then
            local btn = self.advanceButtonBounds
            if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
                self:handleAdvanceClick()
                return
            end
        end

        -- Check character plate clicks
        for i, plate in ipairs(self.characterPlates) do
            if x >= plate.x and x <= plate.x + M.LAYOUT.PLATE_WIDTH and
               y >= plate.y and y <= plate.y + plate:getHeight() then

                if currentState == camp_controller.STATES.ACTIONS then
                    self:openActionMenuFor(i, x, y)
                elseif currentState == camp_controller.STATES.BREAK_BREAD then
                    self:handleBreakBreadClick(i)
                elseif currentState == camp_controller.STATES.RECOVERY then
                    self:handleRecoveryClick(i, x, y)
                end
                return
            end
        end
    end

    function screen:mousereleased(x, y, button)
        -- Nothing special for now
    end

    function screen:mousemoved(x, y, dx, dy)
        self.hoverButton = nil
        self.hoveredBond = nil
        self.hoveredPlateIndex = nil

        -- Check which plate is hovered (for fellowship mode)
        for i, plate in ipairs(self.characterPlates) do
            if x >= plate.x and x <= plate.x + M.LAYOUT.PLATE_WIDTH and
               y >= plate.y and y <= plate.y + plate:getHeight() then
                self.hoveredPlateIndex = i
                break
            end
        end

        -- Check meatgrinder button hover
        if self.meatgrinderButtonBounds then
            local btn = self.meatgrinderButtonBounds
            if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
                self.hoverButton = "meatgrinder"
            end
        end

        -- Check break camp button hover
        if self.breakCampButtonBounds then
            local btn = self.breakCampButtonBounds
            if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
                self.hoverButton = "breakcamp"
            end
        end

        -- Check advance button hover
        if self.advanceButtonBounds then
            local btn = self.advanceButtonBounds
            if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
                self.hoverButton = "advance"
            end
        end

        -- Check action menu hover
        if self.actionMenuOpen and self.actionMenuBounds then
            local menu = self.actionMenuBounds
            if x >= menu.x and x <= menu.x + menu.w and y >= menu.y and y <= menu.y + menu.h then
                local itemIndex = math.floor((y - menu.y - 5) / menu.itemH) + 1
                if itemIndex >= 1 and itemIndex <= #self.actionMenuItems then
                    self.hoverButton = "action_" .. itemIndex
                end
            end
        end

        -- Check bond hover (during recovery)
        local currentState = self.campController and self.campController:getState()
        if currentState == camp_controller.STATES.RECOVERY then
            for i, plate in ipairs(self.characterPlates) do
                local pc = self.guild[i]
                if pc and pc.bonds then
                    local bondX = plate.x + M.LAYOUT.PLATE_WIDTH - 30
                    local bondY = plate.y + 5
                    local bondSize = 12
                    local bondSpacing = bondSize + 4

                    local bondIndex = 0
                    for targetId, bond in pairs(pc.bonds) do
                        local bx = bondX
                        local by = bondY + bondIndex * bondSpacing
                        local dist = math.sqrt((x - bx)^2 + (y - by)^2)
                        if dist < bondSize then
                            self.hoveredBond = { pcIndex = i, targetId = targetId, bond = bond }
                        end
                        bondIndex = bondIndex + 1
                    end
                end
            end
        end
    end

    function screen:keypressed(key)
        if key == "escape" then
            -- Cancel fellowship mode first, then action menu
            if self.fellowshipMode then
                self:cancelFellowshipMode()
            elseif self.actionMenuOpen then
                self.actionMenuOpen = false
            end
        end
    end

    --- Cancel fellowship selection mode (S9.1)
    function screen:cancelFellowshipMode()
        self.fellowshipMode = false
        self.fellowshipActor = nil
        self.fellowshipActorIndex = nil
        print("[CampScreen] Fellowship cancelled")
    end

    ----------------------------------------------------------------------------
    -- ACTION HANDLERS
    ----------------------------------------------------------------------------

    function screen:openActionMenuFor(pcIndex, x, y)
        local pc = self.guild[pcIndex]
        if not pc then return end

        -- Check if already submitted action
        if self.campController.actionsCompleted[pc.id] then
            return
        end

        self.selectedPC = pc
        self.actionMenuX = x
        self.actionMenuY = y

        -- Get available actions
        self.actionMenuItems = camp_actions.getAvailableActions(pc, self.guild)
        self.actionMenuOpen = true
    end

    function screen:handleActionMenuClick(x, y)
        if not self.actionMenuBounds then return false end

        local menu = self.actionMenuBounds
        if x < menu.x or x > menu.x + menu.w or y < menu.y or y > menu.y + menu.h then
            return false
        end

        local itemIndex = math.floor((y - menu.y - 5) / menu.itemH) + 1
        if itemIndex >= 1 and itemIndex <= #self.actionMenuItems then
            local action = self.actionMenuItems[itemIndex]
            self:submitCampAction(self.selectedPC, action)
            self.actionMenuOpen = false
            return true
        end

        return false
    end

    function screen:submitCampAction(pc, actionDef)
        if not pc or not actionDef then return end

        -- S9.1: Fellowship requires two-character selection mode
        if actionDef.id == "fellowship" then
            self:enterFellowshipMode(pc)
            return
        end

        -- Build action data
        local actionData = {
            type = actionDef.id,
        }

        -- Handle target selection for actions that need it
        if actionDef.requiresTarget then
            if actionDef.targetType == "pc" then
                -- For other PC-targeting actions, pick first other PC (simplified)
                for _, other in ipairs(self.guild) do
                    if other.id ~= pc.id then
                        actionData.target = other
                        break
                    end
                end
            end
            -- Other target types would need more UI (item picker, etc.)
        end

        -- Submit to controller
        local success, result = self.campController:submitAction(pc, actionData)
        if success then
            print("[CampScreen] Action submitted: " .. actionDef.name)
        else
            print("[CampScreen] Action failed: " .. (result or "unknown"))
        end
    end

    --- Enter fellowship selection mode (S9.1)
    function screen:enterFellowshipMode(actorPC)
        -- Find actor's index
        local actorIndex = nil
        for i, pc in ipairs(self.guild) do
            if pc.id == actorPC.id then
                actorIndex = i
                break
            end
        end

        self.fellowshipMode = true
        self.fellowshipActor = actorPC
        self.fellowshipActorIndex = actorIndex
        self.actionMenuOpen = false

        print("[CampScreen] Entering fellowship mode for " .. actorPC.name)
    end

    --- Handle clicks during fellowship mode (S9.1)
    function screen:handleFellowshipClick(x, y)
        -- Check if clicking on a character plate
        for i, plate in ipairs(self.characterPlates) do
            if x >= plate.x and x <= plate.x + M.LAYOUT.PLATE_WIDTH and
               y >= plate.y and y <= plate.y + plate:getHeight() then

                local targetPC = self.guild[i]
                if not targetPC then return end

                -- Clicking self cancels selection
                if self.fellowshipActor and targetPC.id == self.fellowshipActor.id then
                    self:cancelFellowshipMode()
                    return
                end

                -- Check if bond already charged
                if self.fellowshipActor and self.fellowshipActor.bonds and
                   self.fellowshipActor.bonds[targetPC.id] and
                   self.fellowshipActor.bonds[targetPC.id].charged then
                    print("[CampScreen] Bond with " .. targetPC.name .. " is already charged!")
                    return
                end

                -- Submit fellowship action with target
                local actionData = {
                    type = "fellowship",
                    target = targetPC,
                }

                local success, result = self.campController:submitAction(self.fellowshipActor, actionData)
                if success then
                    print("[CampScreen] Fellowship completed: " .. self.fellowshipActor.name ..
                          " and " .. targetPC.name)
                else
                    print("[CampScreen] Fellowship failed: " .. (result or "unknown"))
                end

                -- Exit fellowship mode
                self:cancelFellowshipMode()
                return
            end
        end

        -- Clicking elsewhere cancels
        self:cancelFellowshipMode()
    end

    function screen:handleBreakBreadClick(pcIndex)
        local pc = self.guild[pcIndex]
        if not pc then return end

        -- Check if already resolved
        if self.campController.rationsConsumed[pc.id] then
            return
        end

        -- Try to consume ration
        local success, result = self.campController:consumeRation(pc)
        print("[CampScreen] Break bread for " .. pc.name .. ": " .. (result or "?"))
    end

    function screen:handleRecoveryClick(pcIndex, x, y)
        local pc = self.guild[pcIndex]
        if not pc then return end

        -- Check if clicked on a bond
        if self.hoveredBond and self.hoveredBond.pcIndex == pcIndex then
            local bond = self.hoveredBond.bond
            local targetId = self.hoveredBond.targetId

            if bond.charged then
                -- Determine spend type based on conditions
                local spendType = "heal_wound"
                if pc.conditions and pc.conditions.stressed then
                    spendType = "clear_stress"
                end

                local success, result = self.campController:spendBondForRecovery(pc, targetId, spendType)
                print("[CampScreen] Bond spent: " .. (result or "failed"))
            else
                print("[CampScreen] Bond is not charged")
            end
        end
    end

    function screen:handleMeatgrinderClick()
        if not self.campController then return end

        local success, err = self.campController:resolveWatch()
        if success then
            print("[CampScreen] Meatgrinder drawn - watch resolved")
        else
            print("[CampScreen] Watch failed: " .. (err or "unknown"))
        end
    end

    function screen:handleBreakCampClick()
        if not self.campController then return end

        -- advanceStep from TEARDOWN calls endCamp() which emits phase_changed
        local success, err = self.campController:advanceStep()
        if success then
            print("[CampScreen] Camp broken - returning to crawl")
        else
            print("[CampScreen] Break camp failed: " .. (err or "unknown"))
        end
    end

    function screen:handleAdvanceClick()
        if not self.campController then return end

        local success, err = self.campController:advanceStep()
        if success then
            print("[CampScreen] Advanced to next step")
        else
            print("[CampScreen] Cannot advance: " .. (err or "unknown"))
        end
    end

    return screen
end

return M
