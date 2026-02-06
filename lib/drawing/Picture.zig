const lm = @import("../root.zig");
const std = @import("std");

const Self = @This();

transform: lm.Transform = .zero,
tetxure: ?lm.Texture = null,
tint: lm.Color = .white,
fill_color: ?lm.Color = null,

entity: ?*lm.Entity = null,
