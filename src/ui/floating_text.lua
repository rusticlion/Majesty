-- floating_text.lua
-- Floating Text System for Majesty
-- Ticket S10.2: Damage numbers and combat feedback
--
-- Creates animated text that floats upward and fades out.
-- Used for damage numbers, healing, status effects, etc.

local M = {}

--------------------------------------------------------------------------------
-- TEXT TYPES & COLORS
--------------------------------------------------------------------------------
M.TYPES = {
    DAMAGE        = "damage",
    HEAL          = "heal",
    BLOCK         = "block",
    MISS          = "miss",
    CRITICAL      = "critical",
    CONDITION     = "condition",
    BONUS         = "bonus",
    INFO          = "info",
}

M.COLORS = {
    [M.TYPES.DAMAGE]    = { 0.90, 0.30, 0.25, 1.0 },   -- Red
    [M.TYPES.HEAL]      = { 0.35, 0.75, 0.40, 1.0 },   -- Green
    [M.TYPES.BLOCK]     = { 0.70, 0.65, 0.55, 1.0 },   -- Grey/bronze
    [M.TYPES.MISS]      = { 0.60, 0.60, 0.60, 1.0 },   -- Grey
    [M.TYPES.CRITICAL]  = { 1.00, 0.85, 0.20, 1.0 },   -- Gold
    [M.TYPES.CONDITION] = { 0.80, 0.60, 0.90, 1.0 },   -- Purple
    [M.TYPES.BONUS]     = { 0.50, 0.80, 0.95, 1.0 },   -- Blue
    [M.TYPES.INFO]      = { 0.90, 0.90, 0.85, 1.0 },   -- White
}

--------------------------------------------------------------------------------
-- ANIMATION CONSTANTS
--------------------------------------------------------------------------------
M.FLOAT_SPEED = 50      -- Pixels per second
M.DURATION = 1.2        -- Seconds before fully faded
M.FADE_START = 0.6      -- When to start fading (percentage of duration)
M.SCALE_BOUNCE = 0.15   -- Initial scale bounce amount
M.BOUNCE_DURATION = 0.2 -- Duration of scale bounce

--------------------------------------------------------------------------------
-- FLOATING TEXT MANAGER
--------------------------------------------------------------------------------

local manager = {
    texts = {},  -- Array of active floating texts
}

--------------------------------------------------------------------------------
-- TEXT SPAWNING
--------------------------------------------------------------------------------

--- Spawn a floating text
-- @param text string: The text to display
-- @param x number: Starting X position (screen coordinates)
-- @param y number: Starting Y position (screen coordinates)
-- @param textType string: One of TYPES constants
-- @param options table: { scale, duration, floatSpeed }
function M.spawn(text, x, y, textType, options)
    options = options or {}

    local floatingText = {
        text = text,
        x = x,
        y = y,
        startY = y,
        textType = textType or M.TYPES.INFO,
        color = M.COLORS[textType] or M.COLORS[M.TYPES.INFO],

        -- Animation state
        timer = 0,
        duration = options.duration or M.DURATION,
        floatSpeed = options.floatSpeed or M.FLOAT_SPEED,
        scale = 1.0 + M.SCALE_BOUNCE,
        alpha = 1.0,

        -- Visual options
        baseScale = options.scale or 1.0,
        outline = options.outline ~= false,  -- Default true
    }

    manager.texts[#manager.texts + 1] = floatingText

    return floatingText
end

--- Spawn damage number at entity position
-- @param amount number: Damage amount
-- @param entityX number: Entity's X position
-- @param entityY number: Entity's Y position
-- @param isCritical boolean: Is this a critical hit?
function M.spawnDamage(amount, entityX, entityY, isCritical)
    local textType = isCritical and M.TYPES.CRITICAL or M.TYPES.DAMAGE
    local text = "-" .. tostring(amount)
    if isCritical then
        text = "CRIT! " .. text
    end

    -- Add some horizontal scatter
    local offsetX = (math.random() - 0.5) * 30
    M.spawn(text, entityX + offsetX, entityY - 20, textType, {
        scale = isCritical and 1.3 or 1.0,
    })
end

--- Spawn healing number
function M.spawnHeal(amount, entityX, entityY)
    local text = "+" .. tostring(amount)
    local offsetX = (math.random() - 0.5) * 30
    M.spawn(text, entityX + offsetX, entityY - 20, M.TYPES.HEAL)
end

--- Spawn block indicator
function M.spawnBlock(entityX, entityY)
    M.spawn("BLOCK", entityX, entityY - 20, M.TYPES.BLOCK)
end

--- Spawn miss indicator
function M.spawnMiss(entityX, entityY)
    M.spawn("MISS", entityX, entityY - 20, M.TYPES.MISS)
end

--- Spawn condition text
function M.spawnCondition(conditionName, entityX, entityY)
    local text = string.upper(conditionName)
    M.spawn(text, entityX, entityY - 25, M.TYPES.CONDITION)
end

--- Spawn bonus/modifier text
function M.spawnBonus(text, entityX, entityY)
    M.spawn(text, entityX, entityY - 30, M.TYPES.BONUS)
end

--------------------------------------------------------------------------------
-- UPDATE & DRAW
--------------------------------------------------------------------------------

--- Update all floating texts
-- @param dt number: Delta time
function M.update(dt)
    -- Update each text and remove expired ones
    local i = 1
    while i <= #manager.texts do
        local ft = manager.texts[i]
        ft.timer = ft.timer + dt

        -- Float upward
        ft.y = ft.startY - (ft.timer * ft.floatSpeed)

        -- Scale bounce (shrink back to normal)
        if ft.timer < M.BOUNCE_DURATION then
            local bounceProgress = ft.timer / M.BOUNCE_DURATION
            ft.scale = ft.baseScale + M.SCALE_BOUNCE * (1 - bounceProgress)
        else
            ft.scale = ft.baseScale
        end

        -- Fade out
        local fadeStart = ft.duration * M.FADE_START
        if ft.timer > fadeStart then
            local fadeProgress = (ft.timer - fadeStart) / (ft.duration - fadeStart)
            ft.alpha = 1 - fadeProgress
        end

        -- Remove if expired
        if ft.timer >= ft.duration then
            table.remove(manager.texts, i)
        else
            i = i + 1
        end
    end
end

--- Draw all floating texts
function M.draw()
    if not love then return end

    for _, ft in ipairs(manager.texts) do
        local r, g, b = ft.color[1], ft.color[2], ft.color[3]
        local a = ft.alpha

        -- Draw outline for readability
        if ft.outline then
            love.graphics.setColor(0, 0, 0, a * 0.7)
            for ox = -1, 1 do
                for oy = -1, 1 do
                    if ox ~= 0 or oy ~= 0 then
                        love.graphics.print(
                            ft.text,
                            ft.x + ox,
                            ft.y + oy,
                            0,
                            ft.scale, ft.scale
                        )
                    end
                end
            end
        end

        -- Draw main text
        love.graphics.setColor(r, g, b, a)
        love.graphics.print(ft.text, ft.x, ft.y, 0, ft.scale, ft.scale)
    end
end

--- Clear all floating texts
function M.clear()
    manager.texts = {}
end

--- Get count of active texts
function M.getCount()
    return #manager.texts
end

return M
