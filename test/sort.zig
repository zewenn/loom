const lm = @import("loom");
const std = @import("std");

const sort = lm.sort;

const testing = std.testing;
const expect = testing.expect;
const expectError = testing.expectError;
const expectEqual = testing.expectEqual;
const expectEqualSlices = testing.expectEqualSlices;
const expectEqualStrings = testing.expectEqualStrings;

const TestStruct = struct {
    y: f32 = 0,
    z: f32 = 0,

    pub fn init(y: f32, z: f32) TestStruct {
        return TestStruct{
            .y = y,
            .z = z,
        };
    }

    pub fn orderFn(lhs: TestStruct, rhs: TestStruct) bool {
        const lhs_is_behind_rhs = lhs.z < rhs.z;
        const lhs_is_above_rhs = lhs.z == rhs.z and lhs.y < rhs.y;

        return lhs_is_behind_rhs or lhs_is_above_rhs;
    }
};

fn usizeEqls(lhs: usize, rhs: usize) bool {
    return lhs <= rhs;
}

test "merge sort items in an array" {
    var arr = try lm.Array(usize).init(std.testing.allocator, &.{ 3, 1, 2, 0 });
    defer arr.deinit();

    try expectEqualSlices(usize, &.{ 3, 1, 2, 0 }, arr.items());

    try sort.merge(usize, arr, 0, arr.len() - 1, usizeEqls);

    try expectEqualSlices(usize, &.{ 0, 1, 2, 3 }, arr.items());
}

test "merge sort TestStruct elements" {
    var arr = try lm.Array(TestStruct).init(std.testing.allocator, &.{
        .init(0, 0),
        .init(1, 1),
        .init(1, 0),
        .init(0, 1),
        .init(2, 1),
    });
    defer arr.deinit();

    try expectEqualSlices(
        TestStruct,
        &.{
            .init(0, 0),
            .init(1, 1),
            .init(1, 0),
            .init(0, 1),
            .init(2, 1),
        },
        arr.items(),
    );

    try sort.merge(TestStruct, arr, 0, arr.len() - 1, TestStruct.orderFn);

    try expectEqualSlices(
        TestStruct,
        &.{
            .init(0, 0),
            .init(1, 0),
            .init(0, 1),
            .init(1, 1),
            .init(2, 1),
        },
        arr.items(),
    );
}
