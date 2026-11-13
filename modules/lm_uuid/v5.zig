const std = @import("std");
const core = @import("core.zig");

const Uuid = core.Uuid;

/// Create a version 5 UUID from the namespace and name.
pub fn new(namespace: Uuid, name: []const u8) Uuid {
    const digest = hash(namespace, name);
    var uuid: Uuid = std.mem.bytesToValue(u128, digest[0..16]);
    uuid &= 0xffffffffffffff3fff0fffffffffffff;
    uuid |= 0x00000000000000800050000000000000;
    return uuid;
}

fn hash(namespace: Uuid, name: []const u8) [std.crypto.hash.Sha1.digest_length]u8 {
    var sha1_hasher = std.crypto.hash.Sha1.init(.{});
    var namespace_copy = namespace;
    sha1_hasher.update(std.mem.asBytes(&namespace_copy));
    sha1_hasher.update(name);
    return sha1_hasher.finalResult();
}

test "A.4 Example of a UUIDv5 Value (rfc9562) - only hash" {
    const urn = @import("urn.zig");

    const dns_namespace = try urn.deserialize("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    const digest = hash(dns_namespace, "www.example.com");

    try std.testing.expectEqualSlices(u8, "\x2e\xd6\x65\x7d\xe9\x27\x46\x8b\x55\xe1\x26\x65\xa8\xae\xa6\xa2\x2d\xee\x3e\x35", &digest);
}

test "A.4 Example of a UUIDv5 Value (rfc9562)" {
    const urn = @import("urn.zig");

    const dns_namespace = try urn.deserialize("6ba7b810-9dad-11d1-80b4-00c04fd430c8");
    const uuid_v5 = new(dns_namespace, "www.example.com");
    const urn_v5 = urn.serialize(uuid_v5);

    try std.testing.expectEqualStrings("2ed6657d-e927-568b-95e1-2665a8aea6a2", &urn_v5);
    try std.testing.expectEqual(core.Version.name_based_sha1, core.version(uuid_v5));
}

test "create a version 5 UUID" {
    const urn = @import("urn.zig");
    const first_namespace = try urn.deserialize("15f62bf5-5f5b-4dc6-96b3-386ee85d0922");
    const second_namespace = try urn.deserialize("70aad581-fc81-4886-92df-f03c9ad340bf");

    const base_uuid = new(first_namespace, "base_uuid");
    try std.testing.expectEqual(core.Version.name_based_sha1, core.version(base_uuid));
    try std.testing.expectEqual(core.Variant.rfc4122, core.variant(base_uuid));

    const different_name_uuid = new(first_namespace, "same_namespace");
    try std.testing.expectEqual(core.Version.name_based_sha1, core.version(different_name_uuid));
    try std.testing.expectEqual(core.Variant.rfc4122, core.variant(different_name_uuid));
    try std.testing.expect(base_uuid != different_name_uuid);

    const different_namespace_uuid = new(second_namespace, "base_uuid");
    try std.testing.expectEqual(core.Version.name_based_sha1, core.version(different_namespace_uuid));
    try std.testing.expectEqual(core.Variant.rfc4122, core.variant(different_namespace_uuid));
    try std.testing.expect(base_uuid != different_namespace_uuid);

    const repeated_uuid = new(first_namespace, "base_uuid");
    try std.testing.expectEqual(base_uuid, repeated_uuid);

    try std.testing.expectEqualStrings(
        "a771e72c-fa33-5ad7-a26d-f63a2aa62fe1",
        &urn.serialize(base_uuid),
    );
    try std.testing.expectEqualStrings(
        "24ade676-fc5c-56bb-a99c-c467801a48b9",
        &urn.serialize(different_name_uuid),
    );
    try std.testing.expectEqualStrings(
        "f2668bee-a4af-5f56-92fd-b371cdcd9cd2",
        &urn.serialize(different_namespace_uuid),
    );
}
