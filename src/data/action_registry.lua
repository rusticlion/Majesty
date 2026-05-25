-- action_registry.lua
-- Data registry of all actions for Majesty
-- Ticket S6.2: Categorized Command Board
--
-- Defines all actions from the rulebook (p. 116-120) with their suit tags,
-- attributes, and descriptions.

local constants = require('constants')

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

local function cloneValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, entry in pairs(value) do
        copy[key] = cloneValue(entry)
    end
    return copy
end

local function normalizeTalentId(talentId)
    return tostring(talentId or ""):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
end

local function isMajorArcanaChallengeCard(card)
    local value = tonumber(card and card.value)
    if not value or value < 1 or value > 21 then
        return false
    end
    return card.is_major == true or card.suit == constants.SUITS.MAJOR
end

local function isGreaterDoomCard(card)
    local value = tonumber(card and card.value) or 0
    return isMajorArcanaChallengeCard(card) and value >= 15 and value <= 21
end

local function canGMIgnoreMinorSuit(entity, card)
    return entity and entity.isPC == false and isMajorArcanaChallengeCard(card)
end

local function hasUsableTalent(entity, talentId)
    if not entity or type(entity.talents) ~= "table" then
        return false
    end

    local requested = normalizeTalentId(talentId)
    for key, talent in pairs(entity.talents) do
        local matches = normalizeTalentId(key) == requested
        if not matches and type(talent) == "table" then
            matches = normalizeTalentId(talent.id or talent.name or talent.talentId) == requested
        end
        if matches then
            if type(talent) == "table" then
                return talent.wounded ~= true
            end
            return talent == true
        end
    end

    return false
end

local function itemIsArchwoodWand(item)
    if not item or item.destroyed then
        return false
    end

    local props = item.properties or {}
    if props.archwood and props.wand then
        return true
    end

    local id = normalizeTalentId(item.templateId or item.id or item.name)
    return id == "wand_archwood" or id == "wand_of_archwood"
end

local function getArchwoodWandInHands(entity)
    local inv = entity and entity.inventory
    if not inv then
        return nil
    end

    local hands = inv.getItems and inv:getItems("hands") or inv.hands or {}
    for _, item in ipairs(hands or {}) do
        if itemIsArchwoodWand(item) then
            return item
        end
    end

    return nil
end

local function hasArchwoodWandInHands(entity)
    return getArchwoodWandInHands(entity) ~= nil
end

local function itemIsMeleeWeapon(item)
    return item and item.isWeapon and not item.isRanged
end

local function itemIsDagger(item)
    if not item then
        return false
    end
    local weaponType = normalizeTalentId(item.weaponType or item.type or item.name)
    return weaponType == "dagger"
end

local function getTwoHandedFocusWeapon(entity)
    local inv = entity and entity.inventory
    if not inv then
        return nil
    end

    local weapon = inv.getWieldedWeapon and inv:getWieldedWeapon()
    if not itemIsMeleeWeapon(weapon) or itemIsDagger(weapon) then
        return nil
    end

    local props = weapon.properties or {}
    if weapon.twoHanded or weapon.two_handed or props.twoHanded or props.two_handed or
       props.twoHandedFocus then
        return weapon
    end

    local weaponSize = weapon.size or 1
    if weaponSize >= 2 then
        return weapon
    end

    local freeHands = inv.availableSlots and inv:availableSlots("hands") or 0
    if freeHands >= 1 then
        return weapon
    end

    return nil
end

local function canUseTwoHandedFocus(entity)
    return hasUsableTalent(entity, "two_handed_focus") and getTwoHandedFocusWeapon(entity) ~= nil
end

local function listContainsNormalized(items, value)
    local normalized = normalizeTalentId(value)
    for _, item in ipairs(items or {}) do
        if normalizeTalentId(item) == normalized then
            return true
        end
    end
    return false
end

local function hasWornArmorType(entity, armorTypes)
    if not entity then
        return false
    end

    local actorArmorType = normalizeTalentId(entity.armorType or entity.armor_type)
    if actorArmorType ~= "" and listContainsNormalized(armorTypes, actorArmorType) then
        return true
    end

    local armor = entity.armor
    if type(armor) == "table" then
        local props = armor.properties or {}
        local armorType = normalizeTalentId(armor.armorType or armor.armor_type or props.armorType or props.armor_type)
        if armorType ~= "" and listContainsNormalized(armorTypes, armorType) then
            return true
        end
    end

    local inv = entity.inventory
    local belt = inv and inv.getItems and inv:getItems("belt") or inv and inv.belt or {}
    for _, item in ipairs(belt or {}) do
        local props = item.properties or {}
        local armorType = normalizeTalentId(item.armorType or item.armor_type or props.armorType or props.armor_type)
        if (item.isArmor or props.armor) and not item.destroyed and
           listContainsNormalized(armorTypes, armorType) then
            return true
        end
    end

    return false
end

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
        id = "aim",
        name = "Aim",
        suit = M.SUITS.SWORDS,
        attribute = "swords",
        description = "Prepare a facedown bow shot; reveal it on your next bow Attack to add this card's value.",
        requiresTarget = true,
        targetType = "enemy",
        requiresWeaponType = "bow",
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
        id = "roughhouse",
        name = "Roughhouse",
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        description = "Attempt a maneuver, then choose Disarm, Displace, Root, or Trip.",
        requiresTarget = true,
        targetType = "enemy",
        challengeAction = true,
        roughhouseEffects = { "disarm", "displace", "root", "trip", "exhaust", "notch", "silence" },
        fightDirtyEffects = { exhaust = true, notch = true, silence = true },
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
        showInCommandBoard = false,
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
        showInCommandBoard = false,
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
        showInCommandBoard = false,
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
        showInCommandBoard = false,
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
        description = "Bank a bonus for an ally's declared trigger action (card value + Cups).",
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
        id = "counter_spell",
        name = "Counter-spell",
        suit = M.SUITS.WANDS,
        attribute = "wands",
        description = "Interrupt or negate sorcery through the Counter-spell talent.",
        requiresTarget = false,
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
    {
        id = "dwimmercraft",
        name = "Dwimmercraft",
        suit = M.SUITS.MISC,
        attribute = nil,
        description = "Use the Dwimmercraft talent for minor magic or second sight.",
        requiresTarget = false,
        allowMinor = false,
        autoSuccess = true,
        challengeAction = true,
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
        requiresLoreBid = true,
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
        id = "flee",
        name = "Flee",
        suit = M.SUITS.MISC,
        attribute = nil,
        description = "Retreat from a Challenge using the rulebook pursuit procedure.",
        requiresTarget = false,
        allowMinor = false,
        autoSuccess = true,
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
        id = "heavy_metal_machine",
        name = "Heavy Metal Machine",
        suit = M.SUITS.MISC,
        attribute = nil,
        description = "Ready iron or steel armor to add Swords to Initiative against one incoming action.",
        requiresTarget = false,
        allowMinor = false,
        requiresTalent = "heavy_metal_machine",
        requiresArmorTypeAny = { "iron", "steel" },
        challengeAction = true,
    },
    {
        id = "up_my_sleeve",
        name = "Up My Sleeve",
        suit = M.SUITS.MISC,
        attribute = nil,
        description = "Spend Resolve to declare a common one-slot item you had all along.",
        requiresTarget = false,
        allowMinor = false,
        autoSuccess = true,
        requiresTalent = "up_my_sleeve",
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

M.CHALLENGE_ACTION_DETAILS = {
    {
        id = "melee",
        rulebookId = "attack",
        label = "Attack (Melee)",
        sourcePages = "116",
        category = M.SUITS.SWORDS,
        suit = M.SUITS.SWORDS,
        attribute = "swords",
        canBeMinor = true,
        target = "same-zone enemy",
        primaryValue = "card value + Swords",
        minorValue = "card face value only",
        successTest = "exceed target Initiative",
        tieRule = "attacker wins unless defender has a shield",
        effects = {
            "Reveal target Initiative.",
            "Deal 1 Wound on a hit.",
            "Successful melee Attacks engage attacker and target.",
        },
    },
    {
        id = "missile",
        rulebookId = "attack",
        label = "Attack (Missile)",
        sourcePages = "116",
        category = M.SUITS.SWORDS,
        suit = M.SUITS.SWORDS,
        attribute = "swords",
        canBeMinor = true,
        target = "enemy in range",
        primaryValue = "card value + Swords",
        minorValue = "card face value only",
        successTest = "exceed target Initiative",
        tieRule = "attacker wins unless defender has a shield",
        effects = {
            "Reveal target Initiative.",
            "Deal 1 Wound on a hit.",
            "Engaged attackers cannot ordinarily make missile Attacks.",
        },
    },
    {
        id = "riposte",
        rulebookId = "riposte",
        label = "Riposte",
        sourcePages = "116",
        category = M.SUITS.SWORDS,
        suit = M.SUITS.SWORDS,
        attribute = "swords",
        canBeMinor = true,
        facedown = true,
        trigger = "next targeted by an Attack, Roughhouse, or similar action",
        primaryValue = "card value + Swords when played on your turn",
        minorValue = "card face value only when played as a minor action",
        successTest = "Riposte value exceeds incoming action value",
        tieRule = "riposter wins unless attacker has a shield",
        effects = {
            "Deal 1 Wound to the attacker on a successful counterstrike.",
            "Discard the Riposte card after it resolves.",
        },
    },
    {
        id = "avoid",
        rulebookId = "avoid",
        label = "Avoid",
        sourcePages = "117",
        category = M.SUITS.PENTACLES,
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        canBeMinor = true,
        target = "danger, threat, guard, or engaged opponent",
        primaryValue = "card value + Pentacles",
        minorValue = "card face value only",
        successTest = "equal or exceed engaged opponent Initiative, otherwise exceed non-engaged threat Initiative",
        effects = {
            "Move to an adjacent zone.",
            "Safely disengage from opponents beaten or tied by the Avoid value.",
            "Opponents not Avoided may deal 1 Wound before movement.",
        },
    },
    {
        id = "dash",
        rulebookId = "dash",
        label = "Dash",
        sourcePages = "117",
        category = M.SUITS.PENTACLES,
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        canBeMinor = true,
        primaryValue = "card value + Pentacles",
        minorValue = "card face value only",
        effects = {
            "Leave the current zone and move up to two zones away.",
        },
    },
    {
        id = "dodge",
        rulebookId = "dodge",
        label = "Dodge",
        sourcePages = "117",
        category = M.SUITS.PENTACLES,
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        canBeMinor = true,
        facedown = true,
        trigger = "next targeted by an Attack, Roughhouse, or similar action",
        primaryValue = "card value + Pentacles when played on your turn",
        minorValue = "card face value only when played as a minor action",
        effects = {
            "Add the Dodge value to Initiative against the triggering action.",
            "If the boosted Initiative exceeds the incoming action value, the action misses.",
            "Discard the Dodge card after it resolves.",
        },
    },
    {
        id = "roughhouse",
        rulebookId = "roughhouse",
        label = "Roughhouse",
        sourcePages = "117",
        category = M.SUITS.PENTACLES,
        suit = M.SUITS.PENTACLES,
        attribute = "pentacles",
        canBeMinor = true,
        target = "opponent",
        primaryValue = "card value + Pentacles",
        minorValue = "card face value only",
        successTest = "exceed target Initiative",
        effects = {
            "Choose Disarm, Displace, Root, or Trip on success.",
            "The target uses Recover to remove the imposed effect.",
        },
        choices = { "disarm", "displace", "root", "trip" },
    },
    {
        id = "aid",
        rulebookId = "aid_another",
        label = "Aid Another",
        sourcePages = "118",
        category = M.SUITS.CUPS,
        suit = M.SUITS.CUPS,
        attribute = "cups",
        canBeMinor = true,
        facedown = true,
        target = "ally and declared trigger action",
        primaryValue = "card value + Cups",
        minorValue = "card face value only",
        effects = {
            "Reveal when the ally performs the trigger action.",
            "Add Aid Another value to the ally's action value.",
        },
    },
    {
        id = "command",
        rulebookId = "command",
        label = "Command",
        sourcePages = "118",
        category = M.SUITS.CUPS,
        suit = M.SUITS.CUPS,
        attribute = "cups",
        canBeMinor = true,
        target = "animal companion or similar ally",
        primaryValue = "card value + Cups",
        minorValue = "card face value only",
        effects = {
            "Known commands with no combatant target can use any value.",
            "Commands targeting a combatant compare against that target's Initiative.",
            "Animal companions act through Command rather than taking independent actions.",
        },
    },
    {
        id = "pull_item",
        rulebookId = "pull_item_from_pack",
        label = "Pull Item from Pack",
        sourcePages = "118",
        category = M.SUITS.CUPS,
        suit = M.SUITS.CUPS,
        attribute = "cups",
        canBeMinor = true,
        primaryValue = "card value + Cups",
        minorValue = "card face value only",
        effects = {
            "Pull an item from the pack and swap it with an item in hand.",
        },
    },
    {
        id = "use_item",
        rulebookId = "use_item",
        label = "Use Item",
        sourcePages = "118",
        category = M.SUITS.CUPS,
        suit = M.SUITS.CUPS,
        attribute = "cups",
        canBeMinor = true,
        primaryValue = "card value + Cups",
        minorValue = "card face value only",
        effects = {
            "Self-use can use any value.",
            "Hostile combatant use compares against target Initiative.",
            "Bomb-like uses are Attack-like but tied to Cups.",
        },
    },
    {
        id = "banter",
        rulebookId = "banter",
        label = "Banter",
        sourcePages = "119",
        category = M.SUITS.WANDS,
        suit = M.SUITS.WANDS,
        attribute = "wands",
        canBeMinor = true,
        target = "enemy with Morale",
        primaryValue = "card value + Wands",
        minorValue = "card face value only",
        successTest = "exceed target Morale",
        effects = {
            "Shift target Disposition by one step in intensity or to an adjacent emotion.",
            "GM may apply favor or disfavor from the target's likes and dislikes.",
        },
    },
    {
        id = "speak_incantation",
        rulebookId = "speak_incantation",
        label = "Speak Incantation",
        sourcePages = "119",
        category = M.SUITS.WANDS,
        suit = M.SUITS.WANDS,
        attribute = "wands",
        canBeMinor = true,
        target = "spell target",
        primaryValue = "card value + Wands",
        minorValue = "card face value only",
        successTest = "exceed target Initiative when opposed",
        tieRule = "caster wins unless defender has a shield",
        requirements = {
            "trained spell talent",
            "spell component held in one hand",
            "ability to speak",
        },
    },
    {
        id = "recover",
        rulebookId = "recover",
        label = "Recover",
        sourcePages = "119",
        category = M.SUITS.WANDS,
        suit = M.SUITS.WANDS,
        attribute = "wands",
        canBeMinor = true,
        primaryValue = "card value + Wands",
        minorValue = "card face value only",
        effects = {
            "Remove one GM-approved recoverable effect.",
            "Hard-to-escape effects such as chains, curses, or petrification may be nonrecoverable.",
        },
    },
    {
        id = "bid_lore",
        rulebookId = "bid_lore",
        label = "Bid Lore",
        sourcePages = "120",
        category = M.SUITS.MISC,
        suit = M.SUITS.MISC,
        attribute = nil,
        canBeMinor = false,
        primaryValue = "any card; card value does not decide the lore answer",
        effects = {
            "Spend the Challenge action and card whether the GM accepts, rejects, or asks for a rephrase.",
        },
    },
    {
        id = "guard",
        rulebookId = "guard",
        label = "Guard",
        sourcePages = "120",
        category = M.SUITS.MISC,
        suit = M.SUITS.MISC,
        attribute = nil,
        canBeMinor = false,
        primaryValue = "any card from hand",
        requirements = { "shield" },
        effects = {
            "Replace current Initiative with the played card's value.",
            "Discard the old Initiative card.",
        },
    },
    {
        id = "move",
        rulebookId = "move",
        label = "Move",
        sourcePages = "120",
        category = M.SUITS.MISC,
        suit = M.SUITS.MISC,
        attribute = nil,
        canBeMinor = false,
        primaryValue = "any card",
        effects = {
            "Move from the current zone to an adjacent zone.",
            "Obstacles, engagement, or hazards may require Avoid or another procedure instead.",
        },
    },
    {
        id = "pull_item_belt",
        rulebookId = "pull_item_from_belt",
        label = "Pull Item from Belt",
        sourcePages = "120",
        category = M.SUITS.MISC,
        suit = M.SUITS.MISC,
        attribute = nil,
        canBeMinor = false,
        primaryValue = "any card",
        effects = {
            "Pull an item from the belt and swap it with an item in hand.",
        },
    },
    {
        id = "reload",
        rulebookId = "reload_crossbow",
        label = "Reload Crossbow",
        sourcePages = "120",
        category = M.SUITS.MISC,
        suit = M.SUITS.MISC,
        attribute = nil,
        canBeMinor = false,
        primaryValue = "any card",
        requirements = { "unloaded crossbow", "bolt ammunition" },
        effects = {
            "Fit another bolt into a crossbow and crank the cranequin.",
        },
    },
    {
        id = "test_fate",
        rulebookId = "test_fate",
        label = "Test Fate",
        sourcePages = "120",
        category = M.SUITS.MISC,
        suit = M.SUITS.MISC,
        attribute = nil,
        canBeMinor = false,
        primaryValue = "spend any card, then draw a separate minor-arcana test card",
        effects = {
            "Use for risky feats more complex than Trivial Action.",
            "The spent Challenge card is not the Test Fate card.",
            "Resolve, pushed fate, and motif bids use the normal Test Fate procedure.",
        },
    },
    {
        id = "trivial_action",
        rulebookId = "trivial_action",
        label = "Trivial Action",
        sourcePages = "120",
        category = M.SUITS.MISC,
        suit = M.SUITS.MISC,
        attribute = nil,
        canBeMinor = false,
        primaryValue = "any card of any value",
        effects = {
            "Resolve a momentary, uncontested interaction not covered by other actions.",
        },
        examples = {
            "open a door",
            "throw a lever",
            "pick up an ordinary ground item",
            "drop prone",
        },
    },
    {
        id = "up_my_sleeve",
        rulebookId = "up_my_sleeve",
        label = "Up My Sleeve",
        sourcePages = "74",
        category = M.SUITS.MISC,
        suit = M.SUITS.MISC,
        attribute = nil,
        canBeMinor = false,
        primaryValue = "any card; spend 1 Resolve",
        requirements = {
            "Up My Sleeve talent",
            "common one-slot item",
            "maximum twice per Crawl",
        },
        effects = {
            "Produce the declared item in hand as something carried the whole time.",
        },
        examples = {
            "lockpick",
            "dagger",
            "handkerchief",
            "empty vial",
            "length of wire",
        },
    },
    {
        id = "vigilance",
        rulebookId = "vigilance",
        label = "Vigilance",
        sourcePages = "120",
        category = M.SUITS.MISC,
        suit = M.SUITS.MISC,
        attribute = nil,
        canBeMinor = false,
        facedown = true,
        cardSuitRule = "same_suit_as_follow_up_action",
        trigger = "declared circumstance before the follow-up action",
        primaryValue = "matching-suit card for the declared follow-up action",
        effects = {
            "Play the card facedown.",
            "Declare a trigger and the action taken when the trigger occurs.",
            "Flip the card and resolve the follow-up action when triggered.",
        },
    },
    {
        id = "flee",
        rulebookId = "retreat",
        label = "Flee",
        sourcePages = "123-124",
        category = M.SUITS.MISC,
        suit = M.SUITS.MISC,
        attribute = nil,
        canBeMinor = false,
        primaryValue = "each adventurer spends a miscellaneous Challenge card if retreat happens mid-Challenge",
        effects = {
            "Fast or magical pursuers can make escape impossible.",
            "Slow, awkward, or lair-bound foes may allow clean retreat.",
            "Equivalent pursuit uses a Pentacles group test from the highest and lowest Pentacles adventurers.",
        },
    },
}

M.CHALLENGE_ACTION_REFERENCE = {
    source = "Core Rules Chapter 7: Challenge Actions",
    sourcePages = "116-120",
    actionPages = "116-120",
    gmingPages = "121-123",
    freeActions = {
        requireCard = false,
        examples = {
            "talk in character",
            "move around within a zone",
        },
        limits = {
            "Speech can be blocked by silence or similar effects.",
            "Within-zone movement can be blocked by restraints or similar effects.",
        },
    },
    valueRules = {
        primaryTurn = {
            addAttribute = true,
            description = "Suited Challenge Actions add the matching attribute to the played card value on the actor's turn.",
        },
        minorAction = {
            addAttribute = false,
            description = "Minor actions use only the played card's face value.",
        },
        miscellaneous = {
            anySuit = true,
            addAttribute = false,
            description = "Miscellaneous actions can use any suit unless their individual procedure says otherwise.",
        },
    },
    suitGroups = {
        { suit = M.SUITS.SWORDS, label = "Swords", actions = { "melee", "missile", "riposte" } },
        { suit = M.SUITS.PENTACLES, label = "Pentacles", actions = { "avoid", "dash", "dodge", "roughhouse" } },
        { suit = M.SUITS.CUPS, label = "Cups", actions = { "aid", "command", "pull_item", "use_item" } },
        { suit = M.SUITS.WANDS, label = "Wands", actions = { "banter", "speak_incantation", "recover" } },
        {
            suit = M.SUITS.MISC,
            label = "Miscellaneous",
            actions = {
                "bid_lore",
                "guard",
                "move",
                "pull_item_belt",
                "reload",
                "test_fate",
                "trivial_action",
                "vigilance",
            },
        },
    },
    coreActionIds = {
        "melee",
        "missile",
        "riposte",
        "avoid",
        "dash",
        "dodge",
        "roughhouse",
        "aid",
        "command",
        "pull_item",
        "use_item",
        "banter",
        "speak_incantation",
        "recover",
        "bid_lore",
        "guard",
        "move",
        "pull_item_belt",
        "reload",
        "test_fate",
        "trivial_action",
        "vigilance",
    },
    relatedProcedures = {
        flee = "Retreat procedure, Core Rules Chapter 7 pp. 123-124",
    },
    extensionActionIds = {
        "aim",
        "counter_spell",
        "dwimmercraft",
        "heavy_metal_machine",
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

M.CHALLENGE_ACTION_ALIASES = {
    attack = "melee",
    attack_melee = "melee",
    melee_attack = "melee",
    attack_ranged = "missile",
    attack_missile = "missile",
    ranged_attack = "missile",
    missile_attack = "missile",
    aid_another = "aid",
    pull_item_from_pack = "pull_item",
    pull_from_pack = "pull_item",
    use_an_item = "use_item",
    speak_incantation = "speak_incantation",
    cast_spell = "speak_incantation",
    pull_item_from_belt = "pull_item_belt",
    pull_from_belt = "pull_item_belt",
    reload_crossbow = "reload",
    test_of_fate = "test_fate",
    test_fate = "test_fate",
    trivial = "trivial_action",
    trivial_action = "trivial_action",
    retreat = "flee",
}

M.challengeActionDetailsById = {}
for _, details in ipairs(M.CHALLENGE_ACTION_DETAILS) do
    M.challengeActionDetailsById[details.id] = details
    M.challengeActionDetailsById[details.rulebookId] = M.challengeActionDetailsById[details.rulebookId] or details
end

local function normalizeActionId(actionId)
    local current = actionId
    local seen = {}

    while current and M.ALIASES[current] and not seen[current] do
        seen[current] = true
        current = M.ALIASES[current]
    end

    return current or actionId
end

local function normalizeChallengeActionLookup(actionId)
    local normalized = normalizeTalentId(actionId)
    return M.CHALLENGE_ACTION_ALIASES[normalized] or normalizeActionId(normalized)
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
            if not weapon and action.requiresWeaponType == "ranged" and hasUsableTalent(entity, "gramarye") then
                weapon = getArchwoodWandInHands(entity)
            end
            if weapon then
                if action.requiresWeaponType == "ranged" then
                    hasRequiredWeapon = weapon.isRanged == true or
                        (hasUsableTalent(entity, "gramarye") and itemIsArchwoodWand(weapon))
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

    if action.requiresTalent and not hasUsableTalent(entity, action.requiresTalent) then
        return false, "Requires " .. tostring(action.requiresTalent):gsub("_", " ")
    end

    if action.requiresArmorTypeAny and not hasWornArmorType(entity, action.requiresArmorTypeAny) then
        return false, "Requires worn iron or steel armor."
    end

    if action.requiresTag then
        if not hasTagInHands(entity, action.requiresTag) then
            return false, "Requires " .. action.requiresTag
        end
    end

    if action.requiresCompanion then
        local hasCompanion = entity and (
            entity.companion ~= nil or
            (type(entity.companions) == "table" and next(entity.companions) ~= nil) or
            (type(entity.animalCompanions) == "table" and next(entity.animalCompanions) ~= nil)
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

    if action.requiresLoreBid then
        local loreBids = entity and entity.loreBids or 0
        if loreBids <= 0 then
            return false, "No lore bids remaining"
        end
    end

    return true, nil
end

--- Get an action by ID
function M.getAction(actionId)
    local normalized = normalizeActionId(actionId)
    return M.byId[normalized]
end

function M.getChallengeActionReference()
    return cloneValue(M.CHALLENGE_ACTION_REFERENCE)
end

function M.getChallengeActionDetails(actionId)
    if actionId == nil then
        return cloneValue(M.CHALLENGE_ACTION_DETAILS)
    end

    local normalized = normalizeChallengeActionLookup(actionId)
    return cloneValue(M.challengeActionDetailsById[normalized])
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
    local gmMinorSuitBypass = not isPrimaryTurn and canGMIgnoreMinorSuit(entity, card)

    for _, action in ipairs(M.ACTIONS) do
        local canUse = false

        if isPrimaryTurn then
            -- On primary turn, any action is available
            canUse = true
        elseif gmMinorSuitBypass then
            -- The GM uses suitless major arcana; lesser dooms cover ordinary Challenge Actions.
            canUse = action.suit ~= M.SUITS.MISC and action.allowMinor ~= false and
                not isGreaterDoomCard(card)
        else
            -- On minor turn, only suit-matched actions (excluding misc)
            if action.suit == cardSuit and action.allowMinor ~= false then
                canUse = true
            elseif M.canUseMinorActionWithCard(action, cardSuit, entity) then
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

function M.canUseMinorActionWithCard(action, cardSuit, entity)
    if not action or action.allowMinor == false then
        return false
    end

    if action.id == "roughhouse" and cardSuit == M.SUITS.SWORDS then
        return hasUsableTalent(entity, "fight_dirty")
    end

    if action.id == "missile" and cardSuit == M.SUITS.WANDS then
        return hasUsableTalent(entity, "gramarye") and hasArchwoodWandInHands(entity)
    end

    if action.id == "melee" and (cardSuit == M.SUITS.SWORDS or cardSuit == M.SUITS.PENTACLES) then
        return canUseTwoHandedFocus(entity)
    end

    return false
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
