-- action_resolver.lua
-- Challenge Action Resolution for Majesty
-- Ticket S4.4: Maps suits to mechanical effects
--
-- Suits and their actions:
-- - SWORDS: Melee (requires engagement), Missile (bypasses engagement)
-- - PENTACLES: Roughhouse (Trip, Disarm, Displace)
-- - CUPS: Support, healing, social
-- - WANDS: Banter (attacks Morale), magic
--
-- Great Success (face cards on matching suit) triggers weapon bonuses

local events = require('logic.events')
local disposition_module = require('logic.disposition')
local constants = require('constants')
local action_registry = require('data.action_registry')
local spell_registry = require('data.spell_registry')
local maleficence_tables = require('data.maleficence_tables')
local entity_factory = require('entities.factory')
local fate_resolver = require('logic.resolver')
local inventory = require('logic.inventory')
local item_templates = require('data.item_templates')
local camp_actions = require('logic.camp_actions')
local city_events = require('data.city_events')

local M = {}

--------------------------------------------------------------------------------
-- ACTION TYPES
--------------------------------------------------------------------------------
M.ACTION_TYPES = {
    -- Swords
    MELEE      = "melee",       -- Requires engagement
    MISSILE    = "missile",     -- Bypasses engagement, ammo cost

    -- Pentacles
    ROUGHHOUSE = "roughhouse",  -- Choose Disarm, Displace, Root, or Trip
    TRIP       = "trip",        -- Knock prone
    DISARM     = "disarm",      -- Remove weapon
    DISPLACE   = "displace",    -- Push to different zone
    GRAPPLE    = "grapple",     -- Establish grapple

    -- Cups
    COMMAND    = "command",     -- Command companion actions
    HEAL       = "heal",        -- Healing action
    PARLEY     = "parley",      -- Social extension
    RALLY      = "rally",       -- Social extension
    SHIELD     = "shield",      -- Protect another
    AID        = "aid",         -- S7.1: Aid Another (bank bonus for ally)

    -- Wands
    BANTER     = "banter",      -- Attack morale
    SPEAK_INCANTATION = "speak_incantation", -- Rulebook spellcasting action
    CAST       = "cast",        -- Legacy alias for Speak Incantation
    COUNTER_SPELL = "counter_spell", -- Talent interrupt/negation for sorcery
    DWIMMERCRAFT = "dwimmercraft", -- Talent: minor magic/second sight
    RECOVER    = "recover",     -- S7.4: Clear negative status effects

    -- Special
    FLEE       = "flee",        -- Attempt to escape
    MOVE       = "move",        -- Change zone
    USE_ITEM   = "use_item",    -- Use an item
    PULL_ITEM  = "pull_item",   -- Pull item from pack
    PULL_ITEM_BELT = "pull_item_belt", -- Pull item from belt
    INTERACT   = "interact",    -- Environment interaction
    BID_LORE   = "bid_lore",    -- Misc rules lookup action
    GUARD      = "guard",       -- Replace initiative if shielded
    HEAVY_METAL_MACHINE = "heavy_metal_machine", -- Talent interrupt: add Swords to Initiative once
    TEST_FATE  = "test_fate",   -- Mid-challenge test of fate trigger
    TRIVIAL_ACTION = "trivial_action", -- Simple uncontested action
    VIGILANCE  = "vigilance",   -- Prepared triggered response
    SNEAK      = "sneak",       -- Talent procedure: off-stage sneaking and dramatic arrival
    CREATURE_GAZE = "creature_gaze", -- Cardless creature gaze/effect procedure
    COCKATRICE_GAZE = "cockatrice_gaze", -- Automatic Cockatrice gaze
    GRIFFIN_DROP = "griffin_drop", -- Cardless Griffin free-action drop
    HARPY_SHRIEK = "harpy_shriek", -- Greater-doom Harpy area stun
    LION_CAUTIOUS_RETREAT = "lion_cautious_retreat", -- Greater-doom Lion disengage
    MIMIC_HARDEN = "mimic_harden", -- Greater-doom Mimic weapon immunity

    -- Defensive Actions (S4.9)
    DODGE      = "dodge",       -- Adds card value to defense difficulty
    RIPOSTE    = "riposte",     -- Counter-attack when attacked

    -- Interrupt Actions (S4.9)
    FOOL_INTERRUPT = "fool_interrupt",  -- The Fool: take immediate action out of turn

    -- Engagement Actions (S6.3)
    AVOID      = "avoid",       -- Escape engagement without parting blows
    DASH       = "dash",        -- Quick move (subject to parting blows)

    -- S7.8: Ammunition
    RELOAD     = "reload",      -- Reload a crossbow
}

M.ACTION_ALIASES = {
    cast = M.ACTION_TYPES.SPEAK_INCANTATION,
    counterspell = M.ACTION_TYPES.COUNTER_SPELL,
    root = M.ACTION_TYPES.ROUGHHOUSE,
    go_sneaking = M.ACTION_TYPES.SNEAK,
    sneak_arrival = M.ACTION_TYPES.SNEAK,
    arrive_from_sneak = M.ACTION_TYPES.SNEAK,
}

--------------------------------------------------------------------------------
-- S7.6: WEAPON TYPES (for specialization logic)
--------------------------------------------------------------------------------
M.WEAPON_TYPES = {
    -- Blades: Riposte deals 2 damage
    BLADE   = { "sword", "dagger", "axe" },
    -- Hammers: Double damage threshold
    HAMMER  = { "mace", "hammer", "staff" },
    -- Daggers: Piercing vs vulnerable targets
    DAGGER  = { "dagger" },
    -- Flails: Ties count as success
    FLAIL   = { "flail" },
    -- Axes: Cleave on defeat
    AXE     = { "axe" },
    -- Ranged
    BOW     = { "bow" },
    CROSSBOW = { "crossbow" },
}

--------------------------------------------------------------------------------
-- WEAPON TYPES & GREAT SUCCESS BONUSES
--------------------------------------------------------------------------------
M.WEAPON_BONUSES = {
    -- Blade weapons: +1 wound on Great Success
    sword       = { great_bonus = "extra_wound", wound_bonus = 1 },
    dagger      = { great_bonus = "extra_wound", wound_bonus = 1 },
    axe         = { great_bonus = "extra_wound", wound_bonus = 1 },

    -- Blunt weapons: Stagger on Great Success
    mace        = { great_bonus = "stagger" },
    hammer      = { great_bonus = "stagger" },
    staff       = { great_bonus = "stagger" },

    -- Piercing weapons: Ignore armor on Great Success
    spear       = { great_bonus = "pierce_armor" },
    pike        = { great_bonus = "pierce_armor" },

    -- Ranged weapons
    bow         = { great_bonus = "extra_wound", wound_bonus = 1, uses_ammo = true },
    crossbow    = { great_bonus = "pierce_armor", uses_ammo = true },
    thrown      = { great_bonus = "extra_wound", wound_bonus = 1, uses_ammo = true },
}

--------------------------------------------------------------------------------
-- THE FOOL HELPER (S4.9)
--------------------------------------------------------------------------------

--- Check if a card is The Fool
-- @param card table: Card to check
-- @return boolean: true if card is The Fool
function M.isFool(card)
    if not card then return false end
    return card.name == "The Fool" or (card.is_major and card.value == 0)
end

local function normalizeSocialTag(value)
    if type(value) ~= "string" then
        return nil
    end

    local normalized = value:lower()
    normalized = normalized:gsub("^%s+", ""):gsub("%s+$", "")
    normalized = normalized:gsub("[%s%-]+", "_")
    return normalized
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

local function normalizedTableContains(value, wanted)
    wanted = normalizeTalentKey(wanted)
    if type(value) ~= "table" then
        return false
    end

    for key, item in pairs(value) do
        if normalizeTalentKey(key) == wanted and item ~= false then
            return true
        end
        if type(item) == "string" and normalizeTalentKey(item) == wanted then
            return true
        end
        if type(item) == "table" and normalizeTalentKey(item.id or item.name or item.tag) == wanted then
            return true
        end
    end

    return false
end

local function entityHasNormalizedTag(entity, tag)
    if not entity then
        return false
    end
    return normalizedTableContains(entity.tags, tag) or
        normalizedTableContains(entity.aiTags, tag) or
        normalizedTableContains(entity.traits, tag)
end

local function normalizedEntitySize(entity)
    if not entity then
        return nil
    end
    return normalizeTalentKey(entity.size or entity.sizeCategory or entity.scale or entity.category)
end

local function isGiantSizedEntity(entity)
    if not entity then
        return false
    end
    if entity.giantSized or entity.giantSize or entity.huge or entity.massive or entity.giant then
        return true
    end
    local size = normalizedEntitySize(entity)
    return size == "huge" or size == "giant" or size == "massive" or
        size == "gargantuan" or size == "colossal" or size == "titanic"
end

local function targetRequiresGiantSizeToRoughhouse(target)
    if not target then
        return false
    end
    if target.roughhouseImmuneUnlessGiantSized or target.roughhouseRequiresGiantSize then
        return true
    end
    local dragonHuge = target.dragon and target.dragon.huge
    return dragonHuge and dragonHuge.immuneToRoughhouseUnlessGiantSized
end

local function actionCanAffectGiantSizedTarget(action)
    if not action then
        return false
    end
    if action.canAffectGiantSize or action.affectsGiantSize or action.giantSizedRoughhouse or
       action.canRoughhouseHuge then
        return true
    end
    return isGiantSizedEntity(action.actor)
end

local UP_MY_SLEEVE_TEMPLATE_ALIASES = {
    empty_vial = "hermetic_bottle",
    vial = "hermetic_bottle",
    bottle = "hermetic_bottle",
    lockpick = "lockpicks",
    lock_picks = "lockpicks",
    rope_50ft = "rope",
    rope_50_ft = "rope",
}

local UP_MY_SLEEVE_COMMON_TEMPLATES = {
    candles = true,
    chalk = true,
    dagger = true,
    grappling_hook = true,
    hermetic_bottle = true,
    lard = true,
    lockpicks = true,
    ration = true,
    rope = true,
    torch = true,
}

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

local function appendNormalizedKey(out, value)
    local normalized = normalizeTalentKey(value)
    if normalized ~= "" then
        out[#out + 1] = normalized
    end
end

local function appendNormalizedKeys(out, value)
    if type(value) == "string" or type(value) == "number" then
        appendNormalizedKey(out, value)
        return
    end

    if type(value) ~= "table" then
        return
    end

    for key, item in pairs(value) do
        if type(item) == "string" or type(item) == "number" then
            appendNormalizedKey(out, item)
        elseif type(item) == "table" then
            appendNormalizedKey(out, item.id or item.name or item.tag or item.type)
        elseif item == true then
            appendNormalizedKey(out, key)
        end
    end
end

local function normalizedKeyVariants(value)
    local normalized = normalizeTalentKey(value)
    local variants = {}
    if normalized == "" then
        return variants
    end

    variants[normalized] = true
    if #normalized > 3 and normalized:sub(-1) == "s" then
        variants[normalized:sub(1, -2)] = true
    end
    variants[normalized:gsub("_", "")] = true
    return variants
end

local function normalizedKeysMatch(a, b)
    local aVariants = normalizedKeyVariants(a)
    local bVariants = normalizedKeyVariants(b)
    for variant in pairs(aVariants) do
        if bVariants[variant] then
            return true
        end
    end
    return false
end

local function getHunterFoeLabel(talentId, entry)
    if type(entry) == "table" then
        local value = entry.foe or entry.hatedFoe or entry.hunterFoe or entry.category or
            entry.enemyCategory or entry.specializationCategory
        if value then
            return tostring(value)
        end
    end

    return HUNTER_DEFAULT_FOES[normalizeTalentKey(talentId)]
end

local function getHunterSpecializationTags(talentId, entry)
    local tags = {}
    if type(entry) == "string" or type(entry) == "number" then
        appendNormalizedKey(tags, entry)
    elseif type(entry) == "table" then
        appendNormalizedKeys(tags, entry.specializationTags or entry.specialization_tags)
        appendNormalizedKeys(tags, entry.targetTags or entry.target_tags)
        appendNormalizedKeys(tags, entry.tags)
        appendNormalizedKey(tags, entry.specialization or entry.speciality or entry.specialty)
        appendNormalizedKey(tags, entry.species or entry.enemyType or entry.prey or entry.quarry)
    end

    local unique = {}
    local out = {}
    for _, tag in ipairs(tags) do
        if tag ~= "" and not unique[tag] then
            unique[tag] = true
            out[#out + 1] = tag
        end
    end
    return out
end

local function collectHunterTalents(actor)
    local hunters = {}
    for _, talentId in ipairs(HUNTER_TALENT_IDS) do
        local entry = getUsableTalentEntry(actor, talentId)
        if entry then
            hunters[#hunters + 1] = {
                talentId = talentId,
                entry = entry,
                foe = getHunterFoeLabel(talentId, entry),
                specializationTags = getHunterSpecializationTags(talentId, entry),
            }
        end
    end
    return hunters
end

local function collectTargetHunterTags(target)
    local tags = {}
    local function add(value)
        for variant in pairs(normalizedKeyVariants(value)) do
            tags[variant] = true
        end
    end
    local function addCollection(value)
        if type(value) == "string" or type(value) == "number" then
            add(value)
            return
        end
        if type(value) ~= "table" then
            return
        end
        for key, item in pairs(value) do
            if type(item) == "string" or type(item) == "number" then
                add(item)
            elseif type(item) == "table" then
                add(item.id or item.name or item.tag or item.type)
            elseif item == true then
                add(key)
            end
        end
    end

    if not target then
        return tags
    end

    addCollection(target.tags)
    addCollection(target.aiTags)
    addCollection(target.traits)
    add(target.id)
    add(target.name)
    add(target.blueprintId)
    add(target.templateId)
    add(target.enemyType)
    add(target.kind)
    add(target.type)
    add(target.category)
    add(target.kin)
    add(target.kith)
    add(target.species)
    add(target.race)
    add(target.ancestry)

    if target.undead then add("undead") end
    if target.spirit then add("spirit") end
    if target.beast or target.animal then add("beast") end
    if target.kith or target.kin or target.isPC then add("kith") end
    if target.construct or target.automaton then add("construct") end

    return tags
end

local function getActionTargetKin(action, target)
    local function normalizePresent(value)
        local normalized = normalizeTalentKey(value)
        if normalized ~= "" then
            return normalized
        end
        return nil
    end

    return normalizePresent(action and (action.targetKin or action.targetKith or action.opponentKin)) or
        normalizePresent(target and target.kin) or
        normalizePresent(target and target.kith) or
        normalizePresent(target and target.species) or
        normalizePresent(target and target.race) or
        normalizePresent(target and target.ancestry)
end

local function entityIsTrollKin(action, entity)
    local kin = getActionTargetKin(action, entity)
    if kin == "troll" or kin == "trolls" then
        return true
    end
    if entityHasNormalizedTag(entity, "troll") then
        return true
    end
    return getEntityTalentEntry(entity, "giants_strength") ~= nil or getEntityTalentEntry(entity, "colossal") ~= nil
end

local function entityIsNonTrollKin(action, entity)
    if not entity or entityIsTrollKin(action, entity) then
        return false
    end

    local kin = getActionTargetKin(action, entity)
    if kin then
        return true
    end

    return entity.isPC == true or entity.isUnderfolk == true or entity.underfolk == true or
        entityHasNormalizedTag(entity, "underfolk") or entityHasNormalizedTag(entity, "dwarf") or
        entityHasNormalizedTag(entity, "halfling")
end

local function actionHasRawStrengthContext(action)
    if not action then
        return false
    end
    if action.rawStrengthContest == false or action.giantsStrengthContest == false then
        return false
    end
    if action.rawStrengthContest == true or action.giantsStrengthContest == true or
       action.strengthContest == true then
        return true
    end

    local parts = {}
    local function addPart(value)
        if value ~= nil then
            parts[#parts + 1] = normalizeTalentKey(value)
        end
    end

    addPart(action.contestContext)
    addPart(action.strengthContext)
    addPart(action.testContext)
    addPart(action.context)
    addPart(action.intent)
    addPart(action.relatedTo)
    addPart(action.feat)
    addPart(action.description)

    for key, value in pairs(action.tags or {}) do
        parts[#parts + 1] = normalizeTalentKey(key)
        parts[#parts + 1] = normalizeTalentKey(value)
    end

    local context = table.concat(parts, " ")
    for _, tag in ipairs({
        "raw_strength",
        "arm_wrestling",
        "armwrestling",
        "lifting",
        "lift",
        "pulling",
        "pull",
        "pushing",
        "push",
        "shoving",
        "shove",
        "wrestling",
        "wrestle",
        "force_open",
        "raw_power",
        "strength_contest",
    }) do
        if context:find(tag, 1, true) then
            return true
        end
    end

    return false
end

local function getResolveAmount(actor)
    if not actor then
        return 0
    end
    if type(actor.resolve) == "table" then
        return actor.resolve.current or 0
    end
    if type(actor.resolve) == "number" then
        return actor.resolve
    end
    return 0
end

local function loreResolveFailureText(reason)
    if reason == "requires_loremaster" then
        return "Requires Loremaster to spend Resolve for lore"
    elseif reason == "not_enough_resolve" then
        return "No Resolve remaining for Loremaster lore"
    end
    return "Cannot spend Resolve for lore"
end

local function loreFollowUpFailureText(reason)
    if reason == "requires_weird_wise_ancient" then
        return "Requires Weird, Wise, Ancient to ask a free lore follow-up"
    elseif reason == "requires_accepted_lore" then
        return "Free lore follow-up requires a previous accepted lore answer"
    end
    return "Cannot ask a free lore follow-up"
end

local function normalizeForetellPrediction(value)
    if type(value) == "boolean" then
        return value
    end
    if type(value) == "string" then
        local normalized = value:lower():gsub("^%s+", ""):gsub("%s+$", "")
        if normalized == "yes" or normalized == "true" or normalized == "will" or normalized == "happens" then
            return true
        elseif normalized == "no" or normalized == "false" or normalized == "wont" or
               normalized == "won't" or normalized == "will not" or
               normalized == "won_t" or normalized == "will_not" then
            return false
        end
    end
    return nil
end

local function firstNonNil(...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if value ~= nil then
            return value
        end
    end
    return nil
end

local function normalizeTrivialIntent(action)
    local intent = action and (action.trivialAction or action.trivialIntent or action.intent or
        action.interaction or action.procedure)
    if type(intent) == "table" then
        intent = intent.id or intent.action or intent.type
    end
    if type(intent) ~= "string" then
        return nil
    end
    return intent:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("[%s%-]+", "_")
end

local function collectSocialTags(value, out)
    out = out or {}
    if type(value) == "string" then
        local tag = normalizeSocialTag(value)
        if tag and tag ~= "" then
            out[#out + 1] = tag
        end
    elseif type(value) == "table" then
        for _, item in ipairs(value) do
            collectSocialTags(item, out)
        end
    end
    return out
end

local function hasSocialTag(sourceTags, actionTags)
    local sourceSet = {}
    for _, tag in ipairs(collectSocialTags(sourceTags)) do
        sourceSet[tag] = true
    end

    for _, tag in ipairs(actionTags or {}) do
        if sourceSet[tag] then
            return true, tag
        end
    end

    return false, nil
end

local function entityHasMaledictionFlag(entity, flag)
    if not entity or not flag then
        return false
    end
    if entity[flag] == true then
        return true
    end

    local malediction = entity.malediction
    local curse = malediction and malediction.curse
    local flags = curse and curse.flags
    return malediction and malediction.active ~= false and flags and flags[flag] == true
end

local function entityMaledictionFlagValue(entity, flag)
    if not entity or not flag then
        return nil
    end
    if entity[flag] ~= nil then
        return entity[flag]
    end

    local malediction = entity.malediction
    local curse = malediction and malediction.curse
    local flags = curse and curse.flags
    if malediction and malediction.active ~= false and flags then
        return flags[flag]
    end
    return nil
end

local function socialTargetIsUndead(target)
    if not target then
        return false
    end
    if target.undead or target.isUndead then
        return true
    end
    for _, tag in ipairs(target.tags or {}) do
        if tostring(tag):lower() == "undead" then
            return true
        end
    end
    return false
end

local function getMaledictionSocialModifier(actor, target)
    if not actor or not target or socialTargetIsUndead(target) then
        return 0, nil
    end
    if entityHasMaledictionFlag(actor, "gmCharactersUsuallyHostile") or
       entityHasMaledictionFlag(actor, "appearsAsDesiccatedCorpse") then
        return -3, "desiccated_corpse_hostility"
    end
    return 0, nil
end

local function applyMaledictionSocialModifier(action, result, target)
    local modifier, effect = getMaledictionSocialModifier(action and action.actor, target)
    if modifier == 0 then
        return 0
    end

    result.effects = result.effects or {}
    result.effects[#result.effects + 1] = "malediction_social_disfavor"
    if effect then
        result.effects[#result.effects + 1] = effect
    end
    result.testValue = (result.testValue or 0) + modifier
    result.socialModifier = (result.socialModifier or 0) + modifier
    result.maledictionSocialModifier = modifier
    return modifier
end

local function getPactSocialModifier(actor)
    if camp_actions.findUnbrokenActivePact(actor, "hide_face") then
        return -3, "hide_face_social_disfavor"
    end
    return 0, nil
end

local function applyPactSocialModifier(action, result)
    local modifier, effect = getPactSocialModifier(action and action.actor)
    if modifier == 0 then
        return 0
    end

    result.effects = result.effects or {}
    result.effects[#result.effects + 1] = "pact_social_disfavor"
    if effect then
        result.effects[#result.effects + 1] = effect
    end
    result.testValue = (result.testValue or 0) + modifier
    result.socialModifier = (result.socialModifier or 0) + modifier
    result.pactSocialModifier = (result.pactSocialModifier or 0) + modifier
    return modifier
end

local function normalizeSpeechVolume(value)
    if type(value) ~= "string" then
        return nil
    end
    return value:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("[%s%-]+", "_")
end

local function actionUsesLoudSpeech(action)
    if not action then
        return false
    end
    local volume = normalizeSpeechVolume(action.speechVolume or action.voiceVolume or action.volume)
    return action.loudSpeech == true or action.shouts == true or action.shout == true or
        action.yells == true or action.yell == true or volume == "loud" or volume == "shout" or
        volume == "shouting" or volume == "yell" or volume == "yelling"
end

local function actionTellsKnowingLie(action)
    if not action then
        return false
    end
    return action.knowinglyLies == true or action.knownLie == true or action.lie == true or
        action.lies == true or action.deception == true or action.falsehood == true
end

local function breakSocialPact(resolver, action, result, pactId, reason)
    local actor = action and action.actor
    local pact = camp_actions.findUnbrokenActivePact(actor, pactId)
    if not pact then
        return nil
    end

    local ok, breakResult, detail = camp_actions.breakPact(actor, pact, {
        eventBus = resolver and resolver.eventBus,
        actionResolver = resolver,
        reason = reason,
    })
    result.pactBreaks = result.pactBreaks or {}
    result.pactBreaks[#result.pactBreaks + 1] = {
        ok = ok,
        result = breakResult,
        detail = detail,
        pact = pact,
        pactId = pactId,
        reason = reason,
    }
    result.effects = result.effects or {}
    result.effects[#result.effects + 1] = "pact_broken_" .. pactId
    return detail
end

local function applySocialPactBreaks(resolver, action, result)
    if actionUsesLoudSpeech(action) then
        breakSocialPact(resolver, action, result, "silence", "silence_loud_speech")
    end
    if actionTellsKnowingLie(action) then
        breakSocialPact(resolver, action, result, "verity", "verity_knowing_lie")
    end
    return result.pactBreaks
end

local function normalizeLanguage(value)
    if type(value) ~= "string" then
        return nil
    end
    local normalized = value:lower()
    normalized = normalized:gsub("^%s+", ""):gsub("%s+$", "")
    normalized = normalized:gsub("[%s%-]+", "_")
    return normalized
end

local function languageListHas(source, language)
    language = normalizeLanguage(language)
    if not language then
        return false
    end
    if type(source) == "string" then
        return normalizeLanguage(source) == language
    end
    if type(source) == "table" then
        if source[language] == true then
            return true
        end
        for _, item in ipairs(source) do
            if normalizeLanguage(item) == language then
                return true
            end
        end
    end
    return false
end

local function getLockedSpeechLanguage(actor)
    local language = (actor and actor.languageLocked) or entityMaledictionFlagValue(actor, "languageLocked")
    if language == true then
        return "tylwyth"
    end
    if language then
        return normalizeLanguage(language)
    end
    if entityHasMaledictionFlag(actor, "speaksGibberishToNonTylwyth") then
        return "tylwyth"
    end
    return nil
end

local function targetUnderstandsLanguage(target, language, action)
    language = normalizeLanguage(language)
    if not target or not language then
        return false
    end
    action = action or {}
    if action.sharedLanguage == true or action.targetUnderstandsLanguage == true or
       action.targetUnderstandsLockedLanguage == true then
        return true
    end
    if language == "tylwyth" and (action.targetUnderstandsTylwyth == true or target.understandsTylwyth == true or
       target.tylwyth == true) then
        return true
    end
    if target.understandsAllLanguages or target.universalSpeech or target.magicalTranslation then
        return true
    end
    return languageListHas(action.sharedLanguage, language) or
        languageListHas(action.language, language) or
        languageListHas(action.targetLanguage, language) or
        languageListHas(target.languages, language) or
        languageListHas(target.knownLanguages, language) or
        languageListHas(target.understandsLanguages, language) or
        languageListHas(target.speaks, language) or
        languageListHas(target.language, language) or
        languageListHas(target.nativeLanguage, language)
end

local function applyLockedSpeechSocialGate(action, result, target)
    local language = getLockedSpeechLanguage(action and action.actor)
    if not language or targetUnderstandsLanguage(target, language, action) then
        return false
    end

    result.success = false
    result.description = "The target hears only gibberish."
    result.languageLocked = language
    result.effects = result.effects or {}
    result.effects[#result.effects + 1] = "language_locked_gibberish"
    result.effects[#result.effects + 1] = "shared_language_missing"
    if language == "tylwyth" then
        result.effects[#result.effects + 1] = "tylwyth_only"
    end
    return true
end

local function actorMustSpeakInRhymes(actor)
    if not actor then
        return false
    end
    local conditions = actor.conditions or {}
    return actor.mustSpeakInRhymes == true or
        actor.rhymebound == true or
        conditions.rhymebound == true or
        entityHasMaledictionFlag(actor, "mustSpeakInRhymes")
end

local function actionSpeechRhymes(action)
    action = action or {}
    return action.speechRhymes == true or
        action.rhymedSpeech == true or
        action.rhymes == true or
        action.rhymingCouplets == true or
        action.rhymeAccepted == true
end

local function applyRhymedSpeechSocialGate(action, result)
    local actor = action and action.actor
    if not actorMustSpeakInRhymes(actor) or actionSpeechRhymes(action) then
        return false
    end

    result.success = false
    result.description = "The curse binds the words until the speech rhymes."
    result.requiresRhymedSpeech = true
    result.effects = result.effects or {}
    result.effects[#result.effects + 1] = "rhymed_speech_required"
    result.effects[#result.effects + 1] = "rhymebound_speech_blocked"
    if entityHasMaledictionFlag(actor, "mustSpeakInRhymes") or actor.mustSpeakInRhymes == true then
        result.effects[#result.effects + 1] = "speak_in_rhymes"
    end
    if actor.rhymebound == true or (actor.conditions and actor.conditions.rhymebound == true) then
        result.effects[#result.effects + 1] = "rhymebound"
    end
    return true
end

local function collectActionTags(out, source)
    if type(source) == "table" then
        for _, value in ipairs(source) do
            local tag = normalizeSocialTag(value)
            if tag and tag ~= "" then
                out[tag] = true
            end
        end
        for key, value in pairs(source) do
            if type(key) ~= "number" and value then
                local tag = normalizeSocialTag(key)
                if tag and tag ~= "" then
                    out[tag] = true
                end
            end
        end
    else
        local tag = normalizeSocialTag(source)
        if tag and tag ~= "" then
            out[tag] = true
        end
    end
end

local function hasBloodyTears(actor)
    if not actor then
        return false
    end
    local conditions = actor.conditions or {}
    return conditions.bloody_tears == true or actor.bloodyTears == true
end

local function hasAngelicChant(actor)
    if not actor then
        return false
    end
    local conditions = actor.conditions or {}
    return conditions.angelic_chant == true or actor.angelicChant == true
end

local function isVisionBasedAction(action, actionDef)
    action = action or {}
    if action.visionBased == true or action.requiresVision == true or
       action.sightBased == true or action.requiresSight == true then
        return true
    end
    if actionDef and (actionDef.visionBased == true or actionDef.requiresVision == true or
       actionDef.sightBased == true or actionDef.requiresSight == true) then
        return true
    end

    local tags = {}
    collectActionTags(tags, action.context)
    collectActionTags(tags, action.challengeContext)
    collectActionTags(tags, action.testContext)
    collectActionTags(tags, action.intent)
    collectActionTags(tags, action.activity)
    collectActionTags(tags, action.tags)
    collectActionTags(tags, action.actionTags)
    collectActionTags(tags, action.fateTags)

    return tags.vision == true or tags.visual == true or tags.sight == true or
        tags.see == true or tags.seeing == true or tags.look == true or
        tags.observe == true or tags.inspect == true or tags.scrutinize == true or
        tags.search == true or tags.investigate == true or tags.read == true or
        tags.aim == true
end

local METAL_MATERIAL_TAGS = {
    metal = true,
    iron = true,
    steel = true,
    silver = true,
    copper = true,
    bronze = true,
    brass = true,
}

local NON_METAL_MATERIAL_TAGS = {
    wood = true,
    wooden = true,
    archwood = true,
    bone = true,
    leather = true,
    cloth = true,
}

local METAL_WEAPON_TYPES = {
    sword = true,
    dagger = true,
    axe = true,
    mace = true,
    hammer = true,
    flail = true,
    spear = true,
    pike = true,
}

local METAL_TOOL_TYPES = {
    lockpick = true,
    grapple = true,
    chain = true,
    crowbar = true,
    hammer = true,
    hatchet = true,
    spikes = true,
    pick = true,
    shovel = true,
    tinker = true,
}

local WOOD_WEAPON_TYPES = {
    bow = true,
    crossbow = true,
    staff = true,
}

local WOOD_TOOL_TYPES = {
    pole = true,
}

local WOOD_TEMPLATE_IDS = {
    bow = true,
    crossbow = true,
    firewood = true,
    torch = true,
    wand_archwood = true,
}

local function tokenValueMatches(value, token)
    token = normalizeSocialTag(token)
    if not token or token == "" then
        return false
    end

    if type(value) == "string" then
        return normalizeSocialTag(value) == token
    end

    if type(value) == "table" then
        if value[token] == true then
            return true
        end

        for key, entry in pairs(value) do
            if entry == true and normalizeSocialTag(key) == token then
                return true
            end
            if type(entry) == "string" and normalizeSocialTag(entry) == token then
                return true
            end
        end
    end

    return false
end

local function materialValueMatches(value, material)
    local requested = normalizeSocialTag(material)
    if not requested or requested == "" then
        return false
    end

    if type(value) == "string" then
        local actual = normalizeSocialTag(value)
        if actual == requested then
            return true
        end
        if requested == "metal" and METAL_MATERIAL_TAGS[actual] then
            return true
        end
        if requested == "wood" and actual == "wooden" then
            return true
        end
        return false
    end

    if type(value) == "table" then
        if value[requested] == true then
            return true
        end

        for key, entry in pairs(value) do
            if entry == true and materialValueMatches(key, requested) then
                return true
            end
            if materialValueMatches(entry, requested) then
                return true
            end
        end
    end

    return false
end

local function itemHasMarker(item, marker)
    if not item then
        return false
    end

    local normalized = normalizeSocialTag(marker)
    if not normalized or normalized == "" then
        return false
    end

    local props = item.properties or {}
    if item[normalized] == true or props[normalized] == true then
        return true
    end

    return tokenValueMatches(item.tags, normalized) or tokenValueMatches(props.tags, normalized)
end

local function itemHasAnyMarker(item, markers)
    for marker in pairs(markers or {}) do
        if itemHasMarker(item, marker) then
            return true
        end
    end
    return false
end

local function itemMatchesMaterial(item, material)
    if not material then
        return true
    end
    if not item then
        return false
    end

    local requested = normalizeSocialTag(material)
    local props = item.properties or {}

    if materialValueMatches(item.material, requested) or
       materialValueMatches(props.material, requested) or
       materialValueMatches(props.materials, requested) then
        return true
    end

    if requested == "metal" then
        if itemHasAnyMarker(item, METAL_MATERIAL_TAGS) then
            return true
        end
        if itemHasAnyMarker(item, NON_METAL_MATERIAL_TAGS) or
           materialValueMatches(item.material, "wood") or
           materialValueMatches(props.material, "wood") then
            return false
        end

        local weaponType = normalizeSocialTag(item.weaponType or props.weaponType)
        if weaponType and METAL_WEAPON_TYPES[weaponType] then
            return true
        end

        local toolType = normalizeSocialTag(item.toolType or props.toolType)
        if toolType and METAL_TOOL_TYPES[toolType] then
            return true
        end

        local armorType = normalizeSocialTag(item.armorType or props.armorType)
        if item.isArmor or props.armor then
            return armorType == "iron" or armorType == "steel" or armorType == "helm"
        end
    elseif requested == "wood" or requested == "wooden" then
        if itemHasMarker(item, "wood") or itemHasMarker(item, "wooden") or
           itemHasMarker(item, "archwood") or itemHasMarker(item, "firewood") then
            return true
        end

        local weaponType = normalizeSocialTag(item.weaponType or props.weaponType)
        if weaponType and WOOD_WEAPON_TYPES[weaponType] then
            return true
        end

        local toolType = normalizeSocialTag(item.toolType or props.toolType)
        if toolType and WOOD_TOOL_TYPES[toolType] then
            return true
        end

        local templateId = normalizeSocialTag(item.templateId)
        if templateId and WOOD_TEMPLATE_IDS[templateId] then
            return true
        end

        local name = normalizeSocialTag(item.name)
        return name == "torch" or name == "firewood" or name == "wood" or
            name == "wooden_object" or name == "wand_of_archwood"
    end

    return false
end

local function itemIsArchwoodWand(item)
    if not item then
        return false
    end
    local props = item.properties or {}
    if props.wand and props.archwood then
        return true
    end
    local id = normalizeSocialTag(item.templateId or item.id or item.name)
    return id == "wand_archwood" or id == "wand_of_archwood"
end

local function itemIsWeaponForPact(item)
    if not item or itemIsArchwoodWand(item) then
        return false
    end
    local props = item.properties or {}
    return item.isWeapon == true or props.weapon == true or item.weaponType ~= nil or
        props.weaponType ~= nil or item.isMelee == true or item.isRanged == true
end

local function itemIsArmorOrShieldForPact(item)
    if not item then
        return false
    end
    local props = item.properties or {}
    return item.isArmor == true or props.armor == true or item.armorType ~= nil or
        props.armorType ~= nil or itemHasMarker(item, "shield")
end

local function itemIsFelledWoodForPact(item)
    return item ~= nil and not itemIsArchwoodWand(item) and itemMatchesMaterial(item, "wood")
end

local SKIN_MATERIAL_TAGS = {
    skin = true,
    skins = true,
    hide = true,
    hides = true,
    leather = true,
    fur = true,
    furs = true,
    calfskin = true,
}

local function itemIsSkinOrFurForPact(item)
    if not item then
        return false
    end
    local props = item.properties or {}
    for marker in pairs(SKIN_MATERIAL_TAGS) do
        if itemHasMarker(item, marker) or materialValueMatches(item.material, marker) or
           materialValueMatches(props.material, marker) or materialValueMatches(props.materials, marker) then
            return true
        end
    end

    local name = normalizeSocialTag(item.name)
    return name and (name:find("leather", 1, true) ~= nil or
        name:find("fur", 1, true) ~= nil or
        name:find("skin", 1, true) ~= nil or
        name:find("hide", 1, true) ~= nil)
end

local function itemHasMaleficenceTag(item, tag)
    if not tag then
        return true
    end
    if not item then
        return false
    end

    local normalized = normalizeSocialTag(tag)
    local props = item.properties or {}

    if normalized == "potion" and (props.potion or props.alchemicalType == "potion") then
        return true
    end
    if normalized == "ration" and (item.isRation or props.ration or item.type == "ration") then
        return true
    end
    if normalized == "perishable" and (props.perishable or item.perishable) then
        return true
    end

    return itemHasMarker(item, normalized)
end

local function itemMatchesMaleficenceEffect(item, effect)
    if not item or item.destroyed then
        return false
    end

    effect = effect or {}
    local props = item.properties or {}
    local from = normalizeSocialTag(effect.from)

    if effect.material and not itemMatchesMaterial(item, effect.material) then
        return false
    end
    if effect.exceptMaterial and itemMatchesMaterial(item, effect.exceptMaterial) then
        return false
    end
    if effect.excludeMaterial and itemMatchesMaterial(item, effect.excludeMaterial) then
        return false
    end
    if effect.tag and not itemHasMaleficenceTag(item, effect.tag) then
        return false
    end
    if from == "weapon" and not (item.isWeapon or props.weapon or item.weaponType) then
        return false
    end
    if from == "treasure" and not (props.treasure or props.currency or props.jewelry or props.gem or
       props.gems or props.precious) then
        return false
    end

    return true
end

local function featureMatchesMaleficenceMaterial(feature, material)
    if not feature or not material then
        return false
    end

    local wanted = normalizeSocialTag(material)
    local props = feature.properties or {}
    local featureMaterial = normalizeSocialTag(feature.material or props.material)
    if featureMaterial == wanted then
        return true
    end

    if wanted == "wood" then
        if feature.wooden or feature.isWooden or props.wooden or props.isWooden then
            return true
        end
        local name = normalizeSocialTag(feature.name or feature.id)
        return name == "wooden_door" or name == "wooden_chest" or
            name == "wood_door" or name == "wood_chest"
    end

    return false
end

local function entityCarriesMaleficenceMaterial(entity, material)
    if not entity then
        return false
    end

    local requested = normalizeSocialTag(material)
    if requested == "metal" and (entity.carriesMetal or entity.hasMetal or entity.wearingMetalArmor) then
        return true
    end

    if entity.inventory and entity.inventory.getAllItems then
        for _, entry in ipairs(entity.inventory:getAllItems()) do
            if itemMatchesMaterial(entry.item, material) then
                return true
            end
        end
    end

    return false
end

local function maleficenceLabel(value)
    local label = tostring(value or "Maleficence")
    label = label:gsub("_", " ")
    return (label:gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end))
end

local function normalizeMaleficenceAttribute(attribute)
    local normalized = normalizeSocialTag(attribute)
    if normalized == "swords" then
        return constants.SUITS.SWORDS, "swords"
    elseif normalized == "pentacles" then
        return constants.SUITS.PENTACLES, "pentacles"
    elseif normalized == "cups" then
        return constants.SUITS.CUPS, "cups"
    elseif normalized == "wands" then
        return constants.SUITS.WANDS, "wands"
    end

    return constants.SUITS.WANDS, "wands"
end

local function getMappedMaleficenceValue(values, entity, index)
    if type(values) ~= "table" then
        return nil
    end

    return values[entity] or
        (entity and entity.id and values[entity.id]) or
        (entity and entity.name and values[entity.name]) or
        values[index]
end

local function drawMaleficenceTestCard(resolverInstance, opts)
    opts = opts or {}
    local deck = opts.roomTestDeck or opts.testDeck or opts.playerDeck or
        (resolverInstance and resolverInstance.playerDeck)
    if not deck or not deck.draw then
        return nil, false
    end

    local card = deck:draw()
    if card and deck.discard and opts.discardRoomTestDraws ~= false then
        deck:discard(card)
        return card, true
    end

    return card, false
end

local function resolveMaleficenceRoomTestForEntity(resolverInstance, entity, effect, opts, index)
    local suit, attributeName = normalizeMaleficenceAttribute(effect.attribute)
    local suppliedResult = getMappedMaleficenceValue(opts.roomTestResults or opts.testResults, entity, index)
    local suppliedCard = getMappedMaleficenceValue(opts.roomTestCards or opts.testCards, entity, index)
    local suppliedFavor = getMappedMaleficenceValue(opts.roomTestFavor or opts.testFavor, entity, index)

    if suppliedResult and suppliedResult.card and not suppliedCard then
        suppliedCard = suppliedResult.card
    end

    if suppliedResult and suppliedResult.result then
        return suppliedResult, suppliedResult.cards and suppliedResult.cards[1] or suppliedCard, false
    end

    local card = suppliedCard
    local discarded = false
    if not card then
        card, discarded = drawMaleficenceTestCard(resolverInstance, opts)
    end
    if not card then
        return nil, nil, false
    end

    local attributeValue = 0
    if entity then
        if entity.getAttribute then
            attributeValue = entity:getAttribute(suit) or 0
        else
            attributeValue = entity[attributeName] or 0
        end
    end

    return fate_resolver.resolveTest(attributeValue, suit, card, suppliedFavor), card, discarded
end

local function applyMaleficenceRoomTestFailure(entity, effect, opts)
    if not entity then
        return nil
    end

    local failCondition = normalizeSocialTag(effect.failCondition or effect.condition)
    entity.conditions = entity.conditions or {}

    if failCondition == "knocked_out" or failCondition == "knockout" then
        entity.conditions.knocked_out = true
        entity.conditions.knockout = true
        entity.conditions.sleeping = true
        entity.sleep = entity.sleep or {}
        entity.sleep.source = "maleficence"
        entity.sleep.maleficence = true
        entity.sleep.deep = true
        entity.sleep.branch = opts and opts.branch
        entity.sleep.rank = opts and opts.entry and opts.entry.rank
        entity.maleficenceSleep = entity.sleep
        return "knocked_out"
    end

    if failCondition then
        entity.conditions[failCondition] = true
        return failCondition
    end

    return nil
end

local function getMaleficenceMinorDiscardCard(opts)
    opts = opts or {}
    local card = opts.minorDiscardCard or opts.topMinorDiscardCard or
        opts.topMinorDiscard or opts.dispositionCard
    if card then
        return card
    end

    local deck = opts.minorDeck or opts.playerDeck
    if deck and deck.peekDiscard then
        return deck:peekDiscard()
    end

    return nil
end

local function getImpDesireFromMinorCard(card)
    if not card then
        return nil
    end

    if card.suit == constants.SUITS.SWORDS then
        return "flesh"
    elseif card.suit == constants.SUITS.PENTACLES then
        return "shinies"
    elseif card.suit == constants.SUITS.CUPS then
        return "pet"
    elseif card.suit == constants.SUITS.WANDS then
        return "sorcerer_blood"
    end

    return nil
end

local function getMaleficenceSpawnCount(effect, opts)
    opts = opts or {}
    local explicit = tonumber(opts.spawnCount or effect.countValue)
    if explicit then
        return math.max(0, math.floor(explicit))
    end

    if effect.countFrom == "minor_discard_value" then
        local card = getMaleficenceMinorDiscardCard(opts)
        return math.max(0, math.floor(tonumber(card and card.value) or 0))
    end

    if effect.count == "several" then
        return math.max(1, math.floor(tonumber(opts.severalSpawnCount) or 3))
    end

    return math.max(1, math.floor(tonumber(effect.count) or 1))
end

local function configureMaleficenceSpawn(entity, actor, effect, opts, index)
    if not entity then
        return
    end

    entity.source = "maleficence"
    entity.maleficenceSpawn = true
    entity.maleficenceSpawnIndex = index
    entity.sourceActor = actor
    entity.sourceActorId = actor and actor.id
    entity.sourceActorName = actor and actor.name
    entity.location = (actor and (actor.location or actor.roomId or actor.currentRoomId)) or entity.location
    entity.roomId = (actor and (actor.roomId or actor.currentRoomId or actor.location)) or entity.roomId
    entity.zone = (opts and opts.spawnZone) or (actor and actor.zone) or entity.zone
    entity.conditions = entity.conditions or {}

    if effect.hostile then
        entity.hostile = true
        entity.conditions.hostile = true
    end

    if effect.mobId == "imp" then
        local desire = getImpDesireFromMinorCard(getMaleficenceMinorDiscardCard(opts))
        entity.impDesire = desire
        entity.maleficenceDesire = desire
    elseif effect.mobId == "hekatephage" then
        entity.hostile = true
        entity.conditions.hostile = true
        entity.conditions.shrouded = true
        entity.conditions.intangible = true
        entity.followsSorcerer = actor
        entity.followsSorcererId = actor and actor.id
        entity.magicEater = true
        entity.endsNonConcentrationSpells = true
    elseif effect.mobId == "stone_twin" then
        entity.hostile = true
        entity.conditions.hostile = true
        entity.replaceTarget = actor
        entity.replaceTargetId = actor and actor.id
        entity.mission = "kill_and_replace_sorcerer"
        if actor and actor.name then
            entity.name = "Stone Twin of " .. actor.name
        end
    end
end

local function createMaleficenceRoomFeature(effect)
    effect = effect or {}
    local featureId = effect.feature or effect.hazard or effect.tag or effect.type or "maleficence"
    local featureType = effect.type == "room_hazard" and "hazard" or "maleficence_feature"
    local feature = {
        id = tostring(featureId),
        name = maleficenceLabel(featureId),
        type = featureType,
        state = "active",
        source = "maleficence",
        maleficenceType = effect.type,
    }

    if effect.type == "room_hazard" then
        feature.hazard = effect.hazard or effect.tag
        feature.isHazard = true
    else
        feature.feature = effect.feature or effect.tag
    end

    return feature
end

local function createMaleficenceAreaCondition(effect)
    effect = effect or {}
    local condition = effect.areaCondition or effect.condition or effect.tag or "area_condition"
    return {
        id = tostring(effect.tag or condition or "area_condition"),
        name = maleficenceLabel(effect.name or condition),
        type = "area_condition",
        state = "active",
        source = "maleficence",
        condition = condition,
        target = effect.target,
        maleficenceType = effect.type,
    }
end

local function entityHasTagValue(entity, tag)
    if not entity or not tag then
        return false
    end

    local tags = entity.tags or entity.aiTags or entity.traits or {}
    if type(tags) ~= "table" then
        return false
    end

    if tags[tag] == true then
        return true
    end

    for _, value in pairs(tags) do
        if value == tag then
            return true
        end
    end

    return false
end

local function isInspirationImmuneTarget(target)
    if not target then
        return true
    end
    local conditions = target.conditions or {}
    return target.immuneToInspiration == true or target.inspirationImmune == true or
        target.emotionless == true or target.noEmotions == true or conditions.inspire_immune == true or
        conditions.inspired_immune == true or conditions.nymph_beauty == true or
        conditions.emotionless == true or entityHasTagValue(target, "emotionless") or
        entityHasTagValue(target, "mindless")
end

local function isControlImmuneTarget(target)
    if not target then
        return true
    end
    local conditions = target.conditions or {}
    return target.immuneToControl == true or target.controlImmune == true or
        conditions.control_immune == true or conditions.controlImmune == true or
        conditions.cannot_be_controlled == true or conditions.nymph_beauty == true
end

local invisibleFireFlammableMaterials = {
    wood = true,
    cloth = true,
    paper = true,
    parchment = true,
    fabric = true,
    canvas = true,
    linen = true,
}

local function hasMaterialValue(value, material)
    if type(value) == "string" then
        return string.lower(value) == material
    elseif type(value) == "table" then
        if value[material] == true then
            return true
        end
        for _, entry in pairs(value) do
            if type(entry) == "string" and string.lower(entry) == material then
                return true
            end
        end
    end
    return false
end

local function targetHasMaterial(target, material)
    local props = target and target.properties or {}
    return hasMaterialValue(target and target.material, material)
        or hasMaterialValue(target and target.substance, material)
        or hasMaterialValue(props.material, material)
        or hasMaterialValue(props.materials, material)
        or hasMaterialValue(props.substance, material)
end

local function isFlammableTarget(target)
    local props = target and target.properties or {}
    if target and (target.flammable == true or props.flammable == true) then
        return true
    end

    for material in pairs(invisibleFireFlammableMaterials) do
        if targetHasMaterial(target, material) then
            return true
        end
    end

    return false
end

local function isWeaponTarget(target)
    local props = target and target.properties or {}
    return target and (target.isWeapon == true or target.weaponType ~= nil or
        props.weapon == true or props.isWeapon == true or entityHasTagValue(target, "weapon"))
end

local function notchItemTarget(target)
    target.notches = target.notches or 0
    target.durability = target.durability or inventory.DURABILITY.NORMAL
    return inventory.addNotch(target)
end

local function isPetrifiedTarget(target)
    if not target then
        return false
    end
    local conditions = target.conditions or {}
    return target.petrified == true or target.curseOfPetrification == true or
        target.petrificationCurse == true or conditions.petrified == true or
        conditions.petrification == true or conditions.turned_to_stone == true
end

local function isStoneTarget(target)
    if not target then
        return false
    end
    local props = target.properties or {}
    local conditions = target.conditions or {}
    return target.stone == true or props.stone == true or conditions.stone == true or
        targetHasMaterial(target, "stone") or isPetrifiedTarget(target) or
        entityHasTagValue(target, "stone") or entityHasTagValue(target, "gargoyle") or
        entityHasTagValue(target, "animate_stone") or entityHasTagValue(target, "animate_statue")
end

local function isStoneCreatureTarget(target)
    return target and target.takeWound ~= nil and isStoneTarget(target)
end

local function isPersonSizedStoneTarget(target, effect)
    local props = target and target.properties or {}
    if target and (target.personSized == true or props.personSized == true) then
        return true
    end
    if target and (target.large == true or props.large == true or props.largerThanPerson == true) then
        return false
    end

    local size = target and (target.size or target.slots or props.size or props.slots)
    return not size or size <= ((effect and effect.personSizeLimit) or 2)
end

local function clearPetrification(target)
    if not target then
        return false
    end

    local cured = isPetrifiedTarget(target)
    target.conditions = target.conditions or {}
    for _, condition in ipairs({ "petrified", "petrification", "turned_to_stone", "stone" }) do
        if target.conditions[condition] then
            cured = true
            target.conditions[condition] = false
        end
    end

    if target.petrified or target.curseOfPetrification or target.petrificationCurse then
        cured = true
    end
    target.petrified = false
    target.curseOfPetrification = nil
    target.petrificationCurse = nil

    local malediction = target.malediction
    local curse = malediction and malediction.curse
    local curseId = malediction and (malediction.curseId or (curse and curse.id))
    if curseId == "petrification" or (malediction and malediction.petrification == true) then
        malediction.active = false
        malediction.ended = true
        malediction.endReason = "cockatrice_oil"
        cured = true
    end

    local function clearPetrificationEntry(entry)
        if type(entry) == "table" and (entry.curseId == "petrification" or entry.petrification == true or
           (entry.curse and entry.curse.id == "petrification")) then
            entry.active = false
            entry.ended = true
            entry.endReason = "cockatrice_oil"
            cured = true
        end
    end
    clearPetrificationEntry(target.petrificationMalediction)
    if type(target.maledictions) == "table" then
        clearPetrificationEntry(target.maledictions.petrification)
    end

    return cured
end

local impPotionAlchemicalConditions = {
    "poisoned",
    "poison",
    "harpy_wings",
    "flying",
    "flight",
    "arms_are_wings",
    "cannot_hold_items",
    "cannot_hover",
    "must_keep_flying",
    "fire_immunity",
    "heat_immunity",
    "gear_still_burns",
    "face_rat_illusion",
    "illusion_duplicate_pending",
    "visual_illusion",
    "water_breathing",
    "underwater_breathing",
    "gills",
    "nymph_beauty",
    "disposition_influence_favor",
    "inspire_immune",
    "control_immune",
    "poison_immunity",
    "ingestion_immunity",
    "harmless_swallowing",
    "shapeless_body",
    "no_fall_damage",
    "squeeze_through_gaps",
    "cold_immunity",
    "ice_damage_immunity",
    "comfortable_in_cold",
    "ungoat_spell_ward",
    "spell_target_blocked",
    "cannot_cast_spells",
    "mist_form",
    "vampire_mist",
    "hazard_resistant",
    "can_pass_cracks",
    "vampire_weaknesses",
    "sunlight_stuns",
    "wholesome_herbs_stun",
    "silver_stuns",
    "running_water_stuns",
    "sizeChanged",
    "sizeGrown",
    "titan_growth",
    "inspired",
    "inspiredJoy",
    "inspiredRomanticJoy",
    "inLove",
    "inspiredDistaste",
    "inHate",
    "inspiredAnger",
    "enraged",
}

local function clearImpPotionAlchemy(target)
    local cleared = {}
    if not target then
        return cleared
    end

    target.conditions = target.conditions or {}
    for _, condition in ipairs(impPotionAlchemicalConditions) do
        if target.conditions[condition] then
            target.conditions[condition] = false
            cleared[#cleared + 1] = condition
        end
        if target.conditionDurations then
            target.conditionDurations[condition] = nil
        end
    end

    if target.poisoned then
        target.poisoned = false
        cleared[#cleared + 1] = "poisoned"
    end
    target.poison = nil

    for _, field in ipairs({
        "romanticInspiration",
        "romanticInspirationTarget",
        "distasteInspiration",
        "distasteInspirationTarget",
        "ogrePheromone",
        "recklessAttackTarget",
        "mistForm",
        "vampireWeaknesses",
        "changeSize",
    }) do
        if target[field] ~= nil then
            target[field] = nil
        end
    end

    return cleared
end

local griffinOilCleanFlags = {
    "rust",
    "rusted",
    "dirty",
    "filthy",
    "filth",
    "impure",
    "impurities",
    "minorFlaw",
    "minor_flaw",
    "minor_flaws",
    "foul",
    "stink",
}

local function clearCleanseFlag(container, key, cleaned)
    if container and container[key] then
        container[key] = false
        cleaned[#cleaned + 1] = key
    end
end

local function cleanseTargetWithGriffinOil(target, action)
    local cleaned = {}
    if not target then
        return cleaned
    end

    local props = target.properties or {}
    target.properties = props
    for _, key in ipairs(griffinOilCleanFlags) do
        clearCleanseFlag(target, key, cleaned)
        clearCleanseFlag(props, key, cleaned)
    end

    local conditions = target.conditions or {}
    if conditions.imp_stink or conditions.choking_stink or target.impStink then
        conditions.imp_stink = false
        conditions.choking_stink = false
        cleaned[#cleaned + 1] = "imp_stink"
        if target.impStink and target.impStink.stressedUntilWashed and conditions.stressed then
            conditions.stressed = false
            cleaned[#cleaned + 1] = "imp_stink_stress"
        end
        target.impStink = nil
    end

    props.cleaned = true
    props.griffinOilClean = true
    target.cleaned = true
    if action and (action.dungeonBath == true or action.bath == true or target == action.actor) then
        target.griffinOilBath = true
    end

    return cleaned
end

local function rememberContainerField(container, key)
    if not container then
        return { present = false }
    end

    return {
        present = container[key] ~= nil,
        value = container[key],
    }
end

local function restoreContainerField(container, key, record)
    if not container or not record then
        return
    end

    if record.present then
        container[key] = record.value
    else
        container[key] = nil
    end
end

local function applyJinnPotionShroud(target, item, effect)
    target.conditions = target.conditions or {}
    local previous = {
        fields = {
            canSeeShrouded = rememberContainerField(target, "canSeeShrouded"),
            canSeeInvisible = rememberContainerField(target, "canSeeInvisible"),
            shroudedBy = rememberContainerField(target, "shroudedBy"),
        },
        conditions = {
            shrouded = rememberContainerField(target.conditions, "shrouded"),
            invisible = rememberContainerField(target.conditions, "invisible"),
            see_shrouded = rememberContainerField(target.conditions, "see_shrouded"),
            jinn_shroud = rememberContainerField(target.conditions, "jinn_shroud"),
        },
    }

    target.conditions.shrouded = true
    target.conditions.invisible = true
    target.conditions.see_shrouded = true
    target.conditions.jinn_shroud = true
    target.canSeeShrouded = true
    target.canSeeInvisible = true
    target.shroudedBy = target

    target.jinnShroud = {
        sourceItemId = item.id,
        sourceItemName = item.name,
        duration = effect.duration or "visible_interaction",
        endsOnVisibleObjectInteraction = true,
        previous = previous,
    }
    target.shroud = {
        caster = target,
        source = "jinn_potion",
        sourceItemId = item.id,
        sourceItemName = item.name,
        duration = effect.duration or "visible_interaction",
        potion = true,
        canSeeShrouded = true,
        visibleObjectsEndEffect = true,
        visibleObjectsRequireResolve = false,
        previous = previous,
    }

    return target.shroud
end

local function clearJinnPotionShroud(target, reason)
    if not target or not target.shroud then
        return nil
    end
    local shroud = target.shroud
    if shroud.source ~= "jinn_potion" and shroud.visibleObjectsEndEffect ~= true then
        return nil
    end

    local previous = (target.jinnShroud and target.jinnShroud.previous) or shroud.previous or {}
    restoreContainerField(target, "canSeeShrouded", previous.fields and previous.fields.canSeeShrouded)
    restoreContainerField(target, "canSeeInvisible", previous.fields and previous.fields.canSeeInvisible)
    restoreContainerField(target, "shroudedBy", previous.fields and previous.fields.shroudedBy)

    target.conditions = target.conditions or {}
    restoreContainerField(target.conditions, "shrouded", previous.conditions and previous.conditions.shrouded)
    restoreContainerField(target.conditions, "invisible", previous.conditions and previous.conditions.invisible)
    restoreContainerField(target.conditions, "see_shrouded", previous.conditions and previous.conditions.see_shrouded)
    restoreContainerField(target.conditions, "jinn_shroud", previous.conditions and previous.conditions.jinn_shroud)

    target.shroud = nil
    target.jinnShroud = nil

    return {
        target = target,
        reason = reason or "visible_object_interaction",
        source = "jinn_potion",
    }
end

local function isIntangibleTarget(target)
    if not target then
        return false
    end

    local conditions = target.conditions or {}
    local props = target.properties or {}
    return target.intangible == true or target.incorporeal == true or target.ethereal == true or
        target.tangible == false or target.visible == false or target.invisible == true or
        conditions.intangible == true or conditions.incorporeal == true or conditions.ethereal == true or
        conditions.tangible == false or conditions.visible == false or conditions.invisible == true or
        props.intangible == true or props.incorporeal == true or props.ethereal == true or
        props.tangible == false or props.visible == false or props.invisible == true
end

local function materializeWithJinnBomb(target, item)
    target.conditions = target.conditions or {}
    target.properties = target.properties or {}

    target.intangible = false
    target.incorporeal = false
    target.ethereal = false
    target.invisible = false
    target.visible = true
    target.tangible = true

    target.conditions.intangible = false
    target.conditions.incorporeal = false
    target.conditions.ethereal = false
    target.conditions.invisible = false
    target.conditions.visible = true
    target.conditions.tangible = true

    target.properties.intangible = false
    target.properties.incorporeal = false
    target.properties.ethereal = false
    target.properties.invisible = false
    target.properties.visible = true
    target.properties.tangible = true

    target.materializedByJinnBomb = {
        sourceItemId = item.id,
        sourceItemName = item.name,
        visible = true,
        tangible = true,
    }

    return target.materializedByJinnBomb
end

local function isNonLivingObjectTarget(target)
    if not target then
        return false
    end

    local props = target.properties or {}
    local conditions = target.conditions or {}
    local living = target.isPC == true or target.living == true or target.alive == true or
        target.creature == true or target.isCreature == true or target.health ~= nil or
        target.baseMorale ~= nil or target.takeWound ~= nil or conditions.living == true or
        conditions.alive == true or props.living == true or props.alive == true or
        entityHasTagValue(target, "creature") or entityHasTagValue(target, "living")
    if living then
        return false
    end

    return target.templateId ~= nil or target.durability ~= nil or target.notches ~= nil or
        target.itemType ~= nil or target.type ~= nil or props.object == true or props.isObject == true or
        props.material ~= nil or props.materials ~= nil or target.material ~= nil
end

local function awakenObjectAsMimic(target, item)
    target.conditions = target.conditions or {}
    target.properties = target.properties or {}

    local originalName = target.name or "object"
    target.isMimic = true
    target.alive = true
    target.construct = true
    target.loyal = false
    target.loyalToActor = false
    target.conditions.mimic = true
    target.properties.mimic = true
    target.properties.alive = true
    target.properties.construct = true
    target.properties.camouflagedAsObject = true
    target.properties.notLoyal = true

    target.mimic = {
        sourceItemId = item.id,
        sourceItemName = item.name,
        originalName = originalName,
        notLoyal = true,
        camouflagedAsObject = true,
        construct = true,
        treatsNotchesAsWounds = 2,
        mustExceedInitiative = true,
        attributes = {
            swords = 4,
            pentacles = 0,
            cups = 1,
            wands = 1,
        },
        health = 2,
        defense = 6,
        likes = { "sleeping" },
        hates = { "itself" },
    }

    return target.mimic
end

local function getMaleficenceInspiredDisposition(effect, opts)
    opts = opts or {}

    local requested = opts.inspiredDisposition or opts.randomDisposition or effect.disposition
    if requested then
        local disposition, severity = disposition_module.parseDisposition(requested, opts.dispositionSeverity)
        return disposition, severity, disposition_module.getDispositionLabel(disposition, severity), "explicit"
    end

    local card = opts.dispositionCard or opts.randomDispositionCard or opts.minorDiscardCard or
        opts.topMinorDiscard or opts.topMinorDiscardCard
    local disposition, severity, label = disposition_module.dispositionFromMinorDiscard(card)
    if disposition then
        return disposition, severity, label, "minor_discard"
    end

    local wheel = disposition_module.WHEEL or {
        disposition_module.DISPOSITIONS.ANGER,
        disposition_module.DISPOSITIONS.DISTASTE,
        disposition_module.DISPOSITIONS.SADNESS,
        disposition_module.DISPOSITIONS.JOY,
        disposition_module.DISPOSITIONS.SURPRISE,
        disposition_module.DISPOSITIONS.TRUST,
        disposition_module.DISPOSITIONS.FEAR,
    }
    local random = opts.random or math.random
    local index = tonumber(opts.randomDispositionIndex) or random(#wheel)
    index = math.max(1, math.min(#wheel, math.floor(index)))
    disposition = wheel[index]
    severity = disposition_module.SEVERITY.BASIC
    return disposition, severity, disposition_module.getDispositionLabel(disposition, severity), "random"
end

local function applyMaleficenceInspiredDisposition(target, disposition, severity, label)
    if not target then
        return nil
    end

    if isInspirationImmuneTarget(target) then
        return nil
    end

    local oldDisposition = target.getDisposition and target:getDisposition() or target.disposition
    local oldSeverity = target.getDispositionSeverity and target:getDispositionSeverity() or target.dispositionSeverity

    local conditions = target.conditions or {}
    target.conditions = conditions
    conditions.inspired = true
    conditions.inspiredRandomDisposition = true
    conditions["inspired_" .. tostring(disposition)] = true
    target.inspiredDisposition = disposition
    target.maleficenceInspiration = {
        source = "maleficence",
        disposition = disposition,
        severity = severity,
        label = label,
        previousDisposition = oldDisposition,
        previousSeverity = oldSeverity,
    }

    if target.setDisposition then
        target:setDisposition(disposition, severity)
    else
        target.disposition = disposition
        target.dispositionSeverity = severity
    end

    return {
        target = target,
        disposition = disposition,
        severity = severity,
        label = label,
        previousDisposition = oldDisposition,
        previousSeverity = oldSeverity,
    }
end

local function recordMaleficenceBodyChange(actor, effect, result, opts)
    if not actor then
        return false
    end

    opts = opts or {}
    local entry = opts.entry or {}
    local changeId = normalizeSocialTag(effect.change or effect.bodyChange or entry.title or "body_change")
    local change = {
        id = changeId,
        name = effect.name or entry.title or maleficenceLabel(changeId),
        summary = effect.summary or entry.summary,
        source = "maleficence",
        branch = opts.branch,
        rank = entry.rank,
        permanent = effect.permanent == true,
    }

    actor.bodyChanges = actor.bodyChanges or {}
    actor.bodyChanges[#actor.bodyChanges + 1] = change
    actor.conditions = actor.conditions or {}
    actor.conditions.body_changed = true
    actor.conditions[changeId] = true
    actor.maleficenceBodyChange = change

    result.bodyChanges = result.bodyChanges or {}
    result.bodyChanges[#result.bodyChanges + 1] = change
    result.effects[#result.effects + 1] = "maleficence_body_change"
    result.effects[#result.effects + 1] = "maleficence_body_change_" .. changeId
    return true
end

local function transformMaleficenceItem(item, effect)
    if not item then
        return nil
    end

    effect = effect or {}
    local props = item.properties or {}
    item.properties = props

    local before = {
        name = item.name,
        type = item.type,
        isWeapon = item.isWeapon,
        weaponType = item.weaponType,
        isMelee = item.isMelee,
        isRanged = item.isRanged,
        uses_ammo = item.uses_ammo,
        isLoaded = item.isLoaded,
    }

    local to = normalizeSocialTag(effect.to)
    if to == "tool" then
        local weaponType = normalizeSocialTag(item.weaponType or props.weaponType or "weapon")
        item.name = effect.name or ("Tool Formerly " .. (item.name or "Weapon"))
        item.type = "tool"
        item.isWeapon = false
        item.weaponType = nil
        item.isMelee = false
        item.isRanged = false
        item.uses_ammo = false
        item.isLoaded = nil
        props.weapon = nil
        props.weaponType = nil
        props.tool = true
        props.toolType = props.toolType or ("transformed_" .. weaponType)
    elseif to == "scarabs" then
        item.name = effect.name or "Scarabs"
        item.type = "scarabs"
        props.currency = nil
        props.jewelry = nil
        props.gem = nil
        props.gems = nil
        props.precious = nil
        props.value = nil
        props.magical = nil
        props.scarabs = true
    else
        item.name = effect.name or ("Transformed " .. (item.name or "Item"))
        item.type = to or item.type
        props[to or "transformed"] = true
    end

    item.transformedByMaleficence = true
    item.maleficenceTransform = {
        from = effect.from,
        to = effect.to,
        permanent = true,
        before = before,
    }
    props.transformedByMaleficence = true
    props.transformedFrom = effect.from
    props.transformedTo = effect.to

    return before
end

local function banterIntentTarget(intent)
    local tag = normalizeSocialTag(intent)
    if tag == "taunt" or tag == "provoke" or tag == "challenge" or tag == "anger" then
        return disposition_module.DISPOSITIONS.ANGER
    end
    if tag == "demoralize" or tag == "shame" or tag == "sadden" or tag == "sadness" then
        return disposition_module.DISPOSITIONS.SADNESS
    end
    if tag == "surprise" or tag == "startle" or tag == "confuse" then
        return disposition_module.DISPOSITIONS.SURPRISE
    end
    if tag == "trust" or tag == "reassure" then
        return disposition_module.DISPOSITIONS.TRUST
    end
    return disposition_module.DISPOSITIONS.FEAR
end

local function applySocialOutcomeToResult(result, target, outcome)
    if not outcome then
        return
    end

    result.effects = result.effects or {}
    result.socialOutcome = outcome

    if target then
        target.socialOutcome = outcome
    end

    if outcome.fairExchange then
        result.effects[#result.effects + 1] = "social_good_faith"
    end
    if outcome.extraAid then
        result.effects[#result.effects + 1] = "social_extra_aid"
    end
    if outcome.concession then
        result.effects[#result.effects + 1] = "social_concession"
    end
    if outcome.shouldFlee then
        result.effects[#result.effects + 1] = "social_flee"
        if target then
            target.conditions = target.conditions or {}
            target.conditions.fleeing = true
        end
    end
    if outcome.likelyChallenge then
        result.effects[#result.effects + 1] = "social_combat_risk"
    end
    if outcome.needsAlleviation then
        result.effects[#result.effects + 1] = "social_need"
    end
    if outcome.uncertain then
        result.effects[#result.effects + 1] = "social_uncertain"
    end
end

local function socialTargetMatchesEncounter(room, socialEncounter, target)
    if not room or not socialEncounter or not target then
        return false
    end

    local guardianId = socialEncounter.guardian
    if guardianId and (target.id == guardianId or target.featureId == guardianId or target.poiId == guardianId) then
        return true
    end

    for _, feature in ipairs(room.features or {}) do
        if not guardianId or feature.id == guardianId then
            local encounter = feature.encounter
            local blueprintId = encounter and (encounter.blueprint_id or encounter.blueprintId)
            if blueprintId and target.blueprintId == blueprintId then
                return true
            end
        end
    end

    return false
end

local function preparedSocialEffectMatches(room, socialEncounter, record, target)
    if not record or not target then
        return false
    end
    if not record.target then
        return true
    end
    if target.id == record.target or target.featureId == record.target or target.poiId == record.target then
        return true
    end
    if socialEncounter and socialEncounter.guardian == record.target then
        return socialTargetMatchesEncounter(room, socialEncounter, target)
    end
    return false
end

local function roomSocialOutcomeKey(outcome)
    if not outcome then
        return nil
    end
    if outcome.fairExchange or outcome.extraAid then
        return "trust_success"
    end
    if outcome.concession or outcome.shouldFlee then
        return "fear_success"
    end
    if outcome.likelyChallenge then
        return "anger_combat"
    end
    return nil
end

local function appendResultSentence(result, sentence)
    if not sentence or sentence == "" then
        return
    end

    if result.description and result.description ~= "" then
        result.description = result.description .. " " .. sentence
    else
        result.description = sentence
    end
end

--------------------------------------------------------------------------------
-- S7.6: WEAPON TYPE HELPERS
--------------------------------------------------------------------------------

--- Check if a weapon is of a specific category
-- @param weapon table: Weapon to check
-- @param category string: Category key from WEAPON_TYPES
-- @return boolean
function M.isWeaponType(weapon, category)
    if not weapon then return false end
    local weaponType = (weapon.weaponType or weapon.type or weapon.name or ""):lower()
    local types = M.WEAPON_TYPES[category]
    if not types then return false end

    for _, t in ipairs(types) do
        if weaponType == t or weaponType:find(t) then
            return true
        end
    end
    return false
end

local function normalizeFlareKey(value)
    return spell_registry.normalizeId(value)
end

local function flareTableContainsValue(items, value)
    if type(items) ~= "table" then
        return false
    end
    for _, entry in ipairs(items) do
        if entry == value then
            return true
        end
    end
    return false
end

local function flareHasTag(entity, tag)
    local tags = entity and entity.tags
    if type(tags) == "table" and (tags[tag] or flareTableContainsValue(tags, tag)) then
        return true
    end
    local aiTags = entity and entity.aiTags
    return type(aiTags) == "table" and (aiTags[tag] or flareTableContainsValue(aiTags, tag)) or false
end

local function getFlareLightKind(item)
    if not item then
        return nil
    end

    local props = item.properties or {}
    local id = normalizeFlareKey(item.templateId or item.id)
    local name = normalizeFlareKey(item.name or props.name)
    if props.candle or id == "candles" or id == "candle" or name == "candles" or name == "candle" then
        return "candle"
    end
    if id == "torch" or name == "torch" then
        return "torch"
    end
    if id == "lantern" or name == "lantern" then
        return "lantern"
    end
    if props.light_source then
        return "light"
    end
    return nil
end

local function isFlareCampfire(target, action)
    local props = target and target.properties or {}
    local mode = normalizeFlareKey(action and (action.flareMode or action.lightKind or action.sourceKind))
    local name = normalizeFlareKey(target and (target.name or target.id))
    return mode == "campfire" or props.campfire == true or (target and target.campfire == true) or
        name == "campfire" or name == "camp_fire"
end

local function getFlareZoneId(action, actor, target)
    return action.zoneId or action.zone or action.targetZoneId or action.targetZone or
        (target and (target.zoneId or target.zone)) or (actor and (actor.zoneId or actor.zone))
end

local function entityCarriesFlareItem(entity, item)
    if not entity or not item then
        return false
    end
    if entity.weapon == item then
        return true
    end
    local inv = entity.inventory
    if not inv then
        return false
    end
    if item.id and inv.findItem and inv:findItem(item.id) == item then
        return true
    end
    for _, location in ipairs({ inventory.LOCATIONS.HANDS, inventory.LOCATIONS.BELT, inventory.LOCATIONS.PACK }) do
        for _, carried in ipairs(inv[location] or {}) do
            if carried == item then
                return true
            end
        end
    end
    return false
end

local function inferFlareBearer(action, item)
    if not action or not item then
        return nil
    end
    if action.bearer or action.targetBearer or action.itemBearer then
        return action.bearer or action.targetBearer or action.itemBearer
    end

    local function check(entity)
        if entityCarriesFlareItem(entity, item) then
            return entity
        end
        return nil
    end

    local bearer = check(action.actor) or check(action.target)
    if bearer then
        return bearer
    end

    local groups = { action.allEntities, action.entities, action.combatants, action.guild, action.creatures }
    for _, group in ipairs(groups) do
        if type(group) == "table" then
            for _, entity in ipairs(group) do
                bearer = check(entity)
                if bearer then
                    return bearer
                end
            end
        end
    end

    return nil
end

local function getFlareInitiative(action, creature)
    local maps = {
        action and action.targetInitiatives,
        action and action.initiatives,
        action and action.initiativeValues,
    }
    for _, map in ipairs(maps) do
        if type(map) == "table" and creature then
            local value = map[creature] or map[creature.id] or map[creature.name]
            if type(value) == "table" then
                value = value.value or (value.card and value.card.value)
            end
            value = tonumber(value)
            if value then
                return value
            end
        end
    end

    local direct = creature and (creature.initiativeValue or creature.currentInitiative or creature.initiative)
    if type(direct) == "table" then
        direct = direct.value or (direct.card and direct.card.value)
    end
    return tonumber(direct) or 0
end

local function isFlareCreatureTarget(entity)
    if not entity or entity.isItem or entity.itemType then
        return false
    end
    if entity.takeWound or entity.isPC ~= nil or entity.npcHealth ~= nil or entity.health ~= nil then
        return true
    end
    local props = entity.properties or {}
    return entity.creature == true or entity.npc == true or entity.monster == true or entity.animal == true or
        entity.undead == true or entity.creatureType ~= nil or entity.kind == "creature" or
        props.creature == true or flareHasTag(entity, "creature") or flareHasTag(entity, "monster")
end

local function collectFlareCampfireCreatures(action, zoneId)
    local creatures = {}
    for _, entity in ipairs((action and action.allEntities) or {}) do
        if entity and isFlareCreatureTarget(entity) and
           (not zoneId or entity.zone == zoneId or entity.zoneId == zoneId) then
            creatures[#creatures + 1] = entity
        end
    end
    return creatures
end

local function isObviouslySuicidalControlOrder(action, orderText)
    action = action or {}
    if action.suicidalOrder == true or action.orderSuicidal == true or action.commandIsSuicidal == true or
       action.obviouslySuicidal == true then
        return true
    end
    if action.suicidalOrder == false or action.orderSuicidal == false or action.commandIsSuicidal == false or
       action.obviouslySuicidal == false then
        return false
    end

    if type(orderText) ~= "string" then
        return false
    end

    local text = string.lower(orderText)
    return text:find("kill yourself", 1, true) ~= nil or
        text:find("die for me", 1, true) ~= nil or
        text:find("jump into lava", 1, true) ~= nil or
        text:find("jump in lava", 1, true) ~= nil or
        text:find("walk into fire", 1, true) ~= nil or
        text:find("walk into the fire", 1, true) ~= nil or
        text:find("drown yourself", 1, true) ~= nil
end

local WOODWEAVE_SIZE_RANKS = {
    tiny = 1,
    handful = 1,
    hand = 1,
    handheld = 1,
    small = 2,
    chest = 3,
    chest_sized = 3,
    medium = 3,
    human = 4,
    human_sized = 4,
    large = 5,
    huge = 6,
    massive = 7,
    giant = 7,
}

local function woodweaveSizeValue(value)
    if type(value) == "number" then
        return value
    end
    if type(value) ~= "string" then
        return nil
    end

    local numeric = tonumber(value)
    if numeric then
        return numeric
    end

    local normalized = value:lower()
    normalized = normalized:gsub("^%s+", ""):gsub("%s+$", "")
    normalized = normalized:gsub("[%s%-]+", "_")
    return WOODWEAVE_SIZE_RANKS[normalized]
end

local function getWoodweaveSizeFrom(source)
    if type(source) ~= "table" then
        return woodweaveSizeValue(source)
    end

    local props = source.properties or {}
    return woodweaveSizeValue(source.woodweaveSize) or
        woodweaveSizeValue(source.rawMaterialSize) or
        woodweaveSizeValue(source.size) or
        woodweaveSizeValue(source.sizeSlots) or
        woodweaveSizeValue(source.bulk) or
        woodweaveSizeValue(source.sizeCategory) or
        woodweaveSizeValue(props.woodweaveSize) or
        woodweaveSizeValue(props.rawMaterialSize) or
        woodweaveSizeValue(props.size) or
        woodweaveSizeValue(props.sizeSlots) or
        woodweaveSizeValue(props.bulk) or
        woodweaveSizeValue(props.sizeCategory)
end

local function getWoodweaveRequestedShapeSize(action)
    if type(action) ~= "table" then
        return nil
    end

    local size = woodweaveSizeValue(action.requiredSize) or
        woodweaveSizeValue(action.shapeSize) or
        woodweaveSizeValue(action.objectSize) or
        woodweaveSizeValue(action.outputSize) or
        woodweaveSizeValue(action.desiredSize)
    if size then
        return size
    end

    for _, field in ipairs({ "shapeInto", "shape", "objectName", "object" }) do
        local spec = action[field]
        size = getWoodweaveSizeFrom(spec)
        if size then
            return size
        end
    end

    return nil
end

local function hasEquivalentWoodweaveShapeSize(materials, action)
    if not materials then
        return false
    end

    local props = materials.properties or {}
    if materials.equivalentSize == false or props.equivalentSize == false or
       materials.equivalentRawWood == false or props.equivalentRawWood == false then
        return false
    end
    if materials.equivalentSize == true or props.equivalentSize == true or
       materials.equivalentRawWood == true or props.equivalentRawWood == true then
        return true
    end

    local requestedSize = getWoodweaveRequestedShapeSize(action)
    if not requestedSize then
        return true
    end

    local availableSize = getWoodweaveSizeFrom(materials)
    return availableSize ~= nil and availableSize >= requestedSize
end

local function removeChallengeCardFromArray(cards, choice)
    if type(cards) ~= "table" or #cards == 0 then
        return nil, nil, "no_challenge_card"
    end

    choice = choice or {}
    local index = tonumber(choice.index or choice.cardIndex)
    local explicitCard = choice.card

    if not index and explicitCard then
        for i, card in ipairs(cards) do
            if card == explicitCard then
                index = i
                break
            end
        end
        if not index then
            return nil, nil, "card_not_in_hand"
        end
    end

    if not index then
        index = 1
    end
    if index < 1 or index > #cards then
        return nil, nil, "invalid_card_index"
    end

    return table.remove(cards, index), index, nil
end

local function discardChallengeCardToDeck(deck, card)
    if deck and deck.discard and card then
        deck:discard(card)
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- ACTION RESOLVER FACTORY
--------------------------------------------------------------------------------

--- Create a new ActionResolver
-- @param config table: { eventBus, zoneSystem, bidLoreEngine }
-- @return ActionResolver instance
function M.createActionResolver(config)
    config = config or {}

    local resolver = {
        eventBus   = config.eventBus or events.globalBus,
        zoneSystem = config.zoneSystem,
        bidLoreEngine = config.bidLoreEngine,
        challengeController = config.challengeController,
        playerHand = config.playerHand,
        playerDeck = config.playerDeck,
        gmDeck = config.gmDeck,
        roomManager = config.roomManager,
        watchManager = config.watchManager,
        environmentManager = config.environmentManager,
        worldState = config.worldState or config.gameState,
        -- S12.1: Engagements now tracked by zoneSystem (zone_system.lua)
        -- The zoneSystem is the single source of truth for engagement state
        -- S7.1: Track active aids { [targetId] = { val = bonus, source = actorName } }
        activeAids = {},
        vigilanceCounter = 0, -- Monotonic order for deterministic vigilance trigger ordering
    }

    function resolver:wantsResolveForLore(action)
        return action and (
            action.spendResolveForLore == true or
            action.resolveForLore == true or
            action.useResolveForLore == true or
            action.spendResolveForBidLore == true
        )
    end

    function resolver:wantsFreeLoreFollowUp(action)
        return action and (
            action.freeLoreFollowUp == true or
            action.loreFollowUp == true or
            action.weirdWiseAncientFollowUp == true
        )
    end

    function resolver:canSpendLoremasterResolveForLore(actor)
        if not entityHasUsableTalent(actor, "loremaster") then
            return false, "requires_loremaster"
        end
        if getResolveAmount(actor) < 1 then
            return false, "not_enough_resolve"
        end
        return true, nil
    end

    function resolver:canUseFreeLoreFollowUp(actor, previousResult)
        if not entityHasUsableTalent(actor, "weird_wise_ancient") then
            return false, "requires_weird_wise_ancient"
        end

        local previousVerdict = previousResult and previousResult.verdict
        if not previousVerdict and previousResult and previousResult.bidLore then
            previousVerdict = previousResult.bidLore.verdict
        end

        if not previousResult or (previousResult.success ~= true and previousVerdict ~= "accepted") then
            return false, "requires_accepted_lore"
        end

        return true, nil
    end

    ----------------------------------------------------------------------------
    -- S12.2: ACTION VALIDATION
    ----------------------------------------------------------------------------

    --- Check if an actor can perform a given action
    -- @param actor table: The acting entity
    -- @param actionType string: The action type (e.g., "missile")
    -- @param actionDef table: Optional action definition from action_registry
    -- @return boolean, string: can perform, reason if blocked
    function resolver:canPerformAction(actor, actionType, actionDef, actionContext)
        if not actor then return false, "No actor" end
        actionType = self:normalizeActionType(actionType)

        local conditions = actor.conditions or {}
        if conditions.dead or actor.dead then
            return false, "Cannot act while dead"
        end
        if conditions.deaths_door then
            return false, "Cannot act at Death's Door"
        end
        if conditions.knocked_out or conditions.knockout then
            return false, "Cannot act while knocked out"
        end
        if conditions.chicken or conditions.chickenDoom or (actor.chickenDoom and actor.chickenDoom.active ~= false) then
            return false, "Cannot act while transformed into a chicken"
        end

        if conditions.rooted and (
            actionType == M.ACTION_TYPES.AVOID or
            actionType == M.ACTION_TYPES.DASH or
            actionType == M.ACTION_TYPES.DODGE or
            actionType == M.ACTION_TYPES.MOVE
        ) then
            return false, "Cannot avoid, dash, dodge, or move while rooted"
        end

        if conditions.prone and (
            actionType == M.ACTION_TYPES.AVOID or
            actionType == M.ACTION_TYPES.DASH or
            actionType == M.ACTION_TYPES.MOVE
        ) then
            return false, "Cannot avoid, dash, or move while prone"
        end

        -- S12.2: Check ranged restriction when engaged
        local isRanged = actionType == M.ACTION_TYPES.MISSILE
        if actionDef and actionDef.isRanged then
            isRanged = true
        end

        if isRanged and (conditions.blind or conditions.blinded) then
            return false, "Cannot make missile attacks while blind"
        end

        if isRanged and self:hasAnyEngagement(actor) then
            return false, "Cannot use ranged weapons while engaged"
        end

        if actionDef then
            local requirementsDef = actionDef
            if actionType == M.ACTION_TYPES.BID_LORE and actionDef.requiresLoreBid and
               self:wantsResolveForLore(actionContext) then
                local canSpendResolve, resolveReason = self:canSpendLoremasterResolveForLore(actor)
                if not canSpendResolve then
                    return false, loreResolveFailureText(resolveReason)
                end
                requirementsDef = {}
                for key, value in pairs(actionDef) do
                    requirementsDef[key] = value
                end
                requirementsDef.requiresLoreBid = false
            end

            local requirementsOk, requirementReason = action_registry.checkActionRequirements(requirementsDef, actor)
            if not requirementsOk then
                return false, requirementReason or "Action requirements not met"
            end
        end

        return true, nil
    end

    ----------------------------------------------------------------------------
    -- ACTION HELPERS
    ----------------------------------------------------------------------------

    local actionSuitToCardSuit = {
        [action_registry.SUITS.SWORDS]    = constants.SUITS.SWORDS,
        [action_registry.SUITS.PENTACLES] = constants.SUITS.PENTACLES,
        [action_registry.SUITS.CUPS]      = constants.SUITS.CUPS,
        [action_registry.SUITS.WANDS]     = constants.SUITS.WANDS,
    }

    function resolver:dropCarriedItem(entity, item, reason, opts)
        if not entity or not item then
            return nil
        end

        local droppedItem = item
        if entity.inventory and entity.inventory.removeItem and item.id then
            droppedItem = entity.inventory:removeItem(item.id) or item
        elseif entity.weapon == item then
            entity.weapon = nil
        end

        entity.droppedItems = entity.droppedItems or {}
        entity.droppedItems[#entity.droppedItems + 1] = droppedItem

        self.eventBus:emit(events.EVENTS.LIGHT_SOURCE_DROPPED, {
            entity = entity,
            item = droppedItem,
            reason = reason,
            torchStaysLit = opts and opts.torchStaysLit,
            torchExtinguished = opts and opts.torchExtinguished,
        })

        return droppedItem
    end

    function resolver:getStunDiscardChoice(entity, opts)
        opts = opts or {}
        local action = opts.action or {}
        local choice = {
            card = opts.stunDiscardCard or action.stunDiscardCard,
            index = opts.stunDiscardIndex or opts.stunDiscardCardIndex or
                action.stunDiscardIndex or action.stunDiscardCardIndex,
        }
        local entityId = entity and entity.id

        local function applyMappedChoice(value)
            if value == nil then
                return
            end

            local numeric = tonumber(value)
            if numeric then
                choice.index = numeric
                return
            end

            if type(value) == "table" then
                if value.card or value.index or value.cardIndex then
                    choice.card = value.card or choice.card
                    choice.index = value.index or value.cardIndex or choice.index
                else
                    choice.card = value
                end
            end
        end

        if entityId then
            if type(opts.stunDiscards) == "table" then
                applyMappedChoice(opts.stunDiscards[entityId])
            end
            if type(action.stunDiscards) == "table" then
                applyMappedChoice(action.stunDiscards[entityId])
            end
            if type(action.stunDiscardCards) == "table" then
                applyMappedChoice(action.stunDiscardCards[entityId])
            end
            if type(action.stunDiscardIndexes) == "table" then
                applyMappedChoice(action.stunDiscardIndexes[entityId])
            end
        end

        return choice
    end

    function resolver:discardStunChallengeCard(entity, opts)
        opts = opts or {}
        local action = opts.action or {}
        local choice = self:getStunDiscardChoice(entity, opts)

        local function makeResult(card, index, source, deckDiscarded, reason)
            return {
                entity = entity,
                card = card,
                index = index,
                source = source,
                deckDiscarded = deckDiscarded == true,
                discarded = card ~= nil,
                reason = reason,
            }
        end

        local playerHand = opts.playerHand or action.playerHand or self.playerHand
        if entity and entity.isPC and playerHand and playerHand.discardCard then
            local card, index, err = playerHand:discardCard(entity, {
                card = choice.card,
                index = choice.index,
                reason = "stunned",
            })
            if card then
                return makeResult(card, index, "player_hand", true, nil)
            end
            if err == "card_not_in_hand" or err == "invalid_card_index" then
                return makeResult(nil, nil, "player_hand", false, err)
            end
        end

        local handData = opts.handData or action.handData or (entity and entity.challengeHandData)
        local hand = opts.hand or action.hand or (handData and handData.cards) or
            (entity and entity.challengeHand)
        if type(hand) ~= "table" or #hand == 0 then
            local entityHand = entity and entity.hand
            if type(entityHand) == "table" and #entityHand > 0 then
                hand = entityHand
            end
        end

        if type(hand) == "table" and #hand > 0 then
            local deck = opts.deck or action.stunDiscardDeck or action.discardDeck or
                (entity and entity.isPC and (action.playerDeck or self.playerDeck) or (action.gmDeck or self.gmDeck))
            local card, index, err = removeChallengeCardFromArray(hand, choice)
            if card then
                return makeResult(card, index, "entity_hand", discardChallengeCardToDeck(deck, card), nil)
            end
            return makeResult(nil, nil, "entity_hand", false, err)
        end

        local npcAI = opts.npcAI or action.npcAI or self.npcAI
        if entity and not entity.isPC and npcAI and npcAI.useCard then
            local index = choice.index
            if not index and choice.card and type(npcAI.hand) == "table" then
                for i, card in ipairs(npcAI.hand) do
                    if card == choice.card then
                        index = i
                        break
                    end
                end
                if not index then
                    return makeResult(nil, nil, "gm_hand", false, "card_not_in_hand")
                end
            end

            local card = npcAI:useCard(index or 1)
            if card then
                return makeResult(card, index or 1, "gm_hand", true, nil)
            end
        end

        return makeResult(nil, nil, nil, false, "no_challenge_card")
    end

    function resolver:applyStun(entity, opts)
        opts = opts or {}
        if not entity then
            return {
                discarded = false,
                reason = "no_entity",
            }
        end

        entity.conditions = entity.conditions or {}
        entity.conditions.stunned = true
        if opts.instant ~= false then
            entity.conditions.stunnedInstant = true
        end

        local discard = self:discardStunChallengeCard(entity, opts)
        entity.lastStunDiscard = discard

        if discard.card and discard.source ~= "player_hand" then
            self.eventBus:emit(events.EVENTS.CHALLENGE_CARD_DISCARDED, {
                entity = entity,
                card = discard.card,
                cardIndex = discard.index,
                reason = "stunned",
            })
        end

        return discard
    end

    function resolver:getEffectAllEntities(opts)
        opts = opts or {}
        local action = opts.action or {}
        return opts.allEntities or action.allEntities or
            (action.challengeController and action.challengeController.allCombatants) or
            (self.challengeController and self.challengeController.allCombatants)
    end

    function resolver:applyRooted(entity, opts)
        if not entity then
            return false
        end

        opts = opts or {}
        entity.conditions = entity.conditions or {}
        entity.conditions.rooted = true
        self:clearAllEngagements(entity, self:getEffectAllEntities(opts))

        self.eventBus:emit("entity_rooted", {
            entity = entity,
            reason = opts.reason or "rooted",
        })

        return true
    end

    function resolver:isLightSourceItem(item)
        if not item then
            return false
        end

        local props = item.properties or {}
        local name = string.lower(item.name or "")
        return props.light_source == true or name == "torch" or name == "lantern" or
            name == "candle" or name == "candles"
    end

    function resolver:breakLightSourceItem(entity, item, reason, result)
        if not self:isLightSourceItem(item) or item.destroyed then
            return false
        end

        item.properties = item.properties or {}
        item.destroyed = true
        item.properties.broken = true
        item.properties.extinguished = true
        item.properties.isLit = false
        item.properties.is_lit = false

        if result then
            result.effects[#result.effects + 1] = "light_source_broken"
            result.lightSourceBroken = item
        end

        self.eventBus:emit(events.EVENTS.LIGHT_DESTROYED, {
            entity = entity,
            item = item,
            reason = reason,
        })
        self.eventBus:emit(events.EVENTS.INVENTORY_CHANGED, {
            entity = entity,
            item = item,
            reason = reason,
        })

        return true
    end

    function resolver:breakLightSourceWeaponIfNeeded(action, result)
        return self:breakLightSourceItem(action and action.actor, action and action.weapon, "used_as_weapon", result)
    end

    function resolver:isFragileFallItem(item)
        if not item or item.destroyed then
            return false
        end

        local props = item.properties or {}
        local tags = props.tags or item.tags or {}
        return item.durability == 1 or props.fragile == true or props.hermeticBottle == true or
            props.glass == true or tags.fragile == true or tags.glass == true
    end

    function resolver:destroyFragileFallItems(entity)
        local destroyed = {}
        if not entity or not entity.inventory or not entity.inventory.getItems then
            return destroyed
        end

        for _, location in ipairs({ inventory.LOCATIONS.BELT, inventory.LOCATIONS.PACK }) do
            local items = entity.inventory:getItems(location) or {}
            for _, item in ipairs(items) do
                if self:isFragileFallItem(item) then
                    item.destroyed = true
                    item.properties = item.properties or {}
                    item.properties.broken = true
                    item.properties.destroyedByFall = true
                    destroyed[#destroyed + 1] = item
                end
            end
        end

        if #destroyed > 0 then
            self.eventBus:emit(events.EVENTS.INVENTORY_CHANGED, {
                entity = entity,
                reason = "fall_great_failure",
                destroyedItems = destroyed,
            })
        end

        return destroyed
    end

    function resolver:resolveAcrobatFallReduction(entity, opts, result)
        if not entityHasUsableTalent(entity, "acrobat") then
            return 0
        end

        local prepared = opts.acrobatPrepared == true or opts.preparedForFall == true or opts.prepared == true or
            entity.acrobatPrepared == true or entity.preparedForFall == true
        local spendResolve = opts.spendResolveForAcrobat == true or opts.useAcrobatResolve == true or
            opts.acrobatResolve == true

        if not prepared and spendResolve then
            local ok, reason = self:spendResolveForFavor(entity)
            if not ok then
                result.effects[#result.effects + 1] = "acrobat_resolve_missing"
                result.acrobatResolveReason = reason
                return 0
            end
            result.acrobatResolveSpent = true
            result.effects[#result.effects + 1] = "resolve_spent_for_acrobat"
        elseif not prepared then
            return 0
        end

        result.acrobatReductionFeet = 20
        result.effects[#result.effects + 1] = "acrobat_fall_reduction"
        return 20
    end

    function resolver:resolveFall(entity, heightFeet, opts)
        opts = opts or {}
        heightFeet = math.max(0, tonumber(heightFeet or opts.heightFeet or opts.height or 0) or 0)

        local result = {
            entity = entity,
            heightFeet = heightFeet,
            effectiveHeightFeet = heightFeet,
            baseWounds = math.floor(heightFeet / 10),
            wounds = 0,
            effects = { "falling" },
            fragileItemsDestroyed = {},
        }

        if not entity then
            result.success = false
            result.description = "No falling entity."
            return result
        end

        if (entity.conditions and entity.conditions.no_fall_damage) or entity.immuneToFallingDamage or
           self:doesElementProtectionBlock(entity, "falling") then
            result.success = true
            result.prevented = true
            result.effects[#result.effects + 1] = "fall_prevented"
            result.effectiveHeightFeet = 0
            result.description = "Falling damage prevented."
            return result
        end

        local testResult = opts.testResult
        if not testResult and opts.card then
            testResult = fate_resolver.resolveTest(entity.pentacles or 0, constants.SUITS.PENTACLES, opts.card, opts.favor)
        end

        local greatFailure = opts.greatFailure == true or
            (testResult and testResult.success == false and testResult.isGreat == true) or
            (testResult and testResult.result == fate_resolver.RESULTS.GREAT_FAILURE)
        local reduction = 0

        if not greatFailure then
            if opts.greatSuccess == true or (testResult and testResult.success and testResult.isGreat) then
                reduction = 20
                result.effects[#result.effects + 1] = "fall_great_success"
            elseif opts.success == true or (testResult and testResult.success) then
                reduction = 10
                result.effects[#result.effects + 1] = "fall_success"
            end
        end

        reduction = reduction + self:resolveAcrobatFallReduction(entity, opts, result)

        result.testResult = testResult
        result.greatFailure = greatFailure
        result.heightReductionFeet = reduction
        result.effectiveHeightFeet = math.max(0, heightFeet - reduction)
        result.wounds = math.floor(result.effectiveHeightFeet / 10)

        if greatFailure then
            result.effects[#result.effects + 1] = "fall_great_failure"
            result.fragileItemsDestroyed = self:destroyFragileFallItems(entity)
        end

        if result.wounds > 0 then
            self:applyDamage(entity, result.wounds, { "piercing", "falling" }, nil, opts.allEntities, opts.woundOptions)
        end

        result.success = result.wounds == 0
        result.description = result.wounds > 0
            and ("Fell " .. tostring(heightFeet) .. " feet and took " .. tostring(result.wounds) .. " piercing Wound(s).")
            or ("Fell " .. tostring(heightFeet) .. " feet without damage.")

        return result
    end

    function resolver:getActionDef(action)
        if not action then return nil end
        if action.actionDef then return action.actionDef end
        if action.type then
            return action_registry.getAction(action.type)
        end
        return nil
    end

    function resolver:normalizeActionType(actionType)
        if not actionType then
            return actionType
        end
        return M.ACTION_ALIASES[actionType] or actionType
    end

    function resolver:usesCardValueOnly(action)
        if not action then return false end
        if action.isControlledAction then return true end
        if action.isMinorAction then return true end
        return false
    end

    function resolver:getActionModifier(action, actionDef)
        if not action or not action.actor then return 0 end
        if self:usesCardValueOnly(action) then return 0 end

        if self:isGramaryWandAttack(action) then
            return action.actor.wands or 0
        end

        if actionDef and actionDef.attribute then
            return action.actor[actionDef.attribute] or 0
        end

        -- Fallback for unknown actions: use card suit stat
        if not actionDef and action.card and action.card.suit then
            return self:getStatModifier(action.actor, action.card.suit)
        end

        return 0
    end

    function resolver:isInitiativeOpposed(actionType)
        actionType = self:normalizeActionType(actionType)
        return actionType == M.ACTION_TYPES.MELEE or
               actionType == M.ACTION_TYPES.MISSILE or
               actionType == M.ACTION_TYPES.ROUGHHOUSE or
               actionType == M.ACTION_TYPES.TRIP or
               actionType == M.ACTION_TYPES.DISARM or
               actionType == M.ACTION_TYPES.DISPLACE or
               actionType == M.ACTION_TYPES.GRAPPLE or
               actionType == M.ACTION_TYPES.SPEAK_INCANTATION or
               actionType == M.ACTION_TYPES.COMMAND or
               actionType == M.ACTION_TYPES.USE_ITEM
    end

    function resolver:heavyMetalMachineMatches(interrupt, action)
        if not interrupt then
            return false
        end

        if interrupt.againstAction and action and interrupt.againstAction ~= action then
            return false
        end
        if interrupt.againstActionId and action and action.id and interrupt.againstActionId ~= action.id then
            return false
        end
        if interrupt.againstActorId and action and action.actor and interrupt.againstActorId ~= action.actor.id then
            return false
        end

        return true
    end

    function resolver:consumeHeavyMetalMachineInterrupt(target, action, baseInitiative)
        local interrupt = target and target.heavyMetalMachineInterrupt
        if not interrupt or interrupt.consumed then
            return baseInitiative
        end
        if not self:heavyMetalMachineMatches(interrupt, action) then
            return baseInitiative
        end

        local controller = (action and action.challengeController) or self.challengeController
        local currentRound = controller and controller.currentRound or action and action.currentRound or interrupt.round
        if interrupt.round and currentRound and interrupt.round ~= currentRound then
            target.heavyMetalMachineInterrupt = nil
            return baseInitiative
        end

        interrupt.consumed = true
        target.heavyMetalMachineInterrupt = nil

        local boosted = baseInitiative + (interrupt.bonus or 0)
        action.heavyMetalMachineApplied = {
            actor = target,
            bonus = interrupt.bonus or 0,
            baseInitiative = baseInitiative,
            value = boosted,
            card = interrupt.card,
        }

        return boosted
    end

    function resolver:getTargetInitiative(target, action)
        if not target then return nil end
        if action and action.targetInitiative then
            return self:consumeHeavyMetalMachineInterrupt(target, action, action.targetInitiative)
        end

        local controller = (action and action.challengeController) or self.challengeController
        if controller and controller.getInitiativeSlot then
            local slot = controller:getInitiativeSlot(target.id)
            if slot then
                if not slot.revealed then
                    slot.revealed = true
                    self.eventBus:emit(events.EVENTS.INITIATIVE_REVEALED, {
                        entity = target,
                    })
                end
                local value = slot.value or (slot.card and slot.card.value) or nil
                if value then
                    return self:consumeHeavyMetalMachineInterrupt(target, action, value)
                end
                return nil
            end
        end

        return nil
    end

    function resolver:entityHasShield(entity)
        return self:getIntactShield(entity, { handsOnly = true }) ~= nil
    end

    function resolver:getIntactShield(entity, options)
        options = options or {}
        if not entity or not entity.inventory or not entity.inventory.getItems then
            return nil
        end

        local locations = options.handsOnly and { inventory.LOCATIONS.HANDS } or {
            inventory.LOCATIONS.HANDS,
            inventory.LOCATIONS.BELT,
            inventory.LOCATIONS.PACK,
        }

        for _, location in ipairs(locations) do
            for _, item in ipairs(entity.inventory:getItems(location) or {}) do
                if itemHasMarker(item, "shield") and not item.destroyed then
                    local durability = item.durability or 1
                    if (item.notches or 0) < durability then
                        return item, location
                    end
                end
            end
        end

        return nil
    end

    function resolver:entityHasMeleeWeapon(entity)
        local inv = entity and entity.inventory
        if not inv then
            return false
        end
        if inv.hasMeleeWeaponInHands then
            return inv:hasMeleeWeaponInHands() == true
        end

        for _, item in ipairs(inv.hands or {}) do
            if item.isMelee or (item.isWeapon and not item.isRanged) then
                return true
            end
        end
        return false
    end

    function resolver:entityLacksMeleeWeaponAndShield(entity)
        if not entity or not entity.inventory then
            return false
        end
        return not self:entityHasMeleeWeapon(entity) and not self:entityHasShield(entity)
    end

    function resolver:recoverDroppedItem(entity)
        if not entity or not entity.droppedItems or #entity.droppedItems == 0 then
            return nil, nil
        end

        local item = table.remove(entity.droppedItems)
        if entity.inventory and entity.inventory.addItem then
            local ok, err = entity.inventory:addItem(item, inventory.LOCATIONS.HANDS)
            if not ok then
                entity.droppedItems[#entity.droppedItems + 1] = item
                return nil, err or "hands_full"
            end
        end

        self.eventBus:emit(events.EVENTS.INVENTORY_CHANGED, {
            entity = entity,
            item = item,
            reason = "recover_dropped_item",
        })

        return item, nil
    end

    local function normalizeTotemTag(value)
        value = tostring(value or ""):lower()
        value = value:gsub("^%s+", ""):gsub("%s+$", "")
        value = value:gsub("[%s%-]+", "_")
        value = value:gsub("[^%w_]", "")
        return value
    end

    local function addTotemTag(tags, value)
        local tag = normalizeTotemTag(value)
        if tag ~= "" then
            tags[tag] = true
        end
    end

    local function collectTotemTags(tags, source)
        if type(source) == "table" then
            for _, value in ipairs(source) do
                addTotemTag(tags, value)
            end
            for key, value in pairs(source) do
                if type(key) ~= "number" and value then
                    addTotemTag(tags, key)
                end
            end
        else
            addTotemTag(tags, source)
        end
    end

    local function totemKnownForMatchesAction(totemForm, action)
        if not totemForm or not action then
            return false
        end
        if action.totemRelevant == true or action.totemActionKnown == true or action.totemKnownAction == true then
            return true
        end

        local known = totemForm.knownForSet or {}
        local actionTags = {}
        collectTotemTags(actionTags, action.totemTags or action.fateTags or action.actionTags or action.tags)
        collectTotemTags(actionTags, action.totemAction or action.activity or action.intent or action.context)

        for tag in pairs(actionTags) do
            if known[tag] then
                return true
            end
        end

        return false
    end

    function resolver:getTotemTestFateBonus(actor, action)
        local totemForm = actor and actor.totemForm
        if not totemForm or totemForm.active == false or (action and action.totemBonus == false) then
            return 0
        end
        if totemKnownForMatchesAction(totemForm, action) then
            return totemForm.testOfFateBonus or 5
        end
        return 0
    end

    local function isStealthTestAction(action, actionDef)
        action = action or {}
        if action.stealth == true or action.requiresStealth == true or action.stealthAction == true then
            return true
        end
        if actionDef and (actionDef.stealth == true or actionDef.requiresStealth == true) then
            return true
        end

        local tags = {}
        collectTotemTags(tags, action.context)
        collectTotemTags(tags, action.challengeContext)
        collectTotemTags(tags, action.testContext)
        collectTotemTags(tags, action.intent)
        collectTotemTags(tags, action.activity)
        collectTotemTags(tags, action.tags)
        collectTotemTags(tags, action.actionTags)
        collectTotemTags(tags, action.fateTags)

        return tags.stealth == true or tags.sneak == true or tags.sneaking == true or
            tags.hide == true or tags.hiding == true or tags.silent == true
    end

    function resolver:requestTestOfFate(action, actionDef, result)
        if action.actor and isStealthTestAction(action, actionDef) and
           (action.actor.stealthImpossible or hasAngelicChant(action.actor)) then
            result.success = false
            result.description = "Stealth is impossible."
            result.effects[#result.effects + 1] = "stealth_impossible"
            if action.actor.stealthImpossible then
                result.effects[#result.effects + 1] = "shame_bell_stealth_blocked"
            end
            if hasAngelicChant(action.actor) then
                result.effects[#result.effects + 1] = "angelic_chant_stealth_blocked"
            end
            action.result = result
            return result
        end

        local suitKey = actionDef and actionDef.suit or nil
        local mappedSuit = suitKey and actionSuitToCardSuit[suitKey] or nil
        local targetSuit = action.targetSuit or action.testSuit or mappedSuit
        local attribute = action.attribute or action.testAttribute or action.fateAttribute or
                          (actionDef and actionDef.attribute) or "pentacles"
        local totemBonus = self:getTotemTestFateBonus(action.actor, action)
        local favor = action.favor
        if hasBloodyTears(action.actor) and isVisionBasedAction(action, actionDef) then
            if favor == true then
                favor = nil
            else
                favor = false
            end
            result.effects[#result.effects + 1] = "bloody_tears_vision_disfavor"
        end
        local sizeFavor = self:getChangeSizeActionFavor(action.actor, M.ACTION_TYPES.TEST_FATE, action)
        if sizeFavor ~= nil then
            if favor == nil then
                favor = sizeFavor
            elseif favor ~= sizeFavor then
                favor = nil
            end
            if sizeFavor == true then
                result.effects[#result.effects + 1] = "change_size_action_favor"
            else
                result.effects[#result.effects + 1] = "change_size_action_disfavor"
            end
        end
        if self:getNymphDispositionInfluenceFavor(action.actor, action) then
            if favor == nil then
                favor = true
            elseif favor == false then
                favor = nil
            end
            result.effects[#result.effects + 1] = "nymph_beauty_disposition_favor"
        end
        if action.disfavor == true then
            favor = false
        end
        local spentResolveForFavor = false

        if action.spendResolveForFavor or action.resolveForFavor then
            local ok, reason = self:spendResolveForFavor(action.actor)
            if not ok then
                result.success = false
                result.description = "Cannot spend Resolve for favor: " .. (reason or "resolve unavailable") .. "."
                result.effects[#result.effects + 1] = "resolve_missing"
                action.result = result
                return result
            end

            spentResolveForFavor = true
            result.effects[#result.effects + 1] = "resolve_spent_for_favor"
            if favor == false then
                favor = nil
            else
                favor = true
            end
        end

        if totemBonus > 0 then
            result.effects[#result.effects + 1] = "totem_test_bonus"
        end

        self.eventBus:emit(events.EVENTS.REQUEST_TEST_OF_FATE, {
            entity = action.actor,
            attribute = attribute,
            targetSuit = targetSuit,
            favor = favor,
            attributeBonus = totemBonus > 0 and totemBonus or nil,
            totemBonus = totemBonus > 0 and totemBonus or nil,
            spentResolveForFavor = spentResolveForFavor,
            description = actionDef and actionDef.name or "Test of Fate",
            action = action,
            actionCard = action.card,
        })

        result.pendingTestOfFate = true
        result.description = "Test of Fate underway."
        action.result = result

        return result
    end

    function resolver:requestBidLore(action, actionDef, result)
        local controller = action.challengeController or self.challengeController
        local availableSubjects = {}
        local questionTypes = {}

        if self.bidLoreEngine then
            if self.bidLoreEngine.getAvailableSubjects then
                availableSubjects = self.bidLoreEngine:getAvailableSubjects({
                    actor = action.actor,
                    action = action,
                    challengeController = controller,
                    roomId = controller and controller.roomId or nil,
                })
            end
            if self.bidLoreEngine.getQuestionTypes then
                questionTypes = self.bidLoreEngine:getQuestionTypes()
            end
        end

        self.eventBus:emit(events.EVENTS.REQUEST_BID_LORE, {
            entity = action.actor,
            actor = action.actor,
            action = action,
            actionDef = actionDef,
            challengeController = controller,
            roomId = controller and controller.roomId or nil,
            availableSubjects = availableSubjects,
            questionTypes = questionTypes,
        })

        result.pendingBidLore = true
        result.description = "Bid Lore underway."
        action.result = result

        return result
    end

    function resolver:applyPreparedRoomSocialEffects(action, result, target)
        local manager = action and (action.roomManager or self.roomManager)
        if not manager or not manager.getRoom or not target then
            return 0
        end

        local roomId = action.roomId or action.currentRoomId or
            (target and target.location) or (action.actor and action.actor.location)
        if not roomId then
            return 0
        end

        local room = manager:getRoom(roomId)
        local socialEncounter = room and (room.socialEncounter or
            (manager.getSocialEncounter and manager:getSocialEncounter(roomId)))
        if not room or not socialEncounter then
            return 0
        end

        local preparedEffects = manager.getSocialPreparedEffects and
            manager:getSocialPreparedEffects(roomId) or socialEncounter.preparedEffects or {}
        local totalModifier = 0
        local applied = {}

        for _, record in ipairs(preparedEffects or {}) do
            if preparedSocialEffectMatches(room, socialEncounter, record, target) then
                if record.type == "social_favor" then
                    local modifier = tonumber(record.modifier) or 0
                    if modifier ~= 0 then
                        totalModifier = totalModifier + modifier
                        applied[#applied + 1] = record
                        result.effects[#result.effects + 1] = "room_social_feature_favor"
                    end
                elseif record.type == "disposition_shift" or record.type == "set_disposition" then
                    local targetKey = target.id or target.name or "target"
                    record.appliedTo = record.appliedTo or {}
                    if not record.appliedTo[targetKey] then
                        local oldDisposition = target.getDisposition and target:getDisposition() or target.disposition
                        local oldSeverity = target.getDispositionSeverity and target:getDispositionSeverity()
                            or target.dispositionSeverity
                            or 2
                        local newDisposition = record.disposition or "trust"
                        local newSeverity = record.severity or oldSeverity

                        if target.setDisposition then
                            target:setDisposition(newDisposition, newSeverity)
                        else
                            target.disposition = newDisposition
                            target.dispositionSeverity = newSeverity
                        end

                        if self.endCharmForDispositionChange then
                            self:endCharmForDispositionChange(
                                target,
                                oldDisposition,
                                newDisposition,
                                action,
                                oldSeverity,
                                newSeverity)
                        end

                        record.appliedTo[targetKey] = true
                        applied[#applied + 1] = record
                        result.effects[#result.effects + 1] = "room_social_feature_disposition"
                    end
                end
            end
        end

        if totalModifier ~= 0 then
            result.testValue = (result.testValue or 0) + totalModifier
            result.roomSocialModifier = (result.roomSocialModifier or 0) + totalModifier
        end
        if #applied > 0 then
            result.roomSocialPreparations = applied
        end

        return totalModifier
    end

    function resolver:applyRoomSocialEncounterOutcome(action, result)
        if not action or not result or not result.socialOutcome then
            return false
        end

        local manager = action.roomManager or self.roomManager
        if not manager or not manager.getRoom then
            return false
        end

        local target = action.target
        local roomId = action.roomId or action.currentRoomId or
            (target and target.location) or (action.actor and action.actor.location)
        if not roomId then
            return false
        end

        local room = manager:getRoom(roomId)
        local socialEncounter = room and (room.socialEncounter or
            (manager.getSocialEncounter and manager:getSocialEncounter(roomId)))
        if not room or not socialEncounter or socialEncounter.resolved then
            return false
        end

        if not socialTargetMatchesEncounter(room, socialEncounter, target) then
            return false
        end

        local outcomeKey = action.socialOutcomeKey or roomSocialOutcomeKey(result.socialOutcome)
        local outcome = outcomeKey and socialEncounter.outcomes and socialEncounter.outcomes[outcomeKey]
        if not outcome then
            return false
        end

        socialEncounter.resolved = true
        socialEncounter.resolvedOutcome = outcomeKey
        socialEncounter.resolvedBy = action.actor and action.actor.id or nil

        result.roomSocialEncounter = {
            roomId = roomId,
            outcome = outcomeKey,
            effect = outcome.effect,
            reward = outcome.reward,
            description = outcome.description,
        }
        result.effects[#result.effects + 1] = "room_social_encounter_resolved"
        result.effects[#result.effects + 1] = "room_social_" .. tostring(outcomeKey)
        if outcome.effect then
            result.effects[#result.effects + 1] = "room_social_" .. tostring(outcome.effect)
        end

        appendResultSentence(result, outcome.description)

        if outcome.effect == "reveal_secret_passage" then
            room.secretPassageRevealed = true
            room.revealedSecretPassage = true
            socialEncounter.secretPassageRevealed = true
            result.revealedSecretPassage = true
            result.effects[#result.effects + 1] = "room_social_secret_revealed"
        elseif outcome.effect == "guardian_retreats" then
            if target then
                target.conditions = target.conditions or {}
                target.conditions.fleeing = true
                target.retreated = true
            end
            result.guardianRetreats = true
        elseif outcome.effect == "combat_start" then
            if target then
                target.conditions = target.conditions or {}
                target.conditions.hostile = true
                target.socialCombatTriggered = true
            end
            room.socialCombatTriggered = true
            result.triggersCombat = true
        end

        if outcome.reward then
            result.rewardItemId = outcome.reward
            local rewardItem = inventory.createItemFromTemplate(outcome.reward)
            result.rewardItem = rewardItem
            if rewardItem and action.actor and action.actor.inventory and action.actor.inventory.addItem then
                local added, reason = action.actor.inventory:addItem(rewardItem, inventory.LOCATIONS.PACK)
                result.rewardGranted = added
                result.rewardLocation = added and inventory.LOCATIONS.PACK or nil
                result.rewardError = not added and reason or nil
                result.effects[#result.effects + 1] = added and "room_social_reward_granted" or "room_social_reward_pending"
            else
                result.effects[#result.effects + 1] = "room_social_reward_pending"
            end
        end

        if target then
            target.socialEncounterOutcome = outcomeKey
        end

        self.eventBus:emit(events.EVENTS.ROOM_SOCIAL_ENCOUNTER_RESOLVED, {
            roomId = roomId,
            target = target,
            targetId = target and target.id or nil,
            actor = action.actor,
            actorId = action.actor and action.actor.id or nil,
            outcome = outcomeKey,
            effect = outcome.effect,
            reward = outcome.reward,
            result = result,
        })

        return true
    end

    function resolver:spendResolveForFavor(actor)
        if not actor then
            return false, "missing_actor"
        end

        if actor.spendResolve then
            local ok, reason = actor:spendResolve(1)
            if ok then
                return true, nil
            end
            return false, reason or "not_enough_resolve"
        end

        if type(actor.resolve) == "table" then
            if (actor.resolve.current or 0) < 1 then
                return false, "not_enough_resolve"
            end
            actor.resolve.current = actor.resolve.current - 1
            return true, nil
        end

        if type(actor.resolve) == "number" then
            if actor.resolve < 1 then
                return false, "not_enough_resolve"
            end
            actor.resolve = actor.resolve - 1
            return true, nil
        end

        return false, "resolve_unavailable"
    end

    function resolver:spendLoremasterResolveForLore(actor)
        local canSpend, reason = self:canSpendLoremasterResolveForLore(actor)
        if not canSpend then
            return false, reason
        end
        return self:spendResolveForFavor(actor)
    end

    function resolver:entityInList(items, entity)
        if type(items) ~= "table" or not entity then
            return false
        end

        local entityId = entity.id
        for _, item in ipairs(items) do
            if item == entity or (entityId and item and item.id == entityId) then
                return true
            end
        end
        return false
    end

    function resolver:ensureSneakChallengeMembership(controller, actor)
        local added = {}
        if not controller or not actor then
            return added
        end

        controller.pcs = controller.pcs or {}
        if not self:entityInList(controller.pcs, actor) then
            controller.pcs[#controller.pcs + 1] = actor
            added.pcs = true
        end

        controller.allCombatants = controller.allCombatants or {}
        if not self:entityInList(controller.allCombatants, actor) then
            controller.allCombatants[#controller.allCombatants + 1] = actor
            added.allCombatants = true
        end

        return added
    end

    function resolver:resolveSneak(action, result)
        action = action or {}
        local actor = action.actor
        result.effects[#result.effects + 1] = "sneak"

        if not actor then
            result.reason = "missing_actor"
            result.description = "Sneak requires an actor."
            result.effects[#result.effects + 1] = "missing_actor"
            action.result = result
            return result
        end

        if not entityHasUsableTalent(actor, "sneak") then
            result.reason = "requires_sneak"
            result.description = "Sneak requires a usable Sneak talent."
            result.effects[#result.effects + 1] = "talent_missing_or_wounded"
            action.result = result
            return result
        end

        local mode = action.mode or action.sneakMode
        local wantsArrival = action.arrive == true or action.arriveFromSneak == true or
            action.sneakArrival == true or mode == "arrive" or mode == "arrival"

        if not wantsArrival then
            local state = actor.sneakState or {}
            state.active = true
            state.offStage = true
            state.location = firstNonNil(action.location, action.roomId, action.locationId, state.location)
            state.sceneId = firstNonNil(action.sceneId, action.scene, state.sceneId)
            state.tension = firstNonNil(action.tension, action.tensionActive, state.tension)
            if state.tension == nil then
                state.tension = true
            end

            actor.sneaking = true
            actor.offStage = true
            actor.sneakState = state

            result.success = true
            result.sneaking = true
            result.offStage = true
            result.sneakState = state
            result.effects[#result.effects + 1] = "sneak_off_stage"
            result.description = (actor.name or actor.id or "The adventurer") .. " goes sneaking off-stage."

            self.eventBus:emit("sneak_started", {
                actor = actor,
                action = action,
                state = state,
                result = result,
            })

            action.result = result
            return result
        end

        if action.plausible == false or action.arrivalPlausible == false then
            result.reason = "sneak_arrival_implausible"
            result.description = "Sneak arrival is not plausible from the declared position."
            result.effects[#result.effects + 1] = "sneak_arrival_implausible"
            action.result = result
            return result
        end

        local state = actor.sneakState
        local hasTrackedSneak = actor.sneaking == true or actor.offStage == true or
            (type(state) == "table" and state.active ~= false and state.offStage ~= false)
        if not hasTrackedSneak and action.allowUntrackedArrival ~= true then
            result.reason = "not_sneaking"
            result.description = "Sneak arrival requires the actor to be off-stage sneaking."
            result.effects[#result.effects + 1] = "sneak_not_off_stage"
            action.result = result
            return result
        end

        local freeRejoin = action.tensionEvaporated == true or action.tensionGone == true or action.tension == false
        if not freeRejoin then
            local spent, spendReason = self:spendResolveForFavor(actor)
            if not spent then
                result.reason = spendReason or "not_enough_resolve"
                result.description = "Cannot spend Resolve to arrive dramatically from Sneak."
                result.effects[#result.effects + 1] = "resolve_missing"
                action.result = result
                return result
            end
            result.resolveSpent = 1
            result.effects[#result.effects + 1] = "resolve_spent_for_sneak_arrival"
        end

        actor.sneaking = false
        actor.offStage = false
        if type(state) == "table" then
            state.active = false
            state.offStage = false
            state.arrived = true
        end

        result.success = true
        result.sneakArrival = true
        result.freeRejoin = freeRejoin

        local controller = action.challengeController or self.challengeController
        local challengeActive = controller and controller.isActive and controller:isActive()
        if freeRejoin then
            result.effects[#result.effects + 1] = "sneak_free_rejoin"
            result.description = (actor.name or actor.id or "The adventurer") ..
                " rejoins when the tension evaporates."
            self.eventBus:emit("sneak_rejoined", {
                actor = actor,
                action = action,
                result = result,
                free = true,
            })
        elseif challengeActive then
            result.challengeJoined = true
            result.challengeMembership = self:ensureSneakChallengeMembership(controller, actor)
            result.effects[#result.effects + 1] = "sneak_joined_challenge"
            result.description = (actor.name or actor.id or "The adventurer") ..
                " arrives dramatically and joins the Challenge flow."
            self.eventBus:emit("sneak_joined_challenge", {
                actor = actor,
                action = action,
                controller = controller,
                result = result,
            })
        else
            local ambush = {
                actor = actor,
                source = "sneak",
                location = action.location or action.roomId or (state and state.location),
                target = action.target,
                action = action,
            }
            actor.pendingSneakAmbush = ambush
            result.ambush = true
            result.pendingAmbush = ambush
            result.effects[#result.effects + 1] = "sneak_ambush"
            result.description = (actor.name or actor.id or "The adventurer") ..
                " arrives dramatically; the arrival counts as an ambush."
            self.eventBus:emit("sneak_ambush_arrival", {
                actor = actor,
                action = action,
                ambush = ambush,
                result = result,
            })
        end

        action.result = result
        return result
    end

    function resolver:spendResolveForTestFateFavor(actor)
        return self:spendResolveForFavor(actor)
    end

    function resolver:getUpMySleeveUses(actor)
        return actor and (actor.upMySleeveUses or actor.upMySleeveCrawlUses or 0) or 0
    end

    function resolver:normalizeUpMySleeveTemplateId(value)
        local normalized = normalizeTalentKey(value)
        if normalized == "" then
            return nil
        end
        return UP_MY_SLEEVE_TEMPLATE_ALIASES[normalized] or normalized
    end

    function resolver:createUpMySleeveItem(itemSpec)
        if type(itemSpec) == "string" then
            local templateId = self:normalizeUpMySleeveTemplateId(itemSpec)
            if templateId and item_templates.hasTemplate(templateId) then
                return inventory.createItemFromTemplate(templateId), templateId, nil
            end
            return nil, templateId, "unknown_item"
        end

        if type(itemSpec) ~= "table" then
            return nil, nil, "missing_item"
        end

        local templateId = itemSpec.templateId or itemSpec.itemTemplate
        if not templateId and not itemSpec.name then
            templateId = itemSpec.id
        end
        templateId = templateId and self:normalizeUpMySleeveTemplateId(templateId) or nil
        if templateId and item_templates.hasTemplate(templateId) then
            return inventory.createItemFromTemplate(templateId, itemSpec.overrides), templateId, nil
        end

        if itemSpec.name then
            return inventory.createItem(itemSpec), nil, nil
        end

        return nil, templateId, templateId and "unknown_item" or "missing_item"
    end

    function resolver:isUpMySleeveItemAllowed(item, itemSpec, templateId)
        if not item then
            return false, "missing_item"
        end
        if item.oversized or (item.size or 1) > 1 then
            return false, "not_one_slot"
        end

        local props = item.properties or {}
        if props.magical or props.artifact or props.relic or props.treasure or props.rare or item.rare then
            return false, "not_common"
        end

        if templateId then
            return UP_MY_SLEEVE_COMMON_TEMPLATES[templateId] == true, "not_common"
        end

        if type(itemSpec) == "table" and (itemSpec.common == true or props.common == true) then
            return true, nil
        end

        return false, "not_common"
    end

    function resolver:resolveUpMySleeve(actor, itemSpec, opts)
        opts = opts or {}
        local result = {
            success = false,
            actor = actor,
            effects = { "up_my_sleeve" },
        }

        if not entityHasUsableTalent(actor, "up_my_sleeve") then
            result.reason = "requires_up_my_sleeve"
            result.effects[#result.effects + 1] = "talent_missing_or_wounded"
            result.description = "Up My Sleeve requires a usable Up My Sleeve talent."
            return result
        end

        local maxUses = opts.maxUses or 2
        local uses = self:getUpMySleeveUses(actor)
        if uses >= maxUses then
            result.reason = "uses_exhausted"
            result.effects[#result.effects + 1] = "up_my_sleeve_uses_exhausted"
            result.description = "Both sleeves have already been used this Crawl."
            return result
        end

        local item, templateId, createReason = self:createUpMySleeveItem(itemSpec)
        if not item then
            result.reason = createReason or "missing_item"
            result.effects[#result.effects + 1] = "up_my_sleeve_item_invalid"
            result.description = "No valid common item was declared."
            return result
        end

        local allowed, itemReason = self:isUpMySleeveItemAllowed(item, itemSpec, templateId)
        if not allowed then
            result.reason = itemReason
            result.effects[#result.effects + 1] = "up_my_sleeve_item_invalid"
            result.description = "Up My Sleeve can only produce a common one-slot item."
            return result
        end

        local canCheckResolve = false
        local hasResolve = false
        if actor.hasResolve then
            canCheckResolve = true
            hasResolve = actor:hasResolve(1)
        elseif actor.resolve ~= nil then
            canCheckResolve = true
            hasResolve = getResolveAmount(actor) >= 1
        end
        if canCheckResolve and not hasResolve then
            result.reason = "not_enough_resolve"
            result.effects[#result.effects + 1] = "resolve_missing"
            result.description = "Cannot spend Resolve for Up My Sleeve."
            return result
        end

        actor.inventory = actor.inventory or inventory.createInventory()
        local location = opts.location or inventory.LOCATIONS.HANDS
        local added, addReason = actor.inventory:addItem(item, location)
        if not added then
            result.reason = addReason
            result.effects[#result.effects + 1] = "inventory_full"
            result.description = "No room to produce the item."
            return result
        end

        local spent, spendReason = self:spendResolveForFavor(actor)
        if not spent then
            actor.inventory:removeItem(item.id)
            result.reason = spendReason
            result.effects[#result.effects + 1] = "resolve_missing"
            result.description = "Cannot spend Resolve for Up My Sleeve."
            return result
        end

        actor.upMySleeveUses = uses + 1
        actor.upMySleeveCrawlUses = actor.upMySleeveUses

        item.properties = item.properties or {}
        item.properties.upMySleeve = true
        item.properties.producedBy = actor.id

        result.success = true
        result.item = item
        result.location = location
        result.templateId = templateId
        result.uses = actor.upMySleeveUses
        result.usesRemaining = math.max(0, maxUses - actor.upMySleeveUses)
        result.effects[#result.effects + 1] = "resolve_spent_for_up_my_sleeve"
        result.effects[#result.effects + 1] = "item_produced"
        result.description = (actor.name or actor.id or "An adventurer") ..
            " had " .. (item.name or "an item") .. " up their sleeve."

        self.eventBus:emit("up_my_sleeve_item_created", result)
        return result
    end

    function resolver:spendInspirationCard(actor, card, opts)
        opts = opts or {}
        if not actor or not card then
            return false, "missing_inspiration"
        end
        if actor.inspirationCard ~= card then
            return false, "inspiration_card_mismatch"
        end

        actor.inspirationCard = nil
        actor.spentInspirationCards = actor.spentInspirationCards or {}
        actor.spentInspirationCards[#actor.spentInspirationCards + 1] = card

        card.inspiration = card.inspiration or {}
        card.inspiration.spent = true
        card.inspiration.spentFor = opts.usage or opts.reason or "action"

        local discardDeck = opts.deck or opts.playerDeck or self.playerDeck
        if discardDeck and discardDeck.discard then
            discardDeck:discard(card)
        end

        local detail = {
            actor = actor,
            card = card,
            usage = card.inspiration.spentFor,
            discarded = discardDeck ~= nil,
        }
        self.eventBus:emit("inspiration_card_spent", detail)

        return true, detail
    end

    function resolver:spendActionInspirationCard(action, result)
        if not action or not action.actor or not action.card then
            return
        end
        if action.useInspirationCard ~= true and action.card ~= action.actor.inspirationCard then
            return
        end

        local ok, detailOrReason = self:spendInspirationCard(action.actor, action.card, {
            usage = action.inspirationUsage or "action",
            deck = action.inspirationDiscardDeck or action.playerDeck,
        })
        if ok then
            result.inspirationSpent = detailOrReason
            result.effects[#result.effects + 1] = "inspiration_spent"
        else
            result.inspirationSpendFailed = detailOrReason
        end
    end

    function resolver:wantsAreteAutoSuccess(action)
        return action and (action.useAreteAutoSuccess == true or
            action.spendResolveForArete == true or
            action.autoSucceedWithTalent == true)
    end

    function resolver:getAreteTestContext(action)
        local parts = {}
        local function add(value)
            if type(value) == "table" then
                for _, item in pairs(value) do
                    add(item)
                end
            elseif value ~= nil then
                parts[#parts + 1] = normalizeTalentKey(value)
            end
        end

        add(action.testContext)
        add(action.fateContext)
        add(action.context)
        add(action.intent)
        add(action.relatedTo)
        add(action.feat)
        add(action.description)
        add(action.tags)
        return table.concat(parts, "_")
    end

    function resolver:areteContextMatches(contextText, tags)
        for _, tag in ipairs(tags or {}) do
            if contextText:find(normalizeTalentKey(tag), 1, true) then
                return true
            end
        end
        return false
    end

    function resolver:getApplicableAreteAutoSuccessTalent(action)
        if not self:wantsAreteAutoSuccess(action) then
            return nil, "not_requested"
        end

        local actor = action.actor
        local requested = normalizeTalentKey(action.areteTalent or action.talentId or action.talent or "")
        local contextText = self:getAreteTestContext(action)
        local candidates = {
            {
                id = "iron_beards",
                missing = "Requires Iron Beards",
                mismatch = "Iron Beards requires a strength, endurance, or stubbornness Test of Fate",
                tags = { "strength", "endurance", "stubbornness", "stubborn", "force", "tough" },
            },
            {
                id = "underfoot",
                missing = "Requires Underfoot",
                mismatch = "Underfoot requires a quiet or subtle Test of Fate",
                tags = { "quiet", "subtle", "stealth", "sneak", "sneaking", "hide", "hidden", "silent" },
            },
            {
                id = "colossal",
                missing = "Requires Colossal",
                mismatch = "Colossal requires an impressive feat of strength or destruction",
                tags = { "colossal", "strength", "portcullis", "smash", "door", "supporting_column",
                    "destruction", "destroy", "battlefield", "feat_of_strength" },
            },
        }

        local requestedCandidate = nil
        for _, candidate in ipairs(candidates) do
            if requested == "" or requested == candidate.id then
                if requested == candidate.id then
                    requestedCandidate = candidate
                end
                if entityHasUsableTalent(actor, candidate.id) then
                    if self:areteContextMatches(contextText, candidate.tags) then
                        return candidate.id, nil
                    end
                    if requested == candidate.id then
                        return nil, candidate.mismatch
                    end
                elseif requested == candidate.id then
                    return nil, candidate.missing
                end
            end
        end

        if requestedCandidate then
            return nil, requestedCandidate.missing
        end
        return nil, "No applicable arête talent"
    end

    function resolver:resolveAreteAutoSuccessTestOfFate(action, actionDef, result)
        if not self:wantsAreteAutoSuccess(action) then
            return nil
        end

        local talentId, reason = self:getApplicableAreteAutoSuccessTalent(action)
        if not talentId then
            result.success = false
            result.testOfFate = true
            result.description = reason or "No applicable arête talent."
            result.effects[#result.effects + 1] = "arete_auto_success_blocked"
            action.result = result
            return result
        end

        local ok, resolveReason = self:spendResolveForFavor(action.actor)
        if not ok then
            result.success = false
            result.testOfFate = true
            result.description = "Cannot spend Resolve for arête talent: " ..
                (resolveReason or "resolve unavailable") .. "."
            result.effects[#result.effects + 1] = "resolve_missing"
            result.effects[#result.effects + 1] = "arete_auto_success_blocked"
            action.result = result
            return result
        end

        result.success = true
        result.testOfFate = true
        result.areteAutoSuccess = true
        result.areteTalent = talentId
        result.description = "Test of Fate automatically succeeds through " .. talentId .. "."
        result.effects[#result.effects + 1] = "test_fate_auto_success"
        result.effects[#result.effects + 1] = "arete_auto_success"
        result.effects[#result.effects + 1] = "arete_" .. talentId
        result.effects[#result.effects + 1] = "resolve_spent_for_arete"
        if talentId == "colossal" then
            result.battlefieldChanged = action.battlefieldChange or true
            result.effects[#result.effects + 1] = "colossal_battlefield_change"
        end

        self.eventBus:emit("test_of_fate_auto_success", {
            actor = action.actor,
            action = action,
            actionDef = actionDef,
            talentId = talentId,
            result = result,
        })

        action.result = result
        return result
    end

    function resolver:canApplyChallengeActionFavor(action, actionDef, actionType)
        if not action or not actionDef then
            return false
        end
        if not actionDef.challengeAction then
            return false
        end
        if actionDef.testOfFate or actionDef.autoSuccess then
            return false
        end
        if not actionDef.attribute then
            return false
        end
        if actionType == M.ACTION_TYPES.BANTER then
            return false
        end
        return true
    end

    function resolver:hasBrainfeverAttackFavor(actor, actionType)
        if not actor then
            return false
        end
        local normalizedType = self:normalizeActionType(actionType)
        if normalizedType ~= M.ACTION_TYPES.MELEE and normalizedType ~= M.ACTION_TYPES.MISSILE then
            return false
        end

        local conditions = actor.conditions or {}
        return actor.brainfever ~= nil or conditions.brainfever == true
    end

    function resolver:getActionChallengeRound(action)
        local controller = action and (action.challengeController or self.challengeController)
        return action and (action.currentRound or action.round) or
            controller and controller.currentRound or nil
    end

    function resolver:applyAmbusherDamageBonus(action, result)
        if not action or not result or result.ambusherDamageBonus then
            return false
        end
        if (result.damageDealt or 0) <= 0 then
            return false
        end
        if not entityHasUsableTalent(action.actor, "ambusher") then
            return false
        end
        if not self:isActiveChallengeAction(action) then
            return false
        end
        if self:getActionChallengeRound(action) ~= 1 then
            return false
        end

        local previousDamage = result.damageDealt or 0
        result.damageDealt = math.max(previousDamage, 2)
        result.ambusherDamageBonus = {
            previousDamage = previousDamage,
            damageDealt = result.damageDealt,
        }
        result.effects[#result.effects + 1] = "ambusher_first_round_damage"
        if result.damageDealt > previousDamage then
            result.effects[#result.effects + 1] = "damage_increased"
        end
        return true
    end

    function resolver:getMonsterHunterAttackFavor(action, actionType)
        local normalizedType = self:normalizeActionType(actionType)
        if normalizedType ~= M.ACTION_TYPES.MELEE and normalizedType ~= M.ACTION_TYPES.MISSILE then
            return nil
        end
        if not self:isActiveChallengeAction(action) then
            return nil
        end

        local targetTags = collectTargetHunterTags(action and action.target)
        for _, hunter in ipairs(collectHunterTalents(action and action.actor)) do
            for _, specializationTag in ipairs(hunter.specializationTags or {}) do
                if targetTags[specializationTag] then
                    return hunter
                end
                for targetTag in pairs(targetTags) do
                    if normalizedKeysMatch(targetTag, specializationTag) then
                        return hunter
                    end
                end
            end
        end

        return nil
    end

    local function isHarmfulChallengeAction(actionType)
        return actionType == M.ACTION_TYPES.MELEE or
            actionType == M.ACTION_TYPES.MISSILE or
            actionType == M.ACTION_TYPES.ROUGHHOUSE or
            actionType == M.ACTION_TYPES.TRIP or
            actionType == M.ACTION_TYPES.DISARM or
            actionType == M.ACTION_TYPES.DISPLACE or
            actionType == M.ACTION_TYPES.GRAPPLE
    end

    local function normalizeSizeValue(value)
        value = tostring(value or ""):lower()
        value = value:gsub("^%s+", ""):gsub("%s+$", "")
        value = value:gsub("[%s%-]+", "_")
        return value
    end

    local function getChangeSizeMode(action)
        action = action or {}
        local mode = normalizeSizeValue(action.changeSizeMode or action.sizeMode or action.targetSize or
            action.mode or action.intent)
        if mode == "grow" or mode == "growth" or mode == "large" or mode == "larger" or
           mode == "enlarge" or mode == "double" then
            return "grow"
        end
        if mode == "shrink" or mode == "small" or mode == "smaller" or mode == "reduce" or
           mode == "halve" or mode == "half" then
            return "shrink"
        end
        return nil
    end

    local function combineFavorState(current, incoming)
        if incoming == nil then
            return current
        end
        if current == incoming then
            return current
        end
        if current == nil then
            return incoming
        end
        return nil
    end

    function resolver:getChangeSizeActionFavor(actor, actionType, action)
        if not actor or not actor.changeSize or actor.changeSize.active == false then
            return nil
        end
        if actionType == M.ACTION_TYPES.MELEE or actionType == M.ACTION_TYPES.MISSILE then
            return nil
        end
        if actor.changeSize.testOfFateOnly and actionType ~= M.ACTION_TYPES.TEST_FATE then
            return nil
        end

        if action and (action.changeSizeAdvantage == true or action.sizeAdvantage == true) then
            return true
        end
        if action and (action.changeSizeDisadvantage == true or action.sizeDisadvantage == true) then
            return false
        end

        local mode = actor.changeSize.mode
        local context = normalizeSizeValue(action and (action.sizeContext or action.context or action.challengeContext))
        if context == "squeeze" or context == "sneak" or context == "stealth" or context == "hide" or
           context == "crawl" or context == "small_space" then
            return mode == "shrink" and true or false
        end
        if context == "strength" or context == "lift" or context == "force" or context == "contest" then
            return mode == "grow" and true or false
        end

        if actionType == M.ACTION_TYPES.ROUGHHOUSE or actionType == M.ACTION_TYPES.TRIP or
           actionType == M.ACTION_TYPES.DISARM or actionType == M.ACTION_TYPES.DISPLACE or
           actionType == M.ACTION_TYPES.GRAPPLE then
            return mode == "grow" and true or false
        end

        return nil
    end

    function resolver:getNymphDispositionInfluenceFavor(actor, action)
        local conditions = actor and actor.conditions or {}
        if not (conditions.nymph_beauty or conditions.disposition_influence_favor) then
            return nil
        end
        action = action or {}
        local intent = normalizeSizeValue(action.intent or action.socialIntent or action.context or
            action.challengeContext or action.testContext)
        local influenceDisposition = action.influenceDisposition == true or
            action.dispositionInfluence == true or action.favorablyInfluenceDisposition == true or
            action.improveDisposition == true or action.targetDisposition ~= nil or
            intent == "influence_disposition" or intent == "improve_disposition" or
            intent == "favorable_disposition" or intent == "parley"
        if not influenceDisposition then
            return nil
        end

        local target = action.target or action.socialTarget or action.creature
        local attracted = action.targetAttracted == true or action.creatureAttracted == true or
            action.attracted == true or (target and (target.attractedToActor == true or
            target.attractedToNymphBeauty == true or target.attracted == true or
            target.conditions and target.conditions.attracted == true))
        if not attracted then
            return nil
        end
        return true
    end

    function resolver:isEntityShrouded(entity)
        if not entity then
            return false
        end
        local conditions = entity.conditions or {}
        return entity.shroud ~= nil or conditions.shrouded == true or conditions.invisible == true
    end

    function resolver:canActorSeeShrouded(actor, target, action)
        if not self:isEntityShrouded(target) then
            return true
        end
        if actor == target then
            return true
        end
        action = action or {}
        if action.canSeeShrouded == true or action.magicSight == true or action.specialSenses == true then
            return true
        end
        if actor and (actor.canSeeShrouded == true or actor.magicSight == true or actor.specialSenses == true) then
            return true
        end
        if target and target.shroud then
            local visibleTo = target.shroud.visibleTo
            if visibleTo and actor then
                local key = actor.id or actor.name or tostring(actor)
                if visibleTo[actor] == true or visibleTo[key] == true then
                    return true
                end
            end
        end
        return false
    end

    function resolver:markShroudedMovement(target, opts)
        if not target or not target.shroud then
            return nil
        end
        opts = opts or {}
        target.shroud.moved = true
        target.shroud.vaguePresenceKnown = true
        target.shroud.lastMovementReason = opts.reason or "movement"
        target.shroud.lastMovementTurn = opts.turn
        return target.shroud
    end

    function resolver:maintainShroudForVisibleInteraction(actor, target, opts)
        opts = opts or {}
        if not target or not target.shroud or target.shroud.caster ~= actor then
            return {
                success = false,
                reason = "shroud_missing",
            }
        end
        if opts.visibleObject == false then
            return {
                success = true,
                shroud = target.shroud,
                resolveSpent = 0,
            }
        end
        if target.shroud.visibleObjectsEndEffect == true then
            local ended = clearJinnPotionShroud(target, "visible_object_interaction")
            return {
                success = false,
                reason = "visible_object_interaction",
                endedShroud = ended,
                resolveSpent = 0,
                effects = { "jinn_shroud_ended", "shroud_ended" },
            }
        end
        if opts.requiresResolve == false then
            return {
                success = true,
                shroud = target.shroud,
                resolveSpent = 0,
            }
        end

        local ok, reason = self:spendSpellResolve(actor, 1)
        if ok then
            target.shroud.maintenanceResolveSpent = (target.shroud.maintenanceResolveSpent or 0) + 1
            target.shroud.visibleInteractions = (target.shroud.visibleInteractions or 0) + 1
            return {
                success = true,
                shroud = target.shroud,
                resolveSpent = 1,
                effects = { "shroud_maintained" },
            }
        end

        local ended = self:endOngoingSpell(actor, { spellId = "shroud", target = target }, "shroud_maintenance_unpaid")
        return {
            success = false,
            reason = reason or "resolve_missing",
            endedSpell = ended,
            effects = { "shroud_ended" },
        }
    end

    function resolver:askObjectWithMimicPotion(actor, object, opts)
        opts = opts or {}
        local speech = actor and actor.objectSpeech
        if not speech or speech.active == false then
            return {
                success = false,
                reason = "object_speech_missing",
            }
        end
        if not isNonLivingObjectTarget(object) then
            return {
                success = false,
                reason = "object_target_required",
            }
        end

        local props = object.properties or {}
        local topic = tostring(opts.topic or opts.questionType or opts.question or "purpose"):lower()
        local answerType = "limited"
        local answer = opts.answer

        if not answer and (topic:find("purpose", 1, true) or topic:find("created", 1, true) or
           topic:find("task", 1, true)) then
            answerType = "created_purpose"
            answer = object.purpose or props.purpose or props.createdFor or props.createdToPerform or
                "This object knows the task it was created to perform."
        elseif not answer and (topic:find("history", 1, true) or topic:find("done", 1, true) or
           topic:find("past", 1, true) or topic:find("opened", 1, true) or topic:find("killed", 1, true)) then
            answerType = "object_history"
            answer = object.history or props.history or props.done or props.hasDone or
                "This object can describe what it has done."
        elseif not answer then
            answer = "The object does not know much about that."
        end

        local response = {
            success = true,
            actor = actor,
            object = object,
            answer = answer,
            answerType = answerType,
            objectSpeech = speech,
            realTimeMinutes = speech.realTimeMinutes,
            knowsCreatedPurpose = true,
            knowsOwnHistory = true,
            limitedOtherwise = true,
            gmBeerExtendsConversation = true,
        }
        actor.objectSpeechConversations = actor.objectSpeechConversations or {}
        actor.objectSpeechConversations[#actor.objectSpeechConversations + 1] = response
        return response
    end

    function resolver:applyChallengeActionFavor(action, result, actionDef, actionType)
        result.baseTestValue = result.testValue
        result.favor = nil
        result.favorModifier = 0
        result.spentResolveForFavor = false

        if not self:canApplyChallengeActionFavor(action, actionDef, actionType) then
            return true
        end

        local favor = nil
        if action.favor == true then
            favor = true
        elseif action.favor == false then
            favor = false
        end

        local actorConditions = action.actor and action.actor.conditions or {}
        local targetConditions = action.target and action.target.conditions or {}

        if actorConditions.exhausted then
            favor = combineFavorState(favor, false)
            result.effects[#result.effects + 1] = "exhausted_action_disfavor"
        end

        if actorConditions.blind or actorConditions.blinded then
            favor = combineFavorState(favor, false)
            result.effects[#result.effects + 1] = "blind_action_disfavor"
        end

        if hasBloodyTears(action.actor) then
            favor = combineFavorState(favor, false)
            result.effects[#result.effects + 1] = "bloody_tears_vision_disfavor"
        end

        if action.actor and action.actor.faceRatDiseaseWandsDisfavor and
           (actionType == M.ACTION_TYPES.BANTER or actionType == M.ACTION_TYPES.PARLEY or
            action.socialInfluence == true or action.influenceOthers == true) then
            favor = combineFavorState(favor, false)
            result.effects[#result.effects + 1] = "face_rat_disease_wands_disfavor"
        end

        if actionType == M.ACTION_TYPES.SPEAK_INCANTATION and
           (actorConditions.deaf or actorConditions.deafened) then
            favor = combineFavorState(favor, false)
            result.effects[#result.effects + 1] = "deafened_incantation_disfavor"
        end

        if isHarmfulChallengeAction(actionType) and (targetConditions.blind or targetConditions.blinded) then
            favor = combineFavorState(favor, true)
            result.effects[#result.effects + 1] = "blind_target_favor"
        end

        if isHarmfulChallengeAction(actionType) and self:entityLacksMeleeWeaponAndShield(action.target) then
            favor = combineFavorState(favor, true)
            result.effects[#result.effects + 1] = "unarmed_target_favor"
        end

        if actionType == M.ACTION_TYPES.MELEE and targetConditions.prone then
            favor = combineFavorState(favor, true)
            result.effects[#result.effects + 1] = "prone_target_melee_favor"
        elseif actionType == M.ACTION_TYPES.MISSILE and targetConditions.prone then
            favor = combineFavorState(favor, false)
            result.effects[#result.effects + 1] = "prone_target_missile_disfavor"
        end

        if isHarmfulChallengeAction(actionType) and self:isEntityShrouded(action.target) and
           not self:canActorSeeShrouded(action.actor, action.target, action) then
            local shroud = action.target and action.target.shroud
            local vaguePresenceKnown = action.shroudedPresenceKnown == true or action.vaguePresenceKnown == true or
                (shroud and shroud.vaguePresenceKnown == true)
            if not vaguePresenceKnown then
                result.success = false
                result.description = "Cannot deliberately target a Shrouded creature."
                result.effects[#result.effects + 1] = "shrouded_target_unseen"
                return false
            end
            if favor == true then
                favor = nil
            else
                favor = false
            end
            result.effects[#result.effects + 1] = "shrouded_target_disfavor"
        end

        if isHarmfulChallengeAction(actionType) and self:isEntityShrouded(action.actor) and action.target and
           not self:canActorSeeShrouded(action.target, action.actor, action) then
            if favor == false then
                favor = nil
            else
                favor = true
            end
            result.effects[#result.effects + 1] = "shrouded_harm_favor"
        end

        local sizeFavor = self:getChangeSizeActionFavor(action.actor, actionType, action)
        if sizeFavor ~= nil then
            favor = combineFavorState(favor, sizeFavor)
            if sizeFavor == true then
                result.effects[#result.effects + 1] = "change_size_action_favor"
            else
                result.effects[#result.effects + 1] = "change_size_action_disfavor"
            end
        end

        if self:hasBrainfeverAttackFavor(action.actor, actionType) then
            if favor == false then
                favor = nil
            else
                favor = true
            end
            result.effects[#result.effects + 1] = "brainfever_attack_favor"
        end

        local hunter = self:getMonsterHunterAttackFavor(action, actionType)
        if hunter then
            favor = combineFavorState(favor, true)
            result.monsterHunter = {
                talentId = hunter.talentId,
                foe = hunter.foe,
                specializationTags = hunter.specializationTags,
            }
            result.effects[#result.effects + 1] = "monster_hunter_attack_favor"
            result.effects[#result.effects + 1] = "hunter_attack_favor"
        end

        if action.actor and action.actor.nextActionFavor then
            favor = combineFavorState(favor, true)
            result.effects[#result.effects + 1] = "next_action_favor"
            if action.actor.nextActionFavorSource == "proud_and_ancient" then
                result.effects[#result.effects + 1] = "proud_and_ancient_favor"
            end
            result.nextActionFavorSource = action.actor.nextActionFavorSource
            action.actor.nextActionFavor = nil
            action.actor.nextActionFavorSource = nil
        end

        if action.disfavor == true then
            if favor == true then
                favor = nil
            else
                favor = false
            end
        end

        if action.spendResolveForFavor or action.resolveForFavor then
            local ok, reason = self:spendResolveForFavor(action.actor)
            if not ok then
                result.success = false
                result.description = "Cannot spend Resolve for favor: " .. (reason or "resolve unavailable") .. "."
                result.effects[#result.effects + 1] = "resolve_missing"
                return false
            end

            result.spentResolveForFavor = true
            result.effects[#result.effects + 1] = "resolve_spent_for_favor"
            if favor == false then
                favor = nil
            else
                favor = true
            end
        end

        if favor == true then
            result.favorModifier = 3
            result.effects[#result.effects + 1] = "action_favor"
        elseif favor == false then
            result.favorModifier = -3
            result.effects[#result.effects + 1] = "action_disfavor"
        end

        result.favor = favor
        result.modifier = (result.modifier or 0) + result.favorModifier
        result.testValue = result.cardValue + result.modifier

        return true
    end

    function resolver:resolveTestOfFateOutcome(action, testResult)
        local result = {
            success = testResult and testResult.success or false,
            isGreat = testResult and testResult.isGreat or false,
            damageDealt = 0,
            effects = {},
            description = "",
            testOfFate = true,
            testResult = testResult,
        }

        if result.success then
            result.description = "Test of Fate succeeded."
        else
            result.description = "Test of Fate failed."
        end

        action.result = result
        return result
    end

    function resolver:resolveBidLoreOutcome(action, bidLoreResult)
        local actor = action and action.actor
        local verdict = bidLoreResult and bidLoreResult.verdict or "rephrase_needed"
        local accepted = verdict == "accepted"
        local loreBidSpent = false
        local resolveSpentForLore = false
        local freeFollowUpUsed = false

        local result = {
            success = accepted,
            isGreat = false,
            damageDealt = 0,
            effects = { "lore_bid" },
            description = "",
            bidLore = bidLoreResult,
        }

        if accepted then
            if self:wantsFreeLoreFollowUp(action) then
                local ok, reason = self:canUseFreeLoreFollowUp(actor,
                    action and (action.previousLoreResult or action.previousBidLoreResult or action.previousBidLore))
                if ok then
                    freeFollowUpUsed = true
                    result.effects[#result.effects + 1] = "weird_wise_ancient_follow_up"
                    result.effects[#result.effects + 1] = "lore_follow_up_free"
                else
                    result.success = false
                    result.effects[#result.effects + 1] = "lore_follow_up_blocked"
                    result.description = loreFollowUpFailureText(reason) .. "."
                    self.eventBus:emit(events.EVENTS.BID_LORE_VERDICT, {
                        actor = actor,
                        action = action,
                        verdict = verdict,
                        loreSpend = false,
                        resolveSpend = false,
                        freeFollowUp = false,
                        lorePayment = "failed",
                        selection = bidLoreResult and bidLoreResult.selection or nil,
                        scoreBreakdown = bidLoreResult and bidLoreResult.scoreBreakdown or nil,
                    })
                    action.result = result
                    return result
                end
            elseif self:wantsResolveForLore(action) then
                local ok, reason = self:spendLoremasterResolveForLore(actor)
                if ok then
                    resolveSpentForLore = true
                    result.effects[#result.effects + 1] = "loremaster_resolve_spent"
                    result.effects[#result.effects + 1] = "resolve_spent_for_lore"
                else
                    result.success = false
                    result.effects[#result.effects + 1] = "resolve_missing"
                    result.description = "Cannot spend Resolve for lore: " .. loreResolveFailureText(reason) .. "."
                    self.eventBus:emit(events.EVENTS.BID_LORE_VERDICT, {
                        actor = actor,
                        action = action,
                        verdict = verdict,
                        loreSpend = false,
                        resolveSpend = false,
                        lorePayment = "failed",
                        selection = bidLoreResult and bidLoreResult.selection or nil,
                        scoreBreakdown = bidLoreResult and bidLoreResult.scoreBreakdown or nil,
                    })
                    action.result = result
                    return result
                end
            elseif actor then
                local current = actor.loreBids or 0
                actor.loreBids = math.max(0, current - 1)
                loreBidSpent = true
                result.effects[#result.effects + 1] = "lore_spent"
            end
            result.effects[#result.effects + 1] = "lore_accepted"
            if bidLoreResult and bidLoreResult.uncannyKnowledge then
                result.effects[#result.effects + 1] = "uncanny_knowledge_lore"
            end

            local response = bidLoreResult and bidLoreResult.response or {}
            local summary = response.summary or "Lore answer provided."
            local implication = response.implication
            result.description = "Bid Lore accepted: " .. summary
            if implication and implication ~= "" then
                result.description = result.description .. " " .. implication
            end
        elseif verdict == "rejected_subject_unavailable" then
            result.effects[#result.effects + 1] = "lore_rejected_subject"
            result.description = "Bid Lore rejected: " .. (bidLoreResult and bidLoreResult.reason or "Subject unavailable.")
        elseif verdict == "rejected_unknown_with_motif" then
            result.effects[#result.effects + 1] = "lore_rejected_motif"
            result.description = "Bid Lore rejected: " .. (bidLoreResult and bidLoreResult.reason or "Motif mismatch.")
        else
            result.effects[#result.effects + 1] = "lore_rephrase_needed"
            result.description = "Bid Lore needs rephrase: " .. (bidLoreResult and bidLoreResult.reason or "Refine the question.")
        end

        self.eventBus:emit(events.EVENTS.BID_LORE_VERDICT, {
            actor = actor,
            action = action,
            verdict = verdict,
            loreSpend = loreBidSpent,
            resolveSpend = resolveSpentForLore,
            freeFollowUp = freeFollowUpUsed,
            lorePayment = freeFollowUpUsed and "free_follow_up" or
                (resolveSpentForLore and "resolve" or (loreBidSpent and "lore_bid" or "none")),
            selection = bidLoreResult and bidLoreResult.selection or nil,
            scoreBreakdown = bidLoreResult and bidLoreResult.scoreBreakdown or nil,
        })

        action.result = result
        return result
    end

    function resolver:resolveCrawlBidLore(request)
        request = request or {}
        local actor = request.actor or request.entity
        local action = {
            actor = actor,
            type = M.ACTION_TYPES.BID_LORE,
            roomId = request.roomId,
            crawlBidLore = true,
            spendResolveForLore = request.spendResolveForLore == true or request.resolveForLore == true or
                request.useResolveForLore == true or request.spendResolveForBidLore == true,
        }

        if self:wantsResolveForLore(action) then
            local canSpendResolve, resolveReason = self:canSpendLoremasterResolveForLore(actor)
            if not canSpendResolve then
                return {
                    success = false,
                    crawlBidLore = true,
                    effects = { "lore_bid", "lore_unavailable", "resolve_missing" },
                    description = loreResolveFailureText(resolveReason),
                }
            end
        elseif actor and (actor.loreBids or 0) <= 0 then
            return {
                success = false,
                crawlBidLore = true,
                effects = { "lore_bid", "lore_unavailable" },
                description = "No lore bids remaining",
            }
        end

        if not self.bidLoreEngine then
            return {
                success = false,
                crawlBidLore = true,
                effects = { "lore_bid", "lore_unavailable" },
                description = "No lore engine available.",
            }
        end

        local subjectId = request.subjectId
        local availableSet = {}
        local availableSubjects = self.bidLoreEngine:getAvailableSubjects({
            actor = actor,
            roomId = request.roomId,
            challengeController = request.challengeController,
            action = request,
        })
        for _, subject in ipairs(availableSubjects or {}) do
            availableSet[subject.id] = true
        end

        local bidLoreResult
        if subjectId and not availableSet[subjectId] then
            bidLoreResult = {
                verdict = "rejected_subject_unavailable",
                reason = "That subject is not currently available.",
                loreSpend = false,
                suggestedQuestionTypes = {},
                scoreBreakdown = {},
            }
        else
            bidLoreResult = self.bidLoreEngine:adjudicate({
                actor = actor,
                party = request.party or request.guild or (self.worldState and self.worldState.guild),
                roomId = request.roomId,
                subjectId = subjectId,
                questionType = request.questionType,
                motif = request.motif,
                focus = request.focus,
                targetNpcId = request.targetNpcId,
                targetNpcBlueprintId = request.targetNpcBlueprintId,
            })
        end

        bidLoreResult.selection = bidLoreResult.selection or {
            subjectId = subjectId,
            questionType = request.questionType,
            motif = request.motif,
            focus = request.focus,
            targetNpcId = request.targetNpcId,
            targetNpcBlueprintId = request.targetNpcBlueprintId,
        }

        local result = self:resolveBidLoreOutcome(action, bidLoreResult)
        result.crawlBidLore = true
        result.challengeAction = false
        result.cardCost = false
        result.availableSubjects = availableSubjects
        result.effects[#result.effects + 1] = "crawl_lore_bid"

        return result
    end

    function resolver:resolveBidLoreFollowUp(request)
        request = request or {}
        local actor = request.actor or request.entity
        local previousResult = request.previousResult or request.previousLoreResult or
            request.previousBidLoreResult or request.previousBidLore

        local canFollowUp, followUpReason = self:canUseFreeLoreFollowUp(actor, previousResult)
        if not canFollowUp then
            return {
                success = false,
                freeLoreFollowUp = true,
                effects = { "lore_bid", "lore_follow_up_blocked" },
                description = loreFollowUpFailureText(followUpReason),
            }
        end

        if not self.bidLoreEngine then
            return {
                success = false,
                freeLoreFollowUp = true,
                effects = { "lore_bid", "lore_unavailable" },
                description = "No lore engine available.",
            }
        end

        local subjectId = request.subjectId
        local availableSet = {}
        local availableSubjects = self.bidLoreEngine:getAvailableSubjects({
            actor = actor,
            roomId = request.roomId,
            challengeController = request.challengeController,
            action = request,
        })
        for _, subject in ipairs(availableSubjects or {}) do
            availableSet[subject.id] = true
        end

        local bidLoreResult
        if subjectId and not availableSet[subjectId] then
            bidLoreResult = {
                verdict = "rejected_subject_unavailable",
                reason = "That subject is not currently available.",
                loreSpend = false,
                suggestedQuestionTypes = {},
                scoreBreakdown = {},
            }
        else
            bidLoreResult = self.bidLoreEngine:adjudicate({
                actor = actor,
                party = request.party or request.guild or (self.worldState and self.worldState.guild),
                roomId = request.roomId,
                subjectId = subjectId,
                questionType = request.questionType,
                motif = request.motif,
                focus = request.focus,
                targetNpcId = request.targetNpcId,
                targetNpcBlueprintId = request.targetNpcBlueprintId,
            })
        end

        bidLoreResult.selection = bidLoreResult.selection or {
            subjectId = subjectId,
            questionType = request.questionType,
            motif = request.motif,
            focus = request.focus,
            targetNpcId = request.targetNpcId,
            targetNpcBlueprintId = request.targetNpcBlueprintId,
        }

        local action = {
            actor = actor,
            type = M.ACTION_TYPES.BID_LORE,
            roomId = request.roomId,
            freeLoreFollowUp = true,
            previousLoreResult = previousResult,
        }
        local result = self:resolveBidLoreOutcome(action, bidLoreResult)
        result.freeLoreFollowUp = true
        result.challengeAction = false
        result.cardCost = false
        result.availableSubjects = availableSubjects
        result.effects[#result.effects + 1] = "lore_follow_up"

        return result
    end

    function resolver:getConArtistPreferenceList(target, preference)
        local normalized = normalizeSocialTag(preference or "likes")
        local social = target and target.social or {}
        local wantsDislike = normalized == "dislikes" or normalized == "dislike" or
            normalized == "hates" or normalized == "hate"

        if wantsDislike then
            return social.dislikes or social.hates or target.dislikes or target.hates, "dislikes", "hates"
        end

        return social.likes or social.wants or target.likes or target.wants, "likes", "wants"
    end

    function resolver:resolveConArtistLore(request)
        request = request or {}
        local actor = request.actor or request.entity
        local target = request.target or request.npc

        if not entityHasUsableTalent(actor, "con_artist") then
            return {
                success = false,
                conArtistLore = true,
                effects = { "lore_bid", "con_artist_blocked" },
                description = "Requires Con Artist to reveal likes or dislikes.",
            }
        end

        local observed = request.observed == true or request.talked == true or request.talkedTo == true or
            request.conversed == true or request.observedConversation == true
        if not observed then
            return {
                success = false,
                conArtistLore = true,
                effects = { "lore_bid", "con_artist_observation_required" },
                description = "Con Artist requires a few minutes observing or talking to the target.",
            }
        end

        local action = {
            actor = actor,
            type = M.ACTION_TYPES.BID_LORE,
            conArtistLore = true,
            spendResolveForLore = request.spendResolveForLore == true or request.resolveForLore == true or
                request.useResolveForLore == true or request.spendResolveForBidLore == true,
        }

        if self:wantsResolveForLore(action) then
            local canSpendResolve, resolveReason = self:canSpendLoremasterResolveForLore(actor)
            if not canSpendResolve then
                return {
                    success = false,
                    conArtistLore = true,
                    effects = { "lore_bid", "lore_unavailable", "resolve_missing" },
                    description = loreResolveFailureText(resolveReason),
                }
            end
        elseif actor and (actor.loreBids or 0) <= 0 then
            return {
                success = false,
                conArtistLore = true,
                effects = { "lore_bid", "lore_unavailable" },
                description = "No lore bids remaining",
            }
        end

        local preferences, kind, discovery = self:getConArtistPreferenceList(target, request.preference or request.choice)
        if type(preferences) ~= "table" or #preferences == 0 then
            local unavailable = self:resolveBidLoreOutcome(action, {
                verdict = "rephrase_needed",
                reason = "No authored " .. tostring(kind or "preferences") .. " are known for this target.",
                loreSpend = false,
                suggestedQuestionTypes = {},
                scoreBreakdown = {},
                selection = {
                    talent = "con_artist",
                    preference = kind,
                    targetId = target and target.id or nil,
                },
            })
            unavailable.conArtistLore = true
            unavailable.effects[#unavailable.effects + 1] = "con_artist_lore_unavailable"
            return unavailable
        end

        local targetName = target and (target.name or target.id) or "The target"
        local revealed = preferences[request.index or 1] or preferences[1]
        local phrase = kind == "dislikes" and "reacts poorly to" or "responds well to"
        local bidLoreResult = {
            verdict = "accepted",
            reason = "Con Artist reveals a social preference.",
            loreSpend = true,
            conArtistLore = true,
            response = {
                summary = string.format("%s %s %s.", targetName, phrase, tostring(revealed)),
                details = { tostring(revealed) },
                implication = kind == "dislikes" and
                    "Avoid that approach or use it only to provoke." or
                    "Use that approach to improve the conversation.",
                sourceRefs = { "talent:con_artist" },
            },
            scoreBreakdown = {
                talent = "con_artist",
            },
            selection = {
                talent = "con_artist",
                preference = kind,
                targetId = target and target.id or nil,
            },
        }

        local result = self:resolveBidLoreOutcome(action, bidLoreResult)
        result.conArtistLore = true
        result.conArtistPreference = {
            kind = kind,
            value = revealed,
            targetId = target and target.id or nil,
        }
        result.effects[#result.effects + 1] = "con_artist_lore"
        result.effects[#result.effects + 1] = "con_artist_" .. tostring(kind) .. "_revealed"

        if target then
            if kind == "dislikes" then
                target.hates = target.hates or preferences
            else
                target.wants = target.wants or preferences
            end
            self.eventBus:emit("social_discovery", {
                target = target,
                targetId = target.id,
                discoveries = kind == "dislikes" and { "hates", "dislikes" } or { "wants", "likes" },
                source = "con_artist",
                preference = result.conArtistPreference,
            })
        end

        return result
    end

    function resolver:resolveForetellLore(request)
        request = request or {}
        local actor = request.actor or request.entity

        if not entityHasUsableTalent(actor, "foretell") then
            return {
                success = false,
                foretellLore = true,
                effects = { "lore_bid", "foretell_blocked" },
                description = "Requires Foretell to ask a prophetic yes/no lore question.",
            }
        end

        local ifAction = request.ifAction or request.actionDescription or request.doing or request.x
        local willOutcome = request.willOutcome or request.outcome or request.y
        if not ifAction or ifAction == "" or not willOutcome or willOutcome == "" then
            return {
                success = false,
                foretellLore = true,
                effects = { "lore_bid", "foretell_rephrase_needed" },
                description = "Foretell needs an 'If I do X, will Y happen?' question.",
            }
        end

        local action = {
            actor = actor,
            type = M.ACTION_TYPES.BID_LORE,
            foretellLore = true,
            spendResolveForLore = request.spendResolveForLore == true or request.resolveForLore == true or
                request.useResolveForLore == true or request.spendResolveForBidLore == true,
        }

        if self:wantsResolveForLore(action) then
            local canSpendResolve, resolveReason = self:canSpendLoremasterResolveForLore(actor)
            if not canSpendResolve then
                return {
                    success = false,
                    foretellLore = true,
                    effects = { "lore_bid", "lore_unavailable", "resolve_missing" },
                    description = loreResolveFailureText(resolveReason),
                }
            end
        elseif actor and (actor.loreBids or 0) <= 0 then
            return {
                success = false,
                foretellLore = true,
                effects = { "lore_bid", "lore_unavailable" },
                description = "No lore bids remaining",
            }
        end

        local prediction = normalizeForetellPrediction(firstNonNil(
            request.prediction,
            request.answer,
            request.willHappen,
            request.happens
        ))

        if prediction == nil then
            local noHunch = self:resolveBidLoreOutcome(action, {
                verdict = "rephrase_needed",
                reason = "No new prophetic hunch is available for that moment.",
                loreSpend = false,
                suggestedQuestionTypes = {},
                scoreBreakdown = {},
                selection = {
                    talent = "foretell",
                    ifAction = ifAction,
                    willOutcome = willOutcome,
                },
            })
            noHunch.foretellLore = true
            noHunch.effects[#noHunch.effects + 1] = "foretell_no_new_information"
            return noHunch
        end

        local answerWord = prediction and "Yes" or "No"
        local bidLoreResult = {
            verdict = "accepted",
            reason = "Foretell supplies a prophetic hunch.",
            loreSpend = true,
            foretellLore = true,
            response = {
                summary = string.format("%s. If you %s, %s %s happen.",
                    answerWord,
                    tostring(ifAction),
                    tostring(willOutcome),
                    prediction and "will" or "will not"),
                details = {
                    string.format("Hunch: %s.", answerWord),
                    "This prophetic sense lasts only a moment.",
                },
                implication = "Act on it now or let the moment pass.",
                sourceRefs = { "talent:foretell" },
            },
            scoreBreakdown = {
                talent = "foretell",
            },
            selection = {
                talent = "foretell",
                ifAction = ifAction,
                willOutcome = willOutcome,
            },
        }

        local result = self:resolveBidLoreOutcome(action, bidLoreResult)
        result.foretellLore = true
        result.foretell = {
            ifAction = ifAction,
            willOutcome = willOutcome,
            prediction = prediction,
            answer = answerWord,
            expires = "momentary",
        }
        result.effects[#result.effects + 1] = "foretell_lore"
        result.effects[#result.effects + 1] = "foretell_momentary"
        result.effects[#result.effects + 1] = prediction and "foretell_yes" or "foretell_no"
        if actor then
            actor.lastForetell = result.foretell
        end

        return result
    end

    local function normalizeDefenseChoice(value)
        if value == true then
            return "dodge"
        end
        if type(value) ~= "string" then
            return nil
        end

        local normalized = value:lower():gsub("%s+", "_")
        if normalized == "dodge" or normalized == "riposte" then
            return normalized
        end
        return nil
    end

    function resolver:getGuardianAngelDefenseType(action, target)
        action = action or {}
        local angel = target and target.guardianAngel
        local choice = action.guardianAngelDefenseType or action.useGuardianAngelAs or action.guardianAngelUse
        if not choice and angel and angel.autoUse then
            choice = angel.defenseType or angel.autoUse
        end
        return normalizeDefenseChoice(choice)
    end

    function resolver:consumeGuardianAngelDefense(target, defenseType)
        defenseType = normalizeDefenseChoice(defenseType)
        local angel = target and target.guardianAngel
        if not target or not angel or angel.used or not defenseType then
            return nil
        end

        angel.used = true
        angel.usedAs = defenseType
        target.guardianAngel = nil
        target.guardianAngelCard = nil
        if target.conditions then
            target.conditions.guardianAngel = false
        end

        target.usedGuardianAngels = target.usedGuardianAngels or {}
        target.usedGuardianAngels[#target.usedGuardianAngels + 1] = angel

        self.eventBus:emit("guardian_angel_used", {
            target = target,
            angel = angel,
            defenseType = defenseType,
        })

        return {
            type = defenseType,
            card = angel.card,
            value = angel.value or (angel.card and angel.card.value) or 0,
            guardianAngel = angel,
            source = "guardian_angel",
        }
    end

    function resolver:isDefeatedForDefense(entity)
        return entity and entity.conditions and (entity.conditions.dead or entity.conditions.deaths_door)
    end

    function resolver:getDefenseCandidates(action)
        if action and type(action.allEntities) == "table" then
            return action.allEntities
        end

        local controller = action and action.challengeController or self.challengeController
        if controller and type(controller.allCombatants) == "table" then
            return controller.allCombatants
        end

        return {}
    end

    function resolver:consumeAllyDefense(action, target)
        if not target then
            return nil
        end

        for _, candidate in ipairs(self:getDefenseCandidates(action)) do
            if candidate ~= target and candidate.isPC == target.isPC and
                candidate.zone == target.zone and
                not self:isDefeatedForDefense(candidate) and
                candidate.hasDefense and candidate:hasDefense() and candidate.consumeDefense then
                local defense = candidate:consumeDefense()
                if defense then
                    defense.source = "ally"
                    defense.defender = candidate
                    defense.protectedTarget = target
                    return defense
                end
            end
        end

        return nil
    end

    function resolver:consumeIncomingDefense(action, target)
        if not target then
            return nil
        end

        local guardianType = self:getGuardianAngelDefenseType(action, target)
        local pending = nil
        if target.hasDefense and target:hasDefense() then
            pending = target:getDefense()
        end

        if guardianType then
            local angelDefense = self:consumeGuardianAngelDefense(target, guardianType)
            if angelDefense then
                if pending and pending.type == guardianType then
                    local prepared = target:consumeDefense()
                    angelDefense.preparedDefense = prepared
                    angelDefense.value = (angelDefense.value or 0) + (prepared and prepared.value or 0)
                    angelDefense.cards = { prepared and prepared.card, angelDefense.card }
                    angelDefense.combined = true
                end
                return angelDefense
            end
        end

        if pending and target.consumeDefense then
            return target:consumeDefense()
        end

        local allyDefense = self:consumeAllyDefense(action, target)
        if allyDefense then
            return allyDefense
        end

        return nil
    end

    function resolver:resolveInitiativeContest(action, result, options)
        options = options or {}
        local target = action.target

        if not target then
            result.success = false
            result.description = "No target!"
            return { success = false }
        end

        local giantsStrengthContest = self:resolveGiantsStrengthContest(action, result)
        if giantsStrengthContest then
            return giantsStrengthContest
        end

        local attackValue = result.testValue
        local baseInitiative = self:getTargetInitiative(target, action) or result.difficulty
        local tieWins = options.tieWins or false
        local considerShield = options.considerShield or false
        local defenderHasShield = considerShield and self:entityHasShield(target) or false

        local riposteTriggered = false
        local riposteDefense = nil

        local defense = self:consumeIncomingDefense(action, target)
        if defense then
            if defense.guardianAngel then
                result.effects[#result.effects + 1] = "guardian_angel_used"
            end
            if defense.source == "ally" then
                result.effects[#result.effects + 1] = "ally_defense_used"
            end
            if defense.type == "dodge" then
                local dodgeValue = defense.value or 0
                local newInitiative = baseInitiative + dodgeValue
                result.effects[#result.effects + 1] = "dodge_used"

                if newInitiative > attackValue then
                    result.success = false
                    result.description = "Dodged! "
                    result.effects[#result.effects + 1] = "dodged"
                    return {
                        success = false,
                        dodged = true,
                        attackValue = attackValue,
                        baseInitiative = baseInitiative,
                    }
                else
                    result.effects[#result.effects + 1] = "dodge_failed"
                end
            elseif defense.type == "riposte" then
                riposteTriggered = true
                riposteDefense = defense
                result.effects[#result.effects + 1] = "riposte_ready"
            end
        end

        result.success = (attackValue > baseInitiative) or
                         (tieWins and attackValue == baseInitiative and not defenderHasShield)
        result.difficulty = baseInitiative

        return {
            success = result.success,
            attackValue = attackValue,
            baseInitiative = baseInitiative,
            riposteTriggered = riposteTriggered,
            riposteDefense = riposteDefense,
        }
    end

    function resolver:resolveGiantsStrengthContest(action, result)
        local actor = action and action.actor
        local target = action and action.target
        if not actor or not target then
            return nil
        end
        if not (entityHasUsableTalent(actor, "giants_strength") or entityHasUsableTalent(actor, "giant_strength")) then
            return nil
        end
        if not actionHasRawStrengthContext(action) then
            return nil
        end
        if not entityIsNonTrollKin(action, target) then
            return nil
        end

        local baseInitiative = self:getTargetInitiative(target, action) or result.difficulty
        result.success = true
        result.difficulty = baseInitiative
        result.giantsStrengthAutoWin = true
        result.effects[#result.effects + 1] = "giants_strength_auto_win"
        result.effects[#result.effects + 1] = "talent_giants_strength"

        self.eventBus:emit("giants_strength_contest_won", {
            actor = actor,
            target = target,
            action = action,
        })

        return {
            success = true,
            giantsStrength = true,
            attackValue = result.testValue,
            baseInitiative = baseInitiative,
            riposteTriggered = false,
            riposteDefense = nil,
        }
    end

    function resolver:getActionRound(action)
        if action and action.round then
            return action.round
        end
        local controller = (action and action.challengeController) or self.challengeController
        return controller and controller.currentRound or nil
    end

    function resolver:markPetrifiedByCockatriceGaze(target, action)
        target.conditions = target.conditions or {}
        target.conditions.petrified = true
        target.conditions.petrification = true
        target.petrified = true
        target.curseOfPetrification = true
        target.petrificationCurse = true
        target.material = "stone"

        target.nonRecoverableConditions = target.nonRecoverableConditions or {}
        target.nonRecoverableConditions.petrified = "cockatrice_gaze"
        target.nonRecoverableConditions.petrification = "cockatrice_gaze"

        local source = action and action.actor
        local malediction = {
            active = true,
            curseId = "petrification",
            curseName = "Petrification",
            petrification = true,
            source = "cockatrice_gaze",
            sourceId = source and source.id or nil,
            sourceName = source and source.name or nil,
            curse = {
                id = "petrification",
                name = "Petrification",
            },
        }
        target.petrificationMalediction = malediction
        target.maledictions = target.maledictions or {}
        target.maledictions.petrification = malediction
        if type(target.malediction) ~= "table" or not target.malediction.active or
           target.malediction.curseId == "petrification" or
           (target.malediction.curse and target.malediction.curse.id == "petrification") then
            target.malediction = malediction
        end

        if target.cockatriceGazeRooted or target.rootedBy == "cockatrice_gaze" then
            target.conditions.rooted = false
            target.cockatriceGazeRooted = false
            if target.rootedBy == "cockatrice_gaze" then
                target.rootedBy = nil
            end
        end
    end

    function resolver:resolveCreatureGaze(action, result)
        result.effects = result.effects or {}
        action = action or {}
        local actor = action.actor
        local target = action.target

        if not actor then
            result.success = false
            result.description = "No actor for creature gaze."
            result.effects[#result.effects + 1] = "missing_actor"
            return result
        end
        if not target then
            result.success = false
            result.description = "No target for creature gaze."
            result.effects[#result.effects + 1] = "missing_target"
            return result
        end

        local gaze = action.gaze or (actor.cockatrice and actor.cockatrice.gaze)
        local isCockatrice = action.type == M.ACTION_TYPES.COCKATRICE_GAZE or
            entityHasNormalizedTag(actor, "cockatrice") or (actor.cockatrice and actor.cockatrice.gaze)
        if not isCockatrice or not gaze then
            result.success = false
            result.description = "Creature gaze is not defined."
            result.effects[#result.effects + 1] = "creature_gaze_missing"
            return result
        end

        local round = self:getActionRound(action)
        if gaze.oncePerRound and round and actor.cockatriceGazeUsedRound == round then
            result.success = false
            result.description = "Cockatrice gaze already used this round."
            result.effects[#result.effects + 1] = "cockatrice_gaze_round_spent"
            return result
        end
        if gaze.oncePerRound and round then
            actor.cockatriceGazeUsedRound = round
        end

        result.success = true
        result.automatic = true
        result.cardValue = 0
        result.testValue = 0
        result.difficulty = 0
        result.gaze = gaze
        result.effects[#result.effects + 1] = "creature_gaze"
        result.effects[#result.effects + 1] = "cockatrice_gaze"

        if action.reflectedByMirror or action.mirrorReflection then
            result.effects[#result.effects + 1] = "cockatrice_gaze_not_reflected_by_mirror"
        end

        target.conditions = target.conditions or {}
        if target.conditions.rooted then
            self:markPetrifiedByCockatriceGaze(target, action)
            result.effects[#result.effects + 1] = "cockatrice_gaze_petrified"
            result.effects[#result.effects + 1] = "petrification_curse"
            result.effects[#result.effects + 1] = "condition_petrified"
            result.description = (target.name or "Target") .. " is turned to stone by the Cockatrice's gaze."
        else
            self:applyRooted(target, { action = action, reason = "cockatrice_gaze" })
            target.cockatriceGazeRooted = true
            target.cockatriceGazeSource = actor.id or actor.name
            target.cockatriceGazeRound = round
            target.rootedBy = "cockatrice_gaze"
            result.effects[#result.effects + 1] = "cockatrice_gaze_rooted"
            result.effects[#result.effects + 1] = "rooted"
            result.description = (target.name or "Target") .. " is Rooted by the Cockatrice's gaze."
        end

        self.eventBus:emit("creature_gaze_resolved", {
            actor = actor,
            target = target,
            action = action,
            result = result,
        })

        action.result = result
        return result
    end

    function resolver:requiresGreaterDoomForGriffinGrab(action)
        if not action then
            return true
        end
        local doom = action.greaterDoom or action.doom
        local effect = doom and doom.effect
        if effect and effect.type == "roughhouse_grab" then
            return false
        end
        return not (action.greaterDoomCard or action.discardedGreaterDoom or action.useGreaterDoom == true or
            action.griffinGrabGreaterDoom == true)
    end

    function resolver:isGriffinGrabRoughhouse(action, effect)
        if effect == "grab" or effect == "griffin_grab" then
            return true
        end
        if action and (action.griffinGrab == true or action.grab == true) then
            return true
        end
        local doom = action and (action.greaterDoom or action.doom)
        local doomEffect = doom and doom.effect
        return doomEffect and doomEffect.type == "roughhouse_grab"
    end

    function resolver:isBadLittleHandsRoughhouse(action, effect)
        if effect ~= "steal_belt_item" then
            return false
        end
        if not action then
            return false
        end
        if action.badLittleHands == true or action.stealBeltItem == true then
            return true
        end

        local doom = action.lesserDoom or action.doom
        local doomEffect = doom and doom.effect
        if doomEffect and doomEffect.type == "roughhouse_steal_belt_item" then
            return true
        end

        return entityHasNormalizedTag(action.actor, "face_rat")
    end

    function resolver:getBadLittleHandsTargetItem(action)
        local target = action and action.target
        local inv = target and target.inventory
        if not inv or not inv.getItems then
            return nil, nil, "missing_inventory"
        end

        if action.itemId and inv.findItem then
            local item, location = inv:findItem(action.itemId)
            if item and location == inventory.LOCATIONS.BELT then
                return item, location, nil
            end
            return nil, location, "selected_item_not_on_belt"
        end

        if action.item and action.item.id and inv.findItem then
            local item, location = inv:findItem(action.item.id)
            if item and location == inventory.LOCATIONS.BELT then
                return item, location, nil
            end
            return nil, location, "selected_item_not_on_belt"
        end

        local beltItems = inv:getItems(inventory.LOCATIONS.BELT) or {}
        return beltItems[1], inventory.LOCATIONS.BELT, nil
    end

    function resolver:recordBadLittleHandsItem(faceRat, owner, item, location, action)
        faceRat.badLittleHands = faceRat.badLittleHands or {}
        faceRat.stolenItems = faceRat.stolenItems or {}

        local record = {
            item = item,
            from = owner,
            fromId = owner and owner.id or nil,
            fromName = owner and owner.name or nil,
            location = location or inventory.LOCATIONS.BELT,
            retrieveBy = { "disarm", "kill" },
            reason = "bad_little_hands",
            action = action,
        }

        faceRat.badLittleHands[#faceRat.badLittleHands + 1] = item
        faceRat.stolenItems[#faceRat.stolenItems + 1] = record

        item.stolenBy = faceRat.id
        item.stolenByName = faceRat.name
        item.stolenFrom = owner and owner.id or nil
        item.stolenFromName = owner and owner.name or nil
        item.heldInBadLittleHands = true

        return record
    end

    function resolver:peekBadLittleHandsItem(faceRat)
        if not faceRat then
            return nil, nil
        end
        if faceRat.stolenItems and #faceRat.stolenItems > 0 then
            local record = faceRat.stolenItems[1]
            return record.item, record
        end
        if faceRat.badLittleHands and #faceRat.badLittleHands > 0 then
            local item = faceRat.badLittleHands[1]
            return item, { item = item, location = inventory.LOCATIONS.BELT }
        end
        return nil, nil
    end

    function resolver:popBadLittleHandsItem(faceRat)
        if not faceRat then
            return nil, nil
        end

        local record = nil
        local item = nil
        if faceRat.stolenItems and #faceRat.stolenItems > 0 then
            record = table.remove(faceRat.stolenItems, 1)
            item = record and record.item
        end
        if faceRat.badLittleHands and #faceRat.badLittleHands > 0 then
            if item and item.id then
                for i, held in ipairs(faceRat.badLittleHands) do
                    if held == item or held.id == item.id then
                        table.remove(faceRat.badLittleHands, i)
                        break
                    end
                end
            else
                item = table.remove(faceRat.badLittleHands, 1)
            end
        end

        if item and not record then
            record = { item = item, location = inventory.LOCATIONS.BELT }
        end

        return item, record
    end

    function resolver:clearBadLittleHandsItemMetadata(item)
        if not item then
            return
        end
        item.stolenBy = nil
        item.stolenByName = nil
        item.stolenFrom = nil
        item.stolenFromName = nil
        item.heldInBadLittleHands = nil
    end

    function resolver:returnBadLittleHandsItem(faceRat, item, record, reason)
        local owner = record and record.from or nil
        local recovered = {
            item = item,
            owner = owner,
            ownerId = record and record.fromId or nil,
            reason = reason or "bad_little_hands_recovered",
            returned = false,
        }

        self:clearBadLittleHandsItemMetadata(item)

        if owner and owner.inventory and owner.inventory.addItem then
            local tried = {}
            local function tryLocation(location)
                if not location or tried[location] then
                    return false
                end
                tried[location] = true
                local ok, addReason = owner.inventory:addItem(item, location)
                if ok then
                    recovered.returned = true
                    recovered.location = location
                    return true
                end
                recovered.error = addReason
                return false
            end

            tryLocation(record and record.location)
            if not recovered.returned then
                tryLocation(inventory.LOCATIONS.BELT)
            end
            if not recovered.returned then
                tryLocation(inventory.LOCATIONS.PACK)
            end
            if not recovered.returned then
                tryLocation(inventory.LOCATIONS.HANDS)
            end
        end

        if not recovered.returned and faceRat then
            faceRat.droppedItems = faceRat.droppedItems or {}
            faceRat.droppedItems[#faceRat.droppedItems + 1] = item
            recovered.dropped = true
        end

        self.eventBus:emit(events.EVENTS.INVENTORY_CHANGED, {
            entity = owner or faceRat,
            item = item,
            reason = reason or "bad_little_hands_recovered",
            source = faceRat,
            recovery = recovered,
        })

        return recovered
    end

    function resolver:releaseBadLittleHandsItem(faceRat, reason)
        local item, record = self:popBadLittleHandsItem(faceRat)
        if not item then
            return nil
        end
        return self:returnBadLittleHandsItem(faceRat, item, record, reason)
    end

    function resolver:releaseAllBadLittleHandsItems(faceRat, reason)
        local released = {}
        while self:peekBadLittleHandsItem(faceRat) do
            local recovery = self:releaseBadLittleHandsItem(faceRat, reason)
            if not recovery then
                break
            end
            released[#released + 1] = recovery
        end
        return released
    end

    function resolver:releaseGriffinGrab(griffin, victim, reason)
        griffin = griffin or (victim and victim.griffinGrabbedBy)
        victim = victim or (griffin and griffin.grabbedVictim)
        if not victim then
            return nil
        end

        if victim.conditions and (victim.griffinGrabbedBy or victim.rootedBy == "griffin_grab") then
            victim.conditions.rooted = false
        end
        victim.griffinGrabbedBy = nil
        victim.griffinGrabbedById = nil
        victim.griffinGrabbedByName = nil
        victim.griffinGrabMovesWith = nil
        victim.griffinGrabRecoverCausesFallingDamage = nil
        victim.griffinGrabFallHeightFeet = nil
        if victim.rootedBy == "griffin_grab" then
            victim.rootedBy = nil
        end

        if griffin then
            griffin.grabbedVictim = nil
            griffin.griffinGrab = nil
        end

        return {
            victim = victim,
            griffin = griffin,
            reason = reason or "released",
        }
    end

    function resolver:applyGriffinGrabMove(actor, oldZone, newZone, action, result)
        local grab = actor and actor.griffinGrab
        local victim = grab and grab.victim
        if not victim or not grab.targetMovesWithActor or not newZone then
            return nil
        end

        local victimOldZone = victim.zone
        if self.zoneSystem and victim.id then
            self.zoneSystem:placeEntity(victim.id, newZone)
        end
        victim.zone = newZone
        result.griffinGrabMovedVictim = {
            victim = victim,
            oldZone = victimOldZone,
            newZone = newZone,
        }
        result.effects[#result.effects + 1] = "griffin_grab_victim_moved"

        self.eventBus:emit("entity_zone_changed", {
            entity = victim,
            oldZone = victimOldZone or oldZone,
            newZone = newZone,
            reason = "griffin_grab",
        })

        return victim
    end

    function resolver:redirectMissedAttackToGrabbedVictim(action, result, opts)
        opts = opts or {}
        local griffin = action and action.target
        local grab = griffin and griffin.griffinGrab
        local victim = grab and grab.victim
        if not victim or not grab.missedAttacksHitGrabbedVictim then
            return false
        end
        if victim.conditions and (victim.conditions.dead or victim.conditions.deaths_door) then
            return false
        end

        local damage = opts.damage or action.griffinGrabRedirectDamage or 1
        result.griffinGrabRedirect = {
            griffin = griffin,
            victim = victim,
            damage = damage,
        }
        result.effects[#result.effects + 1] = "miss_redirected_to_grabbed_victim"
        result.effects[#result.effects + 1] = "griffin_grab_victim_hit"
        result.description = (result.description or "Miss!") .. " The missed Attack hits the grabbed victim."

        if damage > 0 then
            self:applyDamage(victim, damage, result.effects, action.weapon, action.allEntities,
                self:getActionWoundOptions(action, victim), {
                    source = "griffin_grab_missed_attack",
                    action = action,
                    useAegis = action.useAegis,
                })
        end

        return true
    end

    function resolver:applyGriffinGrabFall(victim, action, result, reason)
        if not victim then
            return nil
        end

        local heightFeet = action and (action.heightFeet or action.roomHeightFeet or action.fallHeightFeet) or
            victim.griffinGrabFallHeightFeet or 0
        local fall = self:resolveFall(victim, heightFeet, {
            card = action and action.fallCard,
            testResult = action and action.fallTestResult,
            success = action and action.fallSuccess,
            greatSuccess = action and action.fallGreatSuccess,
            greatFailure = action and action.fallGreatFailure,
            allEntities = action and action.allEntities,
            woundOptions = action and action.fallWoundOptions,
        })
        result.griffinGrabFall = fall
        result.effects[#result.effects + 1] = "griffin_grab_fall"
        for _, effect in ipairs(fall.effects or {}) do
            result.effects[#result.effects + 1] = effect
        end
        result.description = (result.description or "") .. " " .. (fall.description or "Victim falls.")
        return fall
    end

    function resolver:resolveGriffinDrop(action, result)
        result.effects = result.effects or {}
        action = action or {}
        local actor = action.actor
        local grab = actor and actor.griffinGrab
        local victim = action.target or (grab and grab.victim)

        if not actor or not victim or not grab then
            result.success = false
            result.description = "No grabbed victim to drop."
            result.effects[#result.effects + 1] = "griffin_drop_blocked"
            return result
        end

        local causesFall = action.causesFallingDamage ~= false and
            (action.heightFeet or action.roomHeightFeet or action.fallHeightFeet or grab.flying or actor.flying)
        if not action.heightFeet and not action.roomHeightFeet and not action.fallHeightFeet and grab.heightFeet then
            action.heightFeet = grab.heightFeet
        end
        self:releaseGriffinGrab(actor, victim, "griffin_drop")

        result.success = true
        result.effects[#result.effects + 1] = "griffin_drop"
        result.effects[#result.effects + 1] = "griffin_grab_released"
        result.description = (actor.name or "Griffin") .. " drops " .. (victim.name or "the victim") .. "."

        if causesFall then
            self:applyGriffinGrabFall(victim, action, result, "griffin_drop")
        end

        action.result = result
        return result
    end

    function resolver:resolveHarpyShriek(action, result)
        result.effects = result.effects or {}
        action = action or {}
        local actor = action.actor

        if not actor then
            result.success = false
            result.description = "No harpy for Shriek."
            result.effects[#result.effects + 1] = "missing_actor"
            return result
        end
        if not (entityHasNormalizedTag(actor, "harpy") or actor.harpy) then
            result.success = false
            result.description = "Shriek requires a harpy."
            result.effects[#result.effects + 1] = "harpy_shriek_blocked"
            return result
        end

        local doom = action.greaterDoom or action.doom
        local effect = doom and doom.effect
        if not (action.greaterDoomCard or action.discardedGreaterDoom or action.useGreaterDoom == true or
           (effect and effect.type == "same_zone_stun")) then
            result.success = false
            result.description = "Harpy Shriek requires a greater doom."
            result.effects[#result.effects + 1] = "harpy_shriek_requires_greater_doom"
            return result
        end

        local zone = action.zone or actor.zone
        local affected = {}
        local skipped = {}
        local candidates = action.targets or action.allEntities or {}
        for _, candidate in ipairs(candidates) do
            if candidate ~= actor and candidate.zone == zone and not entityHasNormalizedTag(candidate, "harpy") then
                self:applyStun(candidate, {
                    action = action,
                    instant = true,
                    hand = candidate.challengeHand,
                    handData = candidate.challengeHandData,
                    playerHand = action.playerHand,
                    playerDeck = action.playerDeck,
                    gmDeck = action.gmDeck,
                    npcAI = action.npcAI,
                })
                affected[#affected + 1] = candidate
            elseif candidate ~= actor then
                skipped[#skipped + 1] = candidate
            end
        end

        result.success = true
        result.affected = affected
        result.skipped = skipped
        result.drawsNearbyCreatures = true
        result.loudNoise = {
            source = actor,
            kind = "harpy_shriek",
            zone = zone,
            drawsNearbyCreatures = true,
        }
        actor.lastLoudNoise = result.loudNoise
        if action.room then
            action.room.loudNoise = result.loudNoise
        end

        result.effects[#result.effects + 1] = "harpy_shriek"
        result.effects[#result.effects + 1] = "same_zone_stun"
        result.effects[#result.effects + 1] = "loud_noise"
        result.effects[#result.effects + 1] = "draws_nearby_creatures"
        result.description = "Harpy Shriek stuns " .. tostring(#affected) .. " non-harpy creature(s)."

        self.eventBus:emit("harpy_shriek", {
            actor = actor,
            zone = zone,
            affected = affected,
            skipped = skipped,
            loudNoise = result.loudNoise,
        })

        action.result = result
        return result
    end

    function resolver:resolveLionCautiousRetreat(action, result)
        result.effects = result.effects or {}
        action = action or {}
        local actor = action.actor
        local target = action.target

        if not actor then
            result.success = false
            result.description = "No lion for Cautious Retreat."
            result.effects[#result.effects + 1] = "missing_actor"
            return result
        end
        if not (entityHasNormalizedTag(actor, "lion") or actor.lion) then
            result.success = false
            result.description = "Cautious Retreat requires a lion."
            result.effects[#result.effects + 1] = "lion_cautious_retreat_blocked"
            return result
        end
        if not target then
            result.success = false
            result.description = "No adventurer to disengage from."
            result.effects[#result.effects + 1] = "lion_cautious_retreat_missing_target"
            return result
        end

        local doom = action.greaterDoom or action.doom
        local effect = doom and doom.effect
        if not (action.greaterDoomCard or action.discardedGreaterDoom or action.useGreaterDoom == true or
           (effect and effect.type == "disengage_one")) then
            result.success = false
            result.description = "Lion Cautious Retreat requires a greater doom."
            result.effects[#result.effects + 1] = "lion_cautious_retreat_requires_greater_doom"
            return result
        end

        self:breakEngagement(actor, target)

        result.success = true
        result.cardless = true
        result.countsTowardTurnCard = false
        result.effects[#result.effects + 1] = "lion_cautious_retreat"
        result.effects[#result.effects + 1] = "greater_doom"
        result.effects[#result.effects + 1] = "disengaged"
        result.greaterDoom = {
            name = doom and doom.name or "Cautious Retreat",
            card = action.greaterDoomCard,
        }
        result.description = (actor.name or "Lion") .. " disengages from " ..
            (target.name or "one adventurer") .. " without spending its turn card."

        self.eventBus:emit("lion_cautious_retreat", {
            actor = actor,
            target = target,
            action = action,
            result = result,
        })

        action.result = result
        return result
    end

    function resolver:isMimicTarget(entity)
        return entity and (entity.isMimic == true or entity.mimic ~= nil or entityHasNormalizedTag(entity, "mimic"))
    end

    function resolver:mimicRequiresExceedInitiative(entity)
        if not self:isMimicTarget(entity) then
            return false
        end
        if entity.mimic and entity.mimic.mustExceedInitiative == false then
            return false
        end
        return true
    end

    function resolver:getWeaponImmunityKey(weapon)
        if not weapon then
            return nil
        end
        return normalizeTalentKey(weapon.weaponType or weapon.type or weapon.name or weapon.templateId)
    end

    function resolver:resolveMimicHarden(action, result)
        result.effects = result.effects or {}
        action = action or {}
        local actor = action.actor

        if not actor then
            result.success = false
            result.description = "No mimic for Harden."
            result.effects[#result.effects + 1] = "missing_actor"
            return result
        end
        if not self:isMimicTarget(actor) then
            result.success = false
            result.description = "Harden requires a mimic."
            result.effects[#result.effects + 1] = "mimic_harden_blocked"
            return result
        end

        local doom = action.greaterDoom or action.doom
        local effect = doom and doom.effect
        if not (action.greaterDoomCard or action.discardedGreaterDoom or action.useGreaterDoom == true or
           (effect and effect.type == "mimic_harden_weapon_immunity")) then
            result.success = false
            result.description = "Mimic Harden requires a greater doom."
            result.effects[#result.effects + 1] = "mimic_harden_requires_greater_doom"
            return result
        end

        local weaponType = actor.lastWoundingWeaponType
        if not weaponType or weaponType == "" then
            result.success = false
            result.description = "Mimic Harden has no last wounding weapon type."
            result.effects[#result.effects + 1] = "mimic_harden_no_wounding_weapon"
            return result
        end

        actor.mimicWeaponImmunityType = weaponType
        actor.mimicWeaponImmunityName = actor.lastWoundingWeaponName or weaponType
        actor.mimicHarden = {
            weaponType = weaponType,
            weaponName = actor.mimicWeaponImmunityName,
            source = doom and doom.name or "Harden",
        }

        result.success = true
        result.cardless = true
        result.countsTowardTurnCard = false
        result.effects[#result.effects + 1] = "mimic_harden"
        result.effects[#result.effects + 1] = "greater_doom"
        result.effects[#result.effects + 1] = "weapon_immunity"
        result.weaponImmunityType = weaponType
        result.description = (actor.name or "Mimic") .. " hardens against " ..
            tostring(actor.mimicWeaponImmunityName) .. " attacks."

        self.eventBus:emit("mimic_harden", {
            actor = actor,
            action = action,
            result = result,
        })

        action.result = result
        return result
    end

    ----------------------------------------------------------------------------
    -- MAIN RESOLUTION ENTRY POINT
    ----------------------------------------------------------------------------

    --- Resolve an action
    -- @param action table: { actor, target, type, card, weapon, ... }
    -- @return table: { success, isGreat, damageDealt, effects, description }
    function resolver:resolve(action)
        local result = {
            success = false,
            isGreat = false,
            damageDealt = 0,
            effects = {},
            description = "",
            cardValue = 0,
            modifier = 0,
            testValue = 0,
            difficulty = 10,
        }

        action = action or {}
        local actionType = self:normalizeActionType(action.type or "generic")
        action.normalizedType = actionType

        if actionType == M.ACTION_TYPES.CREATURE_GAZE or actionType == M.ACTION_TYPES.COCKATRICE_GAZE then
            return self:resolveCreatureGaze(action, result)
        end

        if actionType == M.ACTION_TYPES.GRIFFIN_DROP then
            return self:resolveGriffinDrop(action, result)
        end

        if actionType == M.ACTION_TYPES.HARPY_SHRIEK then
            return self:resolveHarpyShriek(action, result)
        end

        if actionType == M.ACTION_TYPES.LION_CAUTIOUS_RETREAT then
            return self:resolveLionCautiousRetreat(action, result)
        end

        if actionType == M.ACTION_TYPES.MIMIC_HARDEN then
            return self:resolveMimicHarden(action, result)
        end

        if actionType == M.ACTION_TYPES.SNEAK then
            return self:resolveSneak(action, result)
        end

        if not action.actor or not action.card then
            result.description = "Invalid action"
            return result
        end

        -- Cache action definition early so registry-level requirements apply
        -- even when callers pass only a raw action type.
        local actionDef = self:getActionDef(action)
        if actionDef then
            action.actionDef = actionDef
        end

        -- S12.2: Pre-resolution validation
        local canPerform, blockReason = self:canPerformAction(action.actor, action.type, actionDef, action)
        if not canPerform then
            result.success = false
            result.description = blockReason or "Action blocked"
            result.effects[#result.effects + 1] = "action_blocked"

            -- Emit blocked event
            self.eventBus:emit("action_blocked", {
                actor = action.actor,
                actionType = action.type,
                reason = blockReason,
            })

            return result
        end

        -- Get card info
        local card = action.card
        result.cardValue = card.value or 0
        local suit = card.suit

        -- S4.9: Check for The Fool interrupt
        if M.isFool(card) then
            return self:resolveFoolInterrupt(action, result)
        end

        -- S7.x: Non-combat actions during Challenges can trigger Test of Fate
        local controller = action.challengeController or self.challengeController
        if actionDef and actionDef.testOfFate and controller and controller.isActive and controller:isActive() then
            local areteResult = self:resolveAreteAutoSuccessTestOfFate(action, actionDef, result)
            if areteResult then
                return areteResult
            end
            return self:requestTestOfFate(action, actionDef, result)
        end

        -- Bid Lore resolves asynchronously through the Bid Lore modal.
        if actionType == M.ACTION_TYPES.BID_LORE and controller and controller.isActive and controller:isActive() then
            return self:requestBidLore(action, actionDef, result)
        end

        -- Calculate modifier from action's associated attribute (or card-only rules)
        local statMod = self:getActionModifier(action, actionDef)
        result.modifier = statMod

        -- Total test value
        result.testValue = result.cardValue + result.modifier

        local favorOk = self:applyChallengeActionFavor(action, result, actionDef, actionType)
        if not favorOk then
            action.result = result
            return result
        end

        -- Get difficulty (target's defense or fixed value)
        result.difficulty = self:getDifficulty(action, actionDef)
        if action.heavyMetalMachineApplied then
            result.heavyMetalMachineApplied = action.heavyMetalMachineApplied
            result.effects[#result.effects + 1] = "heavy_metal_machine_interrupt"
            result.effects[#result.effects + 1] = "initiative_boosted"
        end

        -- Check for success
        result.success = result.testValue >= result.difficulty

        -- Check for Great Success (face card matching suit)
        result.isGreat = self:isGreatSuccess(card, action.actor)

        -- Route to specific resolution based on ACTION TYPE (not card suit)
        -- This allows using any card for any action on primary turns
        -- Swords actions (combat)
        if actionType == M.ACTION_TYPES.MELEE or actionType == M.ACTION_TYPES.MISSILE then
            self:resolveSwordsAction(action, result)
        -- Pentacles actions (agility/technical)
        elseif actionType == M.ACTION_TYPES.ROUGHHOUSE or
               actionType == M.ACTION_TYPES.TRIP or actionType == M.ACTION_TYPES.DISARM or
               actionType == M.ACTION_TYPES.DISPLACE or actionType == M.ACTION_TYPES.GRAPPLE or
               actionType == M.ACTION_TYPES.AVOID or actionType == M.ACTION_TYPES.DASH then
            self:resolvePentaclesAction(action, result)
        -- Cups actions (defense/social)
        elseif actionType == M.ACTION_TYPES.DODGE or actionType == M.ACTION_TYPES.RIPOSTE or
               actionType == M.ACTION_TYPES.HEAL or actionType == M.ACTION_TYPES.SHIELD or
               actionType == M.ACTION_TYPES.AID or actionType == M.ACTION_TYPES.COMMAND or
               actionType == M.ACTION_TYPES.PARLEY or actionType == M.ACTION_TYPES.RALLY or
               actionType == M.ACTION_TYPES.PULL_ITEM or actionType == M.ACTION_TYPES.USE_ITEM then
            self:resolveCupsAction(action, result)
        -- Wands actions (magic/perception)
        elseif actionType == M.ACTION_TYPES.BANTER or actionType == M.ACTION_TYPES.SPEAK_INCANTATION or
               actionType == M.ACTION_TYPES.COUNTER_SPELL or actionType == M.ACTION_TYPES.RECOVER then
            self:resolveWandsAction(action, result)
        -- Movement and misc
        elseif actionType == M.ACTION_TYPES.MOVE then
            self:resolveMove(action, result, action.allEntities)
        elseif actionType == M.ACTION_TYPES.GUARD then
            self:resolveGuard(action, result)
        elseif actionType == M.ACTION_TYPES.HEAVY_METAL_MACHINE then
            self:resolveHeavyMetalMachine(action, result)
        elseif actionType == M.ACTION_TYPES.VIGILANCE then
            self:resolveVigilance(action, result)
        elseif actionType == M.ACTION_TYPES.DWIMMERCRAFT then
            self:resolveDwimmercraft(action, result)
        elseif actionType == M.ACTION_TYPES.FLEE then
            self:resolveFlee(action, result)
        elseif actionType == M.ACTION_TYPES.BID_LORE or
               actionType == M.ACTION_TYPES.TRIVIAL_ACTION or
               actionType == M.ACTION_TYPES.TEST_FATE or
               actionType == M.ACTION_TYPES.INTERACT then
            self:resolveGenericAction(action, result)
        elseif actionType == M.ACTION_TYPES.PULL_ITEM_BELT then
            self:resolvePullItemFromBelt(action, result)
        elseif actionType == M.ACTION_TYPES.RELOAD then
            -- S7.8: Reload crossbow
            self:resolveReload(action, result)
        else
            -- Unknown action type - fall back to action definition suit when available
            local fallbackSuit = actionDef and actionDef.suit

            if fallbackSuit == action_registry.SUITS.SWORDS then
                self:resolveSwordsAction(action, result)
            elseif fallbackSuit == action_registry.SUITS.PENTACLES then
                self:resolvePentaclesAction(action, result)
            elseif fallbackSuit == action_registry.SUITS.CUPS then
                self:resolveCupsAction(action, result)
            elseif fallbackSuit == action_registry.SUITS.WANDS then
                self:resolveWandsAction(action, result)
            elseif suit == constants.SUITS.SWORDS then
                self:resolveSwordsAction(action, result)
            elseif suit == constants.SUITS.PENTACLES then
                self:resolvePentaclesAction(action, result)
            elseif suit == constants.SUITS.CUPS then
                self:resolveCupsAction(action, result)
            elseif suit == constants.SUITS.WANDS then
                self:resolveWandsAction(action, result)
            else
                self:resolveGenericAction(action, result)
            end
        end

        if actionType == M.ACTION_TYPES.BANTER or actionType == M.ACTION_TYPES.PARLEY then
            self:applyRoomSocialEncounterOutcome(action, result)
        end

        if action.isQuickInterrupt or action.quickInterrupt then
            result.quickInterrupt = true
            result.effects[#result.effects + 1] = "quick_interrupt"
        end

        self:spendActionInspirationCard(action, result)

        -- Attach result to action for event emission
        action.result = result

        return result
    end

    ----------------------------------------------------------------------------
    -- STAT MODIFIER CALCULATION
    ----------------------------------------------------------------------------

    --- Get the stat modifier for a given suit
    function resolver:getStatModifier(entity, suit)
        if not entity then return 0 end

        if suit == constants.SUITS.SWORDS then
            return entity.swords or 0
        elseif suit == constants.SUITS.PENTACLES then
            return entity.pentacles or 0
        elseif suit == constants.SUITS.CUPS then
            return entity.cups or 0
        elseif suit == constants.SUITS.WANDS then
            return entity.wands or 0
        end

        return 0
    end

    ----------------------------------------------------------------------------
    -- S7.1: AID ANOTHER SYSTEM
    ----------------------------------------------------------------------------

    --- Apply any active aids to an actor's result
    -- @param actor table: The acting entity
    -- @param result table: Result to modify
    function resolver:applyActiveAids(actor, result)
        if not actor or not actor.id then return end

        local aid = self.activeAids[actor.id]
        if aid then
            result.modifier = (result.modifier or 0) + aid.val
            result.testValue = result.cardValue + result.modifier
            result.description = (result.description or "") .. "(Aided by " .. aid.source .. " +" .. aid.val .. ") "
            result.effects[#result.effects + 1] = "aided"

            -- Clear the aid (one-time use)
            self.activeAids[actor.id] = nil
            print("[AID] " .. (actor.name or actor.id) .. " used aid bonus +" .. aid.val .. " from " .. aid.source)
        end
    end

    --- Register an aid for a target
    -- @param target table: Entity receiving the aid
    -- @param value number: Bonus value (card value + cups)
    -- @param source string: Name of the aiding entity
    function resolver:registerAid(target, value, source)
        if not target or not target.id then return end

        -- Overwrite any existing aid (per S7.1 design notes)
        self.activeAids[target.id] = {
            val = value,
            source = source,
        }
        print("[AID] " .. source .. " aids " .. (target.name or target.id) .. " with +" .. value .. " bonus")
    end

    ----------------------------------------------------------------------------
    -- DIFFICULTY CALCULATION
    ----------------------------------------------------------------------------

    --- Get the difficulty for an action
    function resolver:getDifficulty(action, actionDef)
        local target = action.target
        local actionType = self:normalizeActionType(action.type)

        -- Default difficulty
        local difficulty = 10

        if target then
            -- Initiative-opposed actions compare against target Initiative
            if self:isInitiativeOpposed(actionType) then
                local initValue = self:getTargetInitiative(target, action)
                if initValue then
                    return initValue
                end

                -- Fallback: legacy defense if initiative unavailable
                return 10 + (target.pentacles or 0)
            end

            if actionType == M.ACTION_TYPES.BANTER then
                -- S12.3: Banter vs dynamic Morale
                if target.getMorale then
                    difficulty = target:getMorale()
                elseif target.baseMorale then
                    difficulty = target.baseMorale
                else
                    -- Legacy fallback
                    difficulty = target.morale or (10 + (target.wands or 0))
                end
            elseif actionType == M.ACTION_TYPES.PARLEY then
                -- Parley is intentionally slightly harder than Banter
                if target.getMorale then
                    difficulty = target:getMorale() + 1
                elseif target.baseMorale then
                    difficulty = target.baseMorale + 1
                end
            end
        end

        return difficulty
    end

    ----------------------------------------------------------------------------
    -- GREAT SUCCESS CHECK
    ----------------------------------------------------------------------------

    --- Check if this is a Great Success
    -- Great = Face card (11-14) AND card suit matches actor's highest stat
    function resolver:isGreatSuccess(card, actor)
        if not card or card.value < 11 then
            return false
        end

        -- Check if card suit matches actor's specialization
        -- (simplified: check if this suit is their highest)
        local suit = card.suit
        local statValue = self:getStatModifier(actor, suit)

        -- For now, any face card on a stat >= 2 is Great
        return statValue >= 2
    end

    ----------------------------------------------------------------------------
    -- SWORDS RESOLUTION (Melee & Missile)
    ----------------------------------------------------------------------------

    function resolver:resolveSwordsAction(action, result)
        local actionType = self:normalizeActionType(action.type or M.ACTION_TYPES.MELEE)

        if actionType == M.ACTION_TYPES.MISSILE then
            self:resolveMissile(action, result)
        else
            self:resolveMelee(action, result)
        end
    end

    function resolver:wantsReaver(action)
        return action and (action.useReaver == true or action.reaver == true or action.reaverCharge == true)
    end

    function resolver:resolveReaverCharge(action, result)
        if not self:wantsReaver(action) then
            return true
        end

        local actor = action and action.actor
        if not entityHasUsableTalent(actor, "reaver") then
            result.success = false
            result.description = "Requires Reaver"
            result.effects[#result.effects + 1] = "reaver_blocked"
            return false
        end
        if not self:isActiveChallengeAction(action) then
            result.success = false
            result.description = "Reaver requires an active Challenge"
            result.effects[#result.effects + 1] = "reaver_blocked"
            return false
        end
        if actor.conditions and actor.conditions.rooted then
            result.success = false
            result.description = "Cannot Reaver charge while rooted"
            result.effects[#result.effects + 1] = "reaver_blocked"
            return false
        end

        local oldZone = actor and actor.zone
        local destinationZone = action.reaverDestinationZone or action.chargeDestinationZone or
            (action.target and action.target.zone)
        if not destinationZone or oldZone == destinationZone then
            return true
        end

        local canMove, moveError = self:canMoveBetweenZones(action, oldZone, destinationZone, { maxDistance = 1 })
        if not canMove then
            result.success = false
            result.description = "Reaver charge failed: destination zone is not adjacent."
            result.effects[#result.effects + 1] = "reaver_blocked"
            if moveError then
                result.effects[#result.effects + 1] = moveError
            end
            return false
        end

        local moveResult = {
            success = false,
            effects = {},
            description = "",
        }
        self:resolveMove({
            actor = actor,
            destinationZone = destinationZone,
            challengeController = action.challengeController,
            maxMoveDistance = 1,
        }, moveResult, action.allEntities)

        if not moveResult.success then
            result.success = false
            result.description = "Reaver charge failed: " .. (moveResult.description or "movement failed")
            result.effects[#result.effects + 1] = "reaver_blocked"
            for _, effect in ipairs(moveResult.effects or {}) do
                result.effects[#result.effects + 1] = effect
            end
            return false
        end

        result.reaverCharge = {
            actor = actor,
            oldZone = oldZone,
            newZone = destinationZone,
        }
        for _, effect in ipairs(moveResult.effects or {}) do
            result.effects[#result.effects + 1] = effect
        end
        result.effects[#result.effects + 1] = "reaver_charge"
        result.description = (result.description or "") .. "Reaver charge! "

        if actor.conditions and (actor.conditions.dead or actor.conditions.deaths_door) then
            result.success = false
            result.description = "Reaver charge failed: the actor fell during movement."
            result.effects[#result.effects + 1] = "reaver_blocked"
            return false
        end

        return true
    end

    function resolver:wantsDoomEye(action)
        return action and (action.useDoomEye == true or action.doomEye == true or action.perfectShot == true)
    end

    function resolver:getDoomEyeMissileWeapon(action)
        local weapon = action and action.weapon
        if weapon and (weapon.isRanged or M.isWeaponType(weapon, "BOW") or M.isWeaponType(weapon, "CROSSBOW")) then
            return weapon
        end

        local inv = action and action.actor and action.actor.inventory
        if inv and inv.getWieldedWeapon then
            weapon = inv:getWieldedWeapon()
            if weapon and (weapon.isRanged or M.isWeaponType(weapon, "BOW") or M.isWeaponType(weapon, "CROSSBOW")) then
                return weapon
            end
        end

        return nil
    end

    function resolver:isArchwoodWand(item)
        if not item or item.destroyed then
            return false
        end

        local props = item.properties or {}
        if props.wand and props.archwood then
            return true
        end

        local id = normalizeTalentKey(item.templateId or item.id or item.name)
        return id == "wand_archwood" or id == "wand_of_archwood"
    end

    function resolver:breakPactForItemContact(action, result, item, pactId, reason)
        local actor = action and action.actor
        local pact = camp_actions.findUnbrokenActivePact(actor, pactId)
        if not pact then
            return nil
        end

        local ok, breakResult, detail = camp_actions.breakPact(actor, pact, {
            eventBus = self.eventBus,
            actionResolver = self,
            reason = reason,
        })
        result.pactBreaks = result.pactBreaks or {}
        result.pactBreaks[#result.pactBreaks + 1] = {
            ok = ok,
            result = breakResult,
            detail = detail,
            pact = pact,
            pactId = pactId,
            reason = reason,
            item = item,
        }
        result.effects[#result.effects + 1] = "pact_broken_" .. pactId
        return detail
    end

    function resolver:applyPactItemObligations(action, result, item, reason)
        if not item or not action or not action.actor then
            return {}
        end

        local breaks = {}
        if itemIsArmorOrShieldForPact(item) then
            local detail = self:breakPactForItemContact(action, result, item, "forego_armor",
                reason or "forego_armor_item_contact")
            if detail then
                breaks[#breaks + 1] = detail
            end
        end
        if itemIsWeaponForPact(item) then
            local detail = self:breakPactForItemContact(action, result, item, "forego_weapons",
                reason or "forego_weapons_item_contact")
            if detail then
                breaks[#breaks + 1] = detail
            end
        end
        if itemIsFelledWoodForPact(item) then
            local detail = self:breakPactForItemContact(action, result, item, "forego_wood",
                reason or "forego_wood_item_contact")
            if detail then
                breaks[#breaks + 1] = detail
            end
        end
        if itemIsSkinOrFurForPact(item) then
            local detail = self:breakPactForItemContact(action, result, item, "forego_skins",
                reason or "forego_skins_item_contact")
            if detail then
                breaks[#breaks + 1] = detail
            end
        end

        return breaks
    end

    function resolver:getActionWeapon(action)
        if not action then
            return nil
        end
        if action.weapon then
            return action.weapon
        end
        local inv = action.actor and action.actor.inventory
        return inv and inv.getWieldedWeapon and inv:getWieldedWeapon() or nil
    end

    function resolver:getGramaryWand(action)
        if not action then
            return nil
        end

        if self:isArchwoodWand(action.weapon) then
            return action.weapon
        end

        local inv = action.actor and action.actor.inventory
        local weapon = inv and inv.getWieldedWeapon and inv:getWieldedWeapon()
        if self:isArchwoodWand(weapon) then
            return weapon
        end
        local hands = inv and inv.getItems and inv:getItems(inventory.LOCATIONS.HANDS) or {}
        for _, item in ipairs(hands or {}) do
            if self:isArchwoodWand(item) then
                return item
            end
        end

        return nil
    end

    function resolver:isActiveChallengeAction(action)
        if not action then
            return false
        end

        local controller = action.challengeController or self.challengeController
        if controller and controller.isActive then
            return controller:isActive() == true
        end

        return action.inChallenge == true or action.challenge == true
    end

    function resolver:isGramaryWandAttack(action)
        return action and
            self:normalizeActionType(action.type) == M.ACTION_TYPES.MISSILE and
            self:isActiveChallengeAction(action) and
            entityHasUsableTalent(action.actor, "gramarye") and
            self:getGramaryWand(action) ~= nil
    end

    function resolver:canUseDoomEye(action)
        local actor = action and action.actor
        if not entityHasUsableTalent(actor, "doom_eye") then
            return false, "Requires Doom Eye"
        end
        if self:normalizeActionType(action.type) ~= M.ACTION_TYPES.MISSILE then
            return false, "Doom Eye requires a missile Attack"
        end
        if not action.card or action.card.suit ~= constants.SUITS.SWORDS then
            return false, "Doom Eye requires a Sword card"
        end

        if not self:isActiveChallengeAction(action) then
            return false, "Doom Eye requires an active Challenge"
        end

        local weapon = self:getDoomEyeMissileWeapon(action)
        if not weapon then
            return false, "Doom Eye requires a missile weapon"
        end

        return true, nil, weapon
    end

    function resolver:applyMaledictionWeaponRust(action, result)
        local actor = action and action.actor
        local weapon = action and action.weapon
        if not actor or not actor.weaponRustMalediction or not weapon then
            return nil
        end

        local cardValue = action.card and action.card.value or result.cardValue or 0
        local threshold = actor.maledictionWeaponNotchThreshold or 10
        if cardValue < threshold then
            return nil
        end

        local inventory = require('logic.inventory')
        weapon.notches = weapon.notches or 0
        weapon.durability = weapon.durability or 1
        local notchResult = inventory.addNotch(weapon)
        result.weaponNotchResult = notchResult
        result.effects[#result.effects + 1] = "malediction_weapon_notched"
        if notchResult == "destroyed" then
            result.effects[#result.effects + 1] = "weapon_destroyed"
        end
        return notchResult
    end

    function resolver:applyAttackAffliction(target, effect, action, result)
        if not target then
            return nil
        end

        local afflictionId = effect.affliction or effect.afflictionId or "affliction"
        target.afflictions = target.afflictions or {}
        local affliction = target.afflictions[afflictionId]
        if not affliction then
            affliction = {
                id = afflictionId,
                name = effect.afflictionName or (afflictionId == "face_rat_disease" and "Face Rat Disease") or afflictionId,
                source = effect.source or "greater_doom_attack",
                sourceId = action and action.actor and action.actor.id or nil,
                stage = 1,
                maxStage = 3,
                stageCosts = {
                    [1] = 1,
                    [2] = 1,
                    [3] = 2,
                },
                stages = {
                    {
                        id = "featureless_mask",
                        cureCharges = 1,
                        wandsInfluenceDisfavor = true,
                    },
                    {
                        id = "skin_over_nose_and_mouth",
                        cureCharges = 1,
                        condition = "silenced",
                    },
                    {
                        id = "skin_over_eyes",
                        cureCharges = 2,
                        condition = "blind",
                    },
                },
            }
            target.afflictions[afflictionId] = affliction
        else
            affliction.stage = math.max(affliction.stage or 1, 1)
        end

        if afflictionId == "face_rat_disease" then
            target.faceRatDisease = affliction
            target.faceRatDiseaseWandsDisfavor = true
        end

        result.attackAffliction = affliction
        result.effects[#result.effects + 1] = "attack_affliction"
        result.effects[#result.effects + 1] = afflictionId
        return affliction
    end

    function resolver:applyStealFaceAttack(target, effect, action, result)
        if not target then
            return nil
        end

        target.conditions = target.conditions or {}
        target.conditions.blind = effect.blind ~= false
        target.conditions.blinded = effect.blind ~= false
        target.conditions.silenced = effect.silence ~= false
        target.silenced = effect.silence ~= false
        target.faceStolen = true
        target.faceStolenBy = action and action.actor
        target.faceStolenById = action and action.actor and action.actor.id or nil

        local actor = action and action.actor
        if actor then
            actor.stolenFaces = actor.stolenFaces or {}
            actor.stolenFaces[#actor.stolenFaces + 1] = {
                victim = target,
                victimId = target.id,
                victimName = target.name,
                permanent = effect.copiesFacePermanently ~= false,
            }
            actor.currentFace = target.name or target.id
        end

        if effect.replacesWound ~= false then
            result.damageDealt = 0
            result.effects[#result.effects + 1] = "wound_replaced"
        end
        result.stealFace = {
            actor = actor,
            target = target,
            blind = effect.blind ~= false,
            silence = effect.silence ~= false,
        }
        result.effects[#result.effects + 1] = "steal_face"
        result.effects[#result.effects + 1] = "blind"
        result.effects[#result.effects + 1] = "silenced"
        return result.stealFace
    end

    function resolver:getActionLesserDoomEffect(action)
        local doom = action and (action.lesserDoom or action.attackDoom)
        if not doom then
            return nil, nil
        end
        return doom.effect or {}, doom
    end

    function resolver:applyAttackConditionChoice(target, effect, action, result, doom)
        local choice = action.lesserDoomChoice or action.doomChoice or action.conditionChoice or
            action.choice or effect.choice or effect.defaultChoice or (effect.choices and effect.choices[1])
        choice = self:normalizeRoughhouseEffect(choice)

        result.attackConditionChoice = choice
        result.effects[#result.effects + 1] = "attack_condition_choice"
        if doom and doom.id == "bite" and entityHasNormalizedTag(action.actor, "lion") then
            result.effects[#result.effects + 1] = "lion_bite"
        end

        if choice == "disarmed" or choice == "disarm" then
            local droppedItem = nil
            if target.inventory and target.inventory.getItems then
                local handsItems = target.inventory:getItems(inventory.LOCATIONS.HANDS) or {}
                droppedItem = handsItems[1]
            elseif target.weapon then
                droppedItem = target.weapon
            end

            if droppedItem then
                droppedItem = self:dropCarriedItem(target, droppedItem, "attack_condition_choice", action)
                target.conditions = target.conditions or {}
                target.conditions.disarmed = true
                result.droppedItem = droppedItem
                result.effects[#result.effects + 1] = "disarmed"
                result.effects[#result.effects + 1] = "lion_bite_disarm"
                result.description = result.description .. (doom and doom.name or "Attack") ..
                    " disarms [" .. (droppedItem.name or "item") .. "]! "
            else
                result.effects[#result.effects + 1] = "disarm_no_item"
                result.description = result.description .. (doom and doom.name or "Attack") ..
                    " tries to disarm, but the target holds nothing. "
            end
        elseif choice == "tripped" or choice == "trip" then
            target.conditions = target.conditions or {}
            target.conditions.prone = true
            self:clearAllEngagements(target, action.allEntities)
            result.effects[#result.effects + 1] = "prone"
            result.effects[#result.effects + 1] = "lion_bite_trip"
            result.description = result.description .. (doom and doom.name or "Attack") .. " trips the target! "
        end
    end

    function resolver:applyDoubleInitiativeAttackBonus(target, effect, action, result, doom)
        local targetInitiative = result.difficulty or self:getTargetInitiative(target, action) or 0
        if targetInitiative <= 0 then
            return
        end
        if (result.testValue or 0) < targetInitiative * 2 then
            return
        end

        local previousDamage = result.damageDealt or 0
        result.damageDealt = math.max(previousDamage, effect.wounds or 2)
        result.doubleInitiativeAttackBonus = {
            previousDamage = previousDamage,
            damageDealt = result.damageDealt,
            targetInitiative = targetInitiative,
            attackValue = result.testValue,
        }
        result.effects[#result.effects + 1] = "double_initiative_attack_bonus"
        if doom and doom.id == "claw" and entityHasNormalizedTag(action.actor, "lion") then
            result.effects[#result.effects + 1] = "lion_claw_double_initiative"
        end
        if result.damageDealt > previousDamage then
            result.effects[#result.effects + 1] = "damage_increased"
            result.description = result.description .. (doom and doom.name or "Attack") ..
                " lands with overwhelming force! "
        end
    end

    function resolver:applyAttackLesserDoom(action, result, target)
        local effect, doom = self:getActionLesserDoomEffect(action)
        if not effect or not target then
            return
        end

        if effect.type == "attack_plus_condition_choice" then
            self:applyAttackConditionChoice(target, effect, action, result, doom)
        elseif effect.type == "attack_double_initiative_bonus" then
            self:applyDoubleInitiativeAttackBonus(target, effect, action, result, doom)
        end
    end

    function resolver:applyAttackGreaterDoom(action, result, target)
        local doom = action.greaterDoom
        if not doom or not target then
            return
        end

        local effect = doom.effect or {}
        result.effects[#result.effects + 1] = "greater_doom"
        result.greaterDoom = {
            name = doom.name,
            card = action.greaterDoomCard,
        }

        if effect.type == "web" then
            target.conditions = target.conditions or {}
            target.conditions.webbed = true
            self:applyRooted(target, { action = action, reason = "web" })
            target.webbedLimbs = math.max(target.webbedLimbs or 0, effect.limbs or 4)

            result.effects[#result.effects + 1] = "webbed"
            result.effects[#result.effects + 1] = "rooted"
            result.description = result.description .. (doom.name or "Greater doom") .. "! Target is webbed and rooted. "

            if effect.suppressDamage or effect.noDamage then
                result.damageDealt = 0
            end
        elseif effect.type == "attack_affliction" then
            self:applyAttackAffliction(target, effect, action, result)
            result.description = result.description .. (doom.name or "Greater doom") .. "! Target contracts " ..
                tostring(effect.afflictionName or effect.affliction or "an affliction") .. ". "
        elseif effect.type == "attack_blind_and_silence" then
            self:applyStealFaceAttack(target, effect, action, result)
            result.description = result.description .. (doom.name or "Greater doom") ..
                "! Target is Blinded and Silenced instead of wounded. "
        elseif effect.type == "attack_piercing" then
            result.effects[#result.effects + 1] = "piercing"
            if doom.id == "riot_of_teeth" or entityHasNormalizedTag(action.actor, "mimic") then
                result.effects[#result.effects + 1] = "mimic_riot_of_teeth"
            end
            result.description = result.description .. (doom.name or "Greater doom") ..
                "! Attack deals Piercing damage. "
        else
            result.description = result.description .. (doom.name or "Greater doom") .. "! "
        end
    end

    --- Resolve melee attack
    function resolver:resolveMelee(action, result)
        local target = action.target

        -- S7.1: Apply any active aids to this attack
        self:applyActiveAids(action.actor, result)

        -- S12.7: Apply Mob Rule bonuses (swarm attack bonuses)
        if action.mobRuleBonus then
            local mobBonus = action.mobRuleBonus
            if mobBonus.favor then
                result.effects[#result.effects + 1] = "mob_favor"
            end
            if mobBonus.piercing then
                result.effects[#result.effects + 1] = "piercing"
                result.effects[#result.effects + 1] = "mob_piercing"
            end
            if mobBonus.critical then
                result.effects[#result.effects + 1] = "critical"
                result.effects[#result.effects + 1] = "mob_critical"
            end
        end

        if not self:resolveReaverCharge(action, result) then
            return
        end

        local attackValue = result.testValue
        local baseInitiative = result.difficulty
        local defenderHasShield = target and self:entityHasShield(target)
        local targetRequiresExceed = self:mimicRequiresExceedInitiative(target)

        -- Check engagement (must be in same zone as target)
        if self.zoneSystem and target then
            local actorZone = action.actor.zone
            local targetZone = target.zone

            if actorZone ~= targetZone then
                result.success = false
                result.description = "Target is not engaged (different zone)"
                result.effects[#result.effects + 1] = "not_engaged"
                return
            end
        end

        self:breakLightSourceWeaponIfNeeded(action, result)
        self:applyPactItemObligations(action, result, self:getActionWeapon(action), "weapon_attack")

        -- S4.9: Check for and handle defensive actions
        local riposteTriggered = false
        local riposteDefense = nil

        local defense = self:consumeIncomingDefense(action, target)
        if defense then
            if defense.guardianAngel then
                result.effects[#result.effects + 1] = "guardian_angel_used"
            end
            if defense.source == "ally" then
                result.effects[#result.effects + 1] = "ally_defense_used"
            end
            if defense.type == "dodge" then
                -- Dodge: add card value to Initiative; if higher than attack value, miss
                local dodgeValue = defense.value or 0
                local newInitiative = baseInitiative + dodgeValue
                result.effects[#result.effects + 1] = "dodge_used"

                if newInitiative > attackValue then
                    result.success = false
                    result.description = "Dodged! "
                    result.effects[#result.effects + 1] = "dodged"
                    self:redirectMissedAttackToGrabbedVictim(action, result)
                    return
                else
                    result.effects[#result.effects + 1] = "dodge_failed"
                end
            elseif defense.type == "riposte" then
                -- Riposte: will counter-attack after resolution
                riposteTriggered = true
                riposteDefense = defense
                result.effects[#result.effects + 1] = "riposte_ready"
            end
        end

        -- Resolve hit against Initiative (ties go to attacker unless defender has shield)
        result.success = (attackValue > baseInitiative) or
                         (attackValue == baseInitiative and not defenderHasShield and not targetRequiresExceed)
        if targetRequiresExceed and attackValue == baseInitiative then
            result.effects[#result.effects + 1] = "mimic_tough_requires_exceed"
        end

        -- S7.6: Flail specialization - ties count as success
        if not result.success and not targetRequiresExceed and action.weapon and M.isWeaponType(action.weapon, "FLAIL") then
            if attackValue == baseInitiative then
                result.success = true
                result.description = "Flail tie-breaker! "
                result.effects[#result.effects + 1] = "flail_tie"
            end
        end

        if result.success then
            result.damageDealt = 1
            result.description = (result.description or "") .. "Hit! "

            -- S6.3: Form engagement on successful melee attack
            if target and action.actor then
                self:formEngagement(action.actor, target)
            end

            -- S7.6: Hammer/Mace specialization - double damage on overwhelming hit
            if action.weapon and M.isWeaponType(action.weapon, "HAMMER") then
                if result.testValue >= (result.difficulty * 2) then
                    result.damageDealt = 2
                    result.description = result.description .. "Crushing blow! "
                    result.effects[#result.effects + 1] = "hammer_crush"
                end
            end

            -- S7.6: Dagger specialization - piercing vs vulnerable targets
            if action.weapon and M.isWeaponType(action.weapon, "DAGGER") then
                if target and target.conditions then
                    if target.conditions.rooted or target.conditions.prone or target.conditions.disarmed then
                        result.effects[#result.effects + 1] = "piercing"
                        result.description = result.description .. "Exploits vulnerability! "
                    end
                end
            end

            -- Check for Great Success weapon bonus
            if result.isGreat and action.weapon then
                local weaponType = action.weapon.weaponType or action.weapon.type or action.weapon.name
                local bonus = M.WEAPON_BONUSES[weaponType:lower()]

                if bonus then
                    if bonus.great_bonus == "extra_wound" then
                        result.damageDealt = result.damageDealt + (bonus.wound_bonus or 1)
                        result.description = result.description .. "Great Success! +" .. bonus.wound_bonus .. " wound. "
                    elseif bonus.great_bonus == "stagger" then
                        result.effects[#result.effects + 1] = "stagger"
                        result.description = result.description .. "Great Success! Target staggered. "
                    elseif bonus.great_bonus == "pierce_armor" then
                        result.effects[#result.effects + 1] = "pierce_armor"
                        result.description = result.description .. "Great Success! Armor pierced. "
                    end
                end
            end

            self:applyAttackLesserDoom(action, result, target)
            self:applyAttackGreaterDoom(action, result, target)
            self:applyAmbusherDamageBonus(action, result)

            -- Apply damage to target (with weapon for cleave check)
            if target and result.damageDealt > 0 then
                self:applyDamage(target, result.damageDealt, result.effects, action.weapon, action.allEntities,
                    self:getActionWoundOptions(action, target), {
                        source = "attack",
                        action = action,
                        useAegis = action.useAegis,
                    })
            end
        else
            result.description = "Miss!"
            self:redirectMissedAttackToGrabbedVictim(action, result)
            if action.greaterDoom then
                result.description = result.description .. " " .. (action.greaterDoom.name or "Greater doom") .. " wasted."
                result.effects[#result.effects + 1] = "greater_doom_wasted"
            end
        end

        self:applyMaledictionWeaponRust(action, result)

        -- S4.9: Resolve Riposte counter-attack
        if riposteTriggered and riposteDefense and target then
            local riposteResult = self:resolveRiposte(target, action.actor, riposteDefense, attackValue)
            result.riposteResult = riposteResult
            result.description = result.description .. " Riposte! "
            if riposteResult.success then
                result.description = result.description .. "Counter-attack hits!"
            else
                result.description = result.description .. "Counter-attack misses."
            end
        end
    end

    --- Resolve missile attack
    function resolver:resolveMissile(action, result)
        -- S7.1: Apply any active aids to this attack
        self:applyActiveAids(action.actor, result)

        if not self:resolveReaverCharge(action, result) then
            return
        end

        -- S7.5: Ranged engagement penalty - shooting while engaged is hard
        if action.actor.is_engaged then
            result.modifier = result.modifier - 3
            result.testValue = result.cardValue + result.modifier
            result.description = "(Engaged -3) "
            result.effects[#result.effects + 1] = "engaged_ranged_penalty"
        end

        local attackValue = result.testValue
        local baseInitiative = result.difficulty
        local target = action.target
        local defenderHasShield = target and self:entityHasShield(target)
        local targetRequiresExceed = self:mimicRequiresExceedInitiative(target)
        local dodged = false
        local riposteTriggered = false
        local riposteDefense = nil
        local doomEyeActive = false
        local gramaryWandAttack = self:isGramaryWandAttack(action)

        if gramaryWandAttack then
            action.weapon = action.weapon or self:getGramaryWand(action)
            result.effects[#result.effects + 1] = "gramary_wand_attack"
            result.effects[#result.effects + 1] = "gramary_wands_action"
        end

        if self:wantsDoomEye(action) then
            local canUseDoomEye, doomEyeReason, doomEyeWeapon = self:canUseDoomEye(action)
            if not canUseDoomEye then
                result.success = false
                result.description = doomEyeReason
                result.effects[#result.effects + 1] = "doom_eye_blocked"
                return
            end

            doomEyeActive = true
            action.weapon = action.weapon or doomEyeWeapon
            result.doomEyeAutoHit = true
            result.effects[#result.effects + 1] = "doom_eye_auto_hit"
        end

        self:applyPactItemObligations(action, result, self:getActionWeapon(action), "weapon_attack")

        -- Dodge can negate missile attacks
        local defense = self:consumeIncomingDefense(action, target)
        if defense then
            if defense.guardianAngel then
                result.effects[#result.effects + 1] = "guardian_angel_used"
            end
            if defense.source == "ally" then
                result.effects[#result.effects + 1] = "ally_defense_used"
            end
            if defense.type == "dodge" then
                local dodgeValue = defense.value or 0
                local newInitiative = baseInitiative + dodgeValue
                result.effects[#result.effects + 1] = "dodge_used"

                if newInitiative > attackValue and not doomEyeActive then
                    dodged = true
                    result.success = false
                    result.description = "Dodged! "
                    result.effects[#result.effects + 1] = "dodged"
                elseif newInitiative > attackValue and doomEyeActive then
                    result.effects[#result.effects + 1] = "dodge_failed"
                    result.effects[#result.effects + 1] = "doom_eye_ignores_dodge"
                else
                    result.effects[#result.effects + 1] = "dodge_failed"
                end
            elseif defense.type == "riposte" then
                riposteTriggered = true
                riposteDefense = defense
                result.effects[#result.effects + 1] = "riposte_ready"
            end
        end

        if doomEyeActive then
            result.success = true
            result.effects[#result.effects + 1] = "doom_eye_ignores_initiative"
        elseif not dodged then
            -- Resolve hit against Initiative (ties go to attacker unless defender has shield)
            result.success = (attackValue > baseInitiative) or
                             (attackValue == baseInitiative and not defenderHasShield and not targetRequiresExceed)
            if targetRequiresExceed and attackValue == baseInitiative then
                result.effects[#result.effects + 1] = "mimic_tough_requires_exceed"
            end
        end

        -- S7.8: Crossbow must be loaded
        if action.weapon and M.isWeaponType(action.weapon, "CROSSBOW") then
            if not action.weapon.isLoaded then
                result.success = false
                result.description = (result.description or "") .. "Reload required!"
                result.effects[#result.effects + 1] = "not_loaded"
                return
            end
        end

        -- Check ammo
        if action.weapon and action.weapon.uses_ammo then
            local ammo = action.actor.ammo or 0
            if ammo <= 0 then
                result.success = false
                result.description = "Out of ammo!"
                result.effects[#result.effects + 1] = "no_ammo"
                return
            end

            -- Consume ammo
            action.actor.ammo = ammo - 1
            result.effects[#result.effects + 1] = "ammo_used"
        end

        -- Missile bypasses engagement - no zone check needed

        -- S7.8: Unload crossbow after firing
        if action.weapon and M.isWeaponType(action.weapon, "CROSSBOW") then
            action.weapon.isLoaded = false
            result.effects[#result.effects + 1] = "crossbow_fired"
        end

        if result.success then
            result.damageDealt = 1
            result.description = (result.description or "") .. "Hit! "

            -- Great Success bonuses (same as melee)
            if result.isGreat and action.weapon then
                local weaponType = action.weapon.weaponType or action.weapon.type or action.weapon.name or "bow"
                local bonus = M.WEAPON_BONUSES[weaponType:lower()]

                if bonus then
                    if bonus.great_bonus == "extra_wound" then
                        result.damageDealt = result.damageDealt + (bonus.wound_bonus or 1)
                        result.description = result.description .. "Great Success! "
                    elseif bonus.great_bonus == "pierce_armor" then
                        result.effects[#result.effects + 1] = "pierce_armor"
                        result.description = result.description .. "Armor pierced! "
                    end
                end
            end

            self:applyAttackLesserDoom(action, result, target)
            self:applyAmbusherDamageBonus(action, result)

            if action.target then
                self:applyDamage(action.target, result.damageDealt, result.effects, action.weapon, nil,
                    self:getActionWoundOptions(action, action.target), {
                        source = "attack",
                        action = action,
                        useAegis = action.useAegis,
                    })
            end
        else
            if not result.description or result.description == "" then
                result.description = "Miss!"
            end
            self:redirectMissedAttackToGrabbedVictim(action, result)
        end

        self:applyMaledictionWeaponRust(action, result)

        if riposteTriggered and riposteDefense and target then
            local riposteResult = self:resolveRiposte(target, action.actor, riposteDefense, attackValue)
            result.riposteResult = riposteResult
            result.description = result.description .. " Riposte! "
            if riposteResult.success then
                result.description = result.description .. "Counter-attack hits!"
            else
                result.description = result.description .. "Counter-attack misses."
            end
        end
    end

    ----------------------------------------------------------------------------
    -- RIPOSTE COUNTER-ATTACK (S4.9)
    ----------------------------------------------------------------------------

    --- Resolve a Riposte counter-attack
    -- @param defender table: Entity performing the riposte
    -- @param attacker table: Original attacker being counter-attacked
    -- @param defense table: The consumed defense { type, card, value }
    -- @return table: Result of the riposte attack
    function resolver:resolveRiposte(defender, attacker, defense, attackerValue)
        defender = (defense and defense.defender) or defender
        local riposteResult = {
            success = false,
            isGreat = false,
            damageDealt = 0,
            effects = {},
            description = "",
        }

        if not defender or not attacker or not defense then
            return riposteResult
        end

        -- Riposte uses the card that was prepared
        local card = defense.card
        local cardValue = defense.value or (card and card.value) or 0

        -- The prepared defense value already encodes the timing rule:
        -- turn actions include the attribute; minor actions use face value only.
        local testValue = cardValue

        local compareValue = attackerValue
        if not compareValue and attacker then
            compareValue = 10 + (attacker.pentacles or 0)
        end

        local attackerHasShield = attacker and self:entityHasShield(attacker)
        riposteResult.success = (testValue > compareValue) or
                                (testValue == compareValue and not attackerHasShield)

        if riposteResult.success then
            riposteResult.damageDealt = 1

            -- S7.6: Blade specialization - riposte deals 2 damage with swords
            if defender.weapon and M.isWeaponType(defender.weapon, "BLADE") then
                riposteResult.damageDealt = 2
                riposteResult.description = "Riposte connects with blade! (2 wounds)"
            else
                riposteResult.description = "Riposte connects!"
            end

            -- Apply damage to the original attacker
            self:applyDamage(attacker, riposteResult.damageDealt, riposteResult.effects, defender.weapon, nil, nil, {
                source = "attack",
                defense = defense,
                useAegis = attacker.autoUseAegis,
            })

            -- Emit event for visual feedback
            self.eventBus:emit("riposte_hit", {
                defender = defender,
                attacker = attacker,
                damage = riposteResult.damageDealt,
            })
        else
            riposteResult.description = "Riposte parried!"
        end

        return riposteResult
    end

    ----------------------------------------------------------------------------
    -- PENTACLES RESOLUTION (Roughhouse)
    ----------------------------------------------------------------------------

    function resolver:resolvePentaclesAction(action, result)
        local actionType = self:normalizeActionType(action.type or M.ACTION_TYPES.TRIP)

        if actionType == M.ACTION_TYPES.ROUGHHOUSE then
            self:resolveRoughhouse(action, result)
        elseif actionType == M.ACTION_TYPES.TRIP then
            self:resolveTrip(action, result)
        elseif actionType == M.ACTION_TYPES.DISARM then
            self:resolveDisarm(action, result)
        elseif actionType == M.ACTION_TYPES.DISPLACE then
            self:resolveDisplace(action, result)
        elseif actionType == M.ACTION_TYPES.GRAPPLE then
            -- S7.2: Grapple sets rooted condition
            self:resolveGrapple(action, result)
        elseif actionType == M.ACTION_TYPES.AVOID then
            -- S6.3: Avoid action to escape engagement
            self:resolveAvoid(action, result)
        elseif actionType == M.ACTION_TYPES.DASH then
            -- S6.3: Dash is a Pentacles-based quick move
            self:resolveDash(action, result, action.allEntities)
        else
            self:resolveTrip(action, result)  -- Default
        end
    end

    function resolver:normalizeRoughhouseEffect(effect)
        effect = tostring(effect or ""):lower()
        effect = effect:gsub("[’']", "")
        effect = effect:gsub("%s+", "_")
        effect = effect:gsub("[^%w_]", "")

        if effect == "grapple" or effect == "rooted" then
            return "root"
        end
        if effect == "griffin_grab" then
            return "grab"
        end
        if effect == "bad_little_hands" or effect == "roughhouse_steal_belt_item" or
           effect == "steal_belt" or effect == "steal_belt_item" then
            return "steal_belt_item"
        end
        if effect == "push" or effect == "push_back" then
            return "displace"
        end
        if effect == "exhausted" then
            return "exhaust"
        end
        if effect == "notch_item" or effect == "damage_item" or effect == "break_item" then
            return "notch"
        end
        if effect == "silenced" then
            return "silence"
        end
        if effect == "" then
            return "trip"
        end

        return effect
    end

    function resolver:isFightDirtyRoughhouseEffect(effect)
        return effect == "exhaust" or effect == "notch" or effect == "silence"
    end

    function resolver:resolveGriffinGrab(action, result)
        local actor = action.actor
        local target = action.target

        if not actor or not target then
            result.success = false
            result.description = "No target to grab!"
            result.effects[#result.effects + 1] = "griffin_grab_blocked"
            return
        end
        if self:requiresGreaterDoomForGriffinGrab(action) then
            result.success = false
            result.description = "Griffin Grab requires a greater doom."
            result.effects[#result.effects + 1] = "griffin_grab_requires_greater_doom"
            return
        end

        local contest = self:resolveInitiativeContest(action, result, {
            tieWins = false,
        })

        if contest.dodged then
            return
        end

        if result.success then
            self:applyRooted(target, { action = action, reason = "griffin_grab" })

            local heightFeet = action.heightFeet or action.roomHeightFeet or action.fallHeightFeet
            local isFlying = actor.flying == true or action.flying == true or action.flyByAttack == true or
                (actor.conditions and actor.conditions.flying == true)
            actor.grabbedVictim = target
            actor.griffinGrab = {
                victim = target,
                targetMovesWithActor = true,
                missedAttacksHitGrabbedVictim = true,
                flying = isFlying,
                heightFeet = heightFeet,
            }

            target.griffinGrabbedBy = actor
            target.griffinGrabbedById = actor.id
            target.griffinGrabbedByName = actor.name
            target.griffinGrabMovesWith = actor
            target.griffinGrabRecoverCausesFallingDamage = isFlying
            target.griffinGrabFallHeightFeet = heightFeet
            target.rootedBy = "griffin_grab"

            result.description = "Grabbed! Target is Rooted and moves with the griffin."
            result.effects[#result.effects + 1] = "griffin_grab"
            result.effects[#result.effects + 1] = "rooted"
            result.effects[#result.effects + 1] = "target_moves_with_griffin"
            if isFlying then
                result.effects[#result.effects + 1] = "griffin_grab_flying"
            end
        else
            result.description = "Failed to grab!"
        end

        self:appendRoughhouseRiposte(action, result, contest)
    end

    function resolver:resolveStealBeltItem(action, result)
        local actor = action.actor
        local target = action.target

        if not actor or not target then
            result.success = false
            result.description = "No target to steal from!"
            result.effects[#result.effects + 1] = "bad_little_hands_blocked"
            return
        end
        if not self:isBadLittleHandsRoughhouse(action, "steal_belt_item") then
            result.success = false
            result.description = "Bad Little Hands is a Face Rat lesser doom."
            result.effects[#result.effects + 1] = "bad_little_hands_requires_face_rat"
            return
        end

        local contest = self:resolveInitiativeContest(action, result, {
            tieWins = false,
        })

        if contest.dodged then
            return
        end

        if result.success then
            local item, location, itemReason = self:getBadLittleHandsTargetItem(action)
            if not item then
                result.success = false
                result.description = "No belt item to steal!"
                result.effects[#result.effects + 1] = "bad_little_hands_no_belt_item"
                result.badLittleHandsFailure = itemReason
            else
                local stolen = nil
                if target.inventory and target.inventory.removeItem and item.id then
                    stolen = target.inventory:removeItem(item.id)
                end
                stolen = stolen or item

                local record = self:recordBadLittleHandsItem(actor, target, stolen, location, action)
                result.description = "Bad Little Hands steals [" .. (stolen.name or "belt item") .. "]!"
                result.effects[#result.effects + 1] = "bad_little_hands"
                result.effects[#result.effects + 1] = "belt_item_stolen"
                result.stolenItem = stolen
                result.stolenItemRecord = record

                self.eventBus:emit(events.EVENTS.INVENTORY_CHANGED, {
                    entity = target,
                    item = stolen,
                    reason = "bad_little_hands_stolen",
                    source = actor,
                })
            end
        else
            result.description = "Failed to steal belt item!"
        end

        self:appendRoughhouseRiposte(action, result, contest)
    end

    function resolver:resolveRoughhouse(action, result)
        local effect = self:normalizeRoughhouseEffect(
            action.roughhouseEffect or action.effect or action.maneuver or action.outcome
        )
        result.roughhouseEffect = effect
        result.effects[#result.effects + 1] = "roughhouse"
        result.effects[#result.effects + 1] = "roughhouse_" .. effect

        if self:isGriffinGrabRoughhouse(action, effect) then
            return self:resolveGriffinGrab(action, result)
        end
        if effect == "steal_belt_item" then
            return self:resolveStealBeltItem(action, result)
        end

        if self:isFightDirtyRoughhouseEffect(effect) and not entityHasUsableTalent(action.actor, "fight_dirty") then
            result.success = false
            result.description = "Requires Fight Dirty."
            result.effects[#result.effects + 1] = "fight_dirty_required"
            return
        end

        if targetRequiresGiantSizeToRoughhouse(action.target) and not actionCanAffectGiantSizedTarget(action) then
            result.success = false
            result.description = "Target is too huge to Roughhouse."
            result.effects[#result.effects + 1] = "roughhouse_target_too_huge"
            result.effects[#result.effects + 1] = "roughhouse_requires_giant_size"
            return
        end

        if effect == "trip" then
            self:resolveTrip(action, result)
        elseif effect == "disarm" then
            self:resolveDisarm(action, result)
        elseif effect == "displace" then
            self:resolveDisplace(action, result)
        elseif effect == "root" then
            self:resolveRoot(action, result)
        elseif effect == "exhaust" then
            self:resolveExhaust(action, result)
        elseif effect == "notch" then
            self:resolveNotch(action, result)
        elseif effect == "silence" then
            self:resolveSilence(action, result)
        else
            result.success = false
            result.description = "Unknown Roughhouse effect: " .. tostring(effect)
            result.effects[#result.effects + 1] = "roughhouse_effect_unknown"
        end
    end

    function resolver:resolveTrip(action, result)
        local contest = self:resolveInitiativeContest(action, result, {
            tieWins = false,
        })

        if contest.dodged then
            return
        end

        if result.success then
            result.description = "Knocked down!"
            result.effects[#result.effects + 1] = "prone"

            if action.target then
                action.target.conditions = action.target.conditions or {}
                action.target.conditions.prone = true
            end
            self:clearAllEngagements(action.target, action.allEntities)
        else
            result.description = "Failed to trip!"
        end

        if contest.riposteTriggered and contest.riposteDefense and action.target then
            local riposteResult = self:resolveRiposte(action.target, action.actor, contest.riposteDefense, contest.attackValue)
            result.riposteResult = riposteResult
            result.description = result.description .. " Riposte! "
            if riposteResult.success then
                result.description = result.description .. "Counter-attack hits!"
            else
                result.description = result.description .. "Counter-attack misses."
            end
        end
    end

    --- S7.3: Disarm with inventory drop
    function resolver:resolveDisarm(action, result)
        local target = action.target

        if not target then
            result.success = false
            result.description = "No target to disarm!"
            return
        end

        local contest = self:resolveInitiativeContest(action, result, {
            tieWins = false,
        })

        if contest.dodged then
            return
        end

        -- Check if target has anything in hands or Face Rat Bad Little Hands.
        local droppedItem = nil
        local badLittleHandsItem = self:peekBadLittleHandsItem(target)
        if target.inventory and target.inventory.getItems then
            local handsItems = target.inventory:getItems("hands")
            if handsItems and #handsItems > 0 then
                droppedItem = handsItems[1]
            end
        elseif target.weapon then
            droppedItem = target.weapon
        end

        if result.success then
            if badLittleHandsItem then
                local recovery = self:releaseBadLittleHandsItem(target, "disarm")
                local recoveredItem = recovery and recovery.item or badLittleHandsItem
                result.description = "Disarmed stolen [" .. (recoveredItem.name or "item") .. "] from Bad Little Hands!"
                result.effects[#result.effects + 1] = "disarmed"
                result.effects[#result.effects + 1] = "bad_little_hands_item_recovered"
                result.effects[#result.effects + 1] = "belt_item_recovered"
                result.recoveredItem = recoveredItem
                result.recovery = recovery

                -- Set disarmed condition on target
                if target.conditions then
                    target.conditions.disarmed = true
                end
            elseif droppedItem then
                droppedItem = self:dropCarriedItem(target, droppedItem, "disarm", action)
                result.description = "Disarmed [" .. (droppedItem.name or "item") .. "]!"
                result.effects[#result.effects + 1] = "disarmed"
                result.droppedItem = droppedItem

                -- Set disarmed condition on target
                if target.conditions then
                    target.conditions.disarmed = true
                end
            else
                -- Can't disarm someone with nothing in hands
                result.success = false
                result.description = "Target has nothing to disarm!"
            end
        else
            result.description = "Failed to disarm!"
        end

        if contest.riposteTriggered and contest.riposteDefense and target then
            local riposteResult = self:resolveRiposte(target, action.actor, contest.riposteDefense, contest.attackValue)
            result.riposteResult = riposteResult
            result.description = result.description .. " Riposte! "
            if riposteResult.success then
                result.description = result.description .. "Counter-attack hits!"
            else
                result.description = result.description .. "Counter-attack misses."
            end
        end
    end

    --- S7.2: Grapple sets rooted condition
    function resolver:resolveGrapple(action, result)
        local target = action.target

        if not target then
            result.success = false
            result.description = "No target to grapple!"
            return
        end

        local contest = self:resolveInitiativeContest(action, result, {
            tieWins = false,
        })

        if contest.dodged then
            return
        end

        if result.success then
            result.description = "Grappled! Target is rooted."
            result.effects[#result.effects + 1] = "grappled"
            result.effects[#result.effects + 1] = "rooted"

            -- Set rooted condition on target
            if target.conditions then
                target.conditions.rooted = true
            else
                target.conditions = { rooted = true }
            end

            -- Also form engagement
            self:formEngagement(action.actor, target)
        else
            result.description = "Failed to grapple!"
        end

        if contest.riposteTriggered and contest.riposteDefense and target then
            local riposteResult = self:resolveRiposte(target, action.actor, contest.riposteDefense, contest.attackValue)
            result.riposteResult = riposteResult
            result.description = result.description .. " Riposte! "
            if riposteResult.success then
                result.description = result.description .. "Counter-attack hits!"
            else
                result.description = result.description .. "Counter-attack misses."
            end
        end
    end

    function resolver:resolveRoot(action, result)
        local target = action.target

        if not target then
            result.success = false
            result.description = "No target to root!"
            return
        end

        local contest = self:resolveInitiativeContest(action, result, {
            tieWins = false,
        })

        if contest.dodged then
            return
        end

        if result.success then
            result.description = "Rooted!"
            result.effects[#result.effects + 1] = "rooted"
            self:applyRooted(target, { action = action, reason = "roughhouse_root" })
        else
            result.description = "Failed to root!"
        end

        if contest.riposteTriggered and contest.riposteDefense and target then
            local riposteResult = self:resolveRiposte(target, action.actor, contest.riposteDefense, contest.attackValue)
            result.riposteResult = riposteResult
            result.description = result.description .. " Riposte! "
            if riposteResult.success then
                result.description = result.description .. "Counter-attack hits!"
            else
                result.description = result.description .. "Counter-attack misses."
            end
        end
    end

    function resolver:appendRoughhouseRiposte(action, result, contest)
        if contest.riposteTriggered and contest.riposteDefense and action.target then
            local riposteResult = self:resolveRiposte(action.target, action.actor, contest.riposteDefense, contest.attackValue)
            result.riposteResult = riposteResult
            result.description = result.description .. " Riposte! "
            if riposteResult.success then
                result.description = result.description .. "Counter-attack hits!"
            else
                result.description = result.description .. "Counter-attack misses."
            end
        end
    end

    function resolver:resolveFightDirtyCondition(action, result, condition, effectName, successText, failureText)
        local target = action.target

        if not target then
            result.success = false
            result.description = "No target!"
            return
        end

        local contest = self:resolveInitiativeContest(action, result, {
            tieWins = false,
        })

        if contest.dodged then
            return
        end

        if result.success then
            target.conditions = target.conditions or {}
            target.conditions[condition] = true
            result.description = successText
            result.effects[#result.effects + 1] = effectName
        else
            result.description = failureText
        end

        self:appendRoughhouseRiposte(action, result, contest)
    end

    function resolver:resolveExhaust(action, result)
        self:resolveFightDirtyCondition(action, result, "exhausted", "exhausted", "Exhausted!", "Failed to exhaust!")
    end

    function resolver:resolveSilence(action, result)
        self:resolveFightDirtyCondition(action, result, "silenced", "silenced", "Silenced!", "Failed to silence!")
    end

    function resolver:getRoughhouseNotchItem(action)
        local target = action and action.target
        if not target then
            return nil
        end
        if action.targetItem then
            return action.targetItem
        end

        local itemId = action.targetItemId or action.itemId
        if itemId and target.inventory and target.inventory.findItem then
            local item = target.inventory:findItem(itemId)
            if item then
                return item
            end
        end

        if target.inventory and target.inventory.getItems then
            local handItems = target.inventory:getItems("hands")
            if handItems and #handItems > 0 then
                return handItems[1]
            end
        end

        return target.weapon
    end

    function resolver:resolveNotch(action, result)
        local target = action.target

        if not target then
            result.success = false
            result.description = "No target to Notch!"
            return
        end

        local contest = self:resolveInitiativeContest(action, result, {
            tieWins = false,
        })

        if contest.dodged then
            return
        end

        if result.success then
            if self:isMimicTarget(target) then
                local wounds = target.mimic and target.mimic.treatsNotchesAsWounds or 2
                result.description = "Notched mimic for " .. tostring(wounds) .. " Wounds!"
                result.effects[#result.effects + 1] = "mimic_construct_notch_wounds"
                result.effects[#result.effects + 1] = "mimic_notched"
                result.damageDealt = wounds
                self:applyDamage(target, wounds, result.effects, nil, action.allEntities, nil, {
                    source = "notch",
                    action = action,
                })
                self:appendRoughhouseRiposte(action, result, contest)
                return
            end

            local item = self:getRoughhouseNotchItem(action)
            if item then
                local notchResult = inventory.addNotch(item)
                result.description = "Notched " .. (item.name or "item") .. "!"
                result.effects[#result.effects + 1] = "item_notched"
                if notchResult == "destroyed" then
                    result.effects[#result.effects + 1] = "item_destroyed"
                end
                result.itemNotchResult = notchResult
                result.notchedItem = item
            else
                result.success = false
                result.description = "No target item to Notch!"
                result.effects[#result.effects + 1] = "no_item_to_notch"
            end
        else
            result.description = "Failed to Notch!"
        end

        self:appendRoughhouseRiposte(action, result, contest)
    end

    function resolver:resolveDisplace(action, result)
        local contest = self:resolveInitiativeContest(action, result, {
            tieWins = false,
        })

        if contest.dodged then
            return
        end

        if result.success then
            result.description = "Pushed back!"
            result.effects[#result.effects + 1] = "displaced"

            -- Would move target to adjacent zone
            if action.target and action.destinationZone then
                action.target.zone = action.destinationZone
            end

            self:clearAllEngagements(action.target, action.allEntities)
        else
            result.description = "Failed to push!"
        end

        if contest.riposteTriggered and contest.riposteDefense and action.target then
            local riposteResult = self:resolveRiposte(action.target, action.actor, contest.riposteDefense, contest.attackValue)
            result.riposteResult = riposteResult
            result.description = result.description .. " Riposte! "
            if riposteResult.success then
                result.description = result.description .. "Counter-attack hits!"
            else
                result.description = result.description .. "Counter-attack misses."
            end
        end
    end

    ----------------------------------------------------------------------------
    -- CUPS RESOLUTION (Support/Social)
    ----------------------------------------------------------------------------

    function resolver:resolveCupsAction(action, result)
        local actionType = self:normalizeActionType(action.type or M.ACTION_TYPES.AID)

        if actionType == M.ACTION_TYPES.DODGE then
            -- S4.9: Prepare Dodge defense
            self:resolveDodge(action, result)
        elseif actionType == M.ACTION_TYPES.RIPOSTE then
            -- S4.9: Prepare Riposte defense
            self:resolveRipostePrepare(action, result)
        elseif actionType == M.ACTION_TYPES.HEAL then
            self:resolveHeal(action, result)
        elseif actionType == M.ACTION_TYPES.COMMAND then
            self:resolveCommand(action, result)
        elseif actionType == M.ACTION_TYPES.PARLEY then
            self:resolveParley(action, result)
        elseif actionType == M.ACTION_TYPES.RALLY then
            self:resolveRally(action, result)
        elseif actionType == M.ACTION_TYPES.USE_ITEM then
            self:resolveUseItem(action, result)
        elseif actionType == M.ACTION_TYPES.PULL_ITEM then
            self:resolvePullItemFromPack(action, result)
        elseif actionType == M.ACTION_TYPES.SHIELD then
            result.success = true
            result.description = "Shielding " .. (action.target and action.target.name or "ally")
            result.effects[#result.effects + 1] = "shielding"
        elseif actionType == M.ACTION_TYPES.AID then
            -- S7.1: Aid Another
            self:resolveAidAnother(action, result)
        else
            self:resolveGenericAction(action, result)
        end
    end

    --- S7.1: Aid Another - bank a bonus for an ally's next action
    function resolver:resolveAidAnother(action, result)
        local actor = action.actor
        local target = action.target

        if not target then
            result.success = false
            result.description = "No ally to aid!"
            return
        end

        if not target.isPC and actor.isPC then
            result.success = false
            result.description = "Can only aid allies!"
            return
        end

        -- Aid always succeeds (no test required)
        result.success = true

        -- Calculate bonus from resolved action value (respects minor-action rules)
        local totalBonus = result.testValue or (action.card and action.card.value) or 0

        -- Register the aid for the target
        self:registerAid(target, totalBonus, actor.name or "ally")

        result.description = "Aided " .. (target.name or "ally") .. "! (+" .. totalBonus .. " to next action)"
        result.effects[#result.effects + 1] = "aid_banked"
    end

    function resolver:normalizeCommandName(commandName)
        commandName = tostring(commandName or ""):lower()
        commandName = commandName:gsub("[’']", "")
        commandName = commandName:gsub("%s+", "_")
        commandName = commandName:gsub("[^%w_]", "")

        if commandName == "sic_em" or commandName == "sicem" or commandName == "attack" then
            return "sic_em"
        elseif commandName == "get_help" or commandName == "gethelp" then
            return "get_help"
        elseif commandName == "do_a_trick" or commandName == "do_trick" or commandName == "trick" then
            return "do_a_trick"
        end

        return commandName
    end

    function resolver:getCommandCompanion(actor, action)
        if not actor then
            return nil
        end

        if action.companion then
            return action.companion
        end

        local companionId = action.companionId
        for _, collection in ipairs({ actor.companions or false, actor.animalCompanions or false }) do
            if type(collection) == "table" then
                for key, companion in pairs(collection) do
                    if type(companion) == "table" then
                        if not companionId or companion.id == companionId or key == companionId then
                            return companion
                        end
                    end
                end
            end
        end

        return actor.companion
    end

    function resolver:companionKnowsCommand(companion, commandName)
        if not commandName or commandName == "" then
            return true
        end
        if companion and (companion.commandsAny or companion.obeysMostCommands) then
            return true
        end

        local commands = companion and (companion.knownCommands or companion.commands)
        if not commands then
            return true
        end

        for key, value in pairs(commands) do
            if type(value) == "string" then
                if self:normalizeCommandName(value) == commandName then
                    return true
                end
            elseif type(value) == "table" then
                if self:normalizeCommandName(value.id or value.name) == commandName then
                    return true
                end
            elseif value and self:normalizeCommandName(key) == commandName then
                return true
            end
        end

        return false
    end

    function resolver:companionAllowsSpokenCommand(companion, rawCommand)
        if not companion or not companion.oneWordCommandsOnly then
            return true
        end

        local text = tostring(rawCommand or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if text == "" then
            return false
        end
        return text:find("[%s_]") == nil
    end

    function resolver:canCommandCompanion(companion)
        if not companion then
            return false, "No companion to command."
        end

        local conditions = companion.conditions or {}
        if conditions.dead then
            return false, "Companion is dead."
        end
        if companion.weak or companion.starving or conditions.weak or conditions.starving then
            return false, "Companion is weak and cannot be commanded."
        end

        return true, nil
    end

    local function removeCompanionFromActor(actor, companion)
        if not actor or not companion or type(actor.companions) ~= "table" then
            return false
        end

        local removed = false
        for key, entry in pairs(actor.companions) do
            if entry == companion then
                actor.companions[key] = nil
                removed = true
            end
        end
        if actor.companion == companion then
            actor.companion = nil
        end
        return removed
    end

    function resolver:recordBoundZombieService(companion, action, result)
        local binding = companion and companion.raiseZombie
        if not binding or binding.active == false then
            return nil
        end

        binding.servicesCompleted = (binding.servicesCompleted or 0) + 1
        binding.servicesRemaining = math.max(0, (binding.servicesRemaining or 0) - 1)
        companion.zombieServicesCompleted = binding.servicesCompleted
        companion.zombieServicesRemaining = binding.servicesRemaining
        result.effects[#result.effects + 1] = "bound_zombie_service_spent"
        result.boundZombieServicesRemaining = binding.servicesRemaining

        if binding.servicesRemaining <= 0 then
            binding.completed = true
            local ended = self:endOngoingSpell(binding.caster, binding.spellEntry or {
                spellId = "raise_zombie",
                target = companion,
                raisedZombie = companion,
            }, "raise_zombie_services_completed", {
                source = action,
            })
            result.endedSpell = ended
            result.effects[#result.effects + 1] = "raise_zombie_services_completed"
            return ended
        end

        return nil
    end

    function resolver:isContestedCommand(actor, target, action)
        if action and action.contestedCommand ~= nil then
            return action.contestedCommand
        end
        if not target or target == actor then
            return false
        end
        if actor and target and actor.isPC ~= nil and target.isPC ~= nil then
            return actor.isPC ~= target.isPC
        end
        return true
    end

    function resolver:applyCompanionCommand(action, result, companion, commandName)
        local actor = action.actor
        local target = action.target

        companion.lastCommand = commandName
        companion.commandedThisRound = true
        companion.currentCommand = {
            command = commandName,
            actor = actor,
            target = target,
            item = action.item,
        }

        if commandName == "sic_em" then
            if not target then
                result.success = false
                result.description = "No target for Sic 'Em."
                result.effects[#result.effects + 1] = "command_target_missing"
                return
            end

            local damage = action.commandDamage or companion.damage or 1
            result.damageDealt = damage
            result.effects[#result.effects + 1] = "companion_attack"
            self:applyDamage(target, damage, action.commandDamageEffects or {}, nil, action.allEntities,
                self:getActionWoundOptions(action, target), {
                    source = "attack",
                    action = action,
                    useAegis = action.useAegis,
                })

            if companion.zone and target.zone then
                self:formEngagement(companion, target)
            end

            result.description = (companion.name or "Companion") .. " attacks " .. (target.name or "target") .. "."
        elseif commandName == "fetch" then
            result.fetchedItem = action.item
            result.effects[#result.effects + 1] = "companion_fetch"
            if action.item then
                result.description = (companion.name or "Companion") .. " fetches " .. (action.item.name or "item") .. "."
            else
                result.description = (companion.name or "Companion") .. " starts fetching."
            end
        elseif commandName == "guard" then
            companion.guarding = action.commandTarget or target or actor
            result.effects[#result.effects + 1] = "companion_guard"
            result.description = (companion.name or "Companion") .. " guards " .. (companion.guarding.name or "the area") .. "."
        elseif commandName == "heel" or commandName == "stay" then
            companion.zone = actor and actor.zone or companion.zone
            result.effects[#result.effects + 1] = "companion_positioned"
            result.description = (companion.name or "Companion") .. " obeys " .. commandName:gsub("_", " ") .. "."
        else
            result.effects[#result.effects + 1] = "companion_command"
            result.description = (companion.name or "Companion") .. " follows the command."
        end

        if result.success ~= false then
            self:recordBoundZombieService(companion, action, result)
        end
    end

    function resolver:resolveCommand(action, result)
        local actor = action.actor
        local target = action.target
        local companion = self:getCommandCompanion(actor, action)
        local canCommand, blockReason = self:canCommandCompanion(companion)

        if not canCommand then
            result.success = false
            result.description = blockReason
            result.effects[#result.effects + 1] = "command_blocked"
            return
        end

        local rawCommand = action.commandName or action.command or "command"
        if not self:companionAllowsSpokenCommand(companion, rawCommand) then
            result.success = false
            result.description = (companion.name or "Companion") .. " only understands one-word commands."
            result.effects[#result.effects + 1] = "command_too_complex"
            return
        end

        local commandName = self:normalizeCommandName(rawCommand)
        if not self:companionKnowsCommand(companion, commandName) then
            result.success = false
            result.description = (companion.name or "Companion") .. " does not know " .. commandName:gsub("_", " ") .. "."
            result.effects[#result.effects + 1] = "unknown_command"
            return
        end

        local contest = nil
        if self:isContestedCommand(actor, target, action) then
            contest = self:resolveInitiativeContest(action, result, {
                tieWins = true,
                considerShield = true,
            })
        else
            result.success = true
        end

        if result.success then
            result.effects[#result.effects + 1] = "commanded"
            result.companion = companion
            result.commandName = commandName
            self:applyCompanionCommand(action, result, companion, commandName)
        else
            result.description = "Command resisted."
        end

        if contest and contest.riposteTriggered and contest.riposteDefense and target then
            local riposteResult = self:resolveRiposte(target, actor, contest.riposteDefense, contest.attackValue)
            result.riposteResult = riposteResult
            result.description = result.description .. " Riposte! "
            if riposteResult.success then
                result.description = result.description .. "Counter-attack hits!"
            else
                result.description = result.description .. "Counter-attack misses."
            end
        end
    end

    function resolver:resolveParley(action, result)
        local target = action.target
        if not target then
            result.success = false
            result.description = "No target to parley with."
            return
        end
        if applyRhymedSpeechSocialGate(action, result) then
            return
        end
        if applyLockedSpeechSocialGate(action, result, target) then
            return
        end

        self:applyPreparedRoomSocialEffects(action, result, target)

        -- Parley requires exceeding the social difficulty, matching Banter semantics.
        applyMaledictionSocialModifier(action, result, target)
        applyPactSocialModifier(action, result)
        applySocialPactBreaks(self, action, result)
        result.success = result.testValue > result.difficulty

        self.eventBus:emit("social_discovery", {
            target = target,
            targetId = target.id,
            discoveries = { "disposition", "morale" },
        })

        if result.success then
            local oldDisposition = target.getDisposition and target:getDisposition() or target.disposition
            local oldDispositionSeverity = target.getDispositionSeverity and target:getDispositionSeverity()
                or target.dispositionSeverity
                or 2
            local newDisposition = oldDisposition or "distaste"
            local newDispositionSeverity = oldDispositionSeverity
            local dispositionChange = "held"

            if disposition_module and disposition_module.moveTowardState and disposition_module.DISPOSITIONS then
                newDisposition, newDispositionSeverity, dispositionChange = disposition_module.moveTowardState(
                    newDisposition,
                    oldDispositionSeverity,
                    disposition_module.DISPOSITIONS.TRUST,
                    1
                )
            elseif target.shiftDisposition then
                target:shiftDisposition(1, 1)
                newDisposition = target.getDisposition and target:getDisposition() or target.disposition
            end

            if target.setDisposition then
                target:setDisposition(newDisposition, newDispositionSeverity)
            else
                target.disposition = newDisposition
                target.dispositionSeverity = newDispositionSeverity
            end
            self:endCharmForDispositionChange(
                target,
                oldDisposition,
                newDisposition,
                action,
                oldDispositionSeverity,
                newDispositionSeverity)

            result.oldDisposition = oldDisposition
            result.oldDispositionSeverity = oldDispositionSeverity
            result.newDisposition = newDisposition
            result.newDispositionSeverity = newDispositionSeverity
            result.newDispositionLabel = disposition_module.getDispositionLabel(newDisposition, newDispositionSeverity)
            result.dispositionTarget = disposition_module.DISPOSITIONS.TRUST
            result.dispositionChange = dispositionChange
            applySocialOutcomeToResult(result, target,
                disposition_module.getSocialOutcome(newDisposition, newDispositionSeverity))

            result.description = "Parley gains ground."
            result.effects[#result.effects + 1] = "parley_progress"
        else
            local oldDisposition = target.getDisposition and target:getDisposition() or target.disposition or "distaste"
            local oldDispositionSeverity = target.getDispositionSeverity and target:getDispositionSeverity()
                or target.dispositionSeverity
                or 2
            local newDisposition, newDispositionSeverity, dispositionChange = disposition_module.moveTowardState(
                oldDisposition,
                oldDispositionSeverity,
                disposition_module.DISPOSITIONS.ANGER,
                1)
            if target.setDisposition then
                target:setDisposition(newDisposition, newDispositionSeverity)
            else
                target.disposition = newDisposition
                target.dispositionSeverity = newDispositionSeverity
            end
            self:endCharmForDispositionChange(
                target,
                oldDisposition,
                newDisposition,
                action,
                oldDispositionSeverity,
                newDispositionSeverity)
            result.oldDisposition = oldDisposition
            result.oldDispositionSeverity = oldDispositionSeverity
            result.newDisposition = newDisposition
            result.newDispositionSeverity = newDispositionSeverity
            result.newDispositionLabel = disposition_module.getDispositionLabel(newDisposition, newDispositionSeverity)
            result.dispositionTarget = disposition_module.DISPOSITIONS.ANGER
            result.dispositionChange = dispositionChange
            applySocialOutcomeToResult(result, target,
                disposition_module.getSocialOutcome(newDisposition, newDispositionSeverity))
            result.description = "Parley fails to persuade."
        end
    end

    function resolver:resolveRally(action, result)
        local target = action.target or action.actor
        if not target then
            result.success = false
            result.description = "No ally to rally."
            return
        end

        if not result.success then
            result.description = "Rally falters."
            return
        end

        local cleared = nil
        if target.conditions then
            if target.conditions.stressed then
                target.conditions.stressed = false
                cleared = "stressed"
            elseif target.conditions.frightened then
                target.conditions.frightened = false
                cleared = "frightened"
            elseif target.conditions.deaf then
                target.conditions.deaf = false
                cleared = "deaf"
            elseif target.conditions.blind then
                target.conditions.blind = false
                cleared = "blind"
            end
        end

        if target.modifyMorale then
            target:modifyMorale(1)
        end

        if cleared then
            result.description = "Rallied " .. (target.name or "ally") .. " (" .. cleared .. " cleared)."
            result.effects[#result.effects + 1] = "rally_" .. cleared
        else
            result.description = "Rallied " .. (target.name or "ally") .. "."
            result.effects[#result.effects + 1] = "rally_boost"
        end
    end

    function resolver:getItemUseEffect(item)
        local props = item and item.properties or {}
        if props.useEffect then
            return props.useEffect
        end
        if props.challengeEffect then
            return props.challengeEffect
        end

        if props.effect == "heal_wound" then
            return { type = "heal_wound", target = "self_or_target" }
        elseif props.effect == "cure_poison" then
            return {
                type = "clear_conditions",
                target = "self_or_target",
                conditions = { "poisoned", "poison" },
                successMessage = "Poison cured.",
            }
        end

        return nil
    end

    function resolver:getItemEffectTarget(action, effect)
        local targetMode = effect and effect.target or "self_or_target"

        if targetMode == "self" or targetMode == "actor" then
            return action.actor
        elseif targetMode == "target" then
            return action.target
        elseif targetMode == "self_or_target" then
            return action.target or action.actor
        end

        return action.target or action.actor
    end

    function resolver:isContestedItemUse(actor, target, item, action)
        if action and action.contestedUseItem ~= nil then
            return action.contestedUseItem
        end
        if not target or target == actor then
            return false
        end

        local props = item and item.properties or {}
        if props.bomb or props.offensive or props.hostileUse then
            return true
        end

        if actor and target and actor.isPC ~= nil and target.isPC ~= nil then
            return actor.isPC ~= target.isPC
        end

        return false
    end

    function resolver:shouldConsumeItemOnUse(item, result, attempted)
        local props = item and item.properties or {}

        if props.consumeOnAttempt then
            return attempted
        end
        if props.consumeOnMiss and attempted and not result.success then
            return true
        end
        if props.consumable or props.potion or props.bomb or props.oil or props.alchemical then
            return result.success
        end

        return false
    end

    function resolver:consumeUsedItem(inventory, item, result)
        if not inventory or not item then
            return
        end

        local ok = false
        if item.stackable and inventory.removeItemQuantity then
            ok = inventory:removeItemQuantity(item.id, 1)
        elseif inventory.removeItem then
            local removed = inventory:removeItem(item.id)
            ok = removed ~= nil
        end

        if ok then
            item.destroyed = true
            result.consumedItem = item
            result.effects[#result.effects + 1] = "item_consumed"
        end
    end

    function resolver:clearTargetConditions(target, conditionList)
        if not target then
            return nil
        end

        target.conditions = target.conditions or {}
        for _, condition in ipairs(conditionList or {}) do
            if target.conditions[condition] then
                target.conditions[condition] = false
                return condition
            end
        end

        return nil
    end

    function resolver:destroyTargetArmor(target, result)
        if not target then
            return false
        end

        local destroyed = false

        if target.isPC then
            if (target.armorSlots or 0) > 0 or (target.armorNotches or 0) > 0 then
                target.armorSlots = 0
                target.armorNotches = 0
                target.armorDestroyed = true
                destroyed = true
            end
        else
            if (target.npcDefense or 0) > 0 or (target.npcMaxDefense or 0) > 0 then
                target.npcDefense = 0
                target.npcMaxDefense = 0
                destroyed = true
            end
        end

        if destroyed then
            result.effects[#result.effects + 1] = "armor_destroyed"
        end

        return destroyed
    end

    local function tableContainsValue(list, value)
        if type(list) ~= "table" then
            return false
        end

        for _, entry in ipairs(list) do
            if entry == value then
                return true
            end
        end

        return false
    end

    local function hasTag(entity, tag)
        local tags = entity and entity.tags
        if type(tags) == "table" then
            if tags[tag] then
                return true
            end

            if tableContainsValue(tags, tag) then
                return true
            end
        end

        local aiTags = entity and entity.aiTags
        if type(aiTags) == "table" then
            if aiTags[tag] then
                return true
            end

            if tableContainsValue(aiTags, tag) then
                return true
            end
        end

        return false
    end

    local medicalMotifTerms = {
        "medical",
        "medicine",
        "medic",
        "doctor",
        "physician",
        "surgeon",
        "chirurgeon",
        "healer",
        "herbalist",
        "apothecary",
        "midwife",
    }

    local function motifContainsMedicalTerm(motif)
        local lower = string.lower(tostring(motif or ""))
        for _, term in ipairs(medicalMotifTerms) do
            if string.find(lower, term, 1, true) then
                return true
            end
        end
        return false
    end

    function resolver:getMedicalMotif(actor, declaredMotif)
        if not actor then
            return nil
        end

        if declaredMotif and actor.hasMotif then
            local hasDeclared, motif = actor:hasMotif(declaredMotif)
            if hasDeclared then
                return motif or declaredMotif
            end
        end

        for _, motif in ipairs(actor.motifs or {}) do
            if motifContainsMedicalTerm(motif) then
                return motif
            end
        end

        if actor.talents and actor.talents.chirurgeon then
            return "Chirurgeon"
        end

        return nil
    end

    function resolver:applyItemUseAttribute(action, result, effect)
        if not action or not result or not effect or not effect.attribute then
            return
        end

        local actor = action.actor
        local attribute = effect.attribute
        local modifier = actor and actor[attribute] or 0
        result.modifier = modifier
        result.testValue = (result.cardValue or (action.card and action.card.value) or 0) + modifier
        result.itemUseAttribute = attribute
    end

    function resolver:isWardAffectedTarget(target, affectedTags)
        if not target then
            return false
        end

        if target.undead or target.spirit then
            return true
        end

        for _, tag in ipairs(affectedTags or {}) do
            if hasTag(target, tag) then
                return true
            end
        end

        return false
    end

    function resolver:hasAnyTargetTag(target, tags)
        if not target then
            return false
        end

        for _, tag in ipairs(tags or {}) do
            if hasTag(target, tag) or target[tag] then
                return true
            end
        end

        return false
    end

    function resolver:resolvePoulticeDeathsDoor(action, result, item, effect, target)
        if not target.conditions or not target.conditions.deaths_door then
            result.success = false
            result.itemEffect = { type = "poultice_deaths_door", noEffect = true }
            result.description = effect.noEffectMessage or ((item.name or "Poultice") .. " can only save someone at Death's Door.")
            result.effects[#result.effects + 1] = "poultice_no_effect"
            return false
        end

        if target.conditions.dead then
            result.success = false
            result.itemEffect = { type = "poultice_deaths_door", noEffect = true }
            result.description = "Too late for a poultice."
            result.effects[#result.effects + 1] = "poultice_too_late"
            return false
        end

        local card = action.poulticeCard or action.testCard or action.card or {}
        local woundedWands = target.getAttribute and target:getAttribute(constants.SUITS.WANDS) or (target.wands or 0)
        local medicalMotif = action.medicalFavor and (action.medicalMotif or "medical motif") or
                             self:getMedicalMotif(action.actor, action.medicalMotif)
        local favorModifier = medicalMotif and 3 or 0
        local total = (card.value or 0) + woundedWands + favorModifier
        local difficulty = effect.difficulty or action.poulticeDifficulty or 14
        local greatFailure = action.poulticeGreatFailure or action.greatFailure or
                             (action.testResult and action.testResult.isGreat and not action.testResult.success)
        local success = not greatFailure and total >= difficulty

        result.cardValue = card.value or result.cardValue or 0
        result.modifier = woundedWands + favorModifier
        result.testValue = total
        result.difficulty = difficulty
        result.favor = medicalMotif and true or nil
        result.poulticeTest = {
            card = card,
            attribute = "wands",
            targetSuit = constants.SUITS.WANDS,
            target = target,
            applier = action.actor,
            medicalMotif = medicalMotif,
            total = total,
            difficulty = difficulty,
            success = success,
            greatFailure = greatFailure,
        }

        if success then
            local healResult = target.healWound and target:healWound() or nil
            result.success = healResult ~= nil
            result.itemEffect = { type = "poultice_deaths_door", result = healResult }
            if result.success then
                result.description = effect.successMessage or "Poultice applied: Death's Door cleared."
                result.effects[#result.effects + 1] = "poultice_success"
                result.effects[#result.effects + 1] = "healed"
                return true
            end
        end

        target.conditions.dead = true
        result.success = false
        result.itemEffect = { type = "poultice_deaths_door", result = "dead" }
        result.description = effect.failureMessage or "Poultice failed: the character dies."
        result.effects[#result.effects + 1] = "poultice_failed"
        result.effects[#result.effects + 1] = "entity_dead"

        if greatFailure then
            local zombie = entity_factory.createUndeadFromAdventurer(target, "zombie", {
                location = target.location,
                zone = target.zone,
            })
            if zombie then
                if target.markUndeadRaised then
                    target:markUndeadRaised(zombie, action.currentWatch or action.watchNumber)
                end
                result.undeadRaised = zombie
                result.effects[#result.effects + 1] = "zombie_raised"
                result.description = "Poultice failed catastrophically: the character dies and instantly rises as a zombie."
                self.eventBus:emit(events.EVENTS.UNDEAD_RAISED, {
                    source = target,
                    undead = zombie,
                    undeadType = "zombie",
                    reason = "poultice_great_failure",
                    watchNumber = action.currentWatch or action.watchNumber,
                })
            end
        elseif target.scheduleUndeadRise then
            result.pendingUndeadRise = target:scheduleUndeadRise("zombie", action.currentWatch or action.watchNumber, {
                reason = "poultice_failed",
            })
            result.effects[#result.effects + 1] = "zombie_rise_scheduled"
        end

        self.eventBus:emit(events.EVENTS.ENTITY_DEFEATED, {
            entity = target,
            reason = greatFailure and "poultice_great_failure" or "poultice_failed",
            item = item,
        })

        return false
    end

    function resolver:potionHasNoEffect(target)
        if not target then
            return false
        end

        if target.isItem or target.itemType or target.properties then
            return true
        end

        return target.undead or target.construct or target.automaton
            or hasTag(target, "undead")
            or hasTag(target, "construct")
            or hasTag(target, "automaton")
    end

    function resolver:materialIsImmune(target, materials)
        local props = target and target.properties or {}
        local material = props.material or target.material
        return material ~= nil and tableContainsValue(materials, material)
    end

    function resolver:destroyObjectTarget(target, effect, result)
        if not target then
            return false
        end

        local props = target.properties or {}
        if target.magical or props.magical then
            result.effects[#result.effects + 1] = "object_resisted"
            return false
        end

        if self:materialIsImmune(target, effect.immuneMaterials) then
            result.effects[#result.effects + 1] = "material_resisted"
            return false
        end

        if target.durability or target.notches then
            target.notches = target.durability or target.notches or 1
        end
        target.destroyed = true
        result.effects[#result.effects + 1] = "object_destroyed"
        return true
    end

    function resolver:applyItemUseEffect(action, result, item)
        local effect = self:getItemUseEffect(item)
        if not effect then
            return true
        end

        local target = self:getItemEffectTarget(action, effect)
        if not target then
            result.success = false
            result.description = "No valid target for " .. (item.name or "item") .. "."
            result.effects[#result.effects + 1] = "item_target_missing"
            return false
        end

        local props = item and item.properties or {}
        if props.potion and self:potionHasNoEffect(target) then
            result.itemEffect = { type = effect.type or "unknown", noEffect = true }
            result.description = effect.noEffectMessage or ((item.name or "Potion") .. " has no effect on the target.")
            result.effects[#result.effects + 1] = "potion_no_effect"
            return true
        end

        if effect.type == "poultice_deaths_door" then
            return self:resolvePoulticeDeathsDoor(action, result, item, effect, target)
        elseif effect.type == "salt_ooze" then
            if not self:hasAnyTargetTag(target, effect.affectedTags) then
                result.success = false
                result.itemEffect = { type = "salt_ooze", noEffect = true }
                result.description = effect.noEffectMessage or ((item.name or "Salt") .. " has no special effect.")
                result.effects[#result.effects + 1] = "salt_no_effect"
                return false
            end

            local damage = effect.damage or {}
            local amount = damage.amount or 2
            local damageEffects = damage.effects or { "salt_reactive" }
            result.damageDealt = (result.damageDealt or 0) + amount
            for _, damageEffect in ipairs(damageEffects) do
                result.effects[#result.effects + 1] = damageEffect
            end
            self:applyDamage(target, amount, damageEffects, nil, action.allEntities,
                self:getActionWoundOptions(action, target))
            result.itemEffect = { type = "salt_ooze", amount = amount }
            result.description = effect.successMessage or ((item.name or "Salt") .. " deals " .. amount .. " Wounds.")
            return true
        elseif effect.type == "refuel_lantern" then
            local props = target and target.properties or {}
            if not target or not props.light_source or not props.provides_belt_light then
                result.success = false
                result.itemEffect = { type = "refuel_lantern", noEffect = true }
                result.description = effect.noEffectMessage or ((item.name or "Oil") .. " can only refill a lantern.")
                result.effects[#result.effects + 1] = "refuel_no_effect"
                return false
            end

            props.flicker_count = effect.flickers or 4
            props.extinguished = false
            props.isLit = true
            result.itemEffect = {
                type = "refuel_lantern",
                target = target,
                flickers = props.flicker_count,
            }
            result.description = effect.successMessage or "Lantern refilled."
            result.effects[#result.effects + 1] = "lantern_refueled"
            return true
        elseif effect.type == "ward_undead" then
            if not self:isWardAffectedTarget(target, effect.affectedTags) then
                result.success = false
                result.itemEffect = { type = "ward_undead", noEffect = true }
                result.description = effect.noEffectMessage or ((item.name or "Ward") .. " has no effect.")
                result.effects[#result.effects + 1] = "ward_no_effect"
                return false
            end

            if action.destinationZone then
                target.zone = action.destinationZone
            end

            self:clearAllEngagements(target, action.allEntities)
            target.conditions = target.conditions or {}
            target.conditions.displaced = true
            result.itemEffect = {
                type = "ward_undead",
                target = target,
                destinationZone = action.destinationZone,
            }
            result.description = effect.successMessage or ((item.name or "Ward") .. " displaces the creature.")
            result.effects[#result.effects + 1] = "ward_success"
            result.effects[#result.effects + 1] = "displaced"
            return true
        elseif effect.type == "heal_wound" then
            if not target.healWound then
                result.success = false
                result.description = "No healable target."
                result.effects[#result.effects + 1] = "item_effect_failed"
                return false
            end
            if target.immuneToHealEffect or target.immuneToHeal then
                result.success = false
                result.description = "Cannot heal: immune to the Heal effect."
                result.effects[#result.effects + 1] = "heal_immune"
                return false
            end

            local healResult, err = target:healWound()
            if healResult then
                result.itemEffect = { type = "heal_wound", result = healResult }
                result.description = (effect.successMessage or "Healed: " .. healResult)
                result.effects[#result.effects + 1] = "healed"
                return true
            end

            result.success = false
            result.description = "Cannot heal: " .. (err or "unknown")
            if err == "healing_blocked" then
                result.effects[#result.effects + 1] = "healing_blocked"
            else
                result.effects[#result.effects + 1] = "item_effect_failed"
            end
            return false
        elseif effect.type == "clear_conditions" then
            local cleared = self:clearTargetConditions(target, effect.conditions)
            result.itemEffect = { type = "clear_conditions", cleared = cleared }
            if cleared then
                result.description = effect.successMessage or ("Cleared " .. cleared .. ".")
                result.effects[#result.effects + 1] = "condition_cleared"
                result.effects[#result.effects + 1] = "cleared_" .. cleared
            else
                result.description = effect.noEffectMessage or ((item.name or "Item") .. " used, but no condition changed.")
                result.effects[#result.effects + 1] = "item_no_condition"
            end
            return true
        elseif effect.type == "apply_conditions" then
            target.conditions = target.conditions or {}
            for condition, value in pairs(effect.conditions or {}) do
                target.conditions[condition] = value
                if effect.duration and value then
                    target.conditionDurations = target.conditionDurations or {}
                    target.conditionDurations[condition] = {
                        duration = effect.duration,
                        sourceItemId = item.id,
                        sourceItemName = item.name,
                    }
                end
                result.effects[#result.effects + 1] = condition
            end

            result.itemEffect = {
                type = "apply_conditions",
                conditions = effect.conditions,
                duration = effect.duration,
            }
            result.description = effect.successMessage or ((item.name or "Item") .. " effect lands.")
            return true
        elseif effect.type == "apply_properties" then
            local props = target.properties or {}
            target.properties = props
            for property, value in pairs(effect.properties or {}) do
                props[property] = value
                if effect.duration and value then
                    props.effectDurations = props.effectDurations or {}
                    props.effectDurations[property] = {
                        duration = effect.duration,
                        sourceItemId = item.id,
                        sourceItemName = item.name,
                    }
                end
                result.effects[#result.effects + 1] = property
            end

            result.itemEffect = {
                type = "apply_properties",
                target = target,
                properties = effect.properties,
                duration = effect.duration,
            }
            result.description = effect.successMessage or ((item.name or "Item") .. " changes the target.")
            return true
        elseif effect.type == "purge_poison_alchemy" then
            local cleared = clearImpPotionAlchemy(target)
            local controller = action.challengeController or self.challengeController
            local challengeActive = action.inChallenge == true or action.challenge == true or
                action.phase == "challenge" or (controller and controller.isActive and controller:isActive())
            if challengeActive then
                target.conditions = target.conditions or {}
                target.conditions.exhausted = true
                target.impPotionExhausted = true
                result.effects[#result.effects + 1] = "exhausted"
            end

            result.itemEffect = {
                type = "purge_poison_alchemy",
                target = target,
                cleared = cleared,
                exhausted = challengeActive == true,
            }
            result.clearedAlchemy = cleared
            result.effects[#result.effects + 1] = "poison_alchemy_purged"
            result.description = effect.successMessage or
                ((item.name or "Item") .. " purges poison and alchemy.")
            return true
        elseif effect.type == "dungeon_bird_rumor" then
            local rumor = action.rumor or action.dungeonRumor or action.questRumor
            if not rumor then
                local event = city_events.getEvent(action.rumorValue or effect.defaultRumorValue or 11)
                if event then
                    rumor = {
                        category = event.category,
                        title = event.title,
                        summary = event.summary,
                        cityEvent = event,
                    }
                end
            end

            local birdRumor = {
                sourceItemId = item.id,
                sourceItemName = item.name,
                arrivesInWatches = effect.arrivesInWatches or 1,
                rumor = rumor,
                pending = action.resolveRumorNow ~= true,
                dungeonBird = true,
                looksLikeOwl = true,
                isOwl = false,
            }
            if action.resolveRumorNow then
                birdRumor.delivered = true
            end

            target.pendingDungeonBirdRumors = target.pendingDungeonBirdRumors or {}
            target.pendingDungeonBirdRumors[#target.pendingDungeonBirdRumors + 1] = birdRumor
            target.dungeonBirdRumor = birdRumor

            result.itemEffect = {
                type = "dungeon_bird_rumor",
                target = target,
                rumor = rumor,
                arrivesInWatches = birdRumor.arrivesInWatches,
                pending = birdRumor.pending,
            }
            result.dungeonBirdRumor = birdRumor
            result.effects[#result.effects + 1] = "dungeon_bird_summoned"
            result.effects[#result.effects + 1] = birdRumor.pending and "rumor_pending" or "rumor_delivered"
            result.description = effect.successMessage or
                ((item.name or "Item") .. " calls a dungeon bird with a rumor.")
            return true
        elseif effect.type == "jinn_shroud" then
            local shroud = applyJinnPotionShroud(target, item, effect)
            result.itemEffect = {
                type = "jinn_shroud",
                target = target,
                shroud = shroud,
                duration = shroud.duration,
                canSeeShrouded = true,
                endsOnVisibleObjectInteraction = true,
            }
            result.shroud = shroud
            result.effects[#result.effects + 1] = "shrouded"
            result.effects[#result.effects + 1] = "jinn_shroud"
            result.effects[#result.effects + 1] = "see_shrouded"
            result.description = effect.successMessage or
                ((item.name or "Item") .. " makes the drinker Shrouded.")
            return true
        elseif effect.type == "object_speech" then
            target.conditions = target.conditions or {}
            target.conditions.object_speech = true
            target.canTalkToObjects = true
            target.objectSpeech = {
                sourceItemId = item.id,
                sourceItemName = item.name,
                duration = effect.duration or "three_minutes_real_time",
                realTimeMinutes = effect.realTimeMinutes or 3,
                active = true,
                knowsCreatedPurpose = true,
                knowsOwnHistory = true,
                limitedOtherwise = true,
                gmBeerExtendsConversation = true,
            }
            target.conditionDurations = target.conditionDurations or {}
            target.conditionDurations.object_speech = {
                duration = target.objectSpeech.duration,
                sourceItemId = item.id,
                sourceItemName = item.name,
            }

            result.itemEffect = {
                type = "object_speech",
                target = target,
                objectSpeech = target.objectSpeech,
            }
            result.objectSpeech = target.objectSpeech
            result.effects[#result.effects + 1] = "object_speech"
            result.effects[#result.effects + 1] = "talk_to_objects"
            result.description = effect.successMessage or
                ((item.name or "Item") .. " lets the drinker talk to objects.")
            return true
        elseif effect.type == "grow_creature" then
            local multiplier = effect.sizeMultiplier or 2
            target.conditions = target.conditions or {}
            target.conditions.sizeChanged = true
            target.conditions.sizeGrown = true
            target.conditions.sizeShrunk = false
            target.conditions.titan_growth = true
            target.changeSize = {
                source = "alchemy",
                sourceItemId = item.id,
                sourceItemName = item.name,
                active = true,
                mode = "grow",
                duration = effect.duration,
                heightMultiplier = effect.heightMultiplier or multiplier,
                sizeMultiplier = multiplier,
                attackValuesUnaffected = true,
                challengeActionFavor = effect.challengeActionFavor ~= false,
                testOfFateOnly = effect.challengeActionFavor == false,
            }
            target.sizeMultiplier = multiplier
            target.heightMultiplier = effect.heightMultiplier or multiplier
            target.sizeChanged = true

            if effect.duration then
                target.conditionDurations = target.conditionDurations or {}
                for _, condition in ipairs({ "sizeChanged", "sizeGrown", "titan_growth" }) do
                    target.conditionDurations[condition] = {
                        duration = effect.duration,
                        sourceItemId = item.id,
                        sourceItemName = item.name,
                    }
                end
            end

            result.changeSize = target.changeSize
            result.itemEffect = {
                type = "grow_creature",
                target = target,
                duration = effect.duration,
                sizeMultiplier = multiplier,
            }
            result.effects[#result.effects + 1] = "size_grown"
            result.effects[#result.effects + 1] = "titan_growth"
            result.description = effect.successMessage or ((item.name or "Item") .. " makes the target grow.")
            return true
        elseif effect.type == "location_insight" then
            local subject = action.locationSubject or action.subject or action.person or action.place or action.thing
            if not subject or tostring(subject) == "" then
                result.success = false
                result.description = "Choose one person, place, or thing to locate."
                result.effects[#result.effects + 1] = "location_subject_required"
                return false
            end

            local insight = {
                sourceItemId = item.id,
                sourceItemName = item.name,
                subject = subject,
                answer = action.locationAnswer or action.gmAnswer,
                prophetic = true,
            }
            target.locationInsights = target.locationInsights or {}
            target.locationInsights[#target.locationInsights + 1] = insight
            target.latestLocationInsight = insight
            result.locationInsight = insight
            result.itemEffect = {
                type = "location_insight",
                target = target,
                insight = insight,
            }
            result.effects[#result.effects + 1] = "location_insight"
            result.effects[#result.effects + 1] = "prophetic_insight"
            result.description = effect.successMessage or
                ((item.name or "Item") .. " grants a flash of prophetic location insight.")
            return true
        elseif effect.type == "barking_lure" then
            local props = target.properties or {}
            target.properties = props
            props.barkingLure = true
            props.questingBeastBark = true
            props.effectDurations = props.effectDurations or {}
            props.effectDurations.barkingLure = {
                duration = effect.duration or "watch",
                sourceItemId = item.id,
                sourceItemName = item.name,
            }

            local manager = action.watchManager or self.watchManager
            local draws = {}
            local encounters = {}
            local drawCount = effect.drawCount or 2
            if manager and manager.drawMeatgrinder then
                for _ = 1, drawCount do
                    local draw = manager:drawMeatgrinder()
                    if draw then
                        draw.questingBeastLure = true
                        draw.lureTarget = target
                        draw.lureTargetId = target.id
                        draws[#draws + 1] = draw
                        if draw.category == "random_encounter" then
                            encounters[#encounters + 1] = draw
                        end
                    end
                end
            else
                props.pendingMeatgrinderDraws = (props.pendingMeatgrinderDraws or 0) + drawCount
            end

            result.itemEffect = {
                type = "barking_lure",
                target = target,
                duration = effect.duration,
                draws = draws,
                encounters = encounters,
            }
            result.meatgrinderDraws = draws
            result.questingBeastEncounters = encounters
            result.effects[#result.effects + 1] = "barking_lure"
            result.effects[#result.effects + 1] = "meatgrinder_draw_twice"
            if #encounters > 0 then
                result.effects[#result.effects + 1] = "encounters_drawn_to_lure"
            elseif not manager or not manager.drawMeatgrinder then
                result.effects[#result.effects + 1] = "meatgrinder_draws_pending"
            end
            result.description = effect.successMessage or
                ((item.name or "Item") .. " begins barking like many hounds.")
            return true
        elseif effect.type == "trigger_maleficence" then
            local branches = { "wastes", "weald", "weird", "welkin" }
            local branchIndex = action.maleficenceTableIndex or (action.card and action.card.suit) or 1
            local branch = action.maleficenceBranch or action.branch or
                branches[((branchIndex - 1) % #branches) + 1]
            local opts = {
                resolve = true,
                card = action.maleficenceCard or action.maleficenceDraw,
                value = action.maleficenceValue,
                suit = action.maleficenceSuit,
                source = item,
                sourceItemId = item.id,
                sourceItemName = item.name,
                allEntities = action.allEntities,
                roomEntities = action.roomEntities,
                environmentManager = action.environmentManager,
                watchManager = action.watchManager,
                roomManager = action.roomManager,
            }
            local record = self:triggerMaleficence(target, branch, "ungoat_bomb", opts)
            local maleficenceResult = record and record.resolution
            if not maleficenceResult or not maleficenceResult.success then
                result.success = false
                result.description = "Maleficence could not be resolved."
                result.effects[#result.effects + 1] = "maleficence_draw_missing"
                result.itemEffect = {
                    type = "trigger_maleficence",
                    target = target,
                    branch = branch,
                    record = record,
                    result = maleficenceResult,
                }
                return false
            end

            result.itemEffect = {
                type = "trigger_maleficence",
                target = target,
                branch = branch,
                record = record,
                result = maleficenceResult,
            }
            result.maleficence = maleficenceResult
            result.effects[#result.effects + 1] = "ungoat_maleficence"
            result.effects[#result.effects + 1] = "maleficence_" .. branch
            result.description = effect.successMessage or
                ((item.name or "Item") .. " centers maleficence on the target.")
            return true
        elseif effect.type == "negate_spells" then
            local props = target.properties or {}
            target.properties = props
            props.magicSuppressed = true
            props.spellsNegated = true
            props.effectDurations = props.effectDurations or {}
            props.effectDurations.magicSuppressed = {
                duration = effect.duration or "watch",
                sourceItemId = item.id,
                sourceItemName = item.name,
            }

            local negated = {}
            local function spellAffectsTarget(spellEntry)
                if not spellEntry then
                    return false
                end
                if spellEntry.target == target or spellEntry.circleProtection == target or
                   spellEntry.mirrorMeld == target or spellEntry.portableHole == target then
                    return true
                end
                for _, spellTarget in ipairs(spellEntry.targets or {}) do
                    if spellTarget == target then
                        return true
                    end
                end
                return false
            end

            for _, caster in ipairs(action.allEntities or action.casters or {}) do
                if caster and type(caster.activeSpells) == "table" then
                    for index = #caster.activeSpells, 1, -1 do
                        local spellEntry = caster.activeSpells[index]
                        if spellAffectsTarget(spellEntry) then
                            local ended = self:endOngoingSpell(caster, spellEntry, "ungoat_oil")
                            negated[#negated + 1] = ended or spellEntry
                        end
                    end
                end
            end

            if type(target.activeEnchantments) == "table" then
                target.pausedEnchantments = target.pausedEnchantments or {}
                for _, enchantment in ipairs(target.activeEnchantments) do
                    enchantment.paused = true
                    enchantment.pausedUntil = effect.duration or "watch"
                    target.pausedEnchantments[#target.pausedEnchantments + 1] = enchantment
                    negated[#negated + 1] = enchantment
                end
            elseif target.enchanted or props.enchanted or props.magical then
                props.enchantmentPaused = true
                props.enchantmentPausedUntil = effect.duration or "watch"
            end

            result.itemEffect = {
                type = "negate_spells",
                target = target,
                duration = effect.duration,
                negated = negated,
            }
            result.negatedSpells = negated
            result.effects[#result.effects + 1] = "spells_negated"
            result.effects[#result.effects + 1] = "magic_suppressed"
            result.description = effect.successMessage or
                ((item.name or "Item") .. " negates active magic on the target.")
            return true
        elseif effect.type == "mist_form" then
            local dropped = {}
            if target.inventory and target.inventory.getAllItems then
                local entries = target.inventory:getAllItems()
                for _, entry in ipairs(entries) do
                    local carriedItem = entry.item
                    if carriedItem and carriedItem.id and carriedItem.id ~= item.id then
                        local droppedItem = self:dropCarriedItem(target, carriedItem, "mist_form")
                        if droppedItem then
                            dropped[#dropped + 1] = droppedItem
                        end
                    end
                end
            end

            target.conditions = target.conditions or {}
            target.conditions.mist_form = true
            target.conditions.vampire_mist = true
            target.conditions.hazard_resistant = true
            target.conditions.can_pass_cracks = true
            target.mistForm = {
                sourceItemId = item.id,
                sourceItemName = item.name,
                duration = effect.duration or "watch",
                walkingPace = true,
                equipmentDropped = dropped,
                vulnerableToStrongWindOrExtremeCold = true,
            }
            if effect.duration then
                target.conditionDurations = target.conditionDurations or {}
                for _, condition in ipairs({ "mist_form", "vampire_mist", "hazard_resistant", "can_pass_cracks" }) do
                    target.conditionDurations[condition] = {
                        duration = effect.duration,
                        sourceItemId = item.id,
                        sourceItemName = item.name,
                    }
                end
            end

            result.itemEffect = {
                type = "mist_form",
                target = target,
                duration = effect.duration,
                droppedItems = dropped,
            }
            result.droppedItems = dropped
            result.effects[#result.effects + 1] = "mist_form"
            result.effects[#result.effects + 1] = "equipment_dropped"
            result.description = effect.successMessage or
                ((item.name or "Item") .. " transforms the drinker into mist.")
            return true
        elseif effect.type == "vampire_weaknesses" then
            target.conditions = target.conditions or {}
            target.conditions.vampire_weaknesses = true
            target.conditions.sunlight_stuns = true
            target.conditions.wholesome_herbs_stun = true
            target.conditions.silver_stuns = true
            target.conditions.running_water_stuns = true
            target.vampireWeaknesses = {
                sourceItemId = item.id,
                sourceItemName = item.name,
                duration = effect.duration or "watch",
                triggers = { "sunlight", "wholesome_herbs", "silver", "running_water" },
            }
            if effect.duration then
                target.conditionDurations = target.conditionDurations or {}
                for _, condition in ipairs({
                    "vampire_weaknesses",
                    "sunlight_stuns",
                    "wholesome_herbs_stun",
                    "silver_stuns",
                    "running_water_stuns",
                }) do
                    target.conditionDurations[condition] = {
                        duration = effect.duration,
                        sourceItemId = item.id,
                        sourceItemName = item.name,
                    }
                end
            end

            local exposure = action.exposure or action.exposedTo or action.trigger
            if exposure == "sunlight" or exposure == "wholesome_herbs" or exposure == "garlic" or
               exposure == "wolfsbane" or exposure == "wild_rose" or exposure == "silver" or
               exposure == "running_water" then
                target.conditions.stunned = true
                target.vampireWeaknesses.lastExposure = exposure
                result.effects[#result.effects + 1] = "vampire_weakness_stunned"
            end

            result.itemEffect = {
                type = "vampire_weaknesses",
                target = target,
                duration = effect.duration,
                exposure = exposure,
            }
            result.effects[#result.effects + 1] = "vampire_weaknesses"
            result.description = effect.successMessage or
                ((item.name or "Item") .. " gives the target vampire weaknesses.")
            return true
        elseif effect.type == "romantic_inspiration" then
            local conditions = target.conditions or {}
            local emotionless = target.emotionless == true or target.noEmotions == true or
                conditions.emotionless == true or conditions.inspire_immune == true or
                conditions.inspired_immune == true or conditions.nymph_beauty == true or
                hasTag(target, "emotionless") or hasTag(target, "mindless")
            if emotionless then
                result.itemEffect = {
                    type = "romantic_inspiration",
                    target = target,
                    noEffect = true,
                }
                result.effects[#result.effects + 1] = "romantic_inspiration_no_effect"
                result.effects[#result.effects + 1] = "emotionless_unaffected"
                result.description = (item.name or "Item") .. " has no effect on the target."
                return true
            end

            local loveTarget = action.firstSeenCreature or action.firstSeen or action.seenCreature or
                action.loveTarget or action.romanticTarget or action.actor
            target.conditions = conditions
            conditions.inspired = true
            conditions.inspiredJoy = true
            conditions.inspiredRomanticJoy = true
            conditions.inLove = true
            if effect.duration then
                target.conditionDurations = target.conditionDurations or {}
                for _, condition in ipairs({ "inspired", "inspiredJoy", "inspiredRomanticJoy", "inLove" }) do
                    target.conditionDurations[condition] = {
                        duration = effect.duration,
                        sourceItemId = item.id,
                        sourceItemName = item.name,
                    }
                end
            end

            target.romanticInspiration = {
                sourceItemId = item.id,
                sourceItemName = item.name,
                target = loveTarget,
                targetId = loveTarget and (loveTarget.id or loveTarget.name),
                duration = effect.duration or "watch",
                inspiredWithJoy = true,
                romantic = true,
            }
            target.romanticInspirationTarget = loveTarget

            result.itemEffect = {
                type = "romantic_inspiration",
                target = target,
                loveTarget = loveTarget,
                duration = effect.duration,
            }
            result.romanticInspiration = target.romanticInspiration
            result.effects[#result.effects + 1] = "romantic_inspiration"
            result.effects[#result.effects + 1] = "inspired_romantic_joy"
            result.description = effect.successMessage or
                ((item.name or "Item") .. " inspires romantic joy.")
            return true
        elseif effect.type == "distaste_inspiration" then
            if isInspirationImmuneTarget(target) then
                result.itemEffect = {
                    type = "distaste_inspiration",
                    target = target,
                    noEffect = true,
                }
                result.effects[#result.effects + 1] = "distaste_inspiration_no_effect"
                result.effects[#result.effects + 1] = "emotionless_unaffected"
                result.description = (item.name or "Item") .. " has no effect on the target."
                return true
            end

            local hateTarget = action.firstSeenCreature or action.firstSeen or action.seenCreature or
                action.hateTarget or action.distasteTarget or action.actor
            target.conditions = target.conditions or {}
            local conditions = target.conditions
            conditions.inspired = true
            conditions.inspiredDistaste = true
            conditions.inHate = true
            if effect.duration then
                target.conditionDurations = target.conditionDurations or {}
                for _, condition in ipairs({ "inspired", "inspiredDistaste", "inHate" }) do
                    target.conditionDurations[condition] = {
                        duration = effect.duration,
                        sourceItemId = item.id,
                        sourceItemName = item.name,
                    }
                end
            end

            target.disposition = "distaste"
            target.distasteInspiration = {
                sourceItemId = item.id,
                sourceItemName = item.name,
                target = hateTarget,
                targetId = hateTarget and (hateTarget.id or hateTarget.name),
                duration = effect.duration or "watch",
                inspiredWithDistaste = true,
            }
            target.distasteInspirationTarget = hateTarget

            result.itemEffect = {
                type = "distaste_inspiration",
                target = target,
                hateTarget = hateTarget,
                duration = effect.duration,
            }
            result.distasteInspiration = target.distasteInspiration
            result.effects[#result.effects + 1] = "distaste_inspiration"
            result.effects[#result.effects + 1] = "inspired_distaste"
            result.description = effect.successMessage or
                ((item.name or "Item") .. " inspires hateful distaste.")
            return true
        elseif effect.type == "imp_stink" then
            target.conditions = target.conditions or {}
            local stunDiscard = self:applyStun(target, { action = action })
            target.conditions.imp_stink = true
            target.conditions.choking_stink = true
            target.impStink = {
                sourceItemId = item.id,
                sourceItemName = item.name,
                requiresWashing = true,
            }
            if target.isPC then
                target.conditions.stressed = true
                target.impStink.stressedUntilWashed = true
                result.effects[#result.effects + 1] = "stressed_until_washed"
            end

            result.itemEffect = {
                type = "imp_stink",
                target = target,
                stunDiscard = stunDiscard,
                stressed = target.isPC == true,
            }
            result.stunDiscard = stunDiscard
            result.effects[#result.effects + 1] = "stunned"
            result.effects[#result.effects + 1] = "imp_stink"
            result.description = effect.successMessage or
                ((item.name or "Item") .. " stuns the target with a terrible stink.")
            return true
        elseif effect.type == "compel_confession" then
            if isControlImmuneTarget(target) then
                result.itemEffect = {
                    type = "compel_confession",
                    target = target,
                    noEffect = true,
                }
                result.effects[#result.effects + 1] = "compelled_confession_no_effect"
                result.effects[#result.effects + 1] = "control_immune"
                result.description = (item.name or "Item") .. " has no effect on the target."
                return true
            end

            local orderText = tostring(action.confessionOrder or action.controlOrder or "confess gravest sin")
            local wordCount = 0
            for _ in string.gmatch(orderText, "%S+") do
                wordCount = wordCount + 1
            end

            target.conditions = target.conditions or {}
            target.conditions.controlled = true
            target.controlledBy = action.actor
            target.controlOrder = {
                text = orderText,
                wordCount = wordCount,
                sourceItemId = item.id,
                sourceItemName = item.name,
                fulfilled = false,
                singleTask = true,
            }
            target.controlCommandsRemaining = 1
            target.confessionControl = {
                sourceItemId = item.id,
                sourceItemName = item.name,
                controller = action.actor,
                order = orderText,
                gravestSin = true,
                confession = action.confession or action.gravestSin or target.gravestSin,
                fulfilled = false,
            }

            result.itemEffect = {
                type = "compel_confession",
                target = target,
                order = target.controlOrder,
            }
            result.controlOrder = target.controlOrder
            result.confessionControl = target.confessionControl
            result.effects[#result.effects + 1] = "controlled"
            result.effects[#result.effects + 1] = "compelled_confession"
            result.description = effect.successMessage or
                ((item.name or "Item") .. " controls the target into confession.")
            return true
        elseif effect.type == "invisible_fire" then
            local targetProps = target.properties or {}
            target.properties = targetProps
            targetProps.invisibleFire = true
            targetProps.castsLight = false
            targetProps.shedsLight = false
            targetProps.generatesHeat = true
            targetProps.notQuenchedByWater = true
            targetProps.extinguishedBySmothering = true
            target.invisibleFire = {
                sourceItemId = item.id,
                sourceItemName = item.name,
                castsLight = false,
                generatesHeat = true,
                notQuenchedByWater = true,
                extinguishedBySmothering = true,
            }

            local flammableConsumed = false
            local weaponNotchResult = nil
            if isFlammableTarget(target) and action.consumeFlammable ~= false then
                target.destroyed = true
                targetProps.consumedByInvisibleFire = true
                flammableConsumed = true
                result.effects[#result.effects + 1] = "flammable_consumed"
            elseif action.dipWeapon == true or action.invisibleFireWeapon == true or isWeaponTarget(target) then
                targetProps.invisibleFireWeapon = true
                targetProps.burnsHotAsTorch = true
                targetProps.fireWeaknessBonus = true
                targetProps.fireDamagePotential = true
                weaponNotchResult = notchItemTarget(target)
                result.weaponNotchResult = weaponNotchResult
                result.effects[#result.effects + 1] = "invisible_fire_weapon"
                result.effects[#result.effects + 1] = "weapon_notched"
                if weaponNotchResult == "destroyed" then
                    result.effects[#result.effects + 1] = "weapon_destroyed"
                end
            end

            result.itemEffect = {
                type = "invisible_fire",
                target = target,
                flammableConsumed = flammableConsumed,
                weaponNotchResult = weaponNotchResult,
            }
            result.effects[#result.effects + 1] = "invisible_fire"
            result.description = effect.successMessage or
                ((item.name or "Item") .. " burns with invisible heat.")
            return true
        elseif effect.type == "cockatrice_stone_smoke" then
            if not isStoneTarget(target) then
                result.itemEffect = {
                    type = "cockatrice_stone_smoke",
                    target = target,
                    noEffect = true,
                }
                result.effects[#result.effects + 1] = "cockatrice_smoke_no_effect"
                result.description = (item.name or "Item") .. " has no effect on non-stone targets."
                return true
            end

            if isStoneCreatureTarget(target) then
                local damageEffects = { "critical", "cockatrice_stone_smoke" }
                result.damageDealt = (result.damageDealt or 0) + 1
                for _, damageEffect in ipairs(damageEffects) do
                    result.effects[#result.effects + 1] = damageEffect
                end
                result.effects[#result.effects + 1] = "stone_creature_critical"
                self:applyDamage(target, 1, damageEffects, nil, action.allEntities,
                    self:getActionWoundOptions(action, target))
                result.itemEffect = {
                    type = "cockatrice_stone_smoke",
                    target = target,
                    damage = 1,
                    critical = true,
                }
                result.description = effect.creatureMessage or
                    ((item.name or "Item") .. " deals Critical damage to the stone creature.")
                return true
            end

            local targetProps = target.properties or {}
            target.properties = targetProps
            if isPersonSizedStoneTarget(target, effect) then
                target.destroyed = true
                targetProps.dissolvedByCockatrice = true
                result.effects[#result.effects + 1] = "stone_item_destroyed"
                result.itemEffect = {
                    type = "cockatrice_stone_smoke",
                    target = target,
                    destroyed = true,
                }
                result.description = effect.successMessage or
                    ((item.name or "Item") .. " destroys the stone object.")
            else
                targetProps.holeMelted = true
                targetProps.cockatriceMeltedHole = true
                targetProps.passageOpen = action.openPassage ~= false
                target.holeMelted = true
                result.effects[#result.effects + 1] = "stone_hole_melted"
                result.itemEffect = {
                    type = "cockatrice_stone_smoke",
                    target = target,
                    holeMelted = true,
                }
                result.description = effect.largeObjectMessage or
                    ((item.name or "Item") .. " melts a hole in the stone object.")
            end
            return true
        elseif effect.type == "cockatrice_stone_flesh" then
            if not isStoneTarget(target) then
                result.itemEffect = {
                    type = "cockatrice_stone_flesh",
                    target = target,
                    noEffect = true,
                }
                result.effects[#result.effects + 1] = "cockatrice_oil_no_effect"
                result.description = (item.name or "Item") .. " has no effect on non-stone targets."
                return true
            end

            local targetProps = target.properties or {}
            target.properties = targetProps
            local cured = clearPetrification(target)
            targetProps.formerMaterial = targetProps.formerMaterial or targetProps.material or target.material or "stone"
            targetProps.material = "flesh"
            targetProps.fleshyStone = true
            targetProps.stoneMadeFlesh = true
            if target.material == "stone" then
                target.material = "flesh"
            end
            target.fleshyStone = true

            result.itemEffect = {
                type = "cockatrice_stone_flesh",
                target = target,
                curedPetrification = cured,
            }
            result.effects[#result.effects + 1] = "stone_fleshified"
            if cured then
                result.effects[#result.effects + 1] = "petrification_cured"
            end
            result.description = effect.successMessage or
                ((item.name or "Item") .. " turns touched stone into flesh.")
            return true
        elseif effect.type == "rage_pheromone" then
            local candidates = action.zoneEntities or action.creaturesInZone or action.allEntities or {}
            local targetZone = action.targetZone or (target and target.zone)
            local affected = {}
            local skipped = {}

            for _, creature in ipairs(candidates) do
                local sameZone = action.zoneEntities ~= nil or targetZone == nil or creature.zone == targetZone
                local conditions = creature and creature.conditions or {}
                local emotionless = creature and (
                    creature.emotionless == true or creature.noEmotions == true or
                    conditions.emotionless == true or conditions.inspire_immune == true or
                    conditions.inspired_immune == true or conditions.nymph_beauty == true or
                    hasTag(creature, "emotionless") or hasTag(creature, "mindless")
                )
                if creature and creature ~= target and sameZone and not emotionless then
                    creature.conditions = creature.conditions or {}
                    creature.conditions.inspired = true
                    creature.conditions.inspiredAnger = true
                    creature.conditions.enraged = true
                    creature.disposition = "anger"
                    creature.recklessAttackTarget = target
                    creature.ogrePheromone = {
                        sourceItemId = item.id,
                        sourceItemName = item.name,
                        target = target,
                        targetId = target and target.id,
                    }
                    affected[#affected + 1] = creature
                elseif creature and creature ~= target and sameZone and emotionless then
                    skipped[#skipped + 1] = creature
                end
            end

            result.itemEffect = {
                type = "rage_pheromone",
                target = target,
                affected = affected,
                skipped = skipped,
            }
            result.pheromoneAffected = affected
            result.pheromoneSkipped = skipped
            result.effects[#result.effects + 1] = "rage_pheromone"
            if #affected > 0 then
                result.effects[#result.effects + 1] = "inspired_anger"
            else
                result.effects[#result.effects + 1] = "rage_pheromone_no_effect"
            end
            if #skipped > 0 then
                result.effects[#result.effects + 1] = "emotionless_unaffected"
            end
            result.description = effect.successMessage or
                ((item.name or "Item") .. " makes nearby creatures furious at the target.")
            return true
        elseif effect.type == "cleanse_surface" then
            local cleaned = cleanseTargetWithGriffinOil(target, action)
            result.itemEffect = {
                type = "cleanse_surface",
                target = target,
                cleaned = cleaned,
                dungeonBath = target and target.griffinOilBath == true,
            }
            result.cleaned = cleaned
            result.effects[#result.effects + 1] = "cleaned"
            result.effects[#result.effects + 1] = "griffin_oil_cleanse"
            for _, flag in ipairs(cleaned) do
                if flag == "imp_stink_stress" then
                    result.effects[#result.effects + 1] = "washed_stress_cleared"
                    break
                end
            end
            result.description = effect.successMessage or
                ((item.name or "Item") .. " cleans the touched target.")
            return true
        elseif effect.type == "materialize_intangible" then
            if not isIntangibleTarget(target) then
                result.itemEffect = {
                    type = "materialize_intangible",
                    target = target,
                    noEffect = true,
                }
                result.effects[#result.effects + 1] = "jinn_bomb_no_effect"
                result.description = (item.name or "Item") .. " has no special effect on material targets."
                return true
            end

            local materialized = materializeWithJinnBomb(target, item)
            result.itemEffect = {
                type = "materialize_intangible",
                target = target,
                materialized = materialized,
            }
            result.materialized = materialized
            result.effects[#result.effects + 1] = "intangible_visible_tangible"
            result.effects[#result.effects + 1] = "materialized"
            result.description = effect.successMessage or
                ((item.name or "Item") .. " forces the target into the material realm.")
            return true
        elseif effect.type == "frictionless_surface" then
            local props = target.properties or {}
            target.properties = props
            props.frictionless = true
            props.utterlyFrictionless = true
            target.frictionless = true
            local pouredOut = action.pouredOut == true or action.createPuddle == true or
                action.puddle == true or target.type == "floor" or props.floor == true
            if pouredOut then
                props.slipperyPuddle = true
                props.puddleDiameterFeet = effect.puddleDiameterFeet or 10
                target.slipperyPuddle = {
                    sourceItemId = item.id,
                    sourceItemName = item.name,
                    diameterFeet = props.puddleDiameterFeet,
                    frictionless = true,
                }
                result.effects[#result.effects + 1] = "slippery_puddle"
            end

            result.itemEffect = {
                type = "frictionless_surface",
                target = target,
                puddle = pouredOut,
                diameterFeet = props.puddleDiameterFeet,
            }
            result.effects[#result.effects + 1] = "frictionless"
            result.description = effect.successMessage or
                ((item.name or "Item") .. " makes the touched surface frictionless.")
            return true
        elseif effect.type == "city_portal" then
            local targetProps = target.properties or {}
            target.properties = targetProps
            targetProps.cityPortal = true
            targetProps.fieryRealityHole = true
            targetProps.portalOpen = true
            targetProps.portalDestination = "city"
            targetProps.portalDuration = effect.duration or "one_minute"

            target.cityPortal = {
                sourceItemId = item.id,
                sourceItemName = item.name,
                destination = "city",
                manholeArrival = true,
                beginsCityPhase = true,
                openFor = effect.duration or "one_minute",
                fieryRealityHole = true,
            }
            target.fieryRealityHole = true

            result.itemEffect = {
                type = "city_portal",
                target = target,
                portal = target.cityPortal,
            }
            result.cityPortal = target.cityPortal
            result.effects[#result.effects + 1] = "city_portal_opened"
            result.effects[#result.effects + 1] = "fiery_reality_hole"

            if action.enterPortal == true or action.teleportActor == true then
                local actor = action.actor
                if actor then
                    actor.location = "city"
                    actor.teleportedToCity = true
                    actor.cityPortalArrival = {
                        sourceItemId = item.id,
                        sourceItemName = item.name,
                        arrival = "manhole",
                    }
                end
                result.phaseChange = {
                    oldPhase = action.currentPhase or action.phase or "crawl",
                    newPhase = "city",
                    reason = "jinn_oil_city_portal",
                }
                result.effects[#result.effects + 1] = "teleported_to_city"
                result.effects[#result.effects + 1] = "city_phase_begins"
                if self.eventBus then
                    self.eventBus:emit(events.EVENTS.PHASE_CHANGED, result.phaseChange)
                end
            end

            result.description = effect.successMessage or
                ((item.name or "Item") .. " opens a fiery portal to the City.")
            return true
        elseif effect.type == "awaken_mimic" then
            if not isNonLivingObjectTarget(target) then
                result.itemEffect = {
                    type = "awaken_mimic",
                    target = target,
                    noEffect = true,
                }
                result.effects[#result.effects + 1] = "mimic_oil_no_effect"
                result.description = (item.name or "Item") .. " only awakens non-living objects."
                return true
            end

            local mimic = awakenObjectAsMimic(target, item)
            result.itemEffect = {
                type = "awaken_mimic",
                target = target,
                mimic = mimic,
            }
            result.mimic = mimic
            result.effects[#result.effects + 1] = "mimic_awakened"
            result.effects[#result.effects + 1] = "not_loyal"
            result.description = effect.successMessage or
                ((item.name or "Item") .. " turns the object into a mimic.")
            return true
        elseif effect.type == "mushroom_patch" then
            local props = target.properties or {}
            target.properties = props
            local discardCard = action.minorDiscardCard or action.topMinorDiscardCard or action.discardCard or {}
            local mushroom = (effect.mushroomsBySuit or {})[discardCard.suit] or
                { id = "unknown_mushroom", name = "unknown giant mushroom" }
            props.mushroomPatch = {
                source = item.name,
                suit = discardCard.suit,
                card = discardCard,
                mushroom = mushroom,
                duration = effect.duration or "watch",
            }
            result.itemEffect = {
                type = "mushroom_patch",
                target = target,
                suit = discardCard.suit,
                mushroom = mushroom,
                duration = effect.duration,
            }
            result.effects[#result.effects + 1] = "mushroom_patch"
            if mushroom.id then
                result.effects[#result.effects + 1] = "mushroom_" .. mushroom.id
            end
            result.description = effect.successMessage or ((item.name or "Item") .. " creates a mushroom patch.")
            return true
        elseif effect.type == "adhere" then
            local props = target.properties or {}
            target.properties = props
            props.adhered = true
            props.adheredUntil = effect.duration or "watch"
            target.adheredTo = action.secondaryTarget
            result.itemEffect = {
                type = "adhere",
                target = target,
                secondaryTarget = action.secondaryTarget,
                duration = effect.duration,
            }
            result.effects[#result.effects + 1] = "adhered"
            result.description = effect.successMessage or ((item.name or "Item") .. " bonds the target.")
            return true
        elseif effect.type == "damage" then
            local amount = effect.amount or 1
            local damageEffects = effect.effects or {}
            result.damageDealt = (result.damageDealt or 0) + amount
            for _, damageEffect in ipairs(damageEffects) do
                result.effects[#result.effects + 1] = damageEffect
            end
            self:applyDamage(target, amount, damageEffects, nil, action.allEntities,
                self:getActionWoundOptions(action, target))
            result.itemEffect = { type = "damage", amount = amount }
            result.description = effect.successMessage or ((item.name or "Item") .. " deals " .. amount .. " Wound.")
            return true
        elseif effect.type == "destroy_armor" then
            local destroyed = self:destroyTargetArmor(target, result)
            result.itemEffect = { type = "destroy_armor", destroyed = destroyed }
            if destroyed then
                result.description = effect.successMessage or "Armor destroyed."
            else
                result.description = effect.noEffectMessage or ((item.name or "Item") .. " hits, but there is no armor to destroy.")
            end
            return true
        elseif effect.type == "destroy_object_or_damage_creature" then
            if target.takeWound then
                local damage = effect.damageIfCreature or {}
                local amount = damage.amount or 1
                local damageEffects = damage.effects or {}
                result.damageDealt = (result.damageDealt or 0) + amount
                for _, damageEffect in ipairs(damageEffects) do
                    result.effects[#result.effects + 1] = damageEffect
                end
                self:applyDamage(target, amount, damageEffects, nil, action.allEntities,
                    self:getActionWoundOptions(action, target))
                result.itemEffect = { type = "damage", amount = amount }
                result.description = effect.creatureMessage or ((item.name or "Item") .. " burns flesh.")
                return true
            end

            local destroyed = self:destroyObjectTarget(target, effect, result)
            result.itemEffect = { type = "destroy_object", destroyed = destroyed }
            if destroyed then
                result.description = effect.successMessage or ((item.name or "Item") .. " destroys the object.")
            else
                result.description = effect.noEffectMessage or ((item.name or "Item") .. " has no effect on the object.")
            end
            return true
        end

        result.itemEffect = { type = effect.type or "unknown" }
        result.description = effect.successMessage or ((item.name or "Item") .. " effect lands.")
        return true
    end

    function resolver:resolveUseItem(action, result)
        local actor = action.actor
        local inventory = actor and actor.inventory
        local item = action.item
        local itemLocation = nil

        if inventory then
            if not item and action.itemId and inventory.findItem then
                item, itemLocation = inventory:findItem(action.itemId)
            elseif item and inventory.findItem then
                _, itemLocation = inventory:findItem(item.id)
            end
        end

        if not inventory or not item then
            result.success = false
            result.description = "No item selected."
            result.effects[#result.effects + 1] = "item_missing"
            return
        end

        if itemLocation ~= "hands" then
            result.success = false
            result.description = "Use Item requires an item in hand."
            result.effects[#result.effects + 1] = "item_not_held"
            return
        end

        self:applyPactItemObligations(action, result, item, "use_item")

        local effect = self:getItemUseEffect(item)
        self:applyItemUseAttribute(action, result, effect)

        local contested = self:isContestedItemUse(actor, action.target, item, action)
        local contest = nil
        if contested then
            self:applyActiveAids(actor, result)
            contest = self:resolveInitiativeContest(action, result, {
                tieWins = true,
                considerShield = true,
            })
        else
            result.success = true
        end

        if result.success then
            result.item = item
            result.effects[#result.effects + 1] = "item_used"
            self:applyItemUseEffect(action, result, item)
            if result.success and (not result.description or result.description == "") then
                result.description = action.target and ((item.name or "Item") .. " effect lands.") or ((item.name or "Item") .. " used.")
            end
        else
            result.description = "Item use resisted."
        end

        if self:shouldConsumeItemOnUse(item, result, true) then
            self:consumeUsedItem(inventory, item, result)
        end

        if contest and contest.riposteTriggered and contest.riposteDefense and action.target then
            local riposteResult = self:resolveRiposte(action.target, actor, contest.riposteDefense, contest.attackValue)
            result.riposteResult = riposteResult
            result.description = result.description .. " Riposte! "
            if riposteResult.success then
                result.description = result.description .. "Counter-attack hits!"
            else
                result.description = result.description .. "Counter-attack misses."
            end
        end
    end

    local function getItemSlotSize(item)
        if not item then return 0 end
        return item.stackable and 1 or (item.size or 1)
    end

    function resolver:findItemInLocation(inventory, location, itemId)
        if not inventory or not inventory[location] then
            return nil
        end

        for _, item in ipairs(inventory[location]) do
            if not itemId or item.id == itemId then
                return item
            end
        end

        return nil
    end

    function resolver:canStoreItemInLocation(inventory, item, location, freedSlots)
        if not inventory or not item or not location then
            return false, "invalid_inventory"
        end
        if item.oversized and location ~= "belt" then
            return false, "oversized_belt_only"
        end
        if item.isArmor and location ~= "belt" then
            return false, "armor_belt_only"
        end

        local available = inventory:availableSlots(location) + (freedSlots or 0)
        if available < getItemSlotSize(item) then
            return false, "destination_full"
        end

        return true, nil
    end

    function resolver:resolvePullItemFromLocation(action, result, sourceLocation)
        local actor = action.actor
        local inventory = actor and actor.inventory
        if not inventory then
            result.success = false
            result.description = "No inventory."
            result.effects[#result.effects + 1] = "inventory_missing"
            return
        end

        local pulled = action.item or self:findItemInLocation(inventory, sourceLocation, action.itemId)
        if not pulled then
            result.success = false
            result.description = "No item to pull from " .. sourceLocation .. "."
            result.effects[#result.effects + 1] = "item_missing"
            return
        end

        local _, pulledLocation = inventory:findItem(pulled.id)
        if pulledLocation ~= sourceLocation then
            result.success = false
            result.description = "Selected item is not in " .. sourceLocation .. "."
            result.effects[#result.effects + 1] = "wrong_item_location"
            return
        end

        local held = self:findItemInLocation(inventory, "hands", action.swapWithItemId)
        if not held and inventory:availableSlots("hands") < getItemSlotSize(pulled) then
            held = self:findItemInLocation(inventory, "hands")
        end

        local handFreedSlots = held and getItemSlotSize(held) or 0
        local canHold, holdReason = self:canStoreItemInLocation(inventory, pulled, "hands", handFreedSlots)
        if not canHold then
            result.success = false
            result.description = "Cannot hold " .. (pulled.name or "item") .. "."
            result.effects[#result.effects + 1] = holdReason or "hands_full"
            return
        end

        if held then
            local sourceFreedSlots = getItemSlotSize(pulled)
            local canStore, storeReason = self:canStoreItemInLocation(inventory, held, sourceLocation, sourceFreedSlots)
            if not canStore then
                result.success = false
                result.description = "Cannot swap held " .. (held.name or "item") .. " into " .. sourceLocation .. "."
                result.effects[#result.effects + 1] = storeReason or "swap_blocked"
                return
            end
        end

        inventory:removeItem(pulled.id)
        if held then
            inventory:removeItem(held.id)
        end

        local addedPulled = inventory:addItem(pulled, "hands")
        local addedHeld = true
        if held then
            addedHeld = inventory:addItem(held, sourceLocation)
        end

        if not addedPulled or not addedHeld then
            result.success = false
            result.description = "Item swap failed."
            result.effects[#result.effects + 1] = "swap_failed"
            return
        end

        result.success = true
        result.item = pulled
        result.swappedItem = held
        result.description = "Pulled " .. (pulled.name or "item") .. " from " .. sourceLocation .. "."
        if held then
            result.description = result.description .. " Swapped out " .. (held.name or "held item") .. "."
        end
        result.effects[#result.effects + 1] = "item_pulled_" .. sourceLocation
        self:applyPactItemObligations(action, result, pulled, "pull_item")
    end

    function resolver:resolvePullItemFromPack(action, result)
        self:resolvePullItemFromLocation(action, result, "pack")
    end

    function resolver:resolvePullItemFromBelt(action, result)
        self:resolvePullItemFromLocation(action, result, "belt")
    end

    function resolver:discardReplacedDefense(action, replacedDefense)
        if not replacedDefense or not replacedDefense.card then
            return false
        end

        local actor = action and action.actor
        local controller = action and action.challengeController or self.challengeController
        local discardDeck = action and (action.discardDeck or action.deck)

        if not discardDeck then
            if actor and actor.isPC == false then
                discardDeck = (action and action.gmDeck) or self.gmDeck or (controller and controller.gmDeck)
            else
                discardDeck = (action and action.playerDeck) or self.playerDeck or (controller and controller.playerDeck)
            end
        end

        if discardDeck and discardDeck.discard then
            discardDeck:discard(replacedDefense.card)
            return true
        end

        return false
    end

    --- Prepare a Dodge defense (S4.9)
    -- Dodge adds card value to defense difficulty when attacked
    function resolver:resolveDodge(action, result)
        local actor = action.actor
        local card = action.card

        if not actor or not card then
            result.success = false
            result.description = "Invalid dodge attempt"
            return
        end

        local defenseValue = result.testValue or (card.value or 0)

        -- Prepare the dodge defense
        local success, err, replacedDefense = actor:prepareDefense("dodge", card, defenseValue)

        if success then
            result.success = true
            result.description = "Preparing to dodge! (+" .. defenseValue .. " to Initiative)"
            result.effects[#result.effects + 1] = "dodge_prepared"

            if replacedDefense then
                result.replacedDefense = replacedDefense
                result.replacedDefenseDiscarded = self:discardReplacedDefense(action, replacedDefense)
                result.effects[#result.effects + 1] = "defense_replaced"
                result.description = result.description .. " Replaced previous facedown defense."

                self.eventBus:emit("defense_replaced", {
                    entity = actor,
                    oldType = replacedDefense.type,
                    oldCard = replacedDefense.card,
                    newType = "dodge",
                    discarded = result.replacedDefenseDiscarded,
                })
            end

            self.eventBus:emit("defense_prepared", {
                entity = actor,
                type = "dodge",
                value = defenseValue,
                faceValue = card.value or 0,
                modifier = defenseValue - (card.value or 0),
                isMinorAction = action.isMinorAction == true,
            })
        else
            result.success = false
            result.description = "Cannot prepare dodge: " .. (err or "unknown")
        end
    end

    --- Prepare a Riposte defense (S4.9)
    -- Riposte triggers a counter-attack when attacked
    function resolver:resolveRipostePrepare(action, result)
        local actor = action.actor
        local card = action.card

        if not actor or not card then
            result.success = false
            result.description = "Invalid riposte attempt"
            return
        end

        local defenseValue = result.testValue or (card.value or 0)

        -- Prepare the riposte defense
        local success, err, replacedDefense = actor:prepareDefense("riposte", card, defenseValue)

        if success then
            result.success = true
            result.description = "Ready to riposte! (Counter-attack with value " .. defenseValue .. ")"
            result.effects[#result.effects + 1] = "riposte_prepared"

            if replacedDefense then
                result.replacedDefense = replacedDefense
                result.replacedDefenseDiscarded = self:discardReplacedDefense(action, replacedDefense)
                result.effects[#result.effects + 1] = "defense_replaced"
                result.description = result.description .. " Replaced previous facedown defense."

                self.eventBus:emit("defense_replaced", {
                    entity = actor,
                    oldType = replacedDefense.type,
                    oldCard = replacedDefense.card,
                    newType = "riposte",
                    discarded = result.replacedDefenseDiscarded,
                })
            end

            self.eventBus:emit("defense_prepared", {
                entity = actor,
                type = "riposte",
                value = defenseValue,
                faceValue = card.value or 0,
                modifier = defenseValue - (card.value or 0),
                isMinorAction = action.isMinorAction == true,
            })
        else
            result.success = false
            result.description = "Cannot prepare riposte: " .. (err or "unknown")
        end
    end

    function resolver:resolveHeal(action, result)
        if result.success then
            local target = action.target or action.actor

            if target and (target.immuneToHealEffect or target.immuneToHeal) then
                result.success = false
                result.description = "Cannot heal: immune to the Heal effect."
                result.effects[#result.effects + 1] = "heal_immune"
                return
            end

            -- Attempt to heal wound (respects stress gate)
            local healResult, err = target:healWound()

            if healResult then
                result.description = "Healed: " .. healResult
                result.effects[#result.effects + 1] = "healed"
            else
                result.success = false
                result.description = "Cannot heal: " .. (err or "unknown")
                if err == "healing_blocked" then
                    result.effects[#result.effects + 1] = "healing_blocked"
                end
            end
        else
            result.description = "Healing failed!"
        end
    end

    ----------------------------------------------------------------------------
    -- WANDS RESOLUTION (Banter/Magic)
    ----------------------------------------------------------------------------

    function resolver:resolveWandsAction(action, result)
        local actionType = self:normalizeActionType(action.type or M.ACTION_TYPES.BANTER)

        if actionType == M.ACTION_TYPES.BANTER then
            self:resolveBanter(action, result)
        elseif actionType == M.ACTION_TYPES.SPEAK_INCANTATION then
            self:resolveSpeakIncantation(action, result)
        elseif actionType == M.ACTION_TYPES.COUNTER_SPELL then
            self:resolveCounterSpell(action, result)
        elseif actionType == M.ACTION_TYPES.RECOVER then
            -- S7.4: Recover action
            self:resolveRecover(action, result)
        else
            self:resolveBanter(action, result)
        end
    end

    --- S7.4: Recover - clear one negative status effect in priority order
    function resolver:clearRecoveredDuration(actor, condition)
        local durations = actor and actor.conditionDurations
        local duration = durations and durations[condition]
        if duration and duration["until"] == "recover" then
            durations[condition] = nil
            if next(durations) == nil then
                actor.conditionDurations = nil
            end
            return true
        end
        return false
    end

    function resolver:resolveRecover(action, result)
        local actor = action.actor

        if not actor or not actor.conditions then
            result.success = false
            result.description = "Nothing to recover from."
            return
        end

        -- Priority order for clearing conditions (per S7.4 spec)
        local conditions = actor.conditions
        local cleared = nil
        local requested = normalizeTalentKey(action.recoverEffect or action.condition or action.effect or action.recover)
        local function wants(...)
            if requested == "" then
                return true
            end
            for _, name in ipairs({ ... }) do
                if requested == name then
                    return true
                end
            end
            return false
        end

        if wants("webbed", "web", "webbed_limb", "webbed_limbs") and
           (conditions.webbed or (actor.webbedLimbs and actor.webbedLimbs > 0)) then
            local remainingLimbs = actor.webbedLimbs or 1
            if remainingLimbs > 1 then
                actor.webbedLimbs = remainingLimbs - 1
                conditions.rooted = true
                cleared = "webbed_limb"
                result.description = "Freed one limb from webs (" .. actor.webbedLimbs .. " remain)."
            else
                actor.webbedLimbs = 0
                conditions.webbed = false
                conditions.rooted = false
                cleared = "webbed"
                result.description = "Freed from webs!"
            end
        elseif wants("rooted", "root") and conditions.rooted and not (conditions.bindingRooted or actor.bindingRootedBy or
               (actor.nonRecoverableConditions and actor.nonRecoverableConditions.rooted)) then
            conditions.rooted = false
            if actor.cockatriceGazeRooted or actor.rootedBy == "cockatrice_gaze" then
                actor.cockatriceGazeRooted = false
                actor.cockatriceGazeSource = nil
                actor.cockatriceGazeRound = nil
                if actor.rootedBy == "cockatrice_gaze" then
                    actor.rootedBy = nil
                end
            end
            if actor.griffinGrabbedBy or actor.rootedBy == "griffin_grab" then
                local griffin = actor.griffinGrabbedBy
                local causesFall = actor.griffinGrabRecoverCausesFallingDamage
                local fallHeight = actor.griffinGrabFallHeightFeet
                if not action.heightFeet and not action.roomHeightFeet and not action.fallHeightFeet and fallHeight then
                    action.heightFeet = fallHeight
                end
                self:releaseGriffinGrab(griffin, actor, "recover")
                result.effects[#result.effects + 1] = "griffin_grab_released"
                if causesFall then
                    self:applyGriffinGrabFall(actor, action, result, "recover")
                end
            end
            cleared = "rooted"
        elseif wants("prone", "trip", "tripped") and conditions.prone then
            conditions.prone = false
            cleared = "prone"
        elseif wants("blind", "blinded") and (conditions.blind or conditions.blinded) then
            conditions.blind = false
            conditions.blinded = false
            if actor.conditionDurations then
                actor.conditionDurations.blind = nil
                actor.conditionDurations.blinded = nil
            end
            cleared = "blind"
        elseif wants("deaf", "deafened") and (conditions.deaf or conditions.deafened) then
            conditions.deaf = false
            conditions.deafened = false
            if actor.conditionDurations then
                actor.conditionDurations.deaf = nil
                actor.conditionDurations.deafened = nil
            end
            cleared = "deaf"
        elseif wants("silence", "silent", "silenced") and conditions.silenced then
            conditions.silenced = false
            actor.silenced = false
            if actor.conditionDurations then
                actor.conditionDurations.silenced = nil
            end
            cleared = "silenced"
        elseif wants("exhausted", "exhaust") and conditions.exhausted and
               not (actor.nonRecoverableConditions and actor.nonRecoverableConditions.exhausted) then
            conditions.exhausted = false
            actor.exhausted = false
            if actor.conditionDurations then
                actor.conditionDurations.exhausted = nil
            end
            cleared = "exhausted"
        elseif wants("burning", "on_fire", "fire") and (conditions.burning or conditions.onFire) then
            conditions.burning = false
            conditions.onFire = false
            actor.onFire = false
            cleared = "burning"
        elseif wants("disarmed", "disarm", "dropped_item", "weapon") and conditions.disarmed then
            local recoveredItem, recoverErr = self:recoverDroppedItem(actor)
            if recoverErr then
                result.success = false
                result.description = "Cannot recover dropped item: " .. tostring(recoverErr)
                result.effects[#result.effects + 1] = "recover_dropped_item_blocked"
                return
            end
            conditions.disarmed = false
            cleared = "disarmed"
            result.recoveredItem = recoveredItem
            result.description = "Recovered Weapon!"
            result.effects[#result.effects + 1] = "weapon_recovered"
        elseif wants("rooted", "root") and conditions.rooted then
            result.description = "Rooted by Binding; the spell must be countered or interrupted."
            result.effects[#result.effects + 1] = "binding_rooted"
        elseif wants("maledicted", "malediction", "curse", "cursed") and conditions.maledicted then
            result.description = "Malediction is a Curse; Recover cannot clear it."
            result.effects[#result.effects + 1] = "malediction_recover_blocked"
        end

        if cleared then
            result.success = true
            if not result.description or result.description == "" then
                result.description = "Recovered from " .. cleared .. "!"
            end
            result.effects[#result.effects + 1] = "recovered_" .. cleared
            if self:clearRecoveredDuration(actor, cleared) then
                result.effects[#result.effects + 1] = "recovered_duration_cleared"
            end
        else
            result.success = false
            if not result.description or result.description == "" then
                if requested ~= "" then
                    result.description = "Cannot recover from " .. requested .. "."
                    result.effects[#result.effects + 1] = "recover_effect_unavailable"
                else
                    result.description = "Nothing to recover from."
                end
            end
        end
    end

    --- Resolve Banter (attacks Morale instead of Health)
    -- S12.3: Updated to use dynamic morale calculation
    -- S12.4: Applies disposition modifiers and shifts disposition
    function resolver:resolveBanter(action, result)
        -- Banter compares vs target's Morale (p. 119)
        -- Difficulty = target's current morale + disposition modifier

        local target = action.target
        if not target then
            result.description = "No target for banter!"
            return
        end
        if applyRhymedSpeechSocialGate(action, result) then
            return
        end
        if applyLockedSpeechSocialGate(action, result, target) then
            return
        end

        self:applyPreparedRoomSocialEffects(action, result, target)

        -- S12.3: Get target's current morale (dynamically calculated)
        local targetMorale = 10  -- Default fallback
        if target.getMorale then
            targetMorale = target:getMorale()
        elseif target.baseMorale then
            targetMorale = target.baseMorale
        end

        -- S12.4: Apply disposition modifier
        local dispositionMod = 0
        local targetDisposition = target.disposition or "distaste"
        if disposition_module then
            dispositionMod = disposition_module.getSocialModifier(targetDisposition, "banter")
        end

        local socialTags = collectSocialTags(action.socialTags or action.banterTags or action.approach or action.socialApproach)
        local liked, likedTag = hasSocialTag(target.social and target.social.likes, socialTags)
        local disliked, dislikedTag = hasSocialTag(
            (target.social and (target.social.dislikes or target.social.hates)) or nil,
            socialTags
        )
        local favorModifier = 0
        if liked then
            favorModifier = favorModifier + 3
            result.effects[#result.effects + 1] = "social_favor"
        end
        if disliked then
            favorModifier = favorModifier - 3
            result.effects[#result.effects + 1] = "social_disfavor"
        end
        local maledictionModifier = getMaledictionSocialModifier(action.actor, target)
        if maledictionModifier ~= 0 then
            favorModifier = favorModifier + maledictionModifier
            result.effects[#result.effects + 1] = "malediction_social_disfavor"
            result.effects[#result.effects + 1] = "desiccated_corpse_hostility"
            result.maledictionSocialModifier = maledictionModifier
        end
        if action.actor and action.actor.faceRatDiseaseWandsDisfavor then
            favorModifier = favorModifier - 3
            result.effects[#result.effects + 1] = "face_rat_disease_wands_disfavor"
        end

        -- Override difficulty with morale + disposition modifier
        result.difficulty = targetMorale + dispositionMod
        result.testValue = result.testValue + favorModifier
        result.socialModifier = favorModifier
        applyPactSocialModifier(action, result)
        applySocialPactBreaks(self, action, result)
        result.socialFavorTag = likedTag
        result.socialDisfavorTag = dislikedTag

        -- Recalculate success based on morale difficulty
        result.success = result.testValue > result.difficulty

        -- Reveal disposition and morale on ANY banter attempt (you learn by trying)
        self.eventBus:emit("social_discovery", {
            target = target,
            targetId = target.id,
            discoveries = { "disposition", "morale" },
        })

        if result.success then
            result.description = "Verbal hit! "
            result.effects[#result.effects + 1] = "morale_damage"

            -- Apply morale damage via modifier
            local moraleDamage = 2  -- Base banter damage
            if result.isGreat then
                moraleDamage = 4  -- Great success deals double
                result.description = result.description .. "Great Success! "

                -- Great success also reveals likes/dislikes
                self.eventBus:emit("social_discovery", {
                    target = target,
                    targetId = target.id,
                    discoveries = { "hates", "wants" },
                })
            end

            -- S12.3: Apply morale damage as temporary modifier
            if target.modifyMorale then
                target:modifyMorale(-moraleDamage)
            end

            -- S12.4: Shift disposition toward the declared social intent.
            local oldDisposition = target.getDisposition and target:getDisposition() or target.disposition or "distaste"
            local oldDispositionSeverity = target.getDispositionSeverity and target:getDispositionSeverity()
                or target.dispositionSeverity
                or 2
            local dispositionTarget = banterIntentTarget(action.banterIntent or action.intent or action.dispositionTarget or action.banterGoal)
            local shiftAmount = result.isGreat and 2 or 1
            local newDisposition, newDispositionSeverity, dispositionChange = disposition_module.moveTowardState(
                oldDisposition,
                oldDispositionSeverity,
                dispositionTarget,
                shiftAmount)
            if target.setDisposition then
                target:setDisposition(newDisposition, newDispositionSeverity)
            else
                target.disposition = newDisposition
                target.dispositionSeverity = newDispositionSeverity
            end
            self:endCharmForDispositionChange(
                target,
                oldDisposition,
                newDisposition,
                action,
                oldDispositionSeverity,
                newDispositionSeverity)
            result.oldDisposition = oldDisposition
            result.oldDispositionSeverity = oldDispositionSeverity
            result.newDisposition = newDisposition
            result.newDispositionSeverity = newDispositionSeverity
            result.newDispositionLabel = disposition_module.getDispositionLabel(newDisposition, newDispositionSeverity)
            result.dispositionTarget = dispositionTarget
            result.dispositionChange = dispositionChange
            result.effects[#result.effects + 1] = "disposition_shift"
            applySocialOutcomeToResult(result, target,
                disposition_module.getSocialOutcome(newDisposition, newDispositionSeverity))

            result.moraleDamage = moraleDamage

            -- Check for morale break (morale drops to 0 or below)
            local newMorale = 10
            if target.getMorale then
                newMorale = target:getMorale()
            end

            if newMorale <= 0 then
                result.effects[#result.effects + 1] = "morale_broken"
                result.description = result.description .. "Morale broken!"

                if target.conditions then
                    target.conditions.fleeing = true
                end
            else
                result.description = result.description .. string.format("Morale: %d -> %d", targetMorale, newMorale)
            end
        else
            -- S12.4: Failed banter can anger the target
            local oldDisposition = target.getDisposition and target:getDisposition() or target.disposition or "distaste"
            local oldDispositionSeverity = target.getDispositionSeverity and target:getDispositionSeverity()
                or target.dispositionSeverity
                or 2
            local newDisposition, newDispositionSeverity, dispositionChange = disposition_module.moveTowardState(
                oldDisposition,
                oldDispositionSeverity,
                disposition_module.DISPOSITIONS.ANGER,
                1)
            if target.setDisposition then
                target:setDisposition(newDisposition, newDispositionSeverity)
            else
                target.disposition = newDisposition
                target.dispositionSeverity = newDispositionSeverity
            end
            self:endCharmForDispositionChange(
                target,
                oldDisposition,
                newDisposition,
                action,
                oldDispositionSeverity,
                newDispositionSeverity)
            result.oldDisposition = oldDisposition
            result.oldDispositionSeverity = oldDispositionSeverity
            result.newDisposition = newDisposition
            result.newDispositionSeverity = newDispositionSeverity
            result.newDispositionLabel = disposition_module.getDispositionLabel(newDisposition, newDispositionSeverity)
            result.dispositionChange = dispositionChange
            applySocialOutcomeToResult(result, target,
                disposition_module.getSocialOutcome(newDisposition, newDispositionSeverity))
            result.description = string.format("Banter ineffective! (needed %d, got %d)", result.difficulty, result.testValue)
        end
    end

    function resolver:getSpellFromAction(action)
        if not action then
            return nil
        end

        return spell_registry.getSpell(
            action.spell or
            action.spellId or
            action.spellName or
            (action.actor and action.actor.selectedSpell)
        )
    end

    local function normalizeSpellKey(value)
        return spell_registry.normalizeId(value)
    end

    local function spellEntityKey(entity)
        if not entity then
            return nil
        end
        if type(entity) == "table" then
            return entity.id or entity.name or tostring(entity)
        end
        return tostring(entity)
    end

    local GIVE_FORM_NIL = {}

    local function rememberField(container, key)
        if not container or container[key] == nil then
            return GIVE_FORM_NIL
        end
        return container[key]
    end

    local function restoreField(container, key, value)
        if not container then
            return
        end
        if value == GIVE_FORM_NIL then
            container[key] = nil
        else
            container[key] = value
        end
    end

    local function actionIsChallenge(action)
        return action and (action.inChallenge == true or action.challenge == true or action.phase == "challenge" or
            action.challengeController ~= nil)
    end

    local function collectGiveFormRooms(action, target)
        action = action or {}
        local rooms = {}
        local seen = {}

        local function addRoom(roomRef, contents)
            if roomRef == nil or roomRef == false then
                return
            end

            local entry
            if type(roomRef) == "table" then
                local id = roomRef.id or roomRef.roomId or roomRef.key or roomRef.name
                entry = {
                    id = id,
                    room = roomRef,
                    contents = contents or roomRef.contents or roomRef.roomContents,
                }
            else
                entry = {
                    id = tostring(roomRef),
                    contents = contents,
                }
            end

            local key = entry.id or tostring(roomRef)
            if seen[key] then
                return
            end

            seen[key] = true
            rooms[#rooms + 1] = entry
        end

        local source = action.rooms or action.targetRooms or action.roomIds or action.affectedRooms
        if type(source) == "table" then
            for _, roomRef in ipairs(source) do
                addRoom(roomRef)
            end
            for key, contents in pairs(source) do
                if type(key) ~= "number" and contents then
                    addRoom(key, contents)
                end
            end
        elseif source ~= nil then
            addRoom(source)
        end

        addRoom(action.room or action.targetRoom or action.currentRoom or action.location)
        addRoom(action.roomId or action.targetRoomId or action.currentRoomId or action.locationId)
        addRoom(target)

        return rooms
    end

    local function giveFormAllowedRooms(spell, resolveSpent)
        local baseRooms = spell and spell.baseRooms or 1
        local extraRoomResolve = spell and spell.extraRoomResolve or 1
        local extraResolve = math.max(0, (tonumber(resolveSpent) or 1) - 1)
        return baseRooms + math.floor(extraResolve / math.max(1, extraRoomResolve))
    end

    local function validateGiveFormToNothingness(action, spell, resolveSpent, target)
        local rooms = collectGiveFormRooms(action, target)
        if #rooms < 1 then
            return false, "Give Form to Nothingness needs a target room.", "give_form_room_missing"
        end

        if #rooms > giveFormAllowedRooms(spell, resolveSpent) then
            return false, "Give Form to Nothingness needs one additional Resolve per extra room.",
                "give_form_too_many_rooms"
        end

        if action and (action.playingDrum == false or action.drumPlayed == false or action.performing == false) then
            return false, "Give Form to Nothingness lasts only while the rune-painted drum is played.",
                "give_form_drum_not_played"
        end

        return true, nil, nil, rooms
    end

    local function validateGiveFormDrumUse(action, actor, component)
        if not actionIsChallenge(action) then
            return true
        end

        local inventory = actor and actor.inventory
        if not inventory or not inventory.getItems then
            return true
        end

        for _, item in ipairs(inventory:getItems("hands") or {}) do
            if item ~= component then
                return false, "The rune-painted drum requires both hands to play during Challenges.",
                    "give_form_drum_requires_two_hands"
            end
        end

        return true
    end

    local function collectGiveFormSubjects(action, rooms)
        action = action or {}
        local subjects = {}
        local seen = {}

        local function addSubject(subject)
            if type(subject) ~= "table" or seen[subject] then
                return
            end
            seen[subject] = true
            subjects[#subjects + 1] = subject
        end

        local function collectList(list)
            if type(list) ~= "table" then
                return
            end
            for _, subject in ipairs(list) do
                addSubject(subject)
            end
        end

        local function collectContainer(container)
            if type(container) ~= "table" then
                return
            end

            collectList(container.entities)
            collectList(container.creatures)
            collectList(container.objects)
            collectList(container.items)
            collectList(container.features)
            collectList(container.occupants)

            if container.invisible ~= nil or container.intangible ~= nil or container.ethereal ~= nil or
               container.incorporeal ~= nil or container.visible ~= nil or container.tangible ~= nil then
                addSubject(container)
            end
        end

        collectList(action.subjects)
        collectList(action.entities)
        collectList(action.creatures)
        collectList(action.objects)
        collectList(action.items)

        local roomContents = action.roomContents or action.roomsById
        for _, roomEntry in ipairs(rooms or {}) do
            collectContainer(roomEntry.room)
            collectContainer(roomEntry.contents)
            if roomContents and roomEntry.id then
                collectContainer(roomContents[roomEntry.id])
            end
        end

        return subjects
    end

    local function subjectNeedsGiveForm(subject)
        if type(subject) ~= "table" then
            return false
        end

        local conditions = subject.conditions or {}
        local props = subject.properties or {}

        return subject.invisible == true or subject.visible == false or subject.intangible == true or
            subject.tangible == false or subject.ethereal == true or subject.incorporeal == true or
            conditions.invisible == true or conditions.intangible == true or conditions.ethereal == true or
            conditions.incorporeal == true or props.invisible == true or props.visible == false or
            props.intangible == true or props.tangible == false or props.ethereal == true or
            props.incorporeal == true
    end

    local GIVE_FORM_FIELDS = {
        "invisible",
        "visible",
        "intangible",
        "tangible",
        "ethereal",
        "incorporeal",
    }

    local function makeSubjectVisibleAndTangible(subject, actor, spell)
        local record = {
            subject = subject,
            fields = {},
            conditions = {},
            properties = {},
        }

        for _, key in ipairs(GIVE_FORM_FIELDS) do
            record.fields[key] = rememberField(subject, key)
        end

        subject.invisible = false
        subject.visible = true
        subject.intangible = false
        subject.tangible = true
        subject.ethereal = false
        subject.incorporeal = false
        subject.givenFormBy = actor
        subject.givenFormSpellId = spell and spell.id

        subject.conditions = subject.conditions or {}
        for _, key in ipairs(GIVE_FORM_FIELDS) do
            record.conditions[key] = rememberField(subject.conditions, key)
        end
        subject.conditions.invisible = false
        subject.conditions.visible = true
        subject.conditions.intangible = false
        subject.conditions.tangible = true
        subject.conditions.ethereal = false
        subject.conditions.incorporeal = false

        if subject.properties then
            for _, key in ipairs(GIVE_FORM_FIELDS) do
                record.properties[key] = rememberField(subject.properties, key)
            end
            subject.properties.invisible = false
            subject.properties.visible = true
            subject.properties.intangible = false
            subject.properties.tangible = true
            subject.properties.ethereal = false
            subject.properties.incorporeal = false
        end

        return record
    end

    local function restoreGiveFormSubject(record)
        local subject = record and record.subject
        if not subject then
            return
        end

        for key, value in pairs(record.fields or {}) do
            restoreField(subject, key, value)
        end
        for key, value in pairs(record.conditions or {}) do
            restoreField(subject.conditions, key, value)
        end
        for key, value in pairs(record.properties or {}) do
            restoreField(subject.properties, key, value)
        end

        subject.givenFormBy = nil
        subject.givenFormSpellId = nil
    end

    local function isDarklightCandleTarget(target)
        if not target or target.destroyed then
            return false
        end

        local props = target.properties or {}
        if props.candle == true or props.darklightCandle == true then
            return true
        end
        if type(props.tags) == "table" and (props.tags.candle or tableContainsValue(props.tags, "candle")) then
            return true
        end

        local name = normalizeSpellKey(target.name or target.templateId or target.id)
        return name == "candle" or name == "candles" or string.find(name, "candle", 1, true) ~= nil
    end

    local function actorHoldsSpellObject(actor, target)
        if not actor or not target or not target.id or not actor.inventory or not actor.inventory.findItem then
            return true
        end

        local _, location = actor.inventory:findItem(target.id)
        return location == "hands"
    end

    local function addDarklightViewer(viewers, viewerIds, seen, viewer)
        local key = spellEntityKey(viewer)
        if not key or seen[key] then
            return
        end

        seen[key] = true
        viewers[#viewers + 1] = viewer
        viewerIds[#viewerIds + 1] = key
    end

    local function collectDarklightViewers(action)
        action = action or {}
        local viewers = {}
        local viewerIds = {}
        local seen = {}
        local source = action.darklightViewers or action.additionalViewers or action.viewers or action.visibleTo

        if type(source) == "table" then
            for key, value in pairs(source) do
                if type(key) == "number" then
                    addDarklightViewer(viewers, viewerIds, seen, value)
                elseif value ~= false then
                    addDarklightViewer(viewers, viewerIds, seen, key)
                end
            end
        elseif source then
            addDarklightViewer(viewers, viewerIds, seen, source)
        end

        addDarklightViewer(viewers, viewerIds, seen, action.darklightViewer or action.additionalViewer)
        return viewers, viewerIds
    end

    local function validateDarklight(action, spell, resolveSpent, target)
        if not isDarklightCandleTarget(target) then
            return false, "Darklight requires a candle target.", "darklight_candle_missing"
        end
        if target.darklight and target.darklight.active ~= false then
            return false, "That candle is already under Darklight.", "darklight_already_active"
        end
        if not actorHoldsSpellObject(action and action.actor, target) then
            return false, "Darklight's candle must be held.", "darklight_candle_not_held"
        end

        local viewers, viewerIds = collectDarklightViewers(action)
        local allowedViewers = math.max(0, (resolveSpent or 1) - 1)
        if #viewerIds > allowedViewers then
            return false, "Darklight needs more Resolve for that many extra viewers.", "darklight_too_many_viewers"
        end

        return true, nil, nil, viewers, viewerIds
    end

    local FAR_REALM_ALIASES = {
        waste = "wastes",
        wastes = "wastes",
        weald = "weald",
        weird = "weird",
        welkin = "welkin",
    }

    local function normalizeFarRealm(value)
        local normalized = normalizeSpellKey(value)
        return FAR_REALM_ALIASES[normalized]
    end

    local function addCircleRealm(realms, realmSet, value)
        local realm = normalizeFarRealm(value)
        if realm and not realmSet[realm] then
            realmSet[realm] = true
            realms[#realms + 1] = realm
        end
    end

    local function collectCircleProtectionRealms(action)
        action = action or {}
        local realms = {}
        local realmSet = {}

        if type(action.realms) == "table" then
            for _, realm in ipairs(action.realms) do
                addCircleRealm(realms, realmSet, realm)
            end
            for key, value in pairs(action.realms) do
                if type(key) ~= "number" and value then
                    addCircleRealm(realms, realmSet, key)
                end
            end
        end

        addCircleRealm(realms, realmSet, action.realm or action.farRealm or action.selectedRealm)
        return realms, realmSet
    end

    local function validateCircleProtection(action, spell, resolveSpent)
        action = action or {}
        local realms = collectCircleProtectionRealms(action)
        local realmCount = #realms

        if spell and spell.requiresPreparedCircle and action.circlePrepared ~= true and action.preparedCircle ~= true then
            return false, "Circle of Protection requires a prepared rune circle.", "circle_not_prepared"
        end

        if realmCount < 1 then
            return false, "Circle of Protection requires a selected far realm.", "circle_realm_missing"
        end

        local baseRealms = spell and spell.baseRealms or 1
        local extraRealmResolve = spell and spell.extraRealmResolve or 1
        local requiredResolve = 1 + math.max(0, realmCount - baseRealms) * extraRealmResolve
        if resolveSpent < requiredResolve then
            return false, "Circle of Protection needs more Resolve for that many realms.", "circle_too_many_realms"
        end

        return true, nil, nil, realms
    end

    local function tableHasKeyOrValue(list, key)
        if type(list) ~= "table" then
            return false
        end

        for listKey, value in pairs(list) do
            if normalizeSpellKey(listKey) == key and value ~= false then
                return true
            end
            if type(value) == "string" and normalizeSpellKey(value) == key then
                return true
            end
            if type(value) == "table" then
                local valueId = normalizeSpellKey(value.id or value.name)
                if valueId == key and value.mastered ~= false then
                    return true
                end
            end
        end

        return false
    end

    function resolver:getTalentEntry(actor, talentId)
        local talents = actor and actor.talents
        if type(talents) ~= "table" then
            return nil
        end

        local normalizedTalentId = normalizeSpellKey(talentId)
        for key, value in pairs(talents) do
            if normalizeSpellKey(key) == normalizedTalentId then
                return value
            end
            if type(value) == "table" and normalizeSpellKey(value.id or value.name) == normalizedTalentId then
                return value
            end
        end

        return nil
    end

    function resolver:actorKnowsSpell(actor, spell)
        if not actor or not spell then
            return false
        end

        local spellId = normalizeSpellKey(spell.id)
        local talentId = normalizeSpellKey(spell.talent)

        if tableHasKeyOrValue(actor.knownSpells, spellId) or tableHasKeyOrValue(actor.spells, spellId) then
            return true
        end

        local branchTalent = "magic_of_the_" .. normalizeSpellKey(spell.branch)
        local talent = self:getTalentEntry(actor, talentId) or self:getTalentEntry(actor, branchTalent)
        if talent then
            if type(talent) == "table" and talent.wounded then
                return false
            end
            return true
        end

        return false
    end

    function resolver:spellUsesTrainingXP(actor, spell)
        if not actor or not spell then
            return false
        end

        local spellId = normalizeSpellKey(spell.id)
        if tableHasKeyOrValue(actor.knownSpells, spellId) or tableHasKeyOrValue(actor.spells, spellId) then
            return false
        end

        local talentId = normalizeSpellKey(spell.talent)
        local branchTalent = "magic_of_the_" .. normalizeSpellKey(spell.branch)
        local talent = self:getTalentEntry(actor, talentId) or self:getTalentEntry(actor, branchTalent)
        return type(talent) == "table" and talent.mastered == false
    end

    function resolver:spendTrainingXP(actor)
        if not actor then
            return false
        end

        if actor.xp ~= nil then
            if actor.xp < 1 then
                return false
            end
            actor.xp = actor.xp - 1
            return true
        end

        if actor.experience ~= nil then
            if actor.experience < 1 then
                return false
            end
            actor.experience = actor.experience - 1
            return true
        end

        return false
    end

    function resolver:hasTrainingXP(actor)
        if not actor then
            return false
        end

        if actor.xp ~= nil then
            return actor.xp >= 1
        end

        if actor.experience ~= nil then
            return actor.experience >= 1
        end

        return false
    end

    function resolver:findSpellComponent(actor, spell)
        local inventory = actor and actor.inventory
        if not inventory or not inventory.getItems or not spell then
            return nil, nil
        end

        local hands = inventory:getItems("hands") or {}
        for _, item in ipairs(hands) do
            local props = item.properties or {}
            if props.spellComponent then
                if props.componentFor == spell.id or item.templateId == spell.componentId then
                    return item, "hands"
                end
                if props.branch and props.branch == spell.branch and props.componentFor == "any" then
                    return item, "hands"
                end
            end
        end

        return nil, nil
    end

    function resolver:getPactChargeForSpell(component, spell)
        if not component or not spell then
            return nil
        end

        local props = component.properties or {}
        local charge = component.pactCharge or props.pactCharge
        if type(charge) ~= "table" or charge.active == false or charge.spent then
            return nil
        end
        if props.pactCharged == false then
            return nil
        end

        local componentFor = charge.componentFor or props.componentFor
        if componentFor and componentFor ~= "any" and componentFor ~= spell.id then
            return nil
        end

        return charge
    end

    function resolver:spendPactCharge(component, charge, spell, actor)
        if not component or not charge then
            return nil
        end

        charge.spent = true
        charge.active = false
        charge.spentForSpell = spell and spell.id
        charge.spentBy = actor and actor.id

        component.pactCharge = nil
        component.properties = component.properties or {}
        component.properties.pactCharged = false
        component.properties.pactCharge = nil

        return charge
    end

    local function itemHasSignificantIron(item)
        if not item then
            return false
        end

        local props = item.properties or {}
        local material = props.material or item.material
        if material == "iron" or material == "steel" then
            return props.significantMetal ~= false
        end
        if props.iron or props.steel or item.iron or item.steel then
            return props.significantMetal ~= false
        end
        if item.isArmor and (props.metal or props.ironArmor or props.steelArmor) then
            return true
        end

        return false
    end

    function resolver:hasSignificantIron(entity)
        if not entity then
            return false
        end

        local conditions = entity.conditions or {}
        if entity.spellTargetBlocked or entity.cannotBeTargetedBySpells or entity.cannotCastSpells or
           conditions.spell_target_blocked or conditions.ungoat_spell_ward or conditions.cannot_cast_spells then
            return true
        end

        if entity.hasSignificantIron or entity.carriesSignificantIron or entity.wearingIronArmor then
            return true
        end

        if entity.inventory and entity.inventory.getAllItems then
            for _, entry in ipairs(entity.inventory:getAllItems()) do
                if itemHasSignificantIron(entry.item) then
                    return true
                end
            end
        end

        return false
    end

    function resolver:canSpeakSpell(actor)
        if not actor then
            return false
        end

        local conditions = actor.conditions or {}
        if actor.canSpeak == false or actor.mute or actor.silenced then
            return false
        end
        if conditions.mute or conditions.silenced or conditions.gagged then
            return false
        end

        return true
    end

    function resolver:canSeeOrTouchSpellTarget(action)
        if not action or not action.target then
            return true
        end
        if action.canSeeOrTouch == false then
            return false
        end
        if action.canSeeTarget == false and action.canTouchTarget == false then
            return false
        end

        return true
    end

    function resolver:spendSpellResolve(actor, amount)
        amount = amount or 1
        if not actor then
            return false, "missing_actor"
        end
        if amount <= 0 then
            return true, nil
        end
        if actor.spendResolve then
            local ok, reason = actor:spendResolve(amount)
            if ok then
                return true, nil
            end
            return false, reason or "not_enough_resolve"
        end

        if type(actor.resolve) == "table" then
            if (actor.resolve.current or 0) < amount then
                return false, "not_enough_resolve"
            end
            actor.resolve.current = actor.resolve.current - amount
        elseif actor.resolve ~= nil then
            if actor.resolve < amount then
                return false, "not_enough_resolve"
            end
            actor.resolve = actor.resolve - amount
        end

        return true, nil
    end

    function resolver:getCounterSpellIncomingValue(action)
        if not action then
            return 0
        end

        if action.enemyValue ~= nil then
            return action.enemyValue
        end
        if action.incomingValue ~= nil then
            return action.incomingValue
        end
        if action.spellValue ~= nil then
            return action.spellValue
        end

        local incoming = action.incomingAction or action.spellAction or action.targetAction
        local incomingResult = action.incomingResult or (incoming and incoming.result)
        if incomingResult then
            return incomingResult.testValue or incomingResult.spellValue or incomingResult.value or 0
        end

        if incoming then
            if incoming.testValue ~= nil then
                return incoming.testValue
            end
            if incoming.spellValue ~= nil then
                return incoming.spellValue
            end
            local cardValue = incoming.card and incoming.card.value or 0
            local modifier = incoming.modifier
            if modifier == nil and incoming.actor then
                modifier = incoming.actor.wands or 0
            end
            return cardValue + (modifier or 0)
        end

        return 0
    end

    function resolver:getCounterSpellBranch(action, spell)
        if not action then
            return spell and spell.branch or "unknown"
        end

        local incoming = action.incomingAction or action.spellAction or action.targetAction
        local incomingSpell = spell or (incoming and self:getSpellFromAction(incoming))
        return action.branch or action.spellBranch or
            (incoming and (incoming.branch or incoming.spellBranch)) or
            (incomingSpell and incomingSpell.branch) or
            (action.activeSpell and action.activeSpell.branch) or
            "unknown"
    end

    function resolver:markCounteredSpellAction(action, result, incomingSpell)
        local incoming = action and (action.incomingAction or action.spellAction or action.targetAction)
        if not incoming then
            return
        end

        incoming.countered = true
        incoming.fizzled = true
        incoming.counterSpellResult = result

        if incoming.result then
            incoming.result.success = false
            incoming.result.countered = true
            incoming.result.fizzled = true
            incoming.result.counterSpell = result
            incoming.result.effects = incoming.result.effects or {}
            incoming.result.effects[#incoming.result.effects + 1] = "counter_spell_fizzled"
            incoming.result.description = (incomingSpell and incomingSpell.name or "Spell") .. " fizzles."
        end
    end

    function resolver:resolveCounterSpell(action, result)
        action = action or {}
        result = result or {
            success = false,
            effects = {},
            description = "",
            testValue = action.counterValue or 0,
        }
        result.effects = result.effects or {}
        local actor = action.actor
        result.counterSpell = true

        if not entityHasUsableTalent(actor, "counter_spell") then
            result.success = false
            result.description = "Requires Counter-spell."
            result.effects[#result.effects + 1] = "requires_counter_spell"
            return result
        end

        if not self:canSpeakSpell(actor) then
            result.success = false
            result.description = "Cannot counter-spell without speaking."
            result.effects[#result.effects + 1] = "counter_spell_silenced"
            return result
        end

        if action.canPerceiveCasting == false or action.canPerceiveCaster == false then
            result.success = false
            result.description = "Cannot perceive the spell being cast."
            result.effects[#result.effects + 1] = "counter_spell_caster_unseen"
            return result
        end

        local mode = action.mode or action.counterSpellMode
        local activeSpell = action.activeSpell or action.spellEntry or action.ongoingSpell
        local spellCaster = action.spellCaster or action.targetCaster or action.caster or
            (activeSpell and activeSpell.caster) or action.target
        if mode == "ongoing" or mode == "negate" or mode == "active" or activeSpell then
            if not activeSpell then
                result.success = false
                result.description = "No ongoing spell selected."
                result.effects[#result.effects + 1] = "counter_spell_missing_ongoing_spell"
                return result
            end
            if not spellCaster then
                result.success = false
                result.description = "No caster found for the ongoing spell."
                result.effects[#result.effects + 1] = "counter_spell_missing_caster"
                return result
            end
        elseif not action.incomingAction and not action.spellAction and not action.targetAction and
               action.enemyValue == nil and action.incomingValue == nil and action.spellValue == nil then
            result.success = false
            result.description = "No incoming spell selected."
            result.effects[#result.effects + 1] = "counter_spell_missing_incoming_spell"
            return result
        end

        local spent, spendReason = self:spendResolveForFavor(actor)
        if not spent then
            result.success = false
            result.description = "Cannot counter-spell: " .. (spendReason or "resolve unavailable") .. "."
            result.effects[#result.effects + 1] = "resolve_missing"
            return result
        end

        result.resolveSpent = 1
        result.effects[#result.effects + 1] = "resolve_spent_for_counter_spell"

        if mode == "ongoing" or mode == "negate" or mode == "active" or activeSpell then

            result.success = true
            result.spellFizzled = true
            result.endedSpell = self:endOngoingSpell(spellCaster, activeSpell, "countered", {
                source = action,
            })
            result.effects[#result.effects + 1] = "counter_spell_negated"
            result.effects[#result.effects + 1] = "ongoing_spell_ended"
            result.description = (activeSpell.name or "Ongoing spell") .. " is negated."
            self.eventBus:emit("counter_spell_resolved", result)
            return result
        end

        local incoming = action.incomingAction or action.spellAction or action.targetAction
        local incomingSpell = action.incomingSpell or (incoming and self:getSpellFromAction(incoming))
        if type(incomingSpell) ~= "table" then
            incomingSpell = spell_registry.getSpell(incomingSpell)
        end
        if not incomingSpell and type(action.spell) == "table" then
            incomingSpell = action.spell
        elseif not incomingSpell and type(action.spell) == "string" then
            incomingSpell = spell_registry.getSpell(action.spell)
        end
        local enemyValue = self:getCounterSpellIncomingValue(action)
        local counterValue = action.counterValue or result.testValue or 0
        local branch = self:getCounterSpellBranch(action, incomingSpell)

        result.success = true
        result.spellFizzled = true
        result.enemyValue = enemyValue
        result.counterValue = counterValue
        result.counterSpellWon = counterValue > enemyValue
        result.branch = branch
        result.effects[#result.effects + 1] = "counter_spell_fizzled"

        self:markCounteredSpellAction(action, result, incomingSpell)

        if result.counterSpellWon then
            result.description = (incomingSpell and incomingSpell.name or "Spell") .. " fizzles."
        else
            result.description = (incomingSpell and incomingSpell.name or "Spell") ..
                " fizzles, but the counter-magic causes maleficence."
            result.effects[#result.effects + 1] = "counter_spell_maleficence"
            result.maleficence = self:triggerMaleficence(actor, branch, "counter_spell_failed_or_tied", {
                spell = incomingSpell,
                spellId = incomingSpell and incomingSpell.id,
                source = action,
                card = action.maleficenceCard,
                value = action.maleficenceValue,
                suit = action.maleficenceSuit,
                deck = action.maleficenceDeck or action.deck,
                resolve = action.resolveMaleficence == true or action.maleficenceCard ~= nil or
                    action.maleficenceValue ~= nil,
            })
        end

        self.eventBus:emit("counter_spell_resolved", result)
        return result
    end

    function resolver:getDwimmercraftMode(action)
        local mode = normalizeTalentKey(action and (
            action.mode or action.effect or action.dwimmercraftEffect or action.intent
        ) or "showy_illusion")

        if mode == "second_sight" or mode == "focus_second_sight" or mode == "sight" then
            return "second_sight"
        end
        if mode == "levitate" or mode == "lift" or mode == "pull" or mode == "push" or mode == "move_object" then
            return "levitate"
        end
        if mode == "simple_illusion" or mode == "handheld_illusion" or mode == "object_illusion" then
            return "simple_illusion"
        end

        return "showy_illusion"
    end

    function resolver:canDwimmercraftAffectObject(actor, object, action)
        if not object then
            return false, "dwimmercraft_target_missing"
        end
        if action and action.sameZone == false then
            return false, "dwimmercraft_requires_same_zone"
        end
        if actor and object.zone and actor.zone and object.zone ~= actor.zone then
            return false, "dwimmercraft_requires_same_zone"
        end

        local weight = object.weightPounds or object.weightLbs or object.weight or
            (object.properties and (object.properties.weightPounds or object.properties.weightLbs or object.properties.weight))
        if weight and weight > 10 then
            return false, "dwimmercraft_object_too_heavy"
        end

        local size = object.size or object.slots or (object.properties and (object.properties.size or object.properties.slots))
        if object.oversized or object.twoHanded or object.fitsOneHand == false or object.oneHanded == false or
           (size and size > 1) then
            return false, "dwimmercraft_object_too_large"
        end

        return true, nil
    end

    function resolver:recordDwimmercraftIllusion(actor, action, mode)
        actor.dwimmercraftIllusions = actor.dwimmercraftIllusions or {}
        local illusion = {
            id = action.illusionId or ("dwimmercraft_" .. tostring(#actor.dwimmercraftIllusions + 1)),
            source = "dwimmercraft",
            caster = actor,
            casterId = actor and actor.id,
            mode = mode,
            image = action.image or action.illusion or action.description or
                (mode == "simple_illusion" and "handheld illusion" or "showy magical display"),
            harmless = true,
            obviouslyMagical = mode == "showy_illusion",
            fitsOneHand = mode == "simple_illusion" and true or nil,
            convincingUntilInteracted = mode == "simple_illusion" and true or nil,
            active = true,
        }
        actor.dwimmercraftIllusions[#actor.dwimmercraftIllusions + 1] = illusion
        return illusion
    end

    function resolver:activateSecondSight(actor, action)
        local previousFields = {}
        for _, key in ipairs({
            "canSeeShrouded",
            "canSeeInvisible",
            "canSeeTrueIllusions",
            "canDetectMagic",
            "canDetectEnchantments",
            "canIdentifySorcerers",
            "magicSight",
            "secondSightActive",
        }) do
            previousFields[#previousFields + 1] = {
                key = key,
                value = actor[key],
            }
        end

        local sight = {
            source = "dwimmercraft",
            actor = actor,
            actorId = actor and actor.id,
            active = true,
            duration = "watch",
            seesInvisible = true,
            seesShrouded = true,
            trueFormIllusions = true,
            detectsMagic = true,
            detectsEnchantments = true,
            identifiesSorcerers = true,
            previousFields = previousFields,
            startedAtWatch = action and (action.watchNumber or action.currentWatch),
        }

        actor.secondSight = sight
        actor.canSeeShrouded = true
        actor.canSeeInvisible = true
        actor.canSeeTrueIllusions = true
        actor.canDetectMagic = true
        actor.canDetectEnchantments = true
        actor.canIdentifySorcerers = true
        actor.magicSight = true
        actor.secondSightActive = true
        actor.conditions = actor.conditions or {}
        actor.conditions.second_sight = true
        actor.conditionDurations = actor.conditionDurations or {}
        actor.conditionDurations.second_sight = {
            duration = "watch",
            source = "dwimmercraft",
            effect = sight,
        }

        return sight
    end

    function resolver:resolveDwimmercraft(action, result)
        action = action or {}
        result = result or {
            success = false,
            effects = {},
            description = "",
        }
        result.effects = result.effects or {}

        local actor = action.actor
        if not entityHasUsableTalent(actor, "dwimmercraft") then
            result.success = false
            result.description = "Requires Dwimmercraft."
            result.effects[#result.effects + 1] = "requires_dwimmercraft"
            return result
        end

        local controller = action.challengeController or self.challengeController
        local challengeActive = action.challengeActive == true or
            (controller and controller.isActive and controller:isActive())

        local mode = self:getDwimmercraftMode(action)
        result.dwimmercraftMode = mode
        result.effects[#result.effects + 1] = "dwimmercraft"
        if challengeActive then
            result.effects[#result.effects + 1] = "dwimmercraft_misc_action"
        end

        if mode == "second_sight" then
            local spent, spendReason = self:spendResolveForFavor(actor)
            if not spent then
                result.success = false
                result.description = "Cannot focus second sight: " .. (spendReason or "resolve unavailable") .. "."
                result.effects[#result.effects + 1] = "resolve_missing"
                return result
            end

            result.success = true
            result.resolveSpent = 1
            result.secondSight = self:activateSecondSight(actor, action)
            result.effects[#result.effects + 1] = "second_sight"
            result.effects[#result.effects + 1] = "resolve_spent_for_dwimmercraft"
            result.description = (actor.name or actor.id or "The adventurer") .. " focuses second sight for a watch."
        elseif mode == "levitate" then
            local object = action.target or action.object or action.item
            local ok, reason = self:canDwimmercraftAffectObject(actor, object, action)
            if not ok then
                result.success = false
                result.description = "Dwimmercraft cannot affect that object."
                result.effects[#result.effects + 1] = reason
                return result
            end

            object.dwimmercraft = {
                source = "dwimmercraft",
                caster = actor,
                casterId = actor and actor.id,
                mode = normalizeTalentKey(action.objectMotion or action.motion or action.intent or "levitate"),
                noFineControl = true,
                maxWeightPounds = 10,
                active = true,
            }
            object.levitatedByDwimmercraft = true
            result.success = true
            result.target = object
            result.effects[#result.effects + 1] = "dwimmercraft_levitation"
            result.description = (actor.name or actor.id or "The adventurer") .. " moves a small object with minor magic."
        else
            local illusion = self:recordDwimmercraftIllusion(actor, action, mode)
            result.success = true
            result.illusion = illusion
            if mode == "simple_illusion" then
                result.effects[#result.effects + 1] = "dwimmercraft_simple_illusion"
                result.description = (actor.name or actor.id or "The adventurer") .. " conjures a small convincing illusion."
            else
                result.effects[#result.effects + 1] = "dwimmercraft_showy_illusion"
                result.description = (actor.name or actor.id or "The adventurer") .. " conjures a harmless magical display."
            end
        end

        self.eventBus:emit("dwimmercraft_resolved", result)
        return result
    end

    function resolver:inspectWithSecondSight(actor, subject)
        local sight = actor and actor.secondSight
        if not sight or sight.active == false then
            return {
                success = false,
                reason = "second_sight_inactive",
            }
        end

        local conditions = subject and subject.conditions or {}
        local props = subject and subject.properties or {}
        local illusion = subject and (subject.visualIllusion or subject.illusion or subject.emotionalIllusion)
        local isIllusion = illusion ~= nil or subject and (subject.isIllusion or conditions.illusion)
        local isSorcerer = subject and (
            subject.isSorcerer == true or subject.sorcerer == true or subject.canCastSpells == true or
            type(subject.knownSpells) == "table" or type(subject.spells) == "table" or
            getEntityTalentEntry(subject, "magic_of_the_wastes") ~= nil or
            getEntityTalentEntry(subject, "magic_of_the_weald") ~= nil or
            getEntityTalentEntry(subject, "magic_of_the_weird") ~= nil or
            getEntityTalentEntry(subject, "magic_of_the_welkin") ~= nil
        )

        return {
            success = true,
            actor = actor,
            subject = subject,
            seesInvisible = subject and (subject.invisible == true or conditions.invisible == true),
            seesShrouded = self:isEntityShrouded(subject),
            trueForm = isIllusion and (subject.trueForm or subject.illusionTrueForm or
                (illusion and (illusion.trueForm or illusion.actualForm)) or "illusion") or nil,
            isIllusion = isIllusion == true,
            magical = subject and (subject.magical == true or props.magical == true or
                subject.enchanted == true or conditions.enchanted == true or type(subject.activeSpells) == "table"),
            enchanted = subject and (subject.enchanted == true or conditions.enchanted == true),
            isSorcerer = isSorcerer == true,
        }
    end

    local function findActiveSpellIndex(actor, spellEntry)
        if not actor or type(actor.activeSpells) ~= "table" or not spellEntry then
            return nil
        end

        local spellId = normalizeSpellKey(spellEntry.spellId or spellEntry.id or spellEntry.name)
        local firstMatchingSpellId = nil
        for index, activeSpell in ipairs(actor.activeSpells) do
            if activeSpell == spellEntry then
                return index
            end
            local activeId = normalizeSpellKey(activeSpell.spellId or activeSpell.id or activeSpell.name)
            if spellId ~= "" and activeId == spellId then
                if spellEntry.target and activeSpell.target == spellEntry.target then
                    return index
                end
                firstMatchingSpellId = firstMatchingSpellId or index
            end
        end

        return firstMatchingSpellId
    end

    function resolver:getConcentrationSpell(actor)
        if not actor or type(actor.activeSpells) ~= "table" then
            return nil, nil
        end

        for index, activeSpell in ipairs(actor.activeSpells) do
            if activeSpell.concentration then
                return activeSpell, index
            end
        end

        return nil, nil
    end

    local refreshElementProtectionFlags
    local restoreTotemAttributes
    local appendDroppedItems
    local clearMaledictionState

    clearMaledictionState = function(target, malediction)
        if not target or not malediction then
            return
        end

        local conditions = target.conditions or {}
        target.conditions = conditions
        for _, entry in ipairs(malediction.previousConditions or {}) do
            conditions[entry.key] = entry.value
        end

        for _, entry in ipairs(malediction.previousFields or {}) do
            target[entry.key] = entry.value
        end

        if malediction.previousNonRecoverableConditions then
            target.nonRecoverableConditions = target.nonRecoverableConditions or {}
            for _, entry in ipairs(malediction.previousNonRecoverableConditions) do
                target.nonRecoverableConditions[entry.key] = entry.value
            end
        end

        if malediction.hadPreviousMalediction then
            target.malediction = malediction.previousMalediction
        else
            target.malediction = nil
        end
    end

    local closePortableHole
    local closeMirrorMeld

    function resolver:endOngoingSpell(actor, spellEntry, reason, opts)
        opts = opts or {}
        if not actor or not spellEntry then
            return nil
        end

        local index = findActiveSpellIndex(actor, spellEntry)
        local endedSpell = spellEntry
        if index then
            endedSpell = table.remove(actor.activeSpells, index)
        end

        local committed = endedSpell.resolveCommitted or endedSpell.resolveSpent or 0
        if committed > 0 then
            actor.committedResolve = math.max(0, (actor.committedResolve or 0) - committed)
        end

        local target = endedSpell.target
        if (endedSpell.effectType == "control" or endedSpell.spellId == "control_animal" or
           endedSpell.spellId == "control_undead") and target and target.controlledBy == actor then
            if target.conditions then
                target.conditions.controlled = false
            end
            target.controlledBy = nil
            target.controlWords = nil
            target.controlOrder = nil
            target.controlCommandsRemaining = nil
        end

        if endedSpell.spellId == "animate_object" and target and target.animatedObject and
           target.animatedObject.caster == actor then
            target.animatedObject.active = false
            target.animatedObject.ended = true
            target.animatedObject.endReason = reason or "ended"
            if target.conditions then
                target.conditions.animatedObject = false
            end
            target.animatedBy = nil
            target.animatedObject = nil
        end

        if endedSpell.spellId == "brainfever" and target and target.brainfever and target.brainfever.caster == actor then
            if target.conditions then
                target.conditions.brainfever = false
                target.conditions.enraged = false
            end
            target.brainfever = nil
            target.mustPlayLowestInitiative = false
            target.attackFavorFromBrainfever = false
        end

        if endedSpell.spellId == "necromancy" and target and target.necromancy and target.necromancy.caster == actor then
            if target.conditions then
                target.conditions.necromancy = false
                target.conditions.speaksWithDead = false
            end
            target.necromancy = nil
            target.canSpeakWhileDead = false
            target.speaksAsIfAlive = false
        end

        if endedSpell.spellId == "fleshcraft" and target and target.fleshcraft and target.fleshcraft.caster == actor then
            local fleshcraft = target.fleshcraft
            fleshcraft.active = false
            fleshcraft.ended = true
            fleshcraft.endReason = reason or "ended"
            if target.conditions then
                target.conditions.fleshcraft = false
                target.conditions.detachedBodyPart = false
            end
            if target.detachedBodyParts and target.detachedBodyParts[fleshcraft.bodyPart] == fleshcraft then
                target.detachedBodyParts[fleshcraft.bodyPart] = nil
            end
            target.fleshcraft = nil
            target.detachedBodyPart = nil
            target.detachedBodyPartKind = nil
        end

        if endedSpell.spellId == "raise_zombie" then
            local zombie = endedSpell.raisedZombie or target
            if zombie and zombie.raiseZombie and zombie.raiseZombie.caster == actor then
                local binding = zombie.raiseZombie
                binding.active = false
                binding.ended = true
                binding.endReason = reason or "ended"
                zombie.boundZombie = false
                zombie.boundTo = nil
                zombie.boundToId = nil
                zombie.controlledBy = nil
                zombie.commandsAny = false
                zombie.obeysMostCommands = false
                zombie.obeysSuicidalCommands = false
                zombie.releasedFromBinding = true
                zombie.devilClaimsBody = reason == "raise_zombie_services_completed"
                zombie.mayAttackShuffleOrCrumble = true
                if zombie.conditions then
                    zombie.conditions.controlled = false
                    zombie.conditions.boundZombie = false
                end
                removeCompanionFromActor(actor, zombie)
            end
        end

        if endedSpell.spellId == "malediction" and target and target.malediction and
           target.malediction.caster == actor then
            target.malediction.active = false
            target.malediction.ended = true
            target.malediction.endReason = reason or "ended"
            clearMaledictionState(target, target.malediction)
        end

        if endedSpell.spellId == "binding" then
            local targets = endedSpell.targets or (target and { target } or {})
            for _, boundTarget in ipairs(targets) do
                if boundTarget and boundTarget.bindingRootedBy == actor then
                    if boundTarget.conditions then
                        boundTarget.conditions.rooted = false
                        boundTarget.conditions.bindingRooted = false
                    end
                    boundTarget.bindingRootedBy = nil
                    boundTarget.bindingName = nil
                    if boundTarget.nonRecoverableConditions then
                        boundTarget.nonRecoverableConditions.rooted = nil
                    end
                end
            end
        end

        if endedSpell.spellId == "defy_depths" then
            local targets = endedSpell.targets or (target and { target } or {})
            for _, depthsTarget in ipairs(targets) do
                if depthsTarget and depthsTarget.defyDepths and depthsTarget.defyDepths.caster == actor then
                    if depthsTarget.conditions then
                        depthsTarget.conditions.defyDepths = false
                    end
                    local props = depthsTarget.properties
                    if props then
                        props.floatsOnWater = false
                        props.defyDepths = false
                    end
                    depthsTarget.defyDepths = nil
                    depthsTarget.canWalkOnWater = false
                    depthsTarget.waterWalking = false
                    depthsTarget.floatsOnWater = false
                    depthsTarget.floatingOnWater = false
                    depthsTarget.floating = false
                    depthsTarget.onWaterSurface = false
                    depthsTarget.raisedFromDepths = false
                end
            end
        end

        if endedSpell.spellId == "protection_from_elements" then
            local targets = endedSpell.targets or (target and { target } or {})
            for _, protectedTarget in ipairs(targets) do
                if protectedTarget and protectedTarget.elementProtections then
                    protectedTarget.elementProtections[endedSpell.id or endedSpell.instanceId or endedSpell] = nil
                    for key, protection in pairs(protectedTarget.elementProtections) do
                        if protection and protection.caster == actor and protection.spellEntry == endedSpell then
                            protectedTarget.elementProtections[key] = nil
                        end
                    end
                    protectedTarget.protectionFromElements = nil
                    if refreshElementProtectionFlags then
                        refreshElementProtectionFlags(protectedTarget)
                    end
                end
            end
        end

        if endedSpell.spellId == "wall_of_elements" then
            local wall = endedSpell.elementWall or target
            if wall then
                wall.active = false
                wall.ended = true
                wall.endReason = reason or "ended"
                for _, section in ipairs(wall.sections or {}) do
                    section.active = false
                    section.ended = true
                    section.endReason = wall.endReason
                end
            end

            if actor.activeElementWalls then
                for index = #actor.activeElementWalls, 1, -1 do
                    if actor.activeElementWalls[index] == wall then
                        table.remove(actor.activeElementWalls, index)
                    end
                end
            end
        end

        if endedSpell.spellId == "speak_to_animal" and target and target.speakToAnimal and
           target.speakToAnimal.caster == actor then
            if target.conditions then
                target.conditions.speakToAnimal = false
            end
            target.speakToAnimal = nil
            target.canSpeakWithAnimals = false
            target.speechGarbledBySpiderEgg = false
        end

        if endedSpell.spellId == "totem" and target and target.totemForm and
           target.totemForm.caster == actor then
            local totemForm = target.totemForm
            restoreTotemAttributes(target, totemForm.previousAttributes)
            if target.conditions then
                target.conditions.totemForm = false
            end
            target.totemForm = nil
            target.inTotemForm = false
            target.mouthOccupiedByTotem = false
            if totemForm.previousCanSpeak == nil then
                target.canSpeak = nil
            else
                target.canSpeak = totemForm.previousCanSpeak
            end
            if totemForm.component then
                totemForm.component.spatOut = true
                appendDroppedItems(target, { totemForm.component })
            end
        end

        if endedSpell.spellId == "scry" then
            local scrying = endedSpell.scrying or (actor and actor.scrying)
            if scrying then
                scrying.active = false
                scrying.ended = true
                scrying.endReason = reason or "ended"
            end
            if actor and actor.scrying == scrying then
                actor.scrying = nil
            end
        end

        if endedSpell.spellId == "give_form_to_nothingness" then
            local giveForm = endedSpell.giveForm or target
            if giveForm then
                giveForm.active = false
                giveForm.ended = true
                giveForm.endReason = reason or "ended"
                for _, record in ipairs(giveForm.affectedSubjects or {}) do
                    restoreGiveFormSubject(record)
                end
            end

            if actor.activeGiveForms then
                for index = #actor.activeGiveForms, 1, -1 do
                    if actor.activeGiveForms[index] == giveForm then
                        table.remove(actor.activeGiveForms, index)
                    end
                end
            end
        end

        if endedSpell.spellId == "portable_hole" then
            closePortableHole(actor, endedSpell.portableHole or (target and target.portableHole) or target, reason)
        end

        if endedSpell.spellId == "mirror_meld" then
            closeMirrorMeld(self, actor, endedSpell.mirrorMeld or (target and target.mirrorMeld) or target, reason, opts)
        end

        if endedSpell.spellId == "illusion" then
            local illusion = endedSpell.visualIllusion or target
            if illusion then
                illusion.active = false
                illusion.ended = true
                illusion.endReason = reason or "ended"
            end
            if actor.activeVisualIllusions then
                for index = #actor.activeVisualIllusions, 1, -1 do
                    if actor.activeVisualIllusions[index] == illusion then
                        table.remove(actor.activeVisualIllusions, index)
                    end
                end
            end
        end

        if endedSpell.spellId == "darklight" and target and target.darklight and target.darklight.caster == actor then
            local props = target.properties or {}
            target.properties = props
            local previous = target.darklight.previousProperties or {}
            local keys = {
                "isLit",
                "is_lit",
                "extinguished",
                "flicker_count",
                "darklight",
                "darklightVisibleOnly",
                "darklightHolderId",
                "darklightVisibleTo",
                "darklightViewerIds",
                "ignoreTorchesGutter",
                "darklightIgnoreTorchesGutter",
                "stealthLight",
                "providesOnlyPrivateLight",
                "light_source",
                "candle",
            }
            for _, key in ipairs(keys) do
                props[key] = previous[key]
            end
            target.darklight = nil
        end

        if endedSpell.spellId == "feather" and target and target.featherBy == actor then
            if target.conditions then
                target.conditions.feather = false
                target.conditions.floating = false
            end

            local props = target.properties
            if props then
                props.featherWeight = false
                props.floating = false
                props.easyToMove = false
                props.ignorePressurePlates = false
                props.immuneToHazardScenery = false
            end

            target.feather = nil
            target.featherBy = nil
            target.floating = false
            target.effectiveWeight = nil
            target.weightReducedToFeather = false
            target.immuneToFallingDamage = false
            target.immuneToHazardScenery = false
            target.ignorePressurePlates = false
            target.easyToMove = false
        end

        if endedSpell.spellId == "charm" and target and target.charm and target.charm.caster == actor then
            local charm = target.charm
            local relationId = charm.cloakedTargetId
            if target.conditions then
                target.conditions.charmed = false
                target.conditions.inspired = false
                target.conditions.inspiredTrust = false
            end
            if target.charmedRelations and relationId then
                target.charmedRelations[relationId] = nil
            end
            if reason ~= "disposition_changed" and target.disposition == "trust" and charm.previousDisposition then
                target.disposition = charm.previousDisposition
            end
            target.charm = nil
            target.charmedBy = nil
            target.illusionVisibleOnlyTo = nil
        end

        if (endedSpell.spellId == "fear" or endedSpell.spellId == "enrage") and target and
           target.emotionalIllusion and target.emotionalIllusion.caster == actor then
            local illusion = target.emotionalIllusion
            local relationId = illusion.cloakedTargetId
            local disposition = illusion.disposition
            if target.conditions then
                target.conditions.inspired = false
                target.conditions.inspiredFear = false
                target.conditions.inspiredAnger = false
                target.conditions.fearful = false
                target.conditions.enraged = false
            end
            if target.emotionalIllusionRelations and relationId then
                target.emotionalIllusionRelations[relationId] = nil
            end
            if reason ~= "disposition_changed" and target.disposition == disposition and illusion.previousDisposition then
                target.disposition = illusion.previousDisposition
            end
            target.emotionalIllusion = nil
            target.emotionalIllusionBy = nil
            target.illusionVisibleOnlyTo = nil
            target.mustFleeFrom = nil
            target.recklessAttackTarget = nil
        end

        if endedSpell.spellId == "shroud" and target and target.shroud and target.shroud.caster == actor then
            if target.conditions then
                target.conditions.shrouded = false
                target.conditions.invisible = false
            end
            target.shroud = nil
            target.shroudedBy = nil
        end

        if endedSpell.spellId == "change_size" and target and target.changeSize and target.changeSize.caster == actor then
            if target.conditions then
                target.conditions.sizeChanged = false
                target.conditions.sizeGrown = false
                target.conditions.sizeShrunk = false
            end
            target.changeSize = nil
            target.changedSizeBy = nil
            target.sizeMultiplier = 1
            target.heightMultiplier = 1
            target.sizeChanged = false
        end

        if endedSpell.spellId == "circle_of_protection" then
            local circle = endedSpell.circleProtection or target
            if circle then
                circle.active = false
                circle.ended = true
                circle.endReason = reason or "ended"
            end

            if actor.activeCircleProtections then
                for index = #actor.activeCircleProtections, 1, -1 do
                    if actor.activeCircleProtections[index] == circle then
                        table.remove(actor.activeCircleProtections, index)
                    end
                end
            end
        end

        if endedSpell.spellId == "stinking_cloud" then
            local cloud = endedSpell.stinkingCloud or target
            if cloud then
                cloud.active = false
                cloud.ended = true
                cloud.endReason = reason or "ended"
            end

            if actor.activeStinkingClouds then
                for index = #actor.activeStinkingClouds, 1, -1 do
                    if actor.activeStinkingClouds[index] == cloud then
                        table.remove(actor.activeStinkingClouds, index)
                    end
                end
            end
        end

        endedSpell.ended = true
        endedSpell.endReason = reason or "ended"

        self.eventBus:emit(events.EVENTS.SPELL_ENDED, {
            actor = actor,
            spell = endedSpell,
            reason = endedSpell.endReason,
            source = opts.source,
        })

        return endedSpell
    end

    function resolver:dismissMalediction(caster, target, reason)
        local malediction = target and target.malediction
        if not malediction or malediction.active == false then
            return {
                success = false,
                effects = { "malediction_missing" },
            }
        end

        if caster and malediction.caster and malediction.caster ~= caster then
            return {
                success = false,
                effects = { "malediction_wrong_caster" },
            }
        end

        local spellCaster = malediction.caster or caster
        local ended = self:endOngoingSpell(spellCaster, malediction.spellEntry or {
            spellId = "malediction",
            target = target,
        }, reason or "dismissed")

        return {
            success = ended ~= nil,
            endedSpell = ended,
            effects = { "malediction_dismissed" },
        }
    end

    function resolver:fulfillControlOrder(actor, target)
        if not actor or not target or type(actor.activeSpells) ~= "table" then
            return nil
        end

        for _, spellEntry in ipairs(actor.activeSpells) do
            if spellEntry and spellEntry.effectType == "control" and spellEntry.target == target then
                if target.controlOrder then
                    target.controlOrder.fulfilled = true
                end
                return self:endOngoingSpell(actor, spellEntry, "control_order_fulfilled")
            end
        end

        return nil
    end

    function resolver:isChallengeControlContext(action)
        action = action or {}
        if action.inChallenge == true or action.challenge == true then
            return true
        end

        local controller = action.challengeController or self.challengeController
        return controller and controller.isActive and controller:isActive()
    end

    function resolver:resolveImmediateControlAction(sourceAction, result, controller, target)
        if not self:isChallengeControlContext(sourceAction) then
            return nil
        end

        local spec = sourceAction.controlledAction or sourceAction.commandedAction or sourceAction.immediateControlAction
        if type(spec) ~= "table" then
            result.effects[#result.effects + 1] = "control_immediate_action_pending"
            return nil
        end

        local actionType = self:normalizeActionType(spec.type or spec.id or spec.actionType)
        if not actionType then
            result.effects[#result.effects + 1] = "control_immediate_action_missing"
            return nil
        end

        local controlValue = result.testValue or 0
        local controlledAction = {}
        for key, value in pairs(spec) do
            controlledAction[key] = value
        end
        controlledAction.actor = target
        controlledAction.type = actionType
        controlledAction.card = {
            name = "Controlled " .. tostring(actionType),
            value = controlValue,
            suit = (sourceAction.card and sourceAction.card.suit) or spec.suit,
        }
        controlledAction.isControlledAction = true
        controlledAction.controlledBy = controller
        controlledAction.controlSourceAction = sourceAction
        controlledAction.challengeController = sourceAction.challengeController or self.challengeController
        controlledAction.allEntities = controlledAction.allEntities or sourceAction.allEntities

        result.controlledAction = controlledAction
        result.controlledActionResult = self:resolve(controlledAction)
        result.effects[#result.effects + 1] = "control_immediate_action"

        if sourceAction.controlOrderCompletesAfterImmediate ~= false then
            result.controlEnded = self:fulfillControlOrder(controller, target)
            if result.controlEnded then
                result.effects[#result.effects + 1] = "control_order_fulfilled"
            end
        end

        return result.controlledActionResult
    end

    function resolver:endCharmForDispositionChange(target, oldDisposition, newDisposition, source, oldSeverity, newSeverity)
        local sameDisposition = oldDisposition == newDisposition
        local sameSeverity = oldSeverity == nil or newSeverity == nil or oldSeverity == newSeverity
        if not target or (sameDisposition and sameSeverity) then
            return nil
        end

        local trackedSpellId = nil
        local activeIllusion = nil
        if target.charm then
            activeIllusion = target.charm
            trackedSpellId = "charm"
        elseif target.emotionalIllusion then
            activeIllusion = target.emotionalIllusion
            trackedSpellId = activeIllusion.spellId
        end

        if not activeIllusion then
            return nil
        end

        local caster = activeIllusion.caster
        if not caster then
            if trackedSpellId == "charm" then
                target.charm = nil
                target.charmedBy = nil
            else
                target.emotionalIllusion = nil
                target.emotionalIllusionBy = nil
            end
            return nil
        end

        local activeSpell = nil
        for _, spellEntry in ipairs(caster.activeSpells or {}) do
            if spellEntry.spellId == trackedSpellId and spellEntry.target == target then
                activeSpell = spellEntry
                break
            end
        end

        if activeSpell then
            return self:endOngoingSpell(caster, activeSpell, "disposition_changed", {
                source = source,
                oldDisposition = oldDisposition,
                newDisposition = newDisposition,
            })
        end

        if trackedSpellId == "charm" then
            target.charm = nil
            target.charmedBy = nil
        else
            target.emotionalIllusion = nil
            target.emotionalIllusionBy = nil
        end
        return nil
    end

    function resolver:createCircleProtection(actor, action, spell, resolveSpent, realms, realmSet)
        action = action or {}
        spell = spell or {}

        if actor then
            actor._circleProtectionCounter = (actor._circleProtectionCounter or 0) + 1
        end

        realms = realms or {}
        realmSet = realmSet or {}
        for _, realm in ipairs(realms) do
            realmSet[realm] = true
        end

        local circle = {
            id = action.circleId or action.preparedCircleId or
                ("circle_of_protection_" .. tostring(actor and (actor.id or actor.name) or "caster") .. "_" ..
                    tostring(actor and actor._circleProtectionCounter or os.time())),
            spellId = spell.id or "circle_of_protection",
            caster = actor,
            casterId = actor and actor.id,
            roomId = action.roomId or action.room,
            zoneId = action.zoneId or action.zone or (actor and actor.zone),
            center = action.center or action.position,
            radiusFeet = math.min(tonumber(action.radiusFeet or action.radius or spell.radiusFeet) or 10, spell.radiusFeet or 10),
            realms = realms,
            realmSet = realmSet,
            resolveSpent = resolveSpent,
            prepared = true,
            trapReady = action.trapReady == true or action.trapCasting == true,
            active = true,
            concentration = true,
            createdAt = os.time(),
        }

        if actor then
            actor.activeCircleProtections = actor.activeCircleProtections or {}
            actor.activeCircleProtections[#actor.activeCircleProtections + 1] = circle
        end

        self.eventBus:emit("circle_of_protection_created", {
            actor = actor,
            circle = circle,
            realms = realms,
        })

        return circle
    end

    function resolver:findCircleProtection(circleRef, actor)
        if type(circleRef) == "table" then
            return circleRef
        end
        if not circleRef or not actor then
            return nil
        end

        local circleId = tostring(circleRef)
        for _, circle in ipairs(actor.activeCircleProtections or {}) do
            if tostring(circle.id) == circleId then
                return circle
            end
        end

        return nil
    end

    function resolver:isNativeToCircleRealm(entity, circle)
        if not entity or not circle then
            return false
        end

        local realm = normalizeFarRealm(entity.realm or entity.farRealm or entity.nativeRealm or
            entity.branch or entity.spiritRealm)
        if realm and circle.realmSet and circle.realmSet[realm] then
            return true
        end

        for protectedRealm in pairs(circle.realmSet or {}) do
            if hasTag(entity, protectedRealm) or hasTag(entity, protectedRealm .. "_spirit") or
               hasTag(entity, protectedRealm .. "_creature") then
                return true
            end
        end

        return false
    end

    function resolver:doesCircleProtectionBlock(circleRef, entity, opts)
        opts = opts or {}
        local circle = self:findCircleProtection(circleRef, opts.actor or opts.caster) or circleRef
        if type(circle) ~= "table" or circle.active == false then
            return false
        end
        if opts.acrossBoundary == false or opts.sameSide == true then
            return false
        end
        if opts.action and opts.action ~= "cross" and opts.action ~= "harm" and opts.action ~= "attack" then
            return false
        end

        return self:isNativeToCircleRealm(entity, circle)
    end

    function resolver:triggerMaleficence(actor, branch, reason, opts)
        opts = opts or {}

        local spell = opts.spell
        local spellId = opts.spellId or (spell and (spell.spellId or spell.id))
        local record = {
            actor = actor,
            branch = branch or (spell and spell.branch) or "unknown",
            reason = reason or "magic_gone_wrong",
            spell = spell,
            spellId = spellId,
            source = opts.source,
        }

        record.autoResolveRequested = opts.resolve == true

        if actor then
            actor.pendingMaleficence = record
            actor.maleficenceHistory = actor.maleficenceHistory or {}
            actor.maleficenceHistory[#actor.maleficenceHistory + 1] = record
        end

        self.eventBus:emit(events.EVENTS.MALEFICENCE_TRIGGERED, record)

        if (opts.resolve or opts.card or opts.value) and not record.resolved then
            self:resolveMaleficence(record, opts)
        end

        return record
    end

    function resolver:getMaleficenceDraw(opts)
        opts = opts or {}
        if opts.card then
            return opts.card
        end

        if opts.value then
            return {
                name = maleficence_tables.getRank(opts.value) or tostring(opts.value),
                value = opts.value,
                suit = opts.suit,
            }
        end

        local deck = opts.deck or self.playerDeck
        if deck and deck.draw then
            local card = deck:draw()
            while card and card.value == 0 do
                if deck.discard then
                    deck:discard(card)
                end
                card = deck:draw()
            end
            if card and deck.discard and opts.discardDraw ~= false then
                deck:discard(card)
            end
            return card
        end

        return nil
    end

    function resolver:getEntitiesInActorZone(actor, opts)
        opts = opts or {}
        local entities = opts.allEntities
            or (self.challengeController and self.challengeController.allCombatants)
            or {}
        local zone = actor and actor.zone
        local inZone = {}

        for _, entity in ipairs(entities) do
            if entity and (not zone or entity.zone == zone) then
                inZone[#inZone + 1] = entity
            end
        end

        return inZone
    end

    function resolver:getMaleficenceRoomEntities(actor, opts)
        opts = opts or {}
        if type(opts.roomEntities) == "table" then
            return opts.roomEntities
        end
        if type(opts.entitiesInRoom) == "table" then
            return opts.entitiesInRoom
        end

        local entities = opts.allEntities
            or (self.challengeController and self.challengeController.allCombatants)
            or {}
        local roomId = opts.roomId or opts.currentRoomId or
            (actor and (actor.location or actor.roomId or actor.currentRoomId))

        if type(entities) == "table" and #entities > 0 then
            local hasRoomMarkers = false
            for _, entity in ipairs(entities) do
                if entity and (entity.location or entity.roomId or entity.currentRoomId) then
                    hasRoomMarkers = true
                    break
                end
            end

            if roomId and hasRoomMarkers then
                local inRoom = {}
                for _, entity in ipairs(entities) do
                    local entityRoomId = entity and (entity.location or entity.roomId or entity.currentRoomId)
                    if entityRoomId == roomId then
                        inRoom[#inRoom + 1] = entity
                    end
                end
                return inRoom
            end
        end

        return self:getEntitiesInActorZone(actor, opts)
    end

    function resolver:getMaleficenceRoom(actor, opts)
        opts = opts or {}
        if type(opts.room) == "table" then
            return opts.room, opts.room.id or opts.room.roomId
        end
        if type(opts.currentRoom) == "table" then
            return opts.currentRoom, opts.currentRoom.id or opts.currentRoom.roomId
        end

        local roomId = opts.roomId or opts.currentRoomId or
            (actor and (actor.roomId or actor.currentRoomId or actor.location))
        local manager = opts.roomManager or self.roomManager
        if roomId and manager and manager.getRoom then
            return manager:getRoom(roomId), roomId
        end

        return nil, roomId
    end

    function resolver:recordMaleficenceRoomFeature(actor, effect, result, opts)
        opts = opts or {}
        local feature = createMaleficenceRoomFeature(effect)
        local room, roomId = self:getMaleficenceRoom(actor, opts)
        local manager = opts.roomManager or self.roomManager
        local added = nil

        if roomId and manager and manager.addFeature then
            added = manager:addFeature(roomId, feature)
        elseif room then
            room.features = room.features or {}
            room.features[#room.features + 1] = feature
            added = feature
        end

        added = added or feature
        result.roomFeatures = result.roomFeatures or {}
        result.roomFeatures[#result.roomFeatures + 1] = added
        if effect.type == "room_hazard" then
            result.roomHazards = result.roomHazards or {}
            result.roomHazards[#result.roomHazards + 1] = added
        end
        result.effects[#result.effects + 1] = effect.type == "room_hazard" and
            "maleficence_room_hazard" or "maleficence_room_feature"
        local token = normalizeSocialTag(effect.feature or effect.hazard or effect.tag)
        if token then
            result.effects[#result.effects + 1] = "maleficence_" .. effect.type .. "_" .. token
        end

        return true
    end

    function resolver:recordMaleficenceAreaCondition(actor, effect, result, opts)
        opts = opts or {}
        local feature = createMaleficenceAreaCondition(effect)
        local room, roomId = self:getMaleficenceRoom(actor, opts)
        local manager = opts.roomManager or self.roomManager
        local added = nil

        if roomId and manager and manager.addFeature then
            added = manager:addFeature(roomId, feature)
        elseif room then
            room.features = room.features or {}
            room.features[#room.features + 1] = feature
            added = feature
        end

        added = added or feature
        result.areaConditions = result.areaConditions or {}
        result.areaConditions[#result.areaConditions + 1] = added
        result.effects[#result.effects + 1] = "maleficence_area_condition"

        local token = normalizeSocialTag(effect.areaCondition or effect.condition or effect.tag)
        if token then
            result.effects[#result.effects + 1] = "maleficence_area_condition_" .. token
        end

        return added
    end

    function resolver:getMaleficenceInventoryOwners(actor, effect, opts)
        opts = opts or {}
        effect = effect or {}

        local owners = {}
        local seen = {}

        local function addOwner(owner)
            if owner and not seen[owner] then
                seen[owner] = true
                owners[#owners + 1] = owner
            end
        end

        local scope = effect.scope or effect.target
        if effect.owner == "actor" then
            addOwner(actor)
        elseif scope == "room" or scope == "zone" then
            for _, entity in ipairs(self:getEntitiesInActorZone(actor, opts)) do
                addOwner(entity)
            end
        elseif type(opts.guild) == "table" then
            for _, entity in ipairs(opts.guild) do
                addOwner(entity)
            end
        elseif type(opts.allEntities) == "table" then
            for _, entity in ipairs(opts.allEntities) do
                if entity == actor or entity.isPC or entity.isAdventurer or entity.type == "adventurer" then
                    addOwner(entity)
                end
            end
            if #owners == 0 then
                addOwner(actor)
            end
        else
            addOwner(actor)
        end

        return owners
    end

    function resolver:getMaleficenceAreaConditionTargets(actor, effect, opts)
        opts = opts or {}
        effect = effect or {}
        local targets = {}
        local seen = {}

        local function addTarget(entity)
            if entity and not seen[entity] then
                seen[entity] = true
                targets[#targets + 1] = entity
            end
        end

        if effect.target == "guild" or effect.target == "adventurers" or effect.target == "pcs" then
            if type(opts.guild) == "table" then
                for _, entity in ipairs(opts.guild) do
                    addTarget(entity)
                end
            elseif type(opts.allEntities) == "table" then
                for _, entity in ipairs(opts.allEntities) do
                    if entity and (entity.isPC or entity.isAdventurer or entity.type == "adventurer") then
                        addTarget(entity)
                    end
                end
            end
        elseif effect.target == "room" then
            for _, entity in ipairs(self:getMaleficenceRoomEntities(actor, opts)) do
                addTarget(entity)
            end
        end

        if #targets == 0 then
            addTarget(actor)
        end

        return targets
    end

    function resolver:applyMaleficenceCondition(target, effect, result, opts)
        if not target then
            return false
        end

        target.conditions = target.conditions or {}
        if effect.condition == "rooted" then
            self:applyRooted(target, {
                allEntities = opts and opts.allEntities,
                reason = "maleficence",
            })
        else
            target.conditions[effect.condition] = true
            if effect.condition == "burning" then
                target.conditions.onFire = true
                target.onFire = true
            end
        end
        if effect["until"] or effect.duration or effect.permanent then
            target.conditionDurations = target.conditionDurations or {}
            target.conditionDurations[effect.condition] = {
                ["until"] = effect["until"],
                duration = effect.duration,
                permanent = effect.permanent == true,
            }
        end

        result.effects[#result.effects + 1] = "maleficence_condition_" .. effect.condition
        return true
    end

    function resolver:applyMaleficenceAreaCondition(actor, effect, result, opts)
        opts = opts or {}
        local areaCondition = self:recordMaleficenceAreaCondition(actor, effect, result, opts)
        local targets = {}

        if opts.applyAreaCondition ~= false then
            for _, target in ipairs(self:getMaleficenceAreaConditionTargets(actor, effect, opts)) do
                if self:applyMaleficenceCondition(target, effect, result, opts) then
                    targets[#targets + 1] = target
                end
            end
        end

        result.areaCondition = areaCondition
        result.areaConditionTargets = targets
        if #targets > 0 then
            result.effects[#result.effects + 1] = "maleficence_area_condition_applied"
        else
            result.effects[#result.effects + 1] = "maleficence_area_condition_pending"
        end

        return true
    end

    function resolver:resolveMaleficenceRoomTest(actor, effect, result, opts)
        opts = opts or {}
        local targets = self:getMaleficenceRoomEntities(actor, opts)
        local tests = {}
        local failures = {}
        local pending = {}

        for index, entity in ipairs(targets) do
            local testResult, card, deckDiscarded =
                resolveMaleficenceRoomTestForEntity(self, entity, effect, opts, index)
            local record = {
                entity = entity,
                card = card,
                test = testResult,
                deckDiscarded = deckDiscarded == true,
            }

            if testResult then
                if not testResult.success then
                    local appliedCondition = applyMaleficenceRoomTestFailure(entity, effect, opts)
                    record.failed = true
                    record.appliedCondition = appliedCondition
                    failures[#failures + 1] = record
                end
            else
                record.pending = true
                pending[#pending + 1] = record
            end

            tests[#tests + 1] = record
        end

        result.roomTests = tests
        result.roomTestFailures = failures
        if #pending > 0 then
            result.pendingRoomTests = pending
        end

        result.effects[#result.effects + 1] = "maleficence_room_test"
        local _, attributeName = normalizeMaleficenceAttribute(effect.attribute)
        result.effects[#result.effects + 1] = "maleficence_room_test_" .. attributeName
        if #failures > 0 then
            result.effects[#result.effects + 1] = "maleficence_room_test_failed"
            local failCondition = normalizeSocialTag(effect.failCondition or effect.condition)
            if failCondition then
                result.effects[#result.effects + 1] = "maleficence_room_test_" .. failCondition
            end
        end
        if #pending > 0 then
            result.effects[#result.effects + 1] = "maleficence_room_test_pending"
        end

        return true
    end

    function resolver:spawnMaleficenceEntities(actor, effect, result, opts)
        opts = opts or {}
        local count = getMaleficenceSpawnCount(effect, opts)
        local spawned = {}
        local spawnErrors = {}
        local controller = opts.challengeController or self.challengeController

        for i = 1, count do
            local overrides = {}
            for key, value in pairs(opts.spawnOverrides or {}) do
                overrides[key] = value
            end
            overrides.location = overrides.location or (actor and (actor.location or actor.roomId or actor.currentRoomId))

            local entity, err = entity_factory.createEntity(effect.mobId, overrides)
            if entity then
                if actor then
                    actor._maleficenceSpawnCounter = (actor._maleficenceSpawnCounter or 0) + 1
                    entity.id = string.format("%s_maleficence_%s_%d",
                        tostring(effect.mobId or "spawn"),
                        tostring(actor.id or "actor"),
                        actor._maleficenceSpawnCounter)
                else
                    entity.id = string.format("%s_maleficence_%d", tostring(effect.mobId or "spawn"), i)
                end

                configureMaleficenceSpawn(entity, actor, effect, opts, i)
                spawned[#spawned + 1] = entity
            else
                spawnErrors[#spawnErrors + 1] = {
                    mobId = effect.mobId,
                    reason = err or "blueprint_not_found",
                }
            end
        end

        if controller and opts.addSpawnedToChallenge ~= false then
            controller.npcs = controller.npcs or {}
            for _, entity in ipairs(spawned) do
                controller.npcs[#controller.npcs + 1] = entity
                if controller.allCombatants then
                    controller.allCombatants[#controller.allCombatants + 1] = entity
                end
            end
        end

        result.spawnedEntities = result.spawnedEntities or {}
        result.spawnRecords = result.spawnRecords or {}
        for _, entity in ipairs(spawned) do
            result.spawnedEntities[#result.spawnedEntities + 1] = entity
            result.spawnRecords[#result.spawnRecords + 1] = {
                entity = entity,
                mobId = effect.mobId,
                hostile = entity.hostile == true,
            }
        end
        if #spawnErrors > 0 then
            result.spawnErrors = spawnErrors
        end

        if actor then
            actor.maleficenceSpawns = actor.maleficenceSpawns or {}
            for _, entity in ipairs(spawned) do
                actor.maleficenceSpawns[#actor.maleficenceSpawns + 1] = entity
            end
        end

        result.effects[#result.effects + 1] = "maleficence_spawn"
        if effect.mobId then
            result.effects[#result.effects + 1] = "maleficence_spawn_" .. tostring(effect.mobId)
        end
        if #spawned == 0 and count > 0 then
            result.effects[#result.effects + 1] = "maleficence_spawn_failed"
            result.unappliedEffects = result.unappliedEffects or {}
            result.unappliedEffects[#result.unappliedEffects + 1] = effect
            return false
        end

        return true
    end

    function resolver:scheduleMaleficenceForcedEncounter(actor, effect, result, opts)
        opts = opts or {}
        effect = effect or {}
        local manager = opts.watchManager or self.watchManager
        local entry = opts.entry or result.entry
        local encounter = {
            category = "random_encounter",
            source = "maleficence",
            filter = effect.filter or effect.tag or effect.target,
            description = effect.description or (entry and entry.summary) or
                "The next watch is automatically a random encounter.",
            actorId = actor and actor.id,
            actorName = actor and actor.name,
            branch = opts.branch or result.branch,
            rank = result.rank,
            entryTitle = entry and entry.title,
            maleficence = true,
        }

        local scheduled = nil
        if manager and manager.scheduleForcedEncounter then
            scheduled = manager:scheduleForcedEncounter(encounter)
        elseif actor then
            actor.forcedEncounters = actor.forcedEncounters or {}
            encounter.scheduledAtWatch = nil
            encounter.nextWatch = "next"
            actor.forcedEncounters[#actor.forcedEncounters + 1] = encounter
            scheduled = encounter
        else
            scheduled = encounter
        end

        result.forcedEncounter = scheduled
        result.effects[#result.effects + 1] = "maleficence_force_encounter"

        local token = normalizeSocialTag(encounter.filter)
        if token then
            result.effects[#result.effects + 1] = "maleficence_force_encounter_" .. token
        end

        return true
    end

    function resolver:createMaleficenceProcedureRecord(actor, effect, result, opts, recordType)
        opts = opts or {}
        effect = effect or {}
        local entry = opts.entry or result.entry or {}
        local record = {}

        for key, value in pairs(effect) do
            if key ~= "type" then
                record[key] = value
            end
        end

        record.type = recordType or effect.type
        record.source = "maleficence"
        record.active = record.active ~= false
        record.actorId = actor and actor.id
        record.actorName = actor and actor.name
        record.branch = opts.branch or result.branch
        record.rank = result.rank
        record.entryTitle = entry.title
        record.summary = record.summary or entry.summary
        record.watchNumber = opts.watchNumber or
            ((opts.watchManager or self.watchManager) and (opts.watchManager or self.watchManager).watchCount)

        return record
    end

    function resolver:recordWorldStateList(listName, record, actor, actorListName)
        local worldState = self.worldState
        if worldState then
            worldState[listName] = worldState[listName] or {}
            worldState[listName][#worldState[listName] + 1] = record
        end

        if actor and actorListName then
            actor[actorListName] = actor[actorListName] or {}
            actor[actorListName][#actor[actorListName] + 1] = record
        end
    end

    function resolver:recordMaleficenceEnvironmentShift(actor, effect, result, opts)
        opts = opts or {}
        local manager = opts.environmentManager or self.environmentManager
        local record = self:createMaleficenceProcedureRecord(actor, effect, result, opts, "environment_shift")
        local persisted = nil

        if manager and manager.recordEnvironmentShift then
            persisted = manager:recordEnvironmentShift(record)
        else
            self:recordWorldStateList("environmentShifts", record, actor, "maleficenceEnvironmentShifts")
            persisted = record
        end

        result.environmentShifts = result.environmentShifts or {}
        result.environmentShifts[#result.environmentShifts + 1] = persisted or record
        result.effects[#result.effects + 1] = "maleficence_environment_shift"

        local token = normalizeSocialTag(effect.scope or effect.tag)
        if token then
            result.effects[#result.effects + 1] = "maleficence_environment_shift_" .. token
        end

        return true
    end

    function resolver:recordMaleficenceWorldConsequence(actor, effect, result, opts)
        opts = opts or {}
        local record = self:createMaleficenceProcedureRecord(actor, effect, result, opts, "world_consequence")
        self:recordWorldStateList("worldConsequences", record, actor, "maleficenceWorldConsequences")

        result.worldConsequences = result.worldConsequences or {}
        result.worldConsequences[#result.worldConsequences + 1] = record
        result.effects[#result.effects + 1] = "maleficence_world_consequence"

        local token = normalizeSocialTag(effect.scope or effect.tag)
        if token then
            result.effects[#result.effects + 1] = "maleficence_world_consequence_" .. token
        end

        return true
    end

    function resolver:recordMaleficenceDelayedConsequence(actor, effect, result, opts)
        opts = opts or {}
        local record = self:createMaleficenceProcedureRecord(actor, effect, result, opts, "delayed_consequence")
        self:recordWorldStateList("delayedConsequences", record, actor, "delayedMaleficenceConsequences")

        result.delayedConsequences = result.delayedConsequences or {}
        result.delayedConsequences[#result.delayedConsequences + 1] = record
        result.effects[#result.effects + 1] = "maleficence_delayed_consequence"

        local token = normalizeSocialTag(effect.timing or effect.tag)
        if token then
            result.effects[#result.effects + 1] = "maleficence_delayed_" .. token
        end

        return true
    end

    function resolver:recordMaleficenceGMHook(actor, effect, result, opts)
        opts = opts or {}
        local record = self:createMaleficenceProcedureRecord(actor, effect, result, opts, "gm_adjudication")
        self:recordWorldStateList("gmAdjudicationHooks", record, actor, "pendingGMAdjudications")

        if effect.tag == "adjacent_inventory_ruin" then
            self:ruinAdjacentPotionInventory(actor, result, opts)
        end

        result.gmAdjudicationHooks = result.gmAdjudicationHooks or {}
        result.gmAdjudicationHooks[#result.gmAdjudicationHooks + 1] = record
        result.effects[#result.effects + 1] = "maleficence_gm_adjudication"

        local token = normalizeSocialTag(effect.tag or effect.scope)
        if token then
            result.effects[#result.effects + 1] = "maleficence_gm_" .. token
        end

        return true
    end

    function resolver:ruinAdjacentPotionInventory(actor, result, opts)
        opts = opts or {}
        local ruined = {}
        local seen = {}

        local function findItemIndex(items, target)
            for index, item in ipairs(items or {}) do
                if item == target then
                    return index
                end
            end
            return nil
        end

        for _, record in ipairs(result.destroyedItemRecords or {}) do
            local owner = record.owner or actor
            local inv = owner and owner.inventory
            local location = record.location
            local items = inv and inv[location]
            local potionIndex = record.index or findItemIndex(items, record.item)

            if items and potionIndex and itemHasMaleficenceTag(record.item, "potion") then
                for _, adjacentIndex in ipairs({ potionIndex - 1, potionIndex + 1 }) do
                    local item = items[adjacentIndex]
                    if item and item ~= record.item and not seen[item] then
                        seen[item] = true
                        item.ruined = true
                        item.destroyed = true
                        item.ruinedByMaleficence = true
                        item.ruinedByPotionDetonation = true
                        ruined[#ruined + 1] = {
                            owner = owner,
                            item = item,
                            location = location,
                            index = adjacentIndex,
                            sourceItem = record.item,
                        }
                    end
                end
            end
        end

        result.ruinedAdjacentItems = result.ruinedAdjacentItems or {}
        for _, record in ipairs(ruined) do
            result.ruinedAdjacentItems[#result.ruinedAdjacentItems + 1] = record
        end

        if #ruined > 0 then
            result.effects[#result.effects + 1] = "maleficence_adjacent_inventory_ruined"
        end

        return ruined
    end

    function resolver:recordMaleficenceOmen(actor, effect, result, opts)
        opts = opts or {}
        local record = self:createMaleficenceProcedureRecord(actor, effect, result, opts, "omen")
        if actor then
            actor.maleficenceOmens = actor.maleficenceOmens or {}
            actor.maleficenceOmens[#actor.maleficenceOmens + 1] = record
        end

        result.omens = result.omens or {}
        result.omens[#result.omens + 1] = record
        result.effects[#result.effects + 1] = "maleficence_omen"

        local token = normalizeSocialTag(effect.tag or record.entryTitle)
        if token then
            result.effects[#result.effects + 1] = "maleficence_omen_" .. token
        end

        return true
    end

    function resolver:getMaleficenceTrapTarget(actor, opts)
        opts = opts or {}
        if opts.nearestTrapTarget then
            return opts.nearestTrapTarget
        end
        if opts.nearestTarget then
            return opts.nearestTarget
        end

        local roomEntities = self:getMaleficenceRoomEntities(actor, opts)
        if #roomEntities > 0 then
            return roomEntities[1]
        end

        return actor
    end

    function resolver:destroyMaleficenceRoomWoodFeatures(actor, effect, result, opts)
        opts = opts or {}
        if normalizeSocialTag(effect.material) ~= "wood" then
            return {}
        end
        if effect.scope ~= "room" and effect.target ~= "room" then
            return {}
        end

        local room, roomId = self:getMaleficenceRoom(actor, opts)
        if not room then
            return {}
        end

        local manager = opts.roomManager or self.roomManager
        local destroyedFeatures = {}
        local trapRecords = {}

        for _, feature in ipairs(room.features or {}) do
            if featureMatchesMaleficenceMaterial(feature, "wood") and feature.state ~= "destroyed" then
                if manager and manager.updateFeatureState and roomId and feature.id then
                    manager:updateFeatureState(roomId, feature.id, {
                        state = "destroyed",
                        destroyed = true,
                        destroyedByMaleficence = true,
                    })
                else
                    feature.state = "destroyed"
                    feature.destroyed = true
                    feature.destroyedByMaleficence = true
                end

                destroyedFeatures[#destroyedFeatures + 1] = feature

                local trap = feature.trap
                if trap and not trap.disarmed and not trap.triggered then
                    trap.triggered = true
                    trap.triggeredByMaleficence = true
                    local target = self:getMaleficenceTrapTarget(actor, opts)
                    local trapRecord = {
                        feature = feature,
                        trap = trap,
                        target = target,
                        roomId = roomId,
                    }
                    trapRecords[#trapRecords + 1] = trapRecord

                    if target and target.takeWound and (trap.damage or 0) > 0 then
                        self:applyDamage(target, trap.damage, trap.effects or {}, nil, opts.allEntities, opts.woundOptions, {
                            source = "trap",
                            useAegis = opts.useAegis,
                        })
                        trapRecord.damageApplied = trap.damage
                    end

                    self.eventBus:emit(events.EVENTS.TRAP_TRIGGERED, {
                        roomId = roomId,
                        poiId = feature.id,
                        trap = trap,
                        adventurer = target and target.id,
                        source = "maleficence",
                        feature = feature,
                    })
                end
            end
        end

        if #destroyedFeatures > 0 then
            result.destroyedRoomFeatures = result.destroyedRoomFeatures or {}
            for _, feature in ipairs(destroyedFeatures) do
                result.destroyedRoomFeatures[#result.destroyedRoomFeatures + 1] = feature
            end
            result.effects[#result.effects + 1] = "maleficence_room_wood_destroyed"
        end

        if #trapRecords > 0 then
            result.triggeredWoodTraps = result.triggeredWoodTraps or {}
            for _, trapRecord in ipairs(trapRecords) do
                result.triggeredWoodTraps[#result.triggeredWoodTraps + 1] = trapRecord
            end
            result.effects[#result.effects + 1] = "maleficence_wood_traps_triggered"
        end

        return destroyedFeatures
    end

    function resolver:applyMaleficenceEffect(actor, effect, result, opts)
        opts = opts or {}

        if effect.type == "condition" then
            return self:applyMaleficenceCondition(actor, effect, result, opts)
        elseif effect.type == "damage" then
            if actor and actor.takeWound then
                self:applyDamage(actor, effect.amount or 1, effect.effects or {}, nil, opts.allEntities)
                result.effects[#result.effects + 1] = "maleficence_damage"
                return true
            end
        elseif effect.type == "zone_condition" and effect.condition == "inspired_random_disposition" then
            local disposition, severity, label, source = getMaleficenceInspiredDisposition(effect, opts)
            local inspired = {}
            for _, entity in ipairs(self:getEntitiesInActorZone(actor, opts)) do
                local record = applyMaleficenceInspiredDisposition(entity, disposition, severity, label)
                if record then
                    inspired[#inspired + 1] = record
                end
            end
            result.inspiredDispositions = inspired
            result.randomInspiredDisposition = {
                disposition = disposition,
                severity = severity,
                label = label,
                source = source,
            }
            result.effects[#result.effects + 1] = "maleficence_zone_inspired_random_disposition"
            result.effects[#result.effects + 1] = "maleficence_inspired_" .. disposition
            return true
        elseif effect.type == "zone_condition" then
            for _, entity in ipairs(self:getEntitiesInActorZone(actor, opts)) do
                self:applyMaleficenceCondition(entity, effect, result, opts)
            end
            result.effects[#result.effects + 1] = "maleficence_zone_" .. effect.condition
            return true
        elseif effect.type == "room_feature" or effect.type == "room_hazard" then
            return self:recordMaleficenceRoomFeature(actor, effect, result, opts)
        elseif effect.type == "body_change" then
            return recordMaleficenceBodyChange(actor, effect, result, opts)
        elseif effect.type == "area_condition" then
            return self:applyMaleficenceAreaCondition(actor, effect, result, opts)
        elseif effect.type == "room_test" then
            return self:resolveMaleficenceRoomTest(actor, effect, result, opts)
        elseif effect.type == "spawn" then
            return self:spawnMaleficenceEntities(actor, effect, result, opts)
        elseif effect.type == "force_encounter" then
            return self:scheduleMaleficenceForcedEncounter(actor, effect, result, opts)
        elseif effect.type == "environment_shift" then
            return self:recordMaleficenceEnvironmentShift(actor, effect, result, opts)
        elseif effect.type == "world_consequence" then
            return self:recordMaleficenceWorldConsequence(actor, effect, result, opts)
        elseif effect.type == "delayed_consequence" then
            return self:recordMaleficenceDelayedConsequence(actor, effect, result, opts)
        elseif effect.type == "gm_adjudicate" then
            return self:recordMaleficenceGMHook(actor, effect, result, opts)
        elseif effect.type == "omen" then
            return self:recordMaleficenceOmen(actor, effect, result, opts)
        elseif effect.type == "room_metal_wound" then
            local targets = {}
            for _, entity in ipairs(self:getEntitiesInActorZone(actor, opts)) do
                if entity and entity.takeWound and entityCarriesMaleficenceMaterial(entity, "metal") then
                    targets[#targets + 1] = entity
                    self:applyDamage(entity, effect.amount or 1, effect.effects or {}, nil, opts.allEntities)
                end
            end

            result.metalWoundTargets = targets
            if #targets > 0 then
                result.effects[#result.effects + 1] = "maleficence_room_metal_wound"
            end
            return true
        elseif effect.type == "notch_items" then
            local notched = {}
            local amount = effect.amount or 1
            for _, owner in ipairs(self:getMaleficenceInventoryOwners(actor, effect, opts)) do
                if owner.inventory and owner.inventory.getAllItems then
                    for _, inventoryEntry in ipairs(owner.inventory:getAllItems()) do
                        local item = inventoryEntry.item
                        if itemMatchesMaleficenceEffect(item, effect) then
                            local before = item.notches or 0
                            local statuses = {}
                            for _ = 1, amount do
                                local status = inventory.addNotch(item)
                                statuses[#statuses + 1] = status
                                if status == "already_destroyed" then
                                    break
                                end
                            end
                            notched[#notched + 1] = {
                                owner = owner,
                                item = item,
                                location = inventoryEntry.location,
                                amount = (item.notches or before) - before,
                                destroyed = item.destroyed == true,
                                statuses = statuses,
                            }
                        end
                    end
                end
            end

            result.notchedItems = notched
            if #notched > 0 then
                result.effects[#result.effects + 1] = "maleficence_items_notched"
            end
            return true
        elseif effect.type == "destroy_items" then
            local destroyed = {}
            local destroyedRecords = {}
            for _, owner in ipairs(self:getMaleficenceInventoryOwners(actor, effect, opts)) do
                if owner.inventory and owner.inventory.getAllItems then
                    for _, inventoryEntry in ipairs(owner.inventory:getAllItems()) do
                        local item = inventoryEntry.item
                        if itemMatchesMaleficenceEffect(item, effect) then
                            item.destroyed = true
                            destroyed[#destroyed + 1] = item
                            destroyedRecords[#destroyedRecords + 1] = {
                                owner = owner,
                                item = item,
                                location = inventoryEntry.location,
                                index = inventoryEntry.index,
                            }
                        end
                    end
                end
            end

            result.destroyedItems = destroyed
            result.destroyedItemRecords = destroyedRecords
            if #destroyed > 0 then
                result.effects[#result.effects + 1] = "maleficence_items_destroyed"
            end
            self:destroyMaleficenceRoomWoodFeatures(actor, effect, result, opts)
            return true
        elseif effect.type == "transform_items" then
            local transformed = {}
            for _, owner in ipairs(self:getMaleficenceInventoryOwners(actor, effect, opts)) do
                if owner.inventory and owner.inventory.getAllItems then
                    for _, inventoryEntry in ipairs(owner.inventory:getAllItems()) do
                        local item = inventoryEntry.item
                        if itemMatchesMaleficenceEffect(item, effect) then
                            local before = transformMaleficenceItem(item, effect)
                            transformed[#transformed + 1] = {
                                owner = owner,
                                item = item,
                                location = inventoryEntry.location,
                                from = effect.from,
                                to = effect.to,
                                before = before,
                            }
                        end
                    end
                end
            end

            result.transformedItems = transformed
            if #transformed > 0 then
                result.effects[#result.effects + 1] = "maleficence_items_transformed"
                if effect.from and effect.to then
                    result.effects[#result.effects + 1] = "maleficence_transform_" ..
                        tostring(effect.from) .. "_to_" .. tostring(effect.to)
                end
            end
            return true
        elseif effect.type == "healing_block" then
            local block = {
                ["until"] = effect["until"],
                woundTypes = effect.woundTypes,
                source = "maleficence",
                active = true,
            }
            if actor then
                actor.healingBlocks = actor.healingBlocks or {}
                actor.healingBlocks[#actor.healingBlocks + 1] = block
                actor.healingBlock = block
            end
            result.healingBlock = block
            result.effects[#result.effects + 1] = "maleficence_healing_block"
            return true
        end

        result.unappliedEffects = result.unappliedEffects or {}
        result.unappliedEffects[#result.unappliedEffects + 1] = effect
        return false
    end

    function resolver:resolveMaleficence(record, opts)
        opts = opts or {}
        record = record or {}

        local actor = opts.actor or record.actor
        local branch = opts.branch or record.branch
        local card = self:getMaleficenceDraw(opts)
        if not card or not card.value or card.value < 1 or card.value > 14 then
            return {
                success = false,
                reason = "maleficence_draw_missing",
                actor = actor,
                branch = branch,
                record = record,
            }
        end

        local entry = maleficence_tables.getEntry(branch, card.value)
        if not entry then
            return {
                success = false,
                reason = "maleficence_entry_missing",
                actor = actor,
                branch = branch,
                card = card,
                record = record,
            }
        end

        local result = {
            success = true,
            actor = actor,
            branch = branch,
            card = card,
            rank = entry.rank,
            entry = entry,
            record = record,
            effects = {},
            description = entry.title .. ": " .. entry.summary,
        }

        opts.entry = entry
        opts.branch = branch
        for _, effect in ipairs(entry.effects or {}) do
            self:applyMaleficenceEffect(actor, effect, result, opts)
        end

        record.resolved = true
        record.resolution = result

        if actor and actor.pendingMaleficence == record then
            actor.pendingMaleficence = nil
            actor.lastMaleficence = result
        end

        self.eventBus:emit(events.EVENTS.MALEFICENCE_RESOLVED, result)
        return result
    end

    function resolver:resolvePendingMaleficence(actor, opts)
        opts = opts or {}
        local record = opts.record or (actor and actor.pendingMaleficence)
        if not record then
            return {
                success = false,
                reason = "no_pending_maleficence",
                actor = actor,
            }
        end

        opts.actor = opts.actor or actor or record.actor
        return self:resolveMaleficence(record, opts)
    end

    function resolver:requestConcentrationTest(actor, spellEntry, reason, opts)
        opts = opts or {}
        if not actor or not spellEntry then
            return nil
        end

        local pending = {
            actor = actor,
            spell = spellEntry,
            spellId = spellEntry.spellId or spellEntry.id,
            branch = spellEntry.branch,
            attribute = "wands",
            actionType = M.ACTION_TYPES.TEST_FATE,
            reason = reason or "concentration_test_required",
            woundResult = opts.woundResult,
            damageType = opts.damageType,
            source = opts.source,
        }

        actor.pendingConcentrationTest = pending
        self.eventBus:emit(events.EVENTS.CONCENTRATION_TEST_REQUIRED, pending)
        return pending
    end

    function resolver:resolveConcentrationTestOutcome(actor, success, opts)
        opts = opts or {}
        local pending = actor and actor.pendingConcentrationTest
        if not pending then
            return {
                success = false,
                reason = "no_pending_concentration_test",
            }
        end

        actor.pendingConcentrationTest = nil

        local result = {
            success = success == true,
            actor = actor,
            spell = pending.spell,
            reason = pending.reason,
        }

        if result.success then
            result.description = "Concentration maintained."
        else
            result.description = "Concentration broken; maleficence occurs."
            result.endedSpell = self:endOngoingSpell(actor, pending.spell, "concentration_failed", {
                source = opts.source or pending,
            })
            result.maleficence = self:triggerMaleficence(actor, pending.branch, "concentration_failed", {
                spell = result.endedSpell or pending.spell,
                source = opts.source or pending,
            })
        end

        self.eventBus:emit(events.EVENTS.CONCENTRATION_TEST_RESOLVED, result)
        return result
    end

    function resolver:handleConcentrationHurt(entity, woundResult, damageType)
        if not entity then
            return nil
        end

        local materiallyHurt = woundResult ~= nil
            and woundResult ~= "armor_notched"
            and woundResult ~= "defense_reduced"
        if not materiallyHurt then
            return nil
        end

        local activeSpell = self:getConcentrationSpell(entity)
        if not activeSpell then
            return nil
        end

        if entity.pendingConcentrationTest and entity.pendingConcentrationTest.spellId == activeSpell.spellId then
            return entity.pendingConcentrationTest
        end

        return self:requestConcentrationTest(entity, activeSpell, "hurt_while_concentrating", {
            woundResult = woundResult,
            damageType = damageType,
        })
    end

    function resolver:isSpellContestRequired(action, spell, target)
        if action and action.unwilling ~= nil then
            return action.unwilling
        end
        if not target then
            return false
        end

        local targetMode = spell and spell.targetMode
        if targetMode == "environment" or targetMode == "ally" or targetMode == "willing_parties" or
           targetMode == "dead_person" or targetMode == "dead_body" then
            return false
        end
        if target.isItem or target.itemType or target.properties then
            if self:isCarriedOrWornSpellTarget(action, target) then
                return true
            end
            return false
        end
        if action.actor and target.isPC ~= nil and action.actor.isPC ~= nil then
            return action.actor.isPC ~= target.isPC
        end

        return targetMode == "unwilling_creature" or targetMode == "unwilling_creature_or_object"
    end

    function resolver:getSpellPossessionHolder(action, target)
        if not action or not target then
            return nil
        end

        local function matches(entity, ref)
            if not entity or ref == nil then
                return false
            end
            if type(ref) == "table" then
                return entity == ref
            end
            return entity.id == ref or entity.name == ref
        end

        local directHolder = action.possessionHolder or action.targetOwner or action.itemOwner or
            action.owner or target.owner or target.carriedBy or target.wornBy or target.heldBy or
            target.equippedBy
        if type(directHolder) == "table" then
            return directHolder
        end

        local candidateGroups = {
            { action.actor },
            action.allEntities,
            action.entities,
            action.combatants,
            action.pcs,
            action.npcs,
            action.targets,
        }
        for _, group in ipairs(candidateGroups) do
            for _, entity in ipairs(group or {}) do
                if matches(entity, directHolder) then
                    return entity
                end
            end
        end

        for _, group in ipairs(candidateGroups) do
            for _, entity in ipairs(group or {}) do
                if entity and (entity.weapon == target or entity.shield == target or entity.armor == target) then
                    return entity
                end

                local inv = entity and entity.inventory
                if inv and target.id and inv.findItem then
                    local found = inv:findItem(target.id)
                    if found == target then
                        return entity
                    end
                end
                if inv then
                    for _, location in ipairs({ inventory.LOCATIONS.HANDS, inventory.LOCATIONS.BELT, inventory.LOCATIONS.PACK }) do
                        for _, item in ipairs(inv[location] or {}) do
                            if item == target then
                                return entity
                            end
                        end
                    end
                end
            end
        end

        return nil
    end

    function resolver:isCarriedOrWornSpellTarget(action, target)
        if not target or not (target.isItem or target.itemType or target.properties) then
            return false
        end

        local holder = self:getSpellPossessionHolder(action, target)
        if holder then
            return holder ~= (action and action.actor)
        end

        return target.carried == true or target.worn == true or target.held == true or target.equipped == true or
            (target.properties and (target.properties.carried == true or target.properties.worn == true or
                target.properties.held == true or target.properties.equipped == true))
    end

    function resolver:getSpellContestTarget(action, target)
        return self:getSpellPossessionHolder(action, target) or target
    end

    local function findTargetAffliction(target, afflictionName)
        if not target or not target.afflictions then
            return nil, nil
        end

        if afflictionName then
            return target.afflictions[afflictionName], afflictionName
        end

        for name, affliction in pairs(target.afflictions) do
            return affliction, name
        end

        return nil, nil
    end

    local function collectSpellTargets(action, target, maxTargets)
        local targets = {}
        if type(action.targets) == "table" and #action.targets > 0 then
            for index, spellTarget in ipairs(action.targets) do
                if index > maxTargets then
                    break
                end
                targets[#targets + 1] = spellTarget
            end
        elseif target then
            targets[#targets + 1] = target
        end
        return targets
    end

    local PROTECTION_ELEMENT_ALIASES = {
        fire = "fire",
        heat = "fire",
        flame = "fire",
        flames = "fire",
        water = "water",
        cold = "water",
        ice = "water",
        icy = "water",
        air = "air",
        breath = "air",
        breathing = "air",
        suffocation = "air",
        earth = "earth",
        falling = "earth",
        fall = "earth",
    }

    local function normalizeProtectionElement(value)
        local normalized = normalizeSpellKey(value)
        return PROTECTION_ELEMENT_ALIASES[normalized]
    end

    local function addProtectionElement(elements, elementSet, value)
        local element = normalizeProtectionElement(value)
        if element and not elementSet[element] then
            elementSet[element] = true
            elements[#elements + 1] = element
        end
    end

    local function collectProtectionElements(action)
        action = action or {}
        local elements = {}
        local elementSet = {}

        if type(action.elements) == "table" then
            for _, element in ipairs(action.elements) do
                addProtectionElement(elements, elementSet, element)
            end
            for key, value in pairs(action.elements) do
                if type(key) ~= "number" and value then
                    addProtectionElement(elements, elementSet, key)
                end
            end
        end

        addProtectionElement(elements, elementSet, action.element or action.protectionElement or action.selectedElement)
        return elements, elementSet
    end

    local function collectProtectionTargets(action, target)
        local targets = {}
        if type(action.targets) == "table" and #action.targets > 0 then
            for _, spellTarget in ipairs(action.targets) do
                if spellTarget then
                    targets[#targets + 1] = spellTarget
                end
            end
        elseif target then
            targets[#targets + 1] = target
        end
        return targets
    end

    refreshElementProtectionFlags = function(target)
        if not target then
            return
        end

        local active = {
            fire = false,
            water = false,
            air = false,
            earth = false,
        }
        local any = false

        for _, protection in pairs(target.elementProtections or {}) do
            if protection and protection.active ~= false then
                any = true
                for element in pairs(protection.elementSet or {}) do
                    active[element] = true
                end
            end
        end

        target.conditions = target.conditions or {}
        target.conditions.protectionFromElements = any
        target.protectedElements = any and active or nil
        target.immuneToFire = active.fire
        target.immuneToHeat = active.fire
        target.gearImmuneToFire = active.fire
        target.immuneToCold = active.water
        target.immuneToIce = active.water
        target.gearImmuneToCold = active.water
        target.noNeedToBreathe = active.air
        target.immuneToSuffocation = active.air
        target.conditions.noNeedToBreathe = active.air
        target.conditions.immuneToSuffocation = active.air
        target.immuneToFallingDamage = active.earth or (target.feather and target.feather.preventsFallingDamage) or false
        target.gearImmuneToFalling = active.earth
    end

    local function validateProtectionFromElements(action, spell, resolveSpent, target)
        local targets = collectProtectionTargets(action, target)
        local elements = collectProtectionElements(action)
        local targetCount = #targets
        local elementCount = #elements

        if targetCount < 1 then
            return false, "Protection from the Elements needs at least one target.", "spell_target_missing"
        end
        if elementCount < 1 then
            return false, "Protection from the Elements needs at least one chosen element.", "protection_element_missing"
        end

        local requiredResolve = 1
        requiredResolve = requiredResolve + math.max(0, targetCount - (spell and spell.baseTargets or 1)) *
            (spell and spell.extraTargetResolve or 1)
        requiredResolve = requiredResolve + math.max(0, elementCount - (spell and spell.baseElements or 1)) *
            (spell and spell.extraElementResolve or 1)

        if resolveSpent < requiredResolve then
            return false, "Protection from the Elements needs more Resolve for those targets and elements.",
                "protection_too_many_targets_or_elements"
        end

        return true, nil, nil, targets, elements
    end

    function resolver:doesElementProtectionBlock(target, element)
        local protectedElement = normalizeProtectionElement(element)
        if not target or not protectedElement then
            return false
        end

        for _, protection in pairs(target.elementProtections or {}) do
            if protection and protection.active ~= false and protection.elementSet and protection.elementSet[protectedElement] then
                return true
            end
        end

        local protectedElements = target.protectedElements
        return protectedElements and protectedElements[protectedElement] == true
    end

    local WALL_ELEMENT_ALIASES = {
        earth = "earth",
        stone = "earth",
        rock = "earth",
        wind = "wind",
        winds = "wind",
        air = "wind",
        gale = "wind",
        fire = "fire",
        flame = "fire",
        flames = "fire",
        water = "water",
        wave = "water",
        waves = "water",
    }

    local function normalizeWallElement(value)
        local normalized = normalizeSpellKey(value)
        return WALL_ELEMENT_ALIASES[normalized]
    end

    local function collectWallElements(action, resolveSpent)
        action = action or {}
        resolveSpent = math.max(1, tonumber(resolveSpent) or 1)
        local choices = {}
        local invalidValue = nil

        local function addChoice(value)
            if value == nil or value == false then
                return
            end
            if type(value) == "table" then
                value = value.element or value.wallElement or value.type or value.material
            end

            local element = normalizeWallElement(value)
            if element then
                choices[#choices + 1] = element
            else
                invalidValue = invalidValue or value
            end
        end

        local source = action.wallElements or action.wallSections or action.sections or action.elements
        if type(source) == "table" then
            for _, value in ipairs(source) do
                addChoice(value)
            end
            for key, value in pairs(source) do
                if type(key) ~= "number" and value then
                    addChoice(key)
                end
            end
        elseif source ~= nil then
            addChoice(source)
        end

        if #choices == 0 then
            addChoice(action.wallElement or action.element or action.wallMaterial or action.material)
        end

        if invalidValue ~= nil then
            return nil, "invalid", invalidValue
        end
        if #choices == 0 then
            return nil, "missing"
        end
        if #choices > resolveSpent then
            return nil, "too_many"
        end
        if #choices > 1 and #choices < resolveSpent then
            return nil, "missing"
        end

        local elements = {}
        if #choices == 1 then
            for index = 1, resolveSpent do
                elements[index] = choices[1]
            end
        else
            for index, element in ipairs(choices) do
                elements[index] = element
            end
        end

        return elements, nil
    end

    local function hasWaterWallContext(action)
        action = action or {}
        if action.inWater == true or action.bodyOfWater == true or action.zoneHasWater == true or
           action.water == true or action.isBodyOfWater == true or action.navigableWater == true or
           (action.waterBody ~= nil and action.waterBody ~= false) then
            return true
        end

        local zone = action.zone or action.targetZone or action.zoneInfo or action.location
        if type(zone) == "table" then
            local props = zone.properties or {}
            return zone.water == true or zone.bodyOfWater == true or zone.isBodyOfWater == true or
                zone.navigableWater == true or props.water == true or props.bodyOfWater == true or
                props.isBodyOfWater == true or props.navigableWater == true
        end

        return false
    end

    local function wallIncludesWater(elements)
        for _, element in ipairs(elements or {}) do
            if element == "water" then
                return true
            end
        end
        return false
    end

    local function getWallZoneId(action, actor)
        action = action or {}
        local zoneRef = action.zoneId or action.zone or action.targetZone or action.targetZoneId or
            (actor and (actor.zone or actor.zoneId))
        if type(zoneRef) == "table" then
            return zoneRef.id or zoneRef.name
        end
        return zoneRef
    end

    local function validateWallOfElements(action, resolveSpent)
        local elements, reason = collectWallElements(action, resolveSpent)
        if not elements then
            if reason == "invalid" then
                return false, "Wall of Elements needs earth, wind, fire, or water sections.", "wall_element_invalid"
            elseif reason == "too_many" then
                return false, "Wall of Elements needs one Resolve for each wall section.",
                    "wall_elements_too_many_sections"
            end
            return false, "Wall of Elements needs a chosen element for each section.", "wall_element_missing"
        end
        if wallIncludesWater(elements) and not hasWaterWallContext(action) then
            return false, "Walls of water can only be raised in bodies of water.", "wall_water_requires_water"
        end
        return true, nil, nil, elements
    end

    local function createWallSection(element, index, wallId)
        local section = {
            id = wallId .. "_section_" .. tostring(index),
            wallId = wallId,
            index = index,
            element = element,
            active = true,
            widthFeet = 10,
            heightFeet = 10,
            depthFeet = 2,
            dimensions = {
                width = 10,
                height = 10,
                depth = 2,
                unit = "feet",
            },
        }

        if element == "earth" then
            section.opaque = true
            section.toughAsStone = true
            section.blocksPassage = true
        elseif element == "wind" then
            section.opaque = false
            section.blocksMissiles = true
            section.blocksMissileWeapons = true
            section.blocksFlying = true
            section.blocksFlight = true
        elseif element == "fire" then
            section.opaque = true
            section.permeable = true
            section.woundsOnPassage = true
        elseif element == "water" then
            section.opaque = true
            section.impermeable = true
            section.requiresWater = true
            section.blocksWatercraft = true
        end

        return section
    end

    function resolver:createElementWall(actor, action, spell, resolveSpent, elements)
        action = action or {}
        resolveSpent = math.max(1, tonumber(resolveSpent) or 1)
        if actor then
            actor._elementWallCounter = (actor._elementWallCounter or 0) + 1
        end

        local counter = actor and actor._elementWallCounter or os.time()
        local wallId = action.wallId or ("wall_of_elements_" ..
            tostring(spellEntityKey(actor) or "caster") .. "_" .. tostring(counter))
        local wall = {
            id = wallId,
            spellId = spell and spell.id or "wall_of_elements",
            caster = actor,
            casterId = spellEntityKey(actor),
            active = true,
            concentration = true,
            resolveSpent = resolveSpent,
            zoneId = getWallZoneId(action, actor),
            sectionCount = #elements,
            dimensions = {
                width = 10,
                height = 10,
                depth = 2,
                unit = "feet",
            },
            sections = {},
        }

        for index, element in ipairs(elements) do
            wall.sections[index] = createWallSection(element, index, wallId)
        end

        if actor then
            actor.activeElementWalls = actor.activeElementWalls or {}
            actor.activeElementWalls[#actor.activeElementWalls + 1] = wall
        end

        return wall
    end

    local function wallEntryActive(entry)
        return entry ~= nil and entry.active ~= false
    end

    local function selectElementWallSection(wallOrSection, opts)
        opts = opts or {}
        if not wallOrSection then
            return nil
        end
        if wallOrSection.sections then
            local index = opts.sectionIndex or opts.index or 1
            return wallOrSection.sections[index]
        end
        return wallOrSection
    end

    local function wallSectionBlocksPassage(section, opts)
        opts = opts or {}
        if not wallEntryActive(section) then
            return false
        end

        local element = normalizeWallElement(section.element)
        if element == "earth" or section.toughAsStone or section.blocksPassage then
            return true
        end
        if element == "water" or section.impermeable then
            return true
        end
        if element == "wind" then
            return opts.missile == true or opts.missileWeapon == true or opts.projectile == true or
                opts.ranged == true or opts.flying == true or opts.flight == true
        end

        return false
    end

    function resolver:wallBlocksPassage(wallOrSection, opts)
        opts = opts or {}
        if not wallEntryActive(wallOrSection) then
            return false
        end
        if wallOrSection.sections then
            if opts.sectionIndex or opts.index then
                return wallSectionBlocksPassage(selectElementWallSection(wallOrSection, opts), opts)
            end
            for _, section in ipairs(wallOrSection.sections) do
                if wallSectionBlocksPassage(section, opts) then
                    return true
                end
            end
            return false
        end
        return wallSectionBlocksPassage(wallOrSection, opts)
    end

    function resolver:resolveElementWallPassage(wallOrSection, creature, opts)
        opts = opts or {}
        local section = selectElementWallSection(wallOrSection, opts)
        if not wallEntryActive(section) then
            return {
                success = false,
                effects = { "wall_missing" },
            }
        end
        if self:wallBlocksPassage(section, opts) then
            return {
                success = false,
                blocked = true,
                section = section,
                effects = { "wall_blocks_passage" },
            }
        end

        local passage = {
            success = true,
            section = section,
            effects = {},
        }
        if normalizeWallElement(section.element) == "fire" then
            passage.wounded = true
            passage.effects[#passage.effects + 1] = "wall_fire_wound"
            if creature and creature.takeWound and opts.skipDamage ~= true then
                self:applyDamage(creature, 1, opts.damageEffects or {}, nil, opts.allEntities, opts.woundOptions)
            end
        end

        return passage
    end

    local function isSpellObjectTarget(target)
        if not target then
            return false
        end
        if target.takeWound or target.isPC ~= nil or target.npcHealth ~= nil or target.health ~= nil then
            return false
        end
        return target.isItem or target.itemType or target.templateId or target.properties ~= nil
    end

    local PORTABLE_HOLE_TARGET_FIELDS = {
        "portableHole",
        "hasPortableHole",
        "portableHoleOpen",
        "passageOpen",
        "holeWindow",
        "blindPocket",
        "structureDamaged",
        "structuralIntegrityPreserved",
    }

    local PORTABLE_HOLE_PROPERTY_FIELDS = {
        "portableHole",
        "hasPortableHole",
        "portableHoleOpen",
        "passageOpen",
        "holeWindow",
        "blindPocket",
        "structureDamaged",
        "structuralIntegrityPreserved",
    }

    local function portableHoleTargetFromAction(action, target)
        action = action or {}
        return target or action.surface or action.materialTarget or action.material or action.object or action.feature
    end

    local function isPortableHoleLivingTissue(target)
        if not target then
            return false
        end

        local conditions = target.conditions or {}
        local props = target.properties or {}
        if target.livingTissue == true or props.livingTissue == true or target.living == true or props.living == true or
           target.livingCreature == true or props.livingCreature == true or conditions.livingTissue == true then
            return true
        end

        if target.isPC ~= nil or target.kin ~= nil or target.path ~= nil or target.creatureType ~= nil then
            return not (target.undead or target.construct or target.automaton or target.gargoyle or
                hasTag(target, "undead") or hasTag(target, "construct") or hasTag(target, "gargoyle") or
                hasTag(target, "animate_stone"))
        end

        if target.takeWound and not (props.inanimateMaterial or target.inanimateMaterial or target.inanimate) then
            return not (target.undead or target.construct or target.automaton or target.gargoyle or
                hasTag(target, "undead") or hasTag(target, "construct") or hasTag(target, "gargoyle") or
                hasTag(target, "animate_stone"))
        end

        return false
    end

    local function isPortableHoleInanimateMaterial(target)
        if not target then
            return false
        end

        local props = target.properties or {}
        if target.inanimateMaterial == true or props.inanimateMaterial == true or target.inanimate == true or
           props.inanimate == true then
            return true
        end
        if target.material or props.material or target.surfaceMaterial or props.surfaceMaterial then
            return true
        end
        if target.isWall or target.isDoor or target.isChest or target.wall or target.door or target.chest or
           props.wall or props.door or props.chest then
            return true
        end
        if target.isItem or target.itemType or target.templateId or target.properties ~= nil then
            return true
        end

        return false
    end

    local function portableHoleHasOtherSide(action, target)
        action = action or {}
        local props = target and target.properties or {}
        if action.noOtherSide == true or action.blindPocket == true or target.noOtherSide == true or
           target.blindPocket == true or props.noOtherSide == true or props.blindPocket == true then
            return false
        end
        if action.hasOtherSide == false or target.hasOtherSide == false or props.hasOtherSide == false then
            return false
        end
        return true
    end

    local function validatePortableHole(action, target)
        local surface = portableHoleTargetFromAction(action, target)
        if not surface then
            return false, "Portable Hole needs an inanimate material surface.", "portable_hole_target_missing"
        end
        if isPortableHoleLivingTissue(surface) then
            return false, "Portable Hole does not function on living tissue.", "portable_hole_living_tissue"
        end
        if not isPortableHoleInanimateMaterial(surface) then
            return false, "Portable Hole can only open through inanimate material.",
                "portable_hole_target_not_inanimate"
        end
        if surface.portableHole and surface.portableHole.active ~= false then
            return false, "That surface already has an active Portable Hole.", "portable_hole_already_open"
        end

        return true, nil, nil, surface
    end

    local function createPortableHole(actor, surface, action, spell, component)
        action = action or {}
        local props = surface.properties or {}
        local hadProperties = surface.properties ~= nil
        surface.properties = props

        local previousFields = {}
        local previousProperties = {}
        for _, key in ipairs(PORTABLE_HOLE_TARGET_FIELDS) do
            previousFields[key] = rememberField(surface, key)
        end
        for _, key in ipairs(PORTABLE_HOLE_PROPERTY_FIELDS) do
            previousProperties[key] = rememberField(props, key)
        end

        local hasOtherSide = portableHoleHasOtherSide(action, surface)
        local hole = {
            spellId = spell and spell.id or "portable_hole",
            caster = actor,
            casterId = spellEntityKey(actor),
            target = surface,
            targetId = spellEntityKey(surface),
            component = component,
            active = true,
            concentration = true,
            hasOtherSide = hasOtherSide,
            otherSide = action.otherSide or action.destination or surface.otherSide or props.otherSide,
            passageAllowsThingsToPass = hasOtherSide,
            windowToImmediateOtherSide = hasOtherSide,
            pocketDepthFeet = hasOtherSide and nil or 1,
            contents = action.contents or surface.portableHoleContents or {},
            noStructuralDamage = true,
            preservesStructuralIntegrity = true,
            previousFields = previousFields,
            previousProperties = previousProperties,
            hadProperties = hadProperties,
        }

        surface.portableHole = hole
        surface.hasPortableHole = true
        surface.portableHoleOpen = true
        surface.passageOpen = true
        surface.holeWindow = true
        surface.blindPocket = not hasOtherSide
        surface.structureDamaged = false
        surface.structuralIntegrityPreserved = true

        props.portableHole = true
        props.hasPortableHole = true
        props.portableHoleOpen = true
        props.passageOpen = true
        props.holeWindow = true
        props.blindPocket = not hasOtherSide
        props.structureDamaged = false
        props.structuralIntegrityPreserved = true

        if actor then
            actor.activePortableHoles = actor.activePortableHoles or {}
            actor.activePortableHoles[#actor.activePortableHoles + 1] = hole
        end

        return hole
    end

    local function portableHoleFromRef(holeOrSurface)
        if not holeOrSurface then
            return nil
        end
        if holeOrSurface.spellId == "portable_hole" then
            return holeOrSurface
        end
        return holeOrSurface.portableHole
    end

    function resolver:portableHoleAllowsPassage(holeOrSurface)
        local hole = portableHoleFromRef(holeOrSurface)
        return hole ~= nil and hole.active ~= false and hole.hasOtherSide == true
    end

    function resolver:placeInPortableHole(holeOrSurface, item)
        local hole = portableHoleFromRef(holeOrSurface)
        if not hole or hole.active == false or not item then
            return {
                success = false,
                effects = { "portable_hole_missing" },
            }
        end

        if hole.hasOtherSide then
            item.passedThroughPortableHole = true
            return {
                success = true,
                passedThrough = true,
                hole = hole,
                item = item,
                effects = { "portable_hole_passage" },
            }
        end

        hole.contents = hole.contents or {}
        hole.contents[#hole.contents + 1] = item
        item.inPortableHole = true
        item.inPortableHolePocket = true
        return {
            success = true,
            storedInPocket = true,
            hole = hole,
            item = item,
            effects = { "portable_hole_pocket_item" },
        }
    end

    closePortableHole = function(actor, hole, reason)
        if not hole then
            return
        end

        hole.active = false
        hole.ended = true
        hole.endReason = reason or "ended"

        if not hole.hasOtherSide then
            for _, item in ipairs(hole.contents or {}) do
                item.inPortableHole = false
                item.inPortableHolePocket = false
                item.swallowedByMaterial = true
                item.swallowedButUndamaged = true
                item.destroyed = item.destroyed == true and true or false
            end
            hole.contentsSwallowed = true
        end

        local surface = hole.target
        if surface then
            for key, value in pairs(hole.previousFields or {}) do
                restoreField(surface, key, value)
            end
            if surface.properties then
                for key, value in pairs(hole.previousProperties or {}) do
                    restoreField(surface.properties, key, value)
                end
                if not hole.hadProperties and next(surface.properties) == nil then
                    surface.properties = nil
                end
            end
        end

        if actor and actor.activePortableHoles then
            for index = #actor.activePortableHoles, 1, -1 do
                if actor.activePortableHoles[index] == hole then
                    table.remove(actor.activePortableHoles, index)
                end
            end
        end
    end

    local mirrorMeld = {
        targetFields = {
            "mirrorMeld",
            "mirrorMeldActive",
            "mirrorMeldOpen",
            "mirrorPortalOpen",
            "portalOpen",
            "reflectivePortal",
        },
        propertyFields = {
            "mirrorMeld",
            "mirrorMeldActive",
            "mirrorMeldOpen",
            "mirrorPortalOpen",
            "portalOpen",
            "reflectivePortal",
        },
        creatureFields = {
            "mirrorMeld",
            "inMirrorMeld",
            "visibleOnlyInMirror",
            "canSeeHearNearMirror",
            "canInteractWithWorld",
            "mirrorMeldReflection",
            "reflectedInMirror",
            "intangibleFromOutside",
            "cannotInteractWithWorld",
        },
        creatureConditions = {
            "mirrorMeldReflection",
            "reflection",
        },
        itemFields = {
            "mirrorMeld",
            "inMirrorMeld",
            "visibleInMirror",
            "intangibleFromOutside",
            "magicalWeight",
            "stillCountsAgainstPackSlots",
            "mirrorMeldItem",
        },
        itemProperties = {
            "mirrorMeld",
            "inMirrorMeld",
            "visibleInMirror",
            "intangibleFromOutside",
            "magicalWeight",
            "stillCountsAgainstPackSlots",
            "mirrorMeldItem",
        },
        sizeRanks = {
            tiny = 1,
            little = 1,
            small = 2,
            halfling = 2,
            goblin = 2,
            child = 2,
            medium = 3,
            normal = 3,
            person = 3,
            human = 3,
            adventurer = 3,
            dwarf = 3,
            elf = 3,
            large = 4,
            troll = 4,
            ogre = 4,
            giant = 5,
            huge = 5,
        },
    }

    function mirrorMeld.rememberFields(container, keys)
        local fields = {}
        for _, key in ipairs(keys or {}) do
            fields[key] = rememberField(container, key)
        end
        return fields
    end

    function mirrorMeld.restoreFields(container, fields)
        for key, value in pairs(fields or {}) do
            restoreField(container, key, value)
        end
    end

    function mirrorMeld.removeValue(list, value)
        for index = #(list or {}), 1, -1 do
            if list[index] == value then
                table.remove(list, index)
            end
        end
    end

    function mirrorMeld.addUniqueValue(list, value)
        for _, entry in ipairs(list or {}) do
            if entry == value then
                return
            end
        end
        list[#list + 1] = value
    end

    function mirrorMeld.hasPropertyTag(props, tag)
        local tags = props and props.tags
        if type(tags) ~= "table" then
            return false
        end
        if tags[tag] then
            return true
        end
        return tableContainsValue(tags, tag)
    end

    function mirrorMeld.targetFromAction(action, target)
        action = action or {}
        return target or action.mirror or action.reflectiveSurface or action.surface or action.object or
            action.targetObject
    end

    function mirrorMeld.isTarget(target)
        if not target then
            return false
        end

        local props = target.properties or {}
        if target.mirror == true or target.isMirror == true or target.reflectiveSurface == true or
           target.reflective == true or props.mirror == true or props.isMirror == true or
           props.reflectiveSurface == true or props.reflective == true or hasTag(target, "mirror") or
           mirrorMeld.hasPropertyTag(props, "mirror") then
            return true
        end

        local name = normalizeSpellKey(target.name or target.id or props.name)
        return string.find(name or "", "mirror", 1, true) ~= nil
    end

    function mirrorMeld.validate(action, target)
        local mirror = mirrorMeld.targetFromAction(action, target)
        if not mirror then
            return false, "Mirror Meld needs a mirror large enough to enter.", "mirror_meld_target_missing"
        end
        if not mirrorMeld.isTarget(mirror) then
            return false, "Mirror Meld can only open a portal through a mirror.", "mirror_meld_target_not_mirror"
        end
        if mirror.mirrorMeld and mirror.mirrorMeld.active ~= false then
            return false, "That mirror already has an active Mirror Meld portal.", "mirror_meld_already_open"
        end

        return true, nil, nil, mirror
    end

    function mirrorMeld.sizeRank(value, defaultRank)
        if type(value) == "number" then
            return value
        end

        local key = normalizeSpellKey(value)
        if key and mirrorMeld.sizeRanks[key] then
            return mirrorMeld.sizeRanks[key]
        end
        if key then
            for token, rank in pairs(mirrorMeld.sizeRanks) do
                if string.find(key, token, 1, true) then
                    return rank
                end
            end
        end

        return defaultRank or 3
    end

    function mirrorMeld.capacityRank(mirror, opts)
        opts = opts or {}
        local props = mirror and mirror.properties or {}
        local explicit = opts.mirrorSize or opts.capacitySize or mirror.capacitySize or mirror.mirrorSize or
            mirror.sizeCategory or props.capacitySize or props.mirrorSize or props.sizeCategory
        if explicit ~= nil then
            return mirrorMeld.sizeRank(explicit, 3)
        end

        local height = mirror and (mirror.heightInches or mirror.height or props.heightInches or props.height)
        local width = mirror and (mirror.widthInches or mirror.width or props.widthInches or props.width)
        local dimension = math.max(tonumber(height) or 0, tonumber(width) or 0)
        if dimension > 0 then
            if dimension < 36 then
                return 2
            elseif dimension < 72 then
                return 3
            end
            return 4
        end

        return 3
    end

    function mirrorMeld.subjectRank(subject, opts)
        opts = opts or {}
        return mirrorMeld.sizeRank(opts.size or opts.subjectSize or subject.sizeCategory or subject.creatureSize or
            subject.kin or subject.kind or subject.type, 3)
    end

    function mirrorMeld.create(actor, mirror, action, spell, component)
        action = action or {}
        local props = mirror.properties or {}
        local hadProperties = mirror.properties ~= nil
        mirror.properties = props

        local meld = {
            spellId = spell and spell.id or "mirror_meld",
            caster = actor,
            casterId = spellEntityKey(actor),
            target = mirror,
            targetId = spellEntityKey(mirror),
            component = component,
            active = true,
            concentration = false,
            portalOpen = true,
            allowsCreatures = true,
            allowsItems = true,
            allowsMultipleCreatures = true,
            visibleOnlyInsideMirror = true,
            heardNearMirror = true,
            itemsRemainVisibleButIntangible = true,
            carriedItemsKeepPackWeight = true,
            persistsUntilCreaturesLeaveOrMirrorBroken = true,
            capacityRank = mirrorMeld.capacityRank(mirror, action),
            occupants = {},
            occupantRecords = {},
            items = {},
            itemRecords = {},
            previousFields = mirrorMeld.rememberFields(mirror, mirrorMeld.targetFields),
            previousProperties = mirrorMeld.rememberFields(props, mirrorMeld.propertyFields),
            hadProperties = hadProperties,
        }

        mirror.mirrorMeld = meld
        mirror.mirrorMeldActive = true
        mirror.mirrorMeldOpen = true
        mirror.mirrorPortalOpen = true
        mirror.portalOpen = true
        mirror.reflectivePortal = true

        props.mirrorMeld = true
        props.mirrorMeldActive = true
        props.mirrorMeldOpen = true
        props.mirrorPortalOpen = true
        props.portalOpen = true
        props.reflectivePortal = true

        if actor then
            actor.activeMirrorMelds = actor.activeMirrorMelds or {}
            actor.activeMirrorMelds[#actor.activeMirrorMelds + 1] = meld
        end

        return meld
    end

    function mirrorMeld.fromRef(mirrorOrMeld)
        if not mirrorOrMeld then
            return nil
        end
        if mirrorOrMeld.spellId == "mirror_meld" then
            return mirrorOrMeld
        end
        return mirrorOrMeld.mirrorMeld
    end

    function mirrorMeld.isCreature(subject)
        return subject and (subject.takeWound or subject.isPC ~= nil or subject.npcHealth ~= nil or
            subject.health ~= nil or subject.conditions ~= nil)
    end

    function mirrorMeld.rememberCreature(subject)
        local hadConditions = subject.conditions ~= nil
        subject.conditions = subject.conditions or {}
        return {
            subject = subject,
            hadConditions = hadConditions,
            fields = mirrorMeld.rememberFields(subject, mirrorMeld.creatureFields),
            conditions = mirrorMeld.rememberFields(subject.conditions, mirrorMeld.creatureConditions),
        }
    end

    function mirrorMeld.rememberItem(item)
        local hadProperties = item.properties ~= nil
        item.properties = item.properties or {}
        return {
            item = item,
            hadProperties = hadProperties,
            fields = mirrorMeld.rememberFields(item, mirrorMeld.itemFields),
            properties = mirrorMeld.rememberFields(item.properties, mirrorMeld.itemProperties),
        }
    end

    function mirrorMeld.restoreCreature(record)
        local subject = record and record.subject
        if not subject then
            return
        end
        mirrorMeld.restoreFields(subject, record.fields)
        if subject.conditions then
            mirrorMeld.restoreFields(subject.conditions, record.conditions)
            if not record.hadConditions and next(subject.conditions) == nil then
                subject.conditions = nil
            end
        end
    end

    function mirrorMeld.restoreItem(record)
        local item = record and record.item
        if not item then
            return
        end
        mirrorMeld.restoreFields(item, record.fields)
        if item.properties then
            mirrorMeld.restoreFields(item.properties, record.properties)
            if not record.hadProperties and next(item.properties) == nil then
                item.properties = nil
            end
        end
    end

    function mirrorMeld.hasCreatureOccupants(meld)
        return meld and type(meld.occupants) == "table" and #meld.occupants > 0
    end

    function resolver:enterMirrorMeld(mirrorOrMeld, subject, opts)
        opts = opts or {}
        local meld = mirrorMeld.fromRef(mirrorOrMeld)
        if not meld or meld.active == false or not subject then
            return {
                success = false,
                effects = { "mirror_meld_missing" },
            }
        end

        if mirrorMeld.isCreature(subject) then
            if mirrorMeld.subjectRank(subject, opts) > (opts.capacityRank or meld.capacityRank or 3) then
                return {
                    success = false,
                    mirrorMeld = meld,
                    subject = subject,
                    effects = { "mirror_meld_mirror_too_small" },
                }
            end

            local record = meld.occupantRecords[subject]
            if not record then
                record = mirrorMeld.rememberCreature(subject)
                meld.occupantRecords[subject] = record
            end
            mirrorMeld.addUniqueValue(meld.occupants, subject)
            subject.conditions = subject.conditions or {}
            subject.mirrorMeld = meld
            subject.inMirrorMeld = true
            subject.visibleOnlyInMirror = true
            subject.canSeeHearNearMirror = true
            subject.canInteractWithWorld = false
            subject.cannotInteractWithWorld = true
            subject.reflectedInMirror = true
            subject.mirrorMeldReflection = {
                mirror = meld.target,
                mirrorId = meld.targetId,
                canSeeHearNearMirror = true,
                canInteractWithWorld = false,
            }
            subject.conditions.mirrorMeldReflection = true
            subject.conditions.reflection = true

            return {
                success = true,
                mirrorMeld = meld,
                subject = subject,
                reflection = subject.mirrorMeldReflection,
                effects = { "mirror_meld_entered", "mirror_meld_reflection" },
            }
        end

        local record = meld.itemRecords[subject]
        if not record then
            record = mirrorMeld.rememberItem(subject)
            meld.itemRecords[subject] = record
        end
        mirrorMeld.addUniqueValue(meld.items, subject)
        subject.mirrorMeld = meld
        subject.inMirrorMeld = true
        subject.visibleInMirror = true
        subject.intangibleFromOutside = true
        subject.mirrorMeldItem = true
        subject.properties = subject.properties or {}
        subject.properties.mirrorMeld = true
        subject.properties.inMirrorMeld = true
        subject.properties.visibleInMirror = true
        subject.properties.intangibleFromOutside = true
        subject.properties.mirrorMeldItem = true
        if opts.carried == true then
            subject.magicalWeight = true
            subject.stillCountsAgainstPackSlots = true
            subject.properties.magicalWeight = true
            subject.properties.stillCountsAgainstPackSlots = true
        end

        return {
            success = true,
            mirrorMeld = meld,
            item = subject,
            effects = { "mirror_meld_item_stored" },
        }
    end

    function resolver:exitMirrorMeld(mirrorOrMeld, subject, opts)
        opts = opts or {}
        local meld = mirrorMeld.fromRef(mirrorOrMeld)
        if not meld or meld.active == false or not subject then
            return {
                success = false,
                effects = { "mirror_meld_missing" },
            }
        end

        local creatureRecord = meld.occupantRecords[subject]
        if creatureRecord then
            mirrorMeld.restoreCreature(creatureRecord)
            meld.occupantRecords[subject] = nil
            mirrorMeld.removeValue(meld.occupants, subject)
            subject.exitedMirrorMeld = true

            local endedSpell = nil
            if opts.keepPortalOpen ~= true and not mirrorMeld.hasCreatureOccupants(meld) and meld.spellEntry and meld.caster then
                endedSpell = self:endOngoingSpell(meld.caster, meld.spellEntry, "mirror_meld_creatures_left", {
                    source = opts.source,
                })
            end

            return {
                success = true,
                mirrorMeld = meld,
                subject = subject,
                endedSpell = endedSpell,
                effects = { "mirror_meld_exited" },
            }
        end

        local itemRecord = meld.itemRecords[subject]
        if itemRecord then
            mirrorMeld.restoreItem(itemRecord)
            meld.itemRecords[subject] = nil
            mirrorMeld.removeValue(meld.items, subject)
            subject.removedFromMirrorMeld = true
            return {
                success = true,
                mirrorMeld = meld,
                item = subject,
                effects = { "mirror_meld_item_removed" },
            }
        end

        return {
            success = false,
            mirrorMeld = meld,
            effects = { "mirror_meld_subject_missing" },
        }
    end

    closeMirrorMeld = function(resolverInstance, actor, meldOrMirror, reason, opts)
        opts = opts or {}
        local meld = mirrorMeld.fromRef(meldOrMirror)
        if not meld then
            return
        end

        local broken = reason == "mirror_broken" or opts.broken == true
        meld.active = false
        meld.ended = true
        meld.endReason = reason or "ended"
        meld.broken = broken

        for _, subject in ipairs(meld.occupants or {}) do
            local record = meld.occupantRecords and meld.occupantRecords[subject]
            mirrorMeld.restoreCreature(record)
            subject.returnedFromMirrorMeld = true
            if broken then
                subject.shuntedByBrokenMirror = true
                subject.mirrorBreakWounds = (subject.mirrorBreakWounds or 0) + 2
                if subject.takeWound and opts.skipDamage ~= true and resolverInstance then
                    resolverInstance:applyDamage(subject, 2, opts.damageEffects or {}, nil, opts.allEntities,
                        opts.woundOptions)
                end
            end
        end
        meld.occupants = {}
        meld.occupantRecords = {}

        for _, item in ipairs(meld.items or {}) do
            local record = meld.itemRecords and meld.itemRecords[item]
            mirrorMeld.restoreItem(record)
            item.returnedFromMirrorMeld = true
            if broken then
                item.destroyed = true
                item.destroyedByMirrorBreak = true
            end
        end
        meld.items = {}
        meld.itemRecords = {}

        local mirror = meld.target
        if mirror then
            mirrorMeld.restoreFields(mirror, meld.previousFields)
            if mirror.properties then
                mirrorMeld.restoreFields(mirror.properties, meld.previousProperties)
                if not meld.hadProperties and next(mirror.properties) == nil then
                    mirror.properties = nil
                end
            end
            if broken then
                mirror.broken = true
                mirror.mirrorBroken = true
                mirror.properties = mirror.properties or {}
                mirror.properties.broken = true
                mirror.properties.mirrorBroken = true
            end
        end

        if actor and actor.activeMirrorMelds then
            mirrorMeld.removeValue(actor.activeMirrorMelds, meld)
        end
    end

    function resolver:breakMirrorMeld(mirrorOrMeld, opts)
        opts = opts or {}
        local meld = mirrorMeld.fromRef(mirrorOrMeld)
        if not meld or meld.active == false then
            return {
                success = false,
                effects = { "mirror_meld_missing" },
            }
        end

        local endedSpell = nil
        if meld.spellEntry and meld.caster then
            endedSpell = self:endOngoingSpell(meld.caster, meld.spellEntry, "mirror_broken", {
                source = opts.source,
                broken = true,
                allEntities = opts.allEntities,
                damageEffects = opts.damageEffects,
                woundOptions = opts.woundOptions,
            })
        else
            closeMirrorMeld(self, meld.caster, meld, "mirror_broken", opts)
        end

        return {
            success = true,
            mirrorMeld = meld,
            endedSpell = endedSpell,
            effects = { "mirror_meld_broken", "mirror_meld_shunted" },
        }
    end

    local function normalizeIllusionKind(value)
        local normalized = normalizeSpellKey(value)
        if normalized == "creature" or normalized == "person" or normalized == "monster" or normalized == "animal" then
            return "creature"
        end
        return "object"
    end

    local function illusionAttemptsSubtraction(action)
        action = action or {}
        if action.subtractive == true or action.makeUnseen == true or action.makeInvisible == true or
           action.erase == true or action.remove == true or action.removeObject == true or action.deleteObject == true then
            return true
        end

        local mode = normalizeSpellKey(action.illusionMode or action.mode or action.intent or action.effect)
        return mode == "subtract" or mode == "subtractive" or mode == "hide" or mode == "invisible" or
            mode == "invisibility" or mode == "erase" or mode == "remove"
    end

    local function validateVisualIllusion(action)
        if illusionAttemptsSubtraction(action) then
            return false, "Illusion can add images, but cannot make existing things unseen.",
                "illusion_subtractive_forbidden"
        end

        return true
    end

    local function createVisualIllusion(actor, action, spell, component)
        action = action or {}
        actor._visualIllusionCounter = (actor._visualIllusionCounter or 0) + 1

        local illusion = {
            id = action.illusionId or ("illusion_" .. tostring(spellEntityKey(actor) or "caster") .. "_" ..
                tostring(actor._visualIllusionCounter)),
            spellId = spell and spell.id or "illusion",
            caster = actor,
            casterId = spellEntityKey(actor),
            component = component,
            active = true,
            concentration = true,
            kind = normalizeIllusionKind(action.illusionKind or action.kind or action.creatureOrObject),
            image = action.image or action.illusion or action.description or action.form or "illusory object",
            zoneId = action.zoneId or action.zone or action.targetZone or (actor and actor.zone),
            location = action.location,
            visualOnly = true,
            hologram = true,
            additiveOnly = true,
            subtractive = false,
            tangible = false,
            intangible = true,
            hasWeight = false,
            hasSubstance = false,
            hasSound = false,
            hasSmell = false,
            createsSound = false,
            createsSmell = false,
            createsWeight = false,
            createsSubstance = false,
            canObscureByAddition = true,
            cannotMakeExistingThingsUnseen = true,
            details = {},
            commands = {},
            detailResolveSpent = 0,
        }

        local details = action.details or action.initialDetails
        if type(details) == "table" then
            for _, detail in ipairs(details) do
                illusion.details[#illusion.details + 1] = detail
            end
        elseif details then
            illusion.details[#illusion.details + 1] = details
        end

        actor.activeVisualIllusions = actor.activeVisualIllusions or {}
        actor.activeVisualIllusions[#actor.activeVisualIllusions + 1] = illusion
        return illusion
    end

    local function resolveVisualIllusionRef(actor, illusionRef)
        if type(illusionRef) == "table" and illusionRef.spellId == "illusion" then
            return illusionRef
        end

        local illusions = actor and actor.activeVisualIllusions or {}
        if illusionRef == nil and #illusions == 1 then
            return illusions[1]
        end

        local key = spellEntityKey(illusionRef)
        for _, illusion in ipairs(illusions) do
            if illusion == illusionRef or illusion.id == key then
                return illusion
            end
        end

        return nil
    end

    function resolver:commandVisualIllusion(actor, illusionRef, command, opts)
        opts = opts or {}
        local illusion = resolveVisualIllusionRef(actor, illusionRef)
        if not illusion or illusion.active == false then
            return {
                success = false,
                effects = { "illusion_missing" },
            }
        end

        local entry = {
            command = command or opts.command or opts.action or "mental command",
            requiresMiscAction = actionIsChallenge(opts),
            turn = opts.turn,
        }
        illusion.commands[#illusion.commands + 1] = entry
        illusion.lastCommand = entry.command
        illusion.mentalCommands = true

        return {
            success = true,
            illusion = illusion,
            command = entry,
            effects = { entry.requiresMiscAction and "illusion_command_misc_action" or "illusion_command" },
        }
    end

    function resolver:addVisualIllusionDetail(actor, illusionRef, detail, opts)
        opts = opts or {}
        local illusion = resolveVisualIllusionRef(actor, illusionRef)
        if not illusion or illusion.active == false then
            return {
                success = false,
                effects = { "illusion_missing" },
            }
        end

        local cost = opts.resolveCost or 1
        if opts.free ~= true then
            local ok, reason = self:spendSpellResolve(actor, cost)
            if not ok then
                return {
                    success = false,
                    reason = reason,
                    effects = { "resolve_missing" },
                }
            end
            illusion.detailResolveSpent = (illusion.detailResolveSpent or 0) + cost
        end

        illusion.details[#illusion.details + 1] = detail
        illusion.lastDetail = detail

        return {
            success = true,
            illusion = illusion,
            detail = detail,
            resolveSpent = opts.free == true and 0 or cost,
            effects = { "illusion_detail_added" },
        }
    end

    local function isUndeadTarget(target)
        return target and (target.undead or hasTag(target, "undead"))
    end

    local function isWastesSpirit(target)
        if not target or not (target.spirit or hasTag(target, "spirit")) then
            return false
        end
        local realm = target.realm or target.farRealm or target.branch or target.spiritRealm
        return realm == "wastes" or target.wastesSpirit or hasTag(target, "wastes") or hasTag(target, "wastes_spirit")
    end

    local function isLivingSightedTarget(target)
        if not target or isSpellObjectTarget(target) or isUndeadTarget(target) then
            return false
        end
        if target.construct or target.automaton or hasTag(target, "construct") or hasTag(target, "automaton") then
            return false
        end
        local conditions = target.conditions or {}
        if target.sightless or target.noSight or conditions.blind then
            return false
        end
        return target.takeWound or target.isPC ~= nil or target.npcHealth ~= nil or target.health ~= nil
    end

    local function getGustDestinationZone(action)
        action = action or {}
        return action.destinationZone or action.targetZone or action.destinationZoneId or action.targetZoneId or
            action.displaceToZone or action.zoneTo
    end

    local function isHumanSizedSpellTarget(target)
        if not target or isSpellObjectTarget(target) then
            return false
        end
        if target.humanSized ~= nil then
            return target.humanSized == true
        end
        if target.large or target.huge or target.massive or target.giant then
            return false
        end

        local size = target.size or target.sizeCategory or target.scale or target.category
        if not size then
            return true
        end

        local normalizedSize = normalizeSpellKey(size)
        return normalizedSize ~= "large" and normalizedSize ~= "huge" and normalizedSize ~= "giant" and
            normalizedSize ~= "massive" and normalizedSize ~= "gargantuan" and normalizedSize ~= "colossal" and
            normalizedSize ~= "titanic"
    end

    local function collectDefyDepthsTargets(action, target)
        local targets = {}
        if type(action.targets) == "table" and #action.targets > 0 then
            for _, spellTarget in ipairs(action.targets) do
                if spellTarget then
                    targets[#targets + 1] = spellTarget
                end
            end
        elseif target then
            targets[#targets + 1] = target
        end
        return targets
    end

    local function isDefyDepthsShip(target)
        local props = target and target.properties or {}
        return target and (target.ship == true or target.boat == true or target.vessel == true or
            props.ship == true or props.boat == true or props.vessel == true or
            hasTag(target, "ship") or hasTag(target, "boat") or hasTag(target, "vessel"))
    end

    local function getDefyDepthsShipResolveCost(target)
        if not isDefyDepthsShip(target) then
            return 0
        end

        local props = target.properties or {}
        local size = normalizeSpellKey(target.shipSize or props.shipSize or target.sizeCategory or target.size or props.size)
        if size == "small" or size == "rowboat" or size == "boat" or size == "skiff" or size == "dinghy" then
            return 1
        end

        return 3
    end

    local function isChestSizedObject(target)
        if not isSpellObjectTarget(target) then
            return false
        end
        if isDefyDepthsShip(target) then
            return true
        end
        if target.chestSized ~= nil then
            return target.chestSized == true
        end

        local props = target.properties or {}
        local size = normalizeSpellKey(target.sizeCategory or props.sizeCategory or target.bulk or props.bulk)
        if size == "large" or size == "huge" or size == "massive" or size == "giant" then
            return false
        end
        if type(target.size) == "number" and target.size > 6 then
            return false
        end

        return true
    end

    local function validateDefyDepths(action, spell, resolveSpent, target)
        local targets = collectDefyDepthsTargets(action, target)
        if #targets < 1 then
            return false, "Defy Depths needs at least one target.", "spell_target_missing"
        end

        local requiredResolve = 1 + math.max(0, #targets - (spell and spell.baseTargets or 1)) *
            (spell and spell.extraTargetResolve or 1)
        for _, depthsTarget in ipairs(targets) do
            if isSpellObjectTarget(depthsTarget) then
                if not isChestSizedObject(depthsTarget) then
                    return false, "Defy Depths can only float chest-sized objects or paid-for ships.",
                        "defy_depths_target_too_large"
                end
                requiredResolve = requiredResolve + getDefyDepthsShipResolveCost(depthsTarget)
            elseif not isHumanSizedSpellTarget(depthsTarget) then
                return false, "Defy Depths can only affect human-sized creatures or chest-sized objects.",
                    "defy_depths_target_invalid"
            end
        end

        if resolveSpent < requiredResolve then
            return false, "Defy Depths needs more Resolve for those targets.", "defy_depths_resolve_missing"
        end

        return true, nil, nil, targets
    end

    local function isPersonSpellTarget(target)
        if not target or isSpellObjectTarget(target) or isUndeadTarget(target) then
            return false
        end
        if target.construct or target.automaton or hasTag(target, "construct") or hasTag(target, "automaton") then
            return false
        end
        return target.isPerson == true or target.isPC ~= nil or target.kin ~= nil or target.path ~= nil or target.takeWound ~= nil
    end

    local function isDeadSpellTarget(target)
        local conditions = target and target.conditions or {}
        local props = target and target.properties or {}
        return target and (target.dead == true or target.isDead == true or target.corpse == true or
            target.freshCorpse == true or target.type == "corpse" or props.corpse == true or
            conditions.dead == true)
    end

    local function isDeadPersonSpellTarget(target)
        if not isDeadSpellTarget(target) then
            return false
        end
        local props = target.properties or {}
        if target.animal == true or props.animal == true or target.creatureType == "animal" or target.kind == "animal" or
           hasTag(target, "animal") then
            return false
        end
        return target.isPerson == true or target.wasPerson == true or target.isPC ~= nil or target.kin ~= nil or
            target.path ~= nil or props.person == true or props.wasPerson == true or target.personCorpse == true or
            hasTag(target, "person") or hasTag(target, "humanoid") or hasTag(target, "adventurer")
    end

    local function validateNecromancy(action, target)
        if not target then
            return false, "Necromancy needs a dead person.", "spell_target_missing"
        end
        if not isDeadSpellTarget(target) then
            return false, "Necromancy can only target the dead.", "necromancy_target_not_dead"
        end
        if not isDeadPersonSpellTarget(target) then
            return false, "Necromancy needs the skull of a dead person.", "necromancy_target_not_person"
        end
        if target.necromancy and target.necromancy.active ~= false then
            return false, "That corpse is already answering through Necromancy.", "necromancy_already_active"
        end
        return true, nil, nil
    end

    local function raiseZombieRequiresWatch(action)
        action = action or {}
        return action.watchSpent == true or action.ritualWatchSpent == true or action.spentWatch == true or
            action.ritualComplete == true
    end

    local function getRaiseZombieServiceCount(actor, resolveSpent)
        local wands = tonumber(actor and (actor.wands or (actor.attributes and actor.attributes[constants.SUITS.WANDS]))) or 0
        return math.max(0, wands) * math.max(1, resolveSpent or 1)
    end

    local function validateRaiseZombie(action, target, resolveSpent)
        if not target then
            return false, "Raise Zombie needs a dead body.", "spell_target_missing"
        end
        if not isDeadSpellTarget(target) then
            return false, "Raise Zombie can only target a dead body.", "raise_zombie_target_not_dead"
        end
        if target.raisedZombie or target.corpseRaisedByRaiseZombie then
            return false, "That body has already been raised.", "raise_zombie_body_already_raised"
        end
        if not raiseZombieRequiresWatch(action) then
            return false, "Raise Zombie requires spending a watch on the ritual.", "raise_zombie_watch_required"
        end
        if getRaiseZombieServiceCount(action and action.actor, resolveSpent) < 1 then
            return false, "Raise Zombie needs at least one bound service.", "raise_zombie_no_services"
        end
        return true, nil, nil
    end

    local function addRaisedZombieCompanion(actor, zombie)
        if not actor or not zombie then
            return
        end

        actor.companions = actor.companions or {}
        actor.companions[#actor.companions + 1] = zombie
        if not actor.companion then
            actor.companion = zombie
        end
    end

    local function createRaisedZombie(actor, body, action, spell, resolveSpent)
        action = action or {}
        local zombieName = action.zombieName or ((body and (body.name or body.id) or "Corpse") .. " Zombie")
        local zombie = nil
        local err = nil

        if body and (body.isPC ~= nil or body.kin ~= nil or body.path ~= nil or body.talents ~= nil) then
            zombie, err = entity_factory.createUndeadFromAdventurer(body, "zombie", {
                id = action.zombieId,
                name = zombieName,
                location = action.location or body.location,
                zone = action.zone or body.zone,
            })
        else
            zombie, err = entity_factory.createEntity("zombie", {
                name = zombieName,
                location = action.location or (body and body.location),
            })
            if zombie then
                zombie.id = action.zombieId or ("raised_zombie_" .. tostring(body and (body.id or body.name) or os.time()))
                zombie.zone = action.zone or (body and body.zone) or zombie.zone
                zombie.sourceBodyId = body and (body.id or body.name)
                zombie.sourceBodyName = body and body.name
            end
        end

        if not zombie then
            return nil, err or "zombie_blueprint_missing"
        end

        local services = getRaiseZombieServiceCount(actor, resolveSpent)
        zombie.conditions = zombie.conditions or {}
        zombie.conditions.controlled = true
        zombie.conditions.boundZombie = true
        zombie.boundZombie = true
        zombie.boundTo = actor
        zombie.boundToId = spellEntityKey(actor)
        zombie.controlledBy = actor
        zombie.commandsAny = true
        zombie.obeysMostCommands = true
        zombie.obeysSuicidalCommands = true
        zombie.physicalCapabilitiesPossessedInLife = true
        zombie.sourceBody = body
        zombie.sourceBodyId = zombie.sourceBodyId or (body and (body.id or body.name))
        zombie.sourceBodyName = zombie.sourceBodyName or (body and body.name)
        zombie.raiseZombie = {
            caster = actor,
            casterId = spellEntityKey(actor),
            body = body,
            bodyId = body and (body.id or body.name),
            spellId = spell and spell.id or "raise_zombie",
            active = true,
            concentration = false,
            servicesTotal = services,
            servicesRemaining = services,
            servicesCompleted = 0,
            obeysMostCommands = true,
            obeysSuicidalCommands = true,
            devilBoundInCorpse = true,
            resolveNeverRefreshesWhileActive = true,
        }
        zombie.zombieServicesRemaining = services
        zombie.zombieServicesTotal = services

        if body then
            body.raisedZombie = zombie
            body.corpseRaisedByRaiseZombie = true
            body.raisedBy = actor
            body.raisedBySpell = spell and spell.id or "raise_zombie"
        end

        addRaisedZombieCompanion(actor, zombie)
        return zombie, nil
    end

    function resolver:canSpeakWithDead(speaker, target)
        local necromancy = target and target.necromancy
        if not necromancy or necromancy.active == false then
            return false
        end
        return necromancy.caster == speaker
    end

    local FLESHCRAFT_PARTS = {
        hand = true,
        eye = true,
        ear = true,
        mouth = true,
    }

    local function getFleshcraftPart(action)
        action = action or {}
        local part = action.bodyPart or action.fleshcraftPart or action.detachedPart or action.part
        part = normalizeSpellKey(part)
        if FLESHCRAFT_PARTS[part] then
            return part
        end
        return nil
    end

    local function fleshcraftCapabilities(part)
        if part == "hand" then
            return {
                crawlsLikeSpider = true,
                veryDifficultToNotice = true,
                canChokeSleepingTarget = true,
                canDeliverPoison = true,
            }
        elseif part == "eye" then
            return {
                rollsOnGround = true,
                remoteSight = true,
                ownerCanSeeThroughPart = true,
                ownerCanCloseEyesToSeeThroughPart = true,
            }
        elseif part == "ear" then
            return {
                flopsLikeFish = true,
                remoteHearing = true,
                ownerCanHearThroughPart = true,
            }
        elseif part == "mouth" then
            return {
                canSpeakNormally = true,
            }
        end
        return {}
    end

    local function validateFleshcraft(action, target)
        if not target then
            return false, "Fleshcraft needs the sorcerer as target.", "spell_target_missing"
        end
        if target.fleshcraft and target.fleshcraft.active ~= false then
            return false, "That sorcerer already has a detached body part.", "fleshcraft_already_active"
        end

        local part = getFleshcraftPart(action)
        if not part then
            return false, "Fleshcraft needs a body part: hand, eye, ear, or mouth.", "fleshcraft_part_missing"
        end

        return true, nil, nil, part
    end

    local function getFleshcraftState(partOrOwner)
        if not partOrOwner then
            return nil, nil
        end
        if partOrOwner.spellId == "fleshcraft" and partOrOwner.owner then
            return partOrOwner, partOrOwner.owner
        end
        return partOrOwner.fleshcraft, partOrOwner
    end

    local function applyFleshcraft(actor, target, action, spell)
        local _, _, _, part = validateFleshcraft(action, target)
        local capabilities = fleshcraftCapabilities(part)

        target.conditions = target.conditions or {}
        target.detachedBodyParts = target.detachedBodyParts or {}
        target.conditions.fleshcraft = true
        target.conditions.detachedBodyPart = true

        local state = {
            caster = actor,
            casterId = spellEntityKey(actor),
            owner = target,
            ownerId = spellEntityKey(target),
            target = target,
            targetId = spellEntityKey(target),
            spellId = spell and spell.id or "fleshcraft",
            active = true,
            concentration = true,
            bodyPart = part,
            detachedPart = part,
            movesIndependently = true,
            clumsy = true,
            reattachesWhenPlacedInOriginalPosition = true,
            damageTransfersToOwner = true,
            backlashWounds = 1,
            backlashDamageType = "piercing",
            capabilities = capabilities,
        }
        for key, value in pairs(capabilities) do
            state[key] = value
        end

        target.fleshcraft = state
        target.detachedBodyPart = state
        target.detachedBodyPartKind = part
        target.detachedBodyParts[part] = state
        return state
    end

    function resolver:damageFleshcraftedPart(partOrOwner, opts)
        opts = opts or {}
        local state, owner = getFleshcraftState(partOrOwner)
        if not state or state.active == false or not owner then
            return {
                success = false,
                effects = { "fleshcraft_missing" },
            }
        end

        local effects = { "piercing" }
        if owner.takeWound and opts.skipDamage ~= true then
            self:applyDamage(owner, state.backlashWounds or 1, effects, nil, opts.allEntities, opts.woundOptions)
        end

        local ended = self:endOngoingSpell(state.caster, state.spellEntry or {
            spellId = "fleshcraft",
            target = owner,
        }, opts.reason or "fleshcraft_part_damaged", {
            source = opts.source,
        })

        return {
            success = true,
            owner = owner,
            fleshcraft = state,
            endedSpell = ended,
            effects = { "fleshcraft_part_damaged", "piercing_wound" },
        }
    end

    function resolver:reattachFleshcraftedPart(partOrOwner, opts)
        opts = opts or {}
        local state, owner = getFleshcraftState(partOrOwner)
        if not state or state.active == false or not owner then
            return {
                success = false,
                effects = { "fleshcraft_missing" },
            }
        end

        local ended = self:endOngoingSpell(state.caster, state.spellEntry or {
            spellId = "fleshcraft",
            target = owner,
        }, opts.reason or "fleshcraft_reattached", {
            source = opts.source,
        })

        return {
            success = true,
            owner = owner,
            fleshcraft = state,
            endedSpell = ended,
            effects = { "fleshcraft_reattached" },
        }
    end

    local function isCreatureSpellTarget(target)
        if not target or isSpellObjectTarget(target) then
            return false
        end
        if target.takeWound or target.isPC ~= nil or target.npcHealth ~= nil or target.health ~= nil then
            return true
        end

        local props = target.properties or {}
        return target.creature == true or target.npc == true or target.monster == true or target.animal == true or
            target.undead == true or target.creatureType ~= nil or target.kind == "creature" or
            props.creature == true or hasTag(target, "creature") or hasTag(target, "monster")
    end

    local function getExplicitMaledictionCard(action)
        action = action or {}
        return action.maledictionCard or action.curseCard or action.randomCurseCard or action.drawnCurseCard or
            action.cardToRead
    end

    local function getMaledictionCardFromValue(action)
        action = action or {}
        local value = action.maledictionValue or action.curseValue
        if value == nil then
            return nil
        end

        value = math.floor(tonumber(value) or 0)
        local curse = spell_registry.MALEDICTION_CURSES[value]
        return {
            name = curse and curse.rank or tostring(value),
            value = value,
            suit = action.maledictionSuit or action.curseSuit,
        }
    end

    local function getMaledictionDeck(resolver, action)
        action = action or {}
        return action.maledictionDeck or action.curseDeck or action.deck or resolver.playerDeck
    end

    function resolver:getMaledictionDraw(action)
        action = action or {}
        local explicit = getExplicitMaledictionCard(action) or getMaledictionCardFromValue(action)
        if explicit then
            return explicit, false
        end

        local deck = getMaledictionDeck(self, action)
        if not deck or not deck.draw then
            return nil, false
        end

        for _ = 1, 80 do
            local card = deck:draw()
            if not card then
                return nil, true
            end
            if spell_registry.getMaledictionCurseForCard(card) then
                if deck.discard and action.discardDraw ~= false then
                    deck:discard(card)
                end
                return card, true
            elseif deck.discard then
                deck:discard(card)
            end
        end

        return nil, true
    end

    local function validateMalediction(action, target, resolver)
        if not target then
            return false, "Malediction needs a creature target.", "spell_target_missing"
        end
        if not isCreatureSpellTarget(target) then
            return false, "Malediction can only curse creatures.", "malediction_target_not_creature"
        end
        if target.malediction and target.malediction.active ~= false then
            return false, "That target is already under Malediction.", "malediction_already_active"
        end

        local explicit = getExplicitMaledictionCard(action) or getMaledictionCardFromValue(action)
        if explicit and not spell_registry.getMaledictionCurseForCard(explicit) then
            return false, "Malediction needs a minor arcana curse-table card.", "malediction_card_invalid"
        end
        local deck = getMaledictionDeck(resolver, action)
        if not explicit and (not deck or not deck.draw) then
            return false, "Malediction needs a curse-table draw.", "malediction_draw_missing"
        end

        return true, nil, nil
    end

    local function storePreviousValue(list, key, value)
        list[#list + 1] = {
            key = key,
            value = value,
        }
    end

    local function applyMaledictionCurse(actor, target, spell, card, curse)
        local state = {
            caster = actor,
            casterId = spellEntityKey(actor),
            target = target,
            targetId = spellEntityKey(target),
            spellId = spell and spell.id or "malediction",
            active = true,
            concentration = false,
            noConcentration = true,
            resolveNeverRefreshesWhileActive = true,
            nonRecoverable = true,
            cannotRecover = true,
            canBeDismissedByCaster = true,
            canBeCounterspelled = true,
            curse = curse,
            curseId = curse.id,
            curseName = curse.name,
            curseRank = curse.rank,
            curseCard = card,
            metadata = curse.metadata or {},
            previousFields = {},
            previousConditions = {},
            previousNonRecoverableConditions = {},
            hadPreviousMalediction = target.malediction ~= nil,
            previousMalediction = target.malediction,
        }

        target.conditions = target.conditions or {}
        storePreviousValue(state.previousConditions, "maledicted", target.conditions.maledicted)
        target.conditions.maledicted = true

        for condition, value in pairs(curse.conditions or {}) do
            storePreviousValue(state.previousConditions, condition, target.conditions[condition])
            target.conditions[condition] = value
        end

        local function setField(key, value)
            storePreviousValue(state.previousFields, key, target[key])
            target[key] = value
        end

        setField("maledictedBy", actor)
        setField("maledictionCurseId", curse.id)
        setField("maledictionCurseRank", curse.rank)
        for key, value in pairs(curse.flags or {}) do
            setField(key, value)
        end

        if curse.nonRecoverableConditions then
            target.nonRecoverableConditions = target.nonRecoverableConditions or {}
            for condition, value in pairs(curse.nonRecoverableConditions) do
                storePreviousValue(state.previousNonRecoverableConditions, condition,
                    target.nonRecoverableConditions[condition])
                target.nonRecoverableConditions[condition] = value
            end
        end

        target.malediction = state
        return state
    end

    local function isCharmImmune(target)
        if not target then
            return true
        end
        local conditions = target.conditions or {}
        return isInspirationImmuneTarget(target) or target.illusionImmune == true or
            target.immuneToIllusions == true or conditions.illusionImmune == true or
            hasTag(target, "illusion_immune")
    end

    local function isEmotionlessSpellTarget(target)
        if not target then
            return true
        end
        local conditions = target.conditions or {}
        return target.emotionless == true or target.noEmotions == true or conditions.emotionless == true or
            hasTag(target, "emotionless") or hasTag(target, "mindless")
    end

    local function isAnimalSpellTarget(target)
        if not target then
            return false
        end
        return target.animal == true or target.creatureType == "animal" or target.kind == "animal" or
            target.type == "animal" or hasTag(target, "animal")
    end

    local function getTotemDeck(resolver, action)
        action = action or {}
        return action.totemDeck or action.deck or resolver.playerDeck
    end

    local function hasExplicitTotemSource(action, target)
        action = action or {}
        return action.totemAnimal or action.totem or action.totemName or action.soulTotemAnimal or
            action.totemCard or action.randomTotemCard or action.drawnTotemCard or
            (target and (target.soulTotemAnimal or target.totemAnimal))
    end

    local function validateTotem(action, target, resolver)
        if not target then
            return false, "Totem needs a creature target.", "spell_target_missing"
        end
        if isSpellObjectTarget(target) then
            return false, "Totem can only transform creatures.", "totem_target_not_creature"
        end
        if target.totemForm and target.totemForm.active ~= false then
            return false, "That target is already in Totem form.", "totem_already_active"
        end
        local explicitCard = action and (action.totemCard or action.randomTotemCard or action.drawnTotemCard)
        if explicitCard and not spell_registry.getTotemForCard(explicitCard) then
            return false, "Totem random determination needs a minor arcana chart card.", "totem_card_invalid"
        end
        if not hasExplicitTotemSource(action, target) and not getTotemDeck(resolver, action) then
            return false, "Totem needs a known soul totem or a random totem draw.", "totem_missing"
        end
        return true, nil, nil
    end

    local function drawRandomTotemCard(resolver, action)
        local deck = getTotemDeck(resolver, action)
        if not deck or not deck.draw then
            return nil, false
        end

        for _ = 1, 80 do
            local card = deck:draw()
            if not card then
                return nil, true
            end
            if spell_registry.getTotemForCard(card) then
                if deck.discard then
                    deck:discard(card)
                end
                return card, true
            elseif deck.discard then
                deck:discard(card)
            end
        end

        return nil, true
    end

    local function resolveTotemAnimal(resolver, action, target)
        action = action or {}
        local chosen = action.totemAnimal or action.totem or action.totemName or action.soulTotemAnimal or
            (target and (target.soulTotemAnimal or target.totemAnimal))
        if chosen then
            return tostring(chosen), nil, false, nil
        end

        local card = action.totemCard or action.randomTotemCard or action.drawnTotemCard
        local drawnFromDeck = false
        if not card then
            card, drawnFromDeck = drawRandomTotemCard(resolver, action)
        end
        if not card then
            return nil, nil, drawnFromDeck, "totem_card_missing"
        end

        local totemAnimal = spell_registry.getTotemForCard(card)
        if not totemAnimal then
            return nil, card, drawnFromDeck, "totem_card_invalid"
        end

        return totemAnimal, card, drawnFromDeck, nil
    end

    local function collectTotemKnownFor(action, target)
        local knownFor = {}
        local knownForSet = {}
        local function add(value)
            local tag = normalizeTotemTag(value)
            if tag ~= "" and not knownForSet[tag] then
                knownForSet[tag] = true
                knownFor[#knownFor + 1] = tag
            end
        end

        local function collect(source)
            if type(source) == "table" then
                for _, value in ipairs(source) do
                    add(value)
                end
                for key, value in pairs(source) do
                    if type(key) ~= "number" and value then
                        add(key)
                    end
                end
            else
                add(source)
            end
        end

        collect(target and target.totemKnownFor)
        collect(action and (action.totemKnownFor or action.knownFor or action.totemActions))
        return knownFor, knownForSet
    end

    local function captureTotemAttributes(target)
        local attrs = target.attributes or {}
        return {
            swords = target.swords,
            pentacles = target.pentacles,
            cups = target.cups,
            wands = target.wands,
            attributes = {
                [constants.SUITS.SWORDS] = attrs[constants.SUITS.SWORDS],
                [constants.SUITS.PENTACLES] = attrs[constants.SUITS.PENTACLES],
                [constants.SUITS.CUPS] = attrs[constants.SUITS.CUPS],
                [constants.SUITS.WANDS] = attrs[constants.SUITS.WANDS],
            },
        }
    end

    local function setTotemAttributes(target, value)
        target.attributes = target.attributes or {}
        target.swords = value
        target.pentacles = value
        target.cups = value
        target.wands = value
        target.attributes[constants.SUITS.SWORDS] = value
        target.attributes[constants.SUITS.PENTACLES] = value
        target.attributes[constants.SUITS.CUPS] = value
        target.attributes[constants.SUITS.WANDS] = value
    end

    restoreTotemAttributes = function(target, previous)
        if not target or not previous then
            return
        end

        target.attributes = target.attributes or {}
        target.swords = previous.swords
        target.pentacles = previous.pentacles
        target.cups = previous.cups
        target.wands = previous.wands
        for suit, value in pairs(previous.attributes or {}) do
            target.attributes[suit] = value
        end
    end

    appendDroppedItems = function(target, items)
        if not target or type(items) ~= "table" or #items == 0 then
            return
        end
        target.droppedItems = target.droppedItems or {}
        for _, item in ipairs(items) do
            target.droppedItems[#target.droppedItems + 1] = item
        end
    end

    local function removeInventoryItem(entity, item)
        if not entity or not item or not item.id or not entity.inventory or not entity.inventory.removeItem then
            return nil
        end
        return entity.inventory:removeItem(item.id)
    end

    local function dropTotemGear(target)
        local dropped = {}
        local inventory = target and target.inventory
        if not inventory or not inventory.getAllItems or not inventory.removeItem then
            return dropped
        end

        for _, entry in ipairs(inventory:getAllItems()) do
            local item = entry.item
            if item and item.id then
                local removed = inventory:removeItem(item.id)
                if removed then
                    dropped[#dropped + 1] = removed
                end
            end
        end

        appendDroppedItems(target, dropped)
        return dropped
    end

    function resolver:applyTotemForm(actor, target, action, spell, component)
        local totemAnimal, totemCard, drawnFromDeck, reason = resolveTotemAnimal(self, action, target)
        if not totemAnimal then
            return nil, reason or "totem_missing"
        end

        local knownFor, knownForSet = collectTotemKnownFor(action, target)
        local mouthComponent = removeInventoryItem(actor, component) or component
        local droppedItems = dropTotemGear(target)
        local previousAttributes = captureTotemAttributes(target)

        target.conditions = target.conditions or {}
        target.conditions.totemForm = true
        target.soulTotemAnimal = target.soulTotemAnimal or totemAnimal
        target.totemAnimal = target.soulTotemAnimal
        target.inTotemForm = true
        target.mouthOccupiedByTotem = true
        local previousCanSpeak = target.canSpeak
        target.canSpeak = false
        setTotemAttributes(target, 0)

        target.totemForm = {
            spellId = spell and spell.id or "totem",
            caster = actor,
            casterId = spellEntityKey(actor),
            target = target,
            targetId = spellEntityKey(target),
            active = true,
            animal = target.soulTotemAnimal,
            totemAnimal = target.soulTotemAnimal,
            totemCard = totemCard,
            drawnFromDeck = drawnFromDeck,
            attributesSetToZero = true,
            testOfFateBonus = 5,
            knownFor = knownFor,
            knownForSet = knownForSet,
            droppedItems = droppedItems,
            component = mouthComponent,
            componentInMouth = true,
            previousAttributes = previousAttributes,
            previousCanSpeak = previousCanSpeak,
            endsOnMouthUse = true,
        }

        return target.totemForm
    end

    function resolver:endTotemForMouthAction(target, mouthAction, opts)
        opts = opts or {}
        local totemForm = target and target.totemForm
        if not totemForm or totemForm.active == false then
            return {
                success = false,
                effects = { "totem_missing" },
            }
        end

        local reason = "totem_mouth_" .. normalizeTotemTag(mouthAction or opts.action or "used")
        local ended = self:endOngoingSpell(totemForm.caster, {
            spellId = "totem",
            target = target,
        }, reason, {
            source = opts.source,
        })

        return {
            success = true,
            endedSpell = ended,
            effects = { "totem_ended" },
        }
    end

    local function getControlOrderText(action)
        action = action or {}
        return action.controlOrder or action.order or action.commandText or action.command or action.instruction
    end

    local function countControlOrderWords(orderText)
        if type(orderText) ~= "string" then
            return 0
        end

        local count = 0
        for _ in string.gmatch(orderText, "%S+") do
            count = count + 1
        end
        return count
    end

    local function getAnimateObjectOrderText(action)
        action = action or {}
        return action.animateOrder or action.objectOrder or action.order or action.commandText or action.command or
            action.instruction
    end

    local function isAnimatedObjectWeapon(target)
        if not target then
            return false
        end
        local props = target.properties or {}
        return target.weaponType ~= nil or target.isWeapon == true or props.weapon == true or
            props.isWeapon == true or hasTag(target, "weapon")
    end

    local function validateAnimateObject(action, spell, resolveSpent, target)
        if not target then
            return false, "Animate Object needs an object target.", "spell_target_missing"
        end
        if not isSpellObjectTarget(target) then
            return false, "Animate Object can only target objects.", "animate_object_target_not_object"
        end
        if target.animatedObject and target.animatedObject.active ~= false then
            return false, "That object is already animated.", "animate_object_already_active"
        end

        local orderText = getAnimateObjectOrderText(action)
        local wordCount = countControlOrderWords(orderText)
        if wordCount < 1 then
            return false, "Animate Object needs a command.", "animate_object_order_missing"
        end

        local maxWords = ((action and action.actor and action.actor.wands) or 0) * (resolveSpent or 1)
        if wordCount > maxWords then
            return false, (spell and spell.name or "Animate Object") ..
                " order is too long for the Resolve spent.", "animate_object_order_too_long"
        end

        return true, nil, nil, orderText, maxWords, wordCount
    end

    function resolver:resolveAnimatedObjectTask(object, opts)
        opts = opts or {}
        local animation = object and object.animatedObject
        if not animation or animation.active == false then
            return {
                success = false,
                effects = { "animate_object_missing" },
            }
        end
        if animation.taskFulfilled then
            return {
                success = false,
                effects = { "animate_object_task_already_fulfilled" },
                animatedObject = animation,
            }
        end

        animation.taskFulfilled = true
        animation.fulfilledTask = opts.task or opts.description or animation.orderText
        animation.fulfilledInChallenge = opts.inChallenge == true or opts.challenge == true
        local taskResult = {
            success = true,
            animatedObject = animation,
            actionValue = animation.actionValue,
            value = animation.actionValue,
            effects = { "animate_object_task_fulfilled" },
        }
        if animation.unattendedWeaponOneStrike then
            taskResult.effects[#taskResult.effects + 1] = "animate_object_weapon_strike"
        end

        taskResult.endedSpell = self:endOngoingSpell(animation.caster, animation.spellEntry or {
            spellId = "animate_object",
            target = object,
        }, "animated_object_task_fulfilled", {
            source = opts.source,
        })

        return taskResult
    end

    local function scryLocationRef(action)
        action = action or {}
        return action.scryLocation or action.targetLocation or action.location or action.locationRef or
            action.locationId or action.room or action.roomId
    end

    local function scryLocationId(locationRef)
        if type(locationRef) == "table" then
            return locationRef.id or locationRef.locationId or locationRef.roomId or locationRef.name
        end
        return locationRef
    end

    local function scryLocationName(locationRef, locationId)
        if type(locationRef) == "table" then
            return locationRef.name or locationRef.title or locationId
        end
        return locationId
    end

    local function scryLocationArea(action, locationRef)
        action = action or {}
        if action.targetArea or action.locationArea or action.targetMetaphysicalArea then
            return action.targetArea or action.locationArea or action.targetMetaphysicalArea
        end
        if type(locationRef) == "table" then
            return locationRef.metaphysicalArea or locationRef.area or locationRef.region or locationRef.dungeonLevel or
                locationRef.city or locationRef.forest
        end
        return nil
    end

    local function scryCurrentArea(action, actor)
        action = action or {}
        if action.currentArea or action.metaphysicalArea or action.currentMetaphysicalArea then
            return action.currentArea or action.metaphysicalArea or action.currentMetaphysicalArea
        end
        local currentLocation = action.currentLocation or action.actorLocation
        if type(currentLocation) == "table" then
            return currentLocation.metaphysicalArea or currentLocation.area or currentLocation.region or
                currentLocation.dungeonLevel or currentLocation.city or currentLocation.forest
        end
        if actor then
            return actor.metaphysicalArea or actor.currentMetaphysicalArea or actor.area or actor.region or
                actor.dungeonLevel or actor.city or actor.forest
        end
        return nil
    end

    local function visitedLocationMatches(candidate, locationId)
        if not candidate or not locationId then
            return false
        end
        if type(candidate) == "table" then
            if candidate.visited == false then
                return false
            end
            candidate = candidate.id or candidate.locationId or candidate.roomId or candidate.name
        end
        return normalizeSpellKey(candidate) == normalizeSpellKey(locationId)
    end

    local function actorVisitedScryLocation(actor, action, locationRef, locationId)
        action = action or {}
        if action.visited == true or action.locationVisited == true then
            return true
        end
        if type(locationRef) == "table" and locationRef.visited == true then
            return true
        end
        local visited = (actor and (actor.visitedLocations or actor.visitedLocationIds or actor.visitedRooms)) or {}
        if type(visited) ~= "table" then
            return false
        end
        for key, value in pairs(visited) do
            if value == true and visitedLocationMatches(key, locationId) then
                return true
            end
            if visitedLocationMatches(value, locationId) then
                return true
            end
        end
        return false
    end

    local function validateScry(action, resolveSpent, actor)
        local locationRef = scryLocationRef(action)
        local locationId = scryLocationId(locationRef)
        if not locationId then
            return false, "Scry needs a location to view.", "scry_location_missing"
        end
        if not actorVisitedScryLocation(actor, action, locationRef, locationId) then
            return false, "Scry can only view locations the sorcerer has visited.", "scry_location_unvisited"
        end

        local currentArea = scryCurrentArea(action, actor)
        local targetArea = scryLocationArea(action, locationRef)
        local outsideArea = action and (action.outsideArea == true or action.crossArea == true or
            action.differentMetaphysicalArea == true or action.sameMetaphysicalArea == false)
        if currentArea and targetArea and normalizeSpellKey(currentArea) ~= normalizeSpellKey(targetArea) then
            outsideArea = true
        end
        if outsideArea and (resolveSpent or 1) < 2 then
            return false, "Scry needs +1 Resolve to view outside the current metaphysical area.",
                "scry_area_resolve_missing"
        end

        return true, nil, nil, {
            location = locationRef,
            locationId = locationId,
            locationName = scryLocationName(locationRef, locationId),
            currentArea = currentArea,
            targetArea = targetArea,
            outsideArea = outsideArea == true,
        }
    end

    local function validateControlSpell(action, spell, resolveSpent, target)
        local effect = spell and spell.effect or {}
        if not target then
            return false, "No target for " .. (spell and spell.name or "spell") .. ".", "spell_target_missing"
        end

        if effect.targetTrait == "animal" and not isAnimalSpellTarget(target) then
            return false, (spell.name or "Control") .. " can only control animals.", "control_target_not_animal"
        end
        if effect.targetTrait == "undead" and not isUndeadTarget(target) then
            return false, (spell.name or "Control") .. " can only control undead.", "control_target_not_undead"
        end
        if isControlImmuneTarget(target) then
            return false, (spell.name or "Control") .. " has no effect on control-immune targets.",
                "control_immune"
        end

        local orderText = getControlOrderText(action)
        local maxWords = ((action and action.actor and action.actor.wands) or 0) * (resolveSpent or 1)
        local wordCount = countControlOrderWords(orderText)
        if wordCount > 0 and wordCount > maxWords then
            return false, (spell.name or "Control") .. " order is too long for the Resolve spent.", "control_order_too_long"
        end
        if effect.targetTrait == "animal" and isObviouslySuicidalControlOrder(action, orderText) then
            return false, (spell.name or "Control") .. " cannot force animals to obey obviously suicidal orders.",
                "control_animal_suicidal_order"
        end

        return true, nil, nil, orderText, maxWords, wordCount
    end

    local function getAuguryDeck(self, action)
        action = action or {}
        return action.auguryDeck or action.testDeck or action.deck or self.playerDeck
    end

    local function getAuguryCard(self, action)
        action = action or {}
        if action.auguryCard or action.fateCard or action.cardToRead then
            return action.auguryCard or action.fateCard or action.cardToRead, false
        end

        local deck = getAuguryDeck(self, action)
        if deck and deck.draw then
            return deck:draw(), true
        end

        return nil, false
    end

    local function auguryParableForCard(card)
        if not card then
            return "The Codex Sophia offers no readable omen."
        end

        local name = card.name or "an unknown card"
        local suitImage = "an uncertain sign"
        if card.suit == constants.SUITS.SWORDS then
            suitImage = "a blade and a wound"
        elseif card.suit == constants.SUITS.PENTACLES then
            suitImage = "a locked gate and a careful hand"
        elseif card.suit == constants.SUITS.CUPS then
            suitImage = "a cup passed between wary friends"
        elseif card.suit == constants.SUITS.WANDS then
            suitImage = "a wand raised beneath strange stars"
        end

        return "The Codex Sophia opens to " .. name .. ": " .. suitImage .. "."
    end

    local function getTestAttributeValue(entity, attribute)
        if type(attribute) == "number" then
            return attribute
        end
        if type(attribute) == "string" and entity and type(entity[attribute]) == "number" then
            return entity[attribute]
        end
        return 2
    end

    function resolver:createAugury(actor, action, spell, resolveSpent)
        local card, drawnFromDeck = getAuguryCard(self, action)
        if not card then
            return nil, "Augury needs a fate card to read.", "augury_card_missing"
        end

        action = action or {}
        actor._auguryCounter = (actor._auguryCounter or 0) + 1
        local augury = {
            id = action.auguryId or ("augury_" .. tostring(actor.id or actor.name or "caster") .. "_" ..
                tostring(actor._auguryCounter)),
            spellId = spell and spell.id or "augury",
            caster = actor,
            casterId = actor and (actor.id or actor.name),
            card = card,
            cardHidden = true,
            drawnFromDeck = drawnFromDeck,
            parable = action.parable or auguryParableForCard(card),
            testAttribute = action.testAttribute or action.attribute or action.fateAttribute,
            targetSuit = action.targetSuit or action.testSuit,
            task = action.task or action.description or action.auguryTask,
            resolveSpent = resolveSpent or 1,
            canAttempt = true,
            canSpendResolveForFavor = true,
            canPushFate = true,
            boundByFate = true,
            declined = false,
            revealed = false,
            resolved = false,
        }

        actor.pendingAuguries = actor.pendingAuguries or {}
        actor.pendingAuguries[#actor.pendingAuguries + 1] = augury
        actor.pendingAugury = augury
        return augury, nil, nil
    end

    local function removePendingAugury(actor, augury)
        if not actor or not augury then
            return
        end
        if actor.pendingAugury == augury then
            actor.pendingAugury = nil
        end
        if actor.pendingAuguries then
            for index = #actor.pendingAuguries, 1, -1 do
                if actor.pendingAuguries[index] == augury then
                    table.remove(actor.pendingAuguries, index)
                end
            end
        end
    end

    function resolver:resolveAuguryAttempt(augury, actor, opts)
        opts = opts or {}
        actor = actor or (augury and augury.caster)
        if not augury or not augury.card then
            return {
                success = false,
                reason = "augury_missing",
            }
        end

        local favor = opts.favor
        if opts.disfavor == true then
            favor = false
        end
        local spentResolveForFavor = false
        if opts.spendResolveForFavor or opts.resolveForFavor then
            local ok, reason = self:spendResolveForFavor(actor)
            if not ok then
                return {
                    success = false,
                    reason = reason or "resolve_missing",
                    effects = { "resolve_missing" },
                }
            end
            spentResolveForFavor = true
            if favor == false then
                favor = nil
            else
                favor = true
            end
        end

        local attribute = opts.attribute or opts.testAttribute or augury.testAttribute or "pentacles"
        local attributeValue = getTestAttributeValue(actor, attribute)
        local targetSuit = opts.targetSuit or opts.testSuit or augury.targetSuit
        local test = fate_resolver.resolveTest(attributeValue, targetSuit, augury.card, favor)

        augury.cardHidden = false
        augury.revealed = true
        augury.resolved = true
        augury.attemptedBy = actor
        augury.attemptResult = test
        augury.favor = favor
        augury.spentResolveForFavor = spentResolveForFavor
        removePendingAugury(augury.caster or actor, augury)

        return {
            success = true,
            augury = augury,
            card = augury.card,
            testResult = test,
            favor = favor,
            spentResolveForFavor = spentResolveForFavor,
            effects = { "augury_revealed" },
        }
    end

    function resolver:declineAugury(augury, opts)
        opts = opts or {}
        if not augury or not augury.card then
            return {
                success = false,
                reason = "augury_missing",
            }
        end

        local deck = opts.deck or getAuguryDeck(self, opts)
        if augury.drawnFromDeck and deck and deck.discard then
            deck:discard(augury.card)
        end

        augury.declined = true
        augury.resolved = true
        augury.cardHidden = false
        augury.boundOutcome = opts.boundOutcome
        removePendingAugury(augury.caster, augury)

        return {
            success = true,
            augury = augury,
            card = augury.card,
            boundByFate = true,
            effects = { "augury_declined", "bound_by_fate" },
        }
    end

    local function isSleepDangerousSituation(action)
        action = action or {}
        if action.tense == true or action.dangerous == true or action.inCombat == true or action.inChallenge == true or
           action.combat == true or action.challenge == true then
            return true
        end

        local controller = action.challengeController
        if controller and controller.isActive and controller:isActive() then
            return true
        end

        return false
    end

    function resolver:canSpeakWithAnimal(speaker, animal)
        local speech = speaker and speaker.speakToAnimal
        return speech ~= nil and speech.active ~= false and isAnimalSpellTarget(animal)
    end

    local function getThunderclapZoneId(action, actor)
        action = action or {}
        local zoneRef = action.zoneId or action.zone or action.targetZone or action.targetZoneId or
            (actor and (actor.zone or actor.zoneId))
        if type(zoneRef) == "table" then
            return zoneRef.id or zoneRef.name
        end
        return zoneRef
    end

    local function isCreatureSpellTarget(entity)
        return entity and not isSpellObjectTarget(entity) and
            (entity.takeWound or entity.isPC ~= nil or entity.npcHealth ~= nil or entity.health ~= nil or
                entity.conditions ~= nil)
    end

    local function validateChangeSize(action, target)
        if not target then
            return false, "Change Size needs a creature target.", "spell_target_missing"
        end
        if not isCreatureSpellTarget(target) then
            return false, "Change Size can only target creatures.", "change_size_target_not_creature"
        end
        local mode = getChangeSizeMode(action)
        if not mode then
            return false, "Change Size must either Grow or Shrink the target.", "change_size_mode_missing"
        end
        return true, nil, nil, mode
    end

    local function isLivingPlantTarget(target)
        local props = target and target.properties or {}
        return target and (target.livingPlant == true or target.plant == true or props.livingPlant == true or
            props.plant == true or hasTag(target, "plant") or hasTag(target, "living_plant"))
    end

    local function isWoodenObjectTarget(target)
        if not target or not isSpellObjectTarget(target) then
            return false
        end
        local props = target.properties or {}
        local material = normalizeSpellKey(target.material or props.material)
        return target.wood == true or target.wooden == true or props.wood == true or props.wooden == true or
            material == "wood" or material == "wooden" or hasTag(target, "wood") or hasTag(target, "wooden")
    end

    local function isWoodweaveRawMaterial(target)
        local props = target and target.properties or {}
        return isWoodenObjectTarget(target) or (target and (target.rawWood == true or props.rawWood == true or
            hasTag(target, "raw_wood")))
    end

    local function getWoodweaveMode(action, target)
        action = action or {}
        local mode = normalizeSpellKey(action.woodweaveMode or action.mode or action.effect or action.intent)
        if mode ~= "" then
            return mode
        end
        if action.rootZone or action.vegetationZone or action.zoneId or action.zone then
            return "root"
        end
        if action.rawMaterials or action.shape or action.shapeInto or action.objectName then
            return "shape"
        end
        if isLivingPlantTarget(target) then
            return action.shrink and "shrink" or "grow"
        end
        if isWoodenObjectTarget(target) then
            return "warp"
        end
        return ""
    end

    local function getWoodweaveZoneId(action, actor)
        action = action or {}
        local zoneRef = action.zoneId or action.zone or action.targetZone or action.vegetationZone or
            (actor and (actor.zone or actor.zoneId))
        if type(zoneRef) == "table" then
            return zoneRef.id or zoneRef.name
        end
        return zoneRef
    end

    local function collectWoodweaveZoneCreatures(action, zoneId)
        local creatures = {}
        for _, entity in ipairs((action and action.targets) or {}) do
            if isCreatureSpellTarget(entity) then
                creatures[#creatures + 1] = entity
            end
        end
        if #creatures > 0 then
            return creatures
        end

        for _, entity in ipairs((action and action.allEntities) or {}) do
            if entity and isCreatureSpellTarget(entity) and
               (not zoneId or entity.zone == zoneId or entity.zoneId == zoneId) then
                creatures[#creatures + 1] = entity
            end
        end
        return creatures
    end

    local function notchWoodweaveObject(target)
        if not target then
            return nil
        end
        if target.notches ~= nil or target.durability ~= nil then
            local inventory = require('logic.inventory')
            return inventory.addNotch(target)
        end
        target.notches = (target.notches or 0) + 1
        return "notched"
    end

    local function validateWoodweave(action, actor, target)
        local mode = getWoodweaveMode(action, target)
        if (mode == "grow" or mode == "shrink") and isLivingPlantTarget(target) then
            return true, nil, nil
        end
        if (mode == "warp" or mode == "notch") and isWoodenObjectTarget(target) then
            return true, nil, nil
        end
        if mode == "root" and (getWoodweaveZoneId(action, actor) or
           (action and type(action.targets) == "table" and #action.targets > 0)) then
            return true, nil, nil
        end
        if mode == "shape" then
            local rawMaterials = target or (action and action.rawMaterials)
            if isWoodweaveRawMaterial(rawMaterials) then
                if hasEquivalentWoodweaveShapeSize(rawMaterials, action) then
                    return true, nil, nil
                end
                return false, "Woodweave needs raw wooden materials of equivalent size.",
                    "woodweave_material_size_mismatch"
            end
        end
        return false, "Woodweave needs a living plant, wooden object, vegetation zone, or raw materials.",
            "woodweave_invalid_target"
    end

    local function collectThunderclapCreatures(action, actor, zoneId)
        local creatures = {}
        for _, entity in ipairs(action.allEntities or {}) do
            if entity and entity ~= actor and isCreatureSpellTarget(entity) and
               (not zoneId or entity.zone == zoneId or entity.zoneId == zoneId) then
                creatures[#creatures + 1] = entity
            end
        end
        return creatures
    end

    local function isThunderclapFragileObject(object)
        if not object then
            return false
        end
        local props = object.properties or {}
        return object.fragile == true or object.shatters == true or object.untemperedGlass == true or
            props.fragile == true or props.shatters == true or props.untemperedGlass == true or
            hasTag(object, "fragile") or hasTag(object, "glass") or hasTag(object, "porcelain")
    end

    local function collectThunderclapObjects(action, zoneId)
        local objects = {}

        local function addObjectsFrom(source)
            if type(source) == "table" then
                for _, object in ipairs(source) do
                    if object and (not zoneId or not object.zone or object.zone == zoneId or object.zoneId == zoneId) then
                        objects[#objects + 1] = object
                    end
                end
            end
        end

        addObjectsFrom(action.objects)
        addObjectsFrom(action.zoneObjects)
        addObjectsFrom(action.fragileObjects)
        addObjectsFrom(action.features)

        return objects
    end

    local function getThunderclapChoice(action, entity)
        action = action or {}
        local choices = action.thunderclapChoices or action.creatureChoices or {}
        local choice = nil
        if entity then
            choice = choices[entity.id] or choices[entity.name] or entity.thunderclapChoice
        end
        choice = normalizeSpellKey(choice)
        if choice == "drop" or choice == "drop_items" or choice == "cover_ears" or choice == "hold_ears" then
            return "drop"
        end
        return "endure"
    end

    function resolver:validateThunderclap(action, actor)
        local zoneId = getThunderclapZoneId(action, actor)
        if not zoneId then
            return false, "Thunderclap needs a visible zone.", "thunderclap_zone_missing"
        end
        return true, nil, nil, zoneId
    end

    function resolver:dropHeldItemsForThunderclap(entity)
        local dropped = {}
        if not entity then
            return dropped
        end

        if entity.inventory and entity.inventory.getItems then
            local handsItems = entity.inventory:getItems("hands") or {}
            for index = #handsItems, 1, -1 do
                local item = handsItems[index]
                if item then
                    dropped[#dropped + 1] = self:dropCarriedItem(entity, item, "thunderclap")
                end
            end
        elseif entity.weapon then
            dropped[#dropped + 1] = self:dropCarriedItem(entity, entity.weapon, "thunderclap")
        end

        return dropped
    end

    local function getCharmCloakedTarget(action)
        action = action or {}
        return action.cloakedTarget or action.illusionTarget or action.friendTarget or action.trustedTarget or
            action.secondaryTarget or action.targetFriend
    end

    local function getEmotionalIllusionCloakedTarget(action)
        action = action or {}
        return action.cloakedTarget or action.illusionTarget or action.fearedTarget or action.hatedTarget or
            action.friendTarget or action.trustedTarget or action.secondaryTarget or action.targetFriend
    end

    local function charmCloakedTargetIsWilling(action, cloakedTarget)
        if type(cloakedTarget) ~= "table" then
            return false
        end
        if cloakedTarget.willing == false or cloakedTarget.consent == false or cloakedTarget.charmWilling == false then
            return false
        end
        local consent = action and (action.cloakedTargetConsent or action.friendConsent or action.secondaryTargetConsent)
        if consent == false then
            return false
        end
        return true
    end

    local function emotionalIllusionCloakedTargetIsWilling(action, cloakedTarget)
        if type(cloakedTarget) ~= "table" then
            return false
        end
        if cloakedTarget.willing == false or cloakedTarget.consent == false or cloakedTarget.emotionalIllusionWilling == false then
            return false
        end
        local consent = action and (action.cloakedTargetConsent or action.illusionTargetConsent or
            action.secondaryTargetConsent)
        if consent == false then
            return false
        end
        return true
    end

    function resolver:validateGustOfWind(action, target)
        action = action or {}
        local destinationZone = getGustDestinationZone(action)
        if not target then
            return false, "Gust of Wind needs a target.", "spell_target_missing"
        end
        if not isHumanSizedSpellTarget(target) then
            return false, "Gust of Wind can only displace human-sized targets.", "gust_target_too_large"
        end
        if not destinationZone then
            return false, "Gust of Wind needs an adjacent destination zone.", "gust_destination_missing"
        end

        local fromZone = target.zone or target.zoneId or (action.actor and (action.actor.zone or action.actor.zoneId))
        if not fromZone then
            return false, "Gust of Wind needs the target's current zone.", "gust_origin_missing"
        end

        local canMove, moveError = self:canMoveBetweenZones(action, fromZone, destinationZone, { maxDistance = 1 })
        if not canMove then
            local effectName = moveError == "zone_not_found" and "zone_not_found" or "gust_destination_not_adjacent"
            return false, "Gust of Wind can only move a target to an adjacent zone.", effectName
        end

        return true, nil, nil, destinationZone, fromZone
    end

    local function bindingNameFromAction(action, target)
        action = action or {}
        return action.bindingName or action.namedCreature or action.creatureName or action.targetName or
            (target and target.name)
    end

    local function isBindingGeneric(action)
        action = action or {}
        return action.genericName == true or action.bindingGeneric == true or
            action.nameType == "generic" or action.bindingNameType == "generic"
    end

    local function bindingCandidateVisible(action, candidate)
        if not candidate then
            return false
        end
        if action and (action.includeHidden or action.ignoreVisibility) then
            return true
        end
        if candidate.visible == false or candidate.visibleToCaster == false or
           candidate.canBeSeen == false or candidate.hidden == true then
            return false
        end
        return true
    end

    local function bindingNameMatches(candidate, name, generic)
        if not candidate or not name then
            return false
        end

        local needle = normalizeSpellKey(name)
        if needle == "" then
            return false
        end

        if generic then
            local fields = {
                candidate.creatureType,
                candidate.kind,
                candidate.species,
                candidate.type,
                candidate.kin,
                candidate.archetype,
            }
            for _, field in ipairs(fields) do
                if normalizeSpellKey(field) == needle then
                    return true
                end
            end

            for _, tag in ipairs(candidate.tags or {}) do
                if normalizeSpellKey(tag) == needle then
                    return true
                end
            end

            return false
        end

        return normalizeSpellKey(candidate.name) == needle
    end

    local function addBindingCandidate(targets, seen, candidate)
        if type(candidate) ~= "table" then
            return
        end

        local key = candidate.id or candidate.name or tostring(candidate)
        if seen[key] then
            return
        end

        seen[key] = true
        targets[#targets + 1] = candidate
    end

    local function collectBindingTargets(action, target)
        action = action or {}
        local targets = {}
        local seen = {}
        local name = bindingNameFromAction(action, target)
        local generic = isBindingGeneric(action)
        local candidates = {}

        if type(action.targets) == "table" and #action.targets > 0 then
            for _, candidate in ipairs(action.targets) do
                candidates[#candidates + 1] = candidate
            end
        elseif type(action.allEntities) == "table" and #action.allEntities > 0 then
            for _, candidate in ipairs(action.allEntities) do
                candidates[#candidates + 1] = candidate
            end
        elseif target then
            candidates[#candidates + 1] = target
        end

        for _, candidate in ipairs(candidates) do
            if bindingCandidateVisible(action, candidate) and
               ((not name and candidate == target) or bindingNameMatches(candidate, name, generic)) then
                addBindingCandidate(targets, seen, candidate)
            end
        end

        if #targets == 0 and target and bindingCandidateVisible(action, target) then
            addBindingCandidate(targets, seen, target)
        end

        return targets, name, generic
    end

    local function entityRefKey(entity)
        if not entity then
            return nil
        end
        return entity.id or entity.name or tostring(entity)
    end

    local function addUniqueParty(parties, seen, party)
        if type(party) ~= "table" then
            return
        end

        local key = entityRefKey(party)
        if not key or seen[key] then
            return
        end

        seen[key] = true
        parties[#parties + 1] = party
    end

    local function collectPartiesFrom(value, parties, seen)
        if type(value) ~= "table" then
            return
        end

        if value.id or value.name or value.isPC ~= nil or value.takeWound then
            addUniqueParty(parties, seen, value)
            return
        end

        for _, party in ipairs(value) do
            addUniqueParty(parties, seen, party)
        end

        for key, party in pairs(value) do
            if type(key) ~= "number" then
                addUniqueParty(parties, seen, party)
            end
        end
    end

    local function collectSealPactParties(action, target)
        local parties = {}
        local seen = {}
        action = action or {}

        collectPartiesFrom(action.parties, parties, seen)
        collectPartiesFrom(action.partyTargets, parties, seen)
        collectPartiesFrom(action.targets, parties, seen)

        if #parties == 0 then
            addUniqueParty(parties, seen, target or action.target)
            addUniqueParty(parties, seen, action.secondaryTarget)
            addUniqueParty(parties, seen, action.partyA or action.firstParty or action.promisor)
            addUniqueParty(parties, seen, action.partyB or action.secondParty or action.promisee)
        end

        collectPartiesFrom(action.additionalParties, parties, seen)
        return parties
    end

    local function getConsentValue(consent, party)
        if type(consent) ~= "table" or not party then
            return nil
        end

        local key = entityRefKey(party)
        if consent[party] ~= nil then
            return consent[party]
        end
        if party.id and consent[party.id] ~= nil then
            return consent[party.id]
        end
        if party.name and consent[party.name] ~= nil then
            return consent[party.name]
        end
        if key and consent[key] ~= nil then
            return consent[key]
        end
        return nil
    end

    local function sealPactPartyIsWilling(action, party)
        if action and action.unwilling == true then
            return false
        end
        if not party then
            return false
        end

        local consent = getConsentValue(action and (action.partyConsent or action.consent or action.willingParties), party)
        if consent == false then
            return false
        end
        if party.willing == false or party.consent == false or party.sealPactWilling == false then
            return false
        end

        return true
    end

    local function validateSealPactParties(action, spell, resolveSpent, parties)
        local baseParties = spell and spell.baseParties or 2
        local extraPartyResolve = spell and spell.extraPartyResolve or 1
        local partyCount = #parties

        if partyCount < baseParties then
            return false, "Seal Pact requires at least two willing parties.", "seal_pact_parties_missing"
        end

        local requiredResolve = 1 + math.max(0, partyCount - baseParties) * extraPartyResolve
        if resolveSpent < requiredResolve then
            return false, "Seal Pact needs more Resolve for that many parties.", "seal_pact_too_many_parties"
        end

        for _, party in ipairs(parties) do
            if not sealPactPartyIsWilling(action, party) then
                return false, "Seal Pact requires willing parties.", "seal_pact_unwilling_party"
            end
        end

        return true, nil, nil
    end

    local function appendUniquePact(entity, field, pact)
        if not entity or not pact then
            return
        end

        entity[field] = entity[field] or {}
        for _, existing in ipairs(entity[field]) do
            if existing == pact or (existing.id and existing.id == pact.id) then
                return
            end
        end

        entity[field][#entity[field] + 1] = pact
    end

    local function recordSealPactAwareness(party, pact, opts)
        if not party or not pact then
            return nil
        end
        opts = opts or {}

        local awareness = {
            pact = pact,
            pactId = pact.id,
            reason = opts.reason,
            violator = opts.violator,
            violatorId = entityRefKey(opts.violator),
            dispeller = opts.dispeller,
            dispellerId = entityRefKey(opts.dispeller),
            dispelled = opts.dispelled == true,
            violated = opts.violated == true,
            timestamp = os.time(),
        }

        party.sealPactAwareness = party.sealPactAwareness or {}
        party.sealPactAwareness[#party.sealPactAwareness + 1] = awareness
        party.pactAwareness = party.pactAwareness or {}
        party.pactAwareness[#party.pactAwareness + 1] = awareness
        party.lastSealPactAwareness = awareness
        return awareness
    end

    function resolver:createSealedPact(actor, parties, action, spell, resolveSpent)
        action = action or {}
        spell = spell or {}

        if actor then
            actor._sealPactCounter = (actor._sealPactCounter or 0) + 1
        end

        local pactId = action.pactId or action.contractId or action.oathId
            or ("seal_pact_" .. tostring(entityRefKey(actor) or "caster") .. "_" .. tostring(actor and actor._sealPactCounter or os.time()))
        local pact = {
            id = pactId,
            spellId = spell.id or "seal_pact",
            name = action.pactName or action.oathName or action.contractName or "Sealed Pact",
            terms = action.terms or action.contract or action.oath,
            caster = actor,
            casterId = entityRefKey(actor),
            parties = {},
            partyIds = {},
            resolveSpent = resolveSpent,
            permanent = true,
            active = true,
            dispelled = false,
            violated = false,
            createdAt = os.time(),
        }

        for _, party in ipairs(parties or {}) do
            pact.parties[#pact.parties + 1] = party
            pact.partyIds[#pact.partyIds + 1] = entityRefKey(party)
            appendUniquePact(party, "sealedPacts", pact)
            appendUniquePact(party, "activeSealedPacts", pact)
        end

        appendUniquePact(actor, "sealedPacts", pact)
        appendUniquePact(actor, "activeSealedPacts", pact)

        self.eventBus:emit(events.EVENTS.SEALED_PACT_CREATED, {
            actor = actor,
            pact = pact,
            parties = pact.parties,
        })

        return pact
    end

    function resolver:findSealedPact(pactRef, entity)
        if type(pactRef) == "table" then
            return pactRef
        end
        if not pactRef or not entity then
            return nil
        end

        local pactId = tostring(pactRef)
        for _, pact in ipairs(entity.sealedPacts or {}) do
            if tostring(pact.id) == pactId then
                return pact
            end
        end
        for _, pact in ipairs(entity.activeSealedPacts or {}) do
            if tostring(pact.id) == pactId then
                return pact
            end
        end

        return nil
    end

    function resolver:violateSealedPact(pactRef, violator, opts)
        opts = opts or {}
        local pact = self:findSealedPact(pactRef, violator or opts.entity) or pactRef
        if type(pact) ~= "table" then
            return {
                success = false,
                reason = "sealed_pact_missing",
            }
        end

        local violation = {
            violator = violator,
            violatorId = entityRefKey(violator),
            reason = opts.reason or "pact_violated",
            timestamp = os.time(),
        }
        pact.violated = true
        pact.violation = violation

        if violator then
            violator.conditions = violator.conditions or {}
            violator.conditions.doomed = true
            violator.doomed = true
            local pending = {
                source = "seal_pact",
                pact = pact,
                pactId = pact.id,
                reason = violation.reason,
                result = "great_failure",
            }
            violator.pendingGreatFailure = pending
            violator.pendingSealPactGreatFailure = pending
            violator.pendingGreatFailures = violator.pendingGreatFailures or {}
            violator.pendingGreatFailures[#violator.pendingGreatFailures + 1] = pending
        end

        local awareness = {}
        local violatorKey = entityRefKey(violator)
        for _, party in ipairs(pact.parties or {}) do
            if entityRefKey(party) ~= violatorKey then
                local entry = recordSealPactAwareness(party, pact, {
                    reason = violation.reason,
                    violator = violator,
                    violated = true,
                })
                if entry then
                    awareness[#awareness + 1] = entry
                end
            end
        end

        local result = {
            success = true,
            pact = pact,
            violator = violator,
            violation = violation,
            awareness = awareness,
            doomed = violator,
        }

        self.eventBus:emit(events.EVENTS.SEALED_PACT_VIOLATED, result)
        return result
    end

    function resolver:dispelSealedPact(pactRef, opts)
        opts = opts or {}
        local dispeller = opts.dispeller or opts.actor
        local pact = self:findSealedPact(pactRef, opts.entity or dispeller) or pactRef
        if type(pact) ~= "table" then
            return {
                success = false,
                reason = "sealed_pact_missing",
            }
        end
        if pact.violated then
            pact.dispelBlockedByViolation = true
            return {
                success = false,
                reason = "sealed_pact_already_violated",
                effects = { "sealed_pact_consequences_irremovable" },
                pact = pact,
            }
        end

        pact.dispelled = true
        pact.active = false
        pact.dispelledBy = dispeller
        pact.dispelledById = entityRefKey(dispeller)
        pact.dispelReason = opts.reason or "dispelled"
        pact.dispelledAt = os.time()

        local awareness = {}
        local dispellerKey = entityRefKey(dispeller)
        for _, party in ipairs(pact.parties or {}) do
            if not dispeller or entityRefKey(party) ~= dispellerKey then
                local entry = recordSealPactAwareness(party, pact, {
                    reason = pact.dispelReason,
                    dispeller = dispeller,
                    dispelled = true,
                })
                if entry then
                    awareness[#awareness + 1] = entry
                end
            end
        end

        local result = {
            success = true,
            pact = pact,
            dispeller = dispeller,
            awareness = awareness,
        }

        self.eventBus:emit(events.EVENTS.SEALED_PACT_DISPELLED, result)
        return result
    end

    local function normalizeCloudZoneId(value)
        if type(value) == "table" then
            return value.id or value.zoneId or value.name
        end
        return value
    end

    local function makeZoneSet(zoneIds)
        local zoneSet = {}
        for _, zoneId in ipairs(zoneIds or {}) do
            if zoneId then
                zoneSet[zoneId] = true
            end
        end
        return zoneSet
    end

    local function collectStinkingCloudZoneIds(action, target, actor)
        local zoneIds = {}
        local zoneSet = {}

        local function addZone(zoneRef)
            local zoneId = normalizeCloudZoneId(zoneRef)
            if zoneId and not zoneSet[zoneId] then
                zoneSet[zoneId] = true
                zoneIds[#zoneIds + 1] = zoneId
            end
        end

        if type(action.zoneIds) == "table" then
            for _, zoneRef in ipairs(action.zoneIds) do
                addZone(zoneRef)
            end
        end

        addZone(action.zoneId or action.zone)
        if #zoneIds == 0 then
            addZone(target and (target.zoneId or target.zone))
            addZone(actor and (actor.zoneId or actor.zone))
        end

        return zoneIds, zoneSet
    end

    local function stinkingCloudBreathless(entity)
        if not entity then
            return false
        end

        local conditions = entity.conditions or {}
        if entity.noNeedToBreathe or entity.immuneToSuffocation or entity.doesNotBreathe or
           entity.breathless or entity.breathes == false or entity.breathing == false or
           conditions.noNeedToBreathe or conditions.immuneToSuffocation or conditions.breathless then
            return true
        end

        local tags = entity.tags or {}
        return tags.breathless == true or tags.construct == true or tags.undead == true or
            entity.construct == true or entity.undead == true
    end

    local function entityCloudZoneId(entity)
        return normalizeCloudZoneId(entity and (entity.zoneId or entity.zone))
    end

    local function isActiveStinkingCloudSpell(activeSpell)
        return activeSpell and activeSpell.spellId == "stinking_cloud" and activeSpell.ended ~= true and
            (not activeSpell.stinkingCloud or activeSpell.stinkingCloud.active ~= false)
    end

    function resolver:collectActiveStinkingClouds(combatants)
        local clouds = {}
        for _, entity in ipairs(combatants or {}) do
            for _, activeSpell in ipairs(entity.activeSpells or {}) do
                if isActiveStinkingCloudSpell(activeSpell) then
                    local cloud = activeSpell.stinkingCloud or activeSpell
                    cloud.spellEntry = activeSpell
                    clouds[#clouds + 1] = cloud
                end
            end
        end
        return clouds
    end

    function resolver:applyStinkingCloudRoundStart(context)
        context = context or {}
        local combatants = context.combatants or context.allEntities or
            (self.challengeController and self.challengeController.allCombatants) or {}
        local clouds = context.clouds or self:collectActiveStinkingClouds(combatants)
        local results = {}

        for _, entity in ipairs(combatants) do
            entity.stinkingCloudDrawPenalty = nil
        end

        for _, cloud in ipairs(clouds) do
            if cloud and cloud.active ~= false then
                cloud.zoneSet = cloud.zoneSet or makeZoneSet(cloud.zoneIds)
                cloud.exposureCounts = cloud.exposureCounts or {}

                local seen = {}
                for _, entity in ipairs(combatants) do
                    local entityId = spellEntityKey(entity)
                    local zoneId = entityCloudZoneId(entity)
                    if entityId and zoneId and cloud.zoneSet[zoneId] then
                        seen[entityId] = true
                        entity.conditions = entity.conditions or {}

                        local entry = {
                            cloud = cloud,
                            entity = entity,
                            zoneId = zoneId,
                        }

                        if stinkingCloudBreathless(entity) then
                            entry.immune = true
                            entity.conditions.stinkingCloudImmune = true
                        else
                            local stacks = (cloud.exposureCounts[entityId] or 0) + 1
                            cloud.exposureCounts[entityId] = stacks
                            local stunDiscard = self:applyStun(entity, { action = context })
                            entity.conditions.stinkingCloud = true
                            entity.stinkingCloudStacks = stacks
                            entity.stinkingCloudDrawPenalty = stacks

                            entry.stacks = stacks
                            entry.stunned = true
                            entry.stunDiscard = stunDiscard
                            entry.stunDiscardedCard = stunDiscard.card
                            entry.drawPenalty = stacks

                            if stacks >= 4 then
                                entity.conditions.knocked_out = true
                                entity.conditions.knockout = true
                                entry.knockedOut = true
                            end
                        end

                        results[#results + 1] = entry
                    elseif entityId then
                        cloud.exposureCounts[entityId] = nil
                    end
                end
            end
        end

        if #results > 0 then
            self.eventBus:emit("stinking_cloud_round_start", {
                round = context.round,
                results = results,
                clouds = clouds,
            })
        end

        return results
    end

    local function witheringUndeadKind(target)
        local kind = normalizeSpellKey(target and (target.undeadType or target.blueprintId or target.enemyType or target.type))
        if not kind and target and target.name then
            kind = normalizeSpellKey(target.name)
        end

        if kind and kind:find("zombie") then
            return "zombie"
        end
        if kind and kind:find("skeleton") then
            return "skeleton"
        end
        if kind and kind:find("wraith") then
            return "wraith"
        end

        return kind
    end

    local function applyWitheringSkeletonForm(target)
        local skeleton = entity_factory.createEntity("skeleton_brute", {
            name = target.name,
            location = target.location,
        })

        if skeleton then
            target.attributes = skeleton.attributes
            target.swords = skeleton.swords
            target.pentacles = skeleton.pentacles
            target.cups = skeleton.cups
            target.wands = skeleton.wands
            target.npcHealth = skeleton.npcHealth
            target.npcDefense = skeleton.npcDefense
            target.npcMaxHealth = skeleton.npcMaxHealth
            target.npcMaxDefense = skeleton.npcMaxDefense
            target.instantDestruction = skeleton.instantDestruction
            target.baseMorale = skeleton.baseMorale
            target.rank = skeleton.rank
            target.size = skeleton.size
            target.lesserDooms = skeleton.lesserDooms
            target.greaterDooms = skeleton.greaterDooms
            target.greaterDoom = skeleton.greaterDoom
        end

        target.blueprintId = "skeleton_brute"
        target.enemyType = "skeleton"
        target.undeadType = "skeleton"
        target.undead = true
        target.tags = { "undead", "skeleton" }
        target.aiTags = { "undead", "skeleton", "mindless" }
        target.conditions = target.conditions or {}
        target.conditions.terrible = true
        target.conditions.witheringTransformed = true
        target.witheringTransformation = {
            from = "zombie",
            to = "skeleton",
        }
    end

    local function applyWitheringWraithForm(target)
        target.blueprintId = "wraith"
        target.enemyType = "wraith"
        target.undeadType = "wraith"
        target.undead = true
        target.spirit = true
        target.wraith = true
        target.incorporeal = true
        target.tags = { "undead", "wraith", "spirit", "incorporeal" }
        target.aiTags = { "undead", "wraith", "spirit" }
        target.conditions = target.conditions or {}
        target.conditions.terrible = true
        target.conditions.witheringTransformed = true
        target.witheringTransformation = {
            from = "skeleton",
            to = "wraith",
        }
    end

    local function markWitheringAging(target)
        if not target then
            return nil
        end

        target.conditions = target.conditions or {}
        target.conditions.witheringAging = true
        target.conditions.magicallyAged = true
        target.witheringAging = {
            active = true,
            signs = {
                "grey_hair",
                "wrinkled_skin",
                "jaundiced_eyes",
                "liver_spots",
            },
            untilWoundHealed = true,
        }
        return target.witheringAging
    end

    local function getWitheringMaterial(target)
        local props = target and target.properties or {}
        return normalizeSpellKey(target and (target.material or target.substance or target.objectMaterial) or
            props.material or props.substance)
    end

    local function markWitheringObjectDecay(target)
        local props = target.properties or {}
        target.properties = props

        local material = getWitheringMaterial(target)
        local kind = normalizeSpellKey(target.type or target.itemType or target.name)

        if props.food or target.isRation or target.isFood or kind == "food" or kind == "ration" then
            target.rotted = true
            props.rotted = true
        elseif material == "iron" or material == "steel" or material == "metal" or kind == "chain" then
            target.rusted = true
            props.rusted = true
        elseif material == "wood" or material == "wooden" then
            target.moldy = true
            props.moldy = true
        end

        target.witheredBySpell = true
        props.witheredBySpell = true
    end

    function resolver:applySpellEffect(action, result, spell)
        local actor = action.actor
        local target = action.target
        local effect = spell and spell.effect or {}
        local resolveSpent = action.resolveSpent or 1

        if effect.type == "animate_object" then
            local valid, reason, effectName, orderText, maxWords, wordCount =
                validateAnimateObject(action, spell, resolveSpent, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return false
            end

            target.conditions = target.conditions or {}
            target.conditions.animatedObject = true
            target.animatedBy = actor
            target.animatedObject = {
                caster = actor,
                casterId = spellEntityKey(actor),
                target = target,
                targetId = target.id or target.name,
                spellId = spell.id,
                orderText = orderText,
                maxWords = maxWords,
                wordCount = wordCount,
                singleTask = true,
                taskFulfilled = false,
                intendedPurposeOnly = true,
                invisibleHand = true,
                actionValue = result.testValue,
                challengeActionValue = result.testValue,
                unattendedWeaponOneStrike = isAnimatedObjectWeapon(target),
                active = true,
            }

            result.animatedObject = target.animatedObject
            result.spellTargets = { target }
            result.effects[#result.effects + 1] = "animate_object"
            result.description = spell.name .. " animates " .. (target.name or "object") .. " for one task."
        elseif effect.type == "control" then
            local valid, reason, effectName, orderText, maxWords, wordCount =
                validateControlSpell(action, spell, resolveSpent, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return false
            end

            target.conditions = target.conditions or {}
            target.conditions.controlled = true
            target.controlledBy = actor
            target.controlWords = maxWords
            target.controlOrder = {
                text = orderText,
                wordCount = wordCount,
                maxWords = maxWords,
                spellId = spell.id,
                fulfilled = false,
            }
            target.controlCommandsRemaining = 1
            result.effects[#result.effects + 1] = "controlled"
            result.controlOrder = target.controlOrder
            result.description = spell.name .. " controls " .. (target.name or "target") .. "."
        elseif effect.type == "brainfever" then
            if not target then
                result.success = false
                result.description = "No target for " .. spell.name .. "."
                return false
            end

            if isEmotionlessSpellTarget(target) then
                result.skipOngoingSpell = true
                result.effects[#result.effects + 1] = "brainfever_no_effect"
                result.description = spell.name .. " has no effect on emotionless creatures."
                return true
            end

            target.conditions = target.conditions or {}
            target.conditions.brainfever = true
            target.conditions.enraged = true
            target.brainfever = {
                caster = actor,
                casterId = spellEntityKey(actor),
                spellId = spell.id,
                attackFavor = true,
                mustPlayLowestInitiative = true,
            }
            target.attackFavorFromBrainfever = true
            target.mustPlayLowestInitiative = true
            result.effects[#result.effects + 1] = "brainfever"
            result.description = spell.name .. " drives " .. (target.name or "target") .. " into a rage."
        elseif effect.type == "necromancy" then
            local valid, reason, effectName = validateNecromancy(action, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return false
            end

            target.conditions = target.conditions or {}
            target.conditions.necromancy = true
            target.conditions.speaksWithDead = true
            target.canSpeakWhileDead = true
            target.speaksAsIfAlive = true
            target.necromancy = {
                caster = actor,
                casterId = spellEntityKey(actor),
                target = target,
                targetId = spellEntityKey(target),
                spellId = spell.id,
                active = true,
                concentration = true,
                componentInSkull = true,
                speaksAsIfAlive = true,
                noCompulsion = true,
                notGuaranteedHelpful = true,
                notGuaranteedTruthful = true,
                canBargainNormally = true,
                likelyConcerns = {
                    "unfinished_business",
                    "revenge",
                    "farewell",
                    "sundry_tasks",
                },
            }

            result.necromancy = target.necromancy
            result.spellTargets = { target }
            result.effects[#result.effects + 1] = "necromancy"
            result.description = spell.name .. " lets " .. (target.name or "the dead") .. " speak as if alive."
        elseif effect.type == "raise_zombie" then
            local valid, reason, effectName = validateRaiseZombie(action, target, resolveSpent)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return false
            end

            local zombie, raiseReason = createRaisedZombie(actor, target, action, spell, resolveSpent)
            if not zombie then
                result.success = false
                result.description = "Raise Zombie failed: " .. tostring(raiseReason or "zombie unavailable") .. "."
                result.effects[#result.effects + 1] = "raise_zombie_failed"
                return false
            end

            result.raisedZombie = zombie
            result.spellTargets = { zombie }
            result.effects[#result.effects + 1] = "raise_zombie"
            result.effects[#result.effects + 1] = "bound_zombie_created"
            result.description = spell.name .. " binds " .. (zombie.name or "a zombie") ..
                " for " .. tostring(zombie.zombieServicesRemaining or 0) .. " service(s)."
        elseif effect.type == "fleshcraft" then
            local valid, reason, effectName = validateFleshcraft(action, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return false
            end

            local fleshcraft = applyFleshcraft(actor, target, action, spell)
            result.fleshcraft = fleshcraft
            result.spellTargets = { target }
            result.effects[#result.effects + 1] = "fleshcraft"
            result.effects[#result.effects + 1] = "fleshcraft_" .. fleshcraft.bodyPart
            result.description = spell.name .. " detaches " .. (target.name or "the sorcerer") ..
                "'s " .. fleshcraft.bodyPart .. "."
        elseif effect.type == "malediction" then
            local valid, reason, effectName = validateMalediction(action, target, self)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return false
            end

            local curseCard, drawnFromDeck = self:getMaledictionDraw(action)
            local curse = spell_registry.getMaledictionCurseForCard(curseCard)
            if not curse then
                result.success = false
                result.description = "Malediction could not draw a curse-table card."
                result.effects[#result.effects + 1] = "malediction_draw_missing"
                return false
            end

            local malediction = applyMaledictionCurse(actor, target, spell, curseCard, curse)
            malediction.drawnFromDeck = drawnFromDeck
            result.malediction = malediction
            result.curse = curse
            result.curseCard = curseCard
            result.spellTargets = { target }
            result.effects[#result.effects + 1] = "malediction"
            result.effects[#result.effects + 1] = "malediction_curse_" .. curse.id
            result.description = spell.name .. " curses " .. (target.name or "target") .. " with " .. curse.name .. "."
        elseif effect.type == "augury" then
            local augury, reason, effectName = self:createAugury(actor, action, spell, resolveSpent)
            if not augury then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return false
            end

            result.augury = {
                id = augury.id,
                parable = augury.parable,
                cardHidden = true,
                canAttempt = true,
                canSpendResolveForFavor = true,
                canPushFate = true,
                boundByFate = true,
            }
            result.pendingAugury = augury
            result.effects[#result.effects + 1] = "augury_prepared"
            result.description = spell.name .. " prepares a hidden Test of Fate omen."
        elseif effect.type == "change_size" then
            local valid, reason, effectName, mode = validateChangeSize(action, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return false
            end

            local multiplier = mode == "grow" and 2 or 0.5
            target.conditions = target.conditions or {}
            target.conditions.sizeChanged = true
            target.conditions.sizeGrown = mode == "grow"
            target.conditions.sizeShrunk = mode == "shrink"
            target.changeSize = {
                caster = actor,
                casterId = spellEntityKey(actor),
                spellId = spell.id,
                active = true,
                concentration = true,
                mode = mode,
                heightMultiplier = multiplier,
                sizeMultiplier = multiplier,
                attackValuesUnaffected = true,
            }
            target.changedSizeBy = actor
            target.sizeMultiplier = multiplier
            target.heightMultiplier = multiplier
            target.sizeChanged = true

            result.changeSize = target.changeSize
            result.spellTargets = { target }
            result.effects[#result.effects + 1] = mode == "grow" and "size_grown" or "size_shrunk"
            result.description = spell.name .. " makes " .. (target.name or "target") ..
                (mode == "grow" and " grow." or " shrink.")
        elseif effect.type == "give_form_to_nothingness" then
            local valid, reason, effectName, rooms = validateGiveFormToNothingness(action, spell, resolveSpent, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return false
            end

            local affectedSubjects = {}
            for _, subject in ipairs(collectGiveFormSubjects(action, rooms)) do
                if subjectNeedsGiveForm(subject) then
                    affectedSubjects[#affectedSubjects + 1] = makeSubjectVisibleAndTangible(subject, actor, spell)
                end
            end

            local roomIds = {}
            for _, roomEntry in ipairs(rooms) do
                roomIds[#roomIds + 1] = roomEntry.id
            end

            local giveForm = {
                spellId = spell.id,
                caster = actor,
                casterId = spellEntityKey(actor),
                active = true,
                requiresContinuousDrum = true,
                component = result.component,
                resolveSpent = resolveSpent,
                rooms = rooms,
                roomIds = roomIds,
                affectedSubjects = affectedSubjects,
            }

            actor.activeGiveForms = actor.activeGiveForms or {}
            actor.activeGiveForms[#actor.activeGiveForms + 1] = giveForm

            result.giveForm = giveForm
            result.roomIds = roomIds
            result.zoneIds = roomIds
            result.zoneCount = #roomIds
            result.spellTargets = {}
            for _, record in ipairs(affectedSubjects) do
                result.spellTargets[#result.spellTargets + 1] = record.subject
            end
            result.effects[#result.effects + 1] = "give_form_to_nothingness"
            if #affectedSubjects > 0 then
                result.effects[#result.effects + 1] = "intangible_visible_tangible"
            else
                result.effects[#result.effects + 1] = "give_form_no_subjects"
            end
            result.description = spell.name .. " reveals and gives substance to " ..
                tostring(#affectedSubjects) .. " intangible or invisible subject(s)."
        elseif effect.type == "portable_hole" then
            local valid, reason, effectName, surface = validatePortableHole(action, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return false
            end

            local hole = createPortableHole(actor, surface, action, spell, result.component)
            result.portableHole = hole
            result.spellTargets = { surface }
            result.effects[#result.effects + 1] = "portable_hole"
            if hole.hasOtherSide then
                result.effects[#result.effects + 1] = "portable_hole_passage"
                result.description = spell.name .. " opens a passage through " ..
                    (surface.name or "the inanimate material") .. "."
            else
                result.effects[#result.effects + 1] = "portable_hole_blind_pocket"
                result.description = spell.name .. " opens a one-foot pocket in " ..
                    (surface.name or "the inanimate material") .. "."
            end
        elseif effect.type == "mirror_meld" then
            local valid, reason, effectName, mirror = mirrorMeld.validate(action, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return false
            end

            target = mirror
            action.target = mirror
            local meld = mirrorMeld.create(actor, mirror, action, spell, result.component)
            result.mirrorMeld = meld
            result.spellTargets = { mirror }
            result.effects[#result.effects + 1] = "mirror_meld"
            result.effects[#result.effects + 1] = "mirror_portal_open"
            result.description = spell.name .. " opens a mirror portal through " ..
                (mirror.name or "the mirror") .. "."
        elseif effect.type == "visual_illusion" then
            local valid, reason, effectName = validateVisualIllusion(action)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return false
            end

            local illusion = createVisualIllusion(actor, action, spell, result.component)
            result.visualIllusion = illusion
            result.effects[#result.effects + 1] = "visual_illusion"
            result.effects[#result.effects + 1] = "illusion_additive"
            result.description = spell.name .. " creates a visual-only " .. illusion.kind .. " image."
        elseif effect.type == "flare" then
            local item = action.item or target
            local zoneId = getFlareZoneId(action, actor, target)
            if isFlareCampfire(target, action) then
                local blinded = {}
                local unaffected = {}
                local incantationValue = result.testValue or result.cardValue or 0
                for _, creature in ipairs(collectFlareCampfireCreatures(action, zoneId)) do
                    local initiative = getFlareInitiative(action, creature)
                    if incantationValue > initiative then
                        creature.conditions = creature.conditions or {}
                        creature.conditions.blind = true
                        creature.conditions.blinded = true
                        creature.flareBlindUntil = "next_turn_end"
                        blinded[#blinded + 1] = creature
                    else
                        unaffected[#unaffected + 1] = creature
                    end
                end

                target.properties = target.properties or {}
                target.properties.flaredBySpell = true
                target.properties.extinguished = true
                target.properties.isLit = false
                target.properties.is_lit = false
                target.flared = true

                result.zoneId = zoneId
                result.flare = {
                    kind = "campfire",
                    zoneId = zoneId,
                    blinded = blinded,
                    unaffected = unaffected,
                    incantationValue = incantationValue,
                }
                result.spellTargets = { target }
                result.effects[#result.effects + 1] = "campfire_flared"
                if #blinded > 0 then
                    result.effects[#result.effects + 1] = "campfire_flash_blind"
                end
                result.description = spell.name .. " makes the campfire explode in a blinding flare."
            elseif item and getFlareLightKind(item) then
                item.properties = item.properties or {}
                local props = item.properties
                local kind = getFlareLightKind(item)

                props.isLit = false
                props.is_lit = false
                props.extinguished = true
                props.flaredBySpell = true
                item.flared = true
                result.lightSourceFlared = item
                result.spellTargets = { item }
                result.effects[#result.effects + 1] = "light_flared"
                result.effects[#result.effects + 1] = kind .. "_flared"

                if kind == "torch" then
                    item.destroyed = true
                    item.unrelightable = true
                    props.unrelightable = true
                    result.effects[#result.effects + 1] = "torch_spent"
                    self.eventBus:emit(events.EVENTS.LIGHT_DESTROYED, {
                        entity = inferFlareBearer(action, item),
                        item = item,
                        reason = "flare",
                    })
                else
                    item.relightable = true
                    props.relightable = true
                    self.eventBus:emit(events.EVENTS.LIGHT_EXTINGUISHED, {
                        entity = inferFlareBearer(action, item),
                        item = item,
                        reason = "flare",
                    })
                end

                local bearer = inferFlareBearer(action, item)
                if bearer and (kind == "torch" or kind == "lantern") then
                    bearer.conditions = bearer.conditions or {}
                    bearer.conditions.burning = true
                    bearer.conditions.onFire = true
                    result.bearer = bearer
                    result.effects[#result.effects + 1] = "bearer_catches_fire"
                    if bearer.takeWound then
                        self:applyDamage(bearer, 1, {}, nil, action.allEntities)
                        result.damageDealt = (result.damageDealt or 0) + 1
                    end
                end

                result.description = spell.name .. " makes " .. (item.name or "light") .. " flare and go out."
            elseif target then
                target.conditions = target.conditions or {}
                target.conditions.blind = true
                target.conditions.blinded = true
                target.flareBlindUntil = "next_turn_end"
                result.effects[#result.effects + 1] = "blind"
                result.description = spell.name .. " blinds " .. (target.name or "target") .. "."
            else
                result.description = spell.name .. " manifests."
            end
        elseif effect.type == "defy_depths" then
            local valid, reason, effectName, targets = validateDefyDepths(action, spell, resolveSpent, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return false
            end

            local targetResults = {}
            for _, depthsTarget in ipairs(targets) do
                local props = depthsTarget.properties
                depthsTarget.conditions = depthsTarget.conditions or {}
                depthsTarget.conditions.defyDepths = true

                local shipResolveCost = getDefyDepthsShipResolveCost(depthsTarget)
                local wasSunken = depthsTarget.sunken == true or depthsTarget.submerged == true
                depthsTarget.defyDepths = {
                    caster = actor,
                    casterId = actor and actor.id,
                    target = depthsTarget,
                    targetId = depthsTarget.id,
                    active = true,
                    concentration = true,
                    waterWalking = not isSpellObjectTarget(depthsTarget),
                    floatsOnWater = isSpellObjectTarget(depthsTarget),
                    shipResolveCost = shipResolveCost,
                    raisedFromDepths = wasSunken,
                }

                if isSpellObjectTarget(depthsTarget) then
                    depthsTarget.floatsOnWater = true
                    depthsTarget.floatingOnWater = true
                    depthsTarget.floating = true
                    depthsTarget.onWaterSurface = true
                    depthsTarget.submerged = false
                    depthsTarget.sunken = false
                    depthsTarget.raisedFromDepths = wasSunken
                    if props then
                        props.floatsOnWater = true
                        props.defyDepths = true
                    end
                else
                    depthsTarget.canWalkOnWater = true
                    depthsTarget.waterWalking = true
                end

                targetResults[#targetResults + 1] = depthsTarget.defyDepths
            end

            result.defyDepths = targetResults
            result.spellTargets = targets
            result.effects[#result.effects + 1] = "defy_depths"
            result.description = spell.name .. " lets " .. tostring(#targets) .. " target(s) defy the water."
        elseif effect.type == "gust_of_wind" then
            local valid, reason, effectName, destinationZone, fromZone = self:validateGustOfWind(action, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return false
            end

            if self.zoneSystem and target and target.id then
                local placed, err = self.zoneSystem:placeEntity(target.id, destinationZone)
                if not placed then
                    result.success = false
                    result.description = "Gust of Wind could not place the target in the destination zone."
                    result.effects[#result.effects + 1] = "zone_sync_failed"
                    if err then
                        result.effects[#result.effects + 1] = "zone_sync_error_" .. tostring(err)
                    end
                    return false
                end
            end

            target.zone = destinationZone
            target.zoneId = destinationZone
            target.conditions = target.conditions or {}
            target.conditions.displaced = true
            self:clearAllEngagements(target, action.allEntities)

            result.fromZone = fromZone
            result.destinationZone = destinationZone
            result.gustOfWind = {
                target = target,
                fromZone = fromZone,
                destinationZone = destinationZone,
                gentleLanding = true,
                hazardousDestinationStillApplies = true,
                selfTarget = target == actor,
            }
            result.effects[#result.effects + 1] = "gust_of_wind_displace"
            result.description = spell.name .. " carries " .. (target.name or "target") .. " to " .. tostring(destinationZone) .. "."

            self.eventBus:emit("entity_zone_changed", {
                entity = target,
                oldZone = fromZone,
                newZone = destinationZone,
                source = "gust_of_wind",
            })
        elseif effect.type == "protection_from_elements" then
            local valid, reason, effectName, targets, elements =
                validateProtectionFromElements(action, spell, resolveSpent, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return false
            end

            local _, elementSet = collectProtectionElements(action)
            if actor then
                actor._elementProtectionCounter = (actor._elementProtectionCounter or 0) + 1
            end
            local instanceId = "protection_from_elements_" ..
                tostring(actor and (actor.id or actor.name) or "caster") .. "_" ..
                tostring(actor and actor._elementProtectionCounter or os.time())

            for _, protectedTarget in ipairs(targets) do
                protectedTarget.conditions = protectedTarget.conditions or {}
                protectedTarget.elementProtections = protectedTarget.elementProtections or {}
                protectedTarget.elementProtections[instanceId] = {
                    id = instanceId,
                    spellId = spell.id,
                    caster = actor,
                    casterId = actor and actor.id,
                    elements = elements,
                    elementSet = elementSet,
                    active = true,
                    concentration = true,
                }
                protectedTarget.protectionFromElements = protectedTarget.elementProtections[instanceId]
                refreshElementProtectionFlags(protectedTarget)
            end

            result.elementProtectionInstanceId = instanceId
            result.spellTargets = targets
            result.protectedElements = elements
            result.elementProtectionSet = elementSet
            result.effects[#result.effects + 1] = "protection_from_elements"
            result.description = spell.name .. " protects " .. tostring(#targets) .. " target(s) from " ..
                tostring(#elements) .. " element(s)."
        elseif effect.type == "speak_to_animal" then
            local speaker = target or actor
            if not speaker then
                result.success = false
                result.description = "No speaker for " .. spell.name .. "."
                result.effects[#result.effects + 1] = "spell_target_missing"
                return false
            end

            speaker.conditions = speaker.conditions or {}
            speaker.conditions.speakToAnimal = true
            speaker.canSpeakWithAnimals = true
            speaker.speechGarbledBySpiderEgg = true
            speaker.speakToAnimal = {
                caster = actor,
                casterId = actor and actor.id,
                target = speaker,
                targetId = speaker.id,
                active = true,
                concentration = true,
                animalsGenerallyHelpfulTruthful = true,
                normalAnimalLimits = {
                    "food",
                    "mating",
                    "safety",
                },
            }

            result.speakToAnimal = speaker.speakToAnimal
            result.spellTargets = { speaker }
            result.effects[#result.effects + 1] = "speak_to_animal"
            result.description = spell.name .. " lets " .. (speaker.name or "the sorcerer") .. " speak with animals."
        elseif effect.type == "totem" then
            local totemTarget = target or actor
            local valid, reason, effectName = validateTotem(action, totemTarget, self)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return false
            end

            local totemForm, totemReason = self:applyTotemForm(actor, totemTarget, action, spell, result.component)
            if not totemForm then
                result.success = false
                result.description = "Totem could not determine a soul totem."
                result.effects[#result.effects + 1] = totemReason or "totem_missing"
                return false
            end

            result.totemForm = totemForm
            result.spellTargets = { totemTarget }
            result.droppedItems = totemForm.droppedItems
            result.effects[#result.effects + 1] = "totem_form"
            result.description = spell.name .. " transforms " .. (totemTarget.name or "target") ..
                " into their soul totem."
        elseif effect.type == "thunderclap" then
            local valid, reason, effectName, zoneId = self:validateThunderclap(action, actor)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return false
            end

            local shatteredObjects = {}
            for _, object in ipairs(collectThunderclapObjects(action, zoneId)) do
                if isThunderclapFragileObject(object) then
                    object.destroyed = true
                    object.shattered = true
                    object.shatteredBy = "thunderclap"
                    shatteredObjects[#shatteredObjects + 1] = object
                end
            end

            local creatureResults = {}
            local droppedItems = {}
            for _, creature in ipairs(collectThunderclapCreatures(action, actor, zoneId)) do
                local choice = getThunderclapChoice(action, creature)
                local entry = {
                    creature = creature,
                    choice = choice,
                }
                if choice == "drop" then
                    entry.droppedItems = self:dropHeldItemsForThunderclap(creature)
                    for _, item in ipairs(entry.droppedItems) do
                        droppedItems[#droppedItems + 1] = item
                    end
                    creature.conditions = creature.conditions or {}
                    creature.conditions.coveringEars = true
                else
                    creature.conditions = creature.conditions or {}
                    local stunDiscard = self:applyStun(creature, { action = action })
                    creature.conditions.deaf = true
                    creature.conditions.deafened = true
                    entry.stunned = true
                    entry.stunDiscard = stunDiscard
                    entry.stunDiscardedCard = stunDiscard.card
                    entry.deafened = true
                end
                creatureResults[#creatureResults + 1] = entry
            end

            result.zoneId = zoneId
            result.thunderclap = {
                zoneId = zoneId,
                creatures = creatureResults,
                shatteredObjects = shatteredObjects,
                droppedItems = droppedItems,
            }
            result.shatteredObjects = shatteredObjects
            result.droppedItems = droppedItems
            result.effects[#result.effects + 1] = "thunderclap"
            if #shatteredObjects > 0 then
                result.effects[#result.effects + 1] = "fragile_objects_shattered"
            end
            result.description = spell.name .. " resounds through " .. tostring(zoneId) .. "."
        elseif effect.type == "wall_of_elements" then
            local valid, reason, effectName, elements = validateWallOfElements(action, resolveSpent)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return false
            end

            local wall = self:createElementWall(actor, action, spell, resolveSpent, elements)
            result.elementWall = wall
            result.wallSections = wall.sections
            result.zoneId = wall.zoneId
            result.spellTargets = { wall }
            result.effects[#result.effects + 1] = "wall_of_elements"
            result.description = spell.name .. " raises " .. tostring(wall.sectionCount) ..
                " elemental wall section(s)."
        elseif effect.type == "woodweave" then
            local mode = getWoodweaveMode(action, target)
            local woodweave = {
                mode = mode,
                target = target,
            }

            if mode == "grow" and isLivingPlantTarget(target) then
                target.conditions = target.conditions or {}
                target.conditions.grown = true
                target.growthEffect = "grow"
                target.woodweave = { mode = "grow", caster = actor, spellId = spell.id }
                woodweave.result = "plant_grown"
                result.effects[#result.effects + 1] = "plant_grown"
                result.description = spell.name .. " makes " .. (target.name or "the plant") .. " grow rapidly."
            elseif mode == "shrink" and isLivingPlantTarget(target) then
                target.conditions = target.conditions or {}
                target.conditions.shrunk = true
                target.conditions.witheredToSeed = true
                target.growthEffect = "shrink"
                target.woodweave = { mode = "shrink", caster = actor, spellId = spell.id }
                woodweave.result = "plant_shrunk"
                result.effects[#result.effects + 1] = "plant_shrunk"
                result.description = spell.name .. " withers " .. (target.name or "the plant") .. " back toward seed."
            elseif (mode == "warp" or mode == "notch") and isWoodenObjectTarget(target) then
                local notchResult = notchWoodweaveObject(target)
                target.woodweaveWarped = true
                woodweave.result = notchResult
                result.itemNotchResult = notchResult
                result.effects[#result.effects + 1] = "wooden_object_notched"
                if notchResult == "destroyed" then
                    result.effects[#result.effects + 1] = "object_destroyed"
                end
                result.description = spell.name .. " warps and Notches " .. (target.name or "the wooden object") .. "."
            elseif mode == "root" then
                local zoneId = getWoodweaveZoneId(action, actor)
                local creatures = collectWoodweaveZoneCreatures(action, zoneId)
                for _, creature in ipairs(creatures) do
                    self:applyRooted(creature, { action = action, reason = "woodweave" })
                    creature.conditions = creature.conditions or {}
                    creature.conditions.woodweaveRooted = true
                end
                woodweave.zoneId = zoneId
                woodweave.creatures = creatures
                woodweave.result = "zone_rooted"
                result.zoneId = zoneId
                result.spellTargets = creatures
                result.effects[#result.effects + 1] = "woodweave_zone_rooted"
                result.effects[#result.effects + 1] = "rooted"
                result.description = spell.name .. " raises entangling vines in " .. tostring(zoneId) .. "."
            elseif mode == "shape" then
                local rawMaterials = target or action.rawMaterials
                if not isWoodweaveRawMaterial(rawMaterials) then
                    result.success = false
                    result.description = spell.name .. " needs equivalent raw wood materials to shape."
                    result.effects[#result.effects + 1] = "woodweave_materials_missing"
                    return false
                end
                if not hasEquivalentWoodweaveShapeSize(rawMaterials, action) then
                    result.success = false
                    result.description = spell.name .. " needs raw wooden materials of equivalent size."
                    result.effects[#result.effects + 1] = "woodweave_material_size_mismatch"
                    return false
                end
                rawMaterials.shapedByWoodweave = true
                rawMaterials.shapedInto = action.shapeInto or action.shape or action.objectName or "wooden object"
                rawMaterials.equivalentSizeRequired = true
                woodweave.target = rawMaterials
                woodweave.result = "wood_shaped"
                woodweave.shapedInto = rawMaterials.shapedInto
                result.effects[#result.effects + 1] = "wood_shaped"
                result.description = spell.name .. " shapes raw wood into " .. tostring(rawMaterials.shapedInto) .. "."
            else
                result.success = false
                result.description = spell.name .. " needs a living plant, wooden object, vegetation zone, or raw materials."
                result.effects[#result.effects + 1] = "woodweave_invalid_target"
                return false
            end

            result.woodweave = woodweave
        elseif effect.type == "darklight" then
            local valid, reason, effectName, viewers, viewerIds = validateDarklight(action, spell, resolveSpent, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return false
            end

            local props = target.properties or {}
            target.properties = props
            local previousProperties = {
                isLit = props.isLit,
                is_lit = props.is_lit,
                extinguished = props.extinguished,
                flicker_count = props.flicker_count,
                darklight = props.darklight,
                darklightVisibleOnly = props.darklightVisibleOnly,
                darklightHolderId = props.darklightHolderId,
                darklightVisibleTo = props.darklightVisibleTo,
                darklightViewerIds = props.darklightViewerIds,
                ignoreTorchesGutter = props.ignoreTorchesGutter,
                darklightIgnoreTorchesGutter = props.darklightIgnoreTorchesGutter,
                stealthLight = props.stealthLight,
                providesOnlyPrivateLight = props.providesOnlyPrivateLight,
                light_source = props.light_source,
                candle = props.candle,
            }

            local visibleTo = {}
            local holderId = spellEntityKey(actor)
            if holderId then
                visibleTo[holderId] = true
            end
            for _, viewerId in ipairs(viewerIds) do
                visibleTo[viewerId] = true
            end

            props.light_source = true
            props.candle = true
            props.isLit = true
            props.is_lit = true
            props.extinguished = false
            props.darklight = true
            props.darklightVisibleOnly = true
            props.darklightHolderId = holderId
            props.darklightVisibleTo = visibleTo
            props.darklightViewerIds = viewerIds
            props.ignoreTorchesGutter = true
            props.darklightIgnoreTorchesGutter = true
            props.stealthLight = true
            props.providesOnlyPrivateLight = true

            target.darklight = {
                active = true,
                caster = actor,
                casterId = holderId,
                spellId = spell.id,
                viewers = viewers,
                viewerIds = viewerIds,
                previousProperties = previousProperties,
            }

            result.darklight = target.darklight
            result.darklightViewers = viewers
            result.darklightViewerIds = viewerIds
            result.effects[#result.effects + 1] = "darklight"
            if #viewerIds > 0 then
                result.effects[#result.effects + 1] = "darklight_extra_viewers"
            end
            result.description = spell.name .. " hides a candle's light from everyone except chosen viewers."
        elseif effect.type == "heavenfire" then
            if not target then
                result.description = spell.name .. " manifests."
            elseif isSpellObjectTarget(target) then
                target.properties = target.properties or {}
                local props = target.properties
                props.light_source = true
                props.isLit = true
                props.is_lit = true
                props.brightLight = true
                props.heavenfire = true
                props.noHeat = true
                props.consumesFuel = false
                props.consumable = false
                props.extinguishableByWaterOrSuffocation = true
                props.extinguishOnMeatgrinder = "torches_gutter"
                target.heavenfireLit = true
                result.effects[#result.effects + 1] = "heavenfire_light"
                result.description = spell.name .. " lights " .. (target.name or "object") .. " with bright, heatless flame."
            elseif isUndeadTarget(target) or isWastesSpirit(target) then
                if target.takeWound then
                    self:applyDamage(target, 1, { "piercing" }, nil, action.allEntities,
                        self:getActionWoundOptions(action, target))
                end
                result.damageDealt = (result.damageDealt or 0) + 1
                result.effects[#result.effects + 1] = "heavenfire_piercing_wound"
                result.description = spell.name .. " burns " .. (target.name or "target") .. " with holy light."
            elseif isLivingSightedTarget(target) then
                target.conditions = target.conditions or {}
                target.conditions.blind = true
                target.blindUntil = "end_next_turn"
                result.effects[#result.effects + 1] = "blind"
                result.effects[#result.effects + 1] = "heavenfire_blind"
                result.description = spell.name .. " blinds " .. (target.name or "target") .. "."
            else
                result.effects[#result.effects + 1] = "heavenfire_no_effect"
                result.description = spell.name .. " has no effect on " .. (target.name or "the target") .. "."
            end
        elseif effect.type == "binding" then
            local targets, bindingName, generic = collectBindingTargets(action, target)
            if #targets == 0 then
                result.success = false
                result.description = spell.name .. " finds no matching visible creature."
                result.effects[#result.effects + 1] = "binding_no_targets"
                return false
            end

            for _, boundTarget in ipairs(targets) do
                self:applyRooted(boundTarget, { action = action, reason = "binding" })
                boundTarget.conditions = boundTarget.conditions or {}
                boundTarget.conditions.bindingRooted = true
                boundTarget.bindingRootedBy = actor
                boundTarget.bindingName = bindingName
                boundTarget.nonRecoverableConditions = boundTarget.nonRecoverableConditions or {}
                boundTarget.nonRecoverableConditions.rooted = "binding"
            end

            result.bindingTargets = targets
            result.spellTargets = targets
            result.bindingName = bindingName
            result.bindingGeneric = generic
            result.effects[#result.effects + 1] = "binding_rooted"
            result.description = spell.name .. " roots " .. tostring(#targets) .. " named creature(s)."
        elseif effect.type == "charm" then
            local cloakedTarget = getCharmCloakedTarget(action)
            if not target then
                result.success = false
                result.description = "No target for " .. spell.name .. "."
                result.effects[#result.effects + 1] = "spell_target_missing"
                return false
            end
            if not charmCloakedTargetIsWilling(action, cloakedTarget) then
                result.success = false
                result.description = spell.name .. " needs a second willing target."
                result.effects[#result.effects + 1] = "charm_cloaked_target_missing"
                return false
            end
            if isCharmImmune(target) then
                result.effects[#result.effects + 1] = "charm_no_effect"
                result.skipOngoingSpell = true
                result.description = spell.name .. " has no effect on " .. (target.name or "the target") .. "."
            else
                local previousDisposition = target.getDisposition and target:getDisposition() or target.disposition or "distaste"
                local cloakedTargetId = cloakedTarget.id or cloakedTarget.name or tostring(cloakedTarget)

                target.conditions = target.conditions or {}
                target.conditions.charmed = true
                target.conditions.inspired = true
                target.conditions.inspiredTrust = true
                target.charmedRelations = target.charmedRelations or {}
                target.charmedRelations[cloakedTargetId] = {
                    target = cloakedTarget,
                    targetId = cloakedTargetId,
                    disposition = "trust",
                    inspired = true,
                    illusionVisibleOnlyTo = target,
                    caster = actor,
                    casterId = actor and actor.id,
                }
                target.charm = {
                    caster = actor,
                    casterId = actor and actor.id,
                    primaryTarget = target,
                    cloakedTarget = cloakedTarget,
                    cloakedTargetId = cloakedTargetId,
                    previousDisposition = previousDisposition,
                    concentration = true,
                    endsOnDispositionChange = true,
                    visibleOnlyToTarget = true,
                }
                target.charmedBy = actor
                target.illusionVisibleOnlyTo = target
                if target.setDisposition then
                    target:setDisposition("trust")
                else
                    target.disposition = "trust"
                end

                result.charm = target.charm
                result.cloakedTarget = cloakedTarget
                result.effects[#result.effects + 1] = "charmed"
                result.effects[#result.effects + 1] = "inspired_trust"
                result.description = spell.name .. " inspires trust toward " .. (cloakedTarget.name or "the cloaked target") .. "."
            end
        elseif effect.type == "emotional_illusion" then
            local cloakedTarget = getEmotionalIllusionCloakedTarget(action)
            local disposition = effect.disposition or "fear"
            local spellId = spell.id or disposition
            if not target then
                result.success = false
                result.description = "No target for " .. spell.name .. "."
                result.effects[#result.effects + 1] = "spell_target_missing"
                return false
            end
            if not emotionalIllusionCloakedTargetIsWilling(action, cloakedTarget) then
                result.success = false
                result.description = spell.name .. " needs a second willing target."
                result.effects[#result.effects + 1] = spellId .. "_cloaked_target_missing"
                return false
            end
            if isCharmImmune(target) then
                result.effects[#result.effects + 1] = spellId .. "_no_effect"
                result.skipOngoingSpell = true
                result.description = spell.name .. " has no effect on " .. (target.name or "the target") .. "."
            else
                local previousDisposition = target.getDisposition and target:getDisposition() or target.disposition or "distaste"
                local cloakedTargetId = cloakedTarget.id or cloakedTarget.name or tostring(cloakedTarget)
                local inspiredCondition = disposition == "anger" and "inspiredAnger" or "inspiredFear"
                local relationLabel = disposition == "anger" and "hated" or "feared"

                target.conditions = target.conditions or {}
                target.conditions.inspired = true
                target.conditions[inspiredCondition] = true
                if disposition == "fear" then
                    target.conditions.fearful = true
                    target.mustFleeFrom = cloakedTarget
                elseif disposition == "anger" then
                    target.conditions.enraged = true
                    target.recklessAttackTarget = cloakedTarget
                end
                target.emotionalIllusionRelations = target.emotionalIllusionRelations or {}
                target.emotionalIllusionRelations[cloakedTargetId] = {
                    target = cloakedTarget,
                    targetId = cloakedTargetId,
                    disposition = disposition,
                    relation = relationLabel,
                    inspired = true,
                    illusionVisibleOnlyTo = target,
                    caster = actor,
                    casterId = actor and actor.id,
                }
                target.emotionalIllusion = {
                    caster = actor,
                    casterId = actor and actor.id,
                    spellId = spellId,
                    primaryTarget = target,
                    cloakedTarget = cloakedTarget,
                    cloakedTargetId = cloakedTargetId,
                    disposition = disposition,
                    previousDisposition = previousDisposition,
                    concentration = true,
                    endsOnDispositionChange = true,
                    visibleOnlyToTarget = true,
                }
                target.emotionalIllusionBy = actor
                target.illusionVisibleOnlyTo = target
                if target.setDisposition then
                    target:setDisposition(disposition)
                else
                    target.disposition = disposition
                end

                result.emotionalIllusion = target.emotionalIllusion
                result.cloakedTarget = cloakedTarget
                result.effects[#result.effects + 1] = spellId
                result.effects[#result.effects + 1] = "inspired_" .. disposition
                result.description = spell.name .. " inspires " .. disposition .. " toward " ..
                    (cloakedTarget.name or "the cloaked target") .. "."
            end
        elseif effect.type == "sleep" then
            if not target then
                result.success = false
                result.description = "No target for " .. spell.name .. "."
                result.effects[#result.effects + 1] = "spell_target_missing"
                return false
            end

            target.conditions = target.conditions or {}
            local dangerous = isSleepDangerousSituation(action)
            local longSleep = resolveSpent >= 4 and not dangerous
            target.sleep = {
                caster = actor,
                casterId = actor and actor.id,
                spellId = spell.id,
                dangerous = dangerous,
                resolveSpent = resolveSpent,
                canAwakenWithSharpSlap = not dangerous,
                noAging = longSleep,
                noFoodRequired = longSleep,
            }

            if dangerous then
                result.stunDiscard = self:applyStun(target, { action = action })
                result.stunDiscardedCard = result.stunDiscard.card
                target.conditions.drowsy = true
                result.effects[#result.effects + 1] = "sleep_stunned"
                result.effects[#result.effects + 1] = "drowsy"
                result.description = spell.name .. " leaves " .. (target.name or "target") .. " drowsy and Stunned."
            else
                target.conditions.knocked_out = true
                target.conditions.knockout = true
                target.conditions.sleeping = true
                result.effects[#result.effects + 1] = "sleep_knockout"
                if longSleep then
                    target.sleep.noAging = true
                    target.sleep.noFoodRequired = true
                    target.doesNotAgeWhileAsleep = true
                    target.requiresNoFoodWhileAsleep = true
                    result.effects[#result.effects + 1] = "sleep_suspended_needs"
                end
                result.description = spell.name .. " knocks " .. (target.name or "target") .. " into supernatural sleep."
            end

            result.sleep = target.sleep
        elseif effect.type == "shroud" then
            if not target then
                result.success = false
                result.description = "No target for " .. spell.name .. "."
                result.effects[#result.effects + 1] = "spell_target_missing"
                return false
            end

            target.conditions = target.conditions or {}
            target.conditions.shrouded = true
            target.conditions.invisible = true
            target.shroudedBy = actor
            target.shroud = {
                caster = actor,
                casterId = spellEntityKey(actor),
                spellId = spell.id,
                active = true,
                concentration = true,
                coversCarriedItems = true,
                cannotBeSeenWithoutMagic = true,
                stillAndQuietCannotBeTargeted = true,
                moved = false,
                vaguePresenceKnown = false,
                visibleObjectsRequireResolve = true,
                visibleInteractions = 0,
                maintenanceResolveSpent = 0,
            }

            result.shroud = target.shroud
            result.spellTargets = { target }
            result.effects[#result.effects + 1] = "shrouded"
            result.description = spell.name .. " makes " .. (target.name or "target") .. " and their carried gear Shrouded."
        elseif effect.type == "scry" then
            local valid, reason, effectName, scryDetails = validateScry(action, resolveSpent, actor)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return false
            end

            local scrying = {
                spellId = spell.id,
                caster = actor,
                casterId = spellEntityKey(actor),
                active = true,
                concentration = true,
                location = scryDetails.location,
                locationId = scryDetails.locationId,
                locationName = scryDetails.locationName,
                currentArea = scryDetails.currentArea,
                targetArea = scryDetails.targetArea,
                outsideCurrentArea = scryDetails.outsideArea,
                canSeeLocation = true,
                visitedLocationOnly = true,
                crystalBall = result.component,
                resolveSpent = resolveSpent,
            }
            actor.scrying = scrying
            result.scrying = scrying
            result.effects[#result.effects + 1] = "scrying"
            if scrying.outsideCurrentArea then
                result.effects[#result.effects + 1] = "scry_cross_area"
            end
            result.description = spell.name .. " reveals " .. tostring(scrying.locationName) .. "."
        elseif effect.type == "circle_of_protection" then
            local valid, reason, effectName, realms = validateCircleProtection(action, spell, resolveSpent)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return false
            end

            local _, realmSet = collectCircleProtectionRealms(action)
            local circle = self:createCircleProtection(actor, action, spell, resolveSpent, realms, realmSet)
            result.circleProtection = circle
            result.spellTargets = { circle }
            result.effects[#result.effects + 1] = "circle_of_protection"
            result.description = spell.name .. " protects against " .. tostring(#realms) .. " far realm(s)."
        elseif effect.type == "feather" then
            if not target then
                result.success = false
                result.description = "No target for " .. spell.name .. "."
                result.effects[#result.effects + 1] = "spell_target_missing"
                return false
            end

            target.conditions = target.conditions or {}
            target.conditions.feather = true
            target.conditions.floating = true
            target.featherBy = actor
            target.feather = {
                caster = actor,
                casterId = actor and actor.id,
                concentration = true,
                fallingInterrupted = target.falling == true or action.falling == true,
                preventsFallingDamage = true,
                preventsHazardSceneryDamage = true,
                preventsPressurePlateTrigger = true,
            }
            target.floating = true
            target.falling = false
            target.effectiveWeight = "feather"
            target.weightReducedToFeather = true
            target.immuneToFallingDamage = true
            target.immuneToHazardScenery = true
            target.ignorePressurePlates = true
            target.easyToMove = true

            if target.properties then
                target.properties.featherWeight = true
                target.properties.floating = true
                target.properties.easyToMove = true
                target.properties.ignorePressurePlates = true
                target.properties.immuneToHazardScenery = true
            end

            result.feather = target.feather
            result.spellTargets = { target }
            result.effects[#result.effects + 1] = "feather_weight"
            result.description = spell.name .. " makes " .. (target.name or "target") .. " light as a feather."
        elseif effect.type == "guardian_angel" then
            if not target then
                result.success = false
                result.description = "No target for " .. spell.name .. "."
                result.effects[#result.effects + 1] = "spell_target_missing"
                return false
            end
            if target.guardianAngel and not target.guardianAngel.used then
                result.success = false
                result.description = "Guardian Angel is already protecting " .. (target.name or "target") .. "."
                result.effects[#result.effects + 1] = "guardian_angel_already_active"
                return false
            end

            local card = action.card
            local angel = {
                caster = actor,
                casterId = actor and actor.id,
                target = target,
                targetId = target.id,
                card = card,
                value = card and card.value or 0,
                canDodge = true,
                canRiposte = true,
                doesNotCountDefenseSlot = true,
                lastsUntilUsed = true,
                used = false,
            }

            target.conditions = target.conditions or {}
            target.conditions.guardianAngel = true
            target.guardianAngel = angel
            target.guardianAngelCard = card
            result.guardianAngel = angel
            result.effects[#result.effects + 1] = "guardian_angel_prepared"
            result.description = spell.name .. " waits to protect " .. (target.name or "target") .. " from one blow."
        elseif effect.type == "withering" then
            if target and target.takeWound and not (target.undead or hasTag(target, "undead")) then
                self:applyDamage(target, 1, {}, nil, action.allEntities)
                result.witheringAging = markWitheringAging(target)
                result.damageDealt = (result.damageDealt or 0) + 1
                result.effects[#result.effects + 1] = "withered"
                result.effects[#result.effects + 1] = "withering_aging"
                result.description = spell.name .. " withers " .. (target.name or "target") .. "."
            elseif target and (target.undead or hasTag(target, "undead")) then
                target.conditions = target.conditions or {}
                target.conditions.terrible = true
                local undeadKind = witheringUndeadKind(target)
                if undeadKind == "zombie" then
                    applyWitheringSkeletonForm(target)
                    result.effects[#result.effects + 1] = "zombie_transformed_skeleton"
                elseif undeadKind == "skeleton" then
                    applyWitheringWraithForm(target)
                    result.effects[#result.effects + 1] = "skeleton_transformed_wraith"
                end
                target.witheringEmpowered = true
                result.witheringTransformation = target.witheringTransformation
                result.effects[#result.effects + 1] = "undead_empowered"
                result.description = spell.name .. " makes the undead more terrible."
            elseif target then
                local material = getWitheringMaterial(target)
                local notchResult = nil
                markWitheringObjectDecay(target)
                if material == "stone" then
                    target.stoneUnaffectedByWithering = true
                    result.effects[#result.effects + 1] = "withering_stone_unaffected"
                elseif resolveSpent >= 2 then
                    target.destroyed = true
                    if target.durability then
                        target.notches = target.durability
                    end
                    notchResult = "destroyed"
                    result.effects[#result.effects + 1] = "object_destroyed"
                else
                    target.durability = target.durability or 1
                    target.notches = target.notches or 0
                    notchResult = inventory.addNotch(target)
                    if notchResult == "destroyed" then
                        result.effects[#result.effects + 1] = "object_destroyed"
                    end
                end
                result.effects[#result.effects + 1] = "object_withered"
                result.itemNotchResult = notchResult
                result.description = spell.name .. " decays " .. (target.name or "object") .. "."
            else
                result.description = spell.name .. " manifests."
            end
        elseif effect.type == "stinking_cloud" then
            local zoneIds, zoneSet = collectStinkingCloudZoneIds(action, target, actor)
            local zoneCount = math.max(resolveSpent, #zoneIds)
            local cloud = {
                spellId = spell.id,
                caster = actor,
                casterId = spellEntityKey(actor),
                active = true,
                concentration = true,
                zoneIds = zoneIds,
                zoneSet = zoneSet,
                zoneCount = zoneCount,
                stunPenaltyPerRound = 1,
                knockoutAtStacks = 4,
                exposureCounts = {},
            }

            actor.activeStinkingClouds = actor.activeStinkingClouds or {}
            actor.activeStinkingClouds[#actor.activeStinkingClouds + 1] = cloud

            result.stinkingCloud = cloud
            result.zoneIds = zoneIds
            result.zoneCount = zoneCount
            result.stunPenalty = 1
            result.effects[#result.effects + 1] = "stinking_cloud"
            result.description = spell.name .. " fills " .. result.zoneCount .. " zone(s)."
        elseif effect.type == "life" then
            local targets = collectSpellTargets(action, target, math.max(1, resolveSpent))
            local lifeResults = {}

            for _, lifeTarget in ipairs(targets) do
                local targetResult = {
                    target = lifeTarget,
                    result = "no_effect",
                }

                if lifeTarget and lifeTarget.conditions and lifeTarget.conditions.deaths_door then
                    local healResult = lifeTarget.healWound and lifeTarget:healWound()
                    targetResult.result = healResult or "deaths_door_cleared"
                    targetResult.effect = "deaths_door_cleared"
                    result.effects[#result.effects + 1] = "deaths_door_cleared"
                elseif lifeTarget and (lifeTarget.undead or hasTag(lifeTarget, "undead")) then
                    if lifeTarget.takeWound then
                        self:applyDamage(lifeTarget, 1, {}, nil, action.allEntities,
                            self:getActionWoundOptions(action, lifeTarget))
                    end
                    targetResult.result = "undead_wounded"
                    targetResult.effect = "undead_wounded"
                    result.damageDealt = (result.damageDealt or 0) + 1
                    result.effects[#result.effects + 1] = "undead_wounded"
                elseif lifeTarget and (lifeTarget.plant or hasTag(lifeTarget, "plant")) then
                    lifeTarget.conditions = lifeTarget.conditions or {}
                    lifeTarget.conditions.growing = true
                    targetResult.result = "plant_grown"
                    targetResult.effect = "plant_grown"
                    result.effects[#result.effects + 1] = "plant_grown"
                else
                    local affliction, afflictionName = findTargetAffliction(
                        lifeTarget,
                        action.affliction or action.afflictionName or action.targetAffliction
                    )
                    if affliction then
                        local stage = math.max(1, tonumber(affliction.stage) or 1)
                        targetResult.affliction = afflictionName
                        targetResult.previousStage = stage
                        if stage <= 1 then
                            lifeTarget.afflictions[afflictionName] = nil
                            targetResult.result = "affliction_removed"
                            targetResult.effect = "affliction_removed"
                            result.effects[#result.effects + 1] = "affliction_removed"
                        else
                            affliction.stage = stage - 1
                            affliction.curedThisCamp = true
                            targetResult.result = "affliction_reduced"
                            targetResult.effect = "affliction_reduced"
                            targetResult.stage = affliction.stage
                            result.effects[#result.effects + 1] = "affliction_reduced"
                        end
                    end
                end

                lifeResults[#lifeResults + 1] = targetResult
            end

            result.lifeResults = lifeResults
            if #lifeResults == 0 then
                result.description = spell.name .. " has no target."
            else
                result.description = spell.name .. " touches " .. tostring(#lifeResults) .. " target(s)."
            end
        elseif effect.type == "veritas" then
            if not isPersonSpellTarget(target) then
                result.effects[#result.effects + 1] = "veritas_no_effect"
                result.description = spell.name .. " has no effect on " .. (target and target.name or "the target") .. "."
            else
                target.conditions = target.conditions or {}
                target.conditions.veritas = true
                target.veritas = {
                    caster = actor,
                    casterId = actor and actor.id,
                    knowsKnowinglyToldLies = true,
                    targetAware = true,
                    targetUnderstandsMagicalPolygraph = true,
                    concentration = true,
                }
                result.truthSense = target.veritas
                result.effects[#result.effects + 1] = "veritas"
                result.description = spell.name .. " reveals knowingly spoken lies from " .. (target.name or "target") .. "."
            end
        elseif effect.type == "seal_pact" then
            local parties = collectSealPactParties(action, target)
            local valid, reason, effectName = validateSealPactParties(action, spell, resolveSpent, parties)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return false
            end

            action.parties = parties
            local pact = self:createSealedPact(actor, parties, action, spell, resolveSpent)
            result.sealedPact = pact
            result.parties = parties
            result.effects[#result.effects + 1] = "sealed_pact"
            result.description = spell.name .. " binds " .. tostring(#parties) .. " willing parties."
        else
            result.description = (spell and spell.name or "Spell") .. " takes effect."
        end

        if spell and spell.ongoing and not result.skipOngoingSpell then
            actor.activeSpells = actor.activeSpells or {}
            local committedResolve = action.resolveCommitted
            if committedResolve == nil then
                committedResolve = resolveSpent
            end
            local activeSpell = {
                spellId = spell.id,
                name = spell.name,
                branch = spell.branch,
                caster = actor,
                casterId = actor and actor.id,
                target = target,
                resolveCommitted = committedResolve,
                concentration = spell.concentration == true,
                effectType = effect.type,
                zoneIds = result.zoneIds,
                zoneCount = result.zoneCount,
                targets = result.spellTargets or result.bindingTargets,
                cloakedTarget = result.cloakedTarget,
                circleProtection = result.circleProtection,
                elementWall = result.elementWall,
                totemForm = result.totemForm,
                animatedObject = result.animatedObject,
                fleshcraft = result.fleshcraft,
                raisedZombie = result.raisedZombie,
                malediction = result.malediction,
                scrying = result.scrying,
                giveForm = result.giveForm,
                portableHole = result.portableHole,
                mirrorMeld = result.mirrorMeld,
                visualIllusion = result.visualIllusion,
                stinkingCloud = result.stinkingCloud,
                instanceId = result.elementProtectionInstanceId,
                protectedElements = result.protectedElements,
            }
            actor.activeSpells[#actor.activeSpells + 1] = activeSpell
            if result.animatedObject then
                result.animatedObject.spellEntry = activeSpell
            end
            if result.fleshcraft then
                result.fleshcraft.spellEntry = activeSpell
            end
            if result.raisedZombie and result.raisedZombie.raiseZombie then
                result.raisedZombie.raiseZombie.spellEntry = activeSpell
            end
            if result.malediction then
                result.malediction.spellEntry = activeSpell
            end
            if result.giveForm then
                result.giveForm.spellEntry = activeSpell
            end
            if result.portableHole then
                result.portableHole.spellEntry = activeSpell
            end
            if result.mirrorMeld then
                result.mirrorMeld.spellEntry = activeSpell
            end
            if result.visualIllusion then
                result.visualIllusion.spellEntry = activeSpell
            end
            if result.stinkingCloud then
                result.stinkingCloud.spellEntry = activeSpell
            end
            actor.committedResolve = (actor.committedResolve or 0) + committedResolve
            result.effects[#result.effects + 1] = "ongoing_spell"

            if effect.type == "control" then
                self:resolveImmediateControlAction(action, result, actor, target)
            end
        end

        return true
    end

    function resolver:resolveProudAndAncientWarCry(action, result)
        local actor = action.actor
        if not entityHasUsableTalent(actor, "proud_and_ancient") then
            result.success = false
            result.description = "Requires Proud and Ancient."
            result.effects[#result.effects + 1] = "proud_and_ancient_required"
            return
        end

        local controller = action.challengeController or self.challengeController
        local inChallenge = action.inChallenge == true or
            (controller and controller.isActive and controller:isActive())
        if not inChallenge then
            result.success = false
            result.description = "Proud and Ancient war cry requires an active Challenge."
            result.effects[#result.effects + 1] = "challenge_required"
            return
        end

        local ok, reason = self:spendResolveForFavor(actor)
        if not ok then
            result.success = false
            result.description = "Cannot cry house motto: " .. (reason or "resolve unavailable") .. "."
            result.effects[#result.effects + 1] = "resolve_missing"
            return
        end

        local function normalizeHouse(value)
            return tostring(value or ""):lower():gsub("[’']", ""):gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
        end

        local house = normalizeHouse(action.house or actor.house or actor.humanHouse or actor.kinHouse or actor.family)
        local candidates = {}
        if type(action.heardBy or action.listeners) == "table" then
            candidates = action.heardBy or action.listeners
        elseif type(action.allEntities) == "table" then
            candidates = action.allEntities
        elseif type(action.guild) == "table" then
            candidates = action.guild
        else
            candidates = { actor }
        end

        local affected = {}
        local seen = {}
        local function canHear(entity)
            local conditions = entity and entity.conditions or {}
            return entity and not (conditions.dead or conditions.deaf or conditions.deafened or entity.canHearWarCry == false)
        end
        local function sameHouse(entity)
            if entity == actor then
                return true
            end
            if house == "" then
                return false
            end
            return normalizeHouse(entity.house or entity.humanHouse or entity.kinHouse or entity.family) == house
        end
        local function addAffected(entity)
            if entity and not seen[entity] and canHear(entity) and sameHouse(entity) then
                seen[entity] = true
                entity.nextActionFavor = true
                entity.nextActionFavorSource = "proud_and_ancient"
                affected[#affected + 1] = entity
            end
        end

        addAffected(actor)
        for _, entity in ipairs(candidates) do
            addAffected(entity)
        end

        result.success = true
        result.description = (actor.name or "The adventurer") .. " cries their house motto."
        result.effects[#result.effects + 1] = "proud_and_ancient_war_cry"
        result.effects[#result.effects + 1] = "resolve_spent_for_proud_and_ancient"
        result.affected = affected
        result.affectedCount = #affected
        result.house = house ~= "" and house or nil
    end

    function resolver:resolveSpeakIncantation(action, result)
        local actor = action.actor
        local target = action.target or (type(action.targets) == "table" and action.targets[1] or nil)
        action.target = target
        if action.proudAndAncientWarCry == true or action.proudAndAncient == true or
           action.warCry == "proud_and_ancient" then
            self:resolveProudAndAncientWarCry(action, result)
            return
        end

        local spell = self:getSpellFromAction(action)

        if not spell then
            result.success = false
            result.description = "No spell selected."
            result.effects[#result.effects + 1] = "spell_missing"
            return
        end

        if spell.targetMode == "self" or spell.targetMode == "actor" then
            target = actor
            action.target = target
        end

        if spell.id == "totem" and not target then
            target = actor
            action.target = target
        end

        if spell.id == "portable_hole" and not target then
            target = portableHoleTargetFromAction(action, target)
            action.target = target
        end

        if spell.id == "mirror_meld" and not target then
            target = mirrorMeld.targetFromAction(action, target)
            action.target = target
        end

        local resolveSpent = action.resolveSpent or 1
        local sealPactParties = nil

        if spell.targetMode == "willing_parties" then
            sealPactParties = collectSealPactParties(action, target)
            if not target and #sealPactParties > 0 then
                target = sealPactParties[1]
                action.target = target
            end

            local valid, reason, effectName = validateSealPactParties(action, spell, resolveSpent, sealPactParties)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return
            end

            action.parties = sealPactParties
        end

        if spell.id == "animate_object" then
            local valid, reason, effectName = validateAnimateObject(action, spell, resolveSpent, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return
            end
        end

        if spell.id == "necromancy" then
            local valid, reason, effectName = validateNecromancy(action, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return
            end
        end

        if spell.id == "fleshcraft" then
            local valid, reason, effectName = validateFleshcraft(action, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return
            end
        end

        if spell.id == "raise_zombie" then
            local valid, reason, effectName = validateRaiseZombie(action, target, resolveSpent)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return
            end
        end

        if spell.id == "malediction" then
            local valid, reason, effectName = validateMalediction(action, target, self)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return
            end
        end

        if spell.id == "circle_of_protection" then
            local valid, reason, effectName = validateCircleProtection(action, spell, resolveSpent)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return
            end
        end

        if spell.id == "defy_depths" then
            local valid, reason, effectName = validateDefyDepths(action, spell, resolveSpent, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return
            end
        end

        if spell.id == "gust_of_wind" then
            local valid, reason, effectName = self:validateGustOfWind(action, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return
            end
        end

        if spell.id == "protection_from_elements" then
            local valid, reason, effectName = validateProtectionFromElements(action, spell, resolveSpent, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return
            end
        end

        if spell.id == "thunderclap" then
            local valid, reason, effectName = self:validateThunderclap(action, actor)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return
            end
        end

        if spell.id == "totem" then
            local valid, reason, effectName = validateTotem(action, target, self)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return
            end
        end

        if spell.id == "scry" then
            local valid, reason, effectName = validateScry(action, resolveSpent, actor)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return
            end
        end

        if spell.id == "wall_of_elements" then
            local valid, reason, effectName = validateWallOfElements(action, resolveSpent)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return
            end
        end

        if spell.id == "woodweave" then
            local valid, reason, effectName = validateWoodweave(action, actor, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return
            end
        end

        if spell.id == "change_size" then
            local valid, reason, effectName = validateChangeSize(action, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return
            end
        end

        if spell.id == "give_form_to_nothingness" then
            local valid, reason, effectName = validateGiveFormToNothingness(action, spell, resolveSpent, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return
            end
        end

        if spell.id == "portable_hole" then
            local valid, reason, effectName, surface = validatePortableHole(action, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return
            end
            target = surface
            action.target = target
        end

        if spell.id == "mirror_meld" then
            local valid, reason, effectName, mirror = mirrorMeld.validate(action, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return
            end
            target = mirror
            action.target = target
        end

        if spell.id == "illusion" then
            local valid, reason, effectName = validateVisualIllusion(action)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return
            end
        end

        if spell.id == "darklight" then
            local valid, reason, effectName = validateDarklight(action, spell, resolveSpent, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return
            end
        end

        if spell.effect and spell.effect.type == "control" then
            local valid, reason, effectName = validateControlSpell(action, spell, resolveSpent, target)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return
            end
        end

        if not self:actorKnowsSpell(actor, spell) then
            result.success = false
            result.description = "Missing training for " .. (spell.name or "spell") .. "."
            result.effects[#result.effects + 1] = "spell_training_missing"
            return
        end

        if not target and spell.targetMode ~= "environment" and spell.targetMode ~= "environment_or_creature" and
           spell.targetMode ~= "willing_parties" and spell.targetMode ~= "self" and spell.targetMode ~= "actor" then
            result.success = false
            result.description = "No target for " .. (spell.name or "spell") .. "."
            result.effects[#result.effects + 1] = "spell_target_missing"
            return
        end

        if spell.multiTarget and type(action.targets) == "table" and #action.targets > math.max(1, resolveSpent) then
            result.success = false
            result.description = spell.name .. " needs more Resolve for that many targets."
            result.effects[#result.effects + 1] = "spell_too_many_targets"
            return
        end

        if spell.id == "guardian_angel" and target and target.guardianAngel and not target.guardianAngel.used then
            result.success = false
            result.description = "Guardian Angel is already protecting " .. (target.name or "target") .. "."
            result.effects[#result.effects + 1] = "guardian_angel_already_active"
            return
        end

        if not self:canSpeakSpell(actor) then
            result.success = false
            result.description = "Spellcasting requires loud, clear speech."
            result.effects[#result.effects + 1] = "spell_speech_blocked"
            return
        end

        if not self:canSeeOrTouchSpellTarget(action) then
            result.success = false
            result.description = "Spell target must be visible or touchable."
            result.effects[#result.effects + 1] = "spell_target_unreachable"
            return
        end

        local component = self:findSpellComponent(actor, spell)
        if not component then
            result.success = false
            result.description = "Missing held component for " .. (spell.name or "spell") .. "."
            result.effects[#result.effects + 1] = "spell_component_missing"
            return
        end

        if spell.id == "give_form_to_nothingness" then
            local valid, reason, effectName = validateGiveFormDrumUse(action, actor, component)
            if not valid then
                result.success = false
                result.description = reason
                result.effects[#result.effects + 1] = effectName
                return
            end
        end

        if self:hasSignificantIron(actor) then
            result.success = false
            result.description = "Significant iron prevents spellcasting."
            result.effects[#result.effects + 1] = "iron_blocks_magic"
            return
        end

        if spell.targetMode == "willing_parties" then
            for _, party in ipairs(sealPactParties or {}) do
                if self:hasSignificantIron(party) then
                    result.success = false
                    result.description = "Iron on a pact party makes the spell fizzle."
                    result.effects[#result.effects + 1] = "iron_blocks_magic"
                    return
                end
            end
        elseif target and self:hasSignificantIron(target) then
            result.success = false
            result.description = "Iron on the target makes the spell fizzle."
            result.effects[#result.effects + 1] = "iron_blocks_magic"
            return
        end

        if spell.concentration then
            local activeConcentration = self:getConcentrationSpell(actor)
            if activeConcentration then
                if action.endCurrentConcentration then
                    self:endOngoingSpell(actor, activeConcentration, "replaced_by_new_concentration", {
                        source = action,
                    })
                else
                    result.success = false
                    result.description = "Already concentrating on a spell."
                    result.effects[#result.effects + 1] = "concentration_slot_full"
                    return
                end
            end
        end

        local needsTrainingXP = self:spellUsesTrainingXP(actor, spell)
        if needsTrainingXP and not self:hasTrainingXP(actor) then
            result.success = false
            result.description = "In-training spellcasting requires 1 XP."
            result.effects[#result.effects + 1] = "spell_training_xp_missing"
            return
        end

        local pactCharge = nil
        local resolveCost = resolveSpent
        if action.usePactCharge or action.spendPactCharge then
            pactCharge = self:getPactChargeForSpell(component, spell)
            if not pactCharge then
                result.success = false
                result.description = "No pact charge is available for " .. (spell.name or "spell") .. "."
                result.effects[#result.effects + 1] = "pact_charge_missing"
                return
            end
            resolveCost = math.max(0, resolveSpent - 1)
        end

        local resolveOk, resolveReason = self:spendSpellResolve(actor, resolveCost)
        if not resolveOk then
            result.success = false
            result.description = "Cannot cast: " .. (resolveReason or "resolve unavailable") .. "."
            result.effects[#result.effects + 1] = "resolve_missing"
            return
        end

        if needsTrainingXP then
            if not self:spendTrainingXP(actor) then
                if actor and actor.resolve ~= nil then
                    actor.resolve = actor.resolve + resolveCost
                end
                result.success = false
                result.description = "In-training spellcasting requires 1 XP."
                result.effects[#result.effects + 1] = "spell_training_xp_missing"
                return
            end
            result.effects[#result.effects + 1] = "spell_training_xp_spent"
        end

        if pactCharge then
            self:spendPactCharge(component, pactCharge, spell, actor)
            action.resolveCommitted = resolveCost
            result.pactChargeSpent = true
            result.pactCharge = pactCharge
            result.effects[#result.effects + 1] = "pact_charge_spent"
        end

        result.spell = spell
        result.component = component
        result.resolveSpent = resolveCost
        result.spellResolveValue = resolveSpent

        if self:isSpellContestRequired(action, spell, target) then
            local originalTarget = action.target
            action.target = self:getSpellContestTarget(action, target)
            local contest = self:resolveInitiativeContest(action, result, {
                tieWins = true,
                considerShield = true,
            })
            action.target = originalTarget
            if contest.dodged then
                return
            end
        else
            result.success = true
        end

        if result.success then
            result.effects[#result.effects + 1] = "spell_cast"
            result.effects[#result.effects + 1] = "spell_" .. spell.id
            local applied = self:applySpellEffect(action, result, spell)
            if applied ~= false and result.success ~= false then
                self.eventBus:emit(events.EVENTS.SPELL_CAST, {
                    actor = actor,
                    spell = spell,
                    target = target,
                    resolveSpent = resolveSpent,
                    result = result,
                })
            end
        else
            result.description = "Incantation resisted."
        end
    end

    -- Backward-compatible wrapper
    function resolver:resolveCast(action, result)
        self:resolveSpeakIncantation(action, result)
    end

    function resolver:resolveGuard(action, result)
        local actor = action.actor
        if not actor then
            result.success = false
            result.description = "No actor for Guard."
            return
        end

        if not self:entityHasShield(actor) then
            result.success = false
            result.description = "Guard requires a shield."
            return
        end

        local controller = action.challengeController or self.challengeController
        if not controller or not controller.getInitiativeSlot then
            result.success = false
            result.description = "No initiative slot available."
            return
        end

        local slot = controller:getInitiativeSlot(actor.id)
        if not slot then
            result.success = false
            result.description = "No initiative to replace."
            return
        end

        local oldValue = slot.value or (slot.card and slot.card.value) or 0
        slot.card = action.card
        slot.value = action.card and action.card.value or oldValue
        slot.revealed = true

        self.eventBus:emit(events.EVENTS.INITIATIVE_REVEALED, {
            entity = actor,
        })

        result.success = true
        result.description = "Guard set Initiative from " .. oldValue .. " to " .. slot.value .. "."
        result.effects[#result.effects + 1] = "guarded"
    end

    function resolver:getWornIronOrSteelArmor(actor)
        if not actor then
            return nil
        end

        local actorArmorType = normalizeSocialTag(actor.armorType or actor.wornArmorType)
        if actorArmorType == "iron" or actorArmorType == "steel" then
            return actor.armor or actor
        end

        local inv = actor.inventory
        local belt = inv and inv.getItems and inv:getItems(inventory.LOCATIONS.BELT) or inv and inv.belt or {}
        for _, item in ipairs(belt or {}) do
            local props = item.properties or {}
            local armorType = normalizeSocialTag(item.armorType or props.armorType)
            if (item.isArmor or props.armor) and not item.destroyed and
               (armorType == "iron" or armorType == "steel") then
                return item
            end
        end

        return nil
    end

    function resolver:resolveHeavyMetalMachine(action, result)
        local actor = action.actor
        if not actor then
            result.success = false
            result.description = "No actor for Heavy Metal Machine."
            return
        end

        if not entityHasUsableTalent(actor, "heavy_metal_machine") then
            result.success = false
            result.description = "Requires Heavy Metal Machine."
            result.effects[#result.effects + 1] = "heavy_metal_machine_blocked"
            return
        end
        if not self:isActiveChallengeAction(action) then
            result.success = false
            result.description = "Heavy Metal Machine requires an active Challenge."
            result.effects[#result.effects + 1] = "heavy_metal_machine_blocked"
            return
        end

        local armor = self:getWornIronOrSteelArmor(actor)
        if not armor then
            result.success = false
            result.description = "Requires worn iron or steel armor."
            result.effects[#result.effects + 1] = "heavy_metal_machine_blocked"
            return
        end

        local controller = action.challengeController or self.challengeController
        if not controller or not controller.getInitiativeSlot then
            result.success = false
            result.description = "No initiative slot available."
            result.effects[#result.effects + 1] = "heavy_metal_machine_blocked"
            return
        end

        local slot = controller:getInitiativeSlot(actor.id)
        if not slot then
            result.success = false
            result.description = "No initiative to boost."
            result.effects[#result.effects + 1] = "heavy_metal_machine_blocked"
            return
        end

        local round = controller.currentRound or action.currentRound or 1
        if actor.heavyMetalMachineUsedRound == round then
            result.success = false
            result.description = "Heavy Metal Machine already used this round."
            result.effects[#result.effects + 1] = "heavy_metal_machine_spent"
            return
        end

        local bonus = actor.swords or (actor.getAttribute and actor:getAttribute(constants.SUITS.SWORDS)) or 0
        actor.heavyMetalMachineUsedRound = round
        actor.heavyMetalMachineInterrupt = {
            round = round,
            bonus = bonus,
            card = action.card,
            armor = armor,
            againstAction = action.againstAction,
            againstActionId = action.againstActionId,
            againstActorId = action.againstActorId,
        }

        result.success = true
        result.heavyMetalMachine = actor.heavyMetalMachineInterrupt
        result.description = "Heavy Metal Machine readied +" .. tostring(bonus) .. " Initiative."
        result.effects[#result.effects + 1] = "heavy_metal_machine_readied"
    end

    local function resolveFollowUpActionType(followUpAction)
        if type(followUpAction) == "table" then
            return followUpAction.id or followUpAction.type
        end
        return followUpAction
    end

    --- Pick a sensible same-suit follow-up when UI did not provide one.
    function resolver:selectDefaultVigilanceFollowUp(action)
        if not action or not action.card then
            return nil
        end

        local cardActionSuit = action_registry.cardSuitToActionSuit(action.card.suit)
        if cardActionSuit == action_registry.SUITS.MISC then
            return nil
        end

        local options = action_registry.getActionsForSuit(cardActionSuit, {
            challengeOnly = true,
        })

        for _, option in ipairs(options) do
            local optionType = self:normalizeActionType(option.id)
            if optionType ~= M.ACTION_TYPES.VIGILANCE then
                return optionType
            end
        end

        return nil
    end

    function resolver:resolveVigilance(action, result)
        local actor = action.actor
        if not actor then
            result.success = false
            result.description = "No actor for Vigilance."
            return
        end

        if actor.pendingVigilance then
            result.success = false
            result.description = "Already has Vigilance prepared."
            return
        end

        local followUpActionType = resolveFollowUpActionType(action.followUpAction)
        followUpActionType = self:normalizeActionType(followUpActionType)
        if not followUpActionType then
            followUpActionType = self:selectDefaultVigilanceFollowUp(action)
        end
        if not followUpActionType then
            result.success = false
            result.description = "Vigilance needs a follow-up action."
            return
        end

        local followUpActionDef = action_registry.getAction(followUpActionType)
        if not followUpActionDef then
            result.success = false
            result.description = "Unknown Vigilance follow-up action."
            return
        end

        if followUpActionDef.suit == action_registry.SUITS.MISC then
            result.success = false
            result.description = "Vigilance follow-up must be a suited action."
            return
        end

        if not action.card or not action.card.suit then
            result.success = false
            result.description = "Vigilance requires a suited card."
            return
        end

        local cardActionSuit = action_registry.cardSuitToActionSuit(action.card.suit)
        if cardActionSuit == action_registry.SUITS.MISC then
            result.success = false
            result.description = "Vigilance requires a non-misc suit card."
            return
        end

        if followUpActionDef.suit ~= cardActionSuit then
            result.success = false
            result.description = "Vigilance follow-up suit must match card suit."
            return
        end

        local followUpTargetPolicy = action.followUpTargetPolicy
        if not followUpTargetPolicy then
            if followUpActionDef.targetType == "enemy" then
                followUpTargetPolicy = "trigger_actor"
            elseif followUpActionDef.targetType == "ally" then
                followUpTargetPolicy = "self"
            else
                followUpTargetPolicy = "none"
            end
        end

        self.vigilanceCounter = (self.vigilanceCounter or 0) + 1

        actor.pendingVigilance = {
            card = action.card,
            trigger = action.trigger or action.triggerAction or {
                mode = "targeted_by_hostile_action",
                target = "self",
                hostileOnly = true,
                excludeSelf = true,
            },
            followUpAction = followUpActionType,
            followUpTargetPolicy = followUpTargetPolicy,
            followUpTarget = action.followUpTarget or action.target,
            followUpDestinationZone = action.followUpDestinationZone,
            weapon = action.weapon,
            declaredOrder = self.vigilanceCounter,
        }

        self.eventBus:emit("vigilance_prepared", {
            actor = actor,
            trigger = actor.pendingVigilance.trigger,
            followUpAction = actor.pendingVigilance.followUpAction,
        })

        result.success = true
        result.description = "Vigilance prepared: " ..
            (followUpActionDef.name or followUpActionType) .. "."
        result.effects[#result.effects + 1] = "vigilance_prepared"
    end

    ----------------------------------------------------------------------------
    -- GENERIC RESOLUTION
    ----------------------------------------------------------------------------

    function resolver:getRetreatParticipants(action)
        if type(action.participants) == "table" then
            return action.participants
        end
        if type(action.guild) == "table" then
            return action.guild
        end

        local controller = action.challengeController or self.challengeController
        if controller and type(controller.pcs) == "table" then
            return controller.pcs
        end

        if action.actor then
            return { action.actor }
        end
        return {}
    end

    function resolver:getRetreatTestResults(action)
        if type(action.testResults) == "table" then
            return action.testResults
        end
        if type(action.groupTestResults) == "table" then
            return action.groupTestResults
        end
        if type(action.retreatTests) == "table" then
            return action.retreatTests
        end

        local tests = {}
        if action.highTestResult then
            tests[#tests + 1] = action.highTestResult
        end
        if action.lowTestResult then
            tests[#tests + 1] = action.lowTestResult
        end
        return tests
    end

    function resolver:markRetreatParticipants(participants)
        for _, participant in ipairs(participants or {}) do
            if participant then
                participant.retreated = true
                participant.fledChallenge = true
                participant.conditions = participant.conditions or {}
                participant.conditions.fled = true
            end
        end
    end

    function resolver:finishRetreat(action, result, outcome)
        local participants = self:getRetreatParticipants(action)
        result.participants = participants
        result.retreatOutcome = outcome
        result.escaped = true
        self:markRetreatParticipants(participants)

        local controller = action.challengeController or self.challengeController
        if controller and controller.endChallenge and action.endChallenge ~= false then
            controller:endChallenge("fled", {
                retreat = result,
                participants = participants,
                outcome = "fled",
            })
            result.challengeEnded = true
        end

        self.eventBus:emit("retreat_resolved", {
            actor = action.actor,
            action = action,
            result = result,
            participants = participants,
        })
    end

    function resolver:resolveFlee(action, result)
        result.effects[#result.effects + 1] = "retreat"

        local pursuit = tostring(action.pursuit or action.enemyPursuit or action.pursuitType or ""):lower()
        local mobility = tostring(action.enemyMobility or action.pursuerMobility or ""):lower()

        if action.canRetreat == false or action.escapeImpossible == true or
           action.enemyAutomaticallyCatches == true or action.automaticPursuit == true or
           pursuit == "automatic" or pursuit == "cannot_escape" or mobility == "fast" or mobility == "magical" then
            result.success = false
            result.retreatOutcome = "impossible"
            result.description = "The pursuer is too fast or too magical to escape."
            result.effects[#result.effects + 1] = "retreat_impossible"
            return
        end

        if action.enemyWillNotPursue == true or action.enemyTiedToLair == true or
           pursuit == "none" or pursuit == "no_pursuit" or pursuit == "will_not_pursue" or
           mobility == "slow" or mobility == "awkward" or mobility == "tied_to_lair" then
            result.success = true
            result.description = "The guild retreats; the enemy cannot or will not pursue."
            result.effects[#result.effects + 1] = "retreat_clean"
            result.effects[#result.effects + 1] = "retreat_no_pursuit"
            self:finishRetreat(action, result, "clean")
            return
        end

        local tests = self:getRetreatTestResults(action)
        if #tests == 0 then
            result.success = false
            result.needsGroupTest = true
            result.groupTestAttribute = "pentacles"
            result.description = "Retreat requires a Pentacles group test from the highest and lowest Pentacles adventurers."
            result.effects[#result.effects + 1] = "retreat_group_test_required"
            return
        end

        local group = fate_resolver.resolveGroupTest(tests)
        result.groupTest = group
        result.groupTestAttribute = "pentacles"

        if group.result == fate_resolver.GROUP_RESULTS.SUCCESS then
            result.success = true
            result.description = "The guild gets away cleanly."
            result.effects[#result.effects + 1] = "retreat_clean"
            self:finishRetreat(action, result, "clean")
        elseif group.result == fate_resolver.GROUP_RESULTS.TIGHT_SPOT then
            result.success = true
            result.complication = action.complication or true
            result.description = "The guild escapes, but the GM introduces a complication."
            result.effects[#result.effects + 1] = "retreat_complication"
            self:finishRetreat(action, result, "complication")
        else
            result.success = false
            result.cornered = true
            result.description = "The guild is cornered with no clear path of escape."
            result.effects[#result.effects + 1] = group.result == fate_resolver.GROUP_RESULTS.DISASTER
                and "retreat_disaster" or "retreat_cornered"
        end
    end

    function resolver:resolveTrivialAction(action, result)
        local actor = action.actor
        local intent = normalizeTrivialIntent(action)
        local target = action.target or action.object or action.feature

        result.success = true
        result.effects[#result.effects + 1] = "trivial_action"

        if intent == "drop_prone" or intent == "drop_prone_to_avoid" then
            actor.conditions = actor.conditions or {}
            actor.conditions.prone = true
            result.description = "Dropped prone."
            result.effects[#result.effects + 1] = "dropped_prone"
            result.effects[#result.effects + 1] = "prone"
            return
        end

        if intent == "open_door" or intent == "open" then
            if target then
                target.isOpen = true
                target.open = true
                target.state = action.targetState or "open"
            end
            result.description = "Opened."
            result.effects[#result.effects + 1] = "opened"
            return
        end

        if intent == "throw_lever" or intent == "pull_lever" or intent == "lower_crossbar" then
            if target then
                target.activated = true
                target.state = action.targetState or "activated"
            end
            result.description = "Activated."
            result.effects[#result.effects + 1] = "activated"
            return
        end

        result.description = "Trivial action completed."
    end

    function resolver:resolveGenericAction(action, result)
        local actionDef = action.actionDef or self:getActionDef(action)
        local actionType = self:normalizeActionType(action.type)

        if actionDef and actionDef.autoSuccess then
            result.success = true
        end

        if result.success then
            if actionType == M.ACTION_TYPES.BID_LORE then
                result.description = "Lore bid offered."
                result.effects[#result.effects + 1] = "lore_bid"
            elseif actionType == M.ACTION_TYPES.TRIVIAL_ACTION then
                self:resolveTrivialAction(action, result)
            elseif actionType == M.ACTION_TYPES.PULL_ITEM_BELT then
                result.description = "Pulled item from belt."
                result.effects[#result.effects + 1] = "item_pulled_belt"
            elseif actionType == M.ACTION_TYPES.TEST_FATE then
                result.description = "Test of Fate requested."
            else
                result.description = "Action succeeded!"
            end
        else
            result.description = "Action failed!"
        end
    end

    ----------------------------------------------------------------------------
    -- S7.8: RELOAD ACTION
    ----------------------------------------------------------------------------

    --- Resolve reload action for crossbows
    function resolver:resolveReload(action, result)
        local actor = action.actor
        local weapon = action.weapon

        if not weapon and actor and actor.inventory and actor.inventory.getWieldedWeapon then
            weapon = actor.inventory:getWieldedWeapon()
        end
        if not weapon then
            weapon = actor.weapon
        end

        -- Must have a crossbow equipped
        if not weapon or not M.isWeaponType(weapon, "CROSSBOW") then
            result.success = false
            result.description = "No crossbow to reload!"
            return
        end

        -- Check if already loaded
        if weapon.isLoaded then
            result.success = false
            result.description = "Crossbow is already loaded!"
            return
        end

        -- Reload succeeds (no test required)
        result.success = true
        weapon.isLoaded = true
        result.description = "Crossbow reloaded!"
        result.effects[#result.effects + 1] = "reloaded"
    end

    ----------------------------------------------------------------------------
    -- S6.3/S12.1: ENGAGEMENT SYSTEM
    -- Delegates to zoneSystem as single source of truth
    ----------------------------------------------------------------------------

    --- Form engagement between two entities
    function resolver:formEngagement(entity1, entity2)
        if not entity1 or not entity2 then return end

        -- S12.1: Delegate to zoneSystem
        if self.zoneSystem then
            self.zoneSystem:engage(entity1.id, entity2.id)
        end

        -- Set is_engaged flag on entities (convenience flag)
        entity1.is_engaged = true
        entity2.is_engaged = true

        -- Emit arena event for visual feedback
        self.eventBus:emit("engagement_formed", {
            entity1 = entity1,
            entity2 = entity2,
        })
    end

    --- Break engagement between two specific entities
    function resolver:breakEngagement(entity1, entity2)
        if not entity1 or not entity2 then return end

        -- S12.1: Delegate to zoneSystem
        if self.zoneSystem then
            self.zoneSystem:disengage(entity1.id, entity2.id)
        end

        -- Update is_engaged flag based on remaining engagements
        entity1.is_engaged = self:hasAnyEngagement(entity1)
        entity2.is_engaged = self:hasAnyEngagement(entity2)

        -- Emit arena event for visual feedback
        self.eventBus:emit("engagement_broken", {
            entity1 = entity1,
            entity2 = entity2,
        })
    end

    --- Clear all engagements for an entity (on defeat)
    function resolver:clearAllEngagements(entity, allEntities)
        if not entity then return end

        local engagedIds = {}
        if self.zoneSystem and self.zoneSystem.getEngagedWith then
            for _, id in ipairs(self.zoneSystem:getEngagedWith(entity.id) or {}) do
                engagedIds[#engagedIds + 1] = id
            end
        end
        local wasEngaged = entity.is_engaged or #engagedIds > 0

        -- S12.1: Delegate to zoneSystem
        if self.zoneSystem then
            self.zoneSystem:disengageAll(entity.id)
        end

        entity.is_engaged = false

        if allEntities then
            local engagedSet = {}
            for _, id in ipairs(engagedIds) do
                engagedSet[id] = true
            end

            for _, other in ipairs(allEntities) do
                if other ~= entity and engagedSet[other.id] then
                    other.is_engaged = self:hasAnyEngagement(other)
                end
            end
        end

        if wasEngaged then
            self.eventBus:emit("engagements_cleared", {
                entity = entity,
                engagedIds = engagedIds,
            })
        end
    end

    --- Check if entity has any engagements
    function resolver:hasAnyEngagement(entity)
        if not entity then return false end

        -- S12.1: Delegate to zoneSystem
        if self.zoneSystem then
            return self.zoneSystem:isEngaged(entity.id)
        end
        return false
    end

    --- Check if two entities are engaged
    function resolver:areEngaged(entity1, entity2)
        if not entity1 or not entity2 then return false end

        -- S12.1: Delegate to zoneSystem
        if self.zoneSystem then
            return self.zoneSystem:areEngaged(entity1.id, entity2.id)
        end
        return false
    end

    --- Get all entities engaged with a given entity
    -- @param entity table: The entity to check
    -- @param allEntities table: Array of all entities in the challenge
    -- @return table: Array of engaged entities
    function resolver:getEngagedEnemies(entity, allEntities)
        if not entity then return {} end

        -- S12.1: Get engaged IDs from zoneSystem
        local engagedIds = {}
        if self.zoneSystem then
            engagedIds = self.zoneSystem:getEngagedWith(entity.id)
        end

        -- Convert IDs to entity references
        local enemies = {}
        local idSet = {}
        for _, id in ipairs(engagedIds) do
            idSet[id] = true
        end

        for _, e in ipairs(allEntities or {}) do
            if idSet[e.id] then
                enemies[#enemies + 1] = e
            end
        end
        return enemies
    end

    --- Resolve movement adjacency using zone registry when available,
    -- otherwise fall back to challenge zone data.
    function resolver:getZoneIds(action)
        if self.zoneSystem and self.zoneSystem.getAllZoneIds then
            local ids = self.zoneSystem:getAllZoneIds()
            if ids and #ids > 0 then
                return ids
            end
        end

        local ids = {}
        local zones = action and action.challengeController and action.challengeController.zones
        for _, zone in ipairs(zones or {}) do
            ids[#ids + 1] = zone.id
        end
        return ids
    end

    function resolver:zoneExists(action, zoneId)
        if not zoneId then
            return false
        end

        if self.zoneSystem and self.zoneSystem.getZone and self.zoneSystem:getZone(zoneId) then
            return true
        end

        for _, id in ipairs(self:getZoneIds(action)) do
            if id == zoneId then
                return true
            end
        end

        return false
    end

    function resolver:areZonesAdjacent(action, fromZoneId, toZoneId)
        if self.zoneSystem and self.zoneSystem.getZone and self.zoneSystem.areZonesAdjacent then
            if self.zoneSystem:getZone(fromZoneId) and self.zoneSystem:getZone(toZoneId) then
                return self.zoneSystem:areZonesAdjacent(fromZoneId, toZoneId)
            end
        end

        local zones = action and action.challengeController and action.challengeController.zones
        if not zones or #zones == 0 then
            return true
        end

        local byId = {}
        for _, zone in ipairs(zones) do
            byId[zone.id] = zone
        end

        local fromZone = byId[fromZoneId]
        local toZone = byId[toZoneId]
        if not fromZone or not toZone then
            return false
        end

        if fromZone.adjacent_to then
            for _, adjId in ipairs(fromZone.adjacent_to) do
                if adjId == toZoneId then
                    return true
                end
            end
            return false
        end

        if toZone.adjacent_to then
            for _, adjId in ipairs(toZone.adjacent_to) do
                if adjId == fromZoneId then
                    return true
                end
            end
            return false
        end

        return true
    end

    function resolver:getZoneDistance(action, fromZoneId, toZoneId)
        if not toZoneId then
            return 0, nil
        end
        if not fromZoneId or fromZoneId == toZoneId then
            return 0, nil
        end

        local zoneIds = self:getZoneIds(action)
        if #zoneIds == 0 then
            return 1, nil
        end

        if not self:zoneExists(action, fromZoneId) or not self:zoneExists(action, toZoneId) then
            return nil, "zone_not_found"
        end

        local queue = { { id = fromZoneId, distance = 0 } }
        local seen = { [fromZoneId] = true }
        local index = 1

        while index <= #queue do
            local current = queue[index]
            index = index + 1

            for _, nextId in ipairs(zoneIds) do
                if not seen[nextId] and self:areZonesAdjacent(action, current.id, nextId) then
                    local distance = current.distance + 1
                    if nextId == toZoneId then
                        return distance, nil
                    end
                    seen[nextId] = true
                    queue[#queue + 1] = { id = nextId, distance = distance }
                end
            end
        end

        return nil, "zones_not_connected"
    end

    function resolver:canMoveBetweenZones(action, fromZoneId, toZoneId, opts)
        opts = opts or {}
        local maxDistance = opts.maxDistance or action.maxMoveDistance or 1
        local distance, err = self:getZoneDistance(action, fromZoneId, toZoneId)

        if err then
            return false, err
        end
        if not distance or distance <= maxDistance then
            return true, nil
        end

        return false, "zones_too_far"
    end

    function resolver:getAcrobatTraversalMode(action)
        if not action then
            return nil
        end

        local explicitMode = action.traversalMode or action.traversal or action.movementMode or action.terrainMode
        local mode = explicitMode and normalizeTalentKey(explicitMode) or nil

        if action.climb == true or action.climbing == true or action.verticalTraversal == true then
            mode = mode or "climb"
        elseif action.narrowLedge == true or action.ledge == true then
            mode = mode or "ledge"
        elseif action.tightrope == true then
            mode = mode or "tightrope"
        end

        if action.acrobatTraversal == true or action.requiresAcrobatTraversal == true or action.difficultTraversal == true then
            mode = mode or "difficult_terrain"
        end

        local acrobatModes = {
            climb = true,
            climbing = "climb",
            vertical = "climb",
            vertical_terrain = "climb",
            sheer_surface = "climb",
            ledge = true,
            narrow_ledge = "ledge",
            tightrope = true,
            difficult_terrain = true,
        }
        local mapped = acrobatModes[mode]
        if mapped == true then
            return mode
        end
        if mapped then
            return mapped
        end

        return nil
    end

    function resolver:resolveAcrobatTraversal(action, result)
        local mode = self:getAcrobatTraversalMode(action)
        if not mode then
            return true
        end

        result.acrobatTraversal = {
            mode = mode,
            asMiscAction = true,
            noTestFate = false,
        }

        local testResult = action.traversalTestResult or action.testResult
        if testResult then
            if testResult.success then
                result.effects[#result.effects + 1] = "traversal_test_passed"
                return true
            end

            result.success = false
            result.description = "Traversal failed."
            result.effects[#result.effects + 1] = "traversal_test_failed"
            return false
        end

        if not entityHasUsableTalent(action.actor, "acrobat") then
            result.success = false
            result.description = "Traversal requires a Test of Fate without Acrobat."
            result.effects[#result.effects + 1] = "traversal_test_required"
            result.effects[#result.effects + 1] = "acrobat_traversal_blocked"
            result.traversalRequiresTest = true
            return false
        end

        result.acrobatTraversal.noTestFate = true
        result.effects[#result.effects + 1] = "acrobat_traversal"
        result.effects[#result.effects + 1] = "traversal_no_test"
        return true
    end

    ----------------------------------------------------------------------------
    -- S6.3: PARTING BLOWS
    ----------------------------------------------------------------------------

    --- Check and apply parting blows when entity tries to move while engaged
    -- @param entity table: The moving entity
    -- @param allEntities table: All entities in the challenge
    -- @return table: { blocked = bool, wounds = number, attackers = { ... } }
    function resolver:checkPartingBlows(entity, allEntities)
        local result = {
            blocked = false,
            wounds = 0,
            attackers = {},
        }

        if not entity or not entity.is_engaged then
            return result
        end

        -- S12.1: Get engaged enemies from zoneSystem
        local engagedIds = {}
        if self.zoneSystem then
            engagedIds = self.zoneSystem:getEngagedWith(entity.id)
        end

        -- Convert to a set for fast lookup
        local engagedSet = {}
        for _, id in ipairs(engagedIds) do
            engagedSet[id] = true
        end

        -- Find all engaged enemies in the same zone
        for _, e in ipairs(allEntities or {}) do
            if engagedSet[e.id] and e.zone == entity.zone then
                -- Enemy gets a free parting blow
                result.attackers[#result.attackers + 1] = e
                result.wounds = result.wounds + 1

                -- Emit parting blow event
                self.eventBus:emit(events.EVENTS.PARTING_BLOW, {
                    attacker = e,
                    victim = entity,
                })
            end
        end

        -- Apply wounds to the mover
        if result.wounds > 0 then
            for _ = 1, result.wounds do
                local woundResult = entity:takeWound(false)

                self.eventBus:emit(events.EVENTS.WOUND_TAKEN, {
                    entity = entity,
                    result = woundResult,
                    source = "parting_blow",
                })

                -- Check if mover is incapacitated
                if entity.conditions and entity.conditions.deaths_door then
                    result.blocked = true
                    break
                end
                if entity.conditions and entity.conditions.dead then
                    result.blocked = true
                    break
                end
            end
        end

        return result
    end

    ----------------------------------------------------------------------------
    -- S6.3: MOVE/DASH/AVOID RESOLUTION
    ----------------------------------------------------------------------------

    --- Resolve movement action (subject to parting blows)
    function resolver:resolveMove(action, result, allEntities)
        local actor = action.actor
        local destZone = action.destinationZone
        local oldZone = actor.zone

        -- S7.2: Check for rooted condition
        if actor.conditions and actor.conditions.rooted then
            result.success = false
            result.description = "Rooted! Cannot move."
            result.effects[#result.effects + 1] = "rooted_blocked"
            return
        end

        if not self:resolveAcrobatTraversal(action, result) then
            return
        end

        if destZone then
            local canMove, moveError = self:canMoveBetweenZones(action, oldZone, destZone)
            if not canMove then
                result.success = false
                if moveError == "zone_not_found" then
                    result.description = "Move failed: destination zone is invalid."
                    result.effects[#result.effects + 1] = "zone_not_found"
                else
                    result.description = "Move failed: destination zone is not adjacent."
                    result.effects[#result.effects + 1] = "non_adjacent_move_blocked"
                end
                return
            end
        end

        -- Check for parting blows if engaged
        if actor.is_engaged then
            local partingResult = self:checkPartingBlows(actor, allEntities)

            if partingResult.blocked then
                result.success = false
                result.description = "Movement blocked! "
                if #partingResult.attackers > 0 then
                    result.description = result.description .. "Took " .. partingResult.wounds .. " parting blow(s) and fell!"
                end
                result.effects[#result.effects + 1] = "parting_blow_blocked"
                return
            end

            if partingResult.wounds > 0 then
                result.effects[#result.effects + 1] = "parting_blows"
                result.partingBlows = partingResult
            end
        end

        -- Movement succeeds
        result.success = true
        if destZone then
            if self.zoneSystem and actor and actor.id then
                local placed, err = self.zoneSystem:placeEntity(actor.id, destZone)
                if not placed then
                    result.success = false
                    result.description = "Move failed: destination zone could not be entered."
                    result.effects[#result.effects + 1] = "zone_sync_failed"
                    if err then
                        result.effects[#result.effects + 1] = "zone_sync_error_" .. tostring(err)
                    end
                    return
                end
            end

            actor.zone = destZone
            self:applyGriffinGrabMove(actor, oldZone, destZone, action, result)
            result.description = "Moved to " .. destZone

            -- Emit event for arena view to update display
            self.eventBus:emit("entity_zone_changed", {
                entity = actor,
                oldZone = oldZone,
                newZone = destZone,
            })

            print("[MOVE] " .. (actor.name or actor.id) .. " moved from " .. (oldZone or "?") .. " to " .. destZone)
        else
            result.description = "Movement complete"
        end
        result.effects[#result.effects + 1] = "moved"

        -- Clear engagements (they're now in different zones)
        if actor.is_engaged then
            self:clearAllEngagements(actor)
        end
    end

    --- Resolve Dash action (faster move, still subject to parting blows)
    function resolver:resolveDash(action, result, allEntities)
        local actor = action.actor

        -- S7.2: Check for rooted condition
        if actor.conditions and actor.conditions.rooted then
            result.success = false
            result.description = "Rooted! Cannot dash."
            result.effects[#result.effects + 1] = "rooted_blocked"
            return
        end

        if actor.cannotDash then
            result.success = false
            result.description = "Cannot dash."
            result.effects[#result.effects + 1] = "dash_blocked"
            return
        end

        action.maxMoveDistance = 2

        -- Dash leaves the current zone and can cover up to two zone steps.
        self:resolveMove(action, result, allEntities)

        if result.success then
            result.description = "Dashed! " .. (result.description or "")
            result.effects[#result.effects + 1] = "dashed"
        end
    end

    --- Resolve Avoid action (escape engagement without parting blows)
    function resolver:resolveAvoid(action, result)
        local actor = action.actor
        local card = action.card
        local destinationZone = action.destinationZone

        -- S7.2: Check for rooted condition
        if actor.conditions and actor.conditions.rooted then
            result.success = false
            result.description = "Rooted! Cannot avoid."
            result.effects[#result.effects + 1] = "rooted_blocked"
            return
        end

        if destinationZone then
            local canMove, moveError = self:canMoveBetweenZones(action, actor.zone, destinationZone)
            if not canMove then
                result.success = false
                if moveError == "zone_not_found" then
                    result.description = "Avoid failed: destination zone is invalid."
                    result.effects[#result.effects + 1] = "zone_not_found"
                else
                    result.description = "Avoid failed: destination zone is not adjacent."
                    result.effects[#result.effects + 1] = "non_adjacent_move_blocked"
                end
                return
            end
        end

        local avoidValue = result.testValue or ((card.value or 0) + (actor.pentacles or 0))
        local engagedEnemies = self:getEngagedEnemies(actor, action.allEntities)
        local failures = 0

        for _, enemy in ipairs(engagedEnemies) do
            local enemyInit = self:getTargetInitiative(enemy, action) or (10 + (enemy.pentacles or 0))
            if avoidValue < enemyInit then
                failures = failures + 1

                local woundResult = actor:takeWound(false)
                self.eventBus:emit(events.EVENTS.WOUND_TAKEN, {
                    entity = actor,
                    result = woundResult,
                    source = "avoid_failed",
                })
            end
        end

        result.success = (failures == 0)
        if result.success then
            result.description = "Avoided successfully."
            result.effects[#result.effects + 1] = "avoid_success"
        else
            result.description = "Avoided, but took " .. failures .. " Wound(s)."
            result.effects[#result.effects + 1] = "avoid_failed"
        end

        -- Clear engagements and move regardless of success
        self:clearAllEngagements(actor)

        if destinationZone then
            local oldZone = actor.zone
            if self.zoneSystem and actor and actor.id then
                local placed, err = self.zoneSystem:placeEntity(actor.id, destinationZone)
                if not placed then
                    result.success = false
                    result.description = "Avoid failed: destination zone could not be entered."
                    result.effects[#result.effects + 1] = "zone_sync_failed"
                    if err then
                        result.effects[#result.effects + 1] = "zone_sync_error_" .. tostring(err)
                    end
                    return
                end
            end
            actor.zone = destinationZone
            result.description = result.description .. " Moved to " .. destinationZone

            self.eventBus:emit("entity_zone_changed", {
                entity = actor,
                oldZone = oldZone,
                newZone = destinationZone,
            })
        end
    end

    ----------------------------------------------------------------------------
    -- THE FOOL INTERRUPT (S4.9)
    -- The Fool allows an immediate action out of turn order
    -- Playing The Fool grants a free action with a follow-up card
    ----------------------------------------------------------------------------

    --- Resolve The Fool interrupt
    -- @param action table: { actor, card (The Fool), followUpCard, followUpAction, target }
    -- @param result table: Result to populate
    -- @return table: The result
    function resolver:resolveFoolInterrupt(action, result)
        result.success = true
        result.isFoolInterrupt = true
        result.effects[#result.effects + 1] = "fool_interrupt"

        -- The Fool by itself just grants the interrupt opportunity
        -- If there's a follow-up action specified, resolve that instead
        if action.followUpCard and action.followUpAction then
            -- Create a sub-action using the follow-up card
            local followUpAction = {
                actor = action.actor,
                target = action.target,
                card = action.followUpCard,
                type = action.followUpAction,
                weapon = action.weapon,
            }

            -- Resolve the follow-up action
            local followUpResult = self:resolve(followUpAction)

            -- Merge results
            result.followUpResult = followUpResult
            result.description = "The Fool! Immediate action: " .. (followUpResult.description or "")
            result.damageDealt = followUpResult.damageDealt
            result.isGreat = followUpResult.isGreat

            -- Copy effects from follow-up
            for _, effect in ipairs(followUpResult.effects) do
                result.effects[#result.effects + 1] = effect
            end
        else
            -- No follow-up specified - Fool grants free movement or simple action
            result.description = "The Fool! You may take an immediate action."
            result.effects[#result.effects + 1] = "pending_fool_action"

            -- Emit event for UI to prompt for follow-up action
            self.eventBus:emit("fool_interrupt", {
                actor = action.actor,
                awaitingFollowUp = true,
            })
        end

        -- Attach result
        action.result = result

        return result
    end

    ----------------------------------------------------------------------------
    -- DAMAGE APPLICATION (S7.6: Updated with weapon cleave, S7.7: damage types)
    ----------------------------------------------------------------------------

    function resolver:getIndexedWoundOptions(woundOptions, entity, woundIndex)
        if not woundOptions then
            return nil
        end

        if type(woundOptions) ~= "table" then
            return { choice = woundOptions }
        end

        if entity and entity.id and woundOptions[entity.id] ~= nil then
            return self:getIndexedWoundOptions(woundOptions[entity.id], entity, woundIndex)
        end

        if woundOptions[woundIndex] ~= nil then
            return self:getIndexedWoundOptions(woundOptions[woundIndex], entity, woundIndex)
        end

        return woundOptions
    end

    function resolver:getActionWoundOptions(action, entity)
        if not action then
            return nil
        end

        if action.targetWoundOptions then
            return action.targetWoundOptions
        end
        if action.woundOptions then
            return action.woundOptions
        end
        if action.targetWoundChoices then
            return action.targetWoundChoices
        end
        if action.woundChoices then
            return action.woundChoices
        end
        if action.targetWoundChoice or action.woundChoice or action.targetWoundTalentId or action.woundTalentId then
            return {
                choice = action.targetWoundChoice or action.woundChoice,
                talentId = action.targetWoundTalentId or action.woundTalentId,
                useAegis = action.useAegis,
            }
        end

        return nil
    end

    function resolver:damageOptionsElectAegis(woundOptions, damageContext)
        if damageContext and (damageContext.useAegis == true or damageContext.aegis == true) then
            return true
        end

        if type(woundOptions) ~= "table" then
            return normalizeTalentKey(woundOptions) == "aegis"
        end

        if woundOptions.useAegis == true or woundOptions.aegis == true or woundOptions.aegisShield == true then
            return true
        end

        local choice = normalizeTalentKey(woundOptions.choice or woundOptions.woundChoice)
        return choice == "aegis" or choice == "shield_aegis"
    end

    function resolver:isAegisPhysicalSource(effects, weapon, damageContext)
        if damageContext then
            if damageContext.aegisPhysical ~= nil then
                return damageContext.aegisPhysical == true
            end
            if damageContext.physical ~= nil then
                return damageContext.physical == true
            end

            local source = normalizeTalentKey(damageContext.source or damageContext.damageSource)
            if source == "attack" or source == "trap" or source == "hazard" or source == "physical" then
                return true
            end
        end

        if weapon then
            return true
        end

        for _, effect in ipairs(effects or {}) do
            local normalized = normalizeTalentKey(effect)
            if normalized == "physical" or normalized == "weapon" or normalized == "attack" or
               normalized == "melee" or normalized == "missile" or normalized == "trap" then
                return true
            end
        end

        return false
    end

    function resolver:resolveAegisDamageSubstitution(entity, effects, weapon, woundOptions, damageContext)
        if not entityHasUsableTalent(entity, "aegis") then
            return nil
        end
        if not self:damageOptionsElectAegis(woundOptions, damageContext) then
            return nil
        end
        if not self:isAegisPhysicalSource(effects, weapon, damageContext) then
            return nil
        end

        local shield, location = self:getIntactShield(entity)
        if not shield then
            return nil
        end

        local notchResult = inventory.addNotch(shield)
        local record = {
            entity = entity,
            shield = shield,
            location = location,
            notchResult = notchResult,
            prevented = true,
        }

        effects[#effects + 1] = "aegis_shield_notched"
        effects[#effects + 1] = "aegis_effect_prevented"
        if notchResult == "destroyed" then
            effects[#effects + 1] = "shield_destroyed"
        end

        self.eventBus:emit(events.EVENTS.ITEM_DAMAGE_ABSORBED, {
            entity = entity,
            item = shield,
            itemId = shield.id,
            location = location,
            talent = "aegis",
            notchResult = notchResult,
            destroyed = notchResult == "destroyed",
        })

        return record
    end

    --- Apply damage to an entity
    -- @param entity table: Target entity
    -- @param amount number: Number of wounds
    -- @param effects table: Effect flags (pierce_armor, piercing, critical, etc.)
    -- @param weapon table: Optional weapon for cleave check
    -- @param allEntities table: Optional list of all entities for cleave targeting
    -- @param woundOptions table|string: Optional PC wound choice data for explicit wound selection
    -- @param damageContext table|nil: Optional source metadata, e.g. { source = "attack", useAegis = true }
    function resolver:applyDamage(entity, amount, effects, weapon, allEntities, woundOptions, damageContext)
        effects = effects or {}

        local weaponImmunityKey = self:getWeaponImmunityKey(weapon)
        if self:isMimicTarget(entity) and entity.mimicWeaponImmunityType and
           weaponImmunityKey == entity.mimicWeaponImmunityType then
            effects[#effects + 1] = "mimic_harden_immune"
            self.eventBus:emit("mimic_harden_immune", {
                entity = entity,
                weapon = weapon,
                weaponType = weaponImmunityKey,
            })
            return {
                result = "immune",
                immune = true,
                weaponType = weaponImmunityKey,
            }
        end

        -- S7.7: Determine damage type from effects
        local damageType = "normal"
        for _, eff in ipairs(effects) do
            if eff == "critical" then
                damageType = "critical"
                break
            elseif eff == "piercing" or eff == "pierce_armor" then
                damageType = "piercing"
            end
        end

        local aegisOptions = self:getIndexedWoundOptions(woundOptions, entity, 1)
        local aegisResult = self:resolveAegisDamageSubstitution(entity, effects, weapon, aegisOptions, damageContext)
        if aegisResult then
            print("[DAMAGE] " .. (entity.name or entity.id) .. " uses Aegis; " ..
                  (aegisResult.shield.name or "shield") .. " -> " .. tostring(aegisResult.notchResult))
            return aegisResult
        end

        local wasDefeated = false
        for woundIndex = 1, amount do
            -- Call entity's takeWound with damage type (S7.7)
            local woundResult = entity:takeWound(damageType,
                self:getIndexedWoundOptions(woundOptions, entity, woundIndex))

            print("[DAMAGE] " .. (entity.name or entity.id) .. " takes " .. damageType .. " wound -> " .. (woundResult or "?"))
            print("  Armor: " .. (entity.armorNotches or 0) ..
                  " | Conditions: stag=" .. tostring(entity.conditions and entity.conditions.staggered) ..
                  " inj=" .. tostring(entity.conditions and entity.conditions.injured) ..
                  " dd=" .. tostring(entity.conditions and entity.conditions.deaths_door) ..
                  " dead=" .. tostring(entity.conditions and entity.conditions.dead))

            -- Emit wound event for visual
            self.eventBus:emit(events.EVENTS.WOUND_TAKEN, {
                entity = entity,
                result = woundResult,
                damageType = damageType,
            })

            self:handleConcentrationHurt(entity, woundResult, damageType)

            -- Check for defeat
            if entity.conditions and (entity.conditions.dead or entity.conditions.deaths_door) then
                wasDefeated = true
                if entity.conditions.dead then
                    print("[DEFEAT] " .. (entity.name or entity.id) .. " is DEAD!")
                    local releasedBadLittleHands = self:releaseAllBadLittleHandsItems(entity, "kill")
                    if #releasedBadLittleHands > 0 then
                        effects[#effects + 1] = "bad_little_hands_items_released_on_defeat"
                        self.eventBus:emit("bad_little_hands_items_released", {
                            entity = entity,
                            released = releasedBadLittleHands,
                            reason = "kill",
                        })
                    end
                    -- S6.3: Clear all engagements when defeated
                    self:clearAllEngagements(entity)

                    self.eventBus:emit(events.EVENTS.ENTITY_DEFEATED, {
                        entity = entity,
                    })
                end
                break
            end
        end

        if self:isMimicTarget(entity) and weaponImmunityKey and amount > 0 then
            entity.lastWoundingWeaponType = weaponImmunityKey
            entity.lastWoundingWeaponName = weapon and (weapon.weaponType or weapon.name or weapon.templateId) or weaponImmunityKey
        end

        -- S7.6: Axe Cleave - on defeat, free attack on another enemy in same zone
        if wasDefeated and weapon and M.isWeaponType(weapon, "AXE") and allEntities then
            self:triggerAxeCleave(entity, weapon, allEntities)
        end
    end

    --- S7.6: Trigger axe cleave attack on another enemy in same zone
    function resolver:triggerAxeCleave(defeatedEntity, weapon, allEntities)
        local zone = defeatedEntity.zone
        local cleaveTarget = nil

        -- Find another enemy in the same zone
        for _, e in ipairs(allEntities or {}) do
            if e ~= defeatedEntity and e.zone == zone then
                if not (e.conditions and e.conditions.dead) then
                    -- Prefer enemies over allies
                    if e.isPC ~= defeatedEntity.isPC then
                        cleaveTarget = e
                        break
                    elseif not cleaveTarget then
                        cleaveTarget = e
                    end
                end
            end
        end

        if cleaveTarget then
            print("[CLEAVE] Axe cleaves into " .. (cleaveTarget.name or cleaveTarget.id) .. "!")

            -- Deal 1 wound to cleave target
            self:applyDamage(cleaveTarget, 1, {}, nil, nil)

            -- Emit cleave event for visual feedback
            self.eventBus:emit("axe_cleave", {
                source = defeatedEntity,
                target = cleaveTarget,
            })
        end
    end

    return resolver
end

return M
