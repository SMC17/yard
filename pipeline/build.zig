const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("yard_pipeline", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const unit_tests = b.addTest(.{ .root_module = mod });
    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // oceanman-smoke executable: reads a cable JSON path (and an
    // optional landing-point-geo path) from CLI args + emits a LayPlan
    // to stdout. Drives `scripts/oceanman_smoke.sh`.
    const smoke_mod = b.createModule(.{
        .root_source_file = b.path("src/oceanman_smoke_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    smoke_mod.addImport("yard_pipeline", mod);
    const smoke_exe = b.addExecutable(.{
        .name = "oceanman-smoke",
        .root_module = smoke_mod,
    });
    b.installArtifact(smoke_exe);
    const run_smoke = b.addRunArtifact(smoke_exe);
    if (b.args) |args| run_smoke.addArgs(args);
    const smoke_step = b.step("smoke", "Run the oceanman -> LayPlan smoke driver");
    smoke_step.dependOn(&run_smoke.step);
}
