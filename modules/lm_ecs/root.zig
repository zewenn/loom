/// Archetype-based Entity Component System module for Loom.
pub const System = @import("System.zig");
pub const World = @import("World.zig");
pub const Stage = @import("stages.zig").Stage;

/// Unique numeric identifier representing an entity within a `World`.
pub const Entity = usize;

pub const CommandBuffer = @import("commands.zig").CommandBuffer;
pub const Context = @import("Context.zig");
pub const Archetype = @import("Archetype.zig");
