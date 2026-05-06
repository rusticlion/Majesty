-- motif_tag_map.lua
-- Maps adventurer motifs to deterministic lore tags.

local M = {}

M.EXACT = {
    ["veteran soldier"] = { "combat", "tactics", "monster_lore", "discipline" },
    ["scarred"] = { "survival", "pain_tolerance", "battlefield_memory" },
    ["former burglar"] = { "security", "traps", "urban_underworld", "stealth" },
    ["quick fingers"] = { "dexterity", "sleight", "security" },
    ["hedge witch"] = { "occult", "folk_magic", "reagents", "ritual" },
    ["bookish"] = { "history", "scholarly", "occult", "classification" },
    ["wilderness guide"] = { "tracking", "survival", "hazard", "beast_lore" },
    ["sharp eyes"] = { "observation", "scouting", "hazard", "detail_spotting" },
}

M.KEYWORDS = {
    veteran = { "combat", "discipline", "tactics" },
    soldier = { "combat", "monster_lore", "tactics" },
    scarred = { "survival", "pain_tolerance", "battlefield_memory" },
    former = { "history" },
    burglar = { "security", "traps", "stealth" },
    quick = { "dexterity", "reaction" },
    fingers = { "sleight", "precision" },
    hedge = { "folk_magic", "survival" },
    witch = { "occult", "ritual", "reagents" },
    bookish = { "history", "scholarly", "classification" },
    wilderness = { "survival", "tracking", "hazard" },
    guide = { "tracking", "pathfinding", "hazard" },
    sharp = { "observation", "detail_spotting" },
    eyes = { "observation", "scouting" },
}

return M
