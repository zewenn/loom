const std = @import("std");
const Allocator = std.mem.Allocator;

const lm = @import("../../root.zig");
const shared = @import("./types.zig");

const tof32 = lm.tof32;

const Self = @This();

pub const KeyframeEntry = struct {
    progress: f32,
    keyframe: shared.Keyframe,
};

name: []const u8,
uuid: u128,

keys: ?[]f32 = null,
keysArrayList: ?lm.List(f32) = null,
keyframes: ?lm.List(KeyframeEntry) = null,
base_keyframes: []const shared.Keyframe,
unregistered_keyframes: ?lm.List(shared.Keyframe) = null,

/// Length of the entire animation, in seconds.
length: f64 = 0,
timing_function: shared.TimingFunction = shared.interpolation.lerp,

current_index: f32 = 0.0,
next_index: f32 = 0.0,

current_percent: f32 = 0.0,

playing: bool = false,
loop: bool = false,
mode: shared.Modes = .forwards,

start_time: f64 = 0,

alloc: Allocator,

pub fn init(name: []const u8, length: anytype, timing_function: shared.TimingFunction, frames: []const shared.Keyframe) Self {
    return Self{
        .name = name,
        .uuid = 0,
        .alloc = std.heap.smp_allocator,
        .base_keyframes = frames,
        .length = lm.tof64(length),
        .timing_function = timing_function,
    };
}

pub fn deinit(self: *Self) void {
    self.playing = false;

    if (self.keys) |keys_slice| {
        self.alloc.free(keys_slice);
        self.keys = null;
    }

    if (self.keysArrayList) |*keys_array_list| {
        keys_array_list.deinit();
        self.keysArrayList = null;
    }

    if (self.keyframes) |*stored_keyframes| {
        stored_keyframes.deinit();
        self.keyframes = null;
    }

    if (self.unregistered_keyframes) |*unregistered_keyframes| {
        unregistered_keyframes.deinit();
        self.unregistered_keyframes = null;
    }
}

fn compareKeyframeAscending(_: void, first_entry: KeyframeEntry, second_entry: KeyframeEntry) bool {
    return first_entry.progress < second_entry.progress;
}

fn compareKeyframeDescending(_: void, first_entry: KeyframeEntry, second_entry: KeyframeEntry) bool {
    return first_entry.progress > second_entry.progress;
}

pub fn sortKeys(self: *Self) void {
    const keys_slice = self.keys orelse return;
    self.sortKeySlice(keys_slice);
    self.sortKeyframeEntries();
}

fn sortKeySlice(self: *Self, keys_slice: []f32) void {
    switch (self.mode) {
        .forwards => std.sort.insertion(f32, keys_slice, {}, std.sort.asc(f32)),
        .backwards => std.sort.insertion(f32, keys_slice, {}, std.sort.desc(f32)),
    }
}

fn sortKeyframeEntries(self: *Self) void {
    const stored_keyframes = &(self.keyframes orelse return);
    switch (self.mode) {
        .forwards => std.sort.insertion(KeyframeEntry, stored_keyframes.items(), {}, compareKeyframeAscending),
        .backwards => std.sort.insertion(KeyframeEntry, stored_keyframes.items(), {}, compareKeyframeDescending),
    }
}

fn makeKeysArrayList(self: *Self) *lm.List(f32) {
    return &(self.keysArrayList orelse Blk: {
        self.keysArrayList = lm.List(f32).init(self.alloc);
        break :Blk self.keysArrayList.?;
    });
}

fn makeKeyframesList(self: *Self) *lm.List(KeyframeEntry) {
    return &(self.keyframes orelse Blk: {
        self.keyframes = lm.List(KeyframeEntry).init(self.alloc);
        break :Blk self.keyframes.?;
    });
}

fn makeKeySliceAndSort(self: *Self) !void {
    const array_list = self.makeKeysArrayList();

    if (self.keys) |existing_keys| {
        self.alloc.free(existing_keys);
        self.keys = null;
    }

    self.keys = try array_list.cloneToOwnedSlice();
    self.sortKeys();
}

pub fn chain(self: *Self, percent: f32, keyframe: shared.Keyframe) *Self {
    const normalized_progress: f32 = if (percent > 1.0)
        @min(percent / 100.0, 1.0)
    else
        @max(0.0, percent);

    const stored_keyframes = self.makeKeyframesList();

    for (stored_keyframes.items()) |*entry| {
        if (std.math.approxEqAbs(f32, entry.progress, normalized_progress, 1e-6)) {
            std.log.warn("Overriding existing keyframe at progress {d:.2}", .{normalized_progress});
            entry.keyframe = keyframe;
            return self;
        }
    }

    stored_keyframes.append(.{
        .progress = normalized_progress,
        .keyframe = keyframe,
    }) catch return self;

    const keys_array_list = self.makeKeysArrayList();
    keys_array_list.append(normalized_progress) catch return self;

    self.makeKeySliceAndSort() catch return self;
    return self;
}

pub fn append(self: *Self, keyframe: shared.Keyframe) *Self {
    const unregistered_keyframes = &(self.unregistered_keyframes orelse Blk: {
        self.unregistered_keyframes = lm.List(shared.Keyframe).init(self.alloc);
        break :Blk self.unregistered_keyframes.?;
    });

    unregistered_keyframes.append(keyframe) catch return self;

    return self;
}

pub fn close(self: *Self) void {
    const unregistered_keyframes = &(self.unregistered_keyframes orelse return);
    if (self.keys != null) {
        std.log.warn("Animation.close() cannot be used with .chain()!", .{});
        return;
    }

    const keyframe_count = unregistered_keyframes.len();
    if (keyframe_count == 0) return;

    const stored_keyframes = self.makeKeyframesList();
    const keys_array_list = self.makeKeysArrayList();

    if (keyframe_count == 1) {
        stored_keyframes.append(.{
            .progress = 0.0,
            .keyframe = unregistered_keyframes.items()[0],
        }) catch return;
        keys_array_list.append(0.0) catch return;
        self.makeKeySliceAndSort() catch return;
        return;
    }

    const keyframe_progress_distance: f32 = 1.0 / tof32(keyframe_count - 1);
    for (unregistered_keyframes.items(), 0..) |keyframe, keyframe_index| {
        const progress: f32 = if (keyframe_index == keyframe_count - 1)
            1.0
        else
            @min(tof32(keyframe_index) * keyframe_progress_distance, 1.0);

        stored_keyframes.append(.{
            .progress = progress,
            .keyframe = keyframe,
        }) catch {
            std.log.warn("Couldn't add progress-keyframe pair!", .{});
        };

        keys_array_list.append(progress) catch {
            std.log.warn("Couldn't add number to keys", .{});
        };
    }

    self.makeKeySliceAndSort() catch return;
}

pub fn next(self: *Self) ?shared.Keyframe {
    const stored_keyframes = self.keyframes orelse return null;
    return self.findNextKeyframe(stored_keyframes.items());
}

fn findNextKeyframe(self: *Self, entries: []const KeyframeEntry) ?shared.Keyframe {
    for (entries) |entry| {
        const is_candidate = switch (self.mode) {
            .forwards => entry.progress > self.current_percent,
            .backwards => entry.progress < self.current_percent,
        };
        if (!is_candidate) continue;

        self.next_index = entry.progress;
        return entry.keyframe;
    }

    return null;
}

pub fn current(self: *Self) ?shared.Keyframe {
    const stored_keyframes = self.keyframes orelse return null;
    return self.findCurrentKeyframe(stored_keyframes.items());
}

fn findCurrentKeyframe(self: *Self, entries: []const KeyframeEntry) ?shared.Keyframe {
    var matched_entry: ?KeyframeEntry = null;

    for (entries) |entry| {
        const is_candidate = switch (self.mode) {
            .forwards => entry.progress <= self.current_percent,
            .backwards => entry.progress >= self.current_percent,
        };
        if (!is_candidate) {
            if (self.mode == .forwards and entry.progress > self.current_percent) {
                break;
            }
            continue;
        }

        matched_entry = entry;
    }

    const found_entry = matched_entry orelse {
        if (entries.len == 0) return null;
        self.current_index = entries[0].progress;
        return entries[0].keyframe;
    };

    self.current_index = found_entry.progress;
    return found_entry.keyframe;
}

pub fn incrementCurrentPercent(self: *Self, increment_to: f32) void {
    self.current_percent = increment_to;

    if (increment_to < 1.0) return;

    if (self.loop) {
        self.current_percent = 0.0;
        return;
    }

    self.current_percent = 1.0;
    self.playing = false;
}
