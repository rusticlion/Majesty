Ticket 1.3: Game State and Round Manager
Goal: Implement a global state controller to track the current Phase (Crawl, Challenge, etc.) and handle the "End of Round" triggers, specifically for Tarot reshuffling.
Tasks:
Create src/logic/game_clock.lua.
Define a state variable for currentPhase.
Implement a pendingReshuffle boolean flag.
Create an onCardDrawn(card) listener: If card.id == "the_fool", set pendingReshuffle = true.
Implement endRound(): If pendingReshuffle is true, call shuffle() on both Player and GM decks, then reset the flag to false.
Acceptance Criteria:
Drawing The Fool sets the pendingReshuffle flag.
The decks do not shuffle immediately upon drawing the Fool.
Calling endRound() triggers the dual-deck shuffle if the flag is set.
Design Notes and Pitfalls:
Centralization: Do not put the reshuffle logic inside the Deck class. The Deck shouldn't know about "Rounds." The GameClock acts as the conductor, telling the Decks what to do based on the rules of His Majesty the Worm.
The Fool's Value: Remember the Fool has a value of 0. Ensure the onCardDrawn logic doesn't interfere with the numeric resolution of a Test of Fate.