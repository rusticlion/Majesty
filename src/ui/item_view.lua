-- item_view.lua
-- Item Notch Visualization Component for Majesty
-- Ticket S5.2: Visual durability with scratches, cracks, and destruction FX
--
-- Renders items with:
-- - Base icon (placeholder rectangle for now)
-- - Notch scratches/cracks overlay
-- - Destroyed state (greyed out, crossed through)
-- - Armor pips for NPCs

local M = {}

--------------------------------------------------------------------------------
-- COLORS (Ink on Parchment palette)
--------------------------------------------------------------------------------
M.COLORS = {
    -- Base
    item_bg         = { 0.25, 0.22, 0.20, 1.0 },
    item_border     = { 0.40, 0.35, 0.30, 1.0 },

    -- Notch colors
    scratch_light   = { 0.55, 0.35, 0.30, 0.6 },   -- Light scratch
    scratch_medium  = { 0.50, 0.25, 0.20, 0.8 },   -- Medium scratch
    scratch_heavy   = { 0.45, 0.15, 0.10, 1.0 },   -- Deep gouge

    -- Destroyed
    destroyed_tint  = { 0.35, 0.35, 0.35, 0.7 },
    destroyed_x     = { 0.60, 0.20, 0.15, 0.9 },

    -- Armor pips
    armor_full      = { 0.50, 0.55, 0.60, 1.0 },   -- Steel grey
    armor_notched   = { 0.35, 0.25, 0.20, 0.8 },   -- Damaged
    armor_border    = { 0.30, 0.28, 0.25, 1.0 },

    -- Text
    text_light      = { 0.85, 0.80, 0.70, 1.0 },
    text_dark       = { 0.15, 0.12, 0.10, 1.0 },
}

--------------------------------------------------------------------------------
-- SCRATCH PATTERNS
-- Pre-defined scratch line patterns for each notch level
--------------------------------------------------------------------------------
M.SCRATCH_PATTERNS = {
    -- Notch 1: Single light scratch
    [1] = {
        { 0.2, 0.1, 0.8, 0.9, "light" },
    },
    -- Notch 2: Two crossing scratches
    [2] = {
        { 0.15, 0.15, 0.85, 0.85, "medium" },
        { 0.85, 0.2, 0.2, 0.8, "light" },
    },
    -- Notch 3+: Heavy damage, multiple gouges
    [3] = {
        { 0.1, 0.1, 0.9, 0.9, "heavy" },
        { 0.9, 0.15, 0.15, 0.85, "heavy" },
        { 0.3, 0.05, 0.7, 0.95, "medium" },
    },
}

--------------------------------------------------------------------------------
-- ITEM VIEW FUNCTIONS
--------------------------------------------------------------------------------

--- Draw an item icon with notch visualization
-- @param item table: Item with { name, notches, durability, destroyed }
-- @param x, y number: Position
-- @param size number: Icon size (square)
-- @param options table: { showName, showDurability }
function M.drawItem(item, x, y, size, options)
    if not love or not item then return end

    options = options or {}
    local colors = M.COLORS

    -- Base icon background
    if item.destroyed then
        love.graphics.setColor(colors.destroyed_tint)
    else
        love.graphics.setColor(colors.item_bg)
    end
    love.graphics.rectangle("fill", x, y, size, size, 3, 3)

    -- Border
    love.graphics.setColor(colors.item_border)
    love.graphics.rectangle("line", x, y, size, size, 3, 3)

    -- Draw notch scratches
    if item.notches and item.notches > 0 then
        M.drawNotchScratches(x, y, size, item.notches)
    end

    -- Destroyed overlay
    if item.destroyed then
        M.drawDestroyedOverlay(x, y, size)
    end

    -- Item name (if requested)
    if options.showName then
        love.graphics.setColor(colors.text_light)
        local nameY = y + size + 2
        love.graphics.printf(
            item.name or "???",
            x - 10,
            nameY,
            size + 20,
            "center"
        )
    end

    -- Durability pips (if requested)
    if options.showDurability and item.durability then
        M.drawDurabilityPips(x, y + size + 2, size, item.durability, item.notches or 0)
    end
end

--- Draw notch scratches on an item
-- @param x, y number: Item position
-- @param size number: Item size
-- @param notches number: Number of notches taken
function M.drawNotchScratches(x, y, size, notches)
    local colors = M.COLORS

    -- Get pattern for this notch level (max at 3)
    local patternLevel = math.min(notches, 3)
    local pattern = M.SCRATCH_PATTERNS[patternLevel]

    if not pattern then return end

    for _, scratch in ipairs(pattern) do
        local x1 = x + scratch[1] * size
        local y1 = y + scratch[2] * size
        local x2 = x + scratch[3] * size
        local y2 = y + scratch[4] * size
        local severity = scratch[5]

        -- Set color based on severity
        if severity == "heavy" then
            love.graphics.setColor(colors.scratch_heavy)
            love.graphics.setLineWidth(3)
        elseif severity == "medium" then
            love.graphics.setColor(colors.scratch_medium)
            love.graphics.setLineWidth(2)
        else
            love.graphics.setColor(colors.scratch_light)
            love.graphics.setLineWidth(1.5)
        end

        -- Draw the scratch line with slight jitter for hand-drawn feel
        local midX = (x1 + x2) / 2 + (math.random() - 0.5) * size * 0.1
        local midY = (y1 + y2) / 2 + (math.random() - 0.5) * size * 0.1

        love.graphics.line(x1, y1, midX, midY, x2, y2)
    end

    love.graphics.setLineWidth(1)
end

--- Draw destroyed overlay (heavy X through item)
function M.drawDestroyedOverlay(x, y, size)
    local colors = M.COLORS
    local padding = size * 0.1

    -- Heavy ink X through the item
    love.graphics.setColor(colors.destroyed_x)
    love.graphics.setLineWidth(4)

    -- Main X
    love.graphics.line(
        x + padding, y + padding,
        x + size - padding, y + size - padding
    )
    love.graphics.line(
        x + size - padding, y + padding,
        x + padding, y + size - padding
    )

    -- Additional "shattered" lines for emphasis
    love.graphics.setLineWidth(2)
    love.graphics.line(x + size/2, y + padding/2, x + size/2, y + size - padding/2)
    love.graphics.line(x + padding/2, y + size/2, x + size - padding/2, y + size/2)

    love.graphics.setLineWidth(1)
end

--- Draw durability pips below item
function M.drawDurabilityPips(x, y, width, durability, notches)
    local colors = M.COLORS
    local pipSize = 6
    local pipSpacing = pipSize + 3
    local totalWidth = durability * pipSpacing - 3
    local startX = x + (width - totalWidth) / 2

    for i = 1, durability do
        local pipX = startX + (i - 1) * pipSpacing

        if i <= notches then
            -- Notched pip (damaged)
            love.graphics.setColor(colors.armor_notched)
            love.graphics.rectangle("fill", pipX, y, pipSize, pipSize, 1, 1)
            -- X through notched
            love.graphics.setColor(colors.destroyed_x)
            love.graphics.line(pipX + 1, y + 1, pipX + pipSize - 1, y + pipSize - 1)
        else
            -- Full pip (intact)
            love.graphics.setColor(colors.armor_full)
            love.graphics.rectangle("fill", pipX, y, pipSize, pipSize, 1, 1)
        end

        -- Border
        love.graphics.setColor(colors.armor_border)
        love.graphics.rectangle("line", pipX, y, pipSize, pipSize, 1, 1)
    end
end

--------------------------------------------------------------------------------
-- ARMOR DISPLAY FOR NPCs
--------------------------------------------------------------------------------

--- Draw armor indicator for an NPC (shield icon with pips)
-- @param entity table: Entity with armorSlots and armorNotches
-- @param x, y number: Position
-- @param size number: Icon size
function M.drawNPCArmor(entity, x, y, size)
    if not love or not entity then return end
    if not entity.armorSlots or entity.armorSlots <= 0 then return end

    local colors = M.COLORS
    local slots = entity.armorSlots
    local notches = entity.armorNotches or 0

    -- Draw shield shape
    love.graphics.setColor(colors.armor_full)

    -- Shield outline (simplified heraldic shape)
    local points = {
        x + size * 0.5, y,                      -- Top center
        x + size, y + size * 0.3,               -- Top right
        x + size, y + size * 0.6,               -- Middle right
        x + size * 0.5, y + size,               -- Bottom point
        x, y + size * 0.6,                      -- Middle left
        x, y + size * 0.3,                      -- Top left
    }
    love.graphics.polygon("fill", points)

    -- Shield border
    love.graphics.setColor(colors.armor_border)
    love.graphics.setLineWidth(2)
    love.graphics.polygon("line", points)
    love.graphics.setLineWidth(1)

    -- Draw armor pips inside shield
    local pipSize = math.min(size * 0.15, 8)
    local pipY = y + size * 0.35
    local totalPipWidth = slots * (pipSize + 2) - 2
    local pipStartX = x + (size - totalPipWidth) / 2

    for i = 1, slots do
        local pipX = pipStartX + (i - 1) * (pipSize + 2)

        if i <= notches then
            -- Notched (damaged)
            love.graphics.setColor(colors.armor_notched)
            love.graphics.circle("fill", pipX + pipSize/2, pipY, pipSize/2)
            -- Crack line
            love.graphics.setColor(colors.destroyed_x)
            love.graphics.setLineWidth(1.5)
            love.graphics.line(pipX, pipY - pipSize/3, pipX + pipSize, pipY + pipSize/3)
            love.graphics.setLineWidth(1)
        else
            -- Intact
            love.graphics.setColor(colors.armor_full)
            love.graphics.circle("fill", pipX + pipSize/2, pipY, pipSize/2)
        end
    end

    -- Show if fully damaged
    if notches >= slots then
        -- Broken shield indicator
        love.graphics.setColor(colors.destroyed_x)
        love.graphics.setLineWidth(3)
        love.graphics.line(x + size * 0.2, y + size * 0.2, x + size * 0.8, y + size * 0.8)
        love.graphics.setLineWidth(1)
    end
end

--------------------------------------------------------------------------------
-- INVENTORY TRAY RENDERING
--------------------------------------------------------------------------------

--- Draw an inventory location (hands, belt, or pack)
-- @param inventory table: Inventory instance
-- @param location string: "hands", "belt", or "pack"
-- @param x, y number: Position
-- @param config table: { itemSize, columns, padding }
function M.drawInventoryTray(inventory, location, x, y, config)
    if not love or not inventory then return end

    config = config or {}
    local itemSize = config.itemSize or 40
    local columns = config.columns or 4
    local padding = config.padding or 4

    local items = inventory:getItems(location)

    -- Draw slot backgrounds
    local limit = inventory.limits[location] or 4
    for i = 0, limit - 1 do
        local col = i % columns
        local row = math.floor(i / columns)
        local slotX = x + col * (itemSize + padding)
        local slotY = y + row * (itemSize + padding)

        -- Empty slot background
        love.graphics.setColor(0.15, 0.12, 0.10, 0.5)
        love.graphics.rectangle("fill", slotX, slotY, itemSize, itemSize, 2, 2)
        love.graphics.setColor(0.30, 0.25, 0.20, 0.5)
        love.graphics.rectangle("line", slotX, slotY, itemSize, itemSize, 2, 2)
    end

    -- Draw items
    for i, item in ipairs(items) do
        local col = (i - 1) % columns
        local row = math.floor((i - 1) / columns)
        local itemX = x + col * (itemSize + padding)
        local itemY = y + row * (itemSize + padding)

        M.drawItem(item, itemX, itemY, itemSize, { showDurability = true })
    end
end

return M
