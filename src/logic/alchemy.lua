-- alchemy.lua
-- Rulebook-backed alchemy procedures shared by crawl and camp systems.

local events = require('logic.events')
local inventory = require('logic.inventory')
local item_templates = require('data.item_templates')
local currency = require('logic.currency')

local M = {}

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

M.MENAGERIE_REAGENT_COST = 25
M.MENAGERIE_REAGENTS = {
    brain_spider = "brain_spider_reagent",
    cockatrice = "cockatrice_reagent",
    devil = "devil_reagent",
    face_rat = "face_rat_reagent",
    fungoid = "fungoid_reagent",
    griffin = "griffin_reagent",
    harpy = "harpy_reagent",
    imp = "imp_reagent",
    jinn = "jinn_reagent",
    kelpie = "kelpie_reagent",
    mimic = "mimic_reagent",
    nymph = "nymph_reagent",
    ogre = "ogre_reagent",
    questing_beast = "questing_beast_reagent",
    slime = "slime_reagent",
    titan = "titan_reagent",
    ungoat = "ungoat_reagent",
    vampire = "vampire_reagent",
    winter_wolf = "winter_wolf_reagent",
}

local function normalizeTalentId(talentId)
    return tostring(talentId or ""):lower():gsub("%s+", "_"):gsub("'", "")
end

local function getTalentRecord(entity, talentId)
    if not entity or not entity.talents then
        return nil
    end
    return entity.talents[talentId]
end

function M.hasUsableTalent(actor, talentId)
    local requested = normalizeTalentId(talentId)
    for id in pairs(actor and actor.talents or {}) do
        if normalizeTalentId(id) == requested then
            local talent = getTalentRecord(actor, id)
            if type(talent) == "table" then
                return talent.wounded ~= true
            end
            return talent == true
        end
    end
    return false
end

function M.hasAlchemyTalent(actor)
    return M.hasUsableTalent(actor, "alchemy")
end

local function isEmptyHermeticBottle(item)
    local props = item and item.properties or {}
    if not item then
        return false
    end

    local bottle = item.templateId == "hermetic_bottle" or
        item.type == "hermetic_bottle" or
        props.hermeticBottle == true
    if not bottle then
        return false
    end

    return props.empty == true and
        props.reagent ~= true and
        props.alchemicalReagent ~= true and
        props.alchemical ~= true
end

function M.findEmptyHermeticBottle(actor)
    local inv = actor and actor.inventory
    if not inv or not inv.findItemByPredicate then
        return nil, nil
    end
    return inv:findItemByPredicate(isEmptyHermeticBottle)
end

function M.getGold(actor)
    return currency.getGold(actor)
end

local function isReagentTemplate(templateId)
    local template = item_templates.getTemplate(templateId)
    local props = template and template.properties or {}
    return template ~= nil and (
        template.type == "reagent" or
        props.reagent == true or
        props.alchemicalReagent == true
    )
end

local function isReagentItem(item)
    local props = item and item.properties or {}
    return item ~= nil and (
        item.type == "reagent" or
        props.reagent == true or
        props.alchemicalReagent == true
    )
end

local function normalizeKey(value)
    return tostring(value or ""):lower():gsub("%s+", "_")
end

local function resolveReagentTemplateId(request)
    request = request or {}
    local templateId = request.reagentTemplateId or request.templateId or request.itemTemplateId or request.template
    if templateId then
        return templateId
    end

    local source = normalizeKey(request.source or request.creature or request.monster or request.reagent)
    if source ~= "" then
        return M.MENAGERIE_REAGENTS[source]
    end

    return nil
end

local function stockEntryRecord(entry, key)
    if type(entry) == "table" then
        return entry, entry
    elseif type(entry) == "string" then
        return {
            id = key,
            reagentTemplateId = entry,
        }, nil
    end
    return nil, nil
end

local function stockEntryMatches(entry, key, lookup, lookupKey)
    local candidates = { key }
    if type(entry) == "table" then
        candidates[#candidates + 1] = entry.id
        candidates[#candidates + 1] = entry.stockId
        candidates[#candidates + 1] = entry.catalogId
        candidates[#candidates + 1] = entry.source
        candidates[#candidates + 1] = entry.creature
        candidates[#candidates + 1] = entry.monster
        candidates[#candidates + 1] = entry.reagent
        candidates[#candidates + 1] = entry.reagentTemplateId
        candidates[#candidates + 1] = entry.templateId
        candidates[#candidates + 1] = entry.name
        candidates[#candidates + 1] = entry.title
    else
        candidates[#candidates + 1] = entry
    end

    for _, candidate in ipairs(candidates) do
        if candidate ~= nil then
            local text = tostring(candidate)
            if text == lookup or normalizeKey(text) == lookupKey then
                return true
            end
        end
    end
    return false
end

local function findMenagerieStockEntry(stock, request)
    if type(request.stockEntry) == "table" then
        return request.stockEntry, request.stockEntry, request.stockEntry.id or request.stockEntry.stockId
    end
    if type(request.stockItem) == "table" then
        return request.stockItem, request.stockItem, request.stockItem.id or request.stockItem.stockId
    end
    if type(stock) ~= "table" then
        return nil, nil, nil
    end

    local lookup = request.stockId or request.reagentStockId or request.catalogId or request.source or
        request.creature or request.monster or request.reagent or request.reagentTemplateId or request.templateId
    local lookupText = tostring(lookup or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if lookupText == "" then
        return nil, nil, nil
    end

    local lookupKey = normalizeKey(lookupText)
    local direct = stock[lookupText] or stock[lookupKey]
    if direct ~= nil then
        local record, state = stockEntryRecord(direct, lookupKey)
        return record, state, lookupKey
    end

    for key, entry in pairs(stock) do
        if stockEntryMatches(entry, key, lookupText, lookupKey) then
            local record, state = stockEntryRecord(entry, key)
            return record, state, key
        end
    end
    return nil, nil, nil
end

local function stockQuantityAvailable(stockRecord)
    if type(stockRecord) ~= "table" then
        return nil
    end
    local value = stockRecord.quantityAvailable
    if value == nil then
        value = stockRecord.available
    end
    if value == nil then
        value = stockRecord.stock
    end
    if value == nil then
        value = stockRecord.countAvailable
    end
    return value ~= nil and math.max(0, math.floor(tonumber(value) or 0)) or nil
end

local function decrementStockQuantity(stockState, quantity)
    if type(stockState) ~= "table" then
        return nil
    end

    local field = nil
    if stockState.quantityAvailable ~= nil then
        field = "quantityAvailable"
    elseif stockState.available ~= nil then
        field = "available"
    elseif stockState.stock ~= nil then
        field = "stock"
    elseif stockState.countAvailable ~= nil then
        field = "countAvailable"
    end

    if not field then
        return nil
    end
    stockState[field] = math.max(0, math.floor(tonumber(stockState[field]) or 0) - quantity)
    return stockState[field]
end

local function inventoryHasRoom(actor, location, items)
    local inv = actor and actor.inventory
    if not inv or not inv.availableSlots then
        return false
    end

    location = location or inventory.LOCATIONS.PACK
    local needed = 0
    for _, item in ipairs(items or {}) do
        needed = needed + (item.stackable and 1 or item.size or 1)
    end
    return inv:availableSlots(location) >= needed
end

local function sourceHasNoGuts(source, data)
    data = data or {}
    if data.allowNoGuts == true then
        return false
    end

    return source and (
        source.undead == true or
        source.construct == true or
        source.automaton == true
    )
end

local HUMANOID_REAGENT_EXCLUSIONS = {
    human = true,
    humans = true,
    orc = true,
    orcs = true,
    elf = true,
    elves = true,
    high_elf = true,
    high_elves = true,
    wood_elf = true,
    wood_elves = true,
    dark_elf = true,
    dark_elves = true,
    underfolk = true,
    dwarf = true,
    dwarves = true,
    halfling = true,
    halflings = true,
    troll = true,
    trolls = true,
    gnome = true,
    gnomes = true,
}

local function sourceIsSentientHumanoid(source)
    if not source then
        return false
    end
    if source.isPC == true or source.sentientHumanoid == true then
        return true
    end

    local function excluded(value)
        return HUMANOID_REAGENT_EXCLUSIONS[normalizeKey(value)] == true
    end

    if excluded(source.kin) or excluded(source.kith) or excluded(source.species) or
       excluded(source.race) or excluded(source.ancestry) then
        return true
    end

    local sourceType = normalizeKey(source.type or source.creatureType or source.kind)
    if sourceType == "humanoid" or sourceType == "person" or sourceType == "adventurer" then
        return true
    end

    if type(source.tags) == "table" then
        for _, tag in ipairs(source.tags) do
            if tag == "sentient_humanoid" or tag == "humanoid" or excluded(tag) then
                return true
            end
        end
    end

    return false
end

local function getHarvestData(source)
    if not source then
        return nil
    end

    local data = source.alchemy or source.alchemyReagent or {}
    if type(data) == "string" then
        data = { reagentTemplateId = data }
    elseif type(data) ~= "table" then
        data = {}
    end

    data.reagentTemplateId = data.reagentTemplateId or source.reagentTemplateId
    data.yield = tonumber(data.yield or data.yields or data.count or source.reagentCount) or 1
    data.harvestedCount = tonumber(data.harvestedCount or source.harvestedReagents) or 0

    if not data.reagentTemplateId then
        return nil
    end
    return data
end

local function hasFreshCorpse(source, currentWatch)
    if not source then
        return false, "Requires fresh monstrous corpse"
    end

    local isCorpse = source.type == "corpse" or source.isCorpse == true or source.dead == true or
        (source.conditions and source.conditions.dead == true)
    if not isCorpse then
        return false, "Requires fresh monstrous corpse"
    end

    if source.freshCorpse == false or source.staleCorpse == true then
        return false, "Reagents have spoiled"
    end

    local killedAt = tonumber(source.defeatedAtWatch or source.killedAtWatch or source.corpseWatch)
    local watchNumber = tonumber(currentWatch)
    if killedAt and watchNumber and watchNumber - killedAt >= 1 then
        return false, "Reagents have spoiled"
    end

    return true, nil
end

local function replaceBottleWithReagent(inv, bottle, reagent, location)
    for i, item in ipairs(inv[location] or {}) do
        if item.id == bottle.id then
            inv[location][i] = reagent
            return true
        end
    end
    return false
end

local function sourceTotalHD(source)
    if not source then
        return nil
    end
    local hd = source.totalHD or source.hd
    if hd then
        return tonumber(hd)
    end
    return (tonumber(source.npcMaxHealth or source.health or source.npcHealth) or 0) +
        (tonumber(source.npcMaxDefense or source.defense or source.npcDefense) or 0)
end

local function markHarvestedSource(source, data, watchNumber)
    if not source or not data or data.depleted ~= true then
        return nil
    end

    local isCorpse = source.type == "corpse" or source.isCorpse == true or source.dead == true or
        (source.conditions and source.conditions.dead == true)
    if not isCorpse then
        return nil
    end

    source.reagentsHarvested = true
    source.reagentsDepleted = true
    source.freshCorpse = false
    source.harvestedAtWatch = watchNumber
    if source.state == nil or source.state == "fresh" then
        source.state = "harvested"
    end
    if source.type == "corpse" then
        source.description = "The harvested remains of " .. (source.name or "a monster") .. " lie here."
    end

    return {
        sourceId = source.id,
        state = source.state,
        harvestedAtWatch = watchNumber,
        depleted = true,
    }
end

local function findCarriedReagent(actor, request)
    request = request or {}
    local inv = actor and actor.inventory
    if not inv or not inv.getAllItems then
        return nil, nil
    end

    if type(request.reagent) == "table" then
        local item, location = inv:findItem(request.reagent.id)
        if item and isReagentItem(item) then
            return item, location
        end
        return nil, nil
    end

    local wantedId = request.reagentId or request.itemId or request.id
    local wantedTemplate = request.reagentTemplateId or request.templateId
    local wantedSource = request.source or request.creature or request.monster

    for _, entry in ipairs(inv:getAllItems()) do
        local item = entry.item
        local props = item.properties or {}
        if isReagentItem(item) then
            local matches = true
            if wantedId and item.id ~= wantedId then
                matches = false
            end
            if wantedTemplate and item.templateId ~= wantedTemplate then
                matches = false
            end
            if wantedSource and normalizeKey(props.source) ~= normalizeKey(wantedSource) then
                matches = false
            end
            if matches then
                return item, entry.location
            end
        end
    end

    return nil, nil
end

function M.calculateReagentSaleValue(reagent, opts)
    opts = opts or {}
    local props = reagent and reagent.properties or {}
    local explicit = opts.price or opts.value or opts.gold
    if explicit then
        return math.max(0, math.floor(tonumber(explicit) or 0))
    end

    local storedValue = props.saleValue or props.goldValue or props.value
    if storedValue then
        return math.max(0, math.floor(tonumber(storedValue) or 0))
    end

    local totalHD = tonumber(props.sourceTotalHD or props.totalHD or props.hd)
    if totalHD then
        return math.max(0, math.floor(totalHD * 5))
    end

    return nil
end

local function currentWatchNumber(opts)
    local manager = opts and opts.watchManager
    if manager and manager.getWatchCount then
        return manager:getWatchCount()
    end
    return opts and opts.currentWatch
end

local function spendHarvestWatch(opts)
    opts = opts or {}
    if opts.watchManager and opts.watchManager.incrementWatch then
        return opts.watchManager:incrementWatch(opts.watchOptions or {})
    end
    if opts.spendWatch then
        return opts.spendWatch()
    end
    if opts.watchSpent == true then
        return { watchSpent = true, watchNumber = opts.currentWatch }
    end
    return nil
end

function M.getHarvestReagentOptions(actor, sources, opts)
    opts = opts or {}

    if sources == nil then
        sources = opts.sources or opts.corpses or opts.features or opts.roomFeatures or opts.source
    end
    if sources ~= nil and (sources.id ~= nil or sources.alchemy ~= nil or sources.alchemyReagent ~= nil or
       sources.type == "corpse" or sources.isCorpse == true or sources.dead == true) then
        sources = { sources }
    end
    sources = sources or {}

    local unavailableReasons = {}
    local function addReason(reason)
        if not reason then
            return
        end
        for _, existing in ipairs(unavailableReasons) do
            if existing == reason then
                return
            end
        end
        unavailableReasons[#unavailableReasons + 1] = reason
    end

    local hasTalent = M.hasAlchemyTalent(actor)
    local bottle, bottleLocation = M.findEmptyHermeticBottle(actor)
    local hasBottle = bottle ~= nil
    local currentWatch = currentWatchNumber(opts)

    if not actor then
        addReason("no_actor")
    end
    if not hasTalent then
        addReason("Requires Alchemy talent")
    end
    if not hasBottle then
        addReason("Requires empty hermetic bottle")
    end
    if #sources == 0 then
        addReason("Requires fresh monstrous corpse")
    end

    local function bottlePreview()
        if not bottle then
            return nil
        end
        return {
            id = bottle.id,
            name = bottle.name,
            templateId = bottle.templateId,
            location = bottleLocation,
            size = bottle.size,
        }
    end

    local function sourceMatchesSelection(source)
        local selected = opts.source or opts.selectedSource or opts.corpse
        local selectedId = opts.sourceId or opts.selectedSourceId or opts.corpseId
        if type(selected) == "table" then
            return selected == source or (selected.id ~= nil and selected.id == source.id)
        end
        if selectedId ~= nil then
            return source and source.id == selectedId
        end
        if selected ~= nil then
            return source and source.id == selected
        end
        return false
    end

    local sourceOptions = {}
    local selectedSource = nil
    local selectionRequested = opts.sourceId ~= nil or opts.selectedSourceId ~= nil or opts.corpseId ~= nil or
        opts.selectedSource ~= nil or opts.corpse ~= nil
    local harvestableCount = 0
    for _, source in ipairs(sources) do
        local data = getHarvestData(source)
        local templateId = data and data.reagentTemplateId
        local template = templateId and item_templates.getTemplate(templateId)
        local fresh, freshReason = hasFreshCorpse(source, currentWatch)
        local harvestedCount = data and data.harvestedCount or 0
        local yield = data and data.yield or 0
        local remaining = math.max(0, (yield or 0) - (harvestedCount or 0))
        local sourceReasons = {}
        local function addSourceReason(reason)
            if reason then
                sourceReasons[#sourceReasons + 1] = reason
            end
        end

        if not data or sourceHasNoGuts(source, data) then
            addSourceReason("No viable alchemical reagents")
        elseif sourceIsSentientHumanoid(source) then
            addSourceReason("Sentient humanoids yield no reagents")
        elseif harvestedCount >= yield then
            addSourceReason("No viable alchemical reagents remain")
        elseif not fresh then
            addSourceReason(freshReason)
        elseif not item_templates.hasTemplate(templateId) then
            addSourceReason("Unknown alchemical reagent")
        end

        if not hasTalent then
            addSourceReason("Requires Alchemy talent")
        end
        if not hasBottle then
            addSourceReason("Requires empty hermetic bottle")
        end

        local reagentProps = template and template.properties or {}
        local previewSourceIsCorpse = source and (source.type == "corpse" or source.isCorpse == true or
            source.dead == true or (source.conditions and source.conditions.dead == true))
        local option = {
            id = source and source.id or nil,
            name = source and source.name or nil,
            type = source and source.type or nil,
            sourceBlueprintId = source and source.blueprintId or nil,
            defeatedAtWatch = source and (source.defeatedAtWatch or source.killedAtWatch or source.corpseWatch),
            currentWatch = currentWatch,
            freshCorpse = fresh,
            harvestedCount = harvestedCount,
            yield = yield,
            remainingYield = remaining,
            depleted = data and data.depleted == true or remaining <= 0,
            reagentTemplateId = templateId,
            reagentName = template and template.name or nil,
            reagentSource = reagentProps.source,
            sourceTotalHD = sourceTotalHD(source),
            disabled = #sourceReasons > 0,
            unavailableReasons = sourceReasons,
            selected = sourceMatchesSelection(source),
            actionDataPreview = {
                action = "harvest_reagent",
                sourceId = source and source.id or nil,
                corpseId = source and source.id or nil,
            },
        }

        if template then
            option.reagentPreview = {
                templateId = templateId,
                name = template.name,
                type = template.type,
                source = reagentProps.source,
                hermeticBottle = true,
                saleValue = option.sourceTotalHD and option.sourceTotalHD * 5 or reagentProps.saleValue,
            }
        end

        if not option.disabled then
            harvestableCount = harvestableCount + 1
            option.resultPreview = {
                result = "reagent_harvested",
                reagentTemplateId = templateId,
                reagentName = template and template.name or nil,
                bottleId = bottle and bottle.id or nil,
                bottleLocation = bottleLocation,
                watchSpent = true,
                remainingYieldAfterHarvest = math.max(0, remaining - 1),
                sourceState = remaining <= 1 and {
                    sourceId = source and source.id or nil,
                    state = previewSourceIsCorpse and "harvested" or source and source.state,
                    depleted = true,
                    freshCorpse = false,
                } or nil,
            }
        end

        if option.selected then
            selectedSource = option
        end
        sourceOptions[#sourceOptions + 1] = option
    end

    if selectionRequested and selectedSource == nil then
        addReason("selected_source_unavailable")
    elseif selectedSource and selectedSource.disabled then
        addReason(selectedSource.unavailableReasons[1] or "selected_source_unavailable")
    end

    return {
        result = "harvest_reagent_options_ready",
        actorId = actor and actor.id or nil,
        actorName = actor and actor.name or nil,
        disabled = #unavailableReasons > 0 or harvestableCount == 0 or
            (selectedSource ~= nil and selectedSource.disabled == true),
        unavailableReasons = unavailableReasons,
        hasAlchemyTalent = hasTalent,
        hasEmptyHermeticBottle = hasBottle,
        bottle = bottlePreview(),
        currentWatch = currentWatch,
        sourceOptions = sourceOptions,
        selectedSource = selectedSource,
        harvestableCount = harvestableCount,
        rules = {
            requiresAlchemyTalent = true,
            requiresEmptyHermeticBottle = true,
            requiresFreshMonstrousCorpse = true,
            spendsWatch = true,
            spoilsAfterOneWatch = true,
            excludesUndeadConstructsAndSentientHumanoids = true,
        },
    }
end

function M.canHarvestReagent(actor, source, opts)
    opts = opts or {}

    if not M.hasAlchemyTalent(actor) then
        return false, "Requires Alchemy talent"
    end

    if not M.findEmptyHermeticBottle(actor) then
        return false, "Requires empty hermetic bottle"
    end

    local data = getHarvestData(source)
    if not data or sourceHasNoGuts(source, data) then
        return false, "No viable alchemical reagents"
    end

    if sourceIsSentientHumanoid(source) then
        return false, "Sentient humanoids yield no reagents"
    end

    if data.harvestedCount >= data.yield then
        return false, "No viable alchemical reagents remain"
    end

    local fresh, reason = hasFreshCorpse(source, currentWatchNumber(opts))
    if not fresh then
        return false, reason
    end

    if not item_templates.hasTemplate(data.reagentTemplateId) then
        return false, "Unknown alchemical reagent"
    end

    return true, nil, data
end

function M.resolveHarvestReagent(actor, source, opts)
    opts = opts or {}
    local eventBus = opts.eventBus or events.globalBus
    local bottle, bottleLocation = M.findEmptyHermeticBottle(actor)
    local ok, reason, data = M.canHarvestReagent(actor, source, opts)
    if not ok then
        return false, reason
    end

    local watchResult = spendHarvestWatch(opts)
    if not watchResult then
        return false, "Requires a watch"
    end

    local reagent = inventory.createItemFromTemplate(data.reagentTemplateId)
    if not reagent then
        return false, "Unknown alchemical reagent"
    end

    reagent.properties = reagent.properties or {}
    reagent.properties.hermeticBottle = true
    reagent.properties.harvestedFrom = source.name or source.id
    reagent.properties.harvestedAtWatch = watchResult.watchNumber or opts.currentWatch
    reagent.properties.sourceEntityId = source.id
    reagent.properties.sourceBlueprintId = source.blueprintId
    reagent.properties.sourceTotalHD = sourceTotalHD(source)
    if reagent.properties.sourceTotalHD then
        reagent.properties.saleValue = reagent.properties.sourceTotalHD * 5
    end

    if not replaceBottleWithReagent(actor.inventory, bottle, reagent, bottleLocation) then
        return false, "Could not bottle reagent"
    end

    source.alchemy = source.alchemy or data
    source.alchemy.harvestedCount = (source.alchemy.harvestedCount or data.harvestedCount or 0) + 1
    if source.alchemy.harvestedCount >= (source.alchemy.yield or data.yield or 1) then
        source.alchemy.depleted = true
    end
    local sourceState = markHarvestedSource(source, source.alchemy, watchResult.watchNumber or opts.currentWatch)

    local result = {
        actor = actor,
        source = source,
        reagent = reagent,
        bottle = bottle,
        watchResult = watchResult,
        sourceState = sourceState,
        result = "reagent_harvested",
    }

    eventBus:emit(events.EVENTS.ALCHEMY_REAGENT_HARVESTED or "alchemy_reagent_harvested", result)

    return true, "reagent_harvested", result
end

function M.resolveMenagerieReagentPurchase(buyer, request, opts)
    request = request or {}
    opts = opts or {}
    local eventBus = opts.eventBus or events.globalBus
    local quantity = math.max(1, tonumber(request.quantity or request.count) or 1)
    local stockRecord, stockState, stockKey = findMenagerieStockEntry(
        request.stock or request.catalog or opts.stock or opts.menagerieStock or opts.catalog,
        request
    )
    local templateId = stockRecord and resolveReagentTemplateId(stockRecord) or resolveReagentTemplateId(request)

    if not templateId or not isReagentTemplate(templateId) then
        return false, "Unknown alchemical reagent"
    end

    local available = stockQuantityAvailable(stockRecord)
    if available ~= nil and quantity > available then
        return false, "Reagent stock unavailable"
    end

    if not buyer or not buyer.inventory or not buyer.inventory.addItem then
        return false, "No inventory for reagent"
    end

    local costPerReagent = tonumber(opts.costPerReagent or request.costPerReagent or request.pricePerReagent or
        (stockRecord and (stockRecord.costPerReagent or stockRecord.pricePerReagent or stockRecord.price or
            stockRecord.cost))) or M.MENAGERIE_REAGENT_COST
    local cost = quantity * costPerReagent
    if currency.getGold(buyer) < cost then
        return false, "Not enough gold"
    end

    local location = request.location or opts.location or inventory.LOCATIONS.PACK
    local reagents = {}
    for _ = 1, quantity do
        local reagent = inventory.createItemFromTemplate(templateId)
        if not reagent then
            return false, "Unknown alchemical reagent"
        end
        reagents[#reagents + 1] = reagent
    end

    if not inventoryHasRoom(buyer, location, reagents) then
        return false, "insufficient_slots"
    end

    if not currency.spendGold(buyer, cost) then
        return false, "Not enough gold"
    end

    local stockId = stockRecord and (stockRecord.id or stockRecord.stockId or stockKey) or nil
    local stockName = stockRecord and (stockRecord.name or stockRecord.title) or nil
    local stockProperties = stockRecord and stockRecord.properties or nil
    local purchasedAt = opts.locationName or request.locationName or
        (stockRecord and (stockRecord.locationName or stockRecord.location)) or "Master Underhill's Menagerie"
    for _, reagent in ipairs(reagents) do
        reagent.properties = reagent.properties or {}
        if type(stockProperties) == "table" then
            for key, value in pairs(stockProperties) do
                reagent.properties[key] = cloneValue(value)
            end
        end
        reagent.properties.hermeticBottle = true
        reagent.properties.cityPurchased = true
        reagent.properties.purchasedAt = purchasedAt
        reagent.properties.purchaseCost = costPerReagent
        reagent.properties.menagerieStockId = stockId
        reagent.properties.menagerieStockName = stockName
        buyer.inventory:addItem(reagent, location)
    end
    local stockRemaining = decrementStockQuantity(stockState, quantity)

    local result = {
        buyer = buyer,
        reagents = reagents,
        templateId = templateId,
        quantity = quantity,
        costPerReagent = costPerReagent,
        cost = cost,
        stock = stockRecord,
        stockId = stockId,
        stockName = stockName,
        stockRemaining = stockRemaining,
        result = "reagent_purchased",
    }

    eventBus:emit(events.EVENTS.ALCHEMY_REAGENT_PURCHASED or "alchemy_reagent_purchased", result)

    return true, "reagent_purchased", result
end

function M.resolveReagentSale(seller, request, opts)
    request = request or {}
    opts = opts or {}
    local eventBus = opts.eventBus or events.globalBus

    local reagent, location = findCarriedReagent(seller, request)
    if not reagent then
        return false, "Requires bottled reagent"
    end

    local props = reagent.properties or {}
    if props.hermeticBottle ~= true then
        return false, "Requires bottled reagent"
    end

    local value = M.calculateReagentSaleValue(reagent, {
        price = opts.price or request.price,
        value = opts.value or request.value,
        gold = opts.gold or request.gold,
    })
    if not value then
        return false, "Reagent value unknown"
    end

    if not seller or not seller.inventory or not seller.inventory.removeItem then
        return false, "No inventory for reagent"
    end

    local removed = seller.inventory:removeItem(reagent.id)
    if not removed then
        return false, "Requires bottled reagent"
    end

    currency.addGold(seller, value)

    local result = {
        seller = seller,
        reagent = reagent,
        location = location,
        value = value,
        result = "reagent_sold",
    }

    eventBus:emit(events.EVENTS.ALCHEMY_REAGENT_SOLD or "alchemy_reagent_sold", result)

    return true, "reagent_sold", result
end

return M
