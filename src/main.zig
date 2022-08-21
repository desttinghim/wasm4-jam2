const w4 = @import("wasm4.zig");
const input = @import("input.zig");

const game = @import("game.zig");
const menu = @import("menu.zig");

const Which = enum { Game, Menu, None };
var current: Which = .None;
pub var next: Which = .Menu;

export fn start() void {
    w4.PALETTE.* = .{ 0xe0f8cf, 0x86c06c, 0x644666, 0x100221 };

    menu.start() catch |e| {
        w4.tracef(@errorName(e));
        @panic("Ran into an error! ");
    };
}

var time: usize = 0;
export fn update() void {
    defer time += 1;
    defer input.update();

    // Run start function if next is different than current
    if (current != next) {
        current = next;
        _ = switch (current) {
            .Menu => menu.start(),
            .Game => game.start(),
            .None => {},
        } catch |e| switch(e) {
            error.OutOfMemory => {},
            error.NoRoomEntities => {},
            error.RoomNotFound => {},
            error.PlayerNotFound => {},
            error.EndOfStream => {},
        };
    }

    // Run the update functions
    _ = switch (current) {
        .Menu => menu.update(time),
        .Game => game.update(time),
        .None => {},
    } catch |e| {
        switch(e) {
            error.OutOfMemory => {},
            error.NoRoomEntities => {},
        }
    };
}
