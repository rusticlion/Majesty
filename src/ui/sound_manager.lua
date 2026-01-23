-- sound_manager.lua
-- Sound Manager for Majesty
-- Ticket S10.2: Audio architecture stubs
--
-- Placeholder implementation that logs sound requests.
-- Replace with actual audio loading when assets are available.

local M = {}

--------------------------------------------------------------------------------
-- SOUND TYPES
--------------------------------------------------------------------------------
M.SOUNDS = {
    -- Combat
    SWORD_HIT     = "sword_hit",
    SWORD_MISS    = "sword_miss",
    ARROW_FIRE    = "arrow_fire",
    ARROW_HIT     = "arrow_hit",
    BLOCK         = "block",
    DODGE         = "dodge",
    CRITICAL_HIT  = "critical_hit",

    -- Cards
    CARD_FLIP     = "card_flip",
    CARD_PLAY     = "card_play",
    CARD_DRAW     = "card_draw",
    CARD_SHUFFLE  = "card_shuffle",

    -- UI
    BUTTON_CLICK  = "button_click",
    BUTTON_HOVER  = "button_hover",
    MENU_OPEN     = "menu_open",
    MENU_CLOSE    = "menu_close",

    -- Combat events
    TURN_START    = "turn_start",
    ROUND_START   = "round_start",
    VICTORY       = "victory",
    DEFEAT        = "defeat",

    -- Conditions
    STAGGERED     = "staggered",
    INJURED       = "injured",
    DEATHS_DOOR   = "deaths_door",
    DEATH         = "death",

    -- Ambience
    DUNGEON_AMBIENT = "dungeon_ambient",
    CAMP_FIRE       = "camp_fire",
    COMBAT_MUSIC    = "combat_music",
}

--------------------------------------------------------------------------------
-- SOUND MANAGER SINGLETON
--------------------------------------------------------------------------------

local soundManager = {
    enabled = true,
    volume = 1.0,
    musicVolume = 0.7,
    sfxVolume = 1.0,

    -- Loaded sounds cache
    sounds = {},

    -- Currently playing music
    currentMusic = nil,

    -- Debug mode - logs all sound requests
    debug = true,
}

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

--- Initialize the sound manager
function M.init()
    -- In a full implementation, this would load sound files
    -- For now, just set up the structure
    print("[SoundManager] Initialized (stub mode)")
end

--------------------------------------------------------------------------------
-- SOUND PLAYBACK
--------------------------------------------------------------------------------

--- Play a sound effect
-- @param soundId string: One of SOUNDS constants
-- @param options table: { volume, pitch, loop }
function M.play(soundId, options)
    options = options or {}

    if not soundManager.enabled then return end

    local volume = (options.volume or 1.0) * soundManager.sfxVolume * soundManager.volume

    if soundManager.debug then
        print("[SoundManager] Play: " .. soundId .. " (vol: " .. string.format("%.2f", volume) .. ")")
    end

    -- In full implementation:
    -- local sound = soundManager.sounds[soundId]
    -- if sound then
    --     sound:setVolume(volume)
    --     if options.pitch then sound:setPitch(options.pitch) end
    --     sound:play()
    -- end
end

--- Play background music
-- @param musicId string: Music track ID
-- @param fadeIn number: Fade in time in seconds (optional)
function M.playMusic(musicId, fadeIn)
    if not soundManager.enabled then return end

    if soundManager.debug then
        print("[SoundManager] Music: " .. musicId)
    end

    soundManager.currentMusic = musicId

    -- In full implementation:
    -- if soundManager.currentMusic then
    --     soundManager.currentMusic:stop()
    -- end
    -- local music = soundManager.sounds[musicId]
    -- if music then
    --     music:setLooping(true)
    --     music:setVolume(soundManager.musicVolume * soundManager.volume)
    --     music:play()
    --     soundManager.currentMusic = music
    -- end
end

--- Stop current music
-- @param fadeOut number: Fade out time in seconds (optional)
function M.stopMusic(fadeOut)
    if soundManager.debug then
        print("[SoundManager] Stop music")
    end
    soundManager.currentMusic = nil
end

--------------------------------------------------------------------------------
-- CONVENIENCE METHODS
--------------------------------------------------------------------------------

--- Play combat hit sound based on weapon type
function M.playCombatHit(weaponType, isCritical)
    if isCritical then
        M.play(M.SOUNDS.CRITICAL_HIT)
    elseif weaponType == "bow" or weaponType == "crossbow" then
        M.play(M.SOUNDS.ARROW_HIT)
    else
        M.play(M.SOUNDS.SWORD_HIT)
    end
end

--- Play combat miss sound
function M.playCombatMiss(wasBlocked)
    if wasBlocked then
        M.play(M.SOUNDS.BLOCK)
    else
        M.play(M.SOUNDS.SWORD_MISS)
    end
end

--- Play card sound
function M.playCardSound(action)
    if action == "draw" then
        M.play(M.SOUNDS.CARD_DRAW)
    elseif action == "play" then
        M.play(M.SOUNDS.CARD_PLAY)
    elseif action == "flip" then
        M.play(M.SOUNDS.CARD_FLIP)
    elseif action == "shuffle" then
        M.play(M.SOUNDS.CARD_SHUFFLE)
    end
end

--- Play condition sound
function M.playConditionSound(condition)
    local conditionSounds = {
        staggered = M.SOUNDS.STAGGERED,
        injured = M.SOUNDS.INJURED,
        deaths_door = M.SOUNDS.DEATHS_DOOR,
        dead = M.SOUNDS.DEATH,
    }
    local soundId = conditionSounds[condition]
    if soundId then
        M.play(soundId)
    end
end

--------------------------------------------------------------------------------
-- SETTINGS
--------------------------------------------------------------------------------

--- Enable/disable all sounds
function M.setEnabled(enabled)
    soundManager.enabled = enabled
    print("[SoundManager] Sound " .. (enabled and "enabled" or "disabled"))
end

--- Set master volume (0.0 - 1.0)
function M.setVolume(volume)
    soundManager.volume = math.max(0, math.min(1, volume))
end

--- Set music volume (0.0 - 1.0)
function M.setMusicVolume(volume)
    soundManager.musicVolume = math.max(0, math.min(1, volume))
end

--- Set SFX volume (0.0 - 1.0)
function M.setSFXVolume(volume)
    soundManager.sfxVolume = math.max(0, math.min(1, volume))
end

--- Enable/disable debug logging
function M.setDebug(enabled)
    soundManager.debug = enabled
end

return M
