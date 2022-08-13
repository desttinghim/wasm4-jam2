const w4 = @import("wasm4.zig");
const draw = @import("draw.zig");
const geom = @import("geom.zig");
const sdf = @import("raymarch.zig");

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

export fn update() void {
    w4.DRAW_COLORS.* = 2;
    w4.text("Hello from Zig!", 10, 10);

    const gamepad = w4.GAMEPAD1.*;
    if (gamepad & w4.BUTTON_1 != 0) {
        w4.DRAW_COLORS.* = 4;
    }

    w4.blit(&smiley, 76, 76, 8, 8, w4.BLIT_1BPP);
    w4.text("Press X to blink", 16, 90);

    // const eye = geom.Vec3{ 0, 0, -1 };
    const up = geom.Vec3f{ 0, 1, 0 };
    const right = geom.Vec3f{ 1, 0, 0 };

    var y: i32 = 0;
    while (y < w4.CANVAS_SIZE) : (y += 1) {
        var x: i32 = 0;
        while (x < w4.CANVAS_SIZE) : (x += 1) {
            const u = @splat(3, @intToFloat(f32, x - w4.CANVAS_SIZE / 2));
            const v = @splat(3, @intToFloat(f32, y - w4.CANVAS_SIZE / 2));
            const ro = right * u + up * v;
            const rd = geom.vec3.normalizef(geom.vec3.cross(right, up));

            if (sdf.raymarch(scene, ro, rd, .{})) {
                w4.DRAW_COLORS.* = 4;
            } else {
                w4.DRAW_COLORS.* = 1;
            }
            draw.pixel(x, y);
        }
    }
}

fn scene(point: geom.Vec3f) f32 {
    return sdf.sphere(point, 10);
}
