-- character_sheet.lua
-- Character Sheet Modal for Majesty
-- Ticket S11.1: Full stats, talents, and inventory view
--
-- Layout:
-- +----------+------------------+----------+
-- |  LEFT    |     CENTER       |  RIGHT   |
-- |  Stats   |    Inventory     | Talents  |
-- +----------+------------------+----------+

local events = require('logic.events')
local inventory = require('logic.inventory')

local M = {}

--------------------------------------------------------------------------------
-- LAYOUT CONSTANTS
--------------------------------------------------------------------------------

M.LAYOUT = {
    PADDING = 15,
    HEADER_HEIGHT = 60,
    LEFT_WIDTH = 200,
    RIGHT_WIDTH = 200,
    SLOT_SIZE = 42,
    SLOT_SPACING = 4,
}

--------------------------------------------------------------------------------
-- COLORS
--------------------------------------------------------------------------------

M.COLORS = {
    overlay = { 0, 0, 0, 0.85 },
    panel_bg = { 0.12, 0.12, 0.15, 0.98 },
    panel_border = { 0.4, 0.35, 0.3, 1 },
    header_bg = { 0.18, 0.15, 0.12, 1 },
    text = { 0.9, 0.88, 0.82, 1 },
    text_dim = { 0.6, 0.58, 0.55, 1 },
    text_highlight = { 1, 0.9, 0.6, 1 },
    slot_empty = { 0.15, 0.15, 0.18, 1 },
    slot_filled = { 0.25, 0.22, 0.2, 1 },
    slot_hover = { 0.35, 0.32, 0.28, 1 },
    condition_bad = { 0.9, 0.3, 0.25, 1 },
    condition_neutral = { 0.7, 0.65, 0.5, 1 },
    talent_mastered = { 0.4, 0.7, 0.4, 1 },
    talent_training = { 0.7, 0.6, 0.3, 1 },
    talent_wounded = { 0.7, 0.3, 0.3, 1 },
}

--------------------------------------------------------------------------------
-- CHARACTER SHEET FACTORY
--------------------------------------------------------------------------------

function M.createCharacterSheet(config)
    config = config or {}

    local sheet = {
        eventBus = config.eventBus or events.globalBus,
        guild = config.guild or {},

        -- State
        isOpen = false,
        selectedPC = nil,
        selectedPCIndex = 1,

        -- Layout (calculated on open)
        x = 0,
        y = 0,
        width = 0,
        height = 0,

        -- Hover state
        hoveredSlot = nil,
        hoveredSlotLocation = nil,
        hoveredTalent = nil,

        -- Tooltip
        tooltip = nil,

        -- Drag state (for S11.2)
        dragging = nil,
        dragOffsetX = 0,
        dragOffsetY = 0,
        dragSourceLocation = nil,
        dragSourceIndex = nil,

        -- S11.2: Slot bounds for drop detection
        slotBounds = {},  -- { location_index = { x, y, w, h, location, index } }
    }

    ----------------------------------------------------------------------------
    -- OPEN/CLOSE
    ----------------------------------------------------------------------------

    function sheet:open(pcIndex)
        self.isOpen = true
        self.selectedPCIndex = pcIndex or self.selectedPCIndex
        if self.selectedPCIndex > #self.guild then
            self.selectedPCIndex = 1
        end
        self.selectedPC = self.guild[self.selectedPCIndex]
        self:calculateLayout()
        self.eventBus:emit("character_sheet_opened", { pc = self.selectedPC })
    end

    function sheet:close()
        self.isOpen = false
        self.selectedPC = nil
        self.hoveredSlot = nil
        self.hoveredTalent = nil
        self.tooltip = nil
        self.dragging = nil
        self.eventBus:emit("character_sheet_closed", {})
    end

    function sheet:toggle(pcIndex)
        if self.isOpen then
            self:close()
        else
            self:open(pcIndex)
        end
    end

    ----------------------------------------------------------------------------
    -- LAYOUT
    ----------------------------------------------------------------------------

    function sheet:calculateLayout()
        if not love then return end

        local screenW, screenH = love.graphics.getDimensions()
        local padding = 40

        self.width = screenW - padding * 2
        self.height = screenH - padding * 2
        self.x = padding
        self.y = padding

        -- Calculate column widths
        self.leftColumnX = self.x + M.LAYOUT.PADDING
        self.leftColumnW = M.LAYOUT.LEFT_WIDTH

        self.rightColumnX = self.x + self.width - M.LAYOUT.RIGHT_WIDTH - M.LAYOUT.PADDING
        self.rightColumnW = M.LAYOUT.RIGHT_WIDTH

        self.centerColumnX = self.leftColumnX + self.leftColumnW + M.LAYOUT.PADDING
        self.centerColumnW = self.rightColumnX - self.centerColumnX - M.LAYOUT.PADDING
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function sheet:update(dt)
        if not self.isOpen then return end
        -- Animation updates could go here
    end

    ----------------------------------------------------------------------------
    -- DRAW
    ----------------------------------------------------------------------------

    function sheet:draw()
        if not self.isOpen or not love then return end
        if not self.selectedPC then return end

        local pc = self.selectedPC

        -- Dark overlay
        love.graphics.setColor(M.COLORS.overlay)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())

        -- Main panel
        love.graphics.setColor(M.COLORS.panel_bg)
        love.graphics.rectangle("fill", self.x, self.y, self.width, self.height, 8, 8)

        love.graphics.setColor(M.COLORS.panel_border)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", self.x, self.y, self.width, self.height, 8, 8)
        love.graphics.setLineWidth(1)

        -- Header
        self:drawHeader(pc)

        -- Three columns
        local contentY = self.y + M.LAYOUT.HEADER_HEIGHT + M.LAYOUT.PADDING

        self:drawLeftColumn(pc, contentY)
        self:drawCenterColumn(pc, contentY)
        self:drawRightColumn(pc, contentY)

        -- Tooltip (on top)
        self:drawTooltip()

        -- Draw dragged item (on very top)
        self:drawDraggedItem()

        -- Instructions
        love.graphics.setColor(M.COLORS.text_dim)
        love.graphics.print("Tab: Close | 1-4: Switch Character", self.x + 10, self.y + self.height - 25)
    end

    function sheet:drawHeader(pc)
        local headerY = self.y
        local headerH = M.LAYOUT.HEADER_HEIGHT

        -- Header background
        love.graphics.setColor(M.COLORS.header_bg)
        love.graphics.rectangle("fill", self.x, headerY, self.width, headerH, 8, 0)

        -- Character name
        love.graphics.setColor(M.COLORS.text_highlight)
        love.graphics.print(pc.name or "Unknown", self.x + M.LAYOUT.PADDING, headerY + 10)

        -- Motifs
        love.graphics.setColor(M.COLORS.text_dim)
        local motifText = table.concat(pc.motifs or {}, " | ")
        love.graphics.print(motifText, self.x + M.LAYOUT.PADDING, headerY + 32)

        -- Gold and XP (right side)
        local rightX = self.x + self.width - M.LAYOUT.PADDING - 150
        love.graphics.setColor(M.COLORS.text)
        love.graphics.print("Gold: " .. (pc.gold or 0), rightX, headerY + 10)
        love.graphics.print("XP: " .. (pc.xp or 0), rightX, headerY + 32)

        -- PC selector tabs
        local tabX = self.x + 200
        for i, guildPC in ipairs(self.guild) do
            local isSelected = (i == self.selectedPCIndex)
            local tabW = 80
            local tx = tabX + (i - 1) * (tabW + 5)

            if isSelected then
                love.graphics.setColor(0.3, 0.25, 0.2, 1)
            else
                love.graphics.setColor(0.15, 0.13, 0.12, 1)
            end
            love.graphics.rectangle("fill", tx, headerY + 5, tabW, 25, 4, 4)

            love.graphics.setColor(isSelected and M.COLORS.text_highlight or M.COLORS.text_dim)
            love.graphics.print(guildPC.name, tx + 5, headerY + 10)
        end
    end

    function sheet:drawLeftColumn(pc, startY)
        local x = self.leftColumnX
        local y = startY
        local w = self.leftColumnW

        -- Section: Attributes
        love.graphics.setColor(M.COLORS.text_highlight)
        love.graphics.print("ATTRIBUTES", x, y)
        y = y + 25

        local attributes = {
            { name = "Swords", value = pc.swords or 0, color = {0.8, 0.3, 0.3} },
            { name = "Pentacles", value = pc.pentacles or 0, color = {0.3, 0.7, 0.3} },
            { name = "Cups", value = pc.cups or 0, color = {0.3, 0.5, 0.9} },
            { name = "Wands", value = pc.wands or 0, color = {0.8, 0.6, 0.2} },
        }

        for _, attr in ipairs(attributes) do
            love.graphics.setColor(attr.color)
            love.graphics.print(attr.name .. ":", x, y)
            love.graphics.setColor(M.COLORS.text)
            love.graphics.print(tostring(attr.value), x + 90, y)
            y = y + 22
        end

        y = y + 15

        -- Section: Resolve
        love.graphics.setColor(M.COLORS.text_highlight)
        love.graphics.print("RESOLVE", x, y)
        y = y + 25

        local resolve = pc.resolve or { current = 4, max = 4 }
        love.graphics.setColor(M.COLORS.text)
        love.graphics.print(resolve.current .. " / " .. resolve.max, x, y)

        -- Draw resolve pips
        local pipX = x + 60
        for i = 1, resolve.max do
            if i <= resolve.current then
                love.graphics.setColor(0.3, 0.7, 0.9, 1)
                love.graphics.circle("fill", pipX + (i - 1) * 18, y + 8, 6)
            else
                love.graphics.setColor(0.3, 0.3, 0.3, 1)
                love.graphics.circle("line", pipX + (i - 1) * 18, y + 8, 6)
            end
        end
        y = y + 30

        -- Section: Conditions
        love.graphics.setColor(M.COLORS.text_highlight)
        love.graphics.print("CONDITIONS", x, y)
        y = y + 25

        local conditions = pc.conditions or {}
        local conditionList = { "staggered", "injured", "deaths_door", "stressed", "rooted" }
        local hasCondition = false

        for _, cond in ipairs(conditionList) do
            if conditions[cond] then
                hasCondition = true
                love.graphics.setColor(M.COLORS.condition_bad)
                love.graphics.print("* " .. cond:gsub("_", " "):upper(), x, y)
                y = y + 20
            end
        end

        if not hasCondition then
            love.graphics.setColor(M.COLORS.text_dim)
            love.graphics.print("None", x, y)
        end

        y = y + 25

        -- Section: Armor
        love.graphics.setColor(M.COLORS.text_highlight)
        love.graphics.print("ARMOR", x, y)
        y = y + 25

        local armorSlots = pc.armorSlots or 0
        local armorNotches = pc.armorNotches or 0
        love.graphics.setColor(M.COLORS.text)
        love.graphics.print("Notches: " .. armorNotches .. " / " .. armorSlots, x, y)
    end

    function sheet:drawCenterColumn(pc, startY)
        local x = self.centerColumnX
        local y = startY
        local slotSize = M.LAYOUT.SLOT_SIZE
        local spacing = M.LAYOUT.SLOT_SPACING

        -- S11.2: Clear slot bounds at start of draw
        self.slotBounds = {}

        -- Section: Hands (2 slots)
        love.graphics.setColor(M.COLORS.text_highlight)
        love.graphics.print("HANDS", x, y)
        y = y + 25

        local hands = pc.inventory and pc.inventory:getItems("hands") or {}
        for i = 1, 2 do
            local item = hands[i]
            self:drawInventorySlot(x + (i - 1) * (slotSize + spacing), y, slotSize, item, "hands", i)
        end
        y = y + slotSize + 20

        -- Section: Belt (4 slots)
        love.graphics.setColor(M.COLORS.text_highlight)
        love.graphics.print("BELT", x, y)
        y = y + 25

        local belt = pc.inventory and pc.inventory:getItems("belt") or {}
        for i = 1, 4 do
            local item = belt[i]
            self:drawInventorySlot(x + (i - 1) * (slotSize + spacing), y, slotSize, item, "belt", i)
        end
        y = y + slotSize + 20

        -- Section: Pack (21 slots in grid)
        love.graphics.setColor(M.COLORS.text_highlight)
        love.graphics.print("PACK", x, y)
        y = y + 25

        local pack = pc.inventory and pc.inventory:getItems("pack") or {}
        local cols = 7
        for i = 1, 21 do
            local row = math.floor((i - 1) / cols)
            local col = (i - 1) % cols
            local item = pack[i]
            local slotX = x + col * (slotSize + spacing)
            local slotY = y + row * (slotSize + spacing)
            self:drawInventorySlot(slotX, slotY, slotSize, item, "pack", i)
        end
    end

    function sheet:drawInventorySlot(x, y, size, item, location, index)
        local isHovered = (self.hoveredSlot == index and self.hoveredSlotLocation == location)
        local isDragSource = (self.dragging and self.dragSourceLocation == location and self.dragSourceIndex == index)

        -- S11.2: Store slot bounds for drop detection (always, not just for filled slots)
        local boundsKey = location .. "_" .. index
        self.slotBounds[boundsKey] = { x = x, y = y, w = size, h = size, location = location, index = index }

        -- S11.2: Check if this is a valid drop target
        local isValidDropTarget = false
        local isInvalidDropTarget = false
        if self.dragging and not isDragSource then
            isValidDropTarget = self:canDropAt(location, index)
            isInvalidDropTarget = not isValidDropTarget
        end

        -- Slot background
        if isDragSource then
            -- Dim the source slot while dragging
            love.graphics.setColor(0.1, 0.1, 0.12, 0.5)
        elseif isValidDropTarget then
            -- Highlight valid drop targets
            love.graphics.setColor(0.2, 0.4, 0.3, 0.9)
        elseif isInvalidDropTarget then
            -- Show invalid drop targets
            love.graphics.setColor(0.3, 0.15, 0.15, 0.9)
        elseif item then
            love.graphics.setColor(isHovered and M.COLORS.slot_hover or M.COLORS.slot_filled)
        else
            love.graphics.setColor(M.COLORS.slot_empty)
        end
        love.graphics.rectangle("fill", x, y, size, size, 4, 4)

        -- Slot border
        if isValidDropTarget then
            love.graphics.setColor(0.3, 0.8, 0.4, 1)
            love.graphics.setLineWidth(2)
        elseif isInvalidDropTarget then
            love.graphics.setColor(0.8, 0.3, 0.3, 1)
            love.graphics.setLineWidth(2)
        elseif isHovered and item then
            love.graphics.setColor(M.COLORS.text_highlight)
            love.graphics.setLineWidth(2)
        else
            love.graphics.setColor(0.4, 0.4, 0.4, 0.6)
            love.graphics.setLineWidth(1)
        end
        love.graphics.rectangle("line", x, y, size, size, 4, 4)
        love.graphics.setLineWidth(1)

        -- Item display (skip if this is the drag source)
        if item and not isDragSource then
            -- Item icon (first letter)
            love.graphics.setColor(M.COLORS.text)
            local initial = string.sub(item.name or "?", 1, 2)
            love.graphics.print(initial, x + 4, y + 4)

            -- Quantity for stackables
            if item.stackable and item.quantity and item.quantity > 1 then
                love.graphics.setColor(M.COLORS.text_dim)
                love.graphics.print("x" .. item.quantity, x + size - 20, y + size - 14)
            end

            -- Durability indicator (notches)
            if item.notches and item.notches > 0 then
                love.graphics.setColor(M.COLORS.condition_bad)
                for n = 1, item.notches do
                    love.graphics.rectangle("fill", x + size - 6, y + 4 + (n - 1) * 6, 4, 4)
                end
            end
        end

        -- Store slot bounds on item too for backward compatibility
        if item then
            item._slotBounds = self.slotBounds[boundsKey]
        end
    end

    --- S11.2: Check if dragged item can be dropped at location
    function sheet:canDropAt(location, index)
        if not self.dragging then return false end

        local item = self.dragging

        -- Oversized items can only go on belt
        if item.oversized and location ~= "belt" then
            return false
        end

        -- Armor can only go on belt
        if item.isArmor and location ~= "belt" then
            return false
        end

        -- Check if slot has room
        if not self.selectedPC or not self.selectedPC.inventory then
            return false
        end

        -- For now, allow dropping anywhere with available slots
        -- The inventory:swap() method will handle actual validation
        return true
    end

    function sheet:drawRightColumn(pc, startY)
        local x = self.rightColumnX
        local y = startY
        local w = self.rightColumnW

        -- Section: Talents
        love.graphics.setColor(M.COLORS.text_highlight)
        love.graphics.print("TALENTS", x, y)
        y = y + 25

        local talents = pc.talents or {}
        local hasTalents = false

        for talentId, talentData in pairs(talents) do
            hasTalents = true
            local isHovered = (self.hoveredTalent == talentId)

            -- Background for hover
            if isHovered then
                love.graphics.setColor(0.25, 0.22, 0.2, 1)
                love.graphics.rectangle("fill", x - 5, y - 2, w + 10, 22, 3, 3)
            end

            -- Talent name with status color
            if talentData.wounded then
                love.graphics.setColor(M.COLORS.talent_wounded)
            elseif talentData.mastered then
                love.graphics.setColor(M.COLORS.talent_mastered)
            else
                love.graphics.setColor(M.COLORS.talent_training)
            end

            local displayName = talentId:gsub("_", " "):gsub("^%l", string.upper)
            local status = talentData.mastered and "[M]" or "[T]"
            if talentData.wounded then status = "[W]" end

            love.graphics.print(status .. " " .. displayName, x, y)
            y = y + 24
        end

        if not hasTalents then
            love.graphics.setColor(M.COLORS.text_dim)
            love.graphics.print("None", x, y)
        end

        y = y + 25

        -- Section: Bonds
        love.graphics.setColor(M.COLORS.text_highlight)
        love.graphics.print("BONDS", x, y)
        y = y + 25

        local bonds = pc.bonds or {}
        local hasBonds = false

        for entityId, bondData in pairs(bonds) do
            hasBonds = true
            local bondedPC = nil
            for _, gpc in ipairs(self.guild) do
                if gpc.id == entityId then
                    bondedPC = gpc
                    break
                end
            end

            local name = bondedPC and bondedPC.name or entityId
            local status = bondData.status:gsub("_", " ")
            local charged = bondData.charged and "*" or ""

            love.graphics.setColor(bondData.charged and M.COLORS.talent_mastered or M.COLORS.text_dim)
            love.graphics.print(charged .. name .. ": " .. status, x, y)
            y = y + 20
        end

        if not hasBonds then
            love.graphics.setColor(M.COLORS.text_dim)
            love.graphics.print("None", x, y)
        end
    end

    function sheet:drawTooltip()
        if not self.tooltip then return end

        local mouseX, mouseY = love.mouse.getPosition()
        local padding = 8
        local maxWidth = 250

        -- Measure text
        local font = love.graphics.getFont()
        local textWidth = math.min(font:getWidth(self.tooltip.text), maxWidth)
        local textHeight = font:getHeight() * math.ceil(font:getWidth(self.tooltip.text) / maxWidth)

        local tipX = mouseX + 15
        local tipY = mouseY + 10
        local tipW = textWidth + padding * 2
        local tipH = textHeight + padding * 2

        -- Keep on screen
        local screenW, screenH = love.graphics.getDimensions()
        if tipX + tipW > screenW then tipX = mouseX - tipW - 5 end
        if tipY + tipH > screenH then tipY = mouseY - tipH - 5 end

        -- Background
        love.graphics.setColor(0.1, 0.1, 0.12, 0.95)
        love.graphics.rectangle("fill", tipX, tipY, tipW, tipH, 4, 4)

        love.graphics.setColor(0.4, 0.35, 0.3, 1)
        love.graphics.rectangle("line", tipX, tipY, tipW, tipH, 4, 4)

        -- Text
        love.graphics.setColor(M.COLORS.text)
        love.graphics.printf(self.tooltip.text, tipX + padding, tipY + padding, maxWidth)
    end

    function sheet:drawDraggedItem()
        if not self.dragging then return end

        local mouseX, mouseY = love.mouse.getPosition()
        local size = M.LAYOUT.SLOT_SIZE

        love.graphics.setColor(0.4, 0.35, 0.3, 0.9)
        love.graphics.rectangle("fill", mouseX - size/2, mouseY - size/2, size, size, 4, 4)

        love.graphics.setColor(M.COLORS.text)
        local initial = string.sub(self.dragging.name or "?", 1, 2)
        love.graphics.print(initial, mouseX - size/2 + 4, mouseY - size/2 + 4)
    end

    ----------------------------------------------------------------------------
    -- INPUT
    ----------------------------------------------------------------------------

    function sheet:keypressed(key)
        if not self.isOpen then
            -- Tab opens sheet
            if key == "tab" then
                self:open(1)
                return true
            end
            return false
        end

        -- Tab closes sheet
        if key == "tab" or key == "escape" then
            self:close()
            return true
        end

        -- Number keys switch character
        local keyNum = tonumber(key)
        if keyNum and keyNum >= 1 and keyNum <= #self.guild then
            self.selectedPCIndex = keyNum
            self.selectedPC = self.guild[keyNum]
            return true
        end

        return true  -- Consume all input when open
    end

    function sheet:mousepressed(x, y, button)
        if not self.isOpen then return false end

        -- Check if clicking outside panel to close
        if x < self.x or x > self.x + self.width or
           y < self.y or y > self.y + self.height then
            self:close()
            return true
        end

        -- Check PC tabs in header
        local tabX = self.x + 200
        local tabY = self.y + 5
        for i = 1, #self.guild do
            local tx = tabX + (i - 1) * 85
            if x >= tx and x < tx + 80 and y >= tabY and y < tabY + 25 then
                self.selectedPCIndex = i
                self.selectedPC = self.guild[i]
                return true
            end
        end

        -- Check inventory slots for drag start (S11.2)
        if button == 1 and self.hoveredSlot and self.hoveredSlotLocation then
            local items = self.selectedPC.inventory:getItems(self.hoveredSlotLocation)
            local item = items[self.hoveredSlot]
            if item then
                self.dragging = item
                self.dragSourceLocation = self.hoveredSlotLocation
                self.dragSourceIndex = self.hoveredSlot
                return true
            end
        end

        return true  -- Consume all clicks when open
    end

    function sheet:mousereleased(x, y, button)
        if not self.isOpen then return false end

        -- Handle drag drop (S11.2)
        if self.dragging and button == 1 then
            self:handleDrop(x, y)
            self.dragging = nil
            self.dragSourceLocation = nil
            self.dragSourceIndex = nil
            return true
        end

        return true
    end

    function sheet:mousemoved(x, y, dx, dy)
        if not self.isOpen then return false end

        self.hoveredSlot = nil
        self.hoveredSlotLocation = nil
        self.hoveredTalent = nil
        self.tooltip = nil

        if not self.selectedPC then return true end

        -- S11.2: Check inventory slot hover using slotBounds (works for empty slots too)
        for boundsKey, bounds in pairs(self.slotBounds) do
            if x >= bounds.x and x < bounds.x + bounds.w and
               y >= bounds.y and y < bounds.y + bounds.h then
                self.hoveredSlot = bounds.index
                self.hoveredSlotLocation = bounds.location

                -- Get item at this slot
                local items = self.selectedPC.inventory and self.selectedPC.inventory:getItems(bounds.location) or {}
                local item = items[bounds.index]

                if item then
                    -- Build tooltip
                    local tipLines = { item.name }
                    if item.properties then
                        if item.properties.light_source then
                            table.insert(tipLines, "Light source (" .. (item.properties.flicker_count or 0) .. " flickers)")
                        end
                    end
                    if item.durability then
                        table.insert(tipLines, "Durability: " .. (item.durability - (item.notches or 0)) .. "/" .. item.durability)
                    end
                    if item.size and item.size > 1 then
                        table.insert(tipLines, "Size: " .. item.size .. " slots")
                    end
                    if item.oversized then
                        table.insert(tipLines, "Oversized (Belt only)")
                    end

                    self.tooltip = { text = table.concat(tipLines, "\n") }
                end
                return true
            end
        end

        -- Check talent hover
        local talents = self.selectedPC.talents or {}
        local ty = self.y + M.LAYOUT.HEADER_HEIGHT + M.LAYOUT.PADDING + 25
        for talentId, talentData in pairs(talents) do
            if x >= self.rightColumnX and x < self.rightColumnX + self.rightColumnW and
               y >= ty and y < ty + 22 then
                self.hoveredTalent = talentId

                -- Build talent tooltip
                local status = talentData.mastered and "Mastered" or "In Training"
                if talentData.wounded then status = "Wounded" end
                self.tooltip = { text = talentId:gsub("_", " "):upper() .. "\n" .. status }
                return true
            end
            ty = ty + 24
        end

        return true
    end

    ----------------------------------------------------------------------------
    -- DRAG & DROP (S11.2)
    ----------------------------------------------------------------------------

    function sheet:handleDrop(x, y)
        if not self.dragging or not self.selectedPC then return end

        -- Find target slot using slotBounds
        local targetLoc = nil
        local targetIndex = nil

        for boundsKey, bounds in pairs(self.slotBounds) do
            if x >= bounds.x and x < bounds.x + bounds.w and
               y >= bounds.y and y < bounds.y + bounds.h then
                targetLoc = bounds.location
                targetIndex = bounds.index
                break
            end
        end

        -- Check if valid drop
        if not targetLoc then
            print("[INVENTORY] Dropped outside slots - cancelled")
            return
        end

        -- Same slot - no action
        if targetLoc == self.dragSourceLocation and targetIndex == self.dragSourceIndex then
            return
        end

        -- Check if we can drop here
        if not self:canDropAt(targetLoc, targetIndex) then
            print("[INVENTORY] Invalid drop location: " .. targetLoc)
            return
        end

        -- Perform the move
        local success, reason = self.selectedPC.inventory:swap(self.dragging.id, targetLoc)
        if success then
            print("[INVENTORY] Moved " .. self.dragging.name .. " to " .. targetLoc)
            self.eventBus:emit("inventory_changed", {
                entity = self.selectedPC,
                item = self.dragging,
                from = self.dragSourceLocation,
                to = targetLoc,
            })
        else
            print("[INVENTORY] Move failed: " .. (reason or "unknown"))
            -- Visual feedback for failure could be added here
        end
    end

    --- Get the slot at a given position
    function sheet:getSlotAt(x, y)
        for boundsKey, bounds in pairs(self.slotBounds) do
            if x >= bounds.x and x < bounds.x + bounds.w and
               y >= bounds.y and y < bounds.y + bounds.h then
                return bounds.location, bounds.index
            end
        end
        return nil, nil
    end

    return sheet
end

return M
