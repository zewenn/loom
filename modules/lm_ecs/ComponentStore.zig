const std = @import("std");
const core = @import("lm_core");
const te = core.type_erasure;

const Allocator = std.mem.Allocator;
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

pub fn deinit(self: *Self) void {
    self.dense.deinit();
    self.entities.deinit();
    self.sparse.deinit();

    self.* = undefined;
}

fn assert(self: *Self, comptime T: type) void {
    const size: comptime_int = @sizeOf(T);
    const id = comptime te.typeToHash(T);

    core.assertFmt(size == self.component_size, "size mismatch T@{any} (expected: {d}, found: {d})", .{ T, self.component_size, size });
    core.assertFmt(id == self.component_id, "id mismatch T@{any} (expected: {d}, found: {d})", .{ T, self.component_id, id });
}

pub fn store(self: *Self, entity: usize, component: anytype) !void {
    const T: type = @TypeOf(component);
    self.assert(T);

    if (entity == std.math.maxInt(usize)) return Error.EntityOutOfRange;

    while (self.sparse.len() <= entity) {
        try self.sparse.append(null);
    }

    if (self.sparse.items()[entity] != null) return Error.EntityAlreadyHasComponent;

    const obj_bytes: []const u8 = std.mem.asBytes(&component);

    const index = self.dense.len() / self.component_size;

    try self.dense.appendSlice(obj_bytes);
    try self.entities.append(entity);
    self.sparse.items()[entity] = index;
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
