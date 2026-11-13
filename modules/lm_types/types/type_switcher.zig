const std = @import("std");

pub fn safeIntCast(comptime T: type, value2: anytype) T {
    if (std.math.maxInt(T) < value2) {
        return std.math.maxInt(T);
    }
    if (std.math.minInt(T) > value2) {
        return std.math.minInt(T);
    }

    return @intCast(value2);
}

pub inline fn coerceTo(comptime T: type, value: anytype) ?T {
    const K = @TypeOf(value);
    if (K == T) return value;

    const value_info = @typeInfo(K);

    return switch (@typeInfo(T)) {
        .int, .comptime_int => switch (value_info) {
            .int, .comptime_int => safeIntCast(T, value),
            .float, .comptime_float => @intFromFloat(
                @max(
                    @as(K, @floatFromInt(std.math.minInt(T))),
                    @min(@as(K, @floatFromInt(std.math.maxInt(T))), @round(value)),
                ),
            ),
            .bool => @as(T, @intFromBool(value)),
            .@"enum" => @as(T, @intFromEnum(value)),
            .pointer => safeIntCast(T, @as(usize, @intFromPtr(value))),
            else => null,
        },
        .float, .comptime_float => switch (value_info) {
            .int, .comptime_int => @as(T, @floatFromInt(value)),
            .float, .comptime_float => @as(T, @floatCast(value)),
            .bool => @as(T, @floatFromInt(@intFromBool(value))),
            .@"enum" => @as(T, @floatFromInt(@intFromEnum(value))),
            .pointer => @as(T, @floatFromInt(@as(usize, @intFromPtr(value)))),
            else => null,
        },
        .bool => switch (value_info) {
            .int, .comptime_int => value != 0,
            .float, .comptime_float => @as(isize, @intFromFloat(@round(value))) != 0,
            .bool => value,
            .@"enum" => @as(isize, @intFromEnum(value)) != 0,
            .pointer => @as(usize, @intFromPtr(value)) != 0,
            else => null,
        },
        .@"enum" => switch (value_info) {
            .int, .comptime_int => @enumFromInt(value),
            .float, .comptime_float => @enumFromInt(@as(isize, @intFromFloat(@round(value)))),
            .bool => @enumFromInt(@intFromBool(value)),
            .@"enum" => |enum_info| @enumFromInt(@as(enum_info.tag_type, @intFromEnum(value))),
            .pointer => @enumFromInt(@as(usize, @intFromPtr(value))),
            else => null,
        },
        .pointer => switch (value_info) {
            .int, .comptime_int => @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(value)))),
            .float, .comptime_float => @compileError("Cannot convert float to pointer address"),
            .bool => @compileError("Cannot convert bool to pointer address"),
            .@"enum" => @compileError("Cannot convert enum to pointer address"),
            .pointer => @ptrCast(@alignCast(value)),
            else => null,
        },
        else => Catch: {
            std.log.warn(
                "cannot change type of \"{any}\" to type \"{any}\"",
                .{ @TypeOf(value), T },
            );
            break :Catch null;
        },
    };
}
