const geom = @import("geom.zig");

max: u8,
current: u8,
stunned: ?usize = null,
stunTime: usize = 20,
hitbox: geom.AABBf,
