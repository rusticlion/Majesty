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

local CATEGORY_ALIASES = {
    curiosity = M.CATEGORIES.CURIOSITY,
    curiosities = M.CATEGORIES.CURIOSITY,
    happening = M.CATEGORIES.HAPPENING,
    happenings = M.CATEGORIES.HAPPENING,
    rumor = M.CATEGORIES.RUMOR,
    rumour = M.CATEGORIES.RUMOR,
    rumors = M.CATEGORIES.RUMOR,
    rumours = M.CATEGORIES.RUMOR,
    travel = M.CATEGORIES.TRAVEL_EVENT,
    travel_event = M.CATEGORIES.TRAVEL_EVENT,
    signs = M.CATEGORIES.SIGNS_AND_PORTENTS,
    sign = M.CATEGORIES.SIGNS_AND_PORTENTS,
    signs_and_portents = M.CATEGORIES.SIGNS_AND_PORTENTS,
    portents = M.CATEGORIES.SIGNS_AND_PORTENTS,
}

local function cloneValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, entryValue in pairs(value) do
        copy[key] = cloneValue(entryValue)
    end
    return copy
end

local function normalizeCategory(category)
    if type(category) ~= "string" then
        return nil
    end
    local key = category:lower():gsub("^%s+", ""):gsub("%s+$", "")
    key = key:gsub("[%s%-]+", "_")
    return CATEGORY_ALIASES[key] or key
end

local function entryValue(rawEntry, key)
    if type(rawEntry) == "table" then
        return tonumber(rawEntry.value or rawEntry.cardValue or rawEntry.card_value or rawEntry.index or rawEntry.key or key)
    end
    return tonumber(key)
end

function M.categoryForValue(value)
    value = tonumber(value)
    if not value then
        return nil
    elseif value >= 1 and value <= 5 then
        return M.CATEGORIES.CURIOSITY
    elseif value >= 6 and value <= 10 then
        return M.CATEGORIES.HAPPENING
    elseif value >= 11 and value <= 15 then
        return M.CATEGORIES.RUMOR
    elseif value >= 16 and value <= 20 then
        return M.CATEGORIES.TRAVEL_EVENT
    elseif value == 21 then
        return M.CATEGORIES.SIGNS_AND_PORTENTS
    end
    return nil
end

function M.normalizeEventEntry(value, rawEntry, opts)
    opts = opts or {}
    local numericValue = tonumber(value)
    local record

    if type(rawEntry) == "table" then
        record = cloneValue(rawEntry)
        numericValue = tonumber(record.value or record.cardValue or record.card_value or numericValue)
    elseif rawEntry ~= nil then
        record = {
            title = tostring(rawEntry),
            summary = tostring(rawEntry),
        }
    else
        return nil
    end

    record.value = numericValue or record.value or value
    record.category = normalizeCategory(record.category or record.eventCategory or record.event_category or
        record.type or record.kind) or normalizeCategory(opts.defaultCategory) or M.categoryForValue(record.value)
    record.title = record.title or record.name or record.label or ("City Event " .. tostring(record.value or value))
    record.summary = record.summary or record.description or record.text or record.prompt or record.rumor or record.title
    if type(record.effects) ~= "table" then
        record.effects = type(record.effect) == "table" and record.effect or {}
    end
    record.authorNotes = record.authorNotes or record.author_notes or record.gmNotes or record.gm_notes

    local source = opts.source or opts.tableSource or opts.authorSource
    if source and not record.tableSource then
        record.tableSource = source
    end

    return record
end

function M.normalizeEventTable(tableRef, opts)
    opts = opts or {}
    local meta = {
        tableName = opts.tableName or opts.name or "city_events",
        source = opts.source or opts.tableSource or opts.authorSource,
        missing = {},
        invalid = {},
        count = 0,
        requireComplete = opts.requireComplete == true,
    }
    if type(tableRef) ~= "table" then
        meta.invalidTable = true
        meta.complete = false
        return tableRef, meta
    end

    local minValue = math.floor(tonumber(opts.minValue or 1) or 1)
    local maxValue = math.floor(tonumber(opts.maxValue or 21) or 21)
    local seen = {}

    for value = minValue, maxValue do
        local rawEntry = tableRef[value]
        if rawEntry == nil then
            rawEntry = tableRef[tostring(value)]
        end
        if rawEntry ~= nil then
            local record = M.normalizeEventEntry(value, rawEntry, opts)
            if record then
                tableRef[value] = record
                if tableRef[tostring(value)] ~= nil then
                    tableRef[tostring(value)] = record
                end
                if not seen[value] then
                    seen[value] = true
                    meta.count = meta.count + 1
                end
            else
                meta.invalid[#meta.invalid + 1] = value
            end
        end
    end

    for key, rawEntry in pairs(tableRef) do
        local value = entryValue(rawEntry, key)
        if value and value >= minValue and value <= maxValue then
            local record = seen[value] and tableRef[value] or M.normalizeEventEntry(value, rawEntry, opts)
            if record then
                tableRef[value] = record
                if key ~= value then
                    tableRef[key] = record
                end
                if not seen[value] then
                    seen[value] = true
                    meta.count = meta.count + 1
                end
            end
        elseif type(key) ~= "number" or key < minValue or key > maxValue then
            meta.invalid[#meta.invalid + 1] = key
        end
    end

    for value = minValue, maxValue do
        if not seen[value] then
            meta.missing[#meta.missing + 1] = value
        end
    end
    meta.complete = #meta.missing == 0

    return tableRef, meta
end

M.DEFAULT_EVENTS = {
    [1] = entry(1, M.CATEGORIES.CURIOSITY, "Gross", "A bucket of night soil falls on a random adventurer.", {
        randomAdventurer = {
            id = "night_soil",
            type = "night_soil",
            source = "city_event_gross",
            recordField = "cityEventCuriosities",
        },
    }),
    [2] = entry(2, M.CATEGORIES.CURIOSITY, "Doggy", "A starving dog trails the guild and may follow if fed.", {
        animalCompanionOpportunity = {
            id = "doggy",
            templateId = "hound",
            source = "city_event_doggy",
            recordField = "cityEventAnimalCompanions",
            feedRequired = true,
            acceptsRations = true,
            feedFor = { "hound", "dog" },
            defaultName = "Starving Dog",
        },
    }),
    [3] = entry(3, M.CATEGORIES.CURIOSITY, "An Execution", "A public hanging shows the City's harsh justice."),
    [4] = entry(4, M.CATEGORIES.CURIOSITY, "Stylite", "A pillar-saint denounces the adventurer with the highest Wands.", {
        targetedAdventurer = {
            id = "stylite_denunciation",
            type = "public_denunciation",
            source = "city_event_stylite",
            recordField = "cityEventCuriosities",
            target = "highest_suit",
            suit = "wands",
        },
    }),
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
    [10] = entry(10, M.CATEGORIES.HAPPENING, "The King is Dead, Long Live the King", "A new ruler takes the throne; the GM updates the City's political frame.", {
        citySuccession = {
            id = "king_is_dead",
            source = "city_event_king_is_dead",
            recordField = "citySuccessions",
        },
    }),
    [11] = entry(11, M.CATEGORIES.RUMOR, "The Sporehulk's Wife", "A dungeon lord's spouse lies in a barrow with transformative organs."),
    [12] = entry(12, M.CATEGORIES.RUMOR, "The Star's Daughter", "A fallen star seeks a marriage pact and offers a dangerous wish."),
    [13] = entry(13, M.CATEGORIES.RUMOR, "Medusa's Abortion", "A half-formed gorgon horror crawls through the Castle of Crossed Destinies."),
    [14] = entry(14, M.CATEGORIES.RUMOR, "The Strangler's Palm", "A hidden tavern in the Underworld offers safety for coin and a password."),
    [15] = entry(15, M.CATEGORIES.RUMOR, "The Tomb of the First Dead", "A primal grave holds a treasure that resists immortal nymph control."),
    [16] = entry(16, M.CATEGORIES.TRAVEL_EVENT, "A Theft", "A back-rank adventurer sees stolen gear turn up at a market stall.", {
        travelEvent = {
            target = "back_rank",
            consequence = "stolen_gear_spotted",
        },
    }),
    [17] = entry(17, M.CATEGORIES.TRAVEL_EVENT, "A Challenge", "Bravos insult the adventurer with the highest Pentacles and seek a fight.", {
        travelEvent = {
            target = "highest_suit",
            suit = "pentacles",
            consequence = "bravos_challenge",
        },
    }),
    [18] = entry(18, M.CATEGORIES.TRAVEL_EVENT, "A Proposition", "Sex workers call down to the adventurer with the highest Wands.", {
        travelEvent = {
            target = "highest_suit",
            suit = "wands",
            consequence = "discounted_proposition",
        },
    }),
    [19] = entry(19, M.CATEGORIES.TRAVEL_EVENT, "An Inheritance", "The adventurer with the lowest Cups inherits a troublesome townhouse.", {
        travelEvent = {
            target = "lowest_suit",
            suit = "cups",
            consequence = "grey_river_townhouse",
            property = {
                id = "grey_river_townhouse",
                name = "Townhouse by the Grey River",
                butler = "Aethelred",
                status = "boon_with_intrigue",
            },
        },
    }),
    [20] = entry(20, M.CATEGORIES.TRAVEL_EVENT, "A Disaster: Fire", "After City Actions, the inn catches fire and may cost gear plus Stressed.", {
        timing = "after_city_actions",
        testSuit = "pentacles",
    }),
    [21] = entry(21, M.CATEGORIES.SIGNS_AND_PORTENTS, "Strange Days", "Look at the top minor discard and consult Signs and Portents."),
}

M.SIGNS_AND_PORTENTS = {
    [1] = entry(1, M.CATEGORIES.SIGNS_AND_PORTENTS, "Rip Van Winkle", "The guild returns to the City a century later.", {
        cityOmen = {
            id = "rip_van_winkle",
            kind = "time_skip",
            years = 100,
        },
    }),
    [2] = entry(2, M.CATEGORIES.SIGNS_AND_PORTENTS, "The Blood-Red Star", "A red comet causes sleeplessness; begin the next Crawl Stressed.", {
        nextCrawlCondition = "stressed",
    }),
    [3] = entry(3, M.CATEGORIES.SIGNS_AND_PORTENTS, "Mists", "Emerald fog makes the City Phase take place in unnatural night.", {
        cityOmen = {
            id = "mists",
            kind = "environment",
            flag = "unnaturalNight",
        },
    }),
    [4] = entry(4, M.CATEGORIES.SIGNS_AND_PORTENTS, "The Ancient Quarter", "A vanished district returns and should be added to the City.", {
        drawAdditionalDistrict = true,
    }),
    [5] = entry(5, M.CATEGORIES.SIGNS_AND_PORTENTS, "The Blood Rain", "Blood rains over the City and fouls streets and cisterns.", {
        cityOmen = {
            id = "blood_rain",
            kind = "pollution",
            flag = "bloodRain",
        },
    }),
    [6] = entry(6, M.CATEGORIES.SIGNS_AND_PORTENTS, "Dreams", "Dreams wander between residents; each player tells another player a secret.", {
        cityOmen = {
            id = "wandering_dreams",
            kind = "social_secret",
            requiresPlayerSecrets = true,
        },
    }),
    [7] = entry(7, M.CATEGORIES.SIGNS_AND_PORTENTS, "The Slime Catastrophe", "A slime brought to the City devours a random district.", {
        removeRandomDistrict = true,
    }),
    [8] = entry(8, M.CATEGORIES.SIGNS_AND_PORTENTS, "The Mushroom Forest", "Giant mushrooms block a random district's special City Action.", {
        blockRandomDistrictAction = true,
    }),
    [9] = entry(9, M.CATEGORIES.SIGNS_AND_PORTENTS, "The Thing in the Water", "A huge corpse from the Grey spreads a devastating song.", {
        cityOmen = {
            id = "thing_in_the_water",
            kind = "named_gm_character_loss",
            flag = "greyEnnuiSong",
        },
    }),
    [10] = entry(10, M.CATEGORIES.SIGNS_AND_PORTENTS, "Dog Suicide", "All dogs in the City die in a single night.", {
        cityOmen = {
            id = "dog_suicide",
            kind = "animal_catastrophe",
            flag = "cityDogsDead",
        },
        animalCompanionCatastrophe = {
            id = "dog_suicide",
            type = "animal_catastrophe",
            source = "signs_dog_suicide",
            targetSpecies = { "hound", "dog" },
            condition = "dead",
            recordField = "cityEventAnimalCompanionCasualties",
        },
    }),
    [11] = entry(11, M.CATEGORIES.SIGNS_AND_PORTENTS, "The Black Miracle of the Statues", "Graven images speak blasphemy and iconoclasm rises.", {
        cityOmen = {
            id = "black_miracle_of_the_statues",
            kind = "religious_fervor",
            flag = "iconoclasm",
        },
    }),
    [12] = entry(12, M.CATEGORIES.SIGNS_AND_PORTENTS, "The Honey Cult", "Black honey visions spread anxiety about the Nascent Horde.", {
        cityOmen = {
            id = "honey_cult",
            kind = "cult_anxiety",
            flag = "nascentHordeAnxiety",
        },
    }),
    [13] = entry(13, M.CATEGORIES.SIGNS_AND_PORTENTS, "The Child of Silence", "A silent giant infant hunts the guild through the City.", {
        cityOmen = {
            id = "child_of_silence",
            kind = "guild_hunt",
            flag = "childOfSilenceHuntsGuild",
        },
    }),
    [14] = entry(14, M.CATEGORIES.SIGNS_AND_PORTENTS, "What Is Dead May Never Die", "The dead haunt the City; City Actions are blocked until the source is quelled.", {
        cityOmen = {
            id = "what_is_dead_may_never_die",
            kind = "undead_plague",
            flag = "undeadHauntCity",
        },
        blockedCityActions = "all",
        undeadPlague = {
            id = "what_is_dead_may_never_die",
            source = "signs_what_is_dead_may_never_die",
            blocksCityActions = true,
            sourceRequired = true,
        },
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
