const std = @import("std");
const Allocator = std.mem.Allocator;

const lm_types = @import("lm_types");
const ecs = @import("root.zig");
const System = ecs.System;

/// Fixed lifecycle phases executed sequentially by a `World`.
pub const Stage = enum {
    init,
    load,
    pre_update,
    update,
    post_update,
    tick,
    draw,
    deinit,
};

/// Execution plan grouping non-conflicting systems into parallel batches for one stage.
pub const StageSchedule = struct {
    world: *ecs.World,
    max_hash_count: usize = 0,
    systems: lm_types.List(System),
    batches: lm_types.List(lm_types.List(System)),
    batch_read_masks: lm_types.List(u128),
    batch_write_masks: lm_types.List(u128),
    allocator: Allocator,

    /// Create an empty schedule bound to `world`.
    pub fn init(allocator: Allocator, world: *ecs.World) StageSchedule {
        return .{
            .allocator = allocator,
            .world = world,
            .max_hash_count = 0,
            .systems = .init(allocator),
            .batches = .init(allocator),
            .batch_read_masks = .init(allocator),
            .batch_write_masks = .init(allocator),
        };
    }

    /// Release all scheduled batches and system lists.
    pub fn deinit(self: *StageSchedule) void {
        for (self.batches.items()) |*batch| batch.deinit();
        self.batches.deinit();
        self.batch_read_masks.deinit();
        self.batch_write_masks.deinit();
        self.systems.deinit();

        self.* = undefined;
    }

    /// Compute the archetype bitmask matching all `component_hashes`, or null if any hash is unregistered.
    pub fn generateComponentMask(world: *ecs.World, component_hashes: []const u64) ?u128 {
        var bitmask: u128 = 0;

        for (component_hashes) |component_hash| {
            const bit_index = world.component_bit_indices.getKeyByValue(component_hash) orelse return null;
            const bit_shift = lm_types.types.coerceTo(u7, bit_index) orelse return null;

            bitmask |= @as(u128, 1) << bit_shift;
        }

        return bitmask;
    }

    /// Resolve system masks when possible and schedule the system into an overlapping or new batch.
    pub fn addSystem(self: *StageSchedule, requested_system: System) !void {
        var resolved_system = requested_system;
        if (!resolved_system.hasMasks()) {
            resolved_system.bit_mask = generateComponentMask(self.world, resolved_system.hashes);
            resolved_system.write_mask = generateComponentMask(self.world, resolved_system.write_hashes);
            resolved_system.read_mask = generateComponentMask(self.world, resolved_system.read_hashes);
        }

        if (self.max_hash_count < resolved_system.hashes.len) {
            self.max_hash_count = resolved_system.hashes.len;
        }

        try self.systems.append(resolved_system);
        errdefer _ = self.systems.pop();

        if (try self.tryAppendToConflictingBatch(resolved_system)) return;
        try self.appendNewBatch(resolved_system);
    }

    /// Unschedule the system matching `target_system_id` from the stage and its batch.
    pub fn removeSystem(self: *StageSchedule, target_system_id: u64) void {
        self.removeFromSystemList(target_system_id);
        self.removeFromBatches(target_system_id);
    }

    fn tryAppendToConflictingBatch(self: *StageSchedule, system: System) !bool {
        if (!system.hasMasks()) return false;

        for (self.batches.items(), 0..) |*batch, batch_index| {
            const batch_write_mask = self.batch_write_masks.items()[batch_index];
            const batch_read_mask = self.batch_read_masks.items()[batch_index];
            if (!system.overlapsMasks(batch_write_mask, batch_read_mask)) continue;

            try batch.append(system);
            self.batch_write_masks.items()[batch_index] |= system.write_mask.?;
            self.batch_read_masks.items()[batch_index] |= system.read_mask.?;
            return true;
        }

        return false;
    }

    fn appendNewBatch(self: *StageSchedule, system: System) !void {
        var new_batch = lm_types.List(System).init(self.allocator);
        errdefer new_batch.deinit();

        try new_batch.append(system);

        try self.batches.append(new_batch);
        errdefer _ = self.batches.pop();

        try self.batch_write_masks.append(system.write_mask orelse 0);
        errdefer _ = self.batch_write_masks.pop();

        try self.batch_read_masks.append(system.read_mask orelse 0);
    }

    fn removeFromSystemList(self: *StageSchedule, target_system_id: u64) void {
        for (self.systems.items(), 0..) |system, system_index| {
            if (system.id != target_system_id) continue;

            _ = self.systems.swapRemove(system_index);
            return;
        }
    }

    fn removeFromBatches(self: *StageSchedule, target_system_id: u64) void {
        for (self.batches.items(), 0..) |*batch, batch_index| {
            if (!removeSystemFromBatch(batch, target_system_id)) continue;

            self.recomputeBatchMasks(batch_index);
            return;
        }
    }

    fn removeSystemFromBatch(batch: *lm_types.List(System), target_system_id: u64) bool {
        for (batch.items(), 0..) |system, entry_index| {
            if (system.id != target_system_id) continue;

            _ = batch.swapRemove(entry_index);
            return true;
        }
        return false;
    }

    fn recomputeBatchMasks(self: *StageSchedule, batch_index: usize) void {
        var write_mask: u128 = 0;
        var read_mask: u128 = 0;

        for (self.batches.items()[batch_index].items()) |system| {
            write_mask |= system.write_mask orelse 0;
            read_mask |= system.read_mask orelse 0;
        }

        self.batch_write_masks.items()[batch_index] = write_mask;
        self.batch_read_masks.items()[batch_index] = read_mask;
    }
};
