const ecs = @import("root.zig");

const Self = @This();

/// Per-entity handle injected automatically as the first component of every entity,
/// allowing systems to enqueue deferred world mutations during stage execution.
world: *ecs.World,
entity: ecs.Entity,

/// Enqueue creation of a new entity with the given component tuple.
pub inline fn makeEntity(self: *Self, components: anytype) !void {
    try self.world.command_buffer.makeEntity(components);
}

/// Return true if `entity` is currently alive in the owning world.
pub inline fn isEntityAlive(self: *Self, entity: ecs.Entity) bool {
    return self.world.isEntityAlive(entity);
}

/// Enqueue destruction of the entity bound to this context.
pub inline fn removeThisEntity(self: *Self) !void {
    try self.world.command_buffer.removeEntity(self.entity);
}

/// Enqueue destruction of the specified `entity`.
pub inline fn removeEntity(self: *Self, entity: ecs.Entity) !void {
    try self.world.command_buffer.removeEntity(entity);
}

/// Enqueue adding or overwriting a single `component` on the bound entity.
pub inline fn addComponent(self: *Self, component: anytype) !void {
    try self.world.command_buffer.addComponent(self.entity, component);
}

/// Enqueue adding or overwriting a single `component` on `entity`.
pub inline fn addComponentTo(self: *Self, entity: ecs.Entity, component: anytype) !void {
    try self.world.command_buffer.addComponent(entity, component);
}

/// Enqueue adding or overwriting a tuple of `components` on the bound entity.
pub inline fn addComponents(self: *Self, components: anytype) !void {
    try self.world.command_buffer.addComponents(self.entity, components);
}

/// Enqueue adding or overwriting a tuple of `components` on `entity`.
pub inline fn addComponentsTo(self: *Self, entity: ecs.Entity, components: anytype) !void {
    try self.world.command_buffer.addComponents(entity, components);
}

/// Enqueue removal of `Component` from the bound entity.
pub inline fn removeComponent(self: *Self, comptime Component: type) !void {
    try self.world.command_buffer.removeComponent(self.entity, Component);
}

/// Enqueue removal of `Component` from `entity`.
pub inline fn removeComponentFrom(self: *Self, entity: ecs.Entity, comptime Component: type) !void {
    try self.world.command_buffer.removeComponent(entity, Component);
}

/// Enqueue registration of `system_function` in the given `stage`.
pub inline fn addSystem(self: *Self, stage: ecs.Stage, comptime system_function: anytype) !void {
    try self.world.command_buffer.addSystem(stage, system_function);
}

/// Enqueue removal of `system_function` from the given `stage`.
pub inline fn removeSystem(self: *Self, stage: ecs.Stage, comptime system_function: anytype) !void {
    try self.world.command_buffer.removeSystem(stage, system_function);
}
