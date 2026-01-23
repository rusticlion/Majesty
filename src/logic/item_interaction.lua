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
        if poi.lock and poi.lock.key_id then
            if item.properties and item.properties.key_id == poi.lock.key_id then
                return true, "key_matches"
            end
        end

        -- Check if item can probe hazards
        if poi.trap or poi.type == "hazard" then
            if self:canPerform(item, M.INTERACTION_TYPES.PROBE) then
                return true, "can_probe_hazard"
            end
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

        if not poi.lock then
            result.description = "There's nothing to unlock here."
            return result
        end

        -- Check for key match
        if poi.lock.key_id then
            if item.properties and item.properties.key_id == poi.lock.key_id then
                result.success = true
                result.description = "The " .. item.name .. " fits! You unlock it."
                result.poiStateChange = "unlocked"

                if self.roomManager and context.roomId then
                    self.roomManager:setFeatureState(context.roomId, poi.id, "unlocked")
                end

                return result
            else
                result.description = "This " .. item.name .. " doesn't fit the lock."
                return result
            end
        end

        -- Lockpick attempt (would normally require a test)
        if item.name == "Lockpick" or (item.properties and item.properties.lockpick) then
            result.requiresTest = true
            result.testConfig = {
                attribute = "pentacles",
                difficulty = poi.lock.difficulty or 14,
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

            if self.roomManager and context.roomId then
                self.roomManager:setFeatureState(context.roomId, poi.id, "lit")
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
