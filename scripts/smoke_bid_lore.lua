-- smoke_bid_lore.lua
-- Quick vertical-slice checks for Bid Lore engine + resolver plumbing.

package.path = "./?.lua;./src/?.lua;./src/?/init.lua;./src/?/?.lua;" .. package.path

local events = require('logic.events')
local bid_lore_engine = require('logic.bid_lore_engine')
local action_resolver = require('logic.action_resolver')

local function assertTrue(value, label)
    if not value then
        error(label)
    end
end

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s (expected %s, got %s)", label, tostring(expected), tostring(actual)))
    end
end

local engine = bid_lore_engine.createBidLoreEngine({})

local available = engine:getAvailableSubjects({
    challengeController = {
        roomId = "105_hall_of_solemnity",
        npcs = {
            { blueprintId = "brain_spider", conditions = {} },
        },
    },
})
assertTrue(#available > 0, "Expected at least one available lore subject")

local verdict = engine:adjudicate({
    subjectId = "monster_brain_spider",
    questionType = "vulnerability",
    motif = "Veteran Soldier",
    focus = "tactics",
})
assertEqual(verdict.verdict, "accepted", "Veteran Soldier vulnerability query should be accepted")

local bus = events.createEventBus()
local emittedRequest = false
bus:on(events.EVENTS.REQUEST_BID_LORE, function(_)
    emittedRequest = true
end)

local resolver = action_resolver.createActionResolver({
    eventBus = bus,
    bidLoreEngine = engine,
})

local actor = {
    id = "pc_1",
    name = "Tester",
    loreBids = 4,
    conditions = {},
}

local action = {
    actor = actor,
    card = { name = "The Magician", suit = 5, value = 1, is_major = true },
    type = "bid_lore",
    challengeController = {
        isActive = function()
            return true
        end,
        roomId = "105_hall_of_solemnity",
        npcs = {},
    },
}

local result = resolver:resolve(action)
assertTrue(result.pendingBidLore == true, "Bid Lore action should enter pending async state")
assertTrue(emittedRequest, "Bid Lore request event should be emitted")

local finalized = resolver:resolveBidLoreOutcome(action, verdict)
assertEqual(finalized.success, true, "Accepted lore verdict should be successful")
assertEqual(actor.loreBids, 3, "Accepted lore verdict should spend one lore bid")

print("smoke_bid_lore: ok")
