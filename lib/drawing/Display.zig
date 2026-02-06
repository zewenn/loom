const lm = @import("../root.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;

const drawing = @import("drawing.zig");
const Picture = drawing.Picture;

sort: fn (void, Picture, Picture) bool,

