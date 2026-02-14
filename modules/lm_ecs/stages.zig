const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");

pub const Stage = enum {
    init,
    load,
    pre_update,
    update,
    post_update,
    tick,
    draw,
    deinit,
};

pub const StageInfo = struct {};
