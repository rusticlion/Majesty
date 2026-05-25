-- npc_ai.lua
-- NPC "Dread" AI System for Majesty
-- Ticket S4.5: Basic NPC decision-making for challenges
--
-- AI Decision Logic:
-- 1. Elite/Lord NPCs with Greater Doom (15-21) try to use it immediately
-- 2. Otherwise, attack the PC with lowest current defense
-- 3. Mob Rule: NPCs in same zone get Favor/Piercing bonuses
--
-- This is intentionally simple - NPCs should feel dangerous but fair.

local events = require('logic.events')
local action_resolver = require('logic.action_resolver')
local deck = require('logic.deck')
local inventory = require('logic.inventory')

local M = {}

local function cloneValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, entry in pairs(value) do
        copy[key] = cloneValue(entry)
    end
    return copy
end

--------------------------------------------------------------------------------
-- NPC RANKS (determines AI aggression)
--------------------------------------------------------------------------------
M.RANKS = {
    MINION  = "minion",    -- Basic enemy, simple tactics
    SOLDIER = "soldier",   -- Standard enemy
    ELITE   = "elite",     -- Uses Greater Dooms aggressively
    LORD    = "lord",      -- Boss-level, always uses best card
}

--------------------------------------------------------------------------------
-- S12.6: DOOM CARD CLASSIFICATION
-- Lesser Doom:  Major Arcana 1-14 (Magician through Temperance) - standard actions
-- Greater Doom: Major Arcana 15-21 (Devil through World) - potent special effects
--
-- Rulebook parity: ordinary challenge actions use lesser dooms.
--------------------------------------------------------------------------------
local LARGE_SIZE_VALUES = {
    large = true,
    huge = true,
    giant = true,
    colossal = true,
}

local TARGETED_ACTION_TYPES = {
    [action_resolver.ACTION_TYPES.MELEE] = true,
    [action_resolver.ACTION_TYPES.MISSILE] = true,
    [action_resolver.ACTION_TYPES.ROUGHHOUSE] = true,
    [action_resolver.ACTION_TYPES.TRIP] = true,
    [action_resolver.ACTION_TYPES.DISARM] = true,
    [action_resolver.ACTION_TYPES.DISPLACE] = true,
    [action_resolver.ACTION_TYPES.GRAPPLE] = true,
    [action_resolver.ACTION_TYPES.BANTER] = true,
    [action_resolver.ACTION_TYPES.PARLEY] = true,
    [action_resolver.ACTION_TYPES.SPEAK_INCANTATION] = true,
    [action_resolver.ACTION_TYPES.USE_ITEM] = true,
}

M.GM_CHALLENGE_REFERENCE = {
    source = "Core Rules Chapter 7: GMing the Challenge",
    sourcePages = "121-123",
    roundDrawFormula = {
        deck = "major_arcana",
        timing = "step_1_draw_challenge_cards",
        base = 3,
        recalculatedEachRound = true,
        runtimeMinimum = 1,
        modifiers = {
            { id = "enemy_type", amount = 1, per = "distinct enemy type" },
            { id = "outnumber", amount = 1, when = "living enemies outnumber living adventurers" },
            { id = "double_outnumber", amount = 1, when = "living enemies are at least twice living adventurers" },
            { id = "larger_than_human", amount = 1, per = "enemy physically larger than a human" },
            { id = "elite_enemy", amount = 2, when = "at least one elite enemy is present" },
            { id = "dungeon_lord", amount = 3, when = "at least one dungeon lord is present" },
        },
        examples = {
            {
                id = "twelve_imps_vs_four_adventurers",
                enemies = 12,
                adventurers = 4,
                enemyTypes = 1,
                total = 6,
            },
            {
                id = "seven_imps_vs_four_adventurers",
                enemies = 7,
                adventurers = 4,
                enemyTypes = 1,
                total = 5,
            },
        },
    },
    mulligan = {
        optional = true,
        trigger = "GM hand is mostly greater dooms or has no lesser dooms",
        procedure = {
            "discard all drawn GM cards",
            "draw the same number again",
        },
        runtimeHook = "shouldMulliganRoundHand",
    },
    initiative = {
        timing = "step_2_play_initiative",
        facedown = true,
        oneCardForEach = "significant enemy or enemy group",
        sameEnemyTypeSharesCard = true,
        significantEnemyKeys = {
            "significant",
            M.RANKS.ELITE,
            M.RANKS.LORD,
            "dungeon_lord",
        },
        facedownActionLimit = "every enemy with an Initiative card can have one facedown Challenge Action",
        runtimeHooks = {
            "getInitiativeGroupKey",
            "handleNPCInitiative",
            "discardRoundInitiativeCards",
        },
    },
    doomCards = {
        lesser = {
            values = { min = 1, max = 14 },
            use = {
                "standard Challenge Actions",
                "lesser doom creature abilities",
                "Initiative cards when available",
            },
        },
        greater = {
            values = { min = 15, max = 21 },
            use = {
                "greater doom creature abilities",
                "targeted greater doom riders paired with a lesser-doom Attack",
                "environmental or self-affecting greater doom effects",
                "discard for favor on another Challenge Action",
                "miscellaneous actions except Vigilance",
            },
            standardChallengeActionDefault = false,
            creatureSpecificExceptions = true,
        },
    },
    enemyActions = {
        timing = "step_3_enemy_actions",
        majorArcanaValue = "card number",
        lesserDoomsForStandardActions = true,
        attributesAddedOnEnemyTurns = true,
        targetedGreaterDoomRequiresLesserAttack = true,
    },
    minorActions = {
        timing = "step_4_minor_actions",
        majorArcanaHaveNoSuits = true,
        anyMajorArcanaMayDeclareMinor = true,
        ordinaryActionsUseLesserDooms = true,
        greaterDoomsUseGreaterDoomAbilities = true,
        oneMinorPerEnemyOrEnemyGroup = true,
        activeEnemyOrGroupCannotMinorAfterItsOwnTurn = true,
    },
    endRound = {
        timing = "step_5_end_round",
        assessVictoryOrRetreat = true,
        facedownActionsRemain = true,
        discardUnusedGMHand = true,
        discardCurrentInitiativeCards = true,
        foolDrawShufflesBothDecks = true,
        restatePositionsAtNewRound = true,
    },
    mobRule = {
        sourcePages = "122",
        groupSameAction = true,
        thresholds = {
            { attackers = 2, favor = true, piercing = false, critical = false },
            { attackers = 4, favor = true, piercing = true, critical = false },
            { attackers = 8, favor = true, piercing = false, critical = true },
        },
    },
}

function M.getGMChallengeReference()
    return cloneValue(M.GM_CHALLENGE_REFERENCE)
end

function M.getGMRoundDrawFormula()
    return cloneValue(M.GM_CHALLENGE_REFERENCE.roundDrawFormula)
end

function M.getGMMobRule()
    return cloneValue(M.GM_CHALLENGE_REFERENCE.mobRule)
end

--------------------------------------------------------------------------------
-- NPC AI FACTORY
--------------------------------------------------------------------------------

--- Create a new NPC AI manager
-- @param config table: { eventBus, challengeController, actionResolver, gmDeck, zoneSystem }
-- @return NPCAI instance
function M.createNPCAI(config)
    config = config or {}

    local ai = {
        eventBus            = config.eventBus or events.globalBus,
        challengeController = config.challengeController,
        actionResolver      = config.actionResolver,
        gmDeck              = config.gmDeck,
        zoneSystem          = config.zoneSystem,

        -- GM's hand (cards available for NPC actions)
        hand = {},
        baseHandSize = 3,
        lastPreparedRound = nil,
        roundInitiativeCards = {},
        mulliganMostlyGreaterDooms = config.mulliganMostlyGreaterDooms ~= false,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function ai:init()
        -- Listen for NPC turns
        self.eventBus:on("npc_turn", function(data)
            self:handleNPCTurn(data)
        end)

        -- Listen for NPC initiative selection (S4.6)
        self.eventBus:on("npc_choose_initiative", function(data)
            self:handleNPCInitiative(data)
        end)

        -- Start with an empty hand; round setup draws with parity formula.
        self.eventBus:on(events.EVENTS.CHALLENGE_START, function(data)
            self.hand = {}
            self.lastPreparedRound = nil
            self.roundInitiativeCards = {}
        end)

        -- Draw a fresh hand at the start of each round.
        self.eventBus:on("initiative_phase_start", function(data)
            self:refreshRoundHand(data and data.round)
        end)

        -- Rulebook step 5: discard unused GM Challenge cards before any
        -- Fool-triggered end-round reshuffle happens.
        self.eventBus:on(events.EVENTS.CHALLENGE_ROUND_END, function(data)
            self:discardRoundInitiativeCards()
            self:discardHand()
        end)

        -- Listen for challenge end to discard hand
        self.eventBus:on(events.EVENTS.CHALLENGE_END, function(data)
            self:discardRoundInitiativeCards()
            self:discardHand()
            self.lastPreparedRound = nil
        end)
    end

    ----------------------------------------------------------------------------
    -- INITIATIVE SELECTION (S4.6)
    ----------------------------------------------------------------------------

    --- Handle NPC initiative card selection
    -- @param data table: { npc, round }
    function ai:handleNPCInitiative(data)
        local npc = data.npc
        if not npc then return end

        local groupKey = self:getInitiativeGroupKey(npc)
        local groupedCard = self.roundInitiativeCards[groupKey]
        if groupedCard then
            print("[NPC AI] " .. (npc.name or "NPC") .. " shares initiative: " .. (groupedCard.name or "?") .. " (value " .. (groupedCard.value or 0) .. ")")
            if self.challengeController then
                self.challengeController:submitInitiative(npc, groupedCard)
            end
            return
        end

        -- Ensure we have cards.
        -- If the round hand was exhausted, draw a single emergency card
        -- so initiative submission cannot deadlock the challenge loop.
        if #self.hand == 0 then
            local emergencyCard = self:drawEmergencyCard("initiative")
            if emergencyCard then
                self.hand[#self.hand + 1] = emergencyCard
            end
        end

        if #self.hand == 0 then
            print("[NPC AI] No cards for initiative!")
            return
        end

        -- Choose initiative card based on rank/behavior
        local cardIndex = self:chooseInitiativeCard(npc)
        local card = self:takeCardFromHand(cardIndex)

        if card then
            self.roundInitiativeCards[groupKey] = card
            print("[NPC AI] " .. (npc.name or "NPC") .. " chose initiative: " .. (card.name or "?") .. " (value " .. (card.value or 0) .. ")")

            -- Submit to challenge controller
            if self.challengeController then
                self.challengeController:submitInitiative(npc, card)
            end
        end
    end

    function ai:getInitiativeGroupKey(npc)
        if not npc then
            return "unknown"
        end

        local rank = (npc.rank or ""):lower()
        if npc.significant or rank == M.RANKS.ELITE or rank == M.RANKS.LORD or rank == "dungeon_lord" then
            return npc.id or npc.name or "significant"
        end

        return npc.blueprintId or npc.enemyType or npc.species or npc.name or npc.id or "unknown"
    end

    --- Choose which card to use for initiative based on NPC behavior
    -- Aggressive mobs pick LOW values (act early)
    -- Cowardly/defensive mobs pick HIGH values (act late, react to others)
    -- @param npc table: The NPC entity
    -- @return number: Index of card to use
    function ai:chooseInitiativeCard(npc)
        local rank = npc.rank or M.RANKS.SOLDIER
        local behavior = npc.behavior or "aggressive"

        -- Initiative normally uses lesser dooms (1-14).
        -- If none exist, fall back to any card to avoid dead turns.
        local sorted = {}
        for i, card in ipairs(self.hand) do
            if self:isLesserDoom(card) then
                sorted[#sorted + 1] = { index = i, value = card.value or 0 }
            end
        end
        if #sorted == 0 then
            for i, card in ipairs(self.hand) do
                sorted[#sorted + 1] = { index = i, value = card.value or 0 }
            end
        end
        table.sort(sorted, function(a, b)
            return a.value < b.value
        end)

        local conditions = npc.conditions or {}
        local impWimp = npc.blueprintId == "imp" or npc.enemyType == "imp" or
            (npc.imp and npc.imp.wimps and npc.imp.wimps.alwaysLowestInitiative)
        if npc.mustPlayLowestInitiative or impWimp or npc.brainfever or conditions.brainfever then
            return sorted[1].index
        end
        if npc.mustFleeFrom or conditions.inspiredFear or conditions.fearful then
            return sorted[#sorted].index
        end

        -- Aggressive: pick lowest value (act first)
        if behavior == "aggressive" or rank == M.RANKS.LORD then
            return sorted[1].index
        end

        -- Cowardly/defensive: pick highest value (act last, defensive)
        if behavior == "cowardly" or behavior == "defensive" then
            return sorted[#sorted].index
        end

        -- Default (soldier): pick middle value
        local middleIdx = math.ceil(#sorted / 2)
        return sorted[middleIdx].index
    end

    ----------------------------------------------------------------------------
    -- HAND MANAGEMENT
    ----------------------------------------------------------------------------

    function ai:isDefeated(entity)
        if not entity then
            return true
        end
        return entity.conditions and (entity.conditions.dead or entity.conditions.deaths_door or
            entity.conditions.knocked_out or entity.conditions.knockout)
    end

    function ai:isLesserDoom(card)
        return deck.isLesserDoom(card)
    end

    function ai:isGreaterDoom(card)
        return deck.isGreaterDoom(card)
    end

    function ai:isLargerThanHuman(npc)
        if not npc then
            return false
        end
        if npc.isLargerThanHuman ~= nil then
            return npc.isLargerThanHuman
        end

        local size = npc.size
        if type(size) == "number" then
            return size > 1
        end
        if type(size) == "string" then
            return LARGE_SIZE_VALUES[size:lower()] == true
        end
        return false
    end

    function ai:normalizeAuthoredActionType(value)
        local normalized
        if self.actionResolver and self.actionResolver.normalizeActionType then
            normalized = self.actionResolver:normalizeActionType(value)
        end
        if normalized then
            return normalized
        end

        value = tostring(value or ""):lower()
        value = value:gsub("[^%w]+", "_")
        value = value:gsub("^_+", ""):gsub("_+$", "")
        return action_resolver.ACTION_ALIASES[value] or value
    end

    function ai:collectAuthoredActions(npc)
        local actions = {}
        local sourceKeys = {
            "aiActions",
            "preferredActions",
            "challengeActions",
            "authoredActions",
            "tactics",
        }

        for _, sourceKey in ipairs(sourceKeys) do
            local source = npc and npc[sourceKey]
            if type(source) == "table" then
                if source.type or source.actionType or source.action then
                    actions[#actions + 1] = source
                else
                    for _, entry in ipairs(source) do
                        if type(entry) == "table" and (entry.type or entry.actionType or entry.action) then
                            actions[#actions + 1] = entry
                        end
                    end
                end
            end
        end

        return actions
    end

    function ai:findAuthoredTarget(npc, pcs, entry, actionType)
        if entry.target then
            return entry.target
        end

        local targetId = entry.targetId or entry.target_id
        if targetId then
            for _, pc in ipairs(pcs or {}) do
                if pc == targetId or pc.id == targetId or pc.name == targetId then
                    return pc
                end
            end
        end

        local mode = tostring(entry.targetMode or entry.targeting or entry.targetScope or ""):lower()
        if mode == "self" or mode == "actor" then
            return npc
        end
        if mode == "none" or mode == "environment" or mode == "zone" then
            return nil
        end
        if mode == "same_zone_pc" or mode == "same_zone" or mode == "melee" or entry.requiresSameZone == true then
            return self:selectTarget(npc, pcs or {}, true)
        end
        if mode == "any_pc" or mode == "pc" or mode == "target" or mode == "lowest_defense" then
            return self:selectTarget(npc, pcs or {}, false)
        end

        if TARGETED_ACTION_TYPES[actionType] then
            return self:selectTarget(npc, pcs or {}, actionType == action_resolver.ACTION_TYPES.MELEE)
        end
        return nil
    end

    function ai:selectCardForAuthoredAction(entry, actionType)
        if entry.cardless == true or entry.cardPolicy == "none" or entry.cardUse == "none" then
            return nil, nil, true
        end

        local policy = entry.cardPolicy or entry.cardUse or entry.doomType or entry.doom
        if not policy then
            if actionType == action_resolver.ACTION_TYPES.MOVE or
                actionType == action_resolver.ACTION_TYPES.FREE_ACTION or
                actionType == action_resolver.ACTION_TYPES.TRIVIAL_ACTION or
                actionType == action_resolver.ACTION_TYPES.INTERACT then
                policy = "any"
            else
                policy = "lesser"
            end
        end
        policy = tostring(policy):lower()

        local index
        if policy == "greater" or policy == "greater_doom" then
            index = self:findGreaterDoom()
        elseif policy == "any" or policy == "misc" or policy == "miscellaneous" then
            index = self:selectBestActionCard()
        else
            index = self:selectBestLesserActionCard()
        end

        if not index then
            return nil, nil, false
        end
        return index, self.hand[index], true
    end

    function ai:findAuthoredItem(npc, entry)
        if entry.item then
            return entry.item
        end
        local inv = npc and npc.inventory
        if not inv then
            return nil
        end
        local itemId = entry.itemId or entry.item_id
        if itemId and inv.findItem then
            local item = inv:findItem(itemId)
            if item then
                return item
            end
        end
        local templateId = entry.templateId or entry.itemTemplateId or entry.itemTemplate
        if templateId and inv.findItemByPredicate then
            return inv:findItemByPredicate(function(item)
                return item.templateId == templateId or item.id == templateId
            end)
        end
        return nil
    end

    function ai:findAuthoredGreaterDoom(npc, entry)
        if not entry then
            return nil
        end
        if type(entry.greaterDoom) == "table" then
            return entry.greaterDoom
        end

        local function normalizeKey(value)
            value = tostring(value or ""):lower()
            value = value:gsub("[^%w]+", "_")
            value = value:gsub("^_+", ""):gsub("_+$", "")
            return value
        end

        local doomId = entry.greaterDoomId or entry.doomId or entry.doom_id
        if type(entry.greaterDoom) == "string" then
            doomId = doomId or entry.greaterDoom
        end
        local effectType = entry.greaterDoomEffectType or entry.doomEffectType
        local normalizedDoomId = normalizeKey(doomId)
        local normalizedEffectType = normalizeKey(effectType)

        if normalizedDoomId == "" and normalizedEffectType == "" and
           entry.requiresGreaterDoom ~= true and entry.useGreaterDoom ~= true then
            return nil
        end

        for _, doom in pairs(npc and npc.greaterDooms or {}) do
            local effect = doom and doom.effect
            if normalizedDoomId ~= "" and
               (normalizeKey(doom.id) == normalizedDoomId or normalizeKey(doom.name) == normalizedDoomId) then
                return doom
            end
            if normalizedEffectType ~= "" and effect and normalizeKey(effect.type) == normalizedEffectType then
                return doom
            end
        end

        local doom = npc and npc.greaterDoom
        local effect = doom and doom.effect
        if doom and normalizedDoomId ~= "" and
           (normalizeKey(doom.id) == normalizedDoomId or normalizeKey(doom.name) == normalizedDoomId) then
            return doom
        end
        if doom and normalizedEffectType ~= "" and effect and normalizeKey(effect.type) == normalizedEffectType then
            return doom
        end

        return nil
    end

    function ai:createAuthoredAction(npc, pcs, entry)
        local actionType = self:normalizeAuthoredActionType(entry.type or entry.actionType or entry.action)
        if not actionType or actionType == "" then
            return nil
        end

        local target = self:findAuthoredTarget(npc, pcs, entry, actionType)
        if TARGETED_ACTION_TYPES[actionType] and not target and entry.targetOptional ~= true then
            return nil
        end

        local item
        if actionType == action_resolver.ACTION_TYPES.USE_ITEM or actionType == action_resolver.ACTION_TYPES.PULL_ITEM then
            item = self:findAuthoredItem(npc, entry)
            if not item and entry.requiresItem ~= false then
                return nil
            end
        end

        local cardIndex, card, usable = self:selectCardForAuthoredAction(entry, actionType)
        if not usable then
            return nil
        end

        local greaterDoom = self:findAuthoredGreaterDoom(npc, entry)
        local needsGreaterDoom = entry.requiresGreaterDoom == true or entry.useGreaterDoom == true or
            entry.greaterDoomId ~= nil or entry.doomId ~= nil or entry.doom_id ~= nil or
            entry.greaterDoomEffectType ~= nil or entry.doomEffectType ~= nil or
            type(entry.greaterDoom) == "table" or type(entry.greaterDoom) == "string"
        if needsGreaterDoom and not greaterDoom then
            return nil
        end

        local greaterCardIndex
        local greaterCard
        if needsGreaterDoom and entry.greaterDoomCardless ~= true then
            greaterCardIndex = self:findGreaterDoom()
            if not greaterCardIndex or greaterCardIndex == cardIndex then
                return nil
            end
        end

        if cardIndex and greaterCardIndex then
            card, greaterCard = self:useDoomPair(cardIndex, greaterCardIndex)
        elseif cardIndex then
            card = self:useCard(cardIndex)
        elseif greaterCardIndex then
            greaterCard = self:useCard(greaterCardIndex)
        end

        local action = {}
        for key, value in pairs(entry) do
            if key ~= "cardPolicy" and key ~= "cardUse" and key ~= "doomType" and key ~= "doom" then
                action[key] = value
            end
        end
        action.actor = npc
        action.target = target
        action.card = card
        action.type = actionType
        action.item = item or action.item
        action.greaterDoom = greaterDoom or action.greaterDoom
        if greaterCard then
            action.greaterDoomCard = greaterCard
            action.discardedGreaterDoom = greaterCard
            action.greaterDoomCardCount = action.greaterDoomCardCount or action.greaterDoomCount or 1
        end
        action.allEntities = self.challengeController and self.challengeController.allCombatants
        action.npcAIAuthoredAction = true
        action.npcAIActionSource = entry.source or entry.id or actionType
        return action
    end

    function ai:selectAuthoredChallengeAction(npc, pcs)
        for _, entry in ipairs(self:collectAuthoredActions(npc)) do
            local action = self:createAuthoredAction(npc, pcs, entry)
            if action then
                return action
            end
        end
        return nil
    end

    function ai:hasTag(entity, tag)
        if not entity or not tag then
            return false
        end
        tag = tostring(tag):lower()
        for _, candidate in ipairs(entity.tags or {}) do
            if tostring(candidate):lower() == tag then
                return true
            end
        end
        return false
    end

    function ai:isDogLike(npc)
        if not npc then
            return false
        end
        if npc.dog or npc.hound or self:hasTag(npc, "dog") or self:hasTag(npc, "hound") then
            return true
        end

        local candidates = {
            npc.species,
            npc.type,
            npc.enemyType,
            npc.blueprintId,
            npc.name,
        }
        for _, candidate in ipairs(candidates) do
            local value = tostring(candidate or ""):lower()
            if value:find("dog", 1, true) or value:find("hound", 1, true) then
                return true
            end
        end
        return false
    end

    function ai:targetHasDogCurse(target)
        if not target then
            return false
        end
        if target.dogsHateYou or target.dogAttackPriority or target.cityPhaseDogCurse then
            return true
        end

        local malediction = target.malediction
        local curse = malediction and malediction.curse
        local flags = curse and curse.flags
        return malediction and malediction.active ~= false and flags and flags.dogsHateYou == true
    end

    function ai:isUndead(npc)
        if not npc then
            return false
        end
        return npc.undead == true or npc.isUndead == true or self:hasTag(npc, "undead")
    end

    function ai:isSpirit(npc)
        if not npc then
            return false
        end
        return npc.spirit == true or npc.isSpirit == true or self:hasTag(npc, "spirit")
    end

    function ai:isWraith(npc)
        if not npc then
            return false
        end
        if npc.wraith == true or self:hasTag(npc, "wraith") then
            return true
        end
        local blueprint = tostring(npc.blueprintId or npc.enemyType or npc.species or npc.name or ""):lower()
        return blueprint:find("wraith", 1, true) ~= nil
    end

    function ai:isVisibleLightSourceItem(item, location)
        if not item then
            return false
        end
        local props = item.properties or {}
        if not (props.light_source == true or props.lightSource == true or item.light_source == true) then
            return false
        end
        if not (props.isLit == true or props.lit == true or item.isLit == true or item.lit == true) then
            return false
        end
        if props.darklight == true or item.darklight == true or props.stealthLight == true or item.stealthLight == true then
            return false
        end
        if props.extinguished == true or item.extinguished == true then
            return false
        end
        if location == inventory.LOCATIONS.BELT and props.provides_belt_light == false then
            return false
        end
        return true
    end

    function ai:targetCarriesVisibleLightSource(target)
        if not target then
            return false
        end
        if target.carryingVisibleLightSource == true or target.visibleLightSource == true then
            return true
        end
        if self.actionResolver and self.actionResolver.entityHoldsVisibleLightSource then
            return self.actionResolver:entityHoldsVisibleLightSource(target)
        end

        local inv = target.inventory
        if not inv then
            return false
        end
        for _, location in ipairs({ inventory.LOCATIONS.HANDS, inventory.LOCATIONS.BELT }) do
            local items = inv.getItems and inv:getItems(location) or inv[location] or {}
            for _, item in ipairs(items or {}) do
                if self:isVisibleLightSourceItem(item, location) then
                    return true
                end
            end
        end
        return false
    end

    function ai:targetIsIgnoredByUndead(target)
        if not target then
            return false
        end
        if target.undeadUsuallyIgnore or target.appearsAsDesiccatedCorpse then
            return true
        end

        local malediction = target.malediction
        local curse = malediction and malediction.curse
        local flags = curse and curse.flags
        return malediction and malediction.active ~= false and flags and flags.undeadUsuallyIgnore == true
    end

    function ai:targetHasUndeadMark(target)
        if not target then
            return false
        end
        local conditions = target.conditions or {}
        return conditions.undead_mark == true or target.undeadMark == true
    end

    function ai:targetHasHalo(target)
        if not target then
            return false
        end
        local conditions = target.conditions or {}
        return conditions.halo == true or target.halo == true
    end

    function ai:hasAnyLesserDoom()
        for _, card in ipairs(self.hand) do
            if self:isLesserDoom(card) then
                return true
            end
        end
        return false
    end

    function ai:shouldMulliganRoundHand()
        if not self.mulliganMostlyGreaterDooms or #self.hand == 0 then
            return false, nil
        end

        local greaterDooms = 0
        local lesserDooms = 0
        for _, card in ipairs(self.hand) do
            if self:isGreaterDoom(card) then
                greaterDooms = greaterDooms + 1
            elseif self:isLesserDoom(card) then
                lesserDooms = lesserDooms + 1
            end
        end

        if lesserDooms == 0 then
            return true, "no_lesser_dooms"
        end
        if greaterDooms > (#self.hand / 2) then
            return true, "mostly_greater_dooms"
        end

        return false, nil
    end

    function ai:getAttackGreaterDoom(npc)
        if not npc then
            return nil
        end

        for _, doom in pairs(npc.greaterDooms or {}) do
            if doom.activation == "attack_rider" or doom.trigger == "on_attack" then
                return doom
            end
        end

        local doom = npc.greaterDoom
        if doom and (doom.activation == "attack_rider" or doom.trigger == "on_attack") then
            return doom
        end

        return nil
    end

    function ai:calculateRoundDrawCount()
        local drawCount = self.baseHandSize
        local controller = self.challengeController
        if not controller then
            return drawCount
        end

        local livingNPCs = {}
        local livingPCs = {}

        for _, npc in ipairs(controller.npcs or {}) do
            if not self:isDefeated(npc) then
                livingNPCs[#livingNPCs + 1] = npc
            end
        end

        for _, pc in ipairs(controller.pcs or {}) do
            if not self:isDefeated(pc) then
                livingPCs[#livingPCs + 1] = pc
            end
        end

        if #livingNPCs == 0 then
            return drawCount
        end

        local enemyTypes = {}
        local hasElite = false
        local hasLord = false
        local largerCount = 0

        for _, npc in ipairs(livingNPCs) do
            local typeKey = npc.blueprintId or npc.enemyType or npc.species or npc.name or npc.id
            enemyTypes[typeKey] = true

            local rank = (npc.rank or ""):lower()
            if rank == M.RANKS.ELITE then
                hasElite = true
            end
            if rank == M.RANKS.LORD or rank == "dungeon_lord" then
                hasLord = true
            end
            if self:isLargerThanHuman(npc) then
                largerCount = largerCount + 1
            end
        end

        local enemyTypeCount = 0
        for _, _ in pairs(enemyTypes) do
            enemyTypeCount = enemyTypeCount + 1
        end

        drawCount = drawCount + enemyTypeCount

        local pcCount = #livingPCs
        local npcCount = #livingNPCs
        if pcCount > 0 and npcCount > pcCount then
            drawCount = drawCount + 1
        end
        if pcCount > 0 and npcCount >= (pcCount * 2) then
            drawCount = drawCount + 1
        end

        drawCount = drawCount + largerCount
        if hasElite then
            drawCount = drawCount + 2
        end
        if hasLord then
            drawCount = drawCount + 3
        end

        local drawPenalty = 0
        local drawBonus = 0
        for _, npc in ipairs(livingNPCs) do
            drawPenalty = drawPenalty + math.max(0, npc.stinkingCloudDrawPenalty or npc.challengeDrawPenalty or 0)
            drawBonus = drawBonus + math.max(0, npc.gmChallengeCardsBonus or npc.challengeDrawBonus or 0)
        end
        drawCount = drawCount + drawBonus - drawPenalty

        return math.max(1, drawCount)
    end

    --- Draw cards into GM hand (fresh hand each round)
    function ai:drawHand(drawCount)
        self.hand = {}
        if not self.gmDeck then return end

        local toDraw = drawCount or self.baseHandSize
        for _ = 1, toDraw do
            local card = self.gmDeck:draw()
            if card then
                self.hand[#self.hand + 1] = card
            end
        end
    end

    --- Draw a fresh hand using GM round formula (with one mulligan when unusable).
    function ai:refreshRoundHand(round)
        if round and self.lastPreparedRound == round then
            return
        end

        if not self.gmDeck then
            self.hand = {}
            return
        end

        self:discardHand()
        self.roundInitiativeCards = {}
        local drawCount = self:calculateRoundDrawCount()
        self:drawHand(drawCount)

        local shouldMulligan, mulliganReason = self:shouldMulliganRoundHand()
        if shouldMulligan then
            print("[NPC AI] Mulliganing hand (" .. tostring(mulliganReason) .. ").")
            self:discardHand()
            self:drawHand(drawCount)
        end

        self.lastPreparedRound = round or self.lastPreparedRound
        print("[NPC AI] Drew " .. #self.hand .. " GM cards for round.")
    end

    --- Draw one fallback card to prevent initiative deadlocks if the hand is empty.
    function ai:drawEmergencyCard(context)
        if not self.gmDeck then
            return nil
        end

        local card = self.gmDeck:draw()
        if card then
            print("[NPC AI] Emergency draw for " .. tostring(context) .. ": " .. (card.name or "?"))
        end
        return card
    end

    --- Discard all cards in hand
    function ai:discardHand()
        if self.gmDeck then
            for _, card in ipairs(self.hand) do
                self.gmDeck:discard(card)
            end
        end
        self.hand = {}
    end

    function ai:discardRoundInitiativeCards()
        local seen = {}
        if self.gmDeck then
            for _, card in pairs(self.roundInitiativeCards or {}) do
                if card and not seen[card] then
                    self.gmDeck:discard(card)
                    seen[card] = true
                end
            end
        end
        self.roundInitiativeCards = {}
    end

    --- Remove a card from the GM hand without discarding it.
    function ai:takeCardFromHand(index)
        if index and index <= #self.hand then
            return table.remove(self.hand, index)
        end
        return nil
    end

    --- Use a card from hand (remove and return it)
    function ai:useCard(index)
        local card = self:takeCardFromHand(index)
        if card and self.gmDeck then
            self.gmDeck:discard(card)
        end
        return card
    end

    function ai:useDoomPair(lesserIndex, greaterIndex)
        if not lesserIndex or not greaterIndex or lesserIndex == greaterIndex then
            return nil, nil
        end

        local lesserCard = nil
        local greaterCard = nil

        if lesserIndex > greaterIndex then
            lesserCard = self:useCard(lesserIndex)
            greaterCard = self:useCard(greaterIndex)
        else
            greaterCard = self:useCard(greaterIndex)
            lesserCard = self:useCard(lesserIndex)
        end

        return lesserCard, greaterCard
    end

    function ai:spendGreaterDoomForFavor(action)
        if not action or action.favor == true then
            return action
        end

        local greaterIndex = self:findGreaterDoom()
        if not greaterIndex then
            return action
        end

        local greaterCard = self:useCard(greaterIndex)
        if not greaterCard then
            return action
        end

        action.greaterDoomFavor = true
        action.greaterDoomFavorCard = greaterCard
        action.discardedGreaterDoomForFavor = greaterCard
        return action
    end

    ----------------------------------------------------------------------------
    -- MAIN DECISION ENTRY POINT
    ----------------------------------------------------------------------------

    --- Handle an NPC's turn
    -- @param data table: { npc, turn, pcs }
    function ai:handleNPCTurn(data)
        local npc = data.npc
        local pcs = data.pcs or {}

        if not npc then
            print("[NPC AI] No NPC provided!")
            return
        end

        print("[NPC AI] " .. (npc.name or "NPC") .. " is deciding...")

        -- Make decision
        local decision = self:decide(npc, pcs)

        if decision then
            -- Submit action to challenge controller
            if self.challengeController then
                self.challengeController:submitAction(decision)
            end
        else
            -- No valid action, pass turn
            print("[NPC AI] " .. (npc.name or "NPC") .. " has no valid action")
            if self.challengeController and self.challengeController.skipTurn then
                self.challengeController:skipTurn(npc, "no_valid_action")
            else
                self.eventBus:emit(events.EVENTS.UI_SEQUENCE_COMPLETE, {})
            end
        end
    end

    --- Main decision function
    -- @param npc table: The NPC entity
    -- @param pcs table: Array of PC entities
    -- @return table: Action to take, or nil
    function ai:decide(npc, pcs)
        if #self.hand == 0 then
            local emergencyCard = self:drawEmergencyCard("action")
            if emergencyCard then
                self.hand[#self.hand + 1] = emergencyCard
            end
        end

        if #self.hand == 0 then
            return nil  -- No cards available
        end

        local fearFleeDestination = self:selectFearFleeDestination(npc)
        if fearFleeDestination then
            local cardIndex = self:selectBestActionCard()
            local card = self:useCard(cardIndex)
            if card then
                print("[NPC AI] " .. (npc.name or "NPC") .. " flees from fear toward " .. fearFleeDestination)
                local action = self:createMoveAction(npc, fearFleeDestination, card)
                action.fearFlee = true
                action.fleeSource = npc.mustFleeFrom
                action.fleeSourceId = npc.mustFleeFrom and (npc.mustFleeFrom.id or npc.mustFleeFrom.name) or nil
                return action
            end
        end

        local authoredAction = self:selectAuthoredChallengeAction(npc, pcs)
        if authoredAction then
            print("[NPC AI] " .. (npc.name or "NPC") .. " uses authored action " ..
                tostring(authoredAction.type))
            return authoredAction
        end

        -- Step 1: targeted greater dooms ride alongside a lesser-doom Attack.
        local attackDoom = self:getAttackGreaterDoom(npc)
        if attackDoom then
            local greaterDoomIndex = self:findGreaterDoom()
            local lesserDoomIndex = self:selectBestLesserActionCard()
            if attackDoom and greaterDoomIndex and lesserDoomIndex then
                local target = self:selectTarget(npc, pcs, true)  -- melee only
                if target then
                    local lesserCard, greaterCard = self:useDoomPair(lesserDoomIndex, greaterDoomIndex)
                    local action = self:createAttackAction(npc, target, lesserCard)
                    action.greaterDoom = attackDoom
                    action.greaterDoomCard = greaterCard
                    return action
                end
            end
        end

        -- Step 2: Try melee attack (same zone only)
        local meleeTarget = self:selectTarget(npc, pcs, true)  -- melee only
        if meleeTarget then
            -- Standard Challenge Actions use lesser dooms.
            local cardIndex = self:selectBestLesserActionCard()
            local card = self:useCard(cardIndex)

            if card then
                print("[NPC AI] " .. (npc.name or "NPC") .. " attacks " .. (meleeTarget.name or "PC") .. " in zone " .. (npc.zone or "?"))
                local action = self:createAttackAction(npc, meleeTarget, card)
                return self:spendGreaterDoomForFavor(action)
            end
        end

        -- Step 3: No melee target - try to move toward a target
        local anyTarget = self:selectTarget(npc, pcs, false)  -- any target
        if anyTarget and anyTarget.zone ~= npc.zone then
            local destinationZone = self:selectMoveDestination(npc, anyTarget.zone)
            if not destinationZone then
                print("[NPC AI] " .. (npc.name or "NPC") .. " has no adjacent movement options")
                return nil
            end

            local cardIndex = self:selectBestActionCard()
            local card = self:useCard(cardIndex)

            if card then
                print("[NPC AI] " .. (npc.name or "NPC") .. " moves from " .. (npc.zone or "?") .. " to " .. destinationZone)
                return self:createMoveAction(npc, destinationZone, card)
            end
        end

        -- No valid action
        print("[NPC AI] " .. (npc.name or "NPC") .. " has no valid targets or movement options")
        return nil
    end

    function ai:isFearDriven(npc)
        local conditions = npc and npc.conditions or {}
        return npc and (npc.mustFleeFrom ~= nil or conditions.inspiredFear == true or conditions.fearful == true)
    end

    function ai:selectFearFleeDestination(npc)
        if not self:isFearDriven(npc) or not npc.zone then
            return nil
        end

        local adjacent = self:getAdjacentZones(npc.zone)
        if #adjacent == 0 then
            return nil
        end

        local source = npc.mustFleeFrom or (npc.emotionalIllusion and npc.emotionalIllusion.cloakedTarget)
        local sourceZone = source and source.zone or nil
        table.sort(adjacent)
        for _, zoneId in ipairs(adjacent) do
            if not sourceZone or zoneId ~= sourceZone then
                return zoneId
            end
        end

        return adjacent[1]
    end

    ----------------------------------------------------------------------------
    -- CARD SELECTION
    ----------------------------------------------------------------------------

    --- S12.6: Find a Greater Doom (15-21) in hand
    -- Greater dooms are potent special cards.
    -- @return number|nil: Index of Greater Doom card, or nil
    function ai:findGreaterDoom()
        for i, card in ipairs(self.hand) do
            if self:isGreaterDoom(card) then
                return i
            end
        end
        return nil
    end

    --- S12.6: Find a Lesser Doom (1-14) in hand
    -- Lesser dooms are used for standard initiative and challenge actions.
    -- @return number|nil: Index of Lesser Doom card, or nil
    function ai:findLesserDoom()
        for i, card in ipairs(self.hand) do
            if self:isLesserDoom(card) then
                return i
            end
        end
        return nil
    end

    --- Select the best card for miscellaneous actions.
    -- Miscellaneous actions can use lesser or greater doom cards.
    -- @return number|nil: Index of best card
    function ai:selectBestActionCard()
        local bestLesserIndex = nil
        local bestLesserValue = -1
        local bestAnyIndex = nil
        local bestValue = 0

        for i, card in ipairs(self.hand) do
            local value = card.value or 0
            if value > bestValue then
                bestValue = value
                bestAnyIndex = i
            end

            if self:isLesserDoom(card) and value > bestLesserValue then
                bestLesserValue = value
                bestLesserIndex = i
            end
        end

        return bestLesserIndex or bestAnyIndex
    end

    --- Select the best card for standard Challenge Actions.
    -- Standard enemy Challenge Actions require lesser doom cards.
    -- @return number|nil: Index of best lesser doom card
    function ai:selectBestLesserActionCard()
        local bestLesserIndex = nil
        local bestLesserValue = -1

        for i, card in ipairs(self.hand) do
            local value = card.value or 0
            if self:isLesserDoom(card) and value > bestLesserValue then
                bestLesserValue = value
                bestLesserIndex = i
            end
        end

        return bestLesserIndex
    end

    --- Select a card matching a specific suit
    -- @param suit number: Suit constant
    -- @return number|nil: Index of matching card, or nil
    function ai:selectCardBySuit(suit)
        for i, card in ipairs(self.hand) do
            if card.suit == suit then
                return i
            end
        end
        return nil
    end

    ----------------------------------------------------------------------------
    -- MOVEMENT HELPERS
    ----------------------------------------------------------------------------

    function ai:getAdjacentZones(zoneId)
        if self.zoneSystem and self.zoneSystem.getAdjacentZones then
            return self.zoneSystem:getAdjacentZones(zoneId)
        end

        local zones = {}
        local allZones = self.challengeController and self.challengeController.zones or {}
        local byId = {}
        for _, zone in ipairs(allZones) do
            byId[zone.id] = zone
        end
        local currentZone = byId[zoneId]

        local function hasAdjacency(zone, targetId)
            if not zone or not zone.adjacent_to then
                return nil
            end
            for _, adjId in ipairs(zone.adjacent_to) do
                if adjId == targetId then
                    return true
                end
            end
            return false
        end

        for _, zone in ipairs(allZones) do
            if zone.id ~= zoneId then
                local adjacent = true
                local fromAdj = hasAdjacency(currentZone, zone.id)
                if fromAdj ~= nil then
                    adjacent = fromAdj
                else
                    local toAdj = hasAdjacency(zone, zoneId)
                    if toAdj ~= nil then
                        adjacent = toAdj
                    end
                end

                if adjacent then
                    zones[#zones + 1] = zone.id
                end
            end
        end
        return zones
    end

    function ai:selectMoveDestination(npc, targetZoneId)
        if not npc or not npc.zone or not targetZoneId or npc.zone == targetZoneId then
            return nil
        end

        local adjacent = self:getAdjacentZones(npc.zone)
        if #adjacent == 0 then
            return nil
        end
        table.sort(adjacent)

        for _, zoneId in ipairs(adjacent) do
            if zoneId == targetZoneId then
                return zoneId
            end
        end

        return adjacent[1]
    end

    ----------------------------------------------------------------------------
    -- TARGET SELECTION
    ----------------------------------------------------------------------------

    --- Select the best target from available PCs
    -- Logic: Target PC with lowest current defense, preferring same zone
    -- @param npc table: The attacking NPC
    -- @param pcs table: Array of PC entities
    -- @param meleeOnly boolean: If true, only return targets in same zone
    -- @return table|nil: Target PC entity
    function ai:selectTarget(npc, pcs, meleeOnly)
        local validTargets = {}

        for _, pc in ipairs(pcs) do
            -- Skip defeated PCs
            if self:isDefeated(pc) then
                goto continue
            end

            -- Check zone (for melee, must be in same zone)
            local inRange = (npc.zone == pc.zone)

            -- If meleeOnly, skip out-of-range targets
            if meleeOnly and not inRange then
                goto continue
            end

            validTargets[#validTargets + 1] = {
                pc = pc,
                inRange = inRange,
                defense = self:calculateDefense(pc),
            }

            ::continue::
        end

        if #validTargets == 0 then
            return nil
        end

        if self:isWraith(npc) then
            local unlitTargets = {}
            for _, target in ipairs(validTargets) do
                if not self:targetCarriesVisibleLightSource(target.pc) then
                    unlitTargets[#unlitTargets + 1] = target
                end
            end
            if #unlitTargets > 0 then
                validTargets = unlitTargets
            end
        end

        if self:isDogLike(npc) then
            local cursedTargets = {}
            for _, target in ipairs(validTargets) do
                if self:targetHasDogCurse(target.pc) then
                    cursedTargets[#cursedTargets + 1] = target
                end
            end
            if #cursedTargets > 0 then
                table.sort(cursedTargets, function(a, b)
                    if a.inRange ~= b.inRange then
                        return a.inRange
                    end
                    return a.defense < b.defense
                end)
                return cursedTargets[1].pc
            end
        end

        local priorityTargets = nil
        if self:isUndead(npc) then
            priorityTargets = {}
            for _, target in ipairs(validTargets) do
                if self:targetHasUndeadMark(target.pc) then
                    priorityTargets[#priorityTargets + 1] = target
                end
            end
        elseif self:isSpirit(npc) then
            priorityTargets = {}
            for _, target in ipairs(validTargets) do
                if self:targetHasHalo(target.pc) then
                    priorityTargets[#priorityTargets + 1] = target
                end
            end
        end

        if priorityTargets and #priorityTargets > 0 then
            table.sort(priorityTargets, function(a, b)
                if a.inRange ~= b.inRange then
                    return a.inRange
                end
                return a.defense < b.defense
            end)
            return priorityTargets[1].pc
        end

        if npc.recklessAttackTarget then
            local targetKey = npc.recklessAttackTarget.id or npc.recklessAttackTarget.name
            for _, target in ipairs(validTargets) do
                if target.pc == npc.recklessAttackTarget or target.pc.id == targetKey or target.pc.name == targetKey then
                    return target.pc
                end
            end
        end

        if self:isUndead(npc) then
            local undeadVisibleTargets = {}
            for _, target in ipairs(validTargets) do
                if not self:targetIsIgnoredByUndead(target.pc) then
                    undeadVisibleTargets[#undeadVisibleTargets + 1] = target
                end
            end
            if #undeadVisibleTargets > 0 then
                validTargets = undeadVisibleTargets
            end
        end

        -- Sort by defense (lowest first)
        table.sort(validTargets, function(a, b)
            return a.defense < b.defense
        end)

        -- Prefer in-range targets
        for _, target in ipairs(validTargets) do
            if target.inRange then
                return target.pc
            end
        end

        -- Fall back to any target (only if not meleeOnly)
        if not meleeOnly then
            return validTargets[1].pc
        end

        return nil
    end

    --- Calculate a PC's current defense value
    function ai:calculateDefense(pc)
        local defense = 10

        -- Base defense from Pentacles
        defense = defense + (pc.pentacles or 0)

        -- Armor bonus
        if pc.armorNotches and pc.armorNotches > 0 then
            defense = defense + 2
        end

        -- Wounded penalty
        if pc.conditions then
            if pc.conditions.staggered then
                defense = defense - 1
            end
            if pc.conditions.injured then
                defense = defense - 2
            end
            if pc.conditions.deaths_door then
                defense = defense - 4
            end
        end

        return defense
    end

    ----------------------------------------------------------------------------
    -- ACTION CREATION
    ----------------------------------------------------------------------------

    --- Create an attack action
    function ai:createAttackAction(npc, target, card)
        local action = {
            actor = npc,
            target = target,
            card = card,
            type = action_resolver.ACTION_TYPES.MELEE,
            weapon = (npc.inventory and npc.inventory:getWieldedWeapon()) or { name = "Claws", isMelee = true },
            allEntities = self.challengeController and self.challengeController.allCombatants,
        }

        -- Check for mob rule bonuses
        local mobBonus = self:checkMobRule(npc, target)
        if mobBonus then
            action.mobRuleBonus = mobBonus
            if mobBonus.favor then
                action.favor = true
            end
        end

        return action
    end

    --- Create a move action
    function ai:createMoveAction(npc, destinationZone, card)
        local action = {
            actor = npc,
            card = card,
            type = action_resolver.ACTION_TYPES.MOVE,
            destinationZone = destinationZone,
            allEntities = self.challengeController and self.challengeController.allCombatants,
        }
        return action
    end

    ----------------------------------------------------------------------------
    -- S12.7: MOB RULE (SWARM BONUSES)
    -- When multiple mobs target the same adventurer, they gain bonuses:
    -- - Favor (advantage) at 2+ attackers
    -- - Favor and Piercing damage at 4+ attackers
    -- - Favor and Critical damage at 8+ attackers
    ----------------------------------------------------------------------------

    --- Check for Mob Rule (swarm) bonuses
    -- @param npc table: The attacking NPC
    -- @param target table: The target being attacked
    -- @return table|nil: Bonus info { favor, piercing, critical, alliesCount, attackersCount }
    function ai:checkMobRule(npc, target)
        local alliesInZone = 0

        if self.challengeController then
            local npcs = self.challengeController.npcs or {}
            for _, otherNpc in ipairs(npcs) do
                if otherNpc ~= npc and otherNpc.zone == target.zone then
                    if not (otherNpc.conditions and otherNpc.conditions.dead) then
                        alliesInZone = alliesInZone + 1
                    end
                end
            end
        end

        local attackersCount = alliesInZone + 1
        if attackersCount >= 2 then
            return {
                favor = true,
                piercing = attackersCount >= 4,
                critical = attackersCount >= 8,
                alliesCount = alliesInZone,
                attackersCount = attackersCount,
            }
        end

        return nil
    end

    --- S12.7: Get count of NPCs engaged with a specific target
    -- Used for tracking swarm attacks within a round
    function ai:getAttackersOnTarget(target)
        if not self.challengeController then return 0 end

        local count = 0
        local npcs = self.challengeController.npcs or {}
        for _, npc in ipairs(npcs) do
            if npc.zone == target.zone then
                if not (npc.conditions and npc.conditions.dead) then
                    count = count + 1
                end
            end
        end
        return count
    end

    ----------------------------------------------------------------------------
    -- SPECIAL AI BEHAVIORS
    ----------------------------------------------------------------------------

    --- Check if NPC should flee (low morale)
    function ai:shouldFlee(npc)
        if npc.morale and npc.morale <= 0 then
            return true
        end
        if npc.conditions and npc.conditions.fleeing then
            return true
        end
        return false
    end

    --- Check if NPC should use a special ability
    function ai:shouldUseSpecial(npc, pcs)
        -- Bosses with special abilities would check here
        if npc.specialAbility and npc.specialAbilityCooldown == 0 then
            -- 50% chance to use special
            return math.random() > 0.5
        end
        return false
    end

    return ai
end

return M
