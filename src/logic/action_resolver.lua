-- action_resolver.lua
-- Challenge Action Resolution for Majesty
-- Ticket S4.4: Maps suits to mechanical effects
--
-- Suits and their actions:
-- - SWORDS: Melee (requires engagement), Missile (bypasses engagement)
-- - PENTACLES: Roughhouse (Trip, Disarm, Displace)
-- - CUPS: Support, healing, social
-- - WANDS: Banter (attacks Morale), magic
--
-- Great Success (face cards on matching suit) triggers weapon bonuses

local events = require('logic.events')
local disposition_module = require('logic.disposition')
local constants = require('constants')
local action_registry = require('data.action_registry')

local M = {}

--------------------------------------------------------------------------------
-- ACTION TYPES
--------------------------------------------------------------------------------
M.ACTION_TYPES = {
    -- Swords
    MELEE      = "melee",       -- Requires engagement
    MISSILE    = "missile",     -- Bypasses engagement, ammo cost

    -- Pentacles
    TRIP       = "trip",        -- Knock prone
    DISARM     = "disarm",      -- Remove weapon
    DISPLACE   = "displace",    -- Push to different zone
    GRAPPLE    = "grapple",     -- Establish grapple

    -- Cups
    COMMAND    = "command",     -- Command companion actions
    HEAL       = "heal",        -- Healing action
    PARLEY     = "parley",      -- Social extension
    RALLY      = "rally",       -- Social extension
    SHIELD     = "shield",      -- Protect another
    AID        = "aid",         -- S7.1: Aid Another (bank bonus for ally)

    -- Wands
    BANTER     = "banter",      -- Attack morale
    SPEAK_INCANTATION = "speak_incantation", -- Rulebook spellcasting action
    CAST       = "cast",        -- Legacy alias for Speak Incantation
    RECOVER    = "recover",     -- S7.4: Clear negative status effects

    -- Special
    FLEE       = "flee",        -- Attempt to escape
    MOVE       = "move",        -- Change zone
    USE_ITEM   = "use_item",    -- Use an item
    PULL_ITEM  = "pull_item",   -- Pull item from pack
    PULL_ITEM_BELT = "pull_item_belt", -- Pull item from belt
    INTERACT   = "interact",    -- Environment interaction
    BID_LORE   = "bid_lore",    -- Misc rules lookup action
    GUARD      = "guard",       -- Replace initiative if shielded
    TEST_FATE  = "test_fate",   -- Mid-challenge test of fate trigger
    TRIVIAL_ACTION = "trivial_action", -- Simple uncontested action
    VIGILANCE  = "vigilance",   -- Prepared triggered response

    -- Defensive Actions (S4.9)
    DODGE      = "dodge",       -- Adds card value to defense difficulty
    RIPOSTE    = "riposte",     -- Counter-attack when attacked

    -- Interrupt Actions (S4.9)
    FOOL_INTERRUPT = "fool_interrupt",  -- The Fool: take immediate action out of turn

    -- Engagement Actions (S6.3)
    AVOID      = "avoid",       -- Escape engagement without parting blows
    DASH       = "dash",        -- Quick move (subject to parting blows)

    -- S7.8: Ammunition
    RELOAD     = "reload",      -- Reload a crossbow
}

M.ACTION_ALIASES = {
    cast = M.ACTION_TYPES.SPEAK_INCANTATION,
}

--------------------------------------------------------------------------------
-- S7.6: WEAPON TYPES (for specialization logic)
--------------------------------------------------------------------------------
M.WEAPON_TYPES = {
    -- Blades: Riposte deals 2 damage
    BLADE   = { "sword", "dagger", "axe" },
    -- Hammers: Double damage threshold
    HAMMER  = { "mace", "hammer", "staff" },
    -- Daggers: Piercing vs vulnerable targets
    DAGGER  = { "dagger" },
    -- Flails: Ties count as success
    FLAIL   = { "flail" },
    -- Axes: Cleave on defeat
    AXE     = { "axe" },
    -- Ranged
    BOW     = { "bow" },
    CROSSBOW = { "crossbow" },
}

--------------------------------------------------------------------------------
-- WEAPON TYPES & GREAT SUCCESS BONUSES
--------------------------------------------------------------------------------
M.WEAPON_BONUSES = {
    -- Blade weapons: +1 wound on Great Success
    sword       = { great_bonus = "extra_wound", wound_bonus = 1 },
    dagger      = { great_bonus = "extra_wound", wound_bonus = 1 },
    axe         = { great_bonus = "extra_wound", wound_bonus = 1 },

    -- Blunt weapons: Stagger on Great Success
    mace        = { great_bonus = "stagger" },
    hammer      = { great_bonus = "stagger" },
    staff       = { great_bonus = "stagger" },

    -- Piercing weapons: Ignore armor on Great Success
    spear       = { great_bonus = "pierce_armor" },
    pike        = { great_bonus = "pierce_armor" },

    -- Ranged weapons
    bow         = { great_bonus = "extra_wound", wound_bonus = 1, uses_ammo = true },
    crossbow    = { great_bonus = "pierce_armor", uses_ammo = true },
    thrown      = { great_bonus = "extra_wound", wound_bonus = 1, uses_ammo = true },
}

--------------------------------------------------------------------------------
-- THE FOOL HELPER (S4.9)
--------------------------------------------------------------------------------

--- Check if a card is The Fool
-- @param card table: Card to check
-- @return boolean: true if card is The Fool
function M.isFool(card)
    if not card then return false end
    return card.name == "The Fool" or (card.is_major and card.value == 0)
end

--------------------------------------------------------------------------------
-- S7.6: WEAPON TYPE HELPERS
--------------------------------------------------------------------------------

--- Check if a weapon is of a specific category
-- @param weapon table: Weapon to check
-- @param category string: Category key from WEAPON_TYPES
-- @return boolean
function M.isWeaponType(weapon, category)
    if not weapon then return false end
    local weaponType = (weapon.type or weapon.name or ""):lower()
    local types = M.WEAPON_TYPES[category]
    if not types then return false end

    for _, t in ipairs(types) do
        if weaponType == t or weaponType:find(t) then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- ACTION RESOLVER FACTORY
--------------------------------------------------------------------------------

--- Create a new ActionResolver
-- @param config table: { eventBus, zoneSystem }
-- @return ActionResolver instance
function M.createActionResolver(config)
    config = config or {}

    local resolver = {
        eventBus   = config.eventBus or events.globalBus,
        zoneSystem = config.zoneSystem,
        challengeController = config.challengeController,
        -- S12.1: Engagements now tracked by zoneSystem (zone_system.lua)
        -- The zoneSystem is the single source of truth for engagement state
        -- S7.1: Track active aids { [targetId] = { val = bonus, source = actorName } }
        activeAids = {},
        vigilanceCounter = 0, -- Monotonic order for deterministic vigilance trigger ordering
    }

    ----------------------------------------------------------------------------
    -- S12.2: ACTION VALIDATION
    ----------------------------------------------------------------------------

    --- Check if an actor can perform a given action
    -- @param actor table: The acting entity
    -- @param actionType string: The action type (e.g., "missile")
    -- @param actionDef table: Optional action definition from action_registry
    -- @return boolean, string: can perform, reason if blocked
    function resolver:canPerformAction(actor, actionType, actionDef)
        if not actor then return false, "No actor" end
        actionType = self:normalizeActionType(actionType)

        -- S12.2: Check ranged restriction when engaged
        local isRanged = actionType == M.ACTION_TYPES.MISSILE
        if actionDef and actionDef.isRanged then
            isRanged = true
        end

        if isRanged and self:hasAnyEngagement(actor) then
            return false, "Cannot use ranged weapons while engaged"
        end

        if actionDef then
            local requirementsOk, requirementReason = action_registry.checkActionRequirements(actionDef, actor)
            if not requirementsOk then
                return false, requirementReason or "Action requirements not met"
            end
        end

        return true, nil
    end

    ----------------------------------------------------------------------------
    -- ACTION HELPERS
    ----------------------------------------------------------------------------

    local actionSuitToCardSuit = {
        [action_registry.SUITS.SWORDS]    = constants.SUITS.SWORDS,
        [action_registry.SUITS.PENTACLES] = constants.SUITS.PENTACLES,
        [action_registry.SUITS.CUPS]      = constants.SUITS.CUPS,
        [action_registry.SUITS.WANDS]     = constants.SUITS.WANDS,
    }

    function resolver:getActionDef(action)
        if not action then return nil end
        if action.actionDef then return action.actionDef end
        if action.type then
            return action_registry.getAction(action.type)
        end
        return nil
    end

    function resolver:normalizeActionType(actionType)
        if not actionType then
            return actionType
        end
        return M.ACTION_ALIASES[actionType] or actionType
    end

    function resolver:usesCardValueOnly(action)
        if not action then return false end
        if action.isMinorAction then return true end
        local actionType = self:normalizeActionType(action.type)
        if actionType == M.ACTION_TYPES.DODGE or actionType == M.ACTION_TYPES.RIPOSTE then
            return true
        end
        return false
    end

    function resolver:getActionModifier(action, actionDef)
        if not action or not action.actor then return 0 end
        if self:usesCardValueOnly(action) then return 0 end

        if actionDef and actionDef.attribute then
            return action.actor[actionDef.attribute] or 0
        end

        -- Fallback for unknown actions: use card suit stat
        if not actionDef and action.card and action.card.suit then
            return self:getStatModifier(action.actor, action.card.suit)
        end

        return 0
    end

    function resolver:isInitiativeOpposed(actionType)
        actionType = self:normalizeActionType(actionType)
        return actionType == M.ACTION_TYPES.MELEE or
               actionType == M.ACTION_TYPES.MISSILE or
               actionType == M.ACTION_TYPES.TRIP or
               actionType == M.ACTION_TYPES.DISARM or
               actionType == M.ACTION_TYPES.DISPLACE or
               actionType == M.ACTION_TYPES.GRAPPLE or
               actionType == M.ACTION_TYPES.SPEAK_INCANTATION or
               actionType == M.ACTION_TYPES.COMMAND or
               actionType == M.ACTION_TYPES.USE_ITEM
    end

    function resolver:getTargetInitiative(target, action)
        if not target then return nil end
        if action and action.targetInitiative then
            return action.targetInitiative
        end

        local controller = (action and action.challengeController) or self.challengeController
        if controller and controller.getInitiativeSlot then
            local slot = controller:getInitiativeSlot(target.id)
            if slot then
                if not slot.revealed then
                    slot.revealed = true
                    self.eventBus:emit(events.EVENTS.INITIATIVE_REVEALED, {
                        entity = target,
                    })
                end
                return slot.value or (slot.card and slot.card.value) or nil
            end
        end

        return nil
    end

    function resolver:entityHasShield(entity)
        if not entity or not entity.inventory or not entity.inventory.getItems then
            return false
        end

        local hands = entity.inventory:getItems("hands") or {}
        for _, item in ipairs(hands) do
            local props = item.properties
            if props and props.tags then
                for _, tag in ipairs(props.tags) do
                    if tag == "shield" then
                        return true
                    end
                end
            end
        end

        return false
    end

    function resolver:requestTestOfFate(action, actionDef, result)
        local suitKey = actionDef and actionDef.suit or nil
        local targetSuit = suitKey and actionSuitToCardSuit[suitKey] or nil

        self.eventBus:emit(events.EVENTS.REQUEST_TEST_OF_FATE, {
            entity = action.actor,
            attribute = (actionDef and actionDef.attribute) or "pentacles",
            targetSuit = targetSuit,
            description = actionDef and actionDef.name or "Test of Fate",
        })

        result.pendingTestOfFate = true
        result.description = "Test of Fate underway."
        action.result = result

        return result
    end

    function resolver:resolveTestOfFateOutcome(action, testResult)
        local result = {
            success = testResult and testResult.success or false,
            isGreat = testResult and testResult.isGreat or false,
            damageDealt = 0,
            effects = {},
            description = "",
            testOfFate = true,
            testResult = testResult,
        }

        if result.success then
            result.description = "Test of Fate succeeded."
        else
            result.description = "Test of Fate failed."
        end

        action.result = result
        return result
    end

    function resolver:resolveInitiativeContest(action, result, options)
        options = options or {}
        local target = action.target

        if not target then
            result.success = false
            result.description = "No target!"
            return { success = false }
        end

        local attackValue = result.testValue
        local baseInitiative = self:getTargetInitiative(target, action) or result.difficulty
        local tieWins = options.tieWins or false
        local considerShield = options.considerShield or false
        local defenderHasShield = considerShield and self:entityHasShield(target) or false

        local riposteTriggered = false
        local riposteDefense = nil

        if target.hasDefense and target:hasDefense() then
            local defense = target:getDefense()
            if defense then
                if defense.type == "dodge" then
                    target:consumeDefense()
                    local dodgeValue = defense.value or 0
                    local newInitiative = baseInitiative + dodgeValue
                    result.effects[#result.effects + 1] = "dodge_used"

                    if newInitiative > attackValue then
                        result.success = false
                        result.description = "Dodged! "
                        result.effects[#result.effects + 1] = "dodged"
                        return {
                            success = false,
                            dodged = true,
                            attackValue = attackValue,
                            baseInitiative = baseInitiative,
                        }
                    else
                        result.effects[#result.effects + 1] = "dodge_failed"
                    end
                elseif defense.type == "riposte" then
                    riposteTriggered = true
                    riposteDefense = target:consumeDefense()
                    result.effects[#result.effects + 1] = "riposte_ready"
                end
            end
        end

        result.success = (attackValue > baseInitiative) or
                         (tieWins and attackValue == baseInitiative and not defenderHasShield)
        result.difficulty = baseInitiative

        return {
            success = result.success,
            attackValue = attackValue,
            baseInitiative = baseInitiative,
            riposteTriggered = riposteTriggered,
            riposteDefense = riposteDefense,
        }
    end

    ----------------------------------------------------------------------------
    -- MAIN RESOLUTION ENTRY POINT
    ----------------------------------------------------------------------------

    --- Resolve an action
    -- @param action table: { actor, target, type, card, weapon, ... }
    -- @return table: { success, isGreat, damageDealt, effects, description }
    function resolver:resolve(action)
        local result = {
            success = false,
            isGreat = false,
            damageDealt = 0,
            effects = {},
            description = "",
            cardValue = 0,
            modifier = 0,
            testValue = 0,
            difficulty = 10,
        }

        if not action.actor or not action.card then
            result.description = "Invalid action"
            return result
        end

        -- S12.2: Pre-resolution validation
        local canPerform, blockReason = self:canPerformAction(action.actor, action.type, action.actionDef)
        if not canPerform then
            result.success = false
            result.description = blockReason or "Action blocked"
            result.effects[#result.effects + 1] = "action_blocked"

            -- Emit blocked event
            self.eventBus:emit("action_blocked", {
                actor = action.actor,
                actionType = action.type,
                reason = blockReason,
            })

            return result
        end

        -- Get card info
        local card = action.card
        result.cardValue = card.value or 0
        local suit = card.suit

        -- Cache action definition for suit/attribute logic
        local actionDef = self:getActionDef(action)
        if actionDef then
            action.actionDef = actionDef
        end

        -- S4.9: Check for The Fool interrupt
        if M.isFool(card) then
            return self:resolveFoolInterrupt(action, result)
        end

        -- S7.x: Non-combat actions during Challenges can trigger Test of Fate
        local controller = action.challengeController or self.challengeController
        if actionDef and actionDef.testOfFate and controller and controller.isActive and controller:isActive() then
            return self:requestTestOfFate(action, actionDef, result)
        end

        -- Calculate modifier from action's associated attribute (or card-only rules)
        local statMod = self:getActionModifier(action, actionDef)
        result.modifier = statMod

        -- Total test value
        result.testValue = result.cardValue + result.modifier

        -- Get difficulty (target's defense or fixed value)
        result.difficulty = self:getDifficulty(action, actionDef)

        -- Check for success
        result.success = result.testValue >= result.difficulty

        -- Check for Great Success (face card matching suit)
        result.isGreat = self:isGreatSuccess(card, action.actor)

        -- Route to specific resolution based on ACTION TYPE (not card suit)
        -- This allows using any card for any action on primary turns
        local actionType = self:normalizeActionType(action.type or "generic")
        action.normalizedType = actionType

        -- Swords actions (combat)
        if actionType == M.ACTION_TYPES.MELEE or actionType == M.ACTION_TYPES.MISSILE then
            self:resolveSwordsAction(action, result)
        -- Pentacles actions (agility/technical)
        elseif actionType == M.ACTION_TYPES.TRIP or actionType == M.ACTION_TYPES.DISARM or
               actionType == M.ACTION_TYPES.DISPLACE or actionType == M.ACTION_TYPES.GRAPPLE or
               actionType == M.ACTION_TYPES.AVOID or actionType == M.ACTION_TYPES.DASH then
            self:resolvePentaclesAction(action, result)
        -- Cups actions (defense/social)
        elseif actionType == M.ACTION_TYPES.DODGE or actionType == M.ACTION_TYPES.RIPOSTE or
               actionType == M.ACTION_TYPES.HEAL or actionType == M.ACTION_TYPES.SHIELD or
               actionType == M.ACTION_TYPES.AID or actionType == M.ACTION_TYPES.COMMAND or
               actionType == M.ACTION_TYPES.PARLEY or actionType == M.ACTION_TYPES.RALLY or
               actionType == M.ACTION_TYPES.PULL_ITEM or actionType == M.ACTION_TYPES.USE_ITEM then
            self:resolveCupsAction(action, result)
        -- Wands actions (magic/perception)
        elseif actionType == M.ACTION_TYPES.BANTER or actionType == M.ACTION_TYPES.SPEAK_INCANTATION or
               actionType == M.ACTION_TYPES.RECOVER then
            self:resolveWandsAction(action, result)
        -- Movement and misc
        elseif actionType == M.ACTION_TYPES.MOVE then
            self:resolveMove(action, result, action.allEntities)
        elseif actionType == M.ACTION_TYPES.GUARD then
            self:resolveGuard(action, result)
        elseif actionType == M.ACTION_TYPES.VIGILANCE then
            self:resolveVigilance(action, result)
        elseif actionType == M.ACTION_TYPES.FLEE then
            self:resolveGenericAction(action, result)
        elseif actionType == M.ACTION_TYPES.BID_LORE or
               actionType == M.ACTION_TYPES.PULL_ITEM_BELT or
               actionType == M.ACTION_TYPES.TRIVIAL_ACTION or
               actionType == M.ACTION_TYPES.TEST_FATE or
               actionType == M.ACTION_TYPES.INTERACT then
            self:resolveGenericAction(action, result)
        elseif actionType == M.ACTION_TYPES.RELOAD then
            -- S7.8: Reload crossbow
            self:resolveReload(action, result)
        else
            -- Unknown action type - fall back to action definition suit when available
            local fallbackSuit = actionDef and actionDef.suit

            if fallbackSuit == action_registry.SUITS.SWORDS then
                self:resolveSwordsAction(action, result)
            elseif fallbackSuit == action_registry.SUITS.PENTACLES then
                self:resolvePentaclesAction(action, result)
            elseif fallbackSuit == action_registry.SUITS.CUPS then
                self:resolveCupsAction(action, result)
            elseif fallbackSuit == action_registry.SUITS.WANDS then
                self:resolveWandsAction(action, result)
            elseif suit == constants.SUITS.SWORDS then
                self:resolveSwordsAction(action, result)
            elseif suit == constants.SUITS.PENTACLES then
                self:resolvePentaclesAction(action, result)
            elseif suit == constants.SUITS.CUPS then
                self:resolveCupsAction(action, result)
            elseif suit == constants.SUITS.WANDS then
                self:resolveWandsAction(action, result)
            else
                self:resolveGenericAction(action, result)
            end
        end

        -- Attach result to action for event emission
        action.result = result

        return result
    end

    ----------------------------------------------------------------------------
    -- STAT MODIFIER CALCULATION
    ----------------------------------------------------------------------------

    --- Get the stat modifier for a given suit
    function resolver:getStatModifier(entity, suit)
        if not entity then return 0 end

        if suit == constants.SUITS.SWORDS then
            return entity.swords or 0
        elseif suit == constants.SUITS.PENTACLES then
            return entity.pentacles or 0
        elseif suit == constants.SUITS.CUPS then
            return entity.cups or 0
        elseif suit == constants.SUITS.WANDS then
            return entity.wands or 0
        end

        return 0
    end

    ----------------------------------------------------------------------------
    -- S7.1: AID ANOTHER SYSTEM
    ----------------------------------------------------------------------------

    --- Apply any active aids to an actor's result
    -- @param actor table: The acting entity
    -- @param result table: Result to modify
    function resolver:applyActiveAids(actor, result)
        if not actor or not actor.id then return end

        local aid = self.activeAids[actor.id]
        if aid then
            result.modifier = (result.modifier or 0) + aid.val
            result.testValue = result.cardValue + result.modifier
            result.description = (result.description or "") .. "(Aided by " .. aid.source .. " +" .. aid.val .. ") "
            result.effects[#result.effects + 1] = "aided"

            -- Clear the aid (one-time use)
            self.activeAids[actor.id] = nil
            print("[AID] " .. (actor.name or actor.id) .. " used aid bonus +" .. aid.val .. " from " .. aid.source)
        end
    end

    --- Register an aid for a target
    -- @param target table: Entity receiving the aid
    -- @param value number: Bonus value (card value + cups)
    -- @param source string: Name of the aiding entity
    function resolver:registerAid(target, value, source)
        if not target or not target.id then return end

        -- Overwrite any existing aid (per S7.1 design notes)
        self.activeAids[target.id] = {
            val = value,
            source = source,
        }
        print("[AID] " .. source .. " aids " .. (target.name or target.id) .. " with +" .. value .. " bonus")
    end

    ----------------------------------------------------------------------------
    -- DIFFICULTY CALCULATION
    ----------------------------------------------------------------------------

    --- Get the difficulty for an action
    function resolver:getDifficulty(action, actionDef)
        local target = action.target
        local actionType = self:normalizeActionType(action.type)

        -- Default difficulty
        local difficulty = 10

        if target then
            -- Initiative-opposed actions compare against target Initiative
            if self:isInitiativeOpposed(actionType) then
                local initValue = self:getTargetInitiative(target, action)
                if initValue then
                    return initValue
                end

                -- Fallback: legacy defense if initiative unavailable
                return 10 + (target.pentacles or 0)
            end

            if actionType == M.ACTION_TYPES.BANTER then
                -- S12.3: Banter vs dynamic Morale
                if target.getMorale then
                    difficulty = target:getMorale()
                elseif target.baseMorale then
                    difficulty = target.baseMorale
                else
                    -- Legacy fallback
                    difficulty = target.morale or (10 + (target.wands or 0))
                end
            elseif actionType == M.ACTION_TYPES.PARLEY then
                -- Parley is intentionally slightly harder than Banter
                if target.getMorale then
                    difficulty = target:getMorale() + 1
                elseif target.baseMorale then
                    difficulty = target.baseMorale + 1
                end
            end
        end

        return difficulty
    end

    ----------------------------------------------------------------------------
    -- GREAT SUCCESS CHECK
    ----------------------------------------------------------------------------

    --- Check if this is a Great Success
    -- Great = Face card (11-14) AND card suit matches actor's highest stat
    function resolver:isGreatSuccess(card, actor)
        if not card or card.value < 11 then
            return false
        end

        -- Check if card suit matches actor's specialization
        -- (simplified: check if this suit is their highest)
        local suit = card.suit
        local statValue = self:getStatModifier(actor, suit)

        -- For now, any face card on a stat >= 2 is Great
        return statValue >= 2
    end

    ----------------------------------------------------------------------------
    -- SWORDS RESOLUTION (Melee & Missile)
    ----------------------------------------------------------------------------

    function resolver:resolveSwordsAction(action, result)
        local actionType = self:normalizeActionType(action.type or M.ACTION_TYPES.MELEE)

        if actionType == M.ACTION_TYPES.MISSILE then
            self:resolveMissile(action, result)
        else
            self:resolveMelee(action, result)
        end
    end

    --- Resolve melee attack
    function resolver:resolveMelee(action, result)
        local target = action.target

        -- S7.1: Apply any active aids to this attack
        self:applyActiveAids(action.actor, result)

        -- S12.7: Apply Mob Rule bonuses (swarm attack bonuses)
        if action.mobRuleBonus then
            local mobBonus = action.mobRuleBonus
            -- Attack bonus: +1 per additional attacker in same zone
            if mobBonus.attackBonus and mobBonus.attackBonus > 0 then
                result.modifier = result.modifier + mobBonus.attackBonus
                result.testValue = result.cardValue + result.modifier
                result.description = "(Mob +" .. mobBonus.attackBonus .. ") "
            end
            -- Piercing at 3+ attackers
            if mobBonus.piercing then
                result.effects[#result.effects + 1] = "piercing"
            end
            -- Favor at 2+ attackers (would need deck access for true favor)
            if mobBonus.favor then
                result.effects[#result.effects + 1] = "mob_favor"
            end
        end

        local attackValue = result.testValue
        local baseInitiative = result.difficulty
        local defenderHasShield = target and self:entityHasShield(target)

        -- Check engagement (must be in same zone as target)
        if self.zoneSystem and target then
            local actorZone = action.actor.zone
            local targetZone = target.zone

            if actorZone ~= targetZone then
                result.success = false
                result.description = "Target is not engaged (different zone)"
                result.effects[#result.effects + 1] = "not_engaged"
                return
            end
        end

        -- S4.9: Check for and handle defensive actions
        local riposteTriggered = false
        local riposteDefense = nil

        if target and target.hasDefense and target:hasDefense() then
            local defense = target:getDefense()
            if defense then
                if defense.type == "dodge" then
                    -- Dodge: add card value to Initiative; if higher than attack value, miss
                    target:consumeDefense()
                    local dodgeValue = defense.value or 0
                    local newInitiative = baseInitiative + dodgeValue
                    result.effects[#result.effects + 1] = "dodge_used"

                    if newInitiative > attackValue then
                        result.success = false
                        result.description = "Dodged! "
                        result.effects[#result.effects + 1] = "dodged"
                        return
                    else
                        result.effects[#result.effects + 1] = "dodge_failed"
                    end
                elseif defense.type == "riposte" then
                    -- Riposte: will counter-attack after resolution
                    riposteTriggered = true
                    riposteDefense = target:consumeDefense()
                    result.effects[#result.effects + 1] = "riposte_ready"
                end
            end
        end

        -- Resolve hit against Initiative (ties go to attacker unless defender has shield)
        result.success = (attackValue > baseInitiative) or
                         (attackValue == baseInitiative and not defenderHasShield)

        -- S7.6: Flail specialization - ties count as success
        if not result.success and action.weapon and M.isWeaponType(action.weapon, "FLAIL") then
            if attackValue == baseInitiative then
                result.success = true
                result.description = "Flail tie-breaker! "
                result.effects[#result.effects + 1] = "flail_tie"
            end
        end

        if result.success then
            result.damageDealt = 1
            result.description = (result.description or "") .. "Hit! "

            -- S6.3: Form engagement on successful melee attack
            if target and action.actor then
                self:formEngagement(action.actor, target)
            end

            -- S7.6: Hammer/Mace specialization - double damage on overwhelming hit
            if action.weapon and M.isWeaponType(action.weapon, "HAMMER") then
                if result.testValue >= (result.difficulty * 2) then
                    result.damageDealt = 2
                    result.description = result.description .. "Crushing blow! "
                    result.effects[#result.effects + 1] = "hammer_crush"
                end
            end

            -- S7.6: Dagger specialization - piercing vs vulnerable targets
            if action.weapon and M.isWeaponType(action.weapon, "DAGGER") then
                if target and target.conditions then
                    if target.conditions.rooted or target.conditions.prone or target.conditions.disarmed then
                        result.effects[#result.effects + 1] = "piercing"
                        result.description = result.description .. "Exploits vulnerability! "
                    end
                end
            end

            -- Check for Great Success weapon bonus
            if result.isGreat and action.weapon then
                local weaponType = action.weapon.type or action.weapon.name
                local bonus = M.WEAPON_BONUSES[weaponType:lower()]

                if bonus then
                    if bonus.great_bonus == "extra_wound" then
                        result.damageDealt = result.damageDealt + (bonus.wound_bonus or 1)
                        result.description = result.description .. "Great Success! +" .. bonus.wound_bonus .. " wound. "
                    elseif bonus.great_bonus == "stagger" then
                        result.effects[#result.effects + 1] = "stagger"
                        result.description = result.description .. "Great Success! Target staggered. "
                    elseif bonus.great_bonus == "pierce_armor" then
                        result.effects[#result.effects + 1] = "pierce_armor"
                        result.description = result.description .. "Great Success! Armor pierced. "
                    end
                end
            end

            -- Apply damage to target (with weapon for cleave check)
            if target then
                self:applyDamage(target, result.damageDealt, result.effects, action.weapon, action.allEntities)
            end
        else
            result.description = "Miss!"
        end

        -- S4.9: Resolve Riposte counter-attack
        if riposteTriggered and riposteDefense and target then
            local riposteResult = self:resolveRiposte(target, action.actor, riposteDefense, attackValue)
            result.riposteResult = riposteResult
            result.description = result.description .. " Riposte! "
            if riposteResult.success then
                result.description = result.description .. "Counter-attack hits!"
            else
                result.description = result.description .. "Counter-attack misses."
            end
        end
    end

    --- Resolve missile attack
    function resolver:resolveMissile(action, result)
        -- S7.1: Apply any active aids to this attack
        self:applyActiveAids(action.actor, result)

        -- S7.5: Ranged engagement penalty - shooting while engaged is hard
        if action.actor.is_engaged then
            result.modifier = result.modifier - 3
            result.testValue = result.cardValue + result.modifier
            result.description = "(Engaged -3) "
            result.effects[#result.effects + 1] = "engaged_ranged_penalty"
        end

        local attackValue = result.testValue
        local baseInitiative = result.difficulty
        local target = action.target
        local defenderHasShield = target and self:entityHasShield(target)
        local dodged = false
        local riposteTriggered = false
        local riposteDefense = nil

        -- Dodge can negate missile attacks
        if target and target.hasDefense and target:hasDefense() then
            local defense = target:getDefense()
            if defense and defense.type == "dodge" then
                target:consumeDefense()
                local dodgeValue = defense.value or 0
                local newInitiative = baseInitiative + dodgeValue
                result.effects[#result.effects + 1] = "dodge_used"

                if newInitiative > attackValue then
                    dodged = true
                    result.success = false
                    result.description = "Dodged! "
                    result.effects[#result.effects + 1] = "dodged"
                else
                    result.effects[#result.effects + 1] = "dodge_failed"
                end
            elseif defense and defense.type == "riposte" then
                riposteTriggered = true
                riposteDefense = target:consumeDefense()
                result.effects[#result.effects + 1] = "riposte_ready"
            end
        end

        if not dodged then
            -- Resolve hit against Initiative (ties go to attacker unless defender has shield)
            result.success = (attackValue > baseInitiative) or
                             (attackValue == baseInitiative and not defenderHasShield)
        end

        -- S7.8: Crossbow must be loaded
        if action.weapon and M.isWeaponType(action.weapon, "CROSSBOW") then
            if not action.weapon.isLoaded then
                result.success = false
                result.description = (result.description or "") .. "Reload required!"
                result.effects[#result.effects + 1] = "not_loaded"
                return
            end
        end

        -- Check ammo
        if action.weapon and action.weapon.uses_ammo then
            local ammo = action.actor.ammo or 0
            if ammo <= 0 then
                result.success = false
                result.description = "Out of ammo!"
                result.effects[#result.effects + 1] = "no_ammo"
                return
            end

            -- Consume ammo
            action.actor.ammo = ammo - 1
            result.effects[#result.effects + 1] = "ammo_used"
        end

        -- Missile bypasses engagement - no zone check needed

        -- S7.8: Unload crossbow after firing
        if action.weapon and M.isWeaponType(action.weapon, "CROSSBOW") then
            action.weapon.isLoaded = false
            result.effects[#result.effects + 1] = "crossbow_fired"
        end

        if result.success then
            result.damageDealt = 1
            result.description = (result.description or "") .. "Hit! "

            -- Great Success bonuses (same as melee)
            if result.isGreat and action.weapon then
                local weaponType = action.weapon.type or action.weapon.name or "bow"
                local bonus = M.WEAPON_BONUSES[weaponType:lower()]

                if bonus then
                    if bonus.great_bonus == "extra_wound" then
                        result.damageDealt = result.damageDealt + (bonus.wound_bonus or 1)
                        result.description = result.description .. "Great Success! "
                    elseif bonus.great_bonus == "pierce_armor" then
                        result.effects[#result.effects + 1] = "pierce_armor"
                        result.description = result.description .. "Armor pierced! "
                    end
                end
            end

            if action.target then
                self:applyDamage(action.target, result.damageDealt, result.effects)
            end
        else
            if not result.description or result.description == "" then
                result.description = "Miss!"
            end
        end

        if riposteTriggered and riposteDefense and target then
            local riposteResult = self:resolveRiposte(target, action.actor, riposteDefense, attackValue)
            result.riposteResult = riposteResult
            result.description = result.description .. " Riposte! "
            if riposteResult.success then
                result.description = result.description .. "Counter-attack hits!"
            else
                result.description = result.description .. "Counter-attack misses."
            end
        end
    end

    ----------------------------------------------------------------------------
    -- RIPOSTE COUNTER-ATTACK (S4.9)
    ----------------------------------------------------------------------------

    --- Resolve a Riposte counter-attack
    -- @param defender table: Entity performing the riposte
    -- @param attacker table: Original attacker being counter-attacked
    -- @param defense table: The consumed defense { type, card, value }
    -- @return table: Result of the riposte attack
    function resolver:resolveRiposte(defender, attacker, defense, attackerValue)
        local riposteResult = {
            success = false,
            isGreat = false,
            damageDealt = 0,
            effects = {},
            description = "",
        }

        if not defender or not attacker or not defense then
            return riposteResult
        end

        -- Riposte uses the card that was prepared
        local card = defense.card
        local cardValue = defense.value or (card and card.value) or 0

        -- Riposte uses card value only (no attribute)
        local testValue = cardValue

        local compareValue = attackerValue
        if not compareValue and attacker then
            compareValue = 10 + (attacker.pentacles or 0)
        end

        local attackerHasShield = attacker and self:entityHasShield(attacker)
        riposteResult.success = (testValue > compareValue) or
                                (testValue == compareValue and not attackerHasShield)

        if riposteResult.success then
            riposteResult.damageDealt = 1

            -- S7.6: Blade specialization - riposte deals 2 damage with swords
            if defender.weapon and M.isWeaponType(defender.weapon, "BLADE") then
                riposteResult.damageDealt = 2
                riposteResult.description = "Riposte connects with blade! (2 wounds)"
            else
                riposteResult.description = "Riposte connects!"
            end

            -- Apply damage to the original attacker
            self:applyDamage(attacker, riposteResult.damageDealt, riposteResult.effects)

            -- Emit event for visual feedback
            self.eventBus:emit("riposte_hit", {
                defender = defender,
                attacker = attacker,
                damage = riposteResult.damageDealt,
            })
        else
            riposteResult.description = "Riposte parried!"
        end

        return riposteResult
    end

    ----------------------------------------------------------------------------
    -- PENTACLES RESOLUTION (Roughhouse)
    ----------------------------------------------------------------------------

    function resolver:resolvePentaclesAction(action, result)
        local actionType = self:normalizeActionType(action.type or M.ACTION_TYPES.TRIP)

        if actionType == M.ACTION_TYPES.TRIP then
            self:resolveTrip(action, result)
        elseif actionType == M.ACTION_TYPES.DISARM then
            self:resolveDisarm(action, result)
        elseif actionType == M.ACTION_TYPES.DISPLACE then
            self:resolveDisplace(action, result)
        elseif actionType == M.ACTION_TYPES.GRAPPLE then
            -- S7.2: Grapple sets rooted condition
            self:resolveGrapple(action, result)
        elseif actionType == M.ACTION_TYPES.AVOID then
            -- S6.3: Avoid action to escape engagement
            self:resolveAvoid(action, result)
        elseif actionType == M.ACTION_TYPES.DASH then
            -- S6.3: Dash is a Pentacles-based quick move
            self:resolveDash(action, result, action.allEntities)
        else
            self:resolveTrip(action, result)  -- Default
        end
    end

    function resolver:resolveTrip(action, result)
        local contest = self:resolveInitiativeContest(action, result, {
            tieWins = false,
        })

        if contest.dodged then
            return
        end

        if result.success then
            result.description = "Knocked down!"
            result.effects[#result.effects + 1] = "prone"

            if action.target and action.target.conditions then
                action.target.conditions.prone = true
            end
        else
            result.description = "Failed to trip!"
        end

        if contest.riposteTriggered and contest.riposteDefense and action.target then
            local riposteResult = self:resolveRiposte(action.target, action.actor, contest.riposteDefense, contest.attackValue)
            result.riposteResult = riposteResult
            result.description = result.description .. " Riposte! "
            if riposteResult.success then
                result.description = result.description .. "Counter-attack hits!"
            else
                result.description = result.description .. "Counter-attack misses."
            end
        end
    end

    --- S7.3: Disarm with inventory drop
    function resolver:resolveDisarm(action, result)
        local target = action.target

        if not target then
            result.success = false
            result.description = "No target to disarm!"
            return
        end

        local contest = self:resolveInitiativeContest(action, result, {
            tieWins = false,
        })

        if contest.dodged then
            return
        end

        -- Check if target has anything in hands
        local droppedItem = nil
        if target.inventory and target.inventory.getItems then
            local handsItems = target.inventory:getItems("hands")
            if handsItems and #handsItems > 0 then
                -- Remove the first item from hands
                droppedItem = handsItems[1]
                if target.inventory.removeItem then
                    target.inventory:removeItem(droppedItem.id)
                end
            end
        elseif target.weapon then
            -- Fallback: if no inventory system, just clear weapon
            droppedItem = target.weapon
            target.weapon = nil
        end

        if result.success then
            if droppedItem then
                result.description = "Disarmed [" .. (droppedItem.name or "item") .. "]!"
                result.effects[#result.effects + 1] = "disarmed"
                result.droppedItem = droppedItem

                -- Set disarmed condition on target
                if target.conditions then
                    target.conditions.disarmed = true
                end
            else
                -- Can't disarm someone with nothing in hands
                result.success = false
                result.description = "Target has nothing to disarm!"
            end
        else
            result.description = "Failed to disarm!"
        end

        if contest.riposteTriggered and contest.riposteDefense and target then
            local riposteResult = self:resolveRiposte(target, action.actor, contest.riposteDefense, contest.attackValue)
            result.riposteResult = riposteResult
            result.description = result.description .. " Riposte! "
            if riposteResult.success then
                result.description = result.description .. "Counter-attack hits!"
            else
                result.description = result.description .. "Counter-attack misses."
            end
        end
    end

    --- S7.2: Grapple sets rooted condition
    function resolver:resolveGrapple(action, result)
        local target = action.target

        if not target then
            result.success = false
            result.description = "No target to grapple!"
            return
        end

        local contest = self:resolveInitiativeContest(action, result, {
            tieWins = false,
        })

        if contest.dodged then
            return
        end

        if result.success then
            result.description = "Grappled! Target is rooted."
            result.effects[#result.effects + 1] = "grappled"
            result.effects[#result.effects + 1] = "rooted"

            -- Set rooted condition on target
            if target.conditions then
                target.conditions.rooted = true
            else
                target.conditions = { rooted = true }
            end

            -- Also form engagement
            self:formEngagement(action.actor, target)
        else
            result.description = "Failed to grapple!"
        end

        if contest.riposteTriggered and contest.riposteDefense and target then
            local riposteResult = self:resolveRiposte(target, action.actor, contest.riposteDefense, contest.attackValue)
            result.riposteResult = riposteResult
            result.description = result.description .. " Riposte! "
            if riposteResult.success then
                result.description = result.description .. "Counter-attack hits!"
            else
                result.description = result.description .. "Counter-attack misses."
            end
        end
    end

    function resolver:resolveDisplace(action, result)
        local contest = self:resolveInitiativeContest(action, result, {
            tieWins = false,
        })

        if contest.dodged then
            return
        end

        if result.success then
            result.description = "Pushed back!"
            result.effects[#result.effects + 1] = "displaced"

            -- Would move target to adjacent zone
            if action.target and action.destinationZone then
                action.target.zone = action.destinationZone
            end

            -- S6.3: Break engagement when target is displaced
            if action.target and action.actor then
                self:breakEngagement(action.actor, action.target)
            end
        else
            result.description = "Failed to push!"
        end

        if contest.riposteTriggered and contest.riposteDefense and action.target then
            local riposteResult = self:resolveRiposte(action.target, action.actor, contest.riposteDefense, contest.attackValue)
            result.riposteResult = riposteResult
            result.description = result.description .. " Riposte! "
            if riposteResult.success then
                result.description = result.description .. "Counter-attack hits!"
            else
                result.description = result.description .. "Counter-attack misses."
            end
        end
    end

    ----------------------------------------------------------------------------
    -- CUPS RESOLUTION (Support/Social)
    ----------------------------------------------------------------------------

    function resolver:resolveCupsAction(action, result)
        local actionType = self:normalizeActionType(action.type or M.ACTION_TYPES.AID)

        if actionType == M.ACTION_TYPES.DODGE then
            -- S4.9: Prepare Dodge defense
            self:resolveDodge(action, result)
        elseif actionType == M.ACTION_TYPES.RIPOSTE then
            -- S4.9: Prepare Riposte defense
            self:resolveRipostePrepare(action, result)
        elseif actionType == M.ACTION_TYPES.HEAL then
            self:resolveHeal(action, result)
        elseif actionType == M.ACTION_TYPES.COMMAND then
            self:resolveCommand(action, result)
        elseif actionType == M.ACTION_TYPES.PARLEY then
            self:resolveParley(action, result)
        elseif actionType == M.ACTION_TYPES.RALLY then
            self:resolveRally(action, result)
        elseif actionType == M.ACTION_TYPES.USE_ITEM then
            self:resolveUseItem(action, result)
        elseif actionType == M.ACTION_TYPES.PULL_ITEM then
            self:resolvePullItemFromPack(action, result)
        elseif actionType == M.ACTION_TYPES.SHIELD then
            result.success = true
            result.description = "Shielding " .. (action.target and action.target.name or "ally")
            result.effects[#result.effects + 1] = "shielding"
        elseif actionType == M.ACTION_TYPES.AID then
            -- S7.1: Aid Another
            self:resolveAidAnother(action, result)
        else
            self:resolveGenericAction(action, result)
        end
    end

    --- S7.1: Aid Another - bank a bonus for an ally's next action
    function resolver:resolveAidAnother(action, result)
        local actor = action.actor
        local target = action.target

        if not target then
            result.success = false
            result.description = "No ally to aid!"
            return
        end

        if not target.isPC and actor.isPC then
            result.success = false
            result.description = "Can only aid allies!"
            return
        end

        -- Aid always succeeds (no test required)
        result.success = true

        -- Calculate bonus from resolved action value (respects minor-action rules)
        local totalBonus = result.testValue or (action.card and action.card.value) or 0

        -- Register the aid for the target
        self:registerAid(target, totalBonus, actor.name or "ally")

        result.description = "Aided " .. (target.name or "ally") .. "! (+" .. totalBonus .. " to next action)"
        result.effects[#result.effects + 1] = "aid_banked"
    end

    function resolver:resolveCommand(action, result)
        local actor = action.actor
        local target = action.target
        local hasCompanion = actor and (
            actor.companion ~= nil or
            (type(actor.companions) == "table" and next(actor.companions) ~= nil)
        )

        if not hasCompanion then
            result.success = false
            result.description = "No companion to command."
            return
        end

        if target then
            local targetInitiative = result.difficulty
            local defenderHasShield = self:entityHasShield(target)
            result.success = (result.testValue > targetInitiative) or
                             (result.testValue == targetInitiative and not defenderHasShield)
        else
            result.success = true
        end

        if result.success then
            result.description = "Command issued."
            result.effects[#result.effects + 1] = "commanded"
        else
            result.description = "Command resisted."
        end
    end

    function resolver:resolveParley(action, result)
        local target = action.target
        if not target then
            result.success = false
            result.description = "No target to parley with."
            return
        end

        -- Parley requires exceeding the social difficulty, matching Banter semantics.
        result.success = result.testValue > result.difficulty

        self.eventBus:emit("social_discovery", {
            target = target,
            targetId = target.id,
            discoveries = { "disposition", "morale" },
        })

        if result.success then
            local oldDisposition = target.getDisposition and target:getDisposition() or target.disposition
            local newDisposition = oldDisposition or "distaste"

            if disposition_module and disposition_module.moveToward and disposition_module.DISPOSITIONS then
                newDisposition = disposition_module.moveToward(
                    newDisposition,
                    disposition_module.DISPOSITIONS.TRUST,
                    1
                )
            elseif target.shiftDisposition then
                target:shiftDisposition(1, 1)
                newDisposition = target.getDisposition and target:getDisposition() or target.disposition
            end

            if target.setDisposition then
                target:setDisposition(newDisposition)
            else
                target.disposition = newDisposition
            end

            result.description = "Parley gains ground."
            result.effects[#result.effects + 1] = "parley_progress"
        else
            if target.shiftDisposition then
                target:shiftDisposition(-1, 1)
            end
            result.description = "Parley fails to persuade."
        end
    end

    function resolver:resolveRally(action, result)
        local target = action.target or action.actor
        if not target then
            result.success = false
            result.description = "No ally to rally."
            return
        end

        if not result.success then
            result.description = "Rally falters."
            return
        end

        local cleared = nil
        if target.conditions then
            if target.conditions.stressed then
                target.conditions.stressed = false
                cleared = "stressed"
            elseif target.conditions.frightened then
                target.conditions.frightened = false
                cleared = "frightened"
            elseif target.conditions.deaf then
                target.conditions.deaf = false
                cleared = "deaf"
            elseif target.conditions.blind then
                target.conditions.blind = false
                cleared = "blind"
            end
        end

        if target.modifyMorale then
            target:modifyMorale(1)
        end

        if cleared then
            result.description = "Rallied " .. (target.name or "ally") .. " (" .. cleared .. " cleared)."
            result.effects[#result.effects + 1] = "rally_" .. cleared
        else
            result.description = "Rallied " .. (target.name or "ally") .. "."
            result.effects[#result.effects + 1] = "rally_boost"
        end
    end

    function resolver:resolveUseItem(action, result)
        if action.target then
            local targetInitiative = result.difficulty
            local defenderHasShield = self:entityHasShield(action.target)
            result.success = (result.testValue > targetInitiative) or
                             (result.testValue == targetInitiative and not defenderHasShield)
        else
            result.success = true
        end

        if result.success then
            result.description = action.target and "Item effect lands." or "Item used."
            result.effects[#result.effects + 1] = "item_used"
        else
            result.description = "Item use resisted."
        end
    end

    function resolver:resolvePullItemFromPack(action, result)
        result.success = true
        result.description = "Pulled item from pack."
        result.effects[#result.effects + 1] = "item_pulled_pack"
    end

    --- Prepare a Dodge defense (S4.9)
    -- Dodge adds card value to defense difficulty when attacked
    function resolver:resolveDodge(action, result)
        local actor = action.actor
        local card = action.card

        if not actor or not card then
            result.success = false
            result.description = "Invalid dodge attempt"
            return
        end

        -- Check if entity already has a defense prepared
        if actor.hasDefense and actor:hasDefense() then
            result.success = false
            result.description = "Already has a defense prepared!"
            return
        end

        -- Prepare the dodge defense
        local success, err = actor:prepareDefense("dodge", card)

        if success then
            result.success = true
            result.description = "Preparing to dodge! (+" .. (card.value or 0) .. " to Initiative)"
            result.effects[#result.effects + 1] = "dodge_prepared"

            self.eventBus:emit("defense_prepared", {
                entity = actor,
                type = "dodge",
                value = card.value or 0,
            })
        else
            result.success = false
            result.description = "Cannot prepare dodge: " .. (err or "unknown")
        end
    end

    --- Prepare a Riposte defense (S4.9)
    -- Riposte triggers a counter-attack when attacked
    function resolver:resolveRipostePrepare(action, result)
        local actor = action.actor
        local card = action.card

        if not actor or not card then
            result.success = false
            result.description = "Invalid riposte attempt"
            return
        end

        -- Check if entity already has a defense prepared
        if actor.hasDefense and actor:hasDefense() then
            result.success = false
            result.description = "Already has a defense prepared!"
            return
        end

        -- Prepare the riposte defense
        local success, err = actor:prepareDefense("riposte", card)

        if success then
            result.success = true
            result.description = "Ready to riposte! (Counter-attack with value " .. (card.value or 0) .. ")"
            result.effects[#result.effects + 1] = "riposte_prepared"

            self.eventBus:emit("defense_prepared", {
                entity = actor,
                type = "riposte",
                value = card.value or 0,
            })
        else
            result.success = false
            result.description = "Cannot prepare riposte: " .. (err or "unknown")
        end
    end

    function resolver:resolveHeal(action, result)
        if result.success then
            local target = action.target or action.actor

            -- Attempt to heal wound (respects stress gate)
            local healResult, err = target:healWound()

            if healResult then
                result.description = "Healed: " .. healResult
                result.effects[#result.effects + 1] = "healed"
            else
                result.success = false
                result.description = "Cannot heal: " .. (err or "unknown")
            end
        else
            result.description = "Healing failed!"
        end
    end

    ----------------------------------------------------------------------------
    -- WANDS RESOLUTION (Banter/Magic)
    ----------------------------------------------------------------------------

    function resolver:resolveWandsAction(action, result)
        local actionType = self:normalizeActionType(action.type or M.ACTION_TYPES.BANTER)

        if actionType == M.ACTION_TYPES.BANTER then
            self:resolveBanter(action, result)
        elseif actionType == M.ACTION_TYPES.SPEAK_INCANTATION then
            self:resolveSpeakIncantation(action, result)
        elseif actionType == M.ACTION_TYPES.RECOVER then
            -- S7.4: Recover action
            self:resolveRecover(action, result)
        else
            self:resolveBanter(action, result)
        end
    end

    --- S7.4: Recover - clear one negative status effect in priority order
    function resolver:resolveRecover(action, result)
        local actor = action.actor

        if not actor or not actor.conditions then
            result.success = false
            result.description = "Nothing to recover from."
            return
        end

        -- Priority order for clearing conditions (per S7.4 spec)
        local conditions = actor.conditions
        local cleared = nil

        if conditions.rooted then
            conditions.rooted = false
            cleared = "rooted"
        elseif conditions.prone then
            conditions.prone = false
            cleared = "prone"
        elseif conditions.blind then
            conditions.blind = false
            cleared = "blind"
        elseif conditions.deaf then
            conditions.deaf = false
            cleared = "deaf"
        elseif conditions.disarmed then
            conditions.disarmed = false
            cleared = "disarmed"
            result.description = "Recovered Weapon!"
            result.effects[#result.effects + 1] = "weapon_recovered"
        end

        if cleared then
            result.success = true
            if not result.description or result.description == "" then
                result.description = "Recovered from " .. cleared .. "!"
            end
            result.effects[#result.effects + 1] = "recovered_" .. cleared
        else
            result.success = false
            result.description = "Nothing to recover from."
        end
    end

    --- Resolve Banter (attacks Morale instead of Health)
    -- S12.3: Updated to use dynamic morale calculation
    -- S12.4: Applies disposition modifiers and shifts disposition
    function resolver:resolveBanter(action, result)
        -- Banter compares vs target's Morale (p. 119)
        -- Difficulty = target's current morale + disposition modifier

        local target = action.target
        if not target then
            result.description = "No target for banter!"
            return
        end

        -- S12.3: Get target's current morale (dynamically calculated)
        local targetMorale = 10  -- Default fallback
        if target.getMorale then
            targetMorale = target:getMorale()
        elseif target.baseMorale then
            targetMorale = target.baseMorale
        end

        -- S12.4: Apply disposition modifier
        local dispositionMod = 0
        local targetDisposition = target.disposition or "distaste"
        if disposition_module then
            dispositionMod = disposition_module.getSocialModifier(targetDisposition, "banter")
        end

        -- Override difficulty with morale + disposition modifier
        result.difficulty = targetMorale + dispositionMod

        -- Recalculate success based on morale difficulty
        result.success = result.testValue > result.difficulty

        -- Reveal disposition and morale on ANY banter attempt (you learn by trying)
        self.eventBus:emit("social_discovery", {
            target = target,
            targetId = target.id,
            discoveries = { "disposition", "morale" },
        })

        if result.success then
            result.description = "Verbal hit! "
            result.effects[#result.effects + 1] = "morale_damage"

            -- Apply morale damage via modifier
            local moraleDamage = 2  -- Base banter damage
            if result.isGreat then
                moraleDamage = 4  -- Great success deals double
                result.description = result.description .. "Great Success! "

                -- Great success also reveals likes/dislikes
                self.eventBus:emit("social_discovery", {
                    target = target,
                    targetId = target.id,
                    discoveries = { "hates", "wants" },
                })
            end

            -- S12.3: Apply morale damage as temporary modifier
            if target.modifyMorale then
                target:modifyMorale(-moraleDamage)
            end

            -- S12.4: Shift disposition on success (toward fear/sadness)
            if target.shiftDisposition then
                local shiftAmount = result.isGreat and 2 or 1
                target:shiftDisposition(1, shiftAmount)  -- Clockwise toward fear
            end

            result.moraleDamage = moraleDamage

            -- Check for morale break (morale drops to 0 or below)
            local newMorale = 10
            if target.getMorale then
                newMorale = target:getMorale()
            end

            if newMorale <= 0 then
                result.effects[#result.effects + 1] = "morale_broken"
                result.description = result.description .. "Morale broken!"

                if target.conditions then
                    target.conditions.fleeing = true
                end
            else
                result.description = result.description .. string.format("Morale: %d -> %d", targetMorale, newMorale)
            end
        else
            -- S12.4: Failed banter can anger the target
            if target.shiftDisposition then
                target:shiftDisposition(-1, 1)  -- Counter-clockwise toward anger
            end
            result.description = string.format("Banter ineffective! (needed %d, got %d)", result.difficulty, result.testValue)
        end
    end

    function resolver:resolveSpeakIncantation(action, result)
        local target = action.target

        if target then
            local spellValue = result.testValue
            local targetInitiative = result.difficulty
            local defenderHasShield = self:entityHasShield(target)
            result.success = (spellValue > targetInitiative) or
                             (spellValue == targetInitiative and not defenderHasShield)
        else
            result.success = true
        end

        if result.success then
            result.description = "Incantation takes effect!"
            result.effects[#result.effects + 1] = "spell_cast"
        else
            result.description = "Incantation resisted."
        end
    end

    -- Backward-compatible wrapper
    function resolver:resolveCast(action, result)
        self:resolveSpeakIncantation(action, result)
    end

    function resolver:resolveGuard(action, result)
        local actor = action.actor
        if not actor then
            result.success = false
            result.description = "No actor for Guard."
            return
        end

        if not self:entityHasShield(actor) then
            result.success = false
            result.description = "Guard requires a shield."
            return
        end

        local controller = action.challengeController or self.challengeController
        if not controller or not controller.getInitiativeSlot then
            result.success = false
            result.description = "No initiative slot available."
            return
        end

        local slot = controller:getInitiativeSlot(actor.id)
        if not slot then
            result.success = false
            result.description = "No initiative to replace."
            return
        end

        local oldValue = slot.value or (slot.card and slot.card.value) or 0
        slot.card = action.card
        slot.value = action.card and action.card.value or oldValue
        slot.revealed = true

        self.eventBus:emit(events.EVENTS.INITIATIVE_REVEALED, {
            entity = actor,
        })

        result.success = true
        result.description = "Guard set Initiative from " .. oldValue .. " to " .. slot.value .. "."
        result.effects[#result.effects + 1] = "guarded"
    end

    local function resolveFollowUpActionType(followUpAction)
        if type(followUpAction) == "table" then
            return followUpAction.id or followUpAction.type
        end
        return followUpAction
    end

    --- Pick a sensible same-suit follow-up when UI did not provide one.
    function resolver:selectDefaultVigilanceFollowUp(action)
        if not action or not action.card then
            return nil
        end

        local cardActionSuit = action_registry.cardSuitToActionSuit(action.card.suit)
        if cardActionSuit == action_registry.SUITS.MISC then
            return nil
        end

        local options = action_registry.getActionsForSuit(cardActionSuit, {
            challengeOnly = true,
        })

        for _, option in ipairs(options) do
            local optionType = self:normalizeActionType(option.id)
            if optionType ~= M.ACTION_TYPES.VIGILANCE then
                return optionType
            end
        end

        return nil
    end

    function resolver:resolveVigilance(action, result)
        local actor = action.actor
        if not actor then
            result.success = false
            result.description = "No actor for Vigilance."
            return
        end

        if actor.pendingVigilance then
            result.success = false
            result.description = "Already has Vigilance prepared."
            return
        end

        local followUpActionType = resolveFollowUpActionType(action.followUpAction)
        followUpActionType = self:normalizeActionType(followUpActionType)
        if not followUpActionType then
            followUpActionType = self:selectDefaultVigilanceFollowUp(action)
        end
        if not followUpActionType then
            result.success = false
            result.description = "Vigilance needs a follow-up action."
            return
        end

        local followUpActionDef = action_registry.getAction(followUpActionType)
        if not followUpActionDef then
            result.success = false
            result.description = "Unknown Vigilance follow-up action."
            return
        end

        if followUpActionDef.suit == action_registry.SUITS.MISC then
            result.success = false
            result.description = "Vigilance follow-up must be a suited action."
            return
        end

        if not action.card or not action.card.suit then
            result.success = false
            result.description = "Vigilance requires a suited card."
            return
        end

        local cardActionSuit = action_registry.cardSuitToActionSuit(action.card.suit)
        if cardActionSuit == action_registry.SUITS.MISC then
            result.success = false
            result.description = "Vigilance requires a non-misc suit card."
            return
        end

        if followUpActionDef.suit ~= cardActionSuit then
            result.success = false
            result.description = "Vigilance follow-up suit must match card suit."
            return
        end

        local followUpTargetPolicy = action.followUpTargetPolicy
        if not followUpTargetPolicy then
            if followUpActionDef.targetType == "enemy" then
                followUpTargetPolicy = "trigger_actor"
            elseif followUpActionDef.targetType == "ally" then
                followUpTargetPolicy = "self"
            else
                followUpTargetPolicy = "none"
            end
        end

        self.vigilanceCounter = (self.vigilanceCounter or 0) + 1

        actor.pendingVigilance = {
            card = action.card,
            trigger = action.trigger or action.triggerAction or {
                mode = "targeted_by_hostile_action",
                target = "self",
                hostileOnly = true,
                excludeSelf = true,
            },
            followUpAction = followUpActionType,
            followUpTargetPolicy = followUpTargetPolicy,
            followUpTarget = action.followUpTarget or action.target,
            followUpDestinationZone = action.followUpDestinationZone,
            weapon = action.weapon,
            declaredOrder = self.vigilanceCounter,
        }

        self.eventBus:emit("vigilance_prepared", {
            actor = actor,
            trigger = actor.pendingVigilance.trigger,
            followUpAction = actor.pendingVigilance.followUpAction,
        })

        result.success = true
        result.description = "Vigilance prepared: " ..
            (followUpActionDef.name or followUpActionType) .. "."
        result.effects[#result.effects + 1] = "vigilance_prepared"
    end

    ----------------------------------------------------------------------------
    -- GENERIC RESOLUTION
    ----------------------------------------------------------------------------

    function resolver:resolveGenericAction(action, result)
        local actionDef = action.actionDef or self:getActionDef(action)
        local actionType = self:normalizeActionType(action.type)

        if actionDef and actionDef.autoSuccess then
            result.success = true
        end

        if result.success then
            if actionType == M.ACTION_TYPES.BID_LORE then
                result.description = "Lore bid offered."
                result.effects[#result.effects + 1] = "lore_bid"
            elseif actionType == M.ACTION_TYPES.TRIVIAL_ACTION then
                result.description = "Trivial action completed."
            elseif actionType == M.ACTION_TYPES.PULL_ITEM_BELT then
                result.description = "Pulled item from belt."
                result.effects[#result.effects + 1] = "item_pulled_belt"
            elseif actionType == M.ACTION_TYPES.TEST_FATE then
                result.description = "Test of Fate requested."
            else
                result.description = "Action succeeded!"
            end
        else
            result.description = "Action failed!"
        end
    end

    ----------------------------------------------------------------------------
    -- S7.8: RELOAD ACTION
    ----------------------------------------------------------------------------

    --- Resolve reload action for crossbows
    function resolver:resolveReload(action, result)
        local actor = action.actor
        local weapon = action.weapon

        if not weapon and actor and actor.inventory and actor.inventory.getWieldedWeapon then
            weapon = actor.inventory:getWieldedWeapon()
        end
        if not weapon then
            weapon = actor.weapon
        end

        -- Must have a crossbow equipped
        if not weapon or not M.isWeaponType(weapon, "CROSSBOW") then
            result.success = false
            result.description = "No crossbow to reload!"
            return
        end

        -- Check if already loaded
        if weapon.isLoaded then
            result.success = false
            result.description = "Crossbow is already loaded!"
            return
        end

        -- Reload succeeds (no test required)
        result.success = true
        weapon.isLoaded = true
        result.description = "Crossbow reloaded!"
        result.effects[#result.effects + 1] = "reloaded"
    end

    ----------------------------------------------------------------------------
    -- S6.3/S12.1: ENGAGEMENT SYSTEM
    -- Delegates to zoneSystem as single source of truth
    ----------------------------------------------------------------------------

    --- Form engagement between two entities
    function resolver:formEngagement(entity1, entity2)
        if not entity1 or not entity2 then return end

        -- S12.1: Delegate to zoneSystem
        if self.zoneSystem then
            self.zoneSystem:engage(entity1.id, entity2.id)
        end

        -- Set is_engaged flag on entities (convenience flag)
        entity1.is_engaged = true
        entity2.is_engaged = true

        -- Emit arena event for visual feedback
        self.eventBus:emit("engagement_formed", {
            entity1 = entity1,
            entity2 = entity2,
        })
    end

    --- Break engagement between two specific entities
    function resolver:breakEngagement(entity1, entity2)
        if not entity1 or not entity2 then return end

        -- S12.1: Delegate to zoneSystem
        if self.zoneSystem then
            self.zoneSystem:disengage(entity1.id, entity2.id)
        end

        -- Update is_engaged flag based on remaining engagements
        entity1.is_engaged = self:hasAnyEngagement(entity1)
        entity2.is_engaged = self:hasAnyEngagement(entity2)

        -- Emit arena event for visual feedback
        self.eventBus:emit("engagement_broken", {
            entity1 = entity1,
            entity2 = entity2,
        })
    end

    --- Clear all engagements for an entity (on defeat)
    function resolver:clearAllEngagements(entity)
        if not entity then return end

        -- S12.1: Delegate to zoneSystem
        if self.zoneSystem then
            self.zoneSystem:disengageAll(entity.id)
        end

        entity.is_engaged = false
    end

    --- Check if entity has any engagements
    function resolver:hasAnyEngagement(entity)
        if not entity then return false end

        -- S12.1: Delegate to zoneSystem
        if self.zoneSystem then
            return self.zoneSystem:isEngaged(entity.id)
        end
        return false
    end

    --- Check if two entities are engaged
    function resolver:areEngaged(entity1, entity2)
        if not entity1 or not entity2 then return false end

        -- S12.1: Delegate to zoneSystem
        if self.zoneSystem then
            return self.zoneSystem:areEngaged(entity1.id, entity2.id)
        end
        return false
    end

    --- Get all entities engaged with a given entity
    -- @param entity table: The entity to check
    -- @param allEntities table: Array of all entities in the challenge
    -- @return table: Array of engaged entities
    function resolver:getEngagedEnemies(entity, allEntities)
        if not entity then return {} end

        -- S12.1: Get engaged IDs from zoneSystem
        local engagedIds = {}
        if self.zoneSystem then
            engagedIds = self.zoneSystem:getEngagedWith(entity.id)
        end

        -- Convert IDs to entity references
        local enemies = {}
        local idSet = {}
        for _, id in ipairs(engagedIds) do
            idSet[id] = true
        end

        for _, e in ipairs(allEntities or {}) do
            if idSet[e.id] then
                enemies[#enemies + 1] = e
            end
        end
        return enemies
    end

    --- Resolve movement adjacency using zone registry when available,
    -- otherwise fall back to challenge zone data.
    function resolver:canMoveBetweenZones(action, fromZoneId, toZoneId)
        if not toZoneId then
            return true, nil
        end
        if not fromZoneId or fromZoneId == toZoneId then
            return true, nil
        end

        if self.zoneSystem and self.zoneSystem.getZone and self.zoneSystem.areZonesAdjacent then
            local fromZone = self.zoneSystem:getZone(fromZoneId)
            local toZone = self.zoneSystem:getZone(toZoneId)
            if fromZone and toZone then
                if self.zoneSystem:areZonesAdjacent(fromZoneId, toZoneId) then
                    return true, nil
                end
                return false, "zones_not_adjacent"
            end
            if toZone == nil then
                return false, "zone_not_found"
            end
        end

        local zones = action and action.challengeController and action.challengeController.zones
        if not zones or #zones == 0 then
            return true, nil
        end

        local byId = {}
        for _, zone in ipairs(zones) do
            byId[zone.id] = zone
        end

        local fromZone = byId[fromZoneId]
        local toZone = byId[toZoneId]
        if not toZone then
            return false, "zone_not_found"
        end
        if not fromZone then
            return true, nil
        end

        if fromZone.adjacent_to then
            for _, adjId in ipairs(fromZone.adjacent_to) do
                if adjId == toZoneId then
                    return true, nil
                end
            end
            return false, "zones_not_adjacent"
        end

        if toZone.adjacent_to then
            for _, adjId in ipairs(toZone.adjacent_to) do
                if adjId == fromZoneId then
                    return true, nil
                end
            end
            return false, "zones_not_adjacent"
        end

        return true, nil
    end

    ----------------------------------------------------------------------------
    -- S6.3: PARTING BLOWS
    ----------------------------------------------------------------------------

    --- Check and apply parting blows when entity tries to move while engaged
    -- @param entity table: The moving entity
    -- @param allEntities table: All entities in the challenge
    -- @return table: { blocked = bool, wounds = number, attackers = { ... } }
    function resolver:checkPartingBlows(entity, allEntities)
        local result = {
            blocked = false,
            wounds = 0,
            attackers = {},
        }

        if not entity or not entity.is_engaged then
            return result
        end

        -- S12.1: Get engaged enemies from zoneSystem
        local engagedIds = {}
        if self.zoneSystem then
            engagedIds = self.zoneSystem:getEngagedWith(entity.id)
        end

        -- Convert to a set for fast lookup
        local engagedSet = {}
        for _, id in ipairs(engagedIds) do
            engagedSet[id] = true
        end

        -- Find all engaged enemies in the same zone
        for _, e in ipairs(allEntities or {}) do
            if engagedSet[e.id] and e.zone == entity.zone then
                -- Enemy gets a free parting blow
                result.attackers[#result.attackers + 1] = e
                result.wounds = result.wounds + 1

                -- Emit parting blow event
                self.eventBus:emit(events.EVENTS.PARTING_BLOW, {
                    attacker = e,
                    victim = entity,
                })
            end
        end

        -- Apply wounds to the mover
        if result.wounds > 0 then
            for _ = 1, result.wounds do
                local woundResult = entity:takeWound(false)

                self.eventBus:emit(events.EVENTS.WOUND_TAKEN, {
                    entity = entity,
                    result = woundResult,
                    source = "parting_blow",
                })

                -- Check if mover is incapacitated
                if entity.conditions and entity.conditions.deaths_door then
                    result.blocked = true
                    break
                end
                if entity.conditions and entity.conditions.dead then
                    result.blocked = true
                    break
                end
            end
        end

        return result
    end

    ----------------------------------------------------------------------------
    -- S6.3: MOVE/DASH/AVOID RESOLUTION
    ----------------------------------------------------------------------------

    --- Resolve movement action (subject to parting blows)
    function resolver:resolveMove(action, result, allEntities)
        local actor = action.actor
        local destZone = action.destinationZone
        local oldZone = actor.zone

        -- S7.2: Check for rooted condition
        if actor.conditions and actor.conditions.rooted then
            result.success = false
            result.description = "Rooted! Cannot move."
            result.effects[#result.effects + 1] = "rooted_blocked"
            return
        end

        if destZone then
            local canMove, moveError = self:canMoveBetweenZones(action, oldZone, destZone)
            if not canMove then
                result.success = false
                if moveError == "zone_not_found" then
                    result.description = "Move failed: destination zone is invalid."
                    result.effects[#result.effects + 1] = "zone_not_found"
                else
                    result.description = "Move failed: destination zone is not adjacent."
                    result.effects[#result.effects + 1] = "non_adjacent_move_blocked"
                end
                return
            end
        end

        -- Check for parting blows if engaged
        if actor.is_engaged then
            local partingResult = self:checkPartingBlows(actor, allEntities)

            if partingResult.blocked then
                result.success = false
                result.description = "Movement blocked! "
                if #partingResult.attackers > 0 then
                    result.description = result.description .. "Took " .. partingResult.wounds .. " parting blow(s) and fell!"
                end
                result.effects[#result.effects + 1] = "parting_blow_blocked"
                return
            end

            if partingResult.wounds > 0 then
                result.effects[#result.effects + 1] = "parting_blows"
                result.partingBlows = partingResult
            end
        end

        -- Movement succeeds
        result.success = true
        if destZone then
            if self.zoneSystem and actor and actor.id then
                local placed, err = self.zoneSystem:placeEntity(actor.id, destZone)
                if not placed then
                    result.success = false
                    result.description = "Move failed: destination zone could not be entered."
                    result.effects[#result.effects + 1] = "zone_sync_failed"
                    if err then
                        result.effects[#result.effects + 1] = "zone_sync_error_" .. tostring(err)
                    end
                    return
                end
            end

            actor.zone = destZone
            result.description = "Moved to " .. destZone

            -- Emit event for arena view to update display
            self.eventBus:emit("entity_zone_changed", {
                entity = actor,
                oldZone = oldZone,
                newZone = destZone,
            })

            print("[MOVE] " .. (actor.name or actor.id) .. " moved from " .. (oldZone or "?") .. " to " .. destZone)
        else
            result.description = "Movement complete"
        end
        result.effects[#result.effects + 1] = "moved"

        -- Clear engagements (they're now in different zones)
        if actor.is_engaged then
            self:clearAllEngagements(actor)
        end
    end

    --- Resolve Dash action (faster move, still subject to parting blows)
    function resolver:resolveDash(action, result, allEntities)
        local actor = action.actor

        -- S7.2: Check for rooted condition
        if actor.conditions and actor.conditions.rooted then
            result.success = false
            result.description = "Rooted! Cannot dash."
            result.effects[#result.effects + 1] = "rooted_blocked"
            return
        end

        -- Dash is similar to move but might cover more distance
        self:resolveMove(action, result, allEntities)

        if result.success then
            result.description = "Dashed! " .. (result.description or "")
            result.effects[#result.effects + 1] = "dashed"
        end
    end

    --- Resolve Avoid action (escape engagement without parting blows)
    function resolver:resolveAvoid(action, result)
        local actor = action.actor
        local card = action.card
        local destinationZone = action.destinationZone

        -- S7.2: Check for rooted condition
        if actor.conditions and actor.conditions.rooted then
            result.success = false
            result.description = "Rooted! Cannot avoid."
            result.effects[#result.effects + 1] = "rooted_blocked"
            return
        end

        if destinationZone then
            local canMove, moveError = self:canMoveBetweenZones(action, actor.zone, destinationZone)
            if not canMove then
                result.success = false
                if moveError == "zone_not_found" then
                    result.description = "Avoid failed: destination zone is invalid."
                    result.effects[#result.effects + 1] = "zone_not_found"
                else
                    result.description = "Avoid failed: destination zone is not adjacent."
                    result.effects[#result.effects + 1] = "non_adjacent_move_blocked"
                end
                return
            end
        end

        local avoidValue = result.testValue or ((card.value or 0) + (actor.pentacles or 0))
        local engagedEnemies = self:getEngagedEnemies(actor, action.allEntities)
        local failures = 0

        for _, enemy in ipairs(engagedEnemies) do
            local enemyInit = self:getTargetInitiative(enemy, action) or (10 + (enemy.pentacles or 0))
            if avoidValue < enemyInit then
                failures = failures + 1

                local woundResult = actor:takeWound(false)
                self.eventBus:emit(events.EVENTS.WOUND_TAKEN, {
                    entity = actor,
                    result = woundResult,
                    source = "avoid_failed",
                })
            end
        end

        result.success = (failures == 0)
        if result.success then
            result.description = "Avoided successfully."
            result.effects[#result.effects + 1] = "avoid_success"
        else
            result.description = "Avoided, but took " .. failures .. " Wound(s)."
            result.effects[#result.effects + 1] = "avoid_failed"
        end

        -- Clear engagements and move regardless of success
        self:clearAllEngagements(actor)

        if destinationZone then
            local oldZone = actor.zone
            if self.zoneSystem and actor and actor.id then
                local placed, err = self.zoneSystem:placeEntity(actor.id, destinationZone)
                if not placed then
                    result.success = false
                    result.description = "Avoid failed: destination zone could not be entered."
                    result.effects[#result.effects + 1] = "zone_sync_failed"
                    if err then
                        result.effects[#result.effects + 1] = "zone_sync_error_" .. tostring(err)
                    end
                    return
                end
            end
            actor.zone = destinationZone
            result.description = result.description .. " Moved to " .. destinationZone

            self.eventBus:emit("entity_zone_changed", {
                entity = actor,
                oldZone = oldZone,
                newZone = destinationZone,
            })
        end
    end

    ----------------------------------------------------------------------------
    -- THE FOOL INTERRUPT (S4.9)
    -- The Fool allows an immediate action out of turn order
    -- Playing The Fool grants a free action with a follow-up card
    ----------------------------------------------------------------------------

    --- Resolve The Fool interrupt
    -- @param action table: { actor, card (The Fool), followUpCard, followUpAction, target }
    -- @param result table: Result to populate
    -- @return table: The result
    function resolver:resolveFoolInterrupt(action, result)
        result.success = true
        result.isFoolInterrupt = true
        result.effects[#result.effects + 1] = "fool_interrupt"

        -- The Fool by itself just grants the interrupt opportunity
        -- If there's a follow-up action specified, resolve that instead
        if action.followUpCard and action.followUpAction then
            -- Create a sub-action using the follow-up card
            local followUpAction = {
                actor = action.actor,
                target = action.target,
                card = action.followUpCard,
                type = action.followUpAction,
                weapon = action.weapon,
            }

            -- Resolve the follow-up action
            local followUpResult = self:resolve(followUpAction)

            -- Merge results
            result.followUpResult = followUpResult
            result.description = "The Fool! Immediate action: " .. (followUpResult.description or "")
            result.damageDealt = followUpResult.damageDealt
            result.isGreat = followUpResult.isGreat

            -- Copy effects from follow-up
            for _, effect in ipairs(followUpResult.effects) do
                result.effects[#result.effects + 1] = effect
            end
        else
            -- No follow-up specified - Fool grants free movement or simple action
            result.description = "The Fool! You may take an immediate action."
            result.effects[#result.effects + 1] = "pending_fool_action"

            -- Emit event for UI to prompt for follow-up action
            self.eventBus:emit("fool_interrupt", {
                actor = action.actor,
                awaitingFollowUp = true,
            })
        end

        -- Attach result
        action.result = result

        return result
    end

    ----------------------------------------------------------------------------
    -- DAMAGE APPLICATION (S7.6: Updated with weapon cleave, S7.7: damage types)
    ----------------------------------------------------------------------------

    --- Apply damage to an entity
    -- @param entity table: Target entity
    -- @param amount number: Number of wounds
    -- @param effects table: Effect flags (pierce_armor, piercing, critical, etc.)
    -- @param weapon table: Optional weapon for cleave check
    -- @param allEntities table: Optional list of all entities for cleave targeting
    function resolver:applyDamage(entity, amount, effects, weapon, allEntities)
        effects = effects or {}

        -- S7.7: Determine damage type from effects
        local damageType = "normal"
        for _, eff in ipairs(effects) do
            if eff == "critical" then
                damageType = "critical"
                break
            elseif eff == "piercing" or eff == "pierce_armor" then
                damageType = "piercing"
            end
        end

        local wasDefeated = false
        for _ = 1, amount do
            -- Call entity's takeWound with damage type (S7.7)
            local woundResult = entity:takeWound(damageType)

            print("[DAMAGE] " .. (entity.name or entity.id) .. " takes " .. damageType .. " wound -> " .. (woundResult or "?"))
            print("  Armor: " .. (entity.armorNotches or 0) ..
                  " | Conditions: stag=" .. tostring(entity.conditions and entity.conditions.staggered) ..
                  " inj=" .. tostring(entity.conditions and entity.conditions.injured) ..
                  " dd=" .. tostring(entity.conditions and entity.conditions.deaths_door) ..
                  " dead=" .. tostring(entity.conditions and entity.conditions.dead))

            -- Emit wound event for visual
            self.eventBus:emit(events.EVENTS.WOUND_TAKEN, {
                entity = entity,
                result = woundResult,
                damageType = damageType,
            })

            -- Check for defeat
            if entity.conditions and (entity.conditions.dead or entity.conditions.deaths_door) then
                wasDefeated = true
                if entity.conditions.dead then
                    print("[DEFEAT] " .. (entity.name or entity.id) .. " is DEAD!")
                    -- S6.3: Clear all engagements when defeated
                    self:clearAllEngagements(entity)

                    self.eventBus:emit(events.EVENTS.ENTITY_DEFEATED, {
                        entity = entity,
                    })
                end
                break
            end
        end

        -- S7.6: Axe Cleave - on defeat, free attack on another enemy in same zone
        if wasDefeated and weapon and M.isWeaponType(weapon, "AXE") and allEntities then
            self:triggerAxeCleave(entity, weapon, allEntities)
        end
    end

    --- S7.6: Trigger axe cleave attack on another enemy in same zone
    function resolver:triggerAxeCleave(defeatedEntity, weapon, allEntities)
        local zone = defeatedEntity.zone
        local cleaveTarget = nil

        -- Find another enemy in the same zone
        for _, e in ipairs(allEntities or {}) do
            if e ~= defeatedEntity and e.zone == zone then
                if not (e.conditions and e.conditions.dead) then
                    -- Prefer enemies over allies
                    if e.isPC ~= defeatedEntity.isPC then
                        cleaveTarget = e
                        break
                    elseif not cleaveTarget then
                        cleaveTarget = e
                    end
                end
            end
        end

        if cleaveTarget then
            print("[CLEAVE] Axe cleaves into " .. (cleaveTarget.name or cleaveTarget.id) .. "!")

            -- Deal 1 wound to cleave target
            self:applyDamage(cleaveTarget, 1, {}, nil, nil)

            -- Emit cleave event for visual feedback
            self.eventBus:emit("axe_cleave", {
                source = defeatedEntity,
                target = cleaveTarget,
            })
        end
    end

    return resolver
end

return M
