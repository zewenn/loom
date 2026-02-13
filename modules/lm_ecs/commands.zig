const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");
const ecs = @import("root.zig");

const Stage = ecs.Stage;
const System = ecs.System;
const Entity = ecs.Entity;

const Command = union(enum) {
    add_component: struct {
        entity: Entity,
        type_hash: u64,
        data_offset: usize, // Index into the byte buffer
        data_size: usize,
    },
    add_system: struct { stage: Stage, system: System },

    remove_entity: Entity,
    remove_component: struct { entity: Entity, type_hash: u64 },
    remove_system: struct { stage: Stage, system: System },
};

pub const CommandBuffer = struct {
    const Self = @This();

    mutex: std.Thread.Mutex,
    commands: core.List(Command),
    data: core.List(u8), // Raw component data storage
    allocator: Allocator,

    pub fn init(allocator: Allocator) CommandBuffer {
        return .{
            .mutex = .{},
            .commands = .init(allocator),
            .data = .init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CommandBuffer) void {
        self.commands.deinit();
        self.data.deinit();

        self.* = undefined;
    }

    pub fn addComponent(self: *CommandBuffer, entity: Entity, component: anytype) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const T = @TypeOf(component);
        const hash = comptime core.type_erasure.typeToHash(T);
        const size = @sizeOf(T);

        const offset = self.data.len();
        try self.data.appendSlice(std.mem.asBytes(&component));

        try self.commands.append(.{
            .add_component = .{
                .entity = entity,
                .type_hash = hash,
                .data_offset = offset,
                .data_size = size,
            },
        });
    }

    pub fn addComponents(self: *CommandBuffer, entity: Entity, components: anytype) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (!core.types.isTuple(components)) @compileError("components must be a tuple");

        inline for (components) |component| {
            const T = @TypeOf(component);
            const hash = comptime core.type_erasure.typeToHash(T);
            const size = @sizeOf(T);

            const offset = self.data.len();
            try self.data.appendSlice(std.mem.asBytes(&component));

            try self.commands.append(.{
                .add_component = .{
                    .entity = entity,
                    .type_hash = hash,
                    .data_offset = offset,
                    .data_size = size,
                },
            });
        }
    }

    pub fn addSystem(self: *Self, stage: Stage, comptime func: anytype) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.commands.append(.{
            .add_system = .{
                .stage = stage,
                .system = .init(func),
            },
        });
    }

    pub fn removeEntity(self: *Self, entity: Entity) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.commands.append(.{ .remove_entity = entity });
    }

    pub fn removeComponent(self: *Self, entity: Entity, comptime T: type) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.commands.append(.{
            .remove_component = .{
                .entity = entity,
                .type_hash = comptime core.type_erasure.typeToHash(T),
            },
        });
    }

    pub fn removeSystem(self: *Self, stage: Stage, comptime func: anytype) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.commands.append(.{
            .remove_system = .{
                .stage = stage,
                .system = .init(func),
            },
        });
    }

    pub fn reset(self: *CommandBuffer) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.commands.clearRetainingCapacity();
        self.data.clearRetainingCapacity();
    }
};
