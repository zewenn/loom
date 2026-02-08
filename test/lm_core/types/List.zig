const std = @import("std");
const lm = @import("loom");

const List = lm.types.List;
const Array = lm.types.Array;

const expect = std.testing.expect;

test "init" {
    var test_list = List(u8).init(std.testing.allocator);
    defer test_list.deinit();
}

test "initWithItems" {
    var test_list = try List(u8).initWithItems(std.testing.allocator, &.{ 1, 2, 3 });
    defer test_list.deinit();

    try expect(test_list.at(0) == 1);
    try expect(test_list.at(1) == 2);
    try expect(test_list.at(2) == 3);
}

test "fromArray" {
    var test_array = try Array(u8).init(std.testing.allocator, &.{ 1, 2, 3 });
    defer test_array.deinit();

    var from_array = try List(u8).fromArray(test_array);
    defer from_array.deinit();

    try expect(from_array.at(0) == 1);
    try expect(from_array.at(1) == 2);
    try expect(from_array.at(2) == 3);

    try expect(from_array.len() == 3);
}

test "items" {
    var test_list = try List(u8).initWithItems(std.testing.allocator, &.{ 1, 2, 3 });
    defer test_list.deinit();

    try expect(std.meta.eql(test_list.items(), test_list.arrlist.items));
}

test "len" {
    var test_list = try List(u8).initWithItems(std.testing.allocator, &.{ 1, 2, 3 });
    defer test_list.deinit();

    try expect(std.meta.eql(test_list.items(), test_list.arrlist.items));
}

test "at" {
    var test_list = try List(u8).initWithItems(std.testing.allocator, &.{ 1, 2, 3 });
    defer test_list.deinit();

    try expect(test_list.at(0) == 1);
    try expect(test_list.at(1) == 2);
    try expect(test_list.at(2) == 3);
    try expect(test_list.at(4) == null);
    try expect(test_list.at(-1) == 3);

    var empty = try List(u8).initWithItems(std.testing.allocator, &.{});
    defer empty.deinit();

    try expect(empty.at(0) == null);
}

test "append" {
    var test_list = List(u8).init(std.testing.allocator);
    defer test_list.deinit();

    try test_list.append(234);

    try expect(test_list.len() == 1);
    try expect(test_list.at(0) == 234);
}

test "appendSlice" {
    var test_list = List(u8).init(std.testing.allocator);
    defer test_list.deinit();

    try test_list.appendSlice(&.{ 1, 2, 3 });

    try expect(test_list.len() == 3);
    try expect(test_list.at(0) == 1);
    try expect(test_list.at(1) == 2);
    try expect(test_list.at(2) == 3);
}

test "clearAndFree" {
    var test_list = try List(u8).initWithItems(std.testing.allocator, &.{ 1, 2, 3 });
    defer test_list.deinit();

    try expect(test_list.len() == 3);

    test_list.clearAndFree();

    try expect(test_list.len() == 0);
}

test "clearRetainingCapacity" {
    var test_list = try List(u8).initWithItems(std.testing.allocator, &.{ 1, 2, 3 });
    defer test_list.deinit();

    try expect(test_list.len() == 3);

    test_list.clearAndFree();

    try expect(test_list.len() == 0);
}

test "eql" {
    var test_list = try List(u8).initWithItems(std.testing.allocator, &.{ 1, 2, 3 });
    defer test_list.deinit();

    var other_list = try List(u8).initWithItems(std.testing.allocator, &.{ 1, 2, 3 });
    defer other_list.deinit();

    var not_equal_list = try List(u8).initWithItems(std.testing.allocator, &.{ 3, 2, 1 });
    defer not_equal_list.deinit();

    var not_equal_len_list = try List(u8).initWithItems(std.testing.allocator, &.{ 3, 2, 1 });
    defer not_equal_len_list.deinit();

    try expect(test_list.eql(other_list));
    try expect(!test_list.eql(not_equal_list));
    try expect(!test_list.eql(not_equal_len_list));
}

test "getLast" {
    var test_list = try List(u8).initWithItems(std.testing.allocator, &.{ 1, 2, 3 });
    defer test_list.deinit();

    try std.testing.expectEqual(test_list.getLast(), 3);
}

test "getLastOrNull" {
    var test_list = List(u8).init(std.testing.allocator);
    defer test_list.deinit();

    try expect(test_list.getLastOrNull() == null);

    try test_list.append(1);
    try test_list.append(2);

    try expect(test_list.getLastOrNull() == 2);
}

test "getFirst" {
    var test_list = try List(u8).initWithItems(std.testing.allocator, &.{ 1, 2, 3 });
    defer test_list.deinit();

    try std.testing.expectEqual(test_list.getFirst(), 1);
}

test "getFisrtOrNull" {
    var test_list = List(u8).init(std.testing.allocator);
    defer test_list.deinit();

    try expect(test_list.getFirstOrNull() == null);

    try test_list.append(1);
    try test_list.append(2);

    try expect(test_list.getFirstOrNull() == 1);
}

test "orderedRemove" {
    var test_list = try List(u8).initWithItems(std.testing.allocator, &.{ 1, 2, 3 });
    defer test_list.deinit();

    const removed = test_list.orderedRemove(1);

    try std.testing.expectEqualSlices(u8, &.{ 1, 3 }, test_list.items());
    try expect(removed == 2);
}

test "orderedRemoveMany" {
    var list = List(usize).init(std.testing.allocator);
    defer list.deinit();

    for (0..10) |n| {
        try list.append(n);
    }

    list.orderedRemoveMany(&.{ 1, 5, 5, 7, 9 });
    try std.testing.expectEqualSlices(usize, &.{ 0, 2, 3, 4, 6, 8 }, list.items());

    list.orderedRemoveMany(&.{0});
    try std.testing.expectEqualSlices(usize, &.{ 2, 3, 4, 6, 8 }, list.items());

    list.orderedRemoveMany(&.{});
    try std.testing.expectEqualSlices(usize, &.{ 2, 3, 4, 6, 8 }, list.items());

    list.orderedRemoveMany(&.{ 1, 2, 3, 4 });
    try std.testing.expectEqualSlices(usize, &.{2}, list.items());

    list.orderedRemoveMany(&.{0});
    try std.testing.expectEqualSlices(usize, &.{}, list.items());
}

test "swapRemove" {
    var test_list = try List(u8).initWithItems(std.testing.allocator, &.{ 1, 2, 3 });
    defer test_list.deinit();

    const removed = test_list.swapRemove(0);

    try std.testing.expectEqualSlices(u8, &.{ 3, 2 }, test_list.items());
    try expect(removed == 1);
}

test "pop" {
    var test_list = try List(u8).initWithItems(std.testing.allocator, &.{ 1, 2, 3 });
    defer test_list.deinit();

    var empty = List(u8).init(std.testing.allocator);
    defer empty.deinit();

    const popped = test_list.pop();
    try expect(popped == 3);
    try expect(test_list.len() == 2);

    const empty_popped = empty.pop();
    try expect(empty_popped == null);
    try expect(empty.len() == 0);
}

test "resize" {
    var test_list = try List(u8).initWithItems(std.testing.allocator, &.{ 1, 2, 3 });
    defer test_list.deinit();

    try expect(test_list.len() == 3);

    try test_list.resize(10);

    try expect(test_list.len() == 10);
}

test "shrinkAndFree" {
    var test_list = try List(u8).initWithItems(std.testing.allocator, &.{ 1, 2, 3, 4, 5 });
    defer test_list.deinit();

    try expect(test_list.len() == 5);

    test_list.shrinkAndFree(2);

    try expect(test_list.len() == 2);
}

test "toOwnedSlice" {
    var test_list = try List(u8).initWithItems(std.testing.allocator, &.{ 1, 2, 3, 4, 5 });
    defer test_list.deinit();

    try expect(test_list.len() == 5);

    const slice = try test_list.toOwnedSlice();
    defer std.testing.allocator.free(slice);

    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5 }, slice);
    try expect(test_list.len() == 0);
}

test "cloneToOwnedSlice" {
    var test_list = try List(u8).initWithItems(std.testing.allocator, &.{ 1, 2, 3, 4, 5 });
    defer test_list.deinit();

    try expect(test_list.len() == 5);

    const slice = try test_list.cloneToOwnedSlice();
    defer std.testing.allocator.free(slice);

    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5 }, slice);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5 }, test_list.items());
}

test "toArray" {
    var test_list = try List(u8).initWithItems(std.testing.allocator, &.{ 1, 2, 3, 4, 5 });
    defer test_list.deinit();

    try expect(test_list.len() == 5);

    var array = try test_list.toArray();
    defer array.deinit();

    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5 }, array.slice);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5 }, test_list.items());
}

test "map" {
    var test_list = try List(u8).initWithItems(std.testing.allocator, &.{ 1, 2, 3, 4, 5 });
    defer test_list.deinit();

    var squared = try test_list.map(usize, struct {
        pub fn callback(item: u8) ?usize {
            return std.math.pow(usize, @intCast(item), 2);
        }
    }.callback);
    defer squared.deinit();

    try std.testing.expectEqualSlices(usize, &.{ 1, 4, 9, 16, 25 }, squared.items());

    var squared_odds = try test_list.map(usize, struct {
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

    var test_list = try List(u8).initWithItems(std.testing.allocator, &.{ 1, 2, 3, 4, 5 });
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

    var test_list = try List(u8).initWithItems(std.testing.allocator, &.{ 1, 2, 3, 4, 5 });
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

    var test_list = try List(u8).initWithItems(std.testing.allocator, &.{ 1, 2, 3, 4, 5 });
    defer test_list.deinit();

    try test_list.forEach(s.forEachFn);

    try std.testing.expectError(error.MyError, test_list.forEach(s.errorForeach));
    try std.testing.expectEqual(@as(usize, 15), s.counter);
}
