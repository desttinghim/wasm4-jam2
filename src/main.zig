const w4 = @import("wasm4.zig");
const draw = @import("draw.zig");
const std = @import("std");
const geom = @import("geom.zig");
const input = @import("input.zig");
const tiles = @import("tiles.zig");

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

    pub fn render(this: Actor) void {
        const pos = geom.vec2.ftoi(this.pos + this.offset);
        const size = geom.vec2.ftoi(this.size);
        if (this.image) |image| {
            image.blit(pos);
        } else {
            w4.DRAW_COLORS.* = 4;
            w4.oval(pos[0], pos[1], size[0], size[1]);
        }
    }
};

var player = Actor{
    .pos = geom.Vec2f{ 80, 80 },
    .last_pos = geom.Vec2f{ 80, 80 },
    .rect = geom.AABBf{-3, -3, 6, 6},
    .offset = geom.Vec2f{ -8, -8 },
    .image = null,
    .size = .{ 16, 16 },
};

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
    const hcols = collide(geom.Vec2f{player.pos[0], player.last_pos[1]} + geom.aabb.posf(player.rect), player.size);
    const vcols = collide(geom.Vec2f{player.last_pos[0], player.pos[1]} + geom.aabb.posf(player.rect), player.size);
    if (hcols.len > 0) player.pos[0] = player.last_pos[0];
    if (vcols.len > 0) player.pos[1] = player.last_pos[1];
    player.last_pos = player.pos;

    w4.DRAW_COLORS.* = 0x1234;
    var x: isize = 0;
    while (x < 10) : (x += 1) {
        var y: isize = 0;
        while (y < 10) : (y += 1) {
            tiles.blit(geom.Vec2{ x, y } * tiles.tile_size, level[@intCast(usize, y)][@intCast(usize, x)]);
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

const level = [_][10]u8{
    .{ 0, 1, 2, 3, 0, 0, 0, 0, 0, 0, },
    .{ 0, 18, 19, 20, 0, 0, 0, 0, 0, 0, },
    .{ 0, 35, 36, 37, 0, 0, 0, 0, 0, 0, },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
};

pub fn isSolid(tile: u8) bool {
    return tile > 0;
}

pub fn collide(pos: geom.Vec2f, size: geom.Vec2f) CollisionInfo {
    const tile_sizef = geom.vec2.itof(tiles.tile_size);
    const top_left = pos / tile_sizef;
    const bot_right = top_left + size / tile_sizef;
    var collisions = CollisionInfo.init();

    var i: isize = @floatToInt(i32, top_left[0]);
    while (i <= @floatToInt(i32, bot_right[0])) : (i += 1) {
        var a: isize = @floatToInt(i32, top_left[1]);
        while (a <= @floatToInt(i32, bot_right[1])) : (a += 1) {
            const x = @intCast(usize, i);
            const y = @intCast(usize, a);
            const tile = level[y][x];
            const tilepos = geom.vec2.itof(geom.Vec2{i, a} * tiles.tile_size);

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
