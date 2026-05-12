-- camp_controller.lua
-- Camp Phase State Machine for Majesty
-- Ticket S8.1: Orchestrates the 5 steps of the Camp Phase
--
-- Flow (Rulebook p. 136):
-- 1. SETUP    - Verify shelter/bedroll availability
-- 2. ACTIONS  - Each adventurer takes a camp action
-- 3. BREAK_BREAD - Consume rations (starvation if none)
-- 4. WATCH    - Meatgrinder draw for overnight events
-- 5. RECOVERY - Burn bonds to heal, clear stress
-- 6. TEARDOWN - Return to Crawl phase

local events = require('logic.events')
local campActions = require('logic.camp_actions')
local constants = require('constants')
local fateResolver = require('logic.resolver')
local inventory = require('logic.inventory')

local M = {}

local function normalizeTalentId(talentId)
    return tostring(talentId or ""):lower():gsub("[%s%-]+", "_"):gsub("[’']", "")
end

local function hasControllerUsableTalent(entity, talentId)
    if not entity then
        return false
    end
    if entity.canUseTalent and entity:canUseTalent(talentId) then
        return true
    end

    local requested = normalizeTalentId(talentId)
    for id, talent in pairs(entity.talents or {}) do
        if normalizeTalentId(id) == requested then
            if type(talent) == "table" then
                return talent.wounded ~= true
            end
            return talent == true
        end
    end

    return false
end

--------------------------------------------------------------------------------
-- CAMP STATES
--------------------------------------------------------------------------------
M.STATES = {
    INACTIVE    = "inactive",
    SETUP       = "setup",
    ACTIONS     = "actions",
    BREAK_BREAD = "break_bread",
    WATCH       = "watch",
    RECOVERY    = "recovery",
    TEARDOWN    = "teardown",
}

--------------------------------------------------------------------------------
-- CAMP EVENTS
--------------------------------------------------------------------------------
M.EVENTS = {
    CAMP_START         = "camp_start",
    CAMP_END           = "camp_end",
    CAMP_STEP_CHANGED  = "camp_step_changed",
    RATION_CONSUMED    = "ration_consumed",
    RATION_ASHED       = "ration_ashed",
    NIGHTMARE          = "camp_nightmare",
    VERMIN_THEFT       = "camp_vermin_theft",
    STARVATION_WARNING = "starvation_warning",
    BOND_SPENT         = "bond_spent",
    CAMP_ACTION_TAKEN  = "camp_action_taken",
    CONDITION_EXPIRED  = "camp_condition_expired",
}

--------------------------------------------------------------------------------
-- CAMP CONTROLLER FACTORY
--------------------------------------------------------------------------------

--- Create a new CampController
-- @param config table: { eventBus, guild, watchManager, inventory }
-- @return CampController instance
function M.createCampController(config)
    config = config or {}

    local controller = {
        eventBus     = config.eventBus or events.globalBus,
        guild        = config.guild or {},
        watchManager = config.watchManager,
        meatgrinder  = config.meatgrinder,
        playerDeck   = config.playerDeck,
        actionResolver = config.actionResolver,

        -- State tracking
        state        = M.STATES.INACTIVE,
        currentStep  = 0,

        -- Per-camp tracking
        actionsCompleted   = {},  -- { [entityId] = actionData }
        extraCampActionsUsed = {}, -- { [entityId] = true }
        rationsConsumed    = {},  -- { [entityId] = true }
        animalFeedConsumed = {},  -- { [companionId] = true }
        recoveryCompleted  = {},  -- { [entityId] = true }
        watchResolved      = false,
        patrolActive       = false,  -- True if someone took Patrol action

        -- Shelter status (affects recovery quality)
        hasShelter   = false,
        hasBedrolls  = false,
        hasTent      = false,
        hasFire      = false,
        fireViolatesForegoWood = false,
    }

    ----------------------------------------------------------------------------
    -- STATE QUERIES
    ----------------------------------------------------------------------------

    function controller:getState()
        return self.state
    end

    function controller:getCurrentStep()
        return self.currentStep
    end

    function controller:isActive()
        return self.state ~= M.STATES.INACTIVE
    end

    function controller:detectCampComfortFromGuild()
        local detected = {
            hasBedrolls = false,
            hasTent = false,
            hasFire = false,
            fireViolatesForegoWood = false,
        }

        local function scanItem(item)
            local props = item and item.properties or {}
            local templateId = item and item.templateId
            local name = item and item.name

            if templateId == "bedroll" or name == "Bedroll" or props.bedroll or props.campComfort == "bedroll" then
                detected.hasBedrolls = true
            end
            if templateId == "tent" or name == "Tent" or props.shelter or props.campComfort == "tent" then
                detected.hasTent = true
            end
            if templateId == "firewood" or name == "Firewood" or props.firewood or props.campComfort == "fire" then
                detected.hasFire = true
                if props.felledWood ~= false and props.archwood ~= true and props.willingWood ~= true then
                    detected.fireViolatesForegoWood = true
                end
            end
        end

        for _, member in ipairs(self.guild or {}) do
            local inv = member and member.inventory
            if inv then
                for _, location in ipairs({ "hands", "belt", "pack" }) do
                    for _, item in ipairs(inv[location] or {}) do
                        scanItem(item)
                    end
                end
            end
        end

        return detected
    end

    ----------------------------------------------------------------------------
    -- START CAMP
    ----------------------------------------------------------------------------

    --- Start the camp phase
    -- @param campConfig table: { hasShelter, hasBedrolls, hasTent, hasFire }
    -- @return boolean, string: success, error message
    function controller:startCamp(campConfig)
        if self.state ~= M.STATES.INACTIVE then
            return false, "Camp already in progress"
        end

        campConfig = campConfig or {}

        -- Reset tracking
        self.actionsCompleted = {}
        self.extraCampActionsUsed = {}
        self.rationsConsumed = {}
        self.animalFeedConsumed = {}
        self.recoveryCompleted = {}
        self.watchResolved = false
        self.patrolActive = false

        local detectedComfort = self:detectCampComfortFromGuild()

        -- Explicit camp flags override inventory-derived comfort.
        self.hasShelter = campConfig.hasShelter or false
        local explicitBedrolls = campConfig.hasBedrolls
        if explicitBedrolls == nil then explicitBedrolls = campConfig.hasBedroll end
        local explicitTent = campConfig.hasTent
        if explicitTent == nil then explicitTent = campConfig.hasTents end
        self.hasBedrolls = explicitBedrolls
        if self.hasBedrolls == nil then self.hasBedrolls = detectedComfort.hasBedrolls end
        self.hasTent = explicitTent
        if self.hasTent == nil then self.hasTent = detectedComfort.hasTent end
        self.hasFire = campConfig.hasFire
        if self.hasFire == nil then self.hasFire = detectedComfort.hasFire end
        self.fireViolatesForegoWood = campConfig.fireViolatesForegoWood
        if self.fireViolatesForegoWood == nil then
            self.fireViolatesForegoWood = campConfig.firewoodBoughtWithGold or campConfig.fireBoughtWithGold or
                campConfig.fireIsFelledWood
        end
        if self.fireViolatesForegoWood == nil then
            self.fireViolatesForegoWood = detectedComfort.fireViolatesForegoWood
        end
        if not self.hasFire then
            self.fireViolatesForegoWood = false
        end

        -- Emit start event
        self.eventBus:emit(M.EVENTS.CAMP_START, {
            guild = self.guild,
            hasShelter = self.hasShelter,
            hasBedrolls = self.hasBedrolls,
            hasTent = self.hasTent,
            hasFire = self.hasFire,
            fireViolatesForegoWood = self.fireViolatesForegoWood,
        })

        -- Move to setup
        self:transitionTo(M.STATES.SETUP)

        return true
    end

    ----------------------------------------------------------------------------
    -- STATE TRANSITIONS
    ----------------------------------------------------------------------------

    --- Transition to a new state
    function controller:transitionTo(newState)
        local oldState = self.state
        self.state = newState

        -- Map state to step number
        local stepMap = {
            [M.STATES.SETUP]       = 0,
            [M.STATES.ACTIONS]     = 1,
            [M.STATES.BREAK_BREAD] = 2,
            [M.STATES.WATCH]       = 3,
            [M.STATES.RECOVERY]    = 4,
            [M.STATES.TEARDOWN]    = 5,
        }
        self.currentStep = stepMap[newState] or 0

        self.eventBus:emit(M.EVENTS.CAMP_STEP_CHANGED, {
            oldState = oldState,
            newState = newState,
            step = self.currentStep,
        })

        print("[CAMP] Transitioned to: " .. newState .. " (Step " .. self.currentStep .. ")")

        -- Auto-execute certain steps
        if newState == M.STATES.SETUP then
            self:executeSetup()
        elseif newState == M.STATES.RECOVERY then
            for _, pc in ipairs(self.guild) do
                self:beginRecovery(pc)
            end
        end
    end

    --- Advance to next step
    function controller:advanceStep()
        if self.state == M.STATES.SETUP then
            self:transitionTo(M.STATES.ACTIONS)
        elseif self.state == M.STATES.ACTIONS then
            if self:canAdvanceFromActions() then
                self:transitionTo(M.STATES.BREAK_BREAD)
            else
                return false, "Not all adventurers have taken actions"
            end
        elseif self.state == M.STATES.BREAK_BREAD then
            if self:canAdvanceFromBreakBread() then
                self:transitionTo(M.STATES.WATCH)
            else
                return false, "Rations not resolved for all adventurers"
            end
        elseif self.state == M.STATES.WATCH then
            if self.watchResolved then
                self:transitionTo(M.STATES.RECOVERY)
            else
                return false, "Watch not resolved"
            end
        elseif self.state == M.STATES.RECOVERY then
            self:finalizeRecovery()
            self:transitionTo(M.STATES.TEARDOWN)
        elseif self.state == M.STATES.TEARDOWN then
            self:endCamp()
        end

        return true
    end

    ----------------------------------------------------------------------------
    -- STEP 0: SETUP
    ----------------------------------------------------------------------------

    function controller:executeSetup()
        -- Check shelter conditions
        if not self.hasShelter then
            print("[CAMP] Warning: No shelter - reduced recovery quality")
        end

        -- Auto-advance to actions after brief setup
        self:transitionTo(M.STATES.ACTIONS)
    end

    ----------------------------------------------------------------------------
    -- STEP 1: ACTIONS (S8.3)
    ----------------------------------------------------------------------------

    function controller:canUseLaborUnending(entity)
        if not entity or not entity.id then
            return false, "No actor"
        end
        if self.extraCampActionsUsed[entity.id] then
            return false, "Labor Unending already used"
        end
        if not hasControllerUsableTalent(entity, "labor_unending") then
            return false, "Requires Labor Unending"
        end
        if entity.conditions and entity.conditions.stressed then
            return false, "Already Stressed"
        end
        return true, nil
    end

    function controller:markLaborUnendingUsed(entity)
        entity.conditions = entity.conditions or {}
        entity.conditions.stressed = true
        self.extraCampActionsUsed[entity.id] = true
        self.eventBus:emit("labor_unending_used", {
            entity = entity,
            actor = entity,
        })
    end

    --- Submit a camp action for an adventurer
    -- @param entity table: The adventurer
    -- @param actionData table: { type, target, ... }
    function controller:submitAction(entity, actionData)
        if self.state ~= M.STATES.ACTIONS then
            return false, "Not in actions phase"
        end

        local previousAction = self.actionsCompleted[entity.id]
        local laborUnendingExtra = false
        if previousAction then
            if actionData.useLaborUnending == true or actionData.laborUnending == true then
                local canUseLabor, laborReason = self:canUseLaborUnending(entity)
                if not canUseLabor then
                    return false, laborReason
                end
                laborUnendingExtra = true
            else
                return false, "Action already taken"
            end
        end

        -- Add actor to action data
        actionData.actor = entity

        local actionsCompleted = self.actionsCompleted
        if laborUnendingExtra then
            actionsCompleted = {}
            for id, completedAction in pairs(self.actionsCompleted) do
                if id ~= entity.id then
                    actionsCompleted[id] = completedAction
                end
            end
        end

        -- Resolve the action through camp_actions module
        local context = {
            eventBus = self.eventBus,
            guild = self.guild,
            patrolActive = self.patrolActive,
            actionsCompleted = actionsCompleted,
            campController = self,
            playerDeck = self.playerDeck,
            laborUnendingExtra = laborUnendingExtra,
        }

        local success, result = campActions.resolveAction(actionData, context)

        if success then
            -- Track patrol status for watch phase
            if actionData.type == "patrol" then
                self.patrolActive = true
            end

            if laborUnendingExtra then
                actionData.laborUnendingExtra = true
                self:markLaborUnendingUsed(entity)
                self.actionsCompleted[entity.id] = {
                    type = "labor_unending",
                    actor = entity,
                    laborUnending = true,
                    actions = { previousAction, actionData },
                }
            else
                self.actionsCompleted[entity.id] = actionData
            end
            if actionData.type == "train" and actionData.target then
                self.actionsCompleted[actionData.target.id] = {
                    type = "train_mentor",
                    actor = actionData.target,
                    target = entity,
                    talentId = actionData.talentId or (actionData.request and actionData.request.talentId),
                }
            end

            self.eventBus:emit(M.EVENTS.CAMP_ACTION_TAKEN, {
                entity = entity,
                action = actionData,
                result = result,
            })

            print("[CAMP] " .. entity.name .. " takes action: " .. (actionData.type or "unknown"))
        end

        return success, result
    end

    --- Get available camp actions for an entity
    function controller:getAvailableActions(entity)
        return campActions.getAvailableActions(entity, self.guild)
    end

    function controller:canAdvanceFromActions()
        -- Check all guild members have submitted actions
        for _, pc in ipairs(self.guild) do
            if not self.actionsCompleted[pc.id] then
                return false
            end
        end
        return true
    end

    ----------------------------------------------------------------------------
    -- STEP 2: BREAK BREAD (S8.2)
    ----------------------------------------------------------------------------

    local function findRationItem(entity)
        if not entity.inventory or not entity.inventory.findItemByPredicate then
            return nil, nil
        end

        return entity.inventory:findItemByPredicate(function(item)
            local props = item.properties or {}
            return item.isRation or
                   item.type == "ration" or
                   item.itemType == "ration" or
                   props.isRation or
                   props.isCampMeal or
                   (item.name and item.name:lower():find("ration"))
        end)
    end

    local function removeConsumableItem(entity, item)
        if not entity.inventory or not item then
            return false
        end

        if entity.inventory.removeItemQuantity then
            local ok = entity.inventory:removeItemQuantity(item.id, 1)
            return ok == true
        elseif entity.inventory.removeItem then
            local removed = entity.inventory:removeItem(item.id)
            return removed ~= nil
        end

        return false
    end

    local function hasMaledictionFlag(entity, flag)
        if not entity then
            return false
        end
        if entity[flag] == true then
            return true
        end

        local malediction = entity.malediction
        local curse = malediction and malediction.curse
        local flags = curse and curse.flags
        return malediction and malediction.active ~= false and flags and flags[flag] == true
    end

    local function maledictionMetadata(entity)
        local malediction = entity and entity.malediction
        if malediction and malediction.active ~= false then
            return malediction.metadata or {}
        end
        return {}
    end

    local function indexedOpt(value, index, item)
        if type(value) ~= "table" then
            return value
        end
        if value[index] ~= nil then
            return value[index]
        end
        if item and value[item.id] ~= nil then
            return value[item.id]
        end
        if item and value[item.templateId] ~= nil then
            return value[item.templateId]
        end
        return nil
    end

    local function firstProvided(...)
        for i = 1, select("#", ...) do
            local value = select(i, ...)
            if value ~= nil then
                return value
            end
        end
        return nil
    end

    local function nextRecoveryWoundResult(entity)
        if not entity or not entity.conditions then
            return nil
        end
        if entity.conditions.deaths_door then
            return "deaths_door_healed"
        end
        if entity.conditions.stressed then
            return nil
        end
        if entity.conditions.injured then
            return "injured_healed"
        end
        if entity.conditions.staggered then
            return "staggered_healed"
        end
        if (entity.woundedTalents or 0) > 0 then
            return "talent_healed"
        end
        if (entity.armorNotches or 0) > 0 then
            return "armor_repaired"
        end
        return "fully_healed"
    end

    local function recoveryNeedsExtraBond(entity)
        if not hasMaledictionFlag(entity, "maledictionExtraBondRecoveryCost") then
            return false
        end
        local nextResult = nextRecoveryWoundResult(entity)
        return nextResult == "injured_healed" or nextResult == "talent_healed"
    end

    local function selectExtraRecoveryBond(entity, primaryBondTargetId, opts)
        opts = opts or {}
        local requested = opts.extraBondTargetId or opts.secondBondTargetId or
            opts.additionalBondTargetId or opts.extraRecoveryBondTargetId
        if requested and requested == primaryBondTargetId then
            return nil, "Second recovery Bond must be different"
        end
        if requested then
            local bond = entity.bonds and entity.bonds[requested]
            if not bond or not bond.charged then
                return nil, "Requires two charged Bonds"
            end
            return requested, nil
        end

        for targetId, bond in pairs(entity.bonds or {}) do
            if targetId ~= primaryBondTargetId and bond.charged then
                return targetId, nil
            end
        end

        return nil, "Requires two charged Bonds"
    end

    local function foodTurnsToAsh(entity, opts, index, item)
        if not hasMaledictionFlag(entity, "foodMayTurnToAsh") then
            return false
        end

        local explicit = indexedOpt(firstProvided(opts.rationAsh, opts.ashFood, opts.foodTurnsToAsh), index, item)
        if explicit ~= nil then
            return explicit == true
        end

        local metadata = maledictionMetadata(entity)
        local chance = tonumber(entity.rationAshChance or metadata.rationAshChance) or 0.5
        local roll = indexedOpt(firstProvided(opts.rationAshRoll, opts.ashRoll, opts.foodAshRoll), index, item)
        if roll ~= nil then
            return (tonumber(roll) or 1) <= chance
        end

        return math.random() <= chance
    end

    local function badDreamsWakeStressed(entity, opts)
        opts = opts or {}
        if not hasMaledictionFlag(entity, "badDreams") then
            return false
        end

        local explicit = firstProvided(opts.badDreams, opts.badDream, opts.nightmare)
        if explicit ~= nil then
            return explicit == true
        end

        local metadata = maledictionMetadata(entity)
        local chance = tonumber(entity.wakeStressedChance or metadata.wakeStressedChance) or 0.5
        local roll = firstProvided(opts.badDreamRoll, opts.nightmareRoll, opts.wakeStressedRoll)
        if roll ~= nil then
            return (tonumber(roll) or 1) <= chance
        end

        return math.random() <= chance
    end

    local function verminStealFromPack(entity, opts)
        opts = opts or {}
        if not hasMaledictionFlag(entity, "verminFollow") then
            return nil
        end

        local inv = entity.inventory
        if not inv or not inv.pack or #inv.pack == 0 then
            return nil
        end

        local explicit = firstProvided(opts.verminTheft, opts.verminPackSwap, opts.verminSwap)
        if explicit ~= nil and explicit == false then
            return nil
        end

        if explicit == nil then
            local metadata = maledictionMetadata(entity)
            local chance = tonumber(entity.nightlyPackSwapChance or metadata.nightlyPackSwapChance) or 0.5
            local roll = firstProvided(opts.verminTheftRoll, opts.verminPackSwapRoll, opts.verminSwapRoll)
            if roll ~= nil then
                if (tonumber(roll) or 1) > chance then
                    return nil
                end
            elseif math.random() > chance then
                return nil
            end
        end

        local itemId = opts.verminTheftItemId or opts.verminItemId
        local item = nil
        if itemId and inv.findItem then
            local found, location = inv:findItem(itemId)
            if location == inventory.LOCATIONS.PACK then
                item = found
            end
        end

        if not item then
            local index = math.max(1, math.floor(tonumber(opts.verminTheftIndex or opts.verminPackIndex) or 1))
            item = inv.pack[index] or inv.pack[1]
        end

        if not item then
            return nil
        end

        local removed = inv.removeItem and inv:removeItem(item.id) or nil
        if not removed then
            return nil
        end

        local garbage = opts.verminGarbageItem or inventory.createItem({
            name = opts.verminGarbageName or "Nice Garbage",
            size = 1,
            durability = 1,
            properties = {
                garbage = true,
                verminReplacement = true,
            },
        })
        local added, addReason = inv:addItem(garbage, inventory.LOCATIONS.PACK)

        local detail = {
            entity = entity,
            stolenItem = removed,
            garbageItem = garbage,
            garbageAdded = added == true,
            addReason = addReason,
            curseId = entity.maledictionCurseId or "beloved_by_vermin",
            result = "vermin_pack_swap",
        }
        entity.verminThefts = entity.verminThefts or {}
        entity.verminThefts[#entity.verminThefts + 1] = detail

        return detail
    end

    local function animalCompanionEntries(owner)
        local entries = {}

        for key, companion in pairs(owner and owner.animalCompanions or {}) do
            if type(companion) == "table" then
                entries[#entries + 1] = {
                    key = key,
                    companion = companion,
                }
            end
        end

        table.sort(entries, function(a, b)
            return tostring(a.key) < tostring(b.key)
        end)

        return entries
    end

    local function companionFeedKey(owner, companion, key)
        if companion and companion.id then
            return companion.id
        end

        if key == nil then
            for _, entry in ipairs(animalCompanionEntries(owner)) do
                if entry.companion == companion then
                    key = entry.key
                    break
                end
            end
        end

        local ownerId = owner and owner.id or "owner"
        return ownerId .. "_companion_" .. tostring(key or companion)
    end

    local function animalFeedMatchesCompanion(item, companion)
        local props = item and item.properties or {}
        local feedFor = props.feedFor or props.animalType or props.animalKind

        if not feedFor or feedFor == "any" then
            return true
        end

        feedFor = tostring(feedFor):lower()
        local candidates = {
            companion and companion.id,
            companion and companion.type,
            companion and companion.animalType,
            companion and companion.species,
            companion and companion.kind,
            companion and companion.name,
        }

        for _, candidate in ipairs(candidates) do
            if candidate and tostring(candidate):lower() == feedFor then
                return true
            end
        end

        return false
    end

    local function findAnimalFeedItem(owner, companion)
        if not owner or not owner.inventory or not owner.inventory.findItemByPredicate then
            return nil, nil
        end

        return owner.inventory:findItemByPredicate(function(item)
            local props = item.properties or {}
            local isFeed = item.type == "animal_feed" or
                           item.itemType == "animal_feed" or
                           props.isAnimalFeed or
                           props.animalFeed
            return isFeed and animalFeedMatchesCompanion(item, companion)
        end)
    end

    local function hasUsableTalent(entity, talentId)
        if not entity then
            return false
        end

        if entity.canUseTalent and entity:canUseTalent(talentId) then
            return true
        end

        local talent = entity.talents and entity.talents[talentId]
        if type(talent) == "table" then
            return not talent.wounded
        end
        return talent == true
    end

    local function canChargeBond(entity, targetId)
        if not targetId or not entity.bonds then
            return false
        end

        local bond = entity.bonds[targetId]
        return bond ~= nil and not bond.charged
    end

    local function chargeBond(entity, targetId)
        if not canChargeBond(entity, targetId) then
            return false
        end

        entity.bonds[targetId].charged = true
        return true
    end

    local function activeGluttonyPact(entity)
        return campActions.findUnbrokenActivePact(entity, "gluttony")
    end

    local function activeDevourLivingPact(entity)
        return campActions.findUnbrokenActivePact(entity, "devour_living")
    end

    local function breakPactWithReason(controllerRef, entity, pact, reason)
        if not pact then
            return nil
        end

        local ok, result, detail = campActions.breakPact(entity, pact, {
            eventBus = controllerRef.eventBus,
            actionResolver = controllerRef.actionResolver,
            reason = reason,
        })
        if not ok then
            return {
                result = result,
            }
        end

        return detail
    end

    local function breakGluttonyPact(controllerRef, entity, pact)
        return breakPactWithReason(controllerRef, entity, pact, "gluttony_underfed")
    end

    local function breakDevourLivingPact(controllerRef, entity, pact)
        return breakPactWithReason(controllerRef, entity, pact, "devour_living_forbidden_food")
    end

    local function breakPactsForRecoveryResult(controllerRef, entity, recoveryResult)
        return campActions.breakPactsForRecoveryResult(entity, recoveryResult, {
            eventBus = controllerRef.eventBus,
            actionResolver = controllerRef.actionResolver,
        })
    end

    function controller:markAdventurerUnfed(entity, opts)
        opts = opts or {}
        entity.starvationCount = (entity.starvationCount or 0) + 1

        -- First missed meal: Stressed
        if not entity.conditions then
            entity.conditions = {}
        end
        entity.conditions.stressed = true

        -- Second consecutive missed meal: Starving
        if entity.starvationCount >= 2 then
            entity.conditions.starving = true
            self.eventBus:emit(M.EVENTS.STARVATION_WARNING, {
                entity = entity,
                severity = "starving",
            })
            print("[CAMP] " .. entity.name .. " is STARVING!")
        else
            self.eventBus:emit(M.EVENTS.STARVATION_WARNING, {
                entity = entity,
                severity = "hungry",
            })
            print("[CAMP] " .. entity.name .. " goes hungry (stressed)")
        end

        if opts.ashedItems and #opts.ashedItems > 0 then
            self.eventBus:emit(M.EVENTS.RATION_ASHED, {
                entity = entity,
                items = opts.ashedItems,
                count = #opts.ashedItems,
                result = opts.result or "ration_ashed",
            })
        end

        self.rationsConsumed[entity.id] = true
        self:resolveAnimalFeedsForOwner(entity)
        return false, opts.result or "no_ration"
    end

    --- Consume a ration for an adventurer (S9.2)
    -- @param entity table: The adventurer
    -- @param opts table: Optional { rationCount, chargeBondTargetId }
    -- @return boolean, string: success, result description
    function controller:consumeRation(entity, opts)
        if self.state ~= M.STATES.BREAK_BREAD then
            return false, "Not in break bread phase"
        end

        opts = opts or {}

        local canUseHaleAndHearty = hasUsableTalent(entity, "hale_and_hearty") and
            canChargeBond(entity, opts.chargeBondTargetId)
        local explicitRationCount = opts.rationCount ~= nil or opts.rations ~= nil
        local gluttonyPact = activeGluttonyPact(entity)
        local devourPact = activeDevourLivingPact(entity)
        local devourLivingFood = opts.livingFood == true or opts.devourLivingFood == true or
            entity.devourLivingMealAvailable == true
        local devourForbiddenFood = opts.consumeForbiddenRation == true or opts.eatForbiddenRation == true or
            opts.allowForbiddenRation == true

        if devourPact and devourLivingFood then
            entity.starvationCount = 0
            if entity.conditions and entity.conditions.starving then
                entity.conditions.starving = false
            end
            entity.devourLivingMealAvailable = false
            entity.devourLivingForageFailed = false

            self.rationsConsumed[entity.id] = true
            self.eventBus:emit(M.EVENTS.RATION_CONSUMED, {
                entity = entity,
                count = 0,
                livingFood = true,
                pact = devourPact,
                result = "living_food_consumed",
            })

            print("[CAMP] " .. entity.name .. " ate living vermin")
            self:resolveAnimalFeedsForOwner(entity)
            return true, "living_food_consumed"
        end

        if devourPact and not devourForbiddenFood then
            return self:markAdventurerUnfed(entity, {
                result = entity.devourLivingForageFailed and "devour_living_starving" or "devour_living_no_food",
            })
        end

        local requestedRations = opts.rationCount or opts.rations or (canUseHaleAndHearty and 2 or 1)
        requestedRations = math.max(1, tonumber(requestedRations) or 1)
        if gluttonyPact and not explicitRationCount then
            requestedRations = math.max(requestedRations, 2)
        end

        local consumedItems = {}
        local nourishingItems = {}
        local ashedItems = {}
        local attempts = 0
        while #nourishingItems < requestedRations do
            local rationItem = findRationItem(entity)
            if not rationItem then
                break
            end

            if removeConsumableItem(entity, rationItem) then
                attempts = attempts + 1
                consumedItems[#consumedItems + 1] = rationItem
                if foodTurnsToAsh(entity, opts, attempts, rationItem) then
                    ashedItems[#ashedItems + 1] = rationItem
                else
                    nourishingItems[#nourishingItems + 1] = rationItem
                end
            else
                break
            end
        end

        if #ashedItems > 0 then
            self.eventBus:emit(M.EVENTS.RATION_ASHED, {
                entity = entity,
                items = ashedItems,
                count = #ashedItems,
                result = "ration_ashed",
            })
        end

        if #nourishingItems > 0 then
            -- Reset starvation counter
            entity.starvationCount = 0

            -- Clear starving condition if they were starving
            if entity.conditions and entity.conditions.starving then
                entity.conditions.starving = false
            end

            local bondCharged = false
            if #nourishingItems >= 2 and canUseHaleAndHearty then
                bondCharged = chargeBond(entity, opts.chargeBondTargetId)
            end

            local pactBreak = nil
            local pactBroken = nil
            local pactBreaks = {}
            if gluttonyPact and #nourishingItems < 2 then
                pactBreak = breakGluttonyPact(self, entity, gluttonyPact)
                pactBroken = gluttonyPact
                pactBreaks[#pactBreaks + 1] = {
                    pact = gluttonyPact,
                    detail = pactBreak,
                }
            end
            if devourPact then
                local devourBreak = breakDevourLivingPact(self, entity, devourPact)
                if not pactBreak then
                    pactBreak = devourBreak
                    pactBroken = devourPact
                end
                pactBreaks[#pactBreaks + 1] = {
                    pact = devourPact,
                    detail = devourBreak,
                }
            end

            self.rationsConsumed[entity.id] = true

            self.eventBus:emit(M.EVENTS.RATION_CONSUMED, {
                entity = entity,
                item = nourishingItems[1],
                items = nourishingItems,
                count = #nourishingItems,
                wastedItems = ashedItems,
                wastedCount = #ashedItems,
                bondTargetId = bondCharged and opts.chargeBondTargetId or nil,
                requiredCount = gluttonyPact and 2 or nil,
                pactBroken = pactBroken,
                pactBreak = pactBreak,
                pactBreaks = #pactBreaks > 0 and pactBreaks or nil,
            })

            local firstProps = nourishingItems[1] and nourishingItems[1].properties or {}
            local foodName = firstProps.isCampMeal and "meal" or "ration"
            local rationLabel = #nourishingItems == 1 and ("a " .. foodName) or
                (#nourishingItems .. " " .. foodName .. "s")
            print("[CAMP] " .. entity.name .. " ate " .. rationLabel)
            self:resolveAnimalFeedsForOwner(entity)
            if pactBreak then
                return true, "ration_consumed_pact_broken"
            end
            return true, bondCharged and "ration_consumed_bond_charged" or "ration_consumed"
        elseif #consumedItems > 0 then
            return self:markAdventurerUnfed(entity, {
                result = "ration_ashed",
            })
        else
            return self:markAdventurerUnfed(entity)
        end
    end

    function controller:markAnimalCompanionUnfed(owner, companion, key)
        if not companion then
            return false, "No companion targeted"
        end

        companion.conditions = companion.conditions or {}
        companion.starvationCount = (companion.starvationCount or 0) + 1
        companion.conditions.weak = true
        companion.weak = true

        local severity = "weak"
        if companion.starvationCount >= 2 then
            companion.conditions.starving = true
            companion.starving = true
            severity = "starving"
        end

        local feedKey = companionFeedKey(owner, companion, key)
        self.animalFeedConsumed[feedKey] = true

        self.eventBus:emit(M.EVENTS.STARVATION_WARNING, {
            entity = companion,
            owner = owner,
            severity = severity,
            animalFeed = true,
        })

        print("[CAMP] " .. (companion.name or "Animal companion") .. " goes without feed (" .. severity .. ")")
        return false, "no_animal_feed"
    end

    function controller:feedAnimalCompanion(owner, companion, opts)
        if self.state ~= M.STATES.BREAK_BREAD then
            return false, "Not in break bread phase"
        end

        if not companion then
            return false, "No companion targeted"
        end

        opts = opts or {}
        local feedKey = companionFeedKey(owner, companion, opts.key)
        if self.animalFeedConsumed[feedKey] then
            return true, "animal_feed_already_resolved"
        end

        local feedItem = findAnimalFeedItem(owner, companion)
        if not feedItem then
            return self:markAnimalCompanionUnfed(owner, companion, opts.key)
        end

        if not removeConsumableItem(owner, feedItem) then
            return self:markAnimalCompanionUnfed(owner, companion, opts.key)
        end

        companion.conditions = companion.conditions or {}
        companion.starvationCount = 0
        companion.conditions.weak = false
        companion.conditions.starving = false
        companion.conditions.staggered = false
        companion.weak = false
        companion.starving = false

        self.animalFeedConsumed[feedKey] = true

        self.eventBus:emit(M.EVENTS.RATION_CONSUMED, {
            entity = companion,
            owner = owner,
            item = feedItem,
            animalFeed = true,
            count = 1,
        })

        print("[CAMP] " .. (companion.name or "Animal companion") .. " ate animal feed")
        return true, "animal_feed_consumed"
    end

    function controller:resolveAnimalFeedsForOwner(owner)
        for _, entry in ipairs(animalCompanionEntries(owner)) do
            local feedKey = companionFeedKey(owner, entry.companion, entry.key)
            if not self.animalFeedConsumed[feedKey] then
                self:feedAnimalCompanion(owner, entry.companion, { key = entry.key })
            end
        end
    end

    --- Skip eating for an adventurer (explicit choice to starve)
    function controller:skipRation(entity)
        if self.state ~= M.STATES.BREAK_BREAD then
            return false, "Not in break bread phase"
        end

        return self:markAdventurerUnfed(entity)
    end

    function controller:canAdvanceFromBreakBread()
        for _, pc in ipairs(self.guild) do
            if not self.rationsConsumed[pc.id] then
                return false
            end

            for _, entry in ipairs(animalCompanionEntries(pc)) do
                local feedKey = companionFeedKey(pc, entry.companion, entry.key)
                if not self.animalFeedConsumed[feedKey] then
                    return false
                end
            end
        end
        return true
    end

    ----------------------------------------------------------------------------
    -- STEP 3: WATCH
    ----------------------------------------------------------------------------

    local function isRandomEncounterResult(result)
        if not result then
            return false
        end

        local category = result.category or result.type or result.eventType
        return category == "random_encounter" or
               category == "random encounter" or
               (result.raw and result.raw.category == "random_encounter")
    end

    local function choosePatrolMeatgrinderResult(draws)
        for _, result in ipairs(draws or {}) do
            if not isRandomEncounterResult(result) then
                return result, false
            end
        end

        return draws and draws[1] or nil, (draws and #draws or 0) > 0
    end

    local pathSuitByName = {
        swords = constants.SUITS.SWORDS,
        pentacles = constants.SUITS.PENTACLES,
        cups = constants.SUITS.CUPS,
        wands = constants.SUITS.WANDS,
    }

    local function entityPathSuit(entity)
        if not entity then
            return nil
        end

        if entity.pathSuit or entity.path_suit then
            return entity.pathSuit or entity.path_suit
        end

        local path = entity.path or entity.pathName or entity.suit
        if type(path) == "string" then
            path = path:lower():gsub("^path of ", "")
            return pathSuitByName[path]
        end

        return nil
    end

    function controller:selectWatchGuard(guardCard)
        if not guardCard then
            return nil
        end

        local candidates = {}
        for _, pc in ipairs(self.guild or {}) do
            if entityPathSuit(pc) == guardCard.suit then
                candidates[#candidates + 1] = pc
            end
        end

        if #candidates == 0 then
            for _, pc in ipairs(self.guild or {}) do
                candidates[#candidates + 1] = pc
            end
        end

        if #candidates == 0 then
            return nil
        end

        if #candidates == 1 then
            return candidates[1]
        end

        return candidates[(guardCard.value or 1) % 2 == 1 and 1 or #candidates]
    end

    function controller:getWatchGuardCard(options)
        options = options or {}
        if options.guardCard then
            return options.guardCard
        end

        local playerDeck = options.playerDeck or self.playerDeck
        if playerDeck and playerDeck.peekDiscard then
            return playerDeck:peekDiscard()
        end

        return nil
    end

    function controller:resolveWatchGuardTest(guard, options)
        options = options or {}
        if not guard then
            return nil
        end

        local supplied = options.guardTestResult
        if supplied ~= nil then
            if type(supplied) == "table" then
                return supplied
            end
            return {
                success = supplied == true,
                result = supplied == true and "success" or "failure",
                supplied = true,
            }
        end

        local card = options.guardTestCard
        local playerDeck = options.playerDeck or self.playerDeck
        if not card and playerDeck and playerDeck.draw then
            card = playerDeck:draw()
        end

        if not card then
            return nil
        end

        local cups = guard.getAttribute and guard:getAttribute(constants.SUITS.CUPS) or guard.cups or 0
        local testResult = fateResolver.resolveTest(cups, constants.SUITS.CUPS, card, options.guardTestFavor)

        if playerDeck and playerDeck.discard and not options.guardTestCard then
            playerDeck:discard(card)
        end

        return testResult
    end

    function controller:resolveCampEncounterGuard(watchResult, options)
        options = options or {}
        if not watchResult.challengeTriggered then
            return nil
        end

        local guardCard = self:getWatchGuardCard(options)
        local guard = options.guard or self:selectWatchGuard(guardCard)
        local testResult = self:resolveWatchGuardTest(guard, options)
        local alarmRaised = testResult and testResult.success == true or false
        local surprised = testResult and not testResult.success or false

        local guardResult = {
            guard = guard,
            guardCard = guardCard,
            testResult = testResult,
            alarmRaised = alarmRaised,
            surprised = surprised,
            requiresTest = guard ~= nil and testResult == nil,
            testSuit = "cups",
        }

        watchResult.guard = guard
        watchResult.guardCard = guardCard
        watchResult.guardTest = testResult
        watchResult.alarmRaised = alarmRaised
        watchResult.surprised = surprised
        watchResult.guardTestRequired = guardResult.requiresTest

        self.eventBus:emit("camp_watch_guard", guardResult)

        return guardResult
    end

    --- Resolve the watch (overnight encounter check)
    -- @param doubleDraw boolean: True if someone took Patrol action (auto-detected if nil)
    function controller:resolveWatch(doubleDraw, options)
        if type(doubleDraw) == "table" then
            options = doubleDraw
            doubleDraw = options.doubleDraw
        end
        options = options or {}

        if self.state ~= M.STATES.WATCH then
            return false, "Not in watch phase"
        end

        -- Auto-detect patrol if not specified
        if doubleDraw == nil then
            doubleDraw = self.patrolActive or false
        end

        local watchResult = {
            patrol = doubleDraw == true,
            draws = {},
            selected = nil,
            challengeTriggered = false,
        }

        -- Draw from meatgrinder
        if self.meatgrinder then
            local drawCount = doubleDraw and 2 or 1
            for _ = 1, drawCount do
                local result = self.meatgrinder:draw()
                if result then
                    print("[CAMP] Meatgrinder draw: " .. (result.description or "event"))
                    watchResult.draws[#watchResult.draws + 1] = result
                end
            end

            if doubleDraw then
                watchResult.selected, watchResult.challengeTriggered =
                    choosePatrolMeatgrinderResult(watchResult.draws)
            else
                watchResult.selected = watchResult.draws[1]
                watchResult.challengeTriggered = isRandomEncounterResult(watchResult.selected)
            end

            if watchResult.selected then
                self.eventBus:emit("meatgrinder_result", watchResult.selected)
            end
        end

        self:resolveCampEncounterGuard(watchResult, options)

        self.watchResolved = true
        self.lastWatchResult = watchResult
        print("[CAMP] Watch resolved" .. (doubleDraw and " (patrol active)" or ""))

        return true, watchResult
    end

    ----------------------------------------------------------------------------
    -- STEP 4: RECOVERY (S8.4)
    ----------------------------------------------------------------------------

    local function isStarvingEntity(entity)
        local conditions = entity and entity.conditions or {}
        return entity and (entity.starving or conditions.starving) == true
    end

    local function afflictionMaxStage(affliction)
        if affliction.maxStage then
            return affliction.maxStage
        end
        if affliction.stages and #affliction.stages > 0 then
            return #affliction.stages
        end
        return 4
    end

    local function afflictionCuredStages(affliction)
        affliction.curedStages = affliction.curedStages or {}
        return affliction.curedStages
    end

    local function afflictionStageCost(affliction, stage)
        local costs = affliction.stageCosts or affliction.chargeCosts or affliction.chargesRequired
        if type(costs) == "table" then
            return math.max(1, tonumber(costs[stage] or costs.default) or 1)
        end
        return math.max(1, tonumber(costs or affliction.chargesPerStage) or 1)
    end

    local function findAffliction(entity, afflictionName)
        if not entity or not entity.afflictions then
            return nil, nil
        end

        if afflictionName then
            return entity.afflictions[afflictionName], afflictionName
        end

        for name, affliction in pairs(entity.afflictions) do
            return affliction, name
        end

        return nil, nil
    end

    local function allAfflictionStagesCured(affliction)
        local curedStages = afflictionCuredStages(affliction)
        for stage = 1, afflictionMaxStage(affliction) do
            if not curedStages[stage] then
                return false
            end
        end
        return true
    end

    local function highestUncuredStage(affliction)
        local curedStages = afflictionCuredStages(affliction)
        for stage = afflictionMaxStage(affliction), 1, -1 do
            if not curedStages[stage] then
                return stage
            end
        end
        return nil
    end

    local function regressFromCuredCurrentStage(affliction)
        local curedStages = afflictionCuredStages(affliction)
        local stage = affliction.stage or 1
        while stage > 0 and curedStages[stage] do
            stage = stage - 1
        end
        affliction.stage = math.max(1, stage)
    end

    function controller:applyAfflictionCharges(entity, afflictionName, charges, source)
        local affliction, resolvedName = findAffliction(entity, afflictionName)
        if not affliction then
            return false, "No affliction to cure"
        end

        charges = math.max(1, tonumber(charges) or 1)
        affliction.cureCharges = (affliction.cureCharges or 0) + charges

        local curedStages = afflictionCuredStages(affliction)
        local curedNow = {}
        while true do
            local stage = highestUncuredStage(affliction)
            if not stage then
                break
            end

            local cost = afflictionStageCost(affliction, stage)
            if affliction.cureCharges < cost then
                break
            end

            affliction.cureCharges = affliction.cureCharges - cost
            curedStages[stage] = true
            curedNow[#curedNow + 1] = stage
            affliction.curedThisCamp = true

            if (affliction.stage or 1) == stage then
                regressFromCuredCurrentStage(affliction)
            end
        end

        local fullyCured = allAfflictionStagesCured(affliction)
        if fullyCured then
            entity.afflictions[resolvedName] = nil
        end

        self.eventBus:emit("affliction_charges_spent", {
            entity = entity,
            affliction = resolvedName,
            charges = charges,
            source = source,
            curedStages = curedNow,
            cureChargesRemaining = affliction.cureCharges or 0,
            fullyCured = fullyCured,
        })

        return true, {
            result = fullyCured and "affliction_cured" or "affliction_charged",
            affliction = resolvedName,
            curedStages = curedNow,
            fullyCured = fullyCured,
            cureChargesRemaining = affliction.cureCharges or 0,
        }
    end

    function controller:advanceAffliction(entity, afflictionName, affliction)
        local curedStages = afflictionCuredStages(affliction)
        local currentStage = affliction.stage or 1

        if allAfflictionStagesCured(affliction) then
            entity.afflictions[afflictionName] = nil
            return "affliction_cured"
        end

        if curedStages[currentStage] then
            regressFromCuredCurrentStage(affliction)
            return "affliction_regressed"
        end

        local nextStage = math.min(currentStage + 1, afflictionMaxStage(affliction))
        if curedStages[nextStage] then
            return "affliction_held"
        end

        affliction.stage = nextStage
        print("[CAMP] " .. entity.name .. "'s " .. afflictionName ..
              " advanced to stage " .. affliction.stage)

        if affliction.stage >= afflictionMaxStage(affliction) and affliction.onClimax then
            affliction.onClimax(entity)
        end

        return "affliction_advanced"
    end

    --- Begin recovery for an adventurer
    -- Refills lore bids at the start of recovery.
    function controller:beginRecovery(entity)
        if self.state ~= M.STATES.RECOVERY then
            return false, "Not in recovery phase"
        end

        if isStarvingEntity(entity) then
            return false, "Starving adventurers skip recovery"
        end

        -- Refill lore bids unless starvation skips Recovery.
        entity.loreBids = 4

        return true
    end

    function controller:finalizeRecoveryForEntity(entity)
        if isStarvingEntity(entity) then
            return false, "Starving adventurers skip recovery"
        end

        if entity.conditions and not entity.conditions.stressed and entity.conditions.staggered then
            entity.conditions.staggered = false
            breakPactsForRecoveryResult(self, entity, "staggered_healed")
            print("[CAMP] " .. entity.name .. " clears Staggered")
        end

        return true
    end

    function controller:finalizeRecovery()
        for _, pc in ipairs(self.guild) do
            self:finalizeRecoveryForEntity(pc)
        end
    end

    --- Spend a bond for recovery
    -- @param entity table: The adventurer
    -- @param bondTargetId string: ID of the bond partner
    -- @param spendType string: "heal_wound", "regain_resolve", "clear_stress", or "cure_affliction"
    function controller:spendBondForRecovery(entity, bondTargetId, spendType, opts)
        opts = opts or {}
        if type(opts) == "string" then
            opts = { affliction = opts }
        end

        if self.state ~= M.STATES.RECOVERY then
            return false, "Not in recovery phase"
        end

        if isStarvingEntity(entity) then
            return false, "Starving adventurers cannot recover"
        end

        -- Check if entity has the bond and it's charged
        if not entity.bonds or not entity.bonds[bondTargetId] then
            return false, "No bond with that entity"
        end

        if not entity.bonds[bondTargetId].charged then
            return false, "Bond is not charged"
        end

        -- STRESS GATE: If stressed, MUST clear stress first
        if entity.conditions and entity.conditions.stressed then
            if spendType ~= "clear_stress" then
                return false, "Must clear stress first"
            end
        end

        local extraBondTargetId = nil
        if spendType == "heal_wound" and recoveryNeedsExtraBond(entity) then
            local err = nil
            extraBondTargetId, err = selectExtraRecoveryBond(entity, bondTargetId, opts)
            if not extraBondTargetId then
                return false, err
            end
        end

        -- Spend the bond
        entity.bonds[bondTargetId].charged = false
        if extraBondTargetId then
            entity.bonds[extraBondTargetId].charged = false
        end

        -- Apply benefit
        local result = "unknown"
        local pactBreaks = {}
        if spendType == "clear_stress" then
            if entity.conditions then
                entity.conditions.stressed = false
            end
            result = "stress_cleared"
            pactBreaks = breakPactsForRecoveryResult(self, entity, result)
        elseif spendType == "heal_wound" then
            -- Use entity's healWound method (respects injury gate)
            if entity.healWound then
                local healResult, err = entity:healWound()
                if healResult then
                    result = healResult
                    pactBreaks = breakPactsForRecoveryResult(self, entity, result)
                else
                    -- Refund the bond if healing failed
                    entity.bonds[bondTargetId].charged = true
                    if extraBondTargetId then
                        entity.bonds[extraBondTargetId].charged = true
                    end
                    return false, err or "cannot_heal"
                end
            end
        elseif spendType == "regain_resolve" then
            if entity.regainResolve then
                entity:regainResolve(1)
                result = "resolve_regained"
            end
        elseif spendType == "cure_affliction" or spendType == "affliction" then
            local ok, cureResult = self:applyAfflictionCharges(
                entity,
                opts.affliction or opts.afflictionName or opts.targetAffliction,
                opts.charges or 1,
                "bond"
            )
            if ok then
                result = cureResult.result
            else
                entity.bonds[bondTargetId].charged = true
                return false, cureResult
            end
        end

        self.eventBus:emit(M.EVENTS.BOND_SPENT, {
            entity = entity,
            bondTargetId = bondTargetId,
            extraBondTargetId = extraBondTargetId,
            bondCost = extraBondTargetId and 2 or 1,
            spendType = spendType,
            result = result,
            affliction = opts.affliction or opts.afflictionName or opts.targetAffliction,
            maledictionExtraBondRecoveryCost = extraBondTargetId ~= nil,
            pactBreaks = pactBreaks,
        })

        print("[CAMP] " .. entity.name .. " spent bond with " .. bondTargetId .. " for: " .. result)

        return true, result
    end

    function controller:spendHealthfulItemForRecovery(entity, itemId, opts)
        opts = opts or {}

        if self.state ~= M.STATES.RECOVERY then
            return false, "Not in recovery phase"
        end

        if isStarvingEntity(entity) then
            return false, "Starving adventurers cannot recover"
        end

        if entity.conditions and entity.conditions.stressed then
            return false, "Must clear stress first"
        end

        local inv = entity and entity.inventory
        if not inv or not inv.findItem or not inv.removeItemQuantity then
            return false, "No inventory for healthful item"
        end

        local item = nil
        if itemId then
            item = inv:findItem(itemId)
        elseif inv.findItemByPredicate then
            item = inv:findItemByPredicate(function(candidate)
                return candidate.properties and candidate.properties.afflictionCureCharges
            end)
        end

        if not item then
            return false, "Healthful item not found"
        end

        local props = item.properties or {}
        if not props.afflictionCureCharges then
            return false, "Item is not healthful for afflictions"
        end

        local charges = math.max(1, tonumber(opts.charges or props.afflictionCureCharges) or 1)
        local ok, cureResult = self:applyAfflictionCharges(
            entity,
            opts.affliction or opts.afflictionName or opts.targetAffliction,
            charges,
            opts.source or item.templateId or item.id or "healthful_item"
        )
        if not ok then
            return false, cureResult
        end

        inv:removeItemQuantity(item.id, 1)

        local result = cureResult.result
        local detail = {
            entity = entity,
            item = item,
            itemId = item.id,
            itemName = item.name,
            affliction = cureResult.affliction,
            charges = charges,
            curedStages = cureResult.curedStages,
            fullyCured = cureResult.fullyCured,
            result = result,
        }
        self.eventBus:emit("healthful_item_spent", detail)

        return true, result, detail
    end

    --- Mark recovery complete for an entity
    function controller:completeRecovery(entity)
        self:finalizeRecoveryForEntity(entity)
        self.recoveryCompleted[entity.id] = true
    end

    ----------------------------------------------------------------------------
    -- STEP 5: TEARDOWN / END CAMP (S9.4)
    ----------------------------------------------------------------------------

    function controller:endCamp(opts)
        opts = opts or {}
        -- Process end-of-camp effects for all guild members
        for _, pc in ipairs(self.guild) do
            self:processEndOfCampEffects(pc, opts)
        end

        self.state = M.STATES.INACTIVE

        -- Emit camp end event
        self.eventBus:emit(M.EVENTS.CAMP_END, {
            guild = self.guild,
        })

        -- S9.4: Emit phase change to transition back to crawl
        self.eventBus:emit("phase_changed", {
            oldPhase = "camp",
            newPhase = "crawl",
        })

        print("[CAMP] Camp phase ended - returning to crawl")
    end

    function controller:hasAdequateCampComfort(entity)
        if self.hasShelter then
            return true
        end

        local comfort = 0
        if self.hasBedrolls then comfort = comfort + 1 end
        if self.hasTent then comfort = comfort + 1 end
        local fireCounts = self.hasFire
        if fireCounts and self.fireViolatesForegoWood and
           campActions.findUnbrokenActivePact(entity, "forego_wood") then
            fireCounts = false
        end
        if fireCounts then comfort = comfort + 1 end

        return comfort >= 2
    end

    function controller:clearCampCompleteConditions(entity)
        local cleared = {}
        local durations = entity and entity.conditionDurations
        if not durations then
            return cleared
        end

        entity.conditions = entity.conditions or {}
        for condition, duration in pairs(durations) do
            if duration and duration["until"] == "next_camp_complete" then
                entity.conditions[condition] = false
                if entity[condition] == true then
                    entity[condition] = false
                end
                durations[condition] = nil
                cleared[#cleared + 1] = condition
            end
        end

        if next(durations) == nil then
            entity.conditionDurations = nil
        end

        return cleared
    end

    --- Process end-of-camp effects for a single entity (S9.4)
    function controller:processEndOfCampEffects(entity, opts)
        opts = opts or {}
        if not entity.conditions then
            entity.conditions = {}
        end

        -- 1. Advance afflictions (if entity has any)
        if entity.afflictions then
            for afflictionName, affliction in pairs(entity.afflictions) do
                -- Only advance if not cured this camp
                if not affliction.curedThisCamp then
                    self:advanceAffliction(entity, afflictionName, affliction)
                else
                    -- Reset cured flag for next camp
                    affliction.curedThisCamp = false
                end
            end
        end

        -- 2. Check camp comfort: shelter, or at least two of bedroll/tent/fire.
        if isStarvingEntity(entity) then
            print("[CAMP] " .. entity.name .. " skips end-of-camp comfort checks (starving)")
        elseif not self:hasAdequateCampComfort(entity) then
            entity.conditions.stressed = true
            print("[CAMP] " .. entity.name .. " wakes Stressed (poor camp comfort)")
        end

        if not isStarvingEntity(entity) and badDreamsWakeStressed(entity, opts) then
            entity.conditions.stressed = true
            self.eventBus:emit(M.EVENTS.NIGHTMARE, {
                entity = entity,
                curseId = entity.maledictionCurseId or "bad_dreams",
                result = "stressed",
            })
            print("[CAMP] " .. entity.name .. " wakes Stressed (bad dreams)")
        end

        local theft = verminStealFromPack(entity, opts)
        if theft then
            self.eventBus:emit(M.EVENTS.VERMIN_THEFT, theft)
            print("[CAMP] " .. entity.name .. " loses " .. (theft.stolenItem.name or "an item") ..
                " to enamored vermin")
        end

        for _, condition in ipairs(self:clearCampCompleteConditions(entity)) do
            self.eventBus:emit(M.EVENTS.CONDITION_EXPIRED, {
                entity = entity,
                condition = condition,
                timing = "next_camp_complete",
            })
        end

        -- 3. Animal companions also need to be checked
        if entity.animalCompanions then
            for _, companion in ipairs(entity.animalCompanions) do
                self:processEndOfCampEffects(companion, opts)
            end
        end
    end

    ----------------------------------------------------------------------------
    -- UTILITY
    ----------------------------------------------------------------------------

    --- Get list of adventurers who haven't completed current step
    function controller:getPendingAdventurers()
        local pending = {}

        for _, pc in ipairs(self.guild) do
            local isPending = false

            if self.state == M.STATES.ACTIONS then
                isPending = not self.actionsCompleted[pc.id]
            elseif self.state == M.STATES.BREAK_BREAD then
                isPending = not self.rationsConsumed[pc.id]
            elseif self.state == M.STATES.RECOVERY then
                isPending = not self.recoveryCompleted[pc.id]
            end

            if isPending then
                pending[#pending + 1] = pc
            end
        end

        return pending
    end

    return controller
end

return M
