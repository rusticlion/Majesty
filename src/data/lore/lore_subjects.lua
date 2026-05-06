-- lore_subjects.lua
-- Authored Bid Lore subject catalog used by bid_lore_engine.lua.

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
        },
    },
    {
        id = "monster_brain_spider_queen",
        kind = "monster",
        name = "Glaura Glossolalia",
        shortDescription = "Brain spider queen with overwhelming psychic projection.",
        tags = { "monster_lore", "spider", "boss", "psychic", "ritual", "occult", "command" },
        enemyBlueprintIds = { "brain_spider_queen" },
        answers = {
            vulnerability = {
                summary = "Break her tempo and she loses control over the battlefield.",
                details = {
                    "She is strongest while issuing uninterrupted psychic pressure.",
                    "Stacked disruption from multiple fronts cuts her command quality.",
                    "She dislikes being forced to choose between offense and nest defense.",
                },
                implication = "Trade one clean strike for action denial whenever possible.",
                sourceRefs = { "blueprint:brain_spider_queen" },
            },
            behavior = {
                summary = "Glaura front-loads fear effects, then isolates a finisher target.",
                details = {
                    "She tests willpower first, not armor.",
                    "She pivots quickly once a target shows panic.",
                    "She uses minion spacing to protect her own initiative windows.",
                },
                implication = "Protect resolve economy and block isolation plays.",
                sourceRefs = { "blueprint:brain_spider_queen", "social_notes:glaura" },
            },
            taboo_or_trigger = {
                summary = "Threats to the crown or nest relics trigger reckless retaliation.",
                details = {
                    "Insulting her claim to the tomb provokes overextension.",
                    "Damage near core nest structures spikes aggression.",
                    "She reacts hard to rivals invoking old astronomer names.",
                },
                implication = "Use provocation intentionally and prepare punish windows.",
                sourceRefs = { "room:tripartite_statue", "room:glaura_nest" },
            },
            identity_or_origin = {
                summary = "She is a dominant broodmind shaped by tomb-era ritual residue.",
                details = {
                    "Her speech patterns mirror old ceremonial language.",
                    "She treats the tomb as both nest and throne.",
                    "Her power links to relic symbolism more than brute force.",
                },
                implication = "Scene objects can matter as much as damage output.",
                sourceRefs = { "blueprint:brain_spider_queen", "tomb_history" },
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
        roomIds = { "117_guardian_shrine" },
        answers = {
            identity_or_origin = {
                summary = "The shrine honors astronomer dead who watched for the Comet of Woe.",
                details = {
                    "Tablet inscriptions are memorial and warning texts.",
                    "Offerings are interpreted as signs of intent, not payment.",
                    "Names spoken correctly calm the guardian stance.",
                },
                implication = "Use respectful address and historical references before banter.",
                sourceRefs = { "room:guardian_shrine", "feature:inscribed_tablets" },
            },
            social_preference = {
                summary = "Respectful ritual language and offerings improve reception.",
                details = {
                    "Mockery of the dead rapidly shifts disposition toward anger.",
                    "Reading epitaphs aloud can build trust.",
                    "Desecration cues trigger immediate confrontation.",
                },
                implication = "Lead with deference, then negotiate from trust.",
                sourceRefs = { "socialEncounter:guardian_shrine", "feature:ancient_altar" },
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
}

return M
