-- camp_prompts.lua
-- Campfire Discussion Prompts for Majesty
-- Ticket S9.3: Fellowship roleplay prompts
--
-- Reference: Rulebook pg. 189 "Campfire Discussions"
-- These prompts encourage character development and party bonding.

local M = {}

--------------------------------------------------------------------------------
-- DISCUSSION PROMPTS
-- Each prompt is a question to spark roleplay between characters
--------------------------------------------------------------------------------

M.PROMPTS = {
    -- Personal History
    "What is your earliest memory?",
    "What is your greatest achievement?",
    "What is your deepest regret?",
    "Where did you grow up, and what was it like?",
    "Who taught you your trade or skills?",
    "What drove you to become an adventurer?",
    "Have you ever been in love?",
    "What is the worst thing you've ever done?",
    "What is the kindest thing anyone has ever done for you?",
    "What do you miss most about home?",

    -- Dreams and Fears
    "What do you dream of at night?",
    "What is your greatest fear?",
    "If you could change one thing about your past, what would it be?",
    "What would you do if you found a fortune in the dungeon?",
    "How do you want to be remembered?",
    "What keeps you going when things seem hopeless?",
    "What would make you abandon the guild?",
    "What do you think happens after death?",
    "Is there anyone you would die for?",
    "What scares you more: dying alone, or dying forgotten?",

    -- Beliefs and Values
    "Do you believe in the gods? Which ones?",
    "What is the most important virtue a person can have?",
    "Is there such a thing as a justified lie?",
    "When is violence the right answer?",
    "What do you think of the Crown and its laws?",
    "Is there honor among thieves?",
    "Would you sacrifice one life to save many?",
    "What do you think of magic and those who wield it?",
    "Is revenge ever justified?",
    "What makes someone truly evil?",

    -- Relationships
    "What do you think of the others in our guild?",
    "Who do you trust most in this group?",
    "Have you ever betrayed someone's trust?",
    "What would you never forgive?",
    "Do you have any living family?",
    "Who was your best friend growing up?",
    "Have you ever lost someone close to you?",
    "What makes a true friend?",
    "Is there anyone from your past you wish you could see again?",
    "Who is your greatest enemy?",

    -- The Dungeon
    "What is the strangest thing you've seen in the Underworld?",
    "Do you think we'll ever find what we're looking for down here?",
    "What do you think created these dungeons?",
    "Have you ever felt pity for a monster?",
    "What treasure would make all this worth it?",
    "Do you think we'll make it out alive?",
    "What do you think about when you're on watch?",
    "What's the first thing you'll do when we return to the surface?",
    "Have you ever been tempted by something you found in the depths?",
    "What's the most dangerous situation you've survived?",
}

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------

--- Get a random prompt (seeded for determinism)
-- @param seed number: Optional seed for reproducibility
-- @return string: A random discussion prompt
function M.getRandomPrompt(seed)
    if seed then
        math.randomseed(seed)
    end
    local index = math.random(1, #M.PROMPTS)
    return M.PROMPTS[index]
end

--- Get a specific prompt by index
-- @param index number: 1-based index
-- @return string: The prompt at that index
function M.getPrompt(index)
    return M.PROMPTS[index] or M.PROMPTS[1]
end

--- Get the total number of prompts
function M.getPromptCount()
    return #M.PROMPTS
end

return M
