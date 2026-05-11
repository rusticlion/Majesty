-- vigilance_triggers.lua
-- Named trigger templates for the Vigilance challenge action.

local M = {}

local function copyTable(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, child in pairs(value) do
        copy[key] = copyTable(child)
    end
    return copy
end

M.templates = {
    hostile_targets_self = {
        mode = "targeted_by_hostile_action",
        target = "self",
        hostileOnly = true,
        excludeSelf = true,
    },
    hostile_targets_ally = {
        mode = "targeted_by_hostile_action",
        target = "ally",
        hostileOnly = true,
        excludeSelf = true,
    },
    enemy_moves = {
        mode = "action_filter",
        actionTypes = { "move", "dash", "avoid" },
        hostileOnly = true,
        excludeSelf = true,
    },
    ally_acts = {
        mode = "action_filter",
        alliedOnly = true,
        excludeSelf = true,
    },
    any_character_acts = {
        mode = "action_filter",
        excludeSelf = true,
    },
}

M.options = {
    {
        id = "hostile_targets_self",
        name = "Target Me",
        description = "Trigger when a hostile action targets this adventurer.",
    },
    {
        id = "hostile_targets_ally",
        name = "Target Ally",
        description = "Trigger when a hostile action targets an ally.",
    },
    {
        id = "enemy_moves",
        name = "Enemy Moves",
        description = "Trigger when a hostile character Moves, Dashes, or Avoids.",
    },
    {
        id = "ally_acts",
        name = "Ally Acts",
        description = "Trigger when an ally acts.",
    },
    {
        id = "any_character_acts",
        name = "Anyone Acts",
        description = "Trigger when any other character acts.",
    },
}

function M.getTemplate(templateName, overrides)
    local template = M.templates[templateName]
    if not template then
        return nil
    end

    local trigger = copyTable(template)
    for key, value in pairs(overrides or {}) do
        if key ~= "template" and key ~= "preset" then
            trigger[key] = copyTable(value)
        end
    end
    return trigger
end

function M.getDefaultTrigger()
    return M.getTemplate("hostile_targets_self")
end

function M.listOptions()
    local options = {}
    for _, option in ipairs(M.options) do
        options[#options + 1] = {
            id = option.id,
            name = option.name,
            description = option.description,
            trigger = M.getTemplate(option.id),
        }
    end
    return options
end

return M
