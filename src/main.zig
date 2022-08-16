const w4 = @import("wasm4.zig");
const draw = @import("draw.zig");
const std = @import("std");
const geom = @import("geom.zig");
const input = @import("input.zig");
const world = @import("world.zig");

const world_data = @embedFile(@import("world_data").path);

const builtin = @import("builtin");
const debug = builtin.mode == .Debug;

const FBA = std.heap.FixedBufferAllocator;

var long_alloc_buffer: [4096]u8 = undefined;
var long_fba = FBA.init(&long_alloc_buffer);
const long_alloc = long_fba.allocator();

var frame_alloc_buffer: [2][4096]u8 = undefined;
var frame_fba: [2]FBA = .{
    FBA.init(&frame_alloc_buffer[0]),
    FBA.init(&frame_alloc_buffer[1]),
};
const frame_alloc: [2]std.mem.Allocator = .{
    frame_fba[0].allocator(),
    frame_fba[1].allocator(),
};

const Actor = struct {
    image: ?draw.Blit,
    offset: geom.Vec2f,
    size: geom.Vec2f,

    pos: geom.Vec2f,
    last_pos: geom.Vec2f,
    rect: geom.AABBf,
    shadow: geom.AABBf,

    pub fn render(this: Actor) void {
        const pos = geom.vec2.ftoi(this.pos + this.offset);
        const shadowpos = geom.vec2.ftoi(this.pos + geom.aabb.posf(this.shadow));
        const size = geom.vec2.ftoi(geom.aabb.sizef(this.shadow));
        w4.DRAW_COLORS.* = 0x33;
        w4.oval(shadowpos[0], shadowpos[1], size[0], size[1]);
        if (this.image) |image| {
            image.blit(pos);
        }
    }
};

var player = Actor{
    .pos = geom.Vec2f{ 80, 80 },
    .last_pos = geom.Vec2f{ 80, 80 },
    .rect = geom.AABBf{ -3, -3, 6, 6 },
    .shadow = geom.AABBf{-6.5, 1, 12, 5},
    .offset = geom.Vec2f{ -8, -12 },
    .image = world.player_blit,
    .size = .{ 16, 16 },
};

var room: world.Room = undefined;

export fn start() void {
    if (debug) {
        w4.tracef("tilemap_size = (%d, %d)", world.tilemap_size[0], world.tilemap_size[1]);
    }
    start_safe() catch |e| w4.tracef(@errorName(e));
}

fn start_safe() !void {
    const Cursor = std.io.FixedBufferStream([]const u8);
    var cursor = Cursor{
        .pos = 0,
        .buffer = world_data,
    };
    w4.tracef("%d", world_data.len);
    var reader = cursor.reader();
    {
        const entity_count = try reader.readInt(u8, .Little);
        var i: usize = 0;
        while (i < entity_count) : (i += 1) {
            const entity = try world.Entity.read(reader);
            if (entity.kind == .Player) {
                // TODO
                w4.tracef("PLAYER");
            }
        }
    }
    {
        const room_count = try reader.readInt(u8, .Little);
        w4.tracef("%d", room_count);
        // var i: usize = 0;
        // while (i < entity_count) : (i += 1) {
        room = try world.Room.read(long_alloc, reader);
            // if (entity.kind == .Player) {
                // TODO
            // }
        // }
    }
}

export fn update() void {
    update_safe() catch unreachable;
}

var time: usize = 0;

fn update_safe() !void {
    defer time += 1;
    defer input.update();

    // Memory management
    // Switch frame allocator every frame
    const which_alloc = time % 2;
    const alloc = frame_alloc[which_alloc];
    _ = alloc;
    defer frame_fba[(time + 1) % 2].reset();

    // Input
    const speed = 80.0 / 60.0;
    if (input.btn(.one, .up)) player.pos[1] -= speed;
    if (input.btn(.one, .left)) player.pos[0] -= speed;
    if (input.btn(.one, .right)) player.pos[0] += speed;
    if (input.btn(.one, .down)) player.pos[1] += speed;

    // Collision
    const hcols = collide(geom.Vec2f{ player.pos[0], player.last_pos[1] } + geom.aabb.posf(player.rect), geom.aabb.sizef(player.rect));
    const vcols = collide(geom.Vec2f{ player.last_pos[0], player.pos[1] } + geom.aabb.posf(player.rect), geom.aabb.sizef(player.rect));
    if (hcols.len > 0) player.pos[0] = player.last_pos[0];
    if (vcols.len > 0) player.pos[1] = player.last_pos[1];
    player.last_pos = player.pos;

    w4.DRAW_COLORS.* = 0x1234;
    var x: isize = 0;
    while (x < 10) : (x += 1) {
        var y: isize = 0;
        while (y < 10) : (y += 1) {
            const idx = @intCast(usize, y * 10 + x);
            world.blit(geom.Vec2{ x, y } * world.tile_size, room.tiles[idx]);
        }
    }

    // Render
    player.render();

    if (debug) {
        for (hcols.items[0..hcols.len]) |col| {
            const pos = geom.vec2.ftoi(geom.aabb.posf(col));
            const size = geom.vec2.ftoi(geom.aabb.sizef(col));
            w4.DRAW_COLORS.* = 0x0040;
            w4.rect(pos[0], pos[1], @intCast(u32, size[0]), @intCast(u32, size[1]));
        }
        for (vcols.items[0..vcols.len]) |col| {
            const pos = geom.vec2.ftoi(geom.aabb.posf(col));
            const size = geom.vec2.ftoi(geom.aabb.sizef(col));
            w4.DRAW_COLORS.* = 0x0040;
            w4.rect(pos[0], pos[1], @intCast(u32, size[0]), @intCast(u32, size[1]));
        }
    }
}

pub fn isSolid(tile: u8) bool {
    return (tile >= 1 and tile <= 6) or (tile >= 18 and tile <= 23 and tile != 19) or (tile >= 35 and tile <= 40);
}

pub fn isInScreenBounds(x: i32, y: i32) bool {
    return x >= 0 and y >= 0 and x < w4.CANVAS_SIZE and y < w4.CANVAS_SIZE;
}

pub fn isInMapBounds(x: i32, y: i32) bool {
    return x >= 0 and y >= 0 and x < 10 and y < 10;
}

pub fn collide(pos: geom.Vec2f, size: geom.Vec2f) CollisionInfo {
    const tile_sizef = geom.vec2.itof(world.tile_size);
    const top_left = pos / tile_sizef;
    const bot_right = top_left + size / tile_sizef;
    var collisions = CollisionInfo.init();

    var i: isize = @floatToInt(i32, top_left[0]);
    while (i <= @floatToInt(i32, bot_right[0])) : (i += 1) {
        var a: isize = @floatToInt(i32, top_left[1]);
        while (a <= @floatToInt(i32, bot_right[1])) : (a += 1) {
            if (!isInMapBounds(i, a)) continue;
            const x = @intCast(usize, i);
            const y = @intCast(usize, a);
            const idx = y * 10 + x;
            const tile = room.tiles[idx];
            const tilepos = geom.vec2.itof(geom.Vec2{ i, a } * world.tile_size);

            if (isSolid(tile)) {
                collisions.append(geom.aabb.initvf(tilepos, tile_sizef));
            }
        }
    }

    return collisions;
}

pub const CollisionInfo = struct {
    len: usize,
    items: [9]geom.AABBf,

    pub fn init() CollisionInfo {
        return CollisionInfo{
            .len = 0,
            .items = undefined,
        };
    }

    pub fn append(col: *CollisionInfo, item: geom.AABBf) void {
        std.debug.assert(col.len < 9);
        col.items[col.len] = item;
        col.len += 1;
    }
};
