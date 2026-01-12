Ticket 1.7: The Slot-Based Inventory Manager
Goal: Implement the "Belt vs. Pack" inventory system, handling slot limits and "Notch" tracking for items.
Tasks:
Create src/logic/inventory.lua.
Define constants for SLOTS: BELT = 4, PACK = 21, HANDS = 2.
Implement a Container structure that entities can hold.
Implement addItem(item, target_location):
Verify available slots (Items take 1, 2, or "Oversized" slots).
"Oversized" items must check if they can fit on the Belt.
Implement addNotch(item): Increment notches. If notches >= durability, set is_destroyed = true.
Implement swap(item_id, from_loc, to_loc): Moves items between Hands/Belt/Pack (Crucial for Challenge Phase actions).
Acceptance Criteria:
Attempting to add an item to a full Pack returns a failure/error.
Armor correctly occupies Belt slots while "worn."
The system distinguishes between "Hands" (active) and "Belt/Pack" (stored).
Design Notes and Pitfalls:
Item Uniqueness: Every item needs a unique instance ID. If I have two "Torches," Notching one should not affect the other.
The "Hands" Logic: In HMtW, you have two hands. A lantern takes one, a shield takes one, a two-handed sword takes both. The logic must strictly enforce the HANDS limit of 2.