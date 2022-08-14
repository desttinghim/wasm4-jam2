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

    // Render
    var y: i32 = 0;
    while (y < w4.CANVAS_SIZE) : (y += 1) {
        var x: i32 = 0;
        while (x < w4.CANVAS_SIZE) : (x += 1) {
            const ro = @as(Vec3f, camera.position);
            const vd = rayDirection(std.math.pi / 6.0, @intToFloat(f32, x), @intToFloat(f32, y));
            const rdz = zm.mul(world_to_view, vd);
            const rd = Vec3f{ rdz[0], rdz[1], rdz[2] };

            const info = sdf.raymarch(scene, ro, rd, .{ .maxSteps = 12, .maxDistance = 100, .epsilon = 0.05 });
            if (info.point) |point| {
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
                draw.pixel(x, y);
            } else if (info.floor) {
                w4.DRAW_COLORS.* = 1;
                draw.pixel(x, y);
            }
        }
    }
    w4.DRAW_COLORS.* = 4;
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
const boxlen = geom.vec3.lengthf(boxsize);
fn scene(point: Vec3f) f32 {
    const box = box: {
        const approx = sdf.sphere(point + boxpos, boxlen);
        if (approx > 1) break :box approx;
        break :box sdf.box(point + boxpos, boxsize);
    };
    const spheres = @minimum(sdf.sphere(point, 5), sdf.sphere(point + sphere2, 1));
    const player = sdf.sphere(point - @as(Vec3f, player_pos), 1);
    const env = @minimum(box, spheres);
    return @minimum(player, env);
}
