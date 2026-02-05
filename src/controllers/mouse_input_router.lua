-- mouse_input_router.lua
-- Routes mouse input with modal-first priority and combat/UI fallthrough.

local M = {}

function M.createMouseInputRouter(config)
    config = config or {}

    local gameState = config.gameState
    assert(gameState, "MouseInputRouter requires gameState")

    local router = {
        gameState = gameState,
    }

    local function handleInspectRightClick(x, y)
        if not gameState.inspectPanel then
            return
        end

        local w, _ = love.graphics.getDimensions()

        if x < 200 then
            local yOffset = 50 + 10
            for i, adventurer in ipairs(gameState.guild) do
                local plateY = yOffset + (i - 1) * 80
                if y >= plateY and y < plateY + 70 then
                    gameState.inspectPanel:show(adventurer, "entity", x, y)
                    return
                end
            end
        end

        if gameState.challengeController and gameState.challengeController:isActive() then
            local npcStartX = w - 220
            local npcStartY = 85
            local npcs = gameState.challengeController.npcs or {}
            for i, npc in ipairs(npcs) do
                local npcY = npcStartY + (i - 1) * 65
                if x >= npcStartX and x < w - 10 and y >= npcY and y < npcY + 60 then
                    gameState.inspectPanel:show(npc, "entity", x, y)
                    return
                end
            end
        end

        gameState.inspectPanel:hide()
    end

    function router:mousepressed(x, y, button)
        if gameState.testOfFateModal and gameState.testOfFateModal.isVisible then
            if gameState.testOfFateModal:mousepressed(x, y, button) then
                return true
            end
        end

        if gameState.lootModal and gameState.lootModal.isOpen then
            if gameState.lootModal:mousepressed(x, y, button) then
                return true
            end
        end

        if gameState.characterSheet and gameState.characterSheet.isOpen then
            if gameState.characterSheet:mousepressed(x, y, button) then
                return true
            end
        end

        if button == 2 and gameState.inspectPanel then
            handleInspectRightClick(x, y)
        end

        if gameState.minorActionPanel and gameState.minorActionPanel.isVisible then
            if gameState.minorActionPanel:mousepressed(x, y, button) then
                return true
            end
        end

        if gameState.commandBoard and gameState.commandBoard.isVisible then
            if gameState.commandBoard:mousepressed(x, y, button) then
                return true
            end
        end

        if gameState.challengeInputController and gameState.challengeController and gameState.challengeController:isActive() then
            if gameState.challengeInputController:handleCombatMousePressed(x, y, button) then
                return true
            end
        end

        if gameState.arenaView and gameState.arenaView.isVisible then
            if gameState.arenaView:mousepressed(x, y, button) then
                return true
            end
        end

        if gameState.currentScreen then
            gameState.currentScreen:mousepressed(x, y, button)
            return true
        end

        return false
    end

    function router:mousereleased(x, y, button)
        if gameState.characterSheet and gameState.characterSheet.isOpen then
            if gameState.characterSheet:mousereleased(x, y, button) then
                return true
            end
        end

        if gameState.arenaView and gameState.arenaView.isVisible then
            if gameState.arenaView:mousereleased(x, y, button) then
                return true
            end
        end

        if gameState.currentScreen then
            gameState.currentScreen:mousereleased(x, y, button)
            return true
        end

        return false
    end

    function router:mousemoved(x, y, dx, dy)
        if gameState.testOfFateModal and gameState.testOfFateModal.isVisible then
            gameState.testOfFateModal:mousemoved(x, y)
            return true
        end

        if gameState.lootModal and gameState.lootModal.isOpen then
            gameState.lootModal:mousemoved(x, y, dx, dy)
            return true
        end

        if gameState.characterSheet and gameState.characterSheet.isOpen then
            gameState.characterSheet:mousemoved(x, y, dx, dy)
            return true
        end

        if gameState.minorActionPanel and gameState.minorActionPanel.isVisible then
            gameState.minorActionPanel:mousemoved(x, y, dx, dy)
        end

        if gameState.commandBoard and gameState.commandBoard.isVisible then
            gameState.commandBoard:mousemoved(x, y, dx, dy)
        end

        if gameState.arenaView and gameState.arenaView.isVisible then
            gameState.arenaView:mousemoved(x, y, dx, dy)
        end

        if gameState.currentScreen then
            gameState.currentScreen:mousemoved(x, y, dx, dy)
            return true
        end

        return false
    end

    return router
end

return M
