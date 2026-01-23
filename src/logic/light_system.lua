-- light_system.lua
-- Light Economy System for Majesty
-- Ticket T3_2: Torch flickering and darkness penalties
-- Rework: Per-adventurer light levels with torch/lantern distinction
--
-- New Rules:
-- - BRIGHT: You have a light source in hands, OR a lantern on belt
-- - DIM: Someone else in the party has a light source in hands (but not you)
-- - DARK: No one has a light source AND no environmental light
-- - Lantern special: Works from belt, but breaks when you take a Wound while belted
-- - Torch rule: Must be in hands to count (belt doesn't work)

local events = require('logic.events')
local inventory = require('logic.inventory')

local M = {}

--------------------------------------------------------------------------------
-- LIGHT SOURCE DEFINITIONS
-- Items that can provide light and their properties
--------------------------------------------------------------------------------
M.LIGHT_SOURCES = {
    ["Torch"]       = {
        flicker_max = 3,
        consumable = true,
        requires_hands = true,       -- Must be in hands to provide light
        provides_belt_light = false, -- Does NOT work from belt
        fragile_on_belt = false,
    },
    ["Lantern"]     = {
        flicker_max = 6,
        consumable = false,          -- Uses oil
        requires_hands = false,      -- Works from hands OR belt
        provides_belt_light = true,  -- Works from belt
        fragile_on_belt = true,      -- Breaks when taking wound while on belt
    },
    ["Candle"]      = {
        flicker_max = 2,
        consumable = true,
        requires_hands = true,
        provides_belt_light = false,
        fragile_on_belt = false,
    },
    ["Glowstone"]   = {
        flicker_max = 0,             -- Never gutters
        consumable = false,
        requires_hands = false,      -- Works from anywhere
        provides_belt_light = true,
        fragile_on_belt = false,     -- Magical, doesn't break
    },
}

--------------------------------------------------------------------------------
-- LIGHT LEVELS (simplified - removed NORMAL)
--------------------------------------------------------------------------------
M.LIGHT_LEVELS = {
    BRIGHT = "bright",       -- You have a working light source
    DIM    = "dim",          -- Someone else has light, or environmental light
    DARK   = "dark",         -- No light source anywhere
}

--------------------------------------------------------------------------------
-- LIGHT SYSTEM FACTORY
--------------------------------------------------------------------------------

--- Create a new LightSystem
-- @param config table: { eventBus, guild, zoneSystem }
-- @return LightSystem instance
function M.createLightSystem(config)
    config = config or {}

    local system = {
        eventBus   = config.eventBus or events.globalBus,
        guild      = config.guild or {},    -- Array of adventurers with inventories
        zoneSystem = config.zoneSystem,     -- Optional: for zone-based darkness

        -- Track light level per entity (new system)
        entityLightLevels = {},

        -- Track current party-wide light level (for backward compatibility)
        currentLightLevel = nil,

        -- UI callback for darkness effect
        onDarknessChanged = config.onDarknessChanged,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    --- Initialize and subscribe to events
    function system:init()
        -- Subscribe to torches gutter events
        self.eventBus:on(events.EVENTS.TORCHES_GUTTER, function(data)
            self:handleTorchesGutter(data)
        end)

        -- Subscribe to wound taken events for lantern breaking
        self.eventBus:on(events.EVENTS.WOUND_TAKEN, function(data)
            self:handleWoundTaken(data)
        end)

        -- Subscribe to inventory changes (items moved between slots)
        self.eventBus:on(events.EVENTS.INVENTORY_CHANGED, function(data)
            self:recalculateLightLevels()
        end)

        -- Initial light check
        self:recalculateLightLevels()
    end

    ----------------------------------------------------------------------------
    -- LIGHT SOURCE TRACKING
    ----------------------------------------------------------------------------

    --- Check if an item is a light source
    -- @param item table: Inventory item
    -- @return boolean, table: isLightSource, lightSourceConfig
    function system:isLightSource(item)
        if not item or item.destroyed then
            return false, nil
        end

        local config = M.LIGHT_SOURCES[item.name]
        if config then
            return true, config
        end

        -- Check for light_source property on custom items
        if item.properties and item.properties.light_source then
            return true, item.properties.light_source
        end

        return false, nil
    end

    --- Check if a light source is active (lit, has flickers remaining, not extinguished)
    -- @param item table: The light source item
    -- @param lightConfig table: The light source configuration
    -- @return boolean
    function system:isLightActive(item, lightConfig)
        if item.destroyed then
            return false
        end

        if item.properties and item.properties.extinguished then
            return false
        end

        -- Check if explicitly lit (defaults to true if not set, for backward compat)
        -- Items with isLit = false are "unlit" and don't provide light
        if item.properties and item.properties.isLit == false then
            return false
        end

        -- Check flicker count
        local flickerCount = item.properties and item.properties.flicker_count
        if flickerCount and flickerCount <= 0 then
            return false
        end

        return true
    end

    --- Light a light source (set isLit = true)
    -- @param item table: The light source item
    -- @return boolean: success
    function system:lightItem(item)
        local isLight, lightConfig = self:isLightSource(item)
        if not isLight then
            return false
        end

        if item.destroyed then
            return false
        end

        if not item.properties then
            item.properties = {}
        end

        item.properties.isLit = true
        item.properties.extinguished = false

        -- Initialize flicker count if not set
        if not item.properties.flicker_count then
            item.properties.flicker_count = lightConfig.flicker_max
        end

        self:recalculateLightLevels()
        return true
    end

    --- Extinguish/douse a light source (set isLit = false)
    -- @param item table: The light source item
    -- @return boolean: success
    function system:extinguishItem(item)
        local isLight = self:isLightSource(item)
        if not isLight then
            return false
        end

        if not item.properties then
            item.properties = {}
        end

        item.properties.isLit = false

        self:recalculateLightLevels()
        return true
    end

    --- Check if an entity has a light source in their hands
    -- @param entity table: The entity to check
    -- @return boolean, table: hasLight, lightItem
    function system:hasHandsLight(entity)
        if not entity.inventory then
            return false, nil
        end

        local handsItems = entity.inventory:getItems(inventory.LOCATIONS.HANDS)
        for _, item in ipairs(handsItems) do
            local isLight, lightConfig = self:isLightSource(item)
            if isLight and self:isLightActive(item, lightConfig) then
                return true, item
            end
        end

        return false, nil
    end

    --- Check if an entity has a belt lantern (provides_belt_light)
    -- @param entity table: The entity to check
    -- @return boolean, table: hasLight, lightItem
    function system:hasBeltLight(entity)
        if not entity.inventory then
            return false, nil
        end

        local beltItems = entity.inventory:getItems(inventory.LOCATIONS.BELT)
        for _, item in ipairs(beltItems) do
            local isLight, lightConfig = self:isLightSource(item)
            if isLight and lightConfig and lightConfig.provides_belt_light then
                if self:isLightActive(item, lightConfig) then
                    return true, item
                end
            end
        end

        return false, nil
    end

    --- Check if anyone in the party has an active light source (hands or belt lantern)
    -- @param excludeEntity table: Optional entity to exclude from check
    -- @return boolean
    function system:hasPartyLight(excludeEntity)
        for _, entity in ipairs(self.guild) do
            if entity ~= excludeEntity then
                -- Check hands
                local hasHandsLight = self:hasHandsLight(entity)
                if hasHandsLight then
                    return true
                end
                -- Check belt (lanterns)
                local hasBeltLight = self:hasBeltLight(entity)
                if hasBeltLight then
                    return true
                end
            end
        end
        return false
    end

    --- Find all active light sources in the guild
    -- @return table: Array of { entity, item, location }
    function system:findActiveLightSources()
        local sources = {}

        for _, entity in ipairs(self.guild) do
            if entity.inventory then
                -- Check hands
                local handsItems = entity.inventory:getItems(inventory.LOCATIONS.HANDS)
                for _, item in ipairs(handsItems) do
                    local isLight, lightConfig = self:isLightSource(item)
                    if isLight and self:isLightActive(item, lightConfig) then
                        sources[#sources + 1] = {
                            entity      = entity,
                            item        = item,
                            location    = "hands",
                            lightConfig = lightConfig,
                        }
                    end
                end

                -- Check belt (only for provides_belt_light items)
                local beltItems = entity.inventory:getItems(inventory.LOCATIONS.BELT)
                for _, item in ipairs(beltItems) do
                    local isLight, lightConfig = self:isLightSource(item)
                    if isLight and lightConfig and lightConfig.provides_belt_light then
                        if self:isLightActive(item, lightConfig) then
                            sources[#sources + 1] = {
                                entity      = entity,
                                item        = item,
                                location    = "belt",
                                lightConfig = lightConfig,
                            }
                        end
                    end
                end
            end
        end

        return sources
    end

    ----------------------------------------------------------------------------
    -- TORCHES GUTTER HANDLING
    -- Called when Major Arcana I-V is drawn
    ----------------------------------------------------------------------------

    --- Handle the Torches Gutter event
    -- @param data table: { card, category, value }
    function system:handleTorchesGutter(data)
        local sources = self:findActiveLightSources()

        if #sources == 0 then
            -- No light sources to degrade - darkness intensifies
            self:recalculateLightLevels()
            return
        end

        -- Find the primary light holder (first adventurer holding light in hands)
        local primarySource = nil
        for _, source in ipairs(sources) do
            if source.location == "hands" then
                primarySource = source
                break
            end
        end

        -- Fall back to first available source
        if not primarySource then
            primarySource = sources[1]
        end

        -- Decrement flicker count
        local item = primarySource.item
        local lightConfig = primarySource.lightConfig

        -- Initialize flicker_count if not set
        if not item.properties then
            item.properties = {}
        end
        if not item.properties.flicker_count then
            item.properties.flicker_count = lightConfig.flicker_max
        end

        -- Decrement
        item.properties.flicker_count = item.properties.flicker_count - 1

        -- Emit event for UI updates
        self.eventBus:emit("light_flickered", {
            entity       = primarySource.entity,
            item         = item,
            remaining    = item.properties.flicker_count,
            cardValue    = data.value,
        })

        -- Check if extinguished
        if item.properties.flicker_count <= 0 then
            self:extinguishLight(primarySource)
        end

        -- Recalculate overall light levels
        self:recalculateLightLevels()
    end

    --- Extinguish a light source
    -- @param source table: { entity, item, location, lightConfig }
    function system:extinguishLight(source)
        local item = source.item
        local lightConfig = source.lightConfig

        if lightConfig.consumable then
            -- Consumable lights are destroyed (torches, candles)
            item.destroyed = true
            item.properties.extinguished = true

            self.eventBus:emit("light_destroyed", {
                entity = source.entity,
                item   = item,
            })
        else
            -- Non-consumable lights need refueling (lanterns)
            item.properties.extinguished = true

            self.eventBus:emit("light_extinguished", {
                entity = source.entity,
                item   = item,
                needsFuel = true,
            })
        end
    end

    ----------------------------------------------------------------------------
    -- LANTERN BREAKING ON WOUND
    -- When a PC takes a Wound with a fragile lantern on belt, it breaks
    ----------------------------------------------------------------------------

    --- Handle wound taken event - check for lantern breaking
    -- @param data table: { entity, result, ... }
    function system:handleWoundTaken(data)
        local entity = data.entity

        -- Only check PCs
        if not entity or not entity.isPC then
            return
        end

        -- Check if entity has inventory
        if not entity.inventory then
            return
        end

        -- Check belt for fragile light sources
        local beltItems = entity.inventory:getItems(inventory.LOCATIONS.BELT)
        for _, item in ipairs(beltItems) do
            local isLight, lightConfig = self:isLightSource(item)
            if isLight and lightConfig and lightConfig.fragile_on_belt then
                -- Break the lantern!
                self:breakLantern(entity, item)
            end
        end
    end

    --- Break a lantern (called when wound taken with fragile item on belt)
    -- @param entity table: The entity whose lantern broke
    -- @param item table: The lantern item
    function system:breakLantern(entity, item)
        -- Mark as destroyed
        item.destroyed = true
        if not item.properties then
            item.properties = {}
        end
        item.properties.broken = true
        item.properties.extinguished = true

        -- Emit lantern broken event
        self.eventBus:emit(events.EVENTS.LANTERN_BROKEN, {
            entity = entity,
            item   = item,
        })

        -- Recalculate light levels
        self:recalculateLightLevels()
    end

    ----------------------------------------------------------------------------
    -- LIGHT LEVEL CALCULATION (Per-Entity)
    ----------------------------------------------------------------------------

    --- Get the light level for a specific entity
    -- @param entity table: The entity to check
    -- @return string: One of LIGHT_LEVELS (BRIGHT/DIM/DARK)
    function system:getLightLevelForEntity(entity)
        -- 1. Check entity's hands for any active light source → BRIGHT
        local hasHandsLight = self:hasHandsLight(entity)
        if hasHandsLight then
            return M.LIGHT_LEVELS.BRIGHT
        end

        -- 2. Check entity's belt for lantern with provides_belt_light → BRIGHT
        local hasBeltLight = self:hasBeltLight(entity)
        if hasBeltLight then
            return M.LIGHT_LEVELS.BRIGHT
        end

        -- 3. Check if any OTHER entity has an active light source → DIM
        if self:hasPartyLight(entity) then
            return M.LIGHT_LEVELS.DIM
        end

        -- 4. Check environmental light (future stub) → DIM
        -- TODO: Check zone/room for environmental light sources
        -- if self:hasEnvironmentalLight(entity) then
        --     return M.LIGHT_LEVELS.DIM
        -- end

        -- 5. Otherwise → DARK
        return M.LIGHT_LEVELS.DARK
    end

    --- Recalculate light levels for all entities
    function system:recalculateLightLevels()
        local previousLevels = {}
        for id, level in pairs(self.entityLightLevels) do
            previousLevels[id] = level
        end

        -- Calculate new levels for each entity
        for _, entity in ipairs(self.guild) do
            local entityId = entity.id or tostring(entity)
            local newLevel = self:getLightLevelForEntity(entity)
            local previousLevel = self.entityLightLevels[entityId]

            self.entityLightLevels[entityId] = newLevel

            -- Emit change event if level changed for this entity
            if previousLevel ~= newLevel then
                self.eventBus:emit(events.EVENTS.ENTITY_LIGHT_CHANGED, {
                    entity   = entity,
                    previous = previousLevel,
                    current  = newLevel,
                })
            end
        end

        -- Update party-wide level (worst level for backward compatibility)
        local previousPartyLevel = self.currentLightLevel
        self.currentLightLevel = self:getWorstLightLevel()

        -- Emit party-wide change event if level changed
        if previousPartyLevel ~= self.currentLightLevel then
            local sources = self:findActiveLightSources()

            self.eventBus:emit("light_level_changed", {
                previous = previousPartyLevel,
                current  = self.currentLightLevel,
                sources  = #sources,
            })

            -- Apply darkness penalties if now dark
            if self.currentLightLevel == M.LIGHT_LEVELS.DARK then
                self:applyDarknessPenalty()
            elseif previousPartyLevel == M.LIGHT_LEVELS.DARK then
                self:removeDarknessPenalty()
            end

            -- Notify UI callback
            if self.onDarknessChanged then
                self.onDarknessChanged(self.currentLightLevel)
            end
        end
    end

    --- Get the worst (darkest) light level across all entities
    -- @return string: One of LIGHT_LEVELS
    function system:getWorstLightLevel()
        local hasDark = false
        local hasDim = false

        for _, entity in ipairs(self.guild) do
            local entityId = entity.id or tostring(entity)
            local level = self.entityLightLevels[entityId]

            if level == M.LIGHT_LEVELS.DARK then
                hasDark = true
            elseif level == M.LIGHT_LEVELS.DIM then
                hasDim = true
            end
        end

        if hasDark then
            return M.LIGHT_LEVELS.DARK
        elseif hasDim then
            return M.LIGHT_LEVELS.DIM
        else
            return M.LIGHT_LEVELS.BRIGHT
        end
    end

    ----------------------------------------------------------------------------
    -- DARKNESS PENALTIES
    -- When in darkness, entities gain BLIND effect
    ----------------------------------------------------------------------------

    --- Apply darkness penalty (BLIND) to entities in the dark
    function system:applyDarknessPenalty()
        local darkCount = 0

        for _, entity in ipairs(self.guild) do
            local entityId = entity.id or tostring(entity)
            local level = self.entityLightLevels[entityId]

            if level == M.LIGHT_LEVELS.DARK then
                if entity.conditions then
                    entity.conditions.blind = true
                end
                darkCount = darkCount + 1
            end
        end

        if darkCount > 0 then
            self.eventBus:emit("darkness_fell", {
                affectedCount = darkCount,
            })
        end
    end

    --- Remove darkness penalty when light is restored
    function system:removeDarknessPenalty()
        local restoredCount = 0

        for _, entity in ipairs(self.guild) do
            local entityId = entity.id or tostring(entity)
            local level = self.entityLightLevels[entityId]

            -- Only remove blind if they now have light
            if level ~= M.LIGHT_LEVELS.DARK then
                if entity.conditions and entity.conditions.blind then
                    entity.conditions.blind = false
                    restoredCount = restoredCount + 1
                end
            end
        end

        if restoredCount > 0 then
            self.eventBus:emit("darkness_lifted", {
                affectedCount = restoredCount,
            })
        end
    end

    ----------------------------------------------------------------------------
    -- LIGHT ITEM UTILITIES
    ----------------------------------------------------------------------------

    --- Light a new torch/candle (set initial flicker count)
    -- @param item table: The light source item
    -- @return boolean: success
    function system:lightSource(item)
        local isLight, lightConfig = self:isLightSource(item)
        if not isLight then
            return false
        end

        if item.destroyed then
            return false
        end

        if not item.properties then
            item.properties = {}
        end

        item.properties.flicker_count = lightConfig.flicker_max
        item.properties.extinguished = false

        self:recalculateLightLevels()
        return true
    end

    --- Refuel a lantern (reset flicker count)
    -- @param lantern table: The lantern item
    -- @param fuel table: The oil/fuel item (will be consumed)
    -- @return boolean: success
    function system:refuelLantern(lantern, fuel)
        if lantern.name ~= "Lantern" then
            return false
        end

        if not fuel or fuel.destroyed then
            return false
        end

        -- Consume fuel
        if fuel.stackable and fuel.quantity > 1 then
            fuel.quantity = fuel.quantity - 1
        else
            fuel.destroyed = true
        end

        -- Reset lantern
        if not lantern.properties then
            lantern.properties = {}
        end
        lantern.properties.flicker_count = M.LIGHT_SOURCES["Lantern"].flicker_max
        lantern.properties.extinguished = false

        self:recalculateLightLevels()
        return true
    end

    ----------------------------------------------------------------------------
    -- QUERIES
    ----------------------------------------------------------------------------

    --- Get the current party-wide light level (backward compatibility)
    -- Returns the worst (darkest) level across all entities
    function system:getLightLevel()
        return self.currentLightLevel or M.LIGHT_LEVELS.DARK
    end

    --- Check if party has anyone in darkness
    function system:isDark()
        return self.currentLightLevel == M.LIGHT_LEVELS.DARK
    end

    --- Check if a specific entity is in darkness
    function system:isEntityDark(entity)
        local entityId = entity.id or tostring(entity)
        return self.entityLightLevels[entityId] == M.LIGHT_LEVELS.DARK
    end

    --- Get light level for a specific entity
    function system:getEntityLightLevel(entity)
        local entityId = entity.id or tostring(entity)
        return self.entityLightLevels[entityId] or M.LIGHT_LEVELS.DARK
    end

    --- Get total remaining flickers across all light sources
    function system:getTotalFlickers()
        local sources = self:findActiveLightSources()
        local total = 0

        for _, source in ipairs(sources) do
            local remaining = source.item.properties and source.item.properties.flicker_count
            if remaining then
                total = total + remaining
            else
                total = total + source.lightConfig.flicker_max
            end
        end

        return total
    end

    --- Set the guild (for updates during gameplay)
    function system:setGuild(guildMembers)
        self.guild = guildMembers
        self:recalculateLightLevels()
    end

    return system
end

return M
