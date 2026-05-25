-- action_sequencer.lua
-- Visual Action Sequencer for Majesty
-- Ticket S4.2: Converts logic events into visual timelines
--
-- IMPORTANT: Uses dt-based timers in update(), NOT love.timer.sleep()!
-- sleep() would freeze the entire application.
--
-- Sequence flow:
-- 1. Logic emits CHALLENGE_ACTION / CHALLENGE_RESOLUTION
-- 2. Sequencer queues visual steps: card_slap -> math_overlay -> damage_result
-- 3. Each step has a duration, when done -> next step
-- 4. When all steps done -> emit UI_SEQUENCE_COMPLETE

local events = require('logic.events')

local M = {}

local function resultHasEffect(result, effect)
    for _, value in ipairs(result and result.effects or {}) do
        if value == effect then
            return true
        end
    end
    return false
end

local function entityName(entity, fallback)
    return entity and (entity.name or entity.id) or fallback
end

local function traversalModeLabel(mode)
    local normalized = mode and tostring(mode):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("[%s%-]+", "_")
    local labels = {
        climb = "climb",
        climbing = "climb",
        vertical = "climb",
        vertical_terrain = "climb",
        sheer_surface = "sheer climb",
        ledge = "narrow ledge",
        narrow_ledge = "narrow ledge",
        tightrope = "tightrope",
    }
    return labels[normalized] or (mode and tostring(mode):gsub("_", " ")) or "traversal"
end

local function buildTraversalPopupData(action, result)
    if not result then
        return nil
    end

    local traversal = result.acrobatTraversal
    if not traversal and not (resultHasEffect(result, "traversal_test_passed") or
       resultHasEffect(result, "traversal_test_failed")) then
        return nil
    end

    local mode = (traversal and traversal.mode) or action.traversalMode or action.traversal or action.movementMode
    local label = traversalModeLabel(mode)
    local actor = action and action.actor
    local actorLabel = entityName(actor, "Mover")
    local title = "Traversal"
    local text = actorLabel .. " crosses the " .. label
    local passed = resultHasEffect(result, "traversal_test_passed")
    local failed = resultHasEffect(result, "traversal_test_failed")

    if resultHasEffect(result, "grappling_hook_traversal") then
        title = "Grappling Hook"
        text = actorLabel .. " secures the " .. label
    elseif resultHasEffect(result, "acrobat_traversal") then
        title = "Acrobat"
        text = actorLabel .. " crosses the " .. label .. " without a Test of Fate"
    elseif passed then
        title = "Traversal Test"
        text = actorLabel .. " passes the " .. label .. " Test of Fate"
    elseif failed then
        title = "Traversal Failed"
        text = actorLabel .. " fails the " .. label .. " Test of Fate"
    end

    return {
        title = title,
        text = text,
        actor = actor,
        mode = mode,
        traversalMode = mode,
        destinationZone = action and action.destinationZone,
        acrobatTraversal = traversal,
        noTestFate = traversal and traversal.noTestFate == true,
        testPassed = passed,
        testFailed = failed,
        gear = traversal and traversal.gear,
        grapplingHookTraversal = result.grapplingHookTraversal,
    }
end

local function commandLabel(commandName)
    local normalized = commandName and tostring(commandName):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("[%s%-]+", "_")
    local labels = {
        sic_em = "Sic 'Em",
        fetch = "Fetch",
        guard = "Guard",
        hunt = "Hunt",
        get_help = "Get Help",
        do_a_trick = "Do a Trick",
        heel = "Heel",
        stay = "Stay",
        track = "Track",
    }
    return labels[normalized] or (commandName and tostring(commandName):gsub("_", " ")) or "Command"
end

local function buildCommandPopupData(action, result)
    if not (result and result.success and result.commandName and result.companion) then
        return nil
    end

    local commandName = result.commandName
    local commandText = commandLabel(commandName)
    local companion = result.companion
    local companionName = entityName(companion, "Companion")
    local target = action and (action.commandTarget or action.target)
    local targetName = entityName(target, nil)
    local text = companionName .. " follows " .. commandText

    if resultHasEffect(result, "companion_attack") and targetName then
        text = companionName .. " attacks " .. targetName
    elseif resultHasEffect(result, "companion_fetch") then
        local item = result.fetchedItem or (action and action.item)
        text = companionName .. " fetches " .. (item and (item.name or item.id) or "an item")
    elseif resultHasEffect(result, "companion_guard") then
        local guarded = companion.guarding or target or (action and action.actor)
        text = companionName .. " guards " .. entityName(guarded, "the area")
    elseif resultHasEffect(result, "companion_hunt") then
        text = companionName .. " hunts " .. tostring(result.huntTarget or result.commandObjective or "the quarry")
    elseif resultHasEffect(result, "companion_get_help") then
        text = companionName .. " goes for help"
    elseif resultHasEffect(result, "companion_trick") then
        text = companionName .. " performs " .. tostring(result.trick or "a trick")
    elseif resultHasEffect(result, "companion_positioned") then
        text = companionName .. " obeys " .. commandText
    elseif resultHasEffect(result, "companion_track") then
        text = companionName .. " tracks " .. tostring(result.trackSubject or result.commandObjective or "the trail")
    end

    return {
        title = "Command",
        text = text,
        actor = action and action.actor,
        companion = companion,
        target = target,
        commandName = commandName,
        commandLabel = commandText,
        objective = result.commandObjective,
        item = result.fetchedItem or (action and action.item),
        damageDealt = result.damageDealt,
        pendingTestOfFate = result.pendingTestOfFate == true,
    }
end

local function aidActionLabel(actionType)
    local normalized = actionType and tostring(actionType):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("[%s%-]+", "_")
    local labels = {
        aid = "Aid Another",
        aid_another = "Aid Another",
        attack = "Attack",
        melee = "Melee Attack",
        missile = "Missile Attack",
        roughhouse = "Roughhouse",
        avoid = "Avoid",
        dash = "Dash",
        dodge = "Dodge",
        riposte = "Riposte",
        command = "Command",
        use_item = "Use Item",
        pull_item = "Pull Item",
        speak_incantation = "Speak Incantation",
        trivial_action = "Trivial Action",
    }
    return labels[normalized] or (actionType and tostring(actionType):gsub("_", " ")) or "next action"
end

local function buildCounselPopupData(detail)
    if not detail then
        return nil
    end

    local counselor = detail.counselor or detail.actor
    local target = detail.target
    local card = detail.card
    local actionType = detail.actionType
    local actionLabel = detail.actionName or aidActionLabel(actionType)
    local cardName = detail.cardName or (card and card.name) or "a card"
    local counselorName = entityName(counselor, "Counselor")
    local targetName = entityName(target, "an ally")
    local text = counselorName .. " gives " .. tostring(cardName) .. " to " .. targetName ..
        " for " .. tostring(actionLabel)

    if detail.interrupt then
        text = text .. " as an interrupt"
    end

    return {
        title = "Counsel",
        text = text,
        counselor = counselor,
        actor = counselor,
        target = target,
        card = card,
        cardName = cardName,
        cardSuit = detail.cardSuit or (card and card.suit),
        cardValue = detail.cardValue or (card and card.value),
        cardIndex = detail.cardIndex,
        actionType = actionType,
        actionName = actionLabel,
        actionSuit = detail.actionSuit,
        round = detail.round,
        interrupt = detail.interrupt == true,
        resolveSpent = detail.resolveSpent == true,
        sourceHandSize = detail.sourceHandSize,
        targetHandSize = detail.targetHandSize,
    }
end

local function buildQuickInterruptPopupData(action, result)
    if not (result and result.success and result.quickInterrupt and result.quickInterruptResolution) then
        return nil
    end

    action = action or {}
    local detail = result.quickInterruptResolution
    local actor = detail.actor or action.actor
    local actionType = detail.actionType or action.type
    local actionLabel = aidActionLabel(actionType)
    local actorName = entityName(actor, "Quick adventurer")
    local text = actorName .. " interrupts with " .. tostring(actionLabel)

    return {
        title = "Quick!",
        text = text,
        actor = actor,
        actionType = actionType,
        actionName = actionLabel,
        card = detail.card or action.card,
        cardName = detail.cardName or (action.card and action.card.name),
        cardSuit = detail.cardSuit or (action.card and action.card.suit),
        cardValue = detail.cardValue or (action.card and action.card.value),
        round = detail.round or action.round,
        count = detail.count or action.count,
        previousState = detail.previousState,
        previousActive = detail.previousActive,
        previousActiveId = detail.previousActiveId,
        target = detail.target or action.target,
        targetId = detail.targetId or (action.target and action.target.id),
        destinationZone = detail.destinationZone or action.destinationZone,
        success = detail.success == true,
        description = detail.description or result.description,
    }
end

local function buildTwoHandedFocusPopupData(action, result)
    if not (result and result.twoHandedFocusMinorAttack) then
        return nil
    end

    action = action or {}
    local detail = result.twoHandedFocusMinorAttack
    local actor = detail.actor or action.actor
    local actorName = entityName(actor, "Adventurer")
    local weapon = detail.weapon or action.weapon
    local weaponName = detail.weaponName or entityName(weapon, nil)
    local cardName = detail.cardName or (detail.card and detail.card.name) or
        (action.card and action.card.name) or "a Pentacles card"
    local text = actorName .. " uses " .. tostring(cardName) .. " for a minor melee Attack"

    if weaponName then
        text = text .. " with " .. tostring(weaponName)
    end

    return {
        title = "Two-handed Focus",
        text = text,
        actor = actor,
        weapon = weapon,
        weaponId = detail.weaponId or (weapon and weapon.id),
        weaponName = weaponName,
        card = detail.card or action.card,
        cardName = cardName,
        cardSuit = detail.cardSuit or (action.card and action.card.suit),
        cardValue = detail.cardValue or (action.card and action.card.value),
        testValue = detail.testValue or result.testValue,
        minorAction = true,
        success = result.success == true,
        description = result.description,
    }
end

local function buildProudAndAncientPopupData(action, result)
    if not (result and result.success and result.proudAndAncientWarCry) then
        return nil
    end

    action = action or {}
    local detail = result.proudAndAncientWarCry
    local actor = detail.actor or action.actor
    local actorName = entityName(actor, "Adventurer")
    local motto = detail.motto or action.motto or action.houseMotto
    local affectedCount = detail.affectedCount or result.affectedCount or 0
    local text = actorName .. " cries their house motto"

    if motto and motto ~= "" then
        text = actorName .. " cries \"" .. tostring(motto) .. "\""
    end
    if affectedCount > 0 then
        text = text .. " (" .. tostring(affectedCount) .. " inspired)"
    end

    return {
        title = "Proud and Ancient",
        text = text,
        actor = actor,
        card = detail.card or action.card,
        cardName = detail.cardName or (action.card and action.card.name),
        cardSuit = detail.cardSuit or (action.card and action.card.suit),
        cardValue = detail.cardValue or (action.card and action.card.value),
        house = detail.house or result.house,
        houseName = detail.houseName,
        motto = motto,
        affected = detail.affected or result.affected,
        affectedCount = affectedCount,
        resolveSpent = detail.resolveSpent == true,
        description = detail.description or result.description,
    }
end

local function buildMonsterHunterPopupData(action, result)
    if not (result and result.monsterHunter and resultHasEffect(result, "monster_hunter_attack_favor")) then
        return nil
    end

    action = action or {}
    local detail = result.monsterHunter
    local actor = detail.actor or action.actor
    local target = detail.target or action.target
    local actorName = entityName(actor, "Hunter")
    local targetName = entityName(target, "the target")
    local specialization = detail.specialization
    if not specialization and type(detail.specializationTags) == "table" then
        specialization = detail.specializationTags[1]
    end

    local text = actorName .. " has favor against " .. targetName
    if specialization and specialization ~= "" then
        text = text .. " (" .. tostring(specialization):gsub("_", " ") .. ")"
    end

    return {
        title = "Monster Hunter",
        text = text,
        actor = actor,
        target = target,
        targetId = detail.targetId or (target and target.id),
        actionType = detail.actionType or action.type,
        talentId = detail.talentId,
        foe = detail.foe,
        specialization = specialization,
        specializationTags = detail.specializationTags,
        favor = true,
        success = result.success == true,
        description = result.description,
    }
end

local function buildOrcBloodlinePopups(action, result)
    if not result then
        return {}
    end

    action = action or {}
    local popups = {}
    local actor = action.actor
    local target = action.target
    local weapon = action.weapon or result.weapon

    if resultHasEffect(result, "blur_shrouded") then
        local targetName = entityName(target, "Orc")
        popups[#popups + 1] = {
            title = "Wounding Blur",
            text = targetName .. " becomes Shrouded",
            actor = target,
            target = target,
            talentId = "blur",
            shroud = target and target.shroud,
            shrouded = true,
            description = result.description,
        }
    end

    if resultHasEffect(result, "berserkergang_entered") then
        local targetName = entityName(target, "Berserker")
        popups[#popups + 1] = {
            title = "Berserkergang",
            text = targetName .. " enters rage",
            actor = target,
            target = target,
            talentId = "berserkergang",
            entered = true,
            active = true,
            description = result.description,
        }
    end

    if resultHasEffect(result, "berserkergang_attack_favor") then
        local actorName = entityName(actor, "Berserker")
        popups[#popups + 1] = {
            title = "Berserkergang",
            text = actorName .. " attacks with favor",
            actor = actor,
            target = target,
            talentId = "berserkergang",
            attackFavor = true,
            favor = true,
            description = result.description,
        }
    end

    if resultHasEffect(result, "berserkergang_ended") then
        local actorName = entityName(actor, "Berserker")
        popups[#popups + 1] = {
            title = "Berserkergang",
            text = actorName .. "'s rage ends",
            actor = actor,
            target = target,
            talentId = "berserkergang",
            ended = true,
            description = result.description,
        }
    end

    if resultHasEffect(result, "quicksilver_blood_weapon_destroyed") then
        local targetName = entityName(target, "Orc")
        local weaponName = entityName(weapon, "the weapon")
        popups[#popups + 1] = {
            title = "Quicksilver Blood",
            text = targetName .. " destroys " .. weaponName,
            actor = target,
            target = target,
            attacker = actor,
            weapon = weapon,
            weaponName = weaponName,
            talentId = "quicksilver_blood",
            weaponDestroyed = true,
            description = result.description,
        }
    end

    if resultHasEffect(result, "poison_blood_critical") then
        local targetName = entityName(target, "Orc")
        local attackerName = entityName(actor, "attacker")
        popups[#popups + 1] = {
            title = "Poison Blood",
            text = targetName .. " critically wounds " .. attackerName,
            actor = target,
            target = target,
            attacker = actor,
            weapon = weapon,
            talentId = "poison_blood",
            critical = true,
            description = result.description,
        }
    end

    return popups
end

local function buildAidPopupData(action, result)
    if not result then
        return nil
    end

    action = action or {}
    if result.success and resultHasEffect(result, "aid_banked") and result.aid then
        local aid = result.aid
        local actor = action.actor
        local target = aid.target or action.target
        local actorName = entityName(actor, "Aider")
        local targetName = entityName(target, "ally")
        local triggerLabel = aidActionLabel(aid.triggerAction)
        local text = actorName .. " sets up " .. targetName .. "'s " .. triggerLabel

        if aid.objective and aid.objective ~= "" then
            text = actorName .. " sets up " .. targetName .. ": " .. tostring(aid.objective)
        end

        return {
            title = "Aid Another",
            text = text,
            actor = actor,
            target = target,
            aided = target,
            value = aid.value,
            triggerAction = aid.triggerAction,
            triggerTargetId = aid.triggerTargetId,
            objective = aid.objective,
            aidBanked = true,
        }
    end

    if resultHasEffect(result, "aided") and result.aidApplied then
        local aid = result.aidApplied
        local actor = action.actor
        local actorName = entityName(actor, "Ally")
        local sourceName = aid.source or entityName(aid.sourceActor, "Aider")
        local text = actorName .. " uses " .. tostring(sourceName) .. "'s help"

        if aid.objective and aid.objective ~= "" then
            text = text .. ": " .. tostring(aid.objective)
        end

        return {
            title = "Aid Another",
            text = text,
            actor = actor,
            target = action.target,
            aided = actor,
            source = aid.source,
            sourceActor = aid.sourceActor,
            sourceActorId = aid.sourceActorId,
            value = aid.value,
            triggerAction = aid.triggerAction or action.type,
            triggerTarget = aid.triggerTarget,
            triggerTargetId = aid.triggerTargetId,
            objective = aid.objective,
            aidApplied = true,
            discarded = aid.discarded == true,
        }
    end

    return nil
end

local function buildPullItemPopupData(action, result)
    if not (result and result.success) then
        return nil
    end
    if not (resultHasEffect(result, "item_pulled_pack") or resultHasEffect(result, "item_pulled_belt")) then
        return nil
    end

    action = action or {}
    local actor = action.actor
    local actorName = entityName(actor, "Actor")
    local item = result.item or action.item
    local swappedItem = result.swappedItem
    local sourceLocation = result.sourceLocation or
        (resultHasEffect(result, "item_pulled_belt") and "belt" or "pack")
    local title = sourceLocation == "belt" and "Pull from Belt" or "Pull from Pack"
    local text = actorName .. " pulls " .. entityName(item, "an item") .. " from " .. sourceLocation

    if swappedItem then
        text = text .. " and swaps out " .. entityName(swappedItem, "a held item")
    end

    return {
        title = title,
        text = text,
        actor = actor,
        item = item,
        pulledItem = item,
        swappedItem = swappedItem,
        sourceLocation = sourceLocation,
        destinationLocation = result.destinationLocation or "hands",
        fromPack = sourceLocation == "pack",
        fromBelt = sourceLocation == "belt",
    }
end

local function buildUseItemPopupData(action, result)
    if not (result and resultHasEffect(result, "item_used")) then
        return nil
    end

    action = action or {}
    local detail = result.itemUse or {}
    local actor = detail.actor or action.actor
    local item = detail.item or result.item or action.item
    local target = detail.target or action.target
    local actorName = entityName(actor, "Actor")
    local itemName = entityName(item, "an item")
    local text = actorName .. " uses " .. itemName

    if target then
        text = text .. " on " .. entityName(target, "target")
    elseif detail.targetZone or action.targetZone or action.destinationZone then
        text = text .. " in " .. tostring(detail.targetZone or action.targetZone or action.destinationZone)
    end

    if detail.itemConsumed or result.consumedItem then
        text = text .. " and consumes it"
    elseif detail.spentItemUnit or result.spentItemUnit then
        text = text .. " and spends one"
    end

    local itemEffect = detail.itemEffect or result.itemEffect

    return {
        title = "Use Item",
        text = text,
        actor = actor,
        item = item,
        itemId = detail.itemId or (item and item.id),
        itemName = detail.itemName or itemName,
        itemLocation = detail.itemLocation,
        target = target,
        targetId = detail.targetId or (target and target.id),
        secondaryTarget = detail.secondaryTarget or action.secondaryTarget,
        secondaryTargetId = detail.secondaryTargetId or (action.secondaryTarget and action.secondaryTarget.id),
        targetZone = detail.targetZone or action.targetZone,
        destinationZone = detail.destinationZone or action.destinationZone,
        itemEffect = itemEffect,
        itemEffectType = detail.itemEffectType or (itemEffect and itemEffect.type),
        itemUseAttribute = detail.itemUseAttribute or result.itemUseAttribute,
        damageDealt = detail.damageDealt or result.damageDealt,
        consumedItem = detail.consumedItem or result.consumedItem,
        consumedItemStatus = detail.consumedItemStatus or result.consumedItemStatus,
        itemConsumed = detail.itemConsumed == true or result.consumedItem ~= nil,
        spentItemUnit = detail.spentItemUnit or result.spentItemUnit,
        success = detail.success,
        description = detail.description or result.description,
        effects = detail.effects or result.effects,
        noEffect = itemEffect and itemEffect.noEffect == true,
    }
end

local function buildUpMySleevePopupData(action, result)
    if not (result and result.success and resultHasEffect(result, "item_produced") and
       resultHasEffect(result, "up_my_sleeve")) then
        return nil
    end

    action = action or {}
    local detail = result.upMySleeveCreation or (result.upMySleeve and result.upMySleeve.upMySleeveCreation) or
        result.upMySleeve or {}
    local actor = detail.actor or result.actor or action.actor
    local item = detail.item or result.item or (result.upMySleeve and result.upMySleeve.item)
    local actorName = entityName(actor, "Adventurer")
    local itemName = detail.itemName or entityName(item, "an item")
    local text = actorName .. " produces " .. itemName .. " from a sleeve"

    return {
        title = "Up My Sleeve",
        text = text,
        actor = actor,
        item = item,
        itemId = detail.itemId or (item and item.id),
        itemName = itemName,
        templateId = detail.templateId or result.templateId,
        location = detail.location or result.location,
        resolveSpent = detail.resolveSpent or result.resolveSpent,
        uses = detail.uses or result.uses,
        usesRemaining = detail.usesRemaining or result.usesRemaining,
        maxUses = detail.maxUses,
        produced = true,
        description = detail.description or result.description,
    }
end

local function buildCounterSpellPopupData(action, result)
    if not (result and result.counterSpell and result.success) then
        return nil
    end
    if not (resultHasEffect(result, "counter_spell_fizzled") or
       resultHasEffect(result, "counter_spell_negated")) then
        return nil
    end

    action = action or {}
    local detail = result.counterSpellResolution or {}
    local actor = detail.actor or action.actor
    local actorName = entityName(actor, "Counter-speller")
    local spellName = detail.spellName
    if not spellName and detail.incomingSpell then
        spellName = detail.incomingSpell.name or detail.incomingSpell.id
    end
    if not spellName and detail.activeSpell then
        spellName = detail.activeSpell.name or detail.activeSpell.spellId or detail.activeSpell.id
    end
    spellName = spellName or "the spell"

    local negated = detail.negated == true or resultHasEffect(result, "counter_spell_negated")
    local maleficence = detail.maleficenceTriggered == true or resultHasEffect(result, "counter_spell_maleficence")
    local text = actorName .. " counters " .. tostring(spellName)
    if negated then
        text = actorName .. " negates " .. tostring(spellName)
    elseif maleficence then
        text = actorName .. " fizzles " .. tostring(spellName) .. " with maleficence"
    else
        text = actorName .. " fizzles " .. tostring(spellName)
    end

    return {
        title = "Counter-spell",
        text = text,
        actor = actor,
        target = detail.target or action.target,
        mode = detail.mode or (negated and "ongoing" or "incoming"),
        incomingAction = detail.incomingAction or action.incomingAction or action.spellAction or action.targetAction,
        incomingSpell = detail.incomingSpell or action.incomingSpell or action.spell,
        activeSpell = detail.activeSpell or action.activeSpell or action.spellEntry or action.ongoingSpell,
        spellCaster = detail.spellCaster or action.spellCaster or action.targetCaster or action.caster,
        endedSpell = detail.endedSpell or result.endedSpell,
        spellId = detail.spellId,
        spellName = spellName,
        branch = detail.branch or result.branch,
        resolveSpent = detail.resolveSpent or result.resolveSpent,
        enemyValue = detail.enemyValue or result.enemyValue,
        counterValue = detail.counterValue or result.counterValue,
        counterSpellWon = detail.counterSpellWon,
        spellFizzled = detail.spellFizzled == true or result.spellFizzled == true,
        negated = negated,
        maleficence = detail.maleficence or result.maleficence,
        maleficenceTriggered = maleficence,
        description = detail.description or result.description,
    }
end

local function buildDwimmercraftPopupData(action, result)
    if not (result and result.success and resultHasEffect(result, "dwimmercraft")) then
        return nil
    end

    action = action or {}
    local detail = result.dwimmercraftResolution or {}
    local actor = detail.actor or action.actor
    local actorName = entityName(actor, "Dwimmercrafter")
    local mode = detail.mode or result.dwimmercraftMode or action.dwimmercraftEffect or action.mode
    local text = actorName .. " works minor magic"

    if mode == "second_sight" then
        text = actorName .. " focuses second sight"
    elseif mode == "levitate" then
        local object = detail.object or detail.target or action.object or action.target or action.item
        text = actorName .. " moves " .. entityName(object, "a small object") .. " with minor magic"
    elseif mode == "simple_illusion" then
        text = actorName .. " conjures " .. tostring(detail.image or (detail.illusion and detail.illusion.image) or
            action.image or "a small illusion")
    elseif mode == "showy_illusion" then
        text = actorName .. " conjures a harmless magical display"
    end

    return {
        title = "Dwimmercraft",
        text = text,
        actor = actor,
        mode = mode,
        target = detail.target or action.target,
        targetId = detail.targetId or (action.target and action.target.id),
        object = detail.object or action.object or action.item,
        objectId = detail.objectId or (action.object and action.object.id) or (action.item and action.item.id),
        objectMotion = detail.objectMotion or action.objectMotion or action.motion,
        noFineControl = detail.noFineControl == true,
        maxWeightPounds = detail.maxWeightPounds,
        illusion = detail.illusion or result.illusion,
        illusionId = detail.illusionId,
        image = detail.image,
        harmless = detail.harmless == true,
        obviouslyMagical = detail.obviouslyMagical == true,
        fitsOneHand = detail.fitsOneHand == true,
        convincingUntilInteracted = detail.convincingUntilInteracted == true,
        secondSight = detail.secondSight or result.secondSight,
        duration = detail.duration,
        resolveSpent = detail.resolveSpent or result.resolveSpent,
        seesInvisible = detail.seesInvisible == true,
        seesShrouded = detail.seesShrouded == true,
        trueFormIllusions = detail.trueFormIllusions == true,
        detectsMagic = detail.detectsMagic == true,
        detectsEnchantments = detail.detectsEnchantments == true,
        identifiesSorcerers = detail.identifiesSorcerers == true,
        challengeActive = detail.challengeActive == true,
        miscAction = detail.miscAction == true,
        description = detail.description or result.description,
    }
end

local function buildGuardPopupData(action, result)
    if not (result and result.success and resultHasEffect(result, "guarded")) then
        return nil
    end

    action = action or {}
    local actor = action.actor
    local actorName = entityName(actor, "Guardian")
    local oldValue = result.oldInitiativeValue
    local newValue = result.newInitiativeValue or (result.newInitiativeCard and result.newInitiativeCard.value) or
        (action.card and action.card.value)
    local text = actorName .. " replaces Initiative"

    if oldValue and newValue then
        text = actorName .. " replaces Initiative " .. tostring(oldValue) .. " with " .. tostring(newValue)
    elseif newValue then
        text = actorName .. " sets Initiative to " .. tostring(newValue)
    end

    return {
        title = "Guard",
        text = text,
        actor = actor,
        oldInitiativeCard = result.oldInitiativeCard or result.oldInitiativeCardDiscarded,
        oldInitiativeCardDiscarded = result.oldInitiativeCardDiscarded,
        oldInitiativeValue = oldValue,
        newInitiativeCard = result.newInitiativeCard or action.card,
        newInitiativeValue = newValue,
        discardedOldInitiative = resultHasEffect(result, "guard_old_initiative_discarded"),
    }
end

local function buildPreparedDefensePopupData(action, result)
    if not (result and result.success) then
        return nil
    end
    if not (resultHasEffect(result, "dodge_prepared") or resultHasEffect(result, "riposte_prepared")) then
        return nil
    end

    action = action or {}
    local defense = result.preparedDefense or result.dodgePrepared or result.ripostePrepared or {}
    local defenseType = defense.type or (resultHasEffect(result, "riposte_prepared") and "riposte" or "dodge")
    local title = defenseType == "riposte" and "Riposte" or "Dodge"
    local actor = action.actor or defense.actor
    local actorName = entityName(actor, "Defender")
    local text = actorName .. " prepares a facedown " .. title
    local protectedTarget = defense.protectedTarget or action.protectedTarget or action.defenseTarget or
        action.protectTarget or action.guardTarget or action.allyTarget

    if protectedTarget then
        text = text .. " for " .. entityName(protectedTarget, "ally")
    end
    if defense.replacedDefense or result.replacedDefense then
        text = text .. " and discards the previous facedown action"
    end

    return {
        title = title,
        text = text,
        actor = actor,
        defenseType = defenseType,
        value = defense.value or result.testValue,
        faceValue = defense.faceValue or (action.card and action.card.value),
        modifier = defense.modifier or result.modifier or 0,
        card = defense.card or action.card,
        isMinorAction = defense.isMinorAction == true or action.isMinorAction == true,
        protectedTarget = protectedTarget,
        protectedTargetId = defense.protectedTargetId or (protectedTarget and protectedTarget.id),
        protectedZone = defense.protectedZone or (protectedTarget and protectedTarget.zone),
        replacedDefense = defense.replacedDefense or result.replacedDefense,
        replacedDefenseDiscarded = defense.replacedDefenseDiscarded or result.replacedDefenseDiscarded,
        weapon = defense.weapon,
        lesserDoom = defense.lesserDoom,
        lesserDoomCard = defense.lesserDoomCard,
    }
end

local function buildFacedownActionPopupData(action, result)
    if not (result and result.success) then
        return nil
    end
    if not (resultHasEffect(result, "aim_prepared") or resultHasEffect(result, "vigilance_prepared")) then
        return nil
    end

    action = action or {}
    local detail = result.facedownAction or {}
    local actionType = detail.type or (resultHasEffect(result, "vigilance_prepared") and "vigilance" or "aim")
    local actor = action.actor or detail.actor
    local actorName = entityName(actor, "Actor")
    local title = actionType == "vigilance" and "Vigilance" or "Aim"
    local text = actorName .. " prepares " .. title

    if actionType == "aim" then
        local aim = result.aim or detail
        local target = action.target or detail.target or aim.target
        local weapon = action.weapon or detail.weapon or aim.weapon
        text = actorName .. " aims at " .. entityName(target, "target")
        if weapon then
            text = text .. " with " .. entityName(weapon, "bow")
        end

        return {
            title = "Aim",
            text = text,
            actor = actor,
            target = target,
            targetId = detail.targetId or aim.targetId,
            weapon = weapon,
            value = detail.value or result.aimBonus or aim.value,
            faceValue = detail.faceValue or aim.faceValue,
            card = detail.card or aim.card or action.card,
            isMinorAction = detail.isMinorAction == true or action.isMinorAction == true,
            replacedFacedownActions = detail.replacedFacedownActions or result.replacedFacedownActions,
        }
    end

    local vigilance = result.vigilance or detail
    local followUpAction = detail.followUpAction or vigilance.followUpAction
    local followUpLabel = detail.followUpActionName or aidActionLabel(followUpAction)
    text = actorName .. " watches for " .. followUpLabel

    return {
        title = "Vigilance",
        text = text,
        actor = actor,
        value = detail.value or (action.card and action.card.value),
        faceValue = detail.faceValue or (action.card and action.card.value),
        card = detail.card or vigilance.card or action.card,
        trigger = detail.trigger or vigilance.trigger,
        followUpAction = followUpAction,
        followUpActionName = followUpLabel,
        followUpTargetPolicy = detail.followUpTargetPolicy or vigilance.followUpTargetPolicy,
        followUpTarget = detail.followUpTarget or vigilance.followUpTarget,
        followUpDestinationZone = detail.followUpDestinationZone or vigilance.followUpDestinationZone,
        weapon = detail.weapon or vigilance.weapon,
        declaredOrder = detail.declaredOrder or vigilance.declaredOrder,
        isMinorAction = detail.isMinorAction == true or action.isMinorAction == true,
        replacedFacedownActions = detail.replacedFacedownActions or result.replacedFacedownActions,
    }
end

local function buildTestFatePopupData(action, result)
    if not (result and result.pendingTestOfFate) then
        return nil
    end

    action = action or {}
    local request = result.testFateRequest or {}
    local actor = action.actor or request.entity
    local actorName = entityName(actor, "Actor")
    local attribute = request.attribute or action.testAttribute or action.attribute or "pentacles"
    local targetSuit = request.targetSuit or action.targetSuit or action.testSuit
    local text = actorName .. " starts a " .. tostring(attribute):gsub("_", " ") .. " Test of Fate"

    if targetSuit then
        text = text .. " against " .. tostring(targetSuit)
    end
    if request.favor == true then
        text = text .. " with favor"
    elseif request.favor == false then
        text = text .. " with disfavor"
    end

    return {
        title = "Test Fate",
        text = text,
        actor = actor,
        attribute = attribute,
        targetSuit = targetSuit,
        favor = request.favor,
        attributeBonus = request.attributeBonus,
        totemBonus = request.totemBonus,
        spentResolveForFavor = request.spentResolveForFavor == true,
        motif = request.motif,
        motifFavor = request.motifFavor == true,
        kinTalentFavor = request.kinTalentFavor,
        kinTalentFavorUnavailable = request.kinTalentFavorUnavailable,
        actionCard = request.actionCard or action.card,
        request = request,
        pendingTestOfFate = true,
    }
end

local function buildBidLorePopupData(action, result)
    if not (result and result.pendingBidLore) then
        return nil
    end

    action = action or {}
    local request = result.bidLoreRequest or {}
    local actor = action.actor or request.actor or request.entity
    local actorName = entityName(actor, "Actor")
    local subjects = request.availableSubjects or {}
    local text = actorName .. " bids lore"

    if #subjects > 0 then
        text = text .. " (" .. tostring(#subjects) .. " subject(s) available)"
    end

    return {
        title = "Bid Lore",
        text = text,
        actor = actor,
        action = request.action or action,
        actionCard = action.card,
        actionDef = request.actionDef,
        challengeController = request.challengeController,
        roomId = request.roomId,
        availableSubjects = subjects,
        questionTypes = request.questionTypes or {},
        request = request,
        pendingBidLore = true,
    }
end

local function buildSpellPopupData(action, result)
    if not (result and result.success and resultHasEffect(result, "spell_cast")) then
        return nil
    end

    action = action or {}
    local spellcasting = result.spellcasting or {}
    local spell = spellcasting.spell or result.spell or action.spell
    if not spell then
        return nil
    end

    local actor = spellcasting.actor or action.actor
    local actorName = entityName(actor, "Caster")
    local targets = spellcasting.targets or result.spellTargets
    local target = spellcasting.target or action.target
    if not target and type(targets) == "table" then
        target = targets[1]
    end

    local spellName = spellcasting.spellName or spell.name or spell.id or "spell"
    local text = actorName .. " casts " .. tostring(spellName)
    if target then
        text = text .. " on " .. entityName(target, "target")
    end

    local resolveSpent = spellcasting.resolveSpent
    if resolveSpent == nil then
        resolveSpent = result.resolveSpent
    end
    if resolveSpent ~= nil then
        text = text .. " (" .. tostring(resolveSpent) .. " Resolve)"
    end

    return {
        title = "Speak Incantation",
        text = text,
        actor = actor,
        target = target,
        targets = targets,
        spell = spell,
        spellId = spellcasting.spellId or spell.id,
        spellName = spellName,
        branch = spellcasting.branch or spell.branch,
        component = spellcasting.component or result.component,
        componentId = spellcasting.componentId,
        componentName = spellcasting.componentName,
        resolveSpent = resolveSpent,
        spellResolveValue = spellcasting.spellResolveValue or result.spellResolveValue,
        resolveCommitted = spellcasting.resolveCommitted,
        pactChargeSpent = spellcasting.pactChargeSpent == true,
        pactCharge = spellcasting.pactCharge,
        componentlessSpellcasting = spellcasting.componentlessSpellcasting == true,
        trainingXPSpent = spellcasting.trainingXPSpent == true,
        activeSpell = spellcasting.activeSpell or result.activeSpell,
        ongoingSpell = spellcasting.ongoingSpell == true or result.activeSpell ~= nil,
        concentration = spellcasting.concentration,
        effects = spellcasting.effects or result.effects,
        description = spellcasting.description or result.description,
        spellTargets = spellcasting.spellTargets or result.spellTargets,
        bindingTargets = spellcasting.bindingTargets or result.bindingTargets,
        animatedObject = spellcasting.animatedObject or result.animatedObject,
        controlOrder = spellcasting.controlOrder or result.controlOrder,
        malediction = spellcasting.malediction or result.malediction,
        raisedZombie = spellcasting.raisedZombie or result.raisedZombie,
        fleshcraft = spellcasting.fleshcraft or result.fleshcraft,
        giveForm = spellcasting.giveForm or result.giveForm,
        portableHole = spellcasting.portableHole or result.portableHole,
        mirrorMeld = spellcasting.mirrorMeld or result.mirrorMeld,
        visualIllusion = spellcasting.visualIllusion or result.visualIllusion,
        truthSense = spellcasting.truthSense or result.truthSense,
        stinkingCloud = spellcasting.stinkingCloud or result.stinkingCloud,
        spellcasting = spellcasting,
    }
end

local function buildReloadPopupData(action, result)
    if not (result and result.success and resultHasEffect(result, "reloaded")) then
        return nil
    end

    action = action or {}
    local actor = action.actor
    local weapon = result.reloadedWeapon or result.weapon or action.weapon
    local actorName = entityName(actor, "Actor")
    local weaponName = entityName(weapon, "crossbow")
    local ammoType = result.ammoType or "bolt"
    local text = actorName .. " reloads " .. weaponName

    if result.ammoTracked and result.ammoRemaining ~= nil then
        text = text .. " (" .. tostring(result.ammoRemaining) .. " " .. tostring(ammoType) .. " remaining)"
    end

    return {
        title = "Reload Crossbow",
        text = text,
        actor = actor,
        weapon = weapon,
        reloadedWeapon = weapon,
        ammoType = ammoType,
        ammoTracked = result.ammoTracked == true,
        ammoAvailable = result.ammoAvailable,
        ammoRemaining = result.ammoRemaining,
        loaded = weapon and weapon.isLoaded == true,
    }
end

local function roughhouseEffectLabel(effect)
    local normalized = effect and tostring(effect):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("[%s%-]+", "_")
    local labels = {
        trip = "Trip",
        disarm = "Disarm",
        displace = "Displace",
        root = "Root",
        exhaust = "Exhaust",
        notch = "Notch",
        silence = "Silence",
    }
    return labels[normalized] or (effect and tostring(effect):gsub("_", " ")) or "Roughhouse"
end

local function buildRoughhousePopupData(action, result)
    if not (result and result.success and resultHasEffect(result, "roughhouse")) then
        return nil
    end

    action = action or {}
    local detail = result.roughhouse or {}
    local effect = detail.roughhouseEffect or detail.effect or result.roughhouseEffect or action.roughhouseEffect
    if not effect then
        return nil
    end

    local actor = action.actor or detail.actor
    local target = action.target or detail.target or result.roughhouseTarget
    local actorName = entityName(actor, "Actor")
    local targetName = entityName(target, "target")
    local label = roughhouseEffectLabel(effect)
    local text = actorName .. " uses " .. label .. " on " .. targetName
    local destinationZone = result.roughhouseDestinationZone or detail.destinationZone or action.destinationZone
    local oldZone = detail.oldZone
    local newZone = detail.newZone
    local droppedItem = result.roughhouseDroppedItem or detail.droppedItem or result.droppedItem
    local notchedItem = result.roughhouseNotchedItem or detail.notchedItem or result.notchedItem

    if effect == "trip" then
        text = actorName .. " trips " .. targetName
    elseif effect == "root" then
        text = actorName .. " roots " .. targetName
    elseif effect == "disarm" then
        text = actorName .. " disarms " .. targetName
        if droppedItem then
            text = text .. " of " .. entityName(droppedItem, "an item")
        end
    elseif effect == "displace" then
        text = actorName .. " displaces " .. targetName
        if destinationZone then
            text = text .. " to " .. tostring(destinationZone)
        end
    elseif effect == "notch" and notchedItem then
        text = actorName .. " Notches " .. entityName(notchedItem, "an item")
    end

    return {
        title = "Roughhouse",
        text = text,
        actor = actor,
        target = target,
        effect = effect,
        roughhouseEffect = effect,
        effectLabel = label,
        actionValue = result.roughhouseActionValue or detail.actionValue,
        targetInitiative = result.roughhouseTargetInitiative or detail.targetInitiative,
        oldZone = oldZone,
        newZone = newZone,
        destinationZone = destinationZone,
        droppedItem = droppedItem,
        notchedItem = notchedItem,
        itemNotchResult = result.roughhouseItemNotchResult or detail.itemNotchResult,
        prone = resultHasEffect(result, "prone"),
        rooted = resultHasEffect(result, "rooted"),
        disarmed = resultHasEffect(result, "disarmed"),
        displaced = resultHasEffect(result, "displaced"),
        riposteResult = result.riposteResult,
    }
end

local function recoverEffectLabel(effect)
    local normalized = effect and tostring(effect):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("[%s%-]+", "_")
    local labels = {
        rooted = "Rooted",
        root = "Rooted",
        prone = "Prone",
        tripped = "Prone",
        blind = "Blind",
        blinded = "Blind",
        deaf = "Deafened",
        deafened = "Deafened",
        silenced = "Silenced",
        silence = "Silenced",
        exhausted = "Exhausted",
        burning = "Burning",
        disarmed = "Disarmed",
        dropped_item = "Dropped Item",
        webbed = "Webbed",
        webbed_limb = "Webbed Limb",
    }
    return labels[normalized] or (effect and tostring(effect):gsub("_", " ")) or "an effect"
end

local function buildRecoverPopupData(action, result)
    if not result then
        return nil
    end

    local detail = result.recover or {}
    local recoveredEffect = result.recoveredEffect or detail.recoveredEffect
    local blockedEffect = result.recoverBlockedEffect or detail.blockedEffect
    local recoveredItem = result.recoveredItem or detail.recoveredItem
    if not (recoveredEffect or recoveredItem or blockedEffect) then
        return nil
    end

    action = action or {}
    local actor = action.actor or detail.actor
    local actorName = entityName(actor, "Actor")
    local text = actorName .. " recovers"

    if recoveredItem then
        text = actorName .. " recovers " .. entityName(recoveredItem, "an item")
    elseif recoveredEffect then
        text = actorName .. " recovers from " .. recoverEffectLabel(recoveredEffect)
    elseif blockedEffect then
        text = actorName .. " cannot Recover from " .. recoverEffectLabel(blockedEffect)
    end

    return {
        title = "Recover",
        text = text,
        actor = actor,
        requestedEffect = result.recoverRequestedEffect or detail.requestedEffect,
        recoveredEffect = recoveredEffect,
        recoveredItem = recoveredItem,
        blockedEffect = blockedEffect,
        blockedReason = result.recoverBlockedReason or detail.blockedReason,
        recovered = result.success == true,
        blocked = result.success == false and blockedEffect ~= nil,
    }
end

local function buildBanterPopupData(action, result)
    if not result then
        return nil
    end

    action = action or {}
    local detail = result.banter or {}
    local actionType = action.normalizedType or action.type
    local normalized = actionType and tostring(actionType):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("[%s%-]+", "_")
    if not result.banter and not (normalized == "banter" and result.targetMorale and
       result.oldDisposition and result.newDisposition) then
        return nil
    end

    local actor = action.actor or detail.actor
    local target = action.target or detail.target
    local actorName = entityName(actor, "Speaker")
    local targetName = entityName(target, "target")
    local success = detail.success
    if success == nil then
        success = result.success == true
    end

    local oldLabel = detail.oldDispositionLabel or result.oldDispositionLabel or detail.oldDisposition or
        result.oldDisposition
    local newLabel = detail.newDispositionLabel or result.newDispositionLabel or detail.newDisposition or
        result.newDisposition
    local targetMorale = detail.targetMorale or result.targetMorale
    local socialModifier = detail.socialModifier or result.socialModifier or 0
    local text = actorName .. " Banters with " .. targetName

    if success then
        text = actorName .. " beats " .. targetName .. "'s Morale"
        if oldLabel and newLabel then
            text = actorName .. " shifts " .. targetName .. " from " .. tostring(oldLabel) .. " to " ..
                tostring(newLabel)
        end
    else
        text = actorName .. " fails to beat " .. targetName .. "'s Morale"
        if newLabel then
            text = text .. "; " .. targetName .. " turns " .. tostring(newLabel)
        end
    end

    if targetMorale then
        text = text .. " (Morale " .. tostring(targetMorale) .. ")"
    end
    if socialModifier > 0 then
        text = text .. " with favor"
    elseif socialModifier < 0 then
        text = text .. " with disfavor"
    end

    return {
        title = "Banter",
        text = text,
        actor = actor,
        target = target,
        value = detail.value or detail.actionValue or result.testValue,
        actionValue = detail.actionValue or detail.value or result.testValue,
        difficulty = detail.difficulty or result.difficulty,
        success = success,
        targetMorale = targetMorale,
        moraleBand = detail.moraleBand or result.moraleBand,
        newMorale = detail.newMorale or result.newMorale,
        moraleDamage = detail.moraleDamage or result.moraleDamage or 0,
        intent = detail.intent,
        dispositionTarget = detail.dispositionTarget or result.dispositionTarget,
        oldDisposition = detail.oldDisposition or result.oldDisposition,
        oldDispositionSeverity = detail.oldDispositionSeverity or result.oldDispositionSeverity,
        oldDispositionLabel = oldLabel,
        newDisposition = detail.newDisposition or result.newDisposition,
        newDispositionSeverity = detail.newDispositionSeverity or result.newDispositionSeverity,
        newDispositionLabel = newLabel,
        dispositionChange = detail.dispositionChange or result.dispositionChange,
        socialModifier = socialModifier,
        socialFavorTag = detail.socialFavorTag or result.socialFavorTag,
        socialDisfavorTag = detail.socialDisfavorTag or result.socialDisfavorTag,
        socialItemTags = detail.socialItemTags or result.socialItemTags,
        extraAid = detail.extraAid or resultHasEffect(result, "social_extra_aid"),
        concession = detail.concession or resultHasEffect(result, "social_concession"),
        shouldFlee = detail.shouldFlee or resultHasEffect(result, "social_flee"),
        socialCombatRisk = detail.socialCombatRisk or resultHasEffect(result, "social_combat_risk"),
    }
end

local function buildAvoidPopupData(action, result)
    if not result then
        return nil
    end
    if not (resultHasEffect(result, "avoid_success") or resultHasEffect(result, "avoid_failed") or
       resultHasEffect(result, "avoid_target_passed")) then
        return nil
    end

    action = action or {}
    local movement = result.avoidMovement or {}
    local actor = action.actor or movement.actor
    local oldZone = result.oldZone or movement.oldZone
    local newZone = result.newZone or result.destinationZone or movement.newZone or action.destinationZone
    if not newZone then
        return nil
    end

    local actorName = entityName(actor, "Actor")
    local targetName = entityName(action.target or result.avoidTarget, nil)
    local route = "to " .. tostring(newZone)
    if oldZone and oldZone ~= newZone then
        route = "from " .. tostring(oldZone) .. " to " .. tostring(newZone)
    end
    local text = actorName .. " avoids " .. route
    if targetName then
        text = actorName .. " gets past " .. targetName .. " " .. route
    end

    local failures = result.avoidFailures or movement.avoidFailures or 0
    local wounds = result.avoidWounds or movement.avoidWounds or 0
    local declines = result.avoidWoundDeclines or movement.avoidWoundDeclines
    local declineCount = type(declines) == "table" and #declines or 0

    if failures > 0 then
        text = actorName .. " escapes " .. route .. " after " ..
            tostring(failures) .. " failed Avoid check(s)"
        if wounds > 0 then
            text = text .. " and " .. tostring(wounds) .. " Wound(s)"
        elseif declineCount > 0 then
            text = text .. " with the Wound declined"
        end
    end

    return {
        title = "Avoid",
        text = text,
        actor = actor,
        target = action.target or result.avoidTarget,
        oldZone = oldZone,
        newZone = newZone,
        destinationZone = newZone,
        movementType = "avoid",
        avoidValue = result.avoidValue or movement.avoidValue,
        targetInitiative = result.targetInitiative or movement.targetInitiative,
        avoidFailures = failures,
        avoidWounds = wounds,
        avoidWoundDeclines = declines,
        avoidOpponents = result.avoidOpponents or movement.avoidOpponents,
        targetPassed = resultHasEffect(result, "avoid_target_passed"),
        failedButMoved = resultHasEffect(result, "avoid_failed"),
        woundDeclined = declineCount > 0,
    }
end

local function buildMovementPopupData(action, result)
    if not (result and result.success and resultHasEffect(result, "moved")) then
        return nil
    end

    action = action or {}
    local movementType = result.movementType or action.type or "move"
    local normalized = tostring(movementType):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("[%s%-]+", "_")
    if normalized ~= "move" and normalized ~= "dash" then
        return nil
    end
    if result.acrobatTraversal or resultHasEffect(result, "traversal_test_passed") or
       resultHasEffect(result, "traversal_test_failed") then
        return nil
    end

    local movement = result.movement or {}
    local actor = action.actor or movement.actor
    local oldZone = result.oldZone or movement.oldZone
    local newZone = result.newZone or result.destinationZone or movement.newZone or action.destinationZone
    if not newZone then
        return nil
    end

    local actorName = entityName(actor, "Mover")
    local title = normalized == "dash" and "Dash" or "Move"
    local verb = normalized == "dash" and "dashes" or "moves"
    local text = actorName .. " " .. verb .. " to " .. tostring(newZone)
    if oldZone and oldZone ~= newZone then
        text = actorName .. " " .. verb .. " from " .. tostring(oldZone) .. " to " .. tostring(newZone)
    end

    local partingBlows = result.partingBlows or movement.partingBlows
    local partingBlowWounds = result.partingBlowWounds or movement.partingBlowWounds or
        (partingBlows and partingBlows.wounds) or 0
    local partingBlowDeclines = result.partingBlowDeclines or movement.partingBlowDeclines or
        (partingBlows and partingBlows.allowedPassers)
    local declinedCount = type(partingBlowDeclines) == "table" and #partingBlowDeclines or 0

    if partingBlowWounds > 0 then
        text = text .. " after " .. tostring(partingBlowWounds) .. " parting blow(s)"
    elseif declinedCount > 0 then
        text = text .. " after parting blow declined"
    end

    return {
        title = title,
        text = text,
        actor = actor,
        oldZone = oldZone,
        newZone = newZone,
        destinationZone = newZone,
        movementType = normalized,
        partingBlows = partingBlows,
        partingBlowWounds = partingBlowWounds,
        partingBlowDeclines = partingBlowDeclines,
        partingBlowDeclined = declinedCount > 0,
        partingBlowsTaken = partingBlowWounds > 0,
    }
end

local function buildTrivialActionPopupData(action, result)
    if not (result and result.success and resultHasEffect(result, "trivial_action")) then
        return nil
    end

    action = action or {}
    local actor = action.actor
    local actorName = entityName(actor, "Actor")
    local target = action.target or action.object or action.feature
    local item = result.pickedUpItem or result.item or action.item
    local trivialAction = action.trivialAction or action.intent or action.action
    local text = result.description
    local effect = "trivial_action"

    if resultHasEffect(result, "dropped_prone") then
        target = actor
        effect = "dropped_prone"
        text = actorName .. " drops prone"
    elseif resultHasEffect(result, "opened") then
        effect = "opened"
        text = actorName .. " opens " .. entityName(target, "the way")
    elseif resultHasEffect(result, "activated") then
        effect = "activated"
        text = actorName .. " activates " .. entityName(target, "the mechanism")
    elseif resultHasEffect(result, "ground_item_picked_up") or resultHasEffect(result, "item_picked_up") then
        effect = "item_picked_up"
        text = actorName .. " picks up " .. entityName(item, "an item")
    elseif not text or text == "" then
        text = actorName .. " takes a quick action"
    end

    return {
        title = "Trivial Action",
        text = text,
        actor = actor,
        target = target,
        item = item,
        trivialAction = trivialAction,
        effect = effect,
        droppedProne = resultHasEffect(result, "dropped_prone"),
        opened = resultHasEffect(result, "opened"),
        activated = resultHasEffect(result, "activated"),
        pickedUp = resultHasEffect(result, "ground_item_picked_up") or resultHasEffect(result, "item_picked_up"),
        pickupLocation = result.pickupLocation,
    }
end

local function buildRetreatPopupData(action, result)
    if not result or not resultHasEffect(result, "retreat") then
        return nil
    end

    local outcome = result.retreatOutcome
    local title = "Retreat"
    local gmFacing = false
    local text = result.description
    local retreatComplication = result.retreatComplication

    if outcome == "impossible" or resultHasEffect(result, "retreat_impossible") then
        title = "Retreat Impossible"
        outcome = "impossible"
        gmFacing = true
    elseif result.complication or resultHasEffect(result, "retreat_complication") then
        title = "Retreat Complication"
        outcome = "complication"
        gmFacing = true
    elseif result.cornered or resultHasEffect(result, "retreat_cornered") or resultHasEffect(result, "retreat_disaster") then
        title = "Retreat Cornered"
        outcome = resultHasEffect(result, "retreat_disaster") and "disaster" or "cornered"
        gmFacing = true
    elseif resultHasEffect(result, "retreat_no_pursuit") then
        outcome = "no_pursuit"
    elseif resultHasEffect(result, "retreat_clean") then
        outcome = "clean"
    end

    if not text or text == "" then
        if outcome == "complication" then
            text = "The guild escapes, but the GM introduces a complication."
        elseif outcome == "cornered" or outcome == "disaster" then
            text = "The guild is cornered with no clear path of escape."
        elseif outcome == "impossible" then
            text = "The pursuer is too fast or too magical to escape."
        else
            text = "The guild retreats."
        end
    end

    return {
        title = title,
        text = text,
        actor = action and action.actor,
        outcome = outcome,
        retreatOutcome = outcome,
        escaped = result.escaped == true,
        complication = retreatComplication or result.complication,
        retreatComplication = retreatComplication,
        complicationTarget = retreatComplication and retreatComplication.target or nil,
        complicationTargetId = retreatComplication and retreatComplication.targetId or nil,
        routeDangerous = retreatComplication and retreatComplication.routeDangerous or false,
        cornered = result.cornered == true,
        gmFacing = gmFacing,
        retreatPursuit = result.retreatPursuit or result.retreatAdjudication,
        groupTest = result.groupTest,
        groupTestHits = result.groupTest and result.groupTest.hits or nil,
        participants = result.participants,
    }
end

--------------------------------------------------------------------------------
-- ANIMATION STEP TYPES
--------------------------------------------------------------------------------
M.STEP_TYPES = {
    CARD_SLAP      = "card_slap",       -- Show the card being played
    MATH_OVERLAY   = "math_overlay",    -- Show the calculation (e.g., "7 + 2 = 9")
    DAMAGE_RESULT  = "damage_result",   -- Show the outcome (hit/miss/wound)
    WOUND_WALK     = "wound_walk",      -- Show defense layers being checked
    TEXT_POPUP     = "text_popup",      -- Generic text display
    ENTITY_SHAKE   = "entity_shake",    -- Shake an entity portrait
    FLASH          = "flash",           -- Flash a UI element
    DELAY          = "delay",           -- Simple pause
}

--------------------------------------------------------------------------------
-- DEFAULT DURATIONS (in seconds)
--------------------------------------------------------------------------------
M.DURATIONS = {
    card_slap      = 0.6,
    math_overlay   = 0.5,
    damage_result  = 0.5,
    wound_walk     = 0.8,
    text_popup     = 0.7,
    entity_shake   = 0.3,
    flash          = 0.2,
    delay          = 0.3,
}

--------------------------------------------------------------------------------
-- ACTION SEQUENCER FACTORY
--------------------------------------------------------------------------------

--- Create a new ActionSequencer
-- @param config table: { eventBus }
-- @return ActionSequencer instance
function M.createActionSequencer(config)
    config = config or {}

    local sequencer = {
        eventBus = config.eventBus or events.globalBus,

        -- Queue of pending sequences
        -- Each sequence is an array of steps
        sequenceQueue = {},

        -- Current sequence being played
        currentSequence = nil,
        currentStepIndex = 0,
        currentStep = nil,

        -- Timing
        stepTimer = 0,
        stepDuration = 0,

        -- State
        playing = false,
        isPaused = false,

        -- Visual state for rendering
        activeVisuals = {},  -- { type, data, progress }

        -- Callbacks for custom rendering
        onStepStart = nil,   -- function(step)
        onStepEnd = nil,     -- function(step)
        onSequenceComplete = nil,  -- function(sequence)
    }

    ----------------------------------------------------------------------------
    -- INITIALIZATION
    ----------------------------------------------------------------------------

    --- Initialize and subscribe to events
    function sequencer:init()
        -- Listen for challenge actions to visualize
        self.eventBus:on(events.EVENTS.CHALLENGE_RESOLUTION, function(data)
            self:queueActionSequence(data)
        end)

        -- Listen for wound events to visualize
        self.eventBus:on(events.EVENTS.WOUND_TAKEN, function(data)
            self:queueWoundSequence(data)
        end)

        -- Counsel is a controller-level card transfer rather than a normal
        -- resolver action, so it emits its own presentation event.
        self.eventBus:on("counsel_card_given", function(data)
            self:queueCounselSequence(data)
        end)
    end

    ----------------------------------------------------------------------------
    -- QUEUE MANAGEMENT
    ----------------------------------------------------------------------------

    --- Queue a generic sequence of steps
    -- @param steps table: Array of { type, duration, data }
    function sequencer:push(steps)
        if not steps or #steps == 0 then
            return
        end

        -- Normalize steps (add default durations if missing)
        for _, step in ipairs(steps) do
            if not step.duration then
                step.duration = M.DURATIONS[step.type] or 0.5
            end
        end

        self.sequenceQueue[#self.sequenceQueue + 1] = steps

        -- Start playing if not already
        if not self.playing then
            self:startNextSequence()
        end
    end

    --- Queue a single step
    function sequencer:pushStep(stepType, data, duration)
        self:push({
            {
                type = stepType,
                data = data or {},
                duration = duration or M.DURATIONS[stepType] or 0.5,
            }
        })
    end

    function sequencer:queueCounselSequence(detail)
        local popup = buildCounselPopupData(detail)
        if not popup then
            return
        end

        self:push({
            {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = popup,
                duration = M.DURATIONS.text_popup,
            },
        })
    end

    --- Queue a standard action sequence (card -> math -> result)
    function sequencer:queueActionSequence(resolutionData)
        local action = resolutionData.action or {}
        local result = resolutionData.result or {}

        local steps = {}

        -- Step 1: Card slap (if a card was played)
        if action.card then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.CARD_SLAP,
                data = {
                    card = action.card,
                    actor = action.actor,
                    target = action.target,
                },
            }
        end

        if result.reaverCharge then
            local detail = result.reaverCharge
            local actor = detail.actor or action.actor
            local actorName = actor and (actor.name or actor.id) or "Reaver"
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = {
                    title = "Reaver",
                    text = actorName .. " charges to " .. tostring(detail.newZone or "the target"),
                    actor = actor,
                    oldZone = detail.oldZone,
                    newZone = detail.newZone,
                },
                duration = M.DURATIONS.text_popup,
            }
        end

        if result.doomEyeAutoHit then
            local actorName = action.actor and (action.actor.name or action.actor.id) or "Doom Eye"
            local targetName = action.target and (action.target.name or action.target.id) or "the target"
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = {
                    title = "Doom Eye",
                    text = actorName .. " ignores " .. targetName .. "'s Initiative",
                    actor = action.actor,
                    target = action.target,
                    autoHit = true,
                },
                duration = M.DURATIONS.text_popup,
            }
        end

        local traversalPopup = buildTraversalPopupData(action, result)
        if traversalPopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = traversalPopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        local commandPopup = buildCommandPopupData(action, result)
        if commandPopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = commandPopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        local quickInterruptPopup = buildQuickInterruptPopupData(action, result)
        if quickInterruptPopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = quickInterruptPopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        local twoHandedFocusPopup = buildTwoHandedFocusPopupData(action, result)
        if twoHandedFocusPopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = twoHandedFocusPopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        local proudAndAncientPopup = buildProudAndAncientPopupData(action, result)
        if proudAndAncientPopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = proudAndAncientPopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        local monsterHunterPopup = buildMonsterHunterPopupData(action, result)
        if monsterHunterPopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = monsterHunterPopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        for _, popup in ipairs(buildOrcBloodlinePopups(action, result)) do
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = popup,
                duration = M.DURATIONS.text_popup,
            }
        end

        local aidPopup = buildAidPopupData(action, result)
        if aidPopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = aidPopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        local pullItemPopup = buildPullItemPopupData(action, result)
        if pullItemPopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = pullItemPopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        local useItemPopup = buildUseItemPopupData(action, result)
        if useItemPopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = useItemPopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        local upMySleevePopup = buildUpMySleevePopupData(action, result)
        if upMySleevePopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = upMySleevePopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        local counterSpellPopup = buildCounterSpellPopupData(action, result)
        if counterSpellPopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = counterSpellPopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        local dwimmercraftPopup = buildDwimmercraftPopupData(action, result)
        if dwimmercraftPopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = dwimmercraftPopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        local guardPopup = buildGuardPopupData(action, result)
        if guardPopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = guardPopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        local preparedDefensePopup = buildPreparedDefensePopupData(action, result)
        if preparedDefensePopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = preparedDefensePopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        local facedownActionPopup = buildFacedownActionPopupData(action, result)
        if facedownActionPopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = facedownActionPopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        local testFatePopup = buildTestFatePopupData(action, result)
        if testFatePopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = testFatePopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        local bidLorePopup = buildBidLorePopupData(action, result)
        if bidLorePopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = bidLorePopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        local spellPopup = buildSpellPopupData(action, result)
        if spellPopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = spellPopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        local reloadPopup = buildReloadPopupData(action, result)
        if reloadPopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = reloadPopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        local roughhousePopup = buildRoughhousePopupData(action, result)
        if roughhousePopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = roughhousePopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        local recoverPopup = buildRecoverPopupData(action, result)
        if recoverPopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = recoverPopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        local banterPopup = buildBanterPopupData(action, result)
        if banterPopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = banterPopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        local avoidPopup = buildAvoidPopupData(action, result)
        if avoidPopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = avoidPopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        local movementPopup = buildMovementPopupData(action, result)
        if movementPopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = movementPopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        local trivialActionPopup = buildTrivialActionPopupData(action, result)
        if trivialActionPopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = trivialActionPopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        if result.ambusherDamageBonus then
            local detail = result.ambusherDamageBonus
            local actorName = action.actor and (action.actor.name or action.actor.id) or "Ambusher"
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = {
                    title = "Ambusher",
                    text = actorName .. " deals " .. tostring(detail.damageDealt or result.damageDealt or 2) .. " Wounds",
                    actor = action.actor,
                    target = action.target,
                    previousDamage = detail.previousDamage,
                    damageDealt = detail.damageDealt or result.damageDealt,
                },
                duration = M.DURATIONS.text_popup,
            }
        end

        local retreatPopup = buildRetreatPopupData(action, result)
        if retreatPopup then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = retreatPopup,
                duration = M.DURATIONS.text_popup,
            }
        end

        -- Step 2: Math overlay (show the test calculation)
        if result.testValue or result.difficulty then
            steps[#steps + 1] = {
                type = M.STEP_TYPES.MATH_OVERLAY,
                data = {
                    cardValue = result.cardValue or (action.card and action.card.value),
                    modifier = result.modifier or 0,
                    total = result.testValue,
                    difficulty = result.difficulty,
                    success = result.success,
                    isGreat = result.isGreat,
                },
            }
        end

        if result.heavyMetalMachineApplied then
            local detail = result.heavyMetalMachineApplied
            local actorName = detail.actor and (detail.actor.name or detail.actor.id) or "Heavy Metal Machine"
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = {
                    title = "Heavy Metal Machine",
                    text = actorName .. " boosts Initiative by +" .. tostring(detail.bonus or 0),
                    actor = detail.actor,
                    bonus = detail.bonus or 0,
                    baseInitiative = detail.baseInitiative,
                    value = detail.value,
                    card = detail.card,
                },
                duration = M.DURATIONS.text_popup,
            }
        end

        local aegisResults = result.aegisResults
        if (not aegisResults or #aegisResults == 0) and result.aegisResult then
            aegisResults = { result.aegisResult }
        end
        for _, detail in ipairs(aegisResults or {}) do
            local target = detail.entity or action.target
            local targetName = target and (target.name or target.id) or "Aegis bearer"
            local shieldName = detail.shield and (detail.shield.name or detail.shield.id) or "shield"
            local verb = detail.notchResult == "destroyed" and "destroys" or "Notches"
            steps[#steps + 1] = {
                type = M.STEP_TYPES.TEXT_POPUP,
                data = {
                    title = "Aegis",
                    text = targetName .. " " .. verb .. " " .. shieldName,
                    target = target,
                    shield = detail.shield,
                    notchResult = detail.notchResult,
                    destroyed = detail.notchResult == "destroyed",
                    prevented = detail.prevented == true,
                },
                duration = M.DURATIONS.text_popup,
            }
        end

        -- Step 3: Damage result (if damage was dealt)
        if result.damageDealt or result.success ~= nil then
            local visualDamageDealt = result.damageDealt or 0
            if result.aegisResult and result.aegisResult.prevented then
                visualDamageDealt = 0
            end
            steps[#steps + 1] = {
                type = M.STEP_TYPES.DAMAGE_RESULT,
                data = {
                    success = result.success,
                    damageDealt = visualDamageDealt,
                    target = action.target,
                    description = result.description,
                    isGreat = result.isGreat,
                    aegisPrevented = result.aegisResult ~= nil,
                },
            }
        end

        if #steps > 0 then
            self:push(steps)
        else
            -- No steps to show, emit complete immediately
            self:emitComplete()
        end
    end

    --- Queue a wound visualization sequence
    function sequencer:queueWoundSequence(woundData)
        local steps = {
            {
                type = M.STEP_TYPES.WOUND_WALK,
                data = {
                    entity = woundData.entity,
                    armorAbsorbed = woundData.armorAbsorbed,
                    talentAbsorbed = woundData.talentAbsorbed,
                    conditionApplied = woundData.conditionApplied,
                    finalResult = woundData.finalResult,
                },
                duration = M.DURATIONS.wound_walk,
            }
        }
        self:push(steps)
    end

    ----------------------------------------------------------------------------
    -- PLAYBACK CONTROL
    ----------------------------------------------------------------------------

    --- Start playing the next sequence in queue
    function sequencer:startNextSequence()
        if #self.sequenceQueue == 0 then
            self.playing = false
            self.currentSequence = nil
            self.currentStep = nil
            self.activeVisuals = {}
            return
        end

        self.currentSequence = table.remove(self.sequenceQueue, 1)
        self.currentStepIndex = 0
        self.playing = true

        self:advanceStep()
    end

    --- Advance to the next step in current sequence
    function sequencer:advanceStep()
        if not self.currentSequence then
            self:startNextSequence()
            return
        end

        -- Call onStepEnd for previous step
        if self.currentStep and self.onStepEnd then
            self.onStepEnd(self.currentStep)
        end

        self.currentStepIndex = self.currentStepIndex + 1

        if self.currentStepIndex > #self.currentSequence then
            -- Sequence complete
            self:completeSequence()
            return
        end

        -- Start next step
        self.currentStep = self.currentSequence[self.currentStepIndex]
        self.stepTimer = 0
        self.stepDuration = self.currentStep.duration

        -- Set up active visual
        self.activeVisuals = {
            {
                type = self.currentStep.type,
                data = self.currentStep.data,
                progress = 0,
            }
        }

        -- Call onStepStart callback
        if self.onStepStart then
            self.onStepStart(self.currentStep)
        end

        -- Emit step event for UI
        self.eventBus:emit("action_step_start", {
            step = self.currentStep,
            stepIndex = self.currentStepIndex,
            totalSteps = #self.currentSequence,
        })
    end

    --- Complete the current sequence
    function sequencer:completeSequence()
        local completedSequence = self.currentSequence

        -- Call callback
        if self.onSequenceComplete then
            self.onSequenceComplete(completedSequence)
        end

        self.currentSequence = nil
        self.currentStep = nil
        self.activeVisuals = {}

        -- Emit completion event for challenge controller
        self:emitComplete()

        -- Start next sequence if any
        self:startNextSequence()
    end

    --- Emit the UI_SEQUENCE_COMPLETE event
    function sequencer:emitComplete()
        self.eventBus:emit(events.EVENTS.UI_SEQUENCE_COMPLETE, {
            timestamp = love and love.timer.getTime() or os.time(),
        })
    end

    --- Pause playback
    function sequencer:pause()
        self.isPaused = true
    end

    --- Resume playback
    function sequencer:resume()
        self.isPaused = false
    end

    --- Skip current sequence (for impatient players)
    function sequencer:skip()
        if self.currentSequence then
            self:completeSequence()
        end
    end

    --- Clear all pending sequences
    function sequencer:clear()
        self.sequenceQueue = {}
        self.currentSequence = nil
        self.currentStep = nil
        self.currentStepIndex = 0
        self.playing = false
        self.activeVisuals = {}
    end

    ----------------------------------------------------------------------------
    -- UPDATE (call from love.update)
    ----------------------------------------------------------------------------

    --- Update the sequencer (MUST be called every frame)
    -- @param dt number: Delta time in seconds
    function sequencer:update(dt)
        if not self.playing or self.isPaused then
            return
        end

        if not self.currentStep then
            return
        end

        -- Advance timer
        self.stepTimer = self.stepTimer + dt

        -- Update progress for active visuals
        for _, visual in ipairs(self.activeVisuals) do
            if self.stepDuration > 0 then
                visual.progress = math.min(1, self.stepTimer / self.stepDuration)
            else
                visual.progress = 1
            end
        end

        -- Check if step is complete
        if self.stepTimer >= self.stepDuration then
            self:advanceStep()
        end
    end

    ----------------------------------------------------------------------------
    -- RENDERING HELPERS
    ----------------------------------------------------------------------------

    --- Get current active visuals for rendering
    -- @return table: Array of { type, data, progress }
    function sequencer:getActiveVisuals()
        return self.activeVisuals
    end

    --- Check if a specific visual type is active
    function sequencer:isVisualActive(visualType)
        for _, visual in ipairs(self.activeVisuals) do
            if visual.type == visualType then
                return true, visual
            end
        end
        return false
    end

    --- Get current step progress (0 to 1)
    function sequencer:getProgress()
        if self.stepDuration > 0 then
            return math.min(1, self.stepTimer / self.stepDuration)
        end
        return 1
    end

    ----------------------------------------------------------------------------
    -- QUERIES
    ----------------------------------------------------------------------------

    function sequencer:isPlaying()
        return self.playing == true
    end

    function sequencer:getQueueLength()
        return #self.sequenceQueue
    end

    function sequencer:getCurrentStep()
        return self.currentStep
    end

    return sequencer
end

return M
