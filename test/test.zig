const lm = @import("loom");
const std = @import("std");

const testing = std.testing;

test {
    testing.refAllDecls(lm);

    _ = @import("lm_core/test.zig");
    _ = @import("lm_ecs/test.zig");
}
