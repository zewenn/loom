const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("lm_core");
const ecs = @import("lm_ecs");

const World = ecs.World;

const MyComponent = struct {
    inner: usize = 0,
};
const MyOtherComponent = struct {
    inner: u8 = 0,
};

fn myInitSystem(component: *MyComponent) !void {
    component.inner = 42;
}
fn myOtherInitSystem(component: *MyOtherComponent) !void {
    component.inner = 42;
}
fn myComboInitSystem(component: *MyComponent, component1: *MyOtherComponent) !void {
    component.inner = 42;
    component1.inner = 2;
}

fn myLoadSystem(component: *MyComponent) !void {
    component.inner = 73;
}

test "init / deinit" {
    var world: World = .init(std.testing.allocator);
    defer world.deinit();
}

test "newEntity" {
    var world: World = .init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.newEntity();
    try std.testing.expectEqual(0, entity);

    const entity1 = try world.newEntity();
    try std.testing.expectEqual(1, entity1);
}

test "makeEntity" {
    var world: World = .init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.makeEntity(.{
        MyComponent{ .inner = 67 },
    });

    const result = world.getComponent(MyComponent, entity).?;
    try std.testing.expectEqual(67, result.inner);
}

test "removeEntity" {
    var world: World = .init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.makeEntity(.{
        MyComponent{ .inner = 67 },
    });

    const result = world.getComponent(MyComponent, entity).?.*;
    try std.testing.expect(world.isEntityAlive(entity));
    try std.testing.expectEqual(67, result.inner);

    try world.removeEntity(entity);
    world.runCleanup();

    try std.testing.expectEqual(null, world.getComponent(MyComponent, entity));
    try std.testing.expect(!world.isEntityAlive(entity));
}

test "addComponent / getComponent" {
    var world: World = .init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.newEntity();
    try world.addComponent(entity, MyComponent{ .inner = 67 });

    const result = world.getComponent(MyComponent, entity).?;
    try std.testing.expectEqual(67, result.inner);
}

test "removeComponent" {
    var world: World = .init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.newEntity();
    try world.addComponent(entity, MyComponent{ .inner = 67 });

    const result = world.getComponent(MyComponent, entity).?;
    try std.testing.expectEqual(67, result.inner);

    try world.removeComponent(entity, MyComponent);
    world.runCleanup();

    try std.testing.expectEqual(null, world.getComponent(MyComponent, entity));
}

test "addSystem / runSystem" {
    var world: World = .init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.newEntity();
    try world.addComponent(entity, MyComponent{ .inner = 67 });
    try world.addComponent(entity, MyOtherComponent{ .inner = 67 });
    try world.addSystem(.init, myInitSystem);
    try world.addSystem(.load, myLoadSystem);

    const result = world.getComponent(MyComponent, entity).?;

    try std.testing.expectEqual(67, result.inner);

    try world.runStage(.init);

    try std.testing.expectEqual(42, result.inner);

    try world.runStage(.load);

    try std.testing.expectEqual(73, result.inner);
}

test "addSystem / runSystem without valid component" {
    var world: World = .init(std.testing.allocator);
    defer world.deinit();

    _ = try world.newEntity();

    try world.addSystem(.init, myInitSystem);
    try world.runStage(.init);
}

test "addSystem / runSystem with other type of component" {
    var world: World = .init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.newEntity();
    try world.addComponent(entity, MyOtherComponent{ .inner = 67 });

    const result = world.getComponent(MyOtherComponent, entity).?;

    try std.testing.expectEqual(67, result.inner);

    try world.addSystem(.init, myInitSystem);
    try world.runStage(.init);

    try std.testing.expectEqual(67, result.inner);
}

test "removeSystem" {
    var world: World = .init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.newEntity();
    try world.addComponent(entity, MyComponent{ .inner = 67 });
    try world.addSystem(.init, myInitSystem);

    const result = world.getComponent(MyComponent, entity).?;

    try std.testing.expectEqual(67, result.inner);

    try world.runStage(.init);

    try std.testing.expectEqual(42, result.inner);
    result.inner = 67;

    try world.removeSystem(.init, myInitSystem);
    world.runCleanup();

    try world.runStage(.init);

    try std.testing.expectEqual(67, result.inner);
}
