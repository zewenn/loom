const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");
const SparseSet = core.types.SparseSet;

test "init / deinit" {
    var set = SparseSet.init(std.testing.allocator, u64);
    defer set.deinit();
}

test "set / get" {
    var sparse_set = SparseSet.init(std.testing.allocator, u64);
    defer sparse_set.deinit();

    try sparse_set.set(0, @as(u64, 10));
    try sparse_set.set(1024, @as(u64, 67));
    try sparse_set.set(6668, @as(u64, 42));

    try std.testing.expectEqual(@as(u64, 10), sparse_set.getAs(0, u64).?.*);
    try std.testing.expectEqual(@as(u64, 67), sparse_set.getAs(1024, u64).?.*);
    try std.testing.expectEqual(@as(u64, 42), sparse_set.getAs(6668, u64).?.*);
}

test "remove" {
    var sparse_set = SparseSet.init(std.testing.allocator, u64);
    defer sparse_set.deinit();

    try sparse_set.set(0, @as(u64, 10));
    try sparse_set.set(1024, @as(u64, 67));
    try sparse_set.set(6668, @as(u64, 42));

    try std.testing.expectEqual(@as(u64, 10), sparse_set.getAs(0, u64).?.*);
    try std.testing.expectEqual(@as(u64, 67), sparse_set.getAs(1024, u64).?.*);
    try std.testing.expectEqual(@as(u64, 42), sparse_set.getAs(6668, u64).?.*);

    try sparse_set.remove(1024);

    try std.testing.expectEqual(@as(u64, 10), sparse_set.getAs(0, u64).?.*);
    try std.testing.expectEqual(@as(u64, 42), sparse_set.getAs(6668, u64).?.*);
}
