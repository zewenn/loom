const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");
const ecs = @import("root.zig");

const System = ecs.System;

longest_hash: usize,
systems: core.List(System),

