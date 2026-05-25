-- guild_roster.lua
-- Helpers for rulebook guild roster procedures.

local M = {}

local function normalize(value)
    return tostring(value or "")
        :lower()
        :gsub("[’']", "")
        :gsub("[^%w]+", "_")
        :gsub("^_+", "")
        :gsub("_+$", "")
end

local SIZE_RANKS = {
    tiny = 1,
    very_small = 1,
    small = 2,
    gnome = 2,
    halfling = 2,
    child = 2,
    human = 3,
    human_sized = 3,
    normal = 3,
    medium = 3,
    dwarf = 3,
    high_elf = 3,
    dark_elf = 3,
    wood_elf = 3,
    earthblooded = 3,
    stormblooded = 3,
    seablooded = 3,
    fireblooded = 3,
    large = 4,
    huge = 4,
    troll = 4,
    giant = 5,
}

local function actorId(actor)
    return actor and (actor.id or actor.name) or nil
end

local function actorSizeRank(actor, defaultRank)
    if not actor then
        return defaultRank or 3
    end

    local rank = tonumber(actor.sizeRank or actor.weightRank)
    if rank then
        return math.floor(rank)
    end

    local size = normalize(actor.sizeCategory or actor.creatureSize or actor.bodySize or actor.size or actor.kin or
        actor.kith or actor.species or actor.race)
    return SIZE_RANKS[size] or defaultRank or 3
end

local function collectOrderedEntries(rosterOrMembers)
    if not rosterOrMembers then
        return {}
    end

    if type(rosterOrMembers.marchingOrder) == "table" and #rosterOrMembers.marchingOrder > 0 then
        local entries = {}
        for index, entry in ipairs(rosterOrMembers.marchingOrder) do
            entries[#entries + 1] = {
                actor = entry.actor or entry,
                actorId = entry.actorId or actorId(entry.actor or entry),
                marchingOrder = tonumber(entry.marchingOrder) or index,
                source = entry,
            }
        end
        table.sort(entries, function(a, b)
            return (a.marchingOrder or 0) < (b.marchingOrder or 0)
        end)
        return entries
    end

    local members = rosterOrMembers.adventurers or rosterOrMembers.members or rosterOrMembers
    local entries = {}
    for index, actor in ipairs(members or {}) do
        entries[#entries + 1] = {
            actor = actor,
            actorId = actorId(actor),
            marchingOrder = tonumber(actor and actor.marchingOrder) or index,
            source = actor,
        }
    end
    table.sort(entries, function(a, b)
        return (a.marchingOrder or 0) < (b.marchingOrder or 0)
    end)
    return entries
end

function M.sizeRank(actor, defaultRank)
    return actorSizeRank(actor, defaultRank)
end

function M.selectMarchingOrderActor(rosterOrMembers, opts)
    opts = opts or {}
    local minimumRank = tonumber(opts.minimumRank or opts.minRank)
    if not minimumRank then
        minimumRank = actorSizeRank({
            sizeCategory = opts.minimumSize or opts.minSize or opts.sizeCategory or "human_sized",
        }, 3)
    end

    local skipped = {}
    for _, entry in ipairs(collectOrderedEntries(rosterOrMembers)) do
        local rank = actorSizeRank(entry.actor, 3)
        if rank >= minimumRank then
            return entry.actor, {
                actor = entry.actor,
                actorId = entry.actorId,
                marchingOrder = entry.marchingOrder,
                sizeRank = rank,
                minimumRank = minimumRank,
                skipped = skipped,
            }
        end

        skipped[#skipped + 1] = {
            actor = entry.actor,
            actorId = entry.actorId,
            marchingOrder = entry.marchingOrder,
            sizeRank = rank,
        }
    end

    return nil, {
        reason = "no_marching_order_actor_large_enough",
        minimumRank = minimumRank,
        skipped = skipped,
    }
end

return M
