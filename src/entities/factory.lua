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
local talent_catalog = require('data.talent_catalog')
local language_catalog = require('data.language_catalog')
local motif_catalog = require('data.motif_catalog')
local constants = require('constants')

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

local blueprintFactoryFields = {
    attributes = true,
    starting_gear = true,
    tags = true,
    aiTags = true,
    lesserDooms = true,
    greaterDooms = true,
    greaterDoom = true,
    social = true,
    alchemy = true,
    notes = true,
}

local function copyCreatureMetadata(entity, blueprint)
    for key, value in pairs(blueprint or {}) do
        if type(value) == "table" and not blueprintFactoryFields[key] then
            entity[key] = deepCopy(value)
        end
    end
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
        local minorDeck = overrides.minorDeck or overrides.playerDeck
        local discardCard = nil
        if minorDeck and minorDeck.peekDiscard then
            discardCard = minorDeck:peekDiscard()
        end
        discardCard = discardCard or overrides.minorDiscardCard or overrides.dispositionCard or
            overrides.startingDispositionCard

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
        infiniteHealth   = blueprint.infiniteHealth or false,
        neverTakesWounds = blueprint.neverTakesWounds or false,

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
    copyCreatureMetadata(entity, blueprint)

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

local CALL_TO_ADVENTURE_ATTRIBUTES = { "swords", "pentacles", "cups", "wands" }

local function trimText(value)
    if value == nil then
        return nil
    end
    local text = tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return nil
    end
    return text
end

local function normalizeAttributeName(value)
    local normalized = talent_catalog.normalizePath(value)
    if normalized == "sword" then
        normalized = "swords"
    elseif normalized == "pentacle" then
        normalized = "pentacles"
    elseif normalized == "cup" then
        normalized = "cups"
    elseif normalized == "wand" then
        normalized = "wands"
    end

    for _, attribute in ipairs(CALL_TO_ADVENTURE_ATTRIBUTES) do
        if normalized == attribute then
            return attribute
        end
    end
    return nil
end

local function listFromValues(...)
    local values = {}
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if type(value) == "table" then
            for _, entry in ipairs(value) do
                local text = trimText(entry)
                if text then
                    values[#values + 1] = text
                end
            end
        else
            local text = trimText(value)
            if text then
                values[#values + 1] = text
            end
        end
    end
    return values
end

local function attributeInputValue(config, attribute)
    if config[attribute] ~= nil then
        return config[attribute]
    end
    local attributes = config.attributes or {}
    return attributes[attribute]
end

local function validateCallAttributes(attributes, path)
    local counts = {}
    for _, attribute in ipairs(CALL_TO_ADVENTURE_ATTRIBUTES) do
        local value = tonumber(attributes[attribute])
        if value ~= math.floor(value or 0) or value < 1 or value > 4 then
            return false, "Call to Adventure attributes must be 1, 2, 3, and 4"
        end
        counts[value] = (counts[value] or 0) + 1
    end
    for value = 1, 4 do
        if counts[value] ~= 1 then
            return false, "Call to Adventure attributes must be 1, 2, 3, and 4"
        end
    end

    local pathAttribute = normalizeAttributeName(path)
    if not pathAttribute or attributes[pathAttribute] ~= 4 then
        return false, "Path attribute must be rated 4"
    end
    return true
end

local function setCallAttribute(attributes, attributeName, value)
    local attribute = normalizeAttributeName(attributeName)
    if not attribute then
        return false, "Unknown attribute"
    end
    if attributes[attribute] and attributes[attribute] ~= value then
        return false, "Call to Adventure attributes must be distinct"
    end
    attributes[attribute] = value
    return true
end

local function callToAdventureAttributes(config, path)
    local explicitAttributes = false
    local attributes = {}
    for _, attribute in ipairs(CALL_TO_ADVENTURE_ATTRIBUTES) do
        local value = attributeInputValue(config, attribute)
        if value ~= nil then
            explicitAttributes = true
            attributes[attribute] = math.floor(tonumber(value) or 0)
        end
    end

    if explicitAttributes then
        local valid, reason = validateCallAttributes(attributes, path)
        if not valid then
            return nil, reason
        end
        return attributes
    end

    local pathAttribute = normalizeAttributeName(path)
    if not pathAttribute then
        return nil, "Path required"
    end

    local ok, reason = setCallAttribute(attributes, pathAttribute, 4)
    if not ok then
        return nil, reason
    end
    ok, reason = setCallAttribute(attributes,
        config.fittingInAttribute or config.originAttribute or config.youthAttribute, 1)
    if not ok then
        return nil, reason
    end
    ok, reason = setCallAttribute(attributes, config.failedCareerAttribute or config.careerAttribute, 2)
    if not ok then
        return nil, reason
    end
    ok, reason = setCallAttribute(attributes,
        config.firstAdventureAttribute or config.fullBlownWeirdoAttribute or config.underworldAttribute, 3)
    if not ok then
        return nil, reason
    end

    local valid, validateReason = validateCallAttributes(attributes, path)
    if not valid then
        return nil, validateReason
    end
    return attributes
end

local function hasTalentId(talents, talentId)
    local wanted = talent_catalog.normalizeId(talentId)
    for _, candidate in ipairs(talents or {}) do
        if talent_catalog.normalizeId(candidate) == wanted then
            return true
        end
    end
    return false
end

local function attributeSuit(attribute)
    if attribute == "swords" then
        return constants.SUITS.SWORDS
    elseif attribute == "pentacles" then
        return constants.SUITS.PENTACLES
    elseif attribute == "cups" then
        return constants.SUITS.CUPS
    elseif attribute == "wands" then
        return constants.SUITS.WANDS
    end
    return nil
end

local function unresolvedUltraFastAttributes(path)
    local unresolved = {}
    local pathAttribute = normalizeAttributeName(path)
    for _, attribute in ipairs(CALL_TO_ADVENTURE_ATTRIBUTES) do
        if attribute ~= pathAttribute then
            unresolved[#unresolved + 1] = attribute
        end
    end
    return unresolved
end

local function removeValue(list, value)
    for i = #(list or {}), 1, -1 do
        if list[i] == value then
            table.remove(list, i)
        end
    end
end

local function listContains(list, value)
    for _, item in ipairs(list or {}) do
        if item == value then
            return true
        end
    end
    return false
end

local function ultraFastAssignedAttributeValues(actor, exceptAttribute)
    local values = {}
    for _, attribute in ipairs(CALL_TO_ADVENTURE_ATTRIBUTES) do
        if attribute ~= exceptAttribute then
            local value = tonumber(actor and actor[attribute])
            if value then
                values[value] = true
            end
        end
    end
    return values
end

local function recordUltraFastChoice(actor, record)
    if type(actor) ~= "table" then
        return
    end
    actor.ultraFastCreation = actor.ultraFastCreation or {}
    actor.ultraFastCreation.resolvedQuestions = actor.ultraFastCreation.resolvedQuestions or {}
    actor.ultraFastCreation.resolvedQuestions[#actor.ultraFastCreation.resolvedQuestions + 1] = record
end

local function actorId(actor)
    if type(actor) ~= "table" then
        return nil
    end
    return actor.id or actor.name
end

local function keyedConfigValue(source, actor, index, ...)
    if type(source) ~= "table" then
        return nil
    end

    local id = actorId(actor)
    if id and source[id] ~= nil then
        return source[id]
    end
    if actor and actor.name and source[actor.name] ~= nil then
        return source[actor.name]
    end
    if source[index] ~= nil then
        return source[index]
    end

    for i = 1, select("#", ...) do
        local key = select(i, ...)
        if key and source[key] ~= nil then
            return source[key]
        end
    end
    return nil
end

local ORDINAL_MARCHING_ORDER = {
    first = 1,
    second = 2,
    third = 3,
    fourth = 4,
    fifth = 5,
    sixth = 6,
    seventh = 7,
    eighth = 8,
    ninth = 9,
    tenth = 10,
}

local function parseMarchingOrder(value, memberCount)
    if value == nil then
        return nil
    end

    local number = tonumber(value)
    if number then
        return math.floor(number)
    end

    local normalized = talent_catalog.normalizeId(value)
    if normalized == "last" then
        return memberCount
    end
    if ORDINAL_MARCHING_ORDER[normalized] then
        return ORDINAL_MARCHING_ORDER[normalized]
    end

    local numericPrefix = normalized:match("^(%d+)")
    if numericPrefix then
        return tonumber(numericPrefix)
    end
    return nil
end

local function bondStatusFromConfig(bonds, sourceId, targetId)
    if type(bonds) ~= "table" or not sourceId or not targetId then
        return nil
    end

    local direct = bonds[sourceId]
    if type(direct) == "table" and direct[targetId] ~= nil then
        if type(direct[targetId]) == "table" then
            return direct[targetId].status or direct[targetId].bond or direct[targetId].relationship
        end
        return direct[targetId]
    end

    local paired = bonds[sourceId .. ":" .. targetId] or bonds[sourceId .. "->" .. targetId]
    if paired ~= nil then
        if type(paired) == "table" then
            return paired.status or paired.bond or paired.relationship
        end
        return paired
    end

    for _, entry in ipairs(bonds) do
        if type(entry) == "table" and (entry.from or entry.source or entry.actorId) == sourceId and
            (entry.to or entry.target or entry.targetId) == targetId then
            return entry.status or entry.bond or entry.relationship
        end
    end
    return nil
end

local function setActorBond(source, target, status)
    if not source or not target or not status then
        return false, nil
    end
    local targetId = actorId(target)
    if not targetId then
        return false, nil
    end
    if source.setBond then
        source:setBond(targetId, status)
    else
        source.bonds = source.bonds or {}
        source.bonds[targetId] = source.bonds[targetId] or {}
        source.bonds[targetId].status = status
        source.bonds[targetId].charged = source.bonds[targetId].charged or false
    end
    local info = adventurer_module.applyBondMetadata(source.bonds and source.bonds[targetId], status)
    return true, info
end

local function actorHasBond(source, target)
    local targetId = actorId(target)
    return source and targetId and source.bonds and source.bonds[targetId] ~= nil
end

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

--- Create an adventurer through the rulebook Call to Adventure checklist.
-- This is opt-in so existing authored quick-start PCs can keep bespoke values.
function M.createCallToAdventureAdventurer(config)
    config = config or {}
    local name = trimText(config.name)
    if not name then
        return nil, "Name required"
    end

    local path = talent_catalog.normalizePath(config.path or config.pathName or config.role or config.class or config.suit)
    if path == "" or not normalizeAttributeName(path) then
        return nil, "Path required"
    end

    local attributes, attributeReason = callToAdventureAttributes(config, path)
    if not attributes then
        return nil, attributeReason
    end

    if config.resolve ~= nil and tonumber(config.resolve) ~= 4 then
        return nil, "Call to Adventure Resolve must be 4"
    end
    if config.resolveMax ~= nil and tonumber(config.resolveMax) ~= 4 then
        return nil, "Call to Adventure Resolve must be 4"
    end

    local kin = talent_catalog.normalizeKin(config.kin or config.kinName or config.species or
        config.race or config.ancestry)
    if kin == "" then
        return nil, "Kin required"
    end
    local kithOk, kithReason, kithDetail = talent_catalog.validateKithKin(kin,
        config.kith or config.kithName or config.people)
    if not kithOk then
        return nil, kithReason
    end
    local kith = kithDetail.kith

    local kinTalent = talent_catalog.normalizeId(config.kinTalent or config.defaultKinTalent or
        talent_catalog.getDefaultKinTalent(kin, kith))
    local kinTalentInfo = talent_catalog.getTalentInfo(kinTalent)
    if not kinTalentInfo or kinTalentInfo.kind ~= "kin" then
        return nil, "Kin talent required"
    end
    if kinTalentInfo.kin ~= kin or kinTalentInfo.kith ~= kith then
        return nil, "Kin talent must match kin"
    end

    local pathTalents = talent_catalog.getCreationPathTalents(path)
    if #pathTalents ~= 7 then
        return nil, "Path should provide seven creation talents"
    end

    local masteredPathTalent = talent_catalog.normalizeId(config.masteredPathTalent or
        config.masteredTalent or config.pathTalent)
    if masteredPathTalent == "" then
        return nil, "Mastered path talent required"
    end
    if not hasTalentId(pathTalents, masteredPathTalent) then
        local masteredInfo = talent_catalog.getTalentInfo(masteredPathTalent)
        if path == "swords" and masteredInfo and masteredInfo.path == "swords" and
            masteredPathTalent:find("_hunter", 1, true) then
            masteredPathTalent = "monster_hunter"
        else
            return nil, "Mastered path talent must belong to the chosen path"
        end
    end

    local motifs = listFromValues(config.motifs, config.originMotif, config.failedCareerMotif,
        config.firstAdventureMotif or config.underworldMotif)
    local motifOk, motifReason, motifDetail = motif_catalog.validateMotifs(motifs, {
        requireStructured = config.requireStructuredMotifs == true,
        strictSamples = config.strictRulebookMotifs == true,
    })
    if not motifOk then
        return nil, motifReason
    end

    local quest = trimText(config.quest or config.currentQuest or config.objective)
    if not quest then
        return nil, "Quest required"
    end

    local appearance = trimText(config.appearance or config.looks or config.description)
    if not appearance then
        return nil, "Appearance required"
    end

    local languages = listFromValues(config.languages)
    local languageInfo = {}
    if config.languages then
        local languageOk, languageReason, languageDetail = language_catalog.validateStartingLanguages(languages)
        if not languageOk then
            return nil, languageReason
        end
        languages = languageDetail.languages
        languageInfo = languageDetail.languageInfo
    end

    local talents = deepCopy(config.talents or {})
    talents[kinTalent] = talents[kinTalent] or {}
    talents[kinTalent].mastered = true
    talents[kinTalent].wounded = talents[kinTalent].wounded or false
    talents[kinTalent].xp_invested = talents[kinTalent].xp_invested or 0
    talents[kinTalent].trainingKind = talents[kinTalent].trainingKind or "kin"
    talents[kinTalent].kin = kin
    talents[kinTalent].kith = kith

    for _, talentId in ipairs(pathTalents) do
        local talent = talents[talentId]
        if type(talent) ~= "table" then
            talent = {}
        end
        talent.mastered = talent_catalog.normalizeId(talentId) == masteredPathTalent
        talent.wounded = talent.wounded or false
        talent.xp_invested = talent.xp_invested or 0
        talent.trainingKind = talent.trainingKind or "path"
        talent.path = path
        talents[talentId] = talent
    end

    local pcData = deepCopy(config)
    pcData.name = name
    pcData.swords = attributes.swords
    pcData.pentacles = attributes.pentacles
    pcData.cups = attributes.cups
    pcData.wands = attributes.wands
    pcData.path = path
    pcData.pathName = config.pathName or path
    pcData.kin = kin
    pcData.kith = kith
    pcData.motifs = motifs
    pcData.motifInfo = motifDetail.motifInfo
    pcData.talents = talents
    pcData.resolve = 4
    pcData.resolveMax = 4
    pcData.quest = quest
    pcData.currentQuest = quest
    pcData.appearance = appearance
    pcData.languages = languages
    pcData.knownLanguages = languages
    pcData.languageInfo = languageInfo

    local pc = M.createAdventurer(pcData)
    local arete = talent_catalog.getAreteSetup(kin, kith)
    if arete then
        pc.arete = arete
        pc.areteTriggers = arete.triggers
        pc.areteTalentId = arete.talentId
    end
    pc.quest = quest
    pc.currentQuest = quest
    pc.appearance = appearance
    pc.kith = kith
    pc.languages = languages
    pc.knownLanguages = languages
    pc.languageInfo = languageInfo
    pc.motifInfo = motifDetail.motifInfo
    pc.callToAdventure = {
        attributes = attributes,
        path = path,
        kin = kin,
        kith = kith,
        kinTalent = kinTalent,
        pathTalents = pathTalents,
        masteredPathTalent = masteredPathTalent,
        motifs = motifs,
        motifInfo = motifDetail.motifInfo,
        quest = quest,
        appearance = appearance,
        languages = languages,
        knownLanguages = languages,
        languageInfo = languageInfo,
        arete = arete,
        originStory = config.originStory,
        fittingInStory = config.fittingInStory,
        failedCareer = config.failedCareer,
        failedCareerStory = config.failedCareerStory,
        firstAdventure = config.firstAdventure,
    }

    return pc, "call_to_adventure_created", pc.callToAdventure
end

--- Create a mid-session replacement adventurer using the rulebook ultra-fast shortcut.
-- Only path, kith/kin, kin talent, one path talent, and name are fixed up front.
function M.createUltraFastAdventurer(config)
    config = config or {}
    local name = trimText(config.name)
    if not name then
        return nil, "Name required"
    end

    local path = talent_catalog.normalizePath(config.path or config.pathName or config.role or config.class or config.suit)
    if path == "" or not normalizeAttributeName(path) then
        return nil, "Path required"
    end

    local kin = talent_catalog.normalizeKin(config.kin or config.kinName or config.species or
        config.race or config.ancestry)
    if kin == "" then
        return nil, "Kin required"
    end
    local kithOk, kithReason, kithDetail = talent_catalog.validateKithKin(kin,
        config.kith or config.kithName or config.people)
    if not kithOk then
        return nil, kithReason
    end
    local kith = kithDetail.kith

    local kinTalent = talent_catalog.normalizeId(config.kinTalent or config.defaultKinTalent or
        talent_catalog.getDefaultKinTalent(kin, kith))
    local kinTalentInfo = talent_catalog.getTalentInfo(kinTalent)
    if not kinTalentInfo or kinTalentInfo.kind ~= "kin" then
        return nil, "Kin talent required"
    end
    if kinTalentInfo.kin ~= kin or kinTalentInfo.kith ~= kith then
        return nil, "Kin talent must match kin"
    end

    local pathTalents = talent_catalog.getCreationPathTalents(path)
    if #pathTalents ~= 7 then
        return nil, "Path should provide seven creation talents"
    end

    local masteredPathTalent = talent_catalog.normalizeId(config.masteredPathTalent or
        config.masteredTalent or config.pathTalent)
    if masteredPathTalent == "" then
        return nil, "Mastered path talent required"
    end
    if not hasTalentId(pathTalents, masteredPathTalent) then
        local masteredInfo = talent_catalog.getTalentInfo(masteredPathTalent)
        if path == "swords" and masteredInfo and masteredInfo.path == "swords" and
            masteredPathTalent:find("_hunter", 1, true) then
            masteredPathTalent = "monster_hunter"
        else
            return nil, "Mastered path talent must belong to the chosen path"
        end
    end

    local pathAttribute = normalizeAttributeName(path)

    local talents = {}
    talents[kinTalent] = talents[kinTalent] or {}
    talents[kinTalent].mastered = true
    talents[kinTalent].wounded = talents[kinTalent].wounded or false
    talents[kinTalent].xp_invested = talents[kinTalent].xp_invested or 0
    talents[kinTalent].trainingKind = talents[kinTalent].trainingKind or "kin"
    talents[kinTalent].kin = kin
    talents[kinTalent].kith = kith

    talents[masteredPathTalent] = talents[masteredPathTalent] or {}
    talents[masteredPathTalent].mastered = true
    talents[masteredPathTalent].wounded = talents[masteredPathTalent].wounded or false
    talents[masteredPathTalent].xp_invested = talents[masteredPathTalent].xp_invested or 0
    talents[masteredPathTalent].trainingKind = talents[masteredPathTalent].trainingKind or "path"
    talents[masteredPathTalent].path = path

    local pcData = {
        id = config.id,
        name = name,
        path = path,
        pathName = config.pathName or path,
        kin = kin,
        kith = kith,
        talents = talents,
        resolve = 4,
        resolveMax = 4,
        location = config.location,
        zone = config.zone,
    }
    pcData[pathAttribute] = 4

    local pc = M.createAdventurer(pcData)
    for _, attribute in ipairs(CALL_TO_ADVENTURE_ATTRIBUTES) do
        if attribute ~= pathAttribute then
            pc[attribute] = nil
            pc.attributes[attributeSuit(attribute)] = nil
        end
    end

    local arete = talent_catalog.getAreteSetup(kin, kith)
    if arete then
        pc.arete = arete
        pc.areteTriggers = arete.triggers
        pc.areteTalentId = arete.talentId
    end

    pc.path = path
    pc.pathName = config.pathName or path
    pc.kin = kin
    pc.kith = kith
    pc.motifs = {}
    pc.languages = {}
    pc.knownLanguages = {}
    pc.callToAdventurePending = true
    pc.ultraFastCreation = {
        enabled = true,
        midSession = true,
        reason = config.reason or "mid_session_death_replacement",
        path = path,
        kin = kin,
        kith = kith,
        kinTalent = kinTalent,
        pathTalents = pathTalents,
        masteredPathTalent = masteredPathTalent,
        pathAttribute = pathAttribute,
        unresolvedAttributes = unresolvedUltraFastAttributes(path),
        unresolvedFields = {
            "motifs",
            "quest",
            "appearance",
            "languages",
            "gear",
        },
        heisenbergSheet = true,
        needsFleshingOutAfterSession = true,
        resolvedQuestions = {},
    }

    return pc, "ultra_fast_adventurer_created", pc.ultraFastCreation
end

function M.resolveUltraFastSheetQuestion(actor, opts)
    opts = opts or {}
    if type(actor) ~= "table" or not actor.ultraFastCreation then
        return false, "Ultra-fast adventurer required"
    end

    local field = talent_catalog.normalizeId(opts.field or opts.question or opts.type)
    if field == "attribute" or field == "score" then
        local attribute = normalizeAttributeName(opts.attribute or opts.name)
        if not attribute then
            return false, "Attribute required"
        end
        if attribute == actor.ultraFastCreation.pathAttribute then
            return false, "Path attribute already fixed"
        end
        if not listContains(actor.ultraFastCreation.unresolvedAttributes, attribute) then
            return false, "Ultra-fast attribute already resolved"
        end
        local value = tonumber(opts.value or opts.score)
        if not value or value ~= math.floor(value) or value < 1 or value > 3 then
            return false, "Ultra-fast attribute must be 1, 2, or 3"
        end
        if ultraFastAssignedAttributeValues(actor, attribute)[value] then
            return false, "Ultra-fast attributes must stay distinct"
        end
        actor[attribute] = value
        actor.attributes[attributeSuit(attribute)] = value
        removeValue(actor.ultraFastCreation.unresolvedAttributes, attribute)
        local record = {
            field = "attribute",
            attribute = attribute,
            value = value,
            result = "ultra_fast_question_resolved",
        }
        recordUltraFastChoice(actor, record)
        return true, "ultra_fast_question_resolved", record
    elseif field == "gear" or field == "item" or field == "equipment" then
        local item = opts.item or opts.itemId or opts.templateId or opts.name
        if not item then
            return false, "Item required"
        end
        actor.ultraFastGearAnswers = actor.ultraFastGearAnswers or {}
        local record = {
            field = "gear",
            item = item,
            hasItem = opts.hasItem ~= false and opts.answer ~= false,
            result = "ultra_fast_question_resolved",
        }
        actor.ultraFastGearAnswers[#actor.ultraFastGearAnswers + 1] = record
        recordUltraFastChoice(actor, record)
        return true, "ultra_fast_question_resolved", record
    elseif field == "motif" or field == "motifs" then
        actor.motifs = listFromValues(opts.motifs or opts.value)
        local motifOk, motifReason, motifDetail = motif_catalog.validateMotifs(actor.motifs, {
            requireStructured = opts.requireStructuredMotifs == true,
            strictSamples = opts.strictRulebookMotifs == true,
        })
        if not motifOk then
            return false, motifReason
        end
        actor.motifInfo = motifDetail.motifInfo
        removeValue(actor.ultraFastCreation.unresolvedFields, "motifs")
        local record = {
            field = "motifs",
            motifs = actor.motifs,
            motifInfo = actor.motifInfo,
            result = "ultra_fast_question_resolved",
        }
        recordUltraFastChoice(actor, record)
        return true, "ultra_fast_question_resolved", record
    elseif field == "quest" then
        actor.quest = trimText(opts.quest or opts.value or opts.objective)
        if not actor.quest then
            return false, "Quest required"
        end
        actor.currentQuest = actor.quest
        removeValue(actor.ultraFastCreation.unresolvedFields, "quest")
        local record = {
            field = "quest",
            quest = actor.quest,
            result = "ultra_fast_question_resolved",
        }
        recordUltraFastChoice(actor, record)
        return true, "ultra_fast_question_resolved", record
    elseif field == "appearance" or field == "looks" then
        actor.appearance = trimText(opts.appearance or opts.value or opts.description)
        if not actor.appearance then
            return false, "Appearance required"
        end
        removeValue(actor.ultraFastCreation.unresolvedFields, "appearance")
        local record = {
            field = "appearance",
            appearance = actor.appearance,
            result = "ultra_fast_question_resolved",
        }
        recordUltraFastChoice(actor, record)
        return true, "ultra_fast_question_resolved", record
    elseif field == "language" or field == "languages" then
        local languages = listFromValues(opts.languages or opts.value)
        local ok, reason, detail = language_catalog.validateStartingLanguages(languages)
        if not ok then
            return false, reason
        end
        actor.languages = detail.languages
        actor.knownLanguages = detail.languages
        actor.languageInfo = detail.languageInfo
        removeValue(actor.ultraFastCreation.unresolvedFields, "languages")
        local record = {
            field = "languages",
            languages = actor.languages,
            languageInfo = actor.languageInfo,
            result = "ultra_fast_question_resolved",
        }
        recordUltraFastChoice(actor, record)
        return true, "ultra_fast_question_resolved", record
    end

    return false, "Unsupported ultra-fast question"
end

--- Create the rulebook guild roster from session-0 bonding choices.
function M.createCallToAdventureGuild(config)
    config = config or {}
    local members = config.adventurers or config.members or config.guild or {}
    if #members == 0 then
        return nil, "Guild members required"
    end

    local guildName = trimText(config.name or config.guildName)
    if not guildName then
        return nil, "Guild name required"
    end

    local sigil = trimText(config.sigil or config.heraldry or config.symbol)
    if not sigil then
        return nil, "Guild sigil required"
    end

    local terms = trimText(config.terms or config.lootingRights or config.contractTerms) or
        "Equal shares; funeral expenses paid by the guild."
    local roster = {
        name = guildName,
        guildName = guildName,
        sigil = sigil,
        terms = terms,
        lootingRights = terms,
        adventurers = members,
        members = members,
        entries = {},
        marchingOrder = {},
        roles = {},
    }

    local usedMarchingOrder = {}
    for index, actor in ipairs(members) do
        local id = actorId(actor)
        if not id then
            return nil, "Guild member id required"
        end

        local role = trimText(keyedConfigValue(config.roles or config.guildRoles, actor, index, "role") or
            actor.guildRole or actor.role)
        if config.requireComplete ~= false and not role then
            return nil, "Guild role required"
        end

        local marchingOrder = parseMarchingOrder(keyedConfigValue(config.marchingOrder or config.marchingOrders,
            actor, index, "marchingOrder") or actor.marchingOrder or actor.marchingRank, #members)
        if config.requireComplete ~= false and not marchingOrder then
            return nil, "Marching order required"
        end
        if marchingOrder then
            marchingOrder = math.floor(marchingOrder)
            if marchingOrder < 1 then
                return nil, "Marching order must be positive"
            end
            if usedMarchingOrder[marchingOrder] then
                return nil, "Marching order must be unique"
            end
            usedMarchingOrder[marchingOrder] = true
        end

        actor.guildName = guildName
        actor.guildRole = role
        actor.role = actor.role or role
        actor.marchingOrder = marchingOrder
        actor.guildRosterEntry = {
            actor = actor,
            actorId = id,
            name = actor.name,
            role = role,
            marchingOrder = marchingOrder,
        }

        roster.entries[#roster.entries + 1] = actor.guildRosterEntry
        roster.roles[id] = role
        if marchingOrder then
            roster.marchingOrder[#roster.marchingOrder + 1] = actor.guildRosterEntry
        end
    end

    table.sort(roster.marchingOrder, function(a, b)
        return (a.marchingOrder or 0) < (b.marchingOrder or 0)
    end)

    local bondsApplied = {}
    for _, source in ipairs(members) do
        local sourceId = actorId(source)
        for _, target in ipairs(members) do
            local targetId = actorId(target)
            if source ~= target then
                local status = bondStatusFromConfig(config.bonds, sourceId, targetId)
                if not status and config.defaultBondStatus then
                    status = config.defaultBondStatus
                end
                if status then
                    local bondInfo = adventurer_module.getBondInfo(status)
                    if config.strictBondTypes == true and not bondInfo then
                        return nil, "Unknown Bond type"
                    end
                    local _, appliedInfo = setActorBond(source, target, status)
                    bondsApplied[#bondsApplied + 1] = {
                        from = sourceId,
                        to = targetId,
                        status = status,
                        bondType = appliedInfo and appliedInfo.id or nil,
                        rulebookName = appliedInfo and appliedInfo.name or nil,
                        chargeTrigger = appliedInfo and appliedInfo.chargeTrigger or nil,
                    }
                end
                if config.requireCompleteBonds ~= false and not actorHasBond(source, target) then
                    return nil, "Bond with every other guild member required"
                end
            end
        end
    end

    roster.bonds = bondsApplied
    return roster, "guild_roster_created", {
        roster = roster,
        members = members,
        bonds = bondsApplied,
        result = "guild_roster_created",
    }
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
