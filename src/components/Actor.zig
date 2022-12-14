const draw = @import("../draw.zig");
const geom = @import("../geom.zig");
const world = @import("../world.zig");
const Anim = @import("Anim.zig");

const Actor = @This();
pub const Body = enum { Kinematic, Rigid, Static };

pub const Template = struct {
    kind: world.EntityKind,
    offset: geom.Vec2f,
    collisionBox: geom.AABBf,
    body: Body = .Rigid,
    stunPeriod: usize = 5,
    speed: f32 = 30.0 / 60.0,
    friction: f32 = 0.5,
    animation: *const Anim.ActorTemplate,
    // TODO: figure out where to put this
    // This must be copied, not referenced
    image: draw.Blit,

    pub const Player = Template{
        .kind = .Player,
        .body = .Kinematic,
        .speed = 45.0 / 60.0,
        .collisionBox = geom.AABBf{ -4, -4, 8, 8 },
        .offset = geom.Vec2f{ -8, -12 },
        .image = draw.Blit.init_frame(world.player_style, &world.player_bmp, .{ .bpp = .b2 }, .{ 16, 16 }, 0),
        .animation = &world.PlayerAnimActorTemplate,
    };

    pub const PlayerAttack = Template{
        .kind = .Player,
        .body = .Kinematic,
        .speed = 45.0 / 60.0,
        .friction = 0.85,
        .collisionBox = geom.AABBf{ -4, -4, 8, 8 },
        .offset = geom.Vec2f{ -16, -20 },
        .image = draw.Blit.init_frame(world.player_style, &world.player_punch_bmp, .{ .bpp = .b2 }, .{ 32, 32 }, 0),
        .animation = &world.PlayerAnimActorTemplate,
    };

    pub const Pot = Template{
        .kind = .Pot,
        .collisionBox = geom.AABBf{ -3, -3, 6, 6 },
        .offset = geom.Vec2f{ -8, -12 },
        .image = draw.Blit.init_frame(0x0243, &world.bitmap, .{ .bpp = .b2 }, .{ 16, 16 }, world.pot),
        .animation = &world.PotAnimActorTemplate,
    };

    pub const Skeleton = Template{
        .kind = .Skeleton,
        .body = .Kinematic,
        .collisionBox = geom.AABBf{ -3, -3, 6, 6 },
        .offset = geom.Vec2f{ -8, -12 },
        .image = draw.Blit.init_frame(0x0243, &world.bitmap, .{ .bpp = .b2 }, .{ 16, 16 }, world.skeleton),
        .animation = &world.SkeletonAnimActorTemplate,
    };
};

template: *const Template,

image: draw.Blit,
z: f32 = 0,
last_z: f32 = 0,
pos: geom.Vec2f,
last_pos: geom.Vec2f,
friction: f32,
facing: geom.Direction = .West,
input_vector: geom.Vec2f = geom.Vec2f{ 0, 0 },

/// True if actor is attempting to move
motive: bool = false,
/// True if the actor collided with after being in the air
bounced: bool = false,
/// True if the actor was hit
stunned: ?usize = null,

pub fn init(template: *const Template, pos: geom.Vec2f) Actor {
    return .{
        .template = template,
        .image = template.image,
        .friction = template.friction,
        .pos = pos,
        .last_pos = pos,
    };
}

pub fn setTemplate(this: *Actor, template: *const Template) void {
    this.template = template;
    this.image = template.image;
    this.friction = template.friction;
}

pub fn render(this: *Actor) void {
    const pos = geom.vec2.ftoi(this.pos + this.template.offset);
    this.template.image.blit(pos);
}

pub fn move(actor: *Actor) void {
    // Don't move when stunned
    if (actor.stunned != null) return;
    if (actor.isInAir()) return;
    if (geom.Direction.fromVec2f(actor.input_vector)) |facing| {
        actor.facing = facing;
        actor.pos += @splat(2, actor.template.speed) * actor.input_vector;
        actor.motive = true;
    }
}

pub fn stun(actor: *Actor, time: usize) void {
    actor.stunned = time;
    actor.motive = false;
    actor.friction = 0.85;
}

pub fn isInAir(this: Actor) bool {
    return this.z > 0.4 or this.z - this.last_z > 0.2;
}

pub fn isMoving(this: Actor) bool {
    return (@reduce(.Or, this.pos != this.last_pos));
}

pub fn getAABB(this: Actor) geom.AABBf {
    return geom.aabb.addvf(this.template.collisionBox, this.pos);
}

pub fn getSize(this: Actor) geom.AABBf {
    return geom.aabb.sizef(this.template.collisionBox);
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
