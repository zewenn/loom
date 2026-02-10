const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");
const ByteList = core.ByteList;

const testing = std.testing;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectEqual = std.testing.expectEqual;

const MyTestType = struct {
    const size = std.mem.alignForward(usize, @sizeOf(MyTestType), @alignOf(MyTestType));

    a: u8 = 0,
    b: u32 = 12,
    c: u64 = 42,
};

test "initialize the ByteList correctly" {
    var my_byte_list: ByteList = .init(testing.allocator, MyTestType);
    defer my_byte_list.deinit();

    try expectEqual(comptime core.type_erasure.typeToHash(MyTestType), my_byte_list.entry_id);
    try expectEqual(MyTestType.size, my_byte_list.entry_size);
}

test "create from slice" {
    var my_byte_list: ByteList = try .initWithItems(MyTestType, testing.allocator, &.{
        MyTestType{
            .a = 0,
            .b = 1,
            .c = 2,
        },
        MyTestType{
            .a = 1,
            .b = 2,
            .c = 3,
        },
    });
    defer my_byte_list.deinit();

    try expectEqual(2, my_byte_list.len());
    try expectEqual(MyTestType.size * 2, my_byte_list.rawLen());
}

test "create from Array" {
    var my_array: core.Array(u32) = try .init(testing.allocator, &.{ 1, 2, 3 });
    defer my_array.deinit();

    var my_byte_list: ByteList = try .fromArray(u32, my_array);
    defer my_byte_list.deinit();

    try expectEqual(3, my_byte_list.len());
    try expectEqual(12, my_byte_list.rawLen());
}

test "create from List" {
    var my_list: core.List(u32) = try .initWithItems(testing.allocator, &.{ 1, 2, 3 });
    defer my_list.deinit();

    var my_byte_list: ByteList = try .fromList(u32, my_list);
    defer my_byte_list.deinit();

    try expectEqual(3, my_byte_list.len());
    try expectEqual(12, my_byte_list.rawLen());
}

test "append" {
    var my_byte_list: ByteList = .init(testing.allocator, u32);
    defer my_byte_list.deinit();

    try expectEqual(0, my_byte_list.len());

    try my_byte_list.append(@as(u32, 32));
    try my_byte_list.append(@as(u32, 42));
    try my_byte_list.append(@as(u32, 52));

    try expectEqual(3, my_byte_list.len());
}

test "appendSlice" {
    var my_byte_list: ByteList = .init(testing.allocator, u32);
    defer my_byte_list.deinit();

    try expectEqual(0, my_byte_list.len());

    try my_byte_list.appendSlice(u32, &.{ 0, 1, 2 });

    try expectEqual(3, my_byte_list.len());
}

test "set" {
    var my_byte_list: ByteList = try .initWithItems(u32, testing.allocator, &.{0});
    defer my_byte_list.deinit();

    var value: u32 = 1;

    try expectEqual(@as(u32, 0), my_byte_list.getAs(u32, 0).?.*);

    my_byte_list.set(0, &value);

    try expectEqual(@as(u32, 1), my_byte_list.getAs(u32, 0).?.*);
}

test "get & getAs" {
    var my_byte_list: ByteList = try .initWithItems(u32, testing.allocator, &.{0});
    defer my_byte_list.deinit();

    try expectEqual(@as(u32, 0), my_byte_list.getAs(u32, 0).?.*);
    try expectEqual(
        @as(u32, 0),
        core.ptrCast(u32, my_byte_list.getAs(u32, 0).?).*,
    );
}

test "slicedAs" {
    const test_slice: []const u32 = &.{ 0, 1, 2 };

    var my_byte_list: ByteList = try .initWithItems(u32, testing.allocator, test_slice);
    defer my_byte_list.deinit();

    try expectEqualSlices(u32, test_slice, my_byte_list.slicedAs(u32));
}

test "pop" {
    const value: u32 = 42;
    const sliced: []const u8 = std.mem.asBytes(&value);

    var my_byte_list: ByteList = try .initWithItems(u32, testing.allocator, &.{value});
    defer my_byte_list.deinit();

    try expectEqual(1, my_byte_list.len());

    const popped = my_byte_list.pop().?;

    try expectEqual(0, my_byte_list.len());
    try expectEqualSlices(u8, sliced, popped);
}

test "swapRemove" {
    var my_byte_list: ByteList = try .initWithItems(u32, testing.allocator, &.{ 0, 1, 2, 3 });
    defer my_byte_list.deinit();

    try expectEqual(4, my_byte_list.len());
    try expectEqual(@as(u32, 1), my_byte_list.getAs(u32, 1).?.*);

    my_byte_list.swapRemove(1);

    try expectEqual(3, my_byte_list.len());
    try expectEqual(@as(u32, 3), my_byte_list.getAs(u32, 1).?.*);
}

test "iterator" {
    var my_byte_list: ByteList = try .initWithItems(u32, testing.allocator, &.{ 0, 1, 2, 3 });
    defer my_byte_list.deinit();

    var i: usize = 0;
    const expected: []const u32 = &.{ 0, 1, 2, 3 };

    var iterator = my_byte_list.iterator();
    while (iterator.nextAs(u32)) |ptr| : (i += 1) {
        try std.testing.expectEqual(expected[i], ptr.*);
    }
}
