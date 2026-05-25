-- camp_actions.lua
-- Data registry of Camp Actions for Majesty
-- Ticket S8.3: Camp Actions Implementation
--
-- Defines the actions players can take during Step 1 of Camp Phase.
-- Reference: Rulebook p. 137-139

local events = require('logic.events')
local inventory = require('logic.inventory')
local bid_lore_engine = require('logic.bid_lore_engine')
local constants = require('constants')
local talent_catalog = require('data.talent_catalog')
local animal_companions = require('data.animal_companions')

local M = {}

local function normalizeActionTalentId(talentId)
    return tostring(talentId or ""):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
end

local function isAdventurer(entity)
    return type(entity) == "table" and entity.isPC == true
end

local function guildContains(guild, entity)
    if type(guild) ~= "table" or not entity then
        return false
    end

    for _, member in ipairs(guild) do
        if member == entity or (member and entity.id and member.id == entity.id) then
            return true
        end
    end

    return false
end

local function hasUsableActionTalent(entity, talentId)
    local talents = entity and entity.talents
    if type(talents) ~= "table" then
        return false
    end

    local requested = normalizeActionTalentId(talentId)
    for key, talent in pairs(talents) do
        local matches = normalizeActionTalentId(key) == requested
        if not matches and type(talent) == "table" then
            matches = normalizeActionTalentId(talent.id or talent.name or talent.talentId) == requested
        end
        if matches then
            if type(talent) == "table" then
                return talent.wounded ~= true
            end
            return talent == true
        end
    end

    return false
end

local function normalizeWeaponType(item)
    return tostring((item and (item.weaponType or item.type)) or ""):lower()
end

local function fletchAmmoTypeForItem(item)
    if not item then
        return nil
    end
    local weaponType = normalizeWeaponType(item)
    if weaponType == "bow" then
        return "arrow"
    end
    if weaponType == "crossbow" then
        return "bolt"
    end
    if item.uses_ammo and (item.ammoType == "arrow" or item.ammoType == "bolt") then
        return item.ammoType
    end
    return nil
end

local function ammoCount(actor, ammoType)
    if type(actor and actor.ammunition) == "table" and ammoType then
        return math.max(0, math.floor(tonumber(actor.ammunition[ammoType]) or 0))
    end
    return math.max(0, math.floor(tonumber(actor and actor.ammo) or 0))
end

local function setAmmoCount(actor, ammoType, count)
    count = math.max(0, math.floor(tonumber(count) or 0))
    if ammoType then
        actor.ammunition = actor.ammunition or {}
        actor.ammunition[ammoType] = count
    end
    actor.ammo = count
    return count
end

local function isActionTalentMastered(entity, talentId)
    local talents = entity and entity.talents
    if type(talents) ~= "table" then
        return false
    end

    local requested = normalizeActionTalentId(talentId)
    for key, talent in pairs(talents) do
        local matches = normalizeActionTalentId(key) == requested
        if not matches and type(talent) == "table" then
            matches = normalizeActionTalentId(talent.id or talent.name or talent.talentId) == requested
        end
        if matches then
            if type(talent) == "table" then
                return talent.mastered == true and talent.wounded ~= true
            end
            return talent == true
        end
    end

    return false
end

--------------------------------------------------------------------------------
-- CAMP ACTION CATEGORIES
--------------------------------------------------------------------------------
M.CATEGORIES = {
    MAINTENANCE = "maintenance",  -- Item/gear repair
    SOCIAL      = "social",       -- Bond interactions
    EXPLORATION = "exploration",  -- Scouting, recon
    REST        = "rest",         -- Recovery/healing
}

--------------------------------------------------------------------------------
-- CAMP ACTION DEFINITIONS
--------------------------------------------------------------------------------
-- Each action has:
--   id            - Unique identifier
--   name          - Display name
--   category      - Action category
--   description   - Short description for tooltip
--   requiresTarget - Whether a target is needed
--   targetType    - "pc" (party member), "item", "companion"
--   requiresItem  - Item needed to perform (optional)
--   testSuit      - If a test is required, which suit
--   resolve       - Function to execute the action

M.ACTIONS = {
    ----------------------------------------------------------------------------
    -- MAINTENANCE ACTIONS
    ----------------------------------------------------------------------------
    {
        id = "repair",
        name = "Repair",
        category = M.CATEGORIES.MAINTENANCE,
        description = "Remove 1 Notch from an item. Requires Tinker's Kit.",
        requiresTarget = true,
        targetType = "item",
        requiresItem = "tinkers_kit",
    },
    {
        id = "fletch_arrows",
        name = "Fletch Arrows",
        category = M.CATEGORIES.MAINTENANCE,
        description = "Refill arrows or bolts to twelve. Requires a bow or crossbow.",
        requiresTarget = false,
        requiresFletchAmmo = true,
    },
    {
        id = "brew_alchemy",
        name = "Brew Alchemy",
        category = M.CATEGORIES.MAINTENANCE,
        description = "Transform bottled reagents into potions, bombs, or oils.",
        requiresTarget = false,
        requiresAlchemy = true,
    },
    {
        id = "use_item",
        name = "Use an Item",
        category = M.CATEGORIES.MAINTENANCE,
        description = "Use a Camp-phase item such as leeches, pipeweed, or hunted game preparations.",
        requiresTarget = false,
        requiresCampUsableItem = true,
    },

    ----------------------------------------------------------------------------
    -- SOCIAL ACTIONS
    ----------------------------------------------------------------------------
    {
        id = "fellowship",
        name = "Fellowship",
        category = M.CATEGORIES.SOCIAL,
        description = "Share a moment with a companion. Both charge a Bond with each other.",
        requiresTarget = true,
        targetType = "pc",
    },
    {
        id = "read_book",
        name = "Read a Book",
        category = M.CATEGORIES.EXPLORATION,
        description = "Ask one question based on a readable book you carry.",
        requiresTarget = true,
        targetType = "item",
        requiresReadableBook = true,
    },
    {
        id = "train",
        name = "Train",
        category = M.CATEGORIES.SOCIAL,
        description = "Invest XP into a talent taught by a willing guild-mate who mastered it.",
        requiresTarget = true,
        targetType = "pc",
    },
    {
        id = "use_talent",
        name = "Use a Talent",
        category = M.CATEGORIES.SOCIAL,
        description = "Use a talent that is available during the Camp Phase.",
        requiresTarget = false,
        requiresCampTalent = true,
    },
    {
        id = "make_pact",
        name = "Make a Pact",
        category = M.CATEGORIES.SOCIAL,
        description = "Observe one or more pacts to charge spell components.",
        requiresTarget = false,
        requiresTalent = "gramarye",
    },
    {
        id = "infiltrate",
        name = "Infiltrate",
        category = M.CATEGORIES.EXPLORATION,
        description = "Use Sneak to investigate a known location and unlock precise lore questions.",
        requiresTarget = false,
        requiresTalent = "sneak",
    },
    {
        id = "devour_living",
        name = "Devour the Living",
        category = M.CATEGORIES.EXPLORATION,
        description = "Test Cups to find living vermin for a Devour the Living pact.",
        requiresTarget = false,
        requiresActivePact = "devour_living",
        testSuit = "cups",
    },
    {
        id = "heal_companion",
        name = "Heal Companion",
        category = M.CATEGORIES.SOCIAL,
        description = "Clear Injured from an animal companion. Requires Bond.",
        requiresTarget = true,
        targetType = "companion",
        requiresBond = true,
    },

    ----------------------------------------------------------------------------
    -- EXPLORATION ACTIONS
    ----------------------------------------------------------------------------
    {
        id = "scout",
        name = "Scout Ahead",
        category = M.CATEGORIES.EXPLORATION,
        description = "Test Pentacles to reveal information about adjacent rooms.",
        requiresTarget = false,
        testSuit = "pentacles",
    },
    {
        id = "hunt",
        name = "Hunt",
        category = M.CATEGORIES.EXPLORATION,
        description = "Test Swords with a missile weapon to find fresh game.",
        requiresTarget = false,
        requiresRangedAmmo = true,
        testSuit = "swords",
    },
    {
        id = "patrol",
        name = "Patrol",
        category = M.CATEGORIES.EXPLORATION,
        description = "Keep watch. Draw twice from Meatgrinder during Watch phase.",
        requiresTarget = false,
    },
    {
        id = "update_maps",
        name = "Update Maps",
        category = M.CATEGORIES.EXPLORATION,
        description = "Record travelled rooms as mapped, allowing faster mapped travel.",
        requiresTarget = false,
    },

    ----------------------------------------------------------------------------
    -- REST ACTIONS
    ----------------------------------------------------------------------------
    {
        id = "rest",
        name = "Rest and Recover",
        category = M.CATEGORIES.REST,
        description = "Rest; during Recovery, burn Bonds to heal or stave off afflictions.",
        requiresTarget = false,
    },
}

--------------------------------------------------------------------------------
-- LOOKUP TABLES
--------------------------------------------------------------------------------

M.byId = {}
M.byCategory = {
    [M.CATEGORIES.MAINTENANCE] = {},
    [M.CATEGORIES.SOCIAL] = {},
    [M.CATEGORIES.EXPLORATION] = {},
    [M.CATEGORIES.REST] = {},
}

-- Build lookup tables
for _, action in ipairs(M.ACTIONS) do
    M.byId[action.id] = action
    if M.byCategory[action.category] then
        table.insert(M.byCategory[action.category], action)
    end
end

--------------------------------------------------------------------------------
-- QUERY FUNCTIONS
--------------------------------------------------------------------------------

--- Get an action by ID
function M.getAction(actionId)
    return M.byId[actionId]
end

--- Get all actions for a category
function M.getActionsForCategory(category)
    return M.byCategory[category] or {}
end

--- Get actions available for a given entity
-- @param entity table: The adventurer
-- @param guild table: The party (for fellowship targets)
-- @return table: Array of available action definitions
function M.getAvailableActions(entity, guild, context)
    local available = {}
    context = context or {}

    for _, action in ipairs(M.ACTIONS) do
        local canUse = true

        -- Check item requirements
        if action.requiresItem then
            if entity and entity.inventory and entity.inventory.hasItemOfType then
                local hasItem = entity.inventory:hasItemOfType(action.requiresItem)
                if not hasItem then
                    canUse = false
                end
            else
                canUse = false
            end
        end

        if action.requiresFletchAmmo and not M.hasMissileWeapon(entity) then
            canUse = false
        end

        if action.requiresRangedAmmo and not M.canHunt(entity, context) then
            canUse = false
        end

        if action.requiresReadableBook and not M.hasReadableBook(entity) then
            canUse = false
        end

        if action.requiresAlchemy and not M.canBrewAlchemy(entity) then
            canUse = false
        end

        if action.requiresCampUsableItem and not M.hasCampUsableItem(entity) then
            canUse = false
        end

        if action.requiresCampTalent and not M.hasCampTalent(entity) then
            canUse = false
        end

        if action.requiresTalent and not hasUsableActionTalent(entity, action.requiresTalent) then
            canUse = false
        end

        if action.requiresActivePact and not M.findUnbrokenActivePact(entity, action.requiresActivePact) then
            canUse = false
        end

        -- Check if targeting PC but no other PCs available
        if action.targetType == "pc" then
            local hasOtherPCs = false
            if guild then
                for _, pc in ipairs(guild) do
                    if isAdventurer(pc) and pc.id ~= entity.id then
                        hasOtherPCs = true
                        break
                    end
                end
            end
            if not hasOtherPCs then
                canUse = false
            end
        end

        -- Check companion requirements
        if action.targetType == "companion" then
            local hasCompanion = entity.animalCompanions and #entity.animalCompanions > 0
            if not hasCompanion then
                canUse = false
            end
        end

        if canUse then
            available[#available + 1] = action
        end
    end

    return available
end

--------------------------------------------------------------------------------
-- ACTION RESOLUTION
--------------------------------------------------------------------------------

local function mergeActionContext(context, actionData)
    local merged = {}
    for key, value in pairs(context or {}) do
        merged[key] = value
    end
    for key, value in pairs(actionData or {}) do
        if key ~= "actor" and key ~= "type" and key ~= "target" then
            merged[key] = value
        end
    end
    return merged
end

--- Resolve a camp action
-- @param actionData table: { type, actor, target, ... }
-- @param context table: { eventBus, guild, ... }
-- @return boolean, string: success, result message
function M.resolveAction(actionData, context)
    local actionDef = M.byId[actionData.type]
    if not actionDef then
        return false, "Unknown action: " .. tostring(actionData.type)
    end

    local actor = actionData.actor
    local target = actionData.target
    local eventBus = context.eventBus or events.globalBus

    -- Dispatch to specific handler
    if actionData.type == "repair" then
        return M.resolveRepair(actor, target, eventBus)
    elseif actionData.type == "fletch_arrows" then
        return M.resolveFletchArrows(actor, eventBus)
    elseif actionData.type == "brew_alchemy" then
        return M.resolveBrewAlchemy(actor, actionData, context, eventBus)
    elseif actionData.type == "use_item" then
        return M.resolveUseItem(actor, target, actionData, context, eventBus)
    elseif actionData.type == "fellowship" then
        return M.resolveFellowship(actor, target, eventBus, context)
    elseif actionData.type == "read_book" then
        return M.resolveReadBook(actor, target, actionData.request or actionData.loreRequest, context, eventBus)
    elseif actionData.type == "train" then
        return M.resolveTrain(actor, target, actionData, context, eventBus)
    elseif actionData.type == "use_talent" then
        return M.resolveUseTalent(actor, actionData, context, eventBus)
    elseif actionData.type == "make_pact" then
        return M.resolveMakePact(actor, actionData, context, eventBus)
    elseif actionData.type == "infiltrate" then
        return M.resolveInfiltrate(actor, actionData, context, eventBus)
    elseif actionData.type == "devour_living" then
        return M.resolveDevourLiving(actor, actionData, context, eventBus)
    elseif actionData.type == "rest" then
        return M.resolveRest(actor, eventBus)
    elseif actionData.type == "heal_companion" then
        return M.resolveHealCompanion(actor, target, eventBus)
    elseif actionData.type == "scout" then
        local outcome = actionData.outcome or actionData.testResult or actionData.testOutcome
        if outcome ~= nil then
            return M.resolveScoutOutcome(actor, outcome, mergeActionContext(context, actionData), eventBus)
        end
        return M.resolveScout(actor, context, eventBus)
    elseif actionData.type == "hunt" then
        local outcome = actionData.outcome or actionData.testResult or actionData.testOutcome
        if outcome ~= nil then
            return M.resolveHuntOutcome(actor, outcome, mergeActionContext(context, actionData), eventBus)
        end
        return M.resolveHunt(actor, context, eventBus)
    elseif actionData.type == "patrol" then
        return M.resolvePatrol(actor, context, eventBus)
    elseif actionData.type == "update_maps" then
        local mapContext = {}
        for key, value in pairs(context or {}) do
            mapContext[key] = value
        end
        for key, value in pairs(actionData or {}) do
            if key ~= "actor" and key ~= "type" then
                mapContext[key] = value
            end
        end
        return M.resolveUpdateMaps(actor, mapContext, eventBus)
    end

    return false, "Action not implemented: " .. actionData.type
end

function M.getFletchAmmoTypes(actor)
    local inv = actor and actor.inventory
    local ammoTypes = {}
    local seen = {}
    if not inv then
        return ammoTypes
    end

    for _, location in ipairs({ "hands", "belt", "pack" }) do
        for _, item in ipairs(inv[location] or {}) do
            local ammoType = fletchAmmoTypeForItem(item)
            if ammoType and not seen[ammoType] then
                seen[ammoType] = true
                ammoTypes[#ammoTypes + 1] = ammoType
            end
        end
    end

    return ammoTypes
end

function M.hasMissileWeapon(actor)
    return #M.getFletchAmmoTypes(actor) > 0
end

function M.hasFishingGear(actor)
    local inv = actor and actor.inventory
    if not inv then
        return false
    end

    return inv:findItemByPredicate(function(item)
        local props = item and item.properties or {}
        return item.templateId == "fishing_gear" or item.type == "fishing_gear" or
            item.itemType == "fishing_gear" or props.toolType == "fishing" or props.fishingGear == true
    end) ~= nil
end

local function normalizedText(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:lower():gsub("[^%w]+", "_")
end

local function tableLooksWatery(value)
    if type(value) ~= "table" then
        return false
    end

    local props = value.properties or {}
    if value.water == true or value.bodyOfWater == true or value.body_of_water == true or value.hasWater == true or
       value.river == true or value.lake == true or value.moat == true or value.pool == true or
       value.stream == true or props.water == true or props.bodyOfWater == true or props.body_of_water == true or
       props.hasWater == true or props.river == true or props.lake == true or props.moat == true or
       props.pool == true or props.stream == true then
        return true
    end

    local key = normalizedText(value.type or value.kind or value.category or value.terrain or value.id or value.name)
    if key:find("water", 1, true) or key:find("river", 1, true) or key:find("lake", 1, true) or
       key:find("moat", 1, true) or key:find("pool", 1, true) or key:find("stream", 1, true) or
       key:find("shore", 1, true) then
        return true
    end

    for _, feature in ipairs(value.features or {}) do
        if tableLooksWatery(feature) then
            return true
        end
    end

    return false
end

function M.contextHasFishingWater(context)
    context = context or {}
    if context.hasWater == true or context.bodyOfWater == true or context.body_of_water == true or
       context.atWater == true or context.fishingWater == true then
        return true
    end

    for _, key in ipairs({ "currentRoom", "room", "location", "zone", "campSite", "site" }) do
        if tableLooksWatery(context[key]) then
            return true
        end
    end

    local id = normalizedText(context.currentRoomId or context.roomId or context.locationId or context.zoneId)
    return id:find("water", 1, true) ~= nil or id:find("river", 1, true) ~= nil or
        id:find("lake", 1, true) ~= nil or id:find("moat", 1, true) ~= nil or
        id:find("pool", 1, true) ~= nil or id:find("stream", 1, true) ~= nil or
        id:find("shore", 1, true) ~= nil
end

function M.getHuntMethod(actor, context)
    if M.hasMissileWeapon(actor) then
        return "missile"
    end

    if M.hasFishingGear(actor) then
        if M.contextHasFishingWater(context) then
            return "fishing"
        end
        return nil, "Requires a body of water"
    end

    return nil, "Requires a missile weapon"
end

function M.canHunt(actor, context)
    return M.getHuntMethod(actor, context) ~= nil
end

local function isReadableBook(item)
    local props = item and item.properties or {}
    local bookish = item and item.type == "book" or
                    props.book == true or
                    props.readableBook == true or
                    props.isReadableBook == true
    return bookish and (
        props.readableBook == true or
        props.isReadableBook == true or
        props.loreSubjectId ~= nil or
        props.loreAnswers ~= nil
    )
end

local function actorAfflictionStage(actor, afflictionId)
    if not actor then
        return 0
    end
    local afflictions = actor.afflictions
    local affliction = type(afflictions) == "table" and afflictions[afflictionId]
    if type(affliction) == "table" then
        return tonumber(affliction.stage or affliction.currentStage or affliction.progressStage) or 1
    end
    if affliction == true then
        return 1
    end
    return 0
end

local function actorCannotRead(actor)
    local conditions = actor and actor.conditions or {}
    return actor and (actor.cannotRead == true or actor.cannotReadOrWrite == true or
        conditions.cannot_read == true or conditions.cannot_read_or_write == true or
        actorAfflictionStage(actor, "ghost_lotus") >= 2 or
        actorAfflictionStage(actor, "ghostLotus") >= 2)
end

local function findReadableBook(actor)
    if actorCannotRead(actor) then
        return nil
    end

    local inv = actor and actor.inventory
    if not inv or not inv.findItemByPredicate then
        return nil
    end

    return inv:findItemByPredicate(isReadableBook)
end

function M.hasReadableBook(actor)
    return findReadableBook(actor) ~= nil
end

local function actorCarriesItem(actor, item)
    local inv = actor and actor.inventory
    if not inv or not item or not inv.findItem then
        return false
    end

    local carried = inv:findItem(item.id)
    return carried ~= nil
end

local PACT_DEFINITIONS = {
    devour_living = {
        name = "Devour the Living",
        obligation = "Eat only creatures that are yet living.",
    },
    forego_armor = {
        name = "Forego Armor",
        obligation = "Wear no armor, helm, or shield.",
    },
    forego_skins = {
        name = "Forego Skins",
        obligation = "Wear nothing made from skins, furs, or leather.",
    },
    forego_weapons = {
        name = "Forego Weapons",
        obligation = "Do not touch, manipulate, or wield weapons; wands are exempt.",
    },
    forego_wood = {
        name = "Forego Wood",
        obligation = "Do not wield, touch, or carry felled wood.",
    },
    gluttony = {
        name = "Gluttony",
        obligation = "Eat double portions whenever consuming rations.",
    },
    hide_face = {
        name = "Hide Your Face",
        obligation = "Keep the face hidden behind a mask.",
        socialDisfavor = true,
    },
    self_mortification = {
        name = "Self-mortification",
        obligation = "Wear a hair shirt and remain Stressed.",
        causesStressed = true,
    },
    self_mutilation = {
        name = "Self-mutilation",
        obligation = "Bear pact runes as a Wound that must not be healed.",
        causesWound = true,
    },
    silence = {
        name = "Silence",
        obligation = "Speak only in whispers.",
    },
    verity = {
        name = "Verity",
        obligation = "Tell no knowing lie.",
    },
}

local PACT_ALIASES = {
    devour_the_living = "devour_living",
    hide_your_face = "hide_face",
}

local function normalizePactId(pactId)
    local normalized = normalizeActionTalentId(pactId)
    return PACT_ALIASES[normalized] or normalized
end

local function resolvePactDefinition(pact)
    if type(pact) == "table" then
        local pactId = normalizePactId(pact.id or pact.pactId or pact.name)
        local definition = PACT_DEFINITIONS[pactId]
        if definition then
            return pactId, definition
        end
        if pact.name then
            return pactId, {
                name = pact.name,
                obligation = pact.obligation,
                custom = true,
            }
        end
        return nil, nil
    end

    local pactId = normalizePactId(pact)
    return pactId, PACT_DEFINITIONS[pactId]
end

local function normalizeList(value)
    if value == nil then
        return {}
    end
    if type(value) == "table" then
        if #value == 0 then
            return { value }
        end
        return value
    end
    return { value }
end

local function isSpellComponent(item)
    local props = item and item.properties or {}
    return props.spellComponent == true or props.componentFor ~= nil or item.spellComponent == true
end

local function findSpellComponentForPact(actor, componentRef)
    local inv = actor and actor.inventory
    if not inv then
        return nil, nil
    end
    if type(componentRef) == "table" then
        local carried, location = inv.findItem and inv:findItem(componentRef.id)
        if carried then
            return carried, location
        end
        if actorCarriesItem(actor, componentRef) then
            return componentRef
        end
        return nil, nil
    end
    if componentRef and inv.findItem then
        local byId, location = inv:findItem(componentRef)
        if byId then
            return byId, location
        end
    end
    if componentRef and inv.findItemByPredicate then
        local wanted = normalizeActionTalentId(componentRef)
        return inv:findItemByPredicate(function(item)
            local props = item.properties or {}
            return normalizeActionTalentId(item.templateId or item.id or item.name) == wanted or
                normalizeActionTalentId(props.componentFor) == wanted
        end)
    end
    if inv.findItemByPredicate then
        return inv:findItemByPredicate(function(item)
            local props = item.properties or {}
            return isSpellComponent(item) and not props.pactCharged and item.pactCharge == nil
        end)
    end

    return nil, nil
end

function M.getPactOptions()
    local options = {}
    for pactId, definition in pairs(PACT_DEFINITIONS) do
        options[#options + 1] = {
            id = pactId,
            name = definition.name,
            obligation = definition.obligation,
            socialDisfavor = definition.socialDisfavor == true,
            causesStressed = definition.causesStressed == true,
            causesWound = definition.causesWound == true,
        }
    end
    table.sort(options, function(a, b)
        return (a.name or a.id or "") < (b.name or b.id or "")
    end)
    return options
end

function M.getAvailablePactComponents(actor)
    local inv = actor and actor.inventory
    if not inv or not inv.getAllItems then
        return {}
    end

    local options = {}
    for _, entry in ipairs(inv:getAllItems()) do
        local item = entry.item
        local props = item and item.properties or {}
        if isSpellComponent(item) and not props.pactCharged and item.pactCharge == nil then
            options[#options + 1] = {
                item = item,
                location = entry.location,
                componentFor = props.componentFor,
            }
        end
    end
    return options
end

local function applyImmediatePactEffect(actor, pact)
    if not actor or not pact then
        return nil
    end

    if pact.causesStressed then
        actor.conditions = actor.conditions or {}
        actor.conditions.stressed = true
        actor.stressed = true
        return "stressed"
    end

    if pact.causesWound then
        if actor.takeWound then
            return actor:takeWound("normal", { source = "make_pact", pactId = pact.id })
        end
        actor.pactWounds = (actor.pactWounds or 0) + 1
        return "wound_recorded"
    end

    return nil
end

local function cloneArray(items)
    local out = {}
    for i = 1, #(items or {}) do
        out[i] = items[i]
    end
    return out
end

local function cloneResponse(response)
    if type(response) ~= "table" then
        return {
            summary = tostring(response or ""),
            details = {},
            implication = "",
            sourceRefs = {},
        }
    end

    return {
        summary = response.summary or "",
        details = cloneArray(response.details or {}),
        implication = response.implication or "",
        sourceRefs = cloneArray(response.sourceRefs or {}),
    }
end

local function directBookAnswer(book, questionType)
    local props = book and book.properties or {}
    local answers = props.loreAnswers or {}
    local answer = answers[questionType]
    if not answer then
        return nil
    end

    return cloneResponse(answer)
end

local function findSaltItem(actor)
    local inv = actor and actor.inventory
    if not inv or not inv.findItemByPredicate then
        return nil
    end

    return inv:findItemByPredicate(function(item)
        local name = item.name and item.name:lower()
        return item.templateId == "salt" or
               item.type == "salt" or
               name == "salt"
    end)
end

local function hasCookingGear(actor)
    local inv = actor and actor.inventory
    if not inv or not inv.findItemByPredicate then
        return false
    end

    local item = inv:findItemByPredicate(function(i)
        local props = i.properties or {}
        return i.templateId == "cooking_gear" or
               i.type == "cooking_gear" or
               props.cookingGear or
               props.toolType == "cooking"
    end)

    return item ~= nil
end

local function isFreshGame(item)
    return item and item.properties and item.properties.freshGame == true
end

local function isPipeweedStressItem(item)
    local props = item and item.properties or {}
    local effect = props.useEffect or {}
    local clearsStress = false
    for _, condition in ipairs(effect.conditions or {}) do
        if condition == "stressed" then
            clearsStress = true
            break
        end
    end

    return props.effect == "clear_stress" or
           (effect.type == "clear_conditions" and
            effect.target == "self" and
            clearsStress)
end

local function isTinkersKitItem(item)
    local props = item and item.properties or {}
    return item and (item.templateId == "tinkers_kit" or item.type == "tinkers_kit" or
        props.toolType == "tinker" or props.tinkersKit == true)
end

local function campItemOption(item, location)
    return {
        id = item and item.id or nil,
        name = item and item.name or nil,
        templateId = item and item.templateId or nil,
        location = location,
        size = item and item.size or nil,
        quantity = item and item.quantity or nil,
        stackable = item and item.stackable == true,
        notches = item and item.notches or 0,
        durability = item and item.durability or nil,
        destroyed = item and item.destroyed == true,
    }
end

function M.getMakePactOptions(actor, actionData, context)
    actionData = actionData or {}
    context = context or {}

    local unavailableReasons = {}
    local function addUnavailable(reason)
        if not reason then
            return
        end
        for _, existing in ipairs(unavailableReasons) do
            if existing == reason then
                return
            end
        end
        unavailableReasons[#unavailableReasons + 1] = reason
    end

    local hasGramarye = hasUsableActionTalent(actor, "gramarye")
    local availableComponents = M.getAvailablePactComponents(actor)
    if not actor then
        addUnavailable("no_actor")
    end
    if not hasGramarye then
        addUnavailable("Requires Gramarye")
    end
    if #availableComponents == 0 then
        addUnavailable("Choose a carried spell component")
    end

    local function pactOptionRecord(pactId, definition)
        return {
            id = pactId,
            name = definition.name,
            obligation = definition.obligation,
            socialDisfavor = definition.socialDisfavor == true,
            causesStressed = definition.causesStressed == true,
            causesWound = definition.causesWound == true,
            immediateEffectPreview = definition.causesStressed and "stressed" or
                (definition.causesWound and "wound_recorded" or nil),
            actionDataPreview = {
                type = "make_pact",
                pactId = pactId,
            },
        }
    end

    local selectedPactSpecs = normalizeList(actionData.pacts or actionData.pactIds or
        actionData.pact or actionData.pactId)
    local selectedComponentRefs = normalizeList(actionData.components or actionData.componentIds or
        actionData.component or actionData.componentId)
    local selectedPactIds = {}
    for _, pactSpec in ipairs(selectedPactSpecs) do
        local pactId = resolvePactDefinition(pactSpec)
        if pactId then
            selectedPactIds[pactId] = true
        end
    end

    local function componentRefMatches(ref, item)
        if not ref or not item then
            return false
        end
        if type(ref) == "table" then
            return ref == item or (ref.id ~= nil and ref.id == item.id)
        end
        local wanted = normalizeActionTalentId(ref)
        local props = item.properties or {}
        return normalizeActionTalentId(item.id) == wanted or
            normalizeActionTalentId(item.templateId) == wanted or
            normalizeActionTalentId(item.name) == wanted or
            normalizeActionTalentId(props.componentFor) == wanted
    end

    local function componentSelected(item)
        for _, ref in ipairs(selectedComponentRefs) do
            if componentRefMatches(ref, item) then
                return true
            end
        end
        return false
    end

    local pactOptions = {}
    for _, option in ipairs(M.getPactOptions()) do
        local record = pactOptionRecord(option.id, option)
        record.selected = selectedPactIds[option.id] == true
        pactOptions[#pactOptions + 1] = record
    end

    local componentOptions = {}
    for _, entry in ipairs(availableComponents) do
        local option = campItemOption(entry.item, entry.location)
        option.componentFor = entry.componentFor
        option.selected = componentSelected(entry.item)
        componentOptions[#componentOptions + 1] = option
    end

    local selectedPacts = {}
    local selectedDisabled = false
    local usedComponents = {}
    for index, pactSpec in ipairs(selectedPactSpecs) do
        local pactId, definition = resolvePactDefinition(pactSpec)
        local selected = {
            request = pactSpec,
            pactId = pactId,
            disabled = false,
        }

        if not pactId or not definition then
            selected.disabled = true
            selected.unavailableReason = "Unknown pact"
        else
            selected.name = definition.name
            selected.obligation = definition.obligation
            selected.socialDisfavor = definition.socialDisfavor == true
            selected.causesStressed = definition.causesStressed == true
            selected.causesWound = definition.causesWound == true
            selected.immediateEffectPreview = definition.causesStressed and "stressed" or
                (definition.causesWound and "wound_recorded" or nil)

            local componentRef = selectedComponentRefs[index] or selectedComponentRefs[1]
            local component, location = nil, nil
            if componentRef then
                component, location = findSpellComponentForPact(actor, componentRef)
            else
                component, location = findSpellComponentForPact(actor)
            end
            if component and not location then
                for _, entry in ipairs(availableComponents) do
                    if entry.item == component or componentRefMatches(componentRef, entry.item) then
                        location = entry.location
                        break
                    end
                end
            end
            selected.component = campItemOption(component, location)
            selected.component.componentFor = component and component.properties and component.properties.componentFor
            selected.actionDataPreview = {
                type = "make_pact",
                pactId = pactId,
                componentId = component and component.id or nil,
            }

            if not component or not isSpellComponent(component) then
                selected.disabled = true
                selected.unavailableReason = "Choose a carried spell component"
            elseif usedComponents[component] or (component.id and usedComponents[component.id]) then
                selected.disabled = true
                selected.unavailableReason = "Each pact needs a different component"
            elseif (component.properties or {}).pactCharged or component.pactCharge then
                selected.disabled = true
                selected.unavailableReason = "Component already charged"
            else
                usedComponents[component] = true
                if component.id then
                    usedComponents[component.id] = true
                end
                selected.resultPreview = {
                    result = "pact_made",
                    pactId = pactId,
                    pactName = definition.name,
                    componentId = component.id,
                    componentName = component.name,
                    componentLocation = location,
                    active = true,
                    socialDisfavor = definition.socialDisfavor == true,
                    immediateEffect = selected.immediateEffectPreview,
                }
            end
        end

        if selected.disabled then
            selectedDisabled = true
            addUnavailable(selected.unavailableReason)
        end
        selectedPacts[#selectedPacts + 1] = selected
    end

    return {
        result = "make_pact_options_ready",
        actor = actor,
        actorId = actor and actor.id or nil,
        actorName = actor and actor.name or nil,
        disabled = #unavailableReasons > 0 or selectedDisabled,
        unavailableReasons = unavailableReasons,
        hasGramarye = hasGramarye,
        requiresPacts = #selectedPactSpecs == 0,
        pactOptions = pactOptions,
        componentOptions = componentOptions,
        selectedPacts = selectedPacts,
        selectedCount = #selectedPacts,
        rules = {
            requiresGramarye = true,
            chargesOneComponentPerPact = true,
            eachPactNeedsDifferentComponent = true,
            chargedComponentsCanPowerSpells = true,
            immediateEffects = {
                selfMortification = "stressed",
                selfMutilation = "wound_recorded",
            },
        },
    }
end

local function campInventoryEntries(actor)
    local inv = actor and actor.inventory
    if not inv then
        return {}
    end
    if inv.getAllItems then
        return inv:getAllItems()
    end

    local entries = {}
    for _, location in ipairs({ "hands", "belt", "pack" }) do
        for index, item in ipairs(inv[location] or {}) do
            entries[#entries + 1] = {
                item = item,
                location = location,
                index = index,
            }
        end
    end
    return entries
end

local function isCampUsableItem(item)
    local props = item and item.properties or {}
    return props.leeches == true or props.campUse == true or isPipeweedStressItem(item) or
        isTinkersKitItem(item)
end

local function canPrepareHuntedGame(actor, item)
    return isFreshGame(item) and (hasCookingGear(actor) or findSaltItem(actor) ~= nil)
end

function M.hasCampUsableItem(actor)
    local inv = actor and actor.inventory
    if not inv then
        return false
    end

    if inv.getAllItems then
        for _, entry in ipairs(inv:getAllItems()) do
            local item = entry.item
            if isCampUsableItem(item) or canPrepareHuntedGame(actor, item) then
                return true
            end
        end
        return false
    end

    if not inv.findItemByPredicate then
        return false
    end

    local item = inv:findItemByPredicate(function(candidate)
        return isCampUsableItem(candidate) or canPrepareHuntedGame(actor, candidate)
    end)
    return item ~= nil
end

local function findCampActionItem(actor, itemId)
    local inv = actor and actor.inventory
    if not inv then
        return nil
    end
    if itemId and inv.findItem then
        local item, location = inv:findItem(itemId)
        if item and (isCampUsableItem(item) or canPrepareHuntedGame(actor, item)) then
            return item, location
        end
        return nil, nil
    end
    if inv.findItemByPredicate then
        return inv:findItemByPredicate(function(item)
            return isCampUsableItem(item) or canPrepareHuntedGame(actor, item)
        end)
    end
    return nil
end

local function consumeCampItem(actor, item)
    local inv = actor and actor.inventory
    if not inv or not item or not inv.removeItemQuantity then
        return false
    end

    return inv:removeItemQuantity(item.id, 1)
end

local function drawMinorCard(actionData, context)
    if actionData.card or actionData.drawnCard then
        return actionData.card or actionData.drawnCard, false, nil
    end

    local deck = actionData.deck or actionData.playerDeck or actionData.minorDeck or
        context.playerDeck or context.minorDeck
    if deck and deck.draw then
        return deck:draw(), true, deck
    end

    return nil, false, deck
end

local function leechesGrantCharges(card)
    return card and (card.suit == constants.SUITS.CUPS or card.suit == constants.SUITS.WANDS)
end

--------------------------------------------------------------------------------
-- REPAIR (S8.3)
--------------------------------------------------------------------------------
-- Remove 1 Notch from an item. Requires Tinker's Kit.

function M.getRepairOptions(actor, opts)
    opts = opts or {}
    local selectedTarget = opts.targetItem or opts.itemToRepair or opts.repairTarget or opts.target
    local selectedTargetId = opts.targetItemId or opts.itemToRepairId or opts.repairTargetId or opts.targetItemID or
        (type(selectedTarget) == "table" and selectedTarget.id or selectedTarget)
    local kitOptions = {}
    local repairTargets = {}
    local blockedTargets = {}
    local selectedOption = nil

    for _, entry in ipairs(campInventoryEntries(actor)) do
        local item = entry.item
        if isTinkersKitItem(item) then
            kitOptions[#kitOptions + 1] = campItemOption(item, entry.location)
        end

        if item and (item.notches or 0) > 0 then
            local option = campItemOption(item, entry.location)
            if item.destroyed then
                option.unavailableReason = "destroyed_equipment_cannot_be_salvaged"
                blockedTargets[#blockedTargets + 1] = option
            else
                option.resultPreview = "repaired"
                option.notchesAfterRepair = math.max(0, (item.notches or 0) - 1)
                repairTargets[#repairTargets + 1] = option
                if selectedTargetId and item.id == selectedTargetId then
                    selectedOption = option
                end
            end
        end
    end

    local unavailableReasons = {}
    if #kitOptions == 0 then
        unavailableReasons[#unavailableReasons + 1] = "requires_tinkers_kit"
    end
    if #repairTargets == 0 then
        unavailableReasons[#unavailableReasons + 1] = "no_notched_equipment"
    end
    if selectedTargetId and not selectedOption then
        unavailableReasons[#unavailableReasons + 1] = "selected_item_not_repairable"
    end

    return {
        result = "repair_options_ready",
        actor = actor,
        actorId = actor and actor.id or nil,
        actorName = actor and actor.name or nil,
        hasTinkersKit = #kitOptions > 0,
        kitOptions = kitOptions,
        repairTargets = repairTargets,
        blockedTargets = blockedTargets,
        selectedTarget = selectedOption,
        disabled = #unavailableReasons > 0,
        unavailableReasons = unavailableReasons,
        rules = {
            removesNotches = 1,
            requiresTinkersKit = true,
            destroyedEquipmentCannotBeSalvaged = true,
            kitConsumed = false,
        },
    }
end

function M.resolveRepair(actor, targetItem, eventBus, opts)
    opts = opts or {}
    if not targetItem then
        return false, "No item targeted for repair"
    end

    if targetItem.destroyed then
        return false, "Destroyed equipment cannot be salvaged with a tinker's kit"
    end

    -- Check if item has notches to remove
    if not targetItem.notches or targetItem.notches <= 0 then
        return false, "Item has no notches to repair"
    end

    -- Check for Tinker's Kit
    local hasTinkersKit = false
    if actor.inventory and actor.inventory.hasItemOfType then
        hasTinkersKit = actor.inventory:hasItemOfType("tinkers_kit")
    end

    if not hasTinkersKit then
        return false, "Requires Tinker's Kit"
    end

    -- Perform repair
    if not inventory.repairNotch(targetItem) then
        return false, "Item could not be repaired"
    end

    eventBus:emit("camp_action_resolved", {
        action = opts.action or "repair",
        actor = actor,
        target = targetItem,
        item = opts.item,
        itemId = opts.itemId,
        result = "notch_removed",
    })

    print("[CAMP] " .. actor.name .. " repaired " .. (targetItem.name or "item") ..
          " (notches: " .. targetItem.notches .. ")")

    return true, "repaired"
end

--------------------------------------------------------------------------------
-- FLETCH ARROWS (S8.3)
--------------------------------------------------------------------------------
-- Refill arrows or bolts to twelve.

function M.getFletchArrowsOptions(actor, opts)
    opts = opts or {}
    local weaponOptions = {}
    local ammoOptions = {}
    local seenAmmo = {}
    local unavailableReasons = {}

    if not actor then
        unavailableReasons[#unavailableReasons + 1] = "no_actor"
    elseif not actor.inventory then
        unavailableReasons[#unavailableReasons + 1] = "no_inventory"
    end

    for _, entry in ipairs(campInventoryEntries(actor)) do
        local item = entry.item
        local ammoType = fletchAmmoTypeForItem(item)
        if ammoType then
            local weaponOption = campItemOption(item, entry.location)
            weaponOption.ammoType = ammoType
            weaponOption.actionDataPreview = { type = "fletch_arrows" }
            weaponOptions[#weaponOptions + 1] = weaponOption

            if not seenAmmo[ammoType] then
                seenAmmo[ammoType] = true
                local previous = ammoCount(actor, ammoType)
                local refilled = math.max(previous, 12)
                ammoOptions[#ammoOptions + 1] = {
                    type = ammoType,
                    previousAmmo = previous,
                    ammoAfterFletch = refilled,
                    refilledBy = refilled - previous,
                    willRefill = refilled > previous,
                    alreadyAtOrAboveTwelve = previous >= 12,
                }
            end
        end
    end

    if #weaponOptions == 0 then
        unavailableReasons[#unavailableReasons + 1] = "requires_bow_or_crossbow"
    end

    return {
        result = "fletch_arrows_options_ready",
        actor = actor,
        actorId = actor and actor.id or nil,
        actorName = actor and actor.name or nil,
        hasMissileWeapon = #weaponOptions > 0,
        disabled = #weaponOptions == 0,
        unavailableReasons = unavailableReasons,
        weaponOptions = weaponOptions,
        ammoOptions = ammoOptions,
        actionDataPreview = { type = "fletch_arrows" },
        rules = {
            refillsToAtLeast = 12,
            doesNotReduceFullQuivers = true,
            supportsArrows = true,
            supportsBolts = true,
        },
    }
end

function M.resolveFletchArrows(actor, eventBus)
    local ammoTypes = M.getFletchAmmoTypes(actor)
    if #ammoTypes == 0 then
        return false, "Requires a bow or crossbow"
    end

    local previousAmmo = actor.ammo or 0
    local refilled = {}
    for _, ammoType in ipairs(ammoTypes) do
        local previous = ammoCount(actor, ammoType)
        local count = setAmmoCount(actor, ammoType, math.max(previous, 12))
        refilled[#refilled + 1] = {
            type = ammoType,
            previous = previous,
            ammo = count,
        }
    end

    eventBus:emit("camp_action_resolved", {
        action = "fletch_arrows",
        actor = actor,
        previousAmmo = previousAmmo,
        ammo = actor.ammo,
        ammunition = actor.ammunition,
        refilledAmmunition = refilled,
        result = "ammo_refilled",
    })

    print("[CAMP] " .. actor.name .. " fletches ammunition (ammo: " .. actor.ammo .. ")")

    return true, "ammo_refilled"
end

--------------------------------------------------------------------------------
-- USE AN ITEM (S8.3)
--------------------------------------------------------------------------------
-- Implements healthful Camp items currently called out by the rulebook.

function M.getUseItemOptions(actor, opts)
    opts = opts or {}

    local selectedItem = opts.item or opts.selectedItem or opts.campItem
    local selectedItemId = opts.itemId or opts.selectedItemId or opts.campItemId or
        (type(selectedItem) == "table" and selectedItem.id or selectedItem)
    local guildMembers = {}
    local seenMembers = {}
    local function addGuildMember(member)
        if not member then
            return
        end
        local key = member.id or member
        if seenMembers[key] then
            return
        end
        seenMembers[key] = true
        guildMembers[#guildMembers + 1] = member
    end
    if type(opts.guild) == "table" then
        for _, member in ipairs(opts.guild) do
            addGuildMember(member)
        end
    end
    addGuildMember(actor)

    local function entityOption(entity)
        local stressed = entity and ((entity.conditions and entity.conditions.stressed) or entity.stressed) == true
        return {
            id = entity and entity.id or nil,
            name = entity and entity.name or nil,
            isActor = entity == actor,
            stressed = stressed,
        }
    end

    local function sortedAfflictionOptions(entity)
        local options = {}
        if type(entity and entity.afflictions) ~= "table" then
            return options
        end

        for afflictionName, affliction in pairs(entity.afflictions) do
            if affliction ~= nil and affliction ~= false then
                local data = type(affliction) == "table" and affliction or {}
                options[#options + 1] = {
                    id = data.id or data.afflictionId or afflictionName,
                    name = data.name or data.afflictionName or afflictionName,
                    stage = data.stage,
                    maxStage = data.maxStage,
                    cureCharges = data.cureCharges or 0,
                    curedThisCamp = data.curedThisCamp == true,
                }
            end
        end

        table.sort(options, function(a, b)
            return tostring(a.name or a.id or "") < tostring(b.name or b.id or "")
        end)
        return options
    end

    local function huntedGameCount(item)
        local meals = item and item.properties and item.properties.meals
        if meals == "guild" then
            return math.max(1, math.floor(tonumber(opts.guildSize) or #guildMembers or 1))
        end
        return math.max(1, math.floor(tonumber(meals) or 1))
    end

    local function selectedMatches(item)
        return item and ((selectedItemId and item.id == selectedItemId) or
            (type(selectedItem) == "table" and selectedItem == item))
    end

    local itemOptions = {}
    local unavailableReasons = {}
    local unavailableSeen = {}
    local selectedOption = nil
    local resolvableCount = 0
    local function addUnavailable(reason)
        if reason and not unavailableSeen[reason] then
            unavailableSeen[reason] = true
            unavailableReasons[#unavailableReasons + 1] = reason
        end
    end

    if not actor then
        addUnavailable("no_actor")
    elseif not actor.inventory then
        addUnavailable("no_inventory")
    end

    for _, entry in ipairs(campInventoryEntries(actor)) do
        local item = entry.item
        local props = item and item.properties or {}
        local option = nil
        if item and isPipeweedStressItem(item) then
            local target = entityOption(actor)
            target.resultPreview = target.stressed and "stress_cleared" or "pipeweed_no_effect"
            option = campItemOption(item, entry.location)
            option.kind = "pipeweed"
            option.consumedOnAttempt = props.consumeOnAttempt == true or props.consumable == true
            option.requiresTargetSelection = false
            option.targetOptions = { target }
            option.resultPreview = target.resultPreview
            option.actionDataPreview = {
                type = "use_item",
                itemId = item.id,
            }
        elseif item and props.leeches == true then
            local targetOptions = {}
            for _, member in ipairs(guildMembers) do
                local afflictions = sortedAfflictionOptions(member)
                if #afflictions > 0 then
                    local targetOption = entityOption(member)
                    targetOption.afflictionOptions = afflictions
                    targetOptions[#targetOptions + 1] = targetOption
                end
            end

            local drawOptions = {}
            for _, suit in ipairs({
                constants.SUITS.SWORDS,
                constants.SUITS.PENTACLES,
                constants.SUITS.CUPS,
                constants.SUITS.WANDS,
            }) do
                local charges = leechesGrantCharges({ suit = suit }) and
                    (tonumber(props.afflictionCureCharges) or 2) or 0
                drawOptions[#drawOptions + 1] = {
                    suit = suit,
                    suitName = constants.SUIT_NAMES[suit],
                    charges = charges,
                    resultPreview = charges > 0 and "affliction_charged" or "leeches_no_effect",
                    actionDataPreview = {
                        type = "use_item",
                        itemId = item.id,
                        card = { suit = suit },
                    },
                }
            end

            option = campItemOption(item, entry.location)
            option.kind = "leeches"
            option.consumedOnAttempt = props.consumeOnAttempt == true or props.consumable == true
            option.requiresTargetSelection = true
            option.requiresAfflictionSelection = true
            option.requiresMinorArcanaDraw = true
            option.targetOptions = targetOptions
            option.drawOptions = drawOptions
            option.hasTargetAfflictions = #targetOptions > 0
            option.resultPreview = #targetOptions > 0 and "affliction_charged" or "no_affliction_target"
            if #targetOptions == 0 then
                option.disabled = true
                option.unavailableReason = "no_affliction_target"
            end
        elseif item and isTinkersKitItem(item) then
            local repairOptions = M.getRepairOptions(actor)
            option = campItemOption(item, entry.location)
            option.kind = "tinkers_kit"
            option.consumedOnAttempt = false
            option.requiresRepairTarget = true
            option.repairTargets = repairOptions.repairTargets or {}
            option.blockedRepairTargets = repairOptions.blockedTargets or {}
            option.hasRepairTargets = #option.repairTargets > 0
            option.resultPreview = option.hasRepairTargets and "repaired" or "no_notched_equipment"
            option.rules = repairOptions.rules
            if not option.hasRepairTargets then
                option.disabled = true
                option.unavailableReason = "no_notched_equipment"
            end
        elseif item and isFreshGame(item) then
            local preparationOptions = {}
            local count = huntedGameCount(item)
            if hasCookingGear(actor) then
                preparationOptions[#preparationOptions + 1] = {
                    id = "cook",
                    name = "Cook",
                    preparation = "cook",
                    resultPreview = "game_cooked",
                    mealCountPreview = count,
                    requiresCookingGear = true,
                    actionDataPreview = {
                        type = "use_item",
                        itemId = item.id,
                        preparation = "cook",
                    },
                }
            end
            local salt = findSaltItem(actor)
            if salt then
                preparationOptions[#preparationOptions + 1] = {
                    id = "preserve",
                    name = "Preserve with Salt",
                    preparation = "preserve",
                    resultPreview = "game_preserved",
                    rationCountPreview = count,
                    requiresSalt = true,
                    saltItem = campItemOption(salt, nil),
                    actionDataPreview = {
                        type = "use_item",
                        itemId = item.id,
                        preparation = "preserve",
                    },
                }
            end

            option = campItemOption(item, entry.location)
            option.kind = "fresh_game"
            option.consumedOnAttempt = true
            option.requiresPreparation = true
            option.preparationOptions = preparationOptions
            option.hasPreparationOptions = #preparationOptions > 0
            option.mealCountPreview = count
            option.resultPreview = #preparationOptions > 0 and "game_prepared" or "requires_cooking_gear_or_salt"
            if #preparationOptions == 0 then
                option.disabled = true
                option.unavailableReason = "requires_cooking_gear_or_salt"
            end
        elseif item and props.campUse == true then
            option = campItemOption(item, entry.location)
            option.kind = "camp_use"
            option.disabled = true
            option.unavailableReason = "item_has_no_camp_resolver"
            option.resultPreview = "item_has_no_camp_resolver"
        end

        if option then
            option.action = "use_item"
            itemOptions[#itemOptions + 1] = option
            if option.disabled then
                addUnavailable(option.unavailableReason)
            else
                resolvableCount = resolvableCount + 1
            end
            if selectedMatches(item) then
                selectedOption = option
            end
        end
    end

    if #itemOptions == 0 then
        addUnavailable("no_usable_camp_items")
    end
    if selectedItemId and not selectedOption then
        addUnavailable("selected_item_not_usable")
    elseif selectedOption and selectedOption.disabled then
        addUnavailable("selected_item_unavailable")
    end

    return {
        result = "camp_use_item_options_ready",
        actor = actor,
        actorId = actor and actor.id or nil,
        actorName = actor and actor.name or nil,
        hasUsableItems = #itemOptions > 0,
        hasResolvableOptions = resolvableCount > 0,
        disabled = resolvableCount == 0,
        unavailableReasons = unavailableReasons,
        itemOptions = itemOptions,
        selectedItem = selectedOption,
        rules = {
            pipeweedClearsStress = true,
            pipeweedTargetsSelf = true,
            leechesDrawMinorArcana = true,
            leechesGrantChargesOnCupsOrWands = true,
            leechesNoEffectOnSwordsOrPentacles = true,
            tinkersKitRepairsOneNotch = true,
            freshGameCanBeCookedOrPreserved = true,
            freshGameCookRequiresCookingGear = true,
            freshGamePreserveRequiresSalt = true,
        },
    }
end

function M.resolveUseItem(actor, target, actionData, context, eventBus)
    context = context or {}
    local item = actionData.item
    local itemLocation = nil
    if not item then
        item, itemLocation = findCampActionItem(actor, actionData.itemId)
    elseif actor and actor.inventory and actor.inventory.findItem then
        _, itemLocation = actor.inventory:findItem(item.id)
    end

    if not item then
        return false, "No usable camp item selected"
    end
    if not itemLocation then
        return false, "Item is not carried"
    end

    local props = item.properties or {}
    if props.leeches ~= true and not isPipeweedStressItem(item) and not isTinkersKitItem(item) and
       not canPrepareHuntedGame(actor, item) then
        return false, "Item is not usable during Camp"
    end

    local requestedTarget = target
    target = target or actor
    if not target then
        return false, "No target for item"
    end

    if isFreshGame(item) then
        local preparation = actionData.preparation or actionData.gamePreparation or actionData.method
        preparation = preparation and tostring(preparation):lower():gsub("%s+", "_")
        if not preparation then
            local canCook = hasCookingGear(actor)
            local canPreserve = findSaltItem(actor) ~= nil
            if canCook and not canPreserve then
                preparation = "cook"
            elseif canPreserve and not canCook then
                preparation = "preserve"
            end
        end

        if preparation == "cook" or preparation == "cooking" then
            return M.resolveCookHuntedGame(actor, item, context, eventBus)
        elseif preparation == "preserve" or preparation == "salt" or preparation == "salted" then
            return M.resolvePreserveHuntedGame(actor, item, context, eventBus)
        end

        return false, "Game preparation required"
    end

    if isPipeweedStressItem(item) then
        local result = "pipeweed_no_effect"
        local cleared = false
        target.conditions = target.conditions or {}
        if target.conditions.stressed or target.stressed then
            target.conditions.stressed = false
            target.stressed = false
            result = "stress_cleared"
            cleared = true
        end

        if props.consumeOnAttempt or props.consumable then
            consumeCampItem(actor, item)
        end

        eventBus:emit("camp_action_resolved", {
            action = "use_item",
            item = item,
            itemId = item.id,
            actor = actor,
            target = target,
            cleared = cleared and "stressed" or nil,
            result = result,
        })

        print("[CAMP] " .. actor.name .. " uses " .. (item.name or "item") .. " (" .. result .. ")")

        return true, result
    end

    if isTinkersKitItem(item) then
        local repairTarget = actionData.targetItem or actionData.itemToRepair or actionData.repairTarget or requestedTarget
        return M.resolveRepair(actor, repairTarget, eventBus, {
            action = "use_item",
            item = item,
            itemId = item.id,
        })
    end

    local card, shouldDiscard, drawnDeck = drawMinorCard(actionData, context)
    if not card then
        return false, "Requires minor arcana draw"
    end

    local charges = leechesGrantCharges(card) and (tonumber(props.afflictionCureCharges) or 2) or 0
    local result = "leeches_no_effect"
    local cureResult = nil
    if charges > 0 then
        local controller = context.campController
        if not controller or not controller.applyAfflictionCharges then
            return false, "No affliction recovery controller"
        end

        local ok, applied = controller:applyAfflictionCharges(
            target,
            actionData.affliction or actionData.afflictionName or actionData.targetAffliction,
            charges,
            "leeches"
        )
        if not ok then
            return false, applied
        end

        cureResult = applied
        result = applied.result
    end

    if shouldDiscard and drawnDeck and drawnDeck.discard then
        drawnDeck:discard(card)
    end
    if props.consumeOnAttempt or props.consumable then
        consumeCampItem(actor, item)
    end

    eventBus:emit("camp_action_resolved", {
        action = "use_item",
        item = item,
        itemId = item.id,
        actor = actor,
        target = target,
        card = card,
        charges = charges,
        cureResult = cureResult,
        result = result,
    })

    print("[CAMP] " .. actor.name .. " uses " .. (item.name or "item") .. " (" .. result .. ")")

    return true, result
end

--------------------------------------------------------------------------------
-- FELLOWSHIP (S8.3)
--------------------------------------------------------------------------------
-- Target another PC. Both charge a Bond with each other.

function M.getFellowshipOptions(actor, guild, opts)
    opts = opts or {}
    if type(guild) ~= "table" and type(opts.guild) == "table" then
        guild = opts.guild
    end
    guild = type(guild) == "table" and guild or {}

    local selectedTarget = opts.target or opts.targetPC or opts.guildMate
    local selectedTargetId = opts.targetId or opts.targetPCId or opts.guildMateId or
        (type(selectedTarget) == "table" and selectedTarget.id or selectedTarget)
    local targetOptions = {}
    local blockedTargets = {}
    local unavailableReasons = {}
    local unavailableSeen = {}
    local selectedOption = nil
    local function addUnavailable(reason)
        if reason and not unavailableSeen[reason] then
            unavailableSeen[reason] = true
            unavailableReasons[#unavailableReasons + 1] = reason
        end
    end
    local function bondState(source, target)
        local bond = source and target and source.bonds and source.bonds[target.id]
        return {
            exists = bond ~= nil,
            name = bond and bond.name or (target and target.name or nil),
            charged = bond and bond.charged == true or false,
        }
    end
    local function makeTargetOption(target)
        local actorBond = bondState(actor, target)
        local targetBond = bondState(target, actor)
        return {
            id = target and target.id or nil,
            name = target and target.name or nil,
            isAdventurer = isAdventurer(target),
            isGuildMate = guildContains(guild, target),
            actorBond = actorBond,
            targetBond = targetBond,
            alreadyCharged = actorBond.charged or targetBond.charged,
            resultPreview = "bonds_charged",
            actionDataPreview = {
                type = "fellowship",
                targetId = target and target.id or nil,
            },
        }
    end

    if not isAdventurer(actor) then
        addUnavailable("fellowship_requires_adventurer")
    end

    for _, member in ipairs(guild) do
        local isSelf = actor and member and (member == actor or (actor.id and member.id == actor.id))
        if member and not isSelf then
            local option = makeTargetOption(member)
            if not option.isAdventurer then
                option.disabled = true
                option.unavailableReason = "target_must_be_adventurer"
                blockedTargets[#blockedTargets + 1] = option
            else
                targetOptions[#targetOptions + 1] = option
            end
            if (selectedTargetId and member.id == selectedTargetId) or
               (type(selectedTarget) == "table" and selectedTarget == member) then
                selectedOption = option
            end
        end
    end

    if #targetOptions == 0 then
        addUnavailable("no_fellowship_targets")
    end
    if selectedTargetId and not selectedOption then
        addUnavailable("selected_target_not_guild_mate")
    elseif selectedOption and selectedOption.disabled then
        addUnavailable(selectedOption.unavailableReason or "selected_target_unavailable")
    end

    return {
        result = "fellowship_options_ready",
        actor = actor,
        actorId = actor and actor.id or nil,
        actorName = actor and actor.name or nil,
        hasTargets = #targetOptions > 0,
        disabled = #targetOptions == 0 or not isAdventurer(actor),
        unavailableReasons = unavailableReasons,
        targetOptions = targetOptions,
        blockedTargets = blockedTargets,
        selectedTarget = selectedOption,
        roleplayPrompts = {
            { id = "share_memory", label = "Share a memory" },
            { id = "talk_quests", label = "Talk about a quest" },
            { id = "ask_childhood", label = "Ask about childhood" },
            { id = "tell_childhood", label = "Tell about childhood" },
            { id = "close_scene", label = "Close the scene clearly" },
        },
        rules = {
            requiresAdventurer = true,
            requiresGuildMate = true,
            requiresOtherAdventurer = true,
            chargesReciprocalBonds = true,
            roleplayExchangeRequired = true,
        },
    }
end

function M.resolveFellowship(actor, targetPC, eventBus, context)
    eventBus = eventBus or events.globalBus
    context = context or {}

    if not isAdventurer(actor) then
        return false, "Fellowship requires an adventurer"
    end

    if not targetPC then
        return false, "No companion targeted for fellowship"
    end

    if actor.id == targetPC.id then
        return false, "Cannot fellowship with yourself"
    end

    if not isAdventurer(targetPC) then
        return false, "Fellowship target must be an adventurer"
    end

    if type(context.guild) == "table" and
        (not guildContains(context.guild, actor) or not guildContains(context.guild, targetPC)) then
        return false, "Fellowship requires a guild-mate"
    end

    -- Initialize bonds tables if needed
    if not actor.bonds then actor.bonds = {} end
    if not targetPC.bonds then targetPC.bonds = {} end

    -- Initialize specific bonds if they don't exist
    if not actor.bonds[targetPC.id] then
        actor.bonds[targetPC.id] = { charged = false, name = targetPC.name }
    end
    if not targetPC.bonds[actor.id] then
        targetPC.bonds[actor.id] = { charged = false, name = actor.name }
    end

    -- Charge both bonds
    actor.bonds[targetPC.id].charged = true
    targetPC.bonds[actor.id].charged = true

    eventBus:emit("camp_action_resolved", {
        action = "fellowship",
        actor = actor,
        target = targetPC,
        result = "bonds_charged",
    })

    print("[CAMP] " .. actor.name .. " and " .. targetPC.name .. " share fellowship (bonds charged)")

    return true, "fellowship_complete"
end

--------------------------------------------------------------------------------
-- TRAIN (S8.3)
--------------------------------------------------------------------------------
-- Invest XP into a mentored talent. Both trainer and trainee spend Camp Actions.

local function getTalentRecord(entity, talentId)
    if not entity or not entity.talents then
        return nil, nil
    end

    local requested = talent_catalog.normalizeId(talentId)
    for key, talent in pairs(entity.talents) do
        if talent_catalog.normalizeId(key) == requested then
            return talent, key
        end
        if type(talent) == "table" and
           talent_catalog.normalizeId(talent.id or talent.name or talent.talentId) == requested then
            return talent, key
        end
    end

    return nil, nil
end

local function normalizeTalentId(talentId)
    return talent_catalog.normalizeId(talentId)
end

local CAMP_TALENTS = {
    beast_master = true,
    bookworm = true,
    chirurgeon = true,
    high_chant = true,
    loremaster = true,
    sneak = true,
    war_stories = true,
}

local function isTalentUsable(entity, talentId)
    local talent = getTalentRecord(entity, talentId)
    if not talent then
        return false
    end
    if type(talent) == "table" then
        return talent.wounded ~= true
    end
    return talent == true
end

local function hasUsableTalent(actor, requestedTalentId)
    local requested = normalizeTalentId(requestedTalentId)
    for talentId in pairs(actor and actor.talents or {}) do
        if normalizeTalentId(talentId) == requested and isTalentUsable(actor, talentId) then
            return true, talentId
        end
    end
    return false, nil
end

function M.hasCampTalent(actor)
    for talentId in pairs(actor and actor.talents or {}) do
        if CAMP_TALENTS[normalizeTalentId(talentId)] and isTalentUsable(actor, talentId) then
            return true
        end
    end
    return false
end

function M.getCampTalentOptions(actor)
    local options = {}
    for talentId, talent in pairs(actor and actor.talents or {}) do
        local normalized = normalizeTalentId(talentId)
        if normalized == "" and type(talent) == "table" then
            normalized = normalizeTalentId(talent.id or talent.name or talent.talentId)
        end
        if CAMP_TALENTS[normalized] and isTalentUsable(actor, talentId) then
            options[#options + 1] = {
                id = normalized,
                key = talentId,
                talent = talent,
            }
        end
    end
    table.sort(options, function(a, b)
        return (a.id or "") < (b.id or "")
    end)
    return options
end

local function findCampTalent(actor, requestedTalentId)
    local requested = normalizeTalentId(requestedTalentId)
    for talentId in pairs(actor and actor.talents or {}) do
        local normalized = normalizeTalentId(talentId)
        if CAMP_TALENTS[normalized] and isTalentUsable(actor, talentId) then
            if requested == "" or requested == normalized then
                return normalized, talentId
            end
        end
    end
    return nil, nil
end

local function isTalentMastered(entity, talentId)
    if entity and entity.isTalentMastered then
        return entity:isTalentMastered(talentId)
    end

    local talent = getTalentRecord(entity, talentId)
    if type(talent) == "table" then
        return talent.mastered == true
    end
    return talent == true
end

function M.hasAlchemyTalent(actor)
    return hasUsableTalent(actor, "alchemy")
end

local function isAlchemyKit(item)
    local props = item and item.properties or {}
    return item and (
        item.templateId == "alchemy_kit" or
        item.type == "alchemy_kit" or
        props.alchemyKit == true or
        props.toolType == "alchemy"
    )
end

function M.hasAlchemyKit(actor)
    local inv = actor and actor.inventory
    if not inv or not inv.findItemByPredicate then
        return false
    end
    return inv:findItemByPredicate(isAlchemyKit) ~= nil
end

local function getBrewOutputs(item)
    local props = item and item.properties or {}
    return props.brewOutputs or props.alchemyOutputs
end

local function isAlchemyReagent(item)
    local props = item and item.properties or {}
    local outputs = getBrewOutputs(item)
    return item and type(outputs) == "table" and (
        item.type == "reagent" or
        props.reagent == true or
        props.alchemicalReagent == true
    )
end

local function isHermeticAlchemyReagent(item)
    local props = item and item.properties or {}
    return isAlchemyReagent(item) and props.hermeticBottle == true
end

local function listBrewForms(outputs)
    local forms = {}
    for _, form in ipairs({ "potion", "bomb", "oil" }) do
        if outputs and outputs[form] then
            forms[#forms + 1] = form
        end
    end
    return forms
end

function M.getBrewableReagents(actor)
    local inv = actor and actor.inventory
    if not inv or not inv.getAllItems then
        return {}
    end

    local reagents = {}
    for _, entry in ipairs(inv:getAllItems()) do
        local item = entry.item
        if isHermeticAlchemyReagent(item) then
            local props = item.properties or {}
            local outputs = getBrewOutputs(item)
            reagents[#reagents + 1] = {
                item = item,
                itemId = item.id,
                templateId = item.templateId,
                name = item.name,
                location = entry.location,
                source = props.source,
                forms = listBrewForms(outputs),
            }
        end
    end

    return reagents
end

function M.hasAlchemyReagent(actor)
    return #M.getBrewableReagents(actor) > 0
end

function M.hasUnpreservedAlchemyReagent(actor)
    local inv = actor and actor.inventory
    if not inv or not inv.getAllItems then
        return false
    end

    for _, entry in ipairs(inv:getAllItems()) do
        local item = entry.item
        if isAlchemyReagent(item) and not isHermeticAlchemyReagent(item) then
            return true
        end
    end

    return false
end

function M.canBrewAlchemy(actor)
    return M.hasAlchemyTalent(actor) and M.hasAlchemyKit(actor) and M.hasAlchemyReagent(actor)
end

local function normalizeAlchemyForm(form)
    local value = tostring(form or ""):lower():gsub("%s+", "_")
    if value == "p" or value == "potions" then
        return "potion"
    elseif value == "b" or value == "bombs" then
        return "bomb"
    elseif value == "o" or value == "oils" then
        return "oil"
    elseif value == "potion" or value == "bomb" or value == "oil" then
        return value
    end
    return nil
end

local function requestForm(request, defaultForm)
    return normalizeAlchemyForm(
        request.form or
        request.substanceType or
        request.alchemicalType or
        request.outputType or
        request.kind or
        request.substance or
        defaultForm
    )
end

local function collectBrewRequests(actionData)
    local request = actionData.request or actionData.brewRequest or actionData
    local batch = request.brews or request.transforms or request.reagents or
        actionData.brews or actionData.transforms or actionData.reagents
    local requests = {}

    if type(batch) == "table" and #batch > 0 then
        for _, entry in ipairs(batch) do
            if type(entry) == "table" then
                requests[#requests + 1] = entry
            else
                requests[#requests + 1] = { reagentId = entry }
            end
        end
        return requests
    end

    if request.reagent or request.reagentId or request.itemId or request.source or request.form or
        request.substanceType or request.alchemicalType or request.outputType or request.kind then
        requests[#requests + 1] = request
    end

    return requests
end

local function normalizeKey(value)
    return tostring(value or ""):lower():gsub("%s+", "_")
end

local function matchesReagentRequest(item, request)
    local props = item.properties or {}
    local wantedId = request.reagentId or request.itemId or request.id
    if wantedId and item.id ~= wantedId then
        return false
    end

    local wantedTemplate = request.templateId or request.reagentTemplateId
    if wantedTemplate and item.templateId ~= wantedTemplate then
        return false
    end

    local wantedSource = request.source or request.creature or request.reagentSource
    if wantedSource and normalizeKey(props.source or item.templateId or item.name) ~= normalizeKey(wantedSource) then
        return false
    end

    return true
end

local function findAlchemyReagent(actor, request, used)
    local inv = actor and actor.inventory
    if not inv or not inv.getAllItems then
        return nil, nil
    end

    if type(request.reagent) == "table" then
        local item = request.reagent
        local carried, location = inv:findItem(item.id)
        if carried and isHermeticAlchemyReagent(carried) and not used[carried.id] then
            return carried, location
        end
        if carried and isAlchemyReagent(carried) then
            return nil, nil, "Requires hermetic reagent"
        end
        return nil, nil
    end

    local foundUnpreserved = false
    for _, entry in ipairs(inv:getAllItems()) do
        local item = entry.item
        if isAlchemyReagent(item) and not used[item.id] and matchesReagentRequest(item, request) then
            if isHermeticAlchemyReagent(item) then
                return item, entry.location
            end
            foundUnpreserved = true
        end
    end

    if foundUnpreserved then
        return nil, nil, "Requires hermetic reagent"
    end

    return nil, nil
end

function M.getBrewAlchemyOptions(actor, actionData, context)
    actionData = actionData or {}
    context = context or {}

    local itemTemplates = require('data.item_templates')
    local unavailableReasons = {}
    local function addReason(reason)
        for _, existing in ipairs(unavailableReasons) do
            if existing == reason then
                return
            end
        end
        unavailableReasons[#unavailableReasons + 1] = reason
    end

    local hasTalent = M.hasAlchemyTalent(actor)
    local hasKit = M.hasAlchemyKit(actor)
    local brewable = M.getBrewableReagents(actor)
    local hasHermeticReagents = #brewable > 0
    local hasUnpreservedReagents = M.hasUnpreservedAlchemyReagent(actor)

    if not actor then
        addReason("no_actor")
    end
    if not hasTalent then
        addReason("requires_alchemy_talent")
    end
    if not hasKit then
        addReason("requires_alchemy_kit")
    end
    if not hasHermeticReagents then
        addReason(hasUnpreservedReagents and "requires_hermetic_reagent" or "requires_alchemical_reagent")
    end

    local selectedRaw = collectBrewRequests(actionData)
    local defaultForm = requestForm(actionData, context.defaultAlchemyForm)
    local selectedBrews = {}
    local selectedByItemId = {}
    local used = {}
    local selectedDisabled = false

    local function outputPreview(templateId)
        local template = templateId and itemTemplates.getTemplate(templateId)
        if not template then
            return nil
        end
        local props = template.properties or {}
        local effect = props.useEffect or {}
        return {
            templateId = templateId,
            name = template.name,
            size = template.size,
            stackable = template.stackable == true,
            source = props.source,
            form = props.potion and "potion" or props.bomb and "bomb" or props.oil and "oil" or nil,
            effectType = effect.type,
            target = effect.target,
        }
    end

    local function capacityPreview(reagent, location, output)
        local inv = actor and actor.inventory
        local replacesBottle = not (reagent and reagent.stackable and (reagent.quantity or 1) > 1)
        local slotsRequired = replacesBottle and 0 or math.max(1, tonumber(output and output.size) or 1)
        local available = nil
        if inv and inv.availableSlots and location then
            available = inv:availableSlots(location)
        end
        return {
            location = location,
            usesExistingHermeticBottle = true,
            replacesBottle = replacesBottle,
            additionalSlotsRequired = slotsRequired,
            availableSlots = available,
            sufficientSlots = available == nil or available >= slotsRequired,
        }
    end

    for _, request in ipairs(selectedRaw) do
        local form = requestForm(request, defaultForm)
        local reagent, location, reagentError = findAlchemyReagent(actor, request, used)
        local brew = {
            request = {
                reagentId = request.reagentId or request.itemId or request.id,
                templateId = request.templateId or request.reagentTemplateId,
                source = request.source or request.creature or request.reagentSource,
                form = form,
            },
            form = form,
            disabled = false,
        }

        if not form then
            brew.disabled = true
            brew.unavailableReason = "Choose potion, bomb, or oil"
        elseif not reagent then
            brew.disabled = true
            brew.unavailableReason = reagentError or "Requires alchemical reagent"
        else
            local outputs = getBrewOutputs(reagent)
            local outputTemplateId = outputs and outputs[form]
            brew.reagent = campItemOption(reagent, location)
            brew.reagent.source = (reagent.properties or {}).source
            brew.outputTemplateId = outputTemplateId
            brew.outputPreview = outputPreview(outputTemplateId)
            brew.capacity = capacityPreview(reagent, location, brew.outputPreview)
            brew.actionDataPreview = {
                type = "brew_alchemy",
                reagentId = reagent.id,
                form = form,
            }

            if not outputTemplateId then
                brew.disabled = true
                brew.unavailableReason = "Reagent cannot brew that substance"
            elseif not itemTemplates.hasTemplate(outputTemplateId) then
                brew.disabled = true
                brew.unavailableReason = "Unknown alchemical substance"
            elseif brew.capacity and brew.capacity.sufficientSlots == false then
                brew.disabled = true
                brew.unavailableReason = "insufficient_slots"
            else
                used[reagent.id] = true
                selectedByItemId[reagent.id] = form
            end
        end

        if brew.disabled then
            selectedDisabled = true
        end
        selectedBrews[#selectedBrews + 1] = brew
    end

    local reagentOptions = {}
    for _, entry in ipairs(brewable) do
        local item = entry.item
        local outputs = getBrewOutputs(item)
        local option = campItemOption(item, entry.location)
        option.source = entry.source
        option.hermeticBottle = true
        option.formOptions = {}
        option.actionDataPreview = {
            type = "brew_alchemy",
            reagentId = item.id,
        }
        for _, form in ipairs({ "potion", "bomb", "oil" }) do
            local outputTemplateId = outputs and outputs[form]
            local output = outputPreview(outputTemplateId)
            option.formOptions[#option.formOptions + 1] = {
                form = form,
                available = outputTemplateId ~= nil,
                selected = selectedByItemId[item.id] == form,
                outputTemplateId = outputTemplateId,
                outputPreview = output,
                actionDataPreview = outputTemplateId and {
                    type = "brew_alchemy",
                    reagentId = item.id,
                    form = form,
                } or nil,
            }
        end
        option.forms = listBrewForms(outputs)
        reagentOptions[#reagentOptions + 1] = option
    end

    local unpreservedReagentOptions = {}
    for _, entry in ipairs(campInventoryEntries(actor)) do
        local item = entry.item
        if isAlchemyReagent(item) and not isHermeticAlchemyReagent(item) then
            local option = campItemOption(item, entry.location)
            option.source = (item.properties or {}).source
            option.hermeticBottle = false
            option.disabled = true
            option.unavailableReason = "Requires hermetic reagent"
            unpreservedReagentOptions[#unpreservedReagentOptions + 1] = option
        end
    end

    local disabled = #unavailableReasons > 0 or selectedDisabled
    return {
        result = "brew_alchemy_options_ready",
        actor = actor,
        actorId = actor and actor.id or nil,
        actorName = actor and actor.name or nil,
        disabled = disabled,
        unavailableReasons = unavailableReasons,
        hasAlchemyTalent = hasTalent,
        hasAlchemyKit = hasKit,
        hasHermeticReagents = hasHermeticReagents,
        hasUnpreservedAlchemyReagents = hasUnpreservedReagents,
        requiresBrews = #selectedRaw == 0,
        selectedForm = defaultForm,
        selectedBrews = selectedBrews,
        reagentOptions = reagentOptions,
        unpreservedReagentOptions = unpreservedReagentOptions,
        rules = {
            requiresAlchemyTalent = true,
            requiresAlchemyKit = true,
            requiresHermeticBottle = true,
            usesExistingHermeticBottle = true,
            validForms = { "potion", "bomb", "oil" },
        },
    }
end

local function replaceInventoryItem(inv, itemId, outputItem, location)
    local locations = location and { location } or { "hands", "belt", "pack" }
    for _, loc in ipairs(locations) do
        for i, item in ipairs(inv[loc] or {}) do
            if item.id == itemId then
                if item.stackable and (item.quantity or 1) > 1 then
                    item.quantity = item.quantity - 1
                    local added, err = inv:addItem(outputItem, loc)
                    if not added then
                        item.quantity = item.quantity + 1
                        return false, err
                    end
                    return true, loc
                end

                inv[loc][i] = outputItem
                return true, loc
            end
        end
    end

    return false, "reagent_not_found"
end

local function getAvailableXP(actor)
    if actor.xp ~= nil then
        return actor.xp, "xp"
    end
    return actor.experience or 0, "experience"
end

local function spendXP(actor, amount)
    local xp, field = getAvailableXP(actor)
    if xp < amount then
        return false
    end
    actor[field] = xp - amount
    return true
end

local function requestedTrainingXP(request)
    local rawAmount = request.xp or request.amount or request.xpInvested
    local xpAmount = tonumber(rawAmount)
    if not xpAmount then
        xpAmount = 1
    end
    if xpAmount < 1 or xpAmount ~= math.floor(xpAmount) then
        return nil, "Training XP must be a positive whole number"
    end
    return xpAmount
end

--------------------------------------------------------------------------------
-- BREW ALCHEMY (S8.3)
--------------------------------------------------------------------------------
-- Transform one or more bottled reagents into alchemical substances.

function M.resolveBrewAlchemy(actor, actionData, context, eventBus)
    context = context or {}
    eventBus = eventBus or context.eventBus or events.globalBus
    actionData = actionData or {}

    if not M.hasAlchemyTalent(actor) then
        return false, "Requires Alchemy talent"
    end

    if not M.hasAlchemyKit(actor) then
        return false, "Requires alchemy kit"
    end

    local brewable = M.getBrewableReagents(actor)
    if #brewable == 0 then
        if M.hasUnpreservedAlchemyReagent(actor) then
            return false, "Requires hermetic reagent"
        end
        return false, "Requires alchemical reagent"
    end

    local requests = collectBrewRequests(actionData)
    if #requests == 0 then
        actor.lastBrewAlchemyResult = {
            result = "alchemy_choices_required",
            reagents = brewable,
        }
        eventBus:emit("camp_action_resolved", {
            action = "brew_alchemy",
            actor = actor,
            result = "alchemy_choices_required",
            requiresBrews = true,
            reagents = brewable,
        })
        return true, "alchemy_choices_required", brewable
    end

    local defaultForm = requestForm(actionData, context.defaultAlchemyForm)
    local used = {}
    local plan = {}
    local itemTemplates = require('data.item_templates')

    for _, request in ipairs(requests) do
        local form = requestForm(request, defaultForm)
        if not form then
            return false, "Choose potion, bomb, or oil"
        end

        local reagent, location, reagentError = findAlchemyReagent(actor, request, used)
        if not reagent then
            return false, reagentError or "Requires alchemical reagent"
        end

        local outputs = getBrewOutputs(reagent)
        local outputTemplateId = outputs and outputs[form]
        if not outputTemplateId then
            return false, "Reagent cannot brew that substance"
        end

        if not itemTemplates.hasTemplate(outputTemplateId) then
            return false, "Unknown alchemical substance"
        end

        used[reagent.id] = true
        plan[#plan + 1] = {
            reagent = reagent,
            location = location,
            form = form,
            outputTemplateId = outputTemplateId,
        }
    end

    local brewed = {}
    for _, step in ipairs(plan) do
        local outputItem = inventory.createItemFromTemplate(step.outputTemplateId)
        if not outputItem then
            return false, "Unknown alchemical substance"
        end

        outputItem.properties = outputItem.properties or {}
        outputItem.properties.hermeticBottle = true
        outputItem.properties.brewedFrom = step.reagent.name
        outputItem.properties.sourceReagentId = step.reagent.id

        local replaced, err = replaceInventoryItem(actor.inventory, step.reagent.id, outputItem, step.location)
        if not replaced then
            return false, err or "Could not replace reagent"
        end

        brewed[#brewed + 1] = {
            reagentId = step.reagent.id,
            reagentName = step.reagent.name,
            source = (step.reagent.properties or {}).source,
            form = step.form,
            item = outputItem,
            itemId = outputItem.id,
            templateId = step.outputTemplateId,
            location = step.location,
        }
    end

    actor.lastBrewAlchemyResult = {
        result = "alchemy_brewed",
        brews = brewed,
    }

    eventBus:emit("camp_action_resolved", {
        action = "brew_alchemy",
        actor = actor,
        result = "alchemy_brewed",
        brews = brewed,
    })

    print("[CAMP] " .. actor.name .. " brews " .. #brewed .. " alchemical substance(s)")

    return true, "alchemy_brewed", brewed
end

function M.getTrainOptions(actor, guild, opts)
    opts = opts or {}
    if type(guild) ~= "table" and type(opts.guild) == "table" then
        guild = opts.guild
    end
    guild = type(guild) == "table" and guild or {}

    local unavailableReasons = {}
    local function addUnavailable(reason)
        if not reason then
            return
        end
        for _, existing in ipairs(unavailableReasons) do
            if existing == reason then
                return
            end
        end
        unavailableReasons[#unavailableReasons + 1] = reason
    end

    local selectedTrainer = opts.trainer or opts.target or opts.guildMate
    local selectedTrainerId = opts.trainerId or opts.targetId or opts.guildMateId or
        (type(selectedTrainer) == "table" and selectedTrainer.id or selectedTrainer)
    local request = opts.request or opts.training or opts
    local selectedTalentId = normalizeTalentId(request.talentId or request.talent or request.id)
    local selectedXP, selectedXPError = requestedTrainingXP(request)
    local xpRequested = request.xp ~= nil or request.amount ~= nil or request.xpInvested ~= nil
    if not xpRequested then
        selectedXP = nil
        selectedXPError = nil
    end

    local completed = opts.actionsCompleted or {}
    local actorCompleted = actor and actor.id and completed[actor.id] ~= nil
    local availableXP = select(1, getAvailableXP(actor))
    local trainerOptions = {}
    local blockedTrainers = {}
    local selectedTrainerOption = nil
    local selectedTalentOption = nil
    local selectedXPOption = nil
    local eligibleTrainerCount = 0

    local function trainingTalentOptions(trainer)
        local options = {}
        local seen = {}
        for key, talent in pairs(trainer and trainer.talents or {}) do
            local rawTalentId = type(talent) == "table" and (talent.id or talent.talentId or talent.name) or key
            local talentId = normalizeTalentId(rawTalentId)
            if talentId ~= "" and not seen[talentId] and isTalentMastered(trainer, talentId) then
                seen[talentId] = true
                local trainingOk, training = talent_catalog.validateTraining(actor, talentId, {
                    hasTrainer = true,
                    trainerAvailable = true,
                })
                local existingTalent = getTalentRecord(actor, talentId)
                local alreadyMastered = type(existingTalent) == "table" and existingTalent.mastered == true or
                    existingTalent == true
                local invested = type(existingTalent) == "table" and
                    (tonumber(existingTalent.xp_invested) or 0) or 0
                local remainingToMastery = math.max(1, 7 - invested)
                local option = {
                    id = talentId,
                    name = talent_catalog.getTalentName and talent_catalog.getTalentName(talentId) or talentId,
                    trainerId = trainer and trainer.id or nil,
                    masteredByTrainer = true,
                    actorHasTalent = existingTalent ~= nil,
                    alreadyMastered = alreadyMastered,
                    xpInvested = invested,
                    remainingToMastery = remainingToMastery,
                    selected = selectedTalentId ~= "" and selectedTalentId == talentId,
                    disabled = false,
                    actionDataPreview = {
                        type = "train",
                        targetId = trainer and trainer.id or nil,
                        request = {
                            talentId = talentId,
                        },
                    },
                }
                if trainingOk then
                    option.ownPath = training.ownPath == true
                    option.mentored = training.mentored == true
                    option.trainingKind = training.kind
                    option.path = training.path
                else
                    option.disabled = true
                    option.unavailableReason = training and training.reason or "Talent cannot be trained"
                end
                if alreadyMastered then
                    option.disabled = true
                    option.unavailableReason = "Talent already mastered"
                end
                if option.selected then
                    selectedTalentOption = option
                end
                options[#options + 1] = option
            end
        end
        table.sort(options, function(a, b)
            return tostring(a.name or a.id or "") < tostring(b.name or b.id or "")
        end)
        return options
    end

    for _, trainer in ipairs(guild) do
        if trainer and (not actor or trainer ~= actor and trainer.id ~= actor.id) then
            local option = {
                id = trainer.id,
                name = trainer.name,
                isAdventurer = trainer.isPC == true,
                actionCompleted = trainer.id and completed[trainer.id] ~= nil,
                selected = (selectedTrainerId and trainer.id == selectedTrainerId) or
                    (type(selectedTrainer) == "table" and selectedTrainer == trainer),
                talentOptions = {},
            }
            option.talentOptions = trainingTalentOptions(trainer)
            for _, talentOption in ipairs(option.talentOptions) do
                if not talentOption.disabled then
                    option.teachableTalentCount = (option.teachableTalentCount or 0) + 1
                end
            end
            option.teachableTalentCount = option.teachableTalentCount or 0
            if not option.isAdventurer then
                option.disabled = true
                option.unavailableReason = "Trainer must be an adventurer"
            elseif actorCompleted then
                option.disabled = true
                option.unavailableReason = "Trainee has already taken a Camp Action"
            elseif option.actionCompleted then
                option.disabled = true
                option.unavailableReason = "Trainer has already taken a Camp Action"
            elseif option.teachableTalentCount == 0 then
                option.disabled = true
                option.unavailableReason = "No trainable mastered talents"
            end
            if option.selected then
                selectedTrainerOption = option
            end
            if option.disabled then
                blockedTrainers[#blockedTrainers + 1] = option
            else
                eligibleTrainerCount = eligibleTrainerCount + 1
                trainerOptions[#trainerOptions + 1] = option
            end
        end
    end

    if actorCompleted then
        addUnavailable("Trainee has already taken a Camp Action")
    end
    if eligibleTrainerCount == 0 then
        addUnavailable("No trainer targeted")
    end
    if selectedTrainerId and not selectedTrainerOption then
        addUnavailable("selected_trainer_unavailable")
    elseif selectedTrainerOption and selectedTrainerOption.disabled then
        addUnavailable(selectedTrainerOption.unavailableReason)
    end
    if selectedTalentId ~= "" and not selectedTalentOption then
        addUnavailable("selected_talent_unavailable")
    elseif selectedTalentOption and selectedTalentOption.disabled then
        addUnavailable(selectedTalentOption.unavailableReason)
    end
    if selectedXPError then
        addUnavailable(selectedXPError)
    end

    local xpOptions = {}
    if selectedTalentOption and not selectedTalentOption.disabled then
        local maxXP = math.min(math.max(0, availableXP), selectedTalentOption.remainingToMastery)
        for amount = 1, maxXP do
            local totalAfter = selectedTalentOption.xpInvested + amount
            local option = {
                xp = amount,
                selected = selectedXP == amount,
                totalXPInvestedAfter = totalAfter,
                remainingXPToMasteryAfter = math.max(0, 7 - totalAfter),
                masteredAfter = totalAfter >= 7,
                availableXPAfter = availableXP - amount,
                resultPreview = "training_complete",
                actionDataPreview = {
                    type = "train",
                    targetId = selectedTrainerOption and selectedTrainerOption.id or nil,
                    request = {
                        talentId = selectedTalentOption.id,
                        xp = amount,
                    },
                },
            }
            if option.selected then
                selectedXPOption = option
            end
            xpOptions[#xpOptions + 1] = option
        end
        if #xpOptions == 0 then
            addUnavailable("Not enough XP")
        elseif xpRequested and selectedXP and not selectedXPOption then
            addUnavailable("Not enough XP")
        end
    end

    return {
        result = "train_options_ready",
        actor = actor,
        actorId = actor and actor.id or nil,
        actorName = actor and actor.name or nil,
        disabled = #unavailableReasons > 0,
        unavailableReasons = unavailableReasons,
        availableXP = availableXP,
        actionCompleted = actorCompleted,
        hasTrainerOptions = eligibleTrainerCount > 0,
        trainerOptions = trainerOptions,
        blockedTrainers = blockedTrainers,
        selectedTrainer = selectedTrainerOption,
        selectedTalent = selectedTalentOption,
        xpOptions = xpOptions,
        selectedXP = selectedXPOption,
        requiresTrainer = selectedTrainerOption == nil,
        requiresTalent = selectedTrainerOption ~= nil and selectedTalentOption == nil,
        requiresXP = selectedTalentOption ~= nil and selectedXPOption == nil,
        rules = {
            requiresGuildMateTrainer = true,
            requiresTrainerMasteredTalent = true,
            rejectsKinAndAreteTalents = true,
            rejectsAlreadyMasteredTalents = true,
            xpMustBePositiveWholeNumber = true,
            masteryXP = 7,
            consumesTrainerCampAction = true,
        },
    }
end

function M.resolveTrain(actor, trainer, actionData, context, eventBus)
    context = context or {}
    eventBus = eventBus or context.eventBus or events.globalBus
    actionData = actionData or {}

    if not trainer then
        return false, "No trainer targeted"
    end

    if actor.id == trainer.id then
        return false, "Cannot train yourself"
    end

    local completed = context.actionsCompleted or {}
    if completed[actor.id] then
        return false, "Trainee has already taken a Camp Action"
    end
    if completed[trainer.id] then
        return false, "Trainer has already taken a Camp Action"
    end

    local request = actionData.request or actionData.training or actionData
    local talentId = normalizeTalentId(request.talentId or request.talent or request.id)
    if talentId == "" then
        return false, "Choose a talent to train"
    end

    local trainingOk, training = talent_catalog.validateTraining(actor, talentId, {
        hasTrainer = true,
        trainerAvailable = true,
    })
    if not trainingOk then
        return false, training.reason
    end

    local existingTalent = getTalentRecord(actor, talentId)
    if type(existingTalent) == "table" and existingTalent.mastered == true then
        return false, "Talent already mastered"
    end

    if not isTalentMastered(trainer, talentId) then
        return false, "Trainer has not mastered that talent"
    end

    local xpAmount, xpError = requestedTrainingXP(request)
    if not xpAmount then
        return false, xpError
    end
    if not spendXP(actor, xpAmount) then
        return false, "Not enough XP"
    end

    actor.talents = actor.talents or {}
    local talent = existingTalent or actor.talents[talentId]
    if type(talent) ~= "table" then
        talent = {
            mastered = false,
            wounded = false,
            xp_invested = 0,
        }
        actor.talents[talentId] = talent
    end

    talent.mastered = talent.mastered == true
    talent.wounded = talent.wounded == true
    talent.mentored = training.mentored == true
    talent.pathTrained = training.ownPath == true
    talent.path = training.path or talent.path
    talent.trainingKind = training.kind
    talent.trainerId = trainer.id
    talent.xp_invested = (talent.xp_invested or 0) + xpAmount
    talent.prepared_uses = talent.xp_invested
    talent.uses_remaining = (talent.uses_remaining or 0) + xpAmount
    if talent.xp_invested >= 7 then
        talent.mastered = true
    end

    eventBus:emit("camp_action_resolved", {
        action = "train",
        actor = actor,
        trainer = trainer,
        target = trainer,
        result = "training_complete",
        talentId = talentId,
        xpInvested = xpAmount,
        totalXPInvested = talent.xp_invested,
        mastered = talent.mastered,
    })

    print("[CAMP] " .. actor.name .. " trains " .. talentId .. " with " .. trainer.name)

    return true, "training_complete", talent
end

--------------------------------------------------------------------------------
-- USE A TALENT (S8.3)
--------------------------------------------------------------------------------
-- Dispatch Camp Phase talents that have concrete procedural effects.

local function findAnimalCompanion(actor, companionId)
    local companions = {}
    if actor and actor.companion then
        companions[#companions + 1] = actor.companion
    end
    for _, companion in ipairs(actor and actor.animalCompanions or {}) do
        companions[#companions + 1] = companion
    end

    if not companionId then
        return companions[1]
    end

    for _, companion in ipairs(companions) do
        if companion.id == companionId or companion.name == companionId then
            return companion
        end
    end

    return nil
end

local function listContainsText(items, value)
    local wanted = tostring(value or ""):lower()
    for _, item in ipairs(items or {}) do
        if tostring(item):lower() == wanted then
            return true
        end
    end
    return false
end

local function appendUniqueText(items, value)
    if not value or tostring(value) == "" then
        return false
    end
    if listContainsText(items, value) then
        return false
    end
    items[#items + 1] = value
    return true
end

local function getRequestField(actionData, field)
    local request = actionData and actionData.request
    if request and request[field] ~= nil then
        return request[field]
    end
    return actionData and actionData[field]
end

local function locationKnown(location, roomId, actionData, context)
    local explicitKnown = getRequestField(actionData, "known")
    if explicitKnown ~= nil then
        return explicitKnown == true
    end
    if location and location.known == false then
        return false
    end
    if location and (location.known == true or location.visited == true or location.discovered == true) then
        return true
    end

    local knownLocations = context and context.knownLocations
    if type(knownLocations) == "table" and roomId then
        if knownLocations[roomId] == true then
            return true
        end
        for _, id in ipairs(knownLocations) do
            if id == roomId then
                return true
            end
        end
        return false
    end

    return true
end

local function lookupInfiltrationLocation(actionData, context)
    context = context or {}
    local location = getRequestField(actionData, "location") or getRequestField(actionData, "room")
    local roomId = getRequestField(actionData, "roomId") or getRequestField(actionData, "room_id") or
        getRequestField(actionData, "locationId") or getRequestField(actionData, "location_id")

    if type(location) == "string" and not roomId then
        roomId = location
        location = nil
    end
    if type(location) == "table" and not roomId then
        roomId = location.id or location.roomId or location.locationId
    end

    if not location and roomId then
        if context.roomManager and context.roomManager.getRoom then
            location = context.roomManager:getRoom(roomId)
        elseif context.dungeon and context.dungeon.getRoom then
            location = context.dungeon:getRoom(roomId)
        elseif type(context.rooms) == "table" then
            location = context.rooms[roomId]
        end
    end

    if not location and not roomId then
        return nil, "Choose a location to infiltrate"
    end

    roomId = roomId or (location and (location.id or location.roomId or location.locationId))
    if not locationKnown(location, roomId, actionData, context) then
        return nil, "Location must be known"
    end

    local currentLevel = getRequestField(actionData, "currentLevel") or
        context.currentDungeonLevel or context.dungeonLevel or context.level
    local locationLevel = getRequestField(actionData, "level") or
        (location and (location.level or location.dungeonLevel or location.dungeon_level))
    if currentLevel and locationLevel and tostring(currentLevel) ~= tostring(locationLevel) then
        return nil, "Location is not on current dungeon level"
    end

    return {
        id = roomId or tostring(location and location.name or "location"),
        name = (location and location.name) or tostring(roomId or "Known Location"),
        level = locationLevel or currentLevel,
        location = location,
    }
end

local function mergeFactValue(facts, key, value)
    if value ~= nil then
        facts[key] = value == true
    end
end

local function collectInfiltrationFacts(location, actionData)
    local facts = {
        trapped = false,
        guarded = false,
        hasSecret = false,
        hasLoot = false,
    }

    if location then
        if location.socialEncounter or (location.mobs and #location.mobs > 0) or
           (location.npcs and #location.npcs > 0) then
            facts.guarded = true
        end

        for _, feature in ipairs(location.features or {}) do
            if feature.trap or feature.type == "trap" then
                facts.trapped = true
            end
            if feature.secrets or feature.reveal_connection or feature.state == "hidden" or
               feature.hidden_description then
                facts.hasSecret = true
            end
            if feature.loot or feature.item or feature.treasure then
                facts.hasLoot = true
            end
        end
    end

    local overrides = getRequestField(actionData, "facts") or getRequestField(actionData, "yesNoFacts") or {}
    if type(overrides) ~= "table" then
        overrides = {}
    end
    mergeFactValue(facts, "trapped", overrides.trapped or overrides.hasTrap or overrides.isTrapped)
    mergeFactValue(facts, "guarded", overrides.guarded or overrides.hasGuards or overrides.isGuarded)
    mergeFactValue(facts, "hasSecret", overrides.hasSecret or overrides.secret or overrides.hidden)
    mergeFactValue(facts, "hasLoot", overrides.hasLoot or overrides.loot or overrides.treasure)

    return facts
end

local function collectInfiltrationSubjectIds(location, actionData)
    local subjectIds = {}
    local function add(value)
        if value and tostring(value) ~= "" and not listContainsText(subjectIds, value) then
            subjectIds[#subjectIds + 1] = value
        end
    end

    add(getRequestField(actionData, "subjectId"))
    add(location and (location.loreSubjectId or location.subjectId))
    for _, feature in ipairs(location and location.features or {}) do
        add(feature.loreSubjectId or feature.subjectId)
        local loreEffect = feature.loreEffect
        if type(loreEffect) == "table" then
            add(loreEffect.subjectId)
        end
    end

    return subjectIds
end

function M.getInfiltrateOptions(actor, context, opts)
    context = context or {}
    opts = opts or {}

    local selectedLocation = opts.location or opts.room or opts.target
    local selectedRoomId = opts.roomId or opts.room_id or opts.locationId or opts.location_id or
        (type(selectedLocation) == "table" and (selectedLocation.id or selectedLocation.roomId or
            selectedLocation.locationId) or selectedLocation)
    local currentLevel = opts.currentLevel or context.currentDungeonLevel or context.dungeonLevel or context.level
    local roomManager = context.roomManager
    local dungeon = context.dungeon
    local hasSneak = hasUsableActionTalent(actor, "sneak")
    local locationOptions = {}
    local blockedLocations = {}
    local selectedOption = nil
    local seen = {}
    local resolvableCount = 0
    local unavailableReasons = {}
    local unavailableSeen = {}
    local function addUnavailable(reason)
        if reason and not unavailableSeen[reason] then
            unavailableSeen[reason] = true
            unavailableReasons[#unavailableReasons + 1] = reason
        end
    end
    local function currentRoomId()
        if context.currentRoomId or context.roomId then
            return context.currentRoomId or context.roomId
        end
        if type(context.currentRoom) == "table" then
            return context.currentRoom.id or context.currentRoom.roomId or context.currentRoom.locationId
        end
        if context.currentRoom then
            return context.currentRoom
        end
        return nil
    end
    local function lookupRoom(roomId, room)
        if room then
            return room
        end
        if roomManager and roomManager.getRoom then
            room = roomManager:getRoom(roomId)
        end
        if not room and dungeon and dungeon.getRoom then
            room = dungeon:getRoom(roomId)
        end
        if not room and type(context.rooms) == "table" then
            room = context.rooms[roomId]
        end
        return room
    end
    local function addLocation(roomId, room, source, explicitKnown)
        room = lookupRoom(roomId, room)
        roomId = roomId or (room and (room.id or room.roomId or room.locationId))
        if not roomId or seen[roomId] then
            return
        end
        seen[roomId] = true

        local actionData = {
            roomId = roomId,
            location = room,
        }
        if explicitKnown ~= nil then
            actionData.known = explicitKnown
        elseif source == "known_locations" or source == "current_room" then
            actionData.known = true
        end

        local locationLevel = opts.level or (room and (room.level or room.dungeonLevel or room.dungeon_level))
        local name = (room and room.name) or tostring(roomId)
        local facts = collectInfiltrationFacts(room, actionData)
        local subjectIds = collectInfiltrationSubjectIds(room, actionData)
        local known = locationKnown(room, roomId, actionData, context)
        local option = {
            id = roomId,
            roomId = roomId,
            name = name,
            level = locationLevel or currentLevel,
            source = source,
            known = known,
            current = currentRoomId() == roomId,
            resultPreview = "location_infiltrated",
            motifPreview = opts.motif or ("Infiltrated " .. name),
            factsPreview = facts,
            subjectIds = subjectIds,
            yesNoQuestions = {
                trapped = "Is this location trapped?",
                guarded = "Is this location guarded?",
                hasSecret = "Does this location hide something?",
                hasLoot = "Is there recoverable loot here?",
            },
            actionDataPreview = {
                type = "infiltrate",
                roomId = roomId,
                known = true,
            },
        }

        if not hasSneak then
            option.disabled = true
            option.unavailableReason = "requires_sneak"
        elseif not known then
            option.disabled = true
            option.unavailableReason = "location_must_be_known"
        elseif currentLevel and locationLevel and tostring(currentLevel) ~= tostring(locationLevel) then
            option.disabled = true
            option.unavailableReason = "location_not_on_current_level"
        end

        if option.disabled then
            blockedLocations[#blockedLocations + 1] = option
        else
            locationOptions[#locationOptions + 1] = option
            resolvableCount = resolvableCount + 1
        end

        if selectedRoomId and tostring(roomId) == tostring(selectedRoomId) then
            option.selected = true
            selectedOption = option
        end
    end

    local current = context.currentRoom
    addLocation(context.currentRoomId or context.roomId or
        (type(current) == "table" and (current.id or current.roomId or current.locationId) or current),
        type(current) == "table" and current or nil,
        "current_room")

    local knownLocations = context.knownLocations or context.knownLocationIds
    if type(knownLocations) == "table" then
        for key, value in pairs(knownLocations) do
            local roomId = value
            local room = nil
            if value == true then
                roomId = key
            elseif type(value) == "table" then
                room = value
                roomId = value.id or value.roomId or value.locationId
            end
            addLocation(roomId, room, "known_locations", true)
        end
    end

    if type(context.rooms) == "table" then
        for roomId, room in pairs(context.rooms) do
            if type(room) == "table" and
               (room.known == true or room.visited == true or room.discovered == true) then
                addLocation(roomId, room, "rooms")
            end
        end
    end

    if roomManager and type(roomManager.rooms) == "table" then
        for roomId, room in pairs(roomManager.rooms) do
            if room and room.known ~= false and
               (room.known == true or room.visited == true or room.discovered == true) then
                addLocation(roomId, room, "room_manager")
            end
        end
    end

    if selectedRoomId and not seen[selectedRoomId] then
        addLocation(selectedRoomId, type(selectedLocation) == "table" and selectedLocation or nil,
            "selected", opts.known)
    end

    table.sort(locationOptions, function(a, b)
        return tostring(a.name or a.id or "") < tostring(b.name or b.id or "")
    end)
    table.sort(blockedLocations, function(a, b)
        return tostring(a.name or a.id or "") < tostring(b.name or b.id or "")
    end)

    if not hasSneak then
        addUnavailable("requires_sneak")
    end
    if resolvableCount == 0 then
        addUnavailable("no_known_locations")
    end
    if selectedRoomId and not selectedOption then
        addUnavailable("selected_location_unavailable")
    elseif selectedOption and selectedOption.disabled then
        addUnavailable(selectedOption.unavailableReason or "selected_location_unavailable")
    end

    return {
        result = "infiltrate_options_ready",
        actor = actor,
        actorId = actor and actor.id or nil,
        actorName = actor and actor.name or nil,
        hasSneak = hasSneak,
        hasKnownLocations = resolvableCount > 0,
        disabled = not hasSneak or resolvableCount == 0,
        unavailableReasons = unavailableReasons,
        locationOptions = locationOptions,
        blockedLocations = blockedLocations,
        selectedLocation = selectedOption,
        rules = {
            requiresSneak = true,
            requiresKnownLocation = true,
            requiresCurrentDungeonLevel = true,
            recordsYesNoFacts = true,
            createsLoreMotif = true,
        },
    }
end

function M.resolveInfiltrate(actor, actionData, context, eventBus)
    context = context or {}
    actionData = actionData or {}
    eventBus = eventBus or context.eventBus or events.globalBus

    if not hasUsableActionTalent(actor, "sneak") then
        return false, "Requires Sneak"
    end

    local locationInfo, reason = lookupInfiltrationLocation(actionData, context)
    if not locationInfo then
        return false, reason
    end

    local facts = collectInfiltrationFacts(locationInfo.location, actionData)
    local subjectIds = collectInfiltrationSubjectIds(locationInfo.location, actionData)
    local motif = getRequestField(actionData, "motif") or ("Infiltrated " .. locationInfo.name)

    actor.infiltrations = actor.infiltrations or {}
    local record = {
        id = getRequestField(actionData, "infiltrationId") or
            string.format("infiltration_%s_%d", tostring(actor.id or "actor"), #actor.infiltrations + 1),
        actor = actor,
        actorId = actor.id,
        locationId = locationInfo.id,
        locationName = locationInfo.name,
        level = locationInfo.level,
        facts = facts,
        subjectIds = subjectIds,
        motif = motif,
        source = "sneak_infiltrate",
        yesNoQuestions = {
            trapped = "Is this location trapped?",
            guarded = "Is this location guarded?",
            hasSecret = "Does this location hide something?",
            hasLoot = "Is there recoverable loot here?",
        },
    }
    actor.infiltrations[#actor.infiltrations + 1] = record
    actor.lastInfiltration = record

    actor.motifs = actor.motifs or {}
    appendUniqueText(actor.motifs, motif)

    eventBus:emit("camp_action_resolved", {
        action = "infiltrate",
        talentId = "sneak",
        actor = actor,
        result = "location_infiltrated",
        infiltration = record,
        locationId = record.locationId,
        locationName = record.locationName,
        motif = motif,
    })

    return true, "location_infiltrated", record
end

local function resolveBeastMasterTalent(actor, actionData, eventBus)
    actionData = actionData or {}
    local companion = actionData.companion or actionData.target or
        findAnimalCompanion(actor, actionData.companionId or actionData.companion_id)
    if not companion then
        return false, "Choose an animal companion"
    end

    local command = actionData.commandName or actionData.command or
        (actionData.request and (actionData.request.commandName or actionData.request.command))
    if not command then
        return false, "Choose a command to teach"
    end

    companion.knownCommands = companion.knownCommands or companion.commands or {}
    companion.commands = companion.knownCommands
    local commandDisplay = animal_companions.getCommandDisplayName(command)
    local commandKey = animal_companions.normalizeCommandName(command)
    local function companionKnows(commandList, value)
        local wanted = animal_companions.normalizeCommandName(value)
        for key, known in pairs(commandList or {}) do
            if animal_companions.normalizeCommandName(animal_companions.getCommandEntryName(known, key)) == wanted then
                return true
            end
        end
        return false
    end

    local markFamiliar = actionData.makeFamiliar or actionData.markFamiliar or actionData.familiar or
        (actionData.request and (actionData.request.makeFamiliar or actionData.request.markFamiliar or
            actionData.request.familiar))
    if markFamiliar then
        if not isActionTalentMastered(actor, "beast_master") then
            return false, "Mastered Beast Master required for familiar"
        end
        if actor.familiarCompanionId and actor.familiarCompanionId ~= companion.id then
            return false, "Already has familiar"
        end
        actor.familiarCompanionId = companion.id
        companion.isFamiliar = true
        companion.familiar = true
        companion.familiarOwnerId = actor.id
    end

    if not companionKnows(companion.knownCommands, commandKey) then
        local replace = actionData.replaceCommand or actionData.replace_command or
            (actionData.request and (actionData.request.replaceCommand or actionData.request.replace_command))
        local commandLimit = animal_companions.getCommandLimit(companion)
        if #companion.knownCommands >= commandLimit then
            if not replace then
                if commandLimit == 5 then
                    return false, "Familiar already knows five commands"
                end
                return false, "Companion already knows three commands"
            end

            local replaced = false
            for i, known in ipairs(companion.knownCommands) do
                if animal_companions.normalizeCommandName(animal_companions.getCommandEntryName(known, i)) ==
                   animal_companions.normalizeCommandName(replace) then
                    companion.knownCommands[i] = commandDisplay
                    replaced = true
                    break
                end
            end
            if not replaced then
                return false, "Replacement command not known"
            end
        else
            companion.knownCommands[#companion.knownCommands + 1] = commandDisplay
        end
    end

    eventBus:emit("camp_action_resolved", {
        action = "use_talent",
        talentId = "beast_master",
        actor = actor,
        companion = companion,
        command = commandDisplay,
        result = "companion_command_taught",
    })

    return true, "companion_command_taught", companion
end

local function resolveWarStoriesTalent(actor, actionData, context, eventBus)
    local participants = actionData.participants or (actionData.request and actionData.request.participants) or
        context.guild or { actor }
    local benefits = actionData.benefits or (actionData.request and actionData.request.benefits) or {}
    local applied = {}

    for _, participant in ipairs(participants) do
        local benefit = benefits[participant.id] or benefits[participant.name] or benefits.default or "resolve"
        if type(benefit) == "string" then
            benefit = { type = benefit }
        end

        local appliedResult = nil
        if benefit.type == "charge_bond" or benefit.type == "bond" then
            local targetId = benefit.bondTargetId or benefit.targetId
            if not targetId and participant.bonds then
                for id, bond in pairs(participant.bonds) do
                    if not bond.charged then
                        targetId = id
                        break
                    end
                end
            end
            if targetId and participant.bonds and participant.bonds[targetId] then
                participant.bonds[targetId].charged = true
                appliedResult = "bond_charged"
            else
                appliedResult = "bond_unavailable"
            end
        else
            if type(participant.resolve) == "table" then
                participant.resolve.max = math.max(participant.resolve.max or 4, 5)
                participant.resolve.current = math.min((participant.resolve.current or 0) + 1, 5)
                appliedResult = "resolve_gained"
            elseif participant.resolve ~= nil then
                participant.resolve = math.min(participant.resolve + 1, 5)
                appliedResult = "resolve_gained"
            else
                participant.resolve = 1
                appliedResult = "resolve_gained"
            end
        end

        applied[#applied + 1] = {
            entity = participant,
            result = appliedResult,
        }
    end

    eventBus:emit("camp_action_resolved", {
        action = "use_talent",
        talentId = "war_stories",
        actor = actor,
        result = "war_stories_shared",
        participants = applied,
    })

    return true, "war_stories_shared", applied
end

local function getHighChantDiscardPile(actionData, context)
    local deck = actionData.deck or actionData.playerDeck or actionData.minorDeck or
        context.playerDeck or context.minorDeck
    if deck and deck.discard_pile then
        return deck.discard_pile, deck
    end
    return actionData.discardPile or actionData.discard_pile or context.discardPile or context.discard_pile, deck
end

local function findCardIndex(cards, card)
    for i, candidate in ipairs(cards or {}) do
        if candidate == card then
            return i
        end
    end
    return nil
end

local function resolveHighChantTalent(actor, actionData, context, eventBus)
    context = context or {}
    actionData = actionData or {}

    if actionData.performed == false then
        return false, "High Chant performance required"
    end

    local discardPile = nil
    discardPile = getHighChantDiscardPile(actionData, context)
    if type(discardPile) ~= "table" or #discardPile == 0 then
        return false, "No minor discard cards"
    end

    local maxCards = math.max(0, actor and actor.cups or 0)
    if maxCards <= 0 then
        return false, "No Cups for High Chant"
    end

    local selected = actionData.cards or actionData.selectedCards or {}
    if #selected == 0 then
        local count = math.min(maxCards, #discardPile)
        for i = 0, count - 1 do
            selected[#selected + 1] = discardPile[#discardPile - i]
        end
    end

    if #selected == 0 then
        return false, "No inspiration cards selected"
    end
    if #selected > maxCards then
        return false, "Too many inspiration cards"
    end

    local recipients = actionData.recipients or actionData.targets or { actor }
    if #recipients < #selected then
        return false, "Not enough inspiration recipients"
    end

    local granted = {}
    local removals = {}
    for i, card in ipairs(selected) do
        local discardIndex = findCardIndex(discardPile, card)
        if not discardIndex then
            return false, "Card not in minor discard"
        end

        local recipient = recipients[i] or actor
        if not recipient then
            return false, "Missing inspiration recipient"
        end
        if recipient.inspirationCard then
            return false, "Recipient already has inspiration"
        end

        removals[#removals + 1] = discardIndex
        granted[#granted + 1] = {
            recipient = recipient,
            card = card,
        }
    end

    table.sort(removals, function(a, b)
        return a > b
    end)
    for _, index in ipairs(removals) do
        table.remove(discardPile, index)
    end

    for _, grant in ipairs(granted) do
        local card = grant.card
        card.inspiration = {
            source = "high_chant",
            performerId = actor.id,
            expires = "session_end",
        }
        grant.recipient.inspirationCard = card
        grant.recipient.inspirationSource = actor.id
    end

    eventBus:emit("camp_action_resolved", {
        action = "use_talent",
        talentId = "high_chant",
        actor = actor,
        result = "high_chant_performed",
        inspirationCards = granted,
    })

    return true, "high_chant_performed", granted
end

function M.resolveMakePact(actor, actionData, context, eventBus)
    context = context or {}
    actionData = actionData or {}
    eventBus = eventBus or context.eventBus or events.globalBus

    if not hasUsableActionTalent(actor, "gramarye") then
        return false, "Requires Gramarye"
    end

    local pactSpecs = normalizeList(actionData.pacts or actionData.pactIds or actionData.pact or actionData.pactId)
    if #pactSpecs == 0 then
        return false, "Choose at least one pact"
    end

    local componentRefs = normalizeList(actionData.components or actionData.componentIds or
        actionData.component or actionData.componentId)
    local prepared = {}
    local usedComponents = {}

    for index, pactSpec in ipairs(pactSpecs) do
        local pactId, definition = resolvePactDefinition(pactSpec)
        if not pactId or not definition then
            return false, "Unknown pact"
        end

        local componentRef = componentRefs[index] or componentRefs[1]
        local component = nil
        local location = nil
        if componentRef then
            component, location = findSpellComponentForPact(actor, componentRef)
        else
            component, location = findSpellComponentForPact(actor)
        end

        if not component or not isSpellComponent(component) then
            return false, "Choose a carried spell component"
        end
        if usedComponents[component] or (component.id and usedComponents[component.id]) then
            return false, "Each pact needs a different component"
        end

        local props = component.properties or {}
        if props.pactCharged or component.pactCharge then
            return false, "Component already charged"
        end

        usedComponents[component] = true
        if component.id then
            usedComponents[component.id] = true
        end
        prepared[#prepared + 1] = {
            pactId = pactId,
            definition = definition,
            component = component,
            location = location,
        }
    end

    actor._pactCounter = actor._pactCounter or 0
    actor.activePacts = actor.activePacts or {}
    actor.pacts = actor.pacts or {}

    local made = {}
    for _, entry in ipairs(prepared) do
        actor._pactCounter = actor._pactCounter + 1
        local component = entry.component
        component.properties = component.properties or {}
        local pact = {
            id = actionData.pactRecordId or
                string.format("pact_%s_%d", tostring(actor.id or "actor"), actor._pactCounter),
            pactId = entry.pactId,
            name = entry.definition.name,
            obligation = entry.definition.obligation,
            actor = actor,
            actorId = actor.id,
            component = component,
            componentId = component.id,
            componentName = component.name,
            componentFor = component.properties.componentFor,
            componentLocation = entry.location,
            active = true,
            source = "make_pact",
            socialDisfavor = entry.definition.socialDisfavor == true,
            causesStressed = entry.definition.causesStressed == true,
            causesWound = entry.definition.causesWound == true,
        }

        component.properties.pactCharged = true
        component.properties.pactCharge = pact
        component.pactCharge = pact

        pact.immediateEffect = applyImmediatePactEffect(actor, pact)
        actor.activePacts[#actor.activePacts + 1] = pact
        actor.pacts[#actor.pacts + 1] = pact
        made[#made + 1] = pact
    end

    eventBus:emit("camp_action_resolved", {
        action = "make_pact",
        actor = actor,
        result = "pacts_made",
        pacts = made,
    })

    return true, "pacts_made", made
end

function M.findActivePact(actor, pactRef)
    if type(pactRef) == "table" then
        return pactRef
    end
    if not actor or not pactRef then
        return nil
    end

    local key = tostring(pactRef)
    for _, pact in ipairs(actor.activePacts or {}) do
        if tostring(pact.id) == key or tostring(pact.pactId) == key then
            return pact
        end
    end

    return nil
end

function M.isPactActive(pact)
    return pact ~= nil and pact.active ~= false and not pact.broken and not pact.spent
end

function M.findUnbrokenActivePact(actor, pactRef)
    local pact = M.findActivePact(actor, pactRef)
    if M.isPactActive(pact) then
        return pact
    end
    return nil
end

function M.breakPact(actor, pactRef, opts)
    opts = opts or {}
    local eventBus = opts.eventBus or events.globalBus
    local pact = M.findActivePact(actor, pactRef)
    if not pact or pact.active == false then
        return false, "Pact not active"
    end

    pact.active = false
    pact.broken = true
    pact.breakReason = opts.reason or "pact_broken"

    local component = pact.component
    if component then
        component.pactCharge = nil
        if component.properties then
            component.properties.pactCharged = false
            component.properties.pactCharge = nil
        end
    end

    local branch = opts.branch or (component and component.properties and component.properties.branch) or "unknown"
    local resolver = opts.actionResolver or opts.resolver
    local maleficence = nil
    if resolver and resolver.triggerMaleficence then
        maleficence = resolver:triggerMaleficence(actor, branch, "pact_broken", {
            source = pact,
            spellId = pact.componentFor,
            card = opts.maleficenceCard,
            value = opts.maleficenceValue,
            resolve = opts.resolveMaleficence == true or opts.maleficenceCard ~= nil or
                opts.maleficenceValue ~= nil,
        })
    else
        maleficence = {
            actor = actor,
            branch = branch,
            reason = "pact_broken",
            source = pact,
            spellId = pact.componentFor,
        }
        if actor then
            actor.pendingMaleficence = maleficence
            actor.maleficenceHistory = actor.maleficenceHistory or {}
            actor.maleficenceHistory[#actor.maleficenceHistory + 1] = maleficence
        end
        eventBus:emit(events.EVENTS.MALEFICENCE_TRIGGERED, maleficence)
    end

    return true, "pact_broken", {
        pact = pact,
        maleficence = maleficence,
    }
end

local selfMutilationHealResults = {
    armor_notched = "armor_healed",
    talent_wounded = "talent_healed",
    staggered = "staggered_healed",
    injured = "injured_healed",
    deaths_door = "deaths_door_healed",
    wound_recorded = "heal_wound",
}

local function recoveryResultHealsSelfMutilation(pact, recoveryResult)
    if not pact or not recoveryResult then
        return false
    end
    if recoveryResult == "all_wounds_healed" then
        return true
    end

    local immediate = pact.immediateEffect
    return selfMutilationHealResults[immediate] == recoveryResult
end

function M.breakPactsForRecoveryResult(actor, recoveryResult, opts)
    opts = opts or {}
    local breaks = {}

    local function breakObligation(pactId, reason)
        local pact = M.findUnbrokenActivePact(actor, pactId)
        if not pact then
            return
        end

        local ok, result, detail = M.breakPact(actor, pact, {
            eventBus = opts.eventBus,
            actionResolver = opts.actionResolver or opts.resolver,
            reason = reason,
            branch = opts.branch,
            maleficenceCard = opts.maleficenceCard,
            maleficenceValue = opts.maleficenceValue,
            resolveMaleficence = opts.resolveMaleficence,
        })
        breaks[#breaks + 1] = {
            ok = ok,
            result = result,
            detail = detail,
            pact = pact,
            pactId = pactId,
            reason = reason,
        }
    end

    if recoveryResult == "stress_cleared" then
        breakObligation("self_mortification", "self_mortification_stress_cleared")
    end

    local selfMutilation = M.findUnbrokenActivePact(actor, "self_mutilation")
    if recoveryResultHealsSelfMutilation(selfMutilation, recoveryResult) then
        breakObligation("self_mutilation", "self_mutilation_wound_healed")
    end

    return breaks
end

function M.recordBookwormReading(actor, book)
    local props = book and book.properties or {}
    if not M.hasCampTalent(actor) or not findCampTalent(actor, "bookworm") then
        return false
    end

    actor.bookwormBooks = actor.bookwormBooks or {}
    local entry = {
        bookId = book.id,
        name = book.name,
        subjectId = props.loreSubjectId,
        subjectMatter = props.subjectMatter,
        motif = props.subjectMatter or book.name,
    }
    actor.bookwormBooks[#actor.bookwormBooks + 1] = entry

    actor.motifs = actor.motifs or {}
    if entry.motif and not listContainsText(actor.motifs, entry.motif) then
        actor.motifs[#actor.motifs + 1] = entry.motif
    end

    return true, entry
end

local function isRestAction(action)
    return type(action) == "table" and (action.type == "rest" or action.id == "rest")
end

local function targetIsRestingForChirurgery(target, actionData, context)
    if actionData.targetResting == true or actionData.restAndRecover == true or actionData.targetUsesRest == true then
        return true
    end
    if isRestAction(actionData.targetAction or actionData.restAction) then
        return true
    end

    local actionsCompleted = context.actionsCompleted or {}
    return target and target.id and isRestAction(actionsCompleted[target.id])
end

local function healAllWounds(target)
    local healed = {
        armorNotches = target.armorNotches or 0,
        woundedTalents = target.woundedTalents or 0,
        staggered = target.conditions and target.conditions.staggered == true,
        injured = target.conditions and target.conditions.injured == true,
        deathsDoor = target.conditions and target.conditions.deaths_door == true,
    }

    target.armorNotches = 0
    target.woundedTalents = 0
    target._woundedTalentOrder = {}

    for _, talent in pairs(target.talents or {}) do
        if type(talent) == "table" then
            talent.wounded = false
        end
    end

    if target.conditions then
        target.conditions.staggered = false
        target.conditions.injured = false
        target.conditions.deaths_door = false
    end

    return healed
end

function M.getUseTalentOptions(actor, actionData, context)
    actionData = actionData or {}
    context = context or {}

    local unavailableReasons = {}
    local function addUnavailable(reason)
        if not reason then
            return
        end
        for _, existing in ipairs(unavailableReasons) do
            if existing == reason then
                return
            end
        end
        unavailableReasons[#unavailableReasons + 1] = reason
    end

    local labels = {
        beast_master = "Beast Master",
        bookworm = "Bookworm",
        chirurgeon = "Chirurgery",
        high_chant = "High Chant",
        loremaster = "Loremaster",
        sneak = "Sneak",
        war_stories = "War Stories",
    }
    local details = {
        beast_master = "Teach or retrain an animal companion command",
        bookworm = "Record a readable book as lore",
        chirurgeon = "Heal a resting, non-Stressed guild-mate",
        high_chant = "Turn minor discard cards into inspiration",
        loremaster = "Translate a short ancient text",
        sneak = "Infiltrate a known location",
        war_stories = "Share a tale for Resolve or Bonds",
    }
    local resultPreviews = {
        beast_master = "companion_command_taught",
        bookworm = "bookworm_recorded",
        chirurgeon = "chirurgery_performed",
        high_chant = "high_chant_performed",
        loremaster = "translation_complete",
        sneak = "location_infiltrated",
        war_stories = "war_stories_shared",
    }

    local selectedTalentId = normalizeTalentId(actionData.talentId or actionData.talent or
        (actionData.request and (actionData.request.talentId or actionData.request.talent)))
    local selectedTalent = nil
    local talentOptions = {}
    for _, option in ipairs(M.getCampTalentOptions(actor)) do
        local record = {
            id = option.id,
            key = option.key,
            name = labels[option.id] or option.id,
            detail = details[option.id],
            resultPreview = resultPreviews[option.id],
            selected = selectedTalentId ~= "" and selectedTalentId == option.id,
            actionDataPreview = {
                type = "use_talent",
                talentId = option.id,
            },
        }
        if record.selected then
            selectedTalent = record
        end
        talentOptions[#talentOptions + 1] = record
    end

    if not actor then
        addUnavailable("no_actor")
    end
    if #talentOptions == 0 then
        addUnavailable("no_usable_camp_talent")
    end
    if selectedTalentId ~= "" and not selectedTalent then
        addUnavailable("selected_talent_unavailable")
    end

    local function entityPreview(entity)
        return {
            id = entity and entity.id or nil,
            name = entity and entity.name or nil,
            isPC = entity and entity.isPC == true,
        }
    end

    local function selectedEntityMatches(entity, selected, selectedId)
        if type(selected) == "table" then
            return selected == entity or (selected.id ~= nil and entity and selected.id == entity.id)
        end
        if selectedId ~= nil then
            return entity and entity.id == selectedId
        end
        return selected ~= nil and entity and entity.id == selected
    end

    local guild = type(context.guild) == "table" and context.guild or { actor }
    local branches = {}

    local function resolveAfter(entity)
        local value = entity and entity.resolve
        if type(value) == "table" then
            local current = tonumber(value.current) or 0
            return {
                current = current,
                max = math.max(tonumber(value.max) or 4, 5),
                after = math.min(current + 1, 5),
            }
        end
        local current = tonumber(value) or 0
        return {
            current = current,
            max = 5,
            after = math.min(current + 1, 5),
        }
    end

    local warStories = {
        talentId = "war_stories",
        disabled = false,
        participantOptions = {},
        resultPreview = "war_stories_shared",
    }
    for _, participant in ipairs(guild) do
        if participant and participant.isPC == true then
            local option = entityPreview(participant)
            option.resolvePreview = resolveAfter(participant)
            option.benefitOptions = {
                {
                    type = "resolve",
                    resultPreview = "resolve_gained",
                    actionDataPreview = {
                        type = "use_talent",
                        talentId = "war_stories",
                        participants = { participant },
                        benefits = {
                            [participant.id or participant.name or "participant"] = { type = "resolve" },
                        },
                    },
                },
            }
            for targetId, bond in pairs(participant.bonds or {}) do
                if type(bond) == "table" and bond.charged ~= true then
                    option.benefitOptions[#option.benefitOptions + 1] = {
                        type = "charge_bond",
                        bondTargetId = targetId,
                        bondName = bond.name,
                        resultPreview = "bond_charged",
                        actionDataPreview = {
                            type = "use_talent",
                            talentId = "war_stories",
                            participants = { participant },
                            benefits = {
                                [participant.id or participant.name or "participant"] = {
                                    type = "charge_bond",
                                    bondTargetId = targetId,
                                },
                            },
                        },
                    }
                end
            end
            warStories.participantOptions[#warStories.participantOptions + 1] = option
        end
    end
    if #warStories.participantOptions == 0 then
        warStories.disabled = true
        warStories.unavailableReason = "no_war_stories_participants"
    end
    branches.warStories = warStories

    local selectedBook = actionData.book or actionData.target or actionData.selectedBook
    local selectedBookId = actionData.bookId or actionData.targetId or actionData.selectedBookId or
        (type(selectedBook) == "table" and selectedBook.id or selectedBook)
    local bookworm = {
        talentId = "bookworm",
        disabled = false,
        bookOptions = {},
        resultPreview = "bookworm_recorded",
    }
    for _, entry in ipairs(campInventoryEntries(actor)) do
        local book = entry.item
        if isReadableBook(book) then
            local option = campItemOption(book, entry.location)
            local props = book.properties or {}
            option.subjectId = props.loreSubjectId
            option.subjectMatter = props.subjectMatter
            option.motifPreview = props.subjectMatter or book.name
            option.resultPreview = "bookworm_recorded"
            option.selected = selectedEntityMatches(book, selectedBook, selectedBookId)
            option.actionDataPreview = {
                type = "use_talent",
                talentId = "bookworm",
                targetId = book.id,
            }
            if option.selected then
                bookworm.selectedBook = option
            end
            bookworm.bookOptions[#bookworm.bookOptions + 1] = option
        end
    end
    if #bookworm.bookOptions == 0 then
        bookworm.disabled = true
        bookworm.unavailableReason = "Choose a book"
    elseif selectedBookId and not bookworm.selectedBook then
        bookworm.disabled = true
        bookworm.unavailableReason = "selected_book_not_readable"
    end
    branches.bookworm = bookworm

    local selectedPatient = actionData.target or actionData.patient or actionData.guildMate
    local selectedPatientId = actionData.targetId or actionData.patientId or actionData.guildMateId or
        (type(selectedPatient) == "table" and selectedPatient.id or selectedPatient)
    local chirurgery = {
        talentId = "chirurgeon",
        disabled = false,
        patientOptions = {},
        blockedPatients = {},
        resultPreview = "chirurgery_performed",
    }
    for _, member in ipairs(guild) do
        if member and member ~= actor and (not actor or member.id ~= actor.id) then
            local option = entityPreview(member)
            option.resting = targetIsRestingForChirurgery(member, { target = member }, context)
            option.stressed = member.conditions and member.conditions.stressed == true or false
            option.dead = member.conditions and member.conditions.dead == true or false
            option.healingPreview = {
                armorNotches = member.armorNotches or 0,
                woundedTalents = member.woundedTalents or 0,
                staggered = member.conditions and member.conditions.staggered == true or false,
                injured = member.conditions and member.conditions.injured == true or false,
                deathsDoor = member.conditions and member.conditions.deaths_door == true or false,
            }
            option.resultPreview = "chirurgery_performed"
            option.selected = selectedEntityMatches(member, selectedPatient, selectedPatientId)
            option.actionDataPreview = {
                type = "use_talent",
                talentId = "chirurgeon",
                targetId = member.id,
            }
            if member.isPC == false then
                option.disabled = true
                option.unavailableReason = "Chirurgery targets a guild-mate"
            elseif option.dead then
                option.disabled = true
                option.unavailableReason = "Target is dead"
            elseif option.stressed then
                option.disabled = true
                option.unavailableReason = "Target is Stressed"
            elseif not option.resting then
                option.disabled = true
                option.unavailableReason = "Target must use Rest and Recover"
            end
            if option.selected then
                chirurgery.selectedPatient = option
            end
            if option.disabled then
                chirurgery.blockedPatients[#chirurgery.blockedPatients + 1] = option
            else
                chirurgery.patientOptions[#chirurgery.patientOptions + 1] = option
            end
        end
    end
    if #chirurgery.patientOptions == 0 then
        chirurgery.disabled = true
        chirurgery.unavailableReason = "Target must use Rest and Recover"
    elseif selectedPatientId and not chirurgery.selectedPatient then
        chirurgery.disabled = true
        chirurgery.unavailableReason = "selected_patient_unavailable"
    elseif chirurgery.selectedPatient and chirurgery.selectedPatient.disabled then
        chirurgery.disabled = true
        chirurgery.unavailableReason = chirurgery.selectedPatient.unavailableReason
    end
    branches.chirurgery = chirurgery

    local function companionKnows(commandList, value)
        local wanted = animal_companions.normalizeCommandName(value)
        for key, known in pairs(commandList or {}) do
            if animal_companions.normalizeCommandName(animal_companions.getCommandEntryName(known, key)) == wanted then
                return true
            end
        end
        return false
    end

    local selectedCompanion = actionData.companion or actionData.target
    local selectedCompanionId = actionData.companionId or actionData.companion_id or actionData.targetId or
        (type(selectedCompanion) == "table" and selectedCompanion.id or selectedCompanion)
    local beastMaster = {
        talentId = "beast_master",
        disabled = false,
        companionOptions = {},
        resultPreview = "companion_command_taught",
    }
    local companions = {}
    if actor and actor.companion then
        companions[#companions + 1] = actor.companion
    end
    for _, companion in ipairs(actor and actor.animalCompanions or {}) do
        companions[#companions + 1] = companion
    end
    for _, companion in ipairs(companions) do
        local knownNames = {}
        local known = {}
        for key, command in pairs(companion.knownCommands or companion.commands or {}) do
            local name = animal_companions.getCommandEntryName(command, key)
            local normalized = animal_companions.normalizeCommandName(name)
            if normalized ~= "" and not known[normalized] then
                known[normalized] = true
                knownNames[#knownNames + 1] = animal_companions.getCommandDisplayName(normalized)
            end
        end
        local commandLimit = animal_companions.getCommandLimit(companion)
        local canMarkFamiliar = isTalentMastered(actor, "beast_master") and
            (not actor.familiarCompanionId or actor.familiarCompanionId == companion.id) and
            not companion.isFamiliar and not companion.familiar
        local option = {
            id = companion.id,
            name = companion.name,
            knownCommands = knownNames,
            commandLimit = commandLimit,
            atCommandLimit = #knownNames >= commandLimit,
            canMarkFamiliar = canMarkFamiliar,
            selected = selectedEntityMatches(companion, selectedCompanion, selectedCompanionId),
            commandOptions = {},
        }
        for _, commandId in ipairs(animal_companions.commandOrder or {}) do
            if not companionKnows(companion.knownCommands or companion.commands, commandId) then
                local command = animal_companions.getCommand(commandId)
                local commandName = command and command.name or animal_companions.getCommandDisplayName(commandId)
                if not option.atCommandLimit then
                    option.commandOptions[#option.commandOptions + 1] = {
                        command = commandName,
                        mode = "teach",
                        resultPreview = "companion_command_taught",
                        actionDataPreview = {
                            type = "use_talent",
                            talentId = "beast_master",
                            companionId = companion.id,
                            command = commandName,
                        },
                    }
                elseif canMarkFamiliar then
                    option.commandOptions[#option.commandOptions + 1] = {
                        command = commandName,
                        mode = "mark_familiar",
                        resultPreview = "companion_command_taught",
                        actionDataPreview = {
                            type = "use_talent",
                            talentId = "beast_master",
                            companionId = companion.id,
                            command = commandName,
                            makeFamiliar = true,
                        },
                    }
                else
                    for _, knownName in ipairs(knownNames) do
                        option.commandOptions[#option.commandOptions + 1] = {
                            command = commandName,
                            mode = "replace",
                            replaceCommand = knownName,
                            resultPreview = "companion_command_taught",
                            actionDataPreview = {
                                type = "use_talent",
                                talentId = "beast_master",
                                companionId = companion.id,
                                command = commandName,
                                replaceCommand = knownName,
                            },
                        }
                    end
                end
            end
        end
        if option.selected then
            beastMaster.selectedCompanion = option
        end
        beastMaster.companionOptions[#beastMaster.companionOptions + 1] = option
    end
    if #beastMaster.companionOptions == 0 then
        beastMaster.disabled = true
        beastMaster.unavailableReason = "Choose an animal companion"
    elseif selectedCompanionId and not beastMaster.selectedCompanion then
        beastMaster.disabled = true
        beastMaster.unavailableReason = "selected_companion_unavailable"
    end
    branches.beastMaster = beastMaster

    local discardPile = getHighChantDiscardPile(actionData, context)
    local selectedCards = actionData.cards or actionData.selectedCards or {}
    local selectedRecipients = actionData.recipients or actionData.targets or {}
    local usedRecipients = {}
    for _, recipient in ipairs(selectedRecipients) do
        usedRecipients[recipient] = true
        if recipient and recipient.id then
            usedRecipients[recipient.id] = true
        end
    end
    local highChant = {
        talentId = "high_chant",
        disabled = false,
        maxCards = math.max(0, tonumber(actor and actor.cups) or 0),
        cardOptions = {},
        recipientOptions = {},
        selectedCards = {},
        selectedRecipients = {},
        resultPreview = "high_chant_performed",
    }
    for _, card in ipairs(selectedCards) do
        highChant.selectedCards[#highChant.selectedCards + 1] = {
            name = card and card.name or nil,
            value = card and card.value or nil,
            suit = card and card.suit or nil,
        }
    end
    for _, recipient in ipairs(selectedRecipients) do
        highChant.selectedRecipients[#highChant.selectedRecipients + 1] = entityPreview(recipient)
    end
    if type(discardPile) == "table" then
        for i = 0, #discardPile - 1 do
            local card = discardPile[#discardPile - i]
            highChant.cardOptions[#highChant.cardOptions + 1] = {
                name = card and card.name or nil,
                value = card and card.value or nil,
                suit = card and card.suit or nil,
                selected = findCardIndex(selectedCards, card) ~= nil,
                resultPreview = "inspiration_card_available",
            }
        end
    end
    for _, member in ipairs(guild) do
        if member and member.isPC == true then
            local option = entityPreview(member)
            option.hasInspiration = member.inspirationCard ~= nil
            option.selected = usedRecipients[member] == true or (member.id and usedRecipients[member.id] == true)
            if option.hasInspiration then
                option.disabled = true
                option.unavailableReason = "recipient_already_has_inspiration"
            end
            highChant.recipientOptions[#highChant.recipientOptions + 1] = option
        end
    end
    if highChant.maxCards <= 0 then
        highChant.disabled = true
        highChant.unavailableReason = "No Cups for High Chant"
    elseif #highChant.cardOptions == 0 then
        highChant.disabled = true
        highChant.unavailableReason = "No minor discard cards"
    end
    branches.highChant = highChant

    branches.sneak = M.getInfiltrateOptions(actor, context, actionData)
    branches.sneak.talentId = "sneak"

    local selectedText = actionData.text or actionData.passage or actionData.inscription or
        actionData.document or actionData.book or actionData.target
    local selectedTextId = actionData.textId or actionData.targetId or
        (type(selectedText) == "table" and selectedText.id or selectedText)
    local loremaster = {
        talentId = "loremaster",
        disabled = false,
        textOptions = {},
        resultPreview = "translation_complete",
    }
    for _, entry in ipairs(campInventoryEntries(actor)) do
        local item = entry.item
        local props = item and item.properties or {}
        local hasText = item and (
            item.language ~= nil or item.script ~= nil or item.translatedText ~= nil or
            props.language ~= nil or props.script ~= nil or props.translatedText ~= nil or
            props.translation ~= nil or props.textKind ~= nil or props.ancientText == true
        )
        local longText = props.longText == true or props.requiresCityAction == true or
            item.type == "book" or props.book == true or props.readableBook == true
        if hasText and not longText then
            local option = campItemOption(item, entry.location)
            option.language = item.language or item.script or props.language or props.script
            option.translatedText = item.translatedText or props.translatedText or props.translation
            option.resultPreview = "translation_complete"
            option.selected = selectedEntityMatches(item, selectedText, selectedTextId)
            option.actionDataPreview = {
                type = "use_talent",
                talentId = "loremaster",
                targetId = item.id,
            }
            if option.selected then
                loremaster.selectedText = option
            end
            loremaster.textOptions[#loremaster.textOptions + 1] = option
        end
    end
    if #loremaster.textOptions == 0 then
        loremaster.disabled = true
        loremaster.unavailableReason = "Choose text to translate"
    elseif selectedTextId and not loremaster.selectedText then
        loremaster.disabled = true
        loremaster.unavailableReason = "selected_text_unavailable"
    end
    branches.loremaster = loremaster

    local selectedBranch = nil
    if selectedTalentId == "war_stories" then
        selectedBranch = warStories
    elseif selectedTalentId == "bookworm" then
        selectedBranch = bookworm
    elseif selectedTalentId == "chirurgeon" then
        selectedBranch = chirurgery
    elseif selectedTalentId == "beast_master" then
        selectedBranch = beastMaster
    elseif selectedTalentId == "high_chant" then
        selectedBranch = highChant
    elseif selectedTalentId == "sneak" then
        selectedBranch = branches.sneak
    elseif selectedTalentId == "loremaster" then
        selectedBranch = loremaster
    end
    if selectedBranch and selectedBranch.disabled then
        addUnavailable(selectedBranch.unavailableReason or selectedBranch.unavailableReasons and
            selectedBranch.unavailableReasons[1] or "selected_talent_unavailable")
    end

    return {
        result = "use_talent_options_ready",
        actor = actor,
        actorId = actor and actor.id or nil,
        actorName = actor and actor.name or nil,
        disabled = #unavailableReasons > 0,
        unavailableReasons = unavailableReasons,
        hasUsableCampTalent = #talentOptions > 0,
        requiresTalent = selectedTalent == nil,
        talentOptions = talentOptions,
        selectedTalent = selectedTalent,
        selectedBranch = selectedBranch,
        branches = branches,
        rules = {
            requiresUsableCampTalent = true,
            concreteTalentChoiceRequired = true,
            supportedTalents = {
                "beast_master",
                "bookworm",
                "chirurgeon",
                "high_chant",
                "loremaster",
                "sneak",
                "war_stories",
            },
        },
    }
end

local function resolveChirurgeryTalent(actor, actionData, context, eventBus)
    local target = actionData.target or actionData.patient or actionData.guildMate
    if not target then
        return false, "Choose a guild-mate"
    end
    if target == actor or (target.id ~= nil and actor and target.id == actor.id) then
        return false, "Chirurgery targets a guild-mate"
    end
    if target.isPC == false then
        return false, "Chirurgery targets a guild-mate"
    end
    if target.conditions and target.conditions.dead then
        return false, "Target is dead"
    end
    if target.conditions and target.conditions.stressed then
        return false, "Target is Stressed"
    end
    if not targetIsRestingForChirurgery(target, actionData, context) then
        return false, "Target must use Rest and Recover"
    end

    local healing = healAllWounds(target)
    local pactBreaks = M.breakPactsForRecoveryResult(target, "all_wounds_healed", {
        eventBus = eventBus,
        actionResolver = context.actionResolver or context.resolver,
    })

    local detail = {
        target = target,
        healing = healing,
        pactBreaks = pactBreaks,
    }

    eventBus:emit("camp_action_resolved", {
        action = "use_talent",
        talentId = "chirurgeon",
        actor = actor,
        target = target,
        result = "chirurgery_performed",
        healing = healing,
        pactBreaks = pactBreaks,
    })

    return true, "chirurgery_performed", detail
end

function M.resolveLoremasterTranslation(actor, actionData, context, eventBus)
    context = context or {}
    eventBus = eventBus or context.eventBus or events.globalBus
    actionData = actionData or {}

    if not hasUsableActionTalent(actor, "loremaster") then
        return false, "No usable Loremaster talent"
    end

    local request = actionData.request or actionData.translation or actionData
    if type(request) ~= "table" then
        request = { text = request }
    end
    local subject = request.text or request.passage or request.inscription or
        request.document or request.book or request.target or actionData.target
    if not subject then
        return false, "Choose text to translate"
    end

    local props = type(subject) == "table" and (subject.properties or {}) or {}
    local kind = request.kind or request.textKind or request.translationKind or
        (type(subject) == "table" and (subject.kind or subject.type or props.kind or props.textKind))
    kind = tostring(kind or ""):lower():gsub("%s+", "_")
    local longText = request.longText == true or request.long_text == true or request.requiresCityAction == true or
        request.cityActionRequired == true or kind == "book" or kind == "long_text" or
        (type(subject) == "table" and (subject.isBook == true or subject.readableBook == true or
            props.book == true or props.readableBook == true or props.longText == true or
            props.requiresCityAction == true))
    local cityAction = context.cityAction == true or context.cityPhase == true or actionData.cityAction == true
    if longText and not cityAction then
        return false, "Long translations require a City Action"
    end

    local language = request.language or request.script or
        (type(subject) == "table" and (subject.language or subject.script or props.language or props.script))
    if language then
        language = tostring(language):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    end

    local title = request.title or request.name or
        (type(subject) == "table" and (subject.name or subject.title or subject.id)) or
        tostring(subject)
    local translationId = request.translationId or request.id or
        (type(subject) == "table" and subject.id) or
        ("translation_" .. tostring(#(actor.translations or {}) + 1))
    local watches = tonumber(request.watches or request.watchCost or request.watchesRequired) or (longText and 0 or 1)
    if watches < 0 then
        watches = 0
    end

    local record = {
        id = translationId,
        title = title,
        language = language,
        longText = longText,
        cityAction = cityAction,
        watchesRequired = watches,
        translatedText = request.translatedText or request.translationText or request.answer or
            (type(subject) == "table" and (subject.translatedText or subject.translation or props.translatedText)),
        source = "loremaster",
    }

    actor.translations = actor.translations or {}
    actor.translations[#actor.translations + 1] = record
    actor.loremasterTranslations = actor.translations

    eventBus:emit("camp_action_resolved", {
        action = "use_talent",
        talentId = "loremaster",
        actor = actor,
        target = subject,
        translation = record,
        result = "translation_complete",
    })

    return true, "translation_complete", record
end

function M.resolveUseTalent(actor, actionData, context, eventBus)
    context = context or {}
    eventBus = eventBus or context.eventBus or events.globalBus
    actionData = actionData or {}

    local requested = actionData.talentId or actionData.talent or (actionData.request and actionData.request.talentId)
    local normalizedTalentId = findCampTalent(actor, requested)
    if not normalizedTalentId then
        return false, "No usable Camp talent"
    end

    if normalizedTalentId == "beast_master" then
        return resolveBeastMasterTalent(actor, actionData, eventBus)
    elseif normalizedTalentId == "chirurgeon" then
        return resolveChirurgeryTalent(actor, actionData, context, eventBus)
    elseif normalizedTalentId == "war_stories" then
        return resolveWarStoriesTalent(actor, actionData, context, eventBus)
    elseif normalizedTalentId == "high_chant" then
        return resolveHighChantTalent(actor, actionData, context, eventBus)
    elseif normalizedTalentId == "loremaster" then
        return M.resolveLoremasterTranslation(actor, actionData, context, eventBus)
    elseif normalizedTalentId == "sneak" then
        return M.resolveInfiltrate(actor, actionData, context, eventBus)
    elseif normalizedTalentId == "bookworm" then
        local book = actionData.book or actionData.target
        if not book then
            return false, "Choose a book"
        end
        local ok, entry = M.recordBookwormReading(actor, book)
        if not ok then
            return false, "Bookworm unavailable"
        end
        eventBus:emit("camp_action_resolved", {
            action = "use_talent",
            talentId = "bookworm",
            actor = actor,
            book = book,
            result = "bookworm_recorded",
            entry = entry,
        })
        return true, "bookworm_recorded", entry
    end

    return false, "Camp talent not implemented"
end

--------------------------------------------------------------------------------
-- READ A BOOK (S8.3)
--------------------------------------------------------------------------------
-- Ask one question based on the subject matter of a book carried by the actor.

function M.getReadBookOptions(actor, opts)
    opts = opts or {}
    local questionTypes = require('data.lore.question_types')
    local selectedBook = opts.book or opts.target or opts.selectedBook
    local selectedBookId = opts.bookId or opts.targetId or opts.selectedBookId or
        (type(selectedBook) == "table" and selectedBook.id or selectedBook)
    local selectedQuestionId = opts.questionType or opts.questionTypeId or opts.questionId or
        (type(opts.request) == "table" and (opts.request.questionType or opts.request.questionTypeId or
            opts.request.questionId))
    local cannotRead = actorCannotRead(actor)
    local bookOptions = {}
    local unavailableReasons = {}
    local unavailableSeen = {}
    local selectedBookOption = nil
    local selectedQuestionOption = nil
    local function addUnavailable(reason)
        if reason and not unavailableSeen[reason] then
            unavailableSeen[reason] = true
            unavailableReasons[#unavailableReasons + 1] = reason
        end
    end
    local function copyQuestion(question, book)
        local props = book and book.properties or {}
        local direct = directBookAnswer(book, question.id) ~= nil
        return {
            id = question.id,
            name = question.name,
            prompt = question.prompt,
            subjectId = props.loreSubjectId,
            subjectMatter = props.subjectMatter,
            hasDirectAnswer = direct,
            resultPreview = "book_answered",
            actionDataPreview = {
                type = "read_book",
                targetId = book and book.id or nil,
                request = {
                    questionType = question.id,
                },
            },
        }
    end
    local function questionOptionsForBook(book)
        local props = book and book.properties or {}
        local questions = {}
        if type(props.loreAnswers) == "table" then
            for _, question in ipairs(questionTypes.list()) do
                if props.loreAnswers[question.id] then
                    questions[#questions + 1] = copyQuestion(question, book)
                end
            end
        elseif props.loreSubjectId then
            local engine = opts.bidLoreEngine or opts.loreEngine or bid_lore_engine.createBidLoreEngine({})
            for _, question in ipairs(engine:getQuestionTypesForSubject(props.loreSubjectId)) do
                questions[#questions + 1] = copyQuestion(question, book)
            end
        else
            for _, question in ipairs(questionTypes.list()) do
                questions[#questions + 1] = copyQuestion(question, book)
            end
        end
        return questions
    end

    if not actor then
        addUnavailable("no_actor")
    elseif not actor.inventory then
        addUnavailable("no_inventory")
    end
    if cannotRead then
        addUnavailable("cannot_read")
    end

    for _, entry in ipairs(campInventoryEntries(actor)) do
        local book = entry.item
        if isReadableBook(book) then
            local option = campItemOption(book, entry.location)
            local props = book.properties or {}
            option.subjectId = props.loreSubjectId
            option.subjectMatter = props.subjectMatter
            option.loreMotif = props.loreMotif
            option.requiresQuestion = true
            option.questionOptions = questionOptionsForBook(book)
            option.hasQuestionOptions = #option.questionOptions > 0
            option.resultPreview = "book_question_required"
            option.actionDataPreview = {
                type = "read_book",
                targetId = book.id,
            }
            if cannotRead then
                option.disabled = true
                option.unavailableReason = "cannot_read"
            elseif #option.questionOptions == 0 then
                option.disabled = true
                option.unavailableReason = "no_supported_book_questions"
                addUnavailable(option.unavailableReason)
            end

            if selectedBookId and book.id == selectedBookId then
                selectedBookOption = option
                for _, question in ipairs(option.questionOptions) do
                    if selectedQuestionId and question.id == selectedQuestionId then
                        selectedQuestionOption = question
                        option.selectedQuestion = question
                        break
                    end
                end
            elseif type(selectedBook) == "table" and selectedBook == book then
                selectedBookOption = option
            end

            bookOptions[#bookOptions + 1] = option
        end
    end

    if #bookOptions == 0 then
        addUnavailable("no_readable_books")
    end
    if selectedBookId and not selectedBookOption then
        addUnavailable("selected_book_not_readable")
    elseif selectedBookOption and selectedBookOption.disabled then
        addUnavailable(selectedBookOption.unavailableReason or "selected_book_unavailable")
    elseif selectedQuestionId and selectedBookOption and not selectedQuestionOption then
        addUnavailable("selected_question_unavailable")
    end

    return {
        result = "read_book_options_ready",
        actor = actor,
        actorId = actor and actor.id or nil,
        actorName = actor and actor.name or nil,
        hasReadableBooks = #bookOptions > 0,
        hasResolvableOptions = #bookOptions > 0 and not cannotRead,
        disabled = #bookOptions == 0 or cannotRead,
        unavailableReasons = unavailableReasons,
        bookOptions = bookOptions,
        selectedBook = selectedBookOption,
        selectedQuestion = selectedQuestionOption,
        requiresQuestion = selectedBookOption ~= nil and selectedQuestionOption == nil,
        rules = {
            requiresCarriedReadableBook = true,
            asksOneBookScopedQuestion = true,
            spendsLoreBidUses = false,
            cannotReadBlocksAction = true,
        },
    }
end

function M.resolveReadBook(actor, book, request, context, eventBus)
    context = context or {}
    eventBus = eventBus or context.eventBus or events.globalBus
    book = book or findReadableBook(actor)
    request = request or context.readBookRequest or context.bookLoreRequest or context.loreRequest

    if actorCannotRead(actor) then
        return false, "Cannot read"
    end

    if not book or not isReadableBook(book) then
        return false, "Requires a readable book"
    end

    if not actorCarriesItem(actor, book) then
        return false, "Book must be carried"
    end

    local props = book.properties or {}
    if not request then
        actor.lastBookLoreResult = {
            result = "book_question_required",
            book = book,
            subjectId = props.loreSubjectId,
        }
        eventBus:emit("camp_action_resolved", {
            action = "read_book",
            actor = actor,
            target = book,
            book = book,
            result = "book_question_required",
            requiresQuestion = true,
            subjectId = props.loreSubjectId,
            subjectMatter = props.subjectMatter,
        })
        return true, "book_question_required"
    end

    if type(request) == "string" then
        request = { questionType = request }
    end

    local questionType = request.questionType or request.questionTypeId or request.questionId
    if not questionType then
        return false, "Choose one book question"
    end

    local response = directBookAnswer(book, questionType)
    local verdict = "accepted"
    local reason = "The book contains an answer to that question."
    local engineResult = nil

    if not response then
        local subjectId = request.subjectId or props.loreSubjectId
        if not subjectId then
            return false, "Book subject unavailable"
        end

        local engine = context.bidLoreEngine or context.loreEngine or bid_lore_engine.createBidLoreEngine({})
        engineResult = engine:adjudicate({
            subjectId = subjectId,
            questionType = questionType,
            motif = request.motif or props.loreMotif or props.subjectMatter or book.name,
            focus = request.focus,
        })

        verdict = engineResult.verdict
        reason = engineResult.reason
        if verdict == "accepted" then
            response = cloneResponse(engineResult.response)
        end
    end

    if verdict ~= "accepted" then
        local result = verdict == "rephrase_needed" and "book_rephrase_needed" or "book_question_unavailable"
        actor.lastBookLoreResult = {
            result = result,
            book = book,
            questionType = questionType,
            verdict = verdict,
            reason = reason,
            loreSpend = false,
        }
        eventBus:emit("camp_action_resolved", {
            action = "read_book",
            actor = actor,
            target = book,
            book = book,
            result = result,
            questionType = questionType,
            verdict = verdict,
            reason = reason,
            loreSpend = false,
            engineResult = engineResult,
        })
        return false, result
    end

    actor.lastBookLoreResult = {
        result = "book_answered",
        book = book,
        questionType = questionType,
        response = response,
        loreSpend = false,
    }
    local bookwormRecorded, bookwormEntry = M.recordBookwormReading(actor, book)
    eventBus:emit("camp_action_resolved", {
        action = "read_book",
        actor = actor,
        target = book,
        book = book,
        result = "book_answered",
        questionType = questionType,
        response = response,
        loreSpend = false,
        engineResult = engineResult,
        bookwormRecorded = bookwormRecorded,
        bookwormEntry = bookwormEntry,
    })

    print("[CAMP] " .. actor.name .. " reads " .. (book.name or "a book"))

    return true, "book_answered", response
end

--------------------------------------------------------------------------------
-- REST (S8.3)
--------------------------------------------------------------------------------
-- Generic fallback - no cost, no benefit other than safety.

function M.resolveRest(actor, eventBus)
    eventBus:emit("camp_action_resolved", {
        action = "rest",
        actor = actor,
        result = "rest_and_recover",
    })

    print("[CAMP] " .. actor.name .. " rests quietly")

    return true, "rest_and_recover"
end

--------------------------------------------------------------------------------
-- HEAL COMPANION (S8.3)
--------------------------------------------------------------------------------
-- Clear Injured from an animal companion. Requires a charged bond.

function M.resolveHealCompanion(actor, companion, eventBus)
    if not companion then
        return false, "No companion targeted"
    end

    -- Check if companion is injured
    if not companion.conditions or not companion.conditions.injured then
        return false, "Companion is not injured"
    end

    -- Check if actor has a charged bond (with anyone - represents care/attention)
    local hasChargedBond = false
    if actor.bonds then
        for _, bond in pairs(actor.bonds) do
            if bond.charged then
                hasChargedBond = true
                -- Spend the bond
                bond.charged = false
                break
            end
        end
    end

    if not hasChargedBond then
        return false, "Requires a charged bond"
    end

    -- Clear injured condition
    companion.conditions.injured = false

    eventBus:emit("camp_action_resolved", {
        action = "heal_companion",
        actor = actor,
        target = companion,
        result = "companion_healed",
    })

    print("[CAMP] " .. actor.name .. " tends to " .. (companion.name or "companion") ..
          " (injured cleared)")

    return true, "companion_healed"
end

--------------------------------------------------------------------------------
-- SCOUT (S8.3)
--------------------------------------------------------------------------------
-- Test Pentacles to reveal information about adjacent rooms.
-- Note: Full implementation requires room/map integration.

local function normalizeOutcome(outcome)
    if type(outcome) == "table" then
        outcome = outcome.outcome or outcome.result or outcome.degree or outcome.success
    end

    if outcome == true then return "success" end
    if outcome == false then return "failure" end

    outcome = tostring(outcome or "failure"):lower()
    outcome = outcome:gsub("%s+", "_")
    return outcome
end

local function canonicalTestOutcome(outcome)
    local result = normalizeOutcome(outcome)
    if result == "fail" then
        return "failure"
    elseif result == "great_fail" then
        return "great_failure"
    elseif result == "great_successes" then
        return "great_success"
    end
    return result
end

function M.resolveDevourLiving(actor, actionData, context, eventBus)
    context = context or {}
    actionData = actionData or {}
    eventBus = eventBus or context.eventBus or events.globalBus

    if not M.findUnbrokenActivePact(actor, "devour_living") then
        return false, "Requires Devour the Living pact"
    end

    local outcome = actionData.outcome or actionData.testResult or actionData.result
    if outcome == nil then
        eventBus:emit("camp_action_resolved", {
            action = "devour_living",
            actor = actor,
            result = "devour_living_test_required",
            requiresTest = true,
            testSuit = "cups",
        })
        return true, "devour_living_test_required"
    end

    local result = normalizeOutcome(outcome)
    local success = result == "success" or result == "great_success" or result == "great_successes"
    actor.devourLivingForage = {
        result = result,
        success = success,
    }

    if success then
        actor.devourLivingMealAvailable = true
        actor.devourLivingForageFailed = false
        eventBus:emit("camp_action_resolved", {
            action = "devour_living",
            actor = actor,
            result = "living_food_found",
            outcome = result,
        })
        return true, "living_food_found", actor.devourLivingForage
    end

    actor.devourLivingMealAvailable = false
    actor.devourLivingForageFailed = true
    eventBus:emit("camp_action_resolved", {
        action = "devour_living",
        actor = actor,
        result = "no_living_food",
        outcome = result,
    })
    return false, "no_living_food", actor.devourLivingForage
end

function M.resolveScout(actor, context, eventBus)
    eventBus = eventBus or events.globalBus

    eventBus:emit("camp_action_resolved", {
        action = "scout",
        actor = actor,
        result = "scout_initiated",
        requiresTest = true,
        testSuit = "pentacles",
    })

    print("[CAMP] " .. actor.name .. " scouts the area (test required)")

    return true, "scout_initiated"
end

local function firstScoutInformation(value)
    if type(value) == "table" then
        return value.hint or value.summary or value.description or value[1] or value
    end

    return value
end

local function scoutCurrentRoomId(actor, context)
    context = context or {}
    local watchManager = context.watchManager or context.manager
    return context.currentRoomId or context.roomId or context.currentRoom or
        (watchManager and watchManager.currentRoom) or
        (actor and actor.location)
end

local function scoutRoomManager(context)
    context = context or {}
    local watchManager = context.watchManager or context.manager
    return context.roomManager or (watchManager and watchManager.roomManager)
end

local function scoutDungeon(context)
    context = context or {}
    local watchManager = context.watchManager or context.manager
    return context.dungeon or (watchManager and watchManager.dungeon)
end

local function getManagedRoom(context, roomId)
    local manager = scoutRoomManager(context)
    if manager and manager.getRoom then
        return manager:getRoom(roomId)
    end
    return nil
end

local function collectScoutFeatures(room)
    local features = {}
    if not room or type(room.features) ~= "table" then
        return features
    end

    for _, feature in ipairs(room.features) do
        if feature.state ~= "hidden" and feature.state ~= "removed" and feature.state ~= "destroyed" then
            features[#features + 1] = {
                id = feature.id,
                name = feature.name,
                type = feature.type,
                hint = feature.hidden_description or feature.description,
                trap = feature.trap ~= nil,
                loot = feature.loot ~= nil,
            }
        end
    end

    return features
end

local function makeScoutSummary(room, connection)
    local roomName = room and (room.name or room.id) or "Unknown room"
    local direction = connection and connection.direction
    local prefix = direction and ("To the " .. tostring(direction) .. ", ") or ""
    local detail = connection and connection.description or
        (room and (room.base_description or room.description)) or
        "something nearby"
    return prefix .. tostring(roomName) .. ": " .. tostring(detail)
end

local function scoutAdjacentInformation(actor, context)
    context = context or {}
    local dungeon = scoutDungeon(context)
    if not dungeon or not dungeon.getAdjacentRooms then
        return nil
    end

    local roomId = scoutCurrentRoomId(actor, context)
    if not roomId then
        return nil
    end

    local adjacent = dungeon:getAdjacentRooms(roomId, {
        include_secret = context.includeSecretScout == true or context.includeSecrets == true,
        include_locked = context.includeLockedScout ~= false,
    })
    if #adjacent == 0 then
        return {}
    end

    local information = {}
    for _, entry in ipairs(adjacent) do
        local graphRoom = entry.room or {}
        local targetRoomId = graphRoom.id or (entry.connection and entry.connection.target_room_id)
        local room = getManagedRoom(context, targetRoomId) or graphRoom
        local connection = entry.connection or {}
        local features = collectScoutFeatures(room)
        local dangerLevel = room and room.danger_level or room and room.dangerLevel
        local hasSpecialRoom = (room and room.socialEncounter ~= nil) or #features > 0 or
            (dangerLevel and dangerLevel >= 3)

        information[#information + 1] = {
            roomId = targetRoomId,
            roomName = room and (room.name or graphRoom.name),
            direction = connection.direction,
            summary = makeScoutSummary(room, connection),
            description = room and (room.base_description or room.description or graphRoom.description),
            connectionDescription = connection.description,
            locked = connection.is_locked == true or nil,
            secret = connection.is_secret == true or nil,
            dangerLevel = dangerLevel,
            specialRoom = hasSpecialRoom or nil,
            features = features,
        }
    end

    return information
end

local function scoutInformation(context, fullReport)
    local information = context.scoutInfo or context.nearbyInfo or context.adjacentInfo
    if not information then
        information = scoutAdjacentInformation(context.actor, context) or {}
    end

    if fullReport then
        return context.greatSuccessInfo or context.fullScoutInfo or information
    end

    return firstScoutInformation(context.hint or context.scoutHint or information) or {}
end

function M.getScoutOutcomeOptions(actor, context, opts)
    context = context or {}
    opts = opts or {}

    local function clonePreview(value, seen)
        if type(value) ~= "table" then
            return value
        end
        seen = seen or {}
        if seen[value] then
            return seen[value]
        end
        local copy = {}
        seen[value] = copy
        for key, nested in pairs(value) do
            copy[clonePreview(key, seen)] = clonePreview(nested, seen)
        end
        return copy
    end
    local function previewContext()
        local out = {}
        for key, value in pairs(context) do
            out[key] = value
        end
        out.actor = out.actor or actor
        return out
    end

    local selectedRaw = opts.outcome or opts.selectedOutcome or context.outcome
    local selectedOutcome = selectedRaw ~= nil and canonicalTestOutcome(selectedRaw) or nil
    local infoContext = previewContext()
    local successInfo = clonePreview(scoutInformation(infoContext, false))
    local fullInfo = clonePreview(scoutInformation(infoContext, true))
    local outcomes = {
        {
            outcome = "success",
            name = "Success",
            detail = "Reveal one nearby hint",
            resultPreview = "scout_hint",
            success = true,
            informationPreview = successInfo,
        },
        {
            outcome = "great_success",
            name = "Great Success",
            detail = "Reveal a full adjacent-room report",
            resultPreview = "full_scout_report",
            success = true,
            informationPreview = fullInfo,
            fullReport = true,
        },
        {
            outcome = "failure",
            name = "Failure",
            detail = "Nothing learned",
            resultPreview = "nothing_learned",
            success = false,
        },
        {
            outcome = "great_failure",
            name = "Great Failure",
            detail = "Challenge triggered",
            resultPreview = "challenge_triggered",
            success = false,
            challengeTriggered = true,
        },
    }

    local selectedOption = nil
    for _, option in ipairs(outcomes) do
        option.action = "scout"
        option.testSuit = "pentacles"
        option.requiresTest = true
        option.actionDataPreview = {
            type = "scout",
            outcome = option.outcome,
        }
        if selectedOutcome and option.outcome == selectedOutcome then
            option.selected = true
            selectedOption = option
        end
    end

    local unavailableReasons = {}
    if selectedOutcome and not selectedOption then
        unavailableReasons[#unavailableReasons + 1] = "selected_outcome_unavailable"
    end

    return {
        result = "scout_outcome_options_ready",
        actor = actor,
        actorId = actor and actor.id or nil,
        actorName = actor and actor.name or nil,
        requiresTest = true,
        testSuit = "pentacles",
        disabled = false,
        unavailableReasons = unavailableReasons,
        outcomeOptions = outcomes,
        selectedOutcome = selectedOption,
        rules = {
            successRevealsHint = true,
            greatSuccessRevealsFullReport = true,
            failureLearnsNothing = true,
            greatFailureTriggersChallenge = true,
        },
    }
end

function M.resolveScoutOutcome(actor, outcome, context, eventBus)
    context = context or {}
    context.actor = context.actor or actor
    eventBus = eventBus or events.globalBus

    local result = normalizeOutcome(outcome)
    if result == "great_failure" or result == "great_fail" then
        context.challengeTriggered = true
        actor.lastScoutResult = {
            result = "challenge_triggered",
            information = nil,
            outcome = result,
        }
        eventBus:emit("camp_action_resolved", {
            action = "scout",
            actor = actor,
            result = "challenge_triggered",
            outcome = result,
        })
        return false, "challenge_triggered"
    end

    if result == "failure" or result == "fail" then
        actor.lastScoutResult = {
            result = "nothing_learned",
            information = nil,
            outcome = result,
        }
        eventBus:emit("camp_action_resolved", {
            action = "scout",
            actor = actor,
            result = "nothing_learned",
            outcome = result,
        })
        return false, "nothing_learned"
    end

    local scoutResult = "scout_hint"
    local fullReport = result == "great_success" or result == "great_successes"
    if fullReport then
        scoutResult = "full_scout_report"
    end
    local information = scoutInformation(context, fullReport)

    actor.lastScoutResult = {
        result = scoutResult,
        information = information,
        outcome = result,
    }
    eventBus:emit("camp_action_resolved", {
        action = "scout",
        actor = actor,
        result = scoutResult,
        information = information,
        outcome = result,
    })

    return true, scoutResult, information
end

--------------------------------------------------------------------------------
-- HUNT (S8.3)
--------------------------------------------------------------------------------
-- Test Swords with a missile weapon. Outcomes are resolved after the test.

function M.getHuntOutcomeOptions(actor, context, opts)
    context = context or {}
    opts = opts or {}

    local method, reason = M.getHuntMethod(actor, context)
    local selectedRaw = opts.outcome or opts.selectedOutcome or context.outcome
    local selectedOutcome = selectedRaw ~= nil and canonicalTestOutcome(selectedRaw) or nil
    local outcomes = {
        {
            outcome = "success",
            name = "Success",
            detail = "Fresh game found",
            resultPreview = "fresh_game_found",
            success = true,
            itemPreview = {
                templateId = "fresh_game",
                name = "Fresh Game",
                freshGame = true,
                meals = 1,
            },
        },
        {
            outcome = "great_success",
            name = "Great Success",
            detail = "Large game found",
            resultPreview = "large_game_found",
            success = true,
            itemPreview = {
                templateId = "fresh_game_feast",
                name = "Large Fresh Game",
                freshGame = true,
                meals = "guild",
            },
        },
        {
            outcome = "failure",
            name = "Failure",
            detail = "No game found",
            resultPreview = "no_game",
            success = false,
        },
        {
            outcome = "great_failure",
            name = "Great Failure",
            detail = "Challenge triggered",
            resultPreview = "challenge_triggered",
            success = false,
            challengeTriggered = true,
        },
    }

    local selectedOption = nil
    for _, option in ipairs(outcomes) do
        option.action = "hunt"
        option.method = method
        option.testSuit = "swords"
        option.requiresTest = true
        option.disabled = method == nil
        option.unavailableReason = method == nil and reason or nil
        option.actionDataPreview = {
            type = "hunt",
            outcome = option.outcome,
        }
        if selectedOutcome and option.outcome == selectedOutcome then
            option.selected = true
            selectedOption = option
        end
    end

    local unavailableReasons = {}
    if not method then
        unavailableReasons[#unavailableReasons + 1] = reason
    end
    if selectedOutcome and not selectedOption then
        unavailableReasons[#unavailableReasons + 1] = "selected_outcome_unavailable"
    end

    return {
        result = "hunt_outcome_options_ready",
        actor = actor,
        actorId = actor and actor.id or nil,
        actorName = actor and actor.name or nil,
        method = method,
        hasHuntMethod = method ~= nil,
        requiresTest = true,
        testSuit = "swords",
        disabled = method == nil,
        unavailableReasons = unavailableReasons,
        outcomeOptions = outcomes,
        selectedOutcome = selectedOption,
        rules = {
            missileWeaponCanHunt = true,
            fishingGearRequiresWater = true,
            successFindsFreshGame = true,
            greatSuccessFindsLargeGame = true,
            failureFindsNoGame = true,
            greatFailureTriggersChallenge = true,
        },
    }
end

function M.resolveHunt(actor, context, eventBus)
    context = context or {}
    local method, reason = M.getHuntMethod(actor, context)
    if not method then
        return false, reason
    end

    eventBus:emit("camp_action_resolved", {
        action = "hunt",
        actor = actor,
        result = "hunt_initiated",
        method = method,
        requiresTest = true,
        testSuit = "swords",
    })

    if method == "fishing" then
        print("[CAMP] " .. actor.name .. " fishes for food (Swords test required)")
    else
        print("[CAMP] " .. actor.name .. " hunts for game (Swords test required)")
    end

    return true, "hunt_initiated"
end

function M.resolveHuntOutcome(actor, outcome, context, eventBus)
    context = context or {}
    eventBus = eventBus or events.globalBus

    local method, reason = M.getHuntMethod(actor, context)
    if not method then
        return false, reason
    end

    local result = normalizeOutcome(outcome)
    if result == "great_failure" or result == "great_fail" then
        context.challengeTriggered = true
        eventBus:emit("camp_action_resolved", {
            action = "hunt",
            actor = actor,
            result = "challenge_triggered",
        })
        return false, "challenge_triggered"
    end

    if result == "failure" or result == "fail" then
        eventBus:emit("camp_action_resolved", {
            action = "hunt",
            actor = actor,
            result = "no_game",
        })
        return false, "no_game"
    end

    local templateId = (result == "great_success" or result == "great_successes") and
        "fresh_game_feast" or "fresh_game"
    local gameItem = inventory.createItemFromTemplate(templateId)
    if not actor.inventory or not actor.inventory.addItem then
        return false, "No inventory for game"
    end

    local added, err = actor.inventory:addItem(gameItem, inventory.LOCATIONS.PACK)
    if not added then
        return false, err or "insufficient_slots"
    end

    eventBus:emit("camp_action_resolved", {
        action = "hunt",
        actor = actor,
        item = gameItem,
        method = method,
        result = templateId == "fresh_game_feast" and "large_game_found" or "fresh_game_found",
    })

    if method == "fishing" then
        gameItem.properties = gameItem.properties or {}
        gameItem.properties.gatheredByFishing = true
        print("[CAMP] " .. actor.name .. " returns from fishing with " .. gameItem.name)
    else
        print("[CAMP] " .. actor.name .. " returns with " .. gameItem.name)
    end

    return true, templateId == "fresh_game_feast" and "large_game_found" or "fresh_game_found", gameItem
end

function M.resolvePreserveHuntedGame(actor, gameItem, opts, eventBus)
    opts = opts or {}
    eventBus = eventBus or events.globalBus

    if not isFreshGame(gameItem) then
        return false, "Requires fresh game"
    end

    if not actor.inventory or not actor.inventory.removeItem then
        return false, "No inventory for game"
    end

    local salt = findSaltItem(actor)
    if not salt then
        return false, "Requires salt"
    end

    if actor.inventory.removeItemQuantity then
        actor.inventory:removeItemQuantity(salt.id, 1)
    else
        actor.inventory:removeItem(salt.id)
    end

    actor.inventory:removeItem(gameItem.id)

    local meals = gameItem.properties.meals
    local rationCount = opts.rationCount
    if not rationCount then
        if meals == "guild" then
            rationCount = opts.guildSize or #(opts.guild or {}) or 1
        else
            rationCount = tonumber(meals) or 1
        end
    end
    rationCount = math.max(1, rationCount)

    local ration = inventory.createItemFromTemplate("ration", { quantity = rationCount })
    local added, err = actor.inventory:addItem(ration, inventory.LOCATIONS.PACK)
    if not added then
        return false, err or "insufficient_slots"
    end

    eventBus:emit("camp_action_resolved", {
        action = "preserve_hunted_game",
        actor = actor,
        source = gameItem,
        ration = ration,
        rationCount = rationCount,
        result = "game_preserved",
    })

    print("[CAMP] " .. actor.name .. " preserves hunted game into " .. rationCount .. " ration(s)")

    return true, "game_preserved", ration
end

function M.resolveCookHuntedGame(actor, gameItem, opts, eventBus)
    opts = opts or {}
    eventBus = eventBus or events.globalBus

    if not isFreshGame(gameItem) then
        return false, "Requires fresh game"
    end

    if not actor.inventory or not actor.inventory.removeItem then
        return false, "No inventory for game"
    end

    if not hasCookingGear(actor) then
        return false, "Requires cooking gear"
    end

    actor.inventory:removeItem(gameItem.id)

    local meals = gameItem.properties.meals
    local mealCount = opts.mealCount
    if not mealCount then
        if meals == "guild" then
            mealCount = opts.guildSize or #(opts.guild or {}) or 1
        else
            mealCount = tonumber(meals) or 1
        end
    end
    mealCount = math.max(1, mealCount)

    local meal = inventory.createItemFromTemplate("cooked_game_meal", { quantity = mealCount })
    local added, err = actor.inventory:addItem(meal, inventory.LOCATIONS.PACK)
    if not added then
        return false, err or "insufficient_slots"
    end

    eventBus:emit("camp_action_resolved", {
        action = "cook_hunted_game",
        actor = actor,
        source = gameItem,
        meal = meal,
        mealCount = mealCount,
        result = "game_cooked",
    })

    print("[CAMP] " .. actor.name .. " cooks hunted game into " .. mealCount .. " meal(s)")

    return true, "game_cooked", meal
end

--------------------------------------------------------------------------------
-- PATROL (S8.3)
--------------------------------------------------------------------------------
-- Keep watch. Draw twice from Meatgrinder during Watch phase.

function M.resolvePatrol(actor, context, eventBus)
    context = context or {}
    eventBus = eventBus or events.globalBus

    -- Mark that patrol was taken - affects Watch phase
    context.patrolActive = true
    context.patrolActor = actor

    eventBus:emit("camp_action_resolved", {
        action = "patrol",
        actor = actor,
        result = "patrolling",
    })

    print("[CAMP] " .. actor.name .. " takes patrol duty (double Meatgrinder draw)")

    return true, "patrol_active"
end

--------------------------------------------------------------------------------
-- UPDATE MAPS (S8.3)
--------------------------------------------------------------------------------
-- Record rooms travelled since the last Camp Phase as mapped.

local function appendRoomId(out, seen, roomId)
    if roomId and not seen[roomId] then
        seen[roomId] = true
        out[#out + 1] = roomId
    end
end

local function collectMappedRoomIds(context)
    local out = {}
    local seen = {}

    local function appendList(items)
        for _, value in ipairs(items or {}) do
            if type(value) == "table" then
                appendRoomId(out, seen, value.id or value.roomId)
            else
                appendRoomId(out, seen, value)
            end
        end
    end

    appendList(context.traveledRooms or context.roomsTraveled or context.roomsSinceLastCamp or context.rooms)

    local watchManager = context.watchManager
    if watchManager and watchManager.getRoomsTraveledSinceLastMap then
        appendList(watchManager:getRoomsTraveledSinceLastMap())
    end

    appendRoomId(out, seen, context.currentRoom or context.currentRoomId or context.roomId)
    if watchManager and watchManager.getCurrentRoom then
        appendRoomId(out, seen, watchManager:getCurrentRoom())
    end

    return out
end

function M.getUpdateMapsOptions(actor, context, opts)
    context = context or {}
    opts = opts or {}

    local watchManager = context.watchManager
    local roomManager = context.roomManager or (watchManager and watchManager.roomManager)
    local dungeon = context.dungeon or (watchManager and watchManager.dungeon)
    local mapState = context.guildMap or context.mapState
    local selectedRooms = opts.rooms or opts.selectedRooms or context.selectedRooms
    local roomIds = collectMappedRoomIds(context)
    local function currentRoomId()
        if context.currentRoomId or context.roomId then
            return context.currentRoomId or context.roomId
        end
        if type(context.currentRoom) == "table" then
            return context.currentRoom.id or context.currentRoom.roomId
        end
        if context.currentRoom then
            return context.currentRoom
        end
        if watchManager and watchManager.getCurrentRoom then
            return watchManager:getCurrentRoom()
        end
        return nil
    end
    local function lookupRoom(roomId)
        if roomManager and roomManager.getRoom then
            local room = roomManager:getRoom(roomId)
            if room then
                return room
            end
        end
        if dungeon and dungeon.getRoom then
            return dungeon:getRoom(roomId)
        end
        return nil
    end
    local function copyRoomIds(ids)
        local out = {}
        for i, roomId in ipairs(ids or {}) do
            out[i] = roomId
        end
        return out
    end
    local function selectedMatches(ids)
        if type(selectedRooms) ~= "table" then
            return false
        end
        if #selectedRooms ~= #ids then
            return false
        end
        for i, roomId in ipairs(ids) do
            local selected = selectedRooms[i]
            if type(selected) == "table" then
                selected = selected.id or selected.roomId
            end
            if selected ~= roomId then
                return false
            end
        end
        return true
    end

    local routeOptions = {}
    local selectedRoute = nil
    if #roomIds > 0 then
        local current = currentRoomId()
        local roomOptions = {}
        local labels = {}
        for _, roomId in ipairs(roomIds) do
            local room = lookupRoom(roomId)
            local name = (room and room.name) or tostring(roomId)
            labels[#labels + 1] = name
            roomOptions[#roomOptions + 1] = {
                id = roomId,
                roomId = roomId,
                name = name,
                current = current == roomId,
                alreadyMapped = mapState and mapState.mappedRooms and mapState.mappedRooms[roomId] == true or false,
            }
        end

        local route = {
            id = "travelled_route",
            label = "Map Travelled Route",
            detail = table.concat(labels, ", "),
            rooms = roomOptions,
            roomIds = copyRoomIds(roomIds),
            roomCount = #roomIds,
            resultPreview = "maps_updated",
            mappedRoomTravelPerWatch = 2,
            actionDataPreview = {
                type = "update_maps",
                rooms = copyRoomIds(roomIds),
            },
        }
        if selectedMatches(roomIds) then
            route.selected = true
            selectedRoute = route
        end
        routeOptions[#routeOptions + 1] = route
    end

    local unavailableReasons = {}
    if #routeOptions == 0 then
        unavailableReasons[#unavailableReasons + 1] = "no_rooms_to_map"
    elseif type(selectedRooms) == "table" and not selectedRoute then
        unavailableReasons[#unavailableReasons + 1] = "selected_route_unavailable"
    end

    return {
        result = "update_maps_options_ready",
        actor = actor,
        actorId = actor and actor.id or nil,
        actorName = actor and actor.name or nil,
        hasRoomsToMap = #routeOptions > 0,
        disabled = #routeOptions == 0,
        unavailableReasons = unavailableReasons,
        routeOptions = routeOptions,
        selectedRoute = selectedRoute,
        rules = {
            mapsTravelledRooms = true,
            mappedRoomTravelPerWatch = 2,
            deDuplicatesRooms = true,
        },
    }
end

function M.resolveUpdateMaps(actor, context, eventBus)
    context = context or {}
    eventBus = eventBus or context.eventBus or events.globalBus

    local roomIds = collectMappedRoomIds(context)
    if #roomIds == 0 then
        return false, "No rooms to map"
    end

    local mapState = context.guildMap or context.mapState
    if mapState then
        mapState.mappedRooms = mapState.mappedRooms or {}
        for _, roomId in ipairs(roomIds) do
            mapState.mappedRooms[roomId] = true
        end
        mapState.mappedRoomTravelPerWatch = 2
    end

    local watchManager = context.watchManager
    if watchManager then
        if watchManager.markMappedRooms then
            watchManager:markMappedRooms(roomIds)
        end
        if watchManager.setMappedRoomTravelPerWatch then
            watchManager:setMappedRoomTravelPerWatch(2)
        end
        if watchManager.clearRoomsTraveledSinceLastMap then
            watchManager:clearRoomsTraveledSinceLastMap()
        end
    end

    actor.lastMapUpdate = {
        result = "maps_updated",
        rooms = roomIds,
        mappedRoomTravelPerWatch = 2,
    }

    eventBus:emit("camp_action_resolved", {
        action = "update_maps",
        actor = actor,
        result = "maps_updated",
        rooms = roomIds,
        mappedRoomTravelPerWatch = 2,
    })

    print("[CAMP] " .. actor.name .. " updates the guild map (" .. #roomIds .. " room(s))")

    return true, "maps_updated", roomIds
end

-- CATEGORY DISPLAY NAME
--------------------------------------------------------------------------------

function M.getCategoryDisplayName(category)
    local names = {
        [M.CATEGORIES.MAINTENANCE] = "Maintenance",
        [M.CATEGORIES.SOCIAL] = "Social",
        [M.CATEGORIES.EXPLORATION] = "Exploration",
        [M.CATEGORIES.REST] = "Rest",
    }
    return names[category] or category
end

return M
