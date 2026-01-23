-- npc_ai.lua
-- NPC "Dread" AI System for Majesty
-- Ticket S4.5: Basic NPC decision-making for challenges
--
-- AI Decision Logic:
-- 1. Elite/Lord NPCs with Greater Doom (15-21) use it immediately
-- 2. Otherwise, attack the PC with lowest current defense
-- 3. Mob Rule: NPCs in same zone get Favor/Piercing bonuses
--
-- This is intentionally simple - NPCs should feel dangerous but fair.

local events = require('logic.events')
local constants = require('constants')
local action_resolver = require('logic.action_resolver')

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
-- Greater Doom: Major Arcana 1-14 (Magician through Temperance) - Standard NPC cards
-- Lesser Doom:  Major Arcana 15-21 (Devil through World) - Powerful special cards
--
-- Elite/Lord NPCs can use Lesser Dooms for devastating attacks
--------------------------------------------------------------------------------
local GREATER_DOOM_MAX = 14  -- Cards 1-14 are Greater Doom (common)
local LESSER_DOOM_MIN = 15   -- Cards 15-21 are Lesser Doom (powerful)

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
        handSize = 3,  -- NPCs typically have access to 3 cards
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

        -- Listen for challenge start to draw initial hand
        self.eventBus:on(events.EVENTS.CHALLENGE_START, function(data)
            self:drawHand()
        end)

        -- Listen for challenge end to discard hand
        self.eventBus:on(events.EVENTS.CHALLENGE_END, function(data)
            self:discardHand()
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

        -- Ensure we have cards
        if #self.hand == 0 then
            self:drawHand()
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

        -- Sort hand by value for easier selection
        local sorted = {}
        for i, card in ipairs(self.hand) do
            sorted[#sorted + 1] = { index = i, value = card.value or 0 }
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

    --- Draw cards into GM hand
    function ai:drawHand()
        self.hand = {}
        if not self.gmDeck then return end

        for _ = 1, self.handSize do
            local card = self.gmDeck:draw()
            if card then
                self.hand[#self.hand + 1] = card
            end
        end
    end

    --- Discard all cards in hand
    function ai:discardHand()
        if not self.gmDeck then return end

        for _, card in ipairs(self.hand) do
            self.gmDeck:discard(card)
        end
        self.hand = {}
    end

    --- Draw a single card (after using one)
    function ai:drawCard()
        if not self.gmDeck then return nil end
        local card = self.gmDeck:draw()
        if card then
            self.hand[#self.hand + 1] = card
        end
        return card
    end

    --- Use a card from hand (remove and return it)
    function ai:useCard(index)
        if index and index <= #self.hand then
            local card = table.remove(self.hand, index)
            if self.gmDeck then
                self.gmDeck:discard(card)
            end
            -- Draw replacement
            self:drawCard()
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
            self:drawHand()
        end

        if #self.hand == 0 then
            return nil  -- No cards available
        end

        local rank = npc.rank or M.RANKS.SOLDIER

        -- Step 1: Check for Lesser Doom usage (Elite/Lord only)
        -- S12.6: Lesser Doom (15-21) are the powerful devastating cards
        if rank == M.RANKS.ELITE or rank == M.RANKS.LORD then
            local lesserDoomIndex = self:findLesserDoom()
            if lesserDoomIndex then
                local target = self:selectTarget(npc, pcs, true)  -- melee only
                if target then
                    local card = self:useCard(lesserDoomIndex)
                    -- Mark this as a Lesser Doom attack for special effects
                    local action = self:createAttackAction(npc, target, card)
                    action.isLesserDoom = true
                    return action
                end
            end
        end

        -- Step 2: Try melee attack (same zone only)
        local meleeTarget = self:selectTarget(npc, pcs, true)  -- melee only
        if meleeTarget then
            -- Select best card for attack (highest value)
            local cardIndex = self:selectBestCard()
            local card = self:useCard(cardIndex)

            if card then
                print("[NPC AI] " .. (npc.name or "NPC") .. " attacks " .. (meleeTarget.name or "PC") .. " in zone " .. (npc.zone or "?"))
                return self:createAttackAction(npc, meleeTarget, card)
            end
        end

        -- Step 3: No melee target - try to move toward a target
        local anyTarget = self:selectTarget(npc, pcs, false)  -- any target
        if anyTarget and anyTarget.zone ~= npc.zone then
            -- Move toward the target's zone
            local cardIndex = self:selectBestCard()
            local card = self:useCard(cardIndex)

            if card then
                print("[NPC AI] " .. (npc.name or "NPC") .. " moves from " .. (npc.zone or "?") .. " to " .. (anyTarget.zone or "?"))
                return self:createMoveAction(npc, anyTarget.zone, card)
            end
        end

        -- No valid action
        print("[NPC AI] " .. (npc.name or "NPC") .. " has no valid targets or movement options")
        return nil
    end

    ----------------------------------------------------------------------------
    -- CARD SELECTION
    ----------------------------------------------------------------------------

    --- S12.6: Find a Greater Doom (1-14) in hand
    -- Greater Dooms are the standard Major Arcana cards for NPC actions
    -- @return number|nil: Index of Greater Doom card, or nil
    function ai:findGreaterDoom()
        for i, card in ipairs(self.hand) do
            if card.is_major and card.value >= 1 and card.value <= GREATER_DOOM_MAX then
                return i
            end
        end
        return nil
    end

    --- S12.6: Find a Lesser Doom (15-21) in hand
    -- Lesser Dooms are powerful cards, only Elite/Lord NPCs use them aggressively
    -- @return number|nil: Index of Lesser Doom card, or nil
    function ai:findLesserDoom()
        for i, card in ipairs(self.hand) do
            if card.is_major and card.value >= LESSER_DOOM_MIN then
                return i
            end
        end
        return nil
    end

    --- Select the best card for an attack
    -- @return number: Index of best card (highest value)
    function ai:selectBestCard()
        local bestIndex = 1
        local bestValue = 0

        for i, card in ipairs(self.hand) do
            local value = card.value or 0
            if value > bestValue then
                bestValue = value
                bestIndex = i
            end
        end

        return bestIndex
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

        -- Defensive stance
        if pc.conditions and pc.conditions.defending then
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
