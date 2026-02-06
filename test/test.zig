const std = @import("std");
const testing = std.testing;

test {
    testing.refAllDeclsRecursive(@import("loom"));

    _ = @import("types/types.zig");
    _ = @import("ecs/ecs.zig");
    _ = @import("eventloop/eventloop.zig");
    _ = @import("sort.zig");
}
