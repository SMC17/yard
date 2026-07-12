const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const arena_mod = b.addModule("yard_arena", .{
        .root_source_file = b.path("../arena/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const mod = b.addModule("yard_historical_conflict", .{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "yard_arena", .module = arena_mod }},
    });

    const exe = b.addExecutable(.{
        .name = "yard-historical-conflict",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "yard_historical_conflict", .module = mod }},
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run a governed 1778 scenario");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{ .root_module = mod });
    const test_step = b.step("test", "Run historical-conflict tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
