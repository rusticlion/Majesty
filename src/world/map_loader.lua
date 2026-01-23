-- map_loader.lua
-- Map Generation Utility for Majesty
-- Ticket T2_7: Import maps from various formats into DungeonGraph
--
-- Supports:
-- 1. Standard Lua table format (as used by tutorial_level.lua)
-- 2. Simplified connection string format: "room1 -> room2 [props]"
-- 3. Room blueprint references

local dungeon_graph = require('dungeon_graph')

local M = {}

--------------------------------------------------------------------------------
-- EDGE PROPERTY PARSER
-- Parses edge properties from string format like [locked, secret, direction=north]
--------------------------------------------------------------------------------

local function parseEdgeProperties(propString)
    local props = {}

    if not propString or propString == "" then
        return props
    end

    -- Remove brackets if present
    propString = propString:gsub("^%[", ""):gsub("%]$", "")

    -- Split by comma
    for prop in propString:gmatch("[^,]+") do
        prop = prop:match("^%s*(.-)%s*$")  -- Trim whitespace

        -- Check for key=value format
        local key, value = prop:match("^(%w+)%s*=%s*(.+)$")
        if key then
            -- Handle quoted strings
            value = value:gsub("^[\"']", ""):gsub("[\"']$", "")

            -- Convert boolean strings
            if value == "true" then value = true
            elseif value == "false" then value = false
            end

            props[key] = value
        else
            -- Shorthand properties
            if prop == "locked" then
                props.is_locked = true
            elseif prop == "secret" then
                props.is_secret = true
            elseif prop == "oneway" or prop == "one_way" then
                props.is_one_way = true
            elseif prop:match("^north") or prop:match("^south") or
                   prop:match("^east") or prop:match("^west") or
                   prop:match("^up") or prop:match("^down") then
                props.direction = prop
            end
        end
    end

    return props
end

--------------------------------------------------------------------------------
-- CONNECTION STRING PARSER
-- Format: "room_a -> room_b [properties]"
-- or: "room_a -- room_b [properties]" (bidirectional)
-- or: "room_a <- room_b [properties]" (reverse)
--------------------------------------------------------------------------------

local function parseConnectionString(line)
    -- Match: room_a -> room_b [props] or room_a -- room_b [props]
    local from, arrow, to, propsStr = line:match("^%s*(%S+)%s*([%-<>]+)%s*(%S+)%s*(%[.-%])?%s*$")

    if not from or not to then
        return nil, "Invalid connection format"
    end

    local props = parseEdgeProperties(propsStr)

    -- Handle arrow direction
    if arrow == "<-" then
        -- Reverse direction
        from, to = to, from
    elseif arrow == "->" then
        props.is_one_way = true
    end
    -- "--" is bidirectional (default)

    return {
        from = from,
        to = to,
        properties = props
    }
end

--------------------------------------------------------------------------------
-- ROOM STRING PARSER
-- Format: "room_id: Room Name - Description"
-- or: "room_id: Room Name [props]"
--------------------------------------------------------------------------------

local function parseRoomString(line)
    -- Match: room_id: Name - Description
    local id, rest = line:match("^%s*(%S+):%s*(.+)$")

    if not id then
        return nil, "Invalid room format"
    end

    local name, description, propsStr

    -- Check for properties in brackets at end
    propsStr = rest:match("%[.-%]$")
    if propsStr then
        rest = rest:gsub("%s*%[.-%]$", "")
    end

    -- Split name and description by " - "
    name, description = rest:match("^(.-)%s+%-%s+(.+)$")
    if not name then
        name = rest:match("^%s*(.-)%s*$")
        description = ""
    end

    local props = parseEdgeProperties(propsStr)

    return {
        id = id,
        name = name,
        description = description,
        zones = props.zones,
        danger_level = props.danger_level,
    }
end

--------------------------------------------------------------------------------
-- TEXT FORMAT LOADER
-- Loads dungeon from a multi-line text format
--------------------------------------------------------------------------------

--- Load dungeon from text format
-- @param text string: Multi-line text defining rooms and connections
-- @return table: Data suitable for dungeon_graph.loadFromData
function M.parseTextFormat(text)
    local data = {
        name = "Unnamed Dungeon",
        rooms = {},
        connections = {},
    }

    local section = "header"  -- header, rooms, connections
    local roomsById = {}

    for line in text:gmatch("[^\r\n]+") do
        -- Skip empty lines and comments
        if not line:match("^%s*$") and not line:match("^%s*#") and not line:match("^%s*%-%-") then

            -- Section headers
            if line:match("^%[rooms%]") or line:match("^ROOMS:") then
                section = "rooms"
            elseif line:match("^%[connections%]") or line:match("^CONNECTIONS:") then
                section = "connections"
            elseif line:match("^%[name%]") or line:match("^NAME:") then
                section = "name"
            elseif section == "name" then
                data.name = line:match("^%s*(.-)%s*$")
                section = "header"
            elseif section == "rooms" then
                local room, err = parseRoomString(line)
                if room then
                    data.rooms[#data.rooms + 1] = room
                    roomsById[room.id] = room
                end
            elseif section == "connections" then
                local conn, err = parseConnectionString(line)
                if conn then
                    data.connections[#data.connections + 1] = conn
                end
            end
        end
    end

    return data
end

--------------------------------------------------------------------------------
-- SIMPLIFIED LOADER HELPERS
--------------------------------------------------------------------------------

--- Quick room definition helper
-- @param id string
-- @param name string
-- @param description string (optional)
-- @return table: Room data
function M.room(id, name, description)
    return {
        id = id,
        name = name or id,
        description = description or "",
    }
end

--- Quick connection helper
-- @param from string
-- @param to string
-- @param props table (optional): { direction, locked, secret, one_way, key_id }
-- @return table: Connection data
function M.connect(from, to, props)
    props = props or {}
    return {
        from = from,
        to = to,
        properties = {
            direction   = props.direction,
            is_locked   = props.locked,
            is_secret   = props.secret,
            is_one_way  = props.one_way,
            key_id      = props.key_id,
            description = props.description,
        },
    }
end

--- Quick locked door connection
function M.lockedDoor(from, to, direction, keyId)
    return M.connect(from, to, {
        direction = direction,
        locked = true,
        key_id = keyId,
    })
end

--- Quick secret passage connection
function M.secretPassage(from, to, direction)
    return M.connect(from, to, {
        direction = direction,
        secret = true,
    })
end

--- Quick one-way connection (chute, drop, etc.)
function M.oneWay(from, to, direction)
    return M.connect(from, to, {
        direction = direction,
        one_way = true,
    })
end

--------------------------------------------------------------------------------
-- MAIN LOADER FUNCTIONS
--------------------------------------------------------------------------------

--- Load dungeon from Lua table (wraps dungeon_graph.loadFromData)
-- @param data table: { name, rooms, connections }
-- @return DungeonGraph
function M.loadFromTable(data)
    return dungeon_graph.loadFromData(data)
end

--- Load dungeon from text format
-- @param text string: Multi-line text
-- @return DungeonGraph
function M.loadFromText(text)
    local data = M.parseTextFormat(text)
    return dungeon_graph.loadFromData(data)
end

--- Load dungeon from a Lua file
-- @param path string: Path to Lua file returning { data = {...} }
-- @return DungeonGraph
function M.loadFromFile(path)
    local module = require(path)
    if module.data then
        return dungeon_graph.loadFromData(module.data)
    end
    return nil, "File does not contain 'data' table"
end

--------------------------------------------------------------------------------
-- BUILDER PATTERN
-- Fluent interface for creating dungeons programmatically
--------------------------------------------------------------------------------

--- Create a new DungeonBuilder
-- @param name string: Dungeon name
-- @return DungeonBuilder
function M.builder(name)
    local builder = {
        data = {
            name = name or "Unnamed Dungeon",
            rooms = {},
            connections = {},
        }
    }

    --- Add a room
    function builder:addRoom(id, name, description, config)
        config = config or {}
        self.data.rooms[#self.data.rooms + 1] = {
            id = id,
            name = name or id,
            description = description or "",
            zones = config.zones,
            danger_level = config.danger_level,
        }
        return self
    end

    --- Add a bidirectional connection
    function builder:connect(from, to, direction, props)
        props = props or {}
        self.data.connections[#self.data.connections + 1] = {
            from = from,
            to = to,
            properties = {
                direction   = direction,
                is_locked   = props.locked,
                is_secret   = props.secret,
                is_one_way  = false,
                key_id      = props.key_id,
                description = props.description,
            },
        }
        return self
    end

    --- Add a locked door
    function builder:lockedDoor(from, to, direction, keyId)
        return self:connect(from, to, direction, { locked = true, key_id = keyId })
    end

    --- Add a secret passage
    function builder:secretPassage(from, to, direction)
        return self:connect(from, to, direction, { secret = true })
    end

    --- Add a one-way connection
    function builder:oneWay(from, to, direction)
        self.data.connections[#self.data.connections + 1] = {
            from = from,
            to = to,
            properties = {
                direction = direction,
                is_one_way = true,
            },
        }
        return self
    end

    --- Build the DungeonGraph
    function builder:build()
        return dungeon_graph.loadFromData(self.data)
    end

    return builder
end

return M
