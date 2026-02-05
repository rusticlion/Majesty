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
--   challengeAction - Whether this should appear in Challenge action menus
--   showInCommandBoard - Optional override for Challenge UI visibility

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
        challengeAction = true,
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
        challengeAction = true,
    },
    {
        id = "riposte",
        name = "Riposte",
        suit = M.SUITS.SWORDS,
        attribute = "swords",
        description = "Prepare to counter-attack. If attacked, strike back with this card.",
        requiresTarget = false,
        challengeAction = true,
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
        challengeAction = true,
    },
    {
        id = "dash",
        name = "Dash",
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        description = "Move quickly through a zone, potentially avoiding obstacles.",
        requiresTarget = false,
        challengeAction = true,
    },
    {
        id = "dodge",
        name = "Dodge",
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        description = "Prepare to dodge. Card value helps you avoid an attack.",
        requiresTarget = false,
        challengeAction = true,
    },
    {
        id = "trip",
        name = "Trip",
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        description = "Knock an enemy prone, reducing their defense.",
        requiresTarget = true,
        targetType = "enemy",
        challengeAction = true,
    },
    {
        id = "disarm",
        name = "Disarm",
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        description = "Remove an item from an enemy's hands.",
        requiresTarget = true,
        targetType = "enemy",
        challengeAction = true,
    },
    {
        id = "displace",
        name = "Displace",
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        description = "Push an enemy to an adjacent zone.",
        requiresTarget = true,
        targetType = "enemy",
        challengeAction = true,
    },
    {
        id = "grapple",
        name = "Grapple",
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        description = "Seize an enemy. Success engages and prevents their movement.",
        requiresTarget = true,
        targetType = "enemy",
        challengeAction = true,
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
        challengeAction = false,
        showInCommandBoard = false,
    },
    {
        id = "disarm_trap",
        name = "Disarm Trap",
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        description = "Safely disarm a detected trap.",
        requiresTarget = false,
        testOfFate = true,
        challengeAction = false,
        showInCommandBoard = false,
    },

    ----------------------------------------------------------------------------
    -- CUPS (Support / Commands)
    ----------------------------------------------------------------------------
    {
        id = "aid",
        name = "Aid Another",
        suit = M.SUITS.CUPS,
        attribute = "cups",
        description = "Bank a bonus for an ally's next action (card value + Cups).",
        requiresTarget = true,
        targetType = "ally",
        challengeAction = true,
    },
    {
        id = "command",
        name = "Command",
        suit = M.SUITS.CUPS,
        attribute = "cups",
        description = "Command an animal companion (or similar ally) to act.",
        requiresTarget = false,
        requiresCompanion = true,
        challengeAction = true,
    },
    {
        id = "pull_item",
        name = "Pull Item from Pack",
        suit = M.SUITS.CUPS,
        attribute = "cups",
        description = "Swap an item from your pack with an item in your hands.",
        requiresTarget = false,
        autoSuccess = true,
        challengeAction = true,
    },
    {
        id = "use_item",
        name = "Use Item",
        suit = M.SUITS.CUPS,
        attribute = "cups",
        description = "Use an item in hand. If used on a combatant, resolve against Initiative.",
        requiresTarget = false,  -- Optional target
        challengeAction = true,
    },

    ----------------------------------------------------------------------------
    -- CUPS EXTENSIONS (not shown in Challenge command board)
    ----------------------------------------------------------------------------
    {
        id = "heal",
        name = "Heal",
        suit = M.SUITS.CUPS,
        attribute = "cups",
        description = "Attempt to heal a wound on yourself or an ally.",
        requiresTarget = true,
        targetType = "ally",
        challengeAction = false,
        showInCommandBoard = false,
    },
    {
        id = "parley",
        name = "Parley",
        suit = M.SUITS.CUPS,
        attribute = "cups",
        description = "Attempt to negotiate or reason with an NPC.",
        requiresTarget = true,
        targetType = "any",
        challengeAction = false,
        showInCommandBoard = false,
    },
    {
        id = "rally",
        name = "Rally",
        suit = M.SUITS.CUPS,
        attribute = "cups",
        description = "Inspire an ally, removing a condition or boosting morale.",
        requiresTarget = true,
        targetType = "ally",
        challengeAction = false,
        showInCommandBoard = false,
    },

    ----------------------------------------------------------------------------
    -- WANDS (Social / Spellcraft)
    ----------------------------------------------------------------------------
    {
        id = "banter",
        name = "Banter",
        suit = M.SUITS.WANDS,
        attribute = "wands",
        description = "Taunt, intimidate, or frighten an enemy to sway morale/disposition.",
        requiresTarget = true,
        targetType = "enemy",
        challengeAction = true,
    },
    {
        id = "speak_incantation",
        name = "Speak Incantation",
        suit = M.SUITS.WANDS,
        attribute = "wands",
        description = "Intone the words of power to cast a spell effect.",
        requiresTarget = false,  -- Optional target
        challengeAction = true,
    },
    {
        id = "recover",
        name = "Recover",
        suit = M.SUITS.WANDS,
        attribute = "wands",
        description = "Remove one recoverable effect (rooted, prone, blind, deaf, disarmed).",
        requiresTarget = false,
        challengeAction = true,
    },

    ----------------------------------------------------------------------------
    -- WANDS EXTENSIONS (not shown in Challenge command board)
    ----------------------------------------------------------------------------
    {
        id = "investigate",
        name = "Investigate",
        suit = M.SUITS.WANDS,
        attribute = "wands",
        description = "Search for hidden details, secrets, or clues.",
        requiresTarget = false,
        testOfFate = true,
        challengeAction = false,
        showInCommandBoard = false,
    },
    {
        id = "detect_magic",
        name = "Detect Magic",
        suit = M.SUITS.WANDS,
        attribute = "wands",
        description = "Sense magical auras or enchantments nearby.",
        requiresTarget = false,
        testOfFate = true,
        challengeAction = false,
        showInCommandBoard = false,
    },

    ----------------------------------------------------------------------------
    -- MISCELLANEOUS (Any Suit on Primary Turn; never minor actions)
    ----------------------------------------------------------------------------
    {
        id = "bid_lore",
        name = "Bid Lore",
        suit = M.SUITS.MISC,
        attribute = nil,
        description = "Bid lore during a Challenge to recall esoteric details.",
        requiresTarget = false,
        allowMinor = false,
        autoSuccess = true,
        challengeAction = true,
    },
    {
        id = "guard",
        name = "Guard",
        suit = M.SUITS.MISC,
        attribute = nil,
        description = "If wielding a shield, replace your Initiative with this card's value.",
        requiresTarget = false,
        allowMinor = false,
        requiresTag = "shield",
        challengeAction = true,
    },
    {
        id = "move",
        name = "Move",
        suit = M.SUITS.MISC,
        attribute = nil,  -- No stat added
        description = "Move to an adjacent zone. No test required unless obstacles.",
        requiresTarget = false,
        allowMinor = false,  -- Cannot be a Minor action (normally)
        challengeAction = true,
    },
    {
        id = "pull_item_belt",
        name = "Pull Item from Belt",
        suit = M.SUITS.MISC,
        attribute = nil,
        description = "Swap an item from your belt with an item in your hands.",
        requiresTarget = false,
        allowMinor = false,
        autoSuccess = true,
        challengeAction = true,
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
        challengeAction = false,
        showInCommandBoard = false,
    },
    {
        id = "reload",
        name = "Reload Crossbow",
        suit = M.SUITS.MISC,
        attribute = nil,
        description = "Reload a crossbow (required after each shot).",
        requiresTarget = false,
        allowMinor = false,
        requiresWeaponType = "crossbow",
        challengeAction = true,
    },
    {
        id = "test_fate",
        name = "Test Fate",
        suit = M.SUITS.MISC,
        attribute = nil,
        description = "Trigger a Test of Fate for risky complex actions mid-Challenge.",
        requiresTarget = false,
        allowMinor = false,
        testOfFate = true,
        challengeAction = true,
    },
    {
        id = "trivial_action",
        name = "Trivial Action",
        suit = M.SUITS.MISC,
        attribute = nil,
        description = "Perform a quick uncontested interaction not covered by other actions.",
        requiresTarget = false,
        allowMinor = false,
        autoSuccess = true,
        challengeAction = true,
    },
    {
        id = "vigilance",
        name = "Vigilance",
        suit = M.SUITS.MISC,
        attribute = nil,
        description = "Prepare a triggered response action using a matching-suit card.",
        requiresTarget = false,
        allowMinor = false,
        challengeAction = true,
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

-- Backward-compatible aliases for renamed actions
M.ALIASES = {
    cast = "speak_incantation",
}

local function normalizeActionId(actionId)
    local current = actionId
    local seen = {}

    while current and M.ALIASES[current] and not seen[current] do
        seen[current] = true
        current = M.ALIASES[current]
    end

    return current or actionId
end

local function hasTagInHands(entity, requiredTag)
    if not entity or not entity.inventory or not entity.inventory.getItems then
        return false
    end

    local hands = entity.inventory:getItems("hands") or {}
    for _, item in ipairs(hands) do
        local props = item.properties
        if props and props.tags then
            for _, tag in ipairs(props.tags) do
                if tag == requiredTag then
                    return true
                end
            end
        end
    end

    return false
end

--- Validate an action's requirements against an entity
-- @return boolean, string|nil: canUse, disableReason
function M.checkActionRequirements(action, entity)
    if not action then
        return false, "Unknown action"
    end

    if action.requiresWeaponType then
        local hasRequiredWeapon = false

        if entity and entity.inventory then
            local weapon = entity.inventory:getWieldedWeapon()
            if weapon then
                if action.requiresWeaponType == "ranged" then
                    hasRequiredWeapon = weapon.isRanged == true
                elseif action.requiresWeaponType == "melee" then
                    hasRequiredWeapon = weapon.isMelee == true or (weapon.isWeapon and not weapon.isRanged)
                else
                    hasRequiredWeapon = weapon.weaponType == action.requiresWeaponType
                end
            end
        end

        if not hasRequiredWeapon then
            return false, "Requires " .. action.requiresWeaponType .. " weapon in hands"
        end
    end

    if action.requiresTag then
        if not hasTagInHands(entity, action.requiresTag) then
            return false, "Requires " .. action.requiresTag
        end
    end

    if action.requiresCompanion then
        local hasCompanion = entity and (
            entity.companion ~= nil or
            (type(entity.companions) == "table" and next(entity.companions) ~= nil)
        )
        if not hasCompanion then
            return false, "Requires companion"
        end
    end

    if action.requiresItem then
        if entity and entity.inventory then
            local hasItem = entity.inventory:hasItemOfType(action.requiresItem)
            if not hasItem then
                return false, "Requires " .. action.requiresItem
            end
        else
            return false, "Requires " .. action.requiresItem
        end
    end

    return true, nil
end

--- Get an action by ID
function M.getAction(actionId)
    local normalized = normalizeActionId(actionId)
    return M.byId[normalized]
end

--- Get actions for a suit
-- @param options table|nil: { challengeOnly = bool, commandBoardOnly = bool }
function M.getActionsForSuit(suit, options)
    local actions = M.bySuit[suit] or {}
    if not options then
        return actions
    end

    local filtered = {}
    for _, action in ipairs(actions) do
        local include = true

        if options.challengeOnly and action.challengeAction == false then
            include = false
        end
        if options.commandBoardOnly and action.showInCommandBoard == false then
            include = false
        end

        if include then
            filtered[#filtered + 1] = action
        end
    end

    return filtered
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

        if canUse then
            canUse = M.checkActionRequirements(action, entity)
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
