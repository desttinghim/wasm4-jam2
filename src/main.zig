const w4 = @import("wasm4.zig");
const std = @import("std");
const draw = @import("draw.zig");
const geom = @import("geom.zig");
const input = @import("input.zig");
const world = @import("world.zig");
const Anim = @import("Anim.zig");

const Database = @import("database.zig");

const builtin = @import("builtin");
const debug = builtin.mode == .Debug;
const verbosity = 2;
// const debug = false;

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
const Renderable = @import("Renderable.zig");
const Combat = @import("Combat.zig");
const Health = struct {
    max: u8,
    current: u8,
    stunned: ?usize = null,
    stunTime: usize = 20,
};
const Intelligence = @import("Intelligence.zig");

const player_blit = draw.Blit.init_frame(world.player_style, &world.player_bmp, .{ .bpp = .b2 }, .{ 16, 16 }, 0);
const player_offset = geom.Vec2f{ -8, -12 };
var playerIndex: usize = undefined;
var player_combat = Combat{
    .actorImage = player_blit,
    .actorOffset = player_offset,
    .actor = undefined,
    .animator = undefined,
    .offset = geom.Vec2f{ -16, -20 },
    .image = draw.Blit.init_frame(world.player_style, &world.player_punch_bmp, .{ .bpp = .b2 }, .{ 32, 32 }, 0),
    .punch_down = .{ &world.player_anim_punch_down, &world.player_anim_punch_down2 },
    .punch_up = .{ &world.player_anim_punch_up, &world.player_anim_punch_up2 },
    .punch_side = .{ &world.player_anim_punch_side, &world.player_anim_punch_side2 },
};
var camera = geom.Vec2f{ 0, 0 };
var camera_player_pos = geom.Vec2f{ 0, 0 };
var playerStore: Actor = undefined;

var actors: std.ArrayList(Actor) = undefined;
var collectables: [][2]geom.Vec2f = &.{};
var animators: []Assoc(Anim) = undefined;
var health: []Assoc(Health) = undefined;
var intelligences: []Assoc(Intelligence) = undefined;

var db: Database = undefined;

fn Assoc(comptime T: type) type {
    return struct { key: usize, val: T };
}

var room: world.Room = undefined;

export fn start() void {
    if (debug and verbosity > 0) {
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
            .body = .Kinematic,
            .friction = 0.5,
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
    // TODO: give player a health stat
    var needs_health: usize = 0;
    var needs_combat: usize = 0;
    var needs_intelligence: usize = 0;

    // Load other entities
    for (entities) |entity| {
        const tile_sizef = geom.vec2.itof(world.tile_size);
        const pos = entity.toPos() + (tile_sizef / @splat(2, @as(f32, 2)));
        switch (entity.kind) {
            .Player => {},
            .Pot => {
                needs_health += 1;
                try actors.append(Actor{
                    .kind = entity.kind,
                    .pos = pos,
                    .last_pos = pos,
                    .collisionBox = geom.AABBf{ -3, -3, 6, 6 },
                    .offset = geom.Vec2f{ -8, -12 },
                    .image = draw.Blit.init_frame(0x0243, &world.bitmap, .{ .bpp = .b2 }, .{ 16, 16 }, world.pot),
                });
            },
            .Skeleton => {
                needs_health += 1;
                needs_intelligence += 1;
                needs_combat += 1;
                try actors.append(Actor{
                    .kind = entity.kind,
                    .pos = pos,
                    .last_pos = pos,
                    .body = .Kinematic,
                    .friction = 0.5,
                    .collisionBox = geom.AABBf{ -3, -3, 6, 6 },
                    .offset = geom.Vec2f{ -8, -12 },
                    .image = draw.Blit.init_frame(0x0243, &world.bitmap, .{ .bpp = .b2 }, .{ 16, 16 }, world.skeleton),
                });
            },
        }
    }

    // Allocate animators
    animators = try level_alloc.alloc(Assoc(Anim), needs_animator);
    health = try level_alloc.alloc(Assoc(Health), needs_health);
    intelligences = try level_alloc.alloc(Assoc(Intelligence), needs_intelligence);

    if (debug and verbosity > 0) w4.tracef("[start] Anim count %d", needs_animator);
    // Add components
    var anim_idx: usize = 0;
    var health_idx: usize = 0;
    var intelligence_idx: usize = 0;
    for (actors.items) |actor, a| {
        switch (actor.kind) {
            .Player => {
                animators[anim_idx] = .{ .key = a, .val = .{
                    .anim = &world.player_anim_walk_down,
                } };
                player_combat.animator = &animators[anim_idx].val;
                player_combat.actor = &actors.items[a];
                anim_idx += 1;
            },
            .Pot => {
                health[health_idx] = .{ .key = a, .val = .{
                    .max = 2,
                    .current = 2,
                    .stunTime = 60,
                } };
                health_idx += 1;
            },
            .Skeleton => {
                health[health_idx] = .{ .key = a, .val = .{
                    .max = 5,
                    .current = 5,
                    .stunTime = 60,
                } };
                health_idx += 1;
                intelligences[intelligence_idx] = .{ .key = a, .val = .{.follow_player = true} };
                intelligence_idx += 1;
            },
        }
    }

    // Update camera
    const bounds = geom.aabb.as_rectf(geom.aabb.itof(room.toAABB() * @splat(4, world.tile_size[0])));
    var new_camera = actors.items[playerIndex].pos - geom.Vec2f{ 80, 80 };
    if (new_camera[0] < bounds[0]) new_camera[0] = bounds[0];
    if (new_camera[1] < bounds[1]) new_camera[1] = bounds[1];
    if (new_camera[0] + 160 > bounds[2]) new_camera[0] = bounds[2] - 160;
    if (new_camera[1] + 160 > bounds[3]) new_camera[1] = bounds[3] - 160;
    camera = new_camera;
    camera_player_pos = new_camera;
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

    var hurtboxes = try std.ArrayList(Assoc(geom.Rectf)).initCapacity(alloc, 10);
    defer hurtboxes.deinit();

    var hitboxes = try std.ArrayList(Assoc(geom.Rectf)).initCapacity(alloc, 10);
    defer hitboxes.deinit();

    var next_room: ?world.Room = null;

    // Update player
    {
        // Input
        var player = &actors.items[playerIndex];
        player.motive = false;
        var input_vector = geom.Vec2f{ 0, 0 };

        if (input.btn(.one, .up)) input_vector += geom.Vec2f{ 0, -1 };
        if (input.btn(.one, .left)) input_vector += geom.Vec2f{ -1, 0 };
        if (input.btn(.one, .right)) input_vector += geom.Vec2f{ 1, 0 };
        if (input.btn(.one, .down)) input_vector += geom.Vec2f{ 0, 1 };

        input_vector = geom.vec2.normalizef(input_vector);

        if (!player_combat.is_attacking) {
            player.move(input_vector);
            if (player.motive and player_combat.is_attacking) player_combat.endAttack();
            if (input.btnp(.one, .z)) player_combat.startAttack(time);
        } else if (!player_combat.animator.interruptable) {
            // player.pos += player.facing.getVec2f() * @splat(2, speed);
        } else {
            if (geom.Direction.fromVec2f(input_vector)) |facing| {
                player.facing = facing;
            }
            const delta = time - player_combat.last_attacking;
            if (delta > 25 and input.btnp(.one, .z)) player_combat.startAttack(time);
            if (delta > 40) player_combat.endAttack();
        }

        for (intelligences) |*intAssoc| {
            const intelligence = &intAssoc.val;
            const actor = &actors.items[intAssoc.key];
            if (actor.kind != .Skeleton) continue;
            const player_dir = geom.vec2.normalizef(player.pos - actor.pos);
            const view = geom.vec2.dot(player_dir, actor.facing.getVec2f());
            if (view > 0.5) {
                intelligence.player_in_view = true;
            }
            if (intelligence.player_in_view and intelligence.follow_player) {
                if ( geom.vec2.distf(actor.pos, player.pos) > intelligence.approach_distance) {
                    actor.move(player_dir);
                } else {
                    actor.facing = geom.Direction.fromVec2f(player_dir) orelse actor.facing;
                }
            }
        }

        {
            // Camera
            const bounds = geom.aabb.as_rectf(geom.aabb.itof(room.toAABB() * @splat(4, world.tile_size[0])));
            const centered_camera = player.pos - geom.Vec2f{ 80, 80 };
            var move_dist = geom.vec2.distf(player.pos, camera_player_pos);
            const scale = @minimum(1.0, move_dist / 40);
            const ideal_camera = centered_camera + (player.facing.getVec2f() * geom.Vec2f{ 40, 40 });
            var scaled_camera = centered_camera + (player.facing.getVec2f() * geom.Vec2f{ 40, 40 } * @splat(2, scale));

            if (scaled_camera[0] < bounds[0]) scaled_camera[0] = bounds[0];
            if (scaled_camera[1] < bounds[1]) scaled_camera[1] = bounds[1];
            if (scaled_camera[0] + 160 > bounds[2]) scaled_camera[0] = bounds[2] - 160;
            if (scaled_camera[1] + 160 > bounds[3]) scaled_camera[1] = bounds[3] - 160;

            const camera_to_ideal = geom.vec2.distf(camera, ideal_camera);
            const scaled_to_ideal = geom.vec2.distf(scaled_camera, ideal_camera);
            const centered_to_scaled = geom.vec2.distf(centered_camera, scaled_camera);
            const centered_to_camera = geom.vec2.distf(centered_camera, camera);
            if (centered_to_camera < centered_to_scaled or scaled_to_ideal < camera_to_ideal) {
                camera = geom.vec2.lerp(camera, scaled_camera, 0.1);
            }
            if (!(player.motive and player.isMoving())) {
                camera_player_pos = player.pos;
            }

            const size = geom.aabb.sizef(player.collisionBox);
            const left = (player.pos[0] < bounds[0] + size[0]);
            const up = (player.pos[1] - size[1] < bounds[1]);
            const right = (player.pos[0] > bounds[2] - size[0]);
            const down = (player.pos[1] > bounds[3]);
            if (left or up or right or down) {
                next_room = db.getRoomContaining(player.toGrid());
                if (next_room) |next| {
                    if (room.toID() == next.toID()) next_room = null;
                }
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

        // Animation
        var animator = player_combat.animator;
        if (player.motive and animator.interruptable) {
            switch (player.facing) {
                .Northwest, .Northeast, .North => animator.play(&world.player_anim_walk_up),
                .Southwest, .Southeast, .South => animator.play(&world.player_anim_walk_down),
                .West => {
                    player.image.flags.flip_x = true;
                    animator.play(&world.player_anim_walk_side);
                },
                .East => {
                    player.image.flags.flip_x = false;
                    animator.play(&world.player_anim_walk_side);
                },
            }
        } else {
            if (!player_combat.is_attacking) {
                switch (player.facing) {
                    .Northwest, .Northeast, .North => animator.play(&world.player_anim_stand_up),
                    .Southwest, .Southeast, .South => animator.play(&world.player_anim_stand_down),
                    .West, .East => animator.play(&world.player_anim_stand_side),
                }
            }
        }
    }

    for (actors.items) |*actor, actorIndex| {
        if (actor.body != .Rigid) continue;
        const as_rectf = geom.aabb.as_rectf;
        const addvf = geom.aabb.addvf;
        const hcols = collide(actorIndex, as_rectf(addvf(actor.collisionBox, geom.Vec2f{ actor.pos[0], actor.last_pos[1] })));
        const vcols = collide(actorIndex, as_rectf(addvf(actor.collisionBox, geom.Vec2f{ actor.last_pos[0], actor.pos[1] })));
        var allcols = try std.ArrayList(usize).initCapacity(alloc, 9);

        for (hcols.iterWhich()) |which| {
            if (which != .body) continue;
            try allcols.append(which.body);
        }
        vcol: for (vcols.iterWhich()) |which| {
            if (which != .body) continue;
            for (allcols.items) |which2| {
                if (which.body == which2) continue :vcol;
            }
            try allcols.append(which.body);
        }

        var velocity = (actor.pos - actor.last_pos) * @splat(2, @as(f32, actor.friction));
        for (allcols.items) |body| {
            const other = &actors.items[body];
            if (other.body == .Rigid) {
                other.pos += velocity / @splat(2, @as(f32, 2));
            } else {
                actor.pos -= velocity / @splat(2, @as(f32, 2));
            }
        }
    }

    for (actors.items) |*actor, actorIndex| {
        // Collision
        const as_rectf = geom.aabb.as_rectf;
        const addvf = geom.aabb.addvf;
        const hcols = collide(actorIndex, as_rectf(addvf(actor.collisionBox, geom.Vec2f{ actor.pos[0], actor.last_pos[1] })));
        const vcols = collide(actorIndex, as_rectf(addvf(actor.collisionBox, geom.Vec2f{ actor.last_pos[0], actor.pos[1] })));
        switch (actor.body) {
            .Rigid, .Kinematic => {
                if (hcols.len > 0) actor.pos[0] = actor.last_pos[0];
                if (vcols.len > 0) actor.pos[1] = actor.last_pos[1];
            },
            .Static => {},
        }

        // Kinematics
        const velocity = (actor.pos - actor.last_pos) * @splat(2, @as(f32, actor.friction));
        actor.last_pos = actor.pos;
        actor.pos += velocity;

        switch (actor.kind) {
            .Pot => {
                try hitboxes.append(.{ .key = actorIndex, .val = actor.getRect() });
            },
            .Skeleton => {
                try hitboxes.append(.{ .key = actorIndex, .val = actor.getRect() });
            },
            .Player => {},
        }
    }

    if (player_combat.getHurtbox()) |hurtbox| {
        try hurtboxes.append(.{ .key = playerIndex, .val = geom.aabb.as_rectf(geom.aabb.addvf(hurtbox, actors.items[playerIndex].pos)) });
    }

    for (collectables) |*collectable| {
        // Kinematics
        const velocity = (collectable[0] - collectable[1]) * @splat(2, @as(f32, 0.8));
        collectable[1] = collectable[0];
        collectable[0] += velocity;
    }

    // Store actors to remove
    var to_remove = std.ArrayList(usize).init(alloc);
    defer to_remove.deinit();

    // Update health
    for (health) |*h| {
        if (h.val.stunned) |startTime| {
            if (time - startTime > h.val.stunTime) {
                h.val.stunned = null;
            }
        }
    }

    // Resolve hitbox/hurtbox collisions
    for (hitboxes.items) |hitbox| {
        for (hurtboxes.items) |hurtbox| {
            if (hurtbox.key == hitbox.key) continue;
            if (geom.rect.overlapsf(hurtbox.val, hitbox.val)) {
                for (health) |*h| {
                    if (h.key != hitbox.key) continue;
                    if (h.val.stunned) |_| break;
                    h.val.current -= 1;
                    h.val.stunned = time;
                    if (h.val.current == 0) {
                        try to_remove.append(h.key);
                    }
                    const taker = &actors.items[hitbox.key];
                    const hitter = &actors.items[hurtbox.key];
                    const add = taker.pos - hitter.pos;
                    const max = geom.vec2.normalizef(add) * @splat(2, @as(f32, 4));
                    const vel = @minimum(max, add / @splat(2, @as(f32, 3)));
                    taker.pos += vel;
                    if (debug and verbosity > 1) w4.tracef("[hit] taker (%d, %d)", @floatToInt(i32, taker.pos[0]), @floatToInt(i32, taker.pos[1]));
                    if (debug and verbosity > 1) w4.tracef("[hit] hitter (%d, %d)", @floatToInt(i32, hitter.pos[0]), @floatToInt(i32, hitter.pos[1]));
                    if (debug and verbosity > 1) w4.tracef("[hit] velocity (%d, %d)", @floatToInt(i32, vel[0]), @floatToInt(i32, vel[1]));
                }
            }
        }
    }

    // Remove actors in reverse
    var new_collectables = try alloc.alloc([2]geom.Vec2f, collectables.len + to_remove.items.len);

    if (debug and verbosity > 0 and input.btnp(.one, .x)) {
        for (health) |h, i| {
            w4.tracef("[debug] health %d, key=%d", i, h.key);
        }
        for (actors.items) |a, i| {
            w4.tracef("[debug] actor %d, kind=%s", i, @tagName(a.kind).ptr);
        }
    }

    var collectCount: usize = 0;
    if (debug and verbosity > 1 and to_remove.items.len > 0) w4.tracef("[remove] start");
    while (to_remove.popOrNull()) |remove| {
        // Remove destroyed items
        if (debug and verbosity > 1) w4.tracef("[remove] %d of %d", remove, actors.items.len);
        const actor = actors.swapRemove(remove);
        for (health) |h, i| {
            if (h.key == remove) {
                if (i != health.len - 1) {
                    std.mem.swap(Assoc(Health), &health[i], &health[health.len - 1]);
                }
                health = health[0 .. health.len - 1];
                if (debug and verbosity > 0) w4.tracef("[remove] remove health %d, remove=%d, key=%d", i, remove, h.key);
                if (debug and verbosity > 0) w4.tracef("[remove] health_len=%d", health.len);
                break;
            }
        }
        for (health) |h, i| {
            if (h.key == actors.items.len) {
                health[i].key = remove;
            }
        }
        for (intelligences) |h, i| {
            if (h.key == remove) {
                if (i != intelligences.len - 1) {
                    std.mem.swap(Assoc(Intelligence), &intelligences[i], &intelligences[intelligences.len - 1]);
                }
                intelligences = intelligences[0 .. intelligences.len - 1];
                if (debug and verbosity > 0) w4.tracef("[remove] remove intelligences %d, remove=%d, key=%d", i, remove, h.key);
                if (debug and verbosity > 0) w4.tracef("[remove] intelligences_len=%d", intelligences.len);
                break;
            }
        }
        for (intelligences) |h, i| {
            if (h.key == actors.items.len) {
                intelligences[i].key = remove;
            }
        }
        // Add their position to collectables
        new_collectables[collectCount] = .{ actor.pos, actor.last_pos };
        collectCount += 1;
    }

    for (collectables) |collectable| {
        new_collectables[collectCount] = collectable;
        const player = actors.items[playerIndex].pos;
        const dist = geom.vec2.distf(collectable[0], player);
        if (dist < 8) {
            try to_remove.append(collectCount);
            continue;
        } else if (dist < 48) {
            const towards = geom.vec2.normalizef(player - collectable[0]);
            new_collectables[collectCount][0] += towards * @splat(2, @as(f32, 2.0));
        }
        collectCount += 1;
    }

    // Remove collectables in reverse
    while (to_remove.popOrNull()) |remove| {
        std.mem.swap([2]geom.Vec2f, &new_collectables[remove], &new_collectables[new_collectables.len - 1]);
        new_collectables = new_collectables[0 .. collectables.len - 1];
    }

    collectables = new_collectables;

    if (next_room) |next| {
        playerStore = actors.items[playerIndex];
        room = next;
        try loadRoom();
    }

    try render(alloc);

    if (debug) {
        for (hitboxes.items) |hitbox| {
            const aabb = geom.aabb.ftoi(geom.aabb.subvf(geom.rect.as_aabbf(hitbox.val), camera));
            w4.DRAW_COLORS.* = 0x0040;
            w4.rect(aabb[0], aabb[1], @intCast(usize, aabb[2]), @intCast(usize, aabb[3]));
        }
        for (hurtboxes.items) |hurtbox| {
            const aabb = geom.aabb.ftoi(geom.aabb.subvf(geom.rect.as_aabbf(hurtbox.val), camera));
            w4.DRAW_COLORS.* = 0x0040;
            w4.rect(aabb[0], aabb[1], @intCast(usize, aabb[2]), @intCast(usize, aabb[3]));
        }
    }

    if (debug) {
        w4.DRAW_COLORS.* = 0x0041;
        var chain_text: [9:0]u8 = .{ 'C', 'H', 'A', 'I', 'N', ':', ' ', ' ', 0 };
        chain_text[6] = '0' + @divTrunc(player_combat.chain, 10);
        chain_text[7] = '0' + @mod(player_combat.chain, 10);
        w4.text(&chain_text, 0, 0);
    }
}

fn render(alloc: std.mem.Allocator) !void {
    // Render background tiles
    w4.DRAW_COLORS.* = 0x1234;
    const camera_pos = geom.vec2.ftoi(camera);
    var x: isize = 0;
    while (x < room.size[0]) : (x += 1) {
        var y: isize = 0;
        while (y < room.size[1]) : (y += 1) {
            const idx = @intCast(usize, y * @intCast(i16, room.size[0]) + x);
            world.blit((geom.Vec2{ x, y } + room.toVec2()) * world.tile_size - camera_pos, room.tiles[idx]);
        }
    }

    // Animate!
    for (animators) |*anim| {
        var actor = &actors.items[anim.key];
        anim.val.update(&actor.image.frame, &actor.image.flags);
    }

    // Sort all entities by y
    var draw_order = try std.ArrayList(Renderable).initCapacity(alloc, actors.items.len + collectables.len);
    defer draw_order.deinit();

    addRenderableActor: for (actors.items) |*actor, idx| {
        for (health) |*h| {
            if (h.key != idx) continue;
            if (h.val.stunned) |_| {
                if (time % 10 < 4) {
                    continue :addRenderableActor;
                }
            }
        }
        try draw_order.append(Renderable{ .kind = .{ .Actor = actor } });
    }

    for (collectables) |collectable| {
        try draw_order.append(.{ .kind = .{ .Particle = collectable[0] } });
    }

    std.sort.insertionSort(Renderable, draw_order.items, {}, Renderable.compare);

    //  Render entities
    for (draw_order.items) |renderable| {
        switch (renderable.kind) {
            .Actor => |actor| {
                const pos = geom.vec2.ftoi(actor.pos + actor.offset - camera);
                actor.image.blit(pos);
                const aabb = geom.aabb.ftoi(geom.aabb.subvf(actor.getAABB(), camera));
                if (debug) {
                    w4.DRAW_COLORS.* = 0x0040;
                    w4.rect(aabb[0], aabb[1], @intCast(usize, aabb[2]), @intCast(usize, aabb[3]));
                }
            },
            .Particle => |p| {
                w4.DRAW_COLORS.* = 0x0234;
                world.blit(geom.vec2.ftoi(p) - camera_pos, world.heart);
            },
        }
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
            collisions.append(actor.collisionBox, .{ .body = i });
            if (debug and verbosity > 2) w4.tracef("collision! %d", i);
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
                collisions.append(geom.aabb.initvf(tilepos, tile_sizef), .static);
            }
        }
    }

    return collisions;
}

pub const CollisionInfo = struct {
    len: usize,
    items: [9]geom.AABBf,
    which: [9]BodyInfo,

    const BodyInfo = union(enum) { static, body: usize };

    pub fn init() CollisionInfo {
        return CollisionInfo{
            .len = 0,
            .items = undefined,
            .which = undefined,
        };
    }

    pub fn iterWhich(col: CollisionInfo) []const BodyInfo {
        return col.which[0..col.len];
    }

    pub fn append(col: *CollisionInfo, item: geom.AABBf, body: BodyInfo) void {
        std.debug.assert(col.len < 9);
        col.items[col.len] = item;
        col.which[col.len] = body;
        col.len += 1;
    }
};
