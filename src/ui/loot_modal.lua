-- loot_modal.lua
-- Loot Modal for Majesty
-- Ticket S11.3: UI for looting containers and corpses
--
-- Opens when clicking a searchable container POI.
-- Displays items inside and allows Take/Take All.

local events = require('logic.events')
local inventory = require('logic.inventory')

local M = {}

--------------------------------------------------------------------------------
-- LAYOUT CONSTANTS
--------------------------------------------------------------------------------

M.LAYOUT = {
    WIDTH = 350,
    HEIGHT = 400,
    PADDING = 15,
    SLOT_SIZE = 48,
    SLOT_SPACING = 6,
    BUTTON_HEIGHT = 35,
}

--------------------------------------------------------------------------------
-- COLORS
--------------------------------------------------------------------------------

M.COLORS = {
    overlay = { 0, 0, 0, 0.7 },
    panel_bg = { 0.15, 0.13, 0.12, 0.98 },
    panel_border = { 0.5, 0.4, 0.3, 1 },
    header_bg = { 0.2, 0.17, 0.15, 1 },
    text = { 0.9, 0.88, 0.82, 1 },
    text_dim = { 0.6, 0.58, 0.55, 1 },
    text_highlight = { 1, 0.9, 0.6, 1 },
    slot_empty = { 0.12, 0.12, 0.14, 1 },
    slot_filled = { 0.25, 0.22, 0.18, 1 },
    slot_hover = { 0.35, 0.3, 0.25, 1 },
    button = { 0.25, 0.22, 0.18, 1 },
    button_hover = { 0.35, 0.3, 0.25, 1 },
    button_text = { 0.9, 0.88, 0.82, 1 },
}

--------------------------------------------------------------------------------
-- LOOT MODAL FACTORY
--------------------------------------------------------------------------------

function M.createLootModal(config)
    config = config or {}

    local modal = {
        eventBus = config.eventBus or events.globalBus,
        roomManager = config.roomManager,

        -- State
        isOpen = false,
        containerPOI = nil,      -- The POI being looted
        containerRoomId = nil,   -- Room the container is in
        containerName = "",      -- Display name

        -- Instantiated loot items (created from template IDs)
        lootItems = {},

        -- Selected recipient PC
        recipientPC = nil,
        recipientPCIndex = 1,
        guild = config.guild or {},

        -- Layout
        x = 0,
        y = 0,

        -- Hover state
        hoveredSlot = nil,
        hoveredButton = nil,

        -- Tooltip
        tooltip = nil,
    }

    ----------------------------------------------------------------------------
    -- OPEN/CLOSE
    ----------------------------------------------------------------------------

    --- Open the loot modal for a container POI
    -- @param poi table: The POI data
    -- @param roomId string: The room ID
    function modal:open(poi, roomId)
        if not poi then return end

        self.isOpen = true
        self.containerPOI = poi
        self.containerRoomId = roomId
        self.containerName = poi.name or "Container"

        -- Set default recipient
        if #self.guild > 0 then
            self.recipientPC = self.guild[self.recipientPCIndex]
        end

        -- Instantiate loot items from the POI's loot array
        self:instantiateLoot()

        -- Center the modal
        if love then
            local screenW, screenH = love.graphics.getDimensions()
            self.x = (screenW - M.LAYOUT.WIDTH) / 2
            self.y = (screenH - M.LAYOUT.HEIGHT) / 2
        end

        self.eventBus:emit("loot_modal_opened", { poi = poi, roomId = roomId })
    end

    function modal:close()
        -- Any items not taken remain in the container
        -- (Already handled by room state updates)
        self.isOpen = false
        self.containerPOI = nil
        self.containerRoomId = nil
        self.lootItems = {}
        self.hoveredSlot = nil
        self.hoveredButton = nil
        self.tooltip = nil

        self.eventBus:emit("loot_modal_closed", {})
    end

    ----------------------------------------------------------------------------
    -- LOOT INSTANTIATION
    ----------------------------------------------------------------------------

    --- Instantiate loot items from template IDs
    function modal:instantiateLoot()
        self.lootItems = {}

        if not self.containerPOI then return end

        -- Check for loot array in POI
        local lootIds = self.containerPOI.loot or {}

        -- Also check for secrets loot (if container was searched)
        if self.containerPOI.state == "searched" and self.containerPOI.secrets_loot then
            for _, lootId in ipairs(self.containerPOI.secrets_loot) do
                lootIds[#lootIds + 1] = lootId
            end
        end

        -- Instantiate each item
        for _, lootId in ipairs(lootIds) do
            local item = nil

            -- If it's a string, treat as template ID
            if type(lootId) == "string" then
                item = inventory.createItemFromTemplate(lootId)
            elseif type(lootId) == "table" then
                -- If it's a table, use it directly as config
                item = inventory.createItem(lootId)
            end

            if item then
                self.lootItems[#self.lootItems + 1] = item
            end
        end
    end

    ----------------------------------------------------------------------------
    -- TAKE ITEMS
    ----------------------------------------------------------------------------

    --- Take a single item from the loot
    -- @param index number: Index in lootItems
    function modal:takeItem(index)
        local item = self.lootItems[index]
        if not item then return false end
        if not self.recipientPC or not self.recipientPC.inventory then return false end

        -- Try to add to recipient's inventory (prefer pack)
        local success, reason = self.recipientPC.inventory:addItem(item, inventory.LOCATIONS.PACK)

        if success then
            -- Remove from loot
            table.remove(self.lootItems, index)

            -- Update POI state
            self:updateContainerLoot()

            print("[LOOT] " .. self.recipientPC.name .. " took " .. item.name)
            self.eventBus:emit("item_looted", {
                item = item,
                recipient = self.recipientPC,
                poi = self.containerPOI,
            })

            -- Close if empty
            if #self.lootItems == 0 then
                self:markContainerEmpty()
            end

            return true
        else
            print("[LOOT] Cannot take " .. item.name .. ": " .. (reason or "unknown"))
            return false
        end
    end

    --- Take all items from the loot
    function modal:takeAll()
        -- Take items in reverse order to avoid index issues
        for i = #self.lootItems, 1, -1 do
            self:takeItem(i)
        end
    end

    --- Update the container's loot array to reflect remaining items
    function modal:updateContainerLoot()
        if not self.containerPOI then return end

        -- Update the POI's loot to only contain remaining items
        -- Store as inline configs (not template IDs) since they're now instantiated
        local remainingLoot = {}
        for _, item in ipairs(self.lootItems) do
            -- Convert item back to a config for storage
            remainingLoot[#remainingLoot + 1] = {
                name = item.name,
                size = item.size,
                durability = item.durability,
                stackable = item.stackable,
                stackSize = item.stackSize,
                quantity = item.quantity,
                properties = item.properties,
                templateId = item.templateId,
                keyId = item.keyId,
            }
        end

        self.containerPOI.loot = remainingLoot

        -- Update room manager state
        if self.roomManager then
            self.roomManager:updateFeatureState(
                self.containerRoomId,
                self.containerPOI.id,
                { loot = remainingLoot }
            )
        end
    end

    --- Mark container as empty
    function modal:markContainerEmpty()
        if not self.containerPOI then return end

        self.containerPOI.state = "empty"
        self.containerPOI.loot = {}

        -- Update room manager
        if self.roomManager then
            self.roomManager:updateFeatureState(
                self.containerRoomId,
                self.containerPOI.id,
                { state = "empty", loot = {} }
            )
        end

        self.eventBus:emit("container_emptied", {
            poi = self.containerPOI,
            roomId = self.containerRoomId,
        })
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function modal:update(dt)
        -- No animations needed for now
    end

    ----------------------------------------------------------------------------
    -- DRAW
    ----------------------------------------------------------------------------

    function modal:draw()
        if not self.isOpen or not love then return end

        -- Dark overlay
        love.graphics.setColor(M.COLORS.overlay)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())

        -- Main panel
        love.graphics.setColor(M.COLORS.panel_bg)
        love.graphics.rectangle("fill", self.x, self.y, M.LAYOUT.WIDTH, M.LAYOUT.HEIGHT, 8, 8)

        love.graphics.setColor(M.COLORS.panel_border)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", self.x, self.y, M.LAYOUT.WIDTH, M.LAYOUT.HEIGHT, 8, 8)
        love.graphics.setLineWidth(1)

        -- Header
        love.graphics.setColor(M.COLORS.header_bg)
        love.graphics.rectangle("fill", self.x, self.y, M.LAYOUT.WIDTH, 40, 8, 0)

        love.graphics.setColor(M.COLORS.text_highlight)
        love.graphics.print(self.containerName, self.x + M.LAYOUT.PADDING, self.y + 12)

        -- Close button
        love.graphics.setColor(M.COLORS.text_dim)
        love.graphics.print("[X]", self.x + M.LAYOUT.WIDTH - 35, self.y + 12)

        -- Recipient selector
        local recipientY = self.y + 50
        love.graphics.setColor(M.COLORS.text)
        love.graphics.print("Take to:", self.x + M.LAYOUT.PADDING, recipientY)

        -- PC tabs
        local tabX = self.x + 80
        for i, pc in ipairs(self.guild) do
            local isSelected = (i == self.recipientPCIndex)
            local tabW = 55

            if isSelected then
                love.graphics.setColor(0.3, 0.25, 0.2, 1)
            else
                love.graphics.setColor(0.18, 0.16, 0.14, 1)
            end
            love.graphics.rectangle("fill", tabX + (i-1) * (tabW + 4), recipientY - 2, tabW, 22, 3, 3)

            love.graphics.setColor(isSelected and M.COLORS.text_highlight or M.COLORS.text_dim)
            local shortName = string.sub(pc.name, 1, 6)
            love.graphics.print(shortName, tabX + (i-1) * (tabW + 4) + 4, recipientY)
        end

        -- Loot grid
        local gridY = recipientY + 35
        love.graphics.setColor(M.COLORS.text)
        love.graphics.print("Contents:", self.x + M.LAYOUT.PADDING, gridY)
        gridY = gridY + 22

        local slotSize = M.LAYOUT.SLOT_SIZE
        local spacing = M.LAYOUT.SLOT_SPACING
        local cols = 5
        local maxSlots = 15

        for i = 1, maxSlots do
            local row = math.floor((i - 1) / cols)
            local col = (i - 1) % cols
            local slotX = self.x + M.LAYOUT.PADDING + col * (slotSize + spacing)
            local slotY = gridY + row * (slotSize + spacing)

            local item = self.lootItems[i]
            local isHovered = (self.hoveredSlot == i)

            -- Slot background
            if item then
                love.graphics.setColor(isHovered and M.COLORS.slot_hover or M.COLORS.slot_filled)
            else
                love.graphics.setColor(M.COLORS.slot_empty)
            end
            love.graphics.rectangle("fill", slotX, slotY, slotSize, slotSize, 4, 4)

            -- Slot border
            if isHovered and item then
                love.graphics.setColor(M.COLORS.text_highlight)
                love.graphics.setLineWidth(2)
            else
                love.graphics.setColor(0.4, 0.4, 0.4, 0.5)
                love.graphics.setLineWidth(1)
            end
            love.graphics.rectangle("line", slotX, slotY, slotSize, slotSize, 4, 4)
            love.graphics.setLineWidth(1)

            -- Item display
            if item then
                love.graphics.setColor(M.COLORS.text)
                local initial = string.sub(item.name or "?", 1, 2)
                love.graphics.print(initial, slotX + 4, slotY + 4)

                if item.stackable and item.quantity and item.quantity > 1 then
                    love.graphics.setColor(M.COLORS.text_dim)
                    love.graphics.print("x" .. item.quantity, slotX + slotSize - 22, slotY + slotSize - 14)
                end
            end
        end

        -- Buttons
        local buttonY = self.y + M.LAYOUT.HEIGHT - M.LAYOUT.BUTTON_HEIGHT - M.LAYOUT.PADDING
        local buttonW = (M.LAYOUT.WIDTH - M.LAYOUT.PADDING * 3) / 2

        -- Take All button
        local takeAllHovered = (self.hoveredButton == "take_all")
        love.graphics.setColor(takeAllHovered and M.COLORS.button_hover or M.COLORS.button)
        love.graphics.rectangle("fill", self.x + M.LAYOUT.PADDING, buttonY, buttonW, M.LAYOUT.BUTTON_HEIGHT, 4, 4)
        love.graphics.setColor(M.COLORS.button_text)
        love.graphics.print("Take All", self.x + M.LAYOUT.PADDING + 25, buttonY + 10)

        -- Close button
        local closeHovered = (self.hoveredButton == "close")
        love.graphics.setColor(closeHovered and M.COLORS.button_hover or M.COLORS.button)
        love.graphics.rectangle("fill", self.x + M.LAYOUT.PADDING * 2 + buttonW, buttonY, buttonW, M.LAYOUT.BUTTON_HEIGHT, 4, 4)
        love.graphics.setColor(M.COLORS.button_text)
        love.graphics.print("Close", self.x + M.LAYOUT.PADDING * 2 + buttonW + 35, buttonY + 10)

        -- Empty message
        if #self.lootItems == 0 then
            love.graphics.setColor(M.COLORS.text_dim)
            love.graphics.print("Empty", self.x + M.LAYOUT.WIDTH/2 - 20, gridY + 50)
        end

        -- Tooltip
        self:drawTooltip()
    end

    function modal:drawTooltip()
        if not self.tooltip then return end

        local mouseX, mouseY = love.mouse.getPosition()
        local padding = 6
        local font = love.graphics.getFont()
        local textWidth = font:getWidth(self.tooltip)
        local textHeight = font:getHeight()

        local tipX = mouseX + 12
        local tipY = mouseY + 8
        local tipW = textWidth + padding * 2
        local tipH = textHeight + padding * 2

        -- Keep on screen
        local screenW, screenH = love.graphics.getDimensions()
        if tipX + tipW > screenW then tipX = mouseX - tipW - 5 end
        if tipY + tipH > screenH then tipY = mouseY - tipH - 5 end

        love.graphics.setColor(0.1, 0.1, 0.12, 0.95)
        love.graphics.rectangle("fill", tipX, tipY, tipW, tipH, 3, 3)

        love.graphics.setColor(M.COLORS.text)
        love.graphics.print(self.tooltip, tipX + padding, tipY + padding)
    end

    ----------------------------------------------------------------------------
    -- INPUT
    ----------------------------------------------------------------------------

    function modal:keypressed(key)
        if not self.isOpen then return false end

        if key == "escape" then
            self:close()
            return true
        end

        -- Number keys to switch recipient
        local keyNum = tonumber(key)
        if keyNum and keyNum >= 1 and keyNum <= #self.guild then
            self.recipientPCIndex = keyNum
            self.recipientPC = self.guild[keyNum]
            return true
        end

        return true
    end

    function modal:mousepressed(x, y, button)
        if not self.isOpen then return false end

        -- Check if clicking outside to close
        if x < self.x or x > self.x + M.LAYOUT.WIDTH or
           y < self.y or y > self.y + M.LAYOUT.HEIGHT then
            self:close()
            return true
        end

        -- Close X button
        if x >= self.x + M.LAYOUT.WIDTH - 40 and x < self.x + M.LAYOUT.WIDTH and
           y >= self.y and y < self.y + 40 then
            self:close()
            return true
        end

        -- PC tabs
        local recipientY = self.y + 50
        local tabX = self.x + 80
        for i = 1, #self.guild do
            local tabW = 55
            local tx = tabX + (i-1) * (tabW + 4)
            if x >= tx and x < tx + tabW and y >= recipientY - 2 and y < recipientY + 20 then
                self.recipientPCIndex = i
                self.recipientPC = self.guild[i]
                return true
            end
        end

        -- Loot slots (click to take)
        if self.hoveredSlot and self.lootItems[self.hoveredSlot] then
            self:takeItem(self.hoveredSlot)
            return true
        end

        -- Buttons
        local buttonY = self.y + M.LAYOUT.HEIGHT - M.LAYOUT.BUTTON_HEIGHT - M.LAYOUT.PADDING
        local buttonW = (M.LAYOUT.WIDTH - M.LAYOUT.PADDING * 3) / 2

        if y >= buttonY and y < buttonY + M.LAYOUT.BUTTON_HEIGHT then
            if x >= self.x + M.LAYOUT.PADDING and x < self.x + M.LAYOUT.PADDING + buttonW then
                self:takeAll()
                self:close()
                return true
            elseif x >= self.x + M.LAYOUT.PADDING * 2 + buttonW and x < self.x + M.LAYOUT.WIDTH - M.LAYOUT.PADDING then
                self:close()
                return true
            end
        end

        return true
    end

    function modal:mousemoved(x, y, dx, dy)
        if not self.isOpen then return false end

        self.hoveredSlot = nil
        self.hoveredButton = nil
        self.tooltip = nil

        -- Check loot slots
        local gridY = self.y + 50 + 35 + 22
        local slotSize = M.LAYOUT.SLOT_SIZE
        local spacing = M.LAYOUT.SLOT_SPACING
        local cols = 5

        for i = 1, #self.lootItems do
            local row = math.floor((i - 1) / cols)
            local col = (i - 1) % cols
            local slotX = self.x + M.LAYOUT.PADDING + col * (slotSize + spacing)
            local slotY = gridY + row * (slotSize + spacing)

            if x >= slotX and x < slotX + slotSize and
               y >= slotY and y < slotY + slotSize then
                self.hoveredSlot = i
                local item = self.lootItems[i]
                if item then
                    self.tooltip = item.name
                end
                return true
            end
        end

        -- Check buttons
        local buttonY = self.y + M.LAYOUT.HEIGHT - M.LAYOUT.BUTTON_HEIGHT - M.LAYOUT.PADDING
        local buttonW = (M.LAYOUT.WIDTH - M.LAYOUT.PADDING * 3) / 2

        if y >= buttonY and y < buttonY + M.LAYOUT.BUTTON_HEIGHT then
            if x >= self.x + M.LAYOUT.PADDING and x < self.x + M.LAYOUT.PADDING + buttonW then
                self.hoveredButton = "take_all"
            elseif x >= self.x + M.LAYOUT.PADDING * 2 + buttonW and x < self.x + M.LAYOUT.WIDTH - M.LAYOUT.PADDING then
                self.hoveredButton = "close"
            end
        end

        return true
    end

    return modal
end

return M
