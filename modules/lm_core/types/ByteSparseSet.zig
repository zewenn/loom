const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

const core = @import("../root.zig");
const ByteList = core.types.ByteList;
const PagedList = core.types.PagedList;
const List = core.types.List;

const te = core.type_erasure;

const Self = @This();

entry_id: u64,
entry_size: usize,

dense: ByteList,
backlink: List(usize),
sparse: PagedList(usize, 1024),

allocator: Allocator,

pub fn init(allocator: Allocator, comptime T: type) Self {
    return Self{
        .allocator = allocator,
        .entry_id = comptime te.typeToHash(T),
        .entry_size = te.alignedSize(T),
        .dense = .init(allocator, T),
        .backlink = .init(allocator),
        .sparse = .init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.dense.deinit();
    self.backlink.deinit();
    self.sparse.deinit();

    self.* = undefined;
}

inline fn assertType(self: *Self, comptime T: type) void {
    core.assert(self.entry_id == comptime te.typeToHash(T), "type hash mismatch");
    core.assert(self.entry_size == te.alignedSize(T), "type size mismatch");
}

pub fn set(self: *Self, at: usize, value: anytype) !void {
    const T = @TypeOf(value);
    self.assertType(T);

    const dense_index = self.dense.len();
    try self.dense.append(value);
    try self.backlink.append(at);
    try self.sparse.set(at, dense_index);
}

pub fn get(self: *Self, at: usize) ?*anyopaque {
    const dense_index = self.sparse.get(at) orelse return null;
    return self.dense.get(dense_index);
}

pub fn getAs(self: *Self, at: usize, comptime T: type) ?*T {
    const dense_index = self.sparse.get(at) orelse return null;
    return self.dense.getAs(T, dense_index);
}

pub fn remove(self: *Self, at: usize) void {
    const index = self.sparse.get(at) orelse return;
    const sparse_index = self.backlink.getLast();

    self.sparse.set(sparse_index, index) catch unreachable;

    _ = self.backlink.swapRemove(index);
    self.dense.swapRemove(index);

    self.sparse.remove(at);
}
