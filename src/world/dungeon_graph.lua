-- dungeon_graph.lua
-- Dungeon Graph (Nodes & Edges) for Majesty
-- Ticket T2_1: Graph data structure for dungeon layout
--
-- Design: Rooms are nodes, Connections are edges with properties.
-- Store only room_id in connections (not full Room tables) to avoid
-- infinite recursion when serializing for save files.

local M = {}

--------------------------------------------------------------------------------
-- DIRECTION CONSTANTS
--------------------------------------------------------------------------------
M.DIRECTIONS = {
    NORTH = "north",
    SOUTH = "south",
    EAST  = "east",
    WEST  = "west",
    UP    = "up",
    DOWN  = "down",
}

-- Opposite directions for two-way connections
local OPPOSITE = {
    north = "south",
    south = "north",
    east  = "west",
    west  = "east",
    up    = "down",
    down  = "up",
}

--------------------------------------------------------------------------------
-- ROOM FACTORY
--------------------------------------------------------------------------------

--- Default zone for rooms (T2_3)
local DEFAULT_ZONE = {
    id          = "main",
    name        = "Main",
    description = "The main area of this room.",
}

--- Create a new Room
-- @param config table: { id, name, description, zones }
-- @return Room table
function M.createRoom(config)
    config = config or {}

    -- Ensure room has at least one zone (default: "Main")
    local zones = config.zones
    if not zones or #zones == 0 then
        zones = { DEFAULT_ZONE }
    end

    return {
        id          = config.id or error("Room requires an id"),
        name        = config.name or "Unknown Room",
        description = config.description or "",
        zones       = zones,                     -- Internal zones (T2_3) - always has at least "main"
        connections = {},                        -- Populated by graph:addConnection
        discovered  = config.discovered or true, -- Has this room been found?
        properties  = config.properties or {},   -- Custom room properties
    }
end

--------------------------------------------------------------------------------
-- CONNECTION FACTORY
-- Connections are objects - they can hold logic (locked doors, traps, etc.)
--------------------------------------------------------------------------------

--- Create a Connection (edge) between rooms
-- @param targetRoomId string: The room this connection leads to
-- @param properties table: { direction, is_secret, is_locked, is_one_way, ... }
-- @return Connection table
local function createConnection(targetRoomId, properties)
    properties = properties or {}

    return {
        target_room_id = targetRoomId,
        direction      = properties.direction or nil,
        is_secret      = properties.is_secret or false,
        is_locked      = properties.is_locked or false,
        is_one_way     = properties.is_one_way or false,
        discovered     = not (properties.is_secret or false),  -- Secrets start undiscovered
        key_id         = properties.key_id or nil,              -- What unlocks this?
        trap           = properties.trap or nil,                -- Trap data (future)
        description    = properties.description or nil,         -- "A heavy iron door"
    }
end

--------------------------------------------------------------------------------
-- DUNGEON GRAPH FACTORY
--------------------------------------------------------------------------------

--- Create a new DungeonGraph
-- @return DungeonGraph instance
function M.createGraph()
    local graph = {
        rooms = {},       -- room_id -> Room
        name  = "Unnamed Dungeon",
    }

    ----------------------------------------------------------------------------
    -- ROOM MANAGEMENT
    ----------------------------------------------------------------------------

    --- Add a room to the graph
    -- @param room table: Room created by createRoom()
    function graph:addRoom(room)
        if not room.id then
            return false, "room_missing_id"
        end
        self.rooms[room.id] = room
        return true
    end

    --- Get a room by ID
    function graph:getRoom(roomId)
        return self.rooms[roomId]
    end

    --- Check if a room exists
    function graph:hasRoom(roomId)
        return self.rooms[roomId] ~= nil
    end

    --- Create and add a room in one call
    function graph:createRoom(config)
        local room = M.createRoom(config)
        self:addRoom(room)
        return room
    end

    ----------------------------------------------------------------------------
    -- CONNECTION MANAGEMENT
    ----------------------------------------------------------------------------

    --- Add a connection between two rooms
    -- @param roomA_id string: Source room ID
    -- @param roomB_id string: Target room ID
    -- @param properties table: { direction, is_secret, is_locked, is_one_way, ... }
    -- @return boolean, string: success, error_reason
    function graph:addConnection(roomA_id, roomB_id, properties)
        properties = properties or {}

        local roomA = self.rooms[roomA_id]
        local roomB = self.rooms[roomB_id]

        if not roomA then
            return false, "source_room_not_found"
        end
        if not roomB then
            return false, "target_room_not_found"
        end

        -- Create the connection from A to B
        local connectionAtoB = createConnection(roomB_id, properties)
        roomA.connections[#roomA.connections + 1] = connectionAtoB

        -- If not one-way, create reverse connection from B to A
        if not properties.is_one_way then
            local reverseProps = {}
            for k, v in pairs(properties) do
                reverseProps[k] = v
            end
            -- Flip the direction for the reverse connection
            if properties.direction and OPPOSITE[properties.direction] then
                reverseProps.direction = OPPOSITE[properties.direction]
            end

            local connectionBtoA = createConnection(roomA_id, reverseProps)
            roomB.connections[#roomB.connections + 1] = connectionBtoA
        end

        return true
    end

    --- Add a one-way connection (convenience method)
    function graph:addOneWayConnection(fromId, toId, properties)
        properties = properties or {}
        properties.is_one_way = true
        return self:addConnection(fromId, toId, properties)
    end

    ----------------------------------------------------------------------------
    -- QUERIES
    ----------------------------------------------------------------------------

    --- Get adjacent rooms from a given room
    -- @param roomId string: The room to query from
    -- @param options table: { include_secret, include_locked }
    -- @return table: Array of { room, connection } pairs
    function graph:getAdjacentRooms(roomId, options)
        options = options or {}
        local includeSecret = options.include_secret or false
        local includeLocked = options.include_locked ~= false  -- Default true

        local room = self.rooms[roomId]
        if not room then
            return {}
        end

        local adjacent = {}
        for _, connection in ipairs(room.connections) do
            local include = true

            -- Filter out undiscovered secrets unless requested
            if connection.is_secret and not connection.discovered and not includeSecret then
                include = false
            end

            -- Optionally filter locked connections
            if connection.is_locked and not includeLocked then
                include = false
            end

            if include then
                local targetRoom = self.rooms[connection.target_room_id]
                if targetRoom then
                    adjacent[#adjacent + 1] = {
                        room       = targetRoom,
                        connection = connection,
                    }
                end
            end
        end

        return adjacent
    end

    --- Get a connection between two rooms (if it exists)
    function graph:getConnection(fromId, toId)
        local room = self.rooms[fromId]
        if not room then return nil end

        for _, conn in ipairs(room.connections) do
            if conn.target_room_id == toId then
                return conn
            end
        end
        return nil
    end

    --- Discover a secret connection
    function graph:discoverConnection(fromId, toId)
        local conn = self:getConnection(fromId, toId)
        if conn then
            conn.discovered = true
            return true
        end
        return false
    end

    --- Unlock a locked connection
    function graph:unlockConnection(fromId, toId)
        local conn = self:getConnection(fromId, toId)
        if conn then
            conn.is_locked = false
            -- Also unlock the reverse if it exists
            local reverse = self:getConnection(toId, fromId)
            if reverse then
                reverse.is_locked = false
            end
            return true
        end
        return false
    end

    ----------------------------------------------------------------------------
    -- PATHFINDING HELPERS
    ----------------------------------------------------------------------------

    --- Get all room IDs in the graph
    function graph:getAllRoomIds()
        local ids = {}
        for id, _ in pairs(self.rooms) do
            ids[#ids + 1] = id
        end
        return ids
    end

    --- Count rooms
    function graph:roomCount()
        local count = 0
        for _ in pairs(self.rooms) do
            count = count + 1
        end
        return count
    end

    ----------------------------------------------------------------------------
    -- RESET (S10.1)
    ----------------------------------------------------------------------------

    --- Reset the dungeon to its initial state
    -- Clears discovered flags, re-locks doors, hides secrets
    function graph:reset()
        for _, room in pairs(self.rooms) do
            -- Reset room discovery (keep entrance discovered)
            -- room.discovered = false  -- Uncomment if you want fog of war

            -- Reset all connections
            for _, conn in ipairs(room.connections) do
                -- Re-lock locked doors
                if conn.key_id then
                    conn.is_locked = true
                end

                -- Re-hide secrets
                if conn.is_secret then
                    conn.discovered = false
                end
            end
        end

        print("[DUNGEON] Graph reset to initial state")
    end

    return graph
end

--------------------------------------------------------------------------------
-- DATA LOADER
-- Load a dungeon from a data table (for map files)
--------------------------------------------------------------------------------

--- Load a dungeon graph from a data definition
-- @param data table: { name, rooms = {}, connections = {} }
-- @return DungeonGraph instance
function M.loadFromData(data)
    local graph = M.createGraph()
    graph.name = data.name or "Unnamed Dungeon"

    -- Add all rooms first
    for _, roomData in ipairs(data.rooms or {}) do
        graph:createRoom(roomData)
    end

    -- Then add connections
    for _, connData in ipairs(data.connections or {}) do
        graph:addConnection(connData.from, connData.to, connData.properties)
    end

    return graph
end

return M
