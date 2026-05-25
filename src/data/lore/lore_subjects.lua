-- lore_subjects.lua
-- Authored Bid Lore subject catalog used by bid_lore_engine.lua.

local item_templates = require('data.item_templates')
local question_types = require('data.lore.question_types')

local M = {}

M.SUBJECTS = {
    {
        id = "monster_brain_spider",
        kind = "monster",
        name = "Brain Spider",
        shortDescription = "Psychic ambush predator that uses webs and fear.",
        tags = { "monster_lore", "spider", "psychic", "predator", "web", "occult", "hazard" },
        enemyBlueprintIds = { "brain_spider" },
        answers = {
            vulnerability = {
                summary = "Flame and bright light disrupt a brain spider's ambush rhythm.",
                details = {
                    "Open flame weakens web control and forces repositioning.",
                    "Loud coordinated pressure can break its concentration chain.",
                    "It hates prolonged stand-up fights against shielded fronts.",
                },
                implication = "Force it into visible lanes and deny time for setup.",
                sourceRefs = { "tomb_of_golden_ghosts:web_clusters", "blueprint:brain_spider" },
            },
            behavior = {
                summary = "It opens with pressure and tests the weakest flank first.",
                details = {
                    "It probes isolated targets before committing.",
                    "It prefers to strike after movement bottlenecks.",
                    "When hurt, it falls back behind webs and lets panic spread.",
                },
                implication = "Keep formation tight and rotate wounded allies inward.",
                sourceRefs = { "blueprint:brain_spider", "room:hall_of_solemnity" },
            },
            taboo_or_trigger = {
                summary = "Fire in its nest lanes provokes immediate aggression.",
                details = {
                    "Burning webs near an egg clutch forces a hard response.",
                    "Cornering one without a retreat lane causes reckless lunges.",
                    "Sudden light shifts can make it misread initiative tempo.",
                },
                implication = "Bait overcommit with controlled fire, then counter.",
                sourceRefs = { "room:glaura_nest", "web_hazard_notes" },
            },
            identity_or_origin = {
                summary = "Brain spiders are carrion-psychic predators adapted to ancient tombs.",
                details = {
                    "They nest near old inscriptions and corpse-rich chambers.",
                    "Their webs are structural and sensory, not only adhesive.",
                    "They keep lesser undead or ghosts contained as moving alarm bells.",
                },
                implication = "Expect layered traps where history and webbing overlap.",
                sourceRefs = { "tomb_history", "blueprint:brain_spider" },
            },
            environmental_risk = {
                summary = "Web chokes and sightline breaks are the immediate danger.",
                details = {
                    "Narrow passages can become one-action kill funnels.",
                    "Webbed floors slow repositioning under pressure.",
                    "Ceiling anchor points hide drop angles.",
                },
                implication = "Clear one clean route before splitting zones.",
                sourceRefs = { "room:hall_of_solemnity", "room:trapped_hallway" },
            },
            alchemy_effect = {
                summary = "Brain spider reagents have distinct potion, bomb, and oil preparations.",
                details = {
                    "Ask about one preparation at a time: potion, bomb, or oil.",
                    "A hermetically bottled brain spider reagent can be brewed into any of those three forms.",
                },
                implication = "Each accepted alchemy lore bid reveals one brew form, not the whole recipe set.",
                sourceRefs = { "appendix_b:brain_spider_alchemy", "item:brain_spider_bomb" },
                forms = {
                    potion = {
                        summary = "Brain spider potion makes your speech psionically understandable.",
                        details = {
                            "When you speak, the meaning of your words is psychically broadcast.",
                            "Anyone who hears you can understand you, even without a shared language.",
                        },
                        implication = "Use the potion when language barriers would block negotiation or coordination.",
                        sourceRefs = { "appendix_b:brain_spider_alchemy", "item:brain_spider_potion" },
                        outputTemplateId = "brain_spider_potion",
                    },
                    bomb = {
                        summary = "Brain spider bomb bursts into silver webbing.",
                        details = {
                            "The bomb covers one victim in silver webbing and Roots them.",
                            "The silver web also affects incorporeal creatures.",
                        },
                        implication = "Use the bomb as a Cups-based Use Item attack, then exploit the Rooted target.",
                        sourceRefs = { "appendix_b:brain_spider_alchemy", "item:brain_spider_bomb" },
                        outputTemplateId = "brain_spider_bomb",
                    },
                    oil = {
                        summary = "Brain spider oil is a watch-long binding glue.",
                        details = {
                            "The spinneret chemicals form powerful glue.",
                            "For a watch, the glue sticks two things inseparably together.",
                        },
                        implication = "Use the oil on objects or terrain when binding is more valuable than damage.",
                        sourceRefs = { "appendix_b:brain_spider_alchemy", "item:brain_spider_oil" },
                        outputTemplateId = "brain_spider_oil",
                    },
                },
            },
        },
    },
    {
        id = "monster_brain_spider_queen",
        kind = "monster",
        name = "Glaura Glossolalia",
        shortDescription = "Sorcerous brain spider obsessed with the star-child.",
        tags = { "monster_lore", "spider", "brain_spider", "sorcery", "illusion", "web", "star_child" },
        enemyBlueprintIds = { "brain_spider_queen" },
        answers = {
            vulnerability = {
                summary = "Bludgeoning and smashing weapons are wasted against her soft brain-spider body.",
                details = {
                    "Brain spiders are Squishy and ignore hammers, maces, and similar smashing weapons.",
                    "She has the same 3/3 Health/Defense profile as Kodi.",
                    "She still needs greater doom cards to turn Illusion into a stronger spell.",
                },
                implication = "Use blades, missiles, fire, or spell pressure instead of blunt weapons.",
                sourceRefs = { "blueprint:brain_spider_queen" },
            },
            behavior = {
                summary = "Glaura fights like a brain spider sorcerer, not a brute boss.",
                details = {
                    "She can cast Illusion with her seven-faceted prism.",
                    "She can Web targets instead of dealing Attack damage.",
                    "She can spend Tactics to turn a standard Challenge Action into an interrupt.",
                },
                implication = "Expect false images, webbed Rooting, and interrupt movement when she has doom cards.",
                sourceRefs = { "blueprint:brain_spider_queen", "social_notes:glaura" },
            },
            taboo_or_trigger = {
                summary = "Mythric priests and threats to the star-child obsession cut deepest.",
                details = {
                    "She dislikes Mythric priests and is staunchly atheist.",
                    "She wants to put the star-child into one of her eggs.",
                    "She will fight to the death to protect the star-child if encountered in the laboratory.",
                },
                implication = "Religious provocation and star-child leverage are social risks, not guaranteed advantages.",
                sourceRefs = { "room:116_glaura_nest", "room:114_laboratory" },
            },
            identity_or_origin = {
                summary = "She is Kodi's sorcerously inclined mate and believes godhood is within reach.",
                details = {
                    "She feels she does most of the work in the relationship.",
                    "She likes crude jokes and ribald songs.",
                    "If a face card is on the minor discard pile, she may appear in Kodi's nest.",
                },
                implication = "Her room placement and alliance with Kodi depend on the Tomb's encounter state.",
                sourceRefs = { "blueprint:brain_spider_queen", "tomb_history" },
            },
        },
    },
    {
        id = "monster_brain_spider_kodi",
        kind = "monster",
        name = "Kodi Dove-devourer",
        shortDescription = "Possessive brain spider illusionist who puppets the mummies.",
        tags = { "monster_lore", "spider", "brain_spider", "sorcery", "illusion", "web", "puppet_mummy" },
        enemyBlueprintIds = { "brain_spider_kodi" },
        answers = {
            vulnerability = {
                summary = "Kodi shares the normal brain spider vulnerabilities and weapon immunities.",
                details = {
                    "Bludgeoning and smashing weapons do not hurt brain spiders.",
                    "He has Health/Defense 3/3 despite being described as large.",
                    "His Illusion spell still depends on his prism component and greater doom cards.",
                },
                implication = "Do not waste hammer or mace attacks; break his setup with non-blunt pressure.",
                sourceRefs = { "blueprint:brain_spider_kodi" },
            },
            behavior = {
                summary = "Kodi hides behind illusions and makes the guild waste actions.",
                details = {
                    "In room 109, he controls puppet-mummies from behind an illusory wall.",
                    "Second sight can reveal him through the illusion.",
                    "Missile fire from outside the puppet-mummy room forces him to reveal himself and flee.",
                },
                implication = "Second sight or cautious ranged pressure can break the puppet-mummy trick.",
                sourceRefs = { "blueprint:brain_spider_kodi", "room:109_guard_room" },
            },
            taboo_or_trigger = {
                summary = "Kodi is greedy, possessive, and prickly about status.",
                details = {
                    "He believes whatever he holds in his webs belongs to him.",
                    "He dislikes goblins and being looked down on, especially by nobility.",
                    "He likes goats, drugs, and banjo music.",
                },
                implication = "Mocking his competence or status is likely to sour Parley fast.",
                sourceRefs = { "social_notes:kodi" },
            },
            identity_or_origin = {
                summary = "Kodi is Glaura's ambitious but not especially competent mate.",
                details = {
                    "He is always in room 117 unless already encountered.",
                    "He can also appear in room 116 when a face card is on the minor discard pile.",
                    "If Glaura is threatened in room 116, he can rush to her aid.",
                },
                implication = "Track whether the named brain spiders have already appeared before restaging them.",
                sourceRefs = { "blueprint:brain_spider_kodi", "room:117_kodi_nest" },
            },
        },
    },
    {
        id = "hazard_silvery_webs",
        kind = "hazard",
        name = "Silvery Webs",
        shortDescription = "Unnaturally strong web lattices used as barriers and trip-lines.",
        tags = { "hazard", "web", "trap", "flammable", "adhesive", "movement" },
        roomIds = { "105_hall_of_solemnity", "110_trapped_hallway" },
        answers = {
            vulnerability = {
                summary = "Heat and cutting motion open reliable lanes through web clusters.",
                details = {
                    "Open flame weakens web tension quickly.",
                    "A narrow cut corridor is safer than broad tearing.",
                    "Repeated blunt force tends to entangle weapons.",
                },
                implication = "Create one intentional breach, then rotate through it.",
                sourceRefs = { "room:hall_of_solemnity", "room:trapped_hallway" },
            },
            environmental_risk = {
                summary = "Webs convert movement mistakes into positional collapse.",
                details = {
                    "Hidden trip-lines can trigger larger hazards.",
                    "Sticky mats expose stragglers to focused attacks.",
                    "Blocking routes can force bad zone commitments.",
                },
                implication = "Scout before committing dashes through webbed spaces.",
                sourceRefs = { "trap:web_trigger", "room:hall_of_solemnity" },
            },
            alchemy_effect = {
                summary = "Lamp oil and torch flame create brief high-visibility windows.",
                details = {
                    "Flash burns reveal anchor points and safe angles.",
                    "Smoke can conceal retreat after a breach.",
                    "Residue remains sticky even after partial burn-off.",
                },
                implication = "Time breach-and-move in one action sequence.",
                sourceRefs = { "item:torch", "hazard:web_chemistry_notes" },
            },
        },
    },
    {
        id = "location_guardian_shrine",
        kind = "location",
        name = "Guardian Shrine",
        shortDescription = "Chamber where tomb memory, offerings, and guardian intent overlap.",
        tags = { "history", "location", "spirit", "ritual", "social", "astronomy" },
        roomIds = { "118_chamber_of_vigilant" },
        answers = {
            identity_or_origin = {
                summary = "The shrine honors astronomer dead who watched for the Comet of Woe.",
                details = {
                    "Tablet inscriptions are memorial and warning texts.",
                    "Offerings are interpreted as signs of intent, not payment.",
                    "Names spoken correctly calm the guardian stance.",
                },
                implication = "Use respectful address and historical references before banter.",
                sourceRefs = { "room:chamber_of_vigilant", "feature:inscribed_tablets" },
            },
            social_preference = {
                summary = "Respectful ritual language and offerings improve reception.",
                details = {
                    "Mockery of the dead rapidly shifts disposition toward anger.",
                    "Reading epitaphs aloud can build trust.",
                    "Desecration cues trigger immediate confrontation.",
                },
                implication = "Lead with deference, then negotiate from trust.",
                sourceRefs = { "socialEncounter:chamber_of_vigilant", "feature:ancient_altar" },
            },
            taboo_or_trigger = {
                summary = "The guardian reacts hardest to grave-robbing behavior.",
                details = {
                    "Snatching offerings in view is treated as defilement.",
                    "Breaking memorial tablets escalates instantly.",
                    "Calling the dead liars or fools is a direct provocation.",
                },
                implication = "Keep loot actions separate from parley moments.",
                sourceRefs = { "feature:ancient_altar", "feature:inscribed_tablets" },
            },
        },
    },
    {
        id = "faction_golden_ghosts",
        kind = "faction",
        name = "Golden Ghosts",
        shortDescription = "Restless tomb spirits fixated on protecting sacred relics.",
        tags = { "spirit", "faction", "social", "history", "fear", "grief" },
        roomIds = { "107_looted_tomb" },
        answers = {
            behavior = {
                summary = "They communicate through urgent gesture and repeated warnings.",
                details = {
                    "They cluster around intrusion points and relic routes.",
                    "They are more frantic than hostile unless provoked.",
                    "They repeat references to the crown and theft.",
                },
                implication = "Interpret their signals before assuming direct aggression.",
                sourceRefs = { "room:looted_tomb", "feature:golden_ghosts" },
            },
            social_preference = {
                summary = "They respond to empathy and protection vows, not intimidation.",
                details = {
                    "Calm listening stabilizes interactions.",
                    "Disrespecting the dead quickly shuts communication down.",
                    "Promises to guard relics can earn guidance.",
                },
                implication = "Use supportive social play, then ask precise questions.",
                sourceRefs = { "feature:golden_ghosts", "tomb_history" },
            },
            identity_or_origin = {
                summary = "They are remnants of mourners and keepers bound to unfinished warning duty.",
                details = {
                    "Their attention centers on relic displacement.",
                    "Their weeping appears linked to failed tomb oaths.",
                    "They linger where sarcophagus order has been broken.",
                },
                implication = "Restoring order may unlock safer traversal routes.",
                sourceRefs = { "room:looted_tomb", "feature:sarcophagi" },
            },
        },
    },
    {
        id = "location_tripartite_statue",
        kind = "location",
        name = "Tripartite Statue",
        shortDescription = "Three-faced crowned statue tied to succession and omen lore.",
        tags = { "location", "ritual", "symbolism", "crown", "history", "occult" },
        roomIds = { "108_tripartite_statue" },
        answers = {
            identity_or_origin = {
                summary = "The three faces symbolize maiden, mother, and crone succession rites.",
                details = {
                    "The shared crown marks continuity of authority across life stages.",
                    "Corpse placement implies failed claim or interrupted rite.",
                    "Adjacent inscriptions frame the crown as stewardship, not ownership.",
                },
                implication = "Crown-related choices likely have social and supernatural fallout.",
                sourceRefs = { "room:tripartite_statue", "tomb_symbol_ledger" },
            },
            taboo_or_trigger = {
                summary = "Removing the crown without rite language is treated as sacrilege.",
                details = {
                    "The chamber appears keyed to ceremonial sequence.",
                    "Violent tampering around the statue triggers omen motifs.",
                    "Improper claims provoke both spirits and nest defenders.",
                },
                implication = "Investigate protocol before touching relic pieces.",
                sourceRefs = { "room:tripartite_statue", "guardian_shrine_notes" },
            },
            social_preference = {
                summary = "Entities tied to the statue prefer ritual respect and lawful claim framing.",
                details = {
                    "Oath language softens confrontational disposition shifts.",
                    "Confession of intent is received better than deception.",
                    "Invoking shared guardianship beats personal entitlement claims.",
                },
                implication = "Use lawful language in crown negotiations.",
                sourceRefs = { "social_notes:guardian", "symbolic_protocols" },
            },
        },
    },
    {
        id = "tomb_royal_records",
        kind = "lore",
        name = "Tomb Royal Records",
        shortDescription = "Fragile scroll records of the sealed royal family's rule.",
        tags = { "history", "royal", "records", "taxes", "gifts", "tomb", "book" },
        roomIds = { "102_scriptorium" },
        answers = {
            identity_or_origin = {
                summary = "The scrolls are administrative records from the royal family sealed in the tomb.",
                details = {
                    "Carefully opened scrolls enumerate taxes and gifts collected during the family's rule.",
                    "Their value comes from age and provenance more than secret strategy.",
                    "They are written for bureaucratic memory, not adventurer navigation.",
                },
                implication = "Handle them as delicate historical artifacts rather than ordinary loot notes.",
                sourceRefs = { "room:102_scriptorium", "item:fragile_royal_scroll" },
            },
            environmental_risk = {
                summary = "The records can be destroyed by casual handling.",
                details = {
                    "Opening them without care or in the wrong environment makes them crack apart.",
                    "Transport to City antiquarians requires special protection.",
                    "The sealed chronicle case nearby is a different, more dangerous scroll.",
                },
                implication = "Decide whether to preserve, read, or sell them before anyone starts unrolling parchment.",
                sourceRefs = { "feature:bookshelves", "feature:sealed_scroll_case" },
            },
        },
    },
    {
        id = "underworld_alchemical_reagents",
        kind = "lore",
        name = "Underworld Alchemical Reagents",
        shortDescription = "Francis Stewbrew's partial field notes on this level's alchemical harvests.",
        tags = { "alchemy", "reagents", "underworld", "book", "appendix_b" },
        roomIds = { "104_corpse" },
        answers = {
            alchemy_effect = {
                summary = "The treatise partially identifies which local monsters preserve useful reagents.",
                details = {
                    "Brain spiders are explicitly useful to alchemists if their remains are bottled quickly.",
                    "Oozes, fungi, and other Appendix B-style creatures need hermetic preservation.",
                    "The book is incomplete and does not replace a full Alchemy procedure.",
                },
                implication = "Carry hermetic bottles and spend a watch before harvested reagents go stale.",
                sourceRefs = { "item:alchemical_treatise_francis_stewbrew", "room:104_corpse" },
            },
            identity_or_origin = {
                summary = "Francis Stewbrew wrote these notes as practical reagent fieldwork.",
                details = {
                    "The book catalogs monster remains by dungeon level.",
                    "Its margins focus on handling, bottling, and likely brew forms.",
                    "Several entries are missing or damaged.",
                },
                implication = "Treat it as a partial index, not a guaranteed complete bestiary.",
                sourceRefs = { "item:alchemical_treatise_francis_stewbrew" },
            },
        },
    },
}

local APPENDIX_B_ALCHEMY_SOURCES = {
    { id = "cockatrice", name = "Cockatrice" },
    { id = "devil", name = "Devil" },
    { id = "face_rat", name = "Face Rat" },
    { id = "fungoid", name = "Fungoid" },
    { id = "griffin", name = "Griffin" },
    { id = "harpy", name = "Harpy" },
    { id = "imp", name = "Imp" },
    { id = "jinn", name = "Jinn" },
    { id = "kelpie", name = "Kelpie" },
    { id = "mimic", name = "Mimic" },
    { id = "nymph", name = "Nymph" },
    { id = "ogre", name = "Ogre" },
    { id = "questing_beast", name = "Questing Beast" },
    { id = "slime", name = "Slime" },
    { id = "titan", name = "Titan" },
    { id = "ungoat", name = "Ungoat" },
    { id = "vampire", name = "Vampire" },
    { id = "winter_wolf", name = "Winter Wolf" },
}

local FORM_LABELS = {
    potion = "Potion",
    bomb = "Bomb",
    oil = "Oil",
}

local function appendAppendixBAlchemySubject(source)
    local reagent = item_templates.getTemplate(source.id .. "_reagent")
    local outputs = reagent and reagent.properties and reagent.properties.brewOutputs
    if type(outputs) ~= "table" then
        return
    end

    local forms = {}
    for _, form in ipairs({ "potion", "bomb", "oil" }) do
        local outputTemplateId = outputs[form]
        if outputTemplateId then
            local output = item_templates.getTemplate(outputTemplateId)
            local props = output and output.properties or {}
            local useEffect = props.useEffect or {}
            forms[form] = {
                summary = (output and output.name or (source.name .. " " .. FORM_LABELS[form])) ..
                    " is the " .. source.name .. " " .. form .. " preparation.",
                details = {
                    useEffect.successMessage or "The effect follows the authored Appendix B alchemical substance.",
                    "This answer reveals only the " .. form .. " form for this reagent.",
                },
                implication = "Brew a hermetically bottled " .. source.name ..
                    " reagent into " .. FORM_LABELS[form]:lower() .. " when that effect is needed.",
                sourceRefs = { "appendix_b:" .. source.id .. "_alchemy", "item:" .. outputTemplateId },
                outputTemplateId = outputTemplateId,
            }
        end
    end

    M.SUBJECTS[#M.SUBJECTS + 1] = {
        id = "appendix_b_alchemy_" .. source.id,
        kind = "monster",
        name = source.name .. " Alchemy",
        shortDescription = "Appendix B alchemical preparations from " .. source.name .. " reagents.",
        tags = { "alchemy", "reagent", "reagents", "appendix_b", source.id },
        enemyBlueprintIds = { source.id },
        answers = {
            alchemy_effect = {
                summary = source.name .. " reagents have authored Appendix B alchemical preparations.",
                details = {
                    "Ask about one preparation at a time: potion, bomb, or oil.",
                    "Unavailable forms are not invented when Appendix B gives no such substance.",
                },
                implication = "Each accepted alchemy lore bid reveals one brew form for this reagent.",
                sourceRefs = { "appendix_b:" .. source.id .. "_alchemy", "item:" .. source.id .. "_reagent" },
                forms = forms,
            },
        },
    }
end

for _, source in ipairs(APPENDIX_B_ALCHEMY_SOURCES) do
    appendAppendixBAlchemySubject(source)
end

local VALID_SUBJECT_KINDS = {
    faction = true,
    hazard = true,
    item = true,
    location = true,
    lore = true,
    monster = true,
    npc = true,
}

local VALID_ALCHEMY_FORMS = {
    bomb = true,
    oil = true,
    potion = true,
}

local function isBlank(value)
    return value == nil or tostring(value):gsub("^%s+", ""):gsub("%s+$", "") == ""
end

local function addIssue(list, code, message, field, context)
    local issue = {
        code = code,
        message = message,
        field = field,
    }
    if context then
        for key, value in pairs(context) do
            issue[key] = value
        end
    end
    list[#list + 1] = issue
end

local function mergeIssues(target, source)
    for _, issue in ipairs(source or {}) do
        target[#target + 1] = issue
    end
end

local function validateText(result, value, code, message, field, context)
    if isBlank(value) then
        addIssue(result.errors, code, message, field, context)
        return false
    end
    return true
end

local function validateStringList(result, value, opts)
    opts = opts or {}
    local field = opts.field
    local subjectId = opts.subjectId
    local questionType = opts.questionType
    local form = opts.form
    local missingCode = opts.missingCode
    local missingMessage = opts.missingMessage
    local blankCode = opts.blankCode
    local blankMessage = opts.blankMessage
    local duplicateCode = opts.duplicateCode
    local duplicateMessage = opts.duplicateMessage

    if type(value) ~= "table" or #value == 0 then
        addIssue(result.errors, missingCode, missingMessage, field, {
            subjectId = subjectId,
            questionType = questionType,
            form = form,
        })
        return false
    end

    local seen = {}
    local ok = true
    for index, entry in ipairs(value) do
        if isBlank(entry) then
            addIssue(result.errors, blankCode, blankMessage, field, {
                subjectId = subjectId,
                questionType = questionType,
                form = form,
                index = index,
            })
            ok = false
        else
            local key = tostring(entry)
            if duplicateCode and seen[key] then
                addIssue(result.warnings, duplicateCode, duplicateMessage .. tostring(entry) .. ".", field, {
                    subjectId = subjectId,
                    questionType = questionType,
                    form = form,
                    value = entry,
                })
            end
            seen[key] = true
        end
    end

    return ok
end

local function validateAnswerShape(result, answer, opts)
    opts = opts or {}
    local context = {
        subjectId = opts.subjectId,
        questionType = opts.questionType,
        form = opts.form,
    }

    if type(answer) ~= "table" then
        addIssue(result.errors, opts.missingCode or "answer_missing",
            opts.missingMessage or "Lore answer must be a table.", opts.field or "answers", context)
        return false
    end

    validateText(result, answer.summary, opts.summaryCode or "summary_missing",
        opts.summaryMessage or "Lore answer needs a concise summary.",
        opts.summaryField or "summary", context)
    validateStringList(result, answer.details, {
        field = opts.detailsField or "details",
        subjectId = opts.subjectId,
        questionType = opts.questionType,
        form = opts.form,
        missingCode = opts.detailsCode or "details_missing",
        missingMessage = opts.detailsMessage or "Lore answer needs at least one detail.",
        blankCode = opts.blankDetailCode or "detail_blank",
        blankMessage = opts.blankDetailMessage or "Lore answer has a blank detail.",
    })
    validateText(result, answer.implication, opts.implicationCode or "implication_missing",
        opts.implicationMessage or "Lore answer needs a practical implication.",
        opts.implicationField or "implication", context)
    validateStringList(result, answer.sourceRefs, {
        field = opts.sourceField or "sourceRefs",
        subjectId = opts.subjectId,
        questionType = opts.questionType,
        form = opts.form,
        missingCode = opts.sourceCode or "source_refs_missing",
        missingMessage = opts.sourceMessage or "Lore answer needs at least one source reference.",
        blankCode = opts.blankSourceCode or "source_ref_blank",
        blankMessage = opts.blankSourceMessage or "Lore answer has a blank source reference.",
        duplicateCode = "duplicate_source_ref",
        duplicateMessage = "Lore answer repeats source reference: ",
    })

    return true
end

local function reagentOutputsForSubject(subject)
    local outputs = {}
    local hasReagent = false
    for _, blueprintId in ipairs(subject and subject.enemyBlueprintIds or {}) do
        local reagent = item_templates.getTemplate(tostring(blueprintId) .. "_reagent")
        local brewOutputs = reagent and reagent.properties and reagent.properties.brewOutputs
        if type(brewOutputs) == "table" then
            hasReagent = true
            for form, templateId in pairs(brewOutputs) do
                outputs[form] = templateId
            end
        end
    end
    return outputs, hasReagent
end

local function validateAlchemyForms(result, subject, questionType, answer, opts)
    opts = opts or {}
    if answer.forms == nil then
        return 0
    end
    if questionType ~= "alchemy_effect" then
        addIssue(result.errors, "forms_on_non_alchemy_answer",
            "Only alchemy-effect answers should declare brew forms.", "forms", {
                subjectId = subject.id,
                questionType = questionType,
            })
    end
    if type(answer.forms) ~= "table" or next(answer.forms) == nil then
        addIssue(result.errors, "alchemy_forms_missing",
            "Alchemy answer declares forms but none are authored.", "forms", {
                subjectId = subject.id,
                questionType = questionType,
            })
        return 0
    end

    local formCount = 0
    local reagentOutputs, hasReagent = reagentOutputsForSubject(subject)
    for form, formAnswer in pairs(answer.forms) do
        formCount = formCount + 1
        local formId = tostring(form)
        if not VALID_ALCHEMY_FORMS[formId] then
            addIssue(result.errors, "invalid_alchemy_form",
                "Alchemy answer uses an unknown form: " .. formId .. ".", "forms", {
                    subjectId = subject.id,
                    questionType = questionType,
                    form = formId,
                })
        end

        validateAnswerShape(result, formAnswer, {
            subjectId = subject.id,
            questionType = questionType,
            form = formId,
            missingCode = "alchemy_form_missing",
            missingMessage = "Alchemy form answer must be a table.",
            summaryCode = "form_summary_missing",
            summaryMessage = "Alchemy form answer needs a summary.",
            detailsCode = "form_details_missing",
            detailsMessage = "Alchemy form answer needs at least one detail.",
            implicationCode = "form_implication_missing",
            implicationMessage = "Alchemy form answer needs a practical implication.",
            sourceCode = "form_source_refs_missing",
            sourceMessage = "Alchemy form answer needs at least one source reference.",
        })

        local outputTemplateId = type(formAnswer) == "table" and
            (formAnswer.outputTemplateId or formAnswer.templateId) or nil
        if isBlank(outputTemplateId) then
            addIssue(result.errors, "output_template_missing",
                "Alchemy form answer needs an outputTemplateId.", "outputTemplateId", {
                    subjectId = subject.id,
                    questionType = questionType,
                    form = formId,
                })
        elseif opts.checkItemTemplates ~= false and not item_templates.getTemplate(outputTemplateId) then
            addIssue(result.errors, "output_template_unknown",
                "Alchemy form references an unknown item template: " .. tostring(outputTemplateId) .. ".",
                "outputTemplateId", {
                    subjectId = subject.id,
                    questionType = questionType,
                    form = formId,
                    outputTemplateId = outputTemplateId,
                })
        elseif hasReagent and reagentOutputs[formId] and reagentOutputs[formId] ~= outputTemplateId then
            addIssue(result.warnings, "output_template_not_reagent_brew_output",
                "Alchemy form output does not match the registered reagent brew output.", "outputTemplateId", {
                    subjectId = subject.id,
                    questionType = questionType,
                    form = formId,
                    outputTemplateId = outputTemplateId,
                    expectedTemplateId = reagentOutputs[formId],
                })
        end
    end

    return formCount
end

function M.validateAnswer(answer, opts)
    opts = opts or {}
    local result = {
        ok = true,
        errors = {},
        warnings = {},
        answer = answer,
        subject = opts.subject,
        questionType = opts.questionType,
        alchemyFormCount = 0,
    }

    validateAnswerShape(result, answer, opts)
    if type(answer) == "table" and answer.forms ~= nil then
        result.alchemyFormCount = validateAlchemyForms(result, opts.subject or {}, opts.questionType, answer, opts)
    end

    result.ok = #result.errors == 0
    return result
end

function M.validateSubject(subject, opts)
    opts = opts or {}
    local result = {
        ok = true,
        errors = {},
        warnings = {},
        subject = subject,
        subjectId = type(subject) == "table" and subject.id or nil,
        answerCount = 0,
        alchemyFormCount = 0,
    }

    if type(subject) ~= "table" then
        addIssue(result.errors, "subject_missing", "Lore subject must be a table.", "subject")
        result.ok = false
        return result
    end

    validateText(result, subject.id, "subject_id_missing",
        "Lore subject needs a stable id.", "id", { subjectId = subject.id })
    validateText(result, subject.name, "subject_name_missing",
        "Lore subject needs a display name.", "name", { subjectId = subject.id })
    validateText(result, subject.shortDescription, "short_description_missing",
        "Lore subject needs a short player-facing description.", "shortDescription", { subjectId = subject.id })

    if isBlank(subject.kind) then
        addIssue(result.errors, "subject_kind_missing",
            "Lore subject needs a kind.", "kind", { subjectId = subject.id })
    elseif not VALID_SUBJECT_KINDS[tostring(subject.kind)] then
        addIssue(result.errors, "subject_kind_unknown",
            "Lore subject kind is not recognized: " .. tostring(subject.kind) .. ".",
            "kind", { subjectId = subject.id })
    end

    validateStringList(result, subject.tags, {
        field = "tags",
        subjectId = subject.id,
        missingCode = "tags_missing",
        missingMessage = "Lore subject needs scoring tags.",
        blankCode = "tag_blank",
        blankMessage = "Lore subject has a blank tag.",
        duplicateCode = "duplicate_tag",
        duplicateMessage = "Lore subject repeats tag: ",
    })

    local hasContext = subject.alwaysAvailable or
        (type(subject.roomIds) == "table" and #subject.roomIds > 0) or
        (type(subject.enemyBlueprintIds) == "table" and #subject.enemyBlueprintIds > 0) or
        (type(subject.itemTemplateIds) == "table" and #subject.itemTemplateIds > 0)
    if not hasContext then
        local message = "Lore subject has no context filter; it will only appear through fallback availability."
        if opts.requireContext then
            addIssue(result.errors, "context_missing", message, "roomIds", { subjectId = subject.id })
        else
            addIssue(result.warnings, "context_missing", message, "roomIds", { subjectId = subject.id })
        end
    end

    if subject.itemTemplateIds then
        for _, templateId in ipairs(subject.itemTemplateIds) do
            if opts.checkItemTemplates ~= false and not item_templates.getTemplate(templateId) then
                addIssue(result.errors, "item_template_unknown",
                    "Lore subject references an unknown item template: " .. tostring(templateId) .. ".",
                    "itemTemplateIds", {
                        subjectId = subject.id,
                        itemTemplateId = templateId,
                    })
            end
        end
    end

    if type(subject.answers) ~= "table" or next(subject.answers) == nil then
        addIssue(result.errors, "answers_missing",
            "Lore subject needs at least one authored answer.", "answers", { subjectId = subject.id })
    else
        for questionType, answer in pairs(subject.answers) do
            result.answerCount = result.answerCount + 1
            if not question_types.get(questionType) then
                addIssue(result.errors, "unknown_question_type",
                    "Lore answer uses an unknown question type: " .. tostring(questionType) .. ".",
                    "answers", {
                        subjectId = subject.id,
                        questionType = questionType,
                    })
            end
            local answerValidation = M.validateAnswer(answer, {
                subject = subject,
                subjectId = subject.id,
                questionType = questionType,
                checkItemTemplates = opts.checkItemTemplates,
            })
            result.alchemyFormCount = result.alchemyFormCount + answerValidation.alchemyFormCount
            mergeIssues(result.errors, answerValidation.errors)
            mergeIssues(result.warnings, answerValidation.warnings)
        end
    end

    result.ok = #result.errors == 0
    return result
end

function M.validateRegistry(opts)
    opts = opts or {}
    local subjects = opts.subjects or M.SUBJECTS
    local result = {
        ok = true,
        errors = {},
        warnings = {},
        subjects = {},
        subjectCount = 0,
        answerCount = 0,
        alchemyFormCount = 0,
    }

    if type(subjects) ~= "table" then
        addIssue(result.errors, "registry_missing",
            "Lore subject registry must be a table.", "subjects")
        result.ok = false
        return result
    end

    local seenIds = {}
    for index, subject in ipairs(subjects) do
        result.subjectCount = result.subjectCount + 1
        local validation = M.validateSubject(subject, opts)
        result.subjects[index] = validation
        result.answerCount = result.answerCount + validation.answerCount
        result.alchemyFormCount = result.alchemyFormCount + validation.alchemyFormCount
        mergeIssues(result.errors, validation.errors)
        mergeIssues(result.warnings, validation.warnings)

        local id = type(subject) == "table" and subject.id or nil
        if not isBlank(id) then
            if seenIds[id] then
                addIssue(result.errors, "duplicate_subject_id",
                    "Duplicate lore subject id: " .. tostring(id) .. ".", "id", {
                        subjectId = id,
                        firstIndex = seenIds[id],
                        index = index,
                    })
            end
            seenIds[id] = seenIds[id] or index
        end
    end

    result.ok = #result.errors == 0
    return result
end

local function hasIssueCode(issues, codeSet)
    for _, issue in ipairs(issues or {}) do
        if codeSet[issue.code] then
            return true
        end
    end
    return false
end

local function checklistItem(id, label, complete, detail)
    return {
        id = id,
        label = label,
        complete = complete == true,
        detail = detail,
    }
end

function M.createAuthoringChecklist(opts)
    opts = opts or {}
    local validation = M.validateRegistry(opts)
    local items = {}
    local hasSubjects = validation.subjectCount > 0
    local hasAnswers = validation.answerCount >= validation.subjectCount and
        not hasIssueCode(validation.errors, { answers_missing = true })
    local hasQuestionTypes = not hasIssueCode(validation.errors, {
        unknown_question_type = true,
        forms_on_non_alchemy_answer = true,
    })
    local hasAnswerDepth = not hasIssueCode(validation.errors, {
        summary_missing = true,
        details_missing = true,
        detail_blank = true,
        implication_missing = true,
        source_refs_missing = true,
        source_ref_blank = true,
        form_summary_missing = true,
        form_details_missing = true,
        form_implication_missing = true,
        form_source_refs_missing = true,
    })
    local hasAlchemyOutputs = not hasIssueCode(validation.errors, {
        invalid_alchemy_form = true,
        alchemy_forms_missing = true,
        alchemy_form_missing = true,
        output_template_missing = true,
        output_template_unknown = true,
    })
    local hasContext = not hasIssueCode(validation.errors, { context_missing = true })

    items[#items + 1] = checklistItem("subjects", "Author lore subjects", hasSubjects,
        tostring(validation.subjectCount or 0) .. " lore subject(s) registered.")
    items[#items + 1] = checklistItem("context", "Provide availability context", hasContext,
        hasContext and "Subjects have room, enemy, item, or always-available context." or
        "One or more subjects need availability context.")
    items[#items + 1] = checklistItem("answers", "Author at least one answer per subject", hasAnswers,
        tostring(validation.answerCount or 0) .. " answer(s) registered.")
    items[#items + 1] = checklistItem("question_types", "Use supported question types", hasQuestionTypes,
        hasQuestionTypes and "All answer keys map to Bid Lore question types." or
        "One or more answer keys need a supported question type.")
    items[#items + 1] = checklistItem("answer_depth", "Provide summaries, details, implications, and sources",
        hasAnswerDepth,
        hasAnswerDepth and "All answers have the required answer text." or
        "One or more answers need deeper authored text.")
    items[#items + 1] = checklistItem("alchemy_outputs", "Link alchemy forms to item templates", hasAlchemyOutputs,
        tostring(validation.alchemyFormCount or 0) .. " alchemy form answer(s) linked.")
    items[#items + 1] = checklistItem("validation", "Resolve authoring blockers", validation.ok,
        validation.ok and "No blocking lore authoring errors." or
        tostring(#validation.errors) .. " blocker(s) remain.")

    local complete = true
    for _, item in ipairs(items) do
        if not item.complete then
            complete = false
            break
        end
    end

    return {
        complete = complete,
        items = items,
        validation = validation,
        blockers = validation.errors,
        warnings = validation.warnings,
        counts = {
            subjects = validation.subjectCount,
            answers = validation.answerCount,
            alchemyForms = validation.alchemyFormCount,
        },
    }
end

return M
