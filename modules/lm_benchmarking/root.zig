const std = @import("std");
const Allocator = std.mem.Allocator;

const types = @import("lm_types");

/// Lifecycle callback executed before or after an individual measured or warmup trial.
pub const HookCallback = *const fn () anyerror!void;

/// Configuration passed to `measure` controlling logging, allocation, warmup, and trial hooks.
pub const Options = struct {
    logger: *std.Io.Writer,
    allocator: Allocator,
    warmup_count: usize = 0,
    before_trial: ?HookCallback = null,
    after_trial: ?HookCallback = null,

    /// Return a shallow copy of these options with custom per-trial setup and teardown hooks.
    pub fn withHooks(
        self: Options,
        before_trial: ?HookCallback,
        after_trial: ?HookCallback,
    ) Options {
        var copy = self;
        copy.before_trial = before_trial;
        copy.after_trial = after_trial;
        return copy;
    }
};

fn nanosecondsToSeconds(nanoseconds: i96) f128 {
    return types.coerceTo(f128, nanoseconds).? / types.coerceTo(f128, std.time.ns_per_s).?;
}

fn invokeCallback(comptime function_callback: anytype, arguments: anytype) !void {
    const return_type = @typeInfo(@TypeOf(function_callback)).@"fn".return_type orelse void;
    if (return_type == void) {
        @call(.auto, function_callback, arguments);
        return;
    }

    if (@typeInfo(return_type) == .error_union) {
        const payload = try @call(.auto, function_callback, arguments);
        std.mem.doNotOptimizeAway(payload);
        return;
    }

    const value = @call(.auto, function_callback, arguments);
    std.mem.doNotOptimizeAway(value);
}

fn executeTrial(
    io: std.Io,
    comptime function_callback: anytype,
    arguments: anytype,
    options: Options,
) !f128 {
    if (options.before_trial) |before_trial| try before_trial();
    defer if (options.after_trial) |after_trial| after_trial() catch {};

    const start_timestamp = std.Io.Timestamp.now(io, .awake);
    try invokeCallback(function_callback, arguments);
    const end_timestamp = std.Io.Timestamp.now(io, .awake);

    return nanosecondsToSeconds(start_timestamp.durationTo(end_timestamp).nanoseconds);
}

/// Measure `trial_count` invocations of `function_callback` after `options.warmup_count` warmup runs
/// and write the timing summary to `options.logger`.
pub fn measure(
    comptime trial_count: comptime_int,
    comptime function_name: []const u8,
    comptime function_callback: anytype,
    arguments: anytype,
    options: Options,
) !void {
    types.comptimeAssert(@typeInfo(@TypeOf(function_callback)) == .@"fn", "function_callback must be a function");
    types.comptimeAssert(trial_count > 0, "trial_count must be greater than zero");

    const formatted_arguments = try std.fmt.allocPrint(options.allocator, "{any}", .{arguments});
    defer options.allocator.free(formatted_arguments);

    var threaded_io = std.Io.Threaded.init_single_threaded;
    const io = threaded_io.io();

    for (0..options.warmup_count) |_| {
        _ = try executeTrial(io, function_callback, arguments, options);
    }

    var best_runtime_seconds: ?f128 = null;
    var worst_runtime_seconds: ?f128 = null;
    var total_runtime_seconds: f128 = 0;

    for (0..trial_count) |_| {
        const elapsed_seconds = try executeTrial(io, function_callback, arguments, options);
        total_runtime_seconds += elapsed_seconds;

        if (best_runtime_seconds == null or elapsed_seconds < best_runtime_seconds.?) {
            best_runtime_seconds = elapsed_seconds;
        }
        if (worst_runtime_seconds == null or elapsed_seconds > worst_runtime_seconds.?) {
            worst_runtime_seconds = elapsed_seconds;
        }
    }

    const average_runtime_seconds = total_runtime_seconds / trial_count;

    try options.logger.print(
        "\n" ++
            \\ -----[BENCH SUMMARY]-----
            \\ fn: {s}
            \\ args: {s}
            \\ runtimes (s):
            \\ best: {d:.9}
            \\ worst: {d:.9}
            \\ average: {d:.9}
            \\ total: {d:.9}
            \\ -----[BENCH SUMMARY]-----
        ++ "\n",
        .{
            function_name,
            formatted_arguments,
            best_runtime_seconds orelse 0,
            worst_runtime_seconds orelse 0,
            average_runtime_seconds,
            total_runtime_seconds,
        },
    );
    try options.logger.flush();
}
