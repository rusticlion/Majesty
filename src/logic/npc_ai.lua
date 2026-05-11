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

local M = {}

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
            self:discardHand()
            self.roundInitiativeCards = {}
        end)

        -- Listen for challenge end to discard hand
        self.eventBus:on(events.EVENTS.CHALLENGE_END, function(data)
            self:discardHand()
            self.lastPreparedRound = nil
            self.roundInitiativeCards = {}
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
        local card = self:useCard(cardIndex)

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
        if npc.mustPlayLowestInitiative or npc.brainfever or conditions.brainfever then
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
        for _, npc in ipairs(livingNPCs) do
            drawPenalty = drawPenalty + math.max(0, npc.stinkingCloudDrawPenalty or npc.challengeDrawPenalty or 0)
        end
        drawCount = drawCount - drawPenalty

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

        if #self.hand > 0 and not self:hasAnyLesserDoom() then
            print("[NPC AI] Mulliganing hand (no lesser dooms).")
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
        if not self.gmDeck then return end

        for _, card in ipairs(self.hand) do
            self.gmDeck:discard(card)
        end
        self.hand = {}
    end

    --- Use a card from hand (remove and return it)
    function ai:useCard(index)
        if index and index <= #self.hand then
            local card = table.remove(self.hand, index)
            if self.gmDeck then
                self.gmDeck:discard(card)
            end
            return card
        end
        return nil
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
                return self:createAttackAction(npc, meleeTarget, card)
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
    -- - +1 to hit per additional attacker in same zone
    -- - Piercing damage at 3+ attackers
    -- - Favor (advantage) at 2+ attackers
    ----------------------------------------------------------------------------

    --- Check for Mob Rule (swarm) bonuses
    -- @param npc table: The attacking NPC
    -- @param target table: The target being attacked
    -- @return table|nil: Bonus info { favor, piercing, attackBonus, alliesCount }
    function ai:checkMobRule(npc, target)
        -- Count other NPCs in the same zone as the target (surrounding them)
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

        if alliesInZone > 0 then
            return {
                -- S12.7: Swarm bonuses scale with number of attackers
                attackBonus = alliesInZone,          -- +1 per additional attacker
                favor = alliesInZone >= 1,           -- Favor at 2+ total (self + 1)
                piercing = alliesInZone >= 2,        -- Piercing at 3+ total (self + 2)
                alliesCount = alliesInZone,
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
