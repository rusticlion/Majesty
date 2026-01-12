Ticket 1.6: The Adventurer Schema (PC Specialization)
Goal: Extend the Entity logic to include player-specific systems: Resolve, Motifs, and Bonds.
Tasks:
Create src/entities/adventurer.lua.
Add a resolve component: current (default 4), max (default 4).
Add a motifs list: A collection of strings (e.g., "Drunken Knight").
Add a bonds table: Maps entity_id to a relationship status and a is_charged boolean.
Add a talents table: Maps talent_id to { mastered = bool, xp_invested = int }.
Implement spendResolve(amount): Error handle if current < amount.
Acceptance Criteria:
Data structure supports the "Failed Career" and "Origin" motifs from Session 0.
Bonds can be "charged" and "spent" (logic only).
Design Notes and Pitfalls:
String IDs for Talents: Do not hardcode talent logic here. Just store the ID. The ChallengeManager in a later sprint will look up what the "Aegis" talent actually does.
The Resolve Cap: While the book says max 4, the "War Stories" talent (p. 71) allows Resolve to go up to 5. Ensure the max value is mutable, not a constant.