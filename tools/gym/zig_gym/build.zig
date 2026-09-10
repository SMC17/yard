const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Vendored yard Holtrop HM1984 + ITTC-57 (read-only snippets).
    const yard_resistance = b.createModule(.{
        .root_source_file = b.path("../vendor/yard_zig/resistance/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "yard_resistance", .module = yard_resistance },
        },
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "root.zig", .module = lib_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "yard_sea_zig",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const tests = b.addTest(.{ .root_module = lib_mod });
    const test_step = b.step("test", "Run L0/L1 gym tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run yard_sea_zig CLI");
    run_step.dependOn(&run_cmd.step);
}
