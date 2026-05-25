-- command_board.lua
-- Categorized Command Board for Majesty
-- Ticket S6.2: Suit-grouped grid of actions
--
-- Displays a grid of actions organized by suit when a card is selected.
-- Enforces suit restrictions during Minor Action windows.

local events = require('logic.events')
local action_registry = require('data.action_registry')
local animal_companions = require('data.animal_companions')
local vigilance_triggers = require('data.vigilance_triggers')

local M = {}

--------------------------------------------------------------------------------
-- COLORS
--------------------------------------------------------------------------------
M.COLORS = {
    -- Background
    board_bg        = { 0.15, 0.12, 0.10, 0.95 },
    board_border    = { 0.40, 0.35, 0.30, 1.0 },

    -- Column headers
    header_swords   = { 0.65, 0.25, 0.25, 1.0 },
    header_pentacles= { 0.25, 0.55, 0.30, 1.0 },
    header_cups     = { 0.25, 0.40, 0.70, 1.0 },
    header_wands    = { 0.70, 0.50, 0.20, 1.0 },
    header_misc     = { 0.45, 0.42, 0.40, 1.0 },
    header_text     = { 0.95, 0.92, 0.88, 1.0 },

    -- Action buttons
    button_enabled  = { 0.30, 0.28, 0.25, 1.0 },
    button_disabled = { 0.20, 0.18, 0.16, 0.6 },
    button_hover    = { 0.40, 0.38, 0.35, 1.0 },
    button_selected = { 0.50, 0.45, 0.30, 1.0 },
    button_border   = { 0.50, 0.45, 0.40, 1.0 },
    button_text     = { 0.90, 0.88, 0.82, 1.0 },
    button_text_dis = { 0.50, 0.48, 0.45, 0.6 },

    -- Tooltip
    tooltip_bg      = { 0.10, 0.08, 0.06, 0.95 },
    tooltip_border  = { 0.60, 0.55, 0.45, 1.0 },
    tooltip_text    = { 0.95, 0.92, 0.85, 1.0 },
    tooltip_value   = { 0.90, 0.80, 0.40, 1.0 },
}

--------------------------------------------------------------------------------
-- LAYOUT CONSTANTS
--------------------------------------------------------------------------------
M.COLUMN_WIDTH = 130
M.HEADER_HEIGHT = 30
M.BUTTON_HEIGHT = 36
M.BUTTON_PADDING = 4
M.BOARD_PADDING = 12
M.TOOLTIP_WIDTH = 220
M.TOOLTIP_LINE_HEIGHT = 18

local UP_MY_SLEEVE_ITEM_OPTIONS = {
    {
        id = "lockpick",
        name = "Lockpicks",
        itemSpec = "lockpick",
        templateId = "lockpicks",
        description = "Declare a lockpick or small set of lockpicks.",
    },
    {
        id = "dagger",
        name = "Dagger",
        itemSpec = "dagger",
        templateId = "dagger",
        description = "Declare a common dagger.",
    },
    {
        id = "handkerchief",
        name = "Handkerchief",
        itemSpec = "handkerchief",
        templateId = "handkerchief",
        description = "Declare a handkerchief.",
    },
    {
        id = "empty_vial",
        name = "Empty Vial",
        itemSpec = "empty_vial",
        templateId = "hermetic_bottle",
        description = "Declare an empty vial or small bottle.",
    },
    {
        id = "length_of_wire",
        name = "Length of Wire",
        itemSpec = "length_of_wire",
        templateId = "length_of_wire",
        description = "Declare a useful length of wire.",
    },
}

local DWIMMERCRAFT_OPTIONS = {
    {
        id = "levitate",
        name = "Levitate Object",
        effect = "levitate",
        description = "Move a small one-hand object in your zone.",
        requiresObjectTarget = true,
    },
    {
        id = "showy_illusion",
        name = "Showy Illusion",
        effect = "showy_illusion",
        description = "Conjure a harmless, obviously magical display.",
    },
    {
        id = "simple_illusion",
        name = "Simple Illusion",
        effect = "simple_illusion",
        description = "Conjure a convincing one-hand illusion until interacted with.",
    },
    {
        id = "second_sight",
        name = "Second Sight",
        effect = "second_sight",
        description = "Spend Resolve to focus second sight for a watch.",
        requiresResolve = true,
    },
}

local RETREAT_OPTIONS = {
    {
        id = "retreat_no_pursuit",
        name = "No Pursuit",
        pursuit = "no_pursuit",
        enemyTiedToLair = true,
        enemyWillNotPursue = true,
        description = "The enemy is slow, awkward, bound, or unwilling to pursue.",
    },
    {
        id = "retreat_equivalent",
        name = "Equivalent",
        pursuit = "equivalent",
        description = "Resolve the highest/lowest Pentacles group test.",
    },
    {
        id = "retreat_clever",
        name = "Clever Escape",
        pursuit = "equivalent",
        needsText = true,
        description = "Describe a clever tactic that grants favor to one retreat test.",
    },
}

local function getResolveAmount(entity)
    if not entity then
        return 0
    end
    if type(entity.resolve) == "table" then
        return entity.resolve.current or entity.resolve.value or 0
    end
    if type(entity.resolve) == "number" then
        return entity.resolve
    end
    return tonumber(entity.currentResolve or entity.resolveCurrent or entity.resolve_current) or 0
end

local function getUpMySleeveUses(entity)
    return entity and (entity.upMySleeveUses or entity.upMySleeveCrawlUses or 0) or 0
end

--------------------------------------------------------------------------------
-- COMMAND BOARD FACTORY
--------------------------------------------------------------------------------

--- Create a new CommandBoard
-- @param config table: { eventBus, challengeController }
-- @return CommandBoard instance
function M.createCommandBoard(config)
    config = config or {}

    local board = {
        eventBus = config.eventBus or events.globalBus,
        challengeController = config.challengeController,

        -- State
        isVisible = false,
        selectedCard = nil,
        selectedEntity = nil,
        isPrimaryTurn = true,  -- vs Minor Window
        mode = "action",       -- "action" | picker submodes
        reaverBaseAction = nil,
        reaverOptions = nil,
        doomEyeBaseAction = nil,
        doomEyeOptions = nil,
        proudAndAncientBaseAction = nil,
        proudAndAncientOptions = nil,
        recoverBaseAction = nil,
        recoverEffectOptions = nil,
        roughhouseBaseAction = nil,
        roughhouseEffectOptions = nil,
        commandBaseAction = nil,
        commandOptions = nil,
        pendingCommandTextOption = nil,
        pendingCommandText = nil,
        aidBaseAction = nil,
        aidTriggerOptions = nil,
        pendingAidTriggerOption = nil,
        pendingAidText = nil,
        pullItemBaseAction = nil,
        pullItemOptions = nil,
        pullItemSelectedOption = nil,
        pullItemSwapOptions = nil,
        useItemBaseAction = nil,
        useItemOptions = nil,
        upMySleeveBaseAction = nil,
        upMySleeveOptions = nil,
        dwimmercraftBaseAction = nil,
        dwimmercraftOptions = nil,
        retreatBaseAction = nil,
        retreatOptions = nil,
        pendingRetreatOption = nil,
        pendingRetreatText = nil,
        counterSpellBaseAction = nil,
        counterSpellOptions = nil,
        vigilanceBaseAction = nil,
        vigilanceSelectedFollowUp = nil,
        vigilanceFollowUpOptions = nil,
        vigilanceTriggerOptions = nil,

        -- Layout
        x = 0,
        y = 0,
        width = 0,
        height = 0,

        -- Interaction
        hoveredAction = nil,
        buttons = {},  -- { action, x, y, width, height, enabled }

        -- Colors
        colors = M.COLORS,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function board:init()
        -- Listen for card selection
        self.eventBus:on("card_selected", function(data)
            if data.card and data.entity then
                self:show(data.card, data.entity, data.isPrimaryTurn)
            end
        end)

        -- Listen for card deselection
        self.eventBus:on("card_deselected", function()
            self:hide()
        end)

        -- Listen for challenge state changes
        self.eventBus:on("challenge_state_changed", function(data)
            if data.newState == "minor_window" then
                self.isPrimaryTurn = false
            elseif data.newState == "awaiting_action" then
                self.isPrimaryTurn = true
            end
        end)

        -- Listen for challenge end
        self.eventBus:on(events.EVENTS.CHALLENGE_END, function()
            self:hide()
        end)
    end

    ----------------------------------------------------------------------------
    -- VISIBILITY
    ----------------------------------------------------------------------------

    --- Show the command board for a selected card
    function board:show(card, entity, isPrimaryTurn)
        self.isVisible = true
        self.selectedCard = card
        self.selectedEntity = entity
        self.isPrimaryTurn = isPrimaryTurn ~= false  -- Default true
        self.mode = "action"
        self.reaverBaseAction = nil
        self.reaverOptions = nil
        self.doomEyeBaseAction = nil
        self.doomEyeOptions = nil
        self.proudAndAncientBaseAction = nil
        self.proudAndAncientOptions = nil
        self.recoverBaseAction = nil
        self.recoverEffectOptions = nil
        self.roughhouseBaseAction = nil
        self.roughhouseEffectOptions = nil
        self.commandBaseAction = nil
        self.commandOptions = nil
        self.pendingCommandTextOption = nil
        self.pendingCommandText = nil
        self.aidBaseAction = nil
        self.aidTriggerOptions = nil
        self.pendingAidTriggerOption = nil
        self.pendingAidText = nil
        self.pullItemBaseAction = nil
        self.pullItemOptions = nil
        self.pullItemSelectedOption = nil
        self.pullItemSwapOptions = nil
        self.useItemBaseAction = nil
        self.useItemOptions = nil
        self.upMySleeveBaseAction = nil
        self.upMySleeveOptions = nil
        self.dwimmercraftBaseAction = nil
        self.dwimmercraftOptions = nil
        self.retreatBaseAction = nil
        self.retreatOptions = nil
        self.pendingRetreatOption = nil
        self.pendingRetreatText = nil
        self.counterSpellBaseAction = nil
        self.counterSpellOptions = nil
        self.vigilanceBaseAction = nil
        self.vigilanceSelectedFollowUp = nil
        self.vigilanceFollowUpOptions = nil
        self.vigilanceTriggerOptions = nil

        -- Calculate position (center of screen area)
        local screenW, screenH = love.graphics.getDimensions()
        local numColumns = 5  -- Swords, Pentacles, Cups, Wands, Misc
        self.width = numColumns * M.COLUMN_WIDTH + M.BOARD_PADDING * 2 + (numColumns - 1) * M.BUTTON_PADDING
        self.height = self:calculateHeight()
        self.x = (screenW - self.width) / 2
        self.y = (screenH - self.height) / 2 - 50  -- Slightly above center

        -- Build button layout
        self:buildButtons()
    end

    function board:hide()
        self.isVisible = false
        self.selectedCard = nil
        self.selectedEntity = nil
        self.hoveredAction = nil
        self.hoveredButton = nil
        self.buttons = {}
        self.mode = "action"
        self.reaverBaseAction = nil
        self.reaverOptions = nil
        self.doomEyeBaseAction = nil
        self.doomEyeOptions = nil
        self.proudAndAncientBaseAction = nil
        self.proudAndAncientOptions = nil
        self.recoverBaseAction = nil
        self.recoverEffectOptions = nil
        self.roughhouseBaseAction = nil
        self.roughhouseEffectOptions = nil
        self.commandBaseAction = nil
        self.commandOptions = nil
        self.pendingCommandTextOption = nil
        self.pendingCommandText = nil
        self.aidBaseAction = nil
        self.aidTriggerOptions = nil
        self.pendingAidTriggerOption = nil
        self.pendingAidText = nil
        self.pullItemBaseAction = nil
        self.pullItemOptions = nil
        self.pullItemSelectedOption = nil
        self.pullItemSwapOptions = nil
        self.useItemBaseAction = nil
        self.useItemOptions = nil
        self.upMySleeveBaseAction = nil
        self.upMySleeveOptions = nil
        self.dwimmercraftBaseAction = nil
        self.dwimmercraftOptions = nil
        self.retreatBaseAction = nil
        self.retreatOptions = nil
        self.pendingRetreatOption = nil
        self.pendingRetreatText = nil
        self.counterSpellBaseAction = nil
        self.counterSpellOptions = nil
        self.vigilanceBaseAction = nil
        self.vigilanceSelectedFollowUp = nil
        self.vigilanceFollowUpOptions = nil
        self.vigilanceTriggerOptions = nil
    end

    local function entityHasUsableTalent(entity, talentId)
        if not entity then
            return false
        end
        if entity.canUseTalent then
            return entity:canUseTalent(talentId)
        end

        local talents = entity.talents or {}
        local talent = talents[talentId]
        if type(talent) == "table" then
            if talent.wounded then
                return false
            end
            if talent.mastered ~= nil then
                return talent.mastered == true
            end
            return true
        end
        return talent == true
    end

    --- Calculate total board height based on max column length
    function board:calculateHeight()
        local maxActions = 0
        local filter = { challengeOnly = true, commandBoardOnly = true }
        local suits = { action_registry.SUITS.SWORDS, action_registry.SUITS.PENTACLES,
                        action_registry.SUITS.CUPS, action_registry.SUITS.WANDS,
                        action_registry.SUITS.MISC }

        for _, suit in ipairs(suits) do
            local actions = action_registry.getActionsForSuit(suit, filter)
            maxActions = math.max(maxActions, #actions)
        end

        return M.BOARD_PADDING * 2 + M.HEADER_HEIGHT +
               maxActions * (M.BUTTON_HEIGHT + M.BUTTON_PADDING) + M.BUTTON_PADDING
    end

    --- Build the button layout
    function board:buildButtons()
        self.buttons = {}

        local suits = {
            { id = action_registry.SUITS.SWORDS, name = "Swords", color = self.colors.header_swords },
            { id = action_registry.SUITS.PENTACLES, name = "Pentacles", color = self.colors.header_pentacles },
            { id = action_registry.SUITS.CUPS, name = "Cups", color = self.colors.header_cups },
            { id = action_registry.SUITS.WANDS, name = "Wands", color = self.colors.header_wands },
            { id = action_registry.SUITS.MISC, name = "Misc", color = self.colors.header_misc },
        }

        local cardSuit = action_registry.cardSuitToActionSuit(self.selectedCard.suit)
        local filter = { challengeOnly = true, commandBoardOnly = true }

        for col, suitInfo in ipairs(suits) do
            local colX = self.x + M.BOARD_PADDING + (col - 1) * (M.COLUMN_WIDTH + M.BUTTON_PADDING)
            local actions = action_registry.getActionsForSuit(suitInfo.id, filter)

            -- Column is enabled if:
            -- 1. It's the primary turn (all columns enabled)
            -- 2. It's minor window AND this column matches the card's suit
            local columnEnabled = self.isPrimaryTurn or (suitInfo.id == cardSuit)

            -- Misc column is disabled during minor window
            if suitInfo.id == action_registry.SUITS.MISC and not self.isPrimaryTurn then
                columnEnabled = false
            end

            for i, action in ipairs(actions) do
                local btnY = self.y + M.BOARD_PADDING + M.HEADER_HEIGHT + M.BUTTON_PADDING +
                             (i - 1) * (M.BUTTON_HEIGHT + M.BUTTON_PADDING)

                local talentMinorEnabled = not self.isPrimaryTurn and
                    action_registry.canUseMinorActionWithCard(action, cardSuit, self.selectedEntity)
                local enabled = columnEnabled or talentMinorEnabled
                local disabledReason = nil

                if enabled then
                    local requirementsOk, requirementReason = action_registry.checkActionRequirements(
                        action,
                        self.selectedEntity
                    )
                    if not requirementsOk then
                        enabled = false
                        disabledReason = requirementReason or "Requirements not met"
                    end
                end

                if enabled and action.id == "up_my_sleeve" then
                    local canUseSleeve, sleeveReason = self:getUpMySleeveAvailability()
                    if not canUseSleeve then
                        enabled = false
                        disabledReason = sleeveReason
                    end
                end

                if enabled and action.id == "dwimmercraft" and
                   not entityHasUsableTalent(self.selectedEntity, "dwimmercraft") then
                    enabled = false
                    disabledReason = "Requires Dwimmercraft"
                end

                if enabled and action.id == "counter_spell" then
                    local canUseCounterSpell, counterSpellReason = self:getCounterSpellAvailability(action)
                    if not canUseCounterSpell then
                        enabled = false
                        disabledReason = counterSpellReason
                    end
                end

                -- S12.2: Ranged restriction when engaged
                if enabled and action.isRanged then
                    local entity = self.selectedEntity
                    if entity and entity.is_engaged then
                        enabled = false
                        disabledReason = "Cannot use ranged weapons while engaged"
                    end
                end

                self.buttons[#self.buttons + 1] = {
                    action = action,
                    x = colX,
                    y = btnY,
                    width = M.COLUMN_WIDTH,
                    height = M.BUTTON_HEIGHT,
                    enabled = enabled,
                    disabledReason = disabledReason,  -- S12.2: Tooltip for why disabled
                    suitColor = suitInfo.color,
                }
            end

            -- Store column header info
            self.buttons["header_" .. col] = {
                x = colX,
                y = self.y + M.BOARD_PADDING,
                width = M.COLUMN_WIDTH,
                height = M.HEADER_HEIGHT,
                name = suitInfo.name,
                color = suitInfo.color,
                enabled = columnEnabled,
            }
        end
    end

    function board:getVigilanceFollowUpOptions()
        if not self.selectedCard or not self.selectedEntity then
            return {}
        end

        local cardSuit = action_registry.cardSuitToActionSuit(self.selectedCard.suit)
        if cardSuit == action_registry.SUITS.MISC then
            return {}
        end

        local options = action_registry.getActionsForSuit(cardSuit, {
            challengeOnly = true,
            commandBoardOnly = true,
        })

        local filtered = {}
        for _, option in ipairs(options) do
            if option.id ~= "vigilance" then
                local requirementsOk = action_registry.checkActionRequirements(option, self.selectedEntity)
                if option.id == "counter_spell" and
                   not entityHasUsableTalent(self.selectedEntity, "counter_spell") then
                    requirementsOk = false
                end
                if requirementsOk then
                    filtered[#filtered + 1] = option
                end
            end
        end

        local trivialAction = action_registry.getAction("trivial_action")
        if trivialAction then
            local requirementsOk = action_registry.checkActionRequirements(trivialAction, self.selectedEntity)
            if requirementsOk then
                filtered[#filtered + 1] = trivialAction
            end
        end

        return filtered
    end

    function board:showVigilanceFollowUp(vigilanceAction)
        local options = self:getVigilanceFollowUpOptions()
        if #options == 0 then
            return false
        end

        self.vigilanceBaseAction = vigilanceAction
        self.vigilanceFollowUpOptions = options

        if #options == 1 then
            return self:showVigilanceTriggers(options[1])
        end

        self.mode = "vigilance_followup"
        self.vigilanceSelectedFollowUp = nil
        self.vigilanceTriggerOptions = nil
        self:buildVigilanceFollowUpButtons(options)
        return true
    end

    function board:getRoughhouseEffectOptions(roughhouseAction)
        local effects = roughhouseAction and roughhouseAction.roughhouseEffects or {}
        local names = {
            disarm = "Disarm",
            displace = "Displace",
            exhaust = "Exhaust",
            notch = "Notch",
            root = "Root",
            silence = "Silence",
            trip = "Trip",
        }
        local descriptions = {
            disarm = "Drop one held item.",
            displace = "Move the target to another zone.",
            exhaust = "Leave the target Exhausted.",
            notch = "Damage one held item.",
            root = "Prevent movement until Recover.",
            silence = "Stop the target from making vocal sounds.",
            trip = "Knock the target prone until Recover.",
        }

        local options = {}
        for _, effect in ipairs(effects) do
            if not roughhouseAction.fightDirtyEffects or not roughhouseAction.fightDirtyEffects[effect] or
               action_registry.canUseMinorActionWithCard(roughhouseAction, action_registry.SUITS.SWORDS, self.selectedEntity) then
                options[#options + 1] = {
                    id = "roughhouse_" .. effect,
                    name = names[effect] or effect,
                    description = descriptions[effect] or "Resolve this Roughhouse effect.",
                    roughhouseEffect = effect,
                }
            end
        end

        return options
    end

    function board:showRoughhouseEffects(roughhouseAction)
        local options = self:getRoughhouseEffectOptions(roughhouseAction)
        if #options == 0 then
            return false
        end

        self.mode = "roughhouse_effect"
        self.roughhouseBaseAction = roughhouseAction
        self.roughhouseEffectOptions = options
        self:buildRoughhouseEffectButtons(options)
        return true
    end

    function board:buildRoughhouseEffectButtons(options)
        self.buttons = {}

        local count = #options
        self.width = M.COLUMN_WIDTH + M.BOARD_PADDING * 2
        self.height = M.BOARD_PADDING * 2 + M.HEADER_HEIGHT +
            count * (M.BUTTON_HEIGHT + M.BUTTON_PADDING) + M.BUTTON_PADDING

        local screenW, screenH = love.graphics.getDimensions()
        self.x = (screenW - self.width) / 2
        self.y = (screenH - self.height) / 2 - 20

        self.buttons.header_roughhouse = {
            x = self.x + M.BOARD_PADDING,
            y = self.y + M.BOARD_PADDING,
            width = M.COLUMN_WIDTH,
            height = M.HEADER_HEIGHT,
            name = "Roughhouse",
            color = self.colors.header_pentacles,
            enabled = true,
        }

        local colX = self.x + M.BOARD_PADDING
        for i, option in ipairs(options) do
            local btnY = self.y + M.BOARD_PADDING + M.HEADER_HEIGHT + M.BUTTON_PADDING +
                (i - 1) * (M.BUTTON_HEIGHT + M.BUTTON_PADDING)
            self.buttons[#self.buttons + 1] = {
                action = option,
                x = colX,
                y = btnY,
                width = M.COLUMN_WIDTH,
                height = M.BUTTON_HEIGHT,
                enabled = true,
                disabledReason = nil,
                suitColor = self.colors.header_pentacles,
            }
        end
    end

    local function normalizeCommandName(commandName)
        commandName = tostring(commandName or ""):lower()
        commandName = commandName:gsub("[’']", "")
        commandName = commandName:gsub("%s+", "_")
        commandName = commandName:gsub("[^%w_]", "")

        if commandName == "sic_em" or commandName == "sicem" or commandName == "attack" then
            return "sic_em"
        elseif commandName == "get_help" or commandName == "gethelp" then
            return "get_help"
        elseif commandName == "do_a_trick" or commandName == "do_trick" or commandName == "trick" then
            return "do_a_trick"
        end

        return commandName
    end

    local function titleizeCommandName(commandName)
        local normalized = normalizeCommandName(commandName)
        local names = {
            sic_em = "Sic 'Em",
            get_help = "Get Help",
            do_a_trick = "Do a Trick",
            heel = "Heel",
            guard = "Guard",
            fetch = "Fetch",
            stay = "Stay",
            track = "Track",
            hunt = "Hunt",
        }
        return names[normalized] or tostring(commandName or "Command"):gsub("_", " ")
    end

    local function trimText(value)
        return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end

    local function shallowClone(value)
        if type(value) ~= "table" then
            return {}
        end
        local copy = {}
        for key, item in pairs(value) do
            copy[key] = item
        end
        return copy
    end

    function board:getUpMySleeveAvailability()
        if not entityHasUsableTalent(self.selectedEntity, "up_my_sleeve") then
            return false, "Requires Up My Sleeve"
        end
        if getUpMySleeveUses(self.selectedEntity) >= 2 then
            return false, "Both sleeves already used"
        end
        if getResolveAmount(self.selectedEntity) < 1 then
            return false, "Requires 1 Resolve"
        end
        return true, nil
    end

    function board:getUpMySleeveItemOptions(upMySleeveAction)
        if not upMySleeveAction or upMySleeveAction.id ~= "up_my_sleeve" then
            return {}
        end

        local canUse = self:getUpMySleeveAvailability()
        if not canUse then
            return {}
        end

        local options = {}
        for _, itemOption in ipairs(UP_MY_SLEEVE_ITEM_OPTIONS) do
            local option = shallowClone(upMySleeveAction)
            option.name = itemOption.name
            option.description = itemOption.description
            option.upMySleeveItem = itemOption.itemSpec
            option.upMySleeveItemSpec = itemOption.itemSpec
            option.itemSpec = itemOption.itemSpec
            option.itemTemplateId = itemOption.templateId
            option.upMySleeveOptionId = itemOption.id
            option.upMySleeveOption = itemOption
            options[#options + 1] = option
        end

        return options
    end

    function board:showUpMySleeveOptions(upMySleeveAction)
        local options = self:getUpMySleeveItemOptions(upMySleeveAction)
        if #options == 0 then
            return false
        end

        self.mode = "up_my_sleeve_option"
        self.upMySleeveBaseAction = upMySleeveAction
        self.upMySleeveOptions = options
        self:buildUpMySleeveButtons(options)
        return true
    end

    function board:buildUpMySleeveButtons(options)
        self.buttons = {}

        local count = #options
        self.width = M.COLUMN_WIDTH + M.BOARD_PADDING * 2
        self.height = M.BOARD_PADDING * 2 + M.HEADER_HEIGHT +
            count * (M.BUTTON_HEIGHT + M.BUTTON_PADDING) + M.BUTTON_PADDING

        local screenW, screenH = love.graphics.getDimensions()
        self.x = (screenW - self.width) / 2
        self.y = (screenH - self.height) / 2 - 20

        self.buttons.header_up_my_sleeve = {
            x = self.x + M.BOARD_PADDING,
            y = self.y + M.BOARD_PADDING,
            width = M.COLUMN_WIDTH,
            height = M.HEADER_HEIGHT,
            name = "Up My Sleeve",
            color = self.colors.header_misc,
            enabled = true,
        }

        local colX = self.x + M.BOARD_PADDING
        for i, option in ipairs(options) do
            local btnY = self.y + M.BOARD_PADDING + M.HEADER_HEIGHT + M.BUTTON_PADDING +
                (i - 1) * (M.BUTTON_HEIGHT + M.BUTTON_PADDING)
            self.buttons[#self.buttons + 1] = {
                action = option,
                x = colX,
                y = btnY,
                width = M.COLUMN_WIDTH,
                height = M.BUTTON_HEIGHT,
                enabled = true,
                disabledReason = nil,
                suitColor = self.colors.header_misc,
            }
        end
    end

    function board:getDwimmercraftOptions(dwimmercraftAction)
        if not dwimmercraftAction or dwimmercraftAction.id ~= "dwimmercraft" then
            return {}
        end
        if not entityHasUsableTalent(self.selectedEntity, "dwimmercraft") then
            return {}
        end

        local options = {}
        for _, effectOption in ipairs(DWIMMERCRAFT_OPTIONS) do
            local option = shallowClone(dwimmercraftAction)
            option.name = effectOption.name
            option.description = effectOption.description
            option.dwimmercraftEffect = effectOption.effect
            option.mode = effectOption.effect
            option.effect = effectOption.effect
            option.intent = effectOption.effect
            option.requiresObjectTarget = effectOption.requiresObjectTarget == true
            option.targetType = option.requiresObjectTarget and "object" or option.targetType
            option.dwimmercraftOption = effectOption
            if effectOption.requiresResolve and getResolveAmount(self.selectedEntity) < 1 then
                option.enabled = false
                option.disabledReason = "Requires 1 Resolve"
            end
            options[#options + 1] = option
        end

        return options
    end

    function board:showDwimmercraftOptions(dwimmercraftAction)
        local options = self:getDwimmercraftOptions(dwimmercraftAction)
        if #options == 0 then
            return false
        end

        self.mode = "dwimmercraft_option"
        self.dwimmercraftBaseAction = dwimmercraftAction
        self.dwimmercraftOptions = options
        self:buildDwimmercraftButtons(options)
        return true
    end

    function board:buildDwimmercraftButtons(options)
        self.buttons = {}

        local count = #options
        self.width = M.COLUMN_WIDTH + M.BOARD_PADDING * 2
        self.height = M.BOARD_PADDING * 2 + M.HEADER_HEIGHT +
            count * (M.BUTTON_HEIGHT + M.BUTTON_PADDING) + M.BUTTON_PADDING

        local screenW, screenH = love.graphics.getDimensions()
        self.x = (screenW - self.width) / 2
        self.y = (screenH - self.height) / 2 - 20

        self.buttons.header_dwimmercraft = {
            x = self.x + M.BOARD_PADDING,
            y = self.y + M.BOARD_PADDING,
            width = M.COLUMN_WIDTH,
            height = M.HEADER_HEIGHT,
            name = "Dwimmercraft",
            color = self.colors.header_misc,
            enabled = true,
        }

        local colX = self.x + M.BOARD_PADDING
        for i, option in ipairs(options) do
            local btnY = self.y + M.BOARD_PADDING + M.HEADER_HEIGHT + M.BUTTON_PADDING +
                (i - 1) * (M.BUTTON_HEIGHT + M.BUTTON_PADDING)
            self.buttons[#self.buttons + 1] = {
                action = option,
                x = colX,
                y = btnY,
                width = M.COLUMN_WIDTH,
                height = M.BUTTON_HEIGHT,
                enabled = option.enabled ~= false,
                disabledReason = option.disabledReason,
                suitColor = self.colors.header_misc,
            }
        end
    end

    function board:getRetreatOptions(fleeAction)
        if not fleeAction or fleeAction.id ~= "flee" then
            return {}
        end

        local options = {}
        for _, retreatOption in ipairs(RETREAT_OPTIONS) do
            local option = shallowClone(fleeAction)
            option.name = "Flee: " .. retreatOption.name
            option.label = option.name
            option.description = retreatOption.description
            option.retreatOption = retreatOption
            option.retreatOptionId = retreatOption.id
            option.pursuit = retreatOption.pursuit
            option.enemyTiedToLair = retreatOption.enemyTiedToLair
            option.enemyWillNotPursue = retreatOption.enemyWillNotPursue
            option.retreatNeedsText = retreatOption.needsText == true
            options[#options + 1] = option
        end
        return options
    end

    function board:showRetreatOptions(fleeAction)
        local options = self:getRetreatOptions(fleeAction)
        if #options == 0 then
            return false
        end

        self.mode = "retreat_option"
        self.retreatBaseAction = fleeAction
        self.retreatOptions = options
        self:buildRetreatButtons(options)
        return true
    end

    function board:buildRetreatButtons(options)
        self.buttons = {}

        local count = #options
        self.width = M.COLUMN_WIDTH + M.BOARD_PADDING * 2
        self.height = M.BOARD_PADDING * 2 + M.HEADER_HEIGHT +
            count * (M.BUTTON_HEIGHT + M.BUTTON_PADDING) + M.BUTTON_PADDING

        local screenW, screenH = love.graphics.getDimensions()
        self.x = (screenW - self.width) / 2
        self.y = (screenH - self.height) / 2 - 20

        self.buttons.header_retreat = {
            x = self.x + M.BOARD_PADDING,
            y = self.y + M.BOARD_PADDING,
            width = M.COLUMN_WIDTH,
            height = M.HEADER_HEIGHT,
            name = "Retreat",
            color = self.colors.header_misc,
            enabled = true,
        }

        local colX = self.x + M.BOARD_PADDING
        for i, option in ipairs(options) do
            local btnY = self.y + M.BOARD_PADDING + M.HEADER_HEIGHT + M.BUTTON_PADDING +
                (i - 1) * (M.BUTTON_HEIGHT + M.BUTTON_PADDING)
            self.buttons[#self.buttons + 1] = {
                action = option,
                x = colX,
                y = btnY,
                width = M.COLUMN_WIDTH,
                height = M.BUTTON_HEIGHT,
                enabled = true,
                disabledReason = nil,
                suitColor = self.colors.header_misc,
            }
        end
    end

    function board:showRetreatTextEntry(option)
        if not option then
            return false
        end

        self.mode = "retreat_text"
        self.pendingRetreatOption = option
        self.pendingRetreatText = ""
        self.buttons = {}
        self.hoveredAction = nil
        self.hoveredButton = nil

        local screenW, screenH = love.graphics.getDimensions()
        self.width = M.COLUMN_WIDTH * 2 + M.BOARD_PADDING * 2
        self.height = M.BOARD_PADDING * 2 + M.HEADER_HEIGHT + M.BUTTON_HEIGHT + M.BUTTON_PADDING * 3
        self.x = (screenW - self.width) / 2
        self.y = (screenH - self.height) / 2 - 20
        return true
    end

    function board:returnToRetreatOptionMode()
        self.mode = "retreat_option"
        self.pendingRetreatOption = nil
        self.pendingRetreatText = nil
        self.hoveredAction = nil
        self.hoveredButton = nil
        self:buildRetreatButtons(self.retreatOptions or {})
    end

    function board:submitRetreatTextEntry()
        local text = trimText(self.pendingRetreatText)
        if text == "" or not self.pendingRetreatOption then
            return false
        end

        local option = shallowClone(self.pendingRetreatOption)
        option.cleverTactics = {
            {
                description = text,
                actorId = self.selectedEntity and (self.selectedEntity.id or self.selectedEntity.name) or nil,
            },
        }
        option.retreatTactics = option.cleverTactics
        self:emitActionSelected(option, nil)
        self:hide()
        return true
    end

    local function addUniqueEntity(entities, seen, entity)
        if not entity then
            return
        end
        local key = entity.id or entity
        if seen[key] then
            return
        end
        seen[key] = true
        entities[#entities + 1] = entity
    end

    local function getActiveSpellName(spellEntry)
        return spellEntry and (spellEntry.name or spellEntry.spellName or spellEntry.spellId or spellEntry.id) or
            "Ongoing Spell"
    end

    function board:getCounterSpellSpellSources()
        local entities = {}
        local seen = {}
        local controller = self.challengeController

        addUniqueEntity(entities, seen, self.selectedEntity)
        if controller then
            addUniqueEntity(entities, seen, controller.activeEntity)
            if controller.getActiveEntity then
                addUniqueEntity(entities, seen, controller:getActiveEntity())
            end
            for _, entity in ipairs(controller.allCombatants or {}) do
                addUniqueEntity(entities, seen, entity)
            end
            for _, entity in ipairs(controller.guild or {}) do
                addUniqueEntity(entities, seen, entity)
            end
            for _, entity in ipairs(controller.pcs or {}) do
                addUniqueEntity(entities, seen, entity)
            end
            for _, entity in ipairs(controller.npcs or {}) do
                addUniqueEntity(entities, seen, entity)
            end
        end

        return entities
    end

    function board:getCounterSpellOngoingOptions(counterSpellAction)
        if not counterSpellAction or counterSpellAction.id ~= "counter_spell" then
            return {}
        end
        if not entityHasUsableTalent(self.selectedEntity, "counter_spell") then
            return {}
        end

        local options = {}
        for _, caster in ipairs(self:getCounterSpellSpellSources()) do
            for _, spellEntry in pairs(caster.activeSpells or {}) do
                if spellEntry and spellEntry.ended ~= true and spellEntry.active ~= false then
                    local spellName = getActiveSpellName(spellEntry)
                    local casterName = caster.name or caster.id or "caster"
                    local option = shallowClone(counterSpellAction)
                    option.name = "Negate " .. tostring(spellName)
                    option.description = "Spend Resolve to end " .. tostring(spellName) ..
                        " from " .. tostring(casterName) .. "."
                    option.mode = "ongoing"
                    option.counterSpellMode = "ongoing"
                    option.activeSpell = spellEntry
                    option.spellEntry = spellEntry
                    option.ongoingSpell = spellEntry
                    option.spellCaster = caster
                    option.targetCaster = caster
                    option.caster = caster
                    option.counterSpellOption = {
                        spell = spellEntry,
                        caster = caster,
                    }
                    options[#options + 1] = option
                end
            end
        end

        return options
    end

    function board:getCounterSpellAvailability(counterSpellAction)
        if not entityHasUsableTalent(self.selectedEntity, "counter_spell") then
            return false, "Requires Counter-spell"
        end
        if getResolveAmount(self.selectedEntity) < 1 then
            return false, "Requires 1 Resolve"
        end
        if #self:getCounterSpellOngoingOptions(counterSpellAction) == 0 then
            return false, "No ongoing spells"
        end
        return true, nil
    end

    function board:showCounterSpellOptions(counterSpellAction)
        local options = self:getCounterSpellOngoingOptions(counterSpellAction)
        if #options == 0 then
            return false
        end

        self.mode = "counter_spell_option"
        self.counterSpellBaseAction = counterSpellAction
        self.counterSpellOptions = options
        self:buildCounterSpellButtons(options)
        return true
    end

    function board:buildCounterSpellButtons(options)
        self.buttons = {}

        local count = #options
        self.width = M.COLUMN_WIDTH + M.BOARD_PADDING * 2
        self.height = M.BOARD_PADDING * 2 + M.HEADER_HEIGHT +
            count * (M.BUTTON_HEIGHT + M.BUTTON_PADDING) + M.BUTTON_PADDING

        local screenW, screenH = love.graphics.getDimensions()
        self.x = (screenW - self.width) / 2
        self.y = (screenH - self.height) / 2 - 20

        self.buttons.header_counter_spell = {
            x = self.x + M.BOARD_PADDING,
            y = self.y + M.BOARD_PADDING,
            width = M.COLUMN_WIDTH,
            height = M.HEADER_HEIGHT,
            name = "Counter-spell",
            color = self.colors.header_wands,
            enabled = true,
        }

        local colX = self.x + M.BOARD_PADDING
        for i, option in ipairs(options) do
            local btnY = self.y + M.BOARD_PADDING + M.HEADER_HEIGHT + M.BUTTON_PADDING +
                (i - 1) * (M.BUTTON_HEIGHT + M.BUTTON_PADDING)
            self.buttons[#self.buttons + 1] = {
                action = option,
                x = colX,
                y = btnY,
                width = M.COLUMN_WIDTH,
                height = M.BUTTON_HEIGHT,
                enabled = true,
                disabledReason = nil,
                suitColor = self.colors.header_wands,
            }
        end
    end

    function board:getReaverAttackOptions(attackAction)
        if not attackAction or attackAction.id ~= "melee" then
            return {}
        end
        if not entityHasUsableTalent(self.selectedEntity, "reaver") then
            return {}
        end

        local normal = shallowClone(attackAction)
        normal.name = attackAction.name or "Attack"
        normal.description = attackAction.description or "Resolve a melee Attack."

        local reaver = shallowClone(attackAction)
        reaver.name = "Reaver Charge"
        reaver.description = "Move one adjacent zone toward the target before resolving this melee Attack."
        reaver.useReaver = true
        reaver.reaverCharge = true

        return { normal, reaver }
    end

    function board:showReaverAttackOptions(attackAction)
        local options = self:getReaverAttackOptions(attackAction)
        if #options == 0 then
            return false
        end

        self.mode = "reaver_option"
        self.reaverBaseAction = attackAction
        self.reaverOptions = options
        self:buildReaverAttackButtons(options)
        return true
    end

    function board:buildReaverAttackButtons(options)
        self.buttons = {}

        local count = #options
        self.width = M.COLUMN_WIDTH + M.BOARD_PADDING * 2
        self.height = M.BOARD_PADDING * 2 + M.HEADER_HEIGHT +
            count * (M.BUTTON_HEIGHT + M.BUTTON_PADDING) + M.BUTTON_PADDING

        local screenW, screenH = love.graphics.getDimensions()
        self.x = (screenW - self.width) / 2
        self.y = (screenH - self.height) / 2 - 20

        self.buttons.header_reaver = {
            x = self.x + M.BOARD_PADDING,
            y = self.y + M.BOARD_PADDING,
            width = M.COLUMN_WIDTH,
            height = M.HEADER_HEIGHT,
            name = "Melee Attack",
            color = self.colors.header_swords,
            enabled = true,
        }

        local colX = self.x + M.BOARD_PADDING
        for i, option in ipairs(options) do
            local btnY = self.y + M.BOARD_PADDING + M.HEADER_HEIGHT + M.BUTTON_PADDING +
                (i - 1) * (M.BUTTON_HEIGHT + M.BUTTON_PADDING)
            self.buttons[#self.buttons + 1] = {
                action = option,
                x = colX,
                y = btnY,
                width = M.COLUMN_WIDTH,
                height = M.BUTTON_HEIGHT,
                enabled = true,
                disabledReason = nil,
                suitColor = self.colors.header_swords,
            }
        end
    end

    function board:getDoomEyeAttackOptions(attackAction)
        if not attackAction or attackAction.id ~= "missile" then
            return {}
        end
        if action_registry.cardSuitToActionSuit(self.selectedCard and self.selectedCard.suit) ~=
           action_registry.SUITS.SWORDS then
            return {}
        end
        if not entityHasUsableTalent(self.selectedEntity, "doom_eye") then
            return {}
        end

        local normal = shallowClone(attackAction)
        normal.name = attackAction.name or "Attack"
        normal.description = attackAction.description or "Resolve a ranged Attack."

        local doomEye = shallowClone(attackAction)
        doomEye.name = "Doom Eye Shot"
        doomEye.description = "Elect Doom Eye to ignore the target's Initiative with this missile Attack."
        doomEye.useDoomEye = true
        doomEye.doomEye = true
        doomEye.perfectShot = true

        return { normal, doomEye }
    end

    function board:showDoomEyeAttackOptions(attackAction)
        local options = self:getDoomEyeAttackOptions(attackAction)
        if #options == 0 then
            return false
        end

        self.mode = "doom_eye_option"
        self.doomEyeBaseAction = attackAction
        self.doomEyeOptions = options
        self:buildDoomEyeAttackButtons(options)
        return true
    end

    function board:buildDoomEyeAttackButtons(options)
        self.buttons = {}

        local count = #options
        self.width = M.COLUMN_WIDTH + M.BOARD_PADDING * 2
        self.height = M.BOARD_PADDING * 2 + M.HEADER_HEIGHT +
            count * (M.BUTTON_HEIGHT + M.BUTTON_PADDING) + M.BUTTON_PADDING

        local screenW, screenH = love.graphics.getDimensions()
        self.x = (screenW - self.width) / 2
        self.y = (screenH - self.height) / 2 - 20

        self.buttons.header_doom_eye = {
            x = self.x + M.BOARD_PADDING,
            y = self.y + M.BOARD_PADDING,
            width = M.COLUMN_WIDTH,
            height = M.HEADER_HEIGHT,
            name = "Ranged Attack",
            color = self.colors.header_swords,
            enabled = true,
        }

        local colX = self.x + M.BOARD_PADDING
        for i, option in ipairs(options) do
            local btnY = self.y + M.BOARD_PADDING + M.HEADER_HEIGHT + M.BUTTON_PADDING +
                (i - 1) * (M.BUTTON_HEIGHT + M.BUTTON_PADDING)
            self.buttons[#self.buttons + 1] = {
                action = option,
                x = colX,
                y = btnY,
                width = M.COLUMN_WIDTH,
                height = M.BUTTON_HEIGHT,
                enabled = true,
                disabledReason = nil,
                suitColor = self.colors.header_swords,
            }
        end
    end

    function board:getProudAndAncientIncantationOptions(incantationAction)
        if not incantationAction or incantationAction.id ~= "speak_incantation" then
            return {}
        end
        if not entityHasUsableTalent(self.selectedEntity, "proud_and_ancient") then
            return {}
        end

        local normal = shallowClone(incantationAction)
        normal.name = incantationAction.name or "Speak Incantation"
        normal.description = incantationAction.description or "Speak an incantation."

        local warCry = shallowClone(incantationAction)
        warCry.name = "House Motto"
        warCry.description = "Spend Resolve to cry the house motto and grant favor to same-house allies who can hear."
        warCry.proudAndAncientWarCry = true
        warCry.proudAndAncient = true
        warCry.warCry = "proud_and_ancient"
        warCry.motto = self.selectedEntity and (self.selectedEntity.motto or self.selectedEntity.houseMotto) or nil

        return { normal, warCry }
    end

    function board:showProudAndAncientIncantationOptions(incantationAction)
        local options = self:getProudAndAncientIncantationOptions(incantationAction)
        if #options == 0 then
            return false
        end

        self.mode = "proud_and_ancient_option"
        self.proudAndAncientBaseAction = incantationAction
        self.proudAndAncientOptions = options
        self:buildProudAndAncientIncantationButtons(options)
        return true
    end

    function board:buildProudAndAncientIncantationButtons(options)
        self.buttons = {}

        local count = #options
        self.width = M.COLUMN_WIDTH + M.BOARD_PADDING * 2
        self.height = M.BOARD_PADDING * 2 + M.HEADER_HEIGHT +
            count * (M.BUTTON_HEIGHT + M.BUTTON_PADDING) + M.BUTTON_PADDING

        local screenW, screenH = love.graphics.getDimensions()
        self.x = (screenW - self.width) / 2
        self.y = (screenH - self.height) / 2 - 20

        self.buttons.header_proud_and_ancient = {
            x = self.x + M.BOARD_PADDING,
            y = self.y + M.BOARD_PADDING,
            width = M.COLUMN_WIDTH,
            height = M.HEADER_HEIGHT,
            name = "Incantation",
            color = self.colors.header_wands,
            enabled = true,
        }

        local colX = self.x + M.BOARD_PADDING
        for i, option in ipairs(options) do
            local btnY = self.y + M.BOARD_PADDING + M.HEADER_HEIGHT + M.BUTTON_PADDING +
                (i - 1) * (M.BUTTON_HEIGHT + M.BUTTON_PADDING)
            self.buttons[#self.buttons + 1] = {
                action = option,
                x = colX,
                y = btnY,
                width = M.COLUMN_WIDTH,
                height = M.BUTTON_HEIGHT,
                enabled = true,
                disabledReason = nil,
                suitColor = self.colors.header_wands,
            }
        end
    end

    function board:getRecoverEffectOptions(recoverAction)
        if not recoverAction or recoverAction.id ~= "recover" then
            return {}
        end

        local entity = self.selectedEntity
        local conditions = entity and entity.conditions or {}
        local options = {}
        local added = {}

        local function add(effectId, name, description)
            if added[effectId] then
                return
            end
            added[effectId] = true
            local option = shallowClone(recoverAction)
            option.name = name
            option.description = description or ("Recover from " .. name .. ".")
            option.recoverEffect = effectId
            options[#options + 1] = option
        end

        if conditions.rooted then
            add("rooted", "Recover Root", "Clear Rooted if the effect is recoverable.")
        end
        if conditions.prone then
            add("prone", "Recover Prone", "Stand up from Prone.")
        end
        if conditions.blind or conditions.blinded then
            add("blind", "Recover Blind", "Clear Blind.")
        end
        if conditions.deaf or conditions.deafened then
            add("deaf", "Recover Deaf", "Clear Deafened.")
        end
        if conditions.silenced then
            add("silenced", "Recover Silence", "Clear Silenced.")
        end
        if conditions.exhausted or entity and entity.exhausted then
            add("exhausted", "Recover Exhaust", "Clear Exhausted.")
        end
        if conditions.burning or conditions.onFire or entity and entity.onFire then
            add("burning", "Recover Burning", "Put out Burning clothes and gear.")
        end
        if conditions.webbed or (entity and entity.webbedLimbs and entity.webbedLimbs > 0) then
            add("webbed", "Recover Webbed", "Free yourself from webs.")
        end
        if conditions.disarmed then
            add("disarmed", "Recover Weapon", "Retrieve a dropped weapon.")
        elseif entity and entity.droppedItems and #entity.droppedItems > 0 then
            add("dropped_item", "Recover Item", "Pick up a dropped item.")
        end

        return options
    end

    function board:showRecoverEffects(recoverAction)
        local options = self:getRecoverEffectOptions(recoverAction)
        if #options == 0 then
            return false
        end

        self.mode = "recover_effect"
        self.recoverBaseAction = recoverAction
        self.recoverEffectOptions = options
        self:buildRecoverEffectButtons(options)
        return true
    end

    function board:buildRecoverEffectButtons(options)
        self.buttons = {}

        local count = #options
        self.width = M.COLUMN_WIDTH + M.BOARD_PADDING * 2
        self.height = M.BOARD_PADDING * 2 + M.HEADER_HEIGHT +
            count * (M.BUTTON_HEIGHT + M.BUTTON_PADDING) + M.BUTTON_PADDING

        local screenW, screenH = love.graphics.getDimensions()
        self.x = (screenW - self.width) / 2
        self.y = (screenH - self.height) / 2 - 20

        self.buttons.header_recover = {
            x = self.x + M.BOARD_PADDING,
            y = self.y + M.BOARD_PADDING,
            width = M.COLUMN_WIDTH,
            height = M.HEADER_HEIGHT,
            name = "Recover",
            color = self.colors.header_wands,
            enabled = true,
        }

        local colX = self.x + M.BOARD_PADDING
        for i, option in ipairs(options) do
            local btnY = self.y + M.BOARD_PADDING + M.HEADER_HEIGHT + M.BUTTON_PADDING +
                (i - 1) * (M.BUTTON_HEIGHT + M.BUTTON_PADDING)
            self.buttons[#self.buttons + 1] = {
                action = option,
                x = colX,
                y = btnY,
                width = M.COLUMN_WIDTH,
                height = M.BUTTON_HEIGHT,
                enabled = true,
                disabledReason = nil,
                suitColor = self.colors.header_wands,
            }
        end
    end

    local function getCommandFreeformText(option)
        local commandData = option and option.commandData
        if option then
            local optionText = option.commandObjective or option.objective or option.commandText or
                option.instruction or option.order or option.task or option.trick or option.trickName
            if optionText then
                return optionText
            end
        end
        if commandData then
            return commandData.commandObjective or commandData.objective or commandData.commandText or
                commandData.instruction or commandData.order or commandData.task or commandData.trick or
                commandData.trickName
        end
        return nil
    end

    local function commandWantsFreeformText(option)
        if getCommandFreeformText(option) then
            return false
        end

        local commandName = option and option.commandName
        if commandName == "do_a_trick" then
            return true
        end

        local commandData = option and option.commandData or {}
        return option and (option.freeformObjective or option.requiresObjectiveText or
            commandData.freeformObjective or commandData.requiresObjectiveText)
    end

    local function applyCommandFreeformText(option, text)
        if not option then
            return nil
        end

        local value = trimText(text)
        option.commandObjective = value
        option.objective = value
        option.commandData = option.commandData or {}
        option.commandData.commandObjective = value
        if option.commandName == "do_a_trick" then
            option.trick = value
            option.trickName = value
            option.commandData.trick = option.commandData.trick or value
            option.commandData.trickName = option.commandData.trickName or value
        end
        return option
    end

    function board:getCommandCompanions()
        local entity = self.selectedEntity
        if not entity then
            return {}
        end

        local companions = {}
        local seen = {}
        local function add(companion, key)
            if type(companion) ~= "table" then
                return
            end

            local id = companion.id or key or tostring(#companions + 1)
            if seen[id] then
                return
            end
            seen[id] = true
            companions[#companions + 1] = {
                id = id,
                companion = companion,
            }
        end

        add(entity.companion, entity.companion and entity.companion.id)
        for _, collection in ipairs({ entity.companions, entity.animalCompanions }) do
            if type(collection) == "table" then
                for key, companion in pairs(collection) do
                    add(companion, key)
                end
            end
        end

        return companions
    end

    function board:getKnownCommands(companion)
        local commands = companion and (companion.knownCommands or companion.commands)
        local options = {}

        if type(commands) == "table" then
            for key, value in pairs(commands) do
                local rawName = nil
                rawName = animal_companions.getCommandEntryName(value, key)

                if rawName then
                    options[#options + 1] = {
                        commandName = rawName,
                        commandData = type(value) == "table" and value or nil,
                    }
                end
            end
        elseif commands == nil then
            options[#options + 1] = {
                commandName = "Command",
            }
        end

        table.sort(options, function(a, b)
            return titleizeCommandName(a.commandName) < titleizeCommandName(b.commandName)
        end)

        return options
    end

    function board:getCommandOptions()
        local options = {}
        for _, entry in ipairs(self:getCommandCompanions()) do
            local companion = entry.companion
            for _, knownCommand in ipairs(self:getKnownCommands(companion)) do
                local commandName = knownCommand.commandName
                local commandData = knownCommand.commandData or {}
                local normalizedCommand = normalizeCommandName(commandName)
                options[#options + 1] = {
                    id = "command_" .. entry.id .. "_" .. normalizedCommand,
                    name = titleizeCommandName(commandName),
                    description = "Command " .. (companion.name or "companion") .. ".",
                    commandName = normalizedCommand,
                    commandDisplayName = titleizeCommandName(commandName),
                    commandData = commandData,
                    trick = commandData.trick or commandData.trickName,
                    trickName = commandData.trickName or commandData.trick,
                    companionId = entry.id,
                    companion = companion,
                }
            end
        end

        return options
    end

    function board:showCommandOptions(commandAction)
        local options = self:getCommandOptions()
        if #options == 0 then
            return false
        end

        self.mode = "command_option"
        self.commandBaseAction = commandAction
        self.commandOptions = options
        self:buildCommandOptionButtons(options)
        return true
    end

    function board:showCommandTextEntry(option)
        if not option then
            return false
        end

        self.mode = "command_text"
        self.pendingCommandTextOption = option
        self.pendingCommandText = ""
        self.buttons = {}
        self.hoveredAction = nil
        self.hoveredButton = nil

        local screenW, screenH = love.graphics.getDimensions()
        self.width = M.COLUMN_WIDTH * 2 + M.BOARD_PADDING * 2
        self.height = M.BOARD_PADDING * 2 + M.HEADER_HEIGHT + M.BUTTON_HEIGHT + M.BUTTON_PADDING * 3
        self.x = (screenW - self.width) / 2
        self.y = (screenH - self.height) / 2 - 20
        return true
    end

    function board:returnToCommandOptionMode()
        self.mode = "command_option"
        self.pendingCommandTextOption = nil
        self.pendingCommandText = nil
        self.hoveredAction = nil
        self.hoveredButton = nil
        self:buildCommandOptionButtons(self.commandOptions or {})
    end

    function board:submitCommandTextEntry()
        local text = trimText(self.pendingCommandText)
        if text == "" or not self.commandBaseAction or not self.pendingCommandTextOption then
            return false
        end

        local option = applyCommandFreeformText(self.pendingCommandTextOption, text)
        self:emitActionSelected(
            self.commandBaseAction,
            nil,
            nil,
            nil,
            nil,
            nil,
            option.commandName,
            option.companionId,
            option
        )
        self:hide()
        return true
    end

    function board:getCommandOptionDisabledReason(option)
        local companion = option and option.companion
        if not companion then
            return "No companion"
        end

        local conditions = companion.conditions or {}
        if conditions.dead then
            return "Companion is dead"
        end
        if companion.weak or conditions.weak then
            return "Companion is weak"
        end
        if companion.starving or conditions.starving then
            return "Companion is starving"
        end

        return nil
    end

    function board:buildCommandOptionButtons(options)
        self.buttons = {}

        local count = #options
        self.width = M.COLUMN_WIDTH + M.BOARD_PADDING * 2
        self.height = M.BOARD_PADDING * 2 + M.HEADER_HEIGHT +
            count * (M.BUTTON_HEIGHT + M.BUTTON_PADDING) + M.BUTTON_PADDING

        local screenW, screenH = love.graphics.getDimensions()
        self.x = (screenW - self.width) / 2
        self.y = (screenH - self.height) / 2 - 20

        self.buttons.header_command = {
            x = self.x + M.BOARD_PADDING,
            y = self.y + M.BOARD_PADDING,
            width = M.COLUMN_WIDTH,
            height = M.HEADER_HEIGHT,
            name = "Command",
            color = self.colors.header_cups,
            enabled = true,
        }

        local colX = self.x + M.BOARD_PADDING
        for i, option in ipairs(options) do
            local btnY = self.y + M.BOARD_PADDING + M.HEADER_HEIGHT + M.BUTTON_PADDING +
                (i - 1) * (M.BUTTON_HEIGHT + M.BUTTON_PADDING)
            local disabledReason = self:getCommandOptionDisabledReason(option)
            self.buttons[#self.buttons + 1] = {
                action = option,
                x = colX,
                y = btnY,
                width = M.COLUMN_WIDTH,
                height = M.BUTTON_HEIGHT,
                enabled = disabledReason == nil,
                disabledReason = disabledReason,
                suitColor = self.colors.header_cups,
            }
        end
    end

    function board:getPullItemSourceLocation(action)
        if action and action.id == "pull_item_belt" then
            return "belt"
        end
        return "pack"
    end

    function board:getInventoryItems(location)
        local inv = self.selectedEntity and self.selectedEntity.inventory
        if not inv then
            return {}
        end
        if inv.getItems then
            return inv:getItems(location) or {}
        end
        return inv[location] or {}
    end

    function board:getUseItemOptions()
        local options = {}
        for i, item in ipairs(self:getInventoryItems("hands")) do
            if item and not item.destroyed then
                local itemId = item.id or tostring(i)
                options[#options + 1] = {
                    id = "use_hands_" .. tostring(itemId),
                    name = item.name or item.templateId or ("Held Item " .. tostring(i)),
                    description = "Use this held item.",
                    useItem = item,
                    useItemId = item.id,
                }
            end
        end
        return options
    end

    function board:showUseItemOptions(useAction)
        local options = self:getUseItemOptions()
        if #options == 0 then
            return false
        end

        self.mode = "use_item"
        self.useItemBaseAction = useAction
        self.useItemOptions = options
        self:buildUseItemButtons(options)
        return true
    end

    function board:buildUseItemButtons(options)
        self.buttons = {}

        local count = #options
        self.width = M.COLUMN_WIDTH + M.BOARD_PADDING * 2
        self.height = M.BOARD_PADDING * 2 + M.HEADER_HEIGHT +
            count * (M.BUTTON_HEIGHT + M.BUTTON_PADDING) + M.BUTTON_PADDING

        local screenW, screenH = love.graphics.getDimensions()
        self.x = (screenW - self.width) / 2
        self.y = (screenH - self.height) / 2 - 20

        self.buttons.header_use_item = {
            x = self.x + M.BOARD_PADDING,
            y = self.y + M.BOARD_PADDING,
            width = M.COLUMN_WIDTH,
            height = M.HEADER_HEIGHT,
            name = "Use Item",
            color = self.colors.header_cups,
            enabled = true,
        }

        local colX = self.x + M.BOARD_PADDING
        for i, option in ipairs(options) do
            local btnY = self.y + M.BOARD_PADDING + M.HEADER_HEIGHT + M.BUTTON_PADDING +
                (i - 1) * (M.BUTTON_HEIGHT + M.BUTTON_PADDING)
            self.buttons[#self.buttons + 1] = {
                action = option,
                x = colX,
                y = btnY,
                width = M.COLUMN_WIDTH,
                height = M.BUTTON_HEIGHT,
                enabled = true,
                disabledReason = nil,
                suitColor = self.colors.header_cups,
            }
        end
    end

    function board:getItemSlotSize(item)
        if not item then
            return 0
        end
        return item.stackable and 1 or (item.size or 1)
    end

    function board:getAvailableInventorySlots(location)
        local inv = self.selectedEntity and self.selectedEntity.inventory
        if inv and inv.availableSlots then
            return inv:availableSlots(location)
        end
        return 0
    end

    function board:getPullItemOptions(pullAction)
        local location = self:getPullItemSourceLocation(pullAction)
        local options = {}
        for i, item in ipairs(self:getInventoryItems(location)) do
            if item and not item.destroyed then
                local itemId = item.id or tostring(i)
                options[#options + 1] = {
                    id = "pull_" .. location .. "_" .. tostring(itemId),
                    name = item.name or item.templateId or ("Item " .. tostring(i)),
                    description = "Pull this item from " .. location .. ".",
                    pullItem = item,
                    pullItemId = item.id,
                    pullSourceLocation = location,
                }
            end
        end

        return options
    end

    function board:showPullItemOptions(pullAction)
        local options = self:getPullItemOptions(pullAction)
        if #options == 0 then
            return false
        end

        self.mode = "pull_item"
        self.pullItemBaseAction = pullAction
        self.pullItemOptions = options
        self:buildPullItemButtons(options, self:getPullItemSourceLocation(pullAction))
        return true
    end

    function board:buildPullItemButtons(options, sourceLocation)
        self.buttons = {}

        local count = #options
        self.width = M.COLUMN_WIDTH + M.BOARD_PADDING * 2
        self.height = M.BOARD_PADDING * 2 + M.HEADER_HEIGHT +
            count * (M.BUTTON_HEIGHT + M.BUTTON_PADDING) + M.BUTTON_PADDING

        local screenW, screenH = love.graphics.getDimensions()
        self.x = (screenW - self.width) / 2
        self.y = (screenH - self.height) / 2 - 20

        local color = sourceLocation == "belt" and self.colors.header_misc or self.colors.header_cups
        self.buttons.header_pull_item = {
            x = self.x + M.BOARD_PADDING,
            y = self.y + M.BOARD_PADDING,
            width = M.COLUMN_WIDTH,
            height = M.HEADER_HEIGHT,
            name = sourceLocation == "belt" and "Pull from Belt" or "Pull from Pack",
            color = color,
            enabled = true,
        }

        local colX = self.x + M.BOARD_PADDING
        for i, option in ipairs(options) do
            local btnY = self.y + M.BOARD_PADDING + M.HEADER_HEIGHT + M.BUTTON_PADDING +
                (i - 1) * (M.BUTTON_HEIGHT + M.BUTTON_PADDING)
            self.buttons[#self.buttons + 1] = {
                action = option,
                x = colX,
                y = btnY,
                width = M.COLUMN_WIDTH,
                height = M.BUTTON_HEIGHT,
                enabled = true,
                disabledReason = nil,
                suitColor = color,
            }
        end
    end

    function board:getPullSwapOptions(pullOption)
        local sourceLocation = pullOption and pullOption.pullSourceLocation or
            self:getPullItemSourceLocation(self.pullItemBaseAction)
        local options = {}
        for i, item in ipairs(self:getInventoryItems("hands")) do
            if item and not item.destroyed then
                local itemId = item.id or tostring(i)
                options[#options + 1] = {
                    id = "swap_hands_" .. tostring(itemId),
                    name = item.name or item.templateId or ("Held Item " .. tostring(i)),
                    description = "Swap this held item back to " .. sourceLocation .. ".",
                    pullSwapItem = item,
                    pullSwapItemId = item.id,
                    pullSourceLocation = sourceLocation,
                }
            end
        end
        return options
    end

    function board:pullItemNeedsSwap(pullOption)
        local item = pullOption and pullOption.pullItem
        return self:getAvailableInventorySlots("hands") < self:getItemSlotSize(item)
    end

    function board:showPullSwapOptions(pullOption)
        local options = self:getPullSwapOptions(pullOption)
        if #options == 0 then
            return false
        end

        self.mode = "pull_swap"
        self.pullItemSelectedOption = pullOption
        self.pullItemSwapOptions = options
        self:buildPullSwapButtons(options, pullOption and pullOption.pullSourceLocation)
        return true
    end

    function board:buildPullSwapButtons(options, sourceLocation)
        self.buttons = {}

        local count = #options
        self.width = M.COLUMN_WIDTH + M.BOARD_PADDING * 2
        self.height = M.BOARD_PADDING * 2 + M.HEADER_HEIGHT +
            count * (M.BUTTON_HEIGHT + M.BUTTON_PADDING) + M.BUTTON_PADDING

        local screenW, screenH = love.graphics.getDimensions()
        self.x = (screenW - self.width) / 2
        self.y = (screenH - self.height) / 2 - 20

        local color = sourceLocation == "belt" and self.colors.header_misc or self.colors.header_cups
        self.buttons.header_pull_swap = {
            x = self.x + M.BOARD_PADDING,
            y = self.y + M.BOARD_PADDING,
            width = M.COLUMN_WIDTH,
            height = M.HEADER_HEIGHT,
            name = "Swap Held Item",
            color = color,
            enabled = true,
        }

        local colX = self.x + M.BOARD_PADDING
        for i, option in ipairs(options) do
            local btnY = self.y + M.BOARD_PADDING + M.HEADER_HEIGHT + M.BUTTON_PADDING +
                (i - 1) * (M.BUTTON_HEIGHT + M.BUTTON_PADDING)
            self.buttons[#self.buttons + 1] = {
                action = option,
                x = colX,
                y = btnY,
                width = M.COLUMN_WIDTH,
                height = M.BUTTON_HEIGHT,
                enabled = true,
                disabledReason = nil,
                suitColor = color,
            }
        end
    end

    function board:getAidTriggerOptions()
        local options = {}
        local suits = {
            action_registry.SUITS.SWORDS,
            action_registry.SUITS.PENTACLES,
            action_registry.SUITS.CUPS,
            action_registry.SUITS.WANDS,
            action_registry.SUITS.MISC,
        }

        for _, suit in ipairs(suits) do
            for _, action in ipairs(action_registry.getActionsForSuit(suit, {
                challengeOnly = true,
                commandBoardOnly = true,
            })) do
                if action.id ~= "aid" and action.id ~= "vigilance" then
                    options[#options + 1] = {
                        id = "aid_trigger_" .. action.id,
                        name = action.name,
                        description = "Reveal Aid Another when the ally uses " .. action.name .. ".",
                        aidTrigger = {
                            action = action.id,
                        },
                        aidTriggerAction = action,
                    }
                end
            end
        end

        return options
    end

    function board:showAidTriggers(aidAction)
        local options = self:getAidTriggerOptions()
        if #options == 0 then
            return false
        end

        self.mode = "aid_trigger"
        self.aidBaseAction = aidAction
        self.aidTriggerOptions = options
        self:buildAidTriggerButtons(options)
        return true
    end

    function board:buildAidTriggerButtons(options)
        self.buttons = {}

        local count = #options
        self.width = M.COLUMN_WIDTH + M.BOARD_PADDING * 2
        self.height = M.BOARD_PADDING * 2 + M.HEADER_HEIGHT +
            count * (M.BUTTON_HEIGHT + M.BUTTON_PADDING) + M.BUTTON_PADDING

        local screenW, screenH = love.graphics.getDimensions()
        self.x = (screenW - self.width) / 2
        self.y = (screenH - self.height) / 2 - 20

        self.buttons.header_aid = {
            x = self.x + M.BOARD_PADDING,
            y = self.y + M.BOARD_PADDING,
            width = M.COLUMN_WIDTH,
            height = M.HEADER_HEIGHT,
            name = "Aid Trigger",
            color = self.colors.header_cups,
            enabled = true,
        }

        local colX = self.x + M.BOARD_PADDING
        for i, option in ipairs(options) do
            local btnY = self.y + M.BOARD_PADDING + M.HEADER_HEIGHT + M.BUTTON_PADDING +
                (i - 1) * (M.BUTTON_HEIGHT + M.BUTTON_PADDING)
            self.buttons[#self.buttons + 1] = {
                action = option,
                x = colX,
                y = btnY,
                width = M.COLUMN_WIDTH,
                height = M.BUTTON_HEIGHT,
                enabled = true,
                disabledReason = nil,
                suitColor = self.colors.header_cups,
            }
        end
    end

    function board:showAidObjectiveEntry(option)
        if not option then
            return false
        end

        self.mode = "aid_text"
        self.pendingAidTriggerOption = option
        self.pendingAidText = ""
        self.buttons = {}
        self.hoveredAction = nil
        self.hoveredButton = nil

        local screenW, screenH = love.graphics.getDimensions()
        self.width = M.COLUMN_WIDTH * 2 + M.BOARD_PADDING * 2
        self.height = M.BOARD_PADDING * 2 + M.HEADER_HEIGHT + M.BUTTON_HEIGHT + M.BUTTON_PADDING * 3
        self.x = (screenW - self.width) / 2
        self.y = (screenH - self.height) / 2 - 20
        return true
    end

    function board:returnToAidTriggerMode()
        self.mode = "aid_trigger"
        self.pendingAidTriggerOption = nil
        self.pendingAidText = nil
        self.hoveredAction = nil
        self.hoveredButton = nil
        self:buildAidTriggerButtons(self.aidTriggerOptions or {})
    end

    function board:submitAidObjectiveEntry()
        local text = trimText(self.pendingAidText)
        if text == "" or not self.aidBaseAction or not self.pendingAidTriggerOption then
            return false
        end

        local option = self.pendingAidTriggerOption
        local trigger = shallowClone(option.aidTrigger or {})
        trigger.objective = text
        self:emitActionSelected(
            self.aidBaseAction,
            nil,
            nil,
            nil,
            nil,
            nil,
            nil,
            nil,
            nil,
            trigger,
            option
        )
        self:hide()
        return true
    end

    function board:showVigilanceTriggers(followUpAction)
        self.mode = "vigilance_trigger"
        self.vigilanceSelectedFollowUp = followUpAction
        self.vigilanceTriggerOptions = vigilance_triggers.listOptions()
        self:buildVigilanceTriggerButtons(self.vigilanceTriggerOptions)
        return true
    end

    function board:buildVigilanceFollowUpButtons(options)
        self.buttons = {}

        local count = #options
        self.width = M.COLUMN_WIDTH + M.BOARD_PADDING * 2
        self.height = M.BOARD_PADDING * 2 + M.HEADER_HEIGHT +
            count * (M.BUTTON_HEIGHT + M.BUTTON_PADDING) + M.BUTTON_PADDING

        local screenW, screenH = love.graphics.getDimensions()
        self.x = (screenW - self.width) / 2
        self.y = (screenH - self.height) / 2 - 20

        local cardSuit = action_registry.cardSuitToActionSuit(self.selectedCard and self.selectedCard.suit)
        local suitNames = {
            [action_registry.SUITS.SWORDS] = "Swords",
            [action_registry.SUITS.PENTACLES] = "Pentacles",
            [action_registry.SUITS.CUPS] = "Cups",
            [action_registry.SUITS.WANDS] = "Wands",
        }
        local headerColors = {
            [action_registry.SUITS.SWORDS] = self.colors.header_swords,
            [action_registry.SUITS.PENTACLES] = self.colors.header_pentacles,
            [action_registry.SUITS.CUPS] = self.colors.header_cups,
            [action_registry.SUITS.WANDS] = self.colors.header_wands,
        }

        self.buttons.header_followup = {
            x = self.x + M.BOARD_PADDING,
            y = self.y + M.BOARD_PADDING,
            width = M.COLUMN_WIDTH,
            height = M.HEADER_HEIGHT,
            name = (suitNames[cardSuit] or "Suit") .. " Follow-Up",
            color = headerColors[cardSuit] or self.colors.header_misc,
            enabled = true,
        }

        local colX = self.x + M.BOARD_PADDING
        for i, action in ipairs(options) do
            local btnY = self.y + M.BOARD_PADDING + M.HEADER_HEIGHT + M.BUTTON_PADDING +
                (i - 1) * (M.BUTTON_HEIGHT + M.BUTTON_PADDING)
            self.buttons[#self.buttons + 1] = {
                action = action,
                x = colX,
                y = btnY,
                width = M.COLUMN_WIDTH,
                height = M.BUTTON_HEIGHT,
                enabled = true,
                disabledReason = nil,
                suitColor = self.buttons.header_followup.color,
            }
        end
    end

    function board:returnToActionMode()
        self.mode = "action"
        self.reaverBaseAction = nil
        self.reaverOptions = nil
        self.doomEyeBaseAction = nil
        self.doomEyeOptions = nil
        self.proudAndAncientBaseAction = nil
        self.proudAndAncientOptions = nil
        self.recoverBaseAction = nil
        self.recoverEffectOptions = nil
        self.roughhouseBaseAction = nil
        self.roughhouseEffectOptions = nil
        self.commandBaseAction = nil
        self.commandOptions = nil
        self.pendingCommandTextOption = nil
        self.pendingCommandText = nil
        self.aidBaseAction = nil
        self.aidTriggerOptions = nil
        self.pendingAidTriggerOption = nil
        self.pendingAidText = nil
        self.pullItemBaseAction = nil
        self.pullItemOptions = nil
        self.pullItemSelectedOption = nil
        self.pullItemSwapOptions = nil
        self.useItemBaseAction = nil
        self.useItemOptions = nil
        self.upMySleeveBaseAction = nil
        self.upMySleeveOptions = nil
        self.dwimmercraftBaseAction = nil
        self.dwimmercraftOptions = nil
        self.retreatBaseAction = nil
        self.retreatOptions = nil
        self.pendingRetreatOption = nil
        self.pendingRetreatText = nil
        self.counterSpellBaseAction = nil
        self.counterSpellOptions = nil
        self.vigilanceBaseAction = nil
        self.vigilanceSelectedFollowUp = nil
        self.vigilanceFollowUpOptions = nil
        self.vigilanceTriggerOptions = nil
        self.hoveredAction = nil
        self.hoveredButton = nil

        local screenW, screenH = love.graphics.getDimensions()
        local numColumns = 5
        self.width = numColumns * M.COLUMN_WIDTH + M.BOARD_PADDING * 2 + (numColumns - 1) * M.BUTTON_PADDING
        self.height = self:calculateHeight()
        self.x = (screenW - self.width) / 2
        self.y = (screenH - self.height) / 2 - 50

        self:buildButtons()
    end

    function board:returnToVigilanceFollowUpMode()
        if self.vigilanceBaseAction and self.vigilanceFollowUpOptions and #self.vigilanceFollowUpOptions > 1 then
            self.mode = "vigilance_followup"
            self.vigilanceSelectedFollowUp = nil
            self.vigilanceTriggerOptions = nil
            self.hoveredAction = nil
            self.hoveredButton = nil
            self:buildVigilanceFollowUpButtons(self.vigilanceFollowUpOptions)
        else
            self:returnToActionMode()
        end
    end

    function board:buildVigilanceTriggerButtons(options)
        self.buttons = {}

        local count = #options
        self.width = M.COLUMN_WIDTH + M.BOARD_PADDING * 2
        self.height = M.BOARD_PADDING * 2 + M.HEADER_HEIGHT +
            count * (M.BUTTON_HEIGHT + M.BUTTON_PADDING) + M.BUTTON_PADDING

        local screenW, screenH = love.graphics.getDimensions()
        self.x = (screenW - self.width) / 2
        self.y = (screenH - self.height) / 2 - 20

        self.buttons.header_trigger = {
            x = self.x + M.BOARD_PADDING,
            y = self.y + M.BOARD_PADDING,
            width = M.COLUMN_WIDTH,
            height = M.HEADER_HEIGHT,
            name = "Trigger",
            color = self.colors.header_misc,
            enabled = true,
        }

        local colX = self.x + M.BOARD_PADDING
        for i, option in ipairs(options) do
            local btnY = self.y + M.BOARD_PADDING + M.HEADER_HEIGHT + M.BUTTON_PADDING +
                (i - 1) * (M.BUTTON_HEIGHT + M.BUTTON_PADDING)
            self.buttons[#self.buttons + 1] = {
                action = option,
                x = colX,
                y = btnY,
                width = M.COLUMN_WIDTH,
                height = M.BUTTON_HEIGHT,
                enabled = true,
                disabledReason = nil,
                suitColor = self.colors.header_misc,
            }
        end
    end

    function board:emitActionSelected(action, followUpAction, vigilanceTrigger, vigilanceTriggerOption, roughhouseEffect, roughhouseEffectOption, commandName, commandCompanionId, commandOption, aidTrigger, aidTriggerOption, pullItem, pullItemOption, pullSwapItem, pullSwapOption, useItem, useItemOption)
        self.eventBus:emit("action_selected", {
            action = action,
            card = self.selectedCard,
            entity = self.selectedEntity,
            isPrimaryTurn = self.isPrimaryTurn,
            followUpAction = followUpAction,
            vigilanceTrigger = vigilanceTrigger,
            vigilanceTriggerOption = vigilanceTriggerOption,
            roughhouseEffect = roughhouseEffect,
            roughhouseEffectOption = roughhouseEffectOption,
            commandName = commandName,
            commandCompanionId = commandCompanionId,
            commandOption = commandOption,
            aidTrigger = aidTrigger,
            aidTriggerOption = aidTriggerOption,
            pullItem = pullItem,
            pullItemId = pullItem and pullItem.id or nil,
            pullItemOption = pullItemOption,
            pullSwapItem = pullSwapItem,
            pullSwapItemId = pullSwapItem and pullSwapItem.id or nil,
            pullSwapOption = pullSwapOption,
            useItem = useItem,
            useItemId = useItem and useItem.id or nil,
            useItemOption = useItemOption,
        })
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function board:update(dt)
        -- Animation updates if needed
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    ----------------------------------------------------------------------------

    function board:draw()
        if not love or not self.isVisible then return end

        -- Draw board background
        love.graphics.setColor(self.colors.board_bg)
        love.graphics.rectangle("fill", self.x, self.y, self.width, self.height, 8, 8)

        -- Draw board border
        love.graphics.setColor(self.colors.board_border)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", self.x, self.y, self.width, self.height, 8, 8)
        love.graphics.setLineWidth(1)

        -- Draw title
        love.graphics.setColor(self.colors.header_text)
        local title = nil
        if self.mode == "reaver_option" then
            title = "Choose Attack Approach"
        elseif self.mode == "doom_eye_option" then
            title = "Choose Shot Approach"
        elseif self.mode == "proud_and_ancient_option" then
            title = "Choose Incantation"
        elseif self.mode == "recover_effect" then
            title = "Choose Recover Effect"
        elseif self.mode == "roughhouse_effect" then
            title = "Choose Roughhouse Effect"
        elseif self.mode == "command_option" then
            title = "Choose Companion Command"
        elseif self.mode == "command_text" then
            title = "Describe Command"
        elseif self.mode == "aid_trigger" then
            title = "Choose Aid Trigger"
        elseif self.mode == "aid_text" then
            title = "Describe Aid Objective"
        elseif self.mode == "pull_item" then
            title = "Choose Item"
        elseif self.mode == "pull_swap" then
            title = "Choose Held Swap"
        elseif self.mode == "use_item" then
            title = "Choose Item"
        elseif self.mode == "up_my_sleeve_option" then
            title = "Choose Sleeve Item"
        elseif self.mode == "dwimmercraft_option" then
            title = "Choose Dwimmercraft"
        elseif self.mode == "retreat_option" then
            title = "Frame Retreat"
        elseif self.mode == "retreat_text" then
            title = "Describe Clever Tactic"
        elseif self.mode == "counter_spell_option" then
            title = "Choose Spell to Negate"
        elseif self.mode == "vigilance_followup" then
            title = "Choose Vigilance Follow-Up"
        elseif self.mode == "vigilance_trigger" then
            title = "Choose Vigilance Trigger"
        else
            title = self.isPrimaryTurn and "Choose Action (Primary Turn)" or "Choose Minor Action"
        end
        love.graphics.printf(title, self.x, self.y - 25, self.width, "center")

        if self.mode == "reaver_option" then
            local header = self.buttons.header_reaver
            if header then
                self:drawColumnHeader(header)
            end
        elseif self.mode == "doom_eye_option" then
            local header = self.buttons.header_doom_eye
            if header then
                self:drawColumnHeader(header)
            end
        elseif self.mode == "proud_and_ancient_option" then
            local header = self.buttons.header_proud_and_ancient
            if header then
                self:drawColumnHeader(header)
            end
        elseif self.mode == "recover_effect" then
            local header = self.buttons.header_recover
            if header then
                self:drawColumnHeader(header)
            end
        elseif self.mode == "roughhouse_effect" then
            local header = self.buttons.header_roughhouse
            if header then
                self:drawColumnHeader(header)
            end
        elseif self.mode == "command_option" then
            local header = self.buttons.header_command
            if header then
                self:drawColumnHeader(header)
            end
        elseif self.mode == "aid_trigger" then
            local header = self.buttons.header_aid
            if header then
                self:drawColumnHeader(header)
            end
        elseif self.mode == "pull_item" then
            local header = self.buttons.header_pull_item
            if header then
                self:drawColumnHeader(header)
            end
        elseif self.mode == "pull_swap" then
            local header = self.buttons.header_pull_swap
            if header then
                self:drawColumnHeader(header)
            end
        elseif self.mode == "use_item" then
            local header = self.buttons.header_use_item
            if header then
                self:drawColumnHeader(header)
            end
        elseif self.mode == "up_my_sleeve_option" then
            local header = self.buttons.header_up_my_sleeve
            if header then
                self:drawColumnHeader(header)
            end
        elseif self.mode == "dwimmercraft_option" then
            local header = self.buttons.header_dwimmercraft
            if header then
                self:drawColumnHeader(header)
            end
        elseif self.mode == "retreat_option" then
            local header = self.buttons.header_retreat
            if header then
                self:drawColumnHeader(header)
            end
        elseif self.mode == "counter_spell_option" then
            local header = self.buttons.header_counter_spell
            if header then
                self:drawColumnHeader(header)
            end
        elseif self.mode == "vigilance_followup" then
            local header = self.buttons.header_followup
            if header then
                self:drawColumnHeader(header)
            end
        elseif self.mode == "vigilance_trigger" then
            local header = self.buttons.header_trigger
            if header then
                self:drawColumnHeader(header)
            end
        else
            -- Draw column headers
            for i = 1, 5 do
                local header = self.buttons["header_" .. i]
                if header then
                    self:drawColumnHeader(header)
                end
            end
        end

        -- Draw action buttons
        for _, btn in ipairs(self.buttons) do
            if btn.action then
                self:drawActionButton(btn)
            end
        end

        if self.mode == "command_text" then
            self:drawCommandTextEntry()
        elseif self.mode == "aid_text" then
            self:drawAidTextEntry()
        elseif self.mode == "retreat_text" then
            self:drawRetreatTextEntry()
        end

        -- Draw tooltip
        if self.hoveredAction then
            self:drawTooltip()
        end
    end

    function board:drawCommandTextEntry()
        local option = self.pendingCommandTextOption or {}
        local label = option.commandDisplayName or option.name or "Command"
        local fieldX = self.x + M.BOARD_PADDING
        local fieldY = self.y + M.BOARD_PADDING + M.HEADER_HEIGHT
        local fieldW = self.width - M.BOARD_PADDING * 2
        local fieldH = M.BUTTON_HEIGHT
        local text = self.pendingCommandText or ""

        love.graphics.setColor(self.colors.header_text)
        love.graphics.printf(label, fieldX, self.y + M.BOARD_PADDING + 6, fieldW, "center")
        love.graphics.setColor(self.colors.button_enabled)
        love.graphics.rectangle("fill", fieldX, fieldY, fieldW, fieldH, 4, 4)
        love.graphics.setColor(self.colors.header_cups[1], self.colors.header_cups[2], self.colors.header_cups[3], 0.8)
        love.graphics.rectangle("line", fieldX, fieldY, fieldW, fieldH, 4, 4)
        love.graphics.setColor(self.colors.button_text)
        love.graphics.printf(text, fieldX + 8, fieldY + 10, fieldW - 16, "left")
    end

    function board:drawAidTextEntry()
        local option = self.pendingAidTriggerOption or {}
        local label = option.name or "Aid Objective"
        local fieldX = self.x + M.BOARD_PADDING
        local fieldY = self.y + M.BOARD_PADDING + M.HEADER_HEIGHT
        local fieldW = self.width - M.BOARD_PADDING * 2
        local fieldH = M.BUTTON_HEIGHT
        local text = self.pendingAidText or ""

        love.graphics.setColor(self.colors.header_text)
        love.graphics.printf(label, fieldX, self.y + M.BOARD_PADDING + 6, fieldW, "center")
        love.graphics.setColor(self.colors.button_enabled)
        love.graphics.rectangle("fill", fieldX, fieldY, fieldW, fieldH, 4, 4)
        love.graphics.setColor(self.colors.header_cups[1], self.colors.header_cups[2], self.colors.header_cups[3], 0.8)
        love.graphics.rectangle("line", fieldX, fieldY, fieldW, fieldH, 4, 4)
        love.graphics.setColor(self.colors.button_text)
        love.graphics.printf(text, fieldX + 8, fieldY + 10, fieldW - 16, "left")
    end

    function board:drawRetreatTextEntry()
        local option = self.pendingRetreatOption or {}
        local label = option.name or "Clever Escape"
        local fieldX = self.x + M.BOARD_PADDING
        local fieldY = self.y + M.BOARD_PADDING + M.HEADER_HEIGHT
        local fieldW = self.width - M.BOARD_PADDING * 2
        local fieldH = M.BUTTON_HEIGHT
        local text = self.pendingRetreatText or ""

        love.graphics.setColor(self.colors.header_text)
        love.graphics.printf(label, fieldX, self.y + M.BOARD_PADDING + 6, fieldW, "center")
        love.graphics.setColor(self.colors.button_enabled)
        love.graphics.rectangle("fill", fieldX, fieldY, fieldW, fieldH, 4, 4)
        love.graphics.setColor(self.colors.header_misc[1], self.colors.header_misc[2], self.colors.header_misc[3], 0.8)
        love.graphics.rectangle("line", fieldX, fieldY, fieldW, fieldH, 4, 4)
        love.graphics.setColor(self.colors.button_text)
        love.graphics.printf(text, fieldX + 8, fieldY + 10, fieldW - 16, "left")
    end

    --- Draw a column header
    function board:drawColumnHeader(header)
        local alpha = header.enabled and 1.0 or 0.4

        -- Header background
        love.graphics.setColor(header.color[1], header.color[2], header.color[3], alpha)
        love.graphics.rectangle("fill", header.x, header.y, header.width, header.height, 4, 4)

        -- Header text
        love.graphics.setColor(self.colors.header_text[1], self.colors.header_text[2],
                               self.colors.header_text[3], alpha)
        love.graphics.printf(header.name, header.x, header.y + 7, header.width, "center")
    end

    --- Draw an action button
    function board:drawActionButton(btn)
        local isHovered = (self.hoveredAction == btn.action)

        -- Button background
        local bgColor
        if not btn.enabled then
            bgColor = self.colors.button_disabled
        elseif isHovered then
            bgColor = self.colors.button_hover
        else
            bgColor = self.colors.button_enabled
        end
        love.graphics.setColor(bgColor)
        love.graphics.rectangle("fill", btn.x, btn.y, btn.width, btn.height, 4, 4)

        -- Button border (tinted by suit)
        if btn.enabled then
            love.graphics.setColor(btn.suitColor[1], btn.suitColor[2], btn.suitColor[3], 0.8)
        else
            love.graphics.setColor(self.colors.button_border[1], self.colors.button_border[2],
                                   self.colors.button_border[3], 0.3)
        end
        love.graphics.setLineWidth(btn.enabled and 2 or 1)
        love.graphics.rectangle("line", btn.x, btn.y, btn.width, btn.height, 4, 4)
        love.graphics.setLineWidth(1)

        -- Button text
        local textColor = btn.enabled and self.colors.button_text or self.colors.button_text_dis
        love.graphics.setColor(textColor)

        -- Truncate name if too long
        local displayName = btn.action.name
        if #displayName > 14 then
            displayName = displayName:sub(1, 12) .. ".."
        end
        love.graphics.printf(displayName, btn.x + 4, btn.y + 10, btn.width - 8, "center")
    end

    --- Draw tooltip for hovered action
    function board:drawTooltip()
        local action = self.hoveredAction
        local button = self.hoveredButton
        if not action then return end

        local mx, my = love.mouse.getPosition()

        -- Build tooltip content
        local lines = {}
        lines[#lines + 1] = { text = action.name, color = self.colors.tooltip_text }
        lines[#lines + 1] = { text = "", color = self.colors.tooltip_text }  -- Spacer
        lines[#lines + 1] = { text = action.description, color = self.colors.tooltip_text, wrap = true }

        -- S12.2: Show disabled reason if action is blocked
        if button and not button.enabled and button.disabledReason then
            lines[#lines + 1] = { text = "", color = self.colors.tooltip_text }  -- Spacer
            lines[#lines + 1] = { text = "UNAVAILABLE:", color = { 0.9, 0.3, 0.3, 1.0 } }
            lines[#lines + 1] = { text = button.disabledReason, color = { 0.9, 0.5, 0.5, 1.0 }, wrap = true }
        end

        -- Calculate total value (only for enabled actions)
        if button and button.enabled then
            if action.attribute and self.selectedEntity then
                lines[#lines + 1] = { text = "", color = self.colors.tooltip_text }  -- Spacer
                local cardVal = self.selectedCard.value or 0
                local attrVal = self.selectedEntity[action.attribute] or 0
                local total = cardVal + attrVal
                local attrName = action.attribute:sub(1, 1):upper() .. action.attribute:sub(2)
                local calcText = string.format("Card (%d) + %s (%d) = %d", cardVal, attrName, attrVal, total)
                lines[#lines + 1] = { text = calcText, color = self.colors.tooltip_value }
            elseif not action.attribute then
                lines[#lines + 1] = { text = "", color = self.colors.tooltip_text }
                lines[#lines + 1] = { text = "Face value only", color = self.colors.tooltip_value }
            end
        end

        -- Calculate tooltip height
        local tooltipHeight = M.BOARD_PADDING * 2
        for _, line in ipairs(lines) do
            if line.wrap then
                -- Estimate wrapped text height
                local textWidth = M.TOOLTIP_WIDTH - M.BOARD_PADDING * 2
                local _, wrappedLines = love.graphics.getFont():getWrap(line.text, textWidth)
                tooltipHeight = tooltipHeight + #wrappedLines * M.TOOLTIP_LINE_HEIGHT
            else
                tooltipHeight = tooltipHeight + M.TOOLTIP_LINE_HEIGHT
            end
        end

        -- Position tooltip (avoid going off screen)
        local tooltipX = mx + 15
        local tooltipY = my + 15
        local screenW, screenH = love.graphics.getDimensions()

        if tooltipX + M.TOOLTIP_WIDTH > screenW then
            tooltipX = mx - M.TOOLTIP_WIDTH - 5
        end
        if tooltipY + tooltipHeight > screenH then
            tooltipY = my - tooltipHeight - 5
        end

        -- Draw tooltip background
        love.graphics.setColor(self.colors.tooltip_bg)
        love.graphics.rectangle("fill", tooltipX, tooltipY, M.TOOLTIP_WIDTH, tooltipHeight, 4, 4)

        -- Draw tooltip border
        love.graphics.setColor(self.colors.tooltip_border)
        love.graphics.rectangle("line", tooltipX, tooltipY, M.TOOLTIP_WIDTH, tooltipHeight, 4, 4)

        -- Draw tooltip text
        local textY = tooltipY + M.BOARD_PADDING
        for _, line in ipairs(lines) do
            love.graphics.setColor(line.color)
            if line.wrap then
                love.graphics.printf(line.text, tooltipX + M.BOARD_PADDING, textY,
                                     M.TOOLTIP_WIDTH - M.BOARD_PADDING * 2, "left")
                local _, wrappedLines = love.graphics.getFont():getWrap(line.text, M.TOOLTIP_WIDTH - M.BOARD_PADDING * 2)
                textY = textY + #wrappedLines * M.TOOLTIP_LINE_HEIGHT
            else
                love.graphics.print(line.text, tooltipX + M.BOARD_PADDING, textY)
                textY = textY + M.TOOLTIP_LINE_HEIGHT
            end
        end
    end

    ----------------------------------------------------------------------------
    -- INPUT HANDLING
    ----------------------------------------------------------------------------

    function board:mousepressed(x, y, button)
        if not self.isVisible then return false end
        if button ~= 1 then return false end

        -- Check if clicking on a button
        for _, btn in ipairs(self.buttons) do
            if btn.action and btn.enabled then
                if x >= btn.x and x <= btn.x + btn.width and
                   y >= btn.y and y <= btn.y + btn.height then
                    if self.mode == "action" and btn.action.id == "melee" then
                        local opened = self:showReaverAttackOptions(btn.action)
                        if opened then
                            return true
                        end
                        -- Fall back to standard behavior if Reaver is not available.
                    elseif self.mode == "action" and btn.action.id == "missile" then
                        local opened = self:showDoomEyeAttackOptions(btn.action)
                        if opened then
                            return true
                        end
                        -- Fall back to standard behavior if Doom Eye is not available.
                    elseif self.mode == "action" and btn.action.id == "speak_incantation" then
                        local opened = self:showProudAndAncientIncantationOptions(btn.action)
                        if opened then
                            return true
                        end
                        -- Fall back to standard behavior if Proud and Ancient is not available.
                    elseif self.mode == "action" and btn.action.id == "recover" then
                        local opened = self:showRecoverEffects(btn.action)
                        if opened then
                            return true
                        end
                        -- Fall back to standard behavior if there are no recoverable effects.
                    elseif self.mode == "action" and btn.action.id == "roughhouse" then
                        local opened = self:showRoughhouseEffects(btn.action)
                        if opened then
                            return true
                        end
                        -- Fall back to standard behavior if no effect options are available.
                    elseif self.mode == "action" and btn.action.id == "command" then
                        local opened = self:showCommandOptions(btn.action)
                        if opened then
                            return true
                        end
                        -- Fall back to standard behavior if no command options are available.
                    elseif self.mode == "action" and
                           (btn.action.id == "pull_item" or btn.action.id == "pull_item_belt") then
                        local opened = self:showPullItemOptions(btn.action)
                        if opened then
                            return true
                        end
                        -- Fall back to standard behavior if no carried items are available.
                    elseif self.mode == "action" and btn.action.id == "use_item" then
                        local opened = self:showUseItemOptions(btn.action)
                        if opened then
                            return true
                        end
                        -- Fall back to standard behavior if no held items are available.
                    elseif self.mode == "action" and btn.action.id == "up_my_sleeve" then
                        local opened = self:showUpMySleeveOptions(btn.action)
                        if opened then
                            return true
                        end
                        -- Fall back to standard behavior if no sleeve items are available.
                    elseif self.mode == "action" and btn.action.id == "dwimmercraft" then
                        local opened = self:showDwimmercraftOptions(btn.action)
                        if opened then
                            return true
                        end
                        -- Fall back to standard behavior if no Dwimmercraft options are available.
                    elseif self.mode == "action" and btn.action.id == "flee" then
                        local opened = self:showRetreatOptions(btn.action)
                        if opened then
                            return true
                        end
                        -- Fall back to standard behavior if retreat framing is unavailable.
                    elseif self.mode == "action" and btn.action.id == "counter_spell" then
                        local opened = self:showCounterSpellOptions(btn.action)
                        if opened then
                            return true
                        end
                        -- Fall back to standard behavior if no ongoing spell options are available.
                    elseif self.mode == "action" and btn.action.id == "aid" then
                        local opened = self:showAidTriggers(btn.action)
                        if opened then
                            return true
                        end
                        -- Fall back to standard behavior if no trigger options are available.
                    elseif self.mode == "action" and btn.action.id == "vigilance" and self.isPrimaryTurn then
                        local opened = self:showVigilanceFollowUp(btn.action)
                        if opened then
                            return true
                        end
                        -- Fall back to standard behavior if no follow-up options are available.
                    elseif self.mode == "reaver_option" and self.reaverBaseAction then
                        self:emitActionSelected(btn.action, nil)
                        self:hide()
                        return true
                    elseif self.mode == "doom_eye_option" and self.doomEyeBaseAction then
                        self:emitActionSelected(btn.action, nil)
                        self:hide()
                        return true
                    elseif self.mode == "proud_and_ancient_option" and self.proudAndAncientBaseAction then
                        self:emitActionSelected(btn.action, nil)
                        self:hide()
                        return true
                    elseif self.mode == "recover_effect" and self.recoverBaseAction then
                        self:emitActionSelected(btn.action, nil)
                        self:hide()
                        return true
                    elseif self.mode == "roughhouse_effect" and self.roughhouseBaseAction then
                        self:emitActionSelected(
                            self.roughhouseBaseAction,
                            nil,
                            nil,
                            nil,
                            btn.action.roughhouseEffect,
                            btn.action
                        )
                        self:hide()
                        return true
                    elseif self.mode == "command_option" and self.commandBaseAction then
                        if commandWantsFreeformText(btn.action) and self:showCommandTextEntry(btn.action) then
                            return true
                        end
                        self:emitActionSelected(
                            self.commandBaseAction,
                            nil,
                            nil,
                            nil,
                            nil,
                            nil,
                            btn.action.commandName,
                            btn.action.companionId,
                            btn.action
                        )
                        self:hide()
                        return true
                    elseif self.mode == "pull_item" and self.pullItemBaseAction then
                        if self:pullItemNeedsSwap(btn.action) and self:showPullSwapOptions(btn.action) then
                            return true
                        end
                        self:emitActionSelected(
                            self.pullItemBaseAction,
                            nil,
                            nil,
                            nil,
                            nil,
                            nil,
                            nil,
                            nil,
                            nil,
                            nil,
                            nil,
                            btn.action.pullItem,
                            btn.action
                        )
                        self:hide()
                        return true
                    elseif self.mode == "pull_swap" and self.pullItemBaseAction and self.pullItemSelectedOption then
                        self:emitActionSelected(
                            self.pullItemBaseAction,
                            nil,
                            nil,
                            nil,
                            nil,
                            nil,
                            nil,
                            nil,
                            nil,
                            nil,
                            nil,
                            self.pullItemSelectedOption.pullItem,
                            self.pullItemSelectedOption,
                            btn.action.pullSwapItem,
                            btn.action
                        )
                        self:hide()
                        return true
                    elseif self.mode == "use_item" and self.useItemBaseAction then
                        self:emitActionSelected(
                            self.useItemBaseAction,
                            nil,
                            nil,
                            nil,
                            nil,
                            nil,
                            nil,
                            nil,
                            nil,
                            nil,
                            nil,
                            nil,
                            nil,
                            nil,
                            nil,
                            btn.action.useItem,
                            btn.action
                        )
                        self:hide()
                        return true
                    elseif self.mode == "up_my_sleeve_option" and self.upMySleeveBaseAction then
                        self:emitActionSelected(btn.action, nil)
                        self:hide()
                        return true
                    elseif self.mode == "dwimmercraft_option" and self.dwimmercraftBaseAction then
                        self:emitActionSelected(btn.action, nil)
                        self:hide()
                        return true
                    elseif self.mode == "retreat_option" and self.retreatBaseAction then
                        if btn.action.retreatNeedsText and self:showRetreatTextEntry(btn.action) then
                            return true
                        end
                        self:emitActionSelected(btn.action, nil)
                        self:hide()
                        return true
                    elseif self.mode == "counter_spell_option" and self.counterSpellBaseAction then
                        self:emitActionSelected(btn.action, nil)
                        self:hide()
                        return true
                    elseif self.mode == "aid_trigger" and self.aidBaseAction then
                        self:showAidObjectiveEntry(btn.action)
                        return true
                    elseif self.mode == "vigilance_followup" and self.vigilanceBaseAction then
                        self:showVigilanceTriggers(btn.action)
                        return true
                    elseif self.mode == "vigilance_trigger" and self.vigilanceBaseAction and self.vigilanceSelectedFollowUp then
                        self:emitActionSelected(
                            self.vigilanceBaseAction,
                            self.vigilanceSelectedFollowUp,
                            btn.action.trigger or { template = btn.action.id },
                            btn.action
                        )
                        self:hide()
                        return true
                    end

                    self:emitActionSelected(btn.action, nil)
                    self:hide()
                    return true
                end
            end
        end

        -- Clicking outside closes or steps back from picker modes.
        if x < self.x or x > self.x + self.width or
           y < self.y or y > self.y + self.height then
            if self.mode == "reaver_option" or self.mode == "doom_eye_option" or
               self.mode == "proud_and_ancient_option" or
               self.mode == "recover_effect" or
               self.mode == "roughhouse_effect" or self.mode == "command_option" or
               self.mode == "aid_trigger" or self.mode == "pull_item" or self.mode == "use_item" or
               self.mode == "up_my_sleeve_option" or self.mode == "dwimmercraft_option" or
               self.mode == "retreat_option" or self.mode == "counter_spell_option" then
                self:returnToActionMode()
            elseif self.mode == "command_text" then
                self:returnToCommandOptionMode()
            elseif self.mode == "aid_text" then
                self:returnToAidTriggerMode()
            elseif self.mode == "retreat_text" then
                self:returnToRetreatOptionMode()
            elseif self.mode == "pull_swap" then
                self.mode = "pull_item"
                self.pullItemSelectedOption = nil
                self.pullItemSwapOptions = nil
                self:buildPullItemButtons(self.pullItemOptions or {}, self:getPullItemSourceLocation(self.pullItemBaseAction))
            elseif self.mode == "vigilance_followup" then
                self:returnToActionMode()
            elseif self.mode == "vigilance_trigger" then
                self:returnToVigilanceFollowUpMode()
            else
                self:hide()
            end
            return true
        end

        return false
    end

    function board:mousemoved(x, y, dx, dy)
        if not self.isVisible then return end

        -- Update hovered action (including disabled ones for tooltip)
        self.hoveredAction = nil
        self.hoveredButton = nil  -- S12.2: Track full button for disabled reason
        for _, btn in ipairs(self.buttons) do
            if btn.action then
                if x >= btn.x and x <= btn.x + btn.width and
                   y >= btn.y and y <= btn.y + btn.height then
                    self.hoveredAction = btn.action
                    self.hoveredButton = btn
                    break
                end
            end
        end
    end

    function board:appendCommandText(text)
        if self.mode ~= "command_text" or type(text) ~= "string" or text == "" then
            return false
        end

        self.pendingCommandText = ((self.pendingCommandText or "") .. text):sub(1, 80)
        return true
    end

    function board:appendAidText(text)
        if self.mode ~= "aid_text" or type(text) ~= "string" or text == "" then
            return false
        end

        self.pendingAidText = ((self.pendingAidText or "") .. text):sub(1, 120)
        return true
    end

    function board:appendRetreatText(text)
        if self.mode ~= "retreat_text" or type(text) ~= "string" or text == "" then
            return false
        end

        self.pendingRetreatText = ((self.pendingRetreatText or "") .. text):sub(1, 120)
        return true
    end

    function board:textinput(text)
        return self:appendCommandText(text) or self:appendAidText(text) or self:appendRetreatText(text)
    end

    function board:keypressed(key)
        if not self.isVisible then return false end

        if self.mode == "command_text" then
            if key == "escape" then
                self:returnToCommandOptionMode()
                return true
            elseif key == "return" or key == "kpenter" then
                self:submitCommandTextEntry()
                return true
            elseif key == "backspace" then
                local text = self.pendingCommandText or ""
                self.pendingCommandText = text:sub(1, math.max(0, #text - 1))
                return true
            elseif key == "space" then
                return self:appendCommandText(" ")
            elseif #key == 1 then
                return self:appendCommandText(key)
            end
            return true
        end

        if self.mode == "aid_text" then
            if key == "escape" then
                self:returnToAidTriggerMode()
                return true
            elseif key == "return" or key == "kpenter" then
                self:submitAidObjectiveEntry()
                return true
            elseif key == "backspace" then
                local text = self.pendingAidText or ""
                self.pendingAidText = text:sub(1, math.max(0, #text - 1))
                return true
            elseif key == "space" then
                return self:appendAidText(" ")
            elseif #key == 1 then
                return self:appendAidText(key)
            end
            return true
        end

        if self.mode == "retreat_text" then
            if key == "escape" then
                self:returnToRetreatOptionMode()
                return true
            elseif key == "return" or key == "kpenter" then
                self:submitRetreatTextEntry()
                return true
            elseif key == "backspace" then
                local text = self.pendingRetreatText or ""
                self.pendingRetreatText = text:sub(1, math.max(0, #text - 1))
                return true
            elseif key == "space" then
                return self:appendRetreatText(" ")
            elseif #key == 1 then
                return self:appendRetreatText(key)
            end
            return true
        end

        -- ESC to close
        if key == "escape" then
            if self.mode == "reaver_option" or self.mode == "doom_eye_option" or
               self.mode == "proud_and_ancient_option" or
               self.mode == "recover_effect" or
               self.mode == "roughhouse_effect" or self.mode == "command_option" or
               self.mode == "aid_trigger" or self.mode == "pull_item" or self.mode == "use_item" or
               self.mode == "up_my_sleeve_option" or self.mode == "dwimmercraft_option" or
               self.mode == "retreat_option" or self.mode == "counter_spell_option" then
                self:returnToActionMode()
            elseif self.mode == "aid_text" then
                self:returnToAidTriggerMode()
            elseif self.mode == "retreat_text" then
                self:returnToRetreatOptionMode()
            elseif self.mode == "pull_swap" then
                self.mode = "pull_item"
                self.pullItemSelectedOption = nil
                self.pullItemSwapOptions = nil
                self:buildPullItemButtons(self.pullItemOptions or {}, self:getPullItemSourceLocation(self.pullItemBaseAction))
            elseif self.mode == "vigilance_followup" then
                self:returnToActionMode()
            elseif self.mode == "vigilance_trigger" then
                self:returnToVigilanceFollowUpMode()
            else
                self:hide()
            end
            return true
        end

        return false
    end

    return board
end

return M
