-- animal_companions.lua
-- Data for rulebook animal companion commands and common companion examples.

local M = {}

local function clone(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, entry in pairs(value) do
        copy[key] = clone(entry)
    end
    return copy
end

local function normalizeKey(value)
    local normalized = tostring(value or ""):lower()
    normalized = normalized:gsub("[’']", "")
    normalized = normalized:gsub("%s+", "_")
    normalized = normalized:gsub("[^%w_]", "")
    normalized = normalized:gsub("^_+", ""):gsub("_+$", "")
    return normalized
end

M.commandOrder = {
    "sic_em",
    "hunt",
    "get_help",
    "do_a_trick",
    "heel",
    "guard",
    "fetch",
    "stay",
    "track",
}

M.rules = {
    feed = "Animal companions need animal feed each Camp Phase, carried by their owner.",
    carryingSlots = "Animal companions do not have item-carrying slots under the core rulebook.",
    commandLimit = "Most normal animals can learn three commands.",
    familiarCommandLimit = "A familiar can know five commands.",
    initiative = "Animal companions share their master's Initiative during Challenges.",
    actionGate = "Animal companions do not take actions outside of being Commanded.",
    commandTests = "Commands may prompt Tests of Fate; uniquely suited animals test with favor.",
    wounds = "Animal companions usually only have Staggered and Injured; a Wound after Injured kills them.",
    familiarProtection = "A familiar's owner may spend Resolve to reduce a killing blow.",
    injuredHealing = "An owner may spend a charged Bond during Recovery to clear an animal's Injured condition.",
    hirelings = {
        supported = false,
        label = "Hirelings, henchmen, and mercenaries",
        reason = "The rulebook has no hireling rules; Underworld expedition members are player adventurers in a guild.",
    },
}

function M.getRules()
    return clone(M.rules)
end

M.commands = {
    sic_em = {
        id = "sic_em",
        name = "Sic 'Em",
        aliases = { "sicem", "attack", "sic" },
        targetsCombatant = true,
        effect = "companion_attack",
    },
    hunt = {
        id = "hunt",
        name = "Hunt",
        aliases = { "hunt_down" },
        effect = "companion_hunt",
    },
    get_help = {
        id = "get_help",
        name = "Get Help",
        aliases = { "gethelp", "help" },
        effect = "companion_get_help",
    },
    do_a_trick = {
        id = "do_a_trick",
        name = "Do a Trick",
        aliases = { "do_trick", "trick" },
        effect = "companion_trick",
    },
    heel = {
        id = "heel",
        name = "Heel",
        effect = "companion_positioned",
    },
    guard = {
        id = "guard",
        name = "Guard",
        effect = "companion_guard",
    },
    fetch = {
        id = "fetch",
        name = "Fetch",
        effect = "companion_fetch",
    },
    stay = {
        id = "stay",
        name = "Stay",
        effect = "companion_positioned",
    },
    track = {
        id = "track",
        name = "Track",
        effect = "companion_track",
    },
}

local commandAliases = {}
for id, command in pairs(M.commands) do
    commandAliases[normalizeKey(id)] = id
    commandAliases[normalizeKey(command.name)] = id
    for _, alias in ipairs(command.aliases or {}) do
        commandAliases[normalizeKey(alias)] = id
    end
end

M.templates = {
    hound = {
        id = "hound",
        name = "Hound",
        species = "hound",
        animalType = "hound",
        feedType = "hound",
        aliases = { "dog", "dogs", "small dog", "small dogs", "small but vicious dog", "small but vicious dogs" },
        rarityCost = 100,
        damage = 1,
        suitedTests = { track = true, guard = true, scent = true },
        suggestedCommands = { "Sic 'Em", "Track", "Guard" },
    },
    falcon = {
        id = "falcon",
        name = "Falcon",
        species = "falcon",
        animalType = "falcon",
        feedType = "falcon",
        aliases = { "hunting falcon", "hunting falcons" },
        rarityCost = 150,
        damage = 1,
        suitedTests = { scout = true, fetch = true, flight = true },
        suggestedCommands = { "Fetch", "Track", "Get Help" },
    },
    monkey = {
        id = "monkey",
        name = "Monkey",
        species = "monkey",
        animalType = "monkey",
        feedType = "monkey",
        aliases = { "monkeys" },
        rarityCost = 200,
        damage = 1,
        suitedTests = { climb = true, fetch = true, trick = true },
        suggestedCommands = { "Fetch", "Do a Trick", "Get Help" },
    },
    horse = {
        id = "horse",
        name = "Horse",
        species = "horse",
        animalType = "horse",
        feedType = "horse",
        aliases = { "horses" },
        rarityCost = 250,
        damage = 1,
        suitedTests = { pull = true, carry = true, run = true },
        suggestedCommands = { "Heel", "Stay", "Get Help" },
    },
    riding_boar = {
        id = "riding_boar",
        name = "Riding Boar",
        species = "boar",
        animalType = "boar",
        feedType = "boar",
        aliases = { "boars", "riding boars" },
        rarityCost = 300,
        damage = 1,
        suitedTests = { charge = true, scent = true },
        suggestedCommands = { "Sic 'Em", "Heel", "Guard" },
    },
    dire_moth = {
        id = "dire_moth",
        name = "Dire Moth",
        species = "dire moth",
        animalType = "dire moth",
        feedType = "dire moth",
        aliases = { "trained dire moth", "trained dire moths" },
        rarityCost = 350,
        damage = 1,
        suitedTests = { flight = true, scout = true, darkness = true },
        suggestedCommands = { "Fetch", "Track", "Stay" },
    },
}

local templateAliases = {}
for id, template in pairs(M.templates) do
    templateAliases[normalizeKey(id)] = id
    templateAliases[normalizeKey(template.name)] = id
    templateAliases[normalizeKey(template.species)] = id
    templateAliases[normalizeKey(template.animalType)] = id
    for _, alias in ipairs(template.aliases or {}) do
        templateAliases[normalizeKey(alias)] = id
    end
end

function M.normalizeCommandName(commandName)
    local normalized = normalizeKey(commandName)
    return commandAliases[normalized] or normalized
end

function M.getCommand(commandName)
    local normalized = M.normalizeCommandName(commandName)
    return M.commands[normalized]
end

function M.getCommandDisplayName(commandName)
    local command = M.getCommand(commandName)
    return command and command.name or tostring(commandName or "")
end

function M.getCommandEntryName(value, key)
    if type(value) == "string" then
        return value
    end
    if type(value) == "table" then
        local entryName = value.id or value.name or value.command or value.commandName or value.knownCommand
        if entryName ~= nil then
            return entryName
        end
        if type(key) ~= "number" then
            return key
        end
        return nil
    end
    if value and type(key) ~= "number" then
        return key
    end
    return value
end

function M.isCanonicalCommand(commandName)
    return M.getCommand(commandName) ~= nil
end

function M.isAnimalCompanion(entity)
    return type(entity) == "table" and (
        entity.animalCompanion == true or
        entity.isAnimalCompanion == true or
        entity.type == "animal_companion"
    )
end

function M.getCommandLimit(companion)
    if companion and (companion.isFamiliar or companion.familiar) then
        return 5
    end
    return 3
end

local function collectSuitabilityTags(tags, value)
    if type(value) == "string" then
        local tag = normalizeKey(value)
        if tag ~= "" then
            tags[tag] = true
        end
    elseif type(value) == "table" then
        for key, entry in pairs(value) do
            if type(entry) == "string" then
                collectSuitabilityTags(tags, entry)
            elseif entry == true then
                collectSuitabilityTags(tags, key)
            elseif type(entry) == "table" then
                collectSuitabilityTags(tags, entry.id or entry.name or key)
            end
        end
    end
end

function M.isSuitedForTest(companion, test)
    if not companion then
        return false
    end

    local requested = {}
    collectSuitabilityTags(requested, test)
    if next(requested) == nil then
        return false
    end

    local suited = {}
    collectSuitabilityTags(suited, companion.suitedTests)
    collectSuitabilityTags(suited, companion.favoredTests)
    collectSuitabilityTags(suited, companion.testSuitability)
    collectSuitabilityTags(suited, companion.suitabilityTags)

    for tag in pairs(requested) do
        if suited[tag] then
            return true
        end
    end

    return false
end

local function addIssue(list, code, message, field)
    list[#list + 1] = {
        code = code,
        message = message,
        field = field,
    }
end

local function mergeIssues(target, source, prefix)
    for _, issue in ipairs(source or {}) do
        target[#target + 1] = {
            code = prefix and (prefix .. issue.code) or issue.code,
            message = issue.message,
            field = issue.field,
        }
    end
end

local function collectCommandEntries(commands, output)
    if type(commands) == "string" then
        output[#output + 1] = commands
    elseif type(commands) == "table" then
        for key, value in pairs(commands) do
            if type(key) == "number" then
                if type(value) == "table" then
                    output[#output + 1] = M.getCommandEntryName(value, key) or ""
                else
                    output[#output + 1] = value
                end
            elseif value then
                output[#output + 1] = M.getCommandEntryName(value, key)
            end
        end
    end
end

function M.validateCommandList(commands, opts)
    opts = opts or {}
    local result = {
        ok = true,
        errors = {},
        warnings = {},
        commands = {},
        normalizedCommands = {},
        limit = opts.commandLimit or (opts.familiar and 5 or 3),
    }

    local entries = {}
    collectCommandEntries(commands, entries)

    local seen = {}
    for _, command in ipairs(entries) do
        local normalized = M.normalizeCommandName(command)
        if normalized == "" then
            addIssue(result.errors, "command_missing", "Command entry is blank.", "commands")
        elseif not M.isCanonicalCommand(normalized) then
            addIssue(result.errors, "unknown_command",
                "Unknown animal companion command: " .. tostring(command) .. ".", "commands")
        elseif seen[normalized] then
            addIssue(result.errors, "duplicate_command",
                "Duplicate animal companion command: " .. M.getCommandDisplayName(normalized) .. ".", "commands")
        else
            seen[normalized] = true
            result.normalizedCommands[#result.normalizedCommands + 1] = normalized
            result.commands[#result.commands + 1] = M.getCommandDisplayName(normalized)
        end
    end

    result.count = #result.commands
    if result.limit and result.count > result.limit then
        addIssue(result.errors, "command_limit_exceeded",
            "Animal companion knows " .. tostring(result.count) .. " commands; limit is " ..
            tostring(result.limit) .. ".", "knownCommands")
    end

    result.ok = #result.errors == 0
    return result
end

function M.validateTemplate(templateOrId, opts)
    opts = opts or {}
    local template, templateId
    if type(templateOrId) == "table" then
        template = templateOrId
        templateId = opts.templateId or template.id
    else
        template, templateId = M.getTemplate(templateOrId)
    end

    local result = {
        ok = true,
        errors = {},
        warnings = {},
        templateId = templateId,
        template = template,
    }

    if not template then
        addIssue(result.errors, "unknown_template", "Animal companion template is not registered.", "templateId")
        result.ok = false
        return result
    end

    if not template.name or tostring(template.name) == "" then
        addIssue(result.errors, "template_name_missing", "Animal companion template needs a name.", "name")
    end
    if not template.species and not template.animalType then
        addIssue(result.errors, "species_missing", "Animal companion template needs species or animalType.", "species")
    end
    if not template.feedType then
        addIssue(result.errors, "feed_type_missing", "Animal companion template needs a feedType.", "feedType")
    end

    local cost = tonumber(template.rarityCost or template.cost or template.price)
    if cost and (cost < 100 or cost > 1000) then
        addIssue(result.errors, "rarity_cost_out_of_range",
            "Animal companion rarity cost must be 100-1000g.", "rarityCost")
    elseif not cost then
        addIssue(result.warnings, "rarity_cost_missing",
            "Animal companion template has no rarity cost for City purchase authoring.", "rarityCost")
    end

    local suggested = M.validateCommandList(template.suggestedCommands or {}, {
        commandLimit = opts.suggestedCommandLimit or #M.commandOrder,
    })
    mergeIssues(result.errors, suggested.errors, "suggested_")

    local suited = {}
    collectSuitabilityTags(suited, template.suitedTests)
    collectSuitabilityTags(suited, template.favoredTests)
    collectSuitabilityTags(suited, template.testSuitability)
    collectSuitabilityTags(suited, template.suitabilityTags)
    if next(suited) == nil then
        addIssue(result.warnings, "suitability_missing",
            "Animal companion template has no suitability tags for Test of Fate favor.", "suitedTests")
    end

    result.ok = #result.errors == 0
    return result
end

function M.validateCompanion(companion, opts)
    opts = opts or {}
    local result = {
        ok = true,
        errors = {},
        warnings = {},
        companion = companion,
    }

    if type(companion) ~= "table" then
        addIssue(result.errors, "companion_missing", "Animal companion record is missing.", "companion")
        result.ok = false
        return result
    end

    if opts.requireMarker and not M.isAnimalCompanion(companion) then
        addIssue(result.errors, "companion_marker_missing",
            "Animal companion record should be marked as an animal companion.", "type")
    end

    if not companion.name or tostring(companion.name) == "" then
        addIssue(result.warnings, "name_missing", "Animal companion has no display name.", "name")
    end
    if not companion.species and not companion.animalType and not companion.kind then
        addIssue(result.errors, "species_missing", "Animal companion needs species or animalType.", "species")
    end
    if not companion.feedType then
        addIssue(result.errors, "feed_type_missing", "Animal companion needs a feedType.", "feedType")
    end

    local carrySlots = tonumber(companion.carrySlots or companion.porterSlots or companion.packSlots) or 0
    if carrySlots > 0 then
        local message = "Rulebook animal companions do not have item-carrying slots."
        if opts.strictCarrySlots then
            addIssue(result.errors, "carrying_slots_forbidden", message, "carrySlots")
        else
            addIssue(result.warnings, "carrying_slots_nonstandard", message, "carrySlots")
        end
    end

    local commandValidation = M.validateCommandList(companion.knownCommands or companion.commands or {}, {
        commandLimit = opts.commandLimit or M.getCommandLimit(companion),
        familiar = companion.isFamiliar or companion.familiar,
    })
    result.commandValidation = commandValidation
    result.commandCount = commandValidation.count
    result.commandLimit = commandValidation.limit
    mergeIssues(result.errors, commandValidation.errors)

    local suited = {}
    collectSuitabilityTags(suited, companion.suitedTests)
    collectSuitabilityTags(suited, companion.favoredTests)
    collectSuitabilityTags(suited, companion.testSuitability)
    collectSuitabilityTags(suited, companion.suitabilityTags)
    if next(suited) == nil then
        addIssue(result.warnings, "suitability_missing",
            "Animal companion has no suitability tags for Test of Fate favor.", "suitedTests")
    end

    result.ok = #result.errors == 0
    return result
end

function M.validateHirelingRequest(request)
    local detail = {
        ok = false,
        rule = clone(M.rules.hirelings),
        request = request,
    }
    return false, "Hirelings are not supported by the rulebook", detail
end

function M.validateRegistry(opts)
    opts = opts or {}
    local result = {
        ok = true,
        errors = {},
        warnings = {},
        commandCount = 0,
        templateCount = 0,
        templates = {},
    }

    local ordered = {}
    for _, commandId in ipairs(M.commandOrder or {}) do
        ordered[commandId] = true
        if not M.commands[commandId] then
            addIssue(result.errors, "command_order_unknown",
                "Command order references unknown command: " .. tostring(commandId) .. ".", "commandOrder")
        end
    end

    local aliases = {}
    for commandId, command in pairs(M.commands or {}) do
        result.commandCount = result.commandCount + 1
        if not ordered[commandId] then
            addIssue(result.warnings, "command_order_missing",
                "Command is missing from commandOrder: " .. tostring(commandId) .. ".", "commandOrder")
        end
        if not command.name or tostring(command.name) == "" then
            addIssue(result.errors, "command_name_missing",
                "Command needs a display name: " .. tostring(commandId) .. ".", "commands")
        end
        local commandAliasesToCheck = { commandId, command.name }
        for _, alias in ipairs(command.aliases or {}) do
            commandAliasesToCheck[#commandAliasesToCheck + 1] = alias
        end
        for _, alias in ipairs(commandAliasesToCheck) do
            local normalized = normalizeKey(alias)
            if aliases[normalized] and aliases[normalized] ~= commandId then
                addIssue(result.errors, "command_alias_collision",
                    "Command alias maps to multiple commands: " .. tostring(alias) .. ".", "commands")
            end
            aliases[normalized] = commandId
        end
    end

    for templateId, template in pairs(M.templates or {}) do
        result.templateCount = result.templateCount + 1
        local validation = M.validateTemplate(template, {
            templateId = templateId,
            suggestedCommandLimit = opts.suggestedCommandLimit,
        })
        result.templates[templateId] = validation
        mergeIssues(result.errors, validation.errors, "template_" .. tostring(templateId) .. "_")
        mergeIssues(result.warnings, validation.warnings, "template_" .. tostring(templateId) .. "_")
    end

    result.ok = #result.errors == 0
    return result
end

local function spendOwnerResolve(owner)
    if not owner then
        return false
    end

    if owner.spendResolve then
        local ok = owner:spendResolve(1)
        return ok == true
    end

    if type(owner.resolve) == "table" then
        local current = tonumber(owner.resolve.current) or 0
        if current <= 0 then
            return false
        end
        owner.resolve.current = current - 1
        return true
    end

    local current = tonumber(owner.resolve) or 0
    if current <= 0 then
        return false
    end
    owner.resolve = current - 1
    return true
end

function M.takeWound(companion, opts)
    opts = opts or {}
    if not M.isAnimalCompanion(companion) then
        return nil, { reason = "not_animal_companion" }
    end

    companion.conditions = companion.conditions or {}
    local conditions = companion.conditions
    if conditions.dead or companion.dead then
        return "dead", { alreadyDead = true }
    end

    local damageType = opts.damageType or opts.type or "normal"
    if conditions.injured then
        local owner = opts.owner or opts.companionOwner or companion.owner or companion.master
        local canSpendResolve = opts.allowFamiliarResolve ~= false and
            (companion.isFamiliar or companion.familiar)
        if canSpendResolve and spendOwnerResolve(owner) then
            conditions.deaths_door = true
            conditions.out_of_action = true
            companion.deathsDoor = true
            companion.outOfAction = true
            return "familiar_deaths_door", { resolveSpent = true, owner = owner }
        end

        conditions.dead = true
        companion.dead = true
        return "dead", { killed = true }
    end

    if damageType == "critical" or conditions.staggered then
        conditions.injured = true
        companion.injured = true
        return "injured", { injured = true }
    end

    conditions.staggered = true
    companion.staggered = true
    return "staggered", { staggered = true }
end

function M.healWound(companion)
    if not M.isAnimalCompanion(companion) then
        return nil, "not_animal_companion"
    end

    companion.conditions = companion.conditions or {}
    local conditions = companion.conditions
    if conditions.dead or companion.dead then
        return nil, "dead"
    end

    if conditions.deaths_door or companion.deathsDoor or conditions.out_of_action or companion.outOfAction then
        conditions.deaths_door = false
        conditions.out_of_action = false
        companion.deathsDoor = false
        companion.outOfAction = false
        return "familiar_deaths_door_healed"
    end

    if conditions.injured or companion.injured then
        conditions.injured = false
        companion.injured = false
        return "injured_healed"
    end

    if conditions.staggered or companion.staggered then
        conditions.staggered = false
        companion.staggered = false
        return "staggered_healed"
    end

    return nil, "fully_healed"
end

function M.createCompanionInventory(companion)
    local inventory = require('logic.inventory')
    local carrySlots = math.max(0, math.floor(tonumber(companion and
        (companion.carrySlots or companion.porterSlots or companion.packSlots)) or 0))

    return inventory.createInventory({
        handsSlots = 0,
        beltSlots = 0,
        packSlots = carrySlots,
    })
end

function M.getTemplate(templateId)
    local normalized = normalizeKey(templateId)
    if normalized == "" then
        return nil, nil
    end
    local id = templateAliases[normalized] or normalized
    local template = M.templates[id]
    return template, template and id or nil
end

function M.createCompanion(templateId, overrides)
    overrides = overrides or {}

    local template, resolvedTemplateId = M.getTemplate(templateId or overrides.templateId or
        overrides.companionTemplateId or overrides.species or overrides.animalType or overrides.kind)
    local companion = clone(template or {})

    for key, value in pairs(overrides) do
        companion[key] = clone(value)
    end

    companion.templateId = companion.templateId or resolvedTemplateId
    companion.name = companion.name or companion.species or "Animal companion"
    companion.species = companion.species or companion.animalType or companion.kind or "animal"
    companion.animalType = companion.animalType or companion.species
    companion.feedType = companion.feedType or companion.animalType or companion.species
    companion.type = companion.type or "animal_companion"
    companion.conditions = companion.conditions or {}
    companion.animalCompanion = true
    companion.carrySlots = math.max(0, math.floor(tonumber(companion.carrySlots or
        companion.porterSlots or companion.packSlots) or 0))
    companion.noCarryingSlots = companion.carrySlots <= 0 and companion.noCarryingSlots ~= false

    if companion.knownCommands == nil and companion.commands ~= nil then
        companion.knownCommands = companion.commands
    end
    companion.knownCommands = companion.knownCommands or {}
    companion.commands = companion.knownCommands

    if companion.noCarryingSlots or not companion.inventory then
        companion.inventory = M.createCompanionInventory(companion)
    end

    return companion
end

local function companionId(companion)
    return companion and (companion.id or companion.name or companion.templateId or companion.species)
end

local function actorCompanions(actor)
    if type(actor) ~= "table" then
        return {}
    end
    if type(actor.animalCompanions) == "table" then
        return actor.animalCompanions
    end
    if type(actor.companions) == "table" then
        return actor.companions
    end
    if type(actor.companion) == "table" then
        return { actor.companion }
    end
    return {}
end

local function hasCondition(companion, key)
    return companion and ((companion.conditions and companion.conditions[key]) == true or companion[key] == true)
end

local function companionUnavailableReason(companion)
    if not companion then
        return "Animal companion required"
    end
    if hasCondition(companion, "dead") or companion.dead then
        return "Animal companion dead"
    end
    if companion.abandoned or hasCondition(companion, "abandoned") then
        return "Animal companion abandoned"
    end
    if hasCondition(companion, "weak") or hasCondition(companion, "starving") or
        companion.weak or companion.starving then
        return "Animal companion needs feed"
    end
    if hasCondition(companion, "deaths_door") or hasCondition(companion, "out_of_action") or
        companion.deathsDoor or companion.outOfAction then
        return "Familiar is out of action"
    end
    return nil
end

local function commandListFor(companion)
    local validation = M.validateCommandList(companion and (companion.knownCommands or companion.commands) or {}, {
        commandLimit = M.getCommandLimit(companion),
        familiar = companion and (companion.isFamiliar or companion.familiar),
    })
    return validation
end

local function companionOption(companion, selectedId, selectedCommand)
    local validation = commandListFor(companion)
    local unavailableReason = companionUnavailableReason(companion)
    local id = companionId(companion)
    local conditions = {
        staggered = hasCondition(companion, "staggered") or false,
        injured = hasCondition(companion, "injured") or false,
        weak = hasCondition(companion, "weak") or false,
        starving = hasCondition(companion, "starving") or false,
        dead = hasCondition(companion, "dead") or companion.dead == true,
        familiarDeathsDoor = hasCondition(companion, "deaths_door") or hasCondition(companion, "out_of_action") or
            companion.deathsDoor == true or companion.outOfAction == true,
    }
    local known = {}
    for _, command in ipairs(validation.normalizedCommands or {}) do
        known[command] = true
    end
    return {
        key = id,
        id = id,
        label = companion and (companion.name or companion.species or "Animal companion") or "Animal companion",
        companion = companion,
        templateId = companion and companion.templateId or nil,
        species = companion and (companion.species or companion.animalType or companion.kind) or nil,
        feedType = companion and (companion.feedType or companion.species or companion.animalType) or nil,
        commandLimit = validation.limit,
        commandCount = validation.count,
        knownCommands = clone(validation.normalizedCommands),
        knownCommandLabels = clone(validation.commands),
        selected = selectedId ~= nil and tostring(selectedId) == tostring(id),
        selectedCommandKnown = selectedCommand ~= nil and known[selectedCommand] == true,
        familiar = companion and (companion.isFamiliar == true or companion.familiar == true) or false,
        conditions = conditions,
        needsFeed = companion and not conditions.dead and not conditions.familiarDeathsDoor and
            not (companion.feedResolved or companion.animalFeedResolved or companion.selfFeeding) or false,
        feedResolved = companion and (companion.feedResolved == true or companion.animalFeedResolved == true) or false,
        selfFeeding = companion and companion.selfFeeding == true or false,
        carryingSlots = math.max(0, math.floor(tonumber(companion and
            (companion.carrySlots or companion.porterSlots or companion.packSlots)) or 0)),
        noCarryingSlots = companion and (companion.noCarryingSlots == true or
            math.max(0, math.floor(tonumber(companion.carrySlots or companion.porterSlots or companion.packSlots) or 0)) == 0) or true,
        disabled = unavailableReason ~= nil,
        unavailableReason = unavailableReason,
    }
end

local function templateOption(templateId, template, selectedTemplateId)
    return {
        key = templateId,
        id = templateId,
        label = template.name,
        species = template.species or template.animalType,
        animalType = template.animalType or template.species,
        feedType = template.feedType,
        rarityCost = template.rarityCost,
        damage = template.damage,
        aliases = clone(template.aliases),
        suggestedCommands = clone(template.suggestedCommands),
        suitedTests = clone(template.suitedTests or template.favoredTests or template.testSuitability or
            template.suitabilityTags),
        selected = selectedTemplateId ~= nil and tostring(selectedTemplateId) == tostring(templateId),
    }
end

function M.getCompanionOptions(opts)
    opts = opts or {}
    local owner = opts.owner or opts.actor
    local companions = opts.companions or actorCompanions(owner)
    local selectedCompanion = opts.companion or opts.selectedCompanion
    local selectedCompanionId = opts.companionId or opts.selectedCompanionId or companionId(selectedCompanion)
    local selectedCommand = opts.command and M.normalizeCommandName(opts.command) or
        opts.selectedCommand and M.normalizeCommandName(opts.selectedCommand) or nil
    local selectedTemplate, selectedTemplateId = M.getTemplate(opts.templateId or opts.template or opts.animalType)

    local companionOptions = {}
    local selectedCompanionOption = nil
    for _, companion in ipairs(companions or {}) do
        local option = companionOption(companion, selectedCompanionId, selectedCommand)
        if option.selected then
            selectedCompanionOption = option
        end
        companionOptions[#companionOptions + 1] = option
    end
    if selectedCompanion and not selectedCompanionOption then
        selectedCompanionOption = companionOption(selectedCompanion, companionId(selectedCompanion), selectedCommand)
        selectedCompanionOption.selected = true
        companionOptions[#companionOptions + 1] = selectedCompanionOption
    end

    local commandValidation = selectedCompanionOption and {
        normalizedCommands = selectedCompanionOption.knownCommands,
        commands = selectedCompanionOption.knownCommandLabels,
        limit = selectedCompanionOption.commandLimit,
        count = selectedCompanionOption.commandCount,
    } or commandListFor(selectedCompanion)
    local known = {}
    for _, command in ipairs(commandValidation.normalizedCommands or {}) do
        known[command] = true
    end

    local commandOptions = {}
    local selectedCommandOption = nil
    for index, commandId in ipairs(M.commandOrder or {}) do
        local command = M.commands[commandId]
        if command then
            local commandUnavailable = nil
            if selectedCompanionOption and selectedCompanionOption.disabled then
                commandUnavailable = selectedCompanionOption.unavailableReason
            elseif selectedCompanionOption and not known[commandId] then
                commandUnavailable = "Command not trained"
            end
            local option = {
                key = commandId,
                id = commandId,
                index = index,
                label = command.name,
                aliases = clone(command.aliases),
                effect = command.effect,
                targetsCombatant = command.targetsCombatant == true,
                known = known[commandId] == true,
                selected = selectedCommand == commandId,
                disabled = commandUnavailable ~= nil,
                unavailableReason = commandUnavailable,
            }
            if option.selected then
                selectedCommandOption = option
            end
            commandOptions[#commandOptions + 1] = option
        end
    end

    local templateOptions = {}
    for templateId, template in pairs(M.templates or {}) do
        templateOptions[#templateOptions + 1] = templateOption(templateId, template, selectedTemplateId)
    end
    table.sort(templateOptions, function(a, b)
        return (a.label or a.id or "") < (b.label or b.id or "")
    end)

    return {
        rules = M.getRules(),
        companionOptions = companionOptions,
        companions = companionOptions,
        selectedCompanion = selectedCompanionOption,
        commandOptions = commandOptions,
        commands = commandOptions,
        selectedCommand = selectedCommand,
        selectedCommandOption = selectedCommandOption,
        commandLimit = commandValidation.limit,
        commandCount = commandValidation.count,
        commandSlotsRemaining = math.max(0, (commandValidation.limit or 0) - (commandValidation.count or 0)),
        templateOptions = templateOptions,
        templates = templateOptions,
        selectedTemplate = selectedTemplate and templateOption(selectedTemplateId, selectedTemplate, selectedTemplateId) or nil,
        hirelingRule = clone(M.rules.hirelings),
        resultPreview = "animal_companion_options_ready",
    }
end

return M
