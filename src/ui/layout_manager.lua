-- layout_manager.lua
-- Stage Layout Manager for Majesty
-- Ticket S13.2: Transition Center Vellum layouts across phases (Crawl/Challenge/Camp)
--
-- Focused scope: core visual components only (no modal layers).
-- Transitions are fade-only (positions update immediately).

local events = require('logic.events')

local M = {}

M.STAGES = {
    CRAWL = "crawl",
    CHALLENGE = "challenge",
    CAMP = "camp",
}

local DEFAULTS = {
    leftRailWidth = 200,
    rightRailWidth = 200,
    padding = 10,
    headerHeight = 40,
    bottomReserve = 200,
    arenaTopOffset = 90,
    equipmentBarOffset = 80,
    contextPanelMinWidth = 120,
    contextPanelMaxWidth = 240,
    minArenaWidth = 260,
    fadeDuration = 0.25,
}

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

--- Create a new LayoutManager
-- @param config table: { eventBus, screenWidth, screenHeight, leftRailWidth, rightRailWidth, padding, headerHeight }
-- @return LayoutManager instance
function M.createLayoutManager(config)
    config = config or {}

    local manager = {
        eventBus = config.eventBus or events.globalBus,
        stage = config.initialStage or M.STAGES.CRAWL,
        elements = {},
        screenWidth = config.screenWidth or 1280,
        screenHeight = config.screenHeight or 800,
        config = {
            leftRailWidth = config.leftRailWidth or DEFAULTS.leftRailWidth,
            rightRailWidth = config.rightRailWidth or DEFAULTS.rightRailWidth,
            padding = config.padding or DEFAULTS.padding,
            headerHeight = config.headerHeight or DEFAULTS.headerHeight,
            bottomReserve = config.bottomReserve or DEFAULTS.bottomReserve,
            arenaTopOffset = config.arenaTopOffset or DEFAULTS.arenaTopOffset,
            equipmentBarOffset = config.equipmentBarOffset or DEFAULTS.equipmentBarOffset,
            contextPanelMinWidth = config.contextPanelMinWidth or DEFAULTS.contextPanelMinWidth,
            contextPanelMaxWidth = config.contextPanelMaxWidth or DEFAULTS.contextPanelMaxWidth,
            minArenaWidth = config.minArenaWidth or DEFAULTS.minArenaWidth,
        },
        fadeDuration = config.fadeDuration or DEFAULTS.fadeDuration,
    }

    ----------------------------------------------------------------------------
    -- INIT & EVENTS
    ----------------------------------------------------------------------------

    function manager:init()
        self.eventBus:on(events.EVENTS.PHASE_CHANGED, function(data)
            if data and data.newPhase then
                self:setStage(data.newPhase)
            end
        end)
    end

    ----------------------------------------------------------------------------
    -- REGISTRATION
    ----------------------------------------------------------------------------

    --- Register a UI component to receive layout updates
    -- @param id string: Element ID
    -- @param component table: UI component instance
    -- @param opts table: { apply = function(component, layout) }
    function manager:register(id, component, opts)
        opts = opts or {}
        self.elements[id] = {
            id = id,
            component = component,
            apply = opts.apply,
            alpha = 1,
            targetAlpha = 1,
            layout = {},
            visible = true,
        }

        -- Apply current stage immediately for this element
        self:applyStageLayout(self.stage, true)
    end

    ----------------------------------------------------------------------------
    -- STAGE CONTROL
    ----------------------------------------------------------------------------

    function manager:setStage(stageName, immediate)
        local normalized = stageName
        if normalized ~= M.STAGES.CRAWL and normalized ~= M.STAGES.CHALLENGE and normalized ~= M.STAGES.CAMP then
            normalized = M.STAGES.CRAWL
        end
        self.stage = normalized
        self:applyStageLayout(self.stage, immediate)
    end

    ----------------------------------------------------------------------------
    -- LAYOUT CALCULATION
    ----------------------------------------------------------------------------

    function manager:computeLayouts()
        local cfg = self.config
        local w = self.screenWidth
        local h = self.screenHeight
        local padding = cfg.padding
        local header = cfg.headerHeight

        local centerX = cfg.leftRailWidth + padding
        local centerWidth = w - cfg.leftRailWidth - cfg.rightRailWidth - (padding * 2)
        if centerWidth < 200 then
            centerWidth = 200
        end

        local centerY = header + padding
        local centerHeight = h - header - (padding * 2)
        if centerHeight < 200 then
            centerHeight = 200
        end

        local contextWidth = math.floor(centerWidth * 0.25)
        contextWidth = clamp(contextWidth, cfg.contextPanelMinWidth, cfg.contextPanelMaxWidth)

        local arenaWidth = centerWidth - contextWidth - padding
        if arenaWidth < cfg.minArenaWidth then
            contextWidth = centerWidth - cfg.minArenaWidth - padding
            contextWidth = math.max(100, contextWidth)
            arenaWidth = centerWidth - contextWidth - padding
        end

        local arenaX = centerX + padding
        local arenaY = cfg.arenaTopOffset
        local arenaHeight = h - cfg.bottomReserve - arenaY - padding
        if arenaHeight < 200 then
            arenaHeight = math.max(200, math.floor(h * 0.4))
        end

        local contextX = arenaX + arenaWidth + padding
        local contextY = arenaY
        local contextHeight = arenaHeight

        local narrativeLayout = {
            x = centerX + padding,
            y = centerY,
            width = centerWidth - (padding * 2),
            height = centerHeight,
            alpha = 1,
            visible = true,
        }

        local equipmentLayout = {
            x = centerX + padding,
            y = h - cfg.equipmentBarOffset,
            alpha = 1,
            visible = true,
        }

        local hidden = { alpha = 0, visible = false }

        return {
            [M.STAGES.CRAWL] = {
                narrative_view = narrativeLayout,
                equipment_bar = equipmentLayout,
                arena_view = hidden,
                room_context_panel = hidden,
            },
            [M.STAGES.CHALLENGE] = {
                narrative_view = {
                    x = narrativeLayout.x,
                    y = narrativeLayout.y,
                    width = narrativeLayout.width,
                    height = narrativeLayout.height,
                    alpha = 0,
                    visible = false,
                },
                equipment_bar = {
                    x = equipmentLayout.x,
                    y = equipmentLayout.y,
                    alpha = 0,
                    visible = false,
                },
                arena_view = {
                    x = arenaX,
                    y = arenaY,
                    width = arenaWidth,
                    height = arenaHeight,
                    alpha = 1,
                    visible = true,
                },
                room_context_panel = {
                    x = contextX,
                    y = contextY,
                    width = contextWidth,
                    height = contextHeight,
                    alpha = 1,
                    visible = true,
                },
            },
            [M.STAGES.CAMP] = {
                narrative_view = hidden,
                equipment_bar = hidden,
                arena_view = hidden,
                room_context_panel = hidden,
            },
        }
    end

    ----------------------------------------------------------------------------
    -- APPLY
    ----------------------------------------------------------------------------

    function manager:applyStageLayout(stageName, immediate)
        local layouts = self:computeLayouts()
        local stageLayouts = layouts[stageName] or layouts[M.STAGES.CRAWL]

        for id, element in pairs(self.elements) do
            local layout = stageLayouts[id] or { alpha = 0, visible = false }
            element.layout = layout
            element.targetAlpha = layout.alpha or (layout.visible and 1 or 0)

            if immediate then
                element.alpha = element.targetAlpha
            end

            element.visible = (element.alpha or 0) > 0.01
            self:applyElement(element)
        end
    end

    function manager:applyElement(element)
        if not element.apply then return end
        local layout = element.layout or {}
        element.apply(element.component, {
            x = layout.x,
            y = layout.y,
            width = layout.width,
            height = layout.height,
            alpha = element.alpha or layout.alpha or 1,
            visible = element.visible,
        })
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function manager:update(dt)
        if not dt then return end
        local step = dt / self.fadeDuration
        if step > 1 then step = 1 end

        for _, element in pairs(self.elements) do
            if element.alpha ~= element.targetAlpha then
                if element.alpha < element.targetAlpha then
                    element.alpha = math.min(element.targetAlpha, element.alpha + step)
                else
                    element.alpha = math.max(element.targetAlpha, element.alpha - step)
                end
                element.visible = element.alpha > 0.01
                self:applyElement(element)
            end
        end
    end

    ----------------------------------------------------------------------------
    -- RESIZE
    ----------------------------------------------------------------------------

    function manager:resize(w, h)
        if w then self.screenWidth = w end
        if h then self.screenHeight = h end
        self:applyStageLayout(self.stage, true)
    end

    return manager
end

return M
