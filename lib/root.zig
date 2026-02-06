const std = @import("std");
const builtin = @import("builtin");
const Allocator = @import("std").mem.Allocator;

// Types and Basic Utilities
// --------------------------------------------------------------------------------------------------------------

const rl = @import("raylib");
const clay = @import("zclay");
const uuid = @import("uuid");

pub const deps = if (builtin.is_test)
    struct {}
else
    struct {
        pub const rl = @import("raylib");
        pub const clay = @import("zclay");
        pub const uuid = @import("uuid");
    };

pub const window = @import("window.zig");

pub const types = @import("types/types.zig");
pub const Array = types.Array;
pub const List = types.List;

var seed: u64 = undefined;
var xoshiro: std.Random.Xoshiro256 = .init(0);
pub var random: std.Random = xoshiro.random();

pub const Vector2 = rl.Vector2;
pub const Vector3 = rl.Vector3;
pub const Vector4 = rl.Vector4;
pub const Rectangle = rl.Rectangle;
pub const Color = rl.Color;
pub const Texture = rl.Texture;

pub const ecs = @import("ecs/ecs.zig");
pub const GlobalBehaviour = ecs.Behaviour(Scene);
pub const Behaviour = ecs.Behaviour(Entity);
pub const Entity = ecs.Entity;
pub const Prefab = ecs.Prefab;

pub const eventloop = @import("eventloop/eventloop.zig");
pub const Scene = eventloop.Scene;
pub const SceneController = eventloop.SceneController;

pub const UUIDv7 = uuid.v7.new;

pub const Dimensions = clay.Dimensions;

pub const Transform = @import("builtin-components/Transform.zig");
pub const Renderer = @import("builtin-components/Renderer.zig");
pub const RectangleCollider = @import("builtin-components/collision.zig").RectangleCollider;
pub const CameraTarget = @import("builtin-components/CameraTarget.zig");
pub const Animator = @import("builtin-components/animator/Animator.zig");
pub const Animation = @import("builtin-components/animator/Animation.zig");
pub const Keyframe = @import("builtin-components/animator/Keyframe.zig");
pub const interpolation = @import("builtin-components/animator/interpolation.zig");

pub const Camera = @import("Camera.zig");

pub const assets = @import("assets.zig");
pub const audio = @import("audio.zig");
pub const display = @import("display.zig");
pub const time = @import("time.zig");
pub const input = @import("input.zig");
pub const ui = @import("ui/ui.zig");
pub const sort = @import("sort.zig");

pub const keyboard = input.keyboard;
pub const mouse = input.mouse;
pub const gamepad = input.gamepad;

pub const useAssetPaths = assets.files.paths.use;
const program = struct {
    var dispatcher: SceneController = undefined;
    var running: bool = true;
};

pub fn quit() void {
    program.running = false;
}

pub fn assert(statement: bool, comptime fail_msg: []const u8) void {
    assertFmt(statement, fail_msg, .{});
}

pub fn assertFmt(statement: bool, comptime fail_msg: []const u8, fmt: anytype) void {
    if (statement) return;

    std.log.err(fail_msg, fmt);
    @panic("ASSERTION FAILIURE");
}

pub fn deprecated(comptime msg: []const u8) void {
    if (builtin.is_test) return;

    @compileError("[DEPRECATED] " ++ msg);
}

// Creating the project
// --------------------------------------------------------------------------------------------------------------

pub const ProjectConfig = struct {
    pub const WindowConfig = struct {
        title: [:0]const u8 = "untitled loom project",
        size: Vector2 = .init(1280, 720),

        restore_state: bool = false,

        borderless: bool = false,
        fullscreen: bool = false,
        resizable: bool = false,

        fps_target: i32 = 256,
        vsync: bool = false,

        clear_color: rl.Color = .white,
        exit_key: input.KeyboardKey = .escape,
    };

    pub const AssetPathConfig = struct {
        debug: ?[]const u8 = null,
        release: ?[]const u8 = null,
    };

    window: WindowConfig = .{},
    asset_paths: AssetPathConfig = .{},

    raylib_log_level: rl.TraceLogLevel = .warning,
};

pub fn project(config: ProjectConfig) *const fn (void) void {
    rl.setTraceLogLevel(config.raylib_log_level);

    time.init();

    window.init();
    audio.init();

    window.title.set(config.window.title);
    window.size.set(config.window.size);

    window.restore_state.set(config.window.restore_state);

    window.borderless.set(config.window.borderless);
    window.fullscreen.set(config.window.fullscreen);
    window.resizing.set(config.window.resizable);

    window.vsync.set(config.window.vsync);
    window.fpsTarget.set(config.window.fps_target);
    window.clear_color = config.window.clear_color;
    window.setExitKey(config.window.exit_key);

    assets.files.paths.use(.{
        .debug = config.asset_paths.debug,
        .release = config.asset_paths.release,
    });

    window.restore_state.load() catch {
        std.log.err("failed to load window state", .{});
    };

    display.init();
    ui.init(allocators.arena()) catch @panic("UI INIT FAILED");
    program.dispatcher = .init(allocators.arena());

    std.posix.getrandom(std.mem.asBytes(&seed)) catch {
        seed = coerceTo(u64, rl.getTime()).?;
    };
    xoshiro = std.Random.DefaultPrng.init(seed);
    random = xoshiro.random();

    return projectLoopAndDeinit;
}

fn projectLoopAndDeinit(_: void) void {
    program.dispatcher.setActive("default") catch {
        std.log.info("no default scene", .{});
    };

    while (!window.shouldClose() and program.running) {
        if (keyboard.getKeyDown(.enter) and keyboard.getKey(.left_alt))
            window.toggleDebugMode();

        time.update();
        display.reset();

        const mouse_position = rl.getMousePosition();
        clay.setPointerState(.{
            .x = mouse_position.x,
            .y = mouse_position.y,
        }, rl.isMouseButtonDown(.left));

        const scroll = rl.getMouseWheelMoveV();
        clay.updateScrollContainers(
            true,
            .{ .x = scroll.x, .y = scroll.y },
            time.deltaTime(),
        );

        clay.beginLayout();

        program.dispatcher.execute();

        audio.update();

        rl.beginDrawing();
        defer rl.endDrawing();

        window.clearBackground();
        rendering: {
            const active_scene = activeScene() orelse break :rendering;

            for (active_scene.cameras.items()) |camera| {
                camera.begin() catch {
                    std.log.err("camera failed to begin context", .{});
                };
                defer camera.end();

                switch (camera.draw_mode) {
                    .none => continue,
                    .world => display.render(),
                    .custom => if (camera.draw_fn) |func| func() catch {
                        std.log.err("error while running custom camera draw function", .{});
                    },
                }
            }
        }

        var render_commands = clay.cdefs.Clay_EndLayout();
        ui.update(&render_commands) catch {
            std.log.err("UI update failed", .{});
        };

        if (window.use_debug_mode)
            rl.drawFPS(10, 10);
    }

    program.dispatcher.deinit();
    ui.deinit();
    display.deinit();

    window.restore_state.save() catch {
        std.log.err("failed to save window state", .{});
    };

    audio.deinit();

    assets.deinit();
    window.deinit();

    if (allocators.AI_arena.interface) |arena| {
        arena.deinit();
    }
}

pub fn scene(id: []const u8) *const fn (void) void {
    return program.dispatcher.addSceneOpen(Scene.init(allocators.arena(), id)) catch @panic("Scene creation failed");
}

pub fn prefabs(prefab_array: []const Prefab) void {
    const selected_scene = program.dispatcher.active_scene orelse program.dispatcher.open_scene orelse return;

    selected_scene.addPrefabs(prefab_array) catch {
        std.log.err("couldn't add prefabs", .{});
    };
}

pub fn globalBehaviours(behaviours: anytype) void {
    const selected_scene = program.dispatcher.active_scene orelse program.dispatcher.open_scene orelse return;

    selected_scene.useGlobalBehaviours(behaviours) catch |err| {
        std.log.err("failed to apply global behaviours for scene: \"{s}\". error: {any}", .{ selected_scene.id, err });
    };
}

pub const CameraConfig = struct { id: []const u8, options: Camera.Options };
pub fn cameras(camera_configs: []const CameraConfig) void {
    const selected_scene = program.dispatcher.active_scene orelse program.dispatcher.open_scene orelse return;

    selected_scene.useDefaultCameras(camera_configs) catch {
        std.log.err("failed to add cameras to scene: {s}", .{selected_scene.id});
    };
}

pub fn useMainCamera() void {
    const selected_scene = program.dispatcher.active_scene orelse program.dispatcher.open_scene orelse return;

    selected_scene.default_cameras.append(.{
        .id = "main",
        .options = .{
            .draw_mode = .world,
            .display = .fullscreen,
        },
    }) catch |err| {
        std.log.err("failed to use main camera due to error: {any} in scene \"{s}\"", .{ err, selected_scene.id });
    };
}

pub const prefab = Prefab.init;

// Runtime Entity / Scene Handling
// --------------------------------------------------------------------------------------------------------------

const SummonTag = enum {
    entity,
    prefab,
};

const SummonUnion = union(SummonTag) {
    entity: *Entity,
    prefab: Prefab,
};

pub fn summon(entities_prefabs: []const SummonUnion) !void {
    deprecated("loom.summon is deprecated, use loom.summoning instead");
    const ascene = program.dispatcher.active_scene orelse return;

    for (entities_prefabs) |value| {
        switch (value) {
            .entity => |entity| try ascene.addEntity(entity),
            .prefab => |pfab| try ascene.addEntity(try pfab.makeInstance()),
        }
    }
}

pub const summoning = struct {
    pub inline fn entity(subject: *Entity) !void {
        const ascene = activeScene() orelse return;
        try ascene.addEntity(subject);
    }

    pub inline fn entities(subjects: []const *Entity) !void {
        const ascene = activeScene() orelse return;
        for (subjects) |subject| try ascene.addEntity(subject);
    }

    pub inline fn prefab(subject: Prefab) !void {
        try entities(try subject.makeInstance());
    }

    pub inline fn prefabs(subjects: []const Prefab) !void {
        const ascene = activeScene() orelse return;
        for (subjects) |subject| try ascene.addEntity(try subject.makeInstance());
    }
};

pub fn makeEntity(id: []const u8, components: anytype) !*Entity {
    const ptr = try Entity.create(allocators.generic(), id);
    try ptr.addComponents(components);

    return ptr;
}

pub fn makeEntityI(id: []const u8, index: u32, components: anytype) !*Entity {
    const alloc_id = try std.fmt.allocPrint(allocators.generic(), "{s}-{d}", .{ id, index });
    defer allocators.generic().free(alloc_id);

    const ptr = try Entity.createAllocId(allocators.generic(), alloc_id);
    try ptr.addComponents(components);

    return ptr;
}

pub inline fn activeScene() ?*Scene {
    return program.dispatcher.active_scene;
}

pub fn getEntity(target: EntityTargetType) ?*Entity {
    const ascene = program.dispatcher.active_scene orelse return null;

    return switch (target) {
        .id => |id| ascene.getEntityById(id),
        .uuid => |target_uuid| ascene.getEntityByUuid(target_uuid),
        .ptr => |ptr| ptr,
    };
}

/// The scene will be loaded after the currect dispatcher cycle is executed.
pub inline fn loadScene(scene_id: []const u8) !void {
    try program.dispatcher.setActive(scene_id);
}

const EntityTargetTag = enum {
    id,
    uuid,
    ptr,
};

const EntityTargetType = union(EntityTargetTag) {
    const Self = @This();

    id: []const u8,
    uuid: u128,
    ptr: *Entity,

    pub fn byID(str: []const u8) Self {
        return .{ .id = str };
    }

    pub fn byUUID(target_uuid: u128) Self {
        return .{ .uuid = target_uuid };
    }

    pub fn byPtr(pointer: *Entity) Self {
        return .{ .ptr = pointer };
    }
};

pub fn removeEntity(target: EntityTargetType) void {
    const ascene = program.dispatcher.active_scene orelse return;
    switch (target) {
        .id => |id| ascene.removeEntityById(id),
        .uuid => |target_uuid| ascene.removeEntityByUuid(target_uuid),
        .ptr => |ptr| ascene.removeEntityByPtr(ptr),
    }
}

// Allocators
// --------------------------------------------------------------------------------------------------------------

pub const allocators = struct {
    fn AllocatorInstance(comptime T: type) type {
        return struct {
            interface: ?T = null,
            allocator: ?Allocator = null,
        };
    }

    pub var AI_generic: AllocatorInstance(std.heap.DebugAllocator(.{})) = .{};
    pub var AI_arena: AllocatorInstance(std.heap.ArenaAllocator) = .{};
    pub var AI_scene: AllocatorInstance(std.heap.ArenaAllocator) = .{};

    /// Generic allocator, warns at program exit if a memory leak happened.
    /// In the Debug and ReleaseFast modes this is a `DebugAllocator`,
    /// otherwise it is equivalent to the `std.heap.smp_allocator`
    pub inline fn generic() Allocator {
        return AI_generic.allocator orelse Blk: {
            switch (builtin.mode) {
                .Debug, .ReleaseFast => {
                    AI_generic.interface = std.heap.DebugAllocator(.{}).init;
                    AI_generic.allocator = AI_generic.interface.?.allocator();
                },
                else => AI_generic.allocator = std.heap.smp_allocator,
            }
            break :Blk AI_generic.allocator.?;
        };
    }

    /// Global arena allocator, everything allocated will be freed at program exit.
    pub inline fn arena() Allocator {
        return AI_arena.allocator orelse Blk: {
            AI_arena.interface = std.heap.ArenaAllocator.init(generic());
            AI_arena.allocator = AI_arena.interface.?.allocator();

            break :Blk AI_arena.allocator.?;
        };
    }

    /// This allocator destroys all allocated memory when a new scene is loaded.
    pub inline fn scene() Allocator {
        return AI_scene.allocator orelse Blk: {
            AI_scene.interface = std.heap.ArenaAllocator.init(generic());
            AI_scene.allocator = AI_scene.interface.?.allocator();

            break :Blk AI_scene.allocator.?;
        };
    }

    pub const c = struct {
        const CError = error{
            OutOfMemory,
        };

        pub fn create(comptime T: type) !*T {
            const ptr = try malloc(@sizeOf(T));
            return @ptrCast(@alignCast(ptr));
        }

        pub fn malloc(size: usize) !*anyopaque {
            return std.c.malloc(size) orelse CError.OutOfMemory;
        }

        pub const free = std.c.free;
    };
};

// CoerceTo
// --------------------------------------------------------------------------------------------------------------

pub const coerceTo = types.coerceTo;

/// Shorthand for coerceTo
pub inline fn tof32(value: anytype) f32 {
    return coerceTo(f32, value) orelse 0;
}

/// Shorthand for coerceTo
pub inline fn tof64(value: anytype) f64 {
    return coerceTo(f64, value) orelse 0;
}

/// Shorthand for coerceTo
pub fn toi32(value: anytype) i32 {
    return coerceTo(i32, value) orelse 0;
}

/// Shorthand for coerceTo
pub fn tou32(value: anytype) u32 {
    return coerceTo(u32, value) orelse 0;
}

/// Shorthand for coerceTo
pub fn toisize(value: anytype) isize {
    return coerceTo(isize, value) orelse 0;
}

/// Shorthand for coerceTo
pub fn tousize(value: anytype) usize {
    return coerceTo(usize, value) orelse 0;
}

/// Shorthand for coerceTo
pub fn tou16(value: anytype) u16 {
    return coerceTo(u16, value) orelse 0;
}

/// Shorthand for coerceTo
pub fn toi16(value: anytype) i16 {
    return coerceTo(i16, value) orelse 0;
}

/// Shorthand for coerceTo
pub fn tou8(value: anytype) u8 {
    return coerceTo(u8, value) orelse 0;
}

/// Shorthand for coerceTo
pub fn toi8(value: anytype) i8 {
    return coerceTo(i8, value) orelse 0;
}

// Vector Types
// --------------------------------------------------------------------------------------------------------------

pub fn Vec2(x: anytype, y: anytype) Vector2 {
    return Vector2{
        .x = tof32(x),
        .y = tof32(y),
    };
}

pub fn Vec3(x: anytype, y: anytype, z: anytype) Vector3 {
    return Vector3{
        .x = tof32(x),
        .y = tof32(y),
        .z = tof32(z),
    };
}

pub fn Vec4(x: anytype, y: anytype, z: anytype, w: anytype) Vector4 {
    return Vector4{
        .x = tof32(x),
        .y = tof32(y),
        .z = tof32(z),
        .w = tof32(w),
    };
}

pub fn Rect(x: anytype, y: anytype, width: anytype, height: anytype) Rectangle {
    return Rectangle{
        .x = tof32(x),
        .y = tof32(y),
        .width = tof32(width),
        .height = tof32(height),
    };
}

pub fn vec2() Vector2 {
    return Vec2(0, 0);
}

pub fn vec3() Vector3 {
    return Vec3(0, 0, 0);
}

pub fn vec4() Vector4 {
    return Vec4(0, 0, 0, 0);
}

pub fn rect() Rectangle {
    return Rect(0, 0, 0, 0);
}

pub fn vec2ToVec3(v2: Vector2) Vector3 {
    return Vec3(v2.x, v2.y, 0);
}

pub fn vec3ToVec2(v3: Vector3) Vector2 {
    return Vec2(v3.x, v3.y);
}

pub fn vec2ToDims(vector: Vector2) Dimensions {
    return .{
        .w = vector.x,
        .h = vector.y,
    };
}

pub fn vec3ToDims(vector: Vector3) Dimensions {
    return .{
        .w = vector.x,
        .h = vector.y,
    };
}

pub fn dimsToVec2(dims: Dimensions) Vector2 {
    return .{
        .x = dims.w,
        .y = dims.h,
    };
}

// Other Utilities
// --------------------------------------------------------------------------------------------------------------

pub fn OptionalToError(comptime Optional: type) type {
    const typeinfo = @typeInfo(Optional);

    return switch (typeinfo) {
        .optional => |T| {
            return anyerror!T.child;
        },
        else => @compileError("expected optional type"),
    };
}

pub fn ensureComponent(value: anytype) OptionalToError(@TypeOf(value)) {
    return value orelse err: {
        std.log.err("Component didn't load: {any}", .{@TypeOf(value)});
        break :err error.ComponentDidntLoad;
    };
}

pub fn randColor() rl.Color {
    return rl.Color.init(
        random.int(u8),
        random.int(u8),
        random.int(u8),
        random.int(u8),
    );
}

pub fn randFloat(comptime T: type, min: T, max: T) T {
    return random.float(T) * (max - min) + min;
}
