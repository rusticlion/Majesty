-- smoke_bid_lore.lua
-- Quick vertical-slice checks for Bid Lore engine + resolver plumbing.

package.path = "./?.lua;./src/?.lua;./src/?/init.lua;./src/?/?.lua;" .. package.path

local events = require('logic.events')
local bid_lore_engine = require('logic.bid_lore_engine')
local action_resolver = require('logic.action_resolver')
local crawl_screen = require('ui.screens.crawl_screen')

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

local function containsSubject(subjects, subjectId)
    for _, subject in ipairs(subjects or {}) do
        if subject.id == subjectId then
            return true
        end
    end
    return false
end

local function containsEffect(result, effectId)
    for _, effect in ipairs(result and result.effects or {}) do
        if effect == effectId then
            return true
        end
    end
    return false
end

local function containsValue(items, value)
    for _, item in ipairs(items or {}) do
        if item == value then
            return true
        end
    end
    return false
end

local available = engine:getAvailableSubjects({
    challengeController = {
        roomId = "105_hall_of_solemnity",
        npcs = {
            { blueprintId = "brain_spider", conditions = {} },
        },
    },
})
assertTrue(#available > 0, "Expected at least one available lore subject")

local guardianAvailable = engine:getAvailableSubjects({
    challengeController = {
        roomId = "118_chamber_of_vigilant",
        npcs = {},
    },
})
assertTrue(containsSubject(guardianAvailable, "location_guardian_shrine"),
    "Tomb Guardian social room should expose Guardian Shrine lore")

local guardianVerdict = engine:adjudicate({
    subjectId = "location_guardian_shrine",
    questionType = "social_preference",
    motif = "Bookish",
    focus = "social",
})
assertEqual(guardianVerdict.verdict, "accepted", "Bookish social-preference query should reveal guardian approach")

local verdict = engine:adjudicate({
    subjectId = "monster_brain_spider",
    questionType = "vulnerability",
    motif = "Veteran Soldier",
    focus = "tactics",
})
assertEqual(verdict.verdict, "accepted", "Veteran Soldier vulnerability query should be accepted")

local hunterActor = {
    id = "pc_monster_hunter_lore",
    name = "Monster Hunter Lore",
    motifs = {},
    talents = {
        monster_hunter = {
            foe = "Beast",
            specialization = "brain spider",
            specializationTags = { "brain_spider" },
        },
    },
}
local hunterMotifs = engine:getActorMotifs(hunterActor)
assertTrue(containsValue(hunterMotifs, "Beast Hunter"),
    "Monster Hunter should add its chosen [Foe] Hunter motif to Bid Lore")
local hasHunterMotif, hunterMotif = engine:actorHasAppropriateMotif(hunterActor,
    engine:getSubject("monster_brain_spider"), engine:getQuestionType("behavior"))
assertTrue(hasHunterMotif, "Hunter motif should satisfy monster-related Bid Lore scoring")
assertEqual(hunterMotif, "Beast Hunter", "Bid Lore should report the generated Hunter motif")
hunterActor.talents.monster_hunter.wounded = true
assertTrue(not containsValue(engine:getActorMotifs(hunterActor), "Beast Hunter"),
    "wounded Monster Hunter should not provide its Hunter motif")

local bus = events.createEventBus()
local requestCount = 0
local bidLoreRequests = {}
local verdicts = {}
local socialDiscoveries = {}
bus:on(events.EVENTS.REQUEST_BID_LORE, function(data)
    requestCount = requestCount + 1
    bidLoreRequests[#bidLoreRequests + 1] = data
end)
bus:on(events.EVENTS.BID_LORE_VERDICT, function(data)
    verdicts[#verdicts + 1] = data
end)
bus:on("social_discovery", function(data)
    socialDiscoveries[#socialDiscoveries + 1] = data
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
assertEqual(requestCount, 1, "Bid Lore request event should be emitted")

local finalized = resolver:resolveBidLoreOutcome(action, verdict)
assertEqual(finalized.success, true, "Accepted lore verdict should be successful")
assertEqual(actor.loreBids, 3, "Accepted lore verdict should spend one lore bid")

local rejected = resolver:resolveBidLoreOutcome(action, {
    verdict = "rejected_unknown_with_motif",
    reason = "This motif would not know that.",
})
assertEqual(rejected.success, false, "Rejected lore verdict should fail the action")
assertEqual(actor.loreBids, 3, "Rejected lore verdict should not spend a lore bid")

local rephrase = resolver:resolveBidLoreOutcome(action, {
    verdict = "rephrase_needed",
    reason = "The question is too broad.",
})
assertEqual(rephrase.success, false, "Rephrase lore verdict should fail the action")
assertEqual(actor.loreBids, 3, "Rephrase lore verdict should not spend a lore bid")

actor.loreBids = 0
local blocked = resolver:resolve(action)
assertEqual(blocked.success, false, "Bid Lore with no lore bids should be blocked")
assertEqual(blocked.description, "No lore bids remaining", "No-bid block should explain the rule")
assertTrue(not blocked.pendingBidLore, "Blocked Bid Lore should not enter async state")
assertEqual(requestCount, 1, "Blocked Bid Lore should not emit a request")

local loremaster = {
    id = "pc_loremaster",
    name = "Loremaster",
    loreBids = 0,
    motifs = { "Bookish" },
    resolve = { current = 2, max = 4 },
    talents = {
        loremaster = { wounded = false },
    },
    conditions = {},
}
local loremasterAction = {
    actor = loremaster,
    card = { name = "Two of Cups", suit = 3, value = 2 },
    type = "bid_lore",
    spendResolveForLore = true,
    challengeController = {
        isActive = function()
            return true
        end,
        roomId = "118_chamber_of_vigilant",
        npcs = {},
    },
}
local loremasterPending = resolver:resolve(loremasterAction)
assertTrue(loremasterPending.pendingBidLore == true,
    "Loremaster should be able to open Bid Lore with Resolve and no lore bids")
local loremasterFinal = resolver:resolveBidLoreOutcome(loremasterAction, guardianVerdict)
assertTrue(loremasterFinal.success, "Accepted Loremaster lore should succeed")
assertEqual(loremaster.loreBids, 0, "Loremaster Resolve lore should not spend ordinary lore bids")
assertEqual(loremaster.resolve.current, 1, "Loremaster Resolve lore should spend one Resolve")
assertTrue(containsEffect(loremasterFinal, "loremaster_resolve_spent"),
    "Loremaster Resolve lore should report the talent payment")

local falseLoremaster = {
    id = "pc_false_loremaster",
    name = "False Loremaster",
    loreBids = 0,
    motifs = { "Bookish" },
    resolve = { current = 1, max = 4 },
    talents = {},
    conditions = {},
}
local falseLoremasterBlocked = resolver:resolve({
    actor = falseLoremaster,
    card = { name = "Three of Cups", suit = 3, value = 3 },
    type = "bid_lore",
    spendResolveForLore = true,
    challengeController = {
        isActive = function()
            return true
        end,
        roomId = "118_chamber_of_vigilant",
        npcs = {},
    },
})
assertEqual(falseLoremasterBlocked.success, false,
    "Resolve-for-lore should be blocked without Loremaster")
assertTrue(falseLoremasterBlocked.description:find("Loremaster") ~= nil,
    "missing Loremaster should explain Resolve-for-lore block")

local requestCountBeforeDirectCrawl = requestCount

local crawlActor = {
    id = "pc_crawl_lore",
    name = "Crawl Loredelver",
    loreBids = 2,
    motifs = { "Bookish" },
    conditions = {},
}

local crawlLore = resolver:resolveCrawlBidLore({
    actor = crawlActor,
    roomId = "118_chamber_of_vigilant",
    subjectId = "location_guardian_shrine",
    questionType = "social_preference",
    motif = "Bookish",
    focus = "social",
})
assertTrue(crawlLore.success, "Crawl Bid Lore should answer available room lore")
assertTrue(crawlLore.crawlBidLore, "Crawl Bid Lore should mark non-challenge context")
assertEqual(crawlLore.cardCost, false, "Crawl Bid Lore should not cost a Challenge card")
assertEqual(crawlActor.loreBids, 1, "Accepted Crawl Bid Lore should spend one lore bid")
assertTrue(crawlLore.description:find("Respectful") ~= nil,
    "Crawl Bid Lore should return the authored Guardian social answer")

local unsupportedQuestion = resolver:resolveCrawlBidLore({
    actor = crawlActor,
    roomId = "118_chamber_of_vigilant",
    subjectId = "location_guardian_shrine",
    questionType = "alchemy_effect",
    motif = "Bookish",
})
assertEqual(unsupportedQuestion.success, false, "Unsupported crawl lore question should ask for a rephrase")
assertEqual(crawlActor.loreBids, 1, "Rephrased Crawl Bid Lore should not spend a lore bid")

local unavailableSubject = resolver:resolveCrawlBidLore({
    actor = crawlActor,
    roomId = "118_chamber_of_vigilant",
    subjectId = "monster_brain_spider",
    questionType = "vulnerability",
    motif = "Veteran Soldier",
})
assertEqual(unavailableSubject.success, false, "Unavailable room subject should be rejected")
assertEqual(unavailableSubject.bidLore.verdict, "rejected_subject_unavailable",
    "Unavailable crawl subject should use the subject-unavailable verdict")
assertEqual(crawlActor.loreBids, 1, "Rejected Crawl Bid Lore should not spend a lore bid")

crawlActor.loreBids = 0
local crawlBlocked = resolver:resolveCrawlBidLore({
    actor = crawlActor,
    roomId = "118_chamber_of_vigilant",
    subjectId = "location_guardian_shrine",
    questionType = "social_preference",
    motif = "Bookish",
})
assertEqual(crawlBlocked.success, false, "Crawl Bid Lore should block with no lore bids")
assertEqual(crawlBlocked.description, "No lore bids remaining",
    "No-bid Crawl Bid Lore should explain the rule")
assertEqual(requestCount, requestCountBeforeDirectCrawl,
    "Direct Crawl Bid Lore should not emit a modal request")
assertTrue(#verdicts >= 4, "Bid Lore verdict events should be emitted for finalized lore results")

loremaster.loreBids = 0
loremaster.resolve.current = 1
local crawlResolveLore = resolver:resolveCrawlBidLore({
    actor = loremaster,
    roomId = "118_chamber_of_vigilant",
    subjectId = "location_guardian_shrine",
    questionType = "social_preference",
    motif = "Bookish",
    focus = "social",
    spendResolveForLore = true,
})
assertTrue(crawlResolveLore.success, "Crawl Loremaster lore should spend Resolve when requested")
assertEqual(loremaster.loreBids, 0, "Crawl Loremaster lore should not spend ordinary lore bids")
assertEqual(loremaster.resolve.current, 0, "Crawl Loremaster lore should spend one Resolve")

local gnome = {
    id = "pc_gnome_lore",
    name = "Gnome Lorekeeper",
    loreBids = 1,
    motifs = { "Bookish" },
    talents = {
        weird_wise_ancient = { wounded = false },
    },
    conditions = {},
}
local firstGnomeLore = resolver:resolveCrawlBidLore({
    actor = gnome,
    roomId = "118_chamber_of_vigilant",
    subjectId = "location_guardian_shrine",
    questionType = "identity_or_origin",
    motif = "Bookish",
    focus = "history",
})
assertTrue(firstGnomeLore.success, "Gnome initial Bid Lore should be accepted")
assertEqual(gnome.loreBids, 0, "Initial accepted lore should spend the gnome's last lore bid")

local gnomeFollowUp = resolver:resolveBidLoreFollowUp({
    actor = gnome,
    previousResult = firstGnomeLore,
    roomId = "118_chamber_of_vigilant",
    subjectId = "location_guardian_shrine",
    questionType = "social_preference",
    motif = "Bookish",
    focus = "social",
})
assertTrue(gnomeFollowUp.success, "Weird, Wise, Ancient should allow an accepted free follow-up")
assertEqual(gnome.loreBids, 0, "Free lore follow-up should not spend another lore bid")
assertTrue(containsEffect(gnomeFollowUp, "weird_wise_ancient_follow_up"),
    "Free lore follow-up should report the Weird, Wise, Ancient talent")

local blockedFollowUp = resolver:resolveBidLoreFollowUp({
    actor = crawlActor,
    previousResult = firstGnomeLore,
    roomId = "118_chamber_of_vigilant",
    subjectId = "location_guardian_shrine",
    questionType = "social_preference",
    motif = "Bookish",
    focus = "social",
})
assertEqual(blockedFollowUp.success, false, "Free lore follow-up should require Weird, Wise, Ancient")
assertTrue(blockedFollowUp.description:find("Weird") ~= nil,
    "Blocked free follow-up should explain the missing talent")

local noAnswerFollowUp = resolver:resolveBidLoreFollowUp({
    actor = gnome,
    previousResult = {
        success = false,
        bidLore = { verdict = "rephrase_needed" },
    },
    roomId = "118_chamber_of_vigilant",
    subjectId = "location_guardian_shrine",
    questionType = "social_preference",
    motif = "Bookish",
    focus = "social",
})
assertEqual(noAnswerFollowUp.success, false, "Free lore follow-up should require a prior accepted answer")
assertTrue(noAnswerFollowUp.description:find("previous accepted") ~= nil,
    "Blocked free follow-up should explain the missing accepted answer")

local uncanny = {
    id = "pc_uncanny_knowledge",
    name = "Uncanny Knower",
    loreBids = 1,
    motifs = { "Quick Fingers" },
    talents = {
        uncanny_knowledge = { wounded = false },
    },
    conditions = {},
}
local uncannyLore = resolver:resolveCrawlBidLore({
    actor = uncanny,
    party = { uncanny },
    roomId = "118_chamber_of_vigilant",
    subjectId = "location_guardian_shrine",
    questionType = "identity_or_origin",
})
assertTrue(uncannyLore.success, "Uncanny Knowledge should allow lore when nobody has an appropriate motif")
assertEqual(uncanny.loreBids, 0, "Accepted Uncanny Knowledge lore should spend one lore bid")
assertTrue(containsEffect(uncannyLore, "uncanny_knowledge_lore"),
    "Uncanny Knowledge lore should report the talent fallback")

local uncannyBlockedActor = {
    id = "pc_uncanny_blocked",
    name = "Uncanny Blocked",
    loreBids = 1,
    motifs = { "Quick Fingers" },
    talents = {
        uncanny_knowledge = { wounded = false },
    },
    conditions = {},
}
local scholar = {
    id = "pc_scholar",
    name = "Scholar",
    loreBids = 1,
    motifs = { "Bookish" },
    talents = {},
    conditions = {},
}
local uncannyBlocked = resolver:resolveCrawlBidLore({
    actor = uncannyBlockedActor,
    party = { uncannyBlockedActor, scholar },
    roomId = "118_chamber_of_vigilant",
    subjectId = "location_guardian_shrine",
    questionType = "identity_or_origin",
})
assertEqual(uncannyBlocked.success, false,
    "Uncanny Knowledge should not override another party member's appropriate motif")
assertEqual(uncannyBlockedActor.loreBids, 1,
    "Blocked Uncanny Knowledge should not spend a lore bid")

local conArtist = {
    id = "pc_con_artist",
    name = "Con Artist",
    loreBids = 2,
    motifs = { "Silver Tongue" },
    talents = {
        con_artist = { wounded = false },
    },
    conditions = {},
}
local socialTarget = {
    id = "npc_guardian",
    name = "Tomb Guardian Spirit",
    social = {
        likes = { "respect", "offerings" },
        dislikes = { "grave_robbing", "lies" },
    },
}
local discoveryCountBeforeConArtist = #socialDiscoveries
local conLike = resolver:resolveConArtistLore({
    actor = conArtist,
    target = socialTarget,
    preference = "likes",
    talked = true,
})
assertTrue(conLike.success, "Con Artist should reveal a like after talking or observing")
assertEqual(conLike.conArtistPreference.value, "respect", "Con Artist should reveal the selected like")
assertEqual(conArtist.loreBids, 1, "Accepted Con Artist lore should spend one lore bid")
assertTrue(containsEffect(conLike, "con_artist_likes_revealed"),
    "Con Artist like reveal should report the social preference effect")
assertTrue(socialTarget.wants ~= nil, "Con Artist like reveal should expose wants for the inspect panel")
assertEqual(#socialDiscoveries, discoveryCountBeforeConArtist + 1,
    "Con Artist should emit a social discovery")

local conDislike = resolver:resolveConArtistLore({
    actor = conArtist,
    target = socialTarget,
    preference = "dislikes",
    observed = true,
})
assertTrue(conDislike.success, "Con Artist should reveal a dislike after observation")
assertEqual(conDislike.conArtistPreference.value, "grave_robbing",
    "Con Artist should reveal the selected dislike")
assertEqual(conArtist.loreBids, 0, "Second accepted Con Artist lore should spend another lore bid")
assertTrue(socialTarget.hates ~= nil, "Con Artist dislike reveal should expose hates for the inspect panel")

local unobservedConArtist = {
    id = "pc_con_artist_unobserved",
    name = "Unobserved Con Artist",
    loreBids = 1,
    talents = {
        con_artist = { wounded = false },
    },
    conditions = {},
}
local unobservedBlocked = resolver:resolveConArtistLore({
    actor = unobservedConArtist,
    target = socialTarget,
    preference = "likes",
})
assertEqual(unobservedBlocked.success, false,
    "Con Artist should require observing or talking before revealing social preferences")
assertEqual(unobservedConArtist.loreBids, 1,
    "Blocked Con Artist observation gate should not spend a lore bid")

local falseConArtistBlocked = resolver:resolveConArtistLore({
    actor = crawlActor,
    target = socialTarget,
    preference = "likes",
    talked = true,
})
assertEqual(falseConArtistBlocked.success, false, "Con Artist lore should require the Con Artist talent")

local foretellActor = {
    id = "pc_foretell",
    name = "Foretelling Dark Elf",
    loreBids = 2,
    talents = {
        foretell = { wounded = false },
    },
    conditions = {},
}
local foretellNo = resolver:resolveForetellLore({
    actor = foretellActor,
    ifAction = "open the black door",
    willOutcome = "an attack from the guardian",
    prediction = false,
})
assertTrue(foretellNo.success, "Foretell should accept a structured yes/no hunch")
assertEqual(foretellNo.foretell.answer, "No", "Foretell should preserve the no answer")
assertEqual(foretellNo.foretell.expires, "momentary", "Foretell hunch should be momentary")
assertEqual(foretellActor.loreBids, 1, "Accepted Foretell lore should spend one lore bid")
assertTrue(containsEffect(foretellNo, "foretell_lore"), "Foretell should report its lore effect")
assertTrue(containsEffect(foretellNo, "foretell_momentary"), "Foretell should report momentary duration")
assertTrue(containsEffect(foretellNo, "foretell_no"), "Foretell should report the no hunch")
assertEqual(foretellActor.lastForetell.answer, "No", "Foretell should store the last hunch on the actor")

local foretellYes = resolver:resolveForetellLore({
    actor = foretellActor,
    ifAction = "touch the moonlit altar",
    willOutcome = "a hidden door",
    answer = "yes",
})
assertTrue(foretellYes.success, "Foretell should normalize string yes answers")
assertEqual(foretellYes.foretell.prediction, true, "Foretell yes should store a true prediction")
assertEqual(foretellActor.loreBids, 0, "Second accepted Foretell lore should spend another lore bid")
assertTrue(containsEffect(foretellYes, "foretell_yes"), "Foretell should report the yes hunch")

local noInfoForetellActor = {
    id = "pc_foretell_no_info",
    name = "No Info Foretelling Dark Elf",
    loreBids = 1,
    talents = {
        foretell = { wounded = false },
    },
    conditions = {},
}
local foretellNoInfo = resolver:resolveForetellLore({
    actor = noInfoForetellActor,
    ifAction = "whisper to the mirror",
    willOutcome = "a reply",
})
assertEqual(foretellNoInfo.success, false, "Foretell should rephrase when no new hunch is available")
assertEqual(noInfoForetellActor.loreBids, 1, "No-new-info Foretell should not spend a lore bid")
assertTrue(containsEffect(foretellNoInfo, "foretell_no_new_information"),
    "Foretell should report no-new-info outcomes")

local falseForetellBlocked = resolver:resolveForetellLore({
    actor = crawlActor,
    ifAction = "open the black door",
    willOutcome = "an attack from the guardian",
    prediction = true,
})
assertEqual(falseForetellBlocked.success, false, "Foretell lore should require the Foretell talent")

local malformedForetell = resolver:resolveForetellLore({
    actor = noInfoForetellActor,
    ifAction = "open the black door",
    prediction = true,
})
assertEqual(malformedForetell.success, false, "Foretell should require an if/will question shape")
assertEqual(noInfoForetellActor.loreBids, 1, "Malformed Foretell should not spend a lore bid")

crawlActor.loreBids = 2
local narrative = {
    rawText = "",
    setText = function(self, text)
        self.rawText = text
    end,
}
local crawlScreen = crawl_screen.createCrawlScreen({
    eventBus = bus,
    gameState = {
        guild = { crawlActor },
        activePCIndex = 1,
        actionResolver = resolver,
        bidLoreEngine = engine,
    },
})
crawlScreen.guild = { crawlActor }
crawlScreen.currentRoomId = "118_chamber_of_vigilant"
crawlScreen.narrativeView = narrative

local focusOption = crawlScreen:buildCrawlBidLoreFocusOption({
    roomId = "118_chamber_of_vigilant",
    poiId = "inscribed_tablets",
})
assertEqual(focusOption.action, "bid_lore", "Crawl focus menu should expose Bid Lore in lore-keyed rooms")
assertEqual(focusOption.disabled, nil, "Crawl Bid Lore focus option should be enabled while bids remain")

local requestBeforeCrawlUi = requestCount
local opened = crawlScreen:openCrawlBidLore(crawlActor, { id = "inscribed_tablets" }, {
    roomId = "118_chamber_of_vigilant",
})
assertTrue(opened, "Crawl screen should open the Bid Lore modal request")
assertEqual(requestCount, requestBeforeCrawlUi + 1, "Crawl Bid Lore UI should emit one modal request")

local modalRequest = bidLoreRequests[#bidLoreRequests]
assertEqual(modalRequest.action.context, "crawl", "Crawl Bid Lore modal request should be marked as crawl context")
assertTrue(containsSubject(modalRequest.availableSubjects, "location_guardian_shrine"),
    "Crawl Bid Lore modal request should provide room-available subjects")

local bidsBeforeCrawlUi = crawlActor.loreBids
crawlScreen:handleCrawlBidLoreComplete({
    action = modalRequest.action,
    result = {
        selection = {
            subjectId = "location_guardian_shrine",
            questionType = "social_preference",
            motif = "Bookish",
            focus = "social",
        },
    },
})
assertEqual(crawlActor.loreBids, bidsBeforeCrawlUi - 1,
    "Crawl Bid Lore UI completion should spend one accepted lore bid")
assertTrue(crawlScreen.pendingCrawlBidLore == nil, "Crawl Bid Lore UI completion should clear pending state")
assertTrue(narrative.rawText:find("BID LORE") ~= nil, "Crawl Bid Lore UI should write a narrative block")
assertTrue(narrative.rawText:find("Respectful") ~= nil,
    "Crawl Bid Lore UI should surface the authored room answer")

crawlActor.loreBids = 0
local disabledOption = crawlScreen:buildCrawlBidLoreFocusOption({
    roomId = "118_chamber_of_vigilant",
    poiId = "inscribed_tablets",
})
assertEqual(disabledOption.disabled, true, "Crawl focus menu should disable Bid Lore with no bids")

local blockedRequestCount = requestCount
local blockedOpen = crawlScreen:openCrawlBidLore(crawlActor, { id = "inscribed_tablets" }, {
    roomId = "118_chamber_of_vigilant",
})
assertEqual(blockedOpen, false, "Crawl screen should not open Bid Lore with no bids")
assertEqual(requestCount, blockedRequestCount, "Blocked crawl Bid Lore UI should not emit a modal request")

local loreResolveActor = {
    id = "pc_crawl_loremaster",
    name = "Crawl Loremaster",
    loreBids = 0,
    motifs = { "Bookish" },
    resolve = { current = 1, max = 4 },
    talents = {
        loremaster = { wounded = false },
    },
    conditions = {},
}
local loreResolveNarrative = {
    rawText = "",
    setText = function(self, text)
        self.rawText = text
    end,
}
local loreResolveScreen = crawl_screen.createCrawlScreen({
    eventBus = bus,
    gameState = {
        guild = { loreResolveActor },
        activePCIndex = 1,
        actionResolver = resolver,
        bidLoreEngine = engine,
    },
})
loreResolveScreen.guild = { loreResolveActor }
loreResolveScreen.currentRoomId = "118_chamber_of_vigilant"
loreResolveScreen.narrativeView = loreResolveNarrative

local resolveOption = loreResolveScreen:buildCrawlBidLoreFocusOption({
    roomId = "118_chamber_of_vigilant",
    poiId = "inscribed_tablets",
})
assertEqual(resolveOption.disabled, nil,
    "Crawl focus menu should allow Loremaster Bid Lore with Resolve and no lore bids")
assertEqual(resolveOption.spendResolveForLore, true,
    "Crawl focus menu should mark Loremaster Resolve payment")

local resolveRequestCount = requestCount
local resolveOpened = loreResolveScreen:openCrawlBidLore(loreResolveActor, { id = "inscribed_tablets" }, {
    roomId = "118_chamber_of_vigilant",
})
assertTrue(resolveOpened, "Crawl Loremaster should open Bid Lore with Resolve")
assertEqual(requestCount, resolveRequestCount + 1,
    "Crawl Loremaster Bid Lore should emit one modal request")

local resolveModalRequest = bidLoreRequests[#bidLoreRequests]
assertEqual(resolveModalRequest.action.spendResolveForLore, true,
    "Crawl Loremaster modal request should carry Resolve payment")
loreResolveScreen:handleCrawlBidLoreComplete({
    action = resolveModalRequest.action,
    result = {
        selection = {
            subjectId = "location_guardian_shrine",
            questionType = "social_preference",
            motif = "Bookish",
            focus = "social",
        },
    },
})
assertEqual(loreResolveActor.resolve.current, 0,
    "Crawl Loremaster UI completion should spend one Resolve")
assertEqual(loreResolveActor.loreBids, 0,
    "Crawl Loremaster UI completion should not spend lore bids")

print("smoke_bid_lore: ok")
