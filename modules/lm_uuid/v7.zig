const std = @import("std");
const core = @import("core.zig");

const Uuid = core.Uuid;

/// Create a time-based version 7 UUID using the provided IO interface.
pub fn fromIo(io: std.Io) Uuid {
    const timestamp = std.Io.Timestamp.now(io, .real);
    const timestamp_48bit: u48 = @truncate(@as(u64, @bitCast(timestamp.toMilliseconds())));
    const random_io_source: std.Random.IoSource = .{ .io = io };
    return fromRandom(random_io_source.interface(), timestamp_48bit);
}

/// Create a time-based version 7 UUID using the provided random generator and Unix timestamp in milliseconds.
pub fn fromRandom(random_source: std.Random, timestamp_ms: u64) Uuid {
    const timestamp_48bit: u48 = @truncate(timestamp_ms);
    var uuid: Uuid = undefined;
    random_source.bytes(std.mem.asBytes(&uuid));
    uuid <<= 48;
    uuid |= @as(Uuid, @intCast(core.switchU48(timestamp_48bit)));
    uuid &= 0xffffffffffffff3fff0fffffffffffff;
    uuid |= 0x00000000000000800070000000000000;
    return uuid;
}

/// Create a time-based version 7 UUID using a single-threaded IO source.
pub fn new() Uuid {
    var threaded_io = std.Io.Threaded.init_single_threaded;
    return fromIo(threaded_io.io());
}

test "create a version 7 UUID" {
    const first_uuid = fromIo(std.testing.io);
    try std.testing.expectEqual(core.Version.time_based_epoch, core.version(first_uuid));
    try std.testing.expectEqual(core.Variant.rfc4122, core.variant(first_uuid));

    const second_uuid = fromIo(std.testing.io);
    try std.testing.expectEqual(core.Version.time_based_epoch, core.version(second_uuid));
    try std.testing.expectEqual(core.Variant.rfc4122, core.variant(second_uuid));
    try std.testing.expect(first_uuid != second_uuid);

    const random_io_source: std.Random.IoSource = .{ .io = std.testing.io };
    const fixed_timestamp_ms: u64 = 0x123456789abc;
    const third_uuid = fromRandom(random_io_source.interface(), fixed_timestamp_ms);
    try std.testing.expectEqual(core.Version.time_based_epoch, core.version(third_uuid));
    try std.testing.expectEqual(core.Variant.rfc4122, core.variant(third_uuid));
    try std.testing.expectEqual(@as(u32, 0x12345678), core.getTimeLow(third_uuid));
    try std.testing.expectEqual(@as(u16, 0x9abc), core.getTimeMid(third_uuid));

    const fourth_uuid = new();
    try std.testing.expectEqual(core.Version.time_based_epoch, core.version(fourth_uuid));
    try std.testing.expectEqual(core.Variant.rfc4122, core.variant(fourth_uuid));
    try std.testing.expect(first_uuid != fourth_uuid);
}
