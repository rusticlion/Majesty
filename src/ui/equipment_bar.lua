-- equipment_bar.lua
-- Equipment Bar HUD for Majesty
-- Shows Hands (2 slots) and Belt (4 slots) for the selected PC
-- Items can be dragged from here onto POIs to interact with the world
--
-- Design: Pack items cannot be used directly - only hands/belt items
-- can interact with POIs via drag-and-drop.

local M = {}

local events = require('logic.events')

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

M.SLOT_SIZE = 44
M.SLOT_SPACING = 4
M.SECTION_SPACING = 16  -- Gap between hands and belt sections
M.PADDING = 10

M.HANDS_SLOTS = 2
M.BELT_SLOTS = 4

--------------------------------------------------------------------------------
-- COLORS
--------------------------------------------------------------------------------

M.COLORS = {
    panel_bg = { 0.12, 0.11, 0.10, 0.95 },
    panel_border = { 0.4, 0.35, 0.3, 1 },

    hands_bg = { 0.18, 0.15, 0.12, 1 },
    hands_label = { 0.9, 0.8, 0.6, 1 },

    belt_bg = { 0.15, 0.14, 0.12, 1 },
    belt_label = { 0.7, 0.7, 0.65, 1 },

    slot_empty = { 0.1, 0.1, 0.12, 1 },
    slot_filled = { 0.22, 0.2, 0.18, 1 },
    slot_hover = { 0.35, 0.3, 0.25, 1 },
    slot_dragging = { 0.4, 0.35, 0.25, 0.5 },

    slot_border = { 0.4, 0.35, 0.3, 0.8 },
    slot_border_hover = { 0.9, 0.8, 0.5, 1 },

    text = { 0.9, 0.88, 0.82, 1 },
    text_dim = { 0.6, 0.58, 0.55, 1 },
    text_quantity = { 1, 1, 1, 0.9 },
}

--------------------------------------------------------------------------------
-- EQUIPMENT BAR FACTORY
--------------------------------------------------------------------------------

function M.createEquipmentBar(config)
    config = config or {}

    local bar = {
        eventBus = config.eventBus or events.globalBus,
        inputManager = config.inputManager,
        guild = config.guild or {},

        -- Position (set by crawl_screen layout)
        x = config.x or 0,
        y = config.y or 0,

        -- Selected PC
        selectedPC = 1,

        -- Hover/drag state
        hoveredSlot = nil,      -- { location = "hands"|"belt", index = 1-N }
        dragging = nil,         -- { item, location, index, startX, startY }
        dragOffsetX = 0,
        dragOffsetY = 0,

        -- Calculated dimensions
        width = 0,
        height = 0,

        -- Slot bounds for hit detection
        slotBounds = {},  -- [location_index] = { x, y, w, h, location, index }

        isVisible = true,
    }

    ----------------------------------------------------------------------------
    -- LAYOUT CALCULATION
    ----------------------------------------------------------------------------

    function bar:calculateLayout()
        -- Total width: hands section + spacing + belt section
        local handsWidth = M.HANDS_SLOTS * (M.SLOT_SIZE + M.SLOT_SPACING) - M.SLOT_SPACING
        local beltWidth = M.BELT_SLOTS * (M.SLOT_SIZE + M.SLOT_SPACING) - M.SLOT_SPACING

        self.width = M.PADDING * 2 + handsWidth + M.SECTION_SPACING + beltWidth
        self.height = M.PADDING * 2 + 18 + M.SLOT_SIZE  -- label + slots

        -- Calculate slot bounds
        self.slotBounds = {}

        local slotY = self.y + M.PADDING + 18

        -- Hands slots
        local handsStartX = self.x + M.PADDING
        for i = 1, M.HANDS_SLOTS do
            local slotX = handsStartX + (i - 1) * (M.SLOT_SIZE + M.SLOT_SPACING)
            local key = "hands_" .. i
            self.slotBounds[key] = {
                x = slotX,
                y = slotY,
                w = M.SLOT_SIZE,
                h = M.SLOT_SIZE,
                location = "hands",
                index = i,
            }
        end

        -- Belt slots
        local beltStartX = handsStartX + handsWidth + M.SECTION_SPACING
        for i = 1, M.BELT_SLOTS do
            local slotX = beltStartX + (i - 1) * (M.SLOT_SIZE + M.SLOT_SPACING)
            local key = "belt_" .. i
            self.slotBounds[key] = {
                x = slotX,
                y = slotY,
                w = M.SLOT_SIZE,
                h = M.SLOT_SIZE,
                location = "belt",
                index = i,
            }
        end
    end

    ----------------------------------------------------------------------------
    -- PC SELECTION
    ----------------------------------------------------------------------------

    function bar:setSelectedPC(index)
        if index >= 1 and index <= #self.guild then
            self.selectedPC = index
        end
    end

    function bar:getSelectedPC()
        if self.selectedPC >= 1 and self.selectedPC <= #self.guild then
            return self.guild[self.selectedPC]
        end
        return nil
    end

    ----------------------------------------------------------------------------
    -- ITEM ACCESS
    ----------------------------------------------------------------------------

    function bar:getItemAt(location, index)
        local pc = self:getSelectedPC()
        if not pc or not pc.inventory then return nil end

        local items = pc.inventory:getItems(location)
        return items[index]
    end

    ----------------------------------------------------------------------------
    -- DRAGGING
    ----------------------------------------------------------------------------

    function bar:startDrag(location, index, mouseX, mouseY)
        local item = self:getItemAt(location, index)
        if not item then return false end

        local key = location .. "_" .. index
        local bounds = self.slotBounds[key]
        if not bounds then return false end

        self.dragging = {
            item = item,
            location = location,
            index = index,
            startX = bounds.x,
            startY = bounds.y,
        }

        self.dragOffsetX = mouseX - bounds.x
        self.dragOffsetY = mouseY - bounds.y

        -- Notify input manager that we're dragging an item
        if self.inputManager then
            self.inputManager:beginDrag(item, "item", mouseX, mouseY)
        end

        return true
    end

    function bar:updateDrag(mouseX, mouseY)
        if not self.dragging then return end

        -- Update input manager drag position
        if self.inputManager then
            self.inputManager:updateDrag(mouseX, mouseY)
        end
    end

    function bar:endDrag(mouseX, mouseY)
        if not self.dragging then return nil end

        local dragData = self.dragging
        self.dragging = nil

        -- Check if dropped on a POI via input manager
        if self.inputManager then
            -- Get drop target (POI) at mouse position
            local target = nil
            if self.inputManager.getDropTarget then
                target = self.inputManager:getDropTarget(mouseX, mouseY)
            end

            if target and target.type == "poi" then
                -- Emit item-use event
                self.eventBus:emit(events.EVENTS.USE_ITEM_ON_POI, {
                    item = dragData.item,
                    itemLocation = dragData.location,
                    poiId = target.id,
                    poi = target.data,
                    user = self:getSelectedPC(),
                })

                -- Clear drag state without emitting DROP_ON_TARGET (we handled it)
                self.inputManager:clearDragState()
                return { action = "use_on_poi", target = target }
            end

            -- No valid target - item snaps back to origin slot (visual only)
            self.inputManager:clearDragState()
        end

        -- Dropped on empty space - item returns to its slot automatically
        return nil
    end

    function bar:cancelDrag()
        self.dragging = nil
        if self.inputManager then
            self.inputManager:cancelDrag()
        end
    end

    ----------------------------------------------------------------------------
    -- HIT TESTING
    ----------------------------------------------------------------------------

    function bar:getSlotAt(x, y)
        for key, bounds in pairs(self.slotBounds) do
            if x >= bounds.x and x < bounds.x + bounds.w and
               y >= bounds.y and y < bounds.y + bounds.h then
                return bounds.location, bounds.index, key
            end
        end
        return nil, nil, nil
    end

    function bar:isPointInside(x, y)
        return x >= self.x and x < self.x + self.width and
               y >= self.y and y < self.y + self.height
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function bar:update(dt)
        if not self.isVisible then return end
        if not love then return end

        local mouseX, mouseY = love.mouse.getPosition()

        -- Update hover state (only if not dragging)
        if not self.dragging then
            local loc, idx = self:getSlotAt(mouseX, mouseY)
            if loc then
                self.hoveredSlot = { location = loc, index = idx }
            else
                self.hoveredSlot = nil
            end
        end

        -- Update drag position
        if self.dragging then
            self:updateDrag(mouseX, mouseY)
        end
    end

    ----------------------------------------------------------------------------
    -- DRAW
    ----------------------------------------------------------------------------

    function bar:draw()
        if not self.isVisible then return end
        if not love then return end

        local pc = self:getSelectedPC()
        if not pc then return end

        -- Panel background
        love.graphics.setColor(M.COLORS.panel_bg)
        love.graphics.rectangle("fill", self.x, self.y, self.width, self.height, 6, 6)

        love.graphics.setColor(M.COLORS.panel_border)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", self.x, self.y, self.width, self.height, 6, 6)

        -- Get items
        local handsItems = {}
        local beltItems = {}
        if pc.inventory then
            handsItems = pc.inventory:getItems("hands")
            beltItems = pc.inventory:getItems("belt")
        end

        -- Draw hands section
        self:drawSection("hands", "Hands", handsItems, M.HANDS_SLOTS, M.COLORS.hands_label)

        -- Draw belt section
        self:drawSection("belt", "Belt", beltItems, M.BELT_SLOTS, M.COLORS.belt_label)

        -- Draw PC name
        love.graphics.setColor(M.COLORS.text_dim)
        love.graphics.print(pc.name, self.x + self.width - 60, self.y + 4)

        -- Draw drag ghost
        self:drawDragGhost()
    end

    function bar:drawSection(location, label, items, maxSlots, labelColor)
        -- Find first slot of this section for positioning
        local firstKey = location .. "_1"
        local firstBounds = self.slotBounds[firstKey]
        if not firstBounds then return end

        -- Section label
        love.graphics.setColor(labelColor)
        love.graphics.print(label, firstBounds.x, self.y + M.PADDING)

        -- Draw slots
        for i = 1, maxSlots do
            local key = location .. "_" .. i
            local bounds = self.slotBounds[key]
            if bounds then
                local item = items[i]
                self:drawSlot(bounds, item, location, i)
            end
        end
    end

    function bar:drawSlot(bounds, item, location, index)
        local isHovered = self.hoveredSlot and
                          self.hoveredSlot.location == location and
                          self.hoveredSlot.index == index
        local isDragSource = self.dragging and
                             self.dragging.location == location and
                             self.dragging.index == index

        -- Slot background
        if isDragSource then
            love.graphics.setColor(M.COLORS.slot_dragging)
        elseif item and isHovered then
            love.graphics.setColor(M.COLORS.slot_hover)
        elseif item then
            love.graphics.setColor(M.COLORS.slot_filled)
        else
            love.graphics.setColor(M.COLORS.slot_empty)
        end
        love.graphics.rectangle("fill", bounds.x, bounds.y, bounds.w, bounds.h, 4, 4)

        -- Slot border
        if isHovered and item and not isDragSource then
            love.graphics.setColor(M.COLORS.slot_border_hover)
            love.graphics.setLineWidth(2)
        else
            love.graphics.setColor(M.COLORS.slot_border)
            love.graphics.setLineWidth(1)
        end
        love.graphics.rectangle("line", bounds.x, bounds.y, bounds.w, bounds.h, 4, 4)
        love.graphics.setLineWidth(1)

        -- Item content (skip if being dragged)
        if item and not isDragSource then
            self:drawItemInSlot(item, bounds.x, bounds.y, bounds.w, bounds.h)
        end
    end

    function bar:drawItemInSlot(item, x, y, w, h)
        -- Item icon (simple colored circle with initial)
        local iconColor = self:getItemColor(item)
        love.graphics.setColor(iconColor)
        love.graphics.circle("fill", x + w/2, y + h/2, w/3)

        -- Item initial
        love.graphics.setColor(M.COLORS.text)
        local initial = string.sub(item.name or "?", 1, 1):upper()
        local font = love.graphics.getFont()
        local textW = font:getWidth(initial)
        local textH = font:getHeight()
        love.graphics.print(initial, x + w/2 - textW/2, y + h/2 - textH/2)

        -- Quantity for stackables
        if item.stackable and item.quantity and item.quantity > 1 then
            love.graphics.setColor(M.COLORS.text_quantity)
            love.graphics.print("x" .. item.quantity, x + w - 20, y + h - 14)
        end

        -- Lit indicator for light sources
        if item.properties and item.properties.is_lit then
            love.graphics.setColor(1, 0.9, 0.3, 0.9)
            love.graphics.circle("fill", x + w - 8, y + 8, 4)
        end
    end

    function bar:getItemColor(item)
        if item.properties and item.properties.key then
            return { 0.8, 0.7, 0.3 }  -- Gold for keys
        elseif item.properties and item.properties.light_source then
            if item.properties.is_lit then
                return { 1, 0.8, 0.3 }  -- Bright orange when lit
            else
                return { 0.7, 0.4, 0.2 }  -- Brown when unlit
            end
        elseif item.weaponType then
            return { 0.6, 0.6, 0.7 }  -- Steel for weapons
        elseif item.isRation then
            return { 0.5, 0.7, 0.4 }  -- Green for food
        elseif item.properties and item.properties.potion then
            return { 0.4, 0.5, 0.8 }  -- Blue for potions
        else
            return { 0.5, 0.5, 0.5 }  -- Gray default
        end
    end

    function bar:drawDragGhost()
        if not self.dragging then return end

        local mouseX, mouseY = love.mouse.getPosition()
        local item = self.dragging.item

        -- Draw ghost at mouse position
        local ghostX = mouseX - self.dragOffsetX
        local ghostY = mouseY - self.dragOffsetY

        -- Semi-transparent background
        love.graphics.setColor(0.2, 0.2, 0.25, 0.9)
        love.graphics.rectangle("fill", ghostX, ghostY, M.SLOT_SIZE, M.SLOT_SIZE, 4, 4)

        -- Item content
        self:drawItemInSlot(item, ghostX, ghostY, M.SLOT_SIZE, M.SLOT_SIZE)

        -- Drag hint
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.print("Drop on POI", ghostX, ghostY + M.SLOT_SIZE + 2)
    end

    ----------------------------------------------------------------------------
    -- INPUT HANDLING
    ----------------------------------------------------------------------------

    function bar:mousepressed(x, y, button)
        if not self.isVisible then return false end
        if button ~= 1 then return false end

        local location, index = self:getSlotAt(x, y)
        if location then
            local item = self:getItemAt(location, index)
            if item then
                -- Start dragging
                self:startDrag(location, index, x, y)
                return true
            end
        end

        return false
    end

    function bar:mousereleased(x, y, button)
        if not self.isVisible then return false end
        if button ~= 1 then return false end

        if self.dragging then
            self:endDrag(x, y)
            return true
        end

        return false
    end

    function bar:mousemoved(x, y, dx, dy)
        if not self.isVisible then return false end

        if self.dragging then
            self:updateDrag(x, y)
            return true
        end

        return false
    end

    function bar:init()
        -- Sync with global active PC state
        if gameState and gameState.activePCIndex then
            self.selectedPC = gameState.activePCIndex
        end

        -- Listen for active PC changes
        self.eventBus:on(events.EVENTS.ACTIVE_PC_CHANGED, function(data)
            self.selectedPC = data.newIndex
        end)
    end

    function bar:keypressed(key)
        if not self.isVisible then return false end

        -- Backtick to cycle selected PC
        if key == "`" then
            -- Use global cycleActivePC if available, otherwise fallback to local
            if cycleActivePC then
                cycleActivePC()
            else
                self.selectedPC = (self.selectedPC % #self.guild) + 1
            end
            return true
        end

        -- Escape to cancel drag
        if key == "escape" and self.dragging then
            self:cancelDrag()
            return true
        end

        return false
    end

    -- Initialize layout
    bar:calculateLayout()

    return bar
end

return M
