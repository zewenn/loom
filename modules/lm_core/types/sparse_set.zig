const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

const core = @import("../root.zig");
const ByteList = core.types.ByteList;
const PagedList = core.types.PagedList;
const List = core.types.List;

const te = core.type_erasure;

pub fn SparseSet(comptime DENSE_T: type) type {
    return struct {
        const Self = @This();

        dense: List(DENSE_T),
        backlink: List(usize),
        sparse: PagedList(usize, 1024),

        allocator: Allocator,

        pub fn init(allocator: Allocator) Self {
            return Self{
                .allocator = allocator,
                .dense = .init(allocator),
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

        pub fn len(self: *Self) usize {
            return self.backlink.len();
        }

        pub fn set(self: *Self, at: usize, value: DENSE_T) !void {
            const dense_index = self.dense.len();
            try self.dense.append(value);
            try self.backlink.append(at);
            try self.sparse.set(at, dense_index);
        }

        pub fn get(self: *Self, at: usize) ?DENSE_T {
            const dense_index = self.sparse.get(at) orelse return null;
            return self.dense.at(dense_index);
        }

        pub fn getPtr(self: *Self, at: usize) ?*DENSE_T {
            const dense_index = self.sparse.get(at) orelse return null;
            if (self.dense.len() <= dense_index) return null;

            return &self.dense.items()[dense_index];
        }

        pub fn remove(self: *Self, at: usize) void {
            const index = self.sparse.get(at) orelse return;
            const sparse_index = self.backlink.getLast();

            self.sparse.set(sparse_index, index) catch unreachable;

            _ = self.backlink.swapRemove(index);
            _ = self.dense.swapRemove(index);

            self.sparse.remove(at);
        }
    };
}
