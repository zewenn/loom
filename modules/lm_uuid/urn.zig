const std = @import("std");
const core = @import("core.zig");

const Uuid = core.Uuid;

/// Standard 36-character UUID string representation.
pub const Urn = [36]u8;

/// Null-terminated 36-character UUID string representation.
pub const UrnZ = [36:0]u8;

/// Serialize the given UUID into a URN.
///
/// Each field is separated by a `-` and printed as a zero-filled
/// hexadecimal digit string with the most significant digit first.
pub fn serialize(uuid: Uuid) Urn {
    var urn: Urn = undefined;
    _ = std.fmt.bufPrint(&urn, "{x:0>8}-{x:0>4}-{x:0>4}-{x:0>2}{x:0>2}-{x:0>12}", .{
        core.getTimeLow(uuid),
        core.getTimeMid(uuid),
        core.getTimeHiAndVersion(uuid),
        core.getClockSeqHiAndReserved(uuid),
        core.getClockSeqLow(uuid),
        core.getNode(uuid),
    }) catch unreachable;
    return urn;
}

/// Serialize the given UUID into a null-terminated URN.
///
/// Each field is separated by a `-` and printed as a zero-filled
/// hexadecimal digit string with the most significant digit first.
pub fn serializeZ(uuid: Uuid) UrnZ {
    const serialized_urn = serialize(uuid);
    var buffer: [37]u8 = undefined;
    @memcpy(buffer[0..36], &serialized_urn);
    buffer[36] = 0;
    return buffer[0..36 :0].*;
}

fn parseHexDigit(hex_char: u8) !u8 {
    return switch (hex_char) {
        '0'...'9' => hex_char - '0',
        'A'...'F' => hex_char - 'A' + 10,
        'a'...'f' => hex_char - 'a' + 10,
        else => return error.InvalidHexChar,
    };
}

/// Deserialize the given URN into a UUID.
///
/// If the given URN is malformed, an error is returned.
pub fn deserialize(urn_string: []const u8) !Uuid {
    if (urn_string.len != 36) return error.MalformedUrn;
    if (std.mem.count(u8, urn_string, "-") != 4) return error.MalformedUrn;
    if (urn_string[8] != '-' or urn_string[13] != '-' or urn_string[18] != '-' or urn_string[23] != '-') {
        return error.MalformedUrn;
    }

    var uuid: Uuid = 0;
    var char_index: usize = 0;
    var byte_index: u7 = 0;
    while (char_index <= 34) {
        if (urn_string[char_index] == '-') {
            char_index += 1;
            continue;
        }

        const high_nibble = try parseHexDigit(urn_string[char_index]);
        const low_nibble = try parseHexDigit(urn_string[char_index + 1]);
        const byte_value: u8 = (high_nibble << 4) | low_nibble;
        uuid |= @as(Uuid, @intCast(byte_value)) << (byte_index * 8);
        char_index += 2;
        byte_index += 1;
    }

    return uuid;
}

test "serialize uuid to urn" {
    const sample_uuid: Uuid = 0xffeeddccbbaa99887766554433221100;
    const actual_urn = serialize(sample_uuid);
    try std.testing.expectEqualSlices(u8, "00112233-4455-6677-8899-aabbccddeeff", actual_urn[0..]);
}

test "serialize uuid to null-terminated urn" {
    const sample_uuid: Uuid = 0xffeeddccbbaa99887766554433221100;
    const actual_urn_z = serializeZ(sample_uuid);
    try std.testing.expectEqualSentinel(u8, 0, "00112233-4455-6677-8899-aabbccddeeff", actual_urn_z[0..]);
}

test "deserialize urn to uuid" {
    const sample_urn = "6ba7b811-9dad-11d1-80b4-00c04fd430c8";
    const parsed_uuid = try deserialize(sample_urn);
    try std.testing.expectEqual(@as(Uuid, @intCast(0xc830d44fc000b480d111ad9d11b8a76b)), parsed_uuid);
}

test "urn round-trip serialization" {
    const sample_urn = "6ba7b811-9dad-11d1-80b4-00c04fd430c8";
    const parsed_uuid = try deserialize(sample_urn);
    const round_trip_urn = serialize(parsed_uuid);

    try std.testing.expectEqualStrings(sample_urn, &round_trip_urn);
}
