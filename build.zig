const std = @import("std");
const raylib_build = @import("raylib");

const title = "Dungeon Wizard";
const version = "v0.13.0";

const raylib_config: []const u8 = "-DSUPPORT_CUSTOM_FRAME_CONTROL=1";

fn linkOSStuff(b: *std.Build, target: std.Build.ResolvedTarget, artifact: *std.Build.Step.Compile, do_release: bool) void {
    switch (target.result.os.tag) {
        .macos => {
            if (std.zig.system.darwin.getSdk(b.allocator, target.result)) |sdk| {
                artifact.addSystemFrameworkPath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "/System/Library/Frameworks" }) });
                artifact.linkFramework("CoreFoundation");
                artifact.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "/System/Library/Frameworks/CoreFoundation.framework/Versions/Current/Headers" }) });
                // Don't actually need the Foundation headers, just need to link it
                artifact.linkFramework("Foundation");
                //artifact.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "/System/Library/Frameworks/Foundation.framework/Versions/Current/Headers" }) });
            }
        },
        .windows => {
            artifact.linkLibC();
            artifact.linkSystemLibrary("c");
            artifact.linkSystemLibrary("User32");
            artifact.linkSystemLibrary("Gdi32");
            artifact.linkSystemLibrary("shell32");
            if (do_release) {
                artifact.subsystem = .Windows;
                artifact.entry = .{ .symbol_name = "mainCRTStartup" };
            }
        },
        else => {},
    }
}

pub fn addDynGameConfig(b: *std.Build, module: *std.Build.Module, is_release: bool) void {
    const options = b.addOptions();
    options.addOption([]const u8, "version", version);
    options.addOption(bool, "is_release", is_release);
    module.addOptions("config", options);
}

pub fn addExeConfig(b: *std.Build, module: *std.Build.Module, static_lib: bool, is_release: bool) void {
    const options = b.addOptions();
    options.addOption(bool, "static_lib", static_lib);
    options.addOption(bool, "is_release", is_release);
    options.addOption([]const u8, "version", version);
    module.addOptions("config", options);
}

pub fn linuxDisplayBackend(b: *std.Build) raylib_build.LinuxDisplayBackend {
    // cache this so it's only set once (otherwise when building multiple targets the option is defined more than once)
    const S = struct {
        var cached: ?raylib_build.LinuxDisplayBackend = null;
    };
    if (S.cached) |c| {
        return c;
    }
    S.cached = b.option(
        raylib_build.LinuxDisplayBackend,
        "linux-display-backend",
        "Select the linux display backend used by Raylib (default \"Both\")",
    ) orelse .Both;
    return S.cached.?;
}

pub fn buildDynamic(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, app_only: bool, do_release: bool) ![]*std.Build.Step.Compile {
    var artifacts = std.ArrayList(*std.Build.Step.Compile).init(b.allocator);
    std.debug.print(
        "Dynamic linking\noptimize: {any}\n{s}{s}",
        .{
            optimize,
            if (do_release) "doing release\n" else "",
            if (app_only) "app only\n" else "",
        },
    );

    const raylib_dep = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
        .shared = true,
        .config = raylib_config,
        .linux_display_backend = linuxDisplayBackend(b),
    });
    const raylib = raylib_dep.artifact("raylib");

    const app_lib = b.addSharedLibrary(.{
        .name = "game",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/App.zig"),
        .target = target,
        .optimize = optimize,
    });
    app_lib.linkLibrary(raylib);
    app_lib.addIncludePath(b.path("raylib/src"));
    addDynGameConfig(b, app_lib.root_module, do_release);

    if (!app_only) {
        const exe = b.addExecutable(.{
            .name = title,
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        linkOSStuff(b, target, exe, do_release);
        exe.linkLibrary(raylib);
        exe.addIncludePath(b.path("raylib/src"));

        addExeConfig(b, exe.root_module, false, do_release);

        if (target.query.isNative()) {
            // This *creates* a Run step in the build graph, to be executed when another
            // step is evaluated that depends on it. The next line below will establish
            // such a dependency.
            const run_cmd = b.addRunArtifact(exe);

            // By making the run step depend on the install step, it will be run from the
            // installation directory rather than directly from within the cache directory.
            // This is not necessary, however, if the application depends on other installed
            // files, this ensures they will be present and in the expected location.
            run_cmd.step.dependOn(b.getInstallStep());

            // This allows the user to pass arguments to the application in the build
            // command itself, like this: `zig build run -- arg1 arg2 etc`
            if (b.args) |args| {
                run_cmd.addArgs(args);
            }

            // This creates a build step. It will be visible in the `zig build --help` menu,
            // and can be selected like this: `zig build run`
            // This will evaluate the `run` step rather than the default, which is "install".
            const run_step = b.step("run", "Run the app");
            run_step.dependOn(&run_cmd.step);
        }
        try artifacts.append(exe);
    }
    try artifacts.append(app_lib);
    try artifacts.append(raylib);

    return try artifacts.toOwnedSlice();
}

pub fn buildStatic(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, do_release: bool) ![]*std.Build.Step.Compile {
    std.debug.print("Static linking\noptimize: {any}\n{s}", .{ optimize, if (do_release) "doing release\n" else "" });

    const raylib_dep = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
        .shared = false,
        .config = raylib_config,
        .linux_display_backend = linuxDisplayBackend(b),
    });
    const raylib = raylib_dep.artifact("raylib");
    const exe = b.addExecutable(.{
        .name = title,
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    linkOSStuff(b, target, exe, do_release);
    exe.linkLibrary(raylib);
    exe.addIncludePath(b.path("raylib/src"));

    addExeConfig(b, exe.root_module, true, do_release);

    if (target.query.isNative()) {
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }

    var artifacts = std.ArrayList(*std.Build.Step.Compile).init(b.allocator);
    try artifacts.append(exe);

    return try artifacts.toOwnedSlice();
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    const do_release = b.option(bool, "do-release", "build all targets for release") orelse false;
    const static_link = b.option(bool, "static-link", "build statically") orelse false;
    const app_only = b.option(bool, "app-only", "only build the game shared lib - incompatible with static-link and do-release") orelse false;
    if (app_only) {
        std.debug.assert(!do_release);
        std.debug.assert(!static_link);
    }
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const native_target = b.standardTargetOptions(.{});
    const targets: []const std.Build.ResolvedTarget = blk: {
        if (do_release and native_target.result.os.tag == .macos) {
            break :blk &.{
                native_target,
                b.resolveTargetQuery(.{
                    .cpu_arch = .x86_64,
                    .os_tag = .windows,
                    .os_version_min = .{ .windows = .win10 },
                    .os_version_max = .{ .windows = .win11_ge },
                    .abi = .gnu,
                }),
            };
        } else {
            if (do_release) {
                std.debug.print("WARNING: Since we're not on macos, only releasing for native target\n", .{});
            }
            break :blk &.{native_target};
        }
    };

    if (do_release) {
        b.release_mode = .safe;
        //b.release_mode = .off;
    }
    //const optimize = std.builtin.OptimizeMode.Debug;
    const optimize = if (do_release) std.builtin.OptimizeMode.ReleaseSafe else b.standardOptimizeOption(.{});

    for (targets) |target| {
        const target_triple = try target.result.zigTriple(b.allocator);
        defer b.allocator.free(target_triple);
        std.debug.print("Target triple{s}: {s}\n", .{ if (target.query.isNative()) " (native)" else "", target_triple });

        // buildu
        const artifacts = blk: {
            if (static_link) {
                break :blk try buildStatic(b, target, optimize, do_release);
            } else {
                break :blk try buildDynamic(b, target, optimize, app_only, do_release);
            }
        };

        // installu
        if (do_release) {
            const arch = @tagName(target.result.cpu.arch);
            const os = @tagName(target.result.os.tag);
            const install_dir_path = try std.fmt.allocPrint(b.allocator, "release/{s}-{s}/{s}", .{ os, arch, title });
            // NOTE: DONT DO THIS cos the path is needed by build later!
            // defer b.allocator.free(install_dir_path);
            const install_dir = std.Build.InstallDir{ .custom = install_dir_path };
            for (artifacts) |artifact| {
                b.getInstallStep().dependOn(&b.addInstallArtifact(artifact, .{
                    .dest_dir = .{ .override = install_dir },
                }).step);
            }
        } else {
            for (artifacts) |artifact| {
                b.installArtifact(artifact);
            }
        }

        // testsu
        if (target.query.isNative()) {
            const geometry_unit_tests = b.addTest(.{
                .root_source_file = b.path("src/geometry.zig"),
                .target = target,
                .optimize = optimize,
            });

            const run_geometry_unit_tests = b.addRunArtifact(geometry_unit_tests);

            // Similar to creating the run step earlier, this exposes a `test` step to
            // the `zig build --help` menu, providing a way for the user to request
            // running the unit tests.
            const test_step = b.step("test", "Run unit tests");
            //test_step.dependOn(&run_lib_unit_tests.step);
            test_step.dependOn(&run_geometry_unit_tests.step);
        }
    }
}
