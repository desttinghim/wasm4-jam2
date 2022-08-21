const builtin = @import("builtin");
pub const debug = builtin.mode == .Debug;
pub const verbosity = 0;
pub var muted: bool = false;
