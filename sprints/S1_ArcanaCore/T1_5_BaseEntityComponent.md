Ticket 1.5: The Base Entity Component
Goal: Define a generic Entity table structure that can represent anything capable of acting or taking damage (Adventurers, Monsters, certain Traps).
Tasks:
Create src/entities/base_entity.lua.
Implement a constructor that initializes an entity with:
id: Unique identifier.
name: Display name.
attributes: A table mapping SUITS to values (1-4 for PCs, 0-6 for NPCs).
conditions: A table for HMtW conditions (staggered, stressed, injured, death_door).
location: A reference to the current Room or Zone.
Implement a takeWound() method:
Logic: Check for open condition slots in the priority order defined in the book (Notch Armor -> Wound Talent -> Staggered -> Injured -> Death's Door).
Acceptance Criteria:
An Entity can be instantiated with custom attributes.
takeWound() correctly updates the conditions state based on available "protection" (armor/talents).
Design Notes and Pitfalls:
Junior Warning: Juniors often try to use deep inheritance (Entity -> Mob -> Goblin). Explicitly tell them to use Component Tables. An Adventurer is just an Entity that also has a Bonds table and a Resolve counter.
State Transparency: Ensure the conditions are simple booleans or bitfields so the UI can easily query them for "Red Flashing" effects later.