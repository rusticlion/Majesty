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
            local isGrayed = false

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

            if isSelected then
                love.graphics.setColor(1, 0.9, 0.3, 0.6)
                love.graphics.rectangle("fill", x - 4, y - 4, cardWidth + 8, cardHeight + 8, 8, 8)
            end

            love.graphics.setColor(bgColor[1], bgColor[2], bgColor[3], alpha)
            love.graphics.rectangle("fill", x, y, cardWidth, cardHeight, 6, 6)

            if isHovered and not isSelected then
                love.graphics.setColor(1, 1, 1, 0.3)
                love.graphics.rectangle("fill", x, y, cardWidth, cardHeight, 6, 6)
            end

            if isSelected then
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

                if isPC and state == "awaiting_action" then
                    drawPlayerHand(activeEntity)

                    love.graphics.setColor(1, 1, 0, 1)
                    if inputState.awaitingZone then
                        local zones = inputState.availableZones or {}
                        love.graphics.print("Select destination zone (1-" .. #zones .. "), ESC to cancel", 20, h - 50)
                    elseif inputState.awaitingTarget then
                        love.graphics.print("Select target (1-N), ESC to cancel", 20, h - 50)
                    elseif inputState.selectedCard then
                        love.graphics.print("Choose action from Command Board, ESC to cancel", 20, h - 50)
                    else
                        love.graphics.print("Press Q/W/E to select card, H for hand info, SPACE to pass", 20, h - 50)
                    end
                end
            end

            if state == "minor_window" then
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
                if inputState.awaitingTarget then
                    love.graphics.print("Select target (1-N) for minor action, ESC to cancel", 20, h - 50)
                elseif inputState.selectedCard then
                    love.graphics.print("Choose action from Command Board, ESC to cancel", 20, h - 50)
                elseif inputState.minorPC then
                    love.graphics.print("Press Q/W/E to select card for " .. inputState.minorPC.name .. ", ESC to cancel", 20, h - 50)
                else
                    love.graphics.print("Press 1-4 to select PC for minor action, SPACE to resume", 20, h - 50)
                end
            end
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
