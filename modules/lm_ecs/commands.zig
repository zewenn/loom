const std = @import("std");
const Allocator = std.mem.Allocator;

const lm_types = @import("lm_types");
const ecs = @import("root.zig");

const Stage = ecs.Stage;
const System = ecs.System;
const Entity = ecs.Entity;

/// Serialized component metadata pointing into `CommandBuffer.component_payloads`.
pub const ComponentDescriptor = struct {
    type_hash: u64,
    byte_offset: usize,
    byte_size: usize,
};

/// Payload describing an entity-targeted component addition.
pub const AddComponentPayload = struct {
    entity: Entity,
    type_hash: u64,
    byte_offset: usize,
    byte_size: usize,
};

/// Deferred structural mutation queued during stage execution.
pub const Command = union(enum) {
    make_entity: []ComponentDescriptor,
    add_component: AddComponentPayload,
    add_system: struct { stage: Stage, system: System },

    remove_entity: Entity,
    remove_component: struct { entity: Entity, type_hash: u64 },
    remove_system: struct { stage: Stage, system: System },
};

const Mutex = struct {
    inner: std.Io.Mutex = .init,

    pub fn lock(self: *Mutex) void {
        std.Io.Threaded.mutexLock(&self.inner) catch unreachable;
    }

    pub fn unlock(self: *Mutex) void {
        std.Io.Threaded.mutexUnlock(&self.inner);
    }
};

/// Thread-safe queue of structural ECS mutations applied between stage executions.
pub const CommandBuffer = struct {
    const Self = @This();

    mutex: Mutex,
    commands: lm_types.List(Command),
    component_payloads: lm_types.List(u8),
    allocator: Allocator,

    /// Create an empty command buffer backed by `allocator`.
    pub fn init(allocator: Allocator) CommandBuffer {
        return .{
            .mutex = .{},
            .commands = .init(allocator),
            .component_payloads = .init(allocator),
            .allocator = allocator,
        };
    }

    /// Free all buffered commands, descriptors, and raw component payloads.
    pub fn deinit(self: *Self) void {
        self.releaseMakeEntityDescriptors();
        self.commands.deinit();
        self.component_payloads.deinit();

        self.* = undefined;
    }

    /// Queue creation of a new entity initialized with the given component tuple.
    pub fn makeEntity(self: *Self, components: anytype) !void {
        if (!lm_types.types.isTuple(components)) @compileError("components must be a tuple");

        self.mutex.lock();
        defer self.mutex.unlock();

        var descriptors = lm_types.List(ComponentDescriptor).init(self.allocator);
        defer descriptors.deinit();

        inline for (components) |component| {
            const descriptor = try self.appendComponentDescriptor(component);
            try descriptors.append(descriptor);
        }

        const owned_descriptors = try descriptors.toOwnedSlice();
        errdefer self.allocator.free(owned_descriptors);

        try self.commands.append(.{ .make_entity = owned_descriptors });
    }

    /// Queue adding or overwriting a single `component` on `entity`.
    pub fn addComponent(self: *Self, entity: Entity, component: anytype) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.appendAddComponentCommand(entity, component);
    }

    /// Queue adding or overwriting a tuple of `components` on `entity`.
    pub fn addComponents(self: *Self, entity: Entity, components: anytype) !void {
        if (!lm_types.types.isTuple(components)) @compileError("components must be a tuple");

        self.mutex.lock();
        defer self.mutex.unlock();

        inline for (components) |component| {
            try self.appendAddComponentCommand(entity, component);
        }
    }

    /// Queue registration of `system_function` in the given `stage`.
    pub fn addSystem(self: *Self, stage: Stage, comptime system_function: anytype) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.commands.append(.{
            .add_system = .{
                .stage = stage,
                .system = .init(system_function),
            },
        });
    }

    /// Queue destruction of `entity` and recycling of its entity identifier.
    pub fn removeEntity(self: *Self, entity: Entity) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.commands.append(.{ .remove_entity = entity });
    }

    /// Queue removal of `Component` from `entity`.
    pub fn removeComponent(self: *Self, entity: Entity, comptime Component: type) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.commands.append(.{
            .remove_component = .{
                .entity = entity,
                .type_hash = comptime lm_types.type_erasure.typeToHash(Component),
            },
        });
    }

    /// Queue removal of `system_function` from `stage`.
    pub fn removeSystem(self: *Self, stage: Stage, comptime system_function: anytype) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.commands.append(.{
            .remove_system = .{
                .stage = stage,
                .system = .init(system_function),
            },
        });
    }

    /// Clear all queued commands while retaining backing buffer capacity.
    pub fn reset(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.releaseMakeEntityDescriptors();
        self.commands.clearRetainingCapacity();
        self.component_payloads.clearRetainingCapacity();
    }

    fn appendAddComponentCommand(self: *Self, entity: Entity, component: anytype) !void {
        const descriptor = try self.appendComponentDescriptor(component);
        try self.commands.append(.{
            .add_component = .{
                .entity = entity,
                .type_hash = descriptor.type_hash,
                .byte_offset = descriptor.byte_offset,
                .byte_size = descriptor.byte_size,
            },
        });
    }

    fn appendComponentDescriptor(self: *Self, component: anytype) !ComponentDescriptor {
        const ComponentType: type = @TypeOf(component);
        const type_hash = comptime lm_types.type_erasure.typeToHash(ComponentType);
        const byte_size = @sizeOf(ComponentType);
        const byte_offset = self.component_payloads.len();

        try self.component_payloads.appendSlice(std.mem.asBytes(&component));

        return .{
            .type_hash = type_hash,
            .byte_offset = byte_offset,
            .byte_size = byte_size,
        };
    }

    fn releaseMakeEntityDescriptors(self: *Self) void {
        for (self.commands.items()) |command| {
            if (command == .make_entity) {
                self.allocator.free(command.make_entity);
            }
        }
    }
};
