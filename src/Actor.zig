const draw = @import("draw.zig");
const geom = @import("geom.zig");
const world = @import("world.zig");

const Actor = @This();
pub const Body = enum { Kinematic, Rigid, Static };

kind: world.EntityKind,
image: draw.Blit,
offset: geom.Vec2f,

pos: geom.Vec2f,
last_pos: geom.Vec2f,
collisionBox: geom.AABBf,
friction: f32 = 0.9,
body: Body = .Rigid,
facing: geom.Direction = .West,

// True if actor is attempting to move
motive: bool = false,

pub fn render(this: *Actor) void {
    const pos = geom.vec2.ftoi(this.pos + this.offset);
    this.image.blit(pos);
}

pub fn move(actor: *Actor, input_vector: geom.Vec2f) void {
    const speed: f32 = 30.0 / 60.0;
    if (geom.Direction.fromVec2f(input_vector)) |facing| {
        actor.facing = facing;
        actor.pos += @splat(2, speed) * input_vector;
        actor.motive = true;
    }
}

pub fn isMoving(this: Actor) bool {
    return (@reduce(.Or, this.pos != this.last_pos));
}

pub fn getAABB(this: Actor) geom.AABBf {
    return geom.aabb.addvf(this.collisionBox, this.pos);
}

pub fn getSize(this: Actor) geom.AABBf {
    return geom.aabb.sizef(this.collisionBox);
}

pub fn getRect(this: Actor) geom.Rectf {
    return geom.aabb.as_rectf(this.getAABB());
}

pub fn compare(ctx: void, a: *const Actor, b: *const Actor) bool {
    _ = ctx;
    return a.pos[1] + a.offset[1] < b.pos[1] + b.offset[1];
}

pub fn toGrid(this: Actor) geom.Vec2 {
    return geom.vec2.ftoi(@divFloor(this.pos, world.tile_sizef));
}
