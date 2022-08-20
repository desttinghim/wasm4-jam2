const draw = @import("draw.zig");
const geom = @import("geom.zig");
const world = @import("world.zig");
const Actor = @import("Actor.zig");

const Renderable = @This();

const Kind = union(enum) {
    Actor: *const Actor,
    Particle: geom.Vec2f,
};

kind: Kind,

pub fn getPos(renderable: Renderable) geom.Vec2f {
    return switch (renderable.kind) {
        .Actor => |a| a.pos + a.template.offset,
        .Particle => |p| p,
    };
}

pub fn compare(ctx: void, a: Renderable, b: Renderable) bool {
    _ = ctx;
    const apos = a.getPos();
    const bpos = b.getPos();
    return apos[1] < bpos[1];
}

pub fn toGrid(this: Renderable) geom.Vec2 {
    return geom.vec2.ftoi(@divFloor(this.pos, world.tile_sizef));
}
