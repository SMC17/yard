const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const vulkan_enabled = b.option(bool, "vulkan", "Enable Vulkan draw stub module") orelse false;

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

    const mod_tests = b.addTest(.{ .root_module = mod });
    const test_step = b.step("test", "Run viz-vulkan tests");
    test_step.dependOn(&b.addRunArtifact(mod_tests).step);

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
}