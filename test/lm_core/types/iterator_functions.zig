const std = @import("std");
const lm = @import("loom");

const map = lm.types.iterator_functions.map;
const reduce = lm.types.iterator_functions.reduce;
const filter = lm.types.iterator_functions.filter;
const forEach = lm.types.iterator_functions.forEach;

test map {
    const mapFunc = struct {
        pub fn mapFunc(mappable: usize) ?u8 {
            return @as(u8, @intCast(@min(255, mappable)));
        }
    }.mapFunc;

    const mapOrNullFunc = struct {
        pub fn mapOrNullFunc(mappable: usize) ?u8 {
            if (mappable > 255) return null;
            return @intCast(mappable);
        }
    }.mapOrNullFunc;

    var array = [_]usize{ 1, 2, 3, 256, 255 };

    const mapped = try map(usize, u8, std.testing.allocator, &array, mapFunc);
    defer std.testing.allocator.free(mapped);

    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 255, 255 }, mapped);

    const mapped_or_ignored = try map(usize, u8, std.testing.allocator, &array, mapOrNullFunc);
    defer std.testing.allocator.free(mapped_or_ignored);

    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 255 }, mapped_or_ignored);
}

test reduce {
    const sum = struct {
        pub fn sum(accumulator: usize, mappable: usize) usize {
            return accumulator + mappable;
        }
    }.sum;

    var array = [_]usize{ 1, 2, 3 };

    const summed = reduce(usize, usize, &array, 0, sum);
    try std.testing.expectEqual(@as(usize, 6), summed);
}

test filter {
    const largerThan10 = struct {
        pub fn largerThan10(item: usize) bool {
            return item > 10;
        }
    }.largerThan10;

    var array = [_]usize{ 1, 12, 3, 14 };

    const filtered = try filter(usize, std.testing.allocator, &array, largerThan10);
    defer std.testing.allocator.free(filtered);

    try std.testing.expectEqualSlices(usize, &.{ 12, 14 }, filtered);
}

test forEach {
    const s = struct {
        pub var counter: usize = 0;

        pub fn forEachFn(item: usize) !void {
            counter += item;
        }
    };

    var array = [_]usize{ 1, 2, 3 };

    try forEach(usize, &array, s.forEachFn);

    try std.testing.expectEqual(@as(usize, 6), s.counter);
}
