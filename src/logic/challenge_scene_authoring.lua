-- challenge_scene_authoring.lua
-- Backend validation/checklists for authored Challenge scene rules and hazards.

local constants = require('constants')

local M = {}

local function normalizeKey(value)
    local normalized = tostring(value or ""):lower()
    normalized = normalized:gsub("[^%w]+", "_")
    normalized = normalized:gsub("^_+", ""):gsub("_+$", "")
    return normalized
end

local function asList(value)
    if value == nil then
        return {}
    end
    if type(value) ~= "table" then
        return { value }
    end
    if next(value) == nil then
        return {}
    end
    if #value > 0 then
        return value
    end
    return { value }
end

local function cloneTable(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, entry in pairs(value) do
        copy[key] = entry
    end
    return copy
end

local function addIssue(list, code, message, field, entry)
    list[#list + 1] = {
        code = code,
        message = message,
        field = field,
        entry = entry,
    }
end

local function hasAnyField(entry, fields)
    for _, field in ipairs(fields) do
        if entry[field] ~= nil then
            return true
        end
    end
    return false
end

local function isEmptyList(value)
    if value == nil then
        return true
    end
    if type(value) ~= "table" then
        return tostring(value) == ""
    end
    return next(value) == nil
end

local function collectZones(config)
    local zoneIds = {}
    local duplicates = {}
    for _, zone in ipairs(asList(config and config.zones)) do
        local zoneId = zone and (zone.id or zone.zoneId or zone.key)
        if zoneId then
            zoneId = tostring(zoneId)
            if zoneIds[zoneId] then
                duplicates[zoneId] = true
            end
            zoneIds[zoneId] = true
        end
    end
    return zoneIds, duplicates
end

local function validSuit(value)
    if value == nil then
        return true
    end
    local wanted = normalizeKey(value)
    if wanted == "" then
        return false
    end
    local suits = constants.SUITS or {}
    for _, suit in pairs(suits) do
        if normalizeKey(suit) == wanted then
            return true
        end
    end
    return wanted == "swords" or wanted == "pentacles" or wanted == "cups" or wanted == "wands"
end

local function hasRuleEffect(entry)
    return hasAnyField(entry, {
        "actionTypes",
        "actions",
        "actionType",
        "blockedActions",
        "blockActionTypes",
        "requiredAction",
        "requiresAction",
        "favorActions",
        "favorActionTypes",
        "disfavorActions",
        "disfavorActionTypes",
        "favor",
        "disfavor",
        "movementBlocked",
        "requiredWeaponTags",
        "requiredWeaponTag",
        "requiredItemTags",
        "requiredItemTag",
        "requiredToolTags",
        "requiredToolTag",
        "requiredCardSuit",
        "requiresBothHandsFree",
        "requiredFreeHands",
        "targetTags",
        "targetTag",
    })
end

local function validateSceneEntry(entry, kind, zoneIds, opts)
    opts = opts or {}
    local result = {
        ok = true,
        errors = {},
        warnings = {},
        entry = entry,
        kind = kind,
    }

    if type(entry) ~= "table" then
        if tostring(entry or "") == "" then
            addIssue(result.errors, "entry_missing", "Scene " .. kind .. " entry is blank.", kind, entry)
        end
        result.ok = #result.errors == 0
        return result
    end

    if not entry.id and not entry.key and opts.requireIds then
        addIssue(result.errors, "id_missing", "Scene " .. kind .. " needs an id.", "id", entry)
    elseif not entry.id and not entry.key then
        addIssue(result.warnings, "id_missing", "Scene " .. kind .. " has no stable id.", "id", entry)
    end

    if not entry.description and not entry.text and not entry.summary and not entry.name and not entry.title then
        addIssue(result.errors, "description_missing",
            "Scene " .. kind .. " needs player-facing description text.", "description", entry)
    end

    local zoneId = entry.zoneId or entry.zone
    if zoneId and next(zoneIds or {}) ~= nil and not zoneIds[tostring(zoneId)] then
        addIssue(result.errors, "unknown_zone",
            "Scene " .. kind .. " references an unknown zone: " .. tostring(zoneId) .. ".", "zoneId", entry)
    elseif not zoneId then
        addIssue(result.warnings, "zone_missing",
            "Scene " .. kind .. " is global; add zoneId when the rule is zone-specific.", "zoneId", entry)
    end

    if not hasRuleEffect(entry) then
        addIssue(result.errors, "effect_missing",
            "Scene " .. kind .. " needs at least one runtime effect or gate.", kind, entry)
    end

    local requiredSuit = entry.requiredCardSuit or entry.cardSuit or entry.requiredSuit
    if requiredSuit and not validSuit(requiredSuit) then
        addIssue(result.errors, "invalid_card_suit",
            "Scene " .. kind .. " has an invalid required card suit: " .. tostring(requiredSuit) .. ".",
            "requiredCardSuit", entry)
    end

    if (entry.requiredWeaponTags or entry.requiredWeaponTag) and
       isEmptyList(entry.requiredWeaponTags or entry.requiredWeaponTag) then
        addIssue(result.errors, "weapon_gate_empty",
            "Scene " .. kind .. " declares a weapon gate without weapon tags.", "requiredWeaponTags", entry)
    end

    if (entry.requiredItemTags or entry.requiredItemTag or entry.requiredToolTags or entry.requiredToolTag) and
       isEmptyList(entry.requiredItemTags or entry.requiredItemTag or entry.requiredToolTags or entry.requiredToolTag) then
        addIssue(result.errors, "item_gate_empty",
            "Scene " .. kind .. " declares an item/tool gate without tags.", "requiredItemTags", entry)
    end

    if kind == "hazard" then
        if not (entry.requiredAction or entry.requiresAction or entry.movementBlocked or
           entry.blockReason or entry.reason or entry.consequence or entry.damage or entry.effect) then
            addIssue(result.warnings, "hazard_resolution_missing",
                "Scene hazard should say how it blocks, resolves, or harms characters.", kind, entry)
        end
        if (entry.requiredAction or entry.requiresAction or entry.movementBlocked or
           entry.requiredItemTags or entry.requiredToolTags or entry.requiredCardSuit or
           entry.requiresBothHandsFree or entry.requiredFreeHands) and
           not (entry.blockReason or entry.reason) then
            addIssue(result.warnings, "block_reason_missing",
                "Scene hazard gate should include a player-facing block reason.", "blockReason", entry)
        end
    end

    result.ok = #result.errors == 0
    return result
end

local function appendEntryResults(result, validation)
    if validation.kind == "hazard" then
        result.hazards[#result.hazards + 1] = validation
    else
        result.rules[#result.rules + 1] = validation
    end
    for _, issue in ipairs(validation.errors or {}) do
        result.errors[#result.errors + 1] = issue
    end
    for _, issue in ipairs(validation.warnings or {}) do
        result.warnings[#result.warnings + 1] = issue
    end
end

function M.validateChallengeScene(config, opts)
    config = config or {}
    opts = opts or {}

    local zoneIds, duplicateZones = collectZones(config)
    local result = {
        ok = true,
        errors = {},
        warnings = {},
        rules = {},
        hazards = {},
        zoneIds = zoneIds,
        blockers = {},
    }

    if next(zoneIds) == nil then
        addIssue(result.warnings, "zones_missing",
            "Challenge scene has no authored zones; rules can only be global.", "zones")
    end
    for zoneId in pairs(duplicateZones) do
        addIssue(result.errors, "duplicate_zone", "Duplicate Challenge zone id: " .. zoneId .. ".", "zones")
    end

    for _, rule in ipairs(asList(config.sceneSpecialRules or config.specialRules or config.sceneRules)) do
        appendEntryResults(result, validateSceneEntry(rule, "special_rule", zoneIds, opts))
    end
    for _, hazard in ipairs(asList(config.sceneHazards or config.hazards)) do
        appendEntryResults(result, validateSceneEntry(hazard, "hazard", zoneIds, opts))
    end
    for _, zone in ipairs(asList(config.zones)) do
        local zoneDefaults = {
            zoneId = zone and (zone.id or zone.zoneId or zone.key),
        }
        for _, rule in ipairs(asList(zone and (zone.specialRules or zone.sceneRules))) do
            local entry = type(rule) == "table" and cloneTable(rule) or { description = tostring(rule or "") }
            if type(entry) == "table" and not entry.zoneId and not entry.zone then
                entry.zoneId = zoneDefaults.zoneId
            end
            appendEntryResults(result, validateSceneEntry(entry, "special_rule", zoneIds, opts))
        end
        for _, hazard in ipairs(asList(zone and (zone.hazards or zone.sceneHazards))) do
            local entry = type(hazard) == "table" and cloneTable(hazard) or { description = tostring(hazard or "") }
            if type(entry) == "table" and not entry.zoneId and not entry.zone then
                entry.zoneId = zoneDefaults.zoneId
            end
            appendEntryResults(result, validateSceneEntry(entry, "hazard", zoneIds, opts))
        end
    end

    result.ruleCount = #result.rules
    result.hazardCount = #result.hazards
    result.entryCount = result.ruleCount + result.hazardCount
    if result.entryCount == 0 then
        addIssue(result.warnings, "scene_rules_missing",
            "Challenge scene has no authored special rules or hazards.", "sceneSpecialRules")
    end

    result.ok = #result.errors == 0
    return result
end

local function checklistItem(id, label, complete, detail)
    return {
        id = id,
        label = label,
        complete = complete == true,
        detail = detail,
    }
end

function M.createAuthoringChecklist(config, opts)
    local validation = M.validateChallengeScene(config, opts)
    local items = {}
    local hasZones = next(validation.zoneIds or {}) ~= nil
    local hasEffects = true
    local hasDescriptions = true
    local hasZoneCoverage = true

    for _, entryValidation in ipairs(validation.rules or {}) do
        if #entryValidation.errors > 0 then
            for _, issue in ipairs(entryValidation.errors) do
                if issue.code == "effect_missing" then
                    hasEffects = false
                elseif issue.code == "description_missing" then
                    hasDescriptions = false
                elseif issue.code == "unknown_zone" then
                    hasZoneCoverage = false
                end
            end
        end
    end
    for _, entryValidation in ipairs(validation.hazards or {}) do
        if #entryValidation.errors > 0 then
            for _, issue in ipairs(entryValidation.errors) do
                if issue.code == "effect_missing" then
                    hasEffects = false
                elseif issue.code == "description_missing" then
                    hasDescriptions = false
                elseif issue.code == "unknown_zone" then
                    hasZoneCoverage = false
                end
            end
        end
    end

    items[#items + 1] = checklistItem("zones", "Author Challenge zones", hasZones,
        hasZones and "Zones are present." or "Add at least one zone.")
    items[#items + 1] = checklistItem("scene_entries", "Author special rules or hazards",
        validation.entryCount > 0,
        tostring(validation.entryCount or 0) .. " scene rule/hazard entr" ..
        ((validation.entryCount == 1) and "y" or "ies") .. " found.")
    items[#items + 1] = checklistItem("descriptions", "Provide player-facing descriptions", hasDescriptions,
        hasDescriptions and "All entries have description text." or "One or more entries need description text.")
    items[#items + 1] = checklistItem("runtime_effects", "Declare runtime effects or gates", hasEffects,
        hasEffects and "All entries declare runtime behavior." or "One or more entries need an effect or gate.")
    items[#items + 1] = checklistItem("zone_references", "Reference valid zones", hasZoneCoverage,
        hasZoneCoverage and "All zone references resolve." or "One or more entries reference missing zones.")
    items[#items + 1] = checklistItem("validation", "Resolve authoring blockers", validation.ok,
        validation.ok and "No blocking authoring errors." or tostring(#validation.errors) .. " blocker(s) remain.")

    local complete = true
    for _, item in ipairs(items) do
        if not item.complete then
            complete = false
            break
        end
    end

    return {
        complete = complete,
        items = items,
        validation = validation,
        blockers = validation.errors,
        warnings = validation.warnings,
    }
end

return M
