-- watch_manager.lua
-- Watch Manager & Movement Logic for Majesty
-- Ticket T2_2: Time tracking via Watches, triggers Meatgrinder
--
-- Design: Uses events for loose coupling. WatchManager fires events,
-- other systems (Light, Inventory) subscribe and respond.

local events = require('logic.events')

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
    }

    ----------------------------------------------------------------------------
    -- MEATGRINDER DRAW
    -- Draws from GM deck and categorizes result
    ----------------------------------------------------------------------------

    --- Draw from Meatgrinder (GM deck) and emit appropriate event
    -- @return table: { card, category, value }
    function manager:drawMeatgrinder()
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
        }

        -- Emit the general meatgrinder event
        self.eventBus:emit(events.EVENTS.MEATGRINDER_ROLL, result)

        -- Emit category-specific event
        if category == M.MEATGRINDER.TORCHES_GUTTER then
            self.eventBus:emit(events.EVENTS.TORCHES_GUTTER, result)
        elseif category == M.MEATGRINDER.RANDOM_ENCOUNTER then
            self.eventBus:emit(events.EVENTS.RANDOM_ENCOUNTER, result)
        elseif category == M.MEATGRINDER.CURIOSITY then
            self.eventBus:emit(events.EVENTS.CURIOSITY, result)
        elseif category == M.MEATGRINDER.TRAVEL_EVENT then
            self.eventBus:emit(events.EVENTS.TRAVEL_EVENT, result)
        elseif category == M.MEATGRINDER.QUEST_RUMOR then
            self.eventBus:emit(events.EVENTS.QUEST_RUMOR, result)
        end

        -- Discard the card
        self.gmDeck:discard(card)

        return result
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
            meatgrinderResults = {},
        }

        -- Draw from Meatgrinder
        local firstDraw = self:drawMeatgrinder()
        if firstDraw then
            results.meatgrinderResults[#results.meatgrinderResults + 1] = firstDraw
        end

        -- "Moving Carefully" (p. 91): Draw again, keep if torches gutter
        if options.careful and firstDraw then
            local secondDraw = self:drawMeatgrinder()
            if secondDraw then
                if secondDraw.category == M.MEATGRINDER.TORCHES_GUTTER then
                    -- Keep the torches gutter result
                    results.meatgrinderResults[#results.meatgrinderResults + 1] = secondDraw
                    results.carefulTorchesGutter = true
                end
                -- Otherwise second draw is ignored (but card was still drawn/discarded)
            end
        end

        -- Emit watch passed event
        self.eventBus:emit(events.EVENTS.WATCH_PASSED, {
            watchNumber = self.watchCount,
            careful     = options.careful or false,
            results     = results.meatgrinderResults,
        })

        return results
    end

    ----------------------------------------------------------------------------
    -- LOUD NOISE
    -- Special Meatgrinder check - only triggers on random encounter
    ----------------------------------------------------------------------------

    --- Check for encounters due to loud noise
    -- @return table: { triggered, result } - triggered is true if encounter occurs
    function manager:checkLoudNoise()
        local draw = self:drawMeatgrinder()

        if draw and draw.category == M.MEATGRINDER.RANDOM_ENCOUNTER then
            return { triggered = true, result = draw }
        end

        return { triggered = false, result = draw }
    end

    ----------------------------------------------------------------------------
    -- PARTY MOVEMENT
    -- Updates location of all guild members and advances watch
    ----------------------------------------------------------------------------

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
        end

        local previousRoom = self.currentRoom

        -- Update party location
        self.currentRoom = targetRoomId

        -- Update each guild member's location
        for _, member in ipairs(self.guild) do
            member.location = targetRoomId
        end

        -- Emit room entered event
        self.eventBus:emit(events.EVENTS.ROOM_ENTERED, {
            roomId   = targetRoomId,
            room     = targetRoom,
            previous = previousRoom,
        })

        -- Increment the watch (triggers Meatgrinder)
        local watchResult = self:incrementWatch({ careful = options.careful })

        -- Emit party moved event
        self.eventBus:emit(events.EVENTS.PARTY_MOVED, {
            from        = previousRoom,
            to          = targetRoomId,
            watchNumber = watchResult.watchNumber,
        })

        return true, {
            watchResult  = watchResult,
            previousRoom = previousRoom,
            newRoom      = targetRoomId,
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
