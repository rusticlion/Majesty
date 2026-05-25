-- overland_travel.lua
-- Optional overland travel procedure from Core Rules Chapter 8.

local events = require('logic.events')
local meatgrinder_engine = require('logic.meatgrinder')
local camp_controller = require('logic.camp_controller')
local camp_actions = require('logic.camp_actions')

local M = {}

M.ACTIONS = {
    CAMP_ACTION = "camp_action",
    ENCAMP = "encamp",
    EXPLORE = "explore",
    INTERACT = "interact",
    TRAVEL = "travel",
}

M.EVENTS = {
    ACTION_RESOLVED = "overland_action_resolved",
    DAY_ENDED = "overland_day_ended",
    EXHAUSTION_APPLIED = "overland_exhaustion_applied",
    ENCAMPED = "overland_encamped",
    ENCAMP_READY = "overland_encamp_ready",
    MEATGRINDER_DRAWN = "overland_meatgrinder_drawn",
    SCENE_SET = "overland_scene_set",
}

M.PROCEDURE = {
    optional = true,
    source = "Core Rules Chapter 8 optional Overland Travel",
    watchesPerDay = 3,
    watchLengthHours = 8,
    steps = {
        {
            key = "choose_action",
            label = "Choose action",
            description = "The guild chooses one overland action for the watch.",
        },
        {
            key = "meatgrinder",
            label = "Meatgrinder",
            description = "The GM draws on the Meatgrinder table for a random event or encounter.",
        },
        {
            key = "set_scene",
            label = "Set the scene",
            description = "The GM frames the random result in the current hex, the table plays the scene, then chooses another overland action.",
        },
    },
    exhaustion = {
        trigger = "If the guild fails to Encamp once per day.",
        effect = "Guild members become Exhausted until they Encamp again.",
        consequence = "All tests and Challenge Actions are made with disfavor.",
    },
    campPhaseSplit = "Camp Actions are separated from Camp Phase steps 2-5; Encamp runs Break Bread through end of Camp Phase.",
}

M.ACTION_DETAILS = {
    [M.ACTIONS.CAMP_ACTION] = {
        key = M.ACTIONS.CAMP_ACTION,
        label = "Camp Action",
        description = "Each adventurer can choose any Camp Action to perform during the watch.",
        consumesWatch = true,
    },
    [M.ACTIONS.ENCAMP] = {
        key = M.ACTIONS.ENCAMP,
        label = "Encamp",
        description = "The guild beds down for the night and runs Camp Phase steps 2-5.",
        consumesWatch = true,
        satisfiesDailyEncamp = true,
    },
    [M.ACTIONS.EXPLORE] = {
        key = M.ACTIONS.EXPLORE,
        label = "Explore",
        description = "Look for notable features, lairs, terrain, or spoor discoverable in the current hex.",
        consumesWatch = true,
    },
    [M.ACTIONS.INTERACT] = {
        key = M.ACTIONS.INTERACT,
        label = "Interact",
        description = "Interact with a special feature or location such as a dungeon, hamlet, shrine, or lair.",
        consumesWatch = true,
    },
    [M.ACTIONS.TRAVEL] = {
        key = M.ACTIONS.TRAVEL,
        label = "Travel",
        description = "Move from the current hex into an adjacent hex.",
        consumesWatch = true,
        baseHexes = 1,
        clearRoadBonusHexes = 1,
        allRidingBonusHexes = 1,
    },
}

local actionAliases = {
    camp = M.ACTIONS.CAMP_ACTION,
    camp_action = M.ACTIONS.CAMP_ACTION,
    campaction = M.ACTIONS.CAMP_ACTION,
    encamp = M.ACTIONS.ENCAMP,
    rest = M.ACTIONS.ENCAMP,
    explore = M.ACTIONS.EXPLORE,
    scout_hex = M.ACTIONS.EXPLORE,
    interact = M.ACTIONS.INTERACT,
    interaction = M.ACTIONS.INTERACT,
    travel = M.ACTIONS.TRAVEL,
    move = M.ACTIONS.TRAVEL,
}

local function normalizeAction(value)
    if type(value) == "table" then
        value = value.type or value.action or value.id
    end
    value = tostring(value or ""):gsub("%s+", "_"):lower()
    return actionAliases[value] or value
end

local function actorId(actor)
    return actor and (actor.id or actor.name) or nil
end

local function emit(controller, eventType, data)
    if controller.eventBus and controller.eventBus.emit then
        controller.eventBus:emit(eventType, data)
    end
end

local function ensureConditions(actor)
    actor.conditions = actor.conditions or {}
    return actor.conditions
end

local function applyOverlandExhaustion(actor)
    local conditions = ensureConditions(actor)
    actor.overlandExhaustedWasAlreadyExhausted = conditions.exhausted == true or actor.exhausted == true
    conditions.exhausted = true
    actor.exhausted = true
    actor.overlandExhausted = true
    actor.conditionDurations = actor.conditionDurations or {}
    actor.conditionDurations.exhausted = actor.conditionDurations.exhausted or {}
    actor.conditionDurations.exhausted.overland = true
    actor.conditionDurations.exhausted["until"] = actor.conditionDurations.exhausted["until"] or "encamp"
end

local function clearOverlandExhaustion(actor)
    if not actor or not actor.overlandExhausted then
        return false
    end

    local wasAlreadyExhausted = actor.overlandExhaustedWasAlreadyExhausted == true
    actor.overlandExhausted = nil
    actor.overlandExhaustedWasAlreadyExhausted = nil

    if actor.conditionDurations and actor.conditionDurations.exhausted then
        actor.conditionDurations.exhausted.overland = nil
        if actor.conditionDurations.exhausted["until"] == "encamp" then
            actor.conditionDurations.exhausted["until"] = nil
        end
        if next(actor.conditionDurations.exhausted) == nil then
            actor.conditionDurations.exhausted = nil
        end
    end

    if not wasAlreadyExhausted then
        local conditions = ensureConditions(actor)
        conditions.exhausted = false
        actor.exhausted = false
    end

    return true
end

local function truthy(...)
    for i = 1, select("#", ...) do
        if select(i, ...) == true then
            return true
        end
    end
    return false
end

local function shallowCopy(value)
    local copy = {}
    for k, v in pairs(value or {}) do
        copy[k] = v
    end
    return copy
end

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for key, child in pairs(value) do
        out[key] = deepCopy(child)
    end
    return out
end

function M.getProcedure()
    return deepCopy(M.PROCEDURE)
end

function M.getActionDetails(action)
    if action == nil then
        return deepCopy(M.ACTION_DETAILS)
    end
    return deepCopy(M.ACTION_DETAILS[normalizeAction(action)])
end

local function normalizeCampActionId(actionId)
    return tostring(actionId or ""):lower():gsub("%s+", "_")
end

local function hexId(hex)
    if type(hex) == "table" then
        return hex.id or hex.hexId or hex.key or hex.name
    end
    return hex
end

local function addNeighbor(out, seen, destination, road, source)
    local id = hexId(destination)
    if id == nil or tostring(id) == "" then
        return
    end

    local key = tostring(id)
    if seen[key] then
        if road == false then
            seen[key].road = false
        end
        return
    end

    local entry = {
        id = id,
        road = road == true,
        source = source,
    }
    out[#out + 1] = entry
    seen[key] = entry
end

local function readNeighborEntry(out, seen, key, value, source)
    if type(value) == "table" then
        local destination = value.id or value.hex or value.hexId or value.to or value.destination or value[1] or key
        local road = value.clearRoad == true or value.road == true or value.roads == true or value.clearRoads == true
        addNeighbor(out, seen, destination, road, value)
    elseif value == true then
        addNeighbor(out, seen, key, false, source)
    elseif value ~= false and value ~= nil then
        addNeighbor(out, seen, value, false, source)
    end
end

function M.createOverlandTravelController(config)
    config = config or {}

    local meatgrinder = config.meatgrinder
    if config.meatgrinderTable and not meatgrinder then
        meatgrinder = meatgrinder_engine.createMeatgrinder({
            eventBus = config.eventBus or events.globalBus,
            entityFactory = config.entityFactory,
        })
        meatgrinder:registerTable(config.meatgrinderTable)
    end

    local controller = {
        eventBus = config.eventBus or events.globalBus,
        guild = config.guild or {},
        watchManager = config.watchManager,
        gmDeck = config.gmDeck,
        meatgrinder = meatgrinder,
        meatgrinderContext = config.meatgrinderContext or {},
        hexMap = config.hexMap or config.overlandMap or config.map,
        campController = config.campController,
        campConfig = config.campConfig or {},
        currentHex = config.currentHex or config.hex or config.location,
        currentDay = config.currentDay or 1,
        currentWatch = config.currentWatch or 0,
        watchesPerDay = config.watchesPerDay or 3,
        didEncampToday = config.didEncampToday == true,
        actionLog = {},
        dayLog = {},
    }

    function controller:getState()
        return {
            currentHex = self.currentHex,
            currentDay = self.currentDay,
            currentWatch = self.currentWatch,
            watchesPerDay = self.watchesPerDay,
            didEncampToday = self.didEncampToday,
        }
    end

    function controller:applyDailyExhaustion()
        local exhausted = {}
        for _, actor in ipairs(self.guild or {}) do
            applyOverlandExhaustion(actor)
            exhausted[#exhausted + 1] = actor
        end
        if #exhausted > 0 then
            emit(self, M.EVENTS.EXHAUSTION_APPLIED, {
                day = self.currentDay,
                actors = exhausted,
            })
        end
        return exhausted
    end

    function controller:clearOverlandExhaustion()
        local cleared = {}
        for _, actor in ipairs(self.guild or {}) do
            if clearOverlandExhaustion(actor) then
                cleared[#cleared + 1] = actor
            end
        end
        return cleared
    end

    function controller:getCurrentHexContext()
        if type(self.currentHex) == "table" then
            return self.currentHex
        end
        if self.currentHex then
            return { id = self.currentHex, hexId = self.currentHex }
        end
        return nil
    end

    function controller:getHexData(hex)
        if type(hex) == "table" then
            return hex
        end

        local map = self.hexMap
        if type(map) ~= "table" then
            return nil
        end
        if map.getHex then
            return map:getHex(hex)
        end
        if type(map.hexes) == "table" and map.hexes[hex] then
            return map.hexes[hex]
        end
        return map[hex]
    end

    function controller:getHexNeighbors(hex)
        local out = {}
        local seen = {}
        local map = self.hexMap
        local id = hexId(hex)

        if type(map) == "table" and map.getNeighbors then
            for _, neighbor in ipairs(map:getNeighbors(id) or {}) do
                readNeighborEntry(out, seen, nil, neighbor, neighbor)
            end
        end

        local hexData = self:getHexData(id)
        if type(hexData) == "table" then
            for _, key in ipairs({ "neighbors", "neighbours", "adjacent", "adjacentHexes", "connections", "exits" }) do
                local pool = hexData[key]
                if type(pool) == "table" then
                    for neighborKey, value in pairs(pool) do
                        readNeighborEntry(out, seen, neighborKey, value, pool)
                    end
                end
            end

            local roads = hexData.roads or hexData.clearRoads or hexData.roadConnections
            if type(roads) == "table" then
                for roadKey, value in pairs(roads) do
                    if type(value) == "table" then
                        readNeighborEntry(out, seen, roadKey, value, roads)
                        local neighbor = seen[tostring(hexId(value.id or value.hex or value.hexId or value.to or value.destination or roadKey))]
                        if neighbor then
                            neighbor.road = true
                        end
                    elseif value == true then
                        addNeighbor(out, seen, roadKey, true, roads)
                    else
                        addNeighbor(out, seen, value, true, roads)
                    end
                end
            end
        end

        if type(map) == "table" then
            local scoped = nil
            if type(map.neighbors) == "table" then
                scoped = map.neighbors[id] or map.neighbors[tostring(id)]
            end
            if not scoped and type(map.connections) == "table" then
                scoped = map.connections[id] or map.connections[tostring(id)]
            end
            if type(scoped) == "table" then
                for neighborKey, value in pairs(scoped) do
                    readNeighborEntry(out, seen, neighborKey, value, scoped)
                end
            end
        end

        return out
    end

    function controller:findHexRoute(destination, maxSteps)
        local start = hexId(self.currentHex)
        local goal = hexId(destination)
        if start == nil or goal == nil then
            return nil
        end
        if tostring(start) == tostring(goal) then
            return {
                distance = 0,
                clearRoad = true,
                path = { start },
            }
        end

        local queue = {
            {
                id = start,
                distance = 0,
                clearRoad = true,
                path = { start },
            },
        }
        local visited = { [tostring(start)] = true }
        local index = 1
        local limit = maxSteps or 3
        while queue[index] do
            local node = queue[index]
            index = index + 1
            if node.distance < limit then
                for _, neighbor in ipairs(self:getHexNeighbors(node.id)) do
                    local neighborId = hexId(neighbor.id)
                    local key = tostring(neighborId)
                    if neighborId ~= nil and not visited[key] then
                        visited[key] = true
                        local path = shallowCopy(node.path)
                        path[#path + 1] = neighborId
                        local nextNode = {
                            id = neighborId,
                            distance = node.distance + 1,
                            clearRoad = node.clearRoad and neighbor.road == true,
                            path = path,
                        }
                        if key == tostring(goal) then
                            return nextNode
                        end
                        queue[#queue + 1] = nextNode
                    end
                end
            end
        end

        return nil
    end

    function controller:findHexFeature(hexData, featureId)
        if not hexData or not featureId then
            return nil
        end

        local featureKeys = { "features", "notableFeatures", "discoverableFeatures", "locations" }
        for _, key in ipairs(featureKeys) do
            local pool = hexData[key]
            if type(pool) == "table" then
                for _, feature in ipairs(pool) do
                    local id = feature.id or feature.featureId or feature.name
                    if tostring(id) == tostring(featureId) then
                        return feature
                    end
                end
            end
        end
        return nil
    end

    function controller:drawMeatgrinder(detail)
        local draw = nil
        if self.watchManager and self.watchManager.drawMeatgrinder then
            draw = self.watchManager:drawMeatgrinder()
        elseif self.gmDeck and self.gmDeck.draw then
            local card = self.gmDeck:draw()
            if card then
                local result = nil
                local category = nil
                if self.meatgrinder and self.meatgrinder.resolveEvent then
                    local context = {}
                    for key, value in pairs(self.meatgrinderContext or {}) do
                        context[key] = value
                    end
                    context.guild = self.guild
                    context.overland = true
                    context.emitEvents = false
                    result = self.meatgrinder:resolveEvent(card, self:getCurrentHexContext(), context)
                    category = result and result.category or nil
                elseif self.meatgrinder and self.meatgrinder.getCategory then
                    category = self.meatgrinder:getCategory(card.value)
                end
                if not category and card.value then
                    category = meatgrinder_engine.createMeatgrinder():getCategory(card.value)
                end
                draw = {
                    card = card,
                    category = category,
                    value = card.value,
                    result = result,
                    description = result and result.description or nil,
                    effects = result and result.effects or nil,
                    spawns = result and result.spawns or nil,
                    hex = self.currentHex,
                }
                if self.gmDeck.discard then
                    self.gmDeck:discard(card)
                end
            end
        end

        if not draw then
            return nil
        end

        detail.meatgrinder = draw
        detail.scene = {
            hex = self.currentHex,
            category = draw.category,
            description = draw.description or
                (draw.result and draw.result.description) or
                (draw.card and draw.card.name),
            result = draw.result,
        }
        emit(self, M.EVENTS.MEATGRINDER_DRAWN, {
            action = detail.action,
            currentHex = self.currentHex,
            draw = draw,
        })
        emit(self, M.EVENTS.SCENE_SET, detail.scene)
        return draw
    end

    function controller:advanceWatch(detail)
        self.currentWatch = self.currentWatch + 1
        detail.currentWatch = self.currentWatch
        detail.currentDay = self.currentDay

        if self.currentWatch >= self.watchesPerDay then
            local endedDay = self.currentDay
            local encamped = self.didEncampToday == true
            local exhausted = {}
            if not encamped then
                exhausted = self:applyDailyExhaustion()
                detail.effects[#detail.effects + 1] = "overland_exhausted"
            end

            self.dayLog[#self.dayLog + 1] = {
                day = endedDay,
                encamped = encamped,
                exhaustedActors = exhausted,
            }
            emit(self, M.EVENTS.DAY_ENDED, {
                day = endedDay,
                encamped = encamped,
                exhaustedActors = exhausted,
            })

            self.currentDay = self.currentDay + 1
            self.currentWatch = 0
            self.didEncampToday = false

            detail.dayEnded = endedDay
            detail.encampedThatDay = encamped
            detail.exhaustedActors = exhausted
            detail.currentDay = self.currentDay
            detail.currentWatch = self.currentWatch
        end
    end

    function controller:resolveTravel(request, detail)
        local destination = request.destinationHex or request.destination or request.hex or request.to
        if not destination or tostring(destination) == "" then
            return false, "Destination hex required"
        end

        local explicitDistance = request.distance or request.hexes or request.steps
        local route = self:findHexRoute(destination, 3)
        local distance = math.floor(tonumber(explicitDistance) or (route and route.distance) or 1)
        if distance < 1 then
            return false, "Travel distance required"
        end

        local maxDistance = 1
        local clearRoad = truthy(request.clearRoad, request.clearRoads, request.road, request.roads)
        if not clearRoad and explicitDistance == nil and route and route.clearRoad and route.distance > 1 then
            clearRoad = true
        end
        if clearRoad then
            maxDistance = maxDistance + 1
        end
        if truthy(request.allRiding, request.everyoneRiding, request.mounted, request.guildRiding) then
            maxDistance = maxDistance + 1
        end

        if explicitDistance == nil and self.hexMap and not route then
            return false, "Destination too far"
        end
        if distance > maxDistance then
            return false, "Destination too far"
        end

        detail.fromHex = self.currentHex
        detail.destinationHex = destination
        detail.distance = distance
        detail.maxDistance = maxDistance
        detail.clearRoad = clearRoad
        detail.route = route and route.path or nil
        self.currentHex = destination
        detail.currentHex = self.currentHex
        return true, nil
    end

    function controller:resolveExplore(request, detail)
        local hex = request.hex or self.currentHex
        local hexData = request.hexData or request.locationData or self:getHexData(hex)
        detail.hex = hex
        detail.hexData = hexData

        if hexData then
            detail.terrain = request.terrain or hexData.terrain or hexData.biome
            detail.features = request.features or request.findings or
                hexData.discoverableFeatures or hexData.notableFeatures or hexData.features
            detail.lairs = request.lairs or hexData.lairs
            detail.spoor = request.spoor or hexData.spoor or hexData.tracks
        else
            detail.features = request.features or request.findings
            detail.spoor = request.spoor
        end

        detail.findings = request.findings or detail.features
        detail.effects[#detail.effects + 1] = "overland_explored"
        return true, nil
    end

    function controller:resolveInteract(request, detail)
        local hex = request.hex or self.currentHex
        local hexData = request.hexData or request.locationData or self:getHexData(hex)
        local feature = request.feature or request.location or request.target
        if not feature and request.featureId then
            feature = self:findHexFeature(hexData, request.featureId)
        end
        if not feature then
            return false, "Interact feature required"
        end

        detail.hex = hex
        detail.hexData = hexData
        detail.feature = feature
        detail.featureId = request.featureId or
            (type(feature) == "table" and (feature.id or feature.featureId) or nil)
        detail.interaction = {
            hex = hex,
            feature = feature,
            mode = request.mode or request.interaction,
            destination = request.destination or request.locationId,
        }
        detail.effects[#detail.effects + 1] = "overland_interacted"
        return true, nil
    end

    function controller:prepareEncamp(request, detail)
        local camp = request.campController or self.campController
        if not camp then
            camp = camp_controller.createCampController({
                eventBus = self.eventBus,
                guild = self.guild,
                watchManager = request.watchManager or self.watchManager,
                meatgrinder = request.meatgrinder or self.meatgrinder,
                playerDeck = request.playerDeck,
                actionResolver = request.actionResolver,
                currentRoom = request.currentRoom or request.hex or self.currentHex,
                currentRoomId = request.currentRoomId or request.roomId or request.hexId or self.currentHex,
                roomManager = request.roomManager,
            })
            self.campController = camp
        end

        if camp.getState and camp:getState() == camp_controller.STATES.INACTIVE then
            local ok, err = camp:startCamp(request.campConfig or self.campConfig or {})
            if not ok then
                return false, err
            end
        end

        if camp.transitionTo and camp:getState() == camp_controller.STATES.ACTIONS then
            camp:transitionTo(camp_controller.STATES.BREAK_BREAD)
        end

        detail.campController = camp
        detail.campState = camp.getState and camp:getState() or nil
        detail.campSteps = { "break_bread", "watch", "recovery", "teardown" }
        detail.effects[#detail.effects + 1] = "encamp_camp_steps_ready"
        emit(self, M.EVENTS.ENCAMP_READY, {
            campController = camp,
            campState = detail.campState,
            steps = detail.campSteps,
        })
        return true, nil
    end

    function controller:campActionContext(request, actionsCompleted)
        local context = shallowCopy(request.context or request.campContext or {})
        context.eventBus = context.eventBus or self.eventBus
        context.guild = context.guild or self.guild
        context.watchManager = context.watchManager or request.watchManager or self.watchManager
        context.meatgrinder = context.meatgrinder or request.meatgrinder or self.meatgrinder
        context.playerDeck = context.playerDeck or request.playerDeck
        context.actionResolver = context.actionResolver or request.actionResolver
        context.currentRoom = context.currentRoom or request.currentRoom or request.hex or self.currentHex
        context.currentRoomId = context.currentRoomId or request.currentRoomId or request.roomId or
            request.hexId or self.currentHex
        context.roomManager = context.roomManager or request.roomManager
        context.actionsCompleted = actionsCompleted
        context.overland = true
        context.overlandAction = true
        return context
    end

    function controller:resolveCampActions(request, detail)
        local specs = {}
        if type(request.campActions) == "table" then
            for _, spec in ipairs(request.campActions) do
                specs[#specs + 1] = spec
            end
        end
        if #specs == 0 then
            specs[#specs + 1] = request
        end

        local prepared = {}
        local seenActors = {}
        for _, spec in ipairs(specs) do
            local actionRequest = type(spec) == "table" and spec or { campAction = spec }
            local actor = actionRequest.actor or request.actor
            if not actor then
                return false, "Camp Action actor required"
            end

            local campActionId = normalizeCampActionId(
                actionRequest.campAction or
                actionRequest.campActionId or
                actionRequest.camp_action or
                actionRequest.camp_action_id or
                actionRequest.campType or
                (actionRequest.type ~= M.ACTIONS.CAMP_ACTION and actionRequest.type or nil)
            )
            if campActionId == "" then
                return false, "Camp Action required"
            end

            local actionDef = camp_actions.getAction(campActionId)
            if not actionDef then
                return false, "Unknown Camp Action"
            end

            local actorKey = actor.id or actor
            if seenActors[actorKey] then
                return false, "Action already taken"
            end
            seenActors[actorKey] = true

            if campActionId == "train" and actionRequest.target then
                local targetKey = actionRequest.target.id or actionRequest.target
                if seenActors[targetKey] then
                    return false, "Action already taken"
                end
                seenActors[targetKey] = true
            end

            prepared[#prepared + 1] = {
                request = actionRequest,
                actor = actor,
                campActionId = campActionId,
                actionDef = actionDef,
            }
        end

        local actionsCompleted = {}
        local context = self:campActionContext(request, actionsCompleted)
        detail.campActionResults = {}

        for _, preparedAction in ipairs(prepared) do
            local actionRequest = preparedAction.request
            local actor = preparedAction.actor
            local campActionId = preparedAction.campActionId
            local campActionData = shallowCopy(request)
            campActionData.campActions = nil
            for key, value in pairs(actionRequest) do
                campActionData[key] = value
            end
            campActionData.type = campActionId
            campActionData.actor = actor
            campActionData.target = campActionData.target or actionRequest.target or request.target

            local ok, result, payload = camp_actions.resolveAction(campActionData, context)
            if not ok then
                detail.failedCampAction = {
                    actor = actor,
                    campAction = campActionId,
                    result = result,
                }
                return false, result
            end

            if actor.id then
                actionsCompleted[actor.id] = campActionData
            end
            if campActionId == "train" and campActionData.target and campActionData.target.id then
                actionsCompleted[campActionData.target.id] = {
                    type = "train_mentor",
                    actor = campActionData.target,
                    target = actor,
                    talentId = campActionData.talentId or
                        (campActionData.request and campActionData.request.talentId),
                }
            end

            detail.campActionResults[#detail.campActionResults + 1] = {
                actor = actor,
                campAction = campActionId,
                campActionName = preparedAction.actionDef.name,
                campResult = result,
                payload = payload,
            }
        end

        detail.campActionsCompleted = actionsCompleted
        detail.effects[#detail.effects + 1] = "overland_camp_actions_resolved"
        return true, nil
    end

    function controller:getActionOptions(opts)
        opts = opts or {}
        local procedure = M.getProcedure()
        local actionDetails = M.getActionDetails()
        local selectedAction = normalizeAction(opts.action or opts.type or opts.selectedAction)
        local currentHex = opts.currentHex or opts.hex or self.currentHex
        local currentHexData = opts.hexData or opts.locationData or self:getHexData(currentHex)
        local state = self:getState()
        local selectedDestination = opts.destinationHex or opts.destination or opts.to
        local selectedFeature = opts.feature or opts.location or opts.target
        if not selectedFeature and opts.featureId then
            selectedFeature = self:findHexFeature(currentHexData, opts.featureId)
        end

        local function copySequence(source)
            if type(source) ~= "table" then
                return {}
            end
            local out = {}
            for _, value in ipairs(source) do
                out[#out + 1] = deepCopy(value)
            end
            return out
        end

        local function featureList()
            if type(currentHexData) ~= "table" then
                return copySequence(opts.features or opts.findings)
            end
            return copySequence(opts.features or opts.findings or
                currentHexData.discoverableFeatures or currentHexData.notableFeatures or
                currentHexData.features or currentHexData.locations)
        end

        local function campActionChoices()
            local choices = {}
            for _, action in ipairs(camp_actions.ACTIONS or {}) do
                choices[#choices + 1] = {
                    key = action.id,
                    id = action.id,
                    label = action.name,
                    category = action.category,
                    description = action.description,
                    requiresTarget = action.requiresTarget == true,
                    targetType = action.targetType,
                    requiresItem = action.requiresItem,
                    requiresFletchAmmo = action.requiresFletchAmmo == true,
                    requiresAlchemy = action.requiresAlchemy == true,
                }
            end
            return choices
        end

        local route = nil
        local distance = nil
        local clearRoad = truthy(opts.clearRoad, opts.clearRoads, opts.road, opts.roads)
        if selectedDestination then
            route = self:findHexRoute(selectedDestination, 3)
            distance = math.floor(tonumber(opts.distance or opts.hexes or opts.steps) or
                (route and route.distance) or 1)
            if not clearRoad and opts.distance == nil and opts.hexes == nil and opts.steps == nil and
                route and route.clearRoad and route.distance > 1 then
                clearRoad = true
            end
        end
        local allRiding = truthy(opts.allRiding, opts.everyoneRiding, opts.mounted, opts.guildRiding)
        local maxDistance = 1 + (clearRoad and 1 or 0) + (allRiding and 1 or 0)
        local travelUnavailableReason = nil
        if selectedAction == M.ACTIONS.TRAVEL then
            if not selectedDestination or tostring(selectedDestination) == "" then
                travelUnavailableReason = "Destination hex required"
            elseif opts.distance == nil and opts.hexes == nil and opts.steps == nil and self.hexMap and not route then
                travelUnavailableReason = "Destination too far"
            elseif not distance or distance < 1 then
                travelUnavailableReason = "Travel distance required"
            elseif distance > maxDistance then
                travelUnavailableReason = "Destination too far"
            end
        end

        local interactUnavailableReason = nil
        if selectedAction == M.ACTIONS.INTERACT and not selectedFeature then
            interactUnavailableReason = "Interact feature required"
        end

        local campUnavailableReason = nil
        if selectedAction == M.ACTIONS.CAMP_ACTION then
            if not (opts.actor or opts.campActions) then
                campUnavailableReason = "Camp Action actor required"
            elseif not (opts.campAction or opts.campActionId or opts.camp_action or opts.campActions) then
                campUnavailableReason = "Camp Action required"
            elseif opts.campAction and not camp_actions.getAction(normalizeCampActionId(opts.campAction)) then
                campUnavailableReason = "Unknown Camp Action"
            end
        end

        local unavailableByAction = {
            [M.ACTIONS.TRAVEL] = travelUnavailableReason,
            [M.ACTIONS.INTERACT] = interactUnavailableReason,
            [M.ACTIONS.CAMP_ACTION] = campUnavailableReason,
        }

        local options = {}
        local selectedOption = nil
        local actionOrder = {
            M.ACTIONS.CAMP_ACTION,
            M.ACTIONS.ENCAMP,
            M.ACTIONS.EXPLORE,
            M.ACTIONS.INTERACT,
            M.ACTIONS.TRAVEL,
        }
        for index, action in ipairs(actionOrder) do
            local detail = actionDetails[action] or {}
            local unavailableReason = selectedAction == action and unavailableByAction[action] or nil
            local option = {
                key = action,
                id = action,
                index = index,
                label = detail.label,
                description = detail.description,
                selected = selectedAction == action,
                consumesWatch = detail.consumesWatch == true,
                satisfiesDailyEncamp = detail.satisfiesDailyEncamp == true,
                disabled = unavailableReason ~= nil,
                unavailableReason = unavailableReason,
            }
            if option.selected then
                selectedOption = option
            end
            options[#options + 1] = option
        end

        local neighborOptions = {}
        for _, neighbor in ipairs(self:getHexNeighbors(currentHex)) do
            neighborOptions[#neighborOptions + 1] = {
                id = neighbor.id,
                key = neighbor.id,
                label = tostring(neighbor.id),
                road = neighbor.road == true,
                distance = 1,
                source = neighbor.source,
            }
        end

        local features = featureList()
        return {
            procedure = procedure,
            actionDetails = actionDetails,
            options = options,
            actionOptions = options,
            selectedAction = selectedAction ~= "" and selectedAction or nil,
            selectedOption = selectedOption,
            state = state,
            currentHex = currentHex,
            currentHexData = deepCopy(currentHexData),
            currentDay = state.currentDay,
            currentWatch = state.currentWatch,
            watchesPerDay = state.watchesPerDay,
            watchesRemainingToday = math.max(0, (state.watchesPerDay or 0) - (state.currentWatch or 0)),
            dayWillEndAfterAction = ((state.currentWatch or 0) + 1) >= (state.watchesPerDay or 3),
            didEncampToday = state.didEncampToday == true,
            encampRequiredToday = state.didEncampToday ~= true,
            missingEncampWouldExhaust = state.didEncampToday ~= true and
                ((state.currentWatch or 0) + 1) >= (state.watchesPerDay or 3) and
                selectedAction ~= M.ACTIONS.ENCAMP,
            travelOptions = {
                destinations = neighborOptions,
                selectedDestination = selectedDestination,
                distance = distance,
                maxDistance = maxDistance,
                clearRoad = clearRoad,
                allRiding = allRiding,
                route = route and deepCopy(route.path) or nil,
                unavailableReason = travelUnavailableReason,
                baseHexes = actionDetails[M.ACTIONS.TRAVEL] and actionDetails[M.ACTIONS.TRAVEL].baseHexes,
                clearRoadBonusHexes = actionDetails[M.ACTIONS.TRAVEL] and
                    actionDetails[M.ACTIONS.TRAVEL].clearRoadBonusHexes,
                allRidingBonusHexes = actionDetails[M.ACTIONS.TRAVEL] and
                    actionDetails[M.ACTIONS.TRAVEL].allRidingBonusHexes,
            },
            exploreOptions = {
                terrain = opts.terrain or (type(currentHexData) == "table" and
                    (currentHexData.terrain or currentHexData.biome) or nil),
                features = features,
                lairs = copySequence(opts.lairs or (type(currentHexData) == "table" and currentHexData.lairs or nil)),
                spoor = copySequence(opts.spoor or (type(currentHexData) == "table" and
                    (currentHexData.spoor or currentHexData.tracks) or nil)),
            },
            interactOptions = {
                features = features,
                selectedFeature = deepCopy(selectedFeature),
                selectedFeatureId = opts.featureId or
                    (type(selectedFeature) == "table" and (selectedFeature.id or selectedFeature.featureId) or nil),
                mode = opts.mode or opts.interaction,
                unavailableReason = interactUnavailableReason,
            },
            campActionOptions = {
                actions = campActionChoices(),
                selectedCampAction = opts.campAction or opts.campActionId or opts.camp_action,
                unavailableReason = campUnavailableReason,
            },
            willDrawMeatgrinder = selectedAction ~= nil and selectedAction ~= "",
            resultPreview = "overland_action_options_ready",
        }
    end

    function controller:getOverlandActionOptions(opts)
        return self:getActionOptions(opts)
    end

    function controller:resolveAction(actionData)
        local request = type(actionData) == "table" and actionData or { type = actionData }
        local action = normalizeAction(request)
        if action == "" then
            return false, "Overland action required"
        end

        local detail = {
            action = action,
            actor = request.actor,
            actorId = actorId(request.actor),
            effects = {},
        }

        if action == M.ACTIONS.TRAVEL then
            local ok, err = self:resolveTravel(request, detail)
            if not ok then
                return false, err
            end
        elseif action == M.ACTIONS.ENCAMP then
            local ok, err = self:prepareEncamp(request, detail)
            if not ok then
                return false, err
            end
            self.didEncampToday = true
            detail.clearedExhaustion = self:clearOverlandExhaustion()
            detail.effects[#detail.effects + 1] = "overland_encamped"
            emit(self, M.EVENTS.ENCAMPED, detail)
        elseif action == M.ACTIONS.EXPLORE then
            local ok, err = self:resolveExplore(request, detail)
            if not ok then
                return false, err
            end
        elseif action == M.ACTIONS.INTERACT then
            local ok, err = self:resolveInteract(request, detail)
            if not ok then
                return false, err
            end
        elseif action == M.ACTIONS.CAMP_ACTION then
            local ok, err = self:resolveCampActions(request, detail)
            if not ok then
                return false, err
            end
        else
            return false, "Unknown overland action"
        end

        self:drawMeatgrinder(detail)
        self:advanceWatch(detail)
        self.actionLog[#self.actionLog + 1] = detail
        emit(self, M.EVENTS.ACTION_RESOLVED, detail)
        return true, "overland_action_resolved", detail
    end

    return controller
end

function M.getActionOptions(opts)
    local controller = M.createOverlandTravelController(opts or {})
    return controller:getActionOptions(opts or {})
end

function M.getOverlandActionOptions(opts)
    return M.getActionOptions(opts)
end

return M
