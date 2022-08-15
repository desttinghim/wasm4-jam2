const w4 = @import("wasm4.zig");
const draw = @import("draw.zig");
const sdf = @import("sdf.zig");
const std = @import("std");
const zm = @import("zmath");
const geom = @import("geom.zig");
const Vec3f = geom.Vec3f;

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

// const SceneObjectType = union(enum) {
//     // Radius
//     sphere: f32,
//     // Axis aligned box
//     aabb: Vec3f,
// };

// const SceneObject = struct {
//     pos: Vec3f,
//     type: SceneObjectType,
// };

// const Bounds = struct {
//     pos: Vec3f,
//     extents: Vec3f,
//     pub fn fromSphere(pos: Vec3f, radius: f32) Bounds {
//         return .{.pos = pos, .extents = @splat(3, radius)};
//     }
//     pub fn fromAABB(pos: Vec3f, extents: Vec3f) Bounds {
//         return .{.pos = pos, .extents = extents};
//     }
//     pub fn contains(bounds: Bounds, point: Vec3f) bool {
//         const top = bounds.pos + bounds.extents;
//         const bot = bounds.pos - bounds.extents;
//         return @reduce(.And, point > bot) and @reduce(.And, point < top);
//     };
//     pub fn containsBound(bounds: Bounds, inner: Bounds) bool {
//         const top = inner.pos + inner.extents;
//         const bot = inner.pos - inner.extents;
//         return bounds.contains(top) and bounds.contains(bot);
//     };
//     pub fn expandToContain(bounds: Bounds, inner: Bounds) bool {
//         const top = inner.pos + inner.extents;
//         const bot = inner.pos - inner.extents;
//         return bounds.contains(top) and bounds.contains(bot);
//     };
// };

// const scene_data = [_]SceneObject{
//     .{.pos = .{10,0,0}, .type = .{.sphere = 3}},
//     .{.pos = .{0,0,10}, .type = .{.sphere = 3}},
//     .{.pos = .{10,0,10}, .type = .{.aabb = .{3, 3,3}}}
// };

// var scene: []SceneObject = scene_data[0..];
// var bounds: []Bounds = undefined;

// export fn start() void {
//     start_safe() catch unreachable;
// }

// fn start_safe() !void {
//     bounds = try long_alloc.alloc(Bounds, scene_data.len + 1);
//     const lastbound = &bounds[bounds.len];
//     for(scene) |obj,i| {
//         bounds[i] = switch(obj.type) {
//             .sphere => |s| bounds.fromSphere(obj.pos, s),
//             .aabb => |v| bounds.fromAABB(obj.pos, v),
//         };
//         if (bounds.contains(bounds[i]))
//     }
// }

export fn update() void {
    update_safe() catch unreachable;
}

const Camera = struct {
    h_angle: f32,
    v_angle: f32,
    position: [3]f32,
};

var camera = Camera{
    .h_angle = 0,
    .v_angle = 0,
    .position = [3]f32{ 0, 10, -10 },
};

var player_pos = [3]f32{ 0, 0, 0 };

var time: usize = 0;
const sun = geom.vec3.normalizef(.{ -1, -1, -2 });

var distanceCache: [400]f32 = [_]f32{0} ** 400;

fn update_safe() !void {
    defer time += 1;

    // Switch frame allocator every frame
    const which_alloc = time % 2;
    const alloc = frame_alloc[which_alloc];
    _ = alloc;
    defer frame_fba[(time + 1) % 2].reset();

    // const _forward = zm.f32x4(
    //     @cos(camera.v_angle) * @sin(camera.h_angle),
    //     @sin(camera.v_angle),
    //     @cos(camera.v_angle) * @cos(camera.h_angle),
    //     0,
    // );
    // const right = zm.f32x4(@sin(camera.h_angle), 0, @cos(camera.h_angle), 0);
    // const up = zm.cross3(right, _forward);
    // _ = up;

    var _player_pos = zm.loadArr3w(player_pos, 1);
    const north = zm.f32x4(1, 0, 0, 0);
    const west = zm.f32x4(0, 0, 1, 0);
    const speed = @splat(4, @as(f32, 0.1));

    const gamepad = w4.GAMEPAD1.*;
    if (gamepad & w4.BUTTON_UP != 0) {
        _player_pos += north * speed;
    }
    if (gamepad & w4.BUTTON_DOWN != 0) {
        _player_pos -= north * speed;
    }
    if (gamepad & w4.BUTTON_LEFT != 0) {
        // Left
        // camera.h_angle -= 0.05;
        _player_pos += west * speed;
    }
    if (gamepad & w4.BUTTON_RIGHT != 0) {
        // Right
        // camera.h_angle += 0.05;
        _player_pos -= west * speed;
    }

    var _position = zm.loadArr3w(camera.position, 1);
    const camera_offset = zm.f32x4(-5, -10, -5, 0);
    _position = _player_pos + camera_offset;

    // Calculate position
    const world_to_view = zm.lookAtLh(
        // eye position
        _position,
        // eye direction
        _player_pos,
        // up direction
        zm.F32x4{ 0, 1, 0, 0 },
    );

    zm.storeArr3(camera.position[0..], _position);
    zm.storeArr3(player_pos[0..], _player_pos);

    // Clear the screen
    w4.DRAW_COLORS.* = 1;
    w4.rect(0, 0, 160, 160);

    render(world_to_view, .{ 0, 0, w4.CANVAS_SIZE, w4.CANVAS_SIZE });

    // Render
    w4.DRAW_COLORS.* = 4;
}

fn render(world_to_view: zm.Mat, area: geom.AABB) void {
    // const res_half = @divTrunc(area[2], 2);
    // const res_halfu = @intCast(u32, res_half);
    const res_half = 1;
    // const res_halfu = @intCast(u32, res_half);
    var y: i32 = area[0];
    while (y < area[2]) : (y += res_half) {
        var x: i32 = area[1];
        while (x < area[3]) : (x += res_half) {
            // const ro = @as(Vec3f, camera.position);
            // const vd = rayDirection(std.math.pi / 6.0, @intToFloat(f32, x), @intToFloat(f32, y));
            // const rdz = zm.mul(world_to_view, vd);
            // const rd = geom.vec3.normalizef(Vec3f{ rdz[0], rdz[1], rdz[2] });

            const sph = sdf.sphereProjection(.{0,0,0,5}, world_to_view, std.math.pi / 6.0);
            if (sph > 0) {
                w4.DRAW_COLORS.* = 4;
                draw.pixel(x,y);
            }

            // const info = sdf.coverageSearch(scene, ro, rd, 1.0, 100.0, .{.maxSteps = 12, .epsilon = 1});
            // if (info.hit) {
            //     shade(info.point, y);
            //     w4.rect(x,y,res_halfu, res_halfu);
            // }
        }
    }
}

fn shade(point: Vec3f, y: i32) void {
    const normal = sdf.getNormal(scene, point, .{ .h = 0.0001 });
    const dot = geom.vec3.dotf(normal, sun);
    if (dot < -0.2) {
        w4.DRAW_COLORS.* = 4;
    } else if (dot < 0.2) {
        w4.DRAW_COLORS.* = 3 + @intCast(u16, @mod(y, 2));
    } else if (dot > 0.8) {
        w4.DRAW_COLORS.* = 2;
    } else {
        w4.DRAW_COLORS.* = 3;
    }
}

fn rayDirection(fov: f32, x: f32, y: f32) zm.Vec {
    const size = zm.f32x4s(w4.CANVAS_SIZE / 2);
    const pos = zm.loadArr2(.{ x, y });
    const xy = pos - size;
    const z = size[1] / @tan(fov) / 2;
    return zm.normalize3(zm.loadArr3(.{ xy[0], xy[1], z }));
}

const sphere2 = Vec3f{ 6, 0, 5 };
const boxpos = Vec3f{ 10, 0, -10 };
const boxsize = Vec3f{ 5, 5, 5 };
const boxsize2 = Vec3f{ 1, 1, 1 };
fn scene(point: Vec3f) f32 {
    const box = sdf.box(point + boxpos, boxsize);
    const spheres = @minimum(sdf.box(point, boxsize), sdf.box(point + sphere2, boxsize2));
    const player = sdf.box(point - @as(Vec3f, player_pos), boxsize2);
    const env = @minimum(box, spheres);
    return @minimum(player, env);
}
