-- input_manager.lua
-- Global Input & Drag-and-Drop Manager for Majesty
-- Ticket T2_11: Handle clicking POIs for "Looking" and dragging entities/items for "Acting"
--
-- Design:
-- - Click on POI = Open scrutiny menu (T2_13)
-- - Drag Adventurer/Item onto POI = Trigger investigation
-- - Uses AABB collision for "sticky" targets

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- DRAG STATE CONSTANTS
--------------------------------------------------------------------------------
M.DRAG_TYPES = {
    NONE       = "none",
    ADVENTURER = "adventurer",
    ITEM       = "item",
}

-- Minimum movement to distinguish drag from click (pixels)
local CLICK_THRESHOLD = 5

--------------------------------------------------------------------------------
-- INPUT MANAGER FACTORY
--------------------------------------------------------------------------------

--- Create a new InputManager
-- @param config table: { eventBus, roomManager }
-- @return InputManager instance
function M.createInputManager(config)
    config = config or {}

    local manager = {
        eventBus    = config.eventBus or events.globalBus,
        roomManager = config.roomManager,

        -- Drag state
        isDragging     = false,
        dragType       = M.DRAG_TYPES.NONE,
        dragSource     = nil,       -- The object being dragged
        dragStartX     = 0,
        dragStartY     = 0,
        currentMouseX  = 0,
        currentMouseY  = 0,

        -- Click detection
        pressStartX    = 0,
        pressStartY    = 0,
        pressTarget    = nil,       -- What was under mouse on press
        pressTime      = 0,

        -- UI state
        isLocked       = false,     -- True when a menu is open
        activeMenu     = nil,       -- Current open menu (focus_menu)

        -- Registered hitboxes
        -- Each entry: { id, type, x, y, width, height, data }
        hitboxes       = {},

        -- Drop targets (POIs that can receive drops)
        dropTargets    = {},
    }

    ----------------------------------------------------------------------------
    -- HITBOX REGISTRATION
    -- UI components register their clickable areas here
    ----------------------------------------------------------------------------

    --- Register a hitbox for click/drop detection
    -- @param id string: Unique identifier
    -- @param hitboxType string: "poi", "adventurer", "item", "button"
    -- @param x, y, width, height number: Bounding box
    -- @param data table: Associated data (entity, poi, etc.)
    function manager:registerHitbox(id, hitboxType, x, y, width, height, data)
        self.hitboxes[id] = {
            id     = id,
            type   = hitboxType,
            x      = x,
            y      = y,
            width  = width,
            height = height,
            data   = data or {},
        }

        -- POIs are also drop targets
        if hitboxType == "poi" then
            self.dropTargets[id] = self.hitboxes[id]
        end
    end

    --- Unregister a hitbox
    function manager:unregisterHitbox(id)
        self.hitboxes[id] = nil
        self.dropTargets[id] = nil
    end

    --- Clear all hitboxes (call when room changes)
    function manager:clearHitboxes()
        self.hitboxes = {}
        self.dropTargets = {}
    end

    --- Update a hitbox position (for text reflow)
    function manager:updateHitbox(id, x, y, width, height)
        local hb = self.hitboxes[id]
        if hb then
            hb.x = x
            hb.y = y
            if width then hb.width = width end
            if height then hb.height = height end
        end
    end

    ----------------------------------------------------------------------------
    -- COLLISION DETECTION (AABB)
    ----------------------------------------------------------------------------

    --- Check if point is inside a hitbox
    local function pointInBox(px, py, box)
        return px >= box.x and px <= box.x + box.width and
               py >= box.y and py <= box.y + box.height
    end

    --- Get hitbox at a screen position
    -- @param x, y number: Screen coordinates
    -- @param filterType string|nil: Only return hitboxes of this type
    -- @return hitbox or nil
    function manager:getHitboxAt(x, y, filterType)
        for _, hb in pairs(self.hitboxes) do
            if pointInBox(x, y, hb) then
                if not filterType or hb.type == filterType then
                    return hb
                end
            end
        end
        return nil
    end

    --- Get drop target at a screen position
    -- @return hitbox or nil
    function manager:getDropTarget(x, y)
        for _, hb in pairs(self.dropTargets) do
            if pointInBox(x, y, hb) then
                return hb
            end
        end
        return nil
    end

    ----------------------------------------------------------------------------
    -- DRAG/DROP LIFECYCLE
    ----------------------------------------------------------------------------

    --- Begin dragging an object
    -- @param source table: The object being dragged (adventurer, item)
    -- @param dragType string: One of DRAG_TYPES
    -- @param x, y number: Start position
    function manager:beginDrag(source, dragType, x, y)
        self.isDragging = true
        self.dragType = dragType
        self.dragSource = source
        self.dragStartX = x
        self.dragStartY = y
        self.currentMouseX = x
        self.currentMouseY = y

        self.eventBus:emit(events.EVENTS.DRAG_BEGIN, {
            source = source,
            dragType = dragType,
            x = x,
            y = y,
        })
    end

    --- Update drag position (call from love.mousemoved)
    function manager:updateDrag(x, y)
        if self.isDragging then
            self.currentMouseX = x
            self.currentMouseY = y
        end
    end

    --- End dragging and check for drop
    -- @param x, y number: Release position
    -- @return table: { success, target, action }
    function manager:endDrag(x, y)
        if not self.isDragging then
            return { success = false }
        end

        local result = {
            success = false,
            source = self.dragSource,
            dragType = self.dragType,
            target = nil,
            action = nil,
        }

        -- Check for valid drop target
        local target = self:getDropTarget(x, y)
        if target then
            result.success = true
            result.target = target

            -- Determine action based on drag type
            if self.dragType == M.DRAG_TYPES.ADVENTURER then
                result.action = "investigate"
            elseif self.dragType == M.DRAG_TYPES.ITEM then
                result.action = "use_item"
            end

            self.eventBus:emit(events.EVENTS.DROP_ON_TARGET, {
                source = self.dragSource,
                dragType = self.dragType,
                target = target,
                action = result.action,
            })
        else
            -- No valid target - return to origin
            self.eventBus:emit(events.EVENTS.DRAG_CANCELLED, {
                source = self.dragSource,
                dragType = self.dragType,
            })
        end

        -- Reset drag state
        self.isDragging = false
        self.dragType = M.DRAG_TYPES.NONE
        self.dragSource = nil

        return result
    end

    --- Cancel current drag
    function manager:cancelDrag()
        if self.isDragging then
            self.eventBus:emit(events.EVENTS.DRAG_CANCELLED, {
                source = self.dragSource,
                dragType = self.dragType,
            })
        end

        self.isDragging = false
        self.dragType = M.DRAG_TYPES.NONE
        self.dragSource = nil
    end

    --- Clear drag state without emitting events
    -- Use when an external system has already handled the drop
    function manager:clearDragState()
        self.isDragging = false
        self.dragType = M.DRAG_TYPES.NONE
        self.dragSource = nil
    end

    ----------------------------------------------------------------------------
    -- CLICK DETECTION
    ----------------------------------------------------------------------------

    --- Handle mouse press
    -- @param x, y number: Screen position
    -- @param button number: Mouse button (1 = left)
    function manager:onMousePressed(x, y, button)
        if button ~= 1 then return end  -- Only handle left click
        if self.isLocked then return end  -- UI is locked

        self.pressStartX = x
        self.pressStartY = y
        self.pressTime = love and love.timer.getTime() or os.time()
        self.pressTarget = self:getHitboxAt(x, y)

        -- Check if pressing on a draggable
        if self.pressTarget then
            local hbType = self.pressTarget.type
            if hbType == "adventurer" then
                self:beginDrag(self.pressTarget.data, M.DRAG_TYPES.ADVENTURER, x, y)
            elseif hbType == "item" then
                self:beginDrag(self.pressTarget.data, M.DRAG_TYPES.ITEM, x, y)
            end
        end
    end

    --- Handle mouse release
    -- @param x, y number: Screen position
    -- @param button number: Mouse button
    function manager:onMouseReleased(x, y, button)
        if button ~= 1 then return end

        -- If we were dragging, handle drop
        if self.isDragging then
            local dragDistance = math.sqrt(
                (x - self.pressStartX)^2 + (y - self.pressStartY)^2
            )

            if dragDistance < CLICK_THRESHOLD then
                -- Didn't move enough - treat as click, not drag
                self:cancelDrag()
                self:handleClick(x, y)
            else
                -- Actual drag completed
                self:endDrag(x, y)
            end
            return
        end

        -- Regular click handling
        self:handleClick(x, y)
    end

    --- Handle a click (press + release without significant drag)
    function manager:handleClick(x, y)
        local target = self:getHitboxAt(x, y)

        if not target then
            -- Clicked empty space - close any open menu
            if self.activeMenu then
                self:closeMenu()
            end
            return
        end

        -- Handle based on target type
        if target.type == "poi" then
            -- Open scrutiny menu for this POI
            self.eventBus:emit(events.EVENTS.POI_CLICKED, {
                poiId = target.id,
                poi = target.data,
                x = x,
                y = y,
            })
        elseif target.type == "button" then
            -- Button clicked
            if target.data.onClick then
                target.data.onClick()
            end
            self.eventBus:emit(events.EVENTS.BUTTON_CLICKED, {
                buttonId = target.id,
                data = target.data,
            })
        end
    end

    --- Handle mouse movement
    function manager:onMouseMoved(x, y, dx, dy)
        self.currentMouseX = x
        self.currentMouseY = y

        if self.isDragging then
            self:updateDrag(x, y)
        end
    end

    ----------------------------------------------------------------------------
    -- UI LOCKING (for menus)
    ----------------------------------------------------------------------------

    --- Lock UI (prevent interaction while menu is open)
    function manager:lockUI(menu)
        self.isLocked = true
        self.activeMenu = menu
    end

    --- Unlock UI
    function manager:unlockUI()
        self.isLocked = false
        self.activeMenu = nil
    end

    --- Close the active menu
    function manager:closeMenu()
        if self.activeMenu and self.activeMenu.close then
            self.activeMenu:close()
        end
        self:unlockUI()
    end

    ----------------------------------------------------------------------------
    -- RENDERING HELPERS
    ----------------------------------------------------------------------------

    --- Get drag ghost position and data for rendering
    -- @return table|nil: { source, dragType, x, y } or nil if not dragging
    function manager:getDragGhost()
        if not self.isDragging then
            return nil
        end

        return {
            source   = self.dragSource,
            dragType = self.dragType,
            x        = self.currentMouseX,
            y        = self.currentMouseY,
        }
    end

    --- Check if a drop target is currently hovered
    function manager:isHoveringDropTarget()
        if not self.isDragging then
            return false, nil
        end

        local target = self:getDropTarget(self.currentMouseX, self.currentMouseY)
        return target ~= nil, target
    end

    ----------------------------------------------------------------------------
    -- LÖVE 2D INTEGRATION HELPERS
    ----------------------------------------------------------------------------

    --- Convenience function to hook into love.mousepressed
    function manager:mousepressed(x, y, button)
        self:onMousePressed(x, y, button)
    end

    --- Convenience function to hook into love.mousereleased
    function manager:mousereleased(x, y, button)
        self:onMouseReleased(x, y, button)
    end

    --- Convenience function to hook into love.mousemoved
    function manager:mousemoved(x, y, dx, dy)
        self:onMouseMoved(x, y, dx, dy)
    end

    return manager
end

return M
