-- camp_controller.lua
-- Camp Phase State Machine for Majesty
-- Ticket S8.1: Orchestrates the 5 steps of the Camp Phase
--
-- Flow (Rulebook p. 136):
-- 1. SETUP    - Verify shelter/bedroll availability
-- 2. ACTIONS  - Each adventurer takes a camp action
-- 3. BREAK_BREAD - Consume rations (starvation if none)
-- 4. WATCH    - Meatgrinder draw for overnight events
-- 5. RECOVERY - Burn bonds to heal, clear stress
-- 6. TEARDOWN - Return to Crawl phase

local events = require('logic.events')
local campActions = require('logic.camp_actions')
local constants = require('constants')
local fateResolver = require('logic.resolver')
local inventory = require('logic.inventory')
local animalCompanions = require('data.animal_companions')

local M = {}

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

local function hasSubmittedTestOutcome(actionData)
    return actionData and (actionData.outcome ~= nil or
        actionData.testResult ~= nil or actionData.testOutcome ~= nil)
end

local function isAcceptedFailedTestOutcome(actionData, result)
    if not hasSubmittedTestOutcome(actionData) then
        return false
    end

    if actionData.type == "scout" then
        return result == "nothing_learned" or result == "challenge_triggered"
    elseif actionData.type == "hunt" then
        return result == "no_game" or result == "challenge_triggered"
    elseif actionData.type == "devour_living" then
        return result == "no_living_food"
    end

    return false
end

local function normalizeTalentId(talentId)
    return tostring(talentId or ""):lower():gsub("[%s%-]+", "_"):gsub("[’']", "")
end

local function normalizeFeedKey(value)
    return tostring(value or "")
        :lower()
        :gsub("[’']", "")
        :gsub("[^%w]+", "_")
        :gsub("^_+", "")
        :gsub("_+$", "")
end

local function hasControllerUsableTalent(entity, talentId)
    if not entity then
        return false
    end
    if entity.canUseTalent and entity:canUseTalent(talentId) then
        return true
    end

    local requested = normalizeTalentId(talentId)
    for id, talent in pairs(entity.talents or {}) do
        if normalizeTalentId(id) == requested then
            if type(talent) == "table" then
                return talent.wounded ~= true
            end
            return talent == true
        end
    end

    return false
end

local function entityComfortKey(entity)
    if type(entity) == "table" then
        return entity.id or entity.name
    end
    return entity
end

local function campListIncludesEntity(list, entity)
    if not list or not entity then
        return false
    end

    local key = entityComfortKey(entity)
    if key and list[key] ~= nil then
        return list[key] ~= false
    end
    if list[entity] ~= nil then
        return list[entity] ~= false
    end

    for _, item in ipairs(list) do
        if item == entity or entityComfortKey(item) == key then
            return true
        end
    end
    return false
end

local function countCampListEntries(list)
    if type(list) ~= "table" then
        return 0
    end

    local count = 0
    for key, value in pairs(list) do
        if type(key) == "number" then
            if value ~= nil and value ~= false then
                count = count + 1
            end
        elseif value ~= nil and value ~= false then
            count = count + 1
        end
    end
    return count
end

local function entityAfflictionStage(entity, afflictionId)
    if not entity then
        return 0
    end
    local afflictions = entity.afflictions
    local affliction = type(afflictions) == "table" and afflictions[afflictionId]
    if type(affliction) == "table" then
        return tonumber(affliction.stage or affliction.currentStage or affliction.progressStage) or 1
    end
    if affliction == true then
        return 1
    end
    return 0
end

local function entityHasAfflictionStage(entity, afflictionId, stage)
    return entityAfflictionStage(entity, afflictionId) >= (stage or 1)
end

local function normalizeAfflictionId(value)
    return tostring(value or ""):lower():gsub("[’']", ""):gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
end

local CANONICAL_AFFLICTIONS = {
    black_honey = {
        id = "black_honey",
        name = "Black Honey",
        maxStage = 2,
        stageCosts = { [1] = 5, [2] = 1 },
        stageEffects = {
            [1] = "May draw five Challenge cards instead of four, then spit out 1-4 teeth.",
            [2] = "Cups equals 1; disfavor on fine motor tests of fate.",
        },
        recentlyTakenEffect = "draw_five_challenge_cards",
        reexposureClearsCuredStage = 2,
    },
    ghost_lotus = {
        id = "ghost_lotus",
        name = "Ghost Lotus",
        maxStage = 3,
        stageRecovery = {
            [1] = { xp = 1, charges = 0 },
            [2] = { charges = 2 },
            [3] = { charges = 1 },
        },
        stageEffects = {
            [1] = "Euphoria cancels effects that hamper sleep.",
            [2] = "Cannot read or write and is immune to illusions.",
            [3] = "Rewrite one motif descriptor.",
        },
    },
    giant_rat_venom = {
        id = "giant_rat_venom",
        name = "Giant Rat Venom",
        maxStage = 3,
        stageCosts = { [1] = 1, [2] = 1, [3] = 2 },
        stageEffects = {
            [1] = "The wound turns ugly, green, fetid, and stinking.",
            [2] = "Permanently Exhausted.",
            [3] = "Every Test of Fate causes a Piercing Wound after resolution.",
        },
    },
    face_rat_disease = {
        id = "face_rat_disease",
        name = "Face Rat Disease",
        maxStage = 3,
        stageCosts = { [1] = 1, [2] = 1, [3] = 2 },
        stageEffects = {
            [1] = "Featureless face; disfavor on Wands tests to influence others.",
            [2] = "Skin grows over the nose and mouth; Silenced.",
            [3] = "Skin grows over the eyes; Blind.",
        },
    },
    great_contagion = {
        id = "great_contagion",
        name = "The Great Contagion",
        maxStage = 3,
        stageCosts = { [1] = 2, [2] = 2 },
        stageEffects = {
            [1] = "Painful red whorls; take a Piercing Wound.",
            [2] = "Take Critical damage.",
            [3] = "Death.",
        },
    },
}

local AFFLICTION_ALIASES = {
    blackhoney = "black_honey",
    ghostlotus = "ghost_lotus",
    giantratvenom = "giant_rat_venom",
    faceratdisease = "face_rat_disease",
    greatcontagion = "great_contagion",
}

local function canonicalAfflictionTemplate(afflictionId)
    local normalized = normalizeAfflictionId(afflictionId)
    normalized = AFFLICTION_ALIASES[normalized] or normalized
    return CANONICAL_AFFLICTIONS[normalized], normalized
end

local function applyAfflictionTemplateDefaults(affliction, template)
    if type(template) ~= "table" then
        return
    end

    affliction.id = affliction.id or template.id
    affliction.name = affliction.name or template.name
    affliction.maxStage = affliction.maxStage or template.maxStage
    affliction.stageCosts = affliction.stageCosts or cloneValue(template.stageCosts)
    affliction.stageRecovery = affliction.stageRecovery or cloneValue(template.stageRecovery)
    affliction.stageEffects = affliction.stageEffects or cloneValue(template.stageEffects)
    affliction.recentlyTakenEffect = affliction.recentlyTakenEffect or template.recentlyTakenEffect
    affliction.reexposureClearsCuredStage = affliction.reexposureClearsCuredStage or template.reexposureClearsCuredStage
end

local function syncGhostLotusAfflictionEffects(entity)
    if not entity then
        return
    end
    local stage = math.max(entityAfflictionStage(entity, "ghost_lotus"),
        entityAfflictionStage(entity, "ghostLotus"))
    entity.conditions = entity.conditions or {}
    if stage <= 0 then
        entity.conditions.ghost_lotus_euphoria = nil
        entity.conditions.ghost_lotus_sleep_euphoria = nil
        entity.conditions.ghost_lotus_waking_dream = nil
        entity.ghostLotusEuphoria = false
        entity.ghostLotusSleepEuphoria = false
        entity.ghostLotusMotifRewritePending = false
        if entity.ghostLotusCannotReadWrite then
            entity.conditions.cannot_read = nil
            entity.conditions.cannot_write = nil
            entity.conditions.cannot_read_or_write = nil
            entity.cannotRead = false
            entity.cannotWrite = false
            entity.ghostLotusCannotReadWrite = false
        end
        if entity.ghostLotusIllusionImmune then
            entity.conditions.illusionImmune = nil
            entity.conditions.immune_to_illusions = nil
            entity.immuneToIllusions = false
            entity.ghostLotusIllusionImmune = false
        end
        return
    end

    entity.conditions.ghost_lotus_euphoria = stage >= 1
    entity.ghostLotusEuphoria = stage >= 1

    if stage >= 2 then
        entity.conditions.cannot_read = true
        entity.conditions.cannot_write = true
        entity.conditions.cannot_read_or_write = true
        entity.conditions.illusionImmune = true
        entity.conditions.immune_to_illusions = true
        entity.cannotRead = true
        entity.cannotWrite = true
        entity.immuneToIllusions = true
        entity.ghostLotusCannotReadWrite = true
        entity.ghostLotusIllusionImmune = true
    elseif entity.ghostLotusCannotReadWrite then
        entity.conditions.cannot_read = nil
        entity.conditions.cannot_write = nil
        entity.conditions.cannot_read_or_write = nil
        entity.cannotRead = false
        entity.cannotWrite = false
        entity.ghostLotusCannotReadWrite = false
        if entity.ghostLotusIllusionImmune then
            entity.conditions.illusionImmune = nil
            entity.conditions.immune_to_illusions = nil
            entity.immuneToIllusions = false
            entity.ghostLotusIllusionImmune = false
        end
    end

    if stage >= 3 then
        entity.ghostLotusMotifRewritePending = true
        entity.conditions.ghost_lotus_waking_dream = true
    else
        entity.ghostLotusMotifRewritePending = false
        entity.conditions.ghost_lotus_waking_dream = nil
    end
end

local function syncGiantRatVenomAfflictionEffects(entity)
    if not entity then
        return
    end

    local stage = math.max(entityAfflictionStage(entity, "giant_rat_venom"),
        entityAfflictionStage(entity, "giantRatVenom"))
    entity.conditions = entity.conditions or {}
    entity.nonRecoverableConditions = entity.nonRecoverableConditions or {}

    if stage >= 2 then
        entity.conditions.exhausted = true
        entity.exhausted = true
        entity.nonRecoverableConditions.exhausted = "giant_rat_venom"
        entity.giantRatVenomExhausted = true
    elseif entity.nonRecoverableConditions.exhausted == "giant_rat_venom" then
        entity.conditions.exhausted = false
        entity.exhausted = false
        entity.nonRecoverableConditions.exhausted = nil
        entity.giantRatVenomExhausted = false
    end

    if stage >= 3 then
        entity.conditions.giant_rat_green_mucus = true
        entity.giantRatVenomTestFateWound = true
    else
        entity.conditions.giant_rat_green_mucus = false
        entity.giantRatVenomTestFateWound = false
    end
end

local function syncFaceRatDiseaseAfflictionEffects(entity)
    if not entity then
        return
    end

    local stage = math.max(entityAfflictionStage(entity, "face_rat_disease"),
        entityAfflictionStage(entity, "faceRatDisease"))
    entity.conditions = entity.conditions or {}
    entity.nonRecoverableConditions = entity.nonRecoverableConditions or {}

    if stage <= 0 then
        entity.conditions.face_rat_featureless_mask = nil
        entity.faceRatDiseaseWandsDisfavor = false
        if entity.faceRatDiseaseSilenced then
            entity.conditions.silenced = false
            entity.silenced = false
            entity.nonRecoverableConditions.silenced = nil
            entity.faceRatDiseaseSilenced = false
        end
        if entity.faceRatDiseaseBlind then
            entity.conditions.blind = false
            entity.conditions.blinded = false
            entity.nonRecoverableConditions.blind = nil
            entity.nonRecoverableConditions.blinded = nil
            entity.faceRatDiseaseBlind = false
        end
        return
    end

    entity.conditions.face_rat_featureless_mask = true
    entity.faceRatDiseaseWandsDisfavor = true

    if stage >= 2 then
        entity.conditions.silenced = true
        entity.silenced = true
        entity.nonRecoverableConditions.silenced = "face_rat_disease"
        entity.faceRatDiseaseSilenced = true
    elseif entity.faceRatDiseaseSilenced then
        entity.conditions.silenced = false
        entity.silenced = false
        entity.nonRecoverableConditions.silenced = nil
        entity.faceRatDiseaseSilenced = false
    end

    if stage >= 3 then
        entity.conditions.blind = true
        entity.conditions.blinded = true
        entity.nonRecoverableConditions.blind = "face_rat_disease"
        entity.nonRecoverableConditions.blinded = "face_rat_disease"
        entity.faceRatDiseaseBlind = true
    elseif entity.faceRatDiseaseBlind then
        entity.conditions.blind = false
        entity.conditions.blinded = false
        entity.nonRecoverableConditions.blind = nil
        entity.nonRecoverableConditions.blinded = nil
        entity.faceRatDiseaseBlind = false
    end
end

local function takeAfflictionStageWoundOnce(entity, affliction, effectKey, damageType)
    if not entity or not affliction or not entity.takeWound then
        return nil
    end
    affliction.appliedStageEffects = affliction.appliedStageEffects or {}
    if affliction.appliedStageEffects[effectKey] then
        return nil
    end

    affliction.appliedStageEffects[effectKey] = true
    local wound = entity:takeWound(damageType, {
        source = affliction.id or "affliction",
        reason = effectKey,
    })
    entity.afflictionStageEffects = entity.afflictionStageEffects or {}
    entity.afflictionStageEffects[#entity.afflictionStageEffects + 1] = {
        affliction = affliction.id,
        effect = effectKey,
        damageType = damageType,
        result = wound,
    }
    return wound
end

local function syncGreatContagionAfflictionEffects(entity)
    if not entity then
        return
    end
    local afflictions = entity.afflictions
    local affliction = type(afflictions) == "table" and
        (afflictions.great_contagion or afflictions.greatContagion)
    if type(affliction) ~= "table" then
        return
    end

    affliction.id = affliction.id or "great_contagion"
    affliction.appliedStageEffects = affliction.appliedStageEffects or {}
    local stage = tonumber(affliction.stage or affliction.currentStage or affliction.progressStage) or 1
    entity.conditions = entity.conditions or {}
    if stage >= 1 then
        entity.conditions.red_welts = true
        takeAfflictionStageWoundOnce(entity, affliction, "great_contagion_stage_1_piercing", "piercing")
    end
    if stage >= 2 then
        takeAfflictionStageWoundOnce(entity, affliction, "great_contagion_stage_2_critical", "critical")
    end
    if stage >= 3 and not affliction.appliedStageEffects.great_contagion_stage_3_death then
        affliction.appliedStageEffects.great_contagion_stage_3_death = true
        entity.conditions.dead = true
        entity.dead = true
        entity.greatContagionDeath = true
    end
end

local function syncKnownAfflictionEffects(entity)
    syncGhostLotusAfflictionEffects(entity)
    syncGiantRatVenomAfflictionEffects(entity)
    syncFaceRatDiseaseAfflictionEffects(entity)
    syncGreatContagionAfflictionEffects(entity)
end

--------------------------------------------------------------------------------
-- CAMP STATES
--------------------------------------------------------------------------------
M.STATES = {
    INACTIVE    = "inactive",
    SETUP       = "setup",
    ACTIONS     = "actions",
    BREAK_BREAD = "break_bread",
    WATCH       = "watch",
    RECOVERY    = "recovery",
    TEARDOWN    = "teardown",
}

M.STEP_DETAILS = {
    {
        state = M.STATES.SETUP,
        step = 0,
        label = "Setup",
        appStep = true,
        description = "Prepare the Camp Phase controller and gather shelter or comfort context.",
    },
    {
        state = M.STATES.ACTIONS,
        step = 1,
        label = "Camp Actions",
        description = "Each adventurer has the opportunity to undertake one meaningful activity.",
    },
    {
        state = M.STATES.BREAK_BREAD,
        step = 2,
        label = "Break bread",
        description = "Each adventurer eats one ration and each animal companion eats one animal feed.",
    },
    {
        state = M.STATES.WATCH,
        step = 3,
        label = "No rest for the wicked",
        description = "The GM draws on the Meatgrinder table; random encounters can interrupt camp.",
    },
    {
        state = M.STATES.RECOVERY,
        step = 4,
        label = "Recovery",
        description = "Adventurers burn charged Bonds to clear Stressed, Injured, wounded talents, or regain Resolve.",
    },
    {
        state = M.STATES.TEARDOWN,
        step = 5,
        label = "End of Camp Phase",
        description = "Check bedroll, tent, or fire comfort before the Crawl Phase resumes.",
    },
}

function M.getStepDetails()
    return cloneValue(M.STEP_DETAILS)
end

--------------------------------------------------------------------------------
-- CAMP EVENTS
--------------------------------------------------------------------------------
M.EVENTS = {
    CAMP_START         = "camp_start",
    CAMP_END           = "camp_end",
    CAMP_STEP_CHANGED  = "camp_step_changed",
    RATION_CONSUMED    = "ration_consumed",
    RATION_ASHED       = "ration_ashed",
    NIGHTMARE          = "camp_nightmare",
    VERMIN_THEFT       = "camp_vermin_theft",
    STARVATION_WARNING = "starvation_warning",
    ANIMAL_COMPANION_ABANDONED = "animal_companion_abandoned",
    BOND_SPENT         = "bond_spent",
    CAMP_ACTION_TAKEN  = "camp_action_taken",
    CONDITION_EXPIRED  = "camp_condition_expired",
}

--------------------------------------------------------------------------------
-- CAMP CONTROLLER FACTORY
--------------------------------------------------------------------------------

--- Create a new CampController
-- @param config table: { eventBus, guild, watchManager, inventory }
-- @return CampController instance
function M.createCampController(config)
    config = config or {}

    local controller = {
        eventBus     = config.eventBus or events.globalBus,
        guild        = config.guild or {},
        watchManager = config.watchManager,
        meatgrinder  = config.meatgrinder,
        playerDeck   = config.playerDeck,
        actionResolver = config.actionResolver,
        currentRoom  = config.currentRoom,
        currentRoomId = config.currentRoomId or config.roomId,
        roomManager  = config.roomManager,
        dungeon      = config.dungeon,
        guildMap     = config.guildMap or config.mapState,
        mapState     = config.mapState or config.guildMap,
        traveledRooms = config.traveledRooms or config.roomsTraveled or config.roomsSinceLastCamp,

        -- State tracking
        state        = M.STATES.INACTIVE,
        currentStep  = 0,

        -- Per-camp tracking
        actionsCompleted   = {},  -- { [entityId] = actionData }
        extraCampActionsUsed = {}, -- { [entityId] = true }
        rationsConsumed    = {},  -- { [entityId] = true }
        animalFeedConsumed = {},  -- { [companionId] = true }
        recoveryCompleted  = {},  -- { [entityId] = true }
        watchResolved      = false,
        patrolActive       = false,  -- True if someone took Patrol action

        -- Shelter status (affects recovery quality)
        hasShelter   = false,
        hasBedrolls  = false,
        hasTent      = false,
        hasFire      = false,
        bedrollCount = 0,
        bedrollCapacity = 0,
        bedrollOccupants = nil,
        tentCount    = 0,
        tentCapacity = 0,
        tentOccupants = nil,
        fireViolatesForegoWood = false,
    }

    ----------------------------------------------------------------------------
    -- STATE QUERIES
    ----------------------------------------------------------------------------

    function controller:gainAffliction(entity, afflictionName, opts)
        opts = opts or {}
        if not entity then
            return false, "No entity"
        end

        local template, afflictionId = canonicalAfflictionTemplate(
            afflictionName or opts.affliction or opts.afflictionName or opts.id or opts.name
        )
        if afflictionId == "" then
            return false, "Choose affliction"
        end

        entity.afflictions = entity.afflictions or {}
        local existing = entity.afflictions[afflictionId]
        local reexposed = existing ~= nil
        local affliction = type(existing) == "table" and existing or {
            id = afflictionId,
            stage = 1,
        }
        applyAfflictionTemplateDefaults(affliction, template)

        affliction.id = opts.id or affliction.id or afflictionId
        affliction.name = opts.displayName or opts.name or affliction.name or afflictionId
        affliction.maxStage = opts.maxStage or affliction.maxStage
        affliction.stageCosts = cloneValue(opts.stageCosts or opts.chargeCosts or opts.chargesRequired) or
            affliction.stageCosts
        affliction.stageRecovery = cloneValue(opts.stageRecovery or opts.recoveryByStage) or affliction.stageRecovery
        affliction.stageEffects = cloneValue(opts.stageEffects) or affliction.stageEffects
        affliction.source = opts.source or affliction.source
        affliction.sourceItemId = opts.sourceItemId or affliction.sourceItemId

        local requestedStage = tonumber(opts.stage or opts.currentStage or opts.progressStage)
        local currentStage = tonumber(affliction.stage or 1) or 1
        affliction.stage = reexposed and math.max(currentStage, requestedStage or 1) or
            math.max(1, requestedStage or currentStage)

        local clearedStage = opts.reexposureClearsCuredStage or affliction.reexposureClearsCuredStage
        if reexposed and clearedStage and affliction.curedStages then
            affliction.curedStages[clearedStage] = nil
        end

        if affliction.recentlyTakenEffect then
            affliction.recentlyTaken = true
            entity.recentDrugEffects = entity.recentDrugEffects or {}
            entity.recentDrugEffects[afflictionId] = affliction.recentlyTakenEffect
            if afflictionId == "black_honey" then
                entity.blackHoneyRecentlyTaken = true
                entity.blackHoneyDrawFiveCards = true
            end
        end

        entity.afflictions[afflictionId] = affliction
        syncKnownAfflictionEffects(entity)

        local detail = {
            entity = entity,
            affliction = afflictionId,
            afflictionRecord = affliction,
            stage = affliction.stage,
            reexposed = reexposed,
            result = "affliction_gained",
            clearedCuredStage = reexposed and clearedStage or nil,
        }
        self.eventBus:emit("affliction_gained", detail)

        return true, "affliction_gained", detail
    end

    function controller:getState()
        return self.state
    end

    function controller:getCurrentStep()
        return self.currentStep
    end

    function controller:isActive()
        return self.state ~= M.STATES.INACTIVE
    end

    function controller:detectCampComfortFromGuild()
        local detected = {
            hasBedrolls = false,
            hasTent = false,
            hasFire = false,
            bedrollCount = 0,
            bedrollCapacity = 0,
            tentCount = 0,
            tentCapacity = 0,
            fireViolatesForegoWood = false,
        }

        local function scanItem(item)
            local props = item and item.properties or {}
            local templateId = item and item.templateId
            local name = item and item.name

            if templateId == "bedroll" or name == "Bedroll" or props.bedroll or props.campComfort == "bedroll" then
                detected.hasBedrolls = true
                local quantity = item.quantity or 1
                detected.bedrollCount = detected.bedrollCount + quantity
                detected.bedrollCapacity = detected.bedrollCapacity + quantity * (props.sleepCapacity or props.capacity or 1)
            end
            if templateId == "tent" or name == "Tent" or props.shelter or props.campComfort == "tent" then
                detected.hasTent = true
                local quantity = item.quantity or 1
                detected.tentCount = detected.tentCount + quantity
                detected.tentCapacity = detected.tentCapacity + quantity * (props.sleepCapacity or props.capacity or 2)
            end
            if templateId == "firewood" or name == "Firewood" or props.firewood or props.campComfort == "fire" then
                detected.hasFire = true
                if props.felledWood ~= false and props.archwood ~= true and props.willingWood ~= true then
                    detected.fireViolatesForegoWood = true
                end
            end
        end

        for _, member in ipairs(self.guild or {}) do
            local inv = member and member.inventory
            if inv then
                for _, location in ipairs({ "hands", "belt", "pack" }) do
                    for _, item in ipairs(inv[location] or {}) do
                        scanItem(item)
                    end
                end
            end
        end

        return detected
    end

    ----------------------------------------------------------------------------
    -- START CAMP
    ----------------------------------------------------------------------------

    --- Start the camp phase
    -- @param campConfig table: { hasShelter, hasBedrolls, hasTent, hasFire }
    -- @return boolean, string: success, error message
    function controller:startCamp(campConfig)
        if self.state ~= M.STATES.INACTIVE then
            return false, "Camp already in progress"
        end

        campConfig = campConfig or {}

        -- Reset tracking
        self.actionsCompleted = {}
        self.extraCampActionsUsed = {}
        self.rationsConsumed = {}
        self.animalFeedConsumed = {}
        self.recoveryCompleted = {}
        self.watchResolved = false
        self.patrolActive = false

        local detectedComfort = self:detectCampComfortFromGuild()

        -- Explicit camp flags override inventory-derived comfort.
        self.hasShelter = campConfig.hasShelter or false
        local explicitBedrolls = campConfig.hasBedrolls
        if explicitBedrolls == nil then explicitBedrolls = campConfig.hasBedroll end
        local explicitTent = campConfig.hasTent
        if explicitTent == nil then explicitTent = campConfig.hasTents end
        self.hasBedrolls = explicitBedrolls
        if self.hasBedrolls == nil then self.hasBedrolls = detectedComfort.hasBedrolls end
        self.hasTent = explicitTent
        if self.hasTent == nil then self.hasTent = detectedComfort.hasTent end
        self.bedrollCount = campConfig.bedrollCount or detectedComfort.bedrollCount or 0
        self.bedrollCapacity = campConfig.bedrollCapacity or campConfig.bedrollSlots
        if self.bedrollCapacity == nil then
            self.bedrollCapacity = detectedComfort.bedrollCapacity or 0
            if self.bedrollCapacity <= 0 and self.bedrollCount > 0 then
                self.bedrollCapacity = self.bedrollCount
            elseif self.bedrollCapacity <= 0 and self.hasBedrolls then
                self.bedrollCapacity = 1
            end
        end
        self.bedrollOccupants = campConfig.bedrollOccupants or campConfig.bedrollUsers or campConfig.bedrollAssignments
        if self.bedrollOccupants and countCampListEntries(self.bedrollOccupants) > self.bedrollCapacity then
            return false, "Bedroll capacity exceeded"
        end
        self.tentCount = campConfig.tentCount
        if self.tentCount == nil then
            if (detectedComfort.tentCount or 0) > 0 then
                self.tentCount = detectedComfort.tentCount
            else
                self.tentCount = self.hasTent and 1 or 0
            end
        end
        self.tentCapacity = campConfig.tentCapacity or campConfig.tentSlots
        if self.tentCapacity == nil then
            self.tentCapacity = detectedComfort.tentCapacity or 0
            if self.tentCapacity <= 0 and self.tentCount > 0 then
                self.tentCapacity = self.tentCount * 2
            end
        end
        self.tentOccupants = campConfig.tentOccupants or campConfig.tentUsers or campConfig.tentAssignments
        if self.tentOccupants and countCampListEntries(self.tentOccupants) > self.tentCapacity then
            return false, "Tent capacity exceeded"
        end
        self.hasFire = campConfig.hasFire
        if self.hasFire == nil then self.hasFire = detectedComfort.hasFire end
        self.fireViolatesForegoWood = campConfig.fireViolatesForegoWood
        if self.fireViolatesForegoWood == nil then
            self.fireViolatesForegoWood = campConfig.firewoodBoughtWithGold or campConfig.fireBoughtWithGold or
                campConfig.fireIsFelledWood
        end
        if self.fireViolatesForegoWood == nil then
            self.fireViolatesForegoWood = detectedComfort.fireViolatesForegoWood
        end
        if not self.hasFire then
            self.fireViolatesForegoWood = false
        end

        -- Emit start event
        self.eventBus:emit(M.EVENTS.CAMP_START, {
            guild = self.guild,
            hasShelter = self.hasShelter,
            hasBedrolls = self.hasBedrolls,
            bedrollCapacity = self.bedrollCapacity,
            bedrollOccupants = self.bedrollOccupants,
            hasTent = self.hasTent,
            tentCapacity = self.tentCapacity,
            tentOccupants = self.tentOccupants,
            hasFire = self.hasFire,
            fireViolatesForegoWood = self.fireViolatesForegoWood,
        })

        -- Move to setup
        self:transitionTo(M.STATES.SETUP)

        return true
    end

    ----------------------------------------------------------------------------
    -- STATE TRANSITIONS
    ----------------------------------------------------------------------------

    --- Transition to a new state
    function controller:transitionTo(newState)
        local oldState = self.state
        self.state = newState

        -- Map state to step number
        local stepMap = {
            [M.STATES.SETUP]       = 0,
            [M.STATES.ACTIONS]     = 1,
            [M.STATES.BREAK_BREAD] = 2,
            [M.STATES.WATCH]       = 3,
            [M.STATES.RECOVERY]    = 4,
            [M.STATES.TEARDOWN]    = 5,
        }
        self.currentStep = stepMap[newState] or 0

        self.eventBus:emit(M.EVENTS.CAMP_STEP_CHANGED, {
            oldState = oldState,
            newState = newState,
            step = self.currentStep,
        })

        print("[CAMP] Transitioned to: " .. newState .. " (Step " .. self.currentStep .. ")")

        -- Auto-execute certain steps
        if newState == M.STATES.SETUP then
            self:executeSetup()
        elseif newState == M.STATES.RECOVERY then
            for _, pc in ipairs(self.guild) do
                self:beginRecovery(pc)
            end
        end
    end

    --- Advance to next step
    function controller:advanceStep()
        if self.state == M.STATES.SETUP then
            self:transitionTo(M.STATES.ACTIONS)
        elseif self.state == M.STATES.ACTIONS then
            if self:canAdvanceFromActions() then
                self:transitionTo(M.STATES.BREAK_BREAD)
            else
                return false, "Not all adventurers have taken actions"
            end
        elseif self.state == M.STATES.BREAK_BREAD then
            if self:canAdvanceFromBreakBread() then
                self:transitionTo(M.STATES.WATCH)
            else
                return false, "Rations not resolved for all adventurers"
            end
        elseif self.state == M.STATES.WATCH then
            if self.watchResolved then
                self:transitionTo(M.STATES.RECOVERY)
            else
                return false, "Watch not resolved"
            end
        elseif self.state == M.STATES.RECOVERY then
            self:finalizeRecovery()
            self:transitionTo(M.STATES.TEARDOWN)
        elseif self.state == M.STATES.TEARDOWN then
            self:endCamp()
        end

        return true
    end

    ----------------------------------------------------------------------------
    -- STEP 0: SETUP
    ----------------------------------------------------------------------------

    function controller:executeSetup()
        -- Check shelter conditions
        if not self.hasShelter then
            print("[CAMP] Warning: No shelter - reduced recovery quality")
        end

        -- Auto-advance to actions after brief setup
        self:transitionTo(M.STATES.ACTIONS)
    end

    ----------------------------------------------------------------------------
    -- STEP 1: ACTIONS (S8.3)
    ----------------------------------------------------------------------------

    function controller:canUseLaborUnending(entity)
        if not entity or not entity.id then
            return false, "No actor"
        end
        if self.extraCampActionsUsed[entity.id] then
            return false, "Labor Unending already used"
        end
        if not hasControllerUsableTalent(entity, "labor_unending") then
            return false, "Requires Labor Unending"
        end
        if entity.conditions and entity.conditions.stressed then
            return false, "Already Stressed"
        end
        return true, nil
    end

    function controller:markLaborUnendingUsed(entity)
        entity.conditions = entity.conditions or {}
        entity.conditions.stressed = true
        self.extraCampActionsUsed[entity.id] = true
        self.eventBus:emit("labor_unending_used", {
            entity = entity,
            actor = entity,
        })
    end

    --- Submit a camp action for an adventurer
    -- @param entity table: The adventurer
    -- @param actionData table: { type, target, ... }
    function controller:submitAction(entity, actionData)
        if self.state ~= M.STATES.ACTIONS then
            return false, "Not in actions phase"
        end

        local previousAction = self.actionsCompleted[entity.id]
        local laborUnendingExtra = false
        if previousAction then
            if actionData.useLaborUnending == true or actionData.laborUnending == true then
                local canUseLabor, laborReason = self:canUseLaborUnending(entity)
                if not canUseLabor then
                    return false, laborReason
                end
                laborUnendingExtra = true
            else
                return false, "Action already taken"
            end
        end

        -- Add actor to action data
        actionData.actor = entity

        local actionsCompleted = self.actionsCompleted
        if laborUnendingExtra then
            actionsCompleted = {}
            for id, completedAction in pairs(self.actionsCompleted) do
                if id ~= entity.id then
                    actionsCompleted[id] = completedAction
                end
            end
        end

        -- Resolve the action through camp_actions module
        local context = {
            eventBus = self.eventBus,
            guild = self.guild,
            patrolActive = self.patrolActive,
            actionsCompleted = actionsCompleted,
            campController = self,
            playerDeck = self.playerDeck,
            laborUnendingExtra = laborUnendingExtra,
            currentRoom = actionData.currentRoom or self.currentRoom,
            currentRoomId = actionData.currentRoomId or actionData.roomId or self.currentRoomId,
            roomManager = self.roomManager,
            dungeon = self.dungeon,
            watchManager = actionData.watchManager or self.watchManager,
            guildMap = actionData.guildMap or actionData.mapState or self.guildMap or self.mapState,
            mapState = actionData.mapState or actionData.guildMap or self.mapState or self.guildMap,
            traveledRooms = actionData.traveledRooms or actionData.roomsTraveled or
                actionData.roomsSinceLastCamp or actionData.rooms or self.traveledRooms,
        }

        local success, result = campActions.resolveAction(actionData, context)
        local actionAccepted = success or isAcceptedFailedTestOutcome(actionData, result)

        local promptOnlyResult = result == "alchemy_choices_required" or
            result == "book_question_required" or
            result == "devour_living_test_required"

        if actionAccepted and not promptOnlyResult then
            -- Track patrol status for watch phase
            if actionData.type == "patrol" then
                self.patrolActive = true
            end

            if laborUnendingExtra then
                actionData.laborUnendingExtra = true
                self:markLaborUnendingUsed(entity)
                self.actionsCompleted[entity.id] = {
                    type = "labor_unending",
                    actor = entity,
                    laborUnending = true,
                    actions = { previousAction, actionData },
                }
            else
                self.actionsCompleted[entity.id] = actionData
            end
            if actionData.type == "train" and actionData.target then
                self.actionsCompleted[actionData.target.id] = {
                    type = "train_mentor",
                    actor = actionData.target,
                    target = entity,
                    talentId = actionData.talentId or (actionData.request and actionData.request.talentId),
                }
            end

            self.eventBus:emit(M.EVENTS.CAMP_ACTION_TAKEN, {
                entity = entity,
                action = actionData,
                result = result,
            })

            print("[CAMP] " .. entity.name .. " takes action: " .. (actionData.type or "unknown"))
        end

        return actionAccepted, result
    end

    --- Get available camp actions for an entity
    function controller:getAvailableActions(entity)
        return campActions.getAvailableActions(entity, self.guild, {
            currentRoom = self.currentRoom,
            currentRoomId = self.currentRoomId,
            roomManager = self.roomManager,
        })
    end

    function controller:canAdvanceFromActions()
        -- Check all guild members have submitted actions
        for _, pc in ipairs(self.guild) do
            if not self.actionsCompleted[pc.id] then
                return false
            end
        end
        return true
    end

    ----------------------------------------------------------------------------
    -- STEP 2: BREAK BREAD (S8.2)
    ----------------------------------------------------------------------------

    local function isCampRationItem(item)
        local props = item and item.properties or {}
        return item and (item.isRation or
               item.type == "ration" or
               item.itemType == "ration" or
               props.isRation or
               props.isCampMeal or
               (item.name and item.name:lower():find("ration")))
    end

    local function isEmergencyRationSubstitute(item)
        local props = item and item.properties or {}
        return item and (props.emergencyRation == true or
               props.rationSubstitute == true or
               item.emergencyRation == true or
               item.rationSubstitute == true)
    end

    local function findRationItem(entity)
        if not entity.inventory or not entity.inventory.findItemByPredicate then
            return nil, nil
        end

        local ration, location = entity.inventory:findItemByPredicate(isCampRationItem)
        if ration then
            return ration, location
        end

        return entity.inventory:findItemByPredicate(isEmergencyRationSubstitute)
    end

    local function campConsumableChoice(item, location, kind)
        local props = item and item.properties or {}
        return {
            id = item and item.id or nil,
            name = item and item.name or nil,
            templateId = item and item.templateId or nil,
            location = location,
            quantity = item and (item.quantity or 1) or 0,
            kind = kind,
            isMeal = props.isCampMeal == true,
            emergencySubstitute = kind == "emergency_substitute",
            feedFor = props.feedFor or props.animalType or props.animalKind,
        }
    end

    local function campConsumableChoices(entity, predicate, kind)
        local choices = {}
        local count = 0
        local inv = entity and entity.inventory
        if not inv then
            return choices, count
        end

        for _, location in ipairs({ "hands", "belt", "pack" }) do
            for _, item in ipairs(inv[location] or {}) do
                if predicate(item) then
                    local quantity = item.quantity or 1
                    count = count + quantity
                    choices[#choices + 1] = campConsumableChoice(item, location, kind)
                end
            end
        end
        return choices, count
    end

    local function rationChoicesForEntity(entity)
        local rationChoices, rationCount = campConsumableChoices(entity, isCampRationItem, "ration")
        local substituteChoices, substituteCount =
            campConsumableChoices(entity, isEmergencyRationSubstitute, "emergency_substitute")
        return rationChoices, rationCount, substituteChoices, substituteCount
    end

    local function removeConsumableItem(entity, item)
        if not entity.inventory or not item then
            return false
        end

        if entity.inventory.removeItemQuantity then
            local ok = entity.inventory:removeItemQuantity(item.id, 1)
            return ok == true
        elseif entity.inventory.removeItem then
            local removed = entity.inventory:removeItem(item.id)
            return removed ~= nil
        end

        return false
    end

    local function hasMaledictionFlag(entity, flag)
        if not entity then
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

    local function maledictionMetadata(entity)
        local malediction = entity and entity.malediction
        if malediction and malediction.active ~= false then
            return malediction.metadata or {}
        end
        return {}
    end

    local function indexedOpt(value, index, item)
        if type(value) ~= "table" then
            return value
        end
        if value[index] ~= nil then
            return value[index]
        end
        if item and value[item.id] ~= nil then
            return value[item.id]
        end
        if item and value[item.templateId] ~= nil then
            return value[item.templateId]
        end
        return nil
    end

    local function firstProvided(...)
        for i = 1, select("#", ...) do
            local value = select(i, ...)
            if value ~= nil then
                return value
            end
        end
        return nil
    end

    local function nextRecoveryWoundResult(entity)
        if not entity or not entity.conditions then
            return nil
        end
        if entity.conditions.deaths_door then
            return "deaths_door_healed"
        end
        if entity.conditions.stressed then
            return nil
        end
        if entity.conditions.injured then
            return "injured_healed"
        end
        if entity.conditions.staggered then
            return "staggered_healed"
        end
        if (entity.woundedTalents or 0) > 0 then
            return "talent_healed"
        end
        if (entity.armorNotches or 0) > 0 then
            return "armor_repaired"
        end
        return "fully_healed"
    end

    local function recoveryNeedsExtraBond(entity)
        if not hasMaledictionFlag(entity, "maledictionExtraBondRecoveryCost") then
            return false
        end
        local nextResult = nextRecoveryWoundResult(entity)
        return nextResult == "injured_healed" or nextResult == "talent_healed"
    end

    local function selectExtraRecoveryBond(entity, primaryBondTargetId, opts)
        opts = opts or {}
        local requested = opts.extraBondTargetId or opts.secondBondTargetId or
            opts.additionalBondTargetId or opts.extraRecoveryBondTargetId
        if requested and requested == primaryBondTargetId then
            return nil, "Second recovery Bond must be different"
        end
        if requested then
            local bond = entity.bonds and entity.bonds[requested]
            if not bond or not bond.charged then
                return nil, "Requires two charged Bonds"
            end
            return requested, nil
        end

        for targetId, bond in pairs(entity.bonds or {}) do
            if targetId ~= primaryBondTargetId and bond.charged then
                return targetId, nil
            end
        end

        return nil, "Requires two charged Bonds"
    end

    local function normalizeCampActionType(value)
        value = tostring(value or ""):lower()
        value = value:gsub("[’']", "")
        value = value:gsub("[^%w]+", "_")
        return value:gsub("^_+", ""):gsub("_+$", "")
    end

    local function actionHistoryHasRest(action)
        if type(action) ~= "table" then
            return false
        end

        local actionType = normalizeCampActionType(action.type or action.id or action.action)
        if actionType == "rest" or actionType == "rest_and_recover" then
            return true
        end
        for _, nested in ipairs(action.actions or {}) do
            if actionHistoryHasRest(nested) then
                return true
            end
        end
        return false
    end

    local function tookRestAndRecoverAction(controllerRef, entity)
        if not controllerRef or not entity or not entity.id then
            return false
        end
        return actionHistoryHasRest(controllerRef.actionsCompleted and controllerRef.actionsCompleted[entity.id])
    end

    local function foodTurnsToAsh(entity, opts, index, item)
        if not hasMaledictionFlag(entity, "foodMayTurnToAsh") then
            return false
        end

        local explicit = indexedOpt(firstProvided(opts.rationAsh, opts.ashFood, opts.foodTurnsToAsh), index, item)
        if explicit ~= nil then
            return explicit == true
        end

        local metadata = maledictionMetadata(entity)
        local chance = tonumber(entity.rationAshChance or metadata.rationAshChance) or 0.5
        local roll = indexedOpt(firstProvided(opts.rationAshRoll, opts.ashRoll, opts.foodAshRoll), index, item)
        if roll ~= nil then
            return (tonumber(roll) or 1) <= chance
        end

        return math.random() <= chance
    end

    local function badDreamsWakeStressed(entity, opts)
        opts = opts or {}
        if not hasMaledictionFlag(entity, "badDreams") then
            return false
        end
        if entityHasAfflictionStage(entity, "ghost_lotus", 1) or
           entityHasAfflictionStage(entity, "ghostLotus", 1) then
            entity.conditions = entity.conditions or {}
            entity.conditions.ghost_lotus_sleep_euphoria = true
            entity.ghostLotusSleepEuphoria = true
            return false
        end

        local explicit = firstProvided(opts.badDreams, opts.badDream, opts.nightmare)
        if explicit ~= nil then
            return explicit == true
        end

        local metadata = maledictionMetadata(entity)
        local chance = tonumber(entity.wakeStressedChance or metadata.wakeStressedChance) or 0.5
        local roll = firstProvided(opts.badDreamRoll, opts.nightmareRoll, opts.wakeStressedRoll)
        if roll ~= nil then
            return (tonumber(roll) or 1) <= chance
        end

        return math.random() <= chance
    end

    local function verminStealFromPack(entity, opts)
        opts = opts or {}
        if not hasMaledictionFlag(entity, "verminFollow") then
            return nil
        end

        local inv = entity.inventory
        if not inv or not inv.pack or #inv.pack == 0 then
            return nil
        end

        local explicit = firstProvided(opts.verminTheft, opts.verminPackSwap, opts.verminSwap)
        if explicit ~= nil and explicit == false then
            return nil
        end

        if explicit == nil then
            local metadata = maledictionMetadata(entity)
            local chance = tonumber(entity.nightlyPackSwapChance or metadata.nightlyPackSwapChance) or 0.5
            local roll = firstProvided(opts.verminTheftRoll, opts.verminPackSwapRoll, opts.verminSwapRoll)
            if roll ~= nil then
                if (tonumber(roll) or 1) > chance then
                    return nil
                end
            elseif math.random() > chance then
                return nil
            end
        end

        local itemId = opts.verminTheftItemId or opts.verminItemId
        local item = nil
        if itemId and inv.findItem then
            local found, location = inv:findItem(itemId)
            if location == inventory.LOCATIONS.PACK then
                item = found
            end
        end

        if not item then
            local index = math.max(1, math.floor(tonumber(opts.verminTheftIndex or opts.verminPackIndex) or 1))
            item = inv.pack[index] or inv.pack[1]
        end

        if not item then
            return nil
        end

        local removed = inv.removeItem and inv:removeItem(item.id) or nil
        if not removed then
            return nil
        end

        local garbage = opts.verminGarbageItem or inventory.createItem({
            name = opts.verminGarbageName or "Nice Garbage",
            size = 1,
            durability = 1,
            properties = {
                garbage = true,
                niceGarbage = true,
                verminReplacement = true,
            },
        })
        local added, addReason = inv:addItem(garbage, inventory.LOCATIONS.PACK)

        local detail = {
            entity = entity,
            stolenItem = removed,
            garbageItem = garbage,
            garbageAdded = added == true,
            addReason = addReason,
            curseId = entity.maledictionCurseId or "beloved_by_vermin",
            result = "vermin_pack_swap",
        }
        entity.verminThefts = entity.verminThefts or {}
        entity.verminThefts[#entity.verminThefts + 1] = detail

        return detail
    end

    local function animalCompanionEntries(owner)
        local entries = {}

        for key, companion in pairs(owner and owner.animalCompanions or {}) do
            if type(companion) == "table" then
                entries[#entries + 1] = {
                    key = key,
                    companion = companion,
                }
            end
        end

        table.sort(entries, function(a, b)
            return tostring(a.key) < tostring(b.key)
        end)

        return entries
    end

    local function findAnimalCompanion(owner, companionId)
        for _, entry in ipairs(animalCompanionEntries(owner)) do
            local companion = entry.companion
            if not companionId or companion.id == companionId or companion.name == companionId or
               entry.key == companionId then
                return companion
            end
        end
        return nil
    end

    local function companionFeedKey(owner, companion, key)
        if companion and companion.id then
            return companion.id
        end

        if key == nil then
            for _, entry in ipairs(animalCompanionEntries(owner)) do
                if entry.companion == companion then
                    key = entry.key
                    break
                end
            end
        end

        local ownerId = owner and owner.id or "owner"
        return ownerId .. "_companion_" .. tostring(key or companion)
    end

    local function removeAnimalCompanion(owner, companion, key)
        if not owner or not companion then
            return false
        end

        local removed = false
        local companions = owner.animalCompanions
        if type(companions) == "table" then
            if key ~= nil and companions[key] == companion then
                if type(key) == "number" then
                    table.remove(companions, key)
                else
                    companions[key] = nil
                end
                removed = true
            else
                for entryKey, entry in pairs(companions) do
                    if entry == companion then
                        if type(entryKey) == "number" then
                            table.remove(companions, entryKey)
                        else
                            companions[entryKey] = nil
                        end
                        removed = true
                        break
                    end
                end
            end
        end

        if owner.companion == companion then
            owner.companion = nil
            removed = true
        end

        if type(owner.companions) == "table" then
            for entryKey, entry in pairs(owner.companions) do
                if entry == companion then
                    owner.companions[entryKey] = nil
                    removed = true
                end
            end
        end

        if owner.familiarCompanionId and companion.id and owner.familiarCompanionId == companion.id then
            owner.familiarCompanionId = nil
        end

        return removed
    end

    local function animalFeedMatchesCompanion(item, companion)
        local props = item and item.properties or {}
        local feedFor = props.feedFor or props.animalType or props.animalKind

        if not feedFor or feedFor == "any" then
            return true
        end

        feedFor = normalizeFeedKey(feedFor)
        local candidates = {
            companion and companion.id,
            companion and companion.type,
            companion and companion.animalType,
            companion and companion.species,
            companion and companion.feedType,
            companion and companion.kind,
            companion and companion.name,
        }

        for _, candidate in pairs(candidates) do
            if candidate and normalizeFeedKey(candidate) == feedFor then
                return true
            end
        end

        return false
    end

    local function findAnimalFeedItem(owner, companion)
        if not owner or not owner.inventory or not owner.inventory.findItemByPredicate then
            return nil, nil
        end

        return owner.inventory:findItemByPredicate(function(item)
            local props = item.properties or {}
            local isFeed = item.type == "animal_feed" or
                           item.itemType == "animal_feed" or
                           props.isAnimalFeed or
                           props.animalFeed
            return isFeed and animalFeedMatchesCompanion(item, companion)
        end)
    end

    local function animalFeedChoicesForCompanion(owner, companion)
        return campConsumableChoices(owner, function(item)
            local props = item and item.properties or {}
            local isFeed = item and (item.type == "animal_feed" or
                           item.itemType == "animal_feed" or
                           props.isAnimalFeed or
                           props.animalFeed)
            return isFeed and animalFeedMatchesCompanion(item, companion)
        end, "animal_feed")
    end

    local function hasUsableTalent(entity, talentId)
        if not entity then
            return false
        end

        if entity.canUseTalent and entity:canUseTalent(talentId) then
            return true
        end

        local talent = entity.talents and entity.talents[talentId]
        if type(talent) == "table" then
            return not talent.wounded
        end
        return talent == true
    end

    local function canChargeBond(entity, targetId)
        if not targetId or not entity.bonds then
            return false
        end

        local bond = entity.bonds[targetId]
        return bond ~= nil and not bond.charged
    end

    local function chargeBond(entity, targetId)
        if not canChargeBond(entity, targetId) then
            return false
        end

        entity.bonds[targetId].charged = true
        return true
    end

    local function activeGluttonyPact(entity)
        return campActions.findUnbrokenActivePact(entity, "gluttony")
    end

    local function activeDevourLivingPact(entity)
        return campActions.findUnbrokenActivePact(entity, "devour_living")
    end

    local function breakPactWithReason(controllerRef, entity, pact, reason)
        if not pact then
            return nil
        end

        local ok, result, detail = campActions.breakPact(entity, pact, {
            eventBus = controllerRef.eventBus,
            actionResolver = controllerRef.actionResolver,
            reason = reason,
        })
        if not ok then
            return {
                result = result,
            }
        end

        return detail
    end

    local function breakGluttonyPact(controllerRef, entity, pact)
        return breakPactWithReason(controllerRef, entity, pact, "gluttony_underfed")
    end

    local function breakDevourLivingPact(controllerRef, entity, pact)
        return breakPactWithReason(controllerRef, entity, pact, "devour_living_forbidden_food")
    end

    local function breakPactsForRecoveryResult(controllerRef, entity, recoveryResult)
        return campActions.breakPactsForRecoveryResult(entity, recoveryResult, {
            eventBus = controllerRef.eventBus,
            actionResolver = controllerRef.actionResolver,
        })
    end

    function controller:markAdventurerUnfed(entity, opts)
        opts = opts or {}
        entity.starvationCount = (entity.starvationCount or 0) + 1

        -- First missed meal: Stressed
        if not entity.conditions then
            entity.conditions = {}
        end
        entity.conditions.stressed = true

        -- Second consecutive missed meal: Starving
        if entity.starvationCount >= 2 then
            entity.conditions.starving = true
            self.eventBus:emit(M.EVENTS.STARVATION_WARNING, {
                entity = entity,
                severity = "starving",
            })
            print("[CAMP] " .. entity.name .. " is STARVING!")
        else
            self.eventBus:emit(M.EVENTS.STARVATION_WARNING, {
                entity = entity,
                severity = "hungry",
            })
            print("[CAMP] " .. entity.name .. " goes hungry (stressed)")
        end

        if opts.ashedItems and #opts.ashedItems > 0 then
            self.eventBus:emit(M.EVENTS.RATION_ASHED, {
                entity = entity,
                items = opts.ashedItems,
                count = #opts.ashedItems,
                result = opts.result or "ration_ashed",
            })
        end

        self.rationsConsumed[entity.id] = true
        self:resolveAnimalFeedsForOwner(entity)
        return false, opts.result or "no_ration"
    end

    function controller:sleepSuspendsFoodRequirement(entity)
        if not entity then
            return false
        end

        local conditions = entity.conditions or {}
        local sleep = entity.sleep or {}
        return conditions.sleeping == true and (
            sleep.noFoodRequired == true or
            entity.requiresNoFoodWhileAsleep == true
        )
    end

    function controller:markAdventurerFoodRequirementSuspended(entity)
        entity.starvationCount = 0
        if entity.conditions then
            entity.conditions.starving = false
        end
        if entity.sleep then
            entity.sleep.foodRequirementSuspended = true
        end

        self.rationsConsumed[entity.id] = true
        self.eventBus:emit(M.EVENTS.RATION_CONSUMED, {
            entity = entity,
            count = 0,
            sleepNoFoodRequired = true,
            result = "sleep_no_food_required",
        })
        self:resolveAnimalFeedsForOwner(entity)
        return true, "sleep_no_food_required"
    end

    function controller:getBreakBreadOptions(opts)
        opts = opts or {}
        local selectedEntity = opts.entity or opts.actor or opts.selectedEntity or opts.selectedActor
        local selectedKey = entityComfortKey(selectedEntity) or opts.entityId or opts.actorId or
            opts.selectedEntityId or opts.selectedActorId
        local actors = {}
        local pendingActors = {}
        local pendingAnimalFeeds = {}

        for _, entity in ipairs(opts.guild or opts.actors or self.guild or {}) do
            local actorOpts = opts
            if opts.byActor and entity and entity.id and opts.byActor[entity.id] then
                actorOpts = opts.byActor[entity.id]
            end

            local rationChoices, rationCount, substituteChoices, substituteCount =
                rationChoicesForEntity(entity)
            local chargeableBonds = {}
            for targetId, bond in pairs(entity and entity.bonds or {}) do
                if not bond.charged then
                    chargeableBonds[#chargeableBonds + 1] = {
                        targetId = targetId,
                        bond = cloneValue(bond),
                    }
                end
            end
            table.sort(chargeableBonds, function(a, b)
                return tostring(a.targetId) < tostring(b.targetId)
            end)

            local resolved = entity and entity.id and self.rationsConsumed[entity.id] == true
            local gluttonyPact = activeGluttonyPact(entity)
            local devourPact = activeDevourLivingPact(entity)
            local selectedChargeTarget = actorOpts.chargeBondTargetId or actorOpts.bondTargetId
            local canUseHaleAndHearty = hasUsableTalent(entity, "hale_and_hearty") and
                canChargeBond(entity, selectedChargeTarget)
            local explicitRationCount = actorOpts.rationCount ~= nil or actorOpts.rations ~= nil
            local requestedRations = actorOpts.rationCount or actorOpts.rations or
                (canUseHaleAndHearty and 2 or 1)
            requestedRations = math.max(1, tonumber(requestedRations) or 1)
            if gluttonyPact and not explicitRationCount then
                requestedRations = math.max(requestedRations, 2)
            end

            local totalFoodCount = rationCount + substituteCount
            local devourLivingFood = actorOpts.livingFood == true or actorOpts.devourLivingFood == true or
                (entity and entity.devourLivingMealAvailable == true)
            local devourForbiddenFood = actorOpts.consumeForbiddenRation == true or
                actorOpts.eatForbiddenRation == true or actorOpts.allowForbiddenRation == true
            local sleepSuspendsFood = self:sleepSuspendsFoodRequirement(entity)
            local resultPreview = "ration_consumed"
            local wouldMarkStressed = false
            local wouldMarkStarving = false
            local pactBreaks = {}

            if resolved then
                resultPreview = "already_resolved"
            elseif sleepSuspendsFood then
                resultPreview = "sleep_no_food_required"
            elseif devourPact and devourLivingFood then
                resultPreview = "living_food_consumed"
            elseif devourPact and not devourForbiddenFood then
                resultPreview = entity and entity.devourLivingForageFailed and
                    "devour_living_starving" or "devour_living_no_food"
                wouldMarkStressed = true
                wouldMarkStarving = ((entity and entity.starvationCount or 0) + 1) >= 2
            elseif totalFoodCount <= 0 then
                resultPreview = "no_ration"
                wouldMarkStressed = true
                wouldMarkStarving = ((entity and entity.starvationCount or 0) + 1) >= 2
            elseif gluttonyPact and totalFoodCount < 2 then
                resultPreview = "ration_consumed_pact_broken"
                pactBreaks[#pactBreaks + 1] = "gluttony"
            elseif devourPact and devourForbiddenFood then
                resultPreview = "ration_consumed_pact_broken"
                pactBreaks[#pactBreaks + 1] = "devour_living"
            elseif canUseHaleAndHearty and totalFoodCount >= 2 then
                resultPreview = "ration_consumed_bond_charged"
            end

            local animalFeedPreviews = {}
            for _, entry in ipairs(animalCompanionEntries(entity)) do
                local companion = entry.companion
                local feedKey = companionFeedKey(entity, companion, entry.key)
                local feedChoices, feedCount = animalFeedChoicesForCompanion(entity, companion)
                local conditions = companion and companion.conditions or {}
                local feedResolved = self.animalFeedConsumed[feedKey] == true
                local companionResult = "animal_feed_consumed"
                local wouldBecomeWeak = false
                local wouldBecomeStarving = false
                local wouldAbandon = false
                local starvationCount = companion and (companion.starvationCount or 0) or 0
                local nextStarvationCount = starvationCount

                if feedResolved then
                    companionResult = "animal_feed_already_resolved"
                elseif companion and (companion.abandoned or conditions.abandoned) then
                    companionResult = "animal_companion_abandoned"
                elseif companion and (companion.suppliesOwnFood or companion.selfFeeding) then
                    companionResult = "animal_feed_self_supplied"
                elseif feedCount <= 0 then
                    nextStarvationCount = starvationCount + 1
                    local abandonAt = tonumber(companion and companion.abandonAtStarvationCount) or 3
                    wouldBecomeWeak = true
                    wouldBecomeStarving = nextStarvationCount >= 2
                    wouldAbandon = companion and (
                        companion.abandonNextMissedFeed == true or nextStarvationCount >= abandonAt
                    ) or false
                    companionResult = wouldAbandon and "animal_companion_abandoned" or "no_animal_feed"
                end

                if not feedResolved then
                    pendingAnimalFeeds[#pendingAnimalFeeds + 1] = feedKey
                end

                animalFeedPreviews[#animalFeedPreviews + 1] = {
                    key = entry.key,
                    feedKey = feedKey,
                    companionId = companion and companion.id or nil,
                    companionName = companion and companion.name or nil,
                    resolved = feedResolved,
                    selfFeeding = companion and (companion.suppliesOwnFood or companion.selfFeeding) == true,
                    abandoned = companion and (companion.abandoned or conditions.abandoned) == true,
                    matchingFeedChoices = feedChoices,
                    matchingFeedCount = feedCount,
                    resultPreview = companionResult,
                    starvationCount = starvationCount,
                    nextStarvationCount = nextStarvationCount,
                    wouldClearStaggered = feedCount > 0 and conditions.staggered == true,
                    wouldClearWeak = feedCount > 0 and (conditions.weak == true or companion.weak == true),
                    wouldClearStarving = feedCount > 0 and (conditions.starving == true or companion.starving == true),
                    wouldBecomeWeak = wouldBecomeWeak,
                    wouldBecomeStarving = wouldBecomeStarving,
                    wouldAbandon = wouldAbandon,
                }
            end

            if not resolved then
                pendingActors[#pendingActors + 1] = entity and entity.id or tostring(#pendingActors + 1)
            end

            actors[#actors + 1] = {
                entity = entity,
                entityId = entity and entity.id or nil,
                entityName = entity and entity.name or nil,
                selected = selectedKey ~= nil and entityComfortKey(entity) == selectedKey,
                resolved = resolved,
                rationChoices = rationChoices,
                rationCount = rationCount,
                emergencySubstituteChoices = substituteChoices,
                emergencySubstituteCount = substituteCount,
                totalFoodCount = totalFoodCount,
                requestedRations = requestedRations,
                requiredRations = gluttonyPact and 2 or 1,
                canUseHaleAndHearty = canUseHaleAndHearty,
                haleAndHeartyTalent = hasUsableTalent(entity, "hale_and_hearty"),
                selectedChargeBondTargetId = selectedChargeTarget,
                chargeableBonds = chargeableBonds,
                gluttonyPactActive = gluttonyPact ~= nil,
                devourLivingPactActive = devourPact ~= nil,
                devourLivingMealAvailable = devourLivingFood,
                devourLivingForageFailed = entity and entity.devourLivingForageFailed == true,
                forbiddenRationWouldBreakDevourLiving = devourPact ~= nil and totalFoodCount > 0,
                sleepSuspendsFoodRequirement = sleepSuspendsFood,
                ashFoodPossible = hasMaledictionFlag(entity, "foodMayTurnToAsh"),
                resultPreview = resultPreview,
                pactBreaks = pactBreaks,
                starvationCount = entity and (entity.starvationCount or 0) or 0,
                nextStarvationCount = wouldMarkStressed and
                    ((entity and entity.starvationCount or 0) + 1) or 0,
                wouldMarkStressed = wouldMarkStressed,
                wouldMarkStarving = wouldMarkStarving,
                animalFeeds = animalFeedPreviews,
            }
        end

        return {
            result = "break_bread_options_ready",
            state = self.state,
            inBreakBreadPhase = self.state == M.STATES.BREAK_BREAD,
            canAdvanceNow = self:canAdvanceFromBreakBread(),
            pendingActors = pendingActors,
            pendingAnimalFeeds = pendingAnimalFeeds,
            rules = {
                oneRationPerAdventurer = true,
                gluttonyRequiresTwoRations = true,
                haleAndHeartyCanEatSecondRationToChargeBond = true,
                lardIsEmergencyRationSubstitute = true,
                devourLivingRequiresLivingFood = true,
                sleepCanSuspendFoodRequirement = true,
            },
            actors = actors,
        }
    end

    --- Consume a ration for an adventurer (S9.2)
    -- @param entity table: The adventurer
    -- @param opts table: Optional { rationCount, chargeBondTargetId }
    -- @return boolean, string: success, result description
    function controller:consumeRation(entity, opts)
        if self.state ~= M.STATES.BREAK_BREAD then
            return false, "Not in break bread phase"
        end

        opts = opts or {}

        if self:sleepSuspendsFoodRequirement(entity) then
            return self:markAdventurerFoodRequirementSuspended(entity)
        end

        local canUseHaleAndHearty = hasUsableTalent(entity, "hale_and_hearty") and
            canChargeBond(entity, opts.chargeBondTargetId)
        local explicitRationCount = opts.rationCount ~= nil or opts.rations ~= nil
        local gluttonyPact = activeGluttonyPact(entity)
        local devourPact = activeDevourLivingPact(entity)
        local devourLivingFood = opts.livingFood == true or opts.devourLivingFood == true or
            entity.devourLivingMealAvailable == true
        local devourForbiddenFood = opts.consumeForbiddenRation == true or opts.eatForbiddenRation == true or
            opts.allowForbiddenRation == true

        if devourPact and devourLivingFood then
            entity.starvationCount = 0
            if entity.conditions and entity.conditions.starving then
                entity.conditions.starving = false
            end
            entity.devourLivingMealAvailable = false
            entity.devourLivingForageFailed = false

            self.rationsConsumed[entity.id] = true
            self.eventBus:emit(M.EVENTS.RATION_CONSUMED, {
                entity = entity,
                count = 0,
                livingFood = true,
                pact = devourPact,
                result = "living_food_consumed",
            })

            print("[CAMP] " .. entity.name .. " ate living vermin")
            self:resolveAnimalFeedsForOwner(entity)
            return true, "living_food_consumed"
        end

        if devourPact and not devourForbiddenFood then
            return self:markAdventurerUnfed(entity, {
                result = entity.devourLivingForageFailed and "devour_living_starving" or "devour_living_no_food",
            })
        end

        local requestedRations = opts.rationCount or opts.rations or (canUseHaleAndHearty and 2 or 1)
        requestedRations = math.max(1, tonumber(requestedRations) or 1)
        if gluttonyPact and not explicitRationCount then
            requestedRations = math.max(requestedRations, 2)
        end

        local consumedItems = {}
        local nourishingItems = {}
        local ashedItems = {}
        local attempts = 0
        while #nourishingItems < requestedRations do
            local rationItem = findRationItem(entity)
            if not rationItem then
                break
            end

            if removeConsumableItem(entity, rationItem) then
                attempts = attempts + 1
                consumedItems[#consumedItems + 1] = rationItem
                if foodTurnsToAsh(entity, opts, attempts, rationItem) then
                    ashedItems[#ashedItems + 1] = rationItem
                else
                    nourishingItems[#nourishingItems + 1] = rationItem
                end
            else
                break
            end
        end

        if #ashedItems > 0 then
            self.eventBus:emit(M.EVENTS.RATION_ASHED, {
                entity = entity,
                items = ashedItems,
                count = #ashedItems,
                result = "ration_ashed",
            })
        end

        if #nourishingItems > 0 then
            -- Reset starvation counter
            entity.starvationCount = 0

            -- Clear starving condition if they were starving
            if entity.conditions and entity.conditions.starving then
                entity.conditions.starving = false
            end

            local bondCharged = false
            if #nourishingItems >= 2 and canUseHaleAndHearty then
                bondCharged = chargeBond(entity, opts.chargeBondTargetId)
            end

            local pactBreak = nil
            local pactBroken = nil
            local pactBreaks = {}
            if gluttonyPact and #nourishingItems < 2 then
                pactBreak = breakGluttonyPact(self, entity, gluttonyPact)
                pactBroken = gluttonyPact
                pactBreaks[#pactBreaks + 1] = {
                    pact = gluttonyPact,
                    detail = pactBreak,
                }
            end
            if devourPact then
                local devourBreak = breakDevourLivingPact(self, entity, devourPact)
                if not pactBreak then
                    pactBreak = devourBreak
                    pactBroken = devourPact
                end
                pactBreaks[#pactBreaks + 1] = {
                    pact = devourPact,
                    detail = devourBreak,
                }
            end

            self.rationsConsumed[entity.id] = true

            self.eventBus:emit(M.EVENTS.RATION_CONSUMED, {
                entity = entity,
                item = nourishingItems[1],
                items = nourishingItems,
                count = #nourishingItems,
                wastedItems = ashedItems,
                wastedCount = #ashedItems,
                bondTargetId = bondCharged and opts.chargeBondTargetId or nil,
                requiredCount = gluttonyPact and 2 or nil,
                pactBroken = pactBroken,
                pactBreak = pactBreak,
                pactBreaks = #pactBreaks > 0 and pactBreaks or nil,
            })

            local firstProps = nourishingItems[1] and nourishingItems[1].properties or {}
            local foodName = firstProps.isCampMeal and "meal" or "ration"
            local rationLabel = #nourishingItems == 1 and ("a " .. foodName) or
                (#nourishingItems .. " " .. foodName .. "s")
            print("[CAMP] " .. entity.name .. " ate " .. rationLabel)
            self:resolveAnimalFeedsForOwner(entity)
            if pactBreak then
                return true, "ration_consumed_pact_broken"
            end
            return true, bondCharged and "ration_consumed_bond_charged" or "ration_consumed"
        elseif #consumedItems > 0 then
            return self:markAdventurerUnfed(entity, {
                result = "ration_ashed",
            })
        else
            return self:markAdventurerUnfed(entity)
        end
    end

    function controller:markAnimalCompanionAbandoned(owner, companion, key, opts)
        if not companion then
            return false, "No companion targeted"
        end

        opts = opts or {}
        companion.conditions = companion.conditions or {}
        companion.conditions.abandoned = true
        companion.abandoned = true
        companion.abandonedOwnerId = owner and owner.id or companion.abandonedOwnerId
        companion.abandonReason = opts.reason or "starving"

        local feedKey = companionFeedKey(owner, companion, key)
        self.animalFeedConsumed[feedKey] = true
        local removed = removeAnimalCompanion(owner, companion, key)

        self.eventBus:emit(M.EVENTS.ANIMAL_COMPANION_ABANDONED, {
            entity = companion,
            companion = companion,
            owner = owner,
            reason = companion.abandonReason,
            removed = removed,
            animalFeed = true,
        })

        print("[CAMP] " .. (companion.name or "Animal companion") .. " abandons the guild in search of food")
        return false, "animal_companion_abandoned"
    end

    function controller:markAnimalCompanionUnfed(owner, companion, key, opts)
        if not companion then
            return false, "No companion targeted"
        end

        opts = opts or {}
        companion.conditions = companion.conditions or {}
        companion.starvationCount = (companion.starvationCount or 0) + 1
        companion.conditions.weak = true
        companion.weak = true

        local severity = "weak"
        if companion.starvationCount >= 2 then
            companion.conditions.starving = true
            companion.starving = true
            severity = "starving"
        end

        local feedKey = companionFeedKey(owner, companion, key)
        self.animalFeedConsumed[feedKey] = true

        local abandonAt = tonumber(opts.abandonAtStarvationCount or companion.abandonAtStarvationCount) or 3
        if opts.abandon == true or opts.forceAbandon == true or companion.abandonNextMissedFeed == true or
           companion.starvationCount >= abandonAt then
            self.eventBus:emit(M.EVENTS.STARVATION_WARNING, {
                entity = companion,
                owner = owner,
                severity = "abandoned",
                animalFeed = true,
            })
            return self:markAnimalCompanionAbandoned(owner, companion, key, {
                reason = "starving",
            })
        end

        self.eventBus:emit(M.EVENTS.STARVATION_WARNING, {
            entity = companion,
            owner = owner,
            severity = severity,
            animalFeed = true,
        })

        print("[CAMP] " .. (companion.name or "Animal companion") .. " goes without feed (" .. severity .. ")")
        return false, "no_animal_feed"
    end

    function controller:feedAnimalCompanion(owner, companion, opts)
        if self.state ~= M.STATES.BREAK_BREAD then
            return false, "Not in break bread phase"
        end

        if not companion then
            return false, "No companion targeted"
        end

        opts = opts or {}
        local feedKey = companionFeedKey(owner, companion, opts.key)
        local conditions = companion.conditions or {}
        if companion.abandoned or conditions.abandoned then
            self.animalFeedConsumed[feedKey] = true
            return false, "animal_companion_abandoned"
        end

        if self.animalFeedConsumed[feedKey] then
            return true, "animal_feed_already_resolved"
        end

        if companion.suppliesOwnFood or companion.selfFeeding then
            companion.conditions = companion.conditions or {}
            companion.starvationCount = 0
            companion.conditions.weak = false
            companion.conditions.starving = false
            companion.weak = false
            companion.starving = false
            self.animalFeedConsumed[feedKey] = true
            return true, "animal_feed_self_supplied"
        end

        local feedItem = findAnimalFeedItem(owner, companion)
        if not feedItem then
            return self:markAnimalCompanionUnfed(owner, companion, opts.key, opts)
        end

        if not removeConsumableItem(owner, feedItem) then
            return self:markAnimalCompanionUnfed(owner, companion, opts.key, opts)
        end

        companion.conditions = companion.conditions or {}
        companion.starvationCount = 0
        companion.conditions.weak = false
        companion.conditions.starving = false
        companion.conditions.staggered = false
        companion.weak = false
        companion.starving = false

        self.animalFeedConsumed[feedKey] = true

        self.eventBus:emit(M.EVENTS.RATION_CONSUMED, {
            entity = companion,
            owner = owner,
            item = feedItem,
            animalFeed = true,
            count = 1,
        })

        print("[CAMP] " .. (companion.name or "Animal companion") .. " ate animal feed")
        return true, "animal_feed_consumed"
    end

    function controller:resolveAnimalFeedsForOwner(owner)
        for _, entry in ipairs(animalCompanionEntries(owner)) do
            local feedKey = companionFeedKey(owner, entry.companion, entry.key)
            if not self.animalFeedConsumed[feedKey] then
                self:feedAnimalCompanion(owner, entry.companion, { key = entry.key })
            end
        end
    end

    --- Skip eating for an adventurer (explicit choice to starve)
    function controller:skipRation(entity)
        if self.state ~= M.STATES.BREAK_BREAD then
            return false, "Not in break bread phase"
        end

        if self:sleepSuspendsFoodRequirement(entity) then
            return self:markAdventurerFoodRequirementSuspended(entity)
        end

        return self:markAdventurerUnfed(entity)
    end

    function controller:canAdvanceFromBreakBread()
        for _, pc in ipairs(self.guild) do
            if not self.rationsConsumed[pc.id] then
                return false
            end

            for _, entry in ipairs(animalCompanionEntries(pc)) do
                local feedKey = companionFeedKey(pc, entry.companion, entry.key)
                if not self.animalFeedConsumed[feedKey] then
                    return false
                end
            end
        end
        return true
    end

    ----------------------------------------------------------------------------
    -- STEP 3: WATCH
    ----------------------------------------------------------------------------

    local function isRandomEncounterResult(result)
        if not result then
            return false
        end

        local category = result.category or result.type or result.eventType
        return category == "random_encounter" or
               category == "random encounter" or
               (result.raw and result.raw.category == "random_encounter")
    end

    local function choosePatrolMeatgrinderResult(draws)
        for _, result in ipairs(draws or {}) do
            if not isRandomEncounterResult(result) then
                return result, false
            end
        end

        return draws and draws[1] or nil, (draws and #draws or 0) > 0
    end

    local pathSuitByName = {
        swords = constants.SUITS.SWORDS,
        pentacles = constants.SUITS.PENTACLES,
        cups = constants.SUITS.CUPS,
        wands = constants.SUITS.WANDS,
    }

    local function entityPathSuit(entity)
        if not entity then
            return nil
        end

        if entity.pathSuit or entity.path_suit then
            return entity.pathSuit or entity.path_suit
        end

        local path = entity.path or entity.pathName or entity.suit
        if type(path) == "string" then
            path = path:lower():gsub("^path of ", "")
            return pathSuitByName[path]
        end

        return nil
    end

    function controller:selectWatchGuard(guardCard)
        if not guardCard then
            return nil
        end

        local candidates = {}
        for _, pc in ipairs(self.guild or {}) do
            if entityPathSuit(pc) == guardCard.suit then
                candidates[#candidates + 1] = pc
            end
        end

        if #candidates == 0 then
            for _, pc in ipairs(self.guild or {}) do
                candidates[#candidates + 1] = pc
            end
        end

        if #candidates == 0 then
            return nil
        end

        if #candidates == 1 then
            return candidates[1]
        end

        return candidates[(guardCard.value or 1) % 2 == 1 and 1 or #candidates]
    end

    function controller:getWatchGuardCard(options)
        options = options or {}
        local playerDeck = options.playerDeck or self.playerDeck
        if playerDeck and playerDeck.peekDiscard then
            local card = playerDeck:peekDiscard()
            if card then
                return card
            end
        end

        return options.guardCard
    end

    function controller:resolveWatchGuardTest(guard, options)
        options = options or {}
        if not guard then
            return nil
        end

        local supplied = options.guardTestResult
        if supplied ~= nil then
            if type(supplied) == "table" then
                return supplied
            end
            return {
                success = supplied == true,
                result = supplied == true and "success" or "failure",
                supplied = true,
            }
        end

        local card = options.guardTestCard
        local playerDeck = options.playerDeck or self.playerDeck
        if not card and playerDeck and playerDeck.draw then
            card = playerDeck:draw()
        end

        if not card then
            return nil
        end

        local cups = guard.getAttribute and guard:getAttribute(constants.SUITS.CUPS) or guard.cups or 0
        local testResult = fateResolver.resolveTest(cups, constants.SUITS.CUPS, card, options.guardTestFavor)

        if playerDeck and playerDeck.discard and not options.guardTestCard then
            playerDeck:discard(card)
        end

        return testResult
    end

    function controller:resolveCampEncounterGuard(watchResult, options)
        options = options or {}
        if not watchResult.challengeTriggered then
            return nil
        end

        local guardCard = self:getWatchGuardCard(options)
        local guard = options.guard or self:selectWatchGuard(guardCard)
        local testResult = self:resolveWatchGuardTest(guard, options)
        local alarmRaised = testResult and testResult.success == true or false
        local surprised = testResult and not testResult.success or false

        local guardResult = {
            guard = guard,
            guardCard = guardCard,
            testResult = testResult,
            alarmRaised = alarmRaised,
            surprised = surprised,
            sleepingVulnerable = surprised,
            surpriseEquipmentInactive = surprised,
            armorInactive = surprised,
            weaponsInactive = surprised,
            requiresTest = guard ~= nil and testResult == nil,
            testSuit = "cups",
        }

        watchResult.guard = guard
        watchResult.guardCard = guardCard
        watchResult.guardTest = testResult
        watchResult.alarmRaised = alarmRaised
        watchResult.surprised = surprised
        watchResult.sleepingVulnerable = surprised
        watchResult.surpriseEquipmentInactive = surprised
        watchResult.armorInactive = surprised
        watchResult.weaponsInactive = surprised
        if surprised then
            watchResult.challengeConfig = {
                surprised = true,
                sleepingVulnerable = true,
                surpriseEquipmentInactive = true,
            }
        end
        watchResult.guardTestRequired = guardResult.requiresTest

        self.eventBus:emit("camp_watch_guard", guardResult)

        return guardResult
    end

    --- Resolve the watch (overnight encounter check)
    -- @param doubleDraw boolean: True if someone took Patrol action (auto-detected if nil)
    function controller:resolveWatch(doubleDraw, options)
        if type(doubleDraw) == "table" then
            options = doubleDraw
            doubleDraw = options.doubleDraw
        end
        options = options or {}

        if self.state ~= M.STATES.WATCH then
            return false, "Not in watch phase"
        end

        -- Auto-detect patrol if not specified
        if doubleDraw == nil then
            doubleDraw = self.patrolActive or false
        end

        local watchResult = {
            patrol = doubleDraw == true,
            draws = {},
            selected = nil,
            challengeTriggered = false,
        }

        -- Draw from meatgrinder
        if self.meatgrinder then
            local drawCount = doubleDraw and 2 or 1
            for _ = 1, drawCount do
                local result = self.meatgrinder:draw()
                if result then
                    print("[CAMP] Meatgrinder draw: " .. (result.description or "event"))
                    watchResult.draws[#watchResult.draws + 1] = result
                end
            end

            if doubleDraw then
                watchResult.selected, watchResult.challengeTriggered =
                    choosePatrolMeatgrinderResult(watchResult.draws)
            else
                watchResult.selected = watchResult.draws[1]
                watchResult.challengeTriggered = isRandomEncounterResult(watchResult.selected)
            end

            if watchResult.selected then
                self.eventBus:emit("meatgrinder_result", watchResult.selected)
            end
        end

        self:resolveCampEncounterGuard(watchResult, options)

        self.watchResolved = true
        self.lastWatchResult = watchResult
        print("[CAMP] Watch resolved" .. (doubleDraw and " (patrol active)" or ""))

        return true, watchResult
    end

    ----------------------------------------------------------------------------
    -- STEP 4: RECOVERY (S8.4)
    ----------------------------------------------------------------------------

    local function isStarvingEntity(entity)
        local conditions = entity and entity.conditions or {}
        return entity and (entity.starving or conditions.starving) == true
    end

    local function afflictionMaxStage(affliction)
        if affliction.maxStage then
            return affliction.maxStage
        end
        if affliction.stages and #affliction.stages > 0 then
            return #affliction.stages
        end
        return 4
    end

    local function afflictionCuredStages(affliction)
        affliction.curedStages = affliction.curedStages or {}
        return affliction.curedStages
    end

    local function afflictionHiddenStageCosts(affliction)
        return affliction.hiddenStageCosts or affliction.secretStageCosts or affliction.gmStageCosts or
            affliction.hiddenChargesRequired or affliction.secretChargesRequired
    end

    local function afflictionThresholdsHidden(affliction)
        return affliction.hiddenCureThresholds == true or affliction.hideCureThresholds == true or
            affliction.secretCureThresholds == true or afflictionHiddenStageCosts(affliction) ~= nil
    end

    local function afflictionStageRecovery(affliction, stage)
        local recovery = affliction.stageRecovery or affliction.recoveryByStage or affliction.stageRecoveryCosts
        if type(recovery) ~= "table" then
            return nil
        end
        local spec = recovery[stage] or recovery[tostring(stage)]
        if type(spec) == "table" then
            return spec
        end
        return nil
    end

    local function afflictionCostFrom(costs, fallback, stage)
        if type(costs) == "table" then
            local cost = costs[stage] or costs[tostring(stage)] or costs.default
            if type(cost) == "table" then
                cost = cost.charges or cost.chargeCost or cost.cost
            end
            return math.max(1, tonumber(cost or fallback) or 1)
        end
        return math.max(1, tonumber(costs or fallback) or 1)
    end

    local function afflictionRecoveryChargeCost(spec)
        if type(spec) ~= "table" then
            return nil
        end
        local cost = spec.charges
        if cost == nil then
            cost = spec.chargeCost or spec.cost
        end
        if cost == nil then
            return nil
        end
        return math.max(0, tonumber(cost) or 0)
    end

    local function afflictionStageCost(affliction, stage)
        local hiddenCosts = afflictionHiddenStageCosts(affliction)
        if hiddenCosts ~= nil then
            return afflictionCostFrom(hiddenCosts, affliction.chargesPerStage, stage)
        end

        local recoveryCost = afflictionRecoveryChargeCost(afflictionStageRecovery(affliction, stage))
        if recoveryCost ~= nil then
            return recoveryCost
        end

        local costs = affliction.stageCosts or affliction.chargeCosts or affliction.chargesRequired
        return afflictionCostFrom(costs, affliction.chargesPerStage, stage)
    end

    local function afflictionStageXPCost(affliction, stage)
        local spec = afflictionStageRecovery(affliction, stage)
        if type(spec) ~= "table" then
            return 0
        end
        return math.max(0, math.floor(tonumber(spec.xp or spec.experience or spec.xpCost) or 0))
    end

    local function afflictionStageCostMap(affliction)
        local costs = {}
        for stage = 1, afflictionMaxStage(affliction) do
            costs[stage] = afflictionStageCost(affliction, stage)
        end
        return costs
    end

    local function afflictionStageXPMap(affliction)
        local costs = {}
        for stage = 1, afflictionMaxStage(affliction) do
            local xp = afflictionStageXPCost(affliction, stage)
            if xp > 0 then
                costs[stage] = xp
            end
        end
        return costs
    end

    local function findAffliction(entity, afflictionName)
        if not entity or not entity.afflictions then
            return nil, nil
        end

        if afflictionName then
            return entity.afflictions[afflictionName], afflictionName
        end

        for name, affliction in pairs(entity.afflictions) do
            return affliction, name
        end

        return nil, nil
    end

    local function allAfflictionStagesCured(affliction)
        local curedStages = afflictionCuredStages(affliction)
        for stage = 1, afflictionMaxStage(affliction) do
            if not curedStages[stage] then
                return false
            end
        end
        return true
    end

    local function highestUncuredStage(affliction)
        local curedStages = afflictionCuredStages(affliction)
        for stage = afflictionMaxStage(affliction), 1, -1 do
            if not curedStages[stage] then
                return stage
            end
        end
        return nil
    end

    local function regressFromCuredCurrentStage(affliction)
        local curedStages = afflictionCuredStages(affliction)
        local stage = affliction.stage or 1
        while stage > 0 and curedStages[stage] do
            stage = stage - 1
        end
        affliction.stage = math.max(1, stage)
    end

    function controller:applyAfflictionCharges(entity, afflictionName, charges, source)
        local affliction, resolvedName = findAffliction(entity, afflictionName)
        if not affliction then
            return false, "No affliction to cure"
        end

        charges = math.max(1, tonumber(charges) or 1)
        affliction.cureCharges = (affliction.cureCharges or 0) + charges

        local curedStages = afflictionCuredStages(affliction)
        local thresholdsHidden = afflictionThresholdsHidden(affliction)
        local curedNow = {}
        local revealedStageCosts = {}
        while true do
            local stage = highestUncuredStage(affliction)
            if not stage then
                break
            end

            local cost = afflictionStageCost(affliction, stage)
            if afflictionStageXPCost(affliction, stage) > 0 then
                break
            end
            if affliction.cureCharges < cost then
                break
            end

            affliction.cureCharges = affliction.cureCharges - cost
            curedStages[stage] = true
            curedNow[#curedNow + 1] = stage
            if thresholdsHidden then
                affliction.knownStageCosts = affliction.knownStageCosts or {}
                affliction.knownStageCosts[stage] = cost
                revealedStageCosts[stage] = cost
            end
            affliction.curedThisCamp = true

            if (affliction.stage or 1) == stage then
                regressFromCuredCurrentStage(affliction)
            end
        end

        local fullyCured = allAfflictionStagesCured(affliction)
        local cureChargesRemaining = affliction.cureCharges or 0
        local knownStageCosts = thresholdsHidden and cloneValue(affliction.knownStageCosts or {}) or
            afflictionStageCostMap(affliction)
        if fullyCured then
            entity.afflictions[resolvedName] = nil
        end
        syncKnownAfflictionEffects(entity)

        self.eventBus:emit("affliction_charges_spent", {
            entity = entity,
            affliction = resolvedName,
            charges = charges,
            source = source,
            curedStages = curedNow,
            cureChargesRemaining = cureChargesRemaining,
            fullyCured = fullyCured,
            thresholdsHidden = thresholdsHidden,
            knownStageCosts = knownStageCosts,
            revealedStageCosts = revealedStageCosts,
        })

        return true, {
            result = fullyCured and "affliction_cured" or "affliction_charged",
            affliction = resolvedName,
            curedStages = curedNow,
            fullyCured = fullyCured,
            cureChargesRemaining = cureChargesRemaining,
            thresholdsHidden = thresholdsHidden,
            knownStageCosts = knownStageCosts,
            revealedStageCosts = revealedStageCosts,
        }
    end

    local function availableRecoveryXP(entity)
        if not entity then
            return 0, nil
        end
        if entity.xp ~= nil then
            return math.max(0, math.floor(tonumber(entity.xp) or 0)), "xp"
        end
        if entity.experience ~= nil then
            return math.max(0, math.floor(tonumber(entity.experience) or 0)), "experience"
        end
        return 0, nil
    end

    function controller:applyAfflictionXP(entity, afflictionName, xp, source)
        local affliction, resolvedName = findAffliction(entity, afflictionName)
        if not affliction then
            return false, "No affliction to cure"
        end

        local currentStage = tonumber(affliction.stage or 1) or 1
        local requiredXP = afflictionStageXPCost(affliction, currentStage)
        if requiredXP <= 0 then
            return false, "Affliction stage does not require XP"
        end

        local committedXP = math.max(0, math.floor(tonumber(xp or requiredXP) or 0))
        if committedXP < requiredXP then
            return false, "Not enough XP committed"
        end

        local availableXP, xpField = availableRecoveryXP(entity)
        if not xpField or availableXP < requiredXP then
            return false, "Not enough XP"
        end

        entity[xpField] = availableXP - requiredXP
        local curedStages = afflictionCuredStages(affliction)
        curedStages[currentStage] = true
        affliction.curedThisCamp = true

        local fullyCured = currentStage <= 1 or allAfflictionStagesCured(affliction)
        if fullyCured then
            entity.afflictions[resolvedName] = nil
        else
            regressFromCuredCurrentStage(affliction)
        end
        syncKnownAfflictionEffects(entity)

        local detail = {
            result = fullyCured and "affliction_cured" or "affliction_regressed",
            affliction = resolvedName,
            curedStages = { currentStage },
            fullyCured = fullyCured,
            xpSpent = requiredXP,
            source = source,
        }
        self.eventBus:emit("affliction_xp_spent", {
            entity = entity,
            affliction = resolvedName,
            xpSpent = requiredXP,
            source = source,
            curedStages = detail.curedStages,
            fullyCured = fullyCured,
        })

        return true, detail
    end

    function controller:getAfflictionRecoveryState(entity, afflictionName)
        local affliction, resolvedName = findAffliction(entity, afflictionName)
        if not affliction then
            return nil, "No affliction to cure"
        end

        local hidden = afflictionThresholdsHidden(affliction)
        local state = {
            affliction = resolvedName,
            name = affliction.name or resolvedName,
            stage = affliction.stage or 1,
            maxStage = afflictionMaxStage(affliction),
            cureCharges = affliction.cureCharges or 0,
            curedStages = cloneValue(afflictionCuredStages(affliction)),
            thresholdsHidden = hidden,
            knownStageCosts = hidden and cloneValue(affliction.knownStageCosts or {}) or afflictionStageCostMap(affliction),
            xpStageCosts = afflictionStageXPMap(affliction),
            stageRecovery = cloneValue(affliction.stageRecovery or {}),
        }
        if not hidden then
            state.stageCosts = afflictionStageCostMap(affliction)
        end
        return state
    end

    function controller:getRecoveryOptions(opts)
        opts = opts or {}

        local selectedEntity = opts.entity or opts.actor or opts.selectedEntity or opts.selectedActor
        local selectedKey = entityComfortKey(selectedEntity) or opts.entityId or opts.actorId or
            opts.selectedEntityId or opts.selectedActorId
        local selectedBondTargetId = opts.bondTargetId or opts.targetBondId or opts.selectedBondTargetId
        local selectedSpendType = opts.spendType or opts.recoverySpendType or opts.selectedSpendType
        local selectedAfflictionId = opts.affliction or opts.afflictionName or opts.targetAffliction
        local selectedItemId = opts.itemId or opts.healthfulItemId or opts.selectedItemId
        local selectedCompanionId = opts.companionId or opts.companion_id or opts.selectedCompanionId
        local selectedExtraBondTargetId = opts.extraBondTargetId or opts.secondBondTargetId or
            opts.additionalBondTargetId or opts.extraRecoveryBondTargetId
        local actors = {}
        local pendingActors = {}
        local selectedActorOption = nil
        local selectedBondOption = nil
        local selectedBenefitOption = nil
        local selectedAidOption = nil
        local selectedAfflictionOption = nil

        local function addReason(reasons, reason)
            if not reason then
                return
            end
            for _, existing in ipairs(reasons) do
                if existing == reason then
                    return
                end
            end
            reasons[#reasons + 1] = reason
        end

        local function actorCanRecoverResolve(entity)
            if not entity or type(entity.regainResolve) ~= "function" then
                return false
            end
            if type(entity.resolve) == "table" then
                local current = tonumber(entity.resolve.current or entity.resolve.value)
                local max = tonumber(entity.resolve.max or entity.resolve.maximum or
                    entity.maxResolve or entity.resolveMax or 4) or 4
                return current ~= nil and current < max
            end

            local current = tonumber(entity.resolve or entity.currentResolve or entity.resolveCurrent)
            local max = tonumber(entity.maxResolve or entity.resolveMax or 4) or 4
            return current ~= nil and current < max
        end

        local function sortedAfflictionNames(entity)
            local names = {}
            for name, affliction in pairs(entity and entity.afflictions or {}) do
                if affliction ~= nil and affliction ~= false then
                    names[#names + 1] = name
                end
            end
            table.sort(names, function(a, b)
                return tostring(a) < tostring(b)
            end)
            return names
        end

        local function carriedRecoveryItems(entity)
            local out = {}
            local inv = entity and entity.inventory
            if not inv or not inv.getAllItems then
                return out
            end
            for _, entry in ipairs(inv:getAllItems()) do
                local item = entry.item
                local props = item and item.properties or {}
                if props.afflictionCureCharges ~= nil then
                    out[#out + 1] = {
                        item = item,
                        location = entry.location,
                        charges = math.max(1, tonumber(props.afflictionCureCharges) or 1),
                        leeches = props.leeches == true,
                    }
                end
            end
            table.sort(out, function(a, b)
                return tostring(a.item and (a.item.name or a.item.id) or "") <
                    tostring(b.item and (b.item.name or b.item.id) or "")
            end)
            return out
        end

        local function addBenefit(option, benefit)
            option.benefitOptions[#option.benefitOptions + 1] = benefit
            if option.selected and selectedSpendType and benefit.spendType == selectedSpendType then
                if selectedAfflictionId and benefit.affliction ~= selectedAfflictionId then
                    return
                end
                if selectedCompanionId and benefit.companionId ~= selectedCompanionId then
                    return
                end
                selectedBenefitOption = benefit
            end
        end

        for _, entity in ipairs(opts.guild or opts.actors or self.guild or {}) do
            local actorOpts = opts
            if opts.byActor and entity and entity.id and opts.byActor[entity.id] then
                actorOpts = opts.byActor[entity.id]
            end

            local actorSelectedBondTargetId = actorOpts.bondTargetId or actorOpts.targetBondId or
                actorOpts.selectedBondTargetId or selectedBondTargetId
            local actorSelectedSpendType = actorOpts.spendType or actorOpts.recoverySpendType or
                actorOpts.selectedSpendType or selectedSpendType
            local actorSelectedAfflictionId = actorOpts.affliction or actorOpts.afflictionName or
                actorOpts.targetAffliction or selectedAfflictionId
            local actorSelectedItemId = actorOpts.itemId or actorOpts.healthfulItemId or
                actorOpts.selectedItemId or selectedItemId
            local actorSelectedCompanionId = actorOpts.companionId or actorOpts.companion_id or
                actorOpts.selectedCompanionId or selectedCompanionId
            local actorSelectedExtraBondTargetId = actorOpts.extraBondTargetId or actorOpts.secondBondTargetId or
                actorOpts.additionalBondTargetId or actorOpts.extraRecoveryBondTargetId or selectedExtraBondTargetId

            local conditions = entity and entity.conditions or {}
            local inRecoveryPhase = self.state == M.STATES.RECOVERY
            local starving = isStarvingEntity(entity)
            local stressed = conditions.stressed == true or (entity and entity.stressed == true)
            local restTaken = tookRestAndRecoverAction(self, entity)
            local completed = entity and entity.id and self.recoveryCompleted[entity.id] == true
            local availableXP = select(1, availableRecoveryXP(entity))
            local actorReasons = {}
            local bondOptions = {}
            local aidOptions = {}
            local afflictionOptions = {}
            local actionable = false
            local selected = selectedKey ~= nil and entityComfortKey(entity) == selectedKey

            if not inRecoveryPhase then
                addReason(actorReasons, "Not in recovery phase")
            end
            if starving then
                addReason(actorReasons, "Starving adventurers cannot recover")
            end
            if completed then
                addReason(actorReasons, "Recovery already completed")
            end
            if stressed and actorSelectedSpendType and actorSelectedSpendType ~= "clear_stress" then
                addReason(actorReasons, "Must clear stress first")
            end
            if actorSelectedAfflictionId and not restTaken then
                addReason(actorReasons, "Requires Rest and Recover action")
            end

            for _, afflictionId in ipairs(sortedAfflictionNames(entity)) do
                local affliction = entity.afflictions and entity.afflictions[afflictionId]
                local state = type(affliction) == "table" and self:getAfflictionRecoveryState(entity, afflictionId) or nil
                local stage = (state and state.stage) or 1
                local xpCost = state and state.xpStageCosts and state.xpStageCosts[stage] or 0
                local chargeCost = state and state.stageCosts and state.stageCosts[stage] or nil
                local option = {
                    id = afflictionId,
                    name = (state and state.name) or afflictionId,
                    stage = stage,
                    maxStage = (state and state.maxStage) or 1,
                    cureCharges = (state and state.cureCharges) or 0,
                    curedStages = state and cloneValue(state.curedStages) or {},
                    thresholdsHidden = state and state.thresholdsHidden == true or false,
                    knownStageCosts = state and cloneValue(state.knownStageCosts) or {},
                    xpStageCosts = state and cloneValue(state.xpStageCosts) or {},
                    currentStageChargeCost = chargeCost,
                    currentStageXPCost = xpCost,
                    restAndRecoverTaken = restTaken,
                    selected = actorSelectedAfflictionId == afflictionId,
                    actionDataPreview = {
                        spendType = "cure_affliction",
                        affliction = afflictionId,
                    },
                }
                if not restTaken then
                    option.disabled = true
                    option.unavailableReason = "Requires Rest and Recover action"
                elseif stressed then
                    option.disabled = true
                    option.unavailableReason = "Must clear stress first"
                elseif starving then
                    option.disabled = true
                    option.unavailableReason = "Starving adventurers cannot recover"
                elseif not inRecoveryPhase then
                    option.disabled = true
                    option.unavailableReason = "Not in recovery phase"
                end
                if option.selected and selected then
                    selectedAfflictionOption = option
                end
                afflictionOptions[#afflictionOptions + 1] = option
            end

            local bondIds = {}
            for targetId in pairs(entity and entity.bonds or {}) do
                bondIds[#bondIds + 1] = targetId
            end
            table.sort(bondIds, function(a, b)
                return tostring(a) < tostring(b)
            end)

            for _, targetId in ipairs(bondIds) do
                local bond = entity.bonds[targetId]
                local bondOption = {
                    id = targetId,
                    targetId = targetId,
                    name = bond.name or targetId,
                    charged = bond.charged == true,
                    bond = cloneValue(bond),
                    selected = actorSelectedBondTargetId == targetId,
                    benefitOptions = {},
                }
                if not bondOption.charged then
                    bondOption.disabled = true
                    bondOption.unavailableReason = "Bond is not charged"
                elseif not inRecoveryPhase then
                    bondOption.disabled = true
                    bondOption.unavailableReason = "Not in recovery phase"
                elseif starving then
                    bondOption.disabled = true
                    bondOption.unavailableReason = "Starving adventurers cannot recover"
                elseif completed then
                    bondOption.disabled = true
                    bondOption.unavailableReason = "Recovery already completed"
                end

                if bondOption.selected and selected then
                    selectedBondOption = bondOption
                end

                if stressed then
                    addBenefit(bondOption, {
                        id = "clear_stress",
                        spendType = "clear_stress",
                        label = "Clear Stress",
                        resultPreview = "stress_cleared",
                        selected = bondOption.selected and actorSelectedSpendType == "clear_stress",
                        actionDataPreview = {
                            bondTargetId = targetId,
                            spendType = "clear_stress",
                        },
                    })
                else
                    local woundResult = nextRecoveryWoundResult(entity)
                    if woundResult and woundResult ~= "fully_healed" then
                        local extraBondOptions = {}
                        local needsExtraBond = recoveryNeedsExtraBond(entity)
                        if needsExtraBond then
                            for _, otherId in ipairs(bondIds) do
                                local otherBond = entity.bonds[otherId]
                                if otherId ~= targetId and otherBond and otherBond.charged then
                                    extraBondOptions[#extraBondOptions + 1] = {
                                        targetId = otherId,
                                        name = otherBond.name or otherId,
                                        selected = actorSelectedExtraBondTargetId == otherId,
                                    }
                                end
                            end
                        end
                        addBenefit(bondOption, {
                            id = "heal_wound",
                            spendType = "heal_wound",
                            label = "Heal Wound",
                            resultPreview = woundResult,
                            requiresExtraBond = needsExtraBond,
                            extraBondOptions = extraBondOptions,
                            disabled = needsExtraBond and #extraBondOptions == 0 or nil,
                            unavailableReason = needsExtraBond and #extraBondOptions == 0 and
                                "Requires two charged Bonds" or nil,
                            selected = bondOption.selected and actorSelectedSpendType == "heal_wound",
                            actionDataPreview = {
                                bondTargetId = targetId,
                                spendType = "heal_wound",
                                extraBondTargetId = actorSelectedExtraBondTargetId,
                            },
                        })
                    end

                    if actorCanRecoverResolve(entity) then
                        addBenefit(bondOption, {
                            id = "regain_resolve",
                            spendType = "regain_resolve",
                            label = "Regain Resolve",
                            resultPreview = "resolve_regained",
                            selected = bondOption.selected and actorSelectedSpendType == "regain_resolve",
                            actionDataPreview = {
                                bondTargetId = targetId,
                                spendType = "regain_resolve",
                            },
                        })
                    end

                    if restTaken then
                        for _, afflictionOption in ipairs(afflictionOptions) do
                            addBenefit(bondOption, {
                                id = "cure_affliction:" .. afflictionOption.id,
                                spendType = "cure_affliction",
                                label = "Cure " .. tostring(afflictionOption.name),
                                affliction = afflictionOption.id,
                                resultPreview = "affliction_charged",
                                selected = bondOption.selected and
                                    actorSelectedSpendType == "cure_affliction" and
                                    actorSelectedAfflictionId == afflictionOption.id,
                                actionDataPreview = {
                                    bondTargetId = targetId,
                                    spendType = "cure_affliction",
                                    affliction = afflictionOption.id,
                                },
                            })
                        end
                    end

                    for _, companion in ipairs(entity and entity.animalCompanions or {}) do
                        local companionConditions = companion and companion.conditions or {}
                        if companionConditions.injured == true then
                            addBenefit(bondOption, {
                                id = "heal_companion:" .. tostring(companion.id or companion.name),
                                spendType = "heal_companion",
                                label = "Heal " .. tostring(companion.name or "Companion"),
                                companionId = companion.id,
                                companionName = companion.name,
                                resultPreview = "injured_healed",
                                selected = bondOption.selected and
                                    actorSelectedSpendType == "heal_companion" and
                                    (not actorSelectedCompanionId or actorSelectedCompanionId == companion.id),
                                actionDataPreview = {
                                    bondTargetId = targetId,
                                    spendType = "heal_companion",
                                    companionId = companion.id,
                                },
                            })
                        end
                    end
                end

                if #bondOption.benefitOptions == 0 and not bondOption.disabled then
                    bondOption.disabled = true
                    bondOption.unavailableReason = "No Recovery benefits available"
                end
                for _, benefit in ipairs(bondOption.benefitOptions) do
                    if bondOption.charged and not bondOption.disabled and not benefit.disabled then
                        actionable = true
                    end
                end
                bondOptions[#bondOptions + 1] = bondOption
            end

            for _, entry in ipairs(carriedRecoveryItems(entity)) do
                if not entry.leeches then
                    for _, afflictionOption in ipairs(afflictionOptions) do
                        local item = entry.item
                        local aid = {
                            id = "healthful_item:" .. tostring(item.id) .. ":" .. afflictionOption.id,
                            spendType = "healthful_item",
                            label = "Use " .. tostring(item.name or "Healthful Item"),
                            detail = tostring(afflictionOption.name or afflictionOption.id) ..
                                ", " .. tostring(entry.charges) .. " charges",
                            itemId = item.id,
                            itemName = item.name,
                            templateId = item.templateId,
                            location = entry.location,
                            charges = entry.charges,
                            affliction = afflictionOption.id,
                            resultPreview = "affliction_charged",
                            selected = actorSelectedSpendType == "healthful_item" and
                                actorSelectedItemId == item.id and
                                actorSelectedAfflictionId == afflictionOption.id,
                            actionDataPreview = {
                                spendType = "healthful_item",
                                itemId = item.id,
                                affliction = afflictionOption.id,
                            },
                        }
                        if not restTaken then
                            aid.disabled = true
                            aid.unavailableReason = "Requires Rest and Recover action"
                        elseif stressed then
                            aid.disabled = true
                            aid.unavailableReason = "Must clear stress first"
                        elseif starving then
                            aid.disabled = true
                            aid.unavailableReason = "Starving adventurers cannot recover"
                        elseif not inRecoveryPhase then
                            aid.disabled = true
                            aid.unavailableReason = "Not in recovery phase"
                        end
                        if aid.selected and selected then
                            selectedAidOption = aid
                        end
                        if not aid.disabled then
                            actionable = true
                        end
                        aidOptions[#aidOptions + 1] = aid
                    end
                end
            end

            for _, afflictionOption in ipairs(afflictionOptions) do
                local xpCost = math.max(0, tonumber(afflictionOption.currentStageXPCost) or 0)
                if xpCost > 0 then
                    local aid = {
                        id = "xp_affliction:" .. afflictionOption.id,
                        spendType = "xp_affliction",
                        label = "Spend " .. tostring(xpCost) .. " XP",
                        detail = "Cure " .. tostring(afflictionOption.name or afflictionOption.id),
                        affliction = afflictionOption.id,
                        xp = xpCost,
                        availableXP = availableXP,
                        resultPreview = "affliction_cured",
                        selected = actorSelectedSpendType == "xp_affliction" and
                            actorSelectedAfflictionId == afflictionOption.id,
                        actionDataPreview = {
                            spendType = "xp_affliction",
                            affliction = afflictionOption.id,
                            xp = xpCost,
                        },
                    }
                    if not restTaken then
                        aid.disabled = true
                        aid.unavailableReason = "Requires Rest and Recover action"
                    elseif stressed then
                        aid.disabled = true
                        aid.unavailableReason = "Must clear stress first"
                    elseif starving then
                        aid.disabled = true
                        aid.unavailableReason = "Starving adventurers cannot recover"
                    elseif availableXP < xpCost then
                        aid.disabled = true
                        aid.unavailableReason = "Not enough XP"
                    elseif not inRecoveryPhase then
                        aid.disabled = true
                        aid.unavailableReason = "Not in recovery phase"
                    end
                    if aid.selected and selected then
                        selectedAidOption = aid
                    end
                    if not aid.disabled then
                        actionable = true
                    end
                    aidOptions[#aidOptions + 1] = aid
                end
            end

            if not actionable then
                addReason(actorReasons, "No Recovery benefits available")
            end
            if entity and entity.id and not completed then
                pendingActors[#pendingActors + 1] = entity.id
            end

            local actorOption = {
                entity = entity,
                entityId = entity and entity.id or nil,
                entityName = entity and entity.name or nil,
                selected = selected,
                completed = completed,
                starving = starving,
                stressed = stressed,
                restAndRecoverTaken = restTaken,
                availableXP = availableXP,
                disabled = not inRecoveryPhase or starving or completed or not actionable,
                unavailableReasons = actorReasons,
                bondOptions = bondOptions,
                afflictionOptions = afflictionOptions,
                aidOptions = aidOptions,
                canRecoverResolve = actorCanRecoverResolve(entity),
                nextWoundResult = nextRecoveryWoundResult(entity),
                maledictionExtraBondRecoveryCost = recoveryNeedsExtraBond(entity),
            }
            if selected then
                selectedActorOption = actorOption
            end
            actors[#actors + 1] = actorOption
        end

        return {
            result = "recovery_options_ready",
            state = self.state,
            inRecoveryPhase = self.state == M.STATES.RECOVERY,
            canAdvanceNow = self.state == M.STATES.RECOVERY,
            pendingActors = pendingActors,
            actors = actors,
            selectedActor = selectedActorOption,
            selectedBond = selectedBondOption,
            selectedBenefit = selectedBenefitOption,
            selectedAid = selectedAidOption,
            selectedAffliction = selectedAfflictionOption,
            rules = {
                loreBidsRefillAtRecoveryStart = true,
                stressedMustClearFirst = true,
                starvingSkipsRecovery = true,
                afflictionRecoveryRequiresRestAndRecover = true,
                healthfulItemsCanBurnAfflictionCharges = true,
                leechesUseCampAction = true,
                maledictionPageCanRequireSecondBond = true,
                staggeredClearsAtRecoveryEnd = true,
            },
        }
    end

    function controller:advanceAffliction(entity, afflictionName, affliction)
        local curedStages = afflictionCuredStages(affliction)
        local currentStage = affliction.stage or 1

        if allAfflictionStagesCured(affliction) then
            entity.afflictions[afflictionName] = nil
            return "affliction_cured"
        end

        if curedStages[currentStage] then
            regressFromCuredCurrentStage(affliction)
            return "affliction_regressed"
        end

        local nextStage = math.min(currentStage + 1, afflictionMaxStage(affliction))
        if curedStages[nextStage] then
            return "affliction_held"
        end

        affliction.stage = nextStage
        print("[CAMP] " .. entity.name .. "'s " .. afflictionName ..
              " advanced to stage " .. affliction.stage)

        if affliction.stage >= afflictionMaxStage(affliction) and affliction.onClimax then
            affliction.onClimax(entity)
        end

        return "affliction_advanced"
    end

    --- Begin recovery for an adventurer
    -- Refills lore bids at the start of recovery.
    function controller:beginRecovery(entity)
        if self.state ~= M.STATES.RECOVERY then
            return false, "Not in recovery phase"
        end

        if isStarvingEntity(entity) then
            return false, "Starving adventurers skip recovery"
        end

        -- Refill lore bids unless starvation skips Recovery.
        entity.loreBids = 4

        return true
    end

    function controller:finalizeRecoveryForEntity(entity)
        if isStarvingEntity(entity) then
            return false, "Starving adventurers skip recovery"
        end

        if entity.conditions and not entity.conditions.stressed and entity.conditions.staggered then
            entity.conditions.staggered = false
            breakPactsForRecoveryResult(self, entity, "staggered_healed")
            print("[CAMP] " .. entity.name .. " clears Staggered")
        end

        return true
    end

    function controller:finalizeRecovery()
        for _, pc in ipairs(self.guild) do
            self:finalizeRecoveryForEntity(pc)
        end
    end

    --- Spend a bond for recovery
    -- @param entity table: The adventurer
    -- @param bondTargetId string: ID of the bond partner
    -- @param spendType string: "heal_wound", "regain_resolve", "clear_stress", or "cure_affliction"
    function controller:spendBondForRecovery(entity, bondTargetId, spendType, opts)
        opts = opts or {}
        if type(opts) == "string" then
            opts = { affliction = opts }
        end

        if self.state ~= M.STATES.RECOVERY then
            return false, "Not in recovery phase"
        end

        if isStarvingEntity(entity) then
            return false, "Starving adventurers cannot recover"
        end

        -- Check if entity has the bond and it's charged
        if not entity.bonds or not entity.bonds[bondTargetId] then
            return false, "No bond with that entity"
        end

        if not entity.bonds[bondTargetId].charged then
            return false, "Bond is not charged"
        end

        -- STRESS GATE: If stressed, MUST clear stress first
        if entity.conditions and entity.conditions.stressed then
            if spendType ~= "clear_stress" then
                return false, "Must clear stress first"
            end
        end

        local companionRecoveryTarget = nil
        if spendType == "heal_companion" or spendType == "heal_animal_companion" then
            companionRecoveryTarget = opts.companion or opts.target or
                findAnimalCompanion(entity, opts.companionId or opts.companion_id)
            if not companionRecoveryTarget then
                return false, "Choose animal companion"
            end
            if not animalCompanions.isAnimalCompanion(companionRecoveryTarget) then
                return false, "Target is not an animal companion"
            end
        end

        local extraBondTargetId = nil
        if spendType == "heal_wound" and recoveryNeedsExtraBond(entity) then
            local err = nil
            extraBondTargetId, err = selectExtraRecoveryBond(entity, bondTargetId, opts)
            if not extraBondTargetId then
                return false, err
            end
        end

        -- Spend the bond
        entity.bonds[bondTargetId].charged = false
        if extraBondTargetId then
            entity.bonds[extraBondTargetId].charged = false
        end

        -- Apply benefit
        local result = "unknown"
        local pactBreaks = {}
        if spendType == "clear_stress" then
            if entity.conditions then
                entity.conditions.stressed = false
            end
            result = "stress_cleared"
            pactBreaks = breakPactsForRecoveryResult(self, entity, result)
        elseif spendType == "heal_wound" then
            -- Use entity's healWound method (respects injury gate)
            if entity.healWound then
                local healResult, err = entity:healWound()
                if healResult then
                    result = healResult
                    pactBreaks = breakPactsForRecoveryResult(self, entity, result)
                else
                    -- Refund the bond if healing failed
                    entity.bonds[bondTargetId].charged = true
                    if extraBondTargetId then
                        entity.bonds[extraBondTargetId].charged = true
                    end
                    return false, err or "cannot_heal"
                end
            end
        elseif spendType == "heal_companion" or spendType == "heal_animal_companion" then
            local healResult, err = animalCompanions.healWound(companionRecoveryTarget)
            if healResult then
                result = healResult
            else
                entity.bonds[bondTargetId].charged = true
                return false, err or "cannot_heal_companion"
            end
        elseif spendType == "regain_resolve" then
            if entity.regainResolve then
                entity:regainResolve(1)
                result = "resolve_regained"
            end
        elseif spendType == "cure_affliction" or spendType == "affliction" then
            if not tookRestAndRecoverAction(self, entity) then
                entity.bonds[bondTargetId].charged = true
                if extraBondTargetId then
                    entity.bonds[extraBondTargetId].charged = true
                end
                return false, "Requires Rest and Recover action"
            end
            local ok, cureResult = self:applyAfflictionCharges(
                entity,
                opts.affliction or opts.afflictionName or opts.targetAffliction,
                opts.charges or 1,
                "bond"
            )
            if ok then
                result = cureResult.result
            else
                entity.bonds[bondTargetId].charged = true
                return false, cureResult
            end
        end

        self.eventBus:emit(M.EVENTS.BOND_SPENT, {
            entity = entity,
            bondTargetId = bondTargetId,
            extraBondTargetId = extraBondTargetId,
            bondCost = extraBondTargetId and 2 or 1,
            spendType = spendType,
            result = result,
            companion = companionRecoveryTarget,
            affliction = opts.affliction or opts.afflictionName or opts.targetAffliction,
            maledictionExtraBondRecoveryCost = extraBondTargetId ~= nil,
            pactBreaks = pactBreaks,
        })

        print("[CAMP] " .. entity.name .. " spent bond with " .. bondTargetId .. " for: " .. result)

        return true, result
    end

    function controller:spendXPForAfflictionRecovery(entity, afflictionName, opts)
        opts = opts or {}

        if self.state ~= M.STATES.RECOVERY then
            return false, "Not in recovery phase"
        end

        if isStarvingEntity(entity) then
            return false, "Starving adventurers cannot recover"
        end

        if entity.conditions and entity.conditions.stressed then
            return false, "Must clear stress first"
        end

        if not tookRestAndRecoverAction(self, entity) then
            return false, "Requires Rest and Recover action"
        end

        local ok, detail = self:applyAfflictionXP(
            entity,
            afflictionName or opts.affliction or opts.afflictionName or opts.targetAffliction,
            opts.xp or opts.experience,
            opts.source or "xp"
        )
        if not ok then
            return false, detail
        end

        return true, detail.result, detail
    end

    function controller:spendHealthfulItemForRecovery(entity, itemId, opts)
        opts = opts or {}

        if self.state ~= M.STATES.RECOVERY then
            return false, "Not in recovery phase"
        end

        if isStarvingEntity(entity) then
            return false, "Starving adventurers cannot recover"
        end

        if entity.conditions and entity.conditions.stressed then
            return false, "Must clear stress first"
        end

        if not tookRestAndRecoverAction(self, entity) then
            return false, "Requires Rest and Recover action"
        end

        local inv = entity and entity.inventory
        if not inv or not inv.findItem or not inv.removeItemQuantity then
            return false, "No inventory for healthful item"
        end

        local item = nil
        if itemId then
            item = inv:findItem(itemId)
        elseif inv.findItemByPredicate then
            item = inv:findItemByPredicate(function(candidate)
                return candidate.properties and candidate.properties.afflictionCureCharges
            end)
        end

        if not item then
            return false, "Healthful item not found"
        end

        local props = item.properties or {}
        if not props.afflictionCureCharges then
            return false, "Item is not healthful for afflictions"
        end

        local charges = math.max(1, tonumber(opts.charges or props.afflictionCureCharges) or 1)
        local ok, cureResult = self:applyAfflictionCharges(
            entity,
            opts.affliction or opts.afflictionName or opts.targetAffliction,
            charges,
            opts.source or item.templateId or item.id or "healthful_item"
        )
        if not ok then
            return false, cureResult
        end

        inv:removeItemQuantity(item.id, 1)

        local result = cureResult.result
        local detail = {
            entity = entity,
            item = item,
            itemId = item.id,
            itemName = item.name,
            affliction = cureResult.affliction,
            charges = charges,
            curedStages = cureResult.curedStages,
            fullyCured = cureResult.fullyCured,
            result = result,
        }
        self.eventBus:emit("healthful_item_spent", detail)

        return true, result, detail
    end

    --- Mark recovery complete for an entity
    function controller:completeRecovery(entity)
        self:finalizeRecoveryForEntity(entity)
        self.recoveryCompleted[entity.id] = true
    end

    ----------------------------------------------------------------------------
    -- STEP 5: TEARDOWN / END CAMP (S9.4)
    ----------------------------------------------------------------------------

    function controller:endCamp(opts)
        opts = opts or {}
        -- Process end-of-camp effects for all guild members
        for _, pc in ipairs(self.guild) do
            self:processEndOfCampEffects(pc, opts)
        end

        self.state = M.STATES.INACTIVE

        -- Emit camp end event
        self.eventBus:emit(M.EVENTS.CAMP_END, {
            guild = self.guild,
        })

        -- S9.4: Emit phase change to transition back to crawl
        self.eventBus:emit("phase_changed", {
            oldPhase = "camp",
            newPhase = "crawl",
        })

        print("[CAMP] Camp phase ended - returning to crawl")
    end

    function controller:getCampComfortBreakdown(entity)
        local benefits = {
            shelter = self.hasShelter and true or false,
            bedroll = self.hasBedrolls and true or false,
            tent = self.hasTent and true or false,
            fire = self.hasFire and true or false,
        }

        if self.bedrollOccupants then
            benefits.bedroll = campListIncludesEntity(self.bedrollOccupants, entity)
        end
        if self.tentOccupants then
            benefits.tent = campListIncludesEntity(self.tentOccupants, entity)
        end

        local fireBlockedByForegoWood = false
        if benefits.fire and self.fireViolatesForegoWood and
           campActions.findUnbrokenActivePact(entity, "forego_wood") then
            benefits.fire = false
            fireBlockedByForegoWood = true
        end

        local comfortCount = 0
        if benefits.bedroll then comfortCount = comfortCount + 1 end
        if benefits.tent then comfortCount = comfortCount + 1 end
        if benefits.fire then comfortCount = comfortCount + 1 end

        local missingComforts = {}
        if not benefits.bedroll then missingComforts[#missingComforts + 1] = "bedroll" end
        if not benefits.tent then missingComforts[#missingComforts + 1] = "tent" end
        if not benefits.fire then missingComforts[#missingComforts + 1] = "fire" end

        return {
            entity = entity,
            entityId = entity and entity.id or nil,
            entityName = entity and entity.name or nil,
            benefits = benefits,
            comfortCount = comfortCount,
            comfortable = benefits.shelter or comfortCount >= 2,
            missingComforts = missingComforts,
            fireBlockedByForegoWood = fireBlockedByForegoWood,
        }
    end

    function controller:hasAdequateCampComfort(entity)
        return self:getCampComfortBreakdown(entity).comfortable
    end

    function controller:getEndCampComfortOptions(opts)
        opts = opts or {}
        local selectedEntity = opts.entity or opts.actor or opts.selectedEntity or opts.selectedActor
        local selectedKey = entityComfortKey(selectedEntity) or opts.entityId or opts.actorId or
            opts.selectedEntityId or opts.selectedActorId
        local actors = {}

        for _, entity in ipairs(opts.guild or opts.actors or self.guild or {}) do
            local breakdown = self:getCampComfortBreakdown(entity)
            local starving = isStarvingEntity(entity)
            local unavailableReasons = {}

            if starving then
                unavailableReasons[#unavailableReasons + 1] = "starving_skips_comfort_check"
            elseif not breakdown.comfortable then
                unavailableReasons[#unavailableReasons + 1] = "needs_shelter_or_two_comforts"
            end
            if breakdown.fireBlockedByForegoWood then
                unavailableReasons[#unavailableReasons + 1] = "fire_violates_forego_wood"
            end

            breakdown.selected = selectedKey ~= nil and entityComfortKey(entity) == selectedKey
            breakdown.starving = starving
            breakdown.skipsComfortCheck = starving
            breakdown.wouldWakeStressed = not starving and not breakdown.comfortable
            breakdown.unavailableReasons = unavailableReasons
            actors[#actors + 1] = breakdown
        end

        return {
            result = "end_camp_comfort_options_ready",
            rules = {
                shelterSatisfiesComfort = true,
                comfortElementsRequiredWithoutShelter = 2,
                comfortElements = { "bedroll", "tent", "fire" },
                starvingSkipsComfortCheck = true,
                tentCapacityPerTent = 2,
                bedrollCapacityPerBedroll = 1,
            },
            resources = {
                hasShelter = self.hasShelter and true or false,
                hasBedrolls = self.hasBedrolls and true or false,
                bedrollCount = self.bedrollCount or 0,
                bedrollCapacity = self.bedrollCapacity or 0,
                bedrollOccupants = cloneValue(self.bedrollOccupants),
                hasTent = self.hasTent and true or false,
                tentCount = self.tentCount or 0,
                tentCapacity = self.tentCapacity or 0,
                tentOccupants = cloneValue(self.tentOccupants),
                hasFire = self.hasFire and true or false,
                fireViolatesForegoWood = self.fireViolatesForegoWood and true or false,
            },
            actors = actors,
        }
    end

    function controller:clearCampCompleteConditions(entity)
        local cleared = {}
        local durations = entity and entity.conditionDurations
        if not durations then
            return cleared
        end

        entity.conditions = entity.conditions or {}
        for condition, duration in pairs(durations) do
            if duration and duration["until"] == "next_camp_complete" then
                entity.conditions[condition] = false
                if entity[condition] == true then
                    entity[condition] = false
                end
                durations[condition] = nil
                cleared[#cleared + 1] = condition
            end
        end

        if next(durations) == nil then
            entity.conditionDurations = nil
        end

        return cleared
    end

    --- Process end-of-camp effects for a single entity (S9.4)
    function controller:processEndOfCampEffects(entity, opts)
        opts = opts or {}
        if not entity.conditions then
            entity.conditions = {}
        end

        -- 1. Advance afflictions (if entity has any)
        if entity.afflictions then
            for afflictionName, affliction in pairs(entity.afflictions) do
                -- Only advance if not cured this camp
                if not affliction.curedThisCamp then
                    self:advanceAffliction(entity, afflictionName, affliction)
                else
                    -- Reset cured flag for next camp
                    affliction.curedThisCamp = false
                end
            end
        end
        syncKnownAfflictionEffects(entity)

        -- 2. Check camp comfort: shelter, or at least two of bedroll/tent/fire.
        if isStarvingEntity(entity) then
            print("[CAMP] " .. entity.name .. " skips end-of-camp comfort checks (starving)")
        elseif not self:hasAdequateCampComfort(entity) then
            entity.conditions.stressed = true
            print("[CAMP] " .. entity.name .. " wakes Stressed (poor camp comfort)")
        end

        if not isStarvingEntity(entity) and badDreamsWakeStressed(entity, opts) then
            entity.conditions.stressed = true
            self.eventBus:emit(M.EVENTS.NIGHTMARE, {
                entity = entity,
                curseId = entity.maledictionCurseId or "bad_dreams",
                result = "stressed",
            })
            print("[CAMP] " .. entity.name .. " wakes Stressed (bad dreams)")
        end

        local theft = verminStealFromPack(entity, opts)
        if theft then
            self.eventBus:emit(M.EVENTS.VERMIN_THEFT, theft)
            print("[CAMP] " .. entity.name .. " loses " .. (theft.stolenItem.name or "an item") ..
                " to enamored vermin")
        end

        for _, condition in ipairs(self:clearCampCompleteConditions(entity)) do
            self.eventBus:emit(M.EVENTS.CONDITION_EXPIRED, {
                entity = entity,
                condition = condition,
                timing = "next_camp_complete",
            })
        end

        -- 3. Animal companions also need to be checked
        if entity.animalCompanions then
            for _, companion in ipairs(entity.animalCompanions) do
                self:processEndOfCampEffects(companion, opts)
            end
        end
    end

    ----------------------------------------------------------------------------
    -- UTILITY
    ----------------------------------------------------------------------------

    --- Get list of adventurers who haven't completed current step
    function controller:getPendingAdventurers()
        local pending = {}

        for _, pc in ipairs(self.guild) do
            local isPending = false

            if self.state == M.STATES.ACTIONS then
                isPending = not self.actionsCompleted[pc.id]
            elseif self.state == M.STATES.BREAK_BREAD then
                isPending = not self.rationsConsumed[pc.id]
            elseif self.state == M.STATES.RECOVERY then
                isPending = not self.recoveryCompleted[pc.id]
            end

            if isPending then
                pending[#pending + 1] = pc
            end
        end

        return pending
    end

    return controller
end

return M
