const BlitFlags = @import("../draw.zig").BlitFlags;
const Actor = @import("Actor.zig");

pub const CombatTemplate = struct {
    punch_down: [2][]const Ops,
    punch_up: [2][]const Ops,
    punch_side: [2][]const Ops,
};

pub const ActorTemplate = struct {
    walk_down: []const Ops,
    walk_up: []const Ops,
    walk_side: []const Ops,
    stand_down: []const Ops,
    stand_up: []const Ops,
    stand_side: []const Ops,
};

time: usize = 0,
currentOp: usize = 0,
delayUntil: usize = 0,
anim: []const Ops,
stopped: bool = false,
flipped: bool = false,
interruptable: bool = true,
// TODO find the right place for this
template: *const Actor.Template,

pub const Ops = union(enum) { Index: usize, Wait: usize, FlipX, SetFlipX: bool, Stop, NoInterrupt, AllowInterrupt };

pub fn play(this: *@This(), anim: []const Ops) void {
    if (this.anim.ptr == anim.ptr) return;
    if (!this.interruptable) return;
    if (anim[0] == .NoInterrupt) this.interruptable = false;
    this.anim = anim;
    this.stopped = false;
    this.currentOp = 0;
}

pub fn update(this: *@This(), out: *usize, flags_out: *BlitFlags) void {
    this.time += 1;
    while (!this.stopped and this.anim.len > 0 and this.time >= this.delayUntil) {
        switch (this.anim[this.currentOp]) {
            .Index => |index| out.* = index,
            .Wait => |wait| this.delayUntil = this.time + wait,
            .FlipX => flags_out.flip_x = !flags_out.flip_x,
            .SetFlipX => |flip| flags_out.flip_x = flip,
            .Stop => this.stopped = true,
            .NoInterrupt => this.interruptable = false,
            .AllowInterrupt => this.interruptable = true,
        }
        this.currentOp = (this.currentOp + 1) % this.anim.len;
    }
}

pub fn simple(rate: usize, comptime arr: []const usize) [arr.len * 2]Ops {
    var anim: [arr.len * 2]Ops = undefined;
    inline for (arr) |item, i| {
        anim[i * 2] = Ops{ .Index = item };
        anim[i * 2 + 1] = Ops{ .Wait = rate };
    }
    return anim;
}

pub fn frame(comptime index: usize) [2]Ops {
    return [_]Ops{ .{ .Index = index }, .Stop };
}
