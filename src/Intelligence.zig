const geom = @import("geom.zig");

player_dir: ?geom.Direction = null,

track_player: bool = true,
track_omni_dist: f32 = 16,

follow_player: bool = true,
approach_distance: f32 = 32,
backup_distance: f32 = 16,
circle_dir: enum {NA, CW, WS} = .NA,

attack_cooldown: usize = 120,
attack_distance: f32 = 16,
