const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("yard_dynpos", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const unit_tests = b.addTest(.{ .root_module = mod });
    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    const publish_module = b.createModule(.{
        .root_source_file = b.path("src/telemetry_publish.zig"),
        .target = target,
        .optimize = optimize,
    });
    publish_module.addImport("yard_dynpos", mod);
    const publish_exe = b.addExecutable(.{
        .name = "yard-dynpos-telemetry-publish",
        .root_module = publish_module,
    });
    const publish_run = b.addRunArtifact(publish_exe);
    if (b.args) |args| publish_run.addArgs(args);
    const publish_step = b.step("telemetry-publish", "Publish versioned DP telemetry to local NATS");
    publish_step.dependOn(&publish_run.step);

    const roundtrip_module = b.createModule(.{
        .root_source_file = b.path("src/telemetry_roundtrip.zig"),
        .target = target,
        .optimize = optimize,
    });
    roundtrip_module.addImport("yard_dynpos", mod);
    const roundtrip_exe = b.addExecutable(.{
        .name = "yard-dynpos-telemetry-roundtrip",
        .root_module = roundtrip_module,
    });
    const roundtrip_run = b.addRunArtifact(roundtrip_exe);
    if (b.args) |args| roundtrip_run.addArgs(args);
    const roundtrip_step = b.step("telemetry-roundtrip", "Verify Zig-to-OTP-to-Zig NATS command flow");
    roundtrip_step.dependOn(&roundtrip_run.step);
}
