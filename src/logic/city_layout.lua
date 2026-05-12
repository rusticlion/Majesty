-- city_layout.lua
-- Appendix D card-driven City map generation.

local constants = require('constants')
local city_districts = require('data.city_districts')

local M = {}

local FACE_VALUES = constants.FACE_VALUES

local function normalizeList(value)
    if not value then
        return {}
    end
    if value.suit or value.name then
        return { value }
    end
    return value
end

local function isFaceCard(card)
    return card and tonumber(card.value) and tonumber(card.value) >= FACE_VALUES.PAGE
end

local function districtKey(card)
    if not card then
        return nil
    end
    local value = tonumber(card.value)
    if not value or not city_districts.getDistrict(card.suit, value) then
        return nil
    end
    return tostring(card.suit) .. ":" .. tostring(value)
end

local function cloneConstantList()
    return {
        city_districts.constants.grey,
        city_districts.constants.ossuary,
        city_districts.constants.omphalic_market,
    }
end

local function drawFromQueue(queue, state)
    if state.queueIndex <= #queue then
        local card = queue[state.queueIndex]
        state.queueIndex = state.queueIndex + 1
        return card, "queue"
    end
    if state.deck and state.deck.draw then
        local card = state.deck:draw()
        if card then
            state.drawnFromDeck = true
        end
        return card, "deck"
    end
    return nil, nil
end

local function discardDraw(state, card)
    if state.discardDraws ~= false and state.deck and state.deck.discard then
        state.deck:discard(card)
    end
end

local function drawCentralCard(state)
    local maxDraws = state.maxDraws
    while true do
        if state.drawAttempts >= maxDraws then
            return nil, "City layout deck did not yield a central power card"
        end
        state.drawAttempts = state.drawAttempts + 1
        local card, source = drawFromQueue(state.cards, state)
        if not card then
            return nil, "City layout generation requires a central power card"
        end

        local hasCentralPower = city_districts.centralPowers[card.suit] ~= nil
        local hasFaceDistrict = isFaceCard(card) and city_districts.getDistrict(card.suit, tonumber(card.value)) ~= nil
        if hasCentralPower or hasFaceDistrict then
            state.drawnCards[#state.drawnCards + 1] = card
            if source == "deck" then
                discardDraw(state, card)
            end
            return card
        end

        state.skippedCards[#state.skippedCards + 1] = card
        if source == "deck" then
            discardDraw(state, card)
        else
            return nil, "City layout central card must be a suited minor arcana card"
        end
    end
end

local function drawDistrictCard(state)
    local maxDraws = state.maxDraws
    while true do
        if state.drawAttempts >= maxDraws then
            return nil, "City layout deck did not yield enough unique district cards"
        end
        state.drawAttempts = state.drawAttempts + 1
        local card, source = drawFromQueue(state.cards, state)
        if not card then
            return nil, "City layout generation requires more district cards"
        end

        local key = districtKey(card)
        if not key then
            state.skippedCards[#state.skippedCards + 1] = card
            if source == "deck" then
                discardDraw(state, card)
            else
                return nil, "City layout district card must map to an Appendix D district"
            end
        elseif state.usedDistrictKeys[key] then
            state.duplicateCards[#state.duplicateCards + 1] = card
            if source == "deck" then
                discardDraw(state, card)
            else
                return nil, "City layout district cards must be unique"
            end
        else
            state.usedDistrictKeys[key] = true
            state.drawnCards[#state.drawnCards + 1] = card
            if source == "deck" then
                discardDraw(state, card)
            end
            return card
        end
    end
end

local function addDistrictPlacement(layout, placement)
    local district = city_districts.getDistrict(placement.card.suit, tonumber(placement.card.value))
    placement.district = district
    layout.districts[#layout.districts + 1] = placement

    for _, specialAction in ipairs(district.specialCityActions or {}) do
        layout.specialCityActions[#layout.specialCityActions + 1] = {
            districtId = district.id,
            districtName = district.name,
            action = specialAction,
        }
    end
end

function M.generateCityLayout(opts)
    opts = opts or {}

    local cards = normalizeList(opts.cityCards or opts.layoutCards or opts.cards)
    local deck = opts.deck or opts.playerDeck or opts.minorDeck
    local requestedMaxDraws = math.floor(tonumber(opts.maxDraws) or 80)

    local state = {
        cards = cards,
        queueIndex = 1,
        deck = deck,
        discardDraws = opts.discardDraws,
        maxDraws = math.max(requestedMaxDraws, #cards),
        drawAttempts = 0,
        drawnCards = {},
        skippedCards = {},
        duplicateCards = {},
        usedDistrictKeys = {},
        drawnFromDeck = false,
    }

    local centralCard, err = drawCentralCard(state)
    if not centralCard then
        return nil, err
    end

    local ruler = city_districts.getCentralPower(centralCard)
    local layout = {
        result = "city_layout_generated",
        centralCard = centralCard,
        ruler = ruler,
        centralDistrict = ruler and ruler.district or nil,
        coreDistricts = {},
        sprawlDistricts = {},
        districts = {},
        constants = opts.includeConstants == false and {} or cloneConstantList(),
        specialCityActions = {},
    }

    if layout.centralDistrict then
        state.usedDistrictKeys[districtKey(centralCard)] = true
        addDistrictPlacement(layout, {
            placement = "central",
            card = centralCard,
        })
    end

    for index, position in ipairs(city_districts.layout.corePositions) do
        local card
        card, err = drawDistrictCard(state)
        if not card then
            return nil, err
        end

        local core = {
            placement = "core",
            index = index,
            position = position,
            card = card,
            sprawlCount = city_districts.sprawlCardsByCoreSuit[card.suit] or 0,
            sprawl = {},
        }
        layout.coreDistricts[#layout.coreDistricts + 1] = core
        addDistrictPlacement(layout, core)
    end

    for _, core in ipairs(layout.coreDistricts) do
        for sprawlIndex = 1, core.sprawlCount do
            local card
            card, err = drawDistrictCard(state)
            if not card then
                return nil, err
            end

            local sprawl = {
                placement = "sprawl",
                index = #layout.sprawlDistricts + 1,
                sprawlIndex = sprawlIndex,
                corePosition = core.position,
                coreDistrictId = core.district.id,
                card = card,
            }
            core.sprawl[#core.sprawl + 1] = sprawl
            layout.sprawlDistricts[#layout.sprawlDistricts + 1] = sprawl
            addDistrictPlacement(layout, sprawl)
        end
    end

    layout.counts = {
        districtPlacements = #layout.districts,
        coreDistricts = #layout.coreDistricts,
        sprawlDistricts = #layout.sprawlDistricts,
        constants = #layout.constants,
        specialCityActions = #layout.specialCityActions,
        totalUniqueDistricts = #layout.districts + #layout.constants,
    }

    return layout, {
        result = "city_layout_generated",
        cards = state.drawnCards,
        cardCount = #state.drawnCards,
        skippedCards = state.skippedCards,
        duplicateCards = state.duplicateCards,
        drawnFromDeck = state.drawnFromDeck,
        drawAttempts = state.drawAttempts,
    }
end

return M
