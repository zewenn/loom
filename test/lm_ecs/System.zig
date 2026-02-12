const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");
const ecs = @import("lm_ecs");

const System = ecs.System;

fn testFn(a: *u32, b: *u64, c: *f32) !void {
    try std.testing.expectEqual(16, a.*);
    try std.testing.expectEqual(32, b.*);
    try std.testing.expectEqual(64, c.*);

    std.log.debug("asd", .{});
}

test "wrap function" {
    var a: u32 = 16;
    var b: u64 = 32;
    var c: f32 = 64;

    const generic = System.wrapFunction(testFn);
    const ptrs: []const *anyopaque = &.{ &a, &b, &c };

    try generic(ptrs);
}
