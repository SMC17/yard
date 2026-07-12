const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const vulkan_enabled = b.option(bool, "vulkan", "Enable the native Vulkan frame path") orelse false;
    const vulkan_library_path = b.option(
        []const u8,
        "vulkan-library-path",
        "Linux runtime library path for a Nix-linked Zig invoking system Vulkan ICDs",
    ) orelse "/usr/lib:/usr/lib32";

    const options = b.addOptions();
    options.addOption(bool, "vulkan_enabled", vulkan_enabled);

    const viz_mod = b.addModule("yard_viz", .{
        .root_source_file = b.path("../viz/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mod = b.addModule("yard_viz_vulkan", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "yard_viz", .module = viz_mod },
            .{ .name = "build_options", .module = options.createModule() },
        },
    });
    if (vulkan_enabled) {
        mod.link_libc = true;
        mod.linkSystemLibrary("vulkan", .{});
    }

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_tests = b.addRunArtifact(mod_tests);
    if (vulkan_enabled and target.result.os.tag == .linux) {
        // A Nix-linked Zig may coexist with system Vulkan ICDs. The run step
        // needs the conventional library roots in that configuration.
        run_tests.setEnvironmentVariable("LD_LIBRARY_PATH", vulkan_library_path);
    }
    const test_step = b.step("test", "Run viz-vulkan tests");
    test_step.dependOn(&run_tests.step);

    const render_exe = b.addExecutable(.{
        .name = "render-scene",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/render_cli.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "yard_viz_vulkan", .module = mod },
            },
        }),
    });
    const run_render = b.addRunArtifact(render_exe);
    if (b.args) |args| run_render.addArgs(args);
    const render_step = b.step("render-scene", "Render scene JSON to SVG (headless)");
    render_step.dependOn(&run_render.step);

    const frame_exe = b.addExecutable(.{
        .name = "yard-reference-frame",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/frame_cli.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "yard_viz_vulkan", .module = mod },
            },
        }),
    });
    const run_frame = b.addRunArtifact(frame_exe);
    if (vulkan_enabled and target.result.os.tag == .linux) {
        run_frame.setEnvironmentVariable("LD_LIBRARY_PATH", vulkan_library_path);
    }
    if (b.args) |args| run_frame.addArgs(args);
    const frame_step = b.step("render-frame", "Render a deterministic fleet PPM frame");
    frame_step.dependOn(&run_frame.step);

    if (vulkan_enabled) {
        const native_exe = b.addExecutable(.{
            .name = "yard-native-frame",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/native_cli.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "yard_viz_vulkan", .module = mod },
                },
            }),
        });
        native_exe.root_module.link_libc = true;
        native_exe.root_module.linkSystemLibrary("vulkan", .{});
        const run_native = b.addRunArtifact(native_exe);
        if (target.result.os.tag == .linux) {
            run_native.setEnvironmentVariable("LD_LIBRARY_PATH", vulkan_library_path);
        }
        if (b.args) |args| run_native.addArgs(args);
        const native_step = b.step("native-frame", "Probe Vulkan and render a fleet PPM frame");
        native_step.dependOn(&run_native.step);
    }
}
