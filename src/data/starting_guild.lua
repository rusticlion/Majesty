-- starting_guild.lua
-- Data-authored starter guild for the vertical slice.

local M = {}

M.adventurers = {
    {
        id = "grim",
        name = "Grim",
        swords = 3,
        pentacles = 2,
        cups = 1,
        wands = 1,
        motifs = { "Veteran Soldier", "Scarred" },
        armorSlots = 2,
        talents = {
            aegis = { mastered = true },
        },
        starting_gear = {
            hands = {
                { name = "Sword", weaponType = "sword", isWeapon = true, isMelee = true },
                { name = "Light Shield", durability = 1, properties = { shield = true, tags = { "shield" } } },
            },
            belt = {
                { name = "Torch", properties = {
                    flicker_count = 3,
                    light_source = true,
                    isLit = true,
                    requires_hands = true,
                    provides_belt_light = false,
                    fragile_on_belt = false,
                } },
                { name = "Torch", properties = {
                    flicker_count = 3,
                    light_source = true,
                    isLit = true,
                    requires_hands = true,
                    provides_belt_light = false,
                    fragile_on_belt = false,
                } },
            },
        },
    },
    {
        id = "whisper",
        name = "Whisper",
        swords = 1,
        pentacles = 3,
        cups = 2,
        wands = 1,
        motifs = { "Former Burglar", "Quick Fingers" },
        talents = {
            finesse = { mastered = true },
        },
        starting_gear = {
            hands = {
                { name = "Dagger", weaponType = "dagger", isWeapon = true, isMelee = true },
            },
            belt = {
                { name = "Lockpicks", properties = { tool = true, toolType = "lockpick" } },
                { name = "Rope", properties = { tool = true, toolType = "rope" } },
            },
        },
    },
    {
        id = "ember",
        name = "Ember",
        swords = 1,
        pentacles = 1,
        cups = 3,
        wands = 2,
        motifs = { "Hedge Witch", "Bookish" },
        talents = {
            ritualist = { mastered = false },
        },
        starting_gear = {
            hands = {
                { name = "Staff", weaponType = "staff", isWeapon = true, isMelee = true },
            },
            belt = {
                { name = "Lantern", properties = {
                    flicker_count = 4,
                    light_source = true,
                    isLit = true,
                    requires_hands = false,
                    provides_belt_light = true,
                    fragile_on_belt = true,
                } },
                { name = "Chalk", properties = { tool = true, toolType = "marking" } },
            },
        },
    },
    {
        id = "fern",
        name = "Fern",
        swords = 2,
        pentacles = 2,
        cups = 1,
        wands = 2,
        motifs = { "Wilderness Guide", "Sharp Eyes" },
        ammo = 10,
        talents = {
            pathfinder = { mastered = true },
        },
        starting_gear = {
            hands = {
                { name = "Bow", weaponType = "bow", isWeapon = true, isRanged = true, uses_ammo = true },
            },
            belt = {
                { name = "Torch", properties = {
                    flicker_count = 3,
                    light_source = true,
                    isLit = true,
                    requires_hands = true,
                    provides_belt_light = false,
                    fragile_on_belt = false,
                } },
                { name = "Rations", stackable = true, stackSize = 3, quantity = 3, isRation = true },
            },
        },
    },
}

M.bonds = {
    { from = "grim", to = "whisper", status = "rivalry" },
    { from = "whisper", to = "grim", status = "rivalry" },
    { from = "ember", to = "fern", status = "friendship" },
    { from = "fern", to = "ember", status = "friendship" },
}

return M
