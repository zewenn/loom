const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("root.zig");

pub const Options = struct {
    logger: *std.io.Writer,
    allocator: Allocator,
};

pub fn measure(comptime func: anytype, args: anytype, options: Options) !void {
    const T = @TypeOf(func);

    const fn_name = @typeName(T);

    const args_str = try std.fmt.allocPrint(options.allocator, "{any}", .{args});
    defer options.allocator.free(args_str);

    core.comptimeAssert(@typeInfo(T) == .@"fn", "func must be a function");

    const info = @typeInfo(T).@"fn";

    const start_time = std.time.nanoTimestamp();

    if (info.return_type == void) {
        @call(.auto, func, args);
    } else {
        try @call(.auto, func, args);
    }

    const end_time = std.time.nanoTimestamp();
    const run_time = (core.coerceTo(f128, end_time).? - core.coerceTo(f128, start_time).?) / core.coerceTo(f128, std.time.ns_per_s).?;

    const output = try std.fmt.allocPrint(
        options.allocator,
        \\ -----[BENCH SUMMARY]-----
        \\ fn: {s}
        \\ args: {s}
        \\ runtime: {d:.12}s
        \\ -----[BENCH SUMMARY]-----
    ,
        .{ fn_name, args_str, run_time },
    );

    _ = try options.logger.write(output);
}
