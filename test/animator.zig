const lm = @import("loom");
const std = @import("std");

const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectEqualStrings = testing.expectEqualStrings;

test "Keyframe sprite interpolation order" {
    const first_keyframe = lm.Keyframe{ .sprite = "frame_a.png" };
    const second_keyframe = lm.Keyframe{ .sprite = "frame_b.png" };

    const interpolated_start = first_keyframe.interpolate(second_keyframe, lm.interpolation.lerp, 0.0);
    try expectEqualStrings("frame_a.png", interpolated_start.sprite.?);

    const interpolated_middle = first_keyframe.interpolate(second_keyframe, lm.interpolation.lerp, 0.5);
    try expectEqualStrings("frame_a.png", interpolated_middle.sprite.?);

    const interpolated_past_middle = first_keyframe.interpolate(second_keyframe, lm.interpolation.lerp, 0.51);
    try expectEqualStrings("frame_b.png", interpolated_past_middle.sprite.?);

    const interpolated_end = first_keyframe.interpolate(second_keyframe, lm.interpolation.lerp, 1.0);
    try expectEqualStrings("frame_b.png", interpolated_end.sprite.?);
}

test "Animation single keyframe close" {
    var animation = lm.Animation.init("single", 1.0, lm.interpolation.lerp, &.{
        lm.Keyframe{ .sprite = "only_frame.png" },
    });
    defer animation.deinit();

    for (animation.base_keyframes) |keyframe| {
        _ = animation.append(keyframe);
    }
    animation.close();

    const current_keyframe = animation.current();
    try expect(current_keyframe != null);
    try expectEqualStrings("only_frame.png", current_keyframe.?.sprite.?);

    const next_keyframe = animation.next();
    try expect(next_keyframe == null);
}

test "Animation zero keyframe close does not crash" {
    var unclosed_animation = lm.Animation.init("empty", 1.0, lm.interpolation.lerp, &.{});
    defer unclosed_animation.deinit();

    _ = unclosed_animation.append(lm.Keyframe{ .sprite = "dummy.png" });

    var empty_animation = lm.Animation.init("empty2", 1.0, lm.interpolation.lerp, &.{});
    defer empty_animation.deinit();
    empty_animation.close();

    try expect(empty_animation.keys == null);
}

test "Animation multiple keyframes close" {
    var animation = lm.Animation.init("multi", 1.0, lm.interpolation.lerp, &.{
        lm.Keyframe{ .sprite = "frame_1.png" },
        lm.Keyframe{ .sprite = "frame_2.png" },
    });
    defer animation.deinit();

    for (animation.base_keyframes) |keyframe| {
        _ = animation.append(keyframe);
    }
    animation.close();

    try expect(animation.keys != null);
    try expectEqual(@as(usize, 2), animation.keys.?.len);
    try expectEqual(@as(f32, 0.0), animation.keys.?[0]);
    try expectEqual(@as(f32, 1.0), animation.keys.?[1]);
}

test "Animation supports arbitrary number of keyframes" {
    var animation = lm.Animation.init("many_frames", 2.0, lm.interpolation.lerp, &.{});
    defer animation.deinit();

    for (0..250) |_| {
        _ = animation.append(lm.Keyframe{ .sprite = "dummy_frame.png" });
    }
    animation.close();

    try expect(animation.keys != null);
    try expectEqual(@as(usize, 250), animation.keys.?.len);
    try expectEqual(@as(f32, 0.0), animation.keys.?[0]);
    try expectEqual(@as(f32, 1.0), animation.keys.?[249]);

    for (1..250) |key_index| {
        try expect(animation.keys.?[key_index] > animation.keys.?[key_index - 1]);
    }

    animation.current_percent = 0.5;
    const current_keyframe = animation.current();
    try expect(current_keyframe != null);

    const next_keyframe = animation.next();
    try expect(next_keyframe != null);
}
