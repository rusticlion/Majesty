-- events.lua
-- Simple Event System for Majesty
-- Provides loose coupling between systems (e.g., WatchManager fires events,
-- Light/Inventory systems listen)

local M = {}

--------------------------------------------------------------------------------
-- EVENT TYPES
--------------------------------------------------------------------------------
M.EVENTS = {
    -- Watch & Time
    WATCH_PASSED      = "watch_passed",
    TORCHES_GUTTER    = "torches_gutter",

    -- Meatgrinder Results
    MEATGRINDER_ROLL  = "meatgrinder_roll",
    CURIOSITY         = "curiosity",
    TRAVEL_EVENT      = "travel_event",
    RANDOM_ENCOUNTER  = "random_encounter",
    QUEST_RUMOR       = "quest_rumor",

    -- Movement
    PARTY_MOVED       = "party_moved",
    ROOM_ENTERED      = "room_entered",

    -- Combat/Challenge
    CHALLENGE_START       = "challenge_start",
    CHALLENGE_END         = "challenge_end",
    CHALLENGE_ROUND_END   = "challenge_round_end",
    CHALLENGE_TURN_START  = "challenge_turn_start",
    CHALLENGE_TURN_END    = "challenge_turn_end",
    CHALLENGE_ACTION      = "challenge_action",
    CHALLENGE_RESOLUTION  = "challenge_resolution",
    CHALLENGE_CARD_DISCARDED = "challenge_card_discarded",
    MALEDICTION_CHICKEN_DOOM = "malediction_chicken_doom",
    MALEDICTION_CHICKEN_CLEARED = "malediction_chicken_cleared",
    INITIATIVE_REVEALED   = "initiative_revealed",
    MINOR_ACTION_WINDOW   = "minor_action_window",
    MINOR_ACTION_USED     = "minor_action_used",
    UI_SEQUENCE_COMPLETE  = "ui_sequence_complete",

    -- Wound/Damage
    WOUND_TAKEN           = "wound_taken",
    WOUND_HEALED          = "wound_healed",
    ENTITY_DEFEATED       = "entity_defeated",
    UNDEAD_RAISED         = "undead_raised",
    ARMOR_NOTCHED         = "armor_notched",
    TALENT_WOUNDED        = "talent_wounded",
    CONDITION_EXPIRED     = "condition_expired",

    -- Phase Changes
    PHASE_CHANGED     = "phase_changed",
    CITY_DEATH_AND_TAXES_RESOLVED = "city_death_and_taxes_resolved",
    CITY_NOTEWORTHY_DEEDS_RESOLVED = "city_noteworthy_deeds_resolved",
    CITY_EVENT_RESOLVED = "city_event_resolved",
    CITY_CONTRACTS_TURNED_IN = "city_contracts_turned_in",
    CITY_TREASURE_SOLD = "city_treasure_sold",
    CITY_UPKEEP_RESOLVED = "city_upkeep_resolved",
    CITY_UPKEEP_RECOVERY_BOND_SPENT = "city_upkeep_recovery_bond_spent",
    CITY_ACTION_RESOLVED = "city_action_resolved",
    CITY_NEXT_CRAWL_PLANNED = "city_next_crawl_planned",
    CITY_UNDERWORLD_RESTOCKED = "city_underworld_restocked",
    CITY_PHASE_ENDED = "city_phase_ended",

    -- Zones (T2_3)
    ZONE_CHANGED        = "zone_changed",
    ENTITIES_ENGAGED    = "entities_engaged",
    ENTITIES_DISENGAGED = "entities_disengaged",
    ENGAGEMENT_CHANGED  = "engagement_changed",  -- S12.1: Full engagement state update for UI
    PARTING_BLOW        = "parting_blow",

    -- Room Features (T2_5)
    FEATURE_STATE_CHANGED = "feature_state_changed",
    FEATURE_UPDATED       = "feature_updated",  -- S11.3: arbitrary feature updates
    ROOM_SOCIAL_ENCOUNTER_RESOLVED = "room_social_encounter_resolved",
    ROOM_SOCIAL_FEATURE_RESOLVED = "room_social_feature_resolved",

    -- Interaction (T2_6)
    INTERACTION = "interaction",

    -- Item Use (S11.3+)
    USE_ITEM_ON_POI   = "use_item_on_poi",   -- Drag item from equipment onto POI

    -- POI Info-Gating (T2_8)
    POI_DISCOVERED      = "poi_discovered",
    SCRUTINY_TIME_COST  = "scrutiny_time_cost",

    -- Investigation Bridge (T2_9)
    INVESTIGATION_COMPLETE = "investigation_complete",
    TRAP_TRIGGERED         = "trap_triggered",

    -- Item Interaction (T2_10)
    TRAP_DETECTED         = "trap_detected",
    ITEM_DAMAGE_ABSORBED  = "item_damage_absorbed",

    -- Light System
    LANTERN_BROKEN        = "lantern_broken",
    ENTITY_LIGHT_CHANGED  = "entity_light_changed",
    PARTY_LIGHT_CHANGED   = "light_level_changed",
    LIGHT_FLICKERED       = "light_flickered",
    LIGHT_DESTROYED       = "light_destroyed",
    LIGHT_EXTINGUISHED    = "light_extinguished",
    DARKNESS_FELL         = "darkness_fell",
    DARKNESS_LIFTED       = "darkness_lifted",
    LIGHT_SOURCE_TOGGLED  = "light_source_toggled",
    LIGHT_SOURCE_DROPPED  = "light_source_dropped",
    DARKNESS_DOOMED       = "darkness_doomed",

    -- Inventory
    INVENTORY_CHANGED     = "inventory_changed",

    -- Active PC
    ACTIVE_PC_CHANGED     = "active_pc_changed",

    -- UI Input (T2_11)
    DRAG_BEGIN       = "drag_begin",
    DRAG_CANCELLED   = "drag_cancelled",
    DROP_ON_TARGET   = "drop_on_target",
    POI_CLICKED      = "poi_clicked",
    POI_ACTION_SELECTED = "poi_action_selected",
    BUTTON_CLICKED   = "button_clicked",
    ARENA_ENTITY_CLICKED = "arena_entity_clicked",
    ARENA_ZONE_CLICKED   = "arena_zone_clicked",

    -- Focus Menu (T2_13)
    SCRUTINY_SELECTED = "scrutiny_selected",
    MENU_OPENED       = "menu_opened",
    MENU_CLOSED       = "menu_closed",

    -- S12.5: Test of Fate
    REQUEST_TEST_OF_FATE  = "request_test_of_fate",
    TEST_OF_FATE_COMPLETE = "test_of_fate_complete",
    TEST_FATE_PUSHED      = "test_fate_pushed",

    -- Bid Lore (Challenge async action)
    REQUEST_BID_LORE      = "request_bid_lore",
    BID_LORE_COMPLETE     = "bid_lore_complete",
    BID_LORE_VERDICT      = "bid_lore_verdict",

    -- Sorcery
    SPELL_CAST                    = "spell_cast",
    SPELL_ENDED                   = "spell_ended",
    CONCENTRATION_TEST_REQUIRED   = "concentration_test_required",
    CONCENTRATION_TEST_RESOLVED   = "concentration_test_resolved",
    MALEFICENCE_TRIGGERED         = "maleficence_triggered",
    MALEFICENCE_RESOLVED          = "maleficence_resolved",
    SEALED_PACT_CREATED           = "sealed_pact_created",
    SEALED_PACT_VIOLATED          = "sealed_pact_violated",
    SEALED_PACT_DISPELLED         = "sealed_pact_dispelled",

    -- Alchemy
    ALCHEMY_REAGENT_HARVESTED = "alchemy_reagent_harvested",
    ALCHEMY_REAGENT_PURCHASED = "alchemy_reagent_purchased",
    ALCHEMY_REAGENT_SOLD      = "alchemy_reagent_sold",

    -- Bound by Fate (Crawl UI)
    BOUND_BY_FATE_BLOCKED = "bound_by_fate_blocked",
}

--------------------------------------------------------------------------------
-- EVENT BUS FACTORY
--------------------------------------------------------------------------------

--- Create a new EventBus
-- @return EventBus instance
function M.createEventBus()
    local bus = {
        listeners = {},  -- event_type -> { callback1, callback2, ... }
        history   = {},  -- Recent events for debugging
    }

    ----------------------------------------------------------------------------
    -- SUBSCRIBE
    ----------------------------------------------------------------------------

    --- Subscribe to an event
    -- @param eventType string: One of EVENTS constants
    -- @param callback function: Called with (eventData) when event fires
    -- @return function: Unsubscribe function
    function bus:on(eventType, callback)
        if not self.listeners[eventType] then
            self.listeners[eventType] = {}
        end

        local entry = {
            callback = callback,
            active = true,
        }

        self.listeners[eventType][#self.listeners[eventType] + 1] = entry

        -- Return unsubscribe function
        return function()
            if not entry.active then
                return
            end

            entry.active = false
            local listeners = self.listeners[eventType]
            if not listeners then
                return
            end

            for i, cb in ipairs(listeners) do
                if cb == entry then
                    table.remove(listeners, i)
                    break
                end
            end
        end
    end

    --- Subscribe to an event (fires only once)
    function bus:once(eventType, callback)
        local unsubscribe
        unsubscribe = self:on(eventType, function(data)
            unsubscribe()
            callback(data)
        end)
        return unsubscribe
    end

    ----------------------------------------------------------------------------
    -- EMIT
    ----------------------------------------------------------------------------

    --- Emit an event to all listeners
    -- @param eventType string: One of EVENTS constants
    -- @param data table: Event-specific data
    function bus:emit(eventType, data)
        data = data or {}
        data.eventType = eventType
        data.timestamp = os.time()

        -- Record in history (keep last 50)
        self.history[#self.history + 1] = data
        if #self.history > 50 then
            table.remove(self.history, 1)
        end

        -- Notify listeners. Iterate over a snapshot so unsubscribe/clear during
        -- an emit cannot shift the live array and skip later subscribers.
        local listeners = self.listeners[eventType]
        if listeners then
            local snapshot = {}
            for i, entry in ipairs(listeners) do
                snapshot[i] = entry
            end

            for _, entry in ipairs(snapshot) do
                if entry.active then
                    entry.callback(data)
                end
            end
        end
    end

    ----------------------------------------------------------------------------
    -- UTILITY
    ----------------------------------------------------------------------------

    --- Get listener count for an event
    function bus:listenerCount(eventType)
        local listeners = self.listeners[eventType]
        if not listeners then
            return 0
        end

        local count = 0
        for _, entry in ipairs(listeners) do
            if entry.active then
                count = count + 1
            end
        end
        return count
    end

    --- Clear all listeners for an event (useful for testing)
    function bus:clear(eventType)
        if eventType then
            for _, entry in ipairs(self.listeners[eventType] or {}) do
                entry.active = false
            end
            self.listeners[eventType] = {}
        else
            for _, listeners in pairs(self.listeners) do
                for _, entry in ipairs(listeners) do
                    entry.active = false
                end
            end
            self.listeners = {}
        end
    end

    --- Get recent event history
    function bus:getHistory()
        return self.history
    end

    return bus
end

--------------------------------------------------------------------------------
-- GLOBAL EVENT BUS (singleton for convenience)
--------------------------------------------------------------------------------
M.globalBus = M.createEventBus()

return M
