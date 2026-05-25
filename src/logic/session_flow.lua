-- session_flow.lua
-- Backend helpers for table/session bookkeeping rules.

local camp_actions = require('logic.camp_actions')

local M = {}

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, child in pairs(value) do
        copy[deepCopy(key)] = deepCopy(child)
    end
    return copy
end

M.SESSION_FLOW_PROCEDURE = {
    source = "Core Rules Chapter 1: The Flow of Play",
    beforePlay = {
        {
            key = "recap",
            label = "Recap",
            summary = "One player recaps the previous session with table help and GM corrections.",
            award = {
                condition = "exceptionally good recap",
                amount = 1,
                currency = "Resolve",
                recipient = "recapper or another adventurer who needs it",
            },
            recordFields = {
                "summary",
                "helpers",
                "gmCorrections",
                "currentPhase",
                "currentLocation",
                "currentObjective",
            },
        },
        {
            key = "returning_players",
            label = "Returning players",
            summary = "A player who missed a Crawl session rejoins after describing the Camp Action their trailing adventurer performed.",
            missedPhase = "crawl",
            position = "about one room behind the main guild",
            action = "Camp Action",
            assistantRequiredFor = {
                "Fellowship",
                "Train",
            },
        },
    },
    duringPlay = {
        {
            key = "pursue_quest",
            label = "Decide to pursue one adventurer's quest",
        },
        {
            key = "crawl",
            label = "Adventure through the Underworld",
            phase = "Crawl Phase",
        },
        {
            key = "challenge",
            label = "Struggle against denizens",
            phase = "Challenge Phase",
        },
        {
            key = "camp",
            label = "Rest in the lightless depths",
            phase = "Camp Phase",
        },
        {
            key = "city",
            label = "Return to the City",
            phase = "City Phase",
        },
        {
            key = "contract",
            label = "Pick up a contract to finance the next crawl",
        },
        {
            key = "descend",
            label = "Descend back into the Underworld",
            phase = "Crawl Phase",
        },
    },
    endOfPlay = {
        key = "end_of_play",
        label = "End of play",
        summary = "Play can end after any phase or at a specified time.",
        goodStoppingPoints = {
            "when one scene has just ended",
            "just after introducing a new scene",
        },
        prompts = {
            "what players want to do next",
            "where players want to go next",
            "when the next session happens",
            "who might be absent",
        },
    },
}

M.SESSION_ZERO_PROCEDURE = {
    source = "Core Rules Chapter 2: Session 0",
    defaultAssumption = "megadungeon-based exploration where adventurers pursue their own quests",
    collaborativeGameCreation = {
        {
            key = "expectations",
            label = "Set game expectations",
            prompts = {
                "What sort of game will the GM run?",
                "How does the table feel about deviations from the default formula?",
            },
        },
        {
            key = "fun_sources",
            label = "Discuss sources of fun",
            prompts = {
                "combat and using mechanics",
                "intra-party conflict",
                "intra-party romance",
                "deep character role-playing",
                "spending an evening with friends",
                "emerging story",
            },
        },
        {
            key = "sensitive_subjects",
            label = "Discuss sensitive subjects",
            prompts = {
                "Which difficult themes will be present?",
                "Which subjects should be avoided?",
                "Which subjects require asking first?",
            },
        },
        {
            key = "collaborative_adventurer_creation",
            label = "Create adventurers together",
            prompts = {
                "character overlap and differentiation",
                "rule interpretation questions",
                "table-approved special permissions",
                "GM plot seeds from backgrounds",
                "initial quest review and revision",
            },
        },
    },
    guildCreation = {
        questions = {
            "What is the name of your guild?",
            "Why are you adventuring together?",
            "How did you meet?",
            "Is there a guild leader?",
            "What are the looting rights?",
            "What is the guild sigil?",
        },
        rosterFields = {
            "guild members",
            "marching order",
            "guild roles",
            "directed Bonds with every other guild member",
        },
        optionalStructure = {
            "guild theme",
            "table restrictions",
        },
    },
}

M.NEW_ADVENTURER_ONBOARDING = {
    source = "Core Rules Chapter 2: missed Session 0 checklist",
    priorToFirstSession = {
        "adventurer sheet ready",
        "kin talent and all seven path talents written down",
        "one mastered path talent chosen",
        "remaining path talents in training",
        "Omphalic Market gear chosen",
        "own name known",
    },
    firstSession = {
        "select two players with whom the adventurer has Bonds",
        "say what the adventurer looks like",
        "ask about the game world",
        "ask about the rules",
        "ask for help choosing actions",
        "ask for clarification",
        "give feedback about what worked or could improve",
    },
    priorToSecondSession = {
        "fill out a Bond for every member of the guild",
    },
    endOfSecondSession = {
        "join the current guild or create a better-fitting adventurer",
        "if joining, sign the guild roster",
        "state guild role and marching order",
        "join the current quest and gain 3 XP",
    },
}

function M.getSessionFlowProcedure(section)
    if section == nil then
        return deepCopy(M.SESSION_FLOW_PROCEDURE)
    end
    return deepCopy(M.SESSION_FLOW_PROCEDURE[section])
end

function M.getSessionZeroProcedure()
    return deepCopy(M.SESSION_ZERO_PROCEDURE)
end

function M.getNewAdventurerOnboarding()
    return deepCopy(M.NEW_ADVENTURER_ONBOARDING)
end

local function actorId(actor)
    return actor and (actor.id or actor.name) or nil
end

local function currentResolve(actor)
    local resolve = actor and actor.resolve
    if type(resolve) == "table" then
        return tonumber(resolve.current) or 0
    end
    return tonumber(resolve) or 0
end

local function maxResolve(actor)
    local resolve = actor and actor.resolve
    if type(resolve) == "table" then
        return tonumber(resolve.max) or tonumber(actor.resolveMax) or 4
    end
    return tonumber(actor and (actor.resolveMax or actor.maxResolve)) or 4
end

local function grantResolve(actor, amount)
    if not actor then
        return false, "Resolve recipient required"
    end

    amount = math.max(1, math.floor(tonumber(amount) or 1))
    local before = currentResolve(actor)
    if actor.regainResolve then
        actor:regainResolve(amount)
    elseif type(actor.resolve) == "table" then
        actor.resolve.current = math.min(before + amount, maxResolve(actor))
    else
        actor.resolve = math.min(before + amount, maxResolve(actor))
    end

    return true, {
        before = before,
        after = currentResolve(actor),
        requested = amount,
        applied = currentResolve(actor) - before,
    }
end

local function copyActionData(source)
    if type(source) == "string" then
        return { type = source }
    end
    if type(source) ~= "table" then
        return nil
    end

    local out = {}
    for key, value in pairs(source) do
        out[key] = value
    end
    return out
end

local function normalizeActionType(action)
    local value = type(action) == "table" and (action.type or action.action) or action
    value = tostring(value or ""):lower()
    value = value:gsub("[’']", "")
    value = value:gsub("[^%w]+", "_")
    value = value:gsub("^_+", ""):gsub("_+$", "")
    return value
end

local function normalizePhase(phase)
    if type(phase) == "table" then
        phase = phase.phase or phase.currentPhase or phase.id or phase.name
    end
    if type(phase) ~= "string" then
        return nil
    end
    local value = phase:lower()
    value = value:gsub("[^%w]+", "_")
    value = value:gsub("^_+", ""):gsub("_+$", "")
    return value ~= "" and value or nil
end

function M.getDuringPlayOptions(opts)
    opts = opts or {}
    local campaign = opts.campaign or opts.gameState or opts.state
    local procedure = M.getSessionFlowProcedure("duringPlay")

    local function copySequence(source)
        if type(source) ~= "table" then
            if source ~= nil then
                return { source }
            end
            return {}
        end
        local out = {}
        for index, value in ipairs(source) do
            out[index] = value
        end
        return out
    end

    local function normalizeFlowStep(value)
        if type(value) == "table" then
            value = value.key or value.id or value.step or value.phase or value.name
        end
        local normalized = normalizePhase(value)
        if normalized == "crawl_phase" or normalized == "adventure_through_the_underworld" then
            return "crawl"
        end
        if normalized == "challenge_phase" or normalized == "struggle_against_denizens" then
            return "challenge"
        end
        if normalized == "camp_phase" or normalized == "rest_in_the_lightless_depths" then
            return "camp"
        end
        if normalized == "city_phase" or normalized == "return_to_the_city" then
            return "city"
        end
        if normalized == "pick_up_contract" or normalized == "plan_next_crawl" then
            return "contract"
        end
        if normalized == "pursue_quest" or normalized == "choose_quest" or normalized == "decide_quest" then
            return "pursue_quest"
        end
        if normalized == "descend_back_into_the_underworld" or normalized == "return_to_crawl" then
            return "descend"
        end
        return normalized
    end

    local function indexForStep(key)
        for index, step in ipairs(procedure or {}) do
            if step.key == key then
                return index
            end
        end
        return nil
    end

    local selectedKey = normalizeFlowStep(opts.currentStep or opts.step or opts.currentPhase or opts.phase or
        campaign and (campaign.currentStep or campaign.flowStep or campaign.currentPhase or campaign.phase))
    local selectedIndex = indexForStep(selectedKey)
    local nextIndex = selectedIndex and (selectedIndex % #procedure) + 1 or 1
    local currentQuest = opts.currentQuest or opts.quest or
        campaign and (campaign.currentQuest or campaign.guildQuest)
    local currentContract = opts.currentContract or opts.contract or
        campaign and (campaign.currentContract or campaign.contract)
    local hasCurrentQuest = currentQuest ~= nil
    local hasContract = currentContract ~= nil

    local completed = {}
    for _, key in ipairs(copySequence(opts.completedSteps or opts.completed or opts.done)) do
        completed[normalizeFlowStep(key)] = true
    end

    local options = {}
    for index, step in ipairs(procedure or {}) do
        local unavailableReason = nil
        if step.key == "pursue_quest" and not hasCurrentQuest then
            unavailableReason = "Current quest required"
        elseif step.key == "descend" and not hasCurrentQuest then
            unavailableReason = "Current quest required"
        end
        options[#options + 1] = {
            key = step.key,
            id = step.key,
            label = step.label,
            phase = step.phase,
            index = index,
            selected = selectedKey == step.key,
            next = index == nextIndex,
            completed = completed[step.key] == true,
            disabled = unavailableReason ~= nil,
            unavailableReason = unavailableReason,
        }
    end

    local selectedOption = selectedIndex and options[selectedIndex] or nil
    local nextOption = options[nextIndex]
    return {
        procedure = procedure,
        options = options,
        currentStep = selectedKey,
        currentIndex = selectedIndex,
        selectedOption = selectedOption,
        nextStep = nextOption and nextOption.key or nil,
        nextIndex = nextIndex,
        nextOption = nextOption,
        currentQuest = currentQuest,
        currentContract = currentContract,
        hasCurrentQuest = hasCurrentQuest,
        hasContract = hasContract,
        repeats = true,
        resultPreview = "during_play_options_ready",
    }
end

local function returningActionRequiresAssistant(action)
    local actionType = normalizeActionType(action)
    return actionType == "fellowship" or actionType == "train"
end

local function normalizeAssistantList(opts, absence)
    opts = opts or {}
    local assistants = opts.assistants or opts.helpers or opts.absentWith or
        (absence and absence.assistants) or {}
    if opts.assistant or opts.helper then
        assistants = { opts.assistant or opts.helper }
    end
    return assistants
end

local function listContainsActor(items, actor)
    local id = actorId(actor)
    for _, item in ipairs(items or {}) do
        if item == actor then
            return true
        end
        if id and actorId(item) == id then
            return true
        end
    end
    return false
end

local function contextGuildWithAssistants(guild, actor, assistants)
    local out = {}
    for _, member in ipairs(guild or {}) do
        out[#out + 1] = member
    end
    if actor and not listContainsActor(out, actor) then
        out[#out + 1] = actor
    end
    for _, assistant in ipairs(assistants or {}) do
        if assistant and not listContainsActor(out, assistant) then
            out[#out + 1] = assistant
        end
    end
    return out
end

local function copyList(source)
    if type(source) ~= "table" then
        if source ~= nil then
            return { source }
        end
        return {}
    end

    local out = {}
    for index, value in ipairs(source) do
        out[index] = value
    end
    return out
end

local function copyMap(source)
    if type(source) ~= "table" then
        return {}
    end

    local out = {}
    for key, value in pairs(source) do
        out[key] = value
    end
    return out
end

local function appendRecord(target, key, record)
    if type(target) ~= "table" then
        return
    end
    target[key] = target[key] or {}
    target[key][#target[key] + 1] = record
end

local function nonblank(value)
    return type(value) == "string" and value:gsub("^%s+", ""):gsub("%s+$", "") ~= ""
end

local function actorTalent(actor, talentId)
    if not actor or not talentId or type(actor.talents) ~= "table" then
        return nil
    end
    return actor.talents[talentId]
end

local function actorHasTalent(actor, talentId)
    if not actor or not talentId then
        return false
    end
    if actor.hasTalent then
        return actor:hasTalent(talentId)
    end
    return actorTalent(actor, talentId) ~= nil
end

local function actorIsTalentMastered(actor, talentId)
    if not actor or not talentId then
        return false
    end
    if actor.isTalentMastered then
        return actor:isTalentMastered(talentId)
    end
    local talent = actorTalent(actor, talentId)
    return type(talent) == "table" and talent.mastered == true
end

local function inferredPathTalents(actor, opts)
    opts = opts or {}
    local callToAdventure = actor and actor.callToAdventure or {}
    local explicit = opts.pathTalents or opts.creationPathTalents or callToAdventure.pathTalents or
        (actor and (actor.pathTalents or actor.creationPathTalents))
    local talents = copyList(explicit)
    if #talents > 0 then
        return talents
    end
    if type(actor and actor.talents) == "table" then
        for talentId, talent in pairs(actor.talents) do
            if type(talent) == "table" and talent.trainingKind == "path" then
                talents[#talents + 1] = talentId
            end
        end
    end
    return talents
end

local function inferredKinTalent(actor, opts)
    opts = opts or {}
    local callToAdventure = actor and actor.callToAdventure or {}
    if opts.kinTalent or callToAdventure.kinTalent or actor and actor.kinTalent then
        return opts.kinTalent or callToAdventure.kinTalent or actor.kinTalent
    end
    if type(actor and actor.talents) == "table" then
        for talentId, talent in pairs(actor.talents) do
            if type(talent) == "table" and talent.trainingKind == "kin" then
                return talentId
            end
        end
    end
    return nil
end

local function unresolvedCount(items, predicate)
    local count = 0
    for _, item in ipairs(items or {}) do
        if predicate(item) then
            count = count + 1
        end
    end
    return count
end

function M.resolveRecap(opts)
    opts = opts or {}
    local recapper = opts.recapper or opts.actor or opts.player
    if not recapper then
        return false, "Recapper required"
    end

    local campaign = opts.campaign or opts.gameState or opts.state
    local log = opts.log or opts.campaignLog or opts.sessionLog
    if not log and campaign then
        campaign.campaignLog = campaign.campaignLog or {}
        log = campaign.campaignLog
    end

    local exceptional = opts.exceptional == true or opts.goodRecap == true or opts.awardResolve == true
    local recipient = opts.recipient or opts.giveTo or opts.resolveRecipient or recapper
    local detail = {
        recapper = recapper,
        recapperId = actorId(recapper),
        recipient = recipient,
        recipientId = actorId(recipient),
        exceptional = exceptional,
        summary = opts.summary or opts.recap or opts.text,
        helpers = copyList(opts.helpers or opts.tableHelp or opts.assistedBy),
        gmCorrections = copyList(opts.gmCorrections or opts.corrections),
        currentPhase = opts.currentPhase or opts.phase,
        currentLocation = opts.currentLocation or opts.location,
        currentObjective = opts.currentObjective or opts.objective,
        result = exceptional and "recap_resolve_awarded" or "recap_recorded",
    }
    detail.hasTableHelp = #detail.helpers > 0
    detail.hasGmCorrections = #detail.gmCorrections > 0

    local function persistRecap(record)
        if type(log) == "table" then
            appendRecord(log, "sessionRecaps", record)
            log.lastSessionRecap = record
        end
        if campaign then
            campaign.lastSessionRecap = record
            campaign.currentSessionMemory = {
                summary = record.summary,
                phase = record.currentPhase,
                location = record.currentLocation,
                objective = record.currentObjective,
            }
        end
    end

    if not exceptional then
        persistRecap(detail)
        return true, "recap_recorded", detail
    end

    local ok, grant = grantResolve(recipient, opts.amount or 1)
    if not ok then
        return false, grant
    end
    detail.resolve = grant
    detail.amount = grant.requested
    persistRecap(detail)
    return true, "recap_resolve_awarded", detail
end

function M.getBeforePlayOptions(opts)
    opts = opts or {}
    local campaign = opts.campaign or opts.gameState or opts.state
    local procedure = M.getSessionFlowProcedure("beforePlay")
    local participants = copyList(opts.participants or opts.players or opts.table or opts.guild)

    local function appendUniqueActor(list, actor)
        if not actor then
            return
        end
        if not listContainsActor(list, actor) then
            list[#list + 1] = actor
        end
    end

    local function actorOption(actor, selected)
        local current = currentResolve(actor)
        return {
            actor = actor,
            actorId = actorId(actor),
            name = actor and actor.name,
            selected = selected == true,
            currentResolve = current,
            maxResolve = maxResolve(actor),
            projectedResolveAfterAward = math.min(current + 1, maxResolve(actor)),
            disabled = actor == nil,
            unavailableReason = actor == nil and "Adventurer required" or nil,
        }
    end

    local recapper = opts.recapper or opts.recapActor or opts.actor or opts.player
    local exceptional = opts.exceptional == true or opts.goodRecap == true or opts.awardResolve == true
    local recipient = opts.recipient or opts.giveTo or opts.resolveRecipient or recapper
    appendUniqueActor(participants, recapper)
    appendUniqueActor(participants, recipient)

    local recapperOptions = {}
    local recipientOptions = {}
    for _, participant in ipairs(participants) do
        recapperOptions[#recapperOptions + 1] = actorOption(participant, participant == recapper)
        recipientOptions[#recipientOptions + 1] = actorOption(participant, participant == recipient)
    end

    local helpers = copyList(opts.helpers or opts.tableHelp or opts.assistedBy)
    local gmCorrections = copyList(opts.gmCorrections or opts.corrections)
    local currentPhase = opts.currentPhase or opts.phase or (campaign and (campaign.phase or campaign.currentPhase))
    local currentLocation = opts.currentLocation or opts.location or
        (campaign and campaign.currentSessionMemory and campaign.currentSessionMemory.location)
    local currentObjective = opts.currentObjective or opts.objective or
        (campaign and campaign.currentSessionMemory and campaign.currentSessionMemory.objective)
    local awardCurrent = currentResolve(recipient)
    local awardMax = maxResolve(recipient)
    local awardAfter = recipient and math.min(awardCurrent + 1, awardMax) or nil
    local recapOptions = {
        id = "recap",
        step = deepCopy(procedure and procedure[1]),
        summary = opts.summary or opts.recap or opts.text,
        recapper = recapper,
        recapperId = actorId(recapper),
        recapperOptions = recapperOptions,
        helpers = helpers,
        gmCorrections = gmCorrections,
        hasTableHelp = #helpers > 0,
        hasGmCorrections = #gmCorrections > 0,
        memoryPreview = {
            phase = currentPhase,
            location = currentLocation,
            objective = currentObjective,
        },
        exceptional = exceptional,
        award = {
            condition = "exceptionally good recap",
            amount = 1,
            currency = "Resolve",
            recipient = recipient,
            recipientId = actorId(recipient),
            recipientOptions = recipientOptions,
            currentResolve = recipient and awardCurrent or nil,
            maxResolve = recipient and awardMax or nil,
            projectedResolve = awardAfter,
            projectedApplied = awardAfter and (awardAfter - awardCurrent) or nil,
            disabled = not exceptional or recipient == nil,
            unavailableReason = (not exceptional and "Resolve award not selected") or
                (recipient == nil and "Resolve recipient required") or nil,
        },
        disabled = recapper == nil,
        unavailableReason = recapper == nil and "Recapper required" or nil,
        resultPreview = recapper and (exceptional and "recap_resolve_awarded" or "recap_recorded") or nil,
    }

    local returningActor = opts.returningPlayer or opts.absentPlayer or opts.returningActor or opts.actor or opts.player
    local absence = returningActor and returningActor.returningPlayerAbsence or nil
    local returningParticipants = copyList(opts.absentAdventurers or opts.returningPlayers or opts.guild or participants)
    appendUniqueActor(returningParticipants, returningActor)
    for _, assistant in ipairs(normalizeAssistantList(opts, absence)) do
        appendUniqueActor(returningParticipants, assistant)
    end

    local pendingAction = copyActionData(opts.actionData or opts.action or opts.campAction or
        returningActor and returningActor.pendingReturningCampAction or absence and absence.pendingCampAction)
    local selectedActionType = pendingAction and normalizeActionType(pendingAction)
    if pendingAction and selectedActionType and selectedActionType ~= "" then
        pendingAction.type = selectedActionType
    end

    local assistants = normalizeAssistantList(opts, absence)
    local context = copyMap(opts.context)
    context.guild = contextGuildWithAssistants(opts.guild or context.guild, returningActor, assistants)
    local availableActions = {}
    if returningActor then
        for _, action in ipairs(camp_actions.getAvailableActions(returningActor, context.guild, context)) do
            availableActions[action.id] = true
        end
    end

    local function campActionUnavailableReason(action)
        if not returningActor then
            return "Returning adventurer required"
        end
        if returningActionRequiresAssistant(action.id) and #assistants == 0 then
            return "Assistant adventurer required"
        end
        if availableActions[action.id] then
            return nil
        end
        if action.requiresItem then
            return "Requires " .. tostring(action.requiresItem)
        end
        if action.requiresFletchAmmo then
            return "Requires a bow or crossbow"
        end
        if action.requiresRangedAmmo then
            return "Requires a ranged hunting method"
        end
        if action.requiresReadableBook then
            return "Requires a readable book"
        end
        if action.requiresAlchemy then
            return "Requires Alchemy, an alchemy kit, and bottled reagents"
        end
        if action.requiresCampUsableItem then
            return "Requires a Camp-usable item"
        end
        if action.requiresCampTalent then
            return "Requires a Camp-usable talent"
        end
        if action.requiresTalent then
            return "Requires " .. tostring(action.requiresTalent)
        end
        if action.requiresActivePact then
            return "Requires an active pact"
        end
        if action.targetType == "pc" then
            return "Requires another adventurer"
        end
        if action.targetType == "companion" then
            return "Requires an animal companion"
        end
        return "Camp Action unavailable"
    end

    local campActionOptions = {}
    for _, action in ipairs(camp_actions.ACTIONS) do
        local reason = campActionUnavailableReason(action)
        campActionOptions[#campActionOptions + 1] = {
            id = action.id,
            name = action.name,
            category = action.category,
            description = action.description,
            targetType = action.targetType,
            requiresTarget = action.requiresTarget == true,
            requiresAssistant = returningActionRequiresAssistant(action.id),
            selected = action.id == selectedActionType,
            disabled = reason ~= nil,
            unavailableReason = reason,
        }
    end

    local selectedAction = selectedActionType and camp_actions.getAction(selectedActionType) or nil
    local selectedReason = nil
    if selectedAction then
        selectedReason = campActionUnavailableReason(selectedAction)
    elseif selectedActionType then
        selectedReason = "Unknown Camp Action"
    else
        selectedReason = "Camp Action required"
    end
    local phase = normalizePhase(opts.phase or opts.currentPhase or opts.missedPhase or
        (campaign and (campaign.phase or campaign.currentPhase)))
    local phaseValid = phase == nil or phase == "crawl" or phase == "crawl_phase" or opts.allowOutsideCrawl == true
    local selectedRequiresAssistant = selectedAction and returningActionRequiresAssistant(selectedAction.id)
    local canMarkAbsent = returningActor ~= nil and phaseValid and selectedAction ~= nil and
        selectedReason == nil and not (selectedRequiresAssistant and #assistants == 0)
    local canResolveReturningCampAction = returningActor ~= nil and returningActor.absentFromCrawl == true and
        selectedAction ~= nil and selectedReason == nil and
        not (selectedRequiresAssistant and #assistants == 0 and pendingAction.target == nil)
    local returningUnavailableReason = nil
    if not returningActor then
        returningUnavailableReason = "Returning adventurer required"
    elseif not phaseValid then
        returningUnavailableReason = "Crawl Phase absence required"
    elseif selectedReason and not canResolveReturningCampAction then
        returningUnavailableReason = selectedReason
    end

    local returningCandidateOptions = {}
    for _, participant in ipairs(returningParticipants) do
        local participantAbsence = participant and participant.returningPlayerAbsence or {}
        local participantAction = copyActionData(participant and participant.pendingReturningCampAction or
            participantAbsence.pendingCampAction)
        returningCandidateOptions[#returningCandidateOptions + 1] = {
            actor = participant,
            actorId = actorId(participant),
            name = participant and participant.name,
            selected = participant == returningActor,
            absentFromCrawl = participant and participant.absentFromCrawl == true,
            trailingBehindGuild = participant and participant.trailingBehindGuild == true,
            distanceRooms = participant and (participant.distanceRoomsFromGuild or participantAbsence.distanceRooms),
            pendingCampAction = participantAction,
            disabled = participant == nil or participant.absentFromCrawl ~= true,
            unavailableReason = (participant == nil and "Returning adventurer required") or
                (participant.absentFromCrawl ~= true and "Adventurer is not trailing from a missed Crawl") or nil,
        }
    end

    local assistantOptions = {}
    for _, participant in ipairs(returningParticipants) do
        if participant and participant ~= returningActor then
            assistantOptions[#assistantOptions + 1] = {
                actor = participant,
                actorId = actorId(participant),
                name = participant.name,
                selected = listContainsActor(assistants, participant),
                disabled = false,
            }
        end
    end

    local returningPlayerOptions = {
        id = "returning_players",
        step = deepCopy(procedure and procedure[2]),
        actor = returningActor,
        actorId = actorId(returningActor),
        candidates = returningCandidateOptions,
        phase = phase or "crawl",
        phaseValid = phaseValid,
        distanceRooms = tonumber(opts.distanceRooms) or (absence and absence.distanceRooms) or 1,
        trailingBehind = true,
        selectedCampAction = selectedAction and {
            id = selectedAction.id,
            name = selectedAction.name,
            category = selectedAction.category,
            requiresAssistant = selectedRequiresAssistant == true,
            disabled = selectedReason ~= nil,
            unavailableReason = selectedReason,
        } or nil,
        campActionOptions = campActionOptions,
        assistants = assistants,
        assistantOptions = assistantOptions,
        assistantRequiredFor = copyList(procedure and procedure[2] and procedure[2].assistantRequiredFor),
        canMarkAbsent = canMarkAbsent,
        canResolveReturningCampAction = canResolveReturningCampAction,
        disabled = returningUnavailableReason ~= nil,
        unavailableReason = returningUnavailableReason,
        resultPreview = canResolveReturningCampAction and "returning_player_camp_action_resolved" or
            (canMarkAbsent and "adventurer_absent_from_crawl" or "returning_player_followup_needed"),
    }

    return {
        procedure = procedure,
        recapOptions = recapOptions,
        returningPlayerOptions = returningPlayerOptions,
    }
end

function M.getSessionZeroOptions(opts)
    opts = opts or {}
    local procedure = M.getSessionZeroProcedure()
    local guildDecisions = copyMap(opts.guildDecisions or opts.guild or {})
    local funSources = copyMap(opts.funSources or opts.enjoyment or opts.playerInterests)
    local sensitiveSubjects = {
        included = copyList(opts.sensitiveSubjects or opts.difficultThemes),
        avoid = copyList(opts.avoidSubjects or opts.lines),
        askFirst = copyList(opts.askFirstSubjects or opts.veils),
    }
    local specialPermissions = copyList(opts.specialPermissions or opts.permissionRequests)
    local questReviews = copyList(opts.questReviews or opts.initialQuestReviews or opts.quests)
    local guildTheme = guildDecisions.theme or guildDecisions.guildTheme or opts.guildTheme
    local guildRestrictions = copyList(guildDecisions.restrictions or opts.guildRestrictions)
    local guildMembers = copyList(guildDecisions.members or guildDecisions.guildMembers or
        opts.guildMembers or opts.members)
    local guildMarchingOrder = copyList(guildDecisions.marchingOrder or
        guildDecisions.guildMarchingOrder or opts.guildMarchingOrder or opts.marchingOrder)
    local guildRoles = copyMap(guildDecisions.roles or guildDecisions.guildRoles or
        opts.guildRoles or opts.roles)
    local guildBonds = copyList(guildDecisions.bonds or guildDecisions.initialBonds or
        opts.guildBonds or opts.initialBonds or opts.bonds)

    local hasExpectationDiscussion = opts.campaignPremise ~= nil or opts.premise ~= nil or
        opts.gamePremise ~= nil or #copyList(opts.deviations or opts.formulaDeviations) > 0 or
        next(funSources) ~= nil
    local hasSensitiveSubjectDiscussion = #sensitiveSubjects.included > 0 or
        #sensitiveSubjects.avoid > 0 or #sensitiveSubjects.askFirst > 0
    local unresolvedPermissions = unresolvedCount(specialPermissions, function(item)
        return item and item.approved ~= true and item.tableApproved ~= true
    end)
    local questsNeedingRevision = unresolvedCount(questReviews, function(item)
        return item and (item.vetoed == true or item.needsRevision == true or item.approved == false)
    end)
    local guildCreationQuestions = {
        name = guildDecisions.name ~= nil,
        whyTogether = guildDecisions.whyTogether ~= nil,
        howMet = guildDecisions.howMet ~= nil,
        leader = guildDecisions.leader ~= nil or guildDecisions.hasLeader ~= nil,
        lootingRights = guildDecisions.lootingRights ~= nil,
        sigil = guildDecisions.sigil ~= nil or guildDecisions.heraldry ~= nil or
            guildDecisions.portraiture ~= nil,
        theme = guildTheme ~= nil,
        restrictions = #guildRestrictions > 0,
    }
    local guildRosterChecklist = {
        members = #guildMembers > 0,
        marchingOrder = #guildMarchingOrder > 0,
        roles = next(guildRoles) ~= nil,
        bonds = #guildMembers <= 1 or #guildBonds >= (#guildMembers * (#guildMembers - 1)),
    }
    local guildQuestionsAnswered = guildCreationQuestions.name and guildCreationQuestions.whyTogether and
        guildCreationQuestions.howMet and guildCreationQuestions.leader and
        guildCreationQuestions.lootingRights and guildCreationQuestions.sigil and
        guildRosterChecklist.members and guildRosterChecklist.marchingOrder and
        guildRosterChecklist.roles and guildRosterChecklist.bonds

    local collaborativeOptions = {}
    for _, section in ipairs(procedure.collaborativeGameCreation or {}) do
        local completed = false
        if section.key == "expectations" then
            completed = hasExpectationDiscussion
        elseif section.key == "fun_sources" then
            completed = next(funSources) ~= nil
        elseif section.key == "sensitive_subjects" then
            completed = hasSensitiveSubjectDiscussion
        elseif section.key == "collaborative_adventurer_creation" then
            completed = #copyList(opts.adventurerOverlaps or opts.overlaps) > 0 or
                #copyList(opts.rulesClarifications or opts.ruleQuestions) > 0 or
                #specialPermissions > 0 or #questReviews > 0 or
                #copyList(opts.plotSeeds or opts.gmPlotSeeds) > 0
        end
        collaborativeOptions[#collaborativeOptions + 1] = {
            key = section.key,
            label = section.label,
            prompts = deepCopy(section.prompts or {}),
            completed = completed,
            disabled = false,
        }
    end

    local guildQuestionDefinitions = {
        { id = "name", prompt = "What is the name of your guild?" },
        { id = "whyTogether", prompt = "Why are you adventuring together?" },
        { id = "howMet", prompt = "How did you meet?" },
        { id = "leader", prompt = "Is there a guild leader?" },
        { id = "lootingRights", prompt = "What are the looting rights?" },
        { id = "sigil", prompt = "What is the guild sigil?" },
    }
    local guildQuestionOptions = {}
    local missing = {}
    for _, question in ipairs(guildQuestionDefinitions) do
        local answered = guildCreationQuestions[question.id] == true
        guildQuestionOptions[question.id] = {
            id = question.id,
            prompt = question.prompt,
            answered = answered,
            disabled = false,
            unavailableReason = not answered and "Guild answer required" or nil,
        }
        if not answered then
            missing[#missing + 1] = "guild_" .. question.id
        end
    end

    local rosterOptions = {
        members = {
            id = "members",
            label = "Guild members",
            answered = guildRosterChecklist.members,
            count = #guildMembers,
        },
        marchingOrder = {
            id = "marchingOrder",
            label = "Marching order",
            answered = guildRosterChecklist.marchingOrder,
            count = #guildMarchingOrder,
        },
        roles = {
            id = "roles",
            label = "Guild roles",
            answered = guildRosterChecklist.roles,
        },
        bonds = {
            id = "bonds",
            label = "Directed Bonds",
            answered = guildRosterChecklist.bonds,
            count = #guildBonds,
            requiredCount = #guildMembers <= 1 and 0 or #guildMembers * (#guildMembers - 1),
        },
    }
    for key, option in pairs(rosterOptions) do
        option.disabled = false
        option.unavailableReason = not option.answered and "Guild roster entry required" or nil
        if not option.answered then
            missing[#missing + 1] = "guild_roster_" .. key
        end
    end
    if unresolvedPermissions > 0 then
        missing[#missing + 1] = "unresolved_permissions"
    end
    if questsNeedingRevision > 0 then
        missing[#missing + 1] = "quests_needing_revision"
    end

    local needsFollowup = unresolvedPermissions > 0 or questsNeedingRevision > 0 or not guildQuestionsAnswered
    return {
        procedure = procedure,
        participants = copyList(opts.participants or opts.players or opts.table),
        defaultAssumption = procedure.defaultAssumption,
        collaborativeOptions = collaborativeOptions,
        guildQuestionOptions = guildQuestionOptions,
        guildRosterOptions = rosterOptions,
        guildCreationQuestions = guildCreationQuestions,
        guildRosterChecklist = guildRosterChecklist,
        guildQuestionsAnswered = guildQuestionsAnswered,
        hasExpectationDiscussion = hasExpectationDiscussion,
        hasSensitiveSubjectDiscussion = hasSensitiveSubjectDiscussion,
        unresolvedPermissions = unresolvedPermissions,
        questsNeedingRevision = questsNeedingRevision,
        missing = missing,
        needsFollowup = needsFollowup,
        disabled = false,
        resultPreview = needsFollowup and "session_zero_followup_needed" or "session_zero_ready",
    }
end

function M.recordSessionZero(opts)
    opts = opts or {}
    local campaign = opts.campaign or opts.gameState or opts.state
    local log = opts.log or opts.campaignLog or opts.sessionLog
    if not log and campaign then
        campaign.campaignLog = campaign.campaignLog or {}
        log = campaign.campaignLog
    end

    local record = {
        result = "session_zero_recorded",
        participants = copyList(opts.participants or opts.players or opts.table),
        campaignPremise = opts.campaignPremise or opts.premise or opts.gamePremise,
        expectedPlay = opts.expectedPlay or opts.assumption or "megadungeon_exploration",
        deviations = copyList(opts.deviations or opts.formulaDeviations),
        funSources = copyMap(opts.funSources or opts.enjoyment or opts.playerInterests),
        sensitiveSubjects = {
            included = copyList(opts.sensitiveSubjects or opts.difficultThemes),
            avoid = copyList(opts.avoidSubjects or opts.lines),
            askFirst = copyList(opts.askFirstSubjects or opts.veils),
        },
        adventurerOverlaps = copyList(opts.adventurerOverlaps or opts.overlaps),
        rulesClarifications = copyList(opts.rulesClarifications or opts.ruleQuestions),
        specialPermissions = copyList(opts.specialPermissions or opts.permissionRequests),
        questReviews = copyList(opts.questReviews or opts.initialQuestReviews or opts.quests),
        guildDecisions = copyMap(opts.guildDecisions or opts.guild or {}),
        plotSeeds = copyList(opts.plotSeeds or opts.gmPlotSeeds),
        notes = opts.notes,
    }

    record.hasExpectationDiscussion = record.campaignPremise ~= nil or
        #record.deviations > 0 or next(record.funSources) ~= nil
    record.hasSensitiveSubjectDiscussion = #record.sensitiveSubjects.included > 0 or
        #record.sensitiveSubjects.avoid > 0 or #record.sensitiveSubjects.askFirst > 0
    record.unresolvedPermissions = unresolvedCount(record.specialPermissions, function(item)
        return item and item.approved ~= true and item.tableApproved ~= true
    end)
    record.questsNeedingRevision = unresolvedCount(record.questReviews, function(item)
        return item and (item.vetoed == true or item.needsRevision == true or item.approved == false)
    end)
    record.guildTheme = record.guildDecisions.theme or record.guildDecisions.guildTheme or opts.guildTheme
    record.guildRestrictions = copyList(record.guildDecisions.restrictions or opts.guildRestrictions)
    record.guildMembers = copyList(record.guildDecisions.members or record.guildDecisions.guildMembers or
        opts.guildMembers or opts.members)
    record.guildMarchingOrder = copyList(record.guildDecisions.marchingOrder or
        record.guildDecisions.guildMarchingOrder or opts.guildMarchingOrder or opts.marchingOrder)
    record.guildRoles = copyMap(record.guildDecisions.roles or record.guildDecisions.guildRoles or
        opts.guildRoles or opts.roles)
    record.guildBonds = copyList(record.guildDecisions.bonds or record.guildDecisions.initialBonds or
        opts.guildBonds or opts.initialBonds or opts.bonds)
    record.guildCreationQuestions = {
        name = record.guildDecisions.name ~= nil,
        whyTogether = record.guildDecisions.whyTogether ~= nil,
        howMet = record.guildDecisions.howMet ~= nil,
        leader = record.guildDecisions.leader ~= nil or record.guildDecisions.hasLeader ~= nil,
        lootingRights = record.guildDecisions.lootingRights ~= nil,
        sigil = record.guildDecisions.sigil ~= nil or record.guildDecisions.heraldry ~= nil or
            record.guildDecisions.portraiture ~= nil,
        theme = record.guildTheme ~= nil,
        restrictions = #record.guildRestrictions > 0,
    }
    record.guildRosterChecklist = {
        members = #record.guildMembers > 0,
        marchingOrder = #record.guildMarchingOrder > 0,
        roles = next(record.guildRoles) ~= nil,
        bonds = #record.guildMembers <= 1 or #record.guildBonds >= (#record.guildMembers * (#record.guildMembers - 1)),
    }
    record.guildQuestionsAnswered = record.guildCreationQuestions.name and
        record.guildCreationQuestions.whyTogether and record.guildCreationQuestions.howMet and
        record.guildCreationQuestions.leader and record.guildCreationQuestions.lootingRights and
        record.guildCreationQuestions.sigil and record.guildRosterChecklist.members and
        record.guildRosterChecklist.marchingOrder and record.guildRosterChecklist.roles and
        record.guildRosterChecklist.bonds
    record.needsFollowup = record.unresolvedPermissions > 0 or record.questsNeedingRevision > 0 or
        not record.guildQuestionsAnswered

    if type(log) == "table" then
        appendRecord(log, "sessionZeroRecords", record)
        log.lastSessionZero = record
    end
    if campaign then
        campaign.sessionZero = record
        campaign.sessionZeroComplete = not record.needsFollowup
        if record.guildDecisions.name then
            campaign.guildName = record.guildDecisions.name
        end
        if record.guildDecisions.lootingRights then
            campaign.lootingRights = record.guildDecisions.lootingRights
        end
        if record.guildDecisions.whyTogether then
            campaign.guildWhyTogether = record.guildDecisions.whyTogether
        end
        if record.guildDecisions.howMet then
            campaign.guildHowMet = record.guildDecisions.howMet
        end
        if record.guildDecisions.sigil or record.guildDecisions.heraldry or record.guildDecisions.portraiture then
            campaign.guildSigil = record.guildDecisions.sigil or record.guildDecisions.heraldry or
                record.guildDecisions.portraiture
        end
        if record.guildDecisions.leader ~= nil then
            campaign.guildLeader = record.guildDecisions.leader
        elseif record.guildDecisions.hasLeader ~= nil then
            campaign.guildLeader = record.guildDecisions.hasLeader
        end
        if record.guildTheme then
            campaign.guildTheme = record.guildTheme
        end
        if #record.guildRestrictions > 0 then
            campaign.guildRestrictions = record.guildRestrictions
        end
        if #record.guildMembers > 0 then
            campaign.guildMembers = record.guildMembers
        end
        if #record.guildMarchingOrder > 0 then
            campaign.guildMarchingOrder = record.guildMarchingOrder
        end
        if next(record.guildRoles) ~= nil then
            campaign.guildRoles = record.guildRoles
        end
        if #record.guildBonds > 0 then
            campaign.guildBonds = record.guildBonds
        end
    end

    return true, "session_zero_recorded", record
end

function M.getEndOfPlayOptions(opts)
    opts = opts or {}
    local campaign = opts.campaign or opts.gameState or opts.state
    local procedure = M.getSessionFlowProcedure("endOfPlay")
    local phase = opts.phase or opts.endedPhase or opts.afterPhase or
        (campaign and (campaign.phase or campaign.currentPhase))
    local endedAt = opts.endedAt or opts.time
    local specifiedTime = opts.specifiedTime or opts.scheduledEndTime or opts.timeLimit
    local stoppedAtSpecifiedTime = opts.stoppedAtSpecifiedTime == true or opts.timeLimitReached == true or
        opts.atSpecifiedTime == true
    local goodStoppingPoint = opts.goodStoppingPoint == true
    local sceneJustEnded = opts.sceneJustEnded == true
    local nextSceneTeaser = opts.nextSceneTeaser or opts.nextScene or opts.cliffhanger
    local feedback = copyList(opts.feedback or opts.feedbackRequests or opts.playerFeedback)
    local playerPriorities = copyList(opts.playerPriorities or opts.nextActions or opts.whatNext)
    local desiredDestinations = copyList(opts.desiredDestinations or opts.whereNext or opts.nextDestinations)
    local nextSession = opts.nextSession or opts.nextSessionAt or opts.nextGame
    local expectedAbsences = copyList(opts.expectedAbsences or opts.absences or opts.absentPlayers)

    local hasNextSceneHook = nextSceneTeaser ~= nil
    local hasFeedbackPrompt = #feedback > 0
    local hasNextDirectionFeedback = #playerPriorities > 0 or #desiredDestinations > 0
    local hasNextSessionReminder = nextSession ~= nil or #expectedAbsences > 0
    local closedAtStoppingPoint = goodStoppingPoint or sceneJustEnded or hasNextSceneHook
    local closeReason = opts.closeReason or opts.reason or
        (stoppedAtSpecifiedTime and "specified_time" or nil) or
        (sceneJustEnded and "scene_ended" or nil) or
        (hasNextSceneHook and "new_scene_teaser" or nil) or
        "unspecified"

    local closureOptions = {
        {
            id = "after_phase",
            label = "End after a phase",
            selected = phase ~= nil and not stoppedAtSpecifiedTime,
            phase = phase,
            disabled = false,
        },
        {
            id = "specified_time",
            label = "End at a specified time",
            selected = stoppedAtSpecifiedTime or specifiedTime ~= nil,
            time = specifiedTime,
            disabled = false,
        },
        {
            id = "scene_ended",
            label = "Close when a scene has just ended",
            selected = sceneJustEnded,
            goodStoppingPoint = sceneJustEnded,
            disabled = false,
        },
        {
            id = "new_scene_teaser",
            label = "Close just after introducing a new scene",
            selected = hasNextSceneHook,
            teaser = nextSceneTeaser,
            goodStoppingPoint = hasNextSceneHook,
            disabled = false,
        },
    }

    local promptOptions = {
        {
            id = "what_next",
            prompt = procedure and procedure.prompts and procedure.prompts[1] or "what players want to do next",
            responses = playerPriorities,
            completed = #playerPriorities > 0,
            disabled = false,
        },
        {
            id = "where_next",
            prompt = procedure and procedure.prompts and procedure.prompts[2] or "where players want to go next",
            responses = desiredDestinations,
            completed = #desiredDestinations > 0,
            disabled = false,
        },
        {
            id = "next_session",
            prompt = procedure and procedure.prompts and procedure.prompts[3] or "when the next session happens",
            response = nextSession,
            completed = nextSession ~= nil,
            disabled = false,
        },
        {
            id = "expected_absences",
            prompt = procedure and procedure.prompts and procedure.prompts[4] or "who might be absent",
            responses = expectedAbsences,
            completed = #expectedAbsences > 0,
            disabled = false,
        },
    }

    return {
        procedure = procedure,
        phase = phase,
        endedAt = endedAt,
        specifiedTime = specifiedTime,
        stoppedAtSpecifiedTime = stoppedAtSpecifiedTime,
        goodStoppingPoint = goodStoppingPoint,
        sceneJustEnded = sceneJustEnded,
        nextSceneTeaser = nextSceneTeaser,
        closureOptions = closureOptions,
        feedbackPrompts = feedback,
        promptOptions = promptOptions,
        playerPriorities = playerPriorities,
        desiredDestinations = desiredDestinations,
        nextSession = nextSession,
        expectedAbsences = expectedAbsences,
        hasNextSceneHook = hasNextSceneHook,
        hasFeedbackPrompt = hasFeedbackPrompt,
        hasNextDirectionFeedback = hasNextDirectionFeedback,
        hasNextSessionReminder = hasNextSessionReminder,
        closedAtStoppingPoint = closedAtStoppingPoint,
        closeReasonPreview = closeReason,
        nextSessionReminderPreview = hasNextSessionReminder and {
            nextSession = nextSession,
            expectedAbsences = expectedAbsences,
        } or nil,
        nextSessionAgendaPreview = hasNextDirectionFeedback and {
            priorities = playerPriorities,
            destinations = desiredDestinations,
        } or nil,
        disabled = false,
        resultPreview = "end_of_play_recorded",
    }
end

function M.getNewAdventurerOnboardingOptions(opts)
    opts = opts or {}
    local actor = opts.actor or opts.adventurer or opts.newAdventurer or opts.player
    local onboarding = M.getNewAdventurerOnboarding()

    local pathTalents = inferredPathTalents(actor, opts)
    local kinTalent = inferredKinTalent(actor, opts)
    local masteredPathTalent = opts.masteredPathTalent or
        (actor and actor.callToAdventure and actor.callToAdventure.masteredPathTalent)
    local masteredCount = 0
    local allPathTalentsWritten = #pathTalents == 7
    local unmasteredPathTalentsInTraining = true
    for _, talentId in ipairs(pathTalents) do
        if not actorHasTalent(actor, talentId) then
            allPathTalentsWritten = false
            unmasteredPathTalentsInTraining = false
        elseif actorIsTalentMastered(actor, talentId) then
            masteredCount = masteredCount + 1
            masteredPathTalent = masteredPathTalent or talentId
        end
    end
    for _, talentId in ipairs(pathTalents) do
        if talentId ~= masteredPathTalent and actorIsTalentMastered(actor, talentId) then
            unmasteredPathTalentsInTraining = false
        end
    end

    local gearReady = opts.startingGearSelected == true or opts.gearReady == true or
        (actor and actor.startingGearSelected == true) or
        (actor and type(actor.startingGearSelection) == "table" and actor.startingGearSelection.complete == true)
    local nameKnown = actor and nonblank(actor.name) or opts.nameKnown == true
    local kinTalentWritten = kinTalent ~= nil and actorHasTalent(actor, kinTalent)
    local masteredOnePathTalent = masteredPathTalent ~= nil and masteredCount == 1
    local restInTraining = masteredOnePathTalent and unmasteredPathTalentsInTraining
    local sheetReady = opts.sheetReady == true or (nameKnown and kinTalentWritten and
        allPathTalentsWritten and masteredOnePathTalent and restInTraining)

    local priorMissing = {}
    local function checklistOption(id, label, completed)
        if not completed then
            priorMissing[#priorMissing + 1] = id
        end
        return {
            id = id,
            label = label,
            completed = completed == true,
            disabled = actor == nil,
            unavailableReason = actor == nil and "New adventurer required" or
                (not completed and "Checklist item required") or nil,
        }
    end

    local priorChecklist = {
        checklistOption("sheet_ready", "Adventurer sheet ready", sheetReady),
        checklistOption("kin_talent", "Kin talent written down", kinTalentWritten),
        checklistOption("seven_path_talents", "Seven path talents written down", allPathTalentsWritten),
        checklistOption("one_mastered_path_talent", "One mastered path talent chosen", masteredOnePathTalent),
        checklistOption("unmastered_path_talents_in_training", "Remaining path talents in training", restInTraining),
        checklistOption("omphalic_market_gear", "Omphalic Market gear chosen", gearReady),
        checklistOption("name", "Own name known", nameKnown),
    }
    local readyForFirstSession = actor ~= nil and sheetReady and gearReady and #priorMissing == 0

    local questions = {
        gameWorld = copyList(opts.gameWorldQuestions or opts.worldQuestions),
        rules = copyList(opts.rulesQuestions or opts.ruleQuestions),
        actionHelp = copyList(opts.actionHelpQuestions or opts.actionQuestions),
        clarifications = copyList(opts.clarifications or opts.clarificationQuestions),
        other = copyList(opts.questions),
    }
    local feedback = {
        wentWell = copyList(opts.wentWell or opts.liked or opts.likes),
        couldImprove = copyList(opts.couldImprove or opts.couldHaveGoneBetter or opts.concerns),
        other = copyList(opts.feedback or opts.playerFeedback),
    }
    local bondTargets = copyList(opts.bondTargets or opts.bonds or opts.selectedBonds)
    local appearance = opts.appearance or opts.looks or opts.description or (actor and actor.appearance)
    local questionCount = #questions.gameWorld + #questions.rules + #questions.actionHelp +
        #questions.clarifications + #questions.other
    local feedbackCount = #feedback.wentWell + #feedback.couldImprove + #feedback.other
    local hasAppearance = nonblank(appearance)
    local hasTwoBondTargets = #bondTargets == 2 or opts.bondsSelected == true
    local askedQuestions = questionCount > 0 or opts.askedQuestions == true
    local gaveFeedback = feedbackCount > 0 or opts.gaveFeedback == true

    local firstMissing = {}
    local function firstOption(id, label, completed)
        if not completed then
            firstMissing[#firstMissing + 1] = id
        end
        return {
            id = id,
            label = label,
            completed = completed == true,
            disabled = actor == nil,
            unavailableReason = actor == nil and "New adventurer required" or
                (not completed and "First-session item required") or nil,
        }
    end
    local firstChecklist = {
        firstOption("two_bond_targets", "Select two Bond targets", hasTwoBondTargets),
        firstOption("appearance", "Say what the adventurer looks like", hasAppearance),
        firstOption("questions", "Ask world, rules, action, or clarification questions", askedQuestions),
        firstOption("feedback", "Give first-session feedback", gaveFeedback),
    }
    local firstSessionComplete = actor ~= nil and hasAppearance and hasTwoBondTargets and
        askedQuestions and gaveFeedback

    local guild = copyList(opts.guild or opts.guildMembers or opts.activeGuild or opts.members)
    local requiredBondCount = 0
    local completedBondCount = 0
    local missingBondTargetIds = {}
    local actorKey = actorId(actor)
    for _, member in ipairs(guild) do
        local memberId = actorId(member)
        if memberId and memberId ~= actorKey then
            requiredBondCount = requiredBondCount + 1
            if actor and type(actor.bonds) == "table" and actor.bonds[memberId] ~= nil then
                completedBondCount = completedBondCount + 1
            else
                missingBondTargetIds[#missingBondTargetIds + 1] = memberId
            end
        end
    end
    local completeGuildBonds = opts.completeGuildBonds == true or
        (actor and actor.newAdventurerBondComplete == true) or
        (requiredBondCount > 0 and completedBondCount >= requiredBondCount)

    local guildRoster = opts.guildRoster or opts.roster or {}
    local currentQuest = opts.currentQuest or opts.quest or guildRoster.currentQuest or
        (actor and actor.guildQuest)
    local role = opts.role or opts.guildRole or (actor and actor.guildRole)
    local marchingOrder = opts.marchingOrder or opts.marchingRank or (actor and actor.marchingOrder)
    local hasRole = nonblank(role)
    local hasMarchingOrder = marchingOrder ~= nil and tostring(marchingOrder):gsub("^%s+", ""):gsub("%s+$", "") ~= ""
    local joinMissing = {}
    if not completeGuildBonds then
        joinMissing[#joinMissing + 1] = "complete_guild_bonds"
    end
    if currentQuest == nil then
        joinMissing[#joinMissing + 1] = "current_quest"
    end
    if not hasRole then
        joinMissing[#joinMissing + 1] = "guild_role"
    end
    if not hasMarchingOrder then
        joinMissing[#joinMissing + 1] = "marching_order"
    end
    local canJoinGuild = actor ~= nil and #joinMissing == 0
    local canElectReplacement = actor ~= nil and completeGuildBonds
    local decision = opts.decision or opts.secondSessionDecision or
        (opts.joinGuild == true and "join_guild" or nil) or
        ((opts.createReplacement == true or opts.electReplacement == true) and "create_replacement" or nil)

    local decisionOptions = {
        {
            id = "join_guild",
            label = "Join the current guild",
            selected = decision == "join_guild",
            currentQuest = currentQuest,
            role = role,
            marchingOrder = marchingOrder,
            xpAwarded = currentQuest ~= nil and 3 or 0,
            disabled = not canJoinGuild,
            unavailableReason = (not actor and "New adventurer required") or
                (not completeGuildBonds and "Complete guild Bonds required") or
                (currentQuest == nil and "Current quest required") or
                (not hasRole and "Guild role required") or
                (not hasMarchingOrder and "Marching order required") or nil,
            resultPreview = canJoinGuild and "new_adventurer_joined_guild" or nil,
        },
        {
            id = "create_replacement",
            label = "Create a better-fitting adventurer",
            selected = decision == "create_replacement",
            disabled = not canElectReplacement,
            unavailableReason = (not actor and "New adventurer required") or
                (not completeGuildBonds and "Complete guild Bonds required") or nil,
            resultPreview = canElectReplacement and "new_adventurer_replacement_elected" or nil,
        },
    }
    local secondResultPreview = "new_adventurer_second_session_followup_needed"
    if decision == "join_guild" and canJoinGuild then
        secondResultPreview = "new_adventurer_joined_guild"
    elseif decision == "create_replacement" and canElectReplacement then
        secondResultPreview = "new_adventurer_replacement_elected"
    elseif canJoinGuild or canElectReplacement then
        secondResultPreview = "new_adventurer_second_session_ready"
    end

    return {
        procedure = onboarding,
        actor = actor,
        actorId = actorId(actor),
        disabled = actor == nil,
        unavailableReason = actor == nil and "New adventurer required" or nil,
        priorToFirstSession = {
            checklist = priorChecklist,
            path = opts.path or actor and (actor.path or actor.pathName) or
                (actor and actor.callToAdventure and actor.callToAdventure.path),
            kinTalent = kinTalent,
            pathTalents = pathTalents,
            masteredPathTalent = masteredPathTalent,
            nameKnown = nameKnown,
            kinTalentWritten = kinTalentWritten,
            sevenPathTalentsWritten = allPathTalentsWritten,
            masteredOnePathTalent = masteredOnePathTalent,
            restInTraining = restInTraining,
            sheetReady = sheetReady,
            gearReady = gearReady,
            missing = priorMissing,
            readyForFirstSession = readyForFirstSession,
            needsFollowup = not readyForFirstSession,
            resultPreview = readyForFirstSession and
                "new_adventurer_pre_first_session_ready" or
                "new_adventurer_pre_first_session_followup_needed",
        },
        firstSession = {
            checklist = firstChecklist,
            appearance = appearance,
            bondTargets = bondTargets,
            questions = questions,
            feedback = feedback,
            questionCount = questionCount,
            feedbackCount = feedbackCount,
            hasAppearance = hasAppearance,
            hasTwoBondTargets = hasTwoBondTargets,
            askedQuestions = askedQuestions,
            gaveFeedback = gaveFeedback,
            missing = firstMissing,
            complete = firstSessionComplete,
            needsFollowup = not firstSessionComplete,
            resultPreview = firstSessionComplete and
                "new_adventurer_first_session_ready" or
                "new_adventurer_first_session_followup_needed",
        },
        priorToSecondSession = {
            guildMembers = guild,
            requiredBondCount = requiredBondCount,
            completedBondCount = completedBondCount,
            missingBondTargetIds = missingBondTargetIds,
            completeGuildBonds = completeGuildBonds,
            needsFollowup = not completeGuildBonds,
            resultPreview = completeGuildBonds and
                "new_adventurer_guild_bonds_ready" or
                "new_adventurer_guild_bonds_followup_needed",
        },
        endOfSecondSession = {
            currentQuest = currentQuest,
            role = role,
            marchingOrder = marchingOrder,
            completeGuildBonds = completeGuildBonds,
            missing = joinMissing,
            decisionOptions = decisionOptions,
            canJoinGuild = canJoinGuild,
            canElectReplacement = canElectReplacement,
            resultPreview = secondResultPreview,
        },
    }
end

function M.recordEndOfPlay(opts)
    opts = opts or {}
    local campaign = opts.campaign or opts.gameState or opts.state
    local log = opts.log or opts.campaignLog or opts.sessionLog
    if not log and campaign then
        campaign.campaignLog = campaign.campaignLog or {}
        log = campaign.campaignLog
    end

    local record = {
        result = "end_of_play_recorded",
        phase = opts.phase or opts.endedPhase or opts.afterPhase,
        endedAt = opts.endedAt or opts.time,
        specifiedTime = opts.specifiedTime or opts.scheduledEndTime or opts.timeLimit,
        stoppedAtSpecifiedTime = opts.stoppedAtSpecifiedTime == true or opts.timeLimitReached == true or
            opts.atSpecifiedTime == true,
        goodStoppingPoint = opts.goodStoppingPoint == true,
        sceneJustEnded = opts.sceneJustEnded == true,
        nextSceneTeaser = opts.nextSceneTeaser or opts.nextScene or opts.cliffhanger,
        feedback = copyList(opts.feedback or opts.feedbackRequests or opts.playerFeedback),
        playerPriorities = copyList(opts.playerPriorities or opts.nextActions or opts.whatNext),
        desiredDestinations = copyList(opts.desiredDestinations or opts.whereNext or opts.nextDestinations),
        nextSession = opts.nextSession or opts.nextSessionAt or opts.nextGame,
        expectedAbsences = copyList(opts.expectedAbsences or opts.absences or opts.absentPlayers),
        notes = opts.notes,
    }
    record.hasNextSceneHook = record.nextSceneTeaser ~= nil
    record.hasFeedbackPrompt = #record.feedback > 0
    record.hasNextDirectionFeedback = #record.playerPriorities > 0 or #record.desiredDestinations > 0
    record.hasNextSessionReminder = record.nextSession ~= nil or #record.expectedAbsences > 0
    record.closedAtStoppingPoint = record.goodStoppingPoint or record.sceneJustEnded or record.hasNextSceneHook
    record.closeReason = opts.closeReason or opts.reason or
        (record.stoppedAtSpecifiedTime and "specified_time" or nil) or
        (record.sceneJustEnded and "scene_ended" or nil) or
        (record.hasNextSceneHook and "new_scene_teaser" or nil) or
        "unspecified"

    if type(log) == "table" then
        log.sessionClosures = log.sessionClosures or {}
        log.sessionClosures[#log.sessionClosures + 1] = record
        log.lastSessionClosure = record
    end
    if campaign then
        campaign.lastSessionClosure = record
        if record.hasNextSessionReminder then
            campaign.nextSessionReminder = {
                nextSession = record.nextSession,
                expectedAbsences = record.expectedAbsences,
            }
        end
        if record.hasNextDirectionFeedback then
            campaign.nextSessionAgenda = {
                priorities = record.playerPriorities,
                destinations = record.desiredDestinations,
            }
        end
    end

    return true, "end_of_play_recorded", record
end

function M.recordNewAdventurerPreFirstSession(opts)
    opts = opts or {}
    local actor = opts.actor or opts.adventurer or opts.newAdventurer or opts.player
    if not actor then
        return false, "New adventurer required"
    end

    local campaign = opts.campaign or opts.gameState or opts.state
    local log = opts.log or opts.campaignLog or opts.sessionLog
    if not log and campaign then
        campaign.campaignLog = campaign.campaignLog or {}
        log = campaign.campaignLog
    end

    local pathTalents = inferredPathTalents(actor, opts)
    local kinTalent = inferredKinTalent(actor, opts)
    local masteredPathTalent = opts.masteredPathTalent or
        (actor.callToAdventure and actor.callToAdventure.masteredPathTalent)
    local masteredCount = 0
    local allPathTalentsWritten = #pathTalents == 7
    local unmasteredPathTalentsInTraining = true
    for _, talentId in ipairs(pathTalents) do
        if not actorHasTalent(actor, talentId) then
            allPathTalentsWritten = false
            unmasteredPathTalentsInTraining = false
        elseif actorIsTalentMastered(actor, talentId) then
            masteredCount = masteredCount + 1
            masteredPathTalent = masteredPathTalent or talentId
        end
    end
    for _, talentId in ipairs(pathTalents) do
        if talentId ~= masteredPathTalent and actorIsTalentMastered(actor, talentId) then
            unmasteredPathTalentsInTraining = false
        end
    end

    local gearReady = opts.startingGearSelected == true or opts.gearReady == true or
        actor.startingGearSelected == true or
        (type(actor.startingGearSelection) == "table" and actor.startingGearSelection.complete == true)
    local record = {
        result = "new_adventurer_pre_first_session_recorded",
        actor = actor,
        actorId = actorId(actor),
        name = actor.name,
        path = opts.path or actor.path or actor.pathName or (actor.callToAdventure and actor.callToAdventure.path),
        kinTalent = kinTalent,
        pathTalents = pathTalents,
        masteredPathTalent = masteredPathTalent,
        sheetReady = opts.sheetReady == true,
        gearReady = gearReady,
        notes = opts.notes,
        missing = {},
    }
    record.nameKnown = nonblank(actor.name) or opts.nameKnown == true
    record.kinTalentWritten = kinTalent ~= nil and actorHasTalent(actor, kinTalent)
    record.sevenPathTalentsWritten = allPathTalentsWritten
    record.masteredOnePathTalent = masteredPathTalent ~= nil and masteredCount == 1
    record.restInTraining = record.masteredOnePathTalent and unmasteredPathTalentsInTraining
    record.sheetReady = record.sheetReady or (record.nameKnown and record.kinTalentWritten and
        record.sevenPathTalentsWritten and record.masteredOnePathTalent and record.restInTraining)

    if not record.nameKnown then
        record.missing[#record.missing + 1] = "name"
    end
    if not record.kinTalentWritten then
        record.missing[#record.missing + 1] = "kin_talent"
    end
    if not record.sevenPathTalentsWritten then
        record.missing[#record.missing + 1] = "seven_path_talents"
    end
    if not record.masteredOnePathTalent then
        record.missing[#record.missing + 1] = "one_mastered_path_talent"
    end
    if not record.restInTraining then
        record.missing[#record.missing + 1] = "unmastered_path_talents_in_training"
    end
    if not record.gearReady then
        record.missing[#record.missing + 1] = "omphalic_market_gear"
    end

    record.readyForFirstSession = record.sheetReady and record.gearReady and #record.missing == 0
    record.needsFollowup = not record.readyForFirstSession

    actor.newAdventurerPreFirstSession = record
    appendRecord(actor, "newAdventurerPreFirstSessions", record)
    if type(log) == "table" then
        appendRecord(log, "newAdventurerPreFirstSessions", record)
        log.lastNewAdventurerPreFirstSession = record
    end
    if campaign then
        campaign.lastNewAdventurerPreFirstSession = record
        campaign.newAdventurerPreFirstSessions = campaign.newAdventurerPreFirstSessions or {}
        campaign.newAdventurerPreFirstSessions[#campaign.newAdventurerPreFirstSessions + 1] = record
    end

    return true, "new_adventurer_pre_first_session_recorded", record
end

function M.recordNewAdventurerFirstSession(opts)
    opts = opts or {}
    local actor = opts.actor or opts.adventurer or opts.newAdventurer or opts.player
    if not actor then
        return false, "New adventurer required"
    end

    local campaign = opts.campaign or opts.gameState or opts.state
    local log = opts.log or opts.campaignLog or opts.sessionLog
    if not log and campaign then
        campaign.campaignLog = campaign.campaignLog or {}
        log = campaign.campaignLog
    end

    local questions = {
        gameWorld = copyList(opts.gameWorldQuestions or opts.worldQuestions),
        rules = copyList(opts.rulesQuestions or opts.ruleQuestions),
        actionHelp = copyList(opts.actionHelpQuestions or opts.actionQuestions),
        clarifications = copyList(opts.clarifications or opts.clarificationQuestions),
        other = copyList(opts.questions),
    }
    local feedback = {
        wentWell = copyList(opts.wentWell or opts.liked or opts.likes),
        couldImprove = copyList(opts.couldImprove or opts.couldHaveGoneBetter or opts.concerns),
        other = copyList(opts.feedback or opts.playerFeedback),
    }
    local bondTargets = copyList(opts.bondTargets or opts.bonds or opts.selectedBonds)
    local appearance = opts.appearance or opts.looks or opts.description
    local questionCount = #questions.gameWorld + #questions.rules + #questions.actionHelp +
        #questions.clarifications + #questions.other
    local feedbackCount = #feedback.wentWell + #feedback.couldImprove + #feedback.other

    local record = {
        result = "new_adventurer_first_session_recorded",
        actor = actor,
        actorId = actorId(actor),
        appearance = appearance,
        bondTargets = bondTargets,
        questions = questions,
        feedback = feedback,
        questionCount = questionCount,
        feedbackCount = feedbackCount,
        notes = opts.notes,
    }
    record.hasAppearance = type(appearance) == "string" and appearance:gsub("^%s+", ""):gsub("%s+$", "") ~= ""
    record.hasTwoBondTargets = #bondTargets == 2 or opts.bondsSelected == true
    record.askedQuestions = questionCount > 0 or opts.askedQuestions == true
    record.gaveFeedback = feedbackCount > 0 or opts.gaveFeedback == true
    record.needsFollowup = not (record.hasAppearance and record.hasTwoBondTargets and
        record.askedQuestions and record.gaveFeedback)

    actor.newAdventurerFirstSession = record
    if record.hasAppearance then
        actor.appearance = appearance
    end
    appendRecord(actor, "newAdventurerFirstSessions", record)

    if type(log) == "table" then
        appendRecord(log, "newAdventurerFirstSessions", record)
        log.lastNewAdventurerFirstSession = record
    end
    if campaign then
        campaign.lastNewAdventurerFirstSession = record
        campaign.newAdventurerFirstSessions = campaign.newAdventurerFirstSessions or {}
        campaign.newAdventurerFirstSessions[#campaign.newAdventurerFirstSessions + 1] = record
    end

    return true, "new_adventurer_first_session_recorded", record
end

function M.markAbsentFromCrawl(opts)
    opts = opts or {}
    local actor = opts.actor or opts.absentPlayer or opts.player
    if not actor then
        return false, "Absent adventurer required"
    end

    local campaign = opts.campaign or opts.gameState or opts.state
    local phase = normalizePhase(opts.phase or opts.currentPhase or opts.missedPhase or
        (campaign and (campaign.phase or campaign.currentPhase)))
    if phase and phase ~= "crawl" and phase ~= "crawl_phase" and opts.allowOutsideCrawl ~= true then
        return false, "Crawl Phase absence required"
    end

    local pendingAction = copyActionData(opts.actionData or opts.action or opts.campAction)
    local assistants = normalizeAssistantList(opts)
    if returningActionRequiresAssistant(pendingAction) and #assistants == 0 then
        return false, "Assistant adventurer required"
    end

    local record = {
        actor = actor,
        actorId = actorId(actor),
        distanceRooms = tonumber(opts.distanceRooms) or 1,
        trailingBehind = true,
        phase = phase or "crawl",
        pendingCampAction = pendingAction,
        assistants = assistants,
        result = "adventurer_absent_from_crawl",
    }

    actor.absentFromCrawl = true
    actor.absentPhase = record.phase
    actor.trailingBehindGuild = true
    actor.distanceRoomsFromGuild = record.distanceRooms
    actor.returningPlayerAbsence = record
    actor.pendingReturningCampAction = pendingAction

    for _, assistant in ipairs(assistants or {}) do
        assistant.absentFromCrawl = true
        assistant.absentPhase = record.phase
        assistant.trailingBehindGuild = true
        assistant.distanceRoomsFromGuild = record.distanceRooms
        assistant.absentWithActorId = record.actorId
    end

    return true, "adventurer_absent_from_crawl", record
end

function M.resolveReturningPlayerCampAction(opts)
    opts = opts or {}
    local actor = opts.actor or opts.returningPlayer or opts.player
    if not actor then
        return false, "Returning adventurer required"
    end

    local absence = actor.returningPlayerAbsence or {}
    local actionData = copyActionData(opts.actionData or opts.action or opts.campAction or
        actor.pendingReturningCampAction or absence.pendingCampAction)
    if not actionData or not actionData.type then
        return false, "Camp Action required"
    end
    actionData.actor = actor
    local assistants = normalizeAssistantList(opts, absence)
    if returningActionRequiresAssistant(actionData) then
        if #assistants == 0 and not actionData.target then
            return false, "Assistant adventurer required"
        end
        actionData.target = actionData.target or assistants[1]
    end

    local context = {}
    for key, value in pairs(opts.context or {}) do
        context[key] = value
    end
    context.eventBus = opts.eventBus or context.eventBus
    context.guild = contextGuildWithAssistants(opts.guild or context.guild, actor, assistants)
    context.returningPlayer = true
    context.absentFromCrawl = true

    local ok, campResult = camp_actions.resolveAction(actionData, context)
    local detail = {
        actor = actor,
        actorId = actorId(actor),
        assistants = assistants,
        action = actionData,
        campResult = campResult,
        returningPlayer = true,
        result = ok and "returning_player_camp_action_resolved" or "returning_player_camp_action_failed",
    }
    if not ok then
        return false, campResult, detail
    end

    actor.absentFromCrawl = false
    actor.trailingBehindGuild = false
    actor.distanceRoomsFromGuild = 0
    actor.lastReturningPlayerAbsence = absence
    actor.returningPlayerAbsence = nil
    actor.pendingReturningCampAction = nil
    actor.returnedFromAbsence = true
    actor.returningPlayerCampAction = detail
    for _, assistant in ipairs(absence.assistants or {}) do
        if opts.keepAssistantsAbsent ~= true then
            assistant.absentFromCrawl = false
            assistant.trailingBehindGuild = false
            assistant.distanceRoomsFromGuild = 0
            assistant.absentWithActorId = nil
        end
    end
    return true, "returning_player_camp_action_resolved", detail
end

return M
