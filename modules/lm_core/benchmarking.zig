const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("root.zig");

pub const Options = struct {
    logger: *std.fs.File.Writer,
    allocator: Allocator,
};

pub fn measure(comptime triaL_times: comptime_int, comptime fn_name: []const u8, comptime func: anytype, args: anytype, options: Options) !void {
    const T = @TypeOf(func);

    const args_str = try std.fmt.allocPrint(options.allocator, "{any}", .{args});
    defer options.allocator.free(args_str);

    core.comptimeAssert(@typeInfo(T) == .@"fn", "func must be a function");

    const info = @typeInfo(T).@"fn";

    var runtimes = core.List(f128).init(options.allocator);
    defer runtimes.deinit();

    var worst_runtime: f128 = -1;
    var best_runtime: f128 = -1;
    var avg_runtime: f128 = 0;

    const total_start_time = std.time.nanoTimestamp();

    for (0..triaL_times) |_| {
        const start_time = std.time.nanoTimestamp();

        if (info.return_type == void) {
            @call(.auto, func, args);
        } else {
            try @call(.auto, func, args);
        }

        const end_time = std.time.nanoTimestamp();
        const run_time = (core.coerceTo(f128, end_time).? - core.coerceTo(f128, start_time).?) / core.coerceTo(f128, std.time.ns_per_s).?;

        if (worst_runtime == -1 or worst_runtime < run_time) worst_runtime = run_time;
        if (best_runtime == -1 or best_runtime > run_time) best_runtime = run_time;
        try runtimes.append(run_time);
    }

    const total_end_time = std.time.nanoTimestamp();
    const total_run_time = (core.coerceTo(f128, total_end_time).? - core.coerceTo(f128, total_start_time).?) / core.coerceTo(f128, std.time.ns_per_s).?;

    var sum: f128 = 0;
    for (runtimes.items()) |time| {
        sum += time;
    }
    avg_runtime = sum / triaL_times;

    try options.logger.interface.print(
        "\n" ++
            \\ -----[BENCH SUMMARY]-----
            \\ fn: {s}
            \\ args: {s}
            \\ runtimes:
            \\ best: {d:.9} 
            \\ worst: {d:.9} 
            \\ avg: {d:.9} 
            \\ total: {d:.9} 
            \\ -----[BENCH SUMMARY]-----
        ++ "\n",
        .{ fn_name, args_str, best_runtime, worst_runtime, avg_runtime, total_run_time },
    );
}
