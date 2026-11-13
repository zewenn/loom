const std = @import("std");
const core = @import("core.zig");

const Uuid = core.Uuid;

/// Create a version 4 UUID using a random number generator provided via the IO interface.
pub fn fromIo(io: std.Io) Uuid {
    var uuid: Uuid = undefined;
    io.random(std.mem.asBytes(&uuid));
    uuid &= 0xffffffffffffff3fff0fffffffffffff;
    uuid |= 0x00000000000000800040000000000000;
    return uuid;
}

/// Create a version 4 UUID using the provided random number generator.
pub fn fromRandom(random_source: std.Random) Uuid {
    var uuid: Uuid = undefined;
    random_source.bytes(std.mem.asBytes(&uuid));
    uuid &= 0xffffffffffffff3fff0fffffffffffff;
    uuid |= 0x00000000000000800040000000000000;
    return uuid;
}

/// Create a version 4 UUID using a single-threaded IO random source.
pub fn new() Uuid {
    var threaded_io = std.Io.Threaded.init_single_threaded;
    return fromIo(threaded_io.io());
}

test "create a version 4 UUID" {
    const first_uuid = fromIo(std.testing.io);
    try std.testing.expectEqual(core.Version.random, core.version(first_uuid));
    try std.testing.expectEqual(core.Variant.rfc4122, core.variant(first_uuid));

    const second_uuid = fromIo(std.testing.io);
    try std.testing.expectEqual(core.Version.random, core.version(second_uuid));
    try std.testing.expectEqual(core.Variant.rfc4122, core.variant(second_uuid));
    try std.testing.expect(first_uuid != second_uuid);

    const random_io_source: std.Random.IoSource = .{ .io = std.testing.io };
    const third_uuid = fromRandom(random_io_source.interface());
    try std.testing.expectEqual(core.Version.random, core.version(third_uuid));
    try std.testing.expectEqual(core.Variant.rfc4122, core.variant(third_uuid));
    try std.testing.expect(first_uuid != third_uuid);
    try std.testing.expect(second_uuid != third_uuid);

    const fourth_uuid = new();
    try std.testing.expectEqual(core.Version.random, core.version(fourth_uuid));
    try std.testing.expectEqual(core.Variant.rfc4122, core.variant(fourth_uuid));
    try std.testing.expect(first_uuid != fourth_uuid);
}
