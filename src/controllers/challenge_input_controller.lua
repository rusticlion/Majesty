-- challenge_input_controller.lua
-- Encapsulates Challenge-phase input flow:
-- card select -> action select -> target/zone select -> execute

local events = require('logic.events')

local M = {}

local function createDefaultInputState()
    return {
        selectedCard = nil,
        selectedCardIndex = nil,
        selectedEntity = nil,
        selectedAction = nil,
        awaitingTarget = false,
        awaitingZone = false,
        availableZones = nil,
        minorPC = nil,
        selectedVigilanceFollowUp = nil,
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

    local function resetCombatInputState()
        inputState.selectedCard = nil
        inputState.selectedCardIndex = nil
        inputState.selectedEntity = nil
        inputState.selectedAction = nil
        inputState.awaitingTarget = false
        inputState.awaitingZone = false
        inputState.availableZones = nil
        inputState.minorPC = nil
        inputState.selectedVigilanceFollowUp = nil
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

    local function getValidTargetsForAction(action, actor)
        local challengeController = gameState.challengeController
        local actorZone = actor and actor.zone

        if not action then
            return {}
        end

        local isMelee = (action.id == "melee" or action.id == "grapple" or
            action.id == "trip" or action.id == "disarm" or
            action.id == "displace")

        local targets = {}

        local function addIfValid(entity)
            if not (entity.conditions and entity.conditions.dead) then
                if isMelee then
                    if entity.zone == actorZone then
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

    local function getAvailableDestinationZones(actor)
        local challengeController = gameState.challengeController
        local zones = (challengeController and challengeController.zones) or {}
        local currentZone = actor and actor.zone
        local zoneSystem = gameState.zoneRegistry or (challengeController and challengeController.zoneSystem)

        local availableZones = {}
        for _, zone in ipairs(zones) do
            if zone.id ~= currentZone then
                local isAdjacent = true
                if zoneSystem and currentZone and zoneSystem.getZone and zoneSystem.areZonesAdjacent then
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

    local function executeSelectedAction(target, destinationZone)
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

        local isMinor = (state == "minor_window")

        if isMinor then
            local cards = hand:getHand(entity)
            table.remove(cards, cardIndex)
            gameState.playerDeck:discard(card)

            challengeController:declareMinorAction(entity, card, {
                type = action.id,
                target = target,
                destinationZone = destinationZone,
                weapon = entity.inventory and entity.inventory:getWieldedWeapon() or nil,
                allEntities = challengeController.allCombatants,
            })

            print("[MINOR] " .. entity.name .. " declares " .. action.name)
            inputState.minorPC = nil
        else
            local fullAction = {
                actor = entity,
                target = target,
                card = card,
                type = action.id,
                destinationZone = destinationZone,
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

                fullAction.trigger = {
                    mode = "targeted_by_hostile_action",
                    target = "self",
                    hostileOnly = true,
                    excludeSelf = true,
                }
                fullAction.followUpAction = followUpAction.id
                fullAction.followUpTargetPolicy = getVigilanceFollowUpTargetPolicy(followUpAction)

                print("[VIGILANCE] " .. entity.name .. " prepares " .. followUpAction.name ..
                      " when targeted by a hostile action.")
            elseif destinationZone then
                print("[COMBAT] " .. entity.name .. " uses " .. action.name .. " to move to " .. destinationZone)
            else
                print("[COMBAT] " .. entity.name .. " uses " .. action.name .. " on " .. (target and target.name or "no target"))
            end

            local success, err = challengeController:submitAction(fullAction)
            if not success then
                print("[COMBAT] Action submit failed: " .. tostring(err))
                resetCombatInputState()
                eventBus:emit("card_deselected", {})
                return
            end

            local cards = hand:getHand(entity)
            table.remove(cards, cardIndex)
            gameState.playerDeck:discard(card)
        end

        resetCombatInputState()
        eventBus:emit("card_deselected", {})
    end

    function controller:getState()
        return self.inputState
    end

    function controller:resetInputState()
        resetCombatInputState()
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
        end)
    end

    function controller:handleActionSelected(data)
        if not data or not data.action then
            return
        end

        inputState.selectedAction = data.action

        if data.action.id == "vigilance" then
            if not data.followUpAction then
                print("[VIGILANCE] Select follow-up action from Command Board.")
                resetCombatInputState()
                eventBus:emit("card_deselected", {})
                return
            end

            inputState.selectedVigilanceFollowUp = data.followUpAction
            executeSelectedAction(nil)
            return
        end

        if data.action.id == "move" or data.action.id == "dash" or data.action.id == "avoid" then
            local availableZones = getAvailableDestinationZones(inputState.selectedEntity)

            if #availableZones > 0 then
                inputState.awaitingZone = true
                inputState.availableZones = availableZones

                if data.action.id == "avoid" then
                    print("[COMBAT] Select adjacent destination zone (1-" .. #availableZones .. "), or press Space to avoid in place:")
                else
                    print("[COMBAT] Select adjacent destination zone (1-" .. #availableZones .. "):")
                end
                for i, zone in ipairs(availableZones) do
                    print("  " .. i .. ": " .. zone.name)
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

        if data.action.requiresTarget then
            inputState.awaitingTarget = true
            local targets = getValidTargetsForAction(data.action, inputState.selectedEntity)
            local isMelee = (data.action.id == "melee" or data.action.id == "grapple" or
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

            print("[COMBAT] Select target (1-" .. #targets .. "):")
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

        local cardIndex = getHandCardIndexAt(x, y, activeEntity, 3)
        if cardIndex then
            selectCardForAction(activeEntity, cardIndex, true)
            print("[COMBAT] " .. activeEntity.name .. " selected a card - choose action from Command Board")
            return true
        end

        return false
    end

    function controller:handleChallengeInput(key)
        local challengeController = gameState.challengeController
        local hand = gameState.playerHand
        local challengeState = challengeController:getState()

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

        if inputState.awaitingZone then
            self:handleZoneSelection(key)
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
                selectCardForAction(activeEntity, cardIndex, true)
                print("[COMBAT] " .. activeEntity.name .. " selected " .. card.name .. " - choose action from Command Board")
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
            resetCombatInputState()
            eventBus:emit(events.EVENTS.UI_SEQUENCE_COMPLETE, {})
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

        if inputState.awaitingTarget then
            self:handleTargetSelection(key)
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
                    selectCardForAction(inputState.minorPC, cardIndex, false)
                    print("[MINOR] " .. inputState.minorPC.name .. " selected " .. card.name .. " for minor action")
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

    function controller:handleTargetSelection(key)
        local action = inputState.selectedAction

        if not action then
            inputState.awaitingTarget = false
            return
        end

        local targets = getValidTargetsForAction(action, inputState.selectedEntity)

        local keyNum = tonumber(key)
        if keyNum and keyNum >= 1 and keyNum <= #targets then
            local target = targets[keyNum]
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

    function controller:handleTargetSelectionByEntity(entity)
        local action = inputState.selectedAction
        if not action or not entity then
            return false
        end

        local targets = getValidTargetsForAction(action, inputState.selectedEntity)
        for _, target in ipairs(targets) do
            if target == entity then
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
        if inputState.awaitingTarget then
            self:handleTargetSelectionByEntity(data.entity)
        end
    end

    function controller:handleArenaZoneClick(data)
        if not data or not data.zoneId then
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
