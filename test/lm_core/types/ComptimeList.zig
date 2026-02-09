const core = @import("lm_core");
const ComptimeList = core.ComptimeList;

const std = @import("std");
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectEqual = std.testing.expectEqual;

test "ComptimeList: String Manipulation and Basic Ops" {
    comptime {
        var list = ComptimeList([]const u8).init();

        list.append("Zig");
        list.append("is");
        list.append("fun");

        try expectEqual(@as(usize, 3), list.len());
        try expectEqualStrings("Zig", list.at(0).?);

        try expectEqualStrings("fun", list.at(-1).?);
        try expectEqualStrings("is", list.at(-2).?);

        const popped = list.pop().?;
        try expectEqualStrings("fun", popped);
        try expectEqual(@as(usize, 2), list.len());
    }
}

test "ComptimeList: Functional Logic (Filter & Map)" {
    comptime {
        var list = ComptimeList([]const u8).initWithItems(&.{ "apple", "banana", "cherry", "date" });

        const Helpers = struct {
            fn isLong(comptime s: []const u8) bool {
                return s.len > 5;
            }
            fn toUpper(comptime s: []const u8) ?[]const u8 {
                return if (std.mem.eql(u8, s, "banana")) "BANANA" else "CHERRY";
            }
        };

        var filtered = list.filter(Helpers.isLong);
        try expectEqual(@as(usize, 2), filtered.len());

        var mapped = filtered.map([]const u8, Helpers.toUpper);
        try expectEqualStrings("BANANA", mapped.at(0).?);
    }
}

test "ComptimeList: Removal and Resize" {
    comptime {
        var list = ComptimeList(i32).initWithItems(&.{ 10, 20, 30, 40 });

        const removed = list.orderedRemove(1);
        try expectEqual(@as(i32, 20), removed);
        try expectEqual(@as(i32, 30), list.at(1).?);

        list.resize(1);
        try expectEqual(@as(usize, 1), list.len());
        try expectEqual(@as(i32, 10), list.at(0).?);
    }
}

test "ComptimeList: init" {
    comptime {
        const test_list = ComptimeList(u8).init();
        try expect(test_list.len() == 0);
    }
}

test "ComptimeList: initWithItems" {
    comptime {
        var test_list = ComptimeList(u8).initWithItems(&.{ 1, 2, 3 });

        try expect(test_list.at(0).? == 1);
        try expect(test_list.at(1).? == 2);
        try expect(test_list.at(2).? == 3);
    }
}

test "ComptimeList: items and len" {
    comptime {
        var test_list = ComptimeList(u8).initWithItems(&.{ 1, 2, 3 });
        try expectEqual(@as(usize, 3), test_list.len());
        try expectEqualSlices(u8, &.{ 1, 2, 3 }, test_list.items());
    }
}

test "ComptimeList: at" {
    comptime {
        var test_list = ComptimeList(u8).initWithItems(&.{ 1, 2, 3 });

        try expect(test_list.at(0).? == 1);
        try expect(test_list.at(1).? == 2);
        try expect(test_list.at(2).? == 3);
        try expect(test_list.at(4) == null);
        try expect(test_list.at(-1).? == 3); // Negative indexing support

        var empty = ComptimeList(u8).init();
        try expect(empty.at(0) == null);
    }
}

test "ComptimeList: append and appendSlice" {
    comptime {
        var test_list = ComptimeList(u8).init();

        test_list.append(234);
        try expect(test_list.len() == 1);
        try expect(test_list.at(0).? == 234);

        test_list.appendSlice(&.{ 1, 2, 3 });
        try expect(test_list.len() == 4);
        try expectEqualSlices(u8, &.{ 234, 1, 2, 3 }, test_list.items());
    }
}

test "ComptimeList: clear" {
    comptime {
        var test_list = ComptimeList(u8).initWithItems(&.{ 1, 2, 3 });
        try expect(test_list.len() == 3);

        test_list.clear();
        try expect(test_list.len() == 0);
    }
}

test "ComptimeList: getFirst and getLast" {
    comptime {
        var test_list = ComptimeList(u8).initWithItems(&.{ 1, 2, 3 });

        try expectEqual(test_list.getFirst(), 1);
        try expectEqual(test_list.getLast(), 3);

        try expectEqual(test_list.getFirstOrNull().?, 1);
        try expectEqual(test_list.getLastOrNull().?, 3);
    }
}

test "ComptimeList: orderedRemove" {
    comptime {
        var test_list = ComptimeList(u8).initWithItems(&.{ 1, 2, 3 });

        const removed = test_list.orderedRemove(1);

        try expectEqualSlices(u8, &.{ 1, 3 }, test_list.items());
        try expect(removed == 2);
    }
}

test "ComptimeList: swapRemove" {
    comptime {
        var test_list = ComptimeList(u8).initWithItems(&.{ 1, 2, 3 });

        // Intended behavior: last item (3) moves to index 0
        const removed = test_list.swapRemove(0);

        try expectEqualSlices(u8, &.{ 3, 2 }, test_list.items());
        try expect(removed == 1);
    }
}

test "ComptimeList: pop" {
    comptime {
        var test_list = ComptimeList(u8).initWithItems(&.{ 1, 2, 3 });

        const popped = test_list.pop();
        try expect(popped.? == 3);
        try expect(test_list.len() == 2);

        var empty = ComptimeList(u8).init();
        try expect(empty.pop() == null);
    }
}

test "ComptimeList: resize and shrink" {
    comptime {
        var test_list = ComptimeList(u8).initWithItems(&.{ 1, 2, 3 });

        test_list.resize(5);
        try expect(test_list.len() == 5);
        // Elements 4 and 5 are 'undefined', but length is updated

        test_list.shrink(2);
        try expect(test_list.len() == 2);
        try expectEqualSlices(u8, &.{ 1, 2 }, test_list.items());
    }
}

test "ComptimeList: map" {
    comptime {
        var test_list = ComptimeList(u8).initWithItems(&.{ 1, 2, 3, 4, 5 });

        const Mapper = struct {
            fn square(comptime item: u8) ?usize {
                return @as(usize, item) * item;
            }
        };

        var squared = test_list.map(usize, Mapper.square);
        try expectEqualSlices(usize, &.{ 1, 4, 9, 16, 25 }, squared.items());
    }
}

test "ComptimeList: reduce" {
    comptime {
        const Reducer = struct {
            fn sum(comptime acc: u8, comptime item: u8) u8 {
                return acc + item;
            }
        };

        var test_list = ComptimeList(u8).initWithItems(&.{ 1, 2, 3, 4, 5 });
        const result = test_list.reduce(u8, 0, Reducer.sum);

        try expectEqual(@as(u8, 15), result);
    }
}

test "ComptimeList: filter" {
    comptime {
        const Filterer = struct {
            fn onlyEven(comptime item: u8) bool {
                return @rem(item, 2) == 0;
            }
        };

        var test_list = ComptimeList(u8).initWithItems(&.{ 1, 2, 3, 4, 5 });
        var filtered = test_list.filter(Filterer.onlyEven);

        try expectEqualSlices(u8, &.{ 2, 4 }, filtered.items());
    }
}
