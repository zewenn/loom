const std = @import("std");
const lm_core = @import("lm_core");

test {
    std.testing.refAllDecls(lm_core);

    _ = @import("types/types.zig");
    _ = @import("type_erasure.zig");
}
