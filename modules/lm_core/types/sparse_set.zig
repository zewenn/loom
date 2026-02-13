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

        pub fn getKeyByValue(self: *Self, value: DENSE_T) ?usize {
            for (self.dense.items(), 0..) |item, index| {
                const eqls = switch (@typeInfo(DENSE_T)) {
                    .int, .comptime_int, .float, .comptime_float, .bool, .@"enum" => item == value,
                    else => std.meta.eql(value, item),
                };

                if (!eqls) continue;

                return self.backlink.items()[index];
            }
            return null;
        }

        pub fn contains(self: *Self, at: usize) bool {
            return self.get(at) != null;
        }

        pub fn containsValue(self: *Self, value: DENSE_T) bool {
            for (self.dense.items()) |item| {
                const eqls = switch (@typeInfo(DENSE_T)) {
                    .int, .comptime_int, .float, .comptime_float, .bool, .@"enum" => item == value,
                    else => std.meta.eql(value, item),
                };

                if (eqls) return true;
            }
            return false;
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
