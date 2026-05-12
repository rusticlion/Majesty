-- guild_restock.lua
-- Data-driven shopping/restock helpers for returning to the City.

local inventory = require('logic.inventory')

local M = {}

function M.matchesRestockRule(item, rule)
    if not item or not rule then
        return false
    end

    if rule.any then
        for _, childRule in ipairs(rule.any) do
            if M.matchesRestockRule(item, childRule) then
                return true
            end
        end
        return false
    end

    if rule.all then
        for _, childRule in ipairs(rule.all) do
            if not M.matchesRestockRule(item, childRule) then
                return false
            end
        end
        return true
    end

    if rule.property then
        local value = item.properties and item.properties[rule.property]
        if rule.equals ~= nil then
            return value == rule.equals
        end
        return value ~= nil and value ~= false
    end

    if rule.field then
        local value = item[rule.field]
        if rule.equals ~= nil then
            return value == rule.equals
        end
        return value ~= nil and value ~= false
    end

    if rule.nameContains then
        local name = item.name and item.name:lower() or ""
        return name:find(rule.nameContains:lower(), 1, true) ~= nil
    end

    return false
end

function M.createRestockItem(supply)
    if supply.templateId then
        return inventory.createItemFromTemplate(supply.templateId, supply.overrides)
    end
    if supply.item then
        return inventory.createItem(supply.item)
    end
    return nil
end

function M.restockAdventurer(pc, restockData)
    restockData = restockData or {}

    if pc.ammo ~= nil and restockData.ammo and restockData.ammo.default then
        pc.ammo = restockData.ammo.default
    end

    if not pc.inventory then
        return
    end

    for _, supply in ipairs(restockData.supplies or {}) do
        local existing = pc.inventory:findItemByPredicate(function(item)
            return M.matchesRestockRule(item, supply.match)
        end)

        if not existing then
            local item = M.createRestockItem(supply)
            if item then
                pc.inventory:addItem(item, supply.location or inventory.LOCATIONS.PACK)
            end
        end
    end
end

function M.restockGuild(guild, restockData)
    for _, pc in ipairs(guild or {}) do
        M.restockAdventurer(pc, restockData)
    end
end

return M
