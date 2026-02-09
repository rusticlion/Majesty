# Bid Lore VTT Subsystem PRD

Status: Draft v1  
Owner: Gameplay Systems  
Date: 2026-02-05  
Scope: Challenge-phase `Bid Lore` action for solo/GM-less VTT play.

## 1. Problem Statement

`Bid Lore` is currently a placeholder in challenge resolution (`src/logic/action_resolver.lua:1941`), so players can spend a card but do not get a rules-faithful lore adjudication loop.

Tabletop `Bid Lore` assumes a human GM can interpret motifs and answer open-ended questions. In this prototype, we need deterministic, fast, and transparent adjudication without a human referee.

## 2. Rulebook Source of Truth

This subsystem must preserve the following rules intent:

| Rule intent | Source |
| --- | --- |
| A lore bid is asking “Would my adventurer know this?” via motifs. | `rulebook/CoreRules.txt:1773` |
| Questions must be discrete (not broad/vague). | `rulebook/CoreRules.txt:1774` |
| GM-style outcomes are: yes + detailed answer, no (no spend), or rephrase/reframe. | `rulebook/CoreRules.txt:1788` |
| A lore bid use is spent only when an answer is given. | `rulebook/CoreRules.txt:1792`, `rulebook/CoreRules.txt:1795` |
| In Challenge, bidding lore still costs an action card whether accepted or rejected. | `rulebook/CoreRules.txt:5182`, `rulebook/CoreRules.txt:5188` |
| Obvious knowledge should be given freely; obscure knowledge is gated behind lore bids. | `rulebook/CoreRules.txt:7930`, `rulebook/CoreRules.txt:7938` |
| Accepted lore should be thorough (“keep talking until you run out of material”). | `rulebook/CoreRules.txt:7946` |
| Camp refills lore bids to 4. | `rulebook/CoreRules.txt:6082` |
| Lore bid is one question at a time. | `rulebook/Appendices.txt:1291` |

## 3. Product Goals

1. Deliver a complete `Bid Lore` action loop in Challenge with no human adjudicator.
2. Keep action economy and lore economy faithful to rules above.
3. Make adjudication explainable to players (why accepted/rejected/rephrase).
4. Return useful, tactical, subject-specific answers quickly (single modal interaction).
5. Support authored lore from the sourcebook and dungeon content in repo.

## 4. Non-Goals (v1)

1. Fully open-ended natural-language GM simulation.
2. Dynamic AI-generated lore text.
3. Full talent exception coverage on day one (e.g., all path-specific lore overrides).
4. Crawl-phase freeform lore questioning outside Challenge action flow.

## 5. VTT Adaptation Principles

1. Constrain question input to structured templates so questions are always discrete.
2. Require explicit subject selection to remove ambiguity.
3. Use deterministic motif-to-domain matching instead of freeform human judgment.
4. Use authored answer content only (rulebook/map/monster data), not unconstrained generation.
5. Preserve “rephrase” as a first-class outcome before hard rejection.

## 6. User Experience Spec

### 6.1 Primary Flow (Challenge Turn)

1. Player selects a card and clicks `Bid Lore` on command board.
2. Card is spent as normal challenge action.
3. `Bid Lore Modal` opens with:
   - Subject selector.
   - Question type selector (template-based).
   - Optional refinement tokens.
   - Motif selector (one motif, default required in v1).
4. Player submits.
5. System adjudicates with one of:
   - `accepted`: show detailed answer and spend 1 lore bid use.
   - `rephrase`: explain why too broad/misaligned and offer constrained alternatives (no lore spend).
   - `rejected`: explicit motif/subject mismatch (no lore spend).
6. Action resolves and returns to normal challenge flow.

### 6.2 Modal Inputs (v1)

| Field | Requirement | Notes |
| --- | --- | --- |
| `subjectId` | Required | Chosen from in-scope knowledge subjects. |
| `questionType` | Required | Enum keeps questions discrete. |
| `motif` | Required | Selected from acting PC motifs. |
| `focus` | Optional | Short token/phrase to narrow intent. |

### 6.3 Question Type Catalog (v1)

1. `vulnerability` (weaknesses, counters)
2. `behavior` (habits, tactics, tells)
3. `taboo_or_trigger` (what provokes/placates)
4. `identity_or_origin` (what this thing/place is)
5. `environmental_risk` (hazard implications)
6. `social_preference` (likes/dislikes where authored)
7. `alchemy_effect` (where authored)

## 7. Adjudication Spec

### 7.1 Outcome Model

`verdict` is one of:

1. `accepted`
2. `rephrase_needed`
3. `rejected_unknown_with_motif`
4. `rejected_subject_unavailable`

### 7.2 Deterministic Relevance Scoring

Compute relevance score from three tag sets:

1. `motifTags` from motif parser/map.
2. `subjectTags` from lore subject.
3. `questionTags` from question type.

Score formula (v1):

`score = overlap(motifTags, subjectTags) + overlap(motifTags, questionTags) + contextBonus`

Decision thresholds:

1. `score >= 2`: `accepted` (if answer data exists).
2. `score == 1`: `rephrase_needed`.
3. `score == 0`: `rejected_unknown_with_motif`.

Data availability override:

1. If no authored answer for `(subjectId, questionType)`, return `rephrase_needed` with suggested nearest valid question types.

### 7.3 Lore Spend Rules

1. Card/action cost is always paid for challenge `Bid Lore`.
2. `loreBids` decreases only on `accepted`.
3. `rephrase_needed` does not spend lore bid.
4. `rejected*` does not spend lore bid.

This preserves `CoreRules` action-cost and lore-use semantics.

### 7.4 Answer Thoroughness Rules

On `accepted`, answer payload must include:

1. `summary` (single clear claim)
2. `details` (2-5 concrete facts)
3. `implication` (how this can influence play now)
4. `sourceRefs` (internal lore record ids for debugging)

## 8. Content/Data Model

### 8.1 New Data Files

1. `src/data/lore/lore_subjects.lua`
2. `src/data/lore/question_types.lua`
3. `src/data/lore/motif_tag_map.lua`

### 8.2 `lore_subjects.lua` Schema

```lua
{
  id = "monster_fire_drake",
  kind = "monster", -- monster|npc|location|hazard|item|faction
  name = "Fire Drake",
  tags = {"dragon", "fire", "underworld_predator"},
  answers = {
    vulnerability = {
      summary = "...",
      details = {"...", "..."},
      implication = "...",
    },
    behavior = { ... },
  },
}
```

### 8.3 `motif_tag_map.lua` Schema

```lua
{
  ["dragon hunter"] = {"dragon", "monster_lore", "hunting"},
  ["bookish"] = {"scholarly", "history", "occult"},
  ["former burglar"] = {"locks", "security", "urban_underworld"},
}
```

Fallback behavior:

1. If exact motif key misses, tokenize motif words and map via keyword dictionary.
2. If still empty, `motifTags = {}`.

## 9. Architecture and Integration

### 9.1 New Runtime Modules

1. `src/logic/bid_lore_engine.lua`
2. `src/ui/bid_lore_modal.lua`

### 9.2 Event Additions

Add to `src/logic/events.lua`:

1. `REQUEST_BID_LORE`
2. `BID_LORE_COMPLETE`
3. `BID_LORE_VERDICT` (optional analytics/debug stream)

### 9.3 Action Resolver Contract Changes

In `src/logic/action_resolver.lua`:

1. Replace placeholder in `resolveGenericAction` for `BID_LORE` with async request path.
2. Emit `REQUEST_BID_LORE` payload containing actor, action context, and available subjects.
3. Return `pendingBidLore = true` in result to gate challenge continuation (same pattern as Test of Fate).
4. Add `resolveBidLoreOutcome(action, bidLoreResult)` to finalize description/effects and lore spend.

### 9.4 Bootstrap Wiring

In `src/app/bootstrap.lua`:

1. Instantiate/init `bidLoreModal` similar to `testOfFateModal`.
2. Track `gameState.pendingLoreAction`.
3. In `CHALLENGE_ACTION` handler:
   - if resolver returns `pendingBidLore`, stash action and wait.
4. On `BID_LORE_COMPLETE`:
   - finalize via resolver helper
   - call `challengeController:resolveAction(action)`

### 9.5 Input Routing Priority

In `src/controllers/key_input_router.lua` and `src/controllers/mouse_input_router.lua`:

1. `bidLoreModal` gets modal-first priority equal to `testOfFateModal`.

## 10. Rules Parity Matrix (VTT Interpretation)

| Tabletop rule | VTT interpretation |
| --- | --- |
| Ask any lore question if motif is pertinent. | Ask via template + explicit subject + motif selection. |
| GM judges fair game and can request rephrase. | Deterministic scorer returns `accepted/rephrase/rejected` with reason string. |
| GM gives thorough answer on accepted bid. | Return authored `summary + details + implication`. |
| In Challenge, card is spent regardless of accept/reject. | No change to card discard flow. |
| Lore bid uses spent only when answered. | Spend only on `accepted`. |

## 11. Edge Cases

1. `loreBids <= 0`:
   - `Bid Lore` disabled in command board with reason `No lore bids remaining`.
2. Subject not in current context:
   - hide from selector or reject as `subject_unavailable`.
3. No authored answer:
   - return `rephrase_needed` and suggest supported question types for that subject.
4. Multiple motifs appear relevant:
   - player chooses one motif in v1 for deterministic auditability.
5. Talent exceptions:
   - v1 defer; keep extension hooks in engine.

## 12. Telemetry and Debugging

Emit debug event payload:

1. actor id/name
2. motif selected
3. subject/question selected
4. score breakdown
5. verdict
6. lore spend applied

This enables rapid balancing of motif/tag mappings.

## 13. Test Plan

### 13.1 Unit Tests (engine)

1. Accept path spends lore once.
2. Rephrase path spends zero lore.
3. Reject path spends zero lore.
4. Score thresholds map to expected verdicts.
5. Missing answer data returns rephrase with suggestions.

### 13.2 Integration Tests (challenge flow)

1. Challenge action pauses on `pendingBidLore`.
2. Modal completion resumes `challengeController:resolveAction`.
3. Card is always discarded for Bid Lore action.
4. `loreBids` decrements only on accepted outcomes.
5. Input routers block underlying gameplay while modal open.

## 14. Implementation Plan

Phase A: Vertical Slice

1. Add engine module with static in-memory subject/question sample.
2. Add modal with subject + question type + motif selection.
3. Wire async action flow and lore spend logic.

Phase B: Content Expansion

1. Build initial lore subject catalog from current map and enemy blueprints.
2. Add motif tag map for starter guild motifs in `main.lua`.
3. Add richer answer details and implication text.

Phase C: Exceptions and Depth

1. Add talent-based overrides (free follow-up, no-motif fallback, resolve-substitute).
2. Add context-aware subject filtering (room/faction/encounter).
3. Add QA pass for answer quality and parity.

## 15. Acceptance Criteria (Definition of Done)

1. `Bid Lore` is no longer generic placeholder text.
2. Challenge-turn `Bid Lore` opens modal, adjudicates deterministically, and resumes flow.
3. Rules parity for action cost vs lore-spend semantics is enforced.
4. Players receive actionable, authored answers on accepted bids.
5. System includes logging to tune motif-tag and subject-tag matching.

## 16. Open Decisions

1. Should v1 allow `Bid Lore` without motif selection (strict rules mode says no, except talent overrides)?
2. Should `rephrase_needed` allow unlimited retries inside one action, or cap retries at 1-2 prompts?
3. Should unknown/no-authored-data subjects fail as `rephrase_needed` (current spec) or hard `rejected`?
4. Should we expose score internals to players, or keep them as debug-only telemetry?

## 17. Immediate Follow-Through Back to Action Plumbing

1. Implement Phase A vertical slice first.
2. Then return to action-plumbing backlog items in `docs/CHALLENGE_PARITY_PLAN.md` Phase 2 (`Command`, `Use/Pull Item`, `Roughhouse` alignment), using this Bid Lore flow as the async-action template.
