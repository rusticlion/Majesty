Ticket 1.1: Tarot Registry and Data Constants
Goal: Create a centralized, immutable registry of all Tarot cards (Major and Minor Arcana) to serve as the "Master List" for the game.
Tasks:
Create src/constants.lua to house enums for SUITS (SWORDS, PENTACLES, CUPS, WANDS, MAJOR) and CARD_TYPES (MINOR, MAJOR).
Create src/data/tarot_registry.lua.
Define the MinorArcana table: 56 cards (Ace-10, Page, Knight, Queen, King) for each of the 4 suits.
Add The Fool to the MinorArcana table (Value: 0, Suit: MAJOR).
Define the MajorArcana table: 21 cards (numbered I through XXI).
Each card entry must be a table: { id = string, name = string, suit = enum, value = int, type = enum }.
Acceptance Criteria:
A developer can require tarot_registry and access any card by a unique ID.
All 78 cards are accounted for with correct numeric values (Face cards = 11-14).
The code passes a basic load check without syntax errors.
Design Notes and Pitfalls:
Immutable Data: Treat this registry as read-only. Never move these specific tables; Ticket 1.2 will create instances of these cards for the decks.
Enum usage: Use numeric constants for Suits (e.g., 1, 2, 3, 4). Comparing integers is significantly faster and less error-prone than comparing strings like "Swords".