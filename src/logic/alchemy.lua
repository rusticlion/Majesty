-- alchemy.lua
-- Rulebook-backed alchemy procedures shared by crawl and camp systems.

local events = require('logic.events')
local inventory = require('logic.inventory')
local item_templates = require('data.item_templates')
local currency = require('logic.currency')

local M = {}

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
    local templateId = request.reagentTemplateId or request.templateId or request.itemTemplateId
    if templateId then
        return templateId
    end

    local source = normalizeKey(request.source or request.creature or request.monster or request.reagent)
    if source ~= "" then
        return M.MENAGERIE_REAGENTS[source]
    end

    return nil
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

    local result = {
        actor = actor,
        source = source,
        reagent = reagent,
        bottle = bottle,
        watchResult = watchResult,
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
    local templateId = resolveReagentTemplateId(request)

    if not templateId or not isReagentTemplate(templateId) then
        return false, "Unknown alchemical reagent"
    end

    if not buyer or not buyer.inventory or not buyer.inventory.addItem then
        return false, "No inventory for reagent"
    end

    local cost = quantity * (tonumber(opts.costPerReagent or request.costPerReagent) or M.MENAGERIE_REAGENT_COST)
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

    for _, reagent in ipairs(reagents) do
        reagent.properties = reagent.properties or {}
        reagent.properties.hermeticBottle = true
        reagent.properties.cityPurchased = true
        reagent.properties.purchasedAt = opts.locationName or request.locationName or "Master Underhill's Menagerie"
        reagent.properties.purchaseCost = tonumber(opts.costPerReagent or request.costPerReagent) or M.MENAGERIE_REAGENT_COST
        buyer.inventory:addItem(reagent, location)
    end

    local result = {
        buyer = buyer,
        reagents = reagents,
        templateId = templateId,
        quantity = quantity,
        cost = cost,
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
