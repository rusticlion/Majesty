-- arena_view.lua
-- Arena Vellum (Tactical Schematic) for Majesty
-- Ticket S6.1: Zone-based battle map with tactical tokens
--
-- Replaces the narrative text view during challenges with a schematic
-- showing zone buckets and entity positions.

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- COLORS
--------------------------------------------------------------------------------
M.COLORS = {
    -- Zone buckets
    zone_bg         = { 0.85, 0.80, 0.70, 0.6 },    -- Parchment tint
    zone_border     = { 0.35, 0.30, 0.25, 1.0 },    -- Dark ink
    zone_active     = { 0.90, 0.80, 0.30, 0.3 },    -- Gold highlight for active zone
    zone_hover      = { 0.70, 0.85, 0.70, 0.3 },    -- Green for valid drop target
    zone_adjacent   = { 0.50, 0.70, 0.85, 0.4 },    -- S13.3: Blue highlight for adjacent zones

    -- Zone labels and descriptions
    label_bg        = { 0.25, 0.22, 0.18, 0.9 },
    label_text      = { 0.90, 0.85, 0.75, 1.0 },
    desc_text       = { 0.25, 0.22, 0.18, 0.9 },    -- S13.4: Inline description text (dark ink on parchment)

    -- S13.3: Zone adjacency lines
    adjacency_line  = { 0.45, 0.40, 0.35, 0.5 },    -- Subtle connection line
    adjacency_hover = { 0.60, 0.75, 0.90, 0.7 },    -- Highlighted when showing adjacency

    -- Tactical tokens
    token_pc        = { 0.25, 0.45, 0.35, 1.0 },    -- Green for PCs
    token_npc       = { 0.55, 0.25, 0.25, 1.0 },    -- Red for NPCs
    token_border    = { 0.15, 0.12, 0.10, 1.0 },
    token_active    = { 0.95, 0.85, 0.30, 1.0 },    -- Gold ring for active entity
    token_text      = { 0.95, 0.92, 0.88, 1.0 },

    -- Engagement
    clash_line      = { 0.80, 0.30, 0.20, 0.8 },    -- Red line
    clash_icon      = { 0.90, 0.40, 0.30, 1.0 },    -- Clash icon

    -- Drag ghost
    drag_ghost      = { 1.0, 1.0, 1.0, 0.5 },

    -- S10.2: Targeting reticle
    target_reticle  = { 0.95, 0.35, 0.25, 0.9 },    -- Red targeting
    target_valid    = { 0.35, 0.85, 0.35, 0.9 },    -- Green for valid target
    target_invalid  = { 0.60, 0.60, 0.60, 0.5 },    -- Grey for invalid
}

--------------------------------------------------------------------------------
-- LAYOUT CONSTANTS
--------------------------------------------------------------------------------
M.TOKEN_SIZE = 40
M.TOKEN_SPACING = 8
M.ZONE_PADDING = 15
M.ZONE_LABEL_HEIGHT = 24
M.ZONE_MIN_WIDTH = 150
M.ZONE_MIN_HEIGHT = 120

--------------------------------------------------------------------------------
-- ARENA VIEW FACTORY
--------------------------------------------------------------------------------

--- Create a new ArenaView
-- @param config table: { eventBus, x, y, width, height, inspectPanel, zoneSystem }
-- @return ArenaView instance
function M.createArenaView(config)
    config = config or {}

    local arena = {
        eventBus = config.eventBus or events.globalBus,

        -- Position and size
        x = config.x or 0,
        y = config.y or 0,
        width = config.width or 600,
        height = config.height or 500,

        -- State
        isVisible = false,
        roomData = nil,
        zones = {},              -- { id -> { x, y, width, height, name, entities } }
        entities = {},           -- All entities in the arena
        engagements = {},        -- { [entityId1..entityId2] -> true }

        -- Interaction
        hoveredZone = nil,
        hoveredEntity = nil,     -- S10.2/S13.7: Entity under mouse (always tracked now)
        draggedEntity = nil,
        dragOffsetX = 0,
        dragOffsetY = 0,

        -- Active entity highlight
        activeEntityId = nil,

        -- S10.2: Targeting mode
        targetingMode = false,
        validTargets = {},       -- Array of valid target entity IDs
        targetReticleTimer = 0,  -- For animation

        -- S13.7: Inspect panel reference for enemy tooltips
        inspectPanel = config.inspectPanel,

        -- S13.3: Zone system for adjacency queries
        zoneSystem = config.zoneSystem,

        colors = M.COLORS,
        alpha = 1,
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    function arena:init()
        -- Listen for challenge start
        self.eventBus:on(events.EVENTS.CHALLENGE_START, function(data)
            self:setupArena(data)
        end)

        -- Listen for challenge end
        self.eventBus:on(events.EVENTS.CHALLENGE_END, function(data)
            self:hide()
        end)

        -- Listen for turn changes to highlight active entity
        self.eventBus:on(events.EVENTS.CHALLENGE_TURN_START, function(data)
            if data.activeEntity then
                self.activeEntityId = data.activeEntity.id
            end
        end)

        -- Listen for engagement changes
        self.eventBus:on("engagement_formed", function(data)
            self:addEngagement(data.entity1, data.entity2)
        end)

        self.eventBus:on("engagement_broken", function(data)
            self:removeEngagement(data.entity1, data.entity2)
        end)

        -- S12.1: Listen for full engagement state sync from zone_system
        self.eventBus:on(events.EVENTS.ENGAGEMENT_CHANGED, function(data)
            self:syncEngagements(data.pairs or {})
        end)

        -- Listen for zone changes (from action resolver)
        self.eventBus:on("entity_zone_changed", function(data)
            if data.entity and data.newZone then
                self:syncEntityZone(data.entity, data.newZone)
            end
        end)
    end

    ----------------------------------------------------------------------------
    -- ARENA SETUP
    ----------------------------------------------------------------------------

    --- Set up the arena for a challenge
    function arena:setupArena(challengeData)
        self.isVisible = true
        self.entities = {}
        self.engagements = {}
        self.zones = {}

        -- Get room data for zones
        local roomId = challengeData.roomId
        -- For now, create default zones if room data doesn't have them
        local zoneData = challengeData.zones or self:getDefaultZones()

        -- Calculate zone layout
        self:layoutZones(zoneData)

        -- Add combatants
        local allCombatants = {}
        for _, pc in ipairs(challengeData.pcs or {}) do
            allCombatants[#allCombatants + 1] = pc
        end
        for _, npc in ipairs(challengeData.npcs or {}) do
            allCombatants[#allCombatants + 1] = npc
        end

        -- Place entities in zones
        for _, entity in ipairs(allCombatants) do
            local zoneId = entity.zone or "main"
            self:addEntity(entity, zoneId)
        end

        self.eventBus:emit("arena_ready", { zones = self.zones })
    end

    --- Get default zones if room doesn't specify any
    function arena:getDefaultZones()
        return {
            { id = "main", name = "Battlefield" },
        }
    end

    --- Calculate zone bucket layout
    function arena:layoutZones(zoneData)
        local numZones = #zoneData
        if numZones == 0 then
            numZones = 1
            zoneData = self:getDefaultZones()
        end

        -- Calculate grid layout (prefer horizontal arrangement)
        local cols, rows
        if numZones <= 2 then
            cols, rows = numZones, 1
        elseif numZones <= 4 then
            cols, rows = 2, 2
        elseif numZones <= 6 then
            cols, rows = 3, 2
        else
            cols = math.ceil(math.sqrt(numZones))
            rows = math.ceil(numZones / cols)
        end

        local zoneWidth = math.max(M.ZONE_MIN_WIDTH, (self.width - M.ZONE_PADDING * (cols + 1)) / cols)
        local zoneHeight = math.max(M.ZONE_MIN_HEIGHT, (self.height - M.ZONE_PADDING * (rows + 1)) / rows)

        -- Create zone buckets
        local idx = 1
        for row = 1, rows do
            for col = 1, cols do
                if idx <= numZones then
                    local zd = zoneData[idx]
                    local zx = self.x + M.ZONE_PADDING + (col - 1) * (zoneWidth + M.ZONE_PADDING)
                    local zy = self.y + M.ZONE_PADDING + (row - 1) * (zoneHeight + M.ZONE_PADDING)

                    self.zones[zd.id] = {
                        id = zd.id,
                        name = zd.name or zd.id,
                        description = zd.description,
                        x = zx,
                        y = zy,
                        width = zoneWidth,
                        height = zoneHeight,
                        entities = {},
                    }
                    idx = idx + 1
                end
            end
        end

        -- Preserve entity assignments after relayout
        if next(self.entities) then
            self:rebuildZoneEntities()
        end
    end

    ----------------------------------------------------------------------------
    -- ENTITY MANAGEMENT
    ----------------------------------------------------------------------------

    --- Rebuild zone entity buckets after relayout
    function arena:rebuildZoneEntities()
        for _, zone in pairs(self.zones) do
            zone.entities = {}
        end

        for _, data in pairs(self.entities) do
            local zoneId = data.zoneId or (data.entity and data.entity.zone) or "main"
            local zone = self.zones[zoneId]
            if not zone then
                local fallbackId = next(self.zones)
                zone = fallbackId and self.zones[fallbackId] or nil
                zoneId = zone and zone.id or zoneId
            end
            if zone and data.entity then
                zone.entities[#zone.entities + 1] = data.entity
                data.zoneId = zoneId
                data.entity.zone = zoneId
            end
        end
    end

    --- Add an entity to a zone
    function arena:addEntity(entity, zoneId)
        zoneId = zoneId or "main"

        -- Ensure zone exists
        if not self.zones[zoneId] then
            zoneId = next(self.zones) -- Use first available zone
        end

        if not self.zones[zoneId] then
            return -- No zones available
        end

        -- Store entity reference
        self.entities[entity.id] = {
            entity = entity,
            zoneId = zoneId,
        }

        -- Add to zone's entity list
        local zone = self.zones[zoneId]
        zone.entities[#zone.entities + 1] = entity

        -- Update entity's zone property
        entity.zone = zoneId
    end

    --- Move an entity to a different zone
    function arena:moveEntity(entity, newZoneId)
        local entityData = self.entities[entity.id]
        if not entityData then return false end

        local oldZoneId = entityData.zoneId
        local oldZone = self.zones[oldZoneId]
        local newZone = self.zones[newZoneId]

        if not newZone then return false end

        -- Remove from old zone
        if oldZone then
            for i, e in ipairs(oldZone.entities) do
                if e.id == entity.id then
                    table.remove(oldZone.entities, i)
                    break
                end
            end
        end

        -- Add to new zone
        newZone.entities[#newZone.entities + 1] = entity
        entityData.zoneId = newZoneId
        entity.zone = newZoneId

        -- Emit event
        self.eventBus:emit("entity_zone_changed", {
            entity = entity,
            oldZone = oldZoneId,
            newZone = newZoneId,
        })

        return true
    end

    --- Sync entity zone from external changes (e.g., action resolver)
    -- Updates internal tracking when entity.zone is changed externally
    function arena:syncEntityZone(entity, newZoneId)
        local entityData = self.entities[entity.id]
        if not entityData then return false end

        local oldZoneId = entityData.zoneId
        if oldZoneId == newZoneId then return true end  -- Already in sync

        local oldZone = self.zones[oldZoneId]
        local newZone = self.zones[newZoneId]

        if not newZone then return false end

        -- Remove from old zone
        if oldZone then
            for i, e in ipairs(oldZone.entities) do
                if e.id == entity.id then
                    table.remove(oldZone.entities, i)
                    break
                end
            end
        end

        -- Add to new zone
        newZone.entities[#newZone.entities + 1] = entity
        entityData.zoneId = newZoneId

        return true
    end

    ----------------------------------------------------------------------------
    -- ENGAGEMENT
    ----------------------------------------------------------------------------

    --- Add engagement between two entities
    function arena:addEngagement(entity1, entity2)
        local key = self:engagementKey(entity1, entity2)
        self.engagements[key] = true
    end

    --- Remove engagement between two entities
    function arena:removeEngagement(entity1, entity2)
        local key = self:engagementKey(entity1, entity2)
        self.engagements[key] = nil
    end

    --- Check if two entities are engaged
    function arena:areEngaged(entity1, entity2)
        local key = self:engagementKey(entity1, entity2)
        return self.engagements[key] == true
    end

    --- Generate a consistent key for an engagement pair
    function arena:engagementKey(entity1, entity2)
        local id1 = entity1.id or tostring(entity1)
        local id2 = entity2.id or tostring(entity2)
        if id1 < id2 then
            return id1 .. "_" .. id2
        else
            return id2 .. "_" .. id1
        end
    end

    --- S12.1: Sync engagements from zone_system's authoritative state
    -- @param pairs table: Array of { entityA_id, entityB_id } pairs
    function arena:syncEngagements(pairs)
        -- Clear existing engagements and rebuild from authoritative source
        self.engagements = {}
        for _, pair in ipairs(pairs) do
            local id1, id2 = pair[1], pair[2]
            local key = (id1 < id2) and (id1 .. "_" .. id2) or (id2 .. "_" .. id1)
            self.engagements[key] = true
        end
    end

    ----------------------------------------------------------------------------
    -- VISIBILITY
    ----------------------------------------------------------------------------

    function arena:show()
        self.isVisible = true
    end

    function arena:hide()
        self.isVisible = false
        self.zones = {}
        self.entities = {}
        self.engagements = {}
        self.activeEntityId = nil

        -- S13.7: Clear tooltip when arena hides
        if self.inspectPanel then
            self.inspectPanel:onHoverEnd()
            self.inspectPanel:hide()
        end
        self.hoveredEntity = nil
    end

    function arena:setPosition(x, y)
        self.x = x
        self.y = y
        -- Recalculate zone positions
        if self.roomData then
            self:layoutZones(self.roomData.zones or self:getDefaultZones())
        end
    end

    function arena:resize(width, height)
        self.width = width
        self.height = height
        -- Recalculate zone positions
        if next(self.zones) then
            local zoneData = {}
            for _, zone in pairs(self.zones) do
                zoneData[#zoneData + 1] = { id = zone.id, name = zone.name, description = zone.description }
            end
            self:layoutZones(zoneData)
        end
    end

    --- S13.7: Set inspect panel reference (for late binding)
    function arena:setInspectPanel(panel)
        self.inspectPanel = panel
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    function arena:update(dt)
        -- S10.2: Update targeting reticle animation
        if self.targetingMode then
            self.targetReticleTimer = self.targetReticleTimer + dt
        end
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    ----------------------------------------------------------------------------

    function arena:setColor(color)
        local alpha = (color[4] or 1) * (self.alpha or 1)
        love.graphics.setColor(color[1], color[2], color[3], alpha)
    end

    function arena:setColorRGBA(r, g, b, a)
        local alpha = (a or 1) * (self.alpha or 1)
        love.graphics.setColor(r, g, b, alpha)
    end

    function arena:draw()
        if not love or not self.isVisible or (self.alpha or 0) <= 0 then return end

        -- S13.3: Draw zone adjacency lines (behind zones)
        self:drawAdjacencyLines()

        -- Draw zone buckets
        for _, zone in pairs(self.zones) do
            self:drawZone(zone)
        end

        -- Draw engagement lines
        self:drawEngagements()

        -- S10.2: Draw targeting indicators (behind tokens)
        if self.targetingMode then
            self:drawTargetingIndicators()
        end

        -- Draw entity tokens
        for _, zone in pairs(self.zones) do
            self:drawZoneEntities(zone)
        end

        -- Draw drag ghost
        if self.draggedEntity then
            self:drawDragGhost()
        end

        -- S13.4: Draw zone tooltip if hovering (after everything else)
        self:drawZoneTooltip()
    end

    --- Draw a zone bucket
    function arena:drawZone(zone)
        local colors = self.colors
        local isHovered = (self.hoveredZone == zone.id)
        local hasActiveEntity = false

        -- Check if active entity is in this zone
        for _, entity in ipairs(zone.entities) do
            if entity.id == self.activeEntityId then
                hasActiveEntity = true
                break
            end
        end

        -- S13.3: Check if this zone is adjacent to the hovered zone
        local isAdjacentToHovered = false
        if self.hoveredZone and self.hoveredZone ~= zone.id then
            if self.zoneSystem then
                isAdjacentToHovered = self.zoneSystem:areZonesAdjacent(self.hoveredZone, zone.id)
            else
                -- Fallback: assume all adjacent
                isAdjacentToHovered = true
            end
        end

        -- Background
        if hasActiveEntity then
            self:setColor(colors.zone_active)
        elseif isHovered and self.draggedEntity then
            self:setColor(colors.zone_hover)
        elseif isAdjacentToHovered then
            self:setColor(colors.zone_adjacent)
        else
            self:setColor(colors.zone_bg)
        end
        love.graphics.rectangle("fill", zone.x, zone.y, zone.width, zone.height, 6, 6)

        -- Border
        self:setColor(colors.zone_border)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", zone.x, zone.y, zone.width, zone.height, 6, 6)
        love.graphics.setLineWidth(1)

        -- Label
        self:drawZoneLabel(zone)
    end

    --- Draw zone label and description
    -- S13.4: Descriptions now shown inline within the zone
    function arena:drawZoneLabel(zone)
        local colors = self.colors
        local labelWidth = math.min(zone.width - 20, 120)
        local labelX = zone.x + (zone.width - labelWidth) / 2
        local labelY = zone.y + 5

        -- Label background
        self:setColor(colors.label_bg)
        love.graphics.rectangle("fill", labelX, labelY, labelWidth, M.ZONE_LABEL_HEIGHT, 3, 3)

        -- Label text
        self:setColor(colors.label_text)
        love.graphics.printf(zone.name, labelX, labelY + 4, labelWidth, "center")

        -- S13.4: Draw description below label (if present)
        if zone.description then
            local descX = zone.x + M.ZONE_PADDING
            local descY = zone.y + M.ZONE_LABEL_HEIGHT + 12
            local descWidth = zone.width - M.ZONE_PADDING * 2

            -- Draw description text (dark ink on parchment background)
            self:setColor(colors.desc_text)
            love.graphics.printf(zone.description, descX, descY, descWidth, "left")

            -- Calculate description height for entity positioning
            local font = love.graphics.getFont()
            local _, wrappedText = font:getWrap(zone.description, descWidth)
            zone._descHeight = #wrappedText * font:getHeight() + 8
        else
            zone._descHeight = 0
        end
    end

    --- Draw entities in a zone
    -- S13.4: Tokens now positioned below inline description
    function arena:drawZoneEntities(zone)
        local tokenSize = M.TOKEN_SIZE
        local spacing = M.TOKEN_SPACING

        -- S13.4: Account for description height when positioning tokens
        local descHeight = zone._descHeight or 0
        local startY = zone.y + M.ZONE_LABEL_HEIGHT + 15 + descHeight

        local contentWidth = zone.width - M.ZONE_PADDING * 2
        local contentX = zone.x + M.ZONE_PADDING

        -- Calculate grid layout for tokens
        local tokensPerRow = math.max(1, math.floor(contentWidth / (tokenSize + spacing)))

        for i, entity in ipairs(zone.entities) do
            local row = math.floor((i - 1) / tokensPerRow)
            local col = (i - 1) % tokensPerRow

            local tokenX = contentX + col * (tokenSize + spacing)
            local tokenY = startY + row * (tokenSize + spacing)

            -- Store token position for hit detection
            entity._tokenX = tokenX
            entity._tokenY = tokenY

            -- Draw token (skip if being dragged)
            if self.draggedEntity ~= entity then
                self:drawToken(entity, tokenX, tokenY, tokenSize)
            end
        end
    end

    --- Draw a tactical token
    function arena:drawToken(entity, x, y, size)
        local colors = self.colors
        local isPC = entity.isPC
        local isActive = (entity.id == self.activeEntityId)
        local isDead = entity.conditions and entity.conditions.dead

        -- Active glow
        if isActive then
            self:setColor(colors.token_active)
            love.graphics.circle("fill", x + size/2, y + size/2, size/2 + 4)
        end

        -- Token background
        if isDead then
            self:setColorRGBA(0.3, 0.3, 0.3, 0.7)
        elseif isPC then
            self:setColor(colors.token_pc)
        else
            self:setColor(colors.token_npc)
        end
        love.graphics.circle("fill", x + size/2, y + size/2, size/2)

        -- Border
        self:setColor(colors.token_border)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", x + size/2, y + size/2, size/2)
        love.graphics.setLineWidth(1)

        -- Initials or short name
        local initials = self:getInitials(entity.name or "??")
        self:setColor(colors.token_text)
        love.graphics.printf(initials, x, y + size/2 - 8, size, "center")

        -- Dead X
        if isDead then
            self:setColorRGBA(0.8, 0.2, 0.2, 0.9)
            love.graphics.setLineWidth(3)
            love.graphics.line(x + 5, y + 5, x + size - 5, y + size - 5)
            love.graphics.line(x + size - 5, y + 5, x + 5, y + size - 5)
            love.graphics.setLineWidth(1)
        end
    end

    --- Get initials from a name
    function arena:getInitials(name)
        local words = {}
        for word in name:gmatch("%S+") do
            words[#words + 1] = word
        end

        if #words >= 2 then
            return words[1]:sub(1, 1):upper() .. words[2]:sub(1, 1):upper()
        else
            return name:sub(1, 2):upper()
        end
    end

    --- Draw engagement lines between engaged entities
    function arena:drawEngagements()
        local colors = self.colors

        for key, _ in pairs(self.engagements) do
            -- Parse key to get entity IDs
            local id1, id2 = key:match("(.+)_(.+)")
            local data1 = self.entities[id1]
            local data2 = self.entities[id2]

            if data1 and data2 then
                local e1 = data1.entity
                local e2 = data2.entity

                -- Only draw if both have valid positions
                if e1._tokenX and e2._tokenX then
                    local x1 = e1._tokenX + M.TOKEN_SIZE / 2
                    local y1 = e1._tokenY + M.TOKEN_SIZE / 2
                    local x2 = e2._tokenX + M.TOKEN_SIZE / 2
                    local y2 = e2._tokenY + M.TOKEN_SIZE / 2

                    -- Draw clash line
                    self:setColor(colors.clash_line)
                    love.graphics.setLineWidth(3)
                    love.graphics.line(x1, y1, x2, y2)

                    -- Draw clash icon at midpoint
                    local midX = (x1 + x2) / 2
                    local midY = (y1 + y2) / 2

                    self:setColor(colors.clash_icon)
                    love.graphics.circle("fill", midX, midY, 8)
                    self:setColor(colors.token_border)
                    love.graphics.setLineWidth(2)
                    love.graphics.circle("line", midX, midY, 8)

                    -- Crossed swords icon (simplified)
                    self:setColorRGBA(1, 1, 1, 1)
                    love.graphics.line(midX - 4, midY - 4, midX + 4, midY + 4)
                    love.graphics.line(midX + 4, midY - 4, midX - 4, midY + 4)

                    love.graphics.setLineWidth(1)
                end
            end
        end
    end

    --- Draw drag ghost
    function arena:drawDragGhost()
        if not self.draggedEntity then return end

        local mx, my = love.mouse.getPosition()
        local x = mx - self.dragOffsetX
        local y = my - self.dragOffsetY

        self:setColor(self.colors.drag_ghost)
        self:drawToken(self.draggedEntity, x, y, M.TOKEN_SIZE)
    end

    --- S13.3: Draw adjacency lines between connected zones
    function arena:drawAdjacencyLines()
        local colors = self.colors
        local drawnPairs = {}  -- Track which pairs we've already drawn

        for zoneIdA, zoneA in pairs(self.zones) do
            -- Get adjacent zones (from zone_system if available, otherwise assume all adjacent)
            local adjacentZones = {}
            if self.zoneSystem then
                adjacentZones = self.zoneSystem:getAdjacentZones(zoneIdA)
            else
                -- Fallback: all zones are adjacent to each other
                for zoneIdB, _ in pairs(self.zones) do
                    if zoneIdB ~= zoneIdA then
                        adjacentZones[#adjacentZones + 1] = zoneIdB
                    end
                end
            end

            for _, zoneIdB in ipairs(adjacentZones) do
                local zoneB = self.zones[zoneIdB]
                if zoneB then
                    -- Create unique key for this pair to avoid drawing twice
                    local pairKey = (zoneIdA < zoneIdB) and (zoneIdA .. "_" .. zoneIdB) or (zoneIdB .. "_" .. zoneIdA)

                    if not drawnPairs[pairKey] then
                        drawnPairs[pairKey] = true

                        -- Calculate center points of each zone
                        local ax = zoneA.x + zoneA.width / 2
                        local ay = zoneA.y + zoneA.height / 2
                        local bx = zoneB.x + zoneB.width / 2
                        local by = zoneB.y + zoneB.height / 2

                        -- Check if either zone is hovered (highlight the line)
                        local isHighlighted = (self.hoveredZone == zoneIdA or self.hoveredZone == zoneIdB)

                        if isHighlighted then
                            self:setColor(colors.adjacency_hover)
                            love.graphics.setLineWidth(3)
                        else
                            self:setColor(colors.adjacency_line)
                            love.graphics.setLineWidth(2)
                        end

                        -- Draw dashed line effect
                        local dashLength = 8
                        local gapLength = 4
                        local dx = bx - ax
                        local dy = by - ay
                        local dist = math.sqrt(dx * dx + dy * dy)
                        local ux, uy = dx / dist, dy / dist

                        local pos = 0
                        while pos < dist do
                            local endPos = math.min(pos + dashLength, dist)
                            love.graphics.line(
                                ax + ux * pos, ay + uy * pos,
                                ax + ux * endPos, ay + uy * endPos
                            )
                            pos = endPos + gapLength
                        end

                        love.graphics.setLineWidth(1)
                    end
                end
            end
        end
    end

    --- S13.4: Draw tooltip for hovered zone (only for zones without inline descriptions)
    -- Note: Most zones now show descriptions inline; this is kept for POI/interaction hints
    function arena:drawZoneTooltip()
        -- S13.4: Descriptions now displayed inline within zones
        -- This tooltip could be used for additional info like POIs in the zone
        -- For now, no-op since descriptions are always visible
    end

    ----------------------------------------------------------------------------
    -- INPUT HANDLING
    ----------------------------------------------------------------------------

    function arena:mousepressed(x, y, button)
        if not self.isVisible then return false end

        -- S13.7: Right-click to show entity tooltip immediately
        if button == 2 then
            local entity = self:getEntityAt(x, y)
            if entity and self.inspectPanel then
                local tokenX = entity._tokenX or x
                local tokenY = entity._tokenY or y
                self.inspectPanel:onRightClick(entity, "entity", tokenX + M.TOKEN_SIZE + 5, tokenY)
                return true
            end
            return false
        end

        if button ~= 1 then return false end

        -- Check if clicking on a token
        local entity = self:getEntityAt(x, y)
        if entity then
            -- S13.7: Hide tooltip when clicking a token
            if self.inspectPanel then
                self.inspectPanel:onHoverEnd()
                self.inspectPanel:hide()
            end

            self.eventBus:emit(events.EVENTS.ARENA_ENTITY_CLICKED, {
                entity = entity,
                x = x,
                y = y,
            })
            return true
        end

        -- Check if clicking on a zone (for move selection)
        local zoneId = self:getZoneAt(x, y)
        if zoneId then
            self.eventBus:emit(events.EVENTS.ARENA_ZONE_CLICKED, {
                zoneId = zoneId,
                x = x,
                y = y,
            })
            return true
        end

        return false
    end

    function arena:mousereleased(x, y, button)
        if not self.isVisible then return false end
        if button ~= 1 then return false end

        return false
    end

    function arena:mousemoved(x, y, dx, dy)
        if not self.isVisible then return end

        -- S13.3/S13.4: Always track hovered zone for adjacency highlighting and tooltips
        self.hoveredZone = self:getZoneAt(x, y)

        -- S13.7: Always track hovered entity for tooltips (not just targeting mode)
        local newHoveredEntity = self:getEntityAt(x, y)

        -- Notify inspect panel of hover changes
        if newHoveredEntity ~= self.hoveredEntity then
            if newHoveredEntity and self.inspectPanel then
                -- Started hovering over an entity
                local tokenX = newHoveredEntity._tokenX or x
                local tokenY = newHoveredEntity._tokenY or y
                self.inspectPanel:onHover(newHoveredEntity, "entity", tokenX + M.TOKEN_SIZE + 5, tokenY)
            elseif self.hoveredEntity and self.inspectPanel then
                -- Stopped hovering
                self.inspectPanel:onHoverEnd()
            end
        end

        self.hoveredEntity = newHoveredEntity
    end

    --- Check if a point is inside a token
    function arena:isInsideToken(px, py, tokenX, tokenY)
        local cx = tokenX + M.TOKEN_SIZE / 2
        local cy = tokenY + M.TOKEN_SIZE / 2
        local dx = px - cx
        local dy = py - cy
        return (dx * dx + dy * dy) <= (M.TOKEN_SIZE / 2) * (M.TOKEN_SIZE / 2)
    end

    --- Get zone at a position
    function arena:getZoneAt(x, y)
        for zoneId, zone in pairs(self.zones) do
            if x >= zone.x and x <= zone.x + zone.width and
               y >= zone.y and y <= zone.y + zone.height then
                return zoneId
            end
        end
        return nil
    end

    ----------------------------------------------------------------------------
    -- TARGETING MODE (S10.2)
    ----------------------------------------------------------------------------

    --- Enter targeting mode
    -- @param validTargetIds table: Array of valid target entity IDs
    function arena:enterTargetingMode(validTargetIds)
        self.targetingMode = true
        self.validTargets = validTargetIds or {}
        self.targetReticleTimer = 0
        print("[ArenaView] Entered targeting mode with " .. #self.validTargets .. " valid targets")
    end

    --- Exit targeting mode
    function arena:exitTargetingMode()
        self.targetingMode = false
        self.validTargets = {}
    end

    --- Check if an entity is a valid target
    function arena:isValidTarget(entityId)
        for _, id in ipairs(self.validTargets) do
            if id == entityId then
                return true
            end
        end
        return false
    end

    --- Get entity at position
    -- S13.7: Fixed to iterate properly and use stored token positions
    function arena:getEntityAt(x, y)
        -- Iterate through all zones and their entities
        for _, zone in pairs(self.zones) do
            for _, entity in ipairs(zone.entities) do
                -- Use stored token positions from last draw
                if entity._tokenX and entity._tokenY then
                    if self:isInsideToken(x, y, entity._tokenX, entity._tokenY) then
                        return entity
                    end
                end
            end
        end
        return nil
    end

    --- Get index of entity within its zone (for positioning)
    function arena:getEntityIndexInZone(entity, zoneId)
        local index = 0
        for _, e in ipairs(self.entities) do
            if (e.zone or "main") == zoneId then
                index = index + 1
                if e.id == entity.id then
                    return index
                end
            end
        end
        return 1
    end

    --- Draw targeting reticle on entity token
    function arena:drawTargetingReticle(tokenX, tokenY, isValid)
        local cx = tokenX + M.TOKEN_SIZE / 2
        local cy = tokenY + M.TOKEN_SIZE / 2
        local radius = M.TOKEN_SIZE / 2 + 8

        -- Animated pulse
        local pulse = math.sin(self.targetReticleTimer * 6) * 0.2 + 0.8

        -- Color based on validity
        local color = isValid and self.colors.target_valid or self.colors.target_reticle

        -- Outer ring (pulsing)
        self:setColorRGBA(color[1], color[2], color[3], (color[4] or 1) * pulse)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", cx, cy, radius)

        -- Crosshairs
        local crossSize = 8
        self:setColorRGBA(color[1], color[2], color[3], color[4] or 1)
        love.graphics.setLineWidth(2)
        -- Top
        love.graphics.line(cx, cy - radius - 5, cx, cy - radius + crossSize)
        -- Bottom
        love.graphics.line(cx, cy + radius + 5, cx, cy + radius - crossSize)
        -- Left
        love.graphics.line(cx - radius - 5, cy, cx - radius + crossSize, cy)
        -- Right
        love.graphics.line(cx + radius + 5, cy, cx + radius - crossSize, cy)

        love.graphics.setLineWidth(1)
    end

    --- Draw targeting indicators on all valid targets
    function arena:drawTargetingIndicators()
        if not self.targetingMode then return end

        for _, targetId in ipairs(self.validTargets) do
            for _, entity in ipairs(self.entities) do
                if entity.id == targetId then
                    local zoneId = entity.zone or "main"
                    local zone = self.zones[zoneId]
                    if zone then
                        local tokenIndex = self:getEntityIndexInZone(entity, zoneId)
                        local tokenX, tokenY = self:getTokenPosition(zone, tokenIndex)

                        -- Draw pulsing ring indicator on valid targets
                        local cx = tokenX + M.TOKEN_SIZE / 2
                        local cy = tokenY + M.TOKEN_SIZE / 2
                        local pulse = math.sin(self.targetReticleTimer * 4) * 0.3 + 0.7

                        self:setColorRGBA(self.colors.target_valid[1],
                                          self.colors.target_valid[2],
                                          self.colors.target_valid[3],
                                          pulse * 0.5)
                        love.graphics.circle("fill", cx, cy, M.TOKEN_SIZE / 2 + 6)
                    end
                end
            end
        end

        -- Draw reticle on hovered entity
        if self.hoveredEntity then
            local zoneId = self.hoveredEntity.zone or "main"
            local zone = self.zones[zoneId]
            if zone then
                local tokenIndex = self:getEntityIndexInZone(self.hoveredEntity, zoneId)
                local tokenX, tokenY = self:getTokenPosition(zone, tokenIndex)
                local isValid = self:isValidTarget(self.hoveredEntity.id)
                self:drawTargetingReticle(tokenX, tokenY, isValid)
            end
        end
    end

    return arena
end

return M
