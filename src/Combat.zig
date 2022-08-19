const draw = @import("draw.zig");
const geom = @import("geom.zig");
const Anim = @import("Anim.zig");
const Actor = @import("Actor.zig");

const Combat = @This();

animator: *Anim,
actor: *Actor,
is_attacking: bool = false,
last_attacking: usize = 0,
last_attack: usize = 0,
chain: u8 = 0,

actorImage: draw.Blit,
actorOffset: geom.Vec2f,
image: draw.Blit,
offset: geom.Vec2f,
punch_down: [2][]const Anim.Ops,
punch_up: [2][]const Anim.Ops,
punch_side: [2][]const Anim.Ops,

pub fn endAttack(this: *Combat) void {
    this.chain = 0;
    this.is_attacking = false;
    this.actor.image = this.actorImage;
    this.actor.offset = this.actorOffset;
    this.actor.image.flags.flip_x = this.actor.facing == .West;
    // Arrest momentum
    this.actor.last_pos = this.actor.pos;
    this.actor.friction = 0.5;
    this.actor.body = .Kinematic;
}

/// Relative to offset
pub fn getHurtbox(this: Combat) ?geom.AABBf {
    if (!this.is_attacking and this.animator.interruptable) return null;
    // This will be called after startAttack, so last_attack == 0 is flipped
    var offset = this.actor.facing.getVec2f() * @splat(2, @as(f32, 8));
    const chain_offset_x: f32 = x: {
        if (offset[1] > 0.01 or offset[1] < 0.01) {
            break :x if (this.last_attack == 0) @as(f32, -4) else -8;
        } else {
            break :x 0;
        }
    };
    offset[0] += chain_offset_x;
    const hurtbox: geom.AABBf = switch (this.actor.facing) {
        .Northwest, .Northeast, .North, .Southwest, .Southeast, .South => .{ 0, -8, 14, 12 },
        .West, .East => .{ 0, -10, 12, 14 },
    };
    return geom.aabb.addvf(hurtbox, offset);
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
    if (this.actor.facing == .South) {
        this.animator.play(this.punch_down[this.last_attack]);
    } else if (this.actor.facing == .North) {
        this.animator.play(this.punch_up[this.last_attack]);
    } else {
        this.animator.play(this.punch_side[this.last_attack]);
        this.actor.image.flags.flip_x = this.actor.facing == .West or this.actor.facing == .Northwest or this.actor.facing == .Southwest;
    }
    this.is_attacking = true;
    this.last_attacking = now;
    this.last_attack = (this.last_attack + 1) % 2;
    this.actor.friction = 0.9;
    this.actor.body = .Rigid;
}
