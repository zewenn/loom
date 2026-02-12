const core = @import("root.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn structToU8Array(allocator: Allocator, object: anytype) ![]u8 {
    const T = @TypeOf(object);
    core.comptimeAssert(@typeInfo(T) == .@"struct", "object wasn't struct");

    var obj: T = object;
    const obj_bytes: []u8 = std.mem.asBytes(&obj);

    return try allocator.dupe(u8, obj_bytes);
}

pub fn structToU8ArrayDest(object: anytype, dest: []u8) void {
    const T = @TypeOf(object);
    core.comptimeAssert(@typeInfo(T) == .@"struct", "object wasn't struct");

    var obj: T = object;
    const obj_bytes: []u8 = std.mem.asBytes(&obj);

    core.assert(dest.len >= obj_bytes.len, "invalid dest size");
    @memcpy(dest[0..obj_bytes.len], obj_bytes);
}

pub fn u8ArrayToStruct(comptime T: type, bytes: []u8) !T {
    if (bytes.len != @sizeOf(T)) {
        return error.InvalidSize;
    }

    return std.mem.bytesToValue(T, bytes[0..@sizeOf(T)]);
}

pub fn u8ArrayToStructPtr(comptime T: type, bytes: []u8) !*T {
    if (bytes.len != @sizeOf(T)) {
        return error.InvalidSize;
    }

    return @ptrCast(@alignCast(bytes.ptr));
}

pub inline fn alignedSize(comptime T: type) usize {
    return std.mem.alignForward(usize, @sizeOf(T), @alignOf(T));
}

pub inline fn typeToHash(comptime T: type) u64 {
    const struct_hash: comptime_int = comptime switch (@typeInfo(T)) {
        .@"struct", .@"enum" => blk: {
            var fieldsum: comptime_int = 1;

            for (std.meta.fields(T), 0..) |field, index| {
                for (field.name, 0..) |char, jndex| {
                    fieldsum += (@as(comptime_int, @intCast(char)) *
                        (@as(comptime_int, @intCast(jndex)) + 1) *
                        (@as(comptime_int, @intCast(index)) + 1)) % std.math.maxInt(u63);
                }
            }

            break :blk fieldsum;
        },
        else => 1,
    };

    const size: comptime_int = comptime switch (@typeInfo(T)) {
        .@"fn" => 1,
        else => @sizeOf(T),
    };

    var name_hash: comptime_int = 0;

    inline for (@typeName(T)) |char| {
        name_hash += @as(comptime_int, @intCast(char)) *
            (@as(comptime_int, @intCast(@alignOf(T))) + 1);
    }

    return (@max(1, size) * @max(1, @alignOf(T)) +
        @max(1, size * 8) * @max(1, @alignOf(T)) +
        struct_hash * name_hash * @max(1, @alignOf(T)) * 13) % std.math.maxInt(u63);
}
