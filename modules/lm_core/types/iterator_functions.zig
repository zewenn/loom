const std = @import("std");
const Allocator = @import("std").mem.Allocator;

pub inline fn MappingFn(T: type, R: type) type {
    return fn (T) ?R;
}

pub inline fn ReduceFn(T: type, R: type) type {
    return fn (accumulator: R, current: T) R;
}

pub inline fn FilterCriteriaFn(T: type) type {
    return fn (item: T) bool;
}

pub inline fn ForEachFn(T: type) type {
    return fn (item: T) anyerror!void;
}

pub fn map(T: type, R: type, allocator: Allocator, array: []T, mapping_function: MappingFn(T, R)) ![]R {
    var list: std.ArrayList(R) = .empty;

    for (array) |item| {
        if (mapping_function(item)) |mapped| try list.append(allocator, mapped);
    }

    return list.toOwnedSlice(allocator);
}

pub fn reduce(T: type, R: type, array: []T, initial: R, reduce_function: ReduceFn(T, R)) R {
    var accumulator: R = initial;
    for (array) |item| {
        accumulator = reduce_function(accumulator, item);
    }

    return accumulator;
}

pub fn filter(T: type, allocator: Allocator, array: []T, criteria: FilterCriteriaFn(T)) ![]T {
    var list: std.ArrayList(T) = .empty;

    for (array) |item| {
        if (criteria(item)) try list.append(allocator, item);
    }

    return try list.toOwnedSlice(allocator);
}

pub inline fn forEach(T: type, array: []T, foreach_function: ForEachFn(T)) !void {
    for (array) |item| {
        try foreach_function(item);
    }
}
