const std = @import("std");
const Allocator = std.mem.Allocator;

const lm = @import("../../root.zig");
const rl = lm.deps.rl;

pub const shared = @import("./types.zig");

pub const Animation = shared.Animation;
pub const KeyFrame = shared.Keyframe;

const Self = @This();

alloc: Allocator,
alive: bool = false,

animations: lm.List(*Animation) = undefined,
base_animations: []const Animation,
playing: lm.List(*Animation) = undefined,
sprite_cache: std.AutoHashMap(u128, lm.List(*rl.Texture)) = undefined,

transform: ?*lm.Transform = null,
display: ?*lm.Renderer = null,

// Behaviour Methods
// --------------------------------------------------------------------------------------------------------------

pub fn Awake(self: *Self) !void {
    self.animations = lm.List(*Animation).init(self.alloc);
    self.playing = lm.List(*Animation).init(self.alloc);
    self.sprite_cache = std.AutoHashMap(u128, lm.List(*rl.Texture)).init(self.alloc);

    for (self.base_animations) |animation| {
        try self.chain(animation);
    }
}

pub fn Start(self: *Self, entity: *lm.Entity) !void {
    self.transform = entity.getComponent(lm.Transform) orelse return;
    self.display = entity.getComponent(lm.Renderer) orelse return;

    for (self.animations.items()) |animation| {
        self.cacheAnimationSprites(animation);
    }
}

pub fn Update(self: *Self, _: *lm.Entity) !void {
    const transform = self.transform orelse return;
    const display = self.display orelse return;

    for (self.playing.items()) |animation| {
        if (!animation.playing) {
            self.stop(animation.name);
            break;
        }

        self.updateAnimation(animation, transform, display);
    }

    self.cleanupFinishedAnimations();
}

pub fn End(self: *Self) !void {
    self.deinit();
}

// Custom / Helper Methods
// --------------------------------------------------------------------------------------------------------------

pub fn init(base_animations: []const Animation) Self {
    return Self{
        .alloc = std.heap.smp_allocator,
        .base_animations = base_animations,
        .alive = true,
    };
}

pub fn deinit(self: *Self) void {
    if (!self.alive) return;

    self.clearAllSpriteCaches();
    self.sprite_cache.deinit();

    for (self.animations.items()) |animation| {
        animation.deinit();
        self.alloc.destroy(animation);
    }

    self.playing.deinit();
    self.animations.deinit();

    self.alive = false;
}

pub fn chain(self: *Self, animation: Animation) !void {
    if (!self.alive) return;

    const stored_animation = try self.alloc.create(Animation);
    stored_animation.* = animation;

    for (stored_animation.base_keyframes) |base_keyframe| {
        _ = stored_animation.append(base_keyframe);
    }
    stored_animation.close();

    if (stored_animation.uuid == 0) stored_animation.uuid = lm.UUIDv7();

    try self.animations.append(stored_animation);
    self.cacheAnimationSprites(stored_animation);
}

pub fn isPlaying(self: *Self, name: []const u8) bool {
    if (!self.alive) return false;

    for (self.animations.items()) |animation| {
        if (std.mem.eql(u8, animation.name, name)) return animation.playing;
    }

    return false;
}

pub fn play(self: *Self, name: []const u8) !void {
    if (!self.alive) return;

    for (self.animations.items()) |animation| {
        if (!std.mem.eql(u8, animation.name, name)) continue;

        if (animation.playing) return;
        try self.playing.append(animation);

        animation.playing = true;
        animation.current_percent = 0.0;
        animation.start_time = lm.time.gameTime();

        break;
    }
}

pub fn stop(self: *Self, name: []const u8) void {
    if (!self.alive) return;

    for (self.animations.items()) |animation| {
        if (!std.mem.eql(u8, animation.name, name)) continue;
        if (!animation.playing) return;

        self.removePlayingAnimation(animation.uuid);
        animation.playing = false;
        return;
    }
}

fn removePlayingAnimation(self: *Self, target_uuid: u128) void {
    for (self.playing.items(), 0..) |animation, animation_index| {
        if (animation.uuid != target_uuid) continue;

        _ = self.playing.swapRemove(animation_index);
        return;
    }
}

fn updateAnimation(
    self: *Self,
    animation: *Animation,
    transform: *lm.Transform,
    display: *lm.Renderer,
) void {
    _ = self;
    const current_keyframe = animation.current() orelse return;
    const next = animation.next();

    const next_keyframe = next orelse {
        current_keyframe.apply(transform, display);
        animation.playing = false;
        return;
    };

    const elapsed_seconds = lm.time.gameTime() - lm.tof32(animation.start_time);
    const duration_seconds = lm.tof32(animation.length);
    const raw_factor = if (duration_seconds > 0.0) elapsed_seconds / duration_seconds else 1.0;
    const interpolation_factor = @min(1.0, @max(0.0, raw_factor));

    const animation_progress_percent = animation.timing_function(0.0, 1.0, interpolation_factor);
    const next_index_percent = animation.timing_function(0.0, 1.0, animation.next_index);
    const current_index_percent = animation.timing_function(0.0, 1.0, animation.current_index);

    const progress_span = next_index_percent - current_index_percent;
    const percent = if (progress_span > 0.0)
        @min(1.0, @max(0.0, (animation_progress_percent - current_index_percent) / progress_span))
    else
        1.0;

    const interpolated_keyframe = current_keyframe
        .interpolate(next_keyframe, shared.interpolation.lerp, percent);

    interpolated_keyframe.apply(transform, display);

    if (percent < 1.0) return;

    animation.incrementCurrentPercent(interpolation_factor);

    if (animation.loop and interpolation_factor >= 1.0) {
        animation.start_time = lm.time.gameTime();
    }
}

fn cleanupFinishedAnimations(self: *Self) void {
    const playing_count = self.playing.len();
    for (1..playing_count + 1) |offset| {
        const index = playing_count - offset;
        const animation = self.playing.items()[index];

        if (animation.playing) continue;
        _ = self.playing.swapRemove(index);
    }
}

fn cacheSprite(self: *Self, animation_uuid: u128, path: []const u8, modifiers: []const i32) void {
    const texture = lm.assets.texture.get(path, modifiers) orelse return;

    const cached_textures = if (self.sprite_cache.getPtr(animation_uuid)) |existing_textures|
        existing_textures
    else Blk: {
        const initialized_textures = lm.List(*rl.Texture).init(self.alloc);
        self.sprite_cache.put(animation_uuid, initialized_textures) catch {
            lm.assets.texture.releasePtr(texture);
            return;
        };
        break :Blk self.sprite_cache.getPtr(animation_uuid).?;
    };

    for (cached_textures.items()) |cached_texture| {
        if (cached_texture == texture) {
            lm.assets.texture.releasePtr(texture);
            return;
        }
    }

    cached_textures.append(texture) catch {
        lm.assets.texture.releasePtr(texture);
    };
}

fn cacheAnimationSprites(self: *Self, animation: *Animation) void {
    const display = self.display orelse return;
    const transform = self.transform orelse return;
    const tile_size = display.tile_size orelse transform.scale;
    const modifiers = [_]i32{ lm.toi32(tile_size.x), lm.toi32(tile_size.y) };

    if (animation.keyframes) |*keyframes| {
        for (keyframes.items()) |entry| {
            const path = entry.keyframe.sprite orelse continue;
            self.cacheSprite(animation.uuid, path, &modifiers);
        }
        return;
    }

    for (animation.base_keyframes) |keyframe| {
        const path = keyframe.sprite orelse continue;
        self.cacheSprite(animation.uuid, path, &modifiers);
    }
}

fn clearAllSpriteCaches(self: *Self) void {
    var cache_iterator = self.sprite_cache.iterator();
    while (cache_iterator.next()) |entry| {
        for (entry.value_ptr.items()) |texture| {
            lm.assets.texture.releasePtr(texture);
        }
        entry.value_ptr.deinit();
    }
    self.sprite_cache.clearAndFree();
}
