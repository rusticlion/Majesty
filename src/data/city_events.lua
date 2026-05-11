-- city_events.lua
-- Default City Events and Signs/Portents tables.

local M = {}

M.CATEGORIES = {
    CURIOSITY = "curiosity",
    HAPPENING = "happening",
    RUMOR = "rumor",
    TRAVEL_EVENT = "travel_event",
    SIGNS_AND_PORTENTS = "signs_and_portents",
}

local function entry(value, category, title, summary, effects)
    return {
        value = value,
        category = category,
        title = title,
        summary = summary,
        effects = effects or {},
    }
end

M.DEFAULT_EVENTS = {
    [1] = entry(1, M.CATEGORIES.CURIOSITY, "Gross", "A bucket of night soil falls on a random adventurer."),
    [2] = entry(2, M.CATEGORIES.CURIOSITY, "Doggy", "A starving dog trails the guild and may follow if fed."),
    [3] = entry(3, M.CATEGORIES.CURIOSITY, "An Execution", "A public hanging shows the City's harsh justice."),
    [4] = entry(4, M.CATEGORIES.CURIOSITY, "Stylite", "A pillar-saint denounces the adventurer with the highest Wands."),
    [5] = entry(5, M.CATEGORIES.CURIOSITY, "Lick Lick Lick", "An old drunk sings while a bloated rat licks her ankles."),
    [6] = entry(6, M.CATEGORIES.HAPPENING, "Famine", "Food is scarce; rations are gated behind luxurious upkeep.", {
        rationUpkeepTier = "luxurious",
    }),
    [7] = entry(7, M.CATEGORIES.HAPPENING, "The Ecstasy of St. Naos", "The City shuts down for a massive holy party; only Carouse is available.", {
        allowedCityActions = { "carouse" },
    }),
    [8] = entry(8, M.CATEGORIES.HAPPENING, "The Coronation of Maiden Wisdom", "Charity lowers upkeep costs for this City Phase.", {
        upkeepCosts = {
            impoverished = 15,
            common = 25,
            luxurious = 50,
        },
    }),
    [9] = entry(9, M.CATEGORIES.HAPPENING, "The Feast of the Constellations", "Taverns close and Carouse is forbidden this City Phase.", {
        blockedCityActions = { "carouse" },
    }),
    [10] = entry(10, M.CATEGORIES.HAPPENING, "The King is Dead, Long Live the King", "A new ruler takes the throne; the GM updates the City's political frame."),
    [11] = entry(11, M.CATEGORIES.RUMOR, "The Sporehulk's Wife", "A dungeon lord's spouse lies in a barrow with transformative organs."),
    [12] = entry(12, M.CATEGORIES.RUMOR, "The Star's Daughter", "A fallen star seeks a marriage pact and offers a dangerous wish."),
    [13] = entry(13, M.CATEGORIES.RUMOR, "Medusa's Abortion", "A half-formed gorgon horror crawls through the Castle of Crossed Destinies."),
    [14] = entry(14, M.CATEGORIES.RUMOR, "The Strangler's Palm", "A hidden tavern in the Underworld offers safety for coin and a password."),
    [15] = entry(15, M.CATEGORIES.RUMOR, "The Tomb of the First Dead", "A primal grave holds a treasure that resists immortal nymph control."),
    [16] = entry(16, M.CATEGORIES.TRAVEL_EVENT, "A Theft", "A back-rank adventurer sees stolen gear turn up at a market stall."),
    [17] = entry(17, M.CATEGORIES.TRAVEL_EVENT, "A Challenge", "Bravos insult the adventurer with the highest Pentacles and seek a fight."),
    [18] = entry(18, M.CATEGORIES.TRAVEL_EVENT, "A Proposition", "Sex workers call down to the adventurer with the highest Wands."),
    [19] = entry(19, M.CATEGORIES.TRAVEL_EVENT, "An Inheritance", "The adventurer with the lowest Cups inherits a troublesome townhouse."),
    [20] = entry(20, M.CATEGORIES.TRAVEL_EVENT, "A Disaster: Fire", "After City Actions, the inn catches fire and may cost gear plus Stressed.", {
        timing = "after_city_actions",
        testSuit = "pentacles",
    }),
    [21] = entry(21, M.CATEGORIES.SIGNS_AND_PORTENTS, "Strange Days", "Look at the top minor discard and consult Signs and Portents."),
}

M.SIGNS_AND_PORTENTS = {
    [1] = entry(1, M.CATEGORIES.SIGNS_AND_PORTENTS, "Rip Van Winkle", "The guild returns to the City a century later."),
    [2] = entry(2, M.CATEGORIES.SIGNS_AND_PORTENTS, "The Blood-Red Star", "A red comet causes sleeplessness; begin the next Crawl Stressed.", {
        nextCrawlCondition = "stressed",
    }),
    [3] = entry(3, M.CATEGORIES.SIGNS_AND_PORTENTS, "Mists", "Emerald fog makes the City Phase take place in unnatural night."),
    [4] = entry(4, M.CATEGORIES.SIGNS_AND_PORTENTS, "The Ancient Quarter", "A vanished district returns and should be added to the City.", {
        drawAdditionalDistrict = true,
    }),
    [5] = entry(5, M.CATEGORIES.SIGNS_AND_PORTENTS, "The Blood Rain", "Blood rains over the City and fouls streets and cisterns."),
    [6] = entry(6, M.CATEGORIES.SIGNS_AND_PORTENTS, "Dreams", "Dreams wander between residents; each player tells another player a secret."),
    [7] = entry(7, M.CATEGORIES.SIGNS_AND_PORTENTS, "The Slime Catastrophe", "A slime brought to the City devours a random district.", {
        removeRandomDistrict = true,
    }),
    [8] = entry(8, M.CATEGORIES.SIGNS_AND_PORTENTS, "The Mushroom Forest", "Giant mushrooms block a random district's special City Action.", {
        blockRandomDistrictAction = true,
    }),
    [9] = entry(9, M.CATEGORIES.SIGNS_AND_PORTENTS, "The Thing in the Water", "A huge corpse from the Grey spreads a devastating song."),
    [10] = entry(10, M.CATEGORIES.SIGNS_AND_PORTENTS, "Dog Suicide", "All dogs in the City die in a single night."),
    [11] = entry(11, M.CATEGORIES.SIGNS_AND_PORTENTS, "The Black Miracle of the Statues", "Graven images speak blasphemy and iconoclasm rises."),
    [12] = entry(12, M.CATEGORIES.SIGNS_AND_PORTENTS, "The Honey Cult", "Black honey visions spread anxiety about the Nascent Horde."),
    [13] = entry(13, M.CATEGORIES.SIGNS_AND_PORTENTS, "The Child of Silence", "A silent giant infant hunts the guild through the City."),
    [14] = entry(14, M.CATEGORIES.SIGNS_AND_PORTENTS, "What Is Dead May Never Die", "The dead haunt the City; City Actions are blocked until the source is quelled.", {
        blockedCityActions = "all",
    }),
}

function M.getEvent(value, tableOverride)
    local tableRef = tableOverride or M.DEFAULT_EVENTS
    return tableRef[tonumber(value)]
end

function M.getSign(value, tableOverride)
    local tableRef = tableOverride or M.SIGNS_AND_PORTENTS
    return tableRef[tonumber(value)]
end

return M
