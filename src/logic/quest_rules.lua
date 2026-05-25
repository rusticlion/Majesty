-- quest_rules.lua
-- Chapter 2 quest shape and GM-prep helpers.

local M = {}

M.RESULTS = {
    ACCEPTED = "quest_accepted",
    NEEDS_REVISION = "quest_needs_revision",
    PREP_RECORDED = "quest_prep_recorded",
    RUMOR_RECORDED = "quest_rumor_recorded",
}

local BROAD_QUESTS = {
    ["get rich"] = true,
    ["be rich"] = true,
    ["become rich"] = true,
    ["get wealthy"] = true,
    ["become wealthy"] = true,
    ["get treasure"] = true,
    ["find treasure"] = true,
    ["gain power"] = true,
    ["get power"] = true,
    ["become powerful"] = true,
    ["be famous"] = true,
    ["become famous"] = true,
    ["get glory"] = true,
    ["win glory"] = true,
}

local ACTION_VERBS = {
    "capture",
    "carry",
    "deliver",
    "find",
    "get",
    "haul",
    "kill",
    "map",
    "pluck",
    "recover",
    "rescue",
    "restore",
    "retrieve",
    "return",
    "save",
    "slay",
    "steal",
}

local function trim(value)
    if type(value) ~= "string" then
        return value
    end
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalizeText(value)
    local normalized = tostring(value or ""):lower()
    normalized = normalized:gsub("[’']", "")
    normalized = normalized:gsub("[^%w]+", " ")
    normalized = normalized:gsub("^%s+", ""):gsub("%s+$", "")
    return normalized
end

local function copyList(values)
    local copy = {}
    for i, value in ipairs(values or {}) do
        copy[i] = value
    end
    return copy
end

local function copyMap(values)
    local copy = {}
    for key, value in pairs(values or {}) do
        copy[key] = value
    end
    return copy
end

local function appendIssue(detail, issue, message)
    detail.issues[#detail.issues + 1] = issue
    detail.messages[#detail.messages + 1] = message
end

local function hasActionVerb(text)
    for _, verb in ipairs(ACTION_VERBS) do
        if text:match("^" .. verb .. "%f[%A]") or text:match("%f[%w]" .. verb .. "%f[%A]") then
            return true
        end
    end
    return false
end

local function normalizeRumors(rumors)
    local normalized = {}
    for _, rumor in ipairs(rumors or {}) do
        if type(rumor) == "table" then
            local entry = copyMap(rumor)
            entry.text = entry.text or entry.rumor or entry.hint
            entry.mayBeFalse = entry.mayBeFalse ~= false
            normalized[#normalized + 1] = entry
        else
            normalized[#normalized + 1] = {
                text = rumor,
                mayBeFalse = true,
            }
        end
    end
    return normalized
end

function M.reviewQuest(opts)
    opts = opts or {}
    local quest = trim(opts.quest or opts.objective or opts.title or opts.description)
    local detail = {
        quest = quest,
        issues = {},
        messages = {},
        suggestions = {},
        discrete = opts.discrete,
        achievable = opts.achievable,
        result = M.RESULTS.ACCEPTED,
    }

    if type(quest) ~= "string" or quest == "" then
        appendIssue(detail, "missing_quest", "Quest required")
    else
        local normalized = normalizeText(quest)
        detail.normalized = normalized
        if BROAD_QUESTS[normalized] then
            appendIssue(detail, "quest_too_broad", "Quest should be discrete and achievable")
            detail.suggestions[#detail.suggestions + 1] =
                "Name the specific object, person, place, or deed the adventurer is pursuing."
        end
        if opts.discrete == false then
            appendIssue(detail, "quest_not_discrete", "Quest should be discrete")
        end
        if opts.achievable == false then
            appendIssue(detail, "quest_not_achievable", "Quest should be achievable")
        end
        if opts.afterCompletion == true and opts.relatedToPreviousAdventure == false then
            appendIssue(detail, "new_quest_not_contextual",
                "New quests after completion should make sense in context")
        end
        if not hasActionVerb(normalized) then
            detail.suggestions[#detail.suggestions + 1] =
                "Phrase the quest around a concrete action, such as find, recover, kill, rescue, or capture."
        end
    end

    detail.valid = #detail.issues == 0
    detail.needsRevision = not detail.valid
    if not detail.valid then
        detail.result = M.RESULTS.NEEDS_REVISION
    end
    detail.message = detail.messages[1]
    return detail.valid, detail.result, detail
end

function M.prepareQuest(opts)
    opts = opts or {}
    local valid, _, review = M.reviewQuest(opts)
    local placement = copyMap(opts.objectivePlacement or opts.placement)
    placement.location = placement.location or opts.location
    placement.roomId = placement.roomId or opts.roomId
    placement.featureId = placement.featureId or opts.featureId
    placement.placed = placement.placed or placement.location ~= nil or placement.roomId ~= nil or
        placement.featureId ~= nil

    local rumors = normalizeRumors(opts.rumors)
    local hints = copyList(opts.hints)
    local characters = copyList(opts.associatedCharacters or opts.characters or opts.npcs)
    local challenges = copyList(opts.challenges or opts.obstacles)
    local pathsToVictory = copyList(opts.pathsToVictory or opts.paths)

    local detail = {
        quest = review.quest,
        review = review,
        objectivePlacement = placement,
        hints = hints,
        rumors = rumors,
        associatedCharacters = characters,
        challenges = challenges,
        pathsToVictory = pathsToVictory,
        twists = copyList(opts.twists),
        competition = copyList(opts.competition),
        trouble = copyList(opts.trouble),
        needsPlacement = not placement.placed,
        hasHints = #hints > 0 or #rumors > 0,
        hasAssociatedCharacters = #characters > 0,
        hasOpenEndedChallenges = #challenges > 0,
        hasPathsToVictory = #pathsToVictory > 0,
        result = M.RESULTS.PREP_RECORDED,
    }

    detail.hasFalseRumors = false
    for _, rumor in ipairs(rumors) do
        if rumor["false"] == true or rumor.correct == false or rumor.mayBeFalse == true then
            detail.hasFalseRumors = true
            break
        end
    end

    detail.readyForPlay = valid and not detail.needsPlacement and detail.hasHints and
        (detail.hasOpenEndedChallenges or detail.hasPathsToVictory)
    detail.needsGMFollowup = not detail.readyForPlay
    return true, M.RESULTS.PREP_RECORDED, detail
end

function M.recordQuestRumor(state, opts)
    state = state or {}
    opts = opts or {}
    local quest = opts.quest or opts.currentQuest or state.currentQuest
    local text = trim(opts.text or opts.rumor or opts.hint)
    if not quest then
        return false, "Current quest required"
    end
    if not text or text == "" then
        return false, "Quest rumor required"
    end

    local record = {
        quest = quest,
        text = text,
        leadsOneStepCloser = opts.leadsOneStepCloser ~= false,
        mayBeFalse = opts.mayBeFalse ~= false,
        correct = opts.correct,
        featuredObject = opts.featuredObject,
        source = opts.source or "quest_rumor",
        result = M.RESULTS.RUMOR_RECORDED,
    }
    state.questRumors = state.questRumors or {}
    state.questRumors[#state.questRumors + 1] = record
    state.lastQuestRumor = record
    return true, M.RESULTS.RUMOR_RECORDED, record
end

return M
