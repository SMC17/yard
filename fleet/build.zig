const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const fossen_mod = b.addModule("yard_fossen", .{
        .root_source_file = b.path("../fossen-6dof/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mod = b.addModule("yard_fleet", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "yard_fossen", .module = fossen_mod }},
    });
    const lib = b.addLibrary(.{ .name = "yard_fleet", .root_module = mod });
    b.installArtifact(lib);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run fleet design and formation tests");
    test_step.dependOn(&run_mod_tests.step);
}
