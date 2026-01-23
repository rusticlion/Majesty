-- factory.lua
-- Entity Factory (The Spawner) for Majesty
-- Ticket T1_8: Centralized factory using data-driven blueprints
--
-- Design: Data-driven, not code-driven.
-- Add new monsters by editing blueprints, not by writing new functions.

--------------------------------------------------------------------------------
-- DEPENDENCIES
--------------------------------------------------------------------------------
local base_entity = require('entities.base_entity')
local adventurer_module = require('entities.adventurer')
local inventory = require('logic.inventory')
local mob_blueprints = require('data.blueprints.mobs')

local M = {}

--------------------------------------------------------------------------------
-- BLUEPRINT REGISTRY
-- Combine all blueprint sources into one lookup table
--------------------------------------------------------------------------------
local blueprints = {}

-- Load mob blueprints
for id, blueprint in pairs(mob_blueprints.blueprints) do
    blueprints[id] = blueprint
end

--- Register additional blueprints (for expansion packs, custom content)
function M.registerBlueprint(id, blueprint)
    blueprints[id] = blueprint
end

--- Check if a blueprint exists
function M.hasBlueprint(id)
    return blueprints[id] ~= nil
end

--- List all available blueprint IDs
function M.listBlueprints()
    local ids = {}
    for id, _ in pairs(blueprints) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end

--------------------------------------------------------------------------------
-- ITEM INSTANTIATION
-- Create actual item instances from gear templates
--------------------------------------------------------------------------------
local function instantiateGear(gearList)
    local items = {}
    for _, template in ipairs(gearList or {}) do
        local item = inventory.createItem({
            name       = template.name,
            size       = template.size or inventory.SIZE.NORMAL,
            durability = template.durability or inventory.DURABILITY.NORMAL,
            oversized  = template.oversized or false,
            stackable  = template.stackable or false,
            stackSize  = template.stackSize or 1,
            quantity   = template.quantity or 1,
            isArmor    = template.isArmor or false,
            properties = template.properties or {},
        })
        items[#items + 1] = item
    end
    return items
end

--------------------------------------------------------------------------------
-- CREATE ENTITY (NPCs / Mobs)
-- Data-driven: looks up template_id in blueprints table
--------------------------------------------------------------------------------

--- Create an NPC entity from a blueprint
-- @param template_id string: Blueprint ID (e.g., "skeleton_brute")
-- @param overrides table: Optional overrides for specific properties
-- @return Entity with inventory and starting gear, or nil if blueprint not found
function M.createEntity(template_id, overrides)
    local blueprint = blueprints[template_id]
    if not blueprint then
        return nil, "blueprint_not_found"
    end

    overrides = overrides or {}

    -- Create base entity
    local entity = base_entity.createEntity({
        name             = overrides.name or blueprint.name,
        swords           = blueprint.attributes.swords,
        pentacles        = blueprint.attributes.pentacles,
        cups             = blueprint.attributes.cups,
        wands            = blueprint.attributes.wands,
        armorSlots       = blueprint.armorSlots or 0,
        talentWoundSlots = blueprint.talentWoundSlots or 0,
        baseMorale       = blueprint.baseMorale or 14,  -- S12.3: Morale system
        disposition      = overrides.disposition or blueprint.disposition or "distaste",  -- S12.4: Disposition
        location         = overrides.location or nil,

        -- NPC Health/Defense system (p. 125)
        -- Health = durability before Death's Door
        -- Defense = protection absorbed first (like armor, scales, hide)
        health           = blueprint.health or blueprint.npcHealth or 3,
        defense          = blueprint.defense or blueprint.npcDefense or blueprint.armorSlots or 0,
        instantDestruction = blueprint.instantDestruction or false,  -- Undead/constructs skip Death's Door

        isPC = false,
    })

    -- Mark as NPC
    entity.isPC = false
    entity.blueprintId = template_id

    -- Attach inventory
    entity.inventory = inventory.createInventory()

    -- Instantiate and place starting gear
    local gear = blueprint.starting_gear or {}

    -- Hands
    if gear.hands then
        local handItems = instantiateGear(gear.hands)
        for _, item in ipairs(handItems) do
            entity.inventory:addItem(item, "hands")
        end
    end

    -- Belt
    if gear.belt then
        local beltItems = instantiateGear(gear.belt)
        for _, item in ipairs(beltItems) do
            entity.inventory:addItem(item, "belt")
        end
    end

    -- Pack
    if gear.pack then
        local packItems = instantiateGear(gear.pack)
        for _, item in ipairs(packItems) do
            entity.inventory:addItem(item, "pack")
        end
    end

    return entity
end

--------------------------------------------------------------------------------
-- CREATE ADVENTURER (PCs)
-- Specialized version with Resolve, Bonds, Motifs, Talents
--------------------------------------------------------------------------------

--- Create a player character adventurer
-- @param pc_data table: Character data from session 0 / character creation
-- @return Adventurer with inventory and starting gear
function M.createAdventurer(pc_data)
    pc_data = pc_data or {}

    -- Create adventurer (extends base entity)
    local pc = adventurer_module.createAdventurer({
        name             = pc_data.name or "Unnamed Adventurer",
        swords           = pc_data.swords or pc_data.attributes and pc_data.attributes.swords or 2,
        pentacles        = pc_data.pentacles or pc_data.attributes and pc_data.attributes.pentacles or 2,
        cups             = pc_data.cups or pc_data.attributes and pc_data.attributes.cups or 2,
        wands            = pc_data.wands or pc_data.attributes and pc_data.attributes.wands or 2,
        armorSlots       = pc_data.armorSlots or 0,
        talentWoundSlots = pc_data.talentWoundSlots or 2,
        resolve          = pc_data.resolve or 4,
        resolveMax       = pc_data.resolveMax or 4,
        motifs           = pc_data.motifs or {},
        bonds            = pc_data.bonds or {},
        talents          = pc_data.talents or {},
        location         = pc_data.location or nil,
    })

    -- Attach inventory
    pc.inventory = inventory.createInventory()

    -- Add starting gear if provided
    local gear = pc_data.starting_gear or {}

    if gear.hands then
        local handItems = instantiateGear(gear.hands)
        for _, item in ipairs(handItems) do
            pc.inventory:addItem(item, "hands")
        end
    end

    if gear.belt then
        local beltItems = instantiateGear(gear.belt)
        for _, item in ipairs(beltItems) do
            pc.inventory:addItem(item, "belt")
        end
    end

    if gear.pack then
        local packItems = instantiateGear(gear.pack)
        for _, item in ipairs(packItems) do
            pc.inventory:addItem(item, "pack")
        end
    end

    return pc
end

--------------------------------------------------------------------------------
-- QUICK SPAWN HELPERS
--------------------------------------------------------------------------------

--- Spawn multiple entities of the same type
-- @param template_id string: Blueprint ID
-- @param count number: How many to spawn
-- @return table: Array of entities
function M.spawnGroup(template_id, count)
    local group = {}
    for i = 1, count do
        local entity, err = M.createEntity(template_id)
        if entity then
            group[#group + 1] = entity
        end
    end
    return group
end

return M
