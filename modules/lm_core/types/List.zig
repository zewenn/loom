const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const Array = @import("Array.zig").Array;
const coerceTo = @import("type_switcher.zig").coerceTo;

const iterator_functions = @import("iterator_functions.zig");

pub fn List(comptime T: type) type {
    return struct {
        const Self = @This();

        arrlist: std.ArrayList(T),
        allocator: Allocator,

        pub fn init(allocator: Allocator) Self {
            return Self{
                .arrlist = .empty,
                .allocator = allocator,
            };
        }

        pub fn initWithItems(allocator: Allocator, initial_items: []const T) !Self {
            var self = Self{
                .arrlist = .empty,
                .allocator = allocator,
            };

            try self.appendSlice(initial_items);

            return self;
        }

        pub fn fromArray(array: Array(T)) !Self {
            return Self{
                .arrlist = try array.toArrayList(),
                .allocator = array.alloc,
            };
        }

        pub fn fromArrayList(array_list: std.ArrayList(T), allocator: Allocator) Self {
            return Self{
                .arrlist = array_list,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.arrlist.deinit(self.allocator);
            self.* = undefined;
        }

        pub inline fn items(self: Self) []T {
            return self.arrlist.items;
        }

        pub inline fn len(self: Self) usize {
            return self.arrlist.items.len;
        }

        pub inline fn capacity(self: Self) usize {
            return self.arrlist.capacity;
        }

        pub fn at(self: Self, index: anytype) ?T {
            const _index = coerceTo(isize, index) orelse return null;
            if (_index >= self.len() or self.len() == 0) return null;

            const real_index: usize = real_index: {
                if (_index < 0) break :real_index coerceTo(usize, coerceTo(isize, self.len()).? + _index).?;
                break :real_index @intCast(_index);
            };

            return self.items()[real_index];
        }

        /// Extend the list by 1 element. Allocates more memory as necessary.
        /// Invalidates element pointers if additional memory is needed.
        pub fn append(self: *Self, item: T) !void {
            try self.arrlist.append(self.allocator, item);
        }

        /// Append the slice of items to the list. Allocates more
        /// memory as necessary.
        /// Invalidates element pointers if additional memory is needed.
        pub fn appendSlice(self: *Self, new_items: []const T) !void {
            try self.arrlist.appendSlice(self.allocator, new_items);
        }

        /// Invalidates all element pointers.
        pub fn clearAndFree(self: *Self) void {
            self.arrlist.clearAndFree(self.allocator);
        }

        /// Invalidates all element pointers.
        pub fn clearRetainingCapacity(self: *Self) void {
            self.arrlist.clearRetainingCapacity();
        }

        /// Creates a copy of this List.
        pub fn clone(self: *Self) !Self {
            return Self{
                .allocator = self.allocator,
                .arrlist = try self.arrlist.clone(self.allocator),
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

        pub inline fn getLast(self: Self) T {
            return self.arrlist.getLast();
        }

        pub inline fn getLastOrNull(self: Self) ?T {
            return self.arrlist.getLastOrNull();
        }

        pub fn getFirst(self: Self) T {
            return self.items()[0];
        }

        pub fn getFirstOrNull(self: Self) ?T {
            return if (self.len() > 0) self.items()[0] else null;
        }

        /// Remove the element at index `i` from the list and return its value.
        /// Invalidates pointers to the last element.
        /// This operation is O(N).
        /// Asserts that the index is in bounds.
        pub inline fn orderedRemove(self: *Self, index: usize) T {
            return self.arrlist.orderedRemove(index);
        }

        /// Remove the elements indexed by `sorted_indexes`. The indexes to be
        /// removed correspond to the array list before deletion.
        ///
        /// Asserts:
        /// * Each index to be removed is in bounds.
        /// * The indexes to be removed are sorted ascending.
        ///
        /// Duplicates in `sorted_indexes` are allowed.
        ///
        /// This operation is O(N).
        ///
        /// Invalidates element pointers beyond the first deleted index.
        pub inline fn orderedRemoveMany(self: *Self, sorted_indexes: []const usize) void {
            self.arrlist.orderedRemoveMany(sorted_indexes);
        }

        pub inline fn swapRemove(self: *Self, index: usize) T {
            return self.arrlist.swapRemove(index);
        }

        pub inline fn pop(self: *Self) ?T {
            return self.arrlist.pop();
        }

        pub inline fn resize(self: *Self, new_len: usize) !void {
            try self.arrlist.resize(self.allocator, new_len);
        }

        pub inline fn shrinkAndFree(self: *Self, new_len: usize) void {
            self.arrlist.shrinkAndFree(self.allocator, new_len);
        }

        pub inline fn toOwnedSlice(self: *Self) ![]T {
            return try self.arrlist.toOwnedSlice(self.allocator);
        }

        pub fn cloneToOwnedSlice(self: *Self) ![]T {
            var cloned = try self.clone();
            return try cloned.toOwnedSlice();
        }

        pub fn toArray(self: *Self) !Array(T) {
            return try .fromArrayList(self.allocator, self.arrlist);
        }

        pub fn map(self: Self, R: type, mapping_function: iterator_functions.MappingFn(T, R)) !List(R) {
            var new_list: List(R) = .init(self.allocator);
            const new_items = try iterator_functions.map(
                T,
                R,
                self.allocator,
                self.items(),
                mapping_function,
            );
            defer self.allocator.free(new_items);

            try new_list.appendSlice(new_items);

            return new_list;
        }

        pub inline fn reduce(self: Self, R: type, initial: R, reduce_function: iterator_functions.ReduceFn(T, R)) R {
            return iterator_functions.reduce(T, R, self.items(), initial, reduce_function);
        }

        pub fn filter(self: Self, criteria: iterator_functions.FilterCriteriaFn(T)) !List(T) {
            var new_list: List(T) = .init(self.allocator);
            const new_items = try iterator_functions.filter(
                T,
                self.allocator,
                self.items(),
                criteria,
            );
            defer self.allocator.free(new_items);

            try new_list.appendSlice(new_items);

            return new_list;
        }

        pub inline fn forEach(self: Self, foreach_function: iterator_functions.ForEachFn(T)) !void {
            try iterator_functions.forEach(T, self.items(), foreach_function);
        }
    };
}
