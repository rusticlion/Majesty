-- item_templates.lua
-- Item Templates for Majesty
-- Ticket S11.3: Data-driven item definitions for looting
--
-- Templates define default properties for items.
-- inventory.createItemFromTemplate(templateId) instantiates these.

local M = {}

--------------------------------------------------------------------------------
-- ITEM TEMPLATES
-- Each template defines: name, size, durability, properties, etc.
--------------------------------------------------------------------------------

M.templates = {

    ----------------------------------------------------------------------------
    -- WEAPONS
    ----------------------------------------------------------------------------

    rusty_sword = {
        name = "Rusty Sword",
        size = 1,
        durability = 2,
        weaponType = "sword",
    },

    dagger = {
        name = "Dagger",
        size = 1,
        durability = 2,
        weaponType = "dagger",
    },

    longsword = {
        name = "Longsword",
        size = 1,
        durability = 3,
        weaponType = "sword",
    },

    bow = {
        name = "Bow",
        size = 2,
        durability = 2,
        weaponType = "bow",
    },

    ----------------------------------------------------------------------------
    -- LIGHT SOURCES
    ----------------------------------------------------------------------------

    torch = {
        name = "Torch",
        size = 1,
        durability = 1,
        properties = {
            flicker_count = 3,
            light_source = true,
            isLit = true,                -- Starts lit by default
            requires_hands = true,       -- Must be in hands to provide light
            provides_belt_light = false, -- Does NOT work from belt
            fragile_on_belt = false,
        },
    },

    lantern = {
        name = "Lantern",
        size = 1,
        durability = 2,
        properties = {
            flicker_count = 6,
            light_source = true,
            isLit = true,                -- Starts lit by default
            requires_hands = false,      -- Works from hands OR belt
            provides_belt_light = true,  -- Works from belt
            fragile_on_belt = true,      -- Breaks when taking wound while on belt
        },
    },

    ----------------------------------------------------------------------------
    -- CONSUMABLES
    ----------------------------------------------------------------------------

    ration = {
        name = "Ration",
        size = 1,
        stackable = true,
        stackSize = 6,
        quantity = 1,
        isRation = true,
    },

    rations_3 = {
        name = "Ration",
        size = 1,
        stackable = true,
        stackSize = 6,
        quantity = 3,
        isRation = true,
    },

    healing_potion = {
        name = "Healing Potion",
        size = 1,
        durability = 1,
        properties = { potion = true, effect = "heal_wound" },
    },

    antidote = {
        name = "Antidote",
        size = 1,
        durability = 1,
        properties = { potion = true, effect = "cure_poison" },
    },

    ----------------------------------------------------------------------------
    -- AMMUNITION
    ----------------------------------------------------------------------------

    arrows = {
        name = "Arrows",
        size = 1,
        stackable = true,
        stackSize = 20,
        quantity = 10,
        ammoType = "arrow",
    },

    bolts = {
        name = "Crossbow Bolts",
        size = 1,
        stackable = true,
        stackSize = 20,
        quantity = 10,
        ammoType = "bolt",
    },

    ----------------------------------------------------------------------------
    -- TOOLS
    ----------------------------------------------------------------------------

    lockpicks = {
        name = "Lockpicks",
        size = 1,
        durability = 2,
        properties = { tool = true, toolType = "lockpick" },
    },

    rope = {
        name = "Rope (50ft)",
        size = 1,
        durability = 2,
        properties = { tool = true, toolType = "rope" },
    },

    grappling_hook = {
        name = "Grappling Hook",
        size = 1,
        durability = 2,
        properties = { tool = true, toolType = "grapple" },
    },

    tinkers_kit = {
        name = "Tinker's Kit",
        size = 1,
        durability = 3,
        properties = { tool = true, toolType = "tinker" },
    },

    chalk = {
        name = "Chalk",
        size = 1,
        stackable = true,
        stackSize = 10,
        quantity = 5,
        properties = { tool = true, toolType = "marking" },
    },

    ----------------------------------------------------------------------------
    -- KEYS
    ----------------------------------------------------------------------------

    silver_spider_key = {
        name = "Silver Spider Key",
        size = 1,
        durability = 3,
        keyId = "laboratory_door",
        properties = { key = true },
    },

    rusty_key = {
        name = "Rusty Key",
        size = 1,
        durability = 1,
        keyId = "generic_door",
        properties = { key = true },
    },

    golden_key = {
        name = "Golden Key",
        size = 1,
        durability = 3,
        keyId = "treasure_vault",
        properties = { key = true },
    },

    ----------------------------------------------------------------------------
    -- TREASURE
    ----------------------------------------------------------------------------

    gold_coins = {
        name = "Gold Coins",
        size = 1,
        stackable = true,
        stackSize = 100,
        quantity = 1,
        properties = { currency = true, value = 1 },
    },

    gold_coins_15 = {
        name = "Gold Coins",
        size = 1,
        stackable = true,
        stackSize = 100,
        quantity = 15,
        properties = { currency = true, value = 1 },
    },

    ruby_ring = {
        name = "Ruby Ring",
        size = 1,
        properties = { jewelry = true, value = 50 },
    },

    golden_amulet = {
        name = "Golden Amulet",
        size = 1,
        properties = { jewelry = true, magical = true, value = 100 },
    },

    ----------------------------------------------------------------------------
    -- QUEST ITEMS
    ----------------------------------------------------------------------------

    vellum_map = {
        name = "Vellum Map",
        size = 1,
        properties = { quest_item = true, map = true },
    },

    silver_crown = {
        name = "Silver Crown",
        size = 1,
        properties = { quest_item = true, cursed = true },
    },

    crumpled_note = {
        name = "Crumpled Note",
        size = 1,
        properties = { readable = true, text = "The crown - don't let them take the crown!" },
    },

    partial_map = {
        name = "Partial Tomb Map",
        size = 1,
        properties = { map = true, incomplete = true },
    },

    -- S12.8: Social encounter rewards
    guardian_blessing = {
        name = "Guardian's Blessing",
        size = 1,
        properties = {
            magical = true,
            blessing = true,
            effect = "protection_from_undead",
            duration = "until_rest",
            description = "A spectral blessing that shields you from hostile undead.",
        },
    },

    golden_medallion = {
        name = "Golden Medallion",
        size = 1,
        properties = {
            jewelry = true,
            magical = true,
            value = 75,
            effect = "sense_undead",
            description = "A medallion that grows warm when undead are near.",
        },
    },

    ----------------------------------------------------------------------------
    -- MISCELLANEOUS
    ----------------------------------------------------------------------------

    waterskin = {
        name = "Waterskin",
        size = 1,
        durability = 1,
        properties = { water_container = true, charges = 3 },
    },

    bedroll = {
        name = "Bedroll",
        size = 2,
        properties = { camping = true },
    },

    tent = {
        name = "Tent",
        size = 2,
        oversized = true,
        properties = { camping = true, shelter = true },
    },
}

--------------------------------------------------------------------------------
-- TEMPLATE LOOKUP
--------------------------------------------------------------------------------

--- Get a template by ID
-- @param templateId string: The template ID
-- @return table or nil: The template data
function M.getTemplate(templateId)
    return M.templates[templateId]
end

--- Check if a template exists
-- @param templateId string: The template ID
-- @return boolean
function M.hasTemplate(templateId)
    return M.templates[templateId] ~= nil
end

--- Get all template IDs
-- @return table: Array of template IDs
function M.getAllTemplateIds()
    local ids = {}
    for id, _ in pairs(M.templates) do
        ids[#ids + 1] = id
    end
    return ids
end

return M
