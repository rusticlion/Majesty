-- smoke_challenge_parity.lua
-- Lightweight parity checks for challenge doom mapping, movement adjacency,
-- and NPC GM-hand draw constraints.

package.path = "./?.lua;./src/?.lua;./src/?/init.lua;./src/?/?.lua;" .. package.path

local constants = require('constants')
local deck = require('logic.deck')
local events = require('logic.events')
local zone_system = require('world.zone_system')
local action_resolver = require('logic.action_resolver')
local npc_ai = require('logic.npc_ai')

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(label .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
    end
end

local function assertTrue(value, label)
    if not value then
        error(label)
    end
end

local function checkDoomClassification()
    for _, card in ipairs(constants.MajorArcana) do
        if card.value >= 1 and card.value <= 14 then
            assertEqual(deck.getDoomType(card), "lesser", "Major " .. card.value .. " should be lesser doom")
            assertTrue(deck.isLesserDoom(card), "Major " .. card.value .. " should satisfy isLesserDoom")
            assertTrue(not deck.isGreaterDoom(card), "Major " .. card.value .. " should not satisfy isGreaterDoom")
        elseif card.value >= 15 and card.value <= 21 then
            assertEqual(deck.getDoomType(card), "greater", "Major " .. card.value .. " should be greater doom")
            assertTrue(deck.isGreaterDoom(card), "Major " .. card.value .. " should satisfy isGreaterDoom")
            assertTrue(not deck.isLesserDoom(card), "Major " .. card.value .. " should not satisfy isLesserDoom")
        end
    end

    local fool = nil
    for _, card in ipairs(constants.MinorArcana) do
        if card.name == "The Fool" then
            fool = card
            break
        end
    end

    assertTrue(fool ~= nil, "The Fool must exist in MinorArcana")
    assertEqual(deck.getDoomType(fool), nil, "The Fool should not be classified as doom")
end

local function buildLinearZones()
    return {
        { id = "A", name = "A", adjacent_to = { "B" } },
        { id = "B", name = "B", adjacent_to = { "A", "C" } },
        { id = "C", name = "C", adjacent_to = { "B" } },
    }
end

local function checkMovementAdjacency()
    local bus = events.createEventBus()
    local zoneRegistry = zone_system.createZoneRegistry({ eventBus = bus })
    local zones = buildLinearZones()
    zoneRegistry:setRoomZones(zones)

    local resolver = action_resolver.createActionResolver({
        eventBus = bus,
        zoneSystem = zoneRegistry,
    })

    local action = {
        challengeController = {
            zones = zones,
        },
    }

    local ok, err = resolver:canMoveBetweenZones(action, "A", "B")
    assertTrue(ok and err == nil, "A->B should be adjacent")

    ok, err = resolver:canMoveBetweenZones(action, "A", "C")
    assertTrue(not ok and err == "zones_not_adjacent", "A->C should be rejected as non-adjacent")

    ok, err = resolver:canMoveBetweenZones(action, "A", "Z")
    assertTrue(not ok and err == "zone_not_found", "A->Z should reject unknown zone")
end

local function checkNPCDrawFloor()
    local bus = events.createEventBus()
    local ai = npc_ai.createNPCAI({
        eventBus = bus,
        challengeController = {
            npcs = {},
            pcs = {},
        },
    })

    local function makeNPC(id)
        return {
            id = id,
            isPC = false,
            rank = "soldier",
            conditions = {},
        }
    end

    local function makePC(id)
        return {
            id = id,
            isPC = true,
            conditions = {},
        }
    end

    ai.challengeController.npcs = {
        makeNPC("n1"),
        makeNPC("n2"),
        makeNPC("n3"),
        makeNPC("n4"),
        makeNPC("n5"),
    }
    ai.challengeController.pcs = {
        makePC("p1"),
        makePC("p2"),
        makePC("p3"),
        makePC("p4"),
        makePC("p5"),
    }

    local drawCount = ai:calculateRoundDrawCount()
    assertTrue(drawCount >= #ai.challengeController.npcs, "Draw count should cover NPC initiative submissions")
end

checkDoomClassification()
checkMovementAdjacency()
checkNPCDrawFloor()

print("smoke_challenge_parity: ok")
