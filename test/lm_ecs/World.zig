const std = @import("std");
const testing = std.testing;

const ecs = @import("lm_ecs");
const World = ecs.World;
const Entity = ecs.Entity;
const Stage = ecs.Stage;

const Position = struct { x: f32, y: f32 };
const Velocity = struct { x: f32, y: f32 };
const Health = struct { value: u32 };
const Tag = struct { id: u8 };

/// Attach components to an existing entity and flush immediately.
fn spawn(world: *World, entity: Entity, components: anytype) !void {
    if (!@import("lm_core").types.isTuple(components))
        @compileError("components must be a tuple");
    inline for (components) |c| {
        try world.command_buffer.addComponent(entity, c);
    }
    try world.flushCommandBuffer();
}

test "newEntity: each call returns a unique ID" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const a = try world.newEntity();
    const b = try world.newEntity();
    const c = try world.newEntity();

    try testing.expect(a != b);
    try testing.expect(a != c);
    try testing.expect(b != c);
}

test "isEntityAlive: true immediately after newEntity" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();
    try testing.expect(world.isEntityAlive(e));
}

test "isEntityAlive: false for an ID that was never issued" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    try testing.expect(!world.isEntityAlive(9999));
}

test "removeEntity: entity is dead after the command is applied" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();
    try world.command_buffer.removeEntity(e);
    try world.flushCommandBuffer();

    try testing.expect(!world.isEntityAlive(e));
}

test "removeEntity: removing an already-dead entity is a no-op" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();
    try world.command_buffer.removeEntity(e);
    try world.flushCommandBuffer();

    try world.command_buffer.removeEntity(e);
    try world.flushCommandBuffer();

    try testing.expect(!world.isEntityAlive(e));
}

test "removeEntity: other entities are unaffected" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const a = try world.newEntity();
    const b = try world.newEntity();
    const c = try world.newEntity();

    try world.command_buffer.removeEntity(b);
    try world.flushCommandBuffer();

    try testing.expect(world.isEntityAlive(a));
    try testing.expect(!world.isEntityAlive(b));
    try testing.expect(world.isEntityAlive(c));
}

test "entity IDs are recycled after removal" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const first = try world.newEntity();
    try world.command_buffer.removeEntity(first);
    try world.flushCommandBuffer();

    const recycled = try world.newEntity();
    try testing.expectEqual(first, recycled);
    try testing.expect(world.isEntityAlive(recycled));
}

test "component is not visible before applyCommandBuffer" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();
    try world.command_buffer.addComponent(e, Position{ .x = 1, .y = 2 });

    try testing.expectEqual(@as(?*Position, null), world.getComponent(Position, e));

    try world.flushCommandBuffer();

    try testing.expect(world.getComponent(Position, e) != null);
}

test "entity spawned via makeEntity is not alive until applyCommandBuffer" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const pre_existing = try world.newEntity();
    try world.command_buffer.makeEntity(.{Position{ .x = 0, .y = 0 }});

    try world.flushCommandBuffer();

    try testing.expect(world.isEntityAlive(pre_existing));
}

test "getComponent: returns null for an entity with no components" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();
    try testing.expectEqual(@as(?*Position, null), world.getComponent(Position, e));
}

test "getComponent: returns null for a type the entity does not have" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();
    try spawn(&world, e, .{Position{ .x = 0, .y = 0 }});

    try testing.expectEqual(@as(?*Health, null), world.getComponent(Health, e));
}

test "getComponent: returns null for a dead entity" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();
    try spawn(&world, e, .{Position{ .x = 0, .y = 0 }});

    try world.command_buffer.removeEntity(e);
    try world.flushCommandBuffer();

    try testing.expectEqual(@as(?*Position, null), world.getComponent(Position, e));
}

test "getComponent: correct value is returned after add" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();
    try spawn(&world, e, .{Position{ .x = 3.14, .y = -2.71 }});

    const pos = world.getComponent(Position, e) orelse return error.TestUnexpectedNull;
    try testing.expectEqual(@as(f32, 3.14), pos.x);
    try testing.expectEqual(@as(f32, -2.71), pos.y);
}

test "getComponent: multiple components on the same entity are all accessible" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();
    try spawn(&world, e, .{
        Position{ .x = 1, .y = 2 },
        Velocity{ .x = 3, .y = 4 },
        Health{ .value = 100 },
    });

    try testing.expectEqual(@as(f32, 1), world.getComponent(Position, e).?.x);
    try testing.expectEqual(@as(f32, 3), world.getComponent(Velocity, e).?.x);
    try testing.expectEqual(@as(u32, 100), world.getComponent(Health, e).?.value);
}

test "getComponent: separate entities have independent component data" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const a = try world.newEntity();
    const b = try world.newEntity();

    try spawn(&world, a, .{Position{ .x = 1, .y = 1 }});
    try spawn(&world, b, .{Position{ .x = 2, .y = 2 }});

    try testing.expectEqual(@as(f32, 1), world.getComponent(Position, a).?.x);
    try testing.expectEqual(@as(f32, 2), world.getComponent(Position, b).?.x);
}

test "getComponent: returned pointer is live — mutation persists" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();
    try spawn(&world, e, .{Position{ .x = 0, .y = 0 }});

    world.getComponent(Position, e).?.x = 99.0;

    try testing.expectEqual(@as(f32, 99.0), world.getComponent(Position, e).?.x);
}

test "adding the same component twice overwrites the first value" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();
    try spawn(&world, e, .{Position{ .x = 1, .y = 1 }});
    try spawn(&world, e, .{Position{ .x = 42, .y = -7 }});

    const pos = world.getComponent(Position, e) orelse return error.TestUnexpectedNull;
    try testing.expectEqual(@as(f32, 42), pos.x);
    try testing.expectEqual(@as(f32, -7), pos.y);
}

test "overwriting a component does not disturb other components" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();
    try spawn(&world, e, .{
        Position{ .x = 5, .y = 5 },
        Health{ .value = 50 },
    });
    try spawn(&world, e, .{Position{ .x = 99, .y = 99 }});

    try testing.expectEqual(@as(u32, 50), world.getComponent(Health, e).?.value);
}

test "removeComponent: component is inaccessible after removal" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();
    try spawn(&world, e, .{Position{ .x = 1, .y = 1 }});

    try world.command_buffer.removeComponent(e, Position);
    try world.flushCommandBuffer();

    try testing.expectEqual(@as(?*Position, null), world.getComponent(Position, e));
}

test "removeComponent: surviving components are still accessible" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();
    try spawn(&world, e, .{
        Position{ .x = 3, .y = 4 },
        Health{ .value = 77 },
    });

    try world.command_buffer.removeComponent(e, Position);
    try world.flushCommandBuffer();

    try testing.expectEqual(@as(?*Position, null), world.getComponent(Position, e));
    try testing.expectEqual(@as(u32, 77), world.getComponent(Health, e).?.value);
}

test "removeComponent: removing a component the entity does not have is a no-op" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();
    try spawn(&world, e, .{Position{ .x = 1, .y = 1 }});

    try world.command_buffer.removeComponent(e, Health);
    try world.flushCommandBuffer();

    try testing.expect(world.isEntityAlive(e));
    try testing.expect(world.getComponent(Position, e) != null);
}

test "removeComponent: entity is still alive after its last component is removed" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();
    try spawn(&world, e, .{Position{ .x = 0, .y = 0 }});

    try world.command_buffer.removeComponent(e, Position);
    try world.flushCommandBuffer();

    try testing.expect(world.isEntityAlive(e));
}

test "adding a component back after removal gives the new value" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();
    try spawn(&world, e, .{Health{ .value = 10 }});

    try world.command_buffer.removeComponent(e, Health);
    try world.flushCommandBuffer();

    try spawn(&world, e, .{Health{ .value = 99 }});

    try testing.expectEqual(@as(u32, 99), world.getComponent(Health, e).?.value);
}

test "adding a second component preserves the first" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();
    try spawn(&world, e, .{Position{ .x = 7, .y = 8 }});
    try spawn(&world, e, .{Velocity{ .x = -1, .y = -2 }});

    try testing.expectEqual(@as(f32, 7), world.getComponent(Position, e).?.x);
    try testing.expectEqual(@as(f32, 8), world.getComponent(Position, e).?.y);
    try testing.expectEqual(@as(f32, -1), world.getComponent(Velocity, e).?.x);
}

test "removing one component preserves the values of all others" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();
    try spawn(&world, e, .{
        Position{ .x = 1, .y = 2 },
        Velocity{ .x = 3, .y = 4 },
        Health{ .value = 55 },
    });

    try world.command_buffer.removeComponent(e, Velocity);
    try world.flushCommandBuffer();

    try testing.expectEqual(@as(f32, 1), world.getComponent(Position, e).?.x);
    try testing.expectEqual(@as(f32, 2), world.getComponent(Position, e).?.y);
    try testing.expectEqual(@as(u32, 55), world.getComponent(Health, e).?.value);
}

test "component data on a bystander entity is unchanged across neighbour transitions" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const a = try world.newEntity();
    const b = try world.newEntity();

    try spawn(&world, a, .{Position{ .x = 1, .y = 1 }});
    try spawn(&world, b, .{Position{ .x = 2, .y = 2 }});

    try spawn(&world, a, .{Health{ .value = 10 }});

    try testing.expectEqual(@as(f32, 2), world.getComponent(Position, b).?.x);
    try testing.expectEqual(@as(f32, 2), world.getComponent(Position, b).?.y);
}

test "round-trip: add, remove, re-add a component produces the new value" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();

    try spawn(&world, e, .{Health{ .value = 1 }});
    try world.command_buffer.removeComponent(e, Health);
    try world.flushCommandBuffer();
    try spawn(&world, e, .{Health{ .value = 2 }});
    try world.command_buffer.removeComponent(e, Health);
    try world.flushCommandBuffer();
    try spawn(&world, e, .{Health{ .value = 3 }});

    try testing.expectEqual(@as(u32, 3), world.getComponent(Health, e).?.value);
}

test "makeEntity: entity is alive after the buffer is flushed" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const before = world.next_entity_index;
    try world.command_buffer.makeEntity(.{Position{ .x = 0, .y = 0 }});
    try world.flushCommandBuffer();

    try testing.expect(world.next_entity_index > before);
}

test "makeEntity: all supplied components are accessible after apply" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const expected_id: Entity = world.next_entity_index;

    try world.command_buffer.makeEntity(.{
        Position{ .x = 5, .y = 6 },
        Health{ .value = 100 },
    });
    try world.flushCommandBuffer();

    try testing.expect(world.isEntityAlive(expected_id));
    try testing.expectEqual(@as(f32, 5), world.getComponent(Position, expected_id).?.x);
    try testing.expectEqual(@as(u32, 100), world.getComponent(Health, expected_id).?.value);
}

test "makeEntity: every entity receives a Context component" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const expected_id: Entity = world.next_entity_index;

    try world.command_buffer.makeEntity(.{Position{ .x = 0, .y = 0 }});
    try world.flushCommandBuffer();

    const ctx = world.getComponent(ecs.Context, expected_id) orelse
        return error.TestUnexpectedNull;

    try testing.expectEqual(&world, ctx.world);
    try testing.expectEqual(expected_id, ctx.entity);
}

test "makeEntity: Context of each entity points to that entity's own ID" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const id_a: Entity = world.next_entity_index;
    try world.command_buffer.makeEntity(.{Position{ .x = 0, .y = 0 }});
    try world.flushCommandBuffer();

    const id_b: Entity = world.next_entity_index;
    try world.command_buffer.makeEntity(.{Position{ .x = 0, .y = 0 }});
    try world.flushCommandBuffer();

    try testing.expectEqual(id_a, world.getComponent(ecs.Context, id_a).?.entity);
    try testing.expectEqual(id_b, world.getComponent(ecs.Context, id_b).?.entity);
}

var g_visited_count: usize = 0;
var g_second_system_ran: bool = false;

fn countPositions(positions: []Position) anyerror!void {
    g_visited_count += positions.len;
}

fn countVelocities(velocities: []Velocity) anyerror!void {
    g_visited_count += velocities.len;
}

fn requireBoth(positions: []Position, velocities: []Velocity) anyerror!void {
    if (positions.len != velocities.len) return error.LengthMismatch;
    g_visited_count += positions.len;
}

fn secondSystem(positions: []Position) anyerror!void {
    _ = positions;
    g_second_system_ran = true;
}

fn sumPositionX(positions: []Position, velocities: []const Velocity) anyerror!void {
    for (positions, velocities) |*pos, vel| {
        pos.x += vel.x;
        pos.y += vel.y;
    }
}

test "runStage: system runs on all entities with the required component" {
    g_visited_count = 0;
    var world = World.init(testing.allocator);
    defer world.deinit();

    const a = try world.newEntity();
    const b = try world.newEntity();
    const c = try world.newEntity();

    try spawn(&world, a, .{Position{ .x = 0, .y = 0 }});
    try spawn(&world, b, .{Position{ .x = 0, .y = 0 }});
    try spawn(&world, c, .{Position{ .x = 0, .y = 0 }});

    try world.command_buffer.addSystem(.update, countPositions);
    try world.flushCommandBuffer();

    try world.runStage(.update);

    try testing.expectEqual(@as(usize, 3), g_visited_count);
}

test "runStage: system skips entities missing a required component" {
    g_visited_count = 0;
    var world = World.init(testing.allocator);
    defer world.deinit();

    const with_pos = try world.newEntity();
    const without_pos = try world.newEntity();

    try spawn(&world, with_pos, .{Position{ .x = 0, .y = 0 }});
    try spawn(&world, without_pos, .{Health{ .value = 10 }});

    try world.command_buffer.addSystem(.update, countPositions);
    try world.flushCommandBuffer();

    try world.runStage(.update);

    try testing.expectEqual(@as(usize, 1), g_visited_count);
}

test "runStage: multi-component system skips entities missing any one component" {
    g_visited_count = 0;
    var world = World.init(testing.allocator);
    defer world.deinit();

    const both = try world.newEntity();
    const pos_only = try world.newEntity();
    const vel_only = try world.newEntity();

    try spawn(&world, both, .{
        Position{ .x = 0, .y = 0 },
        Velocity{ .x = 0, .y = 0 },
    });
    try spawn(&world, pos_only, .{Position{ .x = 0, .y = 0 }});
    try spawn(&world, vel_only, .{Velocity{ .x = 0, .y = 0 }});

    try world.command_buffer.addSystem(.update, requireBoth);
    try world.flushCommandBuffer();

    try world.runStage(.update);

    try testing.expectEqual(@as(usize, 1), g_visited_count);
}

test "runStage: system does not run in a stage it was not registered for" {
    g_visited_count = 0;
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();
    try spawn(&world, e, .{Position{ .x = 0, .y = 0 }});

    try world.command_buffer.addSystem(.update, countPositions);
    try world.flushCommandBuffer();

    try world.runStage(.draw);

    try testing.expectEqual(@as(usize, 0), g_visited_count);
}

test "runStage: multiple systems in the same stage all execute" {
    g_visited_count = 0;
    g_second_system_ran = false;
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();
    try spawn(&world, e, .{Position{ .x = 0, .y = 0 }});

    try world.command_buffer.addSystem(.update, countPositions);
    try world.command_buffer.addSystem(.update, secondSystem);
    try world.flushCommandBuffer();

    try world.runStage(.update);

    try testing.expectEqual(@as(usize, 1), g_visited_count);
    try testing.expect(g_second_system_ran);
}

test "runStage: system correctly mutates component data" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();
    try spawn(&world, e, .{
        Position{ .x = 0, .y = 0 },
        Velocity{ .x = 3, .y = -1 },
    });

    try world.command_buffer.addSystem(.update, sumPositionX);
    try world.flushCommandBuffer();

    try world.runStage(.update);

    try testing.expectEqual(@as(f32, 3), world.getComponent(Position, e).?.x);
    try testing.expectEqual(@as(f32, -1), world.getComponent(Position, e).?.y);
}

test "runStage: mutation accumulates across multiple stage runs" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();
    try spawn(&world, e, .{
        Position{ .x = 0, .y = 0 },
        Velocity{ .x = 1, .y = 2 },
    });

    try world.command_buffer.addSystem(.update, sumPositionX);
    try world.flushCommandBuffer();

    try world.runStage(.update);
    try world.runStage(.update);
    try world.runStage(.update);

    try testing.expectEqual(@as(f32, 3), world.getComponent(Position, e).?.x);
    try testing.expectEqual(@as(f32, 6), world.getComponent(Position, e).?.y);
}

test "runStage: removed entity is not visited in subsequent stage runs" {
    g_visited_count = 0;
    var world = World.init(testing.allocator);
    defer world.deinit();

    const a = try world.newEntity();
    const b = try world.newEntity();

    try spawn(&world, a, .{Position{ .x = 0, .y = 0 }});
    try spawn(&world, b, .{Position{ .x = 0, .y = 0 }});

    try world.command_buffer.addSystem(.update, countPositions);
    try world.flushCommandBuffer();

    try world.runStage(.update);
    try testing.expectEqual(@as(usize, 2), g_visited_count);

    g_visited_count = 0;
    try world.command_buffer.removeEntity(a);
    try world.flushCommandBuffer();

    try world.runStage(.update);
    try testing.expectEqual(@as(usize, 1), g_visited_count);
}

test "runStage: entity whose component is removed is not visited by that system again" {
    g_visited_count = 0;
    var world = World.init(testing.allocator);
    defer world.deinit();

    const a = try world.newEntity();
    const b = try world.newEntity();

    try spawn(&world, a, .{Position{ .x = 0, .y = 0 }});
    try spawn(&world, b, .{
        Position{ .x = 0, .y = 0 },
        Velocity{ .x = 0, .y = 0 },
    });

    try world.command_buffer.addSystem(.update, countPositions);
    try world.flushCommandBuffer();

    try world.runStage(.update);
    try testing.expectEqual(@as(usize, 2), g_visited_count);

    g_visited_count = 0;
    try world.command_buffer.removeComponent(b, Position);
    try world.flushCommandBuffer();

    try world.runStage(.update);
    try testing.expectEqual(@as(usize, 1), g_visited_count);
}

test "runStage: system sees newly added entity on the stage after it is created" {
    g_visited_count = 0;
    var world = World.init(testing.allocator);
    defer world.deinit();

    try world.command_buffer.addSystem(.update, countPositions);
    try world.flushCommandBuffer();

    try world.runStage(.update);
    try testing.expectEqual(@as(usize, 0), g_visited_count);

    const e = try world.newEntity();
    try spawn(&world, e, .{Position{ .x = 0, .y = 0 }});

    try world.runStage(.update);
    try testing.expectEqual(@as(usize, 1), g_visited_count);
}

test "removed system does not run in subsequent stages" {
    g_visited_count = 0;
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();
    try spawn(&world, e, .{Position{ .x = 0, .y = 0 }});

    try world.command_buffer.addSystem(.update, countPositions);
    try world.flushCommandBuffer();

    try world.runStage(.update);
    try testing.expectEqual(@as(usize, 1), g_visited_count);

    g_visited_count = 0;
    try world.command_buffer.removeSystem(.update, countPositions);
    try world.flushCommandBuffer();

    try world.runStage(.update);
    try testing.expectEqual(@as(usize, 0), g_visited_count);
}

test "stress: many entities with different component combinations are all handled" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    var ids: [10]Entity = undefined;
    for (&ids) |*id| id.* = try world.newEntity();

    for (ids[0..3]) |id| try spawn(&world, id, .{Position{ .x = 1, .y = 1 }});
    for (ids[3..6]) |id| try spawn(&world, id, .{
        Position{ .x = 2, .y = 2 },
        Velocity{ .x = 1, .y = 0 },
    });
    for (ids[6..8]) |id| try spawn(&world, id, .{Health{ .value = 50 }});
    for (ids[8..10]) |id| try spawn(&world, id, .{
        Position{ .x = 3, .y = 3 },
        Velocity{ .x = 0, .y = 1 },
        Health{ .value = 100 },
    });

    for (ids[0..3]) |id| {
        try testing.expect(world.isEntityAlive(id));
        try testing.expectEqual(@as(f32, 1), world.getComponent(Position, id).?.x);
        try testing.expectEqual(@as(?*Velocity, null), world.getComponent(Velocity, id));
    }
    for (ids[3..6]) |id| {
        try testing.expectEqual(@as(f32, 2), world.getComponent(Position, id).?.x);
        try testing.expectEqual(@as(f32, 1), world.getComponent(Velocity, id).?.x);
    }
    for (ids[6..8]) |id| {
        try testing.expectEqual(@as(?*Position, null), world.getComponent(Position, id));
        try testing.expectEqual(@as(u32, 50), world.getComponent(Health, id).?.value);
    }
    for (ids[8..10]) |id| {
        try testing.expectEqual(@as(f32, 3), world.getComponent(Position, id).?.x);
        try testing.expectEqual(@as(u32, 100), world.getComponent(Health, id).?.value);
    }
}

test "stress: interleaved add, remove, overwrite across multiple applies" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const e = try world.newEntity();

    try spawn(&world, e, .{Position{ .x = 1, .y = 0 }});
    try spawn(&world, e, .{Health{ .value = 10 }});

    try world.command_buffer.removeComponent(e, Position);
    try world.flushCommandBuffer();

    try spawn(&world, e, .{Velocity{ .x = 5, .y = 0 }});

    try world.command_buffer.removeComponent(e, Health);
    try world.flushCommandBuffer();

    try spawn(&world, e, .{Position{ .x = 99, .y = 99 }});

    try testing.expectEqual(@as(f32, 99), world.getComponent(Position, e).?.x);
    try testing.expectEqual(@as(f32, 5), world.getComponent(Velocity, e).?.x);
    try testing.expectEqual(@as(?*Health, null), world.getComponent(Health, e));
    try testing.expect(world.isEntityAlive(e));
}

test "stress: system visit count matches entity count across archetype boundaries" {
    g_visited_count = 0;
    var world = World.init(testing.allocator);
    defer world.deinit();

    try world.command_buffer.addSystem(.update, countPositions);
    try world.flushCommandBuffer();

    for (0..3) |_| {
        const e = try world.newEntity();
        try spawn(&world, e, .{Position{ .x = 0, .y = 0 }});
    }
    for (0..2) |_| {
        const e = try world.newEntity();
        try spawn(&world, e, .{
            Position{ .x = 0, .y = 0 },
            Health{ .value = 1 },
        });
    }

    try world.runStage(.update);

    try testing.expectEqual(@as(usize, 5), g_visited_count);
}

test "stress: mutation system applied to multiple archetypes all update correctly" {
    var world = World.init(testing.allocator);
    defer world.deinit();

    const a = try world.newEntity();
    const b = try world.newEntity();

    try spawn(&world, a, .{
        Position{ .x = 0, .y = 0 },
        Velocity{ .x = 1, .y = 0 },
    });
    try spawn(&world, b, .{
        Position{ .x = 0, .y = 0 },
        Velocity{ .x = 0, .y = 2 },
        Health{ .value = 10 }, // different archetype from a
    });

    try world.command_buffer.addSystem(.update, sumPositionX);
    try world.flushCommandBuffer();

    try world.runStage(.update);

    try testing.expectEqual(@as(f32, 1), world.getComponent(Position, a).?.x);
    try testing.expectEqual(@as(f32, 0), world.getComponent(Position, a).?.y);
    try testing.expectEqual(@as(f32, 0), world.getComponent(Position, b).?.x);
    try testing.expectEqual(@as(f32, 2), world.getComponent(Position, b).?.y);
}
