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

local M = {}

local function normalizeActionTalentId(talentId)
    return tostring(talentId or ""):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
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
        requiresRangedAmmo = true,
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
        description = "Use a Camp-phase item such as leeches.",
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
    {
        id = "tend_affliction",
        name = "Tend Affliction",
        category = M.CATEGORIES.REST,
        description = "Test Cups to clear an Affliction from yourself or an ally.",
        requiresTarget = true,
        targetType = "pc",
        testSuit = "cups",
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
function M.getAvailableActions(entity, guild)
    local available = {}

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

        if action.requiresRangedAmmo and not M.hasMissileWeapon(entity) then
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
        if action.targetType == "pc" and action.id ~= "tend_affliction" then
            local hasOtherPCs = false
            if guild then
                for _, pc in ipairs(guild) do
                    if pc.id ~= entity.id then
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
        return M.resolveFellowship(actor, target, eventBus)
    elseif actionData.type == "read_book" then
        return M.resolveReadBook(actor, target, actionData.request or actionData.loreRequest, context, eventBus)
    elseif actionData.type == "train" then
        return M.resolveTrain(actor, target, actionData, context, eventBus)
    elseif actionData.type == "use_talent" then
        return M.resolveUseTalent(actor, actionData, context, eventBus)
    elseif actionData.type == "make_pact" then
        return M.resolveMakePact(actor, actionData, context, eventBus)
    elseif actionData.type == "devour_living" then
        return M.resolveDevourLiving(actor, actionData, context, eventBus)
    elseif actionData.type == "rest" then
        return M.resolveRest(actor, eventBus)
    elseif actionData.type == "heal_companion" then
        return M.resolveHealCompanion(actor, target, eventBus)
    elseif actionData.type == "scout" then
        return M.resolveScout(actor, context, eventBus)
    elseif actionData.type == "hunt" then
        return M.resolveHunt(actor, context, eventBus)
    elseif actionData.type == "patrol" then
        return M.resolvePatrol(actor, context, eventBus)
    elseif actionData.type == "update_maps" then
        return M.resolveUpdateMaps(actor, context, eventBus)
    elseif actionData.type == "tend_affliction" then
        return M.resolveTendAffliction(actor, target, context, eventBus)
    end

    return false, "Action not implemented: " .. actionData.type
end

function M.hasMissileWeapon(actor)
    local inv = actor and actor.inventory
    if not inv then
        return false
    end

    for _, location in ipairs({ "hands", "belt", "pack" }) do
        for _, item in ipairs(inv[location] or {}) do
            local weaponType = item.weaponType or item.type
            if item.uses_ammo or weaponType == "bow" or weaponType == "crossbow" then
                return true
            end
        end
    end

    return false
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

local function findReadableBook(actor)
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

local function isCampUsableItem(item)
    local props = item and item.properties or {}
    return props.leeches == true or props.campUse == true
end

function M.hasCampUsableItem(actor)
    local inv = actor and actor.inventory
    if not inv or not inv.findItemByPredicate then
        return false
    end

    return inv:findItemByPredicate(isCampUsableItem) ~= nil
end

local function findCampActionItem(actor, itemId)
    local inv = actor and actor.inventory
    if not inv then
        return nil
    end
    if itemId and inv.findItem then
        return inv:findItem(itemId)
    end
    if inv.findItemByPredicate then
        return inv:findItemByPredicate(isCampUsableItem)
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

function M.resolveRepair(actor, targetItem, eventBus)
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
        action = "repair",
        actor = actor,
        target = targetItem,
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

function M.resolveFletchArrows(actor, eventBus)
    if not M.hasMissileWeapon(actor) then
        return false, "Requires a bow or crossbow"
    end

    local previousAmmo = actor.ammo or 0
    actor.ammo = math.max(previousAmmo, 12)

    eventBus:emit("camp_action_resolved", {
        action = "fletch_arrows",
        actor = actor,
        previousAmmo = previousAmmo,
        ammo = actor.ammo,
        result = "ammo_refilled",
    })

    print("[CAMP] " .. actor.name .. " fletches ammunition (ammo: " .. actor.ammo .. ")")

    return true, "ammo_refilled"
end

--------------------------------------------------------------------------------
-- USE AN ITEM (S8.3)
--------------------------------------------------------------------------------
-- Implements healthful Camp items currently called out by the rulebook.

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
    if props.leeches ~= true then
        return false, "Item is not usable during Camp"
    end

    target = target or actor
    if not target then
        return false, "No target for item"
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

function M.resolveFellowship(actor, targetPC, eventBus)
    if not targetPC then
        return false, "No companion targeted for fellowship"
    end

    if actor.id == targetPC.id then
        return false, "Cannot fellowship with yourself"
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
        return nil
    end
    return entity.talents[talentId]
end

local function normalizeTalentId(talentId)
    return tostring(talentId or ""):lower():gsub("%s+", "_"):gsub("'", "")
end

local CAMP_TALENTS = {
    beast_master = true,
    bookworm = true,
    chirurgeon = true,
    high_chant = true,
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
        if isAlchemyReagent(item) then
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
        if carried and isAlchemyReagent(carried) and not used[carried.id] then
            return carried, location
        end
        return nil, nil
    end

    for _, entry in ipairs(inv:getAllItems()) do
        local item = entry.item
        if isAlchemyReagent(item) and not used[item.id] and matchesReagentRequest(item, request) then
            return item, entry.location
        end
    end

    return nil, nil
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

        local reagent, location = findAlchemyReagent(actor, request, used)
        if not reagent then
            return false, "Requires alchemical reagent"
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
    local talentId = request.talentId or request.talent or request.id
    if not talentId then
        return false, "Choose a talent to train"
    end

    if not isTalentMastered(trainer, talentId) then
        return false, "Trainer has not mastered that talent"
    end

    local xpAmount = math.max(1, tonumber(request.xp or request.amount or request.xpInvested) or 1)
    if not spendXP(actor, xpAmount) then
        return false, "Not enough XP"
    end

    actor.talents = actor.talents or {}
    local talent = actor.talents[talentId]
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
    talent.mentored = true
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

local function resolveBeastMasterTalent(actor, actionData, eventBus)
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

    if not listContainsText(companion.knownCommands, command) then
        local replace = actionData.replaceCommand or actionData.replace_command or
            (actionData.request and (actionData.request.replaceCommand or actionData.request.replace_command))
        if #companion.knownCommands >= 3 then
            if not replace then
                return false, "Companion already knows three commands"
            end

            local replaced = false
            for i, known in ipairs(companion.knownCommands) do
                if tostring(known):lower() == tostring(replace):lower() then
                    companion.knownCommands[i] = command
                    replaced = true
                    break
                end
            end
            if not replaced then
                return false, "Replacement command not known"
            end
        else
            companion.knownCommands[#companion.knownCommands + 1] = command
        end
    end

    eventBus:emit("camp_action_resolved", {
        action = "use_talent",
        talentId = "beast_master",
        actor = actor,
        companion = companion,
        command = command,
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

function M.resolveReadBook(actor, book, request, context, eventBus)
    context = context or {}
    eventBus = eventBus or context.eventBus or events.globalBus
    book = book or findReadableBook(actor)
    request = request or context.readBookRequest or context.bookLoreRequest or context.loreRequest

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

function M.resolveHunt(actor, context, eventBus)
    if not M.hasMissileWeapon(actor) then
        return false, "Requires a missile weapon"
    end

    eventBus:emit("camp_action_resolved", {
        action = "hunt",
        actor = actor,
        result = "hunt_initiated",
        requiresTest = true,
        testSuit = "swords",
    })

    print("[CAMP] " .. actor.name .. " hunts for game (Swords test required)")

    return true, "hunt_initiated"
end

function M.resolveHuntOutcome(actor, outcome, context, eventBus)
    context = context or {}
    eventBus = eventBus or events.globalBus

    if not M.hasMissileWeapon(actor) then
        return false, "Requires a missile weapon"
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
        result = templateId == "fresh_game_feast" and "large_game_found" or "fresh_game_found",
    })

    print("[CAMP] " .. actor.name .. " returns with " .. gameItem.name)

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

--------------------------------------------------------------------------------
-- TEND AFFLICTION (S8.3)
--------------------------------------------------------------------------------
-- Test Cups to clear an Affliction from yourself or an ally.
-- Note: Full implementation requires affliction system.

function M.resolveTendAffliction(actor, target, context, eventBus)
    target = target or actor

    -- Check if target has any affliction
    local hasAffliction = false
    local afflictionName = nil

    if target.afflictions then
        for name, _ in pairs(target.afflictions) do
            hasAffliction = true
            afflictionName = name
            break
        end
    end

    if not hasAffliction then
        return false, "Target has no affliction to tend"
    end

    eventBus:emit("camp_action_resolved", {
        action = "tend_affliction",
        actor = actor,
        target = target,
        affliction = afflictionName,
        result = "tend_initiated",
        requiresTest = true,
        testSuit = "cups",
    })

    print("[CAMP] " .. actor.name .. " tends to " .. target.name ..
          "'s " .. (afflictionName or "affliction") .. " (test required)")

    return true, "tend_initiated"
end

--------------------------------------------------------------------------------
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
