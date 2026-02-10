// Code from: https://github.com/freakmangd/zentig_ecs/blob/main/src/etc/byte_array.zig#L65

const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const core = @import("../root.zig");
const Self = @This();

buffer: []u8,
entry_size: usize,
index: usize = 0,

pub fn next(self: *Self) ?*anyopaque {
    std.debug.assert(self.entry_size > 0);

    if (self.index >= self.buffer.len / self.entry_size) return null;
    self.index += 1;
    return self.buffer.ptr + (self.index - 1) * self.entry_size;
}

pub fn nextAs(self: *Self, comptime T: type) ?*T {
    const n = self.next() orelse return null;
    return core.ptrCast(T, n);
}
