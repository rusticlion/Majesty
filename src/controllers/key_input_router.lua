-- key_input_router.lua
-- Routes keyboard input with modal-first priority, then debug/gameplay keys.

local M = {}

function M.createKeyInputRouter(config)
    config = config or {}

    local gameState = config.gameState
    local showEndOfDemoScreen = config.showEndOfDemoScreen
    local challengeVictoryOutcome = config.challengeVictoryOutcome or "victory"

    assert(gameState, "KeyInputRouter requires gameState")
    assert(showEndOfDemoScreen, "KeyInputRouter requires showEndOfDemoScreen callback")

    local router = {
        gameState = gameState,
        showEndOfDemoScreen = showEndOfDemoScreen,
        challengeVictoryOutcome = challengeVictoryOutcome,
    }

    function router:keypressed(key)
        if gameState.testOfFateModal and gameState.testOfFateModal.isVisible then
            if gameState.testOfFateModal:keypressed(key) then
                return true
            end
        end

        if gameState.lootModal and gameState.lootModal.isOpen then
            if gameState.lootModal:keypressed(key) then
                return true
            end
        end

        if gameState.characterSheet then
            if gameState.characterSheet:keypressed(key) then
                return true
            end
        end

        if gameState.minorActionPanel and gameState.minorActionPanel.isVisible then
            if gameState.minorActionPanel:keypressed(key) then
                return true
            end
        end

        if gameState.commandBoard and gameState.commandBoard.isVisible then
            if gameState.commandBoard:keypressed(key) then
                return true
            end
        end

        if key == "escape" then
            love.event.quit()
        end

        if key == "d" then
            local result = gameState.watchManager:drawMeatgrinder()
            if result then
                print("Drew: " .. result.card.name .. " (" .. result.value .. ") - " .. result.category)
            end
        end

        if key == "m" then
            local result = gameState.watchManager:incrementWatch()
            print("Watch " .. result.watchNumber .. " passed")
        end

        if key == "f9" and gameState.challengeController:isActive() then
            print("=== DEBUG: AUTO-WIN COMBAT ===")
            gameState.challengeController:endChallenge(challengeVictoryOutcome, {
                debugWin = true,
            })
        end

        if key == "x" and gameState.phase == "crawl" and not gameState.challengeController:isActive() then
            local currentRoom = gameState.watchManager:getCurrentRoom()
            if currentRoom == "101_entrance" then
                showEndOfDemoScreen("exited")
            else
                print("[EXIT] You can only exit from the entrance room!")
            end
        end

        if gameState.challengeInputController and gameState.challengeController and gameState.challengeController:isActive() then
            gameState.challengeInputController:handleChallengeInput(key)
            return true
        end

        if gameState.currentScreen then
            gameState.currentScreen:keypressed(key)
            return true
        end

        return false
    end

    return router
end

return M
