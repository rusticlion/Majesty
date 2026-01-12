Ticket 1.8: Entity Factory (The Spawner)
Goal: Create a centralized factory to generate fully-initialized Entity objects using data-driven "Blueprints."
Tasks:
Create src/entities/factory.lua.
Create a folder src/data/blueprints/ and a file mobs.lua.
Define template tables for common entities (e.g., skeleton_brute, goblin_minion).
Template should include: base attributes, default conditions, and a list of starting_gear.
Implement factory.createEntity(template_id):
Initialize the BaseEntity.
Attach a Container (Inventory) from Ticket 1.7.
Instantiate starting_gear from the Registry and place it in the Container.
Implement factory.createAdventurer(pc_data):
Specialized version that also attaches Resolve, Bonds, and Motifs.
Acceptance Criteria:
Calling factory.createEntity("skeleton_brute") returns a fully functional entity with a sword in its hand and attributes set to 6/1/1/4.
The factory correctly distinguishes between an NPC Mob and a PC Adventurer.
Design Notes and Pitfalls:
Data-Driven, Not Code-Driven: Do not write a function createSkeleton(). Write a generic createEntity(id) function that looks up id in a data table. This allows us to add 100 new monsters later just by editing a text file, without touching the logic.
Dependency Injection: The factory needs to know about the Registry (to find items) and the Inventory module. Ensure these are required at the top of the file.