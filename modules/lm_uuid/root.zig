pub const core = @import("core.zig");
pub const urn = @import("urn.zig");
pub const v4 = @import("v4.zig");
pub const v5 = @import("v5.zig");
pub const v7 = @import("v7.zig");

pub const Uuid = core.Uuid;
pub const Variant = core.Variant;
pub const Version = core.Version;
pub const Urn = urn.Urn;
pub const UrnZ = urn.UrnZ;

test {
    _ = core;
    _ = urn;
    _ = v4;
    _ = v5;
    _ = v7;
}
