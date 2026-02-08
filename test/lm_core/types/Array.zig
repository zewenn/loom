const std = @import("std");
const lm = @import("loom");

const List = lm.types.List;
const Array = lm.types.Array;

const expect = std.testing.expect;

test "init" {
    var my_array = try Array(u8).init(std.testing.allocator, &.{ 1, 2, 3 });
    defer my_array.deinit();

    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, my_array.items());
}

test "fromArrayList" {
    var array_list: std.ArrayList(u8) = .empty;
    defer array_list.deinit(std.testing.allocator);

    for (0..10) |item| {
        try array_list.append(std.testing.allocator, @intCast(item));
    }

    var my_array = try Array(u8).fromArrayList(std.testing.allocator, array_list);
    defer my_array.deinit();

    try std.testing.expectEqualSlices(u8, &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 }, my_array.items());
}

test "fromList" {
    var list: List(u8) = try .initWithItems(std.testing.allocator, &.{ 1, 2, 3 });
    defer list.deinit();

    var my_array: Array(u8) = try .fromList(list);
    defer my_array.deinit();

    try std.testing.expectEqualSlices(u8, list.items(), my_array.items());
}

test "items" {
    var my_array = try Array(u8).init(std.testing.allocator, &.{ 1, 2, 3 });
    defer my_array.deinit();

    try std.testing.expectEqualSlices(u8, my_array.slice, my_array.items());
}

test "len" {
    var my_array = try Array(u8).init(std.testing.allocator, &.{ 1, 2, 3 });
    defer my_array.deinit();

    try std.testing.expect(my_array.len() == 3);
    try std.testing.expect(my_array.len() == my_array.slice.len);
}

test "at" {
    var my_array = try Array(u8).init(std.testing.allocator, &.{ 1, 2, 3 });
    defer my_array.deinit();

    try std.testing.expectEqual(my_array.at(1), @as(u8, 2));
    try std.testing.expectEqual(my_array.at(1), my_array.slice[1]);

    try std.testing.expectEqual(my_array.at(-1), @as(u8, 3));
    try std.testing.expectEqual(my_array.at(-1), my_array.slice[my_array.len() - 1]);

    try std.testing.expect(my_array.at(-4) == null);
    try std.testing.expect(my_array.at(4) == null);
}

test "clone" {
    var my_array = try Array(u8).init(std.testing.allocator, &.{ 1, 2, 3 });
    defer my_array.deinit();

    var cloned = try my_array.clone();
    defer cloned.deinit();

    try std.testing.expectEqualSlices(u8, my_array.items(), cloned.items());
}

test "eql" {
    var my_array = try Array(u8).init(std.testing.allocator, &.{ 1, 2, 3 });
    defer my_array.deinit();

    var different_len_array = try Array(u8).init(std.testing.allocator, &.{ 1, 2, 3, 4 });
    defer different_len_array.deinit();

    var not_equal_array = try Array(u8).init(std.testing.allocator, &.{ 1, 2, 4 });
    defer not_equal_array.deinit();

    var equal = try my_array.clone();
    defer equal.deinit();

    try std.testing.expect(!my_array.eql(different_len_array));
    try std.testing.expect(!my_array.eql(not_equal_array));
    try std.testing.expect(my_array.eql(equal));
}

test "set" {
    var my_array = try Array(u8).init(std.testing.allocator, &.{ 1, 2, 3 });
    defer my_array.deinit();

    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, my_array.items());

    my_array.set(0, 0);
    my_array.set(-1, 0);

    my_array.set(-4, 0);
    my_array.set(4, 0);

    try std.testing.expectEqualSlices(u8, &.{ 0, 2, 0 }, my_array.items());
}

test "getFirst" {
    var my_array = try Array(u8).init(std.testing.allocator, &.{ 1, 2, 3 });
    defer my_array.deinit();

    try std.testing.expectEqual(@as(u8, 1), my_array.getFirst());
}

test "getLast" {
    var my_array = try Array(u8).init(std.testing.allocator, &.{ 1, 2, 3 });
    defer my_array.deinit();

    try std.testing.expectEqual(@as(u8, 3), my_array.getLast());
    try std.testing.expectEqual(my_array.at(-1), my_array.getLast());
    try std.testing.expectEqual(my_array.items()[my_array.len() - 1], my_array.getLast());
}

test "getFirstOrNull" {
    var my_array = try Array(u8).init(std.testing.allocator, &.{ 1, 2, 3 });
    defer my_array.deinit();

    try std.testing.expectEqual(@as(u8, 1), my_array.getFirstOrNull());

    var empty = try Array(u8).init(std.testing.allocator, &.{});
    defer empty.deinit();

    try std.testing.expect(empty.getFirstOrNull() == null);
}

test "getLastOrNull" {
    var my_array = try Array(u8).init(std.testing.allocator, &.{ 1, 2, 3 });
    defer my_array.deinit();

    try std.testing.expectEqual(@as(u8, 3), my_array.getLastOrNull());

    var empty = try Array(u8).init(std.testing.allocator, &.{});
    defer empty.deinit();

    try std.testing.expect(empty.getLastOrNull() == null);
}

test "clearAndFree" {
    var my_array = try Array(u8).init(std.testing.allocator, &.{ 1, 2, 3 });
    defer my_array.deinit();

    try std.testing.expect(my_array.len() == 3);

    my_array.clearAndFree();

    try std.testing.expect(my_array.len() == 0);
}

test "toOwnedSlice" {
    var my_array = try Array(u8).init(std.testing.allocator, &.{ 1, 2, 3 });
    defer my_array.deinit();

    const owned_slice = try my_array.toOwnedSlice();
    defer my_array.alloc.free(owned_slice);

    try std.testing.expect(my_array.len() == 0);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, owned_slice);
}

test "cloneToOwnedSlice" {
    var my_array = try Array(u8).init(std.testing.allocator, &.{ 1, 2, 3 });
    defer my_array.deinit();

    const owned_slice = try my_array.cloneToOwnedSlice();
    defer std.testing.allocator.free(owned_slice);

    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, my_array.items());
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, owned_slice);
}

test "toArrayList" {
    var my_array = try Array(u8).init(std.testing.allocator, &.{ 1, 2, 3 });
    defer my_array.deinit();

    var my_array_list = try my_array.toArrayList();
    defer my_array_list.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(u8, my_array.items(), my_array_list.items);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, my_array_list.items);
}

test "toList" {
    var my_array = try Array(u8).init(std.testing.allocator, &.{ 1, 2, 3 });
    defer my_array.deinit();

    var my_list = try my_array.toList();
    defer my_list.deinit();

    try std.testing.expectEqualSlices(u8, my_array.items(), my_list.items());
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, my_list.items());
}

test "map" {
    var my_array = try Array(u8).init(std.testing.allocator, &.{ 1, 2, 3, 4, 5 });
    defer my_array.deinit();

    var squared = try my_array.map(usize, struct {
        pub fn callback(item: u8) ?usize {
            return std.math.pow(usize, @intCast(item), 2);
        }
    }.callback);
    defer squared.deinit();

    try std.testing.expectEqualSlices(usize, &.{ 1, 4, 9, 16, 25 }, squared.items());

    var squared_odds = try my_array.map(usize, struct {
        pub fn callback(item: u8) ?usize {
            if (@rem(item, 2) == 0) return null;

            return std.math.pow(usize, @intCast(item), 2);
        }
    }.callback);
    defer squared_odds.deinit();

    try std.testing.expectEqualSlices(usize, &.{ 1, 9, 25 }, squared_odds.items());
}

test "reduce" {
    const sum = struct {
        pub fn sum(accumulator: u8, mappable: u8) u8 {
            return accumulator + mappable;
        }
    }.sum;

    var test_list = try Array(u8).init(std.testing.allocator, &.{ 1, 2, 3, 4, 5 });
    defer test_list.deinit();

    const summed = test_list.reduce(u8, 0, sum);

    try std.testing.expectEqual(summed, @as(u8, 1 + 2 + 3 + 4 + 5));
}

test "filter" {
    const onlyEven = struct {
        pub fn callback(item: u8) bool {
            return @rem(item, 2) == 0;
        }
    }.callback;

    var test_list = try Array(u8).init(std.testing.allocator, &.{ 1, 2, 3, 4, 5 });
    defer test_list.deinit();

    var only_even = try test_list.filter(onlyEven);
    defer only_even.deinit();

    try std.testing.expectEqualSlices(u8, &.{ 2, 4 }, only_even.items());
}

test "forEach" {
    const s = struct {
        pub var counter: u8 = 0;

        pub fn forEachFn(item: u8) !void {
            counter += item;
        }

        pub fn errorForeach(_: u8) !void {
            return error.MyError;
        }
    };

    var test_list = try Array(u8).init(std.testing.allocator, &.{ 1, 2, 3, 4, 5 });
    defer test_list.deinit();

    try test_list.forEach(s.forEachFn);

    try std.testing.expectError(error.MyError, test_list.forEach(s.errorForeach));
    try std.testing.expectEqual(@as(usize, 15), s.counter);
}
