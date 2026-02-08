const std = @import("std");
const core = @import("lm_core");

const te = core.type_erasure;

const MyData = struct { x: u32, y: u32 };

test "struct to bytes" {
    const data = MyData{ .x = 1, .y = 2 };

    const bytes = try te.structToU8Array(std.testing.allocator, data);
    defer std.testing.allocator.free(bytes);

    try std.testing.expectEqual(@sizeOf(MyData), bytes.len);
}

test "bytes to struct" {
    const data = MyData{ .x = 1, .y = 2 };

    const bytes = try te.structToU8Array(std.testing.allocator, data);
    defer std.testing.allocator.free(bytes);

    const restored_data = try te.u8ArrayToStruct(MyData, bytes);

    try std.testing.expectEqual(data, restored_data);
}

test "bytes to ptr" {
    const data = MyData{ .x = 1, .y = 2 };

    const bytes = try te.structToU8Array(std.testing.allocator, data);
    defer std.testing.allocator.free(bytes);

    const ptr = try te.u8ArrayToStructPtr(MyData, bytes);
    ptr.x = 10;

    const restored_data = try te.u8ArrayToStruct(MyData, bytes);

    try std.testing.expect(restored_data.x == 10);
}
