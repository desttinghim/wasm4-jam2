const w4 = @import("wasm4.zig");
const draw = @import("draw.zig");
const std = @import("std");
const geom = @import("geom.zig");
const input = @import("input.zig");
const world = @import("world.zig");
const Anim = @import("Anim.zig");

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

var actors: []Actor = undefined;
const AnimStore = struct { owns: usize, anim: Anim };
var animators: []AnimStore = undefined;

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
        actors = try long_alloc.alloc(Actor, entity_count);
        var needs_animator: usize = 0;
        var i: usize = 0;
        while (i < entity_count) : (i += 1) {
            const entity = try world.Entity.read(reader);
            const tile_sizef = geom.vec2.itof(world.tile_size);
            const pos = entity.toPos() * tile_sizef + (tile_sizef / @splat(2, @as(f32, 2)));
            if (entity.kind == .Player) {
                needs_animator += 1;
                actors[i] = Actor{
                    .kind = entity.kind,
                    .pos = pos,
                    .last_pos = pos,
                    .collisionBox = geom.AABBf{ -4, -4, 8, 8 },
                    .offset = geom.Vec2f{ -8, -12 },
                    .image = player_blit,
                };
                player_combat.actor = &actors[i];
                w4.tracef("[start] playerIndex %d", i);
            } else {
                actors[i] = Actor{
                    .kind = entity.kind,
                    .pos = pos,
                    .last_pos = pos,
                    .collisionBox = geom.AABBf{ -4, -4, 8, 8 },
                    .offset = geom.Vec2f{ -8, -12 },
                    .image = draw.Blit.init_frame(0x0234, &world.bitmap, .{ .bpp = .b2 }, .{ 16, 16 }, world.pot),
                };
            }
        }

        // Add animator components
        animators = try long_alloc.alloc(AnimStore, needs_animator);
        var idx: usize = 0;
        for (actors) |actor| {
            if (actor.kind == .Player) {
                animators[idx] = .{ .owns = idx, .anim = .{
                    .anim = &world.player_anim_walk_down,
                } };
                player_combat.animator = &animators[idx].anim;
                idx += 1;
            }
        }
    }
    {
        const room_count = try reader.readInt(u8, .Little);
        w4.tracef("%d", room_count);
        room = try world.Room.read(long_alloc, reader);
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

    {
        // Input
        var player = &actors[playerIndex];
        player.motive = false;
        const speed: f32 = 60.0 / 60.0;
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
    var x: isize = 0;
    while (x < 10) : (x += 1) {
        var y: isize = 0;
        while (y < 10) : (y += 1) {
            const idx = @intCast(usize, y * 10 + x);
            world.blit(geom.Vec2{ x, y } * world.tile_size, room.tiles[idx]);
        }
    }

    for (animators) |*store| {
        var actor = &actors[store.owns];
        store.anim.update(&actor.image.frame, &actor.image.flags);
    }

    for (actors) |*actor| {
        actor.render();
        const aabb = geom.aabb.addvf(actor.collisionBox, actor.pos);
        w4.DRAW_COLORS.* = 0x4444;
        w4.rect(@floatToInt(i32, aabb[0]), @floatToInt(i32, aabb[1]), @floatToInt(usize, aabb[2]), @floatToInt(usize, aabb[3]));
    }

    w4.DRAW_COLORS.* = 0x0041;
    var chain_text: [9:0]u8 = .{ 'C', 'H', 'A', 'I', 'N', ':', ' ', ' ', 0 };
    chain_text[6] = '0' + @divTrunc(player_combat.chain, 10);
    chain_text[7] = '0' + @mod(player_combat.chain, 10);
    w4.text(&chain_text, 0, 0);
}

pub fn isSolid(tile: u8) bool {
    return (tile >= 1 and tile <= 6) or (tile >= 18 and tile <= 23 and tile != 19) or (tile >= 35 and tile <= 40) or (tile >= 55 and tile <= 57) or (tile >= 72 and tile <= 74);
}

pub fn isInScreenBounds(x: i32, y: i32) bool {
    return x >= 0 and y >= 0 and x < w4.CANVAS_SIZE and y < w4.CANVAS_SIZE;
}

pub fn isInMapBounds(x: i32, y: i32) bool {
    return x >= 0 and y >= 0 and x < 10 and y < 10;
}

pub fn collide(which: usize, rect: geom.Rectf) CollisionInfo {
    const tile_sizef = geom.vec2.itof(world.tile_size);
    var collisions = CollisionInfo.init();

    for (actors) |actor, i| {
        if (which == i) continue;
        var o_rect = geom.aabb.as_rectf(geom.aabb.addvf(actor.collisionBox, actor.pos));
        if (geom.rect.overlapsf(rect, o_rect)) {
            collisions.append(actor.collisionBox);
            w4.tracef("collision! %d", i);
        }
    }

    const top_left = geom.rect.top_leftf(rect) / tile_sizef;
    const bot_right = top_left + geom.rect.sizef(rect) / tile_sizef;

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
