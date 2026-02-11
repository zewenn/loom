const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");
const SparseSet = core.types.SparseSet;

test "init / deinit" {
    var sparse_set = SparseSet(u64).init(std.testing.allocator);
    defer sparse_set.deinit();
}

test "set / get" {
    var sparse_set = SparseSet(u64).init(std.testing.allocator);
    defer sparse_set.deinit();

    try sparse_set.set(0, 10);
    try sparse_set.set(1024, 42);
    try sparse_set.set(6668, 67);

    try std.testing.expectEqual(10, sparse_set.get(0));
    try std.testing.expectEqual(42, sparse_set.get(1024));
    try std.testing.expectEqual(67, sparse_set.get(6668));
}

test "getPtr" {
    var sparse_set = SparseSet(u64).init(std.testing.allocator);
    defer sparse_set.deinit();

    try sparse_set.set(1024, 10);

    try std.testing.expectEqual(10, sparse_set.get(1024));

    const ptr = sparse_set.getPtr(1024).?;
    ptr.* = 67;

    try std.testing.expectEqual(67, sparse_set.get(1024));
}

test "remove" {
    var sparse_set = SparseSet(u64).init(std.testing.allocator);
    defer sparse_set.deinit();

    try sparse_set.set(0, 10);
    try sparse_set.set(1024, 42);
    try sparse_set.set(6668, 67);

    try std.testing.expectEqual(10, sparse_set.get(0));
    try std.testing.expectEqual(42, sparse_set.get(1024));
    try std.testing.expectEqual(67, sparse_set.get(6668));

    sparse_set.remove(1024);

    try std.testing.expectEqual(10, sparse_set.get(0));
    try std.testing.expectEqual(null, sparse_set.get(1024));
    try std.testing.expectEqual(67, sparse_set.get(6668));
}
