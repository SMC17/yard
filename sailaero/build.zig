const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("yard_sailaero", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const polar_exe = b.addExecutable(.{
        .name = "print-polar",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/print_polar.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_polar = b.addRunArtifact(polar_exe);
    const polar_step = b.step("polar", "Print reference speed polars");
    polar_step.dependOn(&run_polar.step);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run sailaero unit tests");
    test_step.dependOn(&run_mod_tests.step);
}
