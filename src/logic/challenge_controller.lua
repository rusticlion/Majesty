-- challenge_controller.lua
-- Challenge Phase Controller for Majesty
-- Tickets S4.1, S4.6, S4.7: Turn-based state machine with initiative and count-up
--
-- Flow:
-- 1. PRE_ROUND: All entities submit initiative cards (facedown)
-- 2. COUNT_UP: Count from 1-14 (Ace to King), entities act when their card is called
-- 3. Each action: AWAITING_ACTION -> RESOLVING -> VISUAL_SYNC -> MINOR_WINDOW
-- 4. After count reaches 14, new round starts at PRE_ROUND
--
-- The controller PAUSES after each action until UI_SEQUENCE_COMPLETE fires.

local events = require('logic.events')
local vigilance_triggers = require('data.vigilance_triggers')
local constants = require('constants')
local fate_resolver = require('logic.resolver')
local action_registry = require('data.action_registry')
local inventory = require('logic.inventory')
local game_clock = require('logic.game_clock')

local M = {}

--------------------------------------------------------------------------------
-- CHALLENGE STATES
--------------------------------------------------------------------------------
M.STATES = {
    IDLE            = "idle",             -- No challenge active
    STARTING        = "starting",         -- Challenge is initializing
    AMBUSH_RESISTANCE = "ambush_resistance", -- Waiting for Ambusher hue-and-cry election
    PRE_ROUND       = "pre_round",        -- Initiative submission phase (S4.6)
    COUNT_UP        = "count_up",         -- Counting 1-14 for turn order (S4.7)
    AWAITING_ACTION = "awaiting_action",  -- Waiting for active entity to act
    RESOLVING       = "resolving",        -- Processing action result
    VISUAL_SYNC     = "visual_sync",      -- Waiting for UI to complete animation
    MINOR_WINDOW    = "minor_window",     -- Minor action declaration window (paused until resume)
    ENDING          = "ending",           -- Challenge wrapping up
}

--------------------------------------------------------------------------------
-- CHALLENGE OUTCOMES
--------------------------------------------------------------------------------
M.OUTCOMES = {
    VICTORY     = "victory",     -- All enemies defeated
    DEFEAT      = "defeat",      -- All PCs defeated
    FLED        = "fled",        -- Party successfully fled
    TIME_OUT    = "time_out",    -- 14 turns elapsed
    NEGOTIATED  = "negotiated",  -- Combat ended via Banter
}

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------
local MAX_TURNS = 14

M.PROCEDURE_STEPS = {
    {
        index = 0,
        key = "set_scene",
        label = "Set the scene",
        summary = "Frame the Challenge before the round loop begins.",
        timing = "challenge_start",
        responsibilities = {
            "Describe the zones the encounter occupies.",
            "Name the combatants and place them in zones.",
            "Clarify whether either side is surprised or has an ambush advantage.",
            "Announce scenery, position, traps, hazards, or scene special rules before cards are played.",
        },
        runtimeHooks = {
            "startChallenge",
            "resolveSurpriseActions",
            "prepareSceneSpecialRules",
        },
        presentationKeys = {
            "zones",
            "combatants",
            "position",
            "surprise",
            "sceneSpecialRules",
            "sceneHazards",
        },
    },
    {
        index = 1,
        key = "draw_challenge_cards",
        label = "Draw Challenge cards",
        summary = "Each round begins with fresh player Challenge cards and a GM major-arcana hand.",
        timing = "round_start",
        playerCards = {
            deck = "minor_arcana",
            count = 4,
            facedownCardsDoNotReduceDraw = true,
            foolStaysInHand = true,
        },
        gmCards = {
            deck = "major_arcana",
            drawCountSource = "npc_ai.calculateRoundDrawCount",
            basedOn = {
                "enemy type",
                "enemy number",
                "enemy size",
                "elite or lord rank",
                "active round penalties",
            },
        },
        cardsAreSpentOn = {
            "initiative",
            "turn actions",
            "minor actions",
        },
    },
    {
        index = 2,
        key = "play_initiative",
        label = "Play Initiative",
        summary = "Every significant combatant or enemy group commits a facedown Initiative card.",
        timing = "pre_round",
        initiative = {
            facedown = true,
            lowerValuesActSooner = true,
            lowerValuesAreEasierToHit = true,
            revealWhenTargeted = true,
            shieldWinsTies = true,
            resolveCannotModifyInitiative = true,
            sameTypeEnemiesShareCard = true,
            significantEnemiesMayUseIndividualCards = true,
        },
        runtimeHooks = {
            "submitInitiative",
            "triggerNPCInitiative",
            "revealInitiative",
        },
    },
    {
        index = 3,
        key = "take_turns",
        label = "Take turns",
        summary = "Count from Ace through King and resolve each active combatant's turn at their Initiative.",
        timing = "count_up",
        countRange = {
            min = 1,
            max = MAX_TURNS,
            lowLabel = "Ace",
            highLabel = "King",
        },
        turnRules = {
            oneCardPerInitiativeTurn = true,
            oneTurnPerRoundUnlessFool = true,
            interruptActionsDoNotSpendTurn = true,
            skippedTurnsDoNotOpenMinorWindow = true,
            noCardsSkipsTurn = true,
            freeActionsNeedNoCard = {
                "talk in character",
                "move around within a zone unless restrained",
            },
        },
        runtimeHooks = {
            "beginCountUp",
            "advanceCount",
            "startEntityTurn",
            "submitAction",
            "skipTurn",
        },
    },
    {
        index = 4,
        key = "minor_actions",
        label = "Minor actions",
        summary = "After a resolved turn, eligible combatants can declare suited minor actions.",
        timing = "after_turn_action",
        minorRules = {
            playerCardMustMatchSuit = true,
            gmMajorArcanaIgnoreSuit = true,
            greaterDoomsCannotTakeOrdinarySuitedActions = true,
            miscellaneousActionsCannotBeMinor = true,
            actingCombatantCannotMinorAfterTheirTurn = true,
            onlyOneDeclarationPerWindow = true,
            valueUsesCardOnly = true,
            attributesAreNotAdded = true,
        },
        projectVariant = {
            id = "declaration_order_resolution",
            description = "The code resolves minor actions in declaration order by intent instead of modeling full simultaneity.",
        },
        runtimeHooks = {
            "startMinorActionWindow",
            "declareMinorAction",
            "resumeFromMinorWindow",
            "processNextMinorAction",
        },
    },
    {
        index = 5,
        key = "end_round",
        label = "End the round",
        summary = "Discard spent round resources, preserve unresolved facedown actions, and begin the next round if the Challenge continues.",
        timing = "after_count_king",
        cleanup = {
            discardUnusedPlayerChallengeCards = true,
            discardUnusedGMChallengeCards = true,
            discardCurrentInitiativeCards = true,
            facedownActionsRemainInPlay = true,
            foolDrawsShuffleBothDecksBeforeNextDeal = true,
            outOfCardsReshuffleDiscardsAndContinue = true,
        },
        runtimeHooks = {
            "advanceCount",
            "gameClock.endRound",
            "npc_ai.discardRoundInitiativeCards",
            "startNewRound",
        },
    },
}

M.CHALLENGE_PROCEDURE = {
    source = "Core Rules Chapter 7: Challenge Phase",
    sourcePages = "107-115",
    phase = "Challenge",
    loopSteps = { 1, 2, 3, 4, 5 },
    roundValueRange = {
        min = 1,
        max = MAX_TURNS,
        lowLabel = "Ace",
        highLabel = "King",
    },
    steps = M.PROCEDURE_STEPS,
    projectVariants = {
        {
            id = "minor_actions_declaration_order",
            step = "minor_actions",
            description = "Minor actions are resolved in declaration order by intent, per the parity plan's intentional variant.",
        },
    },
}

local function normalizeTalentKey(value)
    return tostring(value or ""):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
end

local function getEntityTalentEntry(entity, talentId)
    local talents = entity and entity.talents
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

local function entityHasUsableTalent(entity, talentId)
    local entry = getEntityTalentEntry(entity, talentId)
    if not entry or entry == false then
        return false
    end
    if type(entry) == "table" then
        return entry.wounded ~= true
    end
    return entry == true
end

local function isMajorArcanaChallengeCard(card)
    local value = tonumber(card and card.value)
    if not value or value < 1 or value > 21 then
        return false
    end
    return card.is_major == true or card.suit == constants.SUITS.MAJOR
end

local function isGreaterDoomCard(card)
    local value = tonumber(card and card.value) or 0
    return isMajorArcanaChallengeCard(card) and value >= 15 and value <= 21
end

local function canGMIgnoreMinorSuit(entity, card)
    return entity and entity.isPC == false and isMajorArcanaChallengeCard(card)
end

local function armorTypeAllowsQuick(armorType)
    local normalized = normalizeTalentKey(armorType)
    return normalized == "" or normalized == "none" or normalized == "light"
end

local function entityWearsLightOrNoArmor(entity)
    if not entity then
        return false
    end

    if not armorTypeAllowsQuick(entity.armorType or entity.wornArmorType) then
        return false
    end

    local actorArmor = entity.armor
    if type(actorArmor) == "table" then
        local props = actorArmor.properties or {}
        if (actorArmor.isArmor or props.armor) and not actorArmor.destroyed then
            if not armorTypeAllowsQuick(actorArmor.armorType or props.armorType) then
                return false
            end
        end
    end

    local inv = entity.inventory
    local belt = inv and inv.getItems and inv:getItems(inventory.LOCATIONS.BELT) or inv and inv.belt or {}
    for _, item in ipairs(belt or {}) do
        local props = item.properties or {}
        if (item.isArmor or props.armor) and not item.destroyed then
            if not armorTypeAllowsQuick(item.armorType or props.armorType) then
                return false
            end
        end
    end

    return true
end

local function getWornIronOrSteelArmor(entity)
    if not entity then
        return nil
    end

    local function isIronOrSteelArmor(item)
        if not item then
            return false
        end
        local props = item.properties or {}
        if not (item.isArmor or props.armor) or item.destroyed then
            return false
        end
        local armorType = normalizeTalentKey(item.armorType or props.armorType or item.material or props.material)
        return armorType == "iron" or armorType == "steel"
    end

    local actorArmor = entity.armor
    if isIronOrSteelArmor(actorArmor) then
        return actorArmor
    end

    local inv = entity.inventory
    local belt = inv and inv.getItems and inv:getItems(inventory.LOCATIONS.BELT) or inv and inv.belt or {}
    for _, item in ipairs(belt or {}) do
        if isIronOrSteelArmor(item) then
            return item
        end
    end

    return nil
end

local function itemIsIntactShield(item)
    if not item or item.destroyed then
        return false
    end

    local props = item.properties or {}
    if item.shield == true or props.shield == true or item.isShield == true or props.isShield == true then
        return true
    end

    local tags = props.tags or item.tags
    if type(tags) == "table" then
        if tags.shield == true then
            return true
        end
        for _, tag in ipairs(tags) do
            if normalizeTalentKey(tag) == "shield" then
                return true
            end
        end
    end

    return normalizeTalentKey(item.type or props.type or item.itemType or props.itemType) == "shield"
end

local function getCarriedIntactShield(entity)
    if not entity then
        return nil
    end

    if itemIsIntactShield(entity.shield) then
        return entity.shield, "shield"
    end

    local inv = entity.inventory
    if inv and inv.getItems then
        for _, location in ipairs({ inventory.LOCATIONS.HANDS, inventory.LOCATIONS.BELT, inventory.LOCATIONS.PACK }) do
            for _, item in ipairs(inv:getItems(location) or {}) do
                if itemIsIntactShield(item) then
                    return item, location
                end
            end
        end
    else
        for _, location in ipairs({ "hands", "belt", "pack" }) do
            for _, item in ipairs((inv and inv[location]) or {}) do
                if itemIsIntactShield(item) then
                    return item, location
                end
            end
        end
    end

    return nil
end

local function spendEntityResolve(entity, amount)
    amount = amount or 1
    if not entity then
        return false, "missing_actor"
    end
    if entity.spendResolve then
        local ok, reason = entity:spendResolve(amount)
        if ok then
            return true, nil
        end
        return false, reason or "not_enough_resolve"
    end
    if type(entity.resolve) == "table" then
        if (entity.resolve.current or 0) < amount then
            return false, "not_enough_resolve"
        end
        entity.resolve.current = entity.resolve.current - amount
        return true, nil
    end
    if type(entity.resolve) == "number" then
        if entity.resolve < amount then
            return false, "not_enough_resolve"
        end
        entity.resolve = entity.resolve - amount
        return true, nil
    end
    return false, "resolve_unavailable"
end

local function getEntityResolveAmount(entity)
    if not entity then
        return 0
    end
    if type(entity.resolve) == "table" then
        return entity.resolve.current or entity.resolve.value or 0
    end
    if type(entity.resolve) == "number" then
        return entity.resolve
    end
    return tonumber(entity.currentResolve or entity.resolveCurrent or entity.resolve_current) or 0
end

local function entityCanSpeak(entity)
    if not entity then
        return false
    end
    local conditions = entity.conditions or {}
    return entity.silenced ~= true and conditions.silenced ~= true and
        conditions.silence ~= true and conditions.muted ~= true
end

local function cloneValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, entry in pairs(value) do
        copy[key] = cloneValue(entry)
    end
    return copy
end

local PROCEDURE_STEP_ALIASES = {
    ["0"] = "set_scene",
    scene = "set_scene",
    set_scene = "set_scene",
    setup = "set_scene",
    start = "set_scene",
    ["1"] = "draw_challenge_cards",
    draw = "draw_challenge_cards",
    draw_cards = "draw_challenge_cards",
    draw_challenge_cards = "draw_challenge_cards",
    challenge_cards = "draw_challenge_cards",
    ["2"] = "play_initiative",
    initiative = "play_initiative",
    play_initiative = "play_initiative",
    ["3"] = "take_turns",
    turn = "take_turns",
    turns = "take_turns",
    take_turns = "take_turns",
    count_up = "take_turns",
    ["4"] = "minor_actions",
    minor = "minor_actions",
    minor_action = "minor_actions",
    minor_actions = "minor_actions",
    ["5"] = "end_round",
    ["end"] = "end_round",
    cleanup = "end_round",
    end_round = "end_round",
    round_end = "end_round",
}

function M.getChallengeProcedure()
    return cloneValue(M.CHALLENGE_PROCEDURE)
end

function M.getChallengeStepDetails(step)
    if step == nil then
        return cloneValue(M.PROCEDURE_STEPS)
    end

    local key = step
    if type(step) == "table" then
        key = step.key or step.id or step.label or step.index or step.step
    end
    if type(key) == "number" then
        key = tostring(key)
    else
        key = tostring(key or ""):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    end

    key = PROCEDURE_STEP_ALIASES[key] or key
    for _, details in ipairs(M.PROCEDURE_STEPS) do
        if details.key == key or tostring(details.index) == key then
            return cloneValue(details)
        end
    end

    return nil
end

local function normalizeList(value)
    if value == nil then
        return {}
    end
    if type(value) ~= "table" then
        return { value }
    end
    if next(value) == nil then
        return {}
    end
    if #value > 0 then
        return value
    end
    return { value }
end

local function sceneRuleId(rule, prefix, index)
    local id = type(rule) == "table" and
        (rule.id or rule.key or rule.name or rule.title or rule.description) or rule
    local slug = normalizeTalentKey(id)
    if slug == "" then
        slug = tostring(prefix or "scene_rule") .. "_" .. tostring(index or 1)
    end
    return slug
end

local function normalizeSceneRule(rawRule, kind, index, defaults)
    defaults = defaults or {}
    local rule = type(rawRule) == "table" and cloneValue(rawRule) or {
        description = tostring(rawRule or ""),
    }
    rule.id = rule.id or sceneRuleId(rule, kind, index)
    rule.kind = rule.kind or kind or "special_rule"
    rule.type = rule.type or rule.kind
    rule.zoneId = rule.zoneId or rule.zone or defaults.zoneId
    rule.zoneName = rule.zoneName or defaults.zoneName
    rule.description = rule.description or rule.text or rule.summary or rule.name or rule.title
    rule.source = rule.source or defaults.source or "challenge_scene"
    return rule
end

local function actionSetHas(actionSet, actionType)
    if actionSet == nil then
        return false
    end
    local wanted = normalizeTalentKey(actionType)
    if wanted == "" then
        return false
    end
    if type(actionSet) == "string" then
        local normalized = normalizeTalentKey(actionSet)
        return normalized == "all" or normalized == wanted
    end
    if type(actionSet) == "table" then
        if actionSet.all == true or actionSet[wanted] == true or actionSet[actionType] == true then
            return true
        end
        for _, value in ipairs(actionSet) do
            local normalized = normalizeTalentKey(value)
            if normalized == "all" or normalized == wanted then
                return true
            end
        end
    end
    return false
end

local function sceneRuleZoneMatches(rule, action)
    local zoneId = rule and (rule.zoneId or rule.zone)
    if not zoneId then
        return true
    end
    zoneId = tostring(zoneId)
    local actor = action and action.actor
    local target = action and action.target

    local function matches(candidate)
        if candidate ~= nil and tostring(candidate) == zoneId then
            return true
        end
        return false
    end

    return matches(action and action.zoneId) or
        matches(action and action.zone) or
        matches(action and action.targetZoneId) or
        matches(action and action.targetZone) or
        matches(action and action.destinationZoneId) or
        matches(action and action.destinationZone) or
        matches(actor and actor.zone) or
        matches(actor and actor.zoneId) or
        matches(target and target.zone) or
        matches(target and target.zoneId)
end

local function entityHasTag(entity, tag)
    local wanted = normalizeTalentKey(tag)
    if wanted == "" then
        return false
    end
    local tags = entity and entity.tags
    if type(tags) == "table" then
        if tags[wanted] == true or tags[tag] == true then
            return true
        end
        for _, value in ipairs(tags) do
            if normalizeTalentKey(value) == wanted then
                return true
            end
        end
    end
    return normalizeTalentKey(entity and (entity.kind or entity.type or entity.species)) == wanted
end

local function addSceneTag(tags, value)
    local normalized = normalizeTalentKey(value)
    if normalized ~= "" then
        tags[normalized] = true
    end
end

local function addSceneTags(tags, values)
    if type(values) ~= "table" then
        addSceneTag(tags, values)
        return
    end

    for key, value in pairs(values) do
        if value == true then
            addSceneTag(tags, key)
        else
            addSceneTag(tags, value)
        end
    end
end

local function getActionWeapon(action)
    if not action then
        return nil
    end
    if action.weapon then
        return action.weapon
    end
    if action.item and (action.item.weaponType or action.item.isWeapon or action.item.isMelee or action.item.isRanged) then
        return action.item
    end
    local inv = action.actor and action.actor.inventory
    if inv and inv.getWieldedWeapon then
        return inv:getWieldedWeapon()
    end
    return nil
end

local function collectItemSceneTags(item)
    local tags = {}
    if not item then
        return tags
    end

    local props = item.properties or {}
    addSceneTags(tags, item.tags)
    addSceneTags(tags, props.tags)
    addSceneTag(tags, item.type or item.itemType or props.type or props.itemType)
    addSceneTag(tags, item.templateId or item.templateID)
    addSceneTag(tags, item.id)
    addSceneTag(tags, item.name)
    addSceneTag(tags, item.toolType or props.toolType)
    addSceneTag(tags, item.material or props.material)

    for key, value in pairs(props) do
        if value == true then
            addSceneTag(tags, key)
        end
    end

    return tags
end

local function collectWeaponSceneTags(weapon)
    local tags = collectItemSceneTags(weapon)
    if not weapon then
        return tags
    end

    local props = weapon.properties or {}
    addSceneTag(tags, weapon.weaponType or props.weaponType)

    local weaponType = normalizeTalentKey(weapon.weaponType or props.weaponType or weapon.type or props.type)
    if weapon.isRanged or props.ranged or weaponType == "bow" or weaponType == "crossbow" or weaponType == "thrown" then
        tags.ranged = true
        tags.missile = true
    end
    if weapon.isMelee or props.melee or (weaponType ~= "" and not tags.ranged) then
        tags.melee = true
    end
    if weaponType == "polearm" or weaponType == "spear" or weaponType == "pike" or weaponType == "halberd" then
        tags.polearm = true
        tags.reach = true
    end

    return tags
end

local function itemHasAnySceneTag(item, wantedTags)
    local tags = normalizeList(wantedTags)
    if #tags == 0 then
        return true
    end

    local itemTags = collectItemSceneTags(item)
    for _, tag in ipairs(tags) do
        if itemTags[normalizeTalentKey(tag)] then
            return true
        end
    end
    return false
end

local function weaponHasAnySceneTag(weapon, wantedTags)
    local tags = normalizeList(wantedTags)
    if #tags == 0 then
        return true
    end

    local weaponTags = collectWeaponSceneTags(weapon)
    for _, tag in ipairs(tags) do
        if weaponTags[normalizeTalentKey(tag)] then
            return true
        end
    end
    return false
end

local function sceneRuleWeaponRestrictionApplies(rule, actionType)
    local weaponActions = rule.weaponRestrictionActions or rule.weaponActions or rule.weaponRestrictedActions
    if weaponActions ~= nil then
        return actionSetHas(weaponActions, actionType)
    end

    local actionFilter = rule.actionTypes or rule.actions or rule.actionType
    if actionFilter ~= nil then
        return actionSetHas(actionFilter, actionType)
    end

    return actionType == "melee" or actionType == "missile"
end

local function sceneRuleWeaponBlock(rule, action, actionType)
    local requiredTags = rule.requiredWeaponTags or rule.requiredWeaponTag or
        rule.allowedWeaponTags or rule.allowedWeaponTypes or rule.allowedWeapons
    local blockedTags = rule.blockedWeaponTags or rule.blockedWeaponTypes or rule.blockedWeapons
    if requiredTags == nil and blockedTags == nil then
        return false, nil
    end
    if not sceneRuleWeaponRestrictionApplies(rule, actionType) then
        return false, nil
    end

    local weapon = getActionWeapon(action)
    if requiredTags ~= nil and not weaponHasAnySceneTag(weapon, requiredTags) then
        return true, rule.weaponBlockReason or rule.blockReason or rule.reason or
            "Scene special rule blocks this weapon."
    end
    if blockedTags ~= nil and weaponHasAnySceneTag(weapon, blockedTags) then
        return true, rule.weaponBlockReason or rule.blockReason or rule.reason or
            "Scene special rule blocks this weapon."
    end

    return false, nil
end

local function sceneRuleItemRestrictionApplies(rule, actionType)
    local itemActions = rule.itemRestrictionActions or rule.itemActions or rule.itemRestrictedActions or
        rule.toolActions or rule.toolRestrictionActions
    if itemActions ~= nil then
        return actionSetHas(itemActions, actionType)
    end

    local actionFilter = rule.actionTypes or rule.actions or rule.actionType
    if actionFilter ~= nil then
        return actionSetHas(actionFilter, actionType)
    end

    local requiredAction = normalizeTalentKey(rule.requiredAction or rule.requiresAction)
    if requiredAction ~= "" then
        return requiredAction == actionType
    end

    return actionType == "move" or actionType == "dash" or actionType == "avoid"
end

local function sceneRuleGateApplies(rule, actionType, actionFields)
    for _, field in ipairs(actionFields or {}) do
        local value = rule[field]
        if value ~= nil then
            return actionSetHas(value, actionType)
        end
    end

    local actionFilter = rule.actionTypes or rule.actions or rule.actionType
    if actionFilter ~= nil then
        return actionSetHas(actionFilter, actionType)
    end

    local requiredAction = normalizeTalentKey(rule.requiredAction or rule.requiresAction)
    if requiredAction ~= "" then
        return requiredAction == actionType
    end

    return actionType == "move" or actionType == "dash" or actionType == "avoid"
end

local SCENE_SUIT_ALIASES = {
    swords = constants.SUITS.SWORDS,
    sword = constants.SUITS.SWORDS,
    pentacles = constants.SUITS.PENTACLES,
    pentacle = constants.SUITS.PENTACLES,
    disks = constants.SUITS.PENTACLES,
    disk = constants.SUITS.PENTACLES,
    discs = constants.SUITS.PENTACLES,
    disc = constants.SUITS.PENTACLES,
    coins = constants.SUITS.PENTACLES,
    coin = constants.SUITS.PENTACLES,
    cups = constants.SUITS.CUPS,
    cup = constants.SUITS.CUPS,
    wands = constants.SUITS.WANDS,
    wand = constants.SUITS.WANDS,
    batons = constants.SUITS.WANDS,
    baton = constants.SUITS.WANDS,
    staves = constants.SUITS.WANDS,
    staff = constants.SUITS.WANDS,
    major = constants.SUITS.MAJOR,
    majors = constants.SUITS.MAJOR,
}

local function normalizeSceneCardSuit(value)
    if type(value) == "table" then
        value = value.suit or value.cardSuit or value.id or value.name
    end
    if type(value) == "number" then
        return value
    end
    if type(value) ~= "string" then
        return nil
    end

    local key = normalizeTalentKey(value)
    if SCENE_SUIT_ALIASES[key] then
        return SCENE_SUIT_ALIASES[key]
    end

    local constantKey = value:upper():gsub("[^%w]+", "_")
    return constants.SUITS[constantKey]
end

local function collectSceneCardSuits(value)
    local suits = {}
    local count = 0

    local function addSuit(entry)
        local suit = normalizeSceneCardSuit(entry)
        if suit and not suits[suit] then
            suits[suit] = true
            count = count + 1
        end
    end

    if value == nil then
        return suits, count
    end
    if type(value) == "table" and value.suit == nil and value.cardSuit == nil and value.id == nil and
       value.name == nil then
        for key, entry in pairs(value) do
            if entry == true then
                addSuit(key)
            else
                addSuit(entry)
            end
        end
    else
        addSuit(value)
    end

    return suits, count
end

local function getActionCardSuit(action)
    local card = action and (action.card or action.selectedCard or action.playedCard or action.fateCard or action.testCard)
    return normalizeSceneCardSuit((card and card.suit) or (action and (action.cardSuit or action.suit)))
end

local function sceneRuleCardSuitBlock(rule, action, actionType)
    local suitSpec = rule.requiredCardSuits or rule.requiredCardSuit or rule.requiredSuits or
        rule.requiredSuit or rule.allowedCardSuits or rule.allowedCardSuit or rule.allowedSuits or
        rule.allowedSuit or rule.cardSuits or rule.cardSuit
    if suitSpec == nil then
        return false, nil
    end
    if not sceneRuleGateApplies(rule, actionType, {
        "cardSuitActions",
        "cardSuitRestrictionActions",
        "suitActions",
        "suitRestrictionActions",
    }) then
        return false, nil
    end

    local allowedSuits, count = collectSceneCardSuits(suitSpec)
    if count == 0 then
        return false, nil
    end

    local actionSuit = getActionCardSuit(action)
    if not actionSuit or not allowedSuits[actionSuit] then
        return true, rule.cardSuitBlockReason or rule.suitBlockReason or rule.blockReason or rule.reason or
            "Scene special rule requires a specific card suit."
    end

    return false, nil
end

local function sceneRuleRequiredFreeHands(rule)
    if rule.requiresBothHandsFree == true or rule.bothHandsFree == true or rule.requiresEmptyHands == true then
        return 2
    end

    local value = rule.requiredFreeHands or rule.minimumFreeHands or rule.minFreeHands
    if value == nil then
        value = rule.requiresFreeHands
    end
    if value == nil then
        value = rule.handsFree or rule.freeHands
    end
    if value == nil or value == false then
        return nil
    end
    if value == true then
        return 1
    end
    if type(value) == "number" then
        return math.max(1, math.floor(value))
    end
    if type(value) == "string" then
        local normalized = normalizeTalentKey(value)
        if normalized == "both" or normalized == "two" or normalized == "both_hands" then
            return 2
        end
        local numeric = tonumber(value)
        if numeric then
            return math.max(1, math.floor(numeric))
        end
        if normalized == "true" or normalized == "yes" or normalized == "one" or normalized == "free" then
            return 1
        end
    end
    return nil
end

local function getActorFreeHands(actor)
    local inv = actor and actor.inventory
    if not inv then
        return 0
    end

    if inv.handsFree then
        local free = inv:handsFree()
        if type(free) == "number" then
            return free
        end
        if free == true then
            return inventory.SLOTS.HANDS
        end
        if free == false then
            return 0
        end
    end
    if inv.availableSlots then
        return inv:availableSlots(inventory.LOCATIONS.HANDS)
    end

    local handLimit = inv.limits and inv.limits.hands or inventory.SLOTS.HANDS
    local used = 0
    local hands = inv.getItems and inv:getItems(inventory.LOCATIONS.HANDS) or inv.hands or {}
    for _, item in ipairs(hands or {}) do
        used = used + (item.stackable and 1 or tonumber(item.size) or 1)
    end
    return math.max(0, handLimit - used)
end

local function sceneRuleHandsBlock(rule, action, actionType)
    local requiredHands = sceneRuleRequiredFreeHands(rule)
    if not requiredHands then
        return false, nil
    end
    if not sceneRuleGateApplies(rule, actionType, {
        "handRestrictionActions",
        "handsRestrictionActions",
        "freeHandActions",
        "freeHandsActions",
    }) then
        return false, nil
    end

    if getActorFreeHands(action and action.actor) < requiredHands then
        return true, rule.handsBlockReason or rule.freeHandsBlockReason or rule.blockReason or rule.reason or
            "Scene special rule requires free hands."
    end

    return false, nil
end

local function findSceneItem(action, tags)
    local function matches(candidate, location)
        if candidate and itemHasAnySceneTag(candidate, tags) then
            return candidate, location
        end
        return nil, nil
    end

    local item, location = matches(action and action.item, action and action.itemLocation)
    if item then return item, location end
    item, location = matches(action and action.requiredItem, action and action.requiredItemLocation)
    if item then return item, location end
    item, location = matches(action and action.tool, action and action.toolLocation)
    if item then return item, location end
    item, location = matches(action and action.gear, action and action.gearLocation)
    if item then return item, location end

    local inv = action and action.actor and action.actor.inventory
    local itemId = action and (action.itemId or action.requiredItemId or action.toolId or action.gearId)
    if itemId and inv and inv.findItem then
        local found, foundLocation = inv:findItem(itemId)
        item, location = matches(found, foundLocation)
        if item then return item, location end
    end

    if inv and inv.findItemByPredicate then
        return inv:findItemByPredicate(function(candidate)
            return itemHasAnySceneTag(candidate, tags)
        end)
    end

    for _, locationName in ipairs({ "hands", "belt", "pack" }) do
        local items = inv and inv[locationName] or {}
        for _, candidate in ipairs(items or {}) do
            item, location = matches(candidate, locationName)
            if item then return item, location end
        end
    end

    return nil, nil
end

local function sceneRuleItemBlock(rule, action, actionType)
    local requiredTags = rule.requiredItemTags or rule.requiredItemTag or rule.requiredToolTags or
        rule.requiredToolTag or rule.requiredGearTags or rule.requiredGearTag or rule.requiredItem or
        rule.requiredTool or rule.requiredGear or rule.requiredItemType or rule.requiredToolType or
        rule.allowedItemTags or rule.allowedToolTags or rule.allowedItem or rule.allowedTool
    local blockedTags = rule.blockedItemTags or rule.blockedItemTag or rule.blockedToolTags or
        rule.blockedToolTag or rule.blockedGearTags or rule.blockedGearTag or rule.blockedItem or
        rule.blockedTool or rule.blockedItemType or rule.blockedToolType
    if requiredTags == nil and blockedTags == nil then
        return false, nil, nil, nil
    end
    if not sceneRuleItemRestrictionApplies(rule, actionType) then
        return false, nil, nil, nil
    end

    local item, location
    if requiredTags ~= nil then
        item, location = findSceneItem(action, requiredTags)
        if not item then
            return true, rule.itemBlockReason or rule.toolBlockReason or rule.blockReason or rule.reason or
                "Scene special rule requires specific gear.", nil, nil
        end
    end

    if blockedTags ~= nil then
        local blockedItem, blockedLocation = findSceneItem(action, blockedTags)
        if blockedItem then
            return true, rule.itemBlockReason or rule.toolBlockReason or rule.blockReason or rule.reason or
                "Scene special rule blocks this gear.", blockedItem, blockedLocation
        end
    end

    return false, nil, item, location
end

local function sceneRuleEntityTagsMatch(rule, action)
    local actorTags = rule.actorTags or rule.actorTag
    for _, tag in ipairs(normalizeList(actorTags)) do
        if not entityHasTag(action and action.actor, tag) then
            return false
        end
    end

    local targetTags = rule.targetTags or rule.targetTag
    for _, tag in ipairs(normalizeList(targetTags)) do
        if not entityHasTag(action and action.target, tag) then
            return false
        end
    end

    return true
end

--------------------------------------------------------------------------------
-- CHALLENGE CONTROLLER FACTORY
--------------------------------------------------------------------------------

--- Create a new ChallengeController
-- @param config table: { eventBus, playerDeck, gmDeck, guild, zoneSystem, gameClock }
-- @return ChallengeController instance
function M.createChallengeController(config)
    config = config or {}

    local controller = {
        eventBus   = config.eventBus or events.globalBus,
        playerDeck = config.playerDeck,
        playerHand = config.playerHand,
        gmDeck     = config.gmDeck,
        actionResolver = config.actionResolver,
        gameClock  = config.gameClock,
        guild      = config.guild or {},  -- PC entities
        zoneSystem = config.zoneSystem,   -- S12.1: Zone registry for engagement tracking

        -- Challenge state
        state           = M.STATES.IDLE,
        currentRound    = 0,          -- Which round of combat (can have multiple)
        activeEntity    = nil,        -- Current acting entity

        -- Combatants
        pcs             = {},         -- PC entities in this challenge
        npcs            = {},         -- NPC/Mob entities in this challenge
        allCombatants   = {},         -- Combined list

        -- Initiative tracking (S4.6)
        initiativeSlots = {},         -- entity.id -> { card, revealed }
        awaitingInitiative = {},      -- Entities that haven't submitted initiative yet

        -- Count-up tracking (S4.7)
        currentCount    = 0,          -- Current initiative count (1-14)
        actedThisRound  = {},         -- entity.id -> true if already acted
        initiativeTieOrder = {},      -- count -> ordered entity ids/refs for tied Initiative declarations

        -- Minor action tracking (S6.4: Declaration Loop)
        -- Intentional design: pending minors resolve in declaration order.
        minorActionTimer    = 0,
        minorActionUsed     = false,
        pendingMinors       = {},     -- Committed minor actions { actor, card, action, target }
        minorWindowActive   = false,  -- True while in minor window (paused)
        resolvingMinors     = false,  -- True while resolving pending minor actions
        pendingVigilanceReactions = {}, -- Triggered vigilance reactions awaiting resolution
        resolvingVigilance = false,     -- True while resolving vigilance reaction queue
        pendingCounterSpellInterrupt = nil, -- Incoming spell currently eligible for Counter-spell
        pendingCounterSpellRestore = nil,   -- Counter-spell interrupt waiting to resume incoming spell
        awaitingCounterSpellDecision = false, -- True while the UI selects or skips an interrupt
        pendingHeavyMetalMachineInterrupt = nil, -- Incoming action eligible for Heavy Metal Machine
        awaitingHeavyMetalMachineDecision = false, -- True while UI selects or skips armor boost
        pendingAegisElection = nil, -- Incoming physical effect eligible for Aegis
        awaitingAegisDecision = false, -- True while UI elects or skips Aegis

        -- Visual sync
        awaitingVisualSync  = false,
        pendingAction       = nil,    -- Action waiting for visual completion

        -- Challenge context
        roomId          = nil,
        zoneId          = nil,
        zones           = nil,        -- Array of zone definitions { id, name, description }
        sceneSpecialRules = {},       -- Authored scene rules from Challenge setup
        sceneHazards    = {},         -- Authored hazard rules from Challenge setup
        zoneSpecialRules = {},        -- zoneId -> scene rules/hazards in that zone
        challengeType   = nil,        -- "combat", "trap", "hazard", "social"
        surprised       = false,      -- True when GM characters ambush the guild
        surpriseResults = {},         -- Pre-challenge automatic GM actions
        ambushResistance = nil,       -- Ambusher talent resistance result, if elected
        pendingAmbusherResistance = nil, -- Start-of-Challenge Ambusher election prompt
        awaitingAmbusherResistanceDecision = false,
        sceneAdvantages = {},         -- Ambush-created scene advantages/special rules
        chickenDoomResults = {},      -- Malediction King stress-test results

        -- Fool interrupt tracking (S4.9)
        pendingFoolRestore = nil,     -- { state, activeEntity } to restore after Fool
        pendingQuickRestore = nil,    -- { state, activeEntity } to restore after Quick!
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    --- Initialize and subscribe to events
    function controller:init()
        -- Listen for visual completion
        self.eventBus:on(events.EVENTS.UI_SEQUENCE_COMPLETE, function(data)
            self:onVisualComplete(data)
        end)

        -- Listen for minor actions
        self.eventBus:on(events.EVENTS.MINOR_ACTION_USED, function(data)
            self:onMinorActionUsed(data)
        end)
    end

    function controller:hasMaledictionFlag(entity, flag)
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

    function controller:getEntityOption(options, entity)
        if type(options) ~= "table" or not entity then
            return options
        end
        return options[entity] or (entity.id and options[entity.id]) or (entity.name and options[entity.name])
    end

    function controller:getChickenDoomTestResult(entity, challengeConfig)
        challengeConfig = challengeConfig or {}
        local tests = challengeConfig.chickenDoomTests or challengeConfig.stressChickenTests
        local testSpec = self:getEntityOption(tests, entity)
        if type(testSpec) == "table" and testSpec.success ~= nil then
            return testSpec
        end

        local cardSpec = testSpec
        if type(testSpec) == "table" then
            cardSpec = testSpec.card or testSpec.testCard
        end
        if not cardSpec then
            local cards = challengeConfig.chickenDoomCards or challengeConfig.stressChickenCards
            cardSpec = self:getEntityOption(cards, entity)
        end
        if not cardSpec and challengeConfig.chickenDoomCard then
            cardSpec = challengeConfig.chickenDoomCard
        end
        if not cardSpec and challengeConfig.stressChickenCard then
            cardSpec = challengeConfig.stressChickenCard
        end

        local deck = challengeConfig.chickenDoomDeck or challengeConfig.stressChickenDeck or self.playerDeck
        if not cardSpec and deck and deck.draw then
            cardSpec = deck:draw()
        end

        if not cardSpec then
            return nil
        end

        local wands = tonumber(entity.wands or (entity.attributes and entity.attributes[constants.SUITS.WANDS])) or 0
        local favor = type(testSpec) == "table" and testSpec.favor or nil
        return fate_resolver.resolveTest(wands, constants.SUITS.WANDS, cardSpec, favor)
    end

    function controller:applyChickenDoomFailure(entity, testResult)
        entity.conditions = entity.conditions or {}
        entity.conditions.chicken = true
        entity.conditions.chickenDoom = true
        entity.chickenDoom = {
            active = true,
            startedRound = (self.currentRound or 0) + 1,
            expiresAfterRound = (self.currentRound or 0) + 1,
            testResult = testResult,
        }
        return entity.chickenDoom
    end

    function controller:resolveStressChickenDooms(challengeConfig)
        local results = {}
        for _, entity in ipairs(self.allCombatants or {}) do
            if not self:isDefeated(entity) and self:hasMaledictionFlag(entity, "stressChickenTest") then
                local testResult = self:getChickenDoomTestResult(entity, challengeConfig)
                local detail = {
                    entity = entity,
                    testResult = testResult,
                    success = testResult and testResult.success == true,
                    result = "resisted",
                }

                if testResult and not testResult.success then
                    detail.result = "chicken"
                    detail.chickenDoom = self:applyChickenDoomFailure(entity, testResult)
                elseif not testResult then
                    detail.result = "test_unavailable"
                end

                results[#results + 1] = detail
                self.eventBus:emit(events.EVENTS.MALEDICTION_CHICKEN_DOOM, detail)
            end
        end

        self.chickenDoomResults = results
        return results
    end

    function controller:clearExpiredChickenDoom(completedRound)
        local cleared = {}
        completedRound = completedRound or self.currentRound or 0

        for _, entity in ipairs(self.allCombatants or {}) do
            local doom = entity.chickenDoom
            if doom and doom.active ~= false and (doom.expiresAfterRound or 0) <= completedRound then
                entity.conditions = entity.conditions or {}
                entity.conditions.chicken = nil
                entity.conditions.chickenDoom = nil
                doom.active = false
                doom.clearedRound = completedRound
                entity.lastChickenDoom = doom
                entity.chickenDoom = nil

                local detail = {
                    entity = entity,
                    round = completedRound,
                    result = "chicken_cleared",
                }
                cleared[#cleared + 1] = detail
                self.eventBus:emit(events.EVENTS.MALEDICTION_CHICKEN_CLEARED, detail)
            end
        end

        return cleared
    end

    function controller:getKnownEntities()
        local entities = {}
        local seen = {}

        local function add(entity)
            if entity and not seen[entity] then
                seen[entity] = true
                entities[#entities + 1] = entity
            end
        end

        for _, collection in ipairs({ self.allCombatants, self.pcs, self.npcs, self.guild }) do
            for _, entity in ipairs(collection or {}) do
                add(entity)
            end
        end

        return entities
    end

    function controller:clearFoolReshuffleConditions(round)
        local expired = {}

        for _, entity in ipairs(self:getKnownEntities()) do
            local durations = entity.conditionDurations
            if durations then
                entity.conditions = entity.conditions or {}
                for condition, duration in pairs(durations) do
                    if duration and duration["until"] == "fool_reshuffle" then
                        entity.conditions[condition] = false
                        if entity[condition] == true then
                            entity[condition] = false
                        end
                        durations[condition] = nil

                        local detail = {
                            entity = entity,
                            condition = condition,
                            timing = "fool_reshuffle",
                            round = round or self.currentRound,
                        }
                        expired[#expired + 1] = detail
                        self.eventBus:emit(events.EVENTS.CONDITION_EXPIRED, detail)
                    end
                end

                if next(durations) == nil then
                    entity.conditionDurations = nil
                end
            end

            local blocks = entity.healingBlocks
            if blocks then
                for i = #blocks, 1, -1 do
                    local block = blocks[i]
                    if block and block["until"] == "fool_reshuffle" then
                        block.active = false
                        table.remove(blocks, i)
                        if entity.healingBlock == block then
                            entity.healingBlock = nil
                        end

                        local detail = {
                            entity = entity,
                            condition = "healing_block",
                            timing = "fool_reshuffle",
                            round = round or self.currentRound,
                            block = block,
                            woundTypes = block.woundTypes,
                        }
                        expired[#expired + 1] = detail
                        self.eventBus:emit(events.EVENTS.CONDITION_EXPIRED, detail)
                    end
                end

                if #blocks == 0 then
                    entity.healingBlocks = nil
                end
            elseif entity.healingBlock and entity.healingBlock["until"] == "fool_reshuffle" then
                local block = entity.healingBlock
                block.active = false
                entity.healingBlock = nil

                local detail = {
                    entity = entity,
                    condition = "healing_block",
                    timing = "fool_reshuffle",
                    round = round or self.currentRound,
                    block = block,
                    woundTypes = block.woundTypes,
                }
                expired[#expired + 1] = detail
                self.eventBus:emit(events.EVENTS.CONDITION_EXPIRED, detail)
            end
        end

        return expired
    end

    function controller:isChickenDoomed(entity)
        local conditions = entity and entity.conditions or {}
        return conditions.chicken == true or conditions.chickenDoom == true or
            (entity and entity.chickenDoom and entity.chickenDoom.active ~= false)
    end

    function controller:registerSceneRule(rule, detail)
        detail = detail or {}
        if not rule then
            return
        end

        self.sceneSpecialRules[#self.sceneSpecialRules + 1] = rule
        if rule.kind == "hazard" or rule.hazard == true then
            self.sceneHazards[#self.sceneHazards + 1] = rule
        end
        local zoneId = rule.zoneId or rule.zone
        if zoneId then
            zoneId = tostring(zoneId)
            self.zoneSpecialRules[zoneId] = self.zoneSpecialRules[zoneId] or {}
            self.zoneSpecialRules[zoneId][#self.zoneSpecialRules[zoneId] + 1] = rule
        end
    end

    function controller:prepareSceneSpecialRules(challengeConfig)
        self.sceneSpecialRules = {}
        self.sceneHazards = {}
        self.zoneSpecialRules = {}

        local index = 0
        local function addRule(rawRule, kind, defaults)
            index = index + 1
            self:registerSceneRule(normalizeSceneRule(rawRule, kind, index, defaults))
        end

        for _, rule in ipairs(normalizeList(challengeConfig.sceneSpecialRules or
            challengeConfig.specialRules or challengeConfig.sceneRules)) do
            addRule(rule, "special_rule", { source = "challenge_scene" })
        end
        for _, rule in ipairs(normalizeList(challengeConfig.sceneHazards or challengeConfig.hazards)) do
            addRule(rule, "hazard", { source = "challenge_scene" })
        end

        for _, zone in ipairs(self.zones or {}) do
            local defaults = {
                zoneId = zone.id,
                zoneName = zone.name,
                source = "zone",
            }
            for _, rule in ipairs(normalizeList(zone.specialRules or zone.sceneRules)) do
                addRule(rule, "special_rule", defaults)
            end
            for _, rule in ipairs(normalizeList(zone.hazards or zone.sceneHazards)) do
                addRule(rule, "hazard", defaults)
            end
        end

        if #self.sceneSpecialRules > 0 then
            self.eventBus:emit("challenge_scene_rules_resolved", {
                roomId = self.roomId,
                zoneId = self.zoneId,
                zones = self.zones,
                sceneSpecialRules = self.sceneSpecialRules,
                sceneHazards = self.sceneHazards,
                zoneSpecialRules = self.zoneSpecialRules,
            })
        end
    end

    function controller:evaluateSceneRules(action, actionType)
        local detail = {
            rules = {},
            effects = {},
            favor = nil,
            blocked = false,
        }
        actionType = normalizeTalentKey(actionType or (action and action.type))

        for _, rule in ipairs(self.sceneSpecialRules or {}) do
            if sceneRuleZoneMatches(rule, action) and sceneRuleEntityTagsMatch(rule, action) then
                local actionMatches = actionSetHas(rule.actionTypes or rule.actions or rule.actionType, actionType)
                local blocked = actionSetHas(rule.blockedActions or rule.blockActionTypes, actionType)
                local requiredAction = normalizeTalentKey(rule.requiredAction or rule.requiresAction)
                if requiredAction ~= "" and requiredAction ~= actionType then
                    blocked = true
                end
                local weaponBlocked, weaponBlockReason = sceneRuleWeaponBlock(rule, action, actionType)
                if weaponBlocked then
                    blocked = true
                end
                local cardSuitBlocked, cardSuitBlockReason = sceneRuleCardSuitBlock(rule, action, actionType)
                if cardSuitBlocked then
                    blocked = true
                end
                local handsBlocked, handsBlockReason = sceneRuleHandsBlock(rule, action, actionType)
                if handsBlocked then
                    blocked = true
                end
                local itemBlocked, itemBlockReason, sceneItem, sceneItemLocation =
                    sceneRuleItemBlock(rule, action, actionType)
                if itemBlocked then
                    blocked = true
                end
                if rule.movementBlocked and (
                    actionType == "move" or actionType == "dash" or actionType == "avoid"
                ) then
                    blocked = true
                end

                local grantsFavor = actionSetHas(rule.favorActions or rule.favorActionTypes, actionType) or
                    (rule.favor == true and actionMatches)
                local grantsDisfavor = actionSetHas(rule.disfavorActions or rule.disfavorActionTypes, actionType) or
                    (rule.disfavor == true and actionMatches)

                if blocked or grantsFavor or grantsDisfavor or actionMatches or sceneItem then
                    detail.rules[#detail.rules + 1] = rule
                    detail.effects[#detail.effects + 1] = rule.kind == "hazard" and "scene_hazard" or
                        "scene_special_rule"
                end

                if blocked then
                    detail.blocked = true
                    detail.blockedRule = rule
                    detail.blockReason = weaponBlockReason or cardSuitBlockReason or handsBlockReason or
                        itemBlockReason or rule.blockReason or rule.reason or
                        "Scene special rule blocks this action"
                    detail.effects[#detail.effects + 1] = "scene_special_rule_blocked"
                    return detail
                end

                if sceneItem then
                    detail.sceneItems = detail.sceneItems or {}
                    detail.sceneItems[#detail.sceneItems + 1] = {
                        rule = rule,
                        item = sceneItem,
                        location = sceneItemLocation,
                    }
                end

                if grantsFavor then
                    detail.favor = true
                    detail.effects[#detail.effects + 1] = "scene_special_rule_favor"
                elseif grantsDisfavor then
                    if detail.favor == true then
                        detail.favor = nil
                    else
                        detail.favor = false
                    end
                    detail.effects[#detail.effects + 1] = "scene_special_rule_disfavor"
                end
            end
        end

        return detail
    end

    ----------------------------------------------------------------------------
    -- CHALLENGE LIFECYCLE
    ----------------------------------------------------------------------------

    --- Start a new challenge
    -- @param config table: { pcs, npcs, roomId, zoneId, challengeType }
    -- @return boolean, string: success, error
    function controller:startChallenge(challengeConfig)
        if self.state ~= M.STATES.IDLE then
            return false, "challenge_already_active"
        end

        challengeConfig = challengeConfig or {}

        -- Set up combatants
        self.pcs = challengeConfig.pcs or self.guild
        self.npcs = challengeConfig.npcs or {}
        self.roomId = challengeConfig.roomId
        self.zoneId = challengeConfig.zoneId
        self.zones = challengeConfig.zones  -- Store zone data for arena view
        self.challengeType = challengeConfig.challengeType or "combat"
        self.initiativeTieOrder = challengeConfig.initiativeTieOrder or challengeConfig.tieOrder or {}
        self.sceneSpecialRules = {}
        self.sceneHazards = {}
        self.zoneSpecialRules = {}
        self.sceneAdvantages = {}

        -- Validate we have combatants
        if #self.pcs == 0 then
            return false, "no_pcs"
        end
        if #self.npcs == 0 and self.challengeType == "combat" then
            return false, "no_npcs"
        end

        self.previousGameClockPhase = nil
        if self.gameClock and self.gameClock.getPhase and self.gameClock.setPhase then
            self.previousGameClockPhase = self.gameClock:getPhase()
            self.gameClock:setPhase(game_clock.PHASES.CHALLENGE)
        end

        -- Build combatant list
        self:buildCombatantList()

        -- Keep zone registry in sync so adjacency checks are authoritative.
        if self.zoneSystem then
            local zones = self.zones
            if not zones or #zones == 0 then
                zones = {}
                if self.zoneId then
                    zones[1] = { id = self.zoneId, name = self.zoneId }
                else
                    zones[1] = { id = "main", name = "Main" }
                end
                self.zones = zones
            end

            self.zoneSystem:setRoomZones(zones)
            self.zoneSystem:clearAllEngagements()

            local fallbackZoneId = (zones[1] and zones[1].id) or self.zoneId
            for _, entity in ipairs(self.allCombatants) do
                local zoneId = entity.zone or fallbackZoneId
                if zoneId then
                    local placed, err = self.zoneSystem:placeEntity(entity.id, zoneId)
                    if not placed and fallbackZoneId then
                        placed, err = self.zoneSystem:placeEntity(entity.id, fallbackZoneId)
                        if placed then
                            zoneId = fallbackZoneId
                        end
                    end
                    if placed then
                        entity.zone = zoneId
                    else
                        print("[Challenge] Warning: could not place " .. tostring(entity.id) .. " in zone (" .. tostring(err) .. ")")
                    end
                end
            end
        end

        self:prepareSceneSpecialRules(challengeConfig)

        -- Initialize state
        self.state = M.STATES.STARTING
        self.currentRound = 0
        self.surprised = challengeConfig.surprised == true
        self.sleepingVulnerable = challengeConfig.sleepingVulnerable == true or
            challengeConfig.sleepingSurprise == true or challengeConfig.surpriseEquipmentInactive == true
        self.surpriseResults = {}
        self.ambushResistance = nil
        self.chickenDoomResults = self:resolveStressChickenDooms(challengeConfig)

        -- Emit start event
        self.eventBus:emit(events.EVENTS.CHALLENGE_START, {
            pcs = self.pcs,
            npcs = self.npcs,
            roomId = self.roomId,
            zones = self.zones,  -- Pass zones to arena view
            challengeType = self.challengeType,
            sceneSpecialRules = self.sceneSpecialRules,
            sceneHazards = self.sceneHazards,
            zoneSpecialRules = self.zoneSpecialRules,
            surprised = self.surprised,
            sleepingVulnerable = self.sleepingVulnerable,
            chickenDoomResults = self.chickenDoomResults,
        })

        if self.surprised and self:wantsAmbusherResistance(challengeConfig) then
            local resistance = self:resolveAmbusherResistance(challengeConfig)
            if resistance and resistance.success then
                self.surprised = false
            end
        elseif self.surprised and self:beginAmbusherResistanceWindow(challengeConfig) then
            return true
        end

        if self.surprised then
            self:resolveSurpriseActions(challengeConfig)
        end

        -- Begin first round (initiative submission)
        self:startNewRound()

        return true
    end

    --- End the current challenge
    -- @param outcome string: One of OUTCOMES
    -- @param data table: Additional outcome data
    function controller:endChallenge(outcome, data)
        data = data or {}
        data.outcome = outcome
        data.finalTurn = self.currentTurn
        data.pcs = self.pcs
        data.npcs = self.npcs

        self.state = M.STATES.ENDING

        -- Emit end event
        self.eventBus:emit(events.EVENTS.CHALLENGE_END, data)

        if self.gameClock and self.gameClock.setPhase then
            self.gameClock:setPhase(self.previousGameClockPhase or game_clock.PHASES.CRAWL)
        end

        -- Reset state
        self:reset()
    end

    function controller:discardFacedownCard(entity, card, reason)
        if not card then
            return false
        end
        local deck = entity and entity.isPC and self.playerDeck or self.gmDeck
        if deck and deck.discard then
            deck:discard(card)
            return true
        end
        return false
    end

    function controller:discardFacedownAction(entity, reason)
        if self.actionResolver and self.actionResolver.discardCurrentFacedownAction then
            return self.actionResolver:discardCurrentFacedownAction(entity, {
                reason = reason or "facedown_voluntarily_discarded",
                challengeController = self,
                playerDeck = self.playerDeck,
                gmDeck = self.gmDeck,
            })
        end

        local result = {
            success = false,
            effects = {},
            description = "No facedown action to discard.",
            discardedFacedownActions = {},
        }

        if entity and entity.pendingDefense then
            local defense = entity.pendingDefense
            entity.pendingDefense = nil
            result.discardedFacedownActions[#result.discardedFacedownActions + 1] = {
                entity = entity,
                type = defense.type or "defense",
                card = defense.card,
                discarded = self:discardFacedownCard(entity, defense.card, reason),
                reason = reason or "facedown_voluntarily_discarded",
            }
        end
        if entity and entity.pendingVigilance then
            local vigilance = entity.pendingVigilance
            entity.pendingVigilance = nil
            result.discardedFacedownActions[#result.discardedFacedownActions + 1] = {
                entity = entity,
                type = "vigilance",
                card = vigilance.card,
                discarded = self:discardFacedownCard(entity, vigilance.card, reason),
                reason = reason or "facedown_voluntarily_discarded",
            }
        end
        if entity and entity.pendingAim then
            local aim = entity.pendingAim
            entity.pendingAim = nil
            result.discardedFacedownActions[#result.discardedFacedownActions + 1] = {
                entity = entity,
                type = "aim",
                card = aim.card,
                discarded = self:discardFacedownCard(entity, aim.card, reason),
                reason = reason or "facedown_voluntarily_discarded",
            }
        end

        result.success = #result.discardedFacedownActions > 0
        if result.success then
            result.description = "Discarded facedown action."
            result.effects[#result.effects + 1] = "facedown_discarded"
        else
            result.effects[#result.effects + 1] = "no_facedown_action"
        end
        return result
    end

    function controller:discardPendingFacedownCards(reason)
        local discarded = {}
        for _, entity in ipairs(self.allCombatants or {}) do
            local defense = entity.pendingDefense
            if defense and defense.card then
                discarded[#discarded + 1] = {
                    entity = entity,
                    type = defense.type or "defense",
                    card = defense.card,
                    discarded = self:discardFacedownCard(entity, defense.card, reason),
                    reason = reason or "challenge_end",
                }
            end
            entity.pendingDefense = nil

            local vigilance = entity.pendingVigilance
            if vigilance and vigilance.card then
                discarded[#discarded + 1] = {
                    entity = entity,
                    type = "vigilance",
                    card = vigilance.card,
                    discarded = self:discardFacedownCard(entity, vigilance.card, reason),
                    reason = reason or "challenge_end",
                }
            end
            entity.pendingVigilance = nil

            local aim = entity.pendingAim
            if aim and aim.card then
                discarded[#discarded + 1] = {
                    entity = entity,
                    type = "aim",
                    card = aim.card,
                    discarded = self:discardFacedownCard(entity, aim.card, reason),
                    reason = reason or "challenge_end",
                }
            end
            entity.pendingAim = nil
        end

        for _, reaction in ipairs(self.pendingVigilanceReactions or {}) do
            if reaction.isVigilanceReaction and reaction.card and not reaction.vigilanceCardDiscarded then
                discarded[#discarded + 1] = self:discardResolvedVigilanceReaction(reaction, reason or "challenge_end")
            end
        end

        if self.actionResolver and self.actionResolver.discardActiveAidCards then
            local aidDiscards = self.actionResolver:discardActiveAidCards(reason or "challenge_end")
            for _, entry in ipairs(aidDiscards or {}) do
                discarded[#discarded + 1] = entry
            end
        end

        return discarded
    end

    function controller:discardResolvedVigilanceReaction(reaction, reason)
        if not reaction or not reaction.isVigilanceReaction or not reaction.card or reaction.vigilanceCardDiscarded then
            return nil
        end

        local discarded = self:discardFacedownCard(reaction.actor, reaction.card, reason or "vigilance_resolved")
        reaction.vigilanceCardDiscarded = discarded
        local entry = {
            entity = reaction.actor,
            type = "vigilance",
            card = reaction.card,
            discarded = discarded,
            reason = reason or "vigilance_resolved",
        }

        self.eventBus:emit("vigilance_card_discarded", entry)
        return entry
    end

    --- Reset controller to idle state
    function controller:reset()
        self.state = M.STATES.IDLE
        self.currentRound = 0
        self.activeEntity = nil

        -- S12.1: Clear all engagements when challenge ends
        if self.zoneSystem then
            self.zoneSystem:clearAllEngagements()
        end

        -- Clear is_engaged flag on all combatants
        self.lastFacedownDiscards = self:discardPendingFacedownCards("challenge_end")
        for _, entity in ipairs(self.allCombatants) do
            entity.is_engaged = false
            entity.pendingVigilance = nil
            entity.pendingAim = nil
        end

        self.pcs = {}
        self.npcs = {}
        self.allCombatants = {}

        -- Initiative tracking
        self.initiativeSlots = {}
        self.awaitingInitiative = {}

        -- Count-up tracking
        self.currentCount = 0
        self.actedThisRound = {}
        self.initiativeTieOrder = {}

        -- Minor action
        self.minorActionTimer = 0
        self.minorActionUsed = false
        self.pendingMinors = {}
        self.minorWindowActive = false
        self.resolvingMinors = false
        self.pendingVigilanceReactions = {}
        self.resolvingVigilance = false

        -- Visual sync
        self.awaitingVisualSync = false
        self.pendingAction = nil
        self.surprised = false
        self.surpriseResults = {}
        self.ambushResistance = nil
        self.pendingAmbusherResistance = nil
        self.awaitingAmbusherResistanceDecision = false
        self.sceneAdvantages = {}
        self.sceneSpecialRules = {}
        self.sceneHazards = {}
        self.zoneSpecialRules = {}
        self.previousGameClockPhase = nil
    end

    ----------------------------------------------------------------------------
    -- COMBATANT MANAGEMENT
    ----------------------------------------------------------------------------

    --- Build the list of all combatants (not ordered - initiative determines order)
    function controller:buildCombatantList()
        self.allCombatants = {}

        -- Add all living PCs
        for _, pc in ipairs(self.pcs) do
            if not self:isDefeated(pc) then
                self.allCombatants[#self.allCombatants + 1] = pc
            end
        end

        -- Add all living NPCs
        for _, npc in ipairs(self.npcs) do
            if not self:isDefeated(npc) then
                self.allCombatants[#self.allCombatants + 1] = npc
            end
        end
    end

    ----------------------------------------------------------------------------
    -- AMBUSH / SURPRISE SETUP (Chapter 7, p. 110)
    ----------------------------------------------------------------------------

    local function normalizeAmbushTactic(value)
        if type(value) ~= "string" then
            return "shank"
        end

        value = value:lower():gsub("^%s+", ""):gsub("%s+$", "")
        value = value:gsub("%s+", "_")

        if value == "advantage" or value == "create_advantage" or value == "tactic_1" then
            return "create_advantage"
        end
        if value == "deprive" or value == "deprive_resources" or value == "resource" or value == "tactic_2" then
            return "deprive_resources"
        end
        if value == "shank" or value == "wound" or value == "attack" or value == "tactic_3" then
            return "shank"
        end

        return value
    end

    local function surpriseActionForNPC(actions, npc, index)
        if type(actions) ~= "table" then
            return {}
        end

        return actions[npc and npc.id] or actions[index] or actions.default or {}
    end

    function controller:getAmbusherResistanceCandidates(options)
        local candidates = {}
        options = options or {}

        for _, pc in ipairs(self.pcs or {}) do
            local usable = entityHasUsableTalent(pc, "ambusher")
            local hasResolve = getEntityResolveAmount(pc) > 0
            if usable and hasResolve then
                candidates[#candidates + 1] = {
                    actor = pc,
                    resolve = getEntityResolveAmount(pc),
                }
            elseif options.includeBlocked and usable then
                candidates[#candidates + 1] = {
                    actor = pc,
                    blocked = true,
                    reason = "resolve_missing",
                    resolve = getEntityResolveAmount(pc),
                }
            elseif options.includeBlocked then
                candidates[#candidates + 1] = {
                    actor = pc,
                    blocked = true,
                    reason = "requires_ambusher",
                    resolve = getEntityResolveAmount(pc),
                }
            end
        end

        return candidates
    end

    function controller:beginAmbusherResistanceWindow(options)
        options = options or {}
        if not self.surprised or options.ambusherResistancePrompt == false or
           options.promptAmbusherResistance == false then
            return false
        end

        local candidates = self:getAmbusherResistanceCandidates(options)
        if #candidates == 0 then
            return false
        end

        self.pendingAmbusherResistance = {
            candidates = candidates,
            challengeConfig = options,
        }
        self.awaitingAmbusherResistanceDecision = true
        self.state = M.STATES.AMBUSH_RESISTANCE

        self.eventBus:emit("ambusher_resistance_available", self.pendingAmbusherResistance)
        return true
    end

    function controller:finishAmbusherResistanceWindow(options)
        options = options or {}
        local pending = self.pendingAmbusherResistance
        local challengeConfig = options.challengeConfig or (pending and pending.challengeConfig) or {}

        self.pendingAmbusherResistance = nil
        self.awaitingAmbusherResistanceDecision = false

        if self.surprised then
            self:resolveSurpriseActions(challengeConfig)
        end

        self:startNewRound()
        return true
    end

    function controller:electAmbusherResistance(actor)
        local pending = self.pendingAmbusherResistance
        if not pending then
            return false, "no_pending_ambusher_resistance"
        end

        local selected = nil
        for _, candidate in ipairs(pending.candidates or {}) do
            if candidate.actor == actor or (candidate.actor and actor and candidate.actor.id == actor.id) then
                selected = candidate.actor
                break
            end
        end

        if not selected then
            return false, "invalid_ambusher"
        end

        local resistance = self:resolveAmbusherResistance({
            resistAmbushWithAmbusher = true,
            ambusherResistActor = selected,
        })
        if resistance and resistance.success then
            self.surprised = false
        end

        self.eventBus:emit("ambusher_resistance_resolved", {
            actor = selected,
            resistance = resistance,
            resisted = resistance and resistance.success == true,
        })

        self:finishAmbusherResistanceWindow({ challengeConfig = pending.challengeConfig })
        return true, resistance
    end

    function controller:skipAmbusherResistance()
        local pending = self.pendingAmbusherResistance
        if not pending then
            return false, "no_pending_ambusher_resistance"
        end

        self.ambushResistance = {
            success = false,
            skipped = true,
            effects = { "ambusher_ambush_resistance", "ambusher_resistance_skipped" },
        }
        self.eventBus:emit("ambusher_resistance_skipped", self.ambushResistance)
        self:finishAmbusherResistanceWindow({ challengeConfig = pending.challengeConfig })
        return true, self.ambushResistance
    end

    function controller:wantsAmbusherResistance(options)
        return options and (
            options.resistAmbushWithAmbusher == true or
            options.ambusherResist == true or
            options.ambusherResistActor ~= nil or
            options.ambusherResistActorId ~= nil
        )
    end

    function controller:findAmbusherResistanceActor(options)
        options = options or {}
        local requestedActor = options.ambusherResistActor
        local requestedId = options.ambusherResistActorId or options.ambusherActorId

        if requestedActor then
            if entityHasUsableTalent(requestedActor, "ambusher") then
                return requestedActor, nil
            end
            return nil, "requires_ambusher"
        end

        for _, pc in ipairs(self.pcs or {}) do
            if requestedId and pc.id ~= requestedId then
                -- Keep looking for the requested actor.
            elseif entityHasUsableTalent(pc, "ambusher") then
                return pc, nil
            elseif requestedId and pc.id == requestedId then
                return nil, "requires_ambusher"
            end
        end

        return nil, requestedId and "ambusher_not_found" or "requires_ambusher"
    end

    function controller:resolveAmbusherResistance(options)
        if not self:wantsAmbusherResistance(options) then
            return nil
        end

        local actor, reason = self:findAmbusherResistanceActor(options)
        local result = {
            success = false,
            actor = actor,
            reason = reason,
            effects = { "ambusher_ambush_resistance" },
        }

        if not actor then
            result.effects[#result.effects + 1] = "ambusher_resistance_blocked"
            self.ambushResistance = result
            self.eventBus:emit("ambush_resistance_failed", result)
            return result
        end

        local ok, spendReason = spendEntityResolve(actor, 1)
        if not ok then
            result.reason = spendReason
            result.effects[#result.effects + 1] = "resolve_missing"
            result.effects[#result.effects + 1] = "ambusher_resistance_blocked"
            self.ambushResistance = result
            self.eventBus:emit("ambush_resistance_failed", result)
            return result
        end

        result.success = true
        result.reason = nil
        result.description = "Ambusher raises a hue and cry before the ambush lands."
        result.effects[#result.effects + 1] = "resolve_spent_for_ambusher"
        result.effects[#result.effects + 1] = "ambush_resisted"
        self.ambushResistance = result
        self.eventBus:emit("ambush_resisted", result)
        return result
    end

    function controller:selectSurpriseTarget(actionSpec, shankedTargets)
        if actionSpec and actionSpec.target then
            return actionSpec.target
        end

        local targetId = actionSpec and (actionSpec.targetId or actionSpec.pcId)
        for _, pc in ipairs(self.pcs or {}) do
            if not self:isDefeated(pc) and (not targetId or pc.id == targetId) and
                not (shankedTargets and shankedTargets[pc.id]) then
                return pc
            end
        end

        return nil
    end

    function controller:resolveSurpriseAction(npc, actionSpec, shankedTargets, surpriseOptions)
        actionSpec = actionSpec or {}
        surpriseOptions = surpriseOptions or {}
        local tactic = normalizeAmbushTactic(actionSpec.tactic or actionSpec.type or actionSpec.action)
        local result = {
            actor = npc,
            tactic = tactic,
            success = true,
            automatic = true,
            effects = {},
            description = actionSpec.description,
        }

        if tactic == "create_advantage" then
            local advantage = {
                actor = npc,
                description = actionSpec.description or actionSpec.advantage or "Ambushers create an advantage.",
                effect = actionSpec.effect,
                zone = actionSpec.zone or (npc and npc.zone),
            }
            self.sceneAdvantages[#self.sceneAdvantages + 1] = advantage
            result.advantage = advantage
            result.effects[#result.effects + 1] = "ambush_advantage"
            result.description = advantage.description
            return result
        end

        local target = self:selectSurpriseTarget(actionSpec, tactic == "shank" and shankedTargets or nil)
        result.target = target

        if not target then
            result.success = false
            result.effects[#result.effects + 1] = "ambush_no_target"
            result.description = "No valid ambush target."
            return result
        end

        target.conditions = target.conditions or {}

        if tactic == "deprive_resources" then
            local resource = actionSpec.resource or actionSpec.deprive or "advantage"
            local condition = actionSpec.condition
            if not condition then
                if resource == "disarm" or resource == "weapon" then
                    condition = "disarmed"
                elseif resource == "extinguish_light" or resource == "light" or resource == "torch" then
                    condition = "light_extinguished"
                elseif resource == "web" or resource == "root" then
                    condition = "rooted"
                end
            end

            if condition then
                target.conditions[condition] = true
                result.condition = condition
            end
            result.resource = resource
            result.effects[#result.effects + 1] = "ambush_deprive_resources"
            result.description = actionSpec.description or "Ambushers deprive the guild of a resource."
            return result
        end

        -- Tactic 3: each attacker deals 1 Wound, but each adventurer can only
        -- be attacked once before the Challenge begins.
        local woundOptions = actionSpec.woundOptions and cloneValue(actionSpec.woundOptions) or {}
        local sleepingVulnerable = surpriseOptions.sleepingVulnerable == true or
            surpriseOptions.sleepingSurprise == true or surpriseOptions.surpriseEquipmentInactive == true or
            actionSpec.sleepingVulnerable == true or actionSpec.sleepingSurprise == true or
            actionSpec.surpriseEquipmentInactive == true
        if sleepingVulnerable then
            woundOptions.ignoreArmor = true
            result.sleepingVulnerable = true
            result.effects[#result.effects + 1] = "sleeping_vulnerable"
            result.effects[#result.effects + 1] = "sleeping_armor_inactive"
            result.effects[#result.effects + 1] = "sleeping_weapons_inactive"
        end
        local woundResult = target.takeWound and target:takeWound(actionSpec.damageType or "normal", woundOptions)
        if shankedTargets and target.id then
            shankedTargets[target.id] = true
        end
        result.woundResult = woundResult
        result.effects[#result.effects + 1] = "ambush_shank"
        result.effects[#result.effects + 1] = "surprise_wound"
        result.description = actionSpec.description or "Ambusher sucker-punches the guild."
        return result
    end

    function controller:resolveSurpriseActions(options)
        options = options or {}
        local results = {}
        local shankedTargets = {}
        local actions = options.surpriseActions or options.ambushActions

        for index, npc in ipairs(options.npcs or self.npcs or {}) do
            if not self:isDefeated(npc) then
                local actionSpec = surpriseActionForNPC(actions, npc, index)
                results[#results + 1] = self:resolveSurpriseAction(npc, actionSpec, shankedTargets, options)
            end
        end

        self.surpriseResults = results
        self.eventBus:emit("challenge_surprise_resolved", {
            pcs = self.pcs,
            npcs = self.npcs,
            results = results,
            sceneAdvantages = self.sceneAdvantages,
            sleepingVulnerable = options.sleepingVulnerable == true or options.sleepingSurprise == true or
                options.surpriseEquipmentInactive == true,
        })

        return results
    end

    ----------------------------------------------------------------------------
    -- ROUND MANAGEMENT (S4.6)
    ----------------------------------------------------------------------------

    --- Start a new round of combat
    function controller:startNewRound()
        self.currentRound = self.currentRound + 1

        -- Check end conditions before starting new round
        local outcome = self:checkEndConditions()
        if outcome then
            self:endChallenge(outcome)
            return
        end

        -- Rebuild combatant list (in case someone died)
        self:buildCombatantList()

        if self.actionResolver and self.actionResolver.applyStinkingCloudRoundStart then
            local roundEffects = self.actionResolver:applyStinkingCloudRoundStart({
                round = self.currentRound,
                combatants = self.allCombatants,
            })
            if roundEffects and #roundEffects > 0 then
                self:buildCombatantList()
                outcome = self:checkEndConditions()
                if outcome then
                    self:endChallenge(outcome)
                    return
                end
            end
        end

        -- Reset round tracking
        self.initiativeSlots = {}
        self.awaitingInitiative = {}
        self.actedThisRound = {}
        self.currentCount = 0

        -- Mark all living combatants as needing initiative
        for _, entity in ipairs(self.allCombatants) do
            self.awaitingInitiative[entity.id] = true
        end

        -- Enter pre-round state
        self.state = M.STATES.PRE_ROUND

        -- Emit event for UI
        self.eventBus:emit("initiative_phase_start", {
            round = self.currentRound,
            combatants = self.allCombatants,
        })

        -- Trigger NPC initiative selection
        for _, entity in ipairs(self.allCombatants) do
            if not entity.isPC then
                self:triggerNPCInitiative(entity)
            end
        end

        print("[Challenge] Round " .. self.currentRound .. " - Awaiting initiative from " .. #self.allCombatants .. " combatants")
    end

    --- Submit initiative card for an entity (S4.6)
    -- @param entity table: The entity submitting
    -- @param card table: The card being used for initiative
    -- @return boolean, string: success, error
    function controller:submitInitiative(entity, card)
        if self.state ~= M.STATES.PRE_ROUND then
            return false, "not_in_pre_round"
        end

        if not entity or not entity.id then
            return false, "invalid_entity"
        end

        if not self.awaitingInitiative[entity.id] then
            return false, "already_submitted"
        end

        if not card then
            return false, "no_card"
        end

        -- Store the initiative card (facedown)
        self.initiativeSlots[entity.id] = {
            card = card,
            revealed = false,
            value = card.value or 0,
        }

        -- Remove from awaiting list
        self.awaitingInitiative[entity.id] = nil

        print("[Initiative] " .. (entity.name or entity.id) .. " submitted: " .. (card.name or "?") .. " (value " .. (card.value or 0) .. ")")

        -- Emit event
        self.eventBus:emit("initiative_submitted", {
            entity = entity,
            -- Don't include card details - it's facedown!
        })

        -- Check if all initiatives are in
        if self:allInitiativesSubmitted() then
            self:beginCountUp()
        end

        return true
    end

    --- Check if all combatants have submitted initiative
    function controller:allInitiativesSubmitted()
        for id, _ in pairs(self.awaitingInitiative) do
            return false  -- At least one is still waiting
        end
        return true
    end

    ----------------------------------------------------------------------------
    -- COUNT-UP SYSTEM (S4.7)
    ----------------------------------------------------------------------------

    --- Begin the count-up phase after all initiatives submitted
    function controller:beginCountUp()
        self.state = M.STATES.COUNT_UP
        self.currentCount = 0

        print("[Challenge] All initiatives submitted. Beginning count-up!")

        self.eventBus:emit("count_up_start", {
            round = self.currentRound,
        })

        -- Start counting
        self:advanceCount()
    end

    --- Advance to the next count value
    function controller:advanceCount()
        -- Check end conditions
        local outcome = self:checkEndConditions()
        if outcome then
            self:endChallenge(outcome)
            return
        end

        self.currentCount = self.currentCount + 1

        -- Round complete when count exceeds 14 (King)
        if self.currentCount > MAX_TURNS then
            print("[Challenge] Round " .. self.currentRound .. " complete!")
            self.eventBus:emit(events.EVENTS.CHALLENGE_ROUND_END, {
                round = self.currentRound,
            })
            self:clearExpiredChickenDoom(self.currentRound)
            if self.actionResolver and self.actionResolver.clearExpiredWraithTangibility then
                self.actionResolver:clearExpiredWraithTangibility(self.currentRound, self.allCombatants)
            end
            if self.gameClock and self.gameClock.endRound then
                local reshuffled = self.gameClock:endRound()
                if reshuffled then
                    self:clearFoolReshuffleConditions(self.currentRound)
                    print("[Challenge] The Fool reshuffled both decks at round end.")
                end
            end
            self:startNewRound()
            return
        end

        -- Emit count event for UI
        self.eventBus:emit("count_up_tick", {
            count = self.currentCount,
            round = self.currentRound,
        })

        -- Find entities whose initiative matches current count
        local actingEntities = self:getEntitiesAtCount(self.currentCount)

        if #actingEntities > 0 then
            -- Start first entity's turn
            self:startEntityTurn(actingEntities[1])
        else
            -- No one acts at this count, continue immediately
            self:advanceCount()
        end
    end

    --- Get all entities whose initiative matches a count value
    function controller:getEntitiesAtCount(count)
        local result = {}
        for _, entity in ipairs(self.allCombatants) do
            if not self:isDefeated(entity) and not self.actedThisRound[entity.id] then
                local slot = self.initiativeSlots[entity.id]
                if slot and slot.value == count then
                    result[#result + 1] = entity
                end
            end
        end
        return self:sortInitiativeTieEntities(result, count)
    end

    function controller:setInitiativeTieOrder(count, order)
        if type(count) == "table" and order == nil then
            self.initiativeTieOrder = count
            return true
        end
        if not count or type(order) ~= "table" then
            return false, "invalid_tie_order"
        end
        self.initiativeTieOrder = self.initiativeTieOrder or {}
        self.initiativeTieOrder[count] = order
        return true
    end

    function controller:getInitiativeTieOrder(count)
        local orders = self.initiativeTieOrder
        if type(orders) ~= "table" then
            return nil
        end
        return orders[count] or orders[tostring(count)]
    end

    function controller:tieOrderTokenMatchesEntity(token, entity)
        if not entity then
            return false
        end
        if token == entity then
            return true
        end
        if type(token) == "string" then
            return token == entity.id or token == entity.name
        end
        if type(token) == "table" then
            return token.entity == entity or token.target == entity or
                (token.id and token.id == entity.id) or
                (token.entityId and token.entityId == entity.id) or
                (token.name and token.name == entity.name)
        end
        return false
    end

    function controller:getInitiativeTieRank(entity, count)
        local order = self:getInitiativeTieOrder(count)
        if type(order) ~= "table" then
            return nil
        end
        for rank, token in ipairs(order) do
            if self:tieOrderTokenMatchesEntity(token, entity) then
                return rank
            end
        end
        return nil
    end

    function controller:sortInitiativeTieEntities(entities, count)
        if type(entities) ~= "table" or #entities <= 1 then
            return entities
        end

        local ranked = {}
        local hasExplicitRank = false
        for index, entity in ipairs(entities) do
            local rank = self:getInitiativeTieRank(entity, count)
            if rank then
                hasExplicitRank = true
            end
            ranked[#ranked + 1] = {
                entity = entity,
                index = index,
                rank = rank or math.huge,
            }
        end

        if not hasExplicitRank then
            return entities
        end

        table.sort(ranked, function(a, b)
            if a.rank ~= b.rank then
                return a.rank < b.rank
            end
            return a.index < b.index
        end)

        for index, entry in ipairs(ranked) do
            entities[index] = entry.entity
        end

        return entities
    end

    function controller:getChallengeCardsForEntity(entity)
        if not entity or not entity.id or not self.playerHand then
            return nil
        end

        local handData = self.playerHand.hands and self.playerHand.hands[entity.id]
        if not handData then
            return nil
        end

        if self.playerHand.getHand then
            return self.playerHand:getHand(entity)
        end

        return handData.cards or {}
    end

    function controller:shouldSkipForNoChallengeCards(entity)
        if not entity or entity.isPC ~= true then
            return false
        end

        local cards = self:getChallengeCardsForEntity(entity)
        return cards ~= nil and #cards == 0
    end

    --- Start a specific entity's turn
    function controller:startEntityTurn(entity)
        self.activeEntity = entity
        self.state = M.STATES.AWAITING_ACTION

        -- Reveal their initiative card
        local slot = self.initiativeSlots[entity.id]
        if slot then
            slot.revealed = true
        end

        -- Emit turn start
        self.eventBus:emit(events.EVENTS.CHALLENGE_TURN_START, {
            count = self.currentCount,
            round = self.currentRound,
            activeEntity = self.activeEntity,
            isPC = self.activeEntity.isPC,
            initiativeCard = slot and slot.card,
        })

        print("[Turn] Count " .. self.currentCount .. ": " .. (entity.name or entity.id) .. "'s turn")

        local resolver = self.actionResolver
        if not resolver then
            local action_resolver = require('logic.action_resolver')
            resolver = action_resolver.createActionResolver({
                eventBus = self.eventBus,
                zoneSystem = self.zoneSystem,
                challengeController = self,
            })
            self.actionResolver = resolver
        end
        if resolver.applyEliteRetributiveStartTurn then
            local retributive = resolver:applyEliteRetributiveStartTurn(entity, self.allCombatants, {
                round = self.currentRound,
                count = self.currentCount,
            })
            self.lastEliteRetributiveResult = retributive
            if retributive and retributive.retributiveHits and #retributive.retributiveHits > 0 then
                self.eventBus:emit("elite_retributive_start_turn", {
                    activeEntity = entity,
                    result = retributive,
                })
                if self:isDefeated(entity) then
                    self:skipTurn(entity, "elite_retributive")
                    return
                end
            end
        end

        if self:isChickenDoomed(self.activeEntity) then
            self:skipTurn(self.activeEntity, "chicken_doom")
            return
        end

        if self:shouldSkipForNoChallengeCards(self.activeEntity) then
            self:skipTurn(self.activeEntity, "no_challenge_cards")
            return
        end

        -- If NPC, trigger AI decision
        if not self.activeEntity.isPC then
            self:triggerNPCAction()
        end
        -- If PC, wait for player input (handled externally)
    end

    --- Called after an entity completes their turn
    function controller:completeTurn()
        if self.activeEntity then
            self.actedThisRound[self.activeEntity.id] = true
        end

        self.activeEntity = nil

        -- Check for more entities at current count
        local moreAtCount = self:getEntitiesAtCount(self.currentCount)
        if #moreAtCount > 0 then
            self:startEntityTurn(moreAtCount[1])
        else
            -- Continue counting
            self:advanceCount()
        end
    end

    --- Check if challenge should end
    -- @return string|nil: Outcome or nil if challenge continues
    function controller:checkEndConditions()
        -- Count surviving PCs
        local survivingPCs = 0
        for _, pc in ipairs(self.pcs) do
            if not self:isDefeated(pc) then
                survivingPCs = survivingPCs + 1
            end
        end

        -- Count surviving NPCs
        local survivingNPCs = 0
        for _, npc in ipairs(self.npcs) do
            if not self:isDefeated(npc) then
                survivingNPCs = survivingNPCs + 1
            end
        end

        -- All NPCs defeated = victory
        if survivingNPCs == 0 and #self.npcs > 0 then
            return M.OUTCOMES.VICTORY
        end

        -- All PCs defeated = defeat
        if survivingPCs == 0 then
            return M.OUTCOMES.DEFEAT
        end

        return nil
    end

    --- Check if an entity is defeated
    function controller:isDefeated(entity)
        if not entity then return true end
        if entity.conditions and entity.conditions.dead then
            return true
        end
        if entity.conditions and entity.conditions.deaths_door then
            return true
        end
        if entity.conditions and (entity.conditions.knocked_out or entity.conditions.knockout) then
            return true
        end
        return false
    end

    ----------------------------------------------------------------------------
    -- ACTION HANDLING
    ----------------------------------------------------------------------------

    --- Check if two entities are hostile to each other
    function controller:areHostile(entityA, entityB)
        if not entityA or not entityB then
            return false
        end
        if entityA == entityB then
            return false
        end
        return entityA.isPC ~= entityB.isPC
    end

    function controller:isCounterSpellIncomingAction(action)
        if not action or action.countered or action.fizzled or action.counterSpellBlocked == true then
            return false
        end

        local actionType = normalizeTalentKey(action.type or action.id)
        return actionType == "speak_incantation" or action.spellId ~= nil or
            action.spell ~= nil or action.incomingSpell ~= nil
    end

    function controller:getCounterSpellCandidateEntities()
        local candidates = {}
        local seen = {}

        local function add(entity)
            if not entity then
                return
            end
            local key = entity.id or entity
            if seen[key] then
                return
            end
            seen[key] = true
            candidates[#candidates + 1] = entity
        end

        for _, entity in ipairs(self.allCombatants or {}) do
            add(entity)
        end
        for _, entity in ipairs(self.pcs or {}) do
            add(entity)
        end
        for _, entity in ipairs(self.guild or {}) do
            add(entity)
        end

        return candidates
    end

    function controller:canCounterSpellIncoming(counterer, card, incomingAction, opts)
        opts = opts or {}
        if not self:isCounterSpellIncomingAction(incomingAction) then
            return false, "incoming_spell_required"
        end
        if not counterer then
            return false, "missing_counterspeller"
        end
        if counterer == incomingAction.actor or
           (counterer.id and incomingAction.actor and counterer.id == incomingAction.actor.id) then
            return false, "cannot_counter_own_spell"
        end
        if opts.allowAlliedCounterspell ~= true and not self:areHostile(counterer, incomingAction.actor) then
            return false, "requires_enemy_spell"
        end
        if not entityHasUsableTalent(counterer, "counter_spell") then
            return false, "requires_counter_spell"
        end
        if not entityCanSpeak(counterer) then
            return false, "counter_spell_silenced"
        end
        if getEntityResolveAmount(counterer) < 1 then
            return false, "resolve_missing"
        end
        if incomingAction.canPerceiveCasting == false or incomingAction.canPerceiveCaster == false or
           opts.canPerceiveCasting == false or opts.canPerceiveCaster == false then
            return false, "counter_spell_caster_unseen"
        end
        if card then
            local cardSuit = action_registry.cardSuitToActionSuit(card.suit)
            if cardSuit ~= action_registry.SUITS.WANDS then
                return false, "requires_wands_card"
            end
        elseif opts.requireCard ~= false then
            return false, "card_required"
        end

        return true, nil
    end

    function controller:getCounterSpellInterruptCandidates(incomingAction, opts)
        local candidates = {}
        if not self:isCounterSpellIncomingAction(incomingAction) then
            return candidates
        end

        opts = opts or {}
        for _, entity in ipairs(self:getCounterSpellCandidateEntities()) do
            local ok, reason = self:canCounterSpellIncoming(entity, nil, incomingAction, {
                allowAlliedCounterspell = opts.allowAlliedCounterspell,
                canPerceiveCasting = opts.canPerceiveCasting,
                canPerceiveCaster = opts.canPerceiveCaster,
                requireCard = false,
            })
            if ok then
                candidates[#candidates + 1] = {
                    actor = entity,
                    counterer = entity,
                    incomingAction = incomingAction,
                    spellCaster = incomingAction.actor,
                }
            elseif opts.includeBlocked then
                candidates[#candidates + 1] = {
                    actor = entity,
                    counterer = entity,
                    incomingAction = incomingAction,
                    spellCaster = incomingAction.actor,
                    blocked = true,
                    reason = reason,
                }
            end
        end

        return candidates
    end

    function controller:actionTargetsEntity(action, entity)
        if not action or not entity then
            return false
        end

        local entityId = entity.id
        local function matches(candidate)
            if not candidate then
                return false
            end
            return candidate == entity or (entityId and candidate.id == entityId)
        end

        if matches(action.target) or matches(action.defender) or matches(action.victim) then
            return true
        end

        local targets = action.targets or action.targetEntities
        if type(targets) == "table" then
            for _, target in ipairs(targets) do
                if matches(target) then
                    return true
                end
            end
        end

        return false
    end

    function controller:isHeavyMetalMachineIncomingAction(action)
        if not action or action.countered or action.fizzled then
            return false
        end
        local actionType = normalizeTalentKey(action.type or action.id)
        if actionType == "heavy_metal_machine" or actionType == "counter_spell" then
            return false
        end
        return action.target ~= nil or action.defender ~= nil or action.victim ~= nil or
            action.targets ~= nil or action.targetEntities ~= nil
    end

    function controller:canUseHeavyMetalMachineInterrupt(entity, card, incomingAction, opts)
        opts = opts or {}
        if not self:isHeavyMetalMachineIncomingAction(incomingAction) then
            return false, "incoming_action_required"
        end
        if not entity then
            return false, "missing_actor"
        end
        if not self:actionTargetsEntity(incomingAction, entity) then
            return false, "requires_targeted_action"
        end
        if incomingAction.actor == entity or
           (incomingAction.actor and entity.id and incomingAction.actor.id == entity.id) then
            return false, "cannot_interrupt_own_action"
        end
        if not entityHasUsableTalent(entity, "heavy_metal_machine") then
            return false, "requires_heavy_metal_machine"
        end

        local armor = getWornIronOrSteelArmor(entity)
        if not armor then
            return false, "requires_iron_or_steel_armor"
        end

        local slot = self.getInitiativeSlot and self:getInitiativeSlot(entity.id)
        if not slot then
            return false, "initiative_required"
        end

        local round = self.currentRound or incomingAction.round or incomingAction.currentRound or 0
        if entity.heavyMetalMachineUsedRound == round then
            return false, "heavy_metal_machine_spent"
        end

        if opts.requireCard ~= false and not card then
            return false, "card_required"
        end

        return true, nil, armor
    end

    function controller:getHeavyMetalMachineInterruptCandidates(incomingAction, opts)
        local candidates = {}
        if not self:isHeavyMetalMachineIncomingAction(incomingAction) then
            return candidates
        end

        opts = opts or {}
        local hand = opts.playerHand or self.playerHand
        local requireHandCard = opts.requireHandCard ~= false

        for _, entity in ipairs(self:getCounterSpellCandidateEntities()) do
            local hasCard = true
            if requireHandCard then
                local cards = hand and hand.getHand and hand:getHand(entity) or nil
                hasCard = cards and #cards > 0
            end

            local ok, reason, armor = false, "card_required", nil
            if hasCard then
                ok, reason, armor = self:canUseHeavyMetalMachineInterrupt(entity, nil, incomingAction, {
                    requireCard = false,
                })
            end

            if ok then
                candidates[#candidates + 1] = {
                    actor = entity,
                    defender = entity,
                    incomingAction = incomingAction,
                    incomingActor = incomingAction.actor,
                    armor = armor,
                }
            elseif opts.includeBlocked then
                candidates[#candidates + 1] = {
                    actor = entity,
                    defender = entity,
                    incomingAction = incomingAction,
                    incomingActor = incomingAction.actor,
                    blocked = true,
                    reason = reason,
                }
            end
        end

        return candidates
    end

    function controller:announceHeavyMetalMachineInterrupts(incomingAction, opts)
        local candidates = self:getHeavyMetalMachineInterruptCandidates(incomingAction, opts)
        if #candidates == 0 then
            self.pendingHeavyMetalMachineInterrupt = nil
            return 0
        end

        incomingAction.heavyMetalMachinePromptPending = true
        self.pendingHeavyMetalMachineInterrupt = {
            incomingAction = incomingAction,
            incomingActor = incomingAction.actor,
            candidates = candidates,
            round = self.currentRound,
            count = self.currentCount,
        }

        self.eventBus:emit("heavy_metal_machine_interrupt_available", self.pendingHeavyMetalMachineInterrupt)
        return #candidates
    end

    function controller:beginHeavyMetalMachineInterruptWindow(incomingAction, opts)
        if not incomingAction then
            return false
        end
        if incomingAction.heavyMetalMachineIncomingEmitted or
           (incomingAction.heavyMetalMachineDecisionResolved and not incomingAction.heavyMetalMachinePromptPending) then
            return false
        end

        local count = self:announceHeavyMetalMachineInterrupts(incomingAction, opts)
        if count == 0 then
            return false
        end

        self.awaitingHeavyMetalMachineDecision = true
        self.state = M.STATES.RESOLVING
        self.pendingAction = incomingAction

        self.eventBus:emit("heavy_metal_machine_interrupt_pause", self.pendingHeavyMetalMachineInterrupt)
        return true
    end

    function controller:isAegisIncomingAction(action)
        if not action or action.countered or action.fizzled then
            return false
        end
        if action.aegisElectionResolved == true then
            return false
        end
        if action.useAegis == true and
           not (self.pendingAegisElection and self.pendingAegisElection.incomingAction == action) then
            return false
        end

        local actionType = normalizeTalentKey(action.type or action.id)
        if actionType == "counter_spell" or actionType == "heavy_metal_machine" then
            return false
        end
        if action.aegisPhysical == false or action.physicalSource == false then
            return false
        end
        if action.aegisPhysical == true or action.physicalSource == true or action.trap == true then
            return true
        end

        return actionType == "melee" or actionType == "missile" or actionType == "attack" or
            actionType == "use_item"
    end

    function controller:canElectAegisForIncoming(entity, incomingAction)
        if not self:isAegisIncomingAction(incomingAction) then
            return false, "incoming_physical_effect_required"
        end
        if not entity then
            return false, "missing_actor"
        end
        if not self:actionTargetsEntity(incomingAction, entity) then
            return false, "requires_targeted_effect"
        end
        if not entityHasUsableTalent(entity, "aegis") then
            return false, "requires_aegis"
        end

        local shield, location = getCarriedIntactShield(entity)
        if not shield then
            return false, "requires_intact_shield"
        end

        return true, nil, shield, location
    end

    function controller:getAegisElectionCandidates(incomingAction, opts)
        local candidates = {}
        if not self:isAegisIncomingAction(incomingAction) then
            return candidates
        end

        opts = opts or {}
        for _, entity in ipairs(self:getCounterSpellCandidateEntities()) do
            local ok, reason, shield, location = self:canElectAegisForIncoming(entity, incomingAction)
            if ok then
                candidates[#candidates + 1] = {
                    actor = entity,
                    defender = entity,
                    incomingAction = incomingAction,
                    incomingActor = incomingAction.actor,
                    shield = shield,
                    shieldLocation = location,
                }
            elseif opts.includeBlocked then
                candidates[#candidates + 1] = {
                    actor = entity,
                    defender = entity,
                    incomingAction = incomingAction,
                    incomingActor = incomingAction.actor,
                    blocked = true,
                    reason = reason,
                }
            end
        end

        return candidates
    end

    function controller:announceAegisElection(incomingAction, opts)
        local candidates = self:getAegisElectionCandidates(incomingAction, opts)
        if #candidates == 0 then
            self.pendingAegisElection = nil
            return 0
        end

        incomingAction.aegisPromptPending = true
        self.pendingAegisElection = {
            incomingAction = incomingAction,
            incomingActor = incomingAction.actor,
            candidates = candidates,
            round = self.currentRound,
            count = self.currentCount,
        }

        self.eventBus:emit("aegis_election_available", self.pendingAegisElection)
        return #candidates
    end

    function controller:beginAegisElectionWindow(incomingAction, opts)
        if not incomingAction then
            return false
        end
        if incomingAction.aegisIncomingEmitted or
           (incomingAction.aegisDecisionResolved and not incomingAction.aegisPromptPending) then
            return false
        end

        local count = self:announceAegisElection(incomingAction, opts)
        if count == 0 then
            return false
        end

        self.awaitingAegisDecision = true
        self.state = M.STATES.RESOLVING
        self.pendingAction = incomingAction

        self.eventBus:emit("aegis_election_pause", self.pendingAegisElection)
        return true
    end

    function controller:beginIncomingActionInterruptWindow(incomingAction, opts)
        if self:beginCounterSpellInterruptWindow(incomingAction, opts) then
            return true
        end
        if self:beginHeavyMetalMachineInterruptWindow(incomingAction, opts) then
            return true
        end
        if self:beginAegisElectionWindow(incomingAction, opts) then
            return true
        end
        return false
    end

    function controller:announceCounterSpellInterrupts(incomingAction, opts)
        local candidates = self:getCounterSpellInterruptCandidates(incomingAction, opts)
        if #candidates == 0 then
            self.pendingCounterSpellInterrupt = nil
            return 0
        end

        incomingAction.counterSpellPromptPending = true
        self.pendingCounterSpellInterrupt = {
            incomingAction = incomingAction,
            spellCaster = incomingAction.actor,
            candidates = candidates,
            round = self.currentRound,
            count = self.currentCount,
        }

        self.eventBus:emit("counter_spell_interrupt_available", self.pendingCounterSpellInterrupt)
        return #candidates
    end

    function controller:beginCounterSpellInterruptWindow(incomingAction, opts)
        local count = self:announceCounterSpellInterrupts(incomingAction, opts)
        if count == 0 then
            return false
        end

        if incomingAction.counterSpellIncomingEmitted then
            return true
        end

        if self.pendingCounterSpellRestore and
           self.pendingCounterSpellRestore.incomingAction == incomingAction then
            return true
        end

        if incomingAction.counterSpellDecisionResolved and
           not incomingAction.counterSpellPromptPending then
            return false
        end

        self.awaitingCounterSpellDecision = true
        self.state = M.STATES.RESOLVING
        self.pendingAction = incomingAction

        self.eventBus:emit("counter_spell_interrupt_pause", self.pendingCounterSpellInterrupt)
        return true
    end

    function controller:resolveCounterSpellPendingIncoming(incomingAction)
        local pending = self.pendingCounterSpellInterrupt
        local action = incomingAction or (pending and pending.incomingAction)
        if not action then
            return false, "no_pending_counter_spell"
        end
        if action.counterSpellIncomingEmitted then
            return false, "incoming_already_emitted"
        end

        action.counterSpellDecisionResolved = true
        action.counterSpellPromptPending = false
        action.counterSpellIncomingEmitted = true

        if pending and pending.incomingAction == action then
            self.pendingCounterSpellInterrupt = nil
        end
        self.awaitingCounterSpellDecision = false

        self.state = M.STATES.RESOLVING
        self.pendingAction = action

        self.eventBus:emit("counter_spell_interrupt_resolved", {
            incomingAction = action,
            spellCaster = action.actor,
            countered = action.countered == true or action.fizzled == true,
        })

        if not action.countered and not action.fizzled then
            if self:beginHeavyMetalMachineInterruptWindow(action) then
                return true, action
            end
            if self:beginAegisElectionWindow(action) then
                return true, action
            end
        end

        self.eventBus:emit(events.EVENTS.CHALLENGE_ACTION, action)

        return true, action
    end

    function controller:skipCounterSpellInterrupt(incomingAction)
        local pending = self.pendingCounterSpellInterrupt
        local action = incomingAction or (pending and pending.incomingAction)
        if not action then
            return false, "no_pending_counter_spell"
        end

        action.counterSpellSkipped = true
        self.eventBus:emit("counter_spell_interrupt_skipped", {
            incomingAction = action,
            spellCaster = action.actor,
        })

        return self:resolveCounterSpellPendingIncoming(action)
    end

    function controller:resolveHeavyMetalMachinePendingIncoming(incomingAction)
        local pending = self.pendingHeavyMetalMachineInterrupt
        local action = incomingAction or (pending and pending.incomingAction)
        if not action then
            return false, "no_pending_heavy_metal_machine"
        end
        if action.heavyMetalMachineIncomingEmitted then
            return false, "incoming_already_emitted"
        end

        action.heavyMetalMachineDecisionResolved = true
        action.heavyMetalMachinePromptPending = false
        action.heavyMetalMachineIncomingEmitted = true

        if pending and pending.incomingAction == action then
            self.pendingHeavyMetalMachineInterrupt = nil
        end
        self.awaitingHeavyMetalMachineDecision = false

        self.state = M.STATES.RESOLVING
        self.pendingAction = action

        self.eventBus:emit("heavy_metal_machine_interrupt_resolved", {
            incomingAction = action,
            incomingActor = action.actor,
            played = action.heavyMetalMachineInterruptPlayed == true,
        })

        if self:beginAegisElectionWindow(action) then
            return true, action
        end

        self.eventBus:emit(events.EVENTS.CHALLENGE_ACTION, action)

        return true, action
    end

    function controller:skipHeavyMetalMachineInterrupt(incomingAction)
        local pending = self.pendingHeavyMetalMachineInterrupt
        local action = incomingAction or (pending and pending.incomingAction)
        if not action then
            return false, "no_pending_heavy_metal_machine"
        end

        action.heavyMetalMachineSkipped = true
        self.eventBus:emit("heavy_metal_machine_interrupt_skipped", {
            incomingAction = action,
            incomingActor = action.actor,
        })

        return self:resolveHeavyMetalMachinePendingIncoming(action)
    end

    function controller:resolveAegisPendingIncoming(incomingAction)
        local pending = self.pendingAegisElection
        local action = incomingAction or (pending and pending.incomingAction)
        if not action then
            return false, "no_pending_aegis"
        end
        if action.aegisIncomingEmitted then
            return false, "incoming_already_emitted"
        end

        action.aegisDecisionResolved = true
        action.aegisPromptPending = false
        action.aegisIncomingEmitted = true

        if pending and pending.incomingAction == action then
            self.pendingAegisElection = nil
        end
        self.awaitingAegisDecision = false

        self.state = M.STATES.RESOLVING
        self.pendingAction = action

        self.eventBus:emit("aegis_election_resolved", {
            incomingAction = action,
            incomingActor = action.actor,
            elected = action.useAegis == true,
            defender = action.aegisActor,
        })
        self.eventBus:emit(events.EVENTS.CHALLENGE_ACTION, action)

        return true, action
    end

    function controller:skipAegisElection(incomingAction)
        local pending = self.pendingAegisElection
        local action = incomingAction or (pending and pending.incomingAction)
        if not action then
            return false, "no_pending_aegis"
        end

        action.aegisSkipped = true
        self.eventBus:emit("aegis_election_skipped", {
            incomingAction = action,
            incomingActor = action.actor,
        })

        return self:resolveAegisPendingIncoming(action)
    end

    --- Normalize trigger definition for pending vigilance
    function controller:normalizeVigilanceTrigger(trigger)
        if type(trigger) == "string" then
            local templated = vigilance_triggers.getTemplate(trigger)
            if templated then
                return templated
            end

            return {
                mode = "action_type",
                actionType = trigger,
                excludeSelf = true,
            }
        end

        if type(trigger) == "table" then
            local templated = vigilance_triggers.getTemplate(trigger.template or trigger.preset, trigger)
            if templated then
                return templated
            end

            return trigger
        end

        -- Default practical trigger: when a hostile action targets the vigilant actor.
        return vigilance_triggers.getDefaultTrigger()
    end

    --- Determine whether a pending vigilance triggers from a resolved action
    function controller:doesVigilanceTrigger(actor, pendingVigilance, triggeringAction)
        if not actor or not pendingVigilance or not triggeringAction then
            return false
        end

        local trigger = self:normalizeVigilanceTrigger(pendingVigilance.trigger)
        local actionType = triggeringAction.normalizedType or triggeringAction.type
        local triggerActor = triggeringAction.actor
        local triggerTarget = triggeringAction.target

        local function matchesActionType()
            if trigger.actionType and actionType ~= trigger.actionType then
                return false
            end
            if type(trigger.actionTypes) == "table" then
                local matched = false
                for _, allowed in ipairs(trigger.actionTypes) do
                    if actionType == allowed then
                        matched = true
                        break
                    end
                end
                if not matched then
                    return false
                end
            end
            return true
        end

        if trigger.mode == "targeted_by_hostile_action" then
            if not triggerActor or triggerActor == actor then
                return false
            end
            if trigger.hostileOnly ~= false and not self:areHostile(actor, triggerActor) then
                return false
            end
            if trigger.target == nil or trigger.target == "self" then
                if triggerTarget ~= actor then
                    return false
                end
            elseif trigger.target == "ally" then
                if not triggerTarget or triggerTarget == actor or self:areHostile(actor, triggerTarget) then
                    return false
                end
            elseif trigger.target == "enemy" then
                if not triggerTarget or not self:areHostile(actor, triggerTarget) then
                    return false
                end
            elseif trigger.target ~= "any" then
                if type(trigger.target) == "string" then
                    if not triggerTarget or triggerTarget.id ~= trigger.target then
                        return false
                    end
                elseif triggerTarget ~= trigger.target then
                    return false
                end
            end
            return matchesActionType()
        end

        if trigger.excludeSelf ~= false and triggerActor == actor then
            return false
        end
        if trigger.hostileOnly and (not triggerActor or not self:areHostile(actor, triggerActor)) then
            return false
        end
        if trigger.alliedOnly and (not triggerActor or self:areHostile(actor, triggerActor)) then
            return false
        end
        if trigger.actorId and (not triggerActor or triggerActor.id ~= trigger.actorId) then
            return false
        end
        if trigger.targetId and (not triggerTarget or triggerTarget.id ~= trigger.targetId) then
            return false
        end
        if trigger.target == "self" and triggerTarget ~= actor then
            return false
        end
        if trigger.target == "ally" and (not triggerTarget or triggerTarget == actor or self:areHostile(actor, triggerTarget)) then
            return false
        end
        if trigger.target == "enemy" and (not triggerTarget or not self:areHostile(actor, triggerTarget)) then
            return false
        end
        if trigger.actorZoneId and (not triggerActor or triggerActor.zone ~= trigger.actorZoneId) then
            return false
        end
        if trigger.targetZoneId and (not triggerTarget or triggerTarget.zone ~= trigger.targetZoneId) then
            return false
        end

        return matchesActionType()
    end

    --- Find a fallback target for vigilance follow-up actions
    function controller:findVigilanceFallbackTarget(actor, targetKind)
        local candidates = nil
        if targetKind == "enemy" then
            candidates = actor and actor.isPC and self.npcs or self.pcs
        elseif targetKind == "ally" then
            candidates = actor and actor.isPC and self.pcs or self.npcs
        else
            candidates = self.allCombatants
        end

        for _, candidate in ipairs(candidates or {}) do
            if candidate ~= actor and not self:isDefeated(candidate) then
                return candidate
            end
        end

        -- Self-target fallback for ally actions
        if targetKind == "ally" and actor and not self:isDefeated(actor) then
            return actor
        end

        return nil
    end

    --- Resolve target selection for a triggered vigilance follow-up
    function controller:resolveVigilanceTarget(actor, pendingVigilance, triggeringAction, followUpDef)
        local triggerActor = triggeringAction and triggeringAction.actor or nil
        local triggerTarget = triggeringAction and triggeringAction.target or nil

        local explicitTarget = pendingVigilance.followUpTarget or pendingVigilance.target
        if explicitTarget and not self:isDefeated(explicitTarget) then
            return explicitTarget
        end

        local policy = pendingVigilance.followUpTargetPolicy
        if policy == "trigger_actor" then
            if triggerActor and not self:isDefeated(triggerActor) then
                return triggerActor
            end
        elseif policy == "trigger_target" then
            if triggerTarget and not self:isDefeated(triggerTarget) then
                return triggerTarget
            end
        elseif policy == "self" then
            return actor
        end

        if not followUpDef then
            return nil
        end

        if followUpDef.targetType == "enemy" then
            if triggerActor and self:areHostile(actor, triggerActor) and not self:isDefeated(triggerActor) then
                return triggerActor
            end
            return self:findVigilanceFallbackTarget(actor, "enemy")
        end

        if followUpDef.targetType == "ally" then
            if triggerActor and not self:areHostile(actor, triggerActor) and not self:isDefeated(triggerActor) then
                return triggerActor
            end
            return self:findVigilanceFallbackTarget(actor, "ally")
        end

        if followUpDef.requiresTarget then
            if triggerActor and not self:isDefeated(triggerActor) then
                return triggerActor
            end
            return self:findVigilanceFallbackTarget(actor, "any")
        end

        return nil
    end

    --- Build a concrete triggered action from pending vigilance state
    function controller:buildVigilanceReactionAction(actor, pendingVigilance, triggeringAction)
        local actionRegistry = require('data.action_registry')
        local followUpActionType = pendingVigilance.followUpAction

        if type(followUpActionType) == "table" then
            followUpActionType = followUpActionType.id or followUpActionType.type
        end
        if not followUpActionType then
            return nil, "missing_follow_up_action"
        end

        local followUpDef = actionRegistry.getAction(followUpActionType)
        if not followUpDef then
            return nil, "unknown_follow_up_action"
        end

        local reaction = {
            actor = actor,
            card = pendingVigilance.card,
            type = followUpActionType,
            actionDef = followUpDef,
            target = self:resolveVigilanceTarget(actor, pendingVigilance, triggeringAction, followUpDef),
            destinationZone = pendingVigilance.followUpDestinationZone,
            weapon = pendingVigilance.weapon or (
                actor and actor.inventory and actor.inventory.getWieldedWeapon and actor.inventory:getWieldedWeapon()
            ) or { name = "Fists", isMelee = true },
            allEntities = self.allCombatants,
            challengeController = self,
            isVigilanceReaction = true,
            triggerAction = triggeringAction,
            round = self.currentRound,
            count = self.currentCount,
            vigilanceDeclaredOrder = pendingVigilance.declaredOrder or 0,
        }

        return reaction
    end

    --- Collect all vigilance reactions triggered by the just-resolved action
    function controller:collectTriggeredVigilanceReactions(triggeringAction)
        if not triggeringAction then
            return {}
        end

        local triggered = {}

        for _, entity in ipairs(self.allCombatants) do
            local pendingVigilance = entity.pendingVigilance
            if pendingVigilance and not self:isDefeated(entity) then
                if self:doesVigilanceTrigger(entity, pendingVigilance, triggeringAction) then
                    entity.pendingVigilance = nil  -- Consume vigilance once triggered

                    local reaction, reason = self:buildVigilanceReactionAction(entity, pendingVigilance, triggeringAction)
                    if reaction then
                        triggered[#triggered + 1] = reaction
                        self.eventBus:emit("vigilance_triggered", {
                            actor = entity,
                            triggerAction = triggeringAction,
                            followUpAction = reaction.type,
                        })
                    else
                        local discarded = self:discardFacedownCard(entity, pendingVigilance.card, "vigilance_trigger_failed")
                        self.eventBus:emit("vigilance_trigger_failed", {
                            actor = entity,
                            triggerAction = triggeringAction,
                            reason = reason,
                            card = pendingVigilance.card,
                            discarded = discarded,
                        })
                        print("[VIGILANCE] " .. (entity.name or entity.id) .. " trigger failed: " .. tostring(reason))
                    end
                end
            end
        end

        table.sort(triggered, function(a, b)
            local orderA = a.vigilanceDeclaredOrder or math.huge
            local orderB = b.vigilanceDeclaredOrder or math.huge
            if orderA == orderB then
                local idA = (a.actor and a.actor.id) or ""
                local idB = (b.actor and b.actor.id) or ""
                return tostring(idA) < tostring(idB)
            end
            return orderA < orderB
        end)

        return triggered
    end

    --- Queue vigilance reactions for processing
    function controller:queueTriggeredVigilanceReactions(triggeringAction)
        local triggered = self:collectTriggeredVigilanceReactions(triggeringAction)
        for _, reaction in ipairs(triggered) do
            self.pendingVigilanceReactions[#self.pendingVigilanceReactions + 1] = reaction
        end
        return #triggered
    end

    --- Continue turn flow when no more vigilance reactions are queued
    function controller:continuePostActionFlow()
        if self.resolvingMinors then
            if #self.pendingMinors > 0 then
                self:processNextMinorAction()
            else
                self.resolvingMinors = false
                self:completeTurn()
            end
            return
        end

        -- Emit turn end once all reactions are complete
        self.eventBus:emit(events.EVENTS.CHALLENGE_TURN_END, {
            count = self.currentCount,
            round = self.currentRound,
            entity = self.activeEntity,
        })

        -- Enter minor action window
        self:startMinorActionWindow()
    end

    --- Process the next queued vigilance reaction
    function controller:processNextVigilanceReaction()
        if #self.pendingVigilanceReactions == 0 then
            self.resolvingVigilance = false
            self:continuePostActionFlow()
            return
        end

        local reaction = table.remove(self.pendingVigilanceReactions, 1)

        print("[VIGILANCE] " .. (reaction.actor.name or reaction.actor.id) ..
              " triggers " .. (reaction.type or "action"))

        self.state = M.STATES.RESOLVING
        self.pendingAction = reaction

        if self:beginIncomingActionInterruptWindow(reaction) then
            return
        end

        -- Resolve through the standard pipeline
        self.eventBus:emit(events.EVENTS.CHALLENGE_ACTION, reaction)
    end

    --- Submit an action for the active entity
    -- @param action table: { type, target, card, ... }
    -- @return boolean, string: success, error
    function controller:submitAction(action)
        if self.state ~= M.STATES.AWAITING_ACTION then
            return false, "not_awaiting_action"
        end

        if not self.activeEntity then
            return false, "no_active_entity"
        end

        action.actor = self.activeEntity
        action.round = self.currentRound
        action.count = self.currentCount
        action.challengeController = self

        if self:beginIncomingActionInterruptWindow(action) then
            return true
        end

        -- Move to resolving state
        self.state = M.STATES.RESOLVING
        self.pendingAction = action

        -- Emit action event for resolution
        self.eventBus:emit(events.EVENTS.CHALLENGE_ACTION, action)

        return true
    end

    --- Skip the active entity's turn without opening a minor-action window.
    -- Rulebook p.114: if a turn is skipped or no card can be played, nobody
    -- takes minor actions and the count-up continues.
    function controller:skipTurn(entity, reason)
        if self.state ~= M.STATES.AWAITING_ACTION then
            return false, "not_awaiting_action"
        end

        if not self.activeEntity then
            return false, "no_active_entity"
        end

        if entity and entity ~= self.activeEntity then
            return false, "not_active_entity"
        end

        local skipped = self.activeEntity
        self.eventBus:emit(events.EVENTS.CHALLENGE_TURN_END, {
            count = self.currentCount,
            round = self.currentRound,
            entity = skipped,
            skipped = true,
            reason = reason or "skipped",
        })

        self:completeTurn()
        return true
    end

    --- Resolve an action (called by action resolver)
    function controller:resolveAction(action)
        -- Store the result
        local result = action.result or { success = false }

        -- Emit resolution event
        self.eventBus:emit(events.EVENTS.CHALLENGE_RESOLUTION, {
            action = action,
            result = result,
        })

        -- Enter visual sync - wait for UI to show the result
        self.state = M.STATES.VISUAL_SYNC
        self.awaitingVisualSync = true

        -- The ActionSequencer will emit UI_SEQUENCE_COMPLETE when done
    end

    --- Called when visual sequence completes
    function controller:onVisualComplete(data)
        if not self.awaitingVisualSync then
            return
        end

        local completedAction = self.pendingAction
        self.awaitingVisualSync = false
        self.pendingAction = nil

        if self.pendingCounterSpellRestore then
            self:completeCounterSpellInterrupt(completedAction)
            return
        end

        -- S4.9: Check if this was a Fool interrupt
        if self.pendingFoolRestore then
            self:completeFoolInterrupt()
            return
        end

        if self.pendingQuickRestore then
            self:completeQuickInterrupt()
            return
        end

        if completedAction and completedAction.isVigilanceReaction then
            self:discardResolvedVigilanceReaction(completedAction, "vigilance_resolved")
        end

        -- Queue vigilance reactions triggered by the just-resolved action
        local triggeredCount = self:queueTriggeredVigilanceReactions(completedAction)
        if triggeredCount > 0 then
            self.resolvingVigilance = true
        end

        if self.resolvingVigilance then
            self:processNextVigilanceReaction()
            return
        end

        self:continuePostActionFlow()
    end

    ----------------------------------------------------------------------------
    -- MINOR ACTION WINDOW (S6.4: Declaration Loop)
    ----------------------------------------------------------------------------

    --- Start the minor action opportunity window
    -- The count-up PAUSES here until Resume is clicked
    function controller:startMinorActionWindow()
        self.state = M.STATES.MINOR_WINDOW
        self.pendingMinors = {}
        self.minorWindowActive = true

        -- Emit state change for UI
        self.eventBus:emit("challenge_state_changed", {
            newState = "minor_window",
            count = self.currentCount,
            round = self.currentRound,
        })

        self.eventBus:emit(events.EVENTS.MINOR_ACTION_WINDOW, {
            count = self.currentCount,
            round = self.currentRound,
            paused = true,  -- Indicate this is a paused window
        })

        print("[MINOR WINDOW] Paused for minor action declarations. Click Resume to continue.")
    end

    --- Declare a minor action (adds to pending list)
    -- @param entity table: The entity declaring the minor action
    -- @param card table: The card being used (must match action suit)
    -- @param action table: { type, target, ... }
    -- @return boolean, string: success, error
    function controller:getMinorActionEntityKey(entity)
        if not entity then
            return nil
        end
        return entity.minorActionGroupId or entity.initiativeGroupId or entity.enemyGroupId or
            entity.groupId or entity.mobId or entity.id or entity
    end

    function controller:minorActionEntityMatches(entityA, entityB)
        if entityA == entityB then
            return true
        end
        local keyA = self:getMinorActionEntityKey(entityA)
        local keyB = self:getMinorActionEntityKey(entityB)
        return keyA ~= nil and keyB ~= nil and keyA == keyB
    end

    function controller:hasPendingMinorForEntity(entity)
        for _, declaration in ipairs(self.pendingMinors or {}) do
            if self:minorActionEntityMatches(entity, declaration.entity) then
                return true
            end
        end
        return false
    end

    function controller:declareMinorAction(entity, card, action)
        if self.state ~= M.STATES.MINOR_WINDOW then
            return false, "not_in_minor_window"
        end

        if not entity or not card or not action then
            return false, "invalid_minor_declaration"
        end

        if self.activeEntity and self:minorActionEntityMatches(entity, self.activeEntity) then
            return false, "acting_entity_cannot_minor"
        end

        if self:hasPendingMinorForEntity(entity) then
            return false, "minor_action_already_declared"
        end

        -- Verify card suit matches action suit (S6.2/S6.4 requirement)
        local actionRegistry = require('data.action_registry')
        local cardSuit = actionRegistry.cardSuitToActionSuit(card.suit)
        local actionDef = actionRegistry.getAction(action.type)

        if actionDef then
            if actionDef.suit == actionRegistry.SUITS.MISC then
                return false, "misc_not_allowed"  -- Misc actions not allowed as minors
            end
            if canGMIgnoreMinorSuit(entity, card) then
                if isGreaterDoomCard(card) then
                    return false, "greater_doom_standard_action_blocked"
                end
            else
                local talentMinor = actionRegistry.canUseMinorActionWithCard(actionDef, cardSuit, entity)
                if actionDef.suit ~= cardSuit and not talentMinor then
                    return false, "suit_mismatch"
                end
            end
        end

        -- Add to pending minors
        local declaration = {
            entity = entity,
            card = card,
            action = action,
            declaredAt = #self.pendingMinors + 1,  -- Order of declaration
        }

        self.pendingMinors[#self.pendingMinors + 1] = declaration

        print("[MINOR] " .. (entity.name or entity.id) .. " declares " ..
              (action.type or "action") .. " with " .. (card.name or "card"))

        self.eventBus:emit("minor_action_declared", {
            entity = entity,
            card = card,
            action = action,
            position = #self.pendingMinors,
        })

        return true
    end

    --- Remove a declared minor action
    function controller:undeclareMinorAction(index)
        if self.state ~= M.STATES.MINOR_WINDOW then
            return false, "not_in_minor_window"
        end

        if index < 1 or index > #self.pendingMinors then
            return false, "invalid_index"
        end

        local removed = table.remove(self.pendingMinors, index)

        self.eventBus:emit("minor_action_undeclared", {
            entity = removed.entity,
            position = index,
        })

        return true
    end

    --- Resume from minor window and resolve all pending minors
    -- Called when "Resume" button is clicked
    function controller:resumeFromMinorWindow()
        if self.state ~= M.STATES.MINOR_WINDOW then
            return false, "not_in_minor_window"
        end

        print("[MINOR WINDOW] Resuming with " .. #self.pendingMinors .. " pending actions")

        self.minorWindowActive = false

        -- Emit state change
        self.eventBus:emit("challenge_state_changed", {
            newState = "resolving_minors",
            pendingCount = #self.pendingMinors,
        })

        -- Process pending minors in declaration order
        if #self.pendingMinors > 0 then
            self:processNextMinorAction()
        else
            -- No minors declared, continue to next turn
            self:completeTurn()
        end

        return true
    end

    --- Process the next pending minor action
    function controller:processNextMinorAction()
        if #self.pendingMinors == 0 then
            -- All minors processed, continue turn
            self:completeTurn()
            return
        end

        -- Get next minor in order
        local minor = table.remove(self.pendingMinors, 1)

        print("[MINOR RESOLVE] Processing " .. (minor.entity.name or minor.entity.id) ..
              "'s " .. (minor.action.type or "action"))

        -- Build the full action
        local fullAction = minor.action
        fullAction.actor = minor.entity
        fullAction.card = minor.card
        fullAction.isMinorAction = true  -- Flag for resolver (uses face value only)
        fullAction.challengeController = self

        self.state = M.STATES.RESOLVING
        self.pendingAction = fullAction
        self.resolvingMinors = true

        if self:beginIncomingActionInterruptWindow(fullAction) then
            return
        end

        -- Emit action for resolution
        self.eventBus:emit(events.EVENTS.CHALLENGE_ACTION, fullAction)

        -- Wait for visual sync before processing next minor
        self.state = M.STATES.VISUAL_SYNC
        self.awaitingVisualSync = true

        -- The onVisualComplete will be called after animation
        -- We need to track that we're resolving minors
        self.resolvingMinors = true
    end

    --- Called when a minor action is used (legacy compatibility)
    function controller:onMinorActionUsed(data)
        if self.state ~= M.STATES.MINOR_WINDOW then
            return
        end

        -- Legacy: single minor action used
        self.minorActionUsed = true

        -- Continue to next entity/count
        self:completeTurn()
    end

    --- Update function (call from love.update)
    function controller:update(dt)
        -- S6.4: Minor window is now paused indefinitely, no timer
        -- The window only ends when Resume is clicked
    end

    ----------------------------------------------------------------------------
    -- NPC AI TRIGGERS
    ----------------------------------------------------------------------------

    --- Trigger AI to choose initiative card (S4.6)
    function controller:triggerNPCInitiative(npc)
        self.eventBus:emit("npc_choose_initiative", {
            npc = npc,
            round = self.currentRound,
        })
    end

    --- Trigger AI to decide NPC action
    function controller:triggerNPCAction()
        -- The AI system will listen for CHALLENGE_TURN_START where isPC = false
        -- and submit an action via submitAction()
        self.eventBus:emit("npc_turn", {
            npc = self.activeEntity,
            count = self.currentCount,
            round = self.currentRound,
            pcs = self.pcs,
        })
    end

    ----------------------------------------------------------------------------
    -- FLEE HANDLING
    ----------------------------------------------------------------------------

    --- Attempt to flee from the challenge
    -- @param entity table: The entity attempting to flee
    -- @param options table|nil: Retreat pursuit/test details for the resolver
    -- @return boolean, table: success, resolver result
    function controller:attemptFlee(entity, options)
        options = options or {}

        local action_resolver = require('logic.action_resolver')
        local resolver = self.actionResolver
        if not resolver then
            resolver = action_resolver.createActionResolver({
                eventBus = self.eventBus,
                zoneSystem = self.zoneSystem,
                challengeController = self,
            })
            self.actionResolver = resolver
        end

        local action = {}
        for key, value in pairs(options) do
            action[key] = value
        end
        action.actor = action.actor or entity
        action.card = action.card or { name = "Retreat", value = 0, suit = constants.SUITS.PENTACLES }
        action.type = action.type or action_resolver.ACTION_TYPES.FLEE
        action.challengeController = action.challengeController or self
        if not action.participants then
            action.participants = (self.pcs and #self.pcs > 0) and self.pcs or { entity }
        end
        action.allEntities = action.allEntities or self.allCombatants

        local result = resolver:resolve(action)
        self.lastRetreatResult = result
        if result and result.needsGroupTest then
            self.pendingRetreat = action
            self.eventBus:emit(events.EVENTS.REQUEST_RETREAT_GROUP_TEST, {
                actor = entity,
                action = action,
                result = result,
                request = result.groupTestRequest,
            })
        else
            self.pendingRetreat = nil
        end

        self.eventBus:emit("challenge_retreat_attempted", {
            actor = entity,
            action = action,
            result = result,
        })

        return result and result.success == true, result
    end

    ----------------------------------------------------------------------------
    -- THE FOOL INTERRUPT (S4.9)
    -- The Fool allows immediate out-of-turn action
    ----------------------------------------------------------------------------

    --- Play The Fool to interrupt and take an immediate action
    -- @param entity table: The entity playing The Fool
    -- @param foolCard table: The Fool card being played
    -- @param followUpCard table: Optional follow-up card for the action
    -- @param action table: Optional action to take immediately
    -- @return boolean, string: success, error
    function controller:playFoolInterrupt(entity, foolCard, followUpCard, action)
        -- Can only interrupt during COUNT_UP, AWAITING_ACTION, or MINOR_WINDOW
        if self.state ~= M.STATES.COUNT_UP and
           self.state ~= M.STATES.AWAITING_ACTION and
           self.state ~= M.STATES.MINOR_WINDOW then
            return false, "cannot_interrupt_now"
        end

        if not entity or not foolCard then
            return false, "invalid_fool_interrupt"
        end

        -- Verify it's The Fool
        if foolCard.name ~= "The Fool" and not (foolCard.is_major and foolCard.value == 0) then
            return false, "not_the_fool"
        end

        if action and not followUpCard and not action.followUpCard then
            return false, "missing_fool_followup_card"
        end

        print("[FOOL INTERRUPT] " .. (entity.name or entity.id) .. " plays The Fool!")

        -- Store the current state to restore after interrupt
        local previousState = self.state
        local previousActive = self.activeEntity

        -- Temporarily make the interrupting entity active
        self.activeEntity = entity
        self.state = M.STATES.RESOLVING

        -- Build the interrupt action
        local interruptAction = action or {
            actor = entity,
            card = foolCard,
            type = "fool_interrupt",
            followUpCard = followUpCard,
            followUpAction = action and action.type,
            target = action and action.target,
        }
        if action then
            local followUpActionType = action.foolFollowUpAction or action.type
            action.actor = entity
            action.card = foolCard
            action.foolCard = foolCard
            action.followUpCard = followUpCard or action.followUpCard
            action.foolFollowUpAction = followUpActionType
            if not action.followUpAction then
                action.followUpAction = followUpActionType
            end
            action.round = self.currentRound
            action.count = self.currentCount
            action.challengeController = self
            action.isFoolInterrupt = true
            action.foolInterrupt = true
            action.isInterrupt = true
        else
            interruptAction.foolCard = foolCard
            interruptAction.followUpCard = followUpCard
            interruptAction.isFoolInterrupt = true
            interruptAction.foolInterrupt = true
            interruptAction.isInterrupt = true
            interruptAction.round = self.currentRound
            interruptAction.count = self.currentCount
            interruptAction.challengeController = self
        end

        self.pendingFoolRestore = {
            state = previousState,
            activeEntity = previousActive,
        }
        self.pendingAction = interruptAction

        -- Emit interrupt event
        self.eventBus:emit("fool_interrupt_start", {
            entity = entity,
            card = foolCard,
            followUpCard = interruptAction.followUpCard,
            action = interruptAction,
            previousState = previousState,
            previousActive = previousActive,
        })

        -- Emit the action for resolution
        self.eventBus:emit(events.EVENTS.CHALLENGE_ACTION, interruptAction)

        -- If no follow-up specified, wait for player to choose
        if not followUpCard and not action then
            self.eventBus:emit("fool_awaiting_followup", {
                entity = entity,
            })
        end

        return true
    end

    --- Called after Fool interrupt resolves to restore state
    function controller:completeFoolInterrupt()
        if self.pendingFoolRestore then
            self.state = self.pendingFoolRestore.state
            self.activeEntity = self.pendingFoolRestore.activeEntity
            self.pendingFoolRestore = nil
            self.pendingAction = nil

            self.eventBus:emit("fool_interrupt_complete", {})

            print("[FOOL INTERRUPT] Complete, resuming normal turn order")
        end
    end

    ----------------------------------------------------------------------------
    -- QUICK! INTERRUPT
    -- A light/no-armor Quick! adventurer can use Pentacles actions out of turn.
    ----------------------------------------------------------------------------

    function controller:canUseQuickInterrupt(entity, card, action)
        if self.state ~= M.STATES.COUNT_UP and
           self.state ~= M.STATES.AWAITING_ACTION and
           self.state ~= M.STATES.MINOR_WINDOW then
            return false, "cannot_interrupt_now"
        end

        if not entity or not card or not action or not action.type then
            return false, "invalid_quick_interrupt"
        end

        if not entityHasUsableTalent(entity, "quick") then
            return false, "requires_quick"
        end

        if not entityWearsLightOrNoArmor(entity) then
            return false, "requires_light_or_no_armor"
        end

        local actionDef = action_registry.getAction(action.type)
        if not actionDef or actionDef.suit ~= action_registry.SUITS.PENTACLES then
            return false, "requires_pentacles_action"
        end

        return true, nil
    end

    function controller:playQuickInterrupt(entity, card, action)
        local ok, reason = self:canUseQuickInterrupt(entity, card, action)
        if not ok then
            return false, reason
        end

        print("[QUICK INTERRUPT] " .. (entity.name or entity.id) ..
              " interrupts with " .. tostring(action.type))

        local previousState = self.state
        local previousActive = self.activeEntity

        self.activeEntity = entity
        self.state = M.STATES.RESOLVING
        self.pendingQuickRestore = {
            state = previousState,
            activeEntity = previousActive,
        }

        action.actor = entity
        action.card = card
        action.round = self.currentRound
        action.count = self.currentCount
        action.challengeController = self
        action.isQuickInterrupt = true
        action.quickInterrupt = true
        action.quickTalentInterrupt = true
        action.quickInterruptContext = {
            actor = entity,
            actorId = entity and entity.id,
            card = card,
            cardName = card and card.name,
            cardSuit = card and card.suit,
            cardValue = card and card.value,
            actionType = action.type,
            round = self.currentRound,
            count = self.currentCount,
            previousState = previousState,
            previousActive = previousActive,
            previousActiveId = previousActive and previousActive.id,
        }

        self.pendingAction = action

        self.eventBus:emit("quick_interrupt_start", {
            entity = entity,
            card = card,
            action = action,
            context = action.quickInterruptContext,
            previousState = previousState,
            previousActive = previousActive,
        })

        self.eventBus:emit(events.EVENTS.CHALLENGE_ACTION, action)

        return true
    end

    ----------------------------------------------------------------------------
    -- COUNTER-SPELL INTERRUPT
    -- A Wands talent reaction that can fizzle an incoming spell before it resolves.
    ----------------------------------------------------------------------------

    function controller:playCounterSpellInterrupt(entity, card, incomingAction, opts)
        opts = opts or {}
        local ok, reason = self:canCounterSpellIncoming(entity, card, incomingAction, opts)
        if not ok then
            return false, reason
        end

        print("[COUNTER-SPELL] " .. (entity.name or entity.id) ..
              " interrupts " .. ((incomingAction.actor and (incomingAction.actor.name or incomingAction.actor.id)) or "a spellcaster"))

        local counterAction = {
            actor = entity,
            target = incomingAction.actor,
            card = card,
            type = "counter_spell",
            incomingAction = incomingAction,
            spellAction = incomingAction,
            incomingSpell = incomingAction.spell or incomingAction.incomingSpell,
            canPerceiveCasting = opts.canPerceiveCasting ~= false and incomingAction.canPerceiveCasting ~= false,
            canPerceiveCaster = opts.canPerceiveCaster ~= false and incomingAction.canPerceiveCaster ~= false,
            round = self.currentRound,
            count = self.currentCount,
            challengeController = self,
            isCounterSpellInterrupt = true,
            counterSpellInterrupt = true,
            isInterrupt = true,
        }

        local pending = self.pendingCounterSpellInterrupt
        local shouldResumeIncoming = opts.resumeIncoming
        if shouldResumeIncoming == nil then
            shouldResumeIncoming = pending and pending.incomingAction == incomingAction and
                not incomingAction.counterSpellIncomingEmitted
        end

        incomingAction.counterSpellDecisionResolved = true
        incomingAction.counterSpellPromptPending = false
        incomingAction.counterSpellInterruptPlayed = true

        if pending and pending.incomingAction == incomingAction then
            self.pendingCounterSpellInterrupt = nil
        end
        self.awaitingCounterSpellDecision = false

        if shouldResumeIncoming then
            self.pendingCounterSpellRestore = {
                incomingAction = incomingAction,
                counterAction = counterAction,
            }
        end

        self.state = M.STATES.RESOLVING
        self.pendingAction = counterAction

        self.eventBus:emit("counter_spell_interrupt_start", {
            entity = entity,
            counterer = entity,
            card = card,
            action = counterAction,
            incomingAction = incomingAction,
            spellCaster = incomingAction.actor,
        })

        self.eventBus:emit(events.EVENTS.CHALLENGE_ACTION, counterAction)

        return true, counterAction
    end

    function controller:completeCounterSpellInterrupt(counterAction)
        local pending = self.pendingCounterSpellRestore
        if not pending then
            return false
        end

        self.pendingCounterSpellRestore = nil

        self.eventBus:emit("counter_spell_interrupt_complete", {
            action = counterAction or pending.counterAction,
            counterAction = counterAction or pending.counterAction,
            incomingAction = pending.incomingAction,
            spellCaster = pending.incomingAction and pending.incomingAction.actor,
        })

        print("[COUNTER-SPELL] Complete, resolving incoming spell")
        return self:resolveCounterSpellPendingIncoming(pending.incomingAction)
    end

    function controller:completeQuickInterrupt()
        if self.pendingQuickRestore then
            self.state = self.pendingQuickRestore.state
            self.activeEntity = self.pendingQuickRestore.activeEntity
            self.pendingQuickRestore = nil
            self.pendingAction = nil

            self.eventBus:emit("quick_interrupt_complete", {})

            print("[QUICK INTERRUPT] Complete, resuming normal turn order")
        end
    end

    ----------------------------------------------------------------------------
    -- HEAVY METAL MACHINE INTERRUPT
    -- An iron/steel-armored Swords talent user can boost Initiative against
    -- one incoming targeted action by discarding any Challenge card.
    ----------------------------------------------------------------------------

    function controller:playHeavyMetalMachineInterrupt(entity, card, incomingAction, opts)
        opts = opts or {}
        local ok, reason, armor = self:canUseHeavyMetalMachineInterrupt(entity, card, incomingAction, opts)
        if not ok then
            return false, reason
        end

        local round = self.currentRound or incomingAction.round or incomingAction.currentRound or 0
        local bonus = entity.swords or (entity.getAttribute and entity:getAttribute(constants.SUITS.SWORDS)) or 0

        entity.heavyMetalMachineUsedRound = round
        entity.heavyMetalMachineInterrupt = {
            round = round,
            bonus = bonus,
            card = card,
            armor = armor,
            againstAction = incomingAction,
            againstActionId = incomingAction.id,
            againstActorId = incomingAction.actor and incomingAction.actor.id,
        }

        incomingAction.heavyMetalMachineInterruptPlayed = true

        local pending = self.pendingHeavyMetalMachineInterrupt
        if pending and pending.incomingAction == incomingAction then
            self.pendingHeavyMetalMachineInterrupt = nil
        end
        self.awaitingHeavyMetalMachineDecision = false

        print("[HEAVY METAL MACHINE] " .. (entity.name or entity.id) ..
              " boosts Initiative against " ..
              ((incomingAction.actor and (incomingAction.actor.name or incomingAction.actor.id)) or "an incoming action"))

        self.eventBus:emit("heavy_metal_machine_interrupt_start", {
            entity = entity,
            actor = entity,
            card = card,
            incomingAction = incomingAction,
            incomingActor = incomingAction.actor,
            bonus = bonus,
            armor = armor,
        })

        return self:resolveHeavyMetalMachinePendingIncoming(incomingAction)
    end

    ----------------------------------------------------------------------------
    -- AEGIS ELECTION
    -- A shield-bearing Aegis user can elect to Notch the shield instead of
    -- suffering a physical effect. The resolver consumes this flag only if the
    -- incoming effect actually lands.
    ----------------------------------------------------------------------------

    function controller:electAegisForIncoming(entity, incomingAction)
        local ok, reason, shield, location = self:canElectAegisForIncoming(entity, incomingAction)
        if not ok then
            return false, reason
        end

        incomingAction.useAegis = true
        incomingAction.aegis = true
        incomingAction.aegisActors = incomingAction.aegisActors or {}
        incomingAction.aegisActorList = incomingAction.aegisActorList or {}
        if entity.id then
            incomingAction.aegisActors[entity.id] = {
                actor = entity,
                shield = shield,
                shieldLocation = location,
            }
        end
        incomingAction.aegisActorList[#incomingAction.aegisActorList + 1] = {
            actor = entity,
            shield = shield,
            shieldLocation = location,
        }
        if not incomingAction.aegisActor then
            incomingAction.aegisActor = entity
            incomingAction.aegisShield = shield
            incomingAction.aegisShieldLocation = location
        end
        incomingAction.aegisElectionPlayed = true

        local pending = self.pendingAegisElection
        if pending and pending.incomingAction == incomingAction then
            local remaining = {}
            for _, candidate in ipairs(pending.candidates or {}) do
                local actor = candidate.actor
                if not actor or not entity.id or actor.id ~= entity.id then
                    remaining[#remaining + 1] = candidate
                end
            end
            if #remaining > 0 then
                pending.candidates = remaining
                self.pendingAegisElection = pending
            else
                self.pendingAegisElection = nil
            end
        end

        print("[AEGIS] " .. (entity.name or entity.id) ..
              " elects to Notch " .. (shield.name or "a shield") ..
              " if the effect lands")

        if self.pendingAegisElection then
            self.awaitingAegisDecision = true
            self.eventBus:emit("aegis_election_selected", {
                entity = entity,
                actor = entity,
                incomingAction = incomingAction,
                incomingActor = incomingAction.actor,
                shield = shield,
                shieldLocation = location,
                remaining = self.pendingAegisElection.candidates,
            })
            self.eventBus:emit("aegis_election_available", self.pendingAegisElection)
            return true, incomingAction
        end

        self.awaitingAegisDecision = false

        self.eventBus:emit("aegis_election_start", {
            entity = entity,
            actor = entity,
            incomingAction = incomingAction,
            incomingActor = incomingAction.actor,
            shield = shield,
            shieldLocation = location,
        })

        return self:resolveAegisPendingIncoming(incomingAction)
    end

    ----------------------------------------------------------------------------
    -- COUNSEL
    -- A Cups talent card transfer that can become an interrupt with Resolve.
    ----------------------------------------------------------------------------

    function controller:findCounselCard(playerHand, counselor, card, opts)
        opts = opts or {}
        if not playerHand or not playerHand.hands or not counselor or not counselor.id then
            return nil, nil, "missing_player_hand"
        end

        local handData = playerHand.hands[counselor.id]
        local cards = handData and handData.cards
        if not cards or #cards == 0 then
            return nil, nil, "no_counsel_card"
        end

        local index = tonumber(opts.cardIndex or opts.index)
        if not index and card then
            for i, candidate in ipairs(cards) do
                if candidate == card then
                    index = i
                    break
                end
            end
        end

        if not index then
            return nil, nil, "card_not_in_hand"
        end
        if index < 1 or index > #cards then
            return nil, nil, "invalid_card_index"
        end

        return cards[index], index, nil
    end

    function controller:resolveCounsel(counselor, target, card, actionType, opts)
        opts = opts or {}
        local playerHand = opts.playerHand or self.playerHand

        if self.state == M.STATES.IDLE or self.state == M.STATES.ENDING then
            return false, "not_in_challenge"
        end
        if not counselor or not target then
            return false, "invalid_counsel"
        end
        if counselor == target or counselor.id == target.id then
            return false, "requires_other_adventurer"
        end
        if not target.isPC then
            return false, "requires_adventurer_target"
        end
        if not entityHasUsableTalent(counselor, "counsel") then
            return false, "requires_counsel"
        end

        local round = self.currentRound or 0
        if counselor.counselUsedRound == round then
            return false, "counsel_already_used"
        end

        local actionDef = action_registry.getAction(actionType)
        if not actionDef then
            return false, "unknown_counsel_action"
        end
        if actionDef.suit == action_registry.SUITS.MISC then
            return false, "requires_suited_action"
        end

        local heldCard, cardIndex, cardReason = self:findCounselCard(playerHand, counselor, card, opts)
        if not heldCard then
            return false, cardReason
        end

        local cardSuit = action_registry.cardSuitToActionSuit(heldCard.suit)
        if cardSuit ~= actionDef.suit then
            return false, "suit_mismatch"
        end

        local interrupt = opts.spendResolve == true or opts.resolveForInterrupt == true or
            opts.spendResolveForInterrupt == true
        local resolveSpent = false
        if interrupt then
            local spent, spendReason = spendEntityResolve(counselor, 1)
            if not spent then
                return false, spendReason or "not_enough_resolve"
            end
            resolveSpent = true
        end

        local sourceHand = playerHand.hands[counselor.id].cards
        table.remove(sourceHand, cardIndex)
        playerHand.hands[target.id] = playerHand.hands[target.id] or {}
        playerHand.hands[target.id].cards = playerHand.hands[target.id].cards or {}
        local targetHand = playerHand.hands[target.id].cards
        targetHand[#targetHand + 1] = heldCard

        counselor.counselUsedRound = round
        heldCard.counsel = {
            counselorId = counselor.id,
            targetId = target.id,
            actionType = actionType,
            round = round,
            interrupt = interrupt,
            resolveSpent = resolveSpent,
        }

        local detail = {
            counselor = counselor,
            target = target,
            card = heldCard,
            cardIndex = cardIndex,
            cardName = heldCard.name,
            cardSuit = heldCard.suit,
            cardValue = heldCard.value,
            actionType = actionType,
            actionName = actionDef.name,
            actionSuit = actionDef.suit,
            round = round,
            interrupt = interrupt,
            resolveSpent = resolveSpent,
            sourceHandSize = #sourceHand,
            targetHandSize = #targetHand,
        }

        self.eventBus:emit("counsel_card_given", detail)

        return true, detail
    end

    ----------------------------------------------------------------------------
    -- QUERIES
    ----------------------------------------------------------------------------

    function controller:isActive()
        return self.state ~= M.STATES.IDLE
    end

    function controller:getCurrentCount()
        return self.currentCount
    end

    function controller:getCurrentRound()
        return self.currentRound
    end

    --- Legacy compatibility: getCurrentTurn returns count
    function controller:getCurrentTurn()
        return self.currentCount
    end

    function controller:getMaxTurns()
        return MAX_TURNS
    end

    function controller:getActiveEntity()
        return self.activeEntity
    end

    function controller:getState()
        return self.state
    end

    function controller:getCombatants()
        return self.allCombatants
    end

    function controller:isPlayerTurn()
        return self.activeEntity and self.activeEntity.isPC
    end

    function controller:isAwaitingInitiative()
        return self.state == M.STATES.PRE_ROUND
    end

    function controller:getAwaitingInitiativeList()
        local list = {}
        for id, _ in pairs(self.awaitingInitiative) do
            list[#list + 1] = id
        end
        return list
    end

    function controller:getInitiativeSlot(entityId)
        return self.initiativeSlots[entityId]
    end

    --- S6.4: Check if in minor action window
    function controller:isInMinorWindow()
        return self.state == M.STATES.MINOR_WINDOW
    end

    --- S6.4: Get pending minor actions
    function controller:getPendingMinors()
        return self.pendingMinors
    end

    return controller
end

return M
