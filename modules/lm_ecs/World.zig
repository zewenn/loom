const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");
const ecs = @import("root.zig");

const System = ecs.System;
const Stage = ecs.Stage;
const Entity = ecs.Entity;
const CommandBuffer = ecs.CommandBuffer;
const Archetype = @import("Archetype.zig");
const StageInfo = @import("stages.zig").StageInfo;

const Mutex = struct {
    impl: std.Io.Mutex = .init,

    pub fn lock(self: *Mutex) void {
        std.Io.Threaded.mutexLock(&self.impl);
    }

    pub fn unlock(self: *Mutex) void {
        std.Io.Threaded.mutexUnlock(&self.impl);
    }
};

const Self = @This();

available_entity_ids: core.List(Entity),
next_entity_index: usize,

type_bit_index_set: core.types.SparseSet(u64),
next_component_bit_index: u7,
component_sizes: std.AutoHashMap(u64, usize),

archetypes: core.List(Archetype),
archetype_lookup: std.AutoHashMap(u128, usize),
entity_to_archetype: core.types.PagedList(usize, 1024),

systems: core.types.SparseSet(StageInfo),

mutex: Mutex,
command_buffer: CommandBuffer,
allocator: Allocator,

pub fn init(allocator: Allocator) Self {
    return .{
        .allocator = allocator,

        .available_entity_ids = .init(allocator),
        .next_entity_index = 0,

        .type_bit_index_set = .init(allocator),
        .next_component_bit_index = 0,
        .component_sizes = .init(allocator),

        .archetypes = .init(allocator),
        .archetype_lookup = .init(allocator),
        .entity_to_archetype = .init(allocator),

        .systems = .init(allocator),

        .mutex = .{},
        .command_buffer = .init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    for (self.archetypes.items()) |*arch| arch.deinit();
    self.archetypes.deinit();
    self.archetype_lookup.deinit();
    self.entity_to_archetype.deinit();

    for (self.systems.dense.items()) |*info| info.deinit();
    self.systems.deinit();

    self.type_bit_index_set.deinit();
    self.component_sizes.deinit();
    self.available_entity_ids.deinit();

    self.command_buffer.deinit();

    self.* = undefined;
}

fn newEntity(self: *Self) !Entity {
    self.mutex.lock();
    defer self.mutex.unlock();

    const id = self.available_entity_ids.pop() orelse blk: {
        defer self.next_entity_index += 1;
        break :blk self.next_entity_index;
    };

    return id;
}

pub inline fn isEntityAlive(self: *Self, entity: Entity) bool {
    return entity < self.next_entity_index and
        !self.available_entity_ids.contains(entity);
}

pub fn entityCount(self: *Self) usize {
    return self.next_entity_index - self.available_entity_ids.len();
}

pub fn getComponent(self: *Self, comptime T: type, entity: Entity) ?*T {
    if (!self.isEntityAlive(entity)) return null;
    const arch_index = self.entity_to_archetype.get(entity) orelse return null;
    return self.archetypes.items()[arch_index].getComponentAs(T, entity);
}

pub fn getComponentConst(self: *Self, comptime T: type, entity: Entity) ?*const T {
    return self.getComponent(T, entity);
}

/// Ensure `hash` is registered and return its component bit.
fn registerComponentType(self: *Self, hash: u64, size: usize) !u128 {
    if (!self.type_bit_index_set.containsValue(hash)) {
        try self.type_bit_index_set.set(self.next_component_bit_index, hash);
        try self.component_sizes.put(hash, size);
        self.next_component_bit_index += 1;
    }
    const bit_index = self.type_bit_index_set.getKeyByValue(hash).?;
    return @as(u128, 1) << @intCast(bit_index);
}

/// Return the component bit for an already-registered hash, or null.
inline fn componentBit(self: *Self, hash: u64) ?u128 {
    const bit_index = self.type_bit_index_set.getKeyByValue(hash) orelse return null;
    return @as(u128, 1) << @intCast(bit_index);
}

/// Return the index of the archetype with this exact mask, creating it if needed.
/// May append to `self.archetypes`; any *Archetype pointers obtained before
/// this call must be re-derived from indices after it returns.
fn findOrCreateArchetype(self: *Self, mask: u128) !usize {
    if (self.archetype_lookup.get(mask)) |idx| return idx;

    var hashes = core.List(u64).init(self.allocator);
    defer hashes.deinit();
    var sizes = core.List(usize).init(self.allocator);
    defer sizes.deinit();

    var bit: u7 = 0;
    while (bit < self.next_component_bit_index) : (bit += 1) {
        const shifted: u128 = @as(u128, 1) << bit;
        if (mask & shifted == 0) continue;

        const hash = self.type_bit_index_set.get(bit) orelse return error.UnknownComponentType;
        const size = self.component_sizes.get(hash) orelse return error.UnknownComponentSize;
        try hashes.append(hash);
        try sizes.append(size);
    }

    const index = self.archetypes.len();
    const new_arch = try Archetype.init(self.allocator, mask, hashes.items(), sizes.items());
    try self.archetypes.append(new_arch);
    errdefer {
        var a = self.archetypes.pop().?;
        a.deinit();
    }

    try self.archetype_lookup.put(mask, index);

    return index;
}

/// A (hash, size, opaque-data-pointer) triple used by insertEntityDirect.
const ComponentEntry = struct {
    hash: u64,
    size: usize,
    data: *const anyopaque,
};

/// Insert a brand-new entity into its final archetype in a single step.
///
/// This is the hot path for make_entity: instead of migrating through N
/// intermediate archetypes (one per addComponent call), we register all
/// component types, compute the final mask, find-or-create the target
/// archetype once, then call arch.addEntity with all data pointers arranged
/// in column order.  N archetype migrations → 1.
fn insertEntityDirect(self: *Self, entity: Entity, components: []const ComponentEntry) !void {
    var final_mask: u128 = 0;
    for (components) |c| {
        final_mask |= try self.registerComponentType(c.hash, c.size);
    }

    const arch_idx = try self.findOrCreateArchetype(final_mask);

    var ptrs: [128]*const anyopaque = undefined;
    var n: usize = 0;

    var bit: u7 = 0;
    while (bit < self.next_component_bit_index) : (bit += 1) {
        const shifted: u128 = @as(u128, 1) << bit;
        if (final_mask & shifted == 0) continue;

        const hash = self.type_bit_index_set.get(bit) orelse return error.UnknownComponentType;

        const ptr = for (components) |c| {
            if (c.hash == hash) break c.data;
        } else return error.MissingComponentData;

        ptrs[n] = ptr;
        n += 1;
    }

    try self.archetypes.items()[arch_idx].addEntity(entity, ptrs[0..n]);
    try self.entity_to_archetype.set(entity, arch_idx);
}

/// Add or overwrite a single component on an entity.
/// Moves the entity to a new archetype when its mask changes.
fn addComponent(
    self: *Self,
    entity: Entity,
    hash: u64,
    size: usize,
    data: *const anyopaque,
) !void {
    const component_bit = try self.registerComponentType(hash, size);

    const old_arch_index = self.entity_to_archetype.get(entity);
    const old_mask: u128 = if (old_arch_index) |idx|
        self.archetypes.items()[idx].mask
    else
        0;

    if (old_mask & component_bit != 0) {
        self.archetypes.items()[old_arch_index.?].setComponent(entity, hash, data);
        return;
    }

    const new_mask = old_mask | component_bit;

    const dst_idx = try self.findOrCreateArchetype(new_mask);

    if (old_arch_index) |src_idx| {
        try self.archetypes.items()[dst_idx].moveEntityFrom(
            entity,
            &self.archetypes.items()[src_idx],
            &.{.{ .hash = hash, .data = data }},
        );
        _ = self.archetypes.items()[src_idx].removeEntity(entity);
    } else {
        try self.archetypes.items()[dst_idx].addEntity(entity, &.{data});
    }

    try self.entity_to_archetype.set(entity, dst_idx);
}

/// Remove a single component from an entity.
/// Moves the entity to the subset archetype; if the entity ends up with no
/// components it is simply removed from its current archetype.
fn removeComponent(self: *Self, entity: Entity, hash: u64) !void {
    const arch_index = self.entity_to_archetype.get(entity) orelse return;
    const bit = self.componentBit(hash) orelse return;

    const old_mask = self.archetypes.items()[arch_index].mask;
    if (old_mask & bit == 0) return; // entity doesn't have this component

    const new_mask = old_mask & ~bit;

    if (new_mask == 0) {
        _ = self.archetypes.items()[arch_index].removeEntity(entity);
        self.entity_to_archetype.removeFast(entity);
        return;
    }

    const dst_idx = try self.findOrCreateArchetype(new_mask);
    const src_idx = arch_index;

    try self.archetypes.items()[dst_idx].moveEntityFrom(
        entity,
        &self.archetypes.items()[src_idx],
        &.{}, // no new components needed — we are only removing one
    );
    _ = self.archetypes.items()[src_idx].removeEntity(entity);

    try self.entity_to_archetype.set(entity, dst_idx);
}

/// Destroy an entity: remove it from its archetype and return its ID to the pool.
fn removeEntity(self: *Self, entity: Entity) void {
    if (!self.isEntityAlive(entity)) return;

    if (self.entity_to_archetype.get(entity)) |arch_index| {
        _ = self.archetypes.items()[arch_index].removeEntity(entity);
        self.entity_to_archetype.removeFast(entity);
    }

    self.available_entity_ids.append(entity) catch {};
}

fn addSystem(self: *Self, stage: Stage, system: System) !void {
    const at = core.types.coerceTo(usize, stage).?;

    if (!self.systems.contains(at))
        try self.systems.set(at, StageInfo.init(self.allocator, self));

    const info = self.systems.getPtr(at) orelse return;
    try info.addSystem(system);
}

fn removeSystem(self: *Self, stage: Stage, system: System) void {
    const at = core.types.coerceTo(usize, stage).?;
    const info = self.systems.getPtr(at) orelse return;
    info.removeSystem(system.id);
}

pub fn runStage(self: *Self, stage: Stage) !void {
    self.mutex.lock();
    defer {
        self.mutex.unlock();
        self.flushCommandBuffer() catch |err|
            std.log.err("applyCommandBuffer failed: {any}", .{err});
    }

    const at = core.types.coerceTo(usize, stage).?;
    const stage_info = self.systems.getPtr(at) orelse return;
    const batches = stage_info.batches.items();
    if (batches.len == 0) return;

    if (batches.len == 1) {
        self.executeBatch(batches[0].items());
        return;
    }

    var threads = self.allocator.alloc(std.Thread, batches.len - 1) catch {
        for (batches) |batch| {
            self.executeBatch(batch.items());
        }
        return;
    };
    defer self.allocator.free(threads);

    var spawned_count: usize = 0;
    for (batches[1..]) |batch| {
        if (std.Thread.spawn(.{}, executeBatch, .{ self, batch.items() })) |t| {
            threads[spawned_count] = t;
            spawned_count += 1;
        } else |_| {
            self.executeBatch(batch.items());
        }
    }

    self.executeBatch(batches[0].items());

    for (threads[0..spawned_count]) |t| {
        t.join();
    }
}

/// Called from the thread pool — one invocation per batch.
/// Systems within a batch are sequential; batches run in parallel.
///
/// The key difference from the sparse-set world: instead of scatter-gathering
/// individual entity pointers we pass each matching archetype's dense column
/// buffers directly to the system callback.  The inner loop is just a mask
/// test and a handful of pointer reads.
fn executeBatch(self: *Self, systems: []const System) void {
    var col_ptrs: [128][*]u8 = undefined;

    for (systems) |system| {
        var resolved = system;
        if (!resolved.hasMasks()) {
            resolved.bit_mask = StageInfo.generateComponentMask(self, resolved.hashes);
            resolved.write_mask = StageInfo.generateComponentMask(self, resolved.write_hashes);
            resolved.read_mask = StageInfo.generateComponentMask(self, resolved.read_hashes);
        }
        if (!resolved.hasMasks()) continue;

        const group_mask = resolved.bit_mask orelse continue;
        const n_hashes = resolved.hashes.len;

        for (self.archetypes.items()) |*arch| {
            if (arch.isEmpty()) continue;
            if (!arch.matchesMask(group_mask)) continue;

            if (!arch.fillColumnPtrs(resolved.hashes, col_ptrs[0..n_hashes])) continue;

            resolved.callback(arch.len(), &col_ptrs) catch |err|
                std.log.err("system '{s}' failed: {any}", .{ resolved.name, err });
        }
    }
}

pub fn flushCommandBuffer(self: *Self) !void {
    defer {
        for (self.command_buffer.commands.items()) |cmd| {
            switch (cmd) {
                .make_entity => |arr| self.command_buffer.allocator.free(arr),
                else => {},
            }
        }
        self.command_buffer.reset();
    }

    for (self.command_buffer.commands.items()) |cmd| {
        switch (cmd) {
            .make_entity => |descriptors| {
                const entity = try self.newEntity();

                var entries: [129]ComponentEntry = undefined;
                var ctx = ecs.Context{ .world = self, .entity = entity };
                entries[0] = .{
                    .hash = comptime core.type_erasure.typeToHash(ecs.Context),
                    .size = core.type_erasure.alignedSize(ecs.Context),
                    .data = &ctx,
                };

                for (descriptors, 1..) |desc, i| {
                    entries[i] = .{
                        .hash = desc.type_hash,
                        .size = desc.data_size,
                        .data = self.command_buffer.data.items()[desc.data_offset..].ptr,
                    };
                }

                try self.insertEntityDirect(entity, entries[0 .. descriptors.len + 1]);
            },
            .add_component => |info| {
                const start = info.data_offset;
                const end = info.data_offset + info.data_size;
                try self.addComponent(
                    info.entity,
                    info.type_hash,
                    info.data_size,
                    self.command_buffer.data.items()[start..end].ptr,
                );
            },
            .add_system => |info| try self.addSystem(info.stage, info.system),
            .remove_entity => |entity| self.removeEntity(entity),
            .remove_component => |data| try self.removeComponent(data.entity, data.type_hash),
            .remove_system => |info| self.removeSystem(info.stage, info.system),
        }
    }
}
