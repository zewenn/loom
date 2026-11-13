const std = @import("std");

/// Universally Unique IDentifier.
///
/// A UUID is 128 bits long and guarantees uniqueness across space and time (RFC 4122 / RFC 9562).
pub const Uuid = u128;

/// Switch a 16-bit integer between little and big endian.
pub fn switchU16(value: u16) u16 {
    return ((value >> 8) & 0x00ff) | ((value << 8) & 0xff00);
}

/// Switch a 32-bit integer between little and big endian.
pub fn switchU32(value: u32) u32 {
    return ((value >> 24) & 0x000000ff) | ((value >> 8) & 0x0000ff00) | ((value << 8) & 0x00ff0000) | ((value << 24) & 0xff000000);
}

/// Switch a 48-bit integer between little and big endian.
pub fn switchU48(value: u48) u48 {
    return ((value >> 40) & 0x0000000000ff) | ((value >> 24) & 0x00000000ff00) | ((value >> 8) & 0x000000ff0000) | ((value << 8) & 0x0000ff000000) | ((value << 24) & 0x00ff00000000) | ((value << 40) & 0xff0000000000);
}

/// Read the `time_low` field in host byte order.
pub fn getTimeLow(uuid: Uuid) u32 {
    return switchU32(@as(u32, @intCast(uuid & 0xffffffff)));
}

/// Write the `time_low` field from host byte order.
pub fn setTimeLow(uuid: *Uuid, value: u32) void {
    uuid.* &= ~@as(Uuid, @intCast(0xffffffff));
    uuid.* |= @as(Uuid, @intCast(switchU32(value)));
}

/// Read the `time_mid` field in host byte order.
pub fn getTimeMid(uuid: Uuid) u16 {
    return switchU16(@as(u16, @intCast((uuid >> 32) & 0xffff)));
}

/// Write the `time_mid` field from host byte order.
pub fn setTimeMid(uuid: *Uuid, value: u16) void {
    uuid.* &= ~(@as(Uuid, @intCast(0xffff)) << 32);
    uuid.* |= @as(Uuid, @intCast(switchU16(value))) << 32;
}

/// Read the `time_hi_and_version` field in host byte order.
pub fn getTimeHiAndVersion(uuid: Uuid) u16 {
    return switchU16(@as(u16, @intCast((uuid >> 48) & 0xffff)));
}

/// Write the `time_hi_and_version` field from host byte order.
pub fn setTimeHiAndVersion(uuid: *Uuid, value: u16) void {
    uuid.* &= ~(@as(Uuid, @intCast(0xffff)) << 48);
    uuid.* |= @as(Uuid, @intCast(switchU16(value))) << 48;
}

/// Read the `clock_seq_hi_and_reserved` field.
pub fn getClockSeqHiAndReserved(uuid: Uuid) u8 {
    return @as(u8, @intCast((uuid >> 64) & 0xff));
}

/// Write the `clock_seq_hi_and_reserved` field.
pub fn setClockSeqHiAndReserved(uuid: *Uuid, value: u8) void {
    uuid.* &= ~(@as(Uuid, @intCast(0xff)) << 64);
    uuid.* |= @as(Uuid, @intCast(value)) << 64;
}

/// Read the `clock_seq_low` field.
pub fn getClockSeqLow(uuid: Uuid) u8 {
    return @as(u8, @intCast((uuid >> 72) & 0xff));
}

/// Write the `clock_seq_low` field.
pub fn setClockSeqLow(uuid: *Uuid, value: u8) void {
    uuid.* &= ~(@as(Uuid, @intCast(0xff)) << 72);
    uuid.* |= @as(Uuid, @intCast(value)) << 72;
}

/// Read the `node` field in host byte order.
pub fn getNode(uuid: Uuid) u48 {
    return switchU48(@as(u48, @intCast((uuid >> 80) & 0xffffffffffff)));
}

/// Write the `node` field from host byte order.
pub fn setNode(uuid: *Uuid, value: u48) void {
    uuid.* &= ~(@as(Uuid, @intCast(0xffffffffffff)) << 80);
    uuid.* |= @as(Uuid, @intCast(switchU48(value))) << 80;
}

/// The variant field determines the layout of the UUID.
pub const Variant = enum {
    /// Reserved, NCS backward compatibility.
    reserved_bw,
    /// The variant specified in RFC 4122.
    rfc4122,
    /// Reserved, Microsoft Corporation backward compatibility.
    reserved_ms,
    /// Reserved for future definition.
    reserved_fu,
    /// Version 6, 7 and 8.
    new_formats,
};

/// Get the variant of the given UUID.
pub fn variant(uuid: Uuid) Variant {
    return switch (getClockSeqHiAndReserved(uuid) >> 5) {
        0, 1, 2, 3 => .reserved_bw,
        4, 5 => .rfc4122,
        6 => .reserved_ms,
        7 => .reserved_fu,
        8, 9, 0xA, 0xB => .new_formats,
        else => unreachable,
    };
}

/// The version (sub-type) of a UUID.
///
/// Versions:
/// * `time_based` - Version 1 UUIDs using a timestamp and monotonic counter
/// * `dce_security` - Version 2 DCE UUIDs
/// * `name_based_md5` - Version 3 UUIDs based on the MD5 hash of some data
/// * `random` - Version 4 UUIDs with random data
/// * `name_based_sha1` - Version 5 UUIDs based on the SHA-1 hash of some data
/// * `time_based_greg` - Version 6 UUIDs using a Gregorian calendar timestamp
/// * `time_based_epoch` - Version 7 UUIDs using an epoch timestamp
/// * `custom` - Version 8 UUIDs are vendor specific
pub const Version = enum(u4) {
    time_based = 1,
    dce_security = 2,
    name_based_md5 = 3,
    random = 4,
    name_based_sha1 = 5,
    time_based_greg = 6,
    time_based_epoch = 7,
    custom = 8,
    ndef,
};

/// Get the version of the given UUID.
pub fn version(uuid: Uuid) Version {
    return switch ((getTimeHiAndVersion(uuid) >> 12) & 0xf) {
        1 => .time_based,
        2 => .dce_security,
        3 => .name_based_md5,
        4 => .random,
        5 => .name_based_sha1,
        6 => .time_based_greg,
        7 => .time_based_epoch,
        8 => .custom,
        else => .ndef,
    };
}

test "get/set time_low" {
    var uuid: Uuid = 0xffeeddccbbaa99887766554433221100;
    try std.testing.expectEqual(@as(u32, @intCast(0x00112233)), getTimeLow(uuid));

    setTimeLow(&uuid, 0xaabbccdd);
    try std.testing.expectEqual(@as(u32, @intCast(0xaabbccdd)), getTimeLow(uuid));
}

test "get/set time_mid" {
    var uuid: Uuid = 0xffeeddccbbaa99887766554433221100;
    try std.testing.expectEqual(@as(u16, @intCast(0x4455)), getTimeMid(uuid));

    setTimeMid(&uuid, 0xaabb);
    try std.testing.expectEqual(@as(Uuid, @intCast(0xffeeddccbbaa99887766bbaa33221100)), uuid);
    try std.testing.expectEqual(@as(u16, @intCast(0xaabb)), getTimeMid(uuid));
}

test "get/set time_hi_and_version" {
    var uuid: Uuid = 0xffeeddccbbaa99887766554433221100;
    try std.testing.expectEqual(@as(u16, @intCast(0x6677)), getTimeHiAndVersion(uuid));

    setTimeHiAndVersion(&uuid, 0xaabb);
    try std.testing.expectEqual(@as(Uuid, @intCast(0xffeeddccbbaa9988bbaa554433221100)), uuid);
    try std.testing.expectEqual(@as(u16, @intCast(0xaabb)), getTimeHiAndVersion(uuid));
}

test "get/set clock_seq_hi_and_reserved" {
    var uuid: Uuid = 0xffeeddccbbaa99887766554433221100;
    try std.testing.expectEqual(@as(u8, @intCast(0x88)), getClockSeqHiAndReserved(uuid));

    setClockSeqHiAndReserved(&uuid, 0xff);
    try std.testing.expectEqual(@as(Uuid, @intCast(0xffeeddccbbaa99ff7766554433221100)), uuid);
    try std.testing.expectEqual(@as(u8, @intCast(0xff)), getClockSeqHiAndReserved(uuid));
}

test "get/set clock_seq_low" {
    var uuid: Uuid = 0xffeeddccbbaa99887766554433221100;
    try std.testing.expectEqual(@as(u8, @intCast(0x99)), getClockSeqLow(uuid));

    setClockSeqLow(&uuid, 0xff);
    try std.testing.expectEqual(@as(Uuid, @intCast(0xffeeddccbbaaff887766554433221100)), uuid);
    try std.testing.expectEqual(@as(u8, @intCast(0xff)), getClockSeqLow(uuid));
}

test "get/set node" {
    var uuid: Uuid = 0xffeeddccbbaa99887766554433221100;
    try std.testing.expectEqual(@as(u48, @intCast(0xaabbccddeeff)), getNode(uuid));

    setNode(&uuid, 0x001122334455);
    try std.testing.expectEqual(@as(Uuid, @intCast(0x55443322110099887766554433221100)), uuid);
    try std.testing.expectEqual(@as(u48, @intCast(0x001122334455)), getNode(uuid));
}

test "get variant" {
    try std.testing.expectEqual(Variant.reserved_bw, variant(0xaaaaaaaaaaaaaa00aaaaaaaaaaaaaaaa));
    try std.testing.expectEqual(Variant.reserved_bw, variant(0xaaaaaaaaaaaaaa20aaaaaaaaaaaaaaaa));
    try std.testing.expectEqual(Variant.reserved_bw, variant(0xaaaaaaaaaaaaaa40aaaaaaaaaaaaaaaa));
    try std.testing.expectEqual(Variant.reserved_bw, variant(0xaaaaaaaaaaaaaa60aaaaaaaaaaaaaaaa));

    try std.testing.expectEqual(Variant.rfc4122, variant(0xaaaaaaaaaaaaaa80aaaaaaaaaaaaaaaa));
    try std.testing.expectEqual(Variant.rfc4122, variant(0xaaaaaaaaaaaaaaA0aaaaaaaaaaaaaaaa));

    try std.testing.expectEqual(Variant.reserved_ms, variant(0xaaaaaaaaaaaaaaC0aaaaaaaaaaaaaaaa));

    try std.testing.expectEqual(Variant.reserved_fu, variant(0xaaaaaaaaaaaaaaE0aaaaaaaaaaaaaaaa));
}

test "get version" {
    try std.testing.expectEqual(Version.time_based, version(0xaaaaaaaaaaaaaaaa0010aaaaaaaaaaaa));
    try std.testing.expectEqual(Version.dce_security, version(0xaaaaaaaaaaaaaaaa0020aaaaaaaaaaaa));
    try std.testing.expectEqual(Version.name_based_md5, version(0xaaaaaaaaaaaaaaaa0030aaaaaaaaaaaa));
    try std.testing.expectEqual(Version.random, version(0xaaaaaaaaaaaaaaaa0040aaaaaaaaaaaa));
    try std.testing.expectEqual(Version.name_based_sha1, version(0xaaaaaaaaaaaaaaaa0050aaaaaaaaaaaa));
    try std.testing.expectEqual(Version.time_based_greg, version(0xaaaaaaaaaaaaaaaa0060aaaaaaaaaaaa));
    try std.testing.expectEqual(Version.time_based_epoch, version(0xaaaaaaaaaaaaaaaa0070aaaaaaaaaaaa));
    try std.testing.expectEqual(Version.custom, version(0xaaaaaaaaaaaaaaaa0080aaaaaaaaaaaa));
    try std.testing.expectEqual(Version.ndef, version(0xaaaaaaaaaaaaaaaa0090aaaaaaaaaaaa));
}
