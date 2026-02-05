-- action_registry.lua
-- Data registry of all actions for Majesty
-- Ticket S6.2: Categorized Command Board
--
-- Defines all actions from the rulebook (p. 116-120) with their suit tags,
-- attributes, and descriptions.

local M = {}

--------------------------------------------------------------------------------
-- SUIT CONSTANTS
--------------------------------------------------------------------------------
M.SUITS = {
    SWORDS    = "swords",
    PENTACLES = "pentacles",
    CUPS      = "cups",
    WANDS     = "wands",
    MISC      = "misc",  -- Miscellaneous (any suit)
}

--------------------------------------------------------------------------------
-- ACTION DEFINITIONS
--------------------------------------------------------------------------------
-- Each action has:
--   id            - Unique identifier
--   name          - Display name
--   suit          - Required suit (SWORDS, PENTACLES, CUPS, WANDS, or MISC)
--   attribute     - Stat added to card value (swords, pentacles, cups, wands)
--   description   - Short description for tooltip
--   allowMinor    - Whether this can be used as a Minor Action (default: true for suit-matched)
--   requiresTarget - Whether a target is needed

M.ACTIONS = {
    ----------------------------------------------------------------------------
    -- SWORDS (Combat / Physical Aggression)
    ----------------------------------------------------------------------------
    {
        id = "melee",
        name = "Attack (Melee)",
        suit = M.SUITS.SWORDS,
        attribute = "swords",
        description = "Strike an enemy in your zone with a melee weapon.",
        requiresTarget = true,
        targetType = "enemy",
    },
    {
        id = "missile",
        name = "Attack (Ranged)",
        suit = M.SUITS.SWORDS,
        attribute = "swords",
        description = "Fire at an enemy in range with a ranged weapon.",
        requiresTarget = true,
        targetType = "enemy",
        requiresWeaponType = "ranged",
        isRanged = true,  -- S12.2: Cannot use while engaged
    },
    {
        id = "riposte",
        name = "Riposte",
        suit = M.SUITS.SWORDS,
        attribute = "swords",
        description = "Prepare to counter-attack. If attacked, strike back with this card.",
        requiresTarget = false,
    },

    ----------------------------------------------------------------------------
    -- PENTACLES (Agility / Technical Skill)
    ----------------------------------------------------------------------------
    {
        id = "avoid",
        name = "Avoid",
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        description = "Avoid a danger or disengage safely; move to an adjacent zone afterward.",
        requiresTarget = false,
    },
    {
        id = "dash",
        name = "Dash",
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        description = "Move quickly through a zone, potentially avoiding obstacles.",
        requiresTarget = false,
    },
    {
        id = "dodge",
        name = "Dodge",
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        description = "Prepare to dodge. Card value helps you avoid an attack.",
        requiresTarget = false,
    },
    {
        id = "trip",
        name = "Trip",
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        description = "Knock an enemy prone, reducing their defense.",
        requiresTarget = true,
        targetType = "enemy",
    },
    {
        id = "disarm",
        name = "Disarm",
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        description = "Remove an item from an enemy's hands.",
        requiresTarget = true,
        targetType = "enemy",
    },
    {
        id = "displace",
        name = "Displace",
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        description = "Push an enemy to an adjacent zone.",
        requiresTarget = true,
        targetType = "enemy",
    },
    {
        id = "grapple",
        name = "Grapple",
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        description = "Seize an enemy. Success engages and prevents their movement.",
        requiresTarget = true,
        targetType = "enemy",
    },
    {
        id = "pick_lock",
        name = "Pick Lock",
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        description = "Attempt to open a locked door or container.",
        requiresTarget = false,
        requiresItem = "lockpicks",
        testOfFate = true,
    },
    {
        id = "disarm_trap",
        name = "Disarm Trap",
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        description = "Safely disarm a detected trap.",
        requiresTarget = false,
        testOfFate = true,
    },

    ----------------------------------------------------------------------------
    -- CUPS (Social / Support)
    ----------------------------------------------------------------------------
    {
        id = "heal",
        name = "Heal",
        suit = M.SUITS.CUPS,
        attribute = "cups",
        description = "Attempt to heal a wound on yourself or an ally.",
        requiresTarget = true,
        targetType = "ally",
    },
    {
        id = "parley",
        name = "Parley",
        suit = M.SUITS.CUPS,
        attribute = "cups",
        description = "Attempt to negotiate or reason with an NPC.",
        requiresTarget = true,
        targetType = "any",
    },
    {
        id = "rally",
        name = "Rally",
        suit = M.SUITS.CUPS,
        attribute = "cups",
        description = "Inspire an ally, removing a condition or boosting morale.",
        requiresTarget = true,
        targetType = "ally",
    },
    {
        id = "aid",
        name = "Aid Another",
        suit = M.SUITS.CUPS,
        attribute = "cups",
        description = "Bank a bonus for an ally's next action (card value + Cups).",
        requiresTarget = true,
        targetType = "ally",
    },
    {
        id = "pull_item",
        name = "Pull Item",
        suit = M.SUITS.CUPS,
        attribute = "cups",
        description = "Ready an item from your pack to your belt.",
        requiresTarget = false,
        autoSuccess = true,
    },
    {
        id = "use_item",
        name = "Use Item",
        suit = M.SUITS.CUPS,
        attribute = "cups",  -- Depends on item, but uses Cups suit
        description = "Activate an item's special ability.",
        requiresTarget = false,
        autoSuccess = true,
    },

    ----------------------------------------------------------------------------
    -- WANDS (Magic / Perception)
    ----------------------------------------------------------------------------
    {
        id = "cast",
        name = "Cast Spell",
        suit = M.SUITS.WANDS,
        attribute = "wands",
        description = "Channel a prepared spell effect.",
        requiresTarget = false,  -- Depends on spell
    },
    {
        id = "banter",
        name = "Banter",
        suit = M.SUITS.WANDS,
        attribute = "wands",
        description = "Taunt, intimidate, or frighten an enemy to sway morale.",
        requiresTarget = true,
        targetType = "enemy",
    },
    {
        id = "investigate",
        name = "Investigate",
        suit = M.SUITS.WANDS,
        attribute = "wands",
        description = "Search for hidden details, secrets, or clues.",
        requiresTarget = false,
        testOfFate = true,
    },
    {
        id = "detect_magic",
        name = "Detect Magic",
        suit = M.SUITS.WANDS,
        attribute = "wands",
        description = "Sense magical auras or enchantments nearby.",
        requiresTarget = false,
        testOfFate = true,
    },
    {
        id = "recover",
        name = "Recover",
        suit = M.SUITS.WANDS,
        attribute = "wands",
        description = "Clear a negative status effect (rooted, prone, blind, deaf, disarmed).",
        requiresTarget = false,
    },

    ----------------------------------------------------------------------------
    -- MISCELLANEOUS (Any Suit on Primary Turn)
    ----------------------------------------------------------------------------
    {
        id = "move",
        name = "Move",
        suit = M.SUITS.MISC,
        attribute = nil,  -- No stat added
        description = "Move to an adjacent zone. No test required unless obstacles.",
        requiresTarget = false,
        allowMinor = false,  -- Cannot be a Minor action (normally)
    },
    {
        id = "interact",
        name = "Interact",
        suit = M.SUITS.MISC,
        attribute = nil,
        description = "Interact with the environment (pull lever, open door, etc.)",
        requiresTarget = false,
        allowMinor = false,
        autoSuccess = true,
    },
    {
        id = "reload",
        name = "Reload",
        suit = M.SUITS.MISC,
        attribute = nil,
        description = "Reload a crossbow (required after each shot).",
        requiresTarget = false,
        allowMinor = false,
        requiresWeaponType = "crossbow",
    },
}

--------------------------------------------------------------------------------
-- LOOKUP TABLES (built at load time)
--------------------------------------------------------------------------------

M.byId = {}
M.bySuit = {
    [M.SUITS.SWORDS] = {},
    [M.SUITS.PENTACLES] = {},
    [M.SUITS.CUPS] = {},
    [M.SUITS.WANDS] = {},
    [M.SUITS.MISC] = {},
}

-- Build lookup tables
for _, action in ipairs(M.ACTIONS) do
    M.byId[action.id] = action
    if M.bySuit[action.suit] then
        table.insert(M.bySuit[action.suit], action)
    end
end

--------------------------------------------------------------------------------
-- QUERY FUNCTIONS
--------------------------------------------------------------------------------

--- Get an action by ID
function M.getAction(actionId)
    return M.byId[actionId]
end

--- Get all actions for a suit
function M.getActionsForSuit(suit)
    return M.bySuit[suit] or {}
end

--- Get actions available for a given card and context
-- @param card table: The card being played (with .suit field)
-- @param isPrimaryTurn boolean: True if this is the entity's primary turn
-- @param entity table: The acting entity (to check requirements)
-- @return table: Array of available action definitions
function M.getAvailableActions(card, isPrimaryTurn, entity)
    local available = {}
    local cardSuit = M.cardSuitToActionSuit(card.suit)

    for _, action in ipairs(M.ACTIONS) do
        local canUse = false

        if isPrimaryTurn then
            -- On primary turn, any action is available
            canUse = true
        else
            -- On minor turn, only suit-matched actions (excluding misc)
            if action.suit == cardSuit and action.allowMinor ~= false then
                canUse = true
            end
        end

        -- Check additional requirements
        -- S13: Check for weapon in hands (via inventory) with proper type matching
        if canUse and action.requiresWeaponType then
            local hasRequiredWeapon = false

            -- Check inventory hands for weapons
            if entity and entity.inventory then
                local weapon = entity.inventory:getWieldedWeapon()
                if weapon then
                    -- "ranged" is a category check (isRanged flag)
                    if action.requiresWeaponType == "ranged" then
                        hasRequiredWeapon = weapon.isRanged == true
                    -- "melee" is a category check
                    elseif action.requiresWeaponType == "melee" then
                        hasRequiredWeapon = weapon.isMelee == true or (weapon.isWeapon and not weapon.isRanged)
                    -- Otherwise check specific weapon type
                    else
                        hasRequiredWeapon = weapon.weaponType == action.requiresWeaponType
                    end
                end
            end

            if not hasRequiredWeapon then
                canUse = false
            end
        end

        if canUse and action.requiresItem then
            -- Check if entity has required item
            if entity and entity.inventory then
                local hasItem = entity.inventory:hasItemOfType(action.requiresItem)
                if not hasItem then
                    canUse = false
                end
            else
                canUse = false
            end
        end

        if canUse then
            available[#available + 1] = action
        end
    end

    return available
end

--- Convert card deck suit number to action suit string
-- Card suits: 1=Swords, 2=Pentacles, 3=Cups, 4=Wands, nil/0=Major Arcana
function M.cardSuitToActionSuit(cardSuit)
    local suitMap = {
        [1] = M.SUITS.SWORDS,
        [2] = M.SUITS.PENTACLES,
        [3] = M.SUITS.CUPS,
        [4] = M.SUITS.WANDS,
    }
    return suitMap[cardSuit] or M.SUITS.MISC
end

--- Get the display name for a suit
function M.getSuitDisplayName(suit)
    local names = {
        [M.SUITS.SWORDS]    = "Swords",
        [M.SUITS.PENTACLES] = "Pentacles",
        [M.SUITS.CUPS]      = "Cups",
        [M.SUITS.WANDS]     = "Wands",
        [M.SUITS.MISC]      = "Misc",
    }
    return names[suit] or suit
end

--- Calculate the total value for an action
-- @param card table: The card being played
-- @param action table: The action definition
-- @param entity table: The acting entity
-- @return number: Card value + attribute (if any)
function M.calculateTotal(card, action, entity)
    local cardValue = card.value or 0

    if action.attribute and entity then
        local attrValue = entity[action.attribute] or 0
        return cardValue + attrValue
    end

    return cardValue
end

return M
