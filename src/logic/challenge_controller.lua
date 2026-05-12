-- challenge_controller.lua
-- Challenge Phase Controller for Majesty
-- Tickets S4.1, S4.6, S4.7: Turn-based state machine with initiative and count-up
--
-- Flow:
-- 1. PRE_ROUND: All entities submit initiative cards (facedown)
-- 2. COUNT_UP: Count from 1-14 (Ace to King), entities act when their card is called
-- 3. Each action: AWAITING_ACTION -> RESOLVING -> VISUAL_SYNC -> MINOR_WINDOW
-- 4. After count reaches 14, new round starts at PRE_ROUND
--
-- The controller PAUSES after each action until UI_SEQUENCE_COMPLETE fires.

local events = require('logic.events')
local vigilance_triggers = require('data.vigilance_triggers')
local constants = require('constants')
local fate_resolver = require('logic.resolver')
local action_registry = require('data.action_registry')
local inventory = require('logic.inventory')

local M = {}

--------------------------------------------------------------------------------
-- CHALLENGE STATES
--------------------------------------------------------------------------------
M.STATES = {
    IDLE            = "idle",             -- No challenge active
    STARTING        = "starting",         -- Challenge is initializing
    PRE_ROUND       = "pre_round",        -- Initiative submission phase (S4.6)
    COUNT_UP        = "count_up",         -- Counting 1-14 for turn order (S4.7)
    AWAITING_ACTION = "awaiting_action",  -- Waiting for active entity to act
    RESOLVING       = "resolving",        -- Processing action result
    VISUAL_SYNC     = "visual_sync",      -- Waiting for UI to complete animation
    MINOR_WINDOW    = "minor_window",     -- Minor action declaration window (paused until resume)
    ENDING          = "ending",           -- Challenge wrapping up
}

--------------------------------------------------------------------------------
-- CHALLENGE OUTCOMES
--------------------------------------------------------------------------------
M.OUTCOMES = {
    VICTORY     = "victory",     -- All enemies defeated
    DEFEAT      = "defeat",      -- All PCs defeated
    FLED        = "fled",        -- Party successfully fled
    TIME_OUT    = "time_out",    -- 14 turns elapsed
    NEGOTIATED  = "negotiated",  -- Combat ended via Banter
}

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------
local MAX_TURNS = 14

local function normalizeTalentKey(value)
    return tostring(value or ""):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
end

local function getEntityTalentEntry(entity, talentId)
    local talents = entity and entity.talents
    if type(talents) ~= "table" then
        return nil
    end

    local requested = normalizeTalentKey(talentId)
    for key, value in pairs(talents) do
        if normalizeTalentKey(key) == requested then
            return value
        end
        if type(value) == "table" and normalizeTalentKey(value.id or value.name or value.talentId) == requested then
            return value
        end
    end

    return nil
end

local function entityHasUsableTalent(entity, talentId)
    local entry = getEntityTalentEntry(entity, talentId)
    if not entry or entry == false then
        return false
    end
    if type(entry) == "table" then
        return entry.wounded ~= true
    end
    return entry == true
end

local function armorTypeAllowsQuick(armorType)
    local normalized = normalizeTalentKey(armorType)
    return normalized == "" or normalized == "none" or normalized == "light"
end

local function entityWearsLightOrNoArmor(entity)
    if not entity then
        return false
    end

    if not armorTypeAllowsQuick(entity.armorType or entity.wornArmorType) then
        return false
    end

    local actorArmor = entity.armor
    if type(actorArmor) == "table" then
        local props = actorArmor.properties or {}
        if (actorArmor.isArmor or props.armor) and not actorArmor.destroyed then
            if not armorTypeAllowsQuick(actorArmor.armorType or props.armorType) then
                return false
            end
        end
    end

    local inv = entity.inventory
    local belt = inv and inv.getItems and inv:getItems(inventory.LOCATIONS.BELT) or inv and inv.belt or {}
    for _, item in ipairs(belt or {}) do
        local props = item.properties or {}
        if (item.isArmor or props.armor) and not item.destroyed then
            if not armorTypeAllowsQuick(item.armorType or props.armorType) then
                return false
            end
        end
    end

    return true
end

local function spendEntityResolve(entity, amount)
    amount = amount or 1
    if not entity then
        return false, "missing_actor"
    end
    if entity.spendResolve then
        local ok, reason = entity:spendResolve(amount)
        if ok then
            return true, nil
        end
        return false, reason or "not_enough_resolve"
    end
    if type(entity.resolve) == "table" then
        if (entity.resolve.current or 0) < amount then
            return false, "not_enough_resolve"
        end
        entity.resolve.current = entity.resolve.current - amount
        return true, nil
    end
    if type(entity.resolve) == "number" then
        if entity.resolve < amount then
            return false, "not_enough_resolve"
        end
        entity.resolve = entity.resolve - amount
        return true, nil
    end
    return false, "resolve_unavailable"
end

--------------------------------------------------------------------------------
-- CHALLENGE CONTROLLER FACTORY
--------------------------------------------------------------------------------

--- Create a new ChallengeController
-- @param config table: { eventBus, playerDeck, gmDeck, guild, zoneSystem, gameClock }
-- @return ChallengeController instance
function M.createChallengeController(config)
    config = config or {}

    local controller = {
        eventBus   = config.eventBus or events.globalBus,
        playerDeck = config.playerDeck,
        playerHand = config.playerHand,
        gmDeck     = config.gmDeck,
        actionResolver = config.actionResolver,
        gameClock  = config.gameClock,
        guild      = config.guild or {},  -- PC entities
        zoneSystem = config.zoneSystem,   -- S12.1: Zone registry for engagement tracking

        -- Challenge state
        state           = M.STATES.IDLE,
        currentRound    = 0,          -- Which round of combat (can have multiple)
        activeEntity    = nil,        -- Current acting entity

        -- Combatants
        pcs             = {},         -- PC entities in this challenge
        npcs            = {},         -- NPC/Mob entities in this challenge
        allCombatants   = {},         -- Combined list

        -- Initiative tracking (S4.6)
        initiativeSlots = {},         -- entity.id -> { card, revealed }
        awaitingInitiative = {},      -- Entities that haven't submitted initiative yet

        -- Count-up tracking (S4.7)
        currentCount    = 0,          -- Current initiative count (1-14)
        actedThisRound  = {},         -- entity.id -> true if already acted

        -- Minor action tracking (S6.4: Declaration Loop)
        -- Intentional design: pending minors resolve in declaration order.
        minorActionTimer    = 0,
        minorActionUsed     = false,
        pendingMinors       = {},     -- Committed minor actions { actor, card, action, target }
        minorWindowActive   = false,  -- True while in minor window (paused)
        resolvingMinors     = false,  -- True while resolving pending minor actions
        pendingVigilanceReactions = {}, -- Triggered vigilance reactions awaiting resolution
        resolvingVigilance = false,     -- True while resolving vigilance reaction queue

        -- Visual sync
        awaitingVisualSync  = false,
        pendingAction       = nil,    -- Action waiting for visual completion

        -- Challenge context
        roomId          = nil,
        zoneId          = nil,
        zones           = nil,        -- Array of zone definitions { id, name, description }
        challengeType   = nil,        -- "combat", "trap", "hazard", "social"
        surprised       = false,      -- True when GM characters ambush the guild
        surpriseResults = {},         -- Pre-challenge automatic GM actions
        ambushResistance = nil,       -- Ambusher talent resistance result, if elected
        sceneAdvantages = {},         -- Ambush-created scene advantages/special rules
        chickenDoomResults = {},      -- Malediction King stress-test results

        -- Fool interrupt tracking (S4.9)
        pendingFoolRestore = nil,     -- { state, activeEntity } to restore after Fool
        pendingQuickRestore = nil,    -- { state, activeEntity } to restore after Quick!
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    --- Initialize and subscribe to events
    function controller:init()
        -- Listen for visual completion
        self.eventBus:on(events.EVENTS.UI_SEQUENCE_COMPLETE, function(data)
            self:onVisualComplete(data)
        end)

        -- Listen for minor actions
        self.eventBus:on(events.EVENTS.MINOR_ACTION_USED, function(data)
            self:onMinorActionUsed(data)
        end)
    end

    function controller:hasMaledictionFlag(entity, flag)
        if not entity or not flag then
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

    function controller:getEntityOption(options, entity)
        if type(options) ~= "table" or not entity then
            return options
        end
        return options[entity] or (entity.id and options[entity.id]) or (entity.name and options[entity.name])
    end

    function controller:getChickenDoomTestResult(entity, challengeConfig)
        challengeConfig = challengeConfig or {}
        local tests = challengeConfig.chickenDoomTests or challengeConfig.stressChickenTests
        local testSpec = self:getEntityOption(tests, entity)
        if type(testSpec) == "table" and testSpec.success ~= nil then
            return testSpec
        end

        local cardSpec = testSpec
        if type(testSpec) == "table" then
            cardSpec = testSpec.card or testSpec.testCard
        end
        if not cardSpec then
            local cards = challengeConfig.chickenDoomCards or challengeConfig.stressChickenCards
            cardSpec = self:getEntityOption(cards, entity)
        end
        if not cardSpec and challengeConfig.chickenDoomCard then
            cardSpec = challengeConfig.chickenDoomCard
        end
        if not cardSpec and challengeConfig.stressChickenCard then
            cardSpec = challengeConfig.stressChickenCard
        end

        local deck = challengeConfig.chickenDoomDeck or challengeConfig.stressChickenDeck or self.playerDeck
        if not cardSpec and deck and deck.draw then
            cardSpec = deck:draw()
        end

        if not cardSpec then
            return nil
        end

        local wands = tonumber(entity.wands or (entity.attributes and entity.attributes[constants.SUITS.WANDS])) or 0
        local favor = type(testSpec) == "table" and testSpec.favor or nil
        return fate_resolver.resolveTest(wands, constants.SUITS.WANDS, cardSpec, favor)
    end

    function controller:applyChickenDoomFailure(entity, testResult)
        entity.conditions = entity.conditions or {}
        entity.conditions.chicken = true
        entity.conditions.chickenDoom = true
        entity.chickenDoom = {
            active = true,
            startedRound = (self.currentRound or 0) + 1,
            expiresAfterRound = (self.currentRound or 0) + 1,
            testResult = testResult,
        }
        return entity.chickenDoom
    end

    function controller:resolveStressChickenDooms(challengeConfig)
        local results = {}
        for _, entity in ipairs(self.allCombatants or {}) do
            if not self:isDefeated(entity) and self:hasMaledictionFlag(entity, "stressChickenTest") then
                local testResult = self:getChickenDoomTestResult(entity, challengeConfig)
                local detail = {
                    entity = entity,
                    testResult = testResult,
                    success = testResult and testResult.success == true,
                    result = "resisted",
                }

                if testResult and not testResult.success then
                    detail.result = "chicken"
                    detail.chickenDoom = self:applyChickenDoomFailure(entity, testResult)
                elseif not testResult then
                    detail.result = "test_unavailable"
                end

                results[#results + 1] = detail
                self.eventBus:emit(events.EVENTS.MALEDICTION_CHICKEN_DOOM, detail)
            end
        end

        self.chickenDoomResults = results
        return results
    end

    function controller:clearExpiredChickenDoom(completedRound)
        local cleared = {}
        completedRound = completedRound or self.currentRound or 0

        for _, entity in ipairs(self.allCombatants or {}) do
            local doom = entity.chickenDoom
            if doom and doom.active ~= false and (doom.expiresAfterRound or 0) <= completedRound then
                entity.conditions = entity.conditions or {}
                entity.conditions.chicken = nil
                entity.conditions.chickenDoom = nil
                doom.active = false
                doom.clearedRound = completedRound
                entity.lastChickenDoom = doom
                entity.chickenDoom = nil

                local detail = {
                    entity = entity,
                    round = completedRound,
                    result = "chicken_cleared",
                }
                cleared[#cleared + 1] = detail
                self.eventBus:emit(events.EVENTS.MALEDICTION_CHICKEN_CLEARED, detail)
            end
        end

        return cleared
    end

    function controller:getKnownEntities()
        local entities = {}
        local seen = {}

        local function add(entity)
            if entity and not seen[entity] then
                seen[entity] = true
                entities[#entities + 1] = entity
            end
        end

        for _, collection in ipairs({ self.allCombatants, self.pcs, self.npcs, self.guild }) do
            for _, entity in ipairs(collection or {}) do
                add(entity)
            end
        end

        return entities
    end

    function controller:clearFoolReshuffleConditions(round)
        local expired = {}

        for _, entity in ipairs(self:getKnownEntities()) do
            local durations = entity.conditionDurations
            if durations then
                entity.conditions = entity.conditions or {}
                for condition, duration in pairs(durations) do
                    if duration and duration["until"] == "fool_reshuffle" then
                        entity.conditions[condition] = false
                        if entity[condition] == true then
                            entity[condition] = false
                        end
                        durations[condition] = nil

                        local detail = {
                            entity = entity,
                            condition = condition,
                            timing = "fool_reshuffle",
                            round = round or self.currentRound,
                        }
                        expired[#expired + 1] = detail
                        self.eventBus:emit(events.EVENTS.CONDITION_EXPIRED, detail)
                    end
                end

                if next(durations) == nil then
                    entity.conditionDurations = nil
                end
            end

            local blocks = entity.healingBlocks
            if blocks then
                for i = #blocks, 1, -1 do
                    local block = blocks[i]
                    if block and block["until"] == "fool_reshuffle" then
                        block.active = false
                        table.remove(blocks, i)
                        if entity.healingBlock == block then
                            entity.healingBlock = nil
                        end

                        local detail = {
                            entity = entity,
                            condition = "healing_block",
                            timing = "fool_reshuffle",
                            round = round or self.currentRound,
                            block = block,
                            woundTypes = block.woundTypes,
                        }
                        expired[#expired + 1] = detail
                        self.eventBus:emit(events.EVENTS.CONDITION_EXPIRED, detail)
                    end
                end

                if #blocks == 0 then
                    entity.healingBlocks = nil
                end
            elseif entity.healingBlock and entity.healingBlock["until"] == "fool_reshuffle" then
                local block = entity.healingBlock
                block.active = false
                entity.healingBlock = nil

                local detail = {
                    entity = entity,
                    condition = "healing_block",
                    timing = "fool_reshuffle",
                    round = round or self.currentRound,
                    block = block,
                    woundTypes = block.woundTypes,
                }
                expired[#expired + 1] = detail
                self.eventBus:emit(events.EVENTS.CONDITION_EXPIRED, detail)
            end
        end

        return expired
    end

    function controller:isChickenDoomed(entity)
        local conditions = entity and entity.conditions or {}
        return conditions.chicken == true or conditions.chickenDoom == true or
            (entity and entity.chickenDoom and entity.chickenDoom.active ~= false)
    end

    ----------------------------------------------------------------------------
    -- CHALLENGE LIFECYCLE
    ----------------------------------------------------------------------------

    --- Start a new challenge
    -- @param config table: { pcs, npcs, roomId, zoneId, challengeType }
    -- @return boolean, string: success, error
    function controller:startChallenge(challengeConfig)
        if self.state ~= M.STATES.IDLE then
            return false, "challenge_already_active"
        end

        challengeConfig = challengeConfig or {}

        -- Set up combatants
        self.pcs = challengeConfig.pcs or self.guild
        self.npcs = challengeConfig.npcs or {}
        self.roomId = challengeConfig.roomId
        self.zoneId = challengeConfig.zoneId
        self.zones = challengeConfig.zones  -- Store zone data for arena view
        self.challengeType = challengeConfig.challengeType or "combat"

        -- Validate we have combatants
        if #self.pcs == 0 then
            return false, "no_pcs"
        end
        if #self.npcs == 0 and self.challengeType == "combat" then
            return false, "no_npcs"
        end

        -- Build combatant list
        self:buildCombatantList()

        -- Keep zone registry in sync so adjacency checks are authoritative.
        if self.zoneSystem then
            local zones = self.zones
            if not zones or #zones == 0 then
                zones = {}
                if self.zoneId then
                    zones[1] = { id = self.zoneId, name = self.zoneId }
                else
                    zones[1] = { id = "main", name = "Main" }
                end
                self.zones = zones
            end

            self.zoneSystem:setRoomZones(zones)
            self.zoneSystem:clearAllEngagements()

            local fallbackZoneId = (zones[1] and zones[1].id) or self.zoneId
            for _, entity in ipairs(self.allCombatants) do
                local zoneId = entity.zone or fallbackZoneId
                if zoneId then
                    local placed, err = self.zoneSystem:placeEntity(entity.id, zoneId)
                    if not placed and fallbackZoneId then
                        placed, err = self.zoneSystem:placeEntity(entity.id, fallbackZoneId)
                        if placed then
                            zoneId = fallbackZoneId
                        end
                    end
                    if placed then
                        entity.zone = zoneId
                    else
                        print("[Challenge] Warning: could not place " .. tostring(entity.id) .. " in zone (" .. tostring(err) .. ")")
                    end
                end
            end
        end

        -- Initialize state
        self.state = M.STATES.STARTING
        self.currentRound = 0
        self.surprised = challengeConfig.surprised == true
        self.surpriseResults = {}
        self.ambushResistance = nil
        self.sceneAdvantages = {}
        self.chickenDoomResults = self:resolveStressChickenDooms(challengeConfig)

        -- Emit start event
        self.eventBus:emit(events.EVENTS.CHALLENGE_START, {
            pcs = self.pcs,
            npcs = self.npcs,
            roomId = self.roomId,
            zones = self.zones,  -- Pass zones to arena view
            challengeType = self.challengeType,
            surprised = self.surprised,
            chickenDoomResults = self.chickenDoomResults,
        })

        if self.surprised then
            local resistance = self:resolveAmbusherResistance(challengeConfig)
            if resistance and resistance.success then
                self.surprised = false
            end
        end

        if self.surprised then
            self:resolveSurpriseActions(challengeConfig)
        end

        -- Begin first round (initiative submission)
        self:startNewRound()

        return true
    end

    --- End the current challenge
    -- @param outcome string: One of OUTCOMES
    -- @param data table: Additional outcome data
    function controller:endChallenge(outcome, data)
        data = data or {}
        data.outcome = outcome
        data.finalTurn = self.currentTurn
        data.pcs = self.pcs
        data.npcs = self.npcs

        self.state = M.STATES.ENDING

        -- Emit end event
        self.eventBus:emit(events.EVENTS.CHALLENGE_END, data)

        -- Reset state
        self:reset()
    end

    --- Reset controller to idle state
    function controller:reset()
        self.state = M.STATES.IDLE
        self.currentRound = 0
        self.activeEntity = nil

        -- S12.1: Clear all engagements when challenge ends
        if self.zoneSystem then
            self.zoneSystem:clearAllEngagements()
        end

        -- Clear is_engaged flag on all combatants
        for _, entity in ipairs(self.allCombatants) do
            entity.is_engaged = false
            entity.pendingVigilance = nil
        end

        self.pcs = {}
        self.npcs = {}
        self.allCombatants = {}

        -- Initiative tracking
        self.initiativeSlots = {}
        self.awaitingInitiative = {}

        -- Count-up tracking
        self.currentCount = 0
        self.actedThisRound = {}

        -- Minor action
        self.minorActionTimer = 0
        self.minorActionUsed = false
        self.pendingMinors = {}
        self.minorWindowActive = false
        self.resolvingMinors = false
        self.pendingVigilanceReactions = {}
        self.resolvingVigilance = false

        -- Visual sync
        self.awaitingVisualSync = false
        self.pendingAction = nil
        self.surprised = false
        self.surpriseResults = {}
        self.ambushResistance = nil
        self.sceneAdvantages = {}
    end

    ----------------------------------------------------------------------------
    -- COMBATANT MANAGEMENT
    ----------------------------------------------------------------------------

    --- Build the list of all combatants (not ordered - initiative determines order)
    function controller:buildCombatantList()
        self.allCombatants = {}

        -- Add all living PCs
        for _, pc in ipairs(self.pcs) do
            if not self:isDefeated(pc) then
                self.allCombatants[#self.allCombatants + 1] = pc
            end
        end

        -- Add all living NPCs
        for _, npc in ipairs(self.npcs) do
            if not self:isDefeated(npc) then
                self.allCombatants[#self.allCombatants + 1] = npc
            end
        end
    end

    ----------------------------------------------------------------------------
    -- AMBUSH / SURPRISE SETUP (Chapter 7, p. 110)
    ----------------------------------------------------------------------------

    local function normalizeAmbushTactic(value)
        if type(value) ~= "string" then
            return "shank"
        end

        value = value:lower():gsub("^%s+", ""):gsub("%s+$", "")
        value = value:gsub("%s+", "_")

        if value == "advantage" or value == "create_advantage" or value == "tactic_1" then
            return "create_advantage"
        end
        if value == "deprive" or value == "deprive_resources" or value == "resource" or value == "tactic_2" then
            return "deprive_resources"
        end
        if value == "shank" or value == "wound" or value == "attack" or value == "tactic_3" then
            return "shank"
        end

        return value
    end

    local function surpriseActionForNPC(actions, npc, index)
        if type(actions) ~= "table" then
            return {}
        end

        return actions[npc and npc.id] or actions[index] or actions.default or {}
    end

    function controller:wantsAmbusherResistance(options)
        return options and (
            options.resistAmbushWithAmbusher == true or
            options.ambusherResist == true or
            options.ambusherResistActor ~= nil or
            options.ambusherResistActorId ~= nil
        )
    end

    function controller:findAmbusherResistanceActor(options)
        options = options or {}
        local requestedActor = options.ambusherResistActor
        local requestedId = options.ambusherResistActorId or options.ambusherActorId

        if requestedActor then
            if entityHasUsableTalent(requestedActor, "ambusher") then
                return requestedActor, nil
            end
            return nil, "requires_ambusher"
        end

        for _, pc in ipairs(self.pcs or {}) do
            if requestedId and pc.id ~= requestedId then
                -- Keep looking for the requested actor.
            elseif entityHasUsableTalent(pc, "ambusher") then
                return pc, nil
            elseif requestedId and pc.id == requestedId then
                return nil, "requires_ambusher"
            end
        end

        return nil, requestedId and "ambusher_not_found" or "requires_ambusher"
    end

    function controller:resolveAmbusherResistance(options)
        if not self:wantsAmbusherResistance(options) then
            return nil
        end

        local actor, reason = self:findAmbusherResistanceActor(options)
        local result = {
            success = false,
            actor = actor,
            reason = reason,
            effects = { "ambusher_ambush_resistance" },
        }

        if not actor then
            result.effects[#result.effects + 1] = "ambusher_resistance_blocked"
            self.ambushResistance = result
            self.eventBus:emit("ambush_resistance_failed", result)
            return result
        end

        local ok, spendReason = spendEntityResolve(actor, 1)
        if not ok then
            result.reason = spendReason
            result.effects[#result.effects + 1] = "resolve_missing"
            result.effects[#result.effects + 1] = "ambusher_resistance_blocked"
            self.ambushResistance = result
            self.eventBus:emit("ambush_resistance_failed", result)
            return result
        end

        result.success = true
        result.reason = nil
        result.description = "Ambusher raises a hue and cry before the ambush lands."
        result.effects[#result.effects + 1] = "resolve_spent_for_ambusher"
        result.effects[#result.effects + 1] = "ambush_resisted"
        self.ambushResistance = result
        self.eventBus:emit("ambush_resisted", result)
        return result
    end

    function controller:selectSurpriseTarget(actionSpec, shankedTargets)
        if actionSpec and actionSpec.target then
            return actionSpec.target
        end

        local targetId = actionSpec and (actionSpec.targetId or actionSpec.pcId)
        for _, pc in ipairs(self.pcs or {}) do
            if not self:isDefeated(pc) and (not targetId or pc.id == targetId) and
                not (shankedTargets and shankedTargets[pc.id]) then
                return pc
            end
        end

        return nil
    end

    function controller:resolveSurpriseAction(npc, actionSpec, shankedTargets)
        actionSpec = actionSpec or {}
        local tactic = normalizeAmbushTactic(actionSpec.tactic or actionSpec.type or actionSpec.action)
        local result = {
            actor = npc,
            tactic = tactic,
            success = true,
            automatic = true,
            effects = {},
            description = actionSpec.description,
        }

        if tactic == "create_advantage" then
            local advantage = {
                actor = npc,
                description = actionSpec.description or actionSpec.advantage or "Ambushers create an advantage.",
                effect = actionSpec.effect,
                zone = actionSpec.zone or (npc and npc.zone),
            }
            self.sceneAdvantages[#self.sceneAdvantages + 1] = advantage
            result.advantage = advantage
            result.effects[#result.effects + 1] = "ambush_advantage"
            result.description = advantage.description
            return result
        end

        local target = self:selectSurpriseTarget(actionSpec, tactic == "shank" and shankedTargets or nil)
        result.target = target

        if not target then
            result.success = false
            result.effects[#result.effects + 1] = "ambush_no_target"
            result.description = "No valid ambush target."
            return result
        end

        target.conditions = target.conditions or {}

        if tactic == "deprive_resources" then
            local resource = actionSpec.resource or actionSpec.deprive or "advantage"
            local condition = actionSpec.condition
            if not condition then
                if resource == "disarm" or resource == "weapon" then
                    condition = "disarmed"
                elseif resource == "extinguish_light" or resource == "light" or resource == "torch" then
                    condition = "light_extinguished"
                elseif resource == "web" or resource == "root" then
                    condition = "rooted"
                end
            end

            if condition then
                target.conditions[condition] = true
                result.condition = condition
            end
            result.resource = resource
            result.effects[#result.effects + 1] = "ambush_deprive_resources"
            result.description = actionSpec.description or "Ambushers deprive the guild of a resource."
            return result
        end

        -- Tactic 3: each attacker deals 1 Wound, but each adventurer can only
        -- be attacked once before the Challenge begins.
        local woundResult = target.takeWound and target:takeWound(actionSpec.damageType or "normal", actionSpec.woundOptions)
        if shankedTargets and target.id then
            shankedTargets[target.id] = true
        end
        result.woundResult = woundResult
        result.effects[#result.effects + 1] = "ambush_shank"
        result.effects[#result.effects + 1] = "surprise_wound"
        result.description = actionSpec.description or "Ambusher sucker-punches the guild."
        return result
    end

    function controller:resolveSurpriseActions(options)
        options = options or {}
        local results = {}
        local shankedTargets = {}
        local actions = options.surpriseActions or options.ambushActions

        for index, npc in ipairs(options.npcs or self.npcs or {}) do
            if not self:isDefeated(npc) then
                local actionSpec = surpriseActionForNPC(actions, npc, index)
                results[#results + 1] = self:resolveSurpriseAction(npc, actionSpec, shankedTargets)
            end
        end

        self.surpriseResults = results
        self.eventBus:emit("challenge_surprise_resolved", {
            pcs = self.pcs,
            npcs = self.npcs,
            results = results,
            sceneAdvantages = self.sceneAdvantages,
        })

        return results
    end

    ----------------------------------------------------------------------------
    -- ROUND MANAGEMENT (S4.6)
    ----------------------------------------------------------------------------

    --- Start a new round of combat
    function controller:startNewRound()
        self.currentRound = self.currentRound + 1

        -- Check end conditions before starting new round
        local outcome = self:checkEndConditions()
        if outcome then
            self:endChallenge(outcome)
            return
        end

        -- Rebuild combatant list (in case someone died)
        self:buildCombatantList()

        if self.actionResolver and self.actionResolver.applyStinkingCloudRoundStart then
            local roundEffects = self.actionResolver:applyStinkingCloudRoundStart({
                round = self.currentRound,
                combatants = self.allCombatants,
            })
            if roundEffects and #roundEffects > 0 then
                self:buildCombatantList()
                outcome = self:checkEndConditions()
                if outcome then
                    self:endChallenge(outcome)
                    return
                end
            end
        end

        -- Reset round tracking
        self.initiativeSlots = {}
        self.awaitingInitiative = {}
        self.actedThisRound = {}
        self.currentCount = 0

        -- Mark all living combatants as needing initiative
        for _, entity in ipairs(self.allCombatants) do
            self.awaitingInitiative[entity.id] = true
        end

        -- Enter pre-round state
        self.state = M.STATES.PRE_ROUND

        -- Emit event for UI
        self.eventBus:emit("initiative_phase_start", {
            round = self.currentRound,
            combatants = self.allCombatants,
        })

        -- Trigger NPC initiative selection
        for _, entity in ipairs(self.allCombatants) do
            if not entity.isPC then
                self:triggerNPCInitiative(entity)
            end
        end

        print("[Challenge] Round " .. self.currentRound .. " - Awaiting initiative from " .. #self.allCombatants .. " combatants")
    end

    --- Submit initiative card for an entity (S4.6)
    -- @param entity table: The entity submitting
    -- @param card table: The card being used for initiative
    -- @return boolean, string: success, error
    function controller:submitInitiative(entity, card)
        if self.state ~= M.STATES.PRE_ROUND then
            return false, "not_in_pre_round"
        end

        if not entity or not entity.id then
            return false, "invalid_entity"
        end

        if not self.awaitingInitiative[entity.id] then
            return false, "already_submitted"
        end

        if not card then
            return false, "no_card"
        end

        -- Store the initiative card (facedown)
        self.initiativeSlots[entity.id] = {
            card = card,
            revealed = false,
            value = card.value or 0,
        }

        -- Remove from awaiting list
        self.awaitingInitiative[entity.id] = nil

        print("[Initiative] " .. (entity.name or entity.id) .. " submitted: " .. (card.name or "?") .. " (value " .. (card.value or 0) .. ")")

        -- Emit event
        self.eventBus:emit("initiative_submitted", {
            entity = entity,
            -- Don't include card details - it's facedown!
        })

        -- Check if all initiatives are in
        if self:allInitiativesSubmitted() then
            self:beginCountUp()
        end

        return true
    end

    --- Check if all combatants have submitted initiative
    function controller:allInitiativesSubmitted()
        for id, _ in pairs(self.awaitingInitiative) do
            return false  -- At least one is still waiting
        end
        return true
    end

    ----------------------------------------------------------------------------
    -- COUNT-UP SYSTEM (S4.7)
    ----------------------------------------------------------------------------

    --- Begin the count-up phase after all initiatives submitted
    function controller:beginCountUp()
        self.state = M.STATES.COUNT_UP
        self.currentCount = 0

        print("[Challenge] All initiatives submitted. Beginning count-up!")

        self.eventBus:emit("count_up_start", {
            round = self.currentRound,
        })

        -- Start counting
        self:advanceCount()
    end

    --- Advance to the next count value
    function controller:advanceCount()
        -- Check end conditions
        local outcome = self:checkEndConditions()
        if outcome then
            self:endChallenge(outcome)
            return
        end

        self.currentCount = self.currentCount + 1

        -- Round complete when count exceeds 14 (King)
        if self.currentCount > MAX_TURNS then
            print("[Challenge] Round " .. self.currentRound .. " complete!")
            self.eventBus:emit(events.EVENTS.CHALLENGE_ROUND_END, {
                round = self.currentRound,
            })
            self:clearExpiredChickenDoom(self.currentRound)
            if self.gameClock and self.gameClock.endRound then
                local reshuffled = self.gameClock:endRound()
                if reshuffled then
                    self:clearFoolReshuffleConditions(self.currentRound)
                    print("[Challenge] The Fool reshuffled both decks at round end.")
                end
            end
            self:startNewRound()
            return
        end

        -- Emit count event for UI
        self.eventBus:emit("count_up_tick", {
            count = self.currentCount,
            round = self.currentRound,
        })

        -- Find entities whose initiative matches current count
        local actingEntities = self:getEntitiesAtCount(self.currentCount)

        if #actingEntities > 0 then
            -- Sort by PC first (tie-breaker: PCs act before NPCs, p.112)
            table.sort(actingEntities, function(a, b)
                -- PCs go first unless NPC has shield (simplified for now)
                if a.isPC and not b.isPC then return true end
                if b.isPC and not a.isPC then return false end
                return false  -- Same type, maintain order
            end)

            -- Start first entity's turn
            self:startEntityTurn(actingEntities[1])
        else
            -- No one acts at this count, continue immediately
            self:advanceCount()
        end
    end

    --- Get all entities whose initiative matches a count value
    function controller:getEntitiesAtCount(count)
        local result = {}
        for _, entity in ipairs(self.allCombatants) do
            if not self:isDefeated(entity) and not self.actedThisRound[entity.id] then
                local slot = self.initiativeSlots[entity.id]
                if slot and slot.value == count then
                    result[#result + 1] = entity
                end
            end
        end
        return result
    end

    --- Start a specific entity's turn
    function controller:startEntityTurn(entity)
        self.activeEntity = entity
        self.state = M.STATES.AWAITING_ACTION

        -- Reveal their initiative card
        local slot = self.initiativeSlots[entity.id]
        if slot then
            slot.revealed = true
        end

        -- Emit turn start
        self.eventBus:emit(events.EVENTS.CHALLENGE_TURN_START, {
            count = self.currentCount,
            round = self.currentRound,
            activeEntity = self.activeEntity,
            isPC = self.activeEntity.isPC,
            initiativeCard = slot and slot.card,
        })

        print("[Turn] Count " .. self.currentCount .. ": " .. (entity.name or entity.id) .. "'s turn")

        if self:isChickenDoomed(self.activeEntity) then
            self:skipTurn(self.activeEntity, "chicken_doom")
            return
        end

        -- If NPC, trigger AI decision
        if not self.activeEntity.isPC then
            self:triggerNPCAction()
        end
        -- If PC, wait for player input (handled externally)
    end

    --- Called after an entity completes their turn
    function controller:completeTurn()
        if self.activeEntity then
            self.actedThisRound[self.activeEntity.id] = true
        end

        self.activeEntity = nil

        -- Check for more entities at current count
        local moreAtCount = self:getEntitiesAtCount(self.currentCount)
        if #moreAtCount > 0 then
            self:startEntityTurn(moreAtCount[1])
        else
            -- Continue counting
            self:advanceCount()
        end
    end

    --- Check if challenge should end
    -- @return string|nil: Outcome or nil if challenge continues
    function controller:checkEndConditions()
        -- Count surviving PCs
        local survivingPCs = 0
        for _, pc in ipairs(self.pcs) do
            if not self:isDefeated(pc) then
                survivingPCs = survivingPCs + 1
            end
        end

        -- Count surviving NPCs
        local survivingNPCs = 0
        for _, npc in ipairs(self.npcs) do
            if not self:isDefeated(npc) then
                survivingNPCs = survivingNPCs + 1
            end
        end

        -- All NPCs defeated = victory
        if survivingNPCs == 0 and #self.npcs > 0 then
            return M.OUTCOMES.VICTORY
        end

        -- All PCs defeated = defeat
        if survivingPCs == 0 then
            return M.OUTCOMES.DEFEAT
        end

        return nil
    end

    --- Check if an entity is defeated
    function controller:isDefeated(entity)
        if not entity then return true end
        if entity.conditions and entity.conditions.dead then
            return true
        end
        if entity.conditions and entity.conditions.deaths_door then
            return true
        end
        if entity.conditions and (entity.conditions.knocked_out or entity.conditions.knockout) then
            return true
        end
        return false
    end

    ----------------------------------------------------------------------------
    -- ACTION HANDLING
    ----------------------------------------------------------------------------

    --- Check if two entities are hostile to each other
    function controller:areHostile(entityA, entityB)
        if not entityA or not entityB then
            return false
        end
        if entityA == entityB then
            return false
        end
        return entityA.isPC ~= entityB.isPC
    end

    --- Normalize trigger definition for pending vigilance
    function controller:normalizeVigilanceTrigger(trigger)
        if type(trigger) == "string" then
            local templated = vigilance_triggers.getTemplate(trigger)
            if templated then
                return templated
            end

            return {
                mode = "action_type",
                actionType = trigger,
                excludeSelf = true,
            }
        end

        if type(trigger) == "table" then
            local templated = vigilance_triggers.getTemplate(trigger.template or trigger.preset, trigger)
            if templated then
                return templated
            end

            return trigger
        end

        -- Default practical trigger: when a hostile action targets the vigilant actor.
        return vigilance_triggers.getDefaultTrigger()
    end

    --- Determine whether a pending vigilance triggers from a resolved action
    function controller:doesVigilanceTrigger(actor, pendingVigilance, triggeringAction)
        if not actor or not pendingVigilance or not triggeringAction then
            return false
        end

        local trigger = self:normalizeVigilanceTrigger(pendingVigilance.trigger)
        local actionType = triggeringAction.normalizedType or triggeringAction.type
        local triggerActor = triggeringAction.actor
        local triggerTarget = triggeringAction.target

        local function matchesActionType()
            if trigger.actionType and actionType ~= trigger.actionType then
                return false
            end
            if type(trigger.actionTypes) == "table" then
                local matched = false
                for _, allowed in ipairs(trigger.actionTypes) do
                    if actionType == allowed then
                        matched = true
                        break
                    end
                end
                if not matched then
                    return false
                end
            end
            return true
        end

        if trigger.mode == "targeted_by_hostile_action" then
            if not triggerActor or triggerActor == actor then
                return false
            end
            if trigger.hostileOnly ~= false and not self:areHostile(actor, triggerActor) then
                return false
            end
            if trigger.target == nil or trigger.target == "self" then
                if triggerTarget ~= actor then
                    return false
                end
            elseif trigger.target == "ally" then
                if not triggerTarget or triggerTarget == actor or self:areHostile(actor, triggerTarget) then
                    return false
                end
            elseif trigger.target == "enemy" then
                if not triggerTarget or not self:areHostile(actor, triggerTarget) then
                    return false
                end
            elseif trigger.target ~= "any" then
                if type(trigger.target) == "string" then
                    if not triggerTarget or triggerTarget.id ~= trigger.target then
                        return false
                    end
                elseif triggerTarget ~= trigger.target then
                    return false
                end
            end
            return matchesActionType()
        end

        if trigger.excludeSelf ~= false and triggerActor == actor then
            return false
        end
        if trigger.hostileOnly and (not triggerActor or not self:areHostile(actor, triggerActor)) then
            return false
        end
        if trigger.alliedOnly and (not triggerActor or self:areHostile(actor, triggerActor)) then
            return false
        end
        if trigger.actorId and (not triggerActor or triggerActor.id ~= trigger.actorId) then
            return false
        end
        if trigger.targetId and (not triggerTarget or triggerTarget.id ~= trigger.targetId) then
            return false
        end
        if trigger.target == "self" and triggerTarget ~= actor then
            return false
        end
        if trigger.target == "ally" and (not triggerTarget or triggerTarget == actor or self:areHostile(actor, triggerTarget)) then
            return false
        end
        if trigger.target == "enemy" and (not triggerTarget or not self:areHostile(actor, triggerTarget)) then
            return false
        end
        if trigger.actorZoneId and (not triggerActor or triggerActor.zone ~= trigger.actorZoneId) then
            return false
        end
        if trigger.targetZoneId and (not triggerTarget or triggerTarget.zone ~= trigger.targetZoneId) then
            return false
        end

        return matchesActionType()
    end

    --- Find a fallback target for vigilance follow-up actions
    function controller:findVigilanceFallbackTarget(actor, targetKind)
        local candidates = nil
        if targetKind == "enemy" then
            candidates = actor and actor.isPC and self.npcs or self.pcs
        elseif targetKind == "ally" then
            candidates = actor and actor.isPC and self.pcs or self.npcs
        else
            candidates = self.allCombatants
        end

        for _, candidate in ipairs(candidates or {}) do
            if candidate ~= actor and not self:isDefeated(candidate) then
                return candidate
            end
        end

        -- Self-target fallback for ally actions
        if targetKind == "ally" and actor and not self:isDefeated(actor) then
            return actor
        end

        return nil
    end

    --- Resolve target selection for a triggered vigilance follow-up
    function controller:resolveVigilanceTarget(actor, pendingVigilance, triggeringAction, followUpDef)
        local triggerActor = triggeringAction and triggeringAction.actor or nil
        local triggerTarget = triggeringAction and triggeringAction.target or nil

        local explicitTarget = pendingVigilance.followUpTarget or pendingVigilance.target
        if explicitTarget and not self:isDefeated(explicitTarget) then
            return explicitTarget
        end

        local policy = pendingVigilance.followUpTargetPolicy
        if policy == "trigger_actor" then
            if triggerActor and not self:isDefeated(triggerActor) then
                return triggerActor
            end
        elseif policy == "trigger_target" then
            if triggerTarget and not self:isDefeated(triggerTarget) then
                return triggerTarget
            end
        elseif policy == "self" then
            return actor
        end

        if not followUpDef then
            return nil
        end

        if followUpDef.targetType == "enemy" then
            if triggerActor and self:areHostile(actor, triggerActor) and not self:isDefeated(triggerActor) then
                return triggerActor
            end
            return self:findVigilanceFallbackTarget(actor, "enemy")
        end

        if followUpDef.targetType == "ally" then
            if triggerActor and not self:areHostile(actor, triggerActor) and not self:isDefeated(triggerActor) then
                return triggerActor
            end
            return self:findVigilanceFallbackTarget(actor, "ally")
        end

        if followUpDef.requiresTarget then
            if triggerActor and not self:isDefeated(triggerActor) then
                return triggerActor
            end
            return self:findVigilanceFallbackTarget(actor, "any")
        end

        return nil
    end

    --- Build a concrete triggered action from pending vigilance state
    function controller:buildVigilanceReactionAction(actor, pendingVigilance, triggeringAction)
        local actionRegistry = require('data.action_registry')
        local followUpActionType = pendingVigilance.followUpAction

        if type(followUpActionType) == "table" then
            followUpActionType = followUpActionType.id or followUpActionType.type
        end
        if not followUpActionType then
            return nil, "missing_follow_up_action"
        end

        local followUpDef = actionRegistry.getAction(followUpActionType)
        if not followUpDef then
            return nil, "unknown_follow_up_action"
        end

        local reaction = {
            actor = actor,
            card = pendingVigilance.card,
            type = followUpActionType,
            actionDef = followUpDef,
            target = self:resolveVigilanceTarget(actor, pendingVigilance, triggeringAction, followUpDef),
            destinationZone = pendingVigilance.followUpDestinationZone,
            weapon = pendingVigilance.weapon or (
                actor and actor.inventory and actor.inventory.getWieldedWeapon and actor.inventory:getWieldedWeapon()
            ) or { name = "Fists", isMelee = true },
            allEntities = self.allCombatants,
            challengeController = self,
            isVigilanceReaction = true,
            triggerAction = triggeringAction,
            round = self.currentRound,
            count = self.currentCount,
            vigilanceDeclaredOrder = pendingVigilance.declaredOrder or 0,
        }

        return reaction
    end

    --- Collect all vigilance reactions triggered by the just-resolved action
    function controller:collectTriggeredVigilanceReactions(triggeringAction)
        if not triggeringAction then
            return {}
        end

        local triggered = {}

        for _, entity in ipairs(self.allCombatants) do
            local pendingVigilance = entity.pendingVigilance
            if pendingVigilance and not self:isDefeated(entity) then
                if self:doesVigilanceTrigger(entity, pendingVigilance, triggeringAction) then
                    entity.pendingVigilance = nil  -- Consume vigilance once triggered

                    local reaction, reason = self:buildVigilanceReactionAction(entity, pendingVigilance, triggeringAction)
                    if reaction then
                        triggered[#triggered + 1] = reaction
                        self.eventBus:emit("vigilance_triggered", {
                            actor = entity,
                            triggerAction = triggeringAction,
                            followUpAction = reaction.type,
                        })
                    else
                        self.eventBus:emit("vigilance_trigger_failed", {
                            actor = entity,
                            triggerAction = triggeringAction,
                            reason = reason,
                        })
                        print("[VIGILANCE] " .. (entity.name or entity.id) .. " trigger failed: " .. tostring(reason))
                    end
                end
            end
        end

        table.sort(triggered, function(a, b)
            local orderA = a.vigilanceDeclaredOrder or math.huge
            local orderB = b.vigilanceDeclaredOrder or math.huge
            if orderA == orderB then
                local idA = (a.actor and a.actor.id) or ""
                local idB = (b.actor and b.actor.id) or ""
                return tostring(idA) < tostring(idB)
            end
            return orderA < orderB
        end)

        return triggered
    end

    --- Queue vigilance reactions for processing
    function controller:queueTriggeredVigilanceReactions(triggeringAction)
        local triggered = self:collectTriggeredVigilanceReactions(triggeringAction)
        for _, reaction in ipairs(triggered) do
            self.pendingVigilanceReactions[#self.pendingVigilanceReactions + 1] = reaction
        end
        return #triggered
    end

    --- Continue turn flow when no more vigilance reactions are queued
    function controller:continuePostActionFlow()
        if self.resolvingMinors then
            if #self.pendingMinors > 0 then
                self:processNextMinorAction()
            else
                self.resolvingMinors = false
                self:completeTurn()
            end
            return
        end

        -- Emit turn end once all reactions are complete
        self.eventBus:emit(events.EVENTS.CHALLENGE_TURN_END, {
            count = self.currentCount,
            round = self.currentRound,
            entity = self.activeEntity,
        })

        -- Enter minor action window
        self:startMinorActionWindow()
    end

    --- Process the next queued vigilance reaction
    function controller:processNextVigilanceReaction()
        if #self.pendingVigilanceReactions == 0 then
            self.resolvingVigilance = false
            self:continuePostActionFlow()
            return
        end

        local reaction = table.remove(self.pendingVigilanceReactions, 1)

        print("[VIGILANCE] " .. (reaction.actor.name or reaction.actor.id) ..
              " triggers " .. (reaction.type or "action"))

        self.state = M.STATES.RESOLVING
        self.pendingAction = reaction

        -- Resolve through the standard pipeline
        self.eventBus:emit(events.EVENTS.CHALLENGE_ACTION, reaction)
    end

    --- Submit an action for the active entity
    -- @param action table: { type, target, card, ... }
    -- @return boolean, string: success, error
    function controller:submitAction(action)
        if self.state ~= M.STATES.AWAITING_ACTION then
            return false, "not_awaiting_action"
        end

        if not self.activeEntity then
            return false, "no_active_entity"
        end

        action.actor = self.activeEntity
        action.round = self.currentRound
        action.count = self.currentCount
        action.challengeController = self

        -- Move to resolving state
        self.state = M.STATES.RESOLVING
        self.pendingAction = action

        -- Emit action event for resolution
        self.eventBus:emit(events.EVENTS.CHALLENGE_ACTION, action)

        return true
    end

    --- Skip the active entity's turn without opening a minor-action window.
    -- Rulebook p.114: if a turn is skipped or no card can be played, nobody
    -- takes minor actions and the count-up continues.
    function controller:skipTurn(entity, reason)
        if self.state ~= M.STATES.AWAITING_ACTION then
            return false, "not_awaiting_action"
        end

        if not self.activeEntity then
            return false, "no_active_entity"
        end

        if entity and entity ~= self.activeEntity then
            return false, "not_active_entity"
        end

        local skipped = self.activeEntity
        self.eventBus:emit(events.EVENTS.CHALLENGE_TURN_END, {
            count = self.currentCount,
            round = self.currentRound,
            entity = skipped,
            skipped = true,
            reason = reason or "skipped",
        })

        self:completeTurn()
        return true
    end

    --- Resolve an action (called by action resolver)
    function controller:resolveAction(action)
        -- Store the result
        local result = action.result or { success = false }

        -- Emit resolution event
        self.eventBus:emit(events.EVENTS.CHALLENGE_RESOLUTION, {
            action = action,
            result = result,
        })

        -- Enter visual sync - wait for UI to show the result
        self.state = M.STATES.VISUAL_SYNC
        self.awaitingVisualSync = true

        -- The ActionSequencer will emit UI_SEQUENCE_COMPLETE when done
    end

    --- Called when visual sequence completes
    function controller:onVisualComplete(data)
        if not self.awaitingVisualSync then
            return
        end

        local completedAction = self.pendingAction
        self.awaitingVisualSync = false
        self.pendingAction = nil

        -- S4.9: Check if this was a Fool interrupt
        if self.pendingFoolRestore then
            self:completeFoolInterrupt()
            return
        end

        if self.pendingQuickRestore then
            self:completeQuickInterrupt()
            return
        end

        -- Queue vigilance reactions triggered by the just-resolved action
        local triggeredCount = self:queueTriggeredVigilanceReactions(completedAction)
        if triggeredCount > 0 then
            self.resolvingVigilance = true
        end

        if self.resolvingVigilance then
            self:processNextVigilanceReaction()
            return
        end

        self:continuePostActionFlow()
    end

    ----------------------------------------------------------------------------
    -- MINOR ACTION WINDOW (S6.4: Declaration Loop)
    ----------------------------------------------------------------------------

    --- Start the minor action opportunity window
    -- The count-up PAUSES here until Resume is clicked
    function controller:startMinorActionWindow()
        self.state = M.STATES.MINOR_WINDOW
        self.pendingMinors = {}
        self.minorWindowActive = true

        -- Emit state change for UI
        self.eventBus:emit("challenge_state_changed", {
            newState = "minor_window",
            count = self.currentCount,
            round = self.currentRound,
        })

        self.eventBus:emit(events.EVENTS.MINOR_ACTION_WINDOW, {
            count = self.currentCount,
            round = self.currentRound,
            paused = true,  -- Indicate this is a paused window
        })

        print("[MINOR WINDOW] Paused for minor action declarations. Click Resume to continue.")
    end

    --- Declare a minor action (adds to pending list)
    -- @param entity table: The entity declaring the minor action
    -- @param card table: The card being used (must match action suit)
    -- @param action table: { type, target, ... }
    -- @return boolean, string: success, error
    function controller:declareMinorAction(entity, card, action)
        if self.state ~= M.STATES.MINOR_WINDOW then
            return false, "not_in_minor_window"
        end

        if not entity or not card or not action then
            return false, "invalid_minor_declaration"
        end

        if self.activeEntity and entity == self.activeEntity then
            return false, "acting_entity_cannot_minor"
        end

        -- Verify card suit matches action suit (S6.2/S6.4 requirement)
        local actionRegistry = require('data.action_registry')
        local cardSuit = actionRegistry.cardSuitToActionSuit(card.suit)
        local actionDef = actionRegistry.getAction(action.type)

        if actionDef then
            local talentMinor = actionRegistry.canUseMinorActionWithCard(actionDef, cardSuit, entity)
            if actionDef.suit ~= cardSuit and actionDef.suit ~= actionRegistry.SUITS.MISC and not talentMinor then
                return false, "suit_mismatch"
            end
            if actionDef.suit == actionRegistry.SUITS.MISC then
                return false, "misc_not_allowed"  -- Misc actions not allowed as minors
            end
        end

        -- Add to pending minors
        local declaration = {
            entity = entity,
            card = card,
            action = action,
            declaredAt = #self.pendingMinors + 1,  -- Order of declaration
        }

        self.pendingMinors[#self.pendingMinors + 1] = declaration

        print("[MINOR] " .. (entity.name or entity.id) .. " declares " ..
              (action.type or "action") .. " with " .. (card.name or "card"))

        self.eventBus:emit("minor_action_declared", {
            entity = entity,
            card = card,
            action = action,
            position = #self.pendingMinors,
        })

        return true
    end

    --- Remove a declared minor action
    function controller:undeclareMinorAction(index)
        if self.state ~= M.STATES.MINOR_WINDOW then
            return false, "not_in_minor_window"
        end

        if index < 1 or index > #self.pendingMinors then
            return false, "invalid_index"
        end

        local removed = table.remove(self.pendingMinors, index)

        self.eventBus:emit("minor_action_undeclared", {
            entity = removed.entity,
            position = index,
        })

        return true
    end

    --- Resume from minor window and resolve all pending minors
    -- Called when "Resume" button is clicked
    function controller:resumeFromMinorWindow()
        if self.state ~= M.STATES.MINOR_WINDOW then
            return false, "not_in_minor_window"
        end

        print("[MINOR WINDOW] Resuming with " .. #self.pendingMinors .. " pending actions")

        self.minorWindowActive = false

        -- Emit state change
        self.eventBus:emit("challenge_state_changed", {
            newState = "resolving_minors",
            pendingCount = #self.pendingMinors,
        })

        -- Process pending minors in declaration order
        if #self.pendingMinors > 0 then
            self:processNextMinorAction()
        else
            -- No minors declared, continue to next turn
            self:completeTurn()
        end

        return true
    end

    --- Process the next pending minor action
    function controller:processNextMinorAction()
        if #self.pendingMinors == 0 then
            -- All minors processed, continue turn
            self:completeTurn()
            return
        end

        -- Get next minor in order
        local minor = table.remove(self.pendingMinors, 1)

        print("[MINOR RESOLVE] Processing " .. (minor.entity.name or minor.entity.id) ..
              "'s " .. (minor.action.type or "action"))

        -- Build the full action
        local fullAction = minor.action
        fullAction.actor = minor.entity
        fullAction.card = minor.card
        fullAction.isMinorAction = true  -- Flag for resolver (uses face value only)
        fullAction.challengeController = self

        -- Emit action for resolution
        self.eventBus:emit(events.EVENTS.CHALLENGE_ACTION, fullAction)

        -- Wait for visual sync before processing next minor
        self.state = M.STATES.VISUAL_SYNC
        self.awaitingVisualSync = true
        self.pendingAction = fullAction

        -- The onVisualComplete will be called after animation
        -- We need to track that we're resolving minors
        self.resolvingMinors = true
    end

    --- Called when a minor action is used (legacy compatibility)
    function controller:onMinorActionUsed(data)
        if self.state ~= M.STATES.MINOR_WINDOW then
            return
        end

        -- Legacy: single minor action used
        self.minorActionUsed = true

        -- Continue to next entity/count
        self:completeTurn()
    end

    --- Update function (call from love.update)
    function controller:update(dt)
        -- S6.4: Minor window is now paused indefinitely, no timer
        -- The window only ends when Resume is clicked
    end

    ----------------------------------------------------------------------------
    -- NPC AI TRIGGERS
    ----------------------------------------------------------------------------

    --- Trigger AI to choose initiative card (S4.6)
    function controller:triggerNPCInitiative(npc)
        self.eventBus:emit("npc_choose_initiative", {
            npc = npc,
            round = self.currentRound,
        })
    end

    --- Trigger AI to decide NPC action
    function controller:triggerNPCAction()
        -- The AI system will listen for CHALLENGE_TURN_START where isPC = false
        -- and submit an action via submitAction()
        self.eventBus:emit("npc_turn", {
            npc = self.activeEntity,
            count = self.currentCount,
            round = self.currentRound,
            pcs = self.pcs,
        })
    end

    ----------------------------------------------------------------------------
    -- FLEE HANDLING
    ----------------------------------------------------------------------------

    --- Attempt to flee from the challenge
    -- @param entity table: The entity attempting to flee
    -- @return boolean: success
    function controller:attemptFlee(entity)
        -- Flee logic would involve a test
        -- For now, simplified: flee always succeeds if no engagement
        local success = true

        if success then
            -- Remove entity from combatants
            for i, e in ipairs(self.allCombatants) do
                if e == entity then
                    table.remove(self.allCombatants, i)
                    break
                end
            end

            -- Check if all PCs fled
            local remainingPCs = 0
            for _, e in ipairs(self.allCombatants) do
                if e.isPC then
                    remainingPCs = remainingPCs + 1
                end
            end

            if remainingPCs == 0 then
                self:endChallenge(M.OUTCOMES.FLED)
            end
        end

        return success
    end

    ----------------------------------------------------------------------------
    -- THE FOOL INTERRUPT (S4.9)
    -- The Fool allows immediate out-of-turn action
    ----------------------------------------------------------------------------

    --- Play The Fool to interrupt and take an immediate action
    -- @param entity table: The entity playing The Fool
    -- @param foolCard table: The Fool card being played
    -- @param followUpCard table: Optional follow-up card for the action
    -- @param action table: Optional action to take immediately
    -- @return boolean, string: success, error
    function controller:playFoolInterrupt(entity, foolCard, followUpCard, action)
        -- Can only interrupt during COUNT_UP, AWAITING_ACTION, or MINOR_WINDOW
        if self.state ~= M.STATES.COUNT_UP and
           self.state ~= M.STATES.AWAITING_ACTION and
           self.state ~= M.STATES.MINOR_WINDOW then
            return false, "cannot_interrupt_now"
        end

        if not entity or not foolCard then
            return false, "invalid_fool_interrupt"
        end

        -- Verify it's The Fool
        if foolCard.name ~= "The Fool" and not (foolCard.is_major and foolCard.value == 0) then
            return false, "not_the_fool"
        end

        print("[FOOL INTERRUPT] " .. (entity.name or entity.id) .. " plays The Fool!")

        -- Store the current state to restore after interrupt
        local previousState = self.state
        local previousActive = self.activeEntity

        -- Emit interrupt event
        self.eventBus:emit("fool_interrupt_start", {
            entity = entity,
            card = foolCard,
            previousState = previousState,
            previousActive = previousActive,
        })

        -- Temporarily make the interrupting entity active
        self.activeEntity = entity
        self.state = M.STATES.RESOLVING

        -- Build the interrupt action
        local interruptAction = action or {
            actor = entity,
            card = foolCard,
            type = "fool_interrupt",
            followUpCard = followUpCard,
            followUpAction = action and action.type,
            target = action and action.target,
        }

        -- Emit the action for resolution
        self.eventBus:emit(events.EVENTS.CHALLENGE_ACTION, interruptAction)

        -- If no follow-up specified, wait for player to choose
        if not followUpCard and not action then
            self.eventBus:emit("fool_awaiting_followup", {
                entity = entity,
            })
        end

        -- Note: Resolution will call back via resolveAction()
        -- After resolution, we need to restore the previous state
        self.pendingFoolRestore = {
            state = previousState,
            activeEntity = previousActive,
        }

        return true
    end

    --- Called after Fool interrupt resolves to restore state
    function controller:completeFoolInterrupt()
        if self.pendingFoolRestore then
            self.state = self.pendingFoolRestore.state
            self.activeEntity = self.pendingFoolRestore.activeEntity
            self.pendingFoolRestore = nil

            self.eventBus:emit("fool_interrupt_complete", {})

            print("[FOOL INTERRUPT] Complete, resuming normal turn order")
        end
    end

    ----------------------------------------------------------------------------
    -- QUICK! INTERRUPT
    -- A light/no-armor Quick! adventurer can use Pentacles actions out of turn.
    ----------------------------------------------------------------------------

    function controller:canUseQuickInterrupt(entity, card, action)
        if self.state ~= M.STATES.COUNT_UP and
           self.state ~= M.STATES.AWAITING_ACTION and
           self.state ~= M.STATES.MINOR_WINDOW then
            return false, "cannot_interrupt_now"
        end

        if not entity or not card or not action or not action.type then
            return false, "invalid_quick_interrupt"
        end

        if not entityHasUsableTalent(entity, "quick") then
            return false, "requires_quick"
        end

        if not entityWearsLightOrNoArmor(entity) then
            return false, "requires_light_or_no_armor"
        end

        local actionDef = action_registry.getAction(action.type)
        if not actionDef or actionDef.suit ~= action_registry.SUITS.PENTACLES then
            return false, "requires_pentacles_action"
        end

        return true, nil
    end

    function controller:playQuickInterrupt(entity, card, action)
        local ok, reason = self:canUseQuickInterrupt(entity, card, action)
        if not ok then
            return false, reason
        end

        print("[QUICK INTERRUPT] " .. (entity.name or entity.id) ..
              " interrupts with " .. tostring(action.type))

        local previousState = self.state
        local previousActive = self.activeEntity

        self.activeEntity = entity
        self.state = M.STATES.RESOLVING
        self.pendingQuickRestore = {
            state = previousState,
            activeEntity = previousActive,
        }

        action.actor = entity
        action.card = card
        action.round = self.currentRound
        action.count = self.currentCount
        action.challengeController = self
        action.isQuickInterrupt = true
        action.quickInterrupt = true

        self.pendingAction = action

        self.eventBus:emit("quick_interrupt_start", {
            entity = entity,
            card = card,
            action = action,
            previousState = previousState,
            previousActive = previousActive,
        })

        self.eventBus:emit(events.EVENTS.CHALLENGE_ACTION, action)

        return true
    end

    function controller:completeQuickInterrupt()
        if self.pendingQuickRestore then
            self.state = self.pendingQuickRestore.state
            self.activeEntity = self.pendingQuickRestore.activeEntity
            self.pendingQuickRestore = nil
            self.pendingAction = nil

            self.eventBus:emit("quick_interrupt_complete", {})

            print("[QUICK INTERRUPT] Complete, resuming normal turn order")
        end
    end

    ----------------------------------------------------------------------------
    -- COUNSEL
    -- A Cups talent card transfer that can become an interrupt with Resolve.
    ----------------------------------------------------------------------------

    function controller:findCounselCard(playerHand, counselor, card, opts)
        opts = opts or {}
        if not playerHand or not playerHand.hands or not counselor or not counselor.id then
            return nil, nil, "missing_player_hand"
        end

        local handData = playerHand.hands[counselor.id]
        local cards = handData and handData.cards
        if not cards or #cards == 0 then
            return nil, nil, "no_counsel_card"
        end

        local index = tonumber(opts.cardIndex or opts.index)
        if not index and card then
            for i, candidate in ipairs(cards) do
                if candidate == card then
                    index = i
                    break
                end
            end
        end

        if not index then
            return nil, nil, "card_not_in_hand"
        end
        if index < 1 or index > #cards then
            return nil, nil, "invalid_card_index"
        end

        return cards[index], index, nil
    end

    function controller:resolveCounsel(counselor, target, card, actionType, opts)
        opts = opts or {}
        local playerHand = opts.playerHand or self.playerHand

        if self.state == M.STATES.IDLE or self.state == M.STATES.ENDING then
            return false, "not_in_challenge"
        end
        if not counselor or not target then
            return false, "invalid_counsel"
        end
        if counselor == target or counselor.id == target.id then
            return false, "requires_other_adventurer"
        end
        if not target.isPC then
            return false, "requires_adventurer_target"
        end
        if not entityHasUsableTalent(counselor, "counsel") then
            return false, "requires_counsel"
        end

        local round = self.currentRound or 0
        if counselor.counselUsedRound == round then
            return false, "counsel_already_used"
        end

        local actionDef = action_registry.getAction(actionType)
        if not actionDef then
            return false, "unknown_counsel_action"
        end
        if actionDef.suit == action_registry.SUITS.MISC then
            return false, "requires_suited_action"
        end

        local heldCard, cardIndex, cardReason = self:findCounselCard(playerHand, counselor, card, opts)
        if not heldCard then
            return false, cardReason
        end

        local cardSuit = action_registry.cardSuitToActionSuit(heldCard.suit)
        if cardSuit ~= actionDef.suit then
            return false, "suit_mismatch"
        end

        local interrupt = opts.spendResolve == true or opts.resolveForInterrupt == true or
            opts.spendResolveForInterrupt == true
        local resolveSpent = false
        if interrupt then
            local spent, spendReason = spendEntityResolve(counselor, 1)
            if not spent then
                return false, spendReason or "not_enough_resolve"
            end
            resolveSpent = true
        end

        local sourceHand = playerHand.hands[counselor.id].cards
        table.remove(sourceHand, cardIndex)
        playerHand.hands[target.id] = playerHand.hands[target.id] or {}
        playerHand.hands[target.id].cards = playerHand.hands[target.id].cards or {}
        local targetHand = playerHand.hands[target.id].cards
        targetHand[#targetHand + 1] = heldCard

        counselor.counselUsedRound = round
        heldCard.counsel = {
            counselorId = counselor.id,
            targetId = target.id,
            actionType = actionType,
            round = round,
            interrupt = interrupt,
            resolveSpent = resolveSpent,
        }

        local detail = {
            counselor = counselor,
            target = target,
            card = heldCard,
            actionType = actionType,
            interrupt = interrupt,
            resolveSpent = resolveSpent,
        }

        self.eventBus:emit("counsel_card_given", detail)

        return true, detail
    end

    ----------------------------------------------------------------------------
    -- QUERIES
    ----------------------------------------------------------------------------

    function controller:isActive()
        return self.state ~= M.STATES.IDLE
    end

    function controller:getCurrentCount()
        return self.currentCount
    end

    function controller:getCurrentRound()
        return self.currentRound
    end

    --- Legacy compatibility: getCurrentTurn returns count
    function controller:getCurrentTurn()
        return self.currentCount
    end

    function controller:getMaxTurns()
        return MAX_TURNS
    end

    function controller:getActiveEntity()
        return self.activeEntity
    end

    function controller:getState()
        return self.state
    end

    function controller:getCombatants()
        return self.allCombatants
    end

    function controller:isPlayerTurn()
        return self.activeEntity and self.activeEntity.isPC
    end

    function controller:isAwaitingInitiative()
        return self.state == M.STATES.PRE_ROUND
    end

    function controller:getAwaitingInitiativeList()
        local list = {}
        for id, _ in pairs(self.awaitingInitiative) do
            list[#list + 1] = id
        end
        return list
    end

    function controller:getInitiativeSlot(entityId)
        return self.initiativeSlots[entityId]
    end

    --- S6.4: Check if in minor action window
    function controller:isInMinorWindow()
        return self.state == M.STATES.MINOR_WINDOW
    end

    --- S6.4: Get pending minor actions
    function controller:getPendingMinors()
        return self.pendingMinors
    end

    return controller
end

return M
