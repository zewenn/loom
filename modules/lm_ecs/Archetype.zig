const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");
const ecs = @import("root.zig");

const Self = @This();

/// The bitmask that uniquely identifies this archetype's component composition.
mask: u128,

/// Ordered component type hashes, parallel to `columns`. Owned by this archetype.
component_hashes: []u64,

/// Dense list of entities currently in this archetype, parallel to each column's rows.
entities: core.List(ecs.Entity),

/// One `ByteList` per component type, in the same order as `component_hashes`.
/// `columns[i][row]` is the component data for `entities[row]` of type `component_hashes[i]`.
columns: core.List(core.ByteList),

/// Sparse map: entity ID -> row index within this archetype's columns.
/// Uses a `PagedList` so it stays memory-efficient for sparse entity ID ranges.
entity_to_row: core.types.PagedList(usize, 1024),

allocator: Allocator,

/// `component_hashes` and `component_sizes` must be the same length and in the same order.
pub fn init(
    allocator: Allocator,
    mask: u128,
    component_hashes: []const u64,
    component_sizes: []const usize,
) !Self {
    std.debug.assert(component_hashes.len == component_sizes.len);

    const owned_hashes = try allocator.dupe(u64, component_hashes);
    errdefer allocator.free(owned_hashes);

    var columns: core.List(core.ByteList) = .init(allocator);
    errdefer {
        for (columns.items()) |*col| col.deinit();
        columns.deinit();
    }

    for (component_hashes, component_sizes) |hash, size| {
        try columns.append(core.ByteList.initWithInfo(allocator, hash, size));
    }

    return Self{
        .mask = mask,
        .component_hashes = owned_hashes,
        .entities = .init(allocator),
        .columns = columns,
        .entity_to_row = .init(allocator),
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    for (self.columns.items()) |*col| col.deinit();
    self.columns.deinit();

    self.entities.deinit();
    self.entity_to_row.deinit();
    self.allocator.free(self.component_hashes);

    self.* = undefined;
}

/// Number of entities currently stored in this archetype.
pub inline fn len(self: *const Self) usize {
    return self.entities.len();
}

pub inline fn isEmpty(self: *const Self) bool {
    return self.entities.len() == 0;
}

/// Returns true if this archetype satisfies all bits in `query_mask`.
pub inline fn matchesMask(self: *const Self, query_mask: u128) bool {
    return (self.mask & query_mask) == query_mask;
}

/// Returns true if this archetype's mask exactly equals the given mask.
pub inline fn exactMask(self: *const Self, other_mask: u128) bool {
    return self.mask == other_mask;
}

/// Returns the column index for `hash`, or null if this archetype doesn't hold that type.
pub fn columnIndex(self: *const Self, hash: u64) ?usize {
    for (self.component_hashes, 0..) |h, i| {
        if (h == hash) return i;
    }
    return null;
}

pub inline fn hasComponent(self: *const Self, hash: u64) bool {
    return self.columnIndex(hash) != null;
}

/// Returns the row index of `entity` within this archetype, or null if it isn't here.
pub inline fn entityRow(self: *Self, entity: ecs.Entity) ?usize {
    return self.entity_to_row.get(entity);
}

pub inline fn containsEntity(self: *Self, entity: ecs.Entity) bool {
    return self.entity_to_row.get(entity) != null;
}

/// Raw pointer to the start of a column's byte buffer by index.
/// Cast to `[*]T` with a known count (from `len()`) in the system wrapper.
pub fn columnPtr(self: *Self, col_index: usize) ?[*]u8 {
    if (col_index >= self.columns.len()) return null;
    const col = &self.columns.items()[col_index];
    if (col.rawLen() == 0) return null;
    return col.rawItems().ptr;
}

/// Raw pointer to the start of a column's byte buffer by component hash.
pub fn columnPtrByHash(self: *Self, hash: u64) ?[*]u8 {
    const index = self.columnIndex(hash) orelse return null;
    return self.columnPtr(index);
}

/// Fills `out` with one `[*]u8` per hash in `hashes`, in the same order.
/// Returns false if any hash is missing from this archetype.
/// Used by the system runner to build the slices array cheaply.
pub fn fillColumnPtrs(self: *Self, hashes: []const u64, out: [][*]u8) bool {
    std.debug.assert(out.len >= hashes.len);
    for (hashes, 0..) |hash, i| {
        out[i] = self.columnPtrByHash(hash) orelse return false;
    }
    return true;
}

/// Add an entity to this archetype.
/// `component_data` must be one opaque pointer per column, in `component_hashes` order.
/// Each pointer must point to at least `entry_size` readable bytes.
pub fn addEntity(self: *Self, entity: ecs.Entity, component_data: []const *const anyopaque) !void {
    std.debug.assert(component_data.len == self.columns.len());

    const row = self.entities.len();

    try self.entities.append(entity);
    errdefer _ = self.entities.pop();

    var appended: usize = 0;
    errdefer {
        for (self.columns.items()[0..appended]) |*col| {
            col.swapRemove(col.len() - 1);
        }
    }

    for (self.columns.items(), component_data) |*col, data| {
        try col.appendBytes(data);
        appended += 1;
    }

    try self.entity_to_row.set(entity, row);
}

/// Remove an entity from this archetype using swap-remove to keep columns dense.
/// Returns the entity that was moved into the vacated slot (if any),
/// so the caller can update any external bookkeeping.
pub fn removeEntity(self: *Self, entity: ecs.Entity) ?ecs.Entity {
    const row = self.entity_to_row.get(entity) orelse return null;
    const last_row = self.entities.len() - 1;
    const last_entity = self.entities.getLast();

    for (self.columns.items()) |*col| col.swapRemove(row);
    _ = self.entities.swapRemove(row);
    self.entity_to_row.remove(entity);

    if (row == last_row) return null;

    self.entity_to_row.set(last_entity, row) catch {};
    return last_entity;
}

/// Get a raw opaque pointer to a component by entity and hash.
pub fn getComponent(self: *Self, entity: ecs.Entity, hash: u64) ?*anyopaque {
    const row = self.entity_to_row.get(entity) orelse return null;
    const col_index = self.columnIndex(hash) orelse return null;
    return self.columns.items()[col_index].get(row);
}

/// Get a typed pointer to a component by entity.
pub fn getComponentAs(self: *Self, comptime T: type, entity: ecs.Entity) ?*T {
    const hash = comptime core.type_erasure.typeToHash(T);
    const row = self.entity_to_row.get(entity) orelse return null;
    const col_index = self.columnIndex(hash) orelse return null;
    return self.columns.items()[col_index].getAs(T, row);
}

/// Get a const typed pointer to a component by entity.
pub fn getComponentConstAs(self: *Self, comptime T: type, entity: ecs.Entity) ?*const T {
    return self.getComponentAs(T, entity);
}

/// Overwrite a component value for an entity that is already in this archetype.
pub fn setComponent(self: *Self, entity: ecs.Entity, hash: u64, data: *const anyopaque) void {
    const row = self.entity_to_row.get(entity) orelse return;
    const col_index = self.columnIndex(hash) orelse return;
    self.columns.items()[col_index].set(row, data);
}

/// Typed overwrite of a component value.
pub fn setComponentAs(self: *Self, comptime T: type, entity: ecs.Entity, value: T) void {
    const hash = comptime core.type_erasure.typeToHash(T);
    self.setComponent(entity, hash, &value);
}

/// Move an entity from `src` into `self`, copying shared columns and filling new ones
/// from `new_components`. `src` does NOT remove the entity — call `src.removeEntity`
/// after this succeeds so that a failed move leaves `src` untouched.
///
/// `new_components` provides raw data for columns that exist in `self` but not in `src`.
pub fn moveEntityFrom(
    self: *Self,
    entity: ecs.Entity,
    src: *Self,
    new_components: []const struct { hash: u64, data: *const anyopaque },
) !void {
    const src_row = src.entity_to_row.get(entity) orelse return error.EntityNotFound;
    const dst_row = self.entities.len();

    try self.entities.append(entity);
    errdefer _ = self.entities.pop();

    var appended: usize = 0;
    errdefer {
        for (self.columns.items()[0..appended]) |*col| {
            col.swapRemove(col.len() - 1);
        }
    }

    for (self.component_hashes, 0..) |hash, col_index| {
        if (src.columnIndex(hash)) |src_col| {
            const bytes = src.columns.items()[src_col].getAsBytes(src_row);
            try self.columns.items()[col_index].appendBytes(bytes.ptr);
            appended += 1;
            continue;
        }

        var found = false;
        for (new_components) |nc| {
            if (nc.hash != hash) continue;
            try self.columns.items()[col_index].appendBytes(nc.data);
            appended += 1;
            found = true;
            break;
        }

        if (!found) return error.MissingComponentData;
    }

    try self.entity_to_row.set(entity, dst_row);
}

/// Iterates over all entities in this archetype in insertion order (dense index order).
pub const EntityIterator = struct {
    archetype: *Self,
    index: usize = 0,

    pub fn next(it: *EntityIterator) ?ecs.Entity {
        if (it.index >= it.archetype.entities.len()) return null;
        defer it.index += 1;
        return it.archetype.entities.items()[it.index];
    }

    pub fn reset(it: *EntityIterator) void {
        it.index = 0;
    }
};

pub fn entityIterator(self: *Self) EntityIterator {
    return .{ .archetype = self };
}

/// Iterates over all entities, yielding both the entity ID and its dense row index.
/// The row index can be used directly with `columns[i].get(row)` for zero-cost component access.
pub const RowIterator = struct {
    archetype: *Self,
    index: usize = 0,

    pub const Row = struct {
        entity: ecs.Entity,
        /// Dense index into each column — use this to index `archetype.columns[i].get(row)`.
        row: usize,
    };

    pub fn next(it: *RowIterator) ?Row {
        if (it.index >= it.archetype.entities.len()) return null;
        defer it.index += 1;
        return .{
            .entity = it.archetype.entities.items()[it.index],
            .row = it.index,
        };
    }

    pub fn reset(it: *RowIterator) void {
        it.index = 0;
    }
};

pub fn rowIterator(self: *Self) RowIterator {
    return .{ .archetype = self };
}

/// Iterates over a single typed component column.
/// Useful for simple single-component passes without going through the system runner.
pub fn ComponentIterator(comptime T: type) type {
    return struct {
        const Iterator = @This();

        slice: []T,
        index: usize = 0,

        pub fn next(it: *Iterator) ?*T {
            if (it.index >= it.slice.len) return null;
            defer it.index += 1;
            return &it.slice[it.index];
        }

        pub fn reset(it: *Iterator) void {
            it.index = 0;
        }
    };
}

/// Returns a typed component iterator for column `T`.
/// Returns null if this archetype doesn't hold `T`.
/// When the archetype is empty the iterator is valid but immediately exhausted.
pub fn componentIterator(self: *Self, comptime T: type) ?ComponentIterator(T) {
    const hash = comptime core.type_erasure.typeToHash(T);
    const col_index = self.columnIndex(hash) orelse return null;
    const col = &self.columns.items()[col_index];

    if (col.len() == 0) return ComponentIterator(T){ .slice = &.{} };
    return ComponentIterator(T){ .slice = col.slicedAs(T) };
}
