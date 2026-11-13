const std = @import("std");
const Allocator = std.mem.Allocator;

const benchmarking = @import("lm_benchmarking");
const ecs = @import("lm_ecs");
const types = @import("lm_types");

const MEASURED_TRIAL_COUNT = 20;

const ENTITY_COUNTS = [_]usize{
    1,
    64,
    1_024,
    16_384,
    65_536,
};

const Position = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
};

const Velocity = struct {
    x: f32 = 1.0,
    y: f32 = 1.0,
};

const Data = struct {
    value: f64 = 0.0,
    padding: [56]u8 = @splat(0),
};

const Health = struct {
    health_points: f32 = 100.0,
    maximum_health_points: f32 = 100.0,
    alive: bool = true,
};

const Damage = struct {
    damage: f32 = 10.0,
};

const Sprite = struct {
    character: u8 = '@',
};

const RenderTarget = struct {
    var buffer: [8192]u8 = @splat(' ');
    var cursor: usize = 0;

    fn blit(character: u8) void {
        buffer[cursor % buffer.len] = character;
        cursor +%= 1;
    }
};

fn movementSystem(positions: []Position, velocities: []const Velocity) !void {
    for (positions, velocities) |*position, velocity| {
        position.x += velocity.x;
        position.y += velocity.y;
    }
}

fn dataSystem(data_components: []Data) !void {
    for (data_components) |*data| {
        data.value = data.value * 1.000_01 + 0.000_1;
    }
}

fn moreComplexSystem(
    positions: []Position,
    velocities: []Velocity,
    data_components: []Data,
) !void {
    for (positions, velocities, data_components) |*position, *velocity, *data| {
        data.value += @as(f64, position.x + position.y);
        velocity.x = @floatCast(@sin(@as(f64, velocity.x)) * 0.001 * data.value);
        velocity.y = @floatCast(@cos(@as(f64, velocity.y)) * 0.001 * data.value);
        position.x += velocity.x;
        position.y += velocity.y;
    }
}

fn healthSystem(health_components: []Health) !void {
    for (health_components) |*health| {
        if (health.health_points <= 0.0) {
            health.alive = false;
            continue;
        }
        health.health_points = @min(health.health_points + 1.0, health.maximum_health_points);
    }
}

fn damageSystem(health_components: []Health, damage_components: []const Damage) !void {
    for (health_components, damage_components) |*health, damage| {
        if (health.alive) health.health_points -= damage.damage;
    }
}

fn spriteSystem(sprites: []Sprite, health_components: []const Health) !void {
    for (sprites, health_components) |*sprite, health| {
        sprite.character = if (health.alive) '@' else 'X';
    }
}

fn renderSystem(sprites: []const Sprite) !void {
    for (sprites) |sprite| {
        RenderTarget.blit(sprite.character);
    }
}

const ArchetypeLayout = enum {
    homogeneous,
    mixed,
};

const SystemSet = enum {
    two_systems,
    seven_systems,
};

const Simulation = struct {
    var allocator: Allocator = undefined;
    var world: ecs.World = undefined;
    var entities: types.List(ecs.Entity) = undefined;
    var entity_count: usize = 0;

    fn beforeCreateTrial() !void {
        world = ecs.World.init(allocator);
    }

    fn afterCreateTrial() !void {
        world.deinit();
    }

    fn beforeDestroyTrial() !void {
        world = ecs.World.init(allocator);
        errdefer world.deinit();

        entities = types.List(ecs.Entity).init(allocator);
        errdefer entities.deinit();

        try populateBasicEntities(entity_count, false);
        try collectWorldEntities();
    }

    fn afterDestroyTrial() !void {
        entities.deinit();
        world.deinit();
    }

    fn initWithEntities(
        benchmark_allocator: Allocator,
        target_entity_count: usize,
        include_half_data: bool,
    ) !void {
        allocator = benchmark_allocator;
        entity_count = target_entity_count;
        world = ecs.World.init(benchmark_allocator);
        errdefer world.deinit();

        entities = types.List(ecs.Entity).init(benchmark_allocator);
        errdefer entities.deinit();

        try populateBasicEntities(target_entity_count, include_half_data);
        try collectWorldEntities();
    }

    fn deinitWithEntities() void {
        entities.deinit();
        world.deinit();
    }

    fn initWithSystems(
        benchmark_allocator: Allocator,
        target_entity_count: usize,
        system_set: SystemSet,
        layout: ArchetypeLayout,
    ) !void {
        allocator = benchmark_allocator;
        entity_count = target_entity_count;
        world = ecs.World.init(benchmark_allocator);
        errdefer world.deinit();

        try registerSystems(system_set);
        try populateStageEntities(target_entity_count, layout);
    }

    fn deinitWorld() void {
        world.deinit();
    }

    fn collectWorldEntities() !void {
        for (world.archetypes.items()) |archetype| {
            try entities.appendSlice(archetype.entities.items());
        }
    }

    fn makeBasicEntity(entity_index: usize, include_half_data: bool) !void {
        if (include_half_data and entity_index % 2 == 0) {
            try world.command_buffer.makeEntity(.{
                Position{ .x = 1.0, .y = 2.0 },
                Velocity{ .x = 0.5, .y = 0.5 },
                Data{ .value = @floatFromInt(entity_index) },
            });
            return;
        }
        try world.command_buffer.makeEntity(.{
            Position{ .x = 1.0, .y = 2.0 },
            Velocity{ .x = 0.5, .y = 0.5 },
        });
    }

    fn populateBasicEntities(target_entity_count: usize, include_half_data: bool) !void {
        for (0..target_entity_count) |entity_index| {
            try makeBasicEntity(entity_index, include_half_data);
        }
        try world.flushCommandBuffer();
    }

    fn registerSystems(system_set: SystemSet) !void {
        try world.command_buffer.addSystem(.update, movementSystem);
        try world.command_buffer.addSystem(.update, dataSystem);
        if (system_set == .two_systems) {
            try world.flushCommandBuffer();
            return;
        }

        try world.command_buffer.addSystem(.update, moreComplexSystem);
        try world.command_buffer.addSystem(.update, healthSystem);
        try world.command_buffer.addSystem(.update, damageSystem);
        try world.command_buffer.addSystem(.update, spriteSystem);
        try world.command_buffer.addSystem(.update, renderSystem);
        try world.flushCommandBuffer();
    }

    fn makeMixedEntity(entity_index: usize) !void {
        switch (entity_index % 4) {
            0 => try world.command_buffer.makeEntity(.{
                Position{}, Velocity{}, Data{}, Health{}, Damage{}, Sprite{},
            }),
            1 => try world.command_buffer.makeEntity(.{
                Position{}, Velocity{}, Data{}, Health{},
            }),
            2 => try world.command_buffer.makeEntity(.{
                Position{}, Velocity{},
            }),
            else => try world.command_buffer.makeEntity(.{
                Health{}, Damage{}, Sprite{},
            }),
        }
    }

    fn makeHomogeneousEntity(entity_index: usize) !void {
        try world.command_buffer.makeEntity(.{
            Position{ .x = @floatFromInt(entity_index), .y = 0.0 },
            Velocity{ .x = 1.0, .y = 1.0 },
            Data{ .value = @floatFromInt(entity_index) },
            Health{},
            Damage{},
            Sprite{},
        });
    }

    fn populateStageEntities(target_entity_count: usize, layout: ArchetypeLayout) !void {
        for (0..target_entity_count) |entity_index| {
            if (layout == .mixed) {
                try makeMixedEntity(entity_index);
                continue;
            }
            try makeHomogeneousEntity(entity_index);
        }
        try world.flushCommandBuffer();
    }

    fn createEntities(target_entity_count: usize) !void {
        for (0..target_entity_count) |_| {
            try world.command_buffer.makeEntity(.{ Position{}, Velocity{} });
        }
        try world.flushCommandBuffer();
    }

    fn destroyEntities(target_entity_count: usize) !void {
        _ = target_entity_count;
        for (entities.items()) |entity| {
            try world.command_buffer.removeEntity(entity);
        }
        try world.flushCommandBuffer();
    }

    fn unpackOneComponent(target_entity_count: usize) f32 {
        _ = target_entity_count;
        var sum: f32 = 0;
        for (entities.items()) |entity| {
            const position = world.getComponent(Position, entity) orelse continue;
            sum += position.x;
        }
        return sum;
    }

    fn unpackTwoComponents(target_entity_count: usize) f32 {
        _ = target_entity_count;
        var sum: f32 = 0;
        for (entities.items()) |entity| {
            const position = world.getComponent(Position, entity) orelse continue;
            const velocity = world.getComponentConst(Velocity, entity) orelse continue;
            sum += position.x + velocity.x;
        }
        return sum;
    }

    fn unpackThreeComponents(target_entity_count: usize) f64 {
        _ = target_entity_count;
        var sum: f64 = 0;
        for (entities.items()) |entity| {
            const position = world.getComponent(Position, entity) orelse continue;
            const velocity = world.getComponentConst(Velocity, entity) orelse continue;
            sum += @as(f64, position.x + velocity.x);
            if (world.getComponent(Data, entity)) |data| sum += data.value;
        }
        return sum;
    }

    fn removeAndAddPosition(target_entity_count: usize) !void {
        _ = target_entity_count;
        for (entities.items()) |entity| {
            try world.command_buffer.removeComponent(entity, Position);
        }
        try world.flushCommandBuffer();

        for (entities.items()) |entity| {
            try world.command_buffer.addComponent(entity, Position{});
        }
        try world.flushCommandBuffer();
    }

    fn runUpdateStage(target_entity_count: usize) !void {
        _ = target_entity_count;
        try world.runStage(.update);
    }
};

fn runCreateBenchmarks(base_options: benchmarking.Options) !void {
    const options = base_options.withHooks(Simulation.beforeCreateTrial, Simulation.afterCreateTrial);
    Simulation.allocator = options.allocator;

    for (ENTITY_COUNTS) |entity_count| {
        Simulation.entity_count = entity_count;
        try benchmarking.measure(
            MEASURED_TRIAL_COUNT,
            "create entities (Position + Velocity)",
            Simulation.createEntities,
            .{entity_count},
            options,
        );
    }
}

fn runDestroyBenchmarks(base_options: benchmarking.Options) !void {
    const options = base_options.withHooks(Simulation.beforeDestroyTrial, Simulation.afterDestroyTrial);
    Simulation.allocator = options.allocator;

    for (ENTITY_COUNTS) |entity_count| {
        Simulation.entity_count = entity_count;
        try benchmarking.measure(
            MEASURED_TRIAL_COUNT,
            "destroy entities (Position + Velocity)",
            Simulation.destroyEntities,
            .{entity_count},
            options,
        );
    }
}

fn runEntityOperationBenchmark(
    comptime benchmark_name: []const u8,
    comptime callback: anytype,
    include_half_data: bool,
    options: benchmarking.Options,
) !void {
    for (ENTITY_COUNTS) |entity_count| {
        try Simulation.initWithEntities(options.allocator, entity_count, include_half_data);
        defer Simulation.deinitWithEntities();

        try benchmarking.measure(
            MEASURED_TRIAL_COUNT,
            benchmark_name,
            callback,
            .{entity_count},
            options,
        );
    }
}

fn runStageBenchmark(
    comptime benchmark_name: []const u8,
    system_set: SystemSet,
    layout: ArchetypeLayout,
    options: benchmarking.Options,
) !void {
    for (ENTITY_COUNTS) |entity_count| {
        try Simulation.initWithSystems(options.allocator, entity_count, system_set, layout);
        defer Simulation.deinitWorld();

        try benchmarking.measure(
            MEASURED_TRIAL_COUNT,
            benchmark_name,
            Simulation.runUpdateStage,
            .{entity_count},
            options,
        );
    }
}

/// Run all `lm_ecs` benchmarks via `lm_benchmarking`.
pub fn runBenchmarks(options: benchmarking.Options) !void {
    try runCreateBenchmarks(options);
    try runDestroyBenchmarks(options);
    try runEntityOperationBenchmark("unpack one (Position)", Simulation.unpackOneComponent, false, options);
    try runEntityOperationBenchmark("unpack two (Position + const Velocity)", Simulation.unpackTwoComponents, false, options);
    try runEntityOperationBenchmark("unpack three (50% have Data)", Simulation.unpackThreeComponents, true, options);
    try runEntityOperationBenchmark("remove and add Position", Simulation.removeAndAddPosition, false, options);
    try runStageBenchmark("2-system update (homogeneous)", .two_systems, .homogeneous, options);
    try runStageBenchmark("2-system update (mixed)", .two_systems, .mixed, options);
    try runStageBenchmark("7-system update (homogeneous)", .seven_systems, .homogeneous, options);
    try runStageBenchmark("7-system update (mixed)", .seven_systems, .mixed, options);
}
