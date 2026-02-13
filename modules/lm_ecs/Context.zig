const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");
const ecs = @import("root.zig");

const Self = @This();

world: *ecs.World,
entity: ecs.Entity,

// TODO: fix this and move to the command buffer
// pub inline fn newEntity(self: *Self) !ecs.Entity {
//     return try self.world.newEntity();
// }

// /// Creates an entity, but the component's will only be added after the stage has run.
// pub fn makeEntity(self: *Self, components: anytype) !ecs.Entity {
//     const entity = try self.world.newEntity();

//     try self.world.command_buffer.addComponents(entity, components);

//     return entity;
// }

pub inline fn isEntityAlive(self: *Self, entity: ecs.Entity) bool {
    return self.world.isEntityAlive(entity);
}

pub inline fn removeThisEntity(self: *Self) !void {
    try self.world.command_buffer.removeEntity(self.entity);
}

pub inline fn removeEntity(self: *Self, entity: ecs.Entity) !void {
    try self.world.command_buffer.removeEntity(entity);
}

pub inline fn addComponent(self: *Self, component: anytype) !void {
    try self.world.command_buffer.addComponent(self.entity, component);
}

pub inline fn addComponentTo(self: *Self, entity: ecs.Entity, component: anytype) !void {
    try self.world.command_buffer.addComponent(entity, component);
}

pub inline fn addComponents(self: *Self, components: anytype) !void {
    try self.world.command_buffer.addComponents(self.entity, components);
}

pub inline fn addComponentsTo(self: *Self, entity: ecs.Entity, components: anytype) !void {
    try self.world.command_buffer.addComponents(entity, components);
}

pub inline fn getComponent(self: *Self, comptime T: type) ?*T {
    return self.world.getComponent(T, self.entity);
}

pub inline fn getComponentFrom(self: *Self, entity: ecs.Entity, comptime T: type) ?*T {
    return self.world.getComponent(T, entity);
}

pub inline fn getComponentConst(self: *Self, comptime T: type) ?*const T {
    return self.world.getComponentConst(T, self.entity);
}

pub inline fn getComponentConstFrom(self: *Self, entity: ecs.Entity, comptime T: type) ?*T {
    return self.world.getComponentConst(T, entity);
}

pub inline fn removeComponent(self: *Self, comptime T: type) !void {
    try self.world.command_buffer.removeComponent(self.entity, T);
}

pub inline fn removeComponentFrom(self: *Self, entity: ecs.Entity, comptime T: type) !void {
    try self.world.command_buffer.removeComponent(entity, T);
}

pub inline fn addSystem(self: *Self, stage: ecs.Stage, comptime system: anytype) !void {
    try self.world.command_buffer.addSystem(stage, system);
}

pub inline fn removeSystem(self: *Self, stage: ecs.Stage, comptime system: anytype) !void {
    try self.world.command_buffer.removeSystem(stage, system);
}
