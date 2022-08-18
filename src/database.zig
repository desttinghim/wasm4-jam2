const std = @import("std");
const geom = @import("geom.zig");
const world = @import("world.zig");
const w4 = @import("wasm4.zig");
var world_data = @embedFile(@import("world_data").path);
const builtin = @import("builtin");
const debug = builtin.mode == .Debug;
// const debug = false;

const Cursor = std.io.FixedBufferStream([]const u8);

/// Fixed buffer stream of world data
cursor: Cursor,
/// Store a reference to the player
player: u16,
/// All entities in the game
entities: []world.Entity,
/// Actual room types
room_data: []world.Room,
/// Binary searchable array
/// Index corresponds with room_data index
room_lookup: []u16,
/// Slices of the entities array for each room
/// Index corresponds with room_data index
room_entities: [][]world.Entity,

const Database = @This();

pub fn init(alloc: std.mem.Allocator) !@This() {
    var cursor = Cursor{
        .pos = 0,
        .buffer = world_data,
    };

    if (debug) w4.tracef("[db.init] %d Bytes", world_data.len);

    var reader = cursor.reader();
    const entity_count = try reader.readInt(u16, .Little);

    if (debug) w4.tracef("[db.init] %d Entities", entity_count);

    var entities = try alloc.alloc(world.Entity, entity_count);
    var playerIndex: usize = 0;
    var player_count: usize = 0;
    var i: usize = 0;
    while (i < entity_count) : (i += 1) {
        const entity = try world.Entity.read(reader);
        entities[i] = entity;
        if (entity.kind == .Player) {
            playerIndex = i;
            player_count += 1;
            if (debug) w4.tracef("[db.init] Player spawn at (%d %d)", entity.vec[0], entity.vec[1]);
        }
    }
    if (debug and player_count == 0) w4.tracef("[db.init] NO PLAYER FOUND");

    const room_count = try reader.readInt(u8, .Little);
    var rooms = try alloc.alloc(world.Room, room_count);

    if (debug) w4.tracef("[db.init] %d Rooms", room_count);

    i = 0;
    while (i < room_count) : (i += 1) {
        rooms[i] = try world.Room.readHeader(reader);
        const tiles_start = @intCast(usize, try cursor.getPos());
        const len = @intCast(usize, rooms[i].size[0]) * @intCast(usize, rooms[i].size[1]);
        if (debug) w4.tracef("[db.init] Room %d: tiles_start=%d, len=%d", i, tiles_start, len);
        rooms[i].tiles = world_data[tiles_start .. tiles_start + len];
        try cursor.seekTo(tiles_start + len);
    }
    if (debug) w4.tracef("[db.init] Parsed rooms");

    // Sort rooms so we can do a binary search on them
    std.sort.insertionSort(world.Room, rooms, {}, world.Room.compare);

    var room_lookup = try alloc.alloc(u16, room_count);
    var room_entities = try alloc.alloc([]world.Entity, room_count);
    for (rooms) |room, roomidx| {
        var start: ?usize = 0;
        room_lookup[roomidx] = room.toID();
        for (entities) |entity, idx| {
            if (start == null and room.contains(entity.toVec())) {
                start = idx;
            }
            const s = start orelse continue;
            if (!room.contains(entity.toVec())) {
                room_entities[roomidx] = entities[s..idx];
                break;
            }
        }
    }

    return @This(){
        .cursor = cursor,
        .player = @intCast(u16, playerIndex),
        .room_data = rooms,
        .room_lookup = room_lookup,
        .entities = entities,
        .room_entities = room_entities,
    };
}

pub fn getSpawn(db: Database) ?world.Entity {
    return db.entities[db.player];
}

pub fn getRoomContaining(db: Database, coord: geom.Vec2) ?world.Room {
    if (debug) w4.tracef("[db.getRoomContaining] (%d, %d)", coord[0], coord[1]);
    for (db.room_data) |room| {
        if (room.contains(coord)) return room;
    }
    return null;
}

pub fn getRoomEntities(db: Database, room: world.Room) ?[]world.Entity {
    for (db.room_lookup) |id, i| {
        if (room.toID() == id) {
            return db.room_entities[i];
        }
    }
    return null;
}
