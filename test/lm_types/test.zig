const std = @import("std");
const lm_types = @import("lm_types");

test {
    std.testing.refAllDecls(lm_types);

    _ = @import("types/types.zig");
    _ = @import("type_erasure.zig");
}
