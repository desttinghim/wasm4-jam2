const draw = @import("draw.zig");
const geom = @import("geom.zig");
const Anim = @import("Anim.zig");
const Actor = @import("Actor.zig");

const Combat = @This();

anim_template: *const Anim.CombatTemplate,
template: *const Actor.Template,
actor: *Actor,
is_attacking: bool = false,
last_attacking: usize = 0,
last_attack: usize = 0,
chain: u8 = 0,

// Attack timings. Times stack
attack_uninterruptable: usize = 10,
attack_combo: usize = 35,
attack_end: usize = 10,

hurtbox_vertical: geom.AABBf,
hurtbox_horizontal: geom.AABBf,

pub fn endAttack(this: *Combat) void {
    this.chain = 0;
    this.is_attacking = false;
    // Arrest momentum
    this.actor.last_pos = this.actor.pos;
}

/// Relative to offset
pub fn getHurtbox(this: Combat, now: usize) ?geom.AABBf {
    if (this.isInterruptable(now)) return null;
    // This will be called after startAttack, so last_attack == 0 is flipped
    var offset = this.actor.facing.getVec2f() * @splat(2, @as(f32, 8));
    const chain_offset_x: f32 = x: {
        if (@fabs(offset[1]) > 0.01) {
            break :x if (this.last_attack == 0) @as(f32, -0) else -4;
        } else {
            break :x 0;
        }
    };
    offset[0] += chain_offset_x;
    const hurtbox: geom.AABBf = switch (this.actor.facing) {
        .Northwest, .Northeast, .North, .Southwest, .Southeast, .South => this.hurtbox_vertical,
        .West, .East => this.hurtbox_horizontal,
    };
    return geom.aabb.addvf(hurtbox, offset);
}

pub fn isInterruptable(this: Combat, now: usize) bool {
    const attack_time = now - this.last_attacking;
    return attack_time > this.attack_uninterruptable;
}

pub fn isCombo(this: Combat, now: usize) bool {
    const attack_time = now - this.last_attacking;
    return attack_time > this.attack_uninterruptable + this.attack_combo and attack_time < this.attack_uninterruptable + this.attack_combo + this.attack_end;
}

pub fn isOver(this: Combat, now: usize) bool {
    return this.isInterruptable(now) and !this.isCombo(now);
}

pub fn startAttack(this: *Combat, now: usize) void {
    if (!this.isInterruptable(now)) {
        this.chain = 0;
        return;
    }
    if (this.isCombo(now)) {
        this.chain +|= 1;
    }
    this.is_attacking = true;
    this.last_attacking = now;
    this.last_attack = (this.last_attack + 1) % 2;
}
