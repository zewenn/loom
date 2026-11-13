const lm = @import("loom");
const std = @import("std");

const testing = std.testing;

test {
    testing.refAllDecls(lm);

    _ = @import("lm_types/test.zig");
    _ = @import("lm_ecs/test.zig");
    _ = @import("lm_uuid/test.zig");
    _ = @import("lm_benchmarking/test.zig");
}
