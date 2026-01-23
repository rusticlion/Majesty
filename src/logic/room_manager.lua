-- room_manager.lua
-- Room Manager for Majesty
-- Ticket T2_5: Logic for room state, features, and descriptions
--
-- Design: All data in blueprints/rooms.lua, all logic here.
-- Rooms can "remember" state changes (destroyed features, etc.)

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- ROOM INSTANCE FACTORY
-- Creates a mutable room instance from a blueprint
--------------------------------------------------------------------------------

--- Create a room instance from a blueprint
-- @param blueprint table: Room blueprint from rooms.lua
-- @param roomId string: Unique ID for this instance
-- @return RoomInstance
function M.createRoomInstance(blueprint, roomId)
    -- Deep copy features so each instance has mutable state
    local features = {}
    for i, feat in ipairs(blueprint.features or {}) do
        features[i] = {}
        for k, v in pairs(feat) do
            features[i][k] = v
        end
    end

    local instance = {
        id               = roomId,
        blueprintId      = blueprint.id,
        name             = blueprint.name,
        -- Support both base_description and description (tomb map uses description)
        base_description = blueprint.base_description or blueprint.description,
        description      = blueprint.description,
        danger_level     = blueprint.danger_level or 1,
        features         = features,
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
    local scrutinizeCount = 0      -- Track for time cost
    local SCRUTINIZE_TIME_COST = 3 -- Every N scrutinizes triggers Meatgrinder check

    --- Reset POI discovery state (call at start of new Crawl)
    function manager:resetPOIDiscovery()
        discoveredPOIs = {}
        scrutinizeCount = 0
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

    ----------------------------------------------------------------------------
    -- INVESTIGATION / TEST-OF-FATE BRIDGE (T2_9, T2_14)
    -- Connects the interaction system to the Tarot resolver
    -- Items can provide bonuses, auto-success, or take damage as proxy
    ----------------------------------------------------------------------------

    --- Conduct an investigation test on a POI
    -- @param adventurer table: The adventurer entity
    -- @param roomId string
    -- @param poiId string
    -- @param drawnCard table: The card drawn from the deck (nil if item auto-success)
    -- @param resolver table: The resolver module
    -- @param item table: Optional item being used for investigation
    -- @return table: { result, stateChange, trapTriggered, description, itemNotched, itemDestroyed }
    function manager:conductInvestigation(adventurer, roomId, poiId, drawnCard, resolver, item)
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
            local itemKeyId = item.properties and item.properties.key_id
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
        local attribute = testConfig.attribute or "pentacles"
        local difficulty = testConfig.difficulty or 14

        -- Get adventurer's attribute value
        local constants = require('constants')
        local suitId = constants.SUITS[string.upper(attribute)] or constants.SUITS.PENTACLES
        local attributeValue = adventurer:getAttribute(suitId)

        -- Check favor/disfavor based on scrutiny
        local favor = nil
        if self:isPOIDiscovered(poiId, "scrutinize") then
            favor = nil  -- Neutral - they scrutinized first
        else
            favor = false  -- Disfavor - investigating blind
        end

        -- T2_14: Item provides favor bonus
        -- Certain items give favor when used appropriately
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

        -- Resolve the test
        local testResult = resolver.resolveTest(attributeValue, suitId, drawnCard, favor)
        result.result = testResult

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

                -- Custom failure callback
                if testConfig.failure_callback then
                    testConfig.failure_callback(adventurer, feature, self)
                end
            end
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

        -- Magnifying glass on scrutiny = favor
        if itemName:find("magnif") or itemName:find("lens") then
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
