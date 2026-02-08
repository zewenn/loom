const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

const core = @import("lm_core");
const te = core.type_erasure;

const PendingComponent = @import("PendingComponent.zig");
pub const Error = error{
    EntityOutOfRange,
    EntityAlreadyHasComponent,
};

const Self = @This();

component_id: u64,
component_size: usize,

dense: core.List(u8),
entities: core.List(usize),
sparse: core.List(?usize),

allocator: Allocator,

pub fn init(comptime T: type, allocator: Allocator) Self {
    return Self{
        .component_id = comptime te.typeToHash(T),
        .component_size = std.mem.alignForward(usize, @sizeOf(T), @alignOf(T)),

        .dense = .init(allocator),
        .entities = .init(allocator),
        .sparse = .init(allocator),

        .allocator = allocator,
    };
}

pub fn fromPending(allocator: Allocator, pending: PendingComponent) !Self {
    var self = Self{
        .component_id = pending.id,
        .component_size = pending.size,

        .dense = .init(allocator),
        .entities = .init(allocator),
        .sparse = .init(allocator),

        .allocator = allocator,
    };

    try self.storePending(pending);
    return self;
}

pub fn deinit(self: *Self) void {
    self.dense.deinit();
    self.entities.deinit();
    self.sparse.deinit();

    self.* = undefined;
}

inline fn assert(self: *Self, comptime T: type) void {
    if (builtin.mode == .ReleaseFast or builtin.mode == .ReleaseSmall) return;

    const size: comptime_int = @sizeOf(T);
    const id = comptime te.typeToHash(T);

    core.assertFmt(size == self.component_size, "size mismatch T@{any} (expected: {d}, found: {d})", .{ T, self.component_size, size });
    core.assertFmt(id == self.component_id, "id mismatch T@{any} (expected: {d}, found: {d})", .{ T, self.component_id, id });
}

fn expandSparse(self: *Self, to: usize) !void {
    if (to == std.math.maxInt(usize)) return Error.EntityOutOfRange;

    while (self.sparse.len() <= to) {
        try self.sparse.append(null);
    }
}

fn addBytesToDense(self: *Self, bytes: []const u8) !void {
    try self.dense.appendSlice(bytes);
    const padding = self.component_size - bytes.len;
    if (padding > 0) try self.dense.appendNTimes(0, padding);
}

pub fn store(self: *Self, entity: usize, component: anytype) !void {
    const T: type = @TypeOf(component);
    self.assert(T);

    try self.expandSparse(entity);
    if (self.sparse.items()[entity] != null) return Error.EntityAlreadyHasComponent;

    const obj_bytes: []const u8 = std.mem.asBytes(&component);
    const index = self.dense.len() / self.component_size;

    try self.addBytesToDense(obj_bytes);

    try self.entities.append(entity);
    self.sparse.items()[entity] = index;
}

pub fn storePending(self: *Self, pending: PendingComponent) !void {
    if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
        core.assert(self.component_size == pending.size, "byte component size mismatch");
        core.assert(self.component_id == pending.id, "byte component hash mismatch");
    }

    try self.expandSparse(pending.entity);
    if (self.sparse.items()[pending.entity] != null) return Error.EntityAlreadyHasComponent;

    const index = self.dense.len() / self.component_size;

    try self.addBytesToDense(pending.bytes);
    try self.entities.append(pending.entity);
    self.sparse.items()[pending.entity] = index;
}

pub fn get(self: *Self, comptime T: type, entity: usize) ?*T {
    self.assert(T);

    if (entity >= self.sparse.len()) return null;

    const start = (self.sparse.items()[entity] orelse return null) * self.component_size;
    const end = start + self.component_size;

    if (self.dense.len() <= start or end > self.dense.len()) return null;

    return te.u8ArrayToStructPtr(T, self.dense.items()[start..end]) catch |err| {
        std.log.err("{any}", .{err});
        return null;
    };
}

pub fn getConst(self: *Self, comptime T: type, entity: usize) ?*const T {
    const component = self.get(T, entity) orelse return null;
    return @ptrCast(@alignCast(component));
}

pub fn remove(self: *Self, entity: usize) !void {
    if (entity >= self.sparse.len()) return;
    if (self.dense.len() == 0) return;

    const last_dense_index = (self.dense.len() / self.component_size) - 1;
    const dead_dense_index = self.sparse.items()[entity] orelse return;

    if (dead_dense_index != last_dense_index) {
        const last_entity = self.entities.items()[last_dense_index];

        const dead_dense_start = dead_dense_index * self.component_size;
        const dead_dense_end = dead_dense_start + self.component_size;

        const last_dense_start = last_dense_index * self.component_size;
        const last_dense_end = last_dense_start + self.component_size;

        @memcpy(
            self.dense.items()[dead_dense_start..dead_dense_end],
            self.dense.items()[last_dense_start..last_dense_end],
        );

        self.sparse.items()[last_entity] = dead_dense_index;
        self.entities.items()[dead_dense_index] = last_entity;
    }

    self.dense.arrlist.shrinkRetainingCapacity(self.dense.len() - self.component_size);
    _ = self.entities.pop();
    self.sparse.items()[entity] = null;
}
