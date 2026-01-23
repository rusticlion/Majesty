-- inventory.lua
-- Slot-Based Inventory Manager for Majesty
-- Ticket T1_7: Belt vs Pack system with notch tracking
--
-- Locations: HANDS (active), BELT (quick access), PACK (stored)
-- Items have unique instance IDs - two torches are separate objects

local M = {}

--------------------------------------------------------------------------------
-- SLOT CONSTANTS
--------------------------------------------------------------------------------
M.SLOTS = {
    HANDS = 2,
    BELT  = 4,
    PACK  = 21,
}

M.LOCATIONS = {
    HANDS = "hands",
    BELT  = "belt",
    PACK  = "pack",
}

--------------------------------------------------------------------------------
-- ITEM SIZE CONSTANTS
--------------------------------------------------------------------------------
M.SIZE = {
    NORMAL    = 1,  -- Most items, one-handed
    LARGE     = 2,  -- Two-handed items
    OVERSIZED = 2,  -- 2 slots AND belt-only
}

--------------------------------------------------------------------------------
-- DURABILITY CONSTANTS
--------------------------------------------------------------------------------
M.DURABILITY = {
    FRAGILE        = 1,  -- Breaks after 1 notch
    NORMAL         = 2,  -- Breaks after 2 notches
    TEMPERED_STEEL = 3,  -- Breaks after 3 notches
}

--------------------------------------------------------------------------------
-- ITEM FACTORY
-- Every item gets a unique instance ID
--------------------------------------------------------------------------------
local nextItemId = 0

--- Create a new Item instance
-- @param config table: { name, size, durability, stackable, stackSize, oversized, ... }
-- @return Item instance with unique ID
function M.createItem(config)
    config = config or {}

    nextItemId = nextItemId + 1

    local item = {
        -- Identity
        id   = config.id or ("item_" .. nextItemId),
        name = config.name or "Unknown Item",

        -- Size (slots consumed)
        size      = config.size or M.SIZE.NORMAL,
        oversized = config.oversized or false,  -- If true, belt-only

        -- Durability
        durability = config.durability or M.DURABILITY.NORMAL,
        notches    = 0,
        destroyed  = false,

        -- Stacking (for arrows, coins, etc.)
        stackable = config.stackable or false,
        stackSize = config.stackSize or 1,  -- Max per slot
        quantity  = config.quantity or 1,

        -- Armor flag (worn armor uses belt slots)
        isArmor = config.isArmor or false,

        -- S11.3: Key properties for locks
        keyId = config.keyId or nil,  -- What locks this key opens

        -- Template reference
        templateId = config.templateId or nil,

        -- Custom properties
        properties = config.properties or {},
    }

    return item
end

--- S11.3: Create an item from a template ID
-- @param templateId string: The template ID from item_templates.lua
-- @param overrides table: Optional property overrides
-- @return Item instance or nil if template not found
function M.createItemFromTemplate(templateId, overrides)
    -- Lazy-load templates to avoid circular dependency
    local item_templates = require('data.item_templates')

    local template = item_templates.getTemplate(templateId)
    if not template then
        print("[INVENTORY] Unknown template: " .. tostring(templateId))
        return nil
    end

    -- Merge template with overrides
    local config = {}
    for k, v in pairs(template) do
        config[k] = v
    end
    if overrides then
        for k, v in pairs(overrides) do
            config[k] = v
        end
    end

    -- Store the template ID for reference
    config.templateId = templateId

    return M.createItem(config)
end

--- Add a notch to an item
-- @return string: "notched", "destroyed", or "already_destroyed"
function M.addNotch(item)
    if item.destroyed then
        return "already_destroyed"
    end

    item.notches = item.notches + 1

    if item.notches >= item.durability then
        item.destroyed = true
        return "destroyed"
    end

    return "notched"
end

--- Repair an item (remove one notch)
function M.repairNotch(item)
    if item.notches > 0 then
        item.notches = item.notches - 1
        if item.destroyed and item.notches < item.durability then
            item.destroyed = false
        end
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- INVENTORY CONTAINER
-- Manages hands, belt, and pack for an entity
--------------------------------------------------------------------------------

--- Create a new Inventory for an entity
-- @param config table: { beltSlots, packSlots } - optional overrides
-- @return Inventory instance
function M.createInventory(config)
    config = config or {}

    local inventory = {
        -- Slot limits (can be customized for special cases)
        limits = {
            hands = M.SLOTS.HANDS,
            belt  = config.beltSlots or M.SLOTS.BELT,
            pack  = config.packSlots or M.SLOTS.PACK,
        },

        -- Item storage by location
        hands = {},  -- Active/held items
        belt  = {},  -- Quick-access items (and worn armor)
        pack  = {},  -- Stored items
    }

    ----------------------------------------------------------------------------
    -- SLOT COUNTING
    ----------------------------------------------------------------------------

    --- Count slots used in a location
    local function countUsedSlots(location)
        local items = inventory[location]
        local used = 0
        for _, item in ipairs(items) do
            if item.stackable then
                used = used + 1  -- Stacked items use 1 slot regardless of quantity
            else
                used = used + item.size
            end
        end
        return used
    end

    --- Get available slots in a location
    function inventory:availableSlots(location)
        return self.limits[location] - countUsedSlots(location)
    end

    --- Get used slots in a location
    function inventory:usedSlots(location)
        return countUsedSlots(location)
    end

    ----------------------------------------------------------------------------
    -- ADD ITEM
    ----------------------------------------------------------------------------

    --- Add an item to a location
    -- @param item table: Item instance
    -- @param location string: "hands", "belt", or "pack"
    -- @return boolean, string: success, error_reason
    function inventory:addItem(item, location)
        location = location or M.LOCATIONS.PACK

        -- Validate location
        if not self[location] then
            return false, "invalid_location"
        end

        -- Oversized items can ONLY go on belt
        if item.oversized and location ~= M.LOCATIONS.BELT then
            return false, "oversized_belt_only"
        end

        -- Worn armor can ONLY go on belt (p. 37: "carried in your belt slots")
        -- Armor in pack would be "loot" and should not have isArmor=true
        if item.isArmor and location ~= M.LOCATIONS.BELT then
            return false, "armor_belt_only"
        end

        -- Check slot availability
        local slotsNeeded = item.stackable and 1 or item.size
        if self:availableSlots(location) < slotsNeeded then
            return false, "insufficient_slots"
        end

        -- Handle stacking
        if item.stackable then
            -- Look for existing stack of same item type
            for _, existing in ipairs(self[location]) do
                if existing.name == item.name and existing.quantity < existing.stackSize then
                    local canAdd = existing.stackSize - existing.quantity
                    local toAdd = math.min(canAdd, item.quantity)
                    existing.quantity = existing.quantity + toAdd
                    item.quantity = item.quantity - toAdd
                    if item.quantity <= 0 then
                        return true, "stacked"
                    end
                end
            end
        end

        -- Add as new item
        self[location][#self[location] + 1] = item
        return true, "added"
    end

    ----------------------------------------------------------------------------
    -- REMOVE ITEM
    ----------------------------------------------------------------------------

    --- Remove an item by ID from any location
    -- @param itemId string: The item's unique ID
    -- @return item, location: The removed item and where it was, or nil
    function inventory:removeItem(itemId)
        for _, location in ipairs({ "hands", "belt", "pack" }) do
            for i, item in ipairs(self[location]) do
                if item.id == itemId then
                    table.remove(self[location], i)
                    return item, location
                end
            end
        end
        return nil, nil
    end

    ----------------------------------------------------------------------------
    -- FIND ITEM
    ----------------------------------------------------------------------------

    --- Find an item by ID
    -- @return item, location or nil, nil
    function inventory:findItem(itemId)
        for _, location in ipairs({ "hands", "belt", "pack" }) do
            for _, item in ipairs(self[location]) do
                if item.id == itemId then
                    return item, location
                end
            end
        end
        return nil, nil
    end

    --- Find items by name
    -- @return table of { item, location } pairs
    function inventory:findItemsByName(name)
        local results = {}
        for _, location in ipairs({ "hands", "belt", "pack" }) do
            for _, item in ipairs(self[location]) do
                if item.name == name then
                    results[#results + 1] = { item = item, location = location }
                end
            end
        end
        return results
    end

    --- Find first item matching a predicate function (S9.2)
    -- @param predicate function(item): returns true if item matches
    -- @return item, location or nil, nil
    function inventory:findItemByPredicate(predicate)
        for _, location in ipairs({ "hands", "belt", "pack" }) do
            for _, item in ipairs(self[location]) do
                if predicate(item) then
                    return item, location
                end
            end
        end
        return nil, nil
    end

    --- Check if inventory has an item of a specific type (S9.2)
    -- @param itemType string: Type to check for (e.g., "ration", "tinkers_kit")
    -- @return boolean
    function inventory:hasItemOfType(itemType)
        local item = self:findItemByPredicate(function(i)
            return i.type == itemType or
                   i.itemType == itemType or
                   (i.properties and i.properties.type == itemType)
        end)
        return item ~= nil
    end

    --- Count items matching a predicate (S9.2)
    -- @param predicate function(item): returns true if item matches
    -- @return number: Total count (respects stackable quantity)
    function inventory:countItemsByPredicate(predicate)
        local count = 0
        for _, location in ipairs({ "hands", "belt", "pack" }) do
            for _, item in ipairs(self[location]) do
                if predicate(item) then
                    count = count + (item.quantity or 1)
                end
            end
        end
        return count
    end

    --- Remove one unit of an item (handles stackables) (S9.2)
    -- @param itemId string: The item's unique ID
    -- @param amount number: Amount to remove (default 1)
    -- @return boolean, string: success, result
    function inventory:removeItemQuantity(itemId, amount)
        amount = amount or 1

        for _, location in ipairs({ "hands", "belt", "pack" }) do
            for i, item in ipairs(self[location]) do
                if item.id == itemId then
                    if item.stackable and item.quantity then
                        if item.quantity > amount then
                            item.quantity = item.quantity - amount
                            return true, "decremented"
                        else
                            -- Remove entire stack
                            table.remove(self[location], i)
                            return true, "removed"
                        end
                    else
                        -- Non-stackable, remove entirely
                        table.remove(self[location], i)
                        return true, "removed"
                    end
                end
            end
        end
        return false, "not_found"
    end

    ----------------------------------------------------------------------------
    -- SWAP / MOVE
    ----------------------------------------------------------------------------

    --- Move an item between locations
    -- @param itemId string: The item's unique ID
    -- @param toLoc string: Destination location
    -- @return boolean, string: success, reason
    function inventory:swap(itemId, toLoc)
        local item, fromLoc = self:findItem(itemId)

        if not item then
            return false, "item_not_found"
        end

        if fromLoc == toLoc then
            return true, "already_there"
        end

        -- Validate destination
        if not self[toLoc] then
            return false, "invalid_destination"
        end

        -- Oversized check
        if item.oversized and toLoc ~= M.LOCATIONS.BELT then
            return false, "oversized_belt_only"
        end

        -- Armor check (worn armor must stay on belt)
        if item.isArmor and toLoc ~= M.LOCATIONS.BELT then
            return false, "armor_belt_only"
        end

        -- Check destination has room
        local slotsNeeded = item.stackable and 1 or item.size
        if self:availableSlots(toLoc) < slotsNeeded then
            return false, "destination_full"
        end

        -- Perform the move
        self:removeItem(itemId)
        self[toLoc][#self[toLoc] + 1] = item

        return true, "moved"
    end

    ----------------------------------------------------------------------------
    -- HANDS UTILITIES
    ----------------------------------------------------------------------------

    --- Check if hands are free
    function inventory:handsFree()
        return self:availableSlots("hands")
    end

    --- Check if holding a specific item type
    function inventory:isHolding(itemName)
        for _, item in ipairs(self.hands) do
            if item.name == itemName then
                return true, item
            end
        end
        return false, nil
    end

    ----------------------------------------------------------------------------
    -- LIST ITEMS
    ----------------------------------------------------------------------------

    --- Get all items in a location
    function inventory:getItems(location)
        return self[location] or {}
    end

    --- Get all items across all locations
    function inventory:getAllItems()
        local all = {}
        for _, location in ipairs({ "hands", "belt", "pack" }) do
            for _, item in ipairs(self[location]) do
                all[#all + 1] = { item = item, location = location }
            end
        end
        return all
    end

    --- Get the currently wielded weapon from hands
    -- Returns the first weapon found in hands, or nil if none
    function inventory:getWieldedWeapon()
        for _, item in ipairs(self.hands) do
            if item.isWeapon then
                return item
            end
        end
        return nil
    end

    --- Check if entity has a ranged weapon in hands
    function inventory:hasRangedWeaponInHands()
        local weapon = self:getWieldedWeapon()
        return weapon and weapon.isRanged
    end

    --- Check if entity has a melee weapon in hands
    function inventory:hasMeleeWeaponInHands()
        local weapon = self:getWieldedWeapon()
        return weapon and (weapon.isMelee or (weapon.isWeapon and not weapon.isRanged))
    end

    return inventory
end

return M
