pub const System = @import("System.zig");
pub const World = @import("World.zig");
pub const Stage = @import("stages.zig").Stage;
pub const Entity = usize;
pub const CleanupMarks = @import("CleanupMarks.zig");

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
