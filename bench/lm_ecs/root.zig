//! ECS Benchmarks — mirrors the categories from
//!   https://github.com/abeimler/ecs_benchmark
//!
//! Benchmark categories implemented
//! ─────────────────────────────────
//!  1. CreateEntities          — queue + apply N entities with 2 components
//!  2. DestroyEntities         — remove N pre-existing entities
//!  3. UnpackOneComponent      — getComponent (Position) per entity
//!  4. UnpackTwoComponents     — getComponent (Position) + getComponentConst (Velocity) per entity
//!  5. UnpackThreeComponents   — same + optional Data (50 % of entities have it)
//!  6. RemoveAddComponent      — remove then re-add Position via command buffer
//!  7. SystemsUpdate2          — runStage with MovementSystem + DataSystem
//!  8. SystemsUpdateMixed2     — same with mixed archetypes (not every entity has every component)
//!  9. ComplexSystemsUpdate7   — runStage with all 7 systems, homogeneous entities
//! 10. ComplexSystemsUpdateMixed7 — all 7 systems, 4 different archetype flavours
//!
//! Build note
//! ──────────
//! Add to your build.zig:
//!
//!   const bench_exe = b.addExecutable(.{
//!       .name = "ecs-benchmark",
//!       .root_source_file = b.path("benchmark.zig"),
//!       .target = target,
//!       .optimize = .ReleaseFast,        // always bench in ReleaseFast
//!   });
//!   bench_exe.root_module.addImport("lm_ecs",  ecs_module);
//!   bench_exe.root_module.addImport("lm_core", core_module);
//!   b.installArtifact(bench_exe);

const std = @import("std");
const ecs = @import("lm_ecs");
const core = @import("lm_core");

// ============================================================================
// Components  (mirror the 6 component types from the benchmark repo)
// ============================================================================

/// 1. PositionComponent
const Position = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
};

/// 2. VelocityComponent
const Velocity = struct {
    x: f32 = 1.0,
    y: f32 = 1.0,
};

/// 3. DataComponent  (64 bytes so it exercises cache pressure like the C++ version)
const Data = struct {
    value: f64 = 0.0,
    pad: [56]u8 = [_]u8{0} ** 56,
};

/// 4. HealthComponent
const Health = struct {
    hp: f32 = 100.0,
    max_hp: f32 = 100.0,
    alive: bool = true,
};

/// 5. DamageComponent
const Damage = struct {
    damage: f32 = 10.0,
};

/// 6. SpriteComponent
const Sprite = struct {
    character: u8 = '@',
};

// ============================================================================
// Systems
//
// Parameter convention (see System.zig / wrapFunction):
//   Each parameter must be a slice-of-pointer, either []*T  (write) or
//   []*const T (read).  The wrapper peels two pointer levels to obtain the
//   component type, uses its hash to locate the archetype column, then
//   reconstructs a typed slice that the body receives at runtime.
// ============================================================================

/// 1. MovementSystem — integrates velocity into position
fn movementSystem(
    positions: []Position,
    velocities: []const Velocity,
) !void {
    for (positions, velocities) |*pos, vel| {
        pos.x += vel.x;
        pos.y += vel.y;
    }
}

/// 2. DataSystem — touches every DataComponent (exercises bandwidth)
fn dataSystem(datas: []Data) !void {
    for (datas) |*d| {
        d.value = d.value * 1.000_01 + 0.000_1;
    }
}

/// 3. MoreComplexSystem — cross-component arithmetic (matches "more complex" C++ system)
fn moreComplexSystem(
    positions: []Position,
    velocities: []Velocity,
    datas: []Data,
) !void {
    for (positions, velocities, datas) |*pos, *vel, *d| {
        d.value += @as(f64, pos.x + pos.y);
        vel.x = @floatCast(@sin(@as(f64, vel.x)) * 0.001 * d.value);
        vel.y = @floatCast(@cos(@as(f64, vel.y)) * 0.001 * d.value);
        pos.x += vel.x;
        pos.y += vel.y;
    }
}

/// 4. HealthSystem — regenerate HP, mark dead entities
fn healthSystem(healths: []Health) !void {
    for (healths) |*h| {
        if (h.hp <= 0.0) {
            h.alive = false;
        } else {
            h.hp = @min(h.hp + 1.0, h.max_hp);
        }
    }
}

/// 5. DamageSystem — apply damage to health
fn damageSystem(
    healths: []Health,
    damages: []const Damage,
) !void {
    for (healths, damages) |*h, d| {
        if (h.alive) h.hp -= d.damage;
    }
}

/// 6. SpriteSystem — choose ASCII character based on alive status
fn spriteSystem(
    sprites: []Sprite,
    healths: []const Health,
) !void {
    for (sprites, healths) |*s, h| {
        s.character = if (h.alive) '@' else 'X';
    }
}

/// 7. RenderSystem — "blit" character into a fixed frame buffer (avoids allocation)
var g_frame_buffer: [8192]u8 = [_]u8{' '} ** 8192;
var g_frame_cursor: usize = 0;

fn renderSystem(sprites: []const Sprite) !void {
    for (sprites) |s| {
        g_frame_buffer[g_frame_cursor % g_frame_buffer.len] = s.character;
        g_frame_cursor +%= 1; // wrapping add
    }
}

// ============================================================================
// Benchmark runner helpers
// ============================================================================

const WARMUP: usize = 5;
const ITERS: usize = 20;

/// Per-category result
const Result = struct {
    label: []const u8,
    n: usize,
    best_ns: f64, // best single run
    avg_ns: f64, // mean over ITERS
    worst_ns: f64, // worst single run
};

fn printHeader(w: anytype, title: []const u8) !void {
    try w.print(
        "\n╔══════════════════════════════════════════════════════════════════╗\n" ++
            "║  {s:<64}║\n" ++
            "╚══════════════════════════════════════════════════════════════════╝\n" ++
            "  {s:<38}  {s:>9}  {s:>12}  {s:>12}  {s:>12}\n" ++
            "  {s:-<38}  {s:->9}  {s:->12}  {s:->12}  {s:->12}\n",
        .{
            title,
            "benchmark",
            "entities",
            "best ns/ent",
            "avg ns/ent",
            "worst ns/ent",
            "",
            "",
            "",
            "",
            "",
        },
    );
}

fn printRow(w: *std.Io.Writer, r: Result) !void {
    const fN: f64 = @floatFromInt(r.n);
    try w.print(
        "  {s:<38}  {:>9}  {:>12.2}  {:>12.2}  {:>12.2}\n",
        .{
            r.label,
            r.n,
            r.best_ns / fN,
            r.avg_ns / fN,
            r.worst_ns / fN,
        },
    );
    try w.flush();
}

// ============================================================================
// 1. Create entities
// ============================================================================

fn benchCreate(allocator: std.mem.Allocator, w: *std.io.Writer, n: usize) !void {
    var best: f64 = std.math.floatMax(f64);
    var worst: f64 = 0;
    var total: f64 = 0;

    for (0..WARMUP + ITERS) |iter| {
        var world = ecs.World.init(allocator);
        defer world.deinit();

        const t0 = std.time.nanoTimestamp();

        for (0..n) |i| {
            try world.command_buffer.makeEntity(.{ Position{}, Velocity{} });
            try w.print("  iter: {d} processing: {d}/{d} {d:.2}%\r", .{ iter, i + 1, n, @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n)) * 100 });
            try w.flush();
        }
        try world.flushCommandBuffer();

        const dt: f64 = @floatFromInt(std.time.nanoTimestamp() - t0);
        if (iter >= WARMUP) {
            total += dt;
            if (dt < best) best = dt;
            if (dt > worst) worst = dt;
        }
    }
    try printRow(w, .{ .label = "create", .n = n, .best_ns = best, .avg_ns = total / ITERS, .worst_ns = worst });
}

// ============================================================================
// 2. Destroy entities
// ============================================================================

fn benchDestroy(allocator: std.mem.Allocator, w: *std.io.Writer, n: usize) !void {
    var best: f64 = std.math.floatMax(f64);
    var worst: f64 = 0;
    var total: f64 = 0;

    for (0..WARMUP + ITERS) |iter| {
        // --- setup ---
        var world = ecs.World.init(allocator);
        defer world.deinit();

        var ids = core.List(ecs.Entity).init(allocator);
        defer ids.deinit();

        for (0..n) |_| {
            const e = try world.newEntity();
            try ids.append(e);
            try world.command_buffer.addComponent(e, Position{});
            try world.command_buffer.addComponent(e, Velocity{});
        }
        try world.flushCommandBuffer();

        // --- timed section ---
        const t0 = std.time.nanoTimestamp();

        for (ids.items(), 0..) |e, i| {
            try world.command_buffer.removeEntity(e);

            try w.print("  iter: {d} processing: {d}/{d} {d:.2}%\r", .{ iter, i + 1, n, @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n)) * 100 });
            try w.flush();
        }
        try world.flushCommandBuffer();

        const dt: f64 = @floatFromInt(std.time.nanoTimestamp() - t0);
        if (iter >= WARMUP) {
            total += dt;
            if (dt < best) best = dt;
            if (dt > worst) worst = dt;
        }
    }
    try printRow(w, .{ .label = "destroy", .n = n, .best_ns = best, .avg_ns = total / ITERS, .worst_ns = worst });
}

// ============================================================================
// 3. Unpack one component — getComponent(Position)
// ============================================================================

fn benchUnpackOne(allocator: std.mem.Allocator, w: *std.io.Writer, n: usize) !void {
    var world = ecs.World.init(allocator);
    defer world.deinit();

    var ids = core.List(ecs.Entity).init(allocator);
    defer ids.deinit();

    for (0..n) |_| {
        const e = try world.newEntity();
        try ids.append(e);
        try world.command_buffer.addComponent(e, Position{ .x = 1.0, .y = 2.0 });
        try world.command_buffer.addComponent(e, Velocity{});
    }
    try world.flushCommandBuffer();

    var best: f64 = std.math.floatMax(f64);
    var worst: f64 = 0;
    var total: f64 = 0;
    var sink: f32 = 0;

    for (0..WARMUP + ITERS) |iter| {
        const t0 = std.time.nanoTimestamp();

        for (ids.items(), 0..) |e, i| {
            if (world.getComponent(Position, e)) |p| sink += p.x;

            try w.print("  iter: {d} processing: {d}/{d} {d:.2}%\r", .{ iter, i + 1, n, @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n)) * 100 });
            try w.flush();
        }

        const dt: f64 = @floatFromInt(std.time.nanoTimestamp() - t0);
        if (iter >= WARMUP) {
            total += dt;
            if (dt < best) best = dt;
            if (dt > worst) worst = dt;
        }
    }

    // prevent the loop from being eliminated by the optimiser
    if (sink == 0) std.log.debug("sink={d}", .{sink});

    try printRow(w, .{ .label = "unpack one (Position)", .n = n, .best_ns = best, .avg_ns = total / ITERS, .worst_ns = worst });
}

// ============================================================================
// 4. Unpack two components — Position (mut) + Velocity (const)
// ============================================================================

fn benchUnpackTwo(allocator: std.mem.Allocator, w: anytype, n: usize) !void {
    var world = ecs.World.init(allocator);
    defer world.deinit();

    var ids = core.List(ecs.Entity).init(allocator);
    defer ids.deinit();

    for (0..n) |_| {
        const e = try world.newEntity();
        try ids.append(e);
        try world.command_buffer.addComponent(e, Position{ .x = 1.0, .y = 2.0 });
        try world.command_buffer.addComponent(e, Velocity{ .x = 0.5, .y = 0.5 });
    }
    try world.flushCommandBuffer();

    var best: f64 = std.math.floatMax(f64);
    var worst: f64 = 0;
    var total: f64 = 0;
    var sink: f32 = 0;

    for (0..WARMUP + ITERS) |iter| {
        const t0 = std.time.nanoTimestamp();

        for (ids.items()) |e| {
            const pos = world.getComponent(Position, e) orelse continue;
            const vel = world.getComponentConst(Velocity, e) orelse continue;
            sink += pos.x + vel.x;
        }

        const dt: f64 = @floatFromInt(std.time.nanoTimestamp() - t0);
        if (iter >= WARMUP) {
            total += dt;
            if (dt < best) best = dt;
            if (dt > worst) worst = dt;
        }
    }

    if (sink == 0) std.log.debug("sink={d}", .{sink});

    try printRow(w, .{ .label = "unpack two (Pos + const Vel)", .n = n, .best_ns = best, .avg_ns = total / ITERS, .worst_ns = worst });
}

// ============================================================================
// 5. Unpack three components — Position + const Velocity + optional Data
//    (mirrors the benchmark note: "not every entity has three components")
// ============================================================================

fn benchUnpackThree(allocator: std.mem.Allocator, w: anytype, n: usize) !void {
    var world = ecs.World.init(allocator);
    defer world.deinit();

    var ids = core.List(ecs.Entity).init(allocator);
    defer ids.deinit();

    for (0..n) |i| {
        const e = try world.newEntity();
        try ids.append(e);
        try world.command_buffer.addComponent(e, Position{ .x = 1.0, .y = 2.0 });
        try world.command_buffer.addComponent(e, Velocity{ .x = 0.5, .y = 0.5 });
        if (i % 2 == 0) {
            try world.command_buffer.addComponent(e, Data{ .value = @floatFromInt(i) });
        }
    }
    try world.flushCommandBuffer();

    var best: f64 = std.math.floatMax(f64);
    var worst: f64 = 0;
    var total: f64 = 0;
    var sink: f64 = 0;

    for (0..WARMUP + ITERS) |iter| {
        const t0 = std.time.nanoTimestamp();

        for (ids.items()) |e| {
            const pos = world.getComponent(Position, e) orelse continue;
            const vel = world.getComponentConst(Velocity, e) orelse continue;
            sink += @as(f64, pos.x + vel.x);
            if (world.getComponent(Data, e)) |d| sink += d.value;
        }

        const dt: f64 = @floatFromInt(std.time.nanoTimestamp() - t0);
        if (iter >= WARMUP) {
            total += dt;
            if (dt < best) best = dt;
            if (dt > worst) worst = dt;
        }
    }

    if (sink == 0) std.log.debug("sink={d}", .{sink});

    try printRow(w, .{ .label = "unpack three (50% have Data)", .n = n, .best_ns = best, .avg_ns = total / ITERS, .worst_ns = worst });
}

// ============================================================================
// 6. Remove and add a component  (mirrors "RemoveAddComponent" benchmark)
//    Times: queue all removes → apply → queue all adds → apply
// ============================================================================

fn benchRemoveAdd(allocator: std.mem.Allocator, w: anytype, n: usize) !void {
    var world = ecs.World.init(allocator);
    defer world.deinit();

    var ids = core.List(ecs.Entity).init(allocator);
    defer ids.deinit();

    for (0..n) |_| {
        const e = try world.newEntity();
        try ids.append(e);
        try world.command_buffer.addComponent(e, Position{ .x = 1.0, .y = 2.0 });
        try world.command_buffer.addComponent(e, Velocity{});
    }
    try world.flushCommandBuffer();

    var best: f64 = std.math.floatMax(f64);
    var worst: f64 = 0;
    var total: f64 = 0;

    for (0..WARMUP + ITERS) |iter| {
        const t0 = std.time.nanoTimestamp();

        // Remove Position from every entity
        for (ids.items()) |e| try world.command_buffer.removeComponent(e, Position);
        try world.flushCommandBuffer();

        // Re-add Position to every entity
        for (ids.items()) |e|
            try world.command_buffer.addComponent(e, Position{ .x = 0.0, .y = 0.0 });
        try world.flushCommandBuffer();

        const dt: f64 = @floatFromInt(std.time.nanoTimestamp() - t0);
        if (iter >= WARMUP) {
            total += dt;
            if (dt < best) best = dt;
            if (dt > worst) worst = dt;
        }
    }

    try printRow(w, .{ .label = "remove+add Position", .n = n, .best_ns = best, .avg_ns = total / ITERS, .worst_ns = worst });
}

// ============================================================================
// Shared setup helpers for system-update benchmarks
// ============================================================================

/// Populate a world with N entities that each have all 6 game components.
fn setupHomogeneous(world: *ecs.World, n: usize) !void {
    for (0..n) |i| {
        try world.command_buffer.makeEntity(.{
            Position{ .x = @floatFromInt(i), .y = 0.0 },
            Velocity{ .x = 1.0, .y = 1.0 },
            Data{ .value = @floatFromInt(i) },
            Health{},
            Damage{},
            Sprite{},
        });
    }
    try world.flushCommandBuffer();
}

/// Populate a world with N entities spread across 4 archetype "flavours".
/// This mirrors the "mixed entities" variant in the C++ benchmark, where
/// not every entity has every component.
///
///   i % 4 == 0  →  all 6 components (Pos+Vel+Data+Health+Dmg+Sprite)
///   i % 4 == 1  →  Pos+Vel+Data+Health        (no Damage, no Sprite)
///   i % 4 == 2  →  Pos+Vel only
///   i % 4 == 3  →  Health+Damage+Sprite only
fn setupMixed(world: *ecs.World, n: usize) !void {
    for (0..n) |i| {
        switch (i % 4) {
            0 => try world.command_buffer.makeEntity(.{
                Position{}, Velocity{}, Data{}, Health{}, Damage{}, Sprite{},
            }),
            1 => try world.command_buffer.makeEntity(.{
                Position{}, Velocity{}, Data{}, Health{},
            }),
            2 => try world.command_buffer.makeEntity(.{
                Position{}, Velocity{},
            }),
            else => try world.command_buffer.makeEntity(.{
                Health{}, Damage{}, Sprite{},
            }),
        }
    }
    try world.flushCommandBuffer();
}

// ============================================================================
// 7. Update systems — 2 systems, homogeneous entities
// ============================================================================

fn benchSystems2(allocator: std.mem.Allocator, w: anytype, n: usize) !void {
    var world = ecs.World.init(allocator);
    defer world.deinit();

    try world.command_buffer.addSystem(.update, movementSystem);
    try world.command_buffer.addSystem(.update, dataSystem);
    try world.flushCommandBuffer();
    try setupHomogeneous(&world, n);

    var best: f64 = std.math.floatMax(f64);
    var worst: f64 = 0;
    var total: f64 = 0;

    for (0..WARMUP + ITERS) |iter| {
        const t0 = std.time.nanoTimestamp();
        try world.runStage(.update);
        const dt: f64 = @floatFromInt(std.time.nanoTimestamp() - t0);

        if (iter >= WARMUP) {
            total += dt;
            if (dt < best) best = dt;
            if (dt > worst) worst = dt;
        }
    }

    try printRow(w, .{ .label = "2-system update (Movement+Data)", .n = n, .best_ns = best, .avg_ns = total / ITERS, .worst_ns = worst });
}

// ============================================================================
// 8. Update systems — 2 systems, mixed archetypes
// ============================================================================

fn benchSystems2Mixed(allocator: std.mem.Allocator, w: anytype, n: usize) !void {
    var world = ecs.World.init(allocator);
    defer world.deinit();

    try world.command_buffer.addSystem(.update, movementSystem);
    try world.command_buffer.addSystem(.update, dataSystem);
    try world.flushCommandBuffer();
    try setupMixed(&world, n);

    var best: f64 = std.math.floatMax(f64);
    var worst: f64 = 0;
    var total: f64 = 0;

    for (0..WARMUP + ITERS) |iter| {
        const t0 = std.time.nanoTimestamp();
        try world.runStage(.update);
        const dt: f64 = @floatFromInt(std.time.nanoTimestamp() - t0);

        if (iter >= WARMUP) {
            total += dt;
            if (dt < best) best = dt;
            if (dt > worst) worst = dt;
        }
    }

    try printRow(w, .{ .label = "2-system update mixed", .n = n, .best_ns = best, .avg_ns = total / ITERS, .worst_ns = worst });
}

// ============================================================================
// 9. Update systems — 7 systems, homogeneous entities
// ============================================================================

fn benchSystems7(allocator: std.mem.Allocator, w: anytype, n: usize) !void {
    var world = ecs.World.init(allocator);
    defer world.deinit();

    try world.command_buffer.addSystem(.update, movementSystem);
    try world.command_buffer.addSystem(.update, dataSystem);
    try world.command_buffer.addSystem(.update, moreComplexSystem);
    try world.command_buffer.addSystem(.update, healthSystem);
    try world.command_buffer.addSystem(.update, damageSystem);
    try world.command_buffer.addSystem(.update, spriteSystem);
    try world.command_buffer.addSystem(.update, renderSystem);
    try world.flushCommandBuffer();
    try setupHomogeneous(&world, n);

    var best: f64 = std.math.floatMax(f64);
    var worst: f64 = 0;
    var total: f64 = 0;

    for (0..WARMUP + ITERS) |iter| {
        const t0 = std.time.nanoTimestamp();
        try world.runStage(.update);
        const dt: f64 = @floatFromInt(std.time.nanoTimestamp() - t0);

        if (iter >= WARMUP) {
            total += dt;
            if (dt < best) best = dt;
            if (dt > worst) worst = dt;
        }
    }

    try printRow(w, .{ .label = "7-system update", .n = n, .best_ns = best, .avg_ns = total / ITERS, .worst_ns = worst });
}

// ============================================================================
// 10. Update systems — 7 systems, mixed archetypes
// ============================================================================

fn benchSystems7Mixed(allocator: std.mem.Allocator, w: anytype, n: usize) !void {
    var world = ecs.World.init(allocator);
    defer world.deinit();

    try world.command_buffer.addSystem(.update, movementSystem);
    try world.command_buffer.addSystem(.update, dataSystem);
    try world.command_buffer.addSystem(.update, moreComplexSystem);
    try world.command_buffer.addSystem(.update, healthSystem);
    try world.command_buffer.addSystem(.update, damageSystem);
    try world.command_buffer.addSystem(.update, spriteSystem);
    try world.command_buffer.addSystem(.update, renderSystem);
    try world.flushCommandBuffer();
    try setupMixed(&world, n);

    var best: f64 = std.math.floatMax(f64);
    var worst: f64 = 0;
    var total: f64 = 0;

    for (0..WARMUP + ITERS) |iter| {
        const t0 = std.time.nanoTimestamp();
        try world.runStage(.update);
        const dt: f64 = @floatFromInt(std.time.nanoTimestamp() - t0);

        if (iter >= WARMUP) {
            total += dt;
            if (dt < best) best = dt;
            if (dt > worst) worst = dt;
        }
    }

    try printRow(w, .{ .label = "7-system update mixed", .n = n, .best_ns = best, .avg_ns = total / ITERS, .worst_ns = worst });
}

// ============================================================================
// Entry point
// ============================================================================

/// Entity counts matching the abeimler benchmark tables (small → large).
const COUNTS = [_]usize{
    1,   4,     8,     16,     32,     64,
    256, 1_024, 4_096, 16_384, 65_536,
    262_144,
    // 1_048_576,  // un-comment for the full ~1 M run
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var buffer = [_]u8{0} ** 1024;
    var writer = std.fs.File.stdout().writer(&buffer);
    var out = &writer.interface;

    try out.print(
        "lm_ecs benchmark  —  {d} warm-up iters, {d} measured iters\n" ++
            "columns: best ns/entity | avg ns/entity | worst ns/entity\n",
        .{ WARMUP, ITERS },
    );

    // ------------------------------------------------------------------
    try printHeader(out, "1. Create entities (Pos + Vel)");
    for (COUNTS) |n| try benchCreate(alloc, out, n);

    // ------------------------------------------------------------------
    try printHeader(out, "2. Destroy entities (Pos + Vel)");
    for (COUNTS) |n| try benchDestroy(alloc, out, n);

    // ------------------------------------------------------------------
    try printHeader(out, "3. Unpack one component");
    for (COUNTS) |n| try benchUnpackOne(alloc, out, n);

    // ------------------------------------------------------------------
    try printHeader(out, "4. Unpack two components");
    for (COUNTS) |n| try benchUnpackTwo(alloc, out, n);

    // ------------------------------------------------------------------
    try printHeader(out, "5. Unpack three components (50 % have Data)");
    for (COUNTS) |n| try benchUnpackThree(alloc, out, n);

    // ------------------------------------------------------------------
    try printHeader(out, "6. Remove and add Position");
    for (COUNTS) |n| try benchRemoveAdd(alloc, out, n);

    // ------------------------------------------------------------------
    try printHeader(out, "7. Systems update — 2 systems");
    for (COUNTS) |n| try benchSystems2(alloc, out, n);

    // ------------------------------------------------------------------
    try printHeader(out, "8. Systems update mixed — 2 systems");
    for (COUNTS) |n| try benchSystems2Mixed(alloc, out, n);

    // ------------------------------------------------------------------
    try printHeader(out, "9. Complex systems update — 7 systems");
    for (COUNTS) |n| try benchSystems7(alloc, out, n);

    // ------------------------------------------------------------------
    try printHeader(out, "10. Complex systems update mixed — 7 systems");
    for (COUNTS) |n| try benchSystems7Mixed(alloc, out, n);

    try out.print("\nDone.\n", .{});
}
