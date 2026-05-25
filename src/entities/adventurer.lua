-- adventurer.lua
-- Adventurer Schema (PC Specialization) for Majesty
-- Ticket T1_6: Extends Entity with Resolve, Motifs, Bonds, Talents
--
-- Design: Composition over inheritance.
-- An Adventurer wraps a base Entity and adds PC-specific components.

local base_entity = require('entities.base_entity')

local M = {}

local function normalizeTalentData(data)
    if type(data) == "table" then
        local normalized = {}
        for key, value in pairs(data) do
            normalized[key] = value
        end
        normalized.mastered = normalized.mastered or false
        normalized.wounded = normalized.wounded or false
        normalized.xp_invested = normalized.xp_invested or 0
        return normalized
    end

    return {
        mastered    = data == true,
        wounded     = false,
        xp_invested = 0,
    }
end

local function normalizeTalents(talents)
    local normalized = {}

    for key, data in pairs(talents or {}) do
        if type(key) == "number" then
            local talentId = type(data) == "table" and (data.id or data.talentId) or data
            if talentId then
                normalized[talentId] = normalizeTalentData(data)
            end
        else
            normalized[key] = normalizeTalentData(data)
        end
    end

    return normalized
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

local function removeWoundedTalentOrder(entity, talentId)
    local order = entity and entity._woundedTalentOrder
    if not order then
        return
    end

    for i = #order, 1, -1 do
        if order[i] == talentId then
            table.remove(order, i)
            return
        end
    end
end

local function maxTalentWounds(entity)
    local talentCount = entity.getTalentCount and entity:getTalentCount() or 0
    return math.min(entity.talentWoundSlots or talentCount, talentCount)
end

local function normalizeBondKey(value)
    local normalized = tostring(value or ""):lower()
    normalized = normalized:gsub("[’']", "")
    normalized = normalized:gsub("[^%w]+", "_")
    normalized = normalized:gsub("^_+", ""):gsub("_+$", "")
    local aliases = {
        ally_bond = "ally",
        friendship = "ally",
        friend = "ally",
        adversary_bond = "adversary",
        enemy = "adversary",
        big = "big_little",
        little = "big_little",
        big_and_little = "big_little",
        big_little_bond = "big_little",
        best_friend_bond = "best_friend",
        love_bond = "love",
        lovers = "love",
        master = "master_henchman",
        henchman = "master_henchman",
        master_henchman_bond = "master_henchman",
        mentor = "mentor_mentee",
        mentee = "mentor_mentee",
        mentor_mentee_bond = "mentor_mentee",
        rivalry = "rival",
        rival_bond = "rival",
        sibling_bond = "sibling",
        unrequited = "unrequited_love",
        unrequited_love_bond = "unrequited_love",
        guardianship = "ward",
        ward_bond = "ward",
    }
    return aliases[normalized] or normalized
end

--------------------------------------------------------------------------------
-- BOND STATUS CONSTANTS
--------------------------------------------------------------------------------
M.BOND_STATUS = {
    ALLY            = "ally",
    ADVERSARY       = "adversary",
    BIG_LITTLE      = "big_little",
    BEST_FRIEND     = "best_friend",
    LOVE            = "love",
    MASTER_HENCHMAN = "master_henchman",
    MENTOR_MENTEE   = "mentor_mentee",
    RIVAL           = "rival",
    SIBLING         = "sibling",
    WARD            = "ward",
    GUARDIANSHIP    = "guardianship",
    RIVALRY         = "rivalry",
    FRIENDSHIP      = "friendship",
    UNREQUITED_LOVE = "unrequited_love",
    DEBT            = "debt",
}

M.BOND_CATALOG = {
    ally = {
        name = "Ally",
        chargeTrigger = "Charge when you make your ally laugh in and out of character.",
    },
    adversary = {
        name = "Adversary",
        chargeTrigger = "Charge when you witness your adversary fail a test of fate.",
    },
    big_little = {
        name = "Big/Little",
        chargeTrigger = "Both charge when your big/little aids you in a test of fate with your weakest attribute.",
    },
    best_friend = {
        name = "Best Friend",
        chargeTrigger = "Both charge when you reveal a secret to your best friend.",
    },
    love = {
        name = "Love",
        chargeTrigger = "Charge when you do something gushy and romantic for your partner.",
    },
    master_henchman = {
        name = "Master/Henchman",
        chargeTrigger = "Masters charge when they compensate their henchman; henchmen charge when using a Camp Action to benefit their master but not themselves.",
    },
    mentor_mentee = {
        name = "Mentor/Mentee",
        chargeTrigger = "Mentees charge when they ask for advice and receive it; mentors charge when a mentee follows their advice.",
    },
    rival = {
        name = "Rival",
        chargeTrigger = "Charge when you witness your rival succeed on a test of fate.",
    },
    sibling = {
        name = "Sibling",
        chargeTrigger = "Charge when you provide aid to your sibling in a test of fate.",
    },
    unrequited_love = {
        name = "Unrequited Love",
        chargeTrigger = "Charge when you do something kind for your love and they rebuff you or turn you down.",
    },
    ward = {
        name = "Ward",
        chargeTrigger = "Charge when your ward survives an entire Challenge without taking a Wound.",
    },
}

function M.normalizeBondStatus(status)
    local normalized = normalizeBondKey(status)
    if M.BOND_CATALOG[normalized] then
        return normalized
    end
    return nil
end

function M.getBondInfo(status)
    local normalized = M.normalizeBondStatus(status)
    local info = normalized and M.BOND_CATALOG[normalized]
    if not info then
        return nil
    end
    return {
        id = normalized,
        name = info.name,
        chargeTrigger = info.chargeTrigger,
    }
end

function M.applyBondMetadata(bond, status)
    if type(bond) ~= "table" then
        return nil
    end
    local info = M.getBondInfo(status or bond.status or bond.bondType)
    if info then
        bond.bondType = info.id
        bond.rulebookName = info.name
        bond.chargeTrigger = info.chargeTrigger
    end
    return info
end

--------------------------------------------------------------------------------
-- ADVENTURER FACTORY
--------------------------------------------------------------------------------

--- Create a new Adventurer (Player Character)
-- @param config table: Entity config plus PC-specific fields
-- @return Adventurer instance (Entity + PC components)
function M.createAdventurer(config)
    config = config or {}

    -- Create base entity first
    local adventurer = base_entity.createEntity(config)

    -- Mark as player character
    adventurer.isPC = true

    ----------------------------------------------------------------------------
    -- RESOLVE
    -- Default 4/4, but max is mutable (War Stories talent allows 5)
    ----------------------------------------------------------------------------
    adventurer.resolve = {
        current = config.resolve or 4,
        max     = config.resolveMax or 4,
    }

    -- Lore bids refresh to 4 in camp; initialize to 4 for fresh expeditions.
    adventurer.loreBids = config.loreBids or 4

    --- Spend resolve points
    -- @param amount number: How much to spend
    -- @return boolean: true if successful, false if insufficient
    function adventurer:spendResolve(amount)
        amount = amount or 1
        if self.resolve.current < amount then
            return false, "insufficient_resolve"
        end
        self.resolve.current = self.resolve.current - amount
        return true
    end

    --- Regain resolve points (capped at max)
    function adventurer:regainResolve(amount)
        amount = amount or 1
        self.resolve.current = math.min(
            self.resolve.current + amount,
            self.resolve.max
        )
        return self
    end

    --- Check if resolve is available
    function adventurer:hasResolve(amount)
        amount = amount or 1
        return self.resolve.current >= amount
    end

    --- Set max resolve (for talents like War Stories)
    function adventurer:setMaxResolve(newMax)
        self.resolve.max = newMax
        -- Don't exceed new max
        if self.resolve.current > newMax then
            self.resolve.current = newMax
        end
        return self
    end

    ----------------------------------------------------------------------------
    -- MOTIFS
    -- Strings representing character background (Failed Career, Origin, etc.)
    -- Used for Favor on related tests
    ----------------------------------------------------------------------------
    adventurer.motifs = config.motifs or {}

    --- Add a motif
    function adventurer:addMotif(motif)
        self.motifs[#self.motifs + 1] = motif
        return self
    end

    --- Check if adventurer has a motif (case-insensitive partial match)
    function adventurer:hasMotif(searchTerm)
        local searchLower = string.lower(searchTerm)
        for _, motif in ipairs(self.motifs) do
            if string.find(string.lower(motif), searchLower, 1, true) then
                return true, motif
            end
        end
        return false
    end

    --- Get all motifs
    function adventurer:getMotifs()
        return self.motifs
    end

    ----------------------------------------------------------------------------
    -- BONDS
    -- Maps entity_id -> { status, charged }
    -- Bonds power rest/recovery mechanics
    ----------------------------------------------------------------------------
    adventurer.bonds = config.bonds or {}
    for _, bond in pairs(adventurer.bonds) do
        M.applyBondMetadata(bond)
    end

    --- Create or update a bond with another entity
    -- @param entityId string: The other entity's ID
    -- @param status string: One of BOND_STATUS constants
    function adventurer:setBond(entityId, status)
        if not self.bonds[entityId] then
            self.bonds[entityId] = { status = status, charged = false }
        else
            self.bonds[entityId].status = status
        end
        M.applyBondMetadata(self.bonds[entityId], status)
        return self
    end

    --- Charge a bond (usually during Crawl phase)
    function adventurer:chargeBond(entityId)
        if self.bonds[entityId] then
            self.bonds[entityId].charged = true
            return true
        end
        return false
    end

    --- Spend a charged bond (during Camp phase for healing)
    -- @return boolean: true if bond was charged and is now spent
    function adventurer:spendBond(entityId)
        if self.bonds[entityId] and self.bonds[entityId].charged then
            self.bonds[entityId].charged = false
            return true
        end
        return false
    end

    --- Check if a bond is charged
    function adventurer:isBondCharged(entityId)
        return self.bonds[entityId] and self.bonds[entityId].charged or false
    end

    --- Get bond info
    function adventurer:getBond(entityId)
        return self.bonds[entityId]
    end

    --- Count charged bonds
    function adventurer:countChargedBonds()
        local count = 0
        for _, bond in pairs(self.bonds) do
            if bond.charged then
                count = count + 1
            end
        end
        return count
    end

    ----------------------------------------------------------------------------
    -- TALENTS
    -- Maps talent_id -> { mastered, wounded, xp_invested }
    -- NO hardcoded talent logic here - just data storage
    -- ChallengeManager will look up what talents actually do
    ----------------------------------------------------------------------------
    adventurer.talents = normalizeTalents(config.talents)
    adventurer.woundedTalents = countWoundedTalents(adventurer.talents)

    --- Add a talent
    -- @param talentId string: The talent's ID (e.g., "aegis", "war_stories")
    -- @param mastered boolean: Whether it's mastered (default false = in training)
    function adventurer:addTalent(talentId, mastered)
        self.talents[talentId] = {
            mastered    = mastered or false,
            wounded     = false,
            xp_invested = 0,
        }
        return self
    end

    --- Check if adventurer has a talent
    function adventurer:hasTalent(talentId)
        return self.talents[talentId] ~= nil
    end

    --- Check if talent is mastered
    function adventurer:isTalentMastered(talentId)
        return self.talents[talentId] and self.talents[talentId].mastered or false
    end

    --- Check if talent is wounded
    function adventurer:isTalentWounded(talentId)
        return self.talents[talentId] and self.talents[talentId].wounded or false
    end

    --- Check if talent is usable (has it, mastered or in-training, not wounded)
    function adventurer:canUseTalent(talentId)
        local talent = self.talents[talentId]
        if not talent then return false end
        if talent.wounded then return false end
        return true
    end

    --- Wound a specific talent
    function adventurer:woundTalent(talentId)
        local talent = self.talents[talentId]
        if not talent then
            return false
        end

        if type(talent) ~= "table" then
            talent = normalizeTalentData(talent)
            self.talents[talentId] = talent
        end

        if talent.wounded then
            self.woundedTalents = countWoundedTalents(self.talents)
            return true
        end

        local woundedCount = countWoundedTalents(self.talents)
        if woundedCount >= maxTalentWounds(self) then
            self.woundedTalents = woundedCount
            return false
        end

        talent.wounded = true
        self._woundedTalentOrder = self._woundedTalentOrder or {}
        self._woundedTalentOrder[#self._woundedTalentOrder + 1] = talentId
        self.woundedTalents = woundedCount + 1
        return true
    end

    --- Heal a specific talent
    function adventurer:healTalent(talentId)
        local talent = self.talents[talentId]
        if not talent then
            return false
        end

        if type(talent) ~= "table" then
            talent = normalizeTalentData(talent)
            self.talents[talentId] = talent
        end

        if talent.wounded then
            talent.wounded = false
            removeWoundedTalentOrder(self, talentId)
            self.woundedTalents = countWoundedTalents(self.talents)
            return true
        end

        self.woundedTalents = countWoundedTalents(self.talents)
        return true
    end

    --- Invest XP in a talent
    function adventurer:investXP(talentId, amount)
        if self.talents[talentId] then
            self.talents[talentId].xp_invested =
                self.talents[talentId].xp_invested + amount
            return true
        end
        return false
    end

    --- Master a talent (usually after enough XP)
    function adventurer:masterTalent(talentId)
        if self.talents[talentId] then
            self.talents[talentId].mastered = true
            return true
        end
        return false
    end

    --- Get list of wounded talent IDs
    function adventurer:getWoundedTalents()
        local wounded = {}
        for id, talent in pairs(self.talents) do
            if talent.wounded then
                wounded[#wounded + 1] = id
            end
        end
        return wounded
    end

    return adventurer
end

return M
