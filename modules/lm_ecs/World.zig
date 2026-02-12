const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");
const ecs = @import("root.zig");

const System = ecs.System;
const Stage = ecs.Stage;
const Entity = ecs.Entity;

const Self = @This();

cleanup_marks: ecs.CleanupMarks,
systems: std.AutoHashMap(Stage, core.List(System)),

available_entity_ids: core.List(usize),
next_entity_index: usize = 0,

groups: std.AutoHashMap(u128, core.types.SparseSet(Entity)),
type_bit_index_map: std.AutoHashMap(u64, u7),
next_component_bit_index: u7 = 0,

stores: std.AutoHashMap(u64, core.types.ByteSparseSet),

allocator: Allocator,

pub fn init(allocator: Allocator) Self {
    return Self{
        .allocator = allocator,

        .groups = .init(allocator),
        .type_bit_index_map = .init(allocator),
        .next_component_bit_index = 0,

        .stores = .init(allocator),
        .systems = .init(allocator),

        .available_entity_ids = .init(allocator),
        .next_entity_index = 0,

        .cleanup_marks = .init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    var stores_iterator = self.stores.valueIterator();
    while (stores_iterator.next()) |set| {
        set.deinit();
    }
    self.stores.deinit();

    var groups_iterator = self.groups.valueIterator();
    while (groups_iterator.next()) |group| {
        group.deinit();
    }
    self.groups.deinit();

    var systems_iterator = self.systems.valueIterator();
    while (systems_iterator.next()) |system_list| {
        system_list.deinit();
    }
    self.systems.deinit();

    self.type_bit_index_map.deinit();
    self.available_entity_ids.deinit();

    self.* = undefined;
}

// Utils
// --------------------------------------------------------------------------------------------------------
inline fn getComponentStore(self: *Self, comptime T: type) ?*core.types.ByteSparseSet {
    return self.stores.getPtr(comptime core.type_erasure.typeToHash(T));
}

fn getComponentStores(self: *Self, comptime types: []const type) !?core.Array(*core.types.ByteSparseSet) {
    var list = core.List(*core.types.ByteSparseSet).init(self.allocator);

    inline for (types) |T| {
        try list.append(self.getComponentStore(T) orelse return null);
    }

    return try list.toArray();
}

fn getComponentStoresByHash(self: *Self, hashes: []const u64) !?core.Array(*core.types.ByteSparseSet) {
    var list = core.List(*core.types.ByteSparseSet).init(self.allocator);

    for (hashes) |hash| {
        try list.append(self.stores.getPtr(hash) orelse return null);
    }

    return try list.toArray();
}
fn getComponentStoresByBits(self: *Self, bits: u128) !?core.Array(*core.types.ByteSparseSet) {
    var list = core.List(*core.types.ByteSparseSet).init(self.allocator);
    var bit_list = core.List(u7).init(self.allocator);
    defer bit_list.deinit();

    var index: u7 = 0;
    while (index < 127) : (index += 1) {
        const base_mask: u128 = 0b1;
        const shifted = base_mask << @intCast(index);

        if (shifted & bits == 0) continue;

        try bit_list.append(index);
    }

    var iter = self.type_bit_index_map.iterator();
    outer: while (iter.next()) |entry| {
        const len = bit_list.len();
        for (1..len + 1) |j| {
            const item = bit_list.items()[len - j];

            if (item != entry.value_ptr.*) continue;
            _ = bit_list.swapRemove(len - j);

            const hash = entry.key_ptr.*;
            try list.append(self.stores.getPtr(hash) orelse continue :outer);

            continue :outer;
        }
    }

    return try list.toArray();
}

pub inline fn isEntityAlive(self: *Self, entity: Entity) bool {
    return entity < self.next_entity_index and !self.available_entity_ids.contains(entity);
}

inline fn assertValidEntityId(self: *Self, id: Entity) void {
    core.assertFmt(
        self.isEntityAlive(id),
        "{d} was outside of created entities",
        .{id},
    );
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

fn getEntitiesForMask(self: *Self, mask: u128) []const Entity {
    const ptr = self.groups.getPtr(mask) orelse return &.{};
    return ptr.backlink.items();
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

// Entities
// --------------------------------------------------------------------------------------------------------

pub fn newEntity(self: *Self) !Entity {
    const new_id = self.available_entity_ids.pop() orelse get: {
        defer self.next_entity_index += 1;
        break :get self.next_entity_index;
    };

    if (!self.groups.contains(0))
        try self.groups.put(0, .init(self.allocator));

    const ptr = self.groups.getPtr(0).?;
    try ptr.set(new_id, new_id);

    return new_id;
}

pub fn makeEntity(self: *Self, components: anytype) !Entity {
    core.comptimeAssert(core.types.isTuple(components), "components must be in a tuple");

    const handle = try self.newEntity();

    inline for (components) |component| {
        try self.addComponent(handle, component);
    }

    return handle;
}

pub fn removeEntity(self: *Self, entity: Entity) !void {
    try self.cleanup_marks.entities.append(entity);
}

// Components
// --------------------------------------------------------------------------------------------------------

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
        try self.groups.put(new_bitmask, .init(self.allocator));

    const ptr = self.groups.getPtr(new_bitmask).?;
    try ptr.set(entity, entity);

    if (!self.stores.contains(hash))
        try self.stores.put(hash, .init(self.allocator, T));

    const store = self.stores.getPtr(hash).?;
    try store.set(entity, component);
}

pub fn getComponent(self: *Self, comptime T: type, entity: Entity) ?*T {
    if (!self.isEntityAlive(entity)) return null;

    const store = self.getComponentStore(T) orelse return null;
    return store.getAs(entity, T);
}

pub fn getConstComponent(self: *Self, comptime T: type, entity: Entity) ?*const T {
    if (!self.isEntityAlive(entity)) return null;

    const store = self.getComponentStore(T) orelse return null;
    const ptr = store.getAs(entity, T) orelse return null;
    return ptr;
}

pub fn removeComponent(self: *Self, entity: Entity, comptime T: type) !void {
    try self.cleanup_marks.components.set(entity, comptime core.type_erasure.typeToHash(T));
}

// Systems
// --------------------------------------------------------------------------------------------------------

pub fn addSystem(self: *Self, stage: Stage, comptime func: anytype) !void {
    if (!self.systems.contains(stage))
        try self.systems.put(stage, .init(self.allocator));

    const ptr = self.systems.getPtr(stage).?;
    try ptr.append(.init(func));
}

pub fn runStage(self: *Self, stage: Stage) !void {
    const system_list = &(self.systems.get(stage) orelse return);

    outer: for (system_list.items()) |system| {
        const bitmask = self.generateComponentMask(system.hashes) orelse continue;
        const entities = self.getEntitiesForMask(bitmask);

        var stores = (try self.getComponentStoresByHash(system.hashes)) orelse continue;
        defer stores.deinit();

        for (entities) |entity| {
            var ptrs: core.List(*anyopaque) = .init(self.allocator);
            defer ptrs.deinit();

            for (stores.items()) |store| {
                const ptr = store.get(entity) orelse continue :outer;
                try ptrs.append(ptr);
            }

            system.invoke(ptrs.items());
        }
    }
}

pub fn removeSystem(self: *Self, stage: Stage, comptime system: anytype) !void {
    const id = System.init(system).id;
    try self.cleanup_marks.systems.append(.init(stage, id));
}

// Cleanup
// --------------------------------------------------------------------------------------------------------

pub fn runCleanup(self: *Self) void {
    defer self.cleanup_marks.reset();

    for (self.cleanup_marks.entities.items()) |entity| {
        if (!self.isEntityAlive(entity)) continue;

        const bits = self.getMaskForEntity(entity);
        var stores = (self.getComponentStoresByBits(bits) catch continue) orelse continue;
        defer stores.deinit();

        for (stores.items()) |store| {
            store.remove(entity);
        }

        self.available_entity_ids.append(entity) catch continue;
    }

    for (self.cleanup_marks.components.backlink.items(), 0..) |backlink, index| {
        const store_hash = self.cleanup_marks.components.dense.items()[index];
        const entity = self.cleanup_marks.components.sparse.get(backlink) orelse continue;

        if (!self.isEntityAlive(entity)) continue;

        const store = self.stores.getPtr(store_hash) orelse continue;
        store.remove(entity);
    }

    outer: for (self.cleanup_marks.systems.items()) |kv| {
        const stage = kv.key;
        const hash = kv.value;

        const stage_list = self.systems.getPtr(stage) orelse continue;
        for (stage_list.items(), 0..) |item, index| {
            if (item.id != hash) continue;

            _ = stage_list.swapRemove(index);
            continue :outer;
        }
    }
}
