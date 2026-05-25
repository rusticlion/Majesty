-- challenge_input_controller.lua
-- Encapsulates Challenge-phase input flow:
-- card select -> action select -> target/zone select -> execute

local constants = require('constants')
local events = require('logic.events')
local action_registry = require('data.action_registry')

local M = {}

local function createDefaultInputState()
    return {
        selectedCard = nil,
        selectedCardIndex = nil,
        selectedEntity = nil,
        selectedAction = nil,
        foolCard = nil,
        foolCardIndex = nil,
        foolFollowUpCard = nil,
        foolFollowUpCardIndex = nil,
        awaitingFoolFollowUpCard = false,
        awaitingTarget = false,
        awaitingAidTriggerTarget = false,
        awaitingObjectTarget = false,
        awaitingSecondaryObjectTarget = false,
        awaitingZone = false,
        awaitingRoughhouseDisplaceZone = false,
        availableZones = nil,
        availableAidTriggerTargets = nil,
        availableObjectTargets = nil,
        selectedAidTarget = nil,
        selectedAidTriggerTarget = nil,
        selectedAidTriggerTargetAction = nil,
        selectedObjectTarget = nil,
        selectedRoughhouseDisplaceTarget = nil,
        minorPC = nil,
        selectedVigilanceFollowUp = nil,
        selectedVigilanceTrigger = nil,
        selectedVigilanceTriggerOption = nil,
        selectedRoughhouseEffect = nil,
        selectedCommandName = nil,
        selectedCommandCompanionId = nil,
        selectedCommandOption = nil,
        selectedCommandTrick = nil,
        selectedCommandObjectTarget = nil,
        selectedAidTrigger = nil,
        selectedAidTriggerOption = nil,
        selectedPullItem = nil,
        selectedPullItemId = nil,
        selectedPullItemOption = nil,
        selectedPullSwapItem = nil,
        selectedPullSwapItemId = nil,
        selectedPullSwapOption = nil,
        selectedUseItem = nil,
        selectedUseItemId = nil,
        selectedUseItemOption = nil,
        selectedUpMySleeveItem = nil,
        selectedUpMySleeveItemSpec = nil,
        selectedUpMySleeveOption = nil,
        selectedCounterSpellMode = nil,
        selectedCounterSpellActiveSpell = nil,
        selectedCounterSpellCaster = nil,
        pendingCounterSpellInterrupt = nil,
        counterSpellCandidateIndex = nil,
        awaitingCounterSpellCard = false,
        pendingAmbusherResistance = nil,
        ambusherResistanceCandidateIndex = nil,
        awaitingAmbusherResistanceChoice = false,
        pendingWoundChoice = nil,
        awaitingWoundChoice = false,
        awaitingWoundTalentChoice = false,
        awaitingBerserkergangChoice = false,
        pendingBerserkergangTalentId = nil,
        pendingAcrobatFallChoice = nil,
        awaitingAcrobatFallChoice = false,
        pendingRetreatGroupTest = nil,
        retreatTestIndex = nil,
        retreatTestCards = nil,
        retreatFavorTarget = nil,
        awaitingRetreatFavorChoice = false,
        pendingHeavyMetalMachineInterrupt = nil,
        heavyMetalMachineCandidateIndex = nil,
        awaitingHeavyMetalMachineCard = false,
        pendingAegisElection = nil,
        aegisCandidateIndex = nil,
        awaitingAegisChoice = false,
        awaitingQuickInterruptActor = false,
        quickInterruptCandidates = nil,
        quickInterruptActor = nil,
        quickInterruptActive = false,
        counselActive = false,
        awaitingCounselActor = false,
        awaitingCounselCard = false,
        awaitingCounselAction = false,
        awaitingCounselTarget = false,
        awaitingCounselResolveChoice = false,
        counselCandidates = nil,
        counselActor = nil,
        counselCard = nil,
        counselCardIndex = nil,
        counselActionOptions = nil,
        counselAction = nil,
        counselTargetCandidates = nil,
        counselTarget = nil,
    }
end

function M.createChallengeInputController(config)
    config = config or {}

    local gameState = config.gameState
    local eventBus = config.eventBus or events.globalBus
    local inputState = config.inputState or createDefaultInputState()

    assert(gameState, "ChallengeInputController requires gameState")

    local controller = {
        gameState = gameState,
        eventBus = eventBus,
        inputState = inputState,
    }

    local function isFoolCard(card)
        return card and (
            card.name == "The Fool" or
            (card.value == 0 and (card.is_major == true or card.suit == constants.SUITS.MAJOR))
        )
    end

    local function entityHasUsableTalent(entity, talentId)
        if not entity then
            return false
        end
        if entity.canUseTalent then
            return entity:canUseTalent(talentId)
        end

        local talents = entity.talents or {}
        local talent = talents[talentId]
        if type(talent) == "table" then
            if talent.wounded then
                return false
            end
            if talent.mastered ~= nil then
                return talent.mastered == true
            end
            return true
        end
        return talent == true
    end

    local function resetCombatInputState()
        inputState.selectedCard = nil
        inputState.selectedCardIndex = nil
        inputState.selectedEntity = nil
        inputState.selectedAction = nil
        inputState.foolCard = nil
        inputState.foolCardIndex = nil
        inputState.foolFollowUpCard = nil
        inputState.foolFollowUpCardIndex = nil
        inputState.awaitingFoolFollowUpCard = false
        inputState.awaitingTarget = false
        inputState.awaitingAidTriggerTarget = false
        inputState.awaitingObjectTarget = false
        inputState.awaitingSecondaryObjectTarget = false
        inputState.awaitingZone = false
        inputState.awaitingRoughhouseDisplaceZone = false
        inputState.availableZones = nil
        inputState.availableAidTriggerTargets = nil
        inputState.availableObjectTargets = nil
        inputState.selectedAidTarget = nil
        inputState.selectedAidTriggerTarget = nil
        inputState.selectedAidTriggerTargetAction = nil
        inputState.selectedObjectTarget = nil
        inputState.selectedRoughhouseDisplaceTarget = nil
        inputState.minorPC = nil
        inputState.selectedVigilanceFollowUp = nil
        inputState.selectedVigilanceTrigger = nil
        inputState.selectedVigilanceTriggerOption = nil
        inputState.selectedRoughhouseEffect = nil
        inputState.selectedCommandName = nil
        inputState.selectedCommandCompanionId = nil
        inputState.selectedCommandOption = nil
        inputState.selectedCommandTrick = nil
        inputState.selectedCommandObjectTarget = nil
        inputState.selectedAidTrigger = nil
        inputState.selectedAidTriggerOption = nil
        inputState.selectedPullItem = nil
        inputState.selectedPullItemId = nil
        inputState.selectedPullItemOption = nil
        inputState.selectedPullSwapItem = nil
        inputState.selectedPullSwapItemId = nil
        inputState.selectedPullSwapOption = nil
        inputState.selectedUseItem = nil
        inputState.selectedUseItemId = nil
        inputState.selectedUseItemOption = nil
        inputState.selectedUpMySleeveItem = nil
        inputState.selectedUpMySleeveItemSpec = nil
        inputState.selectedUpMySleeveOption = nil
        inputState.selectedCounterSpellMode = nil
        inputState.selectedCounterSpellActiveSpell = nil
        inputState.selectedCounterSpellCaster = nil
        inputState.pendingAmbusherResistance = nil
        inputState.ambusherResistanceCandidateIndex = nil
        inputState.awaitingAmbusherResistanceChoice = false
        inputState.pendingWoundChoice = nil
        inputState.awaitingWoundChoice = false
        inputState.awaitingWoundTalentChoice = false
        inputState.awaitingBerserkergangChoice = false
        inputState.pendingBerserkergangTalentId = nil
        inputState.pendingAcrobatFallChoice = nil
        inputState.awaitingAcrobatFallChoice = false
        inputState.pendingAegisElection = nil
        inputState.aegisCandidateIndex = nil
        inputState.awaitingAegisChoice = false
        inputState.awaitingQuickInterruptActor = false
        inputState.quickInterruptCandidates = nil
        inputState.quickInterruptActor = nil
        inputState.quickInterruptActive = false
        inputState.counselActive = false
        inputState.awaitingCounselActor = false
        inputState.awaitingCounselCard = false
        inputState.awaitingCounselAction = false
        inputState.awaitingCounselTarget = false
        inputState.awaitingCounselResolveChoice = false
        inputState.counselCandidates = nil
        inputState.counselActor = nil
        inputState.counselCard = nil
        inputState.counselCardIndex = nil
        inputState.counselActionOptions = nil
        inputState.counselAction = nil
        inputState.counselTargetCandidates = nil
        inputState.counselTarget = nil
    end

    local function getPlateAt(x, y)
        if not gameState.currentScreen or not gameState.currentScreen.characterPlates then
            return nil, nil
        end

        for i, plate in ipairs(gameState.currentScreen.characterPlates) do
            local plateHeight = plate.getHeight and plate:getHeight() or 0
            local plateWidth = plate.width or 0
            if x >= plate.x and x <= plate.x + plateWidth and
               y >= plate.y and y <= plate.y + plateHeight then
                return plate, i
            end
        end

        return nil, nil
    end

    local function getHandCardIndexAt(x, y, pc, maxIndex)
        local hand = gameState.playerHand
        local cards = hand:getHand(pc)
        if #cards == 0 then
            return nil
        end

        local w, h = love.graphics.getDimensions()
        local cardWidth = 100
        local cardHeight = 140
        local cardSpacing = 20
        local totalWidth = (#cards * cardWidth) + ((#cards - 1) * cardSpacing)
        local startX = (w - totalWidth) / 2
        local startY = h - cardHeight - 70

        for i, _ in ipairs(cards) do
            if maxIndex and i > maxIndex then
                break
            end
            local cx = startX + (i - 1) * (cardWidth + cardSpacing)
            if x >= cx and x <= cx + cardWidth and y >= startY and y <= startY + cardHeight then
                return i
            end
        end

        return nil
    end

    local function selectCardForAction(entity, cardIndex, isPrimaryTurn)
        local hand = gameState.playerHand
        local cards = hand:getHand(entity)
        if cardIndex > #cards then
            print("[COMBAT] No card at position " .. cardIndex)
            return false
        end

        local card = cards[cardIndex]

        local challengeState = gameState.challengeController and gameState.challengeController:getState()
        local canPlayFoolInterrupt = isPrimaryTurn or challengeState == "minor_window"

        if canPlayFoolInterrupt and isFoolCard(card) then
            inputState.selectedCard = nil
            inputState.selectedCardIndex = nil
            inputState.selectedEntity = entity
            inputState.selectedAction = nil
            inputState.foolCard = card
            inputState.foolCardIndex = cardIndex
            inputState.foolFollowUpCard = nil
            inputState.foolFollowUpCardIndex = nil
            inputState.awaitingFoolFollowUpCard = true

            eventBus:emit("card_deselected", {})
            eventBus:emit("fool_followup_card_requested", {
                entity = entity,
                card = card,
                cardIndex = cardIndex,
            })
            print("[FOOL INTERRUPT] Select a follow-up card for " .. (entity.name or "this adventurer") .. ".")
            return true
        end

        inputState.selectedCard = card
        inputState.selectedCardIndex = cardIndex
        inputState.selectedEntity = entity

        eventBus:emit("card_selected", {
            card = card,
            entity = entity,
            isPrimaryTurn = isPrimaryTurn,
            cardIndex = cardIndex,
        })

        return true
    end

    local function selectFoolFollowUpCard(entity, cardIndex)
        local hand = gameState.playerHand
        local cards = hand:getHand(entity)
        if cardIndex > #cards then
            print("[FOOL INTERRUPT] No card at position " .. cardIndex)
            return false
        end

        local card = cards[cardIndex]
        if card == inputState.foolCard or cardIndex == inputState.foolCardIndex or isFoolCard(card) then
            print("[FOOL INTERRUPT] The Fool must be played with another non-Fool card.")
            return false
        end

        inputState.selectedCard = card
        inputState.selectedCardIndex = cardIndex
        inputState.selectedEntity = entity
        inputState.selectedAction = nil
        inputState.foolFollowUpCard = card
        inputState.foolFollowUpCardIndex = cardIndex
        inputState.awaitingFoolFollowUpCard = false

        eventBus:emit("card_selected", {
            card = card,
            entity = entity,
            isPrimaryTurn = true,
            cardIndex = cardIndex,
            foolInterrupt = true,
            foolCard = inputState.foolCard,
        })
        print("[FOOL INTERRUPT] " .. (entity.name or "Adventurer") ..
              " selected " .. (card.name or "a follow-up card") .. " - choose action from Command Board")
        return true
    end

    local function getValidTargetsForAction(action, actor)
        local challengeController = gameState.challengeController
        local actorZone = actor and actor.zone

        if not action then
            return {}
        end

        local isMelee = (action.id == "melee" or action.id == "roughhouse" or action.id == "grapple" or
            action.id == "trip" or action.id == "disarm" or
            action.id == "displace")
        local reaverMelee = action.id == "melee" and
            (action.useReaver == true or action.reaver == true or action.reaverCharge == true)

        local targets = {}

        local function zoneDistance(fromZone, toZone)
            if not fromZone or not toZone then
                return nil
            end
            if fromZone == toZone then
                return 0
            end

            local resolver = gameState.actionResolver
            if resolver and resolver.getZoneDistance then
                local distance, err = resolver:getZoneDistance({
                    challengeController = challengeController,
                }, fromZone, toZone)
                if err == nil then
                    return distance
                end
            end

            local zoneSystem = gameState.zoneRegistry or (challengeController and challengeController.zoneSystem)
            if zoneSystem and zoneSystem.getZone and zoneSystem.areZonesAdjacent and
               zoneSystem:getZone(fromZone) and zoneSystem:getZone(toZone) and
               zoneSystem:areZonesAdjacent(fromZone, toZone) then
                return 1
            end

            return nil
        end

        local function addIfValid(entity)
            if not (entity.conditions and entity.conditions.dead) then
                if action.id == "aid" and actor and (entity == actor or entity.id == actor.id) then
                    return
                end
                if isMelee then
                    local distance = zoneDistance(actorZone, entity.zone)
                    if distance == 0 or (reaverMelee and distance == 1) then
                        targets[#targets + 1] = entity
                    end
                else
                    targets[#targets + 1] = entity
                end
            end
        end

        local targetType = action.targetType or "any"

        if targetType == "enemy" or targetType == "any" then
            for _, npc in ipairs(challengeController.npcs or {}) do
                addIfValid(npc)
            end
        end

        if targetType == "ally" or targetType == "any" then
            for _, pc in ipairs(challengeController.pcs or {}) do
                addIfValid(pc)
            end
        end

        return targets
    end

    local function getAvailableDestinationZones(actor, action)
        local challengeController = gameState.challengeController
        local zones = (challengeController and challengeController.zones) or {}
        local currentZone = actor and actor.zone
        local zoneSystem = gameState.zoneRegistry or (challengeController and challengeController.zoneSystem)
        local actionId = action and action.id
        local maxDistance = actionId == "dash" and 2 or 1
        local resolver = gameState.actionResolver

        local availableZones = {}
        for _, zone in ipairs(zones) do
            if zone.id ~= currentZone then
                local isAdjacent = true
                if resolver and resolver.getZoneDistance then
                    local distance, err = resolver:getZoneDistance({
                        challengeController = challengeController,
                    }, currentZone, zone.id)
                    isAdjacent = err == nil and distance and distance > 0 and distance <= maxDistance
                elseif zoneSystem and currentZone and zoneSystem.getZone and zoneSystem.areZonesAdjacent then
                    local fromZone = zoneSystem:getZone(currentZone)
                    local toZone = zoneSystem:getZone(zone.id)
                    if fromZone and toZone then
                        isAdjacent = zoneSystem:areZonesAdjacent(currentZone, zone.id)
                    elseif toZone == nil then
                        isAdjacent = false
                    end
                end

                if isAdjacent then
                    availableZones[#availableZones + 1] = zone
                end
            end
        end

        return availableZones
    end

    local function getZoneTraversalMode(zone)
        if not zone then
            return nil
        end
        local props = zone.properties or {}
        local mode = zone.traversalMode or zone.traversal or zone.movementMode or zone.terrainMode or
            props.traversalMode or props.traversal or props.movementMode or props.terrainMode
        if mode then
            return mode
        end
        if zone.climb == true or zone.climbing == true or zone.requiresClimb == true or
           zone.sheer == true or zone.vertical == true or zone.verticalTraversal == true or
           props.climb == true or props.climbing == true or props.requiresClimb == true or
           props.sheer == true or props.vertical == true or props.verticalTraversal == true then
            return "climb"
        end
        if zone.narrowLedge == true or zone.ledge == true or props.narrowLedge == true or props.ledge == true then
            return "ledge"
        end
        if zone.tightrope == true or props.tightrope == true then
            return "tightrope"
        end
        if zone.requiresAcrobatTraversal == true or zone.acrobatTraversal == true or
           zone.difficultTraversal == true or zone.difficultTerrain == true or
           props.requiresAcrobatTraversal == true or props.acrobatTraversal == true or
           props.difficultTraversal == true or props.difficultTerrain == true then
            return "difficult_terrain"
        end
        return nil
    end

    local function getZoneTraversalDetail(zone)
        local mode = getZoneTraversalMode(zone)
        if not mode then
            return nil
        end
        local props = zone.properties or {}
        return {
            mode = mode,
            zoneId = zone.id,
            zoneName = zone.name,
            requiresAcrobatTraversal = zone.requiresAcrobatTraversal == true or
                zone.acrobatTraversal == true or props.requiresAcrobatTraversal == true or
                props.acrobatTraversal == true or nil,
            difficultTraversal = zone.difficultTraversal == true or zone.difficultTerrain == true or
                props.difficultTraversal == true or props.difficultTerrain == true or nil,
        }
    end

    local function getDestinationZoneById(zoneId)
        if not zoneId then
            return nil
        end
        for _, zone in ipairs(inputState.availableZones or {}) do
            if zone.id == zoneId then
                return zone
            end
        end
        local challengeController = gameState.challengeController
        for _, zone in ipairs((challengeController and challengeController.zones) or {}) do
            if zone.id == zoneId then
                return zone
            end
        end
        return nil
    end

    local function getMoveTraversalForDestination(action, destinationZone)
        if not (action and action.id == "move" and destinationZone) then
            return nil
        end
        return getZoneTraversalDetail(getDestinationZoneById(destinationZone))
    end

    local function formatZoneOption(zone)
        local name = zone and (zone.name or zone.id) or "?"
        local traversal = getZoneTraversalDetail(zone)
        if traversal then
            return name .. " [" .. tostring(traversal.mode):gsub("_", " ") .. "]"
        end
        return name
    end

    local function isRoughhouseDisplaceSelection(action)
        return action and action.id == "roughhouse" and inputState.selectedRoughhouseEffect == "displace"
    end

    local function beginRoughhouseDisplaceZoneSelection(target)
        local availableZones = getAvailableDestinationZones(target, inputState.selectedAction)

        if #availableZones == 0 then
            print("[COMBAT] No adjacent zones available for Roughhouse Displace!")
            resetCombatInputState()
            eventBus:emit("card_deselected", {})
            return true
        end

        inputState.awaitingTarget = false
        inputState.awaitingRoughhouseDisplaceZone = true
        inputState.selectedRoughhouseDisplaceTarget = target
        inputState.availableZones = availableZones

        print("[COMBAT] Select displacement zone for " .. (target.name or target.id or "target") ..
            " (1-" .. #availableZones .. "):")
        for i, zone in ipairs(availableZones) do
            print("  " .. i .. ": " .. formatZoneOption(zone))
        end

        return true
    end

    local function getVigilanceFollowUpTargetPolicy(followUpAction)
        if not followUpAction then
            return "none"
        end

        if followUpAction.targetType == "enemy" then
            return "trigger_actor"
        end
        if followUpAction.targetType == "ally" then
            return "self"
        end
        if followUpAction.requiresTarget then
            return "trigger_actor"
        end

        return "none"
    end

    local function getUseItemEffect(item)
        local props = item and item.properties or {}
        if props.useEffect then
            return props.useEffect
        end
        if props.challengeEffect then
            return props.challengeEffect
        end
        if props.effect == "heal_wound" or props.effect == "cure_poison" then
            return { target = "self_or_target" }
        end
        return nil
    end

    local function buildUseItemTargetAction(action, item)
        if not action or action.id ~= "use_item" then
            return nil
        end

        local effect = getUseItemEffect(item)
        local props = item and item.properties or {}
        local targetMode = effect and effect.target
        local targetType = nil

        if targetMode == "self_or_target" then
            targetType = "ally"
        elseif props.bomb or props.offensive or props.hostileUse then
            targetType = "enemy"
        elseif targetMode == "target" and (
            effect.affectedTags or effect.type == "damage" or effect.type == "salt_ooze" or
            effect.type == "ward_undead" or effect.type == "apply_conditions" or effect.type == "reflect_gaze"
        ) then
            targetType = "enemy"
        end

        if not targetType then
            return nil
        end

        local targetAction = {}
        for key, value in pairs(action) do
            targetAction[key] = value
        end
        targetAction.requiresTarget = true
        targetAction.targetType = targetType
        return targetAction
    end

    local function useItemTargetsZone(item)
        local effect = getUseItemEffect(item)
        return effect and (effect.target == "zone" or effect.target == "target_zone")
    end

    local function useItemTargetsObject(item)
        local effect = getUseItemEffect(item)
        if not effect or effect.target ~= "target" then
            return false
        end
        local props = item and item.properties or {}
        if props.bomb or props.offensive or props.hostileUse then
            return false
        end
        if effect.affectedTags or effect.type == "damage" or effect.type == "salt_ooze" or
           effect.type == "ward_undead" or effect.type == "apply_conditions" or effect.type == "reflect_gaze" then
            return false
        end
        return true
    end

    local function actionTargetsObject(action)
        if not action then
            return false
        end
        if action.requiresObjectTarget or action.targetType == "object" then
            return true
        end
        return action.id == "dwimmercraft" and action.dwimmercraftEffect == "levitate"
    end

    local function useItemNeedsSecondaryObjectTarget(item)
        local effect = getUseItemEffect(item)
        return effect and (
            effect.type == "adhere" or effect.secondaryTarget == true or effect.requiresSecondaryTarget == true
        )
    end

    local function getUseItemTargetZones()
        local challengeController = gameState.challengeController
        local zones = (challengeController and challengeController.zones) or {}
        local availableZones = {}
        for _, zone in ipairs(zones) do
            if zone and zone.id then
                availableZones[#availableZones + 1] = zone
            end
        end
        return availableZones
    end

    local function addUseItemObjectTargets(targets, seen, values)
        if type(values) ~= "table" then
            return
        end

        for key, value in pairs(values) do
            if type(value) == "table" and value.destroyed ~= true and value.removed ~= true then
                local id = value.id or value.key or value.name or key
                if not seen[value] and id then
                    seen[value] = true
                    targets[#targets + 1] = value
                end
            end
        end
    end

    local function getUseItemObjectTargets(excludeTarget)
        local challengeController = gameState.challengeController
        local currentScreen = gameState.currentScreen
        local room = gameState.currentRoom or gameState.room or gameState.currentLocation or
            (currentScreen and (currentScreen.currentRoom or currentScreen.room))
        local targets = {}
        local seen = {}

        if challengeController then
            addUseItemObjectTargets(targets, seen, challengeController.sceneObjects)
            addUseItemObjectTargets(targets, seen, challengeController.objects)
            addUseItemObjectTargets(targets, seen, challengeController.objectTargets)
            addUseItemObjectTargets(targets, seen, challengeController.interactables)
            addUseItemObjectTargets(targets, seen, challengeController.features)
            for _, zone in ipairs(challengeController.zones or {}) do
                addUseItemObjectTargets(targets, seen, zone and zone.objects)
                addUseItemObjectTargets(targets, seen, zone and zone.features)
                addUseItemObjectTargets(targets, seen, zone and zone.hazards)
            end
        end

        if room then
            addUseItemObjectTargets(targets, seen, room.objects)
            addUseItemObjectTargets(targets, seen, room.features)
            addUseItemObjectTargets(targets, seen, room.interactables)
            addUseItemObjectTargets(targets, seen, room.hazards)
        end

        if excludeTarget then
            local filtered = {}
            for _, target in ipairs(targets) do
                if target ~= excludeTarget then
                    filtered[#filtered + 1] = target
                end
            end
            targets = filtered
        end

        return targets
    end

    local function getObjectTargetName(target)
        return target and (target.name or target.label or target.title or target.id or target.key) or "object"
    end

    local function commandTargetsObject(commandName)
        return commandName == "fetch" or commandName == "hunt" or commandName == "track"
    end

    local function commandAllowsNoSpecificTarget(commandName)
        return commandName == "get_help"
    end

    local function getCommandTargetType(commandName)
        if commandName == "sic_em" then
            return "enemy"
        elseif commandName == "guard" or commandName == "get_help" then
            return "ally"
        end
        return nil
    end

    local function getSelectedCommandOptionValue(...)
        local option = inputState.selectedCommandOption
        local commandData = option and option.commandData
        for i = 1, select("#", ...) do
            local key = select(i, ...)
            if option and option[key] ~= nil then
                return option[key]
            end
            if commandData and commandData[key] ~= nil then
                return commandData[key]
            end
        end
        return nil
    end

    local function getSelectedCommandActionValue(action, ...)
        if not action or action.id ~= "command" then
            return nil
        end
        return getSelectedCommandOptionValue(...)
    end

    local function shallowCopyTable(value)
        if type(value) ~= "table" then
            return value
        end

        local copy = {}
        for key, item in pairs(value) do
            copy[key] = item
        end
        return copy
    end

    local function getAidTriggerActionId(trigger)
        if type(trigger) ~= "table" then
            return trigger
        end
        return trigger.action or trigger.type or trigger.actionType or trigger.id
    end

    local function getAidTriggerTargetAction()
        local trigger = inputState.selectedAidTrigger
        if not trigger or trigger.target or trigger.targetId then
            return nil
        end

        local option = inputState.selectedAidTriggerOption
        local triggerAction = option and option.aidTriggerAction
        if not triggerAction then
            triggerAction = action_registry.getAction(getAidTriggerActionId(trigger))
        end
        if not triggerAction or not triggerAction.requiresTarget then
            return nil
        end

        local targetAction = shallowCopyTable(triggerAction)
        targetAction.requiresTarget = true
        targetAction.targetType = targetAction.targetType or "any"
        return targetAction
    end

    local function recordAidTriggerTarget(target)
        local trigger = shallowCopyTable(inputState.selectedAidTrigger or {})
        trigger.target = target
        trigger.targetId = target and (target.id or target.name) or nil
        inputState.selectedAidTrigger = trigger
        inputState.selectedAidTriggerTarget = target
    end

    local function beginAidTriggerTargetSelection(aidedTarget)
        local targetAction = getAidTriggerTargetAction()
        if not targetAction then
            return false
        end

        local targets = getValidTargetsForAction(targetAction, aidedTarget or inputState.selectedEntity)
        if #targets == 0 then
            return false
        end

        inputState.awaitingTarget = false
        inputState.awaitingAidTriggerTarget = true
        inputState.availableAidTriggerTargets = targets
        inputState.selectedAidTarget = aidedTarget
        inputState.selectedAidTriggerTargetAction = targetAction

        print("[AID] Select trigger target (1-" .. #targets .. "), or press Space for any target:")
        for i, target in ipairs(targets) do
            local zoneInfo = target.zone and (" [" .. target.zone .. "]") or ""
            print("  " .. i .. ": " .. (target.name or target.id) .. zoneInfo)
        end
        return true
    end

    local function actionCardStaysInPlay(actionId)
        return actionId == "aid" or actionId == "aim" or actionId == "dodge" or
            actionId == "riposte" or actionId == "vigilance"
    end

    local function removePlayedCardFromHand(hand, entity, card, cardIndex, actionId)
        local keepInPlay = actionCardStaysInPlay(actionId)
        if keepInPlay and hand.takeCard then
            return hand:takeCard(entity, {
                index = cardIndex,
                card = card,
            })
        end
        if hand.discardCard then
            return hand:discardCard(entity, {
                index = cardIndex,
                card = card,
                reason = "action",
            })
        end

        local cards = hand:getHand(entity)
        local removed = table.remove(cards, cardIndex)
        if not keepInPlay and gameState.playerDeck then
            gameState.playerDeck:discard(card)
        end
        return removed, cardIndex, nil
    end

    local function clearCounterSpellPrompt()
        inputState.pendingCounterSpellInterrupt = nil
        inputState.counterSpellCandidateIndex = nil
        inputState.awaitingCounterSpellCard = false
    end

    local function clearAmbusherResistancePrompt()
        inputState.pendingAmbusherResistance = nil
        inputState.ambusherResistanceCandidateIndex = nil
        inputState.awaitingAmbusherResistanceChoice = false
    end

    local function clearWoundChoicePrompt()
        inputState.pendingWoundChoice = nil
        inputState.awaitingWoundChoice = false
        inputState.awaitingWoundTalentChoice = false
        inputState.awaitingBerserkergangChoice = false
        inputState.pendingBerserkergangTalentId = nil
    end

    local function clearAcrobatFallChoicePrompt()
        inputState.pendingAcrobatFallChoice = nil
        inputState.awaitingAcrobatFallChoice = false
    end

    local function normalizeTalentIdForPrompt(talentId)
        local normalized = tostring(talentId or ""):lower()
        normalized = normalized:gsub("[’']", "")
        normalized = normalized:gsub("[^%w]+", "_")
        normalized = normalized:gsub("^_+", ""):gsub("_+$", "")
        return normalized
    end

    local function isBerserkergangTalent(talentId)
        return normalizeTalentIdForPrompt(talentId) == "berserkergang"
    end

    local function getWoundChoiceLabel(choice)
        if choice == "armor" then
            return "Armor"
        elseif choice == "talent" then
            return "Talent"
        elseif choice == "staggered" then
            return "Staggered"
        elseif choice == "injured" then
            return "Injured"
        elseif choice == "deaths_door" then
            return "Death's Door"
        end
        return tostring(choice or "?")
    end

    local function getWoundChoicePromptText()
        local pending = inputState.pendingWoundChoice
        local entity = pending and pending.entity
        local entityName = entity and (entity.name or entity.id) or "Adventurer"
        if inputState.awaitingBerserkergangChoice then
            return "Berserkergang: R to enter rage, SPACE to take the Wound without rage"
        end
        if inputState.awaitingWoundTalentChoice then
            local talentParts = {}
            for i, talentChoice in ipairs((pending and pending.talentChoices) or {}) do
                talentParts[#talentParts + 1] = tostring(i) .. " " ..
                    tostring(talentChoice.name or talentChoice.id or "?")
            end
            return "Wound talent: choose for " .. entityName .. " - " .. table.concat(talentParts, ", ")
        end

        local parts = {}
        for i, choice in ipairs((pending and pending.choices) or {}) do
            parts[#parts + 1] = tostring(i) .. " " .. getWoundChoiceLabel(choice)
        end
        return "Wound: choose for " .. entityName .. " - " .. table.concat(parts, ", ")
    end

    local function setWoundChoicePrompt(data)
        if not data or not data.choices or #data.choices == 0 then
            clearWoundChoicePrompt()
            return
        end

        inputState.pendingWoundChoice = data
        inputState.awaitingWoundChoice = true
        inputState.awaitingWoundTalentChoice = false
        inputState.selectedCard = nil
        inputState.selectedCardIndex = nil
        inputState.selectedEntity = nil
        inputState.selectedAction = nil
        eventBus:emit("card_deselected", {})
        print("[WOUND] " .. getWoundChoicePromptText())
    end

    local function woundChoiceIsAvailable(choice)
        local pending = inputState.pendingWoundChoice
        for _, available in ipairs((pending and pending.choices) or {}) do
            if available == choice then
                return true
            end
        end
        return false
    end

    local function completeWoundChoicePrompt(choice, talentId, opts)
        local pending = inputState.pendingWoundChoice
        if not pending then
            clearWoundChoicePrompt()
            return false
        end
        if not woundChoiceIsAvailable(choice) then
            print("[WOUND] Choice unavailable. " .. getWoundChoicePromptText())
            return true
        end

        local completeData = {
            choice = choice,
            talentId = talentId,
            enterBerserkergang = opts and opts.enterBerserkergang,
            entity = pending.entity,
            action = pending.action,
            pendingWoundChoice = pending,
        }
        clearWoundChoicePrompt()
        eventBus:emit(events.EVENTS.WOUND_CHOICE_COMPLETE, completeData)
        return true
    end

    local function beginBerserkergangChoicePrompt(talentId)
        inputState.awaitingWoundTalentChoice = false
        inputState.awaitingBerserkergangChoice = true
        inputState.pendingBerserkergangTalentId = talentId
        print("[WOUND] " .. getWoundChoicePromptText())
        return true
    end

    local function handleBerserkergangChoiceKey(key)
        if not inputState.awaitingBerserkergangChoice then
            return false
        end

        local talentId = inputState.pendingBerserkergangTalentId
        if key == "r" then
            return completeWoundChoicePrompt("talent", talentId, {
                enterBerserkergang = true,
            })
        elseif key == "space" then
            return completeWoundChoicePrompt("talent", talentId, {
                enterBerserkergang = false,
            })
        elseif key == "escape" then
            inputState.awaitingBerserkergangChoice = false
            inputState.pendingBerserkergangTalentId = nil
            inputState.awaitingWoundTalentChoice = true
            print("[WOUND] " .. getWoundChoicePromptText())
            return true
        end

        print("[WOUND] " .. getWoundChoicePromptText())
        return true
    end

    local function beginWoundTalentChoicePrompt()
        local pending = inputState.pendingWoundChoice
        if not woundChoiceIsAvailable("talent") then
            return completeWoundChoicePrompt("talent")
        end
        local talentChoices = pending and pending.talentChoices or {}
        if #talentChoices == 1 then
            if isBerserkergangTalent(talentChoices[1].id) then
                return beginBerserkergangChoicePrompt(talentChoices[1].id)
            end
            return completeWoundChoicePrompt("talent", talentChoices[1].id)
        end
        if #talentChoices > 1 then
            inputState.awaitingWoundTalentChoice = true
            print("[WOUND] " .. getWoundChoicePromptText())
            return true
        end

        return completeWoundChoicePrompt("talent")
    end

    local function handleWoundTalentChoiceKey(key)
        local pending = inputState.pendingWoundChoice
        if not pending or not inputState.awaitingWoundTalentChoice then
            return false
        end

        if key == "escape" then
            inputState.awaitingWoundTalentChoice = false
            print("[WOUND] " .. getWoundChoicePromptText())
            return true
        end

        local index = tonumber(key)
        local talentChoice = index and pending.talentChoices and pending.talentChoices[index]
        if talentChoice then
            if isBerserkergangTalent(talentChoice.id) then
                return beginBerserkergangChoicePrompt(talentChoice.id)
            end
            return completeWoundChoicePrompt("talent", talentChoice.id)
        end

        print("[WOUND] " .. getWoundChoicePromptText())
        return true
    end

    local function handleWoundChoiceKey(key)
        if not inputState.pendingWoundChoice then
            return false
        end
        if inputState.awaitingBerserkergangChoice then
            return handleBerserkergangChoiceKey(key)
        end
        if inputState.awaitingWoundTalentChoice then
            return handleWoundTalentChoiceKey(key)
        end

        local pending = inputState.pendingWoundChoice
        local keyNum = tonumber(key)
        if keyNum and pending.choices and pending.choices[keyNum] then
            local selectedChoice = pending.choices[keyNum]
            if selectedChoice == "talent" then
                return beginWoundTalentChoicePrompt()
            end
            return completeWoundChoicePrompt(selectedChoice)
        end

        local choiceByKey = {
            a = "armor",
            t = "talent",
            s = "staggered",
            i = "injured",
            d = "deaths_door",
        }
        if choiceByKey[key] then
            if choiceByKey[key] == "talent" then
                return beginWoundTalentChoicePrompt()
            end
            return completeWoundChoicePrompt(choiceByKey[key])
        end

        print("[WOUND] " .. getWoundChoicePromptText())
        return true
    end

    local function getAcrobatFallChoicePromptText()
        local pending = inputState.pendingAcrobatFallChoice
        local entity = pending and pending.entity
        local entityName = entity and (entity.name or entity.id) or "Acrobat"
        local without = pending and pending.woundsWithoutAcrobat or "?"
        local with = pending and pending.woundsWithAcrobat or "?"
        return "Acrobat: R to spend Resolve with " .. entityName .. " (" ..
            tostring(without) .. " Wound(s) -> " .. tostring(with) ..
            "), SPACE to fall normally"
    end

    local function setAcrobatFallChoicePrompt(data)
        if not data or not data.entity then
            clearAcrobatFallChoicePrompt()
            return
        end

        inputState.pendingAcrobatFallChoice = data
        inputState.awaitingAcrobatFallChoice = true
        inputState.selectedCard = nil
        inputState.selectedCardIndex = nil
        inputState.selectedEntity = nil
        inputState.selectedAction = nil
        eventBus:emit("card_deselected", {})
        print("[ACROBAT] " .. getAcrobatFallChoicePromptText())
    end

    local function completeAcrobatFallChoicePrompt(spendResolve)
        local pending = inputState.pendingAcrobatFallChoice
        if not pending then
            clearAcrobatFallChoicePrompt()
            return false
        end

        local completeData = {
            spendResolve = spendResolve == true,
            entity = pending.entity,
            pendingAcrobatFallChoice = pending,
        }
        clearAcrobatFallChoicePrompt()
        eventBus:emit(events.EVENTS.ACROBAT_FALL_CHOICE_COMPLETE, completeData)
        return true
    end

    local function handleAcrobatFallChoiceKey(key)
        if not inputState.pendingAcrobatFallChoice then
            return false
        end
        if key == "r" then
            return completeAcrobatFallChoicePrompt(true)
        elseif key == "space" then
            return completeAcrobatFallChoicePrompt(false)
        end

        print("[ACROBAT] " .. getAcrobatFallChoicePromptText())
        return true
    end

    local function clearRetreatGroupTestPrompt()
        inputState.pendingRetreatGroupTest = nil
        inputState.retreatTestIndex = nil
        inputState.retreatTestCards = nil
        inputState.retreatFavorTarget = nil
        inputState.awaitingRetreatFavorChoice = false
    end

    local function getRetreatTesters()
        local pending = inputState.pendingRetreatGroupTest
        local request = pending and (pending.request or (pending.result and pending.result.groupTestRequest))
        return request and request.testers or {}
    end

    local function getRetreatTesterCard(cards, tester, index)
        if type(cards) ~= "table" or not tester then
            return nil
        end
        return cards[tester.role] or cards[tester.actorId] or cards[tester.actorName] or cards[index]
    end

    local function storeRetreatTesterCard(cards, tester, index, card)
        if type(cards) ~= "table" or not tester or not card then
            return
        end
        local key = tester.role or tester.actorId or tester.actorName or index
        cards[key] = card
    end

    local function firstMissingRetreatTesterIndex()
        local cards = inputState.retreatTestCards or {}
        for index, tester in ipairs(getRetreatTesters()) do
            if not getRetreatTesterCard(cards, tester, index) then
                return index
            end
        end
        return nil
    end

    local function getRetreatPromptTester()
        local testers = getRetreatTesters()
        local index = inputState.retreatTestIndex or firstMissingRetreatTesterIndex() or 1
        if index < 1 or index > #testers then
            index = firstMissingRetreatTesterIndex() or 1
        end
        inputState.retreatTestIndex = index
        return testers[index], index
    end

    local function getRetreatGroupTestPromptText()
        local pending = inputState.pendingRetreatGroupTest
        local request = pending and (pending.request or (pending.result and pending.result.groupTestRequest)) or {}
        local testers = request.testers or {}
        if inputState.awaitingRetreatFavorChoice then
            local parts = {}
            for i, tester in ipairs(testers) do
                parts[#parts + 1] = tostring(i) .. " " .. tostring(tester.actorName or tester.actorId or tester.role)
            end
            return "Retreat: choose clever tactic favor target - " .. table.concat(parts, ", ")
        end

        local tester, index = getRetreatPromptTester()
        local actor = tester and tester.actor
        local actorName = tester and (tester.actorName or tester.actorId or tester.role) or "adventurer"
        local cards = actor and gameState.playerHand and gameState.playerHand:getHand(actor) or {}
        return "Retreat: Q/W/E/R Pentacles test card for " .. actorName ..
            " (" .. tostring(index or 1) .. "/" .. tostring(#testers) .. ", " .. tostring(#cards) .. " cards)"
    end

    local function setRetreatGroupTestPrompt(data)
        local request = data and (data.request or (data.result and data.result.groupTestRequest))
        if not request or not request.testers or #request.testers == 0 then
            clearRetreatGroupTestPrompt()
            return
        end

        inputState.pendingRetreatGroupTest = data
        inputState.retreatTestCards = shallowCopyTable((data.action and data.action.retreatTestCards) or
            data.retreatTestCards or data.groupTestCards or {})
        inputState.retreatFavorTarget = data.retreatFavorTarget or data.favorTarget or
            (data.action and data.action.retreatFavorTarget) or request.favorTarget
        inputState.awaitingRetreatFavorChoice = request.favorChoiceRequired == true and
            inputState.retreatFavorTarget == nil
        inputState.retreatTestIndex = firstMissingRetreatTesterIndex()

        if not inputState.awaitingRetreatFavorChoice and not inputState.retreatTestIndex then
            local completeData = {
                action = data.action,
                retreatTestCards = inputState.retreatTestCards,
                retreatFavorTarget = inputState.retreatFavorTarget,
            }
            clearRetreatGroupTestPrompt()
            eventBus:emit(events.EVENTS.RETREAT_GROUP_TEST_COMPLETE, completeData)
            return
        end

        inputState.selectedCard = nil
        inputState.selectedCardIndex = nil
        inputState.selectedEntity = nil
        inputState.selectedAction = nil
        eventBus:emit("card_deselected", {})
        print("[RETREAT] " .. getRetreatGroupTestPromptText())
    end

    local function completeRetreatGroupTestPrompt()
        local pending = inputState.pendingRetreatGroupTest
        if not pending then
            clearRetreatGroupTestPrompt()
            return false
        end

        local completeData = {
            action = pending.action,
            retreatTestCards = inputState.retreatTestCards or {},
            retreatFavorTarget = inputState.retreatFavorTarget,
        }
        clearRetreatGroupTestPrompt()
        eventBus:emit(events.EVENTS.RETREAT_GROUP_TEST_COMPLETE, completeData)
        return true
    end

    local function handleRetreatGroupTestKey(key)
        if not inputState.pendingRetreatGroupTest then
            return false
        end

        if inputState.awaitingRetreatFavorChoice then
            local index = tonumber(key)
            local tester = index and getRetreatTesters()[index]
            if tester then
                inputState.retreatFavorTarget = tester.role or tester.actorId or tester.actorName
                inputState.awaitingRetreatFavorChoice = false
                inputState.retreatTestIndex = firstMissingRetreatTesterIndex()
                if not inputState.retreatTestIndex then
                    return completeRetreatGroupTestPrompt()
                end
                print("[RETREAT] " .. getRetreatGroupTestPromptText())
            else
                print("[RETREAT] " .. getRetreatGroupTestPromptText())
            end
            return true
        end

        local cardKeys = { q = 1, w = 2, e = 3, r = 4 }
        local cardIndex = cardKeys[key]
        if not cardIndex then
            print("[RETREAT] " .. getRetreatGroupTestPromptText())
            return true
        end

        local tester = getRetreatPromptTester()
        local actor = tester and tester.actor
        if not actor then
            clearRetreatGroupTestPrompt()
            return false
        end

        local hand = gameState.playerHand
        local cards = hand and hand:getHand(actor) or {}
        if cardIndex < 1 or cardIndex > #cards then
            print("[RETREAT] No card at position " .. tostring(cardIndex))
            return true
        end

        local card = cards[cardIndex]
        local removed = nil
        if hand and hand.discardCard then
            removed = hand:discardCard(actor, {
                index = cardIndex,
                card = card,
                reason = "retreat_group_test",
            })
        end
        storeRetreatTesterCard(inputState.retreatTestCards, tester, inputState.retreatTestIndex, removed or card)
        inputState.retreatTestIndex = firstMissingRetreatTesterIndex()
        if not inputState.retreatTestIndex then
            return completeRetreatGroupTestPrompt()
        end

        print("[RETREAT] " .. getRetreatGroupTestPromptText())
        return true
    end

    local function clearHeavyMetalMachinePrompt()
        inputState.pendingHeavyMetalMachineInterrupt = nil
        inputState.heavyMetalMachineCandidateIndex = nil
        inputState.awaitingHeavyMetalMachineCard = false
    end

    local function clearAegisPrompt()
        inputState.pendingAegisElection = nil
        inputState.aegisCandidateIndex = nil
        inputState.awaitingAegisChoice = false
    end

    local function getAmbusherResistancePromptCandidate()
        local pending = inputState.pendingAmbusherResistance
        local candidates = pending and pending.candidates or nil
        if not candidates or #candidates == 0 then
            return nil, nil
        end

        local index = inputState.ambusherResistanceCandidateIndex or 1
        if index < 1 or index > #candidates then
            index = 1
            inputState.ambusherResistanceCandidateIndex = index
        end

        return candidates[index], index
    end

    local function getAmbusherResistancePromptText()
        local candidate = getAmbusherResistancePromptCandidate()
        local actor = candidate and candidate.actor
        local actorName = actor and (actor.name or actor.id) or "Ambusher"
        local pending = inputState.pendingAmbusherResistance
        local candidateCount = pending and pending.candidates and #pending.candidates or 0
        local chooser = candidateCount > 1 and ", 1-" .. candidateCount .. " to choose Ambusher" or ""
        return "Ambusher: R to spend Resolve with " .. actorName ..
            " and cancel surprise" .. chooser .. ", SPACE to skip"
    end

    local function setAmbusherResistancePrompt(data)
        if not data or not data.candidates or #data.candidates == 0 then
            clearAmbusherResistancePrompt()
            return
        end

        inputState.pendingAmbusherResistance = data
        inputState.ambusherResistanceCandidateIndex = 1
        inputState.awaitingAmbusherResistanceChoice = true
        inputState.selectedCard = nil
        inputState.selectedCardIndex = nil
        inputState.selectedEntity = nil
        inputState.selectedAction = nil
        eventBus:emit("card_deselected", {})
        print("[AMBUSHER] " .. getAmbusherResistancePromptText())
    end

    local function selectAmbusherResistanceCandidate(index)
        local pending = inputState.pendingAmbusherResistance
        if not pending or not pending.candidates or not pending.candidates[index] then
            return false
        end

        inputState.ambusherResistanceCandidateIndex = index
        local candidate = pending.candidates[index]
        local actor = candidate.actor
        print("[AMBUSHER] " .. (actor and (actor.name or actor.id) or "Ambusher") ..
            " selected. Press R to spend Resolve and cancel surprise.")
        return true
    end

    local function electAmbusherResistancePrompt()
        local challengeController = gameState.challengeController
        local candidate = getAmbusherResistancePromptCandidate()
        local actor = candidate and candidate.actor
        if not inputState.pendingAmbusherResistance or not actor then
            clearAmbusherResistancePrompt()
            return false
        end

        local ok, resultOrReason = challengeController:electAmbusherResistance(actor)
        if not ok then
            print("[AMBUSHER] Resistance failed: " .. tostring(resultOrReason))
            return true
        end

        print("[AMBUSHER] " .. (actor.name or actor.id) .. " raises the hue and cry.")
        clearAmbusherResistancePrompt()
        return true
    end

    local function skipAmbusherResistancePrompt()
        local challengeController = gameState.challengeController
        if not inputState.pendingAmbusherResistance then
            clearAmbusherResistancePrompt()
            return false
        end

        local ok, err = challengeController:skipAmbusherResistance()
        if not ok then
            print("[AMBUSHER] Skip failed: " .. tostring(err))
            return true
        end

        print("[AMBUSHER] No hue and cry raised.")
        clearAmbusherResistancePrompt()
        return true
    end

    local function handleAmbusherResistanceKey(key)
        if not inputState.pendingAmbusherResistance then
            return false
        end

        local pending = inputState.pendingAmbusherResistance
        local keyNum = tonumber(key)
        if keyNum and pending.candidates and #pending.candidates > 1 then
            if not selectAmbusherResistanceCandidate(keyNum) then
                print("[AMBUSHER] No Ambusher at position " .. tostring(keyNum))
            end
            return true
        end

        if key == "r" or key == "return" then
            return electAmbusherResistancePrompt()
        end
        if key == "space" or key == "escape" then
            return skipAmbusherResistancePrompt()
        end

        print("[AMBUSHER] " .. getAmbusherResistancePromptText())
        return true
    end

    local function handleAmbusherResistanceMouse(x, y)
        if not inputState.pendingAmbusherResistance then
            return false
        end

        local plate = getPlateAt(x, y)
        local candidates = inputState.pendingAmbusherResistance.candidates or {}
        if plate and plate.entity then
            for i, candidate in ipairs(candidates) do
                local actor = candidate.actor
                if actor and (actor == plate.entity or actor.id == plate.entity.id) then
                    selectAmbusherResistanceCandidate(i)
                    return true
                end
            end
        end

        return true
    end

    local function getCounterSpellPromptCandidate()
        local pending = inputState.pendingCounterSpellInterrupt
        local candidates = pending and pending.candidates or nil
        if not candidates or #candidates == 0 then
            return nil, nil
        end

        local index = inputState.counterSpellCandidateIndex or 1
        if index < 1 or index > #candidates then
            index = 1
            inputState.counterSpellCandidateIndex = index
        end

        return candidates[index], index
    end

    local function getCounterSpellPromptText()
        local candidate = getCounterSpellPromptCandidate()
        local counterer = candidate and candidate.actor
        local pending = inputState.pendingCounterSpellInterrupt
        local caster = pending and pending.spellCaster
        local countererName = counterer and (counterer.name or counterer.id) or "counterspeller"
        local casterName = caster and (caster.name or caster.id) or "the caster"
        local candidateCount = pending and pending.candidates and #pending.candidates or 0
        local chooser = candidateCount > 1 and ", 1-" .. candidateCount .. " to choose counterspeller" or ""
        return "Counter-spell: Q/W/E/R Wands card for " .. countererName ..
            " against " .. casterName .. chooser .. ", SPACE to skip"
    end

    local function setCounterSpellPrompt(data)
        if not data or not data.candidates or #data.candidates == 0 then
            clearCounterSpellPrompt()
            return
        end

        inputState.pendingCounterSpellInterrupt = data
        inputState.counterSpellCandidateIndex = 1
        inputState.awaitingCounterSpellCard = true
        inputState.selectedCard = nil
        inputState.selectedCardIndex = nil
        inputState.selectedEntity = nil
        inputState.selectedAction = nil
        eventBus:emit("card_deselected", {})
        print("[COUNTER-SPELL] " .. getCounterSpellPromptText())
    end

    local function selectCounterSpellCandidate(index)
        local pending = inputState.pendingCounterSpellInterrupt
        if not pending or not pending.candidates or not pending.candidates[index] then
            return false
        end

        inputState.counterSpellCandidateIndex = index
        local candidate = pending.candidates[index]
        local actor = candidate.actor
        print("[COUNTER-SPELL] " .. (actor and (actor.name or actor.id) or "Counterspeller") ..
            " selected. Choose a Wands card.")
        return true
    end

    local function playCounterSpellPromptCard(cardIndex)
        local challengeController = gameState.challengeController
        local hand = gameState.playerHand
        local pending = inputState.pendingCounterSpellInterrupt
        local candidate = getCounterSpellPromptCandidate()
        local entity = candidate and candidate.actor
        if not pending or not entity then
            clearCounterSpellPrompt()
            return false
        end

        local cards = hand:getHand(entity)
        if cardIndex < 1 or cardIndex > #cards then
            print("[COUNTER-SPELL] No card at position " .. tostring(cardIndex))
            return true
        end

        local card = cards[cardIndex]
        local actionSuit = action_registry.cardSuitToActionSuit(card.suit)
        if actionSuit ~= action_registry.SUITS.WANDS then
            print("[COUNTER-SPELL] Counter-spell requires a Wands card.")
            return true
        end

        local played, resultOrReason = challengeController:playCounterSpellInterrupt(
            entity,
            card,
            pending.incomingAction
        )
        if not played then
            print("[COUNTER-SPELL] Interrupt failed: " .. tostring(resultOrReason))
            return true
        end

        removePlayedCardFromHand(hand, entity, card, cardIndex, "counter_spell")
        clearCounterSpellPrompt()
        return true
    end

    local function skipCounterSpellPrompt()
        local challengeController = gameState.challengeController
        local pending = inputState.pendingCounterSpellInterrupt
        if not pending then
            clearCounterSpellPrompt()
            return false
        end

        local ok, err = challengeController:skipCounterSpellInterrupt(pending.incomingAction)
        if not ok then
            print("[COUNTER-SPELL] Skip failed: " .. tostring(err))
            return true
        end

        print("[COUNTER-SPELL] No counter-spell played.")
        clearCounterSpellPrompt()
        return true
    end

    local function handleCounterSpellInterruptKey(key)
        if not inputState.pendingCounterSpellInterrupt then
            return false
        end

        if key == "space" or key == "escape" then
            skipCounterSpellPrompt()
            return true
        end

        local pending = inputState.pendingCounterSpellInterrupt
        local keyNum = tonumber(key)
        if keyNum and pending.candidates and #pending.candidates > 1 then
            if not selectCounterSpellCandidate(keyNum) then
                print("[COUNTER-SPELL] No counterspeller at position " .. tostring(keyNum))
            end
            return true
        end

        if key == "h" then
            local candidate = getCounterSpellPromptCandidate()
            local entity = candidate and candidate.actor
            local hand = gameState.playerHand
            local cards = entity and hand:getHand(entity) or {}
            print("[HAND] " .. (entity and (entity.name or entity.id) or "Counterspeller") .. "'s cards:")
            for i, card in ipairs(cards) do
                local keyLetter = ({ "Q", "W", "E", "R" })[i]
                local suitName = hand.getSuitName and hand:getSuitName(card.suit) or tostring(card.suit)
                print("  " .. tostring(keyLetter or i) .. ": " .. (card.name or "Card") ..
                    " (" .. suitName .. ", " .. tostring(card.value or "?") .. ")")
            end
            return true
        end

        local cardKeys = { q = 1, w = 2, e = 3, r = 4 }
        if cardKeys[key] then
            playCounterSpellPromptCard(cardKeys[key])
            return true
        end

        print("[COUNTER-SPELL] " .. getCounterSpellPromptText())
        return true
    end

    local function handleCounterSpellInterruptMouse(x, y)
        if not inputState.pendingCounterSpellInterrupt then
            return false
        end

        local candidate = getCounterSpellPromptCandidate()
        local entity = candidate and candidate.actor
        if entity then
            local cardIndex = getHandCardIndexAt(x, y, entity)
            if cardIndex then
                playCounterSpellPromptCard(cardIndex)
                return true
            end
        end

        return true
    end

    local function getHeavyMetalMachinePromptCandidate()
        local pending = inputState.pendingHeavyMetalMachineInterrupt
        local candidates = pending and pending.candidates or nil
        if not candidates or #candidates == 0 then
            return nil, nil
        end

        local index = inputState.heavyMetalMachineCandidateIndex or 1
        if index < 1 or index > #candidates then
            index = 1
            inputState.heavyMetalMachineCandidateIndex = index
        end

        return candidates[index], index
    end

    local function getHeavyMetalMachinePromptText()
        local candidate = getHeavyMetalMachinePromptCandidate()
        local defender = candidate and candidate.actor
        local pending = inputState.pendingHeavyMetalMachineInterrupt
        local incomingActor = pending and pending.incomingActor
        local defenderName = defender and (defender.name or defender.id) or "armored adventurer"
        local attackerName = incomingActor and (incomingActor.name or incomingActor.id) or "the incoming action"
        local candidateCount = pending and pending.candidates and #pending.candidates or 0
        local chooser = candidateCount > 1 and ", 1-" .. candidateCount .. " to choose defender" or ""
        return "Heavy Metal Machine: Q/W/E/R any card for " .. defenderName ..
            " against " .. attackerName .. chooser .. ", SPACE to skip"
    end

    local function setHeavyMetalMachinePrompt(data)
        if not data or not data.candidates or #data.candidates == 0 then
            clearHeavyMetalMachinePrompt()
            return
        end

        inputState.pendingHeavyMetalMachineInterrupt = data
        inputState.heavyMetalMachineCandidateIndex = 1
        inputState.awaitingHeavyMetalMachineCard = true
        inputState.selectedCard = nil
        inputState.selectedCardIndex = nil
        inputState.selectedEntity = nil
        inputState.selectedAction = nil
        eventBus:emit("card_deselected", {})
        print("[HEAVY METAL MACHINE] " .. getHeavyMetalMachinePromptText())
    end

    local function selectHeavyMetalMachineCandidate(index)
        local pending = inputState.pendingHeavyMetalMachineInterrupt
        if not pending or not pending.candidates or not pending.candidates[index] then
            return false
        end

        inputState.heavyMetalMachineCandidateIndex = index
        local candidate = pending.candidates[index]
        local actor = candidate.actor
        print("[HEAVY METAL MACHINE] " .. (actor and (actor.name or actor.id) or "Defender") ..
            " selected. Choose any card.")
        return true
    end

    local function playHeavyMetalMachinePromptCard(cardIndex)
        local challengeController = gameState.challengeController
        local hand = gameState.playerHand
        local pending = inputState.pendingHeavyMetalMachineInterrupt
        local candidate = getHeavyMetalMachinePromptCandidate()
        local entity = candidate and candidate.actor
        if not pending or not entity then
            clearHeavyMetalMachinePrompt()
            return false
        end

        local cards = hand:getHand(entity)
        if cardIndex < 1 or cardIndex > #cards then
            print("[HEAVY METAL MACHINE] No card at position " .. tostring(cardIndex))
            return true
        end

        local card = cards[cardIndex]
        local played, resultOrReason = challengeController:playHeavyMetalMachineInterrupt(
            entity,
            card,
            pending.incomingAction
        )
        if not played then
            print("[HEAVY METAL MACHINE] Interrupt failed: " .. tostring(resultOrReason))
            return true
        end

        removePlayedCardFromHand(hand, entity, card, cardIndex, "heavy_metal_machine")
        clearHeavyMetalMachinePrompt()
        return true
    end

    local function skipHeavyMetalMachinePrompt()
        local challengeController = gameState.challengeController
        local pending = inputState.pendingHeavyMetalMachineInterrupt
        if not pending then
            clearHeavyMetalMachinePrompt()
            return false
        end

        local ok, err = challengeController:skipHeavyMetalMachineInterrupt(pending.incomingAction)
        if not ok then
            print("[HEAVY METAL MACHINE] Skip failed: " .. tostring(err))
            return true
        end

        print("[HEAVY METAL MACHINE] No armor boost played.")
        clearHeavyMetalMachinePrompt()
        return true
    end

    local function handleHeavyMetalMachineInterruptKey(key)
        if not inputState.pendingHeavyMetalMachineInterrupt then
            return false
        end

        if key == "space" or key == "escape" then
            skipHeavyMetalMachinePrompt()
            return true
        end

        local pending = inputState.pendingHeavyMetalMachineInterrupt
        local keyNum = tonumber(key)
        if keyNum and pending.candidates and #pending.candidates > 1 then
            if not selectHeavyMetalMachineCandidate(keyNum) then
                print("[HEAVY METAL MACHINE] No defender at position " .. tostring(keyNum))
            end
            return true
        end

        if key == "h" then
            local candidate = getHeavyMetalMachinePromptCandidate()
            local entity = candidate and candidate.actor
            local hand = gameState.playerHand
            local cards = entity and hand:getHand(entity) or {}
            print("[HAND] " .. (entity and (entity.name or entity.id) or "Defender") .. "'s cards:")
            for i, card in ipairs(cards) do
                local keyLetter = ({ "Q", "W", "E", "R" })[i]
                local suitName = hand.getSuitName and hand:getSuitName(card.suit) or tostring(card.suit)
                print("  " .. tostring(keyLetter or i) .. ": " .. (card.name or "Card") ..
                    " (" .. suitName .. ", " .. tostring(card.value or "?") .. ")")
            end
            return true
        end

        local cardKeys = { q = 1, w = 2, e = 3, r = 4 }
        if cardKeys[key] then
            playHeavyMetalMachinePromptCard(cardKeys[key])
            return true
        end

        print("[HEAVY METAL MACHINE] " .. getHeavyMetalMachinePromptText())
        return true
    end

    local function handleHeavyMetalMachineInterruptMouse(x, y)
        if not inputState.pendingHeavyMetalMachineInterrupt then
            return false
        end

        local candidate = getHeavyMetalMachinePromptCandidate()
        local entity = candidate and candidate.actor
        if entity then
            local cardIndex = getHandCardIndexAt(x, y, entity)
            if cardIndex then
                playHeavyMetalMachinePromptCard(cardIndex)
                return true
            end
        end

        return true
    end

    local function getAegisPromptCandidate()
        local pending = inputState.pendingAegisElection
        local candidates = pending and pending.candidates or nil
        if not candidates or #candidates == 0 then
            return nil, nil
        end

        local index = inputState.aegisCandidateIndex or 1
        if index < 1 or index > #candidates then
            index = 1
            inputState.aegisCandidateIndex = index
        end

        return candidates[index], index
    end

    local function getAegisPromptText()
        local candidate = getAegisPromptCandidate()
        local defender = candidate and candidate.actor
        local pending = inputState.pendingAegisElection
        local incomingActor = pending and pending.incomingActor
        local defenderName = defender and (defender.name or defender.id) or "shield bearer"
        local attackerName = incomingActor and (incomingActor.name or incomingActor.id) or "the incoming effect"
        local shieldName = candidate and candidate.shield and candidate.shield.name or "shield"
        local candidateCount = pending and pending.candidates and #pending.candidates or 0
        local chooser = candidateCount > 1 and ", 1-" .. candidateCount .. " to choose defender" or ""
        return "Aegis: A to Notch " .. shieldName .. " for " .. defenderName ..
            " against " .. attackerName .. chooser .. ", SPACE to skip"
    end

    local function setAegisPrompt(data)
        if not data or not data.candidates or #data.candidates == 0 then
            clearAegisPrompt()
            return
        end

        inputState.pendingAegisElection = data
        inputState.aegisCandidateIndex = 1
        inputState.awaitingAegisChoice = true
        inputState.selectedCard = nil
        inputState.selectedCardIndex = nil
        inputState.selectedEntity = nil
        inputState.selectedAction = nil
        eventBus:emit("card_deselected", {})
        print("[AEGIS] " .. getAegisPromptText())
    end

    local function selectAegisCandidate(index)
        local pending = inputState.pendingAegisElection
        if not pending or not pending.candidates or not pending.candidates[index] then
            return false
        end

        inputState.aegisCandidateIndex = index
        local candidate = pending.candidates[index]
        local actor = candidate.actor
        print("[AEGIS] " .. (actor and (actor.name or actor.id) or "Shield bearer") ..
            " selected. Press A to Notch a shield if the effect lands.")
        return true
    end

    local function playAegisPrompt()
        local challengeController = gameState.challengeController
        local pending = inputState.pendingAegisElection
        local candidate = getAegisPromptCandidate()
        local entity = candidate and candidate.actor
        if not pending or not entity then
            clearAegisPrompt()
            return false
        end

        local ok, resultOrReason = challengeController:electAegisForIncoming(entity, pending.incomingAction)
        if not ok then
            print("[AEGIS] Election failed: " .. tostring(resultOrReason))
            return true
        end

        if challengeController.pendingAegisElection then
            setAegisPrompt(challengeController.pendingAegisElection)
        else
            clearAegisPrompt()
        end
        return true
    end

    local function skipAegisPrompt()
        local challengeController = gameState.challengeController
        local pending = inputState.pendingAegisElection
        if not pending then
            clearAegisPrompt()
            return false
        end

        local ok, err = challengeController:skipAegisElection(pending.incomingAction)
        if not ok then
            print("[AEGIS] Skip failed: " .. tostring(err))
            return true
        end

        print("[AEGIS] No shield Notch elected.")
        clearAegisPrompt()
        return true
    end

    local function handleAegisKey(key)
        if not inputState.pendingAegisElection then
            return false
        end

        local pending = inputState.pendingAegisElection
        local keyNum = tonumber(key)
        if keyNum and pending.candidates and #pending.candidates > 1 then
            if not selectAegisCandidate(keyNum) then
                print("[AEGIS] No shield bearer at position " .. tostring(keyNum))
            end
            return true
        end

        if key == "a" or key == "return" then
            return playAegisPrompt()
        end
        if key == "space" or key == "escape" then
            return skipAegisPrompt()
        end

        print("[AEGIS] " .. getAegisPromptText())
        return true
    end

    local function handleAegisMouse(x, y)
        if not inputState.pendingAegisElection then
            return false
        end

        local plate = getPlateAt(x, y)
        local candidates = inputState.pendingAegisElection.candidates or {}
        if plate and plate.entity then
            for i, candidate in ipairs(candidates) do
                local actor = candidate.actor
                if actor and (actor == plate.entity or actor.id == plate.entity.id) then
                    selectAegisCandidate(i)
                    return true
                end
            end
        end

        return true
    end

    local function clearQuickInterruptPrompt()
        inputState.awaitingQuickInterruptActor = false
        inputState.quickInterruptCandidates = nil
        inputState.quickInterruptActor = nil
        inputState.quickInterruptActive = false
    end

    local function isQuickInterruptCard(card)
        return card and action_registry.cardSuitToActionSuit(card.suit) == action_registry.SUITS.PENTACLES
    end

    local function getQuickInterruptCandidates()
        local challengeController = gameState.challengeController
        local hand = gameState.playerHand
        if not challengeController or not hand then
            return {}
        end

        local state = challengeController:getState()
        if state ~= "count_up" and state ~= "awaiting_action" and state ~= "minor_window" then
            return {}
        end

        local candidates = {}
        local pcs = gameState.guild or challengeController.pcs or {}
        for _, pc in ipairs(pcs) do
            local cards = hand:getHand(pc)
            local firstPentacles = nil
            for _, card in ipairs(cards or {}) do
                if isQuickInterruptCard(card) then
                    firstPentacles = card
                    break
                end
            end

            if firstPentacles then
                local ok = challengeController:canUseQuickInterrupt(pc, firstPentacles, { type = "dash" })
                if ok then
                    candidates[#candidates + 1] = pc
                end
            end
        end

        return candidates
    end

    local function selectQuickInterruptActor(actor)
        if not actor then
            return false
        end

        inputState.awaitingQuickInterruptActor = false
        inputState.quickInterruptActor = actor
        inputState.quickInterruptActive = true
        inputState.selectedCard = nil
        inputState.selectedCardIndex = nil
        inputState.selectedEntity = actor
        inputState.selectedAction = nil
        eventBus:emit("card_deselected", {})
        print("[QUICK!] Select a Pentacles card for " .. (actor.name or actor.id) .. " (Q/W/E/R).")
        return true
    end

    local function beginQuickInterruptPrompt()
        local candidates = getQuickInterruptCandidates()
        if #candidates == 0 then
            print("[QUICK!] No eligible light/no-armor Quick! adventurer has a Pentacles card.")
            return true
        end

        inputState.quickInterruptCandidates = candidates
        inputState.awaitingQuickInterruptActor = #candidates > 1
        inputState.quickInterruptActive = true

        if #candidates == 1 then
            return selectQuickInterruptActor(candidates[1])
        end

        eventBus:emit("card_deselected", {})
        print("[QUICK!] Select a Quick! adventurer (1-" .. #candidates .. "):")
        for i, actor in ipairs(candidates) do
            print("  " .. i .. ": " .. (actor.name or actor.id))
        end
        return true
    end

    local function selectQuickInterruptCard(cardIndex)
        local actor = inputState.quickInterruptActor
        local hand = gameState.playerHand
        if not actor then
            print("[QUICK!] Select a Quick! adventurer first.")
            return true
        end

        local cards = hand:getHand(actor)
        if cardIndex < 1 or cardIndex > #cards then
            print("[QUICK!] No card at position " .. tostring(cardIndex))
            return true
        end

        local card = cards[cardIndex]
        if not isQuickInterruptCard(card) then
            print("[QUICK!] Quick! requires a Pentacles card.")
            return true
        end

        inputState.selectedCard = card
        inputState.selectedCardIndex = cardIndex
        inputState.selectedEntity = actor
        inputState.selectedAction = nil
        inputState.quickInterruptActive = true

        eventBus:emit("card_selected", {
            card = card,
            entity = actor,
            isPrimaryTurn = true,
            cardIndex = cardIndex,
            quickInterrupt = true,
        })
        print("[QUICK!] " .. (actor.name or actor.id) ..
            " selected " .. (card.name or "a Pentacles card") .. " - choose a Pentacles action.")
        return true
    end

    local function handleQuickInterruptKey(key)
        if not (inputState.awaitingQuickInterruptActor or inputState.quickInterruptActor) then
            return false
        end

        if key == "escape" then
            clearQuickInterruptPrompt()
            resetCombatInputState()
            eventBus:emit("card_deselected", {})
            print("[QUICK!] Selection cancelled.")
            return true
        end

        if inputState.awaitingQuickInterruptActor then
            local index = tonumber(key)
            local candidates = inputState.quickInterruptCandidates or {}
            if index and candidates[index] then
                selectQuickInterruptActor(candidates[index])
            else
                print("[QUICK!] Select a Quick! adventurer (1-" .. #candidates .. ").")
            end
            return true
        end

        if key == "h" then
            local actor = inputState.quickInterruptActor
            local hand = gameState.playerHand
            local cards = actor and hand:getHand(actor) or {}
            print("[HAND] " .. (actor and (actor.name or actor.id) or "Quick! adventurer") .. "'s cards:")
            for i, card in ipairs(cards) do
                local keyLetter = ({ "Q", "W", "E", "R" })[i]
                local suitName = hand.getSuitName and hand:getSuitName(card.suit) or tostring(card.suit)
                print("  " .. tostring(keyLetter or i) .. ": " .. (card.name or "Card") ..
                    " (" .. suitName .. ", " .. tostring(card.value or "?") .. ")")
            end
            return true
        end

        local cardKeys = { q = 1, w = 2, e = 3, r = 4 }
        if cardKeys[key] then
            return selectQuickInterruptCard(cardKeys[key])
        end

        print("[QUICK!] Select a Pentacles card (Q/W/E/R), or ESC to cancel.")
        return true
    end

    local function handleQuickInterruptMouse(x, y)
        if not (inputState.awaitingQuickInterruptActor or inputState.quickInterruptActor) then
            return false
        end

        if inputState.awaitingQuickInterruptActor then
            local plate = getPlateAt(x, y)
            local candidates = inputState.quickInterruptCandidates or {}
            if plate and plate.entity then
                for _, actor in ipairs(candidates) do
                    if actor == plate.entity or actor.id == plate.entity.id then
                        selectQuickInterruptActor(actor)
                        return true
                    end
                end
            end
            return true
        end

        local actor = inputState.quickInterruptActor
        if actor then
            local cardIndex = getHandCardIndexAt(x, y, actor)
            if cardIndex then
                selectQuickInterruptCard(cardIndex)
                return true
            end
        end

        return true
    end

    local function clearCounselPrompt()
        inputState.counselActive = false
        inputState.awaitingCounselActor = false
        inputState.awaitingCounselCard = false
        inputState.awaitingCounselAction = false
        inputState.awaitingCounselTarget = false
        inputState.awaitingCounselResolveChoice = false
        inputState.counselCandidates = nil
        inputState.counselActor = nil
        inputState.counselCard = nil
        inputState.counselCardIndex = nil
        inputState.counselActionOptions = nil
        inputState.counselAction = nil
        inputState.counselTargetCandidates = nil
        inputState.counselTarget = nil
    end

    local function getCounselCandidates()
        local challengeController = gameState.challengeController
        local hand = gameState.playerHand
        if not challengeController or not hand then
            return {}
        end

        local state = challengeController:getState()
        if state == "idle" or state == "ending" or state == "pre_round" then
            return {}
        end

        local round = challengeController.getCurrentRound and challengeController:getCurrentRound() or
            challengeController.currentRound or 0
        local candidates = {}
        local pcs = gameState.guild or challengeController.pcs or {}
        for _, pc in ipairs(pcs) do
            local cards = hand:getHand(pc)
            if entityHasUsableTalent(pc, "counsel") and pc.counselUsedRound ~= round and #cards > 0 then
                candidates[#candidates + 1] = pc
            end
        end
        return candidates
    end

    local function getCounselTargets(counselor)
        local targets = {}
        local challengeController = gameState.challengeController
        local pcs = gameState.guild or challengeController.pcs or {}
        for _, pc in ipairs(pcs) do
            if pc and pc.isPC and counselor and pc.id ~= counselor.id then
                targets[#targets + 1] = pc
            end
        end
        return targets
    end

    local function getCounselActionOptions(card)
        local suit = card and action_registry.cardSuitToActionSuit(card.suit)
        if not suit or suit == action_registry.SUITS.MISC then
            return {}
        end

        local actions = action_registry.getActionsForSuit(suit, {
            challengeOnly = true,
            commandBoardOnly = true,
        })
        local options = {}
        for _, action in ipairs(actions or {}) do
            if action.suit == suit then
                options[#options + 1] = action
            end
        end
        return options
    end

    local function promptCounselActions()
        local options = inputState.counselActionOptions or {}
        print("[COUNSEL] Choose advised action (1-" .. #options .. "):")
        for i, action in ipairs(options) do
            print("  " .. i .. ": " .. (action.name or action.id))
        end
    end

    local function promptCounselTargets()
        local targets = inputState.counselTargetCandidates or {}
        print("[COUNSEL] Choose recipient (1-" .. #targets .. "):")
        for i, target in ipairs(targets) do
            print("  " .. i .. ": " .. (target.name or target.id))
        end
    end

    local function completeCounselPrompt(spendResolve)
        local challengeController = gameState.challengeController
        local hand = gameState.playerHand
        local counselor = inputState.counselActor
        local target = inputState.counselTarget
        local card = inputState.counselCard
        local action = inputState.counselAction
        local cardIndex = inputState.counselCardIndex

        local ok, detail = challengeController:resolveCounsel(counselor, target, card, action and action.id, {
            playerHand = hand,
            cardIndex = cardIndex,
            spendResolve = spendResolve == true,
        })
        if not ok then
            print("[COUNSEL] Counsel failed: " .. tostring(detail))
            clearCounselPrompt()
            return true
        end

        local interruptText = detail.interrupt and " as an interrupt" or ""
        print("[COUNSEL] " .. (counselor.name or counselor.id) .. " gives " ..
            (card.name or "a card") .. " to " .. (target.name or target.id) ..
            " for " .. (action.name or action.id) .. interruptText .. ".")
        clearCounselPrompt()
        eventBus:emit("card_deselected", {})
        return true
    end

    local function advanceCounselAfterTarget(target)
        inputState.counselTarget = target
        inputState.awaitingCounselTarget = false
        inputState.awaitingCounselResolveChoice = true

        local counselor = inputState.counselActor
        if not counselor or (counselor.resolve or 0) <= 0 then
            return completeCounselPrompt(false)
        end

        print("[COUNSEL] Press R to spend Resolve for interrupt advice, or SPACE for normal advice.")
        return true
    end

    local function selectCounselAction(index)
        local action = inputState.counselActionOptions and inputState.counselActionOptions[index]
        if not action then
            print("[COUNSEL] No advised action at position " .. tostring(index))
            return true
        end

        inputState.counselAction = action
        inputState.awaitingCounselAction = false

        local targets = getCounselTargets(inputState.counselActor)
        if #targets == 0 then
            print("[COUNSEL] No other adventurer can receive advice.")
            clearCounselPrompt()
            return true
        end

        inputState.counselTargetCandidates = targets
        if #targets == 1 then
            return advanceCounselAfterTarget(targets[1])
        end

        inputState.awaitingCounselTarget = true
        promptCounselTargets()
        return true
    end

    local function selectCounselCard(cardIndex)
        local actor = inputState.counselActor
        local hand = gameState.playerHand
        if not actor then
            print("[COUNSEL] Select a counselor first.")
            return true
        end

        local cards = hand:getHand(actor)
        if cardIndex < 1 or cardIndex > #cards then
            print("[COUNSEL] No card at position " .. tostring(cardIndex))
            return true
        end

        local card = cards[cardIndex]
        local options = getCounselActionOptions(card)
        if #options == 0 then
            print("[COUNSEL] Counsel requires a suited Challenge card.")
            return true
        end

        inputState.counselCard = card
        inputState.counselCardIndex = cardIndex
        inputState.counselActionOptions = options
        inputState.awaitingCounselCard = false
        inputState.awaitingCounselAction = true
        promptCounselActions()
        return true
    end

    local function selectCounselActor(actor)
        if not actor then
            return false
        end

        inputState.counselActor = actor
        inputState.awaitingCounselActor = false
        inputState.awaitingCounselCard = true
        eventBus:emit("card_deselected", {})
        print("[COUNSEL] Select a card for " .. (actor.name or actor.id) .. " to give (Q/W/E/R).")
        return true
    end

    local function beginCounselPrompt()
        local candidates = getCounselCandidates()
        if #candidates == 0 then
            print("[COUNSEL] No eligible Counsel adventurer has an unused advice card.")
            return true
        end

        inputState.counselActive = true
        inputState.counselCandidates = candidates
        if #candidates == 1 then
            return selectCounselActor(candidates[1])
        end

        inputState.awaitingCounselActor = true
        eventBus:emit("card_deselected", {})
        print("[COUNSEL] Select counselor (1-" .. #candidates .. "):")
        for i, actor in ipairs(candidates) do
            print("  " .. i .. ": " .. (actor.name or actor.id))
        end
        return true
    end

    local function handleCounselKey(key)
        if not inputState.counselActive then
            return false
        end

        if key == "escape" then
            clearCounselPrompt()
            eventBus:emit("card_deselected", {})
            print("[COUNSEL] Selection cancelled.")
            return true
        end

        if inputState.awaitingCounselActor then
            local index = tonumber(key)
            local candidates = inputState.counselCandidates or {}
            if index and candidates[index] then
                selectCounselActor(candidates[index])
            else
                print("[COUNSEL] Select counselor (1-" .. #candidates .. ").")
            end
            return true
        end

        if inputState.awaitingCounselCard then
            local cardKeys = { q = 1, w = 2, e = 3, r = 4 }
            if cardKeys[key] then
                return selectCounselCard(cardKeys[key])
            end
            print("[COUNSEL] Select a card (Q/W/E/R), or ESC to cancel.")
            return true
        end

        if inputState.awaitingCounselAction then
            local index = tonumber(key)
            if index then
                return selectCounselAction(index)
            end
            promptCounselActions()
            return true
        end

        if inputState.awaitingCounselTarget then
            local index = tonumber(key)
            local targets = inputState.counselTargetCandidates or {}
            if index and targets[index] then
                return advanceCounselAfterTarget(targets[index])
            end
            promptCounselTargets()
            return true
        end

        if inputState.awaitingCounselResolveChoice then
            if key == "r" then
                return completeCounselPrompt(true)
            elseif key == "space" or key == "return" then
                return completeCounselPrompt(false)
            end
            print("[COUNSEL] Press R for interrupt advice or SPACE for normal advice.")
            return true
        end

        return true
    end

    local function getCounselPromptIndexAt(x, y, count, itemWidth)
        if not count or count <= 0 then
            return nil
        end
        if y < 138 or y > 196 then
            return nil
        end
        local width = itemWidth or 180
        local index = math.floor((x - 20) / width) + 1
        if index >= 1 and index <= count then
            return index
        end
        return nil
    end

    local function handleCounselMouse(x, y)
        if not inputState.counselActive then
            return false
        end

        if inputState.awaitingCounselActor then
            local plate = getPlateAt(x, y)
            local candidates = inputState.counselCandidates or {}
            if plate and plate.entity then
                for _, actor in ipairs(candidates) do
                    if actor == plate.entity or actor.id == plate.entity.id then
                        selectCounselActor(actor)
                        return true
                    end
                end
            end

            local index = getCounselPromptIndexAt(x, y, #candidates, 180)
            if index and candidates[index] then
                selectCounselActor(candidates[index])
            end
            return true
        end

        if inputState.awaitingCounselCard and inputState.counselActor then
            local cardIndex = getHandCardIndexAt(x, y, inputState.counselActor)
            if cardIndex then
                selectCounselCard(cardIndex)
            end
            return true
        end

        if inputState.awaitingCounselAction then
            local options = inputState.counselActionOptions or {}
            local index = getCounselPromptIndexAt(x, y, #options, 170)
            if index then
                selectCounselAction(index)
            end
            return true
        end

        if inputState.awaitingCounselTarget then
            local plate = getPlateAt(x, y)
            local targets = inputState.counselTargetCandidates or {}
            if plate and plate.entity then
                for _, target in ipairs(targets) do
                    if target == plate.entity or target.id == plate.entity.id then
                        advanceCounselAfterTarget(target)
                        return true
                    end
                end
            end

            local index = getCounselPromptIndexAt(x, y, #targets, 180)
            if index and targets[index] then
                advanceCounselAfterTarget(targets[index])
            end
            return true
        end

        return true
    end

    local function executeSelectedAction(target, destinationZone, secondaryTarget)
        local challengeController = gameState.challengeController
        local hand = gameState.playerHand
        local state = challengeController:getState()

        local card = inputState.selectedCard
        local entity = inputState.selectedEntity
        local action = inputState.selectedAction
        local cardIndex = inputState.selectedCardIndex

        if not card or not entity or not action then
            print("[COMBAT] Invalid action state")
            resetCombatInputState()
            return
        end

        local isQuickInterrupt = inputState.quickInterruptActive == true
        local isMinor = (state == "minor_window") and not isQuickInterrupt
        local moveTraversal = getMoveTraversalForDestination(action, destinationZone)
        local upMySleeveItemSpec = nil
        local upMySleeveItemTemplateId = nil
        if action.id == "up_my_sleeve" then
            upMySleeveItemSpec = inputState.selectedUpMySleeveItemSpec or
                inputState.selectedUpMySleeveItem or action.upMySleeveItemSpec or
                action.upMySleeveItem or action.itemSpec
            upMySleeveItemTemplateId = action.itemTemplateId
        end

        if isMinor and not inputState.foolCard then
            local success, err = challengeController:declareMinorAction(entity, card, {
                type = action.id,
                target = target,
                secondaryTarget = secondaryTarget,
                destinationZone = destinationZone,
                traversalMode = moveTraversal and moveTraversal.mode or nil,
                traversal = moveTraversal and moveTraversal.mode or nil,
                acrobatTraversal = moveTraversal ~= nil or nil,
                requiresAcrobatTraversal = moveTraversal and moveTraversal.requiresAcrobatTraversal or nil,
                difficultTraversal = moveTraversal and moveTraversal.difficultTraversal or nil,
                destinationTraversal = moveTraversal,
                roughhouseEffect = inputState.selectedRoughhouseEffect,
                useReaver = action.useReaver,
                reaverCharge = action.reaverCharge,
                useDoomEye = action.useDoomEye,
                doomEye = action.doomEye,
                perfectShot = action.perfectShot,
                proudAndAncientWarCry = action.proudAndAncientWarCry,
                proudAndAncient = action.proudAndAncient,
                warCry = action.warCry,
                motto = action.motto,
                recoverEffect = action.recoverEffect,
                dwimmercraftEffect = action.dwimmercraftEffect,
                mode = action.mode,
                effect = action.id == "dwimmercraft" and action.effect or nil,
                intent = action.id == "dwimmercraft" and action.intent or nil,
                image = action.id == "dwimmercraft" and action.image or nil,
                objectMotion = action.id == "dwimmercraft" and action.objectMotion or nil,
                counterSpellMode = inputState.selectedCounterSpellMode,
                activeSpell = inputState.selectedCounterSpellActiveSpell,
                spellEntry = inputState.selectedCounterSpellActiveSpell,
                ongoingSpell = inputState.selectedCounterSpellActiveSpell,
                spellCaster = inputState.selectedCounterSpellCaster,
                targetCaster = inputState.selectedCounterSpellCaster,
                commandName = inputState.selectedCommandName,
                companionId = inputState.selectedCommandCompanionId,
                commandObjective = getSelectedCommandActionValue(action, "commandObjective", "objective",
                    "commandText", "instruction", "order", "task"),
                helpTarget = (action.id == "command" and inputState.selectedCommandName == "get_help") and target or nil,
                trick = (action.id == "command" and inputState.selectedCommandName == "do_a_trick") and
                    inputState.selectedCommandTrick or nil,
                commandTestOfFate = getSelectedCommandActionValue(action, "commandTestOfFate",
                    "companionTestOfFate", "requiresTestOfFate", "testOfFate"),
                companionTestTags = getSelectedCommandActionValue(action, "companionTestTags", "testTags",
                    "fateTags"),
                companionTestDescription = getSelectedCommandActionValue(action, "companionTestDescription",
                    "testDescription"),
                companionTestSuit = getSelectedCommandActionValue(action, "companionTestSuit", "testSuit",
                    "targetSuit"),
                companionTestAttribute = getSelectedCommandActionValue(action, "companionTestAttribute",
                    "testAttribute"),
                companionTestAttributeValue = getSelectedCommandActionValue(action, "companionTestAttributeValue",
                    "testAttributeValue"),
                companionTest = getSelectedCommandActionValue(action, "companionTest", "testContext", "activity",
                    "intent"),
                favor = getSelectedCommandActionValue(action, "favor"),
                disfavor = getSelectedCommandActionValue(action, "disfavor"),
                pursuit = action.pursuit,
                enemyPursuit = action.enemyPursuit,
                enemyMobility = action.enemyMobility,
                enemyTiedToLair = action.enemyTiedToLair,
                enemyWillNotPursue = action.enemyWillNotPursue,
                cleverTactics = action.cleverTactics,
                retreatTactics = action.retreatTactics,
                retreatOption = action.retreatOption,
                retreatOptionId = action.retreatOptionId,
                trigger = action.id == "aid" and inputState.selectedAidTrigger or nil,
                upMySleeveItem = upMySleeveItemSpec,
                itemSpec = action.id == "up_my_sleeve" and upMySleeveItemSpec or nil,
                itemTemplateId = upMySleeveItemTemplateId,
                item = (action.id == "use_item" and inputState.selectedUseItem) or
                    ((action.id == "pull_item" or action.id == "pull_item_belt") and inputState.selectedPullItem) or
                    ((action.id == "command" and inputState.selectedCommandName == "fetch") and
                        (target or inputState.selectedCommandObjectTarget)) or nil,
                itemId = (action.id == "use_item" and inputState.selectedUseItemId) or
                    ((action.id == "pull_item" or action.id == "pull_item_belt") and inputState.selectedPullItemId) or nil,
                swapWithItemId = (action.id == "pull_item" or action.id == "pull_item_belt") and
                    inputState.selectedPullSwapItemId or nil,
                weapon = entity.inventory and entity.inventory:getWieldedWeapon() or nil,
                allEntities = challengeController.allCombatants,
            })

            if not success then
                print("[MINOR] Declaration failed: " .. tostring(err))
                resetCombatInputState()
                eventBus:emit("card_deselected", {})
                return
            end

            removePlayedCardFromHand(hand, entity, card, cardIndex, action.id)

            print("[MINOR] " .. entity.name .. " declares " .. action.name)
            inputState.minorPC = nil
        else
            local fullAction = {
                actor = entity,
                target = target,
                secondaryTarget = secondaryTarget,
                card = card,
                type = action.id,
                destinationZone = destinationZone,
                traversalMode = moveTraversal and moveTraversal.mode or nil,
                traversal = moveTraversal and moveTraversal.mode or nil,
                acrobatTraversal = moveTraversal ~= nil or nil,
                requiresAcrobatTraversal = moveTraversal and moveTraversal.requiresAcrobatTraversal or nil,
                difficultTraversal = moveTraversal and moveTraversal.difficultTraversal or nil,
                destinationTraversal = moveTraversal,
                roughhouseEffect = inputState.selectedRoughhouseEffect,
                useReaver = action.useReaver,
                reaverCharge = action.reaverCharge,
                useDoomEye = action.useDoomEye,
                doomEye = action.doomEye,
                perfectShot = action.perfectShot,
                proudAndAncientWarCry = action.proudAndAncientWarCry,
                proudAndAncient = action.proudAndAncient,
                warCry = action.warCry,
                motto = action.motto,
                recoverEffect = action.recoverEffect,
                dwimmercraftEffect = action.dwimmercraftEffect,
                mode = action.mode,
                effect = action.id == "dwimmercraft" and action.effect or nil,
                intent = action.id == "dwimmercraft" and action.intent or nil,
                image = action.id == "dwimmercraft" and action.image or nil,
                objectMotion = action.id == "dwimmercraft" and action.objectMotion or nil,
                counterSpellMode = inputState.selectedCounterSpellMode,
                activeSpell = inputState.selectedCounterSpellActiveSpell,
                spellEntry = inputState.selectedCounterSpellActiveSpell,
                ongoingSpell = inputState.selectedCounterSpellActiveSpell,
                spellCaster = inputState.selectedCounterSpellCaster,
                targetCaster = inputState.selectedCounterSpellCaster,
                commandName = inputState.selectedCommandName,
                companionId = inputState.selectedCommandCompanionId,
                commandObjective = getSelectedCommandActionValue(action, "commandObjective", "objective",
                    "commandText", "instruction", "order", "task"),
                helpTarget = (action.id == "command" and inputState.selectedCommandName == "get_help") and target or nil,
                trick = (action.id == "command" and inputState.selectedCommandName == "do_a_trick") and
                    inputState.selectedCommandTrick or nil,
                commandTestOfFate = getSelectedCommandActionValue(action, "commandTestOfFate",
                    "companionTestOfFate", "requiresTestOfFate", "testOfFate"),
                companionTestTags = getSelectedCommandActionValue(action, "companionTestTags", "testTags",
                    "fateTags"),
                companionTestDescription = getSelectedCommandActionValue(action, "companionTestDescription",
                    "testDescription"),
                companionTestSuit = getSelectedCommandActionValue(action, "companionTestSuit", "testSuit",
                    "targetSuit"),
                companionTestAttribute = getSelectedCommandActionValue(action, "companionTestAttribute",
                    "testAttribute"),
                companionTestAttributeValue = getSelectedCommandActionValue(action, "companionTestAttributeValue",
                    "testAttributeValue"),
                companionTest = getSelectedCommandActionValue(action, "companionTest", "testContext", "activity",
                    "intent"),
                favor = getSelectedCommandActionValue(action, "favor"),
                disfavor = getSelectedCommandActionValue(action, "disfavor"),
                pursuit = action.pursuit,
                enemyPursuit = action.enemyPursuit,
                enemyMobility = action.enemyMobility,
                enemyTiedToLair = action.enemyTiedToLair,
                enemyWillNotPursue = action.enemyWillNotPursue,
                cleverTactics = action.cleverTactics,
                retreatTactics = action.retreatTactics,
                retreatOption = action.retreatOption,
                retreatOptionId = action.retreatOptionId,
                trigger = action.id == "aid" and inputState.selectedAidTrigger or nil,
                upMySleeveItem = upMySleeveItemSpec,
                itemSpec = action.id == "up_my_sleeve" and upMySleeveItemSpec or nil,
                itemTemplateId = upMySleeveItemTemplateId,
                item = (action.id == "use_item" and inputState.selectedUseItem) or
                    ((action.id == "pull_item" or action.id == "pull_item_belt") and inputState.selectedPullItem) or
                    ((action.id == "command" and inputState.selectedCommandName == "fetch") and
                        (target or inputState.selectedCommandObjectTarget)) or nil,
                itemId = (action.id == "use_item" and inputState.selectedUseItemId) or
                    ((action.id == "pull_item" or action.id == "pull_item_belt") and inputState.selectedPullItemId) or nil,
                swapWithItemId = (action.id == "pull_item" or action.id == "pull_item_belt") and
                    inputState.selectedPullSwapItemId or nil,
                weapon = (entity.inventory and entity.inventory:getWieldedWeapon()) or { name = "Fists", isMelee = true },
                allEntities = challengeController.allCombatants,
            }

            if action.id == "vigilance" then
                local followUpAction = inputState.selectedVigilanceFollowUp
                if not followUpAction then
                    print("[VIGILANCE] Follow-up action not selected.")
                    resetCombatInputState()
                    eventBus:emit("card_deselected", {})
                    return
                end

                fullAction.trigger = inputState.selectedVigilanceTrigger or { template = "hostile_targets_self" }
                fullAction.followUpAction = followUpAction.id
                fullAction.followUpTargetPolicy = getVigilanceFollowUpTargetPolicy(followUpAction)

                local triggerName = inputState.selectedVigilanceTriggerOption and inputState.selectedVigilanceTriggerOption.name or "Target Me"
                print("[VIGILANCE] " .. entity.name .. " prepares " .. followUpAction.name ..
                      " on trigger: " .. triggerName .. ".")
            elseif action.id == "flee" then
                fullAction.retreatTestCards = fullAction.retreatTestCards or {}
                fullAction.retreatTestCards[entity.id or entity.name or "actor"] = card
                fullAction.groupTestCards = fullAction.retreatTestCards
            elseif destinationZone and action.id == "use_item" then
                print("[COMBAT] " .. entity.name .. " uses " .. action.name .. " in " .. destinationZone)
            elseif destinationZone then
                print("[COMBAT] " .. entity.name .. " uses " .. action.name .. " to move to " .. destinationZone)
            else
                print("[COMBAT] " .. entity.name .. " uses " .. action.name .. " on " .. (target and target.name or "no target"))
            end

            local success, err
            if inputState.foolCard then
                if not inputState.foolFollowUpCard then
                    print("[FOOL INTERRUPT] Follow-up card not selected.")
                    resetCombatInputState()
                    eventBus:emit("card_deselected", {})
                    return
                end

                fullAction.foolFollowUpAction = action.id
                success, err = challengeController:playFoolInterrupt(
                    entity,
                    inputState.foolCard,
                    inputState.foolFollowUpCard,
                    fullAction
                )
            elseif isQuickInterrupt then
                success, err = challengeController:playQuickInterrupt(entity, card, fullAction)
            else
                success, err = challengeController:submitAction(fullAction)
            end
            if not success then
                print("[COMBAT] Action submit failed: " .. tostring(err))
                resetCombatInputState()
                eventBus:emit("card_deselected", {})
                return
            end

            if inputState.foolCard then
                removePlayedCardFromHand(hand, entity, inputState.foolCard, nil, "fool_interrupt")
                removePlayedCardFromHand(hand, entity, inputState.foolFollowUpCard, nil, action.id)
            else
                removePlayedCardFromHand(hand, entity, card, cardIndex, action.id)
            end
        end

        resetCombatInputState()
        eventBus:emit("card_deselected", {})
    end

    function controller:getState()
        return self.inputState
    end

    function controller:resetInputState()
        resetCombatInputState()
        clearCounterSpellPrompt()
        clearAmbusherResistancePrompt()
        clearWoundChoicePrompt()
        clearRetreatGroupTestPrompt()
        clearHeavyMetalMachinePrompt()
        clearAegisPrompt()
        clearQuickInterruptPrompt()
        clearCounselPrompt()
    end

    function controller:init()
        self.eventBus:on("action_selected", function(data)
            self:handleActionSelected(data)
        end)

        self.eventBus:on(events.EVENTS.ARENA_ENTITY_CLICKED, function(data)
            self:handleArenaEntityClick(data)
        end)

        self.eventBus:on(events.EVENTS.ARENA_ZONE_CLICKED, function(data)
            self:handleArenaZoneClick(data)
        end)

        self.eventBus:on(events.EVENTS.CHALLENGE_END, function()
            resetCombatInputState()
            clearCounterSpellPrompt()
            clearAmbusherResistancePrompt()
            clearWoundChoicePrompt()
            clearAcrobatFallChoicePrompt()
            clearRetreatGroupTestPrompt()
            clearHeavyMetalMachinePrompt()
            clearAegisPrompt()
            clearQuickInterruptPrompt()
            clearCounselPrompt()
        end)

        self.eventBus:on("ambusher_resistance_available", function(data)
            setAmbusherResistancePrompt(data)
        end)

        self.eventBus:on("ambusher_resistance_resolved", function()
            clearAmbusherResistancePrompt()
        end)

        self.eventBus:on("ambusher_resistance_skipped", function()
            clearAmbusherResistancePrompt()
        end)

        self.eventBus:on(events.EVENTS.REQUEST_WOUND_CHOICE, function(data)
            setWoundChoicePrompt(data)
        end)

        self.eventBus:on(events.EVENTS.WOUND_CHOICE_COMPLETE, function(data)
            if inputState.pendingWoundChoice and data and
               inputState.pendingWoundChoice == data.pendingWoundChoice then
                clearWoundChoicePrompt()
            end
        end)

        self.eventBus:on(events.EVENTS.REQUEST_ACROBAT_FALL_CHOICE, function(data)
            setAcrobatFallChoicePrompt(data)
        end)

        self.eventBus:on(events.EVENTS.ACROBAT_FALL_CHOICE_COMPLETE, function(data)
            if inputState.pendingAcrobatFallChoice and data and
               inputState.pendingAcrobatFallChoice == data.pendingAcrobatFallChoice then
                clearAcrobatFallChoicePrompt()
            end
        end)

        self.eventBus:on(events.EVENTS.REQUEST_RETREAT_GROUP_TEST, function(data)
            setRetreatGroupTestPrompt(data)
        end)

        self.eventBus:on(events.EVENTS.RETREAT_GROUP_TEST_COMPLETE, function()
            clearRetreatGroupTestPrompt()
        end)

        self.eventBus:on("counter_spell_interrupt_available", function(data)
            setCounterSpellPrompt(data)
        end)

        self.eventBus:on("counter_spell_interrupt_start", function(data)
            local pending = inputState.pendingCounterSpellInterrupt
            if pending and data and data.incomingAction == pending.incomingAction then
                clearCounterSpellPrompt()
            end
        end)

        self.eventBus:on("counter_spell_interrupt_resolved", function(data)
            local pending = inputState.pendingCounterSpellInterrupt
            if pending and data and data.incomingAction == pending.incomingAction then
                clearCounterSpellPrompt()
            end
        end)

        self.eventBus:on("heavy_metal_machine_interrupt_available", function(data)
            setHeavyMetalMachinePrompt(data)
        end)

        self.eventBus:on("heavy_metal_machine_interrupt_start", function(data)
            local pending = inputState.pendingHeavyMetalMachineInterrupt
            if pending and data and data.incomingAction == pending.incomingAction then
                clearHeavyMetalMachinePrompt()
            end
        end)

        self.eventBus:on("heavy_metal_machine_interrupt_resolved", function(data)
            local pending = inputState.pendingHeavyMetalMachineInterrupt
            if pending and data and data.incomingAction == pending.incomingAction then
                clearHeavyMetalMachinePrompt()
            end
        end)

        self.eventBus:on("aegis_election_available", function(data)
            setAegisPrompt(data)
        end)

        self.eventBus:on("aegis_election_start", function(data)
            local pending = inputState.pendingAegisElection
            if pending and data and data.incomingAction == pending.incomingAction then
                clearAegisPrompt()
            end
        end)

        self.eventBus:on("aegis_election_resolved", function(data)
            local pending = inputState.pendingAegisElection
            if pending and data and data.incomingAction == pending.incomingAction then
                clearAegisPrompt()
            end
        end)
    end

    function controller:handleActionSelected(data)
        if not data or not data.action then
            return
        end

        inputState.selectedAction = data.action
        inputState.selectedRoughhouseEffect = data.roughhouseEffect or data.action.roughhouseEffect
        inputState.selectedCommandName = data.commandName
        inputState.selectedCommandCompanionId = data.commandCompanionId
        inputState.selectedCommandOption = data.commandOption
        inputState.selectedCommandTrick = getSelectedCommandOptionValue("trick", "trickName")
        inputState.selectedAidTrigger = shallowCopyTable(data.aidTrigger)
        inputState.selectedAidTriggerOption = data.aidTriggerOption
        inputState.selectedPullItem = data.pullItem
        inputState.selectedPullItemId = data.pullItemId
        inputState.selectedPullItemOption = data.pullItemOption
        inputState.selectedPullSwapItem = data.pullSwapItem
        inputState.selectedPullSwapItemId = data.pullSwapItemId
        inputState.selectedPullSwapOption = data.pullSwapOption
        inputState.selectedUseItem = data.useItem
        inputState.selectedUseItemId = data.useItemId
        inputState.selectedUseItemOption = data.useItemOption
        inputState.selectedUpMySleeveItem = data.upMySleeveItem or data.action.upMySleeveItem
        inputState.selectedUpMySleeveItemSpec = data.upMySleeveItemSpec or data.itemSpec or
            data.action.upMySleeveItemSpec or data.action.itemSpec
        inputState.selectedUpMySleeveOption = data.upMySleeveOption or data.action.upMySleeveOption
        if data.action.id == "counter_spell" then
            inputState.selectedCounterSpellMode = data.action.counterSpellMode or data.action.mode
            inputState.selectedCounterSpellActiveSpell = data.action.activeSpell or data.action.spellEntry or
                data.action.ongoingSpell
            inputState.selectedCounterSpellCaster = data.action.spellCaster or data.action.targetCaster
        end

        if inputState.quickInterruptActive then
            local actionDef = action_registry.getAction(data.action.id)
            if not actionDef or actionDef.suit ~= action_registry.SUITS.PENTACLES then
                inputState.selectedAction = nil
                print("[QUICK!] Choose a Pentacles action for Quick!.")
                return
            end
        end

        if data.action.id == "vigilance" then
            if not data.followUpAction then
                print("[VIGILANCE] Select follow-up action from Command Board.")
                resetCombatInputState()
                eventBus:emit("card_deselected", {})
                return
            end

            inputState.selectedVigilanceFollowUp = data.followUpAction
            inputState.selectedVigilanceTrigger = data.vigilanceTrigger
            inputState.selectedVigilanceTriggerOption = data.vigilanceTriggerOption
            executeSelectedAction(nil)
            return
        end

        if data.action.id == "move" or data.action.id == "dash" or data.action.id == "avoid" then
            local availableZones = getAvailableDestinationZones(inputState.selectedEntity, data.action)

            if #availableZones > 0 then
                inputState.awaitingZone = true
                inputState.availableZones = availableZones

                if data.action.id == "avoid" then
                    print("[COMBAT] Select adjacent destination zone (1-" .. #availableZones .. "), or press Space to avoid in place:")
                elseif data.action.id == "dash" then
                    print("[COMBAT] Select destination zone up to two zones away (1-" .. #availableZones .. "):")
                else
                    print("[COMBAT] Select adjacent destination zone (1-" .. #availableZones .. "):")
                end
                for i, zone in ipairs(availableZones) do
                    print("  " .. i .. ": " .. formatZoneOption(zone))
                end
            else
                if data.action.id == "avoid" then
                    print("[COMBAT] No adjacent zones available. Resolving Avoid in place.")
                    executeSelectedAction(nil)
                else
                    print("[COMBAT] No adjacent zones available!")
                    resetCombatInputState()
                    eventBus:emit("card_deselected", {})
                end
            end
            return
        end

        if data.action.id == "use_item" and useItemTargetsZone(inputState.selectedUseItem) then
            local availableZones = getUseItemTargetZones()

            if #availableZones > 0 then
                inputState.awaitingZone = true
                inputState.availableZones = availableZones
                print("[COMBAT] Select target zone (1-" .. #availableZones .. "):")
                for i, zone in ipairs(availableZones) do
                    print("  " .. i .. ": " .. (zone.name or zone.id))
                end
            else
                print("[COMBAT] No valid zones available!")
                resetCombatInputState()
                eventBus:emit("card_deselected", {})
            end
            return
        end

        if data.action.id == "use_item" and useItemTargetsObject(inputState.selectedUseItem) then
            local availableObjects = getUseItemObjectTargets()

            if #availableObjects > 0 then
                inputState.awaitingObjectTarget = true
                inputState.availableObjectTargets = availableObjects
                print("[COMBAT] Select object target (1-" .. #availableObjects .. "):")
                for i, objectTarget in ipairs(availableObjects) do
                    print("  " .. i .. ": " .. tostring(getObjectTargetName(objectTarget)))
                end
            else
                print("[COMBAT] No valid object targets available!")
                resetCombatInputState()
                eventBus:emit("card_deselected", {})
            end
            return
        end

        if actionTargetsObject(data.action) then
            local availableObjects = getUseItemObjectTargets()

            if #availableObjects > 0 then
                inputState.awaitingObjectTarget = true
                inputState.availableObjectTargets = availableObjects
                print("[COMBAT] Select object target (1-" .. #availableObjects .. "):")
                for i, objectTarget in ipairs(availableObjects) do
                    print("  " .. i .. ": " .. tostring(getObjectTargetName(objectTarget)))
                end
            else
                print("[COMBAT] No valid object targets available!")
                resetCombatInputState()
                eventBus:emit("card_deselected", {})
            end
            return
        end

        if data.action.id == "command" and commandTargetsObject(data.commandName) then
            local availableObjects = getUseItemObjectTargets()

            if #availableObjects > 0 then
                inputState.awaitingObjectTarget = true
                inputState.availableObjectTargets = availableObjects
                local targetLabel = data.commandName == "track" and "trail or object" or
                    (data.commandName == "hunt" and "trail or prey" or "object")
                print("[COMBAT] Select command " .. targetLabel .. " target (1-" .. #availableObjects ..
                    "), or press Space for no specific target:")
                for i, objectTarget in ipairs(availableObjects) do
                    print("  " .. i .. ": " .. tostring(getObjectTargetName(objectTarget)))
                end
            else
                executeSelectedAction(nil)
            end
            return
        end

        local commandTargetType = data.action.id == "command" and getCommandTargetType(data.commandName) or nil
        local useItemTargetAction = buildUseItemTargetAction(data.action, inputState.selectedUseItem)
        if data.action.requiresTarget or commandTargetType or useItemTargetAction then
            inputState.awaitingTarget = true
            local targetAction = data.action
            if commandTargetType then
                targetAction = {}
                for key, value in pairs(data.action) do
                    targetAction[key] = value
                end
                targetAction.targetType = commandTargetType
                targetAction.requiresTarget = true
            elseif useItemTargetAction then
                targetAction = useItemTargetAction
            end
            inputState.selectedAction = targetAction
            local targets = getValidTargetsForAction(targetAction, inputState.selectedEntity)
            local isMelee = (data.action.id == "melee" or data.action.id == "roughhouse" or data.action.id == "grapple" or
                data.action.id == "trip" or data.action.id == "disarm" or
                data.action.id == "displace")

            if #targets == 0 then
                if isMelee then
                    print("[COMBAT] No enemies in your zone! Use Move to get closer.")
                else
                    print("[COMBAT] No valid targets available!")
                end
                inputState.awaitingTarget = false
                resetCombatInputState()
                eventBus:emit("card_deselected", {})
                return
            end

            if commandTargetType and commandAllowsNoSpecificTarget(data.commandName) then
                print("[COMBAT] Select target (1-" .. #targets .. "), or press Space for no specific target:")
            else
                print("[COMBAT] Select target (1-" .. #targets .. "):")
            end
            for i, target in ipairs(targets) do
                local zoneInfo = target.zone and (" [" .. target.zone .. "]") or ""
                print("  " .. i .. ": " .. (target.name or target.id) .. zoneInfo)
            end
        else
            executeSelectedAction(nil)
        end
    end

    function controller:handleCombatMousePressed(x, y, button)
        if button ~= 1 then
            return false
        end

        local challengeController = gameState.challengeController
        if not challengeController or not challengeController:isActive() then
            return false
        end

        if inputState.pendingWoundChoice then
            return true
        end

        if inputState.pendingAcrobatFallChoice then
            return true
        end

        if inputState.pendingRetreatGroupTest then
            return true
        end

        if inputState.pendingAmbusherResistance then
            return handleAmbusherResistanceMouse(x, y)
        end

        if inputState.pendingCounterSpellInterrupt then
            return handleCounterSpellInterruptMouse(x, y)
        end

        if inputState.pendingHeavyMetalMachineInterrupt then
            return handleHeavyMetalMachineInterruptMouse(x, y)
        end

        if inputState.pendingAegisElection then
            return handleAegisMouse(x, y)
        end

        if inputState.counselActive then
            return handleCounselMouse(x, y)
        end

        if inputState.awaitingQuickInterruptActor or inputState.quickInterruptActor then
            return handleQuickInterruptMouse(x, y)
        end

        local challengeState = challengeController:getState()

        if challengeState == "pre_round" then
            local hand = gameState.playerHand
            if not hand.selectedPC then
                local plate = getPlateAt(x, y)
                if plate and plate.entity and challengeController.awaitingInitiative[plate.entity.id] then
                    hand.selectedPC = plate.entity
                    print("[INITIATIVE] Select a card for " .. plate.entity.name .. " (Q/W/E/R or click)")
                    return true
                end
            end

            if hand.selectedPC and challengeController.awaitingInitiative[hand.selectedPC.id] then
                local cardIndex = getHandCardIndexAt(x, y, hand.selectedPC, 4)
                if cardIndex then
                    local card = hand:useForInitiative(hand.selectedPC, cardIndex)
                    if card then
                        challengeController:submitInitiative(hand.selectedPC, card)
                        hand:clearSelection()
                        return true
                    end
                end
            end
            return false
        end

        if challengeState == "minor_window" then
            if not inputState.minorPC then
                local plate = getPlateAt(x, y)
                if plate and plate.entity then
                    local cards = gameState.playerHand:getHand(plate.entity)
                    if #cards > 0 then
                        inputState.minorPC = plate.entity
                        print("[MINOR] Select a card for " .. plate.entity.name .. " (Q/W/E or click)")
                        return true
                    end
                end
            end

            if inputState.minorPC then
                local cardIndex = getHandCardIndexAt(x, y, inputState.minorPC, 3)
                if cardIndex then
                    selectCardForAction(inputState.minorPC, cardIndex, false)
                    return true
                end
            end
            return false
        end

        if challengeState ~= "awaiting_action" then
            return false
        end

        local activeEntity = challengeController:getActiveEntity()
        if not activeEntity or not activeEntity.isPC then
            return false
        end

        if inputState.awaitingFoolFollowUpCard then
            local cardIndex = getHandCardIndexAt(x, y, activeEntity, 3)
            if cardIndex then
                selectFoolFollowUpCard(activeEntity, cardIndex)
                return true
            end
            return false
        end

        local cardIndex = getHandCardIndexAt(x, y, activeEntity, 3)
        if cardIndex then
            if selectCardForAction(activeEntity, cardIndex, true) and not inputState.awaitingFoolFollowUpCard then
                print("[COMBAT] " .. activeEntity.name .. " selected a card - choose action from Command Board")
            end
            return true
        end

        return false
    end

    function controller:handleChallengeInput(key)
        local challengeController = gameState.challengeController
        local hand = gameState.playerHand

        if inputState.pendingWoundChoice then
            handleWoundChoiceKey(key)
            return
        end

        if inputState.pendingAcrobatFallChoice then
            handleAcrobatFallChoiceKey(key)
            return
        end

        if inputState.pendingRetreatGroupTest then
            handleRetreatGroupTestKey(key)
            return
        end

        if inputState.pendingAmbusherResistance then
            handleAmbusherResistanceKey(key)
            return
        end

        if inputState.pendingCounterSpellInterrupt then
            handleCounterSpellInterruptKey(key)
            return
        end

        if inputState.pendingHeavyMetalMachineInterrupt then
            handleHeavyMetalMachineInterruptKey(key)
            return
        end

        if inputState.pendingAegisElection then
            handleAegisKey(key)
            return
        end

        local challengeState = challengeController:getState()

        if inputState.counselActive then
            handleCounselKey(key)
            return
        end

        if inputState.awaitingQuickInterruptActor or inputState.quickInterruptActor then
            handleQuickInterruptKey(key)
            return
        end

        if key == "c" and challengeState ~= "pre_round" and
           not inputState.selectedCard and not inputState.awaitingTarget and not inputState.awaitingZone and
           not inputState.awaitingObjectTarget and not inputState.awaitingAidTriggerTarget and
           not inputState.awaitingFoolFollowUpCard and not inputState.minorPC then
            beginCounselPrompt()
            return
        end

        if key == "k" and challengeState ~= "pre_round" and
           not inputState.selectedCard and not inputState.awaitingTarget and not inputState.awaitingZone and
           not inputState.awaitingObjectTarget and not inputState.awaitingAidTriggerTarget and
           not inputState.awaitingFoolFollowUpCard and not inputState.minorPC then
            beginQuickInterruptPrompt()
            return
        end

        if challengeState == "pre_round" then
            self:handleInitiativeInput(key)
            return
        end

        if challengeState == "minor_window" then
            self:handleMinorWindowInput(key)
            return
        end

        if challengeState ~= "awaiting_action" then
            return
        end

        local activeEntity = challengeController:getActiveEntity()
        if not activeEntity or not activeEntity.isPC then
            return
        end

        if inputState.awaitingFoolFollowUpCard then
            local cardKeys = { q = 1, w = 2, e = 3 }
            local cardIndex = cardKeys[key]
            if cardIndex then
                selectFoolFollowUpCard(activeEntity, cardIndex)
            else
                print("[FOOL INTERRUPT] Select a follow-up card (Q/W/E).")
            end
            return
        end

        if inputState.awaitingRoughhouseDisplaceZone then
            self:handleRoughhouseDisplaceZoneSelection(key)
            return
        end

        if inputState.awaitingZone then
            self:handleZoneSelection(key)
            return
        end

        if inputState.awaitingAidTriggerTarget then
            self:handleAidTriggerTargetSelection(key)
            return
        end

        if inputState.awaitingObjectTarget then
            self:handleObjectTargetSelection(key)
            return
        end

        if inputState.awaitingTarget then
            self:handleTargetSelection(key)
            return
        end

        local cardKeys = { q = 1, w = 2, e = 3 }
        if cardKeys[key] then
            local cardIndex = cardKeys[key]
            local cards = hand:getHand(activeEntity)

            if cardIndex <= #cards then
                local card = cards[cardIndex]
                if selectCardForAction(activeEntity, cardIndex, true) and not inputState.awaitingFoolFollowUpCard then
                    print("[COMBAT] " .. activeEntity.name .. " selected " .. card.name .. " - choose action from Command Board")
                end
            else
                print("[COMBAT] No card at position " .. cardIndex)
            end
            return
        end

        if key == "h" then
            local cards = hand:getHand(activeEntity)
            print("[HAND] " .. activeEntity.name .. "'s cards:")
            for i, card in ipairs(cards) do
                local keyLetter = ({ "Q", "W", "E" })[i]
                local suitName = hand:getSuitName(card.suit)
                print("  " .. keyLetter .. ": " .. card.name .. " (" .. suitName .. ", " .. card.value .. ")")
            end
            return
        end

        if key == "space" then
            print("[COMBAT] " .. (activeEntity.name or "PC") .. " passes")
            local success, err = challengeController:skipTurn(activeEntity, "pass")
            if not success then
                print("[COMBAT] Pass failed: " .. tostring(err))
            end
            resetCombatInputState()
        end

        if key == "escape" then
            if inputState.selectedCard then
                resetCombatInputState()
                eventBus:emit("card_deselected", {})
                print("[COMBAT] Selection cancelled")
            end
        end
    end

    function controller:handleMinorWindowInput(key)
        local challengeController = gameState.challengeController
        local hand = gameState.playerHand

        if inputState.pendingWoundChoice then
            handleWoundChoiceKey(key)
            return
        end

        if inputState.pendingAcrobatFallChoice then
            handleAcrobatFallChoiceKey(key)
            return
        end

        if inputState.pendingRetreatGroupTest then
            handleRetreatGroupTestKey(key)
            return
        end

        if inputState.pendingAmbusherResistance then
            handleAmbusherResistanceKey(key)
            return
        end

        if inputState.pendingCounterSpellInterrupt then
            handleCounterSpellInterruptKey(key)
            return
        end

        if inputState.pendingHeavyMetalMachineInterrupt then
            handleHeavyMetalMachineInterruptKey(key)
            return
        end

        if inputState.pendingAegisElection then
            handleAegisKey(key)
            return
        end

        if inputState.counselActive then
            handleCounselKey(key)
            return
        end

        if inputState.awaitingQuickInterruptActor or inputState.quickInterruptActor then
            handleQuickInterruptKey(key)
            return
        end

        if key == "c" and
           not inputState.selectedCard and not inputState.awaitingTarget and not inputState.awaitingZone and
           not inputState.awaitingObjectTarget and not inputState.awaitingAidTriggerTarget and
           not inputState.awaitingFoolFollowUpCard and not inputState.minorPC then
            beginCounselPrompt()
            return
        end

        if key == "k" and
           not inputState.selectedCard and not inputState.awaitingTarget and not inputState.awaitingZone and
           not inputState.awaitingObjectTarget and not inputState.awaitingAidTriggerTarget and
           not inputState.awaitingFoolFollowUpCard and not inputState.minorPC then
            beginQuickInterruptPrompt()
            return
        end

        if inputState.awaitingRoughhouseDisplaceZone then
            self:handleRoughhouseDisplaceZoneSelection(key)
            return
        end

        if inputState.awaitingAidTriggerTarget then
            self:handleAidTriggerTargetSelection(key)
            return
        end

        if inputState.awaitingObjectTarget then
            self:handleObjectTargetSelection(key)
            return
        end

        if inputState.awaitingTarget then
            self:handleTargetSelection(key)
            return
        end

        if inputState.awaitingZone then
            self:handleZoneSelection(key)
            return
        end

        if inputState.awaitingFoolFollowUpCard then
            local cardKeys = { q = 1, w = 2, e = 3 }
            local cardIndex = cardKeys[key]
            if cardIndex then
                selectFoolFollowUpCard(inputState.selectedEntity or inputState.minorPC, cardIndex)
            else
                print("[FOOL INTERRUPT] Select a follow-up card (Q/W/E).")
            end
            return
        end

        local keyNum = tonumber(key)
        if keyNum and keyNum >= 1 and keyNum <= 4 then
            local pc = gameState.guild[keyNum]
            if pc then
                local cards = hand:getHand(pc)
                if #cards > 0 then
                    inputState.minorPC = pc
                    print("[MINOR] Select a card for " .. pc.name .. " (Q/W/E)")
                else
                    print("[MINOR] " .. pc.name .. " has no cards!")
                end
            end
            return
        end

        if inputState.minorPC then
            local cardKeys = { q = 1, w = 2, e = 3 }
            if cardKeys[key] then
                local cardIndex = cardKeys[key]
                local cards = hand:getHand(inputState.minorPC)

                if cardIndex <= #cards then
                    local card = cards[cardIndex]
                    if selectCardForAction(inputState.minorPC, cardIndex, false) and
                       not inputState.awaitingFoolFollowUpCard then
                        print("[MINOR] " .. inputState.minorPC.name .. " selected " .. card.name .. " for minor action")
                    end
                end
                return
            end

            if key == "escape" then
                inputState.minorPC = nil
                eventBus:emit("card_deselected", {})
                print("[MINOR] PC selection cancelled")
                return
            end
        end

        if key == "space" or key == "return" then
            challengeController:resumeFromMinorWindow()
            resetCombatInputState()
        end
    end

    function controller:handleZoneSelection(key)
        local zones = inputState.availableZones

        if not zones or #zones == 0 then
            inputState.awaitingZone = false
            return
        end

        if key == "space" and inputState.selectedAction and inputState.selectedAction.id == "avoid" then
            executeSelectedAction(nil)
            return
        end

        local keyNum = tonumber(key)
        if keyNum and keyNum >= 1 and keyNum <= #zones then
            local selectedZone = zones[keyNum]
            executeSelectedAction(nil, selectedZone.id)
            return
        end

        if key == "escape" then
            inputState.awaitingZone = false
            inputState.availableZones = nil
            resetCombatInputState()
            eventBus:emit("card_deselected", {})
            print("[COMBAT] Zone selection cancelled")
        end
    end

    function controller:handleZoneSelectionById(zoneId)
        local zones = inputState.availableZones
        if not zones or #zones == 0 then
            inputState.awaitingZone = false
            return false
        end

        for _, zone in ipairs(zones) do
            if zone.id == zoneId then
                executeSelectedAction(nil, zoneId)
                return true
            end
        end

        print("[COMBAT] Zone not available for move: " .. tostring(zoneId))
        return false
    end

    function controller:handleRoughhouseDisplaceZoneSelection(key)
        local zones = inputState.availableZones

        if not zones or #zones == 0 then
            inputState.awaitingRoughhouseDisplaceZone = false
            return
        end

        local keyNum = tonumber(key)
        if keyNum and keyNum >= 1 and keyNum <= #zones then
            local selectedZone = zones[keyNum]
            executeSelectedAction(inputState.selectedRoughhouseDisplaceTarget, selectedZone.id)
            return
        end

        if key == "escape" then
            inputState.awaitingRoughhouseDisplaceZone = false
            inputState.selectedRoughhouseDisplaceTarget = nil
            inputState.availableZones = nil
            resetCombatInputState()
            eventBus:emit("card_deselected", {})
            print("[COMBAT] Roughhouse Displace zone selection cancelled")
        end
    end

    function controller:handleRoughhouseDisplaceZoneSelectionById(zoneId)
        local zones = inputState.availableZones
        if not zones or #zones == 0 then
            inputState.awaitingRoughhouseDisplaceZone = false
            return false
        end

        for _, zone in ipairs(zones) do
            if zone.id == zoneId then
                executeSelectedAction(inputState.selectedRoughhouseDisplaceTarget, zoneId)
                return true
            end
        end

        print("[COMBAT] Zone not available for Roughhouse Displace: " .. tostring(zoneId))
        return false
    end

    function controller:handleTargetSelection(key)
        local action = inputState.selectedAction

        if not action then
            inputState.awaitingTarget = false
            return
        end

        local targets = getValidTargetsForAction(action, inputState.selectedEntity)

        if key == "space" and action.id == "command" and
           commandAllowsNoSpecificTarget(inputState.selectedCommandName) then
            executeSelectedAction(nil)
            return
        end

        local keyNum = tonumber(key)
        if keyNum and keyNum >= 1 and keyNum <= #targets then
            local target = targets[keyNum]
            if action.id == "aid" and beginAidTriggerTargetSelection(target) then
                return
            end
            if isRoughhouseDisplaceSelection(action) and beginRoughhouseDisplaceZoneSelection(target) then
                return
            end
            executeSelectedAction(target)
            return
        end

        if key == "escape" then
            inputState.awaitingTarget = false
            resetCombatInputState()
            eventBus:emit("card_deselected", {})
            print("[COMBAT] Target selection cancelled")
        end
    end

    function controller:handleAidTriggerTargetSelection(key)
        local targets = inputState.availableAidTriggerTargets

        if not targets or #targets == 0 then
            inputState.awaitingAidTriggerTarget = false
            return
        end

        if key == "space" then
            executeSelectedAction(inputState.selectedAidTarget)
            return
        end

        local keyNum = tonumber(key)
        if keyNum and keyNum >= 1 and keyNum <= #targets then
            local target = targets[keyNum]
            recordAidTriggerTarget(target)
            executeSelectedAction(inputState.selectedAidTarget)
            return
        end

        if key == "escape" then
            inputState.awaitingAidTriggerTarget = false
            inputState.availableAidTriggerTargets = nil
            inputState.selectedAidTarget = nil
            inputState.selectedAidTriggerTarget = nil
            inputState.selectedAidTriggerTargetAction = nil
            resetCombatInputState()
            eventBus:emit("card_deselected", {})
            print("[AID] Trigger target selection cancelled")
        end
    end

    function controller:handleObjectTargetSelection(key)
        local targets = inputState.availableObjectTargets

        if not targets or #targets == 0 then
            inputState.awaitingObjectTarget = false
            return
        end

        if key == "space" and inputState.selectedAction and inputState.selectedAction.id == "command" then
            executeSelectedAction(nil)
            return
        end

        local keyNum = tonumber(key)
        if keyNum and keyNum >= 1 and keyNum <= #targets then
            local selectedTarget = targets[keyNum]
            if inputState.selectedAction and inputState.selectedAction.id == "command" then
                inputState.selectedCommandObjectTarget = selectedTarget
                executeSelectedAction(selectedTarget)
                return
            end
            if actionTargetsObject(inputState.selectedAction) then
                executeSelectedAction(selectedTarget)
                return
            end

            if useItemNeedsSecondaryObjectTarget(inputState.selectedUseItem) and
               not inputState.awaitingSecondaryObjectTarget then
                local secondaryTargets = getUseItemObjectTargets(selectedTarget)
                if #secondaryTargets == 0 then
                    print("[COMBAT] No valid secondary object targets available!")
                    resetCombatInputState()
                    eventBus:emit("card_deselected", {})
                    return
                end

                inputState.selectedObjectTarget = selectedTarget
                inputState.awaitingSecondaryObjectTarget = true
                inputState.availableObjectTargets = secondaryTargets
                print("[COMBAT] Select second object target (1-" .. #secondaryTargets .. "):")
                for i, objectTarget in ipairs(secondaryTargets) do
                    print("  " .. i .. ": " .. tostring(getObjectTargetName(objectTarget)))
                end
                return
            end

            if inputState.awaitingSecondaryObjectTarget then
                executeSelectedAction(inputState.selectedObjectTarget, nil, selectedTarget)
            else
                executeSelectedAction(selectedTarget)
            end
            return
        end

        if key == "escape" then
            inputState.awaitingObjectTarget = false
            inputState.awaitingSecondaryObjectTarget = false
            inputState.availableObjectTargets = nil
            inputState.selectedObjectTarget = nil
            resetCombatInputState()
            eventBus:emit("card_deselected", {})
            print("[COMBAT] Object target selection cancelled")
        end
    end

    function controller:handleObjectTargetSelectionByObject(objectTarget)
        if not objectTarget then
            return false
        end

        for _, target in ipairs(inputState.availableObjectTargets or {}) do
            if target == objectTarget then
                if inputState.selectedAction and inputState.selectedAction.id == "command" then
                    inputState.selectedCommandObjectTarget = target
                    executeSelectedAction(target)
                    return true
                end
                if actionTargetsObject(inputState.selectedAction) then
                    executeSelectedAction(target)
                    return true
                end

                if useItemNeedsSecondaryObjectTarget(inputState.selectedUseItem) and
                   not inputState.awaitingSecondaryObjectTarget then
                    local secondaryTargets = getUseItemObjectTargets(target)
                    if #secondaryTargets == 0 then
                        print("[COMBAT] No valid secondary object targets available!")
                        resetCombatInputState()
                        eventBus:emit("card_deselected", {})
                        return false
                    end
                    inputState.selectedObjectTarget = target
                    inputState.awaitingSecondaryObjectTarget = true
                    inputState.availableObjectTargets = secondaryTargets
                    return true
                end

                if inputState.awaitingSecondaryObjectTarget then
                    executeSelectedAction(inputState.selectedObjectTarget, nil, target)
                else
                    executeSelectedAction(target)
                end
                return true
            end
        end

        print("[COMBAT] Invalid object target.")
        return false
    end

    function controller:handleAidTriggerTargetSelectionByEntity(entity)
        if not entity then
            return false
        end

        for _, target in ipairs(inputState.availableAidTriggerTargets or {}) do
            if target == entity then
                recordAidTriggerTarget(target)
                executeSelectedAction(inputState.selectedAidTarget)
                return true
            end
        end

        print("[AID] Invalid trigger target.")
        return false
    end

    function controller:handleTargetSelectionByEntity(entity)
        local action = inputState.selectedAction
        if not action or not entity then
            return false
        end

        local targets = getValidTargetsForAction(action, inputState.selectedEntity)
        for _, target in ipairs(targets) do
            if target == entity then
                if action.id == "aid" and beginAidTriggerTargetSelection(target) then
                    return true
                end
                if isRoughhouseDisplaceSelection(action) and beginRoughhouseDisplaceZoneSelection(target) then
                    return true
                end
                executeSelectedAction(target)
                return true
            end
        end

        print("[COMBAT] Invalid target for action.")
        return false
    end

    function controller:handleArenaEntityClick(data)
        if not data or not data.entity then
            return
        end
        if inputState.awaitingAidTriggerTarget then
            self:handleAidTriggerTargetSelectionByEntity(data.entity)
            return
        end
        if inputState.awaitingTarget then
            self:handleTargetSelectionByEntity(data.entity)
        end
    end

    function controller:handleArenaZoneClick(data)
        if not data or not data.zoneId then
            return
        end
        if inputState.awaitingRoughhouseDisplaceZone then
            self:handleRoughhouseDisplaceZoneSelectionById(data.zoneId)
            return
        end
        if inputState.awaitingZone then
            self:handleZoneSelectionById(data.zoneId)
        end
    end

    function controller:handleInitiativeInput(key)
        local challengeController = gameState.challengeController
        local hand = gameState.playerHand

        if hand.selectedPC and challengeController.awaitingInitiative[hand.selectedPC.id] then
            local cardKeys = { q = 1, w = 2, e = 3, r = 4 }
            if cardKeys[key] then
                local cardIndex = cardKeys[key]
                local card = hand:useForInitiative(hand.selectedPC, cardIndex)
                if card then
                    challengeController:submitInitiative(hand.selectedPC, card)
                    hand:clearSelection()
                else
                    print("[INITIATIVE] Invalid card selection!")
                end
                return
            end

            if key == "escape" then
                hand:clearSelection()
                return
            end
        end

        local keyNum = tonumber(key)
        if keyNum and keyNum >= 1 and keyNum <= 4 then
            local pc = gameState.guild[keyNum]
            if pc and challengeController.awaitingInitiative[pc.id] then
                local cards = hand:getHand(pc)
                if #cards > 0 then
                    hand.selectedPC = pc
                    print("[INITIATIVE] Select a card for " .. pc.name .. " (Q/W/E/R)")

                    for i, card in ipairs(cards) do
                        local keyLetter = ({ "Q", "W", "E", "R" })[i]
                        print("  " .. keyLetter .. ": " .. card.name .. " (" .. card.value .. ")")
                    end
                else
                    print("[INITIATIVE] " .. pc.name .. " has no cards!")
                end
            elseif pc then
                print("[INITIATIVE] " .. pc.name .. " has already submitted initiative")
            end
        end

        if key == "space" then
            for _, pc in ipairs(gameState.guild) do
                if challengeController.awaitingInitiative[pc.id] then
                    local cards = hand:getHand(pc)
                    if #cards > 0 then
                        local card = hand:useForInitiative(pc, 1)
                        if card then
                            challengeController:submitInitiative(pc, card)
                        end
                    end
                end
            end
            hand:clearSelection()
        end
    end

    return controller
end

return M
