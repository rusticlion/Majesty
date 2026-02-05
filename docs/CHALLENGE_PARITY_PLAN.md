# Challenge Parity Plan (Rulebook Chapter 7)

This plan is anchored to `rulebook/CoreRules.txt` (Challenge flow and actions, pp. 107-126).

## Design Decisions

- Minor actions are resolved in declaration order by intent.
- We are not implementing true simultaneous minor-resolution logic.
- Rationale: declaration-order adds tactical depth and avoids high-complexity adjudication code with low gameplay upside.

## Current Parity Snapshot

### Challenge Procedure

| Rulebook area | Status | Notes | Code |
| --- | --- | --- | --- |
| 0. Set the scene (zones, hazards, position) | Partial | Zones are supported; ambush/surprise/special-scene-rules are mostly GM/manual. | `src/logic/challenge_controller.lua`, `src/world/zone_system.lua` |
| 1. Draw Challenge cards | Partial | Player draw loop exists; GM draw formula parity is not implemented. | `src/logic/npc_ai.lua` |
| 2. Play Initiative | Partial | Initiative workflow exists; enemy grouping/significant-enemy initiative still simplified. | `src/logic/challenge_controller.lua`, `src/logic/npc_ai.lua` |
| 3. Take turns (count-up) | Mostly done | Core count-up and action resolution loop is in place. | `src/logic/challenge_controller.lua` |
| 4. Minor actions | Done (intentional variant) | Declaration window + declaration-order processing is implemented and retained by design. | `src/logic/challenge_controller.lua` |
| 5. End round | Partial | Round loop works; some discard/deck-procedure nuances and GM-side parity remain. | `src/logic/challenge_controller.lua`, `src/logic/npc_ai.lua` |
| GM lesser/greater doom use | Partial / mismatch risk | Current AI comments/logic currently invert lesser/greater labels versus rulebook nomenclature. | `src/logic/npc_ai.lua:35` |

### Challenge Actions

| Action (Rulebook) | Status | Notes | Code |
| --- | --- | --- | --- |
| Attack (Melee/Missile) | Mostly done | Core contest/damage/engagement behavior implemented. | `src/logic/action_resolver.lua` |
| Riposte | Mostly done | Prepared defense + counter resolution in place. | `src/logic/action_resolver.lua` |
| Avoid | Mostly done | Engagement escape and penalties implemented. | `src/logic/action_resolver.lua` |
| Dash | Partial | Uses move pipeline; zone-distance/adjacency semantics need stricter parity handling. | `src/logic/action_resolver.lua`, `src/controllers/challenge_input_controller.lua` |
| Dodge | Mostly done | Prepared defense logic in place. | `src/logic/action_resolver.lua` |
| Roughhouse | Partial | Implemented as split actions (`trip`, `disarm`, `displace`, `grapple`) instead of one roughhouse choice flow. | `src/data/action_registry.lua`, `src/logic/action_resolver.lua` |
| Aid Another | Mostly done | Bonus banking works; trigger specificity can be expanded. | `src/logic/action_resolver.lua` |
| Command | Partial | Contest exists, but no robust companion behavior/command repertoire pipeline. | `src/logic/action_resolver.lua` |
| Pull Item from Pack/Belt | Partial | Generic success text exists; inventory swap details are thin. | `src/logic/action_resolver.lua` |
| Use Item | Partial | Generic success path; item-specific challenge effects not modeled deeply. | `src/logic/action_resolver.lua` |
| Banter | Partial+ | Morale/disposition hooks exist; likes/dislikes and full social outcomes are still shallow. | `src/logic/action_resolver.lua`, `src/logic/disposition.lua` |
| Speak Incantation | Missing/placeholder | Contest shell exists; no spell registry/component/talent-driven effect system. | `src/logic/action_resolver.lua` |
| Recover | Mostly done | Core recoverable-condition clearing implemented. | `src/logic/action_resolver.lua` |
| Bid Lore | Partial | Surface action exists; full lore-bid adjudication loop is not integrated in Challenge flow. | `src/logic/action_resolver.lua` |
| Guard | Mostly done | Initiative replacement with shield gate implemented. | `src/logic/action_resolver.lua` |
| Move | Partial | Movement works but adjacency/obstacle rigor still needs parity tightening. | `src/logic/action_resolver.lua`, `src/controllers/challenge_input_controller.lua` |
| Reload Crossbow | Mostly done | Present and gated; edge cases still need tests. | `src/data/action_registry.lua`, `src/logic/action_resolver.lua` |
| Test Fate | Partial | Mid-challenge flow exists for flagged actions; broader GM-called/interactive use is limited. | `src/logic/action_resolver.lua`, `main.lua` |
| Trivial Action | Basic | Implemented as generic success path. | `src/logic/action_resolver.lua` |
| Vigilance | Mostly done (v1) | Triggered follow-up execution is wired; current UX defaults trigger to hostile actions targeting the vigilant actor. | `src/logic/action_resolver.lua`, `src/logic/challenge_controller.lua`, `src/controllers/challenge_input_controller.lua` |

## Execution Plan

### Phase 1: Core Timing and GM Parity

1. Keep declaration-order minor actions as the project standard.
2. Implement a usable Vigilance trigger engine.
3. Correct GM doom terminology/behavior and implement draw formula parity.
4. Add strict zone adjacency and movement-rule checks for Move/Dash/Avoid.

Definition of done:
- Vigilance can trigger and execute follow-up actions in live Challenges.
- GM round draw count and doom usage follow rulebook math.
- Movement rules cannot skip non-adjacent zones unless allowed by explicit action/effect.

### Phase 2: Action Depth

1. Expand Command into concrete companion action handling.
2. Expand Use Item / Pull Item from Pack/Belt into real inventory interactions.
3. Upgrade Bid Lore challenge-side handling.
4. Decide on Roughhouse UX (single action with effect choice vs current split actions) and align registry/resolver.

Definition of done:
- Non-attack actions materially change state beyond generic success text.

### Phase 3: Spellcasting and Social Completion

1. Add spell registry and spell effect resolver pipeline.
2. Enforce component + training/talent requirements for Speak Incantation.
3. Deepen Banter with stronger like/dislike and disposition consequences.
4. Extend NPC AI to use expanded action surface (social/spell/item actions).

Definition of done:
- Spellcasting and social conflict are first-class systems, not placeholders.

## Immediate Next Implementations

1. GM draw/doom parity fix (Phase 1, item 3).
2. Movement adjacency enforcement (Phase 1, item 4).
3. Vigilance UX expansion (optional): custom trigger templates beyond hostile-targeting default.
