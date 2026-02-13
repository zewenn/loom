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
const MyThirdComponent = struct {
    inner: usize = 0,
};

fn myInitSystem(component: *MyComponent) !void {
    component.inner = 5;
}
fn myOtherInitSystem(component: *MyOtherComponent) !void {
    component.inner = 10;
}
fn myComboInitSystem(res: *MyThirdComponent, component: *const MyComponent, component1: *const MyOtherComponent) !void {
    res.inner = component.inner + component1.inner;
}

fn myContextSystem(ctx: *ecs.Context, _: *const MyComponent) !void {
    try std.testing.expect(ctx.getComponent(MyComponent) != null);
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

test "removeEntity" {
    var world: World = .init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.newEntity();
    try std.testing.expectEqual(0, entity);

    try world.command_buffer.addComponent(entity, MyComponent{ .inner = 67 });
    try world.applyCommandBuffer();

    const result = world.getComponent(MyComponent, entity).?.*;
    try std.testing.expect(world.isEntityAlive(entity));
    try std.testing.expectEqual(67, result.inner);

    try world.command_buffer.removeEntity(entity);
    try world.applyCommandBuffer();

    try std.testing.expectEqual(null, world.getComponent(MyComponent, entity));
    try std.testing.expect(!world.isEntityAlive(entity));
}

test "addComponent / getComponent" {
    var world: World = .init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.newEntity();
    try world.command_buffer.addComponent(entity, MyComponent{ .inner = 67 });
    try world.applyCommandBuffer();

    const result = world.getComponent(MyComponent, entity).?;
    try std.testing.expectEqual(67, result.inner);
}

test "removeComponent" {
    var world: World = .init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.newEntity();
    try world.command_buffer.addComponent(entity, MyComponent{ .inner = 67 });
    try world.applyCommandBuffer();

    const result = world.getComponent(MyComponent, entity).?;
    try std.testing.expectEqual(67, result.inner);

    try world.command_buffer.removeComponent(entity, MyComponent);
    try world.applyCommandBuffer();

    try std.testing.expectEqual(null, world.getComponent(MyComponent, entity));
}

test "addSystem / runSystem" {
    var world: World = .init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.newEntity();

    try world.command_buffer.addComponent(entity, MyComponent{ .inner = 67 });
    try world.command_buffer.addComponent(entity, MyOtherComponent{ .inner = 67 });

    try world.command_buffer.addSystem(.init, myInitSystem);
    try world.command_buffer.addSystem(.init, myContextSystem);
    try world.command_buffer.addSystem(.load, myLoadSystem);

    try world.applyCommandBuffer();

    const result = world.getComponent(MyComponent, entity).?;

    try std.testing.expectEqual(67, result.inner);

    try world.runStage(.init);

    try std.testing.expectEqual(5, result.inner);

    try world.runStage(.load);

    try std.testing.expectEqual(73, result.inner);
}

test "addSystem / runSystem without valid component" {
    var world: World = .init(std.testing.allocator);
    defer world.deinit();

    _ = try world.newEntity();

    try world.command_buffer.addSystem(.init, myInitSystem);
    try world.applyCommandBuffer();

    try world.runStage(.init);
}

test "addSystem / runSystem with other type of component" {
    var world: World = .init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.newEntity();
    try world.command_buffer.addComponent(entity, MyOtherComponent{ .inner = 67 });
    try world.command_buffer.addSystem(.init, myInitSystem);

    try world.applyCommandBuffer();

    const result = world.getComponent(MyOtherComponent, entity).?;

    try std.testing.expectEqual(67, result.inner);

    try world.runStage(.init);

    try std.testing.expectEqual(67, result.inner);
}

test "multiple entities in multiple systems" {
    var world: World = .init(std.testing.allocator);
    defer world.deinit();

    const entity0 = try world.newEntity();
    const entity1 = try world.newEntity();
    const entity2 = try world.newEntity();

    try world.command_buffer.addComponents(entity0, .{
        MyComponent{ .inner = 0 },
        MyOtherComponent{ .inner = 0 },
        MyThirdComponent{ .inner = 0 },
    });

    try world.command_buffer.addComponent(entity1, MyOtherComponent{ .inner = 2 });
    try world.command_buffer.addComponent(entity2, MyComponent{ .inner = 3 });

    try world.command_buffer.addSystem(.init, myInitSystem);
    try world.command_buffer.addSystem(.init, myOtherInitSystem);
    try world.command_buffer.addSystem(.init, myComboInitSystem);

    try world.applyCommandBuffer();

    const e0_third = world.getComponent(MyThirdComponent, entity0).?;
    const e1_other = world.getComponent(MyOtherComponent, entity1).?;
    const e2_mycmp = world.getComponent(MyComponent, entity2).?;

    try std.testing.expectEqual(0, e0_third.inner);
    try std.testing.expectEqual(2, e1_other.inner);
    try std.testing.expectEqual(3, e2_mycmp.inner);

    try world.runStage(.init);
    try world.runStage(.init);

    try std.testing.expectEqual(15, e0_third.inner);
    try std.testing.expectEqual(10, e1_other.inner);
    try std.testing.expectEqual(5, e2_mycmp.inner);
}

test "removeSystem" {
    var world: World = .init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.newEntity();
    try world.command_buffer.addComponent(entity, MyComponent{ .inner = 67 });
    try world.command_buffer.addSystem(.init, myInitSystem);

    try world.applyCommandBuffer();

    const result = world.getComponent(MyComponent, entity).?;

    try std.testing.expectEqual(67, result.inner);

    try world.runStage(.init);

    try std.testing.expectEqual(5, result.inner);
    result.inner = 67;

    try world.command_buffer.removeSystem(.init, myInitSystem);
    try world.applyCommandBuffer();

    try world.runStage(.init);

    try std.testing.expectEqual(67, result.inner);
}
