const std = @import("std");
const builtin = @import("builtin");

const benchmarking = @import("lm_benchmarking");
const ecs_benchmark = @import("lm_ecs/root.zig");

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer if (builtin.mode == .debug) {
        _ = debug_allocator.deinit();
    };

    const allocator = if (builtin.mode == .debug)
        debug_allocator.allocator()
    else
        std.heap.smp_allocator;

    var threaded_io = std.Io.Threaded.init_single_threaded;
    const io = threaded_io.io();

    var stdout_buffer: [4096]u8 = @splat(0);
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);

    const options: benchmarking.Options = .{
        .logger = &stdout_writer.interface,
        .allocator = allocator,
        .warmup_count = 5,
    };

    try ecs_benchmark.runBenchmarks(options);
}
