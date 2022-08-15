const w4 = @import("wasm4.zig");
const draw = @import("draw.zig");
const std = @import("std");
const geom = @import("geom.zig");

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

var player = geom.Vec2f{ 80, 80 };

export fn update() void {
    update_safe() catch unreachable;
}

var time: usize = 0;

fn update_safe() !void {
    defer time += 1;

    // Switch frame allocator every frame
    const which_alloc = time % 2;
    const alloc = frame_alloc[which_alloc];
    _ = alloc;
    defer frame_fba[(time + 1) % 2].reset();

    w4.DRAW_COLORS.* = 4;
    w4.oval(@floatToInt(i32, player[0]), @floatToInt(i32, player[1]), 16, 16);
}
