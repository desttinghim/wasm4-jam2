const w4 = @import("wasm4.zig");
const draw = @import("draw.zig");
const std = @import("std");
const geom = @import("geom.zig");
const input = @import("input.zig");
const world = @import("world.zig");
const Anim = @import("Anim.zig");

const Database = @import("database.zig");

const builtin = @import("builtin");
// const debug = builtin.mode == .Debug;
const debug = false;

const FBA = std.heap.FixedBufferAllocator;

var long_alloc_buffer: [8192]u8 = undefined;
var long_fba = FBA.init(&long_alloc_buffer);
const long_alloc = long_fba.allocator();

var level_alloc_buffer: [8192]u8 = undefined;
var level_fba = FBA.init(&level_alloc_buffer);
const level_alloc = level_fba.allocator();

var frame_alloc_buffer: [2][8192]u8 = undefined;
var frame_fba: [2]FBA = .{
    FBA.init(&frame_alloc_buffer[0]),
    FBA.init(&frame_alloc_buffer[1]),
};
const frame_alloc: [2]std.mem.Allocator = .{
    frame_fba[0].allocator(),
    frame_fba[1].allocator(),
};

const Actor = @import("Actor.zig");

const Combat = struct {
    animator: *Anim,
    actor: *Actor,
    is_attacking: bool = false,
    last_attacking: usize = 0,
    last_attack: usize = 0,
    chain: u8 = 0,

    image: draw.Blit,
    offset: geom.Vec2f,
    punch_down: [2][]const Anim.Ops,
    punch_up: [2][]const Anim.Ops,
    punch_side: [2][]const Anim.Ops,

    pub fn endAttack(this: *Combat) void {
        this.chain = 0;
        this.is_attacking = false;
        this.actor.image = player_blit;
        this.actor.offset = player_offset;
        this.actor.image.flags.flip_x = this.actor.facing == .Left;
        // Arrest momentum
        this.actor.last_pos = this.actor.pos;
    }

    /// Relative to offset
    pub fn getHurtbox(this: Combat) geom.Rectf {
        // This will be called after startAttack, so last_attack == 0 is flipped
        if (this.last_attack == 0) {
            return switch (this.actor.facing) {
                .Up => .{ -4, -20, 13, 10 },
                .Left => .{ -16, -10, 12, 11 },
                .Right => .{ 4, -10, 12, 11 },
                .Down => .{ -4, 0, 12, 12 },
            };
        } else {
            return switch (this.actor.facing) {
                .Up => .{ -7, -20, 13, 10 },
                .Left => .{ -16, -10, 12, 11 },
                .Right => .{ 4, -10, 12, 11 },
                .Down => .{ -8, 0, 12, 12 },
            };
        }
    }

    pub fn startAttack(this: *Combat, now: usize) void {
        if (!this.animator.interruptable) {
            this.chain = 0;
            return;
        }
        if (now - this.last_attacking <= 45) {
            this.chain +|= 1;
        }
        this.actor.image = this.image;
        this.actor.offset = this.offset;
        if (this.actor.facing == .Down) {
            this.animator.play(this.punch_down[this.last_attack]);
        } else if (this.actor.facing == .Up) {
            this.animator.play(this.punch_up[this.last_attack]);
        } else {
            this.animator.play(this.punch_side[this.last_attack]);
            this.actor.image.flags.flip_x = this.actor.facing == .Left;
        }
        this.is_attacking = true;
        this.last_attacking = now;
        this.last_attack = (this.last_attack + 1) % 2;
    }
};

const player_blit = draw.Blit.init_frame(world.player_style, &world.player_bmp, .{ .bpp = .b2 }, .{ 16, 16 }, 0);
const player_offset = geom.Vec2f{ -8, -12 };
var playerIndex: usize = undefined;
var player_combat = Combat{
    .actor = undefined,
    .animator = undefined,
    .offset = geom.Vec2f{ -16, -20 },
    .image = draw.Blit.init_frame(world.player_style, &world.player_punch_bmp, .{ .bpp = .b2 }, .{ 32, 32 }, 0),
    .punch_down = .{ &world.player_anim_punch_down, &world.player_anim_punch_down2 },
    .punch_up = .{ &world.player_anim_punch_up, &world.player_anim_punch_up2 },
    .punch_side = .{ &world.player_anim_punch_side, &world.player_anim_punch_side2 },
};
var camera = geom.Vec2f{ 0, 0 };
var playerStore: Actor = undefined;

var actors: std.ArrayList(Actor) = undefined;
const AnimStore = struct { owns: usize, anim: Anim };
var animators: []AnimStore = undefined;

var db: Database = undefined;

fn Assoc(comptime T: type) type {
    return struct { key: usize, val: T };
}

var room: world.Room = undefined;

export fn start() void {
    if (debug) {
        w4.tracef("tilemap_size = (%d, %d)", world.tilemap_size[0], world.tilemap_size[1]);
    }
    start_safe() catch |e| {
        w4.tracef(@errorName(e));
        @panic("Ran into an error! ");
    };
}

fn start_safe() !void {
    // https://lospec.com/palette-list/crimson
    // CRIMSON
    // by WilLeoKnight
    // w4.PALETTE.* = .{ 0xeff9d6, 0xba5044, 0x7a1c4b, 0x1b0326 };

    // https://lospec.com/palette-list/space-icecream
    // SPACE ICECREAM
    // by Rexsarus
    // w4.PALETTE.* = .{ 0xfffed6, 0xffabab, 0x644666, 0x100221 };

    // https://lospec.com/palette-list/space-icecream
    // Kirokaze GB
    // by Kirokaze
    // w4.PALETTE.* = .{ 0xe2f3e4, 0x94e344, 0x46878f, 0x332c50 };

    // Default
    // WASM-4
    // w4.PALETTE.* = .{ 0xe0f8cf, 0x86c06c, 0x306850, 0x071821 };

    w4.PALETTE.* = .{ 0xe0f8cf, 0x86c06c, 0x644666, 0x100221 };

    db = try Database.init(long_alloc);

    var spawn: world.Entity = db.getSpawn() orelse return error.PlayerNotFound;
    room = db.getRoomContaining(spawn.toVec()) orelse return error.RoomNotFound;

    // Create player
    {
        const tile_sizef = geom.vec2.itof(world.tile_size);
        const pos = spawn.toPos() + (tile_sizef / @splat(2, @as(f32, 2)));
        playerStore = Actor{
            .kind = spawn.kind,
            .pos = pos,
            .last_pos = pos,
            .collisionBox = geom.AABBf{ -4, -4, 8, 8 },
            .offset = geom.Vec2f{ -8, -12 },
            .image = player_blit,
        };
    }

    try loadRoom();
}

fn loadRoom() !void {
    // Reset the level allocator
    level_fba.reset();

    const entities = db.getRoomEntities(room) orelse return error.NoRoomEntities;
    actors = try std.ArrayList(Actor).initCapacity(level_alloc, entities.len);

    try actors.append(playerStore);

    // Declare animator component count (player is implicitly counted)
    var needs_animator: usize = 1;

    // Load other entities
    for (entities) |entity| {
        const tile_sizef = geom.vec2.itof(world.tile_size);
        const pos = entity.toPos() + (tile_sizef / @splat(2, @as(f32, 2)));
        switch (entity.kind) {
            .Player => {},
            .Pot => {
                try actors.append(Actor{
                    .kind = entity.kind,
                    .pos = pos,
                    .last_pos = pos,
                    .collisionBox = geom.AABBf{ -4, -4, 8, 8 },
                    .offset = geom.Vec2f{ -8, -12 },
                    .image = draw.Blit.init_frame(0x0234, &world.bitmap, .{ .bpp = .b2 }, .{ 16, 16 }, world.pot),
                });
            },
        }
    }

    // Allocate animators
    animators = try level_alloc.alloc(AnimStore, needs_animator);

    if (debug) w4.tracef("[start] Anim count %d", needs_animator);
    // Add animator components
    var idx: usize = 0;
    for (actors.items) |actor, a| {
        if (actor.kind == .Player) {
            animators[idx] = .{ .owns = idx, .anim = .{
                .anim = &world.player_anim_walk_down,
            } };
            player_combat.animator = &animators[idx].anim;
            player_combat.actor = &actors.items[a];
            idx += 1;
        }
    }
}

export fn update() void {
    update_safe() catch |e| {
        w4.tracef(@errorName(e));
        @panic("Ran into an error! ");
    };
}

var time: usize = 0;

fn update_safe() !void {
    defer time += 1;
    defer input.update();

    // Memory management
    // Switch frame allocator every frame
    const which_alloc = time % 2;
    const alloc = frame_alloc[which_alloc];
    defer frame_fba[(time + 1) % 2].reset();

    var hurtboxes = std.ArrayList(Assoc(geom.Rectf)).init(alloc);
    defer hurtboxes.deinit();

    var next_room: ?world.Room = null;

    {
        // Input
        var player = &actors.items[playerIndex];
        player.motive = false;
        const speed: f32 = 40.0 / 60.0;
        if (!player_combat.is_attacking) {
            if (input.btn(.one, .up)) {
                player.facing = .Up;
                player.pos[1] -= speed;
                player.motive = true;
            }
            if (input.btn(.one, .left)) {
                player.facing = .Left;
                player.pos[0] -= speed;
                player.motive = true;
            }
            if (input.btn(.one, .right)) {
                player.facing = .Right;
                player.pos[0] += speed;
                player.motive = true;
            }
            if (input.btn(.one, .down)) {
                player.facing = .Down;
                player.pos[1] += speed;
                player.motive = true;
            }
            if (player.motive and player_combat.is_attacking) player_combat.endAttack();
            if (input.btnp(.one, .z)) player_combat.startAttack(time);
        } else if (!player_combat.animator.interruptable) {
            player.pos += player.facing.getVec2f() * @splat(2, speed * 1.25);
            try hurtboxes.append(.{ .key = playerIndex, .val = geom.rect.shiftf(player_combat.getHurtbox(), player.pos) });
        } else {
            if (input.btnp(.one, .z)) player_combat.startAttack(time);
            if (time - player_combat.last_attacking > 45) player_combat.endAttack();
        }

        // Collision
        const as_rectf = geom.aabb.as_rectf;
        const addvf = geom.aabb.addvf;
        const hcols = collide(playerIndex, as_rectf(addvf(player.collisionBox, geom.Vec2f{ player.pos[0], player.last_pos[1] })));
        const vcols = collide(playerIndex, as_rectf(addvf(player.collisionBox, geom.Vec2f{ player.last_pos[0], player.pos[1] })));
        if (hcols.len > 0) player.pos[0] = player.last_pos[0];
        if (vcols.len > 0) player.pos[1] = player.last_pos[1];

        // Kinematics
        const velocity = (player.pos - player.last_pos) * @splat(2, @as(f32, 0.5));
        player.last_pos = player.pos;
        player.pos += velocity;

        {
            camera = player.pos - geom.Vec2f{ 80, 80 };
            const bounds = geom.aabb.as_rectf(geom.aabb.itof(room.toAABB() * @splat(4, world.tile_size[0])));
            if (camera[0] < bounds[0]) camera[0] = bounds[0];
            if (camera[1] < bounds[1]) camera[1] = bounds[1];
            if (camera[0] + 160 > bounds[2]) camera[0] = bounds[2] - 160;
            if (camera[1] + 160 > bounds[3]) camera[1] = bounds[3] - 160;

            const size = geom.aabb.sizef(player.collisionBox);
            const left = (player.pos[0] < bounds[0] + size[0]);
            const up = (player.pos[1] - size[1] < bounds[1]);
            const right = (player.pos[0] > bounds[2] - size[0]);
            const down = (player.pos[1] > bounds[3]);
            if (left or up or right or down) {
                next_room = db.getRoomContaining(player.toGrid());
            }
            if (next_room != null and left) {
                player.pos[0] = bounds[0] - size[0];
                player.last_pos = player.pos;
            }
            if (next_room != null and up) {
                player.pos[1] = bounds[1] - 1;
                player.last_pos = player.pos;
            }
            if (next_room != null and right) {
                player.pos[0] = bounds[2] + size[0] * 1.5;
                player.last_pos = player.pos;
            }
            if (next_room != null and down) {
                player.pos[1] = bounds[3] + 16;
                player.last_pos = player.pos;
            }
        }

        var animator = player_combat.animator;
        if (player.motive and animator.interruptable) {
            if (player.facing == .Up) animator.play(&world.player_anim_walk_up);
            if (player.facing == .Down) animator.play(&world.player_anim_walk_down);
            if (player.facing == .Left) {
                player.image.flags.flip_x = true;
                animator.play(&world.player_anim_walk_side);
            }
            if (player.facing == .Right) {
                player.image.flags.flip_x = false;
                animator.play(&world.player_anim_walk_side);
            }
        } else {
            if (!player_combat.is_attacking) {
                if (player.facing == .Down) {
                    animator.play(&world.player_anim_stand_down);
                } else if (player.facing == .Left or player.facing == .Right) {
                    animator.play(&world.player_anim_stand_side);
                } else {
                    animator.play(&world.player_anim_stand_up);
                }
            }
        }
    }

    // Render
    w4.DRAW_COLORS.* = 0x1234;
    const camera_pos = geom.vec2.ftoi(camera);
    // const camera_pos_g = @divTrunc(camera_pos, world.tile_size);
    var x: isize = 0;
    while (x < room.size[0]) : (x += 1) {
        var y: isize = 0;
        // if (!(x >= camera_pos_g[0] and x < camera_pos_g[0]  + 11)) continue;
        while (y < room.size[1]) : (y += 1) {
            // if (!(y >= camera_pos_g[1]  and y < camera_pos_g[1]  + 11)) continue;
            const idx = @intCast(usize, y * @intCast(i16, room.size[0]) + x);
            world.blit((geom.Vec2{ x, y } + room.toVec2()) * world.tile_size - camera_pos, room.tiles[idx]);
        }
    }

    // Animate!
    for (animators) |*store| {
        var actor = &actors.items[store.owns];
        store.anim.update(&actor.image.frame, &actor.image.flags);
    }

    var draw_order = try std.ArrayList(*Actor).initCapacity(alloc, actors.items.len);
    defer draw_order.deinit();

    for (actors.items) |*actor| {
        try draw_order.append(actor);
    }

    std.sort.insertionSort(*Actor, draw_order.items, {}, Actor.compare);
    for (draw_order.items) |actor| {
        const pos = geom.vec2.ftoi(actor.pos + actor.offset) - camera_pos;
        actor.image.blit(pos);
        const aabb = geom.aabb.subv(geom.rect.as_aabb(geom.rect.ftoi(actor.getRect())), camera_pos);
        if (debug) {
            w4.DRAW_COLORS.* = 0x0040;
            w4.rect(aabb[0], aabb[1], @intCast(usize, aabb[2]), @intCast(usize, aabb[3]));
        }
    }

    // Store actors to remove
    var to_remove = std.ArrayList(usize).init(alloc);
    defer to_remove.deinit();

    // Resolve hitbox/hurtbox collisions
    for (actors.items) |*actor, actorIdx| {
        for (hurtboxes.items) |box| {
            if (box.key == actorIdx) continue;
            if (geom.rect.overlapsf(box.val, actor.getRect())) {
                try to_remove.append(actorIdx);
            }
        }
    }

    std.mem.reverse(usize, to_remove.items);

    // Remove destroyed items
    for (to_remove.items) |remove| {
        _ = actors.swapRemove(remove);
    }

    if (next_room) |next| {
        playerStore = actors.items[playerIndex];
        room = next;
        try loadRoom();
    }

    if (debug) {
        w4.DRAW_COLORS.* = 0x0041;
        var chain_text: [9:0]u8 = .{ 'C', 'H', 'A', 'I', 'N', ':', ' ', ' ', 0 };
        chain_text[6] = '0' + @divTrunc(player_combat.chain, 10);
        chain_text[7] = '0' + @mod(player_combat.chain, 10);
        w4.text(&chain_text, 0, 0);
    }
}

pub fn isSolid(tile: u8) bool {
    return (tile >= 1 and tile <= 6) or (tile >= 18 and tile <= 23 and tile != 19) or (tile >= 35 and tile <= 40) or (tile >= 55 and tile <= 57) or (tile >= 72 and tile <= 74);
}

pub fn isInScreenBounds(pos: geom.Vec2) bool {
    const bounds = geom.aabb.initv(.{room.toVec() * world.room_grid_size * world.tile_size}, @splat(2, @as(i32, w4.CANVAS_SIZE)));
    return bounds.contains(pos);
}

pub fn isInMapBounds(pos: geom.Vec2) bool {
    return pos[0] >= 0 and pos[1] >= 0 and pos[0] < room.size[0] and pos[1] < room.size[1];
}

pub fn collide(which: usize, rect: geom.Rectf) CollisionInfo {
    const tile_sizef = geom.vec2.itof(world.tile_size);
    var collisions = CollisionInfo.init();

    for (actors.items) |actor, i| {
        if (which == i) continue;
        var o_rect = geom.aabb.as_rectf(geom.aabb.addvf(actor.collisionBox, actor.pos));
        if (geom.rect.overlapsf(rect, o_rect)) {
            collisions.append(actor.collisionBox);
            if (debug) w4.tracef("collision! %d", i);
        }
    }

    const roomvec = geom.vec2.itof(room.toVec2());
    const top_left_i = geom.rect.top_leftf(rect) / tile_sizef;
    const bot_right_i = top_left_i + geom.rect.sizef(rect) / tile_sizef;
    const top_left = top_left_i - roomvec;
    const bot_right = bot_right_i - roomvec;

    var i: isize = @floatToInt(i32, top_left[0]);
    while (i <= @floatToInt(i32, bot_right[0])) : (i += 1) {
        var a: isize = @floatToInt(i32, top_left[1]);
        while (a <= @floatToInt(i32, bot_right[1])) : (a += 1) {
            if (!isInMapBounds(.{ i, a })) continue;
            const x = @intCast(usize, i);
            const y = @intCast(usize, a);
            const idx = y * room.size[0] + x;
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
