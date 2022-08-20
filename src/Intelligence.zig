const geom = @import("geom.zig");

player_dir: ?geom.Direction = null,
follow_player: bool = false,
approach_distance: f32 = 32,
backup_distance: f32 = 16,
circle_dir: enum {NA, CW, WS} = .NA,
