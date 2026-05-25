-- fate_binding.lua
-- Generic "bound by fate" bookkeeping for Tests of Fate.

local M = {}

local function normalize(value, fallback)
    if value == nil or value == "" then
        return fallback or "default"
    end
    return tostring(value):lower():gsub("%s+", "_")
end

local function actorId(actor)
    if type(actor) == "table" then
        return actor.id or actor.name
    end
    return actor
end

local function addActorId(ids, seen, actor)
    local id = actorId(actor)
    if id and not seen[id] then
        ids[#ids + 1] = id
        seen[id] = true
    end
end

local function collectActorIds(opts)
    local ids = {}
    local seen = {}

    addActorId(ids, seen, opts.actor or opts.adventurer or opts.lead)
    for _, actor in ipairs(opts.actors or opts.participants or opts.guildMembers or {}) do
        addActorId(ids, seen, actor)
    end
    for _, actor in ipairs(opts.helpers or opts.assistants or opts.aiders or {}) do
        addActorId(ids, seen, actor)
    end

    return ids
end

local function sortedTokens(value, out)
    out = out or {}
    if type(value) == "table" then
        if #value > 0 then
            for _, item in ipairs(value) do
                sortedTokens(item, out)
            end
        else
            for key, item in pairs(value) do
                out[#out + 1] = normalize(key) .. ":" .. normalize(item)
            end
        end
    elseif value ~= nil then
        out[#out + 1] = normalize(value)
    end
    table.sort(out)
    return out
end

function M.circumstanceSignature(opts)
    opts = opts or {}
    if opts.circumstanceSignature then
        return tostring(opts.circumstanceSignature)
    end

    local tokens = {}
    sortedTokens(opts.circumstance or opts.circumstances, tokens)
    sortedTokens(opts.tools or opts.tool or opts.item or opts.items, tokens)
    sortedTokens(opts.state or opts.obstacleState or opts.sceneState, tokens)
    sortedTokens(opts.twist or opts.newTwist or opts.changedBy, tokens)
    if #tokens == 0 then
        return "default"
    end
    return table.concat(tokens, "|")
end

function M.keys(opts)
    opts = opts or {}
    return {
        scope = normalize(opts.scope or opts.scopeId or opts.locationId or opts.roomId, "global"),
        objective = normalize(opts.objective or opts.obstacle or opts.targetId or opts.target or opts.poiId, "objective"),
        method = normalize(opts.method or opts.approach or opts.testKey or opts.action, "default"),
    }
end

local function getObjectiveTable(records, keys)
    local scopeRecords = records[keys.scope]
    return scopeRecords and scopeRecords[keys.objective] or nil
end

function M.getStatus(records, opts)
    records = records or {}
    opts = opts or {}
    local keys = M.keys(opts)
    local objectiveRecords = getObjectiveTable(records, keys)
    if not objectiveRecords then
        return { allowed = true, reason = "new_test", keys = keys }
    end

    local entry = objectiveRecords[keys.method]
    if not entry then
        return { allowed = true, reason = "alternate_method", keys = keys }
    end

    local circumstance = M.circumstanceSignature(opts)
    if entry.circumstance ~= circumstance or opts.circumstanceChanged == true then
        return {
            allowed = true,
            reason = "circumstance_changed",
            keys = keys,
            entry = entry,
            circumstance = circumstance,
        }
    end

    return {
        allowed = false,
        reason = "result_stands",
        keys = keys,
        entry = entry,
        circumstance = circumstance,
    }
end

function M.record(records, opts, testResult)
    records = records or {}
    opts = opts or {}
    local keys = M.keys(opts)
    local circumstance = M.circumstanceSignature(opts)

    records[keys.scope] = records[keys.scope] or {}
    records[keys.scope][keys.objective] = records[keys.scope][keys.objective] or {}
    local entry = {
        keys = keys,
        circumstance = circumstance,
        result = testResult,
        actorIds = collectActorIds(opts),
        guildBound = opts.guildBound ~= false,
        notes = opts.notes,
    }
    records[keys.scope][keys.objective][keys.method] = entry
    return entry, records
end

function M.clear(records, opts)
    if type(records) ~= "table" then
        return false
    end

    local keys = M.keys(opts or {})
    if opts and (opts.method or opts.approach or opts.testKey or opts.action) then
        local objectiveRecords = getObjectiveTable(records, keys)
        if objectiveRecords then
            objectiveRecords[keys.method] = nil
            return true
        end
        return false
    end
    if opts and (opts.objective or opts.obstacle or opts.targetId or opts.target or opts.poiId) then
        if records[keys.scope] then
            records[keys.scope][keys.objective] = nil
            return true
        end
        return false
    end
    records[keys.scope] = nil
    return true
end

return M
