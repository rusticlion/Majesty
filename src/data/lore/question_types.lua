-- question_types.lua
-- Structured Bid Lore question templates for deterministic adjudication.

local M = {}

M.ORDER = {
    "vulnerability",
    "behavior",
    "taboo_or_trigger",
    "identity_or_origin",
    "environmental_risk",
    "social_preference",
    "alchemy_effect",
}

M.BY_ID = {
    vulnerability = {
        id = "vulnerability",
        name = "Vulnerability",
        tags = { "weakness", "counter", "tactics" },
        prompt = "What is this subject vulnerable to?",
    },
    behavior = {
        id = "behavior",
        name = "Behavior",
        tags = { "habit", "pattern", "tactics" },
        prompt = "How does this subject usually behave?",
    },
    taboo_or_trigger = {
        id = "taboo_or_trigger",
        name = "Taboo / Trigger",
        tags = { "taboo", "trigger", "provocation" },
        prompt = "What provokes or calms this subject?",
    },
    identity_or_origin = {
        id = "identity_or_origin",
        name = "Identity / Origin",
        tags = { "history", "origin", "classification" },
        prompt = "What is this subject, and where did it come from?",
    },
    environmental_risk = {
        id = "environmental_risk",
        name = "Environmental Risk",
        tags = { "hazard", "terrain", "risk" },
        prompt = "What nearby environmental risk matters right now?",
    },
    social_preference = {
        id = "social_preference",
        name = "Social Preference",
        tags = { "social", "likes", "dislikes" },
        prompt = "What does this subject respond well or poorly to?",
    },
    alchemy_effect = {
        id = "alchemy_effect",
        name = "Alchemy Effect",
        tags = { "alchemy", "reagent", "reaction" },
        prompt = "What practical reagent or alchemical interaction applies?",
    },
}

function M.get(id)
    return M.BY_ID[id]
end

function M.list()
    local out = {}
    for _, id in ipairs(M.ORDER) do
        local item = M.BY_ID[id]
        if item then
            out[#out + 1] = item
        end
    end
    return out
end

return M
