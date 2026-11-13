const std = @import("std");
const Allocator = std.mem.Allocator;

const lm_types = @import("lm_types");
const ecs = @import("root.zig");
const commands = @import("commands.zig");

const System = ecs.System;
const Stage = ecs.Stage;
const Entity = ecs.Entity;
const CommandBuffer = ecs.CommandBuffer;
const Archetype = @import("Archetype.zig");
const StageSchedule = @import("stages.zig").StageSchedule;

const MAX_COMPONENT_TYPES: usize = @bitSizeOf(u128);
const MAX_ENTITY_CREATION_COMPONENTS: usize = MAX_COMPONENT_TYPES + 1;
const ARCHETYPE_PAGE_CAPACITY: usize = 1024;

const Mutex = struct {
    inner: std.Io.Mutex = .init,

    pub fn lock(self: *Mutex) void {
        std.Io.Threaded.mutexLock(&self.inner) catch unreachable;
    }

    pub fn unlock(self: *Mutex) void {
        std.Io.Threaded.mutexUnlock(&self.inner);
    }
};

const ComponentPayload = struct {
    hash: u64,
    byte_size: usize,
    data: *const anyopaque,
};

const Self = @This();

/// Recycled entity identifiers ready for reuse on newly created entities.
available_entity_ids: lm_types.List(Entity),
/// Next sequential identifier assigned when the recycled pool is empty.
next_entity_index: usize,

component_bit_indices: lm_types.types.SparseSet(u64),
next_component_bit_index: u7,
component_sizes: std.AutoHashMap(u64, usize),

/// Dense collection of distinct component archetypes managed by this world.
archetypes: lm_types.List(Archetype),
archetype_lookup: std.AutoHashMap(u128, usize),
entity_to_archetype: lm_types.types.PagedList(usize, ARCHETYPE_PAGE_CAPACITY),

stage_schedules: lm_types.types.SparseSet(StageSchedule),

mutex: Mutex,
/// Thread-safe queue of deferred entity, component, and system mutations.
command_buffer: CommandBuffer,
allocator: Allocator,

/// Initialize an empty ECS world backed by `allocator`.
pub fn init(allocator: Allocator) Self {
    return .{
        .allocator = allocator,

        .available_entity_ids = .init(allocator),
        .next_entity_index = 0,

        .component_bit_indices = .init(allocator),
        .next_component_bit_index = 0,
        .component_sizes = .init(allocator),

        .archetypes = .init(allocator),
        .archetype_lookup = .init(allocator),
        .entity_to_archetype = .init(allocator),

        .stage_schedules = .init(allocator),

        .mutex = .{},
        .command_buffer = .init(allocator),
    };
}

/// Release all archetypes, stage schedules, component metadata, and buffered commands.
pub fn deinit(self: *Self) void {
    for (self.archetypes.items()) |*archetype| archetype.deinit();
    self.archetypes.deinit();
    self.archetype_lookup.deinit();
    self.entity_to_archetype.deinit();

    for (self.stage_schedules.dense.items()) |*schedule| schedule.deinit();
    self.stage_schedules.deinit();

    self.component_bit_indices.deinit();
    self.component_sizes.deinit();
    self.available_entity_ids.deinit();

    self.command_buffer.deinit();

    self.* = undefined;
}

/// Return true if `entity` has been allocated and not yet destroyed.
pub inline fn isEntityAlive(self: *Self, entity: Entity) bool {
    return entity < self.next_entity_index and
        !self.available_entity_ids.contains(entity);
}

/// Return the total count of currently alive entities.
pub fn entityCount(self: *Self) usize {
    return self.next_entity_index - self.available_entity_ids.len();
}

/// Return a mutable pointer to `Component` for `entity`, or null if missing or dead.
pub fn getComponent(self: *Self, comptime Component: type, entity: Entity) ?*Component {
    if (!self.isEntityAlive(entity)) return null;
    const archetype_index = self.entity_to_archetype.get(entity) orelse return null;
    return self.archetypes.items()[archetype_index].getComponentAs(Component, entity);
}

/// Return a read-only pointer to `Component` for `entity`, or null if missing or dead.
pub fn getComponentConst(self: *Self, comptime Component: type, entity: Entity) ?*const Component {
    return self.getComponent(Component, entity);
}

/// Execute all scheduled batches for `stage` across worker threads, then flush the command buffer.
pub fn runStage(self: *Self, stage: Stage) !void {
    self.mutex.lock();
    defer {
        self.mutex.unlock();
        self.flushCommandBuffer() catch |flush_error|
            std.log.err("flushCommandBuffer failed: {any}", .{flush_error});
    }

    const stage_index = lm_types.types.coerceTo(usize, stage).?;
    const schedule = self.stage_schedules.getPtr(stage_index) orelse return;
    const batches = schedule.batches.items();
    if (batches.len == 0) return;

    if (batches.len == 1) {
        self.executeBatch(batches[0].items());
        return;
    }

    self.dispatchParallelBatches(batches);
}

/// Apply all queued commands in `command_buffer` sequentially and reset buffer storage.
pub fn flushCommandBuffer(self: *Self) !void {
    defer self.command_buffer.reset();

    for (self.command_buffer.commands.items()) |command| {
        try self.executeCommand(command);
    }
}

fn newEntity(self: *Self) Entity {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.available_entity_ids.pop() orelse blk: {
        defer self.next_entity_index += 1;
        break :blk self.next_entity_index;
    };
}

fn registerComponentType(self: *Self, component_hash: u64, component_size_bytes: usize) !u128 {
    if (!self.component_bit_indices.containsValue(component_hash)) {
        try self.component_bit_indices.set(self.next_component_bit_index, component_hash);
        try self.component_sizes.put(component_hash, component_size_bytes);
        self.next_component_bit_index += 1;
    }
    const bit_index = self.component_bit_indices.getKeyByValue(component_hash).?;
    return @as(u128, 1) << @intCast(bit_index);
}

inline fn componentBit(self: *Self, component_hash: u64) ?u128 {
    const bit_index = self.component_bit_indices.getKeyByValue(component_hash) orelse return null;
    return @as(u128, 1) << @intCast(bit_index);
}

fn findOrCreateArchetype(self: *Self, mask: u128) !usize {
    if (self.archetype_lookup.get(mask)) |existing_index| return existing_index;

    var component_hashes = lm_types.List(u64).init(self.allocator);
    defer component_hashes.deinit();
    var component_sizes = lm_types.List(usize).init(self.allocator);
    defer component_sizes.deinit();

    try self.collectArchetypeMetadata(mask, &component_hashes, &component_sizes);

    const archetype_index = self.archetypes.len();
    const created_archetype = try Archetype.init(
        self.allocator,
        mask,
        component_hashes.items(),
        component_sizes.items(),
    );
    try self.archetypes.append(created_archetype);
    errdefer {
        var popped_archetype = self.archetypes.pop().?;
        popped_archetype.deinit();
    }

    try self.archetype_lookup.put(mask, archetype_index);
    return archetype_index;
}

fn collectArchetypeMetadata(
    self: *Self,
    mask: u128,
    component_hashes: *lm_types.List(u64),
    component_sizes: *lm_types.List(usize),
) !void {
    var bit_index: u7 = 0;
    while (bit_index < self.next_component_bit_index) : (bit_index += 1) {
        const bit_mask: u128 = @as(u128, 1) << bit_index;
        if (mask & bit_mask == 0) continue;

        const component_hash = self.component_bit_indices.get(bit_index) orelse return error.UnknownComponentType;
        const component_size = self.component_sizes.get(component_hash) orelse return error.UnknownComponentSize;
        try component_hashes.append(component_hash);
        try component_sizes.append(component_size);
    }
}

fn insertEntityDirect(self: *Self, entity: Entity, components_slice: []const ComponentPayload) !void {
    var composition_mask: u128 = 0;
    for (components_slice) |component| {
        composition_mask |= try self.registerComponentType(component.hash, component.byte_size);
    }

    const archetype_index = try self.findOrCreateArchetype(composition_mask);

    var ordered_data: [MAX_COMPONENT_TYPES]*const anyopaque = undefined;
    var ordered_count: usize = 0;

    var bit_index: u7 = 0;
    while (bit_index < self.next_component_bit_index) : (bit_index += 1) {
        const bit_mask: u128 = @as(u128, 1) << bit_index;
        if (composition_mask & bit_mask == 0) continue;

        const target_hash = self.component_bit_indices.get(bit_index) orelse return error.UnknownComponentType;
        ordered_data[ordered_count] = try findPayloadDataByHash(components_slice, target_hash);
        ordered_count += 1;
    }

    try self.archetypes.items()[archetype_index].addEntity(entity, ordered_data[0..ordered_count]);
    try self.entity_to_archetype.set(entity, archetype_index);
}

fn findPayloadDataByHash(components_slice: []const ComponentPayload, target_hash: u64) !*const anyopaque {
    for (components_slice) |component| {
        if (component.hash == target_hash) return component.data;
    }
    return error.MissingComponentData;
}

fn addComponent(
    self: *Self,
    entity: Entity,
    component_hash: u64,
    component_size_bytes: usize,
    component_data: *const anyopaque,
) !void {
    const component_bit_mask = try self.registerComponentType(component_hash, component_size_bytes);

    const existing_archetype_index = self.entity_to_archetype.get(entity);
    const existing_mask: u128 = if (existing_archetype_index) |archetype_index|
        self.archetypes.items()[archetype_index].mask
    else
        0;

    if (existing_mask & component_bit_mask != 0) {
        self.archetypes.items()[existing_archetype_index.?].setComponent(entity, component_hash, component_data);
        return;
    }

    const updated_mask = existing_mask | component_bit_mask;
    const destination_archetype_index = try self.findOrCreateArchetype(updated_mask);

    if (existing_archetype_index) |source_archetype_index| {
        try self.archetypes.items()[destination_archetype_index].moveEntityFrom(
            entity,
            &self.archetypes.items()[source_archetype_index],
            &.{.{ .hash = component_hash, .data = component_data }},
        );
        _ = self.archetypes.items()[source_archetype_index].removeEntity(entity);
    } else {
        try self.archetypes.items()[destination_archetype_index].addEntity(entity, &.{component_data});
    }

    try self.entity_to_archetype.set(entity, destination_archetype_index);
}

fn removeComponent(self: *Self, entity: Entity, component_hash: u64) !void {
    const source_archetype_index = self.entity_to_archetype.get(entity) orelse return;
    const component_bit_mask = self.componentBit(component_hash) orelse return;

    const existing_mask = self.archetypes.items()[source_archetype_index].mask;
    if (existing_mask & component_bit_mask == 0) return;

    const updated_mask = existing_mask & ~component_bit_mask;
    if (updated_mask == 0) {
        _ = self.archetypes.items()[source_archetype_index].removeEntity(entity);
        self.entity_to_archetype.removeFast(entity);
        return;
    }

    const destination_archetype_index = try self.findOrCreateArchetype(updated_mask);
    try self.archetypes.items()[destination_archetype_index].moveEntityFrom(
        entity,
        &self.archetypes.items()[source_archetype_index],
        &.{},
    );
    _ = self.archetypes.items()[source_archetype_index].removeEntity(entity);

    try self.entity_to_archetype.set(entity, destination_archetype_index);
}

fn removeEntity(self: *Self, entity: Entity) void {
    if (!self.isEntityAlive(entity)) return;

    if (self.entity_to_archetype.get(entity)) |archetype_index| {
        _ = self.archetypes.items()[archetype_index].removeEntity(entity);
        self.entity_to_archetype.removeFast(entity);
    }

    self.available_entity_ids.append(entity) catch {};
}

fn addSystem(self: *Self, stage: Stage, system: System) !void {
    const stage_index = lm_types.types.coerceTo(usize, stage).?;

    if (!self.stage_schedules.contains(stage_index)) {
        try self.stage_schedules.set(stage_index, StageSchedule.init(self.allocator, self));
    }

    const schedule = self.stage_schedules.getPtr(stage_index) orelse return;
    try schedule.addSystem(system);
}

fn removeSystem(self: *Self, stage: Stage, system: System) void {
    const stage_index = lm_types.types.coerceTo(usize, stage).?;
    const schedule = self.stage_schedules.getPtr(stage_index) orelse return;
    schedule.removeSystem(system.id);
}

fn dispatchParallelBatches(self: *Self, batches: []const lm_types.List(System)) void {
    const worker_threads = self.allocator.alloc(std.Thread, batches.len - 1) catch {
        for (batches) |batch| self.executeBatch(batch.items());
        return;
    };
    defer self.allocator.free(worker_threads);

    var spawned_count: usize = 0;
    for (batches[1..]) |batch| {
        if (std.Thread.spawn(.{}, executeBatch, .{ self, batch.items() })) |spawned_thread| {
            worker_threads[spawned_count] = spawned_thread;
            spawned_count += 1;
        } else |_| {
            self.executeBatch(batch.items());
        }
    }

    self.executeBatch(batches[0].items());

    for (worker_threads[0..spawned_count]) |worker_thread| {
        worker_thread.join();
    }
}

fn executeBatch(self: *Self, systems: []const System) void {
    var column_buffers: [MAX_COMPONENT_TYPES][*]u8 = undefined;

    for (systems) |system| {
        const resolved_system = self.resolveSystemMasks(system) orelse continue;
        self.executeSystemAcrossArchetypes(resolved_system, &column_buffers);
    }
}

fn resolveSystemMasks(self: *Self, system: System) ?System {
    var resolved = system;
    if (!resolved.hasMasks()) {
        resolved.bit_mask = StageSchedule.generateComponentMask(self, resolved.hashes);
        resolved.write_mask = StageSchedule.generateComponentMask(self, resolved.write_hashes);
        resolved.read_mask = StageSchedule.generateComponentMask(self, resolved.read_hashes);
    }
    if (!resolved.hasMasks()) return null;
    return resolved;
}

fn executeSystemAcrossArchetypes(
    self: *Self,
    system: System,
    column_buffers: *[MAX_COMPONENT_TYPES][*]u8,
) void {
    const query_mask = system.bit_mask orelse return;
    const hash_count = system.hashes.len;

    for (self.archetypes.items()) |*archetype| {
        if (archetype.isEmpty()) continue;
        if (!archetype.matchesMask(query_mask)) continue;
        if (!archetype.fillColumnBuffers(system.hashes, column_buffers[0..hash_count])) continue;

        system.callback(archetype.len(), column_buffers) catch |callback_error|
            std.log.err("system '{s}' failed: {any}", .{ system.name, callback_error });
    }
}

fn executeCommand(self: *Self, command: commands.Command) !void {
    switch (command) {
        .make_entity => |descriptors| try self.executeMakeEntity(descriptors),
        .add_component => |payload| try self.executeAddComponent(payload),
        .add_system => |system_command| try self.addSystem(system_command.stage, system_command.system),
        .remove_entity => |entity| self.removeEntity(entity),
        .remove_component => |removal| try self.removeComponent(removal.entity, removal.type_hash),
        .remove_system => |system_command| self.removeSystem(system_command.stage, system_command.system),
    }
}

fn executeMakeEntity(self: *Self, descriptors: []const commands.ComponentDescriptor) !void {
    const entity = self.newEntity();

    var payloads: [MAX_ENTITY_CREATION_COMPONENTS]ComponentPayload = undefined;
    var entity_context = ecs.Context{ .world = self, .entity = entity };
    payloads[0] = .{
        .hash = comptime lm_types.type_erasure.typeToHash(ecs.Context),
        .byte_size = lm_types.type_erasure.alignedSize(ecs.Context),
        .data = &entity_context,
    };

    for (descriptors, 1..) |descriptor, payload_index| {
        payloads[payload_index] = .{
            .hash = descriptor.type_hash,
            .byte_size = descriptor.byte_size,
            .data = self.command_buffer.component_payloads.items()[descriptor.byte_offset..].ptr,
        };
    }

    try self.insertEntityDirect(entity, payloads[0 .. descriptors.len + 1]);
}

fn executeAddComponent(self: *Self, payload: commands.AddComponentPayload) !void {
    const start_offset = payload.byte_offset;
    const end_offset = payload.byte_offset + payload.byte_size;
    try self.addComponent(
        payload.entity,
        payload.type_hash,
        payload.byte_size,
        self.command_buffer.component_payloads.items()[start_offset..end_offset].ptr,
    );
}
