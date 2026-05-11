-- currency.lua
-- Shared liquid-gold helpers for City Phase and market procedures.

local M = {}

local function isCurrencyItem(item)
    local props = item and item.properties or {}
    return props.currency == true and (tonumber(props.value) or 0) > 0
end

function M.isCurrencyItem(item)
    return isCurrencyItem(item)
end

function M.getCarriedGold(actor)
    local inv = actor and actor.inventory
    if not inv or not inv.getAllItems then
        return 0
    end

    local total = 0
    for _, entry in ipairs(inv:getAllItems()) do
        local item = entry.item
        if isCurrencyItem(item) then
            total = total + ((item.quantity or 1) * (tonumber(item.properties.value) or 0))
        end
    end
    return total
end

function M.getGold(actor)
    return (tonumber(actor and actor.gold) or 0) + M.getCarriedGold(actor)
end

local function spendCarriedGold(actor, amount)
    local inv = actor and actor.inventory
    if amount <= 0 then
        return true
    end
    if not inv or not inv.getAllItems then
        return false
    end

    for _, entry in ipairs(inv:getAllItems()) do
        local item = entry.item
        local value = item and item.properties and tonumber(item.properties.value) or 0
        if isCurrencyItem(item) and value == 1 then
            local spend = math.min(amount, item.quantity or 1)
            inv:removeItemQuantity(item.id, spend)
            amount = amount - spend
            if amount <= 0 then
                return true
            end
        end
    end

    return false
end

function M.spendGold(actor, amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then
        return true
    end
    if M.getGold(actor) < amount then
        return false
    end

    local remaining = amount
    local purse = tonumber(actor.gold) or 0
    if purse > 0 then
        local spend = math.min(purse, remaining)
        actor.gold = purse - spend
        remaining = remaining - spend
    end

    if remaining > 0 and not spendCarriedGold(actor, remaining) then
        return false
    end

    return true
end

function M.addGold(actor, amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 or not actor then
        return false
    end
    actor.gold = (tonumber(actor.gold) or 0) + amount
    return true
end

function M.collectPercentTax(actor, rate)
    rate = tonumber(rate) or 0
    local startingGold = M.getGold(actor)
    local tax = math.floor(startingGold * rate)

    if tax > 0 and not M.spendGold(actor, tax) then
        return false, "Not enough gold"
    end

    return true, {
        actor = actor,
        startingGold = startingGold,
        taxPaid = tax,
        remainingGold = M.getGold(actor),
        rate = rate,
    }
end

return M
