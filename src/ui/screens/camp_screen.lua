-- camp_screen.lua
-- The Camp Screen UI for Majesty
-- Ticket S8.5: Camp Phase visualization and interaction
--
-- Layout:
-- +------------------------------------------+
-- |           STEP INDICATOR BAR             |
-- +----------+------------------+------------+
-- |  Char 1  |                  |  Char 3    |
-- +----------+    CAMPFIRE      +------------+
-- |  Char 2  |    (center)      |  Char 4    |
-- +----------+------------------+------------+
-- |          ACTION PANEL (context-aware)    |
-- +------------------------------------------+
--
-- Reuses character_plate.lua from S5.1

local events = require('logic.events')
local character_plate = require('ui.character_plate')
local camp_controller = require('logic.camp_controller')
local camp_actions = require('logic.camp_actions')
local camp_prompts = require('data.camp_prompts')
local bid_lore_engine = require('logic.bid_lore_engine')
local question_types = require('data.lore.question_types')
local talent_catalog = require('data.talent_catalog')
local animal_companions = require('data.animal_companions')
local constants = require('constants')

local M = {}

--------------------------------------------------------------------------------
-- LAYOUT CONSTANTS
--------------------------------------------------------------------------------
M.LAYOUT = {
    STEP_BAR_HEIGHT   = 50,
    ACTION_PANEL_HEIGHT = 120,
    PADDING           = 15,
    PLATE_WIDTH       = 200,
    FIRE_SIZE         = 150,
}

--------------------------------------------------------------------------------
-- COLORS
--------------------------------------------------------------------------------
M.COLORS = {
    background     = { 0.05, 0.05, 0.08, 1.0 },   -- Dark night sky
    step_bar_bg    = { 0.10, 0.10, 0.12, 0.95 },
    step_active    = { 0.85, 0.65, 0.25, 1.0 },   -- Warm gold for current step
    step_complete  = { 0.35, 0.55, 0.35, 1.0 },   -- Muted green for done
    step_pending   = { 0.35, 0.35, 0.40, 1.0 },   -- Grey for not yet
    step_text      = { 0.90, 0.85, 0.75, 1.0 },
    fire_outer     = { 0.80, 0.40, 0.10, 0.8 },
    fire_inner     = { 1.00, 0.75, 0.30, 1.0 },
    fire_glow      = { 0.95, 0.60, 0.20, 0.15 },
    panel_bg       = { 0.12, 0.12, 0.14, 0.95 },
    panel_border   = { 0.30, 0.28, 0.25, 1.0 },
    button_bg      = { 0.18, 0.18, 0.20, 1.0 },
    button_hover   = { 0.25, 0.25, 0.28, 1.0 },
    button_text    = { 0.90, 0.85, 0.80, 1.0 },
    bond_charged   = { 0.70, 0.55, 0.85, 1.0 },   -- Purple for charged bonds
    bond_spent     = { 0.40, 0.40, 0.45, 0.5 },   -- Grey for spent bonds
    warning        = { 0.85, 0.40, 0.35, 1.0 },   -- Red for warnings
}

--------------------------------------------------------------------------------
-- STEP NAMES
--------------------------------------------------------------------------------
M.STEP_NAMES = {
    [0] = "Setup",
    [1] = "Actions",
    [2] = "Break Bread",
    [3] = "Watch",
    [4] = "Recovery",
    [5] = "Teardown",
}

--------------------------------------------------------------------------------
-- CAMP SCREEN FACTORY
--------------------------------------------------------------------------------

--- Create a new CampScreen
-- @param config table: { eventBus, campController, guild }
-- @return CampScreen instance
function M.createCampScreen(config)
    config = config or {}

    local screen = {
        -- Core systems
        eventBus       = config.eventBus or events.globalBus,
        campController = config.campController,
        guild          = config.guild or {},

        -- UI state
        width          = 800,
        height         = 600,
        characterPlates = {},
        hoverButton    = nil,
        selectedPC     = nil,      -- PC currently selecting action
        selectedAction = nil,      -- Action currently being configured

        -- Action menu state
        actionMenuOpen = false,
        actionMenuItems = {},
        actionMenuX    = 0,
        actionMenuY    = 0,

        -- Target picker state for Camp Actions that need a concrete target
        targetPickerOpen = false,
        targetPickerItems = {},
        targetPickerAction = nil,
        targetPickerActor = nil,
        targetPickerX = 0,
        targetPickerY = 0,
        targetPickerBounds = nil,

        -- Fellowship selection mode (S9.1)
        fellowshipMode = false,
        fellowshipActor = nil,      -- First PC selected for fellowship
        fellowshipActorIndex = nil,
        fellowshipLaborUnending = false,

        -- Drop zones (for ration drag-drop)
        dropZones      = {},

        -- Bond interaction
        hoveredBond    = nil,
        hoveredPlateIndex = nil,    -- Track which plate is hovered

        -- Prompt overlay (S9.3)
        promptOverlay  = nil,       -- { text, callback }
        subscriptions  = {},
        isDestroyed    = false,

        -- Fire animation
        fireTimer      = 0,

        -- Colors
        colors         = config.colors or M.COLORS,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function screen:init()
        self.isDestroyed = false

        -- Create character plates for guild
        self:createCharacterPlates()

        -- Subscribe to camp events
        self:subscribeEvents()

        -- Initial layout
        if love then
            self:resize(love.graphics.getDimensions())
        end
    end

    function screen:listen(eventType, callback)
        local unsubscribe = self.eventBus:on(eventType, function(data)
            if self.isDestroyed then
                return
            end
            callback(data)
        end)
        self.subscriptions[#self.subscriptions + 1] = unsubscribe
        return unsubscribe
    end

    function screen:unsubscribeEvents()
        for _, unsubscribe in ipairs(self.subscriptions) do
            unsubscribe()
        end
        self.subscriptions = {}
    end

    function screen:destroy()
        self.isDestroyed = true
        self:unsubscribeEvents()

        for _, plate in ipairs(self.characterPlates or {}) do
            if plate.destroy then
                plate:destroy()
            end
        end
    end

    function screen:subscribeEvents()
        self:unsubscribeEvents()

        -- Camp step changed
        self:listen(camp_controller.EVENTS.CAMP_STEP_CHANGED, function(data)
            self:onStepChanged(data)
        end)

        -- Camp action taken
        self:listen(camp_controller.EVENTS.CAMP_ACTION_TAKEN, function(data)
            self:onActionTaken(data)
        end)

        self:listen("camp_action_resolved", function(data)
            self:onCampActionResolved(data)
        end)

        -- Ration consumed
        self:listen(camp_controller.EVENTS.RATION_CONSUMED, function(data)
            self:onRationConsumed(data)
        end)

        -- Bond spent
        self:listen(camp_controller.EVENTS.BOND_SPENT, function(data)
            self:onBondSpent(data)
        end)
    end

    ----------------------------------------------------------------------------
    -- EVENT HANDLERS
    ----------------------------------------------------------------------------

    function screen:onStepChanged(data)
        print("[CampScreen] Step changed to: " .. data.newState)
        -- Close any open menus and cancel fellowship mode
        self.actionMenuOpen = false
        self.targetPickerOpen = false
        self.targetPickerItems = {}
        self.targetPickerAction = nil
        self.targetPickerActor = nil
        self.selectedPC = nil
        self.fellowshipMode = false
        self.fellowshipActor = nil
        self.fellowshipActorIndex = nil
    end

    function screen:onActionTaken(data)
        print("[CampScreen] " .. data.entity.name .. " took action: " .. data.action.type)

        -- S9.3: Show campfire prompt for fellowship actions
        if data.action.type == "fellowship" and data.action.target then
            self:showFellowshipPrompt(data.entity, data.action.target)
        end

        if data.action and data.action.laborUnendingExtra then
            self:showLaborUnendingPrompt(data)
        end
    end

    function screen:onCampActionResolved(data)
        if data and data.action == "fletch_arrows" then
            self:showFletchArrowsPrompt(data)
        elseif data and data.action == "scout" and data.result ~= "scout_initiated" then
            self:showScoutAheadPrompt(data)
        elseif data and data.action == "hunt" and data.result ~= "hunt_initiated" then
            self:showHuntPrompt(data)
        elseif data and data.action == "update_maps" then
            self:showUpdateMapsPrompt(data)
        elseif data and data.action == "infiltrate" and data.result == "location_infiltrated" then
            self:showInfiltratePrompt(data)
        elseif data and data.action == "devour_living" and data.result ~= "devour_living_test_required" then
            self:showDevourLivingPrompt(data)
        elseif data and data.action == "patrol" then
            self:showPatrolPrompt(data)
        elseif data and (data.action == "use_item" or data.action == "cook_hunted_game" or
                         data.action == "preserve_hunted_game") then
            self:showUseItemPrompt(data)
        elseif data and data.action == "read_book" and data.result ~= "book_question_required" then
            self:showReadBookPrompt(data)
        elseif data and data.action == "brew_alchemy" and data.result ~= "alchemy_choices_required" then
            self:showBrewAlchemyPrompt(data)
        elseif data and data.action == "train" then
            self:showTrainPrompt(data)
        elseif data and data.action == "make_pact" then
            self:showMakePactPrompt(data)
        elseif data and data.action == "use_talent" then
            self:showUseTalentPrompt(data)
        end
    end

    function screen:onRationConsumed(data)
        print("[CampScreen] " .. data.entity.name .. " ate")
    end

    function screen:onBondSpent(data)
        print("[CampScreen] Bond spent: " .. data.result)
    end

    ----------------------------------------------------------------------------
    -- CHARACTER PLATES
    ----------------------------------------------------------------------------

    function screen:createCharacterPlates()
        for _, plate in ipairs(self.characterPlates or {}) do
            if plate.destroy then
                plate:destroy()
            end
        end

        self.characterPlates = {}

        for i, adventurer in ipairs(self.guild) do
            local plate = character_plate.createCharacterPlate({
                eventBus = self.eventBus,
                entity = adventurer,
                x = 0,  -- Positioned in calculateLayout
                y = 0,
                width = M.LAYOUT.PLATE_WIDTH,
            })
            plate:init()

            -- Add bond drawing capability
            plate.drawBonds = function(p)
                self:drawBondsForPlate(p, i)
            end

            self.characterPlates[#self.characterPlates + 1] = plate
        end
    end

    function screen:setGuild(guild)
        self.guild = guild or {}
        self:createCharacterPlates()
        self:calculateLayout()
    end

    ----------------------------------------------------------------------------
    -- LAYOUT
    ----------------------------------------------------------------------------

    function screen:calculateLayout()
        local padding = M.LAYOUT.PADDING
        local plateW = M.LAYOUT.PLATE_WIDTH
        local stepH = M.LAYOUT.STEP_BAR_HEIGHT
        local actionH = M.LAYOUT.ACTION_PANEL_HEIGHT

        -- Available area for character plates and fire
        local contentY = stepH + padding
        local contentH = self.height - stepH - actionH - (padding * 2)

        -- Fire center position
        self.fireX = self.width / 2
        self.fireY = contentY + contentH / 2

        -- Position plates around the fire
        local count = #self.characterPlates
        local radius = math.min(self.width, contentH) * 0.35

        for i, plate in ipairs(self.characterPlates) do
            -- Distribute plates in a circle around the fire
            local angle = (i - 1) * (math.pi * 2 / count) - math.pi / 2
            local px = self.fireX + math.cos(angle) * radius - plateW / 2
            local py = self.fireY + math.sin(angle) * radius - plate:getHeight() / 2

            -- Keep within bounds
            px = math.max(padding, math.min(px, self.width - plateW - padding))
            py = math.max(contentY, math.min(py, contentY + contentH - plate:getHeight()))

            plate:setPosition(px, py)
        end

        -- Calculate drop zones for ration interaction
        self:calculateDropZones()
    end

    function screen:calculateDropZones()
        self.dropZones = {}

        -- Each character plate is a drop zone during Break Bread phase
        for i, plate in ipairs(self.characterPlates) do
            self.dropZones[#self.dropZones + 1] = {
                id = "plate_" .. i,
                entityIndex = i,
                x = plate.x,
                y = plate.y,
                width = M.LAYOUT.PLATE_WIDTH,
                height = plate:getHeight(),
            }
        end
    end

    function screen:resize(w, h)
        self.width = w
        self.height = h
        self:calculateLayout()
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function screen:update(dt)
        -- Fire animation
        self.fireTimer = self.fireTimer + dt

        -- Update character plates
        for _, plate in ipairs(self.characterPlates) do
            plate:update(dt)
        end
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    ----------------------------------------------------------------------------

    function screen:draw()
        if not love then return end

        -- Background
        love.graphics.setColor(self.colors.background)
        love.graphics.rectangle("fill", 0, 0, self.width, self.height)

        -- Fire glow (large area)
        self:drawFireGlow()

        -- Step indicator bar
        self:drawStepBar()

        -- Campfire
        self:drawCampfire()

        -- Character plates with bonds
        self:drawCharacterPlates()

        -- Action panel (context-aware)
        self:drawActionPanel()

        -- Action menu (if open)
        if self.actionMenuOpen then
            self:drawActionMenu()
        end

        -- Target picker (if open)
        if self.targetPickerOpen then
            self:drawTargetPicker()
        end

        -- S9.3: Prompt overlay (on top of everything)
        if self.promptOverlay then
            self:drawPromptOverlay()
        end
    end

    --- Draw the campfire prompt overlay (S9.3)
    function screen:drawPromptOverlay()
        if not self.promptOverlay then return end

        -- Darken background
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", 0, 0, self.width, self.height)

        -- Calculate prompt box dimensions
        local boxW = math.min(500, self.width - 60)
        local boxH = 200
        local boxX = (self.width - boxW) / 2
        local boxY = (self.height - boxH) / 2

        -- Draw speech bubble background (parchment-like)
        love.graphics.setColor(0.85, 0.80, 0.70, 1.0)
        love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 12, 12)

        -- Border
        love.graphics.setColor(0.50, 0.45, 0.35, 1.0)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 12, 12)
        love.graphics.setLineWidth(1)

        -- Header
        love.graphics.setColor(0.30, 0.25, 0.20, 1.0)
        love.graphics.printf(self.promptOverlay.title or "CAMPFIRE DISCUSSION",
            boxX, boxY + 15, boxW, "center")

        -- Participants or context
        if self.promptOverlay.subtitle then
            love.graphics.setColor(0.50, 0.45, 0.40, 1.0)
            love.graphics.printf(self.promptOverlay.subtitle, boxX, boxY + 35, boxW, "center")
        elseif self.promptOverlay.actor and self.promptOverlay.target then
            love.graphics.setColor(0.50, 0.45, 0.40, 1.0)
            local participants = self.promptOverlay.actor.name .. " & " .. self.promptOverlay.target.name
            love.graphics.printf(participants, boxX, boxY + 35, boxW, "center")
        end

        -- Separator line
        love.graphics.setColor(0.60, 0.55, 0.45, 0.5)
        love.graphics.line(boxX + 30, boxY + 55, boxX + boxW - 30, boxY + 55)

        -- The prompt text
        love.graphics.setColor(0.20, 0.15, 0.10, 1.0)
        local bodyText = self.promptOverlay.text or ""
        if self.promptOverlay.quote ~= false then
            bodyText = "\"" .. bodyText .. "\""
        end
        love.graphics.printf(bodyText, boxX + 20, boxY + 70, boxW - 40, "center")

        -- Click to dismiss instruction
        love.graphics.setColor(0.50, 0.45, 0.40, 0.8)
        love.graphics.printf(
            "(Click anywhere to continue)",
            boxX, boxY + boxH - 30,
            boxW, "center"
        )

        -- Decorative fire icon
        local fireX = boxX + boxW / 2
        local fireY = boxY + boxH - 55
        self:drawMiniFlame(fireX, fireY)
    end

    --- Draw a small decorative flame icon
    function screen:drawMiniFlame(x, y)
        local size = 12

        -- Outer flame
        love.graphics.setColor(0.80, 0.40, 0.10, 0.8)
        love.graphics.polygon("fill",
            x, y - size,
            x - size * 0.6, y + size * 0.3,
            x + size * 0.6, y + size * 0.3
        )

        -- Inner flame
        love.graphics.setColor(1.0, 0.75, 0.30, 0.9)
        love.graphics.polygon("fill",
            x, y - size * 0.6,
            x - size * 0.3, y + size * 0.2,
            x + size * 0.3, y + size * 0.2
        )
    end

    --- Show fellowship prompt (S9.3)
    function screen:showFellowshipPrompt(actor, target)
        -- Use a seed based on game state for determinism
        local seed = os.time() + (actor.id and #actor.id or 0) + (target.id and #target.id or 0)
        local promptText = camp_prompts.getRandomPrompt(seed)

        self.promptOverlay = {
            text = promptText,
            actor = actor,
            target = target,
        }

        print("[CampScreen] Showing fellowship prompt: " .. promptText)
    end

    function screen:formatFletchAmmoLabel(ammoType)
        if ammoType == "arrow" then
            return "Arrows"
        elseif ammoType == "bolt" then
            return "Bolts"
        end
        local text = tostring(ammoType or "Ammo"):gsub("_", " ")
        return text:gsub("(%a)([%w']*)", function(first, rest)
            return first:upper() .. rest:lower()
        end)
    end

    function screen:formatFletchAmmoSummary(data)
        local parts = {}
        for _, entry in ipairs(data and data.refilledAmmunition or {}) do
            local label = self:formatFletchAmmoLabel(entry.type)
            local previous = math.max(0, math.floor(tonumber(entry.previous) or 0))
            local current = math.max(0, math.floor(tonumber(entry.ammo) or 0))
            parts[#parts + 1] = string.format("%s: %d to %d", label, previous, current)
        end
        if #parts == 0 and data then
            local previous = math.max(0, math.floor(tonumber(data.previousAmmo) or 0))
            local current = math.max(0, math.floor(tonumber(data.ammo) or 0))
            parts[#parts + 1] = string.format("Ammo: %d to %d", previous, current)
        end
        return table.concat(parts, "; ")
    end

    function screen:showFletchArrowsPrompt(data)
        local actor = data and data.actor
        local actorName = actor and (actor.name or actor.id) or "Adventurer"
        local summary = self:formatFletchAmmoSummary(data)
        if summary == "" then
            summary = "Quivers refilled."
        end

        self.promptOverlay = {
            title = "FLETCH ARROWS",
            subtitle = actorName,
            text = actorName .. " refills ammunition. " .. summary .. ".",
            actor = actor,
            quote = false,
        }

        print("[CampScreen] Showing fletch prompt: " .. self.promptOverlay.text)
    end

    function screen:formatScoutInformationItem(value)
        if type(value) ~= "table" then
            return tostring(value or "")
        end

        local text = value.summary or value.hint or value.description or value.roomName or value.name or value.id
        if text ~= nil then
            return tostring(text)
        end

        local parts = {}
        for key, entry in pairs(value) do
            if type(entry) ~= "table" then
                parts[#parts + 1] = tostring(key) .. ": " .. tostring(entry)
            end
        end
        table.sort(parts)
        return table.concat(parts, "; ")
    end

    function screen:formatScoutInformation(information)
        if information == nil then
            return ""
        end
        if type(information) ~= "table" then
            return tostring(information)
        end

        local direct = self:formatScoutInformationItem(information)
        if direct ~= "" then
            return direct
        end

        local parts = {}
        for i, entry in ipairs(information) do
            if i > 3 then
                parts[#parts + 1] = string.format("%d more", #information - 3)
                break
            end
            local formatted = self:formatScoutInformationItem(entry)
            if formatted ~= "" then
                parts[#parts + 1] = formatted
            end
        end
        return table.concat(parts, " | ")
    end

    function screen:showScoutAheadPrompt(data)
        local actor = data and data.actor
        local actorName = actor and (actor.name or actor.id) or "Adventurer"
        local result = data and data.result
        local information = self:formatScoutInformation(data and data.information)
        local text = nil

        if result == "scout_hint" then
            text = actorName .. " returns with a nearby hint."
        elseif result == "full_scout_report" then
            text = actorName .. " returns with a full nearby report."
        elseif result == "nothing_learned" then
            text = actorName .. " finds no new information."
        elseif result == "challenge_triggered" then
            text = actorName .. " stumbles into danger. A Challenge begins."
        else
            text = actorName .. " resolves Scout Ahead."
        end
        if information ~= "" then
            text = text .. " " .. information
        end

        self.promptOverlay = {
            title = "SCOUT AHEAD",
            subtitle = actorName,
            text = text,
            actor = actor,
            quote = false,
        }

        print("[CampScreen] Showing scout prompt: " .. self.promptOverlay.text)
    end

    function screen:showHuntPrompt(data)
        local actor = data and data.actor
        local actorName = actor and (actor.name or actor.id) or "Adventurer"
        local result = data and data.result
        local item = data and data.item
        local itemName = item and (item.name or item.id) or "Fresh Game"
        local method = data and data.method
        local text = nil

        if result == "fresh_game_found" or result == "large_game_found" then
            if method == "fishing" then
                text = actorName .. " returns from fishing with " .. itemName .. "."
            else
                text = actorName .. " returns from the hunt with " .. itemName .. "."
            end
        elseif result == "no_game" then
            if method == "fishing" then
                text = actorName .. " catches nothing."
            else
                text = actorName .. " finds no game."
            end
        elseif result == "challenge_triggered" then
            if method == "fishing" then
                text = actorName .. " hooks danger. A Challenge begins."
            else
                text = actorName .. " stumbles into danger. A Challenge begins."
            end
        else
            text = actorName .. " resolves Hunt."
        end

        self.promptOverlay = {
            title = "HUNT",
            subtitle = actorName,
            text = text,
            actor = actor,
            quote = false,
        }

        print("[CampScreen] Showing hunt prompt: " .. self.promptOverlay.text)
    end

    function screen:formatMappedRooms(rooms)
        local parts = {}
        for i, roomId in ipairs(rooms or {}) do
            if i > 4 then
                parts[#parts + 1] = string.format("%d more", #rooms - 4)
                break
            end
            parts[#parts + 1] = tostring(roomId)
        end
        return table.concat(parts, ", ")
    end

    function screen:showUpdateMapsPrompt(data)
        local actor = data and data.actor
        local actorName = actor and (actor.name or actor.id) or "Adventurer"
        local rooms = data and data.rooms or {}
        local roomCount = #rooms
        local roomText = self:formatMappedRooms(rooms)
        local travelPace = data and data.mappedRoomTravelPerWatch
        local text = string.format("%s updates the guild map with %d room%s.",
            actorName,
            roomCount,
            roomCount == 1 and "" or "s")
        if roomText ~= "" then
            text = text .. " " .. roomText .. "."
        end
        if travelPace then
            text = text .. string.format(" Mapped travel pace: %d rooms per watch.", travelPace)
        end

        self.promptOverlay = {
            title = "UPDATE MAPS",
            subtitle = actorName,
            text = text,
            actor = actor,
            quote = false,
        }

        print("[CampScreen] Showing update maps prompt: " .. self.promptOverlay.text)
    end

    function screen:formatInfiltrationFacts(facts)
        facts = facts or {}
        local parts = {}
        if facts.trapped then
            parts[#parts + 1] = "traps"
        end
        if facts.guarded then
            parts[#parts + 1] = "guards"
        end
        if facts.hasSecret then
            parts[#parts + 1] = "secrets"
        end
        if facts.hasLoot then
            parts[#parts + 1] = "loot"
        end
        if #parts == 0 then
            return "No obvious traps, guards, secrets, or loot."
        end
        return "Signs found: " .. table.concat(parts, ", ") .. "."
    end

    function screen:showInfiltratePrompt(data)
        local actor = data and data.actor
        local actorName = actor and (actor.name or actor.id) or "Adventurer"
        local infiltration = data and data.infiltration or {}
        local locationName = infiltration.locationName or data.locationName or data.locationId or "known location"
        local factSummary = self:formatInfiltrationFacts(infiltration.facts)
        local motif = infiltration.motif or data.motif
        local text = actorName .. " infiltrates " .. tostring(locationName) .. ". " .. factSummary
        if motif and motif ~= "" then
            text = text .. " Lore motif: " .. tostring(motif) .. "."
        end

        self.promptOverlay = {
            title = "INFILTRATE",
            subtitle = actorName,
            text = text,
            actor = actor,
            quote = false,
        }

        print("[CampScreen] Showing infiltrate prompt: " .. self.promptOverlay.text)
    end

    function screen:showDevourLivingPrompt(data)
        local actor = data and data.actor
        local actorName = actor and (actor.name or actor.id) or "Adventurer"
        local result = data and data.result
        local outcome = data and data.outcome
        local text = nil

        if result == "living_food_found" then
            text = actorName .. " finds living vermin to eat at Break Bread."
        elseif result == "no_living_food" then
            text = actorName .. " finds no living food."
        else
            text = actorName .. " resolves Devour the Living."
        end
        if outcome and outcome ~= "" then
            text = text .. " Outcome: " .. tostring(outcome) .. "."
        end

        self.promptOverlay = {
            title = "DEVOUR THE LIVING",
            subtitle = actorName,
            text = text,
            actor = actor,
            quote = false,
        }

        print("[CampScreen] Showing Devour the Living prompt: " .. self.promptOverlay.text)
    end

    function screen:formatCampItemName(item, fallback)
        return item and (item.name or item.id) or fallback or "item"
    end

    function screen:formatMinorCard(card)
        if not card then
            return ""
        end
        if card.name and card.name ~= "" then
            return tostring(card.name)
        end
        local suit = card.suit and self:formatWatchCategory(card.suit) or "Card"
        if card.value then
            return tostring(card.value) .. " of " .. suit
        end
        return suit
    end

    function screen:formatCountedNoun(count, singular, plural)
        count = math.max(0, math.floor(tonumber(count) or 0))
        return tostring(count) .. " " .. (count == 1 and singular or (plural or singular .. "s"))
    end

    function screen:formatAfflictionResult(result)
        if type(result) ~= "table" then
            return ""
        end
        local parts = {}
        if result.affliction then
            parts[#parts + 1] = "Affliction: " .. tostring(result.affliction) .. "."
        end
        if result.fullyCured then
            parts[#parts + 1] = "The affliction is cured."
        elseif result.result == "affliction_charged" then
            parts[#parts + 1] = "Recovery progress is marked."
        end
        return table.concat(parts, " ")
    end

    function screen:showUseItemPrompt(data)
        local actor = data and data.actor
        local actorName = actor and (actor.name or actor.id) or "Adventurer"
        local action = data and data.action
        local result = data and data.result
        local item = data and data.item
        local itemName = self:formatCampItemName(item, "item")
        local target = data and data.target
        local targetName = target and (target.name or target.id)
        local text = nil

        if action == "cook_hunted_game" then
            local source = self:formatCampItemName(data.source, "hunted game")
            local mealCount = data.mealCount or (data.meal and data.meal.quantity)
            text = actorName .. " cooks " .. source .. " into " ..
                self:formatCountedNoun(mealCount, "meal") .. "."
        elseif action == "preserve_hunted_game" then
            local source = self:formatCampItemName(data.source, "hunted game")
            local rationCount = data.rationCount or (data.ration and data.ration.quantity)
            text = actorName .. " preserves " .. source .. " into " ..
                self:formatCountedNoun(rationCount, "ration") .. "."
        elseif result == "stress_cleared" then
            text = actorName .. " uses " .. itemName .. ". Stressed cleared."
        elseif result == "pipeweed_no_effect" then
            text = actorName .. " uses " .. itemName .. ". No Stressed condition is present."
        elseif result == "notch_removed" then
            text = actorName .. " repairs " .. (targetName or "damaged gear") ..
                " with " .. itemName .. ". One Notch removed."
        elseif result == "leeches_no_effect" then
            local cardText = self:formatMinorCard(data and data.card)
            text = actorName .. " applies " .. itemName ..
                (targetName and (" to " .. targetName) or "") .. "."
            if cardText ~= "" then
                text = text .. " Draw: " .. cardText .. "."
            end
            text = text .. " No affliction recovery charges are gained."
        elseif data and data.charges then
            local cardText = self:formatMinorCard(data.card)
            text = actorName .. " applies " .. itemName ..
                (targetName and (" to " .. targetName) or "") .. "."
            if cardText ~= "" then
                text = text .. " Draw: " .. cardText .. "."
            end
            text = text .. " " .. self:formatCountedNoun(data.charges, "affliction recovery charge") ..
                " burned."
            local afflictionText = self:formatAfflictionResult(data.cureResult)
            if afflictionText ~= "" then
                text = text .. " " .. afflictionText
            end
        else
            text = actorName .. " uses " .. itemName .. ". Result: " .. tostring(result or "resolved") .. "."
        end

        self.promptOverlay = {
            title = "USE AN ITEM",
            subtitle = actorName,
            text = text,
            actor = actor,
            quote = false,
        }

        print("[CampScreen] Showing use item prompt: " .. self.promptOverlay.text)
    end

    function screen:formatBookQuestionName(questionType)
        local text = tostring(questionType or "question"):gsub("_", " ")
        return text:gsub("(%a)([%w']*)", function(first, rest)
            return first:upper() .. rest:lower()
        end)
    end

    function screen:formatBookResponse(response)
        if response == nil then
            return ""
        end
        if type(response) ~= "table" then
            return tostring(response)
        end

        local text = response.summary or response.answer or response.description
        if text and text ~= "" then
            return tostring(text)
        end

        local parts = {}
        for key, value in pairs(response) do
            if type(value) ~= "table" then
                parts[#parts + 1] = tostring(key) .. ": " .. tostring(value)
            end
        end
        table.sort(parts)
        return table.concat(parts, "; ")
    end

    function screen:showReadBookPrompt(data)
        local actor = data and data.actor
        local actorName = actor and (actor.name or actor.id) or "Adventurer"
        local book = data and (data.book or data.target)
        local bookName = self:formatCampItemName(book, "a book")
        local question = self:formatBookQuestionName(data and data.questionType)
        local result = data and data.result
        local text = nil

        if result == "book_answered" then
            local answer = self:formatBookResponse(data.response)
            text = actorName .. " reads " .. bookName .. ". Question: " .. question .. "."
            if answer ~= "" then
                text = text .. " " .. answer
            end
            if data.bookwormRecorded then
                text = text .. " Bookworm motif recorded."
            end
        elseif result == "book_rephrase_needed" then
            text = actorName .. " reads " .. bookName .. ". Question: " .. question ..
                ". Rephrase needed."
            if data.reason and data.reason ~= "" then
                text = text .. " " .. tostring(data.reason)
            end
        elseif result == "book_question_unavailable" then
            text = actorName .. " reads " .. bookName .. ". Question: " .. question ..
                ". The book has no available answer."
            if data.reason and data.reason ~= "" then
                text = text .. " " .. tostring(data.reason)
            end
        else
            text = actorName .. " reads " .. bookName .. ". Result: " .. tostring(result or "resolved") .. "."
        end

        self.promptOverlay = {
            title = "READ A BOOK",
            subtitle = actorName,
            text = text,
            actor = actor,
            quote = false,
        }

        print("[CampScreen] Showing read book prompt: " .. self.promptOverlay.text)
    end

    function screen:formatBrewAlchemyEntry(entry)
        local item = entry and entry.item
        local outputName = self:formatCampItemName(item, entry and entry.templateId or "substance")
        local reagentName = entry and entry.reagentName or "reagent"
        local form = entry and entry.form and self:formatBookQuestionName(entry.form) or nil
        local text = tostring(reagentName) .. " -> " .. outputName
        if form then
            text = text .. " (" .. form .. ")"
        end
        return text
    end

    function screen:formatBrewAlchemySummary(brews)
        local parts = {}
        for i, entry in ipairs(brews or {}) do
            if i > 3 then
                parts[#parts + 1] = string.format("%d more", #brews - 3)
                break
            end
            parts[#parts + 1] = self:formatBrewAlchemyEntry(entry)
        end
        return table.concat(parts, "; ")
    end

    function screen:showBrewAlchemyPrompt(data)
        local actor = data and data.actor
        local actorName = actor and (actor.name or actor.id) or "Adventurer"
        local brews = data and data.brews or {}
        local count = #brews
        local text = actorName .. " brews " .. self:formatCountedNoun(count, "alchemical substance") .. "."
        local summary = self:formatBrewAlchemySummary(brews)
        if summary ~= "" then
            text = text .. " " .. summary .. "."
        end

        self.promptOverlay = {
            title = "BREW ALCHEMY",
            subtitle = actorName,
            text = text,
            actor = actor,
            quote = false,
        }

        print("[CampScreen] Showing brew alchemy prompt: " .. self.promptOverlay.text)
    end

    function screen:showTrainPrompt(data)
        local actor = data and data.actor
        local actorName = actor and (actor.name or actor.id) or "Adventurer"
        local trainer = data and (data.trainer or data.target)
        local trainerName = trainer and (trainer.name or trainer.id) or "trainer"
        local talent = self:formatBookQuestionName(data and data.talentId or "talent")
        local xp = math.max(0, math.floor(tonumber(data and data.xpInvested) or 0))
        local total = math.max(0, math.floor(tonumber(data and data.totalXPInvested) or xp))
        local text = actorName .. " trains " .. talent .. " with " .. trainerName ..
            ". " .. self:formatCountedNoun(xp, "XP") .. " invested; " ..
            tostring(total) .. " total."
        if data and data.mastered then
            text = text .. " Talent mastered."
        end

        self.promptOverlay = {
            title = "TRAIN",
            subtitle = actorName .. " & " .. trainerName,
            text = text,
            actor = actor,
            target = trainer,
            quote = false,
        }

        print("[CampScreen] Showing train prompt: " .. self.promptOverlay.text)
    end

    function screen:formatPactEntry(pact)
        local name = pact and (pact.name or pact.pactId) or "Pact"
        local component = pact and (pact.componentName or pact.componentId)
        local text = tostring(name)
        if component and component ~= "" then
            text = text .. " on " .. tostring(component)
        end
        if pact and pact.immediateEffect and pact.immediateEffect ~= "none" then
            text = text .. " (" .. tostring(pact.immediateEffect) .. ")"
        end
        return text
    end

    function screen:formatPactSummary(pacts)
        local parts = {}
        for i, pact in ipairs(pacts or {}) do
            if i > 3 then
                parts[#parts + 1] = string.format("%d more", #pacts - 3)
                break
            end
            parts[#parts + 1] = self:formatPactEntry(pact)
        end
        return table.concat(parts, "; ")
    end

    function screen:showMakePactPrompt(data)
        local actor = data and data.actor
        local actorName = actor and (actor.name or actor.id) or "Adventurer"
        local pacts = data and data.pacts or {}
        local count = #pacts
        local text = actorName .. " makes " .. self:formatCountedNoun(count, "pact") .. "."
        local summary = self:formatPactSummary(pacts)
        if summary ~= "" then
            text = text .. " " .. summary .. "."
        end

        self.promptOverlay = {
            title = "MAKE A PACT",
            subtitle = actorName,
            text = text,
            actor = actor,
            quote = false,
        }

        print("[CampScreen] Showing make pact prompt: " .. self.promptOverlay.text)
    end

    function screen:showLaborUnendingPrompt(data)
        local actor = data and (data.entity or data.actor)
        local action = data and data.action or {}
        local actorName = actor and (actor.name or actor.id) or "Adventurer"
        local actionName = self:formatBookQuestionName(action.type or "Camp Action")
        local note = actorName .. " marks Stressed through Labor Unending to take an extra " ..
            actionName .. " Camp Action."

        if self.promptOverlay and self.promptOverlay.actor == actor then
            self.promptOverlay.text = tostring(self.promptOverlay.text or "") .. " " .. note
            return
        end

        self.promptOverlay = {
            title = "LABOR UNENDING",
            subtitle = actorName,
            text = note,
            actor = actor,
            quote = false,
        }

        print("[CampScreen] Showing Labor Unending prompt: " .. self.promptOverlay.text)
    end

    function screen:formatUseTalentResult(result)
        local text = tostring(result or "result"):gsub("_", " ")
        return text:gsub("(%a)([%w']*)", function(first, rest)
            return first:upper() .. rest:lower()
        end)
    end

    function screen:formatWarStoriesParticipants(participants)
        local parts = {}
        for i, entry in ipairs(participants or {}) do
            if i > 4 then
                parts[#parts + 1] = string.format("%d more", #participants - 4)
                break
            end
            local entity = entry.entity
            local name = entity and (entity.name or entity.id) or "participant"
            parts[#parts + 1] = tostring(name) .. ": " .. self:formatUseTalentResult(entry.result)
        end
        return table.concat(parts, "; ")
    end

    function screen:formatHighChantGrants(grants)
        local parts = {}
        for i, grant in ipairs(grants or {}) do
            if i > 4 then
                parts[#parts + 1] = string.format("%d more", #grants - 4)
                break
            end
            local recipient = grant.recipient
            local name = recipient and (recipient.name or recipient.id) or "recipient"
            local card = self:formatMinorCard(grant.card)
            parts[#parts + 1] = tostring(name) .. (card ~= "" and (" receives " .. card) or " receives inspiration")
        end
        return table.concat(parts, "; ")
    end

    function screen:formatChirurgeryHealing(healing)
        healing = healing or {}
        local parts = {}
        if (tonumber(healing.armorNotches) or 0) > 0 then
            parts[#parts + 1] = self:formatCountedNoun(healing.armorNotches, "armor Notch")
        end
        if (tonumber(healing.woundedTalents) or 0) > 0 then
            parts[#parts + 1] = self:formatCountedNoun(healing.woundedTalents, "wounded talent")
        end
        if healing.staggered then
            parts[#parts + 1] = "Staggered"
        end
        if healing.injured then
            parts[#parts + 1] = "Injured"
        end
        if healing.deathsDoor then
            parts[#parts + 1] = "Death's Door"
        end
        if #parts == 0 then
            return "No Wounds remained."
        end
        return "Healed: " .. table.concat(parts, ", ") .. "."
    end

    function screen:showUseTalentPrompt(data)
        local actor = data and data.actor
        local actorName = actor and (actor.name or actor.id) or "Adventurer"
        local talentId = data and data.talentId or "talent"
        local talentName = self:formatBookQuestionName(talentId)
        local result = data and data.result
        local text = nil

        if talentId == "beast_master" then
            local companion = data.companion
            local companionName = companion and (companion.name or companion.id) or "companion"
            text = actorName .. " teaches " .. companionName .. " the " ..
                tostring(data.command or "command") .. " command."
        elseif talentId == "war_stories" then
            text = actorName .. " shares War Stories."
            local participants = self:formatWarStoriesParticipants(data.participants)
            if participants ~= "" then
                text = text .. " " .. participants .. "."
            end
        elseif talentId == "high_chant" then
            text = actorName .. " performs High Chant."
            local grants = self:formatHighChantGrants(data.inspirationCards)
            if grants ~= "" then
                text = text .. " " .. grants .. "."
            end
        elseif talentId == "chirurgeon" then
            local target = data.target
            local targetName = target and (target.name or target.id) or "patient"
            text = actorName .. " performs Chirurgery on " .. targetName .. ". " ..
                self:formatChirurgeryHealing(data.healing)
        elseif talentId == "loremaster" then
            local translation = data.translation or {}
            local title = translation.title or (data.target and (data.target.name or data.target.id)) or "text"
            text = actorName .. " translates " .. tostring(title) .. "."
            if translation.language then
                text = text .. " Language: " .. self:formatBookQuestionName(translation.language) .. "."
            end
            if translation.translatedText and translation.translatedText ~= "" then
                text = text .. " " .. tostring(translation.translatedText)
            end
        elseif talentId == "bookworm" then
            local entry = data.entry or {}
            local book = data.book
            local bookName = entry.name or self:formatCampItemName(book, "book")
            text = actorName .. " records " .. tostring(bookName) .. " as a Bookworm reading."
            if entry.motif and entry.motif ~= "" then
                text = text .. " Motif: " .. tostring(entry.motif) .. "."
            end
        else
            text = actorName .. " uses " .. talentName .. ". Result: " ..
                self:formatUseTalentResult(result) .. "."
        end

        self.promptOverlay = {
            title = "USE A TALENT",
            subtitle = talentName,
            text = text,
            actor = actor,
            quote = false,
        }

        print("[CampScreen] Showing use talent prompt: " .. self.promptOverlay.text)
    end

    function screen:showPatrolPrompt(data)
        local actor = data and data.actor
        local actorName = actor and (actor.name or actor.id) or "Adventurer"
        local text = actorName .. " takes patrol duty. During the Watch, draw twice from the Meatgrinder " ..
            "and keep a non-encounter result if one appears. A Challenge begins only if both draws are random encounters."

        self.promptOverlay = {
            title = "PATROL",
            subtitle = actorName,
            text = text,
            actor = actor,
            quote = false,
        }

        print("[CampScreen] Showing patrol prompt: " .. self.promptOverlay.text)
    end

    function screen:formatWatchCategory(category)
        local text = tostring(category or "event"):gsub("_", " ")
        return text:gsub("(%a)([%w']*)", function(first, rest)
            return first:upper() .. rest:lower()
        end)
    end

    function screen:formatWatchResultBrief(result)
        if not result then
            return ""
        end
        local category = self:formatWatchCategory(result.category)
        local description = result.description or result.name or result.result or result.id
        if description and description ~= "" then
            return category .. ": " .. tostring(description)
        end
        return category
    end

    function screen:appendSentence(text, sentence)
        if not sentence or sentence == "" then
            return text
        end
        text = text .. sentence
        if not sentence:match("[%.%!%?]$") then
            text = text .. "."
        end
        return text
    end

    function screen:showWatchResultPrompt(watchResult)
        local draws = watchResult and watchResult.draws or {}
        local drawCount = #draws
        local selected = watchResult and watchResult.selected
        local selectedText = self:formatWatchResultBrief(selected)
        local text = nil

        if watchResult and watchResult.patrol then
            text = string.format("Patrol drew %d Meatgrinder card%s.",
                drawCount,
                drawCount == 1 and "" or "s")
            if selectedText ~= "" then
                text = self:appendSentence(text, " Kept " .. selectedText)
            end
            if watchResult.challengeTriggered then
                text = text .. " Both draws were random encounters; a Challenge begins."
            else
                text = text .. " The camp avoids a Challenge."
            end
        elseif selectedText ~= "" then
            text = self:appendSentence("The Watch brings ", selectedText)
            if watchResult and watchResult.challengeTriggered then
                text = text .. " A Challenge begins."
            end
        else
            text = "The Watch passes with no Meatgrinder result."
        end

        local guard = watchResult and watchResult.guard
        if guard then
            local guardName = guard.name or guard.id or "The guard"
            if watchResult.alarmRaised then
                text = text .. " " .. guardName .. " raises the alarm."
            elseif watchResult.surprised then
                text = text .. " " .. guardName ..
                    " fails the watch test; sleepers are surprised and armor and weapons are inactive."
            elseif watchResult.guardTestRequired then
                text = text .. " " .. guardName .. " must test Cups to raise the alarm."
            end
        end

        self.promptOverlay = {
            title = "THE WATCH",
            text = text,
            quote = false,
        }

        print("[CampScreen] Showing watch prompt: " .. self.promptOverlay.text)
    end

    --- Dismiss the prompt overlay (S9.3)
    function screen:dismissPromptOverlay()
        self.promptOverlay = nil
    end

    function screen:drawStepBar()
        local barY = 0
        local barH = M.LAYOUT.STEP_BAR_HEIGHT

        -- Background
        love.graphics.setColor(self.colors.step_bar_bg)
        love.graphics.rectangle("fill", 0, barY, self.width, barH)

        -- Border
        love.graphics.setColor(self.colors.panel_border)
        love.graphics.line(0, barH, self.width, barH)

        -- Current step indicator
        local currentStep = self.campController and self.campController:getCurrentStep() or 0

        -- Draw step indicators
        local stepCount = 6  -- 0-5
        local stepWidth = (self.width - M.LAYOUT.PADDING * 2) / stepCount
        local stepY = barY + 10

        for i = 0, 5 do
            local stepX = M.LAYOUT.PADDING + i * stepWidth
            local stepName = M.STEP_NAMES[i] or "Step " .. i

            -- Determine color
            local bgColor, textColor
            if i == currentStep then
                bgColor = self.colors.step_active
                textColor = { 0.1, 0.1, 0.1, 1.0 }
            elseif i < currentStep then
                bgColor = self.colors.step_complete
                textColor = self.colors.step_text
            else
                bgColor = self.colors.step_pending
                textColor = { 0.6, 0.6, 0.6, 1.0 }
            end

            -- Step box
            love.graphics.setColor(bgColor)
            love.graphics.rectangle("fill", stepX + 2, stepY, stepWidth - 4, barH - 20, 4, 4)

            -- Step text
            love.graphics.setColor(textColor)
            love.graphics.printf(stepName, stepX + 2, stepY + 8, stepWidth - 4, "center")
        end
    end

    function screen:drawCampfire()
        local cx, cy = self.fireX, self.fireY
        local baseSize = M.LAYOUT.FIRE_SIZE / 2

        -- Flickering effect
        local flicker = math.sin(self.fireTimer * 8) * 0.1 +
                        math.sin(self.fireTimer * 12) * 0.05 +
                        math.cos(self.fireTimer * 5) * 0.08

        -- Outer flame (orange)
        love.graphics.setColor(self.colors.fire_outer)
        local outerSize = baseSize * (1 + flicker)
        self:drawFlameShape(cx, cy, outerSize)

        -- Inner flame (yellow)
        love.graphics.setColor(self.colors.fire_inner)
        local innerSize = baseSize * 0.6 * (1 + flicker * 0.5)
        self:drawFlameShape(cx, cy, innerSize)

        -- Core (white-yellow)
        love.graphics.setColor(1.0, 0.95, 0.8, 0.9)
        local coreSize = baseSize * 0.25
        love.graphics.circle("fill", cx, cy + baseSize * 0.2, coreSize)

        -- Embers (small particles)
        love.graphics.setColor(1.0, 0.6, 0.2, 0.7)
        for i = 1, 5 do
            local emberAngle = self.fireTimer * 2 + i * 1.2
            local emberDist = baseSize * 0.4 + math.sin(emberAngle * 3) * 10
            local emberX = cx + math.cos(emberAngle) * emberDist * 0.3
            local emberY = cy - math.sin(self.fireTimer * 3 + i) * emberDist * 0.5
            love.graphics.circle("fill", emberX, emberY, 2 + math.sin(emberAngle) * 1)
        end
    end

    function screen:drawFlameShape(cx, cy, size)
        -- Simple flame polygon
        local points = {}
        local segments = 8

        for i = 0, segments do
            local t = i / segments
            local angle = math.pi * (0.3 + t * 1.4) - math.pi / 2

            -- Flame shape: wider at bottom, pointed at top
            local r = size
            if t < 0.5 then
                r = r * (0.5 + t)
            else
                r = r * (1.5 - t)
            end

            -- Add some randomness
            r = r * (0.9 + math.sin(self.fireTimer * 6 + i) * 0.1)

            points[#points + 1] = cx + math.cos(angle) * r * 0.6
            points[#points + 1] = cy + math.sin(angle) * r
        end

        if #points >= 6 then
            love.graphics.polygon("fill", points)
        end
    end

    function screen:drawFireGlow()
        local cx, cy = self.fireX, self.fireY
        local glowSize = M.LAYOUT.FIRE_SIZE * 2

        -- Radial glow
        for i = 5, 1, -1 do
            local alpha = 0.03 * i
            love.graphics.setColor(self.colors.fire_glow[1], self.colors.fire_glow[2], self.colors.fire_glow[3], alpha)
            love.graphics.circle("fill", cx, cy, glowSize * (i / 5))
        end
    end

    function screen:drawCharacterPlates()
        local currentState = self.campController and self.campController:getState()

        for i, plate in ipairs(self.characterPlates) do
            -- Draw selection highlight for fellowship mode (S9.1)
            if self.fellowshipMode then
                self:drawFellowshipHighlight(plate, i)
            end

            plate:draw()

            -- Draw bonds for this plate (if in recovery phase OR actions phase to show existing bonds)
            if currentState == camp_controller.STATES.RECOVERY or
               currentState == camp_controller.STATES.ACTIONS then
                self:drawBondsForPlate(plate, i)
            end

            -- Draw pending action indicator
            local pc = self.guild[i]
            if pc then
                self:drawPCStatus(plate, pc, i)
            end
        end

        -- Draw fellowship connection line (S9.1)
        if self.fellowshipMode and self.fellowshipActorIndex then
            self:drawFellowshipLine()
        end
    end

    --- Draw fellowship selection highlight (S9.1)
    function screen:drawFellowshipHighlight(plate, index)
        local isActor = (index == self.fellowshipActorIndex)
        local isHovered = (index == self.hoveredPlateIndex)
        local pc = self.guild[index]

        -- Check if this PC can be selected as target
        local canSelect = true
        if self.fellowshipActor and pc then
            -- Can't select self
            if pc.id == self.fellowshipActor.id then
                canSelect = false
            end
            -- Check if bond already charged
            if self.fellowshipActor.bonds and self.fellowshipActor.bonds[pc.id] then
                if self.fellowshipActor.bonds[pc.id].charged then
                    canSelect = false  -- Bond already charged
                end
            end
        end

        -- Draw highlight
        if isActor then
            -- Selected actor - gold highlight
            love.graphics.setColor(0.85, 0.65, 0.25, 0.4)
            love.graphics.rectangle("fill", plate.x - 4, plate.y - 4,
                M.LAYOUT.PLATE_WIDTH + 8, plate:getHeight() + 8, 6, 6)
            love.graphics.setColor(0.85, 0.65, 0.25, 1.0)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", plate.x - 4, plate.y - 4,
                M.LAYOUT.PLATE_WIDTH + 8, plate:getHeight() + 8, 6, 6)
            love.graphics.setLineWidth(1)
        elseif isHovered and canSelect and not isActor then
            -- Valid target - purple hover
            love.graphics.setColor(0.70, 0.55, 0.85, 0.3)
            love.graphics.rectangle("fill", plate.x - 2, plate.y - 2,
                M.LAYOUT.PLATE_WIDTH + 4, plate:getHeight() + 4, 4, 4)
        elseif not canSelect and not isActor then
            -- Invalid target - red tint
            love.graphics.setColor(0.6, 0.3, 0.3, 0.2)
            love.graphics.rectangle("fill", plate.x, plate.y,
                M.LAYOUT.PLATE_WIDTH, plate:getHeight(), 4, 4)
        end
    end

    --- Draw connecting line during fellowship selection (S9.1)
    function screen:drawFellowshipLine()
        if not self.fellowshipActorIndex then return end

        local actorPlate = self.characterPlates[self.fellowshipActorIndex]
        if not actorPlate then return end

        -- Line start: center of actor plate
        local startX = actorPlate.x + M.LAYOUT.PLATE_WIDTH / 2
        local startY = actorPlate.y + actorPlate:getHeight() / 2

        -- Line end: either hovered plate center or mouse position
        local endX, endY
        if self.hoveredPlateIndex and self.hoveredPlateIndex ~= self.fellowshipActorIndex then
            local targetPlate = self.characterPlates[self.hoveredPlateIndex]
            if targetPlate then
                endX = targetPlate.x + M.LAYOUT.PLATE_WIDTH / 2
                endY = targetPlate.y + targetPlate:getHeight() / 2
            end
        end

        if not endX and love then
            endX, endY = love.mouse.getPosition()
        end

        if endX and endY then
            -- Draw glowing line
            love.graphics.setColor(0.70, 0.55, 0.85, 0.3)
            love.graphics.setLineWidth(6)
            love.graphics.line(startX, startY, endX, endY)

            love.graphics.setColor(0.70, 0.55, 0.85, 0.8)
            love.graphics.setLineWidth(2)
            love.graphics.line(startX, startY, endX, endY)

            love.graphics.setLineWidth(1)
        end
    end

    function screen:drawPCStatus(plate, pc, index)
        local currentState = self.campController and self.campController:getState()

        -- Show status based on current phase
        if currentState == camp_controller.STATES.ACTIONS then
            -- Show if action taken
            local actionTaken = self.campController.actionsCompleted[pc.id]
            local canLabor = self:canUseLaborUnendingForExtraAction(pc)
            local statusColor = actionTaken and self.colors.step_complete or self.colors.warning

            love.graphics.setColor(statusColor)
            local statusText = canLabor and "Labor Ready" or (actionTaken and "Done" or "Needs Action")
            love.graphics.print(statusText, plate.x, plate.y - 15)

        elseif currentState == camp_controller.STATES.BREAK_BREAD then
            -- Show if ate
            local ate = self.campController.rationsConsumed[pc.id]
            local statusColor = ate and self.colors.step_complete or self.colors.warning

            love.graphics.setColor(statusColor)
            local statusText = ate and "Fed" or "Hungry"
            love.graphics.print(statusText, plate.x, plate.y - 15)

            -- S9.2: Show warning if no rations in inventory
            if not ate then
                local rationCount = self:countRationsFor(pc)
                if rationCount == 0 then
                    -- Draw warning icon (exclamation triangle)
                    self:drawNoRationWarning(plate.x + M.LAYOUT.PLATE_WIDTH - 25, plate.y + 5)
                else
                    -- Show ration count
                    love.graphics.setColor(self.colors.step_text)
                    love.graphics.print("x" .. rationCount, plate.x + M.LAYOUT.PLATE_WIDTH - 25, plate.y + 5)
                end
            end

        elseif currentState == camp_controller.STATES.RECOVERY then
            -- S9.2: Show stress gate warning
            if pc.conditions and pc.conditions.stressed then
                love.graphics.setColor(self.colors.warning)
                love.graphics.print("STRESSED - Must clear first!", plate.x, plate.y - 15)
            end
        end
    end

    --- Count rations in a PC's inventory (S9.2)
    function screen:countRationsFor(pc)
        if not pc.inventory or not pc.inventory.countItemsByPredicate then
            return 0
        end

        return pc.inventory:countItemsByPredicate(function(item)
            return item.isRation or
                   item.type == "ration" or
                   item.itemType == "ration" or
                   (item.properties and item.properties.isRation) or
                   (item.name and item.name:lower():find("ration"))
        end)
    end

    --- Draw no-ration warning icon (S9.2)
    function screen:drawNoRationWarning(x, y)
        -- Triangle with exclamation
        local size = 18

        -- Warning triangle background
        love.graphics.setColor(self.colors.warning)
        love.graphics.polygon("fill",
            x + size/2, y,
            x, y + size,
            x + size, y + size
        )

        -- Exclamation mark
        love.graphics.setColor(0.1, 0.1, 0.1, 1.0)
        love.graphics.rectangle("fill", x + size/2 - 1.5, y + 5, 3, 7)
        love.graphics.circle("fill", x + size/2, y + size - 4, 2)
    end

    function screen:drawBondsForPlate(plate, pcIndex)
        local pc = self.guild[pcIndex]
        if not pc or not pc.bonds then return end

        -- Draw bond indicators as small circles on the plate
        local bondX = plate.x + M.LAYOUT.PLATE_WIDTH - 30
        local bondY = plate.y + 5
        local bondSize = 12
        local bondSpacing = bondSize + 4

        local bondIndex = 0
        for targetId, bond in pairs(pc.bonds) do
            local bx = bondX
            local by = bondY + bondIndex * bondSpacing

            -- Bond circle
            local bondColor = bond.charged and self.colors.bond_charged or self.colors.bond_spent
            love.graphics.setColor(bondColor)
            love.graphics.circle("fill", bx, by, bondSize / 2)

            -- Border
            love.graphics.setColor(self.colors.panel_border)
            love.graphics.circle("line", bx, by, bondSize / 2)

            -- Hover highlight
            if self.hoveredBond and self.hoveredBond.pcIndex == pcIndex and self.hoveredBond.targetId == targetId then
                love.graphics.setColor(1, 1, 1, 0.3)
                love.graphics.circle("fill", bx, by, bondSize / 2 + 3)
            end

            bondIndex = bondIndex + 1
        end
    end

    function screen:drawActionPanel()
        local panelY = self.height - M.LAYOUT.ACTION_PANEL_HEIGHT
        local panelH = M.LAYOUT.ACTION_PANEL_HEIGHT

        -- Clear phase-specific button bounds (will be set by the appropriate panel)
        self.meatgrinderButtonBounds = nil
        self.breakCampButtonBounds = nil

        -- Background
        love.graphics.setColor(self.colors.panel_bg)
        love.graphics.rectangle("fill", 0, panelY, self.width, panelH)

        -- Border
        love.graphics.setColor(self.colors.panel_border)
        love.graphics.line(0, panelY, self.width, panelY)

        -- Content based on current state
        local currentState = self.campController and self.campController:getState() or camp_controller.STATES.INACTIVE

        if currentState == camp_controller.STATES.ACTIONS then
            self:drawActionsPanel(panelY)
        elseif currentState == camp_controller.STATES.BREAK_BREAD then
            self:drawBreakBreadPanel(panelY)
        elseif currentState == camp_controller.STATES.WATCH then
            self:drawWatchPanel(panelY)
        elseif currentState == camp_controller.STATES.RECOVERY then
            self:drawRecoveryPanel(panelY)
        elseif currentState == camp_controller.STATES.TEARDOWN then
            self:drawTeardownPanel(panelY)
        else
            self:drawGenericPanel(panelY, currentState)
        end

        -- Advance button (if applicable)
        if currentState ~= camp_controller.STATES.INACTIVE and currentState ~= camp_controller.STATES.TEARDOWN then
            self:drawAdvanceButton(panelY)
        end
    end

    function screen:drawActionsPanel(panelY)
        -- Different instructions for fellowship mode (S9.1)
        if self.fellowshipMode then
            love.graphics.setColor(self.colors.bond_charged)
            if self.fellowshipActor then
                love.graphics.print("FELLOWSHIP - Click another character to share a moment with " ..
                    self.fellowshipActor.name .. " (ESC to cancel)", M.LAYOUT.PADDING, panelY + 10)
            else
                love.graphics.print("FELLOWSHIP - Click a character to select them", M.LAYOUT.PADDING, panelY + 10)
            end

            love.graphics.setColor(self.colors.step_text)
            love.graphics.print("Both characters will charge their bond with each other.", M.LAYOUT.PADDING, panelY + 30)
            return
        end

        if self.targetPickerOpen then
            local actionName = self.targetPickerAction and self.targetPickerAction.name or "Camp Action"
            love.graphics.setColor(self.colors.step_active)
            love.graphics.print(actionName .. " - choose an option (ESC to cancel)", M.LAYOUT.PADDING, panelY + 10)
            love.graphics.setColor(self.colors.step_text)
            love.graphics.print("Pick from the list to submit the Camp Action.", M.LAYOUT.PADDING, panelY + 30)
            return
        end

        love.graphics.setColor(self.colors.step_text)
        love.graphics.print("CAMP ACTIONS - Click a character to assign their action", M.LAYOUT.PADDING, panelY + 10)

        -- Show pending characters
        local pending = self.campController:getPendingAdventurers()
        local pendingText = "Waiting: "
        for i, pc in ipairs(pending) do
            if i > 1 then pendingText = pendingText .. ", " end
            pendingText = pendingText .. pc.name
        end
        love.graphics.setColor(self.colors.warning)
        love.graphics.print(pendingText, M.LAYOUT.PADDING, panelY + 30)
    end

    function screen:drawBreakBreadPanel(panelY)
        love.graphics.setColor(self.colors.step_text)
        love.graphics.print("BREAK BREAD - Click characters to consume rations or go hungry", M.LAYOUT.PADDING, panelY + 10)

        local pending = self.campController:getPendingAdventurers()
        local pendingText = "Need to eat: "
        for i, pc in ipairs(pending) do
            if i > 1 then pendingText = pendingText .. ", " end
            pendingText = pendingText .. pc.name
        end
        love.graphics.setColor(self.colors.warning)
        love.graphics.print(pendingText, M.LAYOUT.PADDING, panelY + 30)
    end

    function screen:drawWatchPanel(panelY)
        love.graphics.setColor(self.colors.step_text)
        love.graphics.print("THE WATCH - Draw from the Meatgrinder to see what stirs in the night...", M.LAYOUT.PADDING, panelY + 10)

        if self.campController.patrolActive then
            love.graphics.setColor(self.colors.step_active)
            love.graphics.print("Patrol active - drawing twice!", M.LAYOUT.PADDING, panelY + 30)
        end

        -- Draw meatgrinder button (only if watch not yet resolved)
        if not self.campController.watchResolved then
            local btnW, btnH = 180, 40
            local btnX = self.width / 2 - btnW / 2
            local btnY = panelY + 50

            local isHover = self.hoverButton == "meatgrinder"

            -- Button background
            if isHover then
                love.graphics.setColor(0.45, 0.25, 0.20, 1.0)  -- Warm hover
            else
                love.graphics.setColor(0.35, 0.18, 0.15, 1.0)  -- Dark red-brown
            end
            love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 6, 6)

            -- Button border
            love.graphics.setColor(0.6, 0.35, 0.25, 1.0)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", btnX, btnY, btnW, btnH, 6, 6)
            love.graphics.setLineWidth(1)

            -- Button text
            love.graphics.setColor(self.colors.button_text)
            love.graphics.printf("Draw from Meatgrinder", btnX, btnY + 12, btnW, "center")

            -- Store bounds for click detection
            self.meatgrinderButtonBounds = { x = btnX, y = btnY, w = btnW, h = btnH }
        else
            -- Watch already resolved
            love.graphics.setColor(self.colors.step_complete)
            love.graphics.print("The night passes...", self.width / 2 - 60, panelY + 55)
            self.meatgrinderButtonBounds = nil
        end
    end

    function screen:drawRecoveryPanel(panelY)
        if self.targetPickerOpen and self.targetPickerAction and
           (self.targetPickerAction.id == "recovery_bond" or self.targetPickerAction.id == "recovery_aid") then
            local actionName = self.targetPickerAction.name or "Recovery"
            love.graphics.setColor(self.colors.step_active)
            love.graphics.print(actionName:upper() .. " - choose a benefit (ESC to cancel)", M.LAYOUT.PADDING, panelY + 10)
            love.graphics.setColor(self.colors.step_text)
            love.graphics.print("Pick from the list to apply the selected Recovery benefit.", M.LAYOUT.PADDING, panelY + 30)
            return
        end

        love.graphics.setColor(self.colors.step_text)
        love.graphics.print("RECOVERY - Click charged bonds, or click a character for affliction aids", M.LAYOUT.PADDING, panelY + 10)
        love.graphics.print("Stressed characters must clear stress first!", M.LAYOUT.PADDING, panelY + 30)
    end

    function screen:drawTeardownPanel(panelY)
        love.graphics.setColor(self.colors.step_text)
        love.graphics.print("TEARDOWN - The party packs up camp and prepares to move on.", M.LAYOUT.PADDING, panelY + 10)

        -- Draw "Break Camp" button
        local btnW, btnH = 160, 40
        local btnX = self.width / 2 - btnW / 2
        local btnY = panelY + 50

        local isHover = self.hoverButton == "breakcamp"

        -- Button background
        if isHover then
            love.graphics.setColor(0.35, 0.45, 0.35, 1.0)  -- Green hover
        else
            love.graphics.setColor(0.25, 0.35, 0.25, 1.0)  -- Dark green
        end
        love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 6, 6)

        -- Button border
        love.graphics.setColor(0.4, 0.55, 0.4, 1.0)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", btnX, btnY, btnW, btnH, 6, 6)
        love.graphics.setLineWidth(1)

        -- Button text
        love.graphics.setColor(self.colors.button_text)
        love.graphics.printf("Break Camp", btnX, btnY + 12, btnW, "center")

        -- Store bounds for click detection
        self.breakCampButtonBounds = { x = btnX, y = btnY, w = btnW, h = btnH }
    end

    function screen:drawGenericPanel(panelY, state)
        love.graphics.setColor(self.colors.step_text)
        love.graphics.print("Camp Phase: " .. (state or "Unknown"), M.LAYOUT.PADDING, panelY + 10)
    end

    function screen:drawAdvanceButton(panelY)
        local btnW, btnH = 120, 35
        local btnX = self.width - btnW - M.LAYOUT.PADDING
        local btnY = panelY + M.LAYOUT.ACTION_PANEL_HEIGHT / 2 - btnH / 2

        -- S9.3: Cannot advance while prompt overlay is showing
        local isBlocked = self.promptOverlay ~= nil
        local isHover = self.hoverButton == "advance" and not isBlocked

        local btnColor
        if isBlocked then
            btnColor = { 0.25, 0.25, 0.25, 0.5 }  -- Greyed out
        elseif isHover then
            btnColor = self.colors.button_hover
        else
            btnColor = self.colors.button_bg
        end

        love.graphics.setColor(btnColor)
        love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 4, 4)

        love.graphics.setColor(self.colors.panel_border)
        love.graphics.rectangle("line", btnX, btnY, btnW, btnH, 4, 4)

        local textColor = isBlocked and { 0.5, 0.5, 0.5, 0.7 } or self.colors.button_text
        love.graphics.setColor(textColor)
        love.graphics.printf("Next Step", btnX, btnY + 10, btnW, "center")

        -- Store button bounds for click detection (nil if blocked)
        self.advanceButtonBounds = isBlocked and nil or { x = btnX, y = btnY, w = btnW, h = btnH }
    end

    function screen:drawActionMenu()
        local menuX = self.actionMenuX
        local menuY = self.actionMenuY
        local menuW = 200
        local itemH = 30
        local menuH = #self.actionMenuItems * itemH + 10

        -- Keep menu on screen
        if menuX + menuW > self.width then
            menuX = self.width - menuW - 10
        end
        if menuY + menuH > self.height - M.LAYOUT.ACTION_PANEL_HEIGHT then
            menuY = self.height - M.LAYOUT.ACTION_PANEL_HEIGHT - menuH - 10
        end

        -- Background
        love.graphics.setColor(self.colors.panel_bg)
        love.graphics.rectangle("fill", menuX, menuY, menuW, menuH, 4, 4)

        -- Border
        love.graphics.setColor(self.colors.panel_border)
        love.graphics.rectangle("line", menuX, menuY, menuW, menuH, 4, 4)

        -- Items
        for i, item in ipairs(self.actionMenuItems) do
            local itemY = menuY + 5 + (i - 1) * itemH
            local isHover = self.hoverButton == "action_" .. i

            if isHover then
                love.graphics.setColor(self.colors.button_hover)
                love.graphics.rectangle("fill", menuX + 2, itemY, menuW - 4, itemH - 2, 2, 2)
            end

            love.graphics.setColor(self.colors.button_text)
            love.graphics.print(item.name, menuX + 10, itemY + 6)
        end

        -- Store bounds
        self.actionMenuBounds = { x = menuX, y = menuY, w = menuW, h = menuH, itemH = itemH }
    end

    function screen:drawTargetPicker()
        local menuX = self.targetPickerX
        local menuY = self.targetPickerY
        local menuW = 280
        local itemH = 42
        local headerH = 28
        local menuH = headerH + #self.targetPickerItems * itemH + 10

        -- Keep menu on screen
        if menuX + menuW > self.width then
            menuX = self.width - menuW - 10
        end
        if menuY + menuH > self.height - M.LAYOUT.ACTION_PANEL_HEIGHT then
            menuY = self.height - M.LAYOUT.ACTION_PANEL_HEIGHT - menuH - 10
        end
        menuX = math.max(10, menuX)
        menuY = math.max(M.LAYOUT.STEP_BAR_HEIGHT + 10, menuY)

        love.graphics.setColor(self.colors.panel_bg)
        love.graphics.rectangle("fill", menuX, menuY, menuW, menuH, 4, 4)

        love.graphics.setColor(self.colors.panel_border)
        love.graphics.rectangle("line", menuX, menuY, menuW, menuH, 4, 4)

        love.graphics.setColor(self.colors.step_text)
        local title = self.targetPickerAction and self.targetPickerAction.name or "Choose Target"
        love.graphics.print(title, menuX + 10, menuY + 7)

        for i, item in ipairs(self.targetPickerItems) do
            local itemY = menuY + headerH + (i - 1) * itemH
            local isHover = self.hoverButton == "target_" .. i

            if isHover then
                love.graphics.setColor(self.colors.button_hover)
                love.graphics.rectangle("fill", menuX + 2, itemY, menuW - 4, itemH - 2, 2, 2)
            end

            love.graphics.setColor(self.colors.button_text)
            love.graphics.print(item.label or "Target", menuX + 10, itemY + 5)
            if item.detail then
                love.graphics.setColor(self.colors.step_text)
                love.graphics.print(item.detail, menuX + 10, itemY + 22)
            end
        end

        self.targetPickerBounds = {
            x = menuX,
            y = menuY,
            w = menuW,
            h = menuH,
            itemH = itemH,
            headerH = headerH,
        }
    end

    ----------------------------------------------------------------------------
    -- INPUT HANDLING
    ----------------------------------------------------------------------------

    function screen:mousepressed(x, y, button)
        if button ~= 1 then return end

        local currentState = self.campController and self.campController:getState()

        -- S9.3: Check prompt overlay click (dismisses it)
        if self.promptOverlay then
            self:dismissPromptOverlay()
            return
        end

        -- S9.1: Handle fellowship mode clicks
        if self.fellowshipMode then
            self:handleFellowshipClick(x, y)
            return
        end

        -- Check target picker click
        if self.targetPickerOpen then
            if self:handleTargetPickerClick(x, y) then
                return
            else
                self:cancelTargetPicker()
            end
        end

        -- Check action menu click
        if self.actionMenuOpen then
            if self:handleActionMenuClick(x, y) then
                return
            else
                self.actionMenuOpen = false
            end
        end

        -- Check meatgrinder button (Watch phase)
        if self.meatgrinderButtonBounds then
            local btn = self.meatgrinderButtonBounds
            if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
                self:handleMeatgrinderClick()
                return
            end
        end

        -- Check break camp button (Teardown phase)
        if self.breakCampButtonBounds then
            local btn = self.breakCampButtonBounds
            if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
                self:handleBreakCampClick()
                return
            end
        end

        -- Check advance button
        if self.advanceButtonBounds then
            local btn = self.advanceButtonBounds
            if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
                self:handleAdvanceClick()
                return
            end
        end

        -- Check character plate clicks
        for i, plate in ipairs(self.characterPlates) do
            if x >= plate.x and x <= plate.x + M.LAYOUT.PLATE_WIDTH and
               y >= plate.y and y <= plate.y + plate:getHeight() then

                if currentState == camp_controller.STATES.ACTIONS then
                    self:openActionMenuFor(i, x, y)
                elseif currentState == camp_controller.STATES.BREAK_BREAD then
                    self:handleBreakBreadClick(i)
                elseif currentState == camp_controller.STATES.RECOVERY then
                    self:handleRecoveryClick(i, x, y)
                end
                return
            end
        end
    end

    function screen:mousereleased(x, y, button)
        -- Nothing special for now
    end

    function screen:mousemoved(x, y, dx, dy)
        self.hoverButton = nil
        self.hoveredBond = nil
        self.hoveredPlateIndex = nil

        -- Check which plate is hovered (for fellowship mode)
        for i, plate in ipairs(self.characterPlates) do
            if x >= plate.x and x <= plate.x + M.LAYOUT.PLATE_WIDTH and
               y >= plate.y and y <= plate.y + plate:getHeight() then
                self.hoveredPlateIndex = i
                break
            end
        end

        -- Check meatgrinder button hover
        if self.meatgrinderButtonBounds then
            local btn = self.meatgrinderButtonBounds
            if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
                self.hoverButton = "meatgrinder"
            end
        end

        -- Check break camp button hover
        if self.breakCampButtonBounds then
            local btn = self.breakCampButtonBounds
            if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
                self.hoverButton = "breakcamp"
            end
        end

        -- Check advance button hover
        if self.advanceButtonBounds then
            local btn = self.advanceButtonBounds
            if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
                self.hoverButton = "advance"
            end
        end

        -- Check action menu hover
        if self.actionMenuOpen and self.actionMenuBounds then
            local menu = self.actionMenuBounds
            if x >= menu.x and x <= menu.x + menu.w and y >= menu.y and y <= menu.y + menu.h then
                local itemIndex = math.floor((y - menu.y - 5) / menu.itemH) + 1
                if itemIndex >= 1 and itemIndex <= #self.actionMenuItems then
                    self.hoverButton = "action_" .. itemIndex
                end
            end
        end

        -- Check target picker hover
        if self.targetPickerOpen and self.targetPickerBounds then
            local menu = self.targetPickerBounds
            if x >= menu.x and x <= menu.x + menu.w and y >= menu.y and y <= menu.y + menu.h then
                local itemIndex = math.floor((y - menu.y - menu.headerH) / menu.itemH) + 1
                if itemIndex >= 1 and itemIndex <= #self.targetPickerItems then
                    self.hoverButton = "target_" .. itemIndex
                end
            end
        end

        -- Check bond hover (during recovery)
        local currentState = self.campController and self.campController:getState()
        if currentState == camp_controller.STATES.RECOVERY then
            for i, plate in ipairs(self.characterPlates) do
                local pc = self.guild[i]
                if pc and pc.bonds then
                    local bondX = plate.x + M.LAYOUT.PLATE_WIDTH - 30
                    local bondY = plate.y + 5
                    local bondSize = 12
                    local bondSpacing = bondSize + 4

                    local bondIndex = 0
                    for targetId, bond in pairs(pc.bonds) do
                        local bx = bondX
                        local by = bondY + bondIndex * bondSpacing
                        local dist = math.sqrt((x - bx)^2 + (y - by)^2)
                        if dist < bondSize then
                            self.hoveredBond = { pcIndex = i, targetId = targetId, bond = bond }
                        end
                        bondIndex = bondIndex + 1
                    end
                end
            end
        end
    end

    function screen:keypressed(key)
        if key == "escape" then
            -- Cancel selection modes first, then action menu
            if self.fellowshipMode then
                self:cancelFellowshipMode()
            elseif self.targetPickerOpen then
                self:cancelTargetPicker()
            elseif self.actionMenuOpen then
                self.actionMenuOpen = false
            end
        end
    end

    --- Cancel fellowship selection mode (S9.1)
    function screen:cancelFellowshipMode()
        self.fellowshipMode = false
        self.fellowshipActor = nil
        self.fellowshipActorIndex = nil
        self.fellowshipLaborUnending = false
        print("[CampScreen] Fellowship cancelled")
    end

    function screen:cancelTargetPicker(silent)
        self.targetPickerOpen = false
        self.targetPickerItems = {}
        self.targetPickerAction = nil
        self.targetPickerActor = nil
        self.targetPickerBounds = nil
        if not silent then
            print("[CampScreen] Target selection cancelled")
        end
    end

    ----------------------------------------------------------------------------
    -- ACTION HANDLERS
    ----------------------------------------------------------------------------

    function screen:openActionMenuFor(pcIndex, x, y)
        local pc = self.guild[pcIndex]
        if not pc then return end

        local laborUnendingExtra = self:canUseLaborUnendingForExtraAction(pc)
        if self.campController.actionsCompleted[pc.id] and not laborUnendingExtra then
            return
        end

        self.selectedPC = pc
        self.actionMenuX = x
        self.actionMenuY = y

        -- Get available actions
        if self.campController and self.campController.getAvailableActions then
            self.actionMenuItems = self.campController:getAvailableActions(pc)
        else
            self.actionMenuItems = camp_actions.getAvailableActions(pc, self.guild)
        end
        if laborUnendingExtra then
            self.actionMenuItems = self:withLaborUnendingActionItems(self.actionMenuItems)
        end
        self.actionMenuOpen = true
    end

    function screen:canUseLaborUnendingForExtraAction(pc)
        if not pc or not pc.id or not self.campController then
            return false
        end
        local completed = self.campController.actionsCompleted or {}
        if not completed[pc.id] then
            return false
        end
        if self.campController.canUseLaborUnending then
            local ok = self.campController:canUseLaborUnending(pc)
            return ok == true
        end
        local used = self.campController.extraCampActionsUsed or {}
        if used[pc.id] then
            return false
        end
        if pc.conditions and pc.conditions.stressed then
            return false
        end
        local talents = pc.talents or {}
        local talent = talents.labor_unending or talents["labor unending"] or talents["Labor Unending"]
        if type(talent) == "table" then
            return talent.wounded ~= true
        end
        return talent == true
    end

    function screen:withLaborUnendingActionItems(actions)
        local items = {}
        for i, action in ipairs(actions or {}) do
            local copy = {}
            for key, value in pairs(action) do
                copy[key] = value
            end
            copy.name = (action.name or action.id or "Camp Action") .. " + Labor"
            copy.baseName = action.name
            copy.useLaborUnending = true
            items[i] = copy
        end
        return items
    end

    function screen:handleActionMenuClick(x, y)
        if not self.actionMenuBounds then return false end

        local menu = self.actionMenuBounds
        if x < menu.x or x > menu.x + menu.w or y < menu.y or y > menu.y + menu.h then
            return false
        end

        local itemIndex = math.floor((y - menu.y - 5) / menu.itemH) + 1
        if itemIndex >= 1 and itemIndex <= #self.actionMenuItems then
            local action = self.actionMenuItems[itemIndex]
            self:submitCampAction(self.selectedPC, action, x, y)
            self.actionMenuOpen = false
            return true
        end

        return false
    end

    function screen:isReadableCampBook(item)
        local props = item and item.properties or {}
        local bookish = item and (item.type == "book" or props.book == true or
            props.readableBook == true or props.isReadableBook == true)
        return bookish and (
            props.readableBook == true or
            props.isReadableBook == true or
            props.loreSubjectId ~= nil or
            props.loreAnswers ~= nil
        )
    end

    function screen:isPipeweedCampItem(item)
        local props = item and item.properties or {}
        local effect = props.useEffect or {}
        local clearsStress = false
        for _, condition in ipairs(effect.conditions or {}) do
            if condition == "stressed" then
                clearsStress = true
                break
            end
        end
        return props.effect == "clear_stress" or
            (effect.type == "clear_conditions" and effect.target == "self" and clearsStress)
    end

    function screen:isTinkersKitCampItem(item)
        local props = item and item.properties or {}
        return item and (item.templateId == "tinkers_kit" or item.type == "tinkers_kit" or
            props.toolType == "tinker" or props.tinkersKit == true)
    end

    function screen:isLeechesCampItem(item)
        local props = item and item.properties or {}
        return props.leeches == true
    end

    function screen:isHealthfulRecoveryItem(item)
        local props = item and item.properties or {}
        return props.afflictionCureCharges ~= nil and props.leeches ~= true
    end

    function screen:isFreshGameCampItem(item)
        local props = item and item.properties or {}
        return props.freshGame == true
    end

    function screen:hasCampSalt(pc)
        local inv = pc and pc.inventory
        if not inv or not inv.findItemByPredicate then
            return false
        end

        local salt = inv:findItemByPredicate(function(item)
            local name = item.name and item.name:lower()
            return item.templateId == "salt" or item.type == "salt" or name == "salt"
        end)
        return salt ~= nil
    end

    function screen:hasCookingGear(pc)
        local inv = pc and pc.inventory
        if not inv or not inv.findItemByPredicate then
            return false
        end

        local gear = inv:findItemByPredicate(function(item)
            local props = item and item.properties or {}
            return item.templateId == "cooking_gear" or item.type == "cooking_gear" or
                props.cookingGear == true or props.toolType == "cooking"
        end)
        return gear ~= nil
    end

    function screen:isCampUsableItem(item, pc)
        local props = item and item.properties or {}
        return props.campUse == true or self:isPipeweedCampItem(item) or
            self:isTinkersKitCampItem(item) or self:isLeechesCampItem(item) or
            (self:isFreshGameCampItem(item) and (self:hasCookingGear(pc) or self:hasCampSalt(pc)))
    end

    function screen:getInventoryTargetItems(pc, actionDef)
        local inv = pc and pc.inventory
        if not inv or not inv.getAllItems then
            return {}
        end

        local targets = {}
        for _, entry in ipairs(inv:getAllItems()) do
            local item = entry.item
            local include = item ~= nil
            if actionDef.id == "repair" then
                include = item and not item.destroyed and (tonumber(item.notches) or 0) > 0
            elseif actionDef.id == "read_book" then
                include = self:isReadableCampBook(item)
            end

            if include then
                local detail = entry.location
                if actionDef.id == "repair" then
                    detail = string.format("%s, %d notch%s", entry.location, item.notches or 0,
                        (item.notches == 1) and "" or "es")
                elseif actionDef.id == "read_book" then
                    local props = item.properties or {}
                    detail = props.subjectMatter or props.loreSubjectId or entry.location
                end
                targets[#targets + 1] = {
                    label = item.name or item.id or "Item",
                    detail = detail,
                    target = item,
                }
            end
        end

        return targets
    end

    function screen:getInventoryItemById(pc, itemId)
        if not itemId then
            return nil
        end
        local inv = pc and pc.inventory
        if not inv or not inv.getAllItems then
            return nil
        end
        for _, entry in ipairs(inv:getAllItems()) do
            local item = entry.item
            if item and item.id == itemId then
                return item
            end
        end
        return nil
    end

    function screen:getReadBookOptionData(pc, opts)
        if type(camp_actions.getReadBookOptions) ~= "function" then
            return nil
        end
        return camp_actions.getReadBookOptions(pc, opts or {})
    end

    function screen:getCampUseItemOptionData(pc, opts)
        if type(camp_actions.getUseItemOptions) ~= "function" then
            return nil
        end
        return camp_actions.getUseItemOptions(pc, self:getCampActionOptionContext(opts))
    end

    function screen:getRepairOptionData(pc, opts)
        if type(camp_actions.getRepairOptions) ~= "function" then
            return nil
        end
        return camp_actions.getRepairOptions(pc, opts or {})
    end

    function screen:getReadBookTargetItems(pc)
        local backendOptions = self:getReadBookOptionData(pc)
        if backendOptions then
            local targets = {}
            for _, bookOption in ipairs(backendOptions.bookOptions or {}) do
                if not bookOption.disabled then
                    local book = self:getInventoryItemById(pc, bookOption.id)
                    if book then
                        targets[#targets + 1] = {
                            label = bookOption.name or book.name or book.id or "Book",
                            detail = bookOption.subjectMatter or bookOption.subjectId or bookOption.location,
                            target = book,
                            readBookOption = bookOption,
                        }
                    end
                end
            end
            return targets
        end
        return self:getInventoryTargetItems(pc, { id = "read_book" })
    end

    function screen:getRepairTargetItems(pc)
        local backendOptions = self:getRepairOptionData(pc)
        if backendOptions then
            local targets = {}
            for _, repairTarget in ipairs(backendOptions.repairTargets or {}) do
                if not repairTarget.disabled then
                    local item = self:getInventoryItemById(pc, repairTarget.id)
                    if item then
                        local notches = tonumber(repairTarget.notches or item.notches) or 0
                        local after = tonumber(repairTarget.notchesAfterRepair)
                        local detail = string.format("%s, %d notch%s", repairTarget.location or "carried",
                            notches, notches == 1 and "" or "es")
                        if after then
                            detail = detail .. " -> " .. tostring(after)
                        end
                        targets[#targets + 1] = {
                            label = repairTarget.name or item.name or item.id or "Item",
                            detail = detail,
                            target = item,
                            repairOption = repairTarget,
                        }
                    end
                end
            end
            return targets
        end

        return self:getInventoryTargetItems(pc, { id = "repair" })
    end

    function screen:getCampUseItemTargetItems(pc)
        local backendOptions = self:getCampUseItemOptionData(pc)
        if backendOptions then
            local targets = {}
            for _, option in ipairs(backendOptions.itemOptions or {}) do
                if not option.disabled then
                    local item = self:getInventoryItemById(pc, option.id)
                    if item then
                        local detail = option.location or "carried"
                        if option.kind == "pipeweed" then
                            detail = detail .. ", clears Stressed"
                        elseif option.kind == "leeches" then
                            detail = detail .. ", affliction treatment"
                        elseif option.kind == "tinkers_kit" then
                            detail = detail .. ", repair kit"
                        elseif option.kind == "fresh_game" then
                            local preparations = {}
                            for _, prep in ipairs(option.preparationOptions or {}) do
                                preparations[#preparations + 1] = prep.name or prep.preparation
                            end
                            if #preparations > 0 then
                                detail = detail .. ", " .. table.concat(preparations, " or ")
                            end
                        elseif option.resultPreview then
                            detail = detail .. ", " .. option.resultPreview
                        end

                        local actionData = nil
                        if not option.requiresTargetSelection and not option.requiresRepairTarget and
                           not option.requiresPreparation then
                            actionData = self:copyTable(option.actionDataPreview or {
                                itemId = item.id,
                            })
                        end

                        targets[#targets + 1] = {
                            label = option.name or item.name or item.id or "Item",
                            detail = detail,
                            target = item,
                            campItemKind = option.kind or "item",
                            actionData = actionData,
                            campUseItemOption = option,
                        }
                    end
                end
            end
            return targets
        end

        local inv = pc and pc.inventory
        if not inv or not inv.getAllItems then
            return {}
        end

        local targets = {}
        for _, entry in ipairs(inv:getAllItems()) do
            local item = entry.item
            if self:isCampUsableItem(item, pc) then
                local detail = entry.location or "carried"
                local actionData = { itemId = item.id }
                local kind = "item"
                if self:isPipeweedCampItem(item) then
                    detail = detail .. ", clears Stressed"
                    kind = "pipeweed"
                elseif self:isLeechesCampItem(item) then
                    detail = detail .. ", affliction treatment"
                    actionData = nil
                    kind = "leeches"
                elseif self:isTinkersKitCampItem(item) then
                    detail = detail .. ", repair kit"
                    actionData = nil
                    kind = "tinkers_kit"
                elseif self:isFreshGameCampItem(item) then
                    local options = {}
                    if self:hasCookingGear(pc) then
                        options[#options + 1] = "cook"
                    end
                    if self:hasCampSalt(pc) then
                        options[#options + 1] = "preserve"
                    end
                    detail = detail .. ", " .. table.concat(options, " or ")
                    actionData = nil
                    kind = "fresh_game"
                end

                targets[#targets + 1] = {
                    label = item.name or item.id or "Item",
                    detail = detail,
                    target = item,
                    campItemKind = kind,
                    actionData = actionData,
                }
            end
        end

        return targets
    end

    function screen:getCompanionTargetItems(pc)
        local targets = {}
        local seen = {}
        local function add(companion)
            if not companion then
                return
            end
            local key = companion.id or companion.name or tostring(#targets + 1)
            if seen[key] then
                return
            end
            seen[key] = true
            local status = "Companion"
            if companion.conditions and companion.conditions.injured then
                status = "Injured companion"
            elseif companion.conditions and companion.conditions.staggered then
                status = "Staggered companion"
            end
            targets[#targets + 1] = {
                label = companion.name or key,
                detail = status,
                target = companion,
            }
        end

        add(pc and pc.companion)
        for _, companion in ipairs(pc and pc.animalCompanions or {}) do
            add(companion)
        end
        return targets
    end

    function screen:getActorTalentRecord(actor, talentId)
        local requested = talent_catalog.normalizeId(talentId)
        for key, talent in pairs(actor and actor.talents or {}) do
            if talent_catalog.normalizeId(key) == requested then
                return talent, key
            end
            if type(talent) == "table" and
               talent_catalog.normalizeId(talent.id or talent.name or talent.talentId) == requested then
                return talent, key
            end
        end
        return nil
    end

    function screen:isMasteredTrainTalent(talent)
        if type(talent) == "table" then
            return talent.mastered == true and talent.wounded ~= true
        end
        return talent == true
    end

    function screen:formatTalentName(talentId)
        local text = tostring(talentId or "Talent"):gsub("_", " ")
        return text:gsub("(%a)([%w']*)", function(first, rest)
            return first:upper() .. rest:lower()
        end)
    end

    function screen:isUsableTalentRecord(talent)
        if type(talent) == "table" then
            return talent.mastered == true and talent.wounded ~= true
        end
        return talent == true
    end

    function screen:isBreakBreadFoodItem(item)
        local props = item and item.properties or {}
        return item and (
            item.isRation == true or item.type == "ration" or item.itemType == "ration" or
            props.isRation == true or props.isCampMeal == true or
            props.emergencyRation == true or props.rationSubstitute == true or
            item.emergencyRation == true or item.rationSubstitute == true or
            (item.name and item.name:lower():find("ration") ~= nil)
        )
    end

    function screen:countBreakBreadFood(pc)
        local inv = pc and pc.inventory
        if not inv or not inv.getAllItems then
            return 0
        end

        local count = 0
        for _, entry in ipairs(inv:getAllItems()) do
            if self:isBreakBreadFoodItem(entry.item) then
                count = count + math.max(1, tonumber(entry.item.quantity or 1) or 1)
            end
        end
        return count
    end

    function screen:getBondTargetLabel(pc, targetId)
        local bond = pc and pc.bonds and pc.bonds[targetId]
        if bond and bond.name then
            return bond.name
        end
        for _, other in ipairs(self.guild or {}) do
            if other and other.id == targetId then
                return other.name or targetId
            end
        end
        return tostring(targetId or "Bond")
    end

    function screen:getUnchargedBondIds(pc)
        local ids = {}
        for targetId, bond in pairs(pc and pc.bonds or {}) do
            if bond and bond.charged ~= true then
                ids[#ids + 1] = targetId
            end
        end
        table.sort(ids, function(a, b)
            return tostring(a) < tostring(b)
        end)
        return ids
    end

    function screen:getAnimalCompanionEntries(pc)
        local entries = {}
        for key, companion in pairs(pc and pc.animalCompanions or {}) do
            if type(companion) == "table" then
                entries[#entries + 1] = {
                    key = key,
                    companion = companion,
                }
            end
        end
        table.sort(entries, function(a, b)
            return tostring(a.key) < tostring(b.key)
        end)
        return entries
    end

    function screen:getAnimalCompanionFeedKey(pc, companion, key)
        if companion and companion.id then
            return companion.id
        end
        return (pc and pc.id or "owner") .. "_companion_" .. tostring(key or companion)
    end

    function screen:normalizeFeedKey(value)
        return tostring(value or ""):lower():gsub("[’']", ""):gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    end

    function screen:isAnimalFeedItem(item)
        local props = item and item.properties or {}
        return item and (
            item.type == "animal_feed" or item.itemType == "animal_feed" or
            props.isAnimalFeed == true or props.animalFeed == true
        )
    end

    function screen:animalFeedMatchesCompanion(item, companion)
        local props = item and item.properties or {}
        local feedFor = props.feedFor or props.animalType or props.animalKind
        if not feedFor or feedFor == "any" then
            return true
        end

        feedFor = self:normalizeFeedKey(feedFor)
        local candidates = {
            companion and companion.id,
            companion and companion.type,
            companion and companion.animalType,
            companion and companion.species,
            companion and companion.feedType,
            companion and companion.kind,
            companion and companion.name,
        }
        for _, candidate in pairs(candidates) do
            if candidate and self:normalizeFeedKey(candidate) == feedFor then
                return true
            end
        end
        return false
    end

    function screen:getBreakBreadAnimalFeedStatuses(pc)
        local entries = self:getAnimalCompanionEntries(pc)
        if #entries == 0 then
            return {}
        end

        local feedItems = {}
        local inv = pc and pc.inventory
        if inv and inv.getAllItems then
            for _, entry in ipairs(inv:getAllItems()) do
                if self:isAnimalFeedItem(entry.item) then
                    feedItems[#feedItems + 1] = {
                        item = entry.item,
                        remaining = math.max(1, tonumber(entry.item.quantity or 1) or 1),
                    }
                end
            end
        end

        local statuses = {}
        local resolved = self.campController and self.campController.animalFeedConsumed or {}
        for _, entry in ipairs(entries) do
            local companion = entry.companion
            local feedKey = self:getAnimalCompanionFeedKey(pc, companion, entry.key)
            local conditions = companion.conditions or {}
            local status = {
                companion = companion,
                key = entry.key,
                name = companion.name or companion.id or "Animal companion",
                resolved = resolved[feedKey] == true,
                abandoned = companion.abandoned == true or conditions.abandoned == true,
                selfSupplied = companion.suppliesOwnFood == true or companion.selfFeeding == true,
            }
            if not status.resolved and not status.abandoned and not status.selfSupplied then
                for _, feed in ipairs(feedItems) do
                    if feed.remaining > 0 and self:animalFeedMatchesCompanion(feed.item, companion) then
                        status.feedItem = feed.item
                        feed.remaining = feed.remaining - 1
                        break
                    end
                end
            end
            statuses[#statuses + 1] = status
        end
        return statuses
    end

    function screen:formatBreakBreadAnimalFeedDetail(statuses)
        local parts = {}
        for _, status in ipairs(statuses or {}) do
            local label = status.name or "Companion"
            if status.resolved then
                parts[#parts + 1] = label .. ": resolved"
            elseif status.abandoned then
                parts[#parts + 1] = label .. ": abandoned"
            elseif status.selfSupplied then
                parts[#parts + 1] = label .. ": self-fed"
            elseif status.feedItem then
                parts[#parts + 1] = label .. ": " .. (status.feedItem.name or "Animal Feed")
            else
                parts[#parts + 1] = label .. ": no feed"
            end
        end
        return table.concat(parts, "; ")
    end

    function screen:getBreakBreadChoiceItems(pc)
        local talent = self:getActorTalentRecord(pc, "hale_and_hearty")
        local unchargedBonds = self:getUnchargedBondIds(pc)
        local animalFeedStatuses = self:getBreakBreadAnimalFeedStatuses(pc)
        local animalFeedDetail = self:formatBreakBreadAnimalFeedDetail(animalFeedStatuses)
        local canUseHaleAndHearty = self:isUsableTalentRecord(talent) and #unchargedBonds > 0 and
            self:countBreakBreadFood(pc) >= 2
        if not canUseHaleAndHearty and #animalFeedStatuses == 0 then
            return {}
        end

        local choices = {
            {
                label = "Eat Ration",
                detail = animalFeedDetail ~= "" and animalFeedDetail or "Satisfy Break Bread",
                actionData = {},
            },
        }
        if canUseHaleAndHearty then
            for _, targetId in ipairs(unchargedBonds) do
                local detail = "Charge bond with " .. self:getBondTargetLabel(pc, targetId)
                if animalFeedDetail ~= "" then
                    detail = detail .. "; " .. animalFeedDetail
                end
                choices[#choices + 1] = {
                    label = "Eat Second Ration",
                    detail = detail,
                    actionData = {
                        chargeBondTargetId = targetId,
                    },
                }
            end
        end
        return choices
    end

    function screen:enterBreakBreadPicker(pc, x, y)
        local choices = self:getBreakBreadChoiceItems(pc)
        if #choices == 0 then
            return false
        end

        self.targetPickerOpen = true
        self.targetPickerItems = choices
        self.targetPickerAction = {
            id = "break_bread",
            name = "Break Bread",
        }
        self.targetPickerActor = pc
        self.targetPickerX = x or self.actionMenuX
        self.targetPickerY = y or self.actionMenuY
        self.targetPickerBounds = nil
        self.actionMenuOpen = false
        return true
    end

    function screen:getAvailableTrainingXP(pc)
        return math.max(0, math.floor(tonumber(pc and (pc.xp or pc.experience)) or 0))
    end

    function screen:getCampActionsCompleted()
        local controller = self.campController
        if type(controller) == "table" and type(controller.actionsCompleted) == "table" then
            return controller.actionsCompleted
        end
        return {}
    end

    function screen:getGuildMemberById(entityId)
        if not entityId then
            return nil
        end
        for _, member in ipairs(self.guild or {}) do
            if member and member.id == entityId then
                return member
            end
        end
        return nil
    end

    function screen:getTrainOptionData(pc, opts)
        if type(camp_actions.getTrainOptions) ~= "function" then
            return nil
        end
        local request = {}
        for key, value in pairs(opts or {}) do
            request[key] = value
        end
        request.actionsCompleted = request.actionsCompleted or self:getCampActionsCompleted()
        return camp_actions.getTrainOptions(pc, self.guild, request)
    end

    function screen:getCampActionOptionContext(extra)
        local controller = self.campController or {}
        local context = {
            campController = controller,
            guild = self.guild,
            currentRoom = controller.currentRoom,
            currentRoomId = controller.currentRoomId,
            roomManager = controller.roomManager,
            dungeon = controller.dungeon,
            watchManager = controller.watchManager,
            guildMap = controller.guildMap or controller.mapState,
            mapState = controller.mapState or controller.guildMap,
            traveledRooms = controller.traveledRooms,
        }
        for key, value in pairs(extra or {}) do
            context[key] = value
        end
        return context
    end

    function screen:getTrainableTalentItems(pc, trainer)
        local backendOptions = self:getTrainOptionData(pc, {
            trainerId = trainer and trainer.id or trainer,
        })
        if backendOptions and backendOptions.selectedTrainer then
            local trainerOption = backendOptions.selectedTrainer
            if trainerOption.disabled then
                return {}
            end
            local trainerEntity = type(trainer) == "table" and trainer or
                self:getGuildMemberById(trainerOption.id or trainer)
            local items = {}
            for _, talentOption in ipairs(trainerOption.talentOptions or {}) do
                if not talentOption.disabled then
                    local detail = talentOption.ownPath and "Own path" or "Mentored"
                    if (tonumber(talentOption.xpInvested) or 0) > 0 then
                        detail = detail .. ", " .. talentOption.xpInvested .. " XP invested"
                    end
                    items[#items + 1] = {
                        label = talentOption.name or self:formatTalentName(talentOption.id),
                        detail = detail,
                        target = trainerEntity,
                        trainer = trainerEntity,
                        trainingTalentId = talentOption.id,
                        trainTalentOption = talentOption,
                    }
                end
            end
            return items
        end

        local items = {}
        local seen = {}
        for key, talent in pairs(trainer and trainer.talents or {}) do
            local rawTalentId = type(talent) == "table" and (talent.id or talent.talentId or talent.name) or key
            local talentId = talent_catalog.normalizeId(rawTalentId)
            if talentId ~= "" and not seen[talentId] and self:isMasteredTrainTalent(talent) then
                seen[talentId] = true
                local existingTalent = self:getActorTalentRecord(pc, talentId)
                local alreadyMastered = type(existingTalent) == "table" and existingTalent.mastered == true or
                    existingTalent == true
                local ok, training = talent_catalog.validateTraining(pc, talentId, {
                    hasTrainer = true,
                    trainerAvailable = true,
                })
                if ok and not alreadyMastered then
                    local invested = type(existingTalent) == "table" and
                        (tonumber(existingTalent.xp_invested) or 0) or 0
                    local detail = training.ownPath and "Own path" or "Mentored"
                    if invested > 0 then
                        detail = detail .. ", " .. invested .. " XP invested"
                    end
                    items[#items + 1] = {
                        label = self:formatTalentName(talentId),
                        detail = detail,
                        target = trainer,
                        trainer = trainer,
                        trainingTalentId = talentId,
                    }
                end
            end
        end
        table.sort(items, function(a, b)
            return (a.label or "") < (b.label or "")
        end)
        return items
    end

    function screen:getTrainTrainerTargetItems(pc)
        local backendOptions = self:getTrainOptionData(pc)
        if backendOptions then
            local targets = {}
            for _, trainerOption in ipairs(backendOptions.trainerOptions or {}) do
                local trainer = self:getGuildMemberById(trainerOption.id)
                if trainer then
                    local count = tonumber(trainerOption.teachableTalentCount) or
                        #(trainerOption.talentOptions or {})
                    targets[#targets + 1] = {
                        label = trainerOption.name or trainer.name or trainer.id or "Adventurer",
                        detail = count .. " teachable talent" .. (count == 1 and "" or "s"),
                        target = trainer,
                        trainTrainerOption = trainerOption,
                    }
                end
            end
            return targets
        end

        local targets = {}
        for _, other in ipairs(self.guild or {}) do
            if other and other.isPC == true and other.id ~= pc.id then
                local talents = self:getTrainableTalentItems(pc, other)
                if #talents > 0 then
                    targets[#targets + 1] = {
                        label = other.name or other.id or "Adventurer",
                        detail = #talents .. " teachable talent" .. (#talents == 1 and "" or "s"),
                        target = other,
                    }
                end
            end
        end
        return targets
    end

    function screen:getTrainXPAmountItems(pc, trainer, talentId)
        local backendOptions = self:getTrainOptionData(pc, {
            trainerId = trainer and trainer.id or trainer,
            talentId = talentId,
        })
        if backendOptions and backendOptions.selectedTalent then
            if backendOptions.selectedTalent.disabled then
                return {}
            end
            local trainerEntity = type(trainer) == "table" and trainer or self:getGuildMemberById(
                trainer or (backendOptions.selectedTrainer and backendOptions.selectedTrainer.id)
            )
            local items = {}
            for _, xpOption in ipairs(backendOptions.xpOptions or {}) do
                local actionData = self:copyTable(xpOption.actionDataPreview or {})
                actionData.type = actionData.type or "train"
                actionData.target = trainerEntity
                actionData.request = actionData.request or {
                    talentId = talentId,
                    xp = xpOption.xp,
                }
                local detail = "Invest in " ..
                    (backendOptions.selectedTalent.name or self:formatTalentName(talentId))
                if xpOption.masteredAfter then
                    detail = detail .. ", masters talent"
                elseif xpOption.remainingXPToMasteryAfter ~= nil then
                    detail = detail .. ", " .. xpOption.remainingXPToMasteryAfter .. " XP to mastery"
                end
                items[#items + 1] = {
                    label = xpOption.xp .. " XP",
                    detail = detail,
                    target = trainerEntity,
                    actionData = actionData,
                    trainXPOption = xpOption,
                }
            end
            return items
        end

        local availableXP = self:getAvailableTrainingXP(pc)
        if availableXP <= 0 then
            return {}
        end

        local existingTalent = self:getActorTalentRecord(pc, talentId)
        local invested = type(existingTalent) == "table" and (tonumber(existingTalent.xp_invested) or 0) or 0
        local remainingToMastery = math.max(1, 7 - invested)
        local maxXP = math.min(availableXP, remainingToMastery)
        local items = {}
        for amount = 1, maxXP do
            items[#items + 1] = {
                label = amount .. " XP",
                detail = "Invest in " .. self:formatTalentName(talentId),
                target = trainer,
                actionData = {
                    target = trainer,
                    request = {
                        talentId = talentId,
                        xp = amount,
                    },
                },
            }
        end
        return items
    end

    function screen:getCampTalentLabel(talentId)
        local labels = {
            beast_master = "Beast Master",
            bookworm = "Bookworm",
            chirurgeon = "Chirurgery",
            high_chant = "High Chant",
            loremaster = "Loremaster",
            sneak = "Sneak",
            war_stories = "War Stories",
        }
        return labels[talentId] or self:formatTalentName(talentId)
    end

    function screen:getCampTalentTargetItems(pc)
        local details = {
            beast_master = "Teach or retrain an animal companion command",
            bookworm = "Record a readable book as lore",
            chirurgeon = "Heal a resting, non-Stressed guild-mate",
            high_chant = "Turn a discard into inspiration",
            loremaster = "Translate a short ancient text",
            sneak = "Use Infiltrate for known locations",
            war_stories = "Share a tale for Resolve or Bonds",
        }
        local targets = {}
        for _, option in ipairs(camp_actions.getCampTalentOptions(pc)) do
            targets[#targets + 1] = {
                label = self:getCampTalentLabel(option.id),
                detail = details[option.id],
                campTalentId = option.id,
            }
        end
        return targets
    end

    function screen:getGuildMemberNameById(entityId)
        for _, member in ipairs(self.guild or {}) do
            if member and member.id == entityId then
                return member.name or member.id
            end
        end
        return nil
    end

    function screen:getWarStoriesBenefitItems(pc, selectedParticipants, selectedBenefits)
        selectedParticipants = selectedParticipants or {}
        selectedBenefits = selectedBenefits or {}

        local selectedByKey = {}
        local actorSelected = false
        for _, participant in ipairs(selectedParticipants) do
            local key = participant and (participant.id or participant.name)
            if key then
                selectedByKey[key] = true
            end
            if participant == pc or (participant and pc and participant.id == pc.id) then
                actorSelected = true
            end
        end

        local targets = {}
        if actorSelected then
            targets[#targets + 1] = {
                label = "Share War Stories",
                detail = #selectedParticipants .. " participant" .. (#selectedParticipants == 1 and "" or "s") .. " selected",
                actionData = {
                    talentId = "war_stories",
                    participants = self:copyArray(selectedParticipants),
                    benefits = self:copyTable(selectedBenefits),
                },
            }
        end

        for _, participant in ipairs(self.guild or {}) do
            if participant and participant.isPC == true then
                local key = participant.id or participant.name
                if key and not selectedByKey[key] then
                    local participants = self:copyArray(selectedParticipants)
                    local benefits = self:copyTable(selectedBenefits)
                    participants[#participants + 1] = participant
                    benefits[key] = { type = "resolve" }
                    targets[#targets + 1] = {
                        label = (participant.name or participant.id or "Adventurer") .. ": Gain Resolve",
                        detail = "May raise Resolve to 5",
                        target = participant,
                        campTalentStep = "war_stories_benefit",
                        warStoriesParticipant = participant,
                        warStoriesBenefit = "resolve",
                        selectedParticipants = participants,
                        selectedBenefits = benefits,
                    }

                    for targetId, bond in pairs(participant.bonds or {}) do
                        if type(bond) == "table" and not bond.charged then
                            local bondParticipants = self:copyArray(selectedParticipants)
                            local bondBenefits = self:copyTable(selectedBenefits)
                            bondParticipants[#bondParticipants + 1] = participant
                            bondBenefits[key] = {
                                type = "charge_bond",
                                bondTargetId = targetId,
                            }
                            local bondName = bond.name or self:getGuildMemberNameById(targetId) or targetId
                            targets[#targets + 1] = {
                                label = (participant.name or participant.id or "Adventurer") .. ": Charge Bond",
                                detail = "With " .. tostring(bondName),
                                target = participant,
                                campTalentStep = "war_stories_benefit",
                                warStoriesParticipant = participant,
                                warStoriesBenefit = "charge_bond",
                                warStoriesBondTargetId = targetId,
                                selectedParticipants = bondParticipants,
                                selectedBenefits = bondBenefits,
                            }
                        end
                    end
                end
            end
        end
        return targets
    end

    function screen:getBookwormTargetItems(pc)
        local targets = self:getInventoryTargetItems(pc, { id = "read_book" })
        for _, entry in ipairs(targets) do
            entry.actionData = {
                talentId = "bookworm",
                target = entry.target,
            }
        end
        return targets
    end

    function screen:getLoremasterTextItems(pc)
        local inv = pc and pc.inventory
        if not inv or not inv.getAllItems then
            return {}
        end

        local targets = {}
        for _, entry in ipairs(inv:getAllItems()) do
            local item = entry.item
            local props = item and item.properties or {}
            local hasText = item and (
                item.language ~= nil or item.script ~= nil or item.translatedText ~= nil or
                props.language ~= nil or props.script ~= nil or props.translatedText ~= nil or
                props.translation ~= nil or props.textKind ~= nil or props.ancientText == true
            )
            local longText = props.longText == true or props.requiresCityAction == true or
                item.type == "book" or props.book == true or props.readableBook == true
            if hasText and not longText then
                targets[#targets + 1] = {
                    label = item.name or item.id or "Text",
                    detail = props.language or item.language or props.script or item.script or entry.location,
                    target = item,
                    actionData = {
                        talentId = "loremaster",
                        target = item,
                    },
                }
            end
        end
        return targets
    end

    function screen:getChirurgeryTargetItems(pc)
        local targets = {}
        local completed = self.campController and self.campController.actionsCompleted or {}
        for _, other in ipairs(self.guild or {}) do
            if other and other.isPC == true and other.id ~= pc.id then
                local action = completed[other.id]
                local resting = action and (action.type == "rest" or action.id == "rest")
                local stressed = other.conditions and other.conditions.stressed == true
                local dead = other.conditions and other.conditions.dead == true
                if resting and not stressed and not dead then
                    targets[#targets + 1] = {
                        label = other.name or other.id or "Adventurer",
                        detail = "Resting guild-mate",
                        target = other,
                        actionData = {
                            talentId = "chirurgeon",
                            target = other,
                        },
                    }
                end
            end
        end
        return targets
    end

    function screen:getBeastMasterCompanionItems(pc)
        local targets = self:getCompanionTargetItems(pc)
        for _, entry in ipairs(targets) do
            entry.campTalentStep = "beast_master_companion"
        end
        return targets
    end

    function screen:getKnownCompanionCommandNames(companion)
        local names = {}
        local seen = {}
        for key, known in pairs(companion and (companion.knownCommands or companion.commands) or {}) do
            local name = animal_companions.getCommandEntryName(known, key)
            local normalized = animal_companions.normalizeCommandName(name)
            if normalized ~= "" and not seen[normalized] then
                seen[normalized] = true
                names[#names + 1] = animal_companions.getCommandDisplayName(normalized)
            end
        end
        return names, seen
    end

    function screen:canMarkFamiliar(pc, companion)
        local talent = self:getActorTalentRecord(pc, "beast_master")
        local mastered = type(talent) == "table" and talent.mastered == true or talent == true
        return mastered and (not pc.familiarCompanionId or pc.familiarCompanionId == companion.id)
            and not companion.isFamiliar and not companion.familiar
    end

    function screen:getBeastMasterCommandItems(pc, companion)
        local knownNames, known = self:getKnownCompanionCommandNames(companion)
        local commandLimit = animal_companions.getCommandLimit(companion)
        local atLimit = #knownNames >= commandLimit
        local canMarkFamiliar = self:canMarkFamiliar(pc, companion)
        local items = {}

        for _, commandId in ipairs(animal_companions.commandOrder or {}) do
            if not known[commandId] then
                local command = animal_companions.getCommand(commandId)
                local commandName = command and command.name or animal_companions.getCommandDisplayName(commandId)
                if not atLimit then
                    items[#items + 1] = {
                        label = commandName,
                        detail = "Teach command",
                        target = companion,
                        actionData = {
                            talentId = "beast_master",
                            companionId = companion.id,
                            command = commandName,
                        },
                    }
                elseif canMarkFamiliar then
                    items[#items + 1] = {
                        label = "Familiar: " .. commandName,
                        detail = "Mark familiar and teach command",
                        target = companion,
                        actionData = {
                            talentId = "beast_master",
                            companionId = companion.id,
                            command = commandName,
                            makeFamiliar = true,
                        },
                    }
                else
                    for _, knownName in ipairs(knownNames) do
                        items[#items + 1] = {
                            label = "Replace " .. knownName,
                            detail = "Teach " .. commandName,
                            target = companion,
                            actionData = {
                                talentId = "beast_master",
                                companionId = companion.id,
                                command = commandName,
                                replaceCommand = knownName,
                            },
                        }
                    end
                end
            end
        end

        return items
    end

    function screen:getHighChantCardItems(pc, selectedCards, selectedRecipients, discardPile)
        selectedCards = selectedCards or {}
        selectedRecipients = selectedRecipients or {}
        local deck = self.campController and self.campController.playerDeck
        discardPile = discardPile or (deck and deck.discard_pile) or {}
        local maxCards = math.max(0, tonumber(pc and pc.cups) or 0)
        if maxCards <= 0 then
            return {}
        end

        local targets = {}
        if #selectedCards > 0 then
            targets[#targets + 1] = {
                label = "Perform High Chant",
                detail = #selectedCards .. " inspiration card" .. (#selectedCards == 1 and "" or "s") .. " selected",
                actionData = {
                    talentId = "high_chant",
                    cards = self:copyArray(selectedCards),
                    recipients = self:copyArray(selectedRecipients),
                    discardPile = discardPile,
                },
            }
        end

        local availableRecipients = 0
        for _, other in ipairs(self.guild or {}) do
            if other and other.isPC == true and not other.inspirationCard then
                availableRecipients = availableRecipients + 1
            end
        end
        if availableRecipients <= 0 or #selectedCards >= maxCards or #selectedRecipients >= availableRecipients then
            return targets
        end

        local usedCards = {}
        for _, card in ipairs(selectedCards) do
            usedCards[card] = true
        end
        for i = 0, #discardPile - 1 do
            local card = discardPile[#discardPile - i]
            if card and not usedCards[card] then
                targets[#targets + 1] = {
                    label = card.name or "Discard Card",
                    detail = "Choose inspiration card",
                    target = card,
                    campTalentStep = "high_chant_card",
                    highChantCard = card,
                    discardPile = discardPile,
                    selectedCards = self:copyArray(selectedCards),
                    selectedRecipients = self:copyArray(selectedRecipients),
                }
            end
        end
        return targets
    end

    function screen:getHighChantRecipientItems(pc, card, discardPile, selectedCards, selectedRecipients)
        if not card then
            return {}
        end
        selectedCards = selectedCards or {}
        selectedRecipients = selectedRecipients or {}

        local usedRecipients = {}
        for _, recipient in ipairs(selectedRecipients) do
            usedRecipients[recipient] = true
        end

        local targets = {}
        for _, other in ipairs(self.guild or {}) do
            if other and other.isPC == true and not other.inspirationCard and not usedRecipients[other] then
                local cards = self:copyArray(selectedCards)
                local recipients = self:copyArray(selectedRecipients)
                cards[#cards + 1] = card
                recipients[#recipients + 1] = other
                targets[#targets + 1] = {
                    label = other.name or other.id or "Adventurer",
                    detail = "Receives " .. (card.name or "inspiration"),
                    target = other,
                    campTalentStep = "high_chant_recipient",
                    discardPile = discardPile,
                    selectedCards = cards,
                    selectedRecipients = recipients,
                }
            end
        end
        return targets
    end

    function screen:copyArray(items)
        local out = {}
        for i, item in ipairs(items or {}) do
            out[i] = item
        end
        return out
    end

    function screen:copyTable(items)
        local out = {}
        for key, value in pairs(items or {}) do
            if type(value) == "table" then
                local nested = {}
                for nestedKey, nestedValue in pairs(value) do
                    nested[nestedKey] = nestedValue
                end
                out[key] = nested
            else
                out[key] = value
            end
        end
        return out
    end

    function screen:getMakePactPactItems(pc, selectedPacts, selectedComponents)
        selectedPacts = selectedPacts or {}
        selectedComponents = selectedComponents or {}

        local backendOptions = nil
        if type(camp_actions.getMakePactOptions) == "function" then
            backendOptions = camp_actions.getMakePactOptions(pc, {
                pacts = selectedPacts,
                components = selectedComponents,
            }, self:getCampActionOptionContext())
        end
        local availableComponents = backendOptions and backendOptions.componentOptions or
            camp_actions.getAvailablePactComponents(pc)
        local usedPacts = {}
        for _, pactId in ipairs(selectedPacts) do
            usedPacts[pactId] = true
        end

        local targets = {}
        if #selectedPacts > 0 then
            targets[#targets + 1] = {
                label = #selectedPacts == 1 and "Make Pact" or "Make Pacts",
                detail = #selectedPacts .. " pact" .. (#selectedPacts == 1 and "" or "s") .. " selected",
                actionData = {
                    pacts = self:copyArray(selectedPacts),
                    components = self:copyArray(selectedComponents),
                },
            }
        end

        if #availableComponents <= #selectedComponents then
            return targets
        end

        local pactOptions = backendOptions and backendOptions.pactOptions or camp_actions.getPactOptions()
        for _, pact in ipairs(pactOptions) do
            if not usedPacts[pact.id] and not pact.disabled then
                targets[#targets + 1] = {
                    label = pact.name or pact.id,
                    detail = pact.obligation,
                    pactId = pact.id,
                    pactName = pact.name or pact.id,
                    makePactStep = "pact",
                    selectedPacts = self:copyArray(selectedPacts),
                    selectedComponents = self:copyArray(selectedComponents),
                }
            end
        end

        return targets
    end

    function screen:getMakePactComponentItems(pc, pactEntry)
        local usedComponents = {}
        for _, component in ipairs(pactEntry.selectedComponents or {}) do
            usedComponents[component] = true
            if component.id then
                usedComponents[component.id] = true
            end
        end

        local targets = {}
        local backendOptions = nil
        if type(camp_actions.getMakePactOptions) == "function" then
            local requestedPacts = self:copyArray(pactEntry.selectedPacts)
            if pactEntry.pactId then
                requestedPacts[#requestedPacts + 1] = pactEntry.pactId
            end
            backendOptions = camp_actions.getMakePactOptions(pc, {
                pacts = requestedPacts,
                components = pactEntry.selectedComponents,
            }, self:getCampActionOptionContext())
        end
        local componentOptions = backendOptions and backendOptions.componentOptions or
            camp_actions.getAvailablePactComponents(pc)
        for _, option in ipairs(componentOptions) do
            local component = option.item or self:getInventoryItemById(pc, option.id)
            if component and not usedComponents[component] and not usedComponents[component.id] and
               not option.disabled and not option.selected then
                local selectedPacts = self:copyArray(pactEntry.selectedPacts)
                local selectedComponents = self:copyArray(pactEntry.selectedComponents)
                selectedPacts[#selectedPacts + 1] = pactEntry.pactId
                selectedComponents[#selectedComponents + 1] = component

                local props = component.properties or {}
                local detail = "Charge for " .. (pactEntry.pactName or pactEntry.pactId or "pact")
                if option.location then
                    detail = detail .. " (" .. option.location .. ")"
                elseif props.componentFor then
                    detail = detail .. " (" .. props.componentFor .. ")"
                end

                targets[#targets + 1] = {
                    label = option.name or component.name or component.id or "Spell Component",
                    detail = detail,
                    target = component,
                    makePactStep = "component",
                    selectedPacts = selectedPacts,
                    selectedComponents = selectedComponents,
                }
            end
        end

        return targets
    end

    function screen:getUpdateMapsRouteItems(pc)
        if type(camp_actions.getUpdateMapsOptions) == "function" then
            local backendOptions = camp_actions.getUpdateMapsOptions(pc, self:getCampActionOptionContext())
            if backendOptions then
                local targets = {}
                for _, route in ipairs(backendOptions.routeOptions or {}) do
                    if not route.disabled then
                        targets[#targets + 1] = {
                            label = route.label or route.id or "Map Travelled Route",
                            detail = route.detail,
                            actionData = self:copyTable(route.actionDataPreview or {
                                rooms = route.roomIds,
                            }),
                            updateMapsRouteOption = route,
                        }
                    end
                end
                return targets
            end
        end

        local controller = self.campController or {}
        local watchManager = controller.watchManager or self.watchManager
        local roomManager = controller.roomManager or self.roomManager or (watchManager and watchManager.roomManager)
        local dungeon = controller.dungeon or self.dungeon or (watchManager and watchManager.dungeon)
        local roomIds = {}
        local labels = {}
        local seen = {}

        local function lookupRoom(roomId, room)
            if room then
                return room
            end
            if roomManager and roomManager.getRoom then
                room = roomManager:getRoom(roomId)
            end
            if not room and dungeon and dungeon.getRoom then
                room = dungeon:getRoom(roomId)
            end
            return room
        end

        local function addRoom(value)
            local room = nil
            local roomId = value
            if type(value) == "table" then
                room = value
                roomId = value.id or value.roomId or value.locationId
            end
            if not roomId or seen[roomId] then
                return
            end
            seen[roomId] = true
            roomIds[#roomIds + 1] = roomId
            room = lookupRoom(roomId, room)
            labels[#labels + 1] = (room and room.name) or tostring(roomId)
        end

        local function addRooms(items)
            if type(items) ~= "table" then
                return
            end
            for _, value in ipairs(items) do
                addRoom(value)
            end
        end

        addRooms(controller.traveledRooms or controller.roomsTraveled or
            controller.roomsSinceLastCamp or controller.rooms)
        if watchManager and watchManager.getRoomsTraveledSinceLastMap then
            addRooms(watchManager:getRoomsTraveledSinceLastMap())
        end
        addRoom(controller.currentRoom)
        addRoom(controller.currentRoomId or controller.roomId)
        if watchManager and watchManager.getCurrentRoom then
            addRoom(watchManager:getCurrentRoom())
        end

        if #roomIds == 0 then
            return {}
        end

        local detail = table.concat(labels, ", ")
        if #labels > 4 then
            local visible = {}
            for i = 1, 4 do
                visible[i] = labels[i]
            end
            detail = table.concat(visible, ", ") .. " +" .. tostring(#labels - 4) .. " more"
        end

        local actionData = {
            rooms = self:copyArray(roomIds),
        }
        if watchManager then
            actionData.watchManager = watchManager
        end
        if controller.guildMap or controller.mapState then
            actionData.guildMap = controller.guildMap or controller.mapState
        end

        return {
            {
                label = "Map Travelled Route",
                detail = detail,
                actionData = actionData,
            },
        }
    end

    function screen:getKnownInfiltrationLocationItems(talentId)
        local controller = self.campController or {}
        local targets = {}
        local seen = {}

        local function addLocation(roomId, room)
            roomId = roomId or (room and (room.id or room.roomId or room.locationId))
            if not roomId or seen[roomId] then
                return
            end
            seen[roomId] = true
            local label = (room and room.name) or tostring(roomId)
            local detail = room and room.level and ("Level " .. tostring(room.level)) or "Known location"
            local actionData = {
                roomId = roomId,
                known = true,
            }
            if room then
                actionData.location = room
            end
            if talentId then
                actionData.talentId = talentId
            end
            targets[#targets + 1] = {
                label = label,
                detail = detail,
                target = room,
                actionData = actionData,
            }
        end

        local roomManager = controller.roomManager or self.roomManager
        local currentRoom = controller.currentRoom
        local currentRoomId = controller.currentRoomId or controller.roomId or
            (currentRoom and (currentRoom.id or currentRoom.roomId or currentRoom.locationId))
        if not currentRoom and currentRoomId and roomManager and roomManager.getRoom then
            currentRoom = roomManager:getRoom(currentRoomId)
        end
        if currentRoomId or currentRoom then
            addLocation(currentRoomId, currentRoom)
        end

        local knownLocations = controller.knownLocations or controller.knownLocationIds
        if type(knownLocations) == "table" then
            for key, value in pairs(knownLocations) do
                local roomId = value
                if value == true then
                    roomId = key
                elseif type(value) == "table" then
                    roomId = value.id or value.roomId or value.locationId
                end
                local room = type(value) == "table" and value or
                    (roomManager and roomManager.getRoom and roomManager:getRoom(roomId))
                addLocation(roomId, room)
            end
        end

        if roomManager and type(roomManager.rooms) == "table" then
            for roomId, room in pairs(roomManager.rooms) do
                if room and room.known ~= false and
                   (room.known == true or room.visited == true or room.discovered == true) then
                    addLocation(roomId, room)
                end
            end
        end

        table.sort(targets, function(a, b)
            return (a.label or "") < (b.label or "")
        end)
        return targets
    end

    function screen:getLeechesTargetItems(item, option)
        if option then
            local targets = {}
            for _, targetOption in ipairs(option.targetOptions or {}) do
                if not targetOption.disabled then
                    local target = self:getGuildMemberById(targetOption.id) or targetOption.target
                    if target then
                        local afflictionCount = #(targetOption.afflictionOptions or {})
                        local detail = afflictionCount > 0 and
                            (afflictionCount .. " affliction" .. (afflictionCount == 1 and "" or "s")) or
                            "No affliction recorded"
                        targets[#targets + 1] = {
                            label = targetOption.name or target.name or target.id or "Adventurer",
                            detail = detail,
                            target = target,
                            campItemKind = "leeches_target",
                            leechItem = item,
                            leechOption = option,
                            leechTargetOption = targetOption,
                        }
                    end
                end
            end
            return targets
        end

        local targets = {}
        for _, pc in ipairs(self.guild or {}) do
            if pc and pc.isPC == true then
                local afflictionCount = 0
                for _ in pairs(pc.afflictions or {}) do
                    afflictionCount = afflictionCount + 1
                end
                local detail = afflictionCount > 0 and
                    (afflictionCount .. " affliction" .. (afflictionCount == 1 and "" or "s")) or
                    "No affliction recorded"
                targets[#targets + 1] = {
                    label = pc.name or pc.id or "Adventurer",
                    detail = detail,
                    target = pc,
                    campItemKind = "leeches_target",
                    leechItem = item,
                }
            end
        end
        return targets
    end

    function screen:getHuntedGamePreparationItems(pc, gameItem, option)
        if option then
            local choices = {}
            for _, prep in ipairs(option.preparationOptions or {}) do
                if not prep.disabled then
                    local actionData = self:copyTable(prep.actionDataPreview or {
                        itemId = gameItem and gameItem.id or option.id,
                        preparation = prep.preparation or prep.id,
                    })
                    actionData.itemId = actionData.itemId or (gameItem and gameItem.id) or option.id
                    actionData.preparation = actionData.preparation or prep.preparation or prep.id
                    local detail = prep.resultPreview or "Prepare hunted game"
                    if prep.mealCountPreview then
                        detail = tostring(prep.mealCountPreview) .. " meal" ..
                            (prep.mealCountPreview == 1 and "" or "s")
                    elseif prep.rationCountPreview then
                        detail = tostring(prep.rationCountPreview) .. " ration" ..
                            (prep.rationCountPreview == 1 and "" or "s")
                    end
                    choices[#choices + 1] = {
                        label = prep.name or self:formatTalentName(prep.preparation or prep.id),
                        detail = detail,
                        target = gameItem,
                        actionData = actionData,
                        campUseItemOption = option,
                        preparationOption = prep,
                    }
                end
            end
            return choices
        end

        local choices = {}
        local props = gameItem and gameItem.properties or {}
        local mealText = props.meals == "guild" and "guild meal stack" or "meal"
        if self:hasCookingGear(pc) then
            choices[#choices + 1] = {
                label = "Cook Game",
                detail = "Prepare as " .. mealText,
                target = gameItem,
                actionData = {
                    itemId = gameItem.id,
                    preparation = "cook",
                },
            }
        end
        if self:hasCampSalt(pc) then
            local rationText = props.meals == "guild" and "guild ration stack" or "ration"
            choices[#choices + 1] = {
                label = "Preserve with Salt",
                detail = "Prepare as " .. rationText,
                target = gameItem,
                actionData = {
                    itemId = gameItem.id,
                    preparation = "preserve",
                },
            }
        end
        return choices
    end

    function screen:hasRestedForRecovery(pc)
        local action = self.campController and self.campController.actionsCompleted and
            self.campController.actionsCompleted[pc and pc.id]
        if type(action) ~= "table" then
            return false
        end

        local function isRest(entry)
            if type(entry) ~= "table" then
                return false
            end
            local actionType = tostring(entry.type or entry.id or entry.action or ""):lower()
            actionType = actionType:gsub("[’']", ""):gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
            if actionType == "rest" or actionType == "rest_and_recover" then
                return true
            end
            for _, nested in ipairs(entry.actions or {}) do
                if isRest(nested) then
                    return true
                end
            end
            return false
        end

        return isRest(action)
    end

    function screen:needsRecoveryWoundHeal(pc)
        local conditions = pc and pc.conditions or {}
        return conditions.deaths_door == true or conditions.injured == true or
            conditions.staggered == true or (pc and tonumber(pc.woundedTalents or 0) or 0) > 0 or
            (pc and tonumber(pc.armorNotches or 0) or 0) > 0
    end

    function screen:needsRecoveryResolve(pc)
        if not pc then
            return false
        end
        if type(pc.regainResolve) ~= "function" then
            return false
        end
        if type(pc.resolve) == "table" then
            local current = tonumber(pc.resolve.current or pc.resolve.value)
            if current == nil then
                return false
            end
            local max = tonumber(pc.resolve.max or pc.resolve.maximum or pc.maxResolve or pc.resolveMax or 4) or 4
            return current < max
        end

        local current = tonumber(pc.resolve)
        if current == nil then
            current = tonumber(pc.currentResolve or pc.resolveCurrent)
        end
        if current == nil then
            return false
        end
        local max = tonumber(pc.maxResolve or pc.resolveMax or 4) or 4
        return current < max
    end

    function screen:recoveryPickerActionData(preview)
        local actionData = {}
        for key, value in pairs(preview or {}) do
            actionData[key] = value
        end
        return actionData
    end

    function screen:findRecoveryActorOption(options, pc)
        if not options or not pc then
            return nil
        end
        if options.selectedActor then
            return options.selectedActor
        end
        for _, actorOption in ipairs(options.actors or {}) do
            if actorOption.entity == pc or (pc.id and actorOption.entityId == pc.id) then
                return actorOption
            end
        end
        return nil
    end

    function screen:findRecoveryBondOption(actorOption, bondTargetId)
        if not actorOption then
            return nil
        end
        for _, bondOption in ipairs(actorOption.bondOptions or {}) do
            if bondOption.targetId == bondTargetId or bondOption.id == bondTargetId then
                return bondOption
            end
        end
        return nil
    end

    function screen:getRecoveryBondSpendItems(pc, bondTargetId)
        if not pc then
            return {}
        end

        if self.campController and self.campController.getRecoveryOptions then
            local options = self.campController:getRecoveryOptions({
                actorId = pc.id,
                bondTargetId = bondTargetId,
            })
            local actorOption = self:findRecoveryActorOption(options, pc)
            local bondOption = options and options.selectedBond or
                self:findRecoveryBondOption(actorOption, bondTargetId)
            if bondOption then
                local choices = {}
                for _, benefit in ipairs(bondOption.benefitOptions or {}) do
                    if not benefit.disabled then
                        local actionData = self:recoveryPickerActionData(benefit.actionDataPreview)
                        actionData.bondTargetId = actionData.bondTargetId or bondTargetId
                        actionData.spendType = actionData.spendType or benefit.spendType
                        choices[#choices + 1] = {
                            label = benefit.label or self:formatTalentName(benefit.spendType or "Recovery"),
                            detail = benefit.detail or benefit.resultPreview or "Recovery benefit",
                            actionData = actionData,
                            recoveryOption = benefit,
                        }
                    end
                end
                return choices
            end
        end

        if pc.conditions and pc.conditions.stressed then
            return {
                {
                    label = "Clear Stress",
                    detail = "Required before other Recovery",
                    actionData = {
                        bondTargetId = bondTargetId,
                        spendType = "clear_stress",
                    },
                },
            }
        end

        local choices = {}
        if self:needsRecoveryWoundHeal(pc) then
            choices[#choices + 1] = {
                label = "Heal Wound",
                detail = "Heal next wound, talent wound, or armor damage",
                actionData = {
                    bondTargetId = bondTargetId,
                    spendType = "heal_wound",
                },
            }
        end
        if self:needsRecoveryResolve(pc) then
            choices[#choices + 1] = {
                label = "Regain Resolve",
                detail = "Recover 1 Resolve",
                actionData = {
                    bondTargetId = bondTargetId,
                    spendType = "regain_resolve",
                },
            }
        end
        if self:hasRestedForRecovery(pc) then
            local afflictionNames = {}
            for afflictionName in pairs(pc.afflictions or {}) do
                afflictionNames[#afflictionNames + 1] = afflictionName
            end
            table.sort(afflictionNames, function(a, b)
                return tostring(a) < tostring(b)
            end)
            for _, afflictionName in ipairs(afflictionNames) do
                local affliction = pc.afflictions[afflictionName]
                local stage = type(affliction) == "table" and affliction.stage or nil
                choices[#choices + 1] = {
                    label = "Cure " .. self:formatTalentName(afflictionName),
                    detail = stage and ("Stage " .. tostring(stage)) or "Affliction",
                    actionData = {
                        bondTargetId = bondTargetId,
                        spendType = "cure_affliction",
                        affliction = afflictionName,
                    },
                }
            end
        end
        for _, companion in ipairs(pc.animalCompanions or {}) do
            local conditions = companion and companion.conditions or {}
            if conditions.injured == true then
                choices[#choices + 1] = {
                    label = "Heal " .. (companion.name or "Companion"),
                    detail = "Clear Injured from animal companion",
                    actionData = {
                        bondTargetId = bondTargetId,
                        spendType = "heal_companion",
                        companionId = companion.id,
                        companion = companion,
                    },
                }
            end
        end
        return choices
    end

    function screen:getRecoveryAfflictionNames(pc)
        local names = {}
        for afflictionName in pairs(pc and pc.afflictions or {}) do
            names[#names + 1] = afflictionName
        end
        table.sort(names, function(a, b)
            return tostring(a) < tostring(b)
        end)
        return names
    end

    function screen:getRecoveryAvailableXP(pc)
        if not pc then
            return 0
        end
        if pc.xp ~= nil then
            return math.max(0, math.floor(tonumber(pc.xp) or 0))
        end
        if pc.experience ~= nil then
            return math.max(0, math.floor(tonumber(pc.experience) or 0))
        end
        return 0
    end

    function screen:getRecoveryAidItems(pc)
        if not pc or (pc.conditions and pc.conditions.stressed) then
            return {}
        end

        if self.campController and self.campController.getRecoveryOptions then
            local options = self.campController:getRecoveryOptions({
                actorId = pc.id,
            })
            local actorOption = self:findRecoveryActorOption(options, pc)
            if actorOption then
                local choices = {}
                for _, aid in ipairs(actorOption.aidOptions or {}) do
                    if not aid.disabled then
                        local actionData = self:recoveryPickerActionData(aid.actionDataPreview)
                        actionData.spendType = actionData.spendType or aid.spendType
                        actionData.itemId = actionData.itemId or aid.itemId
                        actionData.affliction = actionData.affliction or aid.affliction
                        actionData.xp = actionData.xp or aid.xp
                        choices[#choices + 1] = {
                            label = aid.label or self:formatTalentName(aid.spendType or "Recovery Aid"),
                            detail = aid.detail or aid.resultPreview or "Recovery aid",
                            target = aid.item,
                            actionData = actionData,
                            recoveryOption = aid,
                        }
                    end
                end
                return choices
            end
        end

        if not self:hasRestedForRecovery(pc) then
            return {}
        end

        local afflictionNames = self:getRecoveryAfflictionNames(pc)
        if #afflictionNames == 0 then
            return {}
        end

        local choices = {}
        local inv = pc.inventory
        if inv and inv.getAllItems then
            for _, entry in ipairs(inv:getAllItems()) do
                local item = entry.item
                if self:isHealthfulRecoveryItem(item) then
                    local charges = math.max(1, tonumber((item.properties or {}).afflictionCureCharges) or 1)
                    for _, afflictionName in ipairs(afflictionNames) do
                        choices[#choices + 1] = {
                            label = "Use " .. (item.name or "Healthful Item"),
                            detail = self:formatTalentName(afflictionName) .. ", " .. tostring(charges) .. " charges",
                            target = item,
                            actionData = {
                                spendType = "healthful_item",
                                itemId = item.id,
                                affliction = afflictionName,
                            },
                        }
                    end
                end
            end
        end

        local availableXP = self:getRecoveryAvailableXP(pc)
        for _, afflictionName in ipairs(afflictionNames) do
            local state = nil
            if self.campController and self.campController.getAfflictionRecoveryState then
                state = self.campController:getAfflictionRecoveryState(pc, afflictionName)
            end
            local affliction = pc.afflictions and pc.afflictions[afflictionName]
            local stage = state and state.stage or (type(affliction) == "table" and affliction.stage) or 1
            local xpCost = state and state.xpStageCosts and state.xpStageCosts[stage]
            if xpCost == nil and type(affliction) == "table" then
                local stageRecovery = affliction.stageRecovery or affliction.recoveryByStage or {}
                local spec = stageRecovery[stage] or stageRecovery[tostring(stage)]
                if type(spec) == "table" then
                    xpCost = spec.xp or spec.experience or spec.xpCost
                end
            end
            xpCost = math.max(0, math.floor(tonumber(xpCost) or 0))
            if xpCost > 0 and availableXP >= xpCost then
                choices[#choices + 1] = {
                    label = "Spend " .. tostring(xpCost) .. " XP",
                    detail = "Cure " .. self:formatTalentName(afflictionName),
                    actionData = {
                        spendType = "xp_affliction",
                        affliction = afflictionName,
                        xp = xpCost,
                    },
                }
            end
        end

        return choices
    end

    function screen:enterRecoveryBondPicker(pc, bondTargetId, x, y)
        local choices = self:getRecoveryBondSpendItems(pc, bondTargetId)
        if #choices == 0 then
            print("[CampScreen] No Recovery benefits available")
            return false
        end

        self.targetPickerOpen = true
        self.targetPickerItems = choices
        self.targetPickerAction = {
            id = "recovery_bond",
            name = "Recovery Bond",
        }
        self.targetPickerActor = pc
        self.targetPickerX = x or self.actionMenuX
        self.targetPickerY = y or self.actionMenuY
        self.targetPickerBounds = nil
        self.actionMenuOpen = false
        return true
    end

    function screen:enterRecoveryAidPicker(pc, x, y)
        local choices = self:getRecoveryAidItems(pc)
        if #choices == 0 then
            print("[CampScreen] No non-Bond Recovery aids available")
            return false
        end

        self.targetPickerOpen = true
        self.targetPickerItems = choices
        self.targetPickerAction = {
            id = "recovery_aid",
            name = "Recovery Aid",
        }
        self.targetPickerActor = pc
        self.targetPickerX = x or self.actionMenuX
        self.targetPickerY = y or self.actionMenuY
        self.targetPickerBounds = nil
        self.actionMenuOpen = false
        return true
    end

    function screen:getLeechesAfflictionItems(item, target, targetOption, leechOption)
        if targetOption then
            local choices = {}
            for _, afflictionOption in ipairs(targetOption.afflictionOptions or {}) do
                if not afflictionOption.disabled then
                    local afflictionName = afflictionOption.id or afflictionOption.name
                    local detail = afflictionOption.stage and ("Stage " .. tostring(afflictionOption.stage)) or
                        "Affliction"
                    choices[#choices + 1] = {
                        label = afflictionOption.name or self:formatTalentName(afflictionName),
                        detail = detail,
                        target = target,
                        campItemKind = "leeches_affliction",
                        leechItem = item,
                        leechOption = leechOption,
                        leechTargetOption = targetOption,
                        afflictionName = afflictionName,
                    }
                end
            end
            return choices
        end

        local choices = {}
        for afflictionName, affliction in pairs(target and target.afflictions or {}) do
            local stage = type(affliction) == "table" and affliction.stage or nil
            local detail = stage and ("Stage " .. tostring(stage)) or "Affliction"
            choices[#choices + 1] = {
                label = self:formatTalentName(afflictionName),
                detail = detail,
                target = target,
                campItemKind = "leeches_affliction",
                leechItem = item,
                afflictionName = afflictionName,
            }
        end
        table.sort(choices, function(a, b)
            return (a.label or "") < (b.label or "")
        end)
        return choices
    end

    function screen:getLeechesDrawItems(item, target, afflictionName, option)
        if option then
            local choices = {}
            for _, draw in ipairs(option.drawOptions or {}) do
                if not draw.disabled then
                    local actionData = self:copyTable(draw.actionDataPreview or {
                        itemId = item and item.id or option.id,
                        card = { suit = draw.suit },
                    })
                    actionData.itemId = actionData.itemId or (item and item.id) or option.id
                    actionData.target = actionData.target or target
                    actionData.affliction = actionData.affliction or afflictionName
                    actionData.card = actionData.card or { suit = draw.suit }
                    actionData.card.suit = actionData.card.suit or draw.suit
                    actionData.card.name = actionData.card.name or
                        ("Leeches Draw: " .. tostring(draw.suitName or draw.suit or "Minor Arcana"))
                    actionData.card.value = actionData.card.value or 1
                    local charges = tonumber(draw.charges) or 0
                    choices[#choices + 1] = {
                        label = draw.suitName or tostring(draw.suit or "Minor Arcana"),
                        detail = charges > 0 and
                            (tostring(charges) .. " affliction cure charge" .. (charges == 1 and "" or "s")) or
                            "No leeching effect",
                        target = target,
                        actionData = actionData,
                        campUseItemOption = option,
                        leechDrawOption = draw,
                    }
                end
            end
            return choices
        end

        return {
            {
                label = "Cups",
                detail = "2 affliction cure charges",
                target = target,
                actionData = {
                    itemId = item.id,
                    target = target,
                    affliction = afflictionName,
                    card = { name = "Leeches Draw: Cups", value = 1, suit = constants.SUITS.CUPS },
                },
            },
            {
                label = "Wands",
                detail = "2 affliction cure charges",
                target = target,
                actionData = {
                    itemId = item.id,
                    target = target,
                    affliction = afflictionName,
                    card = { name = "Leeches Draw: Wands", value = 1, suit = constants.SUITS.WANDS },
                },
            },
            {
                label = "Swords",
                detail = "No leeching effect",
                target = target,
                actionData = {
                    itemId = item.id,
                    target = target,
                    affliction = afflictionName,
                    card = { name = "Leeches Draw: Swords", value = 1, suit = constants.SUITS.SWORDS },
                },
            },
            {
                label = "Pentacles",
                detail = "No leeching effect",
                target = target,
                actionData = {
                    itemId = item.id,
                    target = target,
                    affliction = afflictionName,
                    card = { name = "Leeches Draw: Pentacles", value = 1, suit = constants.SUITS.PENTACLES },
                },
            },
        }
    end

    function screen:getTinkersKitRepairItems(pc, kit, option)
        if option then
            local targets = {}
            for _, repairTarget in ipairs(option.repairTargets or {}) do
                if not repairTarget.disabled then
                    local item = self:getInventoryItemById(pc, repairTarget.id)
                    if item then
                        local notches = tonumber(repairTarget.notches or item.notches) or 0
                        targets[#targets + 1] = {
                            label = repairTarget.name or item.name or item.id or "Item",
                            detail = string.format("%s, %d notch%s", repairTarget.location or "carried",
                                notches, notches == 1 and "" or "es"),
                            target = item,
                            actionData = {
                                itemId = kit and kit.id or option.id,
                                target = item,
                            },
                            campUseItemOption = option,
                            repairOption = repairTarget,
                        }
                    end
                end
            end
            return targets
        end

        local targets = self:getInventoryTargetItems(pc, { id = "repair" })
        for _, entry in ipairs(targets) do
            entry.actionData = {
                itemId = kit.id,
                target = entry.target,
            }
        end
        return targets
    end

    function screen:getDevourLivingOutcomeItems()
        return {
            {
                label = "Success",
                detail = "Living vermin found",
                actionData = { outcome = "success" },
            },
            {
                label = "Great Success",
                detail = "Living vermin found cleanly",
                actionData = { outcome = "great_success" },
            },
            {
                label = "Failure",
                detail = "No living food found",
                actionData = { outcome = "failure" },
            },
            {
                label = "Great Failure",
                detail = "No food and consequences apply",
                actionData = { outcome = "great_failure" },
            },
        }
    end

    function screen:getScoutOutcomeItems(pc)
        if type(camp_actions.getScoutOutcomeOptions) == "function" then
            local backendOptions = camp_actions.getScoutOutcomeOptions(pc, self:getCampActionOptionContext())
            if backendOptions then
                local targets = {}
                for _, option in ipairs(backendOptions.outcomeOptions or {}) do
                    if not option.disabled then
                        targets[#targets + 1] = {
                            label = option.name or option.outcome,
                            detail = option.detail or option.resultPreview,
                            actionData = self:copyTable(option.actionDataPreview or {
                                outcome = option.outcome,
                            }),
                            scoutOutcomeOption = option,
                        }
                    end
                end
                return targets
            end
        end
        return {
            {
                label = "Success",
                detail = "Reveal one nearby hint",
                actionData = { outcome = "success" },
            },
            {
                label = "Great Success",
                detail = "Reveal a full adjacent-room report",
                actionData = { outcome = "great_success" },
            },
            {
                label = "Failure",
                detail = "Nothing learned",
                actionData = { outcome = "failure" },
            },
            {
                label = "Great Failure",
                detail = "Challenge triggered",
                actionData = { outcome = "great_failure" },
            },
        }
    end

    function screen:getHuntOutcomeItems(pc)
        if type(camp_actions.getHuntOutcomeOptions) == "function" then
            local backendOptions = camp_actions.getHuntOutcomeOptions(pc, self:getCampActionOptionContext())
            if backendOptions then
                local targets = {}
                for _, option in ipairs(backendOptions.outcomeOptions or {}) do
                    if not option.disabled then
                        targets[#targets + 1] = {
                            label = option.name or option.outcome,
                            detail = option.detail or option.resultPreview,
                            actionData = self:copyTable(option.actionDataPreview or {
                                outcome = option.outcome,
                            }),
                            huntOutcomeOption = option,
                        }
                    end
                end
                return targets
            end
        end
        return {
            {
                label = "Success",
                detail = "Fresh game found",
                actionData = { outcome = "success" },
            },
            {
                label = "Great Success",
                detail = "Large game found",
                actionData = { outcome = "great_success" },
            },
            {
                label = "Failure",
                detail = "No game found",
                actionData = { outcome = "failure" },
            },
            {
                label = "Great Failure",
                detail = "Challenge triggered",
                actionData = { outcome = "great_failure" },
            },
        }
    end

    function screen:getBrewAlchemyTargetItems(pc, selectedTransforms)
        selectedTransforms = selectedTransforms or {}
        local used = {}
        for _, transform in ipairs(selectedTransforms) do
            if transform.reagentId then
                used[transform.reagentId] = true
            end
        end

        local targets = {}
        if #selectedTransforms > 0 then
            targets[#targets + 1] = {
                label = #selectedTransforms == 1 and "Brew Substance" or "Brew Substances",
                detail = #selectedTransforms .. " reagent" .. (#selectedTransforms == 1 and "" or "s") .. " selected",
                actionData = {
                    transforms = self:copyArray(selectedTransforms),
                },
            }
        end

        if type(camp_actions.getBrewAlchemyOptions) == "function" then
            local backendOptions = camp_actions.getBrewAlchemyOptions(pc, {
                transforms = selectedTransforms,
            }, self:getCampActionOptionContext())
            if backendOptions then
                for _, reagent in ipairs(backendOptions.reagentOptions or {}) do
                    if not used[reagent.id] and not reagent.disabled then
                        local item = self:getInventoryItemById(pc, reagent.id)
                        if item then
                            for _, form in ipairs(reagent.formOptions or {}) do
                                if form.available and form.actionDataPreview then
                                    local outputName = form.outputPreview and form.outputPreview.name
                                    local label = outputName or string.format("%s as %s",
                                        reagent.name or "Reagent",
                                        form.form:sub(1, 1):upper() .. form.form:sub(2))
                                    local detail = reagent.location or reagent.source or "Bottled reagent"
                                    targets[#targets + 1] = {
                                        label = label,
                                        detail = detail,
                                        target = item,
                                        brewAlchemyStep = "form",
                                        selectedTransforms = self:copyArray(selectedTransforms),
                                        brewTransform = {
                                            reagentId = form.actionDataPreview.reagentId or reagent.id,
                                            form = form.actionDataPreview.form or form.form,
                                        },
                                        brewAlchemyOption = reagent,
                                        brewAlchemyFormOption = form,
                                    }
                                end
                            end
                        end
                    end
                end
                return targets
            end
        end

        for _, reagent in ipairs(camp_actions.getBrewableReagents(pc)) do
            if not used[reagent.itemId] then
                for _, form in ipairs(reagent.forms or {}) do
                    local label = string.format("%s as %s", reagent.name or "Reagent",
                        form:sub(1, 1):upper() .. form:sub(2))
                    local detail = reagent.location or reagent.source or "Bottled reagent"
                    targets[#targets + 1] = {
                        label = label,
                        detail = detail,
                        target = reagent.item,
                        brewAlchemyStep = "form",
                        selectedTransforms = self:copyArray(selectedTransforms),
                        brewTransform = {
                            reagentId = reagent.itemId,
                            form = form,
                        },
                    }
                end
            end
        end
        return targets
    end

    function screen:getBookQuestionItems(pc, book)
        if book == nil and type(pc) == "table" and (pc.properties or pc.templateId or pc.type == "book") then
            book = pc
            pc = nil
        end
        local backendOptions = pc and self:getReadBookOptionData(pc, {
            bookId = book and book.id or book,
        })
        if backendOptions and backendOptions.selectedBook then
            local targets = {}
            for _, question in ipairs(backendOptions.selectedBook.questionOptions or {}) do
                local actionData = self:copyTable(question.actionDataPreview or {})
                actionData.type = actionData.type or "read_book"
                actionData.target = book
                actionData.request = actionData.request or {
                    questionType = question.id,
                }
                targets[#targets + 1] = {
                    label = question.name or question.id,
                    detail = question.prompt,
                    target = book,
                    actionData = actionData,
                    readBookQuestionOption = question,
                }
            end
            return targets
        end

        local props = book and book.properties or {}
        local questions = {}

        if type(props.loreAnswers) == "table" then
            for _, question in ipairs(question_types.list()) do
                if props.loreAnswers[question.id] then
                    questions[#questions + 1] = question
                end
            end
        elseif props.loreSubjectId then
            local engine = bid_lore_engine.createBidLoreEngine({})
            questions = engine:getQuestionTypesForSubject(props.loreSubjectId)
        else
            questions = question_types.list()
        end

        local targets = {}
        for _, question in ipairs(questions) do
            targets[#targets + 1] = {
                label = question.name or question.id,
                detail = question.prompt,
                target = book,
                actionData = {
                    target = book,
                    request = {
                        questionType = question.id,
                    },
                },
            }
        end
        return targets
    end

    function screen:getCampActionTargetItems(pc, actionDef)
        if not pc or not actionDef then
            return {}
        end

        if actionDef.id == "brew_alchemy" then
            return self:getBrewAlchemyTargetItems(pc)
        elseif actionDef.id == "read_book" then
            return self:getReadBookTargetItems(pc)
        elseif actionDef.id == "use_item" then
            return self:getCampUseItemTargetItems(pc)
        elseif actionDef.id == "devour_living" then
            return self:getDevourLivingOutcomeItems()
        elseif actionDef.id == "scout" then
            return self:getScoutOutcomeItems(pc)
        elseif actionDef.id == "hunt" then
            return self:getHuntOutcomeItems(pc)
        elseif actionDef.id == "train" then
            return self:getTrainTrainerTargetItems(pc)
        elseif actionDef.id == "use_talent" then
            return self:getCampTalentTargetItems(pc)
        elseif actionDef.id == "make_pact" then
            return self:getMakePactPactItems(pc)
        elseif actionDef.id == "update_maps" then
            return self:getUpdateMapsRouteItems(pc)
        elseif actionDef.id == "infiltrate" then
            return self:getKnownInfiltrationLocationItems()
        elseif actionDef.id == "repair" then
            return self:getRepairTargetItems(pc)
        elseif actionDef.targetType == "pc" then
            local targets = {}
            for _, other in ipairs(self.guild or {}) do
                if other and other.isPC == true and other.id ~= pc.id then
                    targets[#targets + 1] = {
                        label = other.name or other.id or "Adventurer",
                        detail = "Guild-mate",
                        target = other,
                    }
                end
            end
            return targets
        elseif actionDef.targetType == "item" then
            return self:getInventoryTargetItems(pc, actionDef)
        elseif actionDef.targetType == "companion" then
            return self:getCompanionTargetItems(pc)
        end

        return {}
    end

    function screen:enterTargetPicker(pc, actionDef, x, y)
        local targets = self:getCampActionTargetItems(pc, actionDef)
        if #targets == 0 then
            print("[CampScreen] No valid targets for " .. (actionDef.name or actionDef.id or "action"))
            return false
        end

        self.targetPickerOpen = true
        self.targetPickerItems = targets
        self.targetPickerAction = actionDef
        self.targetPickerActor = pc
        self.targetPickerX = x or self.actionMenuX
        self.targetPickerY = y or self.actionMenuY
        self.targetPickerBounds = nil
        self.actionMenuOpen = false
        return true
    end

    function screen:submitCampActionWithTarget(entry)
        if not entry or not self.targetPickerActor or not self.targetPickerAction then
            return false
        end

        local pc = self.targetPickerActor
        local actionDef = self.targetPickerAction
        if actionDef.id == "break_bread" then
            local actionData = entry.actionData or {}
            local success, result = self.campController:consumeRation(pc, actionData)
            print("[CampScreen] Break bread for " .. (pc.name or pc.id or "adventurer") .. ": " ..
                (result or "?"))
            self:cancelTargetPicker(true)
            return success, result
        end

        if actionDef.id == "recovery_aid" then
            local actionData = entry.actionData or {}
            local success, result, detail
            if actionData.spendType == "healthful_item" then
                success, result, detail = self.campController:spendHealthfulItemForRecovery(
                    pc,
                    actionData.itemId,
                    actionData
                )
            elseif actionData.spendType == "xp_affliction" then
                success, result, detail = self.campController:spendXPForAfflictionRecovery(
                    pc,
                    actionData.affliction,
                    actionData
                )
            else
                success, result = false, "Unknown Recovery aid"
            end

            if success then
                print("[CampScreen] Recovery aid spent: " .. (result or actionData.spendType or "aid"))
            else
                print("[CampScreen] Recovery aid failed: " .. (result or "unknown"))
            end
            self:cancelTargetPicker(true)
            return success, result, detail
        end

        if actionDef.id == "recovery_bond" then
            local actionData = entry.actionData or {}
            local bondTargetId = actionData.bondTargetId or entry.bondTargetId
            local spendType = actionData.spendType or entry.spendType or "heal_wound"
            local success, result = self.campController:spendBondForRecovery(pc, bondTargetId, spendType, actionData)
            if success then
                print("[CampScreen] Bond spent: " .. (result or spendType))
            else
                print("[CampScreen] Bond spend failed: " .. (result or "unknown"))
            end
            self:cancelTargetPicker(true)
            return success, result
        end

        if actionDef.id == "use_item" and entry.campItemKind == "fresh_game" and not entry.actionData then
            local choices = self:getHuntedGamePreparationItems(pc, entry.target, entry.campUseItemOption)
            if #choices == 0 then
                print("[CampScreen] No valid hunted game preparations")
                self:cancelTargetPicker(true)
                return false
            end
            self.targetPickerItems = choices
            self.targetPickerBounds = nil
            return true, "use_item_hunted_game_picker_open"
        elseif actionDef.id == "use_item" and entry.campItemKind == "leeches" and not entry.actionData then
            local targets = self:getLeechesTargetItems(entry.target, entry.campUseItemOption)
            if #targets == 0 then
                print("[CampScreen] No valid leech targets")
                self:cancelTargetPicker(true)
                return false
            end
            self.targetPickerItems = targets
            self.targetPickerBounds = nil
            return true, "use_item_target_picker_open"
        elseif actionDef.id == "use_item" and entry.campItemKind == "leeches_target" and not entry.actionData then
            local choices = self:getLeechesAfflictionItems(entry.leechItem, entry.target,
                entry.leechTargetOption, entry.leechOption)
            if #choices == 0 then
                print("[CampScreen] No afflictions for leeches")
                self:cancelTargetPicker(true)
                return false
            end
            self.targetPickerItems = choices
            self.targetPickerBounds = nil
            return true, "use_item_leeches_affliction_picker_open"
        elseif actionDef.id == "use_item" and entry.campItemKind == "leeches_affliction" and not entry.actionData then
            local choices = self:getLeechesDrawItems(entry.leechItem, entry.target, entry.afflictionName,
                entry.leechOption)
            if #choices == 0 then
                print("[CampScreen] No leech draw choices")
                self:cancelTargetPicker(true)
                return false
            end
            self.targetPickerItems = choices
            self.targetPickerBounds = nil
            return true, "use_item_leeches_draw_picker_open"
        elseif actionDef.id == "use_item" and entry.campItemKind == "tinkers_kit" and not entry.actionData then
            local targets = self:getTinkersKitRepairItems(pc, entry.target, entry.campUseItemOption)
            if #targets == 0 then
                print("[CampScreen] No damaged items for Tinker's Kit")
                self:cancelTargetPicker(true)
                return false
            end
            self.targetPickerItems = targets
            self.targetPickerBounds = nil
            return true, "use_item_repair_picker_open"
        end

        if actionDef.id == "read_book" and entry.target and not entry.actionData then
            local questions = self:getBookQuestionItems(pc, entry.target)
            if #questions == 0 then
                print("[CampScreen] No available questions for " .. (entry.target.name or "book"))
                self:cancelTargetPicker(true)
                return false
            end

            self.targetPickerItems = questions
            self.targetPickerBounds = nil
            return true, "book_question_picker_open"
        end

        if actionDef.id == "train" and entry.trainingTalentId and not entry.actionData then
            local xpItems = self:getTrainXPAmountItems(pc, entry.trainer or entry.target, entry.trainingTalentId)
            if #xpItems == 0 then
                print("[CampScreen] No XP available for training")
                self:cancelTargetPicker(true)
                return false
            end

            self.targetPickerItems = xpItems
            self.targetPickerBounds = nil
            return true, "train_xp_picker_open"
        elseif actionDef.id == "train" and entry.target and not entry.actionData then
            local talents = self:getTrainableTalentItems(pc, entry.target)
            if #talents == 0 then
                print("[CampScreen] No trainable talents from " .. (entry.target.name or "trainer"))
                self:cancelTargetPicker(true)
                return false
            end

            self.targetPickerItems = talents
            self.targetPickerBounds = nil
            return true, "train_talent_picker_open"
        end

        if actionDef.id == "brew_alchemy" and entry.brewAlchemyStep == "form" then
            local transforms = self:copyArray(entry.selectedTransforms)
            transforms[#transforms + 1] = entry.brewTransform
            local choices = self:getBrewAlchemyTargetItems(pc, transforms)
            if #choices == 0 then
                print("[CampScreen] No valid alchemy brew choices")
                self:cancelTargetPicker(true)
                return false
            end

            self.targetPickerItems = choices
            self.targetPickerBounds = nil
            return true, "brew_alchemy_choice_picker_open"
        end

        if actionDef.id == "make_pact" and entry.makePactStep == "pact" then
            local components = self:getMakePactComponentItems(pc, entry)
            if #components == 0 then
                print("[CampScreen] No available spell components for Make a Pact")
                self:cancelTargetPicker(true)
                return false
            end

            self.targetPickerItems = components
            self.targetPickerBounds = nil
            return true, "make_pact_component_picker_open"
        elseif actionDef.id == "make_pact" and entry.makePactStep == "component" then
            local choices = self:getMakePactPactItems(pc, entry.selectedPacts, entry.selectedComponents)
            if #choices == 0 then
                print("[CampScreen] No valid pact choices")
                self:cancelTargetPicker(true)
                return false
            end

            self.targetPickerItems = choices
            self.targetPickerBounds = nil
            return true, "make_pact_choice_picker_open"
        end

        if actionDef.id == "use_talent" and entry.campTalentStep == "beast_master_companion" then
            local commands = self:getBeastMasterCommandItems(pc, entry.target)
            if #commands == 0 then
                print("[CampScreen] No Beast Master command choices")
                self:cancelTargetPicker(true)
                return false
            end

            self.targetPickerItems = commands
            self.targetPickerBounds = nil
            return true, "beast_master_command_picker_open"
        elseif actionDef.id == "use_talent" and entry.campTalentStep == "high_chant_card" then
            local recipients = self:getHighChantRecipientItems(pc, entry.highChantCard or entry.target,
                entry.discardPile, entry.selectedCards, entry.selectedRecipients)
            if #recipients == 0 then
                print("[CampScreen] No High Chant inspiration recipients")
                self:cancelTargetPicker(true)
                return false
            end

            self.targetPickerItems = recipients
            self.targetPickerBounds = nil
            return true, "high_chant_recipient_picker_open"
        elseif actionDef.id == "use_talent" and entry.campTalentStep == "high_chant_recipient" then
            local choices = self:getHighChantCardItems(pc, entry.selectedCards, entry.selectedRecipients, entry.discardPile)
            if #choices == 0 then
                print("[CampScreen] No High Chant card choices")
                self:cancelTargetPicker(true)
                return false
            end

            self.targetPickerItems = choices
            self.targetPickerBounds = nil
            return true, "high_chant_card_picker_open"
        elseif actionDef.id == "use_talent" and entry.campTalentStep == "war_stories_benefit" then
            local choices = self:getWarStoriesBenefitItems(pc, entry.selectedParticipants, entry.selectedBenefits)
            if #choices == 0 then
                print("[CampScreen] No War Stories benefit choices")
                self:cancelTargetPicker(true)
                return false
            end

            self.targetPickerItems = choices
            self.targetPickerBounds = nil
            return true, "war_stories_choice_picker_open"
        elseif actionDef.id == "use_talent" and entry.campTalentId and not entry.actionData then
            local talentId = entry.campTalentId
            local choices = nil
            if talentId == "beast_master" then
                choices = self:getBeastMasterCompanionItems(pc)
            elseif talentId == "bookworm" then
                choices = self:getBookwormTargetItems(pc)
            elseif talentId == "chirurgeon" then
                choices = self:getChirurgeryTargetItems(pc)
            elseif talentId == "high_chant" then
                choices = self:getHighChantCardItems(pc)
            elseif talentId == "loremaster" then
                choices = self:getLoremasterTextItems(pc)
            elseif talentId == "sneak" then
                choices = self:getKnownInfiltrationLocationItems("sneak")
            elseif talentId == "war_stories" then
                choices = self:getWarStoriesBenefitItems(pc)
            else
                entry.actionData = { talentId = talentId }
            end

            if choices then
                if #choices == 0 then
                    print("[CampScreen] No valid choices for " .. self:getCampTalentLabel(talentId))
                    self:cancelTargetPicker(true)
                    return false
                end
                self.targetPickerItems = choices
                self.targetPickerBounds = nil
                return true, "use_talent_choice_picker_open"
            end
        end

        local actionData = {
            type = actionDef.id,
        }
        if entry.actionData then
            for key, value in pairs(entry.actionData) do
                actionData[key] = value
            end
        else
            actionData.target = entry.target
        end
        if actionDef.useLaborUnending then
            actionData.useLaborUnending = true
        end

        local success, result = self.campController:submitAction(pc, actionData)
        if success and not self:isPromptOnlyCampActionResult(result) then
            print("[CampScreen] Action submitted: " .. actionDef.name)
            self:cancelTargetPicker(true)
        elseif success then
            print("[CampScreen] Action needs more input: " .. (result or "unknown"))
            self:cancelTargetPicker(true)
        else
            print("[CampScreen] Action failed: " .. (result or "unknown"))
            self:cancelTargetPicker(true)
        end
        return success, result
    end

    function screen:isPromptOnlyCampActionResult(result)
        return result == "alchemy_choices_required" or
            result == "book_question_required" or
            result == "devour_living_test_required"
    end

    function screen:selectTargetPickerItem(index)
        local entry = self.targetPickerItems[index]
        if not entry then
            return false
        end
        return self:submitCampActionWithTarget(entry)
    end

    function screen:handleTargetPickerClick(x, y)
        if not self.targetPickerBounds then
            return false
        end

        local menu = self.targetPickerBounds
        if x < menu.x or x > menu.x + menu.w or y < menu.y or y > menu.y + menu.h then
            return false
        end

        local itemIndex = math.floor((y - menu.y - menu.headerH) / menu.itemH) + 1
        if itemIndex >= 1 and itemIndex <= #self.targetPickerItems then
            self:selectTargetPickerItem(itemIndex)
            return true
        end

        return false
    end

    function screen:submitCampAction(pc, actionDef, x, y)
        if not pc or not actionDef then return end

        -- S9.1: Fellowship requires two-character selection mode
        if actionDef.id == "fellowship" then
            self:enterFellowshipMode(pc, actionDef.useLaborUnending == true)
            return
        end

        if actionDef.requiresTarget or actionDef.id == "brew_alchemy" or
           actionDef.id == "use_item" or actionDef.id == "devour_living" or
           actionDef.id == "scout" or actionDef.id == "hunt" or
           actionDef.id == "use_talent" or actionDef.id == "make_pact" or
           actionDef.id == "update_maps" or actionDef.id == "infiltrate" then
            if self:enterTargetPicker(pc, actionDef, x, y) then
                return
            end
            return
        end

        -- Build action data
        local actionData = {
            type = actionDef.id,
        }
        if actionDef.useLaborUnending then
            actionData.useLaborUnending = true
        end

        -- Submit to controller
        local success, result = self.campController:submitAction(pc, actionData)
        if success and not self:isPromptOnlyCampActionResult(result) then
            print("[CampScreen] Action submitted: " .. actionDef.name)
        elseif success then
            print("[CampScreen] Action needs more input: " .. (result or "unknown"))
        else
            print("[CampScreen] Action failed: " .. (result or "unknown"))
        end
    end

    --- Enter fellowship selection mode (S9.1)
    function screen:enterFellowshipMode(actorPC, useLaborUnending)
        -- Find actor's index
        local actorIndex = nil
        for i, pc in ipairs(self.guild) do
            if pc.id == actorPC.id then
                actorIndex = i
                break
            end
        end

        self.fellowshipMode = true
        self.fellowshipActor = actorPC
        self.fellowshipActorIndex = actorIndex
        self.fellowshipLaborUnending = useLaborUnending == true
        self.actionMenuOpen = false

        print("[CampScreen] Entering fellowship mode for " .. actorPC.name)
    end

    --- Handle clicks during fellowship mode (S9.1)
    function screen:handleFellowshipClick(x, y)
        -- Check if clicking on a character plate
        for i, plate in ipairs(self.characterPlates) do
            if x >= plate.x and x <= plate.x + M.LAYOUT.PLATE_WIDTH and
               y >= plate.y and y <= plate.y + plate:getHeight() then

                local targetPC = self.guild[i]
                if not targetPC then return end

                -- Clicking self cancels selection
                if self.fellowshipActor and targetPC.id == self.fellowshipActor.id then
                    self:cancelFellowshipMode()
                    return
                end

                -- Check if bond already charged
                if self.fellowshipActor and self.fellowshipActor.bonds and
                   self.fellowshipActor.bonds[targetPC.id] and
                   self.fellowshipActor.bonds[targetPC.id].charged then
                    print("[CampScreen] Bond with " .. targetPC.name .. " is already charged!")
                    return
                end

                -- Submit fellowship action with target
                local actionData = {
                    type = "fellowship",
                    target = targetPC,
                }
                if self.fellowshipLaborUnending then
                    actionData.useLaborUnending = true
                end

                local success, result = self.campController:submitAction(self.fellowshipActor, actionData)
                if success then
                    print("[CampScreen] Fellowship completed: " .. self.fellowshipActor.name ..
                          " and " .. targetPC.name)
                else
                    print("[CampScreen] Fellowship failed: " .. (result or "unknown"))
                end

                -- Exit fellowship mode
                self:cancelFellowshipMode()
                return
            end
        end

        -- Clicking elsewhere cancels
        self:cancelFellowshipMode()
    end

    function screen:handleBreakBreadClick(pcIndex)
        local pc = self.guild[pcIndex]
        if not pc then return end

        -- Check if already resolved
        if self.campController.rationsConsumed[pc.id] then
            return
        end

        if self:enterBreakBreadPicker(pc, x, y) then
            return
        end

        -- Try to consume ration
        local success, result = self.campController:consumeRation(pc)
        print("[CampScreen] Break bread for " .. pc.name .. ": " .. (result or "?"))
    end

    function screen:handleRecoveryClick(pcIndex, x, y)
        local pc = self.guild[pcIndex]
        if not pc then return end

        -- Check if clicked on a bond
        if self.hoveredBond and self.hoveredBond.pcIndex == pcIndex then
            local bond = self.hoveredBond.bond
            local targetId = self.hoveredBond.targetId

            if bond.charged then
                if pc.conditions and pc.conditions.stressed then
                    local success, result = self.campController:spendBondForRecovery(pc, targetId, "clear_stress")
                    print("[CampScreen] Bond spent: " .. (result or "failed"))
                    return success, result
                end

                return self:enterRecoveryBondPicker(pc, targetId, x, y)
            else
                print("[CampScreen] Bond is not charged")
                return false
            end
        end

        return self:enterRecoveryAidPicker(pc, x, y)
    end

    function screen:handleMeatgrinderClick()
        if not self.campController then return end

        local success, result = self.campController:resolveWatch()
        if success then
            self:showWatchResultPrompt(result)
            print("[CampScreen] Meatgrinder drawn - watch resolved")
        else
            print("[CampScreen] Watch failed: " .. (result or "unknown"))
        end
    end

    function screen:handleBreakCampClick()
        if not self.campController then return end

        -- advanceStep from TEARDOWN calls endCamp() which emits phase_changed
        local success, err = self.campController:advanceStep()
        if success then
            print("[CampScreen] Camp broken - returning to crawl")
        else
            print("[CampScreen] Break camp failed: " .. (err or "unknown"))
        end
    end

    function screen:handleAdvanceClick()
        if not self.campController then return end

        local success, err = self.campController:advanceStep()
        if success then
            print("[CampScreen] Advanced to next step")
        else
            print("[CampScreen] Cannot advance: " .. (err or "unknown"))
        end
    end

    return screen
end

return M
