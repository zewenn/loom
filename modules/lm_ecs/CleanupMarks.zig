const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");
const ecs = @import("root.zig");

const System = ecs.System;
const Stage = ecs.Stage;
const Entity = ecs.Entity;

const Self = @This();

entities: core.List(Entity),
components: core.types.SparseSet(u64),
systems: core.List(core.types.KeyValuePair(Stage, u64)),

allocator: Allocator,

pub fn init(allocator: Allocator) Self {
    return Self{
        .allocator = allocator,
        .components = .init(allocator),
        .entities = .init(allocator),
        .systems = .init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.components.deinit();
    self.entities.deinit();
    self.systems.deinit();

    self.* = undefined;
}

pub fn reset(self: *Self) void {
    self.components.deinit();
    self.components = .init(self.allocator);

    self.entities.clearAndFree();
    self.systems.clearAndFree();
}
