const std = @import("std");
const rlz = @import("raylib_zig");

const Module = std.Build.Module;
const Import = Module.Import;

const builder = struct {
    const DependencyOptions = struct {
        link_raylib: bool = false,
        link_clay: bool = false,
        link_system_sdks: bool = false,

        pub const none: DependencyOptions = .{
            .link_clay = false,
            .link_raylib = false,
            .link_system_sdks = false,
        };

        pub const all: DependencyOptions = .{
            .link_clay = true,
            .link_raylib = true,
            .link_system_sdks = true,
        };

        pub const sdks_only: DependencyOptions = .{
            .link_clay = false,
            .link_raylib = false,
            .link_system_sdks = true,
        };
    };

    pub const Options = struct {
        dependency_options: DependencyOptions = .all,
        imports: []const Import = &.{},
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
    };

    pub fn module(b: *std.Build, comptime mod_name: []const u8, options: Options) *Module {
        const target = options.target;
        const optimize = options.optimize;

        const mod = b.createModule(.{
            .root_source_file = b.path("modules/" ++ mod_name ++ "/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,

            .imports = options.imports,
        });

        const raylib_dep = b.dependency("raylib_zig", .{
            .target = target,
            .optimize = optimize,
            .linux_display_backend = rlz.LinuxDisplayBackend.X11,
        });

        const raylib = raylib_dep.module("raylib"); // main raylib module
        const raygui = raylib_dep.module("raygui"); // raygui module
        const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library

        const zclay_dep = b.dependency("zclay", .{ .target = target, .optimize = optimize });
        const zclay = zclay_dep.module("zclay");

        const uuid_dep = b.dependency("uuid", .{ .target = target, .optimize = optimize });
        const uuid = uuid_dep.module("uuid");

        mod.addImport("uuid", uuid);

        if (options.dependency_options.link_clay) {
            mod.addImport("clay", zclay);
        }

        if (options.dependency_options.link_raylib) {
            mod.addImport("raylib", raylib);
            mod.addImport("raygui", raygui);
            mod.linkLibrary(raylib_artifact);
        }

        if (options.dependency_options.link_system_sdks) if (b.lazyDependency("system_sdk", .{})) |system_sdk| switch (target.result.os.tag) {
            .windows => {
                if (target.result.cpu.arch.isX86() and (target.result.abi.isGnu() or target.result.abi.isMusl())) {
                    mod.addLibraryPath(system_sdk.path("windows/lib/x86_64-windows-gnu"));
                }
            },
            .macos => {
                mod.addLibraryPath(system_sdk.path("macos12/usr/lib"));
                mod.addFrameworkPath(system_sdk.path("macos12/System/Library/Frameworks"));

                mod.linkFramework("Foundation", .{ .needed = true });
                mod.linkFramework("CoreFoundation", .{ .needed = true });
                mod.linkFramework("CoreGraphics", .{ .needed = true });
                mod.linkFramework("CoreServices", .{ .needed = true });
                mod.linkFramework("AppKit", .{ .needed = true });
                mod.linkFramework("IOKit", .{ .needed = true });

                mod.linkSystemLibrary("objc", .{});
            },
            .linux => {
                if (target.result.cpu.arch.isX86()) {
                    mod.addLibraryPath(system_sdk.path("linux/lib/x86_64-linux-gnu"));
                    raylib.addLibraryPath(system_sdk.path("linux/lib/x86_64-linux-gnu"));
                    raylib.addSystemIncludePath(system_sdk.path("linux/include"));

                    raylib.addLibraryPath(.{ .cwd_relative = "/usr/bin" });
                    raylib.addLibraryPath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu" });
                    raylib.addSystemIncludePath(.{ .cwd_relative = "/usr/include/X11" });

                    raylib.linkSystemLibrary("GL", .{ .needed = true });
                    raylib.linkSystemLibrary("GLX", .{ .needed = true });
                    raylib.linkSystemLibrary("X11", .{ .needed = true });
                    raylib.linkSystemLibrary("Xcursor", .{ .needed = true });
                    raylib.linkSystemLibrary("Xext", .{ .needed = true });
                    raylib.linkSystemLibrary("Xi", .{ .needed = true });
                    raylib.linkSystemLibrary("Xinerama", .{ .needed = true });
                    raylib.linkSystemLibrary("Xrandr", .{ .needed = true });
                    raylib.linkSystemLibrary("Xrender", .{ .needed = true });

                    raylib_artifact.addLibraryPath(system_sdk.path("linux/lib/x86_64-linux-gnu"));
                    raylib_artifact.addSystemIncludePath(system_sdk.path("linux/include"));

                    raylib_artifact.addLibraryPath(.{ .cwd_relative = "/usr/bin" });
                    raylib_artifact.addLibraryPath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu" });
                    raylib_artifact.addSystemIncludePath(.{ .cwd_relative = "/usr/include/X11" });

                    raylib_artifact.linkSystemLibrary("GLX");
                    raylib_artifact.linkSystemLibrary("X11");
                    raylib_artifact.linkSystemLibrary("Xcursor");
                    raylib_artifact.linkSystemLibrary("Xext");
                    raylib_artifact.linkSystemLibrary("Xi");
                    raylib_artifact.linkSystemLibrary("Xinerama");
                    raylib_artifact.linkSystemLibrary("Xrandr");
                    raylib_artifact.linkSystemLibrary("Xrender");
                } else if (target.result.cpu.arch == .aarch64) {
                    mod.addLibraryPath(system_sdk.path("linux/lib/aarch64-linux-gnu"));
                }
            },
            else => {},
        };

        return mod;
    }

    pub fn link(b: *std.Build, link_to: []const *std.Build.Module, comptime mod_name: []const u8, options: Options) void {
        const mod = module(b, mod_name, options);
        for (link_to) |target| {
            target.addImport(mod_name, mod);
        }
    }
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const loom_mod = b.createModule(.{
        .root_source_file = b.path("lib/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const test_module = b.addModule("test", .{
        .root_source_file = b.path("test/test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_module.addImport("loom", loom_mod);

    const core = builder.module(b, "lm_core", .{
        .target = target,
        .optimize = optimize,
    });
    const core_import = Import{ .name = "lm_core", .module = core };
    loom_mod.addImport("lm_core", core);
    test_module.addImport("lm_core", core);

    builder.link(b, &.{ loom_mod, test_module }, "lm_ecs", .{
        .dependency_options = .none,
        .target = target,
        .optimize = optimize,

        .imports = &.{core_import},
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "loom",
        .root_module = loom_mod,
    });
    b.installArtifact(lib);

    const main_module_unit_test = b.addTest(.{
        .name = "loom unit tests",
        .root_module = test_module,
    });

    const run_lib_unit_tests = b.addRunArtifact(main_module_unit_test);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    const examples: []const []const u8 = &.{};

    const build_all_step = b.step("example=all", "");
    inline for (examples) |example| {
        const exe_mod = b.createModule(.{
            .root_source_file = b.path("examples/" ++ example ++ "/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        exe_mod.addImport("loom", loom_mod);

        const exe = b.addExecutable(.{
            .name = example,
            .root_module = exe_mod,
        });

        const run_step = b.step("run-example=" ++ example, "");
        const build_step = b.step("example=" ++ example, "");

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());

        const exe_cmd = b.addInstallArtifact(exe, .{});
        build_step.dependOn(b.getInstallStep());

        run_step.dependOn(&run_cmd.step);

        build_step.dependOn(&exe_cmd.step);
        build_all_step.dependOn(&exe_cmd.step);
    }
}
