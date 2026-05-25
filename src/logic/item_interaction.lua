-- item_interaction.lua
-- Item-Based Interaction for Majesty
-- Ticket T2_10: Allow items to bypass or aid in interactions (p. 16)
--
-- Design: Items can be used to probe POIs instead of adventurers.
-- On failure, items take notches instead of adventurers taking wounds.
-- This enables "orthogonal problem solving" - creative item use.
--
-- Example: Investigating a "Pit" with a "10-foot Pole" skips wound logic
-- and instead notches the pole.

local events = require('logic.events')
local inventory = require('logic.inventory')

local M = {}

--------------------------------------------------------------------------------
-- ITEM INTERACTION TYPES
-- What an item can do when used on a POI
--------------------------------------------------------------------------------
M.INTERACTION_TYPES = {
    PROBE    = "probe",     -- Test for traps/hazards (pole, stick)
    UNLOCK   = "unlock",    -- Open locks (key, lockpick)
    TRIGGER  = "trigger",   -- Activate from distance (thrown rock)
    LIGHT    = "light",     -- Illuminate (torch, lantern)
    PROTECT  = "protect",   -- Shield from effect (shield, umbrella)
    BREAK    = "break",     -- Destroy obstacle (hammer, axe)
    RETRIEVE = "retrieve",  -- Grab distant items (hook, rope)
    WEDGE    = "wedge",     -- Wedge a door or gate closed (iron spikes)
    PITON    = "piton",     -- Set climbing pitons/anchors (iron spikes)
}

--------------------------------------------------------------------------------
-- ITEM PROPERTY TAGS
-- Tags that enable special interactions
--------------------------------------------------------------------------------
M.ITEM_TAGS = {
    REACH      = "reach",       -- Can probe from distance (poles, spears)
    KEY        = "key",         -- Can unlock specific locks
    LIGHT_SOURCE = "light_source", -- Provides illumination
    TOOL       = "tool",        -- General-purpose tool
    PROBE      = "probe",       -- Can safely probe hazards
    HEAVY      = "heavy",       -- Can trigger pressure plates
    SHARP      = "sharp",       -- Can cut things
    FRAGILE    = "fragile",     -- Extra vulnerable to notching
}

--------------------------------------------------------------------------------
-- ITEM INTERACTION DEFINITIONS
-- Maps item properties to what they can do with POIs
--------------------------------------------------------------------------------

-- Which items can do which interaction types
local itemCapabilities = {
    ["10-foot Pole"]  = { M.INTERACTION_TYPES.PROBE, M.INTERACTION_TYPES.TRIGGER },
    ["Rope"]          = { M.INTERACTION_TYPES.RETRIEVE },
    ["Grappling Hook"] = { M.INTERACTION_TYPES.RETRIEVE, M.INTERACTION_TYPES.TRIGGER },
    ["Lockpick"]      = { M.INTERACTION_TYPES.UNLOCK },
    ["Crowbar"]       = { M.INTERACTION_TYPES.BREAK, M.INTERACTION_TYPES.PROBE },
    ["Hammer"]        = { M.INTERACTION_TYPES.BREAK, M.INTERACTION_TYPES.TRIGGER },
    ["Torch"]         = { M.INTERACTION_TYPES.LIGHT },
    ["Lantern"]       = { M.INTERACTION_TYPES.LIGHT },
    ["Shield"]        = { M.INTERACTION_TYPES.PROTECT },
    ["Iron Spikes"]   = { M.INTERACTION_TYPES.WEDGE, M.INTERACTION_TYPES.PITON, M.INTERACTION_TYPES.TRIGGER },
    ["Flint and Tinder"] = { M.INTERACTION_TYPES.LIGHT },
}

-- Generic capabilities based on item tags
local tagCapabilities = {
    [M.ITEM_TAGS.REACH]   = { M.INTERACTION_TYPES.PROBE, M.INTERACTION_TYPES.TRIGGER },
    [M.ITEM_TAGS.PROBE]   = { M.INTERACTION_TYPES.PROBE },
    [M.ITEM_TAGS.KEY]     = { M.INTERACTION_TYPES.UNLOCK },
    [M.ITEM_TAGS.TOOL]    = { M.INTERACTION_TYPES.PROBE, M.INTERACTION_TYPES.BREAK },
    [M.ITEM_TAGS.HEAVY]   = { M.INTERACTION_TYPES.TRIGGER },
    [M.ITEM_TAGS.LIGHT_SOURCE] = { M.INTERACTION_TYPES.LIGHT },
}

local toolTypeCapabilities = {
    crowbar = { M.INTERACTION_TYPES.BREAK, M.INTERACTION_TYPES.PROBE },
    hammer = { M.INTERACTION_TYPES.BREAK, M.INTERACTION_TYPES.TRIGGER },
    hatchet = { M.INTERACTION_TYPES.BREAK },
    lockpick = { M.INTERACTION_TYPES.UNLOCK },
    grapple = { M.INTERACTION_TYPES.RETRIEVE, M.INTERACTION_TYPES.TRIGGER },
    pole = { M.INTERACTION_TYPES.PROBE, M.INTERACTION_TYPES.TRIGGER },
    spikes = { M.INTERACTION_TYPES.WEDGE, M.INTERACTION_TYPES.PITON, M.INTERACTION_TYPES.TRIGGER },
    firestarter = { M.INTERACTION_TYPES.LIGHT },
}

local function normalizeKey(value)
    if type(value) ~= "string" then
        return nil
    end
    local key = value:lower()
    key = key:gsub("^%s+", ""):gsub("%s+$", "")
    key = key:gsub("[%s%-']+", "_")
    return key
end

local function getItemToolType(item)
    local props = item and item.properties or {}
    return normalizeKey(props.toolType or item.toolType or item.type or item.templateId)
end

local function getContextInventory(context)
    if not context then
        return nil
    end
    return context.inventory or context.inv or
        (context.adventurer and context.adventurer.inventory) or
        (context.actor and context.actor.inventory) or
        (context.user and context.user.inventory)
end

local function isCrowbar(item)
    return normalizeKey(item and item.name) == "crowbar" or getItemToolType(item) == "crowbar"
end

local function isLockpick(item)
    local props = item and item.properties or {}
    return normalizeKey(item and item.name) == "lockpick" or normalizeKey(item and item.name) == "lockpicks" or
        getItemToolType(item) == "lockpick" or props.lockpick == true
end

local function getItemKeyId(item)
    local props = item and item.properties or {}
    return item and (item.keyId or item.key_id or props.keyId or props.key_id)
end

local function getLockKeyId(lock)
    return lock and (lock.keyId or lock.key_id)
end

local function isLockedDoorOrChest(poi)
    if not poi then
        return false
    end

    local kind = normalizeKey(poi.type or poi.kind or poi.category)
    local name = normalizeKey(poi.name or poi.id) or ""
    local doorOrChest = kind == "door" or kind == "chest" or kind == "container" or
        name:find("door", 1, true) ~= nil or name:find("chest", 1, true) ~= nil
    local activeLock = (poi.lock ~= nil and poi.lock.broken ~= true and poi.lock.disabled ~= true and
        poi.lock.locked ~= false) or poi.locked == true or poi.state == "locked"
    return doorOrChest and activeLock
end

local function hasActiveLock(poi)
    if not poi then
        return false
    end
    return (poi.lock ~= nil and poi.lock.broken ~= true and poi.lock.disabled ~= true and poi.lock.locked ~= false) or
        poi.locked == true or poi.state == "locked"
end

local function markFeatureUnlocked(poi)
    if not poi then
        return
    end
    poi.state = "unlocked"
    poi.locked = false
    if poi.lock then
        poi.lock.locked = false
        poi.lock.picked = true
    end
end

local function markFeatureBrokenOpen(poi)
    if not poi then
        return
    end
    poi.state = "broken"
    poi.broken = true
    poi.forcedOpen = true
    poi.priedOpen = true
    poi.locked = false
    if poi.lock then
        poi.lock.broken = true
        poi.lock.disabled = true
    end
end

local function isDoorLikePOI(poi)
    if not poi then
        return false
    end
    local props = poi.properties or {}
    local kind = normalizeKey(poi.type or poi.kind or poi.category)
    local name = normalizeKey(poi.name or poi.id) or ""
    return kind == "door" or kind == "gate" or kind == "portal" or props.door == true or
        props.gate == true or name:find("door", 1, true) ~= nil or name:find("gate", 1, true) ~= nil
end

local function isClimbSurfacePOI(poi)
    if not poi then
        return false
    end
    local props = poi.properties or {}
    local kind = normalizeKey(poi.type or poi.kind or poi.category)
    local name = normalizeKey(poi.name or poi.id) or ""
    return poi.climbable == true or poi.requiresClimb == true or poi.sheer == true or poi.vertical == true or
        props.climbable == true or props.requiresClimb == true or props.sheer == true or props.vertical == true or
        kind == "climb" or kind == "climbing" or kind == "wall" or kind == "surface" or
        name:find("cliff", 1, true) ~= nil or name:find("wall", 1, true) ~= nil or
        name:find("shaft", 1, true) ~= nil or name:find("pit", 1, true) ~= nil
end

local function isFireStartPOI(poi)
    if not poi then
        return false
    end
    local props = poi.properties or {}
    local kind = normalizeKey(poi.type or poi.kind or poi.category)
    local name = normalizeKey(poi.name or poi.id) or ""
    return kind == "light" or kind == "fire" or kind == "campfire" or kind == "brazier" or
        props.light_source == true or props.firewood == true or props.fire == true or props.campfire == true or
        props.flammable == true or name:find("fire", 1, true) ~= nil or name:find("brazier", 1, true) ~= nil
end

local function markFireStarted(poi)
    poi.properties = poi.properties or {}
    poi.state = "lit"
    poi.lit = true
    poi.isLit = true
    poi.fireStarted = true
    poi.properties.isLit = true
    poi.properties.lit = true
    poi.properties.extinguished = false
    poi.properties.fireStarted = true
    if poi.properties.firewood or normalizeKey(poi.type) == "campfire" then
        poi.campfire = true
        poi.properties.campfire = true
    end
end

local function spendOneItemUnit(item, context)
    local inv = getContextInventory(context)
    if inv and item and item.stackable and item.id and inv.removeItemQuantity then
        local ok, status = inv:removeItemQuantity(item.id, 1)
        if ok then
            if status == "removed" then
                item.quantity = 0
                item.destroyed = true
            end
            return true, status
        end
    end

    if item and item.stackable then
        local quantity = math.max(0, math.floor(tonumber(item.quantity) or 0))
        if quantity <= 0 then
            return false, "empty"
        end
        if quantity > 1 then
            item.quantity = quantity - 1
            return true, "decremented"
        end
        item.quantity = 0
        item.destroyed = true
        return true, "removed"
    end

    if item then
        item.destroyed = true
        return true, "removed"
    end

    return false, "missing_item"
end

local function markDoorWedged(poi, item)
    poi.properties = poi.properties or {}
    poi.state = "wedged"
    poi.wedgedClosed = true
    poi.spikedClosed = true
    poi.openBlocked = true
    poi.canOpen = false
    poi.spikesUsed = (poi.spikesUsed or 0) + 1
    poi.wedgedByItemId = item and item.id or nil
    poi.properties.wedgedClosed = true
    poi.properties.spikedClosed = true
    poi.properties.openBlocked = true
end

local function markPitonAnchor(poi, item)
    poi.properties = poi.properties or {}
    poi.pitonAnchors = (poi.pitonAnchors or 0) + 1
    poi.climbingAnchor = true
    poi.climbAssisted = true
    poi.properties.pitonAnchors = (poi.properties.pitonAnchors or 0) + 1
    poi.properties.climbingAnchor = true
    poi.properties.climbAssisted = true
    poi.properties.pitonItemId = item and item.id or nil
end

local function testSucceeded(testResult)
    if testResult == true then
        return true
    end
    if type(testResult) == "table" then
        return testResult.success == true
    end
    return false
end

local function breakOneLockpick(item, context)
    local inv = getContextInventory(context)
    if inv and item and item.stackable and item.id and inv.removeItemQuantity then
        local ok, status = inv:removeItemQuantity(item.id, 1)
        if ok then
            return true, status
        end
    end

    if item and item.stackable then
        local quantity = math.max(1, math.floor(tonumber(item.quantity) or 1))
        if quantity > 1 then
            item.quantity = quantity - 1
            return true, "decremented"
        end
        item.quantity = 0
        item.destroyed = true
        return true, "removed"
    end

    if item then
        local notchResult = inventory.addNotch(item)
        return notchResult ~= "already_destroyed", notchResult
    end

    return false, "missing_item"
end

--------------------------------------------------------------------------------
-- ITEM INTERACTION SYSTEM FACTORY
--------------------------------------------------------------------------------

--- Create a new ItemInteractionSystem
-- @param config table: { eventBus, roomManager }
-- @return ItemInteractionSystem instance
function M.createItemInteractionSystem(config)
    config = config or {}

    local system = {
        eventBus    = config.eventBus or events.globalBus,
        roomManager = config.roomManager,
    }

    ----------------------------------------------------------------------------
    -- CAPABILITY CHECKING
    ----------------------------------------------------------------------------

    --- Get all interaction types an item can perform
    -- @param item table: The item
    -- @return table: Array of interaction types
    function system:getItemCapabilities(item)
        local capabilities = {}
        local seen = {}

        -- Check by item name first
        if itemCapabilities[item.name] then
            for _, cap in ipairs(itemCapabilities[item.name]) do
                if not seen[cap] then
                    capabilities[#capabilities + 1] = cap
                    seen[cap] = true
                end
            end
        end

        -- Check by item tags
        if item.properties and item.properties.tags then
            for _, tag in ipairs(item.properties.tags) do
                if tagCapabilities[tag] then
                    for _, cap in ipairs(tagCapabilities[tag]) do
                        if not seen[cap] then
                            capabilities[#capabilities + 1] = cap
                            seen[cap] = true
                        end
                    end
                end
            end
        end

        local toolType = getItemToolType(item)
        if toolType and toolTypeCapabilities[toolType] then
            for _, cap in ipairs(toolTypeCapabilities[toolType]) do
                if not seen[cap] then
                    capabilities[#capabilities + 1] = cap
                    seen[cap] = true
                end
            end
        end

        if item and (item.isWeapon or item.weaponType) and not seen[M.INTERACTION_TYPES.BREAK] then
            capabilities[#capabilities + 1] = M.INTERACTION_TYPES.BREAK
            seen[M.INTERACTION_TYPES.BREAK] = true
        end

        local props = item and item.properties or {}
        if (getItemKeyId(item) or props.key == true) and not seen[M.INTERACTION_TYPES.UNLOCK] then
            capabilities[#capabilities + 1] = M.INTERACTION_TYPES.UNLOCK
            seen[M.INTERACTION_TYPES.UNLOCK] = true
        end

        return capabilities
    end

    --- Check if an item can perform a specific interaction type
    function system:canPerform(item, interactionType)
        local caps = self:getItemCapabilities(item)
        for _, cap in ipairs(caps) do
            if cap == interactionType then
                return true
            end
        end
        return false
    end

    --- Check if an item can be used on a POI
    -- @param item table: The item
    -- @param poi table: The POI/feature
    -- @return boolean, string: canUse, reason
    function system:canUseItemOnPOI(item, poi)
        -- Check if POI accepts items
        if poi.item_blocked then
            return false, "poi_rejects_items"
        end

        -- Check if item has any relevant capability
        local itemCaps = self:getItemCapabilities(item)
        if #itemCaps == 0 then
            return false, "item_has_no_capabilities"
        end

        -- Check for specific key requirements
        local lockKeyId = getLockKeyId(poi.lock)
        if lockKeyId then
            local itemKeyId = getItemKeyId(item)
            if itemKeyId == lockKeyId then
                return true, "key_matches"
            end
            if itemKeyId and not isLockpick(item) then
                return false, "key_mismatch"
            end
        end

        -- Check if item can probe hazards
        if poi.trap or poi.type == "hazard" then
            if self:canPerform(item, M.INTERACTION_TYPES.PROBE) then
                return true, "can_probe_hazard"
            end
        end

        if isDoorLikePOI(poi) and self:canPerform(item, M.INTERACTION_TYPES.WEDGE) then
            return true, "can_wedge_door"
        end

        if isClimbSurfacePOI(poi) and self:canPerform(item, M.INTERACTION_TYPES.PITON) then
            return true, "can_set_piton"
        end

        -- Generic capability match
        return true, "has_capabilities"
    end

    ----------------------------------------------------------------------------
    -- ITEM INTERACTION EXECUTION
    ----------------------------------------------------------------------------

    --- Use an item to interact with a POI
    -- @param item table: The item being used
    -- @param poi table: The POI/feature
    -- @param interactionType string: One of INTERACTION_TYPES
    -- @param context table: { roomId, adventurer, ... }
    -- @return table: { success, description, itemDamaged, itemDestroyed, poiStateChange }
    function system:useItemOnPOI(item, poi, interactionType, context)
        context = context or {}

        local result = {
            success = false,
            description = "",
            itemDamaged = false,
            itemDestroyed = false,
            poiStateChange = nil,
        }

        -- Check if item can do this interaction
        if not self:canPerform(item, interactionType) then
            result.description = "This " .. item.name .. " can't be used that way."
            return result
        end

        -- Handle different interaction types
        if interactionType == M.INTERACTION_TYPES.PROBE then
            return self:handleProbe(item, poi, context)
        elseif interactionType == M.INTERACTION_TYPES.UNLOCK then
            return self:handleUnlock(item, poi, context)
        elseif interactionType == M.INTERACTION_TYPES.TRIGGER then
            return self:handleTrigger(item, poi, context)
        elseif interactionType == M.INTERACTION_TYPES.LIGHT then
            return self:handleLight(item, poi, context)
        elseif interactionType == M.INTERACTION_TYPES.BREAK then
            return self:handleBreak(item, poi, context)
        elseif interactionType == M.INTERACTION_TYPES.WEDGE then
            return self:handleWedge(item, poi, context)
        elseif interactionType == M.INTERACTION_TYPES.PITON then
            return self:handlePiton(item, poi, context)
        end

        result.description = "Nothing happens."
        return result
    end

    ----------------------------------------------------------------------------
    -- INTERACTION HANDLERS
    ----------------------------------------------------------------------------

    --- Handle PROBE interaction (safely check for traps/hazards)
    function system:handleProbe(item, poi, context)
        local result = {
            success = true,
            description = "",
            itemDamaged = false,
            itemDestroyed = false,
        }

        -- Probing a trap
        if poi.trap then
            if poi.trap.detected then
                result.description = "You've already detected a trap here."
                return result
            end

            -- Probing with a pole/tool detects the trap safely!
            result.description = "Using your " .. item.name .. ", you detect " ..
                (poi.trap.description or "a trap") .. "!"

            -- Mark trap as detected
            if self.roomManager and context.roomId then
                local feature = self.roomManager:getFeature(context.roomId, poi.id)
                if feature and feature.trap then
                    feature.trap.detected = true
                end
            end

            -- But the item might still take damage from the probing
            if poi.trap.damages_probe then
                local notchResult = inventory.addNotch(item)
                result.itemDamaged = true
                result.itemDestroyed = (notchResult == "destroyed")

                if result.itemDestroyed then
                    result.description = result.description .. " Your " .. item.name .. " is destroyed in the process!"
                else
                    result.description = result.description .. " Your " .. item.name .. " is slightly damaged."
                end
            end

            -- Emit trap detected event
            self.eventBus:emit(events.EVENTS.TRAP_DETECTED, {
                roomId = context.roomId,
                poiId = poi.id,
                trap = poi.trap,
                method = "item_probe",
                item = item.id,
            })

            return result
        end

        -- Probing a hazard (pit, unstable floor, etc.)
        if poi.type == "hazard" then
            result.description = "You probe the " .. (poi.name or "hazard") .. " with your " .. item.name .. "."

            if poi.hazard_description then
                result.description = result.description .. " " .. poi.hazard_description
            end

            return result
        end

        -- Generic probing
        result.description = "You poke at the " .. (poi.name or "object") .. " with your " .. item.name .. ". Nothing notable happens."
        return result
    end

    --- Handle UNLOCK interaction
    function system:handleUnlock(item, poi, context)
        local result = {
            success = false,
            description = "",
            itemDamaged = false,
            itemDestroyed = false,
        }

        if not hasActiveLock(poi) then
            result.description = "There's nothing to unlock here."
            return result
        end

        local lock = poi.lock or {}

        -- Check for key match
        local lockKeyId = getLockKeyId(lock)
        if lockKeyId then
            if getItemKeyId(item) == lockKeyId then
                result.success = true
                result.description = "The " .. item.name .. " fits! You unlock it."
                result.poiStateChange = "unlocked"
                markFeatureUnlocked(poi)

                if self.roomManager and context.roomId then
                    self.roomManager:setFeatureState(context.roomId, poi.id, "unlocked")
                    local feature = self.roomManager:getFeature(context.roomId, poi.id)
                    markFeatureUnlocked(feature)
                end

                return result
            else
                result.description = "This " .. item.name .. " doesn't fit the lock."
                return result
            end
        end

        -- Lockpick attempt (would normally require a test)
        if isLockpick(item) then
            local difficulty = lock.difficulty or poi.difficulty or 14
            local testResult = context and (context.testResult or context.result)

            if testResult ~= nil then
                if testSucceeded(testResult) then
                    result.success = true
                    result.description = "You pick the lock successfully."
                    result.poiStateChange = "unlocked"
                    result.targetUnlocked = true
                    markFeatureUnlocked(poi)

                    if self.roomManager and context.roomId then
                        self.roomManager:setFeatureState(context.roomId, poi.id, "unlocked")
                        local feature = self.roomManager:getFeature(context.roomId, poi.id)
                        markFeatureUnlocked(feature)
                    end
                else
                    local broke, breakStatus = breakOneLockpick(item, context)
                    result.description = "You fail to pick the lock, and one of your lockpicks breaks."
                    result.failedTest = true
                    result.lockpickBroken = broke
                    result.lockpickBreakStatus = breakStatus
                    result.itemDamaged = broke
                    result.itemDestroyed = breakStatus == "removed" or breakStatus == "destroyed"
                end
                return result
            end

            result.requiresTest = true
            result.testConfig = {
                attribute = "pentacles",
                difficulty = difficulty,
                breakLockpickOnFailure = true,
                success_desc = "You pick the lock successfully.",
                failure_desc = "You fail to pick the lock, and one of your lockpicks breaks.",
            }
            result.description = "You attempt to pick the lock..."
            return result
        end

        result.description = "You can't unlock this with a " .. item.name .. "."
        return result
    end

    --- Handle TRIGGER interaction (activate from distance)
    function system:handleTrigger(item, poi, context)
        local result = {
            success = true,
            description = "",
            itemDamaged = false,
            itemDestroyed = false,
        }

        -- Triggering a known trap from distance
        if poi.trap and poi.trap.detected then
            result.description = "You trigger the trap from a safe distance using your " .. item.name .. "."

            -- Trap is triggered but no one is hurt
            if self.roomManager and context.roomId then
                local feature = self.roomManager:getFeature(context.roomId, poi.id)
                if feature and feature.trap then
                    feature.trap.disarmed = true  -- Triggered = disarmed
                end
            end

            self.eventBus:emit(events.EVENTS.TRAP_TRIGGERED, {
                roomId = context.roomId,
                poiId = poi.id,
                trap = poi.trap,
                method = "item_trigger",
                item = item.id,
                safelyTriggered = true,
            })

            return result
        end

        -- Triggering a mechanism
        if poi.type == "mechanism" then
            result.description = "You activate the " .. (poi.name or "mechanism") .. " with your " .. item.name .. "."
            return result
        end

        result.description = "You poke at it with your " .. item.name .. "."
        return result
    end

    --- Handle LIGHT interaction
    function system:handleLight(item, poi, context)
        local result = {
            success = true,
            description = "",
        }

        if poi.type == "light" and poi.state == "unlit" then
            result.description = "You light the " .. (poi.name or "light source") .. " with your " .. item.name .. "."
            result.poiStateChange = "lit"
            markFireStarted(poi)

            if self.roomManager and context.roomId then
                self.roomManager:setFeatureState(context.roomId, poi.id, "lit")
                local feature = self.roomManager:getFeature(context.roomId, poi.id)
                if feature then
                    markFireStarted(feature)
                end
            end

            return result
        end

        if isFireStartPOI(poi) then
            result.description = "You start a fire at the " .. (poi.name or "fire") .. " with your " .. item.name .. "."
            result.poiStateChange = "lit"
            markFireStarted(poi)

            if self.roomManager and context.roomId then
                self.roomManager:setFeatureState(context.roomId, poi.id, "lit")
                local feature = self.roomManager:getFeature(context.roomId, poi.id)
                if feature then
                    markFireStarted(feature)
                end
            end

            return result
        end

        result.description = "You wave your " .. item.name .. " around, casting dancing shadows."
        return result
    end

    --- Handle BREAK interaction
    function system:handleBreak(item, poi, context)
        local result = {
            success = false,
            description = "",
            itemDamaged = false,
            itemDestroyed = false,
        }

        if isCrowbar(item) and isLockedDoorOrChest(poi) then
            local difficulty = (poi.lock and poi.lock.difficulty) or poi.difficulty or 14
            local testResult = context and (context.testResult or context.result)

            if testResult ~= nil then
                if testSucceeded(testResult) then
                    result.success = true
                    result.description = "You force the " .. (poi.name or "door") .. " open with the crowbar, breaking it."
                    result.poiStateChange = "broken"
                    result.targetBroken = true
                    markFeatureBrokenOpen(poi)

                    if self.roomManager and context.roomId then
                        self.roomManager:setFeatureState(context.roomId, poi.id, "broken")
                        local feature = self.roomManager:getFeature(context.roomId, poi.id)
                        markFeatureBrokenOpen(feature)
                    end
                else
                    result.description = "The " .. (poi.name or "door") .. " holds fast."
                    result.failedTest = true
                end
                return result
            end

            result.requiresTest = true
            result.testConfig = {
                attribute = "swords",
                difficulty = difficulty,
                poiStateChange = "broken",
                breaksTarget = true,
                success_desc = "You force the " .. (poi.name or "door") .. " open with the crowbar, breaking it.",
                failure_desc = "The " .. (poi.name or "door") .. " holds fast.",
            }
            result.description = "You set the crowbar and try to force the " .. (poi.name or "door") .. "."
            return result
        end

        -- Can't break indestructible things
        if poi.indestructible then
            result.description = "The " .. (poi.name or "object") .. " is far too sturdy to break."
            return result
        end

        -- Breaking something usually requires a test or just succeeds for fragile things
        if poi.fragile or poi.breakable then
            result.success = true
            result.description = "You smash the " .. (poi.name or "object") .. " with your " .. item.name .. "!"
            result.poiStateChange = "destroyed"

            if self.roomManager and context.roomId then
                self.roomManager:setFeatureState(context.roomId, poi.id, "destroyed")
            end

            -- Breaking things may damage the tool
            if not poi.fragile then  -- Only fragile things break without tool damage
                local notchResult = inventory.addNotch(item)
                result.itemDamaged = (notchResult == "notched")
                result.itemDestroyed = (notchResult == "destroyed")
            end

            return result
        end

        result.description = "You'd need more than a " .. item.name .. " to break that."
        return result
    end

    --- Handle WEDGE interaction (spike a door or gate closed)
    function system:handleWedge(item, poi, context)
        local result = {
            success = false,
            description = "",
            itemDamaged = false,
            itemDestroyed = false,
        }

        if not isDoorLikePOI(poi) then
            result.description = "Iron spikes can only wedge a door, gate, or similar portal."
            return result
        end
        if poi.open == true or poi.state == "open" then
            result.description = "The " .. (poi.name or "door") .. " must be closed before it can be wedged."
            return result
        end

        local spent, spendStatus = spendOneItemUnit(item, context)
        if not spent then
            result.description = "No iron spike remains to wedge the " .. (poi.name or "door") .. "."
            result.itemSpendStatus = spendStatus
            return result
        end

        markDoorWedged(poi, item)
        result.success = true
        result.description = "You drive an iron spike into the " .. (poi.name or "door") .. ", wedging it closed."
        result.poiStateChange = "wedged"
        result.itemSpent = true
        result.itemSpendStatus = spendStatus
        result.itemDestroyed = spendStatus == "removed"

        if self.roomManager and context.roomId then
            self.roomManager:setFeatureState(context.roomId, poi.id, "wedged")
            local feature = self.roomManager:getFeature(context.roomId, poi.id)
            markDoorWedged(feature or poi, item)
        end

        return result
    end

    --- Handle PITON interaction (set a climbing anchor)
    function system:handlePiton(item, poi, context)
        local result = {
            success = false,
            description = "",
            itemDamaged = false,
            itemDestroyed = false,
        }

        if not isClimbSurfacePOI(poi) then
            result.description = "There is no useful climbing surface to set a piton."
            return result
        end

        local spent, spendStatus = spendOneItemUnit(item, context)
        if not spent then
            result.description = "No iron spike remains to use as a piton."
            result.itemSpendStatus = spendStatus
            return result
        end

        markPitonAnchor(poi, item)
        result.success = true
        result.description = "You drive an iron spike as a piton into the " .. (poi.name or "surface") .. "."
        result.poiStateChange = "pitoned"
        result.itemSpent = true
        result.itemSpendStatus = spendStatus
        result.itemDestroyed = spendStatus == "removed"

        if self.roomManager and context.roomId then
            local feature = self.roomManager:getFeature(context.roomId, poi.id)
            markPitonAnchor(feature or poi, item)
        end

        return result
    end

    ----------------------------------------------------------------------------
    -- DAMAGE ABSORPTION
    -- Items can take notches instead of adventurers taking wounds
    ----------------------------------------------------------------------------

    --- Have an item absorb damage that would wound an adventurer
    -- @param item table: The item absorbing damage
    -- @return table: { absorbed, itemDestroyed, description }
    function system:absorbDamage(item)
        local result = {
            absorbed = false,
            itemDestroyed = false,
            description = "",
        }

        -- Item must be able to absorb damage (shields, armor, tools in hands)
        if item.destroyed then
            result.description = "The " .. item.name .. " is already destroyed."
            return result
        end

        local notchResult = inventory.addNotch(item)

        result.absorbed = true
        result.itemDestroyed = (notchResult == "destroyed")

        if result.itemDestroyed then
            result.description = "Your " .. item.name .. " takes the blow and shatters!"
        else
            result.description = "Your " .. item.name .. " takes the blow and is notched."
        end

        self.eventBus:emit(events.EVENTS.ITEM_DAMAGE_ABSORBED, {
            itemId = item.id,
            destroyed = result.itemDestroyed,
        })

        return result
    end

    return system
end

return M
