const w4 = @import("wasm4.zig");
const draw = @import("draw.zig");
const std = @import("std");
const geom = @import("geom.zig");
const input = @import("input.zig");
const tiles = @import("tiles.zig");

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

const Actor = struct {
    image: ?draw.Blit,
    pos: geom.Vec2f,
    offset: geom.Vec2f,
    size: geom.Vec2f,

    pub fn render(this: Actor) void {
        const pos = geom.vec2.ftoi(this.pos + this.offset);
        const size = geom.vec2.ftoi(this.size);
        if (this.image) |image| {
            image.blit(pos);
        } else {
            w4.DRAW_COLORS.* = 4;
            w4.oval(pos[0], pos[1], size[0], size[1]);
        }
    }
};

var player = Actor{
    .pos = geom.Vec2f{ 80, 80 },
    .offset = geom.Vec2f{ -8, -8 },
    .image = null,
    .size = .{ 16, 16 },
};

export fn update() void {
    update_safe() catch unreachable;
}

var time: usize = 0;

fn update_safe() !void {
    defer time += 1;
    defer input.update();

    // Memory management
    // Switch frame allocator every frame
    const which_alloc = time % 2;
    const alloc = frame_alloc[which_alloc];
    _ = alloc;
    defer frame_fba[(time + 1) % 2].reset();

    // Input
    const speed = 80.0 / 60.0;
    if (input.btn(.one, .up)) player.pos[1] -= speed;
    if (input.btn(.one, .left)) player.pos[0] -= speed;
    if (input.btn(.one, .right)) player.pos[0] += speed;
    if (input.btn(.one, .down)) player.pos[1] += speed;

    if ((player.pos + player.size + player.offset)[1] < 127) {
        player.pos[1] += 1;
    }

    w4.DRAW_COLORS.* = 0x1234;
    var x: isize = 0;
    while (x < 10) : (x += 1) {
        var y: isize = 0;
        while (y < 10) : (y += 1) {
            tiles.blit(geom.Vec2{ x, y } * tiles.tile_size, 0);
        }
    }

    // Render
    player.render();
    w4.rect(0, 128, 160, 8);
}
