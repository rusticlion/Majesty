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
local disposition = require('logic.disposition')
local mob_blueprints = require('data.blueprints.mobs')

local M = {}

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, child in pairs(value) do
        copy[key] = deepCopy(child)
    end
    return copy
end

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
        local templateId = template.templateId or template.itemTemplate
        local item

        if templateId then
            local overrides = {}
            for key, value in pairs(template) do
                if key ~= "templateId" and key ~= "itemTemplate" then
                    overrides[key] = deepCopy(value)
                end
            end
            item = inventory.createItemFromTemplate(templateId, next(overrides) and overrides or nil)
        else
            item = inventory.createItem({
                name       = template.name,
                size       = template.size or inventory.SIZE.NORMAL,
                durability = template.durability or inventory.DURABILITY.NORMAL,
                oversized  = template.oversized or false,
                stackable  = template.stackable or false,
                stackSize  = template.stackSize or 1,
                quantity   = template.quantity or 1,
                isArmor    = template.isArmor or false,
                weaponType = template.weaponType,
                isWeapon   = template.isWeapon,
                isMelee    = template.isMelee,
                isRanged   = template.isRanged,
                uses_ammo  = template.uses_ammo,
                isLoaded   = template.isLoaded,
                keyId      = template.keyId,
                type       = template.type,
                isRation   = template.isRation,
                properties = deepCopy(template.properties or {}),
            })
        end

        if item then
            items[#items + 1] = item
        end
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
    local startingDisposition = overrides.disposition or blueprint.disposition
    local startingDispositionSeverity = overrides.dispositionSeverity or overrides.disposition_severity or
        blueprint.dispositionSeverity or blueprint.disposition_severity

    if not startingDisposition then
        local discardCard = overrides.minorDiscardCard or overrides.dispositionCard or overrides.startingDispositionCard
        local minorDeck = overrides.minorDeck or overrides.playerDeck
        if not discardCard and minorDeck and minorDeck.peekDiscard then
            discardCard = minorDeck:peekDiscard()
        end

        if discardCard then
            local randomDisposition, randomSeverity = disposition.dispositionFromMinorDiscard(discardCard)
            startingDisposition = randomDisposition
            startingDispositionSeverity = randomSeverity
        end
    end

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
        disposition      = startingDisposition or "distaste",  -- S12.4: Disposition
        dispositionSeverity = startingDispositionSeverity,
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
    entity.enemyType = blueprint.enemyType or template_id
    entity.rank = overrides.rank or blueprint.rank
    entity.size = overrides.size or blueprint.size
    entity.tags = deepCopy(blueprint.tags)
    entity.undead = overrides.undead ~= nil and overrides.undead or blueprint.undead
    entity.construct = overrides.construct ~= nil and overrides.construct or blueprint.construct
    entity.automaton = overrides.automaton ~= nil and overrides.automaton or blueprint.automaton
    entity.aiTags = deepCopy(blueprint.aiTags)
    entity.lesserDooms = deepCopy(blueprint.lesserDooms)
    entity.greaterDooms = deepCopy(blueprint.greaterDooms)
    entity.greaterDoom = deepCopy(blueprint.greaterDoom)
    entity.social = deepCopy(blueprint.social)
    entity.alchemy = deepCopy(blueprint.alchemy)
    entity.notes = deepCopy(blueprint.notes)
    entity.zombie = deepCopy(blueprint.zombie)
    entity.mimic = deepCopy(blueprint.mimic)
    entity.nymph = deepCopy(blueprint.nymph)
    entity.ogre = deepCopy(blueprint.ogre)
    entity.questingBeast = deepCopy(blueprint.questingBeast)
    entity.skeleton = deepCopy(blueprint.skeleton)
    entity.slime = deepCopy(blueprint.slime)
    entity.titan = deepCopy(blueprint.titan)
    entity.ungoat = deepCopy(blueprint.ungoat)
    entity.vampire = deepCopy(blueprint.vampire)
    entity.wraith = deepCopy(blueprint.wraith)
    entity.winterWolf = deepCopy(blueprint.winterWolf)

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

function M.createUndeadFromAdventurer(adventurer, undeadType, overrides)
    overrides = overrides or {}
    undeadType = undeadType or "zombie"

    local name = overrides.name
    if not name then
        local sourceName = adventurer and adventurer.name or "Adventurer"
        name = sourceName .. " Zombie"
    end

    local undead, err = M.createEntity(undeadType, {
        name = name,
        location = overrides.location or (adventurer and adventurer.location),
        rank = overrides.rank,
    })
    if not undead then
        return nil, err
    end

    undead.id = overrides.id or ((adventurer and adventurer.id or "adventurer") .. "_" .. undeadType)
    undead.zone = overrides.zone or (adventurer and adventurer.zone) or undead.zone
    undead.sourceAdventurerId = adventurer and adventurer.id or nil
    undead.sourceAdventurerName = adventurer and adventurer.name or nil
    undead.raisedFromDeadAdventurer = true

    return undead
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
        id               = pc_data.id,
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
        kin              = pc_data.kin or pc_data.kith or pc_data.species or pc_data.race or pc_data.ancestry,
        kith             = pc_data.kith,
        species          = pc_data.species,
        race             = pc_data.race,
        ancestry         = pc_data.ancestry,
    })

    pc.path = pc_data.path or pc_data.pathName or pc_data.role or pc_data.class or pc_data.suit
    pc.pathName = pc_data.pathName

    pc.ammo = pc_data.ammo or pc.ammo

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
