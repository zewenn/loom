const std = @import("std");
const Allocator = std.mem.Allocator;

const lm_types = @import("lm_types");
const ecs = @import("root.zig");

const Self = @This();

const ENTITY_PAGE_CAPACITY: usize = 1024;

/// Initial raw payload entry passed when migrating an entity to a wider archetype.
pub const ComponentDataEntry = struct {
    hash: u64,
    data: *const anyopaque,
};

/// Bitmask uniquely identifying this archetype's component composition.
mask: u128,

/// Ordered component type hashes parallel to `columns`. Owned by this archetype.
component_hashes: []u64,

/// Dense list of entities currently in this archetype, parallel to each column's rows.
entities: lm_types.List(ecs.Entity),

/// Dense byte columns, one `ByteList` per component type in `component_hashes` order.
columns: lm_types.List(lm_types.ByteList),

/// Sparse map from entity identifier to dense row index within this archetype's columns.
entity_to_row: lm_types.types.PagedList(usize, ENTITY_PAGE_CAPACITY),

allocator: Allocator,

/// Construct an archetype whose `component_hashes` and `component_sizes` match in length and order.
pub fn init(
    allocator: Allocator,
    mask: u128,
    component_hashes: []const u64,
    component_sizes: []const usize,
) !Self {
    std.debug.assert(component_hashes.len == component_sizes.len);

    const owned_hashes = try allocator.dupe(u64, component_hashes);
    errdefer allocator.free(owned_hashes);

    var columns: lm_types.List(lm_types.ByteList) = .init(allocator);
    errdefer {
        for (columns.items()) |*column| column.deinit();
        columns.deinit();
    }

    for (component_hashes, component_sizes) |component_hash, component_size_bytes| {
        try columns.append(lm_types.ByteList.initWithInfo(allocator, component_hash, component_size_bytes));
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

/// Release all columns, entity mappings, and owned component hashes.
pub fn deinit(self: *Self) void {
    for (self.columns.items()) |*column| column.deinit();
    self.columns.deinit();

    self.entities.deinit();
    self.entity_to_row.deinit();
    self.allocator.free(self.component_hashes);

    self.* = undefined;
}

/// Return the number of entities currently stored in this archetype.
pub inline fn len(self: *const Self) usize {
    return self.entities.len();
}

/// Return true if no entities currently reside in this archetype.
pub inline fn isEmpty(self: *const Self) bool {
    return self.entities.len() == 0;
}

/// Return true if this archetype satisfies every bit present in `query_mask`.
pub inline fn matchesMask(self: *const Self, query_mask: u128) bool {
    return (self.mask & query_mask) == query_mask;
}

/// Return true if this archetype's composition matches `other_mask` exactly.
pub inline fn exactMask(self: *const Self, other_mask: u128) bool {
    return self.mask == other_mask;
}

/// Return the column index holding `component_hash`, or null if absent.
pub fn columnIndex(self: *const Self, component_hash: u64) ?usize {
    for (self.component_hashes, 0..) |stored_hash, column_index| {
        if (stored_hash == component_hash) return column_index;
    }
    return null;
}

/// Return true if this archetype stores a column for `component_hash`.
pub inline fn hasComponent(self: *const Self, component_hash: u64) bool {
    return self.columnIndex(component_hash) != null;
}

/// Return the dense row index for `entity`, or null if `entity` is not in this archetype.
pub inline fn entityRow(self: *Self, entity: ecs.Entity) ?usize {
    return self.entity_to_row.get(entity);
}

/// Return true if `entity` resides in this archetype.
pub inline fn containsEntity(self: *Self, entity: ecs.Entity) bool {
    return self.entity_to_row.get(entity) != null;
}

/// Return the start of column `column_index`'s dense byte buffer, or null when empty or out of bounds.
pub fn columnBuffer(self: *Self, column_index: usize) ?[*]u8 {
    if (column_index >= self.columns.len()) return null;

    const column = &self.columns.items()[column_index];
    if (column.rawLen() == 0) return null;

    return column.rawItems().ptr;
}

/// Return the start of the dense byte buffer for `component_hash`, or null when missing or empty.
pub fn columnBufferByHash(self: *Self, component_hash: u64) ?[*]u8 {
    const column_index = self.columnIndex(component_hash) orelse return null;
    return self.columnBuffer(column_index);
}

/// Populate `destination_buffers` with column base addresses matching `component_hashes` in order.
/// Returns false when any requested hash is missing from this archetype.
pub fn fillColumnBuffers(
    self: *Self,
    component_hashes: []const u64,
    destination_buffers: [][*]u8,
) bool {
    std.debug.assert(destination_buffers.len >= component_hashes.len);

    for (component_hashes, 0..) |component_hash, slot_index| {
        destination_buffers[slot_index] = self.columnBufferByHash(component_hash) orelse return false;
    }
    return true;
}

/// Append `entity` and one payload pointer per column in `component_hashes` order.
pub fn addEntity(self: *Self, entity: ecs.Entity, component_data: []const *const anyopaque) !void {
    std.debug.assert(component_data.len == self.columns.len());

    const target_row = self.entities.len();

    try self.entities.append(entity);
    errdefer _ = self.entities.pop();

    var appended_column_count: usize = 0;
    errdefer rollbackAppendedColumns(self.columns.items()[0..appended_column_count]);

    for (self.columns.items(), component_data) |*column, component_payload| {
        try column.appendBytes(component_payload);
        appended_column_count += 1;
    }

    try self.entity_to_row.set(entity, target_row);
}

/// Remove `entity` via swap-remove and return the relocated trailing entity if any moved.
pub fn removeEntity(self: *Self, entity: ecs.Entity) ?ecs.Entity {
    const removed_row = self.entity_to_row.get(entity) orelse return null;
    const last_row = self.entities.len() - 1;
    const trailing_entity = self.entities.getLast();

    for (self.columns.items()) |*column| column.swapRemove(removed_row);
    _ = self.entities.swapRemove(removed_row);
    self.entity_to_row.remove(entity);

    if (removed_row == last_row) return null;

    self.entity_to_row.set(trailing_entity, removed_row) catch {};
    return trailing_entity;
}

/// Return an opaque pointer to `entity`'s component data matching `component_hash`.
pub fn getComponent(self: *Self, entity: ecs.Entity, component_hash: u64) ?*anyopaque {
    const row_index = self.entity_to_row.get(entity) orelse return null;
    const column_index = self.columnIndex(component_hash) orelse return null;
    return self.columns.items()[column_index].get(row_index);
}

/// Return a mutable typed pointer to `entity`'s `Component` value.
pub fn getComponentAs(self: *Self, comptime Component: type, entity: ecs.Entity) ?*Component {
    const component_hash = comptime lm_types.type_erasure.typeToHash(Component);
    const row_index = self.entity_to_row.get(entity) orelse return null;
    const column_index = self.columnIndex(component_hash) orelse return null;
    return self.columns.items()[column_index].getAs(Component, row_index);
}

/// Return a read-only typed pointer to `entity`'s `Component` value.
pub fn getComponentConstAs(self: *Self, comptime Component: type, entity: ecs.Entity) ?*const Component {
    return self.getComponentAs(Component, entity);
}

/// Overwrite the component identified by `component_hash` on an existing entity.
pub fn setComponent(self: *Self, entity: ecs.Entity, component_hash: u64, component_data: *const anyopaque) void {
    const row_index = self.entity_to_row.get(entity) orelse return;
    const column_index = self.columnIndex(component_hash) orelse return;
    self.columns.items()[column_index].set(row_index, component_data);
}

/// Overwrite `Component` on an existing entity with `value`.
pub fn setComponentAs(self: *Self, comptime Component: type, entity: ecs.Entity, value: Component) void {
    const component_hash = comptime lm_types.type_erasure.typeToHash(Component);
    self.setComponent(entity, component_hash, &value);
}

/// Copy `entity` from `source_archetype` into `self`, supplying newly added columns via `new_components`.
/// Leaves `source_archetype` unmodified so callers can remove after migration succeeds.
pub fn moveEntityFrom(
    self: *Self,
    entity: ecs.Entity,
    source_archetype: *Self,
    new_components: []const ComponentDataEntry,
) !void {
    const source_row = source_archetype.entity_to_row.get(entity) orelse return error.EntityNotFound;
    const destination_row = self.entities.len();

    try self.entities.append(entity);
    errdefer _ = self.entities.pop();

    var appended_column_count: usize = 0;
    errdefer rollbackAppendedColumns(self.columns.items()[0..appended_column_count]);

    for (self.component_hashes, 0..) |component_hash, column_index| {
        const component_payload: *const anyopaque = if (source_archetype.columnIndex(component_hash)) |source_column_index|
            source_archetype.columns.items()[source_column_index].getAsBytes(source_row).ptr
        else
            findComponentData(new_components, component_hash) orelse return error.MissingComponentData;

        try self.columns.items()[column_index].appendBytes(component_payload);
        appended_column_count += 1;
    }

    try self.entity_to_row.set(entity, destination_row);
}

/// Sequential iterator yielding each entity identifier stored in this archetype.
pub const EntityIterator = struct {
    archetype: *Self,
    index: usize = 0,

    pub fn next(self: *EntityIterator) ?ecs.Entity {
        if (self.index >= self.archetype.entities.len()) return null;
        defer self.index += 1;
        return self.archetype.entities.items()[self.index];
    }

    pub fn reset(self: *EntityIterator) void {
        self.index = 0;
    }
};

/// Create an iterator over all entities in this archetype in dense order.
pub fn entityIterator(self: *Self) EntityIterator {
    return .{ .archetype = self };
}

/// Sequential iterator yielding each entity alongside its dense row index.
pub const RowIterator = struct {
    archetype: *Self,
    index: usize = 0,

    pub const Row = struct {
        entity: ecs.Entity,
        row: usize,
    };

    pub fn next(self: *RowIterator) ?Row {
        if (self.index >= self.archetype.entities.len()) return null;
        defer self.index += 1;
        return .{
            .entity = self.archetype.entities.items()[self.index],
            .row = self.index,
        };
    }

    pub fn reset(self: *RowIterator) void {
        self.index = 0;
    }
};

/// Create an iterator yielding both entity identifiers and column row indices.
pub fn rowIterator(self: *Self) RowIterator {
    return .{ .archetype = self };
}

/// Typed sequential iterator over a single component column.
pub fn ComponentIterator(comptime Component: type) type {
    return struct {
        const Iterator = @This();

        slice: []Component,
        index: usize = 0,

        pub fn next(self: *Iterator) ?*Component {
            if (self.index >= self.slice.len) return null;
            defer self.index += 1;
            return &self.slice[self.index];
        }

        pub fn reset(self: *Iterator) void {
            self.index = 0;
        }
    };
}

/// Return a typed iterator over the `Component` column, or null if absent.
pub fn componentIterator(self: *Self, comptime Component: type) ?ComponentIterator(Component) {
    const component_hash = comptime lm_types.type_erasure.typeToHash(Component);
    const column_index = self.columnIndex(component_hash) orelse return null;
    const column = &self.columns.items()[column_index];

    if (column.len() == 0) return ComponentIterator(Component){ .slice = &.{} };
    return ComponentIterator(Component){ .slice = column.slicedAs(Component) };
}

fn rollbackAppendedColumns(columns: []lm_types.ByteList) void {
    for (columns) |*column| {
        column.swapRemove(column.len() - 1);
    }
}

fn findComponentData(entries: []const ComponentDataEntry, target_hash: u64) ?*const anyopaque {
    for (entries) |entry| {
        if (entry.hash == target_hash) return entry.data;
    }
    return null;
}
