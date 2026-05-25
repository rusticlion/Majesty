-- challenge_overlay.lua
-- Draws Challenge-phase HUD and player hand overlays.

local M = {}

function M.createChallengeOverlay(config)
    config = config or {}

    local gameState = config.gameState
    local inputState = config.inputState

    assert(gameState, "ChallengeOverlay requires gameState")
    assert(inputState, "ChallengeOverlay requires inputState")

    local overlay = {
        gameState = gameState,
        inputState = inputState,
    }

    local function getCounterSpellPromptCandidate()
        local pending = inputState.pendingCounterSpellInterrupt
        local candidates = pending and pending.candidates or nil
        if not candidates or #candidates == 0 then
            return nil
        end

        local index = inputState.counterSpellCandidateIndex or 1
        return candidates[index] or candidates[1]
    end

    local function getCounterSpellPrompt()
        local pending = inputState.pendingCounterSpellInterrupt
        if not pending then
            return nil
        end

        local candidate = getCounterSpellPromptCandidate()
        local counterer = candidate and candidate.actor
        local caster = pending.spellCaster
        local countererName = counterer and (counterer.name or counterer.id) or "counterspeller"
        local casterName = caster and (caster.name or caster.id) or "the caster"
        local candidateCount = pending.candidates and #pending.candidates or 0
        local chooser = candidateCount > 1 and ", 1-" .. candidateCount .. " to choose counterspeller" or ""
        return "Counter-spell: Q/W/E/R Wands card for " .. countererName ..
            " against " .. casterName .. chooser .. ", SPACE to skip"
    end

    local function getAmbusherResistancePromptCandidate()
        local pending = inputState.pendingAmbusherResistance
        local candidates = pending and pending.candidates or nil
        if not candidates or #candidates == 0 then
            return nil
        end

        local index = inputState.ambusherResistanceCandidateIndex or 1
        return candidates[index] or candidates[1]
    end

    local function getAmbusherResistancePrompt()
        local pending = inputState.pendingAmbusherResistance
        if not pending then
            return nil
        end

        local candidate = getAmbusherResistancePromptCandidate()
        local actor = candidate and candidate.actor
        local actorName = actor and (actor.name or actor.id) or "Ambusher"
        local candidateCount = pending.candidates and #pending.candidates or 0
        local chooser = candidateCount > 1 and ", 1-" .. candidateCount .. " to choose Ambusher" or ""
        return "Ambusher: R to spend Resolve with " .. actorName ..
            " and cancel surprise" .. chooser .. ", SPACE to skip"
    end

    local function getHeavyMetalMachinePromptCandidate()
        local pending = inputState.pendingHeavyMetalMachineInterrupt
        local candidates = pending and pending.candidates or nil
        if not candidates or #candidates == 0 then
            return nil
        end

        local index = inputState.heavyMetalMachineCandidateIndex or 1
        return candidates[index] or candidates[1]
    end

    local function getHeavyMetalMachinePrompt()
        local pending = inputState.pendingHeavyMetalMachineInterrupt
        if not pending then
            return nil
        end

        local candidate = getHeavyMetalMachinePromptCandidate()
        local defender = candidate and candidate.actor
        local incomingActor = pending.incomingActor
        local defenderName = defender and (defender.name or defender.id) or "armored adventurer"
        local incomingName = incomingActor and (incomingActor.name or incomingActor.id) or "the incoming action"
        local candidateCount = pending.candidates and #pending.candidates or 0
        local chooser = candidateCount > 1 and ", 1-" .. candidateCount .. " to choose defender" or ""
        return "Heavy Metal Machine: Q/W/E/R any card for " .. defenderName ..
            " against " .. incomingName .. chooser .. ", SPACE to skip"
    end

    local function getAegisPromptCandidate()
        local pending = inputState.pendingAegisElection
        local candidates = pending and pending.candidates or nil
        if not candidates or #candidates == 0 then
            return nil
        end

        local index = inputState.aegisCandidateIndex or 1
        return candidates[index] or candidates[1]
    end

    local function getAegisPrompt()
        local pending = inputState.pendingAegisElection
        if not pending then
            return nil
        end

        local candidate = getAegisPromptCandidate()
        local defender = candidate and candidate.actor
        local incomingActor = pending.incomingActor
        local shieldName = candidate and candidate.shield and candidate.shield.name or "shield"
        local defenderName = defender and (defender.name or defender.id) or "shield bearer"
        local incomingName = incomingActor and (incomingActor.name or incomingActor.id) or "the incoming effect"
        local candidateCount = pending.candidates and #pending.candidates or 0
        local chooser = candidateCount > 1 and ", 1-" .. candidateCount .. " to choose defender" or ""
        return "Aegis: A to Notch " .. shieldName .. " for " .. defenderName ..
            " against " .. incomingName .. chooser .. ", SPACE to skip"
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

    local function getWoundChoicePrompt()
        local pending = inputState.pendingWoundChoice
        if not pending then
            return nil
        end

        if inputState.awaitingBerserkergangChoice then
            return "Berserkergang: R to enter rage, SPACE to take the Wound without rage"
        end

        if inputState.awaitingWoundTalentChoice then
            local talentParts = {}
            for i, talentChoice in ipairs(pending.talentChoices or {}) do
                talentParts[#talentParts + 1] = tostring(i) .. " " ..
                    tostring(talentChoice.name or talentChoice.id or "?")
            end
            return "Wound talent: " .. table.concat(talentParts, ", ")
        end

        local parts = {}
        for i, choice in ipairs(pending.choices or {}) do
            parts[#parts + 1] = tostring(i) .. " " .. getWoundChoiceLabel(choice)
        end
        return "Wound: " .. table.concat(parts, ", ")
    end

    local function getAcrobatFallChoicePrompt()
        local pending = inputState.pendingAcrobatFallChoice
        if not pending then
            return nil
        end

        local entity = pending.entity
        local entityName = entity and (entity.name or entity.id) or "Acrobat"
        local without = pending.woundsWithoutAcrobat or "?"
        local with = pending.woundsWithAcrobat or "?"
        return "Acrobat: R spend Resolve with " .. entityName .. " (" ..
            tostring(without) .. " Wound(s) -> " .. tostring(with) ..
            "), SPACE to fall normally"
    end

    local function getRetreatTesterCard(cards, tester, index)
        if type(cards) ~= "table" or not tester then
            return nil
        end
        return cards[tester.role] or cards[tester.actorId] or cards[tester.actorName] or cards[index]
    end

    local function getRetreatGroupTestPrompt()
        local pending = inputState.pendingRetreatGroupTest
        if not pending then
            return nil
        end

        local request = pending.request or (pending.result and pending.result.groupTestRequest) or {}
        local testers = request.testers or {}
        if inputState.awaitingRetreatFavorChoice then
            local parts = {}
            for i, tester in ipairs(testers) do
                parts[#parts + 1] = tostring(i) .. " " .. tostring(tester.actorName or tester.actorId or tester.role)
            end
            return "Retreat: choose clever tactic favor - " .. table.concat(parts, ", ")
        end

        local index = inputState.retreatTestIndex or 1
        local cards = inputState.retreatTestCards or {}
        if getRetreatTesterCard(cards, testers[index], index) then
            for i, tester in ipairs(testers) do
                if not getRetreatTesterCard(cards, tester, i) then
                    index = i
                    break
                end
            end
        end
        local tester = testers[index]
        local name = tester and (tester.actorName or tester.actorId or tester.role) or "adventurer"
        return "Retreat: Q/W/E/R Pentacles test card for " .. name ..
            " (" .. tostring(index) .. "/" .. tostring(#testers) .. ")"
    end

    function overlay:getFooterPrompt(state, activeEntity)
        local woundChoicePrompt = getWoundChoicePrompt()
        if woundChoicePrompt then
            return woundChoicePrompt
        end

        local acrobatFallChoicePrompt = getAcrobatFallChoicePrompt()
        if acrobatFallChoicePrompt then
            return acrobatFallChoicePrompt
        end

        local retreatPrompt = getRetreatGroupTestPrompt()
        if retreatPrompt then
            return retreatPrompt
        end

        local ambusherResistancePrompt = getAmbusherResistancePrompt()
        if ambusherResistancePrompt then
            return ambusherResistancePrompt
        end

        local counterSpellPrompt = getCounterSpellPrompt()
        if counterSpellPrompt then
            return counterSpellPrompt
        end

        local heavyMetalMachinePrompt = getHeavyMetalMachinePrompt()
        if heavyMetalMachinePrompt then
            return heavyMetalMachinePrompt
        end

        local aegisPrompt = getAegisPrompt()
        if aegisPrompt then
            return aegisPrompt
        end

        if inputState.counselActive then
            if inputState.awaitingCounselActor then
                local count = inputState.counselCandidates and #inputState.counselCandidates or 0
                return "Counsel: select counselor (1-" .. count .. "), ESC to cancel"
            elseif inputState.awaitingCounselCard then
                return "Counsel: select card to give (Q/W/E/R), ESC to cancel"
            elseif inputState.awaitingCounselAction then
                local count = inputState.counselActionOptions and #inputState.counselActionOptions or 0
                return "Counsel: select advised action (1-" .. count .. "), ESC to cancel"
            elseif inputState.awaitingCounselTarget then
                local count = inputState.counselTargetCandidates and #inputState.counselTargetCandidates or 0
                return "Counsel: select recipient (1-" .. count .. "), ESC to cancel"
            elseif inputState.awaitingCounselResolveChoice then
                return "Counsel: R to spend Resolve for interrupt, SPACE for normal advice"
            end
        end

        if inputState.awaitingQuickInterruptActor then
            local count = inputState.quickInterruptCandidates and #inputState.quickInterruptCandidates or 0
            return "Quick!: select adventurer (1-" .. count .. "), ESC to cancel"
        end

        if inputState.quickInterruptActor and not inputState.selectedCard then
            return "Quick!: select Pentacles card for " ..
                (inputState.quickInterruptActor.name or inputState.quickInterruptActor.id) .. " (Q/W/E/R), ESC to cancel"
        end

        if inputState.quickInterruptActive and inputState.selectedCard then
            return "Quick!: choose a Pentacles action from Command Board, ESC to cancel"
        end

        if state == "awaiting_action" and activeEntity and activeEntity.isPC then
            if inputState.awaitingFoolFollowUpCard then
                return "Select follow-up card for The Fool (Q/W/E), ESC to cancel"
            elseif inputState.awaitingRoughhouseDisplaceZone then
                local zones = inputState.availableZones or {}
                return "Select displacement zone (1-" .. #zones .. "), ESC to cancel"
            elseif inputState.awaitingZone then
                local zones = inputState.availableZones or {}
                return "Select destination zone (1-" .. #zones .. "), ESC to cancel"
            elseif inputState.awaitingTarget then
                return "Select target (1-N), ESC to cancel"
            elseif inputState.selectedCard then
                return "Choose action from Command Board, ESC to cancel"
            else
                return "Press Q/W/E to select card, H for hand info, C for Counsel, K for Quick!, SPACE to pass"
            end
        end

        if state == "minor_window" then
            if inputState.awaitingFoolFollowUpCard then
                return "Select follow-up card for The Fool (Q/W/E), ESC to cancel"
            elseif inputState.awaitingRoughhouseDisplaceZone then
                local zones = inputState.availableZones or {}
                return "Select displacement zone (1-" .. #zones .. ") for minor action, ESC to cancel"
            elseif inputState.awaitingTarget then
                return "Select target (1-N) for minor action, ESC to cancel"
            elseif inputState.awaitingZone then
                local zones = inputState.availableZones or {}
                return "Select destination zone (1-" .. #zones .. ") for minor action, ESC to cancel"
            elseif inputState.selectedCard then
                return "Choose action from Command Board, ESC to cancel"
            elseif inputState.minorPC then
                return "Press Q/W/E to select card for " .. inputState.minorPC.name .. ", ESC to cancel"
            else
                return "Press 1-4 to select PC for minor action, C for Counsel, K for Quick!, SPACE to resume"
            end
        end

        if state == "pre_round" then
            return "Press 1-4 to submit initiative cards for each guild member"
        end

        if state == "count_up" then
            return "Press C for Counsel or K for Quick! interrupt"
        end

        return nil
    end

    local function drawPlayerHand(pc)
        local hand = gameState.playerHand
        local cards = hand:getHand(pc)
        local w, h = love.graphics.getDimensions()

        if #cards == 0 then
            return
        end

        local cardWidth = 100
        local cardHeight = 140
        local cardSpacing = 20
        local totalWidth = (#cards * cardWidth) + ((#cards - 1) * cardSpacing)
        local startX = (w - totalWidth) / 2
        local startY = h - cardHeight - 70

        local mouseX, mouseY = love.mouse.getPosition()

        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", startX - 10, startY - 30, totalWidth + 20, cardHeight + 60, 8, 8)

        love.graphics.setColor(0.9, 0.9, 0.9, 1)
        love.graphics.print(pc.name .. "'s Hand", startX, startY - 25)

        local keyLetters = { "Q", "W", "E", "R" }
        for i, card in ipairs(cards) do
            local x = startX + (i - 1) * (cardWidth + cardSpacing)
            local y = startY

            local isSelected = (inputState.selectedCardIndex == i and inputState.selectedEntity == pc)
            local isHovered = mouseX >= x and mouseX < x + cardWidth and mouseY >= y and mouseY < y + cardHeight
            local isFoolTrigger = inputState.awaitingFoolFollowUpCard and
                inputState.foolCardIndex == i and inputState.selectedEntity == pc
            local isGrayed = isFoolTrigger

            local suitColors = {
                [1] = { 0.8, 0.3, 0.3 },
                [2] = { 0.3, 0.7, 0.3 },
                [3] = { 0.3, 0.5, 0.9 },
                [4] = { 0.8, 0.6, 0.2 },
            }
            local bgColor = suitColors[card.suit] or { 0.5, 0.4, 0.6 }

            local alpha = 0.9
            if isGrayed then
                bgColor = { 0.35, 0.35, 0.35 }
                alpha = 0.6
            end

            if isSelected or isFoolTrigger then
                love.graphics.setColor(1, 0.9, 0.3, 0.6)
                love.graphics.rectangle("fill", x - 4, y - 4, cardWidth + 8, cardHeight + 8, 8, 8)
            end

            love.graphics.setColor(bgColor[1], bgColor[2], bgColor[3], alpha)
            love.graphics.rectangle("fill", x, y, cardWidth, cardHeight, 6, 6)

            if isHovered and not isSelected then
                love.graphics.setColor(1, 1, 1, 0.3)
                love.graphics.rectangle("fill", x, y, cardWidth, cardHeight, 6, 6)
            end

            if isSelected or isFoolTrigger then
                love.graphics.setColor(1, 0.85, 0.2, 1)
                love.graphics.setLineWidth(3)
            elseif isHovered then
                love.graphics.setColor(1, 1, 1, 0.9)
                love.graphics.setLineWidth(2)
            else
                love.graphics.setColor(0.2, 0.2, 0.2, 1)
                love.graphics.setLineWidth(1)
            end
            love.graphics.rectangle("line", x, y, cardWidth, cardHeight, 6, 6)
            love.graphics.setLineWidth(1)

            local promptColor = isHovered and { 1, 1, 0.5, 1 } or { 1, 1, 0, 1 }
            if isGrayed then
                promptColor = { 0.5, 0.5, 0.5, 0.7 }
            end
            love.graphics.setColor(promptColor)
            love.graphics.print("[" .. keyLetters[i] .. "]", x + cardWidth / 2 - 10, y + 5)

            local textColor = isGrayed and { 0.6, 0.6, 0.6, 1 } or { 1, 1, 1, 1 }
            love.graphics.setColor(textColor)
            love.graphics.print(tostring(card.value or "?"), x + cardWidth / 2 - 5, y + 25)

            love.graphics.setColor(isGrayed and { 0.5, 0.5, 0.5, 1 } or { 0.9, 0.9, 0.9, 1 })
            local suitName = hand:getSuitName(card.suit)
            love.graphics.print(suitName, x + 5, y + 55)

            local cardName = card.name or "Unknown"
            if #cardName > 12 then
                cardName = string.sub(cardName, 1, 10) .. ".."
            end
            love.graphics.print(cardName, x + 5, y + 75)

            local actionInfo = hand:getActionsForCard(card)
            if actionInfo then
                love.graphics.setColor(0.7, 0.7, 0.7, 1)
                love.graphics.print(actionInfo.primary, x + 5, y + cardHeight - 25)
            end
        end
    end

    function overlay:draw()
        local controller = gameState.challengeController
        local w, h = love.graphics.getDimensions()
        local state = controller:getState()

        love.graphics.setColor(0.2, 0, 0, 0.8)
        love.graphics.rectangle("fill", 0, 0, w, 80)

        if state == "pre_round" then
            love.graphics.setColor(1, 0.8, 0.2, 1)
            love.graphics.print("=== INITIATIVE PHASE ===", w / 2 - 100, 10)

            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print("Round " .. controller:getCurrentRound(), w / 2 - 30, 35)

            love.graphics.setColor(0.8, 0.8, 0.8, 1)
            local yOffset = 55
            for i, pc in ipairs(gameState.guild) do
                local submitted = not controller.awaitingInitiative[pc.id]
                local status = submitted and "[Ready]" or "[Press " .. i .. "]"
                local color = submitted and { 0.3, 1, 0.3, 1 } or { 1, 1, 0.3, 1 }
                love.graphics.setColor(color)
                love.graphics.print(i .. ". " .. pc.name .. " " .. status, 20 + (i - 1) * 150, yOffset)
            end

            love.graphics.setColor(1, 1, 0, 1)
            love.graphics.print("Press 1-4 to submit initiative cards for each guild member", 20, h - 50)
        else
            love.graphics.setColor(1, 0.3, 0.3, 1)
            love.graphics.print("=== CHALLENGE PHASE ===", w / 2 - 100, 10)

            love.graphics.setColor(1, 1, 1, 1)
            local countText = string.format("Round %d | Count: %d / %d",
                controller:getCurrentRound(),
                controller:getCurrentCount(),
                controller:getMaxTurns())
            love.graphics.print(countText, w / 2 - 70, 35)

            local activeEntity = controller:getActiveEntity()
            if activeEntity then
                local actorName = activeEntity.name or "Unknown"
                local isPC = activeEntity.isPC

                love.graphics.setColor(isPC and { 0.3, 1, 0.3, 1 } or { 1, 0.3, 0.3, 1 })
                love.graphics.print(actorName .. "'s turn (" .. state .. ")", 20, 55)

                local slot = controller:getInitiativeSlot(activeEntity.id)
                if slot and slot.revealed then
                    love.graphics.setColor(0.9, 0.85, 0.7, 1)
                    love.graphics.print("Initiative: " .. slot.value, 20, 35)
                end

                if isPC and state == "awaiting_action" and
                   not inputState.pendingCounterSpellInterrupt and
                   not inputState.pendingHeavyMetalMachineInterrupt and
                   not inputState.pendingAegisElection and
                   not inputState.awaitingQuickInterruptActor and not inputState.quickInterruptActor and
                   not inputState.counselActive then
                    drawPlayerHand(activeEntity)

                    love.graphics.setColor(1, 1, 0, 1)
                    love.graphics.print(self:getFooterPrompt(state, activeEntity), 20, h - 50)
                end
            end

            if inputState.pendingCounterSpellInterrupt then
                local candidate = getCounterSpellPromptCandidate()
                local counterer = candidate and candidate.actor
                local pending = inputState.pendingCounterSpellInterrupt
                local caster = pending.spellCaster

                love.graphics.setColor(0.05, 0.06, 0.08, 0.88)
                love.graphics.rectangle("fill", 0, 82, w, 54)

                love.graphics.setColor(0.9, 0.85, 0.45, 1)
                love.graphics.print("COUNTER-SPELL WINDOW", 20, 92)

                love.graphics.setColor(1, 1, 1, 1)
                local line = (counterer and (counterer.name or counterer.id) or "Counterspeller") ..
                    " may interrupt " .. (caster and (caster.name or caster.id) or "the caster")
                love.graphics.print(line, 20, 114)

                if counterer then
                    drawPlayerHand(counterer)
                end

                love.graphics.setColor(1, 1, 0, 1)
                love.graphics.print(self:getFooterPrompt(state, activeEntity), 20, h - 50)
            end

            if inputState.pendingHeavyMetalMachineInterrupt then
                local candidate = getHeavyMetalMachinePromptCandidate()
                local defender = candidate and candidate.actor
                local pending = inputState.pendingHeavyMetalMachineInterrupt
                local incomingActor = pending.incomingActor

                love.graphics.setColor(0.08, 0.07, 0.05, 0.9)
                love.graphics.rectangle("fill", 0, 82, w, 54)

                love.graphics.setColor(0.95, 0.78, 0.35, 1)
                love.graphics.print("HEAVY METAL MACHINE", 20, 92)

                love.graphics.setColor(1, 1, 1, 1)
                local line = (defender and (defender.name or defender.id) or "Armored adventurer") ..
                    " may boost Initiative against " ..
                    (incomingActor and (incomingActor.name or incomingActor.id) or "the incoming action")
                love.graphics.print(line, 20, 114)

                if defender then
                    drawPlayerHand(defender)
                end

                love.graphics.setColor(1, 1, 0, 1)
                love.graphics.print(self:getFooterPrompt(state, activeEntity), 20, h - 50)
            end

            if inputState.pendingAegisElection then
                local candidate = getAegisPromptCandidate()
                local defender = candidate and candidate.actor
                local pending = inputState.pendingAegisElection
                local incomingActor = pending.incomingActor
                local shieldName = candidate and candidate.shield and candidate.shield.name or "shield"

                love.graphics.setColor(0.05, 0.07, 0.06, 0.9)
                love.graphics.rectangle("fill", 0, 82, w, 54)

                love.graphics.setColor(0.55, 0.95, 0.65, 1)
                love.graphics.print("AEGIS", 20, 92)

                love.graphics.setColor(1, 1, 1, 1)
                local line = (defender and (defender.name or defender.id) or "Shield bearer") ..
                    " may Notch " .. shieldName .. " against " ..
                    (incomingActor and (incomingActor.name or incomingActor.id) or "the incoming effect")
                love.graphics.print(line, 20, 114)

                love.graphics.setColor(1, 1, 0, 1)
                love.graphics.print(self:getFooterPrompt(state, activeEntity), 20, h - 50)
            end

            if inputState.counselActive then
                love.graphics.setColor(0.06, 0.04, 0.08, 0.9)
                love.graphics.rectangle("fill", 0, 138, w, 58)

                love.graphics.setColor(0.85, 0.65, 1, 1)
                love.graphics.print("COUNSEL", 20, 148)

                love.graphics.setColor(1, 1, 1, 1)
                if inputState.awaitingCounselActor then
                    local x = 20
                    for i, actor in ipairs(inputState.counselCandidates or {}) do
                        love.graphics.print(i .. ". " .. (actor.name or actor.id), x, 170)
                        x = x + 180
                    end
                elseif inputState.awaitingCounselCard and inputState.counselActor then
                    love.graphics.print((inputState.counselActor.name or inputState.counselActor.id) ..
                        " gives advice", 20, 170)
                    drawPlayerHand(inputState.counselActor)
                elseif inputState.awaitingCounselAction then
                    local x = 20
                    for i, action in ipairs(inputState.counselActionOptions or {}) do
                        love.graphics.print(i .. ". " .. (action.name or action.id), x, 170)
                        x = x + 170
                    end
                elseif inputState.awaitingCounselTarget then
                    local x = 20
                    for i, target in ipairs(inputState.counselTargetCandidates or {}) do
                        love.graphics.print(i .. ". " .. (target.name or target.id), x, 170)
                        x = x + 180
                    end
                elseif inputState.awaitingCounselResolveChoice then
                    local target = inputState.counselTarget
                    local action = inputState.counselAction
                    love.graphics.print("Advise " .. (target and (target.name or target.id) or "recipient") ..
                        " to use " .. (action and (action.name or action.id) or "the card"), 20, 170)
                end

                love.graphics.setColor(1, 1, 0, 1)
                love.graphics.print(self:getFooterPrompt(state, activeEntity), 20, h - 50)
            end

            if inputState.awaitingQuickInterruptActor or inputState.quickInterruptActor then
                love.graphics.setColor(0.04, 0.08, 0.08, 0.88)
                love.graphics.rectangle("fill", 0, 138, w, 58)

                love.graphics.setColor(0.45, 0.9, 0.8, 1)
                love.graphics.print("QUICK! INTERRUPT", 20, 148)

                if inputState.awaitingQuickInterruptActor then
                    love.graphics.setColor(1, 1, 1, 1)
                    local candidates = inputState.quickInterruptCandidates or {}
                    local x = 20
                    for i, actor in ipairs(candidates) do
                        love.graphics.print(i .. ". " .. (actor.name or actor.id), x, 170)
                        x = x + 180
                    end
                elseif inputState.quickInterruptActor then
                    love.graphics.setColor(1, 1, 1, 1)
                    love.graphics.print((inputState.quickInterruptActor.name or inputState.quickInterruptActor.id) ..
                        " may act with a Pentacles interrupt", 20, 170)
                    drawPlayerHand(inputState.quickInterruptActor)
                end

                love.graphics.setColor(1, 1, 0, 1)
                love.graphics.print(self:getFooterPrompt(state, activeEntity), 20, h - 50)
            end

            if state == "minor_window" and
               not inputState.pendingCounterSpellInterrupt and
               not inputState.pendingHeavyMetalMachineInterrupt and
               not inputState.pendingAegisElection and
               not inputState.awaitingQuickInterruptActor and not inputState.quickInterruptActor and
               not inputState.counselActive then
                love.graphics.setColor(0.8, 0.6, 0.2, 1)
                love.graphics.print("=== MINOR ACTION WINDOW ===", w / 2 - 120, 55)

                love.graphics.setColor(0.8, 0.8, 0.8, 1)
                local hand = gameState.playerHand
                for i, pc in ipairs(gameState.guild) do
                    local cards = hand:getHand(pc)
                    local cardCount = #cards
                    local status = cardCount > 0 and string.format("[%d cards]", cardCount) or "[no cards]"
                    local color = cardCount > 0 and { 0.7, 1, 0.7, 1 } or { 0.5, 0.5, 0.5, 1 }
                    love.graphics.setColor(color)
                    love.graphics.print(i .. ". " .. pc.name .. " " .. status, 20 + (i - 1) * 160, 55)
                end

                if inputState.minorPC then
                    drawPlayerHand(inputState.minorPC)
                end

                love.graphics.setColor(1, 1, 0, 1)
                love.graphics.print(self:getFooterPrompt(state, nil), 20, h - 50)
            end
        end

        if state == "count_up" and not inputState.awaitingQuickInterruptActor and
           not inputState.quickInterruptActor and not inputState.counselActive then
            love.graphics.setColor(1, 1, 0, 1)
            love.graphics.print(self:getFooterPrompt(state, nil), 20, h - 50)
        end

        if state == "pre_round" then
            local hand = gameState.playerHand
            if hand.selectedPC then
                drawPlayerHand(hand.selectedPC)
                love.graphics.setColor(1, 1, 0, 1)
                love.graphics.print("Press Q/W/E/R to select initiative card, ESC to cancel, SPACE for auto-all", 20, h - 50)
            end
        end

        local combatDsp = gameState.combatDisplay
        if state == "count_up" or state == "awaiting_action" or state == "resolving" then
            local barWidth = w - 40
            combatDsp:drawCountUpBar(20, h - 30, barWidth, controller:getCurrentCount(), controller:getMaxTurns())
        end
    end

    return overlay
end

return M
