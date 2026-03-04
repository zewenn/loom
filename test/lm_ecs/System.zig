const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");
const ecs = @import("lm_ecs");

const System = ecs.System;

fn testFn(a: []*u32, b: []*u64, c: []const *f32) !void {
    try std.testing.expectEqual(2, a.len);
    try std.testing.expectEqual(2, b.len);
    try std.testing.expectEqual(2, c.len);

    try std.testing.expectEqual(a.len, b.len);
    try std.testing.expectEqual(b.len, c.len);

    try std.testing.expectEqual(0, a[0].*);
    try std.testing.expectEqual(1, a[1].*);

    try std.testing.expectEqual(0, b[0].*);
    try std.testing.expectEqual(1, b[1].*);

    try std.testing.expectEqual(64.16, c[0].*);
    try std.testing.expectEqual(96.5, c[1].*);
}

test "wrap function" {
    var u32_1: u32 = 0;
    var u32_2: u32 = 1;
    var u64_1: u64 = 0;
    var u64_2: u64 = 1;
    var f32_1: f32 = 64.16;
    var f32_2: f32 = 96.5;

    const ptr = try std.testing.allocator.alloc(*anyopaque, 6);
    defer std.testing.allocator.free(ptr);

    ptr[0] = &u32_1;
    ptr[1] = &u32_2;

    ptr[2] = &u64_1;
    ptr[3] = &u64_2;

    ptr[4] = &f32_1;
    ptr[5] = &f32_2;

    const generic = System.wrapFunction(testFn);

    try generic(2, ptr);
}
