const core = @import("root.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn structToU8Array(allocator: Allocator, object: anytype) ![]u8 {
    const T = @TypeOf(object);
    core.comptimeAssert(@typeInfo(T) == .@"struct", "object wasn't struct");

    const obj: T = object;
    const obj_bytes: []u8 = std.mem.asBytes(&obj);

    return try allocator.dupe(u8, obj_bytes);
}

pub fn u8ArrayToStruct(comptime T: type, bytes: []const u8) !T {
    if (bytes.len != @sizeOf(T)) {
        return error.InvalidSize;
    }

    return std.mem.bytesToValue(T, bytes[0..@sizeOf(T)]);
}
