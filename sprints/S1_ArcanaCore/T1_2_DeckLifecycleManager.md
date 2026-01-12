Ticket 1.2: Deck Lifecycle Manager (DeckLib)
Goal: Implement the logic for managing two live decks: the Player's Deck (Minor + Fool) and the GM's Deck (Major).
Tasks:
Create src/logic/deck.lua.
Implement a Deck class/factory that maintains a draw_pile and a discard_pile.
Implement a shuffle() method using the Fisher-Yates algorithm.
Implement a draw() method that removes the top card from the draw_pile.
Implement logic in draw() to automatically move discard_pile to draw_pile and shuffle only if the draw pile is completely empty (Standard logic).
Implement a discard(card) method to move a card to the discard_pile.
Acceptance Criteria:
Calling draw() on an empty deck with cards in the discard pile triggers an automatic reshuffle.
Shuffling results in a non-deterministic order (verify by seeding math.random).
Major and Minor decks can exist independently.
Design Notes and Pitfalls:
The "Deep Copy" Trap: When initializing a deck from the Registry (Ticket 1.1), ensure you are copying the card data into a new table. Do not store references to the master registry, or modifying a "Notched" card state later will affect all instances of that card.
Randomness: Lua's math.random requires a seed. Call math.randomseed(os.time()) once in the init function of the manager.