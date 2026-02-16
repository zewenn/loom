const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");
const ecs = @import("lm_ecs");

const sim1 = struct {
    pub const Position = struct {
        x: f32,
        y: f32,
    };

    pub const Velocity = struct {
        x: f32,
        y: f32,
    };

    pub const Data = struct {
        p: f32,
        d: u64,
        z: u128,
    };

    pub const Health = struct {
        current: f32,
        max: f32,
    };

    pub const Damage = struct {
        current: f32,
    };

    pub const Sprite = struct {
        data: []const u8,
    };

    fn movementSystem(position: *Position, velocity: *const Velocity) !void {
        position.x += velocity.x;
        position.y += velocity.y;
    }

    fn dataSystem(data: *Data) !void {
        data.d += 10;
        data.p += 20;
        data.z += 3000;
    }

    fn moreComplexSystem(data: *Data, velocity: *Velocity, health: *const Health) !void {
        data.d += 10;
        data.p *= health.max;

        velocity.x += data.p;
    }

    fn healthSystem(health: *Health) !void {
        health.current = @min(health.max, health.current + 1);
    }

    fn damageSystem(health: *Health, damage: *const Damage) !void {
        health.current -= damage.current;
    }

    fn spriteSytsem(sprite: *Sprite, health: *const Health) !void {
        if (health.current > 90) {
            sprite.data = ":D";
            return;
        }

        if (health.current > 50) {
            sprite.data = ":)";
            return;
        }

        if (health.current > 10) {
            sprite.data = ":(";
            return;
        }

        sprite.data = "x(";
    }

    pub var world: ecs.World = undefined;

    pub fn init(allocator: Allocator) !void {
        world = .init(allocator);

        const seed: u64 = 0;
        var xoshiro = std.Random.Xoshiro256.init(seed);
        var rand = xoshiro.random();

        for (0..500_000) |_| {
            const entity = try world.newEntity();
            try world.command_buffer.addComponents(entity, .{
                Position{
                    .x = rand.float(f32),
                    .y = rand.float(f32),
                },
                Velocity{
                    .x = rand.float(f32),
                    .y = rand.float(f32),
                },
                Data{
                    .p = rand.float(f32),
                    .d = rand.int(u64),
                    .z = rand.int(u64),
                },
                Health{
                    .current = 50,
                    .max = 100,
                },
                Damage{
                    .current = 50,
                },
                Sprite{
                    .data = "asdasda",
                },
            });
        }
        for (0..250_000) |_| {
            const entity = try world.newEntity();
            try world.command_buffer.addComponents(entity, .{
                Position{
                    .x = rand.float(f32),
                    .y = rand.float(f32),
                },
                Velocity{
                    .x = rand.float(f32),
                    .y = rand.float(f32),
                },
                Health{
                    .current = 50,
                    .max = 100,
                },
                Damage{
                    .current = 50,
                },
                Sprite{
                    .data = "asdasda",
                },
            });
        }
        for (0..250_000) |_| {
            const entity = try world.newEntity();
            try world.command_buffer.addComponents(entity, .{
                Position{
                    .x = rand.float(f32),
                    .y = rand.float(f32),
                },
                Velocity{
                    .x = rand.float(f32),
                    .y = rand.float(f32),
                },
                Health{
                    .current = 50,
                    .max = 100,
                },
                Damage{
                    .current = 50,
                },
            });
        }

        try world.command_buffer.addSystem(.init, movementSystem);
        try world.command_buffer.addSystem(.init, dataSystem);
        try world.command_buffer.addSystem(.init, moreComplexSystem);
        try world.command_buffer.addSystem(.init, healthSystem);
        try world.command_buffer.addSystem(.init, damageSystem);
        try world.command_buffer.addSystem(.init, spriteSytsem);

        try world.applyCommandBuffer();
    }

    pub fn deinit() void {
        world.deinit();
    }

    pub fn run1MilStage() !void {
        try world.runStage(.init);
    }
};

const sim15SystemsFor1MilEntities = struct {
    pub const TestComponent = struct {
        inner: u64 = 0,
    };
    const OtherTestComponent = struct {
        inner: u64 = 0,
    };

    fn testSystem(t_comp: *TestComponent) !void {
        t_comp.inner = 67;
    }

    fn testSystem2(t_comp: *TestComponent) !void {
        t_comp.inner = 42;
    }

    fn testSystem3(t_comp: *TestComponent) !void {
        t_comp.inner = 89;
    }

    fn testSystem4(t_comp: *TestComponent) !void {
        t_comp.inner = 89;
    }

    fn testSystem5(t_comp: *TestComponent) !void {
        t_comp.inner = 89;
    }

    fn otherTestSystem(t_comp: *OtherTestComponent) !void {
        t_comp.inner = 42;
    }

    fn otherTestSystem2(t_comp: *OtherTestComponent) !void {
        t_comp.inner = 42;
    }

    fn otherTestSystem3(t_comp: *OtherTestComponent) !void {
        t_comp.inner = 42;
    }

    fn otherTestSystem4(t_comp: *OtherTestComponent) !void {
        t_comp.inner = 42;
    }

    fn otherTestSystem5(t_comp: *OtherTestComponent) !void {
        t_comp.inner = 42;
    }

    fn combinedSystem(t_comp: *TestComponent, t_comp2: *const OtherTestComponent) !void {
        t_comp.inner = t_comp2.inner;
    }

    fn combinedSystem2(t_comp: *TestComponent, t_comp2: *const OtherTestComponent) !void {
        t_comp.inner = t_comp2.inner * 42;
    }

    fn combinedSystem3(t_comp: *TestComponent, t_comp2: *const OtherTestComponent) !void {
        t_comp.inner = t_comp2.inner * 67;
    }

    fn combinedSystem4(t_comp: *TestComponent, t_comp2: *const OtherTestComponent) !void {
        t_comp.inner = t_comp2.inner * 7;
    }

    fn combinedSystem5(t_comp: *TestComponent, t_comp2: *const OtherTestComponent) !void {
        t_comp.inner = t_comp2.inner * t_comp2.inner;
    }

    pub var world: ecs.World = undefined;

    pub fn init(allocator: Allocator) !void {
        world = .init(allocator);

        for (0..500_000) |_| {
            const entity = try world.newEntity();
            try world.command_buffer.addComponents(entity, .{
                TestComponent{},
            });
        }
        for (0..500_000) |_| {
            const entity = try world.newEntity();
            try world.command_buffer.addComponents(entity, .{
                OtherTestComponent{},
            });
        }
        try world.command_buffer.addSystem(.init, testSystem);
        try world.command_buffer.addSystem(.init, testSystem2);
        try world.command_buffer.addSystem(.init, testSystem3);
        try world.command_buffer.addSystem(.init, testSystem4);
        try world.command_buffer.addSystem(.init, testSystem5);

        try world.command_buffer.addSystem(.init, otherTestSystem);
        try world.command_buffer.addSystem(.init, otherTestSystem2);
        try world.command_buffer.addSystem(.init, otherTestSystem3);
        try world.command_buffer.addSystem(.init, otherTestSystem4);
        try world.command_buffer.addSystem(.init, otherTestSystem5);

        try world.command_buffer.addSystem(.init, combinedSystem);
        try world.command_buffer.addSystem(.init, combinedSystem2);
        try world.command_buffer.addSystem(.init, combinedSystem3);
        try world.command_buffer.addSystem(.init, combinedSystem4);
        try world.command_buffer.addSystem(.init, combinedSystem5);

        try world.runStage(.init);
    }

    pub fn deinit() void {
        world.deinit();
    }

    pub fn runStage() !void {
        try world.runStage(.init);
    }
};

pub fn testBench() u64 {
    return 100_000_000 % 23847;
}

pub fn runBenchmarks() !void {
    var buffer: [32]u8 = [_]u8{0} ** 32;
    var writer = std.fs.File.stdout().writer(&buffer);

    const config: core.benchmarking.Options = .{
        .allocator = std.heap.smp_allocator,
        .logger = &writer,
    };

    std.log.debug("asd", .{});

    try sim1.init(std.heap.smp_allocator);
    defer sim1.deinit();

    std.log.debug("asd", .{});

    // try sim15SystemsFor1MilEntities.init(std.heap.smp_allocator);
    // defer sim15SystemsFor1MilEntities.deinit();

    try core.benchmarking.measure(100, "Two million stage", sim1.run1MilStage, .{}, config);
    // try core.benchmarking.measure(10_000, "One million + 15 system stage", sim15SystemsFor1MilEntities.runStage, .{}, config);

}
