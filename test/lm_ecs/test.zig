const std = @import("std");
const ecs = @import("lm_ecs");

test {
    std.testing.refAllDeclsRecursive(ecs);

    _ = @import("System.zig");
    _ = @import("World.zig");
}
