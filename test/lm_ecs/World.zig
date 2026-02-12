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

fn mySystem(component: *MyComponent) !void {
    component.inner = 42;
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

test "addComponent / getComponent" {
    var world: World = .init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.newEntity();
    try world.addComponent(entity, MyComponent{ .inner = 67 });

    const result = world.getComponent(MyComponent, entity).?;
    try std.testing.expectEqual(67, result.inner);
}

test "addSystem / runSystem" {
    var world: World = .init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.newEntity();
    try world.addComponent(entity, MyComponent{ .inner = 67 });

    const result = world.getComponent(MyComponent, entity).?;

    try std.testing.expectEqual(67, result.inner);

    try world.addSystem(mySystem);
    try world.runSystems();

    try std.testing.expectEqual(42, result.inner);
}

test "addSystem / runSystem without valid component" {
    var world: World = .init(std.testing.allocator);
    defer world.deinit();

    _ = try world.newEntity();

    try world.addSystem(mySystem);
    try world.runSystems();
}

test "addSystem / runSystem with other type of component" {
    var world: World = .init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.newEntity();
    try world.addComponent(entity, MyOtherComponent{ .inner = 67 });

    const result = world.getComponent(MyOtherComponent, entity).?;

    try std.testing.expectEqual(67, result.inner);

    try world.addSystem(mySystem);
    try world.runSystems();

    try std.testing.expectEqual(67, result.inner);
}
