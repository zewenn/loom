pub const ComponentStore = @import("ComponentStore.zig");
pub const PendingComponent = @import("PendingComponent.zig");

// Plan:
// const MyComponent = struct { ... };
// const Player = world.newEntity(.{ MyComponent{}, SomethingElse{}, ElseElse{} });
// fn mySystem(component1: *MyComponent, component2: *const SomethingElse, component3: *ElseElse) !void { ... }
// world.useSystem([------------], mySystem);
//                  .init
//                  .load
//                  .pre_update
//                  .update
//                  .post_update
//                  .tick
//                  .draw
//                  .deinit
