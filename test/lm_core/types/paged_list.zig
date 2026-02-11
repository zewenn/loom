const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");
const PagedList = core.PagedList;

test "init" {
    var list: PagedList(usize, 1024) = .init(std.testing.allocator);
    defer list.deinit();
}

test "set / get" {
    var list: PagedList(usize, 1024) = .init(std.testing.allocator);
    defer list.deinit();

    try list.set(16, 42);
    const result = list.get(16);

    try std.testing.expectEqual(42, result);
    try std.testing.expectEqual(1, list.list.len());
    try std.testing.expectEqual(17, list.list.items()[0].?.len());
}

test "getPtr" {
    var list: PagedList(usize, 1024) = .init(std.testing.allocator);
    defer list.deinit();

    try list.set(16, 42);
    const ptr = list.getPtr(16).?;

    try std.testing.expectEqual(42, ptr.*);

    ptr.* = 67;

    try std.testing.expectEqual(67, ptr.*);
}

test "removeFast" {
    var list: PagedList(usize, 8) = .init(std.testing.allocator);
    defer list.deinit();

    try list.set(16, 42);
    const value = list.get(16).?;

    try std.testing.expectEqual(42, value);
    try std.testing.expectEqual(3, list.list.len());
    try std.testing.expectEqual(1, list.list.items()[2].?.len());

    list.removeFast(16);

    try std.testing.expectEqual(null, list.get(16));
    try std.testing.expectEqual(3, list.list.len());
    try std.testing.expectEqual(1, list.list.items()[2].?.len());
}

test "remove" {
    var list: PagedList(usize, 8) = .init(std.testing.allocator);
    defer list.deinit();

    try list.set(16, 42);
    try list.set(2, 67);
    const value = list.get(16).?;

    try std.testing.expectEqual(42, value);
    try std.testing.expectEqual(3, list.list.len());
    try std.testing.expectEqual(1, list.list.items()[2].?.len());

    list.remove(16);

    try std.testing.expectEqual(null, list.get(16));
    try std.testing.expectEqual(1, list.list.len());
    try std.testing.expectEqual(3, list.list.items()[0].?.len());
}
