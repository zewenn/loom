const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");
const ecs = @import("root.zig");

const System = ecs.System;
const Stage = ecs.Stage;
const Entity = ecs.Entity;
const CommandBuffer = ecs.CommandBuffer;
const StageInfo = @import("stages.zig").StageInfo;

const Self = @This();

cleanup_marks: ecs.CleanupMarks,
// systems: std.AutoHashMap(Stage, core.List(System)),
systems: core.types.SparseSet(StageInfo),

mutex: std.Thread.Mutex,

available_entity_ids: core.List(usize),
next_entity_index: usize = 0,

masks: core.types.SparseSet(u128),
type_bit_index_set: core.types.SparseSet(u64),
next_component_bit_index: u7 = 0,

stores: std.AutoHashMap(u64, core.types.ByteSparseSet),

thread_pool: ?std.Thread.Pool,
run_stage_scratch_memory: core.List(*anyopaque),
cleanup_scratch_memory: core.List(*anyopaque),

command_buffer: CommandBuffer,

allocator: Allocator,

pub fn init(allocator: Allocator) Self {
    return Self{
        .allocator = allocator,

        .type_bit_index_set = .init(allocator),
        .next_component_bit_index = 0,

        .masks = .init(allocator),
        .stores = .init(allocator),
        .systems = .init(allocator),

        .available_entity_ids = .init(allocator),
        .next_entity_index = 0,
        .mutex = .{},

        .thread_pool = null,
        .run_stage_scratch_memory = .init(allocator),
        .cleanup_scratch_memory = .init(allocator),

        .command_buffer = .init(allocator),

        .cleanup_marks = .init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    var stores_iterator = self.stores.valueIterator();
    while (stores_iterator.next()) |set| {
        set.deinit();
    }
    self.stores.deinit();

    for (self.systems.dense.items()) |*info| {
        info.deinit();
    }
    self.systems.deinit();

    self.masks.deinit();
    self.type_bit_index_set.deinit();
    self.available_entity_ids.deinit();

    if (self.thread_pool) |*pool| pool.deinit();
    self.run_stage_scratch_memory.deinit();
    self.cleanup_scratch_memory.deinit();

    self.command_buffer.deinit();

    self.* = undefined;
}

// Utils
// --------------------------------------------------------------------------------------------------------

inline fn getComponentStore(self: *Self, comptime T: type) ?*core.types.ByteSparseSet {
    return self.stores.getPtr(comptime core.type_erasure.typeToHash(T));
}

fn getComponentStoresByBits(self: *Self, bits: u128, buffer: *core.List(*anyopaque)) !void {
    buffer.shrinkRetainingCapacity(0);
    try buffer.ensureTotalCapacity(128);

    var index: u7 = 0;
    while (index < @min(127, self.next_component_bit_index)) : (index += 1) {
        const base_mask: u128 = 0b1;
        const shifted = base_mask << @intCast(index);

        if (shifted & bits == 0) continue;

        const hash = self.type_bit_index_set.get(index) orelse return error.HashNotFound;
        const store_ptr = self.stores.getPtr(hash) orelse return error.StoreNotFound;

        try buffer.append(store_ptr);
    }
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

// Entities
// --------------------------------------------------------------------------------------------------------

pub fn newEntity(self: *Self) !Entity {
    self.mutex.lock();
    defer self.mutex.unlock();

    const new_id = self.available_entity_ids.pop() orelse get: {
        defer self.next_entity_index += 1;
        break :get self.next_entity_index;
    };

    try self.command_buffer.addComponent(new_id, ecs.Context{
        .world = self,
        .entity = new_id,
    });

    try self.masks.set(new_id, 0);
    return new_id;
}

fn removeEntity(self: *Self, entity: Entity) !void {
    try self.cleanup_marks.entities.append(entity);
}

// Components
// --------------------------------------------------------------------------------------------------------

fn addComponent(self: *Self, entity: Entity, entry_id: u64, entry_size: usize, entry: *const anyopaque) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    self.assertValidEntityId(entity);

    if (!self.type_bit_index_set.containsValue(entry_id)) {
        try self.type_bit_index_set.set(self.next_component_bit_index, entry_id);
        self.next_component_bit_index += 1;
    }

    const bit_index = self.type_bit_index_set.getKeyByValue(entry_id).?;
    const shift = core.coerceTo(u7, bit_index).?;

    const component_bit = @as(u128, 1) << shift;

    const old_mask: u128 = self.masks.get(entity) orelse 0;
    const new_mask = old_mask | component_bit;
    try self.masks.set(entity, new_mask);

    if (!self.stores.contains(entry_id))
        try self.stores.put(entry_id, .initFromInfo(self.allocator, entry_id, entry_size));

    const store = self.stores.getPtr(entry_id).?;
    try store.setWithInfo(entity, entry_id, entry_size, entry);
}

pub fn getComponent(self: *Self, comptime T: type, entity: Entity) ?*T {
    if (!self.isEntityAlive(entity)) return null;

    const store = self.getComponentStore(T) orelse return null;
    return store.getAs(entity, T);
}

pub fn getComponentConst(self: *Self, comptime T: type, entity: Entity) ?*const T {
    if (!self.isEntityAlive(entity)) return null;

    const store = self.getComponentStore(T) orelse return null;
    const ptr = store.getAs(entity, T) orelse return null;
    return ptr;
}

fn removeComponent(self: *Self, entity: Entity, hash: u64) !void {
    try self.cleanup_marks.components.set(entity, hash);
}

// Systems
// --------------------------------------------------------------------------------------------------------

fn addSystem(self: *Self, stage: Stage, system: System) !void {
    const at = core.types.coerceTo(usize, stage).?;
    if (!self.systems.contains(at))
        try self.systems.set(at, .init(self.allocator, self));

    const info = self.systems.getPtr(at) orelse return;
    try info.addSystem(system);
}

pub fn runStage(self: *Self, stage: Stage) !void {
    self.mutex.lock();
    defer {
        self.mutex.unlock();
        self.applyCommandBuffer() catch |err| {
            std.log.err("command buffer could not be applied: {any}", .{err});
        };
    }

    const stage_info = self.systems.getPtr(core.types.coerceTo(usize, stage).?) orelse return;
    const batches = stage_info.batches;
    if (batches.len() == 0) return;

    try self.run_stage_scratch_memory.resize(stage_info.max_hash_count * 2 * batches.len());
    const memory = self.run_stage_scratch_memory.items();

    if (self.thread_pool == null) {
        self.thread_pool = undefined;
        try self.thread_pool.?.init(.{ .allocator = self.allocator, .n_jobs = 16 });
    }

    const pool = &(self.thread_pool orelse return);
    var wg: std.Thread.WaitGroup = .{};

    for (batches.items(), 0..) |batch, index| {
        const start = stage_info.max_hash_count * 2 * index;
        const end = stage_info.max_hash_count * 2 * (index + 1);

        pool.spawnWg(&wg, executeBatch, .{ self, batch.items(), memory[start..end] });
    }

    wg.wait();
}

fn executeBatch(self: *Self, systems: []const System, memory: []*anyopaque) void {
    outer: for (systems) |system| {
        const group_mask = system.bit_mask orelse continue;
        const hash_count = system.hashes.len;

        const components = memory[0..hash_count];
        const stores = memory[hash_count .. hash_count * 2];

        // TODO:    cache this to avoid hashmap lookups
        //          when a new store gets added systems need to be refreshed :(
        for (system.hashes, 0..) |hash, index| {
            stores[index] = self.stores.getPtr(hash) orelse continue :outer;
        }

        // TODO:    cache this on the system and only modify if a new component
        //          has been added to a store matched by the bitmask
        var smallest_store: *core.types.ByteSparseSet = core.ptrCast(core.types.ByteSparseSet, stores[0]);
        for (stores[1..]) |ptr| {
            const store = core.ptrCast(core.types.ByteSparseSet, ptr);
            if (store.len() < smallest_store.len()) smallest_store = store;
        }

        // TODO:    add thread pooling to this to make entity processing faster
        entities: for (smallest_store.backlink.items()) |entity| {
            const entity_mask = self.masks.get(entity).?;
            if ((group_mask & entity_mask) != group_mask) continue;

            for (stores, 0..) |raw_ptr, index| {
                const store = core.ptrCast(core.types.ByteSparseSet, raw_ptr);

                const new_ptr = store.get(entity) orelse continue :entities;
                components[index] = new_ptr;
            }

            system.invoke(components);
        }
    }
}

fn removeSystem(self: *Self, stage: Stage, system: System) !void {
    try self.cleanup_marks.systems.append(.init(stage, system.id));
}

// Cleanup
// --------------------------------------------------------------------------------------------------------

pub fn applyCommandBuffer(self: *Self) !void {
    for (self.command_buffer.commands.items()) |cmd| switch (cmd) {
        .make_entity => |arr| {
            defer self.command_buffer.allocator.free(arr);

            const entity = try self.newEntity();
            for (arr) |info| {
                const start = info.data_offset;
                const end = info.data_offset + info.data_size;
                try self.addComponent(entity, info.type_hash, info.data_size, self.command_buffer.data.items()[start..end].ptr);
            }
        },
        .add_component => |info| {
            const start = info.data_offset;
            const end = info.data_offset + info.data_size;
            try self.addComponent(info.entity, info.type_hash, info.data_size, self.command_buffer.data.items()[start..end].ptr);
        },
        .add_system => |info| try self.addSystem(info.stage, info.system),

        // TODO:    rework removes to actually remove and not fuck with the heap
        .remove_entity => |entity| try self.removeEntity(entity),
        .remove_component => |data| try self.removeComponent(data.entity, data.type_hash),
        .remove_system => |info| try self.removeSystem(info.stage, info.system),
    };

    self.runCleanup();
}

// TODO:    remove unnecessary allocations for removals, this can be merged into applyCommandBuffer
fn runCleanup(self: *Self) void {
    defer {
        self.command_buffer.reset();
        self.cleanup_marks.reset();
    }

    for (self.cleanup_marks.entities.items()) |entity| {
        if (!self.isEntityAlive(entity)) continue;

        const bits = self.masks.get(entity) orelse continue;
        self.getComponentStoresByBits(bits, &self.cleanup_scratch_memory) catch continue;

        for (self.cleanup_scratch_memory.items()) |mem| {
            const store = core.ptrCast(core.types.ByteSparseSet, mem);
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

    for (self.cleanup_marks.systems.items()) |kv| {
        const stage = core.types.coerceTo(usize, kv.key).?;
        const target_system_id = kv.value;

        const stage_list = self.systems.getPtr(stage) orelse continue;
        stage_list.removeSystem(target_system_id);
    }
}
