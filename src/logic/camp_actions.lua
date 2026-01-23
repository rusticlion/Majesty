-- camp_actions.lua
-- Data registry of Camp Actions for Majesty
-- Ticket S8.3: Camp Actions Implementation
--
-- Defines the actions players can take during Step 1 of Camp Phase.
-- Reference: Rulebook p. 137-139

local events = require('logic.events')

local M = {}

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
        name = "Scout",
        category = M.CATEGORIES.EXPLORATION,
        description = "Test Pentacles to reveal information about adjacent rooms.",
        requiresTarget = false,
        testSuit = "pentacles",
    },
    {
        id = "patrol",
        name = "Patrol",
        category = M.CATEGORIES.EXPLORATION,
        description = "Keep watch. Draw twice from Meatgrinder during Watch phase.",
        requiresTarget = false,
    },

    ----------------------------------------------------------------------------
    -- REST ACTIONS
    ----------------------------------------------------------------------------
    {
        id = "rest",
        name = "Rest",
        category = M.CATEGORIES.REST,
        description = "Simply rest. No cost, no benefit beyond safety.",
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
    elseif actionData.type == "fellowship" then
        return M.resolveFellowship(actor, target, eventBus)
    elseif actionData.type == "rest" then
        return M.resolveRest(actor, eventBus)
    elseif actionData.type == "heal_companion" then
        return M.resolveHealCompanion(actor, target, eventBus)
    elseif actionData.type == "scout" then
        return M.resolveScout(actor, context, eventBus)
    elseif actionData.type == "patrol" then
        return M.resolvePatrol(actor, context, eventBus)
    elseif actionData.type == "tend_affliction" then
        return M.resolveTendAffliction(actor, target, context, eventBus)
    end

    return false, "Action not implemented: " .. actionData.type
end

--------------------------------------------------------------------------------
-- REPAIR (S8.3)
--------------------------------------------------------------------------------
-- Remove 1 Notch from an item. Requires Tinker's Kit.

function M.resolveRepair(actor, targetItem, eventBus)
    if not targetItem then
        return false, "No item targeted for repair"
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
    targetItem.notches = targetItem.notches - 1

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
-- REST (S8.3)
--------------------------------------------------------------------------------
-- Generic fallback - no cost, no benefit other than safety.

function M.resolveRest(actor, eventBus)
    eventBus:emit("camp_action_resolved", {
        action = "rest",
        actor = actor,
        result = "rested",
    })

    print("[CAMP] " .. actor.name .. " rests quietly")

    return true, "rested"
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

function M.resolveScout(actor, context, eventBus)
    -- This would normally involve a Pentacles test
    -- For MVP, mark actor as having scouted

    eventBus:emit("camp_action_resolved", {
        action = "scout",
        actor = actor,
        result = "scouted",
        requiresTest = true,
        testSuit = "pentacles",
    })

    print("[CAMP] " .. actor.name .. " scouts the area (test required)")

    return true, "scout_initiated"
end

--------------------------------------------------------------------------------
-- PATROL (S8.3)
--------------------------------------------------------------------------------
-- Keep watch. Draw twice from Meatgrinder during Watch phase.

function M.resolvePatrol(actor, context, eventBus)
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
