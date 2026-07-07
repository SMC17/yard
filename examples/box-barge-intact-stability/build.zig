const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const hydro_mod = b.addModule("yard_hydro", .{
        .root_source_file = b.path("../../hydro/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const stability_mod = b.addModule("yard_stability", .{
        .root_source_file = b.path("../../stability/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const naval_arch_mod = b.addModule("yard_naval_arch", .{
        .root_source_file = b.path("../../naval-arch/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const compose_mod = b.addModule("yard_compose", .{
        .root_source_file = b.path("../../compose/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "yard_hydro", .module = hydro_mod },
            .{ .name = "yard_stability", .module = stability_mod },
            .{ .name = "yard_naval_arch", .module = naval_arch_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "box-barge-intact-stability",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "yard_compose", .module = compose_mod },
                .{ .name = "yard_naval_arch", .module = naval_arch_mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run canonical box-barge example");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_step.dependOn(&run_cmd.step);

    const mod_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "yard_compose", .module = compose_mod },
                .{ .name = "yard_naval_arch", .module = naval_arch_mod },
            },
        }),
    });
    const test_step = b.step("test", "Run example tests");
    test_step.dependOn(&b.addRunArtifact(mod_tests).step);
}