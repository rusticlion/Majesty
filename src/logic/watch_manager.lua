-- watch_manager.lua
-- Watch Manager & Movement Logic for Majesty
-- Ticket T2_2: Time tracking via Watches, triggers Meatgrinder
--
-- Design: Uses events for loose coupling. WatchManager fires events,
-- other systems (Light, Inventory) subscribe and respond.

local events = require('logic.events')
local entity_factory = require('entities.factory')
local meatgrinder_engine = require('logic.meatgrinder')

local M = {}

--------------------------------------------------------------------------------
-- MEATGRINDER RESULT CATEGORIES
-- Based on Major Arcana value (I-XXI)
--------------------------------------------------------------------------------
M.MEATGRINDER = {
    TORCHES_GUTTER   = "torches_gutter",    -- I-V (1-5)
    CURIOSITY        = "curiosity",          -- VI-X (6-10)
    TRAVEL_EVENT     = "travel_event",       -- XI-XV (11-15)
    RANDOM_ENCOUNTER = "random_encounter",   -- XVI-XX (16-20)
    QUEST_RUMOR      = "quest_rumor",        -- XXI (21)
}

--- Categorize a Major Arcana draw for Meatgrinder
-- @param cardValue number: The card's value (1-21)
-- @return string: One of MEATGRINDER categories
local function categorizeMeatgrinderDraw(cardValue)
    if cardValue >= 1 and cardValue <= 5 then
        return M.MEATGRINDER.TORCHES_GUTTER
    elseif cardValue >= 6 and cardValue <= 10 then
        return M.MEATGRINDER.CURIOSITY
    elseif cardValue >= 11 and cardValue <= 15 then
        return M.MEATGRINDER.TRAVEL_EVENT
    elseif cardValue >= 16 and cardValue <= 20 then
        return M.MEATGRINDER.RANDOM_ENCOUNTER
    elseif cardValue == 21 then
        return M.MEATGRINDER.QUEST_RUMOR
    end
    return nil
end

local function isLoudNoiseEncounterValue(cardValue)
    return cardValue >= 15 and cardValue <= 20
end

local function copyTable(source)
    local copy = {}
    for key, value in pairs(source or {}) do
        copy[key] = value
    end
    return copy
end

local function getCurrentRoomForMeatgrinder(manager)
    if type(manager.currentRoom) == "table" then
        return manager.currentRoom
    end

    if manager.currentRoom and manager.dungeon and manager.dungeon.getRoom then
        local room = manager.dungeon:getRoom(manager.currentRoom)
        if room then
            return room
        end
    end

    if manager.currentRoom then
        return { id = manager.currentRoom }
    end

    return nil
end

local function resolveAuthoredMeatgrinder(manager, card)
    local grinder = manager.meatgrinder
    if not grinder or not grinder.resolveEvent then
        return nil
    end

    local context = copyTable(manager.meatgrinderContext)
    context.watchManager = manager
    context.guild = manager.guild
    context.dungeon = manager.dungeon
    context.emitEvents = false

    return grinder:resolveEvent(card, getCurrentRoomForMeatgrinder(manager), context)
end

local function createForcedEncounterResult(encounter)
    encounter = encounter or {}
    local value = encounter.value or 16
    local filter = encounter.filter

    return {
        card = encounter.card or {
            name = encounter.name or "Forced Encounter",
            value = value,
            forced = true,
        },
        category = M.MEATGRINDER.RANDOM_ENCOUNTER,
        value = value,
        forced = true,
        source = encounter.source or "forced",
        filter = filter,
        description = encounter.description or
            (filter == "animals" and "Every animal in the area converges on the guild." or
                "The next watch brings an unavoidable encounter."),
        spawns = encounter.spawns or {},
        effects = encounter.effects or {
            { type = "encounter_start", filter = filter },
        },
        actorId = encounter.actorId,
        actorName = encounter.actorName,
        branch = encounter.branch,
        rank = encounter.rank,
        entryTitle = encounter.entryTitle,
        raw = encounter,
    }
end

local function firstText(...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if type(value) == "string" and value ~= "" then
            return value
        end
    end
    return nil
end

local function appendText(parts, text)
    if text and text ~= "" then
        parts[#parts + 1] = text
    end
end

local function clearAlchemicalSizeChange(member)
    if not member or not member.changeSize or member.changeSize.source ~= "alchemy" then
        return
    end

    if member.conditions then
        member.conditions.sizeChanged = false
        member.conditions.sizeGrown = false
        member.conditions.sizeShrunk = false
        member.conditions.titan_growth = false
    end
    member.changeSize.active = false
    member.changeSize.ended = true
    member.changeSize.endReason = "watch_expired"
    member.changeSize = nil
    member.sizeMultiplier = 1
    member.heightMultiplier = 1
    member.sizeChanged = false
end

local function clearFaceRatIllusion(member)
    if not member then
        return
    end

    if member.conditions then
        member.conditions.face_rat_illusion = false
        member.conditions.illusion_duplicate_pending = false
        member.conditions.illusion_duplicate_active = false
        member.conditions.face_rat_duplicate = false
        member.conditions.visual_illusion = false
    end
    if member.faceRatIllusion then
        member.faceRatIllusion.active = false
        member.faceRatIllusion.ended = true
        member.faceRatIllusion.endReason = "watch_expired"
    end
    member.faceRatIllusion = nil
    member.faceRatVisualIllusion = nil
    member.faceRatIllusionPending = nil
    member.apparentDuplicateOf = nil
    member.apparentDuplicateOfId = nil
    member.apparentDuplicateName = nil
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

local function clearJinnPotionShroud(member)
    if not member then
        return
    end
    local shroud = member.shroud
    if not (shroud and shroud.source == "jinn_potion") then
        return
    end

    local previous = (member.jinnShroud and member.jinnShroud.previous) or shroud.previous or {}
    restoreContainerField(member, "canSeeShrouded", previous.fields and previous.fields.canSeeShrouded)
    restoreContainerField(member, "canSeeInvisible", previous.fields and previous.fields.canSeeInvisible)
    restoreContainerField(member, "shroudedBy", previous.fields and previous.fields.shroudedBy)

    member.conditions = member.conditions or {}
    restoreContainerField(member.conditions, "shrouded", previous.conditions and previous.conditions.shrouded)
    restoreContainerField(member.conditions, "invisible", previous.conditions and previous.conditions.invisible)
    restoreContainerField(member.conditions, "see_shrouded", previous.conditions and previous.conditions.see_shrouded)
    restoreContainerField(member.conditions, "jinn_shroud", previous.conditions and previous.conditions.jinn_shroud)

    shroud.active = false
    shroud.ended = true
    shroud.endReason = "watch_expired"
    if member.jinnShroud then
        member.jinnShroud.active = false
        member.jinnShroud.ended = true
        member.jinnShroud.endReason = "watch_expired"
    end
    member.shroud = nil
    member.jinnShroud = nil
end

local function clearJinnBombMaterialization(member)
    if not member then
        return
    end
    local materialized = member.materializedByJinnBomb
    if not materialized then
        return
    end

    local previous = materialized.previous or {}
    restoreContainerField(member, "intangible", previous.fields and previous.fields.intangible)
    restoreContainerField(member, "incorporeal", previous.fields and previous.fields.incorporeal)
    restoreContainerField(member, "ethereal", previous.fields and previous.fields.ethereal)
    restoreContainerField(member, "invisible", previous.fields and previous.fields.invisible)
    restoreContainerField(member, "visible", previous.fields and previous.fields.visible)
    restoreContainerField(member, "tangible", previous.fields and previous.fields.tangible)

    member.conditions = member.conditions or {}
    restoreContainerField(member.conditions, "intangible", previous.conditions and previous.conditions.intangible)
    restoreContainerField(member.conditions, "incorporeal", previous.conditions and previous.conditions.incorporeal)
    restoreContainerField(member.conditions, "ethereal", previous.conditions and previous.conditions.ethereal)
    restoreContainerField(member.conditions, "invisible", previous.conditions and previous.conditions.invisible)
    restoreContainerField(member.conditions, "visible", previous.conditions and previous.conditions.visible)
    restoreContainerField(member.conditions, "tangible", previous.conditions and previous.conditions.tangible)
    restoreContainerField(member.conditions, "jinn_materialized",
        previous.conditions and previous.conditions.jinn_materialized)

    local props = member.properties
    if props then
        restoreContainerField(props, "intangible", previous.properties and previous.properties.intangible)
        restoreContainerField(props, "incorporeal", previous.properties and previous.properties.incorporeal)
        restoreContainerField(props, "ethereal", previous.properties and previous.properties.ethereal)
        restoreContainerField(props, "invisible", previous.properties and previous.properties.invisible)
        restoreContainerField(props, "visible", previous.properties and previous.properties.visible)
        restoreContainerField(props, "tangible", previous.properties and previous.properties.tangible)
    end

    materialized.active = false
    materialized.ended = true
    materialized.endReason = "watch_expired"
    member.materializedByJinnBomb = nil
end

local function clearVampireWeaknesses(member)
    if not member then
        return
    end

    if member.conditions then
        member.conditions.vampire_weaknesses = false
        member.conditions.sunlight_stuns = false
        member.conditions.wholesome_herbs_stun = false
        member.conditions.silver_stuns = false
        member.conditions.running_water_stuns = false
    end
    if member.vampireWeaknesses then
        member.vampireWeaknesses.active = false
        member.vampireWeaknesses.ended = true
        member.vampireWeaknesses.endReason = "watch_expired"
    end
    member.vampireWeaknesses = nil
end

local function clearAlchemicalMistForm(member)
    if not member then
        return
    end

    if member.conditions then
        member.conditions.mist_form = false
        member.conditions.vampire_mist = false
        member.conditions.hazard_resistant = false
        member.conditions.can_pass_cracks = false
    end
    if member.mistForm then
        member.mistForm.active = false
        member.mistForm.ended = true
        member.mistForm.endReason = "watch_expired"
    end
    member.mistForm = nil
    member.canPassCracks = false
end

local function clearAlchemicalInspiration(member, kind)
    if not member then
        return
    end

    if kind == "romantic" then
        if member.romanticInspiration then
            member.romanticInspiration.active = false
            member.romanticInspiration.ended = true
            member.romanticInspiration.endReason = "watch_expired"
        end
        member.romanticInspiration = nil
        member.romanticInspirationTarget = nil
    elseif kind == "distaste" then
        if member.distasteInspiration then
            member.distasteInspiration.active = false
            member.distasteInspiration.ended = true
            member.distasteInspiration.endReason = "watch_expired"
        end
        member.distasteInspiration = nil
        member.distasteInspirationTarget = nil
        if member.disposition == "distaste" then
            member.disposition = nil
        end
    elseif kind == "anger" then
        if member.ogrePheromone then
            member.ogrePheromone.active = false
            member.ogrePheromone.ended = true
            member.ogrePheromone.endReason = "watch_expired"
        end
        member.ogrePheromone = nil
        member.recklessAttackTarget = nil
        if member.disposition == "anger" then
            member.disposition = nil
        end
    end
end

local function clearAdhesionProperty(target)
    if not target then
        return
    end

    local props = target and target.properties
    if props then
        props.adhered = false
        props.glued = false
        props.adhesive = false
        props.adheredUntil = nil
    end

    local partner = target and target.adheredTo
    target.adheredTo = nil
    target.adheredBond = nil

    if partner then
        local partnerProps = partner.properties
        if partnerProps then
            partnerProps.adhered = false
            partnerProps.glued = false
            partnerProps.adhesive = false
            partnerProps.adheredUntil = nil
            if partnerProps.effectDurations then
                partnerProps.effectDurations.adhered = nil
                partnerProps.effectDurations.glued = nil
                partnerProps.effectDurations.adhesive = nil
                if next(partnerProps.effectDurations) == nil then
                    partnerProps.effectDurations = nil
                end
            end
        end
        if partner.adheredTo == target then
            partner.adheredTo = nil
        end
        partner.adheredBond = nil
    end
end

local function clearWatchPropertyState(target, property)
    if not target then
        return
    end
    local props = target.properties or {}
    target.properties = props
    props[property] = false

    if property == "adhered" or property == "glued" or property == "adhesive" then
        clearAdhesionProperty(target)
    elseif property == "barkingLure" then
        props.questingBeastBark = false
        props.pendingMeatgrinderDraws = nil
    elseif property == "kelpieOilPlatform" then
        props.oilIsland = false
        props.waterPlatform = false
        props.waterPlatformDiameterFeet = nil
        target.kelpieOilPlatform = nil
    elseif property == "mushroomPatch" then
        props.mushroomPatch = nil
        props.giantMushrooms = false
        target.mushroomPatch = nil
    elseif property == "frictionlessSurface" then
        local puddle = target.slipperyPuddle
        props.frictionlessSurface = false
        props.frictionless = false
        props.utterlyFrictionless = false
        props.slipperyPuddle = false
        props.puddleDiameterFeet = nil
        target.frictionless = false
        if puddle then
            puddle.active = false
            puddle.ended = true
            puddle.endReason = "watch_expired"
        end
        target.slipperyPuddle = nil
        if type(target.hazards) == "table" then
            for index = #target.hazards, 1, -1 do
                local hazard = target.hazards[index]
                local hazardType = type(hazard) == "table" and hazard.type or hazard
                if hazard == puddle or hazardType == "slippery_puddle" or
                   hazardType == "frictionless_puddle" or hazardType == "frictionless" then
                    table.remove(target.hazards, index)
                end
            end
        end
    elseif property == "magicSuppressed" then
        props.magicSuppressed = false
        props.spellsNegated = false
        props.enchantmentPaused = false
        props.magicSuppressedUntil = nil
        props.enchantmentPausedUntil = nil
        if type(target.pausedEnchantments) == "table" then
            for _, enchantment in ipairs(target.pausedEnchantments) do
                enchantment.paused = false
                enchantment.pausedUntil = nil
                enchantment.resumedAfterSuppression = true
            end
        end
        target.pausedEnchantments = nil
        target.magicSuppressionEnded = true
    end
end

local function annotateQuestingBeastLureDraw(draw, target)
    if not draw then
        return
    end

    draw.questingBeastLure = true
    draw.lureTarget = target
    draw.lureTargetId = target and target.id or nil
end

--------------------------------------------------------------------------------
-- WATCH MANAGER FACTORY
--------------------------------------------------------------------------------

--- Create a new WatchManager
-- @param config table: { gameClock, gmDeck, dungeon, guild, eventBus }
-- @return WatchManager instance
function M.createWatchManager(config)
    config = config or {}

    local manager = {
        gameClock   = config.gameClock,
        gmDeck      = config.gmDeck,
        dungeon     = config.dungeon,
        guild       = config.guild or {},      -- Array of adventurer entities
        eventBus    = config.eventBus or events.globalBus,
        watchCount  = 0,
        currentRoom = config.startingRoom or nil,
        mappedRooms = config.mappedRooms or {},
        mappedRoomTravelPerWatch = config.mappedRoomTravelPerWatch or 1,
        mappedRoomTravelProgress = 0,
        roomsTraveledSinceLastMap = {},
        forcedEncounters = config.forcedEncounters or {},
        meatgrinder = config.meatgrinder,
        meatgrinderContext = config.meatgrinderContext or {},
        roomManager = config.roomManager,
        trackedObjects = config.trackedObjects or config.objects or {},
    }

    if config.meatgrinderTable then
        if not manager.meatgrinder then
            manager.meatgrinder = meatgrinder_engine.createMeatgrinder({
                eventBus = manager.eventBus,
                entityFactory = config.entityFactory or entity_factory,
            })
        end

        if manager.meatgrinder.registerTable then
            manager.meatgrinder:registerTable(config.meatgrinderTable)
        end
    end

    if manager.currentRoom then
        manager.roomsTraveledSinceLastMap[#manager.roomsTraveledSinceLastMap + 1] = manager.currentRoom
    end

    ----------------------------------------------------------------------------
    -- MEATGRINDER DRAW
    -- Draws from GM deck and categorizes result
    ----------------------------------------------------------------------------

    function manager:emitMeatgrinderDraw(result)
        if not result then
            return
        end

        -- Emit the general meatgrinder event
        self.eventBus:emit(events.EVENTS.MEATGRINDER_ROLL, result)

        -- Emit category-specific event
        if result.category == M.MEATGRINDER.TORCHES_GUTTER then
            self.eventBus:emit(events.EVENTS.TORCHES_GUTTER, result)
        elseif result.category == M.MEATGRINDER.RANDOM_ENCOUNTER then
            self.eventBus:emit(events.EVENTS.RANDOM_ENCOUNTER, result)
        elseif result.category == M.MEATGRINDER.CURIOSITY then
            self.eventBus:emit(events.EVENTS.CURIOSITY, result)
        elseif result.category == M.MEATGRINDER.TRAVEL_EVENT then
            self.eventBus:emit(events.EVENTS.TRAVEL_EVENT, result)
        elseif result.category == M.MEATGRINDER.QUEST_RUMOR then
            self.eventBus:emit(events.EVENTS.QUEST_RUMOR, result)
        end
    end

    --- Draw from Meatgrinder (GM deck) and emit appropriate event
    -- @return table: { card, category, value }
    function manager:drawMeatgrinder(options)
        options = options or {}
        if not self.gmDeck then
            return nil
        end

        local card = self.gmDeck:draw()
        if not card then
            return nil
        end

        -- Notify GameClock about the draw (for Fool tracking)
        if self.gameClock and self.gameClock.onCardDrawn then
            self.gameClock:onCardDrawn(card)
        end

        local category = categorizeMeatgrinderDraw(card.value)

        local result = {
            card     = card,
            category = category,
            value    = card.value,
            roomId   = self.currentRoom,
        }

        local resolved = resolveAuthoredMeatgrinder(self, card)
        if resolved then
            result.result = resolved
            result.description = resolved.description
            result.effects = resolved.effects
            result.spawns = resolved.spawns
            result.consumed = resolved.consumed
            result.raw = resolved.raw
        end

        if options.emitEvents ~= false then
            self:emitMeatgrinderDraw(result)
        end

        -- Discard the card
        self.gmDeck:discard(card)

        return result
    end

    function manager:resolvePendingBarkingLureDraws(targets)
        local resolved = {}

        for _, target in ipairs(targets or self.trackedObjects or {}) do
            local props = target and target.properties
            local pending = props and tonumber(props.pendingMeatgrinderDraws)
            pending = pending and math.max(0, math.floor(pending)) or 0

            if pending > 0 and (props.barkingLure or props.questingBeastBark) then
                local detail = {
                    target = target,
                    requestedDrawCount = pending,
                    resolvedDrawCount = 0,
                    draws = {},
                    encounters = {},
                    watchNumber = self.watchCount,
                }

                for _ = 1, pending do
                    local draw = self:drawMeatgrinder()
                    if not draw then
                        break
                    end

                    annotateQuestingBeastLureDraw(draw, target)
                    detail.draws[#detail.draws + 1] = draw
                    detail.resolvedDrawCount = detail.resolvedDrawCount + 1

                    if draw.category == M.MEATGRINDER.RANDOM_ENCOUNTER then
                        detail.encounters[#detail.encounters + 1] = draw
                    end
                end

                if detail.resolvedDrawCount >= pending then
                    props.pendingMeatgrinderDraws = nil
                else
                    props.pendingMeatgrinderDraws = pending - detail.resolvedDrawCount
                    detail.remainingDrawCount = props.pendingMeatgrinderDraws
                    detail.unresolved = detail.resolvedDrawCount == 0
                end

                resolved[#resolved + 1] = detail
            end
        end

        return resolved
    end

    ----------------------------------------------------------------------------
    -- FORCED ENCOUNTERS
    ----------------------------------------------------------------------------

    function manager:scheduleForcedEncounter(encounter)
        encounter = encounter or {}
        local scheduled = {}
        for key, value in pairs(encounter) do
            scheduled[key] = value
        end

        scheduled.category = scheduled.category or M.MEATGRINDER.RANDOM_ENCOUNTER
        scheduled.source = scheduled.source or "forced"
        scheduled.scheduledAtWatch = self.watchCount
        scheduled.nextWatch = (self.watchCount or 0) + 1

        self.forcedEncounters = self.forcedEncounters or {}
        self.forcedEncounters[#self.forcedEncounters + 1] = scheduled
        return scheduled
    end

    function manager:consumeForcedEncounters()
        local queue = self.forcedEncounters or {}
        if #queue == 0 then
            return {}
        end

        self.forcedEncounters = {}
        local forcedResults = {}

        for _, encounter in ipairs(queue) do
            local result = createForcedEncounterResult(encounter)
            forcedResults[#forcedResults + 1] = result
            self.eventBus:emit(events.EVENTS.MEATGRINDER_ROLL, result)
            self.eventBus:emit(events.EVENTS.RANDOM_ENCOUNTER, result)
        end

        return forcedResults
    end

    ----------------------------------------------------------------------------
    -- DEATH'S DOOR EXPIRY
    ----------------------------------------------------------------------------

    function manager:expireDeathsDoorMembers()
        local expired = {}

        for _, member in ipairs(self.guild or {}) do
            if member and member.isPC ~= false and member.conditions and
               member.conditions.deaths_door and not member.conditions.dead then
                local didExpire = false

                if member.expireDeathsDoor then
                    didExpire = member:expireDeathsDoor(self.watchCount)
                elseif self.watchCount > 0 then
                    member.conditions.dead = true
                    didExpire = true
                end

                if didExpire then
                    if member.scheduleUndeadRise then
                        member:scheduleUndeadRise("zombie", self.watchCount, {
                            reason = "death_door_expired",
                        })
                    end

                    expired[#expired + 1] = member
                    self.eventBus:emit(events.EVENTS.ENTITY_DEFEATED, {
                        entity = member,
                        reason = "death_door_expired",
                        watchNumber = self.watchCount,
                    })
                end
            end
        end

        return expired
    end

    function manager:raiseScheduledUndead()
        local raised = {}

        for _, member in ipairs(self.guild or {}) do
            local schedule = member and member.undeadRise
            if schedule and not schedule.raised then
                if schedule.prevented or schedule.bodyDestroyed or member.undeadRisePrevented or member.preventUndeadRise then
                    schedule.raised = true
                    schedule.prevented = true
                    schedule.preventedAtWatch = self.watchCount
                    schedule.preventedReason = schedule.preventedReason or "undead_rise_prevented"
                else
                    local riseAtWatch = tonumber(schedule.riseAtWatch)
                    if not riseAtWatch or self.watchCount >= riseAtWatch then
                        local undead = nil
                        if schedule.type == "zombie" then
                            undead = entity_factory.createUndeadFromAdventurer(member, "zombie", {
                                location = member.location,
                                zone = member.zone,
                            })
                        end

                        if undead then
                            if member.markUndeadRaised then
                                member:markUndeadRaised(undead, self.watchCount)
                            else
                                schedule.raised = true
                            end
                            raised[#raised + 1] = undead
                            self.eventBus:emit(events.EVENTS.UNDEAD_RAISED, {
                                source = member,
                                undead = undead,
                                undeadType = schedule.type or "zombie",
                                reason = schedule.reason,
                                watchNumber = self.watchCount,
                            })
                        end
                    end
                end
            end
        end

        return raised
    end

    function manager:clearWatchDurationConditions()
        local expired = {}

        for _, member in ipairs(self.guild or {}) do
            local durations = member and member.conditionDurations
            if durations then
                member.conditions = member.conditions or {}
                for condition, duration in pairs(durations) do
                    if duration and duration.duration == "watch" then
                        member.conditions[condition] = false
                        if member[condition] == true then
                            member[condition] = false
                        end
                        if condition == "second_sight" and member.secondSight then
                            local secondSight = member.secondSight
                            secondSight.active = false
                            secondSight.ended = true
                            secondSight.endReason = "watch_expired"
                            for _, entry in ipairs(secondSight.previousFields or {}) do
                                member[entry.key] = entry.value
                            end
                            member.secondSight = nil
                        end
                        if condition == "sizeChanged" or condition == "sizeGrown" or condition == "titan_growth" then
                            clearAlchemicalSizeChange(member)
                        end
                        if condition == "face_rat_illusion" or condition == "illusion_duplicate_active" or
                           condition == "face_rat_duplicate" then
                            clearFaceRatIllusion(member)
                        end
                        if condition == "jinn_shroud" or condition == "see_shrouded" or
                           condition == "shrouded" or condition == "invisible" then
                            clearJinnPotionShroud(member)
                        end
                        if condition == "jinn_materialized" then
                            clearJinnBombMaterialization(member)
                        end
                        if condition == "vampire_weaknesses" or condition == "sunlight_stuns" or
                           condition == "wholesome_herbs_stun" or condition == "silver_stuns" or
                           condition == "running_water_stuns" then
                            clearVampireWeaknesses(member)
                        end
                        if condition == "mist_form" or condition == "vampire_mist" or
                           condition == "hazard_resistant" or condition == "can_pass_cracks" then
                            clearAlchemicalMistForm(member)
                        end
                        if condition == "inspiredRomanticJoy" or condition == "inLove" then
                            clearAlchemicalInspiration(member, "romantic")
                        end
                        if condition == "inspiredDistaste" or condition == "inHate" then
                            clearAlchemicalInspiration(member, "distaste")
                        end
                        if condition == "inspiredAnger" or condition == "enraged" then
                            clearAlchemicalInspiration(member, "anger")
                        end
                        durations[condition] = nil

                        local detail = {
                            entity = member,
                            condition = condition,
                            timing = "watch",
                            watchNumber = self.watchCount,
                        }
                        expired[#expired + 1] = detail
                        self.eventBus:emit(events.EVENTS.CONDITION_EXPIRED, detail)
                    end
                end

                if next(durations) == nil then
                    member.conditionDurations = nil
                end
            end
        end

        return expired
    end

    function manager:clearWatchDurationProperties(targets)
        local expired = {}

        for _, target in ipairs(targets or self.trackedObjects or {}) do
            local props = target and target.properties
            local durations = props and props.effectDurations
            if durations then
                for property, duration in pairs(durations) do
                    if duration and duration.duration == "watch" then
                        clearWatchPropertyState(target, property)
                        durations[property] = nil

                        local detail = {
                            target = target,
                            property = property,
                            timing = "watch",
                            watchNumber = self.watchCount,
                        }
                        expired[#expired + 1] = detail
                        self.eventBus:emit(events.EVENTS.PROPERTY_EXPIRED, detail)
                    end
                end

                if next(durations) == nil then
                    props.effectDurations = nil
                end
            end
        end

        return expired
    end

    function manager:resolvePendingDungeonBirdRumors()
        local delivered = {}

        for _, member in ipairs(self.guild or {}) do
            local pending = member and member.pendingDungeonBirdRumors
            if type(pending) == "table" then
                for index = #pending, 1, -1 do
                    local birdRumor = pending[index]
                    if type(birdRumor) == "table" and birdRumor.pending ~= false then
                        local remaining = birdRumor.remainingWatches
                        if remaining == nil then
                            remaining = birdRumor.arrivesInWatches or 1
                        end
                        remaining = math.max(0, tonumber(remaining) or 1) - 1
                        birdRumor.remainingWatches = remaining

                        if remaining <= 0 then
                            birdRumor.pending = false
                            birdRumor.delivered = true
                            birdRumor.deliveredAtWatch = self.watchCount
                            birdRumor.arrival = birdRumor.arrival or "dungeon_bird"
                            birdRumor.looksLikeOwl = birdRumor.looksLikeOwl ~= false
                            birdRumor.isOwl = false

                            member.deliveredDungeonBirdRumors = member.deliveredDungeonBirdRumors or {}
                            member.deliveredDungeonBirdRumors[#member.deliveredDungeonBirdRumors + 1] = birdRumor
                            member.latestDungeonBirdRumor = birdRumor
                            member.dungeonBirdRumor = birdRumor
                            table.remove(pending, index)

                            local detail = {
                                entity = member,
                                rumor = birdRumor.rumor,
                                dungeonBirdRumor = birdRumor,
                                watchNumber = self.watchCount,
                            }
                            delivered[#delivered + 1] = detail
                            self.eventBus:emit(events.EVENTS.DUNGEON_BIRD_RUMOR_DELIVERED, detail)
                        end
                    end
                end

                if #pending == 0 then
                    member.pendingDungeonBirdRumors = nil
                end
            end
        end

        return delivered
    end

    ----------------------------------------------------------------------------
    -- INCREMENT WATCH
    -- Called when time passes (movement, long tasks, phase changes)
    ----------------------------------------------------------------------------

    --- Increment the watch counter and trigger Meatgrinder
    -- @param options table: { careful = bool, loud = bool }
    -- @return table: { watchNumber, meatgrinderResults[] }
    function manager:incrementWatch(options)
        options = options or {}

        self.watchCount = self.watchCount + 1

        local results = {
            watchNumber        = self.watchCount,
            reason             = options.reason or options.watchReason or options.source,
            source             = options.source or options.reason or options.watchReason,
            longTask           = options.longTask or options.task,
            phase              = options.phase,
            meatgrinderResults = {},
            deathDoorExpired   = {},
            undeadRaised       = {},
            conditionsExpired  = {},
            propertiesExpired  = {},
            barkingLureDraws   = {},
            dungeonBirdRumors  = {},
        }

        local forcedDraws = self:consumeForcedEncounters()
        if #forcedDraws > 0 then
            results.forcedEncounters = forcedDraws
            for _, forcedDraw in ipairs(forcedDraws) do
                results.meatgrinderResults[#results.meatgrinderResults + 1] = forcedDraw
            end
        else
            -- Draw from Meatgrinder
            local firstDraw = self:drawMeatgrinder()
            if firstDraw then
                results.meatgrinderResults[#results.meatgrinderResults + 1] = firstDraw
            end

            -- "Moving Carefully" (p. 91): Draw again, keep if torches gutter
            if options.careful and firstDraw then
                local secondDraw = self:drawMeatgrinder({ emitEvents = false })
                if secondDraw then
                    secondDraw.movingCarefullyDraw = true
                    results.carefulDraw = secondDraw
                    if secondDraw.category == M.MEATGRINDER.TORCHES_GUTTER then
                        -- Keep the torches gutter result
                        results.meatgrinderResults[#results.meatgrinderResults + 1] = secondDraw
                        results.carefulTorchesGutter = true
                        self:emitMeatgrinderDraw(secondDraw)
                    else
                        secondDraw.ignoredByMovingCarefully = true
                        results.carefulIgnoredDraw = secondDraw
                    end
                    -- Otherwise second draw is ignored (but card was still drawn/discarded)
                end
            end
        end

        results.undeadRaised = self:raiseScheduledUndead()
        results.deathDoorExpired = self:expireDeathsDoorMembers()
        results.conditionsExpired = self:clearWatchDurationConditions()
        results.barkingLureDraws = self:resolvePendingBarkingLureDraws()
        for _, detail in ipairs(results.barkingLureDraws) do
            for _, draw in ipairs(detail.draws or {}) do
                results.meatgrinderResults[#results.meatgrinderResults + 1] = draw
            end
        end
        results.propertiesExpired = self:clearWatchDurationProperties()
        results.dungeonBirdRumors = self:resolvePendingDungeonBirdRumors()

        -- Emit watch passed event
        self.eventBus:emit(events.EVENTS.WATCH_PASSED, {
            watchNumber      = self.watchCount,
            reason           = results.reason,
            source           = results.source,
            longTask         = results.longTask,
            phase            = results.phase,
            careful          = options.careful or false,
            results          = results.meatgrinderResults,
            deathDoorExpired = results.deathDoorExpired,
            undeadRaised     = results.undeadRaised,
            conditionsExpired = results.conditionsExpired,
            barkingLureDraws = results.barkingLureDraws,
            propertiesExpired = results.propertiesExpired,
            dungeonBirdRumors = results.dungeonBirdRumors,
        })

        return results
    end

    function manager:spendWatchForLongTask(task, options)
        local opts = copyTable(options or {})
        if type(task) == "table" then
            for key, value in pairs(task) do
                opts[key] = value
            end
            opts.longTask = opts.longTask or opts.task or opts.description or opts.name
        else
            opts.longTask = opts.longTask or task
        end
        opts.reason = opts.reason or opts.watchReason or "long_task"
        opts.source = opts.source or "long_task"
        return self:incrementWatch(opts)
    end

    function manager:spendWatchForPhase(phase, options)
        local opts = copyTable(options or {})
        if type(phase) == "table" then
            for key, value in pairs(phase) do
                opts[key] = value
            end
            opts.phase = opts.phase or opts.phaseName or opts.name
        else
            opts.phase = opts.phase or phase
        end
        opts.reason = opts.reason or opts.watchReason or "phase"
        opts.source = opts.source or "phase"
        return self:incrementWatch(opts)
    end

    ----------------------------------------------------------------------------
    -- LOUD NOISE
    -- Special Meatgrinder check - only triggers on random encounter
    ----------------------------------------------------------------------------

    --- Check for encounters due to loud noise
    -- @return table: { triggered, result } - triggered is true if encounter occurs
    function manager:checkLoudNoise()
        local draw = self:drawMeatgrinder({ emitEvents = false })

        if draw and isLoudNoiseEncounterValue(draw.value) then
            draw.loudNoiseEncounter = true
            if draw.category ~= M.MEATGRINDER.RANDOM_ENCOUNTER then
                draw.normalCategory = draw.category
                draw.category = M.MEATGRINDER.RANDOM_ENCOUNTER
            end
            self:emitMeatgrinderDraw(draw)
            return { triggered = true, result = draw }
        end

        if draw then
            draw.ignoredByLoudNoise = true
        end
        return { triggered = false, result = draw }
    end

    ----------------------------------------------------------------------------
    -- PARTY MOVEMENT
    -- Updates location of all guild members and advances watch
    ----------------------------------------------------------------------------

    function manager:markMappedRooms(roomIds)
        self.mappedRooms = self.mappedRooms or {}
        for _, roomId in ipairs(roomIds or {}) do
            if roomId then
                self.mappedRooms[roomId] = true
            end
        end
        return self
    end

    function manager:isMappedRoom(roomId)
        return self.mappedRooms and self.mappedRooms[roomId] == true
    end

    function manager:buildCrawlSceneFrame(targetRoomId, targetRoom, previousRoom, watchResult, entryTriggers, options)
        options = options or {}
        local meatgrinderResults = watchResult and watchResult.meatgrinderResults or {}
        local descriptionParts = {}
        appendText(descriptionParts, firstText(
            targetRoom and targetRoom.description,
            targetRoom and targetRoom.summary,
            targetRoom and targetRoom.name
        ))
        for _, draw in ipairs(meatgrinderResults or {}) do
            appendText(descriptionParts, draw.description or (draw.result and draw.result.description))
        end

        return {
            roomId = targetRoomId,
            room = targetRoom,
            previousRoom = previousRoom,
            watchNumber = watchResult and watchResult.watchNumber or self.watchCount,
            watchSpent = watchResult ~= nil,
            meatgrinderResults = meatgrinderResults,
            entryTriggers = entryTriggers,
            description = table.concat(descriptionParts, "\n"),
            prompts = {
                light = options.lightPrompt or "What light do you have?",
                action = options.actionPrompt or "What do you do?",
                hands = options.handsPrompt or "What do you have in your hands?",
            },
            flow = {
                "declare_destination",
                "draw_meatgrinder",
                "ask_light",
                "describe_room_with_meatgrinder",
                "ask_what_do_you_do",
                "ask_hands_for_adjudication",
            },
        }
    end

    function manager:setMappedRoomTravelPerWatch(value)
        self.mappedRoomTravelPerWatch = math.max(1, tonumber(value) or 1)
        return self
    end

    function manager:getRoomsTraveledSinceLastMap()
        local out = {}
        for i, roomId in ipairs(self.roomsTraveledSinceLastMap or {}) do
            out[i] = roomId
        end
        return out
    end

    function manager:clearRoomsTraveledSinceLastMap()
        self.roomsTraveledSinceLastMap = {}
        return self
    end

    function manager:recordRoomForMapping(roomId)
        if not roomId then
            return
        end

        local rooms = self.roomsTraveledSinceLastMap or {}
        for _, existing in ipairs(rooms) do
            if existing == roomId then
                return
            end
        end
        rooms[#rooms + 1] = roomId
        self.roomsTraveledSinceLastMap = rooms
    end

    function manager:shouldSpendWatchForRoomMove(previousRoom, targetRoomId, options)
        options = options or {}
        local mappedTravel = previousRoom and targetRoomId and
            self.mappedRoomTravelPerWatch > 1 and
            self:isMappedRoom(previousRoom) and
            self:isMappedRoom(targetRoomId) and
            not options.forceWatch

        if not mappedTravel then
            self.mappedRoomTravelProgress = 0
            return true
        end

        self.mappedRoomTravelProgress = (self.mappedRoomTravelProgress or 0) + 1
        if self.mappedRoomTravelProgress >= self.mappedRoomTravelPerWatch then
            self.mappedRoomTravelProgress = 0
            return true
        end

        return false
    end

    --- Move the entire party to a new room
    -- @param targetRoomId string: The room to move to
    -- @param options table: { careful = bool }
    -- @return boolean, table: success, { watchResult, previousRoom, newRoom }
    function manager:moveParty(targetRoomId, options)
        options = options or {}

        if not self.dungeon then
            return false, { error = "no_dungeon" }
        end

        local targetRoom = self.dungeon:getRoom(targetRoomId)
        if not targetRoom then
            return false, { error = "room_not_found" }
        end

        -- Check if movement is valid (room is adjacent and accessible)
        if self.currentRoom then
            local connection = self.dungeon:getConnection(self.currentRoom, targetRoomId)
            if not connection then
                return false, { error = "no_connection" }
            end
            if connection.is_locked then
                return false, { error = "connection_locked" }
            end
            if connection.is_secret and not connection.discovered then
                return false, { error = "connection_secret" }
            end
            if connection.is_blocked then
                return false, {
                    error = "connection_blocked",
                    blockedBy = connection.blocked_by,
                    clearedBy = connection.cleared_by,
                    alternateRoute = connection.alternate_route,
                    description = connection.description,
                }
            end
        end

        local previousRoom = self.currentRoom
        self:recordRoomForMapping(previousRoom)

        -- Update party location
        self.currentRoom = targetRoomId
        self:recordRoomForMapping(targetRoomId)

        -- Update each guild member's location
        for _, member in ipairs(self.guild) do
            member.location = targetRoomId
        end

        local entryTriggers = nil
        if self.roomManager and self.roomManager.resolveRoomEntryTriggers then
            entryTriggers = self.roomManager:resolveRoomEntryTriggers(targetRoomId, {
                reason = options.entryTriggerReason or "room_entry",
                watch = self.watchCount,
            })
        end

        -- Emit room entered event
        self.eventBus:emit(events.EVENTS.ROOM_ENTERED, {
            roomId   = targetRoomId,
            room     = targetRoom,
            previous = previousRoom,
            entryTriggers = entryTriggers,
        })

        -- Increment the watch (triggers Meatgrinder). Mapped routes can cover two
        -- mapped room transitions per event after the Update Maps Camp Action.
        local watchResult = nil
        local watchSpent = self:shouldSpendWatchForRoomMove(previousRoom, targetRoomId, options)
        if watchSpent then
            watchResult = self:incrementWatch({ careful = options.careful })
        end

        local sceneFrame = self:buildCrawlSceneFrame(targetRoomId, targetRoom, previousRoom, watchResult,
            entryTriggers, options)
        self.lastCrawlSceneFrame = sceneFrame
        self.eventBus:emit(events.EVENTS.CRAWL_SCENE_SET, sceneFrame)

        -- Emit party moved event
        self.eventBus:emit(events.EVENTS.PARTY_MOVED, {
            from                      = previousRoom,
            to                        = targetRoomId,
            watchNumber               = watchResult and watchResult.watchNumber or self.watchCount,
            watchSpent                = watchSpent,
            mappedRoomTravelProgress  = self.mappedRoomTravelProgress,
            mappedRoomTravelPerWatch  = self.mappedRoomTravelPerWatch,
            entryTriggers             = entryTriggers,
            crawlScene                = sceneFrame,
        })

        return true, {
            watchResult               = watchResult,
            watchSpent                = watchSpent,
            previousRoom              = previousRoom,
            newRoom                   = targetRoomId,
            entryTriggers             = entryTriggers,
            crawlScene                = sceneFrame,
            mappedRoomTravelProgress  = self.mappedRoomTravelProgress,
            mappedRoomTravelPerWatch  = self.mappedRoomTravelPerWatch,
        }
    end

    ----------------------------------------------------------------------------
    -- UTILITY
    ----------------------------------------------------------------------------

    --- Get current watch count
    function manager:getWatchCount()
        return self.watchCount
    end

    --- Get current room
    function manager:getCurrentRoom()
        return self.currentRoom
    end

    --- Set guild members
    function manager:setGuild(guildMembers)
        self.guild = guildMembers
        return self
    end

    --- Add a member to the guild
    function manager:addGuildMember(entity)
        self.guild[#self.guild + 1] = entity
        entity.location = self.currentRoom
        return self
    end

    return manager
end

return M
