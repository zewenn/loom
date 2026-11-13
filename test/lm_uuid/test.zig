const std = @import("std");
const lm_uuid = @import("lm_uuid");

test "reference all lm_uuid declarations" {
    std.testing.refAllDecls(lm_uuid);
}

test "v4 generates valid RFC 4122 random UUIDs" {
    const random_io_source: std.Random.IoSource = .{ .io = std.testing.io };
    const first_uuid = lm_uuid.v4.fromIo(std.testing.io);
    const second_uuid = lm_uuid.v4.fromRandom(random_io_source.interface());
    const third_uuid = lm_uuid.v4.new();

    try std.testing.expectEqual(lm_uuid.Version.random, lm_uuid.core.version(first_uuid));
    try std.testing.expectEqual(lm_uuid.Variant.rfc4122, lm_uuid.core.variant(first_uuid));
    try std.testing.expectEqual(lm_uuid.Version.random, lm_uuid.core.version(second_uuid));
    try std.testing.expectEqual(lm_uuid.Variant.rfc4122, lm_uuid.core.variant(second_uuid));
    try std.testing.expectEqual(lm_uuid.Version.random, lm_uuid.core.version(third_uuid));
    try std.testing.expectEqual(lm_uuid.Variant.rfc4122, lm_uuid.core.variant(third_uuid));
    try std.testing.expect(first_uuid != second_uuid);
}

test "v5 generates deterministic RFC 9562 SHA-1 UUIDs" {
    const dns_namespace = try lm_uuid.urn.deserialize("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    const generated_uuid = lm_uuid.v5.new(dns_namespace, "www.example.com");
    const serialized_urn = lm_uuid.urn.serialize(generated_uuid);

    try std.testing.expectEqual(lm_uuid.Version.name_based_sha1, lm_uuid.core.version(generated_uuid));
    try std.testing.expectEqual(lm_uuid.Variant.rfc4122, lm_uuid.core.variant(generated_uuid));
    try std.testing.expectEqualStrings("2ed6657d-e927-568b-95e1-2665a8aea6a2", &serialized_urn);
}

test "v7 generates valid epoch-time UUIDs" {
    const random_io_source: std.Random.IoSource = .{ .io = std.testing.io };
    const fixed_timestamp_ms: u64 = 0x123456789abc;
    const deterministic_uuid = lm_uuid.v7.fromRandom(random_io_source.interface(), fixed_timestamp_ms);
    const io_uuid = lm_uuid.v7.fromIo(std.testing.io);
    const default_uuid = lm_uuid.v7.new();

    try std.testing.expectEqual(lm_uuid.Version.time_based_epoch, lm_uuid.core.version(deterministic_uuid));
    try std.testing.expectEqual(lm_uuid.Variant.rfc4122, lm_uuid.core.variant(deterministic_uuid));
    try std.testing.expectEqual(@as(u32, 0x12345678), lm_uuid.core.getTimeLow(deterministic_uuid));
    try std.testing.expectEqual(@as(u16, 0x9abc), lm_uuid.core.getTimeMid(deterministic_uuid));

    try std.testing.expectEqual(lm_uuid.Version.time_based_epoch, lm_uuid.core.version(io_uuid));
    try std.testing.expectEqual(lm_uuid.Variant.rfc4122, lm_uuid.core.variant(io_uuid));
    try std.testing.expectEqual(lm_uuid.Version.time_based_epoch, lm_uuid.core.version(default_uuid));
    try std.testing.expectEqual(lm_uuid.Variant.rfc4122, lm_uuid.core.variant(default_uuid));
}

test "urn round-trip serialization and deserialization" {
    const sample_urn = "6ba7b811-9dad-11d1-80b4-00c04fd430c8";
    const parsed_uuid = try lm_uuid.urn.deserialize(sample_urn);
    const serialized_urn = lm_uuid.urn.serialize(parsed_uuid);
    const serialized_urn_z = lm_uuid.urn.serializeZ(parsed_uuid);

    try std.testing.expectEqualStrings(sample_urn, &serialized_urn);
    try std.testing.expectEqualSentinel(u8, 0, sample_urn, &serialized_urn_z);
    try std.testing.expectEqual(parsed_uuid, try lm_uuid.urn.deserialize(&serialized_urn));
}
