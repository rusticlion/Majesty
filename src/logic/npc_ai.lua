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
        end)

        -- Draw a fresh hand at the start of each round.
        self.eventBus:on("initiative_phase_start", function(data)
            self:refreshRoundHand(data and data.round)
        end)

        -- Listen for challenge end to discard hand
        self.eventBus:on(events.EVENTS.CHALLENGE_END, function(data)
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
            print("[NPC AI] " .. (npc.name or "NPC") .. " chose initiative: " .. (card.name or "?") .. " (value " .. (card.value or 0) .. ")")

            -- Submit to challenge controller
            if self.challengeController then
                self.challengeController:submitInitiative(npc, card)
            end
        end
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
        return entity.conditions and entity.conditions.dead
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

    function ai:hasAnyLesserDoom()
        for _, card in ipairs(self.hand) do
            if self:isLesserDoom(card) then
                return true
            end
        end
        return false
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

        -- Challenge controller currently asks each NPC to submit initiative
        -- individually. Keep a minimum so every living NPC can contribute one card.
        drawCount = math.max(drawCount, #livingNPCs)

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
            self.eventBus:emit(events.EVENTS.UI_SEQUENCE_COMPLETE, {})
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

        local rank = npc.rank or M.RANKS.SOLDIER

        -- Step 1: Elite/Lord attempt a greater doom play first.
        if rank == M.RANKS.ELITE or rank == M.RANKS.LORD then
            local greaterDoomIndex = self:findGreaterDoom()
            if greaterDoomIndex then
                local target = self:selectTarget(npc, pcs, true)  -- melee only
                if target then
                    local card = self:useCard(greaterDoomIndex)
                    local action = self:createAttackAction(npc, target, card)
                    action.isGreaterDoom = true
                    return action
                end
            end
        end

        -- Step 2: Try melee attack (same zone only)
        local meleeTarget = self:selectTarget(npc, pcs, true)  -- melee only
        if meleeTarget then
            -- Select best challenge-action card (prefer lesser doom).
            local cardIndex = self:selectBestActionCard()
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

    --- Select the best card for normal challenge actions.
    -- Prefers highest lesser doom; falls back to highest card if needed.
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
            if pc.conditions and pc.conditions.dead then
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
