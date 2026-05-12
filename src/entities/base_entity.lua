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

local function countEntries(tableValue)
    local count = 0
    if not tableValue then
        return count
    end

    for _ in pairs(tableValue) do
        count = count + 1
    end

    return count
end

local function countWoundedTalents(talents)
    local count = 0
    for _, talent in pairs(talents or {}) do
        if type(talent) == "table" and talent.wounded then
            count = count + 1
        end
    end
    return count
end

local function sortedTalentIds(talents)
    local ids = {}
    if not talents then
        return ids
    end

    for id in pairs(talents) do
        ids[#ids + 1] = id
    end

    table.sort(ids, function(a, b)
        return tostring(a) < tostring(b)
    end)

    return ids
end

local function woundNextTalent(entity)
    for _, talentId in ipairs(sortedTalentIds(entity.talents)) do
        local talent = entity.talents[talentId]
        if type(talent) == "table" and not talent.wounded then
            talent.wounded = true
            entity._woundedTalentOrder = entity._woundedTalentOrder or {}
            entity._woundedTalentOrder[#entity._woundedTalentOrder + 1] = talentId
            return talentId
        end
    end

    return nil
end

local function woundSpecificTalent(entity, talentId)
    if not entity or not talentId then
        return nil
    end

    local talent = entity.talents and entity.talents[talentId]
    if type(talent) == "table" and not talent.wounded then
        talent.wounded = true
        entity._woundedTalentOrder = entity._woundedTalentOrder or {}
        entity._woundedTalentOrder[#entity._woundedTalentOrder + 1] = talentId
        return talentId
    end

    return nil
end

local function hasAvailableTalentWound(entity)
    if not entity then
        return false
    end

    local talentCount = entity.getTalentCount and entity:getTalentCount() or countEntries(entity.talents)
    if entity.woundedTalents >= entity.talentWoundSlots or entity.woundedTalents >= talentCount then
        return false
    end

    for _, talentId in ipairs(sortedTalentIds(entity.talents)) do
        local talent = entity.talents[talentId]
        if type(talent) == "table" and not talent.wounded then
            return true
        end
    end

    return false
end

local function normalizeDamageType(damageType)
    if damageType == true then
        return "piercing"
    end
    if not damageType or damageType == false then
        return "normal"
    end
    return damageType
end

local function normalizeWoundChoice(choice)
    if not choice then
        return nil
    end

    choice = tostring(choice):lower()
    choice = choice:gsub("[’']", "")
    choice = choice:gsub("%s+", "_")
    choice = choice:gsub("[^%w_]", "")

    if choice == "armor" or choice == "armor_notched" or choice == "notch_armor" or
       choice == "notch" or choice == "shield" or choice == "helm" then
        return "armor"
    end
    if choice == "talent" or choice == "wound_talent" or choice == "talent_wounded" then
        return "talent"
    end
    if choice == "stagger" or choice == "staggered" then
        return "staggered"
    end
    if choice == "injury" or choice == "injured" then
        return "injured"
    end
    if choice == "deaths_door" or choice == "death_door" or choice == "death" then
        return "deaths_door"
    end

    return choice
end

local function healLastWoundedTalent(entity)
    local order = entity._woundedTalentOrder
    while order and #order > 0 do
        local talentId = table.remove(order)
        local talent = entity.talents and entity.talents[talentId]
        if type(talent) == "table" and talent.wounded then
            talent.wounded = false
            return talentId
        end
    end

    for _, talentId in ipairs(sortedTalentIds(entity.talents)) do
        local talent = entity.talents[talentId]
        if type(talent) == "table" and talent.wounded then
            talent.wounded = false
            return talentId
        end
    end

    return nil
end

local function clearWitheringAging(entity)
    if not entity or not entity.conditions then
        return
    end

    entity.conditions.witheringAging = false
    entity.conditions.magicallyAged = false
    if entity.witheringAging then
        entity.witheringAging.active = false
        entity.witheringAging.healed = true
    end
end

local function healingBlockWoundTypesInclude(block, woundType)
    if not block or block.active == false then
        return false
    end
    local woundTypes = block.woundTypes
    if not woundTypes then
        return true
    end
    if type(woundTypes) == "string" then
        return woundTypes == woundType
    end
    if type(woundTypes) == "table" then
        if woundTypes[woundType] == true then
            return true
        end
        for _, blockedType in ipairs(woundTypes) do
            if blockedType == woundType then
                return true
            end
        end
    end
    return false
end

local function getHealingBlock(entity, woundType)
    if not entity or not woundType then
        return nil
    end
    if healingBlockWoundTypesInclude(entity.healingBlock, woundType) then
        return entity.healingBlock
    end
    for _, block in ipairs(entity.healingBlocks or {}) do
        if healingBlockWoundTypesInclude(block, woundType) then
            return block
        end
    end
    return nil
end

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

    local initialWoundedTalents = countWoundedTalents(config.talents)
    if initialWoundedTalents == 0 and config.woundedTalents then
        initialWoundedTalents = config.woundedTalents
    end

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
        woundedTalents = initialWoundedTalents,            -- Current wounded talents

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
        dispositionSeverity = config.dispositionSeverity or config.disposition_severity or 2,

        -- Entity type flag
        isPC = config.isPC or false,

        -- Kin/species metadata for kin-specific talents and authored procedures.
        kin = config.kin or config.kith or config.species or config.race or config.ancestry,
        kith = config.kith,
        species = config.species,
        race = config.race,
        ancestry = config.ancestry,

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

        -- Whether this NPC ignores the normal HD wound track.
        infiniteHealth = config.infiniteHealth or false,
        neverTakesWounds = config.neverTakesWounds or false,
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
    -- @param value number|nil: The prepared reveal value
    -- @return boolean, string|nil, table|nil: success, error, replaced defense
    function entity:prepareDefense(defenseType, card, value)
        local replaced = self.pendingDefense
        local faceValue = card.value or 0

        self.pendingDefense = {
            type = defenseType,
            card = card,
            value = value or faceValue,
            faceValue = faceValue,
            modifier = (value or faceValue) - faceValue,
        }
        return true, nil, replaced
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
        return not (self.conditions.dead or self.conditions.deaths_door)
    end

    ----------------------------------------------------------------------------
    -- CONDITION SETTERS
    ----------------------------------------------------------------------------

    function entity:markDeathsDoor(currentWatch)
        if self.conditions.dead then
            return false, "dead"
        end

        self.conditions.deaths_door = true
        self.deathDoorExpired = nil
        self.deathDoorExpiredWatch = nil

        local watchNumber = tonumber(currentWatch)
        if watchNumber then
            self.deathDoorWatchStarted = watchNumber
            self.deathDoorExpiresAtWatch = watchNumber + 1
        end

        return true
    end

    function entity:clearDeathsDoor()
        self.conditions.deaths_door = false
        self.deathDoorWatchStarted = nil
        self.deathDoorExpiresAtWatch = nil
        self.deathDoorExpired = nil
        self.deathDoorExpiredWatch = nil
        return self
    end

    function entity:expireDeathsDoor(currentWatch)
        if self.conditions.dead or not self.conditions.deaths_door then
            return false
        end

        local watchNumber = tonumber(currentWatch)
        if not watchNumber then
            return false
        end

        if not self.deathDoorExpiresAtWatch then
            local started = tonumber(self.deathDoorWatchStarted)
            if not started then
                started = watchNumber > 0 and (watchNumber - 1) or watchNumber
                self.deathDoorWatchStarted = started
            end
            self.deathDoorExpiresAtWatch = started + 1
        end

        if watchNumber >= self.deathDoorExpiresAtWatch then
            self.conditions.dead = true
            self.deathDoorExpired = true
            self.deathDoorExpiredWatch = watchNumber
            return true
        end

        return false
    end

    function entity:scheduleUndeadRise(undeadType, currentWatch, options)
        options = options or {}

        local watchNumber = tonumber(currentWatch)
        local riseAtWatch = watchNumber and (watchNumber + 1) or nil

        self.undeadRise = {
            type = undeadType or "zombie",
            riseAtWatch = riseAtWatch,
            reason = options.reason,
            bodyDestroyed = options.bodyDestroyed or false,
            immediate = options.immediate or false,
            raised = false,
        }

        return self.undeadRise
    end

    function entity:markUndeadRaised(undeadEntity, currentWatch)
        self.undeadRise = self.undeadRise or {
            type = undeadEntity and undeadEntity.blueprintId or "zombie",
        }
        self.undeadRise.raised = true
        self.undeadRise.raisedAtWatch = tonumber(currentWatch)
        self.undeadRise.entity = undeadEntity
        self.raisedAsUndead = true
        self.raisedUndeadEntity = undeadEntity
        return undeadEntity
    end

    function entity:setCondition(condition, value)
        if condition == M.CONDITIONS.DEATHS_DOOR or condition == "deaths_door" then
            if value then
                self:markDeathsDoor()
            else
                self:clearDeathsDoor()
            end
            return self
        end

        if self.conditions[condition] ~= nil then
            self.conditions[condition] = value
        end
        return self
    end

    function entity:clearCondition(condition)
        return self:setCondition(condition, false)
    end

    ----------------------------------------------------------------------------
    -- TALENT ACCESS
    ----------------------------------------------------------------------------

    function entity:getTalentCount()
        return countEntries(self.talents)
    end

    function entity:getAvailableWoundChoices(damageType)
        damageType = normalizeDamageType(damageType)

        if not self.isPC then
            return {}
        end

        if self.conditions.deaths_door then
            return {}
        end

        if damageType == "critical" then
            if self.conditions.injured then
                return { "deaths_door" }
            end
            return { "injured" }
        end

        if self.conditions.injured then
            return { "deaths_door" }
        end

        local choices = {}
        if damageType == "normal" and self.armorSlots > 0 and self.armorNotches < self.armorSlots then
            choices[#choices + 1] = "armor"
        end
        if hasAvailableTalentWound(self) then
            choices[#choices + 1] = "talent"
        end
        if not self.conditions.staggered then
            choices[#choices + 1] = "staggered"
        end
        if not self.conditions.injured then
            choices[#choices + 1] = "injured"
        end
        if not self.conditions.deaths_door then
            choices[#choices + 1] = "deaths_door"
        end

        return choices
    end

    function entity:canTakeWoundChoice(choice, damageType)
        choice = normalizeWoundChoice(choice)
        damageType = normalizeDamageType(damageType)

        if not self.isPC then
            return false, "npc_wound_track"
        end
        if self.conditions.deaths_door then
            return false, "already_at_deaths_door"
        end
        if damageType == "critical" then
            if self.conditions.injured then
                return choice == "deaths_door", "critical_forced"
            end
            return choice == "injured", "critical_forced"
        end
        if self.conditions.injured then
            return choice == "deaths_door", "injured_forces_deaths_door"
        end
        if choice == "armor" then
            if damageType == "piercing" then
                return false, "piercing_ignores_armor"
            end
            return self.armorSlots > 0 and self.armorNotches < self.armorSlots, "armor_unavailable"
        end
        if choice == "talent" then
            return hasAvailableTalentWound(self), "talent_unavailable"
        end
        if choice == "staggered" then
            return not self.conditions.staggered, "already_staggered"
        end
        if choice == "injured" then
            return not self.conditions.injured, "already_injured"
        end
        if choice == "deaths_door" then
            return not self.conditions.deaths_door, "already_at_deaths_door"
        end

        return false, "unknown_wound_choice"
    end

    function entity:applyWoundChoice(choice, options)
        choice = normalizeWoundChoice(choice)
        options = options or {}

        if choice == "armor" then
            self.armorNotches = self.armorNotches + 1
            return "armor_notched"
        end

        if choice == "talent" then
            local woundedTalent = woundSpecificTalent(self, options.talentId)
            if not woundedTalent then
                woundedTalent = woundNextTalent(self)
            end
            if woundedTalent then
                self.woundedTalents = self.woundedTalents + 1
                return "talent_wounded"
            end
            return nil
        end

        if choice == "staggered" then
            self.conditions.staggered = true
            return "staggered"
        end

        if choice == "injured" then
            self.conditions.injured = true
            return "injured"
        end

        if choice == "deaths_door" then
            self:markDeathsDoor(options.currentWatch or options.watchNumber)
            return "deaths_door"
        end

        return nil
    end

    ----------------------------------------------------------------------------
    -- TAKE WOUND (S7.7: Updated with damage types)
    -- PCs can explicitly choose any legal wound option; if no choice is given,
    -- the legacy automatic order is used as a deterministic default.
    -- Returns: string describing what absorbed the wound, or nil if dead
    -- @param damageType string|boolean: "normal", "piercing", "critical", or legacy boolean
    --   - "normal" (or false/nil): Standard damage, full cascade
    --   - "piercing" (or true): Skip armor, start at talents
    --   - "critical": Skip armor, talents, staggered - go straight to injured
    -- @param options table: Optional { choice = "armor"|"talent"|"staggered"|"injured"|"deaths_door", talentId = string, currentWatch = number }
    ----------------------------------------------------------------------------

    function entity:takeWound(damageType, options)
        if type(damageType) == "table" then
            options = damageType
            damageType = options.damageType or options.type
        end
        options = options or {}
        damageType = normalizeDamageType(damageType)

        -- Branch: NPCs use simplified Health/Defense system (p. 125)
        if not self.isPC then
            return self:takeWoundNPC(damageType)
        end

        -- PC WOUND TRACK

        -- S7.7: Critical damage skips armor, talents, and staggered
        if damageType == "critical" then
            if self.conditions.deaths_door then
                self.conditions.dead = true
                return "dead"
            elseif self.conditions.injured then
                self:markDeathsDoor(options.currentWatch or options.watchNumber)
                return "deaths_door"
            else
                self.conditions.injured = true
                return "injured"
            end
        end

        -- If already at Death's Door, any further Wound is fatal.
        if self.conditions.deaths_door then
            self.conditions.dead = true
            return "dead"
        end

        -- Rulebook p. 124: if already Injured, the next Wound marks Death's Door.
        if self.conditions.injured then
            self:markDeathsDoor(options.currentWatch or options.watchNumber)
            return "deaths_door"
        end

        local requestedChoice = normalizeWoundChoice(options.choice or options.woundChoice)
        if requestedChoice then
            local canChoose = self:canTakeWoundChoice(requestedChoice, damageType)
            if canChoose then
                local chosenResult = self:applyWoundChoice(requestedChoice, options)
                if chosenResult then
                    return chosenResult
                end
            end
        end

        -- Default 1: Notch Armor (if available and not piercing/critical)
        if damageType == "normal" and self.armorSlots > 0 and self.armorNotches < self.armorSlots then
            self.armorNotches = self.armorNotches + 1
            return "armor_notched"
        end

        -- Default 2: Wound a Talent (up to max, usually 2)
        -- Must have actual talents to wound, not just empty slots
        if hasAvailableTalentWound(self) then
            local woundedTalent = woundNextTalent(self)
            if woundedTalent then
                self.woundedTalents = self.woundedTalents + 1
                return "talent_wounded"
            end
        end

        -- Default 3: Mark Staggered (if not already)
        if not self.conditions.staggered then
            self.conditions.staggered = true
            return "staggered"
        end

        -- Default 4: Mark Injured (if not already)
        if not self.conditions.injured then
            self.conditions.injured = true
            return "injured"
        end

        -- Default 5: Mark Death's Door
        if not self.conditions.deaths_door then
            self:markDeathsDoor(options.currentWatch or options.watchNumber)
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
        if self.infiniteHealth or self.neverTakesWounds then
            return "invulnerable"
        end

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
                    self:markDeathsDoor()
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
        if self.conditions.dead then
            return nil, "dead"
        end

        -- Death's Door is special: any Heal effect saves the character,
        -- wakes them, marks Stressed, and clears Death's Door.
        if self.conditions.deaths_door then
            self:clearDeathsDoor()
            self.conditions.stressed = true
            clearWitheringAging(self)
            return "deaths_door_healed", nil
        end

        -- Stress Gate Check (p. 31): Cannot clear any condition until stressed is removed
        if self.conditions.stressed then
            return nil, "must_clear_stress_first"
        end

        -- Reverse priority: Death's Door → Injured → Staggered → Talents → Armor
        if self.conditions.injured then
            if getHealingBlock(self, "injured") then
                return nil, "healing_blocked"
            end
            self.conditions.injured = false
            clearWitheringAging(self)
            return "injured_healed", nil
        end

        if self.conditions.staggered then
            self.conditions.staggered = false
            clearWitheringAging(self)
            return "staggered_healed", nil
        end

        if self.woundedTalents > 0 then
            if getHealingBlock(self, "talent") then
                return nil, "healing_blocked"
            end
            self.woundedTalents = self.woundedTalents - 1
            healLastWoundedTalent(self)
            clearWitheringAging(self)
            return "talent_healed", nil
        end

        if self.armorNotches > 0 then
            self.armorNotches = self.armorNotches - 1
            clearWitheringAging(self)
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
    function entity:setDisposition(newDisposition, severity)
        local ok, dispositionModule = pcall(require, 'logic.disposition')
        if ok and dispositionModule and dispositionModule.parseDisposition then
            local parsedDisposition, parsedSeverity = dispositionModule.parseDisposition(newDisposition, severity)
            self.disposition = parsedDisposition
            self.dispositionSeverity = parsedSeverity
            return
        end

        self.disposition = newDisposition
        self.dispositionSeverity = severity or self.dispositionSeverity or 2
    end

    function entity:getDispositionSeverity()
        return self.dispositionSeverity or 2
    end

    function entity:getDispositionLabel()
        local ok, dispositionModule = pcall(require, 'logic.disposition')
        if ok and dispositionModule and dispositionModule.getDispositionLabel then
            return dispositionModule.getDispositionLabel(self.disposition, self.dispositionSeverity)
        end
        return self.disposition or "distaste"
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
        local talentCount = self:getTalentCount()
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
