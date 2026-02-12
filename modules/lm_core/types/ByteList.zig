// Inspired by: https://github.com/freakmangd/zentig_ecs/blob/main/src/etc/byte_array.zig#L65

const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

const core = @import("../root.zig");

const List = @import("list.zig").List;
const Array = @import("array.zig").Array;
const ByteIterator = @import("ByteIterator.zig");
const te = core.type_erasure;

const Self = @This();

entry_id: u64,
entry_size: usize,

bytes: List(u8),
allocator: Allocator,

pub fn init(allocator: Allocator, comptime T: type) Self {
    return Self{
        .allocator = allocator,
        .entry_id = comptime te.typeToHash(T),
        .entry_size = std.mem.alignForward(usize, @sizeOf(T), @alignOf(T)),
        .bytes = .init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.bytes.deinit();

    self.* = undefined;
}

pub fn initWithItems(comptime T: type, allocator: Allocator, slice: []const T) !Self {
    var self: Self = .init(allocator, T);
    try self.appendSlice(T, slice);

    return self;
}

pub fn fromArray(comptime T: type, array: Array(T)) !Self {
    return .initWithItems(T, array.alloc, array.items());
}

pub fn fromList(comptime T: type, list: List(T)) !Self {
    return .initWithItems(T, list.allocator, list.items());
}

pub inline fn len(self: *Self) usize {
    return self.bytes.len() / self.entry_size;
}

pub inline fn capacity(self: *Self) usize {
    return self.bytes.capacity() / self.entry_size;
}

pub inline fn rawItems(self: *Self) []u8 {
    return self.bytes.items();
}

pub inline fn rawLen(self: *Self) usize {
    return self.bytes.len();
}

pub inline fn rawCapacity(self: *Self) usize {
    return self.bytes.capacity();
}

pub fn append(self: *Self, item: anytype) !void {
    const T = @TypeOf(item);
    core.assert(
        self.entry_size == std.mem.alignForward(usize, @sizeOf(T), @alignOf(T)),
        "Invalid element insertion",
    );

    try self.bytes.appendSlice(std.mem.asBytes(&item));
}

pub fn appendSlice(self: *Self, comptime T: type, slice: []const T) !void {
    core.assertFmt((comptime te.typeToHash(T)) == self.entry_id, "type mismatch {any}", .{T});
    for (slice) |item| {
        try self.append(item);
    }
}

pub fn appendBytes(self: *Self, bytes_start: *const anyopaque) !void {
    try self.bytes.appendSlice(@as([*]const u8, @ptrCast(bytes_start))[0..self.entry_size]);
}

pub fn set(self: *Self, index: usize, bytes_start: *const anyopaque) void {
    @memcpy(
        self.bytes.items()[index * self.entry_size ..][0..self.entry_size],
        @as([*]const u8, @ptrCast(bytes_start))[0..self.entry_size],
    );
}

pub fn get(self: *Self, index: usize) ?*anyopaque {
    if (builtin.mode == .ReleaseSafe or builtin.mode == .Debug)
        if (index >= self.len()) return null;

    return &self.rawItems()[self.entry_size * index];
}

pub fn getAs(self: *Self, comptime T: type, index: usize) ?*T {
    return core.ptrCast(T, self.get(index) orelse return null);
}

pub fn getAsBytes(self: *Self, index: usize) []const u8 {
    return @as([*]const u8, @ptrCast(&self.bytes.items()[index * self.entry_size]))[0..self.entry_size];
}

pub fn slicedAs(self: *Self, comptime T: type) []T {
    core.assert((comptime te.typeToHash(T)) == self.entry_id, "Type mismatch");

    return @as([*]T, @ptrCast(@alignCast(self.bytes.items().ptr)))[0..self.len()];
}

pub fn pop(self: *Self) ?[]const u8 {
    if (self.bytes.len() == 0) return null;

    const out = self.getAsBytes(self.len() - 1);
    self.bytes.shrinkRetainingCapacity((self.len() - 1) * self.entry_size);

    return out;
}

pub fn swapRemove(self: *Self, index: usize) void {
    if (self.entry_size == 0) {
        self.bytes.shrinkRetainingCapacity((self.len() - 1) * self.entry_size);
        return;
    }

    if (self.len() - 1 == index) {
        _ = self.pop();
        return;
    }

    const bytes = self.pop() orelse return;
    self.set(index, bytes.ptr);
}

pub fn iterator(self: *Self) ByteIterator {
    return ByteIterator{
        .buffer = self.bytes.items(),
        .entry_size = self.entry_size,
        .index = 0,
    };
}
