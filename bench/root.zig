const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");

const ecs_bench = @import("lm_ecs/root.zig");

pub fn main() !void {
    try ecs_bench.main();
}
