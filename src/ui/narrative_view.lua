-- narrative_view.lua
-- Narrative Feed / POI Scrawler for Majesty
-- Ticket T2_12: Render room descriptions with POI highlighting
--
-- Design:
-- - Parse "Rich Text" with POI markers: {poi:id:Display Text}
-- - Render POIs in a different color
-- - Track screen-space coordinates for hitbox registration
-- - Optional typewriter effect

local events = require('logic.events')

local M = {}

--------------------------------------------------------------------------------
-- RICH TEXT TOKEN TYPES
--------------------------------------------------------------------------------
M.TOKEN_TYPES = {
    TEXT = "text",
    POI  = "poi",
}

--------------------------------------------------------------------------------
-- DEFAULT COLORS
--------------------------------------------------------------------------------
M.COLORS = {
    text       = { 0.9, 0.9, 0.85, 1.0 },   -- Off-white for normal text
    poi        = { 0.4, 0.8, 1.0, 1.0 },    -- Cyan for POIs
    poi_hover  = { 0.6, 1.0, 1.0, 1.0 },    -- Brighter cyan on hover
    background = { 0.1, 0.1, 0.12, 0.95 },  -- Dark background
}

--------------------------------------------------------------------------------
-- RICH TEXT PARSER
-- Parses strings like: "A heavy {poi:chest_01:ancient chest} sits here."
--------------------------------------------------------------------------------

--- Parse rich text into tokens
-- @param text string: Raw text with {poi:id:display} markers
-- @return table: Array of { type, text, poiId? }
function M.parseRichText(text)
    local tokens = {}
    local pos = 1
    local len = #text

    while pos <= len do
        -- Look for POI marker
        local startPos = text:find("{poi:", pos, true)

        if startPos then
            -- Add any text before the marker
            if startPos > pos then
                local plainText = text:sub(pos, startPos - 1)
                tokens[#tokens + 1] = {
                    type = M.TOKEN_TYPES.TEXT,
                    text = plainText,
                }
            end

            -- Parse the POI marker: {poi:id:display}
            local endPos = text:find("}", startPos, true)
            if endPos then
                local markerContent = text:sub(startPos + 5, endPos - 1)  -- Skip "{poi:"
                local colonPos = markerContent:find(":", 1, true)

                if colonPos then
                    local poiId = markerContent:sub(1, colonPos - 1)
                    local displayText = markerContent:sub(colonPos + 1)

                    tokens[#tokens + 1] = {
                        type = M.TOKEN_TYPES.POI,
                        text = displayText,
                        poiId = poiId,
                    }
                else
                    -- Malformed marker, treat as text
                    tokens[#tokens + 1] = {
                        type = M.TOKEN_TYPES.TEXT,
                        text = text:sub(startPos, endPos),
                    }
                end

                pos = endPos + 1
            else
                -- No closing brace, treat rest as text
                tokens[#tokens + 1] = {
                    type = M.TOKEN_TYPES.TEXT,
                    text = text:sub(startPos),
                }
                break
            end
        else
            -- No more markers, add remaining text
            tokens[#tokens + 1] = {
                type = M.TOKEN_TYPES.TEXT,
                text = text:sub(pos),
            }
            break
        end
    end

    return tokens
end

--------------------------------------------------------------------------------
-- NARRATIVE VIEW FACTORY
--------------------------------------------------------------------------------

--- Create a new NarrativeView
-- @param config table: { x, y, width, height, font, inputManager, eventBus }
-- @return NarrativeView instance
function M.createNarrativeView(config)
    config = config or {}

    local view = {
        -- Position and size
        x      = config.x or 0,
        y      = config.y or 0,
        width  = config.width or 400,
        height = config.height or 300,

        -- Font (LÖVE font object, or nil for default)
        font       = config.font,
        lineHeight = config.lineHeight or 20,
        padding    = config.padding or 10,

        -- Colors
        colors = config.colors or M.COLORS,

        -- References
        inputManager = config.inputManager,
        eventBus     = config.eventBus or events.globalBus,

        -- Current content
        tokens       = {},          -- Parsed tokens
        rawText      = "",          -- Original text
        poiHitboxes  = {},          -- POI id -> { x, y, width, height }

        -- Typewriter effect
        typewriterEnabled = config.typewriterEnabled or false,
        typewriterSpeed   = config.typewriterSpeed or 30,  -- chars per second
        typewriterPos     = 0,       -- Current character position
        typewriterTime    = 0,       -- Accumulated time

        -- Hover state
        hoveredPOI = nil,

        -- Layout visibility (for stage fades)
        alpha = 1,
        isVisible = true,
    }

    ----------------------------------------------------------------------------
    -- CONTENT MANAGEMENT
    ----------------------------------------------------------------------------

    --- Set the narrative text
    -- @param text string: Rich text with POI markers
    -- @param instant boolean: If true, skip typewriter effect
    function view:setText(text, instant)
        self.rawText = text
        self.tokens = M.parseRichText(text)
        self.poiHitboxes = {}

        if self.typewriterEnabled and not instant then
            self.typewriterPos = 0
            self.typewriterTime = 0
        else
            self.typewriterPos = #text
        end

        -- Recalculate hitboxes
        self:calculateHitboxes()
    end

    --- Append text to current content
    function view:appendText(text)
        self:setText(self.rawText .. text)
    end

    --- Clear all content
    function view:clear()
        self.rawText = ""
        self.tokens = {}
        self.poiHitboxes = {}
        self.typewriterPos = 0

        -- Unregister hitboxes from input manager
        if self.inputManager then
            for poiId, _ in pairs(self.poiHitboxes) do
                self.inputManager:unregisterHitbox(poiId)
            end
        end
    end

    ----------------------------------------------------------------------------
    -- HITBOX CALCULATION
    -- Calculate screen positions for POI text areas
    ----------------------------------------------------------------------------

    --- Calculate hitboxes for all POIs
    function view:calculateHitboxes()
        -- Clear old hitboxes from input manager
        if self.inputManager then
            for poiId, _ in pairs(self.poiHitboxes) do
                self.inputManager:unregisterHitbox(poiId)
            end
        end

        self.poiHitboxes = {}

        -- Simulate text layout to find POI positions
        local x = self.x + self.padding
        local y = self.y + self.padding
        local maxWidth = self.width - (self.padding * 2)

        -- Get font metrics (use default values if not in LÖVE context)
        local charWidth = 8   -- Approximate
        local charHeight = self.lineHeight
        local spaceWidth = charWidth

        if love then
            local font = self.font or love.graphics.getFont()
            if font then
                charHeight = font:getHeight()
                charWidth = font:getWidth("M")
                spaceWidth = font:getWidth(" ")
            end
        end

        for _, token in ipairs(self.tokens) do
            local text = token.text

            -- Split by newlines first (matching draw logic)
            local lines = {}
            local currentPos = 1
            while currentPos <= #text do
                local newlinePos = text:find("\n", currentPos, true)
                if newlinePos then
                    lines[#lines + 1] = text:sub(currentPos, newlinePos - 1)
                    currentPos = newlinePos + 1
                else
                    lines[#lines + 1] = text:sub(currentPos)
                    break
                end
            end

            -- Track POI start position (for multi-word POIs)
            local poiStartX = x
            local poiStartY = y

            for lineIdx, line in ipairs(lines) do
                -- Process words in this line
                for word in line:gmatch("%S+") do
                    local wordWidth = #word * charWidth
                    if love then
                        local font = self.font or love.graphics.getFont()
                        if font then
                            wordWidth = font:getWidth(word)
                        end
                    end

                    -- Check for line wrap
                    if x + wordWidth > self.x + maxWidth then
                        x = self.x + self.padding
                        y = y + charHeight
                    end

                    -- Advance position
                    x = x + wordWidth + spaceWidth
                end

                -- Move to next line if there are more lines
                if lineIdx < #lines then
                    x = self.x + self.padding
                    y = y + charHeight
                end
            end

            -- If this is a POI token, record hitbox for entire POI
            if token.type == M.TOKEN_TYPES.POI then
                -- Calculate POI width (simple approximation)
                local poiWidth = 0
                if love then
                    local font = self.font or love.graphics.getFont()
                    if font then
                        -- Get width of POI text without newlines
                        local cleanText = token.text:gsub("\n", " ")
                        poiWidth = font:getWidth(cleanText)
                    end
                else
                    poiWidth = #token.text * charWidth
                end

                self.poiHitboxes[token.poiId] = {
                    x = poiStartX,
                    y = poiStartY,
                    width = poiWidth,
                    height = charHeight,
                }

                -- Register with input manager
                if self.inputManager then
                    self.inputManager:registerHitbox(
                        token.poiId,
                        "poi",
                        poiStartX, poiStartY, poiWidth, charHeight,
                        { poiId = token.poiId, displayText = token.text }
                    )
                end
            end
        end
    end

    ----------------------------------------------------------------------------
    -- UPDATE
    ----------------------------------------------------------------------------

    --- Update the view (for typewriter effect)
    -- @param dt number: Delta time in seconds
    function view:update(dt)
        -- Typewriter effect
        if self.typewriterEnabled and self.typewriterPos < #self.rawText then
            self.typewriterTime = self.typewriterTime + dt
            local charsToShow = math.floor(self.typewriterTime * self.typewriterSpeed)
            self.typewriterPos = math.min(charsToShow, #self.rawText)
        end

        -- Check for hover (if input manager tracks mouse position)
        if self.inputManager then
            local mx = self.inputManager.currentMouseX
            local my = self.inputManager.currentMouseY

            self.hoveredPOI = nil
            for poiId, hb in pairs(self.poiHitboxes) do
                if mx >= hb.x and mx <= hb.x + hb.width and
                   my >= hb.y and my <= hb.y + hb.height then
                    self.hoveredPOI = poiId
                    break
                end
            end
        end
    end

    ----------------------------------------------------------------------------
    -- RENDERING
    -- Note: Actual rendering requires LÖVE 2D context
    ----------------------------------------------------------------------------

    --- Draw the narrative view
    -- Call this from love.draw()
    function view:draw()
        if not love or not self.isVisible or (self.alpha or 0) <= 0 then
            return  -- Can't draw without LÖVE
        end
        local alpha = self.alpha or 1
        local function setColor(color)
            love.graphics.setColor(color[1], color[2], color[3], (color[4] or 1) * alpha)
        end

        -- Draw background
        setColor(self.colors.background)
        love.graphics.rectangle("fill", self.x, self.y, self.width, self.height)

        -- Set font
        local oldFont = love.graphics.getFont()
        if self.font then
            love.graphics.setFont(self.font)
        end

        -- Draw text with POI highlighting
        local x = self.x + self.padding
        local y = self.y + self.padding
        local maxWidth = self.width - (self.padding * 2)
        local charHeight = love.graphics.getFont():getHeight()
        local charsDrawn = 0

        for _, token in ipairs(self.tokens) do
            -- Check typewriter limit
            if charsDrawn >= self.typewriterPos then
                break
            end

            -- Set color based on token type
            if token.type == M.TOKEN_TYPES.POI then
                if self.hoveredPOI == token.poiId then
                    setColor(self.colors.poi_hover)
                else
                    setColor(self.colors.poi)
                end
            else
                setColor(self.colors.text)
            end

            -- Draw text with proper newline and word wrapping
            local text = token.text
            local remainingChars = self.typewriterPos - charsDrawn

            -- Truncate for typewriter
            if #text > remainingChars then
                text = text:sub(1, remainingChars)
            end

            -- Split by newlines first
            local lines = {}
            local currentPos = 1
            while currentPos <= #text do
                local newlinePos = text:find("\n", currentPos, true)
                if newlinePos then
                    lines[#lines + 1] = text:sub(currentPos, newlinePos - 1)
                    currentPos = newlinePos + 1
                else
                    lines[#lines + 1] = text:sub(currentPos)
                    break
                end
            end

            for lineIdx, line in ipairs(lines) do
                -- Process words in this line
                for word in line:gmatch("%S+") do
                    local wordWidth = love.graphics.getFont():getWidth(word)
                    local spaceWidth = love.graphics.getFont():getWidth(" ")

                    -- Line wrap
                    if x + wordWidth > self.x + maxWidth then
                        x = self.x + self.padding
                        y = y + charHeight
                    end

                    -- Draw word
                    love.graphics.print(word, x, y)
                    x = x + wordWidth + spaceWidth
                end

                -- Move to next line if there are more lines (newline was in original text)
                if lineIdx < #lines then
                    x = self.x + self.padding
                    y = y + charHeight
                end
            end

            charsDrawn = charsDrawn + #token.text
        end

        -- Restore font
        if oldFont then
            love.graphics.setFont(oldFont)
        end
    end

    ----------------------------------------------------------------------------
    -- UTILITY
    ----------------------------------------------------------------------------

    --- Get POI at screen position
    function view:getPOIAt(screenX, screenY)
        for poiId, hb in pairs(self.poiHitboxes) do
            if screenX >= hb.x and screenX <= hb.x + hb.width and
               screenY >= hb.y and screenY <= hb.y + hb.height then
                return poiId
            end
        end
        return nil
    end

    --- Check if typewriter effect is complete
    function view:isTypewriterComplete()
        return self.typewriterPos >= #self.rawText
    end

    --- Set visibility and manage POI hitboxes
    function view:setVisible(visible)
        if self.isVisible == visible then return end
        self.isVisible = visible

        if not visible and self.inputManager then
            for poiId, _ in pairs(self.poiHitboxes) do
                self.inputManager:unregisterHitbox(poiId)
            end
        elseif visible then
            self:calculateHitboxes()
        end
    end

    --- Skip to end of typewriter effect
    function view:skipTypewriter()
        self.typewriterPos = #self.rawText
    end

    --- Resize the view
    function view:resize(width, height)
        self.width = width
        self.height = height
        self:calculateHitboxes()
    end

    --- Move the view
    function view:setPosition(x, y)
        self.x = x
        self.y = y
        self:calculateHitboxes()
    end

    return view
end

return M
