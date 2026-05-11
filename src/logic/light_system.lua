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
local constants = require('constants')

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
        provides_dim_light = true,    -- Provides dim light to nearby guildmates
        fragile_on_belt = false,
    },
    ["Lantern"]     = {
        flicker_max = 4,
        consumable = false,          -- Uses oil
        requires_hands = false,      -- Works from hands OR belt
        provides_belt_light = true,  -- Works from belt
        provides_dim_light = true,    -- Provides dim light to nearby guildmates
        fragile_on_belt = true,      -- Breaks when taking wound while on belt
    },
    ["Candle"]      = {
        flicker_max = 2,
        consumable = true,
        requires_hands = true,
        provides_belt_light = false,
        provides_dim_light = false,   -- Candles do not illuminate nearby guildmates
        fragile_on_belt = false,
    },
    ["Glowstone"]   = {
        flicker_max = 0,             -- Never gutters
        consumable = false,
        requires_hands = false,      -- Works from anywhere
        provides_belt_light = true,
        provides_dim_light = true,
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

M.DARKNESS_DOOMS = {
    GRUE = "eaten_by_grue",
    CAPTURED_BY_MONSTERS = "captured_by_monsters",
    OLU_GANG_RANSOM = "olu_gang_ransom",
    LOST_IN_UNDERWORLD = "lost_in_underworld",
    RETIRED = "retired",
    LOST_ALL_EQUIPMENT = "lost_all_equipment",
    RISK_EQUIPMENT_LOSS = "risk_equipment_loss",
    RAVING_DARKNESS = "raving_darkness",
}

local function entityKey(entity)
    if not entity then
        return nil
    end
    return entity.id or entity.name or tostring(entity)
end

local function listContainsEntityKey(list, key)
    if type(list) ~= "table" or not key then
        return false
    end
    if list[key] == true then
        return true
    end
    for _, value in ipairs(list) do
        if value == key then
            return true
        end
        if type(value) == "table" and entityKey(value) == key then
            return true
        end
    end
    return false
end

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
        playerDeck = config.playerDeck,
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

        -- Legacy/auxiliary UI source: explicit light toggles
        self.eventBus:on(events.EVENTS.LIGHT_SOURCE_TOGGLED, function(data)
            self:handleLightSourceToggled(data)
        end)

        self.eventBus:on(events.EVENTS.LIGHT_SOURCE_DROPPED, function(data)
            self:handleLightSourceDropped(data)
        end)

        -- Initial light check
        self:recalculateLightLevels()
    end

    ----------------------------------------------------------------------------
    -- LIGHT SOURCE TRACKING
    ----------------------------------------------------------------------------

    --- Read lit state from either canonical or legacy field names.
    function system:getItemLitState(item)
        if not item or not item.properties then
            return true
        end
        if item.properties.isLit ~= nil then
            return item.properties.isLit
        end
        if item.properties.is_lit ~= nil then
            return item.properties.is_lit
        end
        return true
    end

    --- Write lit state to canonical and legacy field names for compatibility.
    function system:setItemLitState(item, isLit)
        if not item.properties then
            item.properties = {}
        end
        item.properties.isLit = isLit
        item.properties.is_lit = isLit
    end

    --- Build a normalized light config from item properties.
    function system:buildLightConfigFromProperties(item)
        local props = item and item.properties or {}
        local source = props and props.light_source

        local config = {
            flicker_max = props.flicker_count or 3,
            consumable = props.consumable ~= false,
            requires_hands = props.requires_hands ~= false,
            provides_belt_light = props.provides_belt_light == true,
            provides_dim_light = props.provides_dim_light ~= false,
            fragile_on_belt = props.fragile_on_belt == true,
        }

        if type(source) == "table" then
            if source.flicker_max ~= nil then config.flicker_max = source.flicker_max end
            if source.consumable ~= nil then config.consumable = source.consumable end
            if source.requires_hands ~= nil then config.requires_hands = source.requires_hands end
            if source.provides_belt_light ~= nil then config.provides_belt_light = source.provides_belt_light end
            if source.provides_dim_light ~= nil then config.provides_dim_light = source.provides_dim_light end
            if source.fragile_on_belt ~= nil then config.fragile_on_belt = source.fragile_on_belt end
        end

        return config
    end

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
            return true, self:buildLightConfigFromProperties(item)
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
        if self:getItemLitState(item) == false then
            return false
        end

        -- Check flicker count
        local flickerCount = item.properties and item.properties.flicker_count
        local infiniteSource = lightConfig and (lightConfig.flicker_max or 0) <= 0
        if not infiniteSource and flickerCount and flickerCount <= 0 then
            return false
        end

        return true
    end

    function system:lightIgnoresTorchesGutter(item)
        local props = item and item.properties or {}
        return props.darklight == true or props.ignoreTorchesGutter == true or props.darklightIgnoreTorchesGutter == true
    end

    function system:canEntitySeeLight(holder, item, viewer)
        local props = item and item.properties or {}
        if props.darklight ~= true then
            return true
        end
        if not viewer or viewer == holder then
            return true
        end

        local key = entityKey(viewer)
        if key and props.darklightHolderId == key then
            return true
        end

        return listContainsEntityKey(props.darklightVisibleTo, key)
    end

    function system:providesDimLightToOthers(item, lightConfig, holder, viewer)
        if item and item.properties and item.properties.darklight == true then
            return self:canEntitySeeLight(holder, item, viewer)
        end
        if not lightConfig then
            return true
        end
        return lightConfig.provides_dim_light ~= false
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

        self:setItemLitState(item, true)
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

        self:setItemLitState(item, false)

        self:recalculateLightLevels()
        return true
    end

    --- Handle explicit light source toggle events from UI layers.
    -- @param data table: { item, lit }
    function system:handleLightSourceToggled(data)
        local item = data and data.item
        if not item then
            return
        end

        if data.lit == true then
            self:lightItem(item)
        elseif data.lit == false then
            self:extinguishItem(item)
        else
            self:recalculateLightLevels()
        end
    end

    function system:shouldTorchStayLitWhenDropped(data)
        if data and data.torchStaysLit ~= nil then
            return data.torchStaysLit == true
        end
        if data and data.torchExtinguished ~= nil then
            return data.torchExtinguished ~= true
        end
        return math.random(2) == 1
    end

    function system:handleLightSourceDropped(data)
        data = data or {}
        local item = data.item
        if not item then
            return
        end

        local isLight = self:isLightSource(item)
        if not isLight then
            return
        end

        item.properties = item.properties or {}
        local name = string.lower(item.name or "")

        if name == "lantern" then
            self:breakLantern(data.entity, item, "dropped")
        elseif name == "candle" or name == "candles" then
            self:setItemLitState(item, false)
            item.properties.extinguished = true
            self.eventBus:emit(events.EVENTS.LIGHT_EXTINGUISHED, {
                entity = data.entity,
                item = item,
                reason = "dropped",
            })
            self:recalculateLightLevels()
        elseif name == "torch" then
            if self:shouldTorchStayLitWhenDropped(data) then
                self:recalculateLightLevels()
            else
                item.destroyed = true
                item.properties.extinguished = true
                self:setItemLitState(item, false)
                self.eventBus:emit(events.EVENTS.LIGHT_DESTROYED, {
                    entity = data.entity,
                    item = item,
                    reason = "dropped",
                })
                self:recalculateLightLevels()
            end
        end
    end

    function system:cardValue(card)
        if type(card) == "number" then
            return card
        end
        return card and card.value
    end

    function system:getDarknessDoomType(card)
        local value = self:cardValue(card)
        if not value then
            return nil
        end

        if value >= 1 and value <= 7 then
            return M.DARKNESS_DOOMS.GRUE
        elseif value == 8 then
            return M.DARKNESS_DOOMS.CAPTURED_BY_MONSTERS
        elseif value == 9 then
            return M.DARKNESS_DOOMS.OLU_GANG_RANSOM
        elseif value == 10 then
            return M.DARKNESS_DOOMS.LOST_IN_UNDERWORLD
        elseif value == constants.FACE_VALUES.PAGE then
            return M.DARKNESS_DOOMS.RETIRED
        elseif value == constants.FACE_VALUES.KNIGHT then
            return M.DARKNESS_DOOMS.LOST_ALL_EQUIPMENT
        elseif value == constants.FACE_VALUES.QUEEN then
            return M.DARKNESS_DOOMS.RISK_EQUIPMENT_LOSS
        elseif value == constants.FACE_VALUES.KING then
            return M.DARKNESS_DOOMS.RAVING_DARKNESS
        end

        return nil
    end

    function system:removeAllEquipment(entity)
        local removed = {}
        if not entity or not entity.inventory or not entity.inventory.getAllItems or not entity.inventory.removeItem then
            return removed
        end

        local allItems = entity.inventory:getAllItems()
        for _, entry in ipairs(allItems) do
            local item = entry.item
            if item and item.id then
                local removedItem = entity.inventory:removeItem(item.id)
                if removedItem then
                    removed[#removed + 1] = removedItem
                end
            end
        end

        return removed
    end

    function system:removeSelectedEquipment(entity, shouldLoseItem)
        local removed = {}
        if not entity or not entity.inventory or not entity.inventory.getAllItems or not entity.inventory.removeItem then
            return removed
        end

        local allItems = entity.inventory:getAllItems()
        for index, entry in ipairs(allItems) do
            local item = entry.item
            local lose = false
            if type(shouldLoseItem) == "function" then
                lose = shouldLoseItem(item, entry.location, index) == true
            elseif type(shouldLoseItem) == "table" then
                lose = shouldLoseItem[item and item.id] == true or shouldLoseItem[index] == true
            else
                lose = math.random(2) == 1
            end

            if lose and item and item.id then
                local removedItem = entity.inventory:removeItem(item.id)
                if removedItem then
                    removed[#removed + 1] = removedItem
                end
            end
        end

        return removed
    end

    function system:resolveDarknessDoom(entity, card, opts)
        opts = opts or {}
        local doomType = self:getDarknessDoomType(card)
        local result = {
            entity = entity,
            card = card,
            value = self:cardValue(card),
            doom = doomType,
            lostItems = {},
        }

        if not entity or not doomType then
            return result
        end

        entity.conditions = entity.conditions or {}

        if doomType == M.DARKNESS_DOOMS.GRUE then
            entity.conditions.dead = true
            entity.dead = true
            entity.defeated = true
            entity.darknessDoom = doomType
        elseif doomType == M.DARKNESS_DOOMS.CAPTURED_BY_MONSTERS then
            entity.conditions.captured = true
            entity.capturedByMonsters = true
            entity.darknessDoom = doomType
        elseif doomType == M.DARKNESS_DOOMS.OLU_GANG_RANSOM then
            entity.conditions.captured = true
            entity.heldForRansom = {
                captor = "Olu Gang",
                costPerFame = 1000,
            }
            entity.darknessDoom = doomType
        elseif doomType == M.DARKNESS_DOOMS.LOST_IN_UNDERWORLD then
            entity.conditions.lost = true
            entity.lostInUnderworld = true
            entity.darknessDoom = doomType
        elseif doomType == M.DARKNESS_DOOMS.RETIRED then
            entity.retired = true
            entity.controlledByGM = true
            entity.darknessDoom = doomType
        elseif doomType == M.DARKNESS_DOOMS.LOST_ALL_EQUIPMENT then
            result.lostItems = self:removeAllEquipment(entity)
            entity.lostDarknessEquipment = result.lostItems
            entity.darknessDoom = doomType
        elseif doomType == M.DARKNESS_DOOMS.RISK_EQUIPMENT_LOSS then
            result.lostItems = self:removeSelectedEquipment(entity, opts.loseItem)
            entity.lostDarknessEquipment = result.lostItems
            entity.darknessDoom = doomType
        elseif doomType == M.DARKNESS_DOOMS.RAVING_DARKNESS then
            entity.conditions.stressed = true
            entity.ravingAboutDarkness = true
            entity.darknessDoom = doomType
        end

        return result
    end

    function system:itemIsFuel(item)
        local props = item and item.properties or {}
        return not item.destroyed and (props.fuel == true or props.oil == true)
    end

    function system:guildHasLanternFuel()
        for _, entity in ipairs(self.guild) do
            if entity.inventory and entity.inventory.getAllItems then
                for _, entry in ipairs(entity.inventory:getAllItems()) do
                    if self:itemIsFuel(entry.item) then
                        return true
                    end
                end
            end
        end

        return false
    end

    function system:isRecoverableLightSource(item)
        local isLight, lightConfig = self:isLightSource(item)
        if not isLight or not item or item.destroyed then
            return false
        end

        if self:isLightActive(item, lightConfig) then
            return true
        end

        local props = item.properties or {}
        local name = string.lower(item.name or "")
        local flickers = props.flicker_count
        if flickers ~= nil and flickers <= 0 then
            return false
        end

        if name == "candle" or name == "candles" then
            return true
        elseif name == "lantern" then
            return self:guildHasLanternFuel()
        elseif name == "torch" then
            return props.extinguished ~= true
        end

        return lightConfig and (lightConfig.flicker_max or 0) <= 0
    end

    function system:guildHasRecoverableLightSource()
        for _, entity in ipairs(self.guild) do
            if entity.inventory and entity.inventory.getAllItems then
                for _, entry in ipairs(entity.inventory:getAllItems()) do
                    if self:isRecoverableLightSource(entry.item) then
                        return true
                    end
                end
            end
        end

        return false
    end

    function system:resolveOutOfLightDoom(drawsByEntity)
        local results = {}
        for index, entity in ipairs(self.guild) do
            local card = nil
            if type(drawsByEntity) == "table" then
                card = drawsByEntity[entity] or drawsByEntity[entity.id] or drawsByEntity[index]
            end
            if not card and self.playerDeck and self.playerDeck.draw then
                card = self.playerDeck:draw()
            end

            results[#results + 1] = self:resolveDarknessDoom(entity, card)
        end

        self.eventBus:emit(events.EVENTS.DARKNESS_DOOMED, {
            results = results,
            needsDraw = not self.playerDeck and drawsByEntity == nil,
        })

        return results
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
                local hasHandsLight, handsLight = self:hasHandsLight(entity)
                local _, handsConfig = self:isLightSource(handsLight)
                if hasHandsLight and self:providesDimLightToOthers(handsLight, handsConfig, entity, excludeEntity) and
                   self:canEntitySeeLight(entity, handsLight, excludeEntity) then
                    return true
                end
                -- Check belt (lanterns)
                local hasBeltLight, beltLight = self:hasBeltLight(entity)
                local _, beltConfig = self:isLightSource(beltLight)
                if hasBeltLight and self:providesDimLightToOthers(beltLight, beltConfig, entity, excludeEntity) and
                   self:canEntitySeeLight(entity, beltLight, excludeEntity) then
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
        local forcedExtinguished = {}
        for _, source in ipairs(sources) do
            local props = source.item and source.item.properties or {}
            if props.extinguishOnMeatgrinder == "torches_gutter" then
                self:setItemLitState(source.item, false)
                props.extinguished = true
                forcedExtinguished[source.item] = true
                self.eventBus:emit(events.EVENTS.LIGHT_EXTINGUISHED, {
                    entity = source.entity,
                    item = source.item,
                    reason = "torches_gutter",
                    cardValue = data and data.value,
                })
            end
        end

        local degradableSources = {}
        for _, source in ipairs(sources) do
            if source.lightConfig and (source.lightConfig.flicker_max or 0) > 0 and
               not forcedExtinguished[source.item] and not self:lightIgnoresTorchesGutter(source.item) then
                degradableSources[#degradableSources + 1] = source
            end
        end

        if #degradableSources == 0 then
            -- No light sources to degrade - darkness intensifies
            self:recalculateLightLevels()
            return
        end

        -- Find the primary light holder (first adventurer holding light in hands)
        local primarySource = nil
        for _, source in ipairs(degradableSources) do
            if source.location == "hands" then
                primarySource = source
                break
            end
        end

        -- Fall back to first available source
        if not primarySource then
            primarySource = degradableSources[1]
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
        self.eventBus:emit(events.EVENTS.LIGHT_FLICKERED, {
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
        if not item.properties then
            item.properties = {}
        end
        self:setItemLitState(item, false)

        if lightConfig.consumable then
            -- Consumable lights are destroyed (torches, candles)
            item.destroyed = true
            item.properties.extinguished = true

            self.eventBus:emit(events.EVENTS.LIGHT_DESTROYED, {
                entity = source.entity,
                item   = item,
            })
        else
            -- Non-consumable lights need refueling (lanterns)
            item.properties.extinguished = true

            self.eventBus:emit(events.EVENTS.LIGHT_EXTINGUISHED, {
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
    function system:breakLantern(entity, item, reason)
        -- Mark as destroyed
        item.destroyed = true
        if not item.properties then
            item.properties = {}
        end
        item.properties.broken = true
        item.properties.extinguished = true
        self:setItemLitState(item, false)

        -- Emit lantern broken event
        self.eventBus:emit(events.EVENTS.LANTERN_BROKEN, {
            entity = entity,
            item   = item,
            reason = reason,
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

            self.eventBus:emit(events.EVENTS.PARTY_LIGHT_CHANGED, {
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
            self.eventBus:emit(events.EVENTS.DARKNESS_FELL, {
                affectedCount = darkCount,
            })
            if not self:guildHasRecoverableLightSource() then
                self:resolveOutOfLightDoom()
            end
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
            self.eventBus:emit(events.EVENTS.DARKNESS_LIFTED, {
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
        self:setItemLitState(item, true)

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
        self:setItemLitState(lantern, true)

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
