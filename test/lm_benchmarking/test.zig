const std = @import("std");
const testing = std.testing;

const benchmarking = @import("lm_benchmarking");

const SampleCallbacks = struct {
    var hook_balance: isize = 0;

    fn beforeTrial() !void {
        hook_balance += 1;
    }

    fn afterTrial() !void {
        hook_balance -= 1;
    }

    fn addValues(first: usize, second: usize) usize {
        return first + second;
    }

    fn accumulate() !void {
        if (hook_balance != 1) return error.UnexpectedHookBalance;
    }
};

test "reference all lm_benchmarking declarations" {
    testing.refAllDecls(benchmarking);
}

test "measure handles non-void return values and formats summary" {
    var output_buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&output_buffer);

    const options: benchmarking.Options = .{
        .logger = &writer,
        .allocator = testing.allocator,
        .warmup_count = 2,
    };

    try benchmarking.measure(3, "addValues", SampleCallbacks.addValues, .{ 10, 32 }, options);

    const written = output_buffer[0..writer.end];
    try testing.expect(std.mem.indexOf(u8, written, "fn: addValues") != null);
    try testing.expect(std.mem.indexOf(u8, written, "args: .{ 10, 32 }") != null);
    try testing.expect(std.mem.indexOf(u8, written, "-----[BENCH SUMMARY]-----") != null);
}

test "measure runs before_trial and after_trial hooks for warmup and measured trials" {
    SampleCallbacks.hook_balance = 0;

    var output_buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&output_buffer);

    const options: benchmarking.Options = .{
        .logger = &writer,
        .allocator = testing.allocator,
        .warmup_count = 2,
        .before_trial = SampleCallbacks.beforeTrial,
        .after_trial = SampleCallbacks.afterTrial,
    };

    try benchmarking.measure(4, "accumulate", SampleCallbacks.accumulate, .{}, options);
    try testing.expectEqual(@as(isize, 0), SampleCallbacks.hook_balance);
}
