const std = @import("std");

pub const Uuid = struct {
    bytes: [16]u8,

    /// Generate a UUIDv4 using the provided random number generator.
    pub fn v4(random: std.Random) Uuid {
        var out: [16]u8 = undefined;
        random.bytes(&out);
        // Set version to 4
        out[6] = (out[6] & 0x0f) | 0x40;
        // Set variant to 10xx
        out[8] = (out[8] & 0x3f) | 0x80;
        return .{ .bytes = out };
    }

    /// Generate a UUIDv7 using the provided random number generator and a Unix timestamp in milliseconds.
    pub fn v7(random: std.Random, timestamp_ms: u64) Uuid {
        var out: [16]u8 = undefined;
        
        // 48-bit timestamp (big-endian)
        out[0] = @truncate(timestamp_ms >> 40);
        out[1] = @truncate(timestamp_ms >> 32);
        out[2] = @truncate(timestamp_ms >> 24);
        out[3] = @truncate(timestamp_ms >> 16);
        out[4] = @truncate(timestamp_ms >> 8);
        out[5] = @truncate(timestamp_ms);

        // Randomness for the rest
        random.bytes(out[6..16]);

        // Set version to 7
        out[6] = (out[6] & 0x0f) | 0x70;
        // Set variant to 10xx
        out[8] = (out[8] & 0x3f) | 0x80;
        
        return .{ .bytes = out };
    }

    /// Returns the UUID as a standard 36-character string.
    pub fn toString(self: Uuid) [36]u8 {
        var buf: [36]u8 = undefined;
        const b = self.bytes;
        _ = std.fmt.bufPrint(&buf, "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
            b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
            b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15],
        }) catch unreachable;
        return buf;
    }

    /// Format the UUID using standard formatting.
    pub fn format(
        self: Uuid,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        const b = self.bytes;
        try writer.print("{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
            b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
            b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15],
        });
    }
};

test "Uuid v4" {
    var prng = std.Random.DefaultPrng.init(0);
    const id = Uuid.v4(prng.random());
    try std.testing.expectEqual(@as(u8, 0x40), id.bytes[6] & 0xf0);
    try std.testing.expectEqual(@as(u8, 0x80), id.bytes[8] & 0xc0);
    
    const str = id.toString();
    try std.testing.expectEqual(str.len, 36);
    try std.testing.expectEqual(str[8], '-');
    try std.testing.expectEqual(str[13], '-');
    try std.testing.expectEqual(str[18], '-');
    try std.testing.expectEqual(str[23], '-');
}

test "Uuid v7" {
    var prng = std.Random.DefaultPrng.init(0);
    const ts: u64 = 0x123456789abc;
    const id = Uuid.v7(prng.random(), ts);
    try std.testing.expectEqual(@as(u8, 0x70), id.bytes[6] & 0xf0);
    try std.testing.expectEqual(@as(u8, 0x80), id.bytes[8] & 0xc0);
    try std.testing.expectEqual(@as(u8, 0x12), id.bytes[0]);
    try std.testing.expectEqual(@as(u8, 0x34), id.bytes[1]);
    try std.testing.expectEqual(@as(u8, 0x56), id.bytes[2]);
    try std.testing.expectEqual(@as(u8, 0x78), id.bytes[3]);
    try std.testing.expectEqual(@as(u8, 0x9a), id.bytes[4]);
    try std.testing.expectEqual(@as(u8, 0xbc), id.bytes[5]);
}
