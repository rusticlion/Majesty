-- bid_lore_engine.lua
-- Deterministic Bid Lore adjudication for Challenge actions.

local lore_subjects = require('data.lore.lore_subjects')
local question_types = require('data.lore.question_types')
local motif_tag_map = require('data.lore.motif_tag_map')

local M = {}

local ACCEPT = "accepted"
local REPHRASE = "rephrase_needed"
local REJECT_MOTIF = "rejected_unknown_with_motif"
local REJECT_SUBJECT = "rejected_subject_unavailable"

local function normalizeText(value)
    if type(value) ~= "string" then
        return ""
    end
    local lowered = value:lower()
    lowered = lowered:gsub("^%s+", ""):gsub("%s+$", "")
    return lowered
end

local function normalizeTalentKey(value)
    return tostring(value or ""):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
end

local function getEntityTalentEntry(actor, talentId)
    local talents = actor and actor.talents
    if type(talents) ~= "table" then
        return nil
    end

    local requested = normalizeTalentKey(talentId)
    for key, value in pairs(talents) do
        if normalizeTalentKey(key) == requested then
            return value
        end
        if type(value) == "table" and normalizeTalentKey(value.id or value.name or value.talentId) == requested then
            return value
        end
    end

    return nil
end

local function getUsableTalentEntry(actor, talentId)
    local entry = getEntityTalentEntry(actor, talentId)
    if not entry or entry == false then
        return nil
    end
    if type(entry) == "table" and entry.wounded == true then
        return nil
    end
    return entry
end

local function entityHasUsableTalent(actor, talentId)
    local entry = getUsableTalentEntry(actor, talentId)
    if not entry then
        return false
    end
    if type(entry) == "table" then
        return entry.wounded ~= true
    end
    return entry == true
end

local HUNTER_TALENT_IDS = {
    "monster_hunter",
    "beast_hunter",
    "elemental_hunter",
    "man_hunter",
    "spirit_hunter",
    "undead_hunter",
    "witch_hunter",
}

local HUNTER_DEFAULT_FOES = {
    beast_hunter = "Beast",
    elemental_hunter = "Elemental",
    man_hunter = "Man",
    spirit_hunter = "Spirit",
    undead_hunter = "Undead",
    witch_hunter = "Witch",
}

local function titleCaseKey(value)
    local text = tostring(value or ""):lower():gsub("[_%-%s]+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return nil
    end
    return (text:gsub("(%a)([%w']*)", function(first, rest)
        return first:upper() .. rest
    end))
end

local function getHunterFoeLabel(talentId, entry)
    if type(entry) == "table" then
        local value = entry.foe or entry.hatedFoe or entry.hunterFoe or entry.category or
            entry.enemyCategory or entry.specializationCategory
        if value then
            return titleCaseKey(value)
        end
    end

    return HUNTER_DEFAULT_FOES[normalizeTalentKey(talentId)]
end

local function collectHunterMotifs(actor)
    local motifs = {}
    for _, talentId in ipairs(HUNTER_TALENT_IDS) do
        local entry = getUsableTalentEntry(actor, talentId)
        if entry then
            local foe = getHunterFoeLabel(talentId, entry)
            if foe then
                motifs[#motifs + 1] = foe .. " Hunter"
            end
        end
    end
    return motifs
end

local function collectActors(value, out)
    out = out or {}
    if type(value) ~= "table" then
        return out
    end

    if value.motifs or value.talents or value.id or value.name then
        out[#out + 1] = value
        return out
    end

    for _, item in pairs(value) do
        collectActors(item, out)
    end
    return out
end

local function cloneArray(items)
    local out = {}
    for i = 1, #items do
        out[i] = items[i]
    end
    return out
end

local function toSet(items)
    local set = {}
    for _, item in ipairs(items or {}) do
        set[item] = true
    end
    return set
end

local function hasAny(items, wanted)
    local set = toSet(items)
    for _, tag in ipairs(wanted or {}) do
        if set[tag] then
            return true
        end
    end
    return false
end

local function collectAnswerQuestionIds(subject)
    local ids = {}
    local answers = subject and subject.answers or {}
    for _, questionId in ipairs(question_types.ORDER) do
        if answers[questionId] then
            ids[#ids + 1] = questionId
        end
    end
    return ids
end

local function overlapCount(a, b)
    local bSet = toSet(b)
    local count = 0
    for _, item in ipairs(a or {}) do
        if bSet[item] then
            count = count + 1
        end
    end
    return count
end

local function uniqueSortedTags(tags)
    local seen = {}
    local out = {}
    for _, tag in ipairs(tags or {}) do
        if not seen[tag] then
            seen[tag] = true
            out[#out + 1] = tag
        end
    end
    table.sort(out)
    return out
end

local function listContains(items, value)
    for _, item in ipairs(items or {}) do
        if item == value then
            return true
        end
    end
    return false
end

local function shortQuestionList(questionIds)
    local out = {}
    for _, questionId in ipairs(questionIds or {}) do
        local q = question_types.get(questionId)
        if q then
            out[#out + 1] = q.name
        end
    end
    return out
end

function M.createBidLoreEngine(config)
    config = config or {}

    local engine = {
        subjects = config.subjects or lore_subjects.SUBJECTS,
        motifTagMap = config.motifTagMap or motif_tag_map,
        questions = config.questions or question_types,
        subjectsById = {},
    }

    for _, subject in ipairs(engine.subjects) do
        engine.subjectsById[subject.id] = subject
    end

    function engine:getQuestionType(id)
        return self.questions.get(id)
    end

    function engine:getSubject(subjectId)
        return self.subjectsById[subjectId]
    end

    function engine:getQuestionTypes()
        return self.questions.list()
    end

    function engine:getQuestionTypesForSubject(subjectId)
        local subject = self.subjectsById[subjectId]
        if not subject then
            return self:getQuestionTypes()
        end

        local out = {}
        for _, questionId in ipairs(collectAnswerQuestionIds(subject)) do
            local q = self.questions.get(questionId)
            if q then
                out[#out + 1] = q
            end
        end

        if #out == 0 then
            return self:getQuestionTypes()
        end

        return out
    end

    function engine:getFocusTokens(subjectId, questionTypeId)
        local tokens = {}
        local subject = self.subjectsById[subjectId]
        local question = self.questions.get(questionTypeId)

        for _, tag in ipairs(subject and subject.tags or {}) do
            tokens[#tokens + 1] = tag
        end
        for _, tag in ipairs(question and question.tags or {}) do
            tokens[#tokens + 1] = tag
        end

        return uniqueSortedTags(tokens)
    end

    function engine:getActorMotifs(actor)
        if not actor then
            return {}
        end

        local motifs
        if actor.getMotifs then
            motifs = cloneArray(actor:getMotifs() or {})
        else
            motifs = cloneArray(actor.motifs or {})
        end

        local seen = {}
        for _, motif in ipairs(motifs) do
            seen[normalizeText(motif)] = true
        end
        for _, motif in ipairs(collectHunterMotifs(actor)) do
            local key = normalizeText(motif)
            if key ~= "" and not seen[key] then
                seen[key] = true
                motifs[#motifs + 1] = motif
            end
        end

        return motifs
    end

    function engine:extractMotifTags(motif)
        local motifKey = normalizeText(motif)
        if motifKey == "" then
            return {}
        end

        local tags = {}

        local exact = self.motifTagMap.EXACT and self.motifTagMap.EXACT[motifKey]
        if exact then
            for _, tag in ipairs(exact) do
                tags[#tags + 1] = tag
            end
        end

        for token in motifKey:gmatch("%a+") do
            local tokenTags = self.motifTagMap.KEYWORDS and self.motifTagMap.KEYWORDS[token]
            if tokenTags then
                for _, tag in ipairs(tokenTags) do
                    tags[#tags + 1] = tag
                end
            end
        end

        return uniqueSortedTags(tags)
    end

    function engine:getMotifScoreForSubject(motif, subject, question)
        local motifTags = self:extractMotifTags(motif)
        local subjectTags = subject and subject.tags or {}
        local questionTags = question and question.tags or {}
        local overlapSubject = overlapCount(motifTags, subjectTags)
        local overlapQuestion = overlapCount(motifTags, questionTags)
        local contextBonus = 0

        if subject and subject.kind == "monster" and
           hasAny(motifTags, { "monster_lore", "combat", "tactics", "hunting", "beast_lore" }) then
            contextBonus = contextBonus + 1
        end
        if subject and subject.kind == "hazard" and
           hasAny(motifTags, { "hazard", "survival", "scouting", "security", "traps" }) then
            contextBonus = contextBonus + 1
        end
        if subject and subject.kind == "location" and
           hasAny(motifTags, { "history", "scholarly", "classification", "occult" }) then
            contextBonus = contextBonus + 1
        end

        return overlapSubject + overlapQuestion + contextBonus
    end

    function engine:actorHasAppropriateMotif(actor, subject, question)
        for _, motif in ipairs(self:getActorMotifs(actor)) do
            if self:getMotifScoreForSubject(motif, subject, question) >= 2 then
                return true, motif
            end
        end
        return false, nil
    end

    function engine:canApplyUncannyKnowledge(request, subject, question)
        local actor = request and (request.actor or request.entity)
        if not entityHasUsableTalent(actor, "uncanny_knowledge") then
            return false, "requires_uncanny_knowledge"
        end

        local party = collectActors(request and (request.party or request.guild or request.tableActors or request.actors))
        if #party == 0 and actor then
            party = { actor }
        end

        for _, candidate in ipairs(party) do
            local hasAppropriate = self:actorHasAppropriateMotif(candidate, subject, question)
            if hasAppropriate then
                return false, "appropriate_motif_exists"
            end
        end

        return true, nil
    end

    function engine:getAvailableSubjects(context)
        context = context or {}

        local challengeController = context.challengeController
        local roomId = context.roomId or (challengeController and challengeController.roomId)

        local enemyBlueprints = {}
        for _, npc in ipairs(challengeController and challengeController.npcs or {}) do
            if not (npc.conditions and npc.conditions.dead) then
                local id = npc.blueprintId
                if id then
                    enemyBlueprints[id] = true
                end
            end
        end

        local matched = {}
        for _, subject in ipairs(self.subjects) do
            local include = false

            if subject.alwaysAvailable then
                include = true
            end

            if roomId and listContains(subject.roomIds, roomId) then
                include = true
            end

            if subject.enemyBlueprintIds then
                for _, blueprintId in ipairs(subject.enemyBlueprintIds) do
                    if enemyBlueprints[blueprintId] then
                        include = true
                        break
                    end
                end
            end

            if include then
                matched[#matched + 1] = subject
            end
        end

        if #matched == 0 then
            matched = self.subjects
        end

        local out = {}
        for _, subject in ipairs(matched) do
            out[#out + 1] = {
                id = subject.id,
                name = subject.name,
                kind = subject.kind,
                tags = cloneArray(subject.tags or {}),
                enemyBlueprintIds = cloneArray(subject.enemyBlueprintIds or {}),
                shortDescription = subject.shortDescription,
                questionTypeIds = collectAnswerQuestionIds(subject),
            }
        end

        table.sort(out, function(a, b)
            return tostring(a.name) < tostring(b.name)
        end)

        return out
    end

    local function buildResult(verdict, reason, payload)
        payload = payload or {}
        payload.verdict = verdict
        payload.reason = reason
        payload.loreSpend = verdict == ACCEPT
        return payload
    end

    function engine:adjudicate(request)
        request = request or {}

        local subject = self.subjectsById[request.subjectId]
        if not subject then
            return buildResult(REJECT_SUBJECT, "That subject is not currently available.", {
                suggestedQuestionTypes = {},
                scoreBreakdown = {},
            })
        end

        local question = self.questions.get(request.questionType)
        if not question then
            local supportedIds = collectAnswerQuestionIds(subject)
            return buildResult(REPHRASE, "Choose a discrete question type for this subject.", {
                suggestedQuestionTypes = shortQuestionList(supportedIds),
                scoreBreakdown = {},
            })
        end

        local motif = request.motif
        local motifTags = self:extractMotifTags(motif)
        if normalizeText(motif) == "" or #motifTags == 0 then
            local uncannyOk = self:canApplyUncannyKnowledge(request, subject, question)
            if uncannyOk then
                motifTags = { "uncanny_knowledge" }
            else
                return buildResult(REJECT_MOTIF, "Selected motif does not map to usable lore tags.", {
                    suggestedQuestionTypes = shortQuestionList(collectAnswerQuestionIds(subject)),
                    scoreBreakdown = {
                        motifTags = motifTags,
                        subjectTags = cloneArray(subject.tags or {}),
                        questionTags = cloneArray(question.tags or {}),
                        overlapSubject = 0,
                        overlapQuestion = 0,
                        contextBonus = 0,
                        total = 0,
                    },
                })
            end
        end

        local answer = subject.answers and subject.answers[question.id] or nil
        if not answer then
            local supportedIds = collectAnswerQuestionIds(subject)
            return buildResult(REPHRASE, "That question type has no authored answer for this subject yet.", {
                suggestedQuestionTypes = shortQuestionList(supportedIds),
                scoreBreakdown = {
                    motifTags = motifTags,
                    subjectTags = cloneArray(subject.tags or {}),
                    questionTags = cloneArray(question.tags or {}),
                    overlapSubject = overlapCount(motifTags, subject.tags or {}),
                    overlapQuestion = overlapCount(motifTags, question.tags or {}),
                    contextBonus = 0,
                    total = overlapCount(motifTags, subject.tags or {}) + overlapCount(motifTags, question.tags or {}),
                },
            })
        end

        local subjectTags = subject.tags or {}
        local questionTags = question.tags or {}
        local overlapSubject = overlapCount(motifTags, subjectTags)
        local overlapQuestion = overlapCount(motifTags, questionTags)

        local contextBonus = 0
        if subject.kind == "monster" and hasAny(motifTags, { "monster_lore", "combat", "tactics", "hunting", "beast_lore" }) then
            contextBonus = contextBonus + 1
        end
        if subject.kind == "hazard" and hasAny(motifTags, { "hazard", "survival", "scouting", "security", "traps" }) then
            contextBonus = contextBonus + 1
        end
        if subject.kind == "location" and hasAny(motifTags, { "history", "scholarly", "classification", "occult" }) then
            contextBonus = contextBonus + 1
        end

        local focus = normalizeText(request.focus)
        if focus ~= "" then
            if listContains(subjectTags, focus) or listContains(questionTags, focus) then
                contextBonus = contextBonus + 1
            end
        end

        local score = overlapSubject + overlapQuestion + contextBonus
        local scoreBreakdown = {
            motifTags = motifTags,
            subjectTags = cloneArray(subjectTags),
            questionTags = cloneArray(questionTags),
            overlapSubject = overlapSubject,
            overlapQuestion = overlapQuestion,
            contextBonus = contextBonus,
            total = score,
        }

        local uncannyOk = false
        if score < 2 then
            uncannyOk = self:canApplyUncannyKnowledge(request, subject, question)
        end
        if uncannyOk then
            scoreBreakdown.uncannyKnowledge = true
            scoreBreakdown.uncannyKnowledgeReason = "no_party_motif"
            local details = cloneArray(answer.details or {})
            return buildResult(ACCEPT, "Uncanny Knowledge supplies a lore angle nobody else has.", {
                response = {
                    summary = answer.summary or "",
                    details = details,
                    implication = answer.implication or "",
                    sourceRefs = cloneArray(answer.sourceRefs or {}),
                },
                scoreBreakdown = scoreBreakdown,
                suggestedQuestionTypes = {},
                uncannyKnowledge = true,
            })
        end

        if score >= 2 then
            local details = cloneArray(answer.details or {})
            return buildResult(ACCEPT, "Motif alignment is strong enough for a reliable answer.", {
                response = {
                    summary = answer.summary or "",
                    details = details,
                    implication = answer.implication or "",
                    sourceRefs = cloneArray(answer.sourceRefs or {}),
                },
                scoreBreakdown = scoreBreakdown,
                suggestedQuestionTypes = {},
            })
        end

        if score == 1 then
            return buildResult(REPHRASE, "Close call: narrow the question or pick a more pertinent motif.", {
                suggestedQuestionTypes = shortQuestionList(collectAnswerQuestionIds(subject)),
                scoreBreakdown = scoreBreakdown,
            })
        end

        return buildResult(REJECT_MOTIF, "Motif and subject do not overlap enough to justify an answer.", {
            suggestedQuestionTypes = shortQuestionList(collectAnswerQuestionIds(subject)),
            scoreBreakdown = scoreBreakdown,
        })
    end

    return engine
end

return M
