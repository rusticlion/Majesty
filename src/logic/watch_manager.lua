-- watch_manager.lua
-- Watch Manager & Movement Logic for Majesty
-- Ticket T2_2: Time tracking via Watches, triggers Meatgrinder
--
-- Design: Uses events for loose coupling. WatchManager fires events,
-- other systems (Light, Inventory) subscribe and respond.

local events = require('logic.events')
local entity_factory = require('entities.factory')

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
    }

    if manager.currentRoom then
        manager.roomsTraveledSinceLastMap[#manager.roomsTraveledSinceLastMap + 1] = manager.currentRoom
    end

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
            deathDoorExpired   = {},
            undeadRaised       = {},
            conditionsExpired  = {},
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
        end

        results.undeadRaised = self:raiseScheduledUndead()
        results.deathDoorExpired = self:expireDeathsDoorMembers()
        results.conditionsExpired = self:clearWatchDurationConditions()

        -- Emit watch passed event
        self.eventBus:emit(events.EVENTS.WATCH_PASSED, {
            watchNumber      = self.watchCount,
            careful          = options.careful or false,
            results          = results.meatgrinderResults,
            deathDoorExpired = results.deathDoorExpired,
            undeadRaised     = results.undeadRaised,
            conditionsExpired = results.conditionsExpired,
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

        if draw and isLoudNoiseEncounterValue(draw.value) then
            draw.loudNoiseEncounter = true
            if draw.category ~= M.MEATGRINDER.RANDOM_ENCOUNTER then
                draw.normalCategory = draw.category
                draw.category = M.MEATGRINDER.RANDOM_ENCOUNTER
                self.eventBus:emit(events.EVENTS.RANDOM_ENCOUNTER, draw)
            end
            return { triggered = true, result = draw }
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

        -- Emit room entered event
        self.eventBus:emit(events.EVENTS.ROOM_ENTERED, {
            roomId   = targetRoomId,
            room     = targetRoom,
            previous = previousRoom,
        })

        -- Increment the watch (triggers Meatgrinder). Mapped routes can cover two
        -- mapped room transitions per event after the Update Maps Camp Action.
        local watchResult = nil
        local watchSpent = self:shouldSpendWatchForRoomMove(previousRoom, targetRoomId, options)
        if watchSpent then
            watchResult = self:incrementWatch({ careful = options.careful })
        end

        -- Emit party moved event
        self.eventBus:emit(events.EVENTS.PARTY_MOVED, {
            from                      = previousRoom,
            to                        = targetRoomId,
            watchNumber               = watchResult and watchResult.watchNumber or self.watchCount,
            watchSpent                = watchSpent,
            mappedRoomTravelProgress  = self.mappedRoomTravelProgress,
            mappedRoomTravelPerWatch  = self.mappedRoomTravelPerWatch,
        })

        return true, {
            watchResult               = watchResult,
            watchSpent                = watchSpent,
            previousRoom              = previousRoom,
            newRoom                   = targetRoomId,
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
