const w4 = @import("wasm4.zig");
const std = @import("std");
const draw = @import("draw.zig");
const geom = @import("geom.zig");
const input = @import("input.zig");
const world = @import("world.zig");
const audio = @import("audio.zig");
const main = @import("main.zig");

var music_data = @embedFile(@import("world_data").music);
const Database = @import("database.zig");

const settings = @import("settings.zig");
const debug = settings.debug;
const verbosity = settings.verbosity;

const FBA = std.heap.FixedBufferAllocator;

var long_alloc_buffer: [4096]u8 = undefined;
var long_fba = FBA.init(&long_alloc_buffer);
const long_alloc = long_fba.allocator();

var level_alloc_buffer: [16384]u8 = undefined;
var level_fba = FBA.init(&level_alloc_buffer);
const level_alloc = level_fba.allocator();

var frame_alloc_buffer: [2][4096]u8 = undefined;
var frame_fba: [2]FBA = .{
    FBA.init(&frame_alloc_buffer[0]),
    FBA.init(&frame_alloc_buffer[1]),
};
const frame_alloc: [2]std.mem.Allocator = .{
    frame_fba[0].allocator(),
    frame_fba[1].allocator(),
};

// Associative array
const Assoc = @import("assoc.zig").Assoc;

// Components
const Anim = @import("components/Anim.zig");
const Actor = @import("components/Actor.zig");
const Combat = @import("components/Combat.zig");
const Health = @import("components/Health.zig");
const Renderable = @import("components/Renderable.zig");
const Intelligence = @import("components/Intelligence.zig");

var actors: std.ArrayList(Actor) = undefined;
// var collectable_list: std.ArrayList([2]geom.Vec2f) = undefined;
var collectables: [][2]geom.Vec2f = &.{};
var animators: []Assoc(Anim) = undefined;
var health: []Assoc(Health) = undefined;
var intelligences: []Assoc(Intelligence) = undefined;
var combats: []Assoc(Combat) = undefined;

var playerIndex: usize = undefined;
var bounds: geom.Rectf = undefined;
var camera = geom.Vec2f{ 0, 0 };
var camera_player_pos = geom.Vec2f{ 0, 0 };
var playerStore: Actor = undefined;
var heart_count: usize = 0;

var db: Database = undefined;
// var wae: audio.music.WAE = undefined;

var room: world.Room = undefined;

pub fn start() !void {
    db = try Database.init(long_alloc);
    // const music = try audio.music.Context.init(music_data);
    // wae = audio.music.WAE.init(music);
    // wae.playSong(0);

    var spawn: world.Entity = db.getSpawn() orelse return error.PlayerNotFound;
    room = db.getRoomContaining(spawn.toVec()) orelse return error.RoomNotFound;

    // Create player
    {
        const tile_sizef = geom.vec2.itof(world.tile_size);
        const pos = spawn.toPos() + (tile_sizef / @splat(2, @as(f32, 2)));
        playerStore = Actor.init(&Actor.Template.Player, pos);
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
    var needs_animator: usize = 0;
    var needs_health: usize = 0;
    var needs_combat: usize = 0;
    var needs_intelligence: usize = 0;
    var player_spawn = false;

    // Load other entities
    for (entities) |entity| {
        const tile_sizef = geom.vec2.itof(world.tile_size);
        const pos = entity.toPos() + (tile_sizef / @splat(2, @as(f32, 2)));
        switch (entity.kind) {
            .Player => {
                player_spawn = true;
                needs_health += 1;
                needs_animator += 1;
                needs_combat += 1;
            },
            .Pot => {
                needs_health += 1;
                try actors.append(Actor.init(&Actor.Template.Pot, pos));
            },
            .Skeleton => {
                needs_health += 1;
                needs_intelligence += 1;
                needs_combat += 1;
                try actors.append(Actor.init(&Actor.Template.Skeleton, pos));
            },
        }
    }

    if (!player_spawn) {
        needs_health += 1;
        needs_animator += 1;
        needs_combat += 1;
    }

    // Allocate animators
    health = try level_alloc.alloc(Assoc(Health), needs_health);
    combats = try level_alloc.alloc(Assoc(Combat), needs_combat);
    animators = try level_alloc.alloc(Assoc(Anim), needs_animator);
    intelligences = try level_alloc.alloc(Assoc(Intelligence), needs_intelligence);

    if (debug and verbosity > 0) w4.tracef("[start] Anim count %d", needs_animator);
    // Add components
    var anim_idx: usize = 0;
    var health_idx: usize = 0;
    var intelligence_idx: usize = 0;
    var combat_idx: usize = 0;
    for (actors.items) |actor, a| {
        switch (actor.template.kind) {
            .Player => {
                animators[anim_idx] = .{ .key = a, .val = .{
                    .anim = &world.player_anim_walk_down,
                    .template = &Actor.Template.Player,
                } };
                anim_idx += 1;
                health[health_idx] = .{ .key = a, .val = .{
                    .max = 10,
                    .current = 10,
                    .stunTime = 60,
                    .hitbox = .{ -4, -4, 8, 8 },
                } };
                health_idx += 1;
                combats[combat_idx] = .{ .key = a, .val = Combat{
                    .actor = &actors.items[a],
                    .anim_template = &world.PlayerAnimCombatTemplate,
                    .template = &Actor.Template.PlayerAttack,
                    .hurtbox_vertical = .{ -8, -8, 16, 12 },
                    .hurtbox_horizontal = .{ -4, -10, 12, 16 },
                } };
                combat_idx += 1;
            },
            .Pot => {
                health[health_idx] = .{ .key = a, .val = .{
                    .max = 2,
                    .current = 2,
                    .stunTime = 60,
                    .hitbox = .{ -4, -4, 8, 8 },
                } };
                health_idx += 1;
            },
            .Skeleton => {
                health[health_idx] = .{ .key = a, .val = .{
                    .max = 2,
                    .current = 2,
                    .stunTime = 60,
                    .hitbox = .{ -4, -4, 8, 8 },
                } };
                health_idx += 1;
                intelligences[intelligence_idx] = .{ .key = a, .val = .{
                    .follow_player = true,
                } };
                intelligence_idx += 1;
                combats[combat_idx] = .{ .key = a, .val = Combat{
                    .actor = &actors.items[a],
                    .anim_template = &world.SkeletonAnimCombatTemplate,
                    .template = &Actor.Template.Skeleton,
                    .hurtbox_vertical = .{ -8, -8, 16, 12 },
                    .hurtbox_horizontal = .{ -4, -10, 12, 16 },
                } };
                combat_idx += 1;
            },
        }
    }

    // Update camera
    bounds = geom.aabb.as_rectf(geom.aabb.itof(room.toAABB() * @splat(4, world.tile_size[0])));
    var new_camera = actors.items[playerIndex].pos - geom.Vec2f{ 80, 80 };
    if (new_camera[0] < bounds[0]) new_camera[0] = bounds[0];
    if (new_camera[1] < bounds[1]) new_camera[1] = bounds[1];
    if (new_camera[0] + 160 > bounds[2]) new_camera[0] = bounds[2] - 160;
    if (new_camera[1] + 160 > bounds[3]) new_camera[1] = bounds[3] - 160;
    camera = new_camera;
    camera_player_pos = new_camera;
}

pub fn update(time: usize) !void {

    // Update audio engine
    // wae.update();

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

    // Actor update
    for (actors.items) |*actor| {
        actor.bounced = false;
        actor.motive = false;
        actor.input_vector = geom.Vec2f{ 0, 0 };
        if (actor.stunned) |stunTime| {
            if (time - stunTime > actor.template.stunPeriod) {
                actor.stunned = null;
                actor.friction = 0.5;
            }
        }
    }

    // Update player
    {
        // Input
        var player = &actors.items[playerIndex];
        var input_vector = geom.Vec2f{ 0, 0 };

        if (input.btn(.one, .up)) input_vector += geom.Vec2f{ 0, -1 };
        if (input.btn(.one, .left)) input_vector += geom.Vec2f{ -1, 0 };
        if (input.btn(.one, .right)) input_vector += geom.Vec2f{ 1, 0 };
        if (input.btn(.one, .down)) input_vector += geom.Vec2f{ 0, 1 };

        input_vector = geom.vec2.normalizef(input_vector);
        var player_combat = &combats[Assoc(Combat).get(combats, playerIndex).?].val;
        // var player_animator = &animators[Assoc(Anim).get(animators, playerIndex).?].val;

        if (!player_combat.is_attacking) {
            player.input_vector = input_vector;
            if (input.btnp(.one, .z)) {
                player_combat.startAttack(time);
                audio.punch.play();
            }
        } else if (!player_combat.isInterruptable(time)) {
            player.input_vector = player.facing.getVec2f();
        } else {
            if (geom.Direction.fromVec2f(input_vector)) |facing| {
                player.facing = facing;
            }
            if (input.btnp(.one, .z)) {
                player_combat.startAttack(time);
                var punch = audio.punch;
                punch.fstart += player_combat.chain;
                punch.play();
            }
            if (player_combat.isOver(time)) player_combat.endAttack();
        }

        for (intelligences) |*intAssoc| {
            const intelligence = &intAssoc.val;
            const actor = &actors.items[intAssoc.key];
            // TODO
            if (actor.template.kind != .Skeleton) continue;
            const player_dir = geom.vec2.normalizef(player.pos - actor.pos);
            const player_dist = geom.vec2.distf(actor.pos, player.pos);
            const view = geom.vec2.dot(player_dir, (intelligence.player_dir orelse actor.facing).getVec2f());
            var int_input_vector = geom.Vec2f{ 0, 0 };
            if (intelligence.track_player) {
                if (view > 0) {
                    if (view > 0.5) {
                        intelligence.player_dir = geom.Direction.fromVec2f(player_dir);
                    }
                } else {
                    intelligence.player_dir = null;
                    // TODO add field to intelligence
                    if (player_dist < intelligence.track_omni_dist) intelligence.player_dir = geom.Direction.fromVec2f(player_dir);
                }
            }
            var attacking = false;
            var attack_ready = false;
            var combat_idx_opt = Assoc(Combat).get(combats, intAssoc.key);
            if (combat_idx_opt) |combat_idx| {
                var combat = &combats[combat_idx].val;
                attack_ready = time - combat.last_attacking > intelligence.attack_cooldown;
                if (!combat.is_attacking) {
                    if (intelligence.player_dir) |_| {
                        if (player_dist < intelligence.attack_distance and attack_ready) {
                            attacking = true;
                            combat.startAttack(time);
                        }
                    }
                } else {
                    attacking = true;
                    if (combat.isOver(time)) combat.endAttack();
                }
            }
            if (intelligence.follow_player) {
                if (intelligence.player_dir) |dir| {
                    if (player_dist > intelligence.approach_distance or attack_ready) {
                        int_input_vector = dir.getVec2f();
                    } else if (player_dist < intelligence.backup_distance and !attacking) {
                        int_input_vector = -dir.getVec2f();
                    }
                }
            }
            for (intelligences) |otherAssoc| {
                if (otherAssoc.key == intAssoc.key) continue;
                const other = actors.items[otherAssoc.key];
                if (geom.vec2.distf(actor.pos, other.pos) < 16) {
                    int_input_vector = geom.vec2.normalizef(actor.pos - other.pos);
                    if (intelligence.player_dir) |_| {
                        const cw = geom.vec2.perpendicularCWf(player_dir);
                        const ws = geom.vec2.perpendicularWSf(player_dir);
                        int_input_vector = if (geom.vec2.dot(cw, int_input_vector) > 0.5) cw else ws;
                    }
                    break;
                }
            }
            actor.input_vector = int_input_vector;
        }

        for (actors.items) |*actor| {
            actor.move();
        }

        {
            // Camera
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

            const size = geom.aabb.sizef(player.template.collisionBox);
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
                player.pos[0] = bounds[2] + size[0];
                player.last_pos = player.pos;
            }
            if (next_room != null and down) {
                player.pos[1] = bounds[3] + 16;
                player.last_pos = player.pos;
            }
        }
    }

    for (animators) |*anim| {
        // Animation
        var animator = &anim.val;
        var actor = &actors.items[anim.key];
        var animation_chosen = false;
        var combat_idx_opt = Assoc(Combat).get(combats, anim.key);
        if (combat_idx_opt) |combat_idx| {
            var combat = &combats[combat_idx].val;
            animation_chosen = !combat.isOver(time);
            if (combat.is_attacking and actor.template != combat.template) {
                actor.setTemplate(combat.template);
                if (actor.facing == .South) {
                    animator.play(combat.anim_template.punch_down[combat.last_attack]);
                    actor.image.flags.flip_x = combat.last_attack == 1;
                } else if (combat.actor.facing == .North) {
                    animator.play(combat.anim_template.punch_up[combat.last_attack]);
                    actor.image.flags.flip_x = combat.last_attack == 1;
                } else {
                    animator.play(combat.anim_template.punch_side[combat.last_attack]);
                    actor.image.flags.flip_x = actor.facing == .West or actor.facing == .Northwest or actor.facing == .Southwest;
                }
            } else if (combat.isOver(time) and actor.template != animator.template) {
                actor.setTemplate(animator.template);
            }
        }
        if (!animation_chosen) {
            actor.image.flags.flip_x = actor.facing == .West or actor.facing == .Northwest or actor.facing == .Southwest;
        }
        if (!animation_chosen and actor.motive and animator.interruptable) {
            animation_chosen = true;
            switch (actor.facing) {
                .Northwest, .Northeast, .North => animator.play(actor.template.animation.walk_up),
                .Southwest, .Southeast, .South => animator.play(actor.template.animation.walk_down),
                .West => {
                    animator.play(actor.template.animation.walk_side);
                },
                .East => {
                    actor.image.flags.flip_x = false;
                    animator.play(actor.template.animation.walk_side);
                },
            }
        }
        if (!animation_chosen) {
            switch (actor.facing) {
                .Northwest, .Northeast, .North => animator.play(actor.template.animation.stand_up),
                .Southwest, .Southeast, .South => animator.play(actor.template.animation.stand_down),
                .West, .East => animator.play(actor.template.animation.stand_side),
            }
        }
    }

    var colList = try std.ArrayList(usize).initCapacity(alloc, 5);
    defer colList.deinit();
    for (actors.items) |*actor, actorIndex| {
        if (actor.template.body == .Static) continue;
        const as_rectf = geom.aabb.as_rectf;
        const addvf = geom.aabb.addvf;

        // Don't process collision if in air
        if (actor.isInAir()) continue;

        try collideBodies(&colList, as_rectf(addvf(actor.template.collisionBox, actor.pos)), actorIndex);
        defer colList.items.len = 0;

        switch (actor.template.body) {
            .Rigid => {
                actor.bounced = true;
                for (colList.items) |which| {
                    const other = &actors.items[which];
                    const penetration = geom.rect.penetration(actor.getRect(), other.getRect());
                    if (other.template.body == .Rigid) {
                        other.pos += penetration / @splat(2, @as(f32, 2.0));
                        actor.pos -= penetration / @splat(2, @as(f32, 2.0));
                    } else {
                        actor.pos -= penetration;
                    }
                }
            },
            .Kinematic => {
                for (colList.items) |which| {
                    const other = &actors.items[which];
                    actor.pos += geom.vec2.normalizef(actor.pos - other.pos); // geom.rect.penetration(actor.getRect(), other.getRect());
                }
            },
            .Static => {},
        }
    }

    for (actors.items) |*actor| {
        // Collision
        const as_rectf = geom.aabb.as_rectf;
        const addvf = geom.aabb.addvf;
        const hcols = collide(as_rectf(addvf(actor.template.collisionBox, geom.Vec2f{ actor.pos[0], actor.last_pos[1] })));
        const vcols = collide(as_rectf(addvf(actor.template.collisionBox, geom.Vec2f{ actor.last_pos[0], actor.pos[1] })));
        switch (actor.template.body) {
            .Rigid => {
                if (hcols.len > 0) {
                    actor.bounced = true;
                    actor.pos[0] = actor.last_pos[0];
                }
                if (vcols.len > 0) {
                    actor.bounced = true;
                    actor.pos[1] = actor.last_pos[1];
                }
                const cols = collide(as_rectf(addvf(actor.template.collisionBox, actor.pos)));
                if (cols.len > 0) {
                    actor.bounced = true;
                    actor.pos = actor.last_pos;
                }
            },
            .Kinematic => {
                if (hcols.len > 0) actor.pos[0] = actor.last_pos[0];
                if (vcols.len > 0) actor.pos[1] = actor.last_pos[1];
                const cols = collide(as_rectf(addvf(actor.template.collisionBox, actor.pos)));
                if (cols.len > 0) {
                    actor.bounced = true;
                    actor.pos = actor.last_pos;
                }
            },
            .Static => {},
        }

        // Kinematics
        const FRICTION = if (actor.isInAir()) 0.9 else actor.friction;
        const velocity = (actor.pos - actor.last_pos) * @splat(2, @as(f32, FRICTION));
        actor.last_pos = actor.pos;
        actor.pos += velocity;

        const GRAVITY = 0.2;
        const z_vel = actor.z - actor.last_z - GRAVITY;
        actor.last_z = actor.z;
        actor.z += z_vel;
        if (actor.z < 0) {
            actor.last_z = (actor.z - actor.last_z) * 0.8;
            actor.z = 0;
            if (@fabs(actor.last_z) > 0.7) {
                actor.bounced = true;
                audio.bounced.play();
            }
        }
    }

    for (combats) |combat| {
        if (combat.val.getHurtbox(time)) |hurtbox| {
            try hurtboxes.append(.{
                .key = combat.key,
                .val = geom.aabb.as_rectf(geom.aabb.addvf(hurtbox, actors.items[combat.key].pos)),
            });
        }
    }

    for (collectables) |*collectable| {
        // Kinematics
        const new_collectable = moveAndSlide(geom.rect.initvf(collectable[0] - geom.Vec2f{ 2, 2 }, .{ 4, 4 }), collectable[0], collectable[1], 2.0, 0.9);
        collectable[0] = new_collectable[0];
        collectable[1] = new_collectable[1];
    }

    // Store actors to remove
    var to_remove = std.ArrayList(usize).init(alloc);
    defer to_remove.deinit();

    // Update health
    for (health) |*h| {
        const actor = &actors.items[h.key];
        if (h.val.stunned) |startTime| {
            if (time - startTime > h.val.stunTime) {
                h.val.stunned = null;
            }
            if (actor.template.kind == .Pot and actor.bounced) {
                h.val.stunned = null;
                h.val.current -|= 1;
            }
            if (actor.bounced and h.val.current == 0) h.val.bounced = true;
        } else {
            if (h.val.bounced and h.val.current == 0) {
                try to_remove.append(h.key);
            } else {
                try hitboxes.append(.{
                    .key = h.key,
                    .val = geom.aabb.as_rectf(geom.aabb.addvf(h.val.hitbox, actor.pos)),
                });
            }
            if (!actor.bounced) h.val.bounced = false;
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
                    h.val.current -|= 1;
                    h.val.stunned = time;
                    const taker = &actors.items[hitbox.key];
                    const hitter = &actors.items[hurtbox.key];
                    const dist: f32 = -8.0;
                    const dir = -hitter.facing.getVec2f();
                    const vel = dir * @splat(2, dist);
                    taker.pos += vel;
                    taker.z += 2;
                    taker.stun(time);
                    audio.hit.play();
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
        if (actor.template.kind == .Player) {
            main.next = .Menu;
            long_fba.reset();
            level_fba.reset();
            frame_fba[0].reset();
            frame_fba[1].reset();
            return;
        }
        health = Assoc(Health).swapRemove(health, remove, actors.items.len);
        intelligences = Assoc(Intelligence).swapRemove(intelligences, remove, actors.items.len);

        // Add their position to collectables
        new_collectables[collectCount] = .{ actor.pos, actor.last_pos };
        collectCount += 1;
    }

    for (collectables) |collectable| {
        new_collectables[collectCount] = collectable;
        const player = actors.items[playerIndex].pos;
        const dist = geom.vec2.distf(collectable[0], player);
        if (dist < 4) {
            try to_remove.append(collectCount);
            heart_count += 1;
            audio.collect.play();
            continue;
        } else if (dist < 32) {
            const towards = geom.vec2.normalizef(player - collectable[0]);
            const around = geom.vec2.perpendicularCWf(towards);
            const bias = @splat(2, @as(f32, 2.0));
            const spiral = geom.vec2.normalizef(towards * bias + around);
            const speed = @splat(2, @as(f32, 1.0));
            new_collectables[collectCount][0] += spiral * speed;
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
        playerStore.pos = @divFloor(playerStore.pos, world.tile_sizef) * world.tile_sizef + (world.tile_sizef / @splat(2, @as(f32, 2)));
        room = next;
        try loadRoom();
    }

    try render(alloc, time);

    renderUi();

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

    // if (debug) {
    //     w4.DRAW_COLORS.* = 0x0041;
    //     var chain_text: [9:0]u8 = .{ 'C', 'H', 'A', 'I', 'N', ':', ' ', ' ', 0 };
    //     chain_text[6] = '0' + @divTrunc(player_combat.chain, 10);
    //     chain_text[7] = '0' + @mod(player_combat.chain, 10);
    //     w4.text(&chain_text, 0, 0);
    // }
}

fn render(alloc: std.mem.Allocator, time: usize) !void {
    // Render background tiles
    w4.DRAW_COLORS.* = 0x1234;
    const camera_pos = geom.vec2.ftoi(camera);
    // Render background tiles
    {
        var x: isize = 0;
        while (x < room.size[0]) : (x += 1) {
            var y: isize = 0;
            while (y < room.size[1]) : (y += 1) {
                const idx = @intCast(usize, y * @intCast(i16, room.size[0]) + x);
                world.blit((geom.Vec2{ x, y } + room.toVec2()) * world.tile_size - camera_pos, room.tiles[idx]);
            }
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
                const aabb = geom.aabb.ftoi(geom.aabb.subvf(actor.getAABB(), camera));
                w4.DRAW_COLORS.* = 0x0022;
                w4.oval(aabb[0], aabb[1], aabb[2], aabb[3]);
                if (actor.z >= 1) {
                    w4.DRAW_COLORS.* = 0x0044;
                    w4.oval(aabb[0] + 1, aabb[1] + 1, aabb[2] - 1, aabb[3] - 1);
                }

                const pos = geom.vec2.ftoi(actor.pos + actor.template.offset - camera);
                actor.image.blit(pos - geom.Vec2{ 0, @floatToInt(i32, actor.z) });
                if (debug and actor.z <= 1) {
                    w4.DRAW_COLORS.* = 0x0040;
                    w4.rect(aabb[0], aabb[1], @intCast(usize, aabb[2]), @intCast(usize, aabb[3]));
                }
            },
            .Particle => |p| {
                w4.DRAW_COLORS.* = 0x0234;
                world.blit(geom.vec2.ftoi(p) - camera_pos - geom.Vec2{ 8, 8 }, world.heart);
            },
        }
    }

    // Render foreground tiles
    {
        var x: isize = 0;
        while (x < room.size[0]) : (x += 1) {
            var y: isize = 0;
            while (y < room.size[1]) : (y += 1) {
                const idx = @intCast(usize, y * @intCast(i16, room.size[0]) + x);
                const tile = room.tiles[idx];
                if (!isForeground(tile)) continue;
                w4.DRAW_COLORS.* = 0x0234;
                world.blit((geom.Vec2{ x, y } + room.toVec2()) * world.tile_size - camera_pos, tile);
            }
        }
    }
}

fn renderUi() void {
    const heart_pos = geom.Vec2{ 160 - 48, 0 };

    w4.DRAW_COLORS.* = 0x0111;
    world.blit(heart_pos + geom.Vec2{ 1, 1 }, world.heart);
    w4.DRAW_COLORS.* = 0x0234;
    world.blit(heart_pos, world.heart);

    const ones = @intCast(u8, heart_count % 10);
    const tens = @intCast(u8, (heart_count / 10) % 10);
    const hundreds = @intCast(u8, (heart_count / 100) % 10);
    const heart_count_str = &[4:0]u8{ 'x', '0' + hundreds, '0' + tens, '0' + ones };
    w4.DRAW_COLORS.* = 0x0001;
    w4.textUtf8(heart_count_str, heart_count_str.len, heart_pos[0] + 17, heart_pos[1] + 5);
    w4.DRAW_COLORS.* = 0x0004;
    w4.textUtf8(heart_count_str, heart_count_str.len, heart_pos[0] + 16, heart_pos[1] + 4);
}

pub fn isForeground(tile: u8) bool {
    return switch(tile) {
        96,
        97,
        98,
        79,
        112...114,
        => true,
        else => false,
    };
}

pub fn isSolid(tile: u8) bool {
    return (tile >= 1 and tile <= 6) or
        (tile >= 18 and tile <= 23 and tile != 19) or
        (tile >= 35 and tile <= 40) or
        (tile >= 55 and tile <= 57) or
        (tile >= 72 and tile <= 74) or
        (tile >= 92 and tile <= 101 and tile != 96 and tile != 98) or
        (tile >= 107 and tile <= 118) or
        (tile >= 131 and tile <= 134)
    ;
}

pub fn isInScreenBounds(pos: geom.Vec2) bool {
    const screen_bounds = geom.aabb.initv(.{room.toVec() * world.room_grid_size * world.tile_size}, @splat(2, @as(i32, w4.CANVAS_SIZE)));
    return screen_bounds.contains(pos);
}

pub fn isInMapBounds(pos: geom.Vec2) bool {
    return pos[0] >= 0 and pos[1] >= 0 and pos[0] < room.size[0] and pos[1] < room.size[1];
}

pub fn moveAndSlide(rect: geom.Rectf, pos: geom.Vec2f, last_pos: geom.Vec2f, maxVelocity: f32, friction: f32) [2]geom.Vec2f {
    var new_pos = pos;
    var new_last_pos = pos;
    const speed = geom.vec2.distf(new_pos, last_pos);
    const velocity = geom.vec2.normalizef(new_pos - last_pos) * @splat(2, @minimum(maxVelocity, speed * friction));
    new_pos += velocity;

    const shiftf = geom.aabb.addvf;
    const hcols = collide(shiftf(rect, geom.Vec2f{ pos[0], last_pos[1] }));
    const vcols = collide(shiftf(rect, geom.Vec2f{ last_pos[0], pos[1] }));

    if (hcols.len > 0) {
        new_pos[0] = last_pos[0];
        new_last_pos[0] = new_pos[0] + velocity[0] * 0.5;
    }
    if (vcols.len > 0) {
        new_pos[1] = last_pos[1];
        new_last_pos[1] = new_pos[1] + velocity[1] * 0.5;
    }

    return .{ new_pos, new_last_pos };
}

pub fn collideBodies(collisions: *std.ArrayList(usize), rect: geom.Rectf, which: usize) !void {
    for (actors.items) |actor, i| {
        if (which == i) continue;
        var o_rect = geom.aabb.as_rectf(geom.aabb.addvf(actor.template.collisionBox, actor.pos));
        if (geom.rect.overlapsf(rect, o_rect)) {
            try collisions.append(i);
            if (debug and verbosity > 2) w4.tracef("collision! %d", i);
        }
    }
}

pub fn collide(rect: geom.Rectf) CollisionInfo {
    const tile_sizef = geom.vec2.itof(world.tile_size);
    var collisions = CollisionInfo.init();

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

    pub fn iter(col: CollisionInfo) []const geom.AABBf {
        return col.items[0..col.len];
    }

    pub fn append(col: *CollisionInfo, item: geom.AABBf) void {
        std.debug.assert(col.len < 9);
        col.items[col.len] = item;
        col.len += 1;
    }
};
