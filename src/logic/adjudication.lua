-- adjudication.lua
-- Backend helper for Chapter 1 GM response adjudication.

local meatgrinder = require('logic.meatgrinder')
local fate_binding = require('logic.fate_binding')

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

M.RESPONSES = {
    YES = "yes",
    SAY_MORE = "say_more",
    DRAW = "draw",
    NO = "no",
}

M.DRAW_TYPES = {
    TEST_FATE = "test_fate",
    MEATGRINDER = "meatgrinder",
}

M.MEATGRINDER_PENALTIES = {
    long_time = {
        id = "long_time",
        drawType = M.DRAW_TYPES.MEATGRINDER,
        majorArcanaTrigger = "I-V",
        triggeredCategory = meatgrinder.CATEGORIES.TORCHES_GUTTER,
        consequence = "torches_gutter",
    },
    noise = {
        id = "noise",
        drawType = M.DRAW_TYPES.MEATGRINDER,
        majorArcanaTrigger = "XV-XX",
        triggeredCategory = meatgrinder.CATEGORIES.RANDOM_ENCOUNTER,
        consequence = "random_encounter",
    },
}

local STOCK_PHRASES = {
    [M.RESPONSES.YES] = "Yes, you can do that.",
    [M.RESPONSES.SAY_MORE] = "Say more about what you're doing.",
    [M.RESPONSES.DRAW] = "Draw to see if you can do that.",
    [M.RESPONSES.NO] = "No, you can't do that.",
}

M.RESPONSE_DETAILS = {
    [M.RESPONSES.YES] = {
        key = M.RESPONSES.YES,
        label = "Yes, you can do that",
        stockPhrase = STOCK_PHRASES[M.RESPONSES.YES],
        summary = "The GM describes what happens and the adventurer succeeds without a draw.",
        useWhen = {
            "nothing prevents success",
            "the action is difficult but has no interesting risk",
            "the adventurer has plenty of time",
            "the adventurer has the appropriate tools",
            "the uncertainty is inconsequential",
        },
        canProceed = true,
        drawRequired = false,
    },
    [M.RESPONSES.SAY_MORE] = {
        key = M.RESPONSES.SAY_MORE,
        label = "Say more about what you're doing",
        stockPhrase = STOCK_PHRASES[M.RESPONSES.SAY_MORE],
        summary = "The GM asks for clarification when intent, tactics, scene understanding, or communication is unclear.",
        useWhen = {
            "the declared action is ambiguous",
            "the player and GM picture different scene facts",
            "the method or tactical details matter",
            "the GM needs a concrete approach before choosing a response",
        },
        canProceed = false,
        nextStep = "Shift to Yes, Draw, or No after the table reaches clarity.",
    },
    [M.RESPONSES.DRAW] = {
        key = M.RESPONSES.DRAW,
        label = "Draw to see if you can do that",
        stockPhrase = STOCK_PHRASES[M.RESPONSES.DRAW],
        summary = "Fraught, meaningful, or uncertain actions call for a Test of Fate.",
        useWhen = {
            "the action is dangerous",
            "the outcome is uncertain",
            "something important hangs in the balance",
        },
        avoids = {
            "inconsequential actions",
            "safe tasks where time and tools are available",
        },
        drawType = M.DRAW_TYPES.TEST_FATE,
        canProceed = true,
    },
    [M.RESPONSES.NO] = {
        key = M.RESPONSES.NO,
        label = "No, you can't do that",
        stockPhrase = STOCK_PHRASES[M.RESPONSES.NO],
        summary = "Impossible actions, automatic failures, missing-tool attempts, or weeks-long projects do not resolve as an immediate draw.",
        useWhen = {
            "the action is impossible in the fiction",
            "required tools are missing",
            "the action needs weeks or a long-term project",
            "a previous bound-by-fate result still stands",
        },
        canProceed = false,
        canOfferAlternative = true,
    },
}

M.ADJUDICATION_PROCEDURE = {
    source = "Core Rules Chapter 1: Adjudicating the game: GM responses",
    question = "Can my character do this?",
    stockResponses = {
        M.RESPONSES.YES,
        M.RESPONSES.SAY_MORE,
        M.RESPONSES.DRAW,
        M.RESPONSES.NO,
    },
    safeSuccessThreshold = {
        "no interesting risk",
        "plenty of time",
        "appropriate tools",
    },
    penaltyChoices = {
        {
            key = "long_time",
            label = "Taking a long time",
            prompt = "Tell the player the action will take time before they commit.",
            acceptedDraw = M.MEATGRINDER_PENALTIES.long_time,
        },
        {
            key = "noise",
            label = "Creating a lot of noise",
            prompt = "Tell the player the action will be noisy before they commit.",
            acceptedDraw = M.MEATGRINDER_PENALTIES.noise,
        },
    },
    testFateGuidance = {
        "Tests of Fate should be relatively rare.",
        "Tests of Fate should be tense.",
        "Do not test inconsequential actions.",
        "Draw when something important hangs in the balance.",
    },
    challengePhaseCaveat = "Challenge Actions and player hands bound Challenge Phase decisions, but the GM still adjudicates ambiguity.",
}

function M.getResponseDetails(response)
    if response == nil then
        return deepCopy(M.RESPONSE_DETAILS)
    end
    return deepCopy(M.RESPONSE_DETAILS[response])
end

function M.getAdjudicationProcedure()
    return deepCopy(M.ADJUDICATION_PROCEDURE)
end

local function anyTrue(opts, keys)
    for _, key in ipairs(keys) do
        if opts[key] == true then
            return true
        end
    end
    return false
end

local function hasListedValue(values, expected)
    if type(values) ~= "table" then
        return values == expected
    end
    if values[expected] == true then
        return true
    end
    for _, value in ipairs(values) do
        if value == expected then
            return true
        end
    end
    return false
end

local function addPenalty(penalties, seen, id)
    if M.MEATGRINDER_PENALTIES[id] and not seen[id] then
        penalties[#penalties + 1] = id
        seen[id] = true
    end
end

local function collectPenalties(opts)
    local penalties = {}
    local seen = {}
    local declared = opts.penalties or opts.consequences or opts.costs

    if hasListedValue(declared, "long_time") or hasListedValue(declared, "time") then
        addPenalty(penalties, seen, "long_time")
    end
    if hasListedValue(declared, "noise") or hasListedValue(declared, "loud_noise") then
        addPenalty(penalties, seen, "noise")
    end

    if anyTrue(opts, { "takesLongTime", "longTime", "timeCost", "slow" }) or
        opts.plentyTime == false or opts.enoughTime == false then
        addPenalty(penalties, seen, "long_time")
    end
    if anyTrue(opts, { "createsNoise", "makesNoise", "noisy", "loud", "noiseCost" }) then
        addPenalty(penalties, seen, "noise")
    end

    return penalties
end

local function acceptedPenalty(opts, id)
    if hasListedValue(opts.acceptedPenalties or opts.acceptedCosts, id) then
        return true
    end
    if id == "long_time" and anyTrue(opts, { "acceptLongTime", "spendTime", "spendsTime" }) then
        return true
    end
    if id == "noise" and anyTrue(opts, { "acceptNoise", "riskNoise", "risksNoise" }) then
        return true
    end
    return anyTrue(opts, {
        "acceptPenalty",
        "acceptCost",
        "acceptConsequence",
        "acceptedPenalty",
        "proceedWithPenalty",
        "playerAccepted",
    })
end

local function lacksRequiredTools(opts)
    if anyTrue(opts, { "lacksTools", "missingTools", "noTools" }) then
        return true
    end
    if opts.hasTools == false or opts.appropriateTools == false or opts.toolsAvailable == false then
        return true
    end
    if opts.requiresTools == true and opts.hasTools ~= true and
        opts.appropriateTools ~= true and opts.toolsAvailable ~= true then
        return true
    end
    return false
end

local function needsClarification(opts)
    return anyTrue(opts, {
        "ambiguous",
        "unclear",
        "needsClarification",
        "miscommunication",
        "intentUnclear",
        "tacticsUnclear",
    })
end

local function impossible(opts)
    return anyTrue(opts, {
        "impossible",
        "autoFail",
        "automaticFailure",
        "narrativelyImpossible",
        "forbidden",
    })
end

local function requiresExtendedProject(opts)
    if anyTrue(opts, {
        "requiresExtendedProject",
        "requiresLongTermProject",
        "requiresWeeks",
        "needsWeeks",
        "notImmediate",
        "tooLongForCurrentAction",
    }) then
        return true
    end
    local timeScale = type(opts.timeScale) == "string" and opts.timeScale:lower() or nil
    local requiredTime = type(opts.requiredTime) == "string" and opts.requiredTime:lower() or nil
    return timeScale == "weeks" or timeScale == "months" or timeScale == "extended_project" or
        requiredTime == "weeks" or requiredTime == "months" or requiredTime == "several_weeks"
end

local function isInconsequential(opts)
    if anyTrue(opts, {
        "inconsequential",
        "trivialStakes",
        "lowStakes",
        "noMeaningfulStakes",
    }) then
        return true
    end
    if opts.stakes == false or opts.important == false or opts.somethingImportant == false then
        return true
    end
    local stakes = type(opts.stakes) == "string" and opts.stakes:lower() or nil
    return stakes == "none" or stakes == "low" or stakes == "trivial" or stakes == "inconsequential"
end

local function hasInterestingRisk(opts)
    if opts.risk == false or opts.interestingRisk == false or opts.noInterestingRisk == true then
        return false
    end
    if isInconsequential(opts) then
        return false
    end
    return anyTrue(opts, {
        "risk",
        "interestingRisk",
        "uncertain",
        "outcomeUncertain",
        "fraught",
        "dangerous",
        "requiresTestFate",
        "testFate",
    })
end

local function cardForPenalty(opts, id)
    local cards = opts.majorCards or opts.penaltyCards
    if type(cards) == "table" then
        if cards[id] then
            return cards[id]
        end
        if #cards > 0 then
            return cards[1]
        end
    end
    return opts.majorCard or opts.card
end

local function buildPenaltyDraw(opts, id)
    local spec = M.MEATGRINDER_PENALTIES[id]
    local draw = {}
    for key, value in pairs(spec) do
        draw[key] = value
    end

    local card = cardForPenalty(opts, id)
    if type(card) == "table" then
        draw.card = card
        local value = tonumber(card.value)
        if id == "long_time" then
            draw.triggered = value ~= nil and value >= 1 and value <= 5
        elseif id == "noise" then
            draw.triggered = value ~= nil and value >= 15 and value <= 20
        end
    end

    return draw
end

local function buildPenaltyDetails(opts, penalties)
    local details = {}
    for _, id in ipairs(penalties or {}) do
        details[#details + 1] = buildPenaltyDraw(opts, id)
    end
    return details
end

local function buildTestFateDraw(opts)
    return {
        id = "test_fate",
        drawType = M.DRAW_TYPES.TEST_FATE,
        attribute = opts.attribute or opts.testAttribute,
        targetSuit = opts.targetSuit or opts.suit,
        reason = "uncertain_or_fraught",
    }
end

local function automaticSuccessReason(opts)
    if isInconsequential(opts) then
        return "inconsequential_action"
    end
    if opts.difficult == true or opts.difficulty == "difficult" then
        return "difficult_but_safe"
    end
    return "no_interesting_risk"
end

local function verdict(response, result, opts, extra)
    extra = extra or {}
    local detail = {
        response = response,
        result = result,
        stockPhrase = STOCK_PHRASES[response],
        actor = opts.actor,
        action = opts.action or opts.intent,
        reason = extra.reason,
        canProceed = extra.canProceed,
    }
    for key, value in pairs(extra) do
        detail[key] = value
    end
    return detail
end

local function boundByFateStatus(opts)
    local records = opts.boundByFateRecords or opts.fateBindings or opts.boundTests
    if type(records) ~= "table" then
        return nil
    end
    return fate_binding.getStatus(records, opts)
end

function M.adjudicateAction(opts)
    opts = opts or {}

    if needsClarification(opts) then
        return verdict(M.RESPONSES.SAY_MORE, "clarification_required", opts, {
            canProceed = false,
            question = opts.question or opts.clarifyingQuestion,
            reason = "ambiguous_action",
        })
    end

    if impossible(opts) then
        return verdict(M.RESPONSES.NO, "impossible", opts, {
            canProceed = false,
            reason = "impossible",
        })
    end

    if requiresExtendedProject(opts) then
        return verdict(M.RESPONSES.NO, "extended_project_required", opts, {
            canProceed = false,
            reason = "requires_extended_project",
            requiredTime = opts.requiredTime or opts.timeScale,
            alternative = opts.alternative or opts.allowedAlternative,
        })
    end

    if lacksRequiredTools(opts) then
        return verdict(M.RESPONSES.NO, "missing_tools", opts, {
            canProceed = false,
            reason = "missing_tools",
        })
    end

    local fateStatus = boundByFateStatus(opts)
    if fateStatus and not fateStatus.allowed then
        return verdict(M.RESPONSES.NO, "bound_by_fate", opts, {
            canProceed = false,
            reason = "result_stands",
            boundByFate = fateStatus,
        })
    end

    local penalties = collectPenalties(opts)
    local unacceptedPenalties = {}
    for _, id in ipairs(penalties) do
        if not acceptedPenalty(opts, id) then
            unacceptedPenalties[#unacceptedPenalties + 1] = id
        end
    end

    if #unacceptedPenalties > 0 then
        return verdict(M.RESPONSES.YES, "penalty_choice_required", opts, {
            canProceed = true,
            choiceRequired = true,
            penalties = buildPenaltyDetails(opts, unacceptedPenalties),
            reason = "penalty_requires_player_choice",
            boundByFate = fateStatus,
        })
    end

    if hasInterestingRisk(opts) then
        local draws = { buildTestFateDraw(opts) }
        for _, id in ipairs(penalties) do
            draws[#draws + 1] = buildPenaltyDraw(opts, id)
        end
        return verdict(M.RESPONSES.DRAW, "test_fate_required", opts, {
            canProceed = true,
            drawType = M.DRAW_TYPES.TEST_FATE,
            draws = draws,
            reason = "uncertain_or_fraught",
            boundByFate = fateStatus,
        })
    end

    if #penalties > 0 then
        return verdict(M.RESPONSES.DRAW, "meatgrinder_penalty_draw", opts, {
            canProceed = true,
            drawType = M.DRAW_TYPES.MEATGRINDER,
            draws = buildPenaltyDetails(opts, penalties),
            reason = "accepted_penalty",
            boundByFate = fateStatus,
        })
    end

    return verdict(M.RESPONSES.YES, "automatic_success", opts, {
        canProceed = true,
        reason = automaticSuccessReason(opts),
        boundByFate = fateStatus,
    })
end

function M.getAdjudicationOptions(opts)
    opts = opts or {}
    local preview = type(opts.verdict) == "table" and deepCopy(opts.verdict) or M.adjudicateAction(opts)
    local procedure = M.getAdjudicationProcedure()
    local responseDetails = M.getResponseDetails()

    local function firstDrawWithId(id)
        for _, draw in ipairs(preview.penalties or {}) do
            if draw.id == id then
                return draw
            end
        end
        for _, draw in ipairs(preview.draws or {}) do
            if draw.id == id then
                return draw
            end
        end
        return nil
    end

    local function firstDrawOfType(drawType)
        for _, draw in ipairs(preview.draws or {}) do
            if draw.drawType == drawType then
                return draw
            end
        end
        return nil
    end

    local responseOptions = {}
    local selectedOption = nil
    for index, response in ipairs(procedure.stockResponses or {}) do
        local detail = responseDetails[response] or {}
        local option = {
            key = response,
            id = response,
            index = index,
            label = detail.label or response,
            stockPhrase = detail.stockPhrase,
            summary = detail.summary,
            useWhen = deepCopy(detail.useWhen),
            avoids = deepCopy(detail.avoids),
            canProceed = detail.canProceed,
            drawRequired = detail.drawRequired or detail.drawType ~= nil,
            drawType = detail.drawType,
            nextStep = detail.nextStep,
            canOfferAlternative = detail.canOfferAlternative,
            selected = preview.response == response,
        }
        if option.selected then
            option.result = preview.result
            option.reason = preview.reason
            option.choiceRequired = preview.choiceRequired == true
            selectedOption = option
        end
        responseOptions[#responseOptions + 1] = option
    end

    local penaltyOptions = {}
    for index, choice in ipairs(procedure.penaltyChoices or {}) do
        local draw = firstDrawWithId(choice.key)
        local acceptedDraw = choice.acceptedDraw or {}
        penaltyOptions[#penaltyOptions + 1] = {
            key = choice.key,
            id = choice.key,
            index = index,
            label = choice.label,
            prompt = choice.prompt,
            drawType = acceptedDraw.drawType,
            majorArcanaTrigger = acceptedDraw.majorArcanaTrigger,
            triggeredCategory = acceptedDraw.triggeredCategory,
            consequence = acceptedDraw.consequence,
            selected = draw ~= nil,
            relevant = draw ~= nil,
            choiceRequired = preview.choiceRequired == true and draw ~= nil,
            accepted = preview.result == "meatgrinder_penalty_draw" and draw ~= nil,
            card = draw and deepCopy(draw.card) or nil,
            triggered = draw and draw.triggered or nil,
        }
    end

    local testFateDraw = firstDrawOfType(M.DRAW_TYPES.TEST_FATE)
    local meatgrinderDraw = firstDrawOfType(M.DRAW_TYPES.MEATGRINDER)
    return {
        procedure = procedure,
        responseOptions = responseOptions,
        options = responseOptions,
        selectedResponse = preview.response,
        selectedOption = selectedOption,
        verdictPreview = preview,
        action = opts.action or opts.intent or preview.action,
        actor = opts.actor or preview.actor,
        penaltyOptions = penaltyOptions,
        testFateOption = {
            key = M.DRAW_TYPES.TEST_FATE,
            id = M.DRAW_TYPES.TEST_FATE,
            label = responseDetails[M.RESPONSES.DRAW] and responseDetails[M.RESPONSES.DRAW].label,
            guidance = deepCopy(procedure.testFateGuidance),
            selected = testFateDraw ~= nil,
            relevant = testFateDraw ~= nil,
            attribute = testFateDraw and testFateDraw.attribute or nil,
            targetSuit = testFateDraw and testFateDraw.targetSuit or nil,
            reason = testFateDraw and testFateDraw.reason or nil,
        },
        requiresClarification = preview.response == M.RESPONSES.SAY_MORE,
        requiresPlayerChoice = preview.choiceRequired == true,
        requiresTestFate = testFateDraw ~= nil,
        requiresMeatgrinder = meatgrinderDraw ~= nil,
        hasPenaltyChoice = preview.choiceRequired == true and #penaltyOptions > 0,
        automaticSuccess = preview.result == "automatic_success",
        blocked = preview.response == M.RESPONSES.NO,
        challengePhaseCaveat = procedure.challengePhaseCaveat,
        resultPreview = "adjudication_options_ready",
    }
end

return M
