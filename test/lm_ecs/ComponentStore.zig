const std = @import("std");
const lm_ecs = @import("lm_ecs");

const ComponentStore = lm_ecs.ComponentStore;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const Position = struct { x: f32, y: f32 };

test "Swap-and-Pop Integrity" {
    const allocator = std.testing.allocator;
    var store = ComponentStore.init(Position, allocator);
    defer store.deinit();

    try store.store(0, Position{ .x = 0, .y = 0 });
    try store.store(1, Position{ .x = 1, .y = 1 });
    try store.store(2, Position{ .x = 2, .y = 2 });

    try store.remove(1);

    try expect(store.get(Position, 1) == null);

    const p2 = store.get(Position, 2).?;
    try expectEqual(@as(f32, 2.0), p2.x);

    try expectEqual(@as(usize, 1), store.sparse.items()[2].?);

    try expectEqual(2 * @sizeOf(Position), store.dense.len());
}

const UnalignedStruct = struct {
    a: u8,

    b: u64,
};

test "Alignment Safety" {
    const allocator = std.testing.allocator;
    var store = ComponentStore.init(UnalignedStruct, allocator);
    defer store.deinit();

    try store.store(10, UnalignedStruct{ .a = 1, .b = 100 });
    try store.store(20, UnalignedStruct{ .a = 2, .b = 200 });

    const ptr1 = store.get(UnalignedStruct, 10).?;
    const ptr2 = store.get(UnalignedStruct, 20).?;

    try expectEqual(@as(u64, 100), ptr1.b);
    try expectEqual(@as(u64, 200), ptr2.b);

    try expect(@intFromPtr(ptr1) % 8 == 0);
    try expect(@intFromPtr(ptr2) % 8 == 0);
}

test "Extreme Sparse Gap" {
    const allocator = std.testing.allocator;
    var store = ComponentStore.init(Position, allocator);
    defer store.deinit();

    try store.store(0, Position{ .x = 0, .y = 0 });
    try store.store(1000, Position{ .x = 1000, .y = 1000 });

    try expectEqual(@as(usize, 1001), store.sparse.len());
    try expect(store.sparse.items()[500] == null);

    const p1000 = store.get(Position, 1000).?;
    try expectEqual(@as(f32, 1000.0), p1000.x);
}

test "Error Conditions" {
    const allocator = std.testing.allocator;
    var store = ComponentStore.init(Position, allocator);
    defer store.deinit();

    try store.store(5, Position{ .x = 1, .y = 1 });
    const err = store.store(5, Position{ .x = 2, .y = 2 });
    try std.testing.expectError(ComponentStore.Error.EntityAlreadyHasComponent, err);

    try expect(store.get(Position, 999) == null);

    try store.remove(999);
}

test "Pointer Invalidations (Warning Test)" {
    const allocator = std.testing.allocator;
    var store = ComponentStore.init(Position, allocator);
    defer store.deinit();

    try store.store(0, Position{ .x = 0, .y = 0 });
    try store.store(1, Position{ .x = 1, .y = 1 });

    const ptr_to_1 = store.get(Position, 1).?;

    try store.remove(0);

    const new_ptr_to_1 = store.get(Position, 1).?;
    try expect(ptr_to_1 != new_ptr_to_1);
}
