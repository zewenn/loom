const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");
const ecs = @import("lm_ecs");

const simFor1MilEntities = struct {
    pub var outer: usize = 0;

    const TestComponent = struct {
        inner: u64 = 0,
    };
    const OtherTestComponent = struct {
        inner: u64 = 0,
    };

    fn testSystem(t_comp: *TestComponent) !void {
        t_comp.inner = 67;
        outer += 1;
    }

    fn otherTestSystem(t_comp: *OtherTestComponent) !void {
        t_comp.inner = 42;
    }

    var world: ecs.World = undefined;

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
        try world.command_buffer.addSystem(.init, otherTestSystem);
        try world.runStage(.init);
    }

    pub fn deinit() void {
        world.deinit();
    }

    pub fn run1MilStage() !void {
        try world.runStage(.init);
    }
};

pub fn testBench() u64 {
    return 100_000_000 % 23847;
}

pub fn runBenchmarks() !void {
    var buffer: [64]u8 = [_]u8{0} ** 64;
    const writer = std.debug.lockStderrWriter(&buffer);
    defer std.debug.unlockStderrWriter();

    const config: core.benchmarking.Options = .{
        .allocator = std.heap.smp_allocator,
        .logger = writer,
    };

    try simFor1MilEntities.init(std.heap.smp_allocator);
    defer simFor1MilEntities.deinit();

    try core.benchmarking.measure(simFor1MilEntities.run1MilStage, .{}, config);

    try writer.print("\n{d}\n", .{simFor1MilEntities.outer});
}
