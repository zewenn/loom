const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");
const ecs = @import("root.zig");
const System = ecs.System;

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

pub const StageInfo = struct {
    world: *ecs.World,
    max_hash_count: usize = 0,
    systems: core.List(System),
    batches: core.List(core.List(System)),
    batch_read_masks: core.List(u128),
    batch_write_masks: core.List(u128),

    allocator: Allocator,

    pub fn init(allocator: Allocator, world: *ecs.World) StageInfo {
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

    pub fn deinit(self: *StageInfo) void {
        for (self.batches.items()) |*list| list.deinit();
        self.batches.deinit();
        self.batch_read_masks.deinit();
        self.batch_write_masks.deinit();

        self.systems.deinit();

        self.* = undefined;
    }

    fn generateComponentMask(world: *ecs.World, hashes: []const u64) ?u128 {
        var current_bitmask: u128 = 0b0;

        for (hashes) |hash| {
            const bit_index = world.type_bit_index_set.getKeyByValue(hash) orelse return null;
            const shift = core.types.coerceTo(u7, bit_index) orelse return null;

            const base_mask: u128 = 0b1;
            const shifted = base_mask << shift;
            current_bitmask = current_bitmask | shifted;
        }

        return current_bitmask;
    }

    pub fn addSystem(self: *StageInfo, const_system: System) !void {
        var system = const_system;
        const world = self.world;

        if (!system.hasMasks()) {
            system.bit_mask = generateComponentMask(world, system.hashes);
            system.write_mask = generateComponentMask(world, system.write_hashes);
            system.read_mask = generateComponentMask(world, system.read_hashes);
        }

        if (!system.hasMasks()) return;

        if (self.max_hash_count < system.hashes.len) self.max_hash_count = system.hashes.len;

        try self.systems.append(system);
        errdefer _ = self.systems.pop();

        for (0..self.batches.len()) |batch_index| {
            const write_mask = self.batch_write_masks.items()[batch_index];
            const read_mask = self.batch_read_masks.items()[batch_index];

            if (!system.overlapsMasks(write_mask, read_mask)) continue;

            try self.batches.items()[batch_index].append(system);

            self.batch_write_masks.items()[batch_index] |= system.write_mask.?;
            self.batch_read_masks.items()[batch_index] |= system.read_mask.?;

            return;
        }

        try self.batches.append(.init(self.allocator));
        errdefer _ = self.batches.pop();

        try self.batch_write_masks.append(system.write_mask.?);
        errdefer _ = self.batch_write_masks.pop();

        try self.batch_read_masks.append(system.read_mask.?);
        errdefer _ = self.batch_read_masks.pop();

        const new = &self.batches.items()[self.batches.len() - 1];
        try new.append(system);
    }

    pub fn removeSystem(self: *StageInfo, id: u64) void {
        for (self.systems.items(), 0..) |sys, index| {
            if (sys.id != id) continue;

            _ = self.systems.swapRemove(index);
            break;
        }

        outer: for (self.batches.items(), 0..) |*batch, index| {
            for (batch.items(), 0..) |sys, b_index| {
                if (sys.id != id) continue;

                _ = batch.swapRemove(b_index);

                self.batch_write_masks.items()[index] ^= sys.write_mask.?;
                self.batch_read_masks.items()[index] ^= sys.read_mask.?;
                break :outer;
            }
        }
    }
};
