-- belt_hotbar.lua
-- Belt Hotbar HUD for Majesty
-- Ticket S10.3: Quick-access belt items and ammo display
--
-- Displays belt items for the selected PC with one-click use.
-- Also shows ammo counts for ranged characters.

local M = {}

local events = require('logic.events')

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

M.SLOT_SIZE = 48
M.SLOT_SPACING = 6
M.SLOT_PADDING = 8
M.MAX_SLOTS = 4  -- Belt has 4 slots

--------------------------------------------------------------------------------
-- BELT HOTBAR FACTORY
--------------------------------------------------------------------------------

--- Create a new BeltHotbar instance
-- @param config table: { eventBus, guild, x, y }
-- @return BeltHotbar instance
function M.createBeltHotbar(config)
    config = config or {}

    local hotbar = {
        eventBus = config.eventBus or events.globalBus,
        guild = config.guild or {},
        x = config.x or 10,
        y = config.y or 400,

        -- Currently selected PC (0 = none, 1-4 = guild index)
        selectedPC = 1,

        -- Hover state
        hoveredSlot = nil,

        -- Visibility
        isVisible = true,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function hotbar:init()
        -- Sync with global active PC state
        if gameState and gameState.activePCIndex then
            self.selectedPC = gameState.activePCIndex
        end

        -- Listen for active PC changes
        self.eventBus:on(events.EVENTS.ACTIVE_PC_CHANGED, function(data)
            self.selectedPC = data.newIndex
        end)
    end

    ----------------------------------------------------------------------------
    -- PC SELECTION
    ----------------------------------------------------------------------------

    --- Set the currently selected PC
    function hotbar:setSelectedPC(index)
        if index >= 1 and index <= #self.guild then
            self.selectedPC = index
        end
    end

    --- Get the currently selected PC
    function hotbar:getSelectedPC()
        if self.selectedPC >= 1 and self.selectedPC <= #self.guild then
            return self.guild[self.selectedPC]
        end
        return nil
    end

    ----------------------------------------------------------------------------
    -- ITEM USE
    ----------------------------------------------------------------------------

    local function isItemLit(item)
        local props = item and item.properties
        if not props then return false end
        if props.isLit ~= nil then return props.isLit end
        if props.is_lit ~= nil then return props.is_lit end
        return false
    end

    local function setItemLit(item, lit)
        if not item.properties then
            item.properties = {}
        end
        item.properties.isLit = lit
        item.properties.is_lit = lit
    end

    --- Use an item from the belt
    -- @param slotIndex number: 1-4 belt slot
    function hotbar:useItem(slotIndex)
        local pc = self:getSelectedPC()
        if not pc or not pc.inventory then return false end

        local beltItems = pc.inventory:getItems("belt")
        if slotIndex > #beltItems then return false end

        local item = beltItems[slotIndex]
        if not item then return false end

        -- Handle different item types
        if item.properties and item.properties.light_source then
            -- Torch/Lantern - activate light
            self:useLight(pc, item)
            return true
        elseif item.isRation or item.type == "ration" or
               (item.name and item.name:lower():find("ration")) then
            -- Ration - eat it
            self:useRation(pc, item)
            return true
        elseif item.name and item.name:lower():find("potion") then
            -- Potion - use it
            self:usePotion(pc, item)
            return true
        end

        print("[HOTBAR] Cannot use item: " .. item.name)
        return false
    end

    --- Use a light source
    function hotbar:useLight(pc, item)
        local flickerCount = item.properties.flicker_count or 3

        -- Check if already lit
        if isItemLit(item) then
            print("[HOTBAR] " .. pc.name .. " extinguishes " .. item.name)
            setItemLit(item, false)
            self.eventBus:emit(events.EVENTS.LIGHT_SOURCE_TOGGLED, {
                entity = pc,
                item = item,
                lit = false,
            })
        else
            print("[HOTBAR] " .. pc.name .. " lights " .. item.name .. " (" .. flickerCount .. " flickers remaining)")
            setItemLit(item, true)
            self.eventBus:emit(events.EVENTS.LIGHT_SOURCE_TOGGLED, {
                entity = pc,
                item = item,
                lit = true,
            })
        end
    end

    --- Use a ration
    function hotbar:useRation(pc, item)
        print("[HOTBAR] " .. pc.name .. " eats a ration")

        -- Remove one ration
        pc.inventory:removeItemQuantity(item.id, 1)

        -- Heal starvation if present
        if pc.starvationCount and pc.starvationCount > 0 then
            pc.starvationCount = pc.starvationCount - 1
            print("[HOTBAR] Starvation reduced to " .. pc.starvationCount)
        end

        self.eventBus:emit("ration_consumed", {
            entity = pc,
            item = item,
        })
    end

    --- Use a potion
    function hotbar:usePotion(pc, item)
        print("[HOTBAR] " .. pc.name .. " drinks " .. item.name)

        -- Remove potion
        pc.inventory:removeItem(item.id)

        -- TODO: Apply potion effects based on type
        self.eventBus:emit("potion_consumed", {
            entity = pc,
            item = item,
        })
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function hotbar:update(dt)
        -- Update hover state based on mouse position
        if not self.isVisible then return end

        local mouseX, mouseY = love.mouse.getPosition()
        self.hoveredSlot = nil

        local pc = self:getSelectedPC()
        if not pc or not pc.inventory then return end

        local beltItems = pc.inventory:getItems("belt")
        for i = 1, M.MAX_SLOTS do
            local slotX = self.x + (i - 1) * (M.SLOT_SIZE + M.SLOT_SPACING)
            local slotY = self.y

            if mouseX >= slotX and mouseX < slotX + M.SLOT_SIZE and
               mouseY >= slotY and mouseY < slotY + M.SLOT_SIZE then
                self.hoveredSlot = i
                break
            end
        end
    end

    ----------------------------------------------------------------------------
    -- DRAW
    ----------------------------------------------------------------------------

    function hotbar:draw()
        if not self.isVisible then return end
        if not love then return end

        local pc = self:getSelectedPC()
        if not pc then return end

        local beltItems = {}
        if pc.inventory then
            beltItems = pc.inventory:getItems("belt")
        end

        -- Draw PC name label
        love.graphics.setColor(0.8, 0.8, 0.8, 0.9)
        love.graphics.print(pc.name .. "'s Belt", self.x, self.y - 18)

        -- Draw belt slots
        for i = 1, M.MAX_SLOTS do
            local slotX = self.x + (i - 1) * (M.SLOT_SIZE + M.SLOT_SPACING)
            local slotY = self.y
            local item = beltItems[i]

            -- Slot background
            local isHovered = (self.hoveredSlot == i)
            if item and isHovered then
                love.graphics.setColor(0.4, 0.4, 0.5, 0.9)
            elseif item then
                love.graphics.setColor(0.25, 0.25, 0.3, 0.9)
            else
                love.graphics.setColor(0.15, 0.15, 0.18, 0.7)
            end
            love.graphics.rectangle("fill", slotX, slotY, M.SLOT_SIZE, M.SLOT_SIZE, 4, 4)

            -- Slot border
            if isHovered and item then
                love.graphics.setColor(1, 0.9, 0.4, 1)
                love.graphics.setLineWidth(2)
            else
                love.graphics.setColor(0.5, 0.5, 0.55, 0.8)
                love.graphics.setLineWidth(1)
            end
            love.graphics.rectangle("line", slotX, slotY, M.SLOT_SIZE, M.SLOT_SIZE, 4, 4)
            love.graphics.setLineWidth(1)

            -- Slot number key (1-4)
            love.graphics.setColor(0.6, 0.6, 0.6, 0.7)
            love.graphics.print(tostring(i), slotX + 3, slotY + 2)

            -- Draw item if present
            if item then
                self:drawItemIcon(item, slotX, slotY, M.SLOT_SIZE)

                -- Show tooltip on hover
                if isHovered then
                    self:drawItemTooltip(item, slotX, slotY - 40)
                end
            end
        end

        -- Draw ammo display (if PC has ammo)
        if pc.ammo ~= nil then
            self:drawAmmoDisplay(pc)
        end
    end

    --- Draw an item icon in a slot
    function hotbar:drawItemIcon(item, x, y, size)
        -- Item icon background color based on type
        local iconColor = { 0.6, 0.6, 0.6 }

        if item.properties and item.properties.light_source then
            if isItemLit(item) then
                iconColor = { 1, 0.8, 0.3 }  -- Lit torch = orange/yellow
            else
                iconColor = { 0.7, 0.4, 0.2 }  -- Unlit torch = brown
            end
        elseif item.isRation or (item.name and item.name:lower():find("ration")) then
            iconColor = { 0.5, 0.7, 0.4 }  -- Ration = green
        elseif item.name and item.name:lower():find("potion") then
            iconColor = { 0.4, 0.5, 0.8 }  -- Potion = blue
        end

        -- Draw icon circle
        love.graphics.setColor(iconColor[1], iconColor[2], iconColor[3], 0.9)
        love.graphics.circle("fill", x + size/2, y + size/2, size/3)

        -- Draw item initial/symbol
        love.graphics.setColor(1, 1, 1, 1)
        local initial = string.sub(item.name, 1, 1):upper()
        love.graphics.print(initial, x + size/2 - 4, y + size/2 - 6)

        -- Draw quantity if stackable
        if item.stackable and item.quantity and item.quantity > 1 then
            love.graphics.setColor(1, 1, 1, 0.9)
            love.graphics.print("x" .. item.quantity, x + size - 20, y + size - 14)
        end

        -- Draw lit indicator
        if item.properties and isItemLit(item) then
            love.graphics.setColor(1, 0.9, 0.3, 0.8)
            love.graphics.circle("fill", x + size - 8, y + 8, 4)
        end
    end

    --- Draw item tooltip
    function hotbar:drawItemTooltip(item, x, y)
        local text = item.name
        if item.stackable and item.quantity then
            text = text .. " (x" .. item.quantity .. ")"
        end
        if item.properties and item.properties.flicker_count then
            text = text .. " [" .. item.properties.flicker_count .. " flickers]"
        end

        -- Tooltip background
        local textWidth = love.graphics.getFont():getWidth(text)
        love.graphics.setColor(0.1, 0.1, 0.12, 0.95)
        love.graphics.rectangle("fill", x - 4, y - 2, textWidth + 8, 20, 3, 3)

        -- Tooltip text
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(text, x, y)
    end

    --- Draw ammo counter
    function hotbar:drawAmmoDisplay(pc)
        local ammoX = self.x + M.MAX_SLOTS * (M.SLOT_SIZE + M.SLOT_SPACING) + 10
        local ammoY = self.y

        -- Ammo icon
        love.graphics.setColor(0.6, 0.5, 0.3, 0.9)
        love.graphics.rectangle("fill", ammoX, ammoY, 60, M.SLOT_SIZE, 4, 4)

        love.graphics.setColor(0.5, 0.5, 0.55, 0.8)
        love.graphics.rectangle("line", ammoX, ammoY, 60, M.SLOT_SIZE, 4, 4)

        -- Ammo count
        local ammoText = tostring(pc.ammo or 0)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("Ammo", ammoX + 8, ammoY + 4)

        -- Color based on ammo level
        if pc.ammo <= 0 then
            love.graphics.setColor(1, 0.3, 0.3, 1)  -- Red = empty
        elseif pc.ammo <= 3 then
            love.graphics.setColor(1, 0.8, 0.3, 1)  -- Yellow = low
        else
            love.graphics.setColor(0.3, 1, 0.3, 1)  -- Green = good
        end
        love.graphics.print(ammoText, ammoX + 25, ammoY + 22)
    end

    ----------------------------------------------------------------------------
    -- INPUT
    ----------------------------------------------------------------------------

    function hotbar:mousepressed(x, y, button)
        if not self.isVisible then return false end
        if button ~= 1 then return false end  -- Left click only

        -- Check if clicked on a slot
        if self.hoveredSlot then
            self:useItem(self.hoveredSlot)
            return true
        end

        return false
    end

    function hotbar:keypressed(key)
        if not self.isVisible then return false end

        -- Number keys 1-4 to use belt items
        local keyNum = tonumber(key)
        if keyNum and keyNum >= 1 and keyNum <= M.MAX_SLOTS then
            return self:useItem(keyNum)
        end

        -- Backtick (`) to cycle selected PC (Tab is reserved for character sheet)
        if key == "`" then
            -- Use global cycleActivePC if available, otherwise fallback to local
            if cycleActivePC then
                cycleActivePC()
            else
                self.selectedPC = (self.selectedPC % #self.guild) + 1
            end
            return true
        end

        return false
    end

    return hotbar
end

return M
