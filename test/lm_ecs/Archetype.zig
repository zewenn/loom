const std = @import("std");
const testing = std.testing;

const core = @import("lm_core");
const ecs = @import("lm_ecs");
const Archetype = ecs.Archetype;

const Position = struct { x: f32, y: f32 };
const Velocity = struct { x: f32, y: f32 };
const Health = struct { value: u32 };
const Tag = struct { id: u8 };

const pos_hash = core.type_erasure.typeToHash(Position);
const vel_hash = core.type_erasure.typeToHash(Velocity);
const hp_hash = core.type_erasure.typeToHash(Health);
const tag_hash = core.type_erasure.typeToHash(Tag);

const pos_size = core.type_erasure.alignedSize(Position);
const vel_size = core.type_erasure.alignedSize(Velocity);
const hp_size = core.type_erasure.alignedSize(Health);
const tag_size = core.type_erasure.alignedSize(Tag);

const POS_BIT: u128 = 1 << 0;
const VEL_BIT: u128 = 1 << 1;
const HP_BIT: u128 = 1 << 2;
const TAG_BIT: u128 = 1 << 3;

fn makeArch(
    allocator: std.mem.Allocator,
    mask: u128,
    hashes: []const u64,
    sizes: []const usize,
) !Archetype {
    return Archetype.init(allocator, mask, hashes, sizes);
}

/// Build a two-column (Position + Velocity) archetype.
fn makePVArch(allocator: std.mem.Allocator) !Archetype {
    return makeArch(
        allocator,
        POS_BIT | VEL_BIT,
        &.{ pos_hash, vel_hash },
        &.{ pos_size, vel_size },
    );
}

/// Add a single entity with explicit component values.
fn addPV(arch: *Archetype, entity: ecs.Entity, pos: Position, vel: Velocity) !void {
    var p = pos;
    var v = vel;
    try arch.addEntity(entity, &.{ &p, &v });
}

test "init: fresh archetype is empty and has correct mask" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try testing.expectEqual(@as(usize, 0), arch.len());
    try testing.expect(arch.isEmpty());
    try testing.expectEqual(POS_BIT | VEL_BIT, arch.mask);
}

test "init: component hashes are stored and reachable by index" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try testing.expectEqual(@as(?usize, 0), arch.columnIndex(pos_hash));
    try testing.expectEqual(@as(?usize, 1), arch.columnIndex(vel_hash));
    try testing.expectEqual(@as(?usize, null), arch.columnIndex(hp_hash));
}

test "matchesMask: returns true when archetype covers all queried bits" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try testing.expect(arch.matchesMask(POS_BIT));
    try testing.expect(arch.matchesMask(VEL_BIT));
    try testing.expect(arch.matchesMask(POS_BIT | VEL_BIT));

    try testing.expect(arch.matchesMask(arch.mask));
}

test "matchesMask: returns false when archetype is missing a queried bit" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try testing.expect(!arch.matchesMask(HP_BIT));
    try testing.expect(!arch.matchesMask(POS_BIT | HP_BIT));
}

test "exactMask: only true for the exact same mask" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try testing.expect(arch.exactMask(POS_BIT | VEL_BIT));
    try testing.expect(!arch.exactMask(POS_BIT));
    try testing.expect(!arch.exactMask(POS_BIT | VEL_BIT | HP_BIT));
    try testing.expect(!arch.exactMask(0));
}

test "hasComponent: true only for hashes that belong to this archetype" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try testing.expect(arch.hasComponent(pos_hash));
    try testing.expect(arch.hasComponent(vel_hash));
    try testing.expect(!arch.hasComponent(hp_hash));
    try testing.expect(!arch.hasComponent(tag_hash));
}

test "addEntity: len grows by one per entity added" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try testing.expect(arch.isEmpty());
    try addPV(&arch, 0, .{ .x = 1, .y = 2 }, .{ .x = 0, .y = 0 });
    try testing.expectEqual(@as(usize, 1), arch.len());
    try addPV(&arch, 1, .{ .x = 3, .y = 4 }, .{ .x = 0, .y = 0 });
    try testing.expectEqual(@as(usize, 2), arch.len());
}

test "addEntity: entity is immediately found after insertion" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try testing.expect(!arch.containsEntity(42));
    try addPV(&arch, 42, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 });
    try testing.expect(arch.containsEntity(42));
}

test "addEntity: component values are stored correctly" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    const expected_pos = Position{ .x = 10.0, .y = 20.0 };
    const expected_vel = Velocity{ .x = -1.5, .y = 3.0 };
    try addPV(&arch, 7, expected_pos, expected_vel);

    const got_pos = arch.getComponentAs(Position, 7) orelse return error.TestUnexpectedNull;
    const got_vel = arch.getComponentAs(Velocity, 7) orelse return error.TestUnexpectedNull;

    try testing.expectEqual(expected_pos, got_pos.*);
    try testing.expectEqual(expected_vel, got_vel.*);
}

test "addEntity: multiple entities store independent component data" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 0, .{ .x = 1, .y = 1 }, .{ .x = 10, .y = 10 });
    try addPV(&arch, 1, .{ .x = 2, .y = 2 }, .{ .x = 20, .y = 20 });
    try addPV(&arch, 2, .{ .x = 3, .y = 3 }, .{ .x = 30, .y = 30 });

    try testing.expectEqual(@as(f32, 1), arch.getComponentAs(Position, 0).?.x);
    try testing.expectEqual(@as(f32, 2), arch.getComponentAs(Position, 1).?.x);
    try testing.expectEqual(@as(f32, 3), arch.getComponentAs(Position, 2).?.x);

    try testing.expectEqual(@as(f32, 10), arch.getComponentAs(Velocity, 0).?.x);
    try testing.expectEqual(@as(f32, 20), arch.getComponentAs(Velocity, 1).?.x);
    try testing.expectEqual(@as(f32, 30), arch.getComponentAs(Velocity, 2).?.x);
}

test "addEntity: each entity receives a unique, valid row index" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 10, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 });
    try addPV(&arch, 20, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 });
    try addPV(&arch, 30, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 });

    const row10 = arch.entityRow(10) orelse return error.TestUnexpectedNull;
    const row20 = arch.entityRow(20) orelse return error.TestUnexpectedNull;
    const row30 = arch.entityRow(30) orelse return error.TestUnexpectedNull;

    try testing.expect(row10 < arch.len());
    try testing.expect(row20 < arch.len());
    try testing.expect(row30 < arch.len());

    try testing.expect(row10 != row20);
    try testing.expect(row10 != row30);
    try testing.expect(row20 != row30);
}

test "getComponentAs: returns null for an entity not in this archetype" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try testing.expectEqual(@as(?*Position, null), arch.getComponentAs(Position, 99));
}

test "getComponentAs: returns null for a component type not in this archetype" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 0, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 });
    try testing.expectEqual(@as(?*Health, null), arch.getComponentAs(Health, 0));
}

test "getComponentAs: returned pointer is live — mutation is visible on next call" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 5, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 });

    const ptr = arch.getComponentAs(Position, 5) orelse return error.TestUnexpectedNull;
    ptr.x = 99.0;
    ptr.y = -7.0;

    const check = arch.getComponentAs(Position, 5) orelse return error.TestUnexpectedNull;
    try testing.expectEqual(@as(f32, 99.0), check.x);
    try testing.expectEqual(@as(f32, -7.0), check.y);
}

test "setComponentAs: overwrites an existing component value" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 3, .{ .x = 1, .y = 1 }, .{ .x = 1, .y = 1 });
    arch.setComponentAs(Position, 3, .{ .x = 42.0, .y = -8.0 });

    const got = arch.getComponentAs(Position, 3) orelse return error.TestUnexpectedNull;
    try testing.expectEqual(@as(f32, 42.0), got.x);
    try testing.expectEqual(@as(f32, -8.0), got.y);
}

test "setComponentAs: updating one entity does not affect another entity's data" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 0, .{ .x = 1, .y = 1 }, .{ .x = 0, .y = 0 });
    try addPV(&arch, 1, .{ .x = 2, .y = 2 }, .{ .x = 0, .y = 0 });

    arch.setComponentAs(Position, 0, .{ .x = 99, .y = 99 });

    const unchanged = arch.getComponentAs(Position, 1) orelse return error.TestUnexpectedNull;
    try testing.expectEqual(@as(f32, 2), unchanged.x);
    try testing.expectEqual(@as(f32, 2), unchanged.y);
}

test "removeEntity: unknown entity returns null and leaves len unchanged" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 0, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 });

    const moved = arch.removeEntity(999);
    try testing.expectEqual(@as(?ecs.Entity, null), moved);
    try testing.expectEqual(@as(usize, 1), arch.len());
}

test "removeEntity: removing the only entity leaves an empty archetype" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 0, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 });
    const moved = arch.removeEntity(0);

    try testing.expectEqual(@as(?ecs.Entity, null), moved); // nothing was swapped
    try testing.expect(arch.isEmpty());
    try testing.expect(!arch.containsEntity(0));
}

test "removeEntity: removing the last entity in a multi-entity archetype returns null" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 0, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 });
    try addPV(&arch, 1, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 });

    const moved = arch.removeEntity(1);
    try testing.expectEqual(@as(?ecs.Entity, null), moved);
    try testing.expectEqual(@as(usize, 1), arch.len());
}

test "removeEntity: removed entity is no longer found" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 5, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 });
    _ = arch.removeEntity(5);

    try testing.expect(!arch.containsEntity(5));
    try testing.expectEqual(@as(?usize, null), arch.entityRow(5));
    try testing.expectEqual(@as(?*Position, null), arch.getComponentAs(Position, 5));
}

test "removeEntity: middle entity is swap-removed and displaced entity is identified" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 10, .{ .x = 1, .y = 1 }, .{ .x = 0, .y = 0 });
    try addPV(&arch, 20, .{ .x = 2, .y = 2 }, .{ .x = 0, .y = 0 });
    try addPV(&arch, 30, .{ .x = 3, .y = 3 }, .{ .x = 0, .y = 0 });

    const moved = arch.removeEntity(20);

    try testing.expectEqual(@as(?ecs.Entity, 30), moved);
    try testing.expectEqual(@as(usize, 2), arch.len());
    try testing.expect(!arch.containsEntity(20));
    try testing.expect(arch.containsEntity(10));
    try testing.expect(arch.containsEntity(30));
}

test "removeEntity: displaced entity has an updated, valid row index" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 10, .{ .x = 1, .y = 1 }, .{ .x = 0, .y = 0 });
    try addPV(&arch, 20, .{ .x = 2, .y = 2 }, .{ .x = 0, .y = 0 });
    try addPV(&arch, 30, .{ .x = 3, .y = 3 }, .{ .x = 0, .y = 0 });

    _ = arch.removeEntity(20); // 30 swaps to row 1

    const new_row = arch.entityRow(30) orelse return error.TestUnexpectedNull;
    try testing.expect(new_row < arch.len());

    try testing.expectEqual(@as(ecs.Entity, 30), arch.entities.items()[new_row]);
}

test "removeEntity: displaced entity retains its original component data" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 10, .{ .x = 1, .y = 1 }, .{ .x = 0, .y = 0 });
    try addPV(&arch, 20, .{ .x = 2, .y = 2 }, .{ .x = 0, .y = 0 });
    try addPV(&arch, 30, .{ .x = 3, .y = 3 }, .{ .x = 5, .y = 6 });

    _ = arch.removeEntity(20);

    const pos = arch.getComponentAs(Position, 30) orelse return error.TestUnexpectedNull;
    const vel = arch.getComponentAs(Velocity, 30) orelse return error.TestUnexpectedNull;

    try testing.expectEqual(@as(f32, 3), pos.x);
    try testing.expectEqual(@as(f32, 3), pos.y);
    try testing.expectEqual(@as(f32, 5), vel.x);
    try testing.expectEqual(@as(f32, 6), vel.y);
}

test "removeEntity: untouched entities keep their component data after a swap-remove" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 10, .{ .x = 1, .y = 1 }, .{ .x = 0, .y = 0 });
    try addPV(&arch, 20, .{ .x = 2, .y = 2 }, .{ .x = 0, .y = 0 });
    try addPV(&arch, 30, .{ .x = 3, .y = 3 }, .{ .x = 0, .y = 0 });

    _ = arch.removeEntity(20);

    const pos10 = arch.getComponentAs(Position, 10) orelse return error.TestUnexpectedNull;
    try testing.expectEqual(@as(f32, 1), pos10.x);
    try testing.expectEqual(@as(f32, 1), pos10.y);
}

test "columnPtr: returns non-null pointer after at least one entity is added" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 0, .{ .x = 7, .y = 8 }, .{ .x = 9, .y = 10 });

    try testing.expect(arch.columnPtr(0) != null);
    try testing.expect(arch.columnPtr(1) != null);
}

test "columnPtr: column bytes match the values added via addEntity" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 0, .{ .x = 1.5, .y = 2.5 }, .{ .x = 0, .y = 0 });
    try addPV(&arch, 1, .{ .x = 3.5, .y = 4.5 }, .{ .x = 0, .y = 0 });

    const col_ptr = arch.columnPtr(0) orelse return error.TestUnexpectedNull;
    const slice = @as([*]Position, @ptrCast(@alignCast(col_ptr)))[0..2];

    const row0 = arch.entityRow(0) orelse return error.TestUnexpectedNull;
    const row1 = arch.entityRow(1) orelse return error.TestUnexpectedNull;

    try testing.expectEqual(@as(f32, 1.5), slice[row0].x);
    try testing.expectEqual(@as(f32, 3.5), slice[row1].x);
}

test "columnPtrByHash: returns null for a hash not in this archetype" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 0, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 });
    try testing.expectEqual(@as(?[*]u8, null), arch.columnPtrByHash(hp_hash));
}

test "fillColumnPtrs: succeeds when all hashes are present" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 0, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 });

    var out: [2][*]u8 = undefined;
    const ok = arch.fillColumnPtrs(&.{ pos_hash, vel_hash }, &out);
    try testing.expect(ok);
}

test "fillColumnPtrs: fails when any requested hash is missing" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 0, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 });

    var out: [3][*]u8 = undefined;
    const ok = arch.fillColumnPtrs(&.{ pos_hash, vel_hash, hp_hash }, &out);
    try testing.expect(!ok);
}

test "moveEntityFrom: entity appears in destination with correct data from source" {
    const allocator = testing.allocator;

    var src = try makePVArch(allocator);
    defer src.deinit();

    var dst = try makeArch(
        allocator,
        POS_BIT | VEL_BIT | HP_BIT,
        &.{ pos_hash, vel_hash, hp_hash },
        &.{ pos_size, vel_size, hp_size },
    );
    defer dst.deinit();

    try addPV(&src, 42, .{ .x = 5, .y = 6 }, .{ .x = -1, .y = -2 });

    var new_hp = Health{ .value = 100 };
    try dst.moveEntityFrom(42, &src, &.{.{ .hash = hp_hash, .data = &new_hp }});
    _ = src.removeEntity(42);

    try testing.expect(dst.containsEntity(42));
    try testing.expect(!src.containsEntity(42));

    const pos = dst.getComponentAs(Position, 42) orelse return error.TestUnexpectedNull;
    try testing.expectEqual(@as(f32, 5), pos.x);
    try testing.expectEqual(@as(f32, 6), pos.y);

    const vel = dst.getComponentAs(Velocity, 42) orelse return error.TestUnexpectedNull;
    try testing.expectEqual(@as(f32, -1), vel.x);
    try testing.expectEqual(@as(f32, -2), vel.y);

    const hp = dst.getComponentAs(Health, 42) orelse return error.TestUnexpectedNull;
    try testing.expectEqual(@as(u32, 100), hp.value);
}

test "moveEntityFrom: returns error.EntityNotFound when entity is not in source" {
    const allocator = testing.allocator;

    var src = try makePVArch(allocator);
    defer src.deinit();

    var dst = try makePVArch(allocator);
    defer dst.deinit();

    const result = dst.moveEntityFrom(999, &src, &.{});
    try testing.expectError(error.EntityNotFound, result);
}

test "moveEntityFrom: returns error.MissingComponentData when a required column has no data" {
    const allocator = testing.allocator;

    var src = try makePVArch(allocator);
    defer src.deinit();

    var dst = try makeArch(
        allocator,
        POS_BIT | VEL_BIT | HP_BIT,
        &.{ pos_hash, vel_hash, hp_hash },
        &.{ pos_size, vel_size, hp_size },
    );
    defer dst.deinit();

    try addPV(&src, 1, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 });

    const result = dst.moveEntityFrom(1, &src, &.{});
    try testing.expectError(error.MissingComponentData, result);

    try testing.expect(src.containsEntity(1));
    try testing.expectEqual(@as(usize, 1), src.len());
}

test "moveEntityFrom: a failed move leaves source archetype fully intact" {
    const allocator = testing.allocator;

    var src = try makePVArch(allocator);
    defer src.deinit();

    var dst = try makeArch(
        allocator,
        POS_BIT | VEL_BIT | HP_BIT,
        &.{ pos_hash, vel_hash, hp_hash },
        &.{ pos_size, vel_size, hp_size },
    );
    defer dst.deinit();

    try addPV(&src, 7, .{ .x = 3.14, .y = 2.71 }, .{ .x = 1, .y = 0 });

    _ = dst.moveEntityFrom(7, &src, &.{}) catch {};

    const pos = src.getComponentAs(Position, 7) orelse return error.TestUnexpectedNull;
    try testing.expectEqual(@as(f32, 3.14), pos.x);
    try testing.expectEqual(@as(f32, 2.71), pos.y);
}

test "moveEntityFrom: same-shape archetypes require no new_components" {
    const allocator = testing.allocator;

    var src = try makePVArch(allocator);
    defer src.deinit();

    var dst = try makePVArch(allocator);
    defer dst.deinit();

    try addPV(&src, 0, .{ .x = 7, .y = 8 }, .{ .x = -3, .y = -4 });

    try dst.moveEntityFrom(0, &src, &.{});
    _ = src.removeEntity(0);

    try testing.expect(dst.containsEntity(0));
    try testing.expect(!src.containsEntity(0));

    const pos = dst.getComponentAs(Position, 0) orelse return error.TestUnexpectedNull;
    try testing.expectEqual(@as(f32, 7), pos.x);
    try testing.expectEqual(@as(f32, 8), pos.y);
}

test "EntityIterator: yields nothing on an empty archetype" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    var it = arch.entityIterator();
    try testing.expectEqual(@as(?ecs.Entity, null), it.next());
}

test "EntityIterator: yields every added entity exactly once" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 10, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 });
    try addPV(&arch, 20, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 });
    try addPV(&arch, 30, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 });

    var seen = std.AutoHashMap(ecs.Entity, bool).init(allocator);
    defer seen.deinit();

    var it = arch.entityIterator();
    while (it.next()) |e| {
        try testing.expect(!seen.contains(e));
        try seen.put(e, true);
    }

    try testing.expectEqual(@as(usize, 3), seen.count());
    try testing.expect(seen.contains(10));
    try testing.expect(seen.contains(20));
    try testing.expect(seen.contains(30));
}

test "EntityIterator: reset allows full re-iteration" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 1, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 });
    try addPV(&arch, 2, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 });

    var it = arch.entityIterator();
    var first_count: usize = 0;
    while (it.next()) |_| first_count += 1;

    it.reset();
    var second_count: usize = 0;
    while (it.next()) |_| second_count += 1;

    try testing.expectEqual(first_count, second_count);
    try testing.expectEqual(@as(usize, 2), second_count);
}

test "RowIterator: row index is consistent with entity list" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 5, .{ .x = 1, .y = 2 }, .{ .x = 3, .y = 4 });
    try addPV(&arch, 6, .{ .x = 5, .y = 6 }, .{ .x = 7, .y = 8 });

    var it = arch.rowIterator();
    while (it.next()) |row| {
        try testing.expectEqual(row.entity, arch.entities.items()[row.row]);
    }
}

test "RowIterator: component data accessed via row matches getComponentAs" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 100, .{ .x = 42, .y = 43 }, .{ .x = 0, .y = 0 });

    var it = arch.rowIterator();
    while (it.next()) |row| {
        if (row.entity != 100) continue;
        const via_row = arch.columns.items()[0].getAs(Position, row.row) orelse
            return error.TestUnexpectedNull;
        const via_api = arch.getComponentAs(Position, 100) orelse
            return error.TestUnexpectedNull;
        try testing.expectEqual(via_api.*, via_row.*);
    }
}

test "ComponentIterator: returns null for a type not in this archetype" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try testing.expectEqual(@as(?Archetype.ComponentIterator(Health), null), arch.componentIterator(Health));
}

test "ComponentIterator: yields nothing on an empty archetype" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    var it = arch.componentIterator(Position) orelse return error.TestUnexpectedNull;
    try testing.expectEqual(@as(?*Position, null), it.next());
}

test "ComponentIterator: visits every component value in the column" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 0, .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 0 });
    try addPV(&arch, 1, .{ .x = 2, .y = 0 }, .{ .x = 0, .y = 0 });
    try addPV(&arch, 2, .{ .x = 3, .y = 0 }, .{ .x = 0, .y = 0 });

    var sum: f32 = 0;
    var count: usize = 0;
    var it = arch.componentIterator(Position) orelse return error.TestUnexpectedNull;
    while (it.next()) |pos| {
        sum += pos.x;
        count += 1;
    }

    try testing.expectEqual(@as(usize, 3), count);
    try testing.expectEqual(@as(f32, 6), sum); // 1 + 2 + 3
}

test "ComponentIterator: mutations through the iterator are visible via getComponentAs" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 0, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 });

    var it = arch.componentIterator(Position) orelse return error.TestUnexpectedNull;
    while (it.next()) |pos| {
        pos.x = 77.0;
    }

    const check = arch.getComponentAs(Position, 0) orelse return error.TestUnexpectedNull;
    try testing.expectEqual(@as(f32, 77.0), check.x);
}

test "ComponentIterator: reset allows full re-iteration" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 0, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 });
    try addPV(&arch, 1, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 });

    var it = arch.componentIterator(Position) orelse return error.TestUnexpectedNull;
    var first: usize = 0;
    while (it.next()) |_| first += 1;

    it.reset();
    var second: usize = 0;
    while (it.next()) |_| second += 1;

    try testing.expectEqual(@as(usize, 2), first);
    try testing.expectEqual(first, second);
}

test "stress: interleaved add and remove maintains correct len and data" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 1, .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 0 });
    try addPV(&arch, 2, .{ .x = 2, .y = 0 }, .{ .x = 0, .y = 0 });
    try addPV(&arch, 3, .{ .x = 3, .y = 0 }, .{ .x = 0, .y = 0 });
    try testing.expectEqual(@as(usize, 3), arch.len());

    _ = arch.removeEntity(1);
    try testing.expectEqual(@as(usize, 2), arch.len());
    try testing.expect(!arch.containsEntity(1));

    try addPV(&arch, 4, .{ .x = 4, .y = 0 }, .{ .x = 0, .y = 0 });
    try testing.expectEqual(@as(usize, 3), arch.len());

    try testing.expectEqual(@as(f32, 2), arch.getComponentAs(Position, 2).?.x);
    try testing.expectEqual(@as(f32, 3), arch.getComponentAs(Position, 3).?.x);
    try testing.expectEqual(@as(f32, 4), arch.getComponentAs(Position, 4).?.x);
}

test "stress: repeated removes down to zero leave archetype reusable" {
    const allocator = testing.allocator;
    var arch = try makePVArch(allocator);
    defer arch.deinit();

    try addPV(&arch, 0, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 });
    try addPV(&arch, 1, .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 0 });
    try addPV(&arch, 2, .{ .x = 2, .y = 0 }, .{ .x = 0, .y = 0 });

    _ = arch.removeEntity(0);
    _ = arch.removeEntity(1);
    _ = arch.removeEntity(2);

    try testing.expect(arch.isEmpty());

    try addPV(&arch, 99, .{ .x = 9, .y = 9 }, .{ .x = 0, .y = 0 });
    try testing.expectEqual(@as(usize, 1), arch.len());
    try testing.expect(arch.containsEntity(99));
    try testing.expectEqual(@as(f32, 9), arch.getComponentAs(Position, 99).?.x);
}
