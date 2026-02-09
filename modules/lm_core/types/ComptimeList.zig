const std = @import("std");
const coerceTo = @import("type_switcher.zig").coerceTo;
const iterator_functions = @import("iterator_functions.zig");

pub fn ComptimeList(comptime T: type) type {
    return struct {
        const Self = @This();
        arr: []const T = &.{},

        pub fn init() Self {
            return Self{
                .arr = &.{},
            };
        }

        pub fn initWithItems(comptime starting_items: []const T) Self {
            return Self{
                .arr = starting_items,
            };
        }

        pub inline fn items(comptime self: Self) []const T {
            return self.arr;
        }

        pub inline fn len(comptime self: Self) comptime_int {
            return self.arr.len;
        }

        pub fn at(comptime self: Self, comptime index: anytype) ?T {
            const _index = comptime coerceTo(isize, index) orelse return null;
            if (_index >= self.len() or self.len() == 0) return null;

            const real_index: usize = real_index: {
                if (_index < 0) break :real_index comptime coerceTo(usize, coerceTo(isize, self.len()).? + _index).?;
                break :real_index @intCast(_index);
            };

            return self.items()[real_index];
        }

        pub fn append(comptime self: *Self, comptime value: T) void {
            self.arr = self.arr ++ .{value};
        }

        pub fn appendSlice(comptime self: *Self, comptime slice: []const T) void {
            self.arr = self.arr ++ slice;
        }

        pub fn appendNTimes(comptime self: *Self, comptime value: T, comptime n: comptime_int) void {
            inline for (0..n) |_| {
                self.append(value);
            }
        }

        pub fn clear(comptime self: *Self) void {
            self.arr = &.{};
        }

        pub fn clone(comptime self: *Self) Self {
            return .initWithItems(self.arr);
        }

        pub inline fn getLast(comptime self: Self) T {
            return self.items()[self.len() - 1];
        }

        pub inline fn getLastOrNull(comptime self: Self) ?T {
            return if (self.len() > 0) self.getLast() else null;
        }

        pub fn getFirst(comptime self: Self) T {
            return self.items()[0];
        }

        pub fn getFirstOrNull(comptime self: Self) ?T {
            return if (self.len() > 0) self.items()[0] else null;
        }

        pub fn orderedRemove(comptime self: *Self, comptime index: comptime_int) T {
            const item = self.arr[index];

            if (index == 0) {
                self.arr = self.arr[1..];
                return item;
            }

            if (index == self.len() - 1) {
                self.arr = self.arr[0 .. self.len() - 1];
                return item;
            }

            const first_slice = self.arr[0..index];
            const second_slice = self.arr[index + 1 ..];

            self.arr = first_slice ++ second_slice;
            return item;
        }

        pub fn swapRemove(comptime self: *Self, comptime index: comptime_int) ?T {
            const last = self.getLast();
            const item = self.items()[index];

            if (index == 0) {
                self.arr = .{last} ++ self.arr[1 .. self.len() - 1];
                return item;
            }

            if (index == self.len() - 1) {
                self.arr = self.arr[0 .. self.len() - 1];
                return item;
            }

            const first_slice = self.arr[0..index];
            const second_slice = self.arr[index + 1 .. self.len() - 1];
            self.arr = first_slice ++ &.{last} ++ second_slice;

            return item;
        }

        pub fn pop(comptime self: *Self) ?T {
            if (self.len() == 0) return null;

            const last = self.getLast();
            self.arr = self.arr[0 .. self.len() - 1];
            return last;
        }

        pub fn resize(comptime self: *Self, comptime new_len: comptime_int) void {
            if (self.len() == new_len) return;
            if (self.len() > new_len) {
                self.arr = self.arr[0..new_len];
                return;
            }

            const diff = new_len - self.len();
            self.arr = self.arr ++ (.{undefined} ** diff);
        }

        pub inline fn shrink(comptime self: *Self, comptime new_len: comptime_int) void {
            self.resize(new_len);
        }

        pub fn map(comptime self: *Self, comptime R: type, comptime mapping_fn: iterator_functions.ComptimeMappingFn(T, R)) ComptimeList(R) {
            var new_list = ComptimeList(R).init();
            inline for (self.items()) |item| {
                if (mapping_fn(item)) |i| new_list.append(i);
            }

            return new_list;
        }

        pub fn reduce(comptime self: *Self, comptime R: type, comptime initial: R, comptime reduce_fn: iterator_functions.ComptimeReduceFn(T, R)) R {
            var result: R = initial;
            inline for (self.items()) |item| {
                result = reduce_fn(result, item);
            }
            return result;
        }

        pub fn filter(comptime self: *Self, comptime criteria: iterator_functions.ComptimeFilterCriteriaFn(T)) ComptimeList(T) {
            var new_list = ComptimeList(T).init();
            inline for (self.items()) |item| {
                if (criteria(item)) new_list.append(item);
            }
            return new_list;
        }

        pub fn forEach(comptime self: *Self, comptime foreach_fn: iterator_functions.ComptimeForEachFn(T)) void {
            inline for (self.items()) |item| {
                foreach_fn(item);
            }
        }
    };
}
