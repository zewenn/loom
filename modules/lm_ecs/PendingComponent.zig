const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");
const te = core.type_erasure;
const Self = @This();

id: u64,
entity: usize,
size: usize,
allocator: Allocator,
bytes: []u8,

pub fn init(allocator: Allocator, entity: usize, data: anytype) !Self {
    const T = @TypeOf(data);

    return Self{
        .id = comptime te.typeToHash(T),
        .entity = entity,
        .size = std.mem.alignForward(usize, @sizeOf(T), @alignOf(T)),
        .allocator = allocator,
        .bytes = try te.structToU8Array(allocator, data),
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.bytes);
    self.* = undefined;
}
