const std = @import("std");
const lm_core = @import("lm_core");

const coerceTo = lm_core.types.coerceTo;

test "coerceTo type handling" {
    const expect = std.testing.expect;
    const x = enum(u8) { a = 0, b = 32 };

    try expect(coerceTo(f32, 0) != null);
    try expect(coerceTo(i32, 0) != null);
    try expect(coerceTo(x, 0) != null);
    try expect(coerceTo(bool, 0) != null);
    try expect(coerceTo(*anyopaque, 1) != null);
}

test "coerceTo return type" {
    const expect = std.testing.expect;
    const x = enum(u8) { a = 0, b = 32 };

    try expect(@TypeOf(coerceTo(f32, 0).?) == f32);
    try expect(@TypeOf(coerceTo(i32, 0).?) == i32);
    try expect(@TypeOf(coerceTo(x, 0).?) == x);
    try expect(@TypeOf(coerceTo(*anyopaque, 1).?) == *anyopaque);
}

test "coerceTo int conversions" {
    const expect = std.testing.expect;
    const x = enum(u8) { a = 0, b = 32 };

    var int: usize = 32;
    const int_address: usize = @intFromPtr(&int);
    const @"comptime_int": comptime_int = 32;

    try expect(coerceTo(usize, -1).? == @as(usize, 0));
    try expect(coerceTo(u8, std.math.maxInt(u128)).? == @as(u8, 255));
    try expect(coerceTo(isize, int).? == @as(isize, 32));
    try expect(coerceTo(f32, int).? == @as(f32, 32.0));
    try expect(coerceTo(x, int).? == @as(x, x.b));
    try expect(coerceTo(bool, int).? == @as(bool, true));
    try expect(coerceTo(*usize, int_address).? == &int);

    try expect(coerceTo(isize, @"comptime_int").? == @as(isize, 32));
    try expect(coerceTo(f32, @"comptime_int").? == @as(f32, 32.0));
    try expect(coerceTo(x, @"comptime_int").? == @as(x, x.b));
    try expect(coerceTo(bool, @"comptime_int").? == @as(bool, true));
}

test "coerceTo float conversions" {
    const expect = std.testing.expect;
    const x = enum(u8) { a = 0, b = 32 };

    const float: f64 = 32.34;
    const @"comptime_float": comptime_float = 32.34;

    try expect(coerceTo(isize, float).? == @as(isize, 32));
    try expect(coerceTo(u8, std.math.floatMax(f128)).? == @as(u8, 255));
    try expect(coerceTo(f32, float).? == @as(f32, 32.34));
    try expect(coerceTo(x, float).? == @as(x, x.b));
    try expect(coerceTo(bool, float).? == @as(bool, true));

    try expect(coerceTo(isize, @"comptime_float").? == @as(isize, 32));
    try expect(coerceTo(f32, @"comptime_float").? == @as(f32, 32.34));
    try expect(coerceTo(x, @"comptime_float").? == @as(x, x.b));
    try expect(coerceTo(bool, @"comptime_float").? == @as(bool, true));
}

test "coerceTo enum conversions" {
    const expect = std.testing.expect;
    const x = enum(u8) { a = 0, b = 32 };
    const @"enum": x = x.b;

    try expect(coerceTo(isize, @"enum").? == @as(isize, 32));
    try expect(coerceTo(f32, @"enum").? == @as(f32, 32.0));
    try expect(coerceTo(x, @"enum").? == @as(x, x.b));
    try expect(coerceTo(bool, @"enum").? == @as(bool, true));
}

test "coerceTo bool conversions" {
    const expect = std.testing.expect;
    const x = enum(u8) { a = 0, b = 32 };

    const boolean: bool = false;

    try expect(coerceTo(isize, boolean).? == @as(isize, 0));
    try expect(coerceTo(f32, boolean).? == @as(f32, 0.0));
    try expect(coerceTo(x, boolean).? == @as(x, x.a));
    try expect(coerceTo(bool, boolean).? == @as(bool, false));
}

test "coerceTo pointer conversions" {
    const expect = std.testing.expect;
    const x = enum(u8) { a = 0, b = 32 };
    const @"enum": x = x.b;

    var int: usize = 32;
    const int_address: usize = @intFromPtr(&int);
    const anyopaque_ptr_of_int: *anyopaque = @ptrCast(@alignCast(&int));

    try expect(coerceTo(usize, &int) == int_address);
    try expect(coerceTo(f64, &int) == @as(f64, @floatFromInt(int_address)));
    try expect(coerceTo(bool, &int) == (int_address != 0));
    try expect(coerceTo(x, @as(*anyopaque, @ptrFromInt(32))) == @"enum");
    try expect(coerceTo(*usize, anyopaque_ptr_of_int) == &int);
}
