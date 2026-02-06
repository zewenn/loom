const std = @import("std");
const lm = @import("root.zig");

fn mergeInternal(comptime T: type, arr: lm.Array(T), left: usize, mid: usize, right: usize, order_fn: *const fn (lhs: T, rhs: T) bool) !void {
    const n1 = mid - left + 1;
    const n2 = right - mid;

    var L: lm.Array(T) = try .initWithSize(arr.alloc, n1);
    defer L.deinit();

    var R: lm.Array(T) = try .initWithSize(arr.alloc, n2);
    defer R.deinit();

    for (0..n1) |i|
        L.set(i, arr.items()[left + i]);

    for (0..n2) |j|
        R.set(j, arr.items()[mid + 1 + j]);

    var i: usize = 0;
    var j: usize = 0;

    var k: usize = left;
    while (i < n1 and j < n2) : (k += 1) {
        if (order_fn(L.items()[i], R.items()[j])) {
            arr.items()[k] = L.items()[i];
            i += 1;
            continue;
        }

        arr.items()[k] = R.items()[j];
        j += 1;
    }

    while (i < n1) {
        arr.items()[k] = L.items()[i];
        i += 1;
        k += 1;
    }

    while (j < n2) {
        arr.items()[k] = R.items()[j];
        j += 1;
        k += 1;
    }
}

pub fn merge(comptime T: type, arr: lm.Array(T), left: usize, right: usize, order_fn: *const fn (lhs: T, rhs: T) bool) !void {
    if (left >= right) return;

    const mid = left + @divFloor((right - left), 2);

    try merge(T, arr, left, mid, order_fn);
    try merge(T, arr, mid + 1, right, order_fn);

    try mergeInternal(T, arr, left, mid, right, order_fn);
}
