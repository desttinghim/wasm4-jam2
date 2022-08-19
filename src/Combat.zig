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
