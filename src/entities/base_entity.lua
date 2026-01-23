-- base_entity.lua
-- Base Entity Component for Majesty
-- Ticket T1_5: Generic entity that can act or take damage
--
-- Design: Component tables, NOT deep inheritance.
-- An Adventurer is just an Entity + Bonds + Resolve, etc.

local M = {}

-- Import SUITS for attribute mapping
local constants = require('constants')
local SUITS = constants.SUITS

--------------------------------------------------------------------------------
-- CONDITION CONSTANTS
-- Using simple booleans for easy UI queries ("Red Flashing" effects)
--------------------------------------------------------------------------------
M.CONDITIONS = {
    STRESSED    = "stressed",
    STAGGERED   = "staggered",
    INJURED     = "injured",
    DEATHS_DOOR = "deaths_door",
}

--------------------------------------------------------------------------------
-- ENTITY FACTORY
--------------------------------------------------------------------------------

local nextId = 0

--- Create a new Entity
-- @param config table: { name, attributes, location, ... }
-- @return Entity instance
function M.createEntity(config)
    config = config or {}

    nextId = nextId + 1

    local entity = {
        -- Identity
        id   = config.id or ("entity_" .. nextId),
        name = config.name or "Unknown",

        -- Attributes: SUIT -> value (1-4 for PCs, 0-6 for NPCs)
        attributes = {
            [SUITS.SWORDS]    = config.swords or config.attributes and config.attributes[SUITS.SWORDS] or 1,
            [SUITS.PENTACLES] = config.pentacles or config.attributes and config.attributes[SUITS.PENTACLES] or 1,
            [SUITS.CUPS]      = config.cups or config.attributes and config.attributes[SUITS.CUPS] or 1,
            [SUITS.WANDS]     = config.wands or config.attributes and config.attributes[SUITS.WANDS] or 1,
        },

        -- Shorthand attribute access (for convenient entity.swords style access)
        swords    = config.swords or config.attributes and config.attributes[SUITS.SWORDS] or 1,
        pentacles = config.pentacles or config.attributes and config.attributes[SUITS.PENTACLES] or 1,
        cups      = config.cups or config.attributes and config.attributes[SUITS.CUPS] or 1,
        wands     = config.wands or config.attributes and config.attributes[SUITS.WANDS] or 1,

        -- Conditions: simple booleans for UI transparency
        conditions = {
            stressed    = false,
            staggered   = false,
            injured     = false,
            deaths_door = false,
            dead        = false,  -- Terminal state
        },

        -- Protection slots (for wound absorption)
        armorSlots = config.armorSlots or 0,  -- How many armor notches available
        armorNotches = 0,                      -- Current notches taken

        talentWoundSlots = config.talentWoundSlots or 2,  -- Max wounded talents (usually 2)
        woundedTalents = 0,                                -- Current wounded talents

        -- Talents table (empty for base mobs, populated for adventurers)
        -- Used to verify there are actual talents to wound
        talents = config.talents or {},

        -- Location reference (Room ID)
        location = config.location or nil,

        -- Zone within current room (T2_3)
        -- Simple assignment: entity.zone = "Balcony" (no coordinate systems)
        zone = config.zone or "main",

        -- Defensive action slot (S4.9)
        -- Holds a prepared defense: { type = "dodge"|"riposte", card = {...} }
        pendingDefense = nil,

        -- S12.3: Morale system
        baseMorale = config.baseMorale or 14,  -- Default morale for generic entities
        moraleModifier = 0,  -- Temporary modifiers from intimidation, rallying, etc.

        -- S12.4: Disposition system
        disposition = config.disposition or "distaste",  -- Default neutral-negative disposition

        -- Entity type flag
        isPC = config.isPC or false,

        -- NPC Health/Defense (HD) System (p. 125)
        -- NPCs use a simplified damage tracking: Defense absorbs first, then Health
        -- Example: HD 3/5 = 3 Health, 5 Defense
        -- PCs use the full wound track (armor → talents → staggered → injured → death's door)
        npcHealth = config.health or config.npcHealth or 3,      -- How much damage before Death's Door
        npcDefense = config.defense or config.npcDefense or 0,   -- Absorbs wounds before Health
        npcMaxHealth = config.health or config.npcHealth or 3,   -- For display/reset
        npcMaxDefense = config.defense or config.npcDefense or 0,

        -- Whether this NPC skips Death's Door on defeat (undead, constructs)
        instantDestruction = config.instantDestruction or false,
    }

    ----------------------------------------------------------------------------
    -- ATTRIBUTE ACCESS
    ----------------------------------------------------------------------------

    function entity:getAttribute(suit)
        return self.attributes[suit] or 0
    end

    function entity:setAttribute(suit, value)
        self.attributes[suit] = value
        return self
    end

    ----------------------------------------------------------------------------
    -- ZONE ACCESS (T2_3)
    ----------------------------------------------------------------------------

    function entity:getZone()
        return self.zone
    end

    function entity:setZone(zoneId)
        self.zone = zoneId
        return self
    end

    ----------------------------------------------------------------------------
    -- DEFENSIVE ACTIONS (S4.9)
    ----------------------------------------------------------------------------

    --- Prepare a defensive action for later in the round
    -- @param defenseType string: "dodge" or "riposte"
    -- @param card table: The card being used
    -- @return boolean: success
    function entity:prepareDefense(defenseType, card)
        if self.pendingDefense then
            return false, "already_has_defense"
        end

        self.pendingDefense = {
            type = defenseType,
            card = card,
            value = card.value or 0,
        }
        return true
    end

    --- Check if entity has a pending defense
    function entity:hasDefense()
        return self.pendingDefense ~= nil
    end

    --- Get the pending defense
    function entity:getDefense()
        return self.pendingDefense
    end

    --- Consume (use up) the pending defense
    -- @return table|nil: The defense that was consumed
    function entity:consumeDefense()
        local defense = self.pendingDefense
        self.pendingDefense = nil
        return defense
    end

    --- Clear the pending defense without using it
    function entity:clearDefense()
        self.pendingDefense = nil
    end

    ----------------------------------------------------------------------------
    -- CONDITION QUERIES (for UI)
    ----------------------------------------------------------------------------

    function entity:isStressed()
        return self.conditions.stressed
    end

    function entity:isStaggered()
        return self.conditions.staggered
    end

    function entity:isInjured()
        return self.conditions.injured
    end

    function entity:isAtDeathsDoor()
        return self.conditions.deaths_door
    end

    function entity:isAlive()
        return not self.conditions.deaths_door
    end

    ----------------------------------------------------------------------------
    -- CONDITION SETTERS
    ----------------------------------------------------------------------------

    function entity:setCondition(condition, value)
        if self.conditions[condition] ~= nil then
            self.conditions[condition] = value
        end
        return self
    end

    function entity:clearCondition(condition)
        return self:setCondition(condition, false)
    end

    ----------------------------------------------------------------------------
    -- TAKE WOUND (S7.7: Updated with damage types)
    -- Priority order: Notch Armor → Wound Talent → Staggered → Injured → Death's Door
    -- Returns: string describing what absorbed the wound, or nil if dead
    -- @param damageType string|boolean: "normal", "piercing", "critical", or legacy boolean
    --   - "normal" (or false/nil): Standard damage, full cascade
    --   - "piercing" (or true): Skip armor, start at talents
    --   - "critical": Skip armor, talents, staggered - go straight to injured
    ----------------------------------------------------------------------------

    function entity:takeWound(damageType)
        -- Handle legacy boolean parameter (true = piercing)
        if damageType == true then
            damageType = "piercing"
        elseif not damageType or damageType == false then
            damageType = "normal"
        end

        -- Branch: NPCs use simplified Health/Defense system (p. 125)
        if not self.isPC then
            return self:takeWoundNPC(damageType)
        end

        -- PC WOUND TRACK (full cascade)

        -- S7.7: Critical damage skips armor, talents, and staggered
        if damageType == "critical" then
            -- Go straight to injured cascade
            if not self.conditions.injured then
                self.conditions.injured = true
                return "injured"
            end

            if not self.conditions.deaths_door then
                self.conditions.deaths_door = true
                return "deaths_door"
            end

            self.conditions.dead = true
            return "dead"
        end

        -- Priority 1: Notch Armor (if available and not piercing/critical)
        if damageType == "normal" and self.armorSlots > 0 and self.armorNotches < self.armorSlots then
            self.armorNotches = self.armorNotches + 1
            return "armor_notched"
        end

        -- Priority 2: Wound a Talent (up to max, usually 2)
        -- Must have actual talents to wound, not just empty slots
        local talentCount = self.talents and #self.talents or 0
        if self.woundedTalents < self.talentWoundSlots and talentCount > 0 and self.woundedTalents < talentCount then
            self.woundedTalents = self.woundedTalents + 1
            return "talent_wounded"
        end

        -- Priority 3: Mark Staggered (if not already)
        if not self.conditions.staggered then
            self.conditions.staggered = true
            return "staggered"
        end

        -- Priority 4: Mark Injured (if not already)
        if not self.conditions.injured then
            self.conditions.injured = true
            return "injured"
        end

        -- Priority 5: Mark Death's Door
        if not self.conditions.deaths_door then
            self.conditions.deaths_door = true
            return "deaths_door"
        end

        -- Already at Death's Door - this wound is fatal
        self.conditions.dead = true
        return "dead"
    end

    ----------------------------------------------------------------------------
    -- NPC HEALTH/DEFENSE SYSTEM (p. 125)
    -- Simplified damage tracking for GM's characters:
    -- - Defense reduced first (like armor, scales, thick hide)
    -- - When Defense = 0, reduce Health
    -- - Piercing bypasses Defense, hits Health directly
    -- - Critical bypasses Defense, hits Health directly
    -- - Health = 0 → Death's Door (or instant destruction for undead/constructs)
    ----------------------------------------------------------------------------

    function entity:takeWoundNPC(damageType)
        -- Piercing and Critical bypass Defense, hit Health directly
        local bypassDefense = (damageType == "piercing" or damageType == "critical")

        -- Normal damage: reduce Defense first
        if not bypassDefense and self.npcDefense > 0 then
            self.npcDefense = self.npcDefense - 1
            return "defense_reduced"
        end

        -- Reduce Health
        if self.npcHealth > 0 then
            self.npcHealth = self.npcHealth - 1

            if self.npcHealth <= 0 then
                -- Health depleted
                if self.instantDestruction then
                    -- Undead, constructs, etc. - skip Death's Door
                    self.conditions.dead = true
                    return "destroyed"
                else
                    -- Living creatures go to Death's Door
                    self.conditions.deaths_door = true
                    return "deaths_door"
                end
            end
            return "health_reduced"
        end

        -- Already at 0 Health (Death's Door) - another wound is fatal
        self.conditions.dead = true
        return "dead"
    end

    --- Get NPC's current HD string for display (e.g., "HD: 2/3")
    function entity:getHDString()
        return string.format("HD: %d/%d", self.npcHealth, self.npcDefense)
    end

    --- Get NPC's full HD info
    function entity:getHD()
        return {
            health = self.npcHealth,
            defense = self.npcDefense,
            maxHealth = self.npcMaxHealth,
            maxDefense = self.npcMaxDefense,
        }
    end

    ----------------------------------------------------------------------------
    -- HEALING
    -- Note: Stress is a "Recovery Gate" (p. 31) - must clear stress first
    ----------------------------------------------------------------------------

    --- Attempt to heal a wound
    -- @return string, string: result, errorReason (if blocked by stress)
    function entity:healWound()
        -- Stress Gate Check (p. 31): Cannot clear any condition until stressed is removed
        if self.conditions.stressed then
            return nil, "must_clear_stress_first"
        end

        -- Reverse priority: Death's Door → Injured → Staggered → Talents → Armor
        if self.conditions.deaths_door then
            self.conditions.deaths_door = false
            return "deaths_door_healed", nil
        end

        if self.conditions.injured then
            self.conditions.injured = false
            return "injured_healed", nil
        end

        if self.conditions.staggered then
            self.conditions.staggered = false
            return "staggered_healed", nil
        end

        if self.woundedTalents > 0 then
            self.woundedTalents = self.woundedTalents - 1
            return "talent_healed", nil
        end

        if self.armorNotches > 0 then
            self.armorNotches = self.armorNotches - 1
            return "armor_repaired", nil
        end

        return "fully_healed", nil
    end

    --- Clear stress condition (separate from wound healing)
    -- Stress must be cleared before other conditions can heal
    function entity:clearStress()
        if self.conditions.stressed then
            self.conditions.stressed = false
            return true
        end
        return false
    end

    ----------------------------------------------------------------------------
    -- S12.3: MORALE SYSTEM
    ----------------------------------------------------------------------------

    --- Calculate the entity's current wounds taken
    -- @return number: Total wound levels sustained
    function entity:getWoundsTaken()
        local wounds = 0
        wounds = wounds + self.armorNotches
        wounds = wounds + self.woundedTalents
        if self.conditions.staggered then wounds = wounds + 1 end
        if self.conditions.injured then wounds = wounds + 1 end
        if self.conditions.deaths_door then wounds = wounds + 1 end
        return wounds
    end

    --- Calculate current morale
    -- @param context table: Optional battle context { allies, enemies, defeatedAllies }
    -- @return number: Current morale value
    function entity:getMorale(context)
        context = context or {}

        local morale = self.baseMorale or 14

        -- Penalty for wounds taken (-2 per wound level)
        local wounds = self:getWoundsTaken()
        morale = morale - (wounds * 2)

        -- Penalty for defeated allies (-3 per defeated ally)
        local defeatedAllies = context.defeatedAllies or 0
        morale = morale - (defeatedAllies * 3)

        -- Bonus for wounded enemies (+1 per wounded PC)
        local woundedEnemies = context.woundedEnemies or 0
        morale = morale + woundedEnemies

        -- Apply temporary modifier (from Intimidate, Rally, etc.)
        morale = morale + (self.moraleModifier or 0)

        -- Minimum morale of 1 (unless completely broken)
        return math.max(1, morale)
    end

    --- Modify morale temporarily (e.g., from Intimidate)
    -- @param amount number: Amount to add (negative to reduce)
    function entity:modifyMorale(amount)
        self.moraleModifier = (self.moraleModifier or 0) + amount
    end

    --- Clear temporary morale modifiers
    function entity:clearMoraleModifier()
        self.moraleModifier = 0
    end

    ----------------------------------------------------------------------------
    -- S12.4: DISPOSITION SYSTEM
    ----------------------------------------------------------------------------

    --- Get current disposition
    function entity:getDisposition()
        return self.disposition or "distaste"
    end

    --- Set disposition directly
    function entity:setDisposition(newDisposition)
        self.disposition = newDisposition
    end

    --- Shift disposition (uses disposition module if available)
    -- @param direction number: 1 for clockwise, -1 for counter-clockwise
    -- @param amount number: Steps to shift (default 1)
    function entity:shiftDisposition(direction, amount)
        amount = amount or 1
        -- Simple wheel implementation (full module loaded elsewhere)
        local wheel = { "anger", "distaste", "sadness", "joy", "surprise", "trust", "fear" }
        local index = 1
        for i, d in ipairs(wheel) do
            if d == self.disposition then
                index = i
                break
            end
        end
        index = index + (direction * amount)
        while index < 1 do index = index + #wheel end
        while index > #wheel do index = index - #wheel end
        self.disposition = wheel[index]
    end

    ----------------------------------------------------------------------------
    -- UTILITY
    ----------------------------------------------------------------------------

    --- Get count of available wound absorption slots
    function entity:remainingProtection()
        -- NPCs use Health/Defense system
        if not self.isPC then
            return self.npcDefense + self.npcHealth
        end

        -- PCs use full wound track
        local remaining = 0

        -- Armor slots
        remaining = remaining + (self.armorSlots - self.armorNotches)

        -- Talent wound slots (limited by actual talent count)
        local talentCount = self.talents and #self.talents or 0
        local availableTalentSlots = math.min(self.talentWoundSlots, talentCount)
        remaining = remaining + (availableTalentSlots - self.woundedTalents)

        -- Condition slots (staggered, injured)
        if not self.conditions.staggered then remaining = remaining + 1 end
        if not self.conditions.injured then remaining = remaining + 1 end

        return remaining
    end

    --- How many wounds until death?
    function entity:woundsUntilDeath()
        if self.conditions.dead then
            return 0
        end

        if self.conditions.deaths_door then
            return 0
        end

        -- NPCs: Defense + Health
        if not self.isPC then
            if self.instantDestruction then
                return self.npcDefense + self.npcHealth
            else
                return self.npcDefense + self.npcHealth + 1  -- +1 for death's door
            end
        end

        -- PCs: full protection + 1 for death's door
        return self:remainingProtection() + 1
    end

    return entity
end

return M
