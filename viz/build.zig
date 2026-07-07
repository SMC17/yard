const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("yard_viz", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run viz unit tests");
    test_step.dependOn(&run_mod_tests.step);

    const render_exe = b.addExecutable(.{
        .name = "render-gz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/render_cli.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "yard_viz", .module = mod },
            },
        }),
    });
    const run_render = b.addRunArtifact(render_exe);
    if (b.args) |args| run_render.addArgs(args);

    const render_step = b.step("render-gz", "Render GZ curve SVG from JSON input");
    render_step.dependOn(&run_render.step);
}