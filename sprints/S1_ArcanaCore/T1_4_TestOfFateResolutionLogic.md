Ticket 1.4: Test of Fate Resolution Logic
Goal: Create a standalone logic module to resolve "Tests of Fate" and "Pushing Fate."
Tasks:
Create src/logic/resolver.lua.
Implement resolveTest(attribute, targetSuit, initialCard):
Total = initialCard.value + attribute.
Check for Great Success: Total >= 14 AND initialCard.suit == targetSuit.
Implement resolvePush(currentTotal, secondCard):
If secondCard.id == "the_fool", return Great Failure.
If newTotal < 14, return Great Failure.
Else, return Success.
Acceptance Criteria:
A "Result Object" is returned containing: { success = bool, isGreat = bool, total = int, cards = {} }.
The logic correctly identifies that a "Push" can never result in a "Great Success" (as per page 9).
Design Notes and Pitfalls:
Statelessness: This module should be a "Pure Function" library. It shouldn't know about the Deck or Player. It just takes numbers and cards and returns a result. This makes it incredibly easy to unit test.
The "Face Card" Gotcha: Ensure the values 11, 12, 13, and 14 are being used for Page, Knight, Queen, and King. Junior devs often accidentally use 10 for all face cards.