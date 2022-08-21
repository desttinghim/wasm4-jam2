const std = @import("std");
const w4 = @import("wasm4.zig");
const main = @import("main.zig");
const draw = @import("draw.zig");
const input = @import("input.zig");
const audio = @import("audio.zig");
const settings = @import("settings.zig");

var field: usize = 0;
var max_field: usize = 2;

pub fn start() !void {}

pub fn update(time: usize) !void {
    _ = time;
    text_centered(">             <", 80, 80 + @intCast(i32, field * 8));
    text_centered("Play", 80, 80);
    if (settings.muted) text_centered("Sound is off", 80, 88) else text_centered("Sound is on", 80, 88);

    if (input.btnp(.one, .down)) field += 1;
    if (input.btnp(.one, .up)) field -%= 1;
    if (input.btnp(.one, .z)) switch (field) {
        0 => main.next = .Game,
        1 => settings.muted = !settings.muted,
        else => {},
    };
    // if (input.btnp(.one, .x))

    if (field == std.math.maxInt(usize)) field = max_field - 1;
    field = field % max_field;
}

fn text_centered(text: []const u8, x: i32, y: i32) void {
    const width = @intCast(i32, text.len * 8);
    w4.text(text.ptr, x - @divFloor(width, 2), y);
}
