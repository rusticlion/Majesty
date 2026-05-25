-- room_manager.lua
-- Room Manager for Majesty
-- Ticket T2_5: Logic for room state, features, and descriptions
--
-- Design: All data in blueprints/rooms.lua, all logic here.
-- Rooms can "remember" state changes (destroyed features, etc.)

local events = require('logic.events')
local constants = require('constants')

local M = {}

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, child in pairs(value) do
        copy[key] = deepCopy(child)
    end
    return copy
end

--------------------------------------------------------------------------------
-- ROOM INSTANCE FACTORY
-- Creates a mutable room instance from a blueprint
--------------------------------------------------------------------------------

--- Create a room instance from a blueprint
-- @param blueprint table: Room blueprint from rooms.lua
-- @param roomId string: Unique ID for this instance
-- @return RoomInstance
function M.createRoomInstance(blueprint, roomId)
    -- Deep copy authored room procedure data so each instance has mutable state.
    local features = {}
    for i, feat in ipairs(blueprint.features or {}) do
        features[i] = deepCopy(feat)
    end

    local instance = {
        id               = roomId,
        blueprintId      = blueprint.id,
        name             = blueprint.name,
        -- Support both base_description and description (tomb map uses description)
        base_description = blueprint.base_description or blueprint.description,
        description      = blueprint.description,
        danger_level     = blueprint.danger_level or 1,
        safe             = blueprint.safe,
        authoredSafe     = blueprint.safe,
        safeBecauseSecret = blueprint.safeBecauseSecret,
        goldenGhostActivity = deepCopy(blueprint.goldenGhostActivity),
        features         = features,
        zones            = deepCopy(blueprint.zones or {}),
        socialEncounter  = deepCopy(blueprint.socialEncounter),
        verbs            = blueprint.verbs or {},
        meatgrinder_overrides = blueprint.meatgrinder_overrides or {},

        -- Runtime state
        mobs             = {},  -- Entity IDs of mobs currently in room
        visited          = false,
        discovered       = false,
    }

    return instance
end

--------------------------------------------------------------------------------
-- ROOM MANAGER FACTORY
--------------------------------------------------------------------------------

--- Create a new RoomManager
-- @param config table: { eventBus }
-- @return RoomManager instance
function M.createRoomManager(config)
    config = config or {}

    local manager = {
        rooms    = {},  -- roomId -> RoomInstance
        eventBus = config.eventBus or events.globalBus,
        playerDeck = config.playerDeck,
        dungeon = config.dungeon,
        encounteredBlueprintIds = config.encounteredBlueprintIds or {},
        encounteredFeatureIds = config.encounteredFeatureIds or {},
    }

    ----------------------------------------------------------------------------
    -- ROOM REGISTRATION
    ----------------------------------------------------------------------------

    --- Register a room instance
    function manager:registerRoom(roomInstance)
        self.rooms[roomInstance.id] = roomInstance
    end

    --- Get a room by ID
    function manager:getRoom(roomId)
        return self.rooms[roomId]
    end

    local function connectionIsSecret(connection)
        if not connection then
            return false
        end
        return connection.is_secret == true or
            (connection.properties and connection.properties.is_secret == true)
    end

    local function connectionIsDiscovered(connection)
        return connection and connection.discovered == true
    end

    local function describeSafetyConnection(fromId, connection, incoming)
        return {
            from = fromId,
            to = connection and connection.target_room_id or nil,
            secret = connectionIsSecret(connection),
            discovered = connectionIsDiscovered(connection),
            incoming = incoming == true,
        }
    end

    local function collectRoomSafetyConnections(roomId, graph)
        local records = {}
        if not graph or not graph.getRoom then
            return records
        end

        local graphRoom = graph:getRoom(roomId)
        if graphRoom and graphRoom.connections then
            for _, connection in ipairs(graphRoom.connections) do
                records[#records + 1] = describeSafetyConnection(roomId, connection, false)
            end
        end

        for fromId, otherRoom in pairs(graph.rooms or {}) do
            if fromId ~= roomId and otherRoom.connections then
                local hasOutgoingReverse = graph.getConnection and graph:getConnection(roomId, fromId) ~= nil
                if not hasOutgoingReverse then
                    for _, connection in ipairs(otherRoom.connections) do
                        if connection.target_room_id == roomId then
                            records[#records + 1] = describeSafetyConnection(fromId, connection, true)
                        end
                    end
                end
            end
        end

        return records
    end

    function manager:evaluateRoomSafety(roomId, dungeon)
        local room = self:getRoom(roomId)
        if not room then
            return {
                roomId = roomId,
                safe = false,
                reason = "room_not_found",
            }
        end

        if room.safeBecauseSecret == true then
            local graph = dungeon or self.dungeon
            local connections = collectRoomSafetyConnections(roomId, graph)
            local exposedConnections = {}
            local secretConnections = {}

            for _, record in ipairs(connections) do
                if record.secret then
                    secretConnections[#secretConnections + 1] = record
                    if record.discovered then
                        exposedConnections[#exposedConnections + 1] = record
                    end
                else
                    exposedConnections[#exposedConnections + 1] = record
                end
            end

            if room.safeBecauseSecretExposed == true or #exposedConnections > 0 then
                return {
                    roomId = roomId,
                    safe = false,
                    reason = "secret_room_exposed",
                    safeBecauseSecret = true,
                    secretConnections = secretConnections,
                    exposedConnections = exposedConnections,
                }
            end

            return {
                roomId = roomId,
                safe = room.safe == true or room.authoredSafe == true,
                reason = "secret_room_hidden",
                safeBecauseSecret = true,
                secretConnections = secretConnections,
                exposedConnections = exposedConnections,
            }
        end

        return {
            roomId = roomId,
            safe = room.safe == true,
            reason = room.safe == true and "authored_safe" or "unsafe",
        }
    end

    function manager:updateRoomSafetyFromSecrets(roomId, dungeon, opts)
        opts = opts or {}
        local room = self:getRoom(roomId)
        if not room or room.safeBecauseSecret ~= true then
            return nil
        end

        local wasSafe = room.safe == true
        local safety = self:evaluateRoomSafety(roomId, dungeon)
        if safety.safe == false and wasSafe then
            room.safe = false
            room.effectiveSafe = false
            room.safeBecauseSecretExposed = true
            room.safeLostReason = safety.reason
            room.safeLostByConnections = deepCopy(safety.exposedConnections or {})

            local change = {
                roomId = roomId,
                wasSafe = wasSafe,
                safe = false,
                reason = safety.reason,
                safeBecauseSecret = true,
                exposedConnections = deepCopy(safety.exposedConnections or {}),
                sourceRoomId = opts.sourceRoomId,
                featureId = opts.featureId,
            }

            self.eventBus:emit(events.EVENTS.ROOM_SAFETY_CHANGED, change)
            return change
        end

        return nil
    end

    function manager:getSocialEncounter(roomId)
        local room = self.rooms[roomId]
        return room and room.socialEncounter or nil
    end

    local function appendSocialPreparedEffect(room, record)
        if not room or not room.socialEncounter or not record then
            return nil
        end

        local socialEncounter = room.socialEncounter
        socialEncounter.preparedEffects = socialEncounter.preparedEffects or {}
        socialEncounter.preparedEffects[#socialEncounter.preparedEffects + 1] = record
        return record
    end

    local function rumorAlreadyKnown(rumors, rumorId)
        if not rumorId then
            return false
        end
        for _, rumor in ipairs(rumors or {}) do
            if rumor.id == rumorId then
                return true
            end
        end
        return false
    end

    local function appendKnownRumor(target, rumor)
        if not target or not rumor then
            return
        end
        target.discoveredRumors = target.discoveredRumors or {}
        if not rumorAlreadyKnown(target.discoveredRumors, rumor.id) then
            target.discoveredRumors[#target.discoveredRumors + 1] = deepCopy(rumor)
        end
    end

    local function giftRequirement(giftRumor)
        local requirement = deepCopy((giftRumor and giftRumor.requires) or {})
        if giftRumor and giftRumor.requiresNewBook then
            requirement.itemType = requirement.itemType or "book"
            requirement.properties = requirement.properties or {}
            requirement.properties.book = true
        end
        return requirement
    end

    local function itemMatchesGiftRequirement(item, requirement)
        if not item then
            return false
        end
        requirement = requirement or {}
        local props = item.properties or {}

        if requirement.itemType then
            local itemType = item.type or item.itemType or props.type
            if itemType ~= requirement.itemType then
                return false
            end
        end

        for key, expected in pairs(requirement.properties or {}) do
            local actual = props[key]
            if actual == nil then
                actual = item[key]
            end
            if actual ~= expected then
                return false
            end
        end

        return true
    end

    local function findGiftItem(actor, requirement, opts)
        opts = opts or {}
        local inv = actor and actor.inventory
        if not inv then
            return nil, nil, "missing_inventory"
        end

        local explicit = opts.giftItem or opts.offeredItem or opts.item
        if type(explicit) == "string" and inv.findItem then
            explicit = inv:findItem(explicit)
        end
        if type(explicit) == "table" then
            if not itemMatchesGiftRequirement(explicit, requirement) then
                return nil, nil, "gift_does_not_match"
            end
            if explicit.id and inv.findItem then
                local carried, location = inv:findItem(explicit.id)
                if carried then
                    return carried, location, nil
                end
            end
            return nil, nil, "gift_not_carried"
        end

        local itemId = opts.giftItemId or opts.offeredItemId or opts.itemId
        if itemId and inv.findItem then
            local item, location = inv:findItem(itemId)
            if item and itemMatchesGiftRequirement(item, requirement) then
                return item, location, nil
            end
            return nil, nil, item and "gift_does_not_match" or "gift_not_carried"
        end

        if inv.findItemByPredicate then
            local item, location = inv:findItemByPredicate(function(candidate)
                return itemMatchesGiftRequirement(candidate, requirement)
            end)
            if item then
                return item, location, nil
            end
        end

        return nil, nil, "gift_required"
    end

    function manager:getSocialPreparedEffects(roomId)
        local socialEncounter = self:getSocialEncounter(roomId)
        return socialEncounter and socialEncounter.preparedEffects or {}
    end

    function manager:resolveSocialFeatureProcedure(roomId, featureId, action, actor, opts)
        opts = opts or {}
        local room = self.rooms[roomId]
        local feature = self:getFeature(roomId, featureId)
        if not room or not feature then
            return { success = false, description = "There is nothing to use that way." }
        end

        local result = {
            success = false,
            roomId = roomId,
            featureId = featureId,
            action = action,
            effects = {},
        }

        if action == "make_offering" then
            if feature.offeringMade then
                result.description = "An offering has already been made here."
                return result
            end
            if not feature.acceptsOffering and not feature.offeringEffect then
                result.description = "This does not seem like a place for offerings."
                return result
            end

            local effect = deepCopy(feature.offeringEffect or {})
            local record = {
                type = effect.type or "disposition_shift",
                target = effect.target,
                disposition = effect.disposition or effect.toward or "trust",
                severity = effect.severity or 2,
                amount = effect.amount or 1,
                sourceFeatureId = featureId,
                sourceAction = action,
                actorId = actor and actor.id or nil,
                appliedTo = {},
            }
            appendSocialPreparedEffect(room, record)

            feature.offeringMade = true
            result.success = true
            result.record = record
            result.description = "The offering is accepted as a sign of respectful intent."
            result.effects[#result.effects + 1] = "room_social_offering_prepared"
        elseif action == "study_lore" then
            if feature.loreStudied then
                result.description = "You have already drawn what you can from this lore."
                return result
            end
            if not feature.grantsLore and not feature.loreEffect then
                result.description = "There is no useful lore to study here."
                return result
            end

            local effect = deepCopy(feature.loreEffect or {})
            local record = {
                type = effect.type or "social_favor",
                target = effect.target,
                modifier = effect.modifier or 2,
                description = effect.description,
                lore = feature.grantsLore,
                sourceFeatureId = featureId,
                sourceAction = action,
                actorId = actor and actor.id or nil,
            }
            appendSocialPreparedEffect(room, record)

            feature.loreStudied = true
            if actor then
                actor.discoveredLore = actor.discoveredLore or {}
                if feature.grantsLore then
                    actor.discoveredLore[feature.grantsLore] = true
                end
            end
            result.success = true
            result.record = record
            result.description = effect.description or "The studied lore gives you leverage in the conversation."
            result.effects[#result.effects + 1] = "room_social_lore_prepared"
        elseif action == "give_gift" then
            local giftRumor = feature.giftRumor or feature.bookGiftRumor
            if not giftRumor then
                result.description = "This does not seem interested in gifts."
                return result
            end
            if feature.giftRumorRevealed or (giftRumor and giftRumor.revealed) then
                result.description = "This gift has already earned all the rumor it can."
                return result
            end

            local requirement = giftRequirement(giftRumor)
            local gift, giftLocation, giftReason = findGiftItem(actor, requirement, opts)
            if not gift then
                if giftReason == "gift_does_not_match" then
                    result.description = "That is not the gift this creature wants."
                elseif giftReason == "gift_not_carried" then
                    result.description = "The gift must be carried by the acting adventurer."
                else
                    result.description = "A suitable gift is required."
                end
                result.failureReason = giftReason
                return result
            end

            local removedGift, removedLocation = nil, nil
            if actor and actor.inventory and actor.inventory.removeItem and gift.id then
                removedGift, removedLocation = actor.inventory:removeItem(gift.id)
            end
            if not removedGift then
                result.description = "The gift must be handed over before the rumor is shared."
                result.failureReason = "gift_not_removed"
                return result
            end

            local rumor = deepCopy(giftRumor)
            rumor.requires = nil
            rumor.requiresNewBook = nil
            rumor.revealed = true
            rumor.sourceFeatureId = featureId
            rumor.sourceAction = action
            rumor.giftItemId = removedGift.id
            rumor.giftItemName = removedGift.name

            feature.giftRumorRevealed = true
            if feature.giftRumor then
                feature.giftRumor.revealed = true
            end
            feature.revealedRumors = feature.revealedRumors or {}
            if not rumorAlreadyKnown(feature.revealedRumors, rumor.id) then
                feature.revealedRumors[#feature.revealedRumors + 1] = deepCopy(rumor)
            end
            feature.receivedGifts = feature.receivedGifts or {}
            feature.receivedGifts[#feature.receivedGifts + 1] = {
                itemId = removedGift.id,
                itemName = removedGift.name,
                templateId = removedGift.templateId,
                actorId = actor and actor.id or nil,
                location = removedLocation or giftLocation,
            }
            appendKnownRumor(actor, rumor)

            result.success = true
            result.rumor = rumor
            result.gift = removedGift
            result.record = {
                type = "rumor_revealed",
                rumor = rumor,
                sourceFeatureId = featureId,
                sourceAction = action,
                actorId = actor and actor.id or nil,
                giftItemId = removedGift.id,
                giftItemName = removedGift.name,
            }
            result.description = (feature.name or "The creature") .. " accepts " ..
                (removedGift.name or "the gift") .. " and shares a rumor: " ..
                (rumor.summary or rumor.text or rumor.id or "something useful") .. "."
            result.effects[#result.effects + 1] = "room_social_gift_given"
            result.effects[#result.effects + 1] = "room_social_gift_rumor_revealed"
        elseif action == "return_death_masks" or action == "appease_haunting" then
            return self:resolveHauntingAppeasement(roomId, featureId, actor, opts)
        elseif action == "clear_webbing" then
            return self:resolveBrainSpiderWebDestruction(roomId, featureId, opts)
        elseif action == "solve_puzzle" then
            opts.actor = opts.actor or actor
            return self:resolveTripartitePedestalPuzzle(roomId, featureId, opts)
        elseif action == "take_crown" then
            return self:resolveTripartiteCrownRemoval(roomId, featureId, actor, opts)
        elseif action == "preserve_fragile_scrolls" then
            opts.careful = opts.careful ~= false
            opts.rightEnvironment = opts.rightEnvironment ~= false
            return self:resolveFragileScrollHandling(roomId, featureId, actor, opts)
        elseif action == "open_chronicle_scroll" then
            return self:resolveSealedChronicleOpening(roomId, featureId, actor, opts)
        elseif action == "claim_loot" then
            if feature.singleMeal then
                return self:resolveSingleMealFeature(roomId, featureId, actor, opts)
            end
            return self:resolveFeatureLootClaim(roomId, featureId, actor, opts)
        else
            result.description = "That feature does not support this social procedure."
        end

        if result.success then
            self.eventBus:emit(events.EVENTS.ROOM_SOCIAL_FEATURE_RESOLVED, {
                roomId = roomId,
                featureId = featureId,
                action = action,
                actor = actor,
                actorId = actor and actor.id or nil,
                record = result.record,
                result = result,
            })
        end

        return result
    end

    ----------------------------------------------------------------------------
    -- FEATURE MANAGEMENT
    ----------------------------------------------------------------------------

    --- Get a feature from a room
    function manager:getFeature(roomId, featureId)
        local room = self.rooms[roomId]
        if not room then return nil end

        for _, feat in ipairs(room.features) do
            if feat.id == featureId then
                return feat
            end
        end
        return nil
    end

    local function hauntingDemandMatchesItem(item, demand)
        if not item then
            return false
        end

        local props = item.properties or {}
        local property = demand and demand.itemProperty
        if property and (item[property] == true or props[property] == true) then
            return true
        end

        local templateId = item.templateId or props.templateId
        if demand and demand.itemTemplateId and templateId == demand.itemTemplateId then
            return true
        end
        if demand and demand.itemTemplateIds then
            for _, id in ipairs(demand.itemTemplateIds) do
                if templateId == id then
                    return true
                end
            end
        end

        return props.appeasesGoldenGhosts == true
    end

    local function countHauntingDemandItems(inv, demand)
        local count = 0
        if not inv or not inv.getAllItems then
            return count
        end

        for _, entry in ipairs(inv:getAllItems()) do
            local item = entry.item
            if hauntingDemandMatchesItem(item, demand) then
                count = count + (item.quantity or 1)
            end
        end
        return count
    end

    local function consumeHauntingDemandItems(inv, demand, required)
        local available = countHauntingDemandItems(inv, demand)
        if available < required then
            return nil, available
        end

        local remaining = required
        local consumed = {}
        for _, entry in ipairs(inv:getAllItems()) do
            local item = entry.item
            if remaining <= 0 then
                break
            end
            if hauntingDemandMatchesItem(item, demand) then
                local take = math.min(item.quantity or 1, remaining)
                local removed = false
                local status = nil
                if inv.removeItemQuantity and item.id then
                    removed, status = inv:removeItemQuantity(item.id, take)
                elseif inv.removeItem and item.id then
                    removed = inv:removeItem(item.id) ~= nil
                    status = removed and "removed" or "not_found"
                end

                if removed then
                    consumed[#consumed + 1] = {
                        itemId = item.id,
                        templateId = item.templateId,
                        name = item.name,
                        quantity = take,
                        location = entry.location,
                        result = status,
                    }
                    remaining = remaining - take
                end
            end
        end

        return consumed, available
    end

    local function clearGhostInterference(manager, returnedCount, sourceRoomId, sourceFeatureId)
        local cleared = {}
        for roomId, room in pairs(manager.rooms or {}) do
            for _, feature in ipairs(room.features or {}) do
                local interference = feature.ghostInterference
                local required = interference and tonumber(interference.deathMasksRequired)
                if interference and interference.activeUntilDeathMasksReturned and
                   (not required or returnedCount >= required) then
                    interference.activeUntilDeathMasksReturned = false
                    interference.appeased = true
                    interference.deathMasksReturned = returnedCount
                    interference.clearedByRoomId = sourceRoomId
                    interference.clearedByFeatureId = sourceFeatureId
                    feature.ghostInterferenceCleared = true
                    cleared[#cleared + 1] = {
                        roomId = roomId,
                        featureId = feature.id,
                        deathMasksReturned = returnedCount,
                    }
                end
            end
        end
        return cleared
    end

    local function markGoldenGhostActivityAppeased(manager, haunting)
        local affected = {}
        local roomIds = haunting and haunting.hinderRooms or {}
        for _, roomId in ipairs(roomIds) do
            local room = manager:getRoom(roomId)
            if room and room.goldenGhostActivity then
                room.goldenGhostActivity.appeased = true
                room.goldenGhostActivity.hinderExplorersTheyHear = false
                room.goldenGhostActivity.noLongerHindersExplorers = true
                room.goldenGhostActivity.freedUnappeased = false
                room.goldenGhostActivity.disasterPending = false
                room.goldenGhostActivity.freedomOutcome = nil
                affected[#affected + 1] = roomId
            end
        end
        return affected
    end

    function manager:resolveHauntingAppeasement(roomId, featureId, actor, opts)
        opts = opts or {}
        local feature = self:getFeature(roomId, featureId)
        local haunting = feature and feature.haunting
        local demand = haunting and haunting.demands
        if not feature or not haunting or not demand then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                action = opts.action or "return_death_masks",
                failureReason = "haunting_demand_not_found",
                description = "There is no haunting demand to satisfy here.",
                effects = {},
            }
        end

        if feature.hauntingAppeased or haunting.appeased then
            return {
                success = true,
                roomId = roomId,
                featureId = featureId,
                action = opts.action or "return_death_masks",
                alreadyAppeased = true,
                returnedCount = haunting.deathMasksReturned or demand.total,
                description = "The haunting has already been appeased.",
                effects = { "haunting_already_appeased" },
            }
        end

        local inv = opts.inventory or (actor and actor.inventory)
        local required = math.max(1, tonumber(opts.requiredCount or opts.required or demand.total) or 1)
        local available = countHauntingDemandItems(inv, demand)
        if not inv or available < required then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                action = opts.action or "return_death_masks",
                required = required,
                available = available,
                missing = math.max(0, required - available),
                failureReason = "haunting_relics_required",
                description = "The ghosts still need " .. tostring(required) .. " death masks returned.",
                effects = { "haunting_appeasement_incomplete" },
            }
        end

        local consumed, counted = consumeHauntingDemandItems(inv, demand, required)
        if not consumed then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                action = opts.action or "return_death_masks",
                required = required,
                available = counted or available,
                missing = math.max(0, required - (counted or available)),
                failureReason = "haunting_relics_required",
                description = "The ghosts still need " .. tostring(required) .. " death masks returned.",
                effects = { "haunting_appeasement_incomplete" },
            }
        end

        feature.hauntingAppeased = true
        feature.appeased = true
        feature.state = "appeased"
        haunting.appeased = true
        haunting.deathMasksReturned = required
        haunting.appeasedOutcomeResolved = haunting.appeasedOutcome or "appeased"
        haunting.freedUnappeased = false
        haunting.disasterPending = false

        local clearedInterference = clearGhostInterference(self, required, roomId, featureId)
        local affectedRooms = markGoldenGhostActivityAppeased(self, haunting)
        local result = {
            success = true,
            roomId = roomId,
            featureId = featureId,
            action = opts.action or "return_death_masks",
            actor = actor,
            actorId = actor and actor.id or nil,
            required = required,
            returnedCount = required,
            consumed = consumed,
            clearedInterference = clearedInterference,
            affectedRooms = affectedRooms,
            outcome = haunting.appeasedOutcomeResolved,
            description = "The golden ghosts receive their seven death masks and return to the sleep of death.",
            effects = {
                "haunting_appeased",
                "golden_ghosts_appeased",
                "death_masks_returned",
            },
        }
        if #clearedInterference > 0 then
            result.effects[#result.effects + 1] = "ghost_interference_cleared"
        end

        self.eventBus:emit(events.EVENTS.ROOM_HAUNTING_APPEASED, {
            roomId = roomId,
            featureId = featureId,
            actorId = actor and actor.id or nil,
            result = result,
            consumed = consumed,
            clearedInterference = clearedInterference,
            affectedRooms = affectedRooms,
        })

        return result
    end

    local function connectionHasGhostBlock(connection, featureId)
        if not connection then
            return false
        end
        local props = connection.properties or {}
        return connection.blocks_ghosts == true or props.blocks_ghosts == true or
            connection.blocks_intangible == true or props.blocks_intangible == true or
            connection.destroying_webs_frees_ghosts == true or props.destroying_webs_frees_ghosts == true or
            connection.blocked_by == featureId or props.blocked_by == featureId
    end

    local function clearFeatureGhostBlockConnections(graph, roomId, featureId)
        local cleared = {}
        if not graph or not graph.getRoom then
            return cleared
        end

        local room = graph:getRoom(roomId)
        for _, connection in ipairs((room and room.connections) or {}) do
            if connectionHasGhostBlock(connection, featureId) then
                local toId = connection.target_room_id
                local didClear = false
                if graph.clearConnectionGhostBlock then
                    didClear = graph:clearConnectionGhostBlock(roomId, toId)
                else
                    connection.blocks_ghosts = false
                    connection.blocks_intangible = false
                    connection.destroying_webs_frees_ghosts = false
                    connection.blocked_by = nil
                    if connection.properties then
                        connection.properties.blocks_ghosts = false
                        connection.properties.blocks_intangible = false
                        connection.properties.destroying_webs_frees_ghosts = false
                        connection.properties.blocked_by = nil
                    end
                    didClear = true
                end
                cleared[#cleared + 1] = {
                    from = roomId,
                    to = toId,
                    cleared = didClear,
                }
            end
        end

        return cleared
    end

    local function findHauntingFeaturesInRooms(manager, roomIds)
        local features = {}
        for _, containedRoomId in ipairs(roomIds or {}) do
            local containedRoom = manager:getRoom(containedRoomId)
            for _, feature in ipairs((containedRoom and containedRoom.features) or {}) do
                if feature.haunting then
                    features[#features + 1] = {
                        roomId = containedRoomId,
                        feature = feature,
                    }
                end
            end
        end
        return features
    end

    local function markGhostActivityFreed(manager, roomIds, unappeased, outcome)
        local affected = {}
        for _, containedRoomId in ipairs(roomIds or {}) do
            local containedRoom = manager:getRoom(containedRoomId)
            if containedRoom and containedRoom.goldenGhostActivity then
                containedRoom.goldenGhostActivity.containedByWebs = false
                containedRoom.goldenGhostActivity.ghostsFreed = true
                containedRoom.goldenGhostActivity.freedUnappeased = unappeased == true
                containedRoom.goldenGhostActivity.disasterPending = unappeased == true
                containedRoom.goldenGhostActivity.freedomOutcome = outcome
                affected[#affected + 1] = containedRoomId
            end
        end
        return affected
    end

    function manager:resolveBrainSpiderWebDestruction(roomId, featureId, opts)
        opts = opts or {}
        local feature = self:getFeature(roomId, featureId)
        local webs = feature and feature.brainSpiderWebs
        if not feature or not webs then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                action = "clear_webbing",
                failureReason = "brain_spider_webs_not_found",
                description = "There are no brain-spider webs to clear here.",
                effects = {},
            }
        end

        if feature.destroyed or webs.destroyed then
            return {
                success = true,
                roomId = roomId,
                featureId = featureId,
                action = "clear_webbing",
                alreadyCleared = true,
                description = "The webbing has already been cleared.",
                effects = { "brain_spider_webs_already_cleared" },
            }
        end

        feature.destroyed = true
        feature.state = "destroyed"
        feature.ghostContainmentCleared = webs.blocksGhosts == true
        webs.destroyed = true
        webs.blocksGhosts = false
        webs.solidToTangible = false
        webs.solidToIntangible = false

        local graph = opts.dungeon or self.dungeon
        local clearedConnections = clearFeatureGhostBlockConnections(graph, roomId, featureId)
        local freedHauntings = {}
        local disasterPending = false
        local outcome = nil

        if feature.ghostContainmentCleared then
            for _, record in ipairs(findHauntingFeaturesInRooms(self, webs.containedRooms)) do
                local haunting = record.feature.haunting
                local appeased = record.feature.hauntingAppeased == true or haunting.appeased == true
                haunting.freed = true
                haunting.freedByRoomId = roomId
                haunting.freedByFeatureId = featureId
                record.feature.state = appeased and "freed_appeased" or "freed_unappeased"
                if not appeased then
                    haunting.freedUnappeased = true
                    haunting.disasterPending = true
                    haunting.freedomOutcome = haunting.freedUnappeasedOutcome or "natural_disaster"
                    outcome = outcome or haunting.freedomOutcome
                    disasterPending = true
                end
                freedHauntings[#freedHauntings + 1] = {
                    roomId = record.roomId,
                    featureId = record.feature.id,
                    appeased = appeased,
                    outcome = haunting.freedomOutcome,
                }
            end
        end

        local affectedRooms = markGhostActivityFreed(self, webs.containedRooms, disasterPending, outcome)
        local result = {
            success = true,
            roomId = roomId,
            featureId = featureId,
            action = "clear_webbing",
            feature = feature,
            clearedConnections = clearedConnections,
            freedHauntings = freedHauntings,
            affectedRooms = affectedRooms,
            disasterPending = disasterPending,
            outcome = outcome,
            description = disasterPending and
                "The silvery webs are destroyed, freeing the unappeased golden ghosts." or
                "The silvery webs are destroyed.",
            effects = { "brain_spider_webs_destroyed" },
        }
        if feature.ghostContainmentCleared then
            result.effects[#result.effects + 1] = "ghost_containment_cleared"
        end
        if disasterPending then
            result.effects[#result.effects + 1] = "golden_ghosts_freed_unappeased"
            result.effects[#result.effects + 1] = "natural_disaster_pending"
        end

        self.eventBus:emit(events.EVENTS.FEATURE_GHOST_CONTAINMENT_CLEARED, {
            roomId = roomId,
            featureId = featureId,
            result = result,
            clearedConnections = clearedConnections,
            freedHauntings = freedHauntings,
            affectedRooms = affectedRooms,
        })

        return result
    end

    local function featureGhostInterferenceActive(feature)
        local interference = feature and feature.ghostInterference
        return interference and interference.activeUntilDeathMasksReturned == true and
            interference.appeased ~= true and feature.ghostInterferenceCleared ~= true
    end

    local function normalizePuzzleValue(value)
        if type(value) ~= "string" then
            return value
        end
        return value:lower():gsub("%s+", "_")
    end

    local function submittedPuzzleSolution(opts)
        opts = opts or {}
        local solution = opts.solution or opts.symbols or opts.alignments
        if type(solution) == "table" then
            return solution
        end
        return {
            maiden = opts.maiden,
            mother = opts.mother,
            crone = opts.crone,
        }
    end

    local function puzzleSolutionMatches(expected, submitted)
        local missing = {}
        local mismatched = {}
        for key, value in pairs(expected or {}) do
            local actual = submitted and submitted[key]
            if actual == nil then
                missing[#missing + 1] = key
            elseif normalizePuzzleValue(actual) ~= normalizePuzzleValue(value) then
                mismatched[#mismatched + 1] = key
            end
        end
        return #missing == 0 and #mismatched == 0, missing, mismatched
    end

    function manager:resolveTripartitePedestalPuzzle(roomId, featureId, opts)
        opts = opts or {}
        local feature = self:getFeature(roomId, featureId)
        local puzzle = feature and feature.puzzle
        if not feature or not puzzle then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                action = "solve_puzzle",
                failureReason = "puzzle_not_found",
                description = "There is no puzzle to solve here.",
                effects = {},
            }
        end

        if feature.puzzleSolved or puzzle.solved then
            return {
                success = true,
                roomId = roomId,
                featureId = featureId,
                action = "solve_puzzle",
                alreadySolved = true,
                description = "The puzzle is already solved.",
                effects = { "puzzle_already_solved" },
            }
        end

        local targetFeatureId = puzzle.success and puzzle.success.disarmsTrap
        local targetFeature = targetFeatureId and self:getFeature(roomId, targetFeatureId) or nil
        if featureGhostInterferenceActive(targetFeature) then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                action = "solve_puzzle",
                blockedBy = targetFeatureId,
                failureReason = "ghost_interference_active",
                description = "The golden ghosts prevent anyone from deactivating the statue.",
                effects = { "ghost_interference_active" },
            }
        end

        local submitted = submittedPuzzleSolution(opts)
        local matches, missing, mismatched = puzzleSolutionMatches(puzzle.solution, submitted)
        if not matches then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                action = "solve_puzzle",
                missing = missing,
                mismatched = mismatched,
                failureReason = "puzzle_solution_incorrect",
                description = "The symbols do not line up with the statue faces.",
                effects = { "puzzle_solution_incorrect" },
            }
        end

        feature.puzzleSolved = true
        feature.state = "solved"
        puzzle.solved = true
        puzzle.submittedSolution = deepCopy(submitted)
        puzzle.solvedBy = opts.actorId or (opts.actor and opts.actor.id)

        local disarmedFeature = nil
        if targetFeature then
            disarmedFeature = targetFeature
            targetFeature.trapDisarmed = true
            targetFeature.astrologicalPedestalSolved = true
            if targetFeature.trap then
                targetFeature.trap.disarmed = true
                targetFeature.trap.disarmedBy = featureId
            end
            if targetFeature.crown then
                targetFeature.crown.safeRemoval = puzzle.success and puzzle.success.safeCrownRemoval == true
                targetFeature.crown.safeRemovalBy = featureId
            end
        end

        local result = {
            success = true,
            roomId = roomId,
            featureId = featureId,
            action = "solve_puzzle",
            puzzle = puzzle,
            disarmedFeatureId = targetFeatureId,
            disarmedFeature = disarmedFeature,
            description = "The sun, moon, and star align with the statue faces. The crown can now be removed safely.",
            effects = { "tripartite_pedestal_solved", "puzzle_solved" },
        }
        if disarmedFeature then
            result.effects[#result.effects + 1] = "tripartite_statue_trap_disarmed"
            result.effects[#result.effects + 1] = "safe_crown_removal_enabled"
        end

        self.eventBus:emit(events.EVENTS.FEATURE_PUZZLE_SOLVED, {
            roomId = roomId,
            featureId = featureId,
            result = result,
            disarmedFeatureId = targetFeatureId,
        })

        return result
    end

    function manager:resolveTripartiteCrownRemoval(roomId, featureId, actor, opts)
        opts = opts or {}
        local feature = self:getFeature(roomId, featureId)
        local crown = feature and feature.crown
        if not feature or not crown or not crown.loot then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                action = "take_crown",
                failureReason = "crown_not_found",
                description = "There is no crown to claim here.",
                effects = {},
            }
        end

        if featureGhostInterferenceActive(feature) then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                action = "take_crown",
                failureReason = "ghost_interference_active",
                description = "The golden ghosts prevent anyone from taking the crown.",
                effects = { "ghost_interference_active" },
            }
        end

        if crown.removed then
            return {
                success = true,
                roomId = roomId,
                featureId = featureId,
                action = "take_crown",
                alreadyClaimed = true,
                description = "The crown has already been removed.",
                effects = { "crown_already_removed" },
            }
        end

        local safeRemoval = crown.safeRemoval == true or feature.astrologicalPedestalSolved == true or
            (feature.trap and feature.trap.disarmed == true)
        if crown.safeRemovalRequires and not safeRemoval then
            feature.trapTriggered = true
            if feature.trap then
                feature.trap.triggered = true
                feature.trap.triggeredBy = "crown_removed_before_puzzle_solved"
            end
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                action = "take_crown",
                trapTriggered = true,
                trap = feature.trap,
                failureReason = "crown_trap_triggered",
                description = "Removing the crown before solving the pedestal puzzle triggers the statue trap.",
                effects = { "tripartite_crown_trap_triggered" },
            }
        end

        local item = nil
        local added = false
        local addReason = nil
        if crown.loot then
            local inventory = require('logic.inventory')
            item = inventory.createItemFromTemplate(crown.loot)
            if actor and actor.inventory and actor.inventory.addItem and item then
                added, addReason = actor.inventory:addItem(item, opts.location or inventory.LOCATIONS.PACK)
                if not added then
                    return {
                        success = false,
                        roomId = roomId,
                        featureId = featureId,
                        action = "take_crown",
                        item = item,
                        failureReason = addReason or "inventory_full",
                        description = "There is no room to carry the crown.",
                        effects = { "inventory_full" },
                    }
                end
            end
        end

        crown.removed = true
        crown.removedBy = actor and actor.id or opts.actorId
        crown.removedSafely = true
        feature.crownLootTaken = true
        feature.state = "crown_removed"

        local result = {
            success = true,
            roomId = roomId,
            featureId = featureId,
            action = "take_crown",
            actor = actor,
            actorId = actor and actor.id or nil,
            item = item,
            addedToInventory = added,
            description = "The thorn-antlered silver crown is removed safely.",
            effects = { "tripartite_crown_removed", "treasure_claimed" },
        }

        self.eventBus:emit(events.EVENTS.FEATURE_TREASURE_CLAIMED, {
            roomId = roomId,
            featureId = featureId,
            item = item,
            actorId = actor and actor.id or nil,
            result = result,
        })

        return result
    end

    function manager:resolveFeatureObservation(roomId, featureId, observationKey, opts)
        if type(observationKey) == "table" and opts == nil then
            opts = observationKey
            observationKey = opts.observation or opts.key
        end
        opts = opts or {}

        local feature = self:getFeature(roomId, featureId)
        if not feature then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                error = "feature_not_found",
                effects = {},
            }
        end

        local observations = feature.observations or {}
        if not observationKey then
            for key, value in pairs(observations) do
                if value then
                    observationKey = key
                    break
                end
            end
        end

        local detail = observationKey and observations[observationKey]
        if not detail then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                feature = feature,
                observation = observationKey,
                error = "observation_not_found",
                effects = {},
            }
        end

        feature.revealedObservations = feature.revealedObservations or {}
        local alreadyRevealed = feature.revealedObservations[observationKey] == true
        feature.revealedObservations[observationKey] = true
        feature.observationRevealed = true
        feature.lastObservationRevealed = observationKey

        local result = {
            success = true,
            roomId = roomId,
            featureId = featureId,
            feature = feature,
            observation = observationKey,
            observationDetail = detail,
            actorId = opts.actorId or (opts.actor and opts.actor.id) or nil,
            alreadyRevealed = alreadyRevealed,
            hiddenInfo = feature.hidden_description,
            effects = { "feature_observation_revealed" },
        }
        if observationKey == "brightensWhileEatingMoss" then
            result.effects[#result.effects + 1] = "moss_benefit_clue_revealed"
        end

        if not alreadyRevealed then
            self.eventBus:emit(events.EVENTS.FEATURE_OBSERVATION_REVEALED, {
                roomId = roomId,
                featureId = featureId,
                observation = observationKey,
                actorId = result.actorId,
                hiddenInfo = result.hiddenInfo,
                result = result,
            })
        end

        return result
    end

    local function getFeatureLootTemplateId(feature)
        if not feature then
            return nil
        end
        if type(feature.loot) == "string" then
            return feature.loot
        end
        if type(feature.loot) == "table" then
            return feature.loot[1]
        end
        return feature.itemTemplateId or feature.itemId
    end

    local function getFeatureLootTemplateIds(feature)
        if not feature then
            return {}
        end
        if type(feature.loot) == "string" then
            return { feature.loot }
        end
        if type(feature.loot) == "table" then
            return feature.loot
        end
        local templateId = feature.itemTemplateId or feature.itemId
        if templateId then
            return { templateId }
        end
        return {}
    end

    function manager:resolveSingleMealFeature(roomId, featureId, actor, opts)
        opts = opts or {}
        local feature = self:getFeature(roomId, featureId)
        if not feature then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                error = "feature_not_found",
                effects = {},
            }
        end
        if feature.singleMeal ~= true then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                feature = feature,
                error = "single_meal_not_supported",
                effects = {},
            }
        end
        if feature.singleMealClaimed or feature.lootTaken or feature.state == "depleted" then
            return {
                success = true,
                roomId = roomId,
                featureId = featureId,
                feature = feature,
                alreadyClaimed = true,
                effects = { "single_meal_already_claimed" },
            }
        end

        local templateId = getFeatureLootTemplateId(feature)
        if not templateId then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                feature = feature,
                error = "feature_loot_not_found",
                effects = {},
            }
        end

        local inventory = require('logic.inventory')
        local item = inventory.createItemFromTemplate(templateId)
        if not item then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                feature = feature,
                templateId = templateId,
                error = "item_template_not_found",
                effects = {},
            }
        end

        local added = false
        local addReason = nil
        local location = opts.location or inventory.LOCATIONS.PACK
        if actor and actor.inventory and actor.inventory.addItem then
            added, addReason = actor.inventory:addItem(item, location)
            if not added then
                return {
                    success = false,
                    roomId = roomId,
                    featureId = featureId,
                    feature = feature,
                    item = item,
                    templateId = templateId,
                    failureReason = addReason or "inventory_full",
                    effects = { "inventory_full" },
                }
            end
        end

        feature.singleMealClaimed = true
        feature.singleMealClaimedBy = actor and actor.id or opts.actorId
        feature.lootTaken = true
        feature.claimedLootTemplateId = templateId
        feature.claimedItemId = item.id
        feature.state = "depleted"

        local itemProps = item.properties or {}
        local result = {
            success = true,
            roomId = roomId,
            featureId = featureId,
            feature = feature,
            actor = actor,
            actorId = actor and actor.id or opts.actorId,
            item = item,
            templateId = templateId,
            addedToInventory = added,
            location = added and location or nil,
            itemEffect = itemProps.useEffect,
            effects = { "single_meal_claimed", "feature_loot_claimed" },
        }
        if item.isRation or itemProps.ration == true then
            result.effects[#result.effects + 1] = "ration_claimed"
        end
        if itemProps.healEffect == true or (itemProps.useEffect and itemProps.useEffect.type == "heal_wound") then
            result.effects[#result.effects + 1] = "heal_effect_available"
        end

        self.eventBus:emit(events.EVENTS.FEATURE_LOOT_CLAIMED, {
            roomId = roomId,
            featureId = featureId,
            actorId = result.actorId,
            item = item,
            templateId = templateId,
            result = result,
        })

        return result
    end

    function manager:resolveFeatureLootClaim(roomId, featureId, actor, opts)
        opts = opts or {}
        local feature = self:getFeature(roomId, featureId)
        if not feature then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                error = "feature_not_found",
                effects = {},
            }
        end
        if feature.singleMeal then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                feature = feature,
                error = "single_meal_requires_dedicated_resolver",
                effects = {},
            }
        end
        if feature.lootTaken or feature.state == "looted" then
            return {
                success = true,
                roomId = roomId,
                featureId = featureId,
                feature = feature,
                alreadyClaimed = true,
                effects = { "feature_loot_already_claimed" },
                items = {},
                templateIds = {},
                description = "The useful contents have already been claimed.",
            }
        end

        local templateIds = getFeatureLootTemplateIds(feature)
        if #templateIds == 0 then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                feature = feature,
                error = "feature_loot_not_found",
                effects = {},
            }
        end

        local inventory = require('logic.inventory')
        local items = {}
        for _, templateId in ipairs(templateIds) do
            local item = inventory.createItemFromTemplate(templateId)
            if not item then
                return {
                    success = false,
                    roomId = roomId,
                    featureId = featureId,
                    feature = feature,
                    templateId = templateId,
                    error = "item_template_not_found",
                    effects = {},
                }
            end
            items[#items + 1] = item
        end

        local added = {}
        local location = opts.location or inventory.LOCATIONS.PACK
        if actor and actor.inventory and actor.inventory.addItem then
            for _, item in ipairs(items) do
                local ok, reason = actor.inventory:addItem(item, location)
                if not ok then
                    for _, addedItem in ipairs(added) do
                        actor.inventory:removeItem(addedItem.id)
                    end
                    return {
                        success = false,
                        roomId = roomId,
                        featureId = featureId,
                        feature = feature,
                        item = item,
                        templateId = item.templateId,
                        failureReason = reason or "inventory_full",
                        effects = { "inventory_full" },
                    }
                end
                added[#added + 1] = item
            end
        end

        feature.lootTaken = true
        feature.lootClaimedBy = actor and actor.id or opts.actorId
        feature.claimedLootTemplateIds = deepCopy(templateIds)
        feature.claimedItems = {}
        for _, item in ipairs(items) do
            feature.claimedItems[#feature.claimedItems + 1] = {
                id = item.id,
                templateId = item.templateId,
                name = item.name,
            }
        end
        feature.state = opts.state or "looted"

        local hasTreasure = false
        for _, item in ipairs(items) do
            local props = item.properties or {}
            if props.treasure or props.currency or props.art or props.jewelry then
                hasTreasure = true
                break
            end
        end

        local result = {
            success = true,
            roomId = roomId,
            featureId = featureId,
            feature = feature,
            actor = actor,
            actorId = actor and actor.id or opts.actorId,
            items = items,
            templateIds = templateIds,
            addedToInventory = actor and actor.inventory ~= nil or false,
            location = actor and actor.inventory and location or nil,
            effects = { "feature_loot_claimed" },
            description = "You claim the useful contents.",
        }
        if hasTreasure then
            result.effects[#result.effects + 1] = "treasure_claimed"
        end

        self.eventBus:emit(events.EVENTS.FEATURE_LOOT_CLAIMED, {
            roomId = roomId,
            featureId = featureId,
            actorId = result.actorId,
            items = items,
            templateIds = templateIds,
            result = result,
        })

        return result
    end

    function manager:resolveFragileScrollHandling(roomId, featureId, actor, opts)
        opts = opts or {}
        local feature = self:getFeature(roomId, featureId)
        local scrolls = feature and feature.fragileScrolls
        if not feature or not scrolls then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                error = "fragile_scrolls_not_found",
                effects = {},
            }
        end

        if feature.fragileScrollsDestroyed or scrolls.destroyed or feature.state == "destroyed" then
            return {
                success = true,
                roomId = roomId,
                featureId = featureId,
                feature = feature,
                alreadyHandled = true,
                destroyed = true,
                effects = { "fragile_scrolls_already_destroyed" },
            }
        end

        if feature.scrollsPreserved or feature.lootTaken then
            return {
                success = true,
                roomId = roomId,
                featureId = featureId,
                feature = feature,
                alreadyHandled = true,
                preserved = feature.scrollsPreserved == true,
                effects = { "fragile_scrolls_already_handled" },
            }
        end

        local careful = opts.careful == true or opts.openedCarefully == true or
            opts.handledCarefully == true or opts.action == "preserve_fragile_scrolls"
        local rightEnvironment = opts.rightEnvironment == true or opts.properEnvironment == true or
            opts.specialCare == true or opts.transportCare == true or opts.action == "preserve_fragile_scrolls"

        if scrolls.requiresCarefulOpening and not careful or
           scrolls.requiresRightEnvironment and not rightEnvironment then
            scrolls.destroyed = true
            scrolls.mishandled = true
            scrolls.mishandledBy = actor and actor.id or opts.actorId
            feature.fragileScrollsDestroyed = true
            feature.lootTaken = true
            feature.state = "destroyed"

            local result = {
                success = true,
                roomId = roomId,
                featureId = featureId,
                feature = feature,
                actor = actor,
                actorId = actor and actor.id or opts.actorId,
                preserved = false,
                destroyed = true,
                mishandledOutcome = scrolls.mishandledOutcome or "crack_and_fall_to_dust",
                description = "The fragile scrolls crack and fall to dust.",
                effects = { "fragile_scrolls_destroyed", "scrolls_cracked_to_dust" },
            }
            self.eventBus:emit(events.EVENTS.FEATURE_SCROLL_HANDLED, {
                roomId = roomId,
                featureId = featureId,
                actorId = result.actorId,
                result = result,
            })
            return result
        end

        local templateId = getFeatureLootTemplateId(feature)
        if not templateId then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                feature = feature,
                error = "feature_loot_not_found",
                effects = {},
            }
        end

        local inventory = require('logic.inventory')
        local item = inventory.createItemFromTemplate(templateId)
        if not item then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                feature = feature,
                templateId = templateId,
                error = "item_template_not_found",
                effects = {},
            }
        end

        item.openedCarefully = true
        item.preservedFromRoomId = roomId
        item.preservedFromFeatureId = featureId
        item.properties = item.properties or {}
        item.properties.openedCarefully = true

        local added = false
        local addReason = nil
        local location = opts.location or inventory.LOCATIONS.PACK
        if actor and actor.inventory and actor.inventory.addItem then
            added, addReason = actor.inventory:addItem(item, location)
            if not added then
                return {
                    success = false,
                    roomId = roomId,
                    featureId = featureId,
                    feature = feature,
                    item = item,
                    templateId = templateId,
                    failureReason = addReason or "inventory_full",
                    effects = { "inventory_full" },
                }
            end
        end

        scrolls.preserved = true
        scrolls.openedCarefully = true
        scrolls.preservedBy = actor and actor.id or opts.actorId
        feature.scrollsPreserved = true
        feature.lootTaken = true
        feature.claimedLootTemplateId = templateId
        feature.claimedItemId = item.id
        feature.state = "preserved"

        local result = {
            success = true,
            roomId = roomId,
            featureId = featureId,
            feature = feature,
            actor = actor,
            actorId = actor and actor.id or opts.actorId,
            item = item,
            templateId = templateId,
            preserved = true,
            addedToInventory = added,
            location = added and location or nil,
            antiquarianValueRange = scrolls.antiquarianValueRange or (item.properties and item.properties.antiquarianValueRange),
            description = "The fragile royal scrolls are opened carefully and preserved for transport.",
            effects = { "fragile_scrolls_preserved", "feature_loot_claimed" },
        }

        self.eventBus:emit(events.EVENTS.FEATURE_SCROLL_HANDLED, {
            roomId = roomId,
            featureId = featureId,
            actorId = result.actorId,
            item = item,
            templateId = templateId,
            result = result,
        })
        self.eventBus:emit(events.EVENTS.FEATURE_LOOT_CLAIMED, {
            roomId = roomId,
            featureId = featureId,
            actorId = result.actorId,
            item = item,
            templateId = templateId,
            result = result,
        })

        return result
    end

    function manager:resolveSealedChronicleOpening(roomId, featureId, actor, opts)
        opts = opts or {}
        local feature = self:getFeature(roomId, featureId)
        local chronicle = feature and feature.chronicle
        if not feature or not chronicle then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                error = "sealed_chronicle_not_found",
                effects = {},
            }
        end

        if feature.chronicleOpened or chronicle.opened then
            return {
                success = true,
                roomId = roomId,
                featureId = featureId,
                feature = feature,
                alreadyOpened = true,
                openerId = chronicle.openerId,
                effects = { "chronicle_scroll_already_opened" },
            }
        end

        local templateId = getFeatureLootTemplateId(feature)
        if not templateId then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                feature = feature,
                error = "feature_loot_not_found",
                effects = {},
            }
        end

        local inventory = require('logic.inventory')
        local item = inventory.createItemFromTemplate(templateId)
        if not item then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                feature = feature,
                templateId = templateId,
                error = "item_template_not_found",
                effects = {},
            }
        end

        local openerId = actor and actor.id or opts.actorId
        item.opened = true
        item.openerId = openerId
        item.activeChronicle = true
        item.growingUntilDestroyed = chronicle.growsUntilDestroyed == true
        item.properties = item.properties or {}
        item.properties.opened = true
        item.properties.openerId = openerId
        item.properties.activeChronicle = true
        item.properties.minuteByMinuteChronicle = chronicle.minuteByMinute == true
        item.properties.becomesInfinitelyLong = chronicle.becomesInfinitelyLong == true
        item.properties.growsUntilDestroyed = chronicle.growsUntilDestroyed == true

        local added = false
        local addReason = nil
        local location = opts.location or inventory.LOCATIONS.PACK
        if actor and actor.inventory and actor.inventory.addItem then
            added, addReason = actor.inventory:addItem(item, location)
            if not added then
                return {
                    success = false,
                    roomId = roomId,
                    featureId = featureId,
                    feature = feature,
                    item = item,
                    templateId = templateId,
                    failureReason = addReason or "inventory_full",
                    effects = { "inventory_full" },
                }
            end
        end

        chronicle.opened = true
        chronicle.openerId = openerId
        chronicle.active = true
        chronicle.growing = chronicle.growsUntilDestroyed == true
        feature.chronicleOpened = true
        feature.lootTaken = true
        feature.claimedLootTemplateId = templateId
        feature.claimedItemId = item.id
        feature.state = "chronicling"

        local result = {
            success = true,
            roomId = roomId,
            featureId = featureId,
            feature = feature,
            actor = actor,
            actorId = openerId,
            item = item,
            templateId = templateId,
            addedToInventory = added,
            location = added and location or nil,
            description = "The Vetus chronicle begins recording the opener minute by minute.",
            effects = {
                "chronicle_scroll_opened",
                "opener_chronicle_started",
                "chronicle_grows_until_destroyed",
                "feature_loot_claimed",
            },
        }

        self.eventBus:emit(events.EVENTS.FEATURE_SCROLL_HANDLED, {
            roomId = roomId,
            featureId = featureId,
            actorId = result.actorId,
            item = item,
            templateId = templateId,
            result = result,
        })
        self.eventBus:emit(events.EVENTS.FEATURE_LOOT_CLAIMED, {
            roomId = roomId,
            featureId = featureId,
            actorId = result.actorId,
            item = item,
            templateId = templateId,
            result = result,
        })

        return result
    end

    --- Update a feature's state
    function manager:setFeatureState(roomId, featureId, newState)
        local feature = self:getFeature(roomId, featureId)
        if feature then
            local oldState = feature.state
            feature.state = newState

            self.eventBus:emit(events.EVENTS.FEATURE_STATE_CHANGED, {
                roomId    = roomId,
                featureId = featureId,
                oldState  = oldState,
                newState  = newState,
            })

            return true
        end
        return false
    end

    --- Check if a feature is in a specific state
    function manager:isFeatureState(roomId, featureId, state)
        local feature = self:getFeature(roomId, featureId)
        return feature and feature.state == state
    end

    --- S11.3: Update arbitrary feature properties (for loot, flags, etc.)
    -- @param roomId string: Room containing the feature
    -- @param featureId string: Feature to update
    -- @param updates table: Key-value pairs to merge into feature
    -- @return boolean: success
    function manager:updateFeatureState(roomId, featureId, updates)
        local feature = self:getFeature(roomId, featureId)
        if not feature then
            return false
        end

        for key, value in pairs(updates) do
            feature[key] = value
        end

        self.eventBus:emit(events.EVENTS.FEATURE_UPDATED, {
            roomId = roomId,
            featureId = featureId,
            updates = updates,
        })

        return true
    end

    --- Get all features of a specific type in a room
    function manager:getFeaturesByType(roomId, featureType)
        local room = self.rooms[roomId]
        if not room then return {} end

        local result = {}
        for _, feat in ipairs(room.features) do
            if feat.type == featureType then
                result[#result + 1] = feat
            end
        end
        return result
    end

    local function uniqueFeatureId(room, baseId)
        local wanted = baseId
        local suffix = 2
        local seen = {}
        for _, feature in ipairs(room.features or {}) do
            seen[feature.id] = true
        end
        while seen[wanted] do
            wanted = baseId .. "_" .. tostring(suffix)
            suffix = suffix + 1
        end
        return wanted
    end

    --- Add a feature to a room.
    function manager:addFeature(roomId, feature)
        local room = self.rooms[roomId]
        if not room or not feature then
            return nil
        end

        feature.id = uniqueFeatureId(room, feature.id or "feature")
        room.features[#room.features + 1] = feature

        self.eventBus:emit(events.EVENTS.FEATURE_UPDATED, {
            roomId = roomId,
            featureId = feature.id,
            feature = feature,
            added = true,
        })

        return feature
    end

    --- Turn a defeated monster into a fresh corpse POI that can be harvested.
    function manager:addCorpseForEntity(roomId, entity, opts)
        opts = opts or {}
        local room = self.rooms[roomId]
        if not room then
            return nil, "room_not_found"
        end

        local alchemyData = entity and entity.alchemy
        if not entity or entity.isPC or not alchemyData or alchemyData.noReagent or not alchemyData.reagentTemplateId then
            return nil, "no_harvestable_reagents"
        end

        local isDead = entity.dead == true or (entity.conditions and entity.conditions.dead == true)
        if not isDead then
            return nil, "entity_not_dead"
        end

        for _, feature in ipairs(room.features or {}) do
            if feature.defeatedEntityId == entity.id then
                return feature
            end
        end

        local corpse = {
            id = opts.id or ("corpse_" .. tostring(entity.id or entity.blueprintId or "monster")),
            name = (entity.name or "Monster") .. " corpse",
            type = "corpse",
            description = "The fresh corpse of " .. (entity.name or "a monster") .. " lies here.",
            state = "fresh",
            isCorpse = true,
            freshCorpse = true,
            defeatedEntityId = entity.id,
            sourceBlueprintId = entity.blueprintId,
            defeatedAtWatch = opts.currentWatch,
            alchemy = deepCopy(entity.alchemy),
        }

        self:removeMob(roomId, entity.id)
        return self:addFeature(roomId, corpse)
    end

    --- Get all interactable features in a room
    function manager:getInteractableFeatures(roomId)
        local room = self.rooms[roomId]
        if not room then return {} end

        local result = {}
        for _, feat in ipairs(room.features) do
            -- Skip destroyed/removed features
            if feat.state ~= "destroyed" and feat.state ~= "removed" then
                result[#result + 1] = feat
            end
        end
        return result
    end

    ----------------------------------------------------------------------------
    -- MOB MANAGEMENT
    ----------------------------------------------------------------------------

    --- Add a mob to a room
    function manager:addMob(roomId, entityId)
        local room = self.rooms[roomId]
        if room then
            room.mobs[#room.mobs + 1] = entityId
        end
    end

    --- Remove a mob from a room
    function manager:removeMob(roomId, entityId)
        local room = self.rooms[roomId]
        if room then
            for i, id in ipairs(room.mobs) do
                if id == entityId then
                    table.remove(room.mobs, i)
                    return true
                end
            end
        end
        return false
    end

    --- Get all mobs in a room
    function manager:getMobs(roomId)
        local room = self.rooms[roomId]
        return room and room.mobs or {}
    end

    local function isMinorArcanaSuit(suit)
        if suit == constants.SUITS.SWORDS or suit == constants.SUITS.PENTACLES or
           suit == constants.SUITS.CUPS or suit == constants.SUITS.WANDS then
            return true
        end

        if type(suit) == "string" then
            local normalized = suit:lower():gsub("%s+", "_")
            return normalized == "swords" or normalized == "pentacles" or normalized == "disks" or
                normalized == "cups" or normalized == "wands" or normalized == "batons"
        end

        return false
    end

    local function isMinorArcanaFaceCard(card)
        if type(card) ~= "table" or not isMinorArcanaSuit(card.suit) then
            return false
        end
        local value = tonumber(card.value)
        return value ~= nil and value >= constants.FACE_VALUES.PAGE and value <= constants.FACE_VALUES.KING
    end

    local function getTopMinorDiscard(manager, opts)
        opts = opts or {}
        local minorDeck = opts.playerDeck or opts.minorDeck or manager.playerDeck
        if minorDeck and minorDeck.peekDiscard then
            local card = minorDeck:peekDiscard()
            if card then
                return card
            end
        end

        return opts.minorDiscardCard or opts.minorDiscard or opts.topMinorDiscardCard or opts.topMinorDiscard
    end

    local function appendSpawn(spawns, spawn)
        if not spawn or not spawn.blueprint_id then
            return nil
        end
        spawns[#spawns + 1] = spawn
        return spawn
    end

    local function spawnFromEncounter(encounter)
        if not encounter or not encounter.blueprint_id then
            return nil
        end
        local spawn = deepCopy(encounter)
        spawn.conditionalAllies = nil
        return spawn
    end

    local function collectionContainsIdentifier(collection, id)
        if not collection or not id then
            return false
        end
        if type(collection) ~= "table" then
            return collection == id
        end
        if collection[id] == true then
            return true
        end
        for _, value in pairs(collection) do
            if value == id then
                return true
            end
            if type(value) == "table" and (value.id == id or value.blueprint_id == id or
                value.blueprintId == id) then
                return true
            end
        end
        return false
    end

    local function encounterWasAlreadyResolved(manager, roomId, featureId, encounter, opts)
        if not encounter or encounter.unlessAlreadyEncountered ~= true then
            return false
        end
        opts = opts or {}
        if opts.alreadyEncountered == true or opts.encounterAlreadyResolved == true then
            return true
        end

        local blueprintId = encounter.blueprint_id or encounter.blueprintId
        local alreadyEncountered = opts.alreadyEncountered
        if type(alreadyEncountered) == "table" and
            (collectionContainsIdentifier(alreadyEncountered, blueprintId) or
             collectionContainsIdentifier(alreadyEncountered, featureId) or
             collectionContainsIdentifier(alreadyEncountered, roomId)) then
            return true
        end

        return collectionContainsIdentifier(opts.encounteredBlueprintIds or opts.alreadyEncounteredBlueprintIds or
                opts.encounteredBlueprints, blueprintId) or
            collectionContainsIdentifier(opts.encounteredFeatureIds or opts.alreadyEncounteredFeatureIds,
                featureId) or
            collectionContainsIdentifier(manager.encounteredBlueprintIds, blueprintId) or
            collectionContainsIdentifier(manager.encounteredFeatureIds, featureId)
    end

    local function recordEncounterResolved(manager, roomId, featureId, encounter)
        if not encounter then
            return
        end
        local blueprintId = encounter.blueprint_id or encounter.blueprintId
        if blueprintId then
            manager.encounteredBlueprintIds[blueprintId] = true
        end
        if featureId then
            manager.encounteredFeatureIds[featureId] = true
        end
        if roomId and featureId then
            manager.encounteredFeatureIds[roomId .. ":" .. featureId] = true
        end
    end

    local function markEncounterFeatureTriggered(feature, reason)
        feature.hidden = false
        feature.encounterTriggered = true
        feature.triggered = true
        feature.triggeredBy = reason or feature.triggeredBy
        feature.state = "active"
    end

    local function conditionalAllyMatches(ally, minorDiscard)
        if not ally or not ally.condition then
            return false, "condition_required"
        end
        if ally.condition == "minor_arcana_discard_face_card" then
            if isMinorArcanaFaceCard(minorDiscard) then
                return true, "minor_discard_face_card"
            end
            return false, "minor_discard_not_face_card"
        end
        return false, "unsupported_condition"
    end

    function manager:resolveEncounterFeature(roomId, featureId, opts)
        opts = opts or {}
        local feature = self:getFeature(roomId, featureId)
        local encounter = feature and feature.encounter
        if not encounter then
            return false, "Encounter feature not found"
        end

        local minorDiscard = getTopMinorDiscard(self, opts)
        local result = {
            success = true,
            roomId = roomId,
            featureId = featureId,
            feature = feature,
            encounter = encounter,
            minorDiscardCard = minorDiscard,
            spawns = {},
            activeConditionalAllies = {},
            inactiveConditionalAllies = {},
            effects = {},
        }

        if encounterWasAlreadyResolved(self, roomId, featureId, encounter, opts) then
            result.alreadyEncountered = true
            result.skipped = true
            result.effects[#result.effects + 1] = "encounter_already_encountered"
            return true, result
        end

        appendSpawn(result.spawns, spawnFromEncounter(encounter))

        for _, ally in ipairs(encounter.conditionalAllies or {}) do
            local conditionMet, reason = conditionalAllyMatches(ally, minorDiscard)
            local resolvedAlly = deepCopy(ally)
            resolvedAlly.conditionMet = conditionMet
            resolvedAlly.conditionReason = reason
            resolvedAlly.conditionCard = minorDiscard

            if conditionMet then
                result.activeConditionalAllies[#result.activeConditionalAllies + 1] = resolvedAlly
                local spawn = deepCopy(resolvedAlly)
                spawn.conditionCard = nil
                spawn.conditionMet = nil
                spawn.conditionReason = nil
                spawn.conditionalAlly = true
                appendSpawn(result.spawns, spawn)
            else
                result.inactiveConditionalAllies[#result.inactiveConditionalAllies + 1] = resolvedAlly
            end
        end

        return true, result
    end

    function manager:triggerEncounterFeature(roomId, featureId, opts)
        opts = opts or {}
        local feature = self:getFeature(roomId, featureId)
        local encounter = feature and feature.encounter
        if not feature or not encounter then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                error = "encounter_feature_not_found",
                effects = {},
                spawns = {},
            }
        end

        if encounterWasAlreadyResolved(self, roomId, featureId, encounter, opts) then
            feature.state = "absent"
            feature.absentBecauseAlreadyEncountered = true
            feature.lastSkippedReason = "already_encountered"
            return {
                success = true,
                roomId = roomId,
                featureId = featureId,
                feature = feature,
                encounter = encounter,
                reason = opts.reason or "feature_trigger",
                alreadyEncountered = true,
                skipped = true,
                effects = { "encounter_already_encountered" },
                spawns = {},
            }
        end

        local result = {
            success = true,
            roomId = roomId,
            featureId = featureId,
            feature = feature,
            encounter = encounter,
            reason = opts.reason or "feature_trigger",
            effects = { "feature_encounter_triggered" },
            spawns = {},
            alreadyTriggered = feature.encounterTriggered == true,
        }

        appendSpawn(result.spawns, spawnFromEncounter(encounter))
        if feature.hidden then
            result.effects[#result.effects + 1] = "hidden_encounter_revealed"
        end

        markEncounterFeatureTriggered(feature, result.reason)
        feature.lastTriggeredAtWatch = opts.watch
        feature.triggerCount = (feature.triggerCount or 0) + 1
        recordEncounterResolved(self, roomId, featureId, encounter)

        self.eventBus:emit(events.EVENTS.FEATURE_ENCOUNTER_TRIGGERED, {
            roomId = roomId,
            featureId = featureId,
            reason = result.reason,
            spawns = result.spawns,
            result = result,
        })

        return result
    end

    function manager:triggerFeatureLinkedEncounter(roomId, sourceFeatureId, opts)
        opts = opts or {}
        local source = self:getFeature(roomId, sourceFeatureId)
        local targetFeatureId = source and (source.triggeredEncounterFeatureId or
            source.triggerEncounterFeatureId or source.encounterFeatureId)
        if not targetFeatureId then
            return nil
        end

        return self:triggerEncounterFeature(roomId, targetFeatureId, {
            reason = opts.reason or "feature_investigated",
            watch = opts.watch,
        })
    end

    local function encounterEmergesOnEntry(feature)
        local encounter = feature and feature.encounter
        return encounter and (encounter.emergesOnEnter or encounter.emergesOnEntry or
            feature.emergesOnEnter or feature.emergesOnEntry)
    end

    local function entryEncounterStillBlocksPassage(feature)
        if not feature or not feature.encounter or not feature.encounter.blocksPassage then
            return false
        end
        return feature.state ~= "cleared" and feature.state ~= "defeated" and feature.state ~= "destroyed"
    end

    function manager:resolveRoomEntryTriggers(roomId, opts)
        opts = opts or {}
        local room = self:getRoom(roomId)
        if not room then
            return {
                success = false,
                roomId = roomId,
                error = "room_not_found",
                effects = {},
                triggers = {},
                spawns = {},
                blockingFeatureIds = {},
                blockedPassage = false,
            }
        end

        local result = {
            success = true,
            roomId = roomId,
            reason = opts.reason or "room_entry",
            effects = {},
            triggers = {},
            spawns = {},
            blockingFeatureIds = {},
            blockedPassage = false,
            alreadyResolved = room.entryTriggersResolved == true,
        }

        for _, feature in ipairs(room.features or {}) do
            if encounterEmergesOnEntry(feature) then
                if entryEncounterStillBlocksPassage(feature) then
                    result.blockedPassage = true
                    result.blockingFeatureIds[#result.blockingFeatureIds + 1] = feature.id
                end

                if feature.encounterTriggered ~= true and feature.entryTriggered ~= true then
                    feature.entryTriggered = true
                    feature.lastEntryTriggeredAtWatch = opts.watch
                    local trigger = self:triggerEncounterFeature(roomId, feature.id, {
                        reason = result.reason,
                        watch = opts.watch,
                    })
                    result.triggers[#result.triggers + 1] = trigger
                    for _, spawn in ipairs(trigger.spawns or {}) do
                        result.spawns[#result.spawns + 1] = spawn
                    end
                end
            end
        end

        if #result.triggers > 0 then
            result.effects[#result.effects + 1] = "room_entry_encounter_triggered"
        end
        if result.blockedPassage then
            result.effects[#result.effects + 1] = "room_entry_passage_blocked"
        end

        room.entryTriggersResolved = true
        room.lastEntryTriggerReason = result.reason
        room.lastEntryTriggerWatch = opts.watch

        return result
    end

    local function featureCanRevealBySecondSight(feature)
        local reveal = feature and feature.reveal or {}
        local encounter = feature and feature.encounter or {}
        return reveal.secondSight == true or feature.revealedBySecondSight == true or
            encounter.revealedBySecondSight == true
    end

    local function actorHasSecondSight(actor)
        if not actor then
            return false
        end
        if actor.secondSightActive == true or actor.canSeeTrueIllusions == true or actor.trueSight == true then
            return true
        end
        local sight = actor.secondSight
        if sight == true then
            return true
        end
        return type(sight) == "table" and sight.active ~= false
    end

    local function featureCanRevealByOutsideMissile(feature)
        local reveal = feature and feature.reveal or {}
        return reveal.missileAttacksFromOutsideRoom == true
    end

    local function appendUnique(items, value)
        if not value then
            return
        end
        for _, existing in ipairs(items) do
            if existing == value then
                return
            end
        end
        items[#items + 1] = value
    end

    function manager:resolveIllusoryFeatureReveal(roomId, featureId, opts)
        opts = opts or {}
        local feature = self:getFeature(roomId, featureId)
        if not feature then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                error = "feature_not_found",
                effects = {},
            }
        end

        local method = opts.method or opts.reason or
            (opts.fromOutsideRoom and "missile_attack" or "second_sight")
        local encounter = feature.encounter or {}
        local result = {
            success = false,
            roomId = roomId,
            featureId = featureId,
            feature = feature,
            encounter = encounter,
            method = method,
            effects = {},
            alreadyRevealed = feature.illusionRevealed == true or feature.state == "revealed" or
                feature.state == "escaped",
        }

        if method == "second_sight" then
            local actor = opts.actor or opts.observer
            if not featureCanRevealBySecondSight(feature) then
                result.error = "second_sight_reveal_not_supported"
                return result
            end
            if not actorHasSecondSight(actor) then
                result.error = "second_sight_inactive"
                return result
            end

            feature.secondSightRevealed = true
            feature.visibleThroughIllusion = true
            feature.seenBySecondSightActorIds = feature.seenBySecondSightActorIds or {}
            appendUnique(feature.seenBySecondSightActorIds, actor.id)
            encounter.revealedBySecondSight = true

            result.success = true
            result.revealed = true
            result.visibleOnlyToSecondSight = true
            result.actorId = actor and actor.id or nil
            result.effects[#result.effects + 1] = "illusion_seen_by_second_sight"
        elseif method == "missile_attack" or method == "outside_missile_attack" then
            local outside = opts.fromOutsideRoom == true or opts.outsideRoom == true or
                (opts.attackerRoomId ~= nil and opts.attackerRoomId ~= roomId)
            if not featureCanRevealByOutsideMissile(feature) then
                result.error = "missile_reveal_not_supported"
                return result
            end
            if not outside then
                result.error = "missile_reveal_requires_outside_room"
                return result
            end

            result.success = true
            result.revealed = true
            feature.hidden = false
            feature.illusionRevealed = true
            feature.revealedByMissileFire = true
            encounter.hiddenByIllusion = false
            encounter.revealed = true
            result.effects[#result.effects + 1] = "illusion_revealed_by_missile_fire"

            if encounter.escapesWhenRevealedByMissileFire then
                feature.state = "escaped"
                feature.escaped = true
                feature.kodiEscaped = true
                encounter.escaped = true
                encounter.escapedBy = "missile_attack_from_outside_room"
                result.escaped = true
                result.effects[#result.effects + 1] = "hidden_controller_escaped"
            else
                feature.state = "revealed"
            end
        else
            result.error = "unsupported_reveal_method"
            return result
        end

        if result.success and not result.alreadyRevealed then
            self.eventBus:emit(events.EVENTS.FEATURE_ILLUSION_REVEALED, {
                roomId = roomId,
                featureId = featureId,
                method = method,
                actorId = result.actorId,
                visibleOnlyToSecondSight = result.visibleOnlyToSecondSight,
                escaped = result.escaped,
                result = result,
            })
        end

        return result
    end

    function manager:resolveThrownObjectAtFeature(roomId, featureId, item, opts)
        opts = opts or {}
        local feature = self:getFeature(roomId, featureId)
        if not feature then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                error = "feature_not_found",
                effects = {},
            }
        end

        local behavior = feature.behavior or {}
        if behavior.spitsBackThrownObjects ~= true then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                feature = feature,
                item = item,
                error = "thrown_object_not_handled",
                effects = {},
            }
        end

        local destination = behavior.thrownObjectDestination or opts.returnDestination or "nearby"
        local result = {
            success = true,
            roomId = roomId,
            featureId = featureId,
            feature = feature,
            item = item,
            returned = true,
            consumed = false,
            destination = destination,
            effects = { "thrown_object_returned" },
        }

        feature.thrownObjectsReturned = (feature.thrownObjectsReturned or 0) + 1
        feature.lastReturnedObjectId = item and item.id or nil
        feature.lastReturnedObjectName = item and item.name or nil
        feature.lastReturnedObjectDestination = destination

        if item then
            item.returned = true
            item.consumed = false
            item.location = destination
            item.returnedByFeatureId = featureId
            item.returnedByFeatureName = feature.name
        end

        self.eventBus:emit(events.EVENTS.FEATURE_THROWN_OBJECT_RETURNED, {
            roomId = roomId,
            featureId = featureId,
            itemId = item and item.id or nil,
            destination = destination,
            result = result,
        })

        return result
    end

    local function drawMaleficenceCandidate(opts, drawIndex)
        if type(opts.drawMaleficence) == "function" then
            return opts.drawMaleficence(drawIndex, opts)
        end

        local draws = opts.maleficenceDraws or opts.draws
        if draws then
            return draws[drawIndex]
        end

        if drawIndex == 1 and (opts.maleficenceDraw ~= nil or opts.maleficence ~= nil) then
            return opts.maleficenceDraw or opts.maleficence
        end

        local deck = opts.maleficenceDeck or opts.deck
        if deck and type(deck.draw) == "function" then
            return deck.draw(deck)
        end

        return nil
    end

    local function textIdentifiesPlayerTarget(value)
        if type(value) == "table" then
            for _, child in pairs(value) do
                if textIdentifiesPlayerTarget(child) then
                    return true
                end
            end
            return false
        end
        if value == nil then
            return false
        end

        local text = tostring(value):lower()
        return text == "pc" or text == "pcs" or text == "player" or text == "players" or
            text == "adventurer" or text == "adventurers" or text == "sorcerer" or
            text == "actor" or text:find("random_player", 1, true) ~= nil or
            text:find("single_player", 1, true) ~= nil or
            text:find("specific_player", 1, true) ~= nil or
            text:find("target_player", 1, true) ~= nil or
            text:find("target_adventurer", 1, true) ~= nil
    end

    local playerTargetingMaleficenceEffects = {
        body_change = true,
        condition = true,
        damage = true,
        healing_block = true,
    }

    local function maleficenceEffectTargetsPlayer(effect)
        if type(effect) ~= "table" then
            return false
        end
        if effect.environmental == true or effect.environmentalOnly == true then
            return false
        end
        if effect.targetsPlayer == true or effect.playerTargeting == true or
            effect.specificPlayer == true then
            return true
        end
        if textIdentifiesPlayerTarget(effect.target or effect.targets or effect.appliesTo or
            effect.owner or effect.subject) then
            return true
        end
        return playerTargetingMaleficenceEffects[effect.type] == true
    end

    local function maleficenceTargetsPlayer(entry)
        if not entry then
            return false
        end
        if entry.environmental == true or entry.environmentalOnly == true then
            return false
        end
        if entry.targetsPlayer == true or entry.playerTargeting == true or
            entry.specificPlayer == true then
            return true
        end
        if textIdentifiesPlayerTarget(entry.target or entry.targets or entry.appliesTo or
            entry.owner or entry.subject) then
            return true
        end

        local nestedEntry = entry.entry
        if nestedEntry and nestedEntry ~= entry and maleficenceTargetsPlayer(nestedEntry) then
            return true
        end

        for _, effect in ipairs(entry.effects or {}) do
            if maleficenceEffectTargetsPlayer(effect) then
                return true
            end
        end

        return false
    end

    function manager:resolveStarChildWake(roomId, featureId, opts)
        opts = opts or {}
        local feature = self:getFeature(roomId, featureId)
        if not feature then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                error = "feature_not_found",
                effects = {},
            }
        end

        local wakeEffect = feature.wakeEffect or {}
        if not feature.starChild and not next(wakeEffect) then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                feature = feature,
                error = "wake_effect_not_supported",
                effects = {},
            }
        end
        if wakeEffect.trigger and wakeEffect.trigger ~= "attempt_to_wake" then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                feature = feature,
                error = "unsupported_wake_trigger",
                effects = {},
            }
        end

        local reason = opts.reason or "attempt_to_wake"
        local result = {
            success = true,
            roomId = roomId,
            featureId = featureId,
            feature = feature,
            wakeEffect = wakeEffect,
            reason = reason,
            actorId = opts.actorId or (opts.actor and opts.actor.id) or nil,
            environmentalOnly = wakeEffect.environmentalOnly == true,
            redrawPlayerTargetingEffects = wakeEffect.redrawPlayerTargetingEffects == true,
            returnsToSleep = wakeEffect.returnsToSleep == true,
            redraws = {},
            effects = { "star_child_woken" },
        }

        local drawIndex = 1
        local maxDraws = opts.maxMaleficenceDraws or 20
        while drawIndex <= maxDraws do
            local draw = drawMaleficenceCandidate(opts, drawIndex)
            if not draw then
                result.pendingMaleficenceDraw = true
                result.nextDrawIndex = drawIndex
                result.effects[#result.effects + 1] = "maleficence_draw_required"
                break
            end

            result.drawsAttempted = drawIndex
            if result.redrawPlayerTargetingEffects and maleficenceTargetsPlayer(draw) then
                result.redraws[#result.redraws + 1] = draw
                drawIndex = drawIndex + 1
            else
                result.maleficence = draw
                result.effects[#result.effects + 1] = "environmental_maleficence_drawn"
                break
            end
        end

        if #result.redraws > 0 then
            result.effects[#result.effects + 1] = "player_targeting_maleficence_redrawn"
        end
        if not result.maleficence and not result.pendingMaleficenceDraw then
            result.success = false
            result.error = "maleficence_redraw_limit_exceeded"
            result.effects[#result.effects + 1] = "maleficence_redraw_limit_exceeded"
        end

        local starChild = feature.starChild or {}
        feature.starChild = starChild
        starChild.awakenedBriefly = true
        starChild.wakeCount = (starChild.wakeCount or 0) + 1
        starChild.lastWakeReason = reason
        starChild.lastWakeActorId = result.actorId
        starChild.lastMaleficence = result.maleficence
        starChild.redrawnMaleficenceCount = #result.redraws
        starChild.pendingMaleficenceDraw = result.pendingMaleficenceDraw == true
        if result.returnsToSleep then
            starChild.hibernating = true
            starChild.returnedToSleep = true
            feature.state = "hibernating"
        else
            starChild.hibernating = false
            starChild.returnedToSleep = false
            feature.state = "awake"
        end
        feature.lastWakeEffectReason = reason
        feature.lastWakeEffectResult = {
            maleficence = result.maleficence,
            pendingMaleficenceDraw = result.pendingMaleficenceDraw == true,
            redrawCount = #result.redraws,
            effects = deepCopy(result.effects),
        }

        self.eventBus:emit(events.EVENTS.FEATURE_WAKE_EFFECT_RESOLVED, {
            roomId = roomId,
            featureId = featureId,
            reason = reason,
            actorId = result.actorId,
            maleficence = result.maleficence,
            pendingMaleficenceDraw = result.pendingMaleficenceDraw,
            redraws = result.redraws,
            result = result,
        })

        return result
    end

    function manager:resolveRoomTarryTriggers(roomId, opts)
        opts = opts or {}
        local room = self:getRoom(roomId)
        if not room then
            return {
                success = false,
                roomId = roomId,
                error = "room_not_found",
                effects = {},
                triggers = {},
                spawns = {},
            }
        end

        local watches = opts.watches or opts.watchCount or 1
        local result = {
            success = true,
            roomId = roomId,
            watches = watches,
            effects = {},
            triggers = {},
            spawns = {},
        }

        for _, feature in ipairs(room.features or {}) do
            local encounter = feature.encounter
            local threshold = encounter and encounter.attacksAfterTarryWatches
            if threshold and watches >= threshold and feature.encounterTriggered ~= true then
                local trigger = self:triggerEncounterFeature(roomId, feature.id, {
                    reason = opts.reason or "tarry",
                    watch = opts.watch,
                })
                result.triggers[#result.triggers + 1] = trigger
                for _, spawn in ipairs(trigger.spawns or {}) do
                    result.spawns[#result.spawns + 1] = spawn
                end
            end
        end

        if #result.triggers > 0 then
            result.effects[#result.effects + 1] = "room_tarry_encounter_triggered"
        end

        return result
    end

    ----------------------------------------------------------------------------
    -- DESCRIPTION GENERATION
    -- Concatenates base text with active features and mobs
    ----------------------------------------------------------------------------

    --- Generate description for a feature based on its state
    local function describeFeature(feature)
        -- State-specific descriptions could be added here
        -- For now, return the base description
        if feature.state == "destroyed" then
            return "The remains of " .. (feature.name or "something") .. " lie scattered here."
        elseif feature.state == "hidden" then
            return nil  -- Hidden features aren't described
        else
            return feature.description
        end
    end

    --- Get full room description (base + features + mobs)
    -- @param roomId string
    -- @param context table: { entityRegistry, showHidden }
    -- @return string
    function manager:getDescription(roomId, context)
        context = context or {}
        local room = self.rooms[roomId]
        if not room then
            return "You see nothing remarkable."
        end

        local parts = { room.base_description }

        -- Add feature descriptions
        for _, feature in ipairs(room.features) do
            local showHidden = context.showHidden or false

            -- Skip hidden features unless explicitly shown
            if feature.state == "hidden" and not showHidden then
                -- Don't describe
            else
                local desc = describeFeature(feature)
                if desc then
                    parts[#parts + 1] = desc
                end
            end
        end

        -- Add mob descriptions (requires entity registry to look up names)
        if #room.mobs > 0 and context.entityRegistry then
            local mobNames = {}
            for _, entityId in ipairs(room.mobs) do
                local entity = context.entityRegistry:get(entityId)
                if entity then
                    mobNames[#mobNames + 1] = entity.name
                end
            end

            if #mobNames > 0 then
                if #mobNames == 1 then
                    parts[#parts + 1] = "A " .. mobNames[1] .. " lurks here."
                else
                    local list = table.concat(mobNames, ", ", 1, #mobNames - 1)
                    list = list .. " and " .. mobNames[#mobNames]
                    parts[#parts + 1] = list .. " lurk here."
                end
            end
        end

        return table.concat(parts, " ")
    end

    --- Get a short/glance description (just base text)
    function manager:getGlanceDescription(roomId)
        local room = self.rooms[roomId]
        if not room then
            return "A room."
        end
        return room.name .. ": " .. room.base_description
    end

    ----------------------------------------------------------------------------
    -- ROOM STATE
    ----------------------------------------------------------------------------

    --- Mark a room as visited
    function manager:markVisited(roomId)
        local room = self.rooms[roomId]
        if room then
            room.visited = true
            room.discovered = true
        end
    end

    --- Check if room has been visited
    function manager:isVisited(roomId)
        local room = self.rooms[roomId]
        return room and room.visited
    end

    --- Get room danger level
    function manager:getDangerLevel(roomId)
        local room = self.rooms[roomId]
        return room and room.danger_level or 1
    end

    ----------------------------------------------------------------------------
    -- MEATGRINDER INTEGRATION
    ----------------------------------------------------------------------------

    --- Get custom Meatgrinder entries for a room
    function manager:getMeatgrinderOverrides(roomId)
        local room = self.rooms[roomId]
        return room and room.meatgrinder_overrides or {}
    end

    --- Get room-specific verbs for Meatgrinder flavor
    function manager:getVerbs(roomId)
        local room = self.rooms[roomId]
        return room and room.verbs or {}
    end

    --- Pick a random verb for a category
    function manager:getRandomVerb(roomId, category)
        local verbs = self:getVerbs(roomId)
        local categoryVerbs = verbs[category]

        if categoryVerbs and #categoryVerbs > 0 then
            return categoryVerbs[math.random(#categoryVerbs)]
        end
        return nil
    end

    ----------------------------------------------------------------------------
    -- POI (POINT OF INTEREST) INFO-GATING (T2_8)
    -- Three layers: glance, scrutinize, investigate
    -- Scrutinize requires specific sub-verbs (feel, listen, look closely, etc.)
    ----------------------------------------------------------------------------

    -- Internal state for POI discovery
    local discoveredPOIs = {}      -- poi_id -> { layer -> revealed }
    local boundByFate = {}         -- room_id -> poi_id -> test_key -> { itemKey, circumstance, result }
    local scrutinizeCount = 0      -- Track for time cost
    local SCRUTINIZE_TIME_COST = 3 -- Every N scrutinizes triggers Meatgrinder check

    --- Reset POI discovery state (call at start of new Crawl)
    function manager:resetPOIDiscovery()
        discoveredPOIs = {}
        boundByFate = {}
        scrutinizeCount = 0
    end

    local function getItemKey(item)
        if not item then return nil end
        return item.id or item.name
    end

    local function getCircumstanceSignature(feature)
        if not feature then return "none" end
        local state = tostring(feature.state or "none")
        local trapDetected = "none"
        local trapDisarmed = "none"
        if feature.trap then
            trapDetected = tostring(feature.trap.detected or false)
            trapDisarmed = tostring(feature.trap.disarmed or false)
        end
        return state .. "|trap_detected:" .. trapDetected .. "|trap_disarmed:" .. trapDisarmed
    end

    --- Check whether a Test of Fate can be attempted (Bound by Fate)
    -- @param roomId string
    -- @param poiId string
    -- @param testKey string: identifier for the test type (e.g., "investigate", "item_unlock")
    -- @param context table: { item }
    -- @return table: { allowed, reason, entry }
    function manager:getBoundByFateStatus(roomId, poiId, testKey, context)
        local roomEntry = boundByFate[roomId]
        if not roomEntry then
            return { allowed = true }
        end
        local poiEntry = roomEntry[poiId]
        if not poiEntry then
            return { allowed = true }
        end
        local entry = poiEntry[testKey]
        if not entry then
            return { allowed = true }
        end

        local feature = self:getFeature(roomId, poiId)
        local circumstance = getCircumstanceSignature(feature)
        local itemKey = getItemKey(context and context.item or nil)

        if entry.itemKey ~= itemKey then
            return { allowed = true, reason = "item_changed", entry = entry }
        end

        if entry.circumstance ~= circumstance then
            return { allowed = true, reason = "circumstance_changed", entry = entry }
        end

        return { allowed = false, reason = "result_stands", entry = entry }
    end

    --- Record a Test of Fate outcome (Bound by Fate)
    -- @param roomId string
    -- @param poiId string
    -- @param testKey string
    -- @param context table: { item }
    -- @param result table: Test of Fate result
    function manager:recordBoundByFate(roomId, poiId, testKey, context, result)
        local feature = self:getFeature(roomId, poiId)
        if not feature then
            return false
        end

        boundByFate[roomId] = boundByFate[roomId] or {}
        boundByFate[roomId][poiId] = boundByFate[roomId][poiId] or {}

        boundByFate[roomId][poiId][testKey] = {
            itemKey = getItemKey(context and context.item or nil),
            circumstance = getCircumstanceSignature(feature),
            result = result,
        }

        return true
    end

    --- Check if a POI layer has been discovered
    function manager:isPOIDiscovered(poiId, layer)
        if not discoveredPOIs[poiId] then
            return false
        end
        return discoveredPOIs[poiId][layer] or false
    end

    --- Mark a POI layer as discovered
    function manager:discoverPOI(poiId, layer)
        if not discoveredPOIs[poiId] then
            discoveredPOIs[poiId] = {}
        end
        discoveredPOIs[poiId][layer] = true

        self.eventBus:emit(events.EVENTS.POI_DISCOVERED, {
            poiId = poiId,
            layer = layer,
        })
    end

    --- Get valid sub-verbs for scrutinizing a POI
    -- @param poi table: The feature/POI to scrutinize
    -- @return table: Array of { verb, description }
    function manager:getScrutinyVerbs(poi)
        -- Default verbs based on POI type
        local defaultVerbs = {
            container   = { { verb = "feel", desc = "Feel for hidden compartments" }, { verb = "look", desc = "Look more closely" } },
            decoration  = { { verb = "examine", desc = "Examine the details" }, { verb = "feel", desc = "Feel the surface" } },
            mechanism   = { { verb = "listen", desc = "Listen for mechanisms" }, { verb = "feel", desc = "Feel for seams" } },
            corpse      = { { verb = "search", desc = "Search the remains" }, { verb = "examine", desc = "Examine for clues" } },
            hazard      = { { verb = "study", desc = "Study the hazard" }, { verb = "test", desc = "Test with a pole" } },
            door        = { { verb = "feel", desc = "Feel for drafts" }, { verb = "listen", desc = "Listen at the door" } },
            light       = { { verb = "examine", desc = "Examine the source" } },
            creature    = { { verb = "observe", desc = "Observe behavior" }, { verb = "listen", desc = "Listen carefully" } },
        }

        -- POI can define custom scrutiny verbs
        local verbs = {}
        if poi.scrutiny_verbs then
            for _, v in ipairs(poi.scrutiny_verbs) do
                verbs[#verbs + 1] = v
            end
        else
            local typeVerbs = defaultVerbs[poi.type] or { { verb = "examine", desc = "Look more closely" } }
            for _, v in ipairs(typeVerbs) do
                verbs[#verbs + 1] = v
            end
        end

        -- S11.3: Add "Search" verb for containers/corpses with loot
        if poi.loot and #poi.loot > 0 and poi.state ~= "empty" then
            -- Add search option at the beginning
            table.insert(verbs, 1, { verb = "search", desc = "Search for items" })
        end

        return verbs
    end

    --- Get POI info at a specific layer
    -- @param roomId string
    -- @param poiId string
    -- @param layer string: "glance", "scrutinize", or "investigate"
    -- @param subVerb string: For scrutinize, which verb is used (feel, listen, etc.)
    -- @return table: { text, revealed, subVerb, timeCostTriggered }
    function manager:getPOIInfo(roomId, poiId, layer, subVerb)
        local feature = self:getFeature(roomId, poiId)
        if not feature then
            return { text = "You see nothing there.", revealed = false }
        end

        local result = {
            text = "",
            revealed = false,
            timeCostTriggered = false,
        }

        -- GLANCE: Always available, just the basic description
        if layer == "glance" then
            result.text = feature.name or "Something."
            result.revealed = true
            return result
        end

        -- SCRUTINIZE: Requires saying HOW you're looking
        if layer == "scrutinize" then
            -- Increment scrutinize counter and check time cost
            scrutinizeCount = scrutinizeCount + 1
            if scrutinizeCount >= SCRUTINIZE_TIME_COST then
                scrutinizeCount = 0
                result.timeCostTriggered = true

                self.eventBus:emit(events.EVENTS.SCRUTINY_TIME_COST, {
                    roomId = roomId,
                    poiId = poiId,
                })
            end

            -- Check for verb-specific hidden info
            local hiddenKey = "scrutiny_" .. (subVerb or "examine")
            local hiddenInfo = feature[hiddenKey] or feature.hidden_description

            if hiddenInfo then
                result.text = hiddenInfo
                result.revealed = true
                self:discoverPOI(poiId, "scrutinize")
            else
                -- Generic scrutiny response
                result.text = feature.description or "You look more closely but find nothing unusual."
                result.revealed = true
            end

            return result
        end

        -- INVESTIGATE: May require a test, reveals secrets
        if layer == "investigate" then
            -- Check if already discovered at this level
            if self:isPOIDiscovered(poiId, "investigate") then
                result.text = feature.secrets or feature.investigate_description or "You've already thoroughly investigated this."
                result.revealed = true
                return result
            end

            -- Check if investigation requires a test
            if feature.investigate_test then
                result.requiresTest = true
                result.testConfig = feature.investigate_test
                result.text = "This requires careful investigation."
                return result
            end

            -- Reveal investigation info
            local investigateInfo = feature.secrets or feature.investigate_description
            if investigateInfo then
                result.text = investigateInfo
                result.revealed = true
                self:discoverPOI(poiId, "investigate")
            else
                result.text = "Your thorough investigation reveals nothing more."
                result.revealed = true
            end

            return result
        end

        return result
    end

    --- Get all discovered info for a POI (combines all revealed layers)
    function manager:getDiscoveredPOIInfo(roomId, poiId)
        local feature = self:getFeature(roomId, poiId)
        if not feature then
            return nil
        end

        local info = {
            id = poiId,
            name = feature.name,
            glance = feature.name,
            scrutinize = nil,
            investigate = nil,
        }

        if self:isPOIDiscovered(poiId, "scrutinize") then
            info.scrutinize = feature.hidden_description or feature.description
        end

        if self:isPOIDiscovered(poiId, "investigate") then
            info.investigate = feature.secrets or feature.investigate_description
        end

        return info
    end

    local function normalizeConnectionReveals(feature)
        local reveal = feature and (feature.reveal_connections or feature.reveal_connection)
        if not reveal then
            return {}
        end
        if type(reveal) == "string" then
            return { { to = reveal } }
        end
        if type(reveal) == "table" and reveal[1] then
            return reveal
        end
        if type(reveal) == "table" then
            return { reveal }
        end
        return {}
    end

    local function hasDiscoveredConnection(records)
        for _, record in ipairs(records or {}) do
            if record.discovered then
                return true
            end
        end
        return false
    end

    function manager:revealFeatureConnections(roomId, featureId, dungeon)
        local feature = self:getFeature(roomId, featureId)
        local graph = dungeon or self.dungeon
        if not feature or not graph or not graph.getConnection or not graph.discoverConnection then
            return {}
        end

        local records = {}
        for _, connInfo in ipairs(normalizeConnectionReveals(feature)) do
            local fromId = connInfo.from or roomId
            local toId = connInfo.to or connInfo.target or connInfo.roomId
            if toId then
                local cannotOpenFromThisSide = feature.cannotOpenFromThisSide and
                    (feature.opensFromOtherSide == toId or feature.opensFromOtherSide == connInfo.opensFrom)
                if cannotOpenFromThisSide then
                    records[#records + 1] = {
                        from = fromId,
                        to = toId,
                        discovered = false,
                        blockedFromThisSide = true,
                        reason = "cannot_open_from_this_side",
                    }
                else
                    local connection = graph:getConnection(fromId, toId)
                    if connection then
                        local wasDiscovered = connection.discovered == true
                        local discovered = graph:discoverConnection(fromId, toId) == true
                        local reverseDiscovered = false
                        if discovered and not connection.is_one_way then
                            reverseDiscovered = graph:discoverConnection(toId, fromId) == true
                        end

                        records[#records + 1] = {
                            from = fromId,
                            to = toId,
                            discovered = discovered,
                            wasDiscovered = wasDiscovered,
                            reverseDiscovered = reverseDiscovered,
                            oneWay = connection.is_one_way == true,
                            secret = connection.is_secret == true,
                        }
                    else
                        records[#records + 1] = {
                            from = fromId,
                            to = toId,
                            discovered = false,
                            missingConnection = true,
                            reason = "connection_not_found",
                        }
                    end
                end
            end
        end

        if hasDiscoveredConnection(records) then
            feature.revealedConnections = feature.revealedConnections or {}
            local touchedRooms = {}
            for _, record in ipairs(records) do
                if record.discovered then
                    feature.revealedConnections[#feature.revealedConnections + 1] = {
                        from = record.from,
                        to = record.to,
                        oneWay = record.oneWay,
                        secret = record.secret,
                    }
                    touchedRooms[record.from] = true
                    touchedRooms[record.to] = true
                end
            end

            local safetyChanges = {}
            for touchedRoomId, _ in pairs(touchedRooms) do
                local change = self:updateRoomSafetyFromSecrets(touchedRoomId, graph, {
                    sourceRoomId = roomId,
                    featureId = featureId,
                })
                if change then
                    safetyChanges[#safetyChanges + 1] = change
                end
            end
            records.safetyChanges = safetyChanges

            self.eventBus:emit(events.EVENTS.FEATURE_CONNECTIONS_REVEALED, {
                roomId = roomId,
                featureId = featureId,
                connections = records,
                safetyChanges = safetyChanges,
            })
        end

        return records
    end

    function manager:resolveFeatureTrapTrigger(roomId, featureId, opts)
        opts = opts or {}
        local room = self:getRoom(roomId)
        local feature = self:getFeature(roomId, featureId)
        if not room or not feature then
            return {
                success = false,
                roomId = roomId,
                featureId = featureId,
                error = "feature_not_found",
                effects = {},
            }
        end

        local trap = feature.trap or {}
        local trigger = opts.trigger or trap.trigger or feature.trigger or {}
        local graph = opts.dungeon or self.dungeon
        local targetRoomId = opts.targetRoomId or trigger.clearsBlockedConnection or
            trigger.clearBlockedConnection or trigger.clearsConnectionTo
        local result = {
            success = true,
            roomId = roomId,
            featureId = featureId,
            feature = feature,
            trap = trap,
            effects = { "feature_trap_triggered" },
        }

        feature.trapTriggered = true
        feature.triggered = true
        feature.state = opts.state or "triggered"

        if targetRoomId and graph and graph.clearConnectionBlock then
            local cleared = graph:clearConnectionBlock(roomId, targetRoomId)
            result.clearedConnection = {
                from = roomId,
                to = targetRoomId,
                cleared = cleared,
                blockedBy = trigger.blockedBy or trigger.blocked_by,
            }
            if cleared then
                result.effects[#result.effects + 1] = "blocked_connection_cleared"
            end

            for _, blocker in ipairs(room.features or {}) do
                local block = blocker.blocksConnection
                if block and block.to == targetRoomId and
                   (block.untilTriggered == nil or block.untilTriggered == featureId) then
                    blocker.state = "cleared"
                    blocker.clearedBy = featureId
                    blocker.noLongerBlocksConnection = true
                    block.cleared = true
                    block.clearedBy = featureId
                    result.blockingFeature = blocker
                    result.effects[#result.effects + 1] = "blocking_feature_cleared"
                end
            end

            if cleared then
                self.eventBus:emit(events.EVENTS.FEATURE_CONNECTION_BLOCK_CLEARED, {
                    roomId = roomId,
                    featureId = featureId,
                    targetRoomId = targetRoomId,
                    result = result,
                })
            end
        end

        return result
    end

    ----------------------------------------------------------------------------
    -- INVESTIGATION / TEST-OF-FATE BRIDGE (T2_9, T2_14)
    -- Connects the interaction system to the Tarot resolver
    -- Items can provide bonuses, auto-success, or take damage as proxy
    ----------------------------------------------------------------------------

    --- Compute Test of Fate parameters for a POI investigation
    -- @param adventurer table: The adventurer entity
    -- @param roomId string
    -- @param poiId string
    -- @param item table: Optional item being used for investigation
    -- @return table|nil: { attribute, suitId, attributeValue, favor, difficulty }
    function manager:computeInvestigationTest(adventurer, roomId, poiId, item)
        local feature = self:getFeature(roomId, poiId)
        if not feature then
            return nil
        end

        local testConfig = feature.investigate_test or {}
        local attribute = testConfig.attribute or "pentacles"
        local difficulty = testConfig.difficulty or 14

        -- Get adventurer's attribute value
        local constants = require('constants')
        local suitId = constants.SUITS[string.upper(attribute)] or constants.SUITS.PENTACLES
        local attributeValue = 0
        if adventurer and adventurer.getAttribute then
            attributeValue = adventurer:getAttribute(suitId)
        end

        -- Check favor/disfavor based on scrutiny
        local favor = nil
        if self:isPOIDiscovered(poiId, "scrutinize") then
            favor = nil  -- Neutral - they scrutinized first
        else
            favor = false  -- Disfavor - investigating blind
        end

        -- T2_14: Item provides favor bonus
        if item then
            local itemBonus = self:getItemInvestigationBonus(item, feature)
            if itemBonus == "favor" then
                favor = true  -- Item grants favor
            elseif itemBonus == "negate_disfavor" and favor == false then
                favor = nil  -- Item negates disfavor from not scrutinizing
            end
        end

        -- Additional favor from adventurer motifs or abilities
        if testConfig.favor_condition then
            favor = testConfig.favor_condition(adventurer) or favor
        end

        return {
            attribute = attribute,
            suitId = suitId,
            attributeValue = attributeValue,
            favor = favor,
            difficulty = difficulty,
        }
    end

    --- Conduct an investigation test on a POI
    -- @param adventurer table: The adventurer entity
    -- @param roomId string
    -- @param poiId string
    -- @param drawnCard table: The card drawn from the deck (nil if item auto-success)
    -- @param resolver table: The resolver module
    -- @param item table: Optional item being used for investigation
    -- @param options table: { testResult }
    -- @return table: { result, stateChange, trapTriggered, description, itemNotched, itemDestroyed }
    function manager:conductInvestigation(adventurer, roomId, poiId, drawnCard, resolver, item, options)
        options = options or {}
        local feature = self:getFeature(roomId, poiId)
        if not feature then
            return {
                result = nil,
                description = "There's nothing to investigate there.",
            }
        end

        local result = {
            result = nil,
            stateChange = nil,
            trapTriggered = false,
            itemNotched = false,
            itemDestroyed = false,
            description = "",
        }

        -- T2_14: Check for key_item_id automatic success
        -- If POI has a key_item_id and that item is used, skip test and succeed
        if item and feature.key_item_id then
            local itemKeyId = item.keyId or (item.properties and (item.properties.key_id or item.properties.keyId))
            if itemKeyId == feature.key_item_id or item.name == feature.key_item_id then
                -- Auto-success with the right item!
                self:discoverPOI(poiId, "investigate")

                result.result = { success = true, isGreat = false, total = 0, cards = {} }
                result.description = "The " .. item.name .. " works perfectly! " ..
                    (feature.secrets or feature.investigate_description or "Success!")

                -- Apply success state change
                local testConfig = feature.investigate_test or {}
                if testConfig.success_state then
                    self:setFeatureState(roomId, poiId, testConfig.success_state)
                    result.stateChange = testConfig.success_state
                end

                local revealedConnections = self:revealFeatureConnections(roomId, poiId, options.dungeon)
                if #revealedConnections > 0 then
                    result.revealedConnections = revealedConnections
                    if revealedConnections.safetyChanges and #revealedConnections.safetyChanges > 0 then
                        result.safetyChanges = revealedConnections.safetyChanges
                    end
                end

                self.eventBus:emit(events.EVENTS.INVESTIGATION_COMPLETE, {
                    adventurer = adventurer.id,
                    roomId = roomId,
                    poiId = poiId,
                    result = result.result,
                    usedItem = item.id,
                    autoSuccess = true,
                })

                return result
            end
        end

        -- Determine test parameters from POI
        local testConfig = feature.investigate_test or {}
        local testInfo = self:computeInvestigationTest(adventurer, roomId, poiId, item)

        -- Resolve the test (or use provided override)
        local testResult = options.testResult
        if not testResult then
            if not resolver or not drawnCard or not testInfo then
                return {
                    result = nil,
                    description = "You cannot draw a card right now.",
                }
            end
            testResult = resolver.resolveTest(testInfo.attributeValue, testInfo.suitId, drawnCard, testInfo.favor)
        end
        result.result = testResult

        if feature.investigateTriggersEncounter then
            local triggerResult = self:triggerFeatureLinkedEncounter(roomId, poiId, {
                reason = "investigate",
                watch = options.watch,
            })
            if triggerResult then
                result.triggeredEncounter = triggerResult
                result.effects = result.effects or {}
                result.effects[#result.effects + 1] = "investigation_triggered_encounter"
            end
        end

        -- Handle results
        if testResult.success then
            -- Success! Reveal the secrets
            self:discoverPOI(poiId, "investigate")

            result.description = feature.secrets or feature.investigate_description or "You successfully investigate and find what you're looking for."

            -- Apply success state change
            if testConfig.success_state then
                self:setFeatureState(roomId, poiId, testConfig.success_state)
                result.stateChange = testConfig.success_state
            end

            local revealedConnections = self:revealFeatureConnections(roomId, poiId, options.dungeon)
            if #revealedConnections > 0 then
                result.revealedConnections = revealedConnections
                if revealedConnections.safetyChanges and #revealedConnections.safetyChanges > 0 then
                    result.safetyChanges = revealedConnections.safetyChanges
                end
            end

            -- Great Success bonus
            if testResult.isGreat then
                result.description = result.description .. " A great success!"
                if testConfig.great_success_bonus then
                    result.bonus = testConfig.great_success_bonus
                end
            end
        else
            -- Failure
            result.description = "Your investigation yields nothing."

            -- Check for Great Failure consequences
            if testResult.isGreat then
                result.description = "Your investigation goes terribly wrong!"

                -- T2_14: Item-as-proxy - item takes notch instead of wound
                if item and feature.trap then
                    local inventory = require('logic.inventory')
                    local notchResult = inventory.addNotch(item)

                    result.itemNotched = true
                    result.itemDestroyed = (notchResult == "destroyed")

                    if result.itemDestroyed then
                        result.description = "Your " .. item.name .. " takes the brunt of the trap and is destroyed!"
                    else
                        result.description = "Your " .. item.name .. " takes the brunt of the trap and is notched."
                    end

                    -- Trap was triggered but adventurer is safe
                    result.trapTriggered = true
                    result.trap = feature.trap
                    result.adventurerSafe = true

                    self.eventBus:emit(events.EVENTS.TRAP_TRIGGERED, {
                        roomId = roomId,
                        poiId = poiId,
                        trap = feature.trap,
                        adventurer = adventurer.id,
                        itemProxy = item.id,
                        adventurerSafe = true,
                    })
                elseif feature.trap then
                    -- No item to absorb damage - adventurer suffers
                    result.trapTriggered = true
                    result.trap = feature.trap

                    self.eventBus:emit(events.EVENTS.TRAP_TRIGGERED, {
                        roomId = roomId,
                        poiId = poiId,
                        trap = feature.trap,
                        adventurer = adventurer.id,
                    })

                    result.description = result.description .. " " .. (feature.trap.description or "A trap springs!")
                end

                -- Apply failure state change
                if testConfig.failure_state then
                    self:setFeatureState(roomId, poiId, testConfig.failure_state)
                    result.stateChange = testConfig.failure_state
                end

                if feature.trap then
                    local triggerResult = self:resolveFeatureTrapTrigger(roomId, poiId, {
                        dungeon = options.dungeon,
                    })
                    result.trapTriggerResult = triggerResult
                    if triggerResult.clearedConnection then
                        result.clearedBlockedConnection = triggerResult.clearedConnection
                    end
                end

                -- Custom failure callback
                if testConfig.failure_callback then
                    testConfig.failure_callback(adventurer, feature, self)
                end
            end
        end

        -- Record Bound by Fate (result stands unless circumstances change)
        if testResult then
            self:recordBoundByFate(roomId, poiId, "investigate", { item = item }, testResult)
        end

        -- Emit investigation event
        self.eventBus:emit(events.EVENTS.INVESTIGATION_COMPLETE, {
            adventurer = adventurer.id,
            roomId = roomId,
            poiId = poiId,
            result = testResult,
            trapTriggered = result.trapTriggered,
            usedItem = item and item.id or nil,
            itemNotched = result.itemNotched,
        })

        return result
    end

    --- Determine if an item provides a bonus for investigating a POI
    -- @param item table: The item being used
    -- @param poi table: The POI/feature
    -- @return string|nil: "favor", "negate_disfavor", or nil
    function manager:getItemInvestigationBonus(item, poi)
        -- Check for explicit item_bonuses in POI
        if poi.item_bonuses and poi.item_bonuses[item.name] then
            return poi.item_bonuses[item.name]
        end

        -- Generic item bonus rules
        local itemName = item.name:lower()

        -- Crowbar on locked things = favor
        if (itemName:find("crowbar") or itemName:find("prybar")) and
           (poi.type == "container" or poi.lock) then
            return "favor"
        end

        -- Lockpick on locks = favor
        if itemName:find("lockpick") and poi.lock then
            return "favor"
        end

        -- 10-foot pole on hazards/traps = negate disfavor (safer probing)
        if (itemName:find("pole") or itemName:find("staff")) and
           (poi.trap or poi.type == "hazard") then
            return "negate_disfavor"
        end

        -- Magnifying optics on scrutiny = favor
        if itemName:find("magnif") or itemName:find("lens") or
           (item.properties and (item.properties.magnification or item.properties.magnifier or
               item.properties.opticalZoom)) then
            return "favor"
        end

        return nil
    end

    --- Check if a POI requires an investigation test
    function manager:requiresInvestigationTest(roomId, poiId)
        local feature = self:getFeature(roomId, poiId)
        if not feature then
            return false
        end
        return feature.investigate_test ~= nil
    end

    --- Get investigation test details for UI
    function manager:getInvestigationTestInfo(roomId, poiId)
        local feature = self:getFeature(roomId, poiId)
        if not feature or not feature.investigate_test then
            return nil
        end

        local testConfig = feature.investigate_test
        return {
            attribute = testConfig.attribute or "pentacles",
            hasTrap = feature.trap ~= nil,
            trapDetected = feature.trap and feature.trap.detected,
            hasScrutinized = self:isPOIDiscovered(poiId, "scrutinize"),
        }
    end

    ----------------------------------------------------------------------------
    -- RESET (S10.1)
    ----------------------------------------------------------------------------

    --- Reset all rooms to initial state for a new expedition
    -- @param blueprints table: Original room blueprints to restore from
    function manager:reset(blueprints)
        -- Reset POI discovery state
        self:resetPOIDiscovery()

        -- Reset all rooms
        for roomId, room in pairs(self.rooms) do
            -- Clear visited/discovered flags
            room.visited = false
            room.discovered = false

            -- Clear mobs
            room.mobs = {}

            -- Reset features to initial state
            -- Find original blueprint if provided
            local blueprint = nil
            if blueprints then
                for _, bp in ipairs(blueprints) do
                    if bp.id == room.blueprintId or bp.id == roomId then
                        blueprint = bp
                        break
                    end
                end
            end

            -- Reset feature states
            for i, feature in ipairs(room.features) do
                -- Restore original state
                if blueprint and blueprint.features then
                    for _, origFeat in ipairs(blueprint.features) do
                        if origFeat.id == feature.id then
                            feature.state = origFeat.state or nil
                            break
                        end
                    end
                else
                    -- No blueprint - just clear state
                    feature.state = nil
                end

                -- Reset trap detection
                if feature.trap then
                    feature.trap.detected = false
                    feature.trap.disarmed = false
                end
            end
        end

        print("[ROOM_MANAGER] All rooms reset to initial state")
    end

    return manager
end

return M
