const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const List = @import("List.zig").List;
const iterator_functions = @import("iterator_functions.zig");

const coerceTo = @import("type_switcher.zig").coerceTo;

pub fn cloneArrayListToOwnedSlice(comptime T: type, allocator: std.mem.Allocator, list: std.ArrayList(T)) ![]T {
    var cloned = try list.clone(allocator);
    return try cloned.toOwnedSlice(allocator);
}

pub fn Array(comptime T: type) type {
    return struct {
        const Self = @This();
        const Error = error{
            IncorrectElementType,
            TypeChangeFailiure,
        };

        alloc: Allocator = std.heap.page_allocator,
        slice: []T,

        pub fn init(allocator: std.mem.Allocator, initial_items: []const T) !Self {
            const allocated = try allocator.alloc(T, initial_items.len);
            std.mem.copyForwards(T, allocated, initial_items);

            return Self{
                .alloc = allocator,
                .slice = allocated,
            };
        }

        pub fn fromArrayList(allocator: Allocator, arr: std.ArrayList(T)) !Self {
            return Self{
                .slice = try cloneArrayListToOwnedSlice(T, allocator, arr),
                .alloc = allocator,
            };
        }

        pub fn fromList(list: List(T)) !Self {
            return try Self.fromArrayList(list.allocator, list.arrlist);
        }

        pub fn deinit(self: *Self) void {
            self.alloc.free(self.slice);
            self.* = undefined;
        }

        pub inline fn items(self: Self) []T {
            return self.slice;
        }

        pub inline fn len(self: Self) usize {
            return self.slice.len;
        }

        fn getSafeIndex(self: Self, index: anytype) ?usize {
            var _index = coerceTo(isize, index) orelse return null;

            if (_index < 0) _index = @as(isize, @intCast(self.len())) + _index;

            if (self.len() == 0 or _index > self.len() - 1 or _index < 0)
                return null;

            return @intCast(@max(0, _index));
        }

        pub inline fn at(self: Self, index: anytype) ?T {
            return self.slice[self.getSafeIndex(index) orelse return null];
        }

        pub fn clone(self: Self) !Self {
            const new = try self.alloc.alloc(T, self.slice.len);
            std.mem.copyForwards(T, new, self.slice);

            return Self{
                .slice = new,
                .alloc = self.alloc,
            };
        }

        pub fn eql(self: Self, other: Self) bool {
            if (self.len() != other.len()) return false;

            for (0..self.len()) |index| {
                if (!std.meta.eql(self.at(index), other.at(index)))
                    return false;
            }

            return true;
        }

        pub fn set(self: *Self, index: anytype, value: T) void {
            self.slice[self.getSafeIndex(index) orelse return] = value;
        }

        pub inline fn getFirst(self: Self) T {
            return self.slice[0];
        }

        pub inline fn getLast(self: Self) T {
            return self.slice[self.len() - 1];
        }

        pub inline fn getFirstOrNull(self: Self) ?T {
            return self.at(0);
        }

        pub inline fn getLastOrNull(self: Self) ?T {
            return self.at(-1);
        }

        pub fn clearAndFree(self: *Self) void {
            self.alloc.free(self.slice);
            self.slice.len = 0;
        }

        /// Caller owns the returned memory. Does empty the array. Makes `deinit` safe, but unnecessary to call.
        pub fn toOwnedSlice(self: *Self) ![]T {
            const new_slice = try self.alloc.alloc(T, self.len());
            @memcpy(new_slice, self.slice);
            self.clearAndFree();

            return new_slice;
        }

        pub fn cloneToOwnedSlice(self: Self) ![]T {
            const new_slice = try self.alloc.alloc(T, self.len());
            @memcpy(new_slice, self.slice);

            return new_slice;
        }

        pub fn cloneToArrayList(self: Self) !std.ArrayList(T) {
            const cloned_items = try self.cloneToOwnedSlice();

            var list = try std.ArrayList(T).initCapacity(self.alloc, self.len());
            try list.appendSlice(self.alloc, cloned_items);

            return list;
        }

        pub inline fn cloneToList(self: Self) !List(T) {
            const cloned_items = try self.cloneToOwnedSlice();

            return List(T).initWithItems(self.alloc, cloned_items);
        }

        pub inline fn map(self: Self, R: type, mapping_function: iterator_functions.MappingFn(T, R)) !Array(R) {
            return Array(R){
                .alloc = self.alloc,
                .slice = try iterator_functions.map(
                    T,
                    R,
                    self.alloc,
                    self.items(),
                    mapping_function,
                ),
            };
        }

        pub inline fn reduce(self: Self, R: type, initial: R, reduce_function: iterator_functions.ReduceFn(T, R)) R {
            return iterator_functions.reduce(T, R, self.items(), initial, reduce_function);
        }

        pub inline fn filter(self: Self, criteria: iterator_functions.FilterCriteriaFn(T)) !Self {
            return Self{
                .alloc = self.alloc,
                .slice = try iterator_functions.filter(
                    T,
                    self.alloc,
                    self.items(),
                    criteria,
                ),
            };
        }

        pub inline fn forEach(self: Self, foreach_function: iterator_functions.ForEachFn(T)) !void {
            try iterator_functions.forEach(T, self.items(), foreach_function);
        }
    };
}

pub fn array(comptime T: type, items: []const T) Array(T) {
    return Array(T).init(std.heap.smp_allocator, items) catch unreachable;
}

pub fn arrayAdvanced(
    comptime T: type,
    allocator: Allocator,
    tuple: []const T,
) Array(T) {
    return Array(T).init(
        allocator,
        tuple,
    ) catch unreachable;
}
