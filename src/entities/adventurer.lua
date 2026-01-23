-- adventurer.lua
-- Adventurer Schema (PC Specialization) for Majesty
-- Ticket T1_6: Extends Entity with Resolve, Motifs, Bonds, Talents
--
-- Design: Composition over inheritance.
-- An Adventurer wraps a base Entity and adds PC-specific components.

local base_entity = require('entities.base_entity')

local M = {}

--------------------------------------------------------------------------------
-- BOND STATUS CONSTANTS
--------------------------------------------------------------------------------
M.BOND_STATUS = {
    LOVE            = "love",
    GUARDIANSHIP    = "guardianship",
    RIVALRY         = "rivalry",
    FRIENDSHIP      = "friendship",
    UNREQUITED_LOVE = "unrequited_love",
    DEBT            = "debt",
}

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

    --- Create or update a bond with another entity
    -- @param entityId string: The other entity's ID
    -- @param status string: One of BOND_STATUS constants
    function adventurer:setBond(entityId, status)
        if not self.bonds[entityId] then
            self.bonds[entityId] = { status = status, charged = false }
        else
            self.bonds[entityId].status = status
        end
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
    adventurer.talents = config.talents or {}

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
        if self.talents[talentId] then
            self.talents[talentId].wounded = true
            return true
        end
        return false
    end

    --- Heal a specific talent
    function adventurer:healTalent(talentId)
        if self.talents[talentId] then
            self.talents[talentId].wounded = false
            return true
        end
        return false
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
