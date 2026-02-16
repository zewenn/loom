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

// TODO:    change masks to no longer use a sparse set
//          use a flat list instead to avoid pagedlists
// masks: core.types.SparseSet(u128),
masks: core.List(u128),
type_bit_index_set: core.types.SparseSet(u64),
next_component_bit_index: u7 = 0,

stores: std.AutoHashMap(u64, core.types.ByteSparseSet),

system_batch_thread_pool: ?std.Thread.Pool,
entity_thread_pool: ?std.Thread.Pool,
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

        .system_batch_thread_pool = null,
        .entity_thread_pool = null,
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

    if (self.system_batch_thread_pool) |*pool| pool.deinit();
    if (self.entity_thread_pool) |*pool| pool.deinit();
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

    if (self.masks.len() <= new_id) {
        try self.masks.resize(new_id + 1);
    }
    self.masks.items()[new_id] = 0;

    return new_id;
}

fn removeEntity(self: *Self, entity: Entity) void {
    if (!self.isEntityAlive(entity)) return;

    const bits = self.masks.at(entity) orelse return;
    self.getComponentStoresByBits(bits, &self.cleanup_scratch_memory) catch return;

    for (self.cleanup_scratch_memory.items()) |mem| {
        const store = core.ptrCast(core.types.ByteSparseSet, mem);
        store.remove(entity);
    }

    self.available_entity_ids.append(entity) catch return;
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

    const old_mask: u128 = self.masks.at(entity) orelse 0;
    const new_mask = old_mask | component_bit;
    self.masks.items()[entity] = new_mask;

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

fn removeComponent(self: *Self, entity: Entity, hash: u64) void {
    if (!self.isEntityAlive(entity)) return;

    const store = self.stores.getPtr(hash) orelse return;
    store.remove(entity);
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

    const entity_threads: usize = @max(1, @min(@divFloor(self.next_entity_index - 1, 8192), 16));

    try self.run_stage_scratch_memory.resize(stage_info.max_hash_count * (entity_threads + 1) * batches.len());
    const memory = self.run_stage_scratch_memory.items();

    if (self.system_batch_thread_pool == null) {
        self.system_batch_thread_pool = undefined;
        try self.system_batch_thread_pool.?.init(.{ .allocator = self.allocator, .n_jobs = batches.len() });
    }

    if (self.entity_thread_pool == null) {
        self.entity_thread_pool = undefined;
        try self.entity_thread_pool.?.init(.{
            .allocator = self.allocator,
            .n_jobs = batches.len() * entity_threads,
        });
    }

    const pool = &(self.system_batch_thread_pool orelse return);
    var wg: std.Thread.WaitGroup = .{};

    for (batches.items(), 0..) |batch, index| {
        const start = stage_info.max_hash_count * (entity_threads + 1) * index;
        const end = stage_info.max_hash_count * (entity_threads + 1) * (index + 1);

        pool.spawnWg(&wg, executeBatch, .{ self, batch.items(), memory[start..end], entity_threads });
    }

    wg.wait();
}

fn executeBatch(self: *Self, systems: []const System, memory: []*anyopaque, entity_groups: usize) void {
    outer: for (systems) |system| {
        const group_mask = system.bit_mask orelse continue;
        const hash_count = system.hashes.len;

        const stores: []*core.types.ByteSparseSet = @ptrCast(memory[0..hash_count]);

        // TODO:    cache this to avoid hashmap lookups
        //          when a new store gets added systems need to be refreshed :(
        var smallest_store: *core.types.ByteSparseSet = undefined;
        for (system.hashes, 0..) |hash, index| {
            const store = self.stores.getPtr(hash) orelse continue :outer;
            stores[index] = store;

            if (index == 0) {
                smallest_store = store;
                continue;
            }

            if (store.len() < smallest_store.len()) smallest_store = store;
        }

        const pool = &(self.entity_thread_pool orelse {
            std.log.err("entity pool does not exist", .{});
            return;
        });
        var wg: std.Thread.WaitGroup = .{};

        const entity_len = smallest_store.backlink.len();
        const size: usize = @max(1, @divFloor(entity_len, entity_groups));
        const rem: usize = entity_len - size * entity_groups;

        for (0..entity_groups) |group_index| {
            const comp_start = hash_count * (group_index + 1);
            const comp_end = comp_start + hash_count;

            const entities_start = size * group_index;
            const entities_end = entities_start + if (group_index != entity_groups - 1 or rem == 0) size else rem;

            const components = memory[comp_start..comp_end];
            const entities = smallest_store.backlink.items()[entities_start..entities_end];

            pool.spawnWg(&wg, entityBatch, .{ self, system, group_mask, entities, stores, components });
        }

        wg.wait();
    }
}

inline fn entityBatch(self: *Self, system: System, group_mask: u128, entities: []usize, stores: []*core.types.ByteSparseSet, components: []*anyopaque) void {
    entities: for (entities) |entity| {
        const entity_mask = self.masks.items()[entity];
        if ((group_mask & entity_mask) != group_mask) continue;

        for (stores, 0..) |store, index| {
            components[index] = store.get(entity) orelse continue :entities;
        }

        system.invoke(components);
    }
}

fn removeSystem(self: *Self, stage: Stage, system: System) void {
    const stage_list = self.systems.getPtr(core.types.coerceTo(usize, stage).?) orelse return;
    stage_list.removeSystem(system.id);
}

// Cleanup
// --------------------------------------------------------------------------------------------------------

pub fn applyCommandBuffer(self: *Self) !void {
    defer self.command_buffer.reset();

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

        .remove_entity => |entity| self.removeEntity(entity),
        .remove_component => |data| self.removeComponent(data.entity, data.type_hash),
        .remove_system => |info| self.removeSystem(info.stage, info.system),
    };
}
