const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");

const Self = @This();

const Entity = usize;

free_list: core.List(usize),
next_entity_index: usize = 0,

groups: std.AutoHashMap(u128, core.types.SparseSet(Entity)),
type_bit_index_map: std.AutoHashMap(u64, usize),
next_component_bit_index: usize = 0,

stores: std.AutoHashMap(u64, core.types.ByteSparseSet),

allocator: Allocator,

pub fn init(allocator: Allocator) Self {
    return Self{
        .allocator = allocator,

        .groups = .init(allocator),
        .type_bit_index_map = .init(allocator),
        .next_component_bit_index = 0,

        .stores = .init(allocator),

        .free_list = .init(allocator),
        .next_entity_index = 0,
    };
}

pub fn deinit(self: *Self) void {
    const stores_iterator = self.stores.valueIterator();
    while (stores_iterator.next()) |set| {
        set.deinit();
    }
    self.stores.deinit();

    const groups_iterator = self.groups.valueIterator();
    while (groups_iterator.next()) |group| {
        group.deinit();
    }
    self.groups.deinit();

    self.type_bit_index_map.deinit();
    self.free_list.deinit();

    self.* = undefined;
}

pub inline fn getComponentStore(self: *Self, comptime T: type) ?*core.types.ByteSparseSet {
    return self.stores.getPtr(comptime core.type_erasure.typeToHash(T));
}

pub fn getComponentStores(self: *Self, comptime types: []const type) ?core.Array(*core.types.ByteSparseSet) {
    var list = core.List(*core.types.ByteSparseSet).init(self.allocator);
    defer list.deinit();

    inline for (types) |T| {
        try list.append(self.getComponentStore(T) orelse return null);
    }

    return list.cloneToArray();
}

pub fn getComponentStoresByHash(self: *Self, comptime hashes: []const u64) ?core.Array(*core.types.ByteSparseSet) {
    var list = core.List(*core.types.ByteSparseSet).init(self.allocator);
    defer list.deinit();

    inline for (hashes) |hash| {
        try list.append(self.stores.getPtr(hash) orelse return null);
    }

    return list.cloneToArray();
}

inline fn assertValidEntityId(self: *Self, id: Entity) void {
    core.assertFmt(id < self.next_entity_index, "{d} was outside of created entities", .{id});
    core.assertFmt(self.free_list.contains(id), "{d} belongs to a dead entity", .{id});
}

fn getMaskForEntity(self: *Self, entity: Entity) u128 {
    var mask: u128 = 0;
    var iter = self.groups.iterator();
    while (iter.next()) |entry| {
        if (!entry.value_ptr.*.contains(entity)) continue;

        entry.value_ptr.*.remove(entity);
        mask = entry.key_ptr.*;
    }

    return mask;
}

pub fn newEntity(self: *Self) !void {
    const new_id = self.free_list.pop() orelse get: {
        defer self.next_entity_index += 1;
        break :get self.next_entity_index;
    };

    if (!self.groups.contains(0))
        try self.groups.put(0, .init(self.allocator));

    const ptr = self.groups.getPtr(0).?;
    try ptr.set(new_id, new_id);
}

pub fn addComponent(self: *Self, entity: Entity, component: anytype) !void {
    self.assertValidEntityId(entity);

    const T = @TypeOf(component);
    const hash = comptime core.type_erasure.typeToHash(T);

    if (!self.type_bit_index_map.contains(hash)) {
        try self.type_bit_index_map.put(hash, self.next_component_bit_index);
        self.next_component_bit_index += 1;
    }

    const current_mask: u128 = self.getMaskForEntity(entity);
    const bit_index = self.type_bit_index_map.get(hash).?;
    const base_mask: u128 = 0b1;
    const shifted = base_mask << bit_index;
    const new_bitmask = current_mask | shifted;

    if (!self.groups.contains(new_bitmask))
        self.groups.put(new_bitmask, .init(self.allocator));

    const ptr = self.groups.getPtr(new_bitmask).?;
    try ptr.set(entity, entity);

    if (!self.stores.contains(hash))
        try self.stores.put(hash, .init(self.allocator, T));

    const store = self.stores.getPtr(hash).?;
    try store.set(entity, component);
}

pub fn getComponent(self: *Self, comptime T: type, entity: Entity) ?*T {
    self.assertValidEntityId(entity);

    const store = self.getComponentStore(T) orelse return null;
    return store.getAs(entity, T);
}

pub fn getConstComponent(self: *Self, comptime T: type, entity: Entity) ?*const T {
    self.assertValidEntityId(entity);

    const store = self.getComponentStore(T) orelse return null;
    const ptr = store.getAs(entity, T) orelse return null;
    return ptr;
}

pub fn generateComponentMask(self: *Self, hashes: []const u64) ?u128 {
    var current_bitmask: u128 = 0b0;

    for (hashes) |hash| {
        const bit_index = self.type_bit_index_map.get(hash) orelse return null;
        const base_mask: u128 = 0b1;
        const shifted = base_mask << bit_index;
        current_bitmask = current_bitmask | shifted;
    }

    return current_bitmask;
}
