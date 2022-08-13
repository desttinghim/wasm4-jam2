const w4 = @import("wasm4.zig");
const draw = @import("draw.zig");
const geom = @import("geom.zig");
const sdf = @import("raymarch.zig");
const std = @import("std");
const zm = @import("zmath");

const smiley = [8]u8{
    0b11000011,
    0b10000001,
    0b00100100,
    0b00100100,
    0b00000000,
    0b00100100,
    0b10011001,
    0b11000011,
};

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

var time: usize = 0;

var h_angle: f32 = 0;
var v_angle: f32 = 0;
var position = [3]f32{ 0, 0, -10 };

const sun = zm.normalize3(zm.loadArr3(.{ -1, -1, -2 }));

fn update_safe() !void {
    defer time += 1;

    // Switch frame allocator every frame
    const which_alloc = time % 2;
    const alloc = frame_alloc[which_alloc];
    _ = alloc;
    defer frame_fba[(time + 1) % 2].reset();

    const _forward = zm.f32x4(
        @cos(v_angle) * @sin(h_angle),
        @sin(v_angle),
        @cos(v_angle) * @cos(h_angle),
        0,
    );
    const right = zm.f32x4(@sin(h_angle), 0, @cos(h_angle), 1);
    const up = zm.cross3(right, _forward);
    _ = up;

    var _position = zm.loadArr3w(position, 1);
    const speed = @splat(4, @as(f32, 0.1));

    const gamepad = w4.GAMEPAD1.*;
    if (gamepad & w4.BUTTON_UP != 0) {
        _position += _forward * speed;
    }
    if (gamepad & w4.BUTTON_DOWN != 0) {
        _position -= _forward * speed;
    }
    if (gamepad & w4.BUTTON_LEFT != 0) {
        // Left
        h_angle = @mod(h_angle - 0.05, std.math.pi * 2.0);
    }
    if (gamepad & w4.BUTTON_RIGHT != 0) {
        // Right
        h_angle = @mod(h_angle + 0.05, std.math.pi * 2.0);
    }

    // Calculate position
    const world_to_view = zm.lookToLh(
        // eye position
        _position,
        // eye direction
        _forward,
        // up direction
        zm.F32x4{ 0, 1, 0, 0 },
    );

    zm.storeArr3(position[0..], _position);

    var y: i32 = 0;
    while (y < w4.CANVAS_SIZE) : (y += 1) {
        var x: i32 = 0;
        while (x < w4.CANVAS_SIZE) : (x += 1) {
            const ro = _position;
            const vd = rayDirection(std.math.pi / 6.0, @intToFloat(f32, x), @intToFloat(f32, y));
            const rd = zm.mul(world_to_view, vd);

            const info = sdf.raymarch(scene, ro, rd, .{ .maxSteps = 5, .maxDistance = 100, .epsilon = 0.001 });
            if (info.point) |point| {
                const normal = sdf.getNormal(scene, point, .{ .h = 0.0001 });
                const dot = zm.dot3(normal, sun)[0];
                if (dot < -0.5) {
                    w4.DRAW_COLORS.* = 4;
                } else if (dot < 0) {
                    w4.DRAW_COLORS.* = 3 + @intCast(u16, @mod(y, 2));
                } else {
                    w4.DRAW_COLORS.* = 3;
                }
            } else {
                w4.DRAW_COLORS.* = 1;
            }
            draw.pixel(x, y);
        }
    }
    w4.DRAW_COLORS.* = 4;
}

fn rayDirection(fov: f32, x: f32, y: f32) zm.Vec {
    const size = zm.f32x4s(w4.CANVAS_SIZE / 2);
    const pos = zm.loadArr2(.{x, y});
    const xy = pos - size;
    const z = size[1] / @tan(fov) / 2;
    return zm.normalize3(zm.loadArr3(.{ xy[0], xy[1], z }));
}

const sphere2 = zm.loadArr3(.{ 6, 0, 5 });
fn scene(point: zm.Vec) f32 {
    return @minimum(sdf.sphere(point, 5), sdf.sphere(point + sphere2, 1));
}
