-- bond_rules.lua
-- Rulebook-facing Bond charge adjudication helpers.

local adventurer = require('entities.adventurer')

local M = {}

M.RESULTS = {
    CHARGED = "bond_charged",
    NOT_QUALIFIED = "bond_charge_not_qualified",
    CONSENT_REQUIRED = "bond_consent_required",
    SWAPPED_TO_ALLY = "bond_swapped_to_ally",
    MISSING_BOND = "bond_missing",
}

M.TRIGGERS = {
    PLAY_TO_HILT = "play_to_hilt",
    DANGER = "danger",
    GM_AWARD = "gm_award",
    EXCELLENT_ROLEPLAY = "excellent_roleplay",
    ALLY_LAUGH = "ally_laugh",
    ADVERSARY_WITNESS_FAIL_TEST = "adversary_witness_fail_test",
    BIG_LITTLE_AIDS_WEAK_ATTRIBUTE = "big_little_aids_weak_attribute",
    BEST_FRIEND_REVEAL_SECRET = "best_friend_reveal_secret",
    LOVE_ROMANTIC_GESTURE = "love_romantic_gesture",
    MASTER_PAYMENT = "master_payment",
    HENCHMAN_CAMP_ACTION_BENEFITS_MASTER = "henchman_camp_action_benefits_master",
    MENTEE_ASKS_ADVICE = "mentee_asks_advice",
    MENTOR_ADVICE_FOLLOWED = "mentor_advice_followed",
    RIVAL_WITNESS_SUCCESS_TEST = "rival_witness_success_test",
    SIBLING_AIDS_TEST = "sibling_aids_test",
    UNREQUITED_KINDNESS_REBUFFED = "unrequited_kindness_rebuffed",
    WARD_SURVIVES_CHALLENGE_UNWOUNDED = "ward_survives_challenge_unwounded",
}

M.NEGATIVE_BONDS = {
    adversary = true,
    rival = true,
    unrequited_love = true,
}

local TRIGGER_ALIASES = {
    played_to_hilt = M.TRIGGERS.PLAY_TO_HILT,
    roleplay_to_hilt = M.TRIGGERS.PLAY_TO_HILT,
    puts_in_danger = M.TRIGGERS.DANGER,
    danger_for_bond = M.TRIGGERS.DANGER,
    gm_calls_for_charge = M.TRIGGERS.GM_AWARD,
    excellent_role_play = M.TRIGGERS.EXCELLENT_ROLEPLAY,
    laugh = M.TRIGGERS.ALLY_LAUGH,
    adversary_failed_test = M.TRIGGERS.ADVERSARY_WITNESS_FAIL_TEST,
    big_little_aid = M.TRIGGERS.BIG_LITTLE_AIDS_WEAK_ATTRIBUTE,
    best_friend_secret = M.TRIGGERS.BEST_FRIEND_REVEAL_SECRET,
    romantic_gesture = M.TRIGGERS.LOVE_ROMANTIC_GESTURE,
    love_flowers = M.TRIGGERS.LOVE_ROMANTIC_GESTURE,
    master_compensation = M.TRIGGERS.MASTER_PAYMENT,
    henchman_benefits_master = M.TRIGGERS.HENCHMAN_CAMP_ACTION_BENEFITS_MASTER,
    mentee_advice = M.TRIGGERS.MENTEE_ASKS_ADVICE,
    mentor_advice = M.TRIGGERS.MENTOR_ADVICE_FOLLOWED,
    rival_success = M.TRIGGERS.RIVAL_WITNESS_SUCCESS_TEST,
    sibling_aid = M.TRIGGERS.SIBLING_AIDS_TEST,
    unrequited_rebuff = M.TRIGGERS.UNREQUITED_KINDNESS_REBUFFED,
    ward_unwounded = M.TRIGGERS.WARD_SURVIVES_CHALLENGE_UNWOUNDED,
}

local function actorId(actor)
    if type(actor) ~= "table" then
        return actor
    end
    return actor.id or actor.entityId or actor.name
end

local function normalizeTrigger(trigger)
    local normalized = tostring(trigger or ""):lower()
    normalized = normalized:gsub("[’']", "")
    normalized = normalized:gsub("[^%w]+", "_")
    normalized = normalized:gsub("^_+", ""):gsub("_+$", "")
    return TRIGGER_ALIASES[normalized] or normalized
end

local function copyList(values)
    local copy = {}
    for i, value in ipairs(values or {}) do
        copy[i] = value
    end
    return copy
end

local function getBond(actor, targetId)
    if type(actor) ~= "table" or not targetId then
        return nil
    end
    return actor.bonds and actor.bonds[targetId] or nil
end

local function ensureBond(actor, targetId, status)
    if type(actor) ~= "table" or not targetId then
        return nil
    end
    actor.bonds = actor.bonds or {}
    actor.bonds[targetId] = actor.bonds[targetId] or {
        status = status,
        charged = false,
    }
    if status then
        actor.bonds[targetId].status = status
    end
    adventurer.applyBondMetadata(actor.bonds[targetId], status)
    return actor.bonds[targetId]
end

local function applyBondStatus(actor, targetId, status)
    if type(actor) ~= "table" or not targetId then
        return nil
    end
    if actor.setBond then
        actor:setBond(targetId, status)
        return actor.bonds and actor.bonds[targetId] or nil
    end
    return ensureBond(actor, targetId, status)
end

local function chargeActorBond(actor, targetId)
    if type(actor) ~= "table" or not targetId then
        return false
    end
    if actor.chargeBond then
        return actor:chargeBond(targetId)
    end
    local bond = getBond(actor, targetId)
    if not bond then
        return false
    end
    bond.charged = true
    return true
end

local function appendRecord(list, record)
    if type(list) == "table" then
        list[#list + 1] = record
    end
end

local function appendActorRecord(actor, record)
    if type(actor) ~= "table" then
        return
    end
    actor.bondChargeLog = actor.bondChargeLog or {}
    actor.bondChargeLog[#actor.bondChargeLog + 1] = record
end

local function boolNotFalse(value)
    return value ~= false
end

local function statusFromContext(opts, bond)
    if opts.status or opts.bondType then
        return adventurer.normalizeBondStatus(opts.status or opts.bondType) or opts.status or opts.bondType
    end
    return bond and (bond.bondType or adventurer.normalizeBondStatus(bond.status) or bond.status) or nil
end

local function triggerMatches(trigger, bondType, opts)
    if trigger == M.TRIGGERS.PLAY_TO_HILT or trigger == M.TRIGGERS.DANGER or
        trigger == M.TRIGGERS.GM_AWARD or trigger == M.TRIGGERS.EXCELLENT_ROLEPLAY then
        return true, false, "roleplay_or_danger"
    end

    if trigger == M.TRIGGERS.ALLY_LAUGH then
        return bondType == "ally" and boolNotFalse(opts.inCharacter) and boolNotFalse(opts.outOfCharacter),
            false, "ally_laugh"
    end

    if trigger == M.TRIGGERS.ADVERSARY_WITNESS_FAIL_TEST then
        return bondType == "adversary" and boolNotFalse(opts.witnessed) and
            (opts.testFailed == true or opts.testResult == "failure" or opts.testResult == "great_failure"),
            false, "adversary_failed_test"
    end

    if trigger == M.TRIGGERS.BIG_LITTLE_AIDS_WEAK_ATTRIBUTE then
        return bondType == "big_little" and boolNotFalse(opts.aided) and boolNotFalse(opts.testOfFate) and
            (opts.weakestAttribute == true or opts.weakAttribute == true),
            true, "big_little_aid"
    end

    if trigger == M.TRIGGERS.BEST_FRIEND_REVEAL_SECRET then
        return bondType == "best_friend" and (opts.secretRevealed == true or opts.revealedSecret == true),
            true, "best_friend_secret"
    end

    if trigger == M.TRIGGERS.LOVE_ROMANTIC_GESTURE then
        return bondType == "love" and (opts.romanticGesture == true or opts.gushy == true or
            opts.riskedNeck == true or opts.flowers == true),
            false, "love_romantic_gesture"
    end

    if trigger == M.TRIGGERS.MASTER_PAYMENT then
        return bondType == "master_henchman" and opts.role == "master" and
            (opts.compensated == true or opts.payment == true or opts.paid == true),
            false, "master_payment"
    end

    if trigger == M.TRIGGERS.HENCHMAN_CAMP_ACTION_BENEFITS_MASTER then
        return bondType == "master_henchman" and opts.role == "henchman" and boolNotFalse(opts.campAction) and
            opts.benefitedMaster == true and opts.benefitedSelf ~= true,
            false, "henchman_camp_action"
    end

    if trigger == M.TRIGGERS.MENTEE_ASKS_ADVICE then
        return bondType == "mentor_mentee" and opts.role == "mentee" and
            opts.askedAdvice == true and opts.adviceGiven == true,
            false, "mentee_advice"
    end

    if trigger == M.TRIGGERS.MENTOR_ADVICE_FOLLOWED then
        return bondType == "mentor_mentee" and opts.role == "mentor" and opts.adviceFollowed == true,
            false, "mentor_advice_followed"
    end

    if trigger == M.TRIGGERS.RIVAL_WITNESS_SUCCESS_TEST then
        return bondType == "rival" and boolNotFalse(opts.witnessed) and
            (opts.testSucceeded == true or opts.testResult == "success" or opts.testResult == "great_success"),
            false, "rival_success_test"
    end

    if trigger == M.TRIGGERS.SIBLING_AIDS_TEST then
        return bondType == "sibling" and boolNotFalse(opts.aided) and boolNotFalse(opts.testOfFate),
            false, "sibling_aid"
    end

    if trigger == M.TRIGGERS.UNREQUITED_KINDNESS_REBUFFED then
        return bondType == "unrequited_love" and opts.kindAct == true and
            (opts.rebuffed == true or opts.turnedDown == true),
            false, "unrequited_rebuff"
    end

    if trigger == M.TRIGGERS.WARD_SURVIVES_CHALLENGE_UNWOUNDED then
        return bondType == "ward" and boolNotFalse(opts.challengeCompleted) and
            opts.wounded ~= true and (opts.woundsTaken == nil or opts.woundsTaken == 0),
            false, "ward_unwounded"
    end

    return false, false, "unknown_trigger"
end

local function emit(eventBus, eventType, detail)
    if eventBus and eventBus.emit then
        eventBus:emit(eventType, detail)
    end
end

function M.requiresConsent(status)
    local normalized = adventurer.normalizeBondStatus(status) or status
    return M.NEGATIVE_BONDS[normalized] == true
end

function M.applyConsentFallback(opts)
    opts = opts or {}
    local actor = opts.actor
    local target = opts.target
    local targetId = opts.targetId or actorId(target)
    local actorIdValue = actorId(actor)
    local bond = getBond(actor, targetId)
    local status = statusFromContext(opts, bond)
    local normalized = adventurer.normalizeBondStatus(status) or status

    if not M.requiresConsent(normalized) then
        return false, nil
    end

    if opts.consent == false or opts.tableConsent == false or opts.fun == false or opts.enjoyed == false then
        local updated = applyBondStatus(actor, targetId, "ally")
        local detail = {
            actorId = actorIdValue,
            targetId = targetId,
            previousBondType = normalized,
            bondType = updated and updated.bondType or "ally",
            status = updated and updated.status or "ally",
            result = M.RESULTS.SWAPPED_TO_ALLY,
        }
        appendRecord(opts.records, detail)
        appendActorRecord(actor, detail)
        emit(opts.eventBus, M.RESULTS.SWAPPED_TO_ALLY, detail)
        return true, detail
    end

    if opts.requireConsent == true and opts.consent ~= true and opts.tableConsent ~= true then
        return true, {
            actorId = actorIdValue,
            targetId = targetId,
            bondType = normalized,
            result = M.RESULTS.CONSENT_REQUIRED,
        }
    end

    return false, nil
end

function M.evaluateCharge(opts)
    opts = opts or {}
    local actor = opts.actor
    local target = opts.target
    local targetId = opts.targetId or actorId(target)
    local bond = opts.bond or getBond(actor, targetId)
    local trigger = normalizeTrigger(opts.trigger)

    if not bond and opts.status then
        bond = ensureBond(actor, targetId, opts.status)
    end
    if not bond then
        return false, M.RESULTS.MISSING_BOND, {
            actorId = actorId(actor),
            targetId = targetId,
            trigger = trigger,
            result = M.RESULTS.MISSING_BOND,
        }
    end

    adventurer.applyBondMetadata(bond, opts.status)
    local status = statusFromContext(opts, bond)
    local bondType = adventurer.normalizeBondStatus(status) or bond.bondType or status
    local handled, consentDetail = M.applyConsentFallback(opts)
    if handled then
        if consentDetail.result == M.RESULTS.SWAPPED_TO_ALLY then
            return true, M.RESULTS.SWAPPED_TO_ALLY, consentDetail
        end
        return false, M.RESULTS.CONSENT_REQUIRED, consentDetail
    end

    local qualifies, reciprocal, reason = triggerMatches(trigger, bondType, opts)
    local detail = {
        actorId = actorId(actor),
        targetId = targetId,
        trigger = trigger,
        bondType = bondType,
        status = bond.status,
        reason = reason,
        reciprocal = reciprocal,
        result = qualifies and M.RESULTS.CHARGED or M.RESULTS.NOT_QUALIFIED,
    }
    return qualifies, detail.result, detail
end

function M.resolveCharge(opts)
    opts = opts or {}
    local actor = opts.actor
    local target = opts.target
    local targetId = opts.targetId or actorId(target)
    local ok, result, detail = M.evaluateCharge(opts)

    if not ok then
        return false, result, detail
    end

    if result == M.RESULTS.SWAPPED_TO_ALLY then
        return true, result, detail
    end

    detail.charged = chargeActorBond(actor, targetId)
    detail.chargedActors = detail.charged and { detail.actorId } or {}
    detail.reciprocalCharged = false

    if detail.reciprocal then
        local actorIdValue = actorId(actor)
        local reciprocalBond = getBond(target, actorIdValue)
        if reciprocalBond then
            detail.reciprocalCharged = chargeActorBond(target, actorIdValue)
            if detail.reciprocalCharged then
                detail.chargedActors[#detail.chargedActors + 1] = detail.targetId
            end
        end
    end

    detail.chargedActors = copyList(detail.chargedActors)
    appendRecord(opts.records, detail)
    appendActorRecord(actor, detail)
    emit(opts.eventBus, M.RESULTS.CHARGED, detail)
    return detail.charged, result, detail
end

return M
